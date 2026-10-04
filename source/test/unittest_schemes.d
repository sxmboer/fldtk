// D transliteration of FLTK's test/unittest_schemes.cxx
// (~/Repositories/fltk). Part of the samples/ contract -- see
// samples/README.md. One tab of the "unittests" bundle; see
// samples/test/unittests.d for the registry.
//
// Nods to Edmanuel Torres for the widget layout (STR#2672).
// Check: ./samples/build.sh unittests
module unittest_schemes;

import fl;
import unittests;

class UtSchemesTest : FlGroup
{
    private SchemeChoice schemeChoice_;

    private static void activateSubwin(Widget w, Window win)
    {
        LightButton b = cast(LightButton) w;
        bool active = b.value();
        if (active) b.label("active"); else b.label("inactive");
        // Documentation of deactivate() states: "Currently you cannot
        // deactivate Fl_Window widgets". However, it seems to work in
        // this case. AlbrechtS, FLTK 1.4, July 2022
        if (active) win.activate(); else win.deactivate();
    } // activateSubwin()

    static Widget create()
    {
        return new UtSchemesTest(UT_TESTAREA_X, UT_TESTAREA_Y, UT_TESTAREA_W, UT_TESTAREA_H);
    }

    this(int X, int Y, int W, int H)
    {
        super(X, Y, W, H);

        schemeChoice_ = new SchemeChoice(X + 125, Y, 140, 25, "fldtk Scheme");
        schemeChoice_.labelfont(helveticaBold);

        LightButton active = new LightButton(X + 300, Y, 100, 25, "active");
        active.value(true);
        active.selectionColor(red);
        active.alignment(alignCenter);
        Window subwin = new Window(X, Y + 30, W, H - 30);
        active.callback((w) { activateSubwin(w, subwin); });
        subwin.begin();
        {
            // Pasted from Edmanuel's gleam test app
            {
                Button o = new Button(10, 9, 90, 25, "button");
                o.box(Boxtype.upBox);
                o.color(cast(Color) 101);
                o.tooltip("selection_color() = default");
                o.labelfont(5);
            }
            {
                Button o = new Button(10, 36, 90, 25, "button");
                o.box(Boxtype.upBox);
                o.color(cast(Color) 179);
                o.selectionColor(o.color());
                o.tooltip("selection_color() = color()");
                o.labelfont(4);
                o.labelcolor(background2Color);
            }
            {
                Button o = new Button(10, 63, 90, 25, "button");
                o.box(Boxtype.upBox);
                o.color(cast(Color) 91);
                o.selectionColor(lighter(o.color()));
                o.tooltip("selection_color() = lighter(color())");
            }
            {
                Button o = new Button(10, 90, 90, 25, "button");
                o.box(Boxtype.upBox);
                o.color(inactiveColor);
                o.selectionColor(darker(o.color()));
                o.tooltip("selection_color() = darker(color())");
                o.labelcolor(background2Color);
            }
            {
                Tabs o = new Tabs(10, 120, 320, 215);
                o.color(dark1);
                o.selectionColor(dark1);
                {
                    FlGroup o2 = new FlGroup(14, 141, 310, 190, "tab1");
                    o2.color(dark1);
                    o2.selectionColor(cast(Color) 23);
                    o2.hide();
                    {
                        FlClock o3 = new FlClock(24, 166, 130, 130);
                        o3.box(Boxtype.thinUpBox);
                        o3.color(cast(Color) 12);
                        o3.selectionColor(background2Color);
                        o3.labelcolor(background2Color);
                        o3.tooltip("FlClock with thin up box");
                    }
                    {
                        new Progress(22, 306, 290, 20);
                    }
                    {
                        FlClock o3 = new FlClock(179, 166, 130, 130);
                        o3.box(Boxtype.thinDownBox);
                        o3.color(cast(Color) 26);
                        o3.tooltip("FlClock with thin down box");
                    }
                    o2.end();
                }
                {
                    FlGroup o2 = new FlGroup(15, 140, 310, 190, "tab2");
                    o2.color(dark1);
                    {
                        Slider o3 = new Slider(20, 161, 25, 155);
                        o3.box(Boxtype.downBox);
                        o3.tooltip("Slider with down box");
                    }
                    {
                        Scrollbar o3 = new Scrollbar(50, 161, 25, 155);
                        o3.value(0, 50, 1, 100);
                        o3.box(Boxtype.downBox);
                        o3.tooltip("Scrollbar with down box");
                    }
                    {
                        ValueSlider o3 = new ValueSlider(115, 161, 25, 155);
                        o3.box(Boxtype.downBox);
                    }
                    {
                        ValueOutput o3 = new ValueOutput(240, 265, 75, 25);
                        o3.box(Boxtype.downBox);
                        o3.tooltip("ValueOutput with down box");
                    }
                    {
                        Adjuster o3 = new Adjuster(185, 210, 100, 25);
                        o3.tooltip("Adjuster");
                    }
                    {
                        Counter o3 = new Counter(185, 180, 100, 25);
                        o3.box(Boxtype.downBox);
                        o3.tooltip("Counter with down box");
                    }
                    {
                        Roller o3 = new Roller(85, 161, 25, 155);
                        o3.box(Boxtype.upBox);
                        o3.tooltip("Roller with up box");
                    }
                    {
                        ValueInput o3 = new ValueInput(155, 265, 75, 25);
                        o3.box(Boxtype.downBox);
                        o3.tooltip("ValueInput with down box");
                    }
                    o2.end();
                }
                {
                    FlGroup o2 = new FlGroup(15, 140, 310, 190, "tab3");
                    o2.color(dark1);
                    o2.hide();
                    {
                        Input o3 = new Input(40, 230, 120, 25);
                        o3.box(Boxtype.downBox);
                        o3.tooltip("Input with down box");
                    }
                    {
                        Output o3 = new Output(40, 260, 120, 25);
                        o3.box(Boxtype.downBox);
                        o3.tooltip("Output with down box");
                    }
                    {
                        TextEditor o3 = new TextEditor(180, 160, 125, 55);
                        o3.box(Boxtype.downFrame);
                        o3.color(cast(Color) 80);
                        o3.tooltip("TextEditor with down frame");
                        o3.textsize(8);
                        o3.buffer(new TextBuffer());
                        o3.buffer().text("Text editor");
                    }
                    {
                        TextDisplay o3 = new TextDisplay(180, 230, 125, 55);
                        o3.box(Boxtype.downFrame);
                        o3.color(cast(Color) 12);
                        o3.tooltip("TextDisplay with down frame");
                        o3.textsize(8);
                        o3.buffer(new TextBuffer());
                        o3.buffer().text("Text display");
                    }
                    {
                        FileInput o3 = new FileInput(40, 290, 265, 30);
                        o3.box(Boxtype.downBox);
                        o3.tooltip("FileInput with down box");
                    }
                    o2.end();
                }
                {
                    FlGroup o2 = new FlGroup(15, 140, 310, 190, "tab4");
                    o2.color(dark1);
                    o2.hide();
                    {
                        RadioRoundButton o3 = new RadioRoundButton(40, 160, 120, 25, "Choice 1");
                        o3.tooltip("RadioRoundButton (default)");
                        // don't set selection color (use default selection color)
                        o3.value(true); // selected
                    }
                    {
                        RadioRoundButton o3 = new RadioRoundButton(40, 190, 120, 25, "Choice 2");
                        o3.tooltip("RadioRoundButton (red)");
                        o3.selectionColor(red);
                    }
                    {
                        RadioRoundButton o3 = new RadioRoundButton(40, 220, 120, 25, "Choice 3");
                        o3.tooltip("RadioRoundButton (green)");
                        o3.selectionColor(darker(green));
                    }
                    {
                        RadioRoundButton o3 = new RadioRoundButton(40, 250, 120, 25, "Choice 4");
                        o3.tooltip("RadioRoundButton (blue)");
                        o3.selectionColor(blue);
                    }
                    o2.end();
                }
                o.end();
            } // Tabs o
            {
                Box o = new Box(341, 10, 80, 50, "thin box\ndown1");
                o.box(Boxtype.thinDownBox);
                o.color(cast(Color) 20);
                o.labelsize(10);
            }
            {
                Box o = new Box(430, 10, 80, 50, "thin box\nup1");
                o.box(Boxtype.thinUpBox);
                o.color(fl.enumerations.selectionColor);
                o.labelcolor(cast(Color) 6);
                o.labelsize(10);
            }
            {
                Box o = new Box(341, 71, 80, 44, "thin box\ndown2");
                o.box(Boxtype.thinDownBox);
                o.color(cast(Color) 190);
                o.labelsize(10);
            }
            {
                Box o = new Box(430, 71, 80, 44, "thin box\nup2");
                o.box(Boxtype.thinUpBox);
                o.color(cast(Color) 96);
                o.labelcolor(background2Color);
                o.labelsize(10);
            }
            {
                Box o = new Box(341, 127, 80, 50, "box down3");
                o.box(Boxtype.downBox);
                o.color(cast(Color) 3);
                o.labelsize(10);
            }
            {
                Box o = new Box(430, 127, 80, 50, "box up3");
                o.box(Boxtype.upBox);
                o.color(cast(Color) 104);
                o.labelcolor(cast(Color) 3);
                o.labelsize(10);
            }
            {
                Box o = new Box(341, 189, 80, 50, "box down4");
                o.box(Boxtype.downBox);
                o.color(cast(Color) 42);
                o.labelcolor(darkRed);
                o.labelsize(10);
            }
            {
                Box o = new Box(430, 189, 80, 50, "box up4");
                o.box(Boxtype.upBox);
                o.color(cast(Color) 30);
                o.labelcolor(cast(Color) 26);
                o.labelsize(10);
            }
            {
                Box o = new Box(341, 251, 80, 82, "box down5");
                o.box(Boxtype.downBox);
                o.color(cast(Color) 19);
                o.labelcolor(cast(Color) 4);
                o.labelsize(10);
            }
            {
                Box o = new Box(430, 251, 80, 82, "box up5");
                o.box(Boxtype.upBox);
                o.color(foregroundColor);
                o.labelcolor(background2Color);
                o.labelsize(10);
            }
            {
                LightButton o = new LightButton(110, 10, 105, 25, "Light");
                o.box(Boxtype.downBox);
                o.color(background2Color);
                o.selectionColor(cast(Color) 30);
                o.selectionColor(red);
                o.tooltip("LightButton with down box");
            }
            {
                CheckButton o = new CheckButton(110, 37, 105, 25, "Check");
                o.box(Boxtype.downFrame);
                o.downBox(Boxtype.downBox);
                o.color(dark1);
                o.selectionColor(darker(green));
                o.tooltip("CheckButton with down frame");
            }
            {
                Input o = new Input(220, 10, 100, 25);
                o.box(Boxtype.downBox);
                o.color(cast(Color) 23);
                o.tooltip("Input with down box");
            }
            {
                Adjuster o = new Adjuster(110, 65, 80, 43);
                o.box(Boxtype.upBox);
                o.color(inactiveColor);
                o.selectionColor(background2Color);
                o.labelcolor(cast(Color) 55);
                o.tooltip("Adjuster with up box");
            }
            {
                TextEditor o = new TextEditor(220, 40, 100, 25);
                o.box(Boxtype.downFrame);
                o.color(cast(Color) 19);
                o.selectionColor(dark1);
                o.buffer(new TextBuffer());
                o.tooltip("TextEditor with down frame");
            }
            {
                TextEditor o = new TextEditor(220, 70, 100, 25);
                o.box(Boxtype.upFrame);
                o.color(cast(Color) 19);
                o.selectionColor(dark1);
                o.buffer(new TextBuffer());
                o.tooltip("TextEditor with up frame");
            }
        }
        subwin.end();
        subwin.resizable(subwin);
        subwin.show();
    }
}

static this()
{
    new UnitTest(UT_TEST_SCHEMES, "Schemes Test", () => UtSchemesTest.create());
}
