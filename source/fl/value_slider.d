/*
 * Ported from FL/Fl_Value_Slider.H + src/Fl_Value_Slider.cxx (FLTK
 * 1.5.0, ~/Repositories/fltk).
 *
 * Faithful, complete port. Fl_Value_Slider is Fl_Slider plus a small
 * text box showing the current value; draw()/handle() confine the
 * inherited slider to the remaining area and reuse fl.slider.Slider's
 * now-protected drawSlider()/handleAt() (the direct D equivalent of
 * FLTK's protected Fl_Slider::draw(int,int,int,int)/
 * handle(int,int,int,int,int)) for that part. draw() also calls
 * fl.draw's fl_font()/fl_draw() for the text readout itself, both real
 * now, so the whole widget draws real pixels.
 *
 * format_str() (FLTK's C++11 std::string API for
 * Fl_Valuator::format()) is just fl.valuator's format(), which this
 * port already exposes as a D string -- see that module's note.
 */
module fl.value_slider;

import fl.enumerations;
import fl.slider : Slider;
import fl.draw;
import fl.core;

class ValueSlider : Slider
{
    private
    {
        Font textfont_;
        Fontsize textsize_;
        Color textcolor_;
        short valueWidth_;
        short valueHeight_;
    }

    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        step(1, 100);
        textfont_ = helvetica;
        textsize_ = 10;
        textcolor_ = foregroundColor;
        valueWidth_ = 35;
        valueHeight_ = 25;
    }

    Font textfont() const { return textfont_; }
    void textfont(Font f) { textfont_ = f; }

    Fontsize textsize() const { return textsize_; }
    void textsize(Fontsize s) { textsize_ = s; }

    Color textcolor() const { return textcolor_; }
    void textcolor(Color c) { textcolor_ = c; }

    /// Width of the value box in pixels (horizontal mode only); clamped
    /// to [10, w()-10]. Default is 35.
    void valueWidth(int s)
    {
        if (s > w() - 10) s = w() - 10;
        if (s < 10) s = 10;
        valueWidth_ = cast(short) s;
    }

    int valueWidth() const { return valueWidth_; }

    /// Height of the value box in pixels (vertical mode only); clamped
    /// to [10, h()-10]. Default is 25.
    void valueHeight(int s)
    {
        if (s > h() - 10) s = h() - 10;
        if (s < 10) s = 10;
        valueHeight_ = cast(short) s;
    }

    int valueHeight() const { return valueHeight_; }

    override void draw()
    {
        int sxx = x(), syy = y(), sww = w(), shh = h();
        int bxx = x(), byy = y(), bww = w(), bhh = h();
        if (horizontal())
        {
            bww = valueWidth();
            sxx += valueWidth();
            sww -= valueWidth();
        }
        else
        {
            syy += valueHeight();
            bhh = valueHeight();
            shh -= valueHeight();
        }

        if (damage() & damageAll)
            drawBox(box(), sxx, syy, sww, shh, color());

        drawSlider(sxx + fl.core.boxDx(box()), syy + fl.core.boxDy(box()),
            sww - fl.core.boxDw(box()), shh - fl.core.boxDh(box()));

        drawBox(box(), bxx, byy, bww, bhh, color());

        string buf = format();
        fl_font(textfont(), textsize());
        fl_color(activeR() ? textcolor() : inactive(textcolor()));
        fl_draw(buf, bxx, byy, bww, bhh, alignClip);
    }

    override int handle(Event event)
    {
        if (event == Event.push && fl.core.visibleFocus())
        {
            fl.core.focus(this);
            redraw();
        }

        int sxx = x(), syy = y(), sww = w(), shh = h();
        if (horizontal())
        {
            sxx += valueWidth();
            sww -= valueWidth();
        }
        else
        {
            syy += valueHeight();
            shh -= valueHeight();
        }

        return handleAt(event, sxx + fl.core.boxDx(box()), syy + fl.core.boxDy(box()),
            sww - fl.core.boxDw(box()), shh - fl.core.boxDh(box()));
    }
}

unittest
{
    import fl.group : FlGroup;

    FlGroup.current(null);

    auto v = new ValueSlider(0, 0, 100, 20);
    assert(v.step() == 0.01); // step(1, 100) -> a_/b_ = 1/100
    assert(v.textfont() == helvetica);
    assert(v.textsize() == 10);
    assert(v.valueWidth() == 35);
    assert(v.valueHeight() == 25);

    v.draw(); // draw() calls into stubs only -- just confirm it doesn't throw.

    FlGroup.current(null);
}

unittest
{
    // valueWidth()/valueHeight() clamp to the widget's own size.
    import fl.group : FlGroup;

    FlGroup.current(null);

    auto v = new ValueSlider(0, 0, 100, 20);
    v.valueWidth(1000);
    assert(v.valueWidth() == v.w() - 10);

    v.valueWidth(0);
    assert(v.valueWidth() == 10);

    FlGroup.current(null);
}

unittest
{
    // Dragging a horizontal value slider still moves value() the same
    // way a plain fl.slider.Slider does, just confined to the area
    // left of the value box.
    import fl.group : FlGroup;
    import fl.slider : horSlider;

    FlGroup.current(null);
    fl.core.focus(null);

    auto v = new ValueSlider(0, 0, 200, 20);
    v.type(horSlider);
    v.bounds(0, 10);

    fl.core.eX_ = v.x() + v.valueWidth(); // just past the value box: near minimum
    fl.core.eY_ = 10;
    v.handle(Event.push);
    assert(v.value() < 5);

    fl.core.eX_ = v.x() + v.w() - 1; // near the right edge: near maximum
    v.handle(Event.drag);
    assert(v.value() > 5);

    v.handle(Event.release);

    // Also drains fl.core's shared default callback queue -- see
    // resetForTest()'s doc comment and the hermetic-tests note in
    // CLAUDE.md.
    fl.core.resetForTest();
    FlGroup.current(null);
}
