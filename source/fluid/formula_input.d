/*
 * Ported from FLTK's `fluid::widget::Formula_Input` (`fluid/widgets/
 * Formula_Input.{h,cxx}`) -- an `Fl_Input` that understands a small
 * integer formula language: unary `+`/`-`, `+ - * /` (integer division,
 * silently no-ops on division by zero), parentheses, and named
 * variables. No error checking at all, matching FLTK's own documented
 * behavior ("the interpreter does not perform error checking, so it is
 * assumed that the formula is entered correctly").
 *
 * FLTK's own `Formula_Input_Vars` (a name plus a per-name C function
 * pointer plus one `void*` shared across the whole table) collapses to
 * `FormulaVar` (a name plus a D delegate) -- the direct equivalent
 * matching `CONVENTIONS.md`'s "callbacks are D delegates" convention: each
 * delegate closes over whatever context it needs directly, so there's
 * no shared user-data slot to thread through at all.
 *
 * This class's own `value()`/`value(int)` are repurposed to evaluate/
 * set the formula as an `int`, which hides `Input_`'s own plain-string
 * `value()`/`value(string)`/`value(double)` entirely (D hides all
 * same-named base overloads once a derived class declares its own,
 * same as C++) -- exactly the situation FLTK's own class is in too,
 * resolved there (and here, identically) by adding `text()`/`text(v)`
 * as the raw-string escape hatch instead of trying to keep `value()`
 * doing both jobs. `alias value = Input_.value;` is required by D's
 * compiler regardless (it errors on silent same-name hiding unless the
 * base overload set is explicitly re-introduced this way) even though
 * `text()`/`text(v)` -- not the aliased-back `value(string)` -- are
 * this class's own intended string API, matching FLTK's.
 */
module fluid.formula_input;

import fl;
import std.ascii : isAlpha;

/// A named variable available to a `FormulaInput`'s own formula
/// language, its value computed lazily via `eval()` on demand -- see
/// this module's own top comment for how this maps to FLTK's own
/// `Formula_Input_Vars`.
struct FormulaVar
{
    string name;
    int delegate() eval;
}

class FormulaInput : Input
{
    alias value = Input_.value; // required by D's compiler -- see this module's own top comment

    private FormulaVar[] vars_;

    this(int x, int y, int w, int h, string l = null)
    {
        super(x, y, w, h, l);
        text("0");
    }

    /// Raw text access -- `Input_`'s own `value()`/`value(string)` are
    /// hidden by this class's own `value()`/`value(int)` below (the
    /// same name-hiding FLTK's own class has), so the plain string form
    /// gets its own name, exactly as FLTK itself does.
    string text() const { return super.value(); }
    void text(string v) { super.value(v); }

    /// Sets the named variables available to this formula for its next
    /// evaluation -- call this fresh before reading `value()` whenever
    /// the eval context changes (FLTK's own `variables()` is called the
    /// same way, right before each store-time eval, since its shared
    /// `widget_vars[]` table's user-data gets rebound per selected
    /// widget).
    void variables(FormulaVar[] vars)
    {
        vars_ = vars;
    }

    /// Evaluates the current formula text and returns the result.
    int value() const
    {
        return evalTopLevel(text());
    }

    /// Replaces the current text with `v`'s plain decimal form.
    void value(int v)
    {
        import std.conv : to;
        text(to!string(v));
    }

    override int handle(Event event)
    {
        if (event == Event.mouseWheel)
        {
            auto dy = eventDy();
            if (dy != 0)
            {
                value(value() - dy);
                setChanged();
                doCallback(CallbackReason.changed);
            }
            return 1;
        }
        return super.handle(event);
    }

    private int evalTopLevel(string s) const
    {
        char[] cleaned;
        cleaned.reserve(s.length);
        foreach (c; s)
            if (c != ' ' && c != '\t') cleaned ~= c;
        size_t i = 0;
        return evalExpr(cast(string) cleaned, i, 0);
    }

    /// Ported from `Formula_Input::eval_var(uchar*&)` -- collects a run
    /// of ASCII letters as a variable name and looks it up in `vars_`
    /// (unknown name, or no variables set at all: 0, matching FLTK's own
    /// "no error checking" stance).
    private int evalVar(string s, ref size_t i) const
    {
        if (vars_.length == 0) return 0;
        size_t start = i;
        while (i < s.length && isAlpha(s[i])) i++;
        string name = s[start .. i];
        foreach (ref v; vars_)
            if (v.name == name) return v.eval();
        return 0;
    }

    /// Ported from `Formula_Input::eval(uchar*&, int)` -- precedence
    /// climbing over whitespace-stripped text:
    ///   expr := ['+'|'-'] (number | variable | '(' expr ')') (op expr)*
    /// `i` always points at the next unread character, shared across the
    /// recursive calls. `prio` is the weakest operator this call may
    /// consume: 0 takes `+ -` and `* /`; 2 stops at `+ -` (right side of
    /// a `+`/`-`); 3 stops at `* /` too (right side of a `*`/`/`).
    private int evalExpr(string s, ref size_t i, int prio) const
    {
        char peek() { return i < s.length ? s[i] : '\0'; }

        int v = 0, sgn = 1;
        char c = peek();

        if (c == '-') { sgn = -1; i++; c = peek(); }
        else if (c == '+') { i++; c = peek(); }

        if (c >= '0' && c <= '9')
        {
            while (peek() >= '0' && peek() <= '9')
            {
                v = v * 10 + (peek() - '0');
                i++;
            }
        }
        else if (isAlpha(c))
        {
            v = evalVar(s, i);
        }
        else if (c == '(')
        {
            i++;
            v = evalExpr(s, i, 0);
            if (peek() == ')') i++;
        }
        else
        {
            return 0; // syntax error: no value found
        }
        if (sgn == -1) v = -v;

        for (;;)
        {
            c = peek();
            if (c == '+' || c == '-')
            {
                if (prio > 1) return v;
                i++;
                int rhs = evalExpr(s, i, 2);
                if (c == '+') v += rhs; else v -= rhs;
            }
            else if (c == '*' || c == '/')
            {
                if (prio > 2) return v;
                i++;
                int rhs = evalExpr(s, i, 3);
                if (c == '*') v *= rhs;
                else if (rhs != 0) v /= rhs; // division by zero: silently skipped
            }
            else
            {
                return v;
            }
        }
    }
}

unittest
{
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto f = new FormulaInput(0, 0, 100, 25);
    int eval(string t) { f.text(t); return f.value(); }

    assert(eval("(1+2)*3") == 9);
    assert(eval("((2+3))*2") == 10);
    assert(eval("2*(3+(4*5))") == 46);
    assert(eval("-(2+3)") == -5);
    assert(eval("2*(1+2)+4") == 10);
    assert(eval("10 - 2 - 3") == 5);
    assert(eval("8/0") == 8); // division by zero is skipped
    assert(eval("2 + 3 * 4") == 14);

    FlGroup.current(null);
}
