/*
 * Ported from FL/Fl_Tree.H + src/Fl_Tree.cxx (FLTK 1.5.0). A FlGroup-derived hierarchical list/browser of
 * TreeItems, with vertical/horizontal scrollbars, open/close subtrees,
 * several selection modes, and keyboard navigation.
 *
 * Deviations from FLTK, all deliberate:
 *
 *  - **No separate `Fl_Tree_Reason` enum.** FLTK's own header
 *    defines every `FL_TREE_REASON_*` value as a literal alias of the
 *    generic `FL_REASON_*` constant (`FL_TREE_REASON_SELECTED =
 *    FL_REASON_SELECTED`, etc. -- `do_callback_for_item()` even casts
 *    an `Fl_Tree_Reason` straight to `Fl_Callback_Reason`), so it's
 *    already just a renamed view of the same value space, not a
 *    distinct one. This port uses `fl.enumerations.CallbackReason`
 *    directly for `callbackReason()` -- it already has
 *    `selected`/`deselected`/`reselected`/`opened`/`closed`/`dragged`,
 *    the exact same six values `Fl_Tree_Reason` names, so declaring a
 *    second, redundant D enum with the same members would add nothing.
 *  - **Path-taking overloads return `string`, not `char*`+`len`.**
 *    `item_pathname(char*, int, item)` becomes `itemPathname(item)`
 *    returning a plain `string` -- the usual "D string over
 *    caller-managed buffer" substitution `CONVENTIONS.md` documents for
 *    `Widget.label()`/etc. `parse_path()`/`free_path()` (FLTK's
 *    manual `char**` splitting with matching manual frees) becomes a
 *    private, pure `parsePath()` returning `string[]`, no explicit
 *    cleanup needed.
 *  - **`get_selected_items(Fl_Tree_Item_Array&)` becomes
 *    `selectedItems()` returning `TreeItem[]`** directly, instead of
 *    filling an out-parameter array wrapper that no longer exists in
 *    this port (see `fl.tree_item`'s own top comment on why
 *    `Fl_Tree_Item_Array` isn't ported as its own class at all).
 *  - **`load(Fl_Preferences&)` is real** -- see `load()` below, a
 *    faithful port.
 *  - **`resize()`'s `auto_resize_children()` branch is simplified.**
 *    FLTK calls either `Fl_Group::resize()` (children move/scale
 *    with the group) or plain `Fl_Widget::resize()` (children
 *    untouched) depending on the flag -- a real C++ dispatch choice
 *    between two ancestor classes' methods that D's `super.resize()`
 *    can't directly express past the immediate base (`FlGroup`, not
 *    `Widget`). In practice this only matters for a widget a caller
 *    manually added as a genuine `FlGroup` child of the `Tree` via the
 *    inherited `add()`/`insert()` (TreeItem's own `widget()` is never
 *    a real `FlGroup` child either way -- see `fl.tree_item`'s own top
 *    comment), and even then, `calcDimensions()` (called right after,
 *    in both branches, both here and FLTK) unconditionally
 *    recomputes both scrollbars' own geometry regardless of what
 *    `resize()` did to them -- so for this port's default (and by far
 *    most common) configuration the two branches are behaviorally
 *    identical. This port always takes the `FlGroup.resize()` path;
 *    `autoResizeChildren(true)` additionally calls `initSizes()`
 *    (matching FLTK's own pairing), the one part of the flag's
 *    behavior that *is* still faithfully preserved.
 */
module fl.tree;

import fl.enumerations;
import fl.group : FlGroup;
import fl.widget : Widget;
import fl.scrollbar : Scrollbar;
import fl.slider : horSlider, vertSlider;
import fl.rect : Rect;
import fl.image : Image;
import fl.tree_prefs;
import fl.tree_item : TreeItem;
import fl.draw;
import fl.core;
import prefsmod = fl.preferences;

private enum { pushedNone, pushedOpenClose, pushedUserIcon, pushedLabel }

/**
 * Tree widget: a hierarchical browser of TreeItems, arranged in a
 * parented "tree". Subtrees can be open/closed; items can be added,
 * removed, inserted, sorted, reordered, and selected in several modes.
 * Items may also embed other FLTK widgets. Ported from `Fl_Tree`.
 */
class Tree : FlGroup
{
    private TreeItem root_;
    private TreeItem itemFocus_;
    private TreeItem callbackItem_;
    private CallbackReason callbackReason_ = CallbackReason.unknown;
    private TreePrefs prefs_;
    private int scrollbarSize_ = 0;
    private TreeItem lastselect_;
    private int lastpushed_ = pushedNone;
    private bool autoResizeChildren_ = false;

    protected Scrollbar vscroll_;
    protected Scrollbar hscroll_;
    protected int tox_, toy_, tow_, toh_;
    protected int tix_, tiy_, tiw_, tih_;
    protected int treeW_ = -1;
    protected int treeH_ = -1;

    this(int X, int Y, int W, int H, string L = null)
    {
        super(X, Y, W, H, L);
        prefs_ = new TreePrefs();
        root_ = new TreeItem(this);
        root_.parent(null);
        root_.label("ROOT");

        box(Boxtype.downBox);
        // Qualified: bare `selectionColor` here would resolve to the
        // inherited Widget.selectionColor() *method* (shadowing the
        // fl.enumerations manifest constant of the same name), returning
        // the not-yet-set default (gray) right back into its own setter
        // -- a real bug, found interactively (fldtk's tree selection
        // rendered gray/black instead of FLTK's blue/white) and
        // confirmed by reading Fl_Widget.cxx's real default alongside
        // this constructor.
        color(background2Color, fl.enumerations.selectionColor);
        when(whenChanged);

        int scrollsize = scrollbarSize_ ? scrollbarSize_ : fl.core.scrollbarSize();
        // Constructed while FlGroup's ctor has already called begin(), so
        // these auto-parent into this Tree as its only two real FlGroup
        // children -- TreeItems themselves never are, see
        // fl.tree_item's own top comment.
        vscroll_ = new Scrollbar(X + W - scrollsize, Y, scrollsize, H);
        vscroll_.hide();
        vscroll_.type(vertSlider);
        vscroll_.step(1);
        vscroll_.callback((w) { redraw(); });
        hscroll_ = new Scrollbar(X, Y + H - scrollsize, W, scrollsize);
        hscroll_.hide();
        hscroll_.type(horSlider);
        hscroll_.step(1);
        hscroll_.callback((w) { redraw(); });

        tox_ = tix_ = X + fl.core.boxDx(box());
        toy_ = tiy_ = Y + fl.core.boxDy(box());
        tow_ = tiw_ = W - fl.core.boxDw(box());
        toh_ = tih_ = H - fl.core.boxDh(box());
        treeW_ = -1;
        treeH_ = -1;
        end();
    }

    /// Enable/disable automatically resizing children when the Tree
    /// container itself is resized (default: false). See this module's
    /// own top comment for the one simplification here.
    void autoResizeChildren(bool mode) { autoResizeChildren_ = mode; }
    /// See autoResizeChildren(bool).
    bool autoResizeChildren() const { return autoResizeChildren_; }

    ///////////////////////
    // root methods
    ///////////////////////

    /// Set the label for the root item.
    void rootLabel(string newLabel) { if (root_ !is null) root_.label(newLabel); }
    /// Returns the root item, or null.
    TreeItem root() { return root_; }
    /// Sets the root item to newitem. If a root already exists,
    /// clear() runs first. Use to install a custom TreeItem subclass
    /// as the root.
    void root(TreeItem newitem)
    {
        if (root_ !is null) clear();
        root_ = newitem;
    }
    /// Return the tree's preferences (fonts, colors, margins, icons,
    /// selection/connector style).
    TreePrefs prefs() { return prefs_; }
    /// ditto
    const(TreePrefs) prefs() const { return prefs_; }

    ////////////////////////////////
    // Item creation/removal methods
    ////////////////////////////////

    /// Add a new item given a menu-style path (e.g. "Flintstones/Fred"),
    /// creating any missing parent nodes automatically. If item is
    /// null, a new one is created. Returns the item added, or null on
    /// error.
    TreeItem add(string path, TreeItem item = null)
    {
        if (root_ is null)
        {
            root_ = new TreeItem(this);
            root_.parent(null);
            root_.label("ROOT");
        }
        return root_.add(prefs_, parsePath(path), item);
    }
    /// Add a new child item labeled name to parentItem.
    TreeItem add(TreeItem parentItem, string name) { return parentItem.add(prefs_, name); }
    /// Add a pre-constructed item (e.g. a `TreeItem` subclass with its
    /// own custom `drawItemContent()`/`calcItemHeight()`) as a new
    /// child of parentItem, labeled name.
    TreeItem add(TreeItem parentItem, string name, TreeItem item) { return parentItem.add(prefs_, name, item); }
    /// Insert a new item named name above item above.
    TreeItem insertAbove(TreeItem above, string name) { return above.insertAbove(prefs_, name); }
    /// Insert a new item named name into item's children at pos.
    TreeItem insert(TreeItem item, string name, int pos) { return item.insert(prefs_, name, pos); }

    /// Loads (visualizes) a `fl.preferences.Preferences` database as a
    /// tree: each group becomes a subtree (recursively), each key/value
    /// entry becomes a leaf item labeled "key = value" (truncated past
    /// 40 characters), and any `/` in a key or value is replaced with
    /// `\` first, since `/` is this tree's own path separator. Ported
    /// from `Fl_Tree::load(Fl_Preferences&)` (`src/Fl_Tree.cxx`) --
    /// mainly a debugging/inspection aid for visualizing a preferences
    /// database, not a general persistence mechanism (FLTK has no
    /// matching `save(Fl_Preferences&)` either). The `prefsmod` import
    /// alias avoids colliding with this class's own `prefs_`/`prefs()`
    /// (`fl.tree_prefs.TreePrefs`, this tree's unrelated visual-style
    /// settings) under a single name.
    void load(prefsmod.Preferences prefs)
    {
        import std.array : replace;

        string path = prefs.path();
        path = path == "." ? path[1 .. $] : path[2 .. $];

        int n = prefs.groups();
        for (int i = 0; i < n; i++)
        {
            auto child = new prefsmod.Preferences(prefs, i);
            add(child.path()[2 .. $]);
            load(child);
        }

        n = prefs.entries();
        for (int i = 0; i < n; i++)
        {
            string key = prefs.entry(i).replace("/", "\\");
            string val;
            prefs.get(key, val, "");
            val = val.replace("/", "\\");

            string entry = path ~ "/" ~ key ~ " = " ~ (val.length < 40 ? val : val[0 .. 40] ~ "...");
            add(entry[0] == '/' ? entry[1 .. $] : entry);
        }
    }

    /// Remove item (and its children) from the tree. Returns 0 on
    /// success, -1 if item wasn't found.
    int remove(TreeItem item)
    {
        if (item is itemFocus_) itemFocus_ = null;
        if (item is lastselect_) lastselect_ = null;
        if (item is root_)
        {
            clear();
        }
        else
        {
            TreeItem parent = item.parent();
            if (parent is null) return -1;
            parent.removeChild(item);
        }
        return 0;
    }

    /// Clear the entire tree, including the root. Leaves the tree
    /// completely empty.
    override void clear()
    {
        if (root_ is null) return;
        root_.clearChildren();
        root_ = null;
        itemFocus_ = null;
        lastselect_ = null;
    }

    /// Clear all children of item (item itself is kept).
    void clearChildren(TreeItem item)
    {
        if (item.hasChildren())
        {
            item.clearChildren();
            redraw();
        }
    }

    ////////////////////////
    // Item lookup methods
    ////////////////////////

    /// Find the item at a menu-style path (e.g. "Parent/Child/item"),
    /// or null if not found.
    TreeItem findItem(string path)
    {
        if (root_ is null) return null;
        return root_.findItem(parsePath(path));
    }

    /// Return item's full pathname (e.g. "Parent/Child/Item"), '/' and
    /// '\' within a label escaped with a backslash. If item is null,
    /// root() is used. Returns null if there's no root.
    string itemPathname(TreeItem item)
    {
        TreeItem it = item !is null ? item : root_;
        if (it is null) return null;
        string[] parts;
        for (; it !is null; it = it.parent())
        {
            if (it.isRoot() && !showroot()) break;
            parts ~= it.label().length ? it.label() : "???";
        }
        string result;
        foreach_reverse (i, p; parts)
        {
            foreach (c; p)
            {
                if (c == '/' || c == '\\') result ~= '\\';
                result ~= c;
            }
            if (i != 0) result ~= '/';
        }
        return result;
    }

    /// Find the item the last event was over (walks the whole tree). If
    /// yonly, only the event's y is checked. Prefer callbackItem()
    /// inside a callback instead -- this is for subclasses receiving
    /// events before Tree updates callbackItem().
    TreeItem findClicked(bool yonly = false)
    {
        if (root_ is null) return null;
        return root_.findClicked(prefs_, yonly);
    }

    /// Returns the first item in the tree (always root()), or null.
    TreeItem first() { return root_; }
    /// Returns the first open()/visible() item, or null.
    TreeItem firstVisibleItem()
    {
        TreeItem i = showroot() ? first() : next(first());
        while (i !is null)
        {
            if (i.visible()) return i;
            i = next(i);
        }
        return null;
    }
    /// Return the next item after item, or null.
    TreeItem next(TreeItem item) { return item is null ? null : item.next(); }
    /// Return the previous item before item, or null.
    TreeItem prev(TreeItem item) { return item is null ? null : item.prev(); }
    /// Returns the last item in the tree, or null.
    TreeItem last()
    {
        if (root_ is null) return null;
        TreeItem item = root_;
        while (item.hasChildren()) item = item.child(item.children() - 1);
        return item;
    }
    /// Returns the last open()/visible() item, or null.
    TreeItem lastVisibleItem()
    {
        TreeItem item = last();
        while (item !is null)
        {
            if (item.visibleR()) return (item is root_ && !showroot()) ? null : item;
            item = prev(item);
        }
        return item;
    }
    /// Returns the next open()/visible() item above (dir==up) or below
    /// (dir==down) item, or null. If item is null, wraps to the bottom
    /// (up) or top (down).
    TreeItem nextVisibleItem(TreeItem item, int dir) { return nextItem(item, dir, true); }

    /// Returns the first selected item, or null.
    TreeItem firstSelectedItem() { return nextSelectedItem(null); }
    /// Returns the last selected item, or null.
    TreeItem lastSelectedItem() { return nextSelectedItem(null, up); }

    /// Returns the next item after item in direction dir
    /// (up/down), open/closed items included unless visible is true.
    /// If item is null: wraps to last()/lastVisibleItem() (dir==up) or
    /// first()/firstVisibleItem() (dir==down), per visible.
    TreeItem nextItem(TreeItem item, int dir = down, bool visible = false)
    {
        if (item is null)
        {
            item = visible
                ? (dir == up ? lastVisibleItem() : firstVisibleItem())
                : (dir == up ? last() : first());
            if (item is null) return null;
            if (item.visibleR()) return item;
        }
        if (dir == up) return visible ? item.prevVisible(prefs_) : item.prev();
        if (dir == down) return visible ? item.nextVisible(prefs_) : item.next();
        return null;
    }

    /// Returns the next selected item above/below item, per dir. If
    /// item is null, search starts at first() (down) or last() (up).
    TreeItem nextSelectedItem(TreeItem item, int dir = down)
    {
        if (dir == down)
        {
            if (item is null)
            {
                item = first();
                if (item is null) return null;
                if (item.isSelected()) return item;
            }
            while ((item = item.next()) !is null)
                if (item.isSelected()) return item;
            return null;
        }
        if (dir == up)
        {
            if (item is null)
            {
                item = last();
                if (item is null) return null;
                if (item.isSelected()) return item;
            }
            while ((item = item.prev()) !is null)
                if (item.isSelected()) return item;
            return null;
        }
        return null;
    }

    /// Returns every currently-selected item, top to bottom.
    TreeItem[] selectedItems()
    {
        TreeItem[] result;
        for (auto i = firstSelectedItem(); i !is null; i = nextSelectedItem(i)) result ~= i;
        return result;
    }

    //////////////////////////
    // Item open/close methods
    //////////////////////////

    /// Open item. Returns 1 if it changed, 0 if already open.
    int open(TreeItem item, bool docallback = true)
    {
        if (item.isOpen()) return 0;
        item.open(); // handles recalcTree()
        redraw();
        if (docallback) doCallbackForItem(item, CallbackReason.opened);
        return 1;
    }
    /// Open the item at path. Returns 1 (opened), 0 (already open), or
    /// -1 (not found).
    int open(string path, bool docallback = true)
    {
        TreeItem item = findItem(path);
        if (item is null) return -1;
        return open(item, docallback);
    }
    /// Toggle item's open/closed state.
    void openToggle(TreeItem item, bool docallback = true)
    {
        if (item.isOpen()) close(item, docallback);
        else open(item, docallback);
    }
    /// Close item. Returns 1 if it changed, 0 if already closed.
    int close(TreeItem item, bool docallback = true)
    {
        if (item.isClose()) return 0;
        item.close(); // handles recalcTree()
        redraw();
        if (docallback) doCallbackForItem(item, CallbackReason.closed);
        return 1;
    }
    /// Close the item at path. Returns 1 (closed), 0 (already closed),
    /// or -1 (not found).
    int close(string path, bool docallback = true)
    {
        TreeItem item = findItem(path);
        if (item is null) return -1;
        return close(item, docallback);
    }
    /// See if item is open.
    bool isOpen(const(TreeItem) item) const { return item.isOpen(); }
    /// See if the item at path is open (-1 if not found; check via
    /// findItem() first if you need to distinguish).
    int isOpen(string path)
    {
        auto item = findItem(path);
        return item is null ? -1 : (item.isOpen() ? 1 : 0);
    }
    /// See if item is closed.
    bool isClose(const(TreeItem) item) const { return item.isClose(); }
    /// See if the item at path is closed.
    int isClose(string path)
    {
        auto item = findItem(path);
        return item is null ? -1 : (item.isClose() ? 1 : 0);
    }

    /////////////////////////
    // Item selection methods
    /////////////////////////

    /// Select item. Returns 1 if it changed, 0 if already selected.
    int select(TreeItem item, bool docallback = true)
    {
        bool already = item.isSelected();
        if (!already)
        {
            item.select();
            setChanged();
            if (docallback) doCallbackForItem(item, CallbackReason.selected);
            redraw();
            return 1;
        }
        if (itemReselectMode() == TreeItemReselectMode.selectableAlways && docallback)
            doCallbackForItem(item, CallbackReason.reselected);
        return 0;
    }
    /// Select the item at path. Returns 1, 0, or -1 (not found).
    int select(string path, bool docallback = true)
    {
        TreeItem item = findItem(path);
        if (item is null) return -1;
        return select(item, docallback);
    }
    /// Toggle item's selection state.
    void selectToggle(TreeItem item, bool docallback = true)
    {
        item.selectToggle();
        setChanged();
        if (docallback)
            doCallbackForItem(item, item.isSelected() ? CallbackReason.selected : CallbackReason.deselected);
        redraw();
    }
    /// Deselect item. Returns 1 if it changed, 0 if already deselected.
    int deselect(TreeItem item, bool docallback = true)
    {
        if (item.isSelected())
        {
            item.deselect();
            setChanged();
            if (docallback) doCallbackForItem(item, CallbackReason.deselected);
            redraw();
            return 1;
        }
        return 0;
    }
    /// Deselect the item at path. Returns 1, 0, or -1 (not found).
    int deselect(string path, bool docallback = true)
    {
        TreeItem item = findItem(path);
        if (item is null) return -1;
        return deselect(item, docallback);
    }
    /// Deselect item and all its children (first() if item is null).
    /// Returns how many items changed state.
    int deselectAll(TreeItem item = null, bool docallback = true)
    {
        item = item !is null ? item : first();
        if (item is null) return 0;
        int count = 0;
        if (item.isSelected() && deselect(item, docallback)) count++;
        foreach (t; 0 .. item.children()) count += deselectAll(item.child(t), docallback);
        return count;
    }
    /// Select only selitem, deselecting everything else (first() if
    /// null). Returns how many items changed state.
    int selectOnly(TreeItem selitem, bool docallback = true)
    {
        selitem = selitem !is null ? selitem : first();
        if (selitem is null) return 0;
        int changed = 0;
        for (auto item = first(); item !is null; item = item.next())
        {
            if (item is selitem) continue;
            if (item.isSelected())
            {
                deselect(item, docallback);
                changed++;
            }
        }
        if (selitem.isSelected() && itemReselectMode() == TreeItemReselectMode.selectableAlways)
        {
            select(selitem, docallback);
        }
        else if (!selitem.isSelected())
        {
            select(selitem, docallback);
            changed++;
        }
        return changed;
    }
    /// Select item and all its children (first() if null). Returns how
    /// many items changed state.
    int selectAll(TreeItem item = null, bool docallback = true)
    {
        item = item !is null ? item : first();
        if (item is null) return 0;
        int count = 0;
        if (!item.isSelected() && select(item, docallback)) count++;
        foreach (t; 0 .. item.children()) count += selectAll(item.child(t), docallback);
        return count;
    }

    /// Extend the selection between from and to (inclusive), moving in
    /// direction dir. val: 0=deselect, 1=select, 2=toggle. visible:
    /// true=only affect open()/visible() items. Returns how many items
    /// changed.
    int extendSelectionDir(TreeItem from, TreeItem to, int dir, int val, bool visible)
    {
        int changed = 0;
        for (auto item = from; item !is null; item = nextItem(item, dir, visible))
        {
            final switch (val)
            {
            case 0:
                if (deselect(item, cast(bool)(when() & whenChanged))) changed++;
                break;
            case 1:
                if (select(item, cast(bool)(when() & whenChanged))) changed++;
                break;
            case 2:
                selectToggle(item, cast(bool)(when() & whenChanged));
                changed++;
                break;
            }
            if (item is to) break;
        }
        return changed;
    }

    /// Extend the selection between from and to (inclusive), direction
    /// need not be known in advance (searches the tree). Used by
    /// SHIFT-click. Returns how many items changed.
    int extendSelection(TreeItem from, TreeItem to, int val = 1, bool visible = false)
    {
        int changed = 0;
        if (from is to)
        {
            if (visible && !from.isVisible()) return 0;
            final switch (val)
            {
            case 0:
                if (deselect(from, cast(bool)(when() & whenChanged))) changed++;
                break;
            case 1:
                if (select(from, cast(bool)(when() & whenChanged))) changed++;
                break;
            case 2:
                selectToggle(from, cast(bool)(when() & whenChanged));
                changed++;
                break;
            }
            return changed;
        }
        bool on = false;
        for (auto item = first(); item !is null; item = item.nextVisible(prefs_))
        {
            if (visible && !item.isVisible()) continue;
            if (on || item is from || item is to)
            {
                final switch (val)
                {
                case 0:
                    if (deselect(item, cast(bool)(when() & whenChanged))) changed++;
                    break;
                case 1:
                    if (select(item, cast(bool)(when() & whenChanged))) changed++;
                    break;
                case 2:
                    selectToggle(item, cast(bool)(when() & whenChanged));
                    changed++;
                    break;
                }
                if (item is from || item is to)
                {
                    on = !on;
                    if (!on) break;
                }
            }
        }
        return changed;
    }

    /// Set the item with keyboard focus (null: none). Redraws the
    /// focus box if it changed and it's visible.
    void setItemFocus(TreeItem item)
    {
        if (itemFocus_ !is item)
        {
            itemFocus_ = item;
            if (fl.core.visibleFocus()) redraw();
        }
    }
    /// Get the item that currently has keyboard focus, or null.
    TreeItem getItemFocus() const { return cast(TreeItem) itemFocus_; }
    /// See if item is selected.
    bool isSelected(const(TreeItem) item) const { return item.isSelected(); }
    /// See if the item at path is selected (-1 if not found).
    int isSelected(string path)
    {
        TreeItem item = findItem(path);
        if (item is null) return -1;
        return item.isSelected() ? 1 : 0;
    }

    /////////////////////////////////
    // Item attribute related methods (defaults for newly-add()ed items)
    /////////////////////////////////

    Font itemLabelfont() const { return prefs_.itemLabelfont(); }
    void itemLabelfont(Font val) { prefs_.itemLabelfont(val); }
    Fontsize itemLabelsize() const { return prefs_.itemLabelsize(); }
    void itemLabelsize(Fontsize val) { prefs_.itemLabelsize(val); }
    Color itemLabelfgcolor() const { return prefs_.itemLabelfgcolor(); }
    void itemLabelfgcolor(Color val) { prefs_.itemLabelfgcolor(val); }
    Color itemLabelbgcolor() const { return prefs_.itemLabelbgcolor(); }
    void itemLabelbgcolor(Color val) { prefs_.itemLabelbgcolor(val); }
    Color connectorcolor() const { return prefs_.connectorcolor(); }
    void connectorcolor(Color val) { prefs_.connectorcolor(val); }
    int marginleft() const { return prefs_.marginleft(); }
    void marginleft(int val) { prefs_.marginleft(val); redraw(); recalcTree(); }
    int margintop() const { return prefs_.margintop(); }
    void margintop(int val) { prefs_.margintop(val); redraw(); recalcTree(); }
    int marginbottom() const { return prefs_.marginbottom(); }
    void marginbottom(int val) { prefs_.marginbottom(val); redraw(); recalcTree(); }
    int linespacing() const { return prefs_.linespacing(); }
    void linespacing(int val) { prefs_.linespacing(val); redraw(); recalcTree(); }
    int openchildMarginbottom() const { return prefs_.openchildMarginbottom(); }
    void openchildMarginbottom(int val) { prefs_.openchildMarginbottom(val); redraw(); recalcTree(); }
    int usericonmarginleft() const { return prefs_.usericonmarginleft(); }
    void usericonmarginleft(int val) { prefs_.usericonmarginleft(val); redraw(); recalcTree(); }
    int labelmarginleft() const { return prefs_.labelmarginleft(); }
    void labelmarginleft(int val) { prefs_.labelmarginleft(val); redraw(); recalcTree(); }
    int widgetmarginleft() const { return prefs_.widgetmarginleft(); }
    void widgetmarginleft(int val) { prefs_.widgetmarginleft(val); redraw(); recalcTree(); }
    int connectorwidth() const { return prefs_.connectorwidth(); }
    void connectorwidth(int val) { prefs_.connectorwidth(val); redraw(); recalcTree(); }
    Image usericon() const { return prefs_.usericon(); }
    void usericon(Image val) { prefs_.usericon(val); redraw(); recalcTree(); }
    Image openicon() const { return prefs_.openicon(); }
    void openicon(Image val) { prefs_.openicon(val); redraw(); recalcTree(); }
    Image closeicon() const { return prefs_.closeicon(); }
    void closeicon(Image val) { prefs_.closeicon(val); redraw(); recalcTree(); }
    bool showcollapse() const { return prefs_.showcollapse(); }
    void showcollapse(bool val) { prefs_.showcollapse(val); redraw(); recalcTree(); }
    bool showroot() const { return prefs_.showroot(); }
    void showroot(bool val) { prefs_.showroot(val); redraw(); recalcTree(); }
    TreeConnector connectorstyle() const { return prefs_.connectorstyle(); }
    void connectorstyle(TreeConnector val) { prefs_.connectorstyle(val); redraw(); }
    TreeSort sortorder() const { return prefs_.sortorder(); }
    void sortorder(TreeSort val) { prefs_.sortorder(val); } // no redraw: only affects new adds
    Boxtype selectbox() const { return prefs_.selectbox(); }
    void selectbox(Boxtype val) { prefs_.selectbox(val); redraw(); }
    TreeSelect selectmode() const { return prefs_.selectmode(); }
    void selectmode(TreeSelect val) { prefs_.selectmode(val); }
    TreeItemReselectMode itemReselectMode() const { return prefs_.itemReselectMode(); }
    void itemReselectMode(TreeItemReselectMode mode) { prefs_.itemReselectMode(mode); }
    TreeItemDrawMode itemDrawMode() const { return prefs_.itemDrawMode(); }
    void itemDrawMode(TreeItemDrawMode mode) { prefs_.itemDrawMode(mode); }

    /// Recalculate the widget's outer/inner dimensions and scrollbar
    /// visibility -- a low-overhead update, not a full tree re-walk.
    /// Called on resize() and by calcTree().
    void calcDimensions()
    {
        tox_ = x() + fl.core.boxDx(box());
        toy_ = y() + fl.core.boxDy(box());
        tow_ = w() - fl.core.boxDw(box());
        toh_ = h() - fl.core.boxDh(box());

        if (treeH_ >= 0 && treeW_ >= 0)
        {
            int scrollsize = scrollbarSize_ ? scrollbarSize_ : fl.core.scrollbarSize();
            bool vshow = treeH_ > toh_;
            bool hshow = treeW_ > tow_;
            if (hshow && !vshow && treeH_ > toh_ - scrollsize) vshow = true;
            if (vshow && !hshow && treeW_ > tow_ - scrollsize) hshow = true;
            if (vshow)
            {
                vscroll_.show();
                vscroll_.resize(tox_ + tow_ - scrollsize, toy_,
                    scrollsize, h() - fl.core.boxDh(box()) - (hshow ? scrollsize : 0));
            }
            else
            {
                vscroll_.hide();
                vscroll_.value(0);
            }
            if (hshow)
            {
                hscroll_.show();
                hscroll_.resize(tox_, toy_ + toh_ - scrollsize,
                    tow_ - (vshow ? scrollsize : 0), scrollsize);
            }
            else
            {
                hscroll_.hide();
                hscroll_.value(0);
            }

            tix_ = tox_;
            tiy_ = toy_;
            tiw_ = tow_ - (vscroll_.visible() ? vscroll_.w() : 0);
            tih_ = toh_ - (hscroll_.visible() ? hscroll_.h() : 0);

            vscroll_.sliderSize(cast(double) tih_ / cast(double) treeH_);
            vscroll_.range(0.0, treeH_ - tih_);
            hscroll_.sliderSize(cast(double) tiw_ / cast(double) treeW_);
            hscroll_.range(0.0, treeW_ - tiw_);
        }
        else
        {
            tix_ = tox_;
            tiy_ = toy_;
            tiw_ = tow_;
            tih_ = toh_;
        }
    }

    /// Recalculate the tree's overall pixel size (walking the whole
    /// tree) and scrollbar visibility. Potentially slow on huge trees
    /// -- recalcTree() schedules this lazily rather than calling it
    /// directly.
    void calcTree()
    {
        treeW_ = treeH_ = -1;
        calcDimensions();
        if (root_ is null) return;
        int X = tix_ + prefs_.marginleft() - cast(int) hscroll_.value();
        int Y = tiy_ + prefs_.margintop() - cast(int) vscroll_.value();
        int W = tiw_;
        if (prefs_.connectorstyle() == TreeConnector.connectorNone)
        {
            X -= prefs_.openiconW();
            W += prefs_.openiconW();
        }
        int xmax = 0;
        int ytop = Y;
        fl_font(prefs_.itemLabelfont(), prefs_.itemLabelsize());
        root_.draw(X, Y, W, null, xmax, true, false); // descend without drawing (render=false)
        treeW_ = prefs_.marginleft() + xmax - X;
        treeH_ = prefs_.margintop() + Y - ytop;
        calcDimensions();
    }

    override void resize(int X, int Y, int W, int H)
    {
        fixScrollbarOrder();
        super.resize(X, Y, W, H); // see this module's own top comment
        if (autoResizeChildren()) initSizes();
        calcDimensions();
    }

    override void draw()
    {
        fixScrollbarOrder();
        if (treeW_ == -1) calcTree();
        else calcDimensions();

        if ((damage() & ~damageChild) != 0)
        {
            drawBox();
            drawLabel();
        }
        if (root_ !is null)
        {
            int X = tix_ + prefs_.marginleft() - cast(int) hscroll_.value();
            int Y = tiy_ + prefs_.margintop() - cast(int) vscroll_.value();
            int W = tiw_ - X + tix_;
            if (prefs_.connectorstyle() == TreeConnector.connectorNone)
            {
                X -= prefs_.openiconW();
                W += prefs_.openiconW();
            }
            pushClip(tix_, tiy_, tiw_, tih_);
            int xmax = 0;
            fl_font(prefs_.itemLabelfont(), prefs_.itemLabelsize());
            root_.draw(X, Y, W, (fl.core.focus() is this) ? itemFocus_ : null, xmax, true, true);
            popClip();
        }

        drawChild(vscroll_);
        drawChild(hscroll_);
        if (vscroll_.visible() && hscroll_.visible())
        {
            fl_color(vscroll_.color());
            fl_rectf(hscroll_.x() + hscroll_.w(), vscroll_.y() + vscroll_.h(), vscroll_.w(), hscroll_.h());
        }

        if (prefs_.selectmode() == TreeSelect.selectSingleDraggable && fl.core.pushed() is this)
        {
            TreeItem item = findClicked(true);
            if (item !is null && item !is itemFocus_)
            {
                int hh = fl.core.eventY() - item.y();
                int mid = item.h() / 2;
                bool isAbove = hh < mid;
                fl_color(black);
                int tgt = item.y() + (isAbove ? 0 : item.h());
                fl_line(item.x(), tgt, item.x() + item.w(), tgt);
            }
        }
    }

    /// Print the tree as 'ascii art' to stdout, for debugging.
    void showSelf() { if (root_ !is null) root_.showSelf(); }

    override int handle(Event e)
    {
        if (e == Event.noEvent) return 0;
        int ret = 0;
        bool isShift = (fl.core.eventState() & stateShift) != 0;
        bool isCtrl = (fl.core.eventState() & stateCtrl) != 0;
        bool isCommand = (fl.core.eventState() & stateCommand) != 0;

        if (e == Event.enter || e == Event.leave) return 1;
        switch (e)
        {
        case Event.focus:
            if (itemFocus_ is null)
            {
                switch (fl.core.eventKey())
                {
                case tab:
                    setItemFocus(nextVisibleItem(null, isShift ? up : down));
                    break;
                case left:
                case up:
                    setItemFocus(nextVisibleItem(null, up));
                    break;
                case right:
                case down:
                default:
                    setItemFocus(nextVisibleItem(null, down));
                    break;
                }
            }
            if (fl.core.visibleFocus()) redraw();
            return 1;
        case Event.unfocus:
            if (fl.core.visibleFocus()) redraw();
            return 1;
        case Event.keyDown:
            if (fl.core.focus() is this && prefs_.selectmode() > TreeSelect.selectNone)
            {
                if (itemFocus_ is null)
                {
                    setItemFocus(firstVisibleItem());
                    if (fl.core.eventKey() == up || fl.core.eventKey() == down) return 1;
                }
                if (itemFocus_ !is null)
                {
                    int ekey = fl.core.eventKey();
                    switch (ekey)
                    {
                    case enter:
                    case kpEnter:
                        openToggle(itemFocus_, cast(bool)(when() & whenChanged));
                        return 1;
                    case ' ':
                        final switch (prefs_.selectmode())
                        {
                        case TreeSelect.selectNone:
                            break;
                        case TreeSelect.selectSingle:
                        case TreeSelect.selectSingleDraggable:
                            if (isCtrl)
                            {
                                if (!itemFocus_.isSelected()) selectOnly(itemFocus_, cast(bool)(when() & whenChanged));
                                else deselectAll(null, cast(bool)(when() & whenChanged));
                            }
                            else
                            {
                                selectOnly(itemFocus_, cast(bool)(when() & whenChanged));
                            }
                            lastselect_ = itemFocus_;
                            return 1;
                        case TreeSelect.selectMulti:
                            if (isCtrl) selectToggle(itemFocus_, cast(bool)(when() & whenChanged));
                            else select(itemFocus_, cast(bool)(when() & whenChanged));
                            lastselect_ = itemFocus_;
                            return 1;
                        }
                        break;
                    case right:
                    case left:
                        if (ekey == right && itemFocus_.isClose())
                        {
                            open(itemFocus_);
                            ret = 1;
                        }
                        else if (ekey == left && itemFocus_.isOpen())
                        {
                            close(itemFocus_);
                            ret = 1;
                        }
                        return 1;
                    case up:
                    case down:
                        setItemFocus(nextVisibleItem(itemFocus_, ekey));
                        if (itemFocus_ !is null)
                        {
                            int itemtop = itemFocus_.y();
                            int itembot = itemFocus_.y() + itemFocus_.h();
                            if (itemtop < y()) showItemTop(itemFocus_);
                            if (itembot > y() + h()) showItemBottom(itemFocus_);
                            if (prefs_.selectmode() == TreeSelect.selectMulti && isShift && !itemFocus_.isSelected())
                            {
                                select(itemFocus_, cast(bool)(when() & whenChanged));
                                lastselect_ = itemFocus_;
                            }
                            return 1;
                        }
                        break;
                    case 'a':
                    case 'A':
                        if (isCommand && prefs_.selectmode() == TreeSelect.selectMulti)
                        {
                            selectAll();
                            lastselect_ = firstVisibleItem();
                            takeFocus();
                            return 1;
                        }
                        break;
                    default:
                        break;
                    }
                }
            }
            break;
        default:
            break;
        }

        if (super.handle(e)) return 1;

        if (root_ is null) return ret;
        switch (e)
        {
        case Event.push:
        {
            lastMy_ = fl.core.eventY();
            if (fl.core.visibleFocus() && handle(Event.focus)) fl.core.focus(this);
            TreeItem item = findClicked();
            lastpushed_ = item is null ? pushedNone
                : item.eventOnCollapseIcon(prefs_) ? pushedOpenClose
                : item.eventOnUserIcon(prefs_) ? pushedUserIcon : pushedLabel;
            if (item is null)
            {
                lastselect_ = null;
                final switch (prefs_.selectmode())
                {
                case TreeSelect.selectNone:
                    break;
                case TreeSelect.selectSingle:
                case TreeSelect.selectSingleDraggable:
                case TreeSelect.selectMulti:
                    deselectAll();
                    break;
                }
                break;
            }
            setItemFocus(item);
            ret |= 1;
            if (fl.core.eventButton() == leftMouse)
            {
                if (item.eventOnCollapseIcon(prefs_))
                {
                    openToggle(item);
                }
                else if (item.widget() is null || !fl.core.eventInside(item.widget()))
                {
                    final switch (prefs_.selectmode())
                    {
                    case TreeSelect.selectNone:
                        break;
                    case TreeSelect.selectSingle:
                    case TreeSelect.selectSingleDraggable:
                        selectOnly(item, cast(bool)(when() & whenChanged));
                        lastselect_ = item;
                        break;
                    case TreeSelect.selectMulti:
                        if (isShift)
                        {
                            if (lastselect_ !is null)
                                extendSelection(lastselect_, item, isCtrl ? 2 : 1, true);
                            else
                                select(item);
                        }
                        else if (isCtrl)
                        {
                            selectToggle(item, cast(bool)(when() & whenChanged));
                        }
                        else
                        {
                            selectOnly(item, cast(bool)(when() & whenChanged));
                        }
                        lastselect_ = item;
                        break;
                    }
                }
            }
            break;
        }
        case Event.drag:
        {
            if (lastpushed_ == pushedNone || lastpushed_ == pushedOpenClose) return 0;
            int my = fl.core.eventY();
            int dir = my > lastMy_ ? down : up;
            lastMy_ = my;
            if (my < y())
            {
                dir = up;
                int p = vposition() - (y() - my);
                if (p < 0) p = 0;
                vposition(p);
            }
            else if (my > y() + h())
            {
                dir = down;
                int p = vposition() + (my - y() - h());
                if (p > cast(int) vscroll_.maximum()) p = cast(int) vscroll_.maximum();
                vposition(p);
            }
            if (fl.core.eventButton() != leftMouse) break;
            TreeItem item = findClicked(true);
            if (item is null) break;
            ret |= 1;
            if (prefs_.selectmode() != TreeSelect.selectSingleDraggable) setItemFocus(item);
            if (item is lastselect_) break;
            final switch (prefs_.selectmode())
            {
            case TreeSelect.selectNone:
                break;
            case TreeSelect.selectSingle:
                selectOnly(item, cast(bool)(when() & whenChanged));
                break;
            case TreeSelect.selectSingleDraggable:
                redraw();
                break;
            case TreeSelect.selectMulti:
            {
                TreeItem from = nextVisibleItem(lastselect_, dir);
                extendSelectionDir(from, item, dir, isCtrl ? 2 : 1, true);
                break;
            }
            }
            lastselect_ = item;
            break;
        }
        case Event.release:
            if (prefs_.selectmode() == TreeSelect.selectSingleDraggable && fl.core.eventButton() == leftMouse)
            {
                TreeItem item = findClicked(true);
                if (item !is null && lastselect_ !is null && item !is lastselect_)
                {
                    int hh = fl.core.eventY() - item.y();
                    int mid = item.h() / 2;
                    bool isAbove = hh < mid;
                    TreeItem target = isAbove ? prev(item) : next(item);
                    if (target !is lastselect_)
                    {
                        TreeItem parent = item.parent();
                        if (parent is null)
                        {
                            lastselect_.moveInto(root(), 0);
                        }
                        else if (item.hasChildren() && item.isOpen() && !isAbove)
                        {
                            lastselect_.moveInto(item, 0);
                        }
                        else if (lastselect_.parent() is parent)
                        {
                            if (isAbove) lastselect_.moveAbove(item);
                            else lastselect_.moveBelow(item);
                        }
                        else
                        {
                            int pos = parent.findChild(item);
                            if (!isAbove) pos++;
                            lastselect_.moveInto(parent, pos);
                        }
                        redraw();
                        doCallbackForItem(lastselect_, CallbackReason.dragged);
                    }
                }
                redraw();
            }
            ret |= 1;
            break;
        default:
            break;
        }
        return ret;
    }
    private int lastMy_;

    /////////////////////////////////
    // Displaying / scrolling
    /////////////////////////////////

    /// See if item is currently displayed within the widget's visible
    /// area (doesn't consider open()/close()/hide()/show()).
    bool displayed(TreeItem item)
    {
        item = item !is null ? item : first();
        if (item is null) return false;
        return item.y() >= y() && item.y() <= y() + h() - item.h();
    }
    /// Scroll so item is yoff pixels from the top.
    void showItem(TreeItem item, int yoff)
    {
        item = item !is null ? item : first();
        if (item is null) return;
        int newval = item.y() - y() - yoff + cast(int) vscroll_.value();
        if (newval < vscroll_.minimum()) newval = cast(int) vscroll_.minimum();
        if (newval > vscroll_.maximum()) newval = cast(int) vscroll_.maximum();
        vscroll_.value(newval);
        redraw();
    }
    /// Scroll to make item visible at the top, only if it's currently
    /// off-screen.
    void showItem(TreeItem item)
    {
        item = item !is null ? item : first();
        if (item is null) return;
        if (displayed(item)) return;
        showItemTop(item);
    }
    /// Scroll so item is at the top of the display.
    void showItemTop(TreeItem item) { item = item !is null ? item : first(); if (item !is null) showItem(item, 0); }
    /// Scroll so item is in the middle of the display.
    void showItemMiddle(TreeItem item)
    {
        item = item !is null ? item : first();
        if (item !is null) showItem(item, tih_ / 2 - item.h() / 2);
    }
    /// Scroll so item is at the bottom of the display.
    void showItemBottom(TreeItem item)
    {
        item = item !is null ? item : first();
        if (item !is null) showItem(item, tih_ - item.h());
    }
    /// Display item, scrolling as necessary.
    void display(TreeItem item) { item = item !is null ? item : first(); if (item !is null) showItemMiddle(item); }

    /// Vertical scroll position, in pixels scrolled off the top.
    int vposition() const { return cast(int) vscroll_.value(); }
    /// Set the vertical scroll position.
    void vposition(int pos)
    {
        if (pos < 0) pos = 0;
        if (pos > vscroll_.maximum()) pos = cast(int) vscroll_.maximum();
        if (pos == cast(int) vscroll_.value()) return;
        vscroll_.value(pos);
        redraw();
    }
    /// Horizontal scroll position, in pixels scrolled off the left.
    int hposition() const { return cast(int) hscroll_.value(); }
    /// Set the horizontal scroll position.
    void hposition(int pos)
    {
        if (pos < 0) pos = 0;
        if (pos > hscroll_.maximum()) pos = cast(int) hscroll_.maximum();
        if (pos == cast(int) hscroll_.value()) return;
        hscroll_.value(pos);
        redraw();
    }

    /// See if w is one of this tree's own scrollbars -- skip these when
    /// walking array().
    bool isScrollbar(Widget w) const { return w is vscroll_ || w is hscroll_; }
    /// Get the scrollbar trough size (0: uses fl.core.scrollbarSize()).
    int scrollbarSize() const { return scrollbarSize_; }
    /// Set the scrollbar trough size for this widget only (0: track the
    /// global fl.core.scrollbarSize()).
    void scrollbarSize(int size)
    {
        scrollbarSize_ = size;
        int scrollsize = scrollbarSize_ ? scrollbarSize_ : fl.core.scrollbarSize();
        if (vscroll_.w() != scrollsize) vscroll_.resize(x() + w() - scrollsize, h(), scrollsize, vscroll_.h());
        if (hscroll_.h() != scrollsize) hscroll_.resize(x(), y() + h() - scrollsize, hscroll_.w(), scrollsize);
        calcDimensions();
    }
    /// See if the vertical scrollbar is currently visible.
    bool isVscrollVisible() const { return vscroll_.visible(); }
    /// See if the horizontal scrollbar is currently visible.
    bool isHscrollVisible() const { return hscroll_.visible(); }

    ///////////////////////
    // callback related
    ///////////////////////

    /// Do the callback for item, per reason.
    protected void doCallbackForItem(TreeItem item, CallbackReason reason)
    {
        callbackReason(reason);
        callbackItem(item);
        doCallback(reason);
    }
    /// Sets the item that caused the callback -- normally managed by
    /// Tree itself; only subclasses needing to override this should
    /// call it.
    void callbackItem(TreeItem item) { callbackItem_ = item; }
    /// Gets the item that caused the callback. Valid only within the
    /// callback.
    TreeItem callbackItem() { return callbackItem_; }
    /// Sets the reason for this callback.
    void callbackReason(CallbackReason reason) { callbackReason_ = reason; }
    /// Gets the reason for this callback -- see fl.enumerations'
    /// CallbackReason (this module's own top comment on why there's no
    /// separate Fl_Tree_Reason-equivalent enum).
    CallbackReason callbackReason() const { return callbackReason_; }

    //////////////////
    // fl.tree_item's own package(fl) bridges into FlGroup's protected
    // machinery -- TreeItem isn't a FlGroup subclass (see its own top
    // comment), so it can't reach drawChild()/drawOutsideLabel()
    // directly the way Tree itself can.
    //////////////////

    package(fl) void drawItemWidget(Widget w) { drawChild(w); }
    package(fl) void drawItemWidgetLabel(Widget w) { drawOutsideLabel(w); }
    package(fl) int tix() const { return tix_; }
    package(fl) int tiy() const { return tiy_; }
    package(fl) int tiw() const { return tiw_; }
    package(fl) int tih() const { return tih_; }

    /// Schedule the tree to recalculate its overall size on the next
    /// calcTree() (draw() or an explicit calcTree() call). Ported from
    /// FLTK's own `Fl_Tree::recalc_tree()` -- a public method there
    /// (`FL/Fl_Tree.H`), needed by a real external caller whenever a
    /// custom `TreeItem` subclass's `calcItemHeight()`/
    /// `drawItemContent()` depends on mutable data owned
    /// *outside* the tree (`fluid.node_browser`'s `NodeBrowserItem`
    /// reads a `Node`'s `comment`/`instanceName`, edited live from a
    /// separate properties dialog) -- with no public way to tell the
    /// tree "your cached item geometry may be stale," a comment typed
    /// elsewhere would never grow the row to fit it or repaint the new
    /// text at all until some unrelated full rebuild happened to run.
    void recalcTree() { treeW_ = treeH_ = -1; }

    /// Ensure the scrollbars stay the last two children in array() (so
    /// they draw last / on top).
    private void fixScrollbarOrder()
    {
        auto a = array();
        if (a.length == 0 || a[$ - 1] !is vscroll_)
        {
            Widget[] reordered;
            foreach (o; a)
                if (o !is vscroll_ && o !is hscroll_) reordered ~= o;
            reordered ~= hscroll_;
            reordered ~= vscroll_;
            foreach (i, o; reordered) a[i] = o;
        }
    }
}

/// Parses a menu-style path ("Flintstones/Fred") into its components,
/// honoring backslash-escapes (so "/" or "\" can appear literally within
/// a component). Ported from the internal parse_path()/free_path() pair
/// in Fl_Tree.cxx -- a plain, pure `string[]`-returning function needs
/// no matching free function in D.
private string[] parsePath(string path)
{
    string[] result;
    char[] word;
    size_t i = 0;
    while (i < path.length)
    {
        char c = path[i];
        if (c == '/')
        {
            if (word.length != 0)
            {
                result ~= word.idup;
                word = [];
            }
            i++;
        }
        else if (c == '\\')
        {
            i++;
            if (i < path.length)
            {
                word ~= path[i];
                i++;
            }
        }
        else
        {
            word ~= c;
            i++;
        }
    }
    if (word.length != 0) result ~= word.idup;
    return result;
}

unittest
{
    assert(parsePath("Flintstones/Fred") == ["Flintstones", "Fred"]);
    assert(parsePath("/Holidays/Photos/12\\/25\\/2010") == ["Holidays", "Photos", "12/25/2010"]);
    assert(parsePath("Pathnames/c:\\\\Program Files\\\\MyApp") == ["Pathnames", "c:\\Program Files\\MyApp"]);
    assert(parsePath("") == []);
    assert(parsePath("///") == []);
}

unittest
{
    // add(path)/findItem(path) -- auto-creates missing parent nodes.
    import fl.group : FlGroup;

    FlGroup.current(null);
    auto t = new Tree(0, 0, 200, 200);
    FlGroup.current(null);

    t.add("Flintstones/Fred");
    t.add("Flintstones/Wilma");
    t.add("Simpsons/Homer");

    assert(t.findItem("Flintstones/Fred") !is null);
    assert(t.findItem("Flintstones/Fred").label() == "Fred");
    assert(t.findItem("Flintstones").children() == 2);
    assert(t.findItem("Simpsons/Homer") !is null);
    assert(t.findItem("Nonexistent") is null);
    assert(t.findItem("Flintstones/Nobody") is null);

    fl.core.resetForTest();
}

unittest
{
    // remove()/clear().
    import fl.group : FlGroup;

    FlGroup.current(null);
    auto t = new Tree(0, 0, 200, 200);
    FlGroup.current(null);

    t.add("Aaa");
    auto b = t.add("Bbb");
    assert(t.root().children() == 2);

    assert(t.remove(b) == 0);
    assert(t.root().children() == 1);
    assert(t.findItem("Bbb") is null);

    t.clear();
    assert(t.root() is null);

    fl.core.resetForTest();
}

unittest
{
    // select(path)/deselect(path)/isSelected(path) -- the -1 "not
    // found" tri-state the path-taking overloads need (unlike the
    // TreeItem-taking overloads, which can't fail to find their item).
    import fl.group : FlGroup;

    FlGroup.current(null);
    auto t = new Tree(0, 0, 200, 200);
    FlGroup.current(null);

    t.add("Aaa");
    assert(t.select("Aaa", false) == 1); // changed
    assert(t.select("Aaa", false) == 0); // already selected, no change
    assert(t.isSelected("Aaa") == 1);
    assert(t.deselect("Aaa", false) == 1);
    assert(t.isSelected("Aaa") == 0);
    assert(t.select("Nonexistent", false) == -1);
    assert(t.isSelected("Nonexistent") == -1);

    fl.core.resetForTest();
}

unittest
{
    // open(path)/close(path)/isOpen(path)/isClose(path).
    import fl.group : FlGroup;

    FlGroup.current(null);
    auto t = new Tree(0, 0, 200, 200);
    FlGroup.current(null);

    t.add("Folder/Leaf");
    assert(t.isOpen("Folder") == 1); // TreeItem's own default is open
    assert(t.close("Folder", false) == 1);
    assert(t.isClose("Folder") == 1);
    assert(t.close("Folder", false) == 0); // already closed
    assert(t.open("Folder", false) == 1);
    assert(t.isOpen("Folder") == 1);
    assert(t.open("Nonexistent", false) == -1);

    fl.core.resetForTest();
}

unittest
{
    // selectOnly()/selectedItems()/firstSelectedItem()/nextSelectedItem().
    import fl.group : FlGroup;

    FlGroup.current(null);
    auto t = new Tree(0, 0, 200, 200);
    FlGroup.current(null);

    auto a = t.add("Aaa");
    auto b = t.add("Bbb");
    auto c = t.add("Ccc");
    t.selectmode(TreeSelect.selectMulti);

    t.select(a, false);
    t.select(c, false);
    assert(t.selectedItems() == [a, c]);

    t.selectOnly(b, false);
    assert(t.selectedItems() == [b]);
    assert(!a.isSelected());
    assert(!c.isSelected());

    fl.core.resetForTest();
}

unittest
{
    // load(Preferences): groups become subtrees, entries become
    // "key = value" leaf items, using an in-RAM-only ("runtime")
    // preferences database (see fl.preferences's own unittest for the
    // same pattern) so this stays fully hermetic.
    import fl.group : FlGroup;

    // new Preferences(null, group) opens `group` as a child of the
    // implicit in-RAM root, so p's own path() is "./db", not "." --
    // load() works starting from any node, not just a true root.
    auto p = new prefsmod.Preferences(null, "db");
    p.set("greeting", "hello");
    auto child = new prefsmod.Preferences(p, "Child");
    child.set("num", 42);

    FlGroup.current(null);
    auto t = new Tree(0, 0, 200, 200);
    FlGroup.current(null);

    t.load(p);

    assert(t.findItem("db/greeting = hello") !is null);
    assert(t.findItem("db/Child") !is null);
    assert(t.findItem("db/Child/num = 42") !is null);

    fl.core.resetForTest();
}

unittest
{
    // callbackItem()/callbackReason() get set correctly on a state change.
    import fl.group : FlGroup;

    FlGroup.current(null);
    auto t = new Tree(0, 0, 200, 200);
    FlGroup.current(null);

    auto a = t.add("Aaa");
    t.select(a); // docallback defaults to true
    assert(t.callbackItem() is a);
    assert(t.callbackReason() == CallbackReason.selected);

    t.close(a);
    assert(t.callbackReason() == CallbackReason.closed);

    fl.core.resetForTest();
}
