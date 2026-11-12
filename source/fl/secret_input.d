/*
 * Ported from FL/Fl_Secret_Input.H (FLTK 1.5.0).
 * Trivial `type(inputSecret)` subclass of fl.input's Input -- masks
 * every character with a bullet glyph on display (fl.input_'s expand(),
 * see its module comment for `secretInputCharacter`). The constructor
 * body is ported from Fl_Secret_Input::Fl_Secret_Input()
 * (src/Fl_Input.cxx), not the (empty) header.
 *
 * handle() is ported from Fl_Secret_Input::handle(): marked text from
 * an input method (`fl.core.hasMarkedText()`) is not left selected, so
 * it isn't underlined and the field doesn't show how many characters
 * are being composed.
 */
module fl.secret_input;

import fl.input : Input;
import fl.widget : Widget;
import fl.enumerations : inputSecret, Event;
import fl.core : markedTextActive;

class SecretInput : Input
{
    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        type(inputSecret);
        clearFlag(Widget.Flag.macUseAccentsMenu);
    }

    override int handle(Event event)
    {
        int retval = super.handle(event);
        if (event == Event.keyDown && markedTextActive())
            mark(insertPosition()); // don't underline marked text
        return retval;
    }
}

unittest
{
    import fl.group : FlGroup;

    FlGroup.current(null);

    auto inp = new SecretInput(0, 0, 100, 20);
    assert(inp.inputType() == inputSecret);

    FlGroup.current(null);
}
