/*
 * Ported from FL/fl_ask.H + src/fl_ask.cxx + src/Fl_Message.h/.cxx
 * (FLTK 1.5.0, "intentionally hidden in src/" FLTK). `FL/fl_message.H`
 * and `FL/fl_show_input.H` are pure `#include "fl_ask.H"` compatibility
 * headers FLTK (old names for this same file) and have no separate
 * content to port.
 *
 * `fl_beep()`, the user-facing string globals, `message()`/`alert()`,
 * `fl_input()`/`password()`, and `choice()`/`choiceN()` are ported --
 * the latter two just call `MessageDialog.innards()` with
 * caller-supplied button labels, which already returns the right 0/1/2
 * convention plus tracks `windowClosed_` for `choiceN()`'s wider
 * -1/-2 return range. Deliberately NOT ported, scoped out on purpose:
 * `fl_ask()` (FLTK itself deprecates it -- `choice()` is the
 * replacement it recommends), and the `fl_message_*()` dialog-
 * configuration functions (font/size/position/title/icon/hotspot
 * get/set) -- this port's `MessageDialog` always hotspot-positions
 * (FLTK's own default when `enable_hotspot_` is unset), has no
 * per-call title override, and exposes `messageFont`/`messageSize` as
 * the only configurable globals (matching FLTK's
 * `fl_message_font_`/`fl_message_size_`, the two that exist regardless
 * of the `fl_message_*()` config functions). `fl_input_str()`/
 * `fl_password_str()` also aren't ported as separate functions -- see
 * `fl_input()`'s own doc comment for why they'd be identical to
 * `fl_input()`/`password()` in D (the `str`-vs-internal-buffer split
 * those exist for FLTK is a C-string-ownership concern with no D
 * equivalent).
 *
 * `fl.draw`'s `fl_draw()` box overload implements real word-wrap for
 * `alignWrap`, but `Fl_Message::resizeform()` never exercises it here
 * either way: it sizes the message box to fit the *unwrapped* text
 * exactly (`fl_measure()` called with its wrap-width parameter left at
 * `0`, matching FLTK's own convention where `0` means "no wrap,
 * just measure") -- so a caller who doesn't put their own `\n`s in the
 * message still gets an arbitrarily wide (never wrapped) dialog,
 * exactly like real FLTK. `alignWrap` is still set on the message box
 * below for structural fidelity with FLTK (and in case a future
 * screen-width clamp needs it), and would then actually reflow the
 * text once that clamp presets `fl_measure()`'s width instead of `0`.
 *
 * Modal exclusivity is real cross-window event routing, matching
 * FLTK's own `Fl::modal_` (a "current topmost modal window"
 * pointer, set/cleared as a side effect of `Fl_Window::show()`/
 * `hide()`) plus filtering in `Fl::handle_()` and focus-pinning in
 * `fl_fix_focus()`: `fl.core.modal()` (see that function's own doc
 * comment for the full mechanism) is the ported subsystem, and this
 * module only calls `window_.setModal()` (in the constructor) plus
 * `window_.show()` -- it never calls `fl.core.grab()` for the dialog
 * itself (`grab()` is still what `fl.menu_popup`'s popup engine uses).
 * The "clear any pre-existing grab before showing, restore it after"
 * dance in `innards()` below matches FLTK's own
 * `Fl_Message::innards()` exactly (it guards against interaction with
 * an open menu popup, which does use `grab()`).
 *
 * Also backing this: `fl.window.Window.hotspot(int,int,bool)`/
 * `hotspot(Widget,bool)` (`Fl_Window::hotspot()`, single-monitor and
 * no-decoration-size-query simplified, see that function's own doc
 * comment); `fl.platform_x11`'s `WM_TRANSIENT_FOR`/
 * `_NET_WM_STATE_MODAL` hints (what actually keeps a modal dialog
 * visually on top and its owner un-raisable -- a window-manager
 * convention, not anything FLTK enforces itself once set); and
 * `fl.window.Window`'s own default `callback()` (ported from
 * `Fl_Window::default_callback`/`Fl::default_atclose`, needed since
 * `fl.core.handle()`'s `Event.close` case does real, `modal()`-aware
 * dispatch instead of an unconditional direct `destroyWindow()`, so
 * every *other* window in this port keeps closing normally via its OS
 * close button with no custom `callback()` of its own).
 *
 * Deliberately simplified relative to FLTK's `Fl_Message`: no
 * per-call window title (`window_title`/`message_title_default`).
 * `message()`/`alert()`/`fl_input()`/`password()` all take a plain D
 * `string` rather than a printf-style `const char*, ...` format string
 * -- same substitution this port makes everywhere else a C varargs API
 * meets a GC-owned `string` (see `fl.widget`'s `label()`/`tooltip()`
 * in CONVENTIONS.md); callers who want formatting use `std.format`/string
 * interpolation themselves, e.g. `alert(format("%d messages", n))`.
 */
module fl.ask;

import fl.enumerations;
import fl.core;
import fl.widget : Widget, Callback;
import fl.window : Window;
import fl.box : Box;
import fl.button : Button;
import fl.return_button : ReturnButton;
import fl.input : Input;
import fl.group : FlGroup;
import fldraw = fl.draw;

// pointers you can use to change FLTK to another language -- kept as
// mutable module-level `string`s (not `const(char)*`) as the direct D
// equivalent of FLTK's reassignable `const char *` globals.
string no = "No";
string yes = "Yes";
string ok = "OK";
string fl_cancel = "Cancel";
string fl_close = "Close";

/**
 * Emits a system beep. Forwards to fl.core's beep() (an `XBell()` call
 * on Linux), matching FLTK's `Fl::screen_driver()->beep()`
 * dispatch.
 */
void fl_beep(Beep type = Beep.default_)
{
    fl.core.beep(type);
}

// ---------------------------------------------------------------------
// message()/alert(), built on a D-native MessageDialog
// (the direct equivalent of FLTK's internal Fl_Message class).
// ---------------------------------------------------------------------

/// Configurable font/size for the message text -- matches FLTK's
/// `fl_message_font_`/`fl_message_size_`. `messageSize == -1` (the
/// default) means "use normalSize", same -1 sentinel FLTK uses.
Font messageFont = helvetica;
Fontsize messageSize = -1; /// ditto

private Box messageIconTemplate_;

/// One-shot override for the *next* dialog's icon label -- ported from
/// `Fl_Message::message_icon_label_` (`src/Fl_Message.cxx`), a distinct
/// mechanism from `messageIconTemplate_` above (that one copies box
/// type/font/size/color; this one overrides just the label, and only
/// for one dialog, then reverts to that dialog type's own default
/// glyph -- see the consuming code in `messageBoxWindow()`/wherever
/// `icon_.label(iconLabel)` runs below).
private string messageIconLabelOverride_;

/// Overrides the icon label the *next* `message()`/`alert()`/
/// `fl_ask()`-family dialog shows, instead of that dialog type's own
/// default glyph -- reverts automatically after that one dialog.
/// Ported from `fl_message_icon_label(const char*)` (`src/fl_ask.cxx`,
/// `Fl_Message::icon_label()`).
void messageIconLabel(string str)
{
    messageIconLabelOverride_ = str;
}

/**
 * Returns the default icon container used in the common dialogs
 * (`message()`/`alert()`/`choice()`/`input()`/
 * `password()`), so its box type/font/size/color can be changed for
 * every dialog shown from now on. Ported from `Fl_Message::message_icon()`
 * -- FLTK has both a private lazy-init helper and a public static
 * accessor of this same name; both do the same lazy-init-then-return,
 * so they're collapsed into this one function here.
 */
Box messageIcon()
{
    if (messageIconTemplate_ is null)
    {
        auto previousGroup = FlGroup.current();
        FlGroup.current(null);
        auto o = new Box(Boxtype.thinUpBox, 10, 10, 50, 50, null);
        o.labelfont(timesBold);
        o.labelsize(34);
        o.color(white);
        o.labelcolor(blue);
        messageIconTemplate_ = o;
        FlGroup.current(previousGroup);
    }
    return messageIconTemplate_;
}

// ---------------------------------------------------------------------
// messageHotspot()/messagePosition()/messageTitle() --
// one-shot (or, for hotspot/title_default, persistent) configuration
// for the *next* dialog shown, ported from the matching static fields
// on FLTK's `Fl_Message` (`src/Fl_Message.h`/`.cxx`).
// ---------------------------------------------------------------------

private int enableHotspot_ = 1; /// `Fl_Message::enable_hotspot_`
private int formX_, formY_;     /// `Fl_Message::form_x_`/`form_y_`
private int formPosition_;      /// `Fl_Message::form_position_` -- 0 = not set, 1 = absolute, 2 = centered
private string messageTitle_;         /// `Fl_Message::message_title_`
private string messageTitleDefault_;  /// `Fl_Message::message_title_default_`

/**
 * Sets whether the message box used by the common dialogs follows the
 * mouse pointer (the default). Ported from `fl_message_hotspot(int)`.
 */
void messageHotspot(int enable)
{
    enableHotspot_ = enable ? 1 : 0;
}

/// Returns whether hotspot-following is currently enabled. Ported from
/// `messageHotspot()`.
int messageHotspot()
{
    return enableHotspot_;
}

/**
 * Sets the preferred position for the *next* common dialog shown,
 * overriding the hotspot setting -- reset to "not set" as soon as that
 * dialog is shown. `center` non-zero centers the dialog at (`x`,`y`)
 * instead of using it as the window's top-left corner. Ported from
 * `messagePosition(const int, const int, const int)`.
 */
void messagePosition(int x, int y, int center = 0)
{
    formX_ = x;
    formY_ = y;
    formPosition_ = center ? 2 : 1;
}

/**
 * Same as the 3-argument overload, except the *next* dialog is centered
 * over `widget`'s own extent instead of a raw point. Ported from
 * `messagePosition(Fl_Widget*)`.
 */
void messagePosition(Widget widget)
{
    int xo, yo;
    auto win = widget.topWindowOffset(xo, yo);
    formX_ = xo + widget.w() / 2;
    formY_ = yo + widget.h() / 2;
    if (win !is null)
    {
        formX_ += win.x();
        formY_ += win.y();
    }
    formPosition_ = 2;
}

/**
 * Sets the title of the *next* common dialog shown; reverts to
 * `messageTitleDefault()` (or no title) afterward. `null`/`""`
 * clears a pending one-shot title without setting a new one. Ported
 * from `messageTitle(const char*)`.
 */
void messageTitle(string title)
{
    messageTitle_ = (title.length == 0) ? null : title;
}

/**
 * Sets the permanent default title used by every common dialog that
 * doesn't have a one-shot `fl_message_title()` pending. Ported from
 * `messageTitleDefault(const char*)`.
 */
void messageTitleDefault(string title)
{
    messageTitleDefault_ = (title.length == 0) ? null : title;
}

/// Handles Ctrl+C (Command+C on macOS, though this port only ever runs
/// on Linux so far) to copy the message text to the clipboard. Ported
/// from `Fl_Message_Box::handle()`.
private class MessageBox : Box
{
    this(int x, int y, int w, int h)
    {
        super(Boxtype.noBox, x, y, w, h, null);
    }

    override int handle(Event event)
    {
        auto mods = fl.core.eventState() & (stateMeta | stateCtrl | stateAlt);
        if ((event == Event.keyDown || event == Event.shortcut)
            && fl.core.eventKey() == 'c' && mods == stateCommand)
        {
            fl.core.copy(label(), 1);
            return 1;
        }
        return super.handle(event);
    }
}

/**
 * The base class behind `message()`/`alert()` -- the direct
 * equivalent of FLTK's `Fl_Message` (`src/Fl_Message.h`/`.cxx`,
 * "intentionally hidden in src/... internal use only"). See the module
 * comment for what's deliberately not ported (per-call title).
 */
private class MessageDialog
{
    Window window_;
    MessageBox message_;
    Box icon_;
    Button[3] button_;
    Input input_;
    int retval_;
    int windowClosed_; // 0 = button, -1 = Escape, -2 = WM close button

    /// Ported from `Fl_Message::Fl_Message(const char*)`.
    this(string iconLabel)
    {
        auto previousGroup = FlGroup.current();
        FlGroup.current(null);

        window_ = new Window(400, 150, null);
        message_ = new MessageBox(60, 25, 340, 20);
        message_.alignment(alignLeft | alignInside | alignWrap);

        input_ = new Input(60, 37, 340, 23);
        input_.hide();

        auto iconTemplate = messageIcon();
        icon_ = new Box(iconTemplate.box(), 10, 10, 50, 50, null);
        icon_.labelfont(iconTemplate.labelfont());
        icon_.labelsize(iconTemplate.labelsize());
        icon_.color(iconTemplate.color());
        icon_.labelcolor(iconTemplate.labelcolor());
        icon_.image(iconTemplate.image());
        icon_.alignment(iconTemplate.alignment());
        if (messageIconLabelOverride_ !is null)
        {
            icon_.copyLabel(messageIconLabelOverride_);
            messageIconLabelOverride_ = null;
        }
        else
        {
            icon_.label(iconLabel);
        }

        window_.end(); // don't add the buttons automatically

        // create the buttons (positions: right to left); button 1 is a
        // return button.
        //
        // Each button's callback is built via `buttonCallback(int idx)`
        // below -- a genuine per-call function invocation -- rather
        // than a delegate literal written directly inside this
        // `foreach` body: DMD allocates a *single* closure frame for
        // delegate literals created inside a loop body and reuses it
        // every iteration, so a delegate literal here would have all
        // three buttons' callbacks capture the same `b`, whatever it
        // happens to equal once the loop finishes (2, in this loop).
        // `buttonCallback()`'s own `idx` parameter, unlike a loop
        // variable, is fresh on every call.
        foreach (b; 0 .. 3)
        {
            int x = 310 - b * 100;
            if (b == 1)
                button_[b] = new ReturnButton(x, 70, 90, 23);
            else
                button_[b] = new Button(x, 70, 90, 23);
            button_[b].alignment(alignInside | alignWrap);
            button_[b].callback(buttonCallback(b));
        }

        // add the buttons left to right for tab navigation
        foreach_reverse (b; 0 .. 3)
            window_.add(button_[b]);

        window_.begin();
        window_.resizable(new Box(Boxtype.noBox, 60, 10, 110 - 60, 27, null));
        window_.end();

        window_.callback((w) {
            if ((fl.core.event() == Event.keyDown || fl.core.event() == Event.shortcut)
                && fl.core.eventKey() == escape)
                windowClosed_ = -1;
            else
                windowClosed_ = -2;
            retval_ = 0;
            window_.hide();
        });
        window_.setModal();

        FlGroup.current(previousGroup);
    }

    ~this()
    {
        destroy(window_);
    }

    /// Ported from `Fl_Message::innards()`'s title-assignment block: a
    /// pending one-shot `messageTitle()` wins, is consumed
    /// immediately, and otherwise the persistent default (if any) is
    /// used -- neither overrides a title the caller already set
    /// directly on `window_` (never happens in this port, since
    /// `window_` is always freshly constructed with no label, but
    /// ported faithfully regardless). Split out from `innards()` into
    /// its own method so it's independently unit-testable without
    /// needing a live display (`innards()` itself calls `window_.show()`).
    private void applyTitle()
    {
        if (window_.label() is null && messageTitle_ !is null)
        {
            window_.copyLabel(messageTitle_);
            messageTitle_ = null;
        }
        else if (window_.label() is null && messageTitleDefault_ !is null)
        {
            window_.copyLabel(messageTitleDefault_);
        }
    }

    /// Builds button `idx`'s callback -- see the constructor's own
    /// comment, right above where this is called, for why this needs
    /// to be a real per-call method rather than a delegate literal
    /// written directly inside the button-construction loop.
    private Callback buttonCallback(int idx)
    {
        return (w) {
            windowClosed_ = 0;
            retval_ = idx;
            window_.hide();
        };
    }

    /// Resizes the form and widgets so that they hold everything that
    /// is asked of them. Ported from `Fl_Message::resizeform()`,
    /// including the `input_`-related lines.
    private void resizeform()
    {
        enum iconSize = 50;

        fldraw.fl_font(message_.labelfont(), message_.labelsize());
        int messageW, messageH;
        fldraw.fl_measure(message_.label(), messageW, messageH);

        messageW += 10;
        messageH += 10;
        if (messageW < 340) messageW = 340;
        if (messageH < 30) messageH = 30;

        fldraw.fl_font(button_[0].labelfont(), button_[0].labelsize());

        int[3] buttonW, buttonH;
        int maxH = 25;
        foreach (i; 0 .. 3)
        {
            if (button_[i].visible())
            {
                fldraw.fl_measure(button_[i].label(), buttonW[i], buttonH[i]);
                if (i == 1) buttonW[1] += 20; // account for return button arrow
                buttonW[i] += 30;
                buttonH[i] += 10;
                if (buttonH[i] > maxH) maxH = buttonH[i];
            }
        }

        int textHeight = input_.visible() ? messageH + 25 : messageH;

        int maxW = messageW + 10 + iconSize;
        int w = buttonW[0] + buttonW[1] + buttonW[2] - 10;
        if (w > maxW) maxW = w;

        if (w > messageW && textHeight < iconSize)
        {
            int padH = iconSize - textHeight;
            messageH += padH;
            textHeight += padH;
        }

        messageW = maxW - 10 - iconSize;

        w = maxW + 20;
        int h = maxH + 30 + textHeight;

        window_.size(w, h);
        window_.sizeRange(w, h, w, h);

        message_.resize(20 + iconSize, 10, messageW, messageH);
        icon_.resize(10, 10, iconSize, iconSize);
        icon_.labelsize(iconSize - 10);
        input_.resize(20 + iconSize, 10 + messageH, messageW, 25);

        int x = w;
        foreach (i; 0 .. 3)
        {
            if (buttonW[i])
            {
                x -= buttonW[i];
                button_[i].resize(x, h - 10 - maxH, buttonW[i] - 10, maxH);
            }
        }
        window_.initSizes();
    }

    /**
     * Does all the dialog-window internals: finalizes layout, shows/
     * hides the buttons, sets the message text, pops up the window,
     * and blocks until the user picks a button, presses Escape, or
     * closes the window. Ported from `Fl_Message::innards()`, minus
     * window-title/positioning-config handling (see the module
     * comment). `b0.length == 0` hides that button (matching
     * FLTK's `const char *b0 == NULL` convention), same for `b1`/
     * `b2`.
     *
     * \returns 0 for Escape/window-close/button 0, 1 for button 1
     * (Return key), 2 for button 2 -- matching FLTK exactly.
     */
    int innards(string text, string b0, string b1, string b2)
    {
        fl.core.pushed(null); // stop dragging (FLTK's own STR #2159 fix)

        message_.label(text);
        message_.labelfont(messageFont);
        message_.labelsize(messageSize == -1 ? normalSize : messageSize);

        if (b0.length)
        {
            button_[0].show();
            button_[0].label(b0);
            button_[1].position(210, 70);
        }
        else
        {
            button_[0].hide();
            button_[1].position(310, 70);
        }

        if (b1.length) { button_[1].show(); button_[1].label(b1); }
        else button_[1].hide();

        if (b2.length) { button_[2].show(); button_[2].label(b2); }
        else button_[2].hide();

        resizeform();

        if (button_[1].visible() && !input_.visible())
            button_[1].takeFocus();

        // Ported from Fl_Message::innards()'s own positioning block: an
        // explicit messagePosition() always wins over the hotspot
        // setting, and is reset to "not set" the moment it's consumed.
        if (formPosition_)
        {
            int fx = formX_, fy = formY_;
            if (formPosition_ == 2) // centered
            {
                fx -= window_.w() / 2;
                fy -= window_.h() / 2;
            }
            window_.position(fx, fy);
            formX_ = formY_ = formPosition_ = 0;
        }
        else if (enableHotspot_)
            window_.hotspot(b0.length ? button_[0] : button_[1]);
        else
            window_.freePosition();

        if (b0.length && Widget.labelShortcut(b0))
            button_[0].shortcut(0);

        applyTitle();

        // Deactivate any existing grab (incompatible with a modal
        // window) and restore it afterward -- ported verbatim from
        // FLTK's own `Fl_Message::innards()` (`Fl_Window *g =
        // Fl::grab(); if (g) Fl::grab(0); ... if (g) Fl::grab(g);`).
        // window_ never grabs itself: window_.setModal() (already
        // called in the constructor) plus window_.show() are what make
        // this dialog exclusive now, via fl.core.modal()'s real
        // tracking/filtering -- see that function's own doc comment.
        auto previousGrab = fl.core.grab();
        if (previousGrab !is null) fl.core.grab(null);

        auto currentGroup = FlGroup.current();
        FlGroup.current(null);
        window_.show();
        FlGroup.current(currentGroup);

        while (window_.shown())
            fl.core.wait();
        fl.core.grab(previousGrab);

        return retval_;
    }

    /**
     * Does all the dialog-window internals for a message with a text
     * input field -- shows `input_` (as `type`) preloaded with
     * `defstr`, runs the same `innards()` machinery with a "Cancel"/
     * "OK" button pair, and returns the entered text, or `null` if the
     * user cancelled (Escape, the window's close button, or the
     * "Cancel" button itself). Ported from `Fl_Message::input_innards()`,
     * collapsed to one return path: FLTK's `str` parameter picks
     * between returning through a reused internal C buffer (the
     * original, ABI-stable `fl_input()`/`password()`) or a fresh
     * `std::string` (the newer `fl_input_str()`/`fl_password_str()`) --
     * a distinction that exists purely to manage C-string ownership
     * across the call boundary. A D `string` is already GC-owned and
     * safe to return directly, so there's only one `fl_input()`/
     * `password()` each below, not four; see the module comment.
     */
    string inputInnards(string text, string defstr, InputType type, int maxchar = 0)
    {
        message_.position(60, 10);
        input_.inputType(type);
        input_.show();
        input_.value(defstr);
        input_.takeFocus();
        if (maxchar > 0) input_.maximumSize(maxchar);

        int r = innards(text, fl_cancel, ok, null);
        if (!r) return null;

        return input_.value();
    }
}

/**
 * Shows an information message dialog box and waits for the user to
 * dismiss it. Ported from `Fl::fl_message()`.
 */
void message(string text)
{
    auto msg = new MessageDialog("i");
    scope(exit) destroy(msg);
    msg.innards(text, null, fl_close, null);
}

/**
 * Shows an alert message dialog box and waits for the user to dismiss
 * it. Ported from `Fl::fl_alert()` -- identical to fl_message() except
 * for the icon label ("!" instead of "i").
 */
void alert(string text)
{
    auto msg = new MessageDialog("!");
    scope(exit) destroy(msg);
    msg.innards(text, null, fl_close, null);
}

/**
 * Shows an input dialog with a text field preloaded with `deflt`, and
 * waits for the user to confirm or cancel it. Returns the entered text
 * (which may be `""` if the user cleared the field), or `null` if the
 * user cancelled -- pressed Escape, closed the window, or clicked
 * "Cancel". `maxchar`, if positive, limits the number of characters
 * (not bytes) that can be entered; `0` (the default) means unlimited.
 * Ported from `Fl::fl_input()`/`fl_input(int,...)` -- collapsed to one
 * function taking a real optional parameter rather than FLTK's two
 * separate maxchar/no-maxchar overloads (FLTK needs the split
 * because `maxchar` has to come *before* the printf-style varargs it
 * shares a parameter list with; a plain D default parameter has no such
 * ordering constraint). See the module comment for why there's no
 * separate `fl_input_str()` here.
 */
string fl_input(string text, string deflt = null, int maxchar = 0)
{
    auto msg = new MessageDialog("?");
    scope(exit) destroy(msg);
    return msg.inputInnards(text, deflt, inputNormal, maxchar);
}

/**
 * Same as `fl_input()`, except the entered text is masked (each
 * character shown as a bullet glyph, via `inputSecret` -- see
 * `fl.input_`'s `expand()`) rather than displayed in the clear. Ported
 * from `Fl::fl_password()`/`fl_password(int,...)`, same collapsing-two-
 * overloads-into-one-default-parameter substitution as `fl_input()`.
 */
string password(string text, string deflt = null, int maxchar = 0)
{
    auto msg = new MessageDialog("?");
    scope(exit) destroy(msg);
    return msg.inputInnards(text, deflt, inputSecret, maxchar);
}

/**
 * Shows a dialog with up to 3 customizable choice buttons, laid out
 * right-to-left (`b0` rightmost, `b1` the middle/default Return
 * button, `b2` leftmost), and waits for the user to pick one. Ported
 * from `Fl::fl_choice()` -- `b1`/`b2` pass `null` (matching FLTK's
 * `const char *b1/b2 == 0`) to omit that button, exactly like
 * `MessageDialog.innards()`'s own `b0.length == 0` convention already
 * documents.
 *
 * \returns 0 if `b0` was picked, Escape was pressed, or the window was
 * closed; 1 if `b1` was picked (or Return, since it's always the
 * default/Return button when present); 2 if `b2` was picked -- matching
 * FLTK's own `fl_choice()` return convention exactly (as opposed to
 * `choiceN()`'s wider one below, which distinguishes those three
 * "0" cases from each other).
 */
int choice(string text, string b0, string b1, string b2)
{
    auto msg = new MessageDialog("?");
    scope(exit) destroy(msg);
    return msg.innards(text, b0, b1, b2);
}

/**
 * Same as `choice()`, except Escape and the window close button
 * return distinct negative values instead of both collapsing into the
 * same `0` a real `b0` pick would also return. Ported from
 * `Fl::fl_choice_n()`.
 *
 * \returns -2 if the window was closed via its close button, -1 if
 * Escape was pressed, 0/1/2 for `b0`/`b1`/`b2` otherwise -- matching
 * FLTK's own `fl_choice_n()` return convention exactly.
 */
int choiceN(string text, string b0, string b1, string b2)
{
    auto msg = new MessageDialog("?");
    scope(exit) destroy(msg);
    int r = msg.innards(text, b0, b1, b2);
    return msg.windowClosed_ < 0 ? msg.windowClosed_ : r;
}

unittest
{
    // messageTitle(): a pending one-shot title is applied and then
    // consumed (cleared) so it doesn't leak into the *next* dialog.
    messageTitle_ = null;
    messageTitleDefault_ = null;

    messageTitle("Test Title");
    auto msg1 = new MessageDialog("?");
    scope(exit) destroy(msg1);
    assert(msg1.window_.label() is null);
    msg1.applyTitle();
    assert(msg1.window_.label() == "Test Title");
    assert(messageTitle_ is null); // consumed

    auto msg2 = new MessageDialog("?");
    scope(exit) destroy(msg2);
    msg2.applyTitle();
    assert(msg2.window_.label() is null); // no title pending this time

    // messageTitleDefault(): persists across multiple dialogs.
    messageTitleDefault("Default Title");
    auto msg3 = new MessageDialog("?");
    scope(exit) destroy(msg3);
    msg3.applyTitle();
    assert(msg3.window_.label() == "Default Title");

    auto msg4 = new MessageDialog("?");
    scope(exit) destroy(msg4);
    msg4.applyTitle();
    assert(msg4.window_.label() == "Default Title"); // still applies

    messageTitleDefault_ = null;
}
