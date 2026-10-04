/*
 * Ported from FL/Fl_Output.H (FLTK 1.5.0, ~/Repositories/fltk). Trivial
 * `type(outputNormal)` subclass of fl.input's Input -- a read-only
 * display field with the same look/selection/copy behavior as Input,
 * minus editing and the on-screen-keyboard request (clearFlag(
 * needsKeyboard), matching FLTK's clear_flag(NEEDS_KEYBOARD) --
 * inert on this port's X11-only driver, no on-screen-keyboard support
 * exists here at all, but kept for fidelity/future drivers). The
 * constructor body is ported from Fl_Output::Fl_Output()
 * (src/Fl_Input.cxx), not the (empty) header.
 */
module fl.output;

import fl.input : Input;
import fl.widget : Widget;
import fl.enumerations : outputNormal;

class Output : Input
{
    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        type(outputNormal);
        clearFlag(Widget.Flag.needsKeyboard);
    }
}

unittest
{
    import fl.group : FlGroup;

    FlGroup.current(null);

    auto o = new Output(0, 0, 100, 20);
    assert(o.inputType() == 0); // outputNormal masked by inputTypeMask is inputNormal (0)
    assert(o.readonly() != 0);

    FlGroup.current(null);
}
