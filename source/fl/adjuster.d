/*
 * Ported from FL/Fl_Adjuster.H + src/Fl_Adjuster.cxx (FLTK 1.5.0).
 *
 * A 3-button "slider" (fast/medium/slow buttons side by side, 100x/10x/
 * 1x step()), changed by clicking a button or by the mouse wheel over
 * one (see handle()). value_damage() is a no-op, as in FLTK: changing
 * the value doesn't change the drawn appearance.
 *
 * draw() is structurally ported (same box-splitting/layout math as
 * FLTK), including the three little directional-arrow icons, one per
 * adjustment speed, centered in each of the three boxes in
 * `activeR() ? selectionColor() : inactive(selectionColor())` --
 * matching FLTK's own color choice exactly. Unlike FLTK's 16x16 bitmaps
 * (`src/fastarrow.h`/`mediumarrow.h`/`slowarrow.h`), they are drawn as
 * polygons (`drawSpeedArrows()`), so they stay sharp at any scale. The three box
 * backgrounds (and focus rectangle) draw through `drawBox()`/
 * `drawFocus()`, same as every other widget in this project.
 *
 * `Fl_Widget_Tracker` guards in handle() (fl.widget_tracker.WidgetTracker)
 * match FLTK: FL_PUSH's handle_push() call and FL_RELEASE's
 * click-triggered handle_drag() call are guarded.
 */
module fl.adjuster;

import fl.enumerations;
import fl.valuator : Valuator;
import fl.widget_tracker : WidgetTracker;
import fl.draw;
import fl.core;

// The three speed glyphs, after FLTK's src/fastarrow.h/mediumarrow.h/
// slowarrow.h (16x16 bitmaps): an arrow pointing left above one pointing
// right, with a bigger head the faster the button adjusts. Drawn as
// polygons in the current color, so they are sharp at any scale. The
// coordinates are those of the bitmaps' 16x16 grid; the lower arrow is
// the upper one mirrored left to right, 7 units lower.
private enum int arrowW = 16;
private enum int arrowH = 16;
private immutable double[][][3] arrowShapes = [
    [[0, 4.5, 11, 0.8, 9.5, 4.5, 11, 8.2], [9.5, 4, 16, 4, 16, 5, 9.5, 5]],  // fast
    [[2, 4.5, 7, 0, 7, 9], [7, 4, 14, 4, 14, 5, 7, 5]],                       // medium
    [[4, 4.5, 7, 0, 7, 9], [7, 4, 12, 4, 12, 5, 7, 5]],                       // slow
];

private void drawSpeedArrows(int speed, int x, int y)
{
    foreach (lower; [false, true])
        foreach (shape; arrowShapes[speed])
        {
            beginPolygon();
            for (size_t i = 0; i + 1 < shape.length; i += 2)
                vertex(x + (lower ? arrowW - shape[i] : shape[i]), y + shape[i + 1] + (lower ? 7 : 0));
            endPolygon();
        }
}

class Adjuster : Valuator
{
    private
    {
        int drag_;
        bool soft_ = true;
    }

    /// The default boxtype is upBox.
    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        box(Boxtype.upBox);
        step(1, 10000);
        selectionColor(fl.enumerations.selectionColor);
        drag_ = 0;
        soft_ = true;
    }

    /// If "soft" is turned on (the default), clicks and the mouse wheel
    /// can take the value outside the range: a change stops at the end
    /// of the range, and the next one from there goes past it.
    void soft(bool s) { soft_ = s; }
    bool soft() const { return soft_; }

    protected:

    /// Changing the value does not change the appearance.
    override void valueDamage() {}

    override void draw()
    {
        int dx, dy, W, H;
        if (w() >= h())
        {
            dx = W = w() / 3;
            dy = 0;
            H = h();
        }
        else
        {
            dx = 0;
            W = w();
            dy = H = h() / 3;
        }
        drawBox(drag_ == 1 ? Boxtype.downBox : box(), x(), y() + 2 * dy, W, H, color());
        drawBox(drag_ == 2 ? Boxtype.downBox : box(), x() + dx, y() + dy, W, H, color());
        drawBox(drag_ == 3 ? Boxtype.downBox : box(), x() + 2 * dx, y(), W, H, color());

        fl_color(activeR() ? selectionColor() : inactive(selectionColor()));
        foreach (i; 0 .. 3)
        {
            int bx = x() + i * dx, by = y() + (2 - i) * dy;
            pushClip(bx, by, W, H);
            drawSpeedArrows(i, bx + (W - arrowW) / 2, by + (H - arrowH) / 2);
            popClip();
        }

        if (fl.core.focus() is this) drawFocus();
    }

    /// Which of the three buttons (x, y) is over: 1 for the fast (100x)
    /// one, 2 for the medium (10x), 3 for the slow (1x).
    private int buttonAt(int mx, int my)
    {
        int b = w() >= h() ? 3 * (mx - x()) / w() + 1 : 3 - 3 * (my - y() - 1) / h();
        return b < 1 ? 1 : b > 3 ? 3 : b;
    }

    /**
     * Ported from Fl_Adjuster::handle(). Clicking a button changes the
     * value by 10 times that button's speed (100x, 10x or 1x step()),
     * with Shift held in the other direction. The mouse wheel over a
     * button changes it by the button's speed per notch (up, or a
     * sideways wheel to the right, adds); with Shift held each notch is
     * one step, with Ctrl 100 steps. The arrow keys change it by one
     * step.
     */
    override int handle(Event event)
    {
        double v;
        int delta;
        switch (event)
        {
        case Event.push:
        {
            if (fl.core.visibleFocus()) fl.core.focus(this);
            drag_ = buttonAt(fl.core.eventX(), fl.core.eventY());
            auto wp = WidgetTracker(this);
            handlePush();
            if (wp.deleted()) return 1;
            redraw();
            return 1;
        }

        case Event.drag:
            return 1;

        case Event.mouseWheel:
        {
            int n = wheelNotches();
            if (n == 0) return 0;
            int f = [100, 10, 1][buttonAt(fl.core.eventX(), fl.core.eventY()) - 1];
            auto state = fl.core.eventState();
            if (state & stateShift) f = 1;
            else if (state & stateCtrl) f = 100;
            v = increment(value(), n * f);
            changeByWheel(soft_ ? softclamp(v) : clamp(v));
            return 1;
        }

        case Event.release:
            if (fl.core.eventIsClick()) // detect click but no drag
            {
                if (fl.core.eventState() & (stateShift | stateCapsLock | stateCtrl | stateAlt))
                    delta = -10;
                else
                    delta = 10;
                switch (drag_)
                {
                case 3: v = increment(previousValue(), delta); break;
                case 2: v = increment(previousValue(), delta * 10); break;
                default: v = increment(previousValue(), delta * 100); break;
                }
                auto wp = WidgetTracker(this);
                handleDrag(soft_ ? softclamp(v) : clamp(v));
                if (wp.deleted()) return 1;
            }
            drag_ = 0;
            redraw();
            handleRelease();
            return 1;

        case Event.keyDown:
            switch (fl.core.eventKey())
            {
            case up:
                if (w() > h()) return 0;
                handleDrag(clamp(increment(value(), -1)));
                return 1;
            case down:
                if (w() > h()) return 0;
                handleDrag(clamp(increment(value(), 1)));
                return 1;
            case left:
                if (w() < h()) return 0;
                handleDrag(clamp(increment(value(), -1)));
                return 1;
            case right:
                if (w() < h()) return 0;
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
            break;
        }
        return 0;
    }
}

// ===========================================================================
// Unit tests
// ===========================================================================

unittest
{
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto a = new Adjuster(0, 0, 300, 30); // w() >= h() -> horizontal layout
    assert(a.soft());
    assert(a.step() == 1.0 / 10000.0); // step(1, 10000) from the ctor
    assert(a.box() == Boxtype.upBox);

    fl.core.resetForTest();
}

unittest
{
    // The wheel changes the value by the speed of the button under the
    // mouse per notch (the leftmost button is the fast, 100x one); Shift
    // makes a notch one step, Ctrl 100 steps. Dragging changes nothing.
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto a = new Adjuster(0, 0, 300, 30);
    a.bounds(-1_000_000, 1_000_000);
    a.step(1);
    a.value(0);

    fl.core.eX_ = 10;   // fast button
    fl.core.eY_ = 15;
    fl.core.eDy_ = -1;  // one notch up
    assert(a.handle(Event.mouseWheel) == 1);
    assert(a.value() == 100);

    fl.core.eX_ = 250;  // slow button
    fl.core.eDy_ = 2;   // two notches down
    a.handle(Event.mouseWheel);
    assert(a.value() == 98);

    fl.core.eX_ = 150;  // medium button
    fl.core.eDy_ = -1;
    fl.core.eState_ = stateShift;
    a.handle(Event.mouseWheel);
    assert(a.value() == 99);
    fl.core.eState_ = stateCtrl;
    a.handle(Event.mouseWheel);
    assert(a.value() == 199);
    fl.core.eState_ = 0;
    fl.core.eDy_ = 0;

    fl.core.eX_ = 10;
    a.handle(Event.push);
    fl.core.eX_ = 200;
    a.handle(Event.drag);
    assert(a.value() == 199);
    a.handle(Event.release);
    assert(a.value() == 199);

    fl.core.resetForTest();
}

unittest
{
    // Clicking (no drag) increments by 10x the held button's own
    // multiplier; Shift+click decrements instead.
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto a = new Adjuster(0, 0, 300, 30);
    a.bounds(-1_000_000, 1_000_000);
    a.step(1);
    a.value(0);

    // Leftmost third: the fast (100x) button, drag_ == 1.
    fl.core.eX_ = 10;
    fl.core.eY_ = 15;
    a.handle(Event.push);
    fl.core.eIsClick_ = true;
    a.handle(Event.release);
    assert(a.value() == 1000); // 10 * 100 * step(1) for a plain click

    a.value(0);
    fl.core.eX_ = 10;
    a.handle(Event.push);
    fl.core.eIsClick_ = true;
    fl.core.eState_ = stateShift;
    a.handle(Event.release);
    assert(a.value() == -1000);

    fl.core.resetForTest();
}

unittest
{
    // FL_KEYBOARD arrow keys nudge value() by +-1 step, but only along
    // the adjuster's long axis (matching FLTK's w()><h() checks).
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto wide = new Adjuster(0, 0, 300, 30); // w() > h(): only Left/Right work
    wide.bounds(-1000, 1000);
    wide.step(1);
    wide.value(0);

    fl.core.eKeysym_ = right;
    assert(wide.handle(Event.keyDown) == 1);
    assert(wide.value() == 1);

    fl.core.eKeysym_ = up;
    assert(wide.handle(Event.keyDown) == 0); // ignored: wide, not tall
    assert(wide.value() == 1); // unchanged

    fl.core.resetForTest();
}
