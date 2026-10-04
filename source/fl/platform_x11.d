/*
 * Minimal X11 platform glue for FLTK 1.5.0's window-creation/event-loop
 * layer (~/Repositories/fltk). Not a 1:1 port of a single FLTK
 * file -- FLTK spreads this across src/Fl_x.cxx (3246 lines,
 * itself free functions + globals, not classes -- the same
 * "namespace Fl as free functions" shape fl.core already uses),
 * Fl_Screen_Driver/Fl_Window_Driver (abstract base classes) and their
 * Fl_X11_Screen_Driver/Fl_X11_Window_Driver concrete subclasses.
 *
 * DELIBERATE ARCHITECTURE DEVIATION: FLTK's Screen_Driver/
 * Window_Driver/Graphics_Driver class hierarchy exists to support
 * multiple platforms polymorphically. With only X11 targeted so far,
 * that abstraction has no second implementation to justify it yet, so
 * this is a concrete, non-virtual module instead -- matching the
 * structural-fidelity reasoning CLAUDE.md already uses for `fl.core`
 * (free functions + module state is a closer match for a single
 * implementation than a wrapper class). If/when a Wayland or Windows
 * driver is added, factor out a real driver interface *then* -- don't
 * speculatively build it now.
 *
 * SCOPE: opens a window, maps it, keeps it alive via the
 * event loop (see run()'s own doc comment for the select()-based wait,
 * folding in fl.core's timer queue), reacts to window-manager resizes,
 * and closes
 * cleanly on the window manager's close button (WM_DELETE_WINDOW).
 * WM_NORMAL_HINTS (size-range/aspect/increment, see sendSizeHints())
 * is negotiated, and so are cursor shapes (see setCursor())
 * -- most of them; a few still need a custom pixmap cursor FLTK
 * itself only reaches via a separate, unported image-cursor path (see
 * that function's doc comment). Fullscreen mode (see fullscreenOn()/
 * fullscreenOff()) is negotiated too, EWMH-only. Real subwindows:
 * `createWindow()` creates a real child X window (parented to the
 * immediate window ancestor's own xid, a reduced `ExposureMask`-only
 * event mask, no WM chatter at all -- WM_PROTOCOLS/size-hints/motif-
 * hints/label/transient-for/modal are all skipped, matching FLTK's
 * own blanket `!win->parent()` gate around that whole block) when its
 * immediate window ancestor already has a real xid, or just marks it
 * logically visible and defers real creation otherwise (recreated later
 * via `Window.handle()`'s own `Event.show` case, once the ancestor's own
 * `show()` cascades that event down through the widget tree).
 * `destroyWindow()` recursively destroys (not merely unmaps -- see
 * `Window.handle()`'s own doc comment for why) any subwindows nested
 * inside a window being destroyed, before destroying that window's own
 * xid, matching FLTK's `Fl_Window_Driver::hide_common()`. Deliberately
 * NOT ported for subwindows either (matching FLTK's own X11 driver,
 * which has no code path for this at all): application-initiated
 * resize/move of an *already-created* subwindow doesn't move/resize its
 * real X child window -- see `PORTING.md`'s row for the full note; this
 * isn't a corner cut relative to FLTK, FLTK's own X11 driver has
 * no `XMoveResizeWindow()` call anywhere either.
 *
 * Icons (`setIcons()`/`_NET_WM_ICON`), application-initiated
 * top-level window moves/resizes (`fl.window`'s `resize()`, including
 * the `resize_bug_fix`-equivalent echo-prevention guard it needs,
 * `resizeBugFix_`), the clipboard, multi-fd multiplexing
 * (`Fl::add_fd()`-style), multi-monitor/Xinerama geometry, drag-and-drop
 * (real XDND, see `PORTING.md`'s `FL/x.H` row), the Motif
 * `_MOTIF_WM_HINTS` border/decoration property, WM_HINTS input-focus
 * negotiation (`createWindow()`'s own `InputHint`/`XSetWMHints()`
 * call), and the `Fl_Window::iconize()`-driven WM_HINTS `StateHint`/
 * `IconicState` request (`createWindow()`'s own `WM_HINTS` setup
 * consumes `fl.core.showNextWindowIconic_`, requesting `IconicState`
 * before the first map exactly like FLTK's `-iconic` handling) are all
 * real. Pixel drawing is fully wired
 * up on Expose (creates the shared GC
 * in openDisplay(), points fl.draw at the right window before calling
 * its draw() -- see fl.draw's initGraphics()/setDrawable()); fl.draw
 * itself draws every boxtype this port's `boxTable` has metrics
 * for, plus real text --
 * see that module's own row for the current, accurate picture.
 * WM_HINTS input-focus negotiation
 * still relies on
 * the window manager's own default focus *policy* (click-to-focus vs.
 * focus-follows-mouse, etc. -- that part genuinely is the WM's call,
 * matching FLTK), but this port doesn't leave the WM guessing
 * whether it should use `XSetInputFocus()` at all in the first place.
 *
 * Mouse (ButtonPress/ButtonRelease/MotionNotify/EnterNotify/
 * LeaveNotify, including the wheel via X11's button-4-7 convention) and
 * keyboard (KeyPress/KeyRelease) events are translated into
 * fl.core's event-state globals and dispatched via fl.fl.core.handle()
 * -- see translateState()'s doc comment for the modifier-bit mapping.
 * Double/triple-click detection is ported (setEventXY()/
 * checkdouble(), from set_event_xy()/checkdouble() in Fl_x.cxx) --
 * fl.core's eventClicks() increments on repeated same-button presses
 * within 3px/1000ms of each other. Keyboard autorepeat detection is
 * ported too (see the KeyPress/KeyRelease case's own doc comment) --
 * holding a key produces a stream of FL_KEYDOWN only, not an
 * FL_KEYDOWN/FL_KEYUP pair per repeat. FocusIn/FocusOut ->
 * FL_FOCUS/FL_UNFOCUS translation is ported too (see those cases'
 * own doc comments) -- keyboard focus follows the window manager
 * (alt-tab, focus-follows-mouse, etc.), not just clicks. Side mouse
 * buttons (X button 8/9 -> FL_BUTTON4/FL_BUTTON5, see the ButtonPress/
 * ButtonRelease cases and xbuttonState_) and NumLock/keypad keysym
 * remapping (see the KeyPress/KeyRelease case) are both
 * confirmed against real hardware (a Logitech MX
 * Master 3S for side buttons, a full-size keyboard's numpad for
 * NumLock/keypad -- see smoke-tests/side_buttons.d and
 * smoke-tests/keypad.d). The MX Master 3S's third side button (a gesture
 * button, delivered by X as button number 10, not 8/9) produces no
 * event at all -- expected, not a bug, since this driver (matching
 * FLTK) only ever remaps X button numbers 8/9; any other button
 * number falls through to the ButtonPress/ButtonRelease "unrecognized
 * button number, ignore" case. Dead-key/compose input is real
 * (see openDisplay()'s XOpenIM()/
 * XCreateIC() and the KeyPress case's Xutf8LookupString() use).
 *
 * Linux/X11 only, matching this port's current primary target; the
 * whole module is inert (empty) on other platforms.
 *
 * NO `unittest` BLOCKS HERE, unlike every other module in this port:
 * everything here needs a live X server connection (`dub test` must
 * keep working headlessly/in CI without one). Verified instead by
 * hand with a standalone smoke-test program (create a Window, call
 * show(), call fl.fl.core.run()) run against a real X display.
 */
module fl.platform_x11;

version (linux):

import core.stdc.config : c_ulong, c_long;
import core.sys.posix.unistd : getpid;
import core.time : Duration;

import fl.xlib;
import fl.xcursor;
import fl.xfixes;
import fl.xshape;
import fl.window : FlWindow = Window, resizeBugFix_;
import fl.double_window : doubleWindowTypeTag;
import fl.overlay_window : OverlayWindow;
import glWindow = fl.gl_window;
import fl.gl_window : GlWindow;
import fl.image : RGBImage;
import fl.bmp_image : BMPImage;
import fl.png_image : PngImage;
// Aliased, not a plain `import fl.pixmap : Pixmap;` -- this module
// already wildcard-imports fl.xlib, whose own `Pixmap` is the
// unrelated raw X11 XID typedef (same collision fl.core's `FlWindow`
// alias exists for, see that import's own comment).
import fl.pixmap : CursorPixmap = Pixmap;
import fl.widget : Widget;
import fl.filename : filenameName;
import fl.enumerations : Event, damageExpose, damageAll, damageOverlay, Damage, Keysym, EventState,
    button, stateShift, stateButton1, stateButton4, stateButton5, Beep,
    CursorShape = Cursor, home, left, up, right, down, pageUp, pageDown,
    end, insert, deleteKey, f, kp, kpLast, FdWhen, fdRead, fdWrite, fdExcept,
    Mode, modeDouble;
import fldraw = fl.draw;
import fl.core;

private
{
    Display* display_;
    string pendingDisplayName_; /// see setDisplayName()'s doc comment
    int screen_;

    /// The *default* visual/depth/colormap, queried once from the
    /// display in `openDisplay()` -- used only for `messageWindow_` and
    /// the single shared GC (`fldraw.initGraphics()`), both of which
    /// stay pinned to the default depth for the life of the process
    /// (see `openDisplay()`'s own comment on why). **Not** what real
    /// windows are created with -- `createWindow()` reads `fl_visual`/
    /// `fl_colormap` directly for that, matching FLTK's own
    /// `Fl_X::make_xid()` (see that function's doc comment).
    Visual* visual_;
    int depth_;
    Colormap colormap_;
    Atom wmProtocols_;
    Atom wmDeleteWindow_;
    Atom netWmState_;
    Atom netWmStateFullscreen_;
    Atom netWmFullscreenMonitors_;
    Atom netWmStateMaximizedVert_;
    Atom netWmStateMaximizedHorz_;
    Atom netWmStateModal_;
    Atom netWmStateHidden_;
    Atom netWorkarea_;
    Atom motifWmHints_;
    Atom clipboardAtom_;
    Atom targetsAtom_;
    Atom utf8StringAtom_;
    Atom netWmName_;
    Atom netWmIconName_;
    Atom netWmPid_;
    Atom netWmIcon_;
    Atom imageBmpAtom_;
    Atom imagePngAtom_;
    Atom timestampAtom_;
    Atom primaryTimestampAtom_;
    Atom clipboardTimestampAtom_;
    bool haveXfixes_;
    int xfixesEventBase_;
    int xfixesErrorBase_;

    /// The XDND protocol's own atoms (`fl_Xdnd*`/`fl_XaUtf8String`-
    /// adjacent set in `Fl_x.cxx`) -- registered in `openDisplay()`
    /// alongside every other atom above. See `dnd()`'s own doc comment
    /// for the overall mechanism.
    Atom xdndAware_;
    Atom xdndSelection_;
    Atom xdndEnter_;
    Atom xdndTypeList_;
    Atom xdndPosition_;
    Atom xdndLeave_;
    Atom xdndDrop_;
    Atom xdndStatus_;
    Atom xdndActionCopy_;
    Atom xdndFinished_;
    Atom xdndUriList_;

    /// Per-drop state for whichever XDND drag is currently landing on
    /// (one of) our windows -- the direct equivalents of FLTK's own
    /// file-scope `fl_dnd_source_window`/`fl_dnd_source_types`/
    /// `fl_dnd_type`/`fl_dnd_source_action`/`fl_dnd_action` (`Fl_x.cxx`).
    /// Like FLTK, there's only ever one in flight at a time (a
    /// second `XdndEnter` simply overwrites these before the first drop
    /// completes -- not reentrant, matching FLTK's own single-slot
    /// design).
    Window dndSourceWindow_;
    Atom[] dndSourceTypes_;
    Atom dndType_;
    Atom dndSourceAction_;
    Atom dndAction_;

    /// A tiny (1x1, never mapped) window that exists purely to hold
    /// selection ownership and act as the requestor for our own
    /// XConvertSelection() calls -- the direct equivalent of FLTK's
    /// `fl_message_window` (Fl_x.cxx). Selection ownership has to belong
    /// to *some* real X window; this port has no other window that's
    /// guaranteed to always exist (top-level windows come and go), so a
    /// dedicated one is created once, at display-open time, and lives
    /// for the life of the connection.
    Window messageWindow_;

    /// Linked list of currently-mapped top-level windows; the direct
    /// equivalent of FLTK's `Fl_X::first` (Fl_x.cxx), including
    /// its role as Fl::run()'s loop condition -- see run() below.
    struct WindowRecord
    {
        Window xid;
        FlWindow widget;
        WindowRecord* next;

        // Accumulated damage rectangle since the last flushDamage() --
        // the direct but
        // deliberately simplified equivalent of FLTK's real
        // Fl_X::region (a general, possibly-non-rectangular X11
        // Region built via XCreateRegion()/XUnionRectWithRegion()).
        // This port only ever needs the *bounding box* of everything
        // damaged since the last flush -- an over-inclusive clip never
        // produces wrong pixels (draw() is idempotent), it can only
        // waste a little work redrawing some already-correct pixels
        // between two disjoint damaged areas, which is rare in
        // practice and not worth a full multi-rectangle Region/
        // XSetClipRectangles(n>1) implementation for -- matching this
        // module's own established "simpler rectangle stack, exactly
        // as capable for every case this port exercises" precedent
        // (see fl.draw's clip-stack section comment).
        bool hasDamageRegion;
        int damageX, damageY, damageW, damageH;

        // Set by clearDamageRegion() (a whole-window damage() call --
        // see that function's doc comment) and cleared once
        // flushDamage() actually repaints and clears the widget's
        // damage. Needed to distinguish "nothing damaged yet" from
        // "whole window damaged, no rectangle needed" -- both look like
        // `hasDamageRegion == false`, but FLTK's own
        // `Fl_Widget::damage(uchar,X,Y,W,H)` tells them apart via
        // `if (wi->damage())` (the widget's own already-set damage
        // bits, which survive a whole-window damage() call): when that
        // check is true, it takes the "merge with existing region"
        // branch, and since a whole-window damage() call already nulled
        // `Fl_X::region`, `if (i->region)` guards the merge into a no-op
        // -- the region stays null (unclipped) rather than being
        // replaced with the new, narrower rectangle. Without this flag,
        // accumulateDamage() below couldn't tell the two apart and
        // would wrongly start a fresh, narrow rectangle for any partial
        // damage() call arriving after a whole-window one in the same
        // flush cycle (e.g. a button's own small focus/unfocus repaint
        // landing right after a Fl_Wizard page switch's whole-window
        // redraw) -- silently clipping the next flush down to that
        // small rectangle and leaving everything else undrawn.
        bool fullRepaintPending;

        // Set true when this window is mapped, cleared on its first
        // real Expose event -- backs waitForExpose() below (`Fl_Window::
        // wait_for_expose()`/`Fl_Window_Driver::wait_for_expose_value`,
        // `src/Fl_Window_Driver.cxx`).
        bool waitingForExpose = true;

        // Real double-buffering (fl.double_window's own row, PORTING.md)
        // -- an off-screen Pixmap flushDamage() draws a
        // DoubleWindow into before blitting it onto the real window. `0`
        // means "not yet allocated" (a plain Window never allocates
        // one at all); offscreenW/H record the size it was last
        // allocated at, so flushDamage() can detect a resize and
        // reallocate -- matching FLTK's own Fl_Double_Window::
        // resize() tearing down other_xid, just checked lazily on the
        // next flush instead of eagerly on the ConfigureNotify itself
        // (the widget's own w()/h() are already current by the time
        // flushDamage() runs, since it only ever runs after every
        // queued X event -- including the ConfigureNotify that resized
        // it -- has been drained, so there's no correctness difference,
        // just simpler: one check, in one place, instead of a second
        // hook on every resize path).
        fl.xlib.Pixmap offscreen;
        int offscreenW, offscreenH;
    }

    WindowRecord* first_;

    /// Click-tracking state for setEventXY()/checkdouble() below --
    /// direct equivalents of FLTK's file-scope statics `px`/`py`/
    /// `ptime` (Fl_x.cxx). `lastClickKeysym_` stands in for the same
    /// file's `Fl::e_is_click` doing double duty as both a bool ("is a
    /// click pending") and the keysym of the button that started it;
    /// this port keeps fl.core's `eIsClick_` a plain bool (matching its
    /// public bool eventIsClick() contract) and holds the keysym here
    /// instead, privately, since nothing outside this X11-specific
    /// algorithm ever needs it -- same "prefer the stronger D-side type
    /// when nothing is lost by it" reasoning CLAUDE.md documents
    /// elsewhere in this port.
    int px_, py_;
    Time ptime_;
    Time lastEventTime_;
    Keysym lastClickKeysym_;

    /// Held-state of the side mouse buttons (X button 8/9, remapped to
    /// FL_BUTTON4/FL_BUTTON5) -- the direct equivalent of FLTK's
    /// file-scope `xbutton_state` (Fl_x.cxx). Needed because Xlib's own
    /// `xbutton.state`/`xmotion.state`/etc. fields only carry held-state
    /// bits for buttons 1-3 and the wheel (4/5 in X's numbering, not
    /// FLTK's) -- nothing past that, so this port has to remember the
    /// side buttons' held state itself across events, the same way
    /// FLTK does, and fold it into every event's eState_ (see
    /// setEventXY()) since translateState() alone can't recover it.
    EventState xbuttonState_;

    /// Real input-method state (core-roadmap item 9) -- the direct
    /// equivalents of FLTK's file-scope `Fl_X11_Screen_Driver::
    /// xim_im`/`xim_ic`/`xim_win` (`Fl_x.cxx`). `ximIc_` is recreated
    /// (not just refocused) whenever the focused *window* changes, per
    /// FLTK's own "brute force" comment in `xim_activate()` -- see
    /// that function's own doc comment in this module.
    XIM ximIm_;
    XIC ximIc_;
    Window ximWin_;

    /// "Over the spot" IME preedit-positioning state -- the direct
    /// equivalents of FLTK's file-scope `Fl_X11_Screen_Driver::
    /// fl_is_over_the_spot`/`fl_spot`/`fl_spotf`/`fl_spots` (`Fl_x.cxx`/
    /// `Fl_X11_Screen_Driver.H`). `overTheSpot_` records whether
    /// `newIc()` actually negotiated `XIMPreeditPosition` with the
    /// input method (see that function); `spot_`/`spotFont_`/
    /// `spotSize_` cache the last position `setSpot()` was given, so
    /// `ximActivate()` can re-assert it on a freshly recreated IC
    /// (which otherwise starts back at an all-zero spot), and so
    /// `setSpot()` itself can skip redundant `XSetICValues()` calls
    /// when nothing actually changed, matching FLTK exactly.
    bool overTheSpot_;
    XRectangle spot_;
    int spotFont_ = -1;
    int spotSize_ = -1;
    XFontSet ximFontSet_;

    /// Reused across KeyPress events (grown, never shrunk) rather than
    /// allocated fresh each call -- matches FLTK's own persistent
    /// file-scope `static char *kp_buffer` (Fl_x.cxx), just as a plain
    /// D dynamic array instead of a hand-managed `malloc()`/`realloc()`
    /// pointer (the GC makes that bookkeeping moot, same reasoning
    /// already applied to the timer queue and `fl.core.fdEntries()`).
    char[] ximBuffer_;
}

/**
 * The `XVisualInfo*`/`Colormap` real, live X windows are created with --
 * ported from FLTK's `fl_visual`/`fl_colormap` (`FL/x11.H`), plain
 * process-global state there too, hence `__gshared` here (D module
 * variables are thread-local by default, unlike a C++ global -- see
 * CLAUDE.md's "D module-level variables are thread-local by default"
 * note). Populated to match the display's default visual/colormap as
 * soon as `openDisplay()` runs (mirroring FLTK's own `open_display_
 * ()`, `Fl_x.cxx`), and updated in place by `setVisual()` below on the
 * rare occasion a caller asks for something the default doesn't
 * already satisfy.
 *
 * A caller may also reassign these directly, matching FLTK's
 * plain-global architecture exactly -- `samples/test/image.d`/
 * `tiled_image.d`'s `-v <visid>` diagnostic flag does exactly this, the
 * same way `test/image.cxx`'s original does with its own raw
 * `fl_visual = XGetVisualInfo(...)` assignment.
 *
 * **Real window creation honors these**: `createWindow()` reads these two globals *directly*
 * (not a separately-cached copy) every time it creates a window's real
 * X resource, matching FLTK's own `Fl_X::make_xid(pWindow,
 * fl_visual, fl_colormap)` exactly -- so whichever visual/colormap
 * these currently point at (whether set by `setVisual()` or a raw
 * direct reassignment, like `image.d`'s `-v` flag above) is what any
 * window created *from then on* actually gets. `fl.draw`'s
 * pixel-packing state (`fl_color()`/`fl_xpixel()`) picks these up the
 * same way, lazily, via `ensureVisualFigured()`'s one-time trigger on
 * first real window creation -- see that function's own doc comment
 * for why this matches FLTK's own lazy `figure_out_visual()`
 * design. The shared GC itself is the one piece that stays fixed at
 * the *default* visual's depth regardless (see `openDisplay()`'s own
 * comment on why, and `createWindow()`'s doc comment for the resulting
 * limitation) -- matching FLTK's own single never-recreated
 * `fl_gc`, not a gap this port introduces uniquely.
 */
__gshared XVisualInfo* fl_visual;
/// ditto
__gshared Colormap fl_colormap;

/**
 * Sets which X display `openDisplay()` connects to (the `DISPLAY`-
 * string-shaped name `XOpenDisplay()` takes, e.g. `":0"`/`"host:0.1"`)
 * -- backs `fl.core.arg()`'s `-display` switch (`Fl::screen_driver()->
 * display(v)`, `Fl_X11_Screen_Driver::display(const char*)`). A no-op
 * once the display is already open (matching FLTK: the connection
 * can't be changed after the fact), and only takes effect on the next
 * `openDisplay()` call otherwise -- callers wanting `-display` to
 * actually redirect the connection must call this (via `fl.core.args()`)
 * before anything else opens the display.
 */
void setDisplayName(string name)
{
    if (display_ is null) pendingDisplayName_ = name;
}

/// The current X11 `Display*`, or `null` if `openDisplay()` hasn't run
/// yet. Ported from `fl_x11_display()` (`FL/x11.H`) -- a program can
/// call this (after opening the display) to confirm it's actually
/// running on the X11 backend, matching FLTK's own doc note ("that
/// is, as long as x11Display() returns NULL" for the Wayland case).
/// Always non-null once any window/`openDisplay()` call has run, since
/// this port has no other Linux backend to fall back to.
Display* x11Display() { return display_; }

/// The current default X11 screen number, or `0` if `openDisplay()`
/// hasn't run yet -- ported from `fl_screen` (`FL/x11.H`), same
/// call-when-you-need-it convention as `fl_x11_display()` just above.
int x11Screen() { return screen_; }

/**
 * Blocks until win has received its first real `Expose` event since
 * being shown (or returns immediately if it already has, or isn't
 * shown() at all). Ported from `Fl_Window::wait_for_expose()`
 * (`Fl_Window_Driver::wait_for_expose()`, `src/Fl_Window_Driver.cxx`):
 * `while (!i || wait_for_expose_value) Fl::wait();` -- `!i` (no real
 * X record yet) can't happen in this port's own call shape (`win.
 * shown()` already guarantees a `WindowRecord` exists), so this is
 * just the `wait_for_expose_value` loop. Backs `fl.window.Window.
 * waitForExpose()`.
 */
package(fl) void waitForExpose(FlWindow win)
{
    if (!win.shown()) return;
    for (auto rec = first_; rec !is null; rec = rec.next)
    {
        if (rec.widget !is win) continue;
        while (rec.waitingForExpose) fl.core.wait();
        return;
    }
}

/// Ported from `fl_wl_display()` (`FL/wayland.H`) -- a permanent `null`
/// stub, not a placeholder pending completion: this port has no
/// Wayland driver at all yet (see `PORTING.md`'s platform-scope notes),
/// so there's never a real `wl_display*` to return. Exists purely for
/// call-site compatibility with programs that check both
/// `fl_x11_display()`/`fl_wl_display()` to report which backend is
/// active (`test/fltk-versions.cxx`'s own pattern).
void* wlDisplay() { return null; }

/**
 * Opens the X11 connection and queries the default screen/visual/
 * colormap. Lazy and idempotent, matching FLTK's
 * Fl_Screen_Driver::open_display()'s `been_here` guard. Called
 * automatically by createWindow(); exposed in case callers want to
 * force it earlier.
 */
void openDisplay()
{
    if (display_ !is null) return;

    // Real input-method support (core-roadmap item 9) needs the
    // process's locale set from the environment *before* opening the
    // display/input method -- matching FLTK's own
    // `Fl_X11_Screen_Driver::open_display_platform()` doing exactly
    // this pair of calls first, unconditionally, regardless of whether
    // XIM ends up available at all.
    {
        import core.stdc.locale : setlocale, LC_CTYPE;
        setlocale(LC_CTYPE, "");
    }
    XSetLocaleModifiers("");

    import std.string : toStringz;
    display_ = XOpenDisplay(pendingDisplayName_.length ? pendingDisplayName_.toStringz : null);
    if (display_ is null)
    {
        // Ported from `Fl_X11_Screen_Driver::open_display_platform()`'s
        // own `Fl::fatal("Can't open display: %s", ...)` call, via
        // `fl.core.fatal()`/`setAbort()`, throwing a `fl.core.FatalError`
        // by default rather than
        // FLTK's own `exit(1)` -- see `fatal()`'s own doc comment
        // for why.
        fatal("fl.platform_x11: cannot open X display");
    }

    installErrorHandler();

    // Debug aid, kept permanently (opt-in, zero cost unless set): set
    // `FLDTK_X_SYNC=1` in the environment to force every X request to
    // round-trip synchronously, so a BadXxx error surfaces immediately,
    // in the same stack frame that issued the offending call, instead
    // of asynchronously on some later, unrelated round-trip. Real X
    // errors are reported async by default (the client only learns
    // about one whenever it next happens to block on a reply for an
    // unrelated request), which can show a misleading backtrace
    // pointing at some innocent bystander (e.g. `flushDamage()`,
    // `XftFontOpenName()`) whose own sync round-trip just
    // happened to be what flushed out an old buffered error. Reach for
    // this first for any
    // "X error, but the backtrace points somewhere unrelated"
    // report.
    import std.process : environment;
    if (environment.get("FLDTK_X_SYNC") !is null)
        XSynchronize(display_, True);

    wmProtocols_ = XInternAtom(display_, "WM_PROTOCOLS", False);
    wmDeleteWindow_ = XInternAtom(display_, "WM_DELETE_WINDOW", False);
    netWmState_ = XInternAtom(display_, "_NET_WM_STATE", False);
    netWmStateFullscreen_ = XInternAtom(display_, "_NET_WM_STATE_FULLSCREEN", False);
    netWmFullscreenMonitors_ = XInternAtom(display_, "_NET_WM_FULLSCREEN_MONITORS", False);
    netWmStateMaximizedVert_ = XInternAtom(display_, "_NET_WM_STATE_MAXIMIZED_VERT", False);
    netWmStateMaximizedHorz_ = XInternAtom(display_, "_NET_WM_STATE_MAXIMIZED_HORZ", False);
    netWmStateModal_ = XInternAtom(display_, "_NET_WM_STATE_MODAL", False);
    netWmStateHidden_ = XInternAtom(display_, "_NET_WM_STATE_HIDDEN", False);
    netWorkarea_ = XInternAtom(display_, "_NET_WORKAREA", False);
    motifWmHints_ = XInternAtom(display_, "_MOTIF_WM_HINTS", False);
    clipboardAtom_ = XInternAtom(display_, "CLIPBOARD", False);
    targetsAtom_ = XInternAtom(display_, "TARGETS", False);
    utf8StringAtom_ = XInternAtom(display_, "UTF8_STRING", False);
    imageBmpAtom_ = XInternAtom(display_, "image/bmp", False);
    imagePngAtom_ = XInternAtom(display_, "image/png", False);
    timestampAtom_ = XInternAtom(display_, "TIMESTAMP", False);
    primaryTimestampAtom_ = XInternAtom(display_, "PRIMARY_TIMESTAMP", False);
    clipboardTimestampAtom_ = XInternAtom(display_, "CLIPBOARD_TIMESTAMP", False);
    netWmName_ = XInternAtom(display_, "_NET_WM_NAME", False);
    netWmIconName_ = XInternAtom(display_, "_NET_WM_ICON_NAME", False);
    netWmPid_ = XInternAtom(display_, "_NET_WM_PID", False);
    netWmIcon_ = XInternAtom(display_, "_NET_WM_ICON", False);

    // XDND (ported from open_display_()'s identical block, Fl_x.cxx).
    xdndAware_ = XInternAtom(display_, "XdndAware", False);
    xdndSelection_ = XInternAtom(display_, "XdndSelection", False);
    xdndEnter_ = XInternAtom(display_, "XdndEnter", False);
    xdndTypeList_ = XInternAtom(display_, "XdndTypeList", False);
    xdndPosition_ = XInternAtom(display_, "XdndPosition", False);
    xdndLeave_ = XInternAtom(display_, "XdndLeave", False);
    xdndDrop_ = XInternAtom(display_, "XdndDrop", False);
    xdndStatus_ = XInternAtom(display_, "XdndStatus", False);
    xdndActionCopy_ = XInternAtom(display_, "XdndActionCopy", False);
    xdndFinished_ = XInternAtom(display_, "XdndFinished", False);
    xdndUriList_ = XInternAtom(display_, "text/uri-list", False);

    // Ported from Fl_X11_Screen_Driver::open_display_platform()'s own
    // `XFixesQueryExtension()` probe -- when present (true on every
    // modern desktop; this port's own reference comparison build has
    // it), clipboard-change notification is instant and event-driven
    // (see createWindow()'s `XFixesSelectSelectionInput()` calls and
    // `processNextEvent()`'s `XFixesSelectionNotify` check) instead of
    // falling back to `pollClipboardOwner()`'s 0.5s polling -- see
    // `clipboardNotifyChange()`'s own doc comment for why polling alone
    // is real but *visibly* slower than what a live side-by-side
    // comparison against FLTK expects.
    haveXfixes_ = XFixesQueryExtension(display_, &xfixesEventBase_, &xfixesErrorBase_) != 0;

    screen_ = XDefaultScreen(display_);
    visual_ = XDefaultVisual(display_, screen_);
    depth_ = XDefaultDepth(display_, screen_);
    colormap_ = XDefaultColormap(display_, screen_);

    // Construct an XVisualInfo matching the default Visual and expose
    // it/the default colormap as fl_visual/fl_colormap (see that
    // field's own doc comment) -- ported from open_display_()'s
    // identical `XVisualIDFromVisual()`+`XGetVisualInfo(VisualIDMask)`
    // construction (Fl_x.cxx).
    {
        XVisualInfo templt;
        templt.visualid = XVisualIDFromVisual(visual_);
        int numVisuals;
        fl_visual = XGetVisualInfo(display_, VisualIDMask, &templt, &numVisuals);
        fl_colormap = colormap_;
    }

    // Never mapped -- see the field's own doc comment for why this
    // exists at all. Always created against the *default* visual/depth
    // (matching FLTK's own `fl_message_window = XCreateSimpleWindow
    // (d, RootWindow(d,fl_screen), 0,0,1,1,0, 0, 0)`, `CopyFromParent`
    // depth/visual, called before `fl_visual`/`fl_colormap` are even
    // set) -- selection ownership doesn't depend on window depth, so
    // there's no reason for this to track whatever `fl_visual` might
    // later become.
    messageWindow_ = XCreateWindow(display_, XRootWindow(display_, screen_),
        0, 0, 1, 1, 0, depth_, InputOutput, visual_, 0, null);

    // One shared GC for every window, matching FLTK
    // (Fl_X11_Screen_Driver::open_display_platform() creates it once
    // against the root window's own default depth and never recreates
    // it, even if `Fl::visual()`/a raw `fl_visual` reassignment later
    // selects a different visual -- see `createWindow()`'s own doc
    // comment on why this is a real, FLTK-shared limitation rather
    // than something this port needs to solve: on virtually every
    // modern X server every TrueColor visual shares the same depth
    // regardless of visual ID, so this never actually matters in
    // practice).
    GC gc = XCreateGC(display_, XRootWindow(display_, screen_), 0, null);

    // Disabled deliberately: fl.draw.fl_scroll() uses this GC's
    // XCopyArea() to blit-scroll a Scroll widget's contents, and
    // Xlib's default (enabled) would make the server queue
    // GraphicsExpose/NoExpose events afterward for recovering pixels
    // that were themselves obscured during the copy -- a real but rare
    // edge case FLTK's own driver handles with a synchronous
    // XWindowEvent() wait right after each XCopyArea() call.
    // Deliberately not ported (see fl_scroll()'s own doc comment): a
    // blocking wait for a specific event type from inside a widget's
    // draw() call is delicate to get right against this port's own
    // single XNextEvent() loop, for a benefit that only matters when
    // another window overlapped the scrolled area at the moment of the
    // copy. Disabling exposures outright means the server never sends
    // those events at all, rather than this port silently dropping
    // ones it doesn't handle in processNextEvent()'s `default: break;`.
    XSetGraphicsExposures(display_, gc, False);

    fldraw.initGraphics(display_, gc, screen_, visual_, colormap_);

    initXim();

    // GUI scaling startup -- matches
    // FLTK's own call order exactly (`Fl_Screen_Driver::
    // open_display()`: `use_startup_scale_factor()` first, *then* the
    // Ctrl-+/Ctrl--/Ctrl-0 handler gets registered), right after
    // `open_display_platform()` returns.
    useStartupScaleFactor();
    fl.core.installScaleHandler();
}

/// The `Xft.dpi` X resource value, cached after the first successful
/// read so a later call is a no-op -- ported from `Fl_X11_Screen_
/// Driver::current_xft_dpi`/`desktop_scale_factor()`. `0` means "not
/// read yet" (matching FLTK's own `== 0.` guard); `Xft.dpi` itself
/// is never legitimately `0`, so this doubles as a valid sentinel.
private float currentXftDpi_ = 0.0f;

/**
 * Detects the desktop's own display scale from the `Xft.dpi` X
 * resource and seeds `fl.core.screenScale()` with it -- ported from
 * `Fl_X11_Screen_Driver::desktop_scale_factor()`. `factor = dpi/96`,
 * snapped to exactly `1` or `2` near those values and clamped to `10`
 * max, matching FLTK's own comment verbatim ("checks to prevent
 * potential crash (factor <= 0) or very large factors and round
 * nearly 1 or nearly 2 values (issue #1138)"). A no-op if the
 * resource isn't set at all (common on a plain Xorg session with no
 * desktop environment setting it) or fails to parse as a number.
 */
private void desktopScaleFactor()
{
    if (currentXftDpi_ != 0.0f) return;

    const(char)* s = XGetDefault(display_, "Xft", "dpi");
    if (s is null) return;

    import std.string : fromStringz;
    import std.conv : parse, ConvException;

    auto str = fromStringz(s);
    try
        currentXftDpi_ = parse!float(str);
    catch (ConvException)
        return;

    float factor = currentXftDpi_ / 96.0f;
    if (factor < 1.1f) factor = 1;
    else if (factor > 1.8f && factor < 2.2f) factor = 2;
    else if (factor > 10.0f) factor = 10.0f;

    foreach (i; 0 .. screenCount())
        fl.core.screenScale(i, factor);
}

/**
 * Applies the desktop's detected scale (`desktopScaleFactor()`), folds
 * in the `FLTK_SCALING_FACTOR` environment variable if set, then
 * overrides the result with the user's own last interactively-chosen
 * scale if one was ever saved (`fl.core.loadPersistedScaleFactor()` --
 * a deliberate fldtk-only addition, see that function's own doc
 * comment) -- ported from `Fl_Screen_Driver::use_startup_scale_
 * factor()`. FLTK's own version branches on `rescalable() ==
 * SYSTEMWIDE_APP_SCALING` to decide whether the env var multiplies
 * screen 0's factor and broadcasts the result to every screen, or
 * multiplies each screen's own factor independently -- on X11 this
 * always takes the systemwide branch, matching real FLTK exactly:
 * X11 has no per-monitor startup DPI source at all (`Xft.dpi` is one
 * systemwide X resource, see `desktopScaleFactor()`'s own doc comment),
 * so `screenScale_` (a real per-screen array) legitimately holds the
 * *same* value for every screen at this
 * point regardless -- reading screen 0 below as "the native scale" is
 * representative of every screen, not a simplification. (Windows is
 * different: `fl.platform_win32.seedScaleFromPrimaryMonitor()` really
 * does query each monitor's own independent DPI at startup, matching
 * FLTK's own per-monitor `Fl_WinAPI_Screen_Driver::desktop_scale_
 * factor()` loop -- this function's own broadcast-to-every-screen
 * `foreach` below only runs on the *persisted*-override path, and only
 * applies on Linux.)
 *
 * **`fl.core.seedBaseScale()` is called with the *native* (desktop +
 * env var) value, deliberately before the persisted override below is
 * applied**: without this ordering,
 * `fl.core.baseScale()`'s own lazy-capture-on-first-press
 * fallback would seed itself from whatever `screenScale()` already is
 * by the time the user's first Ctrl-+/Ctrl--/Ctrl-0 press needs it,
 * which (once persistence exists) can be a *previously chosen*
 * absolute scale rather than the desktop's actual native default. That
 * would silently change what "100%" means for the indicator/reset math, so
 * a genuinely-absolute 133% scale (one zoom-out step down from a
 * persisted 150%) would display as "90%" instead of "133%". Seeding the
 * base explicitly, before the override, keeps the indicator's
 * percentage anchored to the true native default regardless of any
 * persisted preference -- see `fl.core.seedBaseScale()`'s own doc
 * comment for the full writeup.
 */
private void useStartupScaleFactor()
{
    desktopScaleFactor();

    float nativeScale = fl.core.screenScale(0);

    import std.process : environment;
    import std.conv : parse, ConvException;
    import std.math : isNaN;

    float envFactor = 1.0f;
    auto str = environment.get("FLTK_SCALING_FACTOR");
    if (str !is null)
    {
        try
            envFactor = parse!float(str);
        catch (ConvException)
            envFactor = 1.0f;
    }

    foreach (i; 0 .. screenCount())
        fl.core.seedBaseScale(i, nativeScale * envFactor);

    float persisted = fl.core.loadPersistedScaleFactor();
    float effective = (isNaN(persisted) ? nativeScale : persisted) * envFactor;

    foreach (i; 0 .. screenCount())
        fl.core.screenScale(i, effective);

    // Seeds the live drawing scale too, not just the per-screen table --
    // `fl.core.currentScale()` otherwise stays at its own hardcoded `1.0`
    // default until the first window's own `make_current()`-equivalent
    // hook runs, which is too late for any measurement or `ImageSurface`
    // built *before* the first window is shown() (a real, plausible
    // pattern -- e.g. pre-rendering a fixed-size icon at the correct
    // device-pixel resolution before the main window exists).
    // `effective` (screen 0's value, which every screen shares at this
    // point on X11 -- see this function's own doc comment) is the best
    // available guess for "the scale," absent any specific window yet.
    fl.core.currentScale(effective);
}

/// One-time latch for `ensureVisualFigured()` below.
private bool visualFigured_;

/**
 * Derives `fl.draw`'s pixel-packing mask/shift/bpp state
 * (`fl.draw.figureOutVisual()`) from whatever `fl_visual` currently
 * points at -- called once, from `createWindow()`, the first time any
 * real window is actually created. Mirrors FLTK's own
 * `figure_out_visual()` trigger exactly: a one-time `static uchar
 * beenhere`-guarded lazy computation (`Fl_Xlib_Graphics_Driver_
 * color.cxx`), first fired on the first real `fl_xpixel()` call rather
 * than eagerly at `openDisplay()`/`Fl::visual()` time. This port fires
 * it slightly earlier -- first `createWindow()` rather than first
 * `fl_xpixel()` -- since nothing in this port ever draws before a
 * window exists to draw into, so the two trigger points are
 * equivalent in practice, and pinning it to `createWindow()` avoids
 * threading a guard through the hot `fl_color()`/`fl_xpixel()` call
 * path itself.
 *
 * This avoids a "process-global-active-visual" sequencing
 * gap: a caller doing `Fl::visual(mode)` as the very first
 * statement of `main()` -- FLTK's own documented precondition --
 * needs it to affect drawn colors, so color-packing
 * state can't lock in eagerly against the *default* visual inside
 * `openDisplay()`, before `Fl::visual()`'s own comparison logic (which
 * itself triggers that same `openDisplay()` call, needing a live
 * connection to enumerate visuals) ever runs. Deferring the commit to
 * first-window-creation time instead means it naturally runs *after*
 * any `Fl::visual()` call a real `main()` would make before creating
 * its first window -- and, matching FLTK's own lazy-first-use
 * design exactly, it also transparently picks up a raw direct
 * `fl_visual = XGetVisualInfo(...)` reassignment (the pattern
 * `samples/test/image.d`/`tiled_image.d`'s `-v <visid>` diagnostic
 * flag uses, bypassing `setVisual()` entirely) with no special-casing
 * needed for that path either -- both routes update the same
 * `fl_visual`/`fl_colormap` globals this function reads.
 */
private void ensureVisualFigured()
{
    if (visualFigured_) return;
    visualFigured_ = true;
    fldraw.figureOutVisual(
        fl_visual !is null ? fl_visual.redMask : 0,
        fl_visual !is null ? fl_visual.greenMask : 0,
        fl_visual !is null ? fl_visual.blueMask : 0,
        fl_visual !is null ? fl_visual.depth : cast(uint) depth_);
}

/// Ported from `test_visual()` (`Fl_X11_Screen_Driver.cxx`, a file-scope
/// static there, `package(fl)` here for `setVisual()`'s own use). Only
/// FLTK's `#else` (non-`USE_COLORMAP`) branch is ported: that macro
/// is never defined in any build this port targets, matching
/// `fl.draw`'s existing "plain 8-8-8 TrueColor visual assumed"
/// simplification -- so `flags`' `modeIndex`/`modeRgb8` distinctions
/// collapse to the same simple class check every visual on a modern
/// TrueColor-only X server passes anyway.
package(fl) bool testVisual(ref XVisualInfo v, Mode flags)
{
    if (v.screen != screen_) return false;
    return v.c_class == StaticColor || v.c_class == TrueColor;
}

/**
 * Selects a visual capable of `flags` (`fl.enumerations.Mode`) --
 * ported from `Fl::visual(int)` (`src/Fl_visual.cxx`, which just
 * dispatches to `screen_driver()->visual(flags)`) +
 * `Fl_X11_Screen_Driver::visual(int)` (`Fl_X11_Screen_Driver.cxx`).
 * Real work in the only case that matters in practice: queries every
 * visual the X server offers via `XGetVisualInfo()` and keeps the
 * deepest one `testVisual()` accepts, updating `fl_visual`/
 * `fl_colormap` in place if it's better than the current default. On
 * virtually every modern X server (exactly one TrueColor visual on
 * offer) this immediately finds the already-active default already
 * satisfies the request and returns `true` without changing anything
 * -- matching FLTK's own early-out (`if (test_visual(*fl_visual,
 * flags)) return 1;`).
 *
 * **Real window creation honors this**: `createWindow()` reads `fl_visual`/
 * `fl_colormap` directly at the time each window is created (matching
 * FLTK's own `Fl_X::make_xid(pWindow, fl_visual, fl_colormap)`,
 * which likewise never caches a separate copy), so a `setVisual()`
 * call made before any window is created/shown takes effect on every
 * window created afterward -- matching FLTK's own documented
 * precondition, "this is only allowed before you call show() on any
 * windows." `fl.draw`'s color-packing state picks it up the same way,
 * via `ensureVisualFigured()`'s own one-time lazy trigger (see that
 * function's doc comment) -- no special-casing needed here for either.
 * `flags & modeDouble` still short-circuits to `false` first, matching
 * FLTK's own `if (flags & FL_DOUBLE) return 0;` (double-buffering
 * is a `DoubleWindow`/overlay concern, never a plain-visual one).
 */
bool setVisual(Mode flags)
{
    if (flags & modeDouble) return false;
    openDisplay();
    if (fl_visual !is null && testVisual(*fl_visual, flags)) return true;
    int num;
    XVisualInfo templt;
    XVisualInfo* visualList = XGetVisualInfo(display_, 0, &templt, &num);
    XVisualInfo* found;
    foreach (i; 0 .. num)
    {
        if (testVisual(visualList[i], flags)
            && (found is null || found.depth < visualList[i].depth))
            found = &visualList[i];
    }
    if (found is null)
    {
        XFree(visualList);
        return false;
    }
    fl_visual = found;
    fl_colormap = XCreateColormap(display_, XRootWindow(display_, screen_),
        fl_visual.visual, AllocNone);
    return true;
}

/**
 * Opens an input method connection and creates its (one, shared) input
 * context -- the direct equivalent of FLTK's `Fl_X11_Screen_Driver::
 * init_xim()` (`Fl_x.cxx`), called once from `openDisplay()`. The
 * actual style negotiation/IC creation is `newIc()`'s job (see its own
 * doc comment) -- this function just opens the input method connection
 * and cleans up if IC creation still fails even after that. A failed
 * `XOpenIM()`/`XCreateIC()` (no input method server reachable at all --
 * rare, but FLTK handles it gracefully rather than treating it as
 * fatal) just leaves `ximIm_`/`ximIc_` null; every consumer below
 * already checks for that and falls back to the plain, non-IME key
 * handling this port always had.
 */
private void initXim()
{
    ximIm_ = XOpenIM(display_, null, null, null);
    if (ximIm_ is null) return;

    newIc();
    if (ximIc_ is null)
    {
        XCloseIM(ximIm_);
        ximIm_ = null;
    }
}

/**
 * Negotiates the best preedit style the input method supports and
 * (re)creates the (one, shared) input context with it -- the direct
 * equivalent of FLTK's `Fl_X11_Screen_Driver::new_ic()`
 * (`Fl_x.cxx`), called from `initXim()` and every time `ximActivate()`
 * recreates the IC for a newly-focused window.
 *
 * **Real "over the spot" IME preedit positioning**, backing
 * `fl.text_display`/`fl.text_editor`'s
 * `setSpot()`/`has_marked_text()` (see those modules'
 * `PORTING.md` rows): queries `XGetIMValues(..., XNQueryInputStyle,
 * ...)` for the styles the input method actually supports and creates
 * the IC with `XIMPreeditPosition | XIMStatusNothing` when available,
 * letting `setSpot()` below position the input method's own floating
 * preedit window at the text cursor (useful for CJK/other IME users --
 * see ibus/fcitx). Simplified relative to FLTK: never tries
 * `XIMPreeditPosition | XIMStatusArea` (a separate on-screen
 * status/candidate-list area FLTK also negotiates first; this port
 * has no such area to offer a position for, and any input method
 * supporting `XIMStatusArea` also supports the plain `XIMStatusNothing`
 * variant this function already tries, so nothing is lost by skipping
 * straight to it). Falls back to `XIMPreeditNothing | XIMStatusNothing`
 * -- FLTK's own fallback too -- when `XIMPreeditPosition` isn't
 * supported at all, which is exactly this port's previous (and still
 * fully correct) behavior.
 *
 * The font set `XNFontSet` needs is created once and reused (matching
 * FLTK's own `static XFontSet fs`) -- input methods generally
 * require *some* font set in a preedit attribute list even though
 * nothing in this port ever draws with it (preedit rendering, under
 * this style, is the input method's own responsibility). Always
 * `"-misc-fixed-*"`, a generic fallback XLFD pattern -- matching
 * FLTK's own `USE_XFT || FLTK_USE_CAIRO` branch exactly (real
 * per-font XLFD lookup is skipped FLTK too under Xft/Cairo, the
 * same situation this port's own Xft-based text rendering is in).
 */
private void newIc()
{
    if (ximFontSet_ is null)
    {
        char** missingList;
        int missingCount;
        char* defString;
        ximFontSet_ = XCreateFontSet(display_, "-misc-fixed-*",
            &missingList, &missingCount, &defString);
        if (missingList) XFreeStringList(missingList);
    }

    auto preeditAttr = XVaCreateNestedList(0,
        XNSpotLocation, &spot_, XNFontSet, ximFontSet_, null);

    bool supportsPreeditPosition;
    XIMStyles* ximStyles;
    if (XGetIMValues(ximIm_, XNQueryInputStyle, &ximStyles, null) is null && ximStyles !is null)
    {
        foreach (i; 0 .. ximStyles.count_styles)
            if (ximStyles.supported_styles[i] == (XIMPreeditPosition | XIMStatusNothing))
                supportsPreeditPosition = true;
    }
    if (ximStyles !is null) XFree(cast(void*) ximStyles);

    ximIc_ = null;
    if (supportsPreeditPosition)
        ximIc_ = XCreateIC(ximIm_, XNInputStyle, XIMPreeditPosition | XIMStatusNothing,
            XNPreeditAttributes, preeditAttr, null);
    XFree(preeditAttr);

    overTheSpot_ = ximIc_ !is null;
    if (ximIc_ is null)
        ximIc_ = XCreateIC(ximIm_, XNInputStyle, XIMPreeditNothing | XIMStatusNothing, null);
}

/**
 * Re-points the (one, shared) input context at `xid` -- the direct
 * equivalent of FLTK's `Fl_X11_Screen_Driver::xim_activate()`
 * (`Fl_x.cxx`), called from `case FocusIn:` above. No-op if XIM never
 * opened successfully (`ximIm_ is null`).
 *
 * Recreates the IC from scratch (destroy + `newIc()` again) rather
 * than just re-pointing its focus/client-window attributes whenever
 * the focused *window* actually changed, matching FLTK's own
 * comment verbatim: "If the focused window has changed, then use the
 * brute force method of completely recreating the input context." A
 * plain `XSetICValues()` re-point (what this function does when the
 * window *hasn't* changed -- e.g. refocusing after a grab/modal dialog
 * closes) would be cheaper, but FLTK found some input methods
 * don't reliably notice a focus/client-window attribute change on an
 * existing IC, only a fresh `XCreateIC()`. Re-asserts the last known
 * spot position on every call, matching FLTK's own unconditional
 * `set_spot()` call at the end -- needed because a freshly recreated
 * IC otherwise starts back at an all-zero spot.
 */
private void ximActivate(Window xid)
{
    if (ximIm_ is null) return;

    if (ximWin_ != xid)
    {
        ximDeactivate();
        newIc();
        ximWin_ = xid;
        if (ximIc_ !is null)
            XSetICValues(ximIc_, XNFocusWindow, ximWin_, XNClientWindow, ximWin_, null);
    }

    setSpot(spotFont_, spotSize_, spot_.x, spot_.y, spot_.width, spot_.height);
}

/// Destroys the current input context, if any -- the direct equivalent
/// of FLTK's `Fl_X11_Screen_Driver::xim_deactivate()`.
private void ximDeactivate()
{
    if (ximIc_ is null) return;
    XDestroyIC(ximIc_);
    ximIc_ = null;
    ximWin_ = 0;
}

/**
 * Positions (or updates) the input method's own "over the spot"
 * preedit window near the text cursor -- the direct equivalent of
 * FLTK's `Fl_X11_Screen_Driver::set_spot()`
 * (`Fl_X11_Screen_Driver.cxx`), backing `fl.core.setSpot()`. A
 * no-op unless `newIc()` actually negotiated `XIMPreeditPosition`
 * (`overTheSpot_`) and an IC currently exists, matching FLTK's own
 * `if (!xim_ic || !fl_is_over_the_spot) return;` guard exactly.
 *
 * Skips redundant `XSetICValues()` calls when neither the position nor
 * the font/size actually changed since last time (`change`, matching
 * FLTK's own flag of the same purpose) -- cheap to check, and
 * `drawCursor()`'s caller (`fl.text_display`) calls this on every
 * single cursor repaint, not just when it moves.
 *
 * Simplification vs. FLTK: no per-window coordinate walk to
 * translate a subwindow-local spot into its top-level window's frame
 * (FLTK's own `Fl::focus()->window()` parent-walk loop) -- callers
 * in this port already report screen-relative coordinates the same
 * way `fl.core.getMouse()`/`Widget.topWindowOffset()`-based callers
 * elsewhere in this port do, so there is nothing left to translate by
 * the time this function receives them. No DPI-scaling multiply either
 * (`Fl_Graphics_Driver::default_driver().scale()`) -- this port has no
 * separate DPI-scaling subsystem yet, a documented gap elsewhere (see
 * `fl.window`'s `PORTING.md` row), not something specific to this
 * function to solve.
 */
package(fl) void setSpot(int font, int size, int X, int Y, int W, int H)
{
    if (ximIc_ is null || !overTheSpot_) return;

    bool changed;
    if (X != spot_.x || Y != spot_.y)
    {
        spot_.x = cast(short) X;
        spot_.y = cast(short) Y;
        spot_.width = cast(ushort) W;
        spot_.height = cast(ushort) H;
        changed = true;
    }
    if (font != spotFont_ || size != spotSize_)
    {
        spotFont_ = font;
        spotSize_ = size;
        changed = true;
    }
    if (!changed) return;

    auto preeditAttr = XVaCreateNestedList(0,
        XNSpotLocation, &spot_, XNFontSet, ximFontSet_, null);
    XSetICValues(ximIc_, XNPreeditAttributes, preeditAttr, null);
    XFree(preeditAttr);
}

/// Clears the cached spot position -- the direct equivalent of
/// FLTK's `Fl_X11_Screen_Driver::reset_spot()`, backing
/// `fl.core.resetSpot()`. FLTK's real implementation just
/// invalidates `fl_spot.x`/`fl_spot.y` (`-1`, an impossible screen
/// coordinate) so the *next* `set_spot()` call is guaranteed to see a
/// change and actually push new `XNPreeditAttributes`, rather than
/// eagerly clearing anything on the input-method side itself --
/// ported the same way.
package(fl) void resetSpot()
{
    spot_.x = -1;
    spot_.y = -1;
}

/// Resets the current input context's composition state -- the direct
/// equivalent of the `XmbResetIC(xim_ic)` half of FLTK's
/// `Fl_X11_Screen_Driver::compose_reset()`. Called from
/// `fl.core.composeReset()`; a no-op if no input context exists.
package(fl) void resetIC()
{
    if (ximIc_ !is null) XmbResetIC(ximIc_);
}

/**
 * Installs a custom Xlib error handler that tolerates exactly one
 * known-benign race instead of taking the whole process down over it.
 *
 * The race this guards against, kept because it's a
 * generally useful thing to understand even though nothing currently
 * triggers it: `XSetInputFocus()` requires its target window to already be
 * *viewable*, but `XMapWindow()` only *requests* that a window become
 * mapped -- for a window a window manager might still be reparenting
 * into a decoration frame, that request can take an arbitrary amount of
 * WM-dependent time to actually land. A caller invoking
 * `XSetInputFocus()` directly on a window whose map hasn't finished
 * landing yet -- e.g. `fl.menu_popup`'s engine immediately after
 * `win.show()` when opening a cascade level -- would reliably reproduce
 * this as a `BadMatch`
 * error on a live server (`X_Error ... BadMatch ... Major opcode ... 42
 * (X_SetInputFocus)`, since Xlib's *default* error handler prints the
 * error and calls `exit()`).
 *
 * `grab()`'s real implementation (`grabPointer()`/`ungrabPointer()`, see
 * those functions' own doc comments) has since replaced the
 * `XSetInputFocus()` call entirely with real `XGrabPointer()`/
 * `XGrabKeyboard()` calls, preceded by `waitViewable()`'s bounded poll
 * -- so nothing in this port calls `XSetInputFocus()` at all anymore,
 * and the specific `BadMatch`-on-`X_SetInputFocus` this handler
 * swallows should no longer be reachable in practice (`XGrabPointer()`/
 * `XGrabKeyboard()` don't have this failure mode to begin with: an
 * unviewable target window makes them return the status code
 * `GrabNotViewable`, not raise a protocol error -- which is exactly why
 * `waitViewable()` polls attributes rather than needing an error
 * handler of its own). This handler is left in place anyway as a
 * defensive catch-all -- cheap insurance against a future direct
 * `XSetInputFocus()` call reintroducing the same race, and harmless
 * since it only swallows this one exact, narrow combination; everything
 * else still terminates the process via Xlib's own default handler, so
 * an unrelated real bug doesn't get masked by this.
 */
private void installErrorHandler()
{
    defaultXErrorHandler = XSetErrorHandler(&handleXError);
}

extern (C) private int handleXError(Display* display, XErrorEvent* event) @nogc nothrow
{
    if (event.error_code == BadMatch && event.request_code == X_SetInputFocus)
    {
        import core.stdc.stdio : fprintf, stderr;
        fprintf(stderr, "fl.platform_x11: ignored a benign XSetInputFocus "
            ~ "BadMatch (window not yet viewable -- see installErrorHandler()'s doc comment)\n");
        return 0;
    }

    return defaultXErrorHandler(display, event);
}

private __gshared XErrorHandler defaultXErrorHandler;

/**
 * Emits a system beep. The direct equivalent of
 * FLTK's `Fl_X11_Screen_Driver::beep()` (only the two volume levels
 * it actually distinguishes -- `error` at full volume, everything else
 * at the system default -- are ported; the other `Beep` enumerators
 * exist FLTK purely for API parity with Windows'
 * richer `MessageBeep()` types).
 */
void beep(Beep type)
{
    openDisplay();
    int volume = (type == Beep.error) ? 100 : 0;
    XBell(display_, volume);
}

/**
 * Claims real X11 ownership of the PRIMARY (`clipboard` 0) or CLIPBOARD
 * (`clipboard` 1) selection for `messageWindow_`, so other X
 * applications' paste requests reach us via `SelectionRequest` (handled
 * in processNextEvent()'s `case SelectionRequest:`). Called from
 * fl.core.copy(); the direct equivalent of FLTK's
 * `Fl_X11_Screen_Driver::copy()` tail (`XSetSelectionOwner(...)`).
 */
package(fl) void setSelectionOwner(int clipboard)
{
    openDisplay();
    Atom selection = clipboard ? clipboardAtom_ : XA_PRIMARY;
    XSetSelectionOwner(display_, selection, messageWindow_, lastEventTime_);
}

/**
 * Asks whichever X application currently owns the PRIMARY/CLIPBOARD
 * selection to convert it to text and hand it back -- fires
 * `XConvertSelection()` and returns immediately, matching FLTK's
 * real, asynchronous `Fl_X11_Screen_Driver::paste()` (it never blocks
 * waiting for the reply either; the `SelectionNotify` reply is handled
 * later, in processNextEvent()'s own `case SelectionNotify:`, which is
 * what actually delivers FL_PASTE via fl.core.deliverPaste()).
 *
 * Requests `UTF8_STRING` first -- simpler than FLTK's full
 * `TARGETS`-negotiation dance (asking the owner what formats it can
 * offer, then picking one), since this port only ever wants plain text
 * anyway. `case SelectionNotify:`'s own handler falls back to asking for
 * `XA_STRING` once if that fails (an owner that only offers legacy Latin-1
 * text), matching the common real-world case (e.g. an xterm selection)
 * without needing the full negotiation FLTK does.
 */
package(fl) void requestSelection(int clipboard)
{
    openDisplay();
    Atom selection = clipboard ? clipboardAtom_ : XA_PRIMARY;
    XConvertSelection(display_, selection, utf8StringAtom_, selection, messageWindow_, CurrentTime);
}

/**
 * The image-paste counterpart to `requestSelection()`, kept as a
 * genuinely separate function rather than a `type` parameter added to
 * that one -- unlike text, we don't know in advance which image MIME
 * type (if any) the current owner can produce, so this always goes
 * through a real `TARGETS` negotiation round trip first (matching
 * FLTK's own `Fl_X11_Screen_Driver::paste()` when `type ==
 * Fl::clipboard_image`, which *always* negotiates via `TARGETS` for
 * both text and images -- this port keeps `requestSelection()`'s
 * existing direct-`UTF8_STRING` shortcut for text unchanged rather than
 * unifying the two, so no existing text-paste caller's behavior
 * changes). The `TARGETS` reply is handled in `processNextEvent()`'s
 * `case SelectionNotify:`, which recognizes it by `target ==
 * targetsAtom_` (this is the only path in this port that ever requests
 * `TARGETS`, so that alone is an unambiguous discriminator -- no extra
 * pending-request-kind state needed).
 */
package(fl) void requestSelectionImage(int clipboard)
{
    openDisplay();
    Atom selection = clipboard ? clipboardAtom_ : XA_PRIMARY;
    XConvertSelection(display_, selection, targetsAtom_, selection, messageWindow_, CurrentTime);
}

/**
 * Ported from `Fl_X11_Screen_Driver::clipboard_contains(const char*)`
 * (`src/Fl_x.cxx`). Genuinely synchronous, unlike every other selection
 * operation in this module: it calls `XNextEvent()` itself, in a tight
 * loop, discarding up to 20 events that aren't the `SelectionNotify`
 * reply it's waiting for -- ported faithfully, including this real
 * FLTK wart (FLTK's own source comment already flags it:
 * `// FIXME: The following loop may ignore up to 20 events!`).
 * **This is worse here than in FLTK**: every other event this
 * port's normal loop would otherwise have handled (`XFilterEvent()`'d
 * IME composition, `keyVector_` bookkeeping, damage accumulation, ...)
 * is silently dropped for whatever raw `XEvent`s land during that
 * window. If a future report says "keystrokes/clicks occasionally get
 * lost right around a clipboard check," this function is the first
 * place to look, not something to re-diagnose from scratch. Only
 * reachable via `fl.core.clipboardContains()`, itself only reachable
 * when this process does *not* already own the CLIPBOARD selection
 * (see that function's own fast path).
 *
 * Text-target checking is deliberately narrower than FLTK's own
 * 8-atom `find_target_text()` list -- just `UTF8_STRING`/`XA_STRING`,
 * matching the same simplification `requestSelection()`'s own doc
 * comment already documents for the text-paste path (this port only
 * ever wants plain text, so `COMPOUND_TEXT`/`text/uri-list`/etc. would
 * never be actionable here anyway).
 */
package(fl) bool clipboardContains(string type)
{
    openDisplay();

    XConvertSelection(display_, clipboardAtom_, targetsAtom_, clipboardAtom_,
        messageWindow_, CurrentTime);
    XFlush(display_);

    XEvent event;
    int i = 0;
    do
    {
        XNextEvent(display_, &event);
        if (event.type == SelectionNotify && event.xselection.property == None) return false;
        i++;
    } while (i < 20 && event.type != SelectionNotify);
    if (i >= 20) return false;

    Atom actual;
    int format;
    c_ulong count, remaining;
    void* portion;
    XGetWindowProperty(display_, event.xselection.requestor, event.xselection.property,
        0, 4000, False, AnyPropertyType, &actual, &format, &count, &remaining, &portion);
    scope(exit) if (portion !is null) XFree(portion);
    if (actual != XA_ATOM) return false;

    Atom wantedFirst = type == clipboardImage ? imageBmpAtom_ : utf8StringAtom_;
    Atom wantedSecond = type == clipboardImage ? imagePngAtom_ : XA_STRING;
    Atom* atoms = cast(Atom*) portion;
    foreach (idx; 0 .. count)
        if (atoms[idx] == wantedFirst || atoms[idx] == wantedSecond) return true;
    return false;
}

////////////////////////////////////////////////////////////////
// Drag-and-drop (fl.core.dnd(), the receiving-side ClientMessage cases
// in processNextEvent() below, and the DND-drop completion branch in
// case SelectionNotify:). Ported from src/fl_dnd_x.cxx (the source/
// drag-loop side, `Fl_X11_Screen_Driver::dnd()`) + the XDND-specific
// branches of Fl_x.cxx's own case ClientMessage:/SelectionNotify:.
//
// Two genuinely different paths, matching FLTK exactly:
//  - **Same-process** (dragging between two windows this app itself
//    created, `samples/examples/howto_drag_and_drop.d`'s own Sender/
//    Receiver): no X protocol at all -- dnd()'s own loop finds the
//    target via find() (this port's window registry) and dispatches
//    Event.dndEnter/dndDrag/dndLeave/dndRelease directly, via
//    localHandle() below.
//  - **Cross-application** (dragging out to, or accepting a drop from,
//    a real XDND-aware X application): the real wire protocol --
//    XdndEnter/XdndPosition/XdndLeave/XdndDrop/XdndStatus/XdndFinished
//    ClientMessages, sent/received via sendClientMessage() below and
//    processNextEvent()'s case ClientMessage:. A drop's actual payload
//    is fetched the same way an ordinary paste() is (XConvertSelection()
//    + case SelectionNotify:), just through a dedicated property
//    (XA_SECONDARY) so that handler can tell a DND-triggered conversion
//    apart from a normal clipboard one and reply with XdndFinished
//    afterward instead of just delivering FL_PASTE.
//
// Deliberately simplified vs. FLTK, matching this port's existing
// text-only-negotiation precedent (requestSelection()'s/
// clipboardContains()'s own doc comments): only UTF8_STRING/XA_STRING/
// text/uri-list are ever offered or accepted -- no COMPOUND_TEXT/
// text/plain;charset=* variants, and no image-drop support (matching
// fl.draw's own "no colormap/palette, plain TrueColor" simplifications
// having nothing to do with this, it's simply not a feature any sample
// or widget in this port needs yet).

/// Returns the max XDND protocol version `window` advertises support
/// for via its own `XdndAware` property, or `0` if it doesn't have one
/// (not itself XDND-aware, or not even a window this process can query
/// -- either way, `dnd()`'s caller treats `0` as "not aware"). Ported
/// from the file-static `dnd_aware()` helper (`fl_dnd_x.cxx`).
private int dndAware(Window window)
{
    Atom actual;
    int format;
    c_ulong count, remaining;
    void* data;
    XGetWindowProperty(display_, window, xdndAware_, 0, 4, False, XA_ATOM,
        &actual, &format, &count, &remaining, &data);
    scope(exit) if (data !is null) XFree(data);
    if (actual == XA_ATOM && format == 32 && count && data !is null)
        return cast(int)(*cast(Atom*) data);
    return 0;
}

/// Sends a real `ClientMessage` to `window`, `format` 32, up to 5 data
/// longs -- ported from `fl_sendClientMessage()` (`Fl_x.cxx`), used for
/// every XDND wire message this module sends (`XdndEnter`/`XdndLeave`/
/// `XdndPosition`/`XdndDrop`/`XdndStatus`/`XdndFinished`). Relies on
/// `XEvent`'s `xany`/`xclient` members sharing the same leading fields
/// (type/window), matching FLTK's own identical idiom.
private void sendClientMessage(Window window, Atom message,
    c_long d0, c_long d1 = 0, c_long d2 = 0, c_long d3 = 0, c_long d4 = 0)
{
    XEvent e;
    e.xany.type = ClientMessage;
    e.xany.window = window;
    e.xclient.message_type = message;
    e.xclient.format = 32;
    e.xclient.data.l[0] = d0;
    e.xclient.data.l[1] = d1;
    e.xclient.data.l[2] = d2;
    e.xclient.data.l[3] = d3;
    e.xclient.data.l[4] = d4;
    XSendEvent(display_, window, False, 0, &e);
}

/// Picks the best text target from `avail` (a drag source's own
/// offered-types list, `XdndEnter`'s data or its `XdndTypeList`
/// property) -- ported from `find_target()`/`find_target_text()`
/// (`Fl_x.cxx`), simplified to this port's own narrower 3-atom
/// preference list (see this section's own header comment) rather than
/// FLTK's fully generic, 8-entry, reusable-for-images-too matcher.
/// Preference order: `UTF8_STRING`, then `XA_STRING`, then
/// `text/uri-list` (so a file manager offering only a URI list is still
/// accepted, delivered as raw `file:///...` text via `Event.paste`).
/// Returns `0` (`None`) if `avail` offers none of the three.
private Atom findTargetText(Atom[] avail)
{
    Atom[3] prefs = [utf8StringAtom_, XA_STRING, xdndUriList_];
    foreach (want; prefs)
        foreach (a; avail)
            if (a == want) return want;
    return 0;
}

/// Installed as `fl.core.localGrab_` for the duration of a drag-and-drop
/// operation (`dnd()` below) -- ported from the file-static `grabfunc()`
/// (`fl_dnd_x.cxx`). While a drag is in progress, every event flowing
/// through the *normal* dispatch path (real X-driven events reaching
/// `fl.core.handle()` -- e.g. `MotionNotify`/`ButtonRelease` on the
/// *source* window, still arriving via the ordinary event loop even
/// though `dnd()` itself is polling the pointer separately) is swallowed
/// except that a genuine button release clears `pushed()`, ending the
/// implicit grab the original mouse-down established -- `dnd()`'s own
/// `while (fl.core.pushed())` loop condition is what that's for.
private int grabFunc(Event event)
{
    if (event == Event.release) fl.core.pushed(null);
    return 0;
}

/// Dispatches `event` to `window`, a window belonging to *this*
/// process, translating `fl.core.eventXRoot()`/`eventYRoot()` (already
/// set by `dnd()`'s own `XQueryPointer()` polling) into `window`-local
/// coordinates first -- ported from the file-static `local_handle()`
/// (`fl_dnd_x.cxx`). Temporarily clears `fl.core.localGrab_` around the
/// call so this synthetic dispatch itself isn't swallowed by
/// `grabFunc()` above, then restores it -- matching FLTK's own
/// `fl_local_grab = 0; ...; fl_local_grab = grabfunc;` bracket exactly.
private int localHandle(Event event, FlWindow window)
{
    fl.core.localGrab_ = null;
    fl.core.eX_ = fl.core.eXRoot_ - window.x();
    fl.core.eY_ = fl.core.eYRoot_ - window.y();
    int ret = fl.core.dispatch(event, window);
    fl.core.localGrab_ = (e) => grabFunc(e);
    return ret;
}

/**
 * Starts a drag-and-drop operation carrying whatever `fl.core.copy()`
 * most recently placed in the PRIMARY selection -- ported from
 * `Fl_X11_Screen_Driver::dnd(int)` (`fl_dnd_x.cxx`). Called from
 * `fl.core.dnd()`; see this section's own header comment for the
 * same-process-vs-cross-application split this loop implements.
 *
 * Blocks (running its own nested `fl.core.wait()` loop) until the drag
 * completes -- i.e. until `fl.core.pushed()` becomes `null`, which
 * happens either via `grabFunc()` reacting to a real button-release on
 * the source window, or, for a same-process target, via `localHandle()`
 * dispatching `Event.dndRelease` directly (see `FlGroup.handle()`'s
 * `case Event.push:`, which is what first set `pushed()` from the
 * initial click that led here).
 */
package(fl) int dnd()
{
    FlWindow sourceFlWin = fl.core.firstWindow();
    if (sourceFlWin is null) return 0;
    sourceFlWin.cursor(CursorShape.move);
    Window sourceWindow = sourceFlWin.xid();
    fl.core.localGrab_ = (e) => grabFunc(e);
    Window targetWindow = 0;
    FlWindow localWindow = null;
    int dndVersion = 4;
    int destX, destY;
    XSetSelectionOwner(display_, xdndSelection_, sourceWindow, lastEventTime_);

    while (fl.core.pushed() !is null)
    {
        // Figure out what window we are pointing at, walking down the
        // window tree from the root exactly as FLTK does: stop as
        // soon as we hit either one of *our own* windows (checked via
        // find(), this port's registry) or one that's at least
        // XDND-aware, whichever comes first.
        Window newWindow = 0;
        int newVersion = 0;
        FlWindow newLocalWindow = null;
        for (Window child = XRootWindow(display_, screen_);;)
        {
            Window root;
            uint junk3;
            XQueryPointer(display_, child, &root, &child,
                &fl.core.eXRoot_, &fl.core.eYRoot_, &destX, &destY, &junk3);
            if (!child)
            {
                if (!newWindow && (newVersion = dndAware(root)) != 0) newWindow = root;
                break;
            }
            newWindow = child;
            if (auto rec = find(child)) { newLocalWindow = rec.widget; break; }
            if ((newVersion = dndAware(newWindow)) != 0) break;
        }

        // fl.core.eXRoot_/eYRoot_ were just written as raw device
        // pixels (the XQueryPointer() calls above write directly into
        // them). Divide down to FLTK units only once we know the
        // pointer landed on one of *our own* windows -- matching
        // FLTK's own conditional-on-new_local_window scaling
        // exactly; `localHandle()`
        // right below expects FLTK-unit values.
        if (newLocalWindow !is null)
        {
            // `newLocalWindow.screenNum()`'s own scale, not a
            // hardcoded screen 0 -- the
            // pointer's real device-pixel root position divides by
            // whichever screen the window it actually landed on is on.
            float s = screenScale(newLocalWindow.screenNum());
            fl.core.eXRoot_ = cast(int)(fl.core.eXRoot_ / s);
            fl.core.eYRoot_ = cast(int)(fl.core.eYRoot_ / s);
        }

        if (newWindow != targetWindow)
        {
            if (localWindow !is null)
                localHandle(Event.dndLeave, localWindow);
            else if (dndVersion)
                sendClientMessage(targetWindow, xdndLeave_, sourceWindow);

            dndVersion = newVersion;
            targetWindow = newWindow;
            localWindow = newLocalWindow;

            if (localWindow !is null)
                localHandle(Event.dndEnter, localWindow);
            else if (dndVersion)
            {
                // Support dragging of files/URLs as well as arbitrary
                // text: if the copied text looks like a URI list (a
                // recognized scheme, no spaces, at least one CRLF),
                // flag it as both text/uri-list and plain text; otherwise
                // just plain text -- matching FLTK's own heuristic
                // exactly (Fl_X11_Screen_Driver::dnd()'s own comment).
                import std.string : startsWith;
                import std.algorithm : canFind;

                string text = fl.core.clipboardContents(0);
                bool looksLikeUriList =
                    (text.startsWith("file:///") || text.startsWith("ftp://")
                        || text.startsWith("http://") || text.startsWith("https://")
                        || text.startsWith("ipp://") || text.startsWith("ldap:")
                        || text.startsWith("mailto:") || text.startsWith("news:")
                        || text.startsWith("smb://"))
                    && !text.canFind(' ') && text.canFind("\r\n");

                if (looksLikeUriList)
                    sendClientMessage(targetWindow, xdndEnter_, sourceWindow,
                        cast(c_long)(dndVersion << 24), xdndUriList_, utf8StringAtom_, XA_STRING);
                else
                    sendClientMessage(targetWindow, xdndEnter_, sourceWindow,
                        cast(c_long)(dndVersion << 24), utf8StringAtom_, XA_STRING, 0);
            }
        }

        if (localWindow !is null)
            localHandle(Event.dndDrag, localWindow);
        else if (dndVersion)
        {
            int exRoot = fl.core.eXRoot_, eyRoot = fl.core.eYRoot_;
            sendClientMessage(targetWindow, xdndPosition_, sourceWindow,
                0, cast(c_long)((exRoot << 16) | eyRoot), lastEventTime_, xdndActionCopy_);
        }

        fl.core.wait();
    }

    if (localWindow !is null)
    {
        fl.core.markPrimaryOwned();
        if (localHandle(Event.dndRelease, localWindow))
            fl.core.paste(fl.core.belowmouse(), 0);
    }
    else if (dndVersion)
    {
        sendClientMessage(targetWindow, xdndDrop_, sourceWindow, 0, lastEventTime_);
    }
    else if (targetWindow)
    {
        // The target isn't XDND-aware at all -- fake a drop by
        // synthesizing a middle-click, an old-school X11 compatibility
        // trick some non-XDND apps still honor (e.g. terminal emulators
        // pasting PRIMARY on a middle click). Ported verbatim.
        XEvent msg;
        msg.xbutton.type = ButtonPress;
        msg.xbutton.window = targetWindow;
        msg.xbutton.root = XRootWindow(display_, screen_);
        msg.xbutton.subwindow = 0;
        msg.xbutton.time = lastEventTime_ + 1;
        msg.xbutton.x = destX;
        msg.xbutton.y = destY;
        msg.xbutton.x_root = fl.core.eXRoot_;
        msg.xbutton.y_root = fl.core.eYRoot_;
        msg.xbutton.state = 0x0;
        msg.xbutton.button = Button2;
        XSendEvent(display_, targetWindow, False, 0, &msg);
        msg.xbutton.time = msg.xbutton.time + 1;
        msg.xbutton.state = Button2Mask;
        msg.xbutton.type = ButtonRelease;
        XSendEvent(display_, targetWindow, False, 0, &msg);
    }

    fl.core.localGrab_ = null;
    fl.core.dispatch(Event.release, sourceFlWin);
    sourceFlWin.cursor(CursorShape.default_);
    return 1;
}

////////////////////////////////////////////////////////////////
// Clipboard-change notification (fl.core.addClipboardNotify()).
//
// Two-tier, matching FLTK's own `#if HAVE_XFIXES` split in
// Fl_x.cxx exactly (both tiers ported, not just one):
//
//  - **Primary: real, instant, event-driven** via the Xfixes extension
//    (`fl.xfixes`) when present -- `createWindow()` subscribes each
//    top-level window with `XFixesSelectSelectionInput()`, and
//    `processNextEvent()`'s own `XFixesSelectionNotify` check reacts
//    the moment the X server delivers one, no polling involved at all.
//    This is the path that actually runs on any modern desktop
//    (`CMakeCache.txt`: `FLTK_USE_XFIXES=ON`). Without it, clipboard
//    change notification would fall back to the polling tier below,
//    which has a visible, wrong-feeling delay real FLTK doesn't have.
//  - **Fallback: 0.5s polling**, unconditionally used when Xfixes isn't
//    available (`haveXfixes_` false) -- ask both selections for their
//    current ownership `Time` via a `TIMESTAMP` target every 0.5s; a
//    changed `Time` since the last poll means some other application
//    took ownership. This is FLTK's own real fallback for exactly
//    this situation, not a simplification unique to this port.
//
// Both tiers funnel into the same handleClipboardTimestamp() below,
// matching FLTK's own shared `handle_clipboard_timestamp()`.
//
// pollClipboardOwner() deliberately uses messageWindow_ as the
// request's requestor, not FLTK's `fl_xid(Fl::first_window())` --
// this module already funnels every other "ask another app to convert
// a selection" XConvertSelection() through messageWindow_ (see that
// field's own doc comment), and messageWindow_ exists unconditionally
// once openDisplay() has run, unlike a shown top-level window. Using it
// here too avoids a spurious "no window shown yet" gate FLTK needs
// only because of its own different choice of requestor.

private Time primaryTimestamp_ = Time.max; // Time.max == FLTK's (Time)-1 sentinel, "not yet known"
private Time clipboardTimestamp_ = Time.max;
private TimeoutHandler clipboardTimeoutHandler_;

/// package(fl): called by fl.core.addClipboardNotify()/
/// removeClipboardNotify() whenever the registered-handler list
/// transitions empty <-> non-empty. Ported from
/// `Fl_X11_Screen_Driver::clipboard_notify_change()`. A no-op beyond
/// the timestamp reset when Xfixes is available -- that tier is always
/// "on" per-window (see createWindow()'s own `XFixesSelectSelectionInput()`
/// calls, unconditional on any registered handler existing at all), so
/// there's no separate polling machinery here to start/stop.
package(fl) void clipboardNotifyChange()
{
    if (fl.core.clipboardNotifyEmpty())
    {
        // Reset so the next time someone starts listening, an old
        // stale timestamp doesn't look like an immediate bogus change.
        primaryTimestamp_ = Time.max;
        clipboardTimestamp_ = Time.max;
        return;
    }

    if (haveXfixes_) return;

    openDisplay();
    pollClipboardOwner();
    if (clipboardTimeoutHandler_ is null)
        clipboardTimeoutHandler_ = () { clipboardTimeoutTick(); };
    if (!fl.core.hasTimeout(clipboardTimeoutHandler_))
        fl.core.addTimeout(0.5, clipboardTimeoutHandler_);
}

private void pollClipboardOwner()
{
    if (haveXfixes_) return; // no polling needed -- see this section's own top comment
    if (fl.core.clipboardNotifyEmpty()) return;

    if (!fl.core.weOwnSelection(0))
        XConvertSelection(display_, XA_PRIMARY, timestampAtom_, primaryTimestampAtom_,
            messageWindow_, lastEventTime_);
    if (!fl.core.weOwnSelection(1))
        XConvertSelection(display_, clipboardAtom_, timestampAtom_, clipboardTimestampAtom_,
            messageWindow_, lastEventTime_);
}

private void clipboardTimeoutTick()
{
    if (fl.core.clipboardNotifyEmpty()) return;
    pollClipboardOwner();
    fl.core.repeatTimeout(0.5, clipboardTimeoutHandler_);
}

/// Called both from a poll's TIMESTAMP reply (`case SelectionNotify:`)
/// and from a real `XFixesSelectionNotify` event (`processNextEvent()`).
/// Ported from `handle_clipboard_timestamp()` (Fl_x.cxx), including
/// FLTK's own "initial scan, just record the baseline, don't
/// notify" step, wrapped in `#if HAVE_XFIXES if (!have_xfixes)
/// #endif` -- it only applies to the polling fallback. An Xfixes event
/// is never a "scan," it's always a genuine ownership change already,
/// so it must notify even the very first time: applying the
/// baseline-swallow unconditionally would silently eat
/// the *first* real copy after startup (`primaryTimestamp_`/
/// `clipboardTimestamp_` both start at the `Time.max` sentinel, so the
/// first event of either kind would look like "just establishing
/// the baseline").
private void handleClipboardTimestamp(int clipboard, Time time)
{
    Time* stamp = clipboard ? &clipboardTimestamp_ : &primaryTimestamp_;

    if (!haveXfixes_ && *stamp == Time.max)
    {
        // Initial poll -- just record whatever the pre-existing
        // owner's timestamp already is, don't treat "we just started
        // watching" as a change. Polling-fallback-only, see this
        // function's own doc comment above.
        *stamp = time;
        return;
    }
    if (time == *stamp) return;
    *stamp = time;

    if (time > lastEventTime_) lastEventTime_ = time;
    fl.core.triggerClipboardNotify(clipboard);
}

/**
 * Names a keysym for fl.core's fl_shortcut_label() (e.g. XK_Left ->
 * "Left"), or returns null if it isn't worth naming -- either because
 * XKeysymToString() doesn't recognize it, or because it falls in the
 * plain printable ASCII/Latin-1 range where the caller's own
 * uppercased-character fallback reads better than Xlib's name for it
 * (same idea as FLTK's "don't use Xlib's 'Return'" comment, applied
 * here to FL_Enter specifically). Ported from
 * Fl_X11_Screen_Driver::shortcut_add_key_name() (src/drivers/X11/
 * Fl_X11_Screen_Driver.cxx) -- doesn't need an open display
 * (XKeysymToString() consults a static Xlib-internal table), so unlike
 * beep()/createWindow() this doesn't call openDisplay() first.
 */
string keyName(uint key)
{
    import fl.enumerations : enter;
    import std.string : fromStringz;

    if (key == enter || key == '\r') return "Enter";
    if (key > 32 && key < 0x100) return null;

    const(char)* q = XKeysymToString(cast(KeySym) key);
    if (q is null) return null;
    return fromStringz(q).idup;
}

/// Backs `fl.core.getSystemScheme()`'s X-resource-database fallback
/// (`Fl_X11_Screen_Driver::get_system_scheme()`'s own
/// `XGetDefault(fl_display, key, "scheme")` call, `src/drivers/X11/
/// Fl_X11_Screen_Driver.cxx`). `program`/`option` are plain D strings
/// converted to the transient null-terminated buffers `XGetDefault()`
/// needs; the returned string, if any, is X-library-owned static
/// storage (never freed), copied into a GC-owned `string` before
/// returning, matching `keyName()`'s own convention just above.
package(fl) string getDefaultResource(string program, string option)
{
    import std.string : toStringz, fromStringz;

    openDisplay();
    const(char)* s = XGetDefault(display_, program.toStringz(), option.toStringz());
    if (s is null) return null;
    return fromStringz(s).idup;
}

private WindowRecord* find(Window xid)
{
    for (auto rec = first_; rec !is null; rec = rec.next)
        if (rec.xid == xid) return rec;
    return null;
}

/// The head of the shown-window list (`first_.widget`, or null if no
/// window is shown) -- the read side of `Fl::first_window()` (Fl.cxx),
/// which just returns `Fl_X::first ? Fl_X::first->w : 0`.
package(fl) FlWindow firstWindowWidget()
{
    return first_ !is null ? first_.widget : null;
}

/// The window after `win` in the shown-window list, or null if `win`
/// is last (or not found). Ported from `Fl::next_window()` (Fl.cxx) --
/// FLTK calls `Fl::error()` when `win` isn't found; this port has
/// no such mechanism, so it just returns null (matching how every other
/// not-found case in this module is already handled).
package(fl) FlWindow nextWindowWidget(FlWindow win)
{
    for (auto rec = first_; rec !is null; rec = rec.next)
        if (rec.widget is win)
            return rec.next !is null ? rec.next.widget : null;
    return null;
}

/// Moves `win`'s record to the front of the shown-window list, unless
/// `fl.core.modal()` is active (to avoid disturbing the modal stack) --
/// the write side of `Fl::first_window(Fl_Window*)` (Fl.cxx), ported
/// from `Fl_Window_Driver::find(fl_uintptr_t)`'s reordering side effect
/// (the same function `find(Window)` above is the read-only half of;
/// FLTK's own version doubles as a plain xid lookup *and* this
/// reordering, this port keeps the two separate since nothing else
/// needs the combined form).
package(fl) void makeWindowFirst(FlWindow win)
{
    if (fl.core.modal() !is null) return;
    WindowRecord** pp = &first_;
    for (auto rec = first_; rec !is null; rec = rec.next)
    {
        if (rec.widget is win)
        {
            if (rec !is first_)
            {
                *pp = rec.next;
                rec.next = first_;
                first_ = rec;
            }
            return;
        }
        pp = &rec.next;
    }
}

/**
 * Creates the real X11 window for win and maps it. The direct
 * equivalent of FLTK's `Fl_X::make_xid()` (Fl_x.cxx). **Real
 * subwindow support**: a subwindow (`win.parent() !is null`) gets a real child
 * X window (parented to `win.window()`'s own xid, not the root) with a
 * reduced `ExposureMask`-only event mask, matching FLTK's own
 * `childEventMask` -- subwindows never directly receive input events at
 * all; those always propagate up to whichever real ancestor window
 * *does* select for them (ultimately the top-level), arriving with
 * coordinates relative to *that* window, which is exactly why
 * `fl.core.sendEvent()`'s subwindow coordinate-offset adjustment matters
 * (see that function's own doc comment) -- a subwindow's own xid exists
 * purely to give its widget subtree an isolated drawable/clip region for
 * *drawing*, not for independent event delivery. If `win.window()`
 * (the immediate window ancestor) doesn't have a real xid of its own yet
 * (not shown), this defers: marks `win` logically visible and returns,
 * matching FLTK's own early-return -- `Window.handle()`'s
 * `Event.show` case is what actually creates it later, once the
 * ancestor's own `show()` cascades `Event.show` down and reaches it.
 * All of the WM-facing negotiation below (WM_PROTOCOLS/size-hints/
 * motif-hints/label/transient-for/modal hints) is skipped entirely for
 * a subwindow, matching FLTK's own blanket `!win->parent()` gate --
 * none of it makes sense for a window with no window manager involved.
 *
 * **Real per-visual window creation**:
 * every window (top-level or subwindow) is created with whatever
 * `fl_visual`/`fl_colormap` currently point at, read directly here --
 * not a separately-cached copy -- matching FLTK's own `Fl_X::
 * make_xid(pWindow, fl_visual, fl_colormap)` exactly. `fl.draw`'s
 * pixel-packing state follows the same visual, via `ensureVisualFigured()`'s
 * one-time trigger below. The one piece that does *not* follow
 * `fl_visual`: the single shared GC (`fl.draw`'s own `gc_`, created
 * once in `openDisplay()` against the *default* visual's depth) is
 * never recreated for a differently-selected visual -- matching
 * FLTK's own single never-recreated `fl_gc` (see `openDisplay()`'s
 * comment). This only matters in the rare case a selected visual's
 * *depth* differs from the default depth (X11 requires a GC's depth to
 * match the drawable it's used on) -- on virtually every modern X
 * server, every TrueColor visual on offer shares one depth regardless
 * of visual ID, so `testVisual()`'s deepest-visual search never
 * actually picks a different-depth one in practice, and FLTK
 * itself never solves this either.
 */

/// Writes `name`/its icon name (`iname`, or -- if empty, matching
/// FLTK's own `if (!iname) iname = fl_filename_name(name);` fallback
/// -- derived from `name`) to `xid`'s WM_NAME/_NET_WM_NAME/
/// XA_WM_ICON_NAME/_NET_WM_ICON_NAME properties. The shared body behind
/// both createWindow()'s initial title-setting and updateWindowLabel()'s
/// live re-application below -- see the latter's doc comment for why a
/// second call site exists at all. `iname` defaults to empty (pure
/// derivation) for the two existing call sites below; `fl.window.Window.
/// iconlabel(string)` (an explicit icon-title override, backing
/// `fl.glut`'s `glutSetIconTitle()`) is what actually
/// passes a real value through.
private void applyWindowLabel(Window xid, string name, string iname = null)
{
    if (iname.length == 0) iname = filenameName(name);
    XChangeProperty(display_, xid, netWmName_, utf8StringAtom_, 8, PropModeReplace,
        cast(const(ubyte)*) toStringzTemp(name), cast(int) name.length);
    XStoreName(display_, xid, toStringzTemp(name));
    XChangeProperty(display_, xid, netWmIconName_, utf8StringAtom_, 8, PropModeReplace,
        cast(const(ubyte)*) toStringzTemp(iname), cast(int) iname.length);
    XChangeProperty(display_, xid, XA_WM_ICON_NAME, XA_STRING, 8, PropModeReplace,
        cast(const(ubyte)*) toStringzTemp(iname), cast(int) iname.length);
}

/**
 * Ported from `Fl_X11_Window_Driver::label()` (Fl_x.cxx) -- pushes
 * `win`'s *current* `label()` to its real X11 title properties. Unlike
 * `applyWindowLabel()` above (called once, at creation time, from
 * `createWindow()`), this is the live counterpart: FLTK's
 * `Fl_Window::label(name, mininame)` calls straight into this same
 * driver entry point on *every* call, not just the first, which is why
 * a real FLTK program's `win->copy_label(buf)` after `win->show()`
 * (e.g. updating a title with live frame/playback info) visibly
 * updates the titlebar immediately. This port's `fl.window.Window` had
 * no equivalent call site at all -- `label()`/`copyLabel()` only ever
 * touched the in-process `Widget.label_` field, so without this call
 * site a post-show()
 * title change (e.g. several GIF-animation/pixmap samples that update their window
 * title from a callback) would show no title change at all. `Window`'s own
 * `label()` override (`fl.window.d`) calls this after updating the
 * base field.
 *
 * Matches FLTK's own `if (shown() && !parent())` guard exactly: a
 * no-op for a window not yet shown (createWindow() will apply the
 * then-current label itself once it is) or for a subwindow (which has
 * no WM-visible titlebar of its own to update).
 */
package(fl) void updateWindowLabel(FlWindow win)
{
    if (win.xid() == 0 || win.parent() !is null) return;
    applyWindowLabel(win.xid(), win.label(), win.iconlabel());
}

/// Rounds `v * s` to the nearest integer -- for a window's on-screen
/// *position* (which can legitimately be negative, e.g. a monitor to
/// the left of the primary one), matching FLTK's `rint(X*s)`
/// (`Fl_x.cxx`'s `make_xid()`/`Fl_X11_Window_Driver::resize()`).
private int scaledPos(int v, float s)
{
    if (s == 1) return v;
    import std.math : lround;

    return cast(int) lround(v * cast(double) s);
}

/// Truncates `v * s`, clamped to a minimum of `1` -- for a window's
/// on-screen *dimension*, matching FLTK's plain (never rounded)
/// `W*s`/`W>0 ? W*s : 1` pattern.
private uint scaledDim(int v, float s)
{
    if (s == 1) return v > 0 ? cast(uint) v : 1;
    int r = cast(int)(v * s);
    return r > 0 ? cast(uint) r : 1;
}

/**
 * `visual`/`colormap` default to the current `fl_visual`/`fl_colormap`
 * globals, matching FLTK's own `Fl_X::make_xid(Fl_Window*,
 * XVisualInfo*=fl_visual, Colormap=fl_colormap)` signature exactly
 * (`FL/platform.H` line 62) -- purely additive, every existing call
 * site keeps creating windows against the process-wide default visual
 * unchanged. The explicit-argument form exists for `fl.gl_window_driver`:
 * a GL window's `before_show()`
 * must create its X window against the specific visual `glXChooseVisual()`
 * picked, not whatever the display default happens to be -- FLTK's own
 * `FL/gl.h` doc comment: "Mesa will crash if you try to use a visual
 * not returned by glXChooseVisual". A per-call override rather than a
 * temporary global reassignment keeps this scoped to just the one GL
 * window, unlike `Fl::gl_visual()`'s separate, opt-in mechanism of
 * reassigning `fl_visual`/`fl_colormap` themselves for every
 * subsequently created window.
 */
void createWindow(FlWindow win, XVisualInfo* visual = null, Colormap colormap = 0)
{
    openDisplay();
    if (visual is null) visual = fl_visual;
    if (colormap == 0) colormap = fl_colormap;
    ensureVisualFigured();

    bool isSubwindow = win.parent() !is null;
    FlWindow parentWin;
    if (isSubwindow)
    {
        parentWin = win.window();
        if (parentWin is null || !parentWin.shown())
        {
            win.setVisible();
            return;
        }
    }

    // Cache which monitor this window is considered to be on, for
    // fl.window.Window.screenNum()'s benefit -- ported from Fl_x.cxx's
    // create_window() (the `#if USE_XFT || FLTK_USE_CAIRO` block just
    // before XCreateWindow()): a subwindow always inherits its top-level
    // ancestor's value; otherwise, an explicit pre-show() screenNum(int)
    // call sticks (checked via rawScreenNum() >= 0, standing in for
    // FLTK's separate force_position() flag, which this port hasn't
    // wired up at all -- no other code path sets it, so this is
    // equivalent in effect); failing that, fall back to
    // firstWindowWidget()'s screen as a hint (a new window defaults to
    // appearing on whatever monitor the frontmost existing window is on),
    // or screen 0 if there is no other shown window yet.
    if (isSubwindow)
        win.rawScreenNum(parentWin.topWindow().screenNum());
    else if (win.rawScreenNum() < 0)
    {
        auto hint = firstWindowWidget();
        win.rawScreenNum(hint !is null ? hint.topWindow().screenNum() : 0);
    }

    // Scaled from FLTK units to real device pixels here, at the one
    // point a window's geometry actually becomes an X11 request --
    // `win.x()`/`win.y()`/`win.w()`/`win.h()` themselves stay in FLTK
    // units throughout, matching FLTK's own `X*s`/`Y*s`/`W*s`/`H*s`
    // at this exact call site (`Fl_x.cxx`'s `make_xid()`).
    float scale = screenScale(win.rawScreenNum());
    int x = scaledPos(win.x, scale);
    int y = scaledPos(win.y, scale);
    uint w = scaledDim(win.w, scale);
    uint h = scaledDim(win.h, scale);

    XSetWindowAttributes attr;
    attr.colormap = colormap;
    attr.event_mask = isSubwindow ? ExposureMask
        : ExposureMask | StructureNotifyMask
        | KeyPressMask | KeyReleaseMask
        | ButtonPressMask | ButtonReleaseMask | PointerMotionMask
        | EnterWindowMask | LeaveWindowMask | FocusChangeMask
        | PropertyChangeMask | KeymapStateMask;
    attr.border_pixel = 0;
    attr.bit_gravity = 0; // ForgetGravity (FLTK's own comment on this field is misleading)

    // FLTK never sets this explicitly either (it relies on the
    // server's default, which is NotUseful -- "don't bother" -- on
    // most real X servers), but backing store is purely an advisory,
    // best-effort server-side optimization: the X11 protocol spec
    // explicitly does not guarantee its contents are correct. Forcing
    // NotUseful here rules out the server trying (and potentially
    // failing) to restore occluded pixels itself, leaving this port's
    // own Expose-triggered repaint as the only path that ever touches
    // these pixels.
    attr.backing_store = NotUseful;

    c_ulong mask = CWColormap | CWEventMask | CWBorderPixel | CWBitGravity | CWBackingStore;

    // Menu popup windows (fl.menu_popup's cascade levels, marked via
    // Widget.Flag.menuWindow -- see fl.menu_item's module) are made
    // override-redirect: the X *server* maps them immediately on
    // XMapWindow() with no window-manager involvement at all, instead
    // of only *requesting* mapping and waiting on however long the WM
    // takes to notice, decide on decoration/reparenting, and actually
    // map its frame. This is the standard, universal technique every
    // real toolkit uses for exactly this kind of transient popup --
    // not a shortcut unique to this port. It's what actually fixes the
    // XSetInputFocus() BadMatch race the `_MOTIF_WM_HINTS`-based
    // border removal alone could only reduce, not eliminate: `XSync()`
    // after mapping (see below) only guarantees the *X server* has
    // processed the map request, not that a window manager has
    // finished reparenting/mapping the frame it decided to wrap the
    // window in -- and for override-redirect windows there is no frame
    // and no WM decision to wait on, so XSync() alone is now
    // sufficient. Confirmed against a live server (fvwm): without this,
    // every single popup open hit the BadMatch race (the installed
    // error handler swallowed the error correctly, but the window
    // itself never became focusable/interactive as a result -- no
    // popup ever actually appeared usable). Deliberately narrow: only
    // menuWindow-flagged windows get this treatment, not every
    // `!border()` window, since override-redirect's other effects
    // (invisible to window-switchers/taskbars, always-above stacking)
    // are appropriate for a transient popup but not for every
    // borderless window a caller might create for other reasons.
    bool isMenuWindow = (win.flags() & Widget.Flag.menuWindow) != 0;
    if (isMenuWindow)
    {
        attr.override_redirect = True;
        mask |= CWOverrideRedirect;
    }

    Window root = isSubwindow ? parentWin.xid() : XRootWindow(display_, screen_);
    Window xid = XCreateWindow(display_, root,
        x, y, w, h, 0, cast(int) visual.depth, InputOutput, visual.visual, mask, &attr);

    // Set WM_CLIENT_MACHINE and WM_LOCALE_NAME -- ported from
    // make_xid()'s own identical all-`NULL`-but-those-two-side-effects
    // call (Fl_x.cxx): XSetWMProperties() still sets both from the
    // process's current hostname/locale even when every other argument
    // is null. Also set _NET_WM_PID (same source location) -- both apply to
    // *every* window, including subwindows, matching FLTK's own
    // placement outside the `!isSubwindow` gate just below (unlike
    // WM_PROTOCOLS/the title properties/WM_CLASS, which are top-level-
    // window-only).
    XSetWMProperties(display_, xid, null, null, null, 0, null, null, null);
    c_long pid = getpid();
    XChangeProperty(display_, xid, netWmPid_, XA_CARDINAL, 32, PropModeReplace,
        cast(const(ubyte)*)&pid, 1);

    auto rec = new WindowRecord;
    rec.xid = xid;
    rec.widget = win;
    rec.next = first_;
    first_ = rec;

    if (!isSubwindow)
    {
        // Ported from make_xid()'s own `if (have_xfixes && !win->parent())`
        // block (Fl_x.cxx) -- subscribes this top-level window to real,
        // event-driven notification the instant another application
        // takes ownership of PRIMARY or CLIPBOARD, backing
        // fl.core.addClipboardNotify() (see processNextEvent()'s own
        // `XFixesSelectionNotify` check for the receiving half). A
        // no-op if the extension isn't present (pollClipboardOwner()'s
        // 0.5s polling is the fallback then, same as FLTK).
        if (haveXfixes_)
        {
            XFixesSelectSelectionInput(display_, xid, XA_PRIMARY, XFixesSetSelectionOwnerNotifyMask);
            XFixesSelectSelectionInput(display_, xid, clipboardAtom_, XFixesSetSelectionOwnerNotifyMask);
        }

        // The WM_DELETE_WINDOW wiring: FLTK writes the WM_PROTOCOLS
        // property directly (rather than calling the XSetWMProtocols()
        // convenience function) -- functionally identical either way.
        XChangeProperty(display_, xid, wmProtocols_, XA_ATOM, 32, PropModeReplace,
            cast(const(ubyte)*)&wmDeleteWindow_, 1);

        // Make it receptive to DnD -- ported from make_xid()'s identical
        // "Make it receptive to DnD" block (Fl_x.cxx). The value stored
        // is a plain integer (the max XDND protocol version this port
        // understands), but declared as `Atom` (`c_ulong`, 8 bytes on
        // 64-bit) rather than `int`/`uint` specifically so it matches
        // the storage width a `format 32` `XChangeProperty()` call
        // actually writes -- the exact bug class CLAUDE.md's
        // `project_xchangeproperty_format32_clong_bug` note warns
        // about (a `uint` here would undersize the property by half and
        // risk corrupting whatever happens to sit right after it).
        Atom xdndVersion = 5;
        XChangeProperty(display_, xid, xdndAware_, XA_ATOM, 32, PropModeReplace,
            cast(const(ubyte)*)&xdndVersion, 1);

        // "send size limits and border" in FLTK's make_xid() (Fl_x.cxx)
        // -- see sendSizeHints()'s own doc comment for why this is skipped
        // when sizeRange() was never called, unlike FLTK.
        sendSizeHints(win, xid);
        if (!win.border()) sendMotifWmHints(xid);

        // Ported from Fl_X11_Window_Driver::label() (Fl_x.cxx), called
        // unconditionally at window-creation time even for an empty
        // label: an untitled window still needs WM_NAME/_NET_WM_NAME
        // set (to an empty string, if nothing else), since some window
        // managers treat "absent" and "present but empty" differently.
        // Also sets the two icon-name properties FLTK sets alongside
        // the title ones (`_NET_WM_ICON_NAME`/`XA_WM_ICON_NAME`): FLTK's
        // `iname` parameter defaults to `fl_filename_name(name)` when
        // no separate icon label was set via `Fl_Window::iconlabel()`
        // -- see `fl.window.Window.iconlabel()`'s own doc comment.
        // Factored into applyWindowLabel() below so the same
        // property-writing logic also backs a *live* title update once
        // the window is already shown -- see that function's own doc
        // comment.
        applyWindowLabel(xid, win.label(), win.iconlabel());

        // Set the class property, which controls the icon used --
        // ported from make_xid()'s own `if (win->xclass())` block
        // (Fl_x.cxx). WM_CLASS
        // is two NUL-terminated strings concatenated: the "instance"
        // name (xclass() verbatim) followed by a capitalized "class"
        // name, including FLTK's own specific quirk for a leading
        // 'x' -- capitalizing *two* letters, not one (matching the
        // traditional X11 naming convention for programs starting with
        // 'x': "xterm"'s class is "XTerm", not "Xterm").
        if (win.xclass().length)
        {
            import std.ascii : toUpper;

            string xclass = win.xclass();
            char[] classVersion = xclass.dup;
            classVersion[0] = cast(char) toUpper(classVersion[0]);
            if (classVersion[0] == 'X' && classVersion.length > 1)
                classVersion[1] = cast(char) toUpper(classVersion[1]);

            ubyte[] buffer;
            buffer.reserve(xclass.length + classVersion.length + 2);
            buffer ~= cast(const(ubyte)[]) xclass;
            buffer ~= 0;
            buffer ~= cast(const(ubyte)[]) classVersion;
            buffer ~= 0;
            XChangeProperty(display_, xid, XA_WM_CLASS, XA_STRING, 8, PropModeReplace,
                buffer.ptr, cast(int) buffer.length);
        }

        // _NET_WM_ICON -- ported from Fl_X11_Window_Driver::set_icons()
        // (Fl_x.cxx), called at this same point in make_xid() (right
        // after WM_CLASS). See setIcons()'s own doc comment for the
        // full mechanism.
        setIcons(win);

        // WM_HINTS input-focus negotiation. Ported from make_xid()'s own
        // `XWMHints *hints = XAllocWMHints(); hints->input = True;
        // hints->flags = InputHint; ... XSetWMHints(...); XFree(hints);`
        // (Fl_x.cxx) -- `input = True` tells the window manager this
        // client relies on it to call `XSetInputFocus()` directly
        // (rather than the `WM_TAKE_FOCUS` protocol this port doesn't
        // implement), which is what most WMs assume by default anyway
        // when no WM_HINTS property exists at all, but a strict
        // ICCCM-following WM is free to *not* assume that -- sending
        // this explicitly removes the ambiguity, matching FLTK's
        // own unconditional behavior for every top-level window.
        // The `StateHint`/`IconicState` branch backs
        // `show_next_window_iconic()`, matching FLTK's own block --
        // see `fl.core.showNextWindowIconic_` and
        // `fl.window.Window.iconize()`'s own doc comment for the full
        // mechanism. Still not ported: the `IconPixmapHint`/
        // `icon_pixmap` legacy fallback (this port's `setIcons()` only
        // sends the modern `_NET_WM_ICON` property, matching every WM
        // this port targets).
        {
            XWMHints* hints = XAllocWMHints();
            hints.input = True;
            hints.flags = InputHint;
            if (fl.core.showNextWindowIconic_)
            {
                hints.flags |= StateHint;
                hints.initial_state = IconicState;
                fl.core.showNextWindowIconic_ = false;
            }
            XSetWMHints(display_, xid, hints);
            XFree(hints);
        }

        // Ported from Fl_X::make_xid()'s own `win->non_modal() && xp->next
        // && !fl_disable_transient_for` block (src/Fl_x.cxx): tells the
        // window manager win is a dialog-like window logically owned by
        // some other already-shown top-level window. `rec.next` (like
        // FLTK's own `xp->next`) can now be *any* kind of window
        // record -- including a subwindow's, now that those share this
        // same list -- so this walks up via `.window()`/`.parent()` to
        // that record's real top-level ancestor first (matching
        // FLTK's own identical `while (wp->parent()) wp =
        // wp->window();` walk, which existed in FLTK for exactly
        // this reason even before this port had any subwindows to
        // trigger it). Most window managers use WM_TRANSIENT_FOR to keep
        // a transient window stacked above/with its owner and to
        // position it sensibly; appending _NET_WM_STATE_MODAL
        // additionally marks it as a modal dialog under the EWMH spec.
        // Confirmed via live testing against real FLTK (fvwm):
        // this -- not any X-server-level grab -- is what makes a modal
        // dialog visually stay on top and the window behind it
        // un-raisable; fl.core.modal() (set just below) is the separate,
        // in-process mechanism that makes it *input*-exclusive.
        //
        // Matches FLTK's real condition exactly: `win->non_modal() &&
        // xp->next && !fl_disable_transient_for` (`Fl_x.cxx`) --
        // `Fl_Window::non_modal()` is a combined check, true for
        // *either* the `MODAL` or `NON_MODAL` flag
        // (`fl.window.Window.nonModal()`), not `modal()` alone --
        // Fluid's own "Tools" panel window (`function_panel.fl`'s
        // `non_modal` flag on `widgetbin_panel`) is a real consumer of
        // the `NON_MODAL`-only case, which needs the title-bar-less/
        // utility-style WM decoration most window managers give a
        // `WM_TRANSIENT_FOR` window even without `_NET_WM_STATE_MODAL`.
        // The `_NET_WM_STATE_MODAL` atom below stays gated on
        // `win.modal()` specifically -- only the outer
        // `XSetTransientForHint()` call applies to both flags.
        if (win.nonModal() && rec.next !is null)
        {
            FlWindow wp = rec.next.widget;
            while (wp.parent !is null) wp = wp.window();
            XSetTransientForHint(display_, xid, wp.xid());
            if (win.modal())
                XChangeProperty(display_, xid, netWmState_, XA_ATOM, 32, PropModeAppend,
                    cast(const(ubyte)*) &netWmStateModal_, 1);
        }
    }

    XMapWindow(display_, xid);
    if (!isSubwindow)
    {
        // Explicit raise: most window managers also do this
        // automatically on map, but not all focus policies guarantee it
        // (e.g. strict "click to focus" without auto-raise-on-map) --
        // without this, a second window created while an earlier one is
        // already on screen (e.g. fl.ask's modal dialogs) can end up
        // fully hidden behind it, technically mapped but never visible.
        // First surfaced via smoke-tests/ask.d, the first smoke test to
        // layer a window on top of an already-visible one. Not relevant
        // to a subwindow (no window manager stacking decision involved
        // at all -- its stacking position among its X11 siblings is
        // whatever XCreateWindow() gave it, which is already correct).
        XRaiseWindow(display_, xid);
    }
    // Force a round-trip so the server has actually processed the map
    // request (as opposed to XFlush(), which only guarantees it was
    // *sent*) before anything calls XSetInputFocus() on this window --
    // see installErrorHandler()'s doc comment for the BadMatch race
    // this closes most of, and why a plain XFlush() wasn't enough.
    XSync(display_, False);

    win.markShown(xid);

    // Ported from Fl_X::set_xid()'s own `if (win->modal()) {Fl::modal_
    // = win; fl_fix_focus();}` (src/Fl_x.cxx), right after the raw X
    // window is created -- the real enforcement point for fl.core's
    // modal() tracker (see that function's own doc comment). Not in
    // fl.window.Window.show() itself, matching FLTK keeping this
    // entirely out of the platform-independent Fl_Window::show().
    if (win.modal())
    {
        fl.core.modal(win);
        fl.core.fixFocus(win);
    }

    win.handle(Event.show);
    win.redraw();
}

/**
 * Re-sends win's WM_NORMAL_HINTS if it's currently shown -- the direct
 * equivalent of FLTK's `Fl_Window_Driver::size_range()`/
 * `use_border()` (`{ if (shown()) sendxjunk(); }`, Fl_x.cxx), called
 * from `fl.window.Window.sizeRange()` after it records a new range.
 * Package-visible: only fl.window should call this (mirroring how only
 * fl.window drives the rest of this module's `FlWindow`-taking API).
 */
package(fl) void sizeRangeChanged(FlWindow win)
{
    if (win.shown()) sendSizeHints(win, win.xid());
}

/**
 * Computes win's on-screen decorated size (window content plus the
 * reparenting window manager's own frame), backing
 * `fl.window.Window.decoratedW()`/`decoratedH()`. Ported from
 * `Fl_X11_Window_Driver::decorated_win_size()`
 * (`src/drivers/X11/Fl_X11_Window_Driver.cxx`): finds the WM frame
 * window via `XQueryTree()` (a reparenting WM inserts itself as win's
 * X-level parent) and compares its `XGetWindowAttributes()` size
 * against win's own. `w`/`h` are always set to win's own w()/h() as a
 * fallback; the return value tells the caller whether real WM-frame
 * dimensions were found (matching FLTK's `true_sides` -- `false`
 * means "frame size unavailable", not "no frame exists").
 *
 * Returns `false` (leaving `w`/`h` at win's own w()/h()) whenever no
 * WM frame can be identified: win isn't shown()/border()ed/visible(),
 * is a subwindow (parent() !is null, meaningless for a WM frame query),
 * or the window manager doesn't reparent at all (some compositors
 * report the queried window's X parent as root itself, exactly like
 * FLTK's own Compiz note).
 *
 * The DPI-scale-factor division FLTK applies
 * (`Fl::screen_driver()->scale(nscreen)`) is real: `w`/`h` are divided
 * back down to FLTK units at the very end, matching FLTK's own `w =
 * attributes.width / s;`.
 */
package(fl) bool decoratedWinSize(FlWindow win, out int w, out int h)
{
    w = win.w();
    h = win.h();
    if (!win.shown() || win.parent() !is null || !win.border() || !win.visible())
        return false;

    Window root, parent;
    Window* children;
    uint n = 0;
    Status status = XQueryTree(display_, win.xid(), &root, &parent, &children, &n);
    if (status != 0 && n) XFree(children);
    // Some compositors (e.g. Compiz) don't reparent at all -- root and
    // parent come back identical, and there's no frame window to measure.
    if (status == 0 || root == parent) return false;

    XWindowAttributes attributes, wAttributes;
    XGetWindowAttributes(display_, parent, &attributes);
    XGetWindowAttributes(display_, win.xid(), &wAttributes);

    // Sometimes very wide window borders are reported -- ignore them,
    // matching FLTK exactly.
    bool trueSides = false;
    if (attributes.width - wAttributes.width >= 20)
    {
        attributes.height -= (attributes.width - wAttributes.width);
        attributes.width = wAttributes.width;
    }
    else if (attributes.width > wAttributes.width)
    {
        trueSides = true;
    }

    float scale = screenScale(win.screenNum());
    w = cast(int)(attributes.width / scale);
    h = cast(int)(attributes.height / scale);
    return trueSides;
}

/**
 * Captures a real screenshot of win's window-manager-drawn frame, for
 * `fl.widget_surface.WidgetSurface.drawDecoratedWindow()`. Ported from
 * `Fl_X11_Window_Driver::capture_titlebar_and_borders()`
 * (`src/drivers/X11/Fl_X11_Window_Driver.cxx`), folded together with
 * the `allow_outside` (decoration-capture) branch of
 * `Fl_X11_Screen_Driver::read_win_rectangle()` it calls into --
 * reusing `fl.draw.readPixelsFromDrawable()`'s already-real
 * `XGetImage()`-based pixel reader directly on the WM's reparenting
 * frame window's own XID, rather than re-deriving a second XGetImage
 * path.
 *
 * **Caller contract, matching FLTK's own call site exactly**:
 * only call this when `win.shown() && win.border() && win.parent()
 * is null` already holds (`drawDecoratedWindow()` checks this before
 * calling in) -- this function doesn't re-check those itself, same as
 * `capture_titlebar_and_borders()` doesn't.
 *
 * **Faithfully reproduces a real FLTK asymmetry, not a port gap**:
 * FLTK's own X11 driver only ever populates the *top* image out of
 * the four (top/left/bottom/right) `draw_decorated_window()` accepts
 * -- left/right/bottom stay permanently null on Linux (only the
 * Windows/Cocoa drivers populate all four). What FLTK calls "top"
 * is really "however much of the reparenting frame window's own
 * pixels can be read in one shot": for a window manager with only a
 * thin title bar and no wide side borders, that's a thin strip
 * scaled to the content width; for a "true sides" WM (wide side
 * borders too, the same condition `decoratedWinSize()`'s own
 * `trueSides` detects), it's the *entire* frame rectangle, stretched
 * to cover the full decorated size when drawn -- FLTK's own way
 * of approximating a themed border it can't otherwise decompose into
 * separate strips.
 *
 * Re-reads `parent`'s attributes directly here (a second
 * `XGetWindowAttributes()` call) for `ww`/`hh`, matching FLTK's own
 * version, which always makes this same second read -- rather than
 * reusing `decoratedWinSize()`'s own `w`/`h` out-values, since those
 * are divided back down to FLTK units (matching FLTK's own
 * `w = attributes.width / s`) while the `XGetImage()`-based read below
 * genuinely needs real, undivided device pixels. Only
 * `decoratedWinSize()`'s `trueSides` return value is still reused from
 * that call.
 *
 * Returns `null` whenever there's nothing to capture: no WM frame
 * geometry can be determined, or `decoratedH() == h()` (no visible
 * decoration at all, matching FLTK's own early-exit check).
 */
package(fl) RGBImage captureTitlebarImage(FlWindow win)
{
    if (win.decoratedH() == win.h()) return null;

    Window xid = win.xid();
    Window root, parent;
    Window* children;
    uint n = 0;
    if (XQueryTree(display_, xid, &root, &parent, &children, &n) == 0) return null;
    if (n) XFree(children);

    int wsides, htop;
    Window childWin;
    if (XTranslateCoordinates(display_, xid, parent, 0, 0, &wsides, &htop, &childWin) == 0)
        return null;

    int dummyW, dummyH;
    bool trueSides = decoratedWinSize(win, dummyW, dummyH);

    // Real device-pixel frame size, read directly rather than reused
    // from decoratedWinSize() above (see this function's own doc
    // comment's Phase 2 correction) -- readPixelsFromDrawable() below
    // needs real device pixels.
    XWindowAttributes attributes;
    XGetWindowAttributes(display_, parent, &attributes);
    int ww = attributes.width, hh = attributes.height;

    if (!trueSides) htop -= wsides;
    if (htop <= 0) return null;

    int capX, capY, capW, capH;
    if (trueSides)
    {
        capX = 1;
        capY = 1;
        capW = ww - 2;
        capH = hh - 2;
    }
    else
    {
        capX = wsides;
        capY = wsides;
        capW = ww - 1;
        capH = htop;
    }
    if (capW <= 0 || capH <= 0) return null;

    auto pixels = fldraw.readPixelsFromDrawable(parent, capX, capY, capW, capH);
    if (pixels is null) return null;

    // The final scale() target size is FLTK units (it's what tells the
    // resulting RGBImage its own "logical" display size) -- decoratedW()/
    // decoratedH()/w() already are; `htop` (from XTranslateCoordinates,
    // real device pixels) needs dividing by scale first, matching
    // FLTK's own `top->scale(w(), htop / s, 0, 1)` in this same
    // `!true_sides` branch.
    auto img = new RGBImage(pixels, capW, capH, 3);
    if (trueSides) img.scale(win.decoratedW(), win.decoratedH(), 0, 1);
    else img.scale(win.w(), cast(int)(htop / screenScale(win.screenNum())), 0, 1);
    return img;
}

/**
 * Writes win's size-range constraints (fl.window.Window.sizeRange()) to
 * its X11 window as WM_NORMAL_HINTS, so a cooperating window manager
 * actually enforces them on interactive resize. Ported from the
 * WM_NORMAL_HINTS half of `Fl_X11_Window_Driver::sendxjunk()`
 * (Fl_x.cxx) -- named differently here since "junk" doesn't describe
 * what's left after trimming it down to just this piece.
 *
 * The Motif `_MOTIF_WM_HINTS` half of FLTK's `sendxjunk()` is
 * ported separately, see `sendMotifWmHints()` right below this
 * function. The `force_position()`-driven
 * `USPosition`/x/y hint is real too (see the `if (win.forcePosition())`
 * block below). The DPI-scale factor `s` sendxjunk() multiplies every
 * dimension by is real too -- see the
 * scaling below, ported from `hints->min_width = s * minw;` et al.,
 * including sendxjunk()'s own "only scale the resize increment if `s`
 * is a whole number" rule (a fractional increment isn't representable
 * as an integer X11 hint at all, so FLTK zeroes it out rather than
 * rounding it into a wrong value).
 *
 * Also deliberately different from FLTK: sendxjunk() runs
 * unconditionally from make_xid() because `Fl_Window::show()` always
 * calls `default_size_range()` first, which guarantees min/max are
 * already populated with *something* sensible (either the window's
 * exact current size, or a size computed from its resizable() widget)
 * even if the caller never called `sizeRange()` explicitly.
 * `default_size_range()`'s resizable()-widget-inspecting algorithm
 * isn't ported (a separate, non-trivial piece of FLTK's Fl_Window.H
 * surface -- see PORTING.md), so without this guard a window that never
 * called sizeRange() would hit this function with min==max==0 and tell
 * the window manager to pin it at a fixed 0x0 size, which is worse than
 * sending no hints at all. Callers (createWindow()/sizeRangeChanged())
 * both only get here when getSizeRange() reports true, so this is safe
 * to assume unconditionally within the function body itself.
 */
private void sendSizeHints(FlWindow win, Window xid)
{
    int minw, minh, maxw, maxh, dw, dh;
    bool aspect;
    if (!win.getSizeRange(&minw, &minh, &maxw, &maxh, &dw, &dh, &aspect))
        return;

    float scale = screenScale(win.screenNum());

    XSizeHints hints;
    hints.min_width = cast(int)(scale * minw);
    hints.min_height = cast(int)(scale * minh);
    hints.max_width = cast(int)(scale * maxw);
    hints.max_height = cast(int)(scale * maxh);
    if (cast(int) scale == scale)
    {
        hints.width_inc = cast(int)(scale * dw);
        hints.height_inc = cast(int)(scale * dh);
    }
    else
    {
        hints.width_inc = 0;
        hints.height_inc = 0;
    }
    hints.win_gravity = StaticGravity;

    if (hints.min_width != hints.max_width || hints.min_height != hints.max_height)
    {
        // Resizable.
        hints.flags = PMinSize | PWinGravity;
        if (hints.max_width >= hints.min_width || hints.max_height >= hints.min_height)
        {
            hints.flags = PMinSize | PMaxSize | PWinGravity;
            // Unfortunately X can't express "only one dimension has a
            // max" -- guess a value for the other one from the screen
            // size, matching FLTK's own Fl::w()/Fl::h() fallback
            // (see XDisplayWidth()/XDisplayHeight()'s doc comment for
            // why this port reaches for those instead).
            if (hints.max_width < hints.min_width)
                hints.max_width = XDisplayWidth(display_, screen_);
            if (hints.max_height < hints.min_height)
                hints.max_height = XDisplayHeight(display_, screen_);
        }
        if (hints.width_inc && hints.height_inc)
            hints.flags |= PResizeInc;
        if (aspect)
        {
            // X insists the aspect-ratio corner sits on the line
            // between min and max -- FLTK's own "stupid X!" comment
            // -- so both corners just reuse the minimum size.
            hints.min_aspect.x = hints.max_aspect.x = hints.min_width;
            hints.min_aspect.y = hints.max_aspect.y = hints.min_height;
            hints.flags |= PAspect;
        }
    }
    else
    {
        // Fixed size.
        hints.flags = PMinSize | PMaxSize | PWinGravity;
    }

    // `win.forcePosition()` used to have no effect at all -- `Flag.
    // forcePosition` was being *set* (by `resize()`'s own move-tracking
    // and `fl.core.transientScaleDisplay()`'s scale indicator, which
    // needs its exact centered position honored) but nothing ever
    // *read* it back, so a window manager (fvwm, in the reported case)
    // was always free to auto-place the window whichever open spot it
    // liked instead. Ported from `sendxjunk()`'s own `if
    // (force_position()) { hints->flags |= USPosition; hints->x =
    // s*w->x(); hints->y = s*w->y(); }` -- `x()`/`y()` scaled the same
    // way every other dimension in this function already is.
    if (win.forcePosition())
    {
        hints.flags |= USPosition;
        hints.x = cast(int)(scale * win.x());
        hints.y = cast(int)(scale * win.y());
    }

    XSetWMNormalHints(display_, xid, &hints);
}

/**
 * Writes the `_MOTIF_WM_HINTS` property requesting no window-manager
 * decorations (border/titlebar/close button/etc) for xid -- the
 * `!w->border()` half of FLTK's `sendxjunk()` (Fl_x.cxx; see
 * `sendSizeHints()`'s own doc comment for the other half). Needed for
 * the menu family's popup windows, which must appear undecorated.
 *
 * Simplified relative to FLTK in two ways, both because this port
 * only ever calls this for popup windows (never for an ordinary
 * decorated-then-undecorated top-level window):
 *  - Always sends `functions = 0` (no MWM_FUNC_* bits at all) rather
 *    than FLTK's resizable-vs-fixed-size branch, since a popup
 *    window here is never resizable in the first place.
 *  - `_MOTIF_WM_HINTS` alone, not FLTK's combined
 *    `if (Fl::grab()) { ...; if (!win->border()) {override_redirect
 *    = 1; ...} }` (border-off + an active real X grab together trigger
 *    override-redirect FLTK). This port's simplified grab (see
 *    fl.core's module comment) isn't a real `XGrabPointer`/
 *    `XGrabKeyboard()` call, so there's no equivalent condition to hang
 *    override-redirect off of -- the popup stays a normal (if
 *    undecorated) window instead. Most window managers still honor
 *    `_MOTIF_WM_HINTS` on an ordinary window, but this is a real,
 *    documented behavioral gap from FLTK's actual popup windows
 *    (which are also override-redirect, bypassing window-manager
 *    placement/focus/stacking decisions entirely): expect possible
 *    window-manager quirks (a taskbar entry, click-to-focus requiring
 *    an extra click, unexpected stacking) that FLTK's real menus
 *    don't have. Revisit with real override-redirect support if this
 *    proves troublesome in practice.
 */
private void sendMotifWmHints(Window xid)
{
    enum long mwmHintsDecorations = 2; // MWM_HINTS_DECORATIONS
    c_long[5] prop = [mwmHintsDecorations, 0, 0, 0, 0]; // flags, functions, decorations, input_mode, status
    XChangeProperty(display_, xid, motifWmHints_, motifWmHints_, 32, PropModeReplace,
        cast(const(ubyte)*) prop.ptr, 5);
}

/**
 * Packs a list of `RGBImage`s into the `_NET_WM_ICON` property's own
 * wire format -- a flat `CARDINAL[]` array, each icon stored back to
 * back as `[width, height, then width*height pixels]`, each pixel a
 * single 32-bit `0xAARRGGBB` value. Ported from the static
 * `icons_to_property()` (`src/Fl_x.cxx`), simplified in the same
 * direction as `fl.draw`'s own image primitives: no `data_w()`/`w()`
 * distinction to handle (no display-scale concept anywhere in this
 * port, so they're always equal), so this reads `img.w()`/`img.h()`
 * directly rather than FLTK's scale-aware `data_w()`/`data_h()` (and
 * the `image->copy()` fallback FLTK needs when they'd otherwise
 * differ).
 *
 * **Element type is `c_long`, not `uint`**: despite `format=32`
 * nominally meaning "32-bit values," Xlib's actual C ABI for
 * `XChangeProperty()` reads
 * `nelements * sizeof(long)` bytes from the given pointer (`long` being
 * the historical "at least 32 bits" portability type the X11 protocol
 * headers still use) -- 8 bytes per element on a 64-bit Linux target,
 * not 4. A `uint[]`-backed buffer here would undersize the buffer by
 * half what `XChangeProperty()` actually reads, so the server would
 * receive the correct first ~half of the data followed by garbage read
 * from adjacent heap memory (or an out-of-bounds page fault) --
 * malformed enough to bring down the window manager/compositor reading
 * it back. This module's own *other* `format=32` `XChangeProperty()`
 * calls follow the same convention (`c_long pid` for `_NET_WM_PID`,
 * `c_long[5] prop` for `_MOTIF_WM_HINTS`); see CLAUDE.md's
 * `project_xchangeproperty_format32_clong_bug` note for the general
 * bug class this avoids.
 */
private c_long[] iconsToProperty(const(RGBImage)[] icons)
{
    size_t sz = 0;
    foreach (img; icons) sz += 2 + img.w() * img.h();

    auto data = new c_long[sz];
    size_t idx = 0;
    foreach (img; icons)
    {
        data[idx++] = img.w();
        data[idx++] = img.h();

        int stride = img.ld() ? img.ld() : img.w() * img.d();
        int extra = stride - img.w() * img.d();
        auto bytes = img.array;
        size_t pos = 0;
        foreach (y; 0 .. img.h())
        {
            foreach (x; 0 .. img.w())
            {
                uint pixel;
                switch (img.d())
                {
                case 1:
                    pixel = (0xffu << 24) | (bytes[pos] << 16) | (bytes[pos] << 8) | bytes[pos];
                    break;
                case 2:
                    pixel = (cast(uint) bytes[pos + 1] << 24) | (bytes[pos] << 16)
                        | (bytes[pos] << 8) | bytes[pos];
                    break;
                case 4:
                    pixel = (cast(uint) bytes[pos + 3] << 24) | (bytes[pos] << 16)
                        | (bytes[pos + 1] << 8) | bytes[pos + 2];
                    break;
                default: // 3 (RGB) and any other depth alike -- fully opaque
                    pixel = (0xffu << 24) | (bytes[pos] << 16) | (bytes[pos + 1] << 8) | bytes[pos + 2];
                    break;
                }
                data[idx++] = cast(c_long) pixel;
                pos += img.d();
            }
            pos += extra;
        }
    }
    return data;
}

/**
 * (Re)writes a top-level window's `_NET_WM_ICON` property -- ported
 * from `Fl_X11_Window_Driver::set_icons()` (`Fl_x.cxx`). Uses `win`'s
 * own icons (`fl.window.Window.iconsForWM()`) if it has any, else the
 * process-wide default list (`FlWindow.defaultIconsForWM()`), matching
 * FLTK's identical `icon_ && icon_->count` fallback exactly.
 * Called once at window-creation time (`createWindow()`, top-level
 * windows only, same gate as `WM_CLASS`/the title properties) and
 * again by `Window.icon()`/`icons()` whenever called on an
 * already-`shown()` window, matching FLTK's own "immediately
 * re-push if the X resource already exists" behavior. Deliberately
 * not ported: the legacy `XWMHints.icon_pixmap` single-bitmap
 * mechanism FLTK also sets alongside this -- superseded by
 * `_NET_WM_ICON` (which virtually every modern desktop honors) and
 * tied to the equally-deliberately-unported deprecated `Fl_Window::
 * icon(const void*)` raw-pixmap-ID API (see `fl.window`'s own row).
 * A window with no icons at all (neither its own nor any default)
 * still gets the property set to a zero-length array, matching
 * FLTK's own unconditional `XChangeProperty()` call regardless of
 * count -- clearing out the desktop's built-in fallback icon isn't
 * this function's job to prevent.
 */
package(fl) void setIcons(FlWindow win)
{
    Window xid = 0;
    for (auto rec = first_; rec !is null; rec = rec.next)
        if (rec.widget is win) { xid = rec.xid; break; }
    if (xid == 0) return;

    auto icons = win.iconsForWM();
    if (icons.length == 0) icons = FlWindow.defaultIconsForWM();

    auto data = iconsToProperty(icons);
    XChangeProperty(display_, xid, netWmIcon_, XA_CARDINAL, 32, PropModeReplace,
        cast(const(ubyte)*) data.ptr, cast(int) data.length);
}

/**
 * Requests exclusive, system-wide delivery of pointer AND keyboard
 * events to win's real window -- the direct equivalent of FLTK's
 * `Fl_X11_Screen_Driver::grab()` (`Fl_x.cxx`), called by
 * `fl.core.grab(Widget)`. Replaces this port's earlier
 * `XSetInputFocus()`-based keyboard-only approximation with the real
 * mechanism FLTK uses: `XGrabPointer()`/`XGrabKeyboard()`, both
 * with `owner_events = True` so pointer events over any of *this app's
 * own* windows still route normally (see `fl.core.grab()`'s own doc
 * comment for why that means same-app menu-to-menu clicks still need
 * explicit handling elsewhere -- the grab alone doesn't intercept
 * those) -- while anything else (another application, or the window
 * manager's own root-window click handling, e.g. a virtual-desktop-
 * switch gesture) gets redirected to `win` instead. That's what gives
 * an open menu/modal dialog genuine OS-level "exclusive attention,"
 * matching every other real desktop app: confirmed interactively that
 * this is exactly why a window manager like fvwm can't switch virtual
 * desktops while *any* app's menu -- including its own -- is open.
 *
 * `XGrabKeyboard()` is skipped on KDE, matching FLTK's own
 * `using_kde` check there (`Fl_X11_Screen_Driver.cxx`, its own comment
 * cites FLTK bug #904 -- grabbing tends to stick on KDE).
 *
 * Uses `lastEventTime_` (the timestamp of the most recently processed
 * event) rather than `CurrentTime`, matching FLTK's own use of
 * `fl_event_time` here -- the X protocol recommends a real timestamp
 * for grab requests over the `CurrentTime` placeholder where one is
 * available, to avoid ambiguity in how the server orders the grab
 * against other recent events.
 *
 * A no-op if win isn't shown() yet (nothing real to grab against).
 */
/**
 * Blocks (briefly, and only ever called from grabPointer()) until xid is
 * actually viewable -- `XGetWindowAttributes()` reporting `IsViewable`,
 * meaning xid itself and every ancestor up to the root are mapped -- or a
 * bounded timeout elapses. This is the "wait for viewable" mechanism
 * `createWindow()`'s own `XSync()` alone can't provide (see that
 * function's doc comment): for a window a reparenting window manager
 * hasn't finished placing into its own decoration frame yet, `XSync()`
 * only guarantees the *X server* has processed this client's
 * `XMapWindow()` request -- for a window manager that has selected
 * `SubstructureRedirectMask` on the root (i.e. any real WM, for any
 * non-override-redirect window), that request is converted into a
 * `MapRequest` event delivered to the WM instead of actually mapping the
 * window; the window only becomes `IsViewable` once the WM has decided on
 * decorations/reparenting and issued its *own* `XMapWindow()` call, which
 * can take an arbitrary (WM-dependent) amount of time. Menu-popup windows
 * (override-redirect, see `createWindow()`) are already viewable by the
 * time this is ever called against them -- there's no WM redirection to
 * wait on -- so in practice this only ever actually polls for
 * non-override-redirect windows, e.g. `fl.ask`'s modal dialogs.
 *
 * Called by `grabPointer()` right before `XGrabPointer()`/
 * `XGrabKeyboard()` -- both silently return `GrabNotViewable` (a status
 * code, not a protocol error, unlike the old `XSetInputFocus()`-based
 * approach this replaced -- see `installErrorHandler()`'s doc comment)
 * if the target window isn't viewable yet, which would otherwise mean
 * the grab just silently fails to take effect with nothing to report it.
 * Polling `XGetWindowAttributes()` (rather than waiting for a
 * `MapNotify` event via `XNextEvent()`) is deliberate: it doesn't touch
 * this port's single event queue at all, so it can't accidentally
 * consume/reorder an unrelated real event out from under the main loop.
 * Bounded at 200ms (20 polls, 10ms apart) so a WM that never maps the
 * window can't hang the caller forever; giving up silently after the
 * timeout is fine, since the worst case is exactly the pre-existing
 * behavior this was added to improve on (grab may silently not take
 * effect).
 */
private void waitViewable(Window xid)
{
    import core.thread : Thread;
    import core.time : msecs;

    XWindowAttributes attrs;
    foreach (_; 0 .. 20)
    {
        XSync(display_, False);
        if (XGetWindowAttributes(display_, xid, &attrs) != 0 && attrs.map_state == IsViewable)
            return;
        Thread.sleep(10.msecs);
    }
}

package(fl) void grabPointer(FlWindow win)
{
    if (!win.shown()) return;
    openDisplay();

    Window xid = win.xid();
    waitViewable(xid);
    XGrabPointer(display_, xid, True,
        ButtonPressMask | ButtonReleaseMask | ButtonMotionMask | PointerMotionMask,
        GrabModeAsync, GrabModeAsync, None, 0, lastEventTime_);

    import std.process : environment;
    if (environment.get("XDG_CURRENT_DESKTOP") != "KDE")
        XGrabKeyboard(display_, xid, True, GrabModeAsync, GrabModeAsync, lastEventTime_);
}

/// ditto, in reverse -- releases both grabs. Safe to call even if no
/// grab is currently active (Xlib itself no-ops in that case) or the
/// display was never opened (this port's own guard, since nothing
/// FLTK needs to release if no window was ever shown).
package(fl) void ungrabPointer()
{
    if (display_ is null) return;
    XUngrabKeyboard(display_, lastEventTime_);
    XUngrabPointer(display_, lastEventTime_);
}

/// One physical monitor's bounding box, in root/screen coordinates --
/// the direct equivalent of FLTK's `Fl_X11_Screen_Driver::screens[]`
/// entries (`x_org`/`y_org`/`width`/`height`), minus the DPI/scale
/// fields FLTK also tracks per-screen (no display-scale concept
/// exists anywhere in this port, see `fl.draw`'s module note).
private struct ScreenInfo { int x, y, w, h; }

private ScreenInfo[] screens_;

/// Cached `_NET_WORKAREA` result -- see `initWorkArea()`'s own doc
/// comment. `w == -1` means not yet queried (mirrors FLTK's own
/// `fl_workarea_xywh[4] = { -1, -1, -1, -1 }` sentinel init).
private ScreenInfo workArea_ = ScreenInfo(0, 0, -1, 0);

/**
 * Lazily populates `screens_` -- the direct equivalent of FLTK's
 * `Fl_X11_Screen_Driver::init()`. Without this, `screenWidth()`/
 * `screenHeight()` would just return the whole X *screen*'s size via
 * `XDisplayWidth()`/`XDisplayHeight()` -- which, under Xinerama/RandR
 * (the modern, near-universal way multiple physical monitors share one
 * X screen), is the combined size of *every* monitor together, not any
 * one of them). Real monitor geometry via `XineramaQueryScreens()` when
 * the extension is active; falls back to a single synthetic "screen"
 * spanning the whole X display otherwise (no Xinerama extension, or it
 * reports inactive) -- this differs from FLTK's own fallback
 * (`ScreenCount(fl_display)`, one entry per *X11 screen*, a much rarer,
 * legacy multi-head mechanism distinct from Xinerama/RandR monitors)
 * deliberately: this port has no concept of multiple X11 screens
 * anywhere else (`screen_` above is a fixed scalar throughout), so
 * porting that fallback path would add a dimension of state nothing
 * else here understands, for a mechanism real-world X servers have
 * moved away from. Only run once per process (matching FLTK's own
 * `if (num_screens < 0) init();` guard on every query function).
 */
private void initScreens()
{
    if (screens_.length > 0) return;

    import fl.xinerama : XineramaIsActive, XineramaQueryScreens;

    if (XineramaIsActive(display_))
    {
        int n;
        auto info = XineramaQueryScreens(display_, &n);
        if (info !is null)
        {
            foreach (i; 0 .. n)
                screens_ ~= ScreenInfo(info[i].x_org, info[i].y_org, info[i].width, info[i].height);
            XFree(info);
        }
    }

    if (screens_.length == 0)
        screens_ = [ScreenInfo(0, 0, XDisplayWidth(display_, screen_), XDisplayHeight(display_, screen_))];
}

/**
 * The number of physical monitors -- the direct equivalent of
 * `Fl::screen_count()` (`Fl_Screen_Driver::screen_count()`). Always at
 * least 1 (matching FLTK's own `return num_screens ? num_screens :
 * 1;`).
 */
package(fl) int screenCount()
{
    openDisplay();
    initScreens();
    return cast(int) screens_.length;
}

/**
 * The bounding box of monitor `n` (clamped to `[0, screenCount())`,
 * matching every FLTK `screen_xywh(...)` overload's own `if (n < 0
 * || n >= num_screens) n = 0;` guard) -- the direct equivalent of
 * `Fl_X11_Screen_Driver::screen_xywh(X,Y,W,H,n)`, including its own
 * scale division (`X = screens[n].x_org / s;` et al.) --
 * `screens_[n]` itself stays real, undivided device
 * pixels (Xinerama's own native unit); only this function's *output*
 * is FLTK units.
 *
 * `screenNum(x,y)`/`screenNum(x,y,w,h)` compare against each screen's
 * own *scaled* bounds, matching FLTK's `Fl_Screen_Driver::
 * screen_num()` (shared/generic, FLTK-unit callers); the raw-Xinerama-
 * geometry comparison lives on as its own separate `screenNumUnscaled()`,
 * matching FLTK's `Fl_X11_Screen_Driver::screen_num_unscaled()` --
 * `getMouse()`, the one caller with a genuine raw device-pixel point
 * already (`XQueryPointer()`'s own result), calls that one instead. See
 * `screenNum(int,int)`'s own doc comment below for the full story.
 */
package(fl) void screenXYWH(out int x, out int y, out int w, out int h, int n)
{
    openDisplay();
    initScreens();
    if (n < 0 || n >= screens_.length) n = 0;
    float s = screenScale(n);
    x = cast(int)(screens_[n].x / s);
    y = cast(int)(screens_[n].y / s);
    w = cast(int)(screens_[n].w / s);
    h = cast(int)(screens_[n].h / s);
}

/**
 * Lazily populates `workArea_` with the primary screen's real work
 * area (excluding any panel/taskbar/dock reserved along an edge) --
 * the direct equivalent of `Fl_X11_Screen_Driver::init_workarea()`.
 * Queries the root window's `_NET_WORKAREA` property (a `CARDINAL[4]`:
 * x, y, w, h) via `XGetWindowProperty()`, but only when there's a
 * single monitor -- matching FLTK's own reasoning verbatim: with
 * several monitors, `_NET_WORKAREA` describes the combined area of
 * *all* of them together, not just the primary one, so using it there
 * would silently misreport screen 0's own work area. Falls back to
 * `screens_[0]`'s full geometry (no reserved-strip exclusion) on that
 * multi-monitor case, on any query failure, or when the returned
 * property has a zero width/height. Only runs once per process
 * (matching FLTK's own `if (num_screens < 0) init();`-style guard,
 * here keyed on `workArea_.w == -1`'s sentinel).
 */
private void initWorkArea()
{
    if (workArea_.w != -1) return;

    Atom actualType;
    int actualFormat;
    c_ulong nitems, bytesAfter;
    void* data;

    bool ok = screens_.length == 1
        && XGetWindowProperty(display_, XRootWindow(display_, screen_), netWorkarea_,
            0, 4, False, XA_CARDINAL, &actualType, &actualFormat, &nitems, &bytesAfter, &data)
            == Success
        && data !is null;

    if (ok)
    {
        scope(exit) XFree(data);
        auto xywh = cast(c_long*) data;
        if (actualType != None && actualFormat == 32 && nitems >= 4 && xywh[2] > 0 && xywh[3] > 0)
        {
            workArea_ = ScreenInfo(cast(int) xywh[0], cast(int) xywh[1],
                cast(int) xywh[2], cast(int) xywh[3]);
            return;
        }
    }

    workArea_ = screens_[0];
}

/**
 * The bounding box of monitor `n`'s *work area* -- the direct
 * equivalent of `Fl_X11_Screen_Driver::screen_work_area()`. Only the
 * primary screen (`n == 0`) can differ from `screenXYWH()`'s full
 * geometry (see `initWorkArea()`'s own doc comment for why); any other
 * screen's work area is just its full geometry, matching FLTK's
 * own `else { screen_xywh(...); }` branch exactly.
 */
package(fl) void screenWorkArea(out int x, out int y, out int w, out int h, int n)
{
    openDisplay();
    initScreens();
    if (n < 0 || n >= screens_.length) n = 0;
    if (n != 0)
    {
        screenXYWH(x, y, w, h, n);
        return;
    }
    initWorkArea();
    // workArea_ is the raw _NET_WORKAREA property value (real device
    // pixels); divided by scale here, matching FLTK's own
    // `Fl_X11_Screen_Driver::x()`/etc. (`fl_workarea_xywh[0] /
    // screens[0].scale`).
    float s = screenScale(0);
    x = cast(int)(workArea_.x / s);
    y = cast(int)(workArea_.y / s);
    w = cast(int)(workArea_.w / s);
    h = cast(int)(workArea_.h / s);
}

/**
 * Horizontal/vertical dots-per-inch of monitor `n` (clamped like
 * `screenXYWH()` above). Ported from `Fl_X11_Screen_Driver::screen_dpi()`'s
 * non-XRandR fallback path only (`src/drivers/X11/
 * Fl_X11_Screen_Driver.cxx`): `screens_[n].w`/`.h` (monitor `n`'s own
 * pixel size, from Xinerama) divided by the *default* X screen's
 * physical size in millimeters (`XDisplayWidthMM()`/`XDisplayHeightMM()`)
 * -- matching FLTK's own documented limitation verbatim ("There's no
 * way to use different DPI for different Xinerama screens", hence
 * reusing one physical-size measurement for every monitor rather than a
 * true per-monitor one). XRandR's own, more accurate per-monitor
 * physical-size query isn't a dependency of this port; `0.0` if the
 * millimeter dimension reports zero (a virtual/headless display),
 * matching FLTK's own `mm ? ... : 0.0f` guard.
 */
package(fl) void screenDpi(out float h, out float v, int n)
{
    openDisplay();
    initScreens();
    if (n < 0 || n >= screens_.length) n = 0;
    int mm = XDisplayWidthMM(display_, screen_);
    h = mm ? screens_[n].w * 25.4f / mm : 0.0f;
    mm = XDisplayHeightMM(display_, screen_);
    v = mm ? screens_[n].h * 25.4f / mm : 0.0f;
}

/**
 * The index of the monitor containing FLTK-unit point `(x,y)`, or `0`
 * if none does -- the direct equivalent of `Fl_Screen_Driver::
 * screen_num(int, int)` (shared, non-X11-specific FLTK code, ported
 * here directly since this port has no driver-class hierarchy to share
 * it through).
 *
 * Each `screens_[i]` is compared against its *own* `screenScale(i)`-
 * divided bounds, not raw Xinerama device pixels: comparing `x`/`y`
 * directly against `screens_[]`'s raw geometry would happen to work on
 * a single monitor at/near the origin (any small FLTK-unit point
 * trivially falls inside a monitor rect starting at `(0,0)`, regardless
 * of which unit either side is actually in) but would silently
 * misidentify which monitor a window is on the moment a second,
 * differently-scaled or non-origin-aligned monitor enters the picture.
 * `getMouse()` below, the one caller that genuinely has a raw device-
 * pixel point already (`XQueryPointer()`'s own result, never divided by
 * any scale), calls the separate `screenNumUnscaled()` instead --
 * matching FLTK's own `Fl_X11_Screen_Driver::screen_num_unscaled()`
 * split exactly, rather than this one function trying to serve both
 * unit conventions at once.
 */
package(fl) int screenNum(int x, int y)
{
    openDisplay();
    initScreens();
    foreach (i, ref s; screens_)
    {
        float sc = screenScale(cast(int) i);
        int sx = cast(int)(s.x / sc), sy = cast(int)(s.y / sc);
        int sw = cast(int)(s.w / sc), sh = cast(int)(s.h / sc);
        if (x >= sx && x < sx + sw && y >= sy && y < sy + sh)
            return cast(int) i;
    }
    return 0;
}

/**
 * The index of the monitor containing raw, undivided device-pixel point
 * `(x,y)`, or `-1` if the point isn't in any known monitor (a real,
 * reachable case: a point in the dead space between two differently-
 * sized/offset monitors) -- the direct equivalent of `Fl_X11_Screen_
 * Driver::screen_num_unscaled()`, FLTK's own X11-specific sibling
 * of the shared, FLTK-unit `screen_num()` above, matching its own
 * `-1`-on-no-match contract exactly (distinguishable from "genuinely on
 * screen 0", matching `fl.platform_win32`'s own sibling). Each caller
 * applies its own fallback,
 * matching FLTK's own two distinct call sites exactly: `getMouse()`
 * defaults to screen `0` (`Fl_X11_Screen_Driver::get_mouse_unscaled()`:
 * `screen >= 0 ? screen : 0`), while the `ConfigureNotify` handler
 * defaults to the window's *previous* screen instead (`Fl_x.cxx`: `if
 * (num == -1) num = olds;`) -- falling back to `0` there instead would
 * misreport an ordinary same-screen resize as a cross-screen move
 * whenever a window's centre transiently reports as "no screen" (e.g.
 * mid-drag, briefly over a monitor gap).
 */
package(fl) int screenNumUnscaled(int x, int y)
{
    openDisplay();
    initScreens();
    foreach (i, ref s; screens_)
        if (x >= s.x && x < s.x + s.w && y >= s.y && y < s.y + s.h)
            return cast(int) i;
    return -1;
}

/**
 * The index of the monitor overlapping FLTK-unit rectangle `(x,y,w,h)`
 * the most, by pixel area -- the direct equivalent of `Fl_Screen_
 * Driver::screen_num(int,int,int,int)`/`fl_intersection()` (shared
 * FLTK code, ported here directly for the same reason as the 2-arg
 * overload above). Compares against each screen's own *scaled*
 * bounds rather than raw Xinerama device pixels, same as the 2-arg
 * overload -- `createWindow()`'s own call to this (a new top-level
 * window's initial screen, from its own FLTK-unit
 * `x()`/`y()`/`w()`/`h()`) needs the same scaled comparison.
 */
package(fl) int screenNum(int x, int y, int w, int h)
{
    openDisplay();
    initScreens();
    int best = 0;
    long bestArea = 0;
    foreach (i, ref s; screens_)
    {
        float sc = screenScale(cast(int) i);
        int sx = cast(int)(s.x / sc), sy = cast(int)(s.y / sc);
        int sw = cast(int)(s.w / sc), sh = cast(int)(s.h / sc);
        int ix1 = x > sx ? x : sx;
        int ix2 = (x + w) < (sx + sw) ? (x + w) : (sx + sw);
        int iy1 = y > sy ? y : sy;
        int iy2 = (y + h) < (sy + sh) ? (y + h) : (sy + sh);
        if (ix2 <= ix1 || iy2 <= iy1) continue;
        long area = cast(long)(ix2 - ix1) * (iy2 - iy1);
        if (area > bestArea)
        {
            bestArea = area;
            best = cast(int) i;
        }
    }
    return best;
}

/**
 * Computes the current mouse position in root/screen coordinates via a
 * fresh `XQueryPointer()` round-trip -- the direct equivalent of
 * `Fl_X11_Screen_Driver::get_mouse_unscaled()`/`get_mouse()`
 * (`src/Fl_x.cxx`); called from `fl.core.getMouse()`, backing
 * FLTK's `Fl::get_mouse()`. Returns the real monitor index
 * containing the mouse. The monitor lookup (`screenNumUnscaled()`) runs on the *raw*
 * device-pixel query result -- `screens_[]`'s own geometry (from
 * Xinerama) is always real device pixels, matching FLTK's own
 * `get_mouse_unscaled()`/`screen_num_unscaled()` split -- but the `x`/
 * `y` this function actually returns to the caller are divided down to
 * FLTK units first, matching FLTK's own `get_mouse()` wrapper
 * (`xx = xx/s; yy = yy/s;`).
 */
package(fl) int getMouse(out int x, out int y)
{
    openDisplay();
    Window root = XRootWindow(display_, screen_);
    Window rootRet, childRet;
    int rawX, rawY, cx, cy;
    uint mask;
    XQueryPointer(display_, root, &rootRet, &childRet, &rawX, &rawY, &cx, &cy, &mask);
    int screen = screenNumUnscaled(rawX, rawY);
    if (screen < 0) screen = 0; // matches FLTK's own `screen >= 0 ? screen : 0`
    float s = screenScale(screen);
    x = cast(int)(rawX / s);
    y = cast(int)(rawY / s);
    return screen;
}

/// Held-state of every key on the keyboard, one bit per keycode --
/// the direct equivalent of FLTK's file-scope `fl_key_vector[32]`
/// (`Fl_x.cxx`), incrementally maintained by the KeyPress/KeyRelease
/// case below (mirroring FLTK's own incremental updates there),
/// wholesale refreshed by getKey() below (mirroring `get_key()`'s own
/// fresh `XQueryKeymap()` call), and also wholesale refreshed by
/// `case KeymapNotify:` above: without that, this vector could appear
/// stuck "held" for a key released while a *different* window had
/// focus, since that window never saw the KeyRelease. The X server
/// automatically generates a KeymapNotify right after every
/// EnterNotify/FocusIn on a window selecting `KeymapStateMask`, which
/// is exactly FLTK's own mechanism for closing this gap.
private ubyte[32] keyVector_;

/**
 * Returns whether `k` (an `fl.enumerations` keysym, or `FL_Button+n`
 * for mouse button `n`) is *recorded* as currently held, per
 * `keyVector_` above -- the direct equivalent of
 * `Fl_X11_Screen_Driver::event_key(int)` (`src/Fl_get_key.cxx`).
 * Reflects whatever `keyVector_` last held (either from the last
 * KeyPress/KeyRelease this port's event loop processed, or the last
 * getKey() call below) rather than querying the server fresh -- call
 * getKey() instead for a guaranteed-current answer. Mouse buttons
 * route through `fl.core.eventState()` instead of the key vector,
 * matching FLTK's own `k > FL_Button && k <= FL_Button+8` special
 * case (X11 can't report *held* mouse-button state through
 * `XQueryKeymap()`, only the modifier/button mask on the most recent
 * event).
 */
package(fl) bool eventKey(Keysym k)
{
    import fl.enumerations : button;

    if (k > button && k <= button + 8)
        return fl.core.eventState(8 << (k - button)) != 0;

    openDisplay();
    KeyCode i = XKeysymToKeycode(display_, cast(KeySym) k);
    if (i == 0) return false;
    return (keyVector_[i / 8] & (1 << (i % 8))) != 0;
}

/// Wholesale-refreshes keyVector_ via a fresh `XQueryKeymap()` round
/// trip, then answers exactly like eventKey() -- the direct equivalent
/// of `Fl_X11_Screen_Driver::get_key()`, backing FLTK's
/// `Fl::get_key(int)`. Unlike eventKey() alone, this is always
/// accurate regardless of whatever KeymapNotify gap left keyVector_
/// stale (see that field's own doc comment).
package(fl) bool getKey(Keysym k)
{
    openDisplay();
    XQueryKeymap(display_, &keyVector_);
    return eventKey(k);
}

/**
 * Changes win's cursor shape -- the direct equivalent of FLTK's
 * `Fl_X11_Window_Driver::set_cursor(Fl_Cursor)` (Fl_x.cxx), called from
 * fl.window.Window.cursor(). Maps fl.enumerations.Cursor shapes to the
 * classic X cursor font (XCreateFontCursor()'s `XC_*` glyph indices,
 * fl.xlib) and applies them via XDefineCursor(); cursors are cached
 * per-shape for the process lifetime as `static` locals, matching
 * FLTK's own function-local statics and its own comment on why
 * ("creating one takes 0.5ms including opening, reading, and closing
 * theme files").
 *
 * `CursorShape.none` is real too (see its own `case`'s doc comment) --
 * a fully blank/invisible cursor, built via a plain-Xlib bitmap-cursor
 * technique rather than FLTK's usual route for it (`Fl_Window::
 * cursor()`'s `fallback_cursor()`, needing real `Fl_Image` support --
 * real now, see below, but overkill for a plain blank bitmap).
 * `CursorShape.nwse`/`nesw` (see this function's own `nwse`/`nesw`
 * special case near its top) are built from the same hand-drawn-bitmap
 * `fallback_cursor()`/image-cursor route FLTK uses, since FLTK has no
 * classic-X-font glyph for a true diagonal-resize arrow either, via
 * `fl.image`/`cursor(const(RGBImage), int, int)`. `CursorShape.default_` doesn't get its own
 * FLTK-style `cursor_default` field (`default_cursor()` isn't
 * ported either) -- it resolves straight to `arrow` here, which is
 * the *net effect* of FLTK's chain for a window that never called
 * `default_cursor()` (`cursor_default` stays `FL_CURSOR_DEFAULT`,
 * which `set_cursor()` can't handle either, so `fallback_cursor()`'s
 * own default case sends it to `FL_CURSOR_ARROW` anyway).
 */

/**
 * Builds a fully transparent/invisible cursor -- an all-zero 8x8
 * bitmap used as both the source and the mask, so `XCreatePixmapCursor()`
 * paints nothing at all. `fg`/`bg` are passed as dummy (zeroed) `XColor`s
 * since the X server never actually samples a color for a source pixel
 * that's always off. Same technique FLTK's own
 * `cache_pixmap_cursor()` (Fl_x.cxx) uses to build `FL_CURSOR_NWSE`/
 * `NESW`/`NONE` from packed bitmap data on its non-Xcursor-library
 * fallback path -- this port only needs the "none" case, and a blank
 * bitmap needs no real glyph data, so this is simpler than porting that
 * whole table.
 */
private Cursor createInvisibleCursor()
{
    static immutable ubyte[8] blankBits = [0, 0, 0, 0, 0, 0, 0, 0]; // 8x8, every bit off

    Window root = XRootWindow(display_, screen_);
    Pixmap blank = XCreateBitmapFromData(display_, root, blankBits.ptr, 8, 8);

    XColor dummy;
    Cursor c = XCreatePixmapCursor(display_, blank, blank, &dummy, &dummy, 0, 0);

    XFreePixmap(display_, blank);
    return c;
}

/**
 * Issues the real X11 call to move/resize a *shown* top-level window --
 * ported from the tail end of `Fl_X11_Window_Driver::resize()`
 * (`Fl_x.cxx`, the actual `XMoveResizeWindow()`/`XResizeWindow()`/
 * `XMoveWindow()` calls; the surrounding echo-prevention/bookkeeping
 * logic lives in `fl.window.Window.resize()`, which calls this only
 * once it's determined the call is application-initiated, not an
 * echo of a `ConfigureNotify` -- see that override's own doc comment
 * for the full mechanism). `isMove`/`isResize` select which of the
 * three calls applies, matching FLTK's own branching exactly. A
 * no-op if `win` has no real X window yet (not shown).
 *
 * `x`/`y`/`w`/`h` arrive here in FLTK units (whatever `fl.window.
 * Window.resize()` was called with) and are scaled to real device
 * pixels right before each X call, matching FLTK's own `rint(X*s)`/
 * `W*s` at this exact call site.
 */
/**
 * `exactDevX`/`exactDevY` (default `int.min`, meaning "no override"):
 * when given, used directly as the device-pixel position instead of
 * recomputing one from `x`/`y` via `scaledPos()` -- needed by
 * `Window.resizeAfterScaleChange()`'s non-clamped case, which already
 * knows the window's exact current device-pixel position and wants the
 * window manager told that exact value explicitly (`XMoveResizeWindow()`,
 * not `XResizeWindow()`) rather than left to apply its own placement
 * heuristic on an unspecified position. Confirmed necessary, not just
 * defensive: a real window manager was observed resizing a window about
 * its *centre* in response to a plain, position-omitting
 * `XResizeWindow()` (see `resizeAfterScaleChange()`'s own doc comment).
 */
package(fl) void resizeWindow(FlWindow win, int x, int y, int w, int h, bool isMove, bool isResize,
    int exactDevX = int.min, int exactDevY = int.min)
{
    if (win.xid() == 0) return;
    float scale = screenScale(win.screenNum());
    int sx = exactDevX != int.min ? exactDevX : scaledPos(x, scale);
    int sy = exactDevY != int.min ? exactDevY : scaledPos(y, scale);
    uint ww = scaledDim(w, scale);
    uint wh = scaledDim(h, scale);
    if (isResize)
    {
        if (isMove)
            XMoveResizeWindow(display_, win.xid(), sx, sy, ww, wh);
        else
            XResizeWindow(display_, win.xid(), ww, wh);
    }
    else
    {
        XMoveWindow(display_, win.xid(), sx, sy);
    }
}

/// Verbatim ports of `src/fl_cursor_nwse.xpm`/`fl_cursor_nesw.xpm` --
/// the classic X cursor font (`XCreateFontCursor()`, what every other
/// shape in `setCursor()` uses) has no true diagonal-resize glyph, so
/// FLTK's own `fallback_cursor()` builds these two from hand-drawn
/// bitmap data via the image-cursor path instead. See `setCursor()`'s
/// own use of these, right below.
private static immutable string[] cursorNwseXpm = [
    "15 15 28 1",
    "  c None",
    ".  c #FFFFFF",
    "+  c #000000",
    "@  c #767676",
    "#  c #4E4E4E",
    "$  c #0C0C0C",
    "%  c #494949",
    "&  c #1B1B1B",
    "*  c #4D4D4D",
    "=  c #363636",
    "-  c #646464",
    ";  c #515151",
    ">  c #242424",
    ",  c #585858",
    "'  c #545454",
    ")  c #6A6A6A",
    "!  c #797979",
    "~  c #444444",
    "{  c #2E2E2E",
    "]  c #3B3B3B",
    "^  c #0A0A0A",
    "/  c #F7F7F7",
    "(  c #595959",
    "_  c #6B6B6B",
    ":  c #080808",
    "<  c #FEFEFE",
    "[  c #FCFCFC",
    "}  c #FDFDFD",
    "..........     ",
    ".++++++@.      ",
    ".+++++#.       ",
    ".++++$.        ",
    ".+++++%.       ",
    ".++&+++*.     .",
    ".+=.-+++;.   ..",
    ".>. .,+++'. .).",
    "..   .#+++,.!+.",
    ".     .~+++{++.",
    "       .]+++++.",
    "        .^++++.",
    "       /(+++++.",
    "      /_::::::.",
    "     <[[[[[[[[}",
];

/// ditto
private static immutable string[] cursorNeswXpm = [
    "15 15 28 1",
    "  c None",
    ".  c #FFFFFF",
    "+  c #767676",
    "@  c #000000",
    "#  c #4E4E4E",
    "$  c #0C0C0C",
    "%  c #494949",
    "&  c #4D4D4D",
    "*  c #1B1B1B",
    "=  c #515151",
    "-  c #646464",
    ";  c #363636",
    ">  c #6A6A6A",
    ",  c #545454",
    "'  c #585858",
    ")  c #242424",
    "!  c #797979",
    "~  c #2E2E2E",
    "{  c #444444",
    "]  c #3B3B3B",
    "^  c #0A0A0A",
    "/  c #595959",
    "(  c #F7F7F7",
    "_  c #080808",
    ":  c #6B6B6B",
    "<  c #FDFDFD",
    "[  c #FCFCFC",
    "}  c #FEFEFE",
    "     ..........",
    "      .+@@@@@@.",
    "       .#@@@@@.",
    "        .$@@@@.",
    "       .%@@@@@.",
    ".     .&@@@*@@.",
    "..   .=@@@-.;@.",
    ".>. .,@@@'. .).",
    ".@!.'@@@#.   ..",
    ".@@~@@@{.     .",
    ".@@@@@].       ",
    ".@@@@^.        ",
    ".@@@@@/(       ",
    ".______:(      ",
    "<[[[[[[[[}     ",
];

package(fl) void setCursor(FlWindow win, CursorShape c)
{
    if (win.xid() == 0) return; // not shown yet -- nothing to apply to

    // No classic X-cursor-font glyph exists for a true diagonal
    // resize arrow, so these two shapes are built from bitmap data
    // and set via the image-cursor path instead -- ported from
    // FLTK's own `fallback_cursor()` (`src/fl_cursor.cxx`), which
    // recurses into `Fl_Window::cursor(const Fl_RGB_Image*, int,
    // int)` the exact same way.
    if (c == CursorShape.nwse || c == CursorShape.nesw)
    {
        auto pxm = new CursorPixmap(c == CursorShape.nwse ? cursorNwseXpm : cursorNeswXpm);
        auto image = new RGBImage(pxm);
        win.cursor(image, 7, 7);
        return;
    }

    static Cursor xcArrow, xcCross, xcWait, xcInsert, xcHand, xcHelp, xcMove,
        xcNs, xcWe, xcNe, xcN, xcNw, xcE, xcW, xcSe, xcS, xcSw, xcNone;

    Cursor xc;

    switch (c)
    {
    case CursorShape.default_:
    case CursorShape.arrow:
        if (xcArrow == None) xcArrow = XCreateFontCursor(display_, XC_left_ptr);
        xc = xcArrow;
        break;
    case CursorShape.cross:
        if (xcCross == None) xcCross = XCreateFontCursor(display_, XC_tcross);
        xc = xcCross;
        break;
    case CursorShape.wait:
        if (xcWait == None) xcWait = XCreateFontCursor(display_, XC_watch);
        xc = xcWait;
        break;
    case CursorShape.insert:
        if (xcInsert == None) xcInsert = XCreateFontCursor(display_, XC_xterm);
        xc = xcInsert;
        break;
    case CursorShape.hand:
        if (xcHand == None) xcHand = XCreateFontCursor(display_, XC_hand2);
        xc = xcHand;
        break;
    case CursorShape.help:
        if (xcHelp == None) xcHelp = XCreateFontCursor(display_, XC_question_arrow);
        xc = xcHelp;
        break;
    case CursorShape.move:
        if (xcMove == None) xcMove = XCreateFontCursor(display_, XC_fleur);
        xc = xcMove;
        break;
    case CursorShape.ns:
        if (xcNs == None) xcNs = XCreateFontCursor(display_, XC_sb_v_double_arrow);
        xc = xcNs;
        break;
    case CursorShape.we:
        if (xcWe == None) xcWe = XCreateFontCursor(display_, XC_sb_h_double_arrow);
        xc = xcWe;
        break;
    case CursorShape.ne:
        if (xcNe == None) xcNe = XCreateFontCursor(display_, XC_top_right_corner);
        xc = xcNe;
        break;
    case CursorShape.n:
        if (xcN == None) xcN = XCreateFontCursor(display_, XC_top_side);
        xc = xcN;
        break;
    case CursorShape.nw:
        if (xcNw == None) xcNw = XCreateFontCursor(display_, XC_top_left_corner);
        xc = xcNw;
        break;
    case CursorShape.e:
        if (xcE == None) xcE = XCreateFontCursor(display_, XC_right_side);
        xc = xcE;
        break;
    case CursorShape.w:
        if (xcW == None) xcW = XCreateFontCursor(display_, XC_left_side);
        xc = xcW;
        break;
    case CursorShape.se:
        if (xcSe == None) xcSe = XCreateFontCursor(display_, XC_bottom_right_corner);
        xc = xcSe;
        break;
    case CursorShape.s:
        if (xcS == None) xcS = XCreateFontCursor(display_, XC_bottom_side);
        xc = xcS;
        break;
    case CursorShape.sw:
        if (xcSw == None) xcSw = XCreateFontCursor(display_, XC_bottom_left_corner);
        xc = xcSw;
        break;
    case CursorShape.none:
        // Unlike every shape above (a classic X cursor-font glyph),
        // "none" is a fully blank/invisible cursor -- built from an
        // all-zero 8x8 bitmap directly via plain Xlib, the same
        // technique FLTK's own `cache_pixmap_cursor()` (Fl_x.cxx)
        // uses for its non-Xcursor-library fallback. Deliberately not
        // reusing FLTK's *other*, more common path for this shape
        // (`fallback_cursor()`'s `Fl_Pixmap`/`Fl_RGB_Image`-based
        // route through the image-cursor `cursor(const Fl_RGB_Image*,
        // int, int)` overload, real now -- see `nwse`/`nesw`'s own
        // handling near the top of this function) -- that route would
        // be overkill for what's actually needed here: a blank bitmap
        // has no real "shape" data to speak of, so the plain-Xlib
        // bitmap-cursor route this port already uses for every other
        // shape is sufficient on its own.
        if (xcNone == None) xcNone = createInvisibleCursor();
        xc = xcNone;
        break;
    default:
        return; // unreachable for any real CursorShape value -- nwse/nesw are handled before this switch
    }

    XDefineCursor(display_, win.xid(), xc);
}

/**
 * Sets `win`'s cursor to a custom image, with `(hotx, hoty)` as the
 * active hotspot (in `image`'s own *logical* `w()`/`h()` coordinates,
 * not necessarily its native pixel dimensions -- see below). Ported
 * from `Fl_X11_Window_Driver::set_cursor(const Fl_RGB_Image*, int,
 * int)` (`Fl_x.cxx`).
 *
 * Returns `false` (matching FLTK's own `int ret` 0/1 convention,
 * just as a `bool`) for `hotx`/`hoty` out of `image`'s bounds, an
 * empty/failed image, or an unrecognized pixel depth -- the caller
 * (`fl.window.Window.cursor()`) falls back to the default arrow
 * cursor in that case, exactly matching FLTK's own
 * `if (ret) return; cursor(FL_CURSOR_DEFAULT);` tail.
 *
 * Reads `w`/`h` from `image.w()`/`h()` -- the *logical*, possibly
 * `scale()`-requested display size, not the image's native pixel-data
 * dimensions -- matching FLTK's own `set_cursor()`, which uses
 * `image->w()`/`h()` for both the hotspot bounds check and
 * `XcursorImageCreate()`'s own dimensions. Calls `image.copy(w, h)`
 * (`RGBImage.copy()`, this port's equivalent of FLTK's own
 * `Fl_Image::copy(int,int)` -- resamples when the target size differs
 * from the native data, otherwise a cheap same-size copy) to get the
 * actually-resampled pixel buffer to read from, exactly what's needed
 * when a caller (like `cursor.d`'s own `rgb.scale(16, 16)`, called on
 * a native-resolution `Fl_Pixmap`-derived image) requests a display
 * size smaller than the image's native data.
 *
 * Deliberately skipped relative to FLTK: the `normalize()` half of
 * that same pre-step. FLTK's `normalize()` exists to turn a
 * colormap-indexed `Fl_RGB_Image` into real per-pixel RGB(A) data
 * first; this port's `RGBImage` has no colormap-indexed representation
 * at all (`fl.draw`'s own "plain 8-8-8 TrueColor visual assumed, no
 * colormap/palette support" simplification, documented in that
 * module's top comment), so `copy()`'s own result is always already
 * plain per-pixel data -- there is nothing for an equivalent step to
 * normalize away.
 */
package(fl) bool setCursorImage(FlWindow win, const(RGBImage) image, int hotx, int hoty)
{
    if (win.xid() == 0) return false; // not shown yet -- nothing to apply to
    if (image is null || image.array.length == 0) return false;
    if (hotx < 0 || hotx >= image.w()) return false;
    if (hoty < 0 || hoty >= image.h()) return false;

    int w = image.w(), h = image.h();
    if (w <= 0 || h <= 0) return false;

    auto resampled = image.copy(w, h);
    if (resampled is null || resampled.array.length == 0) return false;
    int d = resampled.d();
    if (d < 1 || d > 4) return false;

    auto cursor = XcursorImageCreate(w, h);
    if (cursor is null) return false;
    scope(exit) XcursorImageDestroy(cursor);

    int lineDelta = resampled.ld() ? resampled.ld() : w * d;
    const(ubyte)* src = resampled.array.ptr;
    XcursorPixel* dst = cursor.pixels;
    for (int y = 0; y < h; y++)
    {
        const(ubyte)* row = src + y * lineDelta;
        for (int x = 0; x < w; x++)
        {
            const(ubyte)* p = row + x * d;
            ubyte r, g, b, a;
            final switch (d)
            {
            case 1: r = g = b = p[0]; a = 0xff; break;
            case 2: r = g = b = p[0]; a = p[1]; break;
            case 3: r = p[0]; g = p[1]; b = p[2]; a = 0xff; break;
            case 4: r = p[0]; g = p[1]; b = p[2]; a = p[3]; break;
            }
            // Alpha needs to be pre-multiplied for X11 -- matches
            // FLTK's own comment/math exactly.
            r = cast(ubyte)(cast(uint) r * a / 255);
            g = cast(ubyte)(cast(uint) g * a / 255);
            b = cast(ubyte)(cast(uint) b * a / 255);
            *dst = (cast(XcursorPixel) a << 24) | (cast(XcursorPixel) r << 16)
                | (cast(XcursorPixel) g << 8) | cast(XcursorPixel) b;
            dst++;
        }
    }

    cursor.xhot = hotx;
    cursor.yhot = hoty;

    Cursor xc = XcursorImageLoadCursor(display_, cursor);
    XDefineCursor(display_, win.xid(), xc);
    XFreeCursor(display_, xc);
    return true;
}

/// Cached once-per-process result of probing for the X server's SHAPE
/// extension, matching FLTK's own `Fl_X11_Window_Driver::combine_mask()`
/// static-`beenhere` probe-once pattern (just via `XShapeQueryExtension()`
/// directly rather than `dlopen()`/`dlsym()` -- see `fl.xshape`'s own module
/// comment for why a direct link is fine here). Checking is mandatory, not
/// just an optimization: calling `XShapeCombineMask()` on a server that
/// doesn't support SHAPE raises a real protocol error, and this port's own
/// installed `XErrorHandler` (see `installErrorHandler()`) only swallows one
/// narrow, unrelated `BadMatch` case -- anything else still calls Xlib's
/// default handler, which prints and `exit()`s the whole process.
private __gshared bool shapeExtensionChecked_;
private __gshared bool shapeExtensionAvailable_;

private bool shapeExtensionAvailable()
{
    if (!shapeExtensionChecked_)
    {
        shapeExtensionChecked_ = true;
        int eventBase, errorBase;
        shapeExtensionAvailable_ = display_ !is null
            && XShapeQueryExtension(display_, &eventBase, &errorBase) != 0;
    }
    return shapeExtensionAvailable_;
}

/**
 * Applies a 1-bit-per-pixel mask (`bits`, row-major, LSB first, `(w+7)/8`
 * bytes per row -- the same packing `fl.bitmap.Bitmap.array` already uses)
 * as `win`'s window shape via the X SHAPE extension. Ported from the
 * driver-agnostic core of `Fl_X11_Window_Driver::combine_mask()`
 * (`src/drivers/X11/Fl_X11_Window_Driver.cxx`): builds a throwaway `Pixmap`
 * from the packed bits via `XCreateBitmapFromData()` (the same primitive
 * `fl.platform_x11`'s own blank-cursor bitmap already uses), combines it
 * onto the window's `ShapeBounding` region with `XShapeCombineMask()`, then
 * frees the throwaway `Pixmap` -- the mask data itself is copied into the X
 * server's own SHAPE extension state, so nothing needs to be kept alive
 * afterward. A no-op if the window isn't shown yet or the server has no
 * SHAPE extension (see `shapeExtensionAvailable()` above).
 */
package(fl) void applyWindowShapeMask(FlWindow win, int w, int h, const(ubyte)[] bits)
{
    if (win.xid() == 0) return;
    if (w <= 0 || h <= 0 || bits.length == 0) return;
    if (!shapeExtensionAvailable()) return;

    Pixmap pbitmap = XCreateBitmapFromData(display_, win.xid(), bits.ptr,
        cast(uint) w, cast(uint) h);
    if (pbitmap == 0) return;
    XShapeCombineMask(display_, win.xid(), ShapeBounding, 0, 0, pbitmap, ShapeSet);
    XFreePixmap(display_, pbitmap);
}

/// `_NET_WM_STATE`'s own `data.l[0]` protocol values (EWMH spec), not
/// Xlib constants -- kept local to this module since sendWmStateEvent()
/// is the only thing that needs them.
private enum c_long netWmStateRemove = 0;
private enum c_long netWmStateAdd = 1;

/**
 * Asks the window manager to add or remove one or two `_NET_WM_STATE`
 * property values (`_NET_WM_STATE_FULLSCREEN` alone, or both
 * `_NET_WM_STATE_MAXIMIZED_VERT`/`_HORZ` together for maximize) via the
 * EWMH root-window ClientMessage protocol -- the direct equivalent of
 * FLTK's `send_wm_state_event()`/`send_wm_event()` (Fl_x.cxx;
 * FLTK keeps these as two separate functions, one a thin wrapper
 * around the other, collapsed into one here since `send_wm_event()`
 * has no other caller in this port). `prop2` defaults to `None` (0),
 * which FLTK's own general `send_wm_event()` also treats as "no
 * second property" -- harmless to send, the WM just ignores a `None`
 * atom in the list. `XSendEvent()` targets the *root* window with
 * `SubstructureNotifyMask|SubstructureRedirectMask` (rather than the
 * window itself) because that's the mask the window manager -- not our
 * own window -- selects on the root window specifically to receive
 * these requests; this is the standard EWMH client-to-WM messaging
 * pattern, not something specific to fullscreen/maximize.
 */
private void sendWmStateEvent(Window xid, bool add, Atom prop, Atom prop2 = 0)
{
    XEvent e;
    e.type = ClientMessage;
    e.xclient.window = xid;
    e.xclient.message_type = netWmState_;
    e.xclient.format = 32;
    e.xclient.data.l[0] = add ? netWmStateAdd : netWmStateRemove;
    e.xclient.data.l[1] = prop;
    e.xclient.data.l[2] = prop2;
    XSendEvent(display_, XRootWindow(display_, screen_), False,
        SubstructureNotifyMask | SubstructureRedirectMask, &e);
}

/// Ported from the `_NET_WM_FULLSCREEN_MONITORS` `send_wm_event()` call
/// site in `Fl_X11_Window_Driver::fullscreen_on()` -- same
/// ClientMessage-to-the-root-window pattern as `sendWmStateEvent()`
/// just above, just a different property/payload shape (4 monitor
/// indices instead of an add/remove flag plus 1-2 state atoms).
private void sendWmFullscreenMonitorsEvent(Window xid, int top, int bottom, int left, int right)
{
    XEvent e;
    e.type = ClientMessage;
    e.xclient.window = xid;
    e.xclient.message_type = netWmFullscreenMonitors_;
    e.xclient.format = 32;
    e.xclient.data.l[0] = top;
    e.xclient.data.l[1] = bottom;
    e.xclient.data.l[2] = left;
    e.xclient.data.l[3] = right;
    XSendEvent(display_, XRootWindow(display_, screen_), False,
        SubstructureNotifyMask | SubstructureRedirectMask, &e);
}

/**
 * Reads xid's current `_NET_WM_STATE` atom list into `states` (a
 * freshly-`.dup`'d D array, safe to keep past this call -- the
 * server-owned buffer `XGetWindowProperty()` hands back is freed via
 * `XFree()` before returning) -- the direct equivalent of FLTK's
 * `get_xwinprop()` (`Fl_x.cxx`), specialized to always request
 * `_NET_WM_STATE` rather than FLTK's general `Atom prop` parameter
 * (the only property this port ever needs to read back). `64`
 * matches FLTK's own `max_length` -- generous for a handful of
 * `_NET_WM_STATE_*` atoms, and FLTK doesn't bother following
 * `bytes_after` to fetch more either. Returns `false` (states left
 * empty) on any failure or if the property doesn't exist/isn't the
 * expected 32-bit-item format, matching `get_xwinprop()`'s own `-1`
 * returns.
 */
private bool getNetWmState(Window xid, out Atom[] states)
{
    Atom actualType;
    int actualFormat;
    c_ulong nitems, bytesAfter;
    void* data;
    int status = XGetWindowProperty(display_, xid, netWmState_, 0, 64, False,
        AnyPropertyType, &actualType, &actualFormat, &nitems, &bytesAfter, &data);
    if (status != Success) return false;
    if (data is null) return false;
    scope(exit) XFree(data);

    if (actualType == None || actualFormat != 32) return false;

    states = (cast(Atom*) data)[0 .. nitems].dup;
    return true;
}

/**
 * Turns fullscreen mode on for win -- the EWMH half of FLTK's
 * `Fl_X11_Window_Driver::fullscreen_on()` (Fl_x.cxx); called from
 * `fl.window.Window.fullscreen()`. Scoped to EWMH-supporting window
 * managers only: skips FLTK's `ewmh_supported()` capability check
 * (a `_NET_SUPPORTING_WM_CHECK` property round-trip) and its non-EWMH
 * fallback entirely (hide()+show()+`XGrabKeyboard()`, a substantially
 * hackier path for window managers old enough to predate EWMH, which
 * is effectively every window manager in real-world use today) --
 * sending the ClientMessage unconditionally is harmless even on a WM
 * that ignores it, just a no-op. `fullscreen_screens()`'s
 * `_NET_WM_FULLSCREEN_MONITORS` multi-monitor targeting is ported too,
 * backed by `fl.core.screenNum()`/`screenXYWH()`:
 * `win.fullscreenScreenTop()`/etc. (`fl.window`)
 * supply the four monitor indices, defaulting to the window's own
 * current screen (`fl.core.screenNum(win.x, win.y, win.w, win.h)`) when
 * unset, matching FLTK's own `Fl_X11_Window_Driver::fullscreen_on()`
 * fallback exactly.
 *
 * `win.setFullscreenFlag()` -- matching FLTK's own
 * `pWindow->_set_fullscreen();` inside `fullscreen_on()` -- is what
 * makes `fullscreenActive()` actually report true afterward; without
 * this call the EWMH request still works, so the window visibly goes
 * fullscreen, but `fullscreenActive()` never flips, so a second toggle
 * call keeps re-requesting fullscreen instead of calling
 * fullscreenOff().
 */
package(fl) void fullscreenOn(FlWindow win)
{
    win.setFullscreenFlag();

    int top = win.fullscreenScreenTop();
    int bottom = win.fullscreenScreenBottom();
    int left = win.fullscreenScreenLeft();
    int right = win.fullscreenScreenRight();
    if (top < 0 || bottom < 0 || left < 0 || right < 0)
    {
        int n = fl.core.screenNum(win.x(), win.y(), win.w(), win.h());
        top = bottom = left = right = n;
    }
    sendWmFullscreenMonitorsEvent(win.xid(), top, bottom, left, right);

    sendWmStateEvent(win.xid(), true, netWmStateFullscreen_);
    fl.core.dispatch(Event.fullscreen, win);
}

/// ditto, in reverse -- the EWMH half of FLTK's
/// `Fl_X11_Window_Driver::fullscreen_off()`. The EWMH branch there
/// doesn't resize the window itself either (unlike the non-EWMH
/// fallback, which does): toggling `_NET_WM_STATE_FULLSCREEN` off is
/// enough to make a cooperating window manager restore the window's
/// own pre-fullscreen geometry on its own. `win.clearFullscreenFlag()`
/// matches FLTK's `pWindow->_clear_fullscreen();` -- see
/// fullscreenOn()'s own doc comment for why this call matters.
package(fl) void fullscreenOff(FlWindow win)
{
    win.clearFullscreenFlag();
    sendWmStateEvent(win.xid(), false, netWmStateFullscreen_);
    fl.core.dispatch(Event.fullscreen, win);
}

/**
 * Turns maximize mode on for win -- the EWMH half of FLTK's
 * `Fl_X11_Window_Driver::maximize()` (Fl_x.cxx). Sends both
 * `_NET_WM_STATE_MAXIMIZED_VERT` and `_HORZ` in a single ClientMessage
 * (per the EWMH spec, `data.l[1]`/`l[2]`), matching FLTK's own
 * `send_wm_event()` call there. Scoped like `fullscreenOn()`: skips
 * FLTK's `ewmh_supported()` capability check and its non-EWMH
 * fallback (`Fl_Window_Driver::maximize()`'s manual resize-to-work-area,
 * used by window managers old enough to predate EWMH) -- sending the
 * ClientMessage unconditionally is harmless even on a WM that ignores
 * it.
 *
 * Unlike `fullscreenOn()`, this doesn't call `win.setMaximizedFlag()`
 * or `fl.core.handle()` itself -- FLTK's `Fl_Window::maximize()`
 * (not the driver) is what calls `set_flag(MAXIMIZED)`, and the X11
 * driver's `maximize()`/`un_maximize()` fire no `Fl::handle()` event at
 * all (only the `PropertyNotify` handler does -- see that case below --
 * when the WM's actual state change round-trips back).
 */
package(fl) void maximizeOn(FlWindow win)
{
    sendWmStateEvent(win.xid(), true, netWmStateMaximizedVert_, netWmStateMaximizedHorz_);
}

/// ditto, in reverse -- the EWMH half of `Fl_X11_Window_Driver::un_maximize()`.
package(fl) void maximizeOff(FlWindow win)
{
    sendWmStateEvent(win.xid(), false, netWmStateMaximizedVert_, netWmStateMaximizedHorz_);
}

/// Iconifies win's real X window -- the direct equivalent of
/// `Fl_X11_Window_Driver::iconize()` (`XIconifyWindow(fl_display,
/// fl_xid(pWindow), fl_screen)`). Backs `fl.window.Window.iconize()`.
package(fl) void iconizeWindow(FlWindow win)
{
    XIconifyWindow(display_, win.xid(), screen_);
}

/// Re-shows an already-created window: either a top-level window
/// re-raised via `Window.show()`'s "already shown" branch, or a
/// subwindow being remapped in place by `Window.handle(Event.show)`
/// after `unmapWindow()` below hid it without destroying it (the
/// direct equivalent of `Fl_X11_Window_Driver::map()`, called from
/// `Fl_Window::handle()`'s own `FL_SHOW` case).
void raiseWindow(FlWindow win)
{
    openDisplay();
    if (win.xid() != 0)
        XMapWindow(display_, win.xid());
}

/// Hides a subwindow in place without destroying its real X resource
/// or its `WindowRecord`/`Window.shown_` bookkeeping -- the direct
/// equivalent of `Fl_X11_Window_Driver::unmap()`, called from
/// `Window.handle(Event.hide)` for the common "an ancestor `FlGroup`
/// (not a `Window`) was hidden" case. Deliberately does *not* call
/// `win.handle(Event.hide)`/`fl.core.throwFocus()` the way
/// `destroyWindow()` does -- FLTK's own `unmap()` is a bare
/// `XUnmapWindow()` with no widget-tree side effects at all, since
/// nothing was actually destroyed for descendants to be notified
/// about.
void unmapWindow(FlWindow win)
{
    openDisplay();
    if (win.xid() != 0)
        XUnmapWindow(display_, win.xid());
}

/**
 * Destroys win's underlying X11 window and unlinks it from the
 * tracked-windows list. The direct equivalent of FLTK's
 * `Fl_X11_Window_Driver::hide()` + `Fl_Window_Driver::hide_common()`.
 * Destroying `win`
 * would, at the X11-protocol level, implicitly destroy every child X
 * window nested inside it anyway -- but this port's own bookkeeping
 * (each subwindow's own `WindowRecord` in `first_`, and its
 * `Window.shown_` flag) needs to be updated in lockstep, or a stale
 * record would linger forever: `run()`'s own `while (first_ !is null)`
 * loop-continuation would then wait on a window whose real X resource
 * no longer exists. So, matching FLTK's `Fl_Window_Driver::
 * hide_common()` exactly: any subwindow whose immediate window ancestor
 * (`.window()`) is `win` gets recursively, fully destroyed (via its own
 * `Window.hide()`, handling any further-nested subwindows the same way)
 * *before* `win`'s own xid is destroyed -- necessary ordering, not just
 * faithfulness for its own sake, since destroying `win`'s xid first
 * would make each subwindow's own subsequent `XDestroyWindow()` call
 * fail with a protocol `BadWindow` error (the ID would already be gone).
 * Each recursively-destroyed subwindow is immediately re-marked
 * `setVisible()` afterward (matching FLTK's own `W->set_visible()`)
 * so it reappears automatically if `win` is shown again later, rather
 * than staying permanently hidden as if the user had explicitly hidden
 * it themselves.
 */
void destroyWindow(FlWindow win)
{
    WindowRecord** pp = &first_;
    while (*pp !is null && (*pp).widget !is win)
        pp = &(*pp).next;
    if (*pp is null) return; // not currently shown

    auto rec = *pp;
    *pp = rec.next;

    // Cleared early -- matching FLTK's own Fl_X::flx pointer being
    // nulled at the very start of Fl_Window_Driver::hide_common(), well
    // before the real XDestroyWindow() call at the end of this function
    // -- so that shown() already reports false by the time win.handle(
    // Event.hide) below reaches Window.handle()'s own Event.hide guard.
    // Without this ordering, that guard would see shown() still true on
    // `win` itself and recurse right back into destroyWindow(win) a
    // second time, on a window that's still mid-teardown.
    win.markHidden();

    // Ported from Fl_Window_Driver::hide_common()'s own "recursively
    // remove any subwindows" loop (src/Fl_Window_Driver.cxx) -- see this
    // function's own doc comment for why the ordering (before `win`'s
    // own xid destruction, below) matters. Restarts the scan from the
    // head after each removal (matching FLTK's own `wi =
    // Fl_X::first;` restart) since destroying a subwindow unlinks its
    // record from `first_` out from under a normal forward iteration.
    bool restarted = true;
    while (restarted)
    {
        restarted = false;
        for (auto p = first_; p !is null; p = p.next)
        {
            if (p.widget.window() is win)
            {
                p.widget.hide();
                p.widget.setVisible();
                restarted = true;
                break;
            }
        }
    }

    // Ported from Fl_Window_Driver::hide_common()'s own `if (pWindow ==
    // Fl::modal_) {...find next still-shown modal() window...}`
    // (src/Fl_Window_Driver.cxx): re-scans the remaining tracked
    // windows (rec was already unlinked from first_ above) for another
    // still-shown modal() one and reinstates it, rather than just
    // clearing to null -- supports a modal dialog opening another
    // modal dialog on top of it correctly (the lower one regains
    // exclusivity once the upper one closes).
    if (fl.core.modal() is win)
    {
        FlWindow next;
        for (auto p = first_; p !is null; p = p.next)
            if (p.widget.modal()) { next = p.widget; break; }
        fl.core.modal(next);
    }

    // Ported from Fl_Window_Driver::hide_common()'s own `fl_throw_focus(
    // pWindow); pWindow->handle(FL_HIDE);` -- makes sure no stale
    // focus()/belowmouse()/pushed() pointer is left aimed at a widget
    // inside the window being destroyed, then cascades Event.hide
    // through the widget tree (FlGroup.handle()'s own Event.hide case
    // forwards it to every visible child, matching FLTK's identical
    // Fl_Group::handle()).
    fl.core.throwFocus(win);
    win.handle(Event.hide);

    // Only now destroy win's own real X resource -- after every
    // descendant subwindow's xid is already gone (see this function's
    // own doc comment for why that order is required, not just tidy).
    fldraw.releaseDrawable(rec.xid);
    if (rec.offscreen != 0) fldraw.freeOffscreenBuffer(rec.offscreen);
    XDestroyWindow(display_, rec.xid);
    XFlush(display_);
}

/**
 * Runs the event loop until every tracked window has been closed --
 * the direct equivalent of FLTK's `Fl::run()` (`while (Fl_X::first)
 * wait(FOREVER);`, Fl.cxx): just wait()'s own single-iteration body
 * (below), repeated until first_ is null.
 */
void run()
{
    while (first_ !is null) wait();
}

/**
 * Runs one iteration of the event loop -- the direct equivalent of
 * FLTK's `Fl::wait()` (the finer-grained entry point below
 * `run()`'s own `while (first) wait(FOREVER);` loop). Fires any due
 * timers (fl.core.processTimeouts()), repaints (flushDamage()), then
 * either processes an already-queued X event immediately
 * (XPending() > 0) or blocks in waitForEventOrTimeout() until the X
 * connection has data or the next timer is due -- whichever comes
 * first, rather than a plain blocking XNextEvent() loop, since a
 * blocking XNextEvent() would never wake up to fire a timer with no X
 * activity happening. `waitForEventOrTimeout()`
 * folds every registered `addFd()` entry into its own `select()` call
 * alongside the X connection fd, with `idleActive()` clamping that
 * `select()`'s own timeout to zero whenever an idle callback is
 * registered. `fl.core.runChecks()` (`Fl::add_check()`'s equivalent)
 * fires once per iteration, right before `runIdle()` below, matching
 * FLTK's own `do_timeouts() -> run_checks() -> run_idle()` order.
 *
 * flushDamage() runs every call regardless of what woke it up,
 * matching FLTK's own `wait()`/`Fl::flush()` split (Fl::wait()
 * always ends with a call to Fl::flush()). Without this, only a
 * genuine X Expose would repaint anything: a click could flip a Button's
 * value() and fire its callback correctly (handle()/doCallback() don't
 * need a screen to run), but the bevel would never visibly change
 * until some unrelated Expose happened to come along afterward.
 *
 * Exposed (via fl.core.wait()) specifically so the menu popup engine's
 * own nested "run until the user picks something or dismisses it" loop
 * (see fl.menu_item's pulldown()) can call it directly, exactly like
 * FLTK's `pulldown()` calling `Fl::wait()` in its own `for(;;)`
 * loop -- a real, if narrower, "process one iteration of the event
 * loop from inside handling of another event" primitive, not the
 * "collapse everything into run()" shape this module had before menus
 * needed it.
 */
void wait()
{
    fl.core.doWidgetDeletion();
    fl.core.processTimeouts();
    fl.core.runChecks();
    fl.core.runIdle();
    flushDamage();

    if (first_ is null) return;

    if (XPending(display_) > 0)
        processNextEvent();
    else
        waitForEventOrTimeout();
}

/**
 * Bounded-wait counterpart of wait() above -- the direct equivalent of
 * FLTK's `Fl::wait(double time_to_wait)` (`Fl.cxx`, forwarding to
 * `Fl_System_Driver::wait(double)` -> `poll_or_select_with_delay()`).
 * Same body as wait() (fires due timers, repaints, processes one
 * already-queued X event), but when it has to block, it blocks for at
 * most `timeToWait` seconds rather than until the next due timer --
 * `waitForEventOrTimeout()`'s own `Duration maxWait` parameter (below)
 * is exactly this: the same `select()` call, just with a second, tighter
 * upper bound folded into its own timer-driven one via `min()`.
 * Returns FLTK's own simplified two-value convention (matching this
 * port's existing `wait()`/`check()` boolean-ish returns rather than
 * FLTK's full positive/zero/negative `double`, which needs a real
 * error path this port's `select()` call doesn't distinguish): `1.0` if
 * an event was processed (either an already-queued X event or something
 * `select()` woke up for), `0.0` on a plain timeout or once every window
 * has closed.
 */
double wait(double timeToWait)
{
    fl.core.doWidgetDeletion();
    fl.core.processTimeouts();
    fl.core.runChecks();
    fl.core.runIdle();
    flushDamage();

    if (first_ is null) return 0.0;

    if (XPending(display_) > 0)
    {
        processNextEvent();
        return 1.0;
    }

    import core.time : dur;

    long us = cast(long)(timeToWait * 1_000_000.0);
    if (us < 0) us = 0;
    return waitForEventOrTimeout(dur!"usecs"(us)) ? 1.0 : 0.0;
}

/**
 * Non-blocking single iteration of the event loop -- the direct
 * equivalent of FLTK's `Fl::check()` (`Fl.cxx`: `wait(0.0); return
 * Fl_X::first != 0;`). Same body as wait() above (fires due timers,
 * repaints, processes one already-queued X event) but never blocks in
 * waitForEventOrTimeout() -- that's the whole difference between
 * "wait(0.0)" and a genuinely blocking wait(): with nothing pending,
 * this returns immediately instead of sleeping until the next event or
 * timer. Intended for callers doing their own long-running computation
 * who want to keep the UI responsive by polling this periodically,
 * exactly like FLTK's own doc comment for `Fl::check()` describes.
 * Returns whether any window is still tracked (open), matching
 * FLTK's return value.
 */
bool check()
{
    fl.core.doWidgetDeletion();
    fl.core.processTimeouts();
    fl.core.runChecks();
    fl.core.runIdle();
    flushDamage();

    if (first_ !is null && XPending(display_) > 0)
        processNextEvent();

    return first_ !is null;
}

/**
 * Blocks (via select()) until the X connection has data to read, a
 * registered fl.core.addFd() descriptor becomes ready, or the next
 * pending timer is due, whichever comes first -- the piece that lets
 * run() wake up for timers (or a caller's own fd) even with no X
 * activity happening. Not a port of any single FLTK function:
 * matches the *effect* of Fl_Unix_System_Driver::wait()'s
 * `scr_dr->poll_or_select_with_delay(time_to_wait)` call, but as a
 * direct `core.sys.posix.sys.select` call rather than routing through
 * FLTK's own poll()-vs-select() driver choice or its "the X
 * connection is just another add_fd() entry" design (FLTK registers
 * its own X connection fd through the very same Fl::add_fd() mechanism
 * a caller uses, dispatched via a generic callback array; this port
 * keeps the X connection's own handling exactly as it already was --
 * XPending()/processNextEvent() in wait()/check() above -- and folds
 * fl.core.addFd()'s registered descriptors into this select() call
 * *alongside* it, rather than unifying the two, since nothing here
 * needs poll()'s larger-fd-count scalability advantage over select()
 * and unifying would be a bigger, riskier restructuring for no present
 * benefit -- see core-roadmap item 6 for the full reasoning).
 *
 * Real `fl.core.addFd()`/`removeFd()` multiplexing: every entry from
 * `fl.core.fdEntries()` gets
 * folded into whichever of the read/write/except `fd_set`s its own
 * `when` bits ask for, and -- after `select()` returns -- each entry
 * whose fd shows up in a set it actually asked for gets its callback
 * invoked exactly once, matching FLTK's own
 * `if (fd[i].events & revents) fd[i].cb(...)` dispatch.
 *
 * A stray EINTR (e.g. from a signal), a plain timeout, or `select()`
 * returning 0 all just return early without invoking anything; the
 * caller's next loop iteration re-checks XPending() and
 * re-fires timers regardless of why select() returned.
 *
 * `select()`
 * itself is bracketed by `fl.core.unlockForWait()`/`lockForWait()`,
 * matching FLTK's own `Fl_Unix_Screen_Driver::
 * poll_or_select_with_delay()`'s `fl_unlock_function()`/
 * `fl_lock_function()` bracket around the equivalent `poll()`/
 * `select()` call: a no-op unless `fl.core.lock()` was ever called (the
 * common, single-threaded case), and otherwise what lets a worker
 * thread blocked on `fl.core.lock()` actually run while this thread is
 * idle here.
 */
private bool waitForEventOrTimeout(Duration maxWait = Duration.max)
{
    import core.sys.posix.sys.select : select, fd_set, FD_ZERO, FD_SET, FD_ISSET;
    import core.sys.posix.sys.time : timeval;
    import core.time : Duration, hours;

    Duration ttw = fl.core.idleActive()
        ? Duration.zero // Fl_System_Driver::wait(): idle active -> time_to_wait = 0.0
        : fl.core.timeToWait(hours(24)); // "no timer pending" stand-in for forever
    if (ttw < Duration.zero) ttw = Duration.zero;
    if (maxWait < ttw) ttw = maxWait; // wait(double)'s own tighter bound, if any

    fd_set rfds, wfds, efds;
    FD_ZERO(&rfds);
    FD_ZERO(&wfds);
    FD_ZERO(&efds);

    int xfd = XConnectionNumber(display_);
    FD_SET(xfd, &rfds);
    int maxfd = xfd;

    auto entries = fl.core.fdEntries();
    foreach (ref e; entries)
    {
        if (e.when & fdRead) FD_SET(e.fd, &rfds);
        if (e.when & fdWrite) FD_SET(e.fd, &wfds);
        if (e.when & fdExcept) FD_SET(e.fd, &efds);
        if (e.fd > maxfd) maxfd = e.fd;
    }

    long us = ttw.total!"usecs";
    timeval tv;
    tv.tv_sec = cast(typeof(tv.tv_sec))(us / 1_000_000);
    tv.tv_usec = cast(typeof(tv.tv_usec))(us % 1_000_000);

    fl.core.unlockForWait();
    int n = select(maxfd + 1, &rfds, &wfds, &efds, &tv);
    fl.core.lockForWait();
    if (n <= 0) return false;

    foreach (ref e; entries)
    {
        FdWhen revents = 0;
        if (FD_ISSET(e.fd, &rfds)) revents |= fdRead;
        if (FD_ISSET(e.fd, &wfds)) revents |= fdWrite;
        if (FD_ISSET(e.fd, &efds)) revents |= fdExcept;
        if (e.when & revents) e.callback(e.fd);
    }
    return true;
}

/// Ported from `Widget.damage(Damage,x,y,w,h)`'s own call into this
/// module -- the direct but
/// bounding-box-simplified equivalent of FLTK's
/// `Fl_Widget::damage(fl,X,Y,W,H)` merging a new rectangle into
/// `Fl_X::region` (`add_rectangle_to_region()`/`XRectangleRegion()`),
/// see `WindowRecord.hasDamageRegion`'s own doc comment for why a
/// bounding box is enough here. `(x,y,w,h)` arrives already clipped to
/// the window's own bounds by the caller.
package(fl) void accumulateDamage(FlWindow win, int x, int y, int w, int h)
{
    for (auto rec = first_; rec !is null; rec = rec.next)
    {
        if (rec.widget !is win) continue;
        // A whole-window damage() already happened this flush cycle --
        // stay unclipped rather than narrowing to this smaller
        // rectangle. See fullRepaintPending's own doc comment above.
        if (rec.fullRepaintPending) return;
        if (!rec.hasDamageRegion)
        {
            rec.hasDamageRegion = true;
            rec.damageX = x;
            rec.damageY = y;
            rec.damageW = w;
            rec.damageH = h;
        }
        else
        {
            int x2 = rec.damageX + rec.damageW;
            int y2 = rec.damageY + rec.damageH;
            int nx2 = x + w;
            int ny2 = y + h;
            if (x < rec.damageX) rec.damageX = x;
            if (y < rec.damageY) rec.damageY = y;
            if (nx2 > x2) x2 = nx2;
            if (ny2 > y2) y2 = ny2;
            rec.damageW = x2 - rec.damageX;
            rec.damageH = y2 - rec.damageY;
        }
        return;
    }
}

/// Backs `fl.core.captureWindow()` -- finds `win`'s real X window
/// (if shown) and reads pixels straight from it via
/// `fl.draw.readPixelsFromDrawable()`, matching FLTK's
/// `fl_capture_window()`'s "read a mapped window's own xid directly"
/// path (the simplified GL-subwindow-free, single-monitor version of
/// `Fl_Screen_Driver::traverse_to_gl_subwindows()` -- no GL subwindows
/// exist in this port to traverse). Returns `null` if `win` isn't
/// currently shown, matching FLTK's own guard.
package(fl) ubyte[] captureWindowPixels(FlWindow win, int x, int y, int w, int h)
{
    if (!win.shown()) return null;
    for (auto rec = first_; rec !is null; rec = rec.next)
        if (rec.widget is win)
            return fldraw.readPixelsFromDrawable(rec.xid, x, y, w, h, 0);
    return null;
}

/// Ported from `Widget.damage(Damage)`'s own call into this module for
/// the "whole window damaged" case -- discards any accumulated partial
/// rectangle (matches FLTK's `Fl_Widget::damage(uchar)` deleting
/// `Fl_X::region` outright for the same reason: a stale partial
/// rectangle would wrongly clip the next repaint to less than the
/// whole window).
package(fl) void clearDamageRegion(FlWindow win)
{
    for (auto rec = first_; rec !is null; rec = rec.next)
    {
        if (rec.widget is win) { rec.hasDamageRegion = false; rec.fullRepaintPending = true; return; }
    }
}

/**
 * Repaints every currently-shown window whose top-level widget has
 * pending damage(). The direct equivalent of FLTK's `Fl::flush()`
 * (Fl.cxx) -- see run()'s doc comment for why this needs to run after
 * every processed event, not just on Expose. If a window accumulated
 * a partial-damage
 * rectangle since the last flush (`accumulateDamage()` above), that
 * bounding box is pushed as a clip before the single `draw()` call for
 * that window and popped after; a window with no accumulated
 * rectangle (whole-widget damage, e.g. from `redraw()`, or a window
 * shown for the first time) draws completely unclipped, matching
 * FLTK's own `Fl_Window::flush()` (`fl_clip_region(flx_->region)`
 * where a null region means "no clip installed" -- draws to the whole
 * window either way). This is also what makes the `case Expose:`
 * handler below safe to *only* accumulate damage rather than drawing
 * synchronously per fragment: several `Expose` fragments queued
 * together (routine for a single window-uncover operation, which the X
 * server commonly splits into multiple rectangles) coalesce into
 * one accumulated bounding box and exactly one `draw()` call here,
 * instead of one full widget-tree walk per fragment.
 *
 * A `DoubleWindow` (`rec.widget.type() ==
 * doubleWindowTypeTag`) draws into an off-screen `Pixmap`
 * (`rec.offscreen`, allocated/reallocated here on first use or after a
 * resize -- see `WindowRecord.offscreen`'s own doc comment) instead of
 * straight onto the real window, then blits the result across
 * (`fldraw.copyOffscreen()`), clipped the same way the direct-to-window
 * draw above already is. Ported from the driver-agnostic core of
 * FLTK's `Fl_X11_Window_Driver::flush_double()` -- see
 * `fldraw.copyOffscreen()`'s own doc comment for why the Cairo-specific
 * bookkeeping in that function isn't relevant here. A plain `Window`
 * (or any other window type) skips all of this and draws straight to
 * its own xid.
 *
 * An `OverlayWindow`
 * (`cast(OverlayWindow) rec.widget !is null` -- it keeps `DoubleWindow`'s
 * own `type()` tag rather than a distinct one, matching FLTK's
 * choice not to introduce a new `Fl_Overlay_Window`-specific value
 * either) forces a full, unclipped backbuffer-to-window blit on every
 * flush while its overlay is active, then draws `drawOverlay()`
 * straight onto the on-screen window afterward -- ported from
 * `Fl_X11_Window_Driver::flush_overlay()`, see the inline comments
 * just below for the exact mapping. A plain `DoubleWindow` (or `Window`)
 * is unaffected by any of this.
 */
package(fl) void flushDamage()
{
    bool any = false;
    for (auto rec = first_; rec !is null; rec = rec.next)
    {
        if (rec.widget.damage())
        {
            // GlWindow gets a dedicated repaint path -- see
            // fl.gl_window.flushGlWindow()'s own doc comment for why it
            // can't share the double-buffer/overlay logic below (real
            // GLX front/back buffers, not fldtk's own offscreen-Pixmap
            // scheme).
            if (auto glWin = cast(GlWindow) rec.widget)
            {
                glWindow.flushGlWindow(glWin);
                any = true;
                continue;
            }

            bool doubleBuffered = rec.widget.type() == doubleWindowTypeTag;
            // `rec.widget.w()`/`.h()`
            // are FLTK units (logical, pre-scale) -- correct for
            // `pushClip()`/`draw()` below (both already scale
            // internally) -- but `createOffscreenBuffer()`/
            // `copyOffscreen()` are both plain `XCreatePixmap()`/
            // `XCopyArea()` wrappers with *no* internal scaling of
            // their own, so they need the already-scaled dimensions
            // passed in explicitly to match the real, already-
            // correctly-scaled on-screen X window (`createWindow()`
            // already scales the real `XCreateWindow()` call).
            // Scaled here, at the
            // buffer-allocation/blit choke point, matching every other
            // scale-aware primitive's own "scale once, at
            // a well-defined boundary" shape -- not inside
            // `createOffscreenBuffer()`/`copyOffscreen()` themselves,
            // which stay plain unscaled Xlib wrappers, matching their
            // own existing contract.
            float scale = screenScale(rec.widget.screenNum());
            int ww = cast(int) scaledDim(rec.widget.w(), scale);
            int wh = cast(int) scaledDim(rec.widget.h(), scale);

            if (doubleBuffered)
            {
                if (rec.offscreen == 0 || rec.offscreenW != ww || rec.offscreenH != wh)
                {
                    if (rec.offscreen != 0) fldraw.freeOffscreenBuffer(rec.offscreen);
                    rec.offscreen = fldraw.createOffscreenBuffer(rec.xid, ww, wh);
                    rec.offscreenW = ww;
                    rec.offscreenH = wh;
                    // A freshly (re)allocated buffer has undefined
                    // contents -- force a full, unclipped repaint into
                    // it, matching FLTK's own `pWindow->clear_damage(
                    // FL_DAMAGE_ALL)` the first time `other_xid` is
                    // created.
                    rec.widget.damage(damageAll);
                    rec.hasDamageRegion = false;
                }
                doubleBuffered = rec.offscreen != 0; // fall back to direct draw if allocation failed
            }

            // Ported from Fl_X11_Window_Driver::flush_overlay() (see
            // fl.overlay_window's module doc comment for the rest of
            // this story): an Fl_Overlay_Window's overlay is always
            // software-simulated in this port, drawn directly onto the
            // on-screen half of the double buffer and "erased" by
            // recopying the clean backbuffer over it. `eraseOverlay`
            // mirrors FLTK's `erase_overlay` local exactly (`(damage()
            // & FL_DAMAGE_OVERLAY) | (overlay() == pWindow)`): true
            // whenever this flush was triggered by redrawOverlay() (the
            // FL_DAMAGE_OVERLAY bit) or whenever the overlay is simply
            // active at all (so *every* flush of an in-use overlay
            // window forces a full, unclipped recopy -- matching
            // FLTK's own documented "will blink if you change the
            // image" tradeoff). The overlay bit itself is stripped from
            // the window's damage before the normal content-damage
            // logic below runs, matching FLTK's `clear_damage()`-
            // based bookkeeping in `Fl_Overlay_Window::redraw_overlay()`
            // rather than a real `Fl_Widget::damage()` call -- see
            // `OverlayWindow.redrawOverlay()`'s own doc comment for why
            // that distinction matters here.
            auto overlayWin = cast(OverlayWindow) rec.widget;
            bool overlayBitSet = overlayWin !is null && (rec.widget.damage() & damageOverlay) != 0;
            bool eraseOverlay = overlayWin !is null && (overlayBitSet || overlayWin.overlayActive());
            if (overlayBitSet)
                rec.widget.clearDamage(cast(Damage)(rec.widget.damage() & ~damageOverlay));

            // Snapshot the clip decision *before* calling draw() --
            // matching FLTK's `Fl_X11_Window_Driver::flush_double()`,
            // which captures `use_clip_box`/`X,Y,W,H` into plain locals
            // before `draw()` runs, specifically so nothing that happens
            // *during* drawing can change the region used for the blit
            // afterward. `draw()` genuinely
            // does mutate `rec.hasDamageRegion`/`rec.damageX/Y/W/H` as a
            // side effect (e.g. `Fl_Text_Display::
            // draw()`'s `mVScrollBar->damage(FL_DAMAGE_ALL)`, ported
            // faithfully in `fl.text_display`, unconditionally
            // re-accumulates the scrollbar's own placeholder
            // construction-time rect even while invisible), which on a
            // freshly (re)allocated `DoubleWindow` buffer could
            // otherwise let a
            // mid-draw damage() call silently overwrite the "paint the
            // whole freshly-allocated buffer, unclipped" decision just
            // made above with a wrong, narrower rect -- leaving a strip
            // along the right/bottom edges
            // showing whatever was on screen before, never painted at
            // all. A plain (non-double-buffered) `Window` masks the
            // same underlying clip-recompute hazard, since X11 fills a
            // newly mapped window's exposed background from its own
            // `background_pixel` regardless of what this port's own
            // drawing clipped to -- a `DoubleWindow`'s offscreen
            // `Pixmap` has no such fallback (`XCreatePixmap()`'s
            // initial contents are undefined), so the hazard is only
            // reachable there, which is why the snapshot matters
            // specifically for the double-buffered path.
            bool clipped = rec.hasDamageRegion && !eraseOverlay;
            // Logical units -- passed to `pushClip()`/left as-is for
            // `draw()`, which both already scale internally (Phase 1).
            int clipX = rec.damageX, clipY = rec.damageY,
                clipW = rec.damageW, clipH = rec.damageH;
            // Device-pixel equivalents -- see the `ww`/`wh` scaling
            // note above for why `copyOffscreen()` specifically needs
            // these instead of the logical values just above.
            //
            // Deliberately *not* `scaledPos()`/`scaledDim()` (which
            // round/truncate the position and size *independently*):
            // that can under-cover the true dirty rectangle's right/
            // bottom edge by up to 1 device pixel whenever `clipW`/
            // `clipH` isn't an exact multiple of the scale, since
            // `scaledDim()` truncates rather than rounding up -- at a
            // fractional scale, a `MenuBar` closing a dropdown redraws
            // only its own
            // rectangle (`Widget.damage(Damage,x,y,w,h)`, not a whole-
            // window `damage(Damage)`), and a truncated device-pixel
            // clip would leave a thin, uncopied strip of the item's
            // previous
            // "open" highlight box visible along its trailing edge.
            // Rounding the *rectangle's corners*
            // outward -- floor the min corner, ceil the max corner --
            // which guarantees the resulting device-pixel rectangle
            // fully contains the mapped FLTK-unit one, same principle as
            // `resizeAfterScaleChange()`'s own "size rounds up, never
            // under-reports" convention, just applied to a clip
            // rectangle's far edge instead of a window's size.
            import std.math : ceil, floor;

            int devClipX = cast(int) floor(clipX * cast(double) scale);
            int devClipY = cast(int) floor(clipY * cast(double) scale);
            int devClipW = cast(int) ceil((clipX + clipW) * cast(double) scale) - devClipX;
            int devClipH = cast(int) ceil((clipY + clipH) * cast(double) scale) - devClipY;
            // Rounding the far edge *up* can push it 1px past `ww`/`wh`
            // (the offscreen buffer's own truncated allocated size,
            // computed above) when the damage rectangle reaches all the
            // way to the window's edge -- clamp so `copyOffscreen()`
            // never reads past the buffer it's actually sourcing from.
            if (devClipX + devClipW > ww) devClipW = ww - devClipX;
            if (devClipY + devClipH > wh) devClipH = wh - devClipY;

            // Ported from flush_double()'s own `if (pWindow->damage() &
            // ~FL_DAMAGE_EXPOSE)` gate: for a
            // DoubleWindow, a pure reveal (nothing damaged except
            // FL_DAMAGE_EXPOSE -- another window slid off, nothing in
            // *this* window's own content actually changed) needs no
            // draw() call at all -- the backbuffer already holds
            // whatever was last correctly rendered there, so the blit
            // below is sufficient on its own, exactly matching
            // FLTK's own skip. Calling draw() anyway would be actively
            // harmful, not just wasteful: `draw()`
            // would still run with the narrow accumulated-Expose rectangle
            // pushed as the active clip (see `clipped`/`clipX/Y/W/H`
            // below), and `FlGroup.drawChild()`'s own `notClipped()` gate
            // culls a whole child subtree -- including any
            // `drawOutsideLabel()` calls nested inside it -- the moment
            // that subtree's *own* bounding box doesn't yet overlap the
            // sliver, even when the sliver already covers pixels the
            // subtree is responsible for (e.g. a widget's own outside-
            // positioned label, drawn to the *left* of its box by its
            // immediate parent FlGroup). A window-drag's Expose events
            // arrive as a sequence of such slivers sweeping across the
            // window, so real content could get this same false-culled
            // treatment on every single sliver -- e.g.
            // `fluid/panels/settings_panel.fl`'s "Scheme:"/"#
            // Recent Files:" labels, each drawn by an immediately-
            // enclosing anonymous `FlGroup` whose own box exactly matches
            // its child's -- no margin for the label -- so no sliver
            // position would ever both reach the label's own pixels *and*
            // successfully clear the parent FlGroup's clip check at the
            // same time. Skipping
            // draw() entirely for a pure-Expose reveal, matching
            // FLTK, sidesteps the whole failure mode: nothing new
            // needs painting into the backbuffer, so there is no
            // per-sliver traversal to (mis)clip in the first place. A
            // plain (non-double-buffered) `Window` has no backbuffer to
            // fall back on, so it keeps the unconditional-redraw
            // behavior, matching FLTK's own plain `Fl_Window::
            // flush()` (no `~FL_DAMAGE_EXPOSE` check there at all --
            // that optimization is specific to `flush_double()`).
            bool hasContentDamage = doubleBuffered
                ? (rec.widget.damage() & ~damageExpose) != 0
                : rec.widget.damage() != 0;

            fldraw.setDrawable(doubleBuffered ? rec.offscreen : rec.xid);
            FlWindow.setCurrentForDraw(rec.widget);
            if (hasContentDamage)
            {
                if (clipped)
                    fldraw.pushClip(clipX, clipY, clipW, clipH);
                rec.widget.draw();
                if (clipped)
                    fldraw.popClip();
            }

            if (doubleBuffered)
            {
                fldraw.setDrawable(rec.xid);
                if (clipped)
                    fldraw.copyOffscreen(rec.offscreen, devClipX, devClipY, devClipW, devClipH, devClipX, devClipY);
                else
                    fldraw.copyOffscreen(rec.offscreen, 0, 0, ww, wh, 0, 0);
            }

            if (overlayWin !is null && overlayWin.overlayActive())
            {
                // The blit above just recopied a clean, overlay-free
                // backbuffer onto the on-screen window (or, if
                // !doubleBuffered because offscreen allocation failed,
                // there was nothing to erase with -- draw the fresh
                // overlay directly regardless, matching FLTK's own
                // lack of a fallback for that pathological case).
                // Drawing straight onto rec.xid here, not rec.offscreen,
                // is the whole point: this pixel data is never part of
                // the backbuffer, so it's naturally "erased" next time
                // this branch recopies the backbuffer over it.
                fldraw.setDrawable(rec.xid);
                overlayWin.drawOverlay();
            }

            rec.widget.clearDamage();
            rec.hasDamageRegion = false;
            rec.fullRepaintPending = false;
            any = true;
        }
    }
    if (any) XFlush(display_);
}

/**
 * Shared, single-instance state backing a deferred cross-screen window
 * move -- ported from `Fl_X11_Window_Driver::
 * data_for_resize_window_between_screens_` (a single static there too,
 * not per-window: FLTK only ever tracks one such transition in
 * flight across the whole app, and this port matches that exactly).
 * `pending` holds the exact delegate instance passed to `addTimeout()`,
 * needed to `removeTimeout()` the same one back out again if the window
 * re-crosses back before the tick fires.
 */
private struct ResizeBetweenScreens
{
    int screen;
    bool busy;
    TimeoutHandler pending;
}
private ResizeBetweenScreens resizeBetweenScreens_;

/**
 * Returns a fresh delegate closing over `win`, for `addTimeout()`/
 * `removeTimeout()` to share -- written as a real function call
 * (rather than a delegate literal inline in the `ConfigureNotify` case
 * below) deliberately: that case sits inside this module's own
 * event-dispatch loop, and this project has already been bitten once
 * (`smoke-tests/screen_scale_live.d`) by a delegate literal written
 * directly inside a repeatedly-executed scope silently sharing DMD's
 * closure frame across executions instead of capturing a fresh value
 * each time. A genuine function call always gets its own frame.
 */
private TimeoutHandler makeScreenChangeTimeout(FlWindow win)
{
    return () { resizeAfterScreenChange(win); };
}

/**
 * Ported from `Fl_X11_Window_Driver::resize_after_screen_change()`.
 * Runs one tick after the `ConfigureNotify` handler below detects a
 * window's centre crossing into a different, differently-scaled
 * screen -- deliberately deferred rather than reacting immediately,
 * matching FLTK's own comment: "calling it a second later gives a
 * more pleasant user experience when moving windows between distinct
 * screens." Settles the window using its *destination* screen's own
 * scale for both the "old" and "new" factor `resizeAfterScaleChange()`
 * takes -- this isn't a proportional unit conversion, just a
 * re-clamp-with-the-correct-scale pass -- then clears the busy flag so
 * the next cross-screen move can be detected again.
 */
private void resizeAfterScreenChange(FlWindow win)
{
    float f = screenScale(resizeBetweenScreens_.screen);
    win.resizeAfterScaleChange(resizeBetweenScreens_.screen, f, f);
    resizeBetweenScreens_.busy = false;
}

private void processNextEvent()
{
    XEvent ev;
    XNextEvent(display_, &ev); // blocks; also flushes pending output first (Xlib's own guarantee)

    // Ported from Fl_x.cxx's do_queued_events(): `if
    // (fl_send_system_handlers(&xevent)) continue; fl_handle(xevent);`
    // -- any fl.core.addSystemHandler()-registered handler gets first
    // look at the *raw* XEvent, before any of this port's own
    // translation runs at all; consuming it here skips that
    // translation entirely for this event.
    if (fl.core.sendSystemHandlers(&ev)) return;

    // Ported from `fl_handle()`'s own `if (xim_ic && XFilterEvent(...))
    // return(1);` (`Fl_x.cxx`) --
    // lets the input method fully consume a raw event before any of
    // this port's own translation below ever sees it (e.g. a CJK input
    // method's own candidate-selection UI intercepting a click/key
    // meant for it, not this application). Must run for *every* event
    // type, not just KeyPress -- matching FLTK's own unconditional
    // placement here, before the switch.
    if (ximIc_ !is null && XFilterEvent(&ev, 0)) return;

    // Ported from fl_handle()'s own trailing `switch (xevent.type -
    // xfixes_event_base) { case XFixesSelectionNotify: ... }` (Fl_x.cxx)
    // -- an XFixes-extension event type is a runtime value (the
    // extension's own `event_base` plus a fixed subtype offset), so it
    // can't be a `case` label in the `switch` below; checked here
    // instead, before it, same as FLTK checks it as a final
    // fallback after its own window-specific switch. Reuses
    // handleClipboardTimestamp() -- the same function
    // pollClipboardOwner()'s polling fallback calls -- since both paths
    // ultimately just need to know "did this selection's ownership
    // timestamp change"; matches FLTK's own `Fl_x.cxx`, which
    // shares `handle_clipboard_timestamp()` between both paths too.
    if (haveXfixes_ && ev.type == xfixesEventBase_ + XFixesSelectionNotify)
    {
        auto sn = cast(XFixesSelectionNotifyEvent*)&ev;
        int clipboard = sn.selection == clipboardAtom_ ? 1 : 0;
        if (!fl.core.weOwnSelection(clipboard))
            handleClipboardTimestamp(clipboard, sn.selection_timestamp);
        return;
    }

    switch (ev.type)
    {
    case Expose:
        // Ported from Fl_x.cxx's own `case Expose:`/`case
        // GraphicsExpose:` (just `window->damage(FL_DAMAGE_EXPOSE,
        // ...)`, nothing else -- no synchronous draw() here at all).
        // Drawing synchronously, once per fragment,
        // clipped to just that one fragment, would be wasteful
        // when the X server splits a single uncover operation into
        // several Expose rectangles (common), since each one would re-walk
        // the *whole* widget tree's draw() logic separately. Instead this
        // just accumulates the rectangle (via Widget.damage(), which
        // calls into accumulateDamage() above) and lets flushDamage()
        // -- called once per wait()/run() iteration, after every
        // currently-queued X event (including any other pending Expose
        // fragments) has been drained -- do exactly one clipped draw()
        // per window, batching everything accumulated since the last
        // flush, matching FLTK's real Fl::flush() timing.
        if (auto rec = find(ev.xexpose.window))
        {
            // ev.xexpose.x/y/width/height are real device pixels (the
            // X server's own report); `Widget.damage(Damage,x,y,w,h)`
            // expects FLTK-unit, window-relative coordinates (see its
            // own doc comment), so these need converting -- without
            // this conversion, at scale != 1, the accumulated damage
            // rectangle
            // would silently use the *device-pixel* extent as if it were
            // already FLTK units, over-covering at scale > 1 (a wasted
            // but harmless larger redraw) and *under*-covering at
            // scale < 1 (leaving genuinely exposed pixels never
            // redrawn). floor()/ceil()
            // (not simple division) so the FLTK-unit rectangle always
            // *fully contains* the real exposed area regardless of
            // rounding direction -- a fractional-pixel over-cover is
            // harmless, under-covering is exactly the bug being fixed.
            float scale = screenScale(rec.widget.screenNum());
            if (scale == 1)
            {
                rec.widget.damage(damageExpose, ev.xexpose.x, ev.xexpose.y,
                    ev.xexpose.width, ev.xexpose.height);
            }
            else
            {
                import std.math : floor, ceil;

                double sx1 = ev.xexpose.x / cast(double) scale;
                double sy1 = ev.xexpose.y / cast(double) scale;
                double sx2 = (ev.xexpose.x + ev.xexpose.width) / cast(double) scale;
                double sy2 = (ev.xexpose.y + ev.xexpose.height) / cast(double) scale;
                int fx = cast(int) floor(sx1);
                int fy = cast(int) floor(sy1);
                int fw = cast(int) ceil(sx2) - fx;
                int fh = cast(int) ceil(sy2) - fy;
                rec.widget.damage(damageExpose, fx, fy, fw, fh);
            }
            rec.waitingForExpose = false;
        }
        break;

    case ConfigureNotify:
        if (auto rec = find(ev.xconfigure.window))
        {
            // Xlib's ConfigureNotify x/y is unreliable across window
            // managers (it's relative to whichever reparenting frame
            // the WM inserted, not necessarily the root); FLTK
            // does this XGetWindowAttributes+XTranslateCoordinates
            // round-trip to get the real on-screen position. Simpler
            // to just trust ev.xconfigure directly for width/height,
            // which are reliable.
            XWindowAttributes attrs;
            XGetWindowAttributes(display_, rec.xid, &attrs);
            int rx, ry;
            Window child;
            XTranslateCoordinates(display_, rec.xid, attrs.root, 0, 0, &rx, &ry, &child);

            // The window's exact device-pixel position, kept
            // live so `Window.resizeAfterScaleChange()` never has to
            // reconstruct an approximation of it from lossier FLTK units
            // -- see `devicePosX_`/`devicePosY_`'s own doc comment for
            // the rounding hazard this avoids.
            rec.widget.devicePosX_ = rx;
            rec.widget.devicePosY_ = ry;

            // Set *before* calling resize() -- tells that override's
            // own echo-prevention guard this call is relaying the
            // window manager's already-applied geometry, not
            // requesting a new one, so it should skip issuing a
            // redundant XMoveResizeWindow()/etc. call back to the
            // server (which would otherwise round-trip forever).
            // Matches FLTK's own `resize_bug_fix = window;` here
            // exactly (Fl_x.cxx). The pure-move-skips-redraw() flicker
            // fix lives in
            // fl.window.Window.resize() itself, matching
            // FLTK's own architecture (that gate is
            // Fl_X11_Window_Driver::resize()'s own is_a_resize check,
            // not anything ConfigureNotify-specific), and is what
            // application-initiated resize()/position()/size() calls
            // need the exact same gate for too, not just this handler.
            resizeBugFix_ = rec.widget;

            int rw = ev.xconfigure.width, rh = ev.xconfigure.height;

            // Detect whether this window's *centre* just crossed into a
            // different screen -- ported from Fl_x.cxx's own
            // ConfigureNotify handler (the `#if USE_XFT || FLTK_USE_CAIRO`
            // branch, the only one FLTK itself builds today; the
            // `#else` branch is a plain `screen_num()` call this port
            // never needs a separate path for). Reacting to every
            // ConfigureNotify the same way regardless of
            // which screen the window is on would misjudge scale the
            // moment a window sitting on a satellite (non-primary)
            // monitor gets rescaled: an ordinary same-screen resize and a
            // cross-screen
            // move would both go through the exact same immediate
            // `rint()`/`ceil()` math below, using whatever scale is
            // cached for the *old* screen even when the window has
            // already physically landed on a differently-scaled one.
            // See resizeAfterScreenChange() above for why the actual fix
            // is deferred a tick rather than applied here inline.
            int olds = rec.widget.rawScreenNum();
            int num = screenNumUnscaled(rx + rw / 2, ry + rh / 2);
            // Matches FLTK's own `if (num == -1) num = olds;` --
            // a window's centre transiently in the dead space between
            // two monitors (e.g. mid-drag) must not be misread as "no
            // screen, so screen 0," which would falsely look like a
            // cross-screen move to the check just below.
            if (num == -1) num = olds;
            float s = screenScale(num);
            if (num != olds && !rec.widget.menuWindow())
            {
                if (auto m = cast(FlWindow) fl.core.modal())
                {
                    if (m.menuWindow())
                    {
                        // Simulate a distant click to close any open menu
                        // before the window under it moves out from under
                        // it -- ported from FLTK's own
                        // `Fl::e_x_root = 1000000; Fl::modal()->handle(FL_PUSH);`.
                        fl.core.eXRoot_ = 1_000_000;
                        m.handle(Event.push);
                    }
                }
                if (s != screenScale(olds) && !resizeBetweenScreens_.busy
                    && rec.widget !is fl.core.transientScaleWindow())
                {
                    resizeBetweenScreens_.busy = true;
                    resizeBetweenScreens_.screen = num;
                    resizeBetweenScreens_.pending = makeScreenChangeTimeout(rec.widget);
                    fl.core.addTimeout(1.0, resizeBetweenScreens_.pending);
                }
                else if (!resizeBetweenScreens_.busy)
                {
                    rec.widget.rawScreenNum(num);
                }
            }
            else if (resizeBetweenScreens_.busy)
            {
                fl.core.removeTimeout(resizeBetweenScreens_.pending);
                resizeBetweenScreens_.busy = false;
            }

            // rx/ry/width/height are real device pixels (the window
            // manager's own applied geometry); divide back down to
            // FLTK units before handing them to resize(), matching
            // FLTK's own `window->resize(rint(X/s), rint(Y/s),
            // ceil(W/s), ceil(H/s))` at this exact call site --
            // position rounds to
            // nearest, size rounds up (FLTK's own choice: never
            // under-report a window's size after a scaled resize).
            // While a deferred cross-screen settle is pending (`busy`),
            // only reposition -- never resize -- matching FLTK's own
            // `if (!busy && (size differs) && !menu_window) resize();
            // else position();` exactly, so the stale, pre-settle scale
            // `s` computed above can't force a wrong-looking intermediate
            // size onto the window before resizeAfterScreenChange() gets
            // a chance to apply the correct one.
            import std.math : ceil, lround;

            int fx = cast(int) lround(rx / cast(double) s);
            int fy = cast(int) lround(ry / cast(double) s);
            if (!resizeBetweenScreens_.busy
                && (cast(int) ceil(rw / cast(double) s) != rec.widget.w()
                    || cast(int) ceil(rh / cast(double) s) != rec.widget.h())
                && !rec.widget.menuWindow())
            {
                int fw = cast(int) ceil(rw / cast(double) s);
                int fh = cast(int) ceil(rh / cast(double) s);
                rec.widget.resize(fx, fy, fw, fh);
            }
            else
            {
                rec.widget.position(fx, fy);
            }
        }
        break;

    case ClientMessage:
        // Dispatches through fl.core.handle() as a real Event.close --
        // not a direct destroyWindow() call, which would bypass
        // fl.core.handle() entirely, and with it any
        // modal()/grab() filtering (FLTK's real FL_CLOSE case
        // checks both). fl.window.Window's own constructor sets a
        // default callback (hide() + push onto the read queue,
        // matching FLTK's Fl_Window::default_callback) so ordinary
        // windows with no custom callback() still close normally via
        // this path -- see that module's row.
        if (cast(Atom) ev.xclient.data.l[0] == wmDeleteWindow_)
        {
            if (auto rec = find(ev.xclient.window))
                fl.core.dispatch(Event.close, rec.widget);
        }
        else if (ev.xclient.message_type == xdndEnter_)
        {
            // Ported from Fl_x.cxx's own `case ClientMessage:` ==
            // fl_XdndEnter branch. data.l[0] is the source window;
            // data.l[1]'s low bit means "more than 3 types, check the
            // XdndTypeList property on the source instead of data.l[2..4]
            // directly" -- both forms ported, see findTargetText()'s own
            // doc comment for the (deliberately narrower than FLTK's
            // 8-atom) preference list used to pick among them.
            dndSourceWindow_ = cast(Window) ev.xclient.data.l[0];
            Atom[] sourceTypes;
            if (ev.xclient.data.l[1] & 1)
            {
                Atom actual;
                int format;
                c_ulong count, remaining;
                void* buf;
                XGetWindowProperty(display_, dndSourceWindow_, xdndTypeList_,
                    0, 0x8000000L, False, XA_ATOM, &actual, &format, &count, &remaining, &buf);
                if (actual == XA_ATOM && format == 32 && count > 0 && buf !is null)
                    sourceTypes = (cast(Atom*) buf)[0 .. count].dup;
                if (buf !is null) XFree(buf);
            }
            if (sourceTypes.length == 0)
            {
                foreach (t; [cast(Atom) ev.xclient.data.l[2], cast(Atom) ev.xclient.data.l[3],
                        cast(Atom) ev.xclient.data.l[4]])
                    if (t != None) sourceTypes ~= t;
            }
            dndSourceTypes_ = sourceTypes;
            dndType_ = findTargetText(sourceTypes);
            if (dndType_ == None && sourceTypes.length) dndType_ = sourceTypes[0];

            if (auto rec = find(ev.xclient.window))
                fl.core.dispatch(Event.dndEnter, rec.widget);
        }
        else if (ev.xclient.message_type == xdndPosition_)
        {
            // Ported from Fl_x.cxx's own fl_XdndPosition branch --
            // updates the event-position globals from the message's
            // root-relative coordinates, dispatches Event.dndDrag to
            // find out whether the widget under the pointer wants the
            // drop, and answers with a real XdndStatus reply either way
            // (accept/refuse, matching FLTK's own synchronous
            // "answer every position update" protocol requirement).
            dndSourceWindow_ = cast(Window) ev.xclient.data.l[0];
            // data.l[2]'s packed root-relative x/y are real device
            // pixels (the XDND protocol's own wire format); divided
            // down to FLTK units here, matching FLTK's own
            // `Fl::e_x_root = (data[2]>>16)/s;` --
            // eX_/eY_ just below need this to line up
            // with `rec.widget.x()`/`y()`, which are FLTK units.
            //
            // **`rec.widget.screenNum()`'s own scale, not a hardcoded
            // screen 0** -- matches FLTK's own `if (window) s =
            // Fl::screen_driver()->scale(Fl_Window_Driver::driver(
            // window)->screen_num());`, falling back to `s = 1`
            // (matching FLTK's own `float s = 1;` default) if this
            // client message names a window this port isn't tracking.
            auto rec = find(ev.xclient.window);
            float dndScale = rec !is null ? screenScale(rec.widget.screenNum()) : 1.0f;
            fl.core.eXRoot_ = cast(int)(cast(int)(ev.xclient.data.l[2] >> 16) / dndScale);
            fl.core.eYRoot_ = cast(int)(cast(int)(ev.xclient.data.l[2] & 0xFFFF) / dndScale);
            if (rec !is null)
            {
                fl.core.eX_ = fl.core.eXRoot_ - rec.widget.x();
                fl.core.eY_ = fl.core.eYRoot_ - rec.widget.y();
            }
            lastEventTime_ = cast(Time) ev.xclient.data.l[3];
            dndSourceAction_ = cast(Atom) ev.xclient.data.l[4];
            dndAction_ = xdndActionCopy_;
            int accept = rec !is null ? fl.core.dispatch(Event.dndDrag, rec.widget) : 0;
            sendClientMessage(dndSourceWindow_, xdndStatus_, ev.xclient.window,
                accept ? 1 : 0, 0, 0, accept ? dndAction_ : None);
        }
        else if (ev.xclient.message_type == xdndLeave_)
        {
            dndSourceWindow_ = 0; // don't send XdndFinished for this drop
            if (auto rec = find(ev.xclient.window))
                fl.core.dispatch(Event.dndLeave, rec.widget);
        }
        else if (ev.xclient.message_type == xdndDrop_)
        {
            // Ported from Fl_x.cxx's own fl_XdndDrop branch: dispatches
            // Event.dndRelease to find out whether the drop is accepted;
            // if so, fires the real XConvertSelection() for the payload
            // (delivered later via case SelectionNotify:'s own
            // XA_SECONDARY branch, which sends XdndFinished once it has
            // an answer); if not, sends XdndFinished immediately, same
            // as FLTK.
            dndSourceWindow_ = cast(Window) ev.xclient.data.l[0];
            lastEventTime_ = cast(Time) ev.xclient.data.l[2];
            Window toWindow = ev.xclient.window;
            auto rec = find(ev.xclient.window);
            int accepted = rec !is null ? fl.core.dispatch(Event.dndRelease, rec.widget) : 0;
            if (accepted)
            {
                fl.core.setPendingPasteReceiver(fl.core.belowmouse());
                XConvertSelection(display_, xdndSelection_, dndType_, XA_SECONDARY,
                    toWindow, lastEventTime_);
            }
            else
            {
                sendClientMessage(dndSourceWindow_, xdndFinished_, toWindow);
                dndSourceWindow_ = 0;
            }
        }
        break;

    case PropertyNotify:
        // Externally-triggered maximize/fullscreen state sync (e.g.
        // the user double-clicking the title bar), the direct
        // equivalent of FLTK's `case PropertyNotify:` (Fl_x.cxx).
        // Only `_NET_WM_STATE` changes matter here -- everything else
        // this window's WM might touch is ignored, matching FLTK
        // (which gates its entire body on the same atom check).
        if (ev.xproperty.atom == netWmState_)
            if (auto rec = find(ev.xproperty.window))
            {
                bool fullscreenState, maximizeState, minimizeState;
                if (ev.xproperty.state != PropertyDelete)
                {
                    Atom[] states;
                    if (getNetWmState(ev.xproperty.window, states))
                        foreach (a; states)
                        {
                            if (a == netWmStateFullscreen_) fullscreenState = true;
                            // Matches FLTK's own asymmetry: only
                            // MAXIMIZED_HORZ is checked, not _VERT too
                            // (`Fl_x.cxx`'s own `case PropertyNotify:`
                            // -- the two are expected to always appear
                            // together in practice, since maximizeOn()/
                            // maximizeOff() above only ever request
                            // them as a pair).
                            if (a == netWmStateMaximizedHorz_) maximizeState = true;
                            if (a == netWmStateHidden_) minimizeState = true;
                        }
                }

                // Unconditional, matching FLTK's own unconditional
                // `is_maximized(maximize_state)` call -- setMaximizedFlag()/
                // clearMaximizedFlag() are idempotent, so no "did it
                // actually change" guard is needed here.
                if (maximizeState) rec.widget.setMaximizedFlag();
                else rec.widget.clearMaximizedFlag();

                // Fullscreen does fire an event on an actual
                // transition (unlike maximize, which FLTK's own
                // X11 driver never dispatches an Fl::handle() call
                // for -- see maximizeOn()'s doc comment above).
                //
                // Minimize/restore tracking: ported from FLTK's own trailing
                // `if (!event) { if (minimize_state) event = FL_HIDE;
                // else if (!window->visible()) event = FL_SHOW; }`
                // (`Fl_x.cxx`'s `case PropertyNotify:`) -- mutually
                // exclusive with the fullscreen transition above,
                // matching FLTK's single shared `event` variable
                // (a fullscreen transition and a minimize/restore
                // notification never both fire off the same
                // `_NET_WM_STATE` change in practice). Like FLTK's
                // own `Fl_Window::handle()` (see its `FL_SHOW`/`FL_HIDE`
                // cases' own doc comment: "For top-level windows it is
                // assumed the window has already been mapped or
                // unmapped" -- the body only does anything for a
                // *subwindow*, `parent() != null`), this is purely an
                // informational event for the app's own `handle()`
                // override or a global `addHandler()` to react to --
                // it deliberately does not touch `visible()`/`shown()`
                // itself.
                if (rec.widget.fullscreenActive() && !fullscreenState)
                {
                    rec.widget.clearFullscreenFlag();
                    fl.core.dispatch(Event.fullscreen, rec.widget);
                }
                else if (!rec.widget.fullscreenActive() && fullscreenState)
                {
                    rec.widget.setFullscreenFlag();
                    fl.core.dispatch(Event.fullscreen, rec.widget);
                }
                else if (minimizeState)
                {
                    fl.core.dispatch(Event.hide, rec.widget);
                }
                else if (!rec.widget.visible())
                {
                    fl.core.dispatch(Event.show, rec.widget);
                }
            }
        break;

    case SelectionClear:
        // Another app just took ownership of a selection we used to
        // own -- the direct equivalent of FLTK's own
        // `case SelectionClear:` (Fl_x.cxx), just clearing our
        // ownership flag; we don't need to do anything else (our old
        // contents stay in fl.core's buffer, just no longer marked as
        // "the real owner").
        fl.core.clearSelectionOwnership(
            ev.xselectionclear.selection == clipboardAtom_ ? 1 : 0);
        break;

    case SelectionRequest:
        // Another app is asking *us*, as current owner, to convert our
        // selection to some target format -- the direct equivalent of
        // FLTK's own `case SelectionRequest:` (Fl_x.cxx). Two
        // separate branches, matching FLTK's own `if
        // (fl_selection_type[clipboard] == Fl::clipboard_plain_text)
        // ... else ...` split exactly: a plain-text-owned selection
        // only ever advertises/answers `UTF8_STRING`/`XA_STRING`; an
        // image-owned one (`fl.core.copyImage()`) only ever
        // advertises/answers `image/bmp` -- FLTK never offers both
        // out of the same selection at once, and neither does this.
        // Anything else gets refused (property left None), matching
        // the ICCCM's own documented failure convention.
        {
            XSelectionRequestEvent req = ev.xselectionrequest;
            XEvent replyEv;
            replyEv.xselection.type = SelectionNotify;
            replyEv.xselection.display = display_;
            replyEv.xselection.requestor = req.requestor;
            replyEv.xselection.selection = req.selection;
            replyEv.xselection.target = req.target;
            replyEv.xselection.time = req.time;
            replyEv.xselection.property = None;

            // Only ever answer for the two selections we actually claim
            // ownership of (setSelectionOwner() never requests any
            // other) -- anything else is refused, same as an
            // unrecognized target.
            if (req.selection == XA_PRIMARY || req.selection == clipboardAtom_)
            {
                int clipboardIdx = req.selection == clipboardAtom_ ? 1 : 0;
                if (fl.core.selectionOwnedType(clipboardIdx) == fl.core.clipboardImage)
                {
                    if (req.target == targetsAtom_)
                    {
                        Atom[1] targets = [imageBmpAtom_];
                        XChangeProperty(display_, req.requestor, req.property, XA_ATOM, 32,
                            PropModeReplace, cast(const(ubyte)*) targets.ptr, 1);
                        replyEv.xselection.property = req.property;
                    }
                    else if (req.target == imageBmpAtom_)
                    {
                        auto bmp = fl.core.ownedImageBmpBytes(clipboardIdx);
                        if (bmp.length)
                        {
                            XChangeProperty(display_, req.requestor, req.property, req.target, 8,
                                PropModeReplace, bmp.ptr, cast(int) bmp.length);
                            replyEv.xselection.property = req.property;
                        }
                    }
                }
                else if (req.target == targetsAtom_)
                {
                    Atom[2] targets = [utf8StringAtom_, XA_STRING];
                    XChangeProperty(display_, req.requestor, req.property, XA_ATOM, 32,
                        PropModeReplace, cast(const(ubyte)*)targets.ptr, 2);
                    replyEv.xselection.property = req.property;
                }
                else if (req.target == utf8StringAtom_ || req.target == XA_STRING)
                {
                    string text = fl.core.clipboardContents(clipboardIdx);
                    XChangeProperty(display_, req.requestor, req.property, req.target, 8,
                        PropModeReplace, cast(const(ubyte)*) text.ptr, cast(int) text.length);
                    replyEv.xselection.property = req.property;
                }
            }

            XSendEvent(display_, req.requestor, False, 0, &replyEv);
        }
        break;

    case SelectionNotify:
        // The reply to one of this module's own XConvertSelection()
        // calls. Five distinct kinds land here, discriminated the same
        // way FLTK's own single `case SelectionNotify:` (Fl_x.cxx)
        // does -- by which property/target the reply itself names, not
        // by any separately-tracked "what did we last ask for" state:
        //
        //  1. A clipboard-change poll's TIMESTAMP reply
        //     (pollClipboardOwner()) -- must be checked *first* and
        //     return early, matching FLTK exactly: it isn't paste
        //     data at all, and falling through into the branches below
        //     would misinterpret a raw Time value as failed/garbage
        //     paste content.
        //  2. A DND drop's own conversion reply, fired from `case
        //     ClientMessage:`'s own `xdndDrop_` branch -- recognized by
        //     `property == XA_SECONDARY` (matching FLTK's own
        //     discriminator exactly) or, on a failed conversion, by
        //     `dndSourceWindow_ != 0` alone (a refused/failed
        //     conversion's reply comes back with `property == None`,
        //     losing the `XA_SECONDARY` marker -- FLTK's own
        //     handling of this edge case is itself flagged uncertain,
        //     see the `[FIXME: is the condition below really
        //     correct?]` comment in `Fl_x.cxx`). Completes the drop
        //     (`deliverPaste()` + a real `XdndFinished` reply to the
        //     source) instead of just delivering `Event.paste` like an
        //     ordinary paste.
        //  3. requestSelectionImage()'s first round: a TARGETS atom
        //     list, recognized by `target == targetsAtom_` (the only
        //     path in this module that ever requests TARGETS).
        //  4. requestSelectionImage()'s second round: actual image
        //     bytes, recognized by `target == imageBmpAtom_/imagePngAtom_`.
        //  5. requestSelection()'s plain-text reply (unchanged from
        //     before image-paste support existed).
        if (ev.xselection.property == primaryTimestampAtom_ ||
            ev.xselection.property == clipboardTimestampAtom_)
        {
            Atom property = ev.xselection.property;
            if (property != None)
            {
                Atom actualType;
                int actualFormat;
                c_ulong nitems, bytesAfter;
                void* data;
                int status = XGetWindowProperty(display_, ev.xselection.requestor, property,
                    0, 1, True, AnyPropertyType, &actualType, &actualFormat,
                    &nitems, &bytesAfter, &data);
                scope(exit) if (data !is null) XFree(data);
                if (status == Success && data !is null && actualFormat == 32 && nitems == 1)
                    handleClipboardTimestamp(property == clipboardTimestampAtom_ ? 1 : 0,
                        *cast(uint*) data);
            }
            break;
        }

        if (dndSourceWindow_ != 0
            && (ev.xselection.property == XA_SECONDARY || ev.xselection.property == None))
        {
            Window srcWindow = dndSourceWindow_;
            Window toWindow = ev.xselection.requestor;
            Atom property = ev.xselection.property;
            string text;
            bool ok;
            if (property != None)
            {
                Atom actualType;
                int actualFormat;
                c_ulong nitems, bytesAfter;
                void* data;
                int status = XGetWindowProperty(display_, ev.xselection.requestor, property,
                    0, c_long.max, True, AnyPropertyType, &actualType, &actualFormat,
                    &nitems, &bytesAfter, &data);
                if (status == Success && data !is null)
                {
                    scope(exit) XFree(data);
                    text = (cast(char*) data)[0 .. nitems].idup;
                    ok = true;
                }
            }
            fl.core.deliverPaste(ok ? text : null);
            sendClientMessage(srcWindow, xdndFinished_, toWindow,
                ok ? 1 : 0, ok ? dndAction_ : None);
            dndSourceWindow_ = 0;
            break;
        }

        if (ev.xselection.target == targetsAtom_)
        {
            Atom property = ev.xselection.property;
            Atom winner = None;
            if (property != None)
            {
                Atom actualType;
                int actualFormat;
                c_ulong nitems, bytesAfter;
                void* data;
                int status = XGetWindowProperty(display_, ev.xselection.requestor, property,
                    0, c_long.max, True, AnyPropertyType, &actualType, &actualFormat,
                    &nitems, &bytesAfter, &data);
                scope(exit) if (data !is null) XFree(data);
                if (status == Success && data !is null && actualType == XA_ATOM)
                {
                    Atom* atoms = cast(Atom*) data;
                    foreach (candidate; [imageBmpAtom_, imagePngAtom_])
                    {
                        foreach (idx; 0 .. nitems)
                            if (atoms[idx] == candidate) { winner = candidate; break; }
                        if (winner != None) break;
                    }
                }
            }
            if (winner == None)
            {
                fl.core.deliverPasteImage(null);
                break;
            }
            XConvertSelection(display_, ev.xselection.selection, winner,
                ev.xselection.selection, messageWindow_, CurrentTime);
            break;
        }

        if (ev.xselection.target == imageBmpAtom_ || ev.xselection.target == imagePngAtom_)
        {
            Atom property = ev.xselection.property;
            if (property == None)
            {
                fl.core.deliverPasteImage(null);
                break;
            }
            Atom actualType;
            int actualFormat;
            c_ulong nitems, bytesAfter;
            void* data;
            int status = XGetWindowProperty(display_, ev.xselection.requestor, property,
                0, c_long.max, True, AnyPropertyType, &actualType, &actualFormat,
                &nitems, &bytesAfter, &data);
            if (status != Success || data is null)
            {
                fl.core.deliverPasteImage(null);
                break;
            }
            scope(exit) XFree(data);

            if (actualType == imageBmpAtom_)
            {
                auto bytes = (cast(ubyte*) data)[0 .. nitems].idup;
                auto img = new BMPImage("clipboard", bytes);
                fl.core.deliverPasteImage(img.fail() ? null : img);
            }
            else
            {
                // image/png: a native decoder exists now (fl.png_image,
                // see PORTING.md's FL/Fl_PNG_Image.H row) -- same shape
                // as the BMP branch just above.
                auto bytes = (cast(ubyte*) data)[0 .. nitems].idup;
                auto img = new PngImage("clipboard", bytes);
                fl.core.deliverPasteImage(img.fail() ? null : img);
            }
            break;
        }

        // Plain-text reply (requestSelection()'s path, unchanged from
        // before image-paste support existed). `property == None` means
        // the conversion failed (no owner, or it declined); a UTF8_STRING
        // failure gets one retry as XA_STRING (see requestSelection()'s
        // doc comment) before giving up and delivering nothing.
        {
            Atom property = ev.xselection.property;
            if (property == None)
            {
                if (ev.xselection.target == utf8StringAtom_)
                {
                    XConvertSelection(display_, ev.xselection.selection, XA_STRING,
                        ev.xselection.selection, messageWindow_, CurrentTime);
                    break;
                }
                fl.core.deliverPaste(null);
                break;
            }

            Atom actualType;
            int actualFormat;
            c_ulong nitems, bytesAfter;
            void* data;
            int status = XGetWindowProperty(display_, ev.xselection.requestor, property,
                0, c_long.max, True, AnyPropertyType, &actualType, &actualFormat,
                &nitems, &bytesAfter, &data);
            if (status != Success || data is null)
            {
                fl.core.deliverPaste(null);
                break;
            }
            scope(exit) XFree(data);

            if (actualType != utf8StringAtom_ && actualType != XA_STRING)
            {
                fl.core.deliverPaste(null);
                break;
            }

            fl.core.deliverPaste((cast(char*) data)[0 .. nitems].idup);
        }
        break;

    case ButtonPress:
        if (auto rec = find(ev.xbutton.window))
        {
            setEventXY(rec.widget, ev.xbutton.x, ev.xbutton.y, ev.xbutton.x_root,
                ev.xbutton.y_root, ev.xbutton.state, ev.xbutton.time);
            fl.core.eDx_ = 0;
            fl.core.eDy_ = 0;

            int mb = ev.xbutton.button;
            bool shiftDown = (fl.core.eState_ & stateShift) != 0;
            if (mb == 4 && !shiftDown) { fl.core.eDy_ = -1; fl.core.dispatch(Event.mouseWheel, rec.widget); }
            else if (mb == 5 && !shiftDown) { fl.core.eDy_ = 1; fl.core.dispatch(Event.mouseWheel, rec.widget); }
            else if (mb == 6 || (mb == 4 && shiftDown)) { fl.core.eDx_ = -1; fl.core.dispatch(Event.mouseWheel, rec.widget); }
            else if (mb == 7 || (mb == 5 && shiftDown)) { fl.core.eDx_ = 1; fl.core.dispatch(Event.mouseWheel, rec.widget); }
            else
            {
                // X11 pseudo button numbers 4-7 are the wheel (handled
                // above), so real mouse *buttons* are 1-3 (left/middle/
                // right), 8-9 (side buttons back/forward, remapped to
                // FLTK's own 4/5 -- FL_BUTTON4/FL_BUTTON5 -- since those
                // numbers are free once 4/5 mean "wheel" in X's own
                // numbering, matching FLTK; confirmed against real
                // hardware (a Logitech MX Master 3S -- see
                // smoke-tests/side_buttons.d), or anything else a mouse
                // happens to expose (e.g. a third side/gesture button
                // delivered as X button 10). Unlike FLTK's Fl_x.cxx
                // (which has no case at all past 8/9), any such extra
                // button number is forwarded here as a real
                // Event.push/Event.release with eventButton() reporting
                // the true number, rather than silently dropped --
                // deliberately going beyond FLTK, on the reasoning
                // that a click a widget's handle() can react to (e.g. an
                // OpenGL/Cairo canvas binding a function to it) is more
                // useful than silence, and costs nothing to widgets that
                // don't care since it's still just an ordinary
                // Event.push/Event.release. The persistent held-state
                // bitmask (eState_/eventButtons()) is deliberately NOT
                // extended to cover it -- FL_BUTTON(n) is FLTK's own
                // documented "undefined if n outside 1..5", and
                // stateButton1 << (mb - 1) would overflow a 32-bit
                // EventState for any mb past 5 -- so held-state queries
                // stay limited to buttons 1-5 exactly as FLTK
                // defines them; only the one-shot push/release and
                // eventButton() are unbounded.
                if (mb == 8) mb = 4; // side button 1 (back) -> FL_BUTTON4
                else if (mb == 9) mb = 5; // side button 2 (forward) -> FL_BUTTON5
                fl.core.eKeysym_ = button + mb;
                // Xlib's own xbutton.state field has no bits for
                // buttons past 5, so unlike buttons 1-3 (whose held
                // state setEventXY() re-derives every event straight
                // from that field via translateState()), buttons 4/5
                // need this port to remember their own held state
                // itself -- matching FLTK's xbutton_state -- and
                // fold it into eState_ on every event (see
                // setEventXY()).
                if (mb >= 1 && mb <= 5) fl.core.eState_ |= stateButton1 << (mb - 1);
                if (mb == 4) xbuttonState_ |= stateButton4;
                if (mb == 5) xbuttonState_ |= stateButton5;
                checkdouble();
                fl.core.dispatch(Event.push, rec.widget);
            }
        }
        break;

    case ButtonRelease:
        if (auto rec = find(ev.xbutton.window))
        {
            setEventXY(rec.widget, ev.xbutton.x, ev.xbutton.y, ev.xbutton.x_root,
                ev.xbutton.y_root, ev.xbutton.state, ev.xbutton.time);

            int mb = ev.xbutton.button;
            if (mb < 4 || mb > 7)
            {
                // Wheel "buttons" (4-7) generate no ButtonRelease
                // handling FLTK either -- FL_MOUSEWHEEL is a
                // one-shot event, not press/hold. Side buttons (8/9)
                // remap to FL_BUTTON4/5 same as ButtonPress above; any
                // other button number (see the ButtonPress case's own
                // doc comment) is forwarded as-is.
                if (mb == 8) mb = 4;
                else if (mb == 9) mb = 5;
                fl.core.eKeysym_ = button + mb;
                if (mb >= 1 && mb <= 5) fl.core.eState_ &= ~(stateButton1 << (mb - 1));
                if (mb == 4) xbuttonState_ &= ~stateButton4;
                if (mb == 5) xbuttonState_ &= ~stateButton5;
                fl.core.dispatch(Event.release, rec.widget);
            }
        }
        break;

    case MotionNotify:
        if (auto rec = find(ev.xmotion.window))
        {
            setEventXY(rec.widget, ev.xmotion.x, ev.xmotion.y, ev.xmotion.x_root,
                ev.xmotion.y_root, ev.xmotion.state, ev.xmotion.time);
            // "is a button currently held" is read from fl.core.pushed()
            // (set by the FL_PUSH path), not from xmotion.state's
            // button-mask bits -- fl.core.handle()'s own FL_MOVE/FL_DRAG
            // case does that upgrade, matching FLTK.
            fl.core.dispatch(Event.move, rec.widget);
        }
        break;

    case EnterNotify:
        // NotifyInferior fires when the pointer crosses between a
        // window and a *child* window it owns -- FLTK skips it so
        // subwindow transitions don't spuriously re-trigger FL_ENTER on
        // the parent. Genuinely reachable now that real subwindows exist.
        if (ev.xcrossing.detail == NotifyInferior) break;
        if (auto rec = find(ev.xcrossing.window))
        {
            setEventXY(rec.widget, ev.xcrossing.x, ev.xcrossing.y, ev.xcrossing.x_root,
                ev.xcrossing.y_root, ev.xcrossing.state, ev.xcrossing.time);
            // fl.group's handle() already has an Event.enter case that
            // hit-tests children and updates belowmouse() -- this just
            // needs to reach it, matching FLTK's set_event_xy() +
            // `event = FL_ENTER` (FLTK then falls through to the
            // shared `return Fl::handle(event, window)` at the bottom
            // of fl_handle(); this port calls handle() directly since
            // there's no shared tail to fall through to).
            fl.core.dispatch(Event.enter, rec.widget);
        }
        break;

    case LeaveNotify:
        if (ev.xcrossing.detail == NotifyInferior) break;
        if (auto rec = find(ev.xcrossing.window))
        {
            setEventXY(rec.widget, ev.xcrossing.x, ev.xcrossing.y, ev.xcrossing.x_root,
                ev.xcrossing.y_root, ev.xcrossing.state, ev.xcrossing.time);
            // FLTK defers the actual FL_LEAVE dispatch to a later
            // do_queued_events() pass keyed off fl_xmousewin==0 (that
            // indirection exists to distinguish "left this window for
            // one of our own subwindows" from "left FLTK entirely",
            // which only matters once subwindows exist). Without
            // subwindows, leaving the window's boundary always means
            // leaving every widget under the pointer, so this can go
            // straight to fl.core.belowmouse(null) -- the same call
            // FLTK's own leave path bottoms out at, and it already
            // does the right thing: walk up from the current
            // belowmouse() widget sending FL_LEAVE to every ancestor
            // (Widget.contains(null) is always false, so the whole
            // chain gets notified), matching fl.group's Event.enter
            // case in reverse.
            fl.core.belowmouse(null);
        }
        break;

    case FocusIn:
        // The direct equivalent of FLTK's FocusIn case (Fl_x.cxx),
        // minus poll_clipboard_owner() (a separate, unrelated fallback
        // clipboard-change-polling mechanism this port's own direct
        // SelectionClear/SelectionNotify handling doesn't need). The
        // XIM input-context focus call: ximActivate()
        // recreates the input context if the focused *window* changed
        // (matching FLTK's own xim_activate()'s "brute force" comment
        // -- see that function's own doc comment). No xfocus.mode/detail
        // filtering here, matching FLTK -- it doesn't filter on
        // those fields either, unconditionally treating every FocusIn as
        // real. Routes through fl.core.fixFocus() (FLTK's
        // fl_fix_focus(), NOT a generic Event.focus dispatch to the
        // window -- see that function's own doc comment for why the
        // distinction matters), which restores focus to whichever child
        // had it last, or the first/last focusable child if none.
        //
        // `XSetICFocus()`: FLTK's own `fl_handle()` calls this unconditionally
        // in its `case FocusIn:` -- a *separate* call from
        // `xim_activate()`'s own internal `XSetICValues(..., XNFocus
        // Window, ...)` re-point, which only runs when the focused
        // *window* actually changed. Without this call, `FocusOut`'s
        // `XUnsetICFocus()` (below) would have no matching "focus came
        // back"
        // signal on the very next `FocusIn` whenever the window itself
        // *doesn't* change (e.g. tabbing between two widgets in the same
        // window, or a window manager's focus-follows-mouse policy
        // firing on ordinary mouse movement) -- the input method's own
        // compose/dead-key state machine would stop engaging after that,
        // even though basic `Xutf8LookupString()` calls keep succeeding.
        ximActivate(ev.xany.window);
        if (ximIc_ !is null) XSetICFocus(ximIc_);
        if (auto rec = find(ev.xany.window))
            fl.core.fixFocus(rec.widget);
        break;

    case FocusOut:
        // ditto, plus the real XUnsetICFocus() call. Matches FLTK's own FL_UNFOCUS
        // handling exactly otherwise: unconditionally clears focus
        // (fl.core.fixFocus(null), forwarding to focus(null)) rather
        // than checking which window this event was for -- FLTK
        // doesn't check either, since a well-behaved X server only
        // ever sends FocusOut for whichever window is actually losing
        // focus, so there's nothing to disambiguate.
        if (ximIc_ !is null) XUnsetICFocus(ximIc_);
        fl.core.fixFocus(null);
        break;

    case KeymapNotify:
        // Ported from Fl_x.cxx's own `case KeymapNotify:` -- a wholesale refresh of keyVector_
        // (see that field's own doc comment for the gap this closes:
        // without it, a key released while a *different* window had
        // focus never generates a KeyRelease this window sees, so it
        // could appear stuck "held" until the next explicit getKey()
        // call happened to correct it). The X server generates this
        // automatically right after any EnterNotify/FocusIn on a window
        // selecting KeymapStateMask (see that mask's own doc comment in
        // fl.xlib) -- not something this port requests separately.
        keyVector_[] = ev.xkeymap.key_vector[];
        break;

    case KeyPress:
    case KeyRelease:
        // Autorepeat detection, ported from the KEYPRESS/KeyRelease
        // handling in Fl_x.cxx's fl_handle(): X sends a fake KeyRelease
        // immediately before each repeat KeyPress while a key is held
        // down (a back-compatibility quirk FLTK's own comment
        // calls "stupid"; XkbSetDetectableAutoRepeat() would fix it at
        // the source but is itself broken on several real-world
        // distros per that same comment, so FLTK doesn't rely on
        // it either). Detected by peeking (not yet consuming) the next
        // queued event: if it's a KeyPress for the exact same keycode
        // at the exact same timestamp, this KeyRelease is fake --
        // consume that peeked KeyPress now and let the shared logic
        // below process *it* instead (ev.type is re-read fresh after
        // the overwrite, so the existing `if (ev.type == KeyPress)`
        // branch naturally does the right thing). Net effect: a held,
        // autorepeating key produces a stream of FL_KEYDOWN only, never
        // an FL_KEYUP in between -- matching FLTK. The real
        // FL_KEYUP still fires normally once the key is actually
        // released (the peek then finds no matching immediate
        // KeyPress).
        if (ev.type == KeyRelease && XPending(display_))
        {
            XEvent peek;
            XPeekEvent(display_, &peek);
            if (peek.type == KeyPress && peek.xkey.keycode == ev.xkey.keycode
                && peek.xkey.time == ev.xkey.time)
                XNextEvent(display_, &ev); // consume it; ev now holds the real KeyPress
        }

        if (auto rec = find(ev.xkey.window))
        {
            setEventXY(rec.widget, ev.xkey.x, ev.xkey.y, ev.xkey.x_root, ev.xkey.y_root,
                ev.xkey.state, ev.xkey.time);

            // Level-0 (unshifted) keysym: matches FLTK re-fetching
            // via XKeycodeToKeysym(..., 0) rather than trusting
            // XLookupString()'s keysym out-param, so shortcut-matching
            // stays shift-invariant (see fl.core.testShortcut()'s own doc
            // comment on this).
            Keysym keysym = cast(Keysym) XKeycodeToKeysym(display_, ev.xkey.keycode, 0);

            // NumLock/keypad remapping, ported from the XK_KP_F1..
            // XK_KP_Delete handling in Fl_x.cxx: a keypad key's
            // level-0 keysym (what was just fetched above) is one of
            // 15 "keypad function" keysyms in the range 0xff91-0xff9f
            // (XK_KP_F1..XK_KP_Delete) -- what the key does with
            // NumLock OFF. Its level-1 keysym (index 1 below) is what
            // it does with NumLock ON, normally a plain digit or
            // decimal point. Neither the level-0 fetch above nor
            // XLookupString() (used below for eText_) know about this
            // distinction on their own, so this remaps eKeysym_ to
            // whichever FLTK meaning actually applies right now: an
            // `fl.enumerations.kp`-tagged digit, or the arrow/Home/
            // End/etc. special key it represents with NumLock off --
            // matters for both shortcut-matching and fl.group's
            // arrow-key navigation. Not ported: the matching
            // kp_buffer[0] text override FLTK does for the
            // NumLock-on digit case -- FLTK's C string aliasing
            // lets that retroactively edit `Fl::e_text` after the fact
            // (see the doc comment above eText_'s assignment below),
            // which doesn't translate to this port's value-copied
            // `string`; XLookupString() already reports the right
            // digit character as text on its own on a standard setup
            // (it independently honors the live NumLock modifier),
            // so this is a narrow edge case, not a correctness gap for
            // the common case.
            if (keysym >= 0xff91 && keysym <= 0xff9f)
            {
                Keysym keysym1 = cast(Keysym) XKeycodeToKeysym(display_, ev.xkey.keycode, 1);
                bool isDigitForm = keysym1 <= 0x7f || (keysym1 > 0xff9f && keysym1 <= kpLast);
                if (isDigitForm)
                    fl.core.eOriginalKeysym_ = keysym1 | kp;

                if ((ev.xkey.state & Mod2Mask) && isDigitForm)
                    keysym = keysym1 | kp;
                else
                {
                    static immutable Keysym[15] kpFunctionTable = [
                        f + 1, f + 2, f + 3, f + 4,
                        home, left, up, right,
                        down, pageUp, pageDown, end,
                        cast(Keysym) 0xff0b, /* XK_Clear, for KP_Begin */
                        insert, deleteKey,
                    ];
                    keysym = kpFunctionTable[keysym - 0xff91];
                }
            }
            else
                fl.core.eOriginalKeysym_ = keysym;

            fl.core.eKeysym_ = keysym;

            // Any keyboard activity breaks a pending double/triple-click
            // sequence, matching FLTK's unconditional `Fl::e_is_click
            // = 0` at the tail of this case (in addition to whatever
            // setEventXY() above already did based on time/movement).
            fl.core.eIsClick_ = false;

            // Incrementally keep keyVector_ (see its own doc comment)
            // in sync, matching FLTK's own KeyPress/KeyRelease
            // bit-set/-clear in Fl_x.cxx's fl_handle() -- what makes
            // eventKey() usable without a getKey() call first.
            {
                uint keycode = ev.xkey.keycode;
                if (ev.type == KeyPress)
                    keyVector_[keycode / 8] |= (1 << (keycode % 8));
                else
                    keyVector_[keycode / 8] &= ~(1 << (keycode % 8));
            }

            if (ev.type == KeyPress)
            {
                // Real input-method text composition: the plain
                // XLookupString() path below never composes dead
                // keys/CJK input and -- for any character above plain
                // ASCII -- returns locale-dependent 8-bit bytes that
                // this port's own `eText_ = buf[0 .. len].idup` would then
                // wrongly treat as already-UTF-8. FLTK avoids this in
                // its *own* non-XIM fallback by
                // re-encoding via `fl_utf8encode(XKeysymToUcs(keysym))`,
                // a ~300-line keysym-to-
                // Unicode table this port doesn't carry -- see this
                // case's own note below on why that fallback is
                // deliberately not ported here. When an input context
                // exists (the common case -- XIM opens successfully on
                // essentially any real X11 system, even with no fancy
                // IME server running, via its own always-available
                // built-in fallback), `Xutf8LookupString()` is used
                // instead of `XLookupString()` for the *text* only --
                // the keysym computed above (for shortcut-matching) is
                // untouched either way, matching FLTK's own
                // `keysym = fl_KeycodeToKeysym(...)` re-fetch after the
                // lookup call, which discards whatever keysym the
                // lookup itself produced.
                int len;
                if (ximIc_ !is null)
                {
                    if (ximBuffer_.length == 0) ximBuffer_.length = 64;
                    Status status;
                    KeySym composedKeysym;
                    len = Xutf8LookupString(ximIc_, &ev.xkey, ximBuffer_.ptr,
                        cast(int) ximBuffer_.length, &composedKeysym, &status);
                    while (status == XBufferOverflow)
                    {
                        ximBuffer_.length = ximBuffer_.length * 2;
                        len = Xutf8LookupString(ximIc_, &ev.xkey, ximBuffer_.ptr,
                            cast(int) ximBuffer_.length, &composedKeysym, &status);
                    }
                    fl.core.eText_ = ximBuffer_[0 .. len].idup;
                }
                else
                {
                    // No input context at all (XOpenIM()/XCreateIC()
                    // failed in initXim() -- rare). Falls back to the
                    // plain XLookupString() path this port always had;
                    // deliberately does NOT also port FLTK's own
                    // `fl_utf8encode(XKeysymToUcs(keysym))` correction
                    // for non-ASCII Latin-1/2/3/4 characters in this
                    // fallback (a large, mechanically-transcribed
                    // keysym-to-Unicode table with no other use in this
                    // port) -- with XIM available on essentially every
                    // real deployment, this fallback is a rare degraded
                    // path FLTK itself only reaches under the same
                    // circumstance, not a corner this port cuts that
                    // FLTK doesn't also effectively cut in practice.
                    char[32] buf;
                    KeySym unused;
                    len = XLookupString(&ev.xkey, buf.ptr, cast(int) buf.length, &unused, null);
                    fl.core.eText_ = buf[0 .. len].idup;
                }
                fl.core.dispatch(Event.keyDown, rec.widget);
            }
            else
            {
                fl.core.eText_ = "";
                fl.core.dispatch(Event.keyUp, rec.widget);
            }
        }
        break;

    default:
        break;
    }
}

/**
 * Translates Xlib's own modifier/button-held bits (XKeyEvent.state/
 * XButtonEvent.state/XMotionEvent.state) into fl.core's event-state
 * bits. Turns out to be a direct masked shift, not a real lookup table
 * -- Xlib's bit positions for Shift/Lock/Control/Mod1-5/Button1-3 line
 * up 1:1 with fl.enumerations' stateShift/stateCapsLock/stateCtrl/
 * stateAlt/.../stateButton1-3 (all `1 << (16 + n)` for Xlib bit n),
 * confirmed against FLTK's own `Fl::e_state = (state &
 * event_state_mask) << 16`.
 *
 * Side-button (X button 8/9, remapped to FL_BUTTON4/5) state is
 * deliberately excluded from the mask below -- Button4Mask/Button5Mask
 * in Xlib's own state field refer to the scroll wheel, not side
 * buttons, and Xlib carries no held-state bits for buttons past 3 at
 * all. That's tracked separately, matching FLTK's own
 * `xbutton_state` approach -- see `xbuttonState_`'s doc comment and
 * `setEventXY()`, which folds it into `eState_` on every event; this
 * function's own return value alone never carries it.
 */
private EventState translateState(uint xState)
{
    enum uint eventStateMask = ShiftMask | LockMask | ControlMask
        | Mod1Mask | Mod2Mask | Mod3Mask | Mod4Mask | Mod5Mask
        | Button1Mask | Button2Mask | Button3Mask;
    return cast(EventState)((xState & eventStateMask) << 16);
}

/**
 * Records an X event's position/state into fl.core's globals -- shared
 * by every case above that carries this common field layout
 * (ButtonPress/Release, MotionNotify, EnterNotify/LeaveNotify,
 * KeyPress/Release all have their own X/Y/root-X/root-Y/state/time
 * fields at the same relative meaning, which is why FLTK's
 * set_event_xy() (Fl_x.cxx) gets away with a single `fl_xevent->
 * xbutton.*` cast regardless of the real event type -- this port's
 * `XEvent` only unions the specific structs it actually reads rather
 * than a raw byte blob, so the fields are passed in explicitly
 * instead).
 *
 * Also ported from set_event_xy(): cancels a pending click
 * (fl.core.eIsClick_) once the pointer has moved more than 3px or
 * 1000ms have passed since the position checkdouble() last recorded --
 * matching FLTK's literal thresholds exactly (not configurable
 * FLTK either).
 */
private void setEventXY(FlWindow win, int x, int y, int xRoot, int yRoot, uint xState, Time time)
{
    // x/y/xRoot/yRoot arrive as raw device pixels straight from the X
    // event; divided down to FLTK units here, matching FLTK's own
    // `Fl::e_x_root = fl_xevent->xbutton.x_root/s;` etc. in
    // `set_event_xy(Fl_Window *win)`.
    // The click-cancel distance check below compares the already-
    // divided (FLTK-unit) values too, same as FLTK -- its "3"
    // threshold means 3 FLTK units, not 3 raw device pixels.
    //
    // **`screenScale(win.screenNum())`, not a hardcoded screen 0** --
    // matches FLTK's own real
    // `set_event_xy()` exactly: `Fl::screen_driver()->scale(Fl_Window_
    // Driver::driver(win)->screen_num())`, the event's *own* window's
    // screen, not a fixed index. An earlier version of this function
    // took no window parameter at all and hardcoded `screenScale(0)`,
    // silently wrong for a window on any screen but the first.
    float s = screenScale(win.screenNum());
    int fxRoot = cast(int)(xRoot / s);
    int fyRoot = cast(int)(yRoot / s);

    fl.core.eXRoot_ = fxRoot;
    fl.core.eX_ = cast(int)(x / s);
    fl.core.eYRoot_ = fyRoot;
    fl.core.eY_ = cast(int)(y / s);
    // xbuttonState_ folded in on every event, matching FLTK's own
    // `Fl::e_state = ((state & event_state_mask) << 16) | xbutton_state;`
    // -- see xbuttonState_'s own doc comment for why Xlib's state field
    // alone can't recover the side buttons' held state.
    fl.core.eState_ = translateState(xState) | xbuttonState_;
    lastEventTime_ = time;

    import std.math : abs;

    if (abs(fxRoot - px_) + abs(fyRoot - py_) > 3 || time >= ptime_ + 1000)
        fl.core.eIsClick_ = false;
}

/**
 * Called from the ButtonPress case's real-button branch (never for the
 * scroll-wheel pseudo-buttons, matching FLTK): bumps
 * fl.core.eventClicks() if this press is the same button as the last
 * one and setEventXY() hasn't already cancelled the pending click (too
 * far/too slow), otherwise starts a new click run at 0. Ported from
 * checkdouble() (Fl_x.cxx) -- see px_/py_/ptime_/lastClickKeysym_'s doc
 * comment for how FLTK's single overloaded `int e_is_click` (0 =
 * false, nonzero = the pending click's keysym) maps onto this port's
 * separate bool eIsClick_ + private lastClickKeysym_.
 */
private void checkdouble()
{
    if (fl.core.eIsClick_ && lastClickKeysym_ == fl.core.eKeysym_)
        fl.core.eClicks_++;
    else
        fl.core.eClicks_ = 0;

    lastClickKeysym_ = fl.core.eKeysym_;
    fl.core.eIsClick_ = true;

    px_ = fl.core.eXRoot_;
    py_ = fl.core.eYRoot_;
    ptime_ = lastEventTime_;
}

// XStoreName needs a null-terminated C string; this port otherwise
// avoids std.string.toStringz at call sites, so it's wrapped once here.
private const(char)* toStringzTemp(string s)
{
    import std.string : toStringz;

    return toStringz(s);
}
