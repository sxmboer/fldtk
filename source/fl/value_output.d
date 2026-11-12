/*
 * Ported from FL/Fl_Value_Output.H + src/Fl_Value_Output.cxx (FLTK
 * 1.5.0). A read-only numeric display: only the program changes its
 * value, with value(). The user cannot change it with the mouse or the
 * keyboard, so what it shows is always what the program set. step()
 * only sets how the value is formatted (see Valuator.format()).
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
    }

    Font textfont() const { return textfont_; }
    void textfont(Font f) { textfont_ = f; }

    Fontsize textsize() const { return textsize_; }
    void textsize(Fontsize s) { textsize_ = s; }

    Color textcolor() const { return textcolor_; }
    void textcolor(Color c) { textcolor_ = c; }

    /// Takes no user input. It accepts entering and leaving so that its
    /// tooltip shows.
    override int handle(Event event)
    {
        return event == Event.enter || event == Event.leave;
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
    assert(v.box() == Boxtype.noBox);
    assert(v.textfont() == helvetica);
    assert(v.textsize() == fl.enumerations.normalSize);
    assert(v.textcolor() == foregroundColor);

    fl.core.resetForTest();
}

unittest
{
    // No user input changes the value, whatever step() is.
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto v = new ValueOutput(0, 0, 100, 25);
    v.bounds(-1_000_000, 1_000_000);
    v.step(1);
    v.value(0);

    fl.core.eDy_ = -1;
    assert(v.handle(Event.mouseWheel) == 0);
    fl.core.eDy_ = 0;
    fl.core.eX_ = 50;
    fl.core.eKeysym_ = button + leftMouse;
    assert(v.handle(Event.push) == 0);
    assert(v.handle(Event.drag) == 0);
    assert(v.handle(Event.keyDown) == 0);
    assert(v.value() == 0);
    assert(v.handle(Event.enter) == 1);

    fl.core.resetForTest();
}
