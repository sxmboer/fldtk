/*
 * Ported from FL/Fl_Value_Output.H + src/Fl_Value_Output.cxx (FLTK
 * 1.5.0, ~/Repositories/fltk). A lightweight, read-only-looking numeric
 * display: unlike `Fl_Value_Input`, it has no hidden text-entry widget
 * or character buffer at all -- the only way to change its value is
 * dragging (left/middle/right mouse button = 1x/10x/100x step() per
 * pixel, once the drag has moved more than 5px).
 *
 * Faithful, complete port of the numeric/event logic (handle()'s drag
 * math, matching fl.adjuster/fl.value_slider's established idiom of
 * calling into fl.valuator's protected increment()/clamp()/softclamp()/
 * handlePush()/handleDrag()/handleRelease()).
 *
 * draw() is structurally ported (same box-metrics/text-rect math as
 * FLTK) and calls fl.draw's now-real fl_font()/fl_draw() text
 * primitives, so the readout renders for real alongside the box
 * background (drawBox()).
 */
module fl.value_output;

import fl.enumerations;
import fl.valuator : Valuator;
import fl.draw;
import fl.core;

class ValueOutput : Valuator
{
    private
    {
        Font textfont_ = helvetica;
        Fontsize textsize_;
        bool soft_;
        Color textcolor_ = foregroundColor;
    }

    /// The default boxtype is noBox.
    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        box(Boxtype.noBox);
        alignment(alignLeft);
        textfont_ = helvetica;
        textsize_ = fl.enumerations.normalSize;
        textcolor_ = foregroundColor;
        soft_ = false;
    }

    /// If "soft" is turned on, the user is allowed to drag the value
    /// outside the range. If they drag the value to one of the ends,
    /// let go, then grab again and continue to drag, they can get to
    /// any value. Default is off.
    void soft(bool s) { soft_ = s; }
    bool soft() const { return soft_; }

    Font textfont() const { return textfont_; }
    void textfont(Font f) { textfont_ = f; }

    Fontsize textsize() const { return textsize_; }
    void textsize(Fontsize s) { textsize_ = s; }

    Color textcolor() const { return textcolor_; }
    void textcolor(Color c) { textcolor_ = c; }

    override int handle(Event event)
    {
        if (step() == 0) return 0;
        double v;
        int delta;
        int mx = fl.core.eventX();
        static int ix, drag;
        switch (event)
        {
        case Event.push:
            ix = mx;
            drag = fl.core.eventButton();
            handlePush();
            return 1;

        case Event.drag:
            delta = fl.core.eventX() - ix;
            if (delta > 5) delta -= 5;
            else if (delta < -5) delta += 5;
            else delta = 0;
            switch (drag)
            {
            case 3: v = increment(previousValue(), delta * 100); break;
            case 2: v = increment(previousValue(), delta * 10); break;
            default: v = increment(previousValue(), delta); break;
            }
            v = round(v);
            handleDrag(soft_ ? softclamp(v) : clamp(v));
            return 1;

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

    protected:

    override void draw()
    {
        Boxtype b = box() != Boxtype.noBox ? box() : Boxtype.downBox;
        int X = x() + fl.core.boxDx(b);
        int Y = y() + fl.core.boxDy(b);
        int W = w() - fl.core.boxDw(b);
        int H = h() - fl.core.boxDh(b);
        if (damage() & ~damageChild)
            drawBox(b, color());
        else
        {
            fl_color(color());
            fl_rectf(X, Y, W, H);
        }
        string buf = format();
        fl_color(activeR() ? textcolor() : inactive(textcolor()));
        fl_font(textfont(), textsize());
        fl_draw(buf, X, Y, W, H, alignLeft);
    }
}

// ===========================================================================
// Unit tests
// ===========================================================================

unittest
{
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto v = new ValueOutput(0, 0, 100, 25);
    assert(!v.soft());
    assert(v.box() == Boxtype.noBox);
    assert(v.textfont() == helvetica);
    assert(v.textsize() == fl.enumerations.normalSize);
    assert(v.textcolor() == foregroundColor);

    fl.core.resetForTest();
}

unittest
{
    // With step() == 0 (the Valuator default), handle() always
    // declines -- matching FLTK's "used to just display a value"
    // mode.
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto v = new ValueOutput(0, 0, 100, 25);
    assert(v.step() == 0);
    assert(v.handle(Event.push) == 0);

    fl.core.resetForTest();
}

unittest
{
    // Dragging more than 5px moves the value by (delta - 5) * step(),
    // scaled by 1x/10x/100x depending on which mouse button is held
    // (left/middle/right).
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto v = new ValueOutput(0, 0, 100, 25);
    v.bounds(-1_000_000, 1_000_000);
    v.step(1);
    v.value(0);

    fl.core.eX_ = 50;
    fl.core.eKeysym_ = button + leftMouse; // eventButton() == 1
    v.handle(Event.push);

    fl.core.eX_ = 61; // 11px right: delta = 11 - 5 = 6
    v.handle(Event.drag);
    assert(v.value() == 6);

    v.handle(Event.release);
    assert(v.value() == 6);

    fl.core.resetForTest();
}

unittest
{
    // The right mouse button scales the drag delta by 100x.
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto v = new ValueOutput(0, 0, 100, 25);
    v.bounds(-1_000_000, 1_000_000);
    v.step(1);
    v.value(0);

    fl.core.eX_ = 50;
    fl.core.eKeysym_ = button + rightMouse; // eventButton() == 3
    v.handle(Event.push);

    fl.core.eX_ = 61; // delta = 11 - 5 = 6
    v.handle(Event.drag);
    assert(v.value() == 600);

    fl.core.resetForTest();
}
