/*
 * Ported from FL/Fl_Valuator.H + src/Fl_Valuator.cxx (FLTK 1.5.0).
 *
 * Faithful, complete port. Fl_Valuator is pure numeric bookkeeping
 * (range/step/value/rounding/clamping) with no drawing of its own --
 * draw() stays abstract here exactly as it does FLTK (subclasses
 * like fl.slider provide it) -- so unlike most widgets ported so far,
 * there's nothing here that's blocked on the graphics driver.
 *
 * format(char*)/format_str() (FLTK's dual C-buffer/std::string
 * API) are collapsed into a single format() returning a D string,
 * matching this port's established convention of using D `string`
 * instead of C buffer-passing (see fl.widget's label()/tooltip() note
 * in CONVENTIONS.md).
 */
module fl.valuator;

import std.format : format;
import std.math : rint, fabs;

import fl.enumerations;
import fl.widget : Widget;
import fl.core;

/// Shared type() values for valuators that work in both directions;
/// FL_VERTICAL is 0 so it's also every valuator's default type().
enum ubyte verticalType = 0;
enum ubyte horizontalType = 1;

abstract class Valuator : Widget
{
    private
    {
        double value_;
        double previousValue_;
        double min_, max_; // truncates to this range *after* rounding
        double a_;         // rounds to multiples of a_/b_, or no
        int b_;             // rounding at all if a_ is zero
    }

    /// The default boxtype is noBox.
    protected this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        alignment(alignBottom);
        when(whenChanged);
        value_ = 0;
        previousValue_ = 1;
        min_ = 0;
        max_ = 1;
        a_ = 0.0;
        b_ = 1;
    }

    /// True if this valuator works horizontally.
    protected bool horizontal() const { return (type() & horizontalType) != 0; }

    /// The value before an event started changing it.
    protected double previousValue() const { return previousValue_; }
    /// Stores the current value as the previous value.
    protected void handlePush() { previousValue_ = value_; }

    /// Clamps v, but accepts it if the previous value was already out
    /// of range on the same side (so a drag that starts outside the
    /// range isn't yanked back the instant it moves).
    protected double softclamp(double v)
    {
        bool which = min_ <= max_;
        double p = previousValue_;
        if ((v < min_) == which && p != min_ && (p < min_) != which) return min_;
        else if ((v > max_) == which && p != max_ && (p > max_) != which) return max_;
        return v;
    }

    /// Called during a drag, after an FL_WHEN_CHANGED event is
    /// received and before the callback.
    protected void handleDrag(double v)
    {
        if (v != value_)
        {
            value_ = v;
            valueDamage();
            setChanged();
            if (when() & whenChanged) doCallback(CallbackReason.changed);
        }
    }

    /// Called after an FL_WHEN_RELEASE event is received and before
    /// the callback.
    protected void handleRelease()
    {
        if (when() & whenRelease)
        {
            // Ensure changed() is off even if no callback is done -- it
            // may have been turned on by the drag and then the slider
            // returned to its initial position.
            clearChanged();
            if (value_ != previousValue_ || (when() & whenNotChanged))
                doCallback(CallbackReason.released);
        }
    }

    /// Requests damage due to value() changing; overridable so
    /// subclasses can ask for a partial (rather than full) redraw.
    protected void valueDamage() { damage(damageExpose); }

    /// Sets the current value without any damage/changed/callback
    /// side effects.
    protected void setValue(double v) { value_ = v; }

    /// Sets the minimum (a) and maximum (b) values.
    void bounds(double a, double b) { min_ = a; max_ = b; }
    double minimum() const { return min_; }
    void minimum(double a) { min_ = a; }
    double maximum() const { return max_; }
    void maximum(double a) { max_ = a; }
    /// Same as bounds(a, b).
    void range(double a, double b) { min_ = a; max_ = b; }

    void step(int a) { a_ = a; b_ = 1; }
    void step(double a, int b) { a_ = a; b_ = b; }

    /// Sets the step value; see the getter's documentation for how
    /// this is stored internally as a ratio a_/b_ for precision.
    void step(double s)
    {
        enum double epsilon = 4.66e-10;
        if (s < 0) s = -s;
        a_ = rint(s);
        b_ = 1;
        while (fabs(s - a_ / b_) > epsilon && b_ <= (0x7fffffff / 10))
        {
            b_ *= 10;
            a_ = rint(s * b_);
        }
    }

    /// Gets the step value: as the user moves the mouse, value() is
    /// rounded to the nearest multiple of this, before clamping to the
    /// range. Zero (the default) means no rounding.
    double step() const { return a_ / b_; }

    /// Sets the step value to 1.0 / 10^digits (clamped to 0..9).
    void precision(int digits)
    {
        if (digits > 9) digits = 9;
        else if (digits < 0) digits = 0;
        a_ = 1.0;
        b_ = 1;
        while (digits--) b_ *= 10;
    }

    double value() const { return value_; }

    /**
     * Sets the current value, not clamped or rounded first (use
     * clamp()/round() before calling this if needed). Redraws if the
     * new value differs from the current one. Returns true if it
     * changed. changed() is turned off by this call (it's turned back
     * on by the user moving the valuator, and cleared again just
     * before a callback -- the callback may turn it back on).
     */
    bool value(double v)
    {
        clearChanged();
        if (v == value_) return false;
        value_ = v;
        valueDamage();
        return true;
    }

    /// Rounds v to the nearest multiple of step(); a no-op if step()
    /// is zero.
    double round(double v)
    {
        if (a_ != 0) return rint(v * b_ / a_) * a_ / b_;
        return v;
    }

    /// Clamps v to [minimum(), maximum()] (or the reverse range, if
    /// minimum() > maximum()).
    double clamp(double v)
    {
        if ((v < min_) == (min_ <= max_)) return min_;
        else if ((v > max_) == (min_ <= max_)) return max_;
        return v;
    }

    /// Adds n times the step value to v; if step() is zero, adds
    /// n/100 of the full range instead.
    double increment(double v, int n)
    {
        if (a_ == 0) return v + n * (max_ - min_) / 100;
        if (min_ > max_) n = -n;
        return (rint(v * b_ / a_) + n) * a_ / b_;
    }

    /**
     * Formats value() using internal rules based on the current step:
     * "%g" if step() is zero, otherwise "%.*f" with just enough
     * decimal places to represent step() precisely (an integer step
     * gives 0 decimal places, i.e. an integer display).
     */
    string format()
    {
        if (a_ == 0 || b_ == 0) return "%g".format(value_);

        string temp = "%.12f".format(a_ / b_);
        auto i = cast(ptrdiff_t) temp.length - 1;
        while (i > 0 && temp[i] == '0') i--;

        int c = 0;
        while (i > 0 && temp[i] >= '0' && temp[i] <= '9')
        {
            i--;
            c++;
        }

        return "%.*f".format(c, value_);
    }
}

unittest
{
    static class TestValuator : Valuator
    {
        this() { super(0, 0, 100, 20); }
        override void draw() {}
    }

    auto v = new TestValuator();
    assert(v.minimum() == 0 && v.maximum() == 1);
    assert(v.value() == 0);

    assert(v.value(0.5));
    assert(v.value() == 0.5);
    assert(!v.value(0.5)); // no change -> false

    v.bounds(0, 10);
    assert(v.clamp(-5) == 0);
    assert(v.clamp(15) == 10);
    assert(v.clamp(5) == 5);
}

unittest
{
    // step()/round(): a step of 0.5 rounds to the nearest half.
    static class TestValuator : Valuator
    {
        this() { super(0, 0, 100, 20); }
        override void draw() {}
    }

    auto v = new TestValuator();
    v.step(0.5);
    assert(v.step() == 0.5);
    assert(v.round(1.2) == 1.0);
    assert(v.round(1.3) == 1.5);

    v.step(0); // zero step: no rounding
    assert(v.round(1.234) == 1.234);
}

unittest
{
    // format(): integer step -> integer display; fractional step ->
    // just enough decimal places.
    static class TestValuator : Valuator
    {
        this() { super(0, 0, 100, 20); }
        override void draw() {}
    }

    auto v = new TestValuator();
    v.step(1);
    v.value(3);
    assert(v.format() == "3");

    v.step(0.5);
    v.value(3.5);
    assert(v.format() == "3.5");

    v.step(0.01);
    v.value(3.14159);
    assert(v.format() == "3.14");
}

unittest
{
    // handleDrag()/handleRelease() drive changed() the same way
    // fl.widget's doCallback()/clearChanged() interplay works
    // elsewhere: doCallback() only clears changed() for a *custom*
    // callback, not the default queue-push one (see fl.widget's
    // doCallback()) -- but handleRelease() itself always clears
    // changed() directly once whenRelease fires, regardless of that.
    static class TestValuator : Valuator
    {
        this() { super(0, 0, 100, 20); }
        override void draw() {}
    }

    auto v = new TestValuator();

    v.handlePush();
    v.handleDrag(0.3); // default when() is whenChanged -> fires doCallback()
    assert(v.value() == 0.3);
    assert(v.changed()); // no custom callback set, so it isn't cleared

    v.when(whenRelease);
    v.handleRelease();
    assert(!v.changed()); // handleRelease() clears changed() itself once whenRelease fires

    // Drains what handleDrag()/handleRelease() pushed onto fl.core's
    // shared default callback queue (no custom callback was set, so
    // doCallback() fell back to it) -- see resetForTest()'s doc
    // comment and the hermetic-tests note in CONVENTIONS.md.
    fl.core.resetForTest();
}
