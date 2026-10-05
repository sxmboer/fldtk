/*
 * Ported from FL/Fl_Radio_Button.H + the Fl_Radio_Button constructor in
 * src/Fl_Button.cxx (FLTK 1.5.0).
 *
 * Faithful, complete port. Trivial subclass: sets type() to
 * fl.button.radioButton, which makes fl.button.Button's setonly()
 * logic (in its FL_RELEASE/FL_KEYBOARD handling) turn off every other
 * radioButton-typed sibling when this one is selected.
 */
module fl.radio_button;

import fl.button : Button, radioButton;

class RadioButton : Button
{
    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        type(radioButton);
    }
}

unittest
{
    import fl.group : FlGroup;

    FlGroup.current(null);

    auto b = new RadioButton(0, 0, 10, 10, "x");
    assert(b.type() == radioButton);

    FlGroup.current(null);
}
