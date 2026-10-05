/*
 * Ported from FL/Fl_Slider.H + src/Fl_Slider.cxx (FLTK 1.5.0).
 *
 * Faithful, complete port of the numeric logic: handle()'s drag/keyboard
 * math (value_to_position()/position_to_value(), the linear and
 * logarithmic scales, scrollvalue()) is a direct translation, including
 * the `static int offcenter` in the drag handler, which is genuinely
 * shared across *every* Slider instance FLTK too (a plain
 * function-local static in a non-template C++ method) -- not a bug in
 * this port, a faithful copy of an unusual but real FLTK design.
 *
 * draw()/drawBg()/drawTicks() are a complete, faithful port (same box/
 * color/gripper logic as FLTK) and draw real pixels now via
 * fl.draw's fl_line()/fl_yxline()/fl_xyline()/darker()/lighter()
 * (some already added for fl.light_button, the rest new here).
 *
 * handleAt()'s Fl_Widget_Tracker "was `this` deleted mid-callback?"
 * guards are ported now too (fl.widget_tracker.WidgetTracker), matching
 * FLTK exactly: FL_PUSH's handle_push() call and each of
 * FL_KEYBOARD's four arrow-direction handle_push()/handle_drag() calls
 * are guarded, but FL_DRAG's/FL_RELEASE's own handle_drag()/
 * handle_release() calls are not -- FLTK itself doesn't guard
 * those, so this doesn't either.
 */
module fl.slider;

import std.math : log, exp;

import fl.enumerations;
import fl.valuator : Valuator;
import fl.widget_tracker : WidgetTracker;
import fl.rect : Rect;
import fl.draw;
import fl.core;

/// type() values; FL_VERTICAL/FL_VERT_SLIDER (0) is the default.
enum ubyte vertSlider     = 0;
enum ubyte horSlider      = 1;
enum ubyte vertFillSlider = 2;
enum ubyte horFillSlider  = 3;
enum ubyte vertNiceSlider = 4;
enum ubyte horNiceSlider  = 5;

/// Bitset for tick mark positions; see Slider.ticks().
alias TickPosition = ubyte;
enum : TickPosition
{
    ticksNone  = 0x00,
    ticksBelow = 0x01,
    ticksAbove = 0x02,
    ticksLeft  = 0x01,
    ticksRight = 0x02,
}

class Slider : Valuator
{
    enum ScaleType : ubyte { linearScale = 0, logScale }

    private
    {
        float sliderSize_;
        Boxtype slider_;
        ScaleType scaleType_ = ScaleType.linearScale;
        TickPosition ticks_ = ticksNone;
        ubyte numTicks_ = 11;
    }

    /// The default boxtype is downBox.
    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        box(Boxtype.downBox);
        sliderSize_ = 0;
        slider_ = Boxtype.noBox;
    }

    /// t is a type() value (vertSlider, horSlider, ...); the default
    /// boxtype is flatBox for the "nice" slider types, downBox otherwise.
    this(ubyte t, int x, int y, int w, int h, string label)
    {
        super(x, y, w, h, label);
        type(t);
        box(t == horNiceSlider || t == vertNiceSlider ? Boxtype.flatBox : Boxtype.downBox);
        sliderSize_ = 0;
        slider_ = Boxtype.noBox;
    }

    /// Fraction (0..1) of the widget's size taken up by the moving
    /// slider knob; 1 means the knob can't move. Default is 0.
    void sliderSize(double v)
    {
        if (v < 0) v = 0;
        if (v > 1) v = 1;
        if (sliderSize_ != cast(float) v)
        {
            sliderSize_ = cast(float) v;
            damage(damageExpose);
        }
    }

    float sliderSize() const { return sliderSize_; }

    override void bounds(double a, double b)
    {
        if (minimum() != a || maximum() != b)
        {
            super.bounds(a, b);
            damage(damageExpose);
        }
    }

    /**
     * Sets up the slider to represent a scrollbar-style range: pos is
     * the first visible line, size the number of visible lines, first
     * the first line overall, and total the total number of lines.
     * Returns value(pos)'s result.
     */
    bool scrollvalue(int pos, int size, int first, int total)
    {
        step(1, 1);
        if (pos + size > first + total) total = pos + size - first;
        sliderSize(size >= total ? 1.0 : cast(double) size / cast(double) total);
        bounds(first, total - size + first);
        return value(pos);
    }

    /// Gets the slider knob's own boxtype (noBox means "figure out a
    /// matching one from box()").
    Boxtype slider() const { return slider_; }
    void slider(Boxtype c) { slider_ = c; }

    ScaleType scale() const { return scaleType_; }
    void scale(ScaleType s) { scaleType_ = s; }

    TickPosition ticks() const { return ticks_; }
    ubyte numTicks() const { return numTicks_; }

    /// ticksLeft/ticksRight can be OR'd together for vertical sliders,
    /// ticksBelow/ticksAbove for horizontal ones.
    void ticks(TickPosition t, ubyte numTicks = 11)
    {
        ticks_ = t;
        numTicks_ = numTicks;
    }

    override void draw()
    {
        if (damage() & damageAll) drawBox();
        drawSlider(x() + fl.core.boxDx(box()), y() + fl.core.boxDy(box()),
            w() - fl.core.boxDw(box()), h() - fl.core.boxDh(box()));
    }

    override int handle(Event event)
    {
        if (event == Event.push && fl.core.visibleFocus())
        {
            fl.core.focus(this);
            redraw();
        }
        return handleAt(event, x() + fl.core.boxDx(box()), y() + fl.core.boxDy(box()),
            w() - fl.core.boxDw(box()), h() - fl.core.boxDh(box()));
    }

    /// Converts val to a normalized 0..1 position, using scale().
    protected double valueToPosition(double val) const
    {
        if (minimum() == maximum()) return 0.5;

        if (scaleType_ == ScaleType.logScale && minimum() > 0 && maximum() > 0 && val > 0)
        {
            double logMin = log(minimum());
            double logMax = log(maximum());
            double pos = (log(val) - logMin) / (logMax - logMin);
            if (pos > 1.0) pos = 1.0;
            else if (pos < 0.0) pos = 0.0;
            return pos;
        }

        // Linear scale, or an out-of-domain log scale falling back to it.
        double pos = (val - minimum()) / (maximum() - minimum());
        if (pos > 1.0) pos = 1.0;
        else if (pos < 0.0) pos = 0.0;
        return pos;
    }

    /// Converts a normalized 0..1 position back to a value, using scale().
    protected double positionToValue(double pos) const
    {
        if (minimum() == maximum()) return minimum();

        if (scaleType_ == ScaleType.logScale && minimum() > 0 && maximum() > 0)
        {
            double logMin = log(minimum());
            double logMax = log(maximum());
            return exp(pos * (logMax - logMin) + logMin);
        }

        return pos * (maximum() - minimum()) + minimum();
    }

    /// Adds n steps to v; on a log scale, steps are spaced evenly
    /// across the pixel range instead of the value range.
    protected double incrementLinLog(double v, int n, int range)
    {
        if (scaleType_ == ScaleType.logScale)
        {
            double pos = valueToPosition(v);
            pos = pos + (n * 4 / cast(double) range);
            return positionToValue(pos);
        }
        return increment(v, n);
    }

    private void drawBg(int x, int y, int w, int h, int s)
    {
        pushClip(x, y, w, h);
        drawBox();
        popClip();

        Color fgColor = activeR() ? foregroundColor : inactiveColor;
        if (type() == vertNiceSlider)
        {
            if (ticks_ != ticksNone) drawTicks(Rect(x, y + s / 2, w, h - s), s);
            drawBox(Boxtype.thinDownBox, x + w / 2 - 2, y, 4, h, fgColor);
        }
        else if (type() == horNiceSlider)
        {
            if (ticks_ != ticksNone) drawTicks(Rect(x + s / 2, y, w - s, h), s);
            drawBox(Boxtype.thinDownBox, x, y + h / 2 - 2, w, 4, fgColor);
        }
    }

    /// Draws the slider within (x,y,w,h); lets subclasses (e.g.
    /// fl.value_slider) confine it to a smaller area than the widget's
    /// full bounds.
    protected void drawSlider(int x, int y, int w, int h)
    {
        double val = (minimum() == maximum()) ? 0.5 : valueToPosition(value());

        int ww = horizontal() ? w : h;
        int xx, s;
        if (type() == horFillSlider || type() == vertFillSlider)
        {
            s = cast(int)(val * ww + .5);
            if (minimum() > maximum()) { s = ww - s; xx = ww - s; }
            else xx = 0;
        }
        else
        {
            s = cast(int)(sliderSize_ * ww + .5);
            int t = (horizontal() ? h : w) / 2 + 1;
            if (type() == vertNiceSlider || type() == horNiceSlider) t += 4;
            if (s < t) s = t;
            xx = cast(int)(val * (ww - s) + .5);
        }

        int xsl, ysl, wsl, hsl;
        if (horizontal())
        {
            xsl = x + xx; wsl = s; ysl = y; hsl = h;
        }
        else
        {
            ysl = y + xx; hsl = s; xsl = x; wsl = w;
        }

        drawBg(x, y, w, h, s);

        Boxtype box1 = slider_;
        if (box1 == Boxtype.noBox)
        {
            box1 = cast(Boxtype)(box() & ~1);
            if (box1 == Boxtype.noBox) box1 = Boxtype.upBox;
        }

        if (type() == vertNiceSlider)
        {
            drawBox(box1, xsl, ysl, wsl, hsl, gray);
            int d = (hsl - 4) / 2;
            drawBox(Boxtype.thinDownBox, xsl + 2, ysl + d, wsl - 4, hsl - 2 * d, selectionColor());
        }
        else if (type() == horNiceSlider)
        {
            drawBox(box1, xsl, ysl, wsl, hsl, gray);
            int d = (wsl - 4) / 2;
            drawBox(Boxtype.thinDownBox, xsl + d, ysl + 2, wsl - 2 * d, hsl - 4, selectionColor());
        }
        else
        {
            if (wsl > 0 && hsl > 0) drawBox(box1, xsl, ysl, wsl, hsl, selectionColor());

            if (type() != horFillSlider && type() != vertFillSlider && fl.core.isScheme("gtk+"))
            {
                if (w > h && wsl > (hsl + 8))
                {
                    // Horizontal grippers.
                    int hh = hsl - 8;
                    int gx = xsl + (wsl - hsl - 4) / 2;
                    int gy = ysl + 3;

                    fl_color(darker(selectionColor()));
                    fl_line(gx, gy + hh, gx + hh, gy);
                    fl_line(gx + 6, gy + hh, gx + hh + 6, gy);
                    fl_line(gx + 12, gy + hh, gx + hh + 12, gy);

                    gx++;
                    fl_color(lighter(selectionColor()));
                    fl_line(gx, gy + hh, gx + hh, gy);
                    fl_line(gx + 6, gy + hh, gx + hh + 6, gy);
                    fl_line(gx + 12, gy + hh, gx + hh + 12, gy);
                }
                else if (h > w && hsl > (wsl + 8))
                {
                    // Vertical grippers.
                    int gx = xsl + 4;
                    int gw = wsl - 8;
                    int gy = ysl + (hsl - wsl - 4) / 2;

                    fl_color(darker(selectionColor()));
                    fl_line(gx, gy + gw, gx + gw, gy);
                    fl_line(gx, gy + gw + 6, gx + gw, gy + 6);
                    fl_line(gx, gy + gw + 12, gx + gw, gy + 12);

                    gy++;
                    fl_color(lighter(selectionColor()));
                    fl_line(gx, gy + gw, gx + gw, gy);
                    fl_line(gx, gy + gw + 6, gx + gw, gy + 6);
                    fl_line(gx, gy + gw + 12, gx + gw, gy + 12);
                }
            }
        }

        drawLabel(xsl, ysl, wsl, hsl);
        if (fl.core.focus() is this)
        {
            if (type() == horFillSlider || type() == vertFillSlider) drawFocus();
            else drawFocus(box1, xsl, ysl, wsl, hsl);
        }
    }

    protected void drawTicks(const(Rect) r, int s)
    {
        if (ticks_ == ticksNone || numTicks_ == 0) return;

        fl_color(activeR() ? foregroundColor : inactiveColor);
        int n = numTicks_;
        double nd = cast(double)(n - 1);
        for (int i = 0; i < n; i++)
        {
            double v = i / nd;
            if (scaleType_ == ScaleType.logScale)
            {
                v = positionToValue(1.0 - v);
                v = (v - minimum()) / (maximum() - minimum());
            }
            if (horizontal())
            {
                int y1 = (ticks_ & ticksAbove) ? r.y() : r.y() + r.h() / 2;
                int y2 = (ticks_ & ticksBelow) ? r.b() - 1 : r.y() + r.h() / 2;
                fl_yxline(cast(int)(r.r() - v * (r.w() - 1) - 1), y1, y2);
            }
            else
            {
                int x1 = (ticks_ & ticksLeft) ? r.x() : r.x() + r.w() / 2;
                int x2 = (ticks_ & ticksRight) ? r.r() - 1 : r.x() + r.w() / 2;
                fl_xyline(x1, cast(int)(r.b() - v * (r.h() - 1) - 1), x2);
            }
        }
    }

    /// Handles event within (x,y,w,h); lets subclasses (e.g.
    /// fl.value_slider) confine it to a smaller area than the widget's
    /// full bounds.
    protected int handleAt(Event event, int x, int y, int w, int h)
    {
        switch (event)
        {
        case Event.push:
        {
            if (!fl.core.eventInside(x, y, w, h)) return 0;
            auto wp = WidgetTracker(this);
            handlePush();
            if (wp.deleted()) return 1;
            goto case Event.drag;
        }

        case Event.drag:
        {
            double val = (minimum() == maximum()) ? 0.5 : valueToPosition(value());

            int ww = horizontal() ? w : h;
            int mx = horizontal() ? fl.core.eventX() - x : fl.core.eventY() - y;
            int s;

            // Shared across every Slider instance -- see the module note.
            static int offcenter;

            if (type() == horFillSlider || type() == vertFillSlider)
            {
                s = 0;
                if (event == Event.push)
                {
                    int xx = cast(int)(val * ww + .5);
                    offcenter = mx - xx;
                    if (offcenter < -10 || offcenter > 10) offcenter = 0;
                    else return 1;
                }
            }
            else
            {
                s = cast(int)(sliderSize_ * ww + .5);
                if (s >= ww) return 0;
                int t = (horizontal() ? h : w) / 2 + 1;
                if (type() == vertNiceSlider || type() == horNiceSlider) t += 4;
                if (s < t) s = t;
                if (event == Event.push)
                {
                    int xx = cast(int)(val * (ww - s) + .5);
                    offcenter = mx - xx;
                    if (offcenter < 0) offcenter = 0;
                    else if (offcenter > s) offcenter = s;
                    else return 1;
                }
            }

            int xx = mx - offcenter;
            double v = 0;
            bool tryAgain = true;
            while (tryAgain)
            {
                tryAgain = false;
                if (xx < 0)
                {
                    xx = 0;
                    offcenter = mx;
                    if (offcenter < 0) offcenter = 0;
                }
                else if (xx > (ww - s))
                {
                    xx = ww - s;
                    offcenter = mx - xx;
                    if (offcenter > s) offcenter = s;
                }
                double pos = (ww - s) > 0 ? cast(double) xx / cast(double)(ww - s) : 0.0;
                v = round(positionToValue(pos));
                // Make sure a click outside the slider bar moves it.
                if (event == Event.push && v == value())
                {
                    offcenter = s / 2;
                    event = Event.drag;
                    tryAgain = true;
                }
            }
            handleDrag(clamp(v));
            return 1;
        }

        case Event.release:
            handleRelease();
            return 1;

        case Event.keyDown:
        {
            auto wp = WidgetTracker(this);
            switch (fl.core.eventKey())
            {
            case up:
                if (horizontal()) return 0;
                handlePush();
                if (wp.deleted()) return 1;
                handleDrag(clamp(incrementLinLog(value(), -1, h)));
                if (wp.deleted()) return 1;
                handleRelease();
                return 1;
            case down:
                if (horizontal()) return 0;
                handlePush();
                if (wp.deleted()) return 1;
                handleDrag(clamp(incrementLinLog(value(), 1, h)));
                if (wp.deleted()) return 1;
                handleRelease();
                return 1;
            case left:
                if (!horizontal()) return 0;
                handlePush();
                if (wp.deleted()) return 1;
                handleDrag(clamp(incrementLinLog(value(), -1, w)));
                if (wp.deleted()) return 1;
                handleRelease();
                return 1;
            case right:
                if (!horizontal()) return 0;
                handlePush();
                if (wp.deleted()) return 1;
                handleDrag(clamp(incrementLinLog(value(), 1, w)));
                if (wp.deleted()) return 1;
                handleRelease();
                return 1;
            default:
                return 0;
            }
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
}

unittest
{
    import fl.group : FlGroup;

    FlGroup.current(null);

    auto s = new Slider(0, 0, 20, 100);
    assert(s.box() == Boxtype.downBox);
    assert(s.sliderSize() == 0);

    s.sliderSize(1.5); // clamped to 1
    assert(s.sliderSize() == 1);

    s.draw(); // draw() calls into stubs only -- just confirm it doesn't throw.

    FlGroup.current(null);
}

unittest
{
    // Dragging from one end of a vertical slider to the other moves
    // value() from minimum() toward maximum().
    import fl.group : FlGroup;

    FlGroup.current(null);
    fl.core.focus(null);

    auto s = new Slider(0, 0, 20, 100);
    s.bounds(0, 10);
    s.sliderSize(0.1);

    fl.core.eX_ = 10;
    fl.core.eY_ = 0; // top of a vertical slider
    s.handle(Event.push);
    assert(s.value() < 1); // near the minimum

    fl.core.eY_ = 99; // bottom
    s.handle(Event.drag);
    assert(s.value() > 9); // near the maximum

    s.handle(Event.release);

    // Also drains fl.core's shared default callback queue -- see
    // resetForTest()'s doc comment and the hermetic-tests note in
    // CONVENTIONS.md.
    fl.core.resetForTest();
    FlGroup.current(null);
}

unittest
{
    // Arrow keys nudge the value by one step, respecting orientation
    // (a vertical slider ignores Left/Right).
    import fl.group : FlGroup;

    FlGroup.current(null);
    fl.core.focus(null);

    auto s = new Slider(0, 0, 20, 100); // vertical (default type)
    s.bounds(0, 10);
    s.step(1);
    s.value(5);

    assert(s.handle(Event.keyDown) == 0); // no key set yet: falls through to default

    fl.core.eKeysym_ = down;
    assert(s.handle(Event.keyDown) == 1);
    assert(s.value() == 6);

    fl.core.eKeysym_ = left; // ignored: this slider is vertical
    assert(s.handle(Event.keyDown) == 0);

    fl.core.resetForTest();
    FlGroup.current(null);
}

unittest
{
    // scrollvalue() sets up bounds()/sliderSize() from scrollbar-style
    // (pos, size, first, total) parameters.
    import fl.group : FlGroup;

    FlGroup.current(null);

    auto s = new Slider(0, 0, 20, 100);
    s.scrollvalue(0, 10, 0, 100);
    assert(s.minimum() == 0);
    assert(s.maximum() == 90);
    assert(s.sliderSize() == cast(float) 0.1);
    assert(s.value() == 0);

    FlGroup.current(null);
}
