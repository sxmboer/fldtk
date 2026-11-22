/*
 * Compiler messages in the Run window: a double-click on a line such as
 * `source/hello.d(12,5): Error: ...` selects the node that wrote that
 * line of the generated code (`gui_main.d`'s `showCompilerMessage()`).
 *
 * - `parseCompilerMessage()` reads the file, line, column and text of a
 *   message line: dmd's and ldc's `file.d(line,col):` and gdc's
 *   `file.d:line:col:`; `parseCompilerMessages()` reads every message of
 *   a build's output, taking a missing column from dmd's `^` line.
 * - `lineOffset()` turns a line and column into a position in the
 *   generated text, and `nodeAt()` finds the node whose code holds that
 *   position (`Node.setupSpan`/`finalizeSpan`).
 * - `RunTerminal` is the Run window's terminal: a `Terminal` that hands a
 *   double-clicked line to `onLineDoubleClick`.
 */
module fluid.compiler_errors;

import fl;
import fluid.node : Node, TextSpan;

/// Where a compiler message points: a file, a line (1-based) and a
/// column (1-based, 0 when the message gives none), whether it is an
/// error (not a warning, a deprecation or a follow-up line such as
/// `instantiated from here`), and the message as the compiler wrote it,
/// after the place (`Error: undefined identifier `x``).
struct CompilerMessage
{
    string file;
    int line;
    int column;
    bool error;
    string text;
}

/// Reads the place a compiler message line points at: dmd and ldc write
/// `file.d(12,5): Error: ...` (also `Warning:`, `Deprecation:` and the
/// indented follow-up lines, such as `instantiated from here`), gdc
/// writes `file.d:12:5: error: ...`, and so do dmd and ldc with
/// `-verror-style=gnu` (`file.d:12:5: Error: ...`). The column is there
/// with dmd's `-vcolumns`, which dub passes, and always with gdc. Only `.d` and `.di` files count, so
/// a linker or dub line isn't taken for one. Returns false for any other
/// line.
/// Whether the text after a message's position starts an error:
/// `Error:` (dmd, ldc) or `error:` (gdc).
private bool isError(string rest)
{
    import std.algorithm : startsWith;
    return rest.startsWith("Error:") || rest.startsWith("error:");
}

bool parseCompilerMessage(string text, out CompilerMessage m)
{
    import std.regex : matchFirst, ctRegex;
    import std.conv : to;
    import std.string : strip, stripLeft;

    string s = text.stripLeft;
    auto dmd = s.matchFirst(ctRegex!`^(.+?\.di?)\((\d+)(?:,(\d+))?\): `);
    if (!dmd.empty)
    {
        m = CompilerMessage(dmd[1], dmd[2].to!int, dmd[3].length ? dmd[3].to!int : 0,
            isError(dmd.post), dmd.post.strip);
        return true;
    }
    auto gdc = s.matchFirst(ctRegex!`^(.+?\.di?):(\d+):(?:(\d+):)? `);
    if (!gdc.empty)
    {
        m = CompilerMessage(gdc[1], gdc[2].to!int, gdc[3].length ? gdc[3].to!int : 0,
            isError(gdc.post), gdc.post.strip);
        return true;
    }
    return false;
}

unittest
{
    CompilerMessage m;
    assert(parseCompilerMessage("source/hello.d(12,5): Error: undefined identifier `x`", m));
    assert(m == CompilerMessage("source/hello.d", 12, 5, true, "Error: undefined identifier `x`"));
    assert(parseCompilerMessage("hello.d(7): Deprecation: something", m));
    assert(m == CompilerMessage("hello.d", 7, 0, false, "Deprecation: something"));
    assert(parseCompilerMessage("  C:\\proj\\source\\app.d(3,1):        instantiated from here", m));
    assert(m == CompilerMessage("C:\\proj\\source\\app.d", 3, 1, false, "instantiated from here"));
    assert(parseCompilerMessage("hello.d:12:5: error: undefined identifier 'x'", m));
    assert(m == CompilerMessage("hello.d", 12, 5, true, "error: undefined identifier 'x'"));
    assert(parseCompilerMessage("e.d:3:13: Error: undefined identifier `x`", m));
    assert(m == CompilerMessage("e.d", 3, 13, true, "Error: undefined identifier `x`"));
    assert(parseCompilerMessage("e.d:3: Error: undefined identifier `x`", m));
    assert(m == CompilerMessage("e.d", 3, 0, true, "Error: undefined identifier `x`"));
    assert(!parseCompilerMessage("    3 |     int x = undefinedThing;", m));
    assert(!parseCompilerMessage("      |             ^", m));
    assert(parseCompilerMessage("pkg/mod.di:4: warning: w", m));
    assert(m == CompilerMessage("pkg/mod.di", 4, 0, false, "warning: w"));
    assert(!parseCompilerMessage("Error /usr/bin/dmd failed with exit code 1.", m));
    assert(!parseCompilerMessage("    Building hello ~master: building configuration [application]", m));
    assert(!parseCompilerMessage("/usr/bin/ld: hello.o: undefined reference", m));
}

/// Every compiler message in `output`, a build's output, in order. A
/// message without a column (dmd without `-vcolumns`) takes it from the
/// `^` dmd prints under the source line that follows the message.
CompilerMessage[] parseCompilerMessages(string output)
{
    import std.array : array;
    import std.string : indexOf, lineSplitter, strip;

    string[] lines = output.lineSplitter.array;
    CompilerMessage[] result;
    foreach (i, line; lines)
    {
        CompilerMessage m, next;
        if (!parseCompilerMessage(line, m)) continue;
        if (m.column == 0 && i + 2 < lines.length && lines[i + 2].strip == "^"
            && !parseCompilerMessage(lines[i + 1], next))
            m.column = cast(int) lines[i + 2].indexOf('^') + 1;
        result ~= m;
    }
    return result;
}

unittest
{
    string dmd = "e.d(3): Error: undefined identifier `undefinedThing`\n"
        ~ "    int x = undefinedThing;\n"
        ~ "            ^\n"
        ~ "e.d(4): Error: undefined identifier `undefinedThing`\n"
        ~ "    undefinedThing++;\n"
        ~ "    ^\n"
        ~ "e.d(9): Deprecation: no context lines\n"
        ~ "e.d(10,2): Error: has a column\n"
        ~ "    x;\n"
        ~ "        ^\n";
    auto ms = parseCompilerMessages(dmd);
    assert(ms.length == 4);
    assert(ms[0] == CompilerMessage("e.d", 3, 13, true, "Error: undefined identifier `undefinedThing`"));
    assert(ms[1] == CompilerMessage("e.d", 4, 5, true, "Error: undefined identifier `undefinedThing`"));
    assert(ms[2] == CompilerMessage("e.d", 9, 0, false, "Deprecation: no context lines"));
    assert(ms[3] == CompilerMessage("e.d", 10, 2, true, "Error: has a column")); // its own column wins

    // gdc: always a column; its context lines are no messages.
    ms = parseCompilerMessages("e.d:3:13: error: x\n    3 |     int x = y;\n      |             ^\n");
    assert(ms == [CompilerMessage("e.d", 3, 13, true, "error: x")]);
}

/// The position in `text` of line `line` (1-based), column `column`
/// (1-based; 0 is the line's start), kept within that line; -1 when the
/// text has fewer lines.
int lineOffset(string text, int line, int column)
{
    if (line < 1) return -1;
    size_t start = 0;
    foreach (_; 1 .. line)
    {
        import std.string : indexOf;
        auto nl = text.indexOf('\n', start);
        if (nl < 0) return -1;
        start = nl + 1;
    }
    if (start > text.length) return -1;
    size_t end = start;
    while (end < text.length && text[end] != '\n') end++;
    size_t pos = start + (column > 1 ? column - 1 : 0);
    return cast(int) (pos < end ? pos : end);
}

unittest
{
    string t = "ab\ncdef\n\ngh";
    assert(lineOffset(t, 1, 0) == 0);
    assert(lineOffset(t, 2, 3) == 5);
    assert(lineOffset(t, 2, 99) == 7);
    assert(lineOffset(t, 3, 1) == 8);
    assert(lineOffset(t, 4, 2) == 10);
    assert(lineOffset(t, 5, 1) == -1);
    assert(lineOffset(t, 0, 1) == -1);
}

/// The node in `roots` or below whose own code (`setupSpan` or
/// `finalizeSpan`) holds position `pos` of the generated text; the
/// innermost one when spans nest, null when none does (the imports, or
/// the module-level variables of named widgets).
Node nodeAt(Node[] roots, int pos)
{
    static bool holds(TextSpan s, int p) => s.start >= 0 && p >= s.start && p < s.end;
    Node found;
    void walk(Node[] nodes)
    {
        foreach (n; nodes)
        {
            if (holds(n.setupSpan, pos) || holds(n.finalizeSpan, pos))
                found = n;
            walk(n.children);
        }
    }
    walk(roots);
    return found;
}

unittest
{
    import fluid.code_node : CodeNode;
    import fluid.function_node : FunctionNode;

    auto fn = new FunctionNode();
    fn.setupSpan = TextSpan(0, 10);
    fn.finalizeSpan = TextSpan(30, 32);
    auto code = new CodeNode();
    code.setupSpan = TextSpan(10, 20);
    code.finalizeSpan = TextSpan(20, 20);
    fn.addChild(code);
    assert(nodeAt([cast(Node) fn], 5) is fn);
    assert(nodeAt([cast(Node) fn], 15) is code);
    assert(nodeAt([cast(Node) fn], 31) is fn);
    assert(nodeAt([cast(Node) fn], 25) is null);
    assert(nodeAt([cast(Node) fn], 40) is null);
}

/// The Run window's terminal: a `Terminal` that also hands the line the
/// user double-clicks to `onLineDoubleClick`. The double-click still
/// selects the word under the mouse, as in any terminal.
class RunTerminal : Terminal
{
    /// Called with the text of a double-clicked line.
    void delegate(string line) onLineDoubleClick;

    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
    }

    override int handle(Event e)
    {
        int ret = super.handle(e);
        // `eventClicks()` counts the clicks after the first: 1 is a
        // double-click.
        if (e == Event.push && fl.core.eventButton() == leftMouse && fl.core.eventClicks() == 1
            && onLineDoubleClick !is null)
        {
            string line = lineAt(fl.core.eventY());
            if (line.length)
                onLineDoubleClick(line);
            return 1;
        }
        return ret;
    }
}

unittest
{
    // A message about a line of a callback leads to its widget, through
    // the spans of a real generate().
    import std.algorithm : countUntil;
    import std.format : format;
    import std.string : lineSplitter;
    import fluid.code_writer : Writer;
    import fluid.function_node : FunctionNode;
    import fluid.widget_node : WidgetNode;
    import fluid.window_node : WindowNode;

    auto fn = new FunctionNode();
    fn.typeName = "Function";
    auto win = new WindowNode();
    win.typeName = "Window";
    win.instanceName = "win";
    win.w = 100; win.h = 100; win.hasXywh = true;
    auto btn = new WidgetNode();
    btn.typeName = "Button";
    btn.instanceName = "btn";
    btn.w = 50; btn.h = 20; btn.hasXywh = true;
    btn.callback = "undefinedThing++;";
    fn.addChild(win);
    win.addChild(btn);

    string text = new Writer().generate([cast(Node) fn]);
    int lineOf(string what)
    {
        int i = 1;
        foreach (l; text.lineSplitter)
        {
            if (l.countUntil(what) >= 0) return i;
            i++;
        }
        assert(0, what);
    }

    CompilerMessage m;
    assert(parseCompilerMessage(format("bad.d(%d,17): Error: undefined identifier `undefinedThing`",
        lineOf("undefinedThing++")), m));
    assert(nodeAt([cast(Node) fn], lineOffset(text, m.line, m.column)) is btn);
    assert(parseCompilerMessage(format("bad.d(%d,25): Error: none of the overloads", lineOf("btn.callback(")), m));
    assert(nodeAt([cast(Node) fn], lineOffset(text, m.line, m.column)) is btn);
    assert(parseCompilerMessage(format("bad.d(%d,9): Error: x", lineOf("win.end()")), m));
    assert(nodeAt([cast(Node) fn], lineOffset(text, m.line, m.column)) is win);
}
