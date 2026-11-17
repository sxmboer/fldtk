/*
 * Ported from FL/Fl_Int_Input.H (FLTK 1.5.0).
 * Trivial `type(inputInt)` subclass of fl.input's Input -- the
 * constructor body is ported from Fl_Int_Input::Fl_Int_Input()
 * (src/Fl_Input.cxx), not the (empty) header.
 */
module fl.int_input;

import fl.input : Input;
import fl.widget : Widget;
import fl.enumerations : inputInt;

/// A text field for a whole number: it takes only a sign at the start and
/// digits, typed or pasted, so `value().to!int` reads what it holds
/// (an empty field, or a lone sign, still needs a check).
class IntInput : Input
{
    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        type(inputInt);
        clearFlag(Widget.Flag.macUseAccentsMenu);
    }
}

unittest
{
    import fl.group : FlGroup;

    FlGroup.current(null);

    auto inp = new IntInput(0, 0, 100, 20);
    assert(inp.inputType() == inputInt);

    FlGroup.current(null);
}

unittest
{
    // Pasting replaces the text with a number of the field's kind, and
    // refuses anything else (the text stays as it was).
    import fl.group : FlGroup;
    import fl.enumerations : Event;
    static import fl.core;

    FlGroup.current(null);
    auto inp = new IntInput(0, 0, 100, 20);
    inp.value("keep");
    fl.core.eventText("42");
    inp.handle(Event.paste);
    assert(inp.value() == "42", inp.value());
    inp.value("keep");
    fl.core.eventText(" -7 ");
    inp.handle(Event.paste);
    assert(inp.value() == "-7", inp.value());
    inp.value("keep");
    fl.core.eventText("0x1F");
    inp.handle(Event.paste);
    assert(inp.value() == "keep", inp.value());
    inp.value("keep");
    fl.core.eventText("1.5");
    inp.handle(Event.paste);
    assert(inp.value() == "keep", inp.value());
    fl.core.eventText(null);
    FlGroup.current(null);
}
