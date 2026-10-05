/*
 * Ported from FL/Fl_Roller.H + src/Fl_Roller.cxx (FLTK 1.5.0).
 *
 * Faithful, complete port. handle()'s drag/wheel/keyboard math is a
 * direct translation, including the `static int ipos` -- like
 * fl.slider's `offcenter`, a genuine FLTK function-local static
 * shared across every Roller instance, not a bug in this port.
 *
 * draw() is structurally ported (identical branching/pixel math to
 * FLTK) and draws real pixels now -- every fl.draw call it makes
 * (fl_color()/fl_rectf()/fl_yxline()/fl_xyline(), the last two
 * originally added for fl.slider) is real.
 */
module fl.roller;

import std.math : sin, trunc;

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
            handleDrag(clamp(round(increment(previousValue(), newpos - ipos))));
            return 1;

        case Event.release:
            handleRelease();
            return 1;

        case Event.mouseWheel:
            if (fl.core.belowmouse() is this)
            {
                if (horizontal())
                {
                    if (fl.core.eventDx() != 0)
                        handleDrag(clamp(round(increment(value(), -fl.core.eventDx()))));
                }
                else
                {
                    if (fl.core.eventDy() != 0)
                        handleDrag(clamp(round(increment(value(), -fl.core.eventDy()))));
                }
                return 1;
            }
            return 0;

        case Event.keyDown:
            switch (fl.core.eventKey())
            {
            case up:
                if (horizontal()) return 0;
                handleDrag(clamp(increment(value(), -1)));
                return 1;
            case down:
                if (horizontal()) return 0;
                handleDrag(clamp(increment(value(), 1)));
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

        int offset = step() != 0 ? cast(int)(value() / step()) : 0;
        enum double arc = 1.5;  // 1/2 the number of radians visible
        enum double delta = .2; // radians per knurl

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
    // to mouse travel; wheel and arrow keys nudge by a single step.
    import fl.group : FlGroup;

    FlGroup.current(null);
    fl.core.focus(null);
    fl.core.belowmouse(null);

    auto r = new Roller(0, 0, 100, 20); // vertical (default type)
    r.bounds(0, 100);
    r.step(1);

    fl.core.eY_ = 0;
    r.handle(Event.push);
    assert(r.value() == 0);

    fl.core.eY_ = 10; // dragged down 10px -> value increases by 10 (step=1)
    r.handle(Event.drag);
    assert(r.value() == 10);

    r.handle(Event.release);

    fl.core.belowmouse(r);
    fl.core.eDy_ = 2;
    r.handle(Event.mouseWheel);
    assert(r.value() == 8); // increment(value(), -e_dy) = 10 + (-2)

    fl.core.eKeysym_ = down;
    r.handle(Event.keyDown);
    assert(r.value() == 9);

    fl.core.eKeysym_ = left; // ignored: this roller is vertical
    assert(r.handle(Event.keyDown) == 0);

    // Also drains fl.core's shared default callback queue (pushed to
    // several times above, since no explicit callback was set) -- see
    // resetForTest()'s doc comment and the hermetic-tests note in
    // CONVENTIONS.md.
    fl.core.resetForTest();
    FlGroup.current(null);
}
