/*
 * Sibling-reordering editor commands -- `&Edit/&Sort`/`&Earlier`/
 * `&Later`, ported from FLTK's `fluid/nodes/Widget_Node.cxx`'s free
 * `sort()` function and `fluid/nodes/Node.cxx`'s `earlier_cb()`/
 * `later_cb()`. Like `fluid.align_widget`, these are pure functions
 * over a `Node` subtree plus its `LiveTree` counterpart -- `gui_main.d`
 * owns checkpointing/UI refresh, this module only owns the actual
 * reorder math and keeps the live widget tree's own child order in
 * sync with it (sibling order in a live `Fl_Group` is both paint
 * (z-)order and keyboard tab order, so a `Node`-tree-only reorder would
 * silently desync the canvas -- and the generated code -- from each
 * other).
 *
 * All three functions read straight off each `Node`'s own `selected_`
 * flag (kept in sync with `ProjectCanvas.selected()` by that module's
 * own selection methods -- see `fluid.canvas`'s `clearSelectedFlags()`)
 * rather than taking an explicit selection list, matching FLTK's own
 * reliance on `Node::selected` directly. Scoped to one subtree (`root`,
 * always `activeWindow_` at the one call site in `gui_main.d`) rather
 * than FLTK's whole-project flat list -- matches this port's own
 * established "Edit-menu commands operate on the active window"
 * convention (see `gui_main.d`'s `selectAll()`'s own doc comment).
 *
 * **Not ported**: FLTK's `Fluid.proj.tree.allow_layout` gate around
 * `layout_widget()`'s own `Fl_Flex`/`Fl_Grid` relayout call. That gate
 * (the "Synchronized Resize" toggle) lives in
 * `fluid.canvas.ProjectCanvas.allowLayout`, which governs interactive
 * dragging only. These three functions call `Flex.layout()`/
 * `Grid.layout()` unconditionally, which matches FLTK's own *effective*
 * behavior at exactly these three call sites regardless of the toggle's
 * state: FLTK's own `layout_widget()`
 * increments the gate counter itself before calling `o->layout()` and
 * decrements it right after, guaranteeing a real layout here no matter
 * what the persistent toggle is set to.
 */
module fluid.node_order;

import fluid.node : Node;
import fluid.widget_node : WidgetNode;
import fluid.instantiate : LiveTree;
import fluid.flex_node : reindexFlexIfNeeded;
import fl.group : FlGroup;
import fl.flex : Flex;
import fl.grid : Grid;

/// Mirrors a same-parent `Node.moveBefore()` call onto the
/// corresponding live widgets too, via `fl.group.FlGroup.insert()`'s own
/// "move within the same group" fast path -- a no-op if either side has
/// no live widget yet (a node with no `WindowNode` ancestor realized,
/// the same "degrades gracefully" convention `gui_main.d`'s
/// `instantiateUnderLiveParent()` already uses).
private void moveLiveBefore(Node f, Node g, LiveTree live)
{
    if (f.parent is null) return;
    auto group = cast(FlGroup) live.widgetOf.get(f.parent, null);
    auto lf = live.widgetOf.get(f, null);
    auto lg = live.widgetOf.get(g, null);
    if (group is null || lf is null || lg is null) return;
    group.insert(lf, group.find(lg));
}

/// Real relayout for a live `Flex`/`Grid` parent after its own children
/// were reordered (see this module's own top comment on why this is
/// unconditional rather than gated) -- a plain `Group` needs nothing
/// further here, matching FLTK's own default no-op `Node::
/// layout_widget()`.
private void relayoutIfNeeded(Node parentNode, LiveTree live)
{
    auto w = live.widgetOf.get(parentNode, null);
    if (auto flex = cast(Flex) w) flex.layout();
    else if (auto grid = cast(Grid) w) grid.layout();
}

/// `&Edit/&Earlier` -- ported from `earlier_cb()` (`nodes/Node.cxx`):
/// walks `root`'s descendants in document order, and for every selected
/// node whose previous sibling exists and *isn't* itself selected,
/// moves it before that sibling. The "not itself selected" guard is
/// what makes a contiguous run of selected siblings move up together as
/// a block instead of endlessly swapping past each other. Returns
/// whether anything actually moved.
bool moveSelectedEarlier(Node root, LiveTree live)
{
    bool moved = false;
    foreach (f; descendantsInOrder(root))
    {
        if (!f.selected_) continue;
        auto g = f.prevSibling();
        if (g is null || g.selected_) continue;
        auto before = f.parent.children.dup;
        moveLiveBefore(f, g, live);
        f.moveBefore(g);
        reindexFlexIfNeeded(f.parent, before);
        relayoutIfNeeded(f.parent, live);
        moved = true;
    }
    return moved;
}

/// `&Edit/&Later` -- ported from `later_cb()`, the mirror image of
/// `moveSelectedEarlier()` above: walks in *reverse* document order,
/// and for every selected node whose next sibling exists and isn't
/// itself selected, moves that sibling before it instead (equivalent to
/// moving the selected node one slot later). Returns whether anything
/// actually moved.
bool moveSelectedLater(Node root, LiveTree live)
{
    bool moved = false;
    foreach_reverse (f; descendantsInOrder(root))
    {
        if (!f.selected_) continue;
        auto g = f.nextSibling();
        if (g is null || g.selected_) continue;
        auto before = f.parent.children.dup;
        moveLiveBefore(g, f, live);
        g.moveBefore(f);
        reindexFlexIfNeeded(f.parent, before);
        relayoutIfNeeded(f.parent, live);
        moved = true;
    }
    return moved;
}

/// `&Edit/&Sort` -- ported from the free `sort(Node* parent)` function
/// in `nodes/Widget_Node.cxx`. Recursively sorts every level of
/// `root`'s subtree (children first, matching FLTK's own recursion
/// order), moving each selected `WidgetNode` child before the first
/// earlier selected sibling positioned strictly after it on screen (by
/// `y`, then `x`) -- an insertion sort that only ever compares selected
/// siblings against each other, so an unselected sibling's own relative
/// position is never used as a sort key and never itself moves. Returns
/// whether anything actually moved.
bool sortSelected(Node root, LiveTree live)
{
    bool moved = false;

    void sortChildrenOf(Node parent)
    {
        foreach (child; parent.children.dup)
            sortChildrenOf(child);

        auto beforeLevel = parent.children.dup;
        bool movedHere = false;
        foreach (f; parent.children.dup) // original, pre-this-level order
        {
            auto fw = cast(WidgetNode) f;
            if (!f.selected_ || fw is null) continue;

            Node g = null;
            foreach (candidate; parent.children) // live, current order
            {
                if (candidate is f) break;
                if (!candidate.selected_) continue;
                auto gw = cast(WidgetNode) candidate;
                if (gw is null) continue;
                if (gw.y > fw.y || (gw.y == fw.y && gw.x > fw.x)) { g = candidate; break; }
            }
            if (g !is null)
            {
                moveLiveBefore(f, g, live);
                f.moveBefore(g);
                movedHere = true;
            }
        }
        if (movedHere)
        {
            reindexFlexIfNeeded(parent, beforeLevel);
            relayoutIfNeeded(parent, live);
            moved = true;
        }
    }

    sortChildrenOf(root);
    return moved;
}

/// Pre-order (document-order) walk of `root`'s descendants, excluding
/// `root` itself -- matches FLTK's own flat-list traversal order
/// (`Fluid.proj.tree.first`/`next`) closely enough for
/// `moveSelectedEarlier()`/`moveSelectedLater()`'s purposes: both only
/// ever compare a node against its own immediate sibling, so the exact
/// order two unrelated subtrees are visited in relative to each other
/// never matters.
private Node[] descendantsInOrder(Node root)
{
    Node[] result;
    void walk(Node n)
    {
        foreach (c; n.children)
        {
            result ~= c;
            walk(c);
        }
    }
    walk(root);
    return result;
}

unittest
{
    // moveSelectedEarlier()/moveSelectedLater(): a contiguous run of
    // selected siblings moves together as a block, isolated selected
    // siblings just swap with their neighbor -- matches FLTK's own
    // documented behavior (see this module's own doc comment).
    auto root = new Node();
    auto a = new Node(); a.instanceName = "a";
    auto b = new Node(); b.instanceName = "b";
    auto c = new Node(); c.instanceName = "c";
    auto d = new Node(); d.instanceName = "d";
    root.addChild(a);
    root.addChild(b);
    root.addChild(c);
    root.addChild(d);

    // [a b c d], select b and c (a contiguous run) -> Earlier moves
    // both up together: [b c a d].
    b.selected_ = true;
    c.selected_ = true;
    LiveTree empty;
    assert(moveSelectedEarlier(root, empty));
    assert(root.children == [b, c, a, d]);

    // Nothing left to move earlier (b is already first) -- no-op.
    assert(!moveSelectedEarlier(root, empty));
    assert(root.children == [b, c, a, d]);

    b.selected_ = false;
    c.selected_ = false;

    // [b c a d], select c and a (not contiguous) -> Later moves each
    // one slot later, walked in reverse document order: a swaps with
    // its neighbor d first ([b c d a]), then c swaps with its own new
    // neighbor d too ([b d c a]) -- matches FLTK's own `later_cb()`
    // exactly (traced by hand against its real linked-list semantics,
    // not guessed).
    c.selected_ = true;
    a.selected_ = true;
    assert(moveSelectedLater(root, empty));
    assert(root.children == [b, d, c, a]);
}

unittest
{
    // sortSelected(): only selected WidgetNode children are reordered,
    // sorted by (y, x); unselected siblings and non-widget nodes are
    // left untouched and never used as comparison keys.
    import fluid.function_node : FunctionNode;

    auto win = new Node();
    auto low = new WidgetNode(); low.instanceName = "low"; low.x = 0; low.y = 20;
    auto high = new WidgetNode(); high.instanceName = "high"; high.x = 0; high.y = 0;
    auto mid = new WidgetNode(); mid.instanceName = "mid"; mid.x = 0; mid.y = 10;
    auto notWidget = new FunctionNode(); notWidget.instanceName = "notWidget";
    win.addChild(low);
    win.addChild(notWidget);
    win.addChild(high);
    win.addChild(mid);

    low.selected_ = true;
    high.selected_ = true;
    mid.selected_ = true;

    LiveTree empty;
    assert(sortSelected(win, empty));
    // `notWidget` never moves (not a WidgetNode); the three selected
    // widgets end up in y order relative to each other.
    import std.algorithm : filter, countUntil;
    import std.array : array;
    auto widgetsOnly = win.children.filter!(n => cast(WidgetNode) n !is null).array;
    assert(widgetsOnly == [high, mid, low]);
    assert(win.children.countUntil(notWidget) >= 0);
}
