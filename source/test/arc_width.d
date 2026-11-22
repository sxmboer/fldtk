// fldtk test program: line width with fl_arc(), fl_pie() and fl_rect().
// Build: rdmd buildsamples.d test arc_width
// Run:   build/arc_width                        (X11, Xlib drawing)
//        FLDTK_GRAPHICS=cairo build/arc_width   (X11, Cairo drawing)
//
// One column per line width (default, 1, 2, 4, 8). Every shape is drawn
// into a 60x60 box whose area is filled light grey, so you can see where
// a wide line lands: inside the box, centered on its edge, or spilling
// out. Row 1 is fl_rect() for comparison, row 2 a full fl_arc() circle,
// row 3 a 3/4 fl_arc() with round caps, row 4 a 3/4 fl_pie() drawn
// while the wide line style is still set (a pie is a fill, so its size
// should not change with the width). Try the window at 100% and 200%
// scaling (Ctrl+'+'/Ctrl+'-').
//
// Keys: A switches antialiasing off and on again (it changes only what
// draws antialiased, such as Windows' GDI+ drawing); P prints the shapes
// on one page.
import fl;

bool plain; // A: antialiasing off

immutable int[5] widths = [0, 1, 2, 4, 8];
enum cell = 60, gap = 30, left = 70, top = 40;

class Shapes : Widget
{
    this(int x, int y, int w, int h) { super(x, y, w, h); }

    override void draw()
    {
        int aa = antialias();
        if (plain) antialias(0);
        scope (exit) antialias(aa);
        fl_color(white);
        fl_rectf(x(), y(), w(), h());
        fl_font(helvetica, 12);
        foreach (col, lw; widths)
        {
            int cx = x() + left + cast(int) col * (cell + gap);
            fl_color(black);
            fl_draw(lw == 0 ? "default" : "width " ~ cast(char)('0' + lw),
                cx, y() + 20);
            foreach (row; 0 .. 4)
            {
                int cy = y() + top + row * (cell + gap);
                fl_color(rgbColor(220, 220, 220));
                fl_rectf(cx, cy, cell, cell);
                fl_color(blue);
                auto line = useLineStyle(row == 2 ? lineSolid | capRound : lineSolid, lw);
                final switch (row)
                {
                    case 0: fl_rect(cx, cy, cell, cell); break;
                    case 1: fl_arc(cx, cy, cell, cell, 0, 360); break;
                    case 2: fl_arc(cx, cy, cell, cell, 45, 315); break;
                    case 3: fl_pie(cx, cy, cell, cell, 45, 315); break;
                }
            }
        }
        fl_color(black);
        foreach (row, name; ["rect", "arc", "arc 3/4", "pie 3/4"])
            fl_draw(name, x() + 10, y() + top + cast(int) row * (cell + gap) + cell / 2);
    }
}

// Prints `shapes` on one page, centred, made smaller when it doesn't fit.
void print(Widget shapes)
{
    auto printer = new Printer();
    scope (exit) destroy(printer);
    string message;
    int err = printer.beginJob(1, message);
    if (err)
    {
        if (err > 1 && message.length) alert(message);
        return;
    }
    printer.beginPage();
    int pw, ph;
    printer.printableRect(pw, ph);
    float s = 1;
    if (shapes.w() > pw) s = cast(float) pw / shapes.w();
    if (shapes.h() > ph && cast(float) ph / shapes.h() < s) s = cast(float) ph / shapes.h();
    printer.scale(s);
    printer.printableRect(pw, ph);
    printer.origin(pw / 2, ph / 2);
    printer.draw(shapes, -shapes.w() / 2, -shapes.h() / 2);
    printer.endPage();
    printer.endJob();
}

class ShapesWindow : DoubleWindow
{
    Shapes shapes;

    this(int w, int h, string label) { super(w, h, label); }

    override int handle(Event e)
    {
        if (e == Event.shortcut && eventText() == "a")
        {
            plain = !plain;
            label(plain ? "fldtk arc line width (antialiasing off)" : "fldtk arc line width");
            redraw();
            return 1;
        }
        if (e == Event.shortcut && eventText() == "p")
        {
            print(shapes);
            return 1;
        }
        return super.handle(e);
    }
}

void main(string[] args)
{
    int w = left + 5 * (cell + gap), h = top + 4 * (cell + gap);
    auto win = new ShapesWindow(w, h, "fldtk arc line width");
    win.shapes = new Shapes(0, 0, w, h);
    win.end();
    win.resizable(win);
    win.show(args);
    run();
}
