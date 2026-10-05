/*
 * Ported from FL/Fl_Int_Input.H (FLTK 1.5.0).
 * Trivial `type(inputInt)` subclass of fl.input's Input -- the
 * constructor body is ported from Fl_Int_Input::Fl_Int_Input()
 * (src/Fl_Input.cxx), not the (empty) header.
 */
module fl.int_input;

import fl.input : Input;
import fl.widget : Widget;
import fl.enumerations : inputInt;

class IntInput : Input
{
    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        type(inputInt);
        clearFlag(Widget.Flag.macUseAccentsMenu);
    }
}

unittest
{
    import fl.group : FlGroup;

    FlGroup.current(null);

    auto inp = new IntInput(0, 0, 100, 20);
    assert(inp.inputType() == inputInt);

    FlGroup.current(null);
}
