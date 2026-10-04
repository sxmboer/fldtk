// D transliteration of FLTK's test/contrast.cxx (~/Repositories/fltk).
// Part of the samples/ contract -- see samples/README.md.
// Check: ./samples/build.sh contrast
import fl;
// fl.button's Button is the port of Fl_Button; this program's own local
// "class Button : public Fl_Button" collides with that name under the
// Fl_Foo -> Foo convention, so alias the real one to disambiguate (same
// situation as samples/test/coordinates.d's local Box).
import flbutton = fl.button;
import std.format : format;
import std.random : uniform;

// program version
enum string versionStr = "0.9.1";

// prototypes and forward declarations
void buttonCb(Widget w);
Color calcContrast(Color fg, Color bg, Fontsize fs);

// class Button
class Button : flbutton.Button
{
    private string lbuf; // private label buffer
    private Color ocol_; // "original" (label) color
    private int idx_;    // button index (0 - 255)

    this(int x, int y, int w, int h, int n)
    {
        super(x, y, w, h, "");
        idx_ = n;
        box(Boxtype.thinDownBox);
        callback((widget) { buttonCb(widget); });
        color(cast(Color) n);
        lbuf = format("%03d", n);
        label(lbuf);
        setLabelcolor(cast(Color) n);
        labelsize(15);
        labelfont(helvetica);
    }

    void setLabelcolor(Color col)
    {
        ocol_ = col;
        labelcolor(calcContrast(col, color(), labelsize()));
    }

    Color ocol() const { return ocol_; }
    int idx() const { return idx_; }

    override void draw()
    {
        drawBox();
        // draw small filled rectangle with "original" color
        fl_color(ocol_);
        fl_rectf(x() + 5, y() + 5, 10, h() - 10);
        // measure and draw label
        int lw = 0, lh = 0;
        fl_font(labelfont(), labelsize());
        fl_measure(lbuf, lw, lh);
        fl_color(labelcolor());
        fl_draw(lbuf, x() + 15 + (w() - lw - 15) / 2, y() + h() - (h() - lh) / 2 - lh / 4);
        fl_color(black);
    }
} // class Button

// global variables

Terminal term;

double gLfg;    // perceived lightness of foreground color
double gLbg;    // perceived lightness of background color
double gLcref;  // calculated contrast reference (CIELAB, L*a*b*)
int gSelected = -1; // selected button: -1 = none, 0 - 255 = valid button

Fontsize gFs = 15; // fontsize for button labels
int gLevel = 0;    // *init* fl_contrast_level (sensitivity)

ContrastMode gAlgo = ContrastMode.contrastCielab; // contrast algorithm: none, legacy (1.3.x), CIELAB, or custom
string alch = "";           // algorithm as char: "LEGACY", "CIELAB" , or "CUSTOM"

Color lcolor = black; // label color, set by slider callback
Button[256] buttons;  // array of color buttons
ValueSlider[6] sliders; // array of sliders (gray, red, green, blue, level, fontsize)
Output colorOut;      // color output (RRGGBB)

// Custom contrast algorithm: currently a dummy function (returns fg).
// This may be used to define a "better" contrast function in user code
Color customContrast(Color fg, Color bg, Fontsize fs, int)
{
    return fg;
}

/*
  Local function to calculate the contrast and store it in some
  global variables for display purposes and logging.

  This function is a wrapper around fl_contrast() in this demo program.
*/
Color calcContrast(Color fg, Color bg, Fontsize fs)
{
    // Compute and set global *perceived* lightness L* (Lstar) and contrast for display

    gLfg = lightness(fg);
    gLbg = lightness(bg);
    gLcref = gLfg - gLbg; // perceived contrast (light on dark = positive)

    switch (gAlgo)
    {
    case ContrastMode.contrastNone:   // none (return fg)
    case ContrastMode.contrastLegacy: // legacy (FLTK 1.3.x)
    case ContrastMode.contrastCielab: // CIELAB (L*a*b*)
    case ContrastMode.contrastCustom: // custom
        return fl.draw.contrast(fg, bg, fs);
    default:
        break;
    }
    return fg;
}

// set all button label colors and adjust fontsize (labelsize)
void updateLabels()
{
    for (int i = 0; i < 256; i++)
    {
        buttons[i].setLabelcolor(lcolor);
        buttons[i].labelsize(gFs);
    }
}

void buttonCb(Widget w)
{
    auto b = cast(Button) w;
    gSelected = b.idx();                     // selected button index
    Color ocol = fl.getColor(b.ocol());        // button's "original" label color (RGB0)
    Color fg = fl.getColor(b.labelcolor());    // button's label color (RGB0)
    Color bg = fl.getColor(b.color());         // button's background color (RGB0)
    calcContrast(ocol, bg, gFs);              // calculate values to be displayed
    string colorName = "";                    // calculated label color (text)
    if (fg == ocol) colorName = "fg";
    else if (fg == 0xffffff00) colorName = "WHITE";
    else if (fg == 0x0) colorName = "BLACK";
    term.printf("[%s] fg: %06x, bg: %06x, lfg: %6.2f, lbg: %6.2f, lc: %7.2f, %s => %-5s",
        b.label(), ocol >> 8, bg >> 8, gLfg, gLbg, gLcref, alch, colorName);
    if (gAlgo == ContrastMode.contrastLegacy || gAlgo == ContrastMode.contrastCielab)
        term.printf(" (level = %3d)\n", gLevel);
    else
        term.printf("\n");
}

void lfCb(Widget w)
{
    term.printf("\n");
}

// callback for color (gray and R, G, B) sliders
void colorSliderCb(Widget w, int n)
{
    uint r, g, b;
    if (n == 0) // gray slider
    {
        int val = cast(int) sliders[0].value();
        lcolor = rgbColor(cast(ubyte) val, cast(ubyte) val, cast(ubyte) val); // set gray value
        sliders[1].value(val);                // set r/g/b values as well
        sliders[2].value(val);
        sliders[3].value(val);
        r = g = b = val;
    }
    else // any color slider
    {
        r = cast(uint) sliders[1].value();
        g = cast(uint) sliders[2].value();
        b = cast(uint) sliders[3].value();
        lcolor = rgbColor(cast(ubyte) r, cast(ubyte) g, cast(ubyte) b); // set color value
    }
    // update button label colors
    updateLabels();
    // output label color
    colorOut.value(format("%02X %02X %02X", r, g, b));
    w.window().redraw();
}

// callback for "level" and "fontsize" sliders
void sliderCb(Widget w, int n)
{
    switch (n)
    {
    case 1: // fl_contrast_level()
        gLevel = cast(int) sliders[n + 3].value();
        contrastLevel(gLevel); // set/store current contrast level
        break;
    case 2: // 2nd slider: fontsize (labelsize)
        gFs = cast(int) sliders[n + 3].value();
        break;
    default:
        break;
    }
    // update button label colors
    updateLabels();
    w.window().redraw();
}

// callback for the "random color" button
void rcCb(Widget w)
{
    static bool first = true;
    uint r, g, b;

    if (first)
    {
        first = false;
        r = g = b = 0; // initialize with black
    }
    else
    {
        r = uniform(0, 256);
        g = uniform(0, 256);
        b = uniform(0, 256);
    }

    sliders[1].value(r);
    sliders[2].value(g);
    sliders[3].value(b);

    // update button label colors
    lcolor = rgbColor(cast(ubyte) r, cast(ubyte) g, cast(ubyte) b); // set color value
    updateLabels();
    // output label color
    colorOut.value(format("%02X %02X %02X", r, g, b));
    w.window().redraw();
}

// callback for contrast algorithm (radio buttons)
void algoCb(Widget w, ContrastMode val)
{
    gAlgo = val;
    switch (val)
    {
    case ContrastMode.contrastLegacy: alch = "LEGACY"; contrastMode(val); break; // legacy 1.3.x
    case ContrastMode.contrastCielab: alch = "CIELAB"; contrastMode(val); break; // CIELAB L*a*b*
    case ContrastMode.contrastCustom: alch = "CUSTOM"; contrastMode(val); break; // custom
    case ContrastMode.contrastNone:
    default:
        alch = "none  ";
        contrastMode(ContrastMode.contrastNone);
        break;
    }
    gLevel = contrastLevel(); // get current contrast level (per mode)
    sliders[4].value(gLevel);     // set level slider value
    updateLabels();                // update all button labels

    // print selected button's attributes
    if (gSelected >= 0)
        buttonCb(buttons[gSelected]);

    if (w !is null)
        w.window().redraw();
}

// color chooser callback
void colorCb(Widget w)
{
    auto cc = cast(ColorChooser) w;
    int r = cast(int)(cc.r() * 255);
    int g = cast(int)(cc.g() * 255);
    int b = cast(int)(cc.b() * 255);
    Color c = rgbColor(cast(ubyte) r, cast(ubyte) g, cast(ubyte) b);
    auto bt = buttons[255]; // last button
    bt.color(c);
    bt.setLabelcolor(lcolor);
    bt.redraw();
}

// ===============================================================
// ======================   main() program  ======================
// ===============================================================

void main(string[] args)
{
    enum bw = 58;
    enum bh = 30;
    int cw = 16 * bw + 10;
    int ch = 16 * bh + 10;
    int ww = cw + 10;
    int wh = 16 * bh + 135 + 10 + 170 /* terminal */ + 10;
    auto window = new DoubleWindow(ww, wh, "contrast test");

    int n = 0;
    for (int y = 0; y < 16; y++)
    {
        for (int x = 0; x < 16; x++)
        {
            buttons[n] = new Button(x * bw + 10, y * bh + 10, bw, bh, n);
            buttons[n].setLabelcolor(cast(Color) n);
            n++;
        }
    }

    // sliders for label color (gray, red, green, blue)

    enum sx = 10 + bw;
    enum sw = 5 * bw;
    enum sh = 25;
    int sy = ch + 10;

    auto gray = new HorValueSlider(sx, sy, sw, sh, "gray");
    gray.color(0xdddddd00);
    gray.textsize(13);
    gray.alignment(alignLeft);
    gray.value(0);
    gray.bounds(0, 255);
    gray.step(1);
    gray.callback((w) { colorSliderCb(w, 0); });
    sy += sh + 10;

    auto red = new HorValueSlider(sx, sy, sw, sh, "red");
    red.color(fl.enumerations.red);
    red.textcolor(white);
    red.textsize(13);
    red.alignment(alignLeft);
    red.value(0);
    red.bounds(0, 255);
    red.step(1);
    red.callback((w) { colorSliderCb(w, 1); });
    sy += sh + 5;

    auto green = new HorValueSlider(sx, sy, sw, sh, "green");
    green.color(fl.enumerations.green);
    green.textsize(13);
    green.alignment(alignLeft);
    green.value(0);
    green.bounds(0, 255);
    green.step(1);
    green.callback((w) { colorSliderCb(w, 1); });
    sy += sh + 5;

    auto blue = new HorValueSlider(sx, sy, sw, sh, "blue");
    blue.color(fl.enumerations.blue);
    blue.textcolor(white);
    blue.textsize(13);
    blue.alignment(alignLeft);
    blue.value(0);
    blue.bounds(0, 255);
    blue.step(1);
    blue.callback((w) { colorSliderCb(w, 1); });

    sliders[0] = gray;
    sliders[1] = red;
    sliders[2] = green;
    sliders[3] = blue;

    // contrast algorithm selection group

    int cgx = 10 + 6 * bw + 10;
    int cgy = ch + 30;
    int cgw = 90;
    int cgh = 100;
    int abh = 25;

    auto cg = new FlGroup(cgx, cgy, cgw, cgh, "contrast:");
    cg.alignment(alignTop);
    cg.box(Boxtype.borderFrame); // FL_FRAME is Boxtype.borderFrame FLTK

    auto anon = new RadioRoundButton(cgx, cgy, cgw, abh, "none");
    auto aleg = new RadioRoundButton(cgx, cgy + 25, cgw, abh, "LEGACY");
    auto acie = new RadioRoundButton(cgx, cgy + 50, cgw, abh, "CIELAB");
    auto aapc = new RadioRoundButton(cgx, cgy + 75, cgw, abh, "CUSTOM");
    acie.value(true);
    anon.callback((w) { algoCb(w, ContrastMode.contrastNone); });
    aleg.callback((w) { algoCb(w, ContrastMode.contrastLegacy); });
    acie.callback((w) { algoCb(w, ContrastMode.contrastCielab); });
    aapc.callback((w) { algoCb(w, ContrastMode.contrastCustom); });

    cg.end();

    colorOut = new Output(10 + 10 * bw, ch + 10, 100, 30, "label color:");
    colorOut.alignment(alignLeft);
    colorOut.textfont(courier);
    colorOut.textsize(16);
    colorOut.value("00 00 00");

    // light blue "level" slider

    auto sLevel = new HorValueSlider(10 + 9 * bw, red.y(), 3 * bw - 15, sh, "level");
    sLevel.color(231);
    sLevel.textcolor(224);
    sLevel.textsize(13);
    sLevel.alignment(alignLeft);
    sLevel.step(1);
    sLevel.bounds(0, 100);
    sLevel.value(gLevel);
    sLevel.callback((w) { sliderCb(w, 1); });
    sLevel.tooltip("set contrast sensitivity level (0-100), default: 50");

    // labelsize slider

    auto sFs = new HorValueSlider(10 + 9 * bw, green.y(), 3 * bw - 15, sh, "labelsize");
    sFs.color(231);
    sFs.textcolor(224);
    sFs.textsize(13);
    sFs.alignment(alignLeft);
    sFs.step(1);
    sFs.bounds(8, 24);
    sFs.value(15);
    sFs.callback((w) { sliderCb(w, 2); });
    sFs.tooltip("set label/text fontsize");

    sliders[4] = sLevel;
    sliders[5] = sFs;

    // line feed (LF) button

    auto lf = new flbutton.Button(10 + 8 * bw, blue.y(), bw, sh, "LF");
    lf.tooltip("Click to output a linefeed to the log.");
    lf.callback((w) { lfCb(w); });

    // random color (R) button

    auto rc = new flbutton.Button(10 + 8 * bw + lf.w() + 2, blue.y(), bw * 3 / 4, sh, "&RC");
    rc.tooltip("Click to select a random text color.");
    rc.callback((w) { rcCb(w); });

    // color chooser for field #255

    int ccx = 10 + 12 * bw;
    int ccy = ch + 10;
    int ccw = 4 * bw;
    int cch = 120;

    auto colorChooser = new ColorChooser(ccx, ccy, ccw, cch);
    colorChooser.callback((w) { colorCb(w); });
    colorChooser.label("bg color [255] @->");
    colorChooser.rgb(1, 1, 1);
    colorChooser.mode(1); // byte mode
    colorChooser.alignment(alignLeftBottom);

    // set contrast mode and level, update button label colors

    contrastMode(gAlgo);
    contrastFunction((fg, bg, context, size) => customContrast(fg, bg, context, size)); // dummy contrast function
    algoCb(acie, ContrastMode.contrastCielab);

    // Fl_Terminal for output

    int ttx = 10;
    int tty = colorChooser.y() + cch + 10;
    int ttw = window.w() - 20;
    int tth = window.h() - tty - 10;

    term = new Terminal(ttx, tty, ttw, tth);
    term.color(white);
    term.textfgcolor(black);
    term.textsize(13);

    term.printf("FLTK %d.%d.%d contrast() test program with different contrast algorithms, version %s\n",
        FL_MAJOR_VERSION, FL_MINOR_VERSION, FL_PATCH_VERSION, versionStr);
    term.printf(" - Select a foreground (text) color with the gray or red/green/blue sliders (displayed inside each field).\n");
    term.printf(" - Select an arbitrary background color for field #255 with the color chooser.\n");
    term.printf(" - Select a colored field (by clicking on it) to display its attributes.\n");
    term.printf(" - Select the contrast algorithm by clicking on the radio buttons.\n");
    term.printf(" - Tune the contrast algorithm with the light blue \"level\" slider (default: %d).\n", contrastLevel());
    term.printf(" - Select a random foreground (text) color by clicking the RC button\n");

    window.resizable(term);
    window.end();
    window.show(args);
    rcCb(rc); // update button labels - must be called after show()
    fl.run();
}
