/*
 * Simplified equivalent of the popup-window engine backing
 * Fl_Menu_Item::popup()/pulldown() (the file-static Menu_State/
 * Menu_Window/Menu_Title_Window machinery in src/Fl_Menu.cxx). This is
 * the scope the user explicitly agreed to for the whole Menu family
 * (see PORTING.md's Menus rows): a real, usable cascading popup menu,
 * but built on much less platform machinery than FLTK's version,
 * with every simplification documented here rather than silently
 * approximated.
 *
 * Deliberate simplifications, all documented:
 *
 *  - Title windows are real (`MenuTitleWindow`, see that class's own
 *    doc comment). What's genuinely unported is only the
 *    *torn-off/draggable* variant (`Menu_Title_Window`'s
 *    `in_menubar=true` constructor mode, used internally by
 *    `Fl_Menu_Bar` to simulate a "pressed" top-level button) --
 *    `fl.menu_bar.MenuBar` already covers that same visual effect its
 *    own way (`currentPulldownTarget_`), so nothing in this port calls
 *    `pulldown()`'s `title` parameter with that mode. Every cascade
 *    level (including the title window) is a plain content window
 *    (fl.menu_window.MenuWindow), borderless via
 *    fl.window.Window.clearBorder() + the `_MOTIF_WM_HINTS` mechanism
 *    (see PORTING.md's fl.window/fl.platform_x11 rows).
 *  - `fl.core.grab()` establishes a real `XGrabPointer()`/
 *    `XGrabKeyboard()`, both with `owner_events=True` (see that
 *    function's own doc comment). A click genuinely outside this
 *    app entirely (another application, the desktop) is redirected by
 *    X itself to whichever level currently holds the grab, and is
 *    detected and cancels the menu via a real geometric check
 *    (`PopupEngine.isInsideAnyLevel()`, called from
 *    `MenuLevelWindow.handle()`'s `Event.push`/`release` cases) --
 *    matching FLTK's own `Menu_State::is_inside()`. A click on a
 *    *different* same-app widget (e.g. clicking a `Fl_Menu_Button`
 *    again while its own dropdown is open) is delivered to that widget
 *    normally (`owner_events=True` means same-app windows aren't
 *    intercepted), which is what `forceClose()` handles -- see its own
 *    doc comment for exactly how that reentrant case unwinds.
 *  - Autoscroll (`PopupEngine.autoscroll()`, ported from
 *    `Menu_Window::autoscroll()`) is real for both keyboard and mouse.
 *    A menu taller than the screen genuinely still *is* taller than the
 *    screen (no content re-layout/truncation), but `onKey()`'s Up/Down
 *    and `onHover()`'s mouse movement both reposition the window
 *    vertically as the highlighted item moves, keeping that item's row
 *    inside the visible screen strip -- matching FLTK exactly.
 *    Multi-monitor-aware initial positioning
 *    (`Fl::screen_xywh(screen_num)`) is real too -- each cascade level
 *    clamps against the actual bounding box of whichever monitor its
 *    anchor point sits on, via `fl.core.screenXYWH()`, instead of the
 *    whole X display's combined size.
 *  - Every `pulldown()`/`popup()` caller (`fl.choice.Choice`/
 *    `fl.input_choice.InputChoice`/`fl.menu_button.MenuButton`/
 *    `fl.menu_bar.MenuBar.doPulldown()`) wraps its call in a
 *    `fl.widget_tracker.WidgetTracker` and checks `.deleted()` before
 *    touching itself again afterward -- an `Fl_Widget_Tracker`-style
 *    "menu owner deleted mid-loop" guard (STR #3503).
 *  - Both of FLTK's gestures work via the same handling: hovering
 *    (move/drag) opens/closes submenus and updates the highlighted
 *    item; a leaf item is picked on *release* over it. This naturally
 *    covers both "press, drag through the menu, release on the item"
 *    and "click to open elsewhere, click the item" (the second click's
 *    press already re-highlights before its own release picks it) --
 *    the same shape FLTK's own dual gesture support has, though
 *    reached by simpler means (one release rule, not FLTK's
 *    separate `State::PUSHED`/`MENU_PUSHED` tracking). This depends on
 *    `fl.core.handle()`'s `Event.move`/`drag`/`release` cases
 *    re-checking `grab()` the way `Event.push` does, so a drag/release
 *    that started *before* a grab was established (i.e. the very press
 *    that opens the menu) still routes to the now-open popup rather
 *    than the original pre-grab widget -- see that function's own doc
 *    comment. Keyboard is Up/Down/Backspace/Tab
 *    (move within the deepest open level, wrapping, skipping non-
 *    selectable items -- Backspace and unshifted Tab are Down,
 *    Shift+Tab is Up, matching `Menu_State::handle_keyboard_event()`'s
 *    own aliases), Right (open the highlighted item's submenu), Left
 *    (close the deepest level, back to its parent), Enter (pick a
 *    leaf/open a submenu -- or pick, not open, a submenu item that has
 *    its own callback set, matching FLTK's exact
 *    `!current_item->callback_` condition), Escape (cancel everything),
 *    and any other key tries a mnemonic-`&`/explicit-shortcut match
 *    against every open level's own top-level items, deepest first
 *    (`PopupEngine.onKey()`'s tail, ported from `Menu_State::
 *    handle_shortcut()`).
 *  - No shortcut-key underline rendering in the drawn labels -- a pre-
 *    existing, already-documented gap in fl.draw's text primitives,
 *    not something new here (see fl.menu_item's measure()/draw() doc
 *    comments).
 */
module fl.menu_popup;

import fl.core;
import fl.menu_item;
import fl.menu_window : MenuWindow;
import fl.widget : Widget;
import fl.group : FlGroup;
import fl.rect : Rect;
import fl.enumerations : Event, Boxtype, Color, Font, Fontsize, ArrowType,
    Orientation, escape, up, down, left, right, enter,
    kpEnter, alignLeft, alignRight, backSpace, tab, stateShift;
import fldraw = fl.draw;
static import fl.core;

private final class MenuLevelWindow : MenuWindow
{
    PopupEngine engine;
    const(MenuItem)*[] items;  // this level's visible, top-of-array items (submenus not expanded)
    MenuStyle style;
    int highlighted = -1;      // index into items, -1 = none

    /// Shortcut-text column widths for this level -- the D equivalent
    /// of `Menu_Window::shortcuts_w`/`modifiers_w` (`calc_size()`,
    /// `Fl_Menu.cxx`): `modifiersW` is the widest "Ctrl+Alt+" (right-
    /// justified) prefix among this level's items, `shortcutsW` the
    /// widest key name (left-justified) among them, both 0 if no item
    /// has a shortcut. Computed here, at construction, so both the
    /// caller's content-width sizing (`run()`/`openSubmenu()`) and
    /// `drawShortcut()` agree on the same measurement.
    int shortcutsW = 0;
    int modifiersW = 0;

    /// Which monitor this level opened on, captured once at
    /// construction (its initial `(x, y)`) -- matches FLTK's own
    /// `screen_num()` (`Fl_Window`'s stored field, set once and never
    /// re-derived from the window's current position). `autoscroll()`
    /// uses this instead of recomputing "which monitor is this window
    /// on" fresh from its *current* position on every call: on a
    /// multi-monitor (Xinerama) setup, as a tall menu scrolls upward in
    /// response to repeated Down presses, its top-left corner can drift
    /// across a monitor boundary, and recomputing the anchor monitor
    /// from that drifted position mid-scroll would make `screenXYWH()`
    /// suddenly report a *different* monitor's bounds -- the delta math
    /// is only valid relative to one stable, unchanging monitor rect, so
    /// re-deriving it would make the window "bounce to a different
    /// monitor" instead of scrolling smoothly by one row per keypress.
    private int homeScreen_;

    this(PopupEngine engine, const(MenuItem)* first, MenuStyle style,
        int x, int y, int w, int h)
    {
        super(x, y, w, h);
        this.engine = engine;
        this.style = style;
        this.homeScreen_ = fl.core.screenNum(x, y);
        clearBorder();
        setFlag(Widget.Flag.menuWindow);
        box(Boxtype.upBox);
        color(style.windowColor);

        for (auto p = first; p !is null && p.text !is null; p = p.next())
            items ~= p;

        foreach (it; items)
        {
            if (it.shortcut() == 0) continue;
            Font font = (it.labelsize() || it.labelfont()) ? it.labelfont() : style.textfont;
            Fontsize size = it.labelsize() ? it.labelsize() : style.textsize;
            fldraw.fl_font(font, size);
            string keyPart;
            string full = fl.core.flShortcutLabel(cast(uint) it.shortcut(), keyPart);
            string modifiers = full[0 .. $ - keyPart.length];
            // Same "<=4 chars -> two right/left-justified columns,
            // otherwise right-justify the whole label" split FLTK
            // makes via fl_utf_nb_char(); approximated here as a byte
            // count rather than a real UTF-8 character count, since
            // every key name this port's platformKeyName()/uppercased-
            // character fallback can produce is ASCII (see fl.core's
            // flShortcutLabel doc comment).
            if (keyPart.length <= 4)
            {
                int mw = cast(int) fldraw.width(modifiers);
                if (mw > modifiersW) modifiersW = mw;
                int kw = cast(int) fldraw.width(keyPart) + 4;
                if (kw > shortcutsW) shortcutsW = kw;
            }
            else
            {
                int fw = cast(int) fldraw.width(full) + 4;
                if (fw > modifiersW + shortcutsW) modifiersW = fw - shortcutsW;
            }
        }
    }

    /// This formula and `fl.core.menuLinespacing()`'s default (4) both
    /// match `Fl_Menu.cxx`/`Fl.cxx` exactly. If dropdown rows
    /// look shorter than a reference build's, the gap is almost
    /// certainly `it.measure()`'s own text-height result (`fl.xft`'s
    /// simple Xft metrics vs a Cairo+Pango reference build's more
    /// generous line metrics), not this function -- the same
    /// documented, deliberately-not-chased rendering gap CLAUDE.md's
    /// build-config note already covers for antialiasing/text shaping.
    /// `menuLinespacing`'s default is left alone rather than
    /// compensating for that gap with an unrelated knob; revisit once
    /// `fl.xft` is replaced with Pango (already the agreed future
    /// direction, see CLAUDE.md's "Where this port intentionally
    /// exceeds FLTK").
    int rowHeight() const
    {
        int maxH = 0;
        foreach (it; items)
        {
            int hh;
            it.measure(hh, style);
            hh += fl.core.menuLinespacing();
            if (hh > maxH) maxH = hh;
        }
        return maxH > 0 ? maxH : (style.textsize + 6);
    }

    int itemAt(int mx, int my) const
    {
        if (mx < 0 || mx >= w() || my < 0 || my >= h()) return -1;
        int rh = rowHeight();
        if (rh <= 0 || items.length == 0) return -1;
        int idx = my / rh;
        if (idx < 0 || idx >= cast(int) items.length) return -1;
        if (!items[idx].selectable()) return -1;
        return idx;
    }

    override void draw()
    {
        super.draw();
        int rh = rowHeight();
        foreach (i, it; items)
        {
            int mode = (cast(int) i == highlighted) ? 1 : 0;
            it.draw(1, cast(int) i * rh, w() - 2, rh, style, mode);
            // Additional decorations to the right of the label, matching
            // FLTK's draw_entry() (Fl_Menu.cxx): a submenu gets a
            // cascade arrow, otherwise a shortcut (if any) gets its
            // human-readable key combo drawn. MenuItem.draw() above
            // deliberately doesn't draw either -- see its own doc
            // comment -- FLTK leaves both to the popup engine too.
            if (it.submenu())
                drawSubmenuArrow(1, cast(int) i * rh, w() - 2, rh);
            else if (it.shortcut() != 0)
                drawShortcut(it, 1, cast(int) i * rh, w() - 2, rh);
            if (it.flags & menuDivider)
                fldraw.fl_xyline(1, (cast(int) i + 1) * rh - 1, w() - 2);
        }
    }

    /// Ported from `Menu_Window::draw_submenu_arrow()` (`Fl_Menu.cxx`).
    private void drawSubmenuArrow(int x, int y, int w, int h) const
    {
        int sz = ((h - 2) & (-2)) + 1; // must be odd for better centering
        if (sz > 13) sz = 13;          // limit arrow size
        int x1 = x + w - sz - 2;
        int y1 = y + (h - sz) / 2 + 1;
        fldraw.drawArrow(Rect(x1, y1, sz, sz), ArrowType.arrowSingle,
            Orientation.orientRight, fldraw.fl_color());
    }

    /// Ported from `Menu_Window::draw_shortcut()` (`Fl_Menu.cxx`): draws
    /// `m`'s shortcut key combination text right-aligned within
    /// (x,y,w,h) -- a right-justified modifier column ("Ctrl+") followed
    /// by a left-justified key column ("C"), sized from `shortcutsW`/
    /// `modifiersW` above so every item in this level lines its key
    /// names up in the same column, exactly like FLTK.
    private void drawShortcut(const(MenuItem)* m, int x, int y, int w, int h) const
    {
        Font font = (m.labelsize() || m.labelfont()) ? m.labelfont() : style.textfont;
        Fontsize size = m.labelsize() ? m.labelsize() : style.textsize;
        fldraw.fl_font(font, size);
        string keyPart;
        string full = fl.core.flShortcutLabel(cast(uint) m.shortcut(), keyPart);
        string modifiers = full[0 .. $ - keyPart.length];
        if (keyPart.length <= 4)
        {
            fldraw.fl_draw(modifiers, x, y, w - shortcutsW, h, alignRight);
            fldraw.fl_draw(keyPart, x + w - shortcutsW, y, shortcutsW, h, alignLeft);
        }
        else
        {
            fldraw.fl_draw(full, x, y, w - 4, h, alignRight);
        }
    }

    override int handle(Event e)
    {
        // Every mouse case below resolves its *real* target level from
        // the event's root coordinates (`engine.levelAtRoot()`) instead
        // of assuming it's `this` -- `this` is always whichever level
        // currently holds `fl.core.grab()` (the deepest one, see
        // `regrab()`), since that's the sole dispatch target for every
        // mouse event while grabbed, regardless of which real level
        // window the pointer is actually over. See `levelAtRoot()`'s
        // own doc comment for the full story (a real, user-reported
        // navigation bug: hovering back onto an already-open parent
        // level, or re-entering any level after the pointer left the
        // app's own windows, silently did nothing).
        switch (e)
        {
        case Event.push:
        {
            int rx = fl.core.eventXRoot(), ry = fl.core.eventYRoot();
            auto target = engine.levelAtRoot(rx, ry);
            // A click that lands outside every one of the engine's own
            // open level windows cancels the whole menu, matching
            // FLTK's own Menu_State::handle_mouse_events() FL_PUSH
            // case ("Clicking or dragging outside menu cancels it...") --
            // unless `outsideMouseHandler` claims it first (see that
            // field's own doc comment: e.g. a click on a *different*
            // MenuBar top-level item switches to it directly instead of
            // just closing this one).
            if (target is null)
            {
                if (engine.outsideMouseHandler !is null && engine.outsideMouseHandler(rx, ry))
                    return 1;
                engine.cancel();
                return 1;
            }
            engine.onPress(target, target.itemAt(rx - target.x(), ry - target.y()));
            return 1;
        }
        case Event.release:
        {
            // Matching FLTK, `Menu_State::handle_mouse_events()`'s
            // `is_inside()` cancellation is scoped to its `FL_MOVE`/
            // `FL_ENTER`/`FL_PUSH`/`FL_DRAG` case *only* -- `FL_RELEASE`
            // is a wholly separate `case`, gated on
            // `Fl::event_is_click()` (was this press-release pair
            // fast/stationary enough to count as a "click," FLTK's
            // own click-vs-drag heuristic), not position. The opening
            // click's own matching release always lands outside every
            // level (it's physically over the trigger widget, e.g. the
            // `MenuButton`, not over the dropdown that only just
            // appeared below it) -- treating that as a cancel would
            // close a single, quick "open the menu" click on effectively
            // every open, instead of leaving it open the way FLTK's
            // own "mode 1" does.
            //
            // `fl.core.eventIsClick()` is the `event_is_click()`
            // equivalent `onRelease()` (below) calls. Beyond that,
            // FLTK's `FL_RELEASE` case never re-derives *anything*
            // from the release's own position -- it acts purely on
            // `current_item`/`current_menu_ix`, whatever the last
            // `FL_MOVE`/`FL_DRAG` left them as, so a drag that leaves the
            // menu bounds and releases *outside* still finalizes on the
            // last item that WAS highlighted (`event_is_click()` being
            // false, from the drag). This engine's own equivalent of
            // `current_item` is the *deepest* open level's own
            // `highlighted` index (matching `current_menu_ix` always
            // being the deepest active menu FLTK too) -- read it
            // here instead of hardcoding `idx = -1` on every outside
            // release, so the same drag-out-then-release gesture
            // finalizes a pick instead of silently leaving the menu open
            // with nothing selected.
            int rx = fl.core.eventXRoot(), ry = fl.core.eventYRoot();
            auto target = engine.levelAtRoot(rx, ry);
            if (target is null)
            {
                auto deepest = engine.levels.length ? engine.levels[$ - 1] : null;
                if (deepest !is null && deepest.highlighted >= 0)
                    engine.onRelease(deepest, deepest.highlighted);
                else
                    engine.onRelease(this, -1);
                return 1;
            }
            engine.onRelease(target, target.itemAt(rx - target.x(), ry - target.y()));
            return 1;
        }
        case Event.move:
        case Event.drag:
        {
            int rx = fl.core.eventXRoot(), ry = fl.core.eventYRoot();
            auto target = engine.levelAtRoot(rx, ry);
            if (target !is null)
                engine.onHover(target, target.itemAt(rx - target.x(), ry - target.y()));
            // Outside every level -- e.g. hovering back over the
            // MenuBar's own top-level row, or an excursion off toward
            // the desktop -- gets one chance via `outsideMouseHandler`
            // (see its own doc comment) before falling back to leaving
            // the current selection exactly as-is, same as hovering a
            // level's own padding/divider does (onHover()'s idx<0
            // guard).
            else if (engine.outsideMouseHandler !is null)
                engine.outsideMouseHandler(rx, ry);
            return 1;
        }
        case Event.keyDown:
        case Event.shortcut:
            return engine.onKey() ? 1 : 0;
        default:
            return 0;
        }
    }
}

/**
 * The small window shown above a popup's main dropdown when a `title`
 * is given -- ported from `Menu_Title_Window` (`Fl_Menu.cxx`).
 * `Fl_Menu_Button::popup()` passes its
 * own `label()` as `Fl_Menu_Item::popup()`'s `title` argument whenever
 * the button has no visible box (`!box() || type()`, e.g. a
 * `type(POPUP3)` full-window right-click catcher) -- `test/menubar.cxx`'s
 * own `"&popup"`-labelled full-window button is exactly this case, and
 * this is what makes that label appear above the right-click menu.
 * Only the plain (non-menubar) title case is
 * ported -- `Menu_Title_Window`'s other constructor mode
 * (`in_menubar=true`) exists FLTK purely to simulate a "pressed"
 * menubar button while its own dropdown is open, a different feature
 * `fl.menu_bar.MenuBar` already covers itself (`currentPulldownTarget_`,
 * see that module's own doc comment) -- `fl.menu_bar` never passes a
 * `title` through `pulldown()` at all, so that branch has no caller
 * here to support.
 */
private final class MenuTitleWindow : MenuWindow
{
    MenuItem titleItem;
    MenuStyle style;

    this(MenuItem item, MenuStyle style, int x, int y, int w, int h)
    {
        super(x, y, w, h);
        this.titleItem = item;
        this.style = style;
        clearBorder();
        setFlag(Widget.Flag.menuWindow);
        box(Boxtype.upBox);
        color(style.windowColor);
    }

    override void draw()
    {
        super.draw();
        // drawMode 2 = "menu title" -- matches Menu_Title_Window::draw()
        // (`menu->draw(0, 0, w(), h(), button, 2)`): a down_box()/
        // selectionColor()-based background instead of the plain item
        // background/highlight the same MenuItem.draw() gives a regular
        // row (see that function's own drawMode==2 branch).
        titleItem.draw(0, 0, w(), h(), style, 2);
    }
}

/// The PopupEngine for whichever cascading menu is currently the
/// active, outermost one (module-level, not per-instance, so a
/// reentrant pulldown()/popup() call -- see run()'s own doc comment on
/// exactly when that happens -- can find and forcibly close it).
/// Single-threaded, matching every other bit of shared process state
/// in this port (fl.core's event globals, etc.).
private PopupEngine activeEngine_;

private final class PopupEngine
{
    MenuLevelWindow[] levels;
    MenuStyle style;
    const(MenuItem)* picked;
    bool done;

    /// The optional title window shown above the main dropdown for
    /// this run -- see `MenuTitleWindow`'s own doc comment. Null when
    /// `run()` wasn't given a `title`.
    MenuTitleWindow titleWin;

    /// Set (once `run()` starts, latched -- never cleared back to
    /// `false` again during the same run) the first time
    /// `MenuLevelWindow.handle()` sees a real `Event.push` -- i.e. a
    /// *second*, later press landing on one of this engine's own levels
    /// while the menu is already open, as opposed to the original press
    /// that opened it (that one is handled by the menu-triggering
    /// widget itself -- `Choice`/`MenuButton`/etc. -- before any level
    /// window exists to dispatch a push to). Matches FLTK's own
    /// `Menu_State::state == State::PUSHED` (`Fl_Menu.cxx`), used by
    /// `onRelease()` below for exactly the same purpose: FLTK's own
    /// comment on its `FL_RELEASE` case says it plainly -- "Mouse must
    /// either be held down/dragged some, or this must be the second
    /// click (not the one that popped up the menu)".
    private bool freshPress_;

    /// Set (via `pulldown()`'s own optional parameter) by a caller that
    /// has *sibling* top-level items of its own to switch between --
    /// currently only `fl.menu_bar.MenuBar` does. Called from `onKey()`
    /// with `forward=true` for Right, `false` for Left, whenever this
    /// engine is at its outermost level with nothing deeper to open or
    /// close -- matches FLTK's own `Menu_State::handle_left()`/
    /// `handle_right()` switching to the previous/next menubar entry
    /// once at the shallow end of the cascade (`in_menubar &&
    /// current_menu_ix<=0`/`==num_menus-1`, `Fl_Menu.cxx`). Left as
    /// `null` (a no-op) for every other `pulldown()`/`popup()` caller
    /// (`MenuButton`, `Choice`, `InputChoice`, `Tabs`), none of which
    /// have siblings to switch between.
    void delegate(bool forward) siblingSwitch;

    /**
     * Set (via `pulldown()`'s own optional parameter) by a caller that
     * wants a chance to react to a mouse push/move/drag whose root
     * position falls outside every one of *this engine's own* tracked
     * levels, before the normal fallback (cancel on push, no-op on
     * hover) runs -- return `true` to claim it. Currently only
     * `fl.menu_bar.MenuBar` sets this, to cover the mouse-driven half
     * of top-level hover-switching (`Event.move`'s existing case in
     * `MenuBar.handle()` only ever fires *before* any dropdown is open
     * -- once one is, `fl.core.grab()` redirects every mouse event to
     * this popup engine instead, so `MenuBar` itself stops receiving
     * `Event.move` directly at all; this callback is what makes
     * "hover from `Edit`'s open dropdown over to `File`'s bar button"
     * work, since without it the engine has no idea that root position
     * belongs to a sibling top-level item rather than being genuinely
     * outside everything, and would just cancel/no-op instead. Left
     * `null` (no-op fallback
     * runs) for every other `pulldown()`/`popup()` caller (`MenuButton`,
     * `Choice`, `InputChoice`, `Tabs`), none of which have sibling
     * top-level items of their own for a hover to land on.
     */
    bool delegate(int rootX, int rootY) outsideMouseHandler;

    /// Whether root-coordinate point (rootX, rootY) falls within any of
    /// this engine's currently open level windows -- the geometric
    /// "is this point still within my own popup real estate" check
    /// FLTK's `Menu_State::is_inside()` makes (`Fl_Menu.cxx`), used
    /// here for the same purpose: telling a genuine "missed every item,
    /// but the click is still on one of my own windows" event (e.g. a
    /// click on a level's own padding/divider) apart from a real
    /// outside click.
    ///
    /// This needs a real geometric check, not just "which widget did
    /// this event dispatch to", because of how `fl.core.grab()`'s real
    /// `XGrabPointer(..., owner_events=True, ...)` redirects events: a
    /// click over any of *this app's own* windows is delivered there
    /// directly (so it already reached the right level, and a miss
    /// there is legitimately "inside, but no item"), but a click
    /// genuinely outside the whole app -- another window, the desktop --
    /// gets redirected to whichever level currently holds the grab
    /// (`regrab()`, always the deepest one), with coordinates translated
    /// into *that* level's own local space. Both cases dispatch to a
    /// real `MenuLevelWindow.handle()` and both can miss every item
    /// (`itemAt() == -1`) -- widget identity alone can't tell them apart
    /// (the widget *is* ours either way), but comparing the event's true
    /// root position against every level's actual screen rect can.
    bool isInsideAnyLevel(int rootX, int rootY) const
    {
        return levelAtRoot(rootX, rootY) !is null;
    }

    /**
     * Returns whichever of this engine's currently open levels contains
     * root-coordinate point (rootX, rootY), or `null` if none does.
     *
     * `fl.core.grab()`'s dispatch (`fl.core.handle()`'s `Event.push`/
     * `move`/`drag`/`release` cases, matching FLTK's own `Fl::
     * handle_()` exactly -- `if (grab()) wi = grab();`, unconditionally)
     * always routes *every* mouse event to a single grabbed widget --
     * `regrab()` always grabs the *deepest* open level -- regardless of
     * which real X window the raw event physically landed on;
     * `sendEvent()` then translates the event's coordinates to be local
     * to *that* grabbed widget, not the physically-receiving window.
     * Hit-testing directly against `this` using those already-localized
     * coordinates would only ever be correct when `this` (always the
     * deepest level, since that's the sole dispatch target) happens to
     * also be the level the mouse is really over -- the moment the
     * pointer moves onto any *other* open level (a shallower parent,
     * most commonly), the local coordinates it received would be
     * relative to the wrong window entirely (often wildly out of
     * range), so `itemAt()` would reliably return "nothing here," and
     * the real target level's own `handle()` would never even be
     * invoked (dispatch never reaches it -- only the grab widget's
     * `handle()` runs).
     *
     * So this never trusts `this`/locally-dispatched coordinates for
     * hit-testing at all. Every mouse case below instead resolves the
     * *true* target level directly from the event's root coordinates
     * (`fl.core.eventXRoot()`/`eventYRoot()`, untouched by `sendEvent()`'s
     * per-dispatch-target translation -- always real, absolute screen
     * coordinates) against every open level's own known screen rect,
     * the same geometric approach `isInsideAnyLevel()` already used for
     * its own narrower "cancel on outside click" purpose (now just a
     * thin wrapper around this). This is a real, stateless-per-event
     * lookup -- it doesn't matter how the pointer got there (a straight
     * move, or an excursion out of every window and back from some odd
     * angle), so re-entry from anywhere always resolves correctly, with
     * nothing to get stuck on.
     *
     * Searched deepest-first (`foreach_reverse`): cascade levels are
     * drawn in open order with each new one on top, so if two ever
     * overlap (e.g. a submenu that flipped to the *left* of its parent
     * near a screen edge), the visually topmost one should win the hit
     * test, matching what the user actually sees.
     */
    MenuLevelWindow levelAtRoot(int rootX, int rootY) const
    {
        foreach_reverse (lvl; levels)
            if (rootX >= lvl.x() && rootX < lvl.x() + lvl.w()
                && rootY >= lvl.y() && rootY < lvl.y() + lvl.h())
                return cast(MenuLevelWindow) lvl;
        return null;
    }

    /// Cancels this engine immediately, as if Escape had been pressed --
    /// called by `MenuLevelWindow.handle()` when a click or release
    /// lands outside every one of this engine's own open level windows
    /// (see `isInsideAnyLevel()`'s own doc comment). Matches FLTK's
    /// own cancel-on-outside-click behavior
    /// (`Menu_State::handle_mouse_events()`'s FL_PUSH case).
    void cancel()
    {
        done = true;
        picked = null;
    }

    /// Focuses keyboard dispatch (fl.core.grab()) on the deepest open
    /// level, matching the "keyboard always acts on the topmost/
    /// deepest cascade level" rule described in the module doc
    /// comment.
    private void regrab()
    {
        fl.core.grab(levels[$ - 1]);
    }

    /**
     * Repositions `lvl` vertically (never resizing it) so item `idx`'s
     * row stays fully within the current screen's visible Y range --
     * ported from `Menu_Window::autoscroll()` (`Fl_Menu.cxx`). A menu
     * taller than the screen genuinely *is* taller than the screen here
     * too (this port never truncates/re-lays-out its content); what
     * "scrolling" really means, both FLTK and here, is moving the
     * whole (real, oversized) window up or down so the relevant row is
     * inside the visible strip, matching FLTK's
     * `Fl_Window_Driver::reposition_menu_window()` call, via
     * `MenuLevelWindow.resize()`'s pure-reposition path.
     *
     * Called from both `onKey()` and `onHover()`, matching FLTK
     * exactly, which autoscrolls on *every* `current_item` change
     * regardless of source. `MenuLevelWindow.homeScreen_` (see its own
     * doc comment) is what makes this safe to call repeatedly near a
     * monitor boundary, mouse- or keyboard-driven alike: `autoscroll()`
     * measures against that captured-at-construction monitor rather
     * than re-deriving which monitor to measure against from the
     * window's own *current*, already-scrolled position.
     */
    private void autoscroll(MenuLevelWindow lvl, int idx)
    {
        if (idx < 0) return;
        int rh = lvl.rowHeight();
        int scrX, scrY, scrW, scrH;
        fl.core.screenXYWH(scrX, scrY, scrW, scrH, lvl.homeScreen_);

        int rowTop = lvl.y() + fl.core.boxDx(Boxtype.upBox) + 2 + idx * rh;
        int delta;
        if (idx == 0 && rowTop <= scrY + rh)
            delta = scrY - rowTop + 10;
        else if (rowTop <= scrY + rh)
            delta = scrY - rowTop + 10 + rh;
        else
        {
            delta = rowTop + rh - scrH - scrY;
            if (delta < 0) return; // already fully visible, nothing to do
            delta = -delta - 10;
        }
        lvl.resize(lvl.x(), lvl.y() + delta, lvl.w(), lvl.h());
    }

    /// Opens (or replaces) the submenu at depth `parentDepth + 1`,
    /// closing any deeper levels first. `item` must be a submenu item
    /// belonging to levels[parentDepth].
    void openSubmenu(size_t parentDepth, const(MenuItem)* item)
    {
        closeLevelsBelow(parentDepth + 1);

        const(MenuItem)* first = (item.flags & menuSubmenu) ? item + 1 : item.submenuItems_;
        if (first is null) return;

        auto parent = levels[parentDepth];
        int rh = parent.rowHeight();
        int idx = -1;
        foreach (i, it; parent.items)
            if (it is item) { idx = cast(int) i; break; }
        int itemY = parent.y() + (idx >= 0 ? idx * rh : 0);

        FlGroup.current(null);
        auto probe = new MenuLevelWindow(this, first, style, 0, 0, 10, 10);
        int contentW = 60;
        int rowH = probe.rowHeight();
        foreach (it; probe.items)
        {
            int hh;
            int ww = it.measure(hh, style) + 24;
            // Room for the cascade arrow this level will draw next to a
            // nested submenu item -- matches FLTK's own per-item
            // `+= FL_NORMAL_SIZE` for FL_SUBMENU/FL_SUBMENU_POINTER
            // items in Menu_Window::calc_size().
            if (it.submenu()) ww += style.textsize;
            if (ww > contentW) contentW = ww;
        }
        // Room for the shortcut-key column this level will draw, if any
        // item has one -- see drawShortcut()'s doc comment. Deliberately
        // conditional (FLTK always adds this, even with zero
        // shortcuts) so a plain submenu with no shortcuts doesn't grow
        // wider for no visible reason.
        if (probe.shortcutsW + probe.modifiersW > 0)
            contentW += probe.shortcutsW + probe.modifiersW + 2 * fl.core.boxDx(Boxtype.upBox) + 7;
        // A submenu with zero real items (just an immediate sentinel --
        // e.g. test/menubar.cxx's "E&mpty" entry) still needs a real,
        // clickable strip, not a zero-height window: matches FLTK's
        // own Menu_Window::calc_size() formula for `num_items == 0`
        // (`h((num_items ? item_height*num_items-4 : 0)+2*BW+3)`, which
        // reduces to `2*BW+3` -- a small but nonzero strip you can still
        // hover through to reach a sibling top-level item). A 0-height
        // window here would mean this level effectively didn't exist at
        // all: nothing to click, nothing to hover past, and (since
        // `PopupEngine.isInsideAnyLevel()`/level lookups all treat a
        // 0-height rect as containing no points) no way to reach items
        // *beyond* it via mouse or keyboard either.
        int contentH = probe.items.length > 0
            ? rowH * cast(int) probe.items.length
            : 2 * fl.core.boxDx(Boxtype.upBox) + 3;
        FlGroup.current(null);
        destroy(probe);

        int scrX, scrY, scrW, scrH;
        fl.core.screenXYWH(scrX, scrY, scrW, scrH, parent.x(), itemY);
        int px = parent.x() + parent.w();
        if (px + contentW > scrX + scrW) px = parent.x() - contentW;
        if (px < scrX) px = scrX;
        int py = itemY;
        if (py + contentH > scrY + scrH) py = scrY + scrH - contentH;
        if (py < scrY) py = scrY;

        FlGroup.current(null);
        auto win = new MenuLevelWindow(this, first, style, px, py, contentW, contentH);
        levels ~= win;
        win.show();
        regrab();
    }

    /// Destroys every open level from `depth` onward (deepest first).
    void closeLevelsBelow(size_t depth)
    {
        while (levels.length > depth)
        {
            auto lvl = levels[$ - 1];
            levels = levels[0 .. $ - 1];
            lvl.hide();
            destroy(lvl);
        }
        if (levels.length > 0) regrab();
    }

    /**
     * Forcibly closes this engine immediately -- called (via
     * `activeEngine_`) when a *newer*, reentrant `run()` call needs to
     * take over. See `run()`'s own doc comment for exactly when this
     * happens: clicking a different menu-triggering widget (e.g. a
     * `MenuBar`'s "File" while "Edit"'s dropdown is already open)
     * delivers a real, normal `Event.push` to that sibling widget
     * (`fl.core.grab()`'s `owner_events=True` semantics don't intercept
     * same-app clicks -- see that function's own doc comment), which
     * synchronously opens a *second* `run()` call nested inside this
     * one's own suspended `fl.core.wait()` call, deeper in the C stack
     * -- there's no way for *this* engine's own loop to notice and
     * close itself first, since the click that would tell it to is the
     * very thing that's reentering instead.
     *
     * Destroys every open level right away (so nothing stays visibly
     * on screen underneath the new popup) and marks `done` so this
     * engine's own `while (!done)` loop in `run()` -- still suspended,
     * deeper in the call stack -- exits cleanly the next time control
     * returns to it, without trying to re-touch levels this function
     * already destroyed (its own cleanup loop finds `levels.length ==
     * 0` already and no-ops).
     */
    private void forceClose()
    {
        done = true;
        picked = null;
        if (titleWin !is null)
        {
            titleWin.hide();
            destroy(titleWin);
            titleWin = null;
        }
        while (levels.length > 0)
        {
            auto lvl = levels[$ - 1];
            levels = levels[0 .. $ - 1];
            lvl.hide();
            destroy(lvl);
        }
    }

    void onHover(MenuLevelWindow win, int idx)
    {
        size_t depth = 0;
        foreach (i, lvl; levels) if (lvl is win) { depth = i; break; }

        if (idx < 0) return; // moving over padding/divider -- leave selection as-is

        // Nothing to do if this item is already highlighted here *and*
        // either it has no submenu at all, or its submenu is *already*
        // open as the next level down. The condition for "already
        // reconciled, nothing to do" is that a
        // deeper level *does* exist (`levels.length > depth + 1`) --
        // matching this function's own invariant that levels[depth+1],
        // whenever present, always corresponds to win.items[highlighted]'s
        // own submenu. (Deliberately not just "== idx": Left-arrow can
        // close a deeper level while leaving the parent's highlighted
        // index unchanged -- see onKey() -- so re-hovering that same
        // item afterward, now correctly finding levels.length == depth+1
        // again, must still fall through and reopen it.)
        if (win.highlighted == idx
            && (!win.items[idx].submenu() || levels.length > depth + 1))
            return;

        win.highlighted = idx;
        win.redraw();
        // Wired into mouse hover, matching FLTK exactly (`Fl::
        // handle_()`'s own main loop autoscrolls on *every*
        // current_item change, mouse-driven or not).
        autoscroll(win, idx);
        closeLevelsBelow(depth + 1);

        auto it = win.items[idx];
        if (it.submenu()) openSubmenu(depth, it);
    }

    void onPress(MenuLevelWindow win, int idx)
    {
        freshPress_ = true;
        onHover(win, idx);
    }

    void onRelease(MenuLevelWindow win, int idx)
    {
        if (idx < 0) return;
        auto it = win.items[idx];
        if (it.submenu())
        {
            onHover(win, idx); // make sure it's open; stay up
            return;
        }
        // This guard matters for a `Choice` like chart-simple's "Chart
        // type" -- which opens its dropdown *centered on the current
        // value*, per run()'s own startHighlight positioning below,
        // unlike a MenuButton's opens-below-itself layout -- where the
        // opening click's own matching release naturally lands right
        // back on the already-selected item. Without this guard, *any*
        // release landing on a real item would finalize immediately,
        // with no way to tell "this is the very release that opened the
        // menu" apart from "the user genuinely clicked an item after the
        // menu was already up" -- ported from FLTK's real condition (see
        // `freshPress_`'s own doc comment for the exact quote): only
        // finalize if the mouse moved/paused enough to no longer count
        // as a quick click (`!fl.core.eventIsClick()`, covers the
        // press-drag-release gesture), or a genuine second press has
        // already landed on this engine since it opened (`freshPress_`,
        // covers click-to-open-then-click-the-item). Neither being true
        // means this is the opening click's own release -- leave the
        // item highlighted (already done by onHover() above) and the
        // menu open, matching FLTK exactly.
        if (!fl.core.eventIsClick() || freshPress_)
        {
            picked = it;
            done = true;
        }
    }

    private int deepestSelectableMove(MenuLevelWindow lvl, int dir)
    {
        int n = cast(int) lvl.items.length;
        if (n == 0) return -1;
        int i = lvl.highlighted;
        for (int steps = 0; steps < n; steps++)
        {
            i = (i < 0) ? (dir > 0 ? 0 : n - 1) : ((i + dir + n) % n);
            if (lvl.items[i].selectable()) return i;
        }
        return -1;
    }

    bool onKey()
    {
        auto lvl = levels[$ - 1];
        auto key = fl.core.eventKey();

        if (key == escape) { done = true; picked = null; return true; }

        // Backspace and (unshifted) Tab are plain aliases for Up/Down --
        // ported from Menu_State::handle_keyboard_event()'s own
        // FL_BackSpace/FL_Tab cases (Fl_Menu.cxx); Shift+Tab is Up.
        // FLTK's FL_Tab case also has an in_menubar-specific branch
        // (Tab at the shallowest level switches to the next top-level
        // menu) that doesn't apply here -- fl.menu_popup's PopupEngine
        // never tracks the menu *bar* row itself as one of its own
        // `levels` (see fl.menu_bar's row in PORTING.md), so "the
        // shallowest level" here is always a real dropdown, not the bar.
        bool shifted = (fl.core.eventState() & stateShift) != 0;
        if (key == backSpace || (key == tab && shifted)) goto caseUp;
        if (key == tab) goto caseDown;

        if (key == down)
        {
        caseDown:
            auto i = deepestSelectableMove(lvl, 1);
            if (i >= 0) { lvl.highlighted = cast(int) i; lvl.redraw(); autoscroll(lvl, cast(int) i); closeLevelsBelow(levels.length); }
            return true;
        }
        if (key == up)
        {
        caseUp:
            auto i = deepestSelectableMove(lvl, -1);
            if (i >= 0) { lvl.highlighted = cast(int) i; lvl.redraw(); autoscroll(lvl, cast(int) i); closeLevelsBelow(levels.length); }
            return true;
        }
        if (key == right)
        {
            if (lvl.highlighted >= 0)
            {
                auto it = lvl.items[lvl.highlighted];
                if (it.submenu())
                {
                    size_t depth = levels.length - 1;
                    openSubmenu(depth, it);
                    auto i = deepestSelectableMove(levels[$ - 1], 1);
                    if (i >= 0) { levels[$ - 1].highlighted = cast(int) i; levels[$ - 1].redraw(); autoscroll(levels[$ - 1], cast(int) i); }
                    return true;
                }
            }
            // Nothing to drill into (no highlighted item, or it's a
            // plain leaf) -- if we're at the outermost level, this is
            // where a menubar-triggered popup switches to the next
            // sibling top-level menu instead, matching FLTK's own
            // Menu_State::handle_right(). siblingSwitch(), if set, may
            // reentrantly open a whole new PopupEngine and force-close
            // this one (see PopupEngine.forceClose()'s doc comment) --
            // nothing below this point may touch `lvl`/`levels` again.
            if (levels.length == 1 && siblingSwitch !is null) siblingSwitch(true);
            return true;
        }
        if (key == left)
        {
            if (levels.length > 1) { closeLevelsBelow(levels.length - 1); return true; }
            // Same sibling-switch as Right above, other direction --
            // see that branch's comment on why nothing may touch
            // `lvl`/`levels` after this call.
            if (siblingSwitch !is null) siblingSwitch(false);
            return true;
        }
        if (key == enter || key == kpEnter)
        {
            if (lvl.highlighted >= 0)
            {
                auto it = lvl.items[lvl.highlighted];
                // Ported from Menu_State::handle_select(): a submenu
                // item *with its own callback set* finalizes (picks)
                // rather than drilling in -- matching FLTK's exact
                // condition (`!current_item->callback_` guards the
                // auto-drill). Rare in practice (most submenu headers
                // have no callback of their own), but a real, distinct
                // FLTK behavior, not an oversight to skip.
                if (it.submenu() && it.callback() is null)
                {
                    size_t depth = levels.length - 1;
                    openSubmenu(depth, it);
                    auto i = deepestSelectableMove(levels[$ - 1], 1);
                    if (i >= 0) { levels[$ - 1].highlighted = cast(int) i; levels[$ - 1].redraw(); autoscroll(levels[$ - 1], cast(int) i); }
                }
                else
                {
                    picked = it;
                    done = true;
                }
            }
            return true;
        }

        // Shortcut-key matching (mnemonic '&' letters, or an item's own
        // explicit shortcut) -- ported from Menu_State::handle_shortcut()
        // (Fl_Menu.cxx): searches every open level, deepest first, each
        // level's own top-level items only (MenuItem.findShortcut()'s
        // own documented scope -- it doesn't descend into nested
        // submenus). A match on a leaf item finalizes the pick
        // immediately; a match on a submenu item selects/opens it
        // without finalizing, matching FLTK exactly.
        foreach_reverse (i, candidate; levels)
        {
            if (candidate.items.length == 0) continue;
            int ii;
            auto m = candidate.items[0].findShortcut(&ii);
            if (m is null) continue;
            candidate.highlighted = ii;
            candidate.redraw();
            autoscroll(candidate, ii);
            closeLevelsBelow(i + 1);
            if (m.submenu())
                openSubmenu(i, m);
            else
            {
                picked = m;
                done = true;
            }
            return true;
        }
        return false;
    }

    /**
     * Runs this engine's own cascading-popup loop until an item is
     * picked or the menu is dismissed. May be called *reentrant* --
     * i.e. from within another, still-active `PopupEngine`'s own
     * suspended `fl.core.wait()` call -- whenever a different menu-
     * triggering widget (e.g. a second `MenuBar` item) gets clicked
     * while a menu is already open; see `forceClose()`'s own doc
     * comment for exactly why that happens and can't be prevented at
     * the X11-grab level alone. When that happens, the previously-
     * active engine is force-closed immediately, before this one opens
     * anything -- so at most one cascading menu is ever visible.
     */
    const(MenuItem)* run(const(MenuItem)* items, int screenX, int screenY, int w, int h,
        const(MenuItem)* initialItem, MenuStyle style,
        void delegate(bool forward) siblingSwitch = null, string title = null,
        bool delegate(int rootX, int rootY) outsideMouseHandler = null)
    {
        if (activeEngine_ !is null && activeEngine_ !is this)
            activeEngine_.forceClose();
        auto previousEngine = activeEngine_;
        activeEngine_ = this;
        scope(exit) activeEngine_ = previousEngine;

        this.siblingSwitch = siblingSwitch;
        this.outsideMouseHandler = outsideMouseHandler;
        this.style = style;
        FlGroup.current(null);

        auto probe = new MenuLevelWindow(this, items, style, 0, 0, 10, 10);
        int rh = probe.rowHeight();
        int contentW = w > 60 ? w : 60;
        foreach (it; probe.items)
        {
            int hh;
            int ww = it.measure(hh, style) + 24;
            // See openSubmenu()'s identical comment: room for the
            // cascade arrow / shortcut-key column, respectively.
            if (it.submenu()) ww += style.textsize;
            if (ww > contentW) contentW = ww;
        }
        if (probe.shortcutsW + probe.modifiersW > 0)
            contentW += probe.shortcutsW + probe.modifiersW + 2 * fl.core.boxDx(Boxtype.upBox) + 7;
        // See openSubmenu()'s identical comment: a zero-item menu (e.g.
        // a MenuBar's "E&mpty" top-level entry, which reaches this
        // function -- not openSubmenu() -- via MenuBar.doPulldown())
        // still needs a small, real, nonzero-height window.
        int contentH = probe.items.length > 0
            ? rh * cast(int) probe.items.length
            : 2 * fl.core.boxDx(Boxtype.upBox) + 3;
        int startHighlight = -1;
        if (initialItem !is null)
            foreach (i, it; probe.items)
                if (it is initialItem) { startHighlight = cast(int) i; break; }
        FlGroup.current(null);
        destroy(probe);

        // Title measurement -- ported from Menu_Window's own `if (t)
        // titile_w = t->measure(&title_h, button) + 12;` -- a wide
        // title can widen the whole popup, matching FLTK's `if
        // (titile_w > W) W = titile_w;`.
        MenuItem titleItem;
        int titleW, titleH;
        if (title !is null)
        {
            titleItem = MenuItem(title);
            titleW = titleItem.measure(titleH, style) + 12;
            if (titleW > contentW) contentW = titleW;
        }

        int scrX, scrY, scrW, scrH;
        fl.core.screenXYWH(scrX, scrY, scrW, scrH, screenX, screenY);
        int px = screenX;
        int py = screenY + h; // below the given rect, like a pulldown
        if (startHighlight >= 0)
            py = screenY + (h - rh) / 2 - startHighlight * rh; // centered over initialItem
        if (px + contentW > scrX + scrW) px = scrX + scrW - contentW;
        if (px < scrX) px = scrX;
        if (py + contentH > scrY + scrH) py = scrY + scrH - contentH;
        if (py < scrY) py = scrY;

        FlGroup.current(null);
        auto win = new MenuLevelWindow(this, items, style, px, py, contentW, contentH);
        win.highlighted = startHighlight;
        levels ~= win;
        win.show();

        if (title !is null)
        {
            // Ported from Menu_Window's own non-menubar title
            // positioning: `int dy = 2; int ht = title_h+2*BW+3; title
            // = new Menu_Title_Window(X, Y-ht-dy, titile_w, ht, t);` --
            // a small strip sitting just above the main dropdown.
            int ht = titleH + 2 * fl.core.boxDx(Boxtype.upBox) + 3;
            FlGroup.current(null);
            titleWin = new MenuTitleWindow(titleItem, style, px, py - ht - 2, titleW, ht);
            titleWin.show();
        }

        fl.core.grab(win);

        done = false;
        picked = null;
        freshPress_ = false;
        // Outside-click/release cancellation is handled directly by
        // MenuLevelWindow.handle()'s Event.push/release cases (via
        // isInsideAnyLevel()/cancel()) -- a real geometric root-
        // coordinate check, matching FLTK's own Menu_State::
        // is_inside(). No separate fl.core.pushed()-based detector is
        // needed here: `Event.push` always latches `pushed_` to
        // `grab()` first, so `pushed()` can never legitimately observe
        // anything outside this engine's own levels while grabbed.
        while (!done)
            fl.core.wait();

        fl.core.grab(null);
        if (titleWin !is null)
        {
            titleWin.hide();
            destroy(titleWin);
            titleWin = null;
        }
        while (levels.length > 0)
        {
            auto lvl = levels[$ - 1];
            levels = levels[0 .. $ - 1];
            lvl.hide();
            destroy(lvl);
        }
        // Leave global construction state clean for whatever the
        // caller does next -- FlGroup.current() would otherwise still
        // point at a just-destroyed level window (see the Window
        // constructor's own implicit begin(), and CLAUDE.md's note on
        // destroy() wiping an object's fields immediately).
        FlGroup.current(null);
        return picked;
    }
}

/**
 * D equivalent of Fl_Menu_Item::pulldown(): shows `items` as a
 * cascading popup positioned relative to (screenX, screenY, w, h) --
 * screen-*absolute* coordinates (see the module doc comment: this is
 * a deliberate API simplification over FLTK's window-relative
 * `Fl_Menu_Item::pulldown()`, which converts internally using either
 * an owning widget's window chain or the current event's root-vs-
 * local delta; callers here do that conversion themselves, e.g. via
 * `button.window().x() + button.x()` or `fl.core.eventXRoot()`).
 * `initialItem`, if found among `items`, is centered over the rect
 * (matching Fl_Choice's usage); otherwise the menu opens just below
 * it. Runs its own nested event loop (fl.core.wait(), see task #25's
 * doc comment) until an item is picked or the menu is dismissed.
 * Returns the picked item, or null.
 */
const(MenuItem)* pulldown(const(MenuItem)* items, int screenX, int screenY, int w, int h,
    const(MenuItem)* initialItem = null, MenuStyle style = MenuStyle.defaults(),
    void delegate(bool forward) siblingSwitch = null, string title = null,
    bool delegate(int rootX, int rootY) outsideMouseHandler = null)
{
    // Deliberately doesn't reject `items.text is null` -- "items points
    // at a valid sentinel MenuItem{0}" (a genuinely empty submenu, e.g.
    // test/menubar.cxx's "E&mpty" -- one array slot, immediately
    // closed) is not the same as "items is a null pointer" (no menu at
    // all). FLTK draws no such distinction: `Fl_Menu_Item::pulldown()` is
    // a member function called *on* the array pointer, so `this` can
    // never be null by construction, and it unconditionally proceeds
    // to build a `Menu_Window` regardless of item count -- a 0-item
    // menu is a perfectly ordinary, valid input FLTK (its own
    // `Menu_Window` constructor already has a real, non-degenerate
    // `num_items == 0` formula, see `run()`'s own contentH comment
    // above). Only a genuine null *pointer* -- something no valid
    // caller in this port ever actually passes (every real call site
    // already gates on `first !is null` before reaching here) -- is
    // rejected; a valid pointer to an empty array opens the
    // real, small, correctly-clickable-past box FLTK shows too.
    if (items is null) return null;
    auto engine = new PopupEngine();
    return engine.run(items, screenX, screenY, w, h, initialItem, style, siblingSwitch, title,
        outsideMouseHandler);
}

/**
 * D equivalent of Fl_Menu_Item::popup(): pulldown() with a zero-size
 * rect at (screenX, screenY), so the menu opens right at that point
 * (or centered over `initialItem` if given). `title`, if non-null,
 * shows a small title strip above the dropdown -- see
 * `MenuTitleWindow`'s own doc comment.
 */
const(MenuItem)* popup(const(MenuItem)* items, int screenX, int screenY,
    const(MenuItem)* initialItem = null, MenuStyle style = MenuStyle.defaults(),
    string title = null)
{
    return pulldown(items, screenX, screenY, 0, 0, initialItem, style, null, title);
}

// The unittests below exercise everything that doesn't need a live X
// server -- construction, hit-testing math, and the keyboard-
// navigation helper -- matching this project's usual split between
// headless `dub test` coverage and an interactive smoke test (see
// PORTING.md; the real windowing/event-loop path is only verified
// against a live display, in smoke-tests/, never run unsupervised).

unittest
{
    FlGroup.current(null);
    MenuItem[] items = [
        MenuItem("one"),
        MenuItem("two"),
        MenuItem("hidden", 0, null, menuInvisible),
        MenuItem("three"),
        MenuItem(null),
    ];

    auto engine = new PopupEngine();
    auto win = new MenuLevelWindow(engine, &items[0], MenuStyle.defaults(), 0, 0, 100, 100);

    // Invisible items are skipped by next(), so only 3 make it into
    // this level's display list.
    assert(win.items.length == 3);

    int rh = win.rowHeight();
    assert(rh > 0);

    assert(win.itemAt(10, 0) == 0);
    assert(win.itemAt(10, rh) == 1);
    assert(win.itemAt(10, 2 * rh) == 2);
    assert(win.itemAt(10, 100 * rh) == -1); // past the last row
    assert(win.itemAt(-1, 0) == -1);        // outside the window entirely
    assert(win.itemAt(10, -1) == -1);

    win.draw(); // headless: fl.draw's primitives early-return with no display

    destroy(win);
    FlGroup.current(null);
}

unittest
{
    // Inactive/invisible items are skipped by deepestSelectableMove(),
    // and it wraps around both directions.
    FlGroup.current(null);
    MenuItem[] items = [
        MenuItem("a"),
        MenuItem("b", 0, null, menuInactive),
        MenuItem("c"),
        MenuItem(null),
    ];

    auto engine = new PopupEngine();
    auto win = new MenuLevelWindow(engine, &items[0], MenuStyle.defaults(), 0, 0, 100, 100);
    assert(win.items.length == 3);

    win.highlighted = -1;
    assert(engine.deepestSelectableMove(win, 1) == 0); // -1 + down -> first

    win.highlighted = 0;
    assert(engine.deepestSelectableMove(win, 1) == 2); // skips inactive "b"

    win.highlighted = 2;
    assert(engine.deepestSelectableMove(win, 1) == 0); // wraps back to "a"

    win.highlighted = 0;
    assert(engine.deepestSelectableMove(win, -1) == 2); // wraps upward, skipping "b"

    destroy(win);
    FlGroup.current(null);
}
