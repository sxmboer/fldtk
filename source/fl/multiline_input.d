/*
 * Ported from FL/Fl_Multiline_Input.H (FLTK 1.5.0).
 * Trivial `type(inputMultiline)` subclass of fl.input's Input -- the
 * constructor body is ported from Fl_Multiline_Input::Fl_Multiline_Input()
 * (src/Fl_Input.cxx), not the (empty) header.
 *
 * FLTK's doc comment notes the old FLTK 1.1.x behavior where Tab
 * inserts a literal tab character instead of navigating focus -- that's
 * `tabNav(false)`, ported already as part of fl.input_'s tab_nav_
 * field/accessor; nothing extra needed here.
 */
module fl.multiline_input;

import fl.input : Input;
import fl.enumerations : inputMultiline;

class MultilineInput : Input
{
    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        type(inputMultiline);
    }
}

unittest
{
    import fl.group : FlGroup;

    FlGroup.current(null);

    auto inp = new MultilineInput(0, 0, 100, 60);
    assert(inp.inputType() == inputMultiline);

    FlGroup.current(null);
}
