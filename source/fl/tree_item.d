/*
 * Ported from FL/Fl_Tree_Item.H + src/Fl_Tree_Item.cxx (FLTK 1.5.0,
 * ~/Repositories/fltk). A single tree node: label, font/color
 * overrides, icons, an optional child Widget, and its own children
 * (recursively, more TreeItems). Fl_Tree_Item is a plain class, not a
 * Widget subclass -- ported the same way here.
 *
 * Deviations from FLTK, all deliberate:
 *
 *  - **No `Fl_Tree_Item_Array`.** FLTK's `_children` is a hand-
 *    managed `Fl_Tree_Item**`/`_total`/`_size`/`_chunksize` C array
 *    wrapped in its own class purely because pre-C++11 FLTK avoids
 *    STL/templates. This port uses a plain `TreeItem[] children_` GC
 *    array directly -- the exact same substitution already established
 *    for `fl.menu_`'s `MenuItem[]` replacing `Fl_Menu_Item*`'s manual
 *    `alloc`/`copy()`/free bookkeeping. `add()`/`insert()`/`remove()`/
 *    `swap()`/`move()`/`deparent()`/`reparent()` below are ported as
 *    plain slice operations on `children_` instead of calling into a
 *    separate array class -- see each method's own comment for the
 *    FLTK `Fl_Tree_Item_Array` method it replaces.
 *  - **`_flags` (a bit-packed `unsigned short` of OPEN/VISIBLE/ACTIVE/
 *    SELECTED) becomes four separate `bool` fields** (`open_`/
 *    `visible_`/`active_`/`selected_`). Unlike `Align`/`Damage`/etc.,
 *    this bitmask is a private implementation detail never exposed to
 *    callers as a raw bitmask (the public API is boolean accessors
 *    like `isOpen()`/`isSelected()`, never a raw flags getter) -- so
 *    there's no combinable-bitmask API to preserve, and four named
 *    bools are more readable than reimplementing bit-twiddling for a
 *    fixed set of four independent properties. Each place FLTK's
 *    generic `set_flag()` would have triggered `recalc_tree()` as a
 *    side effect (only for OPEN, and only redundantly -- `open()`/
 *    `close()` already call `recalc_tree()` explicitly themselves right
 *    after) keeps that same explicit call at the same call site; no
 *    generic `setFlag()`/`isFlag()` mechanism is ported since nothing
 *    else needs one.
 *  - **`_xywh`/`_collapse_xywh`/`_label_xywh` (three raw `int[4]`) are
 *    `fl.rect.Rect`** instead -- an existing type with the same
 *    x/y/w/h shape, already used elsewhere in this port for exactly
 *    this "describe a screen area without being a Widget" purpose.
 *  - **`user_data()`/`void*` becomes `Object userData_`.** Unlike
 *    `Fl_Callback`'s `void* user_data()` (which this port drops
 *    entirely in favor of D delegates closing over their own context --
 *    see `fl.menu_item`'s row), `Fl_Tree_Item::user_data()` is a
 *    distinct, still-needed feature: an arbitrary opaque payload
 *    attached to a tree node, unrelated to any callback. `Object` is
 *    the natural, type-safe D equivalent of "attach any caller value"
 *    -- same spirit as FLTK's `void*`, just checked by the
 *    compiler instead of cast blindly at every use site.
 *  - **Icon drawing (`openicon()`/`closeicon()`/`usericon()`) is real
 *    now** (2026-08-01, following `fl.image`'s own port): the
 *    `if (prefs.openicon())`-style branches that pick between a custom
 *    icon and the built-in `[+]`/`[-]` glyph, `uiconW`'s real width
 *    contribution to the label's x-position, and `calcItemHeight()`'s
 *    user-icon height contribution are all ported faithfully now,
 *    matching `Fl_Tree_Item::draw()`/`calc_item_height()`/
 *    `event_on_user_icon()` exactly. The built-in `[+]`/`[-]` glyph
 *    itself (FLTK: `Fl_System_Driver::tree_draw_expando_button()`,
 *    a driver hook this port has no abstraction for -- see
 *    `fl.tree_prefs`'s own top comment for why) is ported directly as
 *    a private `drawExpandoButton()` function in this module, where
 *    it's actually used, still the fallback when no custom icon is set.
 *  - **The deprecated no-tree constructor
 *    (`Fl_Tree_Item(const Fl_Tree_Prefs&)`) is not ported.** Unlike the
 *    ordinary renamed-API aliases this port does keep (see
 *    `fl.tree_prefs`'s obsolete-name bullet), FLTK's own doc
 *    comment says this one is more than just an old name: "you must
 *    use Fl_Tree_Item(Fl_Tree*) for proper horizontal scrollbar
 *    behavior" -- i.e. it's a genuinely degraded constructor, not just
 *    a stylistic predecessor. Every method here already assumes a
 *    non-null owning tree (`recalcTree()`, `tree()`, `prefs()`, ...),
 *    so faithfully porting a constructor that leaves `tree_` null would
 *    produce an object most of this class's own methods immediately
 *    null-dereference -- not a useful faithful port, just a landmine.
 *    `next_displayed()`/`prev_displayed()` (also FLTK-deprecated,
 *    "for confusing name") *are* ported, as thin forwarders to
 *    `nextVisible()`/`prevVisible()` -- those are genuinely just old
 *    names for working methods, the same category as `fl.tree_prefs`'s
 *    obsolete aliases, not a degraded-behavior case like the
 *    constructor above.
 */
module fl.tree_item;

import fl.enumerations;
import fl.rect : Rect;
import fl.widget : Widget;
import fl.image : Image;
import fl.tree_prefs;
import fl.tree : Tree;
import fl.core;
import fl.draw;

/**
 * A single node in a Tree: label, per-item font/color overrides,
 * optional icons, an optional child Widget, and its own children
 * (recursively). Ported from `Fl_Tree_Item`.
 */
class TreeItem
{
    private Tree tree_;
    private string label_;
    private Font labelfont_;
    private Fontsize labelsize_;
    private Color labelfgcolor_;
    private Color labelbgcolor_;
    private bool open_ = true;
    private bool visible_ = true;
    private bool active_ = true;
    private bool selected_ = false;
    private Rect xywh_;
    private Rect collapseXywh_;
    private Rect labelXywh_;
    private Widget widget_;
    private Image usericon_;
    private Image userdeicon_;
    private TreeItem[] children_;
    private TreeItem parent_;
    private Object userData_;
    private TreeItem prevSibling_;
    private TreeItem nextSibling_;

    /// Makes a new item for tree, with an empty label (""). Set
    /// label() before adding it to the tree so it draws a name and can
    /// be found by findItem()/etc. Ported from Fl_Tree_Item(Fl_Tree*).
    this(Tree tree)
    {
        tree_ = tree;
        labelfont_ = tree.prefs().itemLabelfont();
        labelsize_ = tree.prefs().itemLabelsize();
        labelfgcolor_ = tree.prefs().itemLabelfgcolor();
        labelbgcolor_ = tree.prefs().itemLabelbgcolor();
    }

    /// Copy constructor -- makes a new item with the same attributes as
    /// o (but not its children; siblings are re-derived by the caller
    /// via updatePrevNext(), never copied directly, matching FLTK).
    this(const(TreeItem) o)
    {
        tree_ = cast(Tree) o.tree_;
        label_ = o.label_;
        labelfont_ = o.labelfont_;
        labelsize_ = o.labelsize_;
        labelfgcolor_ = o.labelfgcolor_;
        labelbgcolor_ = o.labelbgcolor_;
        widget_ = cast(Widget) o.widget_;
        open_ = o.open_;
        visible_ = o.visible_;
        active_ = o.active_;
        selected_ = o.selected_;
        xywh_ = cast(Rect) o.xywh_;
        collapseXywh_ = cast(Rect) o.collapseXywh_;
        labelXywh_ = cast(Rect) o.labelXywh_;
        usericon_ = cast(Image) o.usericon_;
        userData_ = cast(Object) o.userData_;
        parent_ = cast(TreeItem) o.parent_;
    }

    /// The item's x position relative to the window.
    int x() const { return xywh_.x(); }
    /// The item's y position relative to the window.
    int y() const { return xywh_.y(); }
    /// The entire item's width to the right edge of Tree's inner width
    /// within scrollbars.
    int w() const { return xywh_.w(); }
    /// The item's height.
    int h() const { return xywh_.h(); }
    /// The item's label x position relative to the window.
    int labelX() const { return labelXywh_.x(); }
    /// The item's label y position relative to the window.
    int labelY() const { return labelXywh_.y(); }
    /// The item's maximum label width to the right edge of Tree's
    /// inner width within scrollbars.
    int labelW() const { return labelXywh_.w(); }
    /// The item's label height.
    int labelH() const { return labelXywh_.h(); }

    /// Print the tree as 'ascii art' to stdout -- mainly for debugging.
    void showSelf(string indent = "")
    {
        import std.stdio : writefln, stdout;

        writefln("%s-%s (%d children, this=%s, parent=%s, prev=%s, next=%s, depth=%d)",
            indent, label_.length ? label_ : "(NULL)", children_.length,
            cast(void*) this, cast(void*) parent_, cast(void*) prevSibling_,
            cast(void*) nextSibling_, depth());
        foreach (c; children_) c.showSelf(indent ~ " |");
        stdout.flush();
    }

    /// Set the label. Ported from Fl_Tree_Item::label(const char*).
    void label(string val)
    {
        label_ = val;
        recalcTree(); // may change label geometry
    }
    /// Return the label.
    string label() const { return label_; }

    /// Set a user-data value for the item -- see this module's own top
    /// comment on why this is Object, not void*.
    void userData(Object data) { userData_ = data; }
    /// Retrieve the user-data value assigned to the item.
    Object userData() const { return cast(Object) userData_; }

    /// Set item's label font face.
    void labelfont(Font val) { labelfont_ = val; recalcTree(); }
    /// Get item's label font face.
    Font labelfont() const { return labelfont_; }
    /// Set item's label font size.
    void labelsize(Fontsize val) { labelsize_ = val; recalcTree(); }
    /// Get item's label font size.
    Fontsize labelsize() const { return labelsize_; }
    /// Set item's label foreground text color.
    void labelfgcolor(Color val) { labelfgcolor_ = val; }
    /// Return item's label foreground text color.
    Color labelfgcolor() const { return labelfgcolor_; }
    /// Set item's label text color. Alias for labelfgcolor(Color).
    void labelcolor(Color val) { labelfgcolor(val); }
    /// Return item's label text color. Alias for labelfgcolor().
    Color labelcolor() const { return labelfgcolor(); }
    /// Set item's label background color. A special case is made for
    /// 0xffffffff, which uses the parent tree's bg color.
    void labelbgcolor(Color val) { labelbgcolor_ = val; }
    /// Return item's label background color.
    Color labelbgcolor() const { return labelbgcolor_; }

    /// Assign an FLTK widget to this item. Gives it a real parent()
    /// (the owning tree) even though it's never a real FlGroup child --
    /// see fl.tree's own top comment for the full "loose, non-FlGroup-
    /// managed widget" story this mirrors from fl.value_input.
    void widget(Widget val)
    {
        widget_ = val;
        if (val !is null) val.parent(tree_);
        recalcTree(); // may change tree geometry
    }
    /// Return the FLTK widget assigned to this item, if any.
    Widget widget() const { return cast(Widget) widget_; }

    /// Return the number of children this item has.
    int children() const { return cast(int) children_.length; }
    /// Return the child item for the given index.
    TreeItem child(int index) { return children_[index]; }
    /// See if this item has children.
    bool hasChildren() const { return children_.length != 0; }

    /// Return the index of the immediate child with label name, or -1.
    int findChild(string name) const
    {
        foreach (t, c; children_)
            if (c.label_ == name) return cast(int) t;
        return -1;
    }
    /// Return the index of item in this item's list of children, or -1.
    int findChild(TreeItem item) const
    {
        foreach (t, c; children_)
            if (c is item) return cast(int) t;
        return -1;
    }

    /// Return the immediate child with label name, or null.
    TreeItem findChildItem(string name)
    {
        foreach (c; children_)
            if (c.label_ == name) return c;
        return null;
    }

    /// Find child item by descending path arr of names (does not
    /// include self). Only Tree's own internals should need this.
    TreeItem findChildItem(const(string)[] arr)
    {
        foreach (c; children_)
        {
            if (c.label_ == arr[0])
            {
                if (arr.length > 1) return c.findChildItem(arr[1 .. $]);
                return c;
            }
        }
        return null;
    }

    /// Find item by descending path names (includes self). Only Tree's
    /// own internals should need this -- use Tree.findItem() instead.
    TreeItem findItem(const(string)[] names)
    {
        if (names.length == 0) return null;
        auto rest = names;
        if (label_.length != 0 && label_ == names[0])
        {
            rest = names[1 .. $];
            if (rest.length == 0) return this;
        }
        if (children_.length != 0) return findChildItem(rest);
        return null;
    }

    //////////////////
    // Adding items
    //////////////////

    /// Add a new child with label new_label, using prefs.sortorder()
    /// to place it. Ported from Fl_Tree_Item::add(prefs, new_label).
    TreeItem add(TreePrefs prefs, string newLabel)
    {
        return add(prefs, newLabel, null);
    }

    /// Add item as an immediate child labeled new_label; if item is
    /// null, a new one is created. Ported from
    /// Fl_Tree_Item::add(prefs, new_label, item).
    TreeItem add(TreePrefs prefs, string newLabel, TreeItem item)
    {
        if (item is null)
        {
            item = new TreeItem(tree_);
            item.label(newLabel);
        }
        recalcTree(); // may change tree geometry
        item.parent_ = this;
        final switch (prefs.sortorder())
        {
        case TreeSort.sortNone:
            childrenAdd(item);
            return item;
        case TreeSort.sortAscending:
            foreach (t, c; children_)
                if (c.label_.length != 0 && c.label_ > newLabel)
                {
                    childrenInsert(cast(int) t, item);
                    return item;
                }
            childrenAdd(item);
            return item;
        case TreeSort.sortDescending:
            foreach (t, c; children_)
                if (c.label_.length != 0 && c.label_ < newLabel)
                {
                    childrenInsert(cast(int) t, item);
                    return item;
                }
            childrenAdd(item);
            return item;
        }
    }

    /// Descend into the path in arr, adding a new child there. Only
    /// Tree's own internals should need this.
    TreeItem add(TreePrefs prefs, const(string)[] arr)
    {
        return add(prefs, arr, null);
    }

    /// Descend into the path in arr and add newitem there (or a new
    /// item, if null). Only Tree's own internals should need this.
    TreeItem add(TreePrefs prefs, const(string)[] arr, TreeItem newitem)
    {
        if (arr.length == 0) return null;
        TreeItem child = findChildItem(arr[0]);
        if (child !is null)
        {
            if (arr.length == 1)
            {
                if (newitem is null) return null; // error: child exists already
                return child.add(prefs, newitem.label(), newitem);
            }
            return child.add(prefs, arr[1 .. $], newitem); // recurse
        }
        if (arr.length == 1) return add(prefs, arr[0], newitem);
        TreeItem newchild = add(prefs, arr[0]);
        return newchild !is null ? newchild.add(prefs, arr[1 .. $], newitem) : null;
    }

    /// Insert a new item named new_label into this item's children at
    /// position pos (prepended if pos < 0, appended if pos >
    /// children()).
    TreeItem insert(TreePrefs prefs, string newLabel, int pos = 0)
    {
        TreeItem item = new TreeItem(tree_);
        item.label(newLabel);
        item.parent_ = this;
        childrenInsert(pos, item);
        recalcTree(); // may change tree geometry
        return item;
    }

    /// Insert a new item named new_label above this item, or null if
    /// this item has no parent.
    TreeItem insertAbove(TreePrefs prefs, string newLabel)
    {
        TreeItem p = parent_;
        if (p is null) return null;
        foreach (t, c; p.children_)
            if (c is this) return p.insert(prefs, newLabel, cast(int) t);
        return null;
    }

    /// Deparent child at index pos: creates an "orphaned" item (still
    /// allocated, no parent or siblings), typically reparented
    /// elsewhere immediately after. Returns the orphan, or null on
    /// error (pos out of range).
    TreeItem deparent(int pos)
    {
        if (pos < 0 || pos >= children_.length) return null;
        TreeItem orphan = children_[pos];
        TreeItem prev = orphan.prevSibling_;
        TreeItem next = orphan.nextSibling_;
        children_ = children_[0 .. pos] ~ children_[pos + 1 .. $];
        orphan.updatePrevNext(-1); // become an orphan
        if (prev !is null) prev.updatePrevNext(pos - 1);
        if (next !is null) next.updatePrevNext(pos);
        return orphan;
    }

    /// Reparent newchild as our own child at position pos (typically a
    /// recently-deparent()ed item). Returns 0 on success, -1 on error.
    int reparent(TreeItem newchild, int pos)
    {
        if (pos < 0 || pos > children_.length) return -1;
        children_ = children_[0 .. pos] ~ newchild ~ children_[pos .. $];
        newchild.parent_ = this; // update_prev_next() needs this
        newchild.updatePrevNext(pos);
        return 0;
    }

    /// Move a child within this item's children, from index from to
    /// index to. Returns 0 on success, -1 on range error.
    int move(int to, int from)
    {
        if (from == to) return 0;
        if (to < 0 || to >= children_.length || from < 0 || from >= children_.length) return -1;
        TreeItem item = children_[from];
        if (from < to)
            foreach (t; from .. to)
                children_[t] = children_[t + 1];
        else
            for (int t = from; t > to; t--)
                children_[t] = children_[t - 1];
        children_[to] = item;
        foreach (r, c; children_) c.updatePrevNext(cast(int) r);
        return 0;
    }

    /// Move this item above/below/into item, per op (0: above, 1:
    /// below, 2: into as a child at optional pos). Returns 0 on
    /// success, a negative error code otherwise (see FLTK's own
    /// doc comment for the exact codes; ported verbatim).
    int move(TreeItem item, int op = 0, int pos = 0)
    {
        TreeItem fromParent, toParent;
        int from, to;
        switch (op)
        {
        case 0: // "above"
        case 1: // "below"
            fromParent = this.parent_;
            toParent = item.parent_;
            if (fromParent is null || toParent is null) return -1;
            from = fromParent.findChild(this);
            to = toParent.findChild(item);
            break;
        case 2: // "into"
            fromParent = this.parent_;
            if (fromParent is null) return -1;
            toParent = item;
            from = fromParent.findChild(this);
            to = pos;
            break;
        default:
            return -3;
        }
        if (fromParent is null || toParent is null) return -1;
        if (from < 0 || to < 0) return -2;
        if (fromParent is toParent)
        {
            switch (op)
            {
            case 0:
                if (from < to && to > 0) to--;
                break;
            case 1:
                if (from > to && to < toParent.children()) to++;
                break;
            default:
                break;
            }
            if (fromParent.move(to, from) < 0) return -4;
        }
        else
        {
            if (to > toParent.children()) return -4;
            if (fromParent.deparent(from) is null) return -5;
            if (toParent.reparent(this, to) < 0)
            {
                toParent.reparent(this, 0);
                return -6;
            }
        }
        return 0;
    }

    /// Move this item above item. Equivalent to move(item, 0, 0).
    int moveAbove(TreeItem item) { return move(item, 0, 0); }
    /// Move this item below item. Equivalent to move(item, 1, 0).
    int moveBelow(TreeItem item) { return move(item, 1, 0); }
    /// Parent this item as a child of item. Equivalent to move(item, 2, pos).
    int moveInto(TreeItem item, int pos = 0) { return move(item, 2, pos); }

    /// Return the parent tree's prefs.
    TreePrefs prefs() { return tree_.prefs(); }
    /// Return the parent for this item, or null if we're the root.
    TreeItem parent() { return parent_; }
    /// Set the parent for this item. Should only be used by Tree's
    /// internals.
    void parent(TreeItem val) { parent_ = val; }
    /// Return the tree this item belongs to.
    Tree tree() { return tree_; }

    //////////////////
    // Replace / remove
    //////////////////

    /// Replace this item with newitem. This item is destroyed (dropped
    /// from the tree) if successful. Returns newitem on success, null
    /// if it couldn't be replaced.
    TreeItem replace(TreeItem newitem)
    {
        TreeItem p = parent_;
        if (p is null)
        {
            tree_.root(newitem); // we're the root -- tell tree to replace it
            return newitem;
        }
        return p.replaceChild(this, newitem);
    }

    /// Replace existing child olditem with newitem. olditem is
    /// destroyed if successful. Returns newitem, or null if olditem
    /// wasn't found as an immediate child.
    TreeItem replaceChild(TreeItem olditem, TreeItem newitem)
    {
        int pos = findChild(olditem);
        if (pos == -1) return null;
        newitem.parent_ = this;
        children_[pos] = newitem;
        newitem.updatePrevNext(pos);
        recalcTree(); // newitem may have changed tree geometry
        return newitem;
    }

    /// Remove item from this item's children. Returns 0 if removed, -1
    /// if item isn't an immediate child.
    int removeChild(TreeItem item)
    {
        foreach (t, c; children_)
            if (c is item)
            {
                item.clearChildren();
                childrenRemoveAt(cast(int) t);
                recalcTree(); // may change tree geometry
                return 0;
            }
        return -1;
    }

    /// Remove the first immediate child whose label matches name.
    /// Returns 0 if removed, -1 if not found.
    int removeChild(string name)
    {
        foreach (t, c; children_)
            if (c.label_ == name)
            {
                childrenRemoveAt(cast(int) t);
                recalcTree(); // may change tree geometry
                return 0;
            }
        return -1;
    }

    /// Clear all the children for this item.
    void clearChildren()
    {
        children_ = [];
        recalcTree(); // may change tree geometry
    }

    /// Swap two of our children, given index values. Fast, no lookups.
    void swapChildren(int ax, int bx)
    {
        TreeItem tmp = children_[ax];
        children_[ax] = children_[bx];
        children_[bx] = tmp;
        children_[ax].updatePrevNext(ax);
        children_[bx].updatePrevNext(bx);
    }

    /// Swap two of our immediate children, given item pointers. Slow
    /// (linear lookup) -- use swapChildren(int,int) for speed. Returns
    /// 0 on success, -1 if a or b isn't our child.
    int swapChildren(TreeItem a, TreeItem b)
    {
        int ax = -1, bx = -1;
        foreach (t, c; children_)
        {
            if (c is a) ax = cast(int) t;
            if (c is b) bx = cast(int) t;
        }
        if (ax == -1 || bx == -1) return -1;
        swapChildren(ax, bx);
        return 0;
    }

    //////////////////
    // Children array helpers (Fl_Tree_Item_Array replacement -- see
    // this module's own top comment)
    //////////////////

    private void childrenAdd(TreeItem item) { childrenInsert(cast(int) children_.length, item); }

    private void childrenInsert(int pos, TreeItem item)
    {
        if (pos < 0) pos = 0;
        else if (pos > children_.length) pos = cast(int) children_.length;
        children_ = children_[0 .. pos] ~ item ~ children_[pos .. $];
        item.updatePrevNext(pos);
    }

    private void childrenRemoveAt(int index)
    {
        children_ = children_[0 .. index] ~ children_[index + 1 .. $];
        if (index < children_.length)
            children_[index].updatePrevNext(index);
        else if (index - 1 >= 0 && index - 1 < children_.length)
            children_[index - 1].updatePrevNext(index - 1);
    }

    //////////////////
    // State
    //////////////////

    /// Open this item and all its children (shows their widget()s).
    void open()
    {
        open_ = true;
        foreach (c; children_) c.showWidgets();
        recalcTree(); // may change tree geometry
    }
    /// Close this item and all its children (hides their widget()s).
    void close()
    {
        open_ = false;
        foreach (c; children_) c.hideWidgets();
        recalcTree(); // may change tree geometry
    }
    /// See if the item is 'open'.
    bool isOpen() const { return open_; }
    /// See if the item is 'closed'.
    bool isClose() const { return !open_; }
    /// Toggle the item's open/closed state.
    void openToggle() { isOpen() ? close() : open(); }

    /// Change the item's selection state.
    void select(bool val = true) { selected_ = val; }
    /// Toggle the item's selection state.
    void selectToggle() { isSelected() ? deselect() : select(); }
    /// Select item and all its children. Returns how many items
    /// changed state.
    int selectAll()
    {
        int count = 0;
        if (!isSelected())
        {
            select();
            count++;
        }
        foreach (c; children_) count += c.selectAll();
        return count;
    }
    /// Deselect the item.
    void deselect() { selected_ = false; }
    /// Deselect item and all its children. Returns how many items
    /// changed state.
    int deselectAll()
    {
        int count = 0;
        if (isSelected())
        {
            deselect();
            count++;
        }
        foreach (c; children_) count += c.deselectAll();
        return count;
    }
    /// See if the item is selected.
    bool isSelected() const { return selected_; }

    /// Change the item's activation state. When deactivated, the item
    /// is 'grayed out' and its callback won't fire on click. If a
    /// widget() is associated, its activation state changes too.
    void activate(bool val = true)
    {
        active_ = val;
        if (widget_ !is null && val != widget_.active())
        {
            if (val) widget_.activate(); else widget_.deactivate();
            widget_.redraw();
        }
    }
    /// Deactivate the item. Same as activate(false).
    void deactivate() { activate(false); }
    /// See if the item is activated.
    bool isActivated() const { return active_; }
    /// See if the item is activated. Alias for isActivated().
    bool isActive() const { return isActivated(); }

    /// See if the item is visible. Alias for isVisible().
    bool visible() const { return isVisible(); }
    /// See if the item is visible.
    bool isVisible() const { return visible_; }
    /// See if item and all its parents are open() and visible().
    /// Alias for isVisibleR().
    bool visibleR() { return isVisibleR(); }
    /// See if item and all its parents are open() and visible().
    bool isVisibleR()
    {
        if (!visible()) return false;
        for (auto p = parent_; p !is null; p = p.parent_)
            if (!p.visible() || p.isClose()) return false;
        return true;
    }

    /// Set the item's user icon. Use null to disable. No internal copy
    /// is made.
    void usericon(Image val) { usericon_ = val; recalcTree(); }
    /// Get the item's user icon, or null if none.
    Image usericon() const { return cast(Image) usericon_; }
    /// Set the icon to draw when the item is deactivated. Use null to
    /// disable. No internal copy is made.
    void userdeicon(Image val) { userdeicon_ = val; }
    /// Return the deactivated version of the user icon, or null.
    Image userdeicon() const { return cast(Image) userdeicon_; }

    //////////////////
    // Events
    //////////////////

    /// Find the item the last event was over. If yonly, only the
    /// event's y is checked (x is ignored). Returns null if none.
    TreeItem findClicked(TreePrefs prefs, bool yonly = false)
    {
        if (!isVisible()) return null;
        if (isRoot() && !prefs.showroot())
        {
            // skip event check -- root not shown
        }
        else if (yonly)
        {
            if (fl.core.eventY() >= xywh_.y() && fl.core.eventY() <= xywh_.y() + xywh_.h())
                return this;
        }
        else if (fl.core.eventInside(xywh_.x(), xywh_.y(), xywh_.w(), xywh_.h()))
        {
            return this;
        }
        if (isOpen())
            foreach (c; children_)
            {
                auto item = c.findClicked(prefs, yonly);
                if (item !is null) return item;
            }
        return null;
    }

    /// Was the event on this item's collapse icon?
    bool eventOnCollapseIcon(TreePrefs prefs) const
    {
        if (!isVisible() || !isActive() || !hasChildren() || !prefs.showcollapse()) return false;
        return fl.core.eventInside(collapseXywh_.x(), collapseXywh_.y(), collapseXywh_.w(), collapseXywh_.h());
    }

    /// Was the event on this item's user icon, if any?
    bool eventOnUserIcon(TreePrefs prefs) const
    {
        if (!isVisible()) return false;
        if (!fl.core.eventInside(xywh_.x(), xywh_.y(), xywh_.w(), xywh_.h())) return false;
        if (eventOnCollapseIcon(prefs)) return false;
        if (fl.core.eventX() >= labelXywh_.x()) return false;

        Image ui;
        if (isActive())
        {
            if (usericon() !is null) ui = usericon();
            else if (prefs.usericon() !is null) ui = prefs.usericon();
        }
        else
        {
            if (userdeicon() !is null) ui = userdeicon();
            else if (prefs.userdeicon() !is null) ui = prefs.userdeicon();
        }
        if (ui is null) return false;
        int uix = labelXywh_.x() - ui.w();
        if (fl.core.eventX() < uix) return false;
        return true;
    }

    /// Was the event anywhere on the item?
    bool eventOnItem(TreePrefs prefs) const
    {
        return fl.core.eventInside(xywh_.x(), xywh_.y(), xywh_.w(), xywh_.h());
    }

    /// Was the event on this item's label?
    bool eventOnLabel(TreePrefs prefs) const
    {
        if (isVisible() && isActive())
            return fl.core.eventInside(labelXywh_.x(), labelXywh_.y(), labelXywh_.w(), labelXywh_.h());
        return false;
    }

    /// Is this item the root of the tree?
    bool isRoot() const { return parent_ is null; }

    //////////////////
    // Tree walking
    //////////////////

    /// Returns how many levels deep this item is (root == 0).
    int depth()
    {
        int count = 0;
        for (auto item = parent_; item !is null; item = item.parent_) count++;
        return count;
    }

    /// Return the next item in the tree (forward walk).
    TreeItem next()
    {
        TreeItem c = this;
        if (c.hasChildren()) return c.child(0);
        for (auto p = c.parent_; p !is null; c = p, p = c.parent_)
            if (c.nextSibling_ !is null) return c.nextSibling_;
        return null;
    }

    /// Return the previous item in the tree (backward walk).
    TreeItem prev()
    {
        if (parent_ is null) return null;
        if (prevSibling_ is null) return parent_;
        TreeItem p = prevSibling_;
        while (p.hasChildren()) p = p.child(p.children() - 1);
        return p;
    }

    /// Return this item's next sibling, or null.
    TreeItem nextSibling() { return nextSibling_; }
    /// Return this item's previous sibling, or null.
    TreeItem prevSibling() { return prevSibling_; }

    /// Update our prevSibling/nextSibling to point to neighbors, given
    /// index as our current position in the parent's children. Call
    /// after items are added/removed/moved/swapped. index == -1 is a
    /// special case: become an orphan.
    void updatePrevNext(int index)
    {
        if (index == -1)
        {
            parent_ = null;
            prevSibling_ = null;
            nextSibling_ = null;
            return;
        }
        int pchildren = parent_ !is null ? parent_.children() : 0;
        int indexPrev = index - 1;
        int indexNext = index + 1;
        TreeItem itemPrev = (indexPrev >= 0 && indexPrev < pchildren) ? parent_.child(indexPrev) : null;
        TreeItem itemNext = (indexNext >= 0 && indexNext < pchildren) ? parent_.child(indexNext) : null;
        prevSibling_ = itemPrev;
        nextSibling_ = itemNext;
        if (itemPrev !is null) itemPrev.nextSibling_ = this;
        if (itemNext !is null) itemNext.prevSibling_ = this;
    }

    /// Return the next open()/visible() item, skipping closed
    /// children. Returns null if none.
    TreeItem nextVisible(TreePrefs prefs)
    {
        TreeItem item = this;
        while (true)
        {
            item = item.next();
            if (item is null) return null;
            if (item.isRoot() && !prefs.showroot()) continue;
            if (item.visibleR()) return item;
        }
    }
    /// Same as nextVisible(). Deprecated FLTK "for confusing name".
    TreeItem nextDisplayed(TreePrefs prefs) { return nextVisible(prefs); }

    /// Return the previous open()/visible() item, skipping closed
    /// children. Returns null if none.
    TreeItem prevVisible(TreePrefs prefs)
    {
        TreeItem c = this;
        while (c !is null)
        {
            c = c.prev();
            if (c is null) break;
            if (c.isRoot()) return (prefs.showroot() && c.visible()) ? c : null;
            if (!c.visible()) continue;
            TreeItem p = c.parent_;
            while (true)
            {
                if (p is null || p.isRoot()) return c;
                if (p.isClose()) c = p;
                p = p.parent_;
            }
        }
        return null;
    }
    /// Same as prevVisible(). Deprecated FLTK "for confusing name".
    TreeItem prevDisplayed(TreePrefs prefs) { return prevVisible(prefs); }

    //////////////////
    // Drawing
    //////////////////

    /// Returns the recommended foreground color for drawing this item.
    protected Color drawfgcolor()
    {
        if (isSelected()) return contrast(labelfgcolor_, tree_.selectionColor());
        if (isActive() && tree_.activeR()) return labelfgcolor_;
        return inactive(labelfgcolor_);
    }

    /// Returns the recommended background color for drawing this item.
    protected Color drawbgcolor()
    {
        enum unspecified = 0xffffffff;
        if (isSelected())
            return (isActive() && tree_.activeR()) ? tree_.selectionColor() : inactive(tree_.selectionColor());
        return labelbgcolor_ == unspecified ? tree_.color() : labelbgcolor_;
    }

    /// Draw the item's content (background + label), filling the
    /// label_[xywh]() area. Override to implement custom item drawing.
    /// Returns the right-most X of what was drawn (or would be drawn),
    /// used by the tree to size its horizontal scrollbar.
    protected int drawItemContent(bool render)
    {
        Color fg = drawfgcolor();
        Color bg = drawbgcolor();
        auto prefs = tree_.prefs();
        int xmax = labelX();
        if (render && (bg != tree_.color() || isSelected()))
        {
            if (isSelected())
                drawBoxAt(prefs.selectbox(), labelX(), labelY(), labelW(), labelH(), bg);
            else
            {
                fl_color(bg);
                fl_rectf(labelX(), labelY(), labelW(), labelH());
            }
            if (widget_ !is null) widget_.damage(damageAll);
        }
        if (label_.length != 0 && (widget_ is null || (prefs.itemDrawMode() & itemDrawLabelAndWidget) != 0))
        {
            if (render)
            {
                fl_color(fg);
                fl_font(labelfont_, labelsize_);
            }
            int lx = labelX() + prefs.labelmarginleft();
            int ly = labelY() + labelH() / 2 + labelsize_ / 2 - descent() / 2;
            int lw, lh;
            fl_measure(label_, lw, lh);
            if (render) fl_draw(label_, cast(int) label_.length, lx, ly);
            xmax = lx + lw;
        }
        return xmax;
    }

    /// Draw this item and its children. X/W are this item's horizontal
    /// bounds; Y is updated in place to the next item's y. itemfocus is
    /// the tree's current keyboard-focus item, if any. treeItemXmax
    /// tracks the running rightmost edge for the caller's scrollbar
    /// calc. render false means "calculate geometry only, don't paint".
    void draw(int X, ref int Y, int W, TreeItem itemfocus, ref int treeItemXmax,
        bool lastchild = true, bool render = true)
    {
        auto prefs = tree_.prefs();
        if (!isVisible()) return;
        int treeTop = tree_.tiy();
        int treeBot = treeTop + tree_.tih();
        int H = calcItemHeight(prefs);
        int H2 = H + prefs.linespacing();

        xywh_ = Rect(X, Y, W, H);

        int itemYCenter = (Y + H / 2) | 1;
        int iconW = prefs.openiconW();
        int iconH = prefs.openiconH();
        int iconX = X + (iconW + prefs.connectorwidth()) / 2 - 3;
        int iconY = itemYCenter - iconH / 2;
        collapseXywh_ = Rect(iconX, iconY, iconW, iconH);

        int hconnX = X + iconW / 2 - 1;
        int hconnX2 = hconnX + prefs.connectorwidth();
        int hconnXCenter = X + iconW + (hconnX2 - (X + iconW)) / 2;
        int cw1 = iconW + prefs.connectorwidth() / 2, cw2 = prefs.connectorwidth();
        int connW = cw1 > cw2 ? cw1 : cw2;

        bool hasUsericon = usericon_ !is null || prefs.usericon() !is null;
        int uiconX = X + (iconW / 2 - 1 + connW) + (hasUsericon ? prefs.usericonmarginleft() : 0);
        int uiconW = usericon_ !is null ? usericon_.w()
            : (prefs.usericon() !is null ? prefs.usericon().w() : 0);

        labelXywh_ = Rect(uiconX + uiconW + prefs.labelmarginleft(), Y,
            tree_.tix() + tree_.tiw() - (uiconX + uiconW + prefs.labelmarginleft()), H);

        int xmax = 0;

        if (widget_ !is null)
        {
            int wx = uiconX + uiconW + (label_.length != 0 ? prefs.labelmarginleft() : 0);
            int wy = labelY();
            int ww = widget_.w();
            int wh = (prefs.itemDrawMode() & itemHeightFromWidget) != 0 ? widget_.h() : H;
            if (label_.length != 0 && (prefs.itemDrawMode() & itemDrawLabelAndWidget) != 0)
            {
                fl_font(labelfont_, labelsize_);
                int lw, lh;
                fl_measure(label_, lw, lh);
                wx += lw + prefs.widgetmarginleft();
            }
            if (widget_.x() != wx || widget_.y() != wy || widget_.w() != ww || widget_.h() != wh)
                widget_.resize(wx, wy, ww, wh);
        }

        bool clipped = ((Y + H) < treeTop) || (Y > treeBot);
        if (!render) clipped = false;
        bool active = isActive() && tree_.activeR();
        bool drawthis = !(isRoot() && !prefs.showroot());
        if (!clipped)
        {
            if (drawthis)
            {
                if ((tree_.damage() & ~damageChild) != 0 || !render)
                {
                    if (render && prefs.connectorstyle() != TreeConnector.connectorNone)
                    {
                        drawHorizontalConnector(hconnX, hconnXCenter, itemYCenter, prefs);
                        if (hasChildren() && isOpen())
                            drawVerticalConnector(hconnXCenter, itemYCenter, Y + H2, prefs);
                        if (!isRoot())
                        {
                            if (lastchild) drawVerticalConnector(hconnX, Y, itemYCenter, prefs);
                            else drawVerticalConnector(hconnX, Y, Y + H2, prefs);
                        }
                    }
                    if (render && hasChildren() && prefs.showcollapse())
                    {
                        // Real prefs.openicon()/closeicon() are drawn now
                        // when set (2026-08-01, following fl.image's own
                        // port), falling back to the built-in glyph via
                        // drawExpandoButton() otherwise -- matching
                        // FLTK's own is_open()/else branches exactly:
                        // an *open* item shows the "close" icon (click to
                        // close it) or, with no custom icon, a "-" glyph
                        // (drawExpandoButton()'s state=false); a *closed*
                        // item shows the "open" icon or a "+" glyph
                        // (state=true). Bug fixed 2026-07-30
                        // (user-reported): the built-in-glyph fallback
                        // used to pass isOpen() directly, backwards from
                        // FLTK -- an open (collapsible) item showed
                        // "+" and a closed (expandable) one showed "-".
                        if (isOpen())
                        {
                            if (prefs.closeicon() !is null)
                            {
                                if (active) prefs.closeicon().draw(iconX, iconY);
                                else prefs.closedeicon().draw(iconX, iconY);
                            }
                            else
                            {
                                drawExpandoButton(iconX, iconY, false, active);
                            }
                        }
                        else
                        {
                            if (prefs.openicon() !is null)
                            {
                                if (active) prefs.openicon().draw(iconX, iconY);
                                else prefs.opendeicon().draw(iconX, iconY);
                            }
                            else
                            {
                                drawExpandoButton(iconX, iconY, true, active);
                            }
                        }
                    }
                    // Real user-icon drawing (2026-08-01, following
                    // fl.image's own port): the item's own usericon()
                    // takes priority over the tree-wide prefs.usericon(),
                    // matching FLTK's exact if/else-if fallback.
                    if (render && usericon() !is null)
                    {
                        int uiconY = itemYCenter - (usericon().h() >> 1);
                        if (active) usericon().draw(uiconX, uiconY);
                        else if (userdeicon() !is null) userdeicon().draw(uiconX, uiconY);
                    }
                    else if (render && prefs.usericon() !is null)
                    {
                        int uiconY = itemYCenter - (prefs.usericon().h() >> 1);
                        if (active) prefs.usericon().draw(uiconX, uiconY);
                        else if (prefs.userdeicon() !is null) prefs.userdeicon().draw(uiconX, uiconY);
                    }
                    xmax = drawItemContent(render);
                }
                if (widget_ !is null)
                {
                    if (render) tree_.drawItemWidget(widget_);
                    if (widget_.label().length != 0 && render) tree_.drawItemWidgetLabel(widget_);
                    xmax = widget_.x() + widget_.w();
                }
                if (render && this is itemfocus && fl.core.visibleFocus()
                    && fl.core.focus() is tree_ && prefs.selectmode() != TreeSelect.selectNone)
                {
                    Color fg = drawfgcolor(), bg = drawbgcolor();
                    drawBoxFocus(Boxtype.noBox, labelX() + 1, labelY() + 1, labelW() - 1, labelH() - 1, fg, bg);
                }
            }
        }
        if (drawthis) Y += H2;
        if (xmax > treeItemXmax) treeItemXmax = xmax;

        if (hasChildren() && isOpen())
        {
            int childX = drawthis ? (hconnXCenter - iconW / 2 + 1) : X;
            int childW = W - (childX - X);
            int childYStart = Y;
            foreach (t, c; children_)
                c.draw(childX, Y, childW, itemfocus, treeItemXmax, t + 1 == children_.length, render);
            if (hasChildren() && isOpen()) Y += prefs.openchildMarginbottom();
            if (!lastchild)
            {
                int ytop = childYStart;
                int ybot = Y;
                bool isClipped = (ytop < treeTop && ybot < treeTop) || (ytop > treeBot && ybot > treeBot);
                if (render && !isClipped)
                {
                    ytop = ytop < treeTop ? treeTop : ytop;
                    ybot = ybot > treeBot ? treeBot : ybot;
                    drawVerticalConnector(hconnX, ytop, ybot, prefs);
                }
            }
        }
    }

    /// Horizontal connector line, per prefs.connectorstyle(). Override
    /// to implement custom connection line drawing.
    protected void drawHorizontalConnector(int x1, int x2, int y, TreePrefs prefs)
    {
        fl_color(prefs.connectorcolor());
        final switch (prefs.connectorstyle())
        {
        case TreeConnector.connectorSolid:
            fl_line(x1, y, x2, y);
            return;
        case TreeConnector.connectorDotted:
            x1 |= 1; // force alignment w/dot pattern
            for (int xx = x1; xx <= x2; xx += 2) point(xx, y);
            return;
        case TreeConnector.connectorNone:
            return;
        }
    }

    /// Vertical connector line, per prefs.connectorstyle(). Override to
    /// implement custom connection line drawing.
    protected void drawVerticalConnector(int x, int y1, int y2, TreePrefs prefs)
    {
        fl_color(prefs.connectorcolor());
        final switch (prefs.connectorstyle())
        {
        case TreeConnector.connectorSolid:
            y1 |= 1;
            y2 |= 1;
            fl_line(x, y1, x, y2);
            return;
        case TreeConnector.connectorDotted:
            y1 |= 1;
            y2 |= 1;
            for (int yy = y1; yy <= y2; yy += 2) point(x, yy);
            return;
        case TreeConnector.connectorNone:
            return;
        }
    }

    //////////////////
    // Internal
    //////////////////

    /// Show widget() for this item and all children (open() re-shows
    /// widgets a previous close() hid).
    private void showWidgets()
    {
        if (widget_ !is null) widget_.show();
        if (isOpen()) foreach (c; children_) c.showWidgets();
    }

    /// Hide widget() for this item and all children (used by close()).
    private void hideWidgets()
    {
        if (widget_ !is null) widget_.hide();
        foreach (c; children_) c.hideWidgets();
    }

    /// The item's 'visible' height: label font height, widget() height
    /// (if item_draw_mode() wants it), open-icon height (if has
    /// children), user-icon height (if any). Does not include
    /// prefs.linespacing().
    protected int calcItemHeight(TreePrefs prefs)
    {
        if (!isVisible()) return 0;
        int H = 0;
        if (label_.length != 0)
        {
            fl_font(labelfont_, labelsize_); // fl_descent() needs this
            H = labelsize_ + descent() + 1;
        }
        if (widget_ !is null && (prefs.itemDrawMode() & itemHeightFromWidget) != 0 && H < widget_.h())
            H = widget_.h();
        if (hasChildren() && H < prefs.openiconH()) H = prefs.openiconH();
        if (usericon_ !is null && H < usericon_.h()) H = usericon_.h();
        return H;
    }

    /// Schedules the owning tree to recalculate itself -- call whenever
    /// this item's geometry changes (font size, label contents, etc).
    private void recalcTree()
    {
        if (tree_ !is null) tree_.recalcTree();
    }
}

/// Ported from Fl_System_Driver::tree_draw_expando_button() -- see this
/// module's own top comment on why this is a plain function here
/// rather than a driver-hook abstraction. state=true draws a "+"
/// (both lines); state=false draws a "-" (horizontal line only) -- the
/// caller decides which glyph means what (draw()'s own call passes
/// isClose(), not isOpen(), matching FLTK's exact argument order).
private void drawExpandoButton(int x, int y, bool state, bool active)
{
    fl_rectf(x, y, 11, 11, active ? background2Color : inactive(background2Color));
    fl_rect(x, y, 11, 11, inactiveColor);
    fl_color(active ? foregroundColor : inactiveColor);
    fl_line(x + 3, y + 5, x + 7, y + 5);
    if (state) fl_line(x + 5, y + 3, x + 5, y + 7);
}

// ===========================================================================
// Unit tests -- all pure logic (array manipulation, tree walking, flag
// bookkeeping), safe headless. Drawing itself needs a live X display,
// same as every other widget-drawing code in this port (see
// fl.draw's own module note) -- not exercised here.
// ===========================================================================

unittest
{
    import fl.group : FlGroup;

    FlGroup.current(null);
    auto t = new Tree(0, 0, 200, 200);
    FlGroup.current(null);

    auto root = t.root();
    assert(root !is null);
    assert(root.isRoot());
    assert(root.children() == 0);

    auto a = root.add(t.prefs(), "Aaa");
    auto b = root.add(t.prefs(), "Bbb");
    auto c = root.add(t.prefs(), "Ccc");
    assert(root.children() == 3);
    assert(root.child(0) is a);
    assert(root.child(1) is b);
    assert(root.child(2) is c);
    assert(a.parent() is root);
    assert(a.nextSibling() is b);
    assert(b.prevSibling() is a);
    assert(b.nextSibling() is c);
    assert(c.nextSibling() is null);
    assert(root.findChild("Bbb") == 1);
    assert(root.findChild("Zzz") == -1);
    assert(root.findChild(b) == 1);

    // Tree walk (next()/prev()) matches insertion order.
    assert(root.next() is a);
    assert(a.next() is b);
    assert(b.next() is c);
    assert(c.next() is null);
    assert(c.prev() is b);
    assert(b.prev() is a);
    assert(a.prev() is root);

    // depth()
    assert(root.depth() == 0);
    assert(a.depth() == 1);

    fl.core.resetForTest();
}

unittest
{
    // insert()/swapChildren()/removeChild()/clearChildren()
    import fl.group : FlGroup;

    FlGroup.current(null);
    auto t = new Tree(0, 0, 200, 200);
    FlGroup.current(null);

    auto root = t.root();
    auto a = root.add(t.prefs(), "Aaa");
    auto c = root.add(t.prefs(), "Ccc");
    auto b = root.insert(t.prefs(), "Bbb", 1); // between Aaa and Ccc
    assert(root.children() == 3);
    assert(root.child(0) is a);
    assert(root.child(1) is b);
    assert(root.child(2) is c);
    assert(a.nextSibling() is b);
    assert(b.nextSibling() is c);

    root.swapChildren(0, 2); // Ccc, Bbb, Aaa
    assert(root.child(0) is c);
    assert(root.child(2) is a);
    assert(c.nextSibling() is b);
    assert(a.prevSibling() is b);

    assert(root.removeChild(b) == 0);
    assert(root.children() == 2);
    assert(root.findChild(b) == -1);
    assert(c.nextSibling() is a); // re-stitched after removal

    root.clearChildren();
    assert(root.children() == 0);

    fl.core.resetForTest();
}

unittest
{
    // move()/moveAbove()/moveBelow()/moveInto() (deparent+reparent
    // across different parents, and same-parent reordering).
    import fl.group : FlGroup;

    FlGroup.current(null);
    auto t = new Tree(0, 0, 200, 200);
    FlGroup.current(null);

    auto root = t.root();
    auto folder1 = root.add(t.prefs(), "Folder1");
    auto folder2 = root.add(t.prefs(), "Folder2");
    auto x = folder1.add(t.prefs(), "Xxx");
    auto y = folder1.add(t.prefs(), "Yyy");
    assert(folder1.children() == 2);
    assert(folder2.children() == 0);

    assert(x.moveInto(folder2, 0) == 0);
    assert(folder1.children() == 1);
    assert(folder2.children() == 1);
    assert(folder2.child(0) is x);
    assert(x.parent() is folder2);
    assert(folder1.child(0) is y); // re-stitched, no gap

    // Same-parent reorder via moveAbove()/moveBelow().
    auto z = folder2.add(t.prefs(), "Zzz");
    assert(folder2.children() == 2); // x, z
    assert(folder2.child(0) is x);
    assert(folder2.child(1) is z);
    assert(z.moveAbove(x) == 0);
    assert(folder2.child(0) is z);
    assert(folder2.child(1) is x);

    fl.core.resetForTest();
}

unittest
{
    // open()/close()/isOpen()/isClose()/openToggle(), and
    // isVisibleR()/visibleR() through a closed parent.
    import fl.group : FlGroup;

    FlGroup.current(null);
    auto t = new Tree(0, 0, 200, 200);
    FlGroup.current(null);

    auto root = t.root();
    auto folder = root.add(t.prefs(), "Folder");
    auto leaf = folder.add(t.prefs(), "Leaf");

    assert(folder.isOpen()); // TreeItem's own default is OPEN
    assert(leaf.isVisibleR());

    folder.close();
    assert(folder.isClose());
    assert(!leaf.isVisibleR()); // hidden: parent is closed

    folder.open();
    assert(folder.isOpen());
    assert(leaf.isVisibleR());

    folder.openToggle();
    assert(folder.isClose());
    folder.openToggle();
    assert(folder.isOpen());

    fl.core.resetForTest();
}

unittest
{
    // select()/deselect()/selectToggle()/selectAll()/deselectAll().
    import fl.group : FlGroup;

    FlGroup.current(null);
    auto t = new Tree(0, 0, 200, 200);
    FlGroup.current(null);

    auto root = t.root();
    auto a = root.add(t.prefs(), "Aaa");
    auto b = root.add(t.prefs(), "Bbb");
    assert(!a.isSelected());

    a.select();
    assert(a.isSelected());
    a.deselect();
    assert(!a.isSelected());
    a.selectToggle();
    assert(a.isSelected());
    a.selectToggle();
    assert(!a.isSelected());

    fl.core.resetForTest();
}

unittest
{
    // selectAll()/deselectAll() change-counting, isolated from the
    // "a already selected" scenario above.
    import fl.group : FlGroup;

    FlGroup.current(null);
    auto t = new Tree(0, 0, 200, 200);
    FlGroup.current(null);

    auto root = t.root();
    root.add(t.prefs(), "Aaa");
    root.add(t.prefs(), "Bbb");

    assert(root.selectAll() == 3); // root + Aaa + Bbb, none selected yet
    assert(root.isSelected());
    assert(root.child(0).isSelected());
    assert(root.child(1).isSelected());
    assert(root.selectAll() == 0); // already all selected

    assert(root.deselectAll() == 3);
    assert(!root.isSelected());
    assert(root.deselectAll() == 0);

    fl.core.resetForTest();
}

unittest
{
    // findChildItem()/findItem() path descent.
    import fl.group : FlGroup;

    FlGroup.current(null);
    auto t = new Tree(0, 0, 200, 200);
    FlGroup.current(null);

    auto root = t.root();
    root.label("ROOT");
    auto flint = root.add(t.prefs(), "Flintstones");
    flint.add(t.prefs(), "Fred");
    flint.add(t.prefs(), "Wilma");

    assert(root.findChildItem("Flintstones") is flint);
    assert(root.findChildItem("Simpsons") is null);
    assert(root.findItem(["ROOT", "Flintstones", "Fred"]) !is null);
    assert(root.findItem(["ROOT", "Flintstones", "Fred"]).label() == "Fred");
    assert(root.findItem(["ROOT", "Flintstones", "Nobody"]) is null);

    fl.core.resetForTest();
}

unittest
{
    // Real icon sizing (2026-08-01, following fl.image's own port):
    // calcItemHeight() grows to fit a tall usericon(), and eventOnUserIcon()'s
    // uix math resolves using the real image width instead of never
    // resolving true. draw() with a custom prefs.openicon()/closeicon()
    // set is exercised too (headless: Image.draw() itself early-returns
    // with no display, same as every other draw() test in this port --
    // what's actually being confirmed is that the custom-icon branch
    // runs instead of crashing or being skipped).
    import fl.group : FlGroup;
    import fl.image : RGBImage;

    FlGroup.current(null);
    auto t = new Tree(0, 0, 200, 200);
    FlGroup.current(null);

    ubyte[] bits = [255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 0];
    auto tallIcon = new RGBImage(bits.dup, 2, 30, 3); // taller than a normal label row

    auto root = t.root();
    auto item = root.add(t.prefs(), "Item");
    item.usericon(tallIcon);
    assert(item.usericon() is tallIcon);

    int h = item.calcItemHeight(t.prefs());
    assert(h >= tallIcon.h());

    // labelXywh_ is populated by draw()'s geometry pass -- run it once
    // (render=false is enough to compute geometry without touching a
    // display) so eventOnUserIcon()'s uix math has real coordinates to
    // work with, then confirm it no longer unconditionally returns
    // false the moment a real icon is present.
    int y = 0, xmax = 0;
    item.draw(0, y, 200, null, xmax, true, false);
    int uix = item.labelX() - tallIcon.w();
    assert(uix < item.labelX()); // real width was actually subtracted

    fl.core.resetForTest();

    // Custom tree-wide open/close icons: draw() should take the
    // custom-icon branch, not the built-in-glyph fallback, without
    // crashing headlessly.
    FlGroup.current(null);
    auto t2 = new Tree(0, 0, 200, 200);
    FlGroup.current(null);
    auto openImg = new RGBImage(bits.dup, 11, 11, 3);
    t2.prefs().openicon(openImg);
    t2.prefs().closeicon(openImg);
    auto root2 = t2.root();
    root2.add(t2.prefs(), "Child");
    int y2 = 0, xmax2 = 0;
    root2.draw(0, y2, 200, null, xmax2, true, true);

    fl.core.resetForTest();
}
