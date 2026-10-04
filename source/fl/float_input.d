/*
 * Ported from FL/Fl_Float_Input.H (FLTK 1.5.0, ~/Repositories/fltk).
 * Trivial `type(inputFloat)` subclass of fl.input's Input -- the
 * constructor body is ported from Fl_Float_Input::Fl_Float_Input()
 * (src/Fl_Input.cxx), not the (empty) header.
 */
module fl.float_input;

import fl.input : Input;
import fl.widget : Widget;
import fl.enumerations : inputFloat;

class FloatInput : Input
{
    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        type(inputFloat);
        clearFlag(Widget.Flag.macUseAccentsMenu);
    }
}

unittest
{
    import fl.group : FlGroup;
    import fl.enumerations : inputFloat;

    FlGroup.current(null);

    auto inp = new FloatInput(0, 0, 100, 20);
    assert(inp.inputType() == inputFloat);

    FlGroup.current(null);
}
