/*
 * Ported from FL/Fl_Hor_Slider.H + the Fl_Hor_Slider constructor in
 * src/Fl_Slider.cxx (FLTK 1.5.0, ~/Repositories/fltk).
 *
 * Faithful, complete port. Trivial subclass: sets type() to
 * fl.slider.horSlider, which makes fl.slider.Slider's horizontal()
 * check (and therefore its drag/keyboard math and layout) treat width
 * as the axis of motion instead of height.
 */
module fl.hor_slider;

import fl.slider : Slider, horSlider;
import fl.valuator : horizontalType;

class HorSlider : Slider
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

    auto s = new HorSlider(0, 0, 100, 20, "x");
    assert(s.type() == horSlider);
    // horizontal() itself is protected (matching FLTK); type()'s
    // low bit is what it tests.
    assert((s.type() & horizontalType) != 0);

    FlGroup.current(null);
}
