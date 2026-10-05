/*
 * Ported from FL/Fl_Button.H + src/Fl_Button.cxx (FLTK 1.5.0).
 *
 * Faithful port of value()/setonly()/shortcut()/downBox()/compact() and
 * the handle()/draw() logic, except:
 *
 *  - draw(): a complete, faithful port now, including compact() mode's
 *    own drawing branch (box drawn across the parent's bounds, clipped
 *    back to this button's own area via fl.draw's real pushClip()/
 *    popClip(), plus the divider line via fl_yxline()/fl_xyline()).
 *
 *  - simulateKeyAction()/keyReleaseTimeout(): a faithful, complete
 *    port -- flashes the button (value(true), then 0.15s later via
 *    fl.core.addTimeout(), back to value(false)) when triggered by
 *    keyboard/shortcut. `key_release_tracker` (FLTK: a process-wide
 *    `static Fl_Widget_Tracker*`, tracking which button has a pending
 *    revert so a second keyboard-triggered button doesn't leave the
 *    first one's flash dangling) becomes the module-level
 *    `pendingKeyRelease_` below, a plain `Button` reference rather than
 *    a `Fl_Widget_Tracker*`. That substitution alone isn't enough,
 *    though: it doesn't cover *this* button being destroyed while its
 *    own timer is still pending, which is exactly what happens when a
 *    dialog's Enter-triggered OK button (`fl.return_button.ReturnButton`)
 *    closes its own dialog. A `~this()` destructor cancels the pending
 *    timeout outright to cover that case, rather than FLTK's
 *    null-check approach (a plain delegate can't null-check itself
 *    after the fact the way a tracker's `widget()` accessor can) -- see
 *    that destructor's own doc comment for the full mechanism.
 *
 *  - handle()'s FL_RELEASE case and triggeredByKeyboard() now use a
 *    real `fl.widget_tracker.WidgetTracker` (see that module) to guard
 *    the two-callbacks-in-a-row sequences (CHANGED then RELEASED) --
 *    if the CHANGED callback destroys this button (e.g. it closes its
 *    own window), the RELEASED callback is skipped instead of touching
 *    a dead widget, matching FLTK's `Fl_Widget_Tracker wp(this);
 *    do_callback(...); if (wp.deleted()) return 1;` guards exactly.
 *
 *  - handle()'s FLTK `goto triggered_by_keyboard` (jumping from the
 *    FL_SHORTCUT case into shared logic inside the FL_KEYBOARD case) is
 *    factored into a private triggeredByKeyboard() method instead --
 *    same behavior, without a cross-case goto.
 *
 * Fully ported: Fl::test_shortcut(shortcut())/Widget.testShortcut()
 * (fl.core's testShortcut()/fl.widget's testShortcut()), used by
 * handle()'s FL_SHORTCUT case exactly as FLTK does.
 */
module fl.button;

import fl.enumerations;
import fl.widget : Widget;
import fl.widget_tracker : WidgetTracker;
import fl.group : FlGroup;
import fl.core;
import fldraw = fl.draw;

/// Values for type(); mirrors Fl_Button.H's #defines (FL_RADIO_BUTTON
/// is FL_RESERVED_TYPE(100) + 2, kept as the same literal here).
enum ubyte normalButton = 0;
enum ubyte toggleButton = 1;
enum ubyte radioButton = 102;
enum ubyte hiddenButton = 3;

class Button : Widget
{
    private
    {
        int shortcut_;
        bool value_;
        bool oldval_;
        Boxtype downBox_;
        bool compact_;
    }

    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        box(Boxtype.upBox);
        shortcutLabel(true);
    }

    /**
     * Cancels this button's pending keyReleaseTimeout() (if any) so it
     * can never fire on a destroyed widget. This is load-bearing, not a
     * defensive addition: `pendingKeyRelease_` is a plain `Button`
     * reference rather than FLTK's real `Fl_Widget_Tracker` (see
     * that global's own doc comment for why that substitution was
     * made), but a bare reference alone only guards the "a second
     * keyboard-triggered button interrupts the first one's still-
     * pending flash" case -- it does nothing about *this* button being
     * destroyed while its own timer is still pending, which is exactly
     * what happens when a dialog's keyboard-triggered OK button (e.g.
     * `fl.return_button.ReturnButton`, Enter-triggered) closes its own
     * dialog: `simulateKeyAction()` schedules `&keyReleaseTimeout` 0.15s
     * out, the callback fires and closes the window practically
     * immediately, and the whole dialog (including this button) gets
     * `destroy()`d well before that 0.15s elapses. Without this
     * destructor, the stale timer later invokes `keyReleaseTimeout()`
     * on the by-then-destroyed button, e.g. when closing `fl.ask`'s
     * dialogs via Enter (FLTK's own equivalent,
     * `Fl_Button::key_release_timeout()`, avoids this by checking
     * `Fl_Widget_Tracker::widget()` for null before touching the
     * button -- this port instead cancels the timer outright at
     * destruction time, which a plain instance-method delegate can do
     * but a null check inside the method itself cannot, since by the
     * time the delegate is invoked D has already dispatched into the
     * (by-then-zeroed) object).
     *
     * Safe unconditionally, including during GC-driven finalization
     * (see CONVENTIONS.md's GC-finalizer-hazard note and `Widget.~this()`'s
     * own `clearWidgetPointer(this)` call for the established
     * precedent): `fl.core.removeTimeout()` and `pendingKeyRelease_`
     * both only touch this module's/`fl.core`'s own module-level
     * static state, never another GC-managed object, so finalization
     * order relative to other objects doesn't matter here.
     */
    ~this()
    {
        if (pendingKeyRelease_ is this)
        {
            fl.core.removeTimeout(&keyReleaseTimeout);
            pendingKeyRelease_ = null;
        }
    }

    override void draw()
    {
        if (type() == hiddenButton) return;

        Color col = value_ ? selectionColor() : color();
        Boxtype bt = value_ ? (downBox_ != Boxtype.noBox ? downBox_ : fl_down(box())) : box();

        if (compact_ && parent() !is null)
        {
            // Draws the box across the *parent's* full bounds (clipped
            // back to this button's own area), so adjacent compact
            // buttons in the same group appear to share one continuous
            // border -- then a short divider line on whichever edge(s)
            // don't reach the parent's own edge, signalling where this
            // button ends and the next one begins.
            auto p = parent();
            int px, py;
            int pw = p.w(), ph = p.h();
            if (p.asWindow() !is null) { px = 0; py = 0; }
            else { px = p.x(); py = p.y(); }

            fldraw.pushClip(x(), y(), w(), h());
            drawBox(bt, px, py, pw, ph, col);
            fldraw.popClip();

            enum hh = 5, ww = 5;
            Color dividerColor = fl_gray_ramp(numGray / 3);
            if (!activeR()) dividerColor = fldraw.inactive(dividerColor);
            if (x() + w() != px + pw)
            {
                fldraw.fl_color(dividerColor);
                fldraw.fl_yxline(x() + w() - 1, y() + hh, y() + h() - 1 - hh);
            }
            if (y() + h() != py + ph)
            {
                fldraw.fl_color(dividerColor);
                fldraw.fl_xyline(x() + ww, y() + h() - 1, x() + w() - 1 - ww);
            }
        }
        else
        {
            drawBox(bt, col);
        }
        drawBackdrop();

        if (labeltype() == Labeltype.normalLabel && value_)
        {
            // Recolor the label for readability against col (the
            // button's own "down"/selected background), then restore
            // it -- FLTK's own save/restore-around-draw_label()
            // idiom, now that contrast() is real.
            Color c = labelcolor();
            labelcolor(fldraw.contrast(c, col));
            drawLabel();
            labelcolor(c);
        }
        else
        {
            drawLabel();
        }

        if (fl.core.focus() is this) drawFocus();
    }

    override int handle(Event event)
    {
        switch (event)
        {
        case Event.enter:
        case Event.leave:
            return 1;

        case Event.push:
            if (fl.core.visibleFocus() && handle(Event.focus)) fl.core.focus(this);
            goto case Event.drag;
        case Event.drag:
        {
            bool newval;
            if (fl.core.eventInside(this))
                newval = (type() == radioButton) ? true : !oldval_;
            else
            {
                clearChanged();
                newval = oldval_;
            }
            if (newval != value_)
            {
                value_ = newval;
                setChanged();
                if (box() != Boxtype.noBox && fl_box(box()) == box()) redraw();
                else redrawLabel();
                if (when() & whenChanged) doCallback(CallbackReason.changed);
            }
            return 1;
        }

        case Event.release:
            if (value_ == oldval_)
            {
                if (when() & whenNotChanged) doCallback(CallbackReason.selected);
                return 1;
            }
            if (type() == radioButton)
            {
                setonly();
                setChanged();
            }
            else if (type() == toggleButton)
            {
                oldval_ = value_;
                setChanged();
            }
            else
            {
                value(oldval_);
                setChanged();
                if (when() & whenChanged)
                {
                    auto wp = WidgetTracker(this);
                    doCallback(CallbackReason.changed);
                    if (wp.deleted()) return 1;
                }
            }
            if (when() & whenRelease) doCallback(CallbackReason.released);
            return 1;

        case Event.shortcut:
            if (!(shortcut_ != 0 ? fl.core.testShortcut(shortcut_) : testShortcut()))
                return 0;
            if (fl.core.visibleFocus() && handle(Event.focus)) fl.core.focus(this);
            return triggeredByKeyboard();

        case Event.focus:
        case Event.unfocus:
            if (fl.core.visibleFocus())
            {
                if (!fl.core.boxBg(box()))
                {
                    // Widgets with boxtypes that don't draw the background
                    // need a parent to redraw, since it is responsible for
                    // drawing the background.
                    auto win = window();
                    if (win !is null)
                    {
                        int X = x() > 0 ? x() - 1 : 0;
                        int Y = y() > 0 ? y() - 1 : 0;
                        win.damage(damageAll, X, Y, w() + 2, h() + 2);
                    }
                }
                else
                {
                    if (box() != Boxtype.noBox && fl_box(box()) == box()) redraw();
                    else redrawLabel();
                }
                return 1;
            }
            return 0;

        case Event.keyDown:
            if (fl.core.focus() is this && fl.core.eventKey() == ' '
                && !fl.core.eventState(stateShift | stateCtrl | stateAlt | stateMeta))
            {
                return triggeredByKeyboard();
            }
            return 0;

        default:
            return 0;
        }
    }

    /// Sets the current value (on/off) of the button. Returns true if
    /// the value actually changed.
    bool value(bool v)
    {
        oldval_ = v;
        clearChanged();
        if (value_ != v)
        {
            value_ = v;
            if (box() != Boxtype.noBox) redraw();
            else redrawLabel();
            return true;
        }
        return false;
    }

    bool value() const { return value_; }

    /// Same as value(true).
    bool set() { return value(true); }
    /// Same as value(false).
    bool clear() { return value(false); }

    /// Turns this radio button on and turns off every other sibling
    /// widget with type() == radioButton. Should only be called on
    /// radioButton-typed buttons.
    void setonly()
    {
        value(true);
        // Cast always safe in normal use: a widget's parent is always
        // a real FlGroup or null (see Widget.parent()'s own doc comment
        // -- only an exotic composed-child relationship, which a
        // Button would never be, has a non-FlGroup parent).
        FlGroup g = cast(FlGroup) parent;
        if (g is null) return;
        foreach (o; g.array())
        {
            auto b = cast(Button) o;
            if (b !is null && b !is this && b.type() == radioButton)
                b.value(false);
        }
    }

    int shortcut() const { return shortcut_; }
    void shortcut(int s) { shortcut_ = s; }

    Boxtype downBox() const { return downBox_; }
    void downBox(Boxtype b) { downBox_ = b; }

    /// (for backwards compatibility)
    Color downColor() const { return selectionColor(); }
    /// ditto
    void downColor(Color c) { selectionColor(c); }

    void compact(bool v) { compact_ = v; }
    bool compact() const { return compact_; }

    private int triggeredByKeyboard()
    {
        if (type() == radioButton)
        {
            if (!value_)
            {
                setonly();
                setChanged();
                if (when() & whenChanged) doCallback(CallbackReason.changed);
                else if (when() & whenRelease) doCallback(CallbackReason.released);
            }
            else
            {
                if (when() & whenNotChanged) doCallback(CallbackReason.selected);
            }
        }
        else if (type() == toggleButton)
        {
            value(!value());
            setChanged();
            if (when() & whenChanged) doCallback(CallbackReason.changed);
            else if (when() & whenRelease) doCallback(CallbackReason.released);
        }
        else
        {
            simulateKeyAction();
            if (when() & whenChanged)
            {
                setChanged();
                auto wp = WidgetTracker(this);
                doCallback(CallbackReason.changed);
                if (wp.deleted()) return 1;
                setChanged();
                doCallback(CallbackReason.released);
            }
            else if (when() & whenRelease)
            {
                setChanged();
                doCallback(CallbackReason.released);
            }
        }
        return 1;
    }

    /// Ported from Fl_Button::simulate_key_action(). Flashes value()
    /// on, then schedules keyReleaseTimeout() to flash it back off
    /// 0.15s later. See the module comment for pendingKeyRelease_'s
    /// role (FLTK's key_release_tracker).
    protected void simulateKeyAction()
    {
        if (pendingKeyRelease_ !is null)
        {
            auto prev = pendingKeyRelease_;
            fl.core.removeTimeout(&prev.keyReleaseTimeout);
            prev.keyReleaseTimeout();
        }
        value(true);
        redraw();
        pendingKeyRelease_ = this;
        fl.core.addTimeout(0.15, &keyReleaseTimeout);
    }

    /// Ported from Fl_Button::key_release_timeout(). See
    /// simulateKeyAction()'s doc comment.
    private void keyReleaseTimeout()
    {
        if (pendingKeyRelease_ is this)
            pendingKeyRelease_ = null;
        value(false);
        redraw();
    }
}

/// See simulateKeyAction()'s doc comment: which Button (if any)
/// currently has a pending keyReleaseTimeout() -- genuinely shared
/// process-wide, matching FLTK's own `static
/// Fl_Widget_Tracker *key_release_tracker`.
private Button pendingKeyRelease_;

unittest
{
    import fl.group : FlGroup;

    FlGroup.current(null);

    auto b = new Button(0, 0, 80, 20, "&Go");
    assert(b.box == Boxtype.upBox);
    assert(!b.value());
    assert(b.shortcutLabel());

    assert(b.set());       // value was false -> changes, returns true
    assert(b.value());
    assert(!b.set());      // already true -> no change, returns false
    assert(b.clear());
    assert(!b.value());

    FlGroup.current(null);
}

unittest
{
    // FL_PUSH/FL_DRAG inside the button flips value(); releasing while
    // changed fires the callback with FL_REASON_RELEASED (the default
    // when() is whenRelease).
    import fl.group : FlGroup;

    FlGroup.current(null);
    fl.core.focus(null);

    auto b = new Button(0, 0, 20, 20);
    CallbackReason seenReason;
    bool called;
    b.callback((w) { called = true; });

    fl.core.eX_ = 10;
    fl.core.eY_ = 10;
    assert(b.handle(Event.push) == 1);
    assert(b.value());

    assert(b.handle(Event.release) == 1);
    assert(called);

    fl.core.eX_ = 0;
    fl.core.eY_ = 0;
    fl.core.focus(null);
    FlGroup.current(null);
}

unittest
{
    // setonly() turns off every other radioButton-typed sibling.
    import fl.group : FlGroup;

    FlGroup.current(null);

    auto g = new FlGroup(0, 0, 100, 100);
    auto a = new Button(0, 0, 10, 10);
    auto b = new Button(20, 0, 10, 10);
    auto c = new Button(40, 0, 10, 10);
    a.type(radioButton);
    b.type(radioButton);
    c.type(radioButton);
    g.add(a);
    g.add(b);
    g.add(c);
    FlGroup.current(null);

    a.set();
    b.setonly();
    assert(!a.value());
    assert(b.value());
    assert(!c.value());

    FlGroup.current(null);
}

unittest
{
    // FL_SHORTCUT: an explicit shortcut() value takes priority over the
    // label's '&x' shortcut.
    import fl.group : FlGroup;

    FlGroup.current(null);
    fl.core.focus(null);

    auto b = new Button(0, 0, 20, 20, "&Ignored");
    b.shortcut('z');
    bool called;
    b.callback((w) { called = true; });

    fl.core.eKeysym_ = 'z';
    fl.core.eState_ = 0;
    assert(b.handle(Event.shortcut) == 1);
    assert(called);

    fl.core.eKeysym_ = 0;
    fl.core.focus(null);
    FlGroup.current(null);
}

unittest
{
    // simulateKeyAction(): pressing Space while focused flashes value()
    // on, then a real timer flips it back off ~0.15s later.
    import fl.group : FlGroup;
    import core.thread : Thread;
    import core.time : msecs;

    FlGroup.current(null);
    fl.core.resetForTest();
    pendingKeyRelease_ = null;

    auto b = new Button(0, 0, 20, 20);
    fl.core.focus(b);
    fl.core.eKeysym_ = ' ';
    fl.core.eState_ = 0;

    assert(b.handle(Event.keyDown) == 1);
    assert(b.value()); // flashed on immediately

    fl.core.processTimeouts();
    assert(b.value()); // not due yet

    Thread.sleep(200.msecs);
    fl.core.processTimeouts();
    assert(!b.value()); // reverted by the real timer

    fl.core.eKeysym_ = 0;
    fl.core.focus(null);
    pendingKeyRelease_ = null;
    FlGroup.current(null);
    fl.core.resetForTest();
}

unittest
{
    // simulateKeyAction() on a second button while the first's revert
    // is still pending applies that revert immediately, rather than
    // leaving it dangling -- matches FLTK's key_release_tracker
    // behavior (see the module comment).
    import fl.group : FlGroup;

    FlGroup.current(null);
    fl.core.resetForTest();
    pendingKeyRelease_ = null;

    auto a = new Button(0, 0, 20, 20);
    auto b = new Button(30, 0, 20, 20);

    a.simulateKeyAction();
    assert(a.value());
    assert(pendingKeyRelease_ is a);

    b.simulateKeyAction();
    assert(!a.value()); // a's pending revert was applied immediately
    assert(b.value());
    assert(pendingKeyRelease_ is b);

    pendingKeyRelease_ = null;
    FlGroup.current(null);
    fl.core.resetForTest();
}

unittest
{
    // Regression test for a real, reported segfault (see Button's own
    // ~this() doc comment): a keyboard-triggered button destroyed
    // while its keyReleaseTimeout() is still pending used to leave
    // that timer dangling, later firing on the by-then-destroyed
    // widget. Confirms destroy() cancels the pending timeout and
    // clears pendingKeyRelease_ instead of leaving either dangling.
    import fl.group : FlGroup;

    FlGroup.current(null);
    fl.core.resetForTest();
    pendingKeyRelease_ = null;

    auto b = new Button(0, 0, 80, 20, "OK");
    b.simulateKeyAction();
    assert(pendingKeyRelease_ is b);
    assert(fl.core.hasTimeout(&b.keyReleaseTimeout));

    destroy(b);
    assert(pendingKeyRelease_ is null);
    assert(!fl.core.hasTimeout(&b.keyReleaseTimeout));

    FlGroup.current(null);
    fl.core.resetForTest();
}

unittest
{
    // WidgetTracker guard: a CHANGED callback that destroys this very
    // button must not crash handle() when it tries to fire RELEASED
    // afterward -- and must not fire it at all, matching FLTK's
    // `if (wp.deleted()) return 1;`.
    //
    // Sets value_/oldval_ directly (rather than going through
    // handle(Event.push)) so the CHANGED callback fires exactly once,
    // from inside handle(Event.release)'s own guarded branch -- driving
    // it through a real FL_PUSH first would fire CHANGED (and thus
    // destroy the button) a step early, which is a test-setup bug, not
    // anything the guard itself needs to handle: nothing protects a
    // *caller* that keeps invoking methods on a reference it already
    // knows was destroyed.
    import fl.group : FlGroup;

    FlGroup.current(null);
    fl.core.resetForTest();

    auto b = new Button(0, 0, 20, 20);
    b.value_ = true;
    b.oldval_ = false; // differs from value_, so release won't early-return
    b.when(whenChanged | whenRelease);
    bool releasedFired;
    b.callback((w) {
        releasedFired = (fl.core.callbackReason() == CallbackReason.released);
        destroy(b);
    });

    // Should not crash even though the callback destroys `b` mid-release.
    assert(b.handle(Event.release) == 1);
    assert(!releasedFired); // RELEASED never fired: CHANGED's callback deleted b first

    FlGroup.current(null);
    fl.core.resetForTest();
}

unittest
{
    // draw()'s compact() branch: headless (no display -> fl.draw's
    // primitives early-return safely), just confirms the parent-bounds/
    // clip/divider-line arithmetic runs without crashing, for both a
    // plain FlGroup parent and a Window parent (the asWindow() !is null
    // branch, which uses (0,0) instead of the parent's own x()/y()).
    import fl.group : FlGroup;
    import fl.window : Window;

    FlGroup.current(null);

    auto g = new FlGroup(0, 0, 100, 40);
    auto b1 = new Button(0, 0, 50, 40, "A");
    b1.compact(true);
    auto b2 = new Button(50, 0, 50, 40, "B");
    b2.compact(true);
    g.end();
    g.draw();
    destroy(g);

    FlGroup.current(null);

    auto win = new Window(0, 0, 100, 40);
    auto b3 = new Button(0, 0, 50, 40, "C");
    b3.compact(true);
    win.end();
    win.draw();
    destroy(win);

    FlGroup.current(null);
}

unittest
{
    // Event.focus/Event.unfocus: a button whose boxtype has no solid
    // background (fl.core.boxBg() false, e.g. noBox) can't repaint
    // itself alone -- the parent window has to redraw the region just
    // outside it. Confirms this forwards to Window.damage() rather than
    // being a no-op.
    import fl.group : FlGroup;
    import fl.window : Window;

    FlGroup.current(null);
    fl.core.resetForTest();

    auto win = new Window(0, 0, 100, 40);
    auto b = new Button(10, 10, 50, 20, "X");
    b.box(Boxtype.noBox);
    win.end();
    win.clearDamage();

    assert(fl.core.visibleFocus());
    assert(!fl.core.boxBg(b.box()));

    assert(b.handle(Event.focus) == 1);
    assert(win.damage() != 0); // the parent window was told to repaint

    win.clearDamage();
    assert(b.handle(Event.unfocus) == 1);
    assert(win.damage() != 0);

    FlGroup.current(null);
    fl.core.resetForTest();
}
