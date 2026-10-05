// D transliteration of FLTK's test/symbols.cxx.
// Build: rdmd buildsamples.d test symbols
import fl;
import std.format : format;

int N = 0;
enum int W = 70;
enum int H = 70;
enum int ROWS = 6;
enum int COLS = 7;

DoubleWindow window;
ValueSlider orientation;
ValueSlider size;

// fldtk's Widget has no user_data() equivalent (delegates capture their own
// state instead -- see CONVENTIONS.md's callback-porting convention), but this
// sample needs to stash each box's symbol name for a later batch sweep over
// window.children(), not inside a callback closure. A plain AA keyed on the
// widget stands in for FLTK's Fl_Widget::user_data(name).
string[Widget] symbolNames;

void sliderCb(Widget)
{
    int val = cast(int) orientation.value();
    int sze = cast(int) size.value();
    for (int i = window.children(); i--;)
    { // all window children
        Widget wc = window.child(i);
        string l = symbolNames.get(wc, null);
        if (l.length && l[0] == '@')
        { // all children with '@'
            l = l[1 .. $];
            string buf;
            if (wc.box() == Boxtype.noBox)
            { // ascii legend?
                if (val && sze)
                    buf = format("@@%+d%d%s", sze, val, l);
                else if (val)
                    buf = format("@@%d%s", val, l);
                else if (sze)
                    buf = format("@@%+d%s", sze, l);
                else
                    buf = format("@@%s", l);
            }
            else
            { // box with symbol
                if (val && sze)
                    buf = format("@%+d%d%s", sze, val, l);
                else if (val)
                    buf = format("@%d%s", val, l);
                else if (sze)
                    buf = format("@%+d%s", sze, l);
                else
                    buf = format("@%s", l);
            }
            wc.copyLabel(buf);
        }
    }
    window.redraw();
}

void bt(string name)
{
    int x = N % COLS;
    int y = N / COLS;
    N++;
    x = x * W + 10;
    y = y * H + 10;
    string buf = format("@%s", name);
    auto a = new Box(x, y, W - 20, H - 20);
    a.box(Boxtype.noBox);
    a.copyLabel(buf);
    a.alignment(alignBottom);
    a.labelsize(11);
    symbolNames[a] = name;
    auto b = new Box(x, y, W - 20, H - 20);
    b.box(Boxtype.upBox);
    b.copyLabel(name);
    b.labelcolor(dark3);
    symbolNames[b] = name;
}

void main(string[] args)
{
    window = new DoubleWindow(COLS * W, ROWS * H + 60);
    bt("@->");
    bt("@>");
    bt("@>>");
    bt("@>|");
    bt("@>[]");
    bt("@|>");
    bt("@<-");
    bt("@<");
    bt("@<<");
    bt("@|<");
    bt("@[]<");
    bt("@<|");
    bt("@<->");
    bt("@-->");
    bt("@+");
    bt("@->|");
    bt("@||");
    bt("@arrow");
    bt("@returnarrow");
    bt("@square");
    bt("@circle");
    bt("@line");
    bt("@menu");
    bt("@UpArrow");
    bt("@DnArrow");
    bt("@search");
    bt("@FLTK");
    bt("@filenew");
    bt("@fileopen");
    bt("@filesave");
    bt("@filesaveas");
    bt("@fileprint");
    bt("@refresh");
    bt("@reload");
    bt("@undo");
    bt("@redo");
    bt("@import");
    bt("@export");

    orientation = new ValueSlider(cast(int)(window.w() * .05 + .5), window.h() - 40,
            cast(int)(window.w() * .42 + .5), 16, "Orientation");
    orientation.type(horizontalType);
    orientation.range(0.0, 9.0);
    orientation.value(0.0);
    orientation.step(1);
    orientation.callback((w) { sliderCb(w); });

    size = new ValueSlider(cast(int)(window.w() * .53 + .5), window.h() - 40,
            cast(int)(window.w() * .42 + .5), 16, "Size");
    size.type(horizontalType);
    size.range(-3.0, 9.0);
    size.value(0.0);
    size.step(1);
    size.callback((w) { sliderCb(w); });

    window.resizable(window);
    window.show(args);
    fl.run();
}
