/*
 * Ported from FL/Fl_Menu_Button.H + src/Fl_Menu_Button.cxx (FLTK
 * 1.5.0): a button that pops up a menu (or, with type() set, a
 * standalone popup-anywhere menu) built from fl.menu_'s array.
 *
 * Deviations from FLTK, all deliberate:
 *  - `menu_end()` isn't called before popping up the menu: it exists
 *    FLTK purely to finalize the `local_array`/copy-on-write
 *    staging area into private storage before the menu opens (see
 *    fl.menu_'s module doc comment for why none of that machinery
 *    exists at all in this port -- `MenuItem[]` is always already the
 *    widget's own real, GC-owned array).
 *  - `popup()` positions the menu via `Widget.topWindowOffset()` (this
 *    port's already-ported screen-position helper) instead of
 *    FLTK's `Fl_Menu_Item::popup()`/`pulldown()` converting a
 *    window-relative position internally using this widget's own
 *    window chain -- see fl.menu_popup's doc comment: its `pulldown()`/
 *    `popup()` take screen-absolute coordinates directly as a
 *    deliberate API simplification, and this is the conversion that
 *    simplification pushes onto each caller.
 *  - `Fl_Window_Driver::current_menu_button` isn't ported: it's
 *    driver-internal plumbing (cursor/positioning hints for a
 *    `Fl_Window_Driver` this port doesn't have, see fl.platform_x11's
 *    "concrete module, not a driver hierarchy" precedent) that nothing
 *    else in this port reads.
 *  - `Fl_Widget_Tracker`'s "was `this` deleted while the popup's nested
 *    loop ran" guard is ported via `fl.widget_tracker.WidgetTracker`,
 *    matching every other STR #3503-style guard elsewhere in this
 *    port.
 *  - `handle()`'s `FL_SHORTCUT` case needs both `Fl_Widget::test_shortcut()`
 *    (does the button's own label have a matching '&x'?) and
 *    `Menu_::test_shortcut()` (does any menu item?) -- since both are
 *    zero-argument methods with different return types, D can't
 *    overload between them the way C++ can rely on `Fl_Menu_::test_shortcut()`
 *    simply hiding the base one (same name-hiding rule in both
 *    languages, see fl.menu_'s own doc comment on its `alias
 *    testShortcut = Widget.testShortcut;`). Reaching the hidden base
 *    version explicitly needs an upcast (`(cast(Widget) this).testShortcut()`),
 *    the direct D equivalent of FLTK's explicit
 *    `Fl_Widget::test_shortcut()` qualification.
 */
module fl.menu_button;

import fl.menu_ : Menu_;
import fl.menu_item : MenuItem;
import fl.menu_popup;
import fl.widget : Widget;
import fl.widget_tracker : WidgetTracker;
import fl.rect : Rect;
import fl.enumerations : Event, Boxtype, Color, ArrowType, Orientation,
    stateShift, stateCtrl, stateAlt, stateMeta, fl_down;
import fldraw = fl.draw;
static import fl.core;

class MenuButton : Menu_
{
    /// Mouse-button bits for type() -- which button(s) pop up the
    /// menu when this is a standalone popup-anywhere menu (box() ==
    /// noBox or type() != 0).
    enum PopupButtons : ubyte
    {
        popup1   = 1,
        popup2   = 2,
        popup12  = 3,
        popup3   = 4,
        popup13  = 5,
        popup23  = 6,
        popup123 = 7,
    }

    /// Shared across every MenuButton, matching FLTK's static
    /// member -- only one button's dropdown can be open at a time, so
    /// draw() can tell whether *this* instance is the one currently
    /// showing its pressed/down appearance. `protected`, not
    /// `private`, matching FLTK's own visibility exactly: D's
    /// `private` is per-module, not per-class-hierarchy like C++'s
    /// `protected`, and `fl.input_choice`'s `InputMenuButton`
    /// subclasses this from a different module specifically to read
    /// this same field in its own `draw()` override.
    protected static MenuButton pressedMenuButton_;

    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        downBox(Boxtype.noBox);
    }

    override void draw()
    {
        if (box() == Boxtype.noBox || type() != 0) return;

        int ah = h() - fl.core.boxDh(box());
        int aw = ah > 20 ? 20 : ah;
        int ax = x() + w() - fl.core.boxDx(box()) - aw;
        int ay = y() + (h() - ah) / 2;

        drawBox(pressedMenuButton_ is this ? fl_down(box()) : box(), color());
        drawLabel(x() + fl.core.boxDx(box()), y(), w() - fl.core.boxDw(box()) - aw, h());
        if (fl.core.focus() is this) drawFocus();

        Color arrowColor = activeR() ? labelcolor() : fldraw.inactive(labelcolor());
        fldraw.drawArrow(Rect(ax, ay, aw, ah), ArrowType.arrowSingle, Orientation.orientDown, arrowColor);
    }

    /**
     * Acts exactly as though the user clicked the button or typed its
     * shortcut key: shows the menu, waits for a pick, and if one is
     * made, sets value() and fires the callback (or sets changed()).
     * Returns the picked item, or null if the menu was dismissed.
     */
    const(MenuItem)* popup()
    {
        handle(Event.beforeMenu);
        pressedMenuButton_ = this;
        redraw();
        auto tracker = WidgetTracker(this);

        const(MenuItem)* m;
        if (box() == Boxtype.noBox || type() != 0)
        {
            // Ported from Fl_Menu_Button::popup(): "m = menu()->popup(
            // Fl::event_x(), Fl::event_y(), label(), mvalue(), this);",
            // including the title strip (`label()`, e.g.
            // test/menubar.cxx's own "&popup"-labelled full-window
            // right-click button).
            m = fl.menu_popup.popup(menu(), fl.core.eventXRoot(), fl.core.eventYRoot(),
                mvalue(), style(), label());
        }
        else
        {
            int xoff, yoff;
            auto topWin = topWindowOffset(xoff, yoff);
            int screenX = (topWin !is null ? topWin.x() : 0) + xoff;
            int screenY = (topWin !is null ? topWin.y() : 0) + yoff;
            m = fl.menu_popup.pulldown(menu(), screenX, screenY, w(), h(), null, style());
        }
        picked(m);
        pressedMenuButton_ = null;
        if (!tracker.deleted()) redraw();
        return m;
    }

    override int handle(Event e)
    {
        if (menu() is null || menu().text is null) return 0;

        switch (e)
        {
        case Event.enter:
        case Event.leave:
            return (box() != Boxtype.noBox && type() == 0) ? 1 : 0;

        case Event.push:
            if (box() == Boxtype.noBox)
            {
                if (fl.core.eventButton() != 3) return 0;
            }
            else if (type() != 0)
            {
                if (!(type() & (1 << (fl.core.eventButton() - 1)))) return 0;
            }
            if (fl.core.visibleFocus()) fl.core.focus(this);
            popup();
            return 1;

        case Event.keyDown:
            if (box() == Boxtype.noBox) return 0;
            if (fl.core.eventKey() == ' '
                && !(fl.core.eventState() & (stateShift | stateCtrl | stateAlt | stateMeta)))
            {
                popup();
                return 1;
            }
            return 0;

        case Event.shortcut:
            if ((cast(Widget) this).testShortcut()) { popup(); return 1; }
            return testShortcut() !is null;

        case Event.focus:
        case Event.unfocus:
            if (box() != Boxtype.noBox && fl.core.visibleFocus())
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

    auto b = new MenuButton(10, 10, 100, 25, "Menu");
    int calls;
    b.add("Alpha", 0, (Widget w) { calls++; });
    b.add("Beta", 0, (Widget w) { calls++; });

    // handle() bails out cleanly with no menu at all.
    auto empty = new MenuButton(0, 0, 50, 20);
    assert(empty.handle(Event.push) == 0);

    // FL_ENTER/FL_LEAVE are only "handled" for a real button, not a
    // standalone popup-anywhere menu.
    assert(b.handle(Event.enter) == 1);
    b.type(MenuButton.PopupButtons.popup3);
    assert(b.handle(Event.enter) == 0);
    b.type(0);

    destroy(empty);
    destroy(b);
    FlGroup.current(null);
}
