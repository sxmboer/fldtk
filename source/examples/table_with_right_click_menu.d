// D transliteration of FLTK's examples/table-with-right-click-menu.cxx.
// Build: rdmd buildsamples.d examples table_with_right_click_menu
import fl;
import std.format : format;
import std.stdio : writefln;

enum maxRows = 30;
enum maxCols = 26; // A-Z

// Derive a class from Table
class MyTable : Table
{
    // Post context menu at current event x,y
    private void postContextMenu()
    {
        TableContext context = callbackContext();
        if (context == contextColHeader || context == contextCell)
        {
            string s;
            // Create context sensitive menu label
            if (context == contextCell)
                s = format("Cell %c%d", cast(char)('A' + callbackCol()), callbackRow());
            else
                s = format("Column %c", cast(char)('A' + callbackCol()));
            // Post dynamically created context menu, get user's choice
            auto menu = new MenuButton(fl.eventX(), fl.eventY(), 80, 1);
            menu.add(s, 0, null, menuDivider | menuInactive);
            menu.add("Item 1", 0, null);
            menu.add("Item 2", 0, null);
            auto item = menu.popup();
            if (item !is null)
                writefln("You chose '%s'", item.label());
        }
    }

    // Draw the row/col headings
    //    Make this a dark thin upbox with the text inside.
    private void drawHeader(string s, int X, int Y, int W, int H)
    {
        pushClip(X, Y, W, H);
        drawBoxAt(Boxtype.thinUpBox, X, Y, W, H, rowHeaderColor());
        fl_color(black);
        fl_draw(s, X, Y, W, H, alignCenter);
        popClip();
    }

    // Draw the cells
    private void drawCellText(string s, int X, int Y, int W, int H)
    {
        pushClip(X, Y, W, H);
        fl_color(white);
        fl_rectf(X, Y, W, H); // Draw cell bg
        fl_color(gray0);
        fl_draw(s, X, Y, W, H, alignCenter); // Draw cell text
        fl_color(color());
        fl_rect(X, Y, W, H); // Draw box border
        popClip();
    }

    // Handle drawing table's cells
    override void drawCell(TableContext context, int ROW = 0, int COL = 0,
            int X = 0, int Y = 0, int W = 0, int H = 0)
    {
        final switch (context)
        {
        case contextStartpage: // before page is drawn..
            fl_font(helvetica, 16); // set the font for our drawing operations
            return;
        case contextColHeader: // Draw column headers
            drawHeader(format("%c", cast(char)('A' + COL)), X, Y, W, H); // "A", "B", "C", etc.
            return;
        case contextRowHeader: // Draw row headers
            drawHeader(format("%03d:", ROW), X, Y, W, H); // "001:", "002:", etc
            return;
        case contextCell: // Draw cells
            drawCellText(format("%c%d", cast(char)('A' + COL), ROW), X, Y, W, H);
            return;
        case contextNone:
        case contextEndpage:
        case contextTable:
        case contextRcResize:
            return;
        }
    }

public:
    // Constructor
    this(int X, int Y, int W, int H, string L = null)
    {
        super(X, Y, W, H, L);
        // Rows
        rows(maxRows); // how many rows
        rowHeader(true); // enable row headers (along left)
        rowHeightAll(20); // default height of rows
        rowResize(false); // disable row resizing
        // Cols
        cols(maxCols); // how many columns
        colHeader(true); // enable column headers (along top)
        colWidthAll(80); // default width of columns
        colResize(true); // enable column resizing
        end(); // end the Table group
        callback((w) {
            if (fl.eventButton() == rightMouse)
                postContextMenu();
        }); // set a callback for the table
    }
}

void main()
{
    auto win = new DoubleWindow(900, 400, "Table Simple");
    auto table = new MyTable(10, 10, 880, 380);
    win.end();
    win.resizable(table);
    win.show();
    fl.run();
}
