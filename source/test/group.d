// D transliteration of FLTK's test/group.cxx (~/Repositories/fltk).
// Part of the samples/ contract -- see samples/README.md.
// Check: ./samples/build.sh group
import fl;

// Globals for easier testing

enum int ww = 520; // window width
enum int wh = 200; // window height (w/o button and terminal)
enum int th = 200; // initial terminal (tty) height

DoubleWindow window;
Flex g1, g2;
Box b1, b2, b3, b4;
Terminal tty;

void debugGroup(FlGroup g)
{
    const nc = g.children;
    tty.printf("%s has %2d child%s\n", g.label(), nc, nc == 1 ? "" : "ren");
    for (int i = 0; i < g.children; i++)
    {
        Widget w = g.child(i);
        const lbl = w ? w.label() : "";
        // short info
        tty.printf("    Child[%2d] = %s\n", i, lbl);
    }
}

// This button callback exercises multiple Fl_Group operations in a circle.
// Note to devs: make sure that the last action restores the original layout.

void buttonCb(Widget w)
{
    static int move = 0;
    move++;
    tty.printf("\nMove %2d:\n", move);
    switch (move)
    {
    case 1:  g1.insert(b3, 0); break;
    case 2:  g1.insert(b3, 2); break;
    case 3:  g1.insert(b2, 1); break;
    case 4:  g1.insert(b1, 5); break;
    case 5:  g1.insert(b1, 1); break;
    case 6:  g1.insert(b4, 3); break;
    case 7:  g1.insert(b3, 2); break; // no-op (same position)
    case 8:  g2.add(b3); break;
    case 9:  g2.add(b3); break; // no-op (same position)
    case 10: g2.add(b4); break;
    case 11: g1.remove(b2); break;
    case 12: g1.add(b2); move = 0; break; // last move: reset counter
    default:                move = 0; break; // safety: reset counter
    }
    debugGroup(g1);
    debugGroup(g2);
    g1.layout();
    g2.layout();
    window.redraw();
}

void main()
{
    window = new DoubleWindow(ww, wh + th + 100, "FlGroup Test");

    g1 = new Flex(50, 20, ww - 80, wh / 2 - 20, "g1: ");
    g1.type(flexHorizontal);
    g1.box(Boxtype.flatBox);
    g1.color(white);
    g1.alignment(alignLeft);

    b1 = new Box(0, 0, 0, 0, "b1");
    b1.box(Boxtype.flatBox);
    b1.color(red);

    b2 = new Box(0, 0, 0, 0, "b2");
    b2.box(Boxtype.flatBox);
    b2.color(green);

    g1.end();

    g2 = new Flex(50, wh / 2 + 20, ww - 80, wh / 2 - 20, "g2: ");
    g2.type(flexHorizontal);
    g2.box(Boxtype.flatBox);
    g2.color(white);
    g2.alignment(alignLeft);

    b3 = new Box(0, 0, 0, 0, "b3");
    b3.box(Boxtype.flatBox);
    b3.color(blue);
    b3.labelcolor(white);

    b4 = new Box(0, 0, 0, 0, "b4");
    b4.box(Boxtype.flatBox);
    b4.color(yellow);

    g2.end();

    auto bt = new Button(10, wh + 20, ww - 20, 40, "Move children ...");
    bt.callback((w) { buttonCb(w); });

    tty = new Terminal(10, wh + 80, ww - 20, th);

    window.end();
    window.resizable(tty);
    window.sizeRange(window.w, window.h);
    window.show();

    tty.printf("sizeof(Widget)       = %3d\n", Widget.sizeof);
    tty.printf("sizeof(Box)          = %3d\n", Box.sizeof);
    tty.printf("sizeof(Button)       = %3d\n", Button.sizeof);
    tty.printf("sizeof(FlGroup)      = %3d\n", FlGroup.sizeof);
    tty.printf("sizeof(Window)       = %3d\n", Window.sizeof);

    int idx = g2.children + 3;
    tty.printf("child(n) out of range: g2->child(%d) = %x, children = %d\n",
        idx, cast(void*) g2.child(idx), g2.children);

    fl.run();

    // reset pointers to give memory checkers a chance to test for leaks
    g1 = g2 = null;
    tty = null;
    b1 = b2 = b3 = b4 = null;
}
