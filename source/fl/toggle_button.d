/*
 * Ported from FL/Fl_Toggle_Button.H + the Fl_Toggle_Button constructor
 * in src/Fl_Button.cxx (FLTK 1.5.0).
 *
 * Faithful, complete port. Trivial subclass: sets type() to
 * fl.button.toggleButton, which makes fl.button.Button's value() flip
 * (rather than reset) on each click.
 */
module fl.toggle_button;

import fl.button : Button, toggleButton;

class ToggleButton : Button
{
    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        type(toggleButton);
    }
}

unittest
{
    import fl.group : FlGroup;

    FlGroup.current(null);

    auto b = new ToggleButton(0, 0, 10, 10, "x");
    assert(b.type() == toggleButton);

    FlGroup.current(null);
}
