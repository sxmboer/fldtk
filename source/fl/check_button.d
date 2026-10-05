/*
 * Ported from FL/Fl_Check_Button.H + src/Fl_Check_Button.cxx (FLTK
 * 1.5.0).
 *
 * Faithful, complete port. Trivial subclass of fl.light_button: draws
 * its "on" state as a checkmark (downBox() = downBox) instead of a
 * pushed-in box, with no surrounding box of its own.
 */
module fl.check_button;

import fl.enumerations : Boxtype, foregroundColor;
import fl.light_button : LightButton;

class CheckButton : LightButton
{
    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        box(Boxtype.noBox);
        downBox(Boxtype.downBox);
        selectionColor(foregroundColor);
    }
}

unittest
{
    import fl.group : FlGroup;

    FlGroup.current(null);

    auto b = new CheckButton(0, 0, 20, 20, "x");
    assert(b.box() == Boxtype.noBox);
    assert(b.downBox() == Boxtype.downBox);
    assert(b.selectionColor() == foregroundColor);

    b.draw(); // draw() calls into stubs only -- just confirm it doesn't throw.

    FlGroup.current(null);
}
