/*
 * Ported from FL/Fl_Nice_Slider.H + the Fl_Nice_Slider constructor in
 * src/Fl_Slider.cxx (FLTK 1.5.0).
 *
 * Faithful, complete port. Trivial subclass: sets type() to
 * fl.slider.vertNiceSlider and box() to flatBox, which makes
 * fl.slider.Slider draw a slimmer track with a "nicer looking" knob
 * (and optional tick marks) instead of a plain knob-in-a-track.
 */
module fl.nice_slider;

import fl.enumerations : Boxtype;
import fl.slider : Slider, vertNiceSlider;

class NiceSlider : Slider
{
    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        type(vertNiceSlider);
        box(Boxtype.flatBox);
    }
}

unittest
{
    import fl.group : FlGroup;

    FlGroup.current(null);

    auto s = new NiceSlider(0, 0, 20, 100, "x");
    assert(s.type() == vertNiceSlider);
    assert(s.box() == Boxtype.flatBox);

    FlGroup.current(null);
}
