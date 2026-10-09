/*
 * Ported from FL/Fl_Menu_.H + src/Fl_Menu_.cxx (the non-add/insert
 * parts) + src/Fl_Menu_add.cxx (add()/insert()/remove()/replace()/
 * menu_end(), FLTK 1.5.0): the base class of every widget that owns a
 * menu (Fl_Menu_Bar/Fl_Menu_Button/Fl_Choice -- see
 * fl.menu_bar/fl.menu_button/fl.choice, all complete).
 *
 * The single biggest structural deviation from FLTK, and the
 * reason this port is *much* smaller than Fl_Menu_.cxx +
 * Fl_Menu_add.cxx combined: the menu array is a genuine D dynamic
 * array (`MenuItem[] menu_`), not a raw `Fl_Menu_Item*`. FLTK's
 * `alloc` flag (0 = caller-owned static array, 1 = privately
 * `new[]`-allocated, needs `delete[]`; 2 = also needs each item's
 * `text` `free()`d), `copy()`'s manual `new[]`/`memcpy()`, `clear()`'s
 * manual per-item `free()` loop, and the entire `local_array`/
 * `fl_menu_array_owner` process-wide singleton (a shared realloc-
 * doubling scratch buffer, so several unrelated widgets don't each
 * pay for their own growth strategy under manual memory management)
 * all exist purely to work around C++ needing to track *who owns this
 * memory and how to free it*. A GC-backed `MenuItem[]` has no such
 * question -- assigning, appending (`~=`), or slicing it is always
 * safe and always eventually collected, so none of that bookkeeping
 * exists here at all. `menu(MenuItem[])` just holds a reference to
 * whatever the caller passes (same as FLTK's `menu(m)` treating
 * `m` as caller-owned); `add()`/`insert()`/`remove()`/`replace()` just
 * mutate the array directly.
 *
 * Since `value_`/`prevValue_` are raw pointers *into* `menu_`, and a
 * `MenuItem[]` mutation can reallocate (invalidating old pointers),
 * every mutating method re-derives them from an index computed before
 * the mutation -- the same fixup dance FLTK's own `insert()` does
 * by hand (`value_offset`/`menu_+value_offset`), needed for the same
 * reason (a realloc can move the array), just via `std.array`
 * primitives instead of `new[]`/`memmove()`.
 *
 * Other deviations, all deliberate:
 *  - `add()`/`insert()`'s "split label at '/' into automatic
 *    submenus" convenience feature is ported (still genuinely useful,
 *    still the common way menus get built), but the legacy Forms-
 *    compatibility escape hatches around it are not: no leading `_`
 *    per-path-segment divider shorthand, no leading `/` "treat as a
 *    literal filename" escape. Notably, FLTK's own header comment
 *    calls the whole path-splitting feature "actually a totally
 *    unnecessary feature as you can now add submenu titles directly
 *    by setting FL_SUBMENU in the flags" -- so trimming its oldest,
 *    least-used corners is trimming legacy compatibility surface
 *    FLTK itself already considers optional, not core behavior.
 *  - `setonly(MenuItem*)`'s submenu-membership search
 *    (`first_submenu_item()`) only descends into embedded (`FL_SUBMENU`)
 *    submenus, not detached `FL_SUBMENU_POINTER` ones -- consistent
 *    with `fl.menu_item`'s own documented FL_SUBMENU_POINTER scope.
 *  - `find_item_with_user_data()`/`find_item_with_argument()` aren't
 *    ported: there is no `user_data()` at all in this port's callback
 *    design (see `fl.menu_item`'s doc comment), so there's nothing for
 *    them to search by.
 *  - **`global()` is real**: makes this menu's
 *    shortcuts work no matter what window has focus, via
 *    `fl.core.addHandler()` and `Fl::first_window()`/
 *    `first_window(Fl_Window*)` -- see `fl.core`'s own row.
 *  - **`item_pathname()`/`item_pathname_()` are ported**:
 *    `itemPathname()` builds the
 *    slash-separated pathname for an item pointer (or `mvalue()` if
 *    none given), the reverse of `findIndex(string)`/`findItem(string)`
 *    above -- and unlike those two, it does descend into detached
 *    `FL_SUBMENU_POINTER` submenus, matching FLTK's own wider
 *    traversal scope for this one function specifically. Same
 *    D-`string`-return substitution as `Widget.label()`/`tooltip()`
 *    elsewhere in this port: no caller buffer/length, so FLTK's
 *    `-2` "buffer too small" return code has nothing to report.
 *  - No `draw()`/`handle()` here, matching FLTK: `Fl_Menu_` defines
 *    neither (every concrete subclass supplies its own). `Menu_` is an
 *    `abstract class` here for exactly the reason FLTK's own
 *    `Fl_Menu_` can't be instantiated directly either, despite C++
 *    never spelling out "abstract" as its own keyword: `Fl_Widget::draw()`
 *    is `virtual void draw() = 0;` (a real pure virtual), and `Fl_Menu_`
 *    never overrides it -- so an "instantiate `Fl_Menu_` directly" test
 *    program wouldn't compile in real FLTK either.
 */
module fl.menu_;

import fl.widget : Widget, Callback;
import fl.image : Image;
import fl.multi_label : MultiLabel;
import fl.menu_item : MenuItem, MenuFlags, MenuStyle, menuSubmenu, menuRadio,
    menuToggle, menuValue, menuSubmenuPointer, menuDivider, validateMenuArray;
import fl.enumerations : Boxtype, Font, Fontsize, Color, When, CallbackReason,
    Event, whenReleaseAlways, whenChanged, whenRelease, whenNotChanged, Labeltype;
static import fl.enumerations;
static import fl.core;

abstract class Menu_ : Widget
{
    // Fl_Menu_::test_shortcut() (no-arg, returns a MenuItem pointer)
    // hides Fl_Widget::test_shortcut()'s two overloads (no-arg bool,
    // and the static label-matching one) in FLTK C++ too -- same
    // name-hiding rule there as in D, FLTK just never needed an
    // explicit `using Fl_Widget::test_shortcut;` to reach the hidden
    // ones. This alias is D's equivalent escape hatch, restoring
    // access to Widget's overloads under the same name.
    alias testShortcut = Widget.testShortcut;

    private MenuItem[] menu_;
    private const(MenuItem)* value_;
    private const(MenuItem)* prevValue_;

    protected Boxtype downBox_ = Boxtype.noBox;
    protected Boxtype menuBox_ = Boxtype.noBox;
    protected Font textfont_;
    protected Fontsize textsize_;
    protected Color textcolor_;

    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        setFlag(Flag.shortcutLabel);
        box(Boxtype.upBox);
        when(whenReleaseAlways);
        selectionColor(fl.enumerations.selectionColor);
        // Not field initializers: these mirror mutable module-level
        // globals (fl.enumerations.helvetica/normalSize/
        // foregroundColor) that aren't compile-time constants (same
        // issue documented in fl.menu_item's MenuStyle.defaults()).
        textfont_ = fl.enumerations.helvetica;
        textsize_ = fl.enumerations.normalSize;
        textcolor_ = fl.enumerations.foregroundColor;
    }

    // ---- array access ---------------------------------------------------

    /// Returns a pointer to the first item of the menu array, or null
    /// if empty -- same shape as FLTK's `menu()` (a raw pointer),
    /// since MenuItem's own `next()`/`size()`/etc. all operate on
    /// pointers, not slices.
    const(MenuItem)* menu() const { return menu_.length ? &menu_[0] : null; }

    /// Replaces the whole menu array (caller-owned, same as FLTK
    /// -- see the module doc comment for why there's no `alloc`/copy-
    /// on-write tracking needed here). Matches FLTK's own quirk of
    /// leaving value_ pointing at the *first* item, not null.
    ///
    /// **Validates the sentinel**: see `validateMenuArray()`'s own doc
    /// comment for the full story -- every menu array arrives here as a
    /// real, length-tracked `MenuItem[]` slice before `MenuItem.next()`/
    /// etc.'s own raw-pointer walk (needed to match FLTK's flat,
    /// embedded-submenu array format) ever gets a chance to read past
    /// a malformed one.
    void menu(MenuItem[] items)
    {
        validateMenuArray(items);
        menu_ = items;
        prevValue_ = null;
        value_ = menu_.length ? &menu_[0] : null;
    }

    /// Ported from `Fl_Menu_::copy(const Fl_Menu_Item*, void*)`: unlike
    /// `menu(MenuItem[])`, which just holds a reference to the caller's
    /// array, this gives the widget its own independent, mutable copy --
    /// needed whenever a caller's table might be shared across multiple
    /// widgets and one of them wants to mutate its own copy in place
    /// (flags, labels, ...) without corrupting the others (see
    /// `test/menubar.cxx`'s `DynamicChoice` for the canonical FLTK
    /// use case: it flips `menuInactive` on its own items in `handle()`).
    /// The `void* user_data` parameter FLTK also takes has no
    /// equivalent here (`MenuItem` has no user_data slot at all, see
    /// CONVENTIONS.md's callback-porting convention), so it's dropped rather
    /// than ported as a dead parameter.
    void copy(MenuItem[] items)
    {
        menu(items.dup);
    }

    /// This returns the number of MenuItems that make up the menu,
    /// correctly counting submenus, including the trailing sentinel.
    int size() const { return menu_.length ? menu_[0].size() : 0; }

    /// Same as menu(null): clears the menu array entirely.
    void clear()
    {
        menu_ = [];
        value_ = null;
        prevValue_ = null;
    }

    /**
     * Clears the submenu at `index` (which must be a submenu title) of
     * all its items, so it can be repopulated (e.g. a "Recent Files"
     * list). Ported from Fl_Menu_::clear_submenu(); returns 0 on
     * success, -1 if index is out of range or not a submenu.
     */
    int clearSubmenu(int index)
    {
        if (index < 0 || index >= size()) return -1;
        if (!(menu_[index].flags & menuSubmenu)) return -1;
        int i = index + 1;
        while (i < size() && menu_[i].text !is null)
            removeAt(i);
        return 0;
    }

    // ---- add / insert / remove / replace ---------------------------------

    private static string[] splitPath(string label)
    {
        import std.array : appender;

        string[] parts;
        auto buf = appender!string();
        size_t i = 0;
        while (i < label.length)
        {
            if (label[i] == '\\' && i + 1 < label.length)
            {
                buf.put(label[i + 1]);
                i += 2;
                continue;
            }
            if (label[i] == '/')
            {
                parts ~= buf.data;
                buf = appender!string();
                i++;
                continue;
            }
            buf.put(label[i]);
            i++;
        }
        parts ~= buf.data;
        return parts;
    }

    /// Ignores stray '&' characters on either side, matching
    /// FLTK's add()/insert() label-matching compare().
    private static bool labelsMatch(string a, string b)
    {
        size_t ai, bi;
        for (;;)
        {
            while (ai < a.length && a[ai] == '&') ai++;
            while (bi < b.length && b[bi] == '&') bi++;
            bool aEnd = ai >= a.length, bEnd = bi >= b.length;
            if (aEnd || bEnd) return aEnd == bEnd;
            if (a[ai] != b[bi]) return false;
            ai++;
            bi++;
        }
    }

    /// Index just past item i's own (sub)menu contents -- i.e. the
    /// next sibling at the same level -- reusing MenuItem.next()'s
    /// already-tested pointer walk rather than re-deriving it.
    private int siblingAfter(int i) const
    {
        return cast(int) (menu_[i].next() - &menu_[0]);
    }

    private void insertRaw(int at, MenuItem item)
    {
        import std.array : insertInPlace;

        ptrdiff_t voff = value_ ? value_ - &menu_[0] : -1;
        menu_.insertInPlace(at, item);
        value_ = (voff >= 0 && voff < menu_.length) ? &menu_[voff] : null;
    }

    private void removeAt(int i)
    {
        int next = siblingAfter(i);
        ptrdiff_t voff = value_ ? value_ - &menu_[0] : -1;
        menu_ = menu_[0 .. i] ~ menu_[next .. $];
        value_ = (voff >= 0 && voff < menu_.length) ? &menu_[voff] : null;
    }

    /**
     * Inserts a new item at `index` (-1 appends). If `label` contains
     * unescaped '/' characters, each component but the last names (or
     * creates) a submenu, and `index` is ignored -- the item's
     * position is determined by the path instead, matching FLTK.
     * Returns the index the item ended up at.
     */
    int insert(int index, string label, int shortcut, Callback cb, MenuFlags flags = 0)
    {
        // Seed a completely empty array with just a terminator first,
        // so the rest of this method can always assume a well-formed
        // array (one that already ends in a top-level-closing null) to
        // insert into or before -- rather than needing a separate
        // "the array doesn't exist yet" case. Without this, creating a
        // brand-new *submenu* as the very first item (e.g. the first
        // ever add("File/Open", ...) call) would leave the single null
        // inserted to close the submenu's own body doing double duty
        // as the top-level terminator too, which MenuItem.size()'s
        // walk doesn't actually accept -- it needs its own, separate
        // top-level-closing null (see next_visible_or_not()'s nest
        // counting: closing a nested level and closing the top level
        // are always two distinct null elements, never the same one).
        if (menu_.length == 0)
            menu_ = [MenuItem(null)];

        auto parts = splitPath(label);
        int pos = 0;
        foreach (part; parts[0 .. $ - 1])
        {
            int i = pos;
            while (i < size() && menu_[i].text !is null)
            {
                if ((menu_[i].flags & menuSubmenu) && labelsMatch(menu_[i].text, part))
                    break;
                i = siblingAfter(i);
            }
            if (i >= size() || menu_[i].text is null)
            {
                insertRaw(i, MenuItem(part, 0, null, menuSubmenu));
                insertRaw(i + 1, MenuItem(null));
            }
            pos = i + 1;
        }

        string leaf = parts[$ - 1];
        int i = pos;
        while (i < size() && menu_[i].text !is null)
        {
            if (!(menu_[i].flags & menuSubmenu) && labelsMatch(menu_[i].text, leaf))
                break;
            i = siblingAfter(i);
        }
        int at = (i < size() && menu_[i].text !is null) ? i
            : (parts.length > 1 || index < 0 || index > size()) ? i : index;

        auto item = MenuItem(leaf, shortcut, cb, flags);
        if (at < size() && menu_[at].text !is null
            && !(menu_[at].flags & menuSubmenu) && labelsMatch(menu_[at].text, leaf))
        {
            item.labeltype_ = menu_[at].labeltype_;
            item.labelfont_ = menu_[at].labelfont_;
            item.labelsize_ = menu_[at].labelsize_;
            item.labelcolor_ = menu_[at].labelcolor_;
            item.multi = menu_[at].multi;
            menu_[at] = item;
            return at;
        }

        insertRaw(at, item);
        if (flags & menuSubmenu)
            insertRaw(at + 1, MenuItem(null));
        return at;
    }

    /// Same as insert(-1, label, shortcut, cb, flags): appends.
    int add(string label, int shortcut, Callback cb, MenuFlags flags = 0)
    {
        return insert(-1, label, shortcut, cb, flags);
    }

    /// Changes item i's label. If i is out of range, does nothing.
    void replace(int i, string label)
    {
        if (i < 0 || i >= size()) return;
        menu_[i].text = label;
    }

    /// Deletes item i (and, if it's a submenu title, its whole body)
    /// from the menu.
    void remove(int i)
    {
        if (i < 0 || i >= size()) return;
        removeAt(i);
    }

    // ---- lookup -----------------------------------------------------------

    /// Converts an item pointer into its index in menu(), or -1 if it
    /// isn't in this menu (including items inside a detached
    /// FL_SUBMENU_POINTER submenu, matching FLTK).
    int findIndex(const(MenuItem)* item) const
    {
        if (menu_.length == 0) return -1;
        if (item < &menu_[0] || item >= &menu_[0] + menu_.length) return -1;
        return cast(int) (item - &menu_[0]);
    }

    /// Finds the first item with the given callback, traversing
    /// embedded submenus but not FL_SUBMENU_POINTER ones.
    int findIndex(Callback cb) const
    {
        foreach (i; 0 .. size())
            if (menu_[i].callback_ is cb) return i;
        return -1;
    }

    /// Finds the index of the item at the given "File/Open"-style
    /// pathname, traversing embedded submenus but not
    /// FL_SUBMENU_POINTER ones. Exact string match (including '&'),
    /// matching FLTK's find_index(const char*).
    int findIndex(string pathname) const
    {
        string path;
        for (int i = 0; i < size(); i++)
        {
            if (menu_[i].flags & menuSubmenu)
            {
                path = path.length ? path ~ "/" ~ menu_[i].text : menu_[i].text;
                if (path == pathname) return i;
            }
            else if (menu_[i].text is null)
            {
                auto slash = lastIndexOf(path, '/');
                path = slash >= 0 ? path[0 .. slash] : "";
            }
            else
            {
                string itemPath = path.length ? path ~ "/" ~ menu_[i].text : menu_[i].text;
                if (itemPath == pathname) return i;
            }
        }
        return -1;
    }

    const(MenuItem)* findItem(Callback cb) const
    {
        int i = findIndex(cb);
        return i == -1 ? null : &menu_[i];
    }

    const(MenuItem)* findItem(string pathname) const
    {
        int i = findIndex(pathname);
        return i == -1 ? null : &menu_[i];
    }

    /**
     * Ported from `item_pathname()`/`item_pathname_()`: builds the
     * slash-separated pathname ("File/&Open") for `finditem` (or
     * `mvalue()` if `null`), descending into both embedded
     * (`FL_SUBMENU`) and detached (`FL_SUBMENU_POINTER`) submenus --
     * a wider traversal than `findIndex(string)`/`findItem(string)`
     * above, which (matching FLTK's own `find_index()`) don't
     * follow `FL_SUBMENU_POINTER`. Returns `null` if `finditem` isn't
     * found anywhere in this menu (FLTK's `-1` case) -- same
     * D-`string`-return substitution CONVENTIONS.md documents for
     * `Widget.label()`/`tooltip()` elsewhere in this port: no
     * caller-supplied buffer/length, so there's no `-2` "buffer too
     * small" case to report either.
     */
    string itemPathname(const(MenuItem)* finditem = null) const
    {
        if (menu_.length == 0) return null;
        finditem = finditem ? finditem : value_;
        string path, result;
        return itemPathnameStep(&menu_[0], size(), finditem, path, result)
            ? result : null;
    }

    /// INTERNAL: recursive descent for itemPathname() above, ported
    /// from item_pathname_(). `path` is threaded through as the
    /// pathname built up so far; recursing into a FL_SUBMENU_POINTER
    /// array restores it on the way back out (matching FLTK's own
    /// `name[slen] = 0;` "continue from where we were" line).
    private static bool itemPathnameStep(const(MenuItem)* menu, int len,
        const(MenuItem)* finditem, ref string path, out string result)
    {
        int level = 0;
        for (int t = 0; t < len; t++)
        {
            const(MenuItem)* m = menu + t;
            if (m.submenu())
            {
                if (m.flags & menuSubmenuPointer)
                {
                    string saved = path;
                    if (m.text !is null)
                        path = path.length ? path ~ "/" ~ m.text : m.text;
                    if (m.submenuItems_ !is null && itemPathnameStep(
                            m.submenuItems_, m.submenuItems_.size(), finditem, path, result))
                        return true;
                    path = saved;
                }
                else
                {
                    level++;
                    if (m.text !is null)
                        path = path.length ? path ~ "/" ~ m.text : m.text;
                    if (m is finditem) { result = path; return true; }
                }
            }
            else if (m.text !is null)
            {
                if (m is finditem)
                {
                    result = path.length ? path ~ "/" ~ m.text : m.text;
                    return true;
                }
            }
            else
            {
                if (--level < 0) return false;
                auto slash = lastIndexOf(path, '/');
                path = slash >= 0 ? path[0 .. slash] : "";
            }
        }
        return false;
    }

    // ---- value / mvalue / picked ------------------------------------------

    const(MenuItem)* mvalue() const { return value_; }
    const(MenuItem)* prevMvalue() const { return prevValue_; }

    /// Index into menu() of the last item picked, or -1 (see
    /// mvalue()'s own doc comment for when: never picked yet, or the
    /// picked item lives in a detached FL_SUBMENU_POINTER submenu).
    int value() const
    {
        if (value_ is null) return -1;
        if (menu_.length > 0 && value_ >= &menu_[0] && value_ < &menu_[0] + menu_.length)
            return cast(int) (value_ - &menu_[0]);
        return -1;
    }

    /// Sets the picked item directly. Returns 1 if it changed, 0 if
    /// not (matching FLTK).
    int value(const(MenuItem)* m)
    {
        clearChanged();
        if (value_ !is m)
        {
            prevValue_ = value_;
            value_ = m;
            return 1;
        }
        return 0;
    }

    /// Sets the picked item by index into the main array (values
    /// outside 0..size()-1 are ignored, returning 0).
    int value(int i)
    {
        if (menu_.length == 0 || i < 0 || i >= size()) return 0;
        return value(&menu_[i]);
    }

    /// The label of the last item picked, or null.
    string text() const { return value_ ? value_.text : null; }

    /// The label of item i.
    string text(int i) const { return menu_[i].text; }

    // ---- style --------------------------------------------------------

    Font textfont() const { return textfont_; }
    void textfont(Font f) { textfont_ = f; }
    Fontsize textsize() const { return textsize_; }
    void textsize(Fontsize s) { textsize_ = s; }
    Color textcolor() const { return textcolor_; }
    void textcolor(Color c) { textcolor_ = c; }

    Boxtype downBox() const { return downBox_; }
    void downBox(Boxtype b) { downBox_ = b; }

    /// Box type for the menu popup windows; noBox means "use box()
    /// instead" (see fl.menu_bar/fl.menu_button/fl.choice, not yet
    /// ported, for where this gets consumed).
    Boxtype menuBox() const { return menuBox_; }
    void menuBox(Boxtype b) { menuBox_ = b; }

    Color downColor() const { return selectionColor(); }
    void downColor(Color c) { selectionColor(c); }

    /// Builds the MenuStyle fl.menu_popup's popup engine needs from
    /// this widget's own style fields -- see fl.menu_item's doc
    /// comment on why MenuStyle exists instead of passing `this`
    /// directly.
    MenuStyle style() const
    {
        MenuStyle s;
        s.textfont = textfont_;
        s.textsize = textsize_;
        s.textcolor = textcolor_;
        s.selectionColor = selectionColor();
        s.downBox = downBox_;
        s.windowColor = color();
        return s;
    }

    void shortcut(int i, int s) { menu_[i].shortcut(s); }
    void mode(int i, MenuFlags f) { menu_[i].flags = f; }
    int mode(int i) const { return menu_[i].flags; }

    /// Sets item i's plain `image()` field. **Not** what FLTK's own
    /// `fill_in_New_Menu()` uses for the New-widget-menu's icons (see
    /// `multiLabel()` just below for that, and its own doc comment for
    /// why) -- a plain image field falls back to `fl.widget.Label`'s
    /// default "image above text" stacking (matching FLTK's own
    /// `fl_normal_measure()`/`fl_normal_label()` exactly), which is
    /// almost never what a one-line menu item wants. Kept as a general,
    /// faithful counterpart to `shortcut(i, int)`/`mode(i, MenuFlags)`
    /// just above for any future caller that *does* want that
    /// (FLTK's own array-index field access has no equivalent
    /// restriction either, it's just rarely used this way in practice).
    void image(int i, Image img) { menu_[i].image(img); }

    /// Sets item i's label to a side-by-side icon+text `MultiLabel` --
    /// D counterpart of FLTK's `fill_in_New_Menu()`/
    /// `make_iconlabel()` (`fluid/nodes/factory.cxx`), which builds an
    /// `Fl_Multi_Label` (an image part plus a text part) and assigns it
    /// via `Fl_Multi_Label::label(mi)` rather than `mi->image(ic)` --
    /// deliberately, since `Fl_Multi_Label::draw()`/`measure()`
    /// (`fl.multi_label`) always lay their two parts out left-to-right,
    /// unlike a plain `image()` field's stacked default (see `image()`
    /// just above). This port builds its menus through `add()`, so
    /// callers need this instead of poking `menu_` directly (private,
    /// unlike FLTK's raw array).
    void multiLabel(int i, MultiLabel ml) { menu_[i].multiLabel(ml); }

    /// Searches this menu (only the embedded-submenu part of it, not
    /// any FL_SUBMENU_POINTER-detached array -- see the module doc
    /// comment) for the (sub)menu containing `item`, then turns it
    /// on, turning off adjacent radio items in the same group.
    void setonly(MenuItem* item)
    {
        if (menu_.length == 0) return;
        auto first = firstSubmenuItem(item, &menu_[0]);
        if (first is null) return;
        item.setonly(first);
    }

    private static const(MenuItem)* firstSubmenuItem(const(MenuItem)* item, const(MenuItem)* start)
    {
        auto m = start;
        int nest = 0;
        for (;;)
        {
            if (m.text is null)
            {
                if (nest == 0) return null;
                nest--;
            }
            else
            {
                if (m is item) return start;
                if (m.flags & menuSubmenu) nest++;
            }
            m++;
        }
    }

    /**
     * Call this when the user picks item v: applies radio/toggle
     * on/off bookkeeping, updates value()/mvalue(), and fires either
     * the item's own callback (if it has one) or this widget's
     * callback, depending on when(). Returns v. Ported from
     * Fl_Menu_::picked().
     */
    const(MenuItem)* picked(const(MenuItem)* v)
    {
        if (v !is null)
        {
            if (v.radio())
            {
                if (!v.value())
                {
                    setChanged();
                    setonly(cast(MenuItem*) v);
                }
                redraw();
            }
            else if (v.flags & menuToggle)
            {
                setChanged();
                (cast(MenuItem*) v).flags ^= menuValue;
                redraw();
            }
            else if (v !is value_)
            {
                setChanged();
            }
            prevValue_ = value_;
            value_ = v;
            if (when() & (whenChanged | whenRelease))
            {
                if (changed() || (when() & whenNotChanged))
                {
                    if (value_ !is null && value_.callback() !is null)
                        value_.doCallback(this, CallbackReason.selected);
                    else
                        doCallback(CallbackReason.selected);
                }
            }
        }
        return v;
    }

    /**
     * Returns the menu item matching the current event's shortcut
     * (must be called in response to FL_KEYBOARD/FL_SHORTCUT), running
     * it through picked() first (so the match's callback -- or this
     * widget's own -- already fired by the time this returns).
     */
    const(MenuItem)* testShortcut()
    {
        if (menu_.length == 0) return null;
        return picked(menu_[0].testShortcut());
    }

    /**
     * Makes the shortcuts for this menu work no matter what window has
     * focus, by installing a global `fl.core.addHandler()` fallback.
     * This widget doesn't have to be visible (its window can be
     * hidden, or it doesn't need to be in a window at all). Currently
     * there can be only one `global()` menu -- setting a new one
     * replaces the old one, and there's no way to un-`global()` one
     * (matching FLTK's own documented limitation exactly). Ported
     * from `Fl_Menu_::global()` (`src/Fl_Menu_global.cxx`), backed by
     * `fl.core.addHandler()`'s global-handler chain and
     * `Fl::first_window()`/`first_window(Fl_Window*)` (see `fl.core`'s
     * own row).
     */
    void global()
    {
        if (theGlobalWidget_ is null) fl.core.addHandler((Event e) => globalHandler_(e));
        theGlobalWidget_ = this;
    }
}

// Fl_Menu_::the_widget/handler() (src/Fl_Menu_global.cxx) -- genuinely
// process-wide state FLTK too (a plain file-scope static, not a
// per-instance field), same treatment already established for
// fl.slider's offcenter/fl.roller's ipos.
private Menu_ theGlobalWidget_;

private int globalHandler_(Event e)
{
    if (e != Event.shortcut || fl.core.modal() !is null) return 0;
    fl.core.firstWindow(theGlobalWidget_.window());
    return theGlobalWidget_.handle(e);
}

private ptrdiff_t lastIndexOf(string s, char c)
{
    for (ptrdiff_t i = cast(ptrdiff_t) s.length - 1; i >= 0; i--)
        if (s[i] == c) return i;
    return -1;
}

version (unittest)
{
    /// Menu_ is abstract (see the module doc comment); these tests
    /// only exercise the array/lookup/picked() logic, not drawing, so
    /// a no-op draw() is enough.
    private class TestMenu : Menu_
    {
        this(int x, int y, int w, int h) { super(x, y, w, h); }
        override void draw() {}
    }
}

unittest
{
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto m = new TestMenu(0, 0, 100, 20);
    assert(m.size() == 0);
    assert(m.menu() is null);

    int fileOpenCalls, fileSaveCalls, editCopyCalls;
    m.add("File/Open", 0, (Widget w) { fileOpenCalls++; });
    m.add("File/Save", 0, (Widget w) { fileSaveCalls++; });
    m.add("Edit/Copy", 0, (Widget w) { editCopyCalls++; });

    assert(m.findIndex("File/Open") >= 0);
    assert(m.findIndex("File/Save") >= 0);
    assert(m.findIndex("Edit/Copy") >= 0);
    assert(m.findIndex("File/Nonexistent") == -1);

    auto openIdx = m.findIndex("File/Open");
    m.picked(&m.menu()[openIdx]);
    assert(fileOpenCalls == 1);
    assert(m.text() == "Open");
    assert(m.value() == openIdx);

    // itemPathname(): explicit item pointer, and defaulting to mvalue()
    // (the just-picked "File/Open" item above) when finditem is null.
    assert(m.itemPathname(&m.menu()[openIdx]) == "File/Open");
    auto copyIdx = m.findIndex("Edit/Copy");
    assert(m.itemPathname(&m.menu()[copyIdx]) == "Edit/Copy");
    assert(m.itemPathname() == "File/Open");

    // Not found anywhere in this menu.
    MenuItem stray = MenuItem("stray");
    assert(m.itemPathname(&stray) is null);

    FlGroup.current(null);
}

unittest
{
    // itemPathname() descends into a detached FL_SUBMENU_POINTER
    // submenu too, unlike findIndex(string)/findItem(string) above
    // (see those functions' own doc comments on the scope
    // difference -- matching FLTK's item_pathname_() vs.
    // find_index() exactly).
    import fl.group : FlGroup;
    FlGroup.current(null);

    static MenuItem[] detached = [
        MenuItem("Copy"),
        MenuItem("Paste"),
        MenuItem.init,
    ];

    auto m = new TestMenu(0, 0, 100, 20);
    MenuItem[] items = [
        MenuItem("Edit", 0, null, menuSubmenuPointer),
        MenuItem.init,
    ];
    items[0].submenuItems_ = &detached[0];
    m.menu(items);

    assert(m.itemPathname(&detached[0]) == "Edit/Copy");
    assert(m.itemPathname(&detached[1]) == "Edit/Paste");

    FlGroup.current(null);
}

unittest
{
    // Radio group: picked() turns adjacent radios off via setonly().
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto m = new TestMenu(0, 0, 100, 20);
    m.add("R1", 0, null, menuRadio | menuValue);
    m.add("R2", 0, null, menuRadio);
    m.add("R3", 0, null, menuRadio);

    auto r2 = &m.menu()[1];
    m.picked(r2);
    assert(m.menu()[0].value() == 0);
    assert(m.menu()[1].value() == 1);
    assert(m.menu()[2].value() == 0);

    FlGroup.current(null);
}

unittest
{
    // remove() deletes a whole submenu body, not just its title.
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto m = new TestMenu(0, 0, 100, 20);
    m.add("File/Open", 0, null);
    m.add("File/Save", 0, null);
    m.add("Edit/Copy", 0, null);

    int fileIdx = m.findIndex("File");
    assert(fileIdx >= 0);
    m.remove(fileIdx);
    assert(m.findIndex("File/Open") == -1);
    assert(m.findIndex("File/Save") == -1);
    assert(m.findIndex("Edit/Copy") >= 0);

    FlGroup.current(null);
}

unittest
{
    // clear()/replace()/value(int) round-trip.
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto m = new TestMenu(0, 0, 100, 20);
    m.add("one", 0, null);
    m.add("two", 0, null);
    assert(m.size() == 3); // 2 items + sentinel

    m.replace(0, "renamed");
    assert(m.text(0) == "renamed");

    assert(m.value(1) == 1);
    assert(m.value() == 1);
    assert(m.mvalue() is &m.menu()[1]);

    m.clear();
    assert(m.size() == 0);
    assert(m.mvalue() is null);

    FlGroup.current(null);
}

unittest
{
    // global(): installs a handler that reaches this menu's own
    // handle() on Event.shortcut, unless modal() is active -- ported
    // from Fl_Menu_::global()/its file-static handler().
    import fl.group : FlGroup;
    FlGroup.current(null);
    fl.core.resetForTest();

    int handleCalls;
    class GlobalTestMenu : Menu_
    {
        this() { super(0, 0, 100, 20); }
        override void draw() {}
        override int handle(Event e) { handleCalls++; return 1; }
    }
    auto m = new GlobalTestMenu();
    m.global();
    assert(theGlobalWidget_ is m);

    // Wrong event type: not dispatched at all.
    assert(globalHandler_(Event.push) == 0);
    assert(handleCalls == 0);

    // Right event type, no modal(): dispatched.
    assert(globalHandler_(Event.shortcut) == 1);
    assert(handleCalls == 1);

    // modal() active: not dispatched, even for Event.shortcut --
    // matches FLTK's own "if (... || Fl::modal()) return 0;" guard.
    static class W2 : Widget
    {
        this() { super(0, 0, 10, 10); }
        override void draw() {}
    }
    auto modalW = new W2();
    fl.core.modal(modalW);
    assert(globalHandler_(Event.shortcut) == 0);
    assert(handleCalls == 1); // unchanged

    fl.core.modal(null);
    theGlobalWidget_ = null; // this module's own genuinely-shared state, not reset by fl.core.resetForTest()
    fl.core.resetForTest();
    FlGroup.current(null);
}

unittest
{
    // Regression test: calling
    // multiLabel() on an item, then add()ing more siblings into the
    // *same* submenu afterward (exactly `fluid.gui_main`'s own `&New`
    // menu construction order -- add a leaf, immediately set its icon
    // via multiLabel(), move on to the next leaf), used to corrupt the
    // whole submenu. Root cause: `MenuItem.multiLabel()` used to null
    // out `text`, but `text is null` is this array's own sentinel/
    // end-of-(sub)menu marker (`MenuItem.nextVisibleOrNot()`) --
    // nulling a live item's text made every later sibling-scanning
    // search (this test's second/third add() calls) mistake it for the
    // submenu's real closing sentinel, silently misplacing/losing
    // later siblings. Fixed by leaving `text` alone in multiLabel() --
    // see that function's own doc comment.
    import fl.group : FlGroup;
    import fl.multi_label : MultiLabel;
    FlGroup.current(null);

    auto m = new TestMenu(0, 0, 100, 20);
    int aIdx = m.add("New/Alpha", 0, null);
    auto ml = new MultiLabel();
    ml.textB = "Alpha";
    m.multiLabel(aIdx, ml);
    int bIdx = m.add("New/Beta", 0, null);
    int cIdx = m.add("New/Gamma", 0, null);

    assert(m.findIndex("New/Alpha") == aIdx);
    assert(m.findIndex("New/Beta") == bIdx);
    assert(m.findIndex("New/Gamma") == cIdx);
    assert(m.itemPathname(&m.menu()[bIdx]) == "New/Beta");
    assert(m.itemPathname(&m.menu()[cIdx]) == "New/Gamma");

    // The multiLabel item itself is still a real, findable, non-null-
    // text array element -- not mistaken for a sentinel.
    assert(m.menu()[aIdx].text !is null);
    assert(m.menu()[aIdx].labeltype() == Labeltype.multiLabel);

    FlGroup.current(null);
}

unittest
{
    // Diagnostic for a user report ("no separator above Quit"):
    // exercises the exact remove-then-readd cycle `fluid.gui_main`'s
    // `rebuildRecentFilesMenu()` runs (remove &Quit, [add/remove recent
    // files], re-add &Quit), on top of a static item that already
    // carries `menuDivider` (the &File menu's own `&Write Strings`).
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto m = new TestMenu(0, 0, 100, 20);
    m.add("File/New", 0, null);
    int wsIdx = m.add("File/WriteStrings", 0, null, menuDivider);
    m.add("File/Quit", 0, null);

    assert(m.mode(wsIdx) & menuDivider);
    int quitIdx = m.findIndex("File/Quit");
    assert(quitIdx == wsIdx + 1);

    // Simulate rebuildRecentFilesMenu() with zero recent files: remove
    // Quit, (no recent-file paths to remove/re-add here), re-add Quit.
    m.remove(quitIdx);
    m.add("File/Quit", 0, null);

    int wsIdx2 = m.findIndex("File/WriteStrings");
    int quitIdx2 = m.findIndex("File/Quit");
    assert(wsIdx2 == wsIdx); // unchanged position
    assert(m.mode(wsIdx2) & menuDivider); // divider survives the cycle
    assert(quitIdx2 == wsIdx2 + 1); // Quit still directly follows it

    FlGroup.current(null);
}
