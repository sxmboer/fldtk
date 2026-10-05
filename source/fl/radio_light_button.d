/*
 * Ported from FL/Fl_Radio_Light_Button.H + the Fl_Radio_Light_Button
 * constructor at the bottom of src/Fl_Light_Button.cxx (FLTK 1.5.0).
 *
 * Faithful, complete port. Trivial subclass: sets type() to
 * fl.button.radioButton, which makes fl.button.Button's setonly()
 * logic turn off every other radioButton-typed sibling when this one
 * is selected -- same relationship as fl.radio_button is to fl.button,
 * but for fl.light_button.
 */
module fl.radio_light_button;

import fl.button : radioButton;
import fl.light_button : LightButton;

class RadioLightButton : LightButton
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

    auto b = new RadioLightButton(0, 0, 10, 10, "x");
    assert(b.type() == radioButton);

    FlGroup.current(null);
}
