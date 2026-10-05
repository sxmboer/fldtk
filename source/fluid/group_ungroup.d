/*
 * `&Edit/&Group`/`Ung&roup` -- ported from FLTK's `fluid/nodes/
 * Group_Node.cxx`'s `group_cb()`/`ungroup_cb()`. Like `fluid.
 * node_order`/`fluid.align_widget`, these are pure functions over the
 * `Node` tree plus its `LiveTree` counterpart -- `gui_main.d` owns
 * checkpointing/UI refresh and the two upfront `fl_message()`-style
 * preconditions FLTK itself checks in the callback rather than the
 * worker function (see `gui_main.d`'s `groupSelectedCmd()`/
 * `ungroupSelectedCmd()`).
 *
 * **Not ported**: the menu-item-grouping branch both `group_cb()`/
 * `ungroup_cb()` dispatch to first (`Menu_Node.cxx`'s own
 * `group_selected_menuitems()`/`ungroup_selected_menuitems()`) --
 * `fluid.menu_item_node.MenuItemNode` is only parsed/round-tripped and
 * edited as a node, never grouped here.
 */
module fluid.group_ungroup;

import fl;
import fluid.node : Node;
import fluid.widget_node : WidgetNode;
import fluid.group_node : GroupNode;
import fluid.window_node : WindowNode;
import fluid.flex_node : reindexFlexIfNeeded;
import fluid.factory : createNode;
import fluid.instantiate : LiveTree, instantiateOne;

/// Whether `n` is a genuine widget container in FLTK's `Group_Node`
/// sense -- `dynamic_cast<Group_Node*>(qq)` there, which also accepts a
/// `Window_Node` (`Window_Node` derives from `Group_Node` in FLTK).
/// This port's `WindowNode` does *not* derive from `GroupNode` (see
/// `PORTING.md`'s `fluid/nodes/` row), so both casts are needed to
/// match FLTK's real acceptance set. Deliberately narrower than
/// `Node.canHaveChildren()`: that's also `true` for `FunctionNode`/
/// `ClassNode`/`CodeBlockNode`/`DeclBlockNode`/`MenuOwnerNode`, none of
/// which are widget containers a `Group`/`Ungroup` should ever promote
/// a widget into or out of -- `MenuOwnerNode` in particular is exactly
/// the case FLTK routes to the separate, not-ported
/// `group_selected_menuitems()`/`ungroup_selected_menuitems()` (see
/// this module's own top comment); using `canHaveChildren()` here would
/// silently fall through into the wrong path for a selected menu item
/// instead of correctly refusing it.
private bool isContainerNode(Node n)
{
    return cast(GroupNode) n !is null || cast(WindowNode) n !is null;
}

/// Ported from `fix_group_size()` (`nodes/Group_Node.cxx`): enlarges
/// `g` so its own bounds contain every `WidgetNode` anywhere in its
/// subtree (not just direct children -- matches FLTK's own flat-list
/// walk, which considers every descendant regardless of nesting depth).
/// Operates on `Node`-level `x`/`y`/`w`/`h` fields, not a live widget --
/// unlike FLTK, where `Node` has no geometry of its own at all and this
/// function reads/writes the live `Fl_Widget` directly, this port's
/// `WidgetNode` already stores geometry as real fields (see
/// `geometryEdited()` in `gui_main.d` for the established "Node fields
/// are the authoritative source, sync the live widget from them"
/// convention this follows too). `package(fluid)` rather than
/// `private`: also called directly by `gui_main.d`'s own
/// `fitGroupToContentsCmd()` (`&Edit/Fit to Contents`) on an
/// *already-live* group, not just from `groupSelected()`'s own
/// brand-new-group case just below -- see that command's own doc
/// comment for how it re-syncs the live widget tree afterward, since
/// this function alone only ever touches the `Node` model.
///
/// With `shrink` set, the result is instead the exact combined bounding
/// box of the descendants (the group's own current bounds are ignored,
/// so it can get smaller); a group with no `WidgetNode` descendants is
/// left unchanged. Used by `fitGroupToContentsCmd()`.
package(fluid) void fixGroupSize(WidgetNode g, bool shrink = false)
{
    int X = g.x, Y = g.y, R = g.x + g.w, B = g.y + g.h;
    bool first = shrink;

    void walk(Node n)
    {
        foreach (child; n.children)
        {
            if (auto wc = cast(WidgetNode) child)
            {
                if (first)
                {
                    X = wc.x; Y = wc.y; R = wc.x + wc.w; B = wc.y + wc.h;
                    first = false;
                }
                if (wc.x < X) X = wc.x;
                if (wc.y < Y) Y = wc.y;
                if (wc.x + wc.w > R) R = wc.x + wc.w;
                if (wc.y + wc.h > B) B = wc.y + wc.h;
            }
            walk(child);
        }
    }

    walk(g);
    g.x = X; g.y = Y; g.w = R - X; g.h = B - Y;
}

/// `&Edit/&Group` -- ported from `group_cb()` (`nodes/Group_Node.cxx`).
/// `q` is the primary selection (FLTK's own `Fluid.proj.tree.current`);
/// creates a new `Group` as a sibling of `q` inside `q`'s own parent,
/// positioned right where `q` was, then absorbs every other currently-
/// selected direct sibling of `q` into it (in original order) and
/// enlarges it to fit them all (`fixGroupSize()`). Returns the new
/// group `Node`, or `null` if `q` has no real container parent to
/// create the new group in (FLTK's own `qq` ancestor walk collapses to
/// a plain `q.parent` check here -- see this module's own top comment
/// on why: unlike FLTK's flat list, which can put non-widget-shaped
/// nodes in between, a `WidgetNode`'s own `.parent` in this port's real
/// tree is always already the nearest container, by construction, so
/// there is never a non-container node to walk past).
WidgetNode groupSelected(WidgetNode q, LiveTree live, string projectDir)
{
    Node qq = q.parent;
    if (qq is null || !isContainerNode(qq)) return null;
    auto qqBefore = qq.children.dup; // for reindexFlexIfNeeded() below,
                                      // captured before qq loses any
                                      // children to the new group

    auto n = cast(WidgetNode) createNode("Group");
    n.typeName = "Group";
    n.instanceName = "";
    n.hasXywh = true;
    n.x = q.x; n.y = q.y; n.w = q.w; n.h = q.h;

    qq.addChild(n);
    n.moveBefore(q);

    WidgetNode[] moving;
    foreach (child; qq.children.dup)
    {
        if (child is n || !child.selected_) continue;
        if (auto wc = cast(WidgetNode) child)
            moving ~= wc;
    }
    foreach (wc; moving)
    {
        qq.removeChild(wc);
        n.addChild(wc);
    }
    reindexFlexIfNeeded(qq, qqBefore);

    fixGroupSize(n);

    auto liveParentGroup = cast(FlGroup) live.widgetOf.get(qq, null);
    if (liveParentGroup !is null)
    {
        auto newGroupWidget = cast(FlGroup) instantiateOne(n, projectDir);
        // `instantiateOne()`'s own construction (`new FlGroup(...)`)
        // calls `begin()`, which leaves `FlGroup.current()` pointing at
        // `newGroupWidget` -- nothing here ever calls a matching
        // `end()` the way an ordinary `.fl`-parse tree walk would, so
        // this must reset it explicitly (see CONVENTIONS.md's own
        // "Shared static state needs hermetic tests" note on exactly
        // this class of bug: a stray `FlGroup.current()` silently
        // auto-parenting whatever gets constructed next).
        FlGroup.current(null);
        if (newGroupWidget !is null)
        {
            auto liveQ = live.widgetOf.get(q, null);
            int insertIdx = liveQ !is null ? liveParentGroup.find(liveQ) : liveParentGroup.children();
            liveParentGroup.insert(newGroupWidget, insertIdx);
            live.widgetOf[n] = newGroupWidget;
            live.nodeOf[newGroupWidget] = n;

            foreach (wc; moving)
            {
                if (auto lw = live.widgetOf.get(wc, null))
                    newGroupWidget.add(lw);
            }
            newGroupWidget.redraw();
        }
    }

    return n;
}

/// `&Edit/Ung&roup` -- ported from `ungroup_cb()` (`nodes/Group_Node.
/// cxx`). `q` is the primary selection; `qq` (`q.parent`) is the group
/// being dissolved -- every one of `qq`'s currently-selected children
/// (not just `q` itself, matching FLTK's own `t->selected` scan over
/// every direct child at `q`'s own level) is promoted to become a
/// sibling of `qq` instead, spliced into `qq`'s own parent's children
/// array immediately before `qq`, in original relative order. If that
/// empties `qq` out completely, `qq` itself is deleted too (both node
/// and live widget -- matches FLTK's own trailing `qq->remove(); delete
/// qq;`). Returns whether anything actually changed; `false` (a no-op)
/// if `q` has no group parent to ungroup out of, or `grandparent`
/// (`qq.parent`) isn't itself a real widget container to promote into.
/// That second check is stricter than a literal port of FLTK's own
/// `dynamic_cast<Group_Node*>(qq)` (only applied to `qq` there) would
/// be: `qq` moving one level up onto whatever `qq.parent` happens to be
/// is fine as long as `qq` itself is a `Window_Node` or `Group_Node`,
/// but this port's tree has no sane place to put a promoted widget
/// under a non-container ancestor -- most concretely, `qq ==` the
/// project's own top-level `WindowNode`, whose own parent is a
/// `FunctionNode` (`isContainerNode()` correctly rejects that, so
/// ungrouping something sitting directly in a window, with no `Group`
/// wrapping it, is a safe no-op instead of promoting a widget into
/// `FunctionNode.children` -- an invalid tree `code_writer.d` has
/// nothing sane to emit for).
bool ungroupSelected(WidgetNode q, LiveTree live)
{
    import std.algorithm : countUntil;

    Node qq = q.parent;
    if (qq is null || !isContainerNode(qq)) return false;
    Node grandparent = qq.parent;
    if (grandparent is null || !isContainerNode(grandparent)) return false;

    WidgetNode[] moving;
    foreach (child; qq.children.dup)
    {
        if (auto wc = cast(WidgetNode) child)
            if (wc.selected_) moving ~= wc;
    }
    if (moving.length == 0) return false;

    auto liveGrandparentGroup = cast(FlGroup) live.widgetOf.get(grandparent, null);
    auto liveQq = cast(FlGroup) live.widgetOf.get(qq, null);
    int insertIdx = liveGrandparentGroup !is null
        ? (liveQq !is null ? liveGrandparentGroup.find(liveQq) : liveGrandparentGroup.children())
        : -1;
    foreach (wc; moving)
    {
        auto lw = live.widgetOf.get(wc, null);
        if (lw is null) continue; // no live widget for this node at all
        if (liveGrandparentGroup !is null)
        {
            liveGrandparentGroup.insert(lw, insertIdx);
            insertIdx++;
        }
        else if (liveQq !is null)
        {
            // No live grandparent to re-home into (shouldn't happen in
            // practice -- see this function's own doc comment on why
            // `grandparent` should always have a live widget whenever
            // `qq` does -- but if it doesn't, at least detach `lw` from
            // `liveQq` now rather than leave it silently still attached:
            // if `qq` ends up empty and deleted below, `FlGroup.~this()`'s
            // own `clear()` recursively destroys every widget still in
            // its own child array, which would otherwise destroy this
            // orphaned widget too while `live.widgetOf`/`nodeOf` still
            // point at it -- a real, dangling-reference-after-destroy
            // hazard, not just a cosmetic desync.
            liveQq.remove(lw);
        }
    }

    auto gpBefore = grandparent.children.dup; // for reindexFlexIfNeeded()
                                               // below -- `qq` itself
                                               // disappears from this
                                               // list, replaced by `moving`

    foreach (wc; moving) qq.removeChild(wc);
    auto gc = grandparent.children;
    auto idx = gc.countUntil(qq);
    if (idx < 0) return true; // defensive only -- shouldn't happen,
                               // `qq` is always a real child of its own
                               // `.parent`; the Node-tree mutation above
                               // has already committed either way
    grandparent.children = gc[0 .. idx] ~ cast(Node[]) moving ~ gc[idx .. $];
    foreach (wc; moving) wc.parent = grandparent;
    reindexFlexIfNeeded(grandparent, gpBefore);

    // Only ever delete `qq` itself when it's a plain `Group` (a
    // `GroupNode`) -- FLTK's own trailing `qq->remove(); delete qq;`
    // has no equivalent guard, but FLTK's `Window_Node` destructor
    // doesn't need one: a window there is never itself deleted through
    // this path in the first place, since its own destructor has no
    // special "hide the window, deregister it" work to do the way this
    // port's `removeNodes()` does for `WindowNode` (`cv.hide()`,
    // `canvases_.remove(wn)`, clearing `activeWindow_`). Deleting a
    // nested window here directly (`qq` is a `WindowNode`, reachable
    // only from a parsed `.fl` with a window nested inside a `Group` --
    // `createWindowNode()` can't produce one) would skip all of that
    // and leave `canvases_`/`activeWindow_` pointing at a destroyed
    // widget. Leaving an emptied-out nested window in place instead is
    // harmless and correct either way.
    if (qq.children.length == 0 && cast(GroupNode) qq !is null)
    {
        grandparent.removeChild(qq);
        // Belt-and-suspenders on top of the unconditional detach loop
        // above: only actually destroy `liveQq` if it's genuinely empty
        // at the *live* level too. `FlGroup.~this()`'s own `clear()`
        // recursively destroys anything still attached when it runs
        // (deferred to the next `wait()`/`check()` via `deleteWidget()`)
        // -- if it somehow isn't empty here (every path above should
        // have already prevented that, but this is exactly the kind of
        // invariant worth checking before an irreversible, deferred
        // destroy rather than trusting it blindly), leave it alive
        // rather than risk destroying a widget `live.widgetOf`/`nodeOf`
        // still has a mapping for elsewhere.
        if (liveQq !is null && liveQq.children() == 0)
        {
            deleteWidget(liveQq);
            live.widgetOf.remove(qq);
            live.nodeOf.remove(liveQq);
        }
    }

    return true;
}

unittest
{
    // groupSelected(): two selected sibling widgets inside a real
    // GroupNode container get wrapped in a new Group, positioned where
    // the primary selection (`q`) was, sized to fit both.
    auto win = new WindowNode();
    auto container = new GroupNode();
    container.hasXywh = true;
    container.x = 0; container.y = 0; container.w = 200; container.h = 200;
    win.addChild(container);

    auto a = new WidgetNode(); a.instanceName = "a";
    a.hasXywh = true; a.x = 10; a.y = 10; a.w = 20; a.h = 20;
    auto b = new WidgetNode(); b.instanceName = "b";
    b.hasXywh = true; b.x = 40; b.y = 50; b.w = 20; b.h = 20;
    auto c = new WidgetNode(); c.instanceName = "c"; // not selected -- stays put
    c.hasXywh = true; c.x = 100; c.y = 100; c.w = 20; c.h = 20;
    container.addChild(a);
    container.addChild(b);
    container.addChild(c);

    a.selected_ = true;
    b.selected_ = true;

    LiveTree empty;
    auto g = groupSelected(a, empty, ".");
    assert(g !is null);
    assert(g.parent is container);
    assert(container.children == [g, c]); // a/b moved out, c untouched
    assert(g.children == [a, b]);
    assert(a.parent is g && b.parent is g);

    // Bounding box: a is [10,10,20,20] -> right/bottom 30,30; b is
    // [40,50,20,20] -> right/bottom 60,70. fixGroupSize() should cover both.
    assert(g.x == 10 && g.y == 10);
    assert(g.x + g.w == 60 && g.y + g.h == 70);
}

unittest
{
    // groupSelected(): refuses to create a group when `q`'s own parent
    // isn't a real widget container (`isContainerNode()`) -- here `q`
    // sits directly under a `FunctionNode`, which can happen for a
    // stray/malformed selection but should never actually be reachable
    // in practice (a `WidgetNode`'s parent is always a `Window`/`Group`
    // by construction elsewhere in this port).
    import fluid.function_node : FunctionNode;

    auto fn = new FunctionNode();
    auto q = new WidgetNode(); q.instanceName = "q";
    fn.addChild(q);
    q.selected_ = true;

    LiveTree empty;
    assert(groupSelected(q, empty, ".") is null);
    assert(fn.children == [q]); // unchanged
}

unittest
{
    // ungroupSelected(): dissolves a Group directly inside a Window,
    // promoting its selected children back up to become direct children
    // of the window; the now-empty Group node is deleted too.
    auto win = new WindowNode();
    auto grp = new GroupNode(); grp.instanceName = "grp";
    win.addChild(grp);

    auto a = new WidgetNode(); a.instanceName = "a";
    auto b = new WidgetNode(); b.instanceName = "b";
    grp.addChild(a);
    grp.addChild(b);
    a.selected_ = true;
    b.selected_ = true;

    LiveTree empty;
    assert(ungroupSelected(a, empty));
    assert(win.children == [a, b]); // promoted, in original order
    assert(a.parent is win && b.parent is win);
}

unittest
{
    // ungroupSelected(): a widget sitting directly in a Window (no
    // wrapping Group at all) is a safe no-op -- `qq` is the `WindowNode`
    // itself, whose own parent is a `FunctionNode`, which
    // `isContainerNode()` correctly rejects (see `ungroupSelected()`'s
    // own doc comment on why this is stricter than a literal port of
    // FLTK's own single `dynamic_cast<Group_Node*>(qq)` check).
    import fluid.function_node : FunctionNode;

    auto fn = new FunctionNode();
    auto win = new WindowNode();
    fn.addChild(win);

    auto a = new WidgetNode(); a.instanceName = "a";
    win.addChild(a);
    a.selected_ = true;

    LiveTree empty;
    assert(!ungroupSelected(a, empty));
    assert(win.children == [a]); // unchanged
    assert(fn.children == [win]); // unchanged
}
