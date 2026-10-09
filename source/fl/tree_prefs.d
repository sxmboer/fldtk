/*
 * Ported from FL/Fl_Tree_Prefs.H + src/Fl_Tree_Prefs.cxx (FLTK 1.5.0).
 *
 * TreePrefs is a plain settings object shared by a Tree and every
 * TreeItem in it (Tree owns one instance; TreeItem.prefs() returns the
 * owning Tree's own instance) -- ported as a D class (reference
 * semantics), matching FLTK's own single-shared-instance usage:
 * a struct's value semantics would silently break that sharing the
 * first time a copy happened.
 *
 * Deviations from FLTK, all deliberate:
 *  - `tree_connector_style()`/`tree_draw_expando_button()`
 *    (`Fl_System_Driver` hooks FLTK adds so a future non-X11
 *    platform driver could theme these) are not ported as a driver
 *    abstraction -- this port has no `Fl_Screen_Driver`-style hierarchy
 *    at all yet (see `CONVENTIONS.md`'s "not a gap to close proactively"
 *    note on that, same reasoning `fl.draw`/`fl.platform_x11` being
 *    concrete rather than polymorphic already establishes).
 *    `tree_connector_style()`'s only real body
 *    (`return FL_TREE_CONNECTOR_DOTTED;`) is inlined directly as this
 *    class's own constructor default; `tree_draw_expando_button()`'s
 *    drawing logic moves to `fl.tree_item`'s `draw()`, where it's
 *    actually used, as a plain private function.
 *  - **`openicon()`/`closeicon()`/`usericon()`'s "derive and cache a
 *    deactivated (grayed-out) copy" bookkeeping is real**: each setter calls a shared
 *    private `deriveDeicon()` helper (`val.copy()` then `.inactive()`)
 *    and caches the result, exposed via `opendeicon()`/`closedeicon()`/
 *    `userdeicon()` -- collapsing FLTK's three near-identical
 *    inline bodies (`Fl_Tree_Prefs::openicon(Fl_Image*)`/
 *    `closeicon(Fl_Image*)`/the inline `usericon(Fl_Image*)` setter)
 *    into one helper, since D has no per-call-site manual `delete` of
 *    the old cached copy to keep separate. `open{,close}iconW()`/`H()`
 *    now report the real image's `w()`/`h()` when one is set, falling
 *    back to the built-in default (11) only when none is.
 *  - `item_draw_mode()`/`Fl_Tree_Item_Draw_Mode`: FLTK declares
 *    this as a C `enum` but every real call site tests it with `&`,
 *    not `==` (`fl_tree_item.cxx` combines
 *    `FL_TREE_ITEM_DRAW_LABEL_AND_WIDGET`/`FL_TREE_ITEM_HEIGHT_FROM_WIDGET`
 *    as independent bits alongside `FL_TREE_ITEM_DRAW_DEFAULT`). Ported
 *    as `TreeItemDrawMode = alias int` plus manifest constants, per
 *    `CONVENTIONS.md`'s "open bitmask set expressed as a plain C enum" rule
 *    (matching `Align`/`Damage`/etc.'s treatment), not a closed D
 *    `enum` like the other four `Fl_Tree_*` enums in this header, which
 *    genuinely are exclusive/non-combinable and stay real D `enum`s.
 *  - `item_draw_callback()`/`Fl_Tree_Item_Draw_Callback` is a D
 *    delegate (`void delegate(TreeItem)`), not FLTK's C function
 *    pointer + separate `void* userdata` pair -- the usual callback
 *    substitution this port applies everywhere (`CONVENTIONS.md`'s
 *    "callbacks are D delegates" convention); a delegate already
 *    closes over whatever context it needs, so there's no
 *    `item_draw_user_data()` counterpart either.
 *  - The 1.3.0-era obsolete name aliases (`labelfont()` vs.
 *    `item_labelfont()`, etc.) are ported too, as thin forwarding
 *    methods -- cheap, and this port defaults to faithful-unless-
 *    there's-a-specific-reason-not-to; unlike the Forms/XForms-era
 *    exclusions `CONVENTIONS.md` documents, these are ordinary FLTK API
 *    evolution (a same-library rename), not scaffolding for a defunct
 *    external toolkit.
 */
module fl.tree_prefs;

import fl.enumerations;
import fl.image : Image;
import fl.tree_item : TreeItem;

/// Sort order for items added to a tree. Ported from `Fl_Tree_Sort`.
enum TreeSort
{
    sortNone,
    sortAscending,
    sortDescending,
}

/// Connector line style between tree items. Ported from
/// `Fl_Tree_Connector`.
enum TreeConnector
{
    connectorNone,
    connectorDotted,
    connectorSolid,
}

/// Tree selection style. Ported from `Fl_Tree_Select`.
enum TreeSelect
{
    selectNone,
    selectSingle,
    selectMulti,
    selectSingleDraggable,
}

/// Controls whether re-selecting an already-selected item fires a
/// callback. Ported from `Fl_Tree_Item_Reselect_Mode`.
enum TreeItemReselectMode
{
    selectableOnce,
    selectableAlways,
}

/// Open bitmask set (combines via `|`) controlling how an item's label
/// and `widget()` are drawn together. See this module's own top comment
/// for why this is `alias int` rather than a closed `enum`, unlike the
/// four exclusive enums above. Ported from `Fl_Tree_Item_Draw_Mode`.
alias TreeItemDrawMode = int;

enum : TreeItemDrawMode
{
    itemDrawDefault        = 0,
    itemDrawLabelAndWidget = 1,
    itemHeightFromWidget   = 2,
}

/// Ported from `Fl_Tree_Item_Draw_Callback` -- see this module's own
/// top comment for the function-pointer+void* -> delegate substitution.
alias TreeItemDrawCallback = void delegate(TreeItem);

/**
 * Tree widget's preferences/settings -- fonts, colors, margins, icons,
 * selection/connector style. A `Tree` owns exactly one instance and
 * every `TreeItem` in it shares that same instance (`TreeItem.prefs()`
 * returns it directly, not a copy). Ported from `Fl_Tree_Prefs`.
 */
class TreePrefs
{
    private Font labelfont_;
    private Fontsize labelsize_;
    private int margintop_;
    private int marginleft_;
    private int marginbottom_;
    private int openchildMarginbottom_;
    private int usericonmarginleft_;
    private int labelmarginleft_;
    private int widgetmarginleft_;
    private int connectorwidth_;
    private int linespacing_;
    private Color labelfgcolor_;
    private Color labelbgcolor_;
    private Color connectorcolor_;
    private TreeConnector connectorstyle_;
    private Image openimage_;
    private Image closeimage_;
    private Image userimage_;
    private Image opendeimage_;   // derived+cached by openicon(Image) -- see that setter
    private Image closedeimage_;  // derived+cached by closeicon(Image)
    private Image userdeimage_;   // derived+cached by usericon(Image)
    private bool showcollapse_;
    private bool showroot_;
    private TreeSort sortorder_;
    private Boxtype selectbox_;
    private TreeSelect selectmode_;
    private TreeItemReselectMode itemreselectmode_;
    private TreeItemDrawMode itemdrawmode_;
    private TreeItemDrawCallback itemdrawcallback_;

    /// Ported from Fl_Tree_Prefs::Fl_Tree_Prefs() -- defaults assigned
    /// in the constructor body rather than as field initializers since
    /// fl.enumerations.normalSize is a plain runtime global (not a
    /// compile-time manifest constant), matching FLTK's own
    /// constructor-body initialization exactly rather than fighting it.
    this()
    {
        labelfont_ = helvetica;
        labelsize_ = normalSize;
        marginleft_ = 6;
        margintop_ = 3;
        marginbottom_ = 20;
        openchildMarginbottom_ = 0;
        usericonmarginleft_ = 3;
        labelmarginleft_ = 3;
        widgetmarginleft_ = 3;
        linespacing_ = 0;
        labelfgcolor_ = foregroundColor;
        labelbgcolor_ = 0xffffffff; // used as 'transparent'
        connectorcolor_ = inactiveColor;
        connectorstyle_ = TreeConnector.connectorDotted;
        showcollapse_ = true;
        showroot_ = true;
        connectorwidth_ = 17;
        sortorder_ = TreeSort.sortNone;
        selectbox_ = Boxtype.thinUpBox;
        selectmode_ = TreeSelect.selectSingle;
        itemreselectmode_ = TreeItemReselectMode.selectableOnce;
        itemdrawmode_ = itemDrawDefault;
    }

    ////////////////////////////
    // Labels
    ////////////////////////////

    /// Return the label's font.
    Font itemLabelfont() const { return labelfont_; }
    /// Set the label's font to val.
    void itemLabelfont(Font val) { labelfont_ = val; }
    /// Return the label's size in pixels.
    Fontsize itemLabelsize() const { return labelsize_; }
    /// Set the label's size in pixels to val.
    void itemLabelsize(Fontsize val) { labelsize_ = val; }
    /// Get the default label foreground color.
    Color itemLabelfgcolor() const { return labelfgcolor_; }
    /// Set the default label foreground color.
    void itemLabelfgcolor(Color val) { labelfgcolor_ = val; }
    /// Get the default label background color. Returns Tree.color()
    /// unless itemLabelbgcolor() has been set explicitly.
    Color itemLabelbgcolor() const { return labelbgcolor_; }
    /// Set the default label background color. Once set, overrides the
    /// default behavior of using Tree.color().
    void itemLabelbgcolor(Color val) { labelbgcolor_ = val; }

    /////////////////
    // Obsolete names -- 1.3.0 backwards compat, ported as thin
    // forwarders (see this module's own top comment for why).
    /////////////////

    /// Obsolete: use itemLabelfont() instead.
    Font labelfont() const { return labelfont_; }
    /// Obsolete: use itemLabelfont(Font) instead.
    void labelfont(Font val) { labelfont_ = val; }
    /// Obsolete: use itemLabelsize() instead.
    Fontsize labelsize() const { return labelsize_; }
    /// Obsolete: use itemLabelsize(Fontsize) instead.
    void labelsize(Fontsize val) { labelsize_ = val; }
    /// Obsolete: use itemLabelfgcolor() instead.
    Color labelfgcolor() const { return labelfgcolor_; }
    /// Obsolete: use itemLabelfgcolor(Color) instead.
    void labelfgcolor(Color val) { labelfgcolor_ = val; }
    /// Obsolete: use itemLabelbgcolor() instead.
    Color labelbgcolor() const { return itemLabelbgcolor(); }
    /// Obsolete: use itemLabelbgcolor(Color) instead.
    void labelbgcolor(Color val) { itemLabelbgcolor(val); }

    ////////////////////////////
    // Margins
    ////////////////////////////

    /// Get the left margin's value in pixels.
    int marginleft() const { return marginleft_; }
    /// Set the left margin's value in pixels.
    void marginleft(int val) { marginleft_ = val; }
    /// Get the top margin's value in pixels.
    int margintop() const { return margintop_; }
    /// Set the top margin's value in pixels.
    void margintop(int val) { margintop_ = val; }
    /// Get the bottom margin's value in pixels -- the extra distance
    /// the vertical scroller lets you travel.
    int marginbottom() const { return marginbottom_; }
    /// Set the bottom margin's value in pixels.
    void marginbottom(int val) { marginbottom_ = val; }
    /// Get the margin below an open child in pixels.
    int openchildMarginbottom() const { return openchildMarginbottom_; }
    /// Set the margin below an open child in pixels.
    void openchildMarginbottom(int val) { openchildMarginbottom_ = val; }
    /// Get the user icon's left margin value in pixels.
    int usericonmarginleft() const { return usericonmarginleft_; }
    /// Set the user icon's left margin value in pixels.
    void usericonmarginleft(int val) { usericonmarginleft_ = val; }
    /// Get the label's left margin value in pixels.
    int labelmarginleft() const { return labelmarginleft_; }
    /// Set the label's left margin value in pixels.
    void labelmarginleft(int val) { labelmarginleft_ = val; }
    /// Get the widget()'s left margin value in pixels.
    int widgetmarginleft() const { return widgetmarginleft_; }
    /// Set the widget()'s left margin value in pixels.
    void widgetmarginleft(int val) { widgetmarginleft_ = val; }
    /// Get the line spacing value in pixels.
    int linespacing() const { return linespacing_; }
    /// Set the line spacing value in pixels.
    void linespacing(int val) { linespacing_ = val; }

    ////////////////////////////
    // Colors and Styles
    ////////////////////////////

    /// Get the connector color used for tree connection lines.
    Color connectorcolor() const { return connectorcolor_; }
    /// Set the connector color used for tree connection lines.
    void connectorcolor(Color val) { connectorcolor_ = val; }
    /// Get the connector style.
    TreeConnector connectorstyle() const { return connectorstyle_; }
    /// Set the connector style.
    void connectorstyle(TreeConnector val) { connectorstyle_ = val; }
    /// Get the tree connection line's width.
    int connectorwidth() const { return connectorwidth_; }
    /// Set the tree connection line's width.
    void connectorwidth(int val) { connectorwidth_ = val; }

    ////////////////////////////
    // Icons
    ////////////////////////////

    /// Get the current default 'open' icon, or null if none.
    Image openicon() const { return cast(Image) openimage_; }
    int openiconW() const { return openimage_ !is null ? openimage_.w() : 11; }
    int openiconH() const { return openimage_ !is null ? openimage_.h() : 11; }
    /// Set the default 'open' icon. null restores the built-in [+] icon.
    /// Also derives (and caches) a deactivated copy, real via
    /// Image.copy()/inactive() -- see opendeicon().
    void openicon(Image val)
    {
        openimage_ = val;
        opendeimage_ = deriveDeicon(val);
    }

    /// Get the default 'close' icon, or null if none.
    Image closeicon() const { return cast(Image) closeimage_; }
    int closeiconW() const { return closeimage_ !is null ? closeimage_.w() : 11; }
    int closeiconH() const { return closeimage_ !is null ? closeimage_.h() : 11; }
    /// Set the default 'close' icon. null restores the built-in [-] icon.
    /// Also derives (and caches) a deactivated copy -- see closedeicon().
    void closeicon(Image val)
    {
        closeimage_ = val;
        closedeimage_ = deriveDeicon(val);
    }

    /// Get the default 'user icon' (default is null).
    Image usericon() const { return cast(Image) userimage_; }
    /// Set the default 'user icon'. Also derives (and caches) a
    /// deactivated copy -- see userdeicon().
    void usericon(Image val)
    {
        userimage_ = val;
        userdeimage_ = deriveDeicon(val);
    }

    /// Return the deactivated version of the open icon, if any.
    Image opendeicon() const { return cast(Image) opendeimage_; }
    /// Return the deactivated version of the close icon, if any.
    Image closedeicon() const { return cast(Image) closedeimage_; }
    /// Return the deactivated version of the user icon, if any.
    Image userdeicon() const { return cast(Image) userdeimage_; }

    /// Derives a deactivated (grayed-out) copy of val, or null if val
    /// is null. Ported from the shared pattern in Fl_Tree_Prefs::
    /// openicon(Fl_Image*)/closeicon(Fl_Image*)/usericon(Fl_Image*)
    /// (`_opendeimage = _openimage->copy(); _opendeimage->inactive();`,
    /// three times over in FLTK -- collapsed into one private
    /// helper here since D has no `delete`/manual-free bookkeeping to
    /// keep separate per call site).
    private static Image deriveDeicon(Image val)
    {
        if (val is null) return null;
        Image d = val.copy();
        d.inactive();
        return d;
    }

    ////////////////////////////
    // Options
    ////////////////////////////

    /// True if the collapse icon is enabled.
    bool showcollapse() const { return showcollapse_; }
    /// Set whether to show the collapse icon. If disabled, the user
    /// can't interactively collapse items unless the application
    /// provides some other means via open()/close().
    void showcollapse(bool val) { showcollapse_ = val; }
    /// Get the default sort order value.
    TreeSort sortorder() const { return sortorder_; }
    /// Set the default sort order value -- the order new items appear
    /// when add()ed to the tree.
    void sortorder(TreeSort val) { sortorder_ = val; }
    /// Get the default selection box's box drawing style.
    Boxtype selectbox() const { return selectbox_; }
    /// Set the default selection box's box drawing style.
    void selectbox(Boxtype val) { selectbox_ = val; }
    /// True if the root item is shown.
    bool showroot() const { return showroot_; }
    /// Set whether the root item should be shown.
    void showroot(bool val) { showroot_ = val; }
    /// Get the selection mode used for the tree.
    TreeSelect selectmode() const { return selectmode_; }
    /// Set the selection mode used for the tree -- affects how items
    /// are selected when clicked on and dragged over by the mouse.
    void selectmode(TreeSelect val) { selectmode_ = val; }
    /// Get the current item re/selection mode.
    TreeItemReselectMode itemReselectMode() const { return itemreselectmode_; }
    /// Set the item re/selection mode.
    void itemReselectMode(TreeItemReselectMode val) { itemreselectmode_ = val; }
    /// Get the 'item draw mode' used for the tree.
    TreeItemDrawMode itemDrawMode() const { return itemdrawmode_; }
    /// Set the 'item draw mode' used for the tree -- affects how items
    /// are drawn, such as when a widget() is defined.
    void itemDrawMode(TreeItemDrawMode val) { itemdrawmode_ = val; }
    /// Set a callback used to draw items instead of the default
    /// rendering.
    void itemDrawCallback(TreeItemDrawCallback cb) { itemdrawcallback_ = cb; }
    /// Get the current item-draw callback, or null if none.
    TreeItemDrawCallback itemDrawCallback() const
    {
        return cast(TreeItemDrawCallback) itemdrawcallback_;
    }
    /// Invokes the item-draw callback for item o. Caller must first
    /// check itemDrawCallback() !is null.
    void doItemDrawCallback(TreeItem o) const
    {
        (cast(TreeItemDrawCallback) itemdrawcallback_)(o);
    }
}

unittest
{
    auto p = new TreePrefs();

    // Constructor defaults match FLTK's Fl_Tree_Prefs::Fl_Tree_Prefs().
    assert(p.itemLabelfont() == helvetica);
    assert(p.itemLabelsize() == normalSize);
    assert(p.marginleft() == 6);
    assert(p.margintop() == 3);
    assert(p.marginbottom() == 20);
    assert(p.openchildMarginbottom() == 0);
    assert(p.usericonmarginleft() == 3);
    assert(p.labelmarginleft() == 3);
    assert(p.widgetmarginleft() == 3);
    assert(p.linespacing() == 0);
    assert(p.itemLabelfgcolor() == foregroundColor);
    assert(p.itemLabelbgcolor() == 0xffffffff);
    assert(p.connectorcolor() == inactiveColor);
    assert(p.connectorstyle() == TreeConnector.connectorDotted);
    assert(p.openicon() is null);
    assert(p.closeicon() is null);
    assert(p.usericon() is null);
    assert(p.showcollapse());
    assert(p.showroot());
    assert(p.connectorwidth() == 17);
    assert(p.sortorder() == TreeSort.sortNone);
    assert(p.selectbox() == Boxtype.thinUpBox);
    assert(p.selectmode() == TreeSelect.selectSingle);
    assert(p.itemReselectMode() == TreeItemReselectMode.selectableOnce);
    assert(p.itemDrawMode() == itemDrawDefault);
    assert(p.itemDrawCallback() is null);

    // Icon size falls back to the built-in default with no image set.
    assert(p.openiconW() == 11);
    assert(p.openiconH() == 11);
    assert(p.closeiconW() == 11);
    assert(p.closeiconH() == 11);

    // Obsolete 1.3.0 names forward to the same storage as the
    // item_-prefixed ones.
    p.labelfont(courier);
    assert(p.itemLabelfont() == courier);
    p.itemLabelsize(20);
    assert(p.labelsize() == 20);
    p.labelbgcolor(red);
    assert(p.itemLabelbgcolor() == red);

    // item_draw_mode is a real bitmask, not an exclusive enum -- both
    // bits can be set simultaneously.
    p.itemDrawMode(itemDrawLabelAndWidget | itemHeightFromWidget);
    assert((p.itemDrawMode() & itemDrawLabelAndWidget) != 0);
    assert((p.itemDrawMode() & itemHeightFromWidget) != 0);
}

unittest
{
    // Real icon sizing + deactivated-icon derivation: setting a real
    // image reports its own w()/h() instead of the built-in default,
    // and each setter derives (and caches) a grayed-out copy, distinct
    // from the original (never mutates the original -- Image.copy()'s
    // own documented contract), that opendeicon()/closedeicon()/
    // userdeicon() then expose.
    import fl.image : RGBImage;

    auto p = new TreePrefs();
    ubyte[] bits = [255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 0];

    auto openImg = new RGBImage(bits.dup, 2, 2, 3);
    p.openicon(openImg);
    assert(p.openicon() is openImg);
    assert(p.openiconW() == 2 && p.openiconH() == 2);
    assert(p.opendeicon() !is null);
    assert(p.opendeicon() !is openImg);
    assert((cast(RGBImage) p.opendeicon()).array != openImg.array); // dimmed, not identical

    auto closeImg = new RGBImage(bits.dup, 2, 2, 3);
    p.closeicon(closeImg);
    assert(p.closeiconW() == 2 && p.closeiconH() == 2);
    assert(p.closedeicon() !is null && p.closedeicon() !is closeImg);

    auto userImg = new RGBImage(bits.dup, 2, 2, 3);
    p.usericon(userImg);
    assert(p.usericon() is userImg);
    assert(p.userdeicon() !is null && p.userdeicon() !is userImg);

    // Clearing an icon (null) also clears its cached deicon.
    p.openicon(null);
    assert(p.openicon() is null);
    assert(p.opendeicon() is null);
    assert(p.openiconW() == 11); // falls back to the built-in default again
}
