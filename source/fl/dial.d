/*
 * Ported from FL/Fl_Dial.H + src/Fl_Dial.cxx (FLTK 1.5.0,
 * ~/Repositories/fltk). "Provides a circular dial to control a single
 * floating point value" (FLTK's own doc comment): dragging traces
 * an angle from the widget's center, mapped onto [minimum(),
 * maximum()] between angle1()/angle2() (default 45/315 degrees, 0
 * degrees pointing straight down, increasing clockwise).
 *
 * Faithful, complete port of the numeric/event logic, including the
 * protected draw(int,int,int,int)/handle(int,int,int,int,int)
 * overloads FLTK exposes so a subclass can confine the dial to
 * less than the full widget bounds (same pattern already used by
 * fl.positioner).
 *
 * draw() is fully real now. The fillDial branch (type() == fillDial)
 * returns early after two fl_pie() calls plus, for certain round box
 * types, an outlining fl_arc(). The default (normalDial) and lineDial
 * branches draw the knob dot/pointer line indicator via the
 * transform-stack + vertex-path API (pushMatrix()/fl_translate()/
 * fl_scale()/fl_rotate()/beginPolygon()/vertex()/endPolygon()/
 * beginLoop()/endLoop()/circle()) -- all real primitives in
 * fl.draw now (see that module's own comment). Verified visually
 * (testing/smoke_dial_clock.d): a normalDial's dot and a lineDial's
 * pointer both appear at the correct rotation for their value.
 */
module fl.dial;

import std.math : atan2, PI;

import fl.enumerations;
import fl.valuator : Valuator;
import fl.draw;
import fl.core;

/// type() for a dial variant with a dot (the default).
enum ubyte normalDial = 0;
/// type() for a dial variant with a line.
enum ubyte lineDial = 1;
/// type() for a dial variant with a filled arc.
enum ubyte fillDial = 2;

class Dial : Valuator
{
    private
    {
        short a1_, a2_;
    }

    /// The default type() is normalDial; the default boxtype is ovalBox.
    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        box(Boxtype.ovalBox);
        selectionColor(inactiveColor); // was 37
        a1_ = 45;
        a2_ = 315;
    }

    /// Sets or gets the angles used for the minimum and maximum
    /// values. The default values are 45 and 315 (0 degrees is
    /// straight down and the angles progress clockwise). Normally
    /// angle1 is less than angle2, but if you reverse them the dial
    /// moves counter-clockwise.
    short angle1() const { return a1_; }
    void angle1(short a) { a1_ = a; }
    short angle2() const { return a2_; }
    void angle2(short a) { a2_ = a; }
    void angles(short a, short b) { a1_ = a; a2_ = b; }

    override int handle(Event event) { return handle(event, x(), y(), w(), h()); }
    override void draw() { draw(x(), y(), w(), h()); drawLabel(); }

    protected:

    /// Draws the dial within (X, Y, W, H) instead of this widget's
    /// full bounds, letting a subclass confine it to a smaller area.
    void draw(int X, int Y, int W, int H)
    {
        if (damage() & damageAll) drawBox(box(), X, Y, W, H, color());
        X += fl.core.boxDx(box());
        Y += fl.core.boxDy(box());
        W -= fl.core.boxDw(box());
        H -= fl.core.boxDh(box());
        double angle = (a2_ - a1_) * (value() - minimum()) / (maximum() - minimum()) + a1_;
        if (type() == fillDial)
        {
            // Draw this nicely in certain round box types.
            bool foo = box() > Boxtype.roundUpBox && fl.core.boxDx(box()) != 0;
            if (foo) { X--; Y--; W += 2; H += 2; }
            fl_color(activeR() ? color() : inactive(color()));
            fl_pie(X, Y, W, H, 270 - a1_, angle > a1_ ? 360 + 270 - angle : 270 - 360 - angle);
            fl_color(activeR() ? selectionColor() : inactive(selectionColor()));
            fl_pie(X, Y, W, H, 270 - angle, 270 - a1_);
            if (foo)
            {
                fl_color(activeR() ? foregroundColor : inactive(foregroundColor));
                fl_arc(X, Y, W, H, 0, 360);
            }
            return;
        }
        if (!(damage() & damageAll))
        {
            fl_color(activeR() ? color() : inactive(color()));
            fl_pie(X + 1, Y + 1, W - 2, H - 2, 0, 360);
        }
        pushMatrix();
        fl_translate(X + W / 2.0 - .5, Y + H / 2.0 - .5);
        fl_scale(W - 1, H - 1);
        fl_rotate(45 - angle);
        fl_color(activeR() ? selectionColor() : inactive(selectionColor()));
        if (type()) // lineDial
        {
            beginPolygon();
            vertex(0.0, 0.0);
            vertex(-0.04, 0.0);
            vertex(-0.25, 0.25);
            vertex(0.0, 0.04);
            endPolygon();
            fl_color(activeR() ? foregroundColor : inactive(foregroundColor));
            beginLoop();
            vertex(0.0, 0.0);
            vertex(-0.04, 0.0);
            vertex(-0.25, 0.25);
            vertex(0.0, 0.04);
            endLoop();
        }
        else
        {
            beginPolygon();
            circle(-0.20, 0.20, 0.07);
            endPolygon();
            fl_color(activeR() ? foregroundColor : inactive(foregroundColor));
            beginLoop();
            circle(-0.20, 0.20, 0.07);
            endLoop();
        }
        popMatrix();
    }

    /// Same as handle(event), but hit-tests/positions within (X, Y, W,
    /// H) instead of this widget's full bounds.
    int handle(Event event, int X, int Y, int W, int H)
    {
        switch (event)
        {
        case Event.push:
            handlePush();
            goto case Event.drag;

        case Event.drag:
        {
            int mx = (fl.core.eventX() - X - W / 2) * H;
            int my = (fl.core.eventY() - Y - H / 2) * W;
            if (!mx && !my) return 1;
            double angle = 270 - atan2(cast(double)(-my), cast(double) mx) * 180 / PI;
            double oldangle = (a2_ - a1_) * (value() - minimum()) / (maximum() - minimum()) + a1_;
            while (angle < oldangle - 180) angle += 360;
            while (angle > oldangle + 180) angle -= 360;
            double val;
            if ((a1_ < a2_) ? (angle <= a1_) : (angle >= a1_))
                val = minimum();
            else if ((a1_ < a2_) ? (angle >= a2_) : (angle <= a2_))
                val = maximum();
            else
                val = minimum() + (maximum() - minimum()) * (angle - a1_) / (a2_ - a1_);
            handleDrag(clamp(round(val)));
            return 1;
        }

        case Event.release:
            handleRelease();
            return 1;

        case Event.enter:
        case Event.leave:
            return 1;

        default:
            return 0;
        }
    }
}

// ===========================================================================
// Unit tests
// ===========================================================================

unittest
{
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto d = new Dial(0, 0, 100, 100);
    assert(d.type() == normalDial);
    assert(d.box() == Boxtype.ovalBox);
    assert(d.selectionColor() == inactiveColor);
    assert(d.angle1() == 45 && d.angle2() == 315);

    d.angles(0, 180);
    assert(d.angle1() == 0 && d.angle2() == 180);

    fl.core.resetForTest();
}

unittest
{
    // Pointer straight above center (dx == 0, dy < 0) computes to angle
    // == 180 -- per FLTK's "0 degrees is straight down, angles
    // progress clockwise" convention, straight up is the opposite point
    // on the circle -- which is exactly the midpoint of the default
    // 45..315 angle range, so value() lands at the midpoint of
    // [minimum(),maximum()] too. Each case below uses a fresh push (not
    // a continued drag) so the "unwrap toward the previous angle" logic
    // starts from a known baseline (the angle for value()'s current,
    // pre-push value).
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto d = new Dial(0, 0, 100, 100);
    d.bounds(0, 100);
    d.step(1);

    fl.core.eX_ = 50;
    fl.core.eY_ = 0;
    d.handle(Event.push);
    assert(d.value() == 50);

    fl.core.resetForTest();
}

unittest
{
    // Pointer straight below center computes to angle == 360, which
    // unwraps to 0 relative to the default value's baseline angle (45)
    // -- 0 <= a1_ (45), so it clamps to minimum().
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto d = new Dial(0, 0, 100, 100);
    d.bounds(0, 100);
    d.step(1);

    fl.core.eX_ = 50;
    fl.core.eY_ = 100;
    d.handle(Event.push);
    assert(d.value() == 0);

    fl.core.resetForTest();
}

unittest
{
    // A drag landing exactly on the widget's center (mx == my == 0) is
    // a no-op -- FLTK can't compute an angle from a zero vector.
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto d = new Dial(0, 0, 100, 100);
    d.bounds(0, 100);
    d.value(42);

    fl.core.eX_ = 50;
    fl.core.eY_ = 50;
    d.handle(Event.push);
    assert(d.value() == 42); // unchanged

    fl.core.resetForTest();
}

unittest
{
    // Reversing angle1()/angle2() reverses the drag direction (FLTK
    // doc comment: "if you reverse them the dial moves
    // counter-clockwise").
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto d = new Dial(0, 0, 100, 100);
    d.bounds(0, 100);
    d.angles(315, 45); // reversed
    d.step(1);

    // Pointer directly right of center computes to raw angle == 270
    // regardless of a1_/a2_ (same geometry as always). With the
    // *default* 45..315 range that maps to minimum() (270, unwrapped to
    // -90, is <= a1_ == 45). With the range reversed, it instead falls
    // in the interpolated middle rather than clamping at all -- proof
    // this isn't just "the same branch happens to fire," but an
    // actually different mapping from pointer position to value().
    fl.core.eX_ = 100;
    fl.core.eY_ = 50;
    d.handle(Event.push);
    assert(d.value() == 17); // round(100 * (270-315) / (45-315)) == round(16.67)

    fl.core.resetForTest();
}
