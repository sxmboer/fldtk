// D transliteration of FLTK's examples/table-simple.cxx.
// Build: rdmd buildsamples.d examples table_simple
import fl;
import std.format : format;

enum maxRows = 30;
enum maxCols = 26; // A-Z

// Derive a class from Table
class MyTable : Table
{
    int[maxCols][maxRows] data; // data array for cells

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

    // Draw the cell data
    //    Dark gray text on white background with subtle border
    private void drawData(string s, int X, int Y, int W, int H)
    {
        pushClip(X, Y, W, H);
        fl_color(white);
        fl_rectf(X, Y, W, H); // Draw cell bg
        fl_color(gray0);
        fl_draw(s, X, Y, W, H, alignCenter); // Draw cell data
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
            drawHeader(format("%c", cast(char)('A' + COL)), X, Y, W, H);
            return;
        case contextRowHeader: // Draw row headers
            drawHeader(format("%03d:", ROW), X, Y, W, H);
            return;
        case contextCell: // Draw data in cells
            drawData(format("%d", data[ROW][COL]), X, Y, W, H);
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
    //     Make our data array, and initialize the table options.
    this(int X, int Y, int W, int H, string L = null)
    {
        super(X, Y, W, H, L);
        // Fill data array
        foreach (r; 0 .. maxRows)
            foreach (c; 0 .. maxCols)
                data[r][c] = 1000 + (r * 1000) + c;
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
