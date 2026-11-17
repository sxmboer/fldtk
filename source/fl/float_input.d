/*
 * Ported from FL/Fl_Float_Input.H (FLTK 1.5.0).
 * Trivial `type(inputFloat)` subclass of fl.input's Input -- the
 * constructor body is ported from Fl_Float_Input::Fl_Float_Input()
 * (src/Fl_Input.cxx), not the (empty) header.
 */
module fl.float_input;

import fl.input : Input;
import fl.widget : Widget;
import fl.enumerations : inputFloat;

/// A text field for a decimal number: it takes only a sign, digits, a
/// point and an exponent (`12`, `-3.5`, `1e5`, `2.5E-3`), typed or
/// pasted, so `value().to!double` reads a complete number it holds.
class FloatInput : Input
{
    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        type(inputFloat);
        clearFlag(Widget.Flag.macUseAccentsMenu);
    }
}

unittest
{
    import fl.group : FlGroup;
    import fl.enumerations : inputFloat;

    FlGroup.current(null);

    auto inp = new FloatInput(0, 0, 100, 20);
    assert(inp.inputType() == inputFloat);

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
    auto inp = new FloatInput(0, 0, 100, 20);
    inp.value("keep");
    fl.core.eventText("1e5");
    inp.handle(Event.paste);
    assert(inp.value() == "1e5", inp.value());
    inp.value("keep");
    fl.core.eventText("-3.5");
    inp.handle(Event.paste);
    assert(inp.value() == "-3.5", inp.value());
    inp.value("keep");
    fl.core.eventText("2.5E-3");
    inp.handle(Event.paste);
    assert(inp.value() == "2.5E-3", inp.value());
    inp.value("keep");
    fl.core.eventText("0x1F");
    inp.handle(Event.paste);
    assert(inp.value() == "keep", inp.value());
    inp.value("keep");
    fl.core.eventText("1,5");
    inp.handle(Event.paste);
    assert(inp.value() == "keep", inp.value());
    fl.core.eventText(null);
    FlGroup.current(null);
}
