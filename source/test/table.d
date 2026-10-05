// D transliteration of FLTK's test/table.cxx.
// Build: rdmd buildsamples.d test table
//
// exercisetablerow -- Exercise all aspects of the Fl_Table_Row widget
import fl;
import std.conv : to, ConvException;
import std.format : format;

enum int terminalHeight = 120;

// Globals
Terminal gTty;

// Simple demonstration class to derive from Fl_Table_Row
class DemoTable : TableRow
{
private:
    Color cellBgcolor; // color of cell's bg color
    Color cellFgcolor; // color of cell's fg color
    bool showCallbacks_; // set to show callback msgs

protected:
    override void drawCell(TableContext context, // table cell drawing
            int R = 0, int C = 0, int X = 0, int Y = 0, int W = 0, int H = 0)
    {
        string s = format("%d/%d", R, C); // text for each cell

        switch (context)
        {
        case contextStartpage:
            fl_font(helvetica, 16);
            return;

        case contextColHeader:
            pushClip(X, Y, W, H);
            {
                drawBoxAt(Boxtype.thinUpBox, X, Y, W, H, colHeaderColor());
                fl_color(black);
                fl_draw(s, X, Y, W, H, alignCenter);
            }
            popClip();
            return;

        case contextRowHeader:
            pushClip(X, Y, W, H);
            {
                drawBoxAt(Boxtype.thinUpBox, X, Y, W, H, rowHeaderColor());
                fl_color(black);
                fl_draw(s, X, Y, W, H, alignCenter);
            }
            popClip();
            return;

        case contextCell:
            pushClip(X, Y, W, H);
            {
                // BG COLOR
                fl_color(rowSelected(R) ? selectionColor() : cellBgcolor);
                fl_rectf(X, Y, W, H);

                // TEXT
                fl_color(cellFgcolor);
                fl_draw(s, X, Y, W, H, alignCenter);

                // BORDER
                fl_color(color());
                fl_rect(X, Y, W, H);
            }
            popClip();
            return;

        case contextTable:
            gTty.printf("TABLE CONTEXT CALLED\n");
            return;

        case contextEndpage:
        case contextRcResize:
        case contextNone:
            return;
        default:
            return;
        }
    }

    // Callback for table events
    void eventCallback2()
    {
        int R = callbackRow(), C = callbackCol();
        TableContext context = callbackContext();
        string name = label() ? label() : "?";
        if (showCallbacks_)
            gTty.printf("'%s' callback: Row=%d Col=%d Context=%d Event=%d InteractiveResize? %d\n",
                    name, R, C, cast(int) context, cast(int) fl.event(), cast(int) isInteractiveResize());
    }

public:
    this(int x, int y, int w, int h, string l = null)
    {
        super(x, y, w, h, l);
        cellBgcolor = white;
        cellFgcolor = black;
        showCallbacks_ = false;
        callback((w) { eventCallback2(); });
        end();
    }

    Color getCellFGColor() const { return cellFgcolor; }
    Color getCellBGColor() const { return cellBgcolor; }
    void setCellFGColor(Color val) { cellFgcolor = val; }
    void setCellBGColor(Color val) { cellBgcolor = val; }
    void showCallbacks(bool val) { showCallbacks_ = val; }
}

// GLOBAL TABLE WIDGET
DemoTable gTable;

void setrowsCb(Input in_)
{
    // FLTK reads this via atoi(), which returns 0 for unparseable
    // input (e.g. an empty field) instead of throwing -- to!int() has
    // no such fallback, so catch it explicitly rather than letting an
    // empty/garbage field crash the app.
    int rows;
    try
        rows = to!int(in_.value());
    catch (ConvException)
        rows = 0;
    if (rows < 0)
        rows = 0;
    gTable.rows(rows);
}

void setcolsCb(Input in_)
{
    int cols;
    try
        cols = to!int(in_.value());
    catch (ConvException)
        cols = 0;
    if (cols < 0)
        cols = 0;
    gTable.cols(cols);
}

void setrowheaderCb(CheckButton check)
{
    gTable.rowHeader(check.value());
}

void setcolheaderCb(CheckButton check)
{
    gTable.colHeader(check.value());
}

void setrowresizeCb(CheckButton check)
{
    gTable.rowResize(check.value());
}

void setcolresizeCb(CheckButton check)
{
    gTable.colResize(check.value());
}

void setpositionrowCb(Input in_)
{
    int toprow;
    try
        toprow = to!int(in_.value());
    catch (ConvException)
        toprow = 0;
    if (toprow < 0 || toprow >= gTable.rows())
        alert("Must be in range 0 thru #rows");
    else
        gTable.rowPosition(toprow);
}

void setpositioncolCb(Input in_)
{
    int leftcol;
    try
        leftcol = to!int(in_.value());
    catch (ConvException)
        leftcol = 0;
    if (leftcol < 0 || leftcol >= gTable.cols())
        alert("Must be in range 0 thru #cols");
    else
        gTable.colPosition(leftcol);
}

void setrowheaderwidthCb(Input in_)
{
    int val;
    try
        val = to!int(in_.value());
    catch (ConvException)
        val = 0;
    if (val < 1)
    {
        val = 1;
        in_.value("1");
    }
    gTable.rowHeaderWidth(val);
}

void setcolheaderheightCb(Input in_)
{
    int val;
    try
        val = to!int(in_.value());
    catch (ConvException)
        val = 0;
    if (val < 1)
    {
        val = 1;
        in_.value("1");
    }
    gTable.colHeaderHeight(val);
}

void setrowheadercolorCb(Input in_)
{
    int val;
    try
        val = to!int(in_.value());
    catch (ConvException)
        val = 0;
    if (val < 0)
        alert("Must be a color >0");
    else
        gTable.rowHeaderColor(cast(Color) val);
}

void setcolheadercolorCb(Input in_)
{
    int val;
    try
        val = to!int(in_.value());
    catch (ConvException)
        val = 0;
    if (val < 0)
        alert("Must be a color >0");
    else
        gTable.colHeaderColor(cast(Color) val);
}

void setrowheightallCb(Input in_)
{
    int val;
    try
        val = to!int(in_.value());
    catch (ConvException)
        val = 0;
    if (val < 0)
    {
        val = 0;
        in_.value("0");
    }
    gTable.rowHeightAll(val);
}

void setcolwidthallCb(Input in_)
{
    int val;
    try
        val = to!int(in_.value());
    catch (ConvException)
        val = 0;
    if (val < 0)
    {
        val = 0;
        in_.value("0");
    }
    gTable.colWidthAll(val);
}

void settablecolorCb(Input in_)
{
    int val;
    try
        val = to!int(in_.value());
    catch (ConvException)
        val = 0;
    if (val < 0)
        alert("Must be a color >0");
    else
        gTable.color(cast(Color) val);
    gTable.redraw();
}

void setcellfgcolorCb(Input in_)
{
    int val;
    try
        val = to!int(in_.value());
    catch (ConvException)
        val = 0;
    if (val < 0)
        alert("Must be a color >0");
    else
        gTable.setCellFGColor(cast(Color) val);
    gTable.redraw();
}

void setcellbgcolorCb(Input in_)
{
    int val;
    try
        val = to!int(in_.value());
    catch (ConvException)
        val = 0;
    if (val < 0)
        alert("Must be a color >0");
    else
        gTable.setCellBGColor(cast(Color) val);
    gTable.redraw();
}

string itoa(int val)
{
    return to!string(val);
}

void tableboxChoiceCb(Boxtype b)
{
    gTable.tableBox(b);
    gTable.redraw();
}

void widgetboxChoiceCb(Boxtype b)
{
    gTable.box(b);
    gTable.resize(gTable.x(), gTable.y(), gTable.w(), gTable.h());
}

void typeChoiceCb(TableRowSelectMode m)
{
    gTable.selectMode(m);
}

MenuItem[] tableboxChoices = [
    MenuItem("No Box", 0, (w) { tableboxChoiceCb(Boxtype.noBox); }),
    MenuItem("Flat Box", 0, (w) { tableboxChoiceCb(Boxtype.flatBox); }),
    MenuItem("Up Box", 0, (w) { tableboxChoiceCb(Boxtype.upBox); }),
    MenuItem("Down Box", 0, (w) { tableboxChoiceCb(Boxtype.downBox); }),
    MenuItem("Up Frame", 0, (w) { tableboxChoiceCb(Boxtype.upFrame); }),
    MenuItem("Down Frame", 0, (w) { tableboxChoiceCb(Boxtype.downFrame); }),
    MenuItem("Thin Up Box", 0, (w) { tableboxChoiceCb(Boxtype.thinUpBox); }),
    MenuItem("Thin Down Box", 0, (w) { tableboxChoiceCb(Boxtype.thinDownBox); }),
    MenuItem("Thin Up Frame", 0, (w) { tableboxChoiceCb(Boxtype.thinUpFrame); }),
    MenuItem("Thin Down Frame", 0, (w) { tableboxChoiceCb(Boxtype.thinDownFrame); }),
    MenuItem("Engraved Box", 0, (w) { tableboxChoiceCb(Boxtype.engravedBox); }),
    MenuItem("Embossed Box", 0, (w) { tableboxChoiceCb(Boxtype.embossedBox); }),
    MenuItem("Engraved Frame", 0, (w) { tableboxChoiceCb(Boxtype.engravedFrame); }),
    MenuItem("Embossed Frame", 0, (w) { tableboxChoiceCb(Boxtype.embossedFrame); }),
    MenuItem("Border Box", 0, (w) { tableboxChoiceCb(Boxtype.borderBox); }),
    MenuItem("Shadow Box", 0, (w) { tableboxChoiceCb(Boxtype.shadowBox); }),
    MenuItem("Border Frame", 0, (w) { tableboxChoiceCb(Boxtype.borderFrame); }),
    MenuItem(null),
];

MenuItem[] widgetboxChoices = [
    MenuItem("No Box", 0, (w) { widgetboxChoiceCb(Boxtype.noBox); }),
    //MenuItem("Flat Box", 0, (w) { widgetboxChoiceCb(Boxtype.flatBox); }),
    //MenuItem("Up Box", 0, (w) { widgetboxChoiceCb(Boxtype.upBox); }),
    //MenuItem("Down Box", 0, (w) { widgetboxChoiceCb(Boxtype.downBox); }),
    MenuItem("Up Frame", 0, (w) { widgetboxChoiceCb(Boxtype.upFrame); }),
    MenuItem("Down Frame", 0, (w) { widgetboxChoiceCb(Boxtype.downFrame); }),
    //MenuItem("Thin Up Box", 0, (w) { widgetboxChoiceCb(Boxtype.thinUpBox); }),
    //MenuItem("Thin Down Box", 0, (w) { widgetboxChoiceCb(Boxtype.thinDownBox); }),
    MenuItem("Thin Up Frame", 0, (w) { widgetboxChoiceCb(Boxtype.thinUpFrame); }),
    MenuItem("Thin Down Frame", 0, (w) { widgetboxChoiceCb(Boxtype.thinDownFrame); }),
    //MenuItem("Engraved Box", 0, (w) { widgetboxChoiceCb(Boxtype.engravedBox); }),
    //MenuItem("Embossed Box", 0, (w) { widgetboxChoiceCb(Boxtype.embossedBox); }),
    MenuItem("Engraved Frame", 0, (w) { widgetboxChoiceCb(Boxtype.engravedFrame); }),
    MenuItem("Embossed Frame", 0, (w) { widgetboxChoiceCb(Boxtype.embossedFrame); }),
    //MenuItem("Border Box", 0, (w) { widgetboxChoiceCb(Boxtype.borderBox); }),
    //MenuItem("Shadow Box", 0, (w) { widgetboxChoiceCb(Boxtype.shadowBox); }),
    MenuItem("Border Frame", 0, (w) { widgetboxChoiceCb(Boxtype.borderFrame); }),
    MenuItem(null),
];

MenuItem[] typeChoices = [
    MenuItem("SelectNone", 0, (w) { typeChoiceCb(TableRowSelectMode.selectNone); }),
    MenuItem("SelectSingle", 0, (w) { typeChoiceCb(TableRowSelectMode.selectSingle); }),
    MenuItem("SelectMulti", 0, (w) { typeChoiceCb(TableRowSelectMode.selectMulti); }),
    MenuItem(null),
];

void main(string[] args)
{
    auto win = new Window(900, 730 + terminalHeight);

    gTty = new Terminal(0, 730, win.w(), terminalHeight);

    gTable = new DemoTable(20, 20, 860, 460, "Demo");
    gTable.selectionColor(yellow);
    gTable.when(whenRelease | whenChanged);
    gTable.tableBox(Boxtype.noBox);
    gTable.colResizeMin(4);
    gTable.rowResizeMin(4);

    // ROWS
    gTable.rowHeader(true);
    gTable.rowHeaderWidth(60);
    gTable.rowResize(true);
    gTable.rows(500);
    gTable.rowHeightAll(20);

    // COLS
    gTable.cols(500);
    gTable.colHeader(true);
    gTable.colHeaderHeight(25);
    gTable.colResize(true);
    gTable.colWidthAll(80);

    // After initialization, show table's callbacks
    gTable.showCallbacks(true);

    // Add children to window
    win.begin();

    // ROW
    auto setrows = new Input(150, 500, 120, 25, "Rows");
    setrows.labelsize(12);
    setrows.value(itoa(gTable.rows()));
    setrows.callback((w) { setrowsCb(setrows); });
    setrows.when(whenRelease);

    auto rowheightall = new Input(400, 500, 120, 25, "Row Height");
    rowheightall.labelsize(12);
    rowheightall.value(itoa(gTable.rowHeight(0)));
    rowheightall.callback((w) { setrowheightallCb(rowheightall); });
    rowheightall.when(whenRelease);

    auto positionrow = new Input(650, 500, 120, 25, "Row Position");
    positionrow.labelsize(12);
    positionrow.value("1");
    positionrow.callback((w) { setpositionrowCb(positionrow); });
    positionrow.when(whenRelease);

    // COL
    auto setcols = new Input(150, 530, 120, 25, "Cols");
    setcols.labelsize(12);
    setcols.value(itoa(gTable.cols()));
    setcols.callback((w) { setcolsCb(setcols); });
    setcols.when(whenRelease);

    auto colwidthall = new Input(400, 530, 120, 25, "Col Width");
    colwidthall.labelsize(12);
    colwidthall.value(itoa(gTable.colWidth(0)));
    colwidthall.callback((w) { setcolwidthallCb(colwidthall); });
    colwidthall.when(whenRelease);

    auto positioncol = new Input(650, 530, 120, 25, "Col Position");
    positioncol.labelsize(12);
    positioncol.value("1");
    positioncol.callback((w) { setpositioncolCb(positioncol); });
    positioncol.when(whenRelease);

    // ROW HEADER
    auto rowheaderwidth = new Input(150, 570, 120, 25, "Row Header Width");
    rowheaderwidth.labelsize(12);
    rowheaderwidth.value(itoa(gTable.rowHeaderWidth()));
    rowheaderwidth.callback((w) { setrowheaderwidthCb(rowheaderwidth); });
    rowheaderwidth.when(whenRelease);

    auto rowheadercolor = new Input(400, 570, 120, 25, "Row Header Color");
    rowheadercolor.labelsize(12);
    rowheadercolor.value(itoa(cast(int) gTable.rowHeaderColor()));
    rowheadercolor.callback((w) { setrowheadercolorCb(rowheadercolor); });
    rowheadercolor.when(whenRelease);

    auto rowheader = new CheckButton(550, 570, 120, 25, "Row Headers?");
    rowheader.labelsize(12);
    rowheader.callback((w) { setrowheaderCb(rowheader); });
    rowheader.value(gTable.rowHeader());

    auto rowresize = new CheckButton(700, 570, 120, 25, "Row Resize?");
    rowresize.labelsize(12);
    rowresize.callback((w) { setrowresizeCb(rowresize); });
    rowresize.value(gTable.rowResize());

    // COL HEADER
    auto colheaderheight = new Input(150, 600, 120, 25, "Col Header Height");
    colheaderheight.labelsize(12);
    colheaderheight.value(itoa(gTable.colHeaderHeight()));
    colheaderheight.callback((w) { setcolheaderheightCb(colheaderheight); });
    colheaderheight.when(whenRelease);

    auto colheadercolor = new Input(400, 600, 120, 25, "Col Header Color");
    colheadercolor.labelsize(12);
    colheadercolor.value(itoa(cast(int) gTable.colHeaderColor()));
    colheadercolor.callback((w) { setcolheadercolorCb(colheadercolor); });
    colheadercolor.when(whenRelease);

    auto colheader = new CheckButton(550, 600, 120, 25, "Col Headers?");
    colheader.labelsize(12);
    colheader.callback((w) { setcolheaderCb(colheader); });
    colheader.value(gTable.colHeader());

    auto colresize = new CheckButton(700, 600, 120, 25, "Col Resize?");
    colresize.labelsize(12);
    colresize.callback((w) { setcolresizeCb(colresize); });
    colresize.value(gTable.colResize());

    auto tablebox = new Choice(150, 640, 120, 25, "Table Box");
    tablebox.labelsize(12);
    tablebox.textsize(12);
    tablebox.menu(tableboxChoices);
    tablebox.value(0);

    auto widgetbox = new Choice(150, 670, 120, 25, "Widget Box");
    widgetbox.labelsize(12);
    widgetbox.textsize(12);
    widgetbox.menu(widgetboxChoices);
    widgetbox.value(2); // down frame

    auto tablecolor = new Input(400, 640, 120, 25, "Table Color");
    tablecolor.labelsize(12);
    tablecolor.value(itoa(cast(int) gTable.color()));
    tablecolor.callback((w) { settablecolorCb(tablecolor); });
    tablecolor.when(whenRelease);

    auto cellbgcolor = new Input(400, 670, 120, 25, "Cell BG Color");
    cellbgcolor.labelsize(12);
    cellbgcolor.value(itoa(cast(int) gTable.getCellBGColor()));
    cellbgcolor.callback((w) { setcellbgcolorCb(cellbgcolor); });
    cellbgcolor.when(whenRelease);

    auto cellfgcolor = new Input(400, 700, 120, 25, "Cell FG Color");
    cellfgcolor.labelsize(12);
    cellfgcolor.value(itoa(cast(int) gTable.getCellFGColor()));
    cellfgcolor.callback((w) { setcellfgcolorCb(cellfgcolor); });
    cellfgcolor.when(whenRelease);

    auto type = new Choice(650, 640, 120, 25, "Type");
    type.labelsize(12);
    type.textsize(12);
    type.menu(typeChoices);
    type.value(2);

    win.end();
    win.resizable(gTable);
    win.show(args);

    fl.run();
}
