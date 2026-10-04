/*
 * Ported from FL/Fl_Secret_Input.H (FLTK 1.5.0, ~/Repositories/fltk).
 * Trivial `type(inputSecret)` subclass of fl.input's Input -- masks
 * every character with a bullet glyph on display (fl.input_'s expand(),
 * see its module comment for `secretInputCharacter`). The constructor
 * body is ported from Fl_Secret_Input::Fl_Secret_Input()
 * (src/Fl_Input.cxx), not the (empty) header.
 *
 * Fl_Secret_Input::handle(int) is NOT ported: its only job FLTK is
 * `if (event == FL_KEYBOARD && has_marked_text() && compose_state)
 * mark(insert_position());` -- suppressing the marked-text underline
 * IME draws under provisionally-composed characters, so a secret field
 * doesn't visually leak how many characters are being composed. No IME
 * support exists anywhere in this port (see fl.input_'s module
 * comment), so that condition is always false and the override would
 * be a pure pass-through to Fl_Input::handle() -- identical to not
 * overriding handle() at all.
 */
module fl.secret_input;

import fl.input : Input;
import fl.widget : Widget;
import fl.enumerations : inputSecret;

class SecretInput : Input
{
    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        type(inputSecret);
        clearFlag(Widget.Flag.macUseAccentsMenu);
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
