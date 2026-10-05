// D transliteration of FLTK's examples/table-with-keynav.cxx.
// Build: rdmd buildsamples.d examples table_with_keynav
import fl;
import std.format : format;

// GLOBALS -- shared between MyTable's methods and main()/the row-select
// toggle button's callback, exactly as FLTK shares them via free
// global pointers.
ToggleButton gRowselect; // toggle to enable row selection
MyTable gTable; // table widget
Output gSum; // displays sum of user's selection

class MyTable : TableRow
{
protected:
    // Handle drawing all cells in table
    override void drawCell(TableContext context, int R = 0, int C = 0,
            int X = 0, int Y = 0, int W = 0, int H = 0)
    {
        final switch (context)
        {
        case contextColHeader:
        case contextRowHeader:
            fl_font(helveticaBold, 14);
            pushClip(X, Y, W, H);
            Color c = (context == contextColHeader) ? colHeaderColor() : rowHeaderColor();
            drawBoxAt(Boxtype.thinUpBox, X, Y, W, H, c);
            fl_color(black);
            // Draw text for headers
            fl_draw(format("%d", (context == contextColHeader) ? C : R),
                    X, Y, W, H, alignCenter);
            popClip();
            return;
        case contextCell:
            // Keyboard nav and mouse selection highlighting
            bool selected = gRowselect.value() ? (rowSelected(R) != 0) : (isSelected(R, C) != 0);
            drawBoxAt(Boxtype.thinUpBox, X, Y, W, H, selected ? yellow : white);
            // Draw text for the cell
            pushClip(X + 3, Y + 3, W - 6, H - 6);
            fl_font(helvetica, 14);
            fl_color(black);
            fl_draw(format("%d", R * C), X + 3, Y + 3, W - 6, H - 6, alignRight);
            popClip();
            return;
        case contextNone:
        case contextStartpage:
        case contextEndpage:
        case contextTable:
        case contextRcResize:
            return;
        }
    }

public:
    // CTOR
    this(int x, int y, int w, int h, string l = null)
    {
        super(x, y, w, h, l);
        // Row init
        rowHeader(true);
        rowHeaderWidth(70);
        rowResize(true);
        rows(11);
        rowHeightAll(20);
        // Col init
        colHeader(true);
        colHeaderHeight(20);
        colResize(true);
        cols(11);
        colWidthAll(70);
        end(); // Table derives from FlGroup, so end() it
    }

    // Update the displayed sum value
    int getSelectionSum()
    {
        int sum = -1;
        foreach (R; 0 .. rows())
        {
            foreach (C; 0 .. cols())
            {
                if (gRowselect.value() ? (rowSelected(R) != 0) : (isSelected(R, C) != 0))
                {
                    if (sum == -1)
                        sum = 0;
                    sum += R * C;
                }
            }
        }
        return sum;
    }

    // Update the "Selection sum:" display
    void updateSum()
    {
        string s;
        int sum = getSelectionSum();
        if (sum == -1)
        {
            s = "(nothing selected)";
            gSum.color(48);
        }
        else
        {
            s = format("%d", sum);
            gSum.color(white);
        }
        // Update only if different (lets one copy/paste from sum)
        if (s != gSum.value())
        {
            gSum.value(s);
            gSum.redraw();
        }
    }

    // Keyboard and mouse events
    override int handle(Event e)
    {
        int ret = super.handle(e);
        if (e == Event.keyDown && fl.eventKey() == escape)
            fl.hideAllWindows();
        switch (e)
        {
        case Event.push:
        case Event.release:
        case Event.keyUp:
        case Event.keyDown:
        case Event.drag:
            // ret = 1;  // *don't* indicate we 'handled' these, just update ('handling' prevents e.g. tab nav)
            updateSum();
            redraw();
            break;
        case Event.focus: // tells FLTK we're interested in keyboard events
        case Event.unfocus:
            ret = 1;
            break;
        default:
            break;
        }
        return ret;
    }
}

// User changed the 'row select' toggle button
void rowSelectCb(Widget w)
{
    w.window().redraw(); // redraw with changes applied
    gTable.updateSum();
}

void main()
{
    fl.option(fl.Option.arrowFocus, false); // disable arrow focus nav (we want arrows to control cells)
    auto win = new DoubleWindow(862, 312, "Table With Keynav");
    win.begin();
    // Create table
    gTable = new MyTable(10, 30, win.w() - 20, win.h() - 70, "Times Table");
    gTable.tooltip("Use mouse or Shift + Arrow Keys to make selections.\n"
            ~ "Sum of selected values is shown.");
    // Row select toggle button
    gRowselect = new ToggleButton(140, 10, 12, 12, "Row selection");
    gRowselect.alignment(alignLeft);
    gRowselect.value(false);
    gRowselect.selectionColor(yellow);
    gRowselect.callback((w) { rowSelectCb(w); });
    gRowselect.tooltip("Click to toggle row vs. row/col selection");
    // Selection sum display
    win.end();
    win.begin();
    gSum = new Output(140, gTable.y() + gTable.h() + 10, 160, 25, "Selection Sum:");
    gSum.value("(nothing selected)");
    gSum.color(48);
    gSum.tooltip("This field shows the sum of the selected cells in the table");
    win.end();
    win.resizable(gTable);
    win.show();
    fl.run();
}
