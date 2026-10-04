// D transliteration of FLTK's test/overlay.cxx (~/Repositories/fltk).
// Part of the samples/ contract -- see samples/README.md.
// Check: ./samples/build.sh overlay
import fl;
import std.conv : to;

int width = 10, height = 10;

// FLTK: class overlay : public Fl_Overlay_Window (which itself extends
// Fl_Double_Window). fldtk has no OverlayWindow yet -- the intended type
// once ported (a DoubleWindow subclass with a virtual drawOverlay() hook
// plus redrawOverlay()), not a hack bolted onto plain Window.
class Overlay : OverlayWindow
{
    this(int w, int h)
    {
        super(w, h);
    }

    override void drawOverlay()
    {
        fl_color(red);
        fl_rect((w() - width) / 2, (h() - height) / 2, width, height);
    }
}

Overlay ovl;

void bcb1(Widget w) { width += 20; ovl.redrawOverlay(); }
void bcb2(Widget w) { width -= 20; ovl.redrawOverlay(); }
void bcb3(Widget w) { height += 20; ovl.redrawOverlay(); }
void bcb4(Widget w) { height -= 20; ovl.redrawOverlay(); }

int arg(string[] argv, ref int i)
{
    Color n = to!Color(argv[i]);
    if (n <= 0) return 0;
    i++;
    ubyte r, g, b;
    fl.getColor(n, r, g, b);
    fl.setColor(red, r, g, b);
    return i;
}

void main(string[] args)
{
    int i = 0;
    fl.args(args, i, (a, ref j) => arg(a, j));
    ovl = new Overlay(400, 400);
    Button b;
    b = new Button(50, 50, 100, 100, "wider\n(a)");
    b.callback((w) { bcb1(w); }); b.shortcut('a');
    b = new Button(250, 50, 100, 100, "narrower\n(b)");
    b.callback((w) { bcb2(w); }); b.shortcut('b');
    b = new Button(50, 250, 100, 100, "taller\n(c)");
    b.callback((w) { bcb3(w); }); b.shortcut('c');
    b = new Button(250, 250, 100, 100, "shorter\n(d)");
    b.callback((w) { bcb4(w); }); b.shortcut('d');
    ovl.resizable(ovl);
    ovl.end();
    ovl.show(args);
    ovl.redrawOverlay();
    fl.run();
}
