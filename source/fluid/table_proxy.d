/*
 * The `Table` stand-in shown on the design canvas: a small table of
 * sample data with row and column headers, so a freshly created
 * `Table` is visible and sized meaningfully while editing. Ported from
 * `Fl_Table_Proxy` (`fluid/nodes/Group_Node.cxx`). Generated code
 * creates a plain `fl.table.Table`; only the canvas uses this class.
 */
module fluid.table_proxy;

import fl;
import std.format : format;

final class TableProxy : Table
{
    private enum maxRows = 14;
    private enum maxCols = 7;

    private int[maxCols][maxRows] data_;

    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        end();
        foreach (r; 0 .. maxRows)
            foreach (c; 0 .. maxCols)
                data_[r][c] = 1000 + r * 1000 + c;
        rows(maxRows);
        rowHeader(true);
        rowHeightAll(20);
        rowResize(false);
        cols(maxCols);
        colHeader(true);
        colWidthAll(80);
        colResize(true);
    }

    /// Row/column headings: a dark thin up box with the text inside.
    private void drawHeader(string s, int X, int Y, int W, int H)
    {
        pushClip(X, Y, W, H);
        drawBoxAt(Boxtype.thinUpBox, X, Y, W, H, rowHeaderColor());
        fl_color(black);
        fl_draw(s, X, Y, W, H, alignCenter);
        popClip();
    }

    /// Cell data: dark gray text on a white background with a subtle border.
    private void drawData(string s, int X, int Y, int W, int H)
    {
        pushClip(X, Y, W, H);
        fl_color(white);
        fl_rectf(X, Y, W, H);
        fl_color(gray0);
        fl_draw(s, X, Y, W, H, alignCenter);
        fl_color(color());
        fl_rect(X, Y, W, H);
        popClip();
    }

    protected override void drawCell(TableContext context, int row = 0, int col = 0,
        int X = 0, int Y = 0, int W = 0, int H = 0)
    {
        switch (context)
        {
        case contextStartpage:
            fl_font(helvetica, 16);
            return;
        case contextColHeader:
            drawHeader(format("%c", cast(char)('A' + col)), X, Y, W, H);
            return;
        case contextRowHeader:
            drawHeader(format("%03d:", row), X, Y, W, H);
            return;
        case contextCell:
            drawData(format("%d", data_[row][col]), X, Y, W, H);
            return;
        default:
            return;
        }
    }
}
