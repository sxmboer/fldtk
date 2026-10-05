// D transliteration of FLTK's test/line_style_docs.cxx.
// Build: rdmd buildsamples.d test line_style_docs
//
// Notes to devs (and users):
//
// 1. Run this program to create the screenshot for the fl_line_style() docs.
//    Save a screenshot of its original size to documentation/src/fl_line_style.png
// 2. For further tests it's possible to resize the window. Line sizes and widths
//    are adjusted (resized) as well, depending on the window size.
// 3. Some lines may draw outside their boxes in unusual window width/height ratios.
//    These effects are intentionally ignored.
//
// Deliberate deviation from a pure transliteration: StyleBox.draw()'s
// "corner" shape FLTK draws as two separate fl_line() segment calls
// (matching Fl_Graphics_Driver::line(x,y,x1,y1,x2,y2)'s base
// implementation -- two independent XDrawLine() calls, no Xlib/Linux
// driver override providing a real polyline). X11's join_style GC
// attribute has no effect between two independently-drawn segments, so
// FLTK's own version of this program -- and its own published
// documentation screenshot -- never actually exercises FL_JOIN_MITER/
// FL_JOIN_ROUND/FL_JOIN_BEVEL; every join box falls back to looking
// identical to FL_CAP_FLAT (not a fldtk-specific gap). The faithful
// two-fl_line()-call version is kept below, commented out, for
// reference; it's replaced with a real connected fl_begin_line()/
// fl_vertex()/fl_end_line() polyline (a single XDrawLines() call),
// which does let X11 apply join_style at the interior vertex -- so this
// version actually tests what the FLTK original cannot.
import fl;

// constants
enum int sep = 22; // separation between items
int[2] width = [1, 4]; // line widths (thin + thick/dyn.)

// This class draws a box with one line style inside an Fl_Grid widget.
// Row and column parameters are used to position the box inside the grid.
class StyleBox : Box
{
    int style; // line style

    this(int s, int row, int col) // style, row, column
    {
        super(0, 0, 0, 0);
        box(Boxtype.flatBox);
        color(white);
        style = s;
        auto grid = cast(Grid) parent();
        grid.widget(this, row, col, gridFill);
    }

    // Display names use fldtk's own bare D constant spelling (matching
    // each case label exactly -- what a D programmer actually types),
    // not FLTK's C `FL_*` macro name -- see CONVENTIONS.md's convention
    // on this standing rule for GUI text that names a constant.
    string styleStr(int style)
    {
        switch (style)
        {
        case lineSolid:
            return "lineSolid";
        case lineDash:
            return "lineDash";
        case lineDot:
            return "lineDot";
        case lineDashDot:
            return "lineDashDot";
        case lineDashDotDot:
            return "lineDashDotDot";
        case capFlat:
            return "capFlat";
        case capRound:
            return "capRound";
        case capSquare:
            return "capSquare";
        case joinMiter:
            return "joinMiter";
        case joinRound:
            return "joinRound";
        case joinBevel:
            return "joinBevel";
        default:
            return "(?)";
        }
    }

    override void draw()
    {
        drawBox();
        if (style < 0) // draw an empty box
            return;

        // set font and measure widest text
        fl_font(helvetica, 12);
        fl_color(black);
        static int textWidth = 0;
        if (!textWidth)
        {
            int h = 0; // dummy
            fl_measure("lineDashDotDot", textWidth, h);
        }

        // draw the text
        int xPos = x() + sep / 2;
        fl_draw(styleStr(style), xPos, y() + h() / 2 + height() / 2 - 2);

        // calculate dynamic line sizes and widths
        xPos += textWidth + sep / 2;
        int dx = (w() - textWidth - 5 * sep) / 4; // horizontal distance
        int dy = h() - sep;
        int yPos = y() + sep / 2;
        if (dx >= 80 || dy >= 80)
            width[1] = 9;
        else if (dx >= 60 || dy >= 60)
            width[1] = 8;
        else if (dx >= 40 || dy >= 40)
            width[1] = 7;
        else
            width[1] = 5;

        // draw the lines
        for (int i = 0; i < 2; i++, xPos += dx + sep)
        { // thin + thick lines
            lineStyle(style, width[i]);
            // ___
            //    |
            //    |
            // Faithful FLTK port (kept for reference, doesn't test joins --
            // see this file's own header comment for why):
            // fl_line(xPos, yPos, xPos + dx, yPos, xPos + dx, yPos + dy);
            beginLine();
            vertex(xPos, yPos);
            vertex(xPos + dx, yPos);
            vertex(xPos + dx, yPos + dy);
            endLine();

            xPos += dx + sep;
            // ___
            //   /
            //  /
            // fl_line(xPos, yPos, xPos + dx, yPos, xPos, yPos + dy);
            beginLine();
            vertex(xPos, yPos);
            vertex(xPos + dx, yPos);
            vertex(xPos, yPos + dy);
            endLine();
        }

        // restore line settings to default
        lineStyle(lineSolid, 0);
    }
}

void main(string[] args)
{
    auto win = new DoubleWindow(740, 400, "lineStyle()");
    win.color(white);

    // create grid with a nice white 4px border and a
    // light gray background (color) so margins and gaps show thru
    auto grid = new Grid(4, 4, win.w() - 8, win.h() - 8);
    grid.box(Boxtype.flatBox);
    grid.color(cast(Color) 0xd0d0d000);
    grid.layout(6, 2, 4, 4); // 6 rows, 2 columns, ...

    // first column
    auto sb00 = new StyleBox(lineSolid, 0, 0);
    auto sb01 = new StyleBox(lineDash, 1, 0);
    auto sb02 = new StyleBox(lineDot, 2, 0);
    auto sb03 = new StyleBox(lineDashDot, 3, 0);
    auto sb04 = new StyleBox(lineDashDotDot, 4, 0);
    auto sb05 = new StyleBox(-1, 5, 0); // empty box

    // second column
    auto sb10 = new StyleBox(capFlat, 0, 1);
    auto sb11 = new StyleBox(capRound, 1, 1);
    auto sb12 = new StyleBox(capSquare, 2, 1);
    auto sb13 = new StyleBox(joinMiter, 3, 1);
    auto sb14 = new StyleBox(joinRound, 4, 1);
    auto sb15 = new StyleBox(joinBevel, 5, 1);

    grid.end();
    win.end();
    win.resizable(win);
    win.sizeRange(660, 340); // don't allow to shrink too much
    win.show(args);
    fl.run();
}
