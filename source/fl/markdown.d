/*
 * Markdown parser: turns Markdown text into a document tree that
 * `fl.markdown_view.MarkdownView` lays out and draws.
 *
 * It reads the Markdown that README files and documentation use:
 * CommonMark's blocks and inlines plus GitHub's tables, strikethrough
 * and bare `http(s)://` links.
 *
 * Blocks: ATX (`# Title`) and setext (underlined) headings,
 * paragraphs, fenced (``` and ~~~) and indented code blocks, block
 * quotes, bullet and ordered lists (nested, tight or loose, with lazy
 * continuation lines), pipe tables with column alignment, thematic
 * breaks (`---`), and link reference definitions (`[id]: url "title"`,
 * over one or more lines at a paragraph's start), which define links
 * and are not shown. HTML comments are skipped; other HTML lines are
 * read as paragraphs, with their tags dropped.
 *
 * Inlines: emphasis and strong emphasis with `*` and `_` (CommonMark's
 * delimiter rules), `~~strikethrough~~`, code spans, links and images
 * (inline, reference, collapsed and shortcut forms; CommonMark's
 * bracket stack, so links don't nest), autolinks (`<https://...>`,
 * `<name@host>`), bare `http(s)://` URLs, backslash escapes, hard line
 * breaks (two trailing spaces, a trailing backslash or `<br>`), and
 * character references (all of HTML5's names, `fl.html_entities`, and
 * numeric ones).
 *
 * Raw HTML (tags, comments, `<?...?>`, declarations, CDATA) is
 * recognised as CommonMark defines it, so it binds before links and
 * emphasis, but isn't shown: `<br>` is a hard break, `<img src alt>`
 * an image, and other tags are dropped, their text kept.
 *
 * Not read: footnotes, task-list check boxes, GitHub's `www.` and bare
 * e-mail links. Tabs in code blocks are expanded to spaces.
 *
 * Each heading gets an `id` the way GitHub makes one (lower case,
 * punctuation removed, spaces as hyphens, `-1`, `-2` for repeats), so
 * links to `#a-heading` work.
 */
module fl.markdown;

import std.algorithm : canFind, startsWith, endsWith, min, max;
import std.array : appender, join, split, replace;
import std.ascii : isDigit, isAlpha, isAlphaNum, isPunctuation, isWhite;
import std.string : strip, stripLeft, stripRight, splitLines, toLower, indexOf;
import fl.html_entities : htmlEntity;

/// The kind of a `MdInline`.
enum MdInlineKind
{
    text,       /// `text`
    code,       /// `text`, a code span
    emphasis,   /// `children`, in italics
    strong,     /// `children`, in bold
    strike,     /// `children`, struck through
    link,       /// `children`, linking to `url`
    image,      /// the image at `url`, with `text` as its description
    softBreak,  /// a line break inside a paragraph, shown as a space
    hardBreak,  /// a line break that is kept
}

/// A piece of text inside a paragraph, heading or table cell.
struct MdInline
{
    MdInlineKind kind; ///
    string text;       /// The text of `text` and `code`; an image's description.
    string url;        /// The target of `link` and `image`.
    string title;      /// The title of `link` and `image`, if any.
    MdInline[] children; /// The contents of `emphasis`, `strong`, `strike` and `link`.
}

/// The kind of a `MdBlock`.
enum MdBlockKind
{
    document,   /// `children`: the whole document
    paragraph,  /// `inlines`
    heading,    /// `inlines`, at `level` 1 to 6, with `id`
    codeBlock,  /// `text`, with `info` (a fenced block's language)
    quote,      /// `children`
    list,       /// `children` (`listItem` blocks); `ordered`, `start`, `tight`
    listItem,   /// `children`
    table,      /// `rows` (the first is the header) and `aligns`
    rule,       /// a thematic break
}

/// The alignment of a table column.
enum MdAlign
{
    none,   /// no alignment given: left
    left,   ///
    center, ///
    right,  ///
}

/// A block of a Markdown document.
final class MdBlock
{
    MdBlockKind kind; ///
    MdBlock[] children;  /// The blocks inside a `document`, `quote`, `list` or `listItem`.
    MdInline[] inlines;  /// The text of a `paragraph` or `heading`.
    int level;           /// A heading's level, 1 to 6.
    string id;           /// A heading's anchor, for `#id` links.
    string text;         /// A code block's text, ending in a newline.
    string info;         /// A fenced code block's info string (its language).
    bool ordered;        /// Whether a list is numbered.
    int start = 1;       /// The first number of an ordered list.
    bool tight;          /// Whether a list's items are tight: no blank lines between or inside them.
    MdInline[][][] rows; /// A table's rows of cells; `rows[0]` is the header row.
    MdAlign[] aligns;    /// A table's column alignments.
    int line = -1;       /// The source line the block starts on, counting from 0 (-1 for the document).
    int lineCount;       /// The number of source lines the block takes.

    // The unparsed inline text of a paragraph, heading or table cell,
    // parsed once every link reference definition is known.
    private string raw_;
    private string[][] rawRows_;

    this(MdBlockKind kind) { this.kind = kind; }
}

/// A link reference definition: `[label]: url "title"`.
struct MdLinkRef
{
    string url;   ///
    string title; ///
}

/**
 * Parses the Markdown text `source` into a document tree: a
 * `MdBlockKind.document` block whose `children` are the top-level
 * blocks.
 */
MdBlock parseMarkdown(string source)
{
    MdLinkRef[string] refs;
    auto lines = source.replace("\r\n", "\n").replace("\r", "\n").split("\n");
    if (lines.length && lines[$ - 1].length == 0) lines = lines[0 .. $ - 1]; // the final line ending
    foreach (ref l; lines) l = expandTabs(l);

    auto doc = new MdBlock(MdBlockKind.document);
    doc.lineCount = cast(int) lines.length;
    doc.children = parseBlocks(lines, refs, 0);

    int[string] usedIds;
    resolveInlines(doc, refs, usedIds);
    return doc;
}

/// The plain text of `inlines`, without formatting.
string plainText(const(MdInline)[] inlines)
{
    auto buf = appender!string();
    void walk(const(MdInline)[] list)
    {
        foreach (ref i; list)
        {
            final switch (i.kind)
            {
            case MdInlineKind.text, MdInlineKind.code:
                buf.put(i.text);
                break;
            case MdInlineKind.image:
                buf.put(i.text);
                break;
            case MdInlineKind.emphasis, MdInlineKind.strong, MdInlineKind.strike, MdInlineKind.link:
                walk(i.children);
                break;
            case MdInlineKind.softBreak, MdInlineKind.hardBreak:
                buf.put(' ');
                break;
            }
        }
    }
    walk(inlines);
    return buf.data;
}

/**
 * The anchor GitHub gives a heading with the text `text`: lower case,
 * with everything but letters, digits, spaces, hyphens and
 * underscores removed, and spaces turned into hyphens.
 */
string headingSlug(string text)
{
    import std.uni : uniToLower = toLower, uniIsAlpha = isAlpha, isNumber;

    auto buf = appender!string();
    foreach (dchar c; text.strip())
    {
        if (c == ' ') buf.put('-');
        else if (c == '-' || c == '_' || uniIsAlpha(c) || isNumber(c)) buf.put(uniToLower(c));
    }
    return buf.data;
}

// ---------------------------------------------------------------------
// Blocks
// ---------------------------------------------------------------------

private string expandTabs(string line)
{
    if (!line.canFind('\t')) return line;
    auto buf = appender!string();
    size_t col;
    foreach (dchar c; line)
    {
        if (c == '\t')
        {
            do { buf.put(' '); col++; } while (col % 4);
        }
        else
        {
            buf.put(c);
            col++;
        }
    }
    return buf.data;
}

private bool isBlank(string line) { return line.strip().length == 0; }

private size_t indentOf(string line)
{
    size_t n;
    while (n < line.length && line[n] == ' ') n++;
    return n;
}

/// The level of an ATX heading line (`## Title`), or 0.
private int atxLevel(string line, out string content)
{
    if (indentOf(line) > 3) return 0;
    auto s = line.stripLeft();
    int level;
    while (level < s.length && s[level] == '#') level++;
    if (level == 0 || level > 6) return 0;
    if (level < s.length && s[level] != ' ') return 0;
    auto rest = s[level .. $].strip();
    // A closing run of #s, preceded by a space (or making up all of it).
    size_t e = rest.length;
    while (e > 0 && rest[e - 1] == '#') e--;
    if (e == 0) rest = "";
    else if (e < rest.length && rest[e - 1] == ' ') rest = rest[0 .. e].stripRight();
    content = rest;
    return level;
}

private bool isRule(string line)
{
    if (indentOf(line) > 3) return false;
    auto s = line.strip();
    if (s.length < 3) return false;
    char c = s[0];
    if (c != '-' && c != '*' && c != '_') return false;
    int n;
    foreach (ch; s)
    {
        if (ch == c) n++;
        else if (ch != ' ') return false;
    }
    return n >= 3;
}

/// A setext heading underline: 1 for `===`, 2 for `---`, else 0.
private int setextLevel(string line)
{
    if (indentOf(line) > 3) return 0;
    auto s = line.strip();
    if (s.length == 0) return 0;
    char c = s[0];
    if (c != '=' && c != '-') return 0;
    foreach (ch; s)
        if (ch != c) return 0;
    return c == '=' ? 1 : 2;
}

/// The fence of a fenced code block's opening line, or null.
private string fenceOf(string line, out string info)
{
    if (indentOf(line) > 3) return null;
    auto s = line.stripLeft();
    if (s.length < 3 || (s[0] != '`' && s[0] != '~')) return null;
    size_t n;
    while (n < s.length && s[n] == s[0]) n++;
    if (n < 3) return null;
    info = s[n .. $].strip();
    if (s[0] == '`' && info.canFind('`')) return null;
    return s[0 .. n];
}

private struct ListMarker
{
    bool ok;
    bool ordered;
    char bullet;    // '-', '+', '*', or the delimiter '.' or ')' of an ordered marker
    int number;
    size_t width;   // columns from the start of the line to the item's content
    bool empty;     // nothing after the marker
}

private ListMarker listMarker(string line)
{
    ListMarker m;
    size_t ind = indentOf(line);
    if (ind > 3) return m;
    size_t i = ind;
    if (i < line.length && (line[i] == '-' || line[i] == '+' || line[i] == '*'))
    {
        m.bullet = line[i];
        i++;
    }
    else
    {
        size_t d = i;
        while (i < line.length && isDigit(line[i]) && i - d < 9) i++;
        if (i == d || i >= line.length || (line[i] != '.' && line[i] != ')')) return m;
        import std.conv : to;
        m.number = line[d .. i].to!int;
        m.ordered = true;
        m.bullet = line[i];
        i++;
    }
    if (i < line.length && line[i] != ' ') return m;
    size_t sp;
    while (i + sp < line.length && line[i + sp] == ' ') sp++;
    m.ok = true;
    m.empty = i + sp >= line.length;
    if (m.empty || sp > 4) sp = 1;
    m.width = i + sp;
    return m;
}

private bool isHtmlCommentStart(string line)
{
    return indentOf(line) <= 3 && line.stripLeft().startsWith("<!--");
}

/// Splits a table row into its cells' text.
private string[] tableCells(string line)
{
    auto s = line.strip();
    if (s.startsWith("|")) s = s[1 .. $];
    if (s.endsWith("|") && !s.endsWith("\\|")) s = s[0 .. $ - 1];
    string[] cells;
    auto cur = appender!string();
    bool inCode;
    for (size_t i = 0; i < s.length; i++)
    {
        char c = s[i];
        if (c == '\\' && i + 1 < s.length && s[i + 1] == '|')
        {
            cur.put('|');
            i++;
        }
        else if (c == '`')
        {
            inCode = !inCode;
            cur.put(c);
        }
        else if (c == '|' && !inCode)
        {
            cells ~= cur.data.strip();
            cur = appender!string();
        }
        else
            cur.put(c);
    }
    cells ~= cur.data.strip();
    return cells;
}

/// The column alignments of a table's delimiter row, or null if
/// `line` isn't one.
private MdAlign[] tableAligns(string line)
{
    if (!line.canFind('-')) return null;
    auto t = line.strip();
    if (!t.canFind('|') && !t.canFind(':') ) {
        // A one-column delimiter row needs a pipe; "---" is a rule.
        return null;
    }
    MdAlign[] aligns;
    foreach (cell; tableCells(line))
    {
        if (cell.length == 0) return null;
        bool left = cell[0] == ':';
        bool right = cell[$ - 1] == ':';
        auto dashes = cell[left ? 1 : 0 .. right && cell.length > 1 ? $ - 1 : $];
        if (dashes.length == 0) return null;
        foreach (c; dashes)
            if (c != '-') return null;
        aligns ~= left && right ? MdAlign.center : left ? MdAlign.left : right ? MdAlign.right : MdAlign.none;
    }
    return aligns;
}

/// Whether lines[i] and lines[i+1] start a table.
private bool isTableStart(string[] lines, size_t i)
{
    if (i + 1 >= lines.length || !lines[i].canFind('|')) return false;
    if (indentOf(lines[i]) > 3) return false;
    auto aligns = tableAligns(lines[i + 1]);
    return aligns !is null && aligns.length == tableCells(lines[i]).length;
}

// Skips spaces and tabs, and at most one line ending among them.
// Whether it skipped anything.
private bool skipSpaceNewline(string s, ref size_t i)
{
    size_t st = i;
    bool newline;
    while (i < s.length)
    {
        if (s[i] == ' ' || s[i] == '\t') i++;
        else if (s[i] == '\n' && !newline) { newline = true; i++; }
        else break;
    }
    return i > st;
}

/// A link label, `[...]`, at `s[i]`: no unescaped brackets, at most 999
/// characters, not blank. Sets `label` to its text and moves `i` past it.
private bool scanLabel(string s, ref size_t i, out string label)
{
    if (i >= s.length || s[i] != '[') return false;
    size_t j = i + 1;
    while (j < s.length && s[j] != ']')
    {
        if (s[j] == '[') return false;
        if (s[j] == '\\' && j + 1 < s.length && isAsciiPunct(s[j + 1])) j++;
        j++;
    }
    if (j >= s.length || j - i - 1 > 999 || s[i + 1 .. j].strip().length == 0) return false;
    label = s[i + 1 .. j];
    i = j + 1;
    return true;
}

/// A link destination at `s[i]`: `<...>` (on one line, no unescaped
/// `<` or `>`), or a run without spaces or control characters, with
/// balanced parentheses (possibly empty). Sets `dest`, unescaped, and
/// moves `i` past it.
private bool scanDest(string s, ref size_t i, out string dest)
{
    size_t j;
    if (i < s.length && s[i] == '<')
    {
        for (j = i + 1; j < s.length; j++)
        {
            char c = s[j];
            if (c == '\\' && j + 1 < s.length && isAsciiPunct(s[j + 1])) { j++; continue; }
            if (c == '\n' || c == '<') return false;
            if (c == '>')
            {
                dest = unescape(s[i + 1 .. j]);
                i = j + 1;
                return true;
            }
        }
        return false;
    }
    int depth;
    for (j = i; j < s.length; j++)
    {
        char c = s[j];
        if (c <= ' ' || c == 0x7f) break;
        if (c == '\\' && j + 1 < s.length && isAsciiPunct(s[j + 1])) { j++; continue; }
        if (c == '(') depth++;
        else if (c == ')')
        {
            if (depth == 0) break;
            depth--;
        }
    }
    if (depth) return false;
    dest = unescape(s[i .. j]);
    i = j;
    return true;
}

/// A link title at `s[i]`: `"..."`, `'...'` or `(...)`, with backslash
/// escapes. Sets `title`, unescaped, and moves `i` past it.
private bool scanTitle(string s, ref size_t i, out string title)
{
    if (i >= s.length) return false;
    char open = s[i];
    if (open != '"' && open != '\'' && open != '(') return false;
    char close = open == '(' ? ')' : open;
    for (size_t j = i + 1; j < s.length; j++)
    {
        char c = s[j];
        if (c == '\\' && j + 1 < s.length && isAsciiPunct(s[j + 1])) { j++; continue; }
        if (c == close)
        {
            title = unescape(s[i + 1 .. j]);
            i = j + 1;
            return true;
        }
        if (open == '(' && c == '(') return false;
    }
    return false;
}

/// A link reference definition at the start of `s` (a paragraph's
/// text): `[label]: destination "title"`, over one or more lines. Adds
/// it to `refs` (the first definition of a label counts) and returns
/// the length it takes up, up to and including its line ending; 0 if
/// `s` doesn't start with one.
private size_t parseLinkRefDef(string s, ref MdLinkRef[string] refs)
{
    size_t i;
    string label, dest, title;
    if (!scanLabel(s, i, label) || i >= s.length || s[i] != ':') return 0;
    i++;
    skipSpaceNewline(s, i);
    size_t destStart = i;
    if (!scanDest(s, i, dest) || i == destStart) return 0;
    size_t afterDest = i;

    // A title, preceded by white space, with nothing after it on its line.
    bool hasTitle;
    size_t j = i;
    if (skipSpaceNewline(s, j) && scanTitle(s, j, title))
    {
        while (j < s.length && (s[j] == ' ' || s[j] == '\t')) j++;
        if (j >= s.length || s[j] == '\n')
        {
            hasTitle = true;
            i = j;
        }
    }
    if (!hasTitle)
    {
        title = null;
        i = afterDest;
        while (i < s.length && (s[i] == ' ' || s[i] == '\t')) i++;
        if (i < s.length && s[i] != '\n') return 0;
    }
    if (i < s.length) i++;
    auto key = normalizeLabel(label);
    if (key !in refs) refs[key] = MdLinkRef(dest, title);
    return i;
}

// A label's lookup key: Unicode case folded (so `ẞ`, `ß` and `SS` are
// the same), with runs of white space as one space.
private string normalizeLabel(string label)
{
    import std.uni : uniToLower = toLower, uniToUpper = toUpper;
    auto buf = appender!string();
    bool space;
    foreach (dchar c; label.strip())
    {
        if (c == ' ' || c == '\n' || c == '\t') space = true;
        else
        {
            if (space) buf.put(' ');
            space = false;
            buf.put(c);
        }
    }
    return uniToLower(uniToUpper(uniToLower(buf.data)));
}

/// Whether `line` starts a block that ends a paragraph.
private bool interruptsParagraph(string[] lines, size_t i)
{
    auto line = lines[i];
    string dummy;
    if (atxLevel(line, dummy)) return true;
    if (fenceOf(line, dummy) !is null) return true;
    if (isRule(line)) return true;
    if (indentOf(line) <= 3 && line.stripLeft().startsWith(">")) return true;
    if (isHtmlCommentStart(line)) return true;
    auto m = listMarker(line);
    if (m.ok && !m.empty && (!m.ordered || m.number == 1)) return true;
    if (isTableStart(lines, i)) return true;
    return false;
}

// `base` is the source line of `lines[0]`: the lines of a quote or a list
// item are consecutive lines of the source, without their markers.
private MdBlock[] parseBlocks(string[] lines, ref MdLinkRef[string] refs, size_t base = 0)
{
    MdBlock[] blocks;
    size_t i;
    while (i < lines.length)
    {
        auto line = lines[i];
        // The blocks this pass adds start at line `start` and take the
        // lines up to `i`.
        size_t start = i, added = blocks.length;
        scope (exit)
            foreach (b; blocks[added .. $])
            {
                b.line = cast(int)(base + start);
                b.lineCount = cast(int)(i - start);
            }

        if (isBlank(line))
        {
            i++;
            continue;
        }

        // Fenced code block.
        string info;
        auto fence = fenceOf(line, info);
        if (fence !is null)
        {
            size_t ind = indentOf(line);
            auto b = new MdBlock(MdBlockKind.codeBlock);
            b.info = info;
            auto buf = appender!string();
            i++;
            while (i < lines.length)
            {
                auto l = lines[i];
                auto ls = l.stripLeft();
                if (indentOf(l) <= 3 && ls.startsWith(fence) && ls.strip().length >= fence.length)
                {
                    bool allFence = true;
                    foreach (c; ls.strip())
                        if (c != fence[0]) { allFence = false; break; }
                    if (allFence) { i++; break; }
                }
                size_t strip = min(ind, indentOf(l));
                buf.put(l[strip .. $]);
                buf.put('\n');
                i++;
            }
            b.text = buf.data;
            blocks ~= b;
            continue;
        }

        // Indented code block.
        if (indentOf(line) >= 4)
        {
            auto b = new MdBlock(MdBlockKind.codeBlock);
            string[] code;
            while (i < lines.length && (indentOf(lines[i]) >= 4 || isBlank(lines[i])))
            {
                code ~= isBlank(lines[i]) ? "" : lines[i][4 .. $];
                i++;
            }
            while (code.length && code[$ - 1].length == 0) code = code[0 .. $ - 1];
            b.text = code.join("\n") ~ "\n";
            blocks ~= b;
            continue;
        }

        // ATX heading.
        string content;
        if (auto level = atxLevel(line, content))
        {
            auto b = new MdBlock(MdBlockKind.heading);
            b.level = level;
            b.raw_ = content;
            blocks ~= b;
            i++;
            continue;
        }

        if (isRule(line))
        {
            blocks ~= new MdBlock(MdBlockKind.rule);
            i++;
            continue;
        }

        // HTML comment: skipped up to its end.
        if (isHtmlCommentStart(line))
        {
            while (i < lines.length && !lines[i].canFind("-->")) i++;
            i++;
            continue;
        }

        // Block quote.
        if (indentOf(line) <= 3 && line.stripLeft().startsWith(">"))
        {
            string[] inner;
            while (i < lines.length)
            {
                auto l = lines[i];
                auto ls = l.stripLeft();
                if (indentOf(l) <= 3 && ls.startsWith(">"))
                {
                    auto rest = ls[1 .. $];
                    if (rest.startsWith(" ")) rest = rest[1 .. $];
                    inner ~= rest;
                    i++;
                }
                else if (!isBlank(l) && !interruptsParagraph(lines, i) && endsInParagraph(inner))
                {
                    inner ~= lazyLine(l); // lazy continuation of the quote's paragraph
                    i++;
                }
                else
                    break;
            }
            auto b = new MdBlock(MdBlockKind.quote);
            b.children = parseBlocks(inner, refs, base + start);
            blocks ~= b;
            continue;
        }

        // List.
        auto marker = listMarker(line);
        if (marker.ok)
        {
            auto list = new MdBlock(MdBlockKind.list);
            list.ordered = marker.ordered;
            list.start = marker.ordered ? marker.number : 1;
            list.tight = true;
            bool blankBetween;

            while (i < lines.length)
            {
                auto m = listMarker(lines[i]);
                if (!m.ok || m.ordered != marker.ordered || m.bullet != marker.bullet
                    || isRule(lines[i]))
                    break;
                if (blankBetween) list.tight = false;

                string[] itemLines = [lines[i].length > m.width ? lines[i][m.width .. $] : ""];
                size_t itemStart = i;
                i++;
                bool blankInside;
                // An item can start with at most one blank line: one that
                // starts empty and is followed by a blank line is empty.
                bool emptyItem = m.empty && i < lines.length && isBlank(lines[i]);
                while (i < lines.length && !emptyItem)
                {
                    auto l = lines[i];
                    if (isBlank(l))
                    {
                        // Part of the item only if the item continues after it.
                        size_t j = i;
                        while (j < lines.length && isBlank(lines[j])) j++;
                        if (j < lines.length && indentOf(lines[j]) >= m.width)
                        {
                            foreach (k; i .. j) itemLines ~= "";
                            i = j;
                            blankInside = true;
                            continue;
                        }
                        break;
                    }
                    if (indentOf(l) >= m.width)
                    {
                        itemLines ~= l[m.width .. $];
                        i++;
                        continue;
                    }
                    if (!interruptsParagraph(lines, i) && !listMarker(l).ok && endsInParagraph(itemLines))
                    {
                        itemLines ~= lazyLine(l); // lazy continuation line
                        i++;
                        continue;
                    }
                    break;
                }

                auto item = new MdBlock(MdBlockKind.listItem);
                item.line = cast(int)(base + itemStart);
                item.lineCount = cast(int)(i - itemStart);
                item.children = parseBlocks(itemLines, refs, base + itemStart);
                // A blank line between two blocks of the item makes the list loose.
                if (blankInside && item.children.length > 1)
                {
                    bool nestedListOnly = item.children.length == 2
                        && item.children[1].kind == MdBlockKind.list;
                    if (!nestedListOnly || hasBlankBefore(itemLines))
                        list.tight = false;
                }
                list.children ~= item;

                // Blank lines before the next item.
                size_t j = i;
                while (j < lines.length && isBlank(lines[j])) j++;
                blankBetween = j > i;
                if (j < lines.length)
                {
                    auto next = listMarker(lines[j]);
                    if (next.ok && next.ordered == marker.ordered && next.bullet == marker.bullet
                        && !isRule(lines[j]))
                    {
                        i = j;
                        continue;
                    }
                }
                break;
            }
            blocks ~= list;
            continue;
        }

        // Table.
        if (isTableStart(lines, i))
        {
            auto b = new MdBlock(MdBlockKind.table);
            b.aligns = tableAligns(lines[i + 1]);
            size_t cols = b.aligns.length;
            string[] fit(string[] cells)
            {
                if (cells.length > cols) cells = cells[0 .. cols];
                while (cells.length < cols) cells ~= "";
                return cells;
            }
            b.rawRows_ ~= fit(tableCells(lines[i]));
            i += 2;
            while (i < lines.length && !isBlank(lines[i]) && lines[i].canFind('|')
                && !(indentOf(lines[i]) <= 3 && lines[i].stripLeft().startsWith(">")))
            {
                b.rawRows_ ~= fit(tableCells(lines[i]));
                i++;
            }
            blocks ~= b;
            continue;
        }

        // Paragraph, or a setext heading.
        string[] para = [line.stripLeft()];
        i++;
        int setext;
        while (i < lines.length && !isBlank(lines[i]))
        {
            if ((setext = setextLevel(lines[i])) != 0)
            {
                i++;
                break;
            }
            if (interruptsParagraph(lines, i)) break;
            para ~= lines[i].stripLeft();
            i++;
        }
        // Link reference definitions at the paragraph's start define
        // links and aren't shown.
        string text = para.join("\n");
        size_t used;
        while (text.length && (used = parseLinkRefDef(text, refs)) != 0)
            text = text[used .. $];
        if (text.strip().length == 0)
        {
            // Only definitions: a setext underline after them is a line
            // of its own.
            if (setext) i--;
            continue;
        }
        para = text.split("\n");
        if (setext)
        {
            auto b = new MdBlock(MdBlockKind.heading);
            b.level = setext;
            b.raw_ = para.join("\n").strip();
            blocks ~= b;
        }
        else
        {
            auto b = new MdBlock(MdBlockKind.paragraph);
            b.raw_ = para.join("\n").stripRight();
            blocks ~= b;
        }
    }
    return blocks;
}

// Whether `lines` (a quote's or list item's lines so far) end in an
// open paragraph, which a lazy continuation line can continue.
private bool endsInParagraph(string[] lines)
{
    if (lines.length == 0 || isBlank(lines[$ - 1])) return false;
    MdLinkRef[string] scratch;
    auto blocks = parseBlocks(lines, scratch);
    while (blocks.length)
    {
        auto b = blocks[$ - 1];
        if (b.kind == MdBlockKind.paragraph) return true;
        if (b.kind != MdBlockKind.quote && b.kind != MdBlockKind.list && b.kind != MdBlockKind.listItem)
            return false;
        blocks = b.children;
    }
    return false;
}

// A lazy continuation line, as the paragraph text it is: escaped if,
// without its indentation, it would start a block of its own.
private string lazyLine(string line)
{
    auto s = line.stripLeft();
    if (!interruptsParagraph([s], 0) && !setextLevel(s) && !listMarker(s).ok) return s;
    size_t k;
    while (k < s.length && isDigit(s[k])) k++;
    return s[0 .. k] ~ "\\" ~ s[k .. $];
}

private bool hasBlankBefore(string[] itemLines)
{
    // Whether a blank line comes before the item's nested list, rather
    // than only inside it.
    foreach (l; itemLines[1 .. $])
    {
        if (isBlank(l)) return true;
        if (listMarker(l).ok) return false;
    }
    return false;
}

private void resolveInlines(MdBlock b, ref MdLinkRef[string] refs, ref int[string] usedIds)
{
    final switch (b.kind)
    {
    case MdBlockKind.paragraph:
        b.inlines = parseInlines(b.raw_, refs);
        break;
    case MdBlockKind.heading:
        b.inlines = parseInlines(b.raw_, refs);
        string slug = headingSlug(plainText(b.inlines));
        if (auto n = slug in usedIds)
        {
            b.id = slug ~ "-" ~ to_s(*n);
            (*n)++;
        }
        else
        {
            b.id = slug;
            usedIds[slug] = 1;
        }
        break;
    case MdBlockKind.table:
        foreach (row; b.rawRows_)
        {
            MdInline[][] cells;
            foreach (c; row) cells ~= parseInlines(c, refs);
            b.rows ~= cells;
        }
        break;
    case MdBlockKind.document, MdBlockKind.quote, MdBlockKind.list, MdBlockKind.listItem:
        foreach (c; b.children) resolveInlines(c, refs, usedIds);
        break;
    case MdBlockKind.codeBlock, MdBlockKind.rule:
        break;
    }
}

private string to_s(int n)
{
    import std.conv : to;
    return n.to!string;
}

// ---------------------------------------------------------------------
// Inlines
// ---------------------------------------------------------------------

private bool isAsciiPunct(char c) { return c < 0x80 && isPunctuation(c); }

private string unescape(string s)
{
    if (!s.canFind('\\') && !s.canFind('&')) return s;
    auto buf = appender!string();
    for (size_t i = 0; i < s.length; i++)
    {
        if (s[i] == '\\' && i + 1 < s.length && isAsciiPunct(s[i + 1]))
        {
            buf.put(s[i + 1]);
            i++;
        }
        else if (s[i] == '&')
        {
            size_t len;
            auto e = entity(s[i .. $], len);
            if (len) { buf.put(e); i += len - 1; }
            else buf.put('&');
        }
        else
            buf.put(s[i]);
    }
    return buf.data;
}

/// The character entity at the start of `s` (which starts with '&'),
/// and its length in `len`; `len` is 0 if there is none.
private string entity(string s, out size_t len)
{
    import std.utf : encode;
    import std.conv : to, ConvException;

    auto semi = s.indexOf(';');
    if (semi < 2 || semi > 33) return null;
    auto name = s[1 .. semi];
    string r;
    if (name[0] == '#')
    {
        bool hex = name.length > 1 && (name[1] == 'x' || name[1] == 'X');
        auto digits = name[hex ? 2 : 1 .. $];
        if (digits.length == 0 || digits.length > (hex ? 6 : 7)) return null;
        dchar c;
        try
            c = cast(dchar) digits.to!uint(hex ? 16 : 10);
        catch (ConvException) return null;
        if (c == 0 || c > 0x10FFFF || (c >= 0xD800 && c <= 0xDFFF)) c = '\uFFFD';
        char[4] tmp;
        r = tmp[0 .. encode(tmp, c)].idup;
    }
    else
    {
        r = htmlEntity(name);
        if (r is null) return null;
    }
    len = semi + 1;
    return r;
}

// One item of the inline parser's working list: text, a run of
// emphasis delimiters, or a finished inline.
private struct Tok
{
    enum Kind { text, delim, node }
    Kind kind;
    string text;
    MdInline node;
    char ch;
    int count, origCount;
    bool canOpen, canClose;
}

/**
 * Parses the inline Markdown `s` (a paragraph's, heading's or table
 * cell's text) into inlines, with `refs` for reference links.
 */
MdInline[] parseInlines(string s, MdLinkRef[string] refs = null)
{
    return InlineParser(s, refs).run();
}

private struct InlineParser
{
    string s;
    MdLinkRef[string] refs;
    size_t pos;
    Tok[] toks;
    char[] text;

    // An open `[` or `![`, at toks[tok]; `start` is where its text begins.
    struct Bracket
    {
        size_t tok, start;
        bool image, active = true;
    }
    Bracket[] brackets;

    this(string s, MdLinkRef[string] refs)
    {
        this.s = s;
        this.refs = refs;
    }

    void flushText()
    {
        if (text.length)
        {
            Tok t;
            t.kind = Tok.Kind.text;
            t.text = text.idup;
            toks ~= t;
            text.length = 0;
        }
    }

    void addNode(MdInline n)
    {
        flushText();
        Tok t;
        t.kind = Tok.Kind.node;
        t.node = n;
        toks ~= t;
    }

    MdInline[] run()
    {
        while (pos < s.length)
        {
            char c = s[pos];
            switch (c)
            {
            case '\\':
                if (pos + 1 < s.length && s[pos + 1] == '\n')
                {
                    addNode(MdInline(MdInlineKind.hardBreak));
                    pos += 2;
                    skipLeadingSpaces();
                }
                else if (pos + 1 < s.length && isAsciiPunct(s[pos + 1]))
                {
                    text ~= s[pos + 1];
                    pos += 2;
                }
                else
                {
                    text ~= c;
                    pos++;
                }
                break;
            case '`':
                codeSpan();
                break;
            case '*', '_', '~':
                delimRun();
                break;
            case '!':
                if (pos + 1 < s.length && s[pos + 1] == '[')
                {
                    openBracket(true);
                    break;
                }
                text ~= c;
                pos++;
                break;
            case '[':
                openBracket(false);
                break;
            case ']':
                closeBracket();
                break;
            case '<':
                if (angle()) break;
                text ~= c;
                pos++;
                break;
            case '&':
                size_t len;
                auto e = entity(s[pos .. $], len);
                if (len)
                {
                    text ~= e;
                    pos += len;
                }
                else
                {
                    text ~= c;
                    pos++;
                }
                break;
            case '\n':
                // Two or more trailing spaces make a hard break.
                size_t sp;
                while (text.length > sp && text[$ - 1 - sp] == ' ') sp++;
                text.length -= sp;
                addNode(MdInline(sp >= 2 ? MdInlineKind.hardBreak : MdInlineKind.softBreak));
                pos++;
                skipLeadingSpaces();
                break;
            case 'h':
                if (bareUrl()) break;
                text ~= c;
                pos++;
                break;
            default:
                text ~= c;
                pos++;
                break;
            }
        }
        flushText();
        processEmphasis(0);
        return toInlines(toks);
    }

    void skipLeadingSpaces()
    {
        while (pos < s.length && s[pos] == ' ') pos++;
    }

    void codeSpan()
    {
        size_t n;
        while (pos + n < s.length && s[pos + n] == '`') n++;
        // Find a closing run of exactly n backticks.
        size_t i = pos + n;
        while (i < s.length)
        {
            if (s[i] == '`')
            {
                size_t m;
                while (i + m < s.length && s[i + m] == '`') m++;
                if (m == n)
                {
                    auto code = s[pos + n .. i].replace("\n", " ");
                    if (code.length >= 2 && code[0] == ' ' && code[$ - 1] == ' ' && code.strip().length)
                        code = code[1 .. $ - 1];
                    addNode(MdInline(MdInlineKind.code, code));
                    pos = i + m;
                    return;
                }
                i += m;
            }
            else
                i++;
        }
        text ~= s[pos .. pos + n];
        pos += n;
    }

    void delimRun()
    {
        import std.uni : uniIsWhite = isWhite, uniIsPunct = isPunctuation, isSymbol;
        import std.utf : decode, strideBack;

        char c = s[pos];
        size_t n;
        while (pos + n < s.length && s[pos + n] == c) n++;

        dchar before = ' ', after = ' ';
        if (pos > 0)
        {
            size_t k = pos - strideBack(s, pos);
            before = decode(s, k);
        }
        if (pos + n < s.length)
        {
            size_t k = pos + n;
            after = decode(s, k);
        }
        bool punct(dchar d) { return uniIsPunct(d) || isSymbol(d); }
        bool afterWhite = uniIsWhite(after), beforeWhite = uniIsWhite(before);
        bool leftFlanking = !afterWhite && (!punct(after) || beforeWhite || punct(before));
        bool rightFlanking = !beforeWhite && (!punct(before) || afterWhite || punct(after));

        Tok t;
        t.kind = Tok.Kind.delim;
        t.ch = c;
        t.count = t.origCount = cast(int) n;
        t.text = s[pos .. pos + n];
        if (c == '_')
        {
            t.canOpen = leftFlanking && (!rightFlanking || punct(before));
            t.canClose = rightFlanking && (!leftFlanking || punct(after));
        }
        else
        {
            t.canOpen = leftFlanking;
            t.canClose = rightFlanking;
        }
        if (c == '~' && n > 2)
            t.canOpen = t.canClose = false;
        flushText();
        toks ~= t;
        pos += n;
    }

    void openBracket(bool image)
    {
        flushText();
        Tok t;
        t.kind = Tok.Kind.text;
        t.text = image ? "![" : "[";
        brackets ~= Bracket(toks.length, pos + t.text.length, image);
        toks ~= t;
        pos += t.text.length;
    }

    // `]`: CommonMark's "look for link or image". The nearest open
    // bracket, if active, makes a link or image with what follows it,
    // when a target comes next: `(url "title")`, `[label]`, `[]`, or the
    // bracket's own text as a reference label.
    void closeBracket()
    {
        size_t close = pos;
        pos++;
        if (brackets.length == 0 || !brackets[$ - 1].active)
        {
            if (brackets.length) brackets.length--;
            text ~= ']';
            return;
        }
        auto br = brackets[$ - 1];
        brackets.length--;

        string url, title;
        size_t end;
        if ((end = inlineTarget(pos, url, title)) == 0)
        {
            string key = s[br.start .. close], label;
            size_t i = pos;
            if (scanLabel(s, i, label))
            {
                key = label;
                end = i;
            }
            else if (s[pos .. $].startsWith("[]"))
                end = pos + 2;
            else
                end = pos;
            auto r = key.length <= 999 ? normalizeLabel(key) in refs : null;
            if (r is null)
            {
                text ~= ']';
                return;
            }
            url = r.url;
            title = r.title;
        }

        flushText();
        processEmphasis(br.tok + 1);
        MdInline n;
        n.url = url;
        n.title = title;
        auto inner = toInlines(toks[br.tok + 1 .. $]);
        toks.length = br.tok;
        if (br.image)
        {
            n.kind = MdInlineKind.image;
            n.text = plainText(inner);
        }
        else
        {
            n.kind = MdInlineKind.link;
            n.children = inner;
            // No links inside links.
            foreach (ref b; brackets)
                if (!b.image) b.active = false;
        }
        addNode(n);
        pos = end;
    }

    /// Parses `(url "title")` at `p`; returns the position after it, or 0.
    size_t inlineTarget(size_t p, out string url, out string title)
    {
        if (p >= s.length || s[p] != '(') return 0;
        size_t i = p + 1;
        while (i < s.length && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n')) i++;
        if (i < s.length && s[i] != ')')
        {
            if (!scanDest(s, i, url)) return 0;
            size_t j = i;
            bool space;
            while (j < s.length && (s[j] == ' ' || s[j] == '\t' || s[j] == '\n')) { j++; space = true; }
            if (space && j < s.length && s[j] != ')')
            {
                if (!scanTitle(s, j, title)) return 0;
                while (j < s.length && (s[j] == ' ' || s[j] == '\t' || s[j] == '\n')) j++;
            }
            i = j;
        }
        if (i >= s.length || s[i] != ')') return 0;
        return i + 1;
    }

    /// `<...>`: an autolink, or raw HTML: a tag, comment, processing
    /// instruction, declaration or CDATA section. `<br>` is a hard break
    /// and `<img src="..." alt="...">` an image; other HTML is dropped.
    /// False if it is none of these, and the `<` is text.
    bool angle()
    {
        size_t end;
        if ((end = scanAutolink(s, pos)) != 0)
        {
            auto inner = s[pos + 1 .. end - 1];
            MdInline n = MdInline(MdInlineKind.link);
            n.url = inner.canFind(':') ? inner : "mailto:" ~ inner;
            n.children = [MdInline(MdInlineKind.text, inner)];
            addNode(n);
            pos = end;
            return true;
        }
        string name;
        string[string] attrs;
        if ((end = scanHtml(s, pos, name, attrs)) == 0) return false;
        if (name == "br")
            addNode(MdInline(MdInlineKind.hardBreak));
        else if (name == "img" && "src" in attrs)
        {
            MdInline n = MdInline(MdInlineKind.image);
            n.url = attrs["src"];
            n.text = attrs.get("alt", "");
            n.title = attrs.get("title", "");
            addNode(n);
        }
        pos = end;
        return true;
    }

    /// A bare `http://` or `https://` URL, at the start of a word.
    bool bareUrl()
    {
        auto rest = s[pos .. $];
        if (!rest.startsWith("http://") && !rest.startsWith("https://")) return false;
        if (pos > 0 && (isAlphaNum(s[pos - 1]) || s[pos - 1] == '/' || s[pos - 1] == '('
                && pos > 1 && s[pos - 2] == ']'))
            return false;
        size_t i;
        while (i < rest.length && !isWhite(rest[i]) && rest[i] != '<') i++;
        // Trailing punctuation is not part of the URL.
        while (i > 0 && ".,:;!?\"'*_~".canFind(rest[i - 1])) i--;
        if (i > 0 && rest[i - 1] == ')' && rest[0 .. i].count('(') < rest[0 .. i].count(')')) i--;
        auto url = rest[0 .. i];
        if (url.length <= "https://".length) return false;
        MdInline n = MdInline(MdInlineKind.link);
        n.url = url;
        n.children = [MdInline(MdInlineKind.text, url)];
        addNode(n);
        pos += i;
        return true;
    }

    /// CommonMark's "process emphasis": matches closing delimiter runs
    /// with opening ones after index `bottom`, turning each matched pair
    /// and what lies between into one emphasis, strong or strike node.
    void processEmphasis(size_t bottom)
    {
        size_t c = bottom;
        while (c < toks.length)
        {
            auto closer = &toks[c];
            if (closer.kind != Tok.Kind.delim || !closer.canClose || closer.count == 0)
            {
                c++;
                continue;
            }
            // Look back for an opener.
            ptrdiff_t o = cast(ptrdiff_t) c - 1;
            bool found;
            for (; o >= cast(ptrdiff_t) bottom; o--)
            {
                auto op = &toks[o];
                if (op.kind != Tok.Kind.delim || op.ch != closer.ch || !op.canOpen || op.count == 0)
                    continue;
                if (closer.ch == '~')
                {
                    if (op.count != closer.count) continue;
                }
                else if ((op.canClose || closer.canOpen) && (op.origCount + closer.origCount) % 3 == 0
                    && !(op.origCount % 3 == 0 && closer.origCount % 3 == 0))
                    continue;
                found = true;
                break;
            }
            if (!found)
            {
                c++;
                continue;
            }

            auto opener = &toks[o];
            int use = closer.ch == '~' ? closer.count
                : (opener.count >= 2 && closer.count >= 2 ? 2 : 1);
            MdInline n;
            n.kind = closer.ch == '~' ? MdInlineKind.strike
                : use == 2 ? MdInlineKind.strong : MdInlineKind.emphasis;
            n.children = toInlines(toks[o + 1 .. c]);
            opener.count -= use;
            closer.count -= use;
            opener.text = opener.text[0 .. opener.count];
            closer.text = closer.text[0 .. closer.count];

            Tok node;
            node.kind = Tok.Kind.node;
            node.node = n;

            // Replace toks[o+1 .. c] with the node, and drop the opener
            // and closer once used up.
            Tok[] before = toks[0 .. o + 1];
            Tok[] after = toks[c .. $];
            bool dropOpener = opener.count == 0;
            bool dropCloser = after[0].count == 0;
            Tok[] merged = (dropOpener ? before[0 .. $ - 1] : before) ~ node
                ~ (dropCloser ? after[1 .. $] : after);
            size_t nodeIndex = dropOpener ? o : o + 1;
            toks = merged;
            c = dropCloser ? nodeIndex + 1 : nodeIndex + 1;
        }
    }
}

/// An autolink at `s[p]`: `<scheme:...>` (a scheme of 2 to 32
/// letters, digits, `+`, `.` or `-`, starting with a letter; no spaces,
/// control characters, `<` or `>` after it) or `<name@host>`. The
/// position just past it, or 0.
private size_t scanAutolink(string s, size_t p)
{
    size_t i = p + 1;
    if (i < s.length && isAlpha(s[i]))
    {
        size_t j = i + 1;
        while (j < s.length && (isAlphaNum(s[j]) || s[j] == '+' || s[j] == '.' || s[j] == '-')) j++;
        if (j < s.length && s[j] == ':' && j - i >= 2 && j - i <= 32)
        {
            for (j++; j < s.length; j++)
            {
                char c = s[j];
                if (c == '>') return j + 1;
                if (c <= ' ' || c == 0x7f || c == '<') break;
            }
        }
    }
    // An e-mail address.
    size_t j = i;
    while (j < s.length && (isAlphaNum(s[j]) || ".!#$%&'*+/=?^_`{|}~-".canFind(s[j]))) j++;
    if (j == i || j >= s.length || s[j] != '@') return 0;
    j++;
    while (true)
    {
        size_t st = j;
        while (j < s.length && (isAlphaNum(s[j]) || s[j] == '-')) j++;
        if (j == st || j - st > 63 || s[st] == '-' || s[j - 1] == '-') return 0;
        if (j < s.length && s[j] == '.') { j++; continue; }
        break;
    }
    return j < s.length && s[j] == '>' ? j + 1 : 0;
}

/// Raw HTML at `s[p]`: an open or closing tag, `<!-- comment -->`,
/// `<?...?>`, `<!DECLARATION ...>` or `<![CDATA[...]]>`. The position
/// just past it, or 0. For a tag, `name` is its lower-case name (with a
/// leading `/` for a closing tag) and `attrs` its attributes.
private size_t scanHtml(string s, size_t p, out string name, out string[string] attrs)
{
    auto rest = s[p .. $];
    size_t until(string start, string stop)
    {
        auto e = rest[start.length .. $].indexOf(stop);
        return e < 0 ? 0 : p + start.length + e + stop.length;
    }
    if (rest.startsWith("<!-->")) return p + 5;
    if (rest.startsWith("<!--->")) return p + 6;
    if (rest.startsWith("<!--")) return until("<!--", "-->");
    if (rest.startsWith("<?")) return until("<?", "?>");
    if (rest.startsWith("<![CDATA[")) return until("<![CDATA[", "]]>");
    if (rest.length > 2 && rest[1] == '!' && isAlpha(rest[2])) return until("<!", ">");

    size_t i = p + 1;
    bool closing = i < s.length && s[i] == '/';
    if (closing) i++;
    size_t st = i;
    if (i >= s.length || !isAlpha(s[i])) return 0;
    while (i < s.length && (isAlphaNum(s[i]) || s[i] == '-')) i++;
    name = (closing ? "/" : "") ~ s[st .. i].toLower();

    bool space()
    {
        size_t b = i;
        while (i < s.length && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n')) i++;
        return i > b;
    }
    if (closing)
    {
        space();
        return i < s.length && s[i] == '>' ? i + 1 : 0;
    }
    while (true)
    {
        bool sp = space();
        if (i < s.length && s[i] == '>') return i + 1;
        if (s[i .. $].startsWith("/>")) return i + 2;
        if (!sp || i >= s.length) return 0;
        // An attribute: a name, and maybe = and a value.
        size_t ns = i;
        if (!(isAlpha(s[i]) || s[i] == '_' || s[i] == ':')) return 0;
        while (i < s.length && (isAlphaNum(s[i]) || "_.:-".canFind(s[i]))) i++;
        string attr = s[ns .. i].toLower(), value;
        size_t save = i;
        space();
        if (i < s.length && s[i] == '=')
        {
            i++;
            space();
            if (i >= s.length) return 0;
            if (s[i] == '"' || s[i] == '\'')
            {
                auto e = s[i + 1 .. $].indexOf(s[i]);
                if (e < 0) return 0;
                value = s[i + 1 .. i + 1 + e];
                i += e + 2;
            }
            else
            {
                size_t vs = i;
                while (i < s.length && !(s[i] <= ' ' || "\"'=<>`".canFind(s[i]))) i++;
                if (i == vs) return 0;
                value = s[vs .. i];
            }
        }
        else
            i = save;
        attrs[attr] = unescape(value);
    }
}

private MdInline[] toInlines(Tok[] toks)
{
    MdInline[] r;
    void addText(string t)
    {
        if (t.length == 0) return;
        if (r.length && r[$ - 1].kind == MdInlineKind.text)
            r[$ - 1].text ~= t;
        else
            r ~= MdInline(MdInlineKind.text, t);
    }
    foreach (ref t; toks)
    {
        final switch (t.kind)
        {
        case Tok.Kind.text:
            addText(t.text);
            break;
        case Tok.Kind.delim:
            addText(t.text);
            break;
        case Tok.Kind.node:
            r ~= t.node;
            break;
        }
    }
    return r;
}

private size_t count(string s, char c)
{
    size_t n;
    foreach (ch; s) if (ch == c) n++;
    return n;
}

// ---------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------

version (unittest)
{
    // A compact rendering of inlines for the tests: *em*, **strong**,
    // ~~strike~~, `code`, [text](url), ![alt](url), / for a hard break.
    private string show(const(MdInline)[] list)
    {
        auto b = appender!string();
        foreach (ref i; list)
        {
            final switch (i.kind)
            {
            case MdInlineKind.text: b.put(i.text); break;
            case MdInlineKind.code: b.put("`" ~ i.text ~ "`"); break;
            case MdInlineKind.emphasis: b.put("*" ~ show(i.children) ~ "*"); break;
            case MdInlineKind.strong: b.put("**" ~ show(i.children) ~ "**"); break;
            case MdInlineKind.strike: b.put("~~" ~ show(i.children) ~ "~~"); break;
            case MdInlineKind.link: b.put("[" ~ show(i.children) ~ "](" ~ i.url ~ ")"); break;
            case MdInlineKind.image: b.put("![" ~ i.text ~ "](" ~ i.url ~ ")"); break;
            case MdInlineKind.softBreak: b.put(" "); break;
            case MdInlineKind.hardBreak: b.put("/"); break;
            }
        }
        return b.data;
    }

    private string inl(string s) { return show(parseInlines(s)); }
}

unittest
{
    // Emphasis, strong, strikethrough, code.
    assert(inl("a *b* c") == "a *b* c");
    assert(inl("a **b** c") == "a **b** c");
    assert(inl("a _b_ c") == "a *b* c");
    assert(inl("***both***") == "***both***" || inl("***both***") == "*" ~ "**both**" ~ "*");
    assert(inl("**a *b* c**") == "**a *b* c**");
    assert(inl("snake_case_name") == "snake_case_name");
    assert(inl("2 * 3 * 4") == "2 * 3 * 4");
    assert(inl("~~gone~~") == "~~gone~~");
    assert(inl("`a *b*`") == "`a *b*`");
    assert(inl("`` a`b ``") == "`a`b`");
    assert(inl("\\*not\\*") == "*not*");
    assert(inl("*unclosed") == "*unclosed");
}

unittest
{
    // Links, images, autolinks, bare URLs, references.
    assert(inl("[fltk](https://www.fltk.org/)") == "[fltk](https://www.fltk.org/)");
    assert(inl("[a *b*](x.md \"t\")") == "[a *b*](x.md)");
    assert(inl("![pic](img/a.png)") == "![pic](img/a.png)");
    assert(inl("<https://dlang.org>") == "[https://dlang.org](https://dlang.org)");
    assert(inl("see https://dlang.org.") == "see [https://dlang.org](https://dlang.org).");
    assert(inl("a<br>b") == "a/b");
    assert(inl("a <!-- hidden --> b") == "a  b");
    auto refs = ["ref": MdLinkRef("target.md", "")];
    assert(show(parseInlines("[text][ref] and [ref]", refs)) == "[text](target.md) and [ref](target.md)");
    assert(inl("[no ref]") == "[no ref]");
    assert(inl("&copy; &amp; &#65;") == "© & A");
}

unittest
{
    // Line breaks.
    assert(inl("a  \nb") == "a/b");
    assert(inl("a\\\nb") == "a/b");
    assert(inl("a\nb") == "a b");
}

unittest
{
    // Headings, paragraphs, rules, code blocks.
    auto d = parseMarkdown("# Title #\n\nSome *text*\nmore.\n\nSub\n---\n\n***\n\n```d\nvoid main() {}\n```\n\n    indented\n");
    assert(d.children.length == 6);
    assert(d.children[0].kind == MdBlockKind.heading && d.children[0].level == 1);
    assert(show(d.children[0].inlines) == "Title");
    assert(d.children[0].id == "title");
    assert(d.children[1].kind == MdBlockKind.paragraph);
    assert(show(d.children[1].inlines) == "Some *text* more.");
    assert(d.children[2].kind == MdBlockKind.heading && d.children[2].level == 2);
    assert(d.children[3].kind == MdBlockKind.rule);
    assert(d.children[4].kind == MdBlockKind.codeBlock && d.children[4].info == "d");
    assert(d.children[4].text == "void main() {}\n");
    assert(d.children[5].kind == MdBlockKind.codeBlock && d.children[5].text == "indented\n");
}

unittest
{
    // Lists: tight, loose, nested, ordered.
    auto d = parseMarkdown("- a\n- b\n  - c\n- d\n\n1. one\n2. two\n\n3) x\n\n4) y\n");
    assert(d.children.length == 3);
    auto l = d.children[0];
    assert(l.kind == MdBlockKind.list && !l.ordered && l.tight);
    assert(l.children.length == 3);
    assert(l.children[1].children.length == 2);
    assert(l.children[1].children[1].kind == MdBlockKind.list);
    auto o = d.children[1];
    assert(o.ordered && o.start == 1 && o.tight && o.children.length == 2);
    auto loose = d.children[2];
    assert(loose.ordered && loose.start == 3 && !loose.tight && loose.children.length == 2);

    // A lazy continuation line stays in its item.
    auto lazy_ = parseMarkdown("- first line\ncontinued\n- second\n");
    assert(lazy_.children.length == 1 && lazy_.children[0].children.length == 2);
    assert(show(lazy_.children[0].children[0].children[0].inlines) == "first line continued");
}

unittest
{
    // Block quotes and tables.
    auto d = parseMarkdown("> quoted\nlazy\n\n| A | B |\n|:--|--:|\n| 1 | `x\\|y` |\n| 2 |\n");
    assert(d.children.length == 2);
    assert(d.children[0].kind == MdBlockKind.quote);
    assert(show(d.children[0].children[0].inlines) == "quoted lazy");
    auto t = d.children[1];
    assert(t.kind == MdBlockKind.table);
    assert(t.aligns == [MdAlign.left, MdAlign.right]);
    assert(t.rows.length == 3);
    assert(show(t.rows[1][1]) == "`x|y`");
    assert(t.rows[2].length == 2 && t.rows[2][1].length == 0);
}

unittest
{
    // Reference definitions are hidden, also the [//]: # comment idiom;
    // HTML comments are skipped.
    auto d = parseMarkdown("# T\n\n[//]: # (a note)\n\n<!-- x\ny -->\n\nSee [the docs][d].\n\n[d]: docs/README.md\n");
    assert(d.children.length == 2);
    assert(show(d.children[1].inlines) == "See [the docs](docs/README.md).");
}

unittest
{
    // Heading ids, as GitHub makes them.
    assert(headingSlug("Where fldtk is") == "where-fldtk-is");
    assert(headingSlug("1. Opening a terminal") == "1-opening-a-terminal");
    assert(headingSlug("C++ & D: `code`") == "c--d-code");
    auto d = parseMarkdown("## Notes\n\n## Notes\n");
    assert(d.children[0].id == "notes" && d.children[1].id == "notes-1");
}

unittest
{
    // Links don't nest; raw HTML and autolinks bind before brackets.
    assert(inl("[foo [bar](/uri)](/uri)") == "[foo [bar](/uri)](/uri)");
    assert(inl("![[[foo](uri1)](uri2)](uri3)") == "![[foo](uri2)](uri3)");
    assert(inl("[foo <bar attr=\"](baz)\">") == "[foo ");
    assert(inl("[a](<b)c") == "[a](<b)c");
    assert(inl("[link](/url \"title \\\"&quot;\")") == "[link](/url)");
    assert(inl("<img src=\"a.png\" alt=\"A\">") == "![A](a.png)");
    assert(inl("<m:abc> <foo.bar> <a@b.c>") == "<m:abc> <foo.bar> [a@b.c](mailto:a@b.c)");
    assert(inl("&HilbertSpace; &ngE; &nosuch;") == "ℋ ≧̸ &nosuch;");
}

unittest
{
    // Definitions over several lines; labels fold case fully.
    auto d = parseMarkdown("[foo]:\n/url\n  'the title'\n[ẞ]: /ss\n\n[foo] [SS]\n");
    assert(d.children.length == 1);
    assert(show(d.children[0].inlines) == "[foo](/url) [SS](/ss)");
    assert(d.children[0].inlines[0].title == "the title");
    assert(parseMarkdown("[foo]: <bar>(baz)\n").children[0].kind == MdBlockKind.paragraph);
}

unittest
{
    // A rule ends a list; lazy lines are only paragraph text; an item
    // starts with at most one blank line.
    auto d = parseMarkdown("* a\n* * *\n* b\n");
    assert(d.children.length == 3 && d.children[1].kind == MdBlockKind.rule);
    d = parseMarkdown("> foo\nbar\n===\n");
    assert(d.children.length == 1 && show(d.children[0].children[0].inlines) == "foo bar ===");
    d = parseMarkdown(">     code\n    more\n");
    assert(d.children.length == 2 && d.children[1].kind == MdBlockKind.codeBlock);
    d = parseMarkdown("   - d\n    - e\n");
    assert(show(d.children[0].children[0].children[0].inlines) == "d - e");
    d = parseMarkdown("-\n\n  foo\n");
    assert(d.children.length == 2 && d.children[0].children[0].children.length == 0);
}

unittest
{
    // Every block knows the source lines it came from, nested ones too.
    auto d = parseMarkdown("# Title\n\nOne\ntwo\n\n> quoted\n> more\n\n- a\n- b\n\n  b's paragraph\n\n"
        ~ "```D\ncode\n```\n| x | y |\n|---|---|\n| 1 | 2 |\n");
    auto c = d.children;
    assert(c.length == 6);
    assert(c[0].kind == MdBlockKind.heading && c[0].line == 0 && c[0].lineCount == 1);
    assert(c[1].kind == MdBlockKind.paragraph && c[1].line == 2 && c[1].lineCount == 2);
    assert(c[2].kind == MdBlockKind.quote && c[2].line == 5 && c[2].lineCount == 2);
    assert(c[2].children[0].line == 5);
    auto list = c[3];
    assert(list.kind == MdBlockKind.list && list.line == 8);
    assert(list.children[0].line == 8 && list.children[1].line == 9);
    assert(list.children[1].children[1].kind == MdBlockKind.paragraph);
    assert(list.children[1].children[1].line == 11);
    assert(c[4].kind == MdBlockKind.codeBlock && c[4].line == 13 && c[4].lineCount == 3);
    assert(c[5].kind == MdBlockKind.table && c[5].line == 16 && c[5].lineCount == 3);
}
