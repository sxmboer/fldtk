/*
 * Ported from FL/Fl_Simple_Counter.H + the Fl_Simple_Counter constructor
 * in src/Fl_Counter.cxx (FLTK 1.5.0).
 *
 * Faithful, complete port. Trivial subclass: sets type() to
 * fl.counter.simpleCounter, which makes fl.counter.Counter's
 * arrowWidths()/calcMouseobj()/draw() logic show only the 2 inner
 * arrow buttons instead of all 4.
 */
module fl.simple_counter;

import fl.counter : Counter, simpleCounter;

class SimpleCounter : Counter
{
    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        type(simpleCounter);
    }
}

unittest
{
    import fl.group : FlGroup;

    FlGroup.current(null);

    auto c = new SimpleCounter(0, 0, 100, 25, "x");
    assert(c.type() == simpleCounter);

    FlGroup.current(null);
}
