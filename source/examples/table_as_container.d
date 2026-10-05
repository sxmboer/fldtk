// D transliteration of FLTK's examples/table-as-container.cxx.
// Build: rdmd buildsamples.d examples table_as_container
import fl;
import std.format : format;
import std.stdio : stderr;

//
// Simple demonstration class deriving from Table
//
class WidgetTable : Table
{
protected:
    override void drawCell(TableContext context, int R = 0, int C = 0,
            int X = 0, int Y = 0, int W = 0, int H = 0)
    {
        final switch (context)
        {
        case contextStartpage:
            fl_font(helvetica, 12); // font used by all headers
            return;

        case contextRcResize:
            int index = 0;
            foreach (r; 0 .. rows())
            {
                foreach (c; 0 .. cols())
                {
                    if (index >= children())
                        break;
                    int cx, cy, cw, ch;
                    findCell(contextTable, r, c, cx, cy, cw, ch);
                    child(index++).resize(cx, cy, cw, ch);
                }
            }
            initSizes(); // tell group children resized
            return;

        case contextRowHeader:
            pushClip(X, Y, W, H);
            drawBoxAt(Boxtype.thinUpBox, X, Y, W, H, rowHeaderColor());
            fl_color(black);
            fl_draw(format("Row %d", R), X, Y, W, H, alignCenter);
            popClip();
            return;

        case contextColHeader:
            pushClip(X, Y, W, H);
            drawBoxAt(Boxtype.thinUpBox, X, Y, W, H, colHeaderColor());
            fl_color(black);
            fl_draw(format("Column %d", C), X, Y, W, H, alignCenter);
            popClip();
            return;

        case contextCell: // fltk handles drawing the widgets
            return;

        case contextNone:
        case contextEndpage:
        case contextTable:
            return;
        }
    }

public:
    this(int x, int y, int w, int h, string l = null)
    {
        super(x, y, w, h, l);
        colHeader(true);
        colResize(true);
        colHeaderHeight(25);
        rowHeader(true);
        rowResize(true);
        rowHeaderWidth(80);
        end();
    }

    void setSize(int newrows, int newcols)
    {
        clear(); // clear any previous widgets, if any
        rows(newrows);
        cols(newcols);

        begin(); // start adding widgets to group
        foreach (r; 0 .. newrows)
        {
            foreach (c; 0 .. newcols)
            {
                int X, Y, W, H;
                findCell(contextTable, r, c, X, Y, W, H);

                if (c & 1)
                {
                    // Create the input widgets
                    auto inp = new Input(X, Y, W, H);
                    inp.value(format("%d.%d", r, c));
                }
                else
                {
                    // Create the light buttons
                    auto butt = new LightButton(X, Y, W, H);
                    butt.copyLabel(format("%d/%d ", r, c));
                    butt.alignment(alignCenter | alignInside);
                    butt.callback((w) { stderr.writefln("BUTTON: %s", w.label()); });
                    butt.value(((r + c * 2) & 4) ? true : false);
                }
            }
        }
        end();
    }
}

void main()
{
    auto win = new DoubleWindow(940, 500, "Table As Container");
    auto table = new WidgetTable(20, 20, win.w() - 40, win.h() - 40, "FLTK widget table");
    table.setSize(50, 50);
    win.end();
    win.resizable(table);
    win.show();
    fl.run();
}
