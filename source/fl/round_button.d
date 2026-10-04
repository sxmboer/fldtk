/*
 * Ported from FL/Fl_Round_Button.H + the Fl_Round_Button constructor in
 * src/Fl_Round_Button.cxx (FLTK 1.5.0, ~/Repositories/fltk).
 *
 * Faithful, complete port. Trivial subclass: draws its "on" state as a
 * round radio-style light (downBox() = roundDownBox) rather than a
 * pushed-in box, with no surrounding box of its own.
 */
module fl.round_button;

import fl.enumerations : Boxtype, foregroundColor;
import fl.light_button : LightButton;

class RoundButton : LightButton
{
    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        box(Boxtype.noBox);
        downBox(Boxtype.roundDownBox);
        selectionColor(foregroundColor);
    }
}

unittest
{
    import fl.group : FlGroup;

    FlGroup.current(null);

    auto b = new RoundButton(0, 0, 20, 20, "x");
    assert(b.box() == Boxtype.noBox);
    assert(b.downBox() == Boxtype.roundDownBox);
    assert(b.selectionColor() == foregroundColor);

    b.draw(); // draw() calls into stubs only -- just confirm it doesn't throw.

    FlGroup.current(null);
}
