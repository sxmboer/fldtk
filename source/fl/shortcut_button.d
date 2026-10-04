/*
 * Ported from FL/Fl_Shortcut_Button.H + src/Fl_Shortcut_Button.cxx
 * (FLTK 1.5.0, ~/Repositories/fltk).
 *
 * A button that records a key combination typed by the user (click to
 * arm it, then type the shortcut; a second click or losing focus makes
 * it permanent) and draws a human-readable rendering of it via the
 * newly-ported fl.core.flShortcutLabel().
 *
 * Faithful port of the live code paths in draw()/handle()/the
 * constructor/value() (named shortcutValue() here -- see the note by
 * the private fields), with two deliberate omissions, both already
 * disabled or dead FLTK, not features this port is choosing to
 * skip:
 *
 *  - The "default shortcut" feature (default_value()/default_value()/
 *    default_clear(), the reverse-to-default button, and the fields
 *    backing them: default_set_/default_shortcut_/
 *    handle_default_button_/the FL_PUSH-area hit-testing for it) is
 *    entirely `#if 0`-disabled in FLTK itself, with the comment
 *    "Default shortcut settings are disabled until successful review
 *    of the UI". Since none of it ever runs FLTK either, none of
 *    it is ported here -- there's nothing to be faithful to yet.
 *
 *  - Fl::system_driver()->need_test_shortcut_extra() (an
 *    Alt-produces-special-characters accommodation, `1` on macOS only,
 *    `0` everywhere else including this port's X11 target) gates a
 *    whole branch inside FL_KEYBOARD handling that can never run on
 *    Linux; skipped entirely, matching the project-wide precedent of
 *    dropping macOS-only branches guarded by an always-false driver
 *    hook (e.g. fl.draw's `fl.core.isScheme()` branches).
 */
module fl.shortcut_button;

import fl.enumerations;
import fl.core;
import fl.button : Button, toggleButton;
import fldraw = fl.draw;

/// A Button subclass that captures and displays a typed key
/// combination (a "shortcut" in the fl.button.Button.shortcut() /
/// menu-item sense) rather than acting as a plain push button.
class ShortcutButton : Button
{
    private
    {
        bool hot_;
        bool preHot_;
        uint preEsc_;
        uint shortcutValue_;
    }

    // D hides every base-class overload of a name once a derived class
    // declares its own method of that name (unlike C++, which hides
    // only same-signature members) -- the same corner CLAUDE.md/
    // fl.counter's module comment documents for Fl_Counter::step().
    // shortcutValue()/shortcutValue(uint) (below) sidestep it by not
    // reusing the name `value` at all, matching FLTK's own
    // `Fl_Shortcut_Button::value()`/`value(Fl_Shortcut)` in spirit but
    // avoiding a same-name/no-arg-different-return-type clash with
    // Button.value() that D can't express as an overload (D can't
    // overload on return type alone, unlike the double-vs-int case
    // fl.counter hit, which differed in parameter list).

    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        box(Boxtype.downBox);
        selectionColor(fl.enumerations.selectionColor);
        type(toggleButton);
    }

    /// Sets the displayed shortcut. Named shortcutValue() rather than
    /// FLTK's value(Fl_Shortcut) -- see the note above the private
    /// fields for why the name `value` itself can't be reused here.
    void shortcutValue(uint shortcut)
    {
        shortcutValue_ = shortcut;
        clearChanged();
        redraw();
    }

    /// Returns the user-selected shortcut.
    uint shortcutValue() const { return shortcutValue_; }

    override void draw()
    {
        Color col = hot_ ? selectionColor() : color();
        Boxtype b = box();
        if (hot_)
        {
            if (downBox() != Boxtype.noBox)
                b = downBox();
            else if (b > Boxtype.flatBox && b < Boxtype.borderBox)
                b = cast(Boxtype)(cast(int) b ^ 1);
        }
        drawBox(b, col);
        drawBackdrop();

        int X = x() + fl.core.boxDx(box());
        int Y = y() + fl.core.boxDy(box());
        int W = w() - fl.core.boxDw(box());
        int H = h() - fl.core.boxDh(box());
        Color textcol = fldraw.contrast(labelcolor(), col);
        if (!activeR())
            textcol = fldraw.inactive(textcol);
        fldraw.fl_color(textcol);
        fldraw.fl_font(labelfont(), labelsize());
        string text = label();
        if (shortcutValue_)
            text = fl.core.flShortcutLabel(shortcutValue_);
        fldraw.fl_draw(text, X, Y, W, H, alignment() | alignInside);
        if (fl.core.focus() is this) drawFocus();
    }

    override int handle(Event event)
    {
        switch (event)
        {
        case Event.push:
            if (fl.core.visibleFocus() && handle(Event.focus)) fl.core.focus(this);
            preHot_ = hot_;
            goto case Event.release;
        case Event.drag:
        case Event.release:
            hot_ = fl.core.eventInside(this) ? !preHot_ : preHot_;
            if (event == Event.release && preHot_ && !hot_)
                doEndHotCallback();
            redraw();
            return 1;

        case Event.unfocus:
            if (hot_) doEndHotCallback();
            hot_ = false;
            goto case Event.focus;
        case Event.focus:
            redraw();
            return 1;

        case Event.keyDown:
            if (hot_)
            {
                import std.utf : decode;

                dchar v = 0;
                if (fl.core.eventText().length > 0)
                {
                    size_t idx = 0;
                    v = decode(fl.core.eventText(), idx);
                }

                uint sv;
                if ((v > 32 && v < 0x7f) || (v > 0xa0 && v <= 0xff))
                {
                    import std.ascii : isUpper, toLower;

                    uint vv = cast(uint) v;
                    if (vv < 128 && isUpper(cast(char) vv))
                    {
                        vv = toLower(cast(char) vv);
                        vv |= stateShift;
                    }
                    sv = vv | (fl.core.eventState() & (stateMeta | stateAlt | stateCtrl));
                }
                else
                {
                    sv = (fl.core.eventState() & (stateMeta | stateAlt | stateCtrl | stateShift))
                        | cast(uint) fl.core.eventKey();
                    if (sv == escape)
                    {
                        if (shortcutValue_ == escape)
                        {
                            sv = preEsc_;
                            doEndHotCallback();
                            hot_ = false;
                        }
                        else
                        {
                            preEsc_ = shortcutValue_;
                        }
                    }
                    if (sv == backSpace && shortcutValue_) sv = 0;
                }

                if (sv != shortcutValue_)
                {
                    shortcutValue_ = sv;
                    setChanged();
                    redraw();
                    if (when() & whenChanged) doCallback(CallbackReason.changed);
                    clearChanged();
                }
                return 1;
            }
            else if (fl.core.eventKey() == enter || fl.core.eventText() == " ")
            {
                hot_ = true;
                redraw();
                return 1;
            }
            break;

        case Event.shortcut:
            if (hot_) return 1;
            break;

        default:
            break;
        }
        return super.handle(event);
    }

    private void doEndHotCallback()
    {
        if (when() & whenRelease) doCallback(CallbackReason.released);
    }
}

unittest
{
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto b = new ShortcutButton(0, 0, 100, 20);
    assert(b.box() == Boxtype.downBox);
    assert(b.type() == toggleButton);
    assert(b.shortcutValue() == 0);

    b.shortcutValue(stateCtrl | 'a');
    assert(b.shortcutValue() == (stateCtrl | 'a'));

    fl.core.resetForTest();
}

unittest
{
    // Clicking arms ("hot") the button; typing a plain key while hot
    // records it as the new shortcut and (with FL_WHEN_CHANGED set --
    // the widget default is FL_WHEN_RELEASE only) fires the callback.
    import fl.group : FlGroup;
    FlGroup.current(null);
    fl.core.focus(null);

    auto b = new ShortcutButton(0, 0, 100, 20);
    b.when(whenChanged);
    bool called;
    b.callback((w) { called = true; });

    fl.core.eX_ = 10;
    fl.core.eY_ = 10;
    assert(b.handle(Event.push) == 1);
    assert(b.handle(Event.release) == 1); // still inside -> stays hot

    fl.core.eText_ = "a";
    fl.core.eState_ = 0;
    assert(b.handle(Event.keyDown) == 1);
    assert(called);
    assert(b.shortcutValue() == 'a');

    fl.core.eX_ = 0;
    fl.core.eY_ = 0;
    fl.core.eText_ = "";
    fl.core.focus(null);
    fl.core.resetForTest();
}

unittest
{
    // Backspace clears an existing shortcut back to 0, but only once
    // the button is "hot" (armed via a prior click, or here via
    // Enter -- FLTK's keyboard-only activation path).
    import fl.group : FlGroup;
    FlGroup.current(null);
    fl.core.focus(null);

    auto b = new ShortcutButton(0, 0, 100, 20);
    b.shortcutValue('a');

    fl.core.eKeysym_ = enter;
    fl.core.eText_ = "";
    assert(b.handle(Event.keyDown) == 1); // arms it (not-hot Enter branch)

    fl.core.eKeysym_ = backSpace;
    fl.core.eState_ = 0;
    assert(b.handle(Event.keyDown) == 1);
    assert(b.shortcutValue() == 0);

    fl.core.eKeysym_ = 0;
    fl.core.focus(null);
    fl.core.resetForTest();
}
