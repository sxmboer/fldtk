/*
 * Ported from FL/Fl_Round_Clock.H + the Fl_Round_Clock constructor in
 * src/Fl_Clock.cxx (FLTK 1.5.0, ~/Repositories/fltk).
 *
 * Faithful, complete port. Trivial subclass: sets type() to
 * fl.clock.roundClock and box() to noBox -- FLTK's own doc
 * comment: "A clock widget of type FL_ROUND_CLOCK. Has no box."
 */
module fl.round_clock;

import fl.clock : FlClock, roundClock;
import fl.enumerations : Boxtype;

class RoundClock : FlClock
{
    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        type(roundClock);
        box(Boxtype.noBox);
    }
}

unittest
{
    import fl.group : FlGroup;

    FlGroup.current(null);

    auto c = new RoundClock(0, 0, 100, 100, "x");
    assert(c.type() == roundClock);
    assert(c.box() == Boxtype.noBox);

    FlGroup.current(null);
}
