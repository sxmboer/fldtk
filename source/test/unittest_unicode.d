// D transliteration of FLTK's test/unittest_unicode.cxx.
// One tab of the
// "unittests" bundle; see source/test/unittests.d for the registry.
// Build: rdmd buildsamples.d test unittest_unicode
//
// FLTK DEVS: utf-8 encoding must be enabled to edit this file.
module unittest_unicode;

import fl;
import unittests;

private immutable string utf8BoxTest =
      "╳╳ ██ ▏▏┏━━┓ ╔══╗ ╔═╦═╗ ██████\n"
    ~ "╳╳ ██ ▏▏┃  ┃ ║  ║ ╠═╬═╣ ██  ██\n"
    ~ "╳╳ ██ ▏▏┗━━┛ ╚══╝ ╚═╩═╝ ██████\n"
    ~ "\n"
    ~ "underbar: ______\n"
    ~ " overbar: ‾‾‾‾‾‾\n"
    ~ "\n"
    ~ "underbar/overbar alternate:\n"
    ~ "\n"
    ~ "___‾‾‾___‾‾‾___‾‾‾___‾‾‾___\n"
    ~ "‾‾‾___‾‾‾___‾‾‾___‾‾‾___‾‾‾\n";

private immutable string helptext =
    "In this test, ideally the box's lines should all be touching "
    ~ "without white space between. Underbar and overbars should both "
    ~ "be visible and not touching. All the above should be unaffected "
    ~ "by different font sizes and font settings.";

class UtUnicodeBoxTest : FlGroup
{
    private TextBuffer textbuffer;
    private TextDisplay textdisplay;
    private MultilineInput multilineinput;
    private Choice fontChoice;
    private HorValueSlider fontsizeSlider;

    // Font choice callback
    private void fontChoiceCb2()
    {
        switch (fontChoice.value())
        {
        case 0: textdisplay.textfont(courier); break;
        case 1: textdisplay.textfont(screen); break;
        default: break;
        }
        parent().redraw();
    }

    // Slider callback - apply new font size to widgets
    private void fontSizeSliderCb2()
    {
        // Get font size from slider value, apply to widgets
        int fontsize = cast(int) fontsizeSlider.value();
        textdisplay.textsize(fontsize);
        multilineinput.textsize(fontsize);
        multilineinput.insertPosition(0); // keep scrolled to top
        parent().redraw();
    }

    static Widget create()
    {
        return new UtUnicodeBoxTest(UT_TESTAREA_X, UT_TESTAREA_Y, UT_TESTAREA_W, UT_TESTAREA_H);
    }

    this(int x, int y, int w, int h)
    {
        super(x, y, w, h);
        // Fl_Text_Display
        textbuffer = new TextBuffer();
        textbuffer.text(utf8BoxTest);
        textdisplay = new TextDisplay(x + 5, y + 20, 250, 250, "TextDisplay");
        textdisplay.textfont(courier);
        textdisplay.buffer(textbuffer);
        textdisplay.tooltip(helptext);
        // Fl_Multiline_Input
        multilineinput = new MultilineInput(x + 250 + 15, y + 20, 250, 250, "MultilineInput");
        multilineinput.alignment(alignCenter | alignTop);
        multilineinput.textfont(courier);
        multilineinput.value(utf8BoxTest);
        multilineinput.tooltip(helptext);
        // Font choice
        //    Fonts must be fixed width to work correctly..
        fontChoice = new Choice(x + 150, y + h - 80, 200, 25, "Font face");
        fontChoice.add("courier", 0, null, 0);
        fontChoice.add("screen", 0, null, 0);
        fontChoice.value(0);
        fontChoice.callback((w) { fontChoiceCb2(); });
        // Font size slider
        fontsizeSlider = new HorValueSlider(x + 150, y + h - 50, 200, 25, "Font size");
        fontsizeSlider.alignment(alignLeft);
        fontsizeSlider.range(1.0, 50.0);
        fontsizeSlider.step(1.0);
        fontsizeSlider.value(14.0);
        fontsizeSlider.callback((w) { fontSizeSliderCb2(); });
        end();
    }
}

static this()
{
    new UnitTest(UT_TEST_UNICODE, "Unicode Boxes", () => UtUnicodeBoxTest.create());
}
