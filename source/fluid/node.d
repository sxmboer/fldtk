/*
 * Base class for every entry in a parsed .fl project tree -- widgets
 * (Fl_Window, Fl_Slider, Fl_Box, ...) and non-widget scaffolding
 * (Function, decl, class, comment, ...) alike. Ported from FLTK's
 * `fluid::Node` (`fluid/nodes/Node.h`/`.cxx`), but as a real tree
 * (`children`, a plain array) rather than FLTK's flat doubly-
 * linked list plus an integer nesting `level` -- a C-era space
 * optimization with no reason to carry over into a fresh D
 * implementation; every consumer here only ever needs child/parent
 * access, never the flat-list representation itself.
 *
 * Phase 1 scope (see the "Fluid Phase 1" plan): just enough universal
 * properties to parse `test/fast_slow.fl`. Grows per future .fl file.
 */
module fluid.node;

import fluid.project_reader : Reader;
import std.conv : to;

/// A half-open `[start, end)` character-offset range into one generated
/// text buffer, recorded live while `fluid.code_writer.Writer`/
/// `fluid.project_writer.ProjectWriter` walk the tree. Backs the Code
/// View panel's click-a-node -> pan-and-highlight-the-generated-code
/// feature (`codeview_panel.fl`'s `codeviewUpdatePosition()`/
/// `findInText()`). Ported from FLTK's `TextSpan`
/// (`fluid/nodes/Node.h`), but a single `int` pair rather than
/// FLTK's own header/source (`h`/`c`) pair -- this dialect has no
/// header/source split (a single generated `.d` file per project), so
/// there is only ever one "code" buffer to track a position into.
/// `start`/`end` default to `-1`, matching FLTK's own "not tracked"
/// sentinel.
struct TextSpan
{
    int start = -1;
    int end = -1;
}

/// Access level of a widget field or a function, FLTK's
/// `Widget_Node::public_`/`Function_Node::public_` (0/1/2). Inside a class
/// it is the member's D protection attribute. Outside a class, private
/// keeps a widget's variable or a function private to its module
/// (FLTK's `static`) and anything else leaves it public.
enum Access
{
    private_ = 0,
    public_ = 1,
    protected_ = 2,
}

class Node
{
    /// This node's own `.fl` type keyword, e.g. "Fl_Slider", "Function".
    string typeName;

    /// The instance name from the `.fl` file (e.g. "control" in
    /// `Fl_Slider control { ... }`), or "" for an anonymous node
    /// (`Fl_Window {} { ... }`).
    string instanceName;

    Node parent;
    Node[] children;

    // -- universal properties (Node::read_property() in FLTK) --
    string label;
    bool hasLabel;
    string callback;
    string userData;
    string comment;
    bool open_;      // "open" flag -- Fluid-editor-only, harmless to keep
    bool selected_;  // ditto

    /// FLTK: `uid_`/`set_uid()`/`get_uid()` (`Node.h`/`.cxx`) -- a
    /// per-node id, unique within a project, that survives a project
    /// text round-trip when the id is present in the source text (an
    /// ordinary `label`/`comment`-style property, read back in
    /// `readProperty()` below). Every node gets a freshly generated one
    /// at construction time (`nextUid()`), later overwritten by
    /// `readProperty()`'s own "uid" case if the parsed `.fl` text
    /// actually carried one -- the same "construct with a sane default,
    /// let the reader override it if the source said otherwise" shape
    /// every other field on this class already follows.
    ///
    /// Deliberate simplification versus FLTK: a plain, ever-
    /// incrementing counter (`nextUid()`) instead of FLTK's random-
    /// number-plus-collision-retry-scan-the-whole-tree approach
    /// (`Node::set_uid()`) -- this port has no single "the current
    /// project's tree" this base class could scan (plenty of tests
    /// construct a bare `Node`/`WindowNode`/etc. with no project
    /// context at all). The counter is a `ushort` and can wrap or meet
    /// ids read from a `.fl` file, so `ensureUniqueUids()` repairs a
    /// forest before it is written when MergeBack, which looks nodes up
    /// by `uid`, is on.
    ///
    /// `fluid.project_writer.ProjectWriter.generate()` writes `uid` when
    /// its `includeUid` parameter is set (`gui_main.d`'s undo/redo
    /// snapshots, matching windows across a reparse by identity) or
    /// when the project's `ProjectSettings.writeMergebackData` is on.
    ushort uid;

    /// Assigns `uid` -- a plain field initializer can't do this (D
    /// class field initializers are baked into a static, compile-time
    /// `.init` block, so a stateful, non-CTFE-able generator like
    /// `nextUid()` has to run from a real constructor instead). Every
    /// subclass either has no constructor of its own (the compiler
    /// generates one that calls this) or has one that doesn't
    /// explicitly call a different `super(...)` overload (there is
    /// only this one to call, so the compiler inserts an implicit call
    /// to it regardless) -- so this runs for every `Node` instance
    /// project-wide with no per-subclass changes needed.
    this()
    {
        uid = nextUid();
    }

    /// This node's own generated D source position -- see `TextSpan`'s
    /// own doc comment. `setupSpan` is FLTK's `setup_node` (this
    /// node's own code, written before any children); `finalizeSpan` is
    /// `finalize_node` (written after children -- `.end()`,
    /// `resizable()`, and similar postscript). Only `fluid.code_writer.
    /// Writer`'s widget-tree node kinds (window/group/widget) set these
    /// -- every other node kind (Function, Class, decl, comment, ...)
    /// leaves them at `TextSpan.init`, which the Code View panel treats
    /// the same way FLTK treats any untracked position: no
    /// highlight, no pan, no crash.
    TextSpan setupSpan;
    TextSpan finalizeSpan;

    /// This node's own entry in the generated `.fl` project text
    /// (`fluid.project_writer.ProjectWriter`) -- FLTK's `proj1`/
    /// `proj2`. `projSpan1` is the node's own property block (`Type
    /// name {...}`); `projSpan2` is the same span for a leaf node, or
    /// just the closing-brace line of its children block for a
    /// container. Set for every node kind (`ProjectWriter.writeNode()`
    /// walks the whole tree uniformly, unlike `Writer`'s split-by-kind
    /// dispatch above).
    TextSpan projSpan1, projSpan2;

    void addChild(Node child)
    {
        child.parent = this;
        children ~= child;
    }

    /// Removes `child` from `children` (a no-op if it isn't actually a
    /// child of this node) and clears its own `parent` back to `null`
    /// -- the inverse of `addChild()`, needed by `gui_main.d`'s own
    /// "delete selected widget(s)" (a more basic, more urgently missing
    /// capability than undo/multi-target-apply -- you can add a widget
    /// via the palette but couldn't remove one again at all before this).
    void removeChild(Node child)
    {
        import std.algorithm : countUntil, remove;

        auto idx = children.countUntil(child);
        if (idx < 0) return;
        children = children.remove(idx);
        child.parent = null;
    }

    /// Inserts `child` right after `after` in this node's own `children`
    /// array (or appends it, if `after` isn't actually a child of this
    /// node) -- the positional counterpart to `addChild()`'s own
    /// "always append" behavior, needed for `gui_main.d`'s Paste/
    /// Duplicate (a pasted/duplicated node belongs right next to the
    /// selection it was copied from or pasted after, not tacked onto
    /// the end of the container, matching FLTK's own `Node::
    /// move_before()`-based positioning in `Fluid.cxx`'s `paste_from_
    /// clipboard()`/`duplicate_selected()`).
    void insertChildAfter(Node after, Node child)
    {
        import std.algorithm : countUntil;

        child.parent = this;
        auto idx = children.countUntil(after);
        if (idx < 0) { children ~= child; return; }
        children = children[0 .. idx + 1] ~ child ~ children[idx + 1 .. $];
    }

    /// Returns the sibling immediately before this node in its own
    /// parent's `children` array, or `null` if this is the first child
    /// (or has no parent). Ported from FLTK's `Node::prev_sibling()`
    /// (`fluid/nodes/Node.cxx`) -- trivial here since this port's `Node`
    /// already keeps a real `children` array per parent rather than
    /// FLTK's flat doubly-linked list plus an integer nesting
    /// `level` (see this module's own top comment); FLTK has to
    /// walk backward through the whole flat list looking for the first
    /// node at the same `level`, this port just indexes one array.
    Node prevSibling()
    {
        import std.algorithm : countUntil;

        if (parent is null) return null;
        auto idx = parent.children.countUntil(this);
        if (idx <= 0) return null;
        return parent.children[idx - 1];
    }

    /// The next-sibling counterpart to `prevSibling()` above -- ported
    /// from FLTK's `Node::next_sibling()`.
    Node nextSibling()
    {
        import std.algorithm : countUntil;

        if (parent is null) return null;
        auto idx = parent.children.countUntil(this);
        if (idx < 0 || idx + 1 >= parent.children.length) return null;
        return parent.children[idx + 1];
    }

    /// Moves this node to just before sibling `g` within their shared
    /// parent's `children` array -- a no-op if `this`/`g` aren't both
    /// children of the same parent (defensive only; every current
    /// caller, `gui_main.d`'s Earlier/Later and Group/Ungroup, only ever
    /// passes real siblings). Ported from FLTK's `Node::move_before()`
    /// (`fluid/nodes/Node.cxx`), but simpler for the same "real tree, not
    /// a flat list" reason `prevSibling()`/`nextSibling()` are above:
    /// FLTK has to splice its subtree out of, then back into, one
    /// shared flat linked list (and separately fix up every affected
    /// node's `level`); here it's a plain remove-then-insert on one
    /// array, and there's no `level` to keep in sync at all.
    void moveBefore(Node g)
    {
        import std.algorithm : countUntil, remove;

        if (parent is null || g is null || g.parent !is parent) return;
        auto children = parent.children;
        auto srcIdx = children.countUntil(this);
        if (srcIdx < 0) return;
        children = children.remove(srcIdx);
        auto dstIdx = children.countUntil(g);
        if (dstIdx < 0) return; // defensive only -- g was just confirmed to be a sibling
        parent.children = children[0 .. dstIdx] ~ this ~ children[dstIdx .. $];
    }

    /// Whether this node type can contain children in a `.fl` file
    /// (Function/Fl_Window/Fl_Group/... vs a leaf widget like
    /// Fl_Slider/Fl_Box). Overridden per concrete node kind.
    bool canHaveChildren() const { return false; }

    /// `.fl` text may put one more word between a node's type and its name
    /// (`class FL_EXPORT Foo {`). The reader calls this with that first
    /// word when the token after it was not the opening brace, and treats
    /// the token after as the name if it returns true. Only classes take
    /// such a word (FLTK's `Project_Reader` does the same).
    bool acceptLeadingAttribute(string word) { return false; }

    /// Reads one already-tokenized property name; returns false if
    /// this node (or, via the `super.readProperty()` chain, none of
    /// its base classes) recognizes it -- the reader is then forgiving
    /// about the unrecognized property, matching FLTK's own
    /// tolerant-of-unknown-properties parsing spirit (see
    /// `Reader.parseNode()`).
    bool readProperty(Reader r, string name)
    {
        switch (name)
        {
        case "label":
            label = r.readValue();
            hasLabel = true;
            return true;
        case "callback":
            callback = r.readValue();
            return true;
        case "user_data":
            userData = r.readValue();
            return true;
        case "comment":
            comment = r.readValue();
            return true;
        case "open":
            open_ = true;
            return true;
        case "selected":
            selected_ = true;
            return true;
        case "uid":
            // Overwrites the fresh id `this()` already assigned -- see
            // `uid`'s own doc comment. Hex, matching the `%04x` this
            // port (and FLTK) writes it as. A garbled/hand-edited
            // value is tolerated the same way an unrecognized property
            // already is: silently keep the freshly generated one
            // rather than throwing and aborting the whole parse over
            // one bad field.
            try uid = to!ushort(r.readValue(), 16);
            catch (Exception) {}
            return true;
        default:
            return false;
        }
    }

    /// Handles one property found inside a *child*'s own
    /// `parent_properties { ... }` block -- see `fluid.grid_node.
    /// GridNode`'s own override and module doc comment for the concrete
    /// case this exists for (grid-cell placement, stored on the child's
    /// `.fl` property list but interpreted by the parent, matching
    /// FLTK's `Node::read_parent_property()`/`Grid_Node::
    /// read_parent_property()` split). Default: unhandled, mirroring
    /// `readProperty()`'s own convention -- only a container whose
    /// children carry parent-owned properties needs to override this.
    bool readParentProperty(Reader r, Node child, string name)
    {
        return false;
    }
}

/// Backs `Node.uid` -- see that field's own doc comment for why this is
/// a plain incrementing counter rather than FLTK's random-plus-
/// collision-retry `Node::set_uid()`. Starts at 1 so `0`/`ushort.init`
/// stays a usable "no id assigned yet" sentinel for any future caller
/// that wants one (no current caller needs it, `uid` is always assigned
/// by `Node.this()` before anything else can observe it, but costs
/// nothing to reserve).
private ushort nextUid_ = 0;
private ushort nextUid()
{
    return ++nextUid_;
}

/// Makes every node's `uid` nonzero and unique within `roots`' forest,
/// reassigning only the offenders (a later duplicate keeps losing, the
/// first node in tree order keeps its id). Ported from what FLTK's
/// `Node::ensure_unique_uid()` guarantees per node; done as one pass
/// here because `nextUid()`'s process-wide `ushort` counter can wrap in
/// a long session and can collide with ids read from a `.fl` file.
/// MergeBack looks nodes up by `uid`, so both `fluid.project_writer`
/// and `fluid.code_writer` call this before writing when MergeBack is
/// on.
void ensureUniqueUids(Node[] roots)
{
    bool[ushort] taken;
    Node[] pending;
    void walk(Node[] nodes)
    {
        foreach (n; nodes)
        {
            if (n.uid != 0 && n.uid !in taken)
                taken[n.uid] = true;
            else
                pending ~= n;
            walk(n.children);
        }
    }
    walk(roots);
    foreach (n; pending)
    {
        ushort candidate;
        do candidate = nextUid();
        while (candidate == 0 || candidate in taken);
        n.uid = candidate;
        taken[candidate] = true;
    }
}

unittest
{
    // uid: every fresh node gets a distinct, nonzero id, and a value
    // read back off a `.fl` file (readProperty()'s own "uid" case)
    // overwrites the freshly-assigned one rather than being ignored.
    auto a = new Node();
    auto b = new Node();
    assert(a.uid != 0 && b.uid != 0 && a.uid != b.uid);

    // Round-trips through a real parse too, the way `restoreFromText()`
    // actually uses it: a `uid` property in the source text overwrites
    // whatever id the freshly-constructed node would otherwise have
    // gotten.
    auto roots = new Reader("comment x {\n  uid beef\n}\n").readProject();
    assert(roots.length == 1);
    assert(roots[0].uid == 0xbeef);
}

unittest
{
    // insertChildAfter() (used by gui_main.d's Paste/
    // Duplicate): positional sibling insert, vs. addChild()'s own
    // always-append. Also confirms the fallback (appends if `after`
    // isn't actually a child) and that `parent`/`children` stay
    // consistent throughout, the same invariants addChild()/
    // removeChild() already have their own coverage for elsewhere.
    auto root = new Node();
    auto a = new Node(); a.instanceName = "a";
    auto b = new Node(); b.instanceName = "b";
    auto c = new Node(); c.instanceName = "c";
    root.addChild(a);
    root.addChild(c);
    assert(root.children == [a, c]);

    root.insertChildAfter(a, b);
    assert(root.children == [a, b, c]);
    assert(b.parent is root);

    // Inserting after the *last* child behaves like a plain append.
    auto d = new Node(); d.instanceName = "d";
    root.insertChildAfter(c, d);
    assert(root.children == [a, b, c, d]);

    // `after` not actually a child of this node -- falls back to append.
    auto stray = new Node();
    auto e = new Node(); e.instanceName = "e";
    root.insertChildAfter(stray, e);
    assert(root.children == [a, b, c, d, e]);
    assert(e.parent is root);
}

unittest
{
    // prevSibling()/nextSibling()/moveBefore() (used by
    // gui_main.d's Earlier/Later and Group/Ungroup).
    auto root = new Node();
    auto a = new Node(); a.instanceName = "a";
    auto b = new Node(); b.instanceName = "b";
    auto c = new Node(); c.instanceName = "c";
    root.addChild(a);
    root.addChild(b);
    root.addChild(c);

    assert(a.prevSibling() is null);
    assert(a.nextSibling() is b);
    assert(b.prevSibling() is a);
    assert(b.nextSibling() is c);
    assert(c.nextSibling() is null);
    assert(root.prevSibling() is null); // no parent at all
    assert(root.nextSibling() is null);

    // Move the last child before the first -- [a, b, c] -> [c, a, b].
    c.moveBefore(a);
    assert(root.children == [c, a, b]);
    assert(c.parent is root); // unchanged, still a child of the same parent

    // Move it right back -- [c, a, b] -> [a, b, c].
    a.moveBefore(c);
    b.moveBefore(c);
    assert(root.children == [a, b, c]);

    // Moving a node before its own immediate successor is a harmless
    // no-op (same relative order both before and after).
    a.moveBefore(b);
    assert(root.children == [a, b, c]);

    // `g` not actually a sibling (different parent) -- no-op.
    auto stray = new Node();
    auto strayChild = new Node(); strayChild.instanceName = "strayChild";
    stray.addChild(strayChild);
    a.moveBefore(strayChild);
    assert(root.children == [a, b, c]);
}

unittest
{
    // ensureUniqueUids(): duplicates and zeros are reassigned, the first
    // holder of an id keeps it.
    auto root = new Node();
    auto a = new Node();
    auto b = new Node();
    auto c = new Node();
    root.addChild(a);
    root.addChild(b);
    a.addChild(c);
    a.uid = 7;
    b.uid = 7;
    c.uid = 0;
    ensureUniqueUids([root]);
    assert(a.uid == 7);
    assert(b.uid != 7 && b.uid != 0);
    assert(c.uid != 0 && c.uid != 7 && c.uid != b.uid);
    assert(root.uid != 0 && root.uid != a.uid && root.uid != b.uid && root.uid != c.uid);
}
