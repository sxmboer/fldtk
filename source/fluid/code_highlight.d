/**
 * D syntax highlighting for the code-snippet editors and the Code View, in the
 * spirit of real Fluid's `fluid::widget::Code_Editor` (a `TextEditor`
 * whose text buffer drives a parallel style buffer through a lexer). The
 * lexer and its colours are `fl.d_syntax`, shared with
 * `fl.markdown_view.MarkdownView`'s D code blocks; this module re-exports
 * them.
 *
 * `enableHighlighting()` attaches the lexer to a `TextDisplay`,
 * `enableAutoIndent()` gives a `TextEditor` FLTK's Enter behavior (the new
 * line keeps the previous line's indentation), and `renameIdentifier()`
 * renames an identifier in code but not in strings and comments.
 */
module fluid.code_highlight;

import std.array : appender;

import fl;
public import fl.d_syntax;

private bool isIdentStart(char c)
{
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_' || c >= 0x80;
}

private bool isIdentChar(char c)
{
    return isIdentStart(c) || (c >= '0' && c <= '9');
}

/// `code` with every use of the identifier `from` as code renamed to `to`.
/// A `from` inside a string, a character literal or a comment stays as it
/// is (found with `styleParse()`), and so does a member access (`x.from`),
/// which names something else. Used for the widget's own name in `setup`
/// and `finalize` code, which the `.fl` file writes as `o`.
string renameIdentifier(string code, string from, string to)
{
    auto style = new char[code.length];
    styleParse(code, style);
    auto result = appender!string();
    size_t i = 0, copied = 0;
    immutable n = code.length;
    while (i < n)
    {
        if (!isIdentStart(code[i]) || (i > 0 && isIdentChar(code[i - 1])))
        {
            i++;
            continue;
        }
        size_t e = i + 1;
        while (e < n && isIdentChar(code[e])) e++;
        char s = style[i];
        bool inText = s == styleComment || s == styleDocSection || s == styleString
            || s == styleEscape;
        bool member = i > 0 && code[i - 1] == '.' && !(i > 1 && code[i - 2] == '.');
        if (code[i .. e] == from && !inText && !member)
        {
            result ~= code[copied .. i];
            result ~= to;
            copied = e;
        }
        i = e;
    }
    result ~= code[copied .. $];
    return result[];
}

unittest
{
    assert(renameIdentifier("o.label(\"o\"); // o\nfoo(o, x.o);", "o", "btn")
        == "btn.label(\"o\"); // o\nfoo(btn, x.o);");
    assert(renameIdentifier("o.tooltip(`press o`); auto c = 'o'; /* o */ /+ o +/", "o", "b")
        == "b.tooltip(`press o`); auto c = 'o'; /* o */ /+ o +/");
    assert(renameIdentifier("a[0..o] ~ oo ~ o2 ~ _o", "o", "b") == "a[0..b] ~ oo ~ o2 ~ _o");
    assert(renameIdentifier("btn.label(\"btn\"); btnX = btn;", "btn", "o")
        == "o.label(\"btn\"); btnX = o;");
    assert(renameIdentifier("this.redraw(); foo(this);", "this", "o") == "o.redraw(); foo(o);");
}

/// Makes `display` highlight its text as D. `display` must already have its
/// text buffer (`buffer()`), which stays the one highlighted; the style buffer
/// follows every change to it. Like FLTK's `Code_Editor`, the whole
/// buffer is restyled on each change.
void enableHighlighting(TextDisplay display)
{
    auto textBuf = display.buffer();
    auto styleBuf = new TextBuffer();

    void restyle()
    {
        string text = textBuf.text();
        auto style = new char[text.length];
        styleParse(text, style);
        styleBuf.text(cast(string) style);
    }
    restyle();
    display.highlightData(styleBuf, styleTable(display.textsize()), stylePlain, null);

    textBuf.addModifyCallback((pos, nInserted, nDeleted, nRestyled, deletedText) {
        // A selection change only: nothing to restyle.
        if (nInserted == 0 && nDeleted == 0)
        {
            styleBuf.unselect();
            return;
        }
        // Keep the style buffer the same length as the text, then reparse it all.
        if (nInserted > 0)
        {
            auto filler = new char[nInserted];
            filler[] = stylePlain;
            styleBuf.replace(pos, pos + nDeleted, cast(string) filler);
        }
        else
            styleBuf.remove(pos, pos + nDeleted);
        styleBuf.select(pos, pos + nInserted - nDeleted);

        int len = textBuf.length();
        string text = textBuf.textRange(0, len);
        auto style = new char[len];
        styleParse(text, style);
        styleBuf.replace(0, len, cast(string) style);
        display.redisplayRange(0, len);
        display.redraw();
    });
}

/// Enter keeps the indentation of the current line, FLTK's
/// `Code_Editor::auto_indent()`.
private int autoIndent(int, TextEditor e)
{
    if (e.buffer().selected())
    {
        e.insertPosition(e.buffer().primarySelection().start());
        e.buffer().removeSelection();
    }
    int pos = e.insertPosition();
    int start = e.lineStart(pos);
    string line = e.buffer().textRange(start, pos);
    size_t indent = 0;
    while (indent < line.length && (line[indent] == ' ' || line[indent] == '\t'))
        indent++;
    // One insert call for the newline and the indentation, to avoid redraw issues.
    e.insert("\n" ~ line[0 .. indent]);
    e.showInsertPosition();
    e.setChanged();
    if (e.when() & whenChanged)
        e.doCallback(CallbackReason.changed);
    return 1;
}

/// Makes Enter in `editor` keep the current line's indentation.
void enableAutoIndent(TextEditor editor)
{
    editor.addKeyBinding(enter, textEditorAnyState, &autoIndent);
}

unittest
{
    // The style buffer follows the text buffer through inserts and deletes.
    auto editor = new TextEditor(0, 0, 200, 100);
    editor.buffer(new TextBuffer());
    enableHighlighting(editor);
    auto text = editor.buffer();
    auto style = editor.styleBuffer();
    assert(style !is null && style.length() == 0);

    text.text("int x = null;");
    assert(style.text() == "BBBAAALADDDDJ");
    text.insert(0, "if (");
    assert(style.length() == text.length());
    assert(style.text()[0 .. 6] == "BBAIBB");   // "if (in"
    text.remove(0, 4);
    assert(style.text() == "BBBAAALADDDDJ");
    text.text("");
    assert(style.length() == 0);
    text.text("// c\nx");
    assert(style.text() == "FFFFAA");
}

unittest
{
    // Enter keeps the current line's indentation; a selection is replaced.
    auto editor = new TextEditor(0, 0, 200, 100);
    editor.buffer(new TextBuffer());
    enableAutoIndent(editor);
    editor.buffer().text("    if (x)");
    editor.insertPosition(editor.buffer().length());
    assert(autoIndent(0, editor) == 1);
    assert(editor.buffer().text() == "    if (x)\n    ");

    editor.buffer().text("\tfoo bar");
    editor.buffer().select(5, 8);
    editor.insertPosition(8);
    autoIndent(0, editor);
    // The selected "bar" is replaced by the new line and its indentation.
    assert(editor.buffer().text() == "\tfoo \n\t");
}
