/*
 * Ported from FL/Fl_Positioner.H + src/Fl_Positioner.cxx (FLTK 1.5.0,
 * ~/Repositories/fltk). "Provided for Forms compatibility. It provides
 * 2D input" (FLTK's own doc comment): a crosshair the user can drag
 * anywhere inside the box, with independent min/max/step/value ranges
 * for X and Y -- not an `Fl_Valuator` subclass at all (unlike every
 * other widget ported so far in this section), since it needs two
 * independent value axes rather than Valuator's single one.
 *
 * Faithful, complete port, including the protected `draw(int,int,int,
 * int)`/`handle(int,int,int,int,int)` overloads FLTK exposes
 * specifically so a subclass can confine the crosshair area to less
 * than the full widget bounds (its own doc comment: "these allow
 * subclasses to put the dial in a smaller area").
 *
 * draw() draws real pixels: `drawBox()`, the crosshair itself
 * (`fl_xyline()`/`fl_yxline()`, both real on Linux, see
 * fl.draw's module comment), and `drawLabel()` (see fl.widget's
 * drawLabel()) all work.
 */
module fl.positioner;

import fl.enumerations;
import fl.widget : Widget;
import fl.draw;
import fl.core;

private double flinear(double val, double smin, double smax, double gmin, double gmax)
{
    if (smin == smax) return gmax;
    return gmin + (gmax - gmin) * (val - smin) / (smax - smin);
}

class Positioner : Widget
{
    private
    {
        double xmin_, ymin_;
        double xmax_, ymax_;
        double xvalue_, yvalue_;
        double xstep_, ystep_;
    }

    /// The default boxtype is downBox.
    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        box(Boxtype.downBox);
        selectionColor(red);
        alignment(alignBottom);
        when(whenChanged);
        xmin_ = ymin_ = 0;
        xmax_ = ymax_ = 1;
        xvalue_ = yvalue_ = .5;
        xstep_ = ystep_ = 0;
    }

    double xvalue() const { return xvalue_; }
    double yvalue() const { return yvalue_; }

    /// Sets the current position in x and y. Returns true if it
    /// changed.
    bool value(double X, double Y)
    {
        clearChanged();
        if (X == xvalue_ && Y == yvalue_) return false;
        xvalue_ = X;
        yvalue_ = Y;
        redraw();
        return true;
    }

    bool xvalue(double X) { return value(X, yvalue_); }
    bool yvalue(double Y) { return value(xvalue_, Y); }

    /// Sets the X axis bounds.
    void xbounds(double a, double b)
    {
        if (a != xmin_ || b != xmax_)
        {
            xmin_ = a;
            xmax_ = b;
            redraw();
        }
    }

    double xminimum() const { return xmin_; }
    /// Same as xbounds(a, xmaximum()).
    void xminimum(double a) { xbounds(a, xmax_); }
    double xmaximum() const { return xmax_; }
    /// Same as xbounds(xminimum(), a).
    void xmaximum(double a) { xbounds(xmin_, a); }

    /// Sets the Y axis bounds.
    void ybounds(double a, double b)
    {
        if (a != ymin_ || b != ymax_)
        {
            ymin_ = a;
            ymax_ = b;
            redraw();
        }
    }

    double yminimum() const { return ymin_; }
    /// Same as ybounds(a, ymaximum()).
    void yminimum(double a) { ybounds(a, ymax_); }
    double ymaximum() const { return ymax_; }
    /// Same as ybounds(yminimum(), a).
    void ymaximum(double a) { ybounds(ymin_, a); }

    /// Sets the stepping value for the X axis.
    void xstep(double a) { xstep_ = a; }
    /// Sets the stepping value for the Y axis.
    void ystep(double a) { ystep_ = a; }

    override int handle(Event event) { return handle(event, x(), y(), w(), h()); }
    override void draw() { draw(x(), y(), w(), h()); drawLabel(); }

    protected:

    /// Draws the crosshair within (X, Y, W, H) instead of this widget's
    /// full bounds, letting a subclass confine it to a smaller area.
    void draw(int X, int Y, int W, int H)
    {
        int x1 = X + 4;
        int y1 = Y + 4;
        int w1 = W - 2 * 4;
        int h1 = H - 2 * 4;
        int xx = cast(int)(flinear(xvalue(), xmin_, xmax_, x1, x1 + w1 - 1) + .5);
        int yy = cast(int)(flinear(yvalue(), ymin_, ymax_, y1, y1 + h1 - 1) + .5);
        drawBox(box(), X, Y, W, H, color());
        fl_color(selectionColor());
        fl_xyline(x1, yy, x1 + w1);
        fl_yxline(xx, y1, y1 + h1);
    }

    /// Same as handle(event), but hit-tests/positions within (X, Y, W,
    /// H) instead of this widget's full bounds.
    int handle(Event event, int X, int Y, int W, int H)
    {
        switch (event)
        {
        case Event.push:
        case Event.drag:
        case Event.release:
        {
            double x1 = X + 4;
            double y1 = Y + 4;
            double w1 = W - 2 * 4;
            double h1 = H - 2 * 4;
            double xx = flinear(fl.core.eventX(), x1, x1 + w1 - 1.0, xmin_, xmax_);
            if (xstep_) xx = cast(int)(xx / xstep_ + 0.5) * xstep_;
            if (xmin_ < xmax_)
            {
                if (xx < xmin_) xx = xmin_;
                if (xx > xmax_) xx = xmax_;
            }
            else
            {
                if (xx > xmin_) xx = xmin_;
                if (xx < xmax_) xx = xmax_;
            }
            double yy = flinear(fl.core.eventY(), y1, y1 + h1 - 1.0, ymin_, ymax_);
            if (ystep_) yy = cast(int)(yy / ystep_ + 0.5) * ystep_;
            if (ymin_ < ymax_)
            {
                if (yy < ymin_) yy = ymin_;
                if (yy > ymax_) yy = ymax_;
            }
            else
            {
                if (yy > ymin_) yy = ymin_;
                if (yy < ymax_) yy = ymax_;
            }
            if (xx != xvalue_ || yy != yvalue_)
            {
                xvalue_ = xx;
                yvalue_ = yy;
                setChanged();
                redraw();
            }
            if (!(when() & whenChanged || (when() & whenRelease && event == Event.release)))
                return 1;
            if (changed() || when() & whenNotChanged)
            {
                CallbackReason reason = changed() ? CallbackReason.changed : CallbackReason.selected;
                if (event == Event.release)
                {
                    clearChanged();
                    reason = CallbackReason.released;
                }
                doCallback(reason);
            }
            return 1;
        }
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

    auto p = new Positioner(0, 0, 100, 100);
    assert(p.box() == Boxtype.downBox);
    assert(p.selectionColor() == red);
    assert(p.xvalue() == 0.5 && p.yvalue() == 0.5);
    assert(p.xminimum() == 0 && p.xmaximum() == 1);
    assert(p.yminimum() == 0 && p.ymaximum() == 1);

    fl.core.resetForTest();
}

unittest
{
    // value()/xvalue()/yvalue() report whether they actually changed
    // anything, and redraw() only when they do.
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto p = new Positioner(0, 0, 100, 100);
    assert(p.value(0.5, 0.5) == false); // already there: no-op
    assert(p.value(0.25, 0.75) == true);
    assert(p.xvalue() == 0.25 && p.yvalue() == 0.75);

    assert(p.xvalue(0.9) == true);
    assert(p.xvalue() == 0.9 && p.yvalue() == 0.75);

    fl.core.resetForTest();
}

unittest
{
    // FL_PUSH/FL_DRAG map the event position onto [xmin,xmax]x[ymin,
    // ymax] and clamp to it.
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto p = new Positioner(0, 0, 108, 108); // interior: [4, 103] both axes
    p.xbounds(0, 100);
    p.ybounds(0, 100);

    fl.core.eX_ = 4; // left edge of the interior -> xvalue -> xmin
    fl.core.eY_ = 103; // bottom edge -> ymax
    p.handle(Event.push);
    assert(p.xvalue() == 0);
    assert(p.yvalue() == 100);

    fl.core.eX_ = -1000; // far outside -> clamped to xmin
    p.handle(Event.drag);
    assert(p.xvalue() == 0);

    fl.core.resetForTest();
}

unittest
{
    // xstep()/ystep() round the dragged value to the nearest multiple.
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto p = new Positioner(0, 0, 108, 108);
    p.xbounds(0, 100);
    p.xstep(10);

    fl.core.eX_ = 30; // interior x in [4,103], value maps to roughly 26.7
    fl.core.eY_ = 4;
    p.handle(Event.push);
    assert(p.xvalue() == 30); // rounded to the nearest step of 10

    fl.core.resetForTest();
}

unittest
{
    // when() gates the callback: whenChanged fires on every change,
    // and the reason is "released" specifically for FL_RELEASE.
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto p = new Positioner(0, 0, 108, 108);
    p.xbounds(0, 100);
    p.ybounds(0, 100);

    CallbackReason gotReason;
    int calls;
    p.callback((w) { calls++; gotReason = fl.core.callbackReason(); });

    fl.core.eX_ = 4;
    fl.core.eY_ = 4;
    p.handle(Event.push);
    assert(calls == 1);
    assert(gotReason == CallbackReason.changed);

    fl.core.eX_ = 103;
    p.handle(Event.release);
    assert(calls == 2);
    assert(gotReason == CallbackReason.released);

    fl.core.resetForTest();
}
