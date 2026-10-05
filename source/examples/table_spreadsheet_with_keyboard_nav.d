// D transliteration of FLTK's examples/table-spreadsheet-with-keyboard-nav.cxx.
// Build: rdmd buildsamples.d examples table_spreadsheet_with_keyboard_nav
import fl;
import std.format : format;
import std.conv : to, ConvException;

enum maxCols = 26;
enum maxRows = 500;

class Spreadsheet : Table
{
    IntInput input; // single instance of IntInput widget
    int[maxCols][maxRows] values; // array of data for cells
    int rowEdit, colEdit; // row/col being modified
    int sLeft, sTop, sRight, sBottom; // kb nav + mouse selection

protected:
    override void drawCell(TableContext context, int R = 0, int C = 0,
            int X = 0, int Y = 0, int W = 0, int H = 0)
    {
        final switch (context)
        {
        case contextStartpage: // table about to redraw
            // Get kb nav + mouse 'selection region' for use below
            getSelection(sTop, sLeft, sBottom, sRight);
            break;

        case contextColHeader: // draw a column heading (C is column)
            fl_font(helveticaBold, 14);
            pushClip(X, Y, W, H);
            drawBoxAt(Boxtype.thinUpBox, X, Y, W, H, colHeaderColor());
            fl_color(black);
            if (C == cols() - 1) // Last column? show 'TOTAL'
                fl_draw("TOTAL", X, Y, W, H, alignCenter);
            else // Not last column? show column letter
                fl_draw(format("%c", cast(char)('A' + C)), X, Y, W, H, alignCenter);
            popClip();
            return;

        case contextRowHeader: // draw a row heading (R is row)
            fl_font(helveticaBold, 14);
            pushClip(X, Y, W, H);
            drawBoxAt(Boxtype.thinUpBox, X, Y, W, H, rowHeaderColor());
            fl_color(black);
            if (R == rows() - 1) // Last row? Show 'Total'
                fl_draw("TOTAL", X, Y, W, H, alignCenter);
            else // Not last row? show row#
                fl_draw(format("%d", R + 1), X, Y, W, H, alignCenter);
            popClip();
            return;

        case contextCell:
            if (R == rowEdit && C == colEdit && input.visible())
                return; // dont draw for cell with input widget over it
            // Keyboard nav and mouse selection highlighting
            if (R >= sTop && R <= sBottom && C >= sLeft && C <= sRight)
                drawBoxAt(Boxtype.thinUpBox, X, Y, W, H, yellow);
            else if (C < cols() - 1 && R < rows() - 1)
                drawBoxAt(Boxtype.thinUpBox, X, Y, W, H, white);
            else
                drawBoxAt(Boxtype.thinUpBox, X, Y, W, H, 0xbbddbb00); // money green
            // Text
            pushClip(X + 3, Y + 3, W - 6, H - 6);
            fl_color(black);
            if (C == cols() - 1 || R == rows() - 1) // Last row or col? Show total
            {
                fl_font(helveticaBold, 14); // ..in bold font
                string s;
                if (C == cols() - 1 && R == rows() - 1) // Last row+col? Total all cells
                    s = format("%d", sumAll());
                else if (C == cols() - 1) // Row subtotal
                    s = format("%d", sumCols(R));
                else if (R == rows() - 1) // Col subtotal
                    s = format("%d", sumRows(C));
                fl_draw(s, X + 3, Y + 3, W - 6, H - 6, alignRight);
            }
            else // Not last row or col? Show cell contents
            {
                fl_font(helvetica, 14); // ..in regular font
                fl_draw(format("%d", values[R][C]), X + 3, Y + 3, W - 6, H - 6, alignRight);
            }
            popClip();
            return;

        case contextRcResize: // table resizing rows or columns
            if (!input.visible())
                return;
            int ix, iy, iw, ih;
            findCell(contextTable, rowEdit, colEdit, ix, iy, iw, ih);
            if (ix == input.x() && iy == input.y() && iw == input.w() && ih == input.h())
                return; // no change? ignore
            input.resize(ix, iy, iw, ih);
            return;

        case contextNone:
        case contextEndpage:
        case contextTable:
            return;
        }
    }

    // table's event callback (instance)
    void eventCallback2()
    {
        int R = callbackRow();
        int C = callbackCol();
        TableContext context = callbackContext();

        final switch (context)
        {
        case contextCell: // A table event occurred on a cell
            if (fl.event() == Event.push) // mouse click?
            {
                doneEditing(); // finish editing previous
                if (R != rows() - 1 && C != cols() - 1) // only edit cells not in total's columns
                    startEditing(R, C); // start new edit
            }
            else if (fl.event() == Event.keyDown) // key press in table?
            {
                if (fl.eventKey() == escape)
                    fl.hideAllWindows(); // ESC closes app
                if (C == cols() - 1 || R == rows() - 1)
                    return; // no editing of totals column
                doneEditing(); // finish any previous editing
                setSelection(R, C, R, C); // select the current cell
                startEditing(R, C); // start new edit
                if (fl.event() == Event.keyDown
                        && (fl.eventText().length == 0 || fl.eventText()[0] != '\r'))
                    input.handle(fl.event()); // pass keypress to input widget
            }
            return;

        case contextTable: // A table event occurred on dead zone in table
        case contextRowHeader: // A table event occurred on row/column header
        case contextColHeader:
            doneEditing(); // done editing, hide
            return;

        case contextNone:
        case contextStartpage:
        case contextEndpage:
        case contextRcResize:
            return;
        }
    }

public:
    this(int X, int Y, int W, int H, string L = null)
    {
        super(X, Y, W, H, L);
        callback((w) { eventCallback2(); });
        when(whenNotChanged | when());
        // Create input widget that we'll use whenever user clicks on a cell
        input = new IntInput(W / 2, H / 2, 0, 0);
        input.hide();
        input.callback((w) { setValueHide(); });
        input.when(whenEnterKeyAlways); // callback triggered when user hits Enter
        input.maximumSize(5);
        rowEdit = colEdit = 0;
        sLeft = sTop = sRight = sBottom = 0;
        foreach (c; 0 .. maxCols)
            foreach (r; 0 .. maxRows)
                values[r][c] = (r + 2) * (c + 3); // initialize cells
        end();
    }

    // Apply value from input widget to values[row][col] array and hide (done editing)
    void setValueHide()
    {
        // FLTK uses atoi(), which returns 0 for unparseable input
        // (e.g. an empty string) instead of throwing -- to!int() has no
        // such fallback, so match atoi()'s behavior explicitly here.
        int val;
        try
            val = to!int(input.value());
        catch (ConvException)
            val = 0;
        values[rowEdit][colEdit] = val;
        input.hide();
        window().cursor(Cursor.default_); // XXX: if we don't do this, cursor can disappear!
    }

    // Start editing a new cell: move the IntInput widget to specified row/column
    void startEditing(int R, int C)
    {
        rowEdit = R; // Now editing this row/col
        colEdit = C;
        int X, Y, W, H;
        findCell(contextCell, R, C, X, Y, W, H); // Find X/Y/W/H of cell
        input.resize(X, Y, W, H); // Move Input widget there
        string s = format("%d", values[R][C]); // Load input widget with cell's current value
        input.value(s);
        input.insertPosition(0, cast(int) s.length); // Select entire input field
        input.show(); // Show the input widget, now that we've positioned it
        input.takeFocus();
    }

    // Tell the input widget it's done editing, and to 'hide'
    void doneEditing()
    {
        if (input.visible()) // input widget visible, ie. edit in progress?
            setValueHide(); // Transfer its current contents to cell and hide
    }

    // Return the sum of all rows in this column
    int sumRows(int C)
    {
        int sum = 0;
        foreach (r; 0 .. rows() - 1) // -1: don't include cell data in 'totals' column
            sum += values[r][C];
        return sum;
    }

    // Return the sum of all cols in this row
    int sumCols(int R)
    {
        int sum = 0;
        foreach (c; 0 .. cols() - 1) // -1: don't include cell data in 'totals' column
            sum += values[R][c];
        return sum;
    }

    // Return the sum of all cells in table
    int sumAll()
    {
        int sum = 0;
        foreach (c; 0 .. cols() - 1) // -1: don't include cell data in 'totals' column
            foreach (r; 0 .. rows() - 1) // -1: ""
                sum += values[r][c];
        return sum;
    }
}

void main()
{
    fl.option(fl.Option.arrowFocus, true); // we want arrow keys to navigate table's widgets
    auto win = new DoubleWindow(922, 382, "Table Spreadsheet with Keyboard Navigation");
    auto table = new Spreadsheet(20, 20, win.w() - 80, win.h() - 80);
    // Table rows
    table.rowHeader(true);
    table.rowHeaderWidth(70);
    table.rowResize(true);
    table.rows(11);
    table.rowHeightAll(25);
    // Table cols
    table.colHeader(true);
    table.colHeaderHeight(25);
    table.colResize(true);
    table.cols(11);
    table.colWidthAll(70);
    table.setSelection(0, 0, 0, 0); // select top/left cell

    // Add children to window
    win.begin();

    // Row slider
    auto setrows = new ValueSlider(win.w() - 40, 20, 20, win.h() - 80, null);
    setrows.type(vertNiceSlider);
    setrows.bounds(2, maxRows);
    setrows.step(1);
    setrows.value(table.rows() - 1);
    setrows.callback((w) {
        auto v = cast(Valuator) w;
        table.rows(cast(int) v.value() + 1);
        table.redraw();
    });
    setrows.when(whenChanged);
    setrows.clearVisibleFocus();

    // Column slider
    auto setcols = new ValueSlider(20, win.h() - 40, win.w() - 80, 20, null);
    setcols.type(horNiceSlider);
    setcols.bounds(2, maxCols);
    setcols.step(1);
    setcols.value(table.cols() - 1);
    setcols.callback((w) {
        auto v = cast(Valuator) w;
        table.cols(cast(int) v.value() + 1);
        table.redraw();
    });
    setcols.when(whenChanged);
    setcols.clearVisibleFocus();

    win.end();
    win.resizable(table);
    win.show();

    fl.run();
}
