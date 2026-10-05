// D transliteration of FLTK's test/boxtype.cxx.
// Build: rdmd buildsamples.d test boxtype
import fl;
import std.format : format;

int N = 0;
enum W = 200;
enum H = 50;
enum ROWS = 14;

// Note: Run the program with command line '-s abc' to view boxtypes
// with scheme 'abc'.

// class BoxGroup - minimal class to enable visible box size debugging
//
// Set the following static variables to false (default) to disable
// or true to enable the given feature.
//
// If you enable the 'outline' variable, then a red frame should be drawn
// around each box, and it should ideally be fully visible.
//
// The white background is optional (otherwise you see the window background).
//
// Set BOTH variables = false to show the default image for the FLTK manual.

enum bool outline = false; // draw 1-px red frame around all boxes
enum bool boxBg = false;   // draw white background inside all boxes
enum bool inactive = false; // deactivate boxes and use green background

class BoxGroup : FlGroup
{
    this(int x, int y, int w, int h) { super(x, y, w, h); }

    override void draw()
    {
        drawBox();
        if (outline || boxBg)
        {
            foreach (o; array())
            {
                if (outline)
                {
                    fl_color(red);
                    fl_rect(o.x() - 1, o.y() - 1, o.w() + 2, o.h() + 2);
                }
                if (boxBg)
                {
                    fl_color(white);
                    fl_rectf(o.x(), o.y(), o.w(), o.h());
                }
                fl_color(black);
            }
        }
        drawChildren();
    }
}

DoubleWindow window;

void bt(string name, Boxtype type, bool square = false)
{
    int x = N % 4;
    int y = N / 4;
    N++;
    x = x * W + 10;
    y = y * H + 10;
    auto b = new Button(x, y, square ? H - 20 : W - 20, H - 20, name);
    b.box(type);
    b.labelsize(11);
    if (inactive)
    {
        b.color(green);
        b.deactivate();
    }
    if (square) b.alignment(alignRight);
}

void main(string[] args)
{
    window = new DoubleWindow(4 * W, ROWS * H);
    window.box(Boxtype.flatBox);

    fl.args(args);
    fl.getSystemColors();
    window.color(rgbColor(51, 173, 255)); // light blue (#33adff)

    // set window title to show active scheme
    scheme(scheme()); // init scheme
    string title = format("FLTK boxtypes: scheme = '%s'", scheme() ? scheme() : "none");
    window.label(title);

    // create special container group for box size debugging
    auto bg = new BoxGroup(0, 0, window.w(), window.h());
    bg.box(Boxtype.noBox);

    // create demo boxes -- labels use fldtk's own qualified D enum
    // spelling (matching each button's own `Boxtype` argument exactly),
    // not FLTK's C `FL_*` macro name. See CONVENTIONS.md's convention
    // on this standing rule for GUI text that names a constant.
    bt("Boxtype.noBox", Boxtype.noBox);
    bt("Boxtype.flatBox", Boxtype.flatBox);
    N += 2; // go to start of next row to line up boxes & frames
    bt("Boxtype.upBox", Boxtype.upBox);
    bt("Boxtype.downBox", Boxtype.downBox);
    bt("Boxtype.upFrame", Boxtype.upFrame);
    bt("Boxtype.downFrame", Boxtype.downFrame);
    bt("Boxtype.thinUpBox", Boxtype.thinUpBox);
    bt("Boxtype.thinDownBox", Boxtype.thinDownBox);
    bt("Boxtype.thinUpFrame", Boxtype.thinUpFrame);
    bt("Boxtype.thinDownFrame", Boxtype.thinDownFrame);
    bt("Boxtype.engravedBox", Boxtype.engravedBox);
    bt("Boxtype.embossedBox", Boxtype.embossedBox);
    bt("Boxtype.engravedFrame", Boxtype.engravedFrame);
    bt("Boxtype.embossedFrame", Boxtype.embossedFrame);
    bt("Boxtype.borderBox", Boxtype.borderBox);
    bt("Boxtype.shadowBox", Boxtype.shadowBox);
    bt("Boxtype.borderFrame", Boxtype.borderFrame);
    bt("Boxtype.shadowFrame", Boxtype.shadowFrame);
    bt("Boxtype.roundedBox", Boxtype.roundedBox);
    bt("Boxtype.rshadowBox", Boxtype.rshadowBox);
    bt("Boxtype.roundedFrame", Boxtype.roundedFrame);
    bt("Boxtype.rflatBox", Boxtype.rflatBox);
    bt("Boxtype.ovalBox", Boxtype.ovalBox);
    bt("Boxtype.oshadowBox", Boxtype.oshadowBox);
    bt("Boxtype.ovalFrame", Boxtype.ovalFrame);
    bt("Boxtype.oflatBox", Boxtype.oflatBox);
    bt("Boxtype.roundUpBox", Boxtype.roundUpBox);
    bt("Boxtype.roundDownBox", Boxtype.roundDownBox);
    bt("Boxtype.diamondUpBox", Boxtype.diamondUpBox);
    bt("Boxtype.diamondDownBox", Boxtype.diamondDownBox);

    bt("Boxtype.plasticUpBox", Boxtype.plasticUpBox);
    bt("Boxtype.plasticDownBox", Boxtype.plasticDownBox);
    bt("Boxtype.plasticUpFrame", Boxtype.plasticUpFrame);
    bt("Boxtype.plasticDownFrame", Boxtype.plasticDownFrame);
    bt("Boxtype.plasticThinUpBox", Boxtype.plasticThinUpBox);
    bt("Boxtype.plasticThinDownBox", Boxtype.plasticThinDownBox);
    N += 2;
    bt("Boxtype.plasticRoundUpBox", Boxtype.plasticRoundUpBox);
    bt("Boxtype.plasticRoundDownBox", Boxtype.plasticRoundDownBox);
    N += 2;

    bt("Boxtype.gtkUpBox", Boxtype.gtkUpBox);
    bt("Boxtype.gtkDownBox", Boxtype.gtkDownBox);
    bt("Boxtype.gtkUpFrame", Boxtype.gtkUpFrame);
    bt("Boxtype.gtkDownFrame", Boxtype.gtkDownFrame);
    bt("Boxtype.gtkThinUpBox", Boxtype.gtkThinUpBox);
    bt("Boxtype.gtkThinDownBox", Boxtype.gtkThinDownBox);
    bt("Boxtype.gtkThinUpFrame", Boxtype.gtkThinUpFrame);
    bt("Boxtype.gtkThinDownFrame", Boxtype.gtkThinDownFrame);
    bt("Boxtype.gtkRoundUpBox", Boxtype.gtkRoundUpBox);
    bt("Boxtype.gtkRoundDownBox", Boxtype.gtkRoundDownBox);
    bg.end();
    window.resizable(window);
    auto schemeChoice = new SchemeChoice(610, 10, 150, 30, "Scheme:");
    window.end();
    window.show();
    fl.run();
}
