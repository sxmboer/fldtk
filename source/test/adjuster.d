// D transliteration of FLTK's test/adjuster.cxx (~/Repositories/fltk).
// Part of the samples/ contract -- see samples/README.md.
// Check: ./samples/build.sh adjuster
import fl;

void adjcb(Widget o, Box b)
{
    auto a = cast(Adjuster) o;
    string newLabel = a.format();
    b.copyLabel(newLabel);
    b.redraw();
}

void main(string[] args)
{
    auto window = new DoubleWindow(320, 100);

    auto b1 = new Box(20, 30, 80, 25);
    b1.box(Boxtype.downBox);
    b1.color(white);
    auto a1 = new Adjuster(20 + 80, 30, 3 * 25, 25);
    a1.callback((w) { adjcb(w, b1); });
    adjcb(a1, b1);

    auto b2 = new Box(20 + 80 + 4 * 25, 30, 80, 25);
    b2.box(Boxtype.downBox);
    b2.color(white);
    auto a2 = new Adjuster(b2.x() + b2.w(), 10, 25, 3 * 25);
    a2.callback((w) { adjcb(w, b2); });
    adjcb(a2, b2);

    window.resizable(window);
    window.end();
    window.show(args);
    fl.run();
}
