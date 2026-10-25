/*
 * Ported from FL/Fl_Adjuster.H + src/Fl_Adjuster.cxx (FLTK 1.5.0).
 *
 * Faithful, complete port of the numeric/event logic: a 3-button
 * "slider" (small/medium/large step buttons side by side), where
 * dragging any button adjusts by 1x/10x/100x step() per pixel, and
 * clicking (no drag) adjusts by 10x that button's step (Shift+click for
 * -10x). handle()'s FL_PUSH/FL_DRAG/FL_RELEASE/FL_KEYBOARD/FL_FOCUS/
 * FL_UNFOCUS/FL_ENTER/FL_LEAVE cases and value_damage() (a no-op here,
 * matching FLTK -- changing the value doesn't itself change the
 * drawn appearance) are all ported 1:1.
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
 * match FLTK exactly: FL_PUSH's handle_push() call and FL_RELEASE's
 * click-triggered handle_drag() call are guarded; FL_DRAG's own
 * handle_drag() isn't (FLTK doesn't guard it either).
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
        int ix_;
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

    /// If "soft" is turned on (the default), the user is allowed to
    /// drag the value outside the range. If they drag the value to one
    /// of the ends, let go, then grab again and continue to drag, they
    /// can get to any value.
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

    override int handle(Event event)
    {
        double v;
        int delta;
        int mx = fl.core.eventX();
        switch (event)
        {
        case Event.push:
        {
            if (fl.core.visibleFocus()) fl.core.focus(this);
            ix_ = mx;
            if (w() >= h())
                drag_ = 3 * (mx - x()) / w() + 1;
            else
                drag_ = 3 - 3 * (fl.core.eventY() - y() - 1) / h();
            auto wp = WidgetTracker(this);
            handlePush();
            if (wp.deleted()) return 1;
            redraw();
            return 1;
        }

        case Event.drag:
            if (w() >= h())
            {
                delta = x() + (drag_ - 1) * w() / 3; // left edge of button
                if (mx < delta)
                    delta = mx - delta;
                else if (mx > (delta + w() / 3)) // right edge of button
                    delta = mx - delta - w() / 3;
                else
                    delta = 0;
            }
            else
            {
                if (mx < x())
                    delta = mx - x();
                else if (mx > (x() + w()))
                    delta = mx - x() - w();
                else
                    delta = 0;
            }
            switch (drag_)
            {
            case 3: v = increment(previousValue(), delta); break;
            case 2: v = increment(previousValue(), delta * 10); break;
            default: v = increment(previousValue(), delta * 100); break;
            }
            handleDrag(soft_ ? softclamp(v) : clamp(v));
            return 1;

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
    // FL_PUSH picks which of the 3 buttons was hit (based on x position,
    // for a horizontal layout); the leftmost is the "fast" (100x step)
    // button (drag_ == 1), the rightmost the "slow" (1x step) one
    // (drag_ == 3) -- see draw()'s fastarrow/mediumarrow/slowarrow
    // ordering FLTK. FL_DRAG only registers movement once the
    // pointer leaves the held button's own span (delta measures how far
    // past the edge it went), matching the "3-button slider" FLTK
    // doc comment describes.
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto a = new Adjuster(0, 0, 300, 30);
    a.bounds(-1_000_000, 1_000_000);
    a.step(1); // simplifies the expected numbers below
    a.value(0);

    // Push in the leftmost third: the fast (100x) button, drag_ == 1.
    fl.core.eX_ = 10;
    fl.core.eY_ = 15;
    assert(a.handle(Event.push) == 1);

    // Drag 10px past that button's own right edge (x in [0,100)) -> a
    // delta of 10, times the fast button's 100x multiplier.
    fl.core.eX_ = 110;
    a.handle(Event.drag);
    assert(a.value() == 1000);

    a.handle(Event.release);
    assert(a.value() == 1000); // release with no further movement: unchanged

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
