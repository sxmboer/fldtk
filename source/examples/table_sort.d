// D transliteration of FLTK's examples/table-sort.cxx.
// Build: rdmd buildsamples.d examples table_sort
import fl;
import std.format : format;
import std.algorithm : sort;
import std.ascii : isDigit;
import std.conv : parse;
import std.process : executeShell;
import std.string : splitLines, split;

enum margin = 20;

version (Windows)
{
    // WINDOWS
    // DIR flags that simplify parsing:
    //    /-C   -- disable 1000's separator in file sizes
    //    /A-D  -- don't show directories
    enum dircmd = "dir /-C /A-D";
    immutable string[] gHeader = ["Date", "Time", "Size", "Filename"];
}
else
{
    // UNIX
    enum dircmd = "ls -l";
    immutable string[] gHeader = ["Perms", "#L", "Own", "Group", "Size", "Date", "", "", "Filename"];
}

// Font face/sizes for header and rows
enum headerFontface = helveticaBold;
enum headerFontsize = 16;
enum rowFontface = helvetica;
enum rowFontsize = 16;

// A single row of columns
struct Row
{
    string[] cols;
}

// Derive a custom class from TableRow
class MyTable : TableRow
{
private:
    Row[] rowdata_;
    bool sortReverse_;
    int sortLastcol_;

protected:
    override void drawCell(TableContext context, int R = 0, int C = 0,
            int X = 0, int Y = 0, int W = 0, int H = 0)
    {
        string s = "";
        if (R < cast(int) rowdata_.length && C < cast(int) rowdata_[R].cols.length)
            s = rowdata_[R].cols[C];
        final switch (context)
        {
        case contextColHeader:
            pushClip(X, Y, W, H);
            drawBoxAt(Boxtype.thinUpBox, X, Y, W, H, backgroundColor);
            if (C < cast(int) gHeader.length)
            {
                fl_font(headerFontface, headerFontsize);
                fl_color(black);
                fl_draw(gHeader[C], X + 2, Y, W, H, alignLeft); // +2=pad left
                // Draw sort arrow
                if (C == sortLastcol_)
                    drawSortArrow(X, Y, W, H);
            }
            popClip();
            return;
        case contextCell:
            pushClip(X, Y, W, H);
            Color bgcolor = rowSelected(R) ? selectionColor() : white;
            fl_color(bgcolor);
            fl_rectf(X, Y, W, H);
            fl_font(rowFontface, rowFontsize);
            fl_color(black);
            fl_draw(s, X + 2, Y, W, H, alignLeft); // +2=pad left
            fl_color(light2);
            fl_rect(X, Y, W, H);
            popClip();
            return;
        case contextNone:
        case contextStartpage:
        case contextEndpage:
        case contextRowHeader:
        case contextTable:
        case contextRcResize:
            return;
        }
    }

    void sortColumn(int col, bool reverse = false)
    {
        // Cheezy numeric-vs-alphabetic column comparison, mirroring
        // FLTK's SortColumn functor as a captured local predicate.
        bool cmp(const Row a, const Row b)
        {
            string ap = (col < cast(int) a.cols.length) ? a.cols[col] : "";
            string bp = (col < cast(int) b.cols.length) ? b.cols[col] : "";
            if (ap.length && bp.length && isDigit(ap[0]) && isDigit(bp[0]))
            {
                auto apCopy = ap;
                auto bpCopy = bp;
                int av = parse!int(apCopy);
                int bv = parse!int(bpCopy);
                return reverse ? av < bv : bv < av;
            }
            else
            {
                return reverse ? (ap > bp) : (ap < bp);
            }
        }

        rowdata_.sort!cmp;
        redraw();
    }

    void drawSortArrow(int X, int Y, int W, int H)
    {
        int xlft = X + (W - 6) - 8;
        int xctr = X + (W - 6) - 4;
        int xrit = X + (W - 6) - 0;
        int ytop = Y + (H / 2) - 4;
        int ybot = Y + (H / 2) + 4;
        if (sortReverse_)
        {
            // Engraved down arrow
            fl_color(white);
            fl_line(xrit, ytop, xctr, ybot);
            fl_color(41); // dark gray
            fl_line(xlft, ytop, xrit, ytop);
            fl_line(xlft, ytop, xctr, ybot);
        }
        else
        {
            // Engraved up arrow
            fl_color(white);
            fl_line(xrit, ybot, xctr, ytop);
            fl_line(xrit, ybot, xlft, ybot);
            fl_color(41); // dark gray
            fl_line(xlft, ybot, xctr, ytop);
        }
    }

public:
    // Ctor
    this(int x, int y, int w, int h, string l = null)
    {
        super(x, y, w, h, l);
        sortReverse_ = false;
        sortLastcol_ = -1;
        end();
        callback((w) { eventCallback2(); });
    }

    // Callback whenever someone clicks on different parts of the table
    void eventCallback2()
    {
        int COL = callbackCol();
        TableContext context = callbackContext();
        if (context == contextColHeader)
        {
            if (fl.event() == Event.release && fl.eventButton() == leftMouse)
            {
                if (sortLastcol_ == COL) // Click same column? Toggle sort
                    sortReverse_ = !sortReverse_;
                else // Click diff column? Up sort
                    sortReverse_ = false;
                sortColumn(COL, sortReverse_);
                sortLastcol_ = COL;
            }
        }
    }

    // Load table with output of 'cmd'
    void loadCommand(string cmd)
    {
        cols(0);
        auto output = executeShell(cmd).output;
        int line = 0;
        foreach (s; output.splitLines())
        {
            version (Windows)
            {
                // WINDOWS: ignore header/footer lines (blank, or
                // starting with a space) -- matches FLTK's own
                // `dir` output parsing exactly.
                if (s.length == 0 || s[0] == ' ')
                {
                    line++;
                    continue;
                }
            }
            else
            {
                // UNIX
                if (line == 0 && s.length >= 6 && s[0 .. 6] == "total ")
                {
                    line++;
                    continue;
                }
            }
            line++;
            Row newrow;
            string[] tokens = s.split();
            string[] parts;
            foreach (t, tok; tokens)
            {
                version (Windows)
                {
                    // DIR: some systems show a meridiem (AM/PM) field,
                    // some don't (24hr time) -- merge it back into the
                    // previous (time) column when present.
                    if (t == 2 && (tok == "AM" || tok == "PM"))
                    {
                        parts[$ - 1] ~= " " ~ tok;
                        continue;
                    }
                }
                parts ~= tok;
            }
            newrow.cols = parts;
            rowdata_ ~= newrow;
            if (cast(int) newrow.cols.length > cols())
                cols(cast(int) newrow.cols.length);
        }

        // How many rows we loaded
        rows(cast(int) rowdata_.length);
        // Auto-calculate widths, with 20 pixel padding
        autowidth(20);
    }

    // Automatically set column widths to widest data in each column
    void autowidth(int pad)
    {
        int w, h;
        fl_font(headerFontface, headerFontsize);
        foreach (c; 0 .. cast(int) gHeader.length)
        {
            w = 0;
            fl_measure(gHeader[c], w, h);
            colWidth(c, w + pad);
        }
        fl_font(rowFontface, rowFontsize);
        foreach (r; 0 .. cast(int) rowdata_.length)
        {
            foreach (c; 0 .. cast(int) rowdata_[r].cols.length)
            {
                w = 0;
                fl_measure(rowdata_[r].cols[c], w, h);
                if ((w + pad) > colWidth(c))
                    colWidth(c, w + pad);
            }
        }
        tableResized();
        redraw();
    }

    // Resize parent window to size of table
    void resizeWindow()
    {
        int width = 2; // width of table borders
        foreach (t; 0 .. cols())
            width += colWidth(t);
        width += vscrollbar_.w();
        width += margin * 2;
        if (width < 200 || width > fl.w())
            return;
        window().resize(window().x(), window().y(), width, window().h());
    }
}

void main()
{
    auto win = new DoubleWindow(900, 500, "Table Sort");
    auto table = new MyTable(margin, margin, win.w() - margin * 2, win.h() - margin * 2);
    table.selectionColor(yellow);
    table.colHeader(true);
    table.colResize(true);
    table.when(whenRelease); // handle table events on release
    table.loadCommand(dircmd); // load table with a directory listing
    table.rowHeightAll(18); // height of all rows
    table.tooltip("Click on column headings to toggle column sorting");
    table.color(white);
    win.end();
    win.resizable(table);
    table.resizeWindow();
    win.show();
    fl.run();
}
