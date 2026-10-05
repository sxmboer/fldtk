// D transliteration of FLTK's test/resizebox.cxx.
// Build: rdmd buildsamples.d test resizebox
import fl;

bool big = false;
int w1() { return big ? 60 : 40; }
enum int B = 0;
int w3() { return 5 * w1() + 6 * B; }

DoubleWindow window;
Box box_;

void bCb(Widget, int w)
{
    if (window.w() != w3() || window.h() != w3())
    {
        message("Put window back to minimum size before changing");
        return;
    }
    window.initSizes();
    switch (w)
    {
    case 0:
        box_.hide();
        window.box(Boxtype.flatBox);
        window.resizable(null);
        return;
    case 8:
        box_.resize(w1() + B, w1(), 2 * w1(), B);
        break;
    case 2:
        box_.resize(w1() + B, w1() + B + 2 * w1(), 2 * w1(), B);
        break;
    case 4:
        box_.resize(w1() + B, w1(), B, 2 * w1());
        break;
    case 6:
        box_.resize(w1() + B + 2 * w1(), w1() + B, B, 2 * w1());
        break;
    default:
        break;
    }
    window.box(Boxtype.noBox);
    if (w == 6 || w == 4)
        box_.label("re\nsiz\nab\nle");
    else
        box_.label("resizable");
    box_.show();
    window.resizable(box_);
    window.redraw();
}

void main(string[] args)
{
    window = new DoubleWindow(w3(), w3());
    window.box(Boxtype.noBox);
    Box n;
    for (int x = 0; x < 4; x++)
        for (int y = 0; y < 4; y++)
        {
            if ((x == 1 || x == 2) && (y == 1 || y == 2))
                continue;
            n = new Box(Boxtype.engravedBox, x * (B + w1()) + B, y * (B + w1()) + B, w1(), w1(), null);
            n.color(cast(Color)(x + y + 8));
        }
    n = new Box(Boxtype.engravedBox, B, 4 * w1() + 5 * B, 4 * w1() + 3 * B, w1(), null);
    n.color(cast(Color) 12);
    n = new Box(Boxtype.engravedBox, 4 * w1() + 5 * B, B, w1(), 5 * w1() + 4 * B, null);
    n.color(cast(Color) 13);
    n = new Box(Boxtype.engravedBox, w1() + B + B, w1() + B + B, 2 * w1() + B, 2 * w1() + B, null);
    n.color(cast(Color) 8);

    Button b = new RadioButton(w1() + B + 50, w1() + B + 30, 20, 20, "@6>");
    b.callback((w) { bCb(w, 6); });
    (new RadioButton(w1() + B + 30, w1() + B + 10, 20, 20, "@8>")).callback((w) {
        bCb(w, 8);
    });
    (new RadioButton(w1() + B + 10, w1() + B + 30, 20, 20, "@4>")).callback((w) {
        bCb(w, 4);
    });
    (new RadioButton(w1() + B + 30, w1() + B + 50, 20, 20, "@2>")).callback((w) {
        bCb(w, 2);
    });
    (new RadioButton(w1() + B + 30, w1() + B + 30, 20, 20, "off")).callback((w) {
        bCb(w, 0);
    });

    box_ = new Box(Boxtype.flatBox, 0, 0, 0, 0, "resizable");
    box_.color(dark2);
    b.set();
    b.doCallback();
    window.end();

    window.sizeRange(w3(), w3());
    window.show(args);
    fl.run();
}
