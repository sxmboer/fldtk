/*
 * Ported from FL/Fl_Roller.H + src/Fl_Roller.cxx (FLTK 1.5.0).
 *
 * Faithful, complete port. handle()'s drag/keyboard math is a direct
 * translation, including the `static int ipos` -- like
 * fl.slider's `offcenter`, a genuine FLTK function-local static
 * shared across every Roller instance, not a bug in this port.
 *
 * draw() is structurally ported (identical branching/pixel math to
 * FLTK) and draws real pixels now -- every fl.draw call it makes
 * (fl_color()/fl_rectf()/fl_yxline()/fl_xyline(), the last two
 * originally added for fl.slider) is real.
 *
 * Rolling the wheel up or to the right adds: dragging up or right, the
 * Up and Right keys, and the mouse wheel turned up or to the right
 * (Valuator.wheelStepFactor() steps per notch). The ridges move the
 * way the value changes, by at most a third of their spacing per
 * redraw, so a jump of several steps (a wheel notch, a fast drag)
 * doesn't look like a turn the other way.
 */
module fl.roller;

import std.math : sin, trunc, isNaN;

import fl.enumerations;
import fl.valuator : Valuator;
import fl.draw;
import fl.core;

/// Fractional part of x, with the same sign as x (FLTK uses C's
/// modf() for this and discards the integer part it also returns).
private double frac(double x)
{
    return x - trunc(x);
}

class Roller : Valuator
{
    /// How far the ridges have turned, in steps, and the value (in
    /// steps) they were last drawn for.
    private double turn_ = double.nan, drawnSteps_ = double.nan;

    /// The default boxtype is upBox.
    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        box(Boxtype.upBox);
        step(1, 1000);
    }

    override int handle(Event event)
    {
        // Shared across every Roller instance -- see the module note.
        static int ipos;

        int newpos = horizontal() ? fl.core.eventX() : fl.core.eventY();

        switch (event)
        {
        case Event.push:
            if (fl.core.visibleFocus())
            {
                fl.core.focus(this);
                redraw();
            }
            handlePush();
            ipos = newpos;
            return 1;

        case Event.drag:
            // Up and right add.
            handleDrag(clamp(round(increment(previousValue(),
                horizontal() ? newpos - ipos : ipos - newpos))));
            return 1;

        case Event.release:
            handleRelease();
            return 1;

        case Event.mouseWheel:
            if (fl.core.belowmouse() is this)
            {
                int n = wheelNotches();
                if (n != 0)
                    changeByWheel(clamp(round(increment(value(), n * wheelStepFactor()))));
                return 1;
            }
            return 0;

        case Event.keyDown:
            switch (fl.core.eventKey())
            {
            case up:
                if (horizontal()) return 0;
                handleDrag(clamp(increment(value(), 1)));
                return 1;
            case down:
                if (horizontal()) return 0;
                handleDrag(clamp(increment(value(), -1)));
                return 1;
            case left:
                if (!horizontal()) return 0;
                handleDrag(clamp(increment(value(), -1)));
                return 1;
            case right:
                if (!horizontal()) return 0;
                handleDrag(clamp(increment(value(), 1)));
                return 1;
            default:
                return 0;
            }

        case Event.focus:
        case Event.unfocus:
            if (fl.core.visibleFocus())
            {
                redraw();
                return 1;
            }
            return 0;

        case Event.enter:
        case Event.leave:
            return 1;

        default:
            return 0;
        }
    }

    override void draw()
    {
        if (damage() & damageAll) drawBox();

        int rx = x() + fl.core.boxDx(box());
        int ry = y() + fl.core.boxDy(box());
        int rw = w() - fl.core.boxDw(box()) - 1;
        int rh = h() - fl.core.boxDh(box()) - 1;
        if (rw <= 0 || rh <= 0) return;

        enum double arc = 1.5;  // 1/2 the number of radians visible
        enum double delta = .2; // radians per knurl

        // Turn the ridges by the change in value, but by less than half
        // their spacing, so they move the way the value changed.
        double steps = step() != 0 ? value() / step() : 0;
        if (isNaN(drawnSteps_))
            turn_ = steps;
        else
        {
            double spacing = ((horizontal() ? rw : rh) / 2) * delta / sin(arc);
            double d = steps - drawnSteps_, limit = spacing / 3;
            if (d > limit) d = limit;
            else if (d < -limit) d = -limit;
            turn_ += d;
        }
        drawnSteps_ = steps;
        // A growing value turns the ridges right, or up.
        double offset = horizontal() ? turn_ : -turn_;

        if (horizontal())
        {
            // Shaded ends of the wheel.
            int h1 = rw / 4 + 1;
            fl_color(color());
            fl_rectf(rx + h1, ry, rw - 2 * h1, rh);
            for (int i = 0; h1; i++)
            {
                fl_color(cast(Color)(gray - i - 1));
                int h2 = (gray - i - 1) > dark3 ? 2 * h1 / 3 + 1 : 0;
                fl_rectf(rx + h2, ry, h1 - h2, rh);
                fl_rectf(rx + rw - h1, ry, h1 - h2, rh);
                h1 = h2;
            }

            if (activeR())
            {
                // Ridges.
                for (double yy = -arc + frac(offset * sin(arc) / (rw / 2) / delta) * delta; ; yy += delta)
                {
                    int yy1 = cast(int)((sin(yy) / sin(arc) + 1) * rw / 2);
                    if (yy1 <= 0) continue;
                    if (yy1 >= rw - 1) break;
                    fl_color(dark3);
                    fl_yxline(rx + yy1, ry + 1, ry + rh - 1);
                    if (yy < 0) yy1--; else yy1++;
                    fl_color(light1);
                    fl_yxline(rx + yy1, ry + 1, ry + rh - 1);
                }
                // Edges.
                h1 = rw / 8 + 1;
                fl_color(dark2);
                fl_xyline(rx + h1, ry + rh - 1, rx + rw - h1);
                fl_color(dark3);
                fl_yxline(rx, ry + rh, ry, rx + h1);
                fl_xyline(rx + rw - h1, ry, rx + rw);
                fl_color(light2);
                fl_xyline(rx + h1, ry - 1, rx + rw - h1);
                fl_yxline(rx + rw, ry, ry + rh, rx + rw - h1);
                fl_xyline(rx + h1, ry + rh, rx);
            }
        }
        else
        {
            // Shaded ends of the wheel.
            int h1 = rh / 4 + 1;
            fl_color(color());
            fl_rectf(rx, ry + h1, rw, rh - 2 * h1);
            for (int i = 0; h1; i++)
            {
                fl_color(cast(Color)(gray - i - 1));
                int h2 = (gray - i - 1) > dark3 ? 2 * h1 / 3 + 1 : 0;
                fl_rectf(rx, ry + h2, rw, h1 - h2);
                fl_rectf(rx, ry + rh - h1, rw, h1 - h2);
                h1 = h2;
            }

            if (activeR())
            {
                // Ridges.
                for (double yy = -arc + frac(offset * sin(arc) / (rh / 2) / delta) * delta; ; yy += delta)
                {
                    int yy1 = cast(int)((sin(yy) / sin(arc) + 1) * rh / 2);
                    if (yy1 <= 0) continue;
                    if (yy1 >= rh - 1) break;
                    fl_color(dark3);
                    fl_xyline(rx + 1, ry + yy1, rx + rw - 1);
                    if (yy < 0) yy1--; else yy1++;
                    fl_color(light1);
                    fl_xyline(rx + 1, ry + yy1, rx + rw - 1);
                }
                // Edges.
                h1 = rh / 8 + 1;
                fl_color(dark2);
                fl_yxline(rx + rw - 1, ry + h1, ry + rh - h1);
                fl_color(dark3);
                fl_xyline(rx + rw, ry, rx, ry + h1);
                fl_yxline(rx, ry + rh - h1, ry + rh);
                fl_color(light2);
                fl_yxline(rx, ry + h1, ry + rh - h1);
                fl_xyline(rx, ry + rh, rx + rw, ry + rh - h1);
                fl_yxline(rx + rw, ry + h1, ry);
            }
        }

        if (fl.core.focus() is this) drawFocus(Boxtype.thinUpFrame, x(), y(), w(), h());
    }
}

unittest
{
    import fl.group : FlGroup;

    FlGroup.current(null);

    auto r = new Roller(0, 0, 100, 20);
    assert(r.box() == Boxtype.upBox);
    assert(r.step() == 0.001); // step(1, 1000)

    r.draw(); // draw() calls into stubs only -- just confirm it doesn't throw.

    FlGroup.current(null);
}

unittest
{
    // Dragging moves value() by increment()-rounded steps proportional
    // to mouse travel, up adding on a vertical roller; wheel and arrow
    // keys nudge by a single step.
    import fl.group : FlGroup;

    FlGroup.current(null);
    fl.core.focus(null);
    fl.core.belowmouse(null);

    auto r = new Roller(0, 0, 100, 20); // vertical (default type)
    r.bounds(0, 100);
    r.step(1);

    fl.core.eY_ = 20;
    r.handle(Event.push);
    assert(r.value() == 0);

    fl.core.eY_ = 10; // dragged up 10px -> value increases by 10 (step=1)
    r.handle(Event.drag);
    assert(r.value() == 10);

    r.handle(Event.release);

    fl.core.belowmouse(r);
    fl.core.eDy_ = 2;
    fl.core.eState_ = stateShift;
    r.handle(Event.mouseWheel);
    assert(r.value() == 8); // two notches down, one step each with Shift
    fl.core.eState_ = 0;

    fl.core.eKeysym_ = up;
    r.handle(Event.keyDown);
    assert(r.value() == 9);
    fl.core.eKeysym_ = down;
    r.handle(Event.keyDown);
    assert(r.value() == 8);

    fl.core.eKeysym_ = left; // ignored: this roller is vertical
    assert(r.handle(Event.keyDown) == 0);

    // Also drains fl.core's shared default callback queue (pushed to
    // several times above, since no explicit callback was set) -- see
    // resetForTest()'s doc comment and the hermetic-tests note in
    // CONVENTIONS.md.
    fl.core.resetForTest();
    FlGroup.current(null);
}
