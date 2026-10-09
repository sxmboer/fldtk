/*
 * The `Grid` used on the design canvas. Adds what editing needs on top
 * of `fl.grid.Grid`: `drawOverlay()`, which draws the row/column cell
 * lines over a selected grid (or over the grid a dragged child sits
 * in), and `moveCell()`, which places a child into a cell, keeping a
 * child that lands on an occupied cell as a "transient" overlay on
 * that cell. Ported from `Fl_Grid_Proxy` (`fluid/nodes/Grid_Node.cxx`).
 * Generated code creates a plain `fl.grid.Grid`; only the canvas uses
 * this class.
 */
module fluid.grid_proxy;

import fl;
import fluid.grid_node : GridCellInfo;

final class GridProxy : Grid
{
    /// A child that was dropped on an occupied cell: it sits over that
    /// cell without belonging to the grid's cell list, and keeps the
    /// cell data it would have had.
    private struct Transient
    {
        Widget widget;
        GridCellInfo info;
    }

    private Transient[] transient_;

    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
    }

    /// Draws the grid's cell lines in the current drawing color (the
    /// overlay's selection color), then restores that color.
    void drawOverlay()
    {
        if (needLayout()) layout();
        gridColor_ = fl_color();
        lineStyle(lineDot, 0);
        drawGrid();
        fl_color(gridColor_);
    }

    alias widget = Grid.widget;

    /// Assigning a widget to a real cell ends its transient state.
    override Cell widget(Widget wi, int row, int col, int rowspan, int colspan,
        GridAlign align_ = gridFill)
    {
        transientRemove(wi);
        return super.widget(wi, row, col, rowspan, colspan, align_);
    }

    private void transientRemove(Widget w)
    {
        foreach (i, t; transient_)
        {
            if (t.widget is w)
            {
                transient_ = transient_[0 .. i] ~ transient_[i + 1 .. $];
                return;
            }
        }
    }

    private Transient* transientEntry(Widget w)
    {
        foreach (ref t; transient_)
            if (t.widget is w)
                return &t;
        return null;
    }

    /// The cell data of `child`, from its real cell or, failing that,
    /// its transient one. Returns `false` if it has neither.
    bool cellInfo(Widget child, out GridCellInfo info)
    {
        if (auto c = cell(child))
        {
            info = GridCellInfo(c.row(), c.col(), c.rowspan(), c.colspan(),
                cast(int) c.alignment(), c.minWidth(), c.minHeight());
            return true;
        }
        if (auto t = transientEntry(child))
        {
            info = t.info;
            return true;
        }
        return false;
    }

    /**
     * Moves `inChild` (which must already be a child of this grid) into
     * the cell at `toRow`, `toCol`, keeping its span, alignment and
     * minimum size. If that cell is taken, `how` decides: 0 replaces the
     * occupant (which loses its cell), 1 leaves the occupant and
     * unlinks `inChild`, 2 leaves the occupant and makes `inChild` a
     * transient widget resized to the occupant's rectangle. Ported from
     * `Fl_Grid_Proxy::move_cell()`.
     */
    void moveCell(Widget inChild, int toRow, int toCol, int how = 0)
    {
        if (find(inChild) >= children()) return;

        int rowspan = 1, colspan = 1;
        GridAlign align_ = gridFill;
        int w = 20, h = 20;
        if (auto old = cell(inChild))
        {
            if (old.row() == toRow && old.col() == toCol) return;
            rowspan = old.rowspan();
            colspan = old.colspan();
            align_ = old.alignment();
            w = old.minWidth();
            h = old.minHeight();
        }
        if (toRow < 0 || toRow + rowspan > rows()) return;
        if (toCol < 0 || toCol + colspan > cols()) return;

        Cell newCell;
        switch (how)
        {
        case 0:
            newCell = widget(inChild, toRow, toCol, rowspan, colspan, align_);
            break;
        case 1:
            if (cell(toRow, toCol) is null)
                newCell = widget(inChild, toRow, toCol, rowspan, colspan, align_);
            else if (auto old = cell(inChild))
                removeCell(old.row(), old.col());
            break;
        case 2:
            auto occupant = cell(toRow, toCol);
            if (occupant is null)
            {
                newCell = widget(inChild, toRow, toCol, rowspan, colspan, align_);
            }
            else
            {
                if (auto old = cell(inChild))
                    removeCell(old.row(), old.col());
                transientRemove(inChild);
                transient_ ~= Transient(inChild,
                    GridCellInfo(toRow, toCol, rowspan, colspan, cast(int) align_, w, h));
                auto ow = occupant.widget();
                inChild.resize(ow.x(), ow.y(), ow.w(), ow.h());
            }
            break;
        default:
            break;
        }
        if (newCell !is null) newCell.minimumSize(w, h);
    }
}
