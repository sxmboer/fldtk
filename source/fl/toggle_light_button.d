/*
 * Ported from FL/Fl_Toggle_Light_Button.H (FLTK 1.5.0).
 *
 * FLTK isn't a real class here: the header is a back-compatibility
 * `#define Fl_Toggle_Light_Button Fl_Light_Button`, i.e. a plain alias
 * for Fl_Light_Button (fl.light_button's LightButton is already a
 * toggle button -- see its constructor). A D `alias` is the direct
 * equivalent of a C preprocessor type alias, so that's what this is.
 */
module fl.toggle_light_button;

public import fl.light_button : ToggleLightButton = LightButton;

unittest
{
    import fl.group : FlGroup;
    import fl.button : toggleButton;

    FlGroup.current(null);

    auto b = new ToggleLightButton(0, 0, 10, 10, "x");
    assert(b.type() == toggleButton);

    FlGroup.current(null);
}
