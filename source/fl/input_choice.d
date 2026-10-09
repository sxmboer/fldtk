/*
 * Ported from FL/Fl_Input_Choice.H + src/Fl_Input_Choice.cxx (FLTK
 * 1.5.0): a FlGroup combining an Input field with a private
 * InputMenuButton -- the user can type directly, or pick from the
 * dropdown to load the input area.
 *
 * Deviations from FLTK, all deliberate:
 *  - `draw()`'s box/divider branches are real, same fix as
 *    `fl.choice`'s own `draw()` (see that module's doc comment for the
 *    full reasoning -- `fl.core.isScheme()` is real as of
 *    core-roadmap item 11 Phase A): `upBox`/`downBox` picked per
 *    `fl.core.scheme()`, the contrast/lighten recolor gated behind
 *    `!scheme()`, and a 2px divider line drawn under gtk+/gleam/oxy
 *    (FLTK's own `Fl_Input_Choice::draw()` is, per its own comment,
 *    "copied from Fl_Choice::draw() and customized" -- same bug,
 *    same fix, ported here independently rather than shared code since
 *    FLTK itself doesn't share it either).
 *  - `InputMenuButton::handle()` isn't re-declared at all: FLTK
 *    duplicates the *entire* `Fl_Menu_Button::handle()` body into
 *    `InputMenuButton` purely because `Fl_Menu_Button::popup()` is
 *    *not* `virtual` in C++ -- so `Fl_Menu_Button::handle()`'s internal
 *    `popup()` call would statically resolve to the base version even
 *    when called on an `InputMenuButton`, silently skipping the
 *    override entirely unless `handle()` itself is also overridden to
 *    call `popup()` from `InputMenuButton`'s own scope. D methods are
 *    virtual by default (no `final` on `MenuButton.popup()`), so
 *    `MenuButton.handle()`'s call to `popup()` already dispatches
 *    correctly to `InputMenuButton`'s override at runtime -- no need
 *    to duplicate `handle()`'s body at all. A genuine simplification
 *    from D's semantics, not a cut corner.
 *  - `InputMenuButton::popup()`'s "span the full composite width"
 *    positioning uses two separate `Widget.topWindowOffset()` calls
 *    (one from `this`, one from `parent()`) to build screen-absolute
 *    coordinates, instead of FLTK's window-relative
 *    `parent()->x()`/`y()`/`w()`/`h()` handed to a `pulldown()` that
 *    converts internally -- see `fl.menu_popup`'s doc comment on why
 *    its `pulldown()` takes screen-absolute coordinates directly.
 *  - `add(string)` doesn't split on `|` the way FLTK's
 *    `Fl_Menu_::add(const char*)` (the Forms-compatible multi-item-per-
 *    call overload) does -- that pipe-splitting variant isn't ported
 *    onto `fl.menu_` at all (see that module's doc comment: its own
 *    `/`-path-splitting convenience is kept, but the older Forms-era
 *    escape hatches around it are trimmed as legacy compatibility
 *    surface FLTK's own comments already call optional). `add(s)`
 *    here is a thin single-item forward instead.
 *  - `value(int)` on an out-of-range index now throws a catchable
 *    `RangeError` (D's normal bounds-checked array indexing inside
 *    `Menu_.text(int)`) instead of FLTK's silent out-of-bounds
 *    pointer read -- not a deliberate safety feature added here, just
 *    what D's array indexing already does by default; documented since
 *    it's an observable behavior difference for misuse FLTK leaves
 *    undefined.
 */
module fl.input_choice;

import fl.group : FlGroup;
import fl.widget : Widget, Callback;
import fl.widget_tracker : WidgetTracker;
import fl.input : Input;
import fl.menu_button : MenuButton;
import fl.menu_item : MenuItem;
import fl.menu_popup;
import fl.rect : Rect;
import fl.enumerations : Event, Boxtype, Color, Font, Fontsize, When,
    CallbackReason, ArrowType, Orientation, alignLeft, whenChanged,
    whenNotChanged, whenRelease, background2Color, fl_down;
static import fl.core;
import fldraw = fl.draw;

/// Ported from the private Fl_Input_Choice::InputMenuButton nested
/// class. See the module doc comment for why handle() doesn't need to
/// be re-declared here even though FLTK duplicates it.
private class InputMenuButton : MenuButton
{
    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        box(Boxtype.upBox);
    }

    override void draw()
    {
        if (box() == Boxtype.noBox) return;

        drawBox(pressedMenuButton_ is this ? fl_down(box()) : box(), color());
        if (fl.core.focus() is this)
            drawFocus(Boxtype.upBox, x(), y(), w() + 1, h(), color());

        Color arrowColor = activeR() ? labelcolor() : fldraw.inactive(labelcolor());
        fldraw.drawArrow(Rect(x(), y(), w(), h()), ArrowType.arrowChoice,
            Orientation.orientNone, arrowColor);
    }

    /// Makes the pulldown menu appear under the *entire* composite
    /// widget's width, not just this narrow button's own.
    override const(MenuItem)* popup()
    {
        handle(Event.beforeMenu);
        pressedMenuButton_ = this;
        redraw();
        auto tracker = WidgetTracker(this);

        int xoff, yoff;
        auto topWin = topWindowOffset(xoff, yoff);
        auto par = parent();
        int pxoff, pyoff;
        auto parentTopWin = par !is null ? par.topWindowOffset(pxoff, pyoff) : null;

        int screenX = parentTopWin !is null ? parentTopWin.x() + pxoff
            : (topWin !is null ? topWin.x() + xoff : 0);
        int screenY = (topWin !is null ? topWin.y() : 0) + yoff;
        int spanW = par !is null ? par.w() : w();

        auto m = fl.menu_popup.pulldown(menu(), screenX, screenY, spanW, h(), null, style());
        picked(m);
        pressedMenuButton_ = null;
        if (!tracker.deleted()) redraw();
        return m;
    }
}

class InputChoice : FlGroup
{
    private Input input_;
    private InputMenuButton menu_;

    protected int inpX() const { return x() + fl.core.boxDx(box()); }
    protected int inpY() const { return y() + fl.core.boxDy(box()); }
    protected int inpW() const { return w() - fl.core.boxDw(box()) - menuW(); }
    protected int inpH() const { return h() - fl.core.boxDh(box()); }

    protected int menuX() const { return x() + w() - menuW() - fl.core.boxDx(box()); }
    protected int menuY() const { return y() + fl.core.boxDy(box()); }
    protected int menuW() const { return 20; }
    protected int menuH() const { return h() - fl.core.boxDh(box()); }

    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        box(Boxtype.downBox);
        alignment(alignLeft);

        input_ = new Input(inpX(), inpY(), inpW(), inpH());
        input_.callback(&inpCb);
        input_.box(Boxtype.flatBox);
        input_.when(whenChanged | whenNotChanged | whenRelease);

        menu_ = new InputMenuButton(menuX(), menuY(), menuW(), menuH());
        menu_.callback(&menuCb);

        end();
    }

    override void resize(int x, int y, int w, int h)
    {
        super.resize(x, y, w, h);
        input_.resize(inpX(), inpY(), inpW(), inpH());
        menu_.resize(menuX(), menuY(), menuW(), menuH());
    }

    override void draw()
    {
        bool schemed = fl.core.scheme() !is null;
        Boxtype btype = schemed ? Boxtype.upBox : Boxtype.downBox;
        int dx = fl.core.boxDx(btype);
        int dy = fl.core.boxDy(btype);

        Color boxColor = color();
        // Same "weird (why?)" FLTK asymmetry as fl.choice's draw()
        // -- only recolor for contrast/lightening in the default scheme.
        if (!schemed)
        {
            if (fldraw.contrast(textcolor(), background2Color) == textcolor())
                boxColor = background2Color;
            else
                boxColor = fldraw.lighter(color());
        }

        drawBox(btype, boxColor);
        drawChild(menu_);

        // Vertical divider line under gtk+/gleam/oxy (matches
        // fl.choice's own arrow-well-vs-divider table); `woff` then
        // shrinks the input's own clip so it doesn't overdraw the
        // divider, matching FLTK's `woff` exactly.
        int woff = 0;
        if (fl.core.isScheme("gtk+") || fl.core.isScheme("gleam") || fl.core.isScheme("oxy"))
        {
            int x1 = menuX() - dx;
            int y1 = y() + dy;
            int y2 = y() + h() - dy;

            fldraw.fl_color(fldraw.darker(color()));
            fldraw.fl_yxline(x1, y1, y2);

            fldraw.fl_color(fldraw.lighter(color()));
            fldraw.fl_yxline(x1 + 1, y1, y2);
            woff = 2;
        }

        fldraw.pushClip(inpX(), inpY(), inpW() - woff, inpH());
        drawChild(input_);
        fldraw.popClip();

        drawLabel();
    }

    /// Adds a single item to the menu (see the module doc comment on
    /// why this doesn't split `s` on '|' the way FLTK's
    /// single-string add() does).
    void add(string s) { menu_.add(s, 0, null); }

    override bool changed() const { return input_.changed() || super.changed(); }

    override void setChanged() { input_.setChanged(); } // no need to also set the group's own
    override void clearChanged()
    {
        input_.clearChanged();
        super.clearChanged();
    }

    /// Removes all items from the menu (not the group's own children
    /// -- deliberately hides FlGroup.clear(), matching FLTK's own
    /// same-name hiding of Fl_Group::clear()).
    override void clear() { menu_.clear(); }

    Boxtype downBox() const { return menu_.downBox(); }
    void downBox(Boxtype b) { menu_.downBox(b); }

    const(MenuItem)* menu() const { return menu_.menu(); }
    void menu(MenuItem[] items) { menu_.menu(items); }

    Color textcolor() const { return input_.textcolor(); }
    void textcolor(Color c) { input_.textcolor(c); }
    Font textfont() const { return input_.textfont(); }
    void textfont(Font f) { input_.textfont(f); }
    Fontsize textsize() const { return input_.textsize(); }
    void textsize(Fontsize s) { input_.textsize(s); }

    string value() const { return input_.value(); }
    void value(string val) { input_.value(val); }

    /// Chooses item #val in the menu, and sets the input field to
    /// that value (clearing any previous text).
    void value(int val)
    {
        menu_.value(val);
        input_.value(menu_.text(val));
    }

    /// If the input field's current text matches one of the menu
    /// items, makes that item the menu's current selection too.
    /// Returns 1 if a match was found, 0 if not.
    int updateMenubutton()
    {
        foreach (i; 0 .. menu_.size())
        {
            auto item = menu_.menu()[i];
            if (item.submenu()) continue;
            auto name = menu_.text(i);
            if (name !is null && name == input_.value())
            {
                menu_.value(i);
                return 1;
            }
        }
        return 0;
    }

    MenuButton menubutton() { return menu_; }
    Input input() { return input_; }

    private void menuCb(Widget w)
    {
        auto tracker = WidgetTracker(this);
        auto item = menu_.mvalue();
        if (item !is null && item.submenu()) return; // ignore submenus

        if (input_.value() == menu_.text())
        {
            // Widget's own flag only, deliberately not input_'s too --
            // matches FLTK's explicit `Fl_Widget::clear_changed()`
            // qualification here (as opposed to the combined override
            // used below and in the "changed" branch).
            super.clearChanged();
            if (when() & whenNotChanged)
                doCallback(CallbackReason.reselected);
        }
        else
        {
            input_.value(menu_.text());
            input_.setChanged();
            super.setChanged(); // Widget's own flag, not the overridden InputChoice.setChanged()
            if (when() & (whenChanged | whenRelease))
                doCallback(CallbackReason.changed);
        }

        if (tracker.deleted()) return;

        if (callback() !is null)
        {
            super.clearChanged();
            input_.clearChanged();
        }
    }

    private void inpCb(Widget w)
    {
        auto tracker = WidgetTracker(this);
        if (input_.changed())
            super.setChanged();
        else
            super.clearChanged(); // Widget's own flag only, matching FLTK's explicit qualification

        if (fl.core.callbackReason() == CallbackReason.lostFocus)
        {
            if (when() & whenRelease)
                doCallback(CallbackReason.lostFocus);
        }
        else
        {
            if (input_.changed() && (when() & whenChanged))
                doCallback(fl.core.callbackReason());
            else if (when() & whenNotChanged)
                doCallback(fl.core.callbackReason());
        }

        if (tracker.deleted()) return;

        if (callback() !is null)
            super.clearChanged();
    }
}

unittest
{
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto ic = new InputChoice(10, 10, 150, 25);
    ic.add("Red");
    ic.add("Orange");
    ic.add("Yellow");

    assert(ic.value() == "");
    ic.value(1);
    assert(ic.value() == "Orange");
    assert(ic.menubutton().value() == 1);

    ic.value("custom text");
    assert(ic.value() == "custom text");
    assert(ic.updateMenubutton() == 0); // no matching item

    ic.value("Yellow");
    assert(ic.updateMenubutton() == 1);
    assert(ic.menubutton().value() == 2);

    ic.clear();
    assert(ic.menubutton().size() == 0);
    // clear() only touched the menu, not the group's own children.
    assert(ic.input() !is null);
    assert(ic.menubutton() !is null);

    destroy(ic);
    FlGroup.current(null);
}
