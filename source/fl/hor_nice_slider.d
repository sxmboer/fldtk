/*
 * Ported from FL/Fl_Hor_Nice_Slider.H + the Fl_Hor_Nice_Slider
 * constructor in src/Fl_Slider.cxx (FLTK 1.5.0).
 *
 * Faithful, complete port. Trivial subclass: the horizontal
 * counterpart of fl.nice_slider.NiceSlider.
 */
module fl.hor_nice_slider;

import fl.enumerations : Boxtype;
import fl.slider : Slider, horNiceSlider;

class HorNiceSlider : Slider
{
    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        type(horNiceSlider);
        box(Boxtype.flatBox);
    }
}

unittest
{
    import fl.group : FlGroup;

    FlGroup.current(null);

    auto s = new HorNiceSlider(0, 0, 100, 20, "x");
    assert(s.type() == horNiceSlider);
    assert(s.box() == Boxtype.flatBox);

    FlGroup.current(null);
}
