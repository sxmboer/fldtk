/*
 * Ported from FL/Fl_Value_Input.H + src/Fl_Value_Input.cxx (FLTK 1.5.0). A numeric field: a real, editable text entry
 * (click to type a value directly) whose value also changes with the
 * mouse wheel (see handle()).
 *
 * FLTK's own source comment calls this "a kludge": Fl_Value_Input
 * extends Fl_Valuator (not Fl_Group), yet embeds a real Fl_Input child
 * -- achieved in C++ by force-setting `input.parent((Fl_Group*)this)`,
 * an unsafe cast (`Fl_Widget::parent()` returns `Fl_Group*`, and
 * `Fl_Value_Input` genuinely isn't one).
 *
 * This port doesn't replicate that specific cast (D's type system
 * correctly refuses it), but does give `input_` a real, working parent
 * -- via a small, general widening of `Widget.parent_`'s type from
 * `FlGroup` to plain `Widget` (see that field's own doc comment in
 * `fl.widget.d` for the full reasoning). `input_` is still constructed
 * under `FlGroup.current(null)` (so it never auto-parents into whatever
 * group happens to be open when a `ValueInput` is created -- it's not
 * a tree-managed child, `ValueInput` has no `children()` array for it
 * to live in), but its `parent_` is then explicitly set to `this`.
 * Because every consumer of `.parent`/`.parent_` in this port
 * (`contains()`, `damage()`, `window()`, `fl.core`'s focus/belowmouse
 * ancestor walks) only ever needs `Widget`-level information, this one
 * assignment is enough to make all of them work correctly for
 * `input_`, exactly as FLTK's unsafe cast does for the same
 * reasons -- just without the unsafety.
 *
 * (This module went through an earlier, more awkward version that left
 * `parent_` `null` and patched each broken mechanism separately as it
 * was found interactively -- a `getMouse()`-based positioning fallback
 * for `window()`, explicit `redraw()` calls standing in for `damage()`,
 * a `contains()` override -- before it became clear the real bug was
 * `parent_`'s type being narrower than it needed to be. Fixing that
 * once, in `fl.widget.d`, removed the need for all of those but the
 * `getMouse()` fallback, which independently remains a good defensive
 * improvement for `fl.input`/`fl.text_display`'s `handleRmb()` and was
 * kept for that reason -- see those modules' own comments.)
 *
 * Otherwise a complete port: draw() (forwards to the embedded Input's own real
 * draw()), resize(), valueDamage()'s override (keeps the embedded
 * Input's displayed text in sync whenever value() changes
 * programmatically), and inputCallback() (parses the embedded Input's
 * text back into a double whenever *it* changes, matching FLTK's
 * strtod()/strtol() split on whether step() is a nonzero integer).
 */
module fl.value_input;

import fl.enumerations;
import fl.valuator : Valuator;
import fl.input : Input;
import fl.group : FlGroup;
import fl.draw;
import fl.core;

class ValueInput : Valuator
{
    private Input input_;
    private bool soft_;

    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);

        auto previousGroup = FlGroup.current();
        FlGroup.current(null); // input_ is a manually-managed child, not a real group member -- see the module comment
        input_ = new Input(x, y, w, h);
        FlGroup.current(previousGroup);

        // Gives input_ a real (if not tree-managed) parent, so
        // contains()/damage()/window() all correctly walk up through
        // `this` to the real window -- see the module comment.
        input_.parent(this);

        input_.callback((w) { inputCallback(); });
        input_.when(whenChanged);

        box(input_.box());
        color(input_.color());
        selectionColor(input_.selectionColor());
        alignment(alignLeft);
        valueDamage();
        shortcutLabel(true);
    }

    /// If "soft" is turned on, the mouse wheel can take the value
    /// outside the range: a turn stops at the end of the range, and the
    /// next turn from there goes past it. Default is off (FLTK's own default is on, but
    /// only because it never initializes soft_ in its constructor --
    /// see the "Bug fix" note in fl.value_output's history for the
    /// same FLTK quirk elsewhere; here it's simply given an
    /// explicit, sane default instead of leaving it undefined).
    void soft(bool s) { soft_ = s; }
    bool soft() const { return soft_; }

    /// Ported from Fl_Value_Input's inline textfont()/textsize()/
    /// textcolor()/cursor_color() forwarders -- all delegate straight
    /// to the embedded input_.
    Font textfont() const { return input_.textfont(); }
    void textfont(Font f) { input_.textfont(f); }

    Fontsize textsize() const { return input_.textsize(); }
    void textsize(Fontsize s) { input_.textsize(s); }

    Color textcolor() const { return input_.textcolor(); }
    void textcolor(Color c) { input_.textcolor(c); }

    Color cursorColor() const { return input_.cursorColor(); }
    void cursorColor(Color c) { input_.cursorColor(c); }

    /// Ported from Fl_Value_Input::shortcut()/shortcut(int) -- both
    /// forward to the embedded input_ rather than this widget's own
    /// shortcut_ (Valuator/Widget has none), matching FLTK exactly.
    int shortcut() const { return input_.shortcut(); }
    void shortcut(int s) { input_.shortcut(s); }

    /// Ported from Fl_Value_Input::value_damage() -- keeps the
    /// embedded input_'s displayed text (and cursor/selection) in sync
    /// whenever value() changes programmatically. Called automatically
    /// by Valuator.value(double)'s setter. input_.value(...)'s own
    /// internal redraw() is enough to reach the real window now that
    /// input_.parent() is real (see the module comment) -- no explicit
    /// self-damage needed here, matching FLTK exactly.
    protected override void valueDamage()
    {
        input_.value(format());
        input_.mark(input_.insertPosition()); // turn off selection highlight
    }

    /// Ported from the static Fl_Value_Input::input_cb() -- fires when
    /// the embedded input_'s own text changes (every keystroke, since
    /// input_.when() is kept in sync with this widget's when() at the
    /// top of handle()). Parses the typed text as a double, or (if
    /// step() is a nonzero integer) truncates it toward zero first,
    /// matching FLTK's strtod()/strtol() split.
    private void inputCallback()
    {
        import std.math : floor;

        double nv = parseNumberOrZero(input_.value());
        bool useFloat = (step() - floor(step())) > 0.0 || step() == 0.0;
        if (!useFloat) nv = cast(double) cast(long) nv;

        if (nv != value() || (when() & whenNotChanged))
        {
            setValue(nv);
            setChanged();
            if (when()) doCallback(CallbackReason.changed);
        }
    }

    /// Parses a leading number out of s, or 0.0 if s doesn't start
    /// with one -- the D-side equivalent of strtod()'s/strtol()'s
    /// "unparseable input yields 0, never throws" behavior.
    private static double parseNumberOrZero(string s)
    {
        import std.conv : parse;

        if (s.length == 0) return 0.0;
        auto slice = s;
        try
            return parse!double(slice);
        catch (Exception)
            return 0.0;
    }

    override void resize(int x, int y, int w, int h)
    {
        super.resize(x, y, w, h);
        input_.resize(x, y, w, h);
    }

    /// Ported from Fl_Value_Input::draw() -- forwards to the embedded
    /// input_'s own real draw(), after syncing its box/color from this
    /// widget's own (the two are kept in sync exactly like FLTK:
    /// set once in the constructor, then re-applied every draw() in
    /// case a caller changed box()/color()/selectionColor() directly
    /// on the ValueInput rather than through input_).
    override void draw()
    {
        if (damage() & ~damageChild) input_.damage(damageAll);
        input_.box(box());
        input_.color(color(), selectionColor());
        input_.draw();
        input_.clearDamage();
    }

    /**
     * Ported from Fl_Value_Input::handle(). The mouse wheel changes the
     * value: a notch up, or a sideways wheel to the right, adds
     * `wheelStepFactor()` steps (10; 1 with Shift held, 100 with Ctrl),
     * a notch down or to the left subtracts them. Clicking and dragging
     * edit the text, as in any input field.
     */
    override int handle(Event event)
    {
        input_.when(when());

        switch (event)
        {
        case Event.mouseWheel:
        {
            int n = wheelNotches();
            if (n == 0) return 0;
            double v = round(increment(value(), n * wheelStepFactor()));
            changeByWheel(soft_ ? softclamp(v) : clamp(v));
            return 1;
        }

        case Event.focus:
            return input_.takeFocus() ? 1 : 0;

        case Event.shortcut:
            return input_.handle(event);

        default:
            return defaultHandle(event);
        }
    }

    private int defaultHandle(Event event)
    {
        import std.math : floor;

        input_.inputType((step() - floor(step()) > 0.0 || step() == 0.0) ? inputFloat : inputInt);
        return input_.handle(event);
    }
}

// ===========================================================================
// Unit tests
// ===========================================================================

unittest
{
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto v = new ValueInput(0, 0, 100, 25);
    assert(!v.soft());
    assert(v.alignment() == alignLeft);
    assert(v.shortcutLabel());
    assert(v.value() == 0);

    fl.core.resetForTest();
}

unittest
{
    // valueDamage(): setting value() programmatically syncs the
    // embedded input_'s displayed text.
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto v = new ValueInput(0, 0, 100, 25);
    v.value(42);
    assert(v.value() == 42);

    fl.core.resetForTest();
}

unittest
{
    // input_.parent() is real -- contains()/damage()/window() all
    // correctly walk up through the ValueInput itself. Headless-safe:
    // pure widget-tree bookkeeping, no display needed.
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto v = new ValueInput(0, 0, 100, 25);
    assert(v.contains(v.input_));
    assert(v.input_.parent() is v);

    fl.core.resetForTest();
}

unittest
{
    // The wheel: a notch up adds 10 steps, with Shift 1, with Ctrl 100;
    // down subtracts, a sideways wheel to the right adds. Dragging no
    // longer changes the value.
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto v = new ValueInput(0, 0, 100, 25);
    v.bounds(-1_000_000, 1_000_000);
    v.step(1);
    v.value(0);

    fl.core.eDy_ = -1;
    v.handle(Event.mouseWheel);
    assert(v.value() == 10);
    fl.core.eState_ = stateShift;
    v.handle(Event.mouseWheel);
    assert(v.value() == 11);
    fl.core.eState_ = stateCtrl;
    fl.core.eDy_ = 1;
    v.handle(Event.mouseWheel);
    assert(v.value() == -89);
    fl.core.eState_ = 0;
    fl.core.eDy_ = 0;
    fl.core.eDx_ = 1;
    v.handle(Event.mouseWheel);
    assert(v.value() == -79);

    // Shift + wheel up, which the platform reports as a scroll to the
    // left, still adds.
    fl.core.eState_ = stateShift;
    fl.core.eDx_ = -1;
    fl.core.eWheelSwapped_ = true;
    v.handle(Event.mouseWheel);
    assert(v.value() == -78);

    fl.core.eState_ = 0;
    fl.core.eDx_ = 0;
    fl.core.eXRoot_ = 50;
    fl.core.eKeysym_ = button + leftMouse;
    v.handle(Event.push);
    fl.core.eXRoot_ = 80;
    v.handle(Event.drag);
    assert(v.value() == -78);

    fl.core.eKeysym_ = 0;
    fl.core.resetForTest();
}

unittest
{
    // inputCallback(): typing into the embedded input_ and firing its
    // callback updates ValueInput's own value() -- float mode (step()
    // has a fractional part) parses the full decimal value.
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto v = new ValueInput(0, 0, 100, 25);
    v.step(0.5);
    v.input_.value("3.75");
    v.inputCallback();
    assert(v.value() == 3.75);

    fl.core.resetForTest();
}

unittest
{
    // inputCallback() in integer mode (step() is a nonzero integer)
    // truncates a typed decimal value toward zero, matching FLTK's
    // strtol() behavior for that case.
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto v = new ValueInput(0, 0, 100, 25);
    v.step(1);
    v.input_.value("7.9");
    v.inputCallback();
    assert(v.value() == 7);

    fl.core.resetForTest();
}
