/*
 * Ported from FL/Fl_Line_Dial.H + the Fl_Line_Dial constructor in
 * src/Fl_Dial.cxx (FLTK 1.5.0).
 *
 * Faithful, complete port. Trivial subclass: sets type() to
 * fl.dial.lineDial, which makes fl.dial.Dial's draw() render a line
 * instead of a dot knob.
 */
module fl.line_dial;

import fl.dial : Dial, lineDial;

class LineDial : Dial
{
    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        type(lineDial);
    }
}

unittest
{
    import fl.group : FlGroup;

    FlGroup.current(null);

    auto d = new LineDial(0, 0, 100, 100, "x");
    assert(d.type() == lineDial);

    FlGroup.current(null);
}
