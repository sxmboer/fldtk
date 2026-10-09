/*
 * Quick legality check of a code snippet typed into the Widget Properties
 * panel (setup code, callback, user data): brackets, parentheses, braces
 * and quotes must be matched. Ported from FLTK's `c_check()`/`q_check()`
 * (`fluid/nodes/Function_Node.cxx`), with the same error messages, and
 * extended for the D lexical forms C doesn't have: backtick and `r"..."`
 * strings (no escapes) and nestable `/+ ... +/` comments.
 */
module fluid.code_check;

import std.format : format;

/// Checks `code`, returning `null` if it is balanced, else an error
/// message ("missing ')'", "unexpected '}'", ...).
string codeCheck(string code)
{
    size_t i = 0;
    return checkUntil(code, i, 0);
}

/// FLTK's `c_check_recursion()`: scans from `i` until the closing
/// character `type` (0: end of text) is found.
private string checkUntil(string c, ref size_t i, char type)
{
    for (;;)
    {
        if (i >= c.length)
            return type ? format("missing '%s'", type) : null;
        char ch = c[i++];
        switch (ch)
        {
        case '/':
            if (i < c.length && c[i] == '/')
            {
                while (i < c.length && c[i] != '\n') i++;
            }
            else if (i < c.length && c[i] == '*')
            {
                i++;
                while (i < c.length && !(c[i] == '*' && i + 1 < c.length && c[i + 1] == '/')) i++;
                if (i >= c.length) return "missing '*/'";
                i += 2;
            }
            else if (i < c.length && c[i] == '+')
            {
                i++;
                int depth = 1;
                while (depth > 0)
                {
                    if (i + 1 >= c.length) return "missing '+/'";
                    if (c[i] == '/' && c[i + 1] == '+') { depth++; i += 2; }
                    else if (c[i] == '+' && c[i + 1] == '/') { depth--; i += 2; }
                    else i++;
                }
            }
            break;
        case '{':
            if (auto d = checkUntil(c, i, '}')) return d;
            break;
        case '(':
            if (auto d = checkUntil(c, i, ')')) return d;
            break;
        case '[':
            if (auto d = checkUntil(c, i, ']')) return d;
            break;
        case '"':
            // `r"..."` is a wysiwyg string: no escapes.
            bool raw = i >= 2 && c[i - 2] == 'r' && (i < 3 || !isIdentChar(c[i - 3]));
            if (auto d = quoteCheck(c, i, '"', !raw)) return d;
            break;
        case '`':
            if (auto d = quoteCheck(c, i, '`', false)) return d;
            break;
        case '\'':
            if (auto d = quoteCheck(c, i, '\'', true)) return d;
            break;
        case '}':
        case ')':
        case ']':
            if (type == ch) return null;
            return format("unexpected '%s'", ch);
        default:
            break;
        }
    }
}

/// FLTK's `q_check()`: finds the closing quote `type`, skipping escaped
/// characters when `escapes` is set.
private string quoteCheck(string c, ref size_t i, char type, bool escapes)
{
    for (;;)
    {
        if (i >= c.length) return format("missing %s", type);
        char ch = c[i++];
        if (escapes && ch == '\\')
        {
            if (i < c.length) i++;
        }
        else if (ch == type)
            return null;
    }
}

private bool isIdentChar(char ch)
{
    return (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') || ch == '_';
}

unittest
{
    assert(codeCheck("") is null);
    assert(codeCheck(`writeln("a(b");`) is null);
    assert(codeCheck("foo(bar[1], { x; });") is null);
    assert(codeCheck("if (x) { y();") == "missing '}'");
    assert(codeCheck("y());") == "unexpected ')'");
    assert(codeCheck(`writeln("abc);`) == "missing \"");
    assert(codeCheck("char c = '\\'';") is null);
    assert(codeCheck("/* open") == "missing '*/'");
    assert(codeCheck("// ( not code\nx();") is null);
    assert(codeCheck("/+ a /+ ( +/ +/ x();") is null);
    assert(codeCheck("/+ a /+ b +/") == "missing '+/'");
    assert(codeCheck("auto s = `a\\`;") is null);
    assert(codeCheck(`auto s = r"C:\";`) is null);
    assert(codeCheck("auto s = `abc;") == "missing `");
}
