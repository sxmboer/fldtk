/*
 * Ported from FL/Fl_Hor_Value_Slider.H + the Fl_Hor_Value_Slider
 * constructor in src/Fl_Value_Slider.cxx (FLTK 1.5.0).
 *
 * Faithful, complete port. Trivial subclass: sets type() to
 * fl.slider.horSlider on top of fl.value_slider's text-box styling.
 */
module fl.hor_value_slider;

import fl.slider : horSlider;
import fl.value_slider : ValueSlider;

class HorValueSlider : ValueSlider
{
    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        type(horSlider);
    }
}

unittest
{
    import fl.group : FlGroup;

    FlGroup.current(null);

    auto s = new HorValueSlider(0, 0, 100, 20, "x");
    assert(s.type() == horSlider);

    FlGroup.current(null);
}
