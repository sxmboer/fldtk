/*
 * Ported from FL/Fl_Fill_Slider.H + the Fl_Fill_Slider constructor in
 * src/Fl_Slider.cxx (FLTK 1.5.0, ~/Repositories/fltk).
 *
 * Faithful, complete port. Trivial subclass: sets type() to
 * fl.slider.vertFillSlider, which makes fl.slider.Slider draw/drag as
 * a filled meter (useful as a progress bar) instead of a knob-in-a-track.
 */
module fl.fill_slider;

import fl.slider : Slider, vertFillSlider;

class FillSlider : Slider
{
    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        type(vertFillSlider);
    }
}

unittest
{
    import fl.group : FlGroup;

    FlGroup.current(null);

    auto s = new FillSlider(0, 0, 20, 100, "x");
    assert(s.type() == vertFillSlider);

    FlGroup.current(null);
}
