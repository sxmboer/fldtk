// D transliteration of FLTK's test/input.cxx (~/Repositories/fltk).
// Part of the samples/ contract -- see samples/README.md.
// Check: ./samples/build.sh input
import fl;

enum int terminalHeight = 120;

// Globals
Terminal gTty;

int when = 0;
Input[5] input;

void test(Input i)
{
    if (i.changed())
    {
        i.clearChanged();
        gTty.printf("%s '%s'\n", i.label(), i.value());
        char[10] utf8buf;
        int last = utf8Encode(i.index(i.insertPosition()), utf8buf[]);
        utf8buf[last] = 0;
        gTty.printf("Symbol at cursor position: %s\n", utf8buf.ptr);
    }
}

void main(string[] args)
{
    // the following two lines set the correct color scheme, so that
    // calling fl_contrast below will return good results
    fl.args(args);
    fl.getSystemColors();
    auto window = new Window(400, 420 + terminalHeight);
    gTty = new Terminal(0, 420, window.w(), terminalHeight);

    int y = 10;
    input[0] = new Input(70, y, 300, 30, "Normal:");
    y += 35;
    input[0].tooltip("Normal input field");
    // input[0].cursorColor(selectionColor);
    // input[0].maximumSize(20);
    // input[0].staticValue("this is a testgarbage");
    input[1] = new FloatInput(70, y, 300, 30, "Float:");
    y += 35;
    input[1].tooltip("Input field for floating-point number (F1)");
    input[1].shortcut(f + 1);
    input[2] = new IntInput(70, y, 300, 30, "Int:");
    y += 35;
    input[2].tooltip("Input field for integer number (F2)");
    input[2].shortcut(f + 2);
    input[3] = new SecretInput(70, y, 300, 30, "&Secret:");
    y += 35;
    input[3].tooltip("Input field for password (Alt-S)");
    input[4] = new MultilineInput(70, y, 300, 100, "&Multiline:");
    y += 105;
    input[4].tooltip("Input field for short text with newlines (Alt-M)");
    input[4].wrap(1);

    for (int i = 0; i < 4; i++)
    {
        input[i].when(whenNever);
        input[i].callback((w) {
            auto ob = cast(Input) w;
            gTty.printf("Callback for %s '%s'\n", ob.label(), ob.value());
        });
    }
    int y1 = y;

    Button b;
    b = new ToggleButton(10, y, 200, 25, "whenChanged");
    b.callback((w) {
        auto tb = cast(ToggleButton) w;
        if (tb.value())
            when |= whenChanged;
        else
            when &= ~whenChanged;
        for (int i = 0; i < 5; i++)
            input[i].when(when);
    });
    y += 25;
    b.tooltip("Do callback each time the text changes");
    b = new ToggleButton(10, y, 200, 25, "whenRelease");
    b.callback((w) {
        auto tb = cast(ToggleButton) w;
        if (tb.value())
            when |= whenRelease;
        else
            when &= ~whenRelease;
        for (int i = 0; i < 5; i++)
            input[i].when(when);
    });
    y += 25;
    b.tooltip("Do callback when widget loses focus");
    b = new ToggleButton(10, y, 200, 25, "whenEnterKey");
    b.callback((w) {
        auto tb = cast(ToggleButton) w;
        if (tb.value())
            when |= whenEnterKey;
        else
            when &= ~whenEnterKey;
        for (int i = 0; i < 5; i++)
            input[i].when(when);
    });
    y += 25;
    b.tooltip("Do callback when user hits Enter key");
    b = new ToggleButton(10, y, 200, 25, "whenNotChanged");
    b.callback((w) {
        auto tb = cast(ToggleButton) w;
        if (tb.value())
            when |= whenNotChanged;
        else
            when &= ~whenNotChanged;
        for (int i = 0; i < 5; i++)
            input[i].when(when);
    });
    y += 25;
    b.tooltip("Do callback even if the text is not changed");
    y += 5;
    b = new Button(10, y, 200, 25, "&print changed()");
    y += 25;
    b.callback((w) {
        for (int i = 0; i < 5; i++)
            test(input[i]);
    });
    b.tooltip("Print widgets that have changed() flag set");

    b = new LightButton(10, y, 100, 25, " Tab Nav");
    b.tooltip("Control tab navigation for the multiline input field");
    b.callback((w) {
        auto lb = cast(LightButton) w;
        input[4].tabNav(lb.value());
    });
    b.value(input[4].tabNav());
    b = new LightButton(110, y, 100, 25, " Arrow Nav");
    y += 25;
    b.tooltip("Control horizontal arrow key focus navigation behavior.\n"
            ~ "e.g. Fl::OPTION_ARROW_FOCUS");
    b.callback((w) {
        auto lb = cast(LightButton) w;
        fl.option(Option.arrowFocus, lb.value());
    });
    b.value(input[4].tabNav());
    b.value(fl.option(Option.arrowFocus));

    b = new Button(220, y1, 120, 25, "color");
    y1 += 25;
    b.color(input[0].color());
    b.callback((w) {
        uint c;
        ubyte r, g, bl;
        fl.getColor(background2Color, r, g, bl);
        if (colorChooser("color", r, g, bl))
        {
            fl.setColor(background2Color, r, g, bl);
            fl.redraw();
            w.labelcolor(contrast(black, background2Color));
            w.redraw();
        }
    });
    b.tooltip("Color behind the text");
    b = new Button(220, y1, 120, 25, "selection_color");
    y1 += 25;
    b.color(input[0].selectionColor());
    b.callback((w) {
        ubyte r, g, bl;
        fl.getColor(selectionColor, r, g, bl);
        if (colorChooser("selection_color", r, g, bl))
        {
            fl.setColor(selectionColor, r, g, bl);
            fl.redraw();
            w.labelcolor(contrast(black, selectionColor));
            w.redraw();
        }
    });
    b.labelcolor(contrast(black, b.color()));
    b.tooltip("Color behind selected text");
    b = new Button(220, y1, 120, 25, "textcolor");
    y1 += 25;
    b.color(input[0].textcolor());
    b.callback((w) {
        ubyte r, g, bl;
        fl.getColor(foregroundColor, r, g, bl);
        if (colorChooser("textcolor", r, g, bl))
        {
            fl.setColor(foregroundColor, r, g, bl);
            fl.redraw();
            w.labelcolor(contrast(black, foregroundColor));
            w.redraw();
        }
    });
    b.labelcolor(contrast(black, b.color()));
    b.tooltip("Color of the text");

    window.end();
    window.resizable(gTty);
    window.show(args);
    fl.run();
}
