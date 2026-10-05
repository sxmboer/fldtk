/*
 * Ported from FL/Fl_Grid.H + src/Fl_Grid.cxx (FLTK 1.5.0).
 *
 * A FlGroup that lays out its children in a grid of rows/columns, each
 * with its own minimum size, weight (how extra space is distributed
 * on resize), and gap. Faithful, complete port of the layout math
 * (layout()/draw_grid()) and the row/col/cell bookkeeping -- no
 * missing FLTK behavior, only storage-technique simplifications:
 *
 *  - `Cols_`/`Rows_` (manually `new[]`/`delete[]`-managed C arrays,
 *    with hand-written "copy old entries into a bigger/smaller array"
 *    logic in `layout(rows, cols, ...)`) collapse to plain D dynamic
 *    arrays. Setting `.length` on a D array already preserves existing
 *    front elements and default-initializes new ones to the struct's
 *    own field defaults (`Col`/`Row`'s `weight_ = 50`/`gap_ = -1`
 *    included) -- exactly FLTK's copy-preserving-existing-entries
 *    behavior, for free. No destructor is needed either: the GC
 *    reclaims both arrays on its own.
 *  - Each `Row`'s `cells_` was a hand-rolled singly-linked list of
 *    `Cell`s sorted by column (with a public `next()`/`next(Cell*)`
 *    pair on `Cell` existing *solely* to support it -- FLTK's own
 *    doc comment calls this out as a wart that "should be private or
 *    at least protected", GitHub issue #937). Ported as a plain,
 *    column-sorted `Cell[]` per row instead; `next()`/`next(Cell)`
 *    aren't ported at all since nothing needs them once the list
 *    itself is gone.
 *  - `col_width`/`col_weight`/`col_gap`/`row_height`/`row_weight`/
 *    `row_gap`'s `(const int *value, size_t size)` array-setter
 *    overloads collapse to a single `(const(int)[] values)` parameter
 *    -- a D slice already carries its own length.
 *  - `Cell::minimum_size(int*, int*)` (an out-parameter getter) and
 *    `Fl_Grid::margin(int*, int*, int*, int*)`/`gap(int*, int*)`
 *    (same shape) are *not* ported as out-parameter getters: each
 *    would have the exact same arity as an existing same-named setter
 *    overload, which is precisely the ambiguous-overload-resolution
 *    trap `fl.chart`'s `bounds()` hit earlier in this port (a caller
 *    passing plain, non-out-declared locals silently resolves to the
 *    *setter*, not the getter, and the "getter" call is a silent
 *    no-op). Ported as separate plain-return getters instead
 *    (`Cell.minWidth()`/`minHeight()`, `Grid.marginLeft()`/`marginTop()`/
 *    `marginRight()`/`marginBottom()`, `Grid.gapRow()`/`gapCol()`);
 *    the "are all four margins equal?" convenience return value isn't
 *    ported since nothing needs it and it's trivial to recompute from
 *    the four getters if it ever is.
 *  - `Fl_Grid::Cell::align()`/`Fl_Grid::debug()` are renamed to
 *    `Cell.alignment()` / `Grid.dumpLayout()` -- `align` and `debug`
 *    are both D keywords (the former for alignment attributes, the
 *    latter for conditional-compilation blocks), so neither FLTK
 *    name is usable as a plain D identifier.
 *  - `draw_grid()`'s `lineStyle(FL_SOLID, 1)`/`lineStyle(FL_SOLID, 0)`
 *    calls (setting, then restoring, the pen width around the helper
 *    lines) are real, via `fl.draw.lineStyle()`.
 *  - `fl_getenv("FLTK_GRID_DEBUG")` (a locale-aware `getenv()` wrapper
 *    that isn't ported) is replaced with `std.process.environment.get()`
 *    -- a direct, cleaner D stdlib equivalent for the same plain
 *    "is this environment variable set" check.
 */
module fl.grid;

import fl.group : FlGroup;
import fl.widget : Widget;
import fl.rect : Rect;
import fl.enumerations : Boxtype, Color, black, damageChild, lineSolid;
import fl.core;
import fldraw = fl.draw;
import std.process : environment;
import std.stdio : stderr;

/// Fl_Grid_Align: an open bitmask set (combinable via `|`), same
/// alias-plus-constants treatment as Align/Color/Font/When/Damage.
alias GridAlign = ushort;

enum : GridAlign
{
    gridCenter       = 0x0000,
    gridTop          = 0x0001,
    gridBottom       = 0x0002,
    gridLeft         = 0x0004,
    gridRight        = 0x0008,
    gridHorizontal   = 0x0010,
    gridVertical     = 0x0020,
    gridFill         = gridHorizontal | gridVertical,
    gridProportional = 0x0040,
    gridTopLeft      = gridTop | gridLeft,
    gridTopRight     = gridTop | gridRight,
    gridBottomLeft   = gridBottom | gridLeft,
    gridBottomRight  = gridBottom | gridRight,
}

/// A single occupied grid cell: which widget is in it, its position
/// (row/col) and span, its alignment within the cell, and its minimum
/// size. Returned by Grid.widget()/cell() for further configuration
/// (e.g. `grid.widget(b, 0, 0).rowspan(2);`); don't hang onto a Cell
/// past the next layout(int,int,...) call, same caveat FLTK makes.
class Cell
{
    private short row_, col_;
    private short rowspan_ = 1;
    private short colspan_ = 1;
    private GridAlign align_;
    private Widget widget_;
    private int w_, h_;

    private this(int row, int col)
    {
        row_ = cast(short) row;
        col_ = cast(short) col;
    }

    Widget widget() { return widget_; }

    short row() const { return row_; }
    short col() const { return col_; }

    void rowspan(short v) { rowspan_ = v; }
    short rowspan() const { return rowspan_; }
    void colspan(short v) { colspan_ = v; }
    short colspan() const { return colspan_; }

    void alignment(GridAlign a) { align_ = a; }
    GridAlign alignment() const { return align_; }

    /// Sets the cell's minimum widget size; a negative value leaves
    /// that dimension unchanged (matches FLTK's margin()/gap()
    /// "-1 means don't change" convention).
    void minimumSize(int w, int h)
    {
        if (w >= 0) w_ = w;
        if (h >= 0) h_ = h;
    }

    int minWidth() const { return w_; }
    int minHeight() const { return h_; }
}

private struct Col
{
    int minw_;
    int w_;
    short weight_ = 50;
    short gap_ = -1;
}

private struct Row
{
    Cell[] cells_;
    int minh_;
    int h_;
    short weight_ = 50;
    short gap_ = -1;
}

class Grid : FlGroup
{
    private short rowCount_;
    private short colCount_;
    private short marginLeft_, marginTop_, marginRight_, marginBottom_;
    private short gapRow_, gapCol_;
    private Rect oldSize_; // TBD FLTK too -- written on resize(), never read (see the class doc's own "only for resize callback (TBD)" comment)
    private Col[] colArray_;
    private Row[] rowArray_;
    private bool needLayout_;

    protected Color gridColor_;
    protected bool drawGrid_;

    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        resetFields();
        box(Boxtype.flatBox);
    }

    private void resetFields()
    {
        rowCount_ = 0;
        colCount_ = 0;
        marginLeft_ = 0;
        marginTop_ = 0;
        marginRight_ = 0;
        marginBottom_ = 0;
        gapRow_ = 0;
        gapCol_ = 0;
        colArray_ = null;
        rowArray_ = null;
        oldSize_ = Rect(0, 0, 0, 0);
        needLayout_ = false;
        gridColor_ = 0xbbeebb00; // light green
        drawGrid_ = false;
        if (environment.get("FLTK_GRID_DEBUG") !is null)
            drawGrid_ = true;
    }

    /**
     * Sets the basic layout parameters. Calling this again with the
     * same rows/cols is cheap (just updates margin/gap); changing
     * either dimension reallocates the row/col arrays, preserving
     * existing rows/cols up to the smaller of the old/new counts.
     * margin/gap default to -1 ("don't change").
     */
    void layout(int rows, int cols, int margin = -1, int gap = -1)
    {
        if (margin >= 0)
            marginLeft_ = marginTop_ = marginRight_ = marginBottom_ = cast(short) margin;
        if (gap >= 0)
            gapRow_ = gapCol_ = cast(short) gap;

        if (cols == colCount_ && rows == rowCount_) return;

        if (rows <= 0 || cols <= 0)
        {
            clearLayout();
            return;
        }

        colArray_.length = cols;
        rowArray_.length = rows;

        colCount_ = cast(short) cols;
        rowCount_ = cast(short) rows;
        needLayout(true);
    }

    short rows() const { return rowCount_; }
    short cols() const { return colCount_; }

    void needLayout(bool set)
    {
        if (set)
        {
            needLayout_ = true;
            redraw();
        }
        else
        {
            needLayout_ = false;
        }
    }

    bool needLayout() const { return needLayout_; }

    /// Draws the grid helper lines (design/debugging aid, enabled via
    /// showGrid() or the FLTK_GRID_DEBUG environment variable).
    protected void drawGrid()
    {
        int x0 = x() + fl.core.boxDx(box()) + marginLeft_;
        int y0 = y() + fl.core.boxDy(box()) + marginTop_;
        int x1 = x() + w() - fl.core.boxDx(box()) - marginRight_;
        int y1 = y() + h() - fl.core.boxDy(box()) - marginBottom_;

        fldraw.fl_color(gridColor_);
        fldraw.lineStyle(lineSolid, 1);

        fldraw.fl_rect(x0, y0, x1 - x0, y1 - y0);

        for (int r = 0; r < rowCount_ - 1; r++)
        {
            int gap = rowArray_[r].gap_ >= 0 ? rowArray_[r].gap_ : gapRow_;
            y0 += rowArray_[r].h_;
            if (gap == 0)
                fldraw.fl_xyline(x0, y0, x1);
            else
                fldraw.fl_rectf(x0, y0, x1 - x0, gap);
            y0 += gap;
        }

        x0 = x() + fl.core.boxDx(box()) + marginLeft_;
        y0 = y() + fl.core.boxDy(box()) + marginTop_;

        for (int c = 0; c < colCount_ - 1; c++)
        {
            int gap = colArray_[c].gap_ >= 0 ? colArray_[c].gap_ : gapCol_;
            x0 += colArray_[c].w_;
            if (gap == 0)
                fldraw.fl_yxline(x0, y0, y1);
            else
                fldraw.fl_rectf(x0, y0, gap, y1 - y0);
            x0 += gap;
        }

        fldraw.lineStyle(lineSolid, 0);
        fldraw.fl_color(black);
    }

    override void draw()
    {
        if (needLayout())
            layout();

        if (damage() & ~damageChild)
        {
            drawBox();
            if (drawGrid_)
                drawGrid();
            drawLabel();
        }
        drawChildren();
    }

    /**
     * Calculates the grid layout and resizes/positions every child
     * widget. Called automatically on resize(); call it once yourself
     * after assigning widgets to cells or changing row/col settings.
     */
    void layout()
    {
        if (rowCount_ == 0 || colCount_ == 0) return;

        int tw = w() - fl.core.boxDw(box()) - marginLeft_ - marginRight_;
        int th = h() - fl.core.boxDh(box()) - marginTop_ - marginBottom_;

        foreach (ref col; colArray_)
            col.w_ = col.minw_;
        foreach (ref row; rowArray_)
            row.h_ = row.minh_;

        for (int r = 0; r < rowCount_; r++)
        {
            for (int c = 0; c < colCount_; c++)
            {
                Cell cel = cell(r, c);
                if (cel is null) continue;
                Widget wi = cel.widget_;
                if (wi is null || !wi.visible()) continue;
                if (cel.colspan_ == 1 && cel.w_ > colArray_[c].w_) colArray_[c].w_ = cel.w_;
                if (cel.rowspan_ == 1 && cel.h_ > rowArray_[r].h_) rowArray_[r].h_ = cel.h_;
            }
        }

        int tcwi = 0; // total column width incl. gaps
        int tcwe = 0; // total column weight
        int hcwe = 0; // highest column weight
        int icwe = 0; // index of column with highest weight

        int trhe = 0; // total row height incl. gaps
        int trwe = 0; // total row weight
        int hrwe = 0; // highest row weight
        int irwe = 0; // index of row with highest weight

        for (int c = 0; c < colCount_; c++)
        {
            tcwi += colArray_[c].w_;
            tcwe += colArray_[c].weight_;
            if (c < colCount_ - 1)
                tcwi += (colArray_[c].gap_ >= 0) ? colArray_[c].gap_ : gapCol_;
            if (colArray_[c].weight_ > hcwe)
            {
                hcwe = colArray_[c].weight_;
                icwe = c;
            }
        }

        for (int r = 0; r < rowCount_; r++)
        {
            trhe += rowArray_[r].h_;
            trwe += rowArray_[r].weight_;
            if (r < rowCount_ - 1)
                trhe += (rowArray_[r].gap_ >= 0) ? rowArray_[r].gap_ : gapRow_;
            if (rowArray_[r].weight_ > hrwe)
            {
                hrwe = rowArray_[r].weight_;
                irwe = r;
            }
        }

        // Distribute extra space to columns/rows via relative weights;
        // rounding differences land on the column/row with the highest
        // weight.
        int space = tw - tcwi;
        int addSpace = 0;
        int remaining = 0;

        if (space > 0 && tcwe > 0)
        {
            remaining = space;
            for (int c = 0; c < colCount_; c++)
            {
                if (colArray_[c].weight_ > 0)
                {
                    addSpace = cast(int)(cast(float)(space * colArray_[c].weight_) / tcwe + 0.5);
                    colArray_[c].w_ += addSpace;
                    remaining -= addSpace;
                }
            }
            if (remaining != 0)
                colArray_[icwe].w_ += remaining;
        }

        space = th - trhe;

        if (space > 0 && trwe > 0)
        {
            remaining = space;
            for (int r = 0; r < rowCount_; r++)
            {
                if (rowArray_[r].weight_ > 0)
                {
                    addSpace = cast(int)(cast(float)(space * rowArray_[r].weight_) / trwe + 0.5);
                    rowArray_[r].h_ += addSpace;
                    remaining -= addSpace;
                }
            }
            if (remaining != 0)
                rowArray_[irwe].h_ += remaining;
        }

        int x0, y0;
        y0 = y() + fl.core.boxDy(box()) + marginTop_;

        for (int r = 0; r < rowCount_; r++)
        {
            x0 = x() + fl.core.boxDx(box()) + marginLeft_;
            for (int c = 0; c < colCount_; c++)
            {
                int wx = x0;
                int wy = y0;
                Cell cel = cell(r, c);
                if (cel !is null)
                {
                    Widget wi = cel.widget_;
                    if (wi !is null && wi.visible())
                    {
                        int ww = colArray_[c].w_;
                        int wh = rowArray_[r].h_;

                        for (int i = 0; i < cel.colspan_ - 1; i++)
                        {
                            ww += (colArray_[c + i].gap_ >= 0) ? colArray_[c + i].gap_ : gapCol_;
                            ww += colArray_[c + i + 1].w_;
                        }
                        for (int i = 0; i < cel.rowspan_ - 1; i++)
                        {
                            wh += (rowArray_[r + i].gap_ >= 0) ? rowArray_[r + i].gap_ : gapRow_;
                            wh += rowArray_[r + i + 1].h_;
                        }

                        GridAlign ali = cel.align_;
                        GridAlign mask;

                        mask = gridLeft | gridRight | gridHorizontal;
                        if ((ali & mask) == 0)
                        {
                            wx += (ww - cel.w_) / 2;
                            ww = cel.w_;
                        }
                        else if ((ali & mask) == gridLeft)
                        {
                            ww = cel.w_;
                        }
                        else if ((ali & mask) == gridRight)
                        {
                            wx += ww - cel.w_;
                            ww = cel.w_;
                        }

                        mask = gridTop | gridBottom | gridVertical;
                        if ((ali & mask) == 0)
                        {
                            wy += (wh - cel.h_) / 2;
                            wh = cel.h_;
                        }
                        else if ((ali & mask) == gridTop)
                        {
                            wh = cel.h_;
                        }
                        else if ((ali & mask) == gridBottom)
                        {
                            wy += wh - cel.h_;
                            wh = cel.h_;
                        }

                        wi.resize(wx, wy, ww, wh);
                    }
                }

                x0 += colArray_[c].w_ + ((colArray_[c].gap_ >= 0) ? colArray_[c].gap_ : gapCol_);
            }

            y0 += rowArray_[r].h_ + ((rowArray_[r].gap_ >= 0) ? rowArray_[r].gap_ : gapRow_);
        }

        needLayout(false);
        redraw();
    }

    protected override void onRemove(int index)
    {
        Widget w = child(index);
        Cell c = cell(w);
        if (c !is null)
            removeCell(c.row_, c.col_);
    }

    private Cell addCell(int row, int col)
    {
        auto c = new Cell(row, col);
        auto cells = rowArray_[row].cells_;
        size_t pos = cells.length;
        foreach (i, existing; cells)
        {
            if (existing.col_ > col)
            {
                pos = i;
                break;
            }
        }
        rowArray_[row].cells_ = cells[0 .. pos] ~ c ~ cells[pos .. $];
        needLayout(true);
        return c;
    }

    private void removeCell(int row, int col)
    {
        auto cells = rowArray_[row].cells_;
        foreach (i, c; cells)
        {
            if (c.col_ == col)
            {
                rowArray_[row].cells_ = cells[0 .. i] ~ cells[i + 1 .. $];
                break;
            }
        }
        needLayout(true);
    }

    override void resize(int X, int Y, int W, int H)
    {
        oldSize_ = Rect(x(), y(), w(), h());
        resizeBoundsOnly(X, Y, W, H);
        layout();
    }

    /// Removes all cells and resets rows/cols to zero. Existing child
    /// widgets stay as children of the group (base class) but are
    /// hidden. Call layout(rows, cols, ...) again to start a new grid.
    void clearLayout()
    {
        resetFields();
        foreach (i; 0 .. children())
            child(i).hide();
        needLayout(true);
    }

    void margin(int left, int top = -1, int right = -1, int bottom = -1)
    {
        if (left >= 0) marginLeft_ = cast(short) left;
        if (top >= 0) marginTop_ = cast(short) top;
        if (right >= 0) marginRight_ = cast(short) right;
        if (bottom >= 0) marginBottom_ = cast(short) bottom;
        needLayout(true);
    }

    int marginLeft() const { return marginLeft_; }
    int marginTop() const { return marginTop_; }
    int marginRight() const { return marginRight_; }
    int marginBottom() const { return marginBottom_; }

    void gap(int rowGap, int colGap = -1)
    {
        if (rowGap >= 0) gapRow_ = cast(short) rowGap;
        if (colGap >= 0) gapCol_ = cast(short) colGap;
        needLayout(true);
    }

    int gapRow() const { return gapRow_; }
    int gapCol() const { return gapCol_; }

    /// The cell at (row, col), or null if out of bounds or unoccupied.
    Cell cell(int row, int col)
    {
        if (row < 0 || row >= rowCount_ || col < 0 || col >= colCount_) return null;
        foreach (c; rowArray_[row].cells_)
        {
            if (c.col_ > col) return null; // sorted by column: passed it
            if (c.col_ == col) return c;
        }
        return null;
    }

    /// The cell that widget is assigned to, or null if none. Prefer
    /// cell(row, col) when you already know the position -- this
    /// scans every cell in the grid.
    Cell cell(Widget widget)
    {
        foreach (ref row; rowArray_)
            foreach (c; row.cells_)
                if (c.widget_ is widget) return c;
        return null;
    }

    Cell widget(Widget wi, int row, int col, GridAlign align_ = gridFill)
    {
        return widget(wi, row, col, 1, 1, align_);
    }

    /**
     * Assigns wi to the cell at (row, col), spanning rowspan rows and
     * colspan columns. wi must already be a child of this Grid. Moves
     * wi from its old cell if it was already assigned elsewhere; if
     * the target cell already holds a different widget, that widget
     * is deassigned (but stays a child of the group).
     */
    Cell widget(Widget wi, int row, int col, int rowspan, int colspan, GridAlign align_ = gridFill)
    {
        int idx = find(wi);
        if (idx >= children()) return null;
        if (row < 0 || row > rowCount_) return null;
        if (col < 0 || col > colCount_) return null;

        Cell c = cell(row, col);
        if (c is null)
            c = addCell(row, col);

        if (c.widget_ !is wi)
        {
            Cell oc = cell(wi);
            if (oc !is null)
                removeCell(oc.row_, oc.col_);
        }

        c.widget_ = wi;
        c.align_ = align_;
        c.w_ = wi.w();
        c.h_ = wi.h();

        if (rowspan > 0) c.rowspan_ = cast(short) rowspan;
        if (colspan > 0) c.colspan_ = cast(short) colspan;

        needLayout(true);
        return c;
    }

    void colWidth(int col, int value)
    {
        if (col >= 0 && col < colCount_)
        {
            if (colArray_[col].minw_ != value)
            {
                colArray_[col].minw_ = value;
                needLayout(true);
            }
        }
    }

    void colWidth(const(int)[] values)
    {
        foreach (i, v; values)
        {
            if (i >= colCount_) break;
            if (v >= 0) colArray_[i].minw_ = v;
        }
        needLayout(true);
    }

    int colWidth(int col) const
    {
        if (col >= 0 && col < colCount_) return colArray_[col].minw_;
        return 0;
    }

    void colWeight(int col, int value)
    {
        if (col >= 0 && col < colCount_) colArray_[col].weight_ = cast(short) value;
        needLayout(true);
    }

    void colWeight(const(int)[] values)
    {
        foreach (i, v; values)
        {
            if (i >= colCount_) break;
            if (v >= 0) colArray_[i].weight_ = cast(short) v;
        }
        needLayout(true);
    }

    int colWeight(int col) const
    {
        if (col >= 0 && col < colCount_) return colArray_[col].weight_;
        return 0;
    }

    void colGap(int col, int value)
    {
        if (col >= 0 && col < colCount_) colArray_[col].gap_ = cast(short) value;
        needLayout(true);
    }

    void colGap(const(int)[] values)
    {
        foreach (i, v; values)
        {
            if (i >= colCount_) break;
            if (v >= 0) colArray_[i].gap_ = cast(short) v;
        }
        needLayout(true);
    }

    int colGap(int col) const
    {
        if (col >= 0 && col < colCount_) return colArray_[col].gap_;
        return 0;
    }

    void rowHeight(int row, int value)
    {
        if (row >= 0 && row < rowCount_) rowArray_[row].minh_ = value;
        needLayout(true);
    }

    void rowHeight(const(int)[] values)
    {
        foreach (i, v; values)
        {
            if (i >= rowCount_) break;
            if (v >= 0) rowArray_[i].minh_ = v;
        }
        needLayout(true);
    }

    int rowHeight(int row) const
    {
        if (row >= 0 && row < rowCount_) return rowArray_[row].minh_;
        return 0;
    }

    void rowWeight(int row, int value)
    {
        if (row >= 0 && row < rowCount_) rowArray_[row].weight_ = cast(short) value;
        needLayout(true);
    }

    void rowWeight(const(int)[] values)
    {
        foreach (i, v; values)
        {
            if (i >= rowCount_) break;
            if (v >= 0) rowArray_[i].weight_ = cast(short) v;
        }
        needLayout(true);
    }

    int rowWeight(int row) const
    {
        if (row >= 0 && row < rowCount_) return rowArray_[row].weight_;
        return 0;
    }

    void rowGap(int row, int value)
    {
        if (row >= 0 && row < rowCount_) rowArray_[row].gap_ = cast(short) value;
        needLayout(true);
    }

    void rowGap(const(int)[] values)
    {
        foreach (i, v; values)
        {
            if (i >= rowCount_) break;
            if (v >= 0) rowArray_[i].gap_ = cast(short) v;
        }
        needLayout(true);
    }

    int rowGap(int row) const
    {
        if (row >= 0 && row < rowCount_) return rowArray_[row].gap_;
        return 0;
    }

    int computedColWidth(int col) const { return colArray_[col].w_; }
    int computedRowHeight(int row) const { return rowArray_[row].h_; }

    void showGrid(bool set) { drawGrid_ = set; }

    void showGrid(bool set, Color col)
    {
        drawGrid_ = set;
        gridColor_ = col;
    }

    /// Dumps row/col layout info to stderr (FLTK: debug(), renamed
    /// since `debug` is a D keyword). level is currently ignored
    /// except for the "print anything at all" 0-vs-nonzero check,
    /// matching FLTK's own not-yet-implemented level scheme.
    void dumpLayout(int level = 127)
    {
        if (level <= 0) return;
        stderr.writefln("Grid.layout(%d, %d) at (%d, %d, %d, %d)",
            rowCount_, colCount_, x(), y(), w(), h());
        stderr.writefln("    margins:   (%2d, %2d, %2d, %2d)",
            marginLeft_, marginTop_, marginRight_, marginBottom_);
        stderr.writefln("       gaps:   (%2d, %2d)", gapRow_, gapCol_);
        foreach (r, ref row; rowArray_)
        {
            stderr.writefln("Row %2d: minh = %d, weight = %d, gap = %d, h = %d",
                r, row.minh_, row.weight_, row.gap_, row.h_);
            foreach (c; row.cells_)
                stderr.writefln("        Cell(%2d, %2d)", c.row_, c.col_);
        }
    }
}

unittest
{
    FlGroup.current(null);

    auto g = new Grid(0, 0, 320, 180);
    assert(g.box() == Boxtype.flatBox);
    assert(g.rows() == 0 && g.cols() == 0);
    g.end();

    FlGroup.current(null);
}

unittest
{
    // layout(rows,cols) allocates the cell grid; widget() assigns
    // children to cells, and calling layout() (no args) actually
    // positions/sizes them according to column widths/row heights
    // computed from each cell's own minimum size.
    import fl.box : Box;
    FlGroup.current(null);

    auto g = new Grid(0, 0, 300, 100);
    g.layout(1, 3, 0, 0);

    auto a = new Box(0, 0, 50, 20);
    auto b = new Box(0, 0, 80, 20);
    auto c = new Box(0, 0, 60, 20);
    g.end();

    g.widget(a, 0, 0);
    g.widget(b, 0, 1);
    g.widget(c, 0, 2);
    g.layout();

    // No weights set beyond the default (50 each, equal), and no
    // extra space (column widths sum to exactly 300 = 50+80+60+...
    // wait: columns take the widget's own width as minw, so widths
    // are exactly 50, 80, 60 with no gaps -- but they don't sum to
    // 300, so the remaining 110px is distributed proportionally by
    // weight (default 50 for all three, i.e. evenly).
    assert(a.x() == 0);
    assert(b.x() == a.x() + g.computedColWidth(0));
    assert(c.x() == b.x() + g.computedColWidth(1));
    assert(c.x() + g.computedColWidth(2) == 300);

    FlGroup.current(null);
}

unittest
{
    // Column weights control how extra space (beyond each column's
    // minimum) is distributed: a weight-0 column never grows, a
    // weight-100 column absorbs everything else evenly split among
    // the remaining weighted columns.
    import fl.box : Box;
    FlGroup.current(null);

    auto g = new Grid(0, 0, 300, 50);
    g.layout(1, 2, 0, 0);

    auto a = new Box(0, 0, 50, 20);
    auto b = new Box(0, 0, 50, 20);
    g.end();

    g.widget(a, 0, 0);
    g.widget(b, 0, 1);
    g.colWeight(0, 0);   // a's column never grows
    g.colWeight(1, 100); // all extra space goes to b's column
    g.layout();

    assert(g.computedColWidth(0) == 50); // untouched: weight 0
    assert(g.computedColWidth(1) == 250); // 50 + all 200px of slack

    FlGroup.current(null);
}

unittest
{
    // Row weights, rotated 90 degrees from the column-weight test
    // above: the row-axis distribution code (trhe/trwe/hrwe/irwe and
    // the th-trhe split) is a separately hand-transcribed mirror of
    // the column-axis code, not a shared axis-parameterized helper,
    // so it needs its own execution to catch a row/col mixup.
    import fl.box : Box;
    FlGroup.current(null);

    auto g = new Grid(0, 0, 50, 300);
    g.layout(2, 1, 0, 0);

    auto a = new Box(0, 0, 20, 20);
    auto b = new Box(0, 0, 20, 20);
    g.end();

    g.widget(a, 0, 0);
    g.widget(b, 1, 0);
    g.rowWeight(0, 0);   // a's row never grows
    g.rowWeight(1, 100); // all extra space goes to b's row
    g.layout();

    assert(g.computedRowHeight(0) == 20);  // untouched: weight 0
    assert(g.computedRowHeight(1) == 280); // 20 + all 260px of slack

    FlGroup.current(null);
}

unittest
{
    // rowspan (the row twin of the colspan test below) and vertical
    // (non-fill) alignment together, in the same fixture as the
    // gridBottom case is cheap to add alongside it.
    import fl.box : Box;
    FlGroup.current(null);

    auto g = new Grid(0, 0, 100, 200);
    g.layout(2, 1, 0, 10);
    g.rowWeight(0, 0);
    g.rowWeight(1, 0);

    auto tall = new Box(0, 0, 20, 130); // needs row0+gap+row1 to fit
    g.end();

    g.widget(tall, 0, 0, 2, 1, gridFill); // rowspan=2, colspan=1
    g.layout();

    // row0's minh is unaffected by a rowspan>1 cell (matches FLTK:
    // only rowspan==1 cells set a row's minh), so both rows default to
    // 0, and "tall" is stretched across row0+gap(10)+row1 = 10.
    assert(g.computedRowHeight(0) == 0);
    assert(g.computedRowHeight(1) == 0);
    assert(tall.h() == 10);

    FlGroup.current(null);
}

unittest
{
    // Vertical alignment: FL_GRID_BOTTOM keeps the widget's own
    // minimum height and pins it to the bottom of a taller row/cell
    // (the vertical twin of the horizontal-center test below).
    import fl.box : Box;
    FlGroup.current(null);

    auto g = new Grid(0, 0, 20, 100);
    g.layout(1, 1, 0, 0);
    g.colWeight(0, 0);
    g.rowWeight(0, 0);

    auto b = new Box(0, 0, 20, 30);
    g.end();

    g.rowHeight(0, 100); // row taller than the widget itself
    g.widget(b, 0, 0, gridBottom);
    g.layout();

    assert(g.computedRowHeight(0) == 100);
    assert(b.h() == 30);       // not stretched
    assert(b.y() == 100 - 30); // pinned to the bottom

    FlGroup.current(null);
}

unittest
{
    // colspan: a cell spanning 2 columns is sized against their
    // combined width (plus the gap between them), not just one.
    import fl.box : Box;
    FlGroup.current(null);

    auto g = new Grid(0, 0, 200, 50);
    g.layout(1, 3, 0, 10);
    g.colWeight(0, 0);
    g.colWeight(1, 0);
    g.colWeight(2, 0);

    auto wide = new Box(0, 0, 130, 20); // needs cols 0+1+gap to fit
    auto solo = new Box(0, 0, 40, 20);
    g.end();

    g.widget(wide, 0, 0, 1, 2, gridFill); // rowspan=1, colspan=2
    g.widget(solo, 0, 2);
    g.layout();

    // col0's minw is unaffected by a colspan>1 cell (matches FLTK:
    // only colspan==1 cells set a column's minw); col1 has no
    // single-column occupant either, so both default to 0 width, and
    // "wide" gets stretched/positioned across col0+gap+col1 = 0+10+0=10.
    assert(g.computedColWidth(0) == 0);
    assert(g.computedColWidth(1) == 0);
    assert(wide.w() == 10); // col0(0) + gap(10) + col1(0)
    assert(solo.x() == 0 + 0 + 10 + 0 + 10); // col0+gap+col1+gap

    FlGroup.current(null);
}

unittest
{
    // Alignment within a cell: FL_GRID_FILL (the default) stretches
    // the widget to the full cell; an explicit non-stretch alignment
    // keeps the widget's own minimum size and positions it within the
    // (larger) cell instead.
    import fl.box : Box;
    FlGroup.current(null);

    auto g = new Grid(0, 0, 200, 20);
    g.layout(1, 1, 0, 0);
    g.colWeight(0, 0); // column stays at its minimum width (100)
    g.rowWeight(0, 0);

    auto b = new Box(0, 0, 20, 20);
    g.end();

    g.colWidth(0, 100); // cell/column wider than the widget itself
    g.widget(b, 0, 0, gridCenter);
    g.layout();

    assert(g.computedColWidth(0) == 100);
    assert(b.w() == 20); // not stretched
    assert(b.x() == (100 - 20) / 2); // centered within the column

    FlGroup.current(null);
}

unittest
{
    // onRemove(): removing a child widget also detaches it from its
    // grid cell so a later widget() call can reassign that same cell.
    import fl.box : Box;
    FlGroup.current(null);

    auto g = new Grid(0, 0, 100, 100);
    g.layout(1, 1, 0, 0);

    auto a = new Box(0, 0, 10, 10);
    g.end();

    g.widget(a, 0, 0);
    assert(g.cell(0, 0) !is null);

    g.deleteChild(g.find(a));
    assert(g.cell(0, 0) is null);

    auto b = new Box(0, 0, 10, 10);
    g.add(b);
    g.widget(b, 0, 0);
    assert(g.cell(0, 0).widget() is b);

    FlGroup.current(null);
}

unittest
{
    // clearLayout(): resets rows/cols to zero and hides (but doesn't
    // delete) existing children.
    import fl.box : Box;
    FlGroup.current(null);

    auto g = new Grid(0, 0, 100, 100);
    g.layout(1, 2, 0, 0);
    auto a = new Box(0, 0, 10, 10);
    g.end();
    g.widget(a, 0, 0);
    assert(a.visible());

    g.clearLayout();
    assert(g.rows() == 0 && g.cols() == 0);
    assert(!a.visible());
    assert(g.children() == 1); // still a child, just hidden

    FlGroup.current(null);
}

unittest
{
    // resize(): the grid's own resize() override recalculates the
    // layout (unlike FlGroup's default proportional child scaling).
    import fl.box : Box;
    FlGroup.current(null);

    auto g = new Grid(0, 0, 100, 50);
    g.layout(1, 2, 0, 0);
    g.colWeight(0, 50);
    g.colWeight(1, 50);

    auto a = new Box(0, 0, 20, 20);
    auto b = new Box(0, 0, 20, 20);
    g.end();
    g.widget(a, 0, 0);
    g.widget(b, 0, 1);
    g.layout();

    g.resize(0, 0, 200, 50);
    // 160px of slack (200 - 40 combined minw) split evenly: +80 each.
    assert(g.computedColWidth(0) == 100);
    assert(g.computedColWidth(1) == 100);

    FlGroup.current(null);
}
