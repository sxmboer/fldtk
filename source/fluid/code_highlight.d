/**
 * D syntax highlighting for the code-snippet editors and the Code View, in the
 * spirit of real Fluid's `fluid::widget::Code_Editor` (a `TextEditor`
 * whose text buffer drives a parallel style buffer through a lexer). The token
 * classes and the words in each follow the D definition in nano's syntax
 * file (`syntax/d.syntax`): keywords and operators, exception and attribute
 * words, constants, `import`, the runtime types, operator-overload names, D
 * properties such as `.length`, comments (line, block and nested, with
 * documentation sections), strings and character literals with their
 * escapes, and punctuation. That file has no entry for the core keywords and
 * types (`if`, `else`, `for`, `int`, `void`, `class`, `struct`, ...); the
 * ones `d.nanorc` lists are added to the keyword class (`addedKeywordWords`). nano draws these on a dark terminal; the colors
 * here keep the same groups but are chosen for the white text background of
 * Fluid's editors.
 *
 * `styleParse()` is the lexer, a pure function over text; `enableHighlighting()`
 * attaches it to a `TextDisplay`, and `enableAutoIndent()` gives a
 * `TextEditor` FLTK's Enter behavior (the new line keeps the previous
 * line's indentation).
 *
 * The style letters are the index into `styleTable()` plus `'A'`.
 */
module fluid.code_highlight;

import fl;

/// Style letters, in `styleTable()` order.
enum : char
{
    stylePlain = 'A',       /// everything else
    styleKeyword = 'B',     /// keywords, types, properties (nano: yellow)
    styleException = 'C',   /// catch/throw/nothrow, @safe and friends, __FILE__ (red)
    styleConstant = 'D',    /// true/false/null/this/super (bright red)
    styleImport = 'E',      /// import (magenta)
    styleComment = 'F',     /// comments (brown)
    styleString = 'G',      /// string literals (green)
    styleEscape = 'H',      /// character literals, escapes, format specifiers (bright green)
    stylePunct = 'I',       /// ( ) [ ] { } , : ? $ (bright cyan)
    styleSemicolon = 'J',   /// ; and Object/Exception/... (bright magenta)
    styleOpName = 'K',      /// opAdd, opIndex, ... (gray)
    styleOperator = 'L',    /// operators (yellow)
    styleDocSection = 'M',  /// Params:, Returns:, ... inside documentation comments (red)
}

// The words of each class, generated from nano's syntax/d.syntax.
private immutable string[] keywordWords = [
    "abstract", "alias", "align", "asm", "assert", "body", "break", "byte", "cast",
    "cdouble", "cent", "cfloat", "continue", "creal", "dchar", "debug", "delegate",
    "delete", "deprecated", "dstring", "export", "final", "foreach", "foreach_reverse",
    "function", "goto", "idouble", "ifloat", "immutable", "in", "inout", "interface",
    "invariant", "ireal", "is", "lazy", "macro", "mixin", "module", "new", "out",
    "override", "package", "pragma", "pure", "real", "ref", "return", "scope", "shared",
    "string", "synchronized", "typeid", "typeof", "ubyte", "ucent", "uint", "ulong",
    "unittest", "ushort", "version", "wchar", "with", "wstring",
];

private immutable string[] exceptionWords = [
    "@disable", "@live", "@nogc", "@safe", "@system", "@trusted", "__DATE__", "__EOF__",
    "__FILE_FULL_PATH__", "__FILE__", "__FUNCTION__", "__LINE__", "__MODULE__",
    "__PRETTY_FUNCTION__", "__TIMESTAMP__", "__TIME__", "__VENDOR__", "__VERSION__",
    "catch", "finally", "nothrow", "throw", "try",
];

private immutable string[] constantWords = [
    "_argptr", "_arguments", "false", "null", "super", "this", "true",
];

private immutable string[] importWords = [
    "import",
];

private immutable string[] runtimeTypeWords = [
    "ClassInfo", "Error", "Exception", "Interface", "Object", "OffsetTypeInfo", "TypeInfo",
];

private immutable string[] operatorNameWords = [
    "opAdd", "opAddAssign", "opAdd_r", "opAnd", "opAndAssign", "opAnd_r", "opApply",
    "opAssign", "opCall", "opCast", "opCat", "opCatAssign", "opCat_r", "opCmp", "opCom",
    "opDiv", "opDivAssign", "opDiv_r", "opEquals", "opIn", "opIn_r", "opIndex",
    "opIndexAssign", "opMod", "opModAssign", "opMod_r", "opMul", "opMulAssign", "opMul_r",
    "opNeg", "opOr", "opOrAssign", "opOr_r", "opPos", "opPostDec", "opPostInc", "opShl",
    "opShlAssign", "opShl_r", "opShr", "opShrAssign", "opShr_r", "opSlice",
    "opSliceAssign", "opSub", "opSubAssign", "opSub_r", "opUShr", "opUShrAssign",
    "opUShr_r", "opXor", "opXorAssign", "opXor_r",
];

private immutable string[] propertyWords = [
    "alignof", "dig", "dup", "epsilon", "idup", "im", "infinity", "init", "keys",
    "length", "mangleof", "mant_dig", "max", "max_10_exp", "max_exp", "min", "min_10_exp",
    "min_exp", "nan", "offsetof", "ptr", "re", "rehash", "reverse", "sizeof", "sort",
    "stringof", "values",
];

private immutable string[] docSectionWords = [
    "Authors:", "Author:", "BUGS:", "Bugs:", "Date:", "Deprecated:", "Examples:",
    "History:", "License:", "Returns:", "See_Also:", "Standards:", "Throws:", "Version:",
    "Copyright:", "Params:", "Macros:", "TODO:", "FIXME:", "Note:",
];


/// Core D keywords and types that nano's `d.syntax` has no entry for, so
/// they would otherwise be plain text (its `d.nanorc` does list them). Styled
/// like the keywords above.
private immutable string[] addedKeywordWords = [
    "auto", "bool", "case", "char", "class", "const", "default", "do", "double", "else", "enum",
    "extern", "float", "for", "if", "int", "long", "private", "protected", "public", "short",
    "static", "struct", "switch", "template", "union", "void", "while",
];

/// The style of a whole word, built once from the tables above.
private char[string] wordStyles()
{
    static char[string] table;
    if (table.length == 0)
    {
        foreach (w; keywordWords) table[w] = styleKeyword;
        foreach (w; addedKeywordWords) table[w] = styleKeyword;
        foreach (w; exceptionWords) table[w] = styleException;
        foreach (w; constantWords) table[w] = styleConstant;
        foreach (w; importWords) table[w] = styleImport;
        foreach (w; runtimeTypeWords) table[w] = styleSemicolon;
        foreach (w; operatorNameWords) table[w] = styleOpName;
    }
    return table;
}

private bool[string] propertyNames()
{
    static bool[string] table;
    if (table.length == 0)
        foreach (w; propertyWords) table[w] = true;
    return table;
}

private bool isIdentStart(char c)
{
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_' || c >= 0x80;
}

private bool isIdentChar(char c)
{
    return isIdentStart(c) || (c >= '0' && c <= '9');
}

private bool isHexDigit(char c)
{
    return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
}

/// Word attributes written `@name` in nano's file (`@safe`, `@nogc`, ...).
private immutable string[] attributeWords = [
    "@disable", "@nogc", "@live", "@safe", "@system", "@trusted",
];

private void fill(char[] style, size_t from, size_t to, char s)
{
    style[from .. to] = s;
}

/// Length of a backslash escape starting at `text[i]` (which is `\`), inside a
/// string or character literal: `\n`, `\0`, octal, `\xHH`, `\uHHHH`,
/// `\UHHHHHHHH`, `\&name;`, or any other single character.
private size_t escapeLength(const(char)[] text, size_t i)
{
    immutable n = text.length;
    if (i + 1 >= n) return 1;
    char c = text[i + 1];
    size_t hex(size_t count)
    {
        size_t k = 0;
        while (k < count && i + 2 + k < n && isHexDigit(text[i + 2 + k])) k++;
        return 2 + k;
    }
    if (c == 'x') return hex(2);
    if (c == 'u') return hex(4);
    if (c == 'U') return hex(8);
    if (c >= '0' && c <= '7')
    {
        size_t k = 1;
        while (k < 3 && i + 1 + k < n && text[i + 1 + k] >= '0' && text[i + 1 + k] <= '7') k++;
        return 1 + k;
    }
    if (c == '&')
    {
        size_t k = 2;
        while (i + k < n && text[i + k] != ';' && text[i + k] != '"' && text[i + k] != '\n') k++;
        return i + k < n && text[i + k] == ';' ? k + 1 : 2;
    }
    // A multi-byte character after the backslash counts as one.
    size_t len = 2;
    if (c >= 0xC0)
        while (i + len < n && (text[i + len] & 0xC0) == 0x80) len++;
    return len;
}

/// Length of a printf-style format specifier at `text[i]` (which is `%`), or 0.
private size_t formatLength(const(char)[] text, size_t i)
{
    immutable n = text.length;
    size_t k = i + 1;
    if (k < n && text[k] == '%') return 2;
    while (k < n && (text[k] == '#' || text[k] == '0' || text[k] == ' ' || text[k] == '-'
        || text[k] == '+' || text[k] == ',')) k++;
    while (k < n && ((text[k] >= '0' && text[k] <= '9') || text[k] == '*')) k++;
    if (k < n && text[k] == '.')
    {
        k++;
        while (k < n && ((text[k] >= '0' && text[k] <= '9') || text[k] == '*')) k++;
    }
    while (k < n && (text[k] == 'h' || text[k] == 'l' || text[k] == 'L')) k++;
    if (k < n)
        foreach (t; "diuxXeEfgGoscpn")
            if (text[k] == t) return k + 1 - i;
    return 0;
}

/// Styles the rest of a string literal, from `i` (just after the opening
/// quote) up to and including the closing `close`. `raw` strings have no
/// escapes and no format specifiers styled; `hex` strings (`x"..."`) are
/// styled as escapes throughout. Returns the index after the literal.
private size_t scanString(const(char)[] text, char[] style, size_t i, char close, bool raw, bool hex)
{
    immutable n = text.length;
    while (i < n)
    {
        char c = text[i];
        if (c == close)
        {
            style[i] = hex ? styleEscape : styleString;
            return i + 1;
        }
        if (hex)
        {
            style[i++] = styleEscape;
            continue;
        }
        if (!raw && c == '\\')
        {
            size_t len = escapeLength(text, i);
            fill(style, i, i + len, styleEscape);
            i += len;
            continue;
        }
        if (!raw && c == '%')
        {
            size_t len = formatLength(text, i);
            if (len)
            {
                fill(style, i, i + len, styleEscape);
                i += len;
                continue;
            }
        }
        style[i++] = styleString;
    }
    return i;
}

/// Sets `style[i]` for every byte of `text` (`style.length == text.length`).
void styleParse(const(char)[] text, char[] style)
{
    assert(style.length == text.length);
    immutable n = text.length;
    size_t i = 0;
    while (i < n)
    {
        char c = text[i];
        char next = i + 1 < n ? text[i + 1] : '\0';

        // -- comments --
        if (c == '/' && next == '/')
        {
            size_t e = i;
            while (e < n && text[e] != '\n') e++;
            fill(style, i, e, styleComment);
            i = e;
            continue;
        }
        if (c == '/' && (next == '*' || next == '+'))
        {
            bool nested = next == '+';
            // `/**` (but not `/**/`) and `/++` (but not `/++/`) open documentation comments.
            bool doc = i + 2 < n && text[i + 2] == next && !(i + 3 < n && text[i + 3] == '/');
            size_t e = i + 2;
            int depth = 1;
            while (e < n)
            {
                if (nested && text[e] == '/' && e + 1 < n && text[e + 1] == '+') { depth++; e += 2; continue; }
                if (text[e] == next && e + 1 < n && text[e + 1] == '/')
                {
                    e += 2;
                    if (!nested || --depth == 0) break;
                    continue;
                }
                e++;
            }
            fill(style, i, e, styleComment);
            if (doc)
                styleDocSections(text, style, i, e);
            i = e;
            continue;
        }

        // -- strings and characters --
        if (c == '"' || c == '`')
        {
            style[i] = styleString;
            i = scanString(text, style, i + 1, c, c == '`', false);
            continue;
        }
        if ((c == 'r' || c == 'x') && next == '"' && (i == 0 || !isIdentChar(text[i - 1])))
        {
            style[i] = c == 'x' ? styleEscape : styleString;
            style[i + 1] = c == 'x' ? styleEscape : styleString;
            i = scanString(text, style, i + 2, '"', c == 'r', c == 'x');
            continue;
        }
        if (c == '\'')
        {
            size_t e = i + 1;
            if (e < n && text[e] == '\\')
                e += escapeLength(text, e);
            else if (e < n && text[e] != '\'' && text[e] != '\n')
            {
                e++;
                while (e < n && (text[e] & 0xC0) == 0x80) e++;
            }
            if (e < n && text[e] == '\'' && e > i + 1)
            {
                fill(style, i, e + 1, styleEscape);
                i = e + 1;
                continue;
            }
            style[i++] = stylePlain;
            continue;
        }

        // -- words --
        if (isIdentStart(c))
        {
            size_t e = i + 1;
            while (e < n && isIdentChar(text[e])) e++;
            char s = stylePlain;
            if (auto p = text[i .. e] in wordStyles())
                s = *p;
            fill(style, i, e, s);
            i = e;
            continue;
        }
        if (c == '@' && isIdentStart(next))
        {
            size_t e = i + 2;
            while (e < n && isIdentChar(text[e])) e++;
            char s = stylePlain;
            foreach (a; attributeWords)
                if (text[i .. e] == a) s = styleException;
            fill(style, i, e, s);
            i = e;
            continue;
        }
        if (c >= '0' && c <= '9')
        {
            // A number, including its suffix and digit separators, is one plain token.
            size_t e = i + 1;
            while (e < n && isIdentChar(text[e])) e++;
            fill(style, i, e, stylePlain);
            i = e;
            continue;
        }

        // -- dots: `...`, `..`, and D properties such as `.length` --
        if (c == '.')
        {
            if (next == '.')
            {
                size_t len = i + 2 < n && text[i + 2] == '.' ? 3 : 2;
                fill(style, i, i + len, styleOperator);
                i += len;
                continue;
            }
            if (isIdentStart(next))
            {
                size_t e = i + 2;
                while (e < n && isIdentChar(text[e])) e++;
                if (text[i + 1 .. e] in propertyNames())
                {
                    fill(style, i, e, styleKeyword);
                    i = e;
                    continue;
                }
            }
            style[i++] = stylePlain;
            continue;
        }

        // -- punctuation and operators --
        switch (c)
        {
        case '(': case ')': case '[': case ']': case '{': case '}':
        case ',': case ':': case '?': case '$':
            style[i++] = stylePunct;
            continue;
        case ';':
            style[i++] = styleSemicolon;
            continue;
        case '!': case '%': case '&': case '*': case '+': case '-': case '/': case '<':
        case '=': case '>': case '^': case '|': case '~':
            style[i++] = styleOperator;
            continue;
        default:
            style[i++] = stylePlain;
        }
    }
}

/// Inside a documentation comment `text[from .. to]`, restyles the section
/// names of `docSectionWords` (`Params:`, `Returns:`, ...).
private void styleDocSections(const(char)[] text, char[] style, size_t from, size_t to)
{
    size_t i = from;
    while (i < to)
    {
        if (!isIdentStart(text[i])) { i++; continue; }
        size_t e = i + 1;
        while (e < to && isIdentChar(text[e])) e++;
        if (e < to && text[e] == ':')
        {
            e++;
            foreach (w; docSectionWords)
                if (text[i .. e] == w)
                    fill(style, i, e, styleDocSection);
        }
        i = e;
    }
}

/// The style table for `styleParse()`'s letters, at `size` points.
StyleTableEntry[] styleTable(Fontsize size)
{
    return [
        StyleTableEntry(foregroundColor, courier, size),                                // A plain
        StyleTableEntry(rgbColor(0x8a, 0x66, 0x00), courierBold, size),           // B keyword
        StyleTableEntry(rgbColor(0xb0, 0x10, 0x10), courierBold, size),           // C exception
        StyleTableEntry(rgbColor(0xe0, 0x20, 0x20), courierBold, size),           // D constant
        StyleTableEntry(rgbColor(0x90, 0x20, 0x90), courierBold, size),           // E import
        StyleTableEntry(rgbColor(0x8b, 0x5a, 0x2b), courierItalic, size),         // F comment
        StyleTableEntry(rgbColor(0x10, 0x80, 0x10), courier, size),               // G string
        StyleTableEntry(rgbColor(0x00, 0xa0, 0x40), courier, size),               // H escape
        StyleTableEntry(rgbColor(0x00, 0x88, 0x99), courier, size),               // I punctuation
        StyleTableEntry(rgbColor(0xc0, 0x30, 0xc0), courier, size),               // J semicolon
        StyleTableEntry(rgbColor(0x70, 0x70, 0x70), courier, size),               // K operator names
        StyleTableEntry(rgbColor(0x8a, 0x66, 0x00), courier, size),               // L operators
        StyleTableEntry(rgbColor(0xb0, 0x10, 0x10), courierBoldItalic, size),     // M doc sections
    ];
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
    string styleOf(string text)
    {
        auto s = new char[text.length];
        styleParse(text, s);
        return cast(string) s;
    }
    // The style letters of `word` within `text`.
    string at(string text, string word)
    {
        import std.string : indexOf;
        auto s = styleOf(text);
        auto p = text.indexOf(word);
        assert(p >= 0, word);
        return s[p .. p + word.length];
    }

    // Keywords, exception words, constants, import and runtime types.
    assert(at("final class Foo", "final") == "BBBBB");
    assert(at("final class Foo", "class") == "BBBBB");
    assert(at("if (x) return int.max;", "if") == "BB");
    assert(at("void f()", "void") == "BBBB");
    assert(at("try { } catch (Exception e)", "catch") == "CCCCC");
    assert(at("x = null;", "null") == "DDDD");
    assert(at("import std.stdio;", "import") == "EEEEEE");
    assert(at("Object o;", "Object") == "JJJJJJ");
    assert(at("int opAdd(int x)", "opAdd") == "KKKKK");
    assert(at("void f() @safe {}", "@safe") == "CCCCC");
    assert(at("void f() @property {}", "@property") == "AAAAAAAAA");
    // Whole words only.
    assert(at("finalize(x)", "finalize") == "AAAAAAAA");
    assert(at("mynull", "mynull") == "AAAAAA");
    // Properties by their dot, and range operators.
    assert(at("a.length", ".length") == "BBBBBBB");
    assert(at("a.lengths", ".lengths") == "AAAAAAAA");
    assert(at("a[0 .. 2]", "..") == "LL");
    // Punctuation and operators.
    assert(styleOf("(a, b);") == "IAIAAIJ");
    assert(styleOf("a += b") == "AALLAA");
    // Comments: line, block, nested and documentation sections.
    assert(styleOf("a // x\nb") == "AAFFFF" ~ "AA");
    assert(at("a /* x */ b", "/* x */") == "FFFFFFF");
    assert(at("/+ a /+ b +/ c +/ d", "/+ a /+ b +/ c +/") == "FFFFFFFFFFFFFFFFF");
    assert(at("/** Params: x */", "Params:") == "MMMMMMM");
    assert(at("/* Params: x */", "Params:") == "FFFFFFF");
    // Strings, raw strings, escapes, format specifiers, character literals.
    assert(styleOf(`"a\n"`) == "GGHHG");
    assert(styleOf(`"%d%%"`) == "GHHHHG");
    assert(styleOf("`a\\n`") == "GGGGG");
    assert(styleOf(`r"a\n"`) == "GGGGGG");
    assert(styleOf("'x'") == "HHH");
    assert(styleOf(`'\n'`) == "HHHH");
    assert(styleOf(`'\u00e9'`) == "HHHHHHHH");
    assert(styleOf("'\u00e9'") == "HHHH"); // one two-byte character
    assert(styleOf(`x"0A 1b"`) == "HHHHHHHH");
    // An unterminated string runs to the end of the text; keywords inside a
    // string or comment are not keywords.
    assert(styleOf(`"abc`) == "GGGG");
    assert(styleOf(`"if" if`) == "GGGGABB");
    assert(at("// if x", "if") == "FF");
    // Numbers are one plain token.
    assert(styleOf("0x1F_u") == "AAAAAA");
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
