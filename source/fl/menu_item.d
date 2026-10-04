/*
 * Ported from FL/Fl_Menu_Item.H + the item-level (non-popup-engine)
 * parts of src/Fl_Menu.cxx (FLTK 1.5.0): the flat-array menu item
 * representation shared by Fl_Menu_Bar/Fl_Menu_Button/Fl_Choice/
 * Fl_Input_Choice, and the popup() / pulldown() free functions.
 *
 * Deviations from FLTK, all deliberate:
 *
 *  - `callback_` is a D delegate (fl.widget.Callback = void
 *    delegate(Widget)), the same substitution CLAUDE.md documents for
 *    Fl_Callback elsewhere in this port -- no companion `void*
 *    user_data()`/`argument()` slot, since a delegate already closes
 *    over whatever context it needs. FLTK's `do_callback(Fl_Widget*,
 *    void* arg, ...)` / `do_callback(Fl_Widget*, long arg, ...)`
 *    overloads exist only to override that user_data at call time, so
 *    they have no D equivalent here -- same as Fl_Widget's do_callback.
 *  - FL_SUBMENU_POINTER's use of `user_data_` FLTK is unrelated to
 *    callbacks -- it's a `Fl_Menu_Item*` smuggled through a `void*`
 *    slot to point at a detached submenu array. That gets its own
 *    typed field, `submenuItems_`, instead of overloading a generic
 *    user_data slot that no longer exists in the callback-carrying
 *    sense.
 *  - Multi-part labels reuse fl.multi_label's already-ported
 *    `MultiLabel` class via a dedicated `multi` field, exactly
 *    matching fl.widget's `Label.multi` -- instead of FLTK's
 *    `Fl_Multi_Label*` pointer-punned through `text`. Images use a
 *    dedicated `image_` field, drawn by the normal label path (see
 *    `image()`'s own doc comment) -- same substitution as `multi`,
 *    instead of porting FLTK's obsolete `image_label()`/
 *    `_FL_IMAGE_LABEL` pointer-punning mechanism.
 *  - `measure()`/`draw()` take a `MenuStyle` struct (textfont/
 *    textsize/textcolor/selectionColor/downBox) instead of FLTK's
 *    `const Fl_Menu_*` -- fl.menu_ doesn't exist yet (see PORTING.md),
 *    but more importantly, FLTK's own `popup()`/`pulldown()` are
 *    designed to work with a null Fl_Menu_* (a standalone popup with
 *    no owning widget at all) -- a plain style struct is actually a
 *    closer match to that "optional style source" spirit than a
 *    forward reference to a widget class would be. Once fl.menu_
 *    exists it just builds a MenuStyle from its own fields to call
 *    through.
 *  - `popup()`/`pulldown()` (the actual popup-window engine) live in
 *    fl.menu_popup, not here -- see that module and PORTING.md's Menus
 *    rows for the documented simplifications (no real XGrabPointer/
 *    XGrabKeyboard, single content window per cascade level, no tear-
 *    off title windows, no autoscroll for oversized menus).
 *  - `add()`/`insert()` are NOT ported onto MenuItem itself. FLTK
 *    marks the standalone bare-array `Fl_Menu_Item::add()`/`insert()`
 *    "quite depreciated, should not be used" in its own source comment
 *    (Fl_Menu_add.cxx) -- real callers use `Fl_Menu_::add()`/
 *    `insert()` instead, which own a growable array. That's a much
 *    better fit for a D dynamic `MenuItem[]` (`~=`/
 *    `std.array.insertInPlace`) than for a raw `MenuItem*` -- so
 *    add()/insert()/remove()/replace()/menu_end() are ported once onto
 *    fl.menu_'s widget-owned array instead of duplicated here. That
 *    also drops FLTK's `local_array`/`fl_menu_array_owner`
 *    process-wide singleton entirely: it exists purely to let several
 *    unrelated widgets share one realloc-doubling scratch buffer under
 *    manual memory management, which a GC-backed dynamic array has no
 *    need for.
 */
module fl.menu_item;

import fl.widget : Widget, Callback, Label;
import fl.multi_label : MultiLabel;
import fl.image : Image;
import fl.rect : Rect;
import fl.enumerations : Labeltype, Font, Fontsize, Color, CallbackReason,
    Boxtype, helvetica, normalSize, foregroundColor, selectionColor,
    background2Color, backgroundColor, alignLeft;
import fldraw = fl.draw;
static import fl.core;
static import fl.enumerations;

/// Fl_Menu_Item's flags: an open bitmask (combine with `|`), so this
/// follows the established Align/Color/When/Damage convention (alias +
/// manifest constants) rather than a closed `enum`.
alias MenuFlags = int;

enum : MenuFlags
{
    menuInactive        = 1,      /// FL_MENU_INACTIVE: deactivate item (gray out)
    menuToggle          = 2,      /// FL_MENU_TOGGLE: item shows a checkbox
    menuValue           = 4,      /// FL_MENU_VALUE: checkbox/radio on/off state
    menuRadio           = 8,      /// FL_MENU_RADIO: item is a radio button
    menuInvisible       = 0x10,   /// FL_MENU_INVISIBLE: hidden (shortcut still works)
    menuSubmenuPointer  = 0x20,   /// FL_SUBMENU_POINTER: submenuItems_ points at a detached array
    menuSubmenu         = 0x40,   /// FL_SUBMENU: item is a submenu title, embedded inline
    menuDivider         = 0x80,   /// FL_MENU_DIVIDER: divider line below this item
    menuHorizontal      = 0x100,  /// FL_MENU_HORIZONTAL: reserved, unused (matches FLTK)
    menuChatty          = 0x200,  /// FL_MENU_CHATTY: item also gets gotFocus/lostFocus callbacks
    menuHeadline        = 0x400,  /// FL_MENU_HEADLINE: non-selectable section heading
}

/**
 * The subset of Fl_Menu_'s style state that measure()/draw() fall
 * back on when an item doesn't set its own labelfont_/labelsize_/
 * labelcolor_ (see the module doc comment on why this replaces
 * FLTK's `const Fl_Menu_*` parameter). Defaults match
 * Fl_Menu_::Fl_Menu_()'s own field initializers.
 */
struct MenuStyle
{
    Font textfont;
    Fontsize textsize;
    Color textcolor;
    Color selectionColor;
    Boxtype downBox;

    /// The popup window's own background fill -- ported from FLTK's
    /// `Menu_Window`'s `color(button && !Fl::scheme() ? button->color()
    /// : FL_GRAY)` (`Fl_Menu.cxx`): the *owning widget's own* `.color()`
    /// (not a fixed constant), so e.g. `Fl_Choice`'s temporary "preserve
    /// the old white-menu look-n-feel" override (`Fl_Choice::handle()`,
    /// see `fl.choice`'s own doc comment/`doPulldown()`) actually shows
    /// up in the popup, not just in the (unaffected either way) closed
    /// widget. Defaults to `backgroundColor` here, matching FLTK's
    /// own `FL_GRAY` fallback for the no-owning-widget case -- in
    /// practice every real caller in this port always has one and sets
    /// this from its own `color()` instead (see `Menu_.style()`).
    Color windowColor;

    /// Built at call time (not as field initializers) since these
    /// mirror mutable module-level globals (fl.enumerations.normalSize
    /// etc.) that aren't compile-time constants.
    static MenuStyle defaults()
    {
        MenuStyle s;
        s.textfont = helvetica;
        s.textsize = normalSize;
        s.textcolor = foregroundColor;
        s.selectionColor = fl.enumerations.selectionColor;
        s.downBox = Boxtype.noBox;
        s.windowColor = backgroundColor;
        return s;
    }
}

/**
 * Verifies `items` is properly sentinel-terminated -- every embedded
 * submenu (`menuSubmenu`) closed by a matching null-`text` item, and
 * the whole array ending in one too -- using safe, bounds-checked D
 * array indexing throughout (`foreach` over the slice; never a raw
 * pointer, and never reads past `items.length`). This is deliberately
 * *not* how `MenuItem.next()`/`size()`/etc. themselves walk an array
 * (see `MenuItem`'s own doc comment for why that still mirrors
 * FLTK's raw `Fl_Menu_Item*` pointer arithmetic almost verbatim --
 * the flat, sentinel-delimited, embedded-submenu format is inherent to
 * FLTK's own menu-array API, not something this port can safely
 * abandon while staying compatible with how real menu arrays get
 * authored). What FLTK *can't* do anything about -- a bare
 * `Fl_Menu_Item*` carries no length at all, so a missing trailing
 * `{0}` is undefined behavior there too -- this port can, since every
 * menu array arrives at `Menu_.menu()` (`fl.menu_.d`) as a real,
 * length-tracked `MenuItem[]` slice *before* it's ever converted to a
 * raw pointer for the popup engine. Called from there specifically so
 * every `Menu_`-owning widget (`Choice`/`MenuBar`/`MenuButton`/
 * `InputChoice`) gets this check for free at the one common entry
 * point, rather than needing it duplicated in each.
 *
 * Without this check, a menu array missing its trailing sentinel (e.g.
 * `samples/test/label.d`'s `Choice` dropdown) lets `MenuItem.next()`'s
 * pointer walk read past the array's own end into unrelated memory,
 * corrupting a `MenuItem.text` string that can later crash `fl.draw`
 * with a `SIGSEGV` three call-levels away, nowhere near the actual
 * mistake. Throws a clear, immediate, actionable exception here
 * instead.
 */
void validateMenuArray(const(MenuItem)[] items)
{
    if (items.length == 0) return;

    int nest = 0;
    foreach (ref const item; items)
    {
        if (item.text is null)
        {
            if (nest == 0) return; // found the closing sentinel, in bounds
            nest--;
        }
        else if (item.flags & menuSubmenu)
        {
            nest++;
        }
    }

    import std.conv : to;
    throw new Exception("MenuItem[] array of length " ~ items.length.to!string ~
        " is missing its trailing null-text sentinel (a default-initialized " ~
        "`MenuItem.init` -- or FLTK's own spelling, `MenuItem(null)` -- " ~
        "as the last element): fl.menu_item's item-array walk relies on it " ~
        "to know where the array (or an embedded submenu within it) ends; " ~
        "without it, the walk would read past the array into undefined " ~
        "memory instead.");
}

/**
 * Fl_Menu_Item's D equivalent: a plain flat-array element, not a
 * Widget. Arrays are built the same way FLTK's static tables are
 * (a trailing default-initialized `MenuItem` -- `text is null` --
 * marks the end of the array/submenu, exactly like FLTK's
 * trailing `{0}`), since `next()`/`size()`/etc. walk memory the same
 * way FLTK's do via pointer arithmetic on `&this`.
 */
struct MenuItem
{
    string text;
    int shortcut_;
    Callback callback_;
    MenuItem* submenuItems_;  // valid only when flags & menuSubmenuPointer
    MenuFlags flags;
    Labeltype labeltype_;  // normalLabel(0); labelsize_/labelfont_/labelcolor_ also
    Font labelfont_;       // default to 0 (helvetica/unset), matching FLTK's
    Fontsize labelsize_;   // array_insert() zero-fill -- 0 here means "fall back
    Color labelcolor_;     // to the owning fl.menu_'s textfont()/textsize()/etc."
    MultiLabel multi;  // set via multiLabel(), valid when labeltype_ == multiLabel
    Image image_;      // set via image(Image); composed alongside text by the
                        // normalLabel path once measure()/draw() build a Label
                        // from this item's fields -- see image()'s own doc comment
                        // for why this replaces FLTK's image_label() instead
                        // of also porting it.

    this(string text, int shortcut = 0, Callback callback = null, MenuFlags flags = 0)
    {
        this.text = text;
        this.shortcut_ = shortcut;
        this.callback_ = callback;
        this.flags = flags;
    }

    /// Convenience overload for the extremely common "no shortcut"
    /// case: `MenuItem("text", callback)` doesn't resolve against the
    /// main constructor above, since its 2nd positional parameter is
    /// `int shortcut`, not `Callback` -- and D doesn't synthesize an
    /// overload set covering every combination of default parameters
    /// being skipped, unlike C++ default-argument call sites. This
    /// overload exists purely to make that call shape work; it forwards
    /// to the main constructor with `shortcut = 0`.
    this(string text, Callback callback, MenuFlags flags = 0)
    {
        this(text, 0, callback, flags);
    }

    /// Extended overload matching FLTK's full positional
    /// struct-literal init -- `Fl_Menu_Item`'s field order is `text,
    /// shortcut_, callback_, user_data_, flags, labeltype_, labelfont_,
    /// labelsize_, labelcolor_`, and plenty of real menu tables
    /// (`test/menubar.cxx`'s `menutable[]` among them) set fields all the
    /// way out to `labelfont_`/`labelcolor_` via that positional form.
    /// `user_data_` is dropped, same as the main constructor above (this
    /// port's `MenuItem` has no equivalent slot at all -- see
    /// CLAUDE.md's callback-porting convention), so this lines up with
    /// FLTK's field order minus that one slot. `labelfont`/
    /// `labelsize`/`labelcolor` default to `0`, matching this struct's
    /// own documented field semantics (**not** FLTK's literal
    /// `FL_NORMAL_SIZE` etc. default) -- `0` means "fall back to the
    /// owning `fl.menu_`'s `textfont()`/`textsize()`/etc.", same as
    /// leaving them unset via the main constructor already does.
    this(string text, int shortcut, Callback callback, MenuFlags flags,
            Labeltype labeltype, Font labelfont = 0, Fontsize labelsize = 0,
            Color labelcolor = 0)
    {
        this.text = text;
        this.shortcut_ = shortcut;
        this.callback_ = callback;
        this.flags = flags;
        this.labeltype_ = labeltype;
        this.labelfont_ = labelfont;
        this.labelsize_ = labelsize;
        this.labelcolor_ = labelcolor;
    }

    /// Overload for the `menuSubmenuPointer` case -- FLTK reuses the
    /// same `user_data_` slot as the detached-submenu-array pointer when
    /// `FL_SUBMENU_POINTER` is set (a `void*` reinterpreted as
    /// `Fl_Menu_Item*`); this port instead gives `submenuItems_` its own
    /// dedicated field (see that field's own doc comment), so the
    /// positional-init call shape needs its own overload rather than
    /// reusing the dropped user_data_ slot like the plain-flags
    /// constructor above does.
    this(string text, int shortcut, Callback callback, MenuFlags flags,
            MenuItem* submenuItems)
    {
        this.text = text;
        this.shortcut_ = shortcut;
        this.callback_ = callback;
        this.flags = flags;
        this.submenuItems_ = submenuItems;
    }

    // ---- array walking ----------------------------------------------

    /// Advances past the contents of a submenu (embedded or not),
    /// stopping on the sentinel or the next top-level item -- ported
    /// from Fl_Menu.cxx's file-static next_visible_or_not(), which
    /// next()/size()/testShortcut()/findShortcut() all build on.
    private static inout(MenuItem)* nextVisibleOrNot(inout(MenuItem)* m)
    {
        int nest = 0;
        do
        {
            if (m.text is null)
            {
                if (nest == 0) return m;
                nest--;
            }
            else if (m.flags & menuSubmenu)
            {
                nest++;
            }
            m++;
        }
        while (nest);
        return m;
    }

    /// Advances by n items, skipping submenu contents and invisible
    /// items. A null label() on the returned item means "end of array
    /// or submenu".
    inout(MenuItem)* next(int n = 1) inout
    {
        if (n < 0) return null; // so value()==-1 (see fl.menu_) returns null
        inout(MenuItem)* m = &this;
        if (!m.visible()) n++;
        while (n)
        {
            m = nextVisibleOrNot(m);
            if (m.visible() || m.text is null) n--;
        }
        return m;
    }

    inout(MenuItem)* first() inout { return next(0); }

    /// Size of this (sub)menu array in elements, including the
    /// trailing sentinel.
    int size() const
    {
        const(MenuItem)* m = &this;
        int nest = 0;
        for (;;)
        {
            if (m.text is null)
            {
                if (nest == 0) return cast(int) (m - &this) + 1;
                nest--;
            }
            else if (m.flags & menuSubmenu)
            {
                nest++;
            }
            m++;
        }
    }

    // ---- label / labeltype -------------------------------------------

    string label() const { return text; }
    void label(string a) { text = a; }
    void label(Labeltype t, string a) { labeltype_ = t; text = a; }

    /// D counterpart of Fl_Menu_Item::multi_label(): sets label()/
    /// labeltype() to a fl.multi_label.MultiLabel, same substitution
    /// fl.widget's Widget.label(MultiLabel) makes for a class
    /// reference where FLTK smuggles a pointer through `text`.
    ///
    /// **Deliberately leaves `text` untouched**: FLTK's own
    /// `label()`/`text` is a raw `const char*` that can be
    /// pointer-punned to smuggle the `Fl_Multi_Label*` itself through,
    /// so FLTK's version genuinely does end up with a non-null
    /// `text` for a multi-label item -- it's never actually `nullptr`
    /// there, just reinterpreted. This port's `text` is a real
    /// `string`, so nulling it out here (on the reasoning that `text`
    /// becomes meaningless once `multi` takes over drawing) would miss
    /// a structural fact `MenuItem.nextVisibleOrNot()`/`size()`/
    /// `Menu_.insert()`'s own path-matching search all depend on
    /// throughout this whole module: `text is null` is the array's own
    /// sentinel/end-of-(sub)menu marker, load-bearing for *every* item,
    /// not just ones that happen to have an empty label. Nulling a live
    /// item's `text` would make every later sibling-scanning walk (a
    /// whole submenu built via several sequential `Menu_.add()` calls,
    /// each icon set right after its own `add()` — exactly `&New`'s own
    /// construction order in `fluid.gui_main`) mistake that item for
    /// the submenu's real closing sentinel: later siblings would get
    /// inserted *before* it instead of after, and per-submenu item
    /// counts would come out wrong, both of which would show up as "New
    /// menu items are empty" (search loops silently stopping early, item
    /// slots shifting) rather than any drawing-code symptom.
    /// `findShortcut()`'s
    /// own `m.text !is null` loop condition (just below) and its
    /// `m.labeltype_ != Labeltype.multiLabel && ...` guard around testing
    /// `m.text` as a shortcut source both already anticipate `text`
    /// staying populated for a multiLabel item, matching this setter's
    /// own behavior. `l.text = text;` in
    /// `measure()`/`draw()` below is harmless with `text` left set: the
    /// `multiLabel` case in `fl.widget.Label.draw()`/`measure()`
    /// dispatches straight into `multi`, never reading `l.text` at all.
    void multiLabel(MultiLabel ml)
    {
        labeltype_ = Labeltype.multiLabel;
        multi = ml;
    }

    /// Gets/sets the image drawn alongside this item's label. D
    /// counterpart of FLTK's `image_label()`/`Fl_Image::label
    /// (Fl_Menu_Item*)` (both funnel through the same obsolete
    /// `_FL_IMAGE_LABEL` pointer-punning-through-`text` mechanism FLTK
    /// itself deprecates in favor of a real field) -- same substitution
    /// `fl.widget`'s `Label.image` already makes, and for the same
    /// reason: `image_` is a real typed field, drawn by the normal
    /// label-drawing path (`measure()`/`draw()` below both copy it into
    /// the `Label` they build), so a separate `imageLabel` labeltype
    /// dispatch would just be a redundant second way to draw the exact
    /// same pixels. No `deimage()` counterpart -- FLTK's own
    /// `Fl_Menu_Item` doesn't have one either (unlike `Fl_Widget`).
    Image image() const { return cast(Image) image_; }
    void image(Image img) { image_ = img; } /// ditto

    Labeltype labeltype() const { return labeltype_; }
    void labeltype(Labeltype a) { labeltype_ = a; }

    Color labelcolor() const { return labelcolor_; }
    void labelcolor(Color a) { labelcolor_ = a; }

    Font labelfont() const { return labelfont_; }
    void labelfont(Font a) { labelfont_ = a; }

    Fontsize labelsize() const { return labelsize_; }
    void labelsize(Fontsize a) { labelsize_ = a; }

    // ---- callback -----------------------------------------------------

    Callback callback() const { return callback_; }
    void callback(Callback c) { callback_ = c; }

    /// Calls the item's callback with the given widget (the menu/
    /// button that owns this item, matching FLTK's
    /// `do_callback(Fl_Widget*, ...)`). Caller must check callback()
    /// is non-null first, exactly like FLTK.
    void doCallback(Widget o, CallbackReason reason = CallbackReason.unknown) const
    {
        fl.core.callbackReason(reason);
        callback_(o);
    }

    // ---- shortcut -----------------------------------------------------

    int shortcut() const { return shortcut_; }
    void shortcut(int s) { shortcut_ = s; }

    // ---- flag-bit accessors --------------------------------------------

    int submenu() const { return flags & (menuSubmenu | menuSubmenuPointer); }
    int checkbox() const { return flags & menuToggle; }
    int radio() const { return flags & menuRadio; }

    int value() const { return (flags & menuValue) ? 1 : 0; }
    void value(int v) { if (v) set(); else clear(); }
    void set() { flags |= menuValue; }
    void clear() { flags &= ~menuValue; }

    /**
     * Turns this radio item on, turning off adjacent radio items in
     * the same group (stopping at a divider, a non-radio item, the
     * sentinel, or -- going upward -- at `first`). Ported from
     * Fl_Menu_Item::setonly(Fl_Menu_Item const*); the safer
     * Fl_Menu_::setonly(MenuItem*) overload (which finds `first`
     * itself by walking the owning widget's submenu structure) is
     * ported onto fl.menu_ instead, matching FLTK's own
     * recommendation to prefer it.
     */
    void setonly(const(MenuItem)* first = null)
    {
        flags |= menuRadio | menuValue;
        MenuItem* j;
        for (j = &this; ; )
        {
            if (j.flags & menuDivider) break;
            j++;
            if (j.text is null || !j.radio()) break;
            j.clear();
        }
        if (&this != first)
        {
            for (j = (&this) - 1; ; j--)
            {
                if (j.text is null || (j.flags & menuDivider) || !j.radio()) break;
                j.clear();
                if (j == first) break;
            }
        }
    }

    int visible() const { return !(flags & menuInvisible); }
    void show() { flags &= ~menuInvisible; }
    void hide() { flags |= menuInvisible; }

    int active() const { return !(flags & menuInactive); }
    void activate() { flags &= ~menuInactive; }
    void deactivate() { flags |= menuInactive; }

    int activevisible() const { return !(flags & (menuInactive | menuInvisible)); }
    int selectable() const { return !(flags & (menuInactive | menuInvisible | menuHeadline)); }

    void headline(bool yes)
    {
        if (yes) flags |= menuHeadline; else flags &= ~menuHeadline;
    }
    int headline() const { return flags & menuHeadline; }

    // ---- shortcut matching ----------------------------------------------

    /**
     * Recursively searches this (sub)menu array -- and, depth-first,
     * any nested submenus -- for an item whose shortcut() matches the
     * current FL_SHORTCUT event, top-level matches winning over
     * matches found deeper in a submenu. Ignores '&x'-in-label
     * shortcuts (see findShortcut() for that). Ported from
     * Fl_Menu_Item::test_shortcut().
     */
    const(MenuItem)* testShortcut() const
    {
        const(MenuItem)* ret = null;
        const(MenuItem)* m = &this;
        for (; m.text !is null; m = nextVisibleOrNot(m))
        {
            if (m.active())
            {
                if (fl.core.testShortcut(cast(uint) m.shortcut_)) return m;
                if (ret is null && m.submenu())
                {
                    const(MenuItem)* s = (m.flags & menuSubmenu) ? m + 1 : m.submenuItems_;
                    ret = s.testShortcut();
                }
            }
        }
        return ret;
    }

    /**
     * Searches this (sub)menu array (not nested submenus) for an item
     * whose shortcut_ value matches the current event, or whose label
     * has a matching '&x' shortcut. Ported from
     * Fl_Menu_Item::find_shortcut(); multi-part (MultiLabel) labels
     * are matched via `multi.textA`/`multi.textB` (see the module doc
     * comment on why that's a typed field here rather than a pointer
     * cast). Icon/image labels have no text to match and are skipped,
     * same as FLTK's is_special_labeltype() guard.
     */
    const(MenuItem)* findShortcut(int* ip = null, bool requireAlt = false) const
    {
        const(MenuItem)* m = &this;
        int ii = 0;
        for (; m.text !is null; m = nextVisibleOrNot(m), ii++)
        {
            if (m.active())
            {
                bool hit = fl.core.testShortcut(cast(uint) m.shortcut_)
                    || (m.labeltype_ != Labeltype.multiLabel
                        && Widget.testShortcut(m.text, requireAlt))
                    || (m.labeltype_ == Labeltype.multiLabel && m.multi !is null
                        && m.multi.typeA != Labeltype.multiLabel
                        && Widget.testShortcut(m.multi.textA, requireAlt))
                    || (m.labeltype_ == Labeltype.multiLabel && m.multi !is null
                        && m.multi.typeB != Labeltype.multiLabel
                        && Widget.testShortcut(m.multi.textB, requireAlt));
                if (hit)
                {
                    if (ip !is null) *ip = ii;
                    return m;
                }
            }
        }
        return null;
    }

    // ---- measure / draw ------------------------------------------------

    /**
     * Measures the label's width (including the checkbox/radio mark's
     * width, if any), returning the label height via `h`. Ported from
     * Fl_Menu_Item::measure(), including the `&`-shortcut-underline
     * toggle FLTK sets around the measurement (`fl_draw_shortcut =
     * 1`, unconditional -- unlike draw()'s guarded version below,
     * measure() has no nested-call concern to protect against).
     */
    int measure(out int h, const MenuStyle style = MenuStyle.defaults()) const
    {
        Label l;
        // `text` stays non-null even for an image-only item (`""`, never
        // `null` -- see label()'s own doc comment: `text is null` is the
        // flat array's end-of-(sub)menu sentinel, so a real item can't use
        // it to mean "no label"). Passed straight through, `l.text = ""`
        // would make fl.draw's `fl_draw()` (called from draw() below via
        // Label.draw()) count it as one real, non-null text line -- matching
        // FLTK's own C `if (str) {...}` line-counting exactly, but
        // FLTK never actually exercises that path here: `item->image()`
        // pointer-puns the image over `text` and switches labeltype to
        // `_FL_IMAGE_LABEL`, a wholly separate draw/measure pair
        // (`Fl_Image::labeltype()`/`measure()`) that centers the image
        // directly with no text line reserved at all. Since this port
        // deliberately keeps `image_` as its own field instead of
        // replicating that pointer-punning (see `image()`'s own doc
        // comment), reaching the same *pixels* depends on `l.text` here
        // being genuinely absent (`null`, giving `fl_draw()`'s already-
        // established `nLines = str is null ? 0 : ...` its 0-line case) for
        // a label that has no real text, not merely empty -- confirmed via
        // `examples/howto-menu-with-images`' own "Images" submenu (three
        // image-only items, each `label("")`'d for the sentinel reason
        // above): without this, `measure()` sized each item to the image's
        // own height (correctly, since it already checks `text.length`, not
        // nullness) while `draw()` still reserved an extra line of vertical
        // space for the phantom `""` text, shifting every image up by about
        // half an item's height into the item above it.
        l.text = text.length ? text : null;
        l.type = labeltype_;
        l.font = (labelsize_ || labelfont_) ? labelfont_ : style.textfont;
        l.size = labelsize_ ? labelsize_ : style.textsize;
        l.color = foregroundColor;
        l.hMargin = 0;
        l.vMargin = 0;
        l.spacing = 0;
        l.multi = cast(MultiLabel) multi;
        l.image = cast(Image) image_;

        fldraw.fl_draw_shortcut = 1;
        int w = 0;
        l.measure(w, h);
        fldraw.fl_draw_shortcut = 0;
        if (flags & (menuToggle | menuRadio)) w += style.textsize + 4;
        return w;
    }

    /**
     * Draws the item's background (if drawMode != 0), checkbox/radio
     * mark, and label within (x,y,w,h). Ported from
     * Fl_Menu_Item::draw(); drawMode: 0 = unselected, 1 = selected,
     * 2 = menu title. Doesn't draw the shortcut key combination text
     * to the right of the label -- FLTK leaves that to the popup
     * engine's own menuwindow::drawentry() too, not this function.
     */
    void draw(int x, int y, int w, int h, const MenuStyle style = MenuStyle.defaults(), int drawMode = 0) const
    {
        Label l;
        // See measure()'s matching `l.text` line above for why this isn't
        // just `l.text = text;` -- an image-only item's `text` is `""`,
        // never `null` (the sentinel), but `fl_draw()` needs a genuine
        // `null` to skip reserving a phantom text line above the image.
        l.text = text.length ? text : null;
        l.type = labeltype_;
        l.font = (labelsize_ || labelfont_) ? labelfont_ : style.textfont;
        l.size = labelsize_ ? labelsize_ : style.textsize;
        l.color = labelcolor_ ? labelcolor_ : style.textcolor;
        l.hMargin = 0;
        l.vMargin = 0;
        l.spacing = 0;
        l.multi = cast(MultiLabel) multi;
        l.image = cast(Image) image_;
        if (!active()) l.color = fldraw.inactive(cast(Color) l.color);

        if (drawMode)
        {
            Color r = style.selectionColor;
            Boxtype b = style.downBox != Boxtype.noBox ? style.downBox : Boxtype.flatBox;
            l.color = fldraw.contrast(cast(Color) labelcolor_, r);
            if (drawMode == 2) // menu title
            {
                fldraw.drawBoxAt(b, x, y, w, h, r);
                x += 3;
                w -= 8;
            }
            else
            {
                // Ported from FLTK's own `fl_draw_box(b, x+1, y-
                // (Fl::menu_linespacing()-2)/2, w-2, h+(Fl::menu_
                // linespacing()-2), r);` -- `fl.core.menuLinespacing()`
                // already existed (default 4, matching FLTK's own
                // `menu_linespacing_ = 4`), but this call site never
                // actually used it, drawing a plain `(x+1, y, w-2, h)`
                // box instead. At the default linespacing this grows
                // the box by 1 unit on each vertical edge (FLTK's
                // own dropdown-row use of the same formula bridges the
                // gap *between* rows, per `Fl_Menu.cxx`'s positioning
                // code) -- not a fix for the residual-highlight-trace
                // bug on its own (see `MenuBar`'s own module comment
                // for why that bug exists at all: unlike this port,
                // FLTK's `Fl_Menu_Bar::draw()` never invokes this
                // drawMode path in the first place -- it always calls
                // `Fl_Menu_Item::draw()` with the default `draw_mode=0`,
                // so FLTK's own top-level "File is open" highlight
                // is rendered entirely by the popup/cascade window
                // machinery overlaying the bar, never by a modification
                // to the bar's own persistent pixels that would ever
                // need erasing at all), just a separately-confirmed
                // missing piece of faithfully porting this function.
                int ls = fl.core.menuLinespacing();
                fldraw.drawBoxAt(b, x + 1, y - (ls - 2) / 2, w - 2, h + (ls - 2), r);
            }
        }

        if (flags & (menuToggle | menuRadio))
        {
            int d = (h - style.textsize + 1) / 2;
            int wBox = h - 2 * d;

            // Under the "gtk+" scheme, the checkbox/radio glyph's base
            // color is the global FL_SELECTION_COLOR constant, not
            // labelcolor_ -- `if (Fl::is_scheme("gtk+")) check_color =
            // FL_SELECTION_COLOR;` before the contrast() call (FLTK
            // uses the plain global constant here, deliberately not the
            // possibly-customized `m->selection_color()` -- so this uses
            // the same module-level `fl.enumerations.selectionColor`,
            // not `style.selectionColor`).
            Color checkBase = fl.core.isScheme("gtk+") ? fl.enumerations.selectionColor : labelcolor_;
            Color checkColor = fldraw.contrast(checkBase, background2Color);

            if (flags & menuRadio)
            {
                fldraw.drawBoxAt(Boxtype.roundDownBox, x + 2, y + d, wBox, wBox, background2Color);
                if (value())
                {
                    int tW = wBox / 2 + 1;
                    if ((wBox - tW) & 1) tW++;
                    int td = (wBox - tW) / 2;
                    fldraw.drawRadio(x + td + 1, y + d + td - 1, tW + 2, checkColor);
                }
            }
            else
            {
                fldraw.drawBoxAt(Boxtype.downBox, x + 2, y + d, wBox, wBox, background2Color);
                if (value())
                    fldraw.drawCheck(Rect(x + 3, y + d + 1, wBox - 2, wBox - 2), checkColor);
            }
            x += wBox + 3;
            w -= wBox + 3;
        }

        // Guarded rather than unconditional (unlike measure() above):
        // matches FLTK's `if (!fl_draw_shortcut) fl_draw_shortcut
        // = 1;` exactly, so a caller that pre-set fl_draw_shortcut to
        // `2` (fl.choice's "strip but don't underline" hack -- see
        // fl.draw's own doc comment) around this call isn't overridden
        // back to normal-underline mode.
        if (!fldraw.fl_draw_shortcut) fldraw.fl_draw_shortcut = 1;
        l.draw(x + 3, y, w > 6 ? w - 6 : 0, h, alignLeft);
        fldraw.fl_draw_shortcut = 0;
    }
}

unittest
{
    // next()/size(): a flat menu with one embedded submenu.
    MenuItem[] items = [
        MenuItem("alpha"),
        MenuItem("sub", 0, null, menuSubmenu),
        MenuItem("inner1"),
        MenuItem("inner2"),
        MenuItem(null), // end submenu
        MenuItem("beta"),
        MenuItem(null), // end array
    ];

    assert(items[0].size() == 7);
    assert(items[0].next().text == "sub");        // steps onto the submenu title itself
    assert(items[0].next(2).text == "beta");      // skips the whole submenu body
    assert(items[1].next().text == "beta");       // next() from a submenu title also
                                                   // skips its contents -- descending into
                                                   // a submenu is `m+1` pointer arithmetic
                                                   // (see testShortcut()), not next()
    assert((&items[1] + 1).text == "inner1");     // ...like this
    assert(items[0].next(3) is null || items[0].next(3).text is null); // past the end
}

unittest
{
    // visible()/invisible items are skipped by next(), not by size().
    MenuItem[] items = [
        MenuItem("one"),
        MenuItem("hidden", 0, null, menuInvisible),
        MenuItem("two"),
        MenuItem(null),
    ];
    assert(items[0].size() == 4);
    assert(items[0].next().text == "two"); // hidden is skipped
}

unittest
{
    // setonly(): radio group bounded by dividers.
    MenuItem[] items = [
        MenuItem("r1", 0, null, menuRadio | menuValue),
        MenuItem("r2", 0, null, menuRadio),
        MenuItem("r3", 0, null, menuRadio, ),
        MenuItem(null),
    ];
    items[2].flags |= menuDivider;
    items[1].setonly(&items[0]);
    assert(items[0].value() == 0);
    assert(items[1].value() == 1);
    assert(items[2].value() == 0);
}

unittest
{
    // value()/set()/clear()/checkbox()/radio()/submenu().
    MenuItem m = MenuItem("x", 0, null, menuToggle);
    assert(m.checkbox());
    assert(!m.radio());
    assert(m.value() == 0);
    m.value(1);
    assert(m.value() == 1);
    m.clear();
    assert(m.value() == 0);

    MenuItem s = MenuItem("s", 0, null, menuSubmenu);
    assert(s.submenu());
    MenuItem p = MenuItem("p", 0, null, menuSubmenuPointer);
    assert(p.submenu());
}

unittest
{
    // visible/active/headline bit accessors.
    MenuItem m = MenuItem("x");
    assert(m.visible());
    assert(m.active());
    assert(!m.headline());
    m.hide();
    assert(!m.visible());
    m.show();
    assert(m.visible());
    m.deactivate();
    assert(!m.active());
    assert(!m.activevisible());
    m.activate();
    m.headline(true);
    assert(m.headline());
    assert(!m.selectable());
}

unittest
{
    // callback(): a D delegate closing directly over state, no
    // user_data() slot needed.
    int calls = 0;
    Widget seen;
    MenuItem m = MenuItem("x");
    m.callback((Widget w) { calls++; seen = w; });
    assert(m.callback() !is null);

    import fl.box : Box;
    import fl.group : FlGroup;
    FlGroup.current(null);
    auto b = new Box(0, 0, 10, 10);
    m.doCallback(b);
    assert(calls == 1);
    assert(seen is b);
    FlGroup.current(null);
}

unittest
{
    // measure()/draw() with the default style, headless (no display,
    // same as every other module's draw() unittest -- confirms the
    // arithmetic/dispatch runs without crashing, not real pixels).
    MenuItem plain = MenuItem("Hello");
    int h;
    int w = plain.measure(h);
    assert(w > 0);
    assert(h > 0);
    plain.draw(0, 0, 100, h, MenuStyle.defaults(), 0);
    plain.draw(0, 0, 100, h, MenuStyle.defaults(), 1);

    MenuItem chk = MenuItem("Toggle me", 0, null, menuToggle | menuValue);
    int hc;
    int wc = chk.measure(hc);
    assert(wc > w); // checkbox adds width
    chk.draw(0, 0, 100, hc, MenuStyle.defaults(), 0);

    MenuItem radio = MenuItem("Radio me", 0, null, menuRadio | menuValue);
    int hr;
    radio.measure(hr);
    radio.draw(0, 0, 100, hr, MenuStyle.defaults(), 0);
}

unittest
{
    // image(): a real image widens measure()'s reported size (image is
    // above/below text by default, since no alignment is settable on a
    // MenuItem's own Label -- always the "above/below" branch), and
    // draw() doesn't crash with one set. Headless: RGBImage.draw()
    // itself early-returns with no display, same as every other
    // image-bearing draw() test in this port.
    import fl.image : RGBImage;

    MenuItem plain = MenuItem("Hi");
    int hPlain;
    int wPlain = plain.measure(hPlain);

    ubyte[] bits = [255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 0];
    auto img = new RGBImage(bits, 2, 2, 3);
    MenuItem withImage = MenuItem("Hi");
    withImage.image(img);
    assert(withImage.image() is img);

    int hImg;
    int wImg = withImage.measure(hImg);
    assert(wImg >= wPlain); // image() doesn't shrink the measured size
    withImage.draw(0, 0, 100, hImg, MenuStyle.defaults(), 0);
}

unittest
{
    // this(text, callback, flags): the no-shortcut convenience
    // overload -- confirms it forwards to the main constructor with
    // shortcut_ == 0 and doesn't disturb callback/flags.
    int fired = 0;
    auto item = MenuItem("Open", (Widget w) { fired++; }, menuDivider);
    assert(item.text == "Open");
    assert(item.shortcut_ == 0);
    assert(item.flags == menuDivider);
    item.callback()(null);
    assert(fired == 1);
}

unittest
{
    // validateMenuArray() (see the function's own doc comment) must
    // accept every correctly-terminated shape (empty, flat, with an embedded
    // submenu, with a *nested* submenu two levels deep) without
    // throwing, and must reject a missing trailing sentinel, whether
    // the array is entirely flat or the missing sentinel is the one
    // that would have closed an embedded submenu specifically.
    import std.exception : assertThrown, assertNotThrown;

    assertNotThrown(validateMenuArray([])); // empty: trivially fine

    assertNotThrown(validateMenuArray([
        MenuItem("one"), MenuItem("two"), MenuItem.init,
    ]));

    assertNotThrown(validateMenuArray([
        MenuItem("File", 0, null, menuSubmenu),
        MenuItem("Open"),
        MenuItem("Close"),
        MenuItem.init, // closes "File"'s embedded submenu
        MenuItem("Edit"),
        MenuItem.init, // closes the whole array
    ]));

    assertNotThrown(validateMenuArray([
        MenuItem("A", 0, null, menuSubmenu),
        MenuItem("B", 0, null, menuSubmenu), // nested submenu, 2 deep
        MenuItem("C"),
        MenuItem.init, // closes "B"
        MenuItem.init, // closes "A"
        MenuItem.init, // closes the whole array
    ]));

    // Missing sentinel: a flat array with nothing marking its end.
    assertThrown!Exception(validateMenuArray([
        MenuItem("one"), MenuItem("two"),
    ]));

    // Missing sentinel: the embedded submenu itself never closes, so
    // the walk would still be "inside" it when the array's physical
    // end is reached -- also must be rejected, not just the simpler
    // flat case.
    assertThrown!Exception(validateMenuArray([
        MenuItem("File", 0, null, menuSubmenu),
        MenuItem("Open"),
        MenuItem.init, // closes the whole array from nest==0's
                       // perspective, but "File"'s submenu (nest==1
                       // when this is reached) never got its own
                       // closing sentinel first
    ]));
}
