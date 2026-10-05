/*
 * Ported from FL/Fl_Table.H + src/Fl_Table.cxx (FLTK 1.5.0). Base class for table widgets: draws a grid of
 * cells (via the virtual drawCell() hook a subclass overrides), with
 * optional row/column headers, interactive row/column resizing,
 * scrolling, and a rectangular cell-selection cursor. Can also be used
 * as a plain container of real FLTK widgets, one per cell.
 *
 * Deviations from FLTK, all deliberate:
 *
 *  - **A genuine FLTK bug found and fixed, not faithfully
 *    replicated: `row_height(int, int)`'s off-by-one.** FLTK's
 *    `col_width(int col, int width)` grows `_colwidths` via
 *    `_colwidths->resize(col+1, width)` when `col >= now_size` -- correct,
 *    since index `col` must be valid afterward. Its near-identical
 *    twin, `row_height(int row, int height)`, does
 *    `_rowheights->resize(row, height)` -- **missing the `+1`** -- so
 *    when `row == now_size` (the common "append the next row" case),
 *    the vector doesn't grow at all, and the very next line,
 *    `(*_rowheights)[row] = height;`, indexes one past the end via
 *    `std::vector::operator[]` (no bounds check in C++, so this is
 *    silent undefined behavior, not a crash -- explaining how this
 *    survived undetected: most `std::vector` implementations
 *    over-allocate capacity beyond size, so the write frequently lands
 *    in already-owned-but-uninitialized memory rather than visibly
 *    corrupting anything). D arrays *do* bounds-check by default, so
 *    faithfully reproducing the same `resize(row, ...)` call here would
 *    turn silent C++ UB into a guaranteed `RangeError` crash on the
 *    very first row ever added to a table -- the same category of
 *    "faithful replication would be actively harmful in a memory-safe
 *    language" case `CONVENTIONS.md`'s `Fl_Text_Buffer::copy()` note
 *    documents. Fixed here (`row+1`, matching `col_width()`'s own
 *    correct pattern exactly) and logged as an `FLTK_ISSUES.md`
 *    candidate rather than silently worked around.
 *  - `TableContext` is `alias int` + manifest constants, not a closed
 *    `enum` -- FLTK declares it as a plain C `enum` but real call
 *    sites combine values with `&` (`context & (CONTEXT_ROW_HEADER|
 *    CONTEXT_COL_HEADER|CONTEXT_CELL)` in `handle()`'s `FL_DRAG` case),
 *    matching `CONVENTIONS.md`'s "open bitmask expressed as a plain C enum"
 *    rule (same treatment as `fl.tree_prefs`'s `TreeItemDrawMode`).
 *    `ResizeFlag` stays a closed `enum` -- genuinely
 *    mutually-exclusive, never combined.
 *  - **`begin()`/`end()`/`add()`/`insert()`/`remove()`/`children()`/
 *    `child()`/`array()`/`find()` all forward to the *nested* `table_`
 *    (`Fl_Scroll`) container, not `Table`'s own inherited `FlGroup`
 *    versions** -- this matches FLTK exactly (every one of these
 *    is a thin one-line forwarder to `table->...` in the real header),
 *    it's just worth calling out since it means a `Table`'s own direct
 *    `FlGroup` children are always exactly 3 (`table_`, `vscrollbar_`,
 *    `hscrollbar_`, fixed at construction) -- any FLTK widgets a
 *    caller adds via `Table.add()`/`begin()`/`end()` actually become
 *    children of the nested `table_`, not `Table` itself. Ported as
 *    `override` methods (D requires explicit `override` for a
 *    same-signature virtual method, unlike C++'s implicit non-virtual
 *    name-hiding for these -- functionally equivalent here since every
 *    caller wants the `Table`-specific forwarding behavior regardless
 *    of whether they're holding a `Table` or a `FlGroup` reference).
 *  - `isFltkContainer()` (`is_fltk_container()`) is ported exactly as
 *    written (`super.children() > 3`, i.e. `FlGroup.children()`, not the
 *    overridden `children()` above) even though careful reading shows
 *    it can structurally never be true: `Table`'s own direct `FlGroup`
 *    children are fixed at exactly 3 for the object's entire lifetime
 *    (see the previous bullet), so `> 3` never holds. This reads like
 *    a real, low-stakes dead-code bug (not called anywhere internally,
 *    `protected`, likely a holdover from an earlier architecture where
 *    widgets were added directly to `Fl_Table`'s own array) -- logged
 *    as a second `FLTK_ISSUES.md` candidate, ported faithfully
 *    rather than "fixed" with a guess at the original intent.
 *  - `_auto_drag_cb()`'s `Fl::flush()` call (forces an immediate
 *    synchronous repaint mid-drag, so autoscroll feels responsive even
 *    between normal event-loop iterations) is not ported -- `Fl::flush()`
 *    itself isn't ported anywhere in this port yet. Skipped rather than
 *    invented: the surrounding `fl.core.check()` call (already real,
 *    `Fl::check()`'s port) still pumps pending events each timer tick,
 *    so autoscroll still animates, just on the timer's own ~20ms
 *    cadence rather than a forced extra paint -- a minor smoothness
 *    difference, not a functional one.
 *  - `std::vector<int>` (`_colwidths`/`_rowheights`) become plain
 *    `int[]` arrays; the `resize(count, value)` "grow and fill, or
 *    shrink" pattern used in four places (`rows()`/`cols()`/
 *    `rowHeight()`/`colWidth()`) is a small shared private
 *    `resizeFill()` helper instead of hand-inlining the same three
 *    lines four times.
 */
module fl.table;

import fl.enumerations;
import fl.group : FlGroup;
import fl.widget : Widget;
import fl.window : Window;
import fl.scroll : Scroll;
import fl.scrollbar : Scrollbar;
import fl.slider : horSlider, vertSlider;
import fl.rect : Rect;
import fl.draw;
import fl.core;

/// Context bit flags for Table callbacks/draw_cell() -- see this
/// module's own top comment for why this is `alias int` rather than a
/// closed `enum`. Ported from `Fl_Table::TableContext`.
alias TableContext = int;

enum : TableContext
{
    contextNone      = 0,     /// no known context
    contextStartpage = 0x01,  /// before the table is redrawn
    contextEndpage   = 0x02,  /// after the table is redrawn
    contextRowHeader = 0x04,  /// drawing or event occurred in the row header
    contextColHeader = 0x08,  /// drawing or event occurred in the col header
    contextCell      = 0x10,  /// drawing or event occurred in a cell
    contextTable     = 0x20,  /// drawing or event occurred in a dead zone of table
    contextRcResize  = 0x40,  /// column or row is being resized
}

/**
 * Base class for table widgets. Subclass and override drawCell() to
 * draw cell content; row/column count, sizing, headers, resizing, and
 * scrolling are all handled here. Ported from `Fl_Table`.
 */
class Table : FlGroup
{
    private int rows_;
    private int cols_;
    private int rowHeaderW_ = 40;
    private int colHeaderH_ = 18;
    private int rowPosition_;
    private int colPosition_;

    private bool rowHeader_;
    private bool colHeader_;
    private bool rowResize_;
    private bool colResize_;

    /// True once this constructor's own body has finished. Guards the
    /// `drawCell()` call in `tableScrolled()` (see that method) against
    /// firing during construction -- see the "D also does not build up
    /// the vtable progressively" note in CONVENTIONS.md: `table_ !is null`
    /// (guarding every other override below) doesn't help here, since
    /// `table_` is already assigned by the time `tableResized()` runs.
    private bool constructed_;
    private int rowResizeMin_ = 1;
    private int colResizeMin_ = 1;

    private int redrawToprow_ = -1;
    private int redrawBotrow_ = -1;
    private int redrawLeftcol_ = -1;
    private int redrawRightcol_ = -1;
    private Color rowHeaderColor_;
    private Color colHeaderColor_;

    private int autoDrag_; // 0=off, 1=on, 2=temporarily suppressed (see autoDragCb())
    private TableContext selecting_;
    private int scrollbarSize_;
    private bool tabCellNav_;

    private int[] colwidths_;
    private int[] rowheights_;

    private Cursor lastCursor_ = Cursor.default_;

    private TableContext callbackContext_;
    private int callbackRow_;
    private int callbackCol_;

    private int resizingCol_ = -1;
    private int resizingRow_ = -1;
    private int draggingX_ = -1;
    private int draggingY_ = -1;
    private int lastRow_ = -1;

    /// Which resize boundary the mouse is over, if any. Closed set --
    /// genuinely mutually exclusive, never combined.
    protected enum ResizeFlag
    {
        resizeNone,
        resizeColLeft,
        resizeColRight,
        resizeRowAbove,
        resizeRowBelow,
    }

    protected int tableW; /// table's virtual width (in pixels)
    protected int tableH; /// table's virtual height (in pixels)
    protected int toprow; /// top row# of currently visible table on screen
    protected int botrow; /// bottom row# of currently visible table on screen
    protected int leftcol; /// left column# of currently visible table on screen
    protected int rightcol; /// right column# of currently visible table on screen

    protected int currentRow = -1; /// selection cursor's current row (-1 if none)
    protected int currentCol = -1; /// selection cursor's current column (-1 if none)
    protected int selectRow = -1; /// extended selection row (-1 if none)
    protected int selectCol = -1; /// extended selection column (-1 if none)

    protected int toprowScrollpos = -1;
    protected int leftcolScrollpos = -1;

    protected int tix, tiy, tiw, tih; /// table's inner dimension (clip region)
    protected int tox, toy, tow, toh; /// table's outer dimension
    protected int wix, wiy, wiw, wih; /// table widget's inner dimension

    protected Scroll table_; /// child Scroll container for child fltk widgets (if any)
    protected Scrollbar vscrollbar_; /// child vertical scrollbar widget
    protected Scrollbar hscrollbar_; /// child horizontal scrollbar widget

    this(int X, int Y, int W, int H, string L = null)
    {
        super(X, Y, W, H, L);
        rowHeaderColor_ = color();
        colHeaderColor_ = color();

        box(Boxtype.thinDownFrame);

        int sbs = fl.core.scrollbarSize();
        vscrollbar_ = new Scrollbar(X + W - sbs, Y, sbs, H - sbs);
        vscrollbar_.type(vertSlider);
        vscrollbar_.callback((w) { scrollCb(); });

        hscrollbar_ = new Scrollbar(X, Y + H - sbs, W, sbs);
        hscrollbar_.type(horSlider);
        hscrollbar_.callback((w) { scrollCb(); });

        table_ = new Scroll(X, Y, W, H);
        table_.box(Boxtype.noBox);
        table_.type(0); // don't show Scroll's own scrollbars -- use ours
        table_.hide(); // hidden unless children are present
        table_.end();

        tableResized();
        redraw();

        super.end(); // FlGroup's own end() -- NOT Table's own override below
        table_.begin(); // leave with fltk children getting added to the scroll

        constructed_ = true;
    }

    /// Clears the table to zero rows/cols and clears any widgets that
    /// were added with begin()/end() or add()/insert()/etc.
    override void clear()
    {
        rows(0);
        cols(0);
        table_.clear();
    }

    /// The box type drawn around the data table (default: noBox).
    void tableBox(Boxtype val)
    {
        table_.box(val);
        tableResized();
    }
    /// ditto
    Boxtype tableBox() const { return table_.box(); }

    /// Sets the number of rows in the table, and the table is redrawn.
    void rows(int val)
    {
        int oldrows = rows_;
        rows_ = val;
        int defaultH = rowheights_.length > 0 ? rowheights_[$ - 1] : 25;
        resizeFill(rowheights_, val, defaultH);
        tableResized();
        if (val >= oldrows && oldrows > botrow) {} // OPTIMIZATION: change not visible, no redraw
        else redraw();
    }
    /// Returns the number of rows in the table.
    int rows() const { return rows_; }

    /// Sets the number of columns in the table, and the table is redrawn.
    void cols(int val)
    {
        cols_ = val;
        int defaultW = colwidths_.length > 0 ? colwidths_[$ - 1] : 80;
        resizeFill(colwidths_, val, defaultW);
        tableResized();
        redraw();
    }
    /// Returns the number of columns in the table.
    int cols() const { return cols_; }

    /// Returns the range of row/column numbers for all visible and
    /// partially visible cells.
    void visibleCells(out int r1, out int r2, out int c1, out int c2) const
    {
        r1 = toprow;
        r2 = botrow;
        c1 = leftcol;
        c2 = rightcol;
    }

    /// True if someone is interactively resizing a row or column. Only
    /// meaningful from within callback().
    bool isInteractiveResize() const { return resizingRow_ != -1 || resizingCol_ != -1; }

    bool rowResize() const { return rowResize_; }
    /// Allows/disallows row resizing by the user (via the row headers --
    /// rowHeader() must also be enabled).
    void rowResize(bool flag) { rowResize_ = flag; }
    bool colResize() const { return colResize_; }
    /// Allows/disallows column resizing by the user (via the column
    /// headers -- colHeader() must also be enabled).
    void colResize(bool flag) { colResize_ = flag; }
    int colResizeMin() const { return colResizeMin_; }
    void colResizeMin(int val) { colResizeMin_ = val < 1 ? 1 : val; }
    int rowResizeMin() const { return rowResizeMin_; }
    void rowResizeMin(int val) { rowResizeMin_ = val < 1 ? 1 : val; }

    bool rowHeader() const { return rowHeader_; }
    /// Enables/disables showing the row headers; redraws if changed.
    void rowHeader(bool flag)
    {
        rowHeader_ = flag;
        tableResized();
        redraw();
    }
    bool colHeader() const { return colHeader_; }
    /// Enables/disables showing the column headers; redraws if changed.
    void colHeader(bool flag)
    {
        colHeader_ = flag;
        tableResized();
        redraw();
    }

    /// Sets the height in pixels for column headers and redraws.
    void colHeaderHeight(int height)
    {
        colHeaderH_ = height;
        tableResized();
        redraw();
    }
    int colHeaderHeight() const { return colHeaderH_; }
    /// Sets the row header width in pixels and redraws.
    void rowHeaderWidth(int width)
    {
        rowHeaderW_ = width;
        tableResized();
        redraw();
    }
    int rowHeaderWidth() const { return rowHeaderW_; }
    /// Sets the row header color and redraws.
    void rowHeaderColor(Color val) { rowHeaderColor_ = val; redraw(); }
    Color rowHeaderColor() const { return rowHeaderColor_; }
    /// Sets the column header color and redraws.
    void colHeaderColor(Color val) { colHeaderColor_ = val; redraw(); }
    Color colHeaderColor() const { return colHeaderColor_; }

    /// Sets the height of the specified row in pixels, and the table is
    /// redrawn. callback() is invoked with contextRcResize if the
    /// height actually changed and when() has whenChanged set.
    void rowHeight(int row, int height)
    {
        if (row < 0) return;
        if (row < rowheights_.length && rowheights_[row] == height) return; // no change

        // NOTE: `row + 1`, not `row` -- see this module's own top
        // comment on the real FLTK off-by-one this fixes.
        if (row >= rowheights_.length) resizeFill(rowheights_, row + 1, height);
        rowheights_[row] = height;
        tableResized();
        if (row <= botrow) redraw(); // OPTIMIZATION: only if onscreen or above

        if (callback() !is null && (when() & whenChanged) != 0)
            doCallback(contextRcResize, row, 0);
    }
    /// Returns the current height of the specified row, in pixels.
    int rowHeight(int row) const
    {
        return (row < 0 || row >= rowheights_.length) ? 0 : rowheights_[row];
    }

    /// Sets the width of the specified column in pixels, and the table
    /// is redrawn. callback() is invoked with contextRcResize if the
    /// width actually changed and when() has whenChanged set.
    void colWidth(int col, int width)
    {
        if (col < 0) return;
        if (col < colwidths_.length && colwidths_[col] == width) return; // no change

        if (col >= colwidths_.length) resizeFill(colwidths_, col + 1, width);
        colwidths_[col] = width;
        tableResized();
        if (col <= rightcol) redraw(); // OPTIMIZATION: only if onscreen or to the left

        if (callback() !is null && (when() & whenChanged) != 0)
            doCallback(contextRcResize, 0, col);
    }
    /// Returns the current width of the specified column, in pixels.
    int colWidth(int col) const
    {
        return (col < 0 || col >= colwidths_.length) ? 0 : colwidths_[col];
    }

    /// Sets the height of all rows to the same value, in pixels.
    void rowHeightAll(int height) { foreach (r; 0 .. rows()) rowHeight(r, height); }
    /// Sets the width of all columns to the same value, in pixels.
    void colWidthAll(int width) { foreach (c; 0 .. cols()) colWidth(c, width); }

    /// Sets which row should be at the top of the table (scrolling as
    /// necessary; clamped if the table can't scroll that far).
    void rowPosition(int row)
    {
        if (rowPosition_ == row) return; // OPTIMIZATION: no change, avoid redraw
        if (row < 0) row = 0;
        else if (row >= rows()) row = rows() - 1;
        if (tableH <= tih) return; // don't scroll if table smaller than window
        double newtop = rowScrollPosition(row);
        if (newtop > vscrollbar_.maximum()) newtop = vscrollbar_.maximum();
        vscrollbar_.value(newtop);
        tableScrolled();
        redraw();
        rowPosition_ = row; // HACK: override what tableScrolled() came up with
    }
    /// Sets which column should be at the left of the table.
    void colPosition(int col)
    {
        if (colPosition_ == col) return;
        if (col < 0) col = 0;
        else if (col >= cols()) col = cols() - 1;
        if (tableW <= tiw) return;
        double newleft = colScrollPosition(col);
        if (newleft > hscrollbar_.maximum()) newleft = hscrollbar_.maximum();
        hscrollbar_.value(newleft);
        tableScrolled();
        redraw();
        colPosition_ = col;
    }
    /// The current row scroll position, as a row number.
    int rowPosition() const { return rowPosition_; }
    /// The current column scroll position, as a column number.
    int colPosition() const { return colPosition_; }
    /// Deprecated alias for rowPosition(int).
    void topRow(int row) { rowPosition(row); }
    /// Deprecated alias for rowPosition().
    int topRow() const { return rowPosition(); }

    /// See if the cell at row r, column c is within the current
    /// selection rectangle.
    bool isSelected(int r, int c) const
    {
        int sLeft, sRight, sTop, sBottom;
        if (selectCol > currentCol) { sLeft = currentCol; sRight = selectCol; }
        else { sRight = currentCol; sLeft = selectCol; }
        if (selectRow > currentRow) { sTop = currentRow; sBottom = selectRow; }
        else { sBottom = currentRow; sTop = selectRow; }
        return r >= sTop && r <= sBottom && c >= sLeft && c <= sRight;
    }

    /// Gets the region of cells selected (highlighted).
    void getSelection(out int rowTop, out int colLeft, out int rowBot, out int colRight) const
    {
        if (selectCol > currentCol) { colLeft = currentCol; colRight = selectCol; }
        else { colRight = currentCol; colLeft = selectCol; }
        if (selectRow > currentRow) { rowTop = currentRow; rowBot = selectRow; }
        else { rowBot = currentRow; rowTop = selectRow; }
    }

    /// Sets the region of cells to be selected (highlighted). Use
    /// setSelection(-1,-1,-1,-1) to deselect all cells.
    void setSelection(int rowTop, int colLeft, int rowBot, int colRight)
    {
        damageZone(currentRow, currentCol, selectRow, selectCol);
        currentCol = colLeft;
        currentRow = rowTop;
        selectCol = colRight;
        selectRow = rowBot;
        damageZone(currentRow, currentCol, selectRow, selectCol);
    }

    /// Moves the selection cursor a relative number of rows/columns.
    /// If shiftselect, the selection range is extended to the new
    /// position; otherwise the cursor just moves and any previous
    /// selection is cancelled.
    int moveCursor(int R, int C, bool shiftselect)
    {
        if (selectRow == -1) R++;
        if (selectCol == -1) C++;
        R += selectRow;
        C += selectCol;
        if (R < 0) R = 0;
        if (R >= rows()) R = rows() - 1;
        if (C < 0) C = 0;
        if (C >= cols()) C = cols() - 1;
        if (R == selectRow && C == selectCol) return 0;
        damageZone(currentRow, currentCol, selectRow, selectCol, R, C);
        selectRow = R;
        selectCol = C;
        if (!shiftselect || (fl.core.eventState() & stateShift) == 0)
        {
            currentRow = R;
            currentCol = C;
        }
        if (R < toprow + 1 || R > botrow - 1) rowPosition(R);
        if (C < leftcol + 1 || C > rightcol - 1) colPosition(C);
        return 1;
    }
    /// Same as moveCursor(R, C, true).
    int moveCursor(int R, int C) { return moveCursor(R, C, true); }

    override void resize(int X, int Y, int W, int H)
    {
        super.resize(X, Y, W, H);
        tableResized();
        redraw();
    }

    //////////////////
    // Child group management -- all forward to the nested table_
    // Scroll, not Table's own inherited FlGroup behavior. See this
    // module's own top comment.
    //
    // EVERY override below is guarded on `table_ !is null`, falling
    // back to the plain `super.xxx()` (real `FlGroup`) behavior
    // otherwise. This works around a real D
    // vs. C++ construction-order hazard -- see CONVENTIONS.md's own
    // "D resolves virtual dispatch to the most-derived override from
    // the start of construction" note for the general story (the
    // mirror image of the already-documented destructor case). The
    // concrete chain that makes *every* one of these reachable during
    // `Table`'s own constructor, before `table_` exists: `FlGroup`'s
    // constructor calls `begin()` virtually -> (guarded) falls back to
    // `super.begin()`, setting `FlGroup.current_ = this` -> constructing
    // `vscrollbar_`/`hscrollbar_`/`table_` itself then each
    // auto-parents via `Widget`'s own `FlGroup.current().add(this)`,
    // dispatched virtually to *this* `Table` instance regardless of
    // `FlGroup.current()`'s static type -> `add()`'s fallback
    // `super.add(wgt)` runs `FlGroup.add()`'s *code*, but calls made
    // *from inside* that inherited method body (`insert(o, children)`)
    // still dispatch virtually against `Table`'s own vtable, reaching
    // `children()` and `insert(Widget,int)` here too, and transitively
    // `initSizes()`. Without every one of these falling back to `super`
    // during that window, constructing a `Table` segfaults on a null
    // `table_`.
    //////////////////

    /// Resets the internal array of widget sizes and positions.
    override void initSizes()
    {
        if (table_ !is null) { table_.initSizes(); table_.redraw(); }
        else super.initSizes();
    }
    /// Adds wgt (removing it from its current group, if any) to the
    /// end of the table's own child group.
    override void add(Widget wgt)
    {
        if (table_ !is null)
        {
            table_.add(wgt);
            if (table_.children() > 2) table_.show(); else table_.hide();
        }
        else
        {
            super.add(wgt);
        }
    }
    /// Inserts wgt into the table's own child group at position n.
    override void insert(Widget wgt, int n)
    {
        if (table_ !is null) table_.insert(wgt, n);
        else super.insert(wgt, n);
    }
    /// Inserts wgt into the table's own child group before w2 (appends
    /// if w2 isn't in the group).
    override void insert(Widget wgt, Widget w2)
    {
        if (table_ !is null) table_.insert(wgt, w2);
        else super.insert(wgt, w2);
    }
    /// Removes wgt from the table's own child group.
    override void remove(Widget wgt)
    {
        if (table_ !is null) table_.remove(wgt);
        else super.remove(wgt);
    }

    override void begin()
    {
        if (table_ !is null) table_.begin();
        else super.begin();
    }
    override void end()
    {
        if (table_ !is null)
        {
            table_.end();
            // HACK (matching FLTK): avoid showing the Scroll --
            // seems to erase the screen causing unnecessary flicker,
            // even with box() == noBox.
            if (table_.children() > 2) table_.show(); else table_.hide();
            FlGroup.current(cast(FlGroup) this.parent());
        }
        else
        {
            super.end();
        }
    }

    /// Pointer to the array of child widgets (of the nested container),
    /// valid only until the next add()/insert()/remove().
    override inout(Widget)[] array() inout
    {
        return table_ !is null ? table_.array() : super.array();
    }
    /// Returns the nth child widget.
    Widget child(int n) { return table_ !is null ? table_.child(n) : super.child(n); }
    /// Returns the number of child widgets (when used as a container),
    /// not counting the nested Scroll's own hidden h/v scrollbars.
    override int children() const
    {
        return table_ !is null ? table_.children() - 2 : super.children();
    }
    override int find(const(Widget) wgt) const
    {
        return table_ !is null ? table_.find(wgt) : super.find(wgt);
    }

    // CALLBACKS

    /// The row the event occurred on. Only meaningful within callback().
    int callbackRow() const { return callbackRow_; }
    /// The column the event occurred on. Only meaningful within callback().
    int callbackCol() const { return callbackCol_; }
    /// The current table context. Only meaningful within callback().
    TableContext callbackContext() const { return callbackContext_; }

    /// Calls the widget callback, saving context/row/col for
    /// callback_context()/callback_row()/callback_col() to read.
    void doCallback(TableContext context, int row, int col)
    {
        callbackContext_ = context;
        callbackRow_ = row;
        callbackCol_ = col;
        super.doCallback();
    }

    int scrollbarSize() const { return scrollbarSize_; }
    void scrollbarSize(int newSize)
    {
        if (newSize != scrollbarSize_) redraw();
        scrollbarSize_ = newSize;
    }

    /// If true, Tab navigates table cells instead of FLTK widget focus
    /// (default: false).
    void tabCellNav(bool val) { tabCellNav_ = val; }
    bool tabCellNav() const { return tabCellNav_; }

    //////////////////
    // Internal machinery
    //////////////////

    /// Returns the scroll position (in pixels) of row.
    protected long rowScrollPosition(int row)
    {
        int startrow = 0;
        long scroll = 0;
        if (toprowScrollpos != -1 && row >= toprow)
        {
            scroll = toprowScrollpos;
            startrow = toprow;
        }
        foreach (t; startrow .. row) scroll += rowHeight(t);
        return scroll;
    }
    /// Returns the scroll position (in pixels) of col.
    protected long colScrollPosition(int col)
    {
        int startcol = 0;
        long scroll = 0;
        if (leftcolScrollpos != -1 && col >= leftcol)
        {
            scroll = leftcolScrollpos;
            startcol = leftcol;
        }
        foreach (t; startcol .. col) scroll += colWidth(t);
        return scroll;
    }

    /// Returns R/C clamped to the table's known universe. Returns true
    /// if any changes were made.
    protected bool rowColClamp(TableContext context, ref int R, ref int C)
    {
        bool clamped = false;
        if (R < 0) { R = 0; clamped = true; }
        if (C < 0) { C = 0; clamped = true; }
        if (context == contextColHeader)
        {
            if (R >= rows_ && R != 0) { R = rows_ - 1; clamped = true; }
        }
        else if (context == contextRowHeader)
        {
            if (C >= cols_ && C != 0) { C = cols_ - 1; clamped = true; }
        }
        else
        {
            if (R >= rows_) { R = rows_ - 1; clamped = true; }
            if (C >= cols_) { C = cols_ - 1; clamped = true; }
        }
        return clamped;
    }

    /// Returns the (X,Y,W,H) bounding region for context.
    protected void getBounds(TableContext context, out int X, out int Y, out int W, out int H)
    {
        final switch (context)
        {
        case contextColHeader:
            X = tox; Y = wiy; W = tow; H = colHeaderHeight();
            return;
        case contextRowHeader:
            X = wix; Y = toy; W = rowHeaderWidth(); H = toh;
            return;
        case contextTable:
            X = tix; Y = tiy; W = tiw; H = tih;
            return;
        case contextNone, contextStartpage, contextEndpage, contextCell, contextRcResize:
            return; // TODO: other contexts unimplemented, matching FLTK
        }
    }

    /// Find row/col for the most recent mouse event. Returns the
    /// context, R/C, and (via resizeflag) whether the mouse is hovered
    /// over a resize boundary.
    protected TableContext cursor2rowcol(out int R, out int C, out ResizeFlag resizeflag)
    {
        R = C = 0;
        resizeflag = ResizeFlag.resizeNone;
        int X, Y, W, H;
        if (rowHeader())
        {
            getBounds(contextRowHeader, X, Y, W, H);
            if (fl.core.eventInside(X, Y, W, H))
            {
                for (R = toprow; R <= botrow; R++)
                {
                    findCell(contextRowHeader, R, 0, X, Y, W, H);
                    if (fl.core.eventY() >= Y && fl.core.eventY() < Y + H)
                    {
                        if (rowResize())
                        {
                            if (fl.core.eventY() <= Y + 3) resizeflag = ResizeFlag.resizeRowAbove;
                            if (fl.core.eventY() >= Y + H - 3) resizeflag = ResizeFlag.resizeRowBelow;
                        }
                        return contextRowHeader;
                    }
                }
                return contextNone; // in row header dead zone
            }
        }
        if (colHeader())
        {
            getBounds(contextColHeader, X, Y, W, H);
            if (fl.core.eventInside(X, Y, W, H))
            {
                for (C = leftcol; C <= rightcol; C++)
                {
                    findCell(contextColHeader, 0, C, X, Y, W, H);
                    if (fl.core.eventX() >= X && fl.core.eventX() < X + W)
                    {
                        if (colResize())
                        {
                            if (fl.core.eventX() <= X + 3) resizeflag = ResizeFlag.resizeColLeft;
                            if (fl.core.eventX() >= X + W - 3) resizeflag = ResizeFlag.resizeColRight;
                        }
                        return contextColHeader;
                    }
                }
                return contextNone; // in col header dead zone
            }
        }
        if (fl.core.eventInside(tox, toy, tow, toh))
        {
            for (R = toprow; R <= botrow; R++)
            {
                findCell(contextCell, R, C, X, Y, W, H);
                if (fl.core.eventY() < Y) break;
                if (fl.core.eventY() >= Y + H) continue;
                for (C = leftcol; C <= rightcol; C++)
                {
                    findCell(contextCell, R, C, X, Y, W, H);
                    if (fl.core.eventInside(X, Y, W, H)) return contextCell;
                }
            }
            R = C = 0;
            return contextTable;
        }
        return contextNone;
    }

    /// Find a cell's X/Y/W/H region for row R, column C. Returns 0 on
    /// success, -1 if R or C are out of range (X/Y/W/H set to zero).
    protected int findCell(TableContext context, int R, int C, out int X, out int Y, out int W, out int H)
    {
        if (rowColClamp(context, R, C))
        {
            X = Y = W = H = 0;
            return -1;
        }
        X = cast(int) colScrollPosition(C) - cast(int) hscrollbar_.value() + tix;
        Y = cast(int) rowScrollPosition(R) - cast(int) vscrollbar_.value() + tiy;
        W = colWidth(C);
        H = rowHeight(R);

        if (context == contextColHeader)
        {
            Y = wiy;
            H = colHeaderHeight();
            return 0;
        }
        if (context == contextRowHeader)
        {
            X = wix;
            W = rowHeaderWidth();
            return 0;
        }
        if (context == contextCell || context == contextTable) return 0;
        return -1; // TODO: other contexts unimplemented, matching FLTK
    }

    /// Enable automatic scroll-selection (drag selection off the
    /// table's edge autoscrolls).
    private void startAutoDrag()
    {
        if (autoDrag_) return;
        autoDrag_ = 1;
        fl.core.addTimeout(0.3, &autoDragCb);
    }
    private void stopAutoDrag()
    {
        if (!autoDrag_) return;
        fl.core.removeTimeout(&autoDragCb);
        autoDrag_ = 0;
    }
    private void autoDragCb()
    {
        int lx = fl.core.eX_;
        int ly = fl.core.eY_;
        if (selecting_ == contextColHeader) ly = y() + colHeaderHeight();
        else if (selecting_ == contextRowHeader) lx = x() + rowHeaderWidth();
        if (lx > x() + w() - 20)
        {
            fl.core.eX_ = x() + w() - 20;
            if (hscrollbar_.visible()) hscrollbar_.value(hscrollbar_.clamp(hscrollbar_.value() + 30));
            hscrollbar_.doCallback();
            draggingX_ = fl.core.eX_ - 30;
        }
        else if (lx < x() + rowHeaderWidth())
        {
            fl.core.eX_ = x() + rowHeaderWidth() + 1;
            if (hscrollbar_.visible()) hscrollbar_.value(hscrollbar_.clamp(hscrollbar_.value() - 30));
            hscrollbar_.doCallback();
            draggingX_ = fl.core.eX_ + 30;
        }
        if (ly > y() + h() - 20)
        {
            fl.core.eY_ = y() + h() - 20;
            if (vscrollbar_.visible()) vscrollbar_.value(vscrollbar_.clamp(vscrollbar_.value() + 30));
            vscrollbar_.doCallback();
            draggingY_ = fl.core.eY_ - 30;
        }
        else if (ly < y() + colHeaderHeight())
        {
            fl.core.eY_ = y() + colHeaderHeight() + 1;
            if (vscrollbar_.visible()) vscrollbar_.value(vscrollbar_.clamp(vscrollbar_.value() - 30));
            vscrollbar_.doCallback();
            draggingY_ = fl.core.eY_ + 30;
        }
        autoDrag_ = 2;
        handle(Event.drag);
        autoDrag_ = 1;
        fl.core.eX_ = lx;
        fl.core.eY_ = ly;
        fl.core.check();
        // Fl::flush() is not ported -- see this module's own top comment.
        if (fl.core.eventButtons() != 0 && autoDrag_) fl.core.addTimeout(0.05, &autoDragCb);
    }

    /// Recalculate the dimensions of the table (and affect any
    /// children). Calls FlGroup.resize()/initSizes() internally via
    /// table_.
    protected void recalcDimensions()
    {
        wix = x() + fl.core.boxDx(box()); tox = wix; tix = tox + fl.core.boxDx(table_.box());
        wiy = y() + fl.core.boxDy(box()); toy = wiy; tiy = toy + fl.core.boxDy(table_.box());
        wiw = w() - fl.core.boxDw(box()); tow = wiw; tiw = tow - fl.core.boxDw(table_.box());
        wih = h() - fl.core.boxDh(box()); toh = wih; tih = toh - fl.core.boxDh(table_.box());
        if (colHeader())
        {
            tiy += colHeaderHeight(); toy += colHeaderHeight();
            tih -= colHeaderHeight(); toh -= colHeaderHeight();
        }
        if (rowHeader())
        {
            tix += rowHeaderWidth(); tox += rowHeaderWidth();
            tiw -= rowHeaderWidth(); tow -= rowHeaderWidth();
        }
        {
            bool hidev = tableH <= tih;
            bool hideh = tableW <= tiw;
            int scrollsize = scrollbarSize_ ? scrollbarSize_ : fl.core.scrollbarSize();
            if (!hideh && hidev) hidev = (tableH - tih + scrollsize) <= 0;
            if (!hidev && hideh) hideh = (tableW - tiw + scrollsize) <= 0;
            if (hidev) vscrollbar_.hide();
            else { vscrollbar_.show(); tiw -= scrollsize; tow -= scrollsize; }
            if (hideh) hscrollbar_.hide();
            else { hscrollbar_.show(); tih -= scrollsize; toh -= scrollsize; }
        }
        table_.resize(tox, toy, tow, toh);
        table_.initSizes();
    }

    /// Recalculate internals after a scroll (table has been scrolled
    /// or resized). Assumes ti[xywh] is already up to date. Does not
    /// redraw().
    protected void tableScrolled()
    {
        int yy, row;
        int voff = cast(int) vscrollbar_.value();
        for (row = yy = 0; row < rows_; row++)
        {
            yy += rowHeight(row);
            if (yy > voff) { yy -= rowHeight(row); break; }
        }
        rowPosition_ = toprow = row >= rows_ ? row - 1 : row;
        toprowScrollpos = yy;
        voff = cast(int) vscrollbar_.value() + tih;
        for (; row < rows_; row++)
        {
            yy += rowHeight(row);
            if (yy >= voff) break;
        }
        botrow = row >= rows_ ? row - 1 : row;

        int xx, col;
        int hoff = cast(int) hscrollbar_.value();
        for (col = xx = 0; col < cols_; col++)
        {
            xx += colWidth(col);
            if (xx > hoff) { xx -= colWidth(col); break; }
        }
        colPosition_ = leftcol = col >= cols_ ? col - 1 : col;
        leftcolScrollpos = xx;
        hoff = cast(int) hscrollbar_.value() + tiw;
        for (; col < cols_; col++)
        {
            xx += colWidth(col);
            if (xx >= hoff) break;
        }
        rightcol = col >= cols_ ? col - 1 : col;

        // Skipped during construction: FLTK's own call here
        // (Fl_Table::table_scrolled(), src/Fl_Table.cxx) is a genuine
        // no-op the first time, since C++'s vtable still points at
        // Fl_Table's own empty draw_cell() base implementation while
        // Fl_Table's own constructor is still running -- a subclass's
        // real override is never reached until the subclass's own
        // constructor body starts. D has no such staging (the vtable
        // is the most-derived class's from the moment of allocation),
        // so the identical call here would reach a subclass's real
        // drawCell() override before that subclass has initialized
        // any of its own fields -- a real
        // SIGSEGV in source/examples/table_spreadsheet.d's own
        // Spreadsheet.drawCell(), called via this exact path from
        // Table's own constructor before Spreadsheet's had a chance
        // to run. See `constructed_`'s own doc comment.
        if (constructed_)
            drawCell(contextRcResize, 0, 0, 0, 0, 0, 0); // tell children to scroll
    }

    /// Call after the table was resized: recalculates dimensions and
    /// scrollbar sizes. Does NOT redraw() -- left to the caller.
    protected void tableResized()
    {
        tableH = cast(int) rowScrollPosition(rows());
        tableW = cast(int) colScrollPosition(cols());
        recalcDimensions();
        {
            double vscrolltab = (tableH == 0 || tih > tableH) ? 1.0 : cast(double) tih / tableH;
            double hscrolltab = (tableW == 0 || tiw > tableW) ? 1.0 : cast(double) tiw / tableW;
            int scrollsize = scrollbarSize_ ? scrollbarSize_ : fl.core.scrollbarSize();
            vscrollbar_.range(0, tableH - tih);
            vscrollbar_.precision(10);
            vscrollbar_.sliderSize(vscrolltab);
            vscrollbar_.resize(wix + wiw - scrollsize, wiy, scrollsize,
                wih - (hscrollbar_.visible() ? scrollsize : 0));
            vscrollbar_.value(vscrollbar_.clamp(vscrollbar_.value()));
            hscrollbar_.range(0, tableW - tiw);
            hscrollbar_.precision(10);
            hscrollbar_.sliderSize(hscrolltab);
            hscrollbar_.resize(wix, wiy + wih - scrollsize,
                wiw - (vscrollbar_.visible() ? scrollsize : 0), scrollsize);
            hscrollbar_.value(hscrollbar_.clamp(hscrollbar_.value()));
        }
        super.initSizes();
        tableScrolled();
        // DO *NOT* REDRAW -- LEAVE THIS UP TO THE CALLER
    }

    private void scrollCb()
    {
        recalcDimensions();
        tableScrolled();
        redraw();
    }

    /// Changes the mouse cursor to newcursor, if different from the
    /// last cursor set.
    protected void changeCursor(Cursor newcursor)
    {
        if (newcursor != lastCursor_)
        {
            if (window() !is null) window().cursor(newcursor);
            lastCursor_ = newcursor;
        }
    }

    /// Sets the damage zone to the specified row/col range (extending
    /// any previously defined range) and schedules a partial redraw.
    protected void redrawRange(int topRow, int botRow, int leftCol, int rightCol)
    {
        if (redrawToprow_ == -1)
        {
            redrawToprow_ = topRow;
            redrawBotrow_ = botRow;
            redrawLeftcol_ = leftCol;
            redrawRightcol_ = rightCol;
        }
        else
        {
            if (topRow < redrawToprow_) redrawToprow_ = topRow;
            if (botRow > redrawBotrow_) redrawBotrow_ = botRow;
            if (leftCol < redrawLeftcol_) redrawLeftcol_ = leftCol;
            if (rightCol > redrawRightcol_) redrawRightcol_ = rightCol;
        }
        damage(damageChild);
    }

    /// Sets the damage zone to the bounding box of the two given
    /// (r1,c1)/(r2,c2) corners (and optionally a third), then calls
    /// redrawRange().
    protected void damageZone(int r1, int c1, int r2, int c2, int r3 = 0, int c3 = 0)
    {
        int R1 = r1, C1 = c1;
        int R2 = r2, C2 = c2;
        if (r1 > R2) R2 = r1;
        if (r2 < R1) R1 = r2;
        if (r3 > R2) R2 = r3;
        if (r3 < R1) R1 = r3;
        if (c1 > C2) C2 = c1;
        if (c2 < C1) C1 = c2;
        if (c3 > C2) C2 = c3;
        if (c3 < C1) C1 = c3;
        if (R1 < 0)
        {
            if (R2 < 0) return;
            R1 = 0;
        }
        if (C1 < 0)
        {
            if (C2 < 0) return;
            C1 = 0;
        }
        if (R1 < toprow) R1 = toprow;
        if (R2 > botrow) R2 = botrow;
        if (C1 < leftcol) C1 = leftcol;
        if (C2 > rightcol) C2 = rightcol;
        redrawRange(R1, R2, C1, C2);
    }

    /// Draw a single cell (finds its bounds, then calls drawCell()).
    private void redrawCell(TableContext context, int r, int c)
    {
        if (r < 0 || c < 0) return;
        int X, Y, W, H;
        findCell(context, r, c, X, Y, W, H);
        drawCell(context, r, c, X, Y, W, H);
    }

    /// Does the table contain any child fltk widgets? Ported verbatim
    /// from `is_fltk_container()` -- see this module's own top comment
    /// on why this reads like dead code (structurally always false)
    /// rather than something worth "fixing" with a guess.
    protected bool isFltkContainer() const { return super.children() > 3; }

    /**
     * Subclass should override this to draw cell/header content. Called
     * once per (potentially or fully) visible cell whenever the table
     * redraws. See FLTK's own extensive doc comment (`Fl_Table.H`)
     * for the full contract of each TableContext value.
     */
    protected void drawCell(TableContext context, int R = 0, int C = 0, int X = 0, int Y = 0, int W = 0, int H = 0)
    {
    }

    override int handle(Event e)
    {
        int ret = super.handle(e);
        int R, C;
        ResizeFlag resizeflag;
        TableContext context = cursor2rowcol(R, C, resizeflag);
        if (ret != 0)
        {
            if (fl.core.eventInside(hscrollbar_) || fl.core.eventInside(vscrollbar_)) return 1;
            if (context != contextRowHeader && context != contextColHeader
                && fl.core.focus() !is this && contains(fl.core.focus()))
                return 1;
        }
        int eventButton = fl.core.eventButton();
        int eventClicks = fl.core.eventClicks();
        int eventX = fl.core.eventX();
        int eventY = fl.core.eventY();
        int eventKey = fl.core.eventKey();
        auto eventState = fl.core.eventState();
        Widget focusWidget = fl.core.focus();

        switch (e)
        {
        case Event.push:
            if (eventButton == leftMouse && eventClicks == 0)
            {
                if (focusWidget is this)
                {
                    takeFocus();
                    doCallback(contextTable, -1, -1);
                    ret = 1;
                }
                damageZone(currentRow, currentCol, selectRow, selectCol, R, C);
                if (context == contextCell)
                {
                    currentRow = selectRow = R;
                    currentCol = selectCol = C;
                    selecting_ = contextCell;
                }
                else if (resizeflag == ResizeFlag.resizeNone)
                {
                    currentRow = selectRow = -1;
                    currentCol = selectCol = -1;
                }
            }
            if (callback() !is null && resizeflag == ResizeFlag.resizeNone)
                doCallback(context, R, C);

            if (context == contextCell)
            {
                ret = 1;
            }
            else if (context == contextNone)
            {
                if (eventButton == leftMouse && eventX < x() + rowHeaderWidth())
                {
                    currentCol = 0;
                    selectCol = cols() - 1;
                    currentRow = 0;
                    selectRow = rows() - 1;
                    damageZone(currentRow, currentCol, selectRow, selectCol);
                    ret = 1;
                }
            }
            else if (context == contextColHeader)
            {
                if (eventButton == leftMouse)
                {
                    if (resizeflag != ResizeFlag.resizeNone)
                    {
                        resizingCol_ = resizeflag == ResizeFlag.resizeColLeft ? C - 1 : C;
                        resizingRow_ = -1;
                        draggingX_ = eventX;
                        ret = 1;
                    }
                    else
                    {
                        if (focusWidget !is this && contains(focusWidget)) return 0;
                        currentCol = selectCol = C;
                        currentRow = 0;
                        selectRow = rows() - 1;
                        selecting_ = contextColHeader;
                        damageZone(currentRow, currentCol, selectRow, selectCol);
                        ret = 1;
                    }
                }
            }
            else if (context == contextRowHeader)
            {
                if (eventButton == leftMouse)
                {
                    if (resizeflag != ResizeFlag.resizeNone)
                    {
                        resizingRow_ = resizeflag == ResizeFlag.resizeRowAbove ? R - 1 : R;
                        resizingCol_ = -1;
                        draggingY_ = eventY;
                        ret = 1;
                    }
                    else
                    {
                        if (focusWidget !is this && contains(focusWidget)) return 0;
                        currentRow = selectRow = R;
                        currentCol = 0;
                        selectCol = cols() - 1;
                        selecting_ = contextRowHeader;
                        damageZone(currentRow, currentCol, selectRow, selectCol);
                        ret = 1;
                    }
                }
            }
            else
            {
                ret = 0;
            }
            lastRow_ = R;
            break;

        case Event.drag:
            if (autoDrag_ == 1) { ret = 1; break; }
            if (resizingCol_ > -1)
            {
                int offset = draggingX_ - eventX;
                int newW = colWidth(resizingCol_) - offset;
                if (newW < colResizeMin_) newW = colResizeMin_;
                colWidth(resizingCol_, newW);
                draggingX_ = eventX;
                tableResized();
                redraw();
                changeCursor(Cursor.we);
                ret = 1;
                if (callback() !is null && (when() & whenChanged) != 0) doCallback(contextRcResize, R, C);
            }
            else if (resizingRow_ > -1)
            {
                int offset = draggingY_ - eventY;
                int newH = rowHeight(resizingRow_) - offset;
                if (newH < rowResizeMin_) newH = rowResizeMin_;
                rowHeight(resizingRow_, newH);
                draggingY_ = eventY;
                tableResized();
                redraw();
                changeCursor(Cursor.ns);
                ret = 1;
                if (callback() !is null && (when() & whenChanged) != 0) doCallback(contextRcResize, R, C);
            }
            else
            {
                if (eventButton == leftMouse && selecting_ == contextCell && context == contextCell)
                {
                    if (eventClicks) break;
                    if (selectRow != R || selectCol != C) damageZone(currentRow, currentCol, selectRow, selectCol, R, C);
                    selectRow = R;
                    selectCol = C;
                    ret = 1;
                }
                else if (eventButton == leftMouse && selecting_ == contextRowHeader
                    && (context & (contextRowHeader | contextColHeader | contextCell)) != 0)
                {
                    if (selectRow != R) damageZone(currentRow, currentCol, selectRow, selectCol, R, C);
                    selectRow = R;
                    ret = 1;
                }
                else if (eventButton == leftMouse && selecting_ == contextColHeader
                    && (context & (contextRowHeader | contextColHeader | contextCell)) != 0)
                {
                    if (selectCol != C) damageZone(currentRow, currentCol, selectRow, selectCol, R, C);
                    selectCol = C;
                    ret = 1;
                }
            }
            if (resizingRow_ < 0 && resizingCol_ < 0 && autoDrag_ == 0
                && (eventX > x() + w() - 20 || eventX < x() + rowHeaderWidth()
                    || eventY > y() + h() - 20 || eventY < y() + colHeaderHeight()))
                startAutoDrag();
            break;

        case Event.release:
            stopAutoDrag();
            if (context == contextRowHeader || context == contextColHeader
                || context == contextCell || context == contextTable)
            {
                if (resizingCol_ == -1 && resizingRow_ == -1 && callback() !is null
                    && (when() & whenRelease) != 0 && lastRow_ == R)
                    doCallback(context, R, C);
            }
            if (eventButton == leftMouse)
            {
                changeCursor(Cursor.default_);
                resizingCol_ = -1;
                resizingRow_ = -1;
                ret = 1;
            }
            break;

        case Event.move:
            if (context == contextColHeader && resizeflag != ResizeFlag.resizeNone)
                changeCursor(Cursor.we);
            else if (context == contextRowHeader && resizeflag != ResizeFlag.resizeNone)
                changeCursor(Cursor.ns);
            else
                changeCursor(Cursor.default_);
            ret = 1;
            break;

        case Event.enter:
            if (ret == 0) takeFocus();
            ret = 1;
            goto case Event.leave;

        case Event.leave:
            if (resizeflag != ResizeFlag.resizeNone) ret = 1;
            if (e == Event.leave)
            {
                stopAutoDrag();
                changeCursor(Cursor.default_);
            }
            break;

        case Event.focus:
            fl.core.focus(this);
            goto case Event.unfocus;

        case Event.unfocus:
            stopAutoDrag();
            ret = 1;
            break;

        case Event.keyDown:
        {
            ret = 0;
            int isRow = selectRow;
            int isCol = selectCol;
            switch (eventKey)
            {
            case home: ret = moveCursor(0, -1_000_000); break;
            case fl.enumerations.end: ret = moveCursor(0, 1_000_000); break;
            case pageUp: ret = moveCursor(-(botrow - toprow - 1), 0); break;
            case pageDown: ret = moveCursor(botrow - toprow - 1, 0); break;
            case left: ret = moveCursor(0, -1); break;
            case right: ret = moveCursor(0, 1); break;
            case up: ret = moveCursor(-1, 0); break;
            case down: ret = moveCursor(1, 0); break;
            case tab:
                if (!tabCellNav()) break; // not navigating cells? let fltk handle it
                if ((eventState & stateShift) != 0) ret = moveCursor(0, -1, false);
                else ret = moveCursor(0, 1, false);
                break;
            default:
                break;
            }
            if (ret != 0 && fl.core.focus() !is this)
            {
                doCallback(contextTable, -1, -1);
                takeFocus();
            }
            if (callback() !is null
                && ((ret == 0 && (when() & whenNotChanged) != 0) || isRow != selectRow || isCol != selectCol))
            {
                doCallback(contextCell, selectRow, selectCol);
                ret = 1;
            }
            break;
        }

        default:
            changeCursor(Cursor.default_);
            break;
        }
        return ret;
    }

    override void draw()
    {
        int scrollsize = scrollbarSize_ ? scrollbarSize_ : fl.core.scrollbarSize();
        if ((vscrollbar_ !is null && scrollsize != vscrollbar_.w())
            || (hscrollbar_ !is null && scrollsize != hscrollbar_.h()))
            tableResized();

        drawCell(contextStartpage, 0, 0, tix, tiy, tiw, tih);

        pushClip(wix, wiy, wiw, wih);
        super.draw(); // FlGroup's own box+label+children sweep
        popClip();

        drawBox(box(), x(), y(), w(), h(), color());

        if (!table_.visible())
        {
            if ((damage() & damageAll) != 0 || (damage() & damageChild) != 0)
                drawBox(table_.box(), tox, toy, tow, toh, table_.color());
        }

        pushClip(wix, wiy, wiw, wih);
        {
            if ((damage() & damageAll) == 0 && redrawLeftcol_ != -1)
            {
                pushClip(tix, tiy, tiw, tih);
                foreach (c; redrawLeftcol_ .. redrawRightcol_ + 1)
                    foreach (r; redrawToprow_ .. redrawBotrow_ + 1)
                        redrawCell(contextCell, r, c);
                popClip();
            }
            if ((damage() & damageAll) != 0)
            {
                int X, Y, W, H;
                if (rowHeader())
                {
                    getBounds(contextRowHeader, X, Y, W, H);
                    pushClip(X, Y, W, H);
                    foreach (r; toprow .. botrow + 1) redrawCell(contextRowHeader, r, 0);
                    popClip();
                }
                if (colHeader())
                {
                    getBounds(contextColHeader, X, Y, W, H);
                    pushClip(X, Y, W, H);
                    foreach (c; leftcol .. rightcol + 1) redrawCell(contextColHeader, 0, c);
                    popClip();
                }
                pushClip(tix, tiy, tiw, tih);
                foreach (r; toprow .. botrow + 1)
                    foreach (c; leftcol .. rightcol + 1)
                        redrawCell(contextCell, r, c);
                popClip();

                if (rowHeader() && colHeader())
                    fl_rectf(wix, wiy, rowHeaderWidth(), colHeaderHeight(), color());

                if (table_.box() != Boxtype.noBox)
                {
                    if (colHeader())
                        fl_rectf(tox, wiy, fl.core.boxDx(table_.box()), colHeaderHeight(), color());
                    if (rowHeader())
                        fl_rectf(wix, toy, rowHeaderWidth(), fl.core.boxDx(table_.box()), color());
                }

                if (tableW < tiw)
                {
                    fl_rectf(tix + tableW, tiy, tiw - tableW, tih, color());
                    if (colHeader())
                        fl_rectf(tix + tableW, wiy,
                            tiw - tableW + fl.core.boxDw(table_.box()) - fl.core.boxDx(table_.box()),
                            colHeaderHeight(), color());
                }
                if (tableH < tih)
                {
                    fl_rectf(tix, tiy + tableH, tiw, tih - tableH, color());
                    if (rowHeader())
                        fl_rectf(wix, tiy + tableH, rowHeaderWidth(),
                            (wiy + wih) - (tiy + tableH) - (hscrollbar_.visible() ? scrollsize : 0),
                            color());
                }
            }
            if (vscrollbar_.visible() && hscrollbar_.visible())
                fl_rectf(vscrollbar_.x(), hscrollbar_.y(), vscrollbar_.w(), hscrollbar_.h(), color());

            drawCell(contextEndpage, 0, 0, tix, tiy, tiw, tih);

            redrawLeftcol_ = redrawRightcol_ = redrawToprow_ = redrawBotrow_ = -1;
        }
        popClip();
    }
}

/// Grows or shrinks arr to newLen elements. New elements (on growth)
/// are set to fillValue; existing elements are left untouched.
/// Ported from the `std::vector<int>::resize(count, value)` pattern
/// FLTK uses in four places (rows()/cols()/rowHeight()/colWidth()).
private void resizeFill(ref int[] arr, size_t newLen, int fillValue)
{
    auto oldLen = arr.length;
    arr.length = newLen;
    if (newLen > oldLen) arr[oldLen .. newLen] = fillValue;
}

// ===========================================================================
// Unit tests -- pure geometry/state logic, safe headless (no display
// needed: rows()/cols()/rowHeight()/colWidth()/findCell()/moveCursor()
// etc. are plain arithmetic and array bookkeeping). Drawing itself
// needs a live X display, same as every other widget-drawing code in
// this port -- not exercised here.
// ===========================================================================

unittest
{
    // rows()/cols() growth with correct default height/width carried
    // forward from the last existing row/col (matching FLTK's own
    // "row_size() > 0 ? _rowheights->back() : 25" default rule).
    import fl.group : FlGroup;

    FlGroup.current(null);
    auto t = new Table(0, 0, 200, 200);
    FlGroup.current(null);

    assert(t.rows() == 0);
    assert(t.cols() == 0);

    t.rows(3);
    assert(t.rows() == 3);
    assert(t.rowHeight(0) == 25); // first-ever default
    assert(t.rowHeight(2) == 25);

    t.rowHeight(1, 40);
    t.rows(5); // grow again -- new rows carry the *last* row's height
    assert(t.rowHeight(4) == 25); // rowHeight(2)'s height (last before growth), unaffected by row 1's override
    assert(t.rowHeight(1) == 40); // untouched by the regrow

    t.cols(2);
    assert(t.colWidth(0) == 80); // first-ever default
    t.colWidth(0, 120);
    t.cols(4);
    assert(t.colWidth(1) == 80); // second col kept its original default
    assert(t.colWidth(3) == 80); // new cols carry colWidth(1)'s value (80), the last one before growth

    fl.core.resetForTest();
}

unittest
{
    // Regression test for the row_height() off-by-one this port fixes
    // relative to FLTK (see this module's own top comment and the
    // FLTK_ISSUES.md entry) -- appending a row one past the
    // current count must not crash (RangeError) and must actually
    // store the height.
    import fl.group : FlGroup;

    FlGroup.current(null);
    auto t = new Table(0, 0, 200, 200);
    FlGroup.current(null);

    t.rows(3);
    t.rowHeight(3, 99); // one past the current row count -- the exact FLTK bug case
    assert(t.rowHeight(3) == 99);
    t.rowHeight(10, 50); // further out still
    assert(t.rowHeight(10) == 50);
    // The gap (rows 4-9) is filled with the *new* height being set for
    // row 10 (matching std::vector::resize(count, value)'s own
    // fill-every-new-element-with-value semantics -- not the original
    // per-row default from rows(3)).
    assert(t.rowHeight(9) == 50);
    assert(t.rowHeight(4) == 50);

    // colWidth() never had the bug, but exercise the same append case
    // for symmetry.
    t.cols(2);
    t.colWidth(2, 150);
    assert(t.colWidth(2) == 150);

    fl.core.resetForTest();
}

unittest
{
    // rowHeightAll()/colWidthAll() convenience setters.
    import fl.group : FlGroup;

    FlGroup.current(null);
    auto t = new Table(0, 0, 200, 200);
    FlGroup.current(null);

    t.rows(3);
    t.cols(3);
    t.rowHeightAll(30);
    t.colWidthAll(100);
    foreach (r; 0 .. 3) assert(t.rowHeight(r) == 30);
    foreach (c; 0 .. 3) assert(t.colWidth(c) == 100);

    fl.core.resetForTest();
}

unittest
{
    // rowColClamp(): clamps R/C into [0, rows()-1]/[0, cols()-1] for
    // the general (cell) context, but allows row headers to draw even
    // with R==0 and no rows (and similarly for col headers/C==0).
    import fl.group : FlGroup;

    FlGroup.current(null);
    auto t = new Table(0, 0, 200, 200);
    FlGroup.current(null);

    t.rows(5);
    t.cols(3);

    int R = 10, C = 10;
    assert(t.rowColClamp(contextCell, R, C) == true);
    assert(R == 4 && C == 2); // clamped to rows()-1/cols()-1

    R = -1; C = -1;
    assert(t.rowColClamp(contextCell, R, C) == true);
    assert(R == 0 && C == 0);

    R = 0; C = 0;
    assert(t.rowColClamp(contextCell, R, C) == false); // already in range

    fl.core.resetForTest();
}

unittest
{
    // findCell(): basic cell geometry with no headers, no scrolling.
    import fl.group : FlGroup;

    FlGroup.current(null);
    auto t = new Table(0, 0, 200, 200);
    FlGroup.current(null);

    t.rows(3);
    t.cols(3);
    t.rowHeightAll(20);
    t.colWidthAll(50);

    int X, Y, W, H;
    assert(t.findCell(contextCell, 0, 0, X, Y, W, H) == 0);
    assert(W == 50 && H == 20);
    assert(t.findCell(contextCell, 1, 1, X, Y, W, H) == 0);
    // Cell (1,1) starts 50px right and 20px down from (0,0), offset by
    // the table's own inner origin (tix/tiy).
    assert(X == t.tix + 50);
    assert(Y == t.tiy + 20);

    // Out-of-range R/C: error return, XYWH zeroed.
    assert(t.findCell(contextCell, 99, 99, X, Y, W, H) == -1);
    assert(X == 0 && Y == 0 && W == 0 && H == 0);

    fl.core.resetForTest();
}

unittest
{
    // isSelected()/getSelection()/setSelection() -- the rectangular
    // cell-selection cursor.
    import fl.group : FlGroup;

    FlGroup.current(null);
    auto t = new Table(0, 0, 200, 200);
    FlGroup.current(null);

    t.rows(10);
    t.cols(10);

    t.setSelection(2, 3, 5, 7); // rowTop=2 colLeft=3 rowBot=5 colRight=7
    assert(t.isSelected(3, 4));
    assert(t.isSelected(2, 3)); // top-left corner
    assert(t.isSelected(5, 7)); // bottom-right corner
    assert(!t.isSelected(1, 4)); // above the range
    assert(!t.isSelected(6, 4)); // below the range
    assert(!t.isSelected(3, 2)); // left of the range
    assert(!t.isSelected(3, 8)); // right of the range

    int rowTop, colLeft, rowBot, colRight;
    t.getSelection(rowTop, colLeft, rowBot, colRight);
    assert(rowTop == 2 && colLeft == 3 && rowBot == 5 && colRight == 7);

    t.setSelection(-1, -1, -1, -1); // deselect all
    assert(!t.isSelected(3, 4));

    fl.core.resetForTest();
}

unittest
{
    // moveCursor(): relative cursor movement, clamped to the table's
    // row/col range.
    import fl.group : FlGroup;

    FlGroup.current(null);
    auto t = new Table(0, 0, 200, 200);
    FlGroup.current(null);

    t.rows(10);
    t.cols(10);

    assert(t.moveCursor(0, 0, false) == 1); // first move: (-1,-1) + (0+1,0+1) = (0,0)
    assert(t.currentRow == 0 && t.currentCol == 0);

    assert(t.moveCursor(2, 3, false) == 1);
    assert(t.currentRow == 2 && t.currentCol == 3);

    // Clamped at the top-left edge.
    assert(t.moveCursor(-100, -100, false) == 1);
    assert(t.currentRow == 0 && t.currentCol == 0);

    // Clamped at the bottom-right edge.
    assert(t.moveCursor(100, 100, false) == 1);
    assert(t.currentRow == 9 && t.currentCol == 9);

    // No-op move (already there) returns 0.
    assert(t.moveCursor(0, 0, false) == 0);

    fl.core.resetForTest();
}
