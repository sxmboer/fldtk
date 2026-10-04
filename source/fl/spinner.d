/*
 * Ported from FL/Fl_Spinner.H + src/Fl_Spinner.cxx (FLTK 1.5.0,
 * ~/Repositories/fltk). A FlGroup combining a numeric Input field with
 * up/down buttons.
 *
 * The up/down buttons are now real fl.repeat_button.RepeatButton
 * instances (previously plain fl.button.Button, since RepeatButton
 * needed a timer subsystem that didn't exist yet -- see
 * fl.repeat_button's own module comment). Holding a spinner button
 * down now repeats continuously, matching FLTK, instead of
 * changing the value once per click.
 *
 * Fl_Spinner::sb_cb() (FLTK's `Fl_Callback*` + `Fl_Spinner*`
 * user-data two-arg callback, needed in C++ because a plain function
 * pointer can't close over `this`) becomes a private method bound as a
 * D delegate instead -- see CLAUDE.md's callback porting convention.
 */
module fl.spinner;

import std.format : sformat = format;

import fl.enumerations;
import fl.group : FlGroup;
import fl.widget : Widget;
import fl.input : Input;
import fl.repeat_button : RepeatButton;
import fl.rect : Rect;
import fl.core;
import fldraw = fl.draw;

/// Ignores FL_Up/FL_Down (the parent Spinner handles those) -- ported
/// from the private Fl_Spinner::Fl_Spinner_Input nested class.
private class SpinnerInput : Input
{
    this(int x, int y, int w, int h)
    {
        super(x, y, w, h);
    }

    override int handle(Event event)
    {
        if (event == Event.keyDown)
        {
            Keysym key = fl.core.eventKey();
            if (key == fl.enumerations.up || key == fl.enumerations.down)
            {
                super.handle(Event.unfocus); // sets and potentially clips the input value
                return 0;
            }
        }
        return super.handle(event);
    }
}

class Spinner : FlGroup
{
    private
    {
        double value_ = 1.0;
        double minimum_ = 1.0;
        double maximum_ = 100.0;
        double step_ = 1.0;
        string format_ = "%g";
        bool wrap_ = true;

        SpinnerInput input_;
        RepeatButton upButton_;
        RepeatButton downButton_;
    }

    alias color = Widget.color;
    alias type = Widget.type;

    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);

        input_ = new SpinnerInput(x, y, w - h / 2 - 2, h);
        upButton_ = new RepeatButton(x + w - h / 2 - 2, y, h / 2 + 2, h / 2);
        downButton_ = new RepeatButton(x + w - h / 2 - 2, y + h - h / 2, h / 2 + 2, h / 2);

        end();

        value_ = 1.0;
        minimum_ = 1.0;
        maximum_ = 100.0;
        step_ = 1.0;
        wrap_ = true;
        format_ = "%g";

        alignment(alignLeft);

        input_.value("1");
        input_.type(inputInt);
        input_.when(whenEnterKey | whenRelease);
        input_.callback(&sbCb);

        upButton_.callback(&sbCb);
        downButton_.callback(&sbCb);
    }

    /// Ported from Fl_Spinner::sb_cb() -- see the module comment for
    /// why this is a bound delegate rather than a C-style callback +
    /// user-data pair.
    private void sbCb(Widget w)
    {
        double v;

        if (w is input_)
        {
            v = input_.dvalue();
            if (v < minimum_) { value_ = minimum_; update(); }
            else if (v > maximum_) { value_ = maximum_; update(); }
            else value_ = v;
        }
        else if (w is upButton_)
        {
            v = value_ + step_;
            if (v > maximum_) v = wrap_ ? minimum_ : maximum_;
            value_ = v;
            update();
        }
        else if (w is downButton_)
        {
            v = value_ - step_;
            if (v < minimum_) v = wrap_ ? maximum_ : minimum_;
            value_ = v;
            update();
        }

        setChanged();
        doCallback(CallbackReason.changed);
    }

    /// Ported from Fl_Spinner::update().
    private void update()
    {
        string s;
        if (format_.length >= 3 && format_[0] == '%' && format_[1] == '.' && format_[2] == '*')
        {
            // Precision-argument format (e.g. "%.*f", set by type()
            // below): compute the decimal-place count from step_'s own
            // trailing-zero-trimmed decimal representation, mirroring
            // Fl_Valuator::format()'s technique (FLTK's own
            // comment calls this "simplified... but looks ugly").
            string temp = sformat("%.12f", step_);
            size_t sp = temp.length;
            while (sp > 0 && temp[sp - 1] == '0') sp--;
            int c = 0;
            while (sp > 0 && temp[sp - 1] >= '0' && temp[sp - 1] <= '9') { sp--; c++; }
            s = sformat("%.*f", c, value_);
        }
        else
        {
            s = sformat(format_, value_);
        }
        input_.value(s);
    }

    override void draw()
    {
        super.draw(); // buttons are blank -- no labels to draw over

        Color arrowColor = activeR() ? labelcolor() : fldraw.inactive(labelcolor());
        Rect up = Rect(upButton_);
        up.inset(upButton_.box());
        fldraw.drawArrow(up, ArrowType.arrowSingle, Orientation.orientUp, arrowColor);

        Rect down = Rect(downButton_);
        down.inset(downButton_.box());
        fldraw.drawArrow(down, ArrowType.arrowSingle, Orientation.orientDown, arrowColor);
    }

    override int handle(Event event)
    {
        switch (event)
        {
        case Event.keyDown:
        case Event.shortcut:
            if (fl.core.eventKey() == fl.enumerations.up)
            {
                upButton_.doCallback(CallbackReason.dragged);
                return 1;
            }
            else if (fl.core.eventKey() == fl.enumerations.down)
            {
                downButton_.doCallback(CallbackReason.dragged);
                return 1;
            }
            return 0;

        case Event.focus:
            return input_.takeFocus() ? 1 : 0;

        default:
            break;
        }
        return super.handle(event);
    }

    override void resize(int x, int y, int w, int h)
    {
        super.resize(x, y, w, h);

        input_.resize(x, y, w - h / 2 - 2, h);
        upButton_.resize(x + w - h / 2 - 2, y, h / 2 + 2, h / 2);
        downButton_.resize(x + w - h / 2 - 2, y + h - h / 2, h / 2 + 2, h / 2);
    }

    string format() const { return format_; }
    void format(string f) { format_ = f; update(); }

    double maximum() const { return maximum_; }
    void maximum(double m) { maximum_ = m; }

    double minimum() const { return minimum_; }
    void minimum(double m) { minimum_ = m; }

    void range(double a, double b) { minimum_ = a; maximum_ = b; }

    void step(double s)
    {
        step_ = s;
        if (step_ != cast(int) step_) input_.type(inputFloat);
        else input_.type(inputInt);
        update();
    }
    double step() const { return step_; }

    void wrap(bool set) { wrap_ = set; }
    bool wrap() const { return wrap_; }

    Color textcolor() const { return input_.textcolor(); }
    void textcolor(Color c) { input_.textcolor(c); }

    Font textfont() const { return input_.textfont(); }
    void textfont(Font f) { input_.textfont(f); }

    Fontsize textsize() const { return input_.textsize(); }
    void textsize(Fontsize s) { input_.textsize(s); }

    /// Sets the numeric representation (inputInt or inputFloat), also
    /// updating format() -- matches FLTK's non-virtual `type()`
    /// shadowing note (setting the type via a FlGroup/Widget pointer
    /// won't dispatch here, same as FLTK).
    override void type(ubyte v)
    {
        if (v == inputFloat) format("%.*f");
        else format("%.0f");
        input_.type(v);
    }
    override ubyte type() const { return input_.inputType(); }

    double value() const { return value_; }
    void value(double v) { value_ = v; update(); }

    override void color(Color v) { input_.color(v); }
    override Color color() const { return input_.color(); }

    override void selectionColor(Color val) { input_.selectionColor(val); }
    override Color selectionColor() const { return input_.selectionColor(); }

    void maximumSize(int m) { if (m > 0) input_.maximumSize(m); }
    int maximumSize() const { return input_.maximumSize(); }
}

// ===========================================================================
// Unit tests
// ===========================================================================

unittest
{
    import fl.group : FlGroup;

    FlGroup.current(null);
    fl.core.resetForTest();

    auto sp = new Spinner(0, 0, 100, 20);
    assert(sp.value() == 1.0);
    assert(sp.minimum() == 1.0);
    assert(sp.maximum() == 100.0);
    assert(sp.step() == 1.0);
    assert(sp.wrap());

    FlGroup.current(null);
    fl.core.resetForTest();
}

unittest
{
    // up/down buttons change value() by step(), clamped/wrapped at
    // minimum()/maximum(). Exercises sb_cb() directly through the
    // buttons' own callback (doCallback()), same as a real click would.
    import fl.group : FlGroup;

    FlGroup.current(null);
    fl.core.resetForTest();

    auto sp = new Spinner(0, 0, 100, 20);
    sp.range(0, 3);
    sp.step(1);
    sp.wrap(true);
    sp.value(3);

    sp.upButton_.doCallback(); // 3 + 1 > max(3) -> wraps to min(0)
    assert(sp.value() == 0);

    sp.downButton_.doCallback(); // 0 - 1 < min(0) -> wraps to max(3)
    assert(sp.value() == 3);

    FlGroup.current(null);
    fl.core.resetForTest();
}

unittest
{
    // Same, but with wrap() off: clamps at the bound instead.
    import fl.group : FlGroup;

    FlGroup.current(null);
    fl.core.resetForTest();

    auto sp = new Spinner(0, 0, 100, 20);
    sp.range(1, 5);
    sp.step(1);
    sp.wrap(false);
    sp.value(5);

    sp.upButton_.doCallback();
    assert(sp.value() == 5); // clamped at maximum(), no wrap

    FlGroup.current(null);
    fl.core.resetForTest();
}
