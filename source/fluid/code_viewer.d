// Ported from `fluid/widgets/Code_Viewer.h`/`.cxx` -- the read-only view
// behind the Code View window's Source and Project tabs
// (`fluid/panels/codeview_panel.fl`, via a `class {CodeViewer}` override).
//
// The node highlight has to stand out against the syntax-colored text:
// the text area is drawn in a light gray and the highlighted code in the
// display's own color (white by default), so the highlighted part is the
// brightest. The gray is 60% the display's color and 40% a mix of 90%
// background and 10% foreground color. Worked out at draw time,
// not once at construction, so it follows a later scheme/background
// change.
//
// Not ported: `Code_Viewer`'s constructor's key-binding removal
// (`default_key_function(kf_ignore)`, `remove_all_key_bindings()`,
// `cursor_style(CARET_CURSOR)`): those belong to `Fl_Text_Editor`, and
// this port's Code View uses plain `TextDisplay`s, which have no key bindings.
module fluid.code_viewer;

import fl;

/// A `TextDisplay` drawn on a soft gray, with highlighted text in the
/// display's own color.
class CodeViewer : TextDisplay
{
    private Color highlight_ = background2Color;

    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
    }

    override void draw()
    {
        const own = color();
        highlight_ = own;
        color(colorAverage(own, colorAverage(backgroundColor, foregroundColor, 0.9f), 0.6f));
        scope (exit) color(own);
        super.draw();
    }

    /// Highlighted text is drawn on the display's own color, except text
    /// whose style has a background of its own (a compiler message line,
    /// `fl.d_syntax.styleMessage`), which keeps it.
    protected override Color highlightBackground(Color base, bool focused)
    {
        return base == color() ? highlight_ : base;
    }

    // ---- Compiler messages ----
    //
    // Shown inline, the messages are lines of the buffer, inserted after
    // the code line each is about. The code itself stays in `code_`, and
    // `toView()`/`toCode()` and `viewLine()`/`codeLine()` translate
    // between positions and lines of the code and of the view. Each
    // insertion is at a code position (`insAt_`, ascending), with its
    // length, its number of lines, and the code line it follows.

    private string code_;            // the code; null when the buffer's text is the code
    private int[] insAt_;
    private int[] insLen_;
    private int[] insLines_;
    private int[] insAfter_;
    private string[][int] errorLines_;
    private bool errorTooltips_ = true;

    /// Shows `text` as the code, without any compiler messages; the next
    /// `markErrors()` marks the errors in it.
    void code(string text)
    {
        code_ = text;
        insAt_ = insLen_ = insLines_ = insAfter_ = null;
        errorLines_ = null;
        buffer().text(text);
    }

    /// The code shown, without the compiler messages shown among it.
    string code()
    {
        return code_ !is null ? code_ : buffer().text();
    }

    /// The position in the view of position `pos` of the code.
    int toView(int pos)
    {
        if (pos < 0) return pos;
        int v = pos;
        foreach (i, at; insAt_)
        {
            if (at > pos) break;
            v += insLen_[i];
        }
        return v;
    }

    /// The position in the code of position `pos` of the view; on a
    /// message line, the end of the code line the message is about.
    int toCode(int pos)
    {
        if (pos < 0) return pos;
        int shift = 0;
        foreach (i, at; insAt_)
        {
            int start = at + shift;
            if (pos < start) break;
            if (pos < start + insLen_[i]) return at > 0 ? at - 1 : 0;
            shift += insLen_[i];
        }
        return pos - shift;
    }

    /// The line in the view (counted from 1) of line `line` of the code.
    int viewLine(int line)
    {
        int v = line;
        foreach (i, after; insAfter_)
        {
            if (after >= line) break;
            v += insLines_[i];
        }
        return v;
    }

    /// The line in the code (counted from 1) of line `line` of the view;
    /// 0 for a message line.
    int codeLine(int line)
    {
        int shift = 0;
        foreach (i, after; insAfter_)
        {
            int first = after + shift + 1;
            if (line < first) break;
            if (line < first + insLines_[i]) return 0;
            shift += insLines_[i];
        }
        return line - shift;
    }

    /// Marks the places a compiler reports, one `ErrorMark` for each
    /// message, with positions and lines of the code (`code()`): the line
    /// gets a red line number, and the text from `start` to `end`, when
    /// given, is drawn red and underlined (`fl.d_syntax.styleError`).
    /// With `tooltips`, the mouse on a marked line, its line number or its
    /// text, shows the messages about that line in a tooltip. With
    /// `inline`, the messages are also shown among the code, each on a
    /// line of its own under the line it is about, dark red on light red
    /// (`fl.d_syntax.styleMessage`), without a line number of their own.
    /// Both show the messages as the compiler wrote them, each once.
    /// Replaces the marks of an earlier call; with no marks it removes
    /// them. Putting message lines in or taking them out keeps the top
    /// line, the node highlight and the cursor where they were in the
    /// code. The text marks and the colours of the message lines are in
    /// the style buffer of a highlighted view; a view without
    /// highlighting gets the line numbers, the message lines and the
    /// tooltips only.
    void markErrors(const(ErrorMark)[] marks, bool tooltips = true, bool inline = false)
    {
        import fl.d_syntax : styleParse, styleError, styleMessage;
        import fluid.compiler_errors : lineOffset;
        import std.algorithm : canFind, sort;
        import std.array : appender;

        if (buffer() is null) return;
        errorTooltips_ = tooltips;
        errorLines_ = null;
        foreach (m; marks)
        {
            auto list = m.line in errorLines_;
            if (list is null)
                errorLines_[m.line] = m.message.length ? [m.message] : [];
            else if (m.message.length && !(*list).canFind(m.message))
                *list ~= m.message;
        }

        // The view's text: the code, with each marked line's messages
        // under it when they are shown inline.
        string src = code();
        int[] at, len, lines, after;
        auto view = appender!string();
        size_t copied = 0;
        if (inline)
        {
            auto marked = errorLines_.keys;
            sort(marked);
            foreach (l; marked)
            {
                auto messages = errorLines_[l];
                int lineStart = lineOffset(src, l, 0);
                if (messages.length == 0 || lineStart < 0) continue;
                size_t lineEnd = lineStart;
                while (lineEnd < src.length && src[lineEnd] != '\n') lineEnd++;
                size_t indentEnd = lineStart;
                while (indentEnd < lineEnd && (src[indentEnd] == ' ' || src[indentEnd] == '\t')) indentEnd++;
                string indent = src[lineStart .. indentEnd];
                auto block = appender!string();
                size_t pos = lineEnd < src.length ? lineEnd + 1 : lineEnd;
                if (lineEnd == src.length) block ~= "\n";
                foreach (message; messages)
                    block ~= indent ~ message ~ "\n";
                view ~= src[copied .. pos];
                view ~= block[];
                copied = pos;
                at ~= cast(int) pos;
                len ~= cast(int) block[].length;
                lines ~= cast(int) messages.length;
                after ~= l;
            }
        }
        view ~= src[copied .. $];
        string text = view[];

        if (text != buffer().text())
        {
            int top = scrollRow();
            while (top > 1 && codeLine(top) == 0) top--;
            top = codeLine(top);
            int hs, he;
            bool highlighted = buffer().highlightPosition(hs, he);
            hs = toCode(hs);
            he = toCode(he);
            int cursor = toCode(insertPosition());
            int col = scrollCol();

            code_ = src;
            insAt_ = at; insLen_ = len; insLines_ = lines; insAfter_ = after;
            buffer().text(text);
            if (highlighted) buffer().highlight(toView(hs), toView(he));
            insertPosition(toView(cursor));
            scroll(viewLine(top), col);
        }
        else
        {
            code_ = src;
            insAt_ = at; insLen_ = len; insLines_ = lines; insAfter_ = after;
        }

        auto styles = styleBuffer();
        if (styles !is null)
        {
            auto codeStyle = new char[src.length];
            styleParse(src, codeStyle);
            foreach (m; marks)
            {
                int s = m.start < 0 ? 0 : m.start;
                int e = m.end > cast(int) codeStyle.length ? cast(int) codeStyle.length : m.end;
                if (s < e)
                    codeStyle[s .. e] = styleError;
            }
            auto style = new char[text.length];
            size_t c = 0, v = 0;
            foreach (i, p; insAt_)
            {
                style[v .. v + (p - c)] = codeStyle[c .. p];
                v += p - c;
                style[v .. v + insLen_[i]] = styleMessage;
                v += insLen_[i];
                c = p;
            }
            style[v .. $] = codeStyle[c .. $];
            styles.replace(0, styles.length(), cast(string) style);
            redisplayRange(0, cast(int) text.length);
        }
        redraw();
    }

    protected override Color linenumberColor(int line)
    {
        return codeLine(line) in errorLines_ ? rgbColor(0xe0, 0x00, 0x00) : super.linenumberColor(line);
    }

    protected override string linenumberText(int line)
    {
        int c = codeLine(line);
        return c == 0 ? "" : super.linenumberText(c);
    }

    override int handle(Event event)
    {
        if ((event == Event.move || event == Event.enter) && errorTooltips_ && errorLines_.length)
            errorTip();
        return super.handle(event);
    }

    /// The messages about the code line at `y` in the window (its text or
    /// its line number), one per line; null on any other line, a message
    /// line included. `lineY` and `lineH` give that line's place in the
    /// widget.
    string errorsAt(int y, out int lineY, out int lineH)
    {
        static import fl.draw;
        import std.array : join;

        if (buffer() is null || errorLines_.length == 0) return null;
        lineH = fl.draw.height(textfont(), textsize());
        int start = buffer().lineStart(xyToPosition(x(), y));
        int X, Y;
        if (!positionToXy(start, X, Y) || y < Y || y >= Y + lineH) return null;
        auto list = codeLine(buffer().countLines(0, start) + 1) in errorLines_;
        if (list is null) return null;
        lineY = Y - this.y();
        return (*list).join("\n");
    }

    /// Shows the messages about the line under the mouse in a tooltip;
    /// on other lines, the widget's own tooltip, if it has one.
    private void errorTip()
    {
        static import fl.tooltip;
        int lineY, lineH;
        string tip = errorsAt(fl.core.eventY(), lineY, lineH);
        if (tip.length)
            fl.tooltip.enterArea(this, 0, lineY, w(), lineH, tip);
        else
            fl.tooltip.enterArea(this, 0, 0, w(), h(), tooltip());
    }
}

/// One compiler message for `CodeViewer.markErrors()`: the line it is
/// about (counted from 1), the text it points at (`start` to `end`, or
/// -1 for none), and the message.
struct ErrorMark
{
    int line;
    int start = -1;
    int end = -1;
    string message;
}

unittest
{
    // Marked lines get a red number; a marked range the error style,
    // which the next call replaces by the text's own styles again.
    import fl.d_syntax : styleError;
    import fluid.code_highlight : enableHighlighting;

    FlGroup.current(null);
    auto v = new CodeViewer(0, 0, 200, 100);
    FlGroup.current(null);
    v.buffer(new TextBuffer());
    v.buffer().text("int a;\nfoo(b);\n");
    enableHighlighting(v);

    v.markErrors([ErrorMark(2, 7, 10, "Error: undefined identifier `foo`"),
        ErrorMark(2, 10, 11, "Error: none of the overloads"),
        ErrorMark(2, 7, 10, "Error: undefined identifier `foo`")]);
    assert(v.linenumberColor(2) == rgbColor(0xe0, 0x00, 0x00));
    assert(v.linenumberColor(1) == v.linenumberFgcolor());
    assert(v.styleBuffer().textRange(7, 11) == [styleError, styleError, styleError, styleError]);
    assert(v.styleBuffer().byteAt(11) != styleError);
    // A line's messages, each once, in the order the compiler gave them.
    assert(v.errorLines_[2] == ["Error: undefined identifier `foo`", "Error: none of the overloads"]);

    // A message without a column marks the line only.
    v.markErrors([ErrorMark(1, -1, -1, "Deprecation: d")]);
    assert(v.linenumberColor(1) == rgbColor(0xe0, 0x00, 0x00));
    assert(v.linenumberColor(2) == v.linenumberFgcolor());
    assert(v.styleBuffer().byteAt(7) != styleError);

    v.markErrors(null);
    assert(v.linenumberColor(1) == v.linenumberFgcolor());
    assert(v.errorLines_.length == 0);
    int lineY, lineH;
    assert(v.errorsAt(0, lineY, lineH) is null);
}

unittest
{
    // Inline messages: lines of the view under the code line, with their
    // own style and no line number; positions and lines translate both
    // ways, and taking them out gives the code back.
    import fl.d_syntax : styleError, styleMessage;
    import fluid.code_highlight : enableHighlighting;

    FlGroup.current(null);
    auto v = new CodeViewer(0, 0, 200, 100);
    FlGroup.current(null);
    v.buffer(new TextBuffer());
    enableHighlighting(v);
    v.code("void f()\n{\n    foo();\n}\n");
    // "    foo();" is line 3, at 11; foo at 15 .. 18; line 4 starts at 22.
    v.markErrors([ErrorMark(3, 15, 18, "Error: undefined identifier `foo`")], true, true);
    enum msg = "    Error: undefined identifier `foo`\n";
    assert(v.buffer().text() == "void f()\n{\n    foo();\n" ~ msg ~ "}\n");
    assert(v.code() == "void f()\n{\n    foo();\n}\n");
    assert(v.styleBuffer().textRange(15, 18) == [styleError, styleError, styleError]);
    assert(v.styleBuffer().byteAt(22) == styleMessage);
    assert(v.styleBuffer().byteAt(22 + cast(int) msg.length - 1) == styleMessage);
    assert(v.styleBuffer().byteAt(22 + cast(int) msg.length) != styleMessage);

    assert(v.toView(15) == 15 && v.toView(22) == 22 + msg.length);
    assert(v.toCode(22 + cast(int) msg.length) == 22);
    assert(v.toCode(25) == 21); // on the message line: the end of line 3
    assert(v.viewLine(3) == 3 && v.viewLine(4) == 5);
    assert(v.codeLine(4) == 0 && v.codeLine(5) == 4);
    import std.format : format;
    assert(v.linenumberText(4) == "");
    assert(v.linenumberText(5) == format(v.linenumberFormat(), 4));
    assert(v.linenumberColor(3) == rgbColor(0xe0, 0x00, 0x00));
    assert(v.linenumberColor(4) == v.linenumberFgcolor());

    // Without inline: the code alone, the marks stay.
    v.markErrors([ErrorMark(3, 15, 18, "Error: undefined identifier `foo`")], true, false);
    assert(v.buffer().text() == "void f()\n{\n    foo();\n}\n");
    assert(v.styleBuffer().textRange(15, 18) == [styleError, styleError, styleError]);
    assert(v.toView(22) == 22 && v.codeLine(4) == 4);

    // New code clears the marks.
    v.markErrors([ErrorMark(3, 15, 18, "Error: x")], true, true);
    v.code("int a;\n");
    assert(v.buffer().text() == "int a;\n" && v.linenumberColor(1) == v.linenumberFgcolor());
}
