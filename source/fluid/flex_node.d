/*
 * `Fl_Flex` node -- a container with margin/gap and a per-child
 * "fixed size" flag. Ported from FLTK's `Flex_Node`
 * (`fluid/nodes/Group_Node.h`/`.cxx`'s "Flex_Node" section --
 * FLTK keeps it in the same file as `Group_Node`/`Table_Node`
 * rather than its own pair, ported here as its own module instead
 * since this project gives every node kind its own file). `fl.flex.Flex`
 * (the underlying widget) is already a complete, independent port --
 * everything here is purely the `.fl` parse/emit layer.
 *
 * Own properties (matching `Flex_Node::write_properties()`/
 * `read_property()` exactly): `margin {l t r b}`, `gap N`, and
 * `fixed_size_tuples {N idx0 size0 idx1 size1 ...}`.
 *
 * `fixed_size_tuples` stores *child index* -> *fixed size* pairs, which
 * only make sense once every child is known -- FLTK handles this
 * with a two-phase read (`read_property()` stashes the raw array,
 * `postprocess_read()` resolves it against `flex->child(i)` after the
 * whole subtree is parsed). This port doesn't need a matching
 * "postprocess" hook: the raw `int[]` is just kept on this node
 * (`fixedSizeTuples`) and resolved against `.children` directly by
 * `instantiate.d`/`code_writer.d`, both of which only ever run after the
 * entire tree is already parsed -- simpler than FLTK's own
 * two-phase approach here, not a missing feature.
 *
 * `type` (row vs. column, FLTK's `HORIZONTAL`/`VERTICAL` -- see
 * `Group_Node.cxx`'s `flex_type_menu`) needs no new mechanism at all:
 * it's handled generically by `WidgetNode.typeWord` and `code_writer.d`'s
 * existing `typeWordMap`/`translateTypeWord()`, the same path every
 * other widget's `type` keyword already goes through. Two entries were
 * added there (`"HORIZONTAL"` -> `flexHorizontal`, `"VERTICAL"` ->
 * `flexVertical`, from `source/fl/flex.d`).
 *
 * Live-applied to `instantiate.d`'s canvas too, via
 * that module's own `typeWordValueMap`/`applyProperties()` -- a
 * `Flex`'s orientation changes its whole layout, so this is the most
 * visible consumer of that shared `WidgetNode.typeWord` mechanism.
 */
module fluid.flex_node;

import fluid.group_node;
import fluid.node : Node;
import fluid.project_reader : Reader;

final class FlexNode : GroupNode
{
    int marginLeft, marginTop, marginRight, marginBottom;
    bool hasMargin;
    int gap;
    bool hasGap;

    /// Raw `[idx0, size0, idx1, size1, ...]` pairs (FLTK's own
    /// leading pair-count is stripped during parsing -- redundant with
    /// `.length / 2`, nothing here needs it kept) -- see this module's
    /// own top comment on why no "postprocess" resolution step is
    /// needed here.
    int[] fixedSizeTuples;

    override bool readProperty(Reader r, string name)
    {
        switch (name)
        {
        case "margin":
            auto v = r.readValue();
            parseFourInts(v, marginLeft, marginTop, marginRight, marginBottom);
            hasMargin = true;
            return true;
        case "gap":
            gap = toIntSafe(r.readValue());
            hasGap = true;
            return true;
        case "fixed_size_tuples":
            auto all = parseIntArray(r.readValue());
            // First value is FLTK's own pair-count -- redundant
            // with the rest of the array's own length, drop it.
            fixedSizeTuples = all.length > 0 ? all[1 .. $] : all;
            return true;
        default: return super.readProperty(r, name);
        }
    }
}

/// Re-anchors `fn.fixedSizeTuples`' own `[idx, size, ...]` entries to
/// `fn.children`'s *current* order/membership, given `resolveAgainst`
/// -- the children array those indices were last resolved against
/// (almost always `fn.children` itself, captured *before* whatever
/// reorder/removal is about to run). `fixedSizeTuples` stores
/// *positional* child indices (see this module's own top comment), so
/// any operation that changes a `FlexNode`'s own child order or
/// membership -- `fluid.node_order`'s Sort/Earlier/Later,
/// `fluid.group_ungroup`'s Group/Ungroup -- silently makes every entry
/// point at the wrong child (or, after a removal, an entirely different
/// one) unless it calls this right after. An entry whose child is no
/// longer among `fn.children` at all (removed, or moved into a
/// different container) is dropped rather than kept with a stale index
/// -- this matches FLTK's own `Flex_Node::remove_child()`
/// (`Group_Node.cxx`), which calls `((Fl_Flex*)o)->fixed(child, 0)` to
/// explicitly clear a departing child's fixed-size flag, not just a
/// defensive choice made independently here.
void reindexFixedSizeTuples(FlexNode fn, Node[] resolveAgainst)
{
    import std.algorithm : countUntil;

    int[] result;
    for (size_t i = 0; i + 1 < fn.fixedSizeTuples.length; i += 2)
    {
        int oldIdx = fn.fixedSizeTuples[i];
        int size = fn.fixedSizeTuples[i + 1];
        if (oldIdx < 0 || oldIdx >= resolveAgainst.length) continue;
        auto newIdx = fn.children.countUntil(resolveAgainst[oldIdx]);
        if (newIdx < 0) continue;
        result ~= [cast(int) newIdx, size];
    }
    fn.fixedSizeTuples = result;
}

/// `reindexFixedSizeTuples()`, but a no-op for anything other than a
/// `FlexNode` -- the convenience form `fluid.node_order`/`fluid.
/// group_ungroup` actually call after any reorder/removal, since
/// neither one already knows (or should need to know) whether
/// `parentNode` happens to be a `FlexNode` before deciding whether this
/// applies at all.
void reindexFlexIfNeeded(Node parentNode, Node[] before)
{
    if (auto fn = cast(FlexNode) parentNode)
        reindexFixedSizeTuples(fn, before);
}

unittest
{
    import fluid.widget_node : WidgetNode;

    auto fn = new FlexNode();
    auto a = new WidgetNode(); a.instanceName = "a";
    auto b = new WidgetNode(); b.instanceName = "b";
    auto c = new WidgetNode(); c.instanceName = "c";
    fn.addChild(a);
    fn.addChild(b);
    fn.addChild(c);
    fn.fixedSizeTuples = [1, 60]; // b (index 1) is fixed at 60px

    auto before = fn.children.dup;
    // Reorder: move c before a -- [a, b, c] -> [c, a, b].
    c.moveBefore(a);
    assert(fn.children == [c, a, b]);

    reindexFixedSizeTuples(fn, before);
    // b is still the fixed child, now at index 2.
    assert(fn.fixedSizeTuples == [2, 60]);

    // Removing the fixed child drops its entry instead of keeping a
    // stale index.
    before = fn.children.dup;
    fn.removeChild(b);
    reindexFixedSizeTuples(fn, before);
    assert(fn.fixedSizeTuples == []);
}

private int toIntSafe(string s)
{
    import std.conv : to;

    try
        return to!int(s);
    catch (Exception)
        return 0;
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
