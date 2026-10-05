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
 * FLTK), including the three little directional-arrow icons:
 * `fastArrow_`/`mediumArrow_`/`slowArrow_`, transcribed verbatim from
 * FLTK's own `src/fastarrow.h`/`mediumarrow.h`/`slowarrow.h` (16x16
 * XBM bit patterns, one arrow-glyph per adjustment speed), drawn via
 * `fl.bitmap.Bitmap.draw()` centered in each of the three boxes, in
 * `activeR() ? selectionColor() : inactive(selectionColor())` --
 * matching FLTK's own color choice exactly. The three box
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
import fl.bitmap : Bitmap;
import fl.draw;
import fl.core;

// Verbatim transcriptions of FLTK's src/fastarrow.h/mediumarrow.h/
// slowarrow.h -- 16x16 XBM bit patterns (one arrow glyph per adjustment
// speed), unchanged byte-for-byte from the real FLTK source.
private enum int arrowW = 16;
private enum int arrowH = 16;
private immutable ubyte[32] fastArrowBits = [
    0x00, 0x00, 0x00, 0x07, 0xe0, 0x07, 0xfc, 0x03, 0xff, 0xff, 0xfc, 0x03,
    0xe0, 0x07, 0x00, 0x07, 0xe0, 0x00, 0xe0, 0x07, 0xc0, 0x3f, 0xff, 0xff,
    0xc0, 0x3f, 0xe0, 0x07, 0xe0, 0x00, 0x00, 0x00];
private immutable ubyte[32] mediumArrowBits = [
    0x40, 0x00, 0x60, 0x00, 0x70, 0x00, 0x78, 0x00, 0xfc, 0x3f, 0x78, 0x00,
    0x70, 0x00, 0x60, 0x02, 0x40, 0x06, 0x00, 0x0e, 0x00, 0x1e, 0xfc, 0x3f,
    0x00, 0x1e, 0x00, 0x0e, 0x00, 0x06, 0x00, 0x02];
private immutable ubyte[32] slowArrowBits = [
    0x40, 0x00, 0x40, 0x00, 0x60, 0x00, 0x60, 0x00, 0xf0, 0x0f, 0x60, 0x00,
    0x60, 0x00, 0x40, 0x02, 0x40, 0x02, 0x00, 0x06, 0x00, 0x06, 0xf0, 0x0f,
    0x00, 0x06, 0x00, 0x06, 0x00, 0x02, 0x00, 0x02];

// Lazily constructed (not a module constructor -- see fl.symbols's own
// note on a real circular module-constructor dependency this pattern
// sidesteps; these three are trivial data-only Bitmaps with no such
// risk here, but the lazy pattern costs nothing and stays consistent).
private Bitmap fastArrow_, mediumArrow_, slowArrow_;
private void ensureArrowBitmaps()
{
    if (fastArrow_ !is null) return;
    fastArrow_ = new Bitmap(fastArrowBits, arrowW, arrowH);
    mediumArrow_ = new Bitmap(mediumArrowBits, arrowW, arrowH);
    slowArrow_ = new Bitmap(slowArrowBits, arrowW, arrowH);
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

        ensureArrowBitmaps();
        fl_color(activeR() ? selectionColor() : inactive(selectionColor()));
        fastArrow_.draw(x() + (W - arrowW) / 2, y() + 2 * dy + (H - arrowH) / 2, W, H);
        mediumArrow_.draw(x() + dx + (W - arrowW) / 2, y() + dy + (H - arrowH) / 2, W, H);
        slowArrow_.draw(x() + 2 * dx + (W - arrowW) / 2, y() + (H - arrowH) / 2, W, H);

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
