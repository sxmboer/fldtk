// A Markdown editor: the Markdown text on the left, the formatted page
// on the right, following the text as you type and scroll.
// Build: rdmd buildsamples.d test markdown_editor
// Run:   build/markdown_editor [file.md]
//
// The two panes sit in a Tile, so the border between them can be
// dragged. The page is made again a moment after the typing stops (a
// timer that every change restarts), and the two scroll together: what
// the line at the editor's top shows is at the page's top, and scrolling
// the page (or clicking a link to a heading) scrolls the editor to match. Images and links in the page are found from
// the file's folder. A click on a link to another .md file opens that
// file in the editor; other links open as in a MarkdownView.
//
// The Format menu writes the markup for every element the page shows:
//
//   Ctrl+B  bold (**text**)           Ctrl+1 .. Ctrl+6  heading 1 to 6
//   Ctrl+I  italic (*text*)           Ctrl+0            normal text
//   Ctrl+Shift+X  strikethrough       Ctrl+Shift+U      bullet list
//   Ctrl+E  code (`text`)             Ctrl+Shift+O      numbered list
//   Ctrl+K  link ([text](url))        Ctrl+Shift+Q      quote
//   Ctrl+Shift+I  image               Ctrl+Shift+K      code block (D)
//   Ctrl+T  table                     Format > Rule     a rule
//
// The marks for text (bold, italic, strikethrough, code) go around the
// selection; pressed again on marked text they come off, and with nothing
// selected they insert the pair of marks with the cursor between them.
// The ones for lines (headings, lists, quote, code block) change every
// line the selection is on, or the cursor's line, and pressed again they
// take the markup off. Link and image select "url" to type over; a table
// and a rule go on lines of their own after the cursor's line. Each is one
// step to undo.
import fl;
import std.algorithm : endsWith, startsWith;
import std.path : baseName, dirName, extension;
import std.string : toLower;

enum string appName = "Markdown Editor";

// The editor, telling which part of the text is in view.
class Editor : TextEditor
{
    this(int x, int y, int w, int h) { super(x, y, w, h); }

    /// The text position at the top of the view.
    int topPosition() => xyToPosition(x() + 5, y() + 5);
}

DoubleWindow win;
Editor editor;
TextBuffer textBuf;
MarkdownView preview;
string fileName;   // the file being edited, or null for a new text
bool modified;
// The editor's first visible position at the last scroll sync; -1 makes
// the next sync move the page, followedPage makes it take the editor's top
// as it is.
int lastTop = -1;
enum int followedPage = -2;
bool movingPage;   // set while the editor moves the page, which then doesn't move the editor

TimeoutHandler refreshTimer;
TimeoutHandler scrollTimer;

enum string welcome = "# Welcome\n\n"
    ~ "Type **Markdown** on the left and see it *formatted* on the right. "
    ~ "The Format menu writes the markup for you:\n\n"
    ~ "| Keys | Writes | Keys | Writes |\n|---|---|---|---|\n"
    ~ "| Ctrl+B | **bold** | Ctrl+1 to 6 | a heading |\n"
    ~ "| Ctrl+I | *italic* | Ctrl+0 | normal text |\n"
    ~ "| Ctrl+Shift+X | ~~strikethrough~~ | Ctrl+Shift+U | a bullet list |\n"
    ~ "| Ctrl+E | `code` | Ctrl+Shift+O | a numbered list |\n"
    ~ "| Ctrl+K | a [link](https://dlang.org) | Ctrl+Shift+Q | a quote |\n"
    ~ "| Ctrl+Shift+I | an image | Ctrl+Shift+K | a D code block |\n"
    ~ "| Ctrl+T | a table | | |\n\n"
    ~ "Select text first to format it, or press the keys and type.\n\n"
    ~ "> A quote, and below it a code block.\n\n"
    ~ "```D\nimport fl;\n\nvoid main()\n{\n    auto w = new Window(300, 200, \"Hello\");\n    w.show();\n    fl.run();\n}\n```\n";

// ---- The title and the modified flag -----------------------------------

void updateTitle()
{
    string name = fileName.length ? baseName(fileName) : "Untitled";
    win.copyLabel(name ~ (modified ? " *" : "") ~ " - " ~ appName);
}

void setModified(bool m)
{
    if (m == modified) return;
    modified = m;
    updateTitle();
}

// ---- Keeping the page in step with the text ----------------------------

// Shows the text formatted, at the scroll position the page had.
void refresh()
{
    movingPage = true;
    scope (exit) movingPage = false;
    int top = preview.topline();
    preview.value(textBuf.text(), fileName.length ? dirName(fileName) : null);
    preview.topline(top);
    lastTop = -1; // scroll the page to the text again
    syncScroll();
}

// Scrolls the page so that the source line at the editor's top is at the
// page's top (MarkdownView.scrollToSourceLine()).
void syncScroll()
{
    int top = editor.topPosition();
    if (top == lastTop) return;
    bool followed = lastTop == followedPage;
    lastTop = top;
    if (followed) return; // the editor just followed the page
    movingPage = true;
    scope (exit) movingPage = false;
    preview.scrollToSourceLine(textBuf.countLines(0, top));
}

// The other way: when the page is scrolled (or a link to a heading is
// clicked), the editor scrolls so that the source line at the page's top
// is at its own top. The cursor stays where it is.
void followPage()
{
    if (movingPage) return;
    int pos = textBuf.skipLines(0, preview.topSourceLine());
    // scroll() counts the lines on screen, from 1, wrapped ones included.
    editor.scroll(editor.countLines(0, pos, true) + 1, 0);
    // The editor scrolls when it is next drawn, and near the end of the
    // text it can't put the line at its top: the next sync takes its top
    // as it is, instead of moving the page back.
    lastTop = followedPage;
}

// ---- Files ---------------------------------------------------------------

// Asks what to do with unsaved changes. Returns false when the user
// cancels.
bool saveChangesFirst()
{
    if (!modified) return true;
    int r = choice("The text has changes that are not saved.\nSave them first?",
        "Cancel", "Save", "Don't Save");
    if (r == 0) return false;
    if (r == 1) return save();
    return true;
}

void setText(string text, string name)
{
    textBuf.text(text);
    fileName = name;
    editor.insertPosition(0);
    editor.showInsertPosition();
    preview.topline(0);
    modified = false;
    updateTitle();
    refresh();
}

bool openFile(string name)
{
    import std.file : readText;
    import std.path : absolutePath, buildNormalizedPath;
    name = buildNormalizedPath(absolutePath(name));
    string text;
    try text = readText(name);
    catch (Exception e)
    {
        alert("Can't open " ~ name ~ ":\n" ~ e.msg);
        return false;
    }
    setText(text, name);
    return true;
}

bool saveAs()
{
    auto fc = new NativeFileChooser();
    fc.title("Save As");
    fc.type(BrowseType.browseSaveFile);
    fc.filter("Markdown\t*.md");
    if (fileName.length)
    {
        fc.directory(dirName(fileName));
        fc.presetFile(baseName(fileName));
    }
    if (fc.show() != 0) return false;
    string name = fc.filename();
    if (extension(name).length == 0) name ~= ".md";
    fileName = name;
    return save();
}

bool save()
{
    import std.file : write;
    if (!fileName.length) return saveAs();
    try write(fileName, textBuf.text());
    catch (Exception e)
    {
        alert("Can't save " ~ fileName ~ ":\n" ~ e.msg);
        return false;
    }
    modified = false;
    updateTitle();
    refresh(); // the folder for images and links may have changed
    return true;
}

void newCb(Widget)
{
    if (saveChangesFirst()) setText("", null);
}

void openCb(Widget)
{
    if (!saveChangesFirst()) return;
    auto fc = new NativeFileChooser();
    fc.title("Open");
    fc.type(BrowseType.browseFile);
    fc.filter("Markdown\t*.{md,markdown}");
    if (fileName.length) fc.directory(dirName(fileName));
    if (fc.show() == 0) openFile(fc.filename());
}

void quitCb(Widget)
{
    if (saveChangesFirst()) win.hide();
}

// ---- Formatting ------------------------------------------------------------

// Inline marks: bold `**`, italic `*`, strikethrough `~~` and code `` ` ``.

// Whether `text` is marked with `mark` at both ends. For bold that is two
// or more asterisks, for italic an odd number, since `***text***` is both.
bool markedWith(string text, string mark)
{
    char c = mark[0];
    size_t n, m;
    while (n < text.length && text[n] == c) n++;
    while (m < text.length - n && text[$ - 1 - m] == c) m++;
    if (n * 2 > text.length) return false;
    if (c == '*')
    {
        bool ok(size_t k) => mark == "**" ? k >= 2 : k % 2 == 1;
        return ok(n) && ok(m);
    }
    return n >= mark.length && m >= mark.length;
}

// The number of characters c just before or just after position p.
int runBefore(int p, char c)
{
    int n;
    while (p - n > 0 && textBuf.byteAt(p - n - 1) == c) n++;
    return n;
}

int runAfter(int p, char c) /// ditto
{
    int n;
    while (p + n < textBuf.length() && textBuf.byteAt(p + n) == c) n++;
    return n;
}

// Marks the selection with `mark`, or takes the mark off if it has it
// (inside the selection or just around it); with nothing selected,
// inserts the pair of marks with the cursor between them.
void toggleMark(string mark)
{
    int m = cast(int) mark.length;
    int start, end;
    if (!textBuf.selectionPosition(start, end))
    {
        int p = editor.insertPosition();
        textBuf.insert(p, mark ~ mark);
        editor.insertPosition(p + m);
        return;
    }
    string sel = textBuf.textRange(start, end);
    char c = mark[0];
    if (markedWith(sel, mark))
    {
        // **text** selected: take the marks off inside the selection.
        textBuf.replace(start, end, sel[m .. $ - m]);
        selectText(start, end - 2 * m);
    }
    else if (markedWith(textBuf.textRange(start - runBefore(start, c), end + runAfter(end, c)), mark))
    {
        // text selected inside **text**: take off the marks around it.
        textBuf.replace(start - m, end + m, sel);
        selectText(start - m, end - m);
    }
    else
    {
        textBuf.replace(start, end, mark ~ sel ~ mark);
        selectText(start + m, end + m);
    }
}

// Selects the text from start to end, with the cursor at its end.
void selectText(int start, int end)
{
    textBuf.select(start, end);
    editor.insertPosition(end);
}

// A link, or an image: the selection becomes the link's text (the
// image's description), and the address "url" is selected for typing
// over.
void makeLink(bool image)
{
    int start, end;
    if (!textBuf.selectionPosition(start, end))
        start = end = editor.insertPosition();
    string text = textBuf.textRange(start, end);
    if (text.length == 0) text = image ? "description" : "text";
    string open = image ? "![" : "[";
    textBuf.replace(start, end, open ~ text ~ "](url)");
    int u = start + cast(int)(open.length + text.length) + 2;
    selectText(u, u + 3);
}

// Line elements: headings, lists, quotes and code blocks change every
// line the selection is on, or the cursor's line.

// The start and end of the lines the selection is on, or the cursor's
// line. A selection that ends at the start of a line doesn't take that
// line in.
void currentLines(out int start, out int end)
{
    int s, e;
    if (!textBuf.selectionPosition(s, e)) s = e = editor.insertPosition();
    else if (e > s && textBuf.byteAt(e - 1) == '\n') e--;
    start = textBuf.lineStart(s);
    end = textBuf.lineEnd(e);
}

// Replaces the current lines with what `change` makes of them, as one
// step to undo. Afterwards the changed lines are selected, or, when
// nothing was selected, the cursor is at the end of the last one.
void changeLines(string[] delegate(string[] lines) change)
{
    import std.array : join, split;
    bool hadSelection = textBuf.selected();
    int start, end;
    currentLines(start, end);
    string text = textBuf.textRange(start, end);
    string[] lines = text.length ? text.split("\n") : [""];
    string result = change(lines).join("\n");
    textBuf.replace(start, end, result);
    int newEnd = start + cast(int) result.length;
    if (hadSelection) selectText(start, newEnd);
    else
    {
        textBuf.unselect();
        editor.insertPosition(newEnd);
    }
}

// The length of a heading's marks ("## "), or 0 if the line is no heading.
size_t headingMarks(string line)
{
    size_t n;
    while (n < line.length && n < 6 && line[n] == '#') n++;
    if (n == 0) return 0;
    if (n == line.length) return n;
    return line[n] == ' ' ? n + 1 : 0;
}

// The length of a line's list marker ("- ", "* ", "+ ", or "1. ", "1) "
// for a numbered list), or 0.
size_t listMarker(string line, bool numbered)
{
    import std.algorithm : canFind;
    import std.ascii : isDigit;
    if (!numbered)
        return line.length >= 2 && "-*+".canFind(line[0]) && line[1] == ' ' ? 2 : 0;
    size_t i;
    while (i < line.length && isDigit(line[i])) i++;
    return i > 0 && i + 1 < line.length && (line[i] == '.' || line[i] == ')') && line[i + 1] == ' '
        ? i + 2 : 0;
}

// A heading of `level` 1 to 6, or 0 for normal text. Pressed again on a
// heading of that level, the heading becomes normal text.
void setHeading(int level)
{
    import std.algorithm : all;
    import std.array : replicate;
    changeLines((lines) {
        string marks = "#".replicate(level) ~ " ";
        bool already = level > 0 && lines.all!(l => headingMarks(l) == marks.length && l.startsWith(marks[0 .. $ - 1]));
        foreach (ref l; lines)
        {
            l = l[headingMarks(l) .. $];
            if (level > 0 && !already) l = marks ~ l;
        }
        return lines;
    });
}

// A bullet or numbered list item on each line that has text (or on the
// line itself, when it is a single empty line); pressed again on such a
// list, the markers come off. A list of the other kind is changed over.
void toggleList(bool numbered)
{
    import std.algorithm : all, any, max;
    import std.conv : to;
    changeLines((lines) {
        bool already = lines.any!(l => l.length > 0)
            && lines.all!(l => l.length == 0 || listMarker(l, numbered) > 0);
        int n = 1;
        foreach (ref l; lines)
        {
            if (l.length == 0 && lines.length > 1) continue;
            l = l[max(listMarker(l, false), listMarker(l, true)) .. $];
            if (!already) l = (numbered ? (n++).to!string ~ ". " : "- ") ~ l;
        }
        return lines;
    });
}

// A block quote: "> " before every line; pressed again on a quote, the
// marks come off.
void toggleQuote()
{
    import std.algorithm : all;
    changeLines((lines) {
        bool already = lines.all!(l => l.startsWith(">"));
        foreach (ref l; lines)
        {
            if (already) l = l.startsWith("> ") ? l[2 .. $] : l[1 .. $];
            else l = l.length || lines.length == 1 ? "> " ~ l : ">";
        }
        return lines;
    });
}

// A code block of D: fences on lines of their own around the lines, the
// first one ```D, so the page colours the code as D; pressed again on a
// fenced block, the fences come off. On an empty line it inserts an empty
// block with the cursor inside.
void toggleCodeBlock()
{
    int start, end;
    currentLines(start, end);
    if (!textBuf.selected() && start == end)
    {
        textBuf.insert(start, "```D\n\n```");
        editor.insertPosition(start + 5);
        return;
    }
    changeLines((lines) {
        if (lines.length >= 2 && lines[0].startsWith("```") && lines[$ - 1].startsWith("```"))
            return lines[1 .. $ - 1];
        return ["```D"] ~ lines ~ ["```"];
    });
}

// Blocks of their own: a table or a rule goes after the cursor's line,
// with a blank line before and after it (a rule right under a line of
// text would make that line a heading). Returns where the block starts.
int insertBlock(string block)
{
    int p = textBuf.lineEnd(editor.insertPosition());
    bool emptyLine = textBuf.lineStart(p) == p;
    string before = emptyLine ? "\n" : "\n\n";
    textBuf.insert(p, before ~ block ~ "\n\n");
    textBuf.unselect();
    editor.insertPosition(p + cast(int)(before.length + block.length) + 2);
    return p + cast(int) before.length;
}

void insertRule()
{
    insertBlock("---");
}

// A table of two columns and two rows, with the first heading selected
// to type over.
void insertTable()
{
    int t = insertBlock("| Column 1 | Column 2 |\n|---|---|\n|  |  |\n|  |  |");
    selectText(t + 2, t + 10);
}

// ---- Links in the page ---------------------------------------------------

// A click on a link to another .md file opens it in the editor.
bool followLink(MarkdownView view, string url)
{
    import std.path : absolutePath, buildNormalizedPath;
    import std.string : indexOf;
    if (url.startsWith("#") || url.indexOf("://") >= 0 || url.startsWith("mailto:"))
        return false;
    string path = url;
    auto hash = path.indexOf('#');
    if (hash >= 0) path = path[0 .. hash];
    string ext = extension(path).toLower();
    if (ext != ".md" && ext != ".markdown") return false;
    if (fileName.length) path = absolutePath(path, dirName(fileName));
    path = buildNormalizedPath(absolutePath(path));
    if (saveChangesFirst()) openFile(path);
    return true;
}

// ---- The window ------------------------------------------------------------

int main(string[] args)
{
    win = new DoubleWindow(1000, 700, appName);

    auto menu = new MenuBar(0, 0, 1000, 25);
    menu.add("&File/&New", stateCommand | 'n', (w) { newCb(w); });
    menu.add("&File/&Open...", stateCommand | 'o', (w) { openCb(w); });
    menu.add("&File/&Save", stateCommand | 's', (w) { save(); });
    menu.add("&File/Save &As...", stateCommand | stateShift | 's', (w) { saveAs(); }, menuDivider);
    menu.add("&File/&Quit", stateCommand | 'q', (w) { quitCb(w); });
    menu.add("F&ormat/&Bold", stateCommand | 'b', (w) { toggleMark("**"); });
    menu.add("F&ormat/&Italic", stateCommand | 'i', (w) { toggleMark("*"); });
    menu.add("F&ormat/&Strikethrough", stateCommand | stateShift | 'x', (w) { toggleMark("~~"); });
    menu.add("F&ormat/&Code", stateCommand | 'e', (w) { toggleMark("`"); }, menuDivider);
    menu.add("F&ormat/&Link", stateCommand | 'k', (w) { makeLink(false); });
    menu.add("F&ormat/Ima&ge", stateCommand | stateShift | 'i', (w) { makeLink(true); }, menuDivider);
    static foreach (level; 1 .. 7)
        menu.add("F&ormat/&Heading/Heading " ~ level.stringof, stateCommand | ('0' + level),
            (w) { setHeading(level); });
    menu.add("F&ormat/&Normal Text", stateCommand | '0', (w) { setHeading(0); }, menuDivider);
    menu.add("F&ormat/B&ullet List", stateCommand | stateShift | 'u', (w) { toggleList(false); });
    menu.add("F&ormat/Nu&mbered List", stateCommand | stateShift | 'o', (w) { toggleList(true); });
    menu.add("F&ormat/&Quote", stateCommand | stateShift | 'q', (w) { toggleQuote(); });
    menu.add("F&ormat/Code Bloc&k", stateCommand | stateShift | 'k', (w) { toggleCodeBlock(); }, menuDivider);
    menu.add("F&ormat/&Table", stateCommand | 't', (w) { insertTable(); });
    menu.add("F&ormat/&Rule", 0, (w) { insertRule(); });

    auto tile = new Tile(0, 25, 1000, 675);
    textBuf = new TextBuffer();
    editor = new Editor(0, 25, 480, 675);
    editor.buffer(textBuf);
    editor.textfont(courier);
    editor.wrapMode(WrapMode.wrapAtBounds, 0);
    preview = new MarkdownView(480, 25, 520, 675);
    preview.link((v, url) => followLink(v, url));
    preview.callback((w) { followPage(); });
    tile.end();

    win.resizable(tile);
    win.end();
    win.callback((w) { quitCb(w); });

    refreshTimer = () { refresh(); };
    scrollTimer = () { syncScroll(); fl.repeatTimeout(0.15, scrollTimer); };
    textBuf.addModifyCallback((pos, nInserted, nDeleted, nRestyled, deleted) {
        if (nInserted || nDeleted)
        {
            setModified(true);
            fl.removeTimeout(refreshTimer);
            fl.addTimeout(0.3, refreshTimer);
        }
    });

    string file = args.length > 1 && !args[1].startsWith("-") ? args[1] : null;
    if (file.length) args = args[0 .. 1] ~ args[2 .. $];
    win.show(args);
    if (!file.length || !openFile(file))
        setText(welcome, null);
    editor.takeFocus();
    fl.addTimeout(0.15, scrollTimer);
    fl.run();
    return 0;
}

// The Format menu's editing rules. Run them with:
//   dmd -unittest -Isource source/test/markdown_editor.d -of=build/markdown_editor_test \
//       -L-L. -L-rpath=. -L-lfldtk -L-lX11 -L-lXft && build/markdown_editor_test
unittest
{
    FlGroup.current(null);
    textBuf = new TextBuffer();
    editor = new Editor(0, 0, 400, 300);
    editor.buffer(textBuf);
    scope (exit) FlGroup.current(null);

    void set(string text, int start, int end)
    {
        textBuf.text(text);
        if (end > start) selectText(start, end);
        else { textBuf.unselect(); editor.insertPosition(start); }
    }

    // Marks go on, come off from inside or around, and combine.
    set("a word here", 2, 6);
    toggleMark("**");
    assert(textBuf.text() == "a **word** here");
    toggleMark("**");
    assert(textBuf.text() == "a word here");
    set("a **word** here", 2, 10);
    toggleMark("**");
    assert(textBuf.text() == "a word here");
    set("a **word** here", 4, 8);
    toggleMark("*");
    assert(textBuf.text() == "a ***word*** here");
    toggleMark("*");
    assert(textBuf.text() == "a **word** here");
    set("x", 0, 1);
    toggleMark("~~");
    assert(textBuf.text() == "~~x~~");
    set("", 0, 0);
    toggleMark("`");
    assert(textBuf.text() == "``" && editor.insertPosition() == 1);

    // Links and images select the address.
    set("see this", 4, 8);
    makeLink(false);
    assert(textBuf.text() == "see [this](url)" && textBuf.selectionText() == "url");
    set("", 0, 0);
    makeLink(true);
    assert(textBuf.text() == "![description](url)" && textBuf.selectionText() == "url");

    // Headings: set, changed, taken off.
    set("Title\nbody", 2, 2);
    setHeading(2);
    assert(textBuf.text() == "## Title\nbody");
    setHeading(1);
    assert(textBuf.text() == "# Title\nbody");
    setHeading(1);
    assert(textBuf.text() == "Title\nbody");
    set("", 0, 0);
    setHeading(3);
    assert(textBuf.text() == "### " && editor.insertPosition() == 4);

    // Lists: on the lines with text, changed over, taken off.
    set("one\n\ntwo\nnext", 0, 9);
    toggleList(false);
    assert(textBuf.text() == "- one\n\n- two\nnext", textBuf.text());
    toggleList(true);
    assert(textBuf.text() == "1. one\n\n2. two\nnext", textBuf.text());
    toggleList(true);
    assert(textBuf.text() == "one\n\ntwo\nnext", textBuf.text());

    // Quotes keep empty lines inside the quote.
    set("a\n\nb", 0, 4);
    toggleQuote();
    assert(textBuf.text() == "> a\n>\n> b");
    toggleQuote();
    assert(textBuf.text() == "a\n\nb");

    // Code blocks: fenced, unfenced, or an empty one to type into.
    set("x = 1;\ny = 2;", 0, 13);
    toggleCodeBlock();
    assert(textBuf.text() == "```D\nx = 1;\ny = 2;\n```");
    toggleCodeBlock();
    assert(textBuf.text() == "x = 1;\ny = 2;");
    set("", 0, 0);
    toggleCodeBlock();
    assert(textBuf.text() == "```D\n\n```" && editor.insertPosition() == 5);

    // Blocks go after the line, with blank lines around them.
    set("text", 1, 1);
    insertRule();
    assert(textBuf.text() == "text\n\n---\n\n");
    set("text", 0, 0);
    insertTable();
    assert(textBuf.selectionText() == "Column 1");
}
