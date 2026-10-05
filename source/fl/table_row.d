/*
 * Ported from FL/Fl_Table_Row.H + src/Fl_Table_Row.cxx (FLTK 1.5.0). A row-selection specialization of Table --
 * click/drag/Ctrl/Shift select whole rows, similar to a Browser with
 * columns. Still needs a subclass to override drawCell() for actual
 * cell content, same as Table itself.
 *
 * Deviations from FLTK, all deliberate:
 *
 *  - **`type(TableRowSelectMode)`/`type() const` are renamed
 *    `selectMode(TableRowSelectMode)`/`selectMode()`.** FLTK
 *    reuses the generic `Fl_Widget::type()`/`type(uchar)` name for an
 *    unrelated concept (which row-selection mode is active) -- legal
 *    in C++ via method hiding (any derived redeclaration of a name
 *    hides every base overload of that name, so `Fl_Table_Row`'s
 *    `type(TableRowSelectMode)` silently replaces `Fl_Widget::type()`
 *    entirely for `Fl_Table_Row` objects). D has no equivalent
 *    mechanism for two same-arity overloads that differ only in
 *    return type (`ubyte type() const` vs. `TableRowSelectMode
 *    type() const`) -- the same class of conflict `fl.scrollbar`'s own
 *    top comment documents for `Fl_Scrollbar::value()` vs.
 *    `Fl_Slider::value()`. Unlike that case, there's no reason to
 *    preserve the `type()` name here specifically (nothing about
 *    `Fl_Widget::type()`'s own byte is meaningful for a `TableRow`),
 *    so this port just uses a clearer, non-colliding name instead of
 *    an `alias`-based workaround.
 *  - **`rows()` (the getter) needs an explicit `alias rows = Table.rows;`**,
 *    matching FLTK's own redundant-looking `int rows() {
 *    return(Fl_Table::rows()); }` forwarder line for line, just spelled
 *    differently: it turns out D shares C++'s "any `override` of a name
 *    hides every other-signature overload of that name unless
 *    explicitly re-exposed" behavior here too (confirmed by
 *    compilation, not assumed) -- so `override void rows(int val)`
 *    alone genuinely does hide the inherited 0-arg `Table.rows()`
 *    getter, exactly like FLTK's own C++ method-hiding rule.
 *    Same underlying mechanism as `fl.scrollbar`'s `alias value =
 *    Slider.value;`.
 */
module fl.table_row;

import fl.enumerations;
import fl.table;
import fl.core;

/// Row selection behavior. Ported from `Fl_Table_Row::TableRowSelectMode`.
enum TableRowSelectMode
{
    selectNone, /// no selection allowed
    selectSingle, /// single row selection
    selectMulti, /// multiple row selection (default)
}

/**
 * A Table with row-selection behavior -- similar to a Browser with
 * columns. Subclass and override drawCell() to provide cell content,
 * same as Table itself. Ported from `Fl_Table_Row`.
 */
class TableRow : Table
{
    private ubyte[] rowselect_;

    private bool draggingSelect_;
    private int lastRow_ = -1;
    private int lastY_ = -1;
    private int lastPushX_ = -1;
    private int lastPushY_ = -1;

    private TableRowSelectMode selectmode_ = TableRowSelectMode.selectMulti;

    /// Creates an empty table with no rows or columns, headers and
    /// row/column resize disabled.
    this(int X, int Y, int W, int H, string L = null)
    {
        super(X, Y, W, H, L);
    }

    /// Brings Table's own 0-arg `rows()` getter into this class's
    /// overload set -- D, like C++, treats a same-named `override`
    /// below as hiding *every* base overload of that name unless
    /// explicitly re-exposed (this module's own top comment already
    /// covers the *reverse* case, `Fl_Widget::type()`'s getter, for
    /// context -- this one bit even though D's own overload rules
    /// aren't identical to C++'s method-hiding rules in general).
    alias rows = Table.rows;

    /// Sets the number of rows. Ordering matters (matching FLTK's
    /// own PR #1187 fix): enlarge the selection array *before*
    /// Table.rows() (so any redraw it triggers sees a correctly-sized
    /// array), shrink it *after*.
    override void rows(int val)
    {
        if (val > rowselect_.length) rowselect_.length = val; // enlarge (new entries default to 0)
        super.rows(val);
        if (val < rowselect_.length) rowselect_.length = val; // shrink
    }

    /// Sets the table's row-selection mode.
    void selectMode(TableRowSelectMode val)
    {
        selectmode_ = val;
        final switch (val)
        {
        case TableRowSelectMode.selectNone:
            foreach (ref sel; rowselect_) sel = 0;
            redraw();
            break;
        case TableRowSelectMode.selectSingle:
        {
            int count = 0;
            foreach (ref sel; rowselect_)
                if (sel && ++count > 1) sel = 0; // only one allowed
            redraw();
            break;
        }
        case TableRowSelectMode.selectMulti:
            break;
        }
    }
    /// Gets the table's row-selection mode.
    TableRowSelectMode selectMode() const { return selectmode_; }

    /// See if row is selected. Returns false if row is out of range.
    bool rowSelected(int row)
    {
        if (row < 0 || row >= rows()) return false;
        return rowselect_[row] != 0;
    }

    /// Changes the selection state for row: flag 0=clear, 1=set
    /// (default), 2=toggle. Returns 1 if the state changed, 0 if
    /// unchanged, -1 if row is out of range or the mode disallows it.
    int selectRow(int row, int flag = 1)
    {
        int ret = 0;
        if (row < 0 || row >= rows()) return -1;
        final switch (selectmode_)
        {
        case TableRowSelectMode.selectNone:
            return -1;
        case TableRowSelectMode.selectSingle:
            foreach (t; 0 .. rows())
            {
                if (t == row)
                {
                    ubyte oldval = rowselect_[row];
                    if (flag == 2) rowselect_[row] ^= 1;
                    else rowselect_[row] = cast(ubyte) flag;
                    if (oldval != rowselect_[row])
                    {
                        redrawRange(row, row, leftcol, rightcol);
                        ret = 1;
                    }
                }
                else if (rowselect_[t])
                {
                    rowselect_[t] = 0;
                    redrawRange(t, t, leftcol, rightcol);
                }
            }
            break;
        case TableRowSelectMode.selectMulti:
            ubyte oldval = rowselect_[row];
            if (flag == 2) rowselect_[row] ^= 1;
            else rowselect_[row] = cast(ubyte) flag;
            if (rowselect_[row] != oldval)
            {
                if (row >= toprow && row <= botrow) redrawRange(row, row, leftcol, rightcol);
                ret = 1;
            }
            break;
        }
        return ret;
    }

    /// Convenience method to change the selection state for all rows:
    /// flag 0=deselect, 1=select (default), 2=toggle existing state.
    void selectAllRows(int flag = 1)
    {
        final switch (selectmode_)
        {
        case TableRowSelectMode.selectNone:
            return;
        case TableRowSelectMode.selectSingle:
            if (flag != 0) return;
            goto case TableRowSelectMode.selectMulti;
        case TableRowSelectMode.selectMulti:
            bool changed = false;
            if (flag == 2)
            {
                foreach (ref sel; rowselect_) sel ^= 1;
                changed = true;
            }
            else
            {
                foreach (ref sel; rowselect_)
                {
                    changed |= sel != flag;
                    sel = cast(ubyte) flag;
                }
            }
            if (changed) redraw();
            break;
        }
    }

    override void clear()
    {
        rows(0); // implies clearing selection
        cols(0);
        super.clear();
    }

    override int handle(Event e)
    {
        int eventButton = fl.core.eventButton();
        int eventX = fl.core.eventX();
        int eventY = fl.core.eventY();
        auto eventState = fl.core.eventState();

        int ret = super.handle(e);

        int shiftstate = (eventState & stateCtrl) != 0 ? stateCtrl
            : (eventState & stateShift) != 0 ? stateShift : 0;

        int R, C;
        ResizeFlag resizeflag;
        TableContext context = cursor2rowcol(R, C, resizeflag);

        switch (e)
        {
        case Event.push:
            if (eventButton == leftMouse)
            {
                lastPushX_ = eventX;
                lastPushY_ = eventY;

                if (context == contextCell)
                {
                    if (shiftstate == stateCtrl)
                    {
                        selectRow(R, 2); // toggle
                    }
                    else if (shiftstate == stateShift)
                    {
                        selectRow(R, 1);
                        if (lastRow_ > -1)
                        {
                            int srow = R, erow = lastRow_;
                            if (srow > erow) { srow = lastRow_; erow = R; }
                            foreach (row; srow .. erow + 1) selectRow(row, 1);
                        }
                    }
                    else
                    {
                        selectAllRows(0); // clear all previous selections
                        selectRow(R, 1);
                    }
                    lastRow_ = R;
                    draggingSelect_ = true;
                    ret = 1; // ensures FL_DRAG will be sent
                }
            }
            break;

        case Event.drag:
            if (draggingSelect_)
            {
                int offtop = toy - lastY_;
                int offbot = lastY_ - (toy + toh);

                if (offtop > 0 && rowPosition() > 0)
                {
                    int diff = lastY_ - eventY;
                    if (diff < 1) { ret = 1; break; }
                    rowPosition(rowPosition() - diff);
                    context = contextCell;
                    C = 0;
                    R = rowPosition();
                    if (R < 0 || R > rows()) { ret = 1; break; }
                }
                else if (offbot > 0 && botrow < rows())
                {
                    int diff = eventY - lastY_;
                    if (diff < 1) { ret = 1; break; }
                    rowPosition(rowPosition() + diff);
                    context = contextCell;
                    C = 0;
                    R = botrow;
                    if (R < 0 || R > rows()) { ret = 1; break; }
                }
                if (context == contextCell)
                {
                    if (shiftstate == stateCtrl)
                    {
                        if (R != lastRow_) selectRow(R, 2); // toggle if dragged to new row
                    }
                    else
                    {
                        selectRow(R, 1);
                        if (lastRow_ > -1)
                        {
                            int srow = R, erow = lastRow_;
                            if (srow > erow) { srow = lastRow_; erow = R; }
                            foreach (row; srow .. erow + 1) selectRow(row, 1);
                        }
                    }
                    ret = 1;
                    lastRow_ = R;
                }
            }
            break;

        case Event.release:
            if (eventButton == leftMouse)
            {
                draggingSelect_ = false;
                ret = 1;
                int databot = tiy + tableH;
                int dataright = tix + tableW;
                if ((lastPushX_ > dataright && eventX > dataright)
                    || (lastPushY_ > databot && eventY > databot))
                    selectAllRows(0); // clicked off the data table -- clear selection
            }
            break;

        default:
            break;
        }
        lastY_ = eventY;
        return ret;
    }
}

// ===========================================================================
// Unit tests -- pure selection-state logic, safe headless. Drawing/
// mouse interaction need a live X display, same as every other
// widget-drawing code in this port -- not exercised here.
// ===========================================================================

unittest
{
    // selectRow()/rowSelected() under the default selectMulti mode.
    import fl.group : FlGroup;

    FlGroup.current(null);
    auto t = new TableRow(0, 0, 200, 200);
    FlGroup.current(null);

    t.rows(5);
    assert(t.selectMode() == TableRowSelectMode.selectMulti);
    assert(!t.rowSelected(2));

    assert(t.selectRow(2) == 1); // changed
    assert(t.rowSelected(2));
    assert(t.selectRow(2) == 0); // already selected, no change

    assert(t.selectRow(3) == 1);
    assert(t.rowSelected(2) && t.rowSelected(3)); // multi: both stay selected

    assert(t.selectRow(2, 0) == 1); // deselect
    assert(!t.rowSelected(2));
    assert(t.rowSelected(3));

    assert(t.selectRow(3, 2) == 1); // toggle -> deselected
    assert(!t.rowSelected(3));

    assert(t.selectRow(99) == -1); // out of range

    fl.core.resetForTest();
}

unittest
{
    // selectSingle mode: selecting a new row deselects any other.
    import fl.group : FlGroup;

    FlGroup.current(null);
    auto t = new TableRow(0, 0, 200, 200);
    FlGroup.current(null);

    t.rows(5);
    t.selectMode(TableRowSelectMode.selectSingle);

    t.selectRow(1);
    assert(t.rowSelected(1));
    t.selectRow(3);
    assert(t.rowSelected(3));
    assert(!t.rowSelected(1)); // single mode: selecting row 3 clears row 1

    fl.core.resetForTest();
}

unittest
{
    // selectNone mode: selection is always refused.
    import fl.group : FlGroup;

    FlGroup.current(null);
    auto t = new TableRow(0, 0, 200, 200);
    FlGroup.current(null);

    t.rows(5);
    t.selectMode(TableRowSelectMode.selectNone);
    assert(t.selectRow(1) == -1);
    assert(!t.rowSelected(1));

    fl.core.resetForTest();
}

unittest
{
    // selectAllRows(): flag 0=deselect, 1=select, 2=toggle.
    import fl.group : FlGroup;

    FlGroup.current(null);
    auto t = new TableRow(0, 0, 200, 200);
    FlGroup.current(null);

    t.rows(4);
    t.selectAllRows(1);
    foreach (r; 0 .. 4) assert(t.rowSelected(r));

    t.selectAllRows(0);
    foreach (r; 0 .. 4) assert(!t.rowSelected(r));

    t.selectRow(1); // select just row 1
    t.selectAllRows(2); // toggle everything
    assert(!t.rowSelected(1)); // was selected, now not
    assert(t.rowSelected(0)); // was not, now is
    assert(t.rowSelected(2));
    assert(t.rowSelected(3));

    fl.core.resetForTest();
}

unittest
{
    // rows() growing/shrinking the selection array (matching FLTK's
    // own PR #1187 ordering: enlarge before Table.rows(), shrink after).
    import fl.group : FlGroup;

    FlGroup.current(null);
    auto t = new TableRow(0, 0, 200, 200);
    FlGroup.current(null);

    t.rows(5);
    t.selectRow(4);
    assert(t.rowSelected(4));

    t.rows(3); // shrink -- row 4 no longer exists
    assert(t.rows() == 3);
    assert(!t.rowSelected(4)); // out of range now, reports false rather than stale true

    t.rows(6); // grow again -- new rows start deselected
    assert(!t.rowSelected(5));

    fl.core.resetForTest();
}

unittest
{
    // clear() resets rows/cols and selection.
    import fl.group : FlGroup;

    FlGroup.current(null);
    auto t = new TableRow(0, 0, 200, 200);
    FlGroup.current(null);

    t.rows(5);
    t.cols(3);
    t.selectRow(2);

    t.clear();
    assert(t.rows() == 0);
    assert(t.cols() == 0);

    fl.core.resetForTest();
}
