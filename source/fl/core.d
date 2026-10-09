/*
 * Partial port of FL/Fl.H (FLTK 1.5.0) -- a real,
 * substantial (5000+ line) partial port; see PORTING.md's `FL/Fl.H` row
 * for the authoritative, up-to-date status.
 *
 * NOTE ON FLTK 1.5.0 vs the CHANGES_1.4.txt docs: `Fl` is no longer the
 * single monolithic static class it was in 1.3.x/1.4.x. FLTK now
 * declares `namespace Fl { ... }` with its members split across
 * FL/core/events.H, FL/core/options.H, FL/core/function_types.H and
 * FL/core/pen_events.H. fltk_version.dat already reports 1.5.0 while
 * CHANGES_1.4.txt has not been updated to document this restructuring,
 * so it cannot be trusted as a description of current behavior -- read
 * the headers directly. This D port mirrors the namespace shape with a
 * plain module (D modules already act like namespaces), which is a
 * closer structural match than the old static-class translation would
 * have been.
 *
 * Ported from FL/core/events.H:
 *  - focus_ / focus() / focus(Widget)          (upgraded from a trivial
 *                                                setter to the real
 *                                                UNFOCUS-walk + oldFocus()
 *                                                tracking, since
 *                                                fl.group's handle() needs
 *                                                both; see below)
 *  - callback_reason_
 *  - belowmouse_ / belowmouse() / belowmouse(Widget)
 *  - pushed_ / pushed() / pushed(Widget)
 *  - e_number/e_state/e_x/e_y/e_x_root/e_y_root/e_dx/e_dy/e_clicks/
 *    e_is_click/e_keysym/e_original_keysym/e_text and their accessors
 *    (event(), event_x(), event_state(), event_key(), event_text(), ...)
 *  - event_inside(int,int,int,int) / event_inside(const Fl_Widget*)
 *  - test_shortcut(Fl_Shortcut) -- tests event_state()/event_key()/
 *    event_text() against an explicit shortcut() value; not to be
 *    confused with Fl_Widget::test_shortcut() (fl.widget's
 *    Widget.testShortcut()), which tests a '&x'-in-label shortcut.
 *
 * Ported from src/fl_shortcut.cxx (the free-function half, alongside
 * fl.widget's labelShortcut()/testShortcut()):
 *  - fl_shortcut_label(unsigned int) -- the 1-arg convenience overload
 *    only; the 2-arg overload that also reports the end-of-modifiers
 *    split point isn't ported (nothing needs it yet -- only fl.menu's
 *    right-aligned key-name display would, and that's not ported).
 *    Returns a plain D `string` built fresh each call rather than
 *    FLTK's static reused buffer, same `string`-over-`char*`
 *    substitution CONVENTIONS.md documents elsewhere. Modifier-name lookup
 *    (Fl::system_driver()->control_name()/alt_name()/shift_name()/
 *    meta_name()) collapses to plain mutable module-level strings
 *    (flLocalCtrl/flLocalAlt/flLocalShift/flLocalMeta, still swappable
 *    for localization exactly like FLTK's fl_local_ctrl/etc.
 *    globals) since only macOS's system driver overrides them with
 *    symbol characters -- out of scope for this port. Key-name lookup
 *    for the key itself (e.g. keysym -> "F1"/"Left"/"KP_Enter") is a
 *    version(linux)-gated call into fl.platform_x11's keyName()
 *    (XKeysymToString(), matching Fl_X11_Screen_Driver's own override
 *    of shortcut_add_key_name() -- FLTK's platform-independent
 *    default_key_table is a Windows/Wayland-only fallback that X11
 *    never uses, so it isn't ported here either).
 *
 * Ported from Fl_X11_Screen_Driver::compose()/compose_reset()
 * (src/drivers/X11/Fl_X11_Screen_Driver.cxx), as compose()/composeReset()
 * below -- needed once fl.input_ existed (every text-editing widget calls
 * this per FL_KEYBOARD event). `del`/`compose_state` genuinely stay
 * always 0 on X11, matching FLTK's own real X11 driver exactly (see
 * compose()'s own doc comment for the confirmation). Real IME/XIM
 * input-context support is also ported: `fl.platform_x11` opens a real input
 * method (`XOpenIM()`/`XCreateIC()`) and uses `Xutf8LookupString()`
 * instead of `XLookupString()` for `KeyPress` text whenever it succeeds
 * (the common case), so dead-key sequences and full CJK input-method
 * composition both resolve to real, correct UTF-8 text -- see that
 * module's `initXim()`/`ximActivate()` and the `KeyPress` case's own
 * doc comments for the full mechanism and its deliberate scope (no
 * on-screen preedit/candidate-window positioning, since only
 * `fl.text_display` reports a cursor spot via `setSpot()`, and
 * `fl_set_spot()` never negotiates the separate status area).
 *
 * Ported from Fl::copy()/Fl::paste() (src/Fl.cxx) as copy()/paste()
 * below, backed by real X11 selection ownership. copy()
 * claims real ownership via `XSetSelectionOwner()`
 * (fl.platform_x11.setSelectionOwner()); paste() delivers synchronously
 * from our own buffer when we already own the requested selection
 * (matching FLTK's own in-process fast path), and otherwise fires an
 * asynchronous `XConvertSelection()` request
 * (fl.platform_x11.requestSelection()) and returns immediately -- the
 * actual FL_PASTE dispatch happens later, from the new package(fl)
 * deliverPaste(), once fl.platform_x11's event loop receives the real
 * SelectionNotify reply, exactly matching FLTK's real non-blocking
 * model (`Fl_X11_Screen_Driver::paste()` never blocks either). Simplified
 * relative to FLTK: text only (no image selections, no INCR protocol
 * for oversized transfers -- clipboard text always fits in one X
 * property in practice), and requests `UTF8_STRING` directly with a
 * single fallback retry to `XA_STRING` rather than FLTK's full
 * `TARGETS`-negotiation round trip. `weOwnSelection_[2]` (ownership per
 * slot) and `clearSelectionOwnership()` (called from
 * fl.platform_x11's `SelectionClear` handler when another app takes
 * over) mirror FLTK's own `fl_i_own_selection[2]`.
 *
 * Ported from Fl.H + the new src/Fl_Timeout.cxx: add_timeout()/
 * repeat_timeout()/has_timeout()/remove_timeout(), as addTimeout()/
 * repeatTimeout()/hasTimeout()/removeTimeout() below, plus the
 * fire-due-timers/compute-next-wakeup pair (processTimeouts()/
 * timeToWait()) that fl.platform_x11's run() now calls each iteration
 * instead of blocking forever on XNextEvent(). Callbacks are plain D
 * delegates (`TimeoutHandler`), not a C function pointer + `void*`
 * data pair -- see that alias's own doc comment. The timer queue
 * itself is a plain array scanned for its minimum, not FLTK's
 * hand-maintained sorted linked list + reusable free-list (the
 * free-list exists only to dodge `new`/`delete` overhead under C++
 * manual memory management, which the GC makes moot). Scheduling uses
 * `core.time.MonoTime` instead of FLTK's `gettimeofday()`-based
 * `Fl_Timestamp` -- monotonic and free of the wraparound caveat
 * FLTK's own doc comment flags for `Fl::now()` on some platforms.
 * This backs
 * `fl.button`'s `simulateKeyAction()` timed revert, `fl.clock`'s
 * auto-tick, `fl.scrollbar`'s/`fl.repeat_button`'s
 * auto-repeat-while-held, and `fl.spinner`'s buttons.
 *
 * `Fl::now()`/`Fl::seconds_since()`/`Fl::seconds_between()`/
 * `Fl::ticks_since()`/`Fl::ticks_between()` are real too, needed by
 * `source/test/threads.d`'s worker threads,
 * backed by the same `MonoTime`, as `now()`/
 * `secondsSince()`/`secondsBetween()`/`ticksSince()`/`ticksBetween()`
 * (`Timestamp` a plain `alias` for `MonoTime`, every function taking it
 * by value rather than FLTK's `Fl_Timestamp&`). Real thread
 * locking is ported too --
 * `Fl::lock()`/`unlock()`/`awake()`/`awake(handler, data)`/
 * `awake_once(handler, data)` (`src/Fl_lock.cxx`), as `lock()`/
 * `unlock()`/`awake()`/`awake(AwakeHandler)`/`awakeOnce(AwakeHandler)`
 * -- a real recursive `core.sync.mutex.Mutex` UI lock plus a
 * self-pipe/`addFd()`-based wakeup mechanism, released around
 * `fl.platform_x11`'s blocking `select()` exactly like FLTK's own
 * `fl_unlock_function()`/`fl_lock_function()` bracket. See this file's
 * "Thread locking" section (just above `beep()`) for the full writeup,
 * including why the deprecated `awake(void*)`/`thread_message()`
 * message-passing pair isn't ported.
 *
 * Ported:
 *  - Fl::handle()/handle_() itself is real (see below), collapsed into
 *    one `handle()` (the split only exists FLTK for
 *    event_dispatch()); wait()/check() (blocking and non-blocking
 *    single-iteration variants) are both real too.
 *  - Fl::grab()/Fl::grab(Fl_Widget*) is real, backed by actual
 *    `XGrabPointer()`/`XGrabKeyboard()` (fl.platform_x11's
 *    grabPointer()/ungrabPointer()) -- used by fl.menu_popup's popup
 *    engine. A real, separate `Fl::modal_`/`modal()` tracker also exists
 *    now (see modal()'s own doc comment below) -- **not** the same
 *    mechanism as grab(): modal() is what fl.ask's dialogs use for
 *    exclusivity, matching FLTK exactly; grab() is reserved for
 *    popup-menu-style pointer/keyboard capture. focus()/belowmouse()
 *    have the real "don't do anything while grab() is on" guards
 *    FLTK has, and fixFocus() pins focus inside the current modal()
 *    window.
 *  - add_handler()/remove_handler()/add_system_handler()/
 *    remove_system_handler()/event_dispatch() are all real
 *    (addHandler()/removeHandler()/addSystemHandler()/
 *    removeSystemHandler()/eventDispatch() below) -- fl.platform_x11's
 *    event loop calls sendSystemHandlers() on every raw XEvent before
 *    translating it, and dispatch() (the addressable, event_dispatch()-
 *    overridable entry point) is what that loop and fl.core.handle()'s
 *    own recursive calls both go through.
 *  - get_mouse()/get_key() are real (forward to fl.platform_x11).
 *    `Fl::add_fd()`/`remove_fd()` are real too (`addFd()`/
 *    `removeFd()` below), folded into
 *    fl.platform_x11's own select()-based wait alongside the X
 *    connection fd and the timer queue. Real IME/XIM input-context
 *    support is ported too (see
 *    compose()'s own doc comment), and real Windows IME support
 *    exists too (`fl.platform_win32`'s own module comment --
 *    composed/committed IME text, dead-key composition, and the emoji
 *    picker all reach this port's widgets for the first time there).
 *    `enable_im()`/`disable_im()` are ported too: FLTK's own base
 *    `Fl_Screen_Driver::enable_im()`/`disable_im()` are empty no-ops and
 *    X11 doesn't override either, so there is nothing to forward to on
 *    this port's primary platform; `Fl_WinAPI_Screen_Driver` *does*
 *    override both for real, so on Windows these are real too -- see
 *    `enableIm()`/
 *    `disableIm()`'s own doc comments. `first_window()` real (see
 *    `firstWindow()`'s own doc comment).
 *
 * Ported from FL/core/options.H:
 *  - visible_focus()/visible_focus(int), and the general Fl_Option/
 *    option() mechanism itself (Option enum + option()/option(Option,bool)
 *    below) that visibleFocus()/dndTextOps() are now both thin wrappers
 *    over.
 *
 * Ported from FL/Fl.H:
 *  - readqueue()                               (backed by the queue
 *                                                Fl_Widget::default_callback
 *                                                fills; see fl.widget)
 *  - clear_widget_pointer()                    (still clears
 *                                                pushed_/belowmouse_/
 *                                                focus_/oldFocus_ as
 *                                                before -- selection_owner_
 *                                                (X selection ownership)
 *                                                doesn't exist, so that
 *                                                part is skipped -- but now
 *                                                also walks the
 *                                                watch_widget_pointer()
 *                                                list below, which backs
 *                                                fl.widget_tracker's
 *                                                WidgetTracker)
 *  - watch_widget_pointer()/release_widget_pointer() (back
 *                                                fl.widget_tracker's
 *                                                WidgetTracker -- see that
 *                                                module's comment for why
 *                                                this needed a real D
 *                                                redesign rather than a
 *                                                straight port, and why
 *                                                it's not just faithful-
 *                                                for-faithfulness's-sake)
 *  - box_dx()/box_dy()/box_dw()/box_dh()/box_bg() (backed by the metrics
 *                                                half of src/fl_boxtype.cxx's
 *                                                fl_box_table: the per-
 *                                                boxtype dx/dy/dw/dh insets
 *                                                and solid-background-vs-
 *                                                frame flag. The *drawing*
 *                                                half of that table -- the
 *                                                actual box-drawing function
 *                                                pointers -- is real too: see
 *                                                fl.draw.drawBoxAt(), a
 *                                                switch dispatch rather than
 *                                                a literal function-pointer
 *                                                table, but functionally
 *                                                complete for every boxtype
 *                                                boxTable below has a
 *                                                metrics entry for.)
 */
module fl.core;

import fl.enumerations : CallbackReason, Boxtype, Event, Keysym, EventState,
    button, keyMask, stateShift, stateCtrl, stateCommand, stateAlt, stateMeta,
    stateCapsLock, stateButtons, stateButton1, stateButton2, stateButton3,
    stateButton4, stateButton5, Beep, escape, FdWhen, fdRead, fdWrite, fdExcept,
    Labeltype, alignCenter, alignInside, alignClip, backgroundColor, Font, Fontsize,
    symbol, screen, screenBold, zapfDingbats, bold, italic,
    FL_VERSION, FL_API_VERSION, FL_ABI_VERSION,
    Color, colorTable, grayRamp, numGray, fl_gray_ramp, foregroundColor,
    background2Color, selectionColor, Mode, black, white, timesBold;
import fl.widget;
// Aliased, not a plain `import fl.window : Window;` -- fl.platform_x11
// already has to alias this same import the same way (`FlWindow =
// Window`), since it also wildcard-imports fl.xlib, whose own `Window`
// is the unrelated raw X11 XID typedef. Importing fl.core re-exposes
// this alias too, so the same collision would hit fl.platform_x11's
// `import fl.core;` without it.
import fl.window : CoreWindow = Window;
import fl.image : Image, RGBImage;
import fl.bmp_image : BMPImage, createBmp;
import fl.pixmap : Pixmap;
import fl.tiled_image : TiledImage;
import fl.box : Box;
import fl.image_surface : ImageSurface, SurfaceDevice;
import fldraw = fl.draw;
import std.format : format;
import core.time : MonoTime, Duration, usecs, dur;
import core.sync.mutex : Mutex;

// Circular import, deliberately -- same shape as this module's existing
// platformX11 one: fl.tooltip needs fl.core for timers/event-state, and
// fl.core needs fl.tooltip's enter()/exit()/current() at the exact call
// sites Fl::handle_()/Fl::belowmouse() reach them at FLTK (Fl.cxx).
// D handles this fine (no genuine compile-time ordering dependency,
// just plain function calls); see fl.tooltip's own top comment for why
// this replaces FLTK's lazy Fl_Tooltip::enter/exit function-pointer
// indirection rather than porting that trick too.
import fl.tooltip;

version (linux) import platformX11 = fl.platform_x11;
version (Windows) import platformWin32 = fl.platform_win32;
version (linux) import fl.xlib : XParseGeometry, XParseColor, XColor,
    XDefaultScreen, XDefaultColormap, Colormap;

private Widget focus_;
private Widget oldFocus_;
private CallbackReason callbackReason_;
private int boxShadowWidth_ = 3;
private int boxBorderRadiusMax_ = 15;

// ---------------------------------------------------------------------
// Event state (FL/core/events.H)
// ---------------------------------------------------------------------
//
// FLTK keeps these as plain extern globals -- "should be private,
// but would harm back compatibility" per its own comment -- and lets
// Fl_Group.cxx's send()/navkey() helpers read and temporarily rewrite
// e_x/e_y/e_number directly. This port mirrors that: the fields below
// are package(fl)-visible module variables (not wrapped in getter/setter
// pairs) so fl.group can do the same, while external callers only see
// the read-only accessor functions.
//
// Nothing populates these yet -- there is no event loop/platform driver
// (see the module note above) -- so they only matter to code that sets
// them directly, e.g. unit tests exercising fl.group's handle().

package(fl)
{
    Event eNumber_;
    EventState eState_;
    /// Set while `Event.dndEnter`/`dndDrag`/`dndLeave` are being
    /// processed -- ported from FLTK's file-static `dnd_flag`
    /// (`Fl.cxx`). The only consumer is `belowmouse()`'s own
    /// `FL_LEAVE`-vs-`FL_DND_LEAVE` substitution just below; see that
    /// function's doc comment.
    bool dndFlag_;
    /// Ported from FLTK's file-static `int (*fl_local_grab)(int)`
    /// (`Fl.cxx`, "used by fl_dnd.cxx"). `null` outside of a drag
    /// session; see `handle()`'s own doc comment for what it does while
    /// set, and `fl.platform_x11.dnd()`/`localHandle()` for the one
    /// real installer/consumer. A delegate rather than a bare function
    /// pointer per this port's usual callback convention, even though
    /// the one real implementation (`grabFunc()`) doesn't currently
    /// need to close over anything.
    int delegate(Event) localGrab_;
    int eX_, eY_, eXRoot_, eYRoot_, eDx_, eDy_;
    float eDxF_ = 0, eDyF_ = 0;       // hi-res wheel deltas
    float eDxErr_ = 0.5f, eDyErr_ = 0.5f; // fraction carried between hi-res -> int conversions
    int eClicks_;
    bool eIsClick_;
    Keysym eKeysym_, eOriginalKeysym_;
    string eText_;
    Widget belowmouse_;
    Widget pushed_;
    Object eClipboardData_;
    string eClipboardType_;
}

/// The last event that was processed.
Event event() { return eNumber_; }

/// Mouse position of the event, relative to the window it was passed to.
int eventX() { return eX_; }
/// ditto
int eventY() { return eY_; }
/// Overrides the event's X position -- ported use case: `Fl_Widget_Bin_
/// Button::handle()` (FLTK `fluid/widgets/Bin_Button.cxx`) fakes
/// `Fl::e_x = x()-1;` to synthesize a "dragged outside the button"
/// FL_DRAG/FL_RELEASE pair that un-arms the button without firing its
/// own click callback, right before it starts a real DND drag. Same
/// synthetic-event-field precedent as `eventIsClick(bool)`/
/// `eventClicks(int)` just below.
void eventX(int v) { eX_ = v; }
/// ditto
void eventY(int v) { eY_ = v; }

/// Mouse position of the event, in screen coordinates.
int eventXRoot() { return eXRoot_; }
/// ditto
int eventYRoot() { return eYRoot_; }

/// Horizontal/vertical mouse wheel scroll delta for an FL_MOUSEWHEEL event.
int eventDx() { return eDx_; }
/// ditto
int eventDy() { return eDy_; }

/// Horizontal mouse wheel/touchpad scroll delta of an FL_MOUSEWHEEL event
/// in fractional lines; right is positive.
float eventDxF() { return eDxF_; }
/// Vertical counterpart of eventDxF(); down is positive.
float eventDyF() { return eDyF_; }

/// Sets the wheel state for one FL_MOUSEWHEEL event from hi-res deltas
/// (in lines): eventDxF()/eventDyF() get the exact value, eventDx()/
/// eventDy() the whole lines accumulated so far. Only one axis is
/// non-zero per event.
package(fl) void setWheelDelta(float dx, float dy)
{
    import std.math : floor;
    eDxF_ = dx; eDyF_ = dy;
    eDx_ = 0; eDy_ = 0;
    if (dx != 0)
    {
        eDxErr_ += dx;
        float i = floor(eDxErr_);
        eDxErr_ -= i;
        eDx_ = cast(int) i;
    }
    if (dy != 0)
    {
        eDyErr_ += dy;
        float i = floor(eDyErr_);
        eDyErr_ -= i;
        eDy_ = cast(int) i;
    }
}

/// Number of consecutive clicks; N-1 for N clicks.
int eventClicks() { return eClicks_; }
void eventClicks(int i) { eClicks_ = i; }

/// Whether the mouse hasn't moved far/long enough since the last
/// FL_PUSH/FL_KEYBOARD to be considered a "drag" rather than a "click".
bool eventIsClick() { return eIsClick_; }
void eventIsClick(bool v) { eIsClick_ = v; }

/// Which mouse button caused the current event; garbage unless the last
/// event was FL_PUSH or FL_RELEASE.
int eventButton() { return eKeysym_ - button; }

/// Keyboard/mouse-button state bitfield of the last event.
EventState eventState() { return eState_; }
/// Non-zero if any bit in mask is set in the current event state.
EventState eventState(EventState mask) { return eState_ & mask; }

/// Which key caused the current FL_KEYBOARD/FL_SHORTCUT event, or 0.
Keysym eventKey() { return eKeysym_; }
/// Overrides the key reported for the current event -- matches
/// FLTK's `Fl::e_keysym` being a genuinely mutable public global
/// (`FL/core/events.H`), not just a read accessor: an `addHandler()`/
/// `addSystemHandler()` callback can rewrite it before the event
/// reaches widgets (e.g. remapping a keypad key to a digit). Named
/// `eventKeysym()` rather than an `eventKey(Keysym)` overload -- that
/// name is already taken by the *different*, real FLTK function
/// `Fl::event_key(int)` (a "is this key currently held" query, see
/// below), which returns `bool`; D can't overload on return type alone.
void eventKeysym(Keysym k) { eKeysym_ = k; }
/// eventKey() before NumLock keypad-to-arrow-key translation.
Keysym eventOriginalKey() { return eOriginalKeysym_; }

/**
 * Whether key `k` is *recorded* as currently held down, per this
 * port's own incrementally-maintained key-state vector -- the direct
 * equivalent of FLTK's `Fl::event_key(int)`. Forwards to
 * `fl.platform_x11.eventKey()` or `fl.platform_win32.eventKey()`.
 * Reflects whatever the event loop last saw, not a fresh query -- call
 * getKey() instead for a guaranteed-current answer (matching
 * FLTK's own `event_key()`-vs-`get_key()` distinction).
 */
bool eventKey(Keysym k)
{
    version (linux) return platformX11.eventKey(k);
    else version (Windows) return platformWin32.eventKey(k);
    else return false;
}

/**
 * Whether key `k` is currently held down right now, via a fresh
 * query -- the direct equivalent of FLTK's `Fl::get_key(int)`.
 * Forwards to `fl.platform_x11.getKey()` or `fl.platform_win32.getKey()`.
 */
bool getKey(Keysym k)
{
    version (linux) return platformX11.getKey(k);
    else version (Windows) return platformWin32.getKey(k);
    else return false;
}

/**
 * Computes the current mouse position in screen coordinates via a
 * fresh server round trip -- the direct equivalent of FLTK's
 * `Fl::get_mouse(int&, int&)`. Forwards to `fl.platform_x11.getMouse()`;
 * always returns `0` and leaves X/Y unset on non-Linux platforms, since
 * no other platform driver exists yet.
 */
int getMouse(out int x, out int y)
{
    version (linux) return platformX11.getMouse(x, y);
    else version (Windows) return platformWin32.getMouse(x, y);
    else return 0;
}

/**
 * Captures the content of a rectangular zone of a mapped window as an
 * `RGBImage`. Ported from `fl_capture_window()` (`src/readImage.cxx`)
 * -- declared alongside `fl_read_image()` in FLTK's `fl_draw.H`,
 * homed here rather than in `fl.draw` since it needs both a real
 * `Window`-to-xid lookup (`fl.platform_x11`, which `fl.draw` doesn't
 * depend on) and `RGBImage` construction, the same reason `getMouse()`
 * and friends live here rather than in `fl.draw` too. Returns `null`
 * if `win` isn't currently shown or the underlying pixel read failed,
 * matching FLTK's own `NULL`-on-failure contract. Unlike FLTK,
 * no GL-subwindow traversal or display-scale handling (neither exists
 * anywhere in this port). Same "window must be viewable" `XGetImage()`
 * caveat as `fl.draw.readImage()` applies here too -- see that
 * function's own doc comment; `win.shown()` being true isn't quite
 * enough on its own if called too soon after that same window's own
 * `show()` (before the server has confirmed it viewable).
 */
RGBImage captureWindow(CoreWindow win, int x, int y, int w, int h)
{
    version (linux)
    {
        auto pixels = platformX11.captureWindowPixels(win, x, y, w, h);
        return pixels is null ? null : new RGBImage(pixels, w, h, 3);
    }
    else return null;
}

/**
 * Reports the text cursor's screen position to the input method, so a
 * CJK (or other composing) input method can position its own floating
 * preedit window at the cursor instead of some fixed default location
 * -- "over the spot" IME positioning. Ported from `fl_set_spot()`
 * (`src/fl_font.cxx`, forwarding to `Fl::screen_driver()->set_spot()`)
 * -- declared alongside `fl_capture_window()`/`fl_read_image()` in
 * FLTK's `fl_draw.H`, homed here for the same reason those are:
 * needs `fl.platform_x11`, which `fl.draw` doesn't depend on (see
 * `fl_capture_window()`'s own doc comment just above).
 *
 * A no-op unless the input method actually supports "over the spot"
 * preedit positioning (most don't offer it at all, and even when one
 * does, most users' input methods work identically without it -- the
 * composed text still lands correctly either way, since that happens
 * inside `Xutf8LookupString()` regardless, see `compose()`'s own doc
 * comment) -- callers don't need to check anything first, matching
 * FLTK's own unconditional-call contract.
 *
 * `win` is used for real on Windows: for X11 (a single process-wide input context,
 * no per-window coordinate walk left to do by the time a caller's
 * coordinates reach `platformX11.setSpot()`) it is accepted only for
 * signature fidelity and otherwise unused, but
 * `platformWin32.setSpot()` genuinely needs `win` to resolve the
 * right top-level HWND's own IME input context and to convert `win`'s
 * local coordinates into that top-level's client coordinates (a real
 * subwindow-to-top-level walk, unlike X11's side) -- see that function's
 * own doc comment.
 */
void setSpot(Font font, Fontsize size, int X, int Y, int W, int H, CoreWindow win = null)
{
    version (linux) platformX11.setSpot(font, size, X, Y, W, H);
    else version (Windows) platformWin32.setSpot(font, size, X, Y, W, H, win);
}

/// Clears the cached "over the spot" position, so the next `setSpot()`
/// call is guaranteed to push a real update rather than being skipped
/// as a no-op change. Ported from `fl_reset_spot()` (`src/fl_font.cxx`).
/// **Still correctly a no-op on Windows** (checked directly against
/// FLTK, not assumed): `Fl_WinAPI_Screen_Driver` never overrides
/// `reset_spot()`, so real FLTK Windows also just runs the base
/// `Fl_Screen_Driver::reset_spot()` -- an empty `{}` body -- unlike
/// `set_spot()`/`enable_im()`/`disable_im()`, which FLTK's own
/// Windows driver *does* override for real.
void resetSpot()
{
    version (linux) platformX11.resetSpot();
}

/**
 * Ported from `Fl::enable_im()`/`disable_im()` (`Fl.cxx`, forwarding to
 * `Fl::screen_driver()->enable_im()`/`disable_im()`) -- explicitly
 * turns the input method on/off for every shown top-level window. A
 * rarely-used escape hatch most apps never call (IME composition works
 * transparently without it). FLTK's own base `Fl_Screen_
 * Driver::enable_im()`/`disable_im()` are empty no-ops and X11 doesn't
 * override either, so there is nothing for this port to forward to
 * there; `Fl_WinAPI_Screen_Driver`
 * *does* override both for real (`ImmAssociateContextEx()`), so these
 * are real on Windows, still a
 * no-op on Linux, matching FLTK's own per-platform split exactly.
 */
void enableIm()
{
    version (Windows) platformWin32.enableIm();
}

/// ditto (the disabling half).
void disableIm()
{
    version (Windows) platformWin32.disableIm();
}

/// Text associated with the current event (FL_KEYBOARD, FL_PASTE, ...).
string eventText() { return eText_; }
/// Overrides the text reported for the current event -- matches
/// FLTK's `Fl::e_text` being a genuinely mutable public global
/// (`FL/core/events.H`), same rationale as `eventKey(Keysym)` above.
/// `eventLength()` is derived from this, so setting a shorter/longer
/// string already updates it too -- no separate setter needed.
void eventText(string s) { eText_ = s; }
/// FLTK's `Fl::event_length()` exists apart from `strlen(event_text())`
/// because pasted or composed text may contain embedded NULs; a D string
/// carries its own length, so this is just that.
size_t eventLength() { return eText_.length; }

/// Ported from `Fl::clipboard_plain_text`/`Fl::clipboard_image`
/// (`FL/core/events.H`) -- the two `type` values `paste()`/
/// `clipboardContains()` understand. Plain `string` manifest constants
/// rather than FLTK's `extern const char* const` pair: FLTK's
/// own paste()/clipboard_contains() do a mix of pointer-identity and
/// `strcmp()` comparisons against these two globals (their comments
/// don't consistently distinguish which), which only matters because
/// C++ callers can't rely on string interning; D `string`s compare by
/// value with `==` regardless, so every comparison in this port's own
/// paste()/clipboardContains() below is a plain value comparison --
/// deliberately not a transliteration of the pointer-identity checks,
/// since porting *that* literally would silently make some FLTK
/// branches unreachable for any caller that builds an equal-but-
/// distinct string (a real risk, not a hypothetical one: D string
/// literals with the same content aren't guaranteed to be the same
/// array instance).
enum string clipboardPlainText = "text/plain";
enum string clipboardImage = "image"; // sic -- matches Fl::clipboard_image exactly, not a MIME type

/// Associated data for an `Event.paste` whose `eventClipboardType()`
/// is `clipboardImage` -- cast to `RGBImage` to use (matches FLTK's
/// own `void*`-cast-to-`Fl_RGB_Image*` convention exactly). Null for a
/// text paste, or if no compatible image type was found/decodable
/// (e.g. the clipboard owner only offered a still-unported format like
/// PNG -- see `fl.platform_x11`'s own `SelectionNotify` image-decode
/// branch for the current native-only-decodes-BMP scope).
Object eventClipboard() { return eClipboardData_; }

/// `clipboardPlainText` or `clipboardImage` -- which kind of data the
/// current `Event.paste` carries. Ported from
/// `Fl::event_clipboard_type()`.
string eventClipboardType() { return eClipboardType_; }

private int composeState_ = 0;

/// Sets `composeState_` directly -- called from `fl.platform_win32.
/// charEvent()` after a handled `WM_DEADCHAR`/`WM_SYSDEADCHAR` dispatch,
/// matching FLTK's own `Fl::compose_state = 1;` (`Fl_win32.cxx`).
/// `composeState_` itself stays `private` (only `compose()` below reads
/// it) -- this is the one narrow, deliberate crack in that encapsulation,
/// needed because the real value only ever gets set from `fl.platform_
/// win32`, a different module.
package(fl) void markComposeState(int n) { composeState_ = n; }

/**
 * Ported from Fl_X11_Screen_Driver::compose(int&)/Fl_WinAPI_Screen_
 * Driver::compose(int&) -- real per-platform bodies, not just the
 * X11 one. Any text-editing widget calls this for
 * each FL_KEYBOARD event: if it returns true, eventText()/eventLength()
 * hold bytes that should be inserted (`del` says how many bytes to the
 * left of the cursor to delete first, to replace a previous provisional
 * composition); if false, the keystroke should be treated as a
 * function/control key instead.
 *
 * `del`/`composeState_` genuinely stay always 0 on X11 -- confirmed
 * directly against FLTK's own source: `Fl::compose_state` is never
 * set non-zero anywhere in the real X11 driver (`Fl_X11_Screen_Driver.cxx`),
 * only in the Windows one (`Fl_win32.cxx`, via a handled `WM_DEADCHAR`/
 * `WM_SYSDEADCHAR` -- see `fl.platform_win32.charEvent()`'s own doc
 * comment for where `markComposeState(1)` gets called from). Dead-key
 * sequences and full input-method (CJK, etc.) composition still work
 * correctly on X11 -- `Xutf8LookupString()` (in `fl.platform_x11`'s
 * `KeyPress` handling) resolves an entire compose sequence to its final
 * composed UTF-8 character(s) internally, invisibly to this function,
 * before `eventText()` ever sees it. `del` would only ever matter for an
 * input method style that draws a *provisional* composed character
 * directly in the text widget before the sequence completes (needing
 * FLTK to delete-and-replace it) -- FLTK's own X11 driver doesn't
 * use that style, and neither does this port (see `fl.platform_x11.
 * initXim()`'s own doc comment for the specific style requested).
 *
 * **The Windows branch has one real difference from X11's**, ported
 * faithfully from `Fl_WinAPI_Screen_Driver::compose()`: the AltGr
 * ("right Alt") key reports as Ctrl+Alt held together on many
 * international keyboard layouts, which would otherwise make this
 * function misidentify an AltGr-typed character (e.g. AltGr+E for "€")
 * as a function-key combination to skip rather than real text to
 * insert -- `platformWin32.altGrDown()` (a live `GetAsyncKeyState(
 * VK_RMENU)` check, matching FLTK's identical real-time check
 * rather than anything cached in `eState_`) excludes exactly that case.
 */
bool compose(out int del)
{
    ubyte ascii = eText_.length > 0 ? cast(ubyte) eText_[0] : 0;
    bool functionKey = (eState_ & (stateAlt | stateMeta | stateCtrl)) != 0 && !(ascii & 128);
    version (Windows)
        functionKey = functionKey && !((eState_ & stateCtrl) != 0 && platformWin32.altGrDown());
    if (functionKey)
    {
        del = 0;
        return false;
    }
    del = composeState_;
    composeState_ = 0;
    // Only insert non-control characters:
    if (ascii < 32 || ascii == 127) return false;
    return true;
}

/**
 * Ported from Fl_X11_Screen_Driver::compose_reset(). Call after moving
 * the cursor so the next compose() call doesn't set a stale `del`.
 * Also resets the real input context's own composition state, via
 * `fl.platform_x11.resetIC()`'s `XmbResetIC()` call, matching FLTK's
 * own `if (xim_ic) XmbResetIC(xim_ic);`. A no-op on non-Linux platforms.
 */
void composeReset()
{
    composeState_ = 0;
    version (linux) platformX11.resetIC();
}

private string primarySelection_;
private string clipboardBuffer_;

/// Pre-encoded BMP bytes for an owned *image* selection (`copyImage()`)
/// -- the image counterpart to `clipboardBuffer_`/`primarySelection_`.
/// Mirrors FLTK's own `fl_selection_buffer[2]` doing double duty
/// for both text and (BMP-encoded) image payloads, just kept in its
/// own array here rather than reusing the text one's storage.
private const(ubyte)[][2] ownedImageBmp_;

/// Which kind of data `copy()`/`copyImage()` last claimed ownership of
/// for each selection slot -- `clipboardPlainText` or `clipboardImage`.
/// Mirrors FLTK's own `fl_selection_type[2]` (Fl_x.cxx), consulted
/// by `fl.platform_x11`'s `SelectionRequest` handler to decide which
/// `TARGETS` to advertise and `paste()`'s in-process fast path below.
private string[2] selectionType_ = [clipboardPlainText, clipboardPlainText];

/// Whether *this process* currently owns the PRIMARY (index 0) /
/// CLIPBOARD (index 1) X11 selection -- set by copy(), cleared by
/// clearSelectionOwnership() (called from fl.platform_x11's
/// SelectionClear handler when another app takes over). Mirrors
/// FLTK's own `fl_i_own_selection[2]` (Fl_x.cxx).
private bool[2] weOwnSelection_;

/// The receiver of an in-flight, asynchronous paste() request (set only
/// when we don't own the requested selection ourselves) -- consumed by
/// deliverPaste() once fl.platform_x11's SelectionNotify handler gets
/// the reply. Only one paste can be in flight at a time, matching
/// FLTK's own single `fl_selection_requestor`/`fl_selection_type`
/// pair (Fl_x.cxx has no queueing either).
private Widget pendingPasteReceiver_;

/**
 * Ported from Fl::copy(const char*, int, int). Stores `text` into the
 * PRIMARY (`clipboard` 0) or CLIPBOARD (`clipboard` 1) selection slot
 * and claims real X11 selection ownership for it (`XSetSelectionOwner()`,
 * via fl.platform_x11.setSelectionOwner()) so other X applications --
 * not just other widgets in this process -- can request it too. On
 * Windows, `fl.platform_win32.setSelectionOwner()` instead pushes
 * `clipboard`-1's text straight into the real OS clipboard right here,
 * synchronously -- matching FLTK's
 * own `Fl_WinAPI_Screen_Driver::copy()`, which calls `fl_update_
 * clipboard()` unconditionally for `clipboard == 1` and does nothing
 * platform-side at all for `clipboard == 0` (Windows has no real
 * PRIMARY-selection equivalent; index 0 always stays this-process-only
 * on that platform, matching `paste()`'s own Windows-specific handling
 * below). A no-op beyond the local store on any other platform.
 */
void copy(string text, int clipboard)
{
    if (clipboard) clipboardBuffer_ = text;
    else primarySelection_ = text;
    selectionType_[clipboard] = clipboardPlainText;
    weOwnSelection_[clipboard] = true;
    version (linux) platformX11.setSelectionOwner(clipboard);
    version (Windows) platformWin32.setSelectionOwner(clipboard);
}

/**
 * The write-side counterpart to `paste(..., clipboardImage)`. Ported
 * from `Fl_Screen_Driver::copy_image()`/`Fl_X11_Screen_Driver::
 * copy_image()` (`Fl_x.cxx`): encodes `rgbData` (depth-3 RGB, packed,
 * top-down row order, `w*h*3` bytes -- the same layout
 * `fl.draw.readPixelsFromDrawable()`/`RGBImage.array` already use) as
 * a BMP via `fl.bmp_image.createBmp()`, stores the result as the
 * PRIMARY (`clipboard` 0) or CLIPBOARD (`clipboard` 1) selection's
 * payload, and claims real X11 selection ownership for it, same as
 * `copy()` does for text. Other X applications' own paste can then
 * retrieve it as `image/bmp` -- the same format this port's own
 * `paste(..., clipboardImage)` already knows how to decode (see
 * `fl.platform_x11`'s `SelectionRequest`/`SelectionNotify` handling
 * for both directions). A no-op on non-Linux platforms.
 *
 * The one real caller: `fl.widget_surface.CopySurface`'s destructor
 * (for `test/device.cxx`'s "Fl_Copy_Surface" demo).
 */
void copyImage(const(ubyte)[] rgbData, int w, int h, int clipboard)
{
    if (rgbData is null || w <= 0 || h <= 0) return;
    version (linux)
    {
        ownedImageBmp_[clipboard] = createBmp(rgbData, w, h);
        selectionType_[clipboard] = clipboardImage;
        weOwnSelection_[clipboard] = true;
        platformX11.setSelectionOwner(clipboard);
    }
}

/**
 * Ported from Fl::paste(Fl_Widget&, int, const char* type). If this
 * process already owns the requested selection, delivers it to
 * `receiver` synchronously -- matching FLTK's own fast path
 * (`Fl_X11_Screen_Driver::paste()`'s `if (Fl::e_clipboard_type == ...)`
 * in-process shortcut). Otherwise, matching FLTK's real
 * *asynchronous* model exactly, this fires an `XConvertSelection()`
 * request and returns immediately without delivering anything -- the
 * actual FL_PASTE dispatch happens later, from deliverPaste()/
 * deliverPasteImage(), once the event loop receives the X server's
 * SelectionNotify reply (or replies -- an image request needs two, see
 * `fl.platform_x11.requestSelectionImage()`'s own doc comment). On
 * Windows, real `OpenClipboard()`/`GetClipboardData()` reads resolve
 * synchronously instead -- see this
 * function's own Windows-specific branches below (PRIMARY has no real
 * equivalent there at all, so `clipboard == 0` is handled separately,
 * unconditionally, before any of the above). A no-op on any other
 * platform (nothing to convert a selection through).
 *
 * The image in-process fast path (`clipboard == 1` only, matching
 * FLTK's own `clipboard == 1 && ...`restriction -- an owned image
 * is never offered back out of the PRIMARY selection in-process) decodes
 * our own just-BMP-encoded `ownedImageBmp_[1]` back via
 * `fl.bmp_image.BMPImage`, the same decoder `fl.platform_x11`'s
 * `SelectionNotify` handler uses for an *external* owner's image reply
 * -- one decoder, two callers, rather than porting a second bespoke
 * `own_bmp_to_RGB()`.
 */
void paste(Widget receiver, int clipboard, string type = clipboardPlainText)
{
    if (receiver is null) return;

    version (Windows)
    {
        // Windows has no real PRIMARY selection to fall back to --
        // matches FLTK's own `Fl_WinAPI_Screen_Driver::paste()`,
        // whose very first check is the unconditional `if (!clipboard
        // || ...)`: PRIMARY (`clipboard == 0`) *always* resolves from
        // this process's own local buffer, regardless of
        // `weOwnSelection_[0]`, since there's no possible external
        // owner to ask on this platform. Dispatches nothing at all if
        // nothing was ever `copy(..., 0)`-ed, matching FLTK's own
        // `if (i == 0L) { Fl::e_text = 0; return; }` early return.
        if (clipboard == 0)
        {
            if (type == clipboardPlainText && primarySelection_ !is null)
            {
                auto savedText = eText_;
                auto savedType = eClipboardType_;
                eText_ = primarySelection_;
                eClipboardType_ = clipboardPlainText;
                receiver.handle(Event.paste);
                eText_ = savedText;
                eClipboardType_ = savedType;
            }
            return;
        }
    }

    if (type == clipboardPlainText && weOwnSelection_[clipboard]
        && selectionType_[clipboard] == clipboardPlainText)
    {
        string text = clipboard ? clipboardBuffer_ : primarySelection_;
        auto savedText = eText_;
        auto savedType = eClipboardType_;
        eText_ = text;
        eClipboardType_ = clipboardPlainText;
        receiver.handle(Event.paste);
        eText_ = savedText;
        eClipboardType_ = savedType;
        return;
    }

    if (clipboard == 1 && type == clipboardImage && weOwnSelection_[1]
        && selectionType_[1] == clipboardImage)
    {
        auto img = new BMPImage("clipboard", ownedImageBmp_[1]);
        auto savedData = eClipboardData_;
        auto savedType = eClipboardType_;
        eClipboardData_ = img.fail() ? null : img;
        eClipboardType_ = clipboardImage;
        receiver.handle(Event.paste);
        eClipboardData_ = savedData;
        eClipboardType_ = savedType;
        return;
    }

    version (linux)
    {
        pendingPasteReceiver_ = receiver;
        if (type == clipboardImage)
            platformX11.requestSelectionImage(clipboard);
        else
            platformX11.requestSelection(clipboard);
    }

    // Reached only for clipboard == 1 here (clipboard == 0 already
    // returned above) -- unlike X11's genuinely asynchronous
    // XConvertSelection()/SelectionNotify round trip, real Win32
    // clipboard reads (OpenClipboard()/GetClipboardData()) are plain
    // synchronous calls, so fl.platform_win32 resolves and returns the
    // data directly rather than firing a request and waiting for a
    // later message -- deliverPaste()/deliverPasteImage() still do the
    // actual dispatch (same bracketing/restore logic either platform
    // uses), just called immediately instead of from a WM_* handler.
    version (Windows)
    {
        pendingPasteReceiver_ = receiver;
        if (type == clipboardImage)
        {
            // `decodeEnhMetaFileClip()`'s own doc comment needs the
            // receiving widget's screen to convert a `CF_ENHMETAFILE`
            // clipboard entry's `.01mm` logical units to FLTK units at
            // the right GUI scale -- matching FLTK's own
            // `receiver.top_window()` lookup exactly. `0` (screen 0)
            // whenever `receiver` has no window yet, same fallback
            // FLTK's own null-`top_window()` case would hit too.
            auto topWin = receiver.topWindow();
            int screenNum = topWin !is null ? topWin.screenNum() : 0;
            deliverPasteImage(platformWin32.pasteImage(screenNum));
        }
        else
            deliverPaste(platformWin32.pasteText());
    }
}

/**
 * package(fl): called by fl.platform_x11's SelectionNotify handler once
 * the real X11 selection owner (another app, or nobody at all) replies
 * with the requested text -- `text` is null if the conversion failed
 * (no current owner, or it declined/couldn't produce text). Delivers
 * FL_PASTE to whichever widget's paste() call is still pending, matching
 * FLTK's own `Fl::e_text = ...; Fl::e_length = ...;
 * receiver->handle(FL_PASTE);` inside its `case SelectionNotify:`.
 */
package(fl) void deliverPaste(string text)
{
    Widget receiver = pendingPasteReceiver_;
    pendingPasteReceiver_ = null;
    if (receiver is null) return;

    auto savedText = eText_;
    auto savedType = eClipboardType_;
    eText_ = text is null ? "" : text;
    eClipboardType_ = clipboardPlainText;
    receiver.handle(Event.paste);
    eText_ = savedText;
    eClipboardType_ = savedType;
}

/**
 * The image counterpart to deliverPaste() -- called by
 * fl.platform_x11's SelectionNotify handler once an image paste()
 * request has been negotiated and its data decoded (or failed to
 * decode/negotiate, in which case `img` is null). `img` is typed
 * `Object` purely to keep this module free of an `fl.image` import for
 * one narrow use; callers cast `eventClipboard()` to `RGBImage`,
 * matching FLTK's own `void*`-cast-to-`Fl_RGB_Image*` convention.
 * Mirrors FLTK's own `int retval = receiver->handle(FL_PASTE); if
 * (!retval ...) delete (Fl_RGB_Image*)Fl::e_clipboard_data;` -- this
 * port has no explicit `delete` to perform (the GC owns the image
 * either way), so a declined paste (`handle()` returns 0) just drops
 * the reference by restoring the saved value below, same as every
 * other field this function brackets around the `handle()` call.
 */
package(fl) void deliverPasteImage(Object img)
{
    Widget receiver = pendingPasteReceiver_;
    pendingPasteReceiver_ = null;
    if (receiver is null) return;

    auto savedData = eClipboardData_;
    auto savedType = eClipboardType_;
    eClipboardData_ = img;
    eClipboardType_ = clipboardImage;
    receiver.handle(Event.paste);
    eClipboardData_ = savedData;
    eClipboardType_ = savedType;
}

/// package(fl): called by fl.platform_x11's SelectionClear handler when
/// another app takes ownership of a selection we used to own -- mirrors
/// FLTK's own `case SelectionClear: fl_i_own_selection[...] = 0;`.
package(fl) void clearSelectionOwnership(int clipboard)
{
    weOwnSelection_[clipboard] = false;
}

/// package(fl): called by `fl.platform_win32.updateClipboard()` right
/// after a successful `SetClipboardData()` -- mirrors FLTK's own
/// defensive `fl_i_own_selection[1] = 1;` reassert in
/// `fl_update_clipboard()` (`Fl_win32.cxx`), guarding against Windows
/// having synchronously delivered a `WM_DESTROYCLIPBOARD` mid-call (via
/// our own `EmptyClipboard()`), which would otherwise have already
/// cleared this flag out from under the copy that just claimed it.
package(fl) void markSelectionOwned(int clipboard)
{
    weOwnSelection_[clipboard] = true;
}

/// package(fl): called by `fl.platform_x11.dnd()`'s same-process-drop
/// branch, mirroring FLTK's own defensive `fl_i_own_selection[0] =
/// 1;` right before it triggers the local `paste()` -- belt-and-braces
/// for a drag started without an immediately-preceding `copy()` call
/// (in practice `copy()` already set this, since `dnd()` only ever
/// carries whatever `copy()` most recently placed in PRIMARY).
package(fl) void markPrimaryOwned()
{
    weOwnSelection_[0] = true;
}

/// package(fl): called by `fl.platform_x11`'s `XdndDrop` handler right
/// before it fires the real `XConvertSelection()` request for the
/// drop's payload -- mirrors FLTK's own `fl_selection_requestor =
/// Fl::belowmouse();`. Whatever widget is `belowmouse()` at drop time
/// is the one `deliverPaste()` will later deliver `Event.paste` to,
/// once the `SelectionNotify` reply arrives, same mechanism `paste()`
/// itself uses for an ordinary (non-DND) paste.
package(fl) void setPendingPasteReceiver(Widget w)
{
    pendingPasteReceiver_ = w;
}

/// package(fl): fl.platform_x11's SelectionRequest handler needs our
/// current contents to answer another app's conversion request.
package(fl) string clipboardContents(int clipboard)
{
    return clipboard ? clipboardBuffer_ : primarySelection_;
}

/// package(fl): which kind of data (`clipboardPlainText`/
/// `clipboardImage`) `clipboard`'s owned selection currently holds --
/// fl.platform_x11's `SelectionRequest` handler needs this to decide
/// which `TARGETS` to advertise and how to answer a target request.
package(fl) string selectionOwnedType(int clipboard)
{
    return selectionType_[clipboard];
}

/// package(fl): the pre-encoded BMP bytes behind an owned *image*
/// selection (`copyImage()`) -- fl.platform_x11's `SelectionRequest`
/// handler serves these back verbatim for an `image/bmp` target
/// request.
package(fl) const(ubyte)[] ownedImageBmpBytes(int clipboard)
{
    return ownedImageBmp_[clipboard];
}

/// package(fl): fl.platform_x11's clipboard-change polling needs to
/// know whether *this process* already owns a given selection, to
/// skip requesting its own timestamp back from the X server (mirrors
/// FLTK's own `if (!fl_i_own_selection[...])` guards in
/// `poll_clipboard_owner()`).
package(fl) bool weOwnSelection(int clipboard)
{
    return weOwnSelection_[clipboard];
}

/**
 * Ported from Fl::clipboard_contains(const char*). Returns whether the
 * CLIPBOARD selection currently holds data of the given `type`
 * (`clipboardPlainText` or `clipboardImage`) -- both can be true at
 * once (an owner can offer text and image forms of the same data), so
 * this genuinely answers "does it contain this type", not "is this the
 * only type". If this process owns the selection, answered instantly
 * from `weOwnSelection_`/the local buffer's own type (always
 * `clipboardPlainText` here -- see paste()'s own doc comment on why an
 * owned selection is never an image in this port). Otherwise forwards
 * to fl.platform_x11's real, synchronous X11 query (see that function's
 * own doc comment for a real caveat worth reading before calling this
 * from anywhere latency-sensitive) or, on Windows, to
 * fl.platform_win32's `IsClipboardFormatAvailable()`-based query
 * query.
 */
bool clipboardContains(string type)
{
    if (weOwnSelection_[1])
        return type == clipboardPlainText;

    version (linux)
        return platformX11.clipboardContains(type);
    else version (Windows)
        return platformWin32.clipboardContains(type);
    else
        return false;
}

alias ClipboardNotifyHandler = void delegate(int source);

private ClipboardNotifyHandler[] clipNotifyHandlers_;

/**
 * Ported from Fl::add_clipboard_notify(Fl_Clipboard_Notify_Handler,
 * void*). `h` is called with `source` (0 = selection buffer, 1 =
 * clipboard) whenever *another* application changes the selection or
 * clipboard -- not for this process's own copy()/paste() calls. A
 * plain D delegate, not FLTK's function-pointer-plus-`void*`-data
 * pair (matching CONVENTIONS.md's established callback substitution); a
 * caller needing per-registration data just captures it in the
 * delegate's closure. Removes any pre-existing identical registration
 * first, matching FLTK's own de-dup-via-remove-then-add. Real,
 * event-driven notification on both Linux (Xfixes/polling hybrid, see
 * `fl.platform_x11.clipboardNotifyChange()`) and Windows (the classic
 * clipboard-viewer chain, see `fl.platform_win32.clipboardNotifyChange()`).
 */
void addClipboardNotify(ClipboardNotifyHandler h)
{
    removeClipboardNotify(h);
    clipNotifyHandlers_ = h ~ clipNotifyHandlers_;
    version (linux) platformX11.clipboardNotifyChange();
    version (Windows) platformWin32.clipboardNotifyChange();
}

/// Ported from Fl::remove_clipboard_notify(Fl_Clipboard_Notify_Handler).
void removeClipboardNotify(ClipboardNotifyHandler h)
{
    auto before = clipNotifyHandlers_.length;
    ClipboardNotifyHandler[] kept;
    foreach (handler; clipNotifyHandlers_)
        if (handler != h) kept ~= handler;
    clipNotifyHandlers_ = kept;
    if (kept.length != before)
    {
        version (linux) platformX11.clipboardNotifyChange();
        version (Windows) platformWin32.clipboardNotifyChange();
    }
}

/// package(fl): mirrors FLTK's own `fl_clipboard_notify_empty()`
/// (Fl.cxx) -- fl.platform_x11's polling stops (or never starts) once
/// nobody is listening.
package(fl) bool clipboardNotifyEmpty()
{
    return clipNotifyHandlers_.length == 0;
}

/// package(fl): mirrors FLTK's own `fl_trigger_clipboard_notify(int)`
/// (Fl.cxx) -- called by fl.platform_x11 once it detects the selection
/// or clipboard's ownership timestamp actually changed.
package(fl) void triggerClipboardNotify(int source)
{
    foreach (handler; clipNotifyHandlers_)
        handler(source);
}

bool eventShift() { return (eState_ & stateShift) != 0; }
bool eventCtrl() { return (eState_ & stateCtrl) != 0; }
bool eventCommand() { return (eState_ & stateCommand) != 0; }
bool eventAlt() { return (eState_ & stateAlt) != 0; }

EventState eventButtons() { return eState_ & stateButtons; }
bool eventButton1() { return (eState_ & stateButton1) != 0; }
bool eventButton2() { return (eState_ & stateButton2) != 0; }
bool eventButton3() { return (eState_ & stateButton3) != 0; }
bool eventButton4() { return (eState_ & stateButton4) != 0; }
bool eventButton5() { return (eState_ & stateButton5) != 0; }

/// True if event_x()/event_y() falls inside the (x,y,w,h) rectangle.
bool eventInside(int x, int y, int w, int h)
{
    int mx = eX_ - x;
    int my = eY_ - y;
    return mx >= 0 && mx < w && my >= 0 && my < h;
}

/// True if event_x()/event_y() falls inside widget o's bounding box.
/// See the FLTK doc's restriction: only valid for a widget in the
/// same window that's handling the current event, with no intervening
/// subwindow.
bool eventInside(const(Widget) o)
{
    int mx = eX_ - o.x;
    int my = eY_ - o.y;
    return mx >= 0 && mx < o.w && my >= 0 && my < o.h;
}

/**
 * Tests the current event (which must be FL_KEYBOARD or FL_SHORTCUT)
 * against a shortcut value as described by Fl_Button::shortcut(): a
 * keysym OR'd with required shift-state flags. Not to be confused with
 * Widget.testShortcut(), which tests a widget's '&x'-in-label shortcut
 * instead of an explicit shortcut() value.
 */
bool testShortcut(uint shortcut)
{
    if (shortcut == 0) return false;

    uint v = shortcut & keyMask;
    import std.uni : toLower;
    // If the key portion is upper-case, Shift is implicitly required
    // even if the caller didn't OR in stateShift explicitly.
    if (cast(uint) toLower(cast(dchar) v) != v)
        shortcut |= stateShift;

    uint shift = eState_;
    // 0x7fff0000: every shift/modifier-state bit (FL_SHIFT..FL_BUTTON5),
    // matching FLTK's literal mask in Fl::test_shortcut().
    enum uint allShiftMask = 0x7fff0000;

    // Any required shift flag that's off is a mismatch.
    if ((shortcut & shift) != (shortcut & allShiftMask)) return false;
    uint mismatch = (shortcut ^ shift) & allShiftMask;
    // Meta/Alt/Ctrl must always match exactly; Shift is allowed to be
    // "wrong" if the event's first character still matches (below).
    if (mismatch & (stateMeta | stateAlt | stateCtrl)) return false;

    uint key = shortcut & keyMask;

    // If Shift also matches, an exact keysym match is enough.
    if (!(mismatch & stateShift) && key == cast(uint) eKeysym_) return true;

    // Otherwise try matching the first character of event_text(),
    // ignoring shift -- this lets punctuation shortcuts like '#' work
    // rather than having to spell it "shift+3" (US keyboard layout).
    import std.utf : decode;
    dchar firstChar = 0;
    if (eText_.length > 0)
    {
        size_t idx = 0;
        firstChar = decode(eText_, idx);
    }
    if (!(shift & stateCapsLock) && key == cast(uint) firstChar) return true;

    // Kludge so Ctrl+'_' works (as opposed to Ctrl+'^_').
    if ((shift & stateCtrl) && key >= 0x3f && key <= 0x5f && firstChar == (key ^ 0x40))
        return true;

    return false;
}

/// Localizable modifier-key names used by flShortcutLabel(). Ported
/// from fl_local_ctrl/fl_local_alt/fl_local_shift/fl_local_meta
/// (src/Fl.cxx), which forward to Fl::system_driver()->control_name()/
/// etc. -- "Ctrl"/"Alt"/"Shift"/"Meta" on every platform this port
/// targets (see the module comment above for why). Reassign to
/// retarget a different language, same as FLTK.
string flLocalCtrl = "Ctrl";
string flLocalAlt = "Alt"; /// ditto
string flLocalShift = "Shift"; /// ditto
string flLocalMeta = "Meta"; /// ditto

/// Appends a trailing separator to a modifier key name, unless the
/// name already ends in one -- ported verbatim from the static helper
/// add_modifier_key() (src/fl_shortcut.cxx), minus the fixed-size-
/// buffer overflow handling that function needed and a D string
/// doesn't.
private string addModifierKeySeparator(string name)
{
    if (name.length == 0) return name;
    if (name[$ - 1] == '\\') return name[0 .. $ - 1];
    if (name[$ - 1] == '+') return name;
    return name ~ "+";
}

/// The platform hook behind flShortcutLabel(): names key (a keysym),
/// or returns null if it isn't worth naming (the caller falls back to
/// the uppercased character itself). Forwards to fl.platform_x11's
/// keyName() (XKeysymToString()) or fl.platform_win32's (FLTK's
/// generic key-name table).
private string platformKeyName(uint key)
{
    version (linux) return platformX11.keyName(key);
    else version (Windows) return platformWin32.keyName(key);
    else return null;
}

/**
 * Returns a human-readable string for a shortcut value, e.g.
 * "Ctrl+Alt+F1". Ported from fl_shortcut_label(unsigned int)
 * (src/fl_shortcut.cxx) -- see the module comment above for which
 * overload and what's simplified.
 */
string flShortcutLabel(uint shortcut)
{
    string keyPart;
    return flShortcutLabel(shortcut, keyPart);
}

/**
 * 2-arg overload matching `fl_shortcut_label(unsigned int, const char
 * **eom)` (src/fl_shortcut.cxx): returns the same full label as the
 * 1-arg form above, and additionally sets `keyPart` to just the
 * substring *after* all modifier names -- FLTK's `eom` ("end of
 * modifiers") is a pointer into its own single static buffer marking
 * that same split point. Used by `fl.menu_popup`'s shortcut-text
 * drawing (the `Menu_Window::draw_shortcut()` equivalent) to right-
 * justify the modifier names and left-justify the key name in two
 * separate columns, matching FLTK's layout exactly.
 */
string flShortcutLabel(uint shortcut, out string keyPart)
{
    if (shortcut == 0) { keyPart = ""; return ""; }

    uint key = shortcut & keyMask;
    import std.uni : toLower;
    // Same "upper-case key implies Shift" fixup as testShortcut().
    if (cast(uint) toLower(cast(dchar) key) != key)
        shortcut |= stateShift;

    string modifiers;
    if (shortcut & stateCtrl) modifiers ~= addModifierKeySeparator(flLocalCtrl);
    if (shortcut & stateAlt) modifiers ~= addModifierKeySeparator(flLocalAlt);
    if (shortcut & stateShift) modifiers ~= addModifierKeySeparator(flLocalShift);
    if (shortcut & stateMeta) modifiers ~= addModifierKeySeparator(flLocalMeta);

    keyPart = platformKeyName(key);
    if (keyPart.length == 0)
    {
        import std.uni : toUpper;
        import std.utf : encode;

        dchar c = toUpper(cast(dchar) key);
        char[4] buf;
        size_t n = encode(buf, c);
        keyPart = buf[0 .. n].idup;
    }
    return modifiers ~ keyPart;
}

private int scrollbarSize_ = 16;

/**
 * The default width (in pixels) of scrollbar troughs for any widget
 * that doesn't override it with its own explicit instance-level
 * scrollbar size (`fl.scroll.Scroll.scrollbarSize(int)`,
 * `fl.text_display`'s `scrollbarSize(int)`, ...). Ported from
 * `Fl::scrollbar_size()`/`Fl::scrollbar_size(int)` (src/Fl.cxx); the
 * default matches FLTK's own `scrollbar_size_ = 16` initializer.
 * `fl.text_display` takes its default scrollbar size from this.
 */
int scrollbarSize() { return scrollbarSize_; }
void scrollbarSize(int w) { scrollbarSize_ = w; } /// ditto

private int menuLinespacing_ = 4;

/**
 * Extra vertical padding (in pixels) added to every menu item's
 * measured height when laying out a popup/menu-bar's rows. Ported from
 * `Fl::menu_linespacing()`/`Fl::menu_linespacing(int)` (`src/Fl.cxx`,
 * "STR #2927") -- the default (4) matches FLTK's own
 * `menu_linespacing_ = 4` initializer, which itself replaced a
 * hardcoded local macro (`LEADING`) in `Fl_Menu.cxx` once it became
 * user-configurable. `fl.menu_popup.MenuWindow.rowHeight()` reads this
 * global rather than a hardcoded `+4`.
 */
int menuLinespacing() { return menuLinespacing_; }
void menuLinespacing(int h) { menuLinespacing_ = h; } /// ditto

private Widget grabWidget_;

/**
 * Ported from Fl::grab(Fl_Widget*)/Fl::grab() (src/Fl_grab.cxx). "Grab
 * is done while menu systems are up" (FLTK's own comment) -- while
 * a grab is active, focus()/belowmouse() below become no-ops (matching
 * FLTK's `if (grab()) return;` guards).
 *
 * `grab(Widget)` is backed by a **real** `XGrabPointer()`/
 * `XGrabKeyboard()` (`fl.platform_x11.grabPointer()`/`ungrabPointer()`),
 * matching FLTK's own `Fl_X11_Screen_Driver::grab()` -- both with
 * `owner_events=True`, so events over any of *this app's own* windows
 * still route normally (nothing needed there), while events outside
 * all of them -- another application, or the window manager's own
 * root-window click handling (e.g. a virtual-desktop-switch gesture) --
 * get redirected to the grab window instead of reaching their normal
 * destination. That's what makes an open menu genuinely exclusive at
 * the OS level, matching real desktop apps generally (confirmed
 * interactively: this is exactly why a window manager like fvwm can't
 * switch virtual desktops while any app's menu, including its own, is
 * open). NOTE this does *not*, by itself, prevent a click on a
 * *sibling* menu-triggering widget in this same app (e.g. clicking
 * "File" on a menu bar while "Edit"'s dropdown is already open) from
 * delivering normally to that sibling's own window --
 * `owner_events=True` means it still does, matching FLTK exactly --
 * so callers that need to detect "a menu is already active and the
 * user clicked a different trigger" (`fl.menu_bar`/`fl.menu_popup`)
 * still need their own explicit handling for that case; the grab's job
 * is purely the outside-the-app exclusivity.
 *
 * **Reserved for genuine single-widget grab-owners like popup menus**
 * (`fl.menu_popup`), matching FLTK exactly: FLTK's own real
 * modal dialogs (`Fl_Message`, the base of `message()`/`alert()`/
 * `fl_input()`/`password()`) never call this at all -- they rely on
 * the separate `modal()` mechanism below instead (confirmed via direct
 * source reading: `Fl_Message::innards()` only *clears* any pre-existing
 * grab before showing, and restores it afterward, never establishes one
 * of its own). `fl.ask`'s dialogs originally misused `grab()` as a
 * modal substitute here; that caused several real, reported bugs
 * (duplicate dialogs from an incomplete redirect, a "Cancel" button
 * accepting input from an over-broad one, and a stuck hover cursor from
 * `belowmouse()`'s guard above never fitting a dialog with real child
 * widgets) before being replaced with the faithful `modal()` port --
 * see that function's own doc comment.
 */
Widget grab()
{
    return grabWidget_;
}

/// ditto
void grab(Widget win)
{
    grabWidget_ = win;
    if (win !is null)
    {
        auto w = win.asWindow();
        version (linux) if (w !is null) platformX11.grabPointer(w);
    }
    else
    {
        version (linux) platformX11.ungrabPointer();
    }
    // Ungrabbing: FLTK calls fl_fix_focus() here to reconcile focus()
    // with whatever window X now reports as focused, since a real grab
    // can let that drift out of sync. This port's focus()/belowmouse()
    // guards above mean focus_ is never mutated at all while grabbed, so
    // there's nothing to reconcile -- it already still points at
    // whatever had focus before the grab started.
}

private Widget modalWidget_;

/**
 * The current topmost modal window, or null. Ported from `Fl::modal_`/
 * `Fl::modal()` (`Fl.cxx`/`Fl.H`) -- **not** the same thing as
 * `fl.window.Window.modal()` (the per-window flag saying "I *would*
 * enforce exclusivity if shown", pure bookkeeping with zero side
 * effects on its own). This is the actual, currently-enforced global
 * state, mirroring the real `Fl_Window *Fl::modal_` pointer.
 *
 * Unlike `grab()`, there is no public setter here, matching FLTK
 * exactly (`Fl::modal()` is getter-only in `FL/Fl.H`) -- it's set and
 * cleared automatically as a side effect of showing/hiding a window
 * whose `modal()` flag is set, by `fl.platform_x11`'s `createWindow()`/
 * `destroyWindow()` (matching FLTK's own `Fl_X::set_xid()`/
 * `Fl_Window_Driver::hide_common()`, both deep in the X11-specific
 * window-creation/destruction path -- not `Fl_Window::show()`/`hide()`
 * themselves, which FLTK keeps free of modal-specific code, same
 * as this port's `fl.window.Window.show()`/`hide()`).
 *
 * `fl.core.handle()`'s `Event.push`/`move`/`drag`/`release`/`shortcut`/
 * `mouseWheel`/`close` cases all check this (see that function's own
 * doc comment), and `fixFocus()` pins keyboard focus inside it while
 * it's set -- together, this is what makes a real `fl.ask` dialog
 * genuinely exclusive: clicks/hover/keystrokes/close-button-presses
 * aimed at any *other* window belonging to this app are discarded or
 * redirected, without ever touching the X server itself (no
 * `XGrabPointer()`/`XGrabKeyboard()` involved, matching FLTK's own
 * design precisely -- confirmed via live testing of real FLTK's
 * `test/editor.cxx`/`test/colbrowser.cxx`: other applications, virtual
 * desktop switching, and window-manager operations are all completely
 * unaffected by an open modal dialog).
 */
Widget modal()
{
    return modalWidget_;
}

/// package(fl): only fl.platform_x11's createWindow()/destroyWindow()
/// should call this -- see modal()'s own doc comment for why there's
/// no public setter, matching FLTK.
package(fl) void modal(Widget win)
{
    modalWidget_ = win;
}

/**
 * The first (most-recently-shown, or most-recently-made-`first`) top-
 * level window in the list of shown() windows, or null if none are
 * shown. If a modal() window is shown, this is always it -- see
 * `firstWindow(Window)`'s own doc comment for why. Ported from
 * `Fl::first_window()` (`Fl.cxx`); backed by `fl.platform_x11`'s own
 * internal shown-window list (`first_`/`WindowRecord.next`), the direct
 * equivalent of FLTK's `Fl_X::first`.
 *
 * Returns `Window`, not the generic `Widget`, so callers don't need
 * an explicit cast -- matches FLTK's own
 * `Fl_Window* first_window()` exactly, and `firstWindowWidget()`
 * already only ever returns a real `Window` underneath.
 */
CoreWindow firstWindow()
{
    version (linux) return platformX11.firstWindowWidget();
    else version (Windows) return platformWin32.firstWindowWidget();
    else return null;
}

/**
 * The next top-level window after `window` in the list of shown()
 * windows, or null if `window` is the last one (or isn't shown at
 * all). Ported from `Fl::next_window()` (`Fl.cxx`) -- FLTK calls
 * `Fl::error()` when `window` isn't shown; this port has no such
 * mechanism (see this port's established "no `Fl::error()` equivalent"
 * gap, same as elsewhere), so it just returns null instead.
 */
CoreWindow nextWindow(CoreWindow window)
{
    version (linux) return window !is null ? platformX11.nextWindowWidget(window) : null;
    else version (Windows) return window !is null ? platformWin32.nextWindowWidget(window) : null;
    else return null;
}

/// Hides every currently-shown top-level window. Ported from
/// `Fl::hide_all_windows()` (`Fl.cxx`) verbatim: repeatedly hides
/// `firstWindow()` until none remain shown.
void hideAllWindows()
{
    while (firstWindow() !is null) firstWindow().hide();
}

/// Redraws every currently-shown top-level window -- ported from
/// `Fl::redraw()` (`Fl.cxx`) verbatim, walking the same `firstWindow()`/
/// `nextWindow()` list `hideAllWindows()`/`reloadScheme()` already do.
/// Useful after a global state change with no single owning widget
/// (e.g. a `setColor()`/`background()`/`foreground()` call, whose
/// effect every widget's next repaint needs to pick up).
void redraw()
{
    for (auto w = firstWindow(); w !is null; w = nextWindow(w))
        w.redraw();
}

/**
 * Sets the window `firstWindow()` returns: moves it to the front of
 * the shown-window list. A no-op if `window` is null or not shown(),
 * or if modal() is currently active (moving a window to the front
 * while a modal dialog is open would incorrectly let it compete with
 * the modal window for "first" status -- matching FLTK's own
 * comment: "this is not done if modal is true to avoid messing up
 * modal stack"). Ported from `Fl::first_window(Fl_Window*)` (`Fl.cxx`,
 * via `Fl_Window_Driver::find()`'s reordering side effect). Because the
 * first window is used to set the "parent" of modal windows, this is
 * often useful for e.g. `Fl_Menu_::global()` (see `fl.menu_`'s row).
 */
void firstWindow(CoreWindow window)
{
    if (window is null || !window.shown()) return;
    version (linux) platformX11.makeWindowFirst(window);
    else version (Windows) platformWin32.makeWindowFirst(window);
}

// ---------------------------------------------------------------------
// Global event/system handlers and the custom dispatch hook
// (FL/core/function_types.H's Fl_Event_Handler/Fl_System_Handler/
// Fl_Event_Dispatch, and FL/core/events.H's add_handler()/
// add_system_handler()/event_dispatch() family, src/Fl.cxx).
// ---------------------------------------------------------------------

/// Ported from `Fl_Event_Handler` (`int (*)(int event)`,
/// `FL/core/function_types.H`) -- a D delegate instead of a bare C
/// function pointer, per this project's usual callback convention (a
/// delegate already carries its own captured context, so there's
/// nothing else to port from the FLTK typedef).
alias EventHandler = int delegate(Event event);

/// Ported from `Fl_System_Handler` (`int (*)(void *event, void *data)`)
/// -- collapsed to a single-parameter delegate the same way, since the
/// `data` FLTK threads through separately is exactly what a D
/// delegate's own closure already provides. `event` stays a raw
/// `void*` (unlike every other event type in this port) because it
/// genuinely is platform-specific and untyped from `fl.core`'s own
/// point of view -- an `XEvent*` on Linux, matching FLTK's own
/// per-platform documented shape (`MSG*` on Windows, `NSEvent*` on
/// macOS -- neither exists in this port).
alias SystemHandler = int delegate(void* event);

/// Ported from `Fl_Event_Dispatch` (`int (*)(int event, Fl_Window *w)`).
alias EventDispatch = int delegate(Event event, Widget window);

private struct HandlerLink
{
    EventHandler handle;
    HandlerLink* next;
}

private HandlerLink* handlers_;

/**
 * Installs a function to parse otherwise-unrecognized events. If
 * nothing else claims an event, each registered handler is tried (most
 * recently added first) until one returns nonzero; if none do, the
 * event is ignored. Ported from `Fl::add_handler(Fl_Event_Handler)`
 * (`src/Fl.cxx`) -- this port's own `handle()` only reaches this for
 * `Event.shortcut` (an unclaimed shortcut key -- lets app code install
 * global accelerator keys) and `Event.mouseWheel` (a wheel event no
 * widget wanted), matching FLTK's own two real call sites exactly
 * (`send_handlers(FL_SHORTCUT)` in the `FL_SHORTCUT` case, and the
 * shared fallthrough tail `FL_MOUSEWHEEL` reaches via `default: break;`
 * in FLTK's C++ switch -- ported here as an explicit call instead,
 * see that case's own comment). FLTK's own doc comment lists
 * several other trigger events (`FL_SCREEN_CONFIGURATION_CHANGED`,
 * `FL_ZOOM_EVENT`, `FL_APP_ACTIVATE`/`FL_APP_DEACTIVATE`, unrecognized
 * system events) that don't exist as `Event` values in this port at
 * all yet -- nothing to wire up until those subsystems themselves are
 * ported.
 */
void addHandler(EventHandler ha)
{
    auto l = new HandlerLink;
    l.handle = ha;
    l.next = handlers_;
    handlers_ = l;
}

/**
 * Installs `ha` with the priority just lower than `before` (an
 * already-installed handler) -- i.e. `before` still gets first crack,
 * `ha` runs immediately after it. Ported from `Fl::add_handler
 * (Fl_Event_Handler, Fl_Event_Handler)`. Falls back to `addHandler(ha)`
 * if `before` isn't null but isn't found (also matching FLTK: a
 * `before` of `null` is treated the same as the 1-arg overload; not
 * found at all is silently a no-op for the *insertion*, matching
 * FLTK's own `while (l) {...}` falling off the end without
 * inserting anything -- FLTK doesn't call the 1-arg overload in
 * that case either, so this doesn't either).
 */
void addHandler(EventHandler ha, EventHandler before)
{
    if (before is null) { addHandler(ha); return; }
    for (auto l = handlers_; l !is null; l = l.next)
    {
        if (l.handle is before)
        {
            auto q = new HandlerLink;
            q.handle = ha;
            q.next = l.next;
            l.next = q;
            return;
        }
    }
}

/// Returns the most recently installed handler (via either
/// `addHandler()` overload -- FLTK's own doc comment only mentions
/// the 1-arg form, but its implementation (`return handlers ?
/// handlers->handle : NULL;`) doesn't distinguish how the head of the
/// list got there either), or `null` if none are installed. Ported
/// from `Fl::last_handler()`.
EventHandler lastHandler()
{
    return handlers_ !is null ? handlers_.handle : null;
}

/// Removes a previously installed handler (found by delegate equality,
/// same convention as `fl.core.removeTimeout()`). Ported from
/// `Fl::remove_handler(Fl_Event_Handler)`.
void removeHandler(EventHandler ha)
{
    HandlerLink** pp = &handlers_;
    while (*pp !is null && (*pp).handle != ha)
        pp = &(*pp).next;
    if (*pp !is null) *pp = (*pp).next;
}

/// Ported from `send_handlers(int)` (`src/Fl.cxx`, `static`/file-scope
/// FLTK -- exposed here only to `handle()` in this same module, so
/// `private` rather than `package(fl)`).
private int sendHandlers(Event e)
{
    for (auto l = handlers_; l !is null; l = l.next)
        if (l.handle(e)) return 1;
    return 0;
}

private struct SystemHandlerLink
{
    SystemHandler handle;
    SystemHandlerLink* next;
}

private SystemHandlerLink* systemHandlers_;

/**
 * Installs a function to intercept **raw** system events, before
 * FLTK's own translation into its `Event`/`handle()` model even runs.
 * Called for every new system event (most recently added first) until
 * one returns nonzero, at which point FLTK's own normal handling of
 * that raw event is skipped entirely. Ported from
 * `Fl::add_system_handler(Fl_System_Handler, void*)` -- the `void*
 * data` parameter collapses into the delegate's own closure, same
 * substitution `EventHandler`/`SystemHandler` above already make.
 * `event` is a raw `XEvent*` on Linux (see `SystemHandler`'s own doc
 * comment) -- called from `fl.platform_x11`'s own raw `XNextEvent()`
 * loop via `sendSystemHandlers()` below, matching FLTK's exact
 * call site (`Fl_x.cxx`'s `do_queued_events()`, right after
 * `XNextEvent()` and before `fl_handle(xevent)`).
 */
void addSystemHandler(SystemHandler ha)
{
    auto l = new SystemHandlerLink;
    l.handle = ha;
    l.next = systemHandlers_;
    systemHandlers_ = l;
}

/// Removes a previously installed system handler (found by delegate
/// equality). Ported from `Fl::remove_system_handler(Fl_System_Handler)`.
void removeSystemHandler(SystemHandler ha)
{
    SystemHandlerLink** pp = &systemHandlers_;
    while (*pp !is null && (*pp).handle != ha)
        pp = &(*pp).next;
    if (*pp !is null) *pp = (*pp).next;
}

/// Ported from `fl_send_system_handlers(void*)` (`src/Fl.cxx`, a free
/// function FLTK since platform-driver code outside the `Fl`
/// namespace needs to call it -- `package(fl)` here for the same
/// reason: only `fl.platform_x11`'s raw event loop calls this).
/// Returns nonzero if a handler consumed `event` (the caller should
/// skip its own normal translation/dispatch of it in that case).
package(fl) int sendSystemHandlers(void* event)
{
    for (auto l = systemHandlers_; l !is null; l = l.next)
        if (l.handle(event)) return 1;
    return 0;
}

private EventDispatch eventDispatch_;

/// The current custom event dispatch function, or `null` if none is
/// installed. Ported from `Fl::event_dispatch()` (getter).
EventDispatch eventDispatch()
{
    return eventDispatch_;
}

/// Installs (or, passing `null`, removes) a custom event dispatch
/// function that wraps every call to `dispatch()` below -- e.g. to add
/// an app-wide exception boundary around FLTK's own event handling.
/// Ported from `Fl::event_dispatch(Fl_Event_Dispatch)` (setter).
void eventDispatch(EventDispatch d)
{
    eventDispatch_ = d;
}

/**
 * The public event-dispatch entry point -- ported from `Fl::handle()`
 * (`FL/core/events.H`/`src/Fl.cxx`), which FLTK splits from the
 * real logic (`Fl::handle_()`, this module's own `handle()` below,
 * matching FLTK's `handle_()` one-for-one) purely so a custom
 * `eventDispatch()` hook can wrap it: `if (e_dispatch) return
 * e_dispatch(e, window); else return handle_(e, window);`. This port
 * originally collapsed the split entirely, since nothing installed a
 * dispatch hook yet -- now that `eventDispatch()` is real, `handle()`
 * itself stays exactly as it was (still directly callable, matching
 * FLTK keeping `handle_()` `FL_EXPORT`ed for a custom dispatcher to
 * call back into) and this thin wrapper is what `fl.platform_x11`
 * calls for every real, platform-originated event instead, so an
 * installed dispatcher actually gets a chance to intercept them.
 */
int dispatch(Event e, Widget window)
{
    return eventDispatch_ !is null ? eventDispatch_(e, window) : handle(e, window);
}

Widget focus()
{
    return focus_;
}

/**
 * Sets the widget receiving keyboard events. If it changes, every
 * ancestor of the previously-focused widget is sent FL_UNFOCUS (and
 * oldFocus() ends up set to the topmost one), matching FLTK. Now
 * skips this entirely while grab() is active (see that function's own
 * doc comment), matching FLTK's `if (grab()) return;` guard.
 *
 * Calls composeReset() when focus actually moves, as FLTK does. Not
 * ported: FLTK also requests/releases an on-screen keyboard through the
 * screen driver depending on needsKeyboard(), and makes sure the
 * focused widget's top-level window has native input focus via the
 * window driver (`take_focus()`); this port has neither a screen-driver
 * keyboard hook nor a window-driver focus step.
 */
void focus(Widget o)
{
    if (grab()) return;
    if (o !is null && !o.visibleFocus()) return;

    Widget p = focus_;
    if (o !is p)
    {
        composeReset();
        focus_ = o;
        oldFocus_ = null;
        auto savedEvent = eNumber_;
        eNumber_ = Event.unfocus;
        for (; p !is null; p = p.parent)
        {
            p.handle(Event.unfocus);
            oldFocus_ = p;
        }
        eNumber_ = savedEvent;
    }
}

/// The widget that was focused just before the last focus() change that
/// actually moved focus away from it; used by fl.group's handle() to
/// restore focus to the last-focused child on a fresh FL_FOCUS. Stand-in
/// for FLTK's `fl_oldfocus` extern global (set inside Fl::focus()).
package(fl) Widget oldFocus()
{
    return oldFocus_;
}

/**
 * Reconciles focus() with which top-level window X currently says has
 * input focus -- called from fl.platform_x11's FocusIn/FocusOut
 * handling. Ported from the focus-reconciling half of FLTK's
 * `fl_fix_focus()` (Fl.cxx) -- NOT the same as the generic
 * `Fl::handle(FL_FOCUS/FL_UNFOCUS, window)` dispatch: FLTK's own
 * `Fl::handle_()` never sends FL_FOCUS/
 * FL_UNFOCUS to a widget directly for these two cases -- it just
 * updates a `fl_xfocus` variable and calls `fl_fix_focus()`, which is
 * the *only* function that actually produces FL_FOCUS/FL_UNFOCUS
 * events, by calling focus() (this module's own function above),
 * which does the real work of walking the previously-focused widget's
 * ancestor chain sending FL_UNFOCUS. Skipping straight to
 * `Fl::handle(FL_UNFOCUS, window)`-style dispatch (routing to
 * fl.group's `FlGroup.handle()`, whose `case Event.unfocus` is only
 * bookkeeping -- recording `savedfocus_` from oldFocus() -- not an
 * actual unfocus notification) would never reach the truly-focused child
 * widget at all, so a widget's FL_UNFOCUS handler would never run
 * when switching away from the window entirely (only on-click
 * refocusing would work).
 *
 * `xfocusWindow` is the top-level window X says now has focus, or null
 * if none does (the whole application lost input focus). `modal()`
 * redirection is ported too: matches FLTK's `if (Fl::modal()) w =
 * Fl::modal();`, pinning focus inside the modal window's subtree
 * regardless of which window X itself reports as focused -- this is
 * also called directly by `fl.platform_x11.createWindow()` right after
 * a newly-shown modal window sets `modal()` (matching FLTK's own
 * call site inside `Fl_X::set_xid()`, immediately after `Fl::modal_` is
 * assigned), not just from real `FocusIn`/`FocusOut` events. Also
 * ported: the `if (grab()) return;` guard FLTK's `fl_fix_focus()`
 * has as its very first line (a real grab reconciles focus itself when
 * ungrabbing, see `grab(Widget)`'s own doc comment -- nothing here
 * should race with that). Not ported: the `e_keysym` save/restore
 * dance around `take_focus()` (guards against a stray keysym confusing
 * a widget's own shortcut-matching mid-focus-change; no widget in this
 * port inspects `eventKey()` inside its own `Event.focus` handler
 * today, so nothing depends on it yet -- revisit if one ever does).
 */
package(fl) void fixFocus(Widget xfocusWindow)
{
    if (grab() !is null) return;
    if (xfocusWindow !is null)
    {
        Widget w = xfocusWindow;
        while (w.parent !is null) w = w.parent;
        if (modal() !is null) w = modal();
        if (!w.contains(focus_))
            if (!w.takeFocus()) focus(w);
    }
    else
        focus(null);
}

/// The widget under the mouse cursor.
Widget belowmouse()
{
    return belowmouse_;
}

/**
 * Sets the widget under the mouse cursor. If it changes, every ancestor
 * of the previous belowmouse widget (that doesn't contain the new one)
 * is sent FL_LEAVE, matching FLTK. Does not send FL_ENTER to the
 * new widget -- that's a test of whether the widget wants the mouse,
 * done by sending FL_ENTER directly and checking the return value. Now
 * skips this entirely while grab() is active, matching FLTK's
 * `if (grab()) return;` guard.
 *
 * Sends `Event.dndLeave` instead of `Event.leave` while a drag-and-drop
 * operation is in progress (`dndFlag_`, ported from FLTK's
 * file-static `dnd_flag`, set/cleared by `handle()`'s own
 * `Event.dndEnter`/`dndDrag`/`dndLeave` cases) -- matches FLTK's
 * `e_number = dnd_flag ? FL_DND_LEAVE : FL_LEAVE;` exactly.
 */
void belowmouse(Widget o)
{
    if (grab()) return;
    Widget p = belowmouse_;
    if (o !is p)
    {
        belowmouse_ = o;
        auto savedEvent = eNumber_;
        eNumber_ = dndFlag_ ? Event.dndLeave : Event.leave;
        for (; p !is null && !p.contains(o); p = p.parent)
            p.handle(eNumber_);
        eNumber_ = savedEvent;

        // Centralizes what FLTK calls Fl_Tooltip::enter(belowmouse())
        // for separately at each of its own FL_ENTER/FL_MOVE/FL_LEAVE
        // call sites in Fl::handle_() (Fl.cxx) -- every one of those
        // ultimately changes belowmouse() (this setter is the one place
        // that actually happens), and Fl_Tooltip::enter_() is itself
        // idempotent when called again with the same widget (`if (tw ==
        // widget_) return;`), so hooking it here once has the identical
        // net effect without needing a matching case in fl.core.handle()
        // for each of those events individually.
        fl.tooltip.mouseEnter(o);
    }
}

/// The widget receiving FL_DRAG/FL_RELEASE events (and further FL_PUSH).
Widget pushed()
{
    return pushed_;
}

void pushed(Widget o)
{
    pushed_ = o;
}

/**
 * Test-only helper: resets every piece of process-wide mutable state
 * this module exposes -- event state, focus()/belowmouse()/pushed(),
 * the default callback queue backing readqueue(), and the active
 * scheme()/boxtype alias table -- back to its initial "nothing has
 * happened yet" condition. The scheme reset matters beyond fl.core's
 * own tests: scheme_/boxAlias_ are read on every drawBoxAt()/
 * drawRadio() call, so a test that leaves a scheme active (or a
 * failed assertion that skips the restore) would silently change
 * every other module's draw()-exercising test that runs afterward.
 *
 * All of that state is process-wide (module-level globals, matching
 * FLTK's own extern globals), so any unittest anywhere that
 * exercises a widget's handle()/doCallback() can leak into, or
 * inherit stale state from, a completely unrelated module's test.
 * This bit twice before a shared helper existed: once via
 * FlGroup.current_ leaking a stray parent into the next test's widget
 * construction, and once via a Valuator test leaving a widget on the
 * default callback queue that fl.widget's own readqueue() test then
 * popped instead of its own widget. Call this at the start and/or end
 * of any test that touches handle()/doCallback() through a real
 * widget -- see the hermetic-tests note in CONVENTIONS.md.
 */
package(fl) void resetForTest()
{
    focus(null);
    belowmouse(null);
    pushed(null);
    eNumber_ = Event.noEvent;
    eState_ = 0;
    eX_ = 0; eY_ = 0; eXRoot_ = 0; eYRoot_ = 0; eDx_ = 0; eDy_ = 0;
    eDxF_ = 0; eDyF_ = 0; eDxErr_ = 0.5f; eDyErr_ = 0.5f;
    eClicks_ = 0;
    eIsClick_ = false;
    eKeysym_ = 0;
    eOriginalKeysym_ = 0;
    eText_ = null;
    composeState_ = 0;
    timeouts_ = null;
    inTimeoutCallback_ = false;
    widgetWatchList_ = null;
    grabWidget_ = null;
    modalWidget_ = null;
    handlers_ = null;
    systemHandlers_ = null;
    eventDispatch_ = null;
    optionValues_ = optionDefaults_;
    // Deliberately `true`, not `false`: `option()`'s first real call
    // lazily reads the *actual* system/user `Fl_Preferences` files off
    // disk (`readOptions_()`), which is correct production behavior but
    // makes any test that just calls `option()` depend on whatever this
    // host machine's real FLTK-family preferences happen to contain —
    // hit for real when a stray `~/.config/fltk.org/fltk.prefs` with a
    // persisted `PrintUsesGTK:0` (written by some unrelated real FLTK
    // app run on the dev machine, not this port) made
    // `option(Option.printerUsesGtk)`'s own "starts at its documented
    // default" unittest fail. Marking options as already-read means a
    // reset test exercises the in-memory default table only, matching
    // this module's own "Shared static state needs hermetic tests"
    // convention (CONVENTIONS.md) — same category of ambient-state leak as
    // the `FlGroup.current()`/callback-queue cases that convention was
    // written for, just leaking from the real filesystem instead of
    // from a previous test.
    optionsRead_ = true;
    primarySelection_ = null;
    clipboardBuffer_ = null;
    ownedImageBmp_[] = null;
    selectionType_[] = clipboardPlainText;
    weOwnSelection_[] = false;
    pendingPasteReceiver_ = null;
    eClipboardData_ = null;
    eClipboardType_ = null;
    clipNotifyHandlers_ = null;
    fdEntries_ = null;
    idleHandlers_ = null;
    inIdle_ = false;
    awakeQueue_ = null;
    while (readqueue() !is null) {}
    scheme_ = null;
    boxAlias_ = identityBoxAlias();
}

CallbackReason callbackReason()
{
    return callbackReason_;
}

package(fl) void callbackReason(CallbackReason reason)
{
    callbackReason_ = reason;
}

// ---------------------------------------------------------------------
// Fl_Option / Fl::option() -- global FLTK-wide options
// (FL/core/options.H, src/Fl.cxx).
// ---------------------------------------------------------------------

/**
 * Ported from `Fl_Option` (`FL/core/options.H`). Enumerator for global
 * FLTK options -- FLTK's own doc comment: "can be set system wide,
 * per user, or for the running application only." All three tiers are
 * real (`option()`'s own doc comment has the full mechanism); the
 * enum itself and its defaults are ported faithfully, including options no
 * widget in this port consumes yet (there's no `Fl_Native_File_Chooser`/
 * `Fl_Printer`/scaling-zoom subsystem here) -- matching this project's
 * usual "port the full closed enum even before every consumer exists"
 * convention (`fl.enumerations`' `Cursor` does the same).
 */
enum Option
{
    arrowFocus,         /// OPTION_ARROW_FOCUS -- see fl.input's own use
    visibleFocus,       /// OPTION_VISIBLE_FOCUS -- see visibleFocus() below
    dndText,            /// OPTION_DND_TEXT -- see dndTextOps() below
    showTooltips,       /// OPTION_SHOW_TOOLTIPS -- see fl.tooltip.enabled()
    fnfcUsesGtk,        /// OPTION_FNFC_USES_GTK -- no Fl_Native_File_Chooser port yet
    fnfcUsesZenity,     /// OPTION_FNFC_USES_ZENITY -- ditto
    fnfcUsesKdialog,    /// OPTION_FNFC_USES_KDIALOG -- ditto
    printerUsesGtk,     /// OPTION_PRINTER_USES_GTK -- no Fl_Printer port yet
    showScaling,        /// OPTION_SHOW_SCALING -- see transientScaleDisplay() below
    simpleZoomShortcut, /// OPTION_SIMPLE_ZOOM_SHORTCUT -- see scaleHandler() below
}

/// Default value for each `Option`, matching FLTK's own system-
/// preferences defaults (`src/Fl.cxx`'s `opt_prefs.get("...", tmp, N)`
/// calls) -- used as `readOptions_()`'s own system-tier fallback when
/// no `Fl_Preferences` file exists yet (see that function's own doc
/// comment). **One deliberate exception**: `simpleZoomShortcut` defaults
/// to `true` here, not FLTK's own `false` (`OPTION_SIMPLE_ZOOM_
/// SHORTCUT` defaults off in real FLTK too, confirmed against `Fl.cxx`)
/// -- a deliberate project decision, not a porting gap, so that
/// Ctrl-`=` zooms in without needing Shift as well as Ctrl-Shift-`=`
/// (i.e. Ctrl-`+`) continuing to work -- see `scaleHandler()`'s own
/// doc comment for why the plain `+`-requiring path alone isn't
/// convenient on layouts where `+` needs Shift (nearly all of them).
private immutable bool[Option.max + 1] optionDefaults_ = [
    Option.arrowFocus: false,
    Option.visibleFocus: true,
    Option.dndText: true,
    Option.showTooltips: true,
    Option.fnfcUsesGtk: true,
    Option.fnfcUsesZenity: false,
    Option.fnfcUsesKdialog: false,
    Option.printerUsesGtk: true,
    Option.showScaling: true,
    Option.simpleZoomShortcut: true,
];

private bool[Option.max + 1] optionValues_ = optionDefaults_;
private bool optionsRead_ = false;

/// Preferences key name for each `Option`, matching FLTK's own
/// `opt_prefs.get("...", tmp, N)` key strings (`src/Fl.cxx`) exactly --
/// needed so a persisted override written by real FLTK (or
/// `fltk-options`) reads back correctly here too.
private immutable string[Option.max + 1] optionKeys_ = [
    Option.arrowFocus: "ArrowFocus",
    Option.visibleFocus: "VisibleFocus",
    Option.dndText: "DNDText",
    Option.showTooltips: "ShowTooltips",
    Option.fnfcUsesGtk: "FNFCUsesGTK",
    Option.fnfcUsesZenity: "UseZenity",
    Option.fnfcUsesKdialog: "UseKdialog",
    Option.printerUsesGtk: "PrintUsesGTK",
    Option.showScaling: "ShowZoomFactor",
    Option.simpleZoomShortcut: "SimpleZoomShortcut",
];

/**
 * Lazily reads the system-wide, then user-level, `Fl_Preferences`
 * database into `optionValues_`, matching `Fl::option(Fl_Option)`'s own
 * first-call block (`src/Fl.cxx`) exactly: the system tier supplies
 * every option's real default (there's always a value at this tier,
 * `optionDefaults_` mirrors it for when the file doesn't exist yet),
 * then the user tier overrides only the options actually present there
 * (a missing key's `get()` default of `-1` leaves the system value
 * alone -- FLTK's own "only override if set (>= 0)" comment).
 * `fl.preferences.Root.get()` on a nonexistent file/key is a normal,
 * silent no-op (see that module's `RootNode.read()`), so this never
 * creates or touches any file, purely reads whatever's already there.
 * Split out from `Fl_Preferences` being a whole separate subsystem this
 * roadmap item originally scoped out entirely -- ported for real once
 * `fl.preferences` itself was done (see that module's `PORTING.md` row).
 */
private void readOptions_()
{
    import prefsmod = fl.preferences;

    {
        auto prefs = new prefsmod.Preferences(prefsmod.rootCoreSystemL, "fltk.org", "fltk");
        auto optPrefs = new prefsmod.Preferences(prefs, "options");
        foreach (opt; Option.min .. cast(Option)(Option.max + 1))
        {
            int tmp;
            optPrefs.get(optionKeys_[opt], tmp, optionDefaults_[opt] ? 1 : 0);
            optionValues_[opt] = tmp != 0;
        }
    }
    {
        auto prefs = new prefsmod.Preferences(prefsmod.rootCoreUserL, "fltk.org", "fltk");
        auto optPrefs = new prefsmod.Preferences(prefs, "options");
        foreach (opt; Option.min .. cast(Option)(Option.max + 1))
        {
            int tmp;
            optPrefs.get(optionKeys_[opt], tmp, -1);
            if (tmp >= 0) optionValues_[opt] = tmp != 0;
        }
    }
}

/**
 * Returns a global FLTK-wide setting. Ported from
 * `Fl::option(Fl_Option)` (`src/Fl.cxx`): the first call of any option
 * lazily reads the real system-wide then user-level `Fl_Preferences`
 * database (see `readOptions_()`) and caches every option's resolved
 * value, matching FLTK's own `Private::options_read_` guard exactly
 * -- every subsequent call, and every call to the setter below, just
 * reads/writes the cached table.
 */
bool option(Option opt)
{
    if (!optionsRead_)
    {
        readOptions_();
        optionsRead_ = true;
    }
    return optionValues_[opt];
}

/**
 * Overrides an option while the application is running (matching
 * FLTK's own semantics exactly: takes effect immediately, isn't
 * persisted anywhere, and reverts on the next run -- this port simply
 * has no persistence layer to persist it *to*, so that part is true
 * here "by construction" rather than by explicit choice the way it is
 * FLTK). Ported from `Fl::option(Fl_Option, bool)`.
 *
 * A setter call made
 * *before* the getter's own first call must not be silently discarded the
 * moment anything later calls the getter: since `option(Option)` (the getter,
 * just above) only calls `readOptions_()` -- which unconditionally
 * overwrites every entry of `optionValues_` from the on-disk/default
 * preferences -- on its own *first* call, and only *then* sets
 * `optionsRead_ = true`, a setter call that runs before that first
 * getter call would leave `optionsRead_` still false; the next time *anyone*
 * calls the getter (for any option, not necessarily this one -- e.g.
 * `fl.tooltip`/`fl.input`'s own routine `option()` reads), `readOptions_()`
 * would fire and clobber the just-set override back to the default,
 * permanently (nothing re-applies it afterward) -- e.g. `main()`'s own
 * `fl.option(Fl.Option.
 * arrowFocus, true);`, called first thing before any widget exists,
 * would be silently reset to `false` by the first unrelated `option()`
 * getter call reached during setup, so `fl.input`'s `normalInputMove()`
 * would read `false` for the rest of the run and Left/Right/Up/Down could
 * never escape a focused `Input` field no matter how many times the
 * caret was already at the field's boundary. Ported from FLTK's own
 * setter exactly: `if (!Private::options_read_) { option(opt); }` before
 * applying the override -- calling the getter first (for its
 * side effect of populating `optionValues_`/setting `optionsRead_`, not
 * its return value) guarantees the read-from-disk pass has already
 * happened and won't run again later to undo this call.
 */
void option(Option opt, bool val)
{
    if (!optionsRead_) option(opt); // ensure readOptions_() has already run
    optionValues_[opt] = val;
}

// ---------------------------------------------------------------------
// Fl::args()/Fl::arg() -- optional command-line switch parser
// ---------------------------------------------------------------------
//
// Ported from src/Fl_arg.cxx. Genuinely optional (FLTK's own doc
// comment: "You do not need to call this! Feel free to make up your
// own switches."), but real and useful: recognizes the standard FLTK
// switches (-display/-geometry/-title/-name/-bg/-fg/-bg2/-scheme/
// -iconic/-kbd/-nokbd/-dnd/-nodnd/-tooltips/-notooltips), applying the
// ones with an immediate effect right away and stashing the rest
// (geometry/name/title/iconic/bg/fg/bg2) into module state --
// fl.window.Window.show(string[]) applies geometry/name/title/iconic
// once a window actually exists to apply them to, matching FLTK's
// own deferred-application design exactly ("this does not open the
// display, instead switches that need the display open are stashed
// into static variables ... you must display your first window by
// calling window->show(argc,argv)").
//
// Fl::get_system_colors() is real too: see
// getSystemColors() below, which reads the bg/fg/bg2 strings captured
// here to build the gray ramp and default colors via background()/
// foreground()/background2(), and fl.window.Window.show(string[]),
// which calls it at the right point in FLTK's own call order.
// Fl::system_driver()->single_arg()/arg_and_value() (platform-specific
// switch extension points) aren't ported either -- FLTK's own X11
// driver never overrides either hook, so they're unconditionally
// false/no-op on this port's only real target anyway.

private bool argCalled_;
private bool argReturnI_;
package(fl) string argName_;
package(fl) string argTitle_;
package(fl) string argGeometry_;
package(fl) string argBg_;
package(fl) string argFg_;
/// `-scaling_factor` switch value; 1.0 when absent.
package(fl) float argScalingFactor_ = 1.0f;
package(fl) string argBg2_;

/// `Fl_Window::show_next_window_iconic_` -- the direct equivalent of
/// FLTK's static `char` flag on `Fl_Window`, ported here rather
/// than as a class-static in `fl.window` (matching this port's usual
/// home for process-wide flags `fl.platform_x11` also needs to read
/// directly). `arg()`'s own `-iconic` case sets this directly, matching
/// FLTK's `Fl_arg.cxx` call site exactly -- `showNextWindowIconic_`
/// avoids the one-flash-frame tradeoff a separate `argIconic_` flag
/// consumed via a post-`show()` `iconize()` call would have, matching
/// FLTK's real "born iconic" behavior instead. See
/// `fl.window.Window.showNextWindowIconic()`/`(bool)` for the public
/// API surface and `iconize()`/`fl.platform_x11.createWindow()` for
/// the two ends of the mechanism this backs.
package(fl) bool showNextWindowIconic_;

/// Flags returned by `parseGeometry()`: which values the string held,
/// and whether x/y were negative (measured from the right/bottom).
/// The same values as X11's `XValue`... and FLTK's `Fl_Screen_Driver::
/// fl_XValue`....
package(fl) enum : int
{
    geomXValue = 0x0001,
    geomYValue = 0x0002,
    geomWidthValue = 0x0004,
    geomHeightValue = 0x0008,
    geomXNegative = 0x0010,
    geomYNegative = 0x0020,
}

/**
 * Parses an X geometry string, `[=][<width>x<height>][{+-}<x>{+-}<y>]`,
 * returning the `geom*` flags of the values found (0 if the string is
 * malformed) and updating only those arguments. Ported from
 * `Fl::screen_driver()->XParseGeometry()`: on Linux that is Xlib's own
 * `XParseGeometry()`; elsewhere it is FLTK's generic
 * `Fl_Screen_Driver::XParseGeometry()` (`src/Fl_Screen_Driver.cxx`),
 * which also raises a parsed width below 80 to 80 and a height below 30
 * to 30.
 */
package(fl) int parseGeometry(string s, ref int x, ref int y, ref uint width, ref uint height)
{
    version (linux)
    {
        import std.string : toStringz;
        return XParseGeometry(s.toStringz, &x, &y, &width, &height);
    }
    else
    {
        import std.ascii : isDigit;

        size_t p = 0;
        bool at(char c) { return p < s.length && s[p] == c; }
        bool digitAt() { return p < s.length && isDigit(s[p]); }
        // FLTK's file-static `ReadInteger()`: an optional sign, then
        // digits; `p` moves past whatever was read.
        int readInteger()
        {
            int sign = 1;
            if (at('+')) p++;
            else if (at('-')) { p++; sign = -1; }
            int result = 0;
            while (digitAt()) result = result * 10 + (s[p++] - '0');
            return sign * result;
        }

        int mask = 0;
        uint tempWidth, tempHeight;
        int tempX, tempY;

        if (s.length == 0) return mask;
        if (at('=')) p++; // ignore a leading '='

        if (digitAt())
        {
            size_t start = p;
            int n = readInteger();
            tempWidth = n < 0 ? -n : n;
            if (p == start) return 0;
            mask |= geomWidthValue;
            if (!at('x') && !at('X')) return 0; // expected 'x' after width
            p++;
            if (!digitAt()) return 0; // expected a digit after 'x'
            start = p;
            n = readInteger();
            tempHeight = n < 0 ? -n : n;
            if (p == start) return 0;
            mask |= geomHeightValue;
        }

        if (at('+') || at('-'))
        {
            if (at('-')) mask |= geomXNegative;
            size_t start = p;
            tempX = readInteger();
            if (p == start) return 0;
            mask |= geomXValue;
        }
        else if (p < s.length) return 0; // unexpected character

        if (at('+') || at('-'))
        {
            if (at('-')) mask |= geomYNegative;
            size_t start = p;
            tempY = readInteger();
            if (p == start) return 0;
            mask |= geomYValue;
        }
        else if (p < s.length) return 0; // unexpected character

        if (p < s.length) return 0; // trailing junk

        if (mask & geomXValue) x = tempX;
        if (mask & geomYValue) y = tempY;
        if (mask & geomWidthValue) width = tempWidth < 80 ? 80 : tempWidth;
        if (mask & geomHeightValue) height = tempHeight < 30 ? 30 : tempHeight;
        return mask;
    }
}

unittest
{
    int x = -1, y = -1;
    uint w = 7, h = 7;
    assert(parseGeometry("100x50+10-20", x, y, w, h)
        == (geomWidthValue | geomHeightValue | geomXValue | geomYValue | geomYNegative));
    assert(x == 10 && y == -20 && w == 100 && h == 50);

    // Only the values present are updated.
    x = y = -1; w = h = 7;
    assert(parseGeometry("=+5+6", x, y, w, h) == (geomXValue | geomYValue));
    assert(x == 5 && y == 6 && w == 7 && h == 7);

    // Malformed strings.
    foreach (bad; ["not-a-geometry", "100x", "100xA", "+1+2junk", "100x50 "])
        assert(parseGeometry(bad, x, y, w, h) == 0, bad);
    assert(parseGeometry("", x, y, w, h) == 0);

    // FLTK's generic parser enforces a minimum size; Xlib's doesn't.
    version (linux) {} else
    {
        // A width without "x<height>" is rejected; Xlib accepts it.
        assert(parseGeometry("100", x, y, w, h) == 0);
        assert(parseGeometry("10x10", x, y, w, h) == (geomWidthValue | geomHeightValue));
        assert(w == 80 && h == 30);
    }
}

/// Case-insensitive "is `a` a prefix (at least `atleast` characters
/// long) of `canonical`?" -- ported from the file-static `fl_match()`
/// helper (`src/Fl_arg.cxx`), letting every standard switch below be
/// abbreviated (e.g. `-g`/`-geom` for `-geometry`).
private bool argMatch(string a, string canonical, size_t atleast = 1)
{
    import std.ascii : toLower;

    size_t i = 0;
    while (i < a.length && i < canonical.length
        && (a[i] == canonical[i] || toLower(a[i]) == canonical[i]))
        i++;
    return i == a.length && i >= atleast;
}

/// Delegate type for a custom switch handler passed to `args()` --
/// ported from `Fl_Args_Handler` (`FL/core/function_types.H`) as a D
/// delegate rather than a C function pointer, per CONVENTIONS.md's callback
/// convention (a closure can already capture whatever context a
/// function-pointer+`void*` pair would have needed). Should return `0`
/// (leaving `i` unchanged) if `cmdArgs[i]` is unrecognized; otherwise
/// the number of words consumed (and advance `i` by the same amount).
alias ArgsHandler = int delegate(string[] cmdArgs, ref int i);

/**
 * Parses a single switch from `cmdArgs`, starting at word `i`. Returns
 * the number of words eaten (1 or 2, or 0 if unrecognized) and adds
 * the same value to `i`. Ported from `Fl::arg(int,char**,int&)`
 * (`src/Fl_arg.cxx`) -- the default per-switch matcher `args()` below
 * uses internally, exposed in case a caller wants to step through the
 * standard switches manually instead.
 */
int arg(string[] cmdArgs, ref int i)
{
    argCalled_ = true;
    string s = (i >= 0 && i < cast(int) cmdArgs.length) ? cmdArgs[i] : null;

    if (s is null) { i++; return 1; } // something removed by the caller?

    // A word that doesn't start with '-', a word after a bare '--', or
    // '-' by itself all start the "non-switch arguments" -- return 0
    // (unrecognized) but flag argReturnI_ so args() knows to stop
    // *without* treating it as an error.
    if (s.length == 0 || s[0] != '-' || s.length == 1 || (s.length > 1 && s[1] == '-'))
    {
        argReturnI_ = true;
        return 0;
    }
    s = s[1 .. $]; // point after the dash

    if (argMatch(s, "iconic"))
    {
        // Ported from Fl_arg.cxx's own `Fl_Window::
        // show_next_window_iconic(1);` -- a direct call at parse time,
        // not deferred through a separate flag consumed after show()
        // (see fl.window.Window.iconize()'s own doc comment).
        showNextWindowIconic_ = true;
        i++;
        return 1;
    }
    else if (argMatch(s, "kbd"))
    {
        visibleFocus(true);
        i++;
        return 1;
    }
    else if (argMatch(s, "nokbd", 3))
    {
        visibleFocus(false);
        i++;
        return 1;
    }
    else if (argMatch(s, "dnd", 2))
    {
        dndTextOps(true);
        i++;
        return 1;
    }
    else if (argMatch(s, "nodnd", 3))
    {
        dndTextOps(false);
        i++;
        return 1;
    }
    else if (argMatch(s, "tooltips", 2))
    {
        fl.tooltip.enable();
        i++;
        return 1;
    }
    else if (argMatch(s, "notooltips", 3))
    {
        fl.tooltip.disable();
        i++;
        return 1;
    }

    if (i >= cast(int) cmdArgs.length - 1) return 0; // everything left needs a value
    string v = cmdArgs[i + 1];

    if (argMatch(s, "geometry"))
    {
        int gx, gy;
        uint gw, gh;
        if (parseGeometry(v, gx, gy, gw, gh) == 0) return 0;
        argGeometry_ = v;
    }
    else if (argMatch(s, "display", 2))
    {
        version (linux) platformX11.setDisplayName(v);
    }
    else if (argMatch(s, "title", 2))
    {
        argTitle_ = v;
    }
    else if (argMatch(s, "name", 2))
    {
        argName_ = v;
    }
    else if (argMatch(s, "bg2", 3) || argMatch(s, "background2", 11))
    {
        argBg2_ = v;
    }
    else if (argMatch(s, "bg", 2) || argMatch(s, "background", 10))
    {
        argBg_ = v;
    }
    else if (argMatch(s, "fg", 2) || argMatch(s, "foreground", 10))
    {
        argFg_ = v;
    }
    else if (argMatch(s, "scaling", 2) || argMatch(s, "scaling_factor", 14))
    {
        import std.conv : to;
        try argScalingFactor_ = v.to!float;
        catch (Exception) argScalingFactor_ = 0; // atof() of junk is 0 too
    }
    else if (argMatch(s, "scheme", 1))
    {
        scheme(v);
    }
    else
    {
        return 0; // unrecognized
    }

    i += 2;
    return 2;
}

/**
 * Parses command-line switches, using `cb` (if given) to recognize any
 * application-specific ones first. Returns `0` on error, or the index
 * of the first non-switch word (== `cmdArgs.length` if every word was a
 * recognized switch). Ported from `Fl::args(int,char**,int&,
 * Fl_Args_Handler)` (`src/Fl_arg.cxx`). Genuinely optional -- FLTK's
 * own doc comment: "you do not need to call this."
 */
int args(string[] cmdArgs, ref int i, ArgsHandler cb = null)
{
    argCalled_ = true;
    i = 1; // skip cmdArgs[0] (the program name)
    while (i < cast(int) cmdArgs.length)
    {
        if (cb !is null && cb(cmdArgs, i)) continue;
        if (!arg(cmdArgs, i)) return argReturnI_ ? i : 0;
    }
    return i;
}

/// Convenience form of `args(string[],ref int,ArgsHandler)` for a
/// program with no switches of its own -- parses only the standard
/// FLTK ones. Ported from `Fl::args(int,char**)` (`src/Fl_arg.cxx`);
/// FLTK calls `Fl::error(helpmsg)` on an unrecognized switch -- no
/// `Fl::error()` equivalent exists in this port (an established,
/// documented gap elsewhere too), so this silently does nothing on an
/// unrecognized switch instead of printing a usage message.
void args(string[] cmdArgs)
{
    int i;
    args(cmdArgs, i);
}

/// Whether `args()`/`arg()` has been called at least once -- backs
/// `Window.show(string[])`'s FLTK `if (argc && !arg_called)
/// Fl::args(argc,argv);` guard (only auto-parse if the caller hasn't
/// already called `args()` explicitly).
package(fl) bool argCalled() { return argCalled_; }

unittest
{
    // Reset every static this touches so this test is hermetic
    // regardless of what ran before it.
    argCalled_ = false;
    argReturnI_ = false;
    argName_ = null;
    argTitle_ = null;
    argGeometry_ = null;
    showNextWindowIconic_ = false;
    argBg_ = null;
    argFg_ = null;
    argScalingFactor_ = 1.0f;
    argBg2_ = null;
    resetForTest();

    // Abbreviations, case-insensitivity, and the atleast-length guard.
    assert(argMatch("g", "geometry"));
    assert(argMatch("Geo", "geometry"));
    assert(!argMatch("x", "geometry"));
    assert(!argMatch("geometryy", "geometry")); // longer than canonical
    assert(!argMatch("no", "nokbd", 3)); // below the minimum length
    assert(argMatch("nok", "nokbd", 3));

    // Immediate-effect switches.
    int i;
    string[] a1 = ["prog", "-kbd"];
    assert(args(a1, i) == 2);
    assert(visibleFocus() == true);

    string[] a2 = ["prog", "-nokbd"];
    assert(args(a2, i) == 2);
    assert(visibleFocus() == false);
    visibleFocus(true); // restore the default for later tests/other modules

    // Value-taking switches get stashed, not applied immediately.
    string[] a3 = ["prog", "-title", "Hello", "-name", "myapp", "-geometry", "100x50+10+20"];
    assert(args(a3, i) == 7);
    assert(argTitle_ == "Hello");
    assert(argName_ == "myapp");
    assert(argGeometry_ == "100x50+10+20");

    // -bg/-fg/-bg2 (no consumer yet, just captured).
    string[] a4 = ["prog", "-bg", "#ff0000", "-fg", "#00ff00", "-bg2", "#0000ff"];
    assert(args(a4, i) == 7);
    assert(argBg_ == "#ff0000");
    assert(argFg_ == "#00ff00");
    assert(argBg2_ == "#0000ff");

    // -iconic.
    string[] a5 = ["prog", "-iconic"];
    assert(args(a5, i) == 2);
    assert(showNextWindowIconic_ == true);
    showNextWindowIconic_ = false; // restore for later tests

    // A malformed -geometry (no valid X geometry syntax) is rejected --
    // args() stops there and reports it as the first unrecognized word.
    string[] a6 = ["prog", "-geometry", "not-a-geometry"];
    assert(args(a6, i) == 0);

    // A non-switch argument stops parsing without being an error.
    string[] a7 = ["prog", "-kbd", "somefile.txt"];
    assert(args(a7, i) == 2);
    assert(a7[i] == "somefile.txt");

    // A genuinely unrecognized switch is a real error (0, and argReturnI_
    // stays false so args() can tell the two cases apart) -- matching
    // FLTK, argReturnI_/return_i is a plain sticky flag never reset
    // by arg()/args() themselves, so reset it explicitly here for a
    // hermetic test (a7's own non-switch-argument case above legitimately
    // sets it and leaves it set, same as FLTK's own return_i would).
    argReturnI_ = false;
    string[] a8 = ["prog", "-not-a-real-switch"];
    assert(args(a8, i) == 0);

    // Custom handler gets first look, can override a standard switch --
    // claim "-nokbd" itself (without touching visibleFocus()) and confirm
    // the real -nokbd handling never ran underneath it.
    string[] a9 = ["prog", "-nokbd"];
    bool customCalled;
    ArgsHandler cb = (cmdArgs, ref j) {
        customCalled = true;
        j++;
        return 1;
    };
    visibleFocus(true);
    assert(args(a9, i, cb) == 2);
    assert(customCalled);
    assert(visibleFocus() == true); // still true: cb claimed it, real -nokbd branch never ran

    resetForTest();
}

/// The standard-FLTK-switches usage message, for programs that want to
/// print their own "-h"/"--help" text alongside it. Ported from
/// `Fl::help` (`src/Fl_arg.cxx`) -- FLTK's is `helpmsg+13`, the same
/// static string `Fl::error(helpmsg)` prints on an unrecognized switch
/// but with the "options are:\n" prefix sliced off (exactly 13 bytes).
/// Named `argsHelp` rather than `help` -- that name is already taken by
/// `fl.enumerations.help` (the `Help` keysym, `FL_Help`/`0xff68`), and
/// with both modules publicly re-exported through the flattened `fl`
/// package, an unqualified `fl.help` would be ambiguous between them.
immutable string argsHelp =
    " -bg2 color\n"
    ~ " -bg color\n"
    ~ " -di[splay] host:n.n\n"
    ~ " -dn[d]\n"
    ~ " -fg color\n"
    ~ " -g[eometry] WxH+X+Y\n"
    ~ " -i[conic]\n"
    ~ " -k[bd]\n"
    ~ " -na[me] classname\n"
    ~ " -nod[nd]\n"
    ~ " -nok[bd]\n"
    ~ " -not[ooltips]\n"
    ~ " -s[cheme] scheme\n"
    ~ " -scaling[_factor] factor\n"
    ~ " -ti[tle] windowtitle\n"
    ~ " -to[oltips]";

/// Thrown by `fatal()`'s own default handler -- see that function's own
/// doc comment for why throwing, not `exit()`, is this port's real
/// default. A dedicated type (rather than a plain `Exception`) so a
/// catcher can distinguish "the library itself declared its state
/// unusable" from an ordinary exception.
class FatalError : Exception
{
    this(string msg) { super(msg); }
}

/// Ported from `Fl_Abort_Handler` (`FL/core/function_types.H`) -- this
/// port's usual delegate substitution for a C function pointer (see
/// CONVENTIONS.md's "Callbacks are D delegates" convention), applied here
/// even though `fatal()` isn't a widget callback, since the shape (a
/// settable, overridable handler slot) is identical.
alias AbortHandler = void delegate(string msg);

private AbortHandler abortHandler_;

/// Ported from `Fl::set_abort(Fl_Abort_Handler)` (`FL/Fl.H`) -- installs
/// the handler `fatal()` below calls. `null` restores the default (see
/// `fatal()`'s own doc comment). FLTK's own doc comment on
/// `Fl::fatal()` explicitly sanctions this: "your version may be able
/// to use longjmp or an exception to continue, as long as it does not
/// call FLTK again" -- a caller-installed handler that throws is
/// exactly the documented, intended use, not a deviation from the
/// handler *contract*, just from the *default*'s own choice of what to
/// do.
void setAbort(AbortHandler h)
{
    abortHandler_ = h;
}

/// Ported from `Fl::abort` -- the getter half FLTK doesn't name
/// separately (its `Fl::fatal`/`set_abort()` pair is a bare, directly
/// assignable global function pointer), added here for symmetry with
/// every other get/set pair in this port's own convention. `null` means
/// "the default handler is installed."
AbortHandler abortHandler()
{
    return abortHandler_;
}

/**
 * Declares the library's state unusable and must not return normally --
 * ported from `Fl::fatal(const char*, ...)` (`Fl_System_Driver::
 * fatal()`, `src/Fl_System_Driver.cxx`). FLTK's own base
 * implementation prints to stderr then calls `exit(1)`. **This port's
 * real default deliberately doesn't call `exit()`** -- a real, deliberate
 * deviation, not FLTK's own behavior faithfully reproduced:
 * unlike a compiled C++ *application*, `fl.*` is a library an embedding
 * D program links against, and unilaterally tearing down its host
 * process out from under it is exactly the class of surprise this
 * project's own "sweep to remove `exit()` calls" was about (see
 * `fl.platform_x11.openDisplay()`, which already independently arrived
 * at "throw instead" for its own `XOpenDisplay()` failure, which routes
 * through here). The default still prints to
 * stderr first, matching FLTK's own always-prints behavior, then
 * throws a `FatalError` carrying the same message -- FLTK's own
 * doc comment on `Fl::fatal()` explicitly names throwing an exception
 * as an acceptable way to satisfy "must not return" (see `setAbort()`'s
 * own doc comment). An embedding app that genuinely wants FLTK's
 * literal exit-on-fatal behavior can opt back into it:
 * `fl.core.setAbort((msg) { import core.stdc.stdlib : exit; exit(1); });`
 * FLTK takes a printf-style format string plus varargs; this port's
 * own `message()`/`alert()`/etc. convention already has callers
 * pre-format via `std.format.format()` instead, so `fatal()` matches
 * that (a single already-formatted `string`).
 */
void fatal(string msg)
{
    if (abortHandler_ !is null)
    {
        abortHandler_(msg);
        return;
    }

    import std.stdio : stderr;

    stderr.writeln(msg);
    stderr.flush();
    throw new FatalError(msg);
}

unittest
{
    import std.exception : assertThrown, assertNotThrown;

    // Default handler: throws FatalError, never calls exit().
    assertThrown!FatalError(fatal("test fatal message"));

    // A custom handler can opt back into FLTK's literal behavior,
    // or do anything else -- here, just record that it ran.
    bool called;
    setAbort((string msg) { called = true; });
    assertNotThrown(fatal("test fatal message 2"));
    assert(called);

    // null restores the default.
    setAbort(null);
    assert(abortHandler() is null);
    assertThrown!FatalError(fatal("test fatal message 3"));
}

/// Ported from `Fl::version()` (`Fl.cxx`) -- the compiled-in
/// `FL_VERSION` (`fl.enumerations`), deprecated FLTK in favor of
/// `apiVersion()`. Named `version_` since `version` is a D keyword.
double version_() { return FL_VERSION; }

/// Ported from `Fl::api_version()` -- the compiled-in `FL_API_VERSION`.
int apiVersion() { return FL_API_VERSION; }

/// Ported from `Fl::abi_version()` -- the compiled-in `FL_ABI_VERSION`.
int abiVersion() { return FL_ABI_VERSION; }

/// Ported from `fl_open_callback(void(*)(const char*))` (`FL/platform.H`)
/// -- registers a callback for "the user dropped a file on this app's
/// dock icon" (macOS only; needs an app-bundle `Info.plist` declaring
/// accepted file types, per FLTK's own doc comment). A documented
/// no-op here: FLTK's own base `Fl_System_Driver::open_callback()`
/// is already an empty no-op on Linux too (only the macOS system driver
/// overrides it), so this port's Linux-only target already matches
/// FLTK's real behavior by doing nothing. Added for call-site
/// compatibility (`test/editor.cxx`'s tutorial registers one
/// unconditionally). `cb` is a D delegate rather than FLTK's plain
/// function pointer, per the usual callback convention, even though
/// it's never actually invoked here.
void openCallback(void delegate(string filename) cb) { }

/// Ported from `Fl::args_to_utf8(int,char**&)` (`FL/Fl.H`) -- converts
/// a native `argv` (e.g. Windows' possibly-ANSI-codepage command line)
/// to UTF-8 in place. A no-op passthrough here, faithfully: FLTK's
/// own base `Fl_System_Driver::args_to_utf8()` is already a no-op, and
/// neither the X11 nor generic Unix driver overrides it (only Windows
/// does) -- so on this port's only real target, the real FLTK
/// behavior already *is* "do nothing, return `args` unchanged." Returns
/// `args` as given rather than mutating in place, since D `string[]`
/// isn't reassignable through a `char**&` the way FLTK's is.
string[] argsToUtf8(string[] args) { return args; }

// ---------------------------------------------------------------------
// Mutable color table -- Fl::set_color()/get_color()/free_color()
// (fl_color.cxx). FLTK's fl_cmap is a plain, directly-mutable
// 256-entry C array; fl.enumerations.colorTable is `immutable` (a
// compile-time-constant default palette this port's Xft/Xlib drawing
// code has relied on since early on), so a *separate* mutable working
// copy is kept here instead of trying to relax colorTable's own
// immutability -- seeded from it once at module load, then diverging
// per-entry as setColor() is called, exactly matching FLTK's own
// "table starts as the default palette, entries get overwritten in
// place" semantics. fl.draw.colorToRgb8() -- the single shared point
// every Color resolves through -- consults this table via
// colorTableEntry() below instead of colorTable directly, so a
// setColor() call is visible everywhere immediately, matching
// FLTK's fl_cmap exactly.
private uint[256] colorOverrides_ = colorTable;

/// package(fl): read one entry of the mutable color table, bounds-
/// checked the same way fl.draw.colorToRgb8() checked the immutable
/// colorTable before this existed. `fl.draw` is this function's only
/// real caller.
package(fl) uint colorTableEntry(Color i)
{
    return (i < colorOverrides_.length) ? colorOverrides_[i] : 0;
}

/// Sets an entry in the color table -- ported from `Fl::set_color(Fl_Color,
/// uchar, uchar, uchar)`. "You can set it to any 8-bit RGB color. The
/// color is not allocated until fl_color(i) is used" (FLTK's own
/// doc comment) -- true here too: this just rewrites the table entry
/// `fl.draw`'s Xft/Xlib color resolution reads from on the next actual
/// draw call, no eager X11 allocation.
void setColor(Color i, ubyte red, ubyte green, ubyte blue)
{
    setColor(i, (cast(uint) red << 24) | (cast(uint) green << 16) | (cast(uint) blue << 8));
}

/// Ditto, with alpha -- ported from `Fl::set_color(Fl_Color, uchar,
/// uchar, uchar, uchar)`. Matches FLTK's own documented platform
/// caveat verbatim: alpha has no effect on this port's X11 drawing path
/// (real transparency is Wayland/macOS/GL-only FLTK too), so it's
/// stored (for get_color()'s sake, and for API completeness) but
/// otherwise inert here, same as FLTK on X11.
void setColor(Color i, ubyte red, ubyte green, ubyte blue, ubyte alpha)
{
    setColor(i, (cast(uint) red << 24) | (cast(uint) green << 16)
        | (cast(uint) blue << 8) | (alpha ^ 0xff));
}

/// Ditto, taking an already-packed 0xRRGGBBAA value directly -- ported
/// from `Fl::set_color(Fl_Color, unsigned)`, which FLTK routes
/// through a virtual `Fl_Graphics_Driver::set_color()` that just does
/// `fl_cmap[i] = c;` on every driver that doesn't override it (X11
/// included) -- so this port's single concrete implementation, no
/// driver indirection needed.
void setColor(Color i, uint packedRgba)
{
    if ((i & ~0xff) != 0) return; // matches FLTK's implicit (Fl_Color)(i & 255) truncation being a no-op for in-range i; out-of-range i is simply not settable here (colorOverrides_ is exactly 256 entries)
    colorOverrides_[i] = packedRgba;
}

/// Returns the packed 0xRRGGBBAA value for color `i` -- ported from
/// `Fl::get_color(Fl_Color)`. For a "free" (packed-RGB) color, FLTK
/// returns it unchanged; for a table index, the current (possibly
/// setColor()-overridden) table entry.
uint getColor(Color i)
{
    return (i & 0xFFFFFF00) ? i : colorTableEntry(i);
}

/// Ditto, split into r/g/b out-params -- ported from `Fl::get_color(Fl_Color,
/// uchar&, uchar&, uchar&)`.
void getColor(Color i, out ubyte r, out ubyte g, out ubyte b)
{
    uint c = getColor(i);
    r = cast(ubyte)(c >> 24);
    g = cast(ubyte)(c >> 16);
    b = cast(ubyte)(c >> 8);
}

/// Ditto, with alpha -- ported from `Fl::get_color(Fl_Color, uchar&,
/// uchar&, uchar&, uchar&)`.
void getColor(Color i, out ubyte r, out ubyte g, out ubyte b, out ubyte a)
{
    uint c = getColor(i);
    r = cast(ubyte)(c >> 24);
    g = cast(ubyte)(c >> 16);
    b = cast(ubyte)(c >> 8);
    a = cast(ubyte)(c ^ 0xff);
}

/**
 * Returns a human-readable "pretty" name for `fnum` (e.g. "sans
 * bold"), and, via `attributes`, which of `Font.bold`/`Font.italic`
 * the name encodes. Ported from `Fl::get_font_name()` (`Fl.H`), which
 * forwards to the active `Fl_Graphics_Driver`'s own override -- on
 * FLTK X11/Xft that's `Fl_Xlib_Graphics_Driver::get_font_name()`
 * (`src/drivers/Xlib/Fl_Xlib_Graphics_Driver_font_xft.cxx`), which
 * strips a leading style-marker character off the font's internally-
 * registered name and appends " bold"/" italic" words.
 *
 * Delegates to `fl.draw.getFont(fnum)`
 * for the raw name (the same style-char-prefixed string `setFont()`/
 * `setFonts()`/`fontconfigName()` already consult, real for both
 * built-in and custom fonts) and derives the pretty name from *that*
 * -- deriving it algorithmically from `fnum`'s own face/bold/italic
 * *encoding* instead (a 0-15 wraparound grid) would only ever describe
 * the 16 built-in faces, wrapping any `setFonts()`-registered custom
 * font index (16 and up) back onto that same grid and showing the
 * wrong name. This is a single source of truth, matching FLTK's own
 * `get_font_name()` reading from the same registered-name table
 * `Fl::set_font()`/`Fl::set_fonts()` write into.
 */
string getFontName(Font fnum)
{
    int attributes;
    return getFontName(fnum, attributes);
}

/// ditto
string getFontName(Font fnum, out int attributes)
{
    string raw = fldraw.getFont(fnum);
    char c0 = raw.length > 0 ? raw[0] : ' ';
    bool recognized = c0 == ' ' || c0 == 'B' || c0 == 'I' || c0 == 'P';
    string name = (recognized && raw.length > 0) ? raw[1 .. $] : raw;
    bool isBold = c0 == 'B' || c0 == 'P';
    bool isItalic = c0 == 'I' || c0 == 'P';
    if (isBold) name ~= " bold";
    if (isItalic) name ~= " italic";
    attributes = (isBold ? bold : 0) | (isItalic ? italic : 0);
    return name;
}

/// `Fl::free_color()` (`fl_color.cxx`) -- named `releaseColor()`, not
/// `freeColor()`, to avoid colliding with the pre-existing
/// `fl.enumerations.freeColor` constant (`FL_FREE_COLOR = 16`, the
/// starting index of the application-assignable "free" color range --
/// an unrelated meaning of "free") once both are re-exported through
/// the flattened `fl` package namespace. Ported as a documented no-op,
/// matching the base `Fl_Graphics_Driver::free_color()` FLTK itself
/// ships ("nothing to do, reimplement in driver if needed"): freeing an
/// allocated X11 pixel for reuse is only meaningful for a real limited-
/// colormap (palette) display, which this port doesn't support (see
/// CONVENTIONS.md: "plain 8-8-8 TrueColor visual assumed, no colormap/
/// palette support" -- `fl.draw`'s own module comment says the same).
void releaseColor(Color i, int overlay = 0) { }

/// Sets `foregroundColor`'s table entry -- ported from `Fl::foreground(uchar,
/// uchar, uchar)` verbatim (it's just a `set_color()` call FLTK
/// too).
void foreground(ubyte r, ubyte g, ubyte b)
{
    fgSet_ = true;
    setColor(foregroundColor, r, g, b);
}

/// Sets `background2Color`'s table entry -- ported from `Fl::background2(uchar,
/// uchar, uchar)` verbatim.
void background2(ubyte r, ubyte g, ubyte b)
{
    bg2Set_ = true;
    setColor(background2Color, r, g, b);
}

/// Recomputes the 24-entry gray ramp (`grayRamp` .. `grayRamp+numGray-1`)
/// so that `backgroundColor` (`FL_GRAY` FLTK, the ramp position most
/// widgets' default box color/edges resolve to) becomes (r,g,b), fitting
/// a power curve through the rest of the ramp from black to white --
/// ported verbatim from `Fl::background(uchar, uchar, uchar)`
/// (`Fl_get_system_colors.cxx`).
void background(ubyte r, ubyte g, ubyte b)
{
    import std.math : log, pow;

    bgSet_ = true;

    if (r == 0) r = 1; else if (r == 255) r = 254;
    double powr = log(r / 255.0) / log((backgroundColor - grayRamp) / (numGray - 1.0));
    if (g == 0) g = 1; else if (g == 255) g = 254;
    double powg = log(g / 255.0) / log((backgroundColor - grayRamp) / (numGray - 1.0));
    if (b == 0) b = 1; else if (b == 255) b = 254;
    double powb = log(b / 255.0) / log((backgroundColor - grayRamp) / (numGray - 1.0));

    for (int i = 0; i < numGray; i++)
    {
        double gray = i / (numGray - 1.0);
        setColor(fl_gray_ramp(i),
            cast(ubyte)(pow(gray, powr) * 255 + .5),
            cast(ubyte)(pow(gray, powg) * 255 + .5),
            cast(ubyte)(pow(gray, powb) * 255 + .5));
    }
}

private bool fgSet_, bgSet_, bg2Set_;

/// Parses a color description string into r/g/b -- ported from
/// `fl_parse_color()`/`Fl_Screen_Driver::parse_color()` (base hex-triplet
/// path, `#RGB`/`#RRGGBB`/`#RRRGGGBBB`/`#RRRRGGGGBBBB`, `#` optional) +
/// `Fl_X11_Screen_Driver::parse_color()` (the X11 override: "none"/
/// "#transparent" always fail, and any non-hex spec falls through to a
/// real `XParseColor()` query against the X server's own color
/// database -- the same database `-fg red` and similar FLTK demos
/// rely on). Returns `false` if the string couldn't be interpreted
/// (matching FLTK's `return 0`).
version (linux) bool flParseColor(string spec, out ubyte r, out ubyte g, out ubyte b)
{
    import std.ascii : isHexDigit;
    import std.string : toStringz;

    if (spec.length == 0) return false;

    string hex = spec;
    if (hex[0] == '#') hex = hex[1 .. $];

    bool eqCi(string a, string b)
    {
        import std.uni : toLower;
        import std.algorithm.comparison : equal;
        import std.algorithm.iteration : map;
        return equal(a.map!toLower, b.map!toLower);
    }

    if (eqCi(spec, "none") || eqCi(spec, "#transparent")) return false;

    size_t n = hex.length;
    size_t m = n / 3;
    bool allHex = n > 0 && (n % 3 == 0) && m >= 1 && m <= 4;
    if (allHex)
        foreach (c; hex)
            if (!isHexDigit(c)) { allHex = false; break; }

    if (allHex)
    {
        import std.conv : parse;

        int[3] comp;
        foreach (i; 0 .. 3)
        {
            string digits = hex[i * m .. (i + 1) * m];
            comp[i] = parse!int(digits, 16);
        }
        final switch (m)
        {
        case 1: comp[0] *= 0x11; comp[1] *= 0x11; comp[2] *= 0x11; break;
        case 2: break;
        case 3: comp[0] >>= 4; comp[1] >>= 4; comp[2] >>= 4; break;
        case 4: comp[0] >>= 8; comp[1] >>= 8; comp[2] >>= 8; break;
        }
        r = cast(ubyte) comp[0];
        g = cast(ubyte) comp[1];
        b = cast(ubyte) comp[2];
        return true;
    }

    // Not "None", not hex -- ask the X server's own color database
    // (the standard X11 `rgb.txt` name list), matching FLTK's
    // XParseColor() fallback exactly.
    if (platformX11.x11Display() is null) platformX11.openDisplay();
    auto display = platformX11.x11Display();
    if (display is null) return false;
    int screenNum = XDefaultScreen(display);
    Colormap cmap = XDefaultColormap(display, screenNum);
    XColor xc;
    if (!XParseColor(display, cmap, spec.toStringz(), &xc)) return false;
    r = cast(ubyte)(xc.red >> 8);
    g = cast(ubyte)(xc.green >> 8);
    b = cast(ubyte)(xc.blue >> 8);
    return true;
}

/// Ported from `Fl::get_system_colors()` (`Fl_get_system_colors.cxx`,
/// `Fl_X11_Screen_Driver::get_system_colors()`), including the X
/// resource database (Xrdb/KDE `krdb`) desktop-theme lookup --
/// see `getsyscolor()` below, a direct port of the file-static helper
/// of the same name in `Fl_X11_Screen_Driver.cxx`). For each of
/// bg2/fg/bg: an explicit `-bg`/`-fg`/`-bg2` switch (`argBg_`/`argFg_`/
/// `argBg2_`, captured by `arg()` above) wins if present; otherwise
/// `XGetDefault()` is consulted (`"Text"` as the resource class for
/// bg2, matching FLTK's own hardcoded choice there, `key1` --
/// `firstWindow()->xclass()` or `"fltk"` -- for fg/bg, same as
/// `getSystemScheme()` just below uses for its own `XGetDefault()`
/// call); a hardcoded fallback applies if neither resolved anything.
/// Whichever wins is *always* applied (matching FLTK: `getsyscolor()`
/// unconditionally calls its `func` once `arg` resolves to something),
/// each still gated on `!bgSet_`/`!fgSet_`/`!bg2Set_` so an app that
/// already called `background()`/`foreground()`/`background2()` itself
/// isn't overridden. The trailing `Text`/`selectBackground` lookup
/// (`FL_SELECTION_COLOR`) has no `-bg`/`-fg`-style switch or `*Set_`
/// guard at all, matching FLTK exactly -- it always re-reads (or
/// re-defaults) on every call.
version (linux) void getSystemColors()
{
    string key1;
    auto win = firstWindow();
    key1 = win !is null ? win.xclass() : null;
    if (key1.length == 0) key1 = "fltk";

    void getsyscolor(string k1, string k2, string arg, string defarg,
        void delegate(ubyte, ubyte, ubyte) func)
    {
        if (arg.length == 0)
        {
            arg = platformX11.getDefaultResource(k1, k2);
            if (arg.length == 0) arg = defarg;
        }
        ubyte r, g, b;
        if (flParseColor(arg, r, g, b)) func(r, g, b);
    }

    if (!bg2Set_) getsyscolor("Text", "background", argBg2_, "#ffffff", (r, g, b) => background2(r, g, b));
    if (!fgSet_) getsyscolor(key1, "foreground", argFg_, "#000000", (r, g, b) => foreground(r, g, b));
    if (!bgSet_) getsyscolor(key1, "background", argBg_, "#c0c0c0", (r, g, b) => background(r, g, b));
    getsyscolor("Text", "selectBackground", null, "#000080",
        (r, g, b) => setColor(selectionColor, r, g, b));
}
else void getSystemColors() { }

unittest
{
    // setColor()/getColor() round-trip, and colorTableEntry() (what
    // fl.draw.colorToRgb8() reads) reflects it immediately.
    setColor(200, 0x11, 0x22, 0x33);
    assert(getColor(200) == 0x11223300);
    ubyte r, g, b;
    getColor(200, r, g, b);
    assert(r == 0x11 && g == 0x22 && b == 0x33);
    assert(colorTableEntry(200) == 0x11223300);

    // A "free" (packed-RGB) color is returned unchanged by getColor(),
    // never treated as a table index.
    uint free = 0x44556600 | 0x01000000; // set a bit above the low byte
    assert(getColor(free) == free);

    // Restore the default palette entry so this test doesn't leak into
    // whatever else runs afterward (module-level state, same reasoning
    // CONVENTIONS.md's core.resetForTest() note documents elsewhere).
    setColor(200, colorTable[200]);
    assert(colorTableEntry(200) == colorTable[200]);
}

unittest
{
    // background()/foreground() actually rewrite the color table --
    // full precision loss from the power-curve fit isn't guaranteed
    // (matching FLTK's own floating-point approach), so this only
    // checks the ramp moved in the right direction and the requested
    // color landed close to backgroundColor's own ramp position.
    uint before = colorTableEntry(backgroundColor);
    background(200, 100, 50);
    uint after = colorTableEntry(backgroundColor);
    assert(after != before);
    ubyte r, g, b;
    getColor(backgroundColor, r, g, b);
    // background()'s power-curve fit is exact at the backgroundColor's
    // own ramp position by construction (that's what powr/powg/powb
    // solve for) modulo the +.5 rounding in the pow() call.
    assert(r >= 199 && r <= 201);
    assert(g >= 99 && g <= 101);
    assert(b >= 49 && b <= 51);

    foreground(10, 20, 30);
    assert(colorTableEntry(foregroundColor) == 0x0a141e00);

    background2(40, 50, 60);
    assert(colorTableEntry(background2Color) == 0x28323c00);

    // Restore defaults for hermeticity.
    foreach (i; 0 .. numGray) setColor(fl_gray_ramp(i), colorTable[fl_gray_ramp(i)]);
    setColor(foregroundColor, colorTable[foregroundColor]);
    setColor(background2Color, colorTable[background2Color]);
    fgSet_ = bgSet_ = bg2Set_ = false;
}

version (linux) unittest
{
    // flParseColor()'s hex-triplet path -- doesn't need a live X
    // display (only the XParseColor() named-color fallback does).
    ubyte r, g, b;

    assert(flParseColor("#FF0000", r, g, b));
    assert(r == 0xFF && g == 0 && b == 0);

    assert(flParseColor("0F0", r, g, b)); // '#' optional, 1 digit/component
    assert(r == 0 && g == 0xFF && b == 0);

    assert(flParseColor("#000000004444", r, g, b)); // 4 digits/component
    assert(r == 0 && g == 0 && b == 0x44);

    assert(!flParseColor("none", r, g, b));
    assert(!flParseColor("#transparent", r, g, b));
    assert(!flParseColor("", r, g, b));
}

/// Backing storage for `keyboardScreenScaling(bool)` below. Default
/// `true`, matching FLTK's own `Fl_Screen_Driver::keyboard_screen_
/// scaling = 1;`.
private bool keyboardScreenScaling_ = true;

/// Ported from `Fl::keyboard_screen_scaling(int)` (`FL/Fl.H`) -- toggles
/// whether Ctrl+/Ctrl-/Ctrl0 control display scaling.
/// `scaleHandler()` checks this on
/// every `Event.shortcut`, so toggling it takes effect immediately
/// regardless of when `scaleHandler()` itself was installed -- matches
/// FLTK's own defensive double-check (`open_display()` also gates
/// *installing* the handler on this flag's value at startup, but
/// `scale_handler()`'s own `if (!keyboard_screen_scaling) return 0;`
/// is what actually matters for toggling after the fact, so that's the
/// only check this port bothers with -- installing an inert handler
/// costs nothing).
void keyboardScreenScaling(bool value)
{
    keyboardScreenScaling_ = value;
}

/// Ported from `Fl::visible_focus()`/`visible_focus(int)` -- thin
/// wrappers around `option(Option.visibleFocus)`, matching FLTK's
/// own inline forwarding exactly, expressed as one `Option` entry like
/// every other option.
bool visibleFocus() { return option(Option.visibleFocus); }
/// ditto
void visibleFocus(bool v) { option(Option.visibleFocus, v); }

/// Ported from `Fl::dnd_text_ops()`/`dnd_text_ops(int)` -- gates
/// whether `fl.input_`/`fl.text_display` start a real `fl.core.dnd()`
/// drag from a text selection (both check this before calling `dnd()`).
bool dndTextOps() { return option(Option.dndText); }
/// ditto
void dndTextOps(bool v) { option(Option.dndText, v); }

/// Width (in pixels) of the drop-shadow drawn by shadowBox/shadowFrame
/// (fl.draw.drawBoxAt()). Ported from Fl::box_shadow_width(); default 3.
int boxShadowWidth()
{
    return boxShadowWidth_;
}

/// ditto -- values below 1 clamp to 1, matching FLTK.
void boxShadowWidth(int w)
{
    boxShadowWidth_ = w < 1 ? 1 : w;
}

/// Maximum corner radius (in pixels) of the "rounded" (CSS-style)
/// boxtype family (roundedBox/rshadowBox/roundedFrame/rflatBox,
/// fl.draw.drawBoxAt()) -- a box's own radius is normally about 2/5 of
/// its smaller dimension, clamped to this. Ported from
/// Fl::box_border_radius_max(); default 15. Does NOT apply to the
/// "round" family (roundUpBox/roundDownBox), which are true
/// half-circle-sided ovals, not straight edges with rounded corners --
/// matching FLTK's own doc comment distinction.
int boxBorderRadiusMax()
{
    return boxBorderRadiusMax_;
}

/// ditto -- values below 5 clamp to 5, matching FLTK.
void boxBorderRadiusMax(int r)
{
    boxBorderRadiusMax_ = r < 5 ? 5 : r;
}

// ---------------------------------------------------------------------
// Fl_Scheme (color-scheme reactivity) -- FL/Fl.H's scheme()/is_scheme()/
// reload_scheme(), src/Fl_get_system_colors.cxx/src/fl_boxtype.cxx
// (core-roadmap item 11: the mechanism itself. The four schemes' own
// boxtype *drawing* functions live in fl.draw's `drawBoxAt()`; the
// "plastic" scheme's tiled window background is `plasticSchemeTile()`).
// ---------------------------------------------------------------------
//
// Provided: scheme()/scheme(string)/isScheme()/reloadScheme()/
// getSystemScheme(), and a new boxtype alias table (resolveBoxtype()/
// setBoxtype()) that reload_scheme() uses instead of FLTK's
// Fl::set_boxtype(). DELIBERATE SIMPLIFICATION: FLTK's
// Fl::set_boxtype() has two overloads -- `set_boxtype(Fl_Boxtype,
// Fl_Boxtype)` (alias one boxtype to another's existing table row,
// draw function AND metrics together) and `set_boxtype(Fl_Boxtype,
// Fl_Box_Draw_F*, uchar,uchar,uchar,uchar, Fl_Box_Draw_Focus_F* = 0)`
// (register a wholly new FL_FREE_BOXTYPE-style custom boxtype/function
// pointer). reload_scheme() only ever uses the first form -- every
// scheme branch remaps a handful of built-in boxtypes to that scheme's
// own equivalents (`set_boxtype(FL_UP_BOX, FL_GTK_UP_BOX)`), and the
// "none"/default branch remaps them back to themselves. So only that
// alias form is ported, as a plain `Boxtype[]` lookup table
// (`boxAlias_`) rather than a real function-pointer table -- this
// deliberately does NOT reopen `drawBoxAt()`'s own documented "switch,
// not a function-pointer table" simplification (see that function's
// doc comment): the alias is a thin indirection layer resolved *before*
// the switch runs, not a replacement for it. The second, custom-
// boxtype-registration overload stays unsupported, matching
// `drawBoxAt()`'s existing FL_FREE_BOXTYPE limitation.

/// The current scheme name (always lowercase, matching FLTK's own
/// normalization), or `null` for the default look ("none"/"base", or an
/// unrecognized name). Ported from `Fl::scheme_`.
private string scheme_;

/// Boxtype-to-boxtype alias table -- `resolveBoxtype(t)` returns
/// `boxAlias_[t]` when `t` has been remapped (e.g. under the "gtk+"
/// scheme, `resolveBoxtype(Boxtype.upBox) == Boxtype.gtkUpBox`),
/// otherwise `t` itself. Identity by default (every real boxtype index
/// maps to itself) -- ported from the alias half of FLTK's
/// `fl_box_table`-indexed `Fl::set_boxtype()`.
private Boxtype[boxTable.length] boxAlias_ = identityBoxAlias();

private Boxtype[boxTable.length] identityBoxAlias()
{
    Boxtype[boxTable.length] a;
    foreach (i; 0 .. boxTable.length) a[i] = cast(Boxtype) i;
    return a;
}

/// Resolves t through the current scheme's boxtype alias table (see
/// setBoxtype()/reloadScheme()) -- e.g. under the "gtk+" scheme,
/// `resolveBoxtype(Boxtype.upBox)` returns `Boxtype.gtkUpBox`. Identity
/// (returns t unchanged) when no scheme has remapped it, or when t is
/// out of the table's range (FL_FREE_BOXTYPE-and-beyond custom values,
/// never aliased). Used by both `fl.draw`'s `drawBoxAt()` (before its
/// dispatch switch) and this module's own `boxMetrics()` just below --
/// FLTK's `Fl::set_boxtype()` copies a whole `fl_box_table` row,
/// draw function AND metrics together, so aliasing only the draw
/// function and leaving `boxDx()`/`boxDy()`/`boxDw()`/`boxDh()`/
/// `boxBg()` reading the unaliased index would silently break child
/// layout and `drawBoxFocus()`'s inset under an active scheme --
/// a layout bug that would present as a drawing bug.
///
/// Callers must not feed an already-resolved result back into
/// `fl.enumerations`' `fl_up()`/`fl_down()`/`fl_frame()` (the "give me
/// this box's pressed/frame counterpart" arithmetic on the raw enum
/// ordinal) -- those assume an unaliased index and would land on an
/// unrelated boxtype somewhere else in whatever family the resolved
/// value belongs to. No call site does this today (every `fl_down()`
/// call in the tree passes a widget's own, unresolved `box()`); keep it
/// that way rather than resolving before calling them.
Boxtype resolveBoxtype(Boxtype t)
{
    return t < boxAlias_.length ? boxAlias_[t] : t;
}

/// Remaps boxtype `from` to draw (and report metrics/the bg flag) as
/// `to` instead. Ported from the boxtype-to-boxtype overload of
/// `Fl::set_boxtype()` (`src/fl_boxtype.cxx`) -- see this section's own
/// header comment for why only this overload is ported. Pass `from` as
/// both arguments to restore identity (no remapping) for that boxtype.
void setBoxtype(Boxtype from, Boxtype to)
{
    if (from < boxAlias_.length) boxAlias_[from] = to;
}

/// Ported from `Fl_X11_Screen_Driver::get_system_scheme()`
/// (`src/drivers/X11/Fl_X11_Screen_Driver.cxx`): the `FLTK_SCHEME`
/// environment variable first, then the X resource database
/// (`XGetDefault(fl_display, key, "scheme")`, `key` being
/// `firstWindow()->xclass()` if a window exists yet, else `"fltk"`
/// matching FLTK's own hardcoded fallback -- note FLTK's
/// literal fallback is `"fltk"` even there, nothing to do with this
/// port's own `xclass()` default sentinel of the same string, see
/// `fl.window`'s row), via
/// `fl.platform_x11.getDefaultResource()`. A `null` return (neither
/// source set) means `scheme(null)` falls back to the default look,
/// matching FLTK exactly.
private string getSystemScheme()
{
    import std.process : environment;

    string s = environment.get("FLTK_SCHEME");
    if (s.length != 0) return s;

    version (linux)
    {
        auto win = firstWindow();
        string key = win !is null ? win.xclass() : null;
        if (key.length == 0) key = "fltk";
        return platformX11.getDefaultResource(key, "scheme");
    }
    else return null;
}

/**
 * Sets the current widget scheme; `null`/empty re-reads
 * `getSystemScheme()` (the `FLTK_SCHEME` environment variable). Ported
 * from `Fl::scheme(const char*)`: "none"/"base"/unrecognized all
 * normalize to `null` (the default look); "gtk+"/"plastic"/"gleam"/
 * "oxy" normalize to their lowercase form regardless of the case
 * passed in (matching FLTK's `fl_ascii_strcasecmp()`-based case-
 * insensitive matching, `isScheme()` below is deliberately still case-
 * SENSITIVE against the now-normalized `scheme_`, matching FLTK's
 * own documented performance rationale). Calls `reloadScheme()`
 * unconditionally, same as FLTK. Returns true if a real
 * (non-default) scheme ended up active.
 */
bool scheme(string s)
{
    import std.uni : toLower;

    if (s.length == 0) s = getSystemScheme();

    if (s.length != 0)
    {
        string lower = s.toLower();
        switch (lower)
        {
        case "gtk+": case "plastic": case "gleam": case "oxy":
            s = lower;
            break;
        default: // "none", "base", or anything unrecognized
            s = null;
            break;
        }
    }

    scheme_ = s;
    reloadScheme();
    return s.length != 0;
}

/// Returns the current scheme name (already lowercase), or `null` for
/// the default look. Ported from `Fl::scheme()`.
string scheme() { return scheme_; }

/**
 * Returns whether the current scheme is name -- a fast, case-SENSITIVE
 * string compare against the already-normalized (lowercase) `scheme_`,
 * matching FLTK's own documented performance rationale ("you must
 * provide a lowercase string"). Ported from `Fl::is_scheme(const
 * char*)`. Always false while no scheme is active (`scheme_ is null`),
 * matching FLTK regardless of what `name` is.
 */
bool isScheme(string name)
{
    return scheme_.length != 0 && name == scheme_;
}

/**
 * (Re)applies the current scheme's boxtype remapping and scrollbar
 * size. Ported from `Fl::reload_scheme()` (`src/Fl_get_system_colors.cxx`)
 * -- every scheme branch there only ever calls the boxtype-to-boxtype
 * form of `Fl::set_boxtype()` (see this section's own header comment),
 * remapping the same 10 boxtypes (`upFrame`/`downFrame`/`thinUpFrame`/
 * `thinDownFrame`/`upBox`/`downBox`/`thinUpBox`/`thinDownBox`/
 * `roundUpBox`/`roundDownBox`) to that scheme's own equivalents, plus a
 * `scrollbarSize()` change (16 for "plastic"/default, 15 for the other
 * three). The "none"/default branch remaps those same 10 boxtypes back
 * to themselves (identity) rather than to a *different* raw function
 * pointer the way FLTK's own `else` branch technically does
 * (`set_boxtype(FL_UP_BOX, fl_up_box, D1,D1,D2,D2)`, restoring the
 * built-in) -- functionally identical here, since this port's `upBox`
 * case in `drawBoxAt()` already *is* the built-in.
 *
 * The "plastic" scheme's `Fl_Tiled_Image` window-background tile is
 * real too. See `plasticSchemeTile()`
 * (below) for the tile itself, and this function's own closing loop
 * (ported from `reload_scheme()`'s own `for (win = first_window();
 * ...)`) for how it's pushed onto every open window.
 *
 * Every scheme's own boxtype family ("gleam"/"gtk+"/"oxy"/"plastic",
 * plus "none"/default) is ported, so `fl.draw.drawBoxAt()` has a real
 * `case` for every boxtype any scheme remaps to.
 */
void reloadScheme()
{
    switch (scheme_)
    {
    case "gtk+":
        setBoxtype(Boxtype.upFrame, Boxtype.gtkUpFrame);
        setBoxtype(Boxtype.downFrame, Boxtype.gtkDownFrame);
        setBoxtype(Boxtype.thinUpFrame, Boxtype.gtkThinUpFrame);
        setBoxtype(Boxtype.thinDownFrame, Boxtype.gtkThinDownFrame);
        setBoxtype(Boxtype.upBox, Boxtype.gtkUpBox);
        setBoxtype(Boxtype.downBox, Boxtype.gtkDownBox);
        setBoxtype(Boxtype.thinUpBox, Boxtype.gtkThinUpBox);
        setBoxtype(Boxtype.thinDownBox, Boxtype.gtkThinDownBox);
        setBoxtype(Boxtype.roundUpBox, Boxtype.gtkRoundUpBox);
        setBoxtype(Boxtype.roundDownBox, Boxtype.gtkRoundDownBox);
        scrollbarSize(15);
        schemeBg_ = null;
        break;

    case "plastic":
        setBoxtype(Boxtype.upFrame, Boxtype.plasticUpFrame);
        setBoxtype(Boxtype.downFrame, Boxtype.plasticDownFrame);
        setBoxtype(Boxtype.thinUpFrame, Boxtype.plasticUpFrame);
        setBoxtype(Boxtype.thinDownFrame, Boxtype.plasticDownFrame);
        setBoxtype(Boxtype.upBox, Boxtype.plasticUpBox);
        setBoxtype(Boxtype.downBox, Boxtype.plasticDownBox);
        setBoxtype(Boxtype.thinUpBox, Boxtype.plasticThinUpBox);
        setBoxtype(Boxtype.thinDownBox, Boxtype.plasticThinDownBox);
        setBoxtype(Boxtype.roundUpBox, Boxtype.plasticRoundUpBox);
        setBoxtype(Boxtype.roundDownBox, Boxtype.plasticRoundDownBox);
        scrollbarSize(16);
        schemeBg_ = plasticSchemeTile();
        break;

    case "gleam":
        setBoxtype(Boxtype.upFrame, Boxtype.gleamUpFrame);
        setBoxtype(Boxtype.downFrame, Boxtype.gleamDownFrame);
        setBoxtype(Boxtype.thinUpFrame, Boxtype.gleamUpFrame);
        setBoxtype(Boxtype.thinDownFrame, Boxtype.gleamDownFrame);
        setBoxtype(Boxtype.upBox, Boxtype.gleamUpBox);
        setBoxtype(Boxtype.downBox, Boxtype.gleamDownBox);
        setBoxtype(Boxtype.thinUpBox, Boxtype.gleamThinUpBox);
        setBoxtype(Boxtype.thinDownBox, Boxtype.gleamThinDownBox);
        setBoxtype(Boxtype.roundUpBox, Boxtype.gleamRoundUpBox);
        setBoxtype(Boxtype.roundDownBox, Boxtype.gleamRoundDownBox);
        scrollbarSize(15);
        schemeBg_ = null;
        break;

    case "oxy":
        setBoxtype(Boxtype.upFrame, Boxtype.oxyUpFrame);
        setBoxtype(Boxtype.downFrame, Boxtype.oxyDownFrame);
        setBoxtype(Boxtype.thinUpFrame, Boxtype.oxyThinUpFrame);
        setBoxtype(Boxtype.thinDownFrame, Boxtype.oxyThinDownFrame);
        setBoxtype(Boxtype.upBox, Boxtype.oxyUpBox);
        setBoxtype(Boxtype.downBox, Boxtype.oxyDownBox);
        setBoxtype(Boxtype.thinUpBox, Boxtype.oxyThinUpBox);
        setBoxtype(Boxtype.thinDownBox, Boxtype.oxyThinDownBox);
        setBoxtype(Boxtype.roundUpBox, Boxtype.oxyRoundUpBox);
        setBoxtype(Boxtype.roundDownBox, Boxtype.oxyRoundDownBox);
        scrollbarSize(15);
        schemeBg_ = null;
        break;

    default: // "none"/default -- restore identity
        setBoxtype(Boxtype.upFrame, Boxtype.upFrame);
        setBoxtype(Boxtype.downFrame, Boxtype.downFrame);
        setBoxtype(Boxtype.thinUpFrame, Boxtype.thinUpFrame);
        setBoxtype(Boxtype.thinDownFrame, Boxtype.thinDownFrame);
        setBoxtype(Boxtype.upBox, Boxtype.upBox);
        setBoxtype(Boxtype.downBox, Boxtype.downBox);
        setBoxtype(Boxtype.thinUpBox, Boxtype.thinUpBox);
        setBoxtype(Boxtype.thinDownBox, Boxtype.thinDownBox);
        setBoxtype(Boxtype.roundUpBox, Boxtype.roundUpBox);
        setBoxtype(Boxtype.roundDownBox, Boxtype.roundDownBox);
        scrollbarSize(16);
        schemeBg_ = null;
        break;
    }

    // Set (or clear) the background tile for all open windows -- ported
    // from reload_scheme()'s own closing loop (needs firstWindow()/
    // nextWindow(), both real). Deliberately unconditional (runs
    // for every scheme, not just "plastic"): matches FLTK exactly,
    // and is how a window that *was* showing the plastic tile gets its
    // image/label/align cleanly reset back to normal when switching
    // away from "plastic" to any other scheme.
    for (auto win = firstWindow(); win !is null; win = nextWindow(win))
    {
        win.labeltype(schemeBg_ !is null ? Labeltype.normalLabel : Labeltype.noLabel);
        win.alignment(alignCenter | alignInside | alignClip);
        win.image(schemeBg_);
        win.redraw();
    }
}

/**
 * Builds (or rebuilds) the "plastic" scheme's tiled window-background
 * image. Ported from `Fl::reload_scheme()`'s own "plastic" branch
 * (`src/Fl_get_system_colors.cxx`) plus the static `tile`/`tile_cmap`/
 * `tile_xpm` it references (`src/tile.xpm`): a 64x64 XPM, 3 shades of
 * gray recomputed every call from the current `backgroundColor`
 * (`FL_GRAY` FLTK) so the tile always matches the active color
 * scheme, in 4-row repeating stripes (`o`/`.`/`o`/`O`, 16 repeats --
 * built with a loop here rather than hand-transcribing 64 near-
 * identical literal strings, same pixel pattern either way).
 *
 * **Deliberate mechanism difference from FLTK**: FLTK mutates
 * a single process-wide `static char tile_cmap[3][32]` buffer in place
 * (via `snprintf()`) and calls `tile.uncache()` to invalidate whatever
 * X11 pixmap was rendered from the old colors, relying on `Fl_Pixmap`
 * holding a `char**` *pointer* into that same mutable buffer so the
 * next draw re-reads the new colors. This port's `Pixmap` (like
 * FLTK's own char-pointer-punning `MultiLabel`/`FileIcon`
 * alternatives elsewhere in this project) takes an immutable data
 * array frozen at construction, so there's nothing to mutate in place
 * -- a fresh `Pixmap` (and wrapping `TiledImage`) is built each call
 * instead, with the newly-computed color strings baked in directly.
 * Same observable result (the tile always reflects the current
 * background color), different, more idiomatic-for-D mechanism.
 *
 * **Known limitation, faithfully inherited from FLTK, not a port
 * bug**: the returned `TiledImage`'s own `w()`/`h()` are genuinely `0`
 * (`new TiledImage(pixmap, 0, 0)`, matching FLTK's own
 * `Fl_Tiled_Image(&tile, 0, 0)` exactly -- FLTK's own comment
 * there: "giving to the tiled image the screen size may fail with
 * multiscreen configurations, so we leave it with w = h = 0 (STR
 * #3106)"). The generic label-drawing path this feeds into
 * (`fl.draw.fl_draw()`'s image branches, `Fl_Label::draw()` FLTK)
 * draws an attached image via its own natural size (the 2-arg
 * `Image.draw(x,y)`, which resolves to `draw(x,y,w(),h())`) -- for a
 * genuinely `0`-sized tile, that draws nothing at all, so a plain
 * `Window` with the plastic background set (via `fl.window.Window
 * .show()`, see that module) shows a flat color, not a visible tile.
 * This is **FLTK's own documented, acknowledged limitation**, not
 * something this port introduced: `Fl_Tiled_Image`'s own class doc
 * comment (`FL/Fl_Tiled_Image.H`) says outright, "Setting an image
 * (label) for a window may not work as expected due to implementation
 * constraints in FLTK 1.3.x and maybe later... \todo Fix
 * Fl_Tiled_Image as background image for widgets and windows," and
 * recommends the exact workaround FLTK users have always needed:
 * set the tiled image on a plain child `Fl_Group`/`Box` filling the
 * window instead of on the window itself. Originally ported faithfully
 * (bug included) rather than silently fixed, per CONVENTIONS.md's "raise
 * any other exceeds-FLTK idea before acting on it" policy --
 * flagged to the user rather than decided unilaterally.
 *
 * `fl.window.Window.drawBackdrop()`
 * special-cases a `TiledImage` before building the generic `Label`,
 * bypassing the natural-size 2-arg image draw (wrong for a deliberately
 * 0-sized tile) and calling the tiling-aware 4-arg overload directly
 * with the window's real size instead -- see that method's own doc
 * comment in `fl.window.d` for the exact code, and `smoke-tests/
 * plastic_tile.d` for a visual check. See `PORTING.md`'s
 * `FL/Fl_Window.H` row for the full writeup.
 */
private Image plasticSchemeTile()
{
    ubyte r, g, b;
    fldraw.colorToRgb8(backgroundColor, r, g, b);

    // Matches FLTK's own `levels[]`/`"Oo."[i]` scaling exactly --
    // "OSX 10.3 and higher use a background with less contrast" per
    // that array's own comment there, kept verbatim rather than the
    // commented-out higher-contrast alternative right above it in the
    // real source.
    static immutable ubyte[3] levels = [0xff, 0xf8, 0xf4];
    string[3] colorLine;
    static immutable char[3] key = ['O', 'o', '.'];
    foreach (i; 0 .. 3)
    {
        int nr = levels[i] * r / 0xe8; if (nr > 255) nr = 255;
        int ng = levels[i] * g / 0xe8; if (ng > 255) ng = 255;
        int nb = levels[i] * b / 0xe8; if (nb > 255) nb = 255;
        colorLine[i] = format("%c c #%02x%02x%02x", key[i], nr, ng, nb);
    }

    enum oRow = "oooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo";
    enum dotRow = "................................................................";
    enum bigORow = "OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO";

    string[] xpm = ["64 64 3 1", colorLine[0], colorLine[1], colorLine[2]];
    foreach (i; 0 .. 16)
    {
        xpm ~= oRow;
        xpm ~= dotRow;
        xpm ~= oRow;
        xpm ~= bigORow;
    }

    return new TiledImage(new Pixmap(xpm), 0, 0);
}

private Image schemeBg_;

/// The current scheme's tiled window-background image (only "plastic"
/// has one; `null` for every other scheme). `fl.window.Window.show()`
/// applies this to itself on every call, matching FLTK's own
/// `Fl_Window::show()` (`image(Fl::scheme_bg_);` unconditionally, so a
/// window created *after* `scheme("plastic")` was already set still
/// picks it up -- `reloadScheme()`'s own window-update loop only
/// reaches windows that already existed at the time it ran).
Image schemeBg() { return schemeBg_; }

unittest
{
    // scheme()/isScheme()/resolveBoxtype(): pure logic, no display
    // needed. Restores the default scheme at the end so other tests
    // (and boxMetrics()'s own unittest) see the identity alias, same
    // "restore the default for other tests" convention as
    // boxShadowWidth()'s/boxBorderRadiusMax()'s own unittests.
    assert(scheme() is null);
    assert(!isScheme("gtk+"));
    assert(resolveBoxtype(Boxtype.upBox) == Boxtype.upBox);

    // Case-insensitive on the way in, normalized to lowercase, and
    // isScheme() matches only the normalized (lowercase) form.
    assert(scheme("GTK+") == true);
    assert(scheme() == "gtk+");
    assert(isScheme("gtk+"));
    assert(!isScheme("plastic"));
    assert(resolveBoxtype(Boxtype.upBox) == Boxtype.gtkUpBox);
    assert(resolveBoxtype(Boxtype.downBox) == Boxtype.gtkDownBox);
    assert(resolveBoxtype(Boxtype.roundUpBox) == Boxtype.gtkRoundUpBox);
    assert(scrollbarSize() == 15);
    // A boxtype no scheme ever touches (e.g. flatBox) stays identity.
    assert(resolveBoxtype(Boxtype.flatBox) == Boxtype.flatBox);

    // "none"/"base"/unrecognized all normalize to no scheme (null),
    // restoring every remapped boxtype to identity and scrollbarSize()
    // to 16 -- unconditionally, even if an app had called
    // scrollbarSize(N) itself. That's FLTK's own behavior
    // (reload_scheme()'s default branch hardcodes 16 too, it doesn't
    // preserve a caller's override), not a D-port regression -- ported
    // faithfully, not asserting it as a design endorsement.
    assert(scheme("base") == false);
    assert(scheme() is null);
    assert(!isScheme("gtk+"));
    assert(resolveBoxtype(Boxtype.upBox) == Boxtype.upBox);
    assert(scrollbarSize() == 16);

    assert(scheme("not-a-real-scheme") == false);
    assert(scheme() is null);

    // Each of the other three schemes remaps upBox to its own equivalent.
    scheme("plastic");
    assert(resolveBoxtype(Boxtype.upBox) == Boxtype.plasticUpBox);
    assert(scrollbarSize() == 16);
    // "plastic" builds a real tiled window-background image --
    // headless-safe to check directly (Pixmap/
    // TiledImage construction itself needs no live display).
    assert(schemeBg_ !is null);

    scheme("gleam");
    assert(resolveBoxtype(Boxtype.upBox) == Boxtype.gleamUpBox);
    assert(scrollbarSize() == 15);
    // Switching away from "plastic" clears the background image.
    assert(schemeBg_ is null);

    scheme("oxy");
    assert(resolveBoxtype(Boxtype.upBox) == Boxtype.oxyUpBox);
    assert(scrollbarSize() == 15);

    // setBoxtype()'s metrics-routing: boxDx()/boxDw()/boxBg() (fl.core's
    // own boxMetrics()) follow the same alias resolveBoxtype() does --
    // gtkThinUpBox's metrics (1,1,2,2, bg=false, per its own boxTable
    // row -- see FLTK_ISSUES.md's "inconsistent bg/frame flags"
    // candidate for why bg is false there) must show through plain
    // thinUpBox once "gtk+" remaps it, not thinUpBox's own (1,1,2,2,
    // bg=true).
    scheme("gtk+");
    assert(boxDx(Boxtype.thinUpBox) == 1 && boxDw(Boxtype.thinUpBox) == 2);
    assert(boxBg(Boxtype.thinUpBox) == false);

    // Restore the default for other tests -- "base" (not null/empty)
    // deliberately, so this doesn't depend on whether FLTK_SCHEME
    // happens to be set in whatever environment `dub test` runs in
    // (scheme(null)/scheme("") would re-read it, matching FLTK, but
    // that's exactly the environment-dependence this restore needs to
    // avoid).
    scheme("base");
    assert(scheme() is null);
    assert(scrollbarSize() == 16);
}

Widget readqueue()
{
    return widgetQueuePop();
}

/**
 * Top-level event dispatcher -- ported from Fl::handle()/Fl::handle_()
 * (Fl.cxx), collapsed into a single function here since FLTK's
 * split only exists to support a user-installable Fl::event_dispatch()
 * hook (an exception-wrapping mechanism), which isn't ported -- nothing
 * calls add_handler()-style customization yet.
 *
 * This is the piece that turns "here's a raw event and which window it
 * happened in" into the right widget getting Widget.handle() called on
 * it, using pushed()/focus()/belowmouse() to route push/drag/release/
 * keyboard/shortcut events correctly -- e.g. FL_DRAG must go straight
 * to pushed() (not be re-routed through window's own child-hit-testing
 * every time), and FL_RELEASE must clear pushed() *before* dispatch.
 * fl.group's handle()/navigation() (already faithfully ported and
 * tested) handles everything *within* a widget tree once the right
 * event reaches the right starting widget; this is what finds that
 * starting widget.
 *
 * Fl_Tooltip notifications are wired up too: rather
 * than replicating each of FLTK's own scattered FL_ENTER/FL_MOVE/
 * FL_LEAVE call sites individually, this port centralizes the "call
 * Tooltip::enter() when belowmouse() changes" behavior into
 * belowmouse()'s own setter below (see that function's doc comment for
 * why that's behaviorally equivalent) -- only the FL_PUSH (`Event.push`)
 * and FL_KEYBOARD (`Event.keyDown`) cases below need their own explicit
 * calls, since those don't go through a belowmouse() change.
 *
 * Real `modal()` filtering is ported too --
 * see `modal()`'s own doc comment for why a plain `grab()`-as-modal
 * substitute is the wrong architecture. Every case below that FLTK's own `Fl::handle_()` checks
 * `modal()` in does too, verified against the actual FLTK
 * source line-by-line (`src/Fl.cxx`) rather than guessed at:
 *  - `Event.push`: `if (grab()) wi = grab(); else if (modal() && wi !=
 *    modal()) return 0;` -- a push landing on a non-modal window is
 *    discarded outright (not redirected anywhere), so there's no
 *    coordinate-translation concern the way the old `grab()`-redirect
 *    approach had.
 *  - `Event.move`/`Event.drag`: the `modal()` check applies **only**
 *    in the not-already-`pushed()` branch -- an in-progress drag just
 *    keeps following `pushed_`, unaffected, exactly matching FLTK's
 *    own branching (confirmed: `if (pushed()) {...break;} if (modal()
 *    ...) wi = 0;`).
 *  - `Event.release`: falls back to `modal()` only when `pushed_` is
 *    already null (a stray release with nothing pushed) -- `pushed_`
 *    itself already carries any `Event.push`-time `grab()`-redirect
 *    through correctly, so no separate `grab()` branch is needed here
 *    (same reasoning already established for `Event.move`/`Event.drag`
 *    before this modal() addition, see git history/PORTING.md).
 *  - `Event.shortcut`: the no-grab fallback (both the belowmouse-walk
 *    starting point and the Escape-closes-window target) now prefers
 *    `modal()` over plain `window`, matching FLTK's `wi = modal();
 *    if (!wi) wi = window;`.
 *  - `Event.mouseWheel`: redirects to
 *    `grab()` first (if it's not also `modal()`/`window`), else
 *    `modal()`, matching FLTK's compound condition exactly.
 *  - `Event.close` (`fl.enumerations`): `if (grab() || (modal()
 *    && window != modal())) return 0; wi.doCallback(CallbackReason.
 *    closed); return 1;`, matching FLTK's own `FL_CLOSE` case.
 *    WM_DELETE_WINDOW dispatches through this case, so ordinary windows
 *    without a custom `callback()` rely on `fl.window.Window`'s own
 *    default callback (`Fl_Window::default_callback`/
 *    `Fl::default_atclose`, see that module) to close normally.
 *  - `Event.keyDown` needs no modal-specific change at all: since
 *    `fl.ask`'s dialogs never call `grab()` (see `modal()`'s doc
 *    comment), the existing, unmodified `for (wi = grab() ? grab() :
 *    focus(); ...)` already reaches `focus()` correctly on its own --
 *    exactly FLTK's real behavior, since FLTK's real modal
 *    dialogs never grab either.
 *
 * `fixFocus()` (below `belowmouse()`) is the other half of this: it
 * pins keyboard focus inside `modal()`'s subtree whenever it's set,
 * matching FLTK's `fl_fix_focus()` -- see that function's own doc
 * comment.
 *
 * Still not ported: raising the clicked window to the top on FL_PUSH
 * (single-window scope so far). The add_handler() chain and sendEvent()'s
 * subwindow coordinate-offset adjustment are both real -- see
 * addHandler()'s and sendEvent()'s own doc comments (core-roadmap
 * items 1 and 5).
 */
int handle(Event e, Widget window)
{
    eNumber_ = e;
    // Ported from `Fl::handle_()`'s own `if (fl_local_grab) return
    // fl_local_grab(e);` -- `fl.platform_x11.dnd()`'s drag loop installs
    // this while a drag-and-drop session is in progress, so that
    // ordinary X-driven events reaching the main loop while dragging
    // (mouse motion over the *source* window, its own button release)
    // don't get dispatched normally; the loop's own synthetic
    // `Event.dndEnter`/`dndDrag`/etc. calls (via `localHandle()`) briefly
    // clear this first so they aren't swallowed too. See `localGrab()`'s
    // own doc comment.
    if (localGrab_ !is null) return localGrab_(e);
    Widget wi = window;

    switch (e)
    {
    case Event.push:
        // Ported from Fl::handle_()'s own FL_PUSH case: `if (grab())
        // wi = grab(); else if (modal() && wi != modal()) return 0;`.
        // grab() (a real single-widget grab-owner, e.g. an open popup
        // menu) takes priority; failing that, a click on any window
        // other than the current modal one is discarded outright --
        // never dispatched anywhere, so there's no question of stale
        // coordinates landing on the wrong widget in a foreign window.
        if (grab() !is null) wi = grab();
        else if (modal() !is null && wi !is modal()) return 0;
        pushed_ = wi;
        // Ported from Fl::handle_()'s own FL_PUSH case: acts as though
        // the clicked widget was entered, but without popping up a
        // tooltip -- prevents one reappearing right after a click just
        // because the mouse is still over the same widget.
        fl.tooltip.current(wi);
        // FL_PUSH always reports "handled", matching FLTK: even if
        // no widget wants it, clicking a window is meaningful (FLTK
        // then raises the window -- not ported, see the doc comment).
        sendEvent(e, wi, window);
        return 1;

    case Event.move:
    case Event.drag:
        // `grab()` must be re-checked here, not just relying on
        // `pushed_` to already carry any grab-redirected
        // target through from Event.push: that's only true when a grab was
        // *already* active at the time of that Event.push. It's false
        // for the far more common case a popup menu actually exercises:
        // the grab is established *during* the dispatch of that same
        // Event.push (`MenuButton.handle()`'s FL_PUSH case calling
        // `popup()`, which calls `fl.core.grab()`, synchronously, from
        // inside the very `sendEvent()` call below that dispatches the
        // click). At that point `pushed_` is already latched to the
        // *original* clicked widget (the MenuButton), not the popup
        // window -- so without this re-check, every subsequent drag/release while still
        // holding the mouse button down would route to the MenuButton
        // instead of the open popup, silently eating the whole press-
        // drag-release gesture. Ported from FLTK's real
        // `Fl::handle_()` FL_MOVE/FL_DRAG case exactly: `if (pushed())
        // { wi = pushed(); if (grab()) wi = grab(); ...} if (modal() &&
        // wi != modal()) wi = 0; if (grab()) wi = grab();` -- grab()
        // always wins, in both the pushed and not-pushed branches.
        if (pushed_ !is null)
        {
            wi = pushed_;
            if (grab() !is null) wi = grab();
            e = Event.drag;
        }
        else
        {
            if (modal() !is null && wi !is modal()) wi = null;
            if (grab() !is null) wi = grab();
        }
        return wi !is null ? sendEvent(e, wi, window) : 0;

    case Event.release:
        // Same reasoning as Event.move/drag just above: `grab()` is checked -- and
        // takes priority over `pushed_` -- exactly matching FLTK's
        // real FL_RELEASE case (`if (grab()) {wi = grab(); ...} else if
        // (pushed()) {wi = pushed(); ...} else if (modal() && wi !=
        // modal()) return 0;`). `pushed_` is still cleared here (not
        // just when grabbed) since a release with no grab active should
        // still end the drag/click sequence normally.
        if (grab() !is null)
        {
            wi = grab();
            if (!eventButtons()) pushed_ = null;
        }
        else if (pushed_ !is null)
        {
            wi = pushed_;
            if (!eventButtons()) pushed_ = null;
        }
        else if (modal() !is null && wi !is modal())
        {
            return 0;
        }
        return sendEvent(e, wi, window);

    case Event.keyDown:
        // Ported from Fl::handle_()'s unconditional `Fl_Tooltip::enter(
        // (Fl_Widget*)0);` at the top of its own FL_KEYBOARD case --
        // any keypress dismisses a showing/pending tooltip, regardless
        // of where the mouse is. Calls `dismissNow()`, not
        // `mouseEnter(null)`: `mouseEnter(null)` doesn't mean
        // "dismiss immediately", since a null target also arises
        // naturally from an ordinary `belowmouse()` transition (see
        // that function's own doc comment); `dismissNow()` is the real
        // "hide this right now regardless of the mouse" entry point.
        fl.tooltip.dismissNow();

        // Ported from Fl::handle_()'s `for (wi = grab() ? grab() :
        // focus(); ...)` verbatim -- no modal()-specific handling
        // needed here at all: real modal dialogs never grab (see
        // modal()'s own doc comment), so grab() is null while one is
        // open and this naturally reaches focus() (e.g. fl_input()'s
        // own Input field, via fl.ask's takeFocus() call) with no
        // special-casing, exactly like FLTK.
        for (wi = grab() !is null ? grab() : focus_; wi !is null; wi = wi.parent)
            if (sendEvent(Event.keyDown, wi, window)) return 1;
        if (handle(Event.shortcut, window)) return 1;

        // Without this, a
        // plain, unshifted Alt+F wouldn't open a "&File" menu, only
        // Alt+Shift+F would. Ported from the tail of FLTK's own
        // FL_KEYBOARD case (`Fl::handle_()`, `Fl.cxx`) -- a genuinely
        // separate, *unconditional* mechanism from
        // `Widget.testShortcut()`'s own comparison (that one really is
        // exact-case, no fallback, confirmed against a live, debug-
        // instrumented build of FLTK on this same machine: a first
        // `Event.shortcut` attempt with the untouched eventText() fails
        // to match "&File" against plain lowercase "f", exactly as this
        // port's own `testShortcut()` does). What FLTK does *next*,
        // which this port was missing entirely: swap the case of
        // `event_text()`'s first character in place and retry the whole
        // `FL_SHORTCUT` dispatch a second time -- matching "&File"
        // against the swapped-to-uppercase "F". This is what makes a
        // plain Alt+F (no Shift) open a "&File" menu on every platform,
        // including Linux/X11 -- not a Darwin-only fallback the way the
        // OTHER case-insensitive mechanism in `Fl_Widget::test_shortcut()`
        // is (see that function's own already-correct doc comment; this
        // is a second, different mechanism one level up the call stack).
        // ASCII-only (`isAlpha`/`toUpper`/`toLower`), matching FLTK's
        // own `fl_ascii_*` helpers here exactly.
        if (eText_.length == 0) return 0;
        {
            import std.ascii : isAlpha, isUpper, toUpper, toLower;

            char c0 = eText_[0];
            if (!isAlpha(c0)) return 0;
            char swapped = isUpper(c0) ? cast(char) toLower(c0) : cast(char) toUpper(c0);
            if (swapped == c0) return 0; // no change, so don't try again
            eText_ = swapped ~ eText_[1 .. $];
        }
        return handle(Event.shortcut, window);

    case Event.shortcut:
        // Ported from Fl::handle_()'s `if (grab()) {wi = grab();
        // break;}`: grabbed shortcut dispatch goes to the grab widget
        // alone (no parent-chain walk, no add_handler()-style global
        // chain -- a grabbing widget, e.g. a menu popup, is expected to
        // handle its own Escape/cancel behavior directly, and does:
        // fl.menu_popup's own onKey() consumes Escape and returns 1).
        if (grab() !is null)
        {
            if (sendEvent(Event.shortcut, grab(), window)) return 1;
        }
        else
        {
            // Ported from FLTK's `wi = find_active(belowmouse());
            // if (!wi) { wi = modal(); if (!wi) wi = window; } ...`,
            // minus the find_active()/first_window() cross-window
            // routing (still not ported, single-window scope) -- the
            // modal() preference itself is real.
            wi = belowmouse_ !is null ? belowmouse_ : (modal() !is null ? modal() : window);
            for (; wi !is null; wi = wi.parent)
                if (sendEvent(Event.shortcut, wi, window)) return 1;
        }

        // Ported from FLTK's own `// try using add_handle()
        // functions: if (send_handlers(FL_SHORTCUT)) return 1;`
        // (see sendHandlers()'s own doc comment): gives every add_handler()-
        // registered global handler a chance at an otherwise-
        // unclaimed shortcut (e.g. an app-wide accelerator key with no
        // widget of its own) before falling to the Escape-closes-window
        // fallback below.
        if (sendHandlers(Event.shortcut)) return 1;

        // Escape closes windows -- ported from the tail of Fl::handle_()'s
        // own FL_SHORTCUT case: `wi = modal(); if (!wi) wi = window;
        // wi->do_callback(FL_REASON_CANCELLED);`. grab() is checked
        // first here too (not in FLTK's own version of this exact
        // line) since fl.menu_popup still relies on it for Escape
        // closing an open menu.
        if (eKeysym_ == escape)
        {
            Widget target = grab() !is null ? grab() : (modal() !is null ? modal() : window);
            if (target !is null)
            {
                target.doCallback(CallbackReason.cancelled);
                return 1;
            }
        }
        return 0;

    case Event.mouseWheel:
        // Ported from Fl::handle_()'s own FL_MOUSEWHEEL case:
        // `if (grab() && grab()!=modal() && grab()!=window) {...}
        // if (modal()) {...} if (send_event(...,window,...)) return 1;
        // default: break; } ... return send_handlers(e);` -- FLTK
        // relies on C++ switch fallthrough (no `break` before
        // `default:`) to reach the shared `send_handlers(e)` tail when
        // the final window-targeted dispatch fails; ported here as an
        // explicit call instead, same effect.
        if (grab() !is null && grab() !is modal() && grab() !is window)
        {
            if (sendEvent(Event.mouseWheel, grab(), window)) return 1;
        }
        if (modal() !is null)
        {
            sendEvent(Event.mouseWheel, modal(), window);
            return 1;
        }
        if (sendEvent(e, window, window)) return 1;
        return sendHandlers(e);

    case Event.close:
        // Ported from Fl::handle_()'s own FL_CLOSE case: `if (grab()
        // || (modal() && window != modal())) return 0; wi->do_callback
        // (FL_REASON_CLOSED); return 1;`. Backs fl.platform_x11's
        // WM_DELETE_WINDOW handling, including modal filtering.
        if (grab() !is null || (modal() !is null && wi !is modal())) return 0;
        wi.doCallback(CallbackReason.closed);
        return 1;

    case Event.dndEnter:
    case Event.dndDrag:
        // Ported from Fl::handle_()'s own FL_DND_ENTER/FL_DND_DRAG case:
        // `dnd_flag = 1; break;` -- falls through to the shared tail
        // (`if (wi && send_event(e, wi, window)) { dnd_flag = 0; return
        // 1; } dnd_flag = 0; return send_handlers(e);`), `wi` unchanged
        // (still `window`) -- fl.group's own already-real `case
        // Event.dndEnter:`/`dndDrag:` (`FlGroup.handle()`) is what
        // actually walks down to the right child and updates
        // belowmouse(). `dndFlag_` (see its own doc comment) makes any
        // nested belowmouse() call during that walk send `Event.dndLeave`
        // instead of `Event.leave`.
        dndFlag_ = true;
        if (sendEvent(e, wi, window)) { dndFlag_ = false; return 1; }
        dndFlag_ = false;
        return sendHandlers(e);

    case Event.dndLeave:
        // Ported from Fl::handle_()'s own FL_DND_LEAVE case: `dnd_flag
        // = 1; belowmouse(0); dnd_flag = 0; return 1;` -- belowmouse
        // (null)'s own ancestor-walk (see that function's doc comment)
        // is what actually sends `Event.dndLeave` to whatever was
        // belowmouse(); `dndFlag_` is what tells it to use
        // `Event.dndLeave` instead of `Event.leave` while doing so.
        dndFlag_ = true;
        belowmouse(null);
        dndFlag_ = false;
        return 1;

    case Event.dndRelease:
        // Ported from Fl::handle_()'s own FL_DND_RELEASE case: `wi =
        // belowmouse(); break;` -- dispatches straight to whichever
        // widget is currently belowmouse() (set by the dndEnter/dndDrag
        // routing above), not to `window` itself.
        wi = belowmouse();
        dndFlag_ = false;
        if (wi !is null && sendEvent(e, wi, window)) return 1;
        return sendHandlers(e);

    default:
        // FL_ENTER/FL_LEAVE/FL_FOCUS/FL_UNFOCUS/etc: send straight to
        // the window and let fl.group's already-ported handle() sort
        // out the details (child hit-testing, belowmouse() tracking, ...).
        return wi !is null ? sendEvent(e, wi, window) : 0;
    }
}

/**
 * Ported from `send_event()` (`Fl.cxx`) -- real subwindow coordinate
 * translation. `window` is whichever window actually received
 * the raw platform event (the same `window` parameter `handle()` was
 * called with) -- `eX_`/`eY_` arrive already relative to *that* window's
 * own local origin (`fl.platform_x11`'s translation), which is correct
 * as-is only when `w` (the widget actually being dispatched to) lives in
 * that same window. `w` can live in a *different*
 * (nested) window than the one that physically received the event --
 * e.g. a shortcut dispatched via `focus()`'s parent-chain walk, or a
 * modal-redirected click, can cross a subwindow boundary -- so `dx`/`dy`
 * are computed exactly as FLTK does: start from `window`'s own
 * position, then walk up from `w` through every window-type ancestor
 * (including `w` itself, if it's a window) subtracting that window's
 * position. In the common single-window (no subwindow nesting) case
 * this always nets to exactly zero -- `window` IS `w`'s one and only
 * window ancestor -- which is indistinguishable
 * from a no-op there.
 */
private int sendEvent(Event e, Widget w, Widget window)
{
    int dx = 0, dy = 0;
    if (window !is null)
    {
        dx = window.x();
        dy = window.y();
    }
    for (Widget wi = w; wi !is null; wi = wi.parent)
        if (wi.type() >= Widget.windowTypeTag) { dx -= wi.x(); dy -= wi.y(); }

    int saveX = eX_; eX_ += dx;
    int saveY = eY_; eY_ += dy;
    eNumber_ = e;
    int ret = w.handle(e);
    eY_ = saveY;
    eX_ = saveX;
    return ret;
}

/**
 * Runs the event loop until every open window has been closed.
 *
 * Forwards to fl.platform_x11's event loop, which now multiplexes the
 * X connection and the timer queue below via select() (see that
 * module's run()/waitForEventOrTimeout()). Still not ported: FLTK's
 * general Fl::add_fd()/idle-callback multiplexing (see this module's
 * top comment) -- only the X connection fd and timers are waited on.
 * A no-op on non-Linux platforms, since no other platform driver exists
 * yet.
 */
void run()
{
    version (linux) platformX11.run();
    else version (Windows) platformWin32.run();
}

// ---------------------------------------------------------------------
// Fl::delete_widget()/do_widget_deletion()
// ---------------------------------------------------------------------

private Widget[] pendingDeletions_;

/**
 * Schedules `wi` for deletion at the next safe point (the start of the
 * next `wait()`/`check()` call) instead of destroying it immediately --
 * safe to call from inside `wi`'s own callback, unlike `destroy(wi)`
 * directly, which would leave the currently-executing callback running
 * on a destroyed object. Ported from `Fl::delete_widget(Fl_Widget*)`
 * (`Fl.cxx`): hides `wi` first if visible (and, if it's a shown()
 * window, hides that too -- covers the iconified-window case FLTK's
 * own comment calls out), then queues it, skipping duplicates.
 */
void deleteWidget(Widget wi)
{
    if (wi is null) return;

    if (wi.visibleR()) wi.hide();
    auto win = wi.asWindow();
    if (win !is null && win.shown()) win.hide();

    foreach (w; pendingDeletions_)
        if (w is wi) return;
    pendingDeletions_ ~= wi;
}

/// Actually destroys every widget `deleteWidget()` has queued since the
/// last call. Ported from `Fl::do_widget_deletion()` (`Fl.cxx`); called
/// automatically at the top of `wait()`/`check()` (matching FLTK's
/// own `Fl_System_Driver::wait()` call site) -- not normally something
/// a caller needs to invoke directly.
package(fl) void doWidgetDeletion()
{
    auto pending = pendingDeletions_;
    pendingDeletions_ = null;
    foreach (w; pending) destroy(w);
}

/**
 * Runs a single iteration of the event loop -- the finer-grained
 * entry point below run()'s own `while (not-done) wait();` loop,
 * direct equivalent of FLTK's `Fl::wait()`. Forwards to
 * fl.platform_x11's wait(); a no-op on non-Linux platforms.
 *
 * Exists specifically so a nested event loop (e.g. the menu popup
 * engine's pulldown()-style "run until dismissed" loop) can pump one
 * event/timer at a time from inside handling of another event, exactly
 * like FLTK's Fl_Menu_Item::pulldown() calling Fl::wait() directly
 * rather than Fl::run().
 */
void wait()
{
    version (linux) platformX11.wait();
    else version (Windows) platformWin32.wait();
}

/**
 * Bounded-wait variant of wait() -- direct equivalent of FLTK's
 * `Fl::wait(double time_to_wait)`. Blocks for at most `timeToWait`
 * seconds instead of until the next due timer; returns `1.0` if an
 * event was processed, `0.0` on a plain timeout or once every window
 * has closed (a simplified two-value version of FLTK's
 * positive/zero/negative `double`, matching this port's existing
 * `wait()`/`check()` boolean-ish returns -- see
 * `fl.platform_x11.wait(double)`'s own doc comment for the full
 * reasoning). A no-op (always `0.0`) on non-Linux platforms.
 */
double wait(double timeToWait)
{
    version (linux) return platformX11.wait(timeToWait);
    else version (Windows) return platformWin32.wait(timeToWait);
    else return 0.0;
}

/**
 * Non-blocking variant of wait() -- the direct equivalent of FLTK's
 * `Fl::check()`. Fires due timers, repaints, and processes one already-
 * queued X event if there is one, but never blocks waiting for more:
 * callers doing their own long-running computation (a loop that isn't
 * itself driven by the event loop) can call this periodically to keep
 * the UI responsive without yielding control the way wait() would.
 * Returns whether any window is still open, matching FLTK's return
 * value; on non-Linux platforms (no event loop exists yet) always
 * returns `false`.
 */
bool check()
{
    version (linux) return platformX11.check();
    else version (Windows) return platformWin32.check();
    else return false;
}

/**
 * Ported from `Fl::flush()` -- forces any pending damage to be drawn to
 * the screen right now, without processing input events (unlike
 * `wait()`/`check()`, which also flush damage but only as a side effect
 * of waiting for/checking events). Real gap found porting
 * `source/test/checkers.d`: its `computer_move()` sets a wait cursor, calls
 * `Fl::flush()` so that cursor is actually visible, *then* runs a
 * synchronous AI search that can take a noticeable moment -- without a
 * real flush here the cursor wouldn't appear until the search finishes
 * and control returns to the event loop, defeating the point. A no-op
 * on non-Linux platforms, matching every other platform-backed
 * primitive in this module.
 */
void flush()
{
    version (linux) platformX11.flushDamage();
    else version (Windows) platformWin32.flush();
}

// ---------------------------------------------------------------------
// Timers (Fl::add_timeout()/repeat_timeout()/has_timeout()/remove_timeout())
// ---------------------------------------------------------------------

/**
 * Fl_Timeout_Handler's D equivalent: a closure invoked when the timer
 * expires. Unlike FLTK, there is no companion `void* data` slot --
 * same substitution CONVENTIONS.md documents for Callback (fl.widget): a
 * caller needing per-timer context just captures it directly. This
 * also means removeTimeout()/hasTimeout() only take one argument where
 * FLTK takes two (cb, data): comparing two D delegates with `==`
 * already compares both the function AND its closure context, doing
 * the job of FLTK's separate cb+data match in a single value.
 */
alias TimeoutHandler = void delegate();

private struct TimeoutEntry
{
    MonoTime due;
    TimeoutHandler callback;
    bool skip; // see processTimeouts()'s doc comment
}

private TimeoutEntry[] timeouts_;

// "Current" timeout bookkeeping, for repeatTimeout()'s drift-corrected
// rescheduling -- see that function's doc comment. Only one level deep
// (matching the only realistic use: repeatTimeout() called from within
// the very callback it's rescheduling), unlike FLTK's full stack
// (Fl_Timeout::current_timeout), which also has to support Fl::wait()
// reentrancy that doesn't exist in this port.
private MonoTime currentDue_;
private bool inTimeoutCallback_;

private Duration secondsToDuration(double t)
{
    return usecs(cast(long)(t * 1_000_000.0));
}

/**
 * Ported from Fl::add_timeout()/Fl_Timeout::add_timeout(). Schedules
 * cb to run once, `time` seconds from now. See TimeoutHandler's and
 * this module's own doc comments for what's simplified relative to
 * FLTK's queue.
 */
void addTimeout(double time, TimeoutHandler cb)
{
    timeouts_ ~= TimeoutEntry(MonoTime.currTime + secondsToDuration(time), cb, true);
}

/**
 * Ported from Fl::repeat_timeout()/Fl_Timeout::repeat_timeout(). Meant
 * to be called from *within* a timeout callback, to reschedule itself
 * `time` seconds after the *previous* timeout's original due time
 * (not from "now"), correcting for however late that timeout actually
 * fired so a repeating timer doesn't drift. Falls back to plain
 * addTimeout() behavior if called outside of a timeout callback
 * (matching FLTK's own `if (cur) ...` guard -- no current timeout
 * means no base time to correct from).
 */
void repeatTimeout(double time, TimeoutHandler cb)
{
    MonoTime due;
    if (inTimeoutCallback_)
    {
        due = currentDue_ + secondsToDuration(time);
        auto now = MonoTime.currTime;
        if (due < now) due = now + secondsToDuration(0.001); // at least 1ms, matching FLTK's floor
    }
    else
    {
        due = MonoTime.currTime + secondsToDuration(time);
    }
    timeouts_ ~= TimeoutEntry(due, cb, true);
}

/// Ported from Fl::has_timeout()/Fl_Timeout::has_timeout().
bool hasTimeout(TimeoutHandler cb)
{
    foreach (t; timeouts_)
        if (t.callback == cb) return true;
    return false;
}

/**
 * Ported from Fl::remove_timeout()/Fl_Timeout::remove_timeout().
 * Removes every pending timeout matching cb (matching FLTK: "this
 * method removes all matching timeouts, not just the first one").
 */
void removeTimeout(TimeoutHandler cb)
{
    size_t w = 0;
    foreach (i; 0 .. timeouts_.length)
        if (timeouts_[i].callback != cb) timeouts_[w++] = timeouts_[i];
    timeouts_.length = w;
}

/**
 * Ported from Fl_Timeout::do_timeouts(). Fires every timer whose due
 * time has passed, soonest first, repeating until none are left
 * expired -- a callback may itself schedule a new timer via
 * addTimeout()/repeatTimeout(), which are marked `skip` so they can't
 * be immediately re-fired within this same call (matching FLTK's
 * own `skip` flag, added for FLTK issue #450: without it, a timer that
 * reschedules itself with time <= 0 could loop forever inside a single
 * call).
 */
void processTimeouts()
{
    foreach (ref t; timeouts_) t.skip = false;

    bool firedAny = true;
    while (firedAny)
    {
        firedAny = false;
        if (timeouts_.length == 0) break;

        size_t soonest = size_t.max;
        MonoTime soonestDue;
        foreach (i, ref t; timeouts_)
        {
            if (t.skip) continue;
            if (soonest == size_t.max || t.due < soonestDue)
            {
                soonest = i;
                soonestDue = t.due;
            }
        }
        if (soonest == size_t.max || soonestDue > MonoTime.currTime) break;

        auto entry = timeouts_[soonest];
        timeouts_ = timeouts_[0 .. soonest] ~ timeouts_[soonest + 1 .. $];

        auto savedDue = currentDue_;
        auto savedFlag = inTimeoutCallback_;
        currentDue_ = entry.due;
        inTimeoutCallback_ = true;
        entry.callback();
        inTimeoutCallback_ = savedFlag;
        currentDue_ = savedDue;

        firedAny = true;
    }
}

/**
 * Ported from Fl_Timeout::time_to_wait(). How long fl.platform_x11's
 * event loop should block waiting for the next X event before it needs
 * to wake up and re-check timers, capped at `ttw`. Returns
 * `Duration.zero` if a timer is already due.
 */
Duration timeToWait(Duration ttw)
{
    if (timeouts_.length == 0) return ttw;
    auto now = MonoTime.currTime;
    Duration soonest = Duration.max;
    foreach (t; timeouts_)
    {
        auto d = t.due - now;
        if (d < soonest) soonest = d;
    }
    if (soonest < Duration.zero) return Duration.zero;
    return soonest < ttw ? soonest : ttw;
}

/// Ported from `Fl_FD_Handler` (`FL/core/function_types.H`) -- a D
/// delegate rather than a C function pointer + `void*` data slot, per
/// this port's usual substitution (see `TimeoutHandler` just above, and
/// `Callback` in `fl.widget`): a delegate already carries its own
/// captured context, so FLTK's separate `void*` parameter has no D
/// equivalent here either.
alias FdHandler = void delegate(int fd);

package(fl) struct FdEntry
{
    int fd;
    FdWhen when;
    FdHandler callback;
}

/// Registered `addFd()` entries -- a plain dynamic array scanned
/// linearly, not FLTK's hand-managed `realloc()`-grown C array
/// (`Fl_Unix_Screen_Driver::fd`/`pollfds`) -- the GC makes FLTK's
/// manual capacity bookkeeping moot, matching the same reasoning
/// already applied to the timer queue above.
private FdEntry[] fdEntries_;

/**
 * Ported from `Fl::add_fd(int, int, Fl_FD_Handler, void*)` (`Fl.H` +
 * `Fl_Unix_System_Driver::add_fd()`) -- registers `cb` to be called
 * whenever `fd` becomes ready for whichever of `fdRead`/`fdWrite`/
 * `fdExcept` (combined with `|`) `when` asks for: from `fl.platform_x11`'s
 * event loop on Linux (a real `select()`, see `waitForEventOrTimeout()`),
 * or `fl.platform_win32`'s on Windows (`fdRead` only, via a short-
 * interval `PeekNamedPipe()` poll rather than a true wait -- see
 * `pollFds()`'s own doc comment for why Windows can't wait on an
 * anonymous pipe the way `select()` can). Re-registering the same `fd`
 * for overlapping `when` bits replaces the callback for those specific
 * bits (via `removeFd()` below, matching FLTK's own
 * `remove_fd(n,events)` call at the top of its `add_fd()`) rather than
 * adding a second, competing entry.
 *
 * Exercised by `source/examples/howto_add_fd_and_popen.d` (a piped
 * child process's stdout), the only consumer in this project so far.
 */
void addFd(int fd, FdWhen when, FdHandler cb)
{
    removeFd(fd, when);
    fdEntries_ ~= FdEntry(fd, when, cb);
}

/// Ported from `Fl::add_fd(int, Fl_FD_Handler, void*)` -- the 1-arg
/// `when` overload, defaulting to `fdRead` (matching FLTK's own
/// `add_fd(n, cb, v) { add_fd(n, POLLIN, cb, v); }`).
void addFd(int fd, FdHandler cb)
{
    addFd(fd, fdRead, cb);
}

/**
 * Ported from `Fl::remove_fd(int, int)` (`Fl_Unix_System_Driver::
 * remove_fd()`) -- clears `when`'s bits from any entry registered for
 * `fd`, dropping the entry entirely once none of its bits remain
 * (matching FLTK's own "if no events left, delete this fd").
 */
void removeFd(int fd, FdWhen when)
{
    size_t w = 0;
    foreach (i; 0 .. fdEntries_.length)
    {
        if (fdEntries_[i].fd == fd)
        {
            FdWhen remaining = fdEntries_[i].when & ~when;
            if (remaining == 0) continue; // drop this entry
            fdEntries_[i].when = remaining;
        }
        fdEntries_[w++] = fdEntries_[i];
    }
    fdEntries_.length = w;
}

/// Ported from `Fl::remove_fd(int)` -- removes every entry for `fd`
/// regardless of `when` (matching FLTK's own `remove_fd(n, -1)`,
/// `-1` being "every bit set" for a C `int`; `fdRead | fdWrite |
/// fdExcept` is the same thing spelled out for this port's 3-bit set).
void removeFd(int fd)
{
    removeFd(fd, fdRead | fdWrite | fdExcept);
}

/// package(fl): fl.platform_x11's waitForEventOrTimeout() reads this
/// each iteration to fold every registered fd into its own select()
/// call, and to know which callback to invoke once one becomes ready.
/// Returns a defensive copy so a callback that itself calls addFd()/
/// removeFd() while being iterated over can't corrupt the caller's own
/// in-progress loop.
package(fl) FdEntry[] fdEntries()
{
    return fdEntries_.dup;
}

// ---------------------------------------------------------------------
// Fl::add_idle()/has_idle()/remove_idle() (Fl.H + src/Fl_add_idle.cxx)
// ---------------------------------------------------------------------

/// Ported from `Fl_Idle_Handler` (`FL/core/function_types.H`) -- a D
/// delegate rather than a C function pointer + `void*` data slot, same
/// substitution as `FdHandler`/`TimeoutHandler` above: a delegate
/// already carries its own captured context, so FLTK's separate
/// `void*` parameter (and the `Fl_Old_Idle_Handler`/no-data overload
/// it exists to support) has no D equivalent here.
alias IdleHandler = void delegate();

/// Registered `addIdle()` callbacks, in call order. Ported from
/// `Fl_add_idle.cxx`'s `first`/`last`/`freelist` linked ring (a manual
/// free-list of `idle_cb` nodes, purely to avoid `malloc()`/`free()`
/// per add/remove) -- a plain GC-backed dynamic array needs no such
/// bookkeeping, `~=`/slicing already do what the ring existed for.
private IdleHandler[] idleHandlers_;

/// True while `runIdle()` is executing a callback -- ported from
/// `Fl::Private::run_idle()`'s static `in_idle` guard ("FLTK will not
/// recursively call the idle callback").
private bool inIdle_;

/**
 * Adds `cb` to the set of idle callbacks -- ported from
 * `Fl::add_idle(Fl_Idle_Handler, void*)`. Called repeatedly by
 * `wait()`/`check()` (via `runIdle()`, one callback per call, cycling
 * through every registered one in turn -- see that function's own doc
 * comment) whenever no event is ready, and makes `wait()` act as
 * though its timeout were zero the whole time at least one idle
 * callback is installed (`idleActive()`, consulted by
 * `fl.platform_x11.waitForEventOrTimeout()` the same way
 * `Fl_System_Driver::wait()` consults `Fl::idle()` FLTK).
 */
void addIdle(IdleHandler cb)
{
    idleHandlers_ ~= cb;
}

/// Ported from `Fl::has_idle(Fl_Idle_Handler, void*)` -- whether `cb`
/// (compared by delegate identity, the D equivalent of FLTK's
/// `cb`+`data` pointer-pair match) is currently registered.
bool hasIdle(IdleHandler cb)
{
    foreach (h; idleHandlers_)
        if (h is cb) return true;
    return false;
}

/// Ported from `Fl::remove_idle(Fl_Idle_Handler, void*)` -- removes
/// every registered occurrence of `cb` (FLTK's own list can only
/// ever hold one, since `add_idle()` never de-duplicates either; this
/// mirrors that exactly, removing all matches for safety with no
/// observable difference in the common case).
void removeIdle(IdleHandler cb)
{
    size_t w = 0;
    foreach (i; 0 .. idleHandlers_.length)
    {
        if (idleHandlers_[i] is cb) continue;
        idleHandlers_[w++] = idleHandlers_[i];
    }
    idleHandlers_.length = w;
}

/// package(fl): `fl.platform_x11.waitForEventOrTimeout()` consults
/// this to clamp its own `select()` timeout to zero, matching
/// `Fl_System_Driver::wait()`'s `if (Fl::idle()) time_to_wait = 0.0;`.
package(fl) bool idleActive()
{
    return idleHandlers_.length > 0;
}

/**
 * Calls the next idle callback in turn, if any are registered.
 * Ported from `Fl::Private::run_idle()`/`call_idle()` -- FLTK's
 * ring rotates the just-called callback to the back before invoking
 * it (`last = p; first = p->next;` happens *before* `p->cb(p->data)`),
 * so a self-removing "one-shot" idle callback (FLTK's own
 * documented `Fl::remove_idle()` example) correctly removes itself
 * from the rotated arrangement; matched here by rotating this port's
 * own array the same way before calling. Only ever calls *one*
 * callback per invocation, not all of them -- see `addIdle()`'s own
 * doc comment: `wait()`'s near-zero timeout while idle is active
 * means this still runs every registered callback often, without
 * starving the rest of the event loop the way calling all of them in
 * one `wait()` pass would. Guarded against reentrancy (`inIdle_`),
 * matching FLTK's own guarantee.
 */
package(fl) void runIdle()
{
    if (idleHandlers_.length == 0 || inIdle_) return;
    IdleHandler cb = idleHandlers_[0];
    idleHandlers_ = idleHandlers_[1 .. $] ~ cb;
    inIdle_ = true;
    scope (exit) inIdle_ = false;
    cb();
}

// ---------------------------------------------------------------------
// Fl::add_check()/has_check()/remove_check() (FL/Fl.H + src/Fl.cxx)
// ---------------------------------------------------------------------

/// Ported from `Fl_Timeout_Handler` (the same delegate-type substitution
/// as `TimeoutHandler`/`IdleHandler` above -- FLTK reuses the timer
/// callback's own C typedef for checks too, since both are a plain
/// `void(*)(void*)`).
alias CheckHandler = void delegate();

/// Registered `addCheck()` callbacks. Ported from `src/Fl.cxx`'s file-
/// static `first_check`/`next_check`/`free_check` singly-linked ring (a
/// manual free-list, same reason as `idleHandlers_` above doesn't need
/// one under the GC) -- a plain GC-backed dynamic array, newest-first
/// (`addCheck()` prepends), matching FLTK's own documented call
/// order ("called in the reverse order that they were added").
private CheckHandler[] checkHandlers_;

/// True while `runChecks()` is executing its walk -- ported from
/// `next_check == first_check` (FLTK's own reentrancy test: a check
/// callback that calls `Fl::wait()`, and therefore reenters
/// `run_checks()`, must not restart the walk). Simplified to a plain
/// bool guard (skip entirely when already running) rather than
/// replicating the cursor-based "let the outer call keep advancing"
/// mechanics of the linked-list version -- the load-bearing guarantee
/// FLTK's own doc comment cares about (safe to add/remove/`wait()`
/// from inside a check callback, no infinite recursion, no double call)
/// holds either way; only the fine-grained "which pass a check added
/// mid-walk first fires in" ordering differs, which nothing in this
/// port observes.
private bool inChecks_;

/**
 * Registers `cb` to run just before the event loop flushes the display
 * and blocks waiting for the next event -- ported from
 * `Fl::add_check(Fl_Timeout_Handler, void*)`. Unlike an idle callback
 * (`addIdle()`, called repeatedly whenever nothing is pending, which
 * also prevents `wait()` from ever blocking), a check callback fires
 * exactly once per `wait()`/`check()` iteration and never itself
 * suppresses blocking -- see FLTK's own doc comment example: a
 * cheap "does anything actually need redrawing" gate run once per
 * iteration even while a burst of events keeps `wait()` from blocking
 * at all.
 */
void addCheck(CheckHandler cb)
{
    checkHandlers_ = cb ~ checkHandlers_;
}

/// Ported from `Fl::has_check(Fl_Timeout_Handler, void*)` -- whether
/// `cb` (compared by delegate identity) is currently registered.
bool hasCheck(CheckHandler cb)
{
    foreach (h; checkHandlers_)
        if (h is cb) return true;
    return false;
}

/// Ported from `Fl::remove_check(Fl_Timeout_Handler, void*)` -- removes
/// every registered occurrence of `cb` ("harmless to remove a check
/// callback that no longer exists", matching FLTK's own doc
/// comment: a no-op if `cb` isn't registered).
void removeCheck(CheckHandler cb)
{
    size_t w = 0;
    foreach (i; 0 .. checkHandlers_.length)
    {
        if (checkHandlers_[i] is cb) continue;
        checkHandlers_[w++] = checkHandlers_[i];
    }
    checkHandlers_.length = w;
}

/**
 * Calls every registered check callback once, in call order. Ported
 * from `Fl::Private::run_checks()`, called from `fl.platform_x11.wait()`
 * /`check()` right before `runIdle()` -- matching
 * `Fl_System_Driver::wait()`'s own `do_timeouts()` -> `run_checks()` ->
 * `run_idle()` sequence. Iterates a snapshot taken at the start of the
 * call, so a callback that adds a new check via `addCheck()` doesn't
 * see it fire in the same pass (that check runs starting next
 * iteration instead), and a callback that removes a not-yet-called
 * check is honored (checked against the live `checkHandlers_` before
 * calling each one) -- see `inChecks_`'s own doc comment for how
 * reentrancy (a check callback calling `Fl::wait()`) is handled.
 */
package(fl) void runChecks()
{
    if (checkHandlers_.length == 0 || inChecks_) return;
    inChecks_ = true;
    scope (exit) inChecks_ = false;
    auto snapshot = checkHandlers_.dup;
    foreach (cb; snapshot)
        if (hasCheck(cb)) cb();
}

// ---------------------------------------------------------------------
// Fl::now()/seconds_since()/seconds_between()/ticks_since()/
// ticks_between() (Fl.H + the new src/Fl_Timeout.cxx). Needed for
// real by source/test/threads.d, which measures elapsed wall-clock
// time between fl.awake() calls in its prime-number-finder worker
// threads. Backed by core.time.MonoTime, same as the timer queue above
// -- monotonic and free of the wraparound caveat FLTK's own
// Fl_Timestamp doc comment flags for gettimeofday() on some platforms,
// so unlike FLTK there's no "may wrap around" caveat to design
// around. `Timestamp` is a plain `alias` for `MonoTime` rather than
// FLTK's own sec/usec struct, and every function below takes it by
// value rather than FLTK's `Fl_Timestamp&` -- both cheap value-type
// simplifications, not behavior changes.
// ---------------------------------------------------------------------

alias Timestamp = MonoTime;

/// Ported from `Fl::now(double offset = 0)`. `offset` is an optional
/// signed number of seconds added to the returned stamp.
Timestamp now(double offset = 0)
{
    auto t = MonoTime.currTime;
    if (offset != 0)
        t += dur!"hnsecs"(cast(long)(offset * 10_000_000.0));
    return t;
}

/// Ported from `Fl::seconds_since(Fl_Timestamp&)`.
double secondsSince(Timestamp then)
{
    return secondsBetween(MonoTime.currTime, then);
}

/// Ported from `Fl::seconds_between(Fl_Timestamp&, Fl_Timestamp&)`.
double secondsBetween(Timestamp back, Timestamp furtherBack)
{
    return (back - furtherBack).total!"hnsecs" / 10_000_000.0;
}

/// Ported from `Fl::ticks_since(Fl_Timestamp&)` -- elapsed time in
/// 60ths of a second, a convenience unit for per-frame animation.
long ticksSince(Timestamp then)
{
    return ticksBetween(MonoTime.currTime, then);
}

/// Ported from `Fl::ticks_between(Fl_Timestamp&, Fl_Timestamp&)`.
long ticksBetween(Timestamp back, Timestamp furtherBack)
{
    return (back - furtherBack).total!"hnsecs" * 60 / 10_000_000;
}

// ---------------------------------------------------------------------
// Thread locking (src/Fl_lock.cxx) -- Fl::lock()/unlock()/awake()/
// awake(handler)/awake_once(handler). Needed for real by
// source/test/threads.d, which spawns worker threads (via D's own
// core.thread.Thread, not FLTK's sample-local test/threads.h
// pthread-wrapper shim -- out of this port's scope, see that sample's
// own header comment) that compute prime numbers and hand results back
// to the main GUI thread via fl.awake().
//
// Uses core.sync.mutex.Mutex directly rather than transliterating
// Fl_Posix_System_Driver.cxx's own hand-rolled pthread_mutex_t +
// PTHREAD_MUTEX_RECURSIVE dance (with a manual per-thread-owner+counter
// fallback for platforms lacking a recursive mutex): druntime's Mutex
// is already documented as "a general purpose, recursive mutex",
// implemented with PTHREAD_MUTEX_RECURSIVE on Posix -- exactly
// FLTK's own preferred path, just not re-derived by hand. This
// port's Linux target always has PTHREAD_MUTEX_RECURSIVE, so FLTK's
// non-recursive-mutex fallback path is skipped entirely (same kind of
// "assume the common case, skip the exotic-platform fallback"
// simplification as fl.draw's single-TrueColor-visual assumption).
//
// `Fl_Awake_Handler` (a C function pointer + `void*` data pair) becomes
// a single capturing delegate (`AwakeHandler = void delegate()`), the
// usual substitution -- so `awake(handler, data)`'s separate `void*`
// parameter, the deprecated `awake(void*)` overload, and
// `thread_message()` aren't ported: a delegate already carries whatever
// data its call site needs, and FLTK itself deprecated that whole
// message-passing path in favor of `awake(handler, data)` (1.5.0) for
// exactly this reason (its own doc comment: "the API can not ensure
// thread_message() returns messages complete and in the correct
// order"). `awake_once()`'s de-duplication compares `AwakeHandler`
// values with D's built-in delegate `==` (context pointer + function
// pointer), the direct equivalent of FLTK's own func+data pointer
// comparison.
//
// The awake-notification pipe reuses this module's own addFd()
// (core-roadmap item 6) to get folded into fl.platform_x11's
// select() loop, instead of a bespoke second fd-multiplexing mechanism
// -- the same entry point a caller's own fd would use.
// ---------------------------------------------------------------------

alias AwakeHandler = void delegate();

private __gshared Mutex fltkMutex_;
private __gshared Mutex ringMutex_;
private __gshared AwakeHandler[] awakeQueue_;
version (linux)
{
    private __gshared Mutex pipeMutex_;
    private __gshared int[2] threadPipe_ = [-1, -1];
}

private Mutex ringMutex()
{
    if (ringMutex_ is null) ringMutex_ = new Mutex();
    return ringMutex_;
}

version (linux) private Mutex pipeMutex()
{
    if (pipeMutex_ is null) pipeMutex_ = new Mutex();
    return pipeMutex_;
}

/**
 * Acquires the recursive, process-wide FLTK UI lock, initializing the
 * threading subsystem the first time it's called -- matching FLTK's
 * own lazy `Fl::lock()`-triggered setup. The main thread must call this
 * once before `run()`/`wait()` for `awake()` to have any effect from a
 * worker thread; `run()`/`wait()` then release the lock around their
 * own blocking wait (see fl.platform_x11's `waitForEventOrTimeout()`
 * and `unlockForWait()`/`lockForWait()` just below) so a worker thread
 * blocked on `lock()` can actually make progress while the main thread
 * is otherwise idle -- matching the exact mechanism FLTK's own doc
 * comment describes ("The lock is locked all the time except when
 * Fl::wait() is waiting for events").
 *
 * \return 0 always -- threading is unconditionally available on this
 * port's Linux target (FLTK's own nonzero return only ever fires on
 * a platform lacking thread support at all, out of scope here).
 */
int lock()
{
    if (fltkMutex_ is null)
    {
        fltkMutex_ = new Mutex();
        // Eagerly construct ringMutex()/pipeMutex() here too, rather
        // than leaving them purely lazy-initialized: the documented
        // usage pattern is "main thread calls lock() once before
        // spawning any worker threads" (matching FLTK's own
        // documented contract), so doing it here means no two worker
        // threads can ever race the lazy-init `if (x is null) x = new
        // Mutex();` check in ringMutex()/pipeMutex() below by both
        // calling awake(handler) at once right after being spawned
        // (exactly what source/test/threads.d's six worker threads
        // do) -- a real race those lazy accessors would otherwise be
        // exposed to that FLTK's own `lock_ring()` doesn't have to
        // worry about in quite the same way (its own equivalent
        // unguarded `if (!ring_mutex)` check is normally only ever
        // first-hit after Fl::lock() too, but this makes it structural
        // rather than incidental). The lazy accessors stay as a
        // fallback for the (out-of-contract) case of awake() being
        // called before lock() ever runs.
        ringMutex();
        version (linux)
        {
            pipeMutex();
            initAwakePipe();
        }
    }
    fltkMutex_.lock();
    return 0;
}

/// Releases the lock acquired by `lock()`. A no-op if `lock()` was
/// never called (matching FLTK's own `fl_unlock_function` defaulting
/// to a no-op until `Fl::lock()`'s first call rebinds it).
void unlock()
{
    if (fltkMutex_ !is null) fltkMutex_.unlock();
}

/// Releases the lock right before fl.platform_x11's blocking `select()`
/// call, so a worker thread waiting on `lock()` can run while the main
/// thread is otherwise idle -- see `lock()`'s own doc comment. A no-op
/// if `lock()` was never called. Not itself part of FLTK's public
/// API; matches the *effect* of
/// `Fl_Unix_Screen_Driver::poll_or_select_with_delay()`'s own
/// `fl_unlock_function()` call around the same spot.
package(fl) void unlockForWait()
{
    if (fltkMutex_ !is null) fltkMutex_.unlock();
}

/// Reacquires the lock right after the blocking wait above returns --
/// see `unlockForWait()`.
package(fl) void lockForWait()
{
    if (fltkMutex_ !is null) fltkMutex_.lock();
}

version (linux) private void initAwakePipe()
{
    import core.sys.posix.unistd : pipe;
    import core.sys.posix.fcntl : fcntl, F_SETFL, F_GETFL, O_NONBLOCK;

    int[2] fds;
    if (pipe(fds) == -1) return; // "this should not happen" -- matches FLTK's own comment
    threadPipe_ = fds;
    fcntl(threadPipe_[1], F_SETFL, fcntl(threadPipe_[1], F_GETFL) | O_NONBLOCK);
    addFd(threadPipe_[0], fdRead, (fd) { drainAwakePipe(fd); });
}

version (linux) private void drainAwakePipe(int fd)
{
    import core.sys.posix.unistd : read;

    auto pm = pipeMutex();
    pm.lock();
    ubyte dummy;
    read(fd, &dummy, 1);
    pm.unlock();

    drainAwakeQueue();
}

/**
 * Runs every currently-queued `awake()` handler, draining the queue
 * completely. Linux reaches this via `drainAwakePipe()`, itself called
 * from the pipe fd's `addFd()` callback once `select()` reports it
 * readable. Windows has no such fd to hang a callback on (its `awake()`
 * wakes the main thread via a posted thread message instead, see
 * `fl.platform_win32.wakeMainThread()`), so `fl.platform_win32.wait()`/
 * `wait(double)`/`check()` call this directly, once per tick, alongside
 * their existing `doWidgetDeletion()`/`processTimeouts()`/etc. calls --
 * same end effect (every handler queued by a worker thread's `awake()`
 * call runs on the main thread before the next blocking wait), just
 * without a real fd to trigger it.
 */
package(fl) void drainAwakeQueue()
{
    for (;;)
    {
        auto h = popAwakeHandler();
        if (h is null) break;
        h();
    }
}

private void pushAwakeHandler(AwakeHandler handler, bool once)
{
    auto m = ringMutex();
    m.lock();
    scope(exit) m.unlock();

    if (once)
    {
        AwakeHandler[] kept;
        foreach (h; awakeQueue_)
            if (h != handler) kept ~= h;
        awakeQueue_ = kept;
    }
    awakeQueue_ ~= handler;
}

private AwakeHandler popAwakeHandler()
{
    auto m = ringMutex();
    m.lock();
    scope(exit) m.unlock();

    if (awakeQueue_.length == 0) return null;
    auto h = awakeQueue_[0];
    awakeQueue_ = awakeQueue_[1 .. $];
    return h;
}

/**
 * Wakes the main thread's `run()`/`wait()` from a worker thread even if
 * no real event is pending -- ported from `Fl::awake()`. A no-op until
 * `lock()` has been called at least once (matching FLTK's own
 * `if (thread_filedes[1])` guard).
 *
 * On Windows, D's `core.thread.Thread` needs nothing
 * platform-specific to run a worker thread, but every `pushAwakeHandler()` call from a
 * worker thread (via `awake(handler)` below) needs the main thread's blocked
 * `MsgWaitForMultipleObjects()` wait
 * (`fl.platform_win32.waitForMessageOrTimeout()`) to actually wake for
 * it, and something on the Windows side needs to
 * call `popAwakeHandler()` to run the queued handler (Linux's
 * only call site is `drainAwakePipe()`, reachable via the
 * pipe fd this platform doesn't have). This posts a real wake message via
 * `fl.platform_win32.wakeMainThread()` (`PostThreadMessageW()` to the
 * main thread, matching FLTK's own `Fl_WinAPI_Screen_Driver::
 * awake()`), and `fl.platform_win32.wait()`/`wait(double)`/`check()`
 * now call `drainAwakeQueue()` (above) once per tick, alongside their
 * existing `doWidgetDeletion()`/`processTimeouts()`/etc. calls, taking
 * the place Linux's fd-triggered `drainAwakePipe()` plays there.
 */
void awake()
{
    version (linux)
    {
        if (threadPipe_[1] < 0) return;

        import core.sys.posix.unistd : write;
        import core.sys.posix.sys.ioctl : ioctl, FIONREAD;

        auto pm = pipeMutex();
        pm.lock();
        scope(exit) pm.unlock();

        int avail = 0;
        ioctl(threadPipe_[0], FIONREAD, &avail);
        if (avail == 0)
        {
            ubyte dummy = 0;
            write(threadPipe_[1], &dummy, 1);
        }
    }
    else version (Windows)
    {
        platformWin32.wakeMainThread();
    }
}

/**
 * Schedules `handler` to run on the main thread (during its next
 * `run()`/`wait()`/`check()` iteration), then wakes it up -- ported
 * from `Fl::awake(Fl_Awake_Handler, void*)`, minus the separate `void*`
 * parameter (see this section's own header comment).
 *
 * \return 0 always -- this port's queue is a plain GC-backed array
 * rather than FLTK's fixed 1024-entry ring buffer, so there's no
 * "queue is full" case to report (same reasoning already applied to the
 * timer queue above: the GC makes FLTK's fixed-capacity,
 * allocation-free design unnecessary here).
 */
int awake(AwakeHandler handler)
{
    pushAwakeHandler(handler, false);
    awake();
    return 0;
}

/**
 * Same as `awake(AwakeHandler)`, but first removes any previously
 * scheduled entry `==` to `handler` (D delegate equality: same context
 * pointer and function pointer) -- ported from `Fl::awake_once()`.
 */
int awakeOnce(AwakeHandler handler)
{
    pushAwakeHandler(handler, true);
    awake();
    return 0;
}

/**
 * Emits a system beep. Forwards to fl.platform_x11's `beep()` (an
 * `XBell()` call), matching FLTK's `Fl::screen_driver()->beep()`
 * dispatch (`Fl_X11_Screen_Driver::beep()`); a no-op on non-Linux
 * platforms, since no other platform driver exists yet.
 */
void beep(Beep type = Beep.default_)
{
    version (linux) platformX11.beep(type);
    else version (Windows) platformWin32.beep(type);
}

/**
 * Selects a visual capable of `flags` (`modeRgb`/`modeRgb8`/
 * `modeIndex`/`modeDouble`, `fl.enumerations.Mode`) -- ported from
 * `Fl::visual(int)` (`src/Fl_visual.cxx`), forwarding to
 * `fl.platform_x11.setVisual()` (the real search/selection logic; see
 * that function's own doc comment, including the deliberate limits of
 * what it actually changes). Always `true` on non-Linux platforms,
 * since no other platform driver exists yet (matches `beep()`'s/
 * `screenCount()`'s existing no-op fallback convention).
 */
bool visual(Mode flags)
{
    version (linux) return platformX11.setVisual(flags);
    else return true;
}

/**
 * Starts a drag-and-drop operation carrying whatever `copy()` most
 * recently placed in the PRIMARY selection -- ported from `Fl::dnd()`
 * (`Fl.cxx`, itself just `return screen_driver()->dnd();`), forwarding
 * to `fl.platform_x11.dnd()` (the real XDND drag loop -- both the
 * same-process and cross-application/XDND-protocol cases; see that
 * function's own doc comment). Blocks until the drag completes (the
 * mouse button is released), matching FLTK exactly -- it runs its
 * own nested `wait()` loop rather than returning immediately. On
 * Windows, forwards to `fl.platform_win32.dnd()` instead -- real COM
 * drag-and-drop (`DoDragDrop()`), also blocking until the drag
 * completes, just via a single OS call rather than a hand-built poll
 * loop. `0` on any other platform
 * (matches FLTK's own base `Fl_Screen_Driver::dnd()`, which does
 * nothing and returns `0` too).
 */
int dnd()
{
    version (linux) return platformX11.dnd();
    else version (Windows) return platformWin32.dnd();
    else return 0;
}

/**
 * Ported from `Fl::screen_count()` -- see
 * `fl.platform_x11.initScreens()`'s own doc comment for the
 * fallback behavior when Xinerama isn't active.
 * Always at least 1; `1` on non-Linux platforms, since no other
 * platform driver exists yet.
 */
int screenCount()
{
    version (linux) return platformX11.screenCount();
    else version (Windows) return platformWin32.screenCount();
    else return 1;
}

/// Ported from `Fl::use_high_res_GL(int)` (`FL/Fl.H`) -- whether GL
/// windows use the display's native high-res (Retina-style) backing
/// store. A documented no-op: this port has no GL/`Fl_Gl_Window` support
/// at all yet, so the flag has nothing to affect. Added for call-site
/// compatibility (`test/fullscreen.cxx` sets it unconditionally in
/// `main()`, unrelated to the feature that test actually demonstrates),
/// not because it does anything real yet.
void useHighResGL(bool val) { }

/// GUI scale factor storage backing `screenScale(int)`/`screenScale(int,
/// float)` below -- a genuine per-screen array, matching FLTK's
/// real X11/Windows behavior (`Fl_X11_Screen_Driver::rescalable()`/
/// `Fl_WinAPI_Screen_Driver::rescalable()` both report
/// `PER_SCREEN_APP_SCALING`: each monitor keeps its own independent
/// factor). Sized to `maxScreens_` (matching FLTK's own
/// `Fl_Screen_Driver::MAX_SCREENS = 16`) rather than a dynamic array --
/// no allocation, and every index is always valid to read regardless of
/// the live `screenCount()`, same as FLTK's fixed `screens[MAX_
/// SCREENS]`.
///
/// `fl.draw`'s scaled
/// primitives do NOT read this array directly -- they read
/// `currentScale()` below, a separate cached "live drawing scale"
/// value updated whenever a window becomes the active draw target
/// (mirroring FLTK's own split between `Fl_Screen_Driver::scale(n)`,
/// this per-screen table, and `Fl_Graphics_Driver::scale()`, the
/// per-surface live value `make_current()` copies it into). Conflating
/// the two into a single shared scalar would misbehave: dragging one
/// window to a
/// differently-scaled monitor would visibly rescale *every other* window
/// still sitting on the original monitor, since every window's drawing
/// would read the same one value instead of this table's independent
/// per-screen values.
private enum maxScreens_ = 16;
private float[maxScreens_] screenScale_ = 1.0f;

/// Ported from `Fl::screen_scale(int)` (`FL/Fl.H`, `src/Fl.cxx:2499`) --
/// the GUI scale factor for monitor `n`. Returns `screenScale_[n]`, or
/// `1.0` if scaling isn't supported (`screenScalingSupported()`, always
/// true on Linux/Windows) or `n` is out of range (`[0, screenCount())`),
/// matching FLTK's own out-of-range/unsupported-platform fallback
/// exactly. A real per-screen read now (see `screenScale_`'s own
/// comment) -- everything else FLTK's own `screen_scale()` doc
/// comment promises (drawing, window creation/resize, the keybinding)
/// is real too.
float screenScale(int n)
{
    if (!screenScalingSupported() || n < 0 || n >= screenCount() || n >= maxScreens_)
        return 1.0f;
    return screenScale_[n];
}

/// Ported from `Fl::screen_scaling_supported()` (`FL/Fl.H`,
/// `src/Fl.cxx:2545`) -- the capability level: `0` unsupported, `1` a
/// single factor shared by every screen, `2` real independent
/// per-screen factors. `2` on Linux and Windows now, matching FLTK's
/// own X11/Windows drivers (`Fl_X11_Screen_Driver::rescalable()`/
/// `Fl_WinAPI_Screen_Driver::rescalable()`, both `PER_SCREEN_APP_
/// SCALING`) now that `screenScale_` is a genuine per-screen array (see
/// its own doc comment). `0` on any other platform, since no driver
/// exists there at all yet.
int screenScalingSupported()
{
    version (linux) return 2;
    else version (Windows) return 2;
    else return 0;
}

/// Ported from `Fl::screen_scale(int, float)` (`FL/Fl.H`,
/// `src/Fl.cxx:2523`) -- sets monitor `n`'s GUI scale factor
/// independently of every other screen's own entry. Does nothing if `n`
/// is out of range or `factor` is non-positive (matching FLTK's own
/// crash-prevention clamp in `Fl_X11_Screen_Driver::desktop_scale_
/// factor()`).
void screenScale(int n, float factor)
{
    if (n < 0 || n >= screenCount() || n >= maxScreens_ || factor <= 0)
        return;
    screenScale_[n] = factor;
}

/// The GUI scale factor `fl.draw`'s primitives, `fl.image`/`fl.bitmap`'s
/// resampling, and text/font sizing actually draw at right now --
/// ported from `Fl_Graphics_Driver::scale()`, FLTK's own per-surface
/// live value, collapsed to a single module-level cache since this port
/// has no per-window graphics-driver-instance decorator. **Deliberately
/// separate from `screenScale(int)` above** -- that's the persisted
/// per-screen table (`Fl_Screen_Driver::scale(n)`'s equivalent);
/// this is the live value a window's own `make_current()` copies *from*
/// that table (`Fl_X11_Window_Driver::make_current()`: `fl_graphics_
/// driver->scale(Fl::screen_driver()->scale(screen_num()))`). Updated by
/// `currentScale(float)` below at every one of this port's own
/// `make_current()`-equivalent call sites (`Window.makeCurrent()`,
/// `fl.draw.setDrawable()`, `fl.platform_win32`'s `setHdc()` call
/// sites, `resizeAfterScaleChange()`). Starts at `1.0`, matching FLTK's
/// own `Fl_Graphics_Driver::scale_` default.
private float currentScale_ = 1.0f;

/// Reads the live drawing scale `currentScale(float)` below last set --
/// see `currentScale_`'s own doc comment for the FLTK mechanism this
/// mirrors. Every call site in `fl.draw`/`fl.image`/`fl.bitmap` that
/// needs "the scale of whatever window is currently being drawn" calls
/// this, not `screenScale(0)`.
float currentScale()
{
    return currentScale_;
}

/// Sets the live drawing scale -- called from every `make_current()`-
/// equivalent call site (see `currentScale_`'s own doc comment), never
/// directly by drawing code itself. `factor <= 0` is silently ignored,
/// matching `screenScale(int, float)`'s own crash-prevention clamp
/// (a live scale of `0` or negative would corrupt every subsequent
/// device-pixel computation `fl.draw` makes).
package(fl) void currentScale(float factor)
{
    if (factor <= 0) return;
    currentScale_ = factor;
}

/// Preferences vendor/group/key persisting the last interactively-chosen
/// GUI scale factor, shared by every fldtk application -- a genuine
/// fldtk-only addition, not a port of anything: grepping FLTK's
/// `Fl_Screen_Driver::scale_handler()`/`rescale()` chain in
/// FLTK's source turns up no `Fl_Preferences` use at all, so
/// FLTK's own Ctrl-+/Ctrl--/Ctrl-0 handler never remembers the
/// chosen scale across a restart. Requested explicitly by the user
/// ("a user-wide setting that remembers the last scale used... a
/// global factor applying to all applications at once"), which is what
/// satisfies CONVENTIONS.md's "raise any other beyond-FLTK idea before
/// acting" rule here -- the user raised it. **Deliberately vendor
/// `"fldtk"`, not `readOptions_()`'s `"fltk.org"`** -- that pair is a
/// faithful port reading FLTK's own real `Fl_Option` settings
/// file on purpose (so `fltk-options`, which ships with real FLTK,
/// configures this port too); this feature has no FLTK counterpart
/// at all, so it belongs in fldtk's own namespace, same reasoning
/// `fluid/app_prefs.d` uses to diverge from
/// FLTK Fluid's own `"fltk.org"`/`"fluid"` pair. Application
/// `"core"` (not `"fluid"` or any other single app) since this is
/// shared, global state for every fldtk application, not one app's own
/// UI state -- resolves to `~/.config/fldtk/core.prefs`.
private enum scaleFactorPrefsGroup_ = "scaling";
private enum scaleFactorPrefsKey_ = "ScaleFactor"; // matches optionKeys_'s PascalCase key-naming style above

/// Reads the persisted global scale factor written by `persistScaleFactor()`
/// below, or `float.nan` if none has ever been saved (first run, or a
/// user preferences file that predates this feature). A plain read with
/// no caching -- called once, at startup, from `fl.platform_x11.
/// useStartupScaleFactor()`.
///
/// **Always `float.nan` in a `version(unittest)` build, real disk read
/// skipped entirely** -- found the hard way: `dub test` links against
/// a live X display on this dev machine, so `fl.draw`'s own display-
/// needing tests really call `openDisplay()` -> `useStartupScaleFactor()`
/// -> this function mid-suite, which read the *real*
/// `~/.config/fldtk/core.prefs` this same feature's own live testing in
/// Fluid had already written a persisted scale into, silently setting
/// `screenScale_` to that real value process-wide and failing an
/// unrelated `screenScale(0) == 1.0f` "starts at its documented
/// default" assertion later in the same run. Exactly the same category
/// of bug `resetForTest()`'s own `optionsRead_ = true` comment already
/// documents for `readOptions_()`/`Fl_Option` and a stray real
/// `fltk.org/fltk.prefs` -- except that fix works there because
/// `option()`'s real read is lazy (deferred until first call, so
/// pre-seeding a "the real read already ran" flag before any test body
/// executes suppresses it every time); this one is eager, unconditional
/// disk I/O the moment *any* module's test happens to trigger
/// `openDisplay()`, before any test-specific reset flag could run.
/// `version(unittest)` (checked at compile time, so it's unaffected by
/// which module's unittest happens to run first) is the right tool
/// instead: the whole `fldtk-test-library` test-runner binary simply
/// never touches this file, matching `CONVENTIONS.md`'s "Shared static
/// state needs hermetic tests" convention as directly as `optionsRead_`
/// does, just via a different mechanism suited to eager vs. lazy reads.
package(fl) float loadPersistedScaleFactor()
{
    version (unittest) return float.nan;
    else
    {
        import prefsmod = fl.preferences;

        auto prefs = new prefsmod.Preferences(prefsmod.rootCoreUserL, "fldtk", "core");
        auto scalePrefs = new prefsmod.Preferences(prefs, scaleFactorPrefsGroup_);
        float value;
        if (scalePrefs.get(scaleFactorPrefsKey_, value, -1.0f) && value > 0)
            return value;
        return float.nan;
    }
}

/// Writes `factor` to the same user-level `Fl_Preferences` location
/// `loadPersistedScaleFactor()` reads, so the next process (this one or
/// any other fldtk application) starts up at this scale -- called from
/// `scaleHandler()` after every successful live rescale via Ctrl-+/
/// Ctrl--/Ctrl-0. **Calls `.flush()` explicitly** -- `set()` alone only
/// marks the in-memory tree dirty; per `fl.preferences`'s own module
/// doc comment, a GC-collected `Preferences`/`RootNode`'s `~this()`
/// (which would otherwise write a dirty tree) may run late or not at
/// all before the process exits, so relying on it here would silently drop
/// every rescale made shortly before quitting (e.g. scaling to 150%,
/// closing, and reopening at 100% instead).
private void persistScaleFactor(float factor)
{
    import prefsmod = fl.preferences;

    auto prefs = new prefsmod.Preferences(prefsmod.rootCoreUserL, "fldtk", "core");
    auto scalePrefs = new prefsmod.Preferences(prefs, scaleFactorPrefsGroup_);
    scalePrefs.set(scaleFactorPrefsKey_, factor);
    prefs.flush();
}

/// The screen scale in effect when this process started, captured
/// lazily on first use, *per screen* -- ported from `Fl_Screen_Driver::
/// base_scale()` (`static float base = scale(numscreen); return base;`,
/// itself a plain function-local `static`, i.e. shared across every
/// `numscreen` value in the *generic*/X11 driver -- not a port gap
/// there, FLTK's own design). The *Windows* driver
/// overrides this to a genuine per-screen value instead (`Fl_WinAPI_
/// Screen_Driver::base_scale(int n) { return float(dpi[n][0] / 96.); }`).
/// Storing this as a real per-screen array
/// (matching `screenScale_`'s own treatment) satisfies both: `fl.platform_x11.useStartupScaleFactor()`
/// seeds every screen with the *same* value (X11 has no per-monitor
/// startup DPI source, see that function's own doc comment, so this
/// reduces to FLTK's real single-shared-static behavior exactly);
/// `fl.platform_win32.seedScaleFromPrimaryMonitor()` seeds each screen
/// with *its own* real DPI-derived value, matching FLTK's real
/// per-screen Windows override.
///
/// `scaleHandler()`'s "reset to 100%" (Ctrl-'0') step measures relative
/// to this, not relative to `1.0` literally, so a desktop that starts at
/// (say) 150% resets back to *its own* 150%, not to fldtk's internal
/// default. Explicitly seeded at startup (`seedBaseScale()`
/// below) rather than relying purely on the lazy-capture-on-first-press
/// fallback below -- see that function's own doc comment for why plain
/// lazy capture is insufficient once the persisted-scale
/// feature is in play.
private enum maxBaseScreens_ = maxScreens_;
private float[maxBaseScreens_] baseScale_ = float.nan;

/// `package(fl)`, not `private` -- `fl.platform_win32.
/// fakeXWm()` needs this to compute real border/title-bar metrics from
/// the *actual* monitor DPI, separate from `screenScale()`'s own
/// zoom-inclusive value (see that function's own doc comment for the
/// bug this fixes).
package(fl) float baseScale(int n)
{
    import std.math : isNaN;

    if (n < 0 || n >= maxBaseScreens_) return screenScale(n);
    if (isNaN(baseScale_[n]))
        baseScale_[n] = screenScale(n);
    return baseScale_[n];
}

/// Ported from `Fl::normalized_screen_scale(int)`: screen `n`'s scale in
/// relation to its scale when the application started (the value shown
/// in the transient popup during interactive scaling). `1.0` if scaling
/// isn't supported or `n` is out of range.
float normalizedScreenScale(int n)
{
    if (!screenScalingSupported() || n < 0 || n >= screenCount()) return 1.0f;
    return screenScale(n) / baseScale(n);
}

/// Ported from `Fl::normalized_screen_scale(int, float)`: sets screen
/// `n`'s scale to `factor` times its startup scale, rescaling its shown
/// windows. `n == -1` applies to every screen.
void normalizedScreenScale(int n, float factor)
{
    if (!screenScalingSupported() || factor <= 0) return;
    if (n == -1)
    {
        foreach (sc; 0 .. screenCount())
            rescaleAllWindowsFromScreen(sc, factor * baseScale(sc), screenScale(sc));
    }
    else if (n >= 0 && n < screenCount())
        rescaleAllWindowsFromScreen(n, factor * baseScale(n), screenScale(n));
}

/// Explicitly seeds screen `n`'s `baseScale()` reference value -- called
/// once per screen at startup (`fl.platform_x11.useStartupScaleFactor()`/
/// `fl.platform_win32.seedScaleFromPrimaryMonitor()`), right after
/// desktop-scale detection is established but *before* any persisted-
/// scale override (`loadPersistedScaleFactor()`) is applied on top.
/// Without this, `baseScale()`'s plain lazy-capture fallback would seed
/// itself from whatever `screenScale()` already is the first time any
/// Ctrl-+/Ctrl--/Ctrl-0 press needs it -- which, with a
/// persisted scale in play, could be the user's own previously *chosen* absolute
/// scale, not the desktop's actual native default. That would silently
/// redefine what "100%" means for every subsequent press's percentage
/// math, so a genuinely-absolute 133% scale (one zoom-out step down from
/// a persisted 150%) would display as "90%" (its ratio to the *previous*
/// 150%) instead of "133%". Anchoring the base explicitly to the pre-persistence-
/// override value, instead of whatever's active when the user happens to
/// first press a zoom key, avoids that.
package(fl) void seedBaseScale(int n, float value)
{
    if (n < 0 || n >= maxBaseScreens_) return;
    baseScale_[n] = value;
}

/// The transient "137 %" indicator window `transientScaleDisplay()`
/// shows after a live rescale, or `null` between rescales. Compared by
/// identity (`w !is transientScaleWindow_`) in
/// `rescaleAllWindowsFromScreen()`'s "which windows are real top-level
/// application windows" filter -- stands in for FLTK's own
/// `win->user_data() != (void*)&transient_scale_display` marker-pointer
/// check, which this port can't replicate directly (`Widget` has no
/// generic per-widget data slot at all yet, see `CONVENTIONS.md`'s own
/// tracked note on that gap) but doesn't need to either: there is only
/// ever at most one such window alive at a time, so a direct identity
/// comparison against this single stored reference is exactly
/// equivalent, not an approximation.
private CoreWindow transientScaleWindow_;

/// package(fl) accessor for `transientScaleWindow_`, needed by
/// `fl.platform_x11`'s `ConfigureNotify` handler for the same identity
/// check `rescaleAllWindowsFromScreen()` already makes internally --
/// see the deferred cross-screen-move mechanism in that module.
package(fl) CoreWindow transientScaleWindow() { return transientScaleWindow_; }

/// Destroys `transientScaleWindow_` (a no-op if already `null`) --
/// ported from `Fl_Screen_Driver::del_transient_window()`. Called both
/// as a one-shot `addTimeout()` callback (the indicator's normal
/// auto-close) and directly, synchronously, when a new rescale needs
/// to replace a still-showing indicator before its own timeout fires
/// (see `transientScaleDisplay()`). `destroy()`, not `deleteWidget()`:
/// this never runs from *the window's own* callback (deleteWidget()'s
/// whole reason to exist), so an immediate, deterministic destructor
/// call is both safe and what FLTK's own `delete transient_scale_
/// window;` does here.
private void delTransientWindow()
{
    if (transientScaleWindow_ is null) return;
    destroy(transientScaleWindow_);
    transientScaleWindow_ = null;
}

/// Stable `TimeoutHandler` value for `delTransientWindow()`, needed
/// because `addTimeout()`/`removeTimeout()` match callbacks by
/// delegate equality (see `removeTimeout()`'s own doc comment) --
/// `delTransientWindow` itself is a plain module-level function, not a
/// delegate, and re-evaluating a fresh `{ delTransientWindow(); }`
/// literal on every call would produce a *different* delegate value
/// each time, breaking `removeTimeout()`'s later lookup. Lazily
/// initialized, not a `static this()` -- this project has hit a real
/// circular-module-constructor bug from `static this()` before (see
/// `fl.symbols`' own history); lazy init sidesteps that class of
/// problem entirely.
private TimeoutHandler delTransientWindowHandler_;

private TimeoutHandler delTransientWindowHandler()
{
    if (delTransientWindowHandler_ is null)
        delTransientWindowHandler_ = { delTransientWindow(); };
    return delTransientWindowHandler_;
}

/**
 * Briefly shows a small, borderless "137 %"-style indicator window
 * centered on screen `nscreen`, announcing the new scale factor `f`
 * (a ratio, `1.0` == 100%) -- ported from `Fl_Screen_Driver::
 * transient_scale_display()`. Does nothing if `Option.showScaling` is
 * off. The indicator is itself shaped (`Window.shape()`) as a white
 * rounded box on a transparent background, rendered into an
 * `ImageSurface` at up to 3x scale (capped, "limit the growth of the
 * transient window" -- FLTK's own comment) so the shape mask
 * itself looks crisp at high zoom levels; the window's own FLTK-unit
 * size is then shrunk back by whatever amount the cap actually reduced
 * the render scale by, so the *real* on-screen indicator size stays
 * bounded even when the underlying `f` is much larger than 3x.
 *
 * **The `ImageSurface` block below runs at `currentScale()` forced to
 * `1`, saved and restored around just that block** -- a real bug
 * found via a live user report (rounded corners squared off past
 * 100%, then the label text overflowing its own background past
 * 133%): FLTK's real architecture gives every `Fl_Image_Surface`
 * its own independent graphics-driver `scale_`, which defaults to `1`
 * and is entirely decoupled from the *screen* driver's own scale --
 * the `w*s` sizes below are FLTK's *own* manual pre-multiplication
 * for "render this many device pixels," done under the assumption
 * that whatever draws into that surface won't *also* scale by the
 * screen's factor. This port has one shared, module-level *live*
 * drawing scale (`fl.core.currentScale()` -- see its own doc comment
 * for why, separate from the real per-screen `screenScale_` table),
 * read by every `fl.draw` call regardless of which surface is current
 * -- so without this save/restore, `fl_rectf()`/the shape `Box`'s own
 * rounded-rect drawing would scale by whatever the *live* factor
 * happens to be on top of the already-premultiplied `w*s` size, growing
 * past the `ImageSurface`'s own actual pixel bounds and getting clipped
 * there: the rounded corners (near the far edges) fall outside the
 * visible canvas entirely, leaving only a square-cut remainder, and the
 * real background ends up smaller than the (correctly-sized, unaffected
 * by this bug) label text drawn on the real window afterward -- both
 * symptoms trace back to this one cause.
 */
private void transientScaleDisplay(float f, int nscreen)
{
    if (!option(Option.showScaling)) return;

    int w = 150;
    float realScale = screenScale(nscreen);
    float s = realScale > 3 ? 3 : realScale;

    RGBImage img;
    {
        float savedScale = currentScale();
        currentScale(1.0f);
        scope(exit) currentScale(savedScale);

        auto surf = new ImageSurface(cast(int)(w * s), cast(int)(w * s / 2));
        SurfaceDevice.pushCurrent(surf);
        fldraw.fl_color(black);
        fldraw.fl_rectf(-1, -1, cast(int)(w * s) + 2, cast(int)(w * s) + 2);
        auto shapeBox = new Box(Boxtype.rflatBox, 0, 0, cast(int)(w * s), cast(int)(w * s / 2), "");
        shapeBox.color(white);
        surf.draw(shapeBox);
        destroy(shapeBox);
        img = surf.image();
        SurfaceDevice.popCurrent();
        destroy(surf);
    }

    int scrX, scrY, scrW, scrH;
    screenXYWH(scrX, scrY, scrW, scrH, nscreen);
    w = cast(int)(w / (realScale / s));
    auto win = new CoreWindow((scrX + scrW / 2) - w / 2, (scrY + scrH / 2) - w / 4, w, w / 2, null);
    auto label = new Box(Boxtype.flatBox, 0, 0, w, w / 2, null);
    import std.format : format;

    label.copyLabel(format("%d %%", cast(int)(f * 100 + 0.5)));
    label.labelfont(timesBold);
    label.labelsize(cast(Fontsize)(30 * s / realScale));
    label.labelcolor(fl.tooltip.textcolor());
    label.color(fl.tooltip.color());
    win.end();
    win.shape(img);
    win.setOutput();
    win.setNonModal();
    win.screenNum(nscreen);
    win.forcePosition(true);

    if (transientScaleWindow_ !is null)
    {
        removeTimeout(delTransientWindowHandler());
        delTransientWindow();
    }
    transientScaleWindow_ = win;
    win.show();
    addTimeout(1, delTransientWindowHandler());
}

/**
 * Rescales every real top-level application window on screen `screen`
 * from `oldF` to `f` -- ported from `Fl_Screen_Driver::rescale_all_
 * windows_from_screen()`. Sets `screenScale(screen, f)` first -- a real
 * per-screen table update now, touching only `screen`'s own entry (see
 * `screenScale_`'s own doc comment), matching FLTK's separate
 * per-screen-driver-array-plus-graphics-driver-copy update exactly --
 * so by the time each window's own `resizeAfterScaleChange()` issues
 * its real `resize()` call (which also updates `currentScale()`, the
 * live value that window's own subsequent drawing reads), the new
 * scale is already the one `fl.platform_x11.resizeWindow()` will read
 * and apply, and windows left on other screens are untouched, in the
 * table and in what they draw at. Windows are rescaled back-to-front
 * (matching FLTK's own `for (i = count-1; i >= 0; i--)`, "finishing
 * with front one"),
 * skipping the transient indicator window itself
 * (`transientScaleWindow_`) and any subwindow (`parent() !is null`) or
 * window on a different screen.
 */
package(fl) void rescaleAllWindowsFromScreen(int screen, float f, float oldF)
{
    screenScale(screen, f);

    CoreWindow[] windows;
    for (auto w = firstWindow(); w !is null; w = nextWindow(w))
        if (w.parent() is null && w.screenNum() == screen && w !is transientScaleWindow_)
            windows ~= w;
    if (windows.length == 0) return;

    foreach_reverse (w; windows)
    {
        w.resizeAfterScaleChange(screen, oldF, f);
        w.waitForExpose();
    }
}

/**
 * Responds to Ctrl-'+'/Ctrl-'-'/Ctrl-'0' (Ctrl-'=' is the same key as
 * Ctrl-'+' on most layouts) by rescaling every window on the focused
 * widget's screen -- ported verbatim from `Fl_Screen_Driver::scale_
 * handler()`. Installed as an event handler by `fl.platform_x11.
 * openDisplay()`; not exported, since
 * FLTK's own equivalent isn't public API either -- `Fl::add_
 * handler()` is how callers ever see the effect (via `Event.zoomEvent`,
 * dispatched after a successful rescale) or disable it entirely
 * (`keyboardScreenScaling(false)`).
 *
 * The step table and its epsilon-tolerant "which step are we
 * currently on" search are copied byte-for-byte from FLTK (not a
 * geometric formula -- these are deliberately chosen "nice" numbers,
 * several of them repeating thirds/quarters that wouldn't round-trip
 * exactly through float arithmetic without the `1e-4` tolerance).
 * Refuses to rescale while a menu is open (`grab()`) or any top-level
 * window on the affected screen is fullscreen/maximized, matching
 * FLTK's own safety checks exactly.
 */
private int scaleHandler(Event event)
{
    if (!keyboardScreenScaling_) return 0;
    if (event != Event.shortcut || !eventCommand()) return 0;

    enum Zoom { none, zoomIn, zoomOut, zoomReset }

    Zoom zoom = Zoom.none;
    if (testShortcut(stateCommand | '+')) zoom = Zoom.zoomIn;
    else if (testShortcut(stateCommand | '-')) zoom = Zoom.zoomOut;
    else if (testShortcut(stateCommand | '0')) zoom = Zoom.zoomReset;

    // Kludge to recognize shortcut Ctrl+'+' without pressing Shift --
    // see Option.simpleZoomShortcut's own doc comment for the caveats
    // (keyboard-layout dependent). FLTK defaults this off; this
    // port deliberately defaults it *on* instead (optionDefaults_'s
    // own doc comment) so Ctrl-'=' zooms in as a Shift-free alternative
    // to Ctrl-'+' on every layout, not just as an opt-in.
    if (option(Option.simpleZoomShortcut))
    {
        if ((eState_ & (stateMeta | stateAlt | stateCtrl | stateShift)) == stateCommand)
        {
            if (eventKey() == '=') zoom = Zoom.zoomIn;
        }
    }

    if (zoom == Zoom.none) return 0;

    if (grab() !is null) return 0;
    Widget wid = focus();
    if (wid is null) return 0;
    CoreWindow top = wid.topWindow();
    if (top is null) return 0;
    int screen = top.screenNum();

    for (auto w = firstWindow(); w !is null; w = nextWindow(w))
        if (w.parent() is null && w.screenNum() == screen
            && (w.fullscreenActive() || w.maximizeActive()))
            return 0;

    float initialScale = baseScale(screen);
    static immutable float[] scalingValues = [
        0.5f, 2f / 3, 0.8f, 0.9f, 1.0f,
        1.1f, 1.2f, 4f / 3, 1.5f, 1.7f,
        2.0f, 2.4f, 3.0f
    ];

    float oldF = screenScale(screen) / initialScale;
    float f;
    if (zoom == Zoom.zoomReset) f = 1;
    else
    {
        int count = cast(int) scalingValues.length;
        int i;
        for (i = 0; i < count; i++)
            if (oldF >= scalingValues[i] - 1e-4f
                && (i + 1 >= count || oldF < scalingValues[i + 1] - 1e-4f))
                break;
        if (zoom == Zoom.zoomOut) i--; else i++;
        if (i < 0) i = 0;
        else if (i >= count) i = count - 1;
        f = scalingValues[i];
    }
    if (f == oldF) return 1;

    rescaleAllWindowsFromScreen(screen, f * initialScale, screenScale(screen));
    persistScaleFactor(screenScale(screen));
    transientScaleDisplay(f, screen);
    dispatch(Event.zoomEvent, null);
    return 1;
}

/// Installs `scaleHandler()` -- called once from `fl.platform_x11.
/// openDisplay()`'s own one-time setup, matching FLTK's exact call
/// site and timing (`Fl_Screen_Driver::open_display()`, at the end of
/// `open_display_platform()`). Registered via the two-argument
/// `addHandler()` overload, right after whatever was most recently
/// installed at that point (`lastHandler()`), so `scaleHandler()` runs
/// at *lower* priority than it -- matching FLTK's own "so it has
/// less priority" comment; harmless if nothing else is registered yet
/// (the common case), since `addHandler(ha, null)` falls back to
/// plain append then. No gating on `keyboardScreenScaling()` here --
/// unlike FLTK, which also skips *installing* the handler when the
/// flag is off at startup, this port always installs it and lets
/// `scaleHandler()`'s own runtime check decide, so toggling the flag
/// later always takes effect immediately (see that flag's own doc
/// comment).
private EventHandler scaleHandlerDelegate_;

package(fl) void installScaleHandler()
{
    if (scaleHandlerDelegate_ is null)
        scaleHandlerDelegate_ = (Event e) => scaleHandler(e);
    addHandler(scaleHandlerDelegate_, lastHandler());
}

/// Horizontal/vertical dots-per-inch of monitor `n` (default `0`,
/// matching FLTK's own default argument). Ported from
/// `Fl::screen_dpi(float&,float&,int)` -- see `fl.platform_x11.
/// screenDpi()`/`fl.platform_win32.screenDpi()`. `0.0` when the value
/// is unknown, matching FLTK (set explicitly: a D `out float` would
/// otherwise start as NaN).
void screenDpi(out float h, out float v, int n = 0)
{
    h = v = 0.0f;
    version (linux) platformX11.screenDpi(h, v, n);
    else version (Windows) platformWin32.screenDpi(h, v, n);
}

/// Ported from `Fl::screen_xywh(X,Y,W,H,n)` -- the bounding box of
/// monitor `n` (clamped to `[0, screenCount())` if out of range). A
/// no-op (leaves `x`/`y`/`w`/`h` at their `.init` values, all `0`) on
/// non-Linux platforms.
void screenXYWH(out int x, out int y, out int w, out int h, int n)
{
    version (linux) platformX11.screenXYWH(x, y, w, h, n);
    else version (Windows) platformWin32.screenXYWH(x, y, w, h, n);
}

/// Ported from `Fl::screen_xywh(X,Y,W,H,mx,my)` -- the bounding box of
/// whichever monitor contains point `(mx,my)`.
void screenXYWH(out int x, out int y, out int w, out int h, int mx, int my)
{
    screenXYWH(x, y, w, h, screenNum(mx, my));
}

/// Ported from `Fl::screen_xywh(X,Y,W,H,mx,my,mw,mh)` -- the bounding
/// box of whichever monitor overlaps rectangle `(mx,my,mw,mh)` the
/// most, by pixel area.
void screenXYWH(out int x, out int y, out int w, out int h, int mx, int my, int mw, int mh)
{
    screenXYWH(x, y, w, h, screenNum(mx, my, mw, mh));
}

/// Ported from `Fl::screen_xywh(X,Y,W,H)` -- the bounding box of
/// whichever monitor currently contains the mouse pointer (matching
/// FLTK's own `get_mouse()`-based implementation exactly).
void screenXYWH(out int x, out int y, out int w, out int h)
{
    int mx, my;
    int n = getMouse(mx, my); // getMouse() already returns the containing screen index
    screenXYWH(x, y, w, h, n);
}

/**
 * Bounding box of monitor `n`'s (or, no-arg/`(mx,my)` overloads, the
 * mouse-containing/point-containing monitor's) *work area*. Ported from
 * `Fl::screen_work_area(X,Y,W,H,n)`/`(X,Y,W,H,mx,my)`/`(X,Y,W,H)`
 * (`src/screen_xywh.cxx`), backed by the real
 * `_NET_WORKAREA` EWMH query
 * (`fl.platform_x11.screenWorkArea()`, ported from
 * `Fl_X11_Screen_Driver::screen_work_area()`/`init_workarea()`), so
 * these correctly exclude a desktop panel/taskbar/dock reserved
 * along an edge, for the primary screen at least (matching FLTK's
 * own single-monitor-only limitation -- see that function's own doc
 * comment for why `_NET_WORKAREA` can't be trusted per-monitor).
 */
void screenWorkArea(out int x, out int y, out int w, out int h, int n)
{
    version (linux) platformX11.screenWorkArea(x, y, w, h, n);
    else version (Windows) platformWin32.screenWorkArea(x, y, w, h, n);
    else screenXYWH(x, y, w, h, n);
}

/// ditto
void screenWorkArea(out int x, out int y, out int w, out int h, int mx, int my)
{
    screenWorkArea(x, y, w, h, screenNum(mx, my));
}

/// ditto
void screenWorkArea(out int x, out int y, out int w, out int h)
{
    int mx, my;
    int n = getMouse(mx, my);
    screenWorkArea(x, y, w, h, n);
}

/**
 * Top-left position and size, in pixels, of the primary screen's work
 * area (screen index 0). Ported from `Fl::x()`/`Fl::y()`/`Fl::w()`/
 * `Fl::h()` (`src/screen_xywh.cxx`) -- FLTK backs these with
 * `fl_workarea_xywh` (the `_NET_WORKAREA` EWMH property, excluding any
 * panel/taskbar/dock reserved along an edge), a genuinely different X11
 * query than `screenXYWH()` above (Xinerama's *full* monitor geometry).
 * Forwards to `screenWorkArea(..., 0)`, matching FLTK exactly (see
 * that function's own doc comment for the real `_NET_WORKAREA` query
 * and its single-monitor-only limitation).
 */
int x() { int rx, ry, rw, rh; screenWorkArea(rx, ry, rw, rh, 0); return rx; }
int y() { int rx, ry, rw, rh; screenWorkArea(rx, ry, rw, rh, 0); return ry; } /// ditto
int w() { int rx, ry, rw, rh; screenWorkArea(rx, ry, rw, rh, 0); return rw; } /// ditto
int h() { int rx, ry, rw, rh; screenWorkArea(rx, ry, rw, rh, 0); return rh; } /// ditto

/// Ported from `Fl::screen_num(int,int)` -- the index of the monitor
/// containing point `(x,y)`, or `0` if none does (also `0` on
/// non-Linux platforms).
int screenNum(int x, int y)
{
    version (linux) return platformX11.screenNum(x, y);
    else version (Windows)
    {
        int r = platformWin32.screenNum(x, y);
        return r < 0 ? 0 : r;
    }
    else return 0;
}

/// Ported from `Fl::screen_num(int,int,int,int)` -- the index of the
/// monitor overlapping rectangle `(x,y,w,h)` the most, by pixel area.
int screenNum(int x, int y, int w, int h)
{
    version (linux) return platformX11.screenNum(x, y, w, h);
    else version (Windows)
    {
        // fl.platform_win32 doesn't yet have a real "most-overlap"
        // rectangle query (FLTK's own `Fl_Screen_Driver::
        // screen_num(x,y,w,h)` is actually platform-independent, an
        // area-overlap loop over `screen_count()`/`screen_xywh()` --
        // ported here directly rather than in fl.platform_win32, since
        // it needs no platform-specific data beyond what screenXYWH()
        // already exposes).
        import std.algorithm.comparison : max, min;

        int best = 0;
        long bestArea = -1;
        foreach (n; 0 .. screenCount())
        {
            int sx, sy, sw, sh;
            screenXYWH(sx, sy, sw, sh, n);
            long ox = cast(long) max(x, sx);
            long oy = cast(long) max(y, sy);
            long ex = cast(long) min(x + w, sx + sw);
            long ey = cast(long) min(y + h, sy + sh);
            if (ex <= ox || ey <= oy) continue;
            long area = (ex - ox) * (ey - oy);
            if (area > bestArea) { bestArea = area; best = n; }
        }
        return best;
    }
    else return 0;
}

/// Simplified stand-in for Fl::clear_widget_pointer(); see module note
/// above. Also does the one piece of FLTK's separate fl_throw_focus()
/// (Fl_x.cxx, called from ~Fl_Widget() alongside Fl::clear_widget_pointer())
/// that isn't already covered by the watch-list walk below:
/// fl.tooltip.exit(w) hides an already-showing tooltip window and cancels
/// its timers if w is (or owns) the widget it's currently for -- the
/// watch-list only nulls out the dangling *reference*, it doesn't run any
/// cleanup when that happens (see fl.tooltip's currentWidget_ doc comment).
void clearWidgetPointer(Widget w)
{
    if (focus_ is w)
        focus_ = null;
    if (oldFocus_ is w)
        oldFocus_ = null;
    if (belowmouse_ is w)
        belowmouse_ = null;
    if (pushed_ is w)
        pushed_ = null;

    foreach (entry; widgetWatchList_)
        if (*entry is w) *entry = null;

    fl.tooltip.exit(w);
}

/// The widget-watch list backing fl.widget_tracker's WidgetTracker --
/// see that module's comment. Each entry is the address of a
/// WidgetTracker's own `wp_` field (a stack-local struct in every
/// intended use here, so nulling one out during clearWidgetPointer()
/// is always touching plain stack memory, never another GC-managed
/// object's fields -- safe unconditionally, including during
/// GC-driven finalization, unlike the cross-object cases CONVENTIONS.md's
/// GC-finalizer note warns about).
private Widget*[] widgetWatchList_;

/// Ported from Fl::watch_widget_pointer(Fl_Widget*&). Registers `w`
/// (by reference) so a later clearWidgetPointer(w) call finds and
/// nulls it out. package(fl): only fl.widget_tracker's WidgetTracker
/// should call this directly.
package(fl) void watchWidgetPointer(ref Widget w)
{
    widgetWatchList_ ~= &w;
}

/// Ported from Fl::release_widget_pointer(Fl_Widget*&). Removes `w`'s
/// registration; package(fl), see watchWidgetPointer()'s doc comment.
package(fl) void releaseWidgetPointer(ref Widget w)
{
    auto p = &w;
    size_t writeIdx = 0;
    foreach (i; 0 .. widgetWatchList_.length)
        if (widgetWatchList_[i] !is p) widgetWatchList_[writeIdx++] = widgetWatchList_[i];
    widgetWatchList_.length = writeIdx;
}

/*
 * Stand-in for fl_throw_focus() (declared `extern` in src/Fl_Widget.cxx,
 * defined in src/Fl_x.cxx). Moves focus away from a widget that is being
 * hidden, deactivated, or destroyed.
 *
 * `pendingPasteReceiver_` (fl_selection_requestor's D equivalent) is
 * also cleared here: without
 * it, destroying/hiding/deactivating a widget with a paste() request
 * still in flight would let the eventual SelectionNotify reply call
 * handle(Event.paste) on the torn-down widget, exactly what FLTK's
 * own fl_throw_focus() doc comment says this function exists to prevent.
 *
 * Real focus re-derivation: FLTK's real `fl_throw_focus()`
 * clears exactly the same four pointers this
 * port does, then unconditionally calls `fl_fix_focus()`, a
 * separate function. Full
 * `fl_fix_focus()` is a general resync (also handles `belowmouse`/
 * modal/enter-leave, driven by a platform-tracked `fl_xfocus` this port
 * doesn't have an equivalent global for) -- what's ported here is its
 * focus-specific half, re-derived from `w` itself (the widget just
 * thrown from) rather than a separate tracked "window with real OS
 * focus" variable: correct for exactly the case this function exists
 * to fix (the widget holding focus is going away, in a window that
 * itself never lost real OS-level focus), matching what `fl_fix_focus()`
 * would derive too in that same single-window scenario. Walks up to
 * `w`'s own top-level window and calls `takeFocus()` on it (the same
 * `Fl_Group::handle(FL_FOCUS)` child-trying mechanism FLTK's own
 * `Fl_Widget::take_focus()` -> `Fl_Group` override uses, already fully
 * ported -- see `fl.group.FlGroup.handle()`'s own `Event.focus` case),
 * falling back to focusing the window itself if nothing in it wants
 * focus, exactly matching `fl_fix_focus()`'s own `if (!w->take_focus())
 * Fl::focus(w);` tail.
 */
package(fl) void throwFocus(Widget w)
{
    if (w.contains(pushed_))
        pushed_ = null;
    if (w.contains(pendingPasteReceiver_))
        pendingPasteReceiver_ = null;
    if (w.contains(belowmouse_))
        belowmouse_ = null;

    if (w.contains(focus_))
    {
        focus_ = null;
        Widget topWin = w;
        while (topWin.parent !is null) topWin = topWin.parent;
        if (!topWin.takeFocus())
            focus_ = topWin;
    }
}

private struct BoxMetrics
{
    ubyte dx, dy, dw, dh;
    /// True if this boxtype paints a solid background (a "box"); false
    /// if it's outline-only (a "frame"). Mirrors fl_box_table's flags
    /// bit 1 (`bg() { return !(flags & 2); }` FLTK).
    bool bg;
}

/*
 * Ported from the metrics half of fl_box_table's initializer in
 * src/fl_boxtype.cxx (FLTK 1.5.0): the per-boxtype dx/dy/dw/dh frame
 * insets (used e.g. by Fl_Rect::inset(Boxtype) and Fl_Group::bounds()
 * to shrink a rectangle to a widget's interior) and the bg flag. Order
 * matches Boxtype's declaration order 1:1, per FLTK's own "must
 * match list in Enumerations.H!!!" comment on the table.
 *
 * The table's other half -- the actual per-boxtype box-drawing function
 * pointers (fl_up_box, fl_down_frame, ...) and the focus-frame-drawing
 * pointers (fl_rounded_focus, ...) -- is real too: see fl.draw.drawBoxAt() (a switch dispatch, not a literal
 * function-pointer table, but functionally complete) and
 * drawBoxFocus(). Box types beyond freeBoxtype+7 (up to maxBoxtype)
 * have no table entry FLTK either
 * (zero-initialized statically), which boxDx()/etc. below reproduce by
 * falling back to "no frame, has background" for any out-of-range index.
 *
 * D1/D2 mirror FLTK's D1/D2 macros, themselves `BORDER_WIDTH` (2)
 * and `2*BORDER_WIDTH`; this port doesn't have a build-time config
 * knob for BORDER_WIDTH, so the (also default) value of 2 is hardcoded.
 */
private enum ubyte D1 = 2;
private enum ubyte D2 = 4;

private immutable BoxMetrics[] boxTable = [
    BoxMetrics(0,  0,  0,  0,  false), // noBox
    BoxMetrics(0,  0,  0,  0,  true),  // flatBox
    BoxMetrics(D1, D1, D2, D2, true),  // upBox
    BoxMetrics(D1, D1, D2, D2, true),  // downBox
    BoxMetrics(D1, D1, D2, D2, false), // upFrame
    BoxMetrics(D1, D1, D2, D2, false), // downFrame
    BoxMetrics(1,  1,  2,  2,  true),  // thinUpBox
    BoxMetrics(1,  1,  2,  2,  true),  // thinDownBox
    BoxMetrics(1,  1,  2,  2,  false), // thinUpFrame
    BoxMetrics(1,  1,  2,  2,  false), // thinDownFrame
    BoxMetrics(2,  2,  4,  4,  true),  // engravedBox
    BoxMetrics(2,  2,  4,  4,  true),  // embossedBox
    BoxMetrics(2,  2,  4,  4,  false), // engravedFrame
    BoxMetrics(2,  2,  4,  4,  false), // embossedFrame
    BoxMetrics(1,  1,  2,  2,  true),  // borderBox
    BoxMetrics(1,  1,  5,  5,  true),  // shadowBox
    BoxMetrics(1,  1,  2,  2,  false), // borderFrame
    BoxMetrics(1,  1,  5,  5,  false), // shadowFrame
    BoxMetrics(1,  1,  2,  2,  true),  // roundedBox
    BoxMetrics(1,  1,  2,  2,  true),  // rshadowBox
    BoxMetrics(1,  1,  2,  2,  false), // roundedFrame
    BoxMetrics(0,  0,  0,  0,  true),  // rflatBox
    BoxMetrics(3,  3,  6,  6,  true),  // roundUpBox
    BoxMetrics(3,  3,  6,  6,  true),  // roundDownBox
    BoxMetrics(0,  0,  0,  0,  true),  // diamondUpBox
    BoxMetrics(0,  0,  0,  0,  true),  // diamondDownBox
    BoxMetrics(1,  1,  2,  2,  true),  // ovalBox
    BoxMetrics(1,  1,  2,  2,  true),  // oshadowBox
    BoxMetrics(1,  1,  2,  2,  false), // ovalFrame
    BoxMetrics(0,  0,  0,  0,  true),  // oflatBox
    BoxMetrics(2,  2,  4,  4,  true),  // plasticUpBox
    BoxMetrics(2,  2,  4,  4,  true),  // plasticDownBox
    BoxMetrics(2,  2,  4,  4,  false), // plasticUpFrame
    BoxMetrics(2,  2,  4,  4,  false), // plasticDownFrame
    BoxMetrics(2,  2,  4,  4,  true),  // plasticThinUpBox
    BoxMetrics(2,  2,  4,  4,  true),  // plasticThinDownBox
    BoxMetrics(2,  2,  4,  4,  true),  // plasticRoundUpBox
    BoxMetrics(2,  2,  4,  4,  true),  // plasticRoundDownBox
    BoxMetrics(2,  2,  4,  4,  true),  // gtkUpBox
    BoxMetrics(2,  2,  4,  4,  true),  // gtkDownBox
    BoxMetrics(2,  2,  4,  4,  false), // gtkUpFrame
    BoxMetrics(2,  2,  4,  4,  false), // gtkDownFrame
    BoxMetrics(1,  1,  2,  2,  false), // gtkThinUpBox
    BoxMetrics(1,  1,  2,  2,  false), // gtkThinDownBox
    BoxMetrics(1,  1,  2,  2,  true),  // gtkThinUpFrame
    BoxMetrics(1,  1,  2,  2,  true),  // gtkThinDownFrame
    BoxMetrics(2,  2,  4,  4,  true),  // gtkRoundUpBox
    BoxMetrics(2,  2,  4,  4,  true),  // gtkRoundDownBox
    BoxMetrics(2,  2,  4,  4,  true),  // gleamUpBox
    BoxMetrics(2,  2,  4,  4,  true),  // gleamDownBox
    BoxMetrics(2,  2,  4,  4,  false), // gleamUpFrame
    BoxMetrics(2,  2,  4,  4,  false), // gleamDownFrame
    BoxMetrics(2,  2,  4,  4,  true),  // gleamThinUpBox
    BoxMetrics(2,  2,  4,  4,  true),  // gleamThinDownBox
    BoxMetrics(2,  2,  4,  4,  true),  // gleamRoundUpBox
    BoxMetrics(2,  2,  4,  4,  true),  // gleamRoundDownBox
    BoxMetrics(2,  2,  4,  4,  true),  // oxyUpBox
    BoxMetrics(2,  2,  4,  4,  true),  // oxyDownBox
    BoxMetrics(2,  2,  4,  4,  false), // oxyUpFrame
    BoxMetrics(2,  2,  4,  4,  false), // oxyDownFrame
    BoxMetrics(1,  1,  2,  2,  true),  // oxyThinUpBox
    BoxMetrics(1,  1,  2,  2,  true),  // oxyThinDownBox
    BoxMetrics(1,  1,  2,  2,  false), // oxyThinUpFrame
    BoxMetrics(1,  1,  2,  2,  false), // oxyThinDownFrame
    BoxMetrics(2,  2,  4,  4,  true),  // oxyRoundUpBox
    BoxMetrics(2,  2,  4,  4,  true),  // oxyRoundDownBox
    BoxMetrics(2,  2,  4,  4,  true),  // oxyButtonUpBox
    BoxMetrics(2,  2,  4,  4,  true),  // oxyButtonDownBox
    BoxMetrics(3,  3,  6,  6,  true),  // freeBoxtype (FL_FREE_BOX+0)
    BoxMetrics(3,  3,  6,  6,  true),  // FL_FREE_BOX+1
    BoxMetrics(3,  3,  6,  6,  true),  // FL_FREE_BOX+2
    BoxMetrics(3,  3,  6,  6,  true),  // FL_FREE_BOX+3
    BoxMetrics(3,  3,  6,  6,  true),  // FL_FREE_BOX+4
    BoxMetrics(3,  3,  6,  6,  true),  // FL_FREE_BOX+5
    BoxMetrics(3,  3,  6,  6,  true),  // FL_FREE_BOX+6
    BoxMetrics(3,  3,  6,  6,  true),  // FL_FREE_BOX+7
];

private BoxMetrics boxMetrics(Boxtype t)
{
    t = resolveBoxtype(t);
    return t < boxTable.length ? boxTable[t] : BoxMetrics(0, 0, 0, 0, true);
}

int boxDx(Boxtype t) { return boxMetrics(t).dx; }
int boxDy(Boxtype t) { return boxMetrics(t).dy; }
int boxDw(Boxtype t) { return boxMetrics(t).dw; }
int boxDh(Boxtype t) { return boxMetrics(t).dh; }

/// True if boxtype t paints a solid background; false if it's an
/// outline-only "frame" boxtype. `Widget.redrawLabel()` uses it.
bool boxBg(Boxtype t) { return boxMetrics(t).bg; }

unittest
{
    assert(boxDx(Boxtype.noBox) == 0 && boxDw(Boxtype.noBox) == 0);
    assert(!boxBg(Boxtype.noBox));

    assert(boxDx(Boxtype.upBox) == 2 && boxDw(Boxtype.upBox) == 4);
    assert(boxBg(Boxtype.upBox));

    assert(boxDx(Boxtype.upFrame) == 2 && boxDw(Boxtype.upFrame) == 4);
    assert(!boxBg(Boxtype.upFrame));

    assert(boxDx(Boxtype.shadowBox) == 1 && boxDw(Boxtype.shadowBox) == 5);

    // Free/user boxtypes beyond the table (but within Boxtype's range)
    // fall back to "no frame, has background".
    assert(boxDx(Boxtype.maxBoxtype) == 0);
    assert(boxBg(Boxtype.maxBoxtype));
}

unittest
{
    // eventInside(x,y,w,h) tests the mouse position against a plain
    // rectangle; no widget tree needed.
    eX_ = 15;
    eY_ = 25;

    assert(eventInside(10, 20, 10, 10));   // (15,25) is inside [10,20)x[20,30)
    assert(!eventInside(20, 20, 10, 10));  // to the left of this rect
    assert(!eventInside(10, 30, 10, 10));  // above this rect

    eX_ = 0;
    eY_ = 0;
}

unittest
{
    // eventInside(Widget) matches eventInside(x,y,w,h) using the
    // widget's own bounds.
    static class Leaf : Widget
    {
        this(int x, int y, int w, int h) { super(x, y, w, h); }
        override void draw() {}
    }

    auto w = new Leaf(10, 20, 10, 10);

    eX_ = 15;
    eY_ = 25;
    assert(eventInside(w));

    eX_ = 100;
    eY_ = 100;
    assert(!eventInside(w));

    eX_ = 0;
    eY_ = 0;
}

unittest
{
    // testShortcut(0) is always false (0 means "no shortcut").
    assert(!testShortcut(0));
}

unittest
{
    // A plain lower-case letter shortcut matches an exact keysym, with
    // no shift required.
    eKeysym_ = 'a';
    eState_ = 0;
    assert(testShortcut('a'));
    assert(!testShortcut('b'));

    eKeysym_ = 0;
}

unittest
{
    // An upper-case letter in the shortcut value implicitly requires
    // Shift, even if the caller didn't OR stateShift in explicitly.
    eKeysym_ = 'A';
    eState_ = stateShift;
    assert(testShortcut('A'));

    eState_ = 0; // Shift not actually down: no match
    assert(!testShortcut('A'));

    eKeysym_ = 0;
    eState_ = 0;
}

unittest
{
    // Ctrl/Alt/Meta must match exactly; e.g. a plain 'a' shortcut does
    // not fire while Ctrl is held.
    eKeysym_ = 'a';
    eState_ = stateCtrl;
    assert(!testShortcut('a'));

    assert(testShortcut(stateCtrl | 'a'));

    eKeysym_ = 0;
    eState_ = 0;
}

unittest
{
    // Falls back to matching event_text()'s first character (ignoring
    // Shift) when the keysym itself doesn't match -- e.g. '#' typed as
    // shift+3 on a US keyboard layout.
    eKeysym_ = '3';
    eState_ = stateShift;
    eText_ = "#";
    assert(testShortcut('#'));

    eKeysym_ = 0;
    eState_ = 0;
    eText_ = "";
}

unittest
{
    // flShortcutLabel(0) is always "" (0 means "no shortcut").
    assert(flShortcutLabel(0) == "");

    // A plain printable key with no modifiers: just the uppercased
    // character, no "+"-joined modifier prefix.
    assert(flShortcutLabel('a') == "A");

    // Modifiers are prefixed in Ctrl/Alt/Shift/Meta order, matching
    // FLTK's fixed ordering.
    assert(flShortcutLabel(stateCtrl | 'a') == "Ctrl+A");
    assert(flShortcutLabel(stateCtrl | stateAlt | 'a') == "Ctrl+Alt+A");
    assert(flShortcutLabel(stateAlt | stateShift | 'a') == "Alt+Shift+A");

    // An upper-case key implies Shift even if the caller didn't OR it
    // in explicitly (same fixup as testShortcut()).
    assert(flShortcutLabel('A') == "Shift+A");
}

version (linux) unittest
{
    // Non-printable keysyms resolve through fl.platform_x11's
    // XKeysymToString()-backed keyName() rather than falling back to
    // the uppercased-character path -- verified here since it needs a
    // live X11 client library (XKeysymToString() doesn't need an open
    // display connection, just libX11 linked in, which `dub test`
    // already requires for every other module's Xlib bindings).
    import fl.enumerations : left, enter, kpEnter, f;

    assert(flShortcutLabel(left) == "Left");
    assert(flShortcutLabel(kpEnter) == "KP_Enter");
    assert(flShortcutLabel(enter) == "Enter");
    assert(flShortcutLabel(stateCtrl | (f + 1)) == "Ctrl+F1"); // FL_F+1 == F1
}

unittest
{
    // handle(): FL_PUSH sets pushed() and dispatches to the widget
    // passed in, always reporting "handled".
    static class RecordingWidget : Widget
    {
        Event[] seen;
        this() { super(0, 0, 100, 100); }
        override void draw() {}
        override int handle(Event event)
        {
            seen ~= event;
            return 1;
        }
    }

    resetForTest();

    auto w = new RecordingWidget();
    assert(handle(Event.push, w) == 1);
    assert(pushed() is w);
    assert(w.seen == [Event.push]);

    resetForTest();
}

unittest
{
    // handle(): FL_DRAG/FL_RELEASE route to pushed() -- not to the
    // window passed in -- and FL_RELEASE clears pushed() before dispatch.
    static class RecordingWidget : Widget
    {
        Event[] seen;
        this() { super(0, 0, 50, 50); }
        override void draw() {}
        override int handle(Event event)
        {
            seen ~= event;
            return 1;
        }
    }

    resetForTest();

    auto window = new RecordingWidget();
    auto child = new RecordingWidget();

    pushed(child);
    assert(handle(Event.drag, window) == 1);
    assert(child.seen == [Event.drag]);
    assert(window.seen.length == 0); // drag never reached the window itself

    assert(handle(Event.release, window) == 1);
    assert(child.seen == [Event.drag, Event.release]);
    assert(pushed() is null); // cleared by release, before dispatch

    resetForTest();
}

unittest
{
    // handle(): while a grab is active (e.g. fl.menu_popup's open popup
    // window), FL_PUSH redirects to the grab widget instead of whatever
    // window the event actually landed in -- without this, a click on
    // a *different* top-level window dispatched normally to that
    // window's own widgets instead of being swallowed by the grab.
    // FL_DRAG/FL_RELEASE need no separate
    // redirect of their own -- they just follow pushed_, which Event.push
    // already set to the grab target -- confirmed here too (see this
    // function's own doc comment for why an *explicit* redirect was
    // tried and reverted for those two: it clobbered a more-specific
    // pushed_ value in the real FlGroup-child case, a second real bug).
    static class RecordingWidget : Widget
    {
        Event[] seen;
        this() { super(0, 0, 50, 50); }
        override void draw() {}
        override int handle(Event event)
        {
            seen ~= event;
            return 1;
        }
    }

    resetForTest();

    auto grabbed = new RecordingWidget();
    auto other = new RecordingWidget(); // e.g. a button on a sibling window

    grab(grabbed);

    assert(handle(Event.push, other) == 1);
    assert(grabbed.seen == [Event.push]);
    assert(other.seen.length == 0); // never reached the actually-clicked widget
    assert(pushed() is grabbed);

    assert(handle(Event.drag, other) == 1);
    assert(grabbed.seen == [Event.push, Event.drag]);

    assert(handle(Event.release, other) == 1);
    assert(grabbed.seen == [Event.push, Event.drag, Event.release]);
    assert(pushed() is null);
    assert(other.seen.length == 0);

    grab(null);
    resetForTest();
}

unittest
{
    // handle(): a click landing directly on the modal() window itself
    // (fl.ask's own real shape: a dialog with Cancel/OK buttons inside
    // it, window == modal()) must reach the *specific child* that was
    // actually pushed on release, not the window as a whole -- e.g.
    // clicking "Cancel" must release on "Cancel", not somewhere else.
    // This is the same guarantee this codebase already established for
    // grab() (Event.release trusts pushed_ alone, no separate grab()/
    // modal() branch needed once Event.push has already set it
    // correctly), now re-verified for the modal() path specifically
    // now that fl.ask uses modal() instead of grab() (see modal()'s own
    // doc comment for the three real bugs the old grab()-based version
    // of this exact scenario caused, including "Cancel" not actually
    // cancelling).
    import fl.group : FlGroup;

    static class RecordingButton : Widget
    {
        Event[] seen;
        this(int x, int y, int w, int h) { super(x, y, w, h); }
        override void draw() {}
        override int handle(Event event)
        {
            seen ~= event;
            return event == Event.push || event == Event.release;
        }
    }

    FlGroup.current(null);
    resetForTest();

    auto win = new FlGroup(0, 0, 200, 50);
    auto cancel = new RecordingButton(10, 10, 80, 30);
    auto ok = new RecordingButton(110, 10, 80, 30);
    win.end();
    FlGroup.current(null);

    modal(win); // matches fl.ask's dialog window setModal()+show()

    eX_ = 50;
    eY_ = 25; // inside cancel's bounds, not ok's
    assert(handle(Event.push, win) == 1);
    assert(cancel.seen == [Event.push]);
    assert(ok.seen.length == 0);

    assert(handle(Event.release, win) == 1);
    assert(cancel.seen == [Event.push, Event.release]); // release reached cancel, not ok or the window
    assert(ok.seen.length == 0);

    eX_ = 0;
    eY_ = 0;
    modal(null);
    resetForTest();
    FlGroup.current(null);
}

unittest
{
    // modal(): plain getter/setter, package(fl)-visible setter usable
    // from within this module's own tests.
    resetForTest();
    assert(modal() is null);

    static class W : Widget
    {
        this() { super(0, 0, 10, 10); }
        override void draw() {}
    }
    auto w = new W();
    modal(w);
    assert(modal() is w);
    modal(null);
    assert(modal() is null);
    resetForTest();
}

unittest
{
    // firstWindow()/nextWindow()/firstWindow(Window): the parts that
    // don't need a live X server -- no window shown means firstWindow()
    // is null, and firstWindow(Window)/nextWindow(Window) are safe
    // no-ops for a never-shown() Window, matching FLTK's own
    // "!window->shown()) return;" guard. Both take/return a real
    // `Window`, not the generic `Widget`, matching FLTK's own
    // `Fl_Window*` signatures exactly -- so
    // passing a plain, non-Window Widget is a compile-time error,
    // not a runtime no-op.
    import fl.window : Window;
    import fl.group : FlGroup;

    resetForTest();
    assert(firstWindow() is null);
    assert(nextWindow(null) is null);

    FlGroup.current(null);
    auto win = new Window(100, 100, "never shown");
    win.end();
    firstWindow(win); // real Window, but never shown() -- still a no-op
    assert(firstWindow() is null);
    FlGroup.current(null);

    resetForTest();
}

unittest
{
    // handle(): while modal() is set, FL_PUSH to any *other* window is
    // discarded outright (never dispatched anywhere -- unlike grab()'s
    // redirect, there's no question of stale coordinates landing on the
    // wrong widget in a foreign window), but a push landing on the
    // modal window itself dispatches completely normally. Regression
    // coverage for the original reported bug (clicking a "Show" button
    // on the main window while an fl.ask dialog was open kept spawning
    // duplicate dialogs).
    static class RecordingWidget : Widget
    {
        Event[] seen;
        this() { super(0, 0, 50, 50); }
        override void draw() {}
        override int handle(Event event)
        {
            seen ~= event;
            return 1;
        }
    }

    resetForTest();

    auto dialog = new RecordingWidget();  // e.g. fl.ask's dialog window
    auto mainWin = new RecordingWidget(); // e.g. the app's main window

    modal(dialog);

    assert(handle(Event.push, mainWin) == 0); // discarded, not dispatched
    assert(mainWin.seen.length == 0);
    assert(dialog.seen.length == 0);
    assert(pushed() is null); // never set -- the event never reached push handling

    assert(handle(Event.push, dialog) == 1); // the modal window's own clicks work normally
    assert(dialog.seen == [Event.push]);
    assert(pushed() is dialog);

    modal(null);
    resetForTest();
}

unittest
{
    // handle(): while modal() is set, a plain FL_MOVE (nothing pushed)
    // over a *different* window is suppressed (no dispatch at all, so
    // no hover/hit-testing state anywhere gets updated for it), but an
    // in-progress FL_DRAG keeps following pushed_ regardless of modal()
    // -- matches FLTK's exact branching (the modal() check is only
    // in the not-yet-pushed() case).
    static class RecordingWidget : Widget
    {
        Event[] seen;
        this() { super(0, 0, 50, 50); }
        override void draw() {}
        override int handle(Event event)
        {
            seen ~= event;
            return 1;
        }
    }

    resetForTest();

    auto dialog = new RecordingWidget();
    auto mainWin = new RecordingWidget();

    modal(dialog);

    assert(handle(Event.move, mainWin) == 0);
    assert(mainWin.seen.length == 0);

    assert(handle(Event.move, dialog) == 1);
    assert(dialog.seen == [Event.move]);

    // Start a drag on the modal window, then keep dragging even though
    // the raw target window passed to handle() is mainWin -- pushed_
    // wins regardless of modal(), matching FLTK.
    handle(Event.push, dialog);
    dialog.seen = [];
    assert(handle(Event.drag, mainWin) == 1);
    assert(dialog.seen == [Event.drag]);
    assert(mainWin.seen.length == 0);

    handle(Event.release, dialog);
    modal(null);
    resetForTest();
}

unittest
{
    // handle(): FL_RELEASE falls back to modal() only when nothing is
    // currently pushed (a stray release) -- discarded if it lands on a
    // non-modal window, dispatched normally on the modal window itself.
    static class RecordingWidget : Widget
    {
        Event[] seen;
        this() { super(0, 0, 50, 50); }
        override void draw() {}
        override int handle(Event event)
        {
            seen ~= event;
            return 1;
        }
    }

    resetForTest();

    auto dialog = new RecordingWidget();
    auto mainWin = new RecordingWidget();

    modal(dialog);
    assert(pushed() is null);

    assert(handle(Event.release, mainWin) == 0);
    assert(mainWin.seen.length == 0);

    assert(handle(Event.release, dialog) == 1);
    assert(dialog.seen == [Event.release]);

    modal(null);
    resetForTest();
}

unittest
{
    // handle(): FL_MOUSEWHEEL redirects to modal() when set.
    static class RecordingWidget : Widget
    {
        Event[] seen;
        this() { super(0, 0, 50, 50); }
        override void draw() {}
        override int handle(Event event)
        {
            seen ~= event;
            return 1;
        }
    }

    resetForTest();

    auto dialog = new RecordingWidget();
    auto mainWin = new RecordingWidget();

    modal(dialog);
    assert(handle(Event.mouseWheel, mainWin) == 1);
    assert(dialog.seen == [Event.mouseWheel]);
    assert(mainWin.seen.length == 0);

    modal(null);
    resetForTest();
    assert(handle(Event.mouseWheel, mainWin) == 1); // no modal(): dispatches to the actual window
    assert(mainWin.seen == [Event.mouseWheel]);
    resetForTest();
}

unittest
{
    // handle(): Event.close -- discarded for a non-modal
    // window while modal() is set (matches FLTK's real FL_CLOSE
    // filtering), fires
    // doCallback(CallbackReason.closed) normally otherwise.
    static class RecordingWidget : Widget
    {
        CallbackReason[] closedReasons;
        this() { super(0, 0, 50, 50); }
        override void draw() {}
    }

    resetForTest();

    auto dialog = new RecordingWidget();
    auto mainWin = new RecordingWidget();
    dialog.callback((w) { (cast(RecordingWidget) w).closedReasons ~= callbackReason(); });
    mainWin.callback((w) { (cast(RecordingWidget) w).closedReasons ~= callbackReason(); });

    modal(dialog);
    assert(handle(Event.close, mainWin) == 0);
    assert(mainWin.closedReasons.length == 0);

    assert(handle(Event.close, dialog) == 1);
    assert(dialog.closedReasons == [CallbackReason.closed]);

    modal(null);
    resetForTest();

    assert(handle(Event.close, mainWin) == 1); // no modal(): closes normally
    assert(mainWin.closedReasons == [CallbackReason.closed]);
    resetForTest();
}

unittest
{
    // fixFocus(): while modal() is set, focus is pinned inside its
    // subtree regardless of which window X reports as newly focused --
    // matches FLTK's `if (Fl::modal()) w = Fl::modal();`.
    import fl.group : FlGroup;

    FlGroup.current(null);
    resetForTest();

    auto dialog = new FlGroup(0, 0, 100, 100);
    auto dialogChild = new class Widget
    {
        this() { super(10, 10, 20, 20); }
        override void draw() {}
    };
    dialog.end();

    auto otherWin = new FlGroup(0, 0, 100, 100);
    otherWin.end();
    FlGroup.current(null);

    modal(dialog);
    fixFocus(otherWin); // X says otherWin has focus, but modal() overrides it
    assert(dialog.contains(focus_));
    assert(!otherWin.contains(focus_));

    modal(null);
    resetForTest();
    FlGroup.current(null);
}

unittest
{
    // handle(): FL_KEYBOARD walks up from focus() through parent()s
    // until something returns non-zero.
    import fl.group : FlGroup;

    static class Leaf : Widget
    {
        int handleCalls;
        this() { super(0, 0, 10, 10); }
        override void draw() {}
        override int handle(Event event)
        {
            handleCalls++;
            return 0; // always refuses
        }
    }

    static class AcceptingGroup : FlGroup
    {
        int handleCalls;
        this() { super(0, 0, 100, 100); }
        override int handle(Event event)
        {
            handleCalls++;
            return 1;
        }
    }

    FlGroup.current(null);
    resetForTest();

    auto g = new AcceptingGroup();
    auto leaf = new Leaf();
    g.add(leaf);
    FlGroup.current(null);

    focus(leaf);
    assert(focus() is leaf);

    assert(handle(Event.keyDown, g) == 1);
    assert(leaf.handleCalls == 1); // tried first, refused
    assert(g.handleCalls == 1);    // walked up to parent, accepted

    resetForTest();
    FlGroup.current(null);
}

unittest
{
    // handle(): FL_KEYBOARD reaches a real modal() dialog's own focused
    // child (e.g. fl_input()'s Input field) correctly with zero special
    // casing, because grab() is null while a real modal() window is
    // open (fl.ask never calls grab() -- see modal()'s own
    // doc comment) -- so the existing, unmodified `grab() ? grab() :
    // focus()` ternary already reaches focus() directly, exactly
    // matching FLTK's real behavior (FLTK's real modal dialogs
    // never grab either). A "prefer a focused descendant
    // of grab()" workaround is unnecessary for the same reason.
    import fl.group : FlGroup;

    static class Leaf : Widget
    {
        int handleCalls;
        this() { super(0, 0, 10, 10); }
        override void draw() {}
        override int handle(Event event)
        {
            handleCalls++;
            return event == Event.keyDown ? 1 : 0; // consumes the keystroke
        }
    }

    static class RefusingGroup : FlGroup
    {
        int handleCalls;
        this() { super(0, 0, 100, 100); }
        override int handle(Event event)
        {
            if (event == Event.keyDown) { handleCalls++; return 1; } // would swallow it too
            return super.handle(event);
        }
    }

    FlGroup.current(null);
    resetForTest();

    auto g = new RefusingGroup();
    auto leaf = new Leaf();
    g.add(leaf);
    FlGroup.current(null);

    focus(leaf);  // matches Input.takeFocus(), called before the dialog shows
    modal(g);     // matches fl.ask's dialog window setModal()+show()

    assert(handle(Event.keyDown, g) == 1);
    assert(leaf.handleCalls == 1); // reached the focused Input first...
    assert(g.handleCalls == 0);    // ...and consumed it there, not at the window

    modal(null);
    resetForTest();
    FlGroup.current(null);
}

unittest
{
    // handle(): a Button's own shortcut() fires via FlGroup's fallback
    // iteration inside the FL_SHORTCUT case even when a *different*
    // sibling widget currently has focus() -- the mechanism
    // smoke-tests/shortcut_button.d exercises interactively (an
    // "Action" button whose shortcut() is kept in sync with a
    // ShortcutButton's recorded value, meant to fire regardless of
    // which widget has focus, per that test's own doc comment). Added
    // headlessly after a user report that the shortcut didn't seem to
    // trigger interactively, to check this dispatch path in isolation
    // before chasing a possible X11-level cause -- this passes, so the
    // dispatch chain itself (focus()'s FL_KEYBOARD walk falling through
    // to FL_SHORTCUT, then FlGroup.handle()'s child iteration) is not
    // where the interactive bug lives; see fl.shortcut_button.d's own
    // handle() for the more likely suspect (a still-"hot"/armed
    // ShortcutButton keeps focus() and swallows every keystroke as a
    // new recording instead of ever falling through to FL_SHORTCUT).
    import fl.group : FlGroup;
    import fl.window : Window;
    import fl.button : Button;

    FlGroup.current(null);
    resetForTest();

    auto win = new Window(0, 0, 200, 100);
    auto other = new Button(0, 0, 50, 20, "Other");
    auto action = new Button(60, 0, 50, 20, "Action");
    action.shortcut(stateCtrl | stateShift | 'a');
    win.end();
    FlGroup.current(null);

    int fired;
    action.callback((w) { fired++; });

    // A *different* widget has focus, matching fixFocus()'s real
    // behavior on window creation (the first-added child gets it
    // automatically, not whichever widget owns the shortcut).
    focus(other);

    eKeysym_ = cast(Keysym) 'a';
    eState_ = stateCtrl | stateShift;
    eText_ = "";

    assert(handle(Event.keyDown, win) == 1);
    assert(fired == 1);

    resetForTest();
    FlGroup.current(null);
}

unittest
{
    // handle(): FL_MOUSEWHEEL dispatches straight to the window.
    static class RecordingWidget : Widget
    {
        Event[] seen;
        this() { super(0, 0, 100, 100); }
        override void draw() {}
        override int handle(Event event)
        {
            seen ~= event;
            return 1;
        }
    }

    resetForTest();

    auto w = new RecordingWidget();
    assert(handle(Event.mouseWheel, w) == 1);
    assert(w.seen == [Event.mouseWheel]);

    resetForTest();
}

unittest
{
    // boxShadowWidth(): default 3, settable, clamped to >= 1.
    assert(boxShadowWidth() == 3);

    boxShadowWidth(5);
    assert(boxShadowWidth() == 5);

    boxShadowWidth(0);
    assert(boxShadowWidth() == 1);

    boxShadowWidth(3); // restore the default for other tests
}

unittest
{
    // boxBorderRadiusMax(): default 15, settable, clamped to >= 5.
    assert(boxBorderRadiusMax() == 15);

    boxBorderRadiusMax(20);
    assert(boxBorderRadiusMax() == 20);

    boxBorderRadiusMax(2);
    assert(boxBorderRadiusMax() == 5);

    boxBorderRadiusMax(15); // restore the default for other tests
}

unittest
{
    // screenScale(int)/screenScale(int, float): default 1.0, settable,
    // rejects non-positive factors and out-of-range screen numbers.
    assert(screenScale(0) == 1.0f);

    screenScale(0, 2.0f);
    assert(screenScale(0) == 2.0f);

    screenScale(0, 0f);
    assert(screenScale(0) == 2.0f); // unchanged, non-positive rejected

    screenScale(0, -1.0f);
    assert(screenScale(0) == 2.0f); // unchanged, non-positive rejected

    screenScale(-1, 3.0f);
    assert(screenScale(0) == 2.0f); // unchanged, screen -1 out of range

    assert(screenScale(-1) == 1.0f); // out-of-range read reports 1.0

    // A genuine per-screen array: changing screen 1's factor must
    // leave screen 0's own entry untouched -- without this,
    // dragging
    // one window to a differently-scaled monitor would visibly rescale every
    // other window still on the original monitor.
    if (screenCount() > 1)
    {
        screenScale(1, 3.0f);
        assert(screenScale(0) == 2.0f); // still unaffected
        assert(screenScale(1) == 3.0f);
        screenScale(1, 1.0f); // restore
    }

    screenScale(0, 1.0f); // restore the default for other tests

    assert(screenScalingSupported() == 2); // real per-screen support now
}

unittest
{
    // currentScale()/currentScale(float): the live drawing-scale cache,
    // deliberately separate from screenScale()'s own per-screen table
    // (see currentScale_'s own doc comment) -- starts at 1.0, settable,
    // rejects non-positive factors exactly like screenScale(int,float).
    assert(currentScale() == 1.0f);

    currentScale(2.5f);
    assert(currentScale() == 2.5f);

    currentScale(0f);
    assert(currentScale() == 2.5f); // unchanged, non-positive rejected

    currentScale(-1.0f);
    assert(currentScale() == 2.5f); // unchanged, non-positive rejected

    currentScale(1.0f); // restore the default for other tests
}

unittest
{
    // addTimeout(): fires once, after (at least) its requested delay,
    // and processTimeouts() is a no-op before that delay elapses.
    resetForTest();

    int fired;
    addTimeout(0.01, () { fired++; });

    processTimeouts();
    assert(fired == 0); // not due yet

    import core.thread : Thread;
    import core.time : msecs;
    Thread.sleep(30.msecs);

    processTimeouts();
    assert(fired == 1);

    processTimeouts();
    assert(fired == 1); // one-shot: doesn't fire again

    resetForTest();
}

unittest
{
    // hasTimeout()/removeTimeout(): identified by delegate identity
    // (function + closure context), matching two distinct closures
    // over the same captured variable as distinct timers.
    resetForTest();

    int a, b;
    void delegate() cbA = () { a++; };
    void delegate() cbB = () { b++; };

    addTimeout(10.0, cbA);
    addTimeout(10.0, cbB);
    assert(hasTimeout(cbA));
    assert(hasTimeout(cbB));

    removeTimeout(cbA);
    assert(!hasTimeout(cbA));
    assert(hasTimeout(cbB));

    removeTimeout(cbB);
    assert(!hasTimeout(cbB));

    resetForTest();
}

unittest
{
    // removeTimeout() removes *every* matching entry, not just the
    // first, matching FLTK's documented behavior.
    resetForTest();

    int fired;
    void delegate() cb = () { fired++; };
    addTimeout(10.0, cb);
    addTimeout(10.0, cb);
    addTimeout(10.0, cb);

    removeTimeout(cb);
    assert(!hasTimeout(cb));

    resetForTest();
}

unittest
{
    // addFd()/removeFd() (core-roadmap item 6): plain registration/
    // bookkeeping, no live fd or select() call needed to exercise it --
    // fl.platform_x11.waitForEventOrTimeout() is what actually reads
    // fdEntries() and dispatches callbacks against a real select(), and
    // needs a live X server to test at all (see that module's own
    // "no unittest blocks" note), so this covers only the platform-
    // independent bookkeeping half.
    resetForTest();

    assert(fdEntries().length == 0);

    int seen;
    addFd(7, fdRead, (fd) { seen = fd; });
    assert(fdEntries().length == 1);
    assert(fdEntries()[0].fd == 7);
    assert(fdEntries()[0].when == fdRead);

    // 1-arg overload defaults to fdRead, matching FLTK's own
    // add_fd(n, cb) -> add_fd(n, POLLIN, cb).
    addFd(9, (fd) {});
    assert(fdEntries().length == 2);
    foreach (e; fdEntries())
        if (e.fd == 9) assert(e.when == fdRead);

    // Re-registering the same fd for an overlapping `when` replaces the
    // entry for those bits rather than adding a second, competing one
    // (matches FLTK's own remove-then-add-fresh `add_fd()` body).
    addFd(7, fdRead | fdWrite, (fd) { seen = -fd; });
    assert(fdEntries().length == 2); // still just fd 7 and fd 9
    foreach (e; fdEntries())
        if (e.fd == 7) assert(e.when == (fdRead | fdWrite));

    // removeFd(fd, when) narrows -- clearing just fdWrite from fd 7
    // leaves an fdRead-only entry behind, not an empty one.
    removeFd(7, fdWrite);
    assert(fdEntries().length == 2);
    foreach (e; fdEntries())
        if (e.fd == 7) assert(e.when == fdRead);

    // removeFd(fd, when) clearing the *last* remaining bit drops the
    // entry entirely.
    removeFd(7, fdRead);
    assert(fdEntries().length == 1);
    assert(fdEntries()[0].fd == 9);

    // removeFd(fd) (no `when`) removes regardless of bits.
    removeFd(9);
    assert(fdEntries().length == 0);

    resetForTest();
    assert(fdEntries().length == 0);
}

unittest
{
    // Fl::now()/seconds_since()/seconds_between() -- no live event loop
    // needed, pure MonoTime arithmetic.
    auto t0 = now();
    auto t1 = now();
    assert(secondsSince(t0) >= 0);
    assert(secondsBetween(t1, t0) >= 0);
    assert(ticksSince(t0) >= 0);
    assert(ticksBetween(t1, t0) >= 0);

    // now(offset) shifts the returned stamp forward.
    auto shifted = now(10.0);
    assert(secondsBetween(shifted, t0) > 9.0);
}

unittest
{
    // Fl::lock()/unlock()/awake(handler)/awake_once(handler) -- the
    // queue/mutex bookkeeping only; the real wakeup-via-select() path
    // needs a live event loop, same "no unittest blocks for the actual
    // dispatch" reasoning as fl.platform_x11's own module note (see
    // addFd()'s unittest just above). drainAwakePipe() itself just pops
    // this same queue in a loop, so exercising push/pop directly here
    // covers the same logic a real pipe wakeup would run.
    awakeQueue_ = null;

    int calls;
    awake(() { calls++; });
    assert(awakeQueue_.length == 1);
    auto h = popAwakeHandler();
    assert(h !is null);
    h();
    assert(calls == 1);
    assert(popAwakeHandler() is null);

    // awake_once() de-duplicates a repeated, identical delegate value
    // (same context + function pointer) instead of queuing it twice.
    void delegate() same = () { calls++; };
    awakeOnce(same);
    awakeOnce(same);
    assert(awakeQueue_.length == 1);
    awakeQueue_ = null;

    assert(lock() == 0);
    unlock();

    resetForTest();
}

unittest
{
    // repeatTimeout() called from within a firing callback reschedules
    // relative to the *original* due time, not "now" -- so two
    // back-to-back short repeats still fire close together rather than
    // drifting later by however long processTimeouts() itself took.
    resetForTest();

    int fired;
    void selfRepeating()
    {
        fired++;
        if (fired < 2) repeatTimeout(0.01, &selfRepeating);
    }
    addTimeout(0.01, &selfRepeating);

    import core.thread : Thread;
    import core.time : msecs;

    Thread.sleep(30.msecs);
    processTimeouts();
    assert(fired == 1);

    Thread.sleep(30.msecs);
    processTimeouts();
    assert(fired == 2);

    resetForTest();
}

unittest
{
    // timeToWait(): reports the soonest pending timer's remaining
    // delay (capped at the caller's own upper bound), or that upper
    // bound unchanged if nothing is pending.
    import core.time : msecs, seconds, Duration;

    resetForTest();

    assert(timeToWait(5.seconds) == 5.seconds);

    addTimeout(0.5, () {});
    Duration d = timeToWait(5.seconds);
    assert(d > Duration.zero && d <= 500.msecs);

    addTimeout(0.05, () {}); // sooner than the 0.5s one above
    d = timeToWait(5.seconds);
    assert(d > Duration.zero && d <= 50.msecs);

    resetForTest();
}

unittest
{
    // grab(): while active, focus()/belowmouse() become no-ops (matching
    // FLTK's guards), and stop being no-ops again once released.
    import fl.group : FlGroup;
    import fl.box : Box;

    FlGroup.current(null);
    resetForTest();

    auto a = new Box(0, 0, 10, 10);
    auto b = new Box(20, 0, 10, 10);

    focus(a);
    assert(focus() is a);
    belowmouse(a);
    assert(belowmouse() is a);

    assert(grab() is null);
    grab(b); // b stands in for a menu popup window here
    assert(grab() is b);

    focus(b);
    assert(focus() is a); // unchanged: focus() is a no-op while grabbed
    belowmouse(b);
    assert(belowmouse() is a); // ditto

    grab(null);
    assert(grab() is null);

    focus(b);
    assert(focus() is b); // works again now that the grab is released

    resetForTest();
    FlGroup.current(null);
}

unittest
{
    // addHandler()/removeHandler()/lastHandler(): basic install/order/
    // remove, most-recently-added first.
    resetForTest();

    int[] seen;
    EventHandler h1 = (e) { seen ~= 1; return 0; };
    EventHandler h2 = (e) { seen ~= 2; return 0; };

    assert(lastHandler() is null);
    addHandler(h1);
    assert(lastHandler() is h1);
    addHandler(h2);
    assert(lastHandler() is h2); // most recently added

    assert(sendHandlers(Event.shortcut) == 0); // neither claims it
    assert(seen == [2, 1]); // h2 (most recent) tried first

    seen = [];
    removeHandler(h2);
    assert(lastHandler() is h1);
    sendHandlers(Event.shortcut);
    assert(seen == [1]);

    removeHandler(h1);
    assert(lastHandler() is null);
    resetForTest();
}

unittest
{
    // addHandler(ha, before): inserts ha with priority just below
    // `before`, matching FLTK's own doc comment ("just lower than
    // that of function before").
    resetForTest();

    int[] seen;
    EventHandler h1 = (e) { seen ~= 1; return 0; };
    EventHandler h2 = (e) { seen ~= 2; return 0; };
    EventHandler h3 = (e) { seen ~= 3; return 0; };

    addHandler(h1); // list: [h1]
    addHandler(h2); // list: [h2, h1]
    addHandler(h3, h2); // list: [h2, h3, h1] -- h3 runs right after h2

    sendHandlers(Event.shortcut);
    assert(seen == [2, 3, 1]);

    resetForTest();
}

unittest
{
    // addHandler(ha, before) with before==null behaves like the 1-arg
    // overload; with a `before` that isn't installed, it's a silent
    // no-op (matches FLTK's own `while (l) {...}` falling off the
    // list without inserting), rather than an error.
    resetForTest();

    EventHandler h1 = (e) => 0;
    EventHandler h2 = (e) => 0;
    EventHandler neverInstalled = (e) => 0;

    addHandler(h1, null);
    assert(lastHandler() is h1);

    addHandler(h2, neverInstalled);
    assert(lastHandler() is h1); // h2 was never inserted anywhere

    resetForTest();
}

unittest
{
    // handle(): an unclaimed Event.shortcut falls through to
    // sendHandlers() before the Escape-closes-window fallback --
    // see Event.shortcut's own doc comment for the full integration
    // point.
    resetForTest();

    bool called;
    addHandler((e) { called = true; return 1; });

    eKeysym_ = 'z'; // not Escape, and no widget/belowmouse/modal() claims it
    assert(handle(Event.shortcut, null) == 1);
    assert(called);

    eKeysym_ = 0;
    resetForTest();
}

unittest
{
    // handle(): an unclaimed Event.mouseWheel (no grab(), no modal(),
    // and the target window's own handle() refuses it) falls through
    // to sendHandlers() too.
    static class RefusingWidget : Widget
    {
        this() { super(0, 0, 50, 50); }
        override void draw() {}
        override int handle(Event event) { return 0; }
    }

    resetForTest();

    auto w = new RefusingWidget();
    bool called;
    addHandler((e) { called = true; return 1; });

    assert(handle(Event.mouseWheel, w) == 1);
    assert(called);

    resetForTest();
}

unittest
{
    // addSystemHandler()/removeSystemHandler()/sendSystemHandlers():
    // same most-recently-added-first/consume-on-nonzero shape as the
    // regular handler chain, but operating on an opaque void* (a raw
    // platform event, XEvent* on Linux -- a plain int here is enough
    // to exercise the dispatch mechanics headlessly).
    resetForTest();

    int dummyEvent = 42;
    int[] seen;
    SystemHandler s1 = (e) { seen ~= 1; return 0; };
    SystemHandler s2 = (e) { seen ~= *(cast(int*) e) == 42 ? 2 : -1; return 1; };

    addSystemHandler(s1);
    addSystemHandler(s2);

    assert(sendSystemHandlers(&dummyEvent) == 1); // s2 (most recent) claims it
    assert(seen == [2]); // s1 never even ran, s2 consumed it first

    removeSystemHandler(s2);
    seen = [];
    assert(sendSystemHandlers(&dummyEvent) == 0); // now only s1, which never claims it
    assert(seen == [1]);

    removeSystemHandler(s1);
    resetForTest();
}

unittest
{
    // eventDispatch()/dispatch(): a custom dispatcher, once installed,
    // intercepts every dispatch() call instead of the real handle()
    // logic; null (the default) just forwards straight to handle().
    static class RecordingWidget : Widget
    {
        Event[] seen;
        this() { super(0, 0, 50, 50); }
        override void draw() {}
        override int handle(Event event) { seen ~= event; return 1; }
    }

    resetForTest();

    auto w = new RecordingWidget();

    assert(eventDispatch() is null);
    assert(dispatch(Event.push, w) == 1); // no dispatcher installed: forwards to handle()
    assert(w.seen == [Event.push]);
    assert(pushed() is w);
    pushed(null);

    bool dispatcherCalled;
    Event[] dispatcherSaw;
    eventDispatch((e, win) {
        dispatcherCalled = true;
        dispatcherSaw ~= e;
        return handle(e, win); // a real dispatcher normally still calls the real logic
    });
    assert(eventDispatch() !is null);

    w.seen = [];
    assert(dispatch(Event.push, w) == 1);
    assert(dispatcherCalled);
    assert(dispatcherSaw == [Event.push]);
    assert(w.seen == [Event.push]); // still reached the widget, via the dispatcher calling handle()

    eventDispatch(null);
    assert(eventDispatch() is null);

    resetForTest();
}

unittest
{
    // option()/option(Option, bool): every entry starts at its
    // documented FLTK default, is independently settable, and
    // resetForTest() restores all of them together.
    resetForTest();

    assert(option(Option.arrowFocus) == false);
    assert(option(Option.visibleFocus) == true);
    assert(option(Option.dndText) == true);
    assert(option(Option.showTooltips) == true);
    assert(option(Option.fnfcUsesGtk) == true);
    assert(option(Option.fnfcUsesZenity) == false);
    assert(option(Option.fnfcUsesKdialog) == false);
    assert(option(Option.printerUsesGtk) == true);
    assert(option(Option.showScaling) == true);
    assert(option(Option.simpleZoomShortcut) == true); // this port's own default, not FLTK's (see optionDefaults_'s own doc comment)

    option(Option.arrowFocus, true);
    option(Option.showTooltips, false);
    assert(option(Option.arrowFocus) == true);
    assert(option(Option.showTooltips) == false);
    assert(option(Option.visibleFocus) == true); // untouched entries unaffected

    resetForTest();
    assert(option(Option.arrowFocus) == false); // back to default
    assert(option(Option.showTooltips) == true);
}

unittest
{
    // Regression test: calling the setter as the very *first* touch of the options
    // system -- exactly how every real caller uses it (e.g.
    // `fl.option(Fl.Option.arrowFocus, true);` at the top of `main()`,
    // before any widget exists to call the getter first) -- must not
    // get silently discarded the next time *anything* calls the getter.
    resetForTest();

    option(Option.arrowFocus, true); // setter called first, no prior getter call
    assert(option(Option.arrowFocus) == true); // must survive the getter's lazy readOptions_()
    assert(option(Option.visibleFocus) == true); // untouched entries still at their default

    resetForTest();
}

unittest
{
    // visibleFocus()/visibleFocus(bool) and dndTextOps()/dndTextOps(bool):
    // thin wrappers, matching FLTK's own inline forwarding --
    // confirm they actually read/write the same underlying Option
    // entry option() itself does, not an independent copy.
    resetForTest();

    assert(visibleFocus() == true);
    visibleFocus(false);
    assert(!option(Option.visibleFocus));
    option(Option.visibleFocus, true);
    assert(visibleFocus());

    assert(dndTextOps() == true);
    dndTextOps(false);
    assert(!option(Option.dndText));
    option(Option.dndText, true);
    assert(dndTextOps());

    resetForTest();
}

unittest
{
    // core-roadmap item 4: paste() when we don't own the requested
    // selection must NOT deliver synchronously anymore -- it has to
    // match FLTK's real asynchronous model (fire an X11 request,
    // return immediately, deliver later once the reply arrives). The
    // "later" half is exercised directly here via deliverPaste(), the
    // same package-internal entry point fl.platform_x11's
    // SelectionNotify handler calls once the real reply lands.
    import fl.input : Input;

    resetForTest();
    auto recv = new Input(0, 0, 100, 20);

    // Nobody owns clipboard slot 1 in this test (resetForTest() clears
    // weOwnSelection_) -- paste() takes the async path: on Linux this
    // fires a real (harmless) XConvertSelection() via fl.platform_x11
    // and returns without touching recv at all, matching this port's
    // established precedent of touching a live X display as a side
    // effect of a headless test (see e.g. beep()'s own tests).
    //
    // Non-Linux platforms are not similarly untouched: Windows has its own separate, real,
    // *synchronous* `version (Windows)` branch in `paste()` that genuinely reads the
    // live OS clipboard via `OpenClipboard()`/`GetClipboardData()` and
    // delivers whatever it finds immediately -- correct, FLTK-
    // faithful behavior. A headless test has no way to
    // predict or control the real system clipboard's actual content,
    // so this specific assertion can only be checked on Linux, where
    // the real asynchronous model guarantees no delivery happens before
    // `deliverPaste()` is called explicitly below.
    paste(recv, 1);
    version (linux) assert(recv.value() == "");

    // The rest of the async round-trip needs a *pending* receiver to
    // actually exist to deliver to, which only paste()'s `version
    // (linux)` branch (above) sets up -- non-Linux has nothing pending,
    // so deliverPaste() here would have nothing to deliver, not "a
    // stray reply arrived after delivery already happened" the way it
    // does on Linux.
    version (linux)
    {
        // Simulate the eventual SelectionNotify reply.
        deliverPaste("async text");
        assert(recv.value() == "async text");

        // No paste is pending anymore -- a second, unmatched reply is a
        // harmless no-op, not a delivery to a stale receiver.
        deliverPaste("stray reply");
        assert(recv.value() == "async text");
    }

    // Once we own the selection ourselves (copy()), paste() goes back
    // to delivering synchronously -- the in-process fast path, matching
    // FLTK's own "just use our own copy" shortcut.
    copy("owned text", 1);
    auto recv2 = new Input(0, 0, 100, 20);
    paste(recv2, 1);
    assert(recv2.value() == "owned text");

    // clearSelectionOwnership() (fl.platform_x11's SelectionClear
    // handler, simulated here) flips a slot back to the async path --
    // same real-live-clipboard caveat as the first assertion in this
    // test on Windows, see that one's own comment.
    clearSelectionOwnership(1);
    auto recv3 = new Input(0, 0, 100, 20);
    paste(recv3, 1);
    version (linux) assert(recv3.value() == ""); // async again, no synchronous delivery

    destroy(recv);
    destroy(recv2);
    destroy(recv3);
    resetForTest();
}

unittest
{
    // sendEvent(): subwindow coordinate-offset adjustment.
    // eX_/eY_ arrive relative to whichever
    // window actually received the raw platform event; dispatching to a
    // widget that lives inside a *different*, nested window must
    // translate them into that window's own local frame. This test
    // builds a widget tree entirely in memory (never calls show()/
    // hide() -- fl.window/fl.platform_x11's own established convention
    // is that anything touching a real X window needs a live display
    // and isn't unit-tested at all, see fl.platform_x11's module
    // comment), so it's pure coordinate arithmetic, no X server needed.
    import fl.window : Window;
    import fl.group : FlGroup;

    static class RecordingWidget : Widget
    {
        int seenX = int.min, seenY = int.min;
        this(int x, int y, int w, int h) { super(x, y, w, h); }
        override void draw() {}
        override int handle(Event event)
        {
            seenX = eventX();
            seenY = eventY();
            return 1;
        }
    }

    resetForTest();
    FlGroup.current(null);

    auto topWin = new Window(0, 0, 400, 300, "top");
    auto sub = new Window(20, 30, 100, 80, "sub"); // parent-relative to topWin, per the subwindow coordinate convention
    auto leaf = new RecordingWidget(5, 5, 20, 20); // relative to sub
    sub.end();
    topWin.end();
    FlGroup.current(null);

    // A raw event arriving at topWin's own local origin, at (25, 35) --
    // exactly sub's own top-left corner within topWin.
    eX_ = 25;
    eY_ = 35;
    sendEvent(Event.push, leaf, topWin);

    // Dispatched to `leaf` (inside `sub`, inside `topWin`): eventX()/
    // eventY() must come out relative to *sub*'s own local origin, not
    // topWin's -- (25,35) minus sub's own (20,30) offset within topWin
    // = (5,5). Before this fix, sendEvent() never adjusted anything, so
    // leaf would have seen the raw, topWin-relative (25,35) instead.
    assert(leaf.seenX == 5);
    assert(leaf.seenY == 5);

    // eX_/eY_ are restored to their pre-call (topWin-relative) values
    // once sendEvent() returns, matching FLTK's own save/restore.
    assert(eX_ == 25);
    assert(eY_ == 35);

    // Dispatching straight to a widget inside topWin itself (no
    // subwindow nesting at all) still nets to zero adjustment, matching
    // this port's pre-subwindow behavior exactly -- confirms the fix is
    // purely additive for the common case.
    auto plainLeaf = new RecordingWidget(15, 25, 20, 20);
    plainLeaf.parent(topWin);
    eX_ = 15;
    eY_ = 25;
    sendEvent(Event.push, plainLeaf, topWin);
    assert(plainLeaf.seenX == 15);
    assert(plainLeaf.seenY == 25);

    destroy(plainLeaf);
    destroy(leaf);
    destroy(sub);
    destroy(topWin);
    resetForTest();
}

unittest
{
    // throwFocus() clears pendingPasteReceiver_ when it (or an ancestor
    // of it) is thrown -- without this, destroying/hiding/deactivating
    // a widget with a
    // paste() request still in flight would leave a dangling pointer that
    // deliverPaste() would later dispatch Event.paste to anyway.
    import fl.group : FlGroup;

    static class RecordingWidget : Widget
    {
        this(int x, int y, int w, int h) { super(x, y, w, h); }
        override void draw() {}
    }

    resetForTest();

    auto w = new RecordingWidget(0, 0, 10, 10);
    pendingPasteReceiver_ = w;
    throwFocus(w);
    assert(pendingPasteReceiver_ is null);

    // Also cleared when the *ancestor* passed to throwFocus() contains
    // the pending receiver, matching pushed_/belowmouse_/focus_'s own
    // contains()-based clearing just above.
    FlGroup.current(null);
    auto group = new FlGroup(0, 0, 10, 10);
    auto child = new RecordingWidget(0, 0, 5, 5); // auto-parents into group via FlGroup.current()
    group.end();
    FlGroup.current(null);

    pendingPasteReceiver_ = child;
    throwFocus(group);
    assert(pendingPasteReceiver_ is null);

    // An unrelated widget being thrown leaves it untouched.
    auto other = new RecordingWidget(0, 0, 10, 10);
    pendingPasteReceiver_ = w;
    throwFocus(other);
    assert(pendingPasteReceiver_ is w);

    destroy(other);
    destroy(group); // also destroys child, a real FlGroup child
    destroy(w);
    resetForTest();
}

unittest
{
    // addIdle()/hasIdle()/removeIdle()/runIdle() -- headless (no
    // fl.platform_x11 involvement needed, matching fl.core's own
    // "test the platform-independent half directly" precedent used
    // elsewhere in this file, e.g. addFd()/removeFd()'s own tests).
    resetForTest();

    int calls;
    void inc() { calls++; }

    assert(!hasIdle(&inc));
    assert(!idleActive());

    addIdle(&inc);
    assert(hasIdle(&inc));
    assert(idleActive());

    // runIdle() calls exactly one registered callback per invocation
    // (FLTK's own ring-rotation design, see runIdle()'s own doc
    // comment) -- with only one registered, every call fires it.
    runIdle();
    runIdle();
    assert(calls == 2);

    removeIdle(&inc);
    assert(!hasIdle(&inc));
    assert(!idleActive());
    runIdle(); // no-op now
    assert(calls == 2);

    // Multiple callbacks rotate: each runIdle() call fires exactly one,
    // cycling through in registration order.
    int[] order;
    void a() { order ~= 1; }
    void b() { order ~= 2; }
    addIdle(&a);
    addIdle(&b);
    runIdle();
    runIdle();
    runIdle();
    assert(order == [1, 2, 1]);
    removeIdle(&a);
    removeIdle(&b);

    // A self-removing "one-shot" idle callback (FLTK's own
    // documented Fl::remove_idle() usage pattern) correctly removes
    // itself and doesn't get called again.
    int oneShotCalls;
    void oneShot()
    {
        oneShotCalls++;
        removeIdle(&oneShot);
    }

    addIdle(&oneShot);
    runIdle();
    assert(oneShotCalls == 1);
    assert(!hasIdle(&oneShot));
    runIdle(); // nothing left to call
    assert(oneShotCalls == 1);

    resetForTest();
}

unittest
{
    // addCheck()/hasCheck()/removeCheck()/runChecks() -- headless, same
    // "test the platform-independent half directly" precedent as the
    // addIdle() block just above.

    int calls;
    void inc() { calls++; }

    assert(!hasCheck(&inc));
    addCheck(&inc);
    assert(hasCheck(&inc));

    // Unlike runIdle(), a single runChecks() call fires every
    // registered check once (not one-per-call).
    runChecks();
    assert(calls == 1);
    runChecks();
    assert(calls == 2);

    removeCheck(&inc);
    assert(!hasCheck(&inc));
    runChecks(); // no-op now
    assert(calls == 2);

    // Newest-first call order, matching FLTK's documented "reverse
    // order that they were added".
    int[] order;
    void a() { order ~= 1; }
    void b() { order ~= 2; }
    addCheck(&a);
    addCheck(&b);
    runChecks();
    assert(order == [2, 1]);
    removeCheck(&a);
    removeCheck(&b);

    // Harmless to remove a check that was never registered (matching
    // FLTK's own doc comment).
    removeCheck(&inc);

    // A check callback that removes itself mid-runChecks() doesn't get
    // called again, and doesn't disrupt the rest of that same pass.
    int selfRemoveCalls;
    void selfRemove()
    {
        selfRemoveCalls++;
        removeCheck(&selfRemove);
    }

    order = [];
    addCheck(&a);
    addCheck(&selfRemove);
    runChecks();
    assert(selfRemoveCalls == 1);
    assert(order == [1]);
    assert(!hasCheck(&selfRemove));
    runChecks();
    assert(selfRemoveCalls == 1);
    assert(order == [1, 1]);
    removeCheck(&a);

    // A check callback that adds a new check mid-runChecks() doesn't
    // see it fire in the same pass.
    void late() { order ~= 99; }
    void addsLate()
    {
        addCheck(&late);
    }

    order = [];
    addCheck(&addsLate);
    runChecks();
    assert(order == []); // "late" registered, but not called yet
    runChecks();
    assert(order == [99]);
    removeCheck(&addsLate);
    removeCheck(&late);
}
