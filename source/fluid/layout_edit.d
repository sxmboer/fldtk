/*
 * Editing operations for the children of `Grid` and `Flex` containers
 * on the design canvas, and the sync from the live widgets back to the
 * node model. A grid or flex decides where its children sit, so after
 * an edit the live container is the truth and the nodes are brought in
 * line with it: each child's rectangle, a grid child's cell, a flex's
 * child order and fixed sizes.
 *
 * The operations are ported from `Grid_Node`/`Flex_Node`
 * (`fluid/nodes/Grid_Node.cxx`, `Group_Node.cxx`):
 * `insert_child_at()`, `insert_child_at_next_free_cell()`,
 * `keyboard_move_child()` and `child_resized()`.
 */
module fluid.layout_edit;

import fl;
import fluid.node : Node;
import fluid.widget_node : WidgetNode;
import fluid.window_node : WindowNode;
import fluid.grid_node : GridNode, GridCellInfo;
import fluid.flex_node : FlexNode;
import fluid.grid_proxy : GridProxy;
import fluid.instantiate : LiveTree, geometryFromLive;

/// Puts `child` into the flex slot nearest the point `x`, `y` (window
/// coordinates) along the flex's main axis, as `Flex_Node::
/// insert_child_at()` does.
void flexInsertChildAt(Flex flex, Widget child, int x, int y)
{
    int closestIdx = -1;
    int closestDist = flex.w() + flex.h();
    foreach (i; 0 .. flex.children())
    {
        auto c = flex.child(i);
        int d = flex.horizontal() ? x - c.x() : y - c.y();
        if (d < 0) d = -d;
        if (d < closestDist) { closestDist = d; closestIdx = i; }
    }
    int tailD = flex.horizontal() ? x - (flex.x() + flex.w()) : y - (flex.y() + flex.h());
    if (tailD < 0) tailD = -tailD;
    if (tailD < closestDist) { closestDist = tailD; closestIdx = flex.children(); }

    if (closestIdx >= 0)
        flex.insert(child, closestIdx);
}

/// Moves `child` one place along the flex's main axis for an arrow key,
/// as `Flex_Node::keyboard_move_child()` does.
void flexKeyboardMoveChild(Flex flex, Widget child, int key)
{
    int ix = flex.find(child);
    if (ix == flex.children()) return;
    if (flex.horizontal())
    {
        if (key == fl.enumerations.right) flex.insert(child, ix + 2);
        else if (key == fl.enumerations.left && ix > 0) flex.insert(child, ix - 1);
    }
    else
    {
        if (key == fl.enumerations.down) flex.insert(child, ix + 2);
        else if (key == fl.enumerations.up && ix > 0) flex.insert(child, ix - 1);
    }
}

/// Puts `child` into the grid cell under the point `x`, `y` (window
/// coordinates): the last row whose top edge is above the point and the
/// last column whose left edge is left of it. Ported from
/// `Grid_Node::insert_child_at()`; a point above or left of the first
/// cell leaves the child without a cell.
void gridInsertChildAt(GridProxy grid, Widget child, int x, int y)
{
    if (grid.needLayout()) grid.layout();
    int row = -1, col = -1;
    int x0 = grid.x() + fl.core.boxDx(grid.box()) + grid.marginLeft();
    int y0 = grid.y() + fl.core.boxDy(grid.box()) + grid.marginTop();

    foreach (r; 0 .. grid.rows())
    {
        if (y > y0) row = r;
        int gap = grid.rowGap(r) >= 0 ? grid.rowGap(r) : grid.gapRow();
        y0 += grid.computedRowHeight(r) + gap;
    }
    foreach (c; 0 .. grid.cols())
    {
        if (x > x0) col = c;
        int gap = grid.colGap(c) >= 0 ? grid.colGap(c) : grid.gapCol();
        x0 += grid.computedColWidth(c) + gap;
    }
    grid.moveCell(child, row, col, 2);
}

/// Puts `child` into the first free cell in row-major order, adding a
/// row if every cell is taken. Ported from
/// `Grid_Node::insert_child_at_next_free_cell()`.
void gridInsertChildAtNextFreeCell(GridProxy grid, Widget child)
{
    if (grid.cell(child) !is null) return;
    foreach (r; 0 .. grid.rows())
    {
        foreach (c; 0 .. grid.cols())
        {
            if (grid.cell(r, c) is null)
            {
                grid.moveCell(child, r, c);
                return;
            }
        }
    }
    grid.layout(grid.rows() + 1, grid.cols());
    grid.moveCell(child, grid.rows() - 1, 0);
}

/// Moves `child` one cell for an arrow key, as `Grid_Node::
/// keyboard_move_child()` does.
void gridKeyboardMoveChild(GridProxy grid, Widget child, int key)
{
    GridCellInfo info;
    if (!grid.cellInfo(child, info)) return;
    if (key == fl.enumerations.right) grid.moveCell(child, info.row, info.col + 1, 2);
    else if (key == fl.enumerations.left) grid.moveCell(child, info.row, info.col - 1, 2);
    else if (key == fl.enumerations.up) grid.moveCell(child, info.row - 1, info.col, 2);
    else if (key == fl.enumerations.down) grid.moveCell(child, info.row + 1, info.col, 2);
}

/// Takes a resized child's new size as its cell's minimum size on the
/// axes where the cell doesn't stretch it, as `Grid_Node::
/// child_resized()` does: the grid remembers the size a child had when
/// it was added, and the user has just changed it.
void gridChildResized(GridProxy grid, Widget child)
{
    auto cell = grid.cell(child);
    if (cell is null) return;
    if ((cell.alignment() & gridVertical) == 0)
        cell.minimumSize(cell.minWidth(), child.h());
    if ((cell.alignment() & gridHorizontal) == 0)
        cell.minimumSize(child.w(), cell.minHeight());
}

/// Makes the live children of `fn`'s flex follow the order of the
/// nodes, which is what a pasted widget inserted after another needs.
void applyFlexOrderToLive(FlexNode fn, ref LiveTree live)
{
    auto flex = cast(Flex) live.widgetOf.get(fn, null);
    if (flex is null) return;
    int index = 0;
    foreach (c; fn.children)
    {
        auto w = live.widgetOf.get(c, null);
        if (w is null || w.parent() !is flex) continue;
        flex.insert(w, index);
        index++;
    }
    flex.layout();
}

/// Brings a `Grid` or `Flex` node and its children in line with the live
/// container: every child's rectangle, a grid child's cell, and for a
/// flex the child order and fixed sizes. Returns `true` if the order of
/// a flex's children changed, so the project tree needs rebuilding.
bool syncLayoutFromLive(Node container, ref LiveTree live)
{
    bool reordered = false;
    auto gridNode = cast(GridNode) container;
    auto flexNode = cast(FlexNode) container;
    if (gridNode is null && flexNode is null) return false;

    if (flexNode !is null)
    {
        if (auto flex = cast(Flex) live.widgetOf.get(flexNode, null))
        {
            flex.layout();
            Node[] ordered;
            foreach (i; 0 .. flex.children())
            {
                auto n = live.nodeOf.get(flex.child(i), null);
                if (n !is null && n.parent is flexNode) ordered ~= n;
            }
            foreach (c; flexNode.children)
            {
                bool listed = false;
                foreach (o; ordered)
                    if (o is c) { listed = true; break; }
                if (!listed) ordered ~= c;
            }
            foreach (i, c; ordered)
                if (flexNode.children[i] !is c) { reordered = true; break; }
            flexNode.children = ordered;

            int[] tuples;
            foreach (i, c; flexNode.children)
            {
                auto w = live.widgetOf.get(c, null);
                if (w !is null && flex.fixed(w))
                    tuples ~= [cast(int) i, flex.horizontal() ? w.w() : w.h()];
            }
            flexNode.fixedSizeTuples = tuples;
        }
    }

    auto grid = gridNode is null ? null : cast(GridProxy) live.widgetOf.get(gridNode, null);
    if (grid !is null && grid.needLayout()) grid.layout();
    foreach (c; container.children)
    {
        auto wn = cast(WidgetNode) c;
        if (wn is null || cast(WindowNode) c !is null) continue;
        auto w = live.widgetOf.get(c, null);
        if (w is null) continue;
        geometryFromLive(wn, w);
        if (grid !is null)
        {
            GridCellInfo info;
            if (grid.cellInfo(w, info))
                gridNode.cellOf[c] = info;
        }
    }
    if (gridNode !is null && grid !is null)
    {
        gridNode.rows = grid.rows();
        gridNode.cols = grid.cols();
    }
    return reordered;
}

/// `syncLayoutFromLive()` for every grid and flex at or below `node`.
/// Run before the project is written, since a window resize or an edit
/// elsewhere can move layout-managed children without any of the
/// per-edit syncs having seen it.
bool syncAllLayoutsFromLive(Node node, ref LiveTree live)
{
    bool reordered = syncLayoutFromLive(node, live);
    foreach (c; node.children)
        if (syncAllLayoutsFromLive(c, live)) reordered = true;
    return reordered;
}
