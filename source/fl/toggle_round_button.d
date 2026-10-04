/*
 * Ported from FL/Fl_Toggle_Round_Button.H (FLTK 1.5.0,
 * ~/Repositories/fltk).
 *
 * FLTK isn't a real class here: the header is a back-compatibility
 * `#define Fl_Toggle_Round_Button Fl_Round_Button`, i.e. a plain alias
 * for Fl_Round_Button (fl.round_button's RoundButton is already a
 * toggle button by default -- it inherits that from fl.light_button's
 * constructor and never changes it). A D `alias` is the direct
 * equivalent of a C preprocessor type alias, so that's what this is.
 */
module fl.toggle_round_button;

public import fl.round_button : ToggleRoundButton = RoundButton;

unittest
{
    import fl.group : FlGroup;
    import fl.button : toggleButton;

    FlGroup.current(null);

    auto b = new ToggleRoundButton(0, 0, 10, 10, "x");
    assert(b.type() == toggleButton);

    FlGroup.current(null);
}
