/*
 * Ported from FL/Fl_Fill_Dial.H + the Fl_Fill_Dial constructor in
 * src/Fl_Dial.cxx (FLTK 1.5.0, ~/Repositories/fltk).
 *
 * Faithful, complete port. Trivial subclass: sets type() to
 * fl.dial.fillDial, which makes fl.dial.Dial's draw() render a filled
 * arc instead of a knob/line.
 */
module fl.fill_dial;

import fl.dial : Dial, fillDial;

class FillDial : Dial
{
    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        type(fillDial);
    }
}

unittest
{
    import fl.group : FlGroup;

    FlGroup.current(null);

    auto d = new FillDial(0, 0, 100, 100, "x");
    assert(d.type() == fillDial);

    FlGroup.current(null);
}
