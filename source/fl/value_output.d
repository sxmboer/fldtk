/*
 * Ported from FL/Fl_Value_Output.H + src/Fl_Value_Output.cxx (FLTK
 * 1.5.0). A lightweight, read-only-looking numeric
 * display: unlike `Fl_Value_Input`, it has no hidden text-entry widget
 * or character buffer at all -- the user changes its value only with
 * the mouse wheel, and only when step() is nonzero (see handle()).
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

    /// If "soft" is turned on, the mouse wheel can take the value
    /// outside the range: a turn stops at the end of the range, and the
    /// next turn from there goes past it. Default is off.
    void soft(bool s) { soft_ = s; }
    bool soft() const { return soft_; }

    Font textfont() const { return textfont_; }
    void textfont(Font f) { textfont_ = f; }

    Fontsize textsize() const { return textsize_; }
    void textsize(Fontsize s) { textsize_ = s; }

    Color textcolor() const { return textcolor_; }
    void textcolor(Color c) { textcolor_ = c; }

    /// Ported from Fl_Value_Output::handle(). With a nonzero step() the
    /// mouse wheel changes the value: a notch up, or a sideways wheel to
    /// the right, adds `wheelStepFactor()` steps (10; 1 with Shift held,
    /// 100 with Ctrl), down or to the left subtracts them. With step() 0
    /// the widget only displays its value.
    override int handle(Event event)
    {
        if (step() == 0) return 0;
        switch (event)
        {
        case Event.mouseWheel:
        {
            int n = wheelNotches();
            if (n == 0) return 0;
            double v = round(increment(value(), n * wheelStepFactor()));
            changeByWheel(soft_ ? softclamp(v) : clamp(v));
            return 1;
        }

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
    // The wheel: a notch up adds 10 steps, with Ctrl 100; dragging does
    // nothing.
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto v = new ValueOutput(0, 0, 100, 25);
    v.bounds(-1_000_000, 1_000_000);
    v.step(1);
    v.value(0);

    fl.core.eDy_ = -1;
    assert(v.handle(Event.mouseWheel) == 1);
    assert(v.value() == 10);
    fl.core.eState_ = stateCtrl;
    fl.core.eDy_ = 1;
    v.handle(Event.mouseWheel);
    assert(v.value() == -90);

    fl.core.eState_ = 0;
    fl.core.eDy_ = 0;
    fl.core.eX_ = 50;
    fl.core.eKeysym_ = button + leftMouse;
    assert(v.handle(Event.push) == 0);

    fl.core.resetForTest();
}
