/*
 * Ported from FL/Fl_Menu_Bar.H + src/Fl_Menu_Bar.cxx (FLTK 1.5.0): a
 * horizontal strip of top-level menu titles/buttons, each opening a
 * (vertical) dropdown if it's a submenu.
 *
 * Structural deviation from FLTK, and the one place the "simplified
 * popup engine" scoping decision (see fl.menu_popup's doc comment)
 * shows up as more than a cosmetic difference: FLTK hands its
 * *entire* menu array plus a `menubar=1` flag to a single
 * `Fl_Menu_Item::pulldown()` call, and the deep popup engine itself
 * (`Menu_Window`'s `in_menubar` flag) lays out level 0 horizontally
 * inside the same cascading-window machinery every other menu uses.
 * `fl.menu_popup`'s engine only ever renders vertical lists (see that
 * module's doc comment on why), so it can't do that -- instead,
 * `MenuBar` draws and hit-tests its own horizontal top-level row
 * directly (`draw()`/`itemAtX()`, mirroring FLTK's own `draw()`
 * layout math for the hit-testing), and only calls into
 * `fl.menu_popup.pulldown()` for the vertical dropdown *of whichever
 * top-level item was actually clicked* -- passing just that item's
 * submenu array, not the whole bar. A top-level item with no submenu
 * (a menubar "button") is picked directly with no popup at all, same
 * as FLTK. Observably the same behavior; structurally, one call
 * that used to flow through the shared engine now happens in this
 * module instead.
 *
 * Other deviations, matching fl.menu_button's already-documented ones:
 * no `menu_end()` (no local-array staging to finalize, see fl.menu_'s
 * doc comment); `pulldown()` takes screen-absolute coordinates
 * (`Widget.topWindowOffset()` does the conversion, see fl.menu_popup's
 * own doc comment on why); `update()`/`play_menu()` (Fl_Sys_Menu_Bar
 * integration hooks, `virtual` FLTK purely so a native-OS-menu-bar
 * subclass can override them) aren't ported -- no `Fl_Sys_Menu_Bar`
 * exists in this port, and nothing else calls them.
 */
module fl.menu_bar;

import fl.menu_ : Menu_;
import fl.menu_item : MenuItem, menuSubmenu, menuDivider;
import fl.menu_popup;
import fl.enumerations : Event, dark3, light3;
import fl.widget_tracker : WidgetTracker;
import fldraw = fl.draw;
static import fl.core;

class MenuBar : Menu_
{
    /// The top-level item whose dropdown is currently showing, or null
    /// if none is. FLTK doesn't need an equivalent field: its own
    /// `Fl_Menu_Bar::draw()` never highlights the open item itself
    /// either (see this module's own top comment) -- the *deep,
    /// shared* popup engine draws level 0 as the horizontal bar row
    /// too (via `pulldown()`'s `menubar=1` flag) and handles its
    /// highlight-while-open state internally, uniformly with every
    /// vertical dropdown. Since `fl.menu_popup`'s simplified engine
    /// only ever renders vertical lists (that same top comment), this
    /// port's `MenuBar` has to track and draw its own top-level
    /// highlight separately -- this field is that tracking.
    private const(MenuItem)* currentPulldownTarget_;

    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
    }

    override void draw()
    {
        drawBox();
        if (menu() is null || menu().text is null) return;

        int X = x() + 6;
        for (auto m = menu().first(); m.text !is null; m = m.next())
        {
            int mh;
            int itemW = m.measure(mh, style()) + 16;
            m.draw(X, y(), itemW, h(), style(), m is currentPulldownTarget_ ? 1 : 0);
            X += itemW;
            if (m.flags & menuDivider)
            {
                int y1 = y() + fl.core.boxDy(box());
                int y2 = y1 + h() - fl.core.boxDh(box()) - 1;
                fldraw.fl_color(dark3);
                fldraw.fl_yxline(X - 6, y1, y2);
                fldraw.fl_color(light3);
                fldraw.fl_yxline(X - 5, y1, y2);
            }
        }
    }

    /// Finds which top-level item covers screen-relative x, matching
    /// draw()'s own horizontal layout exactly. Returns null past the
    /// last item.
    private const(MenuItem)* itemAtX(int mx, out int itemX, out int itemW) const
    {
        if (menu() is null || menu().text is null) return null;
        int X = x() + 6;
        for (auto m = menu().first(); m.text !is null; m = m.next())
        {
            int mh;
            int w = m.measure(mh, style()) + 16;
            if (mx >= X && mx < X + w)
            {
                itemX = X;
                itemW = w;
                return m;
            }
            X += w;
        }
        return null;
    }

    /// Finds the next (`forward=true`) or previous submenu-type top-
    /// level item relative to `target`, wrapping around -- non-submenu
    /// top-level entries (plain menubar "buttons") are skipped, since
    /// there's nothing to switch *to* for those (matches this module's
    /// own `doPulldown()`, which only ever opens a dropdown for a
    /// `submenu()` item in the first place). Returns null if `target`
    /// isn't found or there's nothing else to switch to. Backs the
    /// Left/Right-arrow menubar navigation `fl.menu_popup`'s
    /// `PopupEngine.siblingSwitch` callback below calls into, matching
    /// FLTK's own `Menu_State::handle_left()`/`handle_right()`
    /// switching to the previous/next menubar entry once at the shallow
    /// end of an open cascade.
    private const(MenuItem)* siblingItem(const(MenuItem)* target, bool forward) const
    {
        const(MenuItem)*[] items;
        for (auto m = menu().first(); m.text !is null; m = m.next())
            if (m.submenu()) items ~= m;
        if (items.length == 0) return null;

        ptrdiff_t idx = -1;
        foreach (i, it; items)
            if (it is target) { idx = cast(ptrdiff_t) i; break; }
        if (idx < 0) return null;

        ptrdiff_t n = cast(ptrdiff_t) items.length;
        ptrdiff_t next = forward ? (idx + 1) % n : (idx - 1 + n) % n;
        return items[next];
    }

    /**
     * Shared tail for the FL_PUSH and FL_SHORTCUT cases -- matches
     * FLTK's own `goto J1` structure (see `fl.repeat_button`'s
     * documented goto-to-factored-function precedent): `initial ==
     * null` means "find the clicked top-level item first" (FL_PUSH),
     * otherwise `initial` is an already-found submenu title (from
     * find_shortcut()) whose dropdown should open directly.
     */
    private int doPulldown(const(MenuItem)* initial)
    {
        // "Menu owner deleted mid-loop" guard (STR #3503) -- ported
        // from `Fl_Menu_Item::pulldown()`'s own `Fl_Widget_Tracker
        // wp((Fl_Widget*)pbutton);`, created as literally its first
        // statement, before touching `pbutton` any further, matching
        // `fl.choice`/`fl.menu_button`/`fl.input_choice`'s own guards
        // around their `fl.menu_popup.pulldown()`/`popup()` calls --
        // `this` (the `MenuBar`) gets dereferenced again right after
        // `pulldown()` returns (`currentPulldownTarget_`/`redraw()`/
        // `picked()` below), and `pulldown()`'s own nested `fl.core.wait()`
        // loop can run arbitrary app callbacks (timers, other widgets'
        // callbacks) for as long as the dropdown stays open -- exactly
        // FLTK's own scenario, a timer callback destroying the menu-
        // owning widget while its dropdown is still open.
        auto tracker = WidgetTracker(this);
        handle(Event.beforeMenu);
        if (tracker.deleted()) return 1;

        const(MenuItem)* target = initial;
        int itemX = x();
        int itemW = w();
        if (target is null)
        {
            int foundX, foundW;
            target = itemAtX(fl.core.eventX(), foundX, foundW);
            if (target is null) return 1; // clicked empty bar space
            itemX = foundX;
            itemW = foundW;
        }
        else
        {
            int X = x() + 6;
            for (auto m = menu().first(); m.text !is null; m = m.next())
            {
                int mh;
                int w = m.measure(mh, style()) + 16;
                if (m is target) { itemX = X; itemW = w; break; }
                X += w;
            }
        }

        // `itemAtX()` finds an item purely by X position, with no
        // activity filter at all (unlike `MenuLevelWindow.itemAt()`,
        // which already excludes non-selectable items for regular
        // dropdown levels) -- so a disabled top-level item like
        // test/menubar.cxx's own "&Inactive" needs this explicit check
        // to stay unresponsive when clicked. Ported
        // from FLTK's own main pulldown() loop, which checks
        // `m->selectable()` before ever treating the current item as
        // something to act on ("if (!m || !m->selectable()) { ...
        // continue; }", Fl_Menu.cxx) -- clicking (or `find_shortcut()`-
        // matching) an inactive top-level entry is a no-op, matching
        // its own dimmed, unresponsive appearance.
        if (!target.selectable()) return 1;

        const(MenuItem)* result;
        if (target.submenu())
        {
            const(MenuItem)* first = (target.flags & menuSubmenu) ? target + 1 : target.submenuItems_;
            if (first !is null)
            {
                int xoff, yoff;
                auto topWin = topWindowOffset(xoff, yoff);
                int screenX = (topWin !is null ? topWin.x() : 0) + xoff + (itemX - x());
                int screenY = (topWin !is null ? topWin.y() : 0) + yoff + h();

                // Highlight this item as "open" for the duration of the
                // (blocking) pulldown() call below -- including while
                // it's reentrant (see fl.menu_popup's PopupEngine.
                // forceClose() for exactly when that happens): a hover-
                // triggered switch (Event.move below) calls doPulldown()
                // again from inside this very call, overwriting
                // currentPulldownTarget_ to the new item before this
                // frame's own pulldown() call returns -- which is
                // exactly right, since that's the item actually showing
                // by the time this frame's redraw()/clear below run.
                currentPulldownTarget_ = target;
                redraw();
                result = fl.menu_popup.pulldown(first, screenX, screenY, itemW, 0, null, style(),
                    (forward) {
                        auto sib = siblingItem(target, forward);
                        if (sib !is null) doPulldown(sib);
                    }, null,
                    (rootX, rootY) {
                        // See fl.menu_popup's own outsideMouseHandler doc
                        // comment for why the *existing* Event.move case
                        // below can't cover hovering from an open
                        // dropdown to a sibling top-level item by itself:
                        // once a
                        // dropdown is open, fl.core.grab() redirects
                        // every mouse event to the popup engine, so this
                        // widget's own handle() stops receiving
                        // Event.move directly at all. This callback is
                        // what the popup engine calls instead, whenever
                        // a mouse event's root position falls outside
                        // every one of *its own* levels -- convert to
                        // this widget's own local coordinate frame and
                        // reuse the exact same hover-switch check.
                        int xo, yo;
                        auto tw = topWindowOffset(xo, yo);
                        int barScreenX = (tw !is null ? tw.x() : 0) + xo;
                        int barScreenY = (tw !is null ? tw.y() : 0) + yo;
                        if (rootY < barScreenY || rootY >= barScreenY + h()) return false;
                        return trySwitchHoverAt(rootX - barScreenX);
                    });
                // See this function's own top comment: `pulldown()`'s
                // nested wait loop can run arbitrary app callbacks for
                // as long as the dropdown stayed open, so `this` may no
                // longer exist by the time it returns -- matching
                // FLTK's own post-loop `(pbutton && wp.deleted()) ?
                // NULL : pp.current_item` (the picked result is forced
                // to "nothing" and no further widget state is touched),
                // stop here rather than dereferencing a destroyed `this`.
                if (tracker.deleted()) return 1;
                currentPulldownTarget_ = null;
                redraw();
            }
        }
        else
        {
            result = target;
        }
        picked(result);
        return 1;
    }

    /// Shared hover-switch check: if a dropdown is currently open
    /// (`currentPulldownTarget_ !is null`) and `localX` (relative to
    /// this widget's own origin, matching `itemAtX()`'s convention)
    /// lands on a *different* top-level submenu item, switches the
    /// open dropdown to it. Returns whether it did. Used both by
    /// `Event.move` below (the case where this widget still receives
    /// the raw event directly -- see that case's own comment on when
    /// that actually happens) and by the `outsideMouseHandler` callback
    /// passed to `fl.menu_popup.pulldown()` above (the practical case,
    /// once any dropdown has actually grabbed the pointer).
    private bool trySwitchHoverAt(int localX)
    {
        if (currentPulldownTarget_ is null) return false;
        int foundX, foundW;
        auto hovered = itemAtX(localX, foundX, foundW);
        if (hovered is null || hovered is currentPulldownTarget_ || !hovered.submenu())
            return false;
        doPulldown(hovered);
        return true;
    }

    override int handle(Event e)
    {
        if (menu() is null || menu().text is null) return 0;

        switch (e)
        {
        case Event.enter:
        case Event.leave:
            return 1;

        case Event.move:
            // Matches real FLTK: once one top-level item's dropdown is
            // open, hovering to a different one switches to it without
            // needing another click. Deliberately does *not* open a
            // dropdown from a bare hover when none is open yet -- only
            // switches an already-open one, matching the click-to-open-
            // the-first-one behavior every other part of this port's UI
            // uses. In practice this case rarely fires once a dropdown
            // is actually open (fl.core.grab() redirects mouse events
            // elsewhere at that point -- see trySwitchHoverAt()'s own
            // doc comment for the callback that covers the real,
            // practical case); kept for the narrow window before any
            // grab is established, and reuses the exact same check.
            trySwitchHoverAt(fl.core.eventX());
            return 1;

        case Event.push:
            return doPulldown(null);

        case Event.shortcut:
            if (visibleR())
            {
                auto v = menu().findShortcut(null, true);
                if (v !is null && v.submenu()) return doPulldown(v);
            }
            return testShortcut() !is null;

        default:
            return 0;
        }
    }
}

unittest
{
    import fl.group : FlGroup;
    import fl.widget : Widget;
    FlGroup.current(null);

    auto bar = new MenuBar(0, 0, 300, 25);
    int fileNewCalls, quitCalls;
    bar.add("File/New", 0, (Widget w) { fileNewCalls++; });
    bar.add("Quit", 0, (Widget w) { quitCalls++; });

    // handle() bails out cleanly with no menu at all.
    auto empty = new MenuBar(0, 0, 50, 20);
    assert(empty.handle(Event.push) == 0);
    assert(bar.handle(Event.enter) == 1);

    // itemAtX() hit-testing matches draw()'s own layout: the first
    // item starts right after the 6px left margin.
    int ix, iw;
    auto hit = bar.itemAtX(bar.x() + 6 + 2, ix, iw);
    assert(hit !is null);
    assert(hit.text == "File");

    destroy(empty);
    destroy(bar);
    FlGroup.current(null);
}
