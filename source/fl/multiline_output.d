/*
 * Ported from FL/Fl_Multiline_Output.H (FLTK 1.5.0). Trivial `type(outputMultiline)` subclass of
 * fl.output's Output -- the constructor body is ported from
 * Fl_Multiline_Output::Fl_Multiline_Output() (src/Fl_Input.cxx), not
 * the (empty) header.
 */
module fl.multiline_output;

import fl.output : Output;
import fl.widget : Widget;
import fl.enumerations : outputMultiline;

class MultilineOutput : Output
{
    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        type(outputMultiline);
        clearFlag(Widget.Flag.needsKeyboard);
    }
}

unittest
{
    import fl.group : FlGroup;
    import fl.enumerations : inputMultiline;

    FlGroup.current(null);

    auto o = new MultilineOutput(0, 0, 100, 60);
    assert(o.inputType() == inputMultiline);
    assert(o.readonly() != 0);

    FlGroup.current(null);
}
