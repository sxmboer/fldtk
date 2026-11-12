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
import fl;

immutable int[5] widths = [0, 1, 2, 4, 8];
enum cell = 60, gap = 30, left = 70, top = 40;

class Shapes : Widget
{
    this(int x, int y, int w, int h) { super(x, y, w, h); }

    override void draw()
    {
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
                lineStyle(row == 2 ? lineSolid | capRound : lineSolid, lw);
                final switch (row)
                {
                    case 0: fl_rect(cx, cy, cell, cell); break;
                    case 1: fl_arc(cx, cy, cell, cell, 0, 360); break;
                    case 2: fl_arc(cx, cy, cell, cell, 45, 315); break;
                    case 3: fl_pie(cx, cy, cell, cell, 45, 315); break;
                }
                lineStyle(lineSolid);
            }
        }
        fl_color(black);
        foreach (row, name; ["rect", "arc", "arc 3/4", "pie 3/4"])
            fl_draw(name, x() + 10, y() + top + cast(int) row * (cell + gap) + cell / 2);
    }
}

void main(string[] args)
{
    int w = left + 5 * (cell + gap), h = top + 4 * (cell + gap);
    auto win = new DoubleWindow(w, h, "fldtk arc line width");
    new Shapes(0, 0, w, h);
    win.end();
    win.resizable(win);
    win.show(args);
    run();
}
