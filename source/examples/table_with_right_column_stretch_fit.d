// D transliteration of FLTK's examples/table-with-right-column-stretch-fit.cxx
// (~/Repositories/fltk).
// Part of the samples/ contract -- see samples/README.md.
// Check: ./samples/build.sh table-with-right-column-stretch-fit
import fl;
import std.format : format;

// Derive a class from Table
class MyTable : Table
{
    // Draw the row/col headings
    //    Make this a dark thin upbox with the text inside.
    private void drawHeader(string s, int X, int Y, int W, int H)
    {
        pushClip(X, Y, W, H);
        drawBoxAt(Boxtype.thinUpBox, X, Y, W, H, rowHeaderColor());
        fl_color(black);
        fl_draw(s, X, Y, W, H, alignLeft);
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
        fl_draw(s, X, Y, W, H, alignLeft); // Draw cell data
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
            fl_font(helvetica, 14); // set the font for our drawing operations
            return;
        case contextColHeader: // Draw column headers
            switch (COL)
            {
            case 0:
                drawHeader(" #Id", X, Y, W, H);
                break;
            case 1:
                drawHeader(" Date / Time", X, Y, W, H);
                break;
            default:
                break;
            }
            return;
        case contextRowHeader: // Draw row headers
            return;
        case contextCell: // Draw data in cells
            switch (COL)
            {
            case 0:
                drawData(format(" #%d", ROW), X, Y, W, H);
                break;
            case 1:
                drawData(format(" 2017-01-02 / 09:20:25.%d", ROW), X, Y, W, H);
                break;
            default:
                break;
            }
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
        // Rows
        rows(10); // how many rows
        rowHeader(false); // disable row headers (along left)
        rowHeightAll(20); // default height of rows
        rowResize(false); // disable interactive row resizing
        // Cols
        cols(2); // how many columns
        colHeader(true); // enable column headers (along top)
        colWidth(0, 50); // fixed width for left column
        colWidth(1, 300); // fixed width for right column (changed later by fixColumnSize()..)
        colResize(false); // disable interactive column resizing
        end(); // end the Table group
        fixColumnSize(); // apply our auto-column-sizing behavior
    }

    // Fix the right column's size to precisely match width of window
    void fixColumnSize()
    {
        if (rows() == 0)
            return; // early exit if no rows to work with
        int X, Y, W, H;
        findCell(contextCell, 0, 1, X, Y, W, H); // get xywh of right column cell in first row
        int off = (X + W) - (tox + tow); // we just need X pos and width. Compute offset from table's outer size
        int oldw = colWidth(1); // save old col width
        colWidth(1, oldw - off); // set new column width based on offset for perfect fit
    }

    // Handle window resizing
    override void resize(int X, int Y, int W, int H)
    {
        super.resize(X, Y, W, H);
        fixColumnSize(); // after letting window resize, fix our right most column
    }
}

// Add more rows
void moreCb(MyTable table)
{
    table.rows(table.rows() + 1);
    table.fixColumnSize();
}

// Remove rows
void lessCb(MyTable table)
{
    if (table.rows() > 0)
        table.rows(table.rows() - 1);
    table.fixColumnSize();
}

void main()
{
    auto win = new DoubleWindow(500, 400, "Table With Right Column Stretch Fit");
    auto table = new MyTable(10, 10, win.w() - 20, 340);
    auto more = new Button(10, 360, 100, 25, "+ Row");
    more.callback((w) { moreCb(table); });
    auto less = new Button(220, 360, 100, 25, "- Row");
    less.callback((w) { lessCb(table); });
    win.end();
    win.resizable(table);
    win.show();
    fl.run();
}
