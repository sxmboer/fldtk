/*
 * Ported from FL/Fl_Radio_Round_Button.H + src/Fl_Round_Button.cxx
 * (FLTK 1.5.0).
 *
 * Faithful, complete port. Trivial subclass: sets type() to
 * fl.button.radioButton on top of fl.round_button's round "light"
 * styling, so it participates in setonly()-based radio-group behavior.
 */
module fl.radio_round_button;

import fl.button : radioButton;
import fl.round_button : RoundButton;

class RadioRoundButton : RoundButton
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
    import fl.enumerations : Boxtype;

    FlGroup.current(null);

    auto b = new RadioRoundButton(0, 0, 10, 10, "x");
    assert(b.type() == radioButton);
    assert(b.downBox() == Boxtype.roundDownBox); // inherited from RoundButton

    FlGroup.current(null);
}
