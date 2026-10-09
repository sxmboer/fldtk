/*
 * Ported from FL/Fl_Choice.H + src/Fl_Choice.cxx (FLTK 1.5.0): a
 * button showing the currently-picked menu item's text (rather than a
 * fixed label), that pops up a dropdown when clicked.
 *
 * Deviations from FLTK, all deliberate:
 *  - `draw()`'s box/divider branches are real (`fl.core.isScheme()`
 *    is real as of core-roadmap item 11 Phase A -- see that
 *    function's own doc comment) -- `Boxtype btype` picks `upBox` under
 *    any active scheme, `downBox` under "none", matching FLTK's
 *    `Fl::scheme() ? FL_UP_BOX : FL_DOWN_BOX`; the box-color
 *    contrast/lighten recolor is gated behind `!scheme()` too, matching
 *    FLTK's own `if (!Fl::scheme())` (its own comment calls this
 *    asymmetry "weird (why?)" -- ported faithfully as-is, not second-
 *    guessed); and gtk+/gleam/oxy draw a 2px divider line instead of
 *    the default scheme's up-box arrow well (every *other* named
 *    scheme -- i.e. "plastic" today -- draws neither, matching
 *    FLTK's own "else: Nothing (!)" comment in `Fl_Choice::draw()`).
 *    One remaining simplification, not yet closed: the closed choice's
 *    current-value text still always goes through the single
 *    `MenuItem.draw()` call below (used for every scheme, not just
 *    "none") rather than FLTK's separate scheme-only raw
 *    `Fl_Label`-based path -- in practice the only two differences are
 *    (a) the scheme-only path skips the checkbox/radio glyph a
 *    `menuToggle`/`menuRadio`-flagged item would otherwise draw (rare
 *    for a plain `Choice` item) and (b) a few pixels of inset, so this
 *    reads as a minor, acceptable gap rather than a visible bug -- flag
 *    it if a real checkbox-flagged `Choice` item under a scheme looks
 *    wrong.
 *  - `handle()`'s temporary `color()` override around the
 *    `pulldown()` call (FLTK: "preserve the old white-menu
 *    look-n-feel") is dropped: it exists to influence the *popup
 *    window's* background color, which FLTK's deep engine derives
 *    from the owning `Fl_Menu_`'s `color()`. `fl.menu_popup`'s
 *    simplified engine doesn't consult the caller's `color()` at all
 *    for popup background (see `fl.menu_item`'s `MenuStyle`, which has
 *    no such field) -- so the override would be genuinely inert here,
 *    not just simplified.
 *  - `fl_draw_shortcut = 2` ("hide the '&' character" hack) is real:
 *    `fl.draw`'s text primitives support shortcut-underline rendering
 *    (see that module's own row), including this exact
 *    strip-but-don't-underline mode.
 *  - `pulldown()` takes screen-absolute coordinates
 *    (`Widget.topWindowOffset()` does the conversion), matching every
 *    other Menu-family leaf widget in this port -- see
 *    `fl.menu_popup`'s own doc comment on why.
 */
module fl.choice;

import fl.menu_ : Menu_;
import fl.menu_item : MenuItem;
import fl.menu_popup;
import fl.widget : Widget;
import fl.widget_tracker : WidgetTracker;
import fl.rect : Rect;
import fl.enumerations : Event, Boxtype, Color, ArrowType, Orientation,
    Align, alignLeft, whenRelease, background2Color,
    stateShift, stateCtrl, stateAlt, stateMeta;
static import fl.core;
import fldraw = fl.draw;

class Choice : Menu_
{
    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        alignment(alignLeft);
        when(whenRelease);
        box(Boxtype.upBox);
        downBox(Boxtype.borderBox);
    }

    override void draw()
    {
        bool schemed = fl.core.scheme() !is null;
        Boxtype btype = schemed ? Boxtype.upBox : Boxtype.downBox;
        int dx = fl.core.boxDx(btype);
        int dy = fl.core.boxDy(btype);

        int H = h() - 2 * dy;
        int W = 20;
        int X = x() + w() - W - dx;
        int Y = y() + dy;

        auto ab = Rect(X, Y, W, H);
        bool active = activeR();
        Color arrowColor = active ? labelcolor() : fldraw.inactive(labelcolor());
        Color boxColor = color();

        // FLTK only applies this contrast/lighten recolor in the
        // default scheme -- its own comment calls the asymmetry "weird
        // (why?)"; ported as-is rather than second-guessed.
        if (!schemed)
        {
            if (fldraw.contrast(textcolor(), background2Color) == textcolor())
                boxColor = background2Color;
            else
                boxColor = fldraw.lighter(color());
        }

        drawBox(btype, boxColor);

        // Arrow well (default scheme), a 2px divider line (gtk+/gleam/
        // oxy), or nothing at all (any other named scheme, e.g.
        // "plastic") -- matches FLTK's own three-way table in
        // Fl_Choice::draw()'s comment.
        if (schemed)
        {
            if (fl.core.isScheme("gtk+") || fl.core.isScheme("gleam") || fl.core.isScheme("oxy"))
            {
                int x1 = x() + w() - W - 2 * dx;
                int y1 = y() + dy;
                int y2 = y() + h() - dy;

                fldraw.fl_color(fldraw.darker(color()));
                fldraw.fl_yxline(x1, y1, y2);

                fldraw.fl_color(fldraw.lighter(color()));
                fldraw.fl_yxline(x1 + 1, y1, y2);
            }
        }
        else
        {
            drawBox(Boxtype.upBox, X, Y, W, H, color());
            ab.inset(Boxtype.upBox);
        }

        fldraw.drawArrow(ab, ArrowType.arrowChoice, Orientation.orientNone, arrowColor);

        W += 2 * dx;

        if (mvalue() !is null)
        {
            MenuItem m = cast(MenuItem) *mvalue();
            if (active) m.activate(); else m.deactivate();

            int xx = x() + dx, yy = y() + dy + 1, ww = w() - W, hh = H - 2;
            fldraw.pushClip(xx, yy, ww, hh);
            // "hack value to make '&' disappear" (FLTK's own
            // comment, src/Fl_Choice.cxx) -- the closed Choice's
            // current-value display strips the '&' but doesn't
            // underline it, since no keyboard accelerator applies to
            // this non-interactive display.
            fldraw.fl_draw_shortcut = 2;
            m.draw(xx, yy, ww, hh, style(), fl.core.focus() is this ? 1 : 0);
            fldraw.fl_draw_shortcut = 0;
            fldraw.popClip();
        }

        drawLabel();
    }

    /// Gets the index of the last item chosen by the user, or -1
    /// initially.
    override int value() const { return super.value(); }

    /// Sets the currently-picked value by index into the menu array.
    /// Returns non-zero if it changed.
    override int value(int v)
    {
        if (v == -1) return value(cast(const(MenuItem)*) null);
        if (v < 0 || v >= size() - 1) return 0;
        if (!super.value(v)) return 0;
        redraw();
        return 1;
    }

    /// Sets the currently-picked value by menu item pointer. Returns
    /// non-zero if it changed.
    override int value(const(MenuItem)* v)
    {
        if (!super.value(v)) return 0;
        redraw();
        return 1;
    }

    /**
     * Shared tail for FL_PUSH/space-bar/matched-'&'-shortcut: opens
     * the dropdown, and if a leaf item was picked, applies it. Matches
     * FLTK's `J1:` label (see `fl.repeat_button`'s documented
     * goto-to-factored-function precedent).
     */
    private int doPulldown(ref WidgetTracker tracker)
    {
        handle(Event.beforeMenu);

        int xoff, yoff;
        auto topWin = topWindowOffset(xoff, yoff);
        int screenX = (topWin !is null ? topWin.x() : 0) + xoff;
        int screenY = (topWin !is null ? topWin.y() : 0) + yoff;

        // Ported from `Fl_Choice::handle()`'s FL_PUSH case: "In order to
        // preserve the old look-n-feel of 'white' menus, temporarily
        // override the color() of this widget" before calling
        // pulldown() -- FLTK mutates its own `color()` for the
        // duration of the call and restores it after; this port's
        // `MenuStyle.windowColor` (a copy, not the widget's real state)
        // makes the temporary-mutate-then-restore dance unnecessary --
        // same visible effect, no restore needed. Applied under
        // FLTK's exact condition: no active scheme (schemes draw
        // their own boxes/colors and don't want this override) and
        // `textcolor()` already contrasts fine against
        // `background2Color` (an unreadable-on-white text color would
        // make the override actively worse, not better).
        auto st = style();
        if (fl.core.scheme().length == 0
            && fldraw.contrast(st.textcolor, background2Color) == st.textcolor)
            st.windowColor = background2Color;

        auto v = fl.menu_popup.pulldown(menu(), screenX, screenY, w(), h(), mvalue(), st);
        if (tracker.deleted()) return 1;

        if (v is null || v.submenu()) return 1;
        if (v !is mvalue()) redraw();
        picked(v);
        return 1;
    }

    override int handle(Event e)
    {
        if (menu() is null || menu().text is null) return 0;
        auto tracker = WidgetTracker(this);

        switch (e)
        {
        case Event.enter:
        case Event.leave:
            return 1;

        case Event.keyDown:
            if (fl.core.eventKey() != ' '
                || (fl.core.eventState() & (stateShift | stateCtrl | stateAlt | stateMeta)))
                return 0;
            goto case Event.push;

        case Event.push:
            if (fl.core.visibleFocus()) fl.core.focus(this);
            return doPulldown(tracker);

        case Event.shortcut:
            if ((cast(Widget) this).testShortcut())
                return doPulldown(tracker);
            auto v = testShortcut();
            if (v is null) return 0;
            if (v !is mvalue()) redraw();
            picked(v);
            return 1;

        case Event.focus:
        case Event.unfocus:
            if (fl.core.visibleFocus())
            {
                redraw();
                return 1;
            }
            return 0;

        default:
            return 0;
        }
    }
}

unittest
{
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto c = new Choice(10, 10, 100, 25);
    assert(c.value() == -1);

    c.add("Zero", 0, null);
    c.add("One", 0, null);
    c.add("Two", 0, null);
    c.add("Three", 0, null);

    assert(c.value(2) == 1); // changed
    assert(c.value() == 2);
    assert(c.text() == "Two");

    assert(c.value(2) == 0); // unchanged, same value again
    assert(c.value(-1) == 1); // clears
    assert(c.value() == -1);
    assert(c.mvalue() is null);

    // Out-of-range indices (including the trailing sentinel slot) are
    // rejected.
    assert(c.value(100) == 0);
    assert(c.value(c.size() - 1) == 0); // size()-1 is the sentinel, not a real item

    // handle() bails out cleanly with no menu at all.
    auto empty = new Choice(0, 0, 50, 20);
    assert(empty.handle(Event.push) == 0);
    assert(c.handle(Event.enter) == 1);

    destroy(empty);
    destroy(c);
    FlGroup.current(null);
}
