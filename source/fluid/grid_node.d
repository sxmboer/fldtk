/*
 * `Fl_Grid` node -- a container that also owns per-child cell
 * placement (row/col/span/align/minsize). Ported from FLTK's
 * `Grid_Node` (`fluid/nodes/Grid_Node.h`/`.cxx`). `fl.grid.Grid` (the
 * underlying widget) is already a complete, independent port --
 * everything here is purely the `.fl` parse/emit layer.
 *
 * Own properties (matching `Grid_Node::write_properties()`/
 * `read_property()` exactly): `dimensions {rows cols}`, `margin
 * {l t r b}`, `gap {rowGap colGap}`, and six bare space-separated int
 * arrays (`rowheights`/`rowweights`/`rowgaps`/`colwidths`/`colweights`/
 * `colgaps`), one value per row or column.
 *
 * **`parent_properties` -- a genuinely new mechanism, not just another
 * node's own property list.** FLTK stores a grid child's cell
 * placement (`location`/`colspan`/`rowspan`/`align`/`minsize`) inside
 * the *child's* own `.fl` property block, but has the *parent* (this
 * class) interpret it -- `Node::read_property()` sees the literal
 * keyword `"parent_properties"`, opens a nested `{ }` block, and hands
 * each inner property name to `child->parent()->read_parent_property()`
 * rather than the child's own `read_property()`. `project_reader.d`'s own top
 * comment already named `parent_properties` as a known-deferred
 * concept -- this is where it's actually built: `Reader.parseNode()`
 * now threads the in-progress parent `Node` through its own recursive
 * call (so a child's property-parsing loop can reach its parent
 * *before* `addChild()` would normally set `child.parent`, which
 * happens only after the child's entire subtree has been read) and
 * calls the new `Node.readParentProperty()` virtual (default: `false`/
 * unhandled, mirroring `readProperty()`'s own convention) when it sees
 * the `parent_properties` keyword. `GridNode` is the only override.
 *
 * The write side (`project_writer.d`) does NOT get a matching virtual
 * method on `Node` -- that file has never used virtual dispatch through
 * `Node` for writing (`writeProperties()`'s own `cast(FunctionNode)`/
 * `cast(WidgetNode)`/... checks are the established pattern, only the
 * *read* side is virtual via `Node.readProperty()`) -- so
 * `project_writer.d`'s own `writeParentProperties()` just checks
 * `cast(GridNode) n.parent` directly, matching that existing style.
 *
 * Cell placement is stored here as a plain `GridCellInfo[Node]` side
 * table rather than needing a live `Fl_Grid::Cell` during parsing (no
 * live widget exists yet at parse time) -- `instantiate.d`/`code_writer.d`
 * read this table once they build/emit the grid's children.
 *
 * The canvas-side pieces live in `fluid.grid_proxy` (overlay, cell
 * moves, transient cells) and `fluid.layout_edit` (click-to-cell
 * insertion, keyboard moves, `child_resized()`, and the sync of a
 * child's cell and rectangle from the live grid back into this node).
 */
module fluid.grid_node;

import fluid.group_node;
import fluid.node : Node;
import fluid.project_reader : Reader;

/// Per-child grid placement -- matches FLTK's `Fl_Grid::Cell`'s own
/// fields and defaults (`rowspan`/`colspan` = 1, `align` = `FL_GRID_FILL`
/// = `fl.grid.gridFill` = 0x30, `minimum_size` = 20x20).
struct GridCellInfo
{
    int row, col;
    int rowspan = 1;
    int colspan = 1;
    int alignRaw = 0x30; // fl.grid.gridFill
    int minW = 20;
    int minH = 20;
}

final class GridNode : GroupNode
{
    int rows = 3, cols = 3; // FLTK's own Grid_Node() ctor default
    bool hasDimensions;

    int marginLeft, marginTop, marginRight, marginBottom;
    bool hasMargin;
    int gapRow, gapCol;
    bool hasGap;

    int[] rowHeights, rowWeights, rowGaps;
    int[] colWidths, colWeights, colGaps;

    /// Keyed by child `Node`, populated via `readParentProperty()` as
    /// each child's own `parent_properties {}` block is parsed.
    GridCellInfo[Node] cellOf;

    override bool readProperty(Reader r, string name)
    {
        switch (name)
        {
        case "dimensions":
            auto v = r.readValue();
            parseTwoInts(v, rows, cols);
            hasDimensions = true;
            return true;
        case "margin":
            auto v = r.readValue();
            parseFourInts(v, marginLeft, marginTop, marginRight, marginBottom);
            hasMargin = true;
            return true;
        case "gap":
            auto v = r.readValue();
            parseTwoInts(v, gapRow, gapCol);
            hasGap = true;
            return true;
        case "rowheights": rowHeights = parseIntArray(r.readValue()); return true;
        case "rowweights": rowWeights = parseIntArray(r.readValue()); return true;
        case "rowgaps": rowGaps = parseIntArray(r.readValue()); return true;
        case "colwidths": colWidths = parseIntArray(r.readValue()); return true;
        case "colweights": colWeights = parseIntArray(r.readValue()); return true;
        case "colgaps": colGaps = parseIntArray(r.readValue()); return true;
        default: return super.readProperty(r, name);
        }
    }

    /// See this module's own top comment for the full `parent_properties`
    /// mechanism -- `child` is the grid child whose block this property
    /// came from (not `this`).
    override bool readParentProperty(Reader r, Node child, string name)
    {
        auto info = child in cellOf;
        GridCellInfo local = info ? *info : GridCellInfo.init;
        switch (name)
        {
        case "location":
            parseTwoInts(r.readValue(), local.row, local.col);
            break;
        case "colspan":
            local.colspan = toIntSafe(r.readValue());
            break;
        case "rowspan":
            local.rowspan = toIntSafe(r.readValue());
            break;
        case "align":
            local.alignRaw = toIntSafe(r.readValue());
            break;
        case "minsize":
            parseTwoInts(r.readValue(), local.minW, local.minH);
            break;
        default:
            return false;
        }
        cellOf[child] = local;
        return true;
    }
}

private int toIntSafe(string s)
{
    import std.conv : to;

    try
        return to!int(s);
    catch (Exception)
        return 0;
}

private void parseTwoInts(string s, ref int a, ref int b)
{
    import std.string : split;

    auto parts = split(s);
    if (parts.length >= 2)
    {
        a = toIntSafe(parts[0]);
        b = toIntSafe(parts[1]);
    }
}

private void parseFourInts(string s, ref int a, ref int b, ref int c, ref int d)
{
    import std.string : split;

    auto parts = split(s);
    if (parts.length >= 4)
    {
        a = toIntSafe(parts[0]);
        b = toIntSafe(parts[1]);
        c = toIntSafe(parts[2]);
        d = toIntSafe(parts[3]);
    }
}

private int[] parseIntArray(string s)
{
    import std.string : split;
    import std.array : array;
    import std.algorithm : map;

    return split(s).map!(toIntSafe).array;
}
