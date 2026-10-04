/*
 * Ported from FL/Fl_Hor_Fill_Slider.H + the Fl_Hor_Fill_Slider
 * constructor in src/Fl_Slider.cxx (FLTK 1.5.0, ~/Repositories/fltk).
 *
 * Faithful, complete port. Trivial subclass: sets type() to
 * fl.slider.horFillSlider -- the horizontal counterpart of
 * fl.fill_slider.FillSlider.
 */
module fl.hor_fill_slider;

import fl.slider : Slider, horFillSlider;

class HorFillSlider : Slider
{
    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        type(horFillSlider);
    }
}

unittest
{
    import fl.group : FlGroup;

    FlGroup.current(null);

    auto s = new HorFillSlider(0, 0, 100, 20, "x");
    assert(s.type() == horFillSlider);

    FlGroup.current(null);
}
