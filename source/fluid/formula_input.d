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
 * matching `CLAUDE.md`'s "callbacks are D delegates" convention: each
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
        return evalExpr(cast(string) cleaned, i, 5);
    }

    private static char readChar(string s, ref size_t i)
    {
        return i < s.length ? s[i++] : '\0';
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

    /// Ported from `Formula_Input::eval(uchar*&, int)` -- a recursive-
    /// descent evaluator over whitespace-stripped text, `i` shared
    /// across recursive calls the same way FLTK's own `uchar*&s`
    /// reference parameter is. `readChar()`'s "return '\0' without
    /// advancing past the end" shape is what replaces FLTK's own
    /// `s--` "push the virtual end-of-string terminator back" idiom
    /// throughout -- once `i` reaches `s.length` it simply stays there,
    /// so every `if (c == 0) return ...;` branch below needs no
    /// separate correction step the way the original pointer code did.
    private int evalExpr(string s, ref size_t i, int prio) const
    {
        int v = 0, sgn = 1;
        char c = readChar(s, i);

        if (c == '\0') return sgn * v;

        if (c == '-') { sgn = -1; c = readChar(s, i); }
        else if (c == '+') { sgn = 1; c = readChar(s, i); }

        if (c == '\0')
        {
            return sgn * v;
        }
        else if (c >= '0' && c <= '9')
        {
            while (c >= '0' && c <= '9')
            {
                v = v * 10 + (c - '0');
                c = readChar(s, i);
            }
        }
        else if (isAlpha(c))
        {
            i--; // push back so evalVar reads the whole identifier itself
            v = evalVar(s, i);
            c = readChar(s, i);
        }
        else if (c == '(')
        {
            // No explicit ')' consumption here -- evalExpr's own inner
            // loop below returns right on ')' without advancing past it,
            // so *this* frame's own trailing `readChar()` (at the bottom
            // of the operator loop) is what actually consumes it. Exact
            // same shape as FLTK's own `v = eval(s, 5);` here.
            v = evalExpr(s, i, 5);
        }
        else
        {
            return sgn * v; // syntax error -- FLTK returns silently too
        }
        if (sgn == -1) v = -v;

        for (;;)
        {
            if (c == '\0')
            {
                return v;
            }
            else if (c == '+' || c == '-')
            {
                if (prio <= 4) { i--; return v; }
                if (c == '+') v += evalExpr(s, i, 4);
                else v -= evalExpr(s, i, 4);
            }
            else if (c == '*' || c == '/')
            {
                if (prio <= 3) { i--; return v; }
                if (c == '*') v *= evalExpr(s, i, 3);
                else
                {
                    int x = evalExpr(s, i, 3);
                    if (x != 0) v /= x; // division by zero: silently skipped
                }
            }
            else if (c == ')')
            {
                return v;
            }
            else
            {
                return v; // syntax error
            }
            c = readChar(s, i);
        }
    }
}

unittest
{
    FlGroup.current(null);
    auto f = new FormulaInput(0, 0, 50, 20);
    scope(exit) FlGroup.current(null);

    // Plain arithmetic, matching FLTK's own documented capability.
    f.text("2+3"); assert(f.value() == 5);
    f.text("2 + 3 * 4"); assert(f.value() == 14); // * binds tighter than +
    f.text("(2 + 3) * 4"); assert(f.value() == 20);
    f.text("-5+2"); assert(f.value() == -3);
    f.text("10/0"); assert(f.value() == 10); // division by zero: silently skipped, v stays at its pre-division value
    f.text("6/4"); assert(f.value() == 1); // integer division, truncating

    // int setter replaces the text with the plain decimal form.
    f.value(42);
    assert(f.text() == "42");
    assert(f.value() == 42);

    // No variables bound yet at all: matches FLTK's own `eval_var()`
    // faithfully, including its own real quirk (see FLTK_ISSUES.md)
    // -- its early `if (!vars_) return 0;` never consumes the identifier,
    // so the parse doesn't just treat the variable as 0, it desyncs and
    // drops the rest of the expression too (`"x+1"` evaluates to `0`,
    // not `1`). Harmless in practice: this port's own 4 real callers
    // (like FLTK's own) always call `variables()` before evaluating.
    assert(f.value() == 42); // still 42, no variables bound yet
    f.text("x+1");
    assert(f.value() == 0);

    // Named variables bound: known names resolve, unknown names are 0
    // (this time via the real name-lookup miss, not the no-table quirk
    // above -- consumes the identifier correctly either way).
    f.variables([FormulaVar("x", () => 10), FormulaVar("y", () => 3)]);
    assert(f.value() == 11); // "x+1" re-evaluated now that x=10 is bound
    f.text("x*y - 2");
    assert(f.value() == 28);
    f.text("z"); // unknown name even with variables bound
    assert(f.value() == 0);
}
