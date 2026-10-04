/*
 * Windows platform glue for FLTK 1.5.0's window-creation/event-loop layer
 * (~/Repositories/fltk), the Windows
 * analogue of `fl.platform_x11`. Not a 1:1 port of a single FLTK
 * file -- FLTK spreads the real logic across `src/Fl_win32.cxx`
 * (3039 lines, itself free functions + globals, same "namespace Fl as
 * free functions" shape `fl.core` already uses -- the actual
 * `src/drivers/WinAPI/Fl_WinAPI_*_Driver.cxx` files are thin factory/
 * driver-class shells around it, mirroring the relationship
 * `fl.platform_x11` already has to FLTK's many `Fl_X11_*` files).
 *
 * DELIBERATE ARCHITECTURE DEVIATION, same reasoning as `fl.platform_x11`'s
 * own top comment -- **and see `PORTING.md`'s `FL/x.H` row for why this
 * project now treats that as a settled criterion, not "wait for a second
 * platform"**: FLTK's `Fl_Screen_Driver`/`Fl_Window_Driver` hierarchy
 * exists to let several concrete backends coexist and be chosen *at
 * runtime, within one process* (the same reason `fl.graphics_driver.
 * GraphicsDriver` genuinely is real and polymorphic -- SVG/PostScript/GL
 * output can all be active in the same running fldtk program). X11 and
 * Windows never do that: a given compiled fldtk binary targets exactly
 * one OS, so which windowing backend is active is a `version()` choice
 * D's compiler already resolves for free, with no runtime dispatch need
 * at all. So this stays a concrete, non-virtual module, exactly like
 * `fl.platform_x11` -- not a second subclass under a new abstract base.
 *
 * SCOPE: open a top-level window, pump Win32 messages via a
 * `MsgWaitForMultipleObjects()`-based wait
 * folding in `fl.core`'s timer queue, translate mouse/keyboard/paint/
 * resize/close into `fl.core`'s existing event-state fields and dispatch
 * via `fl.core.dispatch()`, and repaint via `fl.gdi_graphics_driver.
 * GdiGraphicsDriver` (this module's own `currentDriver`, set once at
 * display-open time).
 *
 * **Real damage-rectangle-clipped repaint**: `accumulateDamage
 * Rect()`/`clearDamageRegion()` mirror `fl.platform_x11.accumulateDamage()`/
 * `clearDamageRegion()`'s identical bounding-box-merge algorithm, and
 * `WM_PAINT`'s own case clips `draw()` to the accumulated rectangle
 * (`fl.draw.pushClip()`/`popClip()`) instead of always drawing the whole
 * window -- see `WindowRecord`'s own doc comment and `accumulateDamage
 * Rect()`'s for the full mechanism, including the one real difference
 * from X11's version (no separate deferred-flush pass; `InvalidateRect()`
 * fires immediately since Windows has no equivalent "accumulate now,
 * flush once per loop iteration" primitive to defer through).
 *
 * Real GDI text (`fl.gdi_graphics_driver`'s own
 * `GdiGraphicsDriver`/`fl.draw.d`'s `version (Windows)` text leaves) --
 * this module itself never touches
 * `fl.draw.d` directly either way, text rendering happens entirely
 * through the `currentDriver` dispatch this module wires up once, at
 * `ensureGraphicsDriver()`.
 *
 * Cursors (stock + custom RGBA), real multi-monitor screen enumeration,
 * DPI-awareness activation, and scale-seeded per-primitive GDI scaling
 * are all real, including real
 * `fake_X_wm()`-based decoration-size negotiation feeding both initial
 * window creation (`createWindow()`) and application-initiated resize
 * (`resizeWindow()`).
 *
 * The clipboard is real:
 * `setSelectionOwner()`/`pasteText()`/`pasteImage()`/
 * `clipboardContains()` back `fl.core.copy()`/`paste()`/
 * `clipboardContains()`'s Windows branches -- real `OpenClipboard()`/
 * `SetClipboardData(CF_UNICODETEXT, ...)` for copy, `GetClipboardData()`
 * for paste (text always; image only the common direct-DIB case, see
 * `pasteImage()`'s own doc comment for the narrower, documented gap).
 * Genuinely synchronous both ways, unlike X11's async `SelectionNotify`
 * round trip. `Fl::add_clipboard_notify()`'s Windows backing is real:
 * the classic `SetClipboardViewer()`/
 * `WM_DRAWCLIPBOARD`/`ChangeClipboardChain()` viewer-chain mechanism,
 * ported verbatim from `Fl_win32.cxx`'s file-scope `fl_clipboard_notify_
 * *()` functions and `WndProc()`'s own `WM_CHANGECBCHAIN`/
 * `WM_DRAWCLIPBOARD` cases (see that section, near `clipboardNotifyChange()`,
 * for the full mechanism).
 *
 * Window state is real:
 * `fullscreenOn()`/`fullscreenOff()`/`makeFullscreen()`, `maximizeOn()`/
 * `maximizeOff()` (plus `WM_SIZE`-based tracking of an externally
 * triggered maximize/restore), `iconizeWindow()` (including a genuinely
 * born-iconic `createWindow()` path when `iconize()` precedes the first
 * `show()`), `setMinMax()` (real `WM_GETMINMAXINFO` live size-range
 * enforcement), and `setIcons()`/`findBestIcon()` (real `WM_SETICON`
 * window icons, reusing the `imageToIcon()` helper already built for
 * custom cursor images) back `fl.window.Window`'s existing
 * platform-independent `fullscreen()`/`maximize()`/`iconize()`/
 * `icons()`/`icon()` surface. See that section's own doc comments for
 * the two deliberate, documented gaps (no shared default-icon cache,
 * and no fallback for maximizing a borderless window).
 *
 * Drag-and-drop is real: real
 * COM (`IDropTarget`/`IDropSource`/`IDataObject`/`DoDragDrop()`/
 * `RegisterDragDrop()`), not the simpler `WM_DROPFILES` shell mechanism.
 * Text-only
 * delivery, matching this port's own already-established X11/XDND MIME-
 * negotiation scope, but covering all three of FLTK's own source
 * formats (`CF_UNICODETEXT`, legacy `CF_TEXT`/CP1252, and `CF_HDROP`
 * dropped-file-lists) -- see that section's own doc comment.
 *
 * `ensureGraphicsDriver()` creates a real `fl.gdiplus_graphics_
 * driver.GdiPlusGraphicsDriver` by default instead of the plain
 * `GdiGraphicsDriver` -- antialiased line/polygon/arc/pie
 * drawing via real GDI+, falling back to plain GDI only if
 * `GdiplusStartup()` itself fails, matching FLTK's own actual
 * default build (`FLTK_GRAPHICS_GDIPLUS` defaults `ON`) rather than
 * the less-featured non-default path. See that module's own doc
 * comment for the full method-by-method port, including one confirmed
 * FLTK bug deviated from (cap/join dispatch) and one considered
 * adaptation (an arc's effective pen width) forced by this port's
 * already-established, already-scaled `lineWidth_` representation.
 *
 * Real subwindow support (`createWindow()`'s own
 * `WS_CHILD` branch): a subwindow (`win.parent() !is null`) gets a
 * real child `HWND` parented to its own containing window's `HWND`
 * instead of a separate top-level, ported from `Fl_WinAPI_Window_
 * Driver::makeWindow()`'s identical `if (w->parent())` branch
 * (`Fl_win32.cxx`). Mouse events need one extra step Linux's X11 side
 * doesn't (`mouseEvent()`'s own doc comment): Win32 delivers a raw
 * mouse message directly to whichever real `HWND` -- subwindow or
 * top-level -- is actually under the cursor, unlike X11's reduced
 * subwindow event mask (`ExposureMask` only), which means only the
 * top-level ever receives one there in the first place; `mouseEvent()`
 * walks up the parent chain first, converting coordinates, so the
 * shared `fl.core.dispatch()`/`sendEvent()` machinery (authored against
 * X11's "already the top-level" contract) sees the same shape on both
 * platforms.
 *
 * A genuine per-monitor scale array is real, with live `WM_DPICHANGED`
 * reaction, double-buffering (damage-rectangle-clipped repaint), and
 * NumLock/keypad remap.
 *
 * **Real IME support**: composed/committed input-
 * method text (CJK, the Windows emoji picker, ...) reaches this port's
 * widgets via `WndProc()`'s top-level
 * `WM_CHAR`/`WM_SYSCHAR` case (this is how *every* IME commit and
 * emoji-picker selection is actually delivered, arriving with no
 * preceding keydown this module claims itself).
 * See `charEvent()`'s own doc comment for the mechanism, `decodeCharUnit()`'s
 * for the real UTF-16 surrogate-pair merging that goes with it,
 * `fl.core.compose()`'s Windows branch for the real AltGr-aware dead-key
 * handling, and `enableIm()`/`disableIm()`/`setSpot()` for the rest of
 * the picture (the explicit on/off toggle API, and "over the spot"
 * composition-window positioning for `fl.text_display`'s existing call
 * site).
 *
 * Keyboard translation (`vkToKeysym()`) goes beyond FLTK's `ms2fltk()`
 * in two places: right Shift is told apart by scan code, and the
 * `VK_OEM_*` punctuation keys report the active layout's character
 * (`oemKeysym()`) instead of FLTK's hardcoded US one. Right Ctrl/Alt
 * and keypad Enter use the extended-key bit, as in FLTK.
 *
 * Windows only, matching this port's secondary target; the whole module
 * is inert (empty) on other platforms.
 *
 * NO `unittest` BLOCKS HERE, matching `fl.platform_x11`'s own reasoning:
 * everything here needs a real Win32 message loop / real window, so
 * `dub test` must keep working headlessly/in CI without one (and without
 * a Windows target at all, on this project's Linux development
 * machine). Verified instead by the user building this on a real Windows
 * machine with DMD and running the accompanying smoke test -- see
 * `smoke-tests/window_win32.d`.
 */
module fl.platform_win32;

version (Windows):

import core.sys.windows.windows;
// `core.sys.windows.windows` -> `ole2` -> `oleidl`/`unknwn` covers
// IDropTarget/IDropSource/IUnknown/the IID_* GUIDs already (all `public
// import`ed along that chain) -- but `objidl` (IDataObject/
// IEnumFORMATETC/FORMATETC/STGMEDIUM/TYMED_HGLOBAL) and `wtypes`
// (DVASPECT_CONTENT) are only plain, non-public imports inside `ole2`,
// so they need pulling in explicitly here.
import core.sys.windows.objidl;
// `DVASPECT_CONTENT` isn't itself an importable top-level symbol --
// it's a member of the `DVASPECT` enum (`enum DVASPECT { DVASPECT_
// CONTENT = 1, ... }`), so `import ... : DVASPECT_CONTENT;` doesn't
// resolve (a real compile error on a real Windows build, not caught
// when this was authored with no Windows toolchain available -- see
// this module's own doc comment). Import the enum type instead and
// alias the one member actually used, so every existing `DVASPECT_
// CONTENT` reference below keeps working unchanged.
import core.sys.windows.wtypes : DVASPECT;
private enum DVASPECT_CONTENT = DVASPECT.DVASPECT_CONTENT;
// Same story as `DVASPECT_CONTENT` just above: `TYMED_HGLOBAL` is a
// member of `objidl`'s own `enum TYMED`, and `DROPEFFECT_NONE`/`_COPY`/
// `_MOVE`/`_LINK` are members of `oleidl`'s `enum DROPEFFECT` (already
// in scope transitively via `core.sys.windows.windows` -> `ole2` ->
// `oleidl`, per the `objidl`/`wtypes` comment above) -- neither is an
// importable top-level symbol on its own.
private enum TYMED_HGLOBAL = TYMED.TYMED_HGLOBAL;
private enum DROPEFFECT_NONE = DROPEFFECT.DROPEFFECT_NONE;
private enum DROPEFFECT_COPY = DROPEFFECT.DROPEFFECT_COPY;
private enum DROPEFFECT_MOVE = DROPEFFECT.DROPEFFECT_MOVE;
private enum DROPEFFECT_LINK = DROPEFFECT.DROPEFFECT_LINK;
// `CF_HDROP`'s dropped-file-list fallback needs `HDROP`/`DragQueryFileW`
// (`core.sys.windows.shellapi`, already transitively public-imported via
// `core.sys.windows.windows`, so no new import for those two); the legacy
// `CF_TEXT`/CP1252 fallback needs `MultiByteToWideChar`/`CP_ACP`
// (`core.sys.windows.winnls`, NOT part of that transitive chain).
import core.sys.windows.winnls : MultiByteToWideChar, CP_ACP;
import core.time : Duration, dur, hours;
import std.array : join;
import std.utf : toUTF16, toUTF16z, toUTF8;

import fl.window : FlWindow = Window, resizeBugFix_;
import fl.enumerations : Event, Keysym, EventState, stateShift, stateCtrl, stateAlt,
    stateCapsLock, stateNumLock, stateButton1, stateButton2, stateButton3, stateButton4,
    stateButton5, stateButtons, button, backSpace, tab, enter, escape, home, left, up,
    right, down, pageUp, pageDown, end, insert, deleteKey, capsLock, numLock, shiftL, shiftR,
    kp, kpEnter, controlL, controlR, altL, altR, f, Beep, CursorShape = Cursor, damageExpose, damageOverlay, fdRead,
    white;
import fl.image : RGBImage;
import fl.draw : pushClip, popClip, fl_color, fl_rectf;
import fl.image_surface : ImageSurface, SurfaceDevice;
import fl.double_window : doubleWindowTypeTag;
import fl.overlay_window : OverlayWindow;
import fl.graphics_driver : currentDriver;
import fl.gdi_graphics_driver : GdiGraphicsDriver;
import gdiplusDriver = fl.gdiplus_graphics_driver;
import glWindow = fl.gl_window;
import fl.gl_window : GlWindow;
import fl.core;

// `core.sys.windows.imm` (transitively public-imported via `core.sys.
// windows.windows` -> ... already covers `HIMC`/`COMPOSITIONFORM`/
// `CFS_POINT`/`IACE_DEFAULT`/`ImmGetContext()`/`ImmSetCompositionWindow()`/
// `ImmReleaseContext()`/`ImmAssociateContext()` directly -- but not the
// "Ex" form FLTK actually calls (`ImmAssociateContextEx(HWND, HIMC,
// DWORD)`, which additionally accepts `IACE_DEFAULT` as a flag meaning
// "reassociate with this window's own default input context" rather
// than requiring the caller to have saved off the previous `HIMC`
// itself, the way the plain, already-bound `ImmAssociateContext()` would
// require). Declared by hand, linking `imm32.lib` directly (listed
// explicitly in `dub.sdl`) --
// matching this project's own established precedent for a system
// function druntime doesn't bind (`EnumDisplayMonitors`/`GetMonitorInfoW`)
// rather than FLTK's
// own `LoadLibrary("IMM32.DLL")`/`GetProcAddress()` dynamic-loading
// dance, which exists there purely for decades-obsolete pre-XP
// tolerance this project has no reason to carry either.
extern (Windows) BOOL ImmAssociateContextEx(HWND, HIMC, DWORD);

private
{
    struct WindowRecord
    {
        HWND hwnd;
        FlWindow widget;
        WindowRecord* next;

        /// Ported from `Fl_WinAPI_Window_Driver::cursor`/`custom_cursor`
        /// -- the window's current `HCURSOR` and whether it's one this
        /// module created itself (via `imageToIcon()`, needing
        /// `DestroyIcon()` when replaced) as opposed to a shared stock
        /// cursor from `LoadCursorW()` (owned by the system, never
        /// destroyed).
        HCURSOR cursor;
        bool customCursor;

        // Accumulated damage rectangle since the last WM_PAINT --
        // mirrors `fl.platform_x11`'s identically-named fields exactly,
        // see that module's own `WindowRecord.hasDamageRegion`'s doc
        // comment for the full reasoning behind the *bounding-box-only*
        // simplification and the `fullRepaintPending` flag's own separate
        // purpose). Logical (FLTK-unit) coordinates, matching X11's own
        // `damageX`/`damageY`/`damageW`/`damageH` -- `pushClip()`/`draw()`
        // both already scale internally (this driver's established
        // "fold scaling directly in" convention), so the clip rectangle
        // itself needs no scaling, only the real `InvalidateRect()` call
        // that schedules the resulting `WM_PAINT` does (see
        // `accumulateDamageRect()`'s own body).
        bool hasDamageRegion;
        int damageX, damageY, damageW, damageH;
        bool fullRepaintPending;

        /// True from just before `win.draw()` runs until just before the
        /// matching `EndPaint()` -- see `accumulateDamageRect()`'s own
        /// doc comment for why this exists (breaking a real, confirmed
        /// infinite-repaint storm).
        bool inPaint;

        // Real double-buffering -- mirrors `fl.platform_x11.WindowRecord.
        // offscreen`'s own Pixmap-based scheme exactly, just an `HBITMAP`
        // + its own memory `HDC` instead of an X `Pixmap`: any window
        // whose `type() == doubleWindowTypeTag` (`fl.double_window.
        // DoubleWindow`) draws into this off-screen bitmap first, then
        // `WM_PAINT`'s own case blits the whole thing onto the real
        // window in one `BitBlt()` -- see that case's own doc comment
        // for why a *whole-buffer* blit (not just the clipped damage
        // rect) is both simpler and correct here (the buffer persists
        // between paints, so its already-correct, unchanged pixels are
        // safe to re-blit alongside whatever `draw()` just refreshed).
        // A plain `Window` never allocates one at all, matching FLTK/
        // X11's own "double-buffering is opt-in via DoubleWindow, not a
        // universal default" behavior exactly, staying
        // faithful to FLTK's scope here rather than deviating.
        // `offscreenW`/`offscreenH` are device pixels (matching the real
        // on-screen window's own already-scaled size), so a resize (or a
        // live `WM_DPICHANGED`-driven scale change, once that's ported)
        // is detected and the buffer reallocated the same way `fl.
        // platform_x11.flushDamage()`'s own resize-detection already
        // works.
        HBITMAP offscreenBmp;
        HDC offscreenDc;
        HBITMAP offscreenOrigBmp; // the 1x1 stock bitmap CreateCompatibleDC() auto-selects; restored before deleting offscreenBmp, matching the already-established, already-bug-motivated "deselect before delete" pattern this module's own gdi_graphics_driver.d uses for pens (see that module's applyLineStyleUnscaled() doc comment for the real double-DeleteObject() bug that pattern exists to avoid)
        int offscreenW, offscreenH;
    }

    WindowRecord* first_;
    bool classRegistered_;
    GdiGraphicsDriver gdiDriver_;

    immutable(wchar)[] wndClassNameW = "FLDTK\0"w;
}

private WindowRecord* find(HWND hwnd)
{
    for (auto rec = first_; rec !is null; rec = rec.next)
        if (rec.hwnd == hwnd) return rec;
    return null;
}

/// The direct equivalent of `fl.platform_x11.firstWindowWidget()` --
/// backs `fl.core.firstWindow()`.
FlWindow firstWindowWidget()
{
    return first_ !is null ? first_.widget : null;
}

/// Ditto, `fl.platform_x11.nextWindowWidget()`.
FlWindow nextWindowWidget(FlWindow window)
{
    for (auto rec = first_; rec !is null; rec = rec.next)
        if (rec.widget is window) return rec.next !is null ? rec.next.widget : null;
    return null;
}

/// Ditto, `fl.platform_x11.makeWindowFirst()`.
void makeWindowFirst(FlWindow window)
{
    WindowRecord** pp = &first_;
    while (*pp !is null && (*pp).widget !is window)
        pp = &(*pp).next;
    if (*pp is null || *pp is first_) return;
    auto rec = *pp;
    *pp = rec.next;
    rec.next = first_;
    first_ = rec;
}

/// `package(fl)` (not `private`) since `fl.image_surface.ImageSurface`'s
/// constructor also calls this -- see that class's own
/// doc comment: an `ImageSurface` built and drawn into before any real
/// window has ever been shown (`shapedwindow.d`'s own `main()` does
/// exactly this) needs a real `GdiGraphicsDriver` to exist *first*,
/// since every `fl.draw` primitive routes through `currentDriver` on
/// this platform (unlike Linux, where `fl.draw` talks to Xlib directly
/// with no such indirection) -- without it, `beginOffscreen()`'s own
/// `if (driver is null ...) return;` guard silently no-ops the redirect,
/// so every drawing call into the surface's offscreen bitmap does
/// nothing at all, leaving it all-black. Idempotent (the `gdiDriver_
/// !is null` guard just below), so calling it here is a no-op on the
/// far more common path where a real window already exists.
package(fl) void ensureGraphicsDriver()
{
    if (gdiDriver_ !is null) return;
    gdiDriver_ = gdiplusDriver.createGraphicsDriver();
    currentDriver = gdiDriver_;
    ensureDpiAwareness();
    seedScaleFromPrimaryMonitor();
    fl.core.installScaleHandler();

    // Captured once, on the main (GUI) thread -- this is always the
    // thread that creates the first window -- so `wakeMainThread()` can
    // later `PostThreadMessageW()` to it from any worker thread. See
    // that function's own doc comment.
    mainThreadId_ = GetCurrentThreadId();

    // Ported from `open_display_platform()`'s own `OleInitialize(0L);`
    // -- OLE must be initialized once, process-wide, before any
    // `RegisterDragDrop()`/`DoDragDrop()` call. `dropTarget_` is the single shared `IDropTarget`
    // instance registered for every window, matching FLTK's own
    // single static `flDropTarget`/`flIDropTarget` (see that section's
    // own doc comment for why one shared instance -- not one per
    // window -- is the real FLTK design, not a simplification made
    // here).
    OleInitialize(null);
    dropTarget_ = new FLDropTarget;
}

/// The one process-wide plain (non-GL) `GdiGraphicsDriver`/
/// `GdiPlusGraphicsDriver` instance, created once by `ensureGraphicsDriver()`.
/// Exposed so `fl.image_surface.ImageSurface` can point its own `driver_`
/// field at it -- see that class's own constructor doc comment for why:
/// unlike Linux, where `currentDriver is null` already means "the native
/// platform drawing path" (so an `ImageSurface`'s driver-less `null`
/// naturally works), Windows has no such fallback -- *every* `fl.draw`
/// primitive requires a real, non-null `currentDriver` to draw anything
/// at all. Calls `ensureGraphicsDriver()` first so this is safe to call
/// before any window has ever been shown (matching `ImageSurface`'s own
/// constructor, which already does the same for exactly this reason).
package(fl) GdiGraphicsDriver plainGraphicsDriver()
{
    ensureGraphicsDriver();
    return gdiDriver_;
}

// ---------------------------------------------------------------------
// DPI-awareness -- ported from `Fl_WinAPI_Screen_Driver::
// open_display_platform()`/`desktop_scale_factor()` (`Fl_win32.cxx:495-
// 575`).
// ---------------------------------------------------------------------

private bool isDpiAware_;

/// `WM_DPICHANGED` -- not declared in this druntime version's
/// `core.sys.windows.winuser`, same gap this file's own `ensureDpiAwareness()`
/// doc comment already notes for the DPI-awareness APIs themselves. Value
/// from the Windows SDK's own `WinUser.h` (`0x02E0`), used by `wndProc()`'s
/// own `case dpiChangedMessage:`.
private enum uint dpiChangedMessage = 0x02E0;

/// Ported from `open_display_platform()`'s own DPI-awareness-activation
/// block, verbatim, including the real `GetProcAddress()`/`LoadLibrary()`
/// dance -- **not** a case for this module's usual "link the modern entry
/// point directly, this project doesn't target ancient Windows" call
/// (see `initScreens()`'s own note on `EnumDisplayMonitors`): unlike
/// that case, these DPI-awareness APIs (`Shcore.DLL`'s `GetProcessDpi
/// Awareness`/`SetProcessDpiAwareness`/`GetDpiForMonitor`,
/// `DPI_AWARENESS_CONTEXT`) aren't declared in this druntime version's
/// `core.sys.windows.*` bindings *at all* -- there's no direct-link
/// option to prefer over the dynamic-loading one, so this ports
/// FLTK's own real fallback chain exactly, not by choice but by
/// necessity (which happens to also be the more faithful port anyway).
private void ensureDpiAwareness()
{
    alias GetProcessDpiAwarenessFn = extern (Windows) HRESULT function(HANDLE, int*) nothrow;
    alias SetProcessDpiAwarenessContextFn = extern (Windows) BOOL function(void*) nothrow;
    alias SetProcessDpiAwarenessFn = extern (Windows) HRESULT function(int) nothrow;

    HMODULE shcore = LoadLibraryA("Shcore.DLL");
    auto getAwareness = shcore !is null
        ? cast(GetProcessDpiAwarenessFn) GetProcAddress(shcore, "GetProcessDpiAwareness") : null;

    int awareness = 0; // PROCESS_DPI_UNAWARE
    if (getAwareness is null || getAwareness(null, &awareness) != 0 /* S_OK */)
        awareness = 0;

    if (awareness == 2 /* PROCESS_PER_MONITOR_DPI_AWARE */) isDpiAware_ = true;

    if (awareness == 0)
    {
        HMODULE user32 = LoadLibraryA("User32.DLL");
        auto setContext = user32 !is null
            ? cast(SetProcessDpiAwarenessContextFn) GetProcAddress(user32, "SetProcessDpiAwarenessContext") : null;
        if (setContext !is null)
        {
            void* perMonitorAwareV2 = cast(void*)(-4);
            isDpiAware_ = setContext(perMonitorAwareV2) != FALSE;
        }
        if (!isDpiAware_)
        {
            auto setAwareness = shcore !is null
                ? cast(SetProcessDpiAwarenessFn) GetProcAddress(shcore, "SetProcessDpiAwareness") : null;
            if (setAwareness !is null && setAwareness(2 /* PROCESS_PER_MONITOR_DPI_AWARE */) == 0)
                isDpiAware_ = true;
        }
    }
}

/// The OS's own raw, zoom-*un*aware per-monitor DPI, as last recorded --
/// ported from `Fl_WinAPI_Screen_Driver::dpi[MAX_SCREENS][2]` (this port
/// only ever needs the X component, matching every other single-axis DPI
/// assumption already elsewhere in this file), **deliberately separate**
/// from `fl.core.screenScale()`'s own zoom-*inclusive* per-screen table.
/// Indexed in parallel with `screens_`, resized alongside it in
/// `seedScaleFromPrimaryMonitor()`.
///
/// The distinction matters for a real, traced-through bug: without it, a
/// window dragged onto an already-Ctrl-+/-zoomed monitor would overwrite
/// that monitor's zoom with the OS's own unzoomed DPI report the moment
/// `dpiChangedMessage` fires for the arriving window -- `WM_DPICHANGED`'s
/// `wParam` always carries the *raw* OS DPI, never anything zoom-
/// inclusive, so comparing it directly against `fl.core.screenScale()`
/// (which *is* zoom-inclusive) can't tell "this screen's own baseline
/// genuinely changed" apart from "this screen was already known, just
/// zoomed differently than its own raw DPI alone would suggest." Matches
/// FLTK's own real distinction exactly -- see `dpiChangedMessage`'s
/// own doc comment for the full mechanism.
private float[] rawDpiX_;

/// The vertical counterpart of `rawDpiX_` (FLTK's `dpi[n][1]`), only
/// read by `screenDpi()`. Kept in step with `rawDpiX_`.
private float[] rawDpiY_;

/// Ported from `Fl_WinAPI_Screen_Driver::screen_dpi()`: screen `n`'s
/// DPI as Windows reports it (96 at 100% scaling), or `0` for both if
/// `n` is out of range. Backs `fl.core.screenDpi()`'s Windows branch.
void screenDpi(out float h, out float v, int n)
{
    ensureGraphicsDriver(); // seeds rawDpiX_/rawDpiY_ (FLTK: `if (num_screens < 0) init();`)
    h = v = 0.0f;
    if (n >= 0 && n < rawDpiX_.length)
    {
        h = rawDpiX_[n];
        v = rawDpiY_[n];
    }
}

/// Bounds-checked read of `rawDpiX_`, `96.0` (the universal Windows
/// DPI baseline) for an out-of-range screen.
private float rawDpiXFor(int screen)
{
    return (screen >= 0 && screen < rawDpiX_.length) ? rawDpiX_[screen] : 96.0f;
}

/// ditto (write)
private void rawDpiXFor(int screen, float dpi)
{
    if (screen >= 0 && screen < rawDpiX_.length) rawDpiX_[screen] = dpi;
}

/// Ported from `Fl_WinAPI_Screen_Driver::desktop_scale_factor()`'s own
/// per-monitor `GetDpiForMonitor()` loop, seeding every screen's own
/// independent entry (`fl.core.screenScale_`, a real per-screen array).
/// `MonitorFromRect(&screens[ns],
/// MONITOR_DEFAULTTONEAREST)` per screen, matching FLTK's own loop
/// exactly (`for (ns = 0; ns < screen_count(); ns++) { hm = fl_
/// MonitorFromRect(&screens[ns], ...); fl_GetDpiForMonitor(hm, 0, &dpiX,
/// &dpiY); scale(ns, dpiX/96.f); }`).
private void seedScaleFromPrimaryMonitor()
{
    initScreens();

    alias GetDpiForMonitorFn = extern (Windows) HRESULT function(HMONITOR, int, UINT*, UINT*) nothrow;

    HMODULE shcore = isDpiAware_ ? LoadLibraryA("Shcore.DLL") : null;
    auto getDpi = shcore !is null
        ? cast(GetDpiForMonitorFn) GetProcAddress(shcore, "GetDpiForMonitor") : null;

    rawDpiX_.length = screens_.length;
    rawDpiY_.length = screens_.length;

    foreach (i, ref s; screens_)
    {
        float dpiX = 96.0f, dpiY = 96.0f;
        if (getDpi !is null)
        {
            RECT r;
            r.left = s.x;
            r.top = s.y;
            r.right = s.x + s.w;
            r.bottom = s.y + s.h;
            HMONITOR mon = MonitorFromRect(&r, MONITOR_DEFAULTTONEAREST);
            UINT dx, dy;
            if (getDpi(mon, 0 /* MDT_EFFECTIVE_DPI */, &dx, &dy) == 0 /* S_OK */)
            {
                dpiX = cast(float) dx;
                dpiY = cast(float) dy;
            }
        }
        rawDpiX_[i] = dpiX;
        rawDpiY_[i] = dpiY;
        fl.core.screenScale(cast(int) i, dpiX / 96.0f);
    }

    // baseScale() -- the Ctrl-'0' reset target and the indicator's "100%"
    // reference -- is a genuine per-screen value on Windows, matching
    // FLTK's own real `Fl_WinAPI_Screen_Driver::base_scale(int n) {
    // return float(dpi[n][0] / 96.); }` override. Each screen simply uses
    // its own `rawDpiX_[i]` -- already the true per-monitor DPI the loop
    // above just queried.
    //
    // Matches `fl.platform_x11.useStartupScaleFactor()`'s own call to
    // `fl.core.seedBaseScale()` right after establishing the native
    // scale: this seeds `fl.core.baseScale()` from the real
    // native DPI here too, rather than relying on
    // `baseScale()`'s own lazy-capture fallback, which grabs whatever
    // `screenScale()` happens to be the first time anything needs it --
    // usually still correct by coincidence (nothing has zoomed yet at
    // that point on a fresh run), but not guaranteed once a persisted
    // absolute scale is loaded before the first zoom key press, the
    // exact failure mode `seedBaseScale()`'s own doc comment documents
    // for the Linux side.
    foreach (i; 0 .. rawDpiX_.length)
        fl.core.seedBaseScale(cast(int) i, rawDpiX_[i] / 96.0f);

    // Seeds the live drawing scale too, not just the per-screen table --
    // `fl.core.currentScale()` otherwise stays at its own hardcoded `1.0`
    // default until the first window's own `make_current()`-equivalent
    // hook runs, which is too late for any measurement or `ImageSurface`
    // built *before* the first window is shown(). The *true* primary
    // monitor's own DPI is the best available guess for "the scale,"
    // absent any specific window yet -- matching `fl.platform_x11.
    // useStartupScaleFactor()`'s identical seed. `(0, 0)`, not
    // `screens_[0]`, for the same reason `seedScaleFromPrimaryMonitor()`'s
    // own real per-monitor loop above doesn't need to (each screen already
    // gets its own correct value there): Windows always places the
    // primary monitor's top-left at virtual origin `(0, 0)`, regardless of
    // `EnumDisplayMonitors()` enumeration order, so this is the one point
    // guaranteed to land on the real primary even when `screens_[0]`
    // itself isn't it.
    float primaryDpiX = 96.0f;
    if (getDpi !is null)
    {
        HMONITOR primaryMon = MonitorFromPoint(POINT(0, 0), MONITOR_DEFAULTTOPRIMARY);
        UINT dx, dy;
        if (getDpi(primaryMon, 0 /* MDT_EFFECTIVE_DPI */, &dx, &dy) == 0 /* S_OK */)
            primaryDpiX = cast(float) dx;
    }
    fl.core.currentScale(primaryDpiX / 96.0f);
}

// ---------------------------------------------------------------------
// Crash diagnostics -- installed once, alongside registerWindowClass()
// (real-world motivation, not speculative): a crash inside a window
// procedure during `DispatchMessage()` can produce *no* output at all --
// not even
// from wndProc()'s own `catch (Throwable)` (see that function's doc
// comment). The Application event
// log (`Get-WinEvent -FilterHashtable @{LogName='Application'; Id=1000}`)
// for the faulting process reports `Exception code: 0xc000041d`
// (STATUS_FATAL_APP_EXIT) in that case. That code is what Windows substitutes when
// an exception -- of *any* kind, including a real hardware fault like an
// access violation, which never becomes a catchable D `Throwable` here
// in the first place -- escapes a window procedure during
// `DispatchMessage()`: USER32's own SEH frame around that call converts
// it into a silent termination, deliberately skipping the normal
// unhandled-exception-filter/WER pipeline to avoid corrupting the
// message loop further. That's *why* there's no dialog, no minidump
// body, nothing -- it's intentional OS behavior, not a project-specific
// mystery, and no `try`/`catch` inside `wndProc()` can ever intercept a
// real hardware fault this way regardless of what it catches.
//
// A `AddVectoredExceptionHandler()` handler runs earlier than any of
// that -- first-chance, before any `__try`/`__except` frame (including
// USER32's) gets to decide anything -- so it's the only reliable place
// left to observe what's actually faulting. `core.sys.windows.
// stacktrace.StackTrace` (druntime's own Windows stack-trace machinery,
// normally used to symbolize a thrown `Throwable`) already does exactly
// the `StackWalk64()`/`dbghelp.dll` symbol-resolution work needed here,
// and it directly accepts an explicit exception `CONTEXT*` -- built for
// this exact use case -- so this reuses it instead of reimplementing
// `StackWalk64()` by hand. Purely observational: always returns
// `EXCEPTION_CONTINUE_SEARCH`, so whatever would have happened without
// this handler still happens, just with a symbolized function/file/line
// stack trace on stderr first.
private bool crashDiagnosticsInstalled_;

private void installCrashDiagnostics()
{
    if (crashDiagnosticsInstalled_) return;
    crashDiagnosticsInstalled_ = true;
    AddVectoredExceptionHandler(1, &crashVectoredHandler);
}

private extern (Windows) LONG crashVectoredHandler(EXCEPTION_POINTERS* ep) nothrow
{
    // Only the categories actually shaped like a fatal native crash --
    // skips routine first-chance exceptions (e.g. anything the D runtime
    // itself raises and recovers from internally) that would otherwise
    // spam stderr on perfectly normal operation, since a vectored
    // handler sees *every* exception, not just genuinely fatal ones.
    switch (ep.ExceptionRecord.ExceptionCode)
    {
    case EXCEPTION_ACCESS_VIOLATION:
    case EXCEPTION_STACK_OVERFLOW:
    case EXCEPTION_ILLEGAL_INSTRUCTION:
    case EXCEPTION_INT_DIVIDE_BY_ZERO:
    case EXCEPTION_ARRAY_BOUNDS_EXCEEDED:
        break;
    default:
        return EXCEPTION_CONTINUE_SEARCH;
    }

    try
    {
        import std.stdio : stderr;
        import core.sys.windows.stacktrace : StackTrace;

        stderr.writefln("fldtk: FATAL exception 0x%08X at address %s",
            cast(uint) ep.ExceptionRecord.ExceptionCode, ep.ExceptionRecord.ExceptionAddress);
        stderr.writeln((new StackTrace(0, ep.ContextRecord)).toString());
        stderr.flush();
    }
    catch (Throwable) {}
    // A genuine EXCEPTION_STACK_OVERFLOW leaves only the one guard-page-
    // sized reserve of extra stack Windows grants a handler after
    // triggering it -- the writefln()/StackTrace() work above may itself
    // re-fault before finishing in that specific case (a second,
    // unrecoverable overflow), which would still leave the top
    // "FATAL exception 0x...STATUS_STACK_OVERFLOW" line above already
    // flushed, still enough on its own to confirm/rule out that specific
    // cause even without a full trace.

    return EXCEPTION_CONTINUE_SEARCH;
}

private void registerWindowClass()
{
    if (classRegistered_) return;
    classRegistered_ = true;

    installCrashDiagnostics();

    WNDCLASSEXW wc;
    wc.cbSize = WNDCLASSEXW.sizeof;
    wc.style = CS_HREDRAW | CS_VREDRAW | CS_OWNDC | CS_DBLCLKS;
    wc.lpfnWndProc = &wndProc;
    wc.hInstance = GetModuleHandleW(null);
    wc.hCursor = LoadCursorW(null, cast(LPCWSTR) 32512 /* IDC_ARROW */);
    wc.hbrBackground = null;
    wc.lpszClassName = wndClassNameW.ptr;
    RegisterClassExW(&wc);
}

/**
 * Ported from `Fl_WinAPI_Window_Driver::fake_X_wm()`
 * (`~/Repositories/fltk/src/Fl_win32.cxx`) -- computes the real
 * decorated-window rectangle (position + border/title-bar sizes) a
 * top-level window with the given `style`/`exStyle` would occupy, given
 * `win`'s own client-area position/size, *before* the real `HWND` exists
 * (FLTK calls this from `makeWindow()`, ahead of `CreateWindowExW()`,
 * for exactly this reason). Returns `0` (no border), `1` (fixed border),
 * or `2` (resizable border, matching FLTK's `ret` return value used
 * by callers to decide `WS_THICKFRAME` eligibility) and fills `bx`/`by`
 * (left/right and top/bottom border width) and `bt` (title-bar height);
 * `X`/`Y` come back holding the *client area's* top-left corner in real
 * device pixels, clamped fully inside the target screen exactly as
 * FLTK clamps it (border's bottom-right, then top-left, then client
 * area's bottom-right, then top-left, in that order).
 *
 * Uses the real, DPI-aware `AdjustWindowRectExForDpi()` when available
 * (dynamically loaded, see `adjustWindowRectExForDpi()` just above --
 * falls back to the plain, system-DPI-only `AdjustWindowRectEx()` if
 * unavailable) rather than FLTK's own genuine per-monitor DPI table
 * this port doesn't have, needing only the single DPI value that
 * actually matters for `win`'s own target screen.
 *
 * **That DPI value is `fl.core.baseScale()`, not `fl.core.screenScale()`
 * -- the real, physical monitor DPI ratio only, deliberately excluding
 * fldtk's own manual Ctrl-+/Ctrl--/Ctrl-0 zoom multiplier `f`
 * (`screenScale() == f * baseScale()`, see `fl.core.
 * rescaleAllWindowsFromScreen()`).** A real window's real, physical-pixel
 * border/title-bar size is governed entirely by the real monitor's real
 * DPI -- an in-app zoom is a purely internal fldtk rendering decision
 * that changes nothing about it. Passing the zoom-inclusive `screenScale()`
 * here instead would ask
 * `AdjustWindowRectExForDpi()` to compute a *fictional* border size that
 * grows with every Ctrl-+ press while the real border Windows actually
 * draws stays fixed, so each `SetWindowPos()` would request an outer size
 * that comes out too large by `2 * (fictional_border - real_border)` --
 * the `WM_SIZE` echo would then report a real client area larger
 * than intended, and since this port's rescale math treats `w()`/`h()`
 * as authoritative rather than re-deriving them from a fixed original,
 * that overshoot would compound on every subsequent zoom step (e.g.
 * `win.h()` drifting 500 -> 502 -> 507 -> 514 across three
 * Ctrl-+ presses), visibly dragging window content toward whichever
 * corner the drift favored. `screenScale()` (the zoom-*inclusive* value)
 * is still exactly right for everything else in this function --
 * `drawingX`/`drawingY`/the client-area `r.right`/`r.bottom` sizing --
 * since fldtk's own rendered client-area content genuinely does grow
 * with `f`, by design; only the OS-chrome-size computation needed the
 * narrower, DPI-only value.
 *
 * `style`/`exStyle` may be passed as `0` for an already-shown window --
 * matching FLTK's own `if (!style) { style = GetWindowLong(hwnd,
 * GWL_STYLE); ... }` fallback -- in which case `liveHwnd` (the window's
 * own, already-real `HWND`) supplies the real, currently-set style flags
 * instead of the caller having to recompute them.
 */
/// `AdjustWindowRectExForDpi()` -- not declared in this druntime
/// version's `core.sys.windows.*` bindings (same gap `ensureDpiAwareness()`'s
/// own doc comment already notes for the Shcore.dll DPI-awareness APIs),
/// dynamically loaded from `User32.dll` (always already loaded, unlike
/// Shcore.dll) the same way. Used by `fakeXWm()` below in place of the
/// plain, DPI-**un**aware `AdjustWindowRectEx()`: that function
/// always computes border/title-bar thickness for the *system* DPI
/// (effectively the primary monitor's), never the actual target
/// monitor's, so on a monitor scaled to 150% every `SetWindowPos()`
/// call would request a too-small outer size for the real (larger) border
/// Windows actually applies there -- the resulting `WM_SIZE` echo
/// would report a client rect a few pixels short of what was asked for,
/// and since this port's resize math bases each new size on whatever
/// `w()`/`h()` *currently* are (never a fixed original), that small
/// per-transition drift would compound across repeated monitor crossings,
/// visibly growing/shrinking the whole window a little more each time.
private alias AdjustWindowRectExForDpiFn = extern (Windows) BOOL function(RECT*, uint, BOOL, uint, uint) nothrow;
private AdjustWindowRectExForDpiFn adjustWindowRectExForDpi_;
private bool adjustWindowRectExForDpiLoaded_;

private AdjustWindowRectExForDpiFn adjustWindowRectExForDpi()
{
    if (!adjustWindowRectExForDpiLoaded_)
    {
        adjustWindowRectExForDpiLoaded_ = true;
        HMODULE user32 = GetModuleHandleA("User32.dll");
        if (user32 !is null)
            adjustWindowRectExForDpi_ =
                cast(AdjustWindowRectExForDpiFn) GetProcAddress(user32, "AdjustWindowRectExForDpi");
    }
    return adjustWindowRectExForDpi_;
}

private int fakeXWm(FlWindow win, out int X, out int Y, out int bt, out int bx, out int by,
    uint style, uint exStyle, HWND liveHwnd = null)
{
    bx = by = bt = 0;
    int ret = 0;
    float s = fl.core.screenScale(win.screenNum());

    if (style == 0 && liveHwnd !is null)
    {
        style = cast(uint) GetWindowLong(liveHwnd, GWL_STYLE);
        exStyle = cast(uint) GetWindowLong(liveHwnd, GWL_EXSTYLE);
    }

    int minw, minh, maxw, maxh;
    win.getSizeRange(&minw, &minh, &maxw, &maxh);

    int drawingX = scaledPos(win.x(), s);
    int drawingY = scaledPos(win.y(), s);
    RECT r;
    r.left = drawingX;
    r.top = drawingY;
    r.right = drawingX + cast(int) scaledDim(win.w(), s);
    r.bottom = drawingY + cast(int) scaledDim(win.h(), s);

    int W, H, xoff, yoff, dx, dy;
    auto adjustForDpi = adjustWindowRectExForDpi();
    // Deliberately `fl.core.baseScale()` here, not the full `s`
    // (`screenScale()`, which is `f * baseScale()` -- see `fl.core.
    // rescaleAllWindowsFromScreen()`): `AdjustWindowRectExForDpi()`'s DPI
    // parameter asks "how big would this window's real, physical,
    // OS-drawn border/title-bar be at this DPI", and the real answer
    // never depends on fldtk's own manual Ctrl-+/Ctrl--/Ctrl-0 zoom
    // multiplier `f`, since an in-app zoom is a purely internal fldtk
    // rendering decision that changes nothing about the real monitor's
    // real DPI or the real, physical-pixel size of Windows' own
    // non-client-area chrome. Passing the full `96*s` would ask Windows
    // to compute a border size that grows with every Ctrl-+ press while
    // the real border Windows actually draws stays fixed, and since this
    // port's rescale math treats `w()`/`h()` as authoritative rather
    // than re-deriving them from a fixed original
    // (`resizeAfterScaleChange()`'s own doc comment flags this general
    // shape of risk), that overshoot would compound across repeated
    // zoom steps. `s` itself is
    // still exactly right for everything else in this function (`drawingX`/
    // `drawingY`/the client-area `r.right`/`r.bottom` sizing): fldtk's
    // own rendered client-area content genuinely does grow with `f`, by
    // design -- only the *OS chrome* size computation needs the narrower
    // DPI-only value.
    float dpiScale = fl.core.baseScale(win.screenNum());
    bool fallback = adjustForDpi !is null
        ? adjustForDpi(&r, style, FALSE, exStyle, cast(uint)(96.0f * dpiScale)) == 0
        : AdjustWindowRectEx(&r, style, FALSE, exStyle) == 0;

    if (!fallback)
    {
        X = r.left;
        Y = r.top;
        W = r.right - r.left;
        H = r.bottom - r.top;
        bx = drawingX - r.left;
        by = r.bottom - (drawingY + cast(int) scaledDim(win.h(), s));
        bt = drawingY - r.top - by;
        xoff = bx;
        yoff = by + bt;
        dx = W - cast(int) scaledDim(win.w(), s);
        dy = H - cast(int) scaledDim(win.h(), s);
        ret = (maxw != minw || maxh != minh) ? 2 : 1;
    }
    else
    {
        if (win.border())
        {
            if (maxw != minw || maxh != minh)
            {
                ret = 2;
                bx = GetSystemMetrics(SM_CXSIZEFRAME);
                by = GetSystemMetrics(SM_CYSIZEFRAME);
            }
            else
            {
                ret = 1;
                bx = GetSystemMetrics(SM_CXFIXEDFRAME);
                by = GetSystemMetrics(SM_CYFIXEDFRAME);
            }
            bt = GetSystemMetrics(SM_CYCAPTION);
        }
        xoff = bx;
        yoff = by + bt;
        dx = 2 * bx;
        dy = 2 * by + bt;
        X = drawingX - xoff;
        Y = drawingY - yoff;
        W = cast(int) scaledDim(win.w(), s) + dx;
        H = cast(int) scaledDim(win.h(), s) + dy;
    }

    int scrX, scrY, scrW, scrH;
    screenXYWHUnscaled(scrX, scrY, scrW, scrH, win.screenNum());

    if (scrX + scrW < X + W) X = scrX + scrW - W;
    if (scrY + scrH < Y + H) Y = scrY + scrH - H;
    if (X < scrX) X = scrX;
    if (Y < scrY) Y = scrY;
    if (scrX + scrW < X + dx + cast(int) scaledDim(win.w(), s))
        X = scrX + scrW - cast(int) scaledDim(win.w(), s) - dx;
    if (scrY + scrH < Y + dy + cast(int) scaledDim(win.h(), s))
        Y = scrY + scrH - cast(int) scaledDim(win.h(), s) - dy;
    if (X + xoff < scrX) X = scrX - xoff;
    if (Y + yoff < scrY) Y = scrY - yoff;

    X += xoff;
    Y += yoff;

    return ret;
}

/**
 * Creates (or, if already shown, raises) `win`'s real on-screen
 * representation -- the direct equivalent of `fl.platform_x11.
 * createWindow()`, called from `fl.window.Window.show()`.
 *
 * Style flags mirror FLTK's own `wintype` switch in `makeWindow()`:
 * `WS_POPUP` for a borderless window (menus/tooltips), `WS_DLGFRAME|
 * WS_CAPTION[|WS_SYSMENU|WS_MINIMIZEBOX]` for a fixed-size bordered
 * window, `WS_THICKFRAME|WS_SYSMENU|WS_MAXIMIZEBOX|WS_CAPTION[|
 * WS_MINIMIZEBOX]` for a resizable one -- the `[...]` pieces are skipped
 * for a `modal()` window, matching FLTK exactly. `fakeXWm()` supplies
 * the real decorated-window rectangle these styles imply, so a bordered
 * window's initial screen position/size accounts for its own title bar
 * and borders instead of the client rectangle being passed straight to
 * `CreateWindowExW()` unadjusted.
 *
 * **Real subwindow support**. Ported from
 * `Fl_WinAPI_Window_Driver::makeWindow()`'s own `if (w->parent())`
 * branch (`Fl_win32.cxx`) -- a subwindow (`win.parent() !is null`) gets
 * a real `WS_CHILD` `HWND`, parented to `win.window()`'s own `HWND` (not
 * the desktop), with none of the top-level-only WM-facing setup below
 * (border styles/`fakeXWm()`/icons/modal/drag-and-drop registration --
 * none of it makes sense for a window with no window manager involved,
 * matching `fl.platform_x11.createWindow()`'s own identical "skip WM
 * negotiation entirely for a subwindow" precedent, which this port's
 * X11 side already implements correctly). `WS_CHILD` coordinates are
 * relative to the parent's own client area in exactly the same sense
 * `win.x()`/`win.y()` already are for a subwindow in this port's own
 * widget-coordinate model, so no extra translation math is needed --
 * matching FLTK's own identical `xp`/`yp` computation for both
 * branches. If `win.window()` doesn't have a real `HWND` yet (its own
 * `show()` hasn't run), this defers -- marks `win` logically visible
 * and returns, matching FLTK's own early return exactly (`if
 * (w->parent() && !Fl_X::flx(w->window()))`) and this port's own X11
 * side: the parent's own later `show()` cascades `Event.show` down
 * (`win.handle(Event.show)` at the end of this function, for every
 * window including subwindows) and creates it then.
 *
 * **`WS_CLIPCHILDREN | WS_CLIPSIBLINGS` on every style branch** --
 * ported from FLTK's own
 * base `style` value (`DWORD style = WS_CLIPCHILDREN | WS_CLIPSIBLINGS;`,
 * before any type-specific bits get OR'd in). Not just a subwindow
 * concern: without `WS_CLIPCHILDREN`, a parent window's own GDI
 * painting isn't clipped around its children's rectangles at all, so a
 * parent redraw can paint straight over a live child subwindow's
 * pixels -- real, visible corruption `WS_CHILD` support alone doesn't
 * fix without this.
 *
 * `WM_GETMINMAXINFO` itself isn't wired up in `wndProc()` yet, so
 * `getSizeRange()`'s min/max (already consulted by `fakeXWm()` to pick
 * the border-vs-thick-frame style) isn't enforced live during an
 * interactive resize drag.
 */
void createWindow(FlWindow win)
{
    ensureGraphicsDriver();
    registerWindowClass();

    bool isSubwindow = win.parent() !is null;
    FlWindow parentWin;
    HWND parentHwnd;
    if (isSubwindow)
    {
        parentWin = win.window();
        parentHwnd = parentWin !is null ? hwndFor(parentWin) : null;
        if (parentHwnd is null)
        {
            win.setVisible();
            return;
        }
    }

    uint exStyle = WS_EX_LEFT | WS_EX_WINDOWEDGE | WS_EX_CONTROLPARENT;
    uint style = WS_CLIPCHILDREN | WS_CLIPSIBLINGS;
    if (isSubwindow)
    {
        style |= WS_CHILD;
    }
    else if (!win.border())
    {
        style |= WS_POPUP;
        // Ported from `makeWindow()`'s own `wintype 0` case (`Fl_win32.cxx`:
        // "No border (used for menus)") -- keeps a borderless top-level
        // (tooltips, popup menus) out of the taskbar/Alt-Tab list. Missing
        // entirely before (found via the user's own report: a tooltip
        // popping up put a taskbar button up showing the tooltip's own
        // text, as if it were a real named window) -- any top-level
        // `HWND` with no `WS_EX_TOOLWINDOW` gets a taskbar button by
        // default regardless of `WS_POPUP`/lack of a caption; nothing
        // about being borderless alone suppresses it.
        exStyle |= WS_EX_TOOLWINDOW;
    }
    else if (win.isResizable())
    {
        style |= WS_THICKFRAME | WS_SYSMENU | WS_MAXIMIZEBOX | WS_CAPTION;
        if (!win.modal()) style |= WS_MINIMIZEBOX;
    }
    else
    {
        style |= WS_DLGFRAME | WS_CAPTION;
        if (!win.modal()) style |= WS_SYSMENU | WS_MINIMIZEBOX;
    }

    // Cache which monitor this window is considered to be on, for
    // `fl.window.Window.screenNum()`'s benefit: without it, every window
    // would silently
    // report `screenNum() == 0` forever (the getter's own out-of-range
    // fallback), regardless of which physical monitor it actually
    // launched on, since nothing else on this platform ever assigns
    // `rawScreenNum()` at creation time -- only a *later* `WM_MOVE`/
    // `WM_DPICHANGED` corrects it, and neither fires for a window that's
    // simply created (not yet moved) on a non-primary monitor.
    //
    // Ported from `Fl_win32.cxx`'s own real `makeWindow()` -- its own
    // `nscreen` computation, **not** `fl.platform_x11.createWindow()`'s
    // "fall back to `firstWindowWidget()`'s screen" heuristic: for the
    // *first* window ever created, there is no other shown window yet,
    // so that heuristic would always fall
    // back to hard-coded screen `0` -- `screens_[0]`, whichever monitor
    // happened to enumerate first, not necessarily where the user is
    // actually sitting. A subwindow
    // always inherits its top-level ancestor's screen; an explicit
    // pre-show() `screenNum(int)`/`forcePosition()`'d window uses that
    // explicit choice (or derives one from its own explicit `x()`/`y()`);
    // otherwise, on a real multi-monitor system, a fresh window opens on
    // whichever screen the *mouse cursor* is currently on, positioned
    // near it (clamped to stay fully on that screen) -- matching
    // FLTK exactly, and matching the real, already-established
    // reasoning that "near the mouse" is a better guess for "where the
    // user is looking" than any enumeration-order-dependent default.
    if (isSubwindow)
        win.rawScreenNum(parentWin.topWindow().screenNum());
    else if (win.forcePosition())
    {
        int explicitScreen = win.rawScreenNum();
        win.rawScreenNum(explicitScreen >= 0
            ? explicitScreen : fl.core.screenNum(win.x(), win.y()));
    }
    else if (fl.core.screenCount() > 1)
    {
        int mx, my;
        int mscreen = fl.core.getMouse(mx, my);
        win.rawScreenNum(mscreen);
        int sx, sy, sw, sh;
        fl.core.screenXYWH(sx, sy, sw, sh, mscreen);
        if (mx + win.w() >= sx + sw) mx = sx + sw - win.w();
        if (my + win.h() >= sy + sh) my = sy + sh - win.h();
        win.position(mx, my);
    }
    else
        win.rawScreenNum(0);

    // Real device-pixel client geometry, matching `make_xid()`'s own
    // `rint(X*s), rint(Y*s), W*s, H*s` (`fl.platform_x11.createWindow()`'s
    // identical `scaledPos()`/`scaledDim()` treatment) -- `win.x()`/`y()`/
    // `w()`/`h()` themselves stay FLTK units throughout, only scaled here
    // and in `fakeXWm()`, at the points a window's geometry actually
    // becomes a real Win32 request. For a subwindow, this is already
    // exactly what `WS_CHILD` needs (parent-relative), so the whole
    // `fakeXWm()`/border-compensation/`forcePosition()` dance below is
    // skipped entirely, matching FLTK's own top-level-only scope for
    // all of it.
    float s = fl.core.screenScale(win.screenNum());
    int devX = scaledPos(win.x(), s);
    int devY = scaledPos(win.y(), s);
    int devW = cast(int) scaledDim(win.w(), s);
    int devH = cast(int) scaledDim(win.h(), s);

    if (!isSubwindow && win.border())
    {
        int xwm, ywm, bt, bx, by;
        fakeXWm(win, xwm, ywm, bt, bx, by, style, exStyle);
        devW += 2 * bx;
        devH += 2 * by + bt;
        if (win.forcePosition())
        {
            devX = xwm - bx;
            devY = ywm - by - bt;
        }
    }

    // A top-level window built without an explicit position (e.g. `new
    // Window(w, h)`, matching FLTK's own two-argument constructor)
    // never sets `forcePosition()`, and `win.x()`/`win.y()` stay at their
    // constructor default of `(0, 0)` (`fl.window.Window`'s own `this(w,
    // h, label)` overload) -- forwarding that literal `(0, 0)` straight
    // into `CreateWindowExW()` above would always place the window at
    // device pixel `(0, 0)`, always the *primary* monitor's top-left
    // corner by Windows' own virtual-desktop convention, regardless of
    // which monitor the app was actually launched from. Confirmed as a
    // real, live, reported bug: every non-explicitly-positioned window
    // opened in the same corner of the same monitor no matter what.
    // FLTK's real `Fl_WinAPI_Window_Driver::makeWindow()` instead
    // passes `CW_USEDEFAULT` for X/Y in exactly this case, letting
    // Windows' own placement heuristic (cascading relative to the
    // foreground window, honoring whichever monitor that's on) choose --
    // ported here the same way, matching Microsoft's own
    // `CreateWindowExW()` documentation of `CW_USEDEFAULT`.
    if (!isSubwindow && !win.forcePosition())
    {
        devX = CW_USEDEFAULT;
        devY = CW_USEDEFAULT;
    }

    // Deliberately does NOT pass `style | WS_VISIBLE`
    // here. Checked directly against `Fl_win32.cxx`'s own `makeWindow()`
    // (`CreateWindowExW()` call, ~line 2427) -- FLTK's `style` never
    // has `WS_VISIBLE` added anywhere in that function, for *any* window
    // kind (top-level or child), full stop; the window is always created
    // invisible and only made visible afterward by the explicit
    // `ShowWindow()` call below (FLTK's own comment right above its
    // equivalent call: "Needs to be done before ShowWindow() to get the
    // correct behavior when we get WM_SETFOCUS"). Creating the window
    // with `WS_VISIBLE` already set instead would make Windows show (and, for
    // an ordinary overlapped/popup top-level window, activate) it as
    // part of `CreateWindowExW()` itself -- *before* the later
    // `ShowWindow(hwnd, showNoActivate ? SW_SHOWNOACTIVATE : ...)` call a
    // few lines down ever runs, so that call's own activation choice
    // would arrive too late to matter: the window would already be shown/activated
    // under the *other* branch's semantics the instant it was created.
    // For `showNoActivate` windows (the scale popup, tooltips, popup
    // menus) this would mean a spurious activate-then-deactivate around
    // creation regardless of the `SW_SHOWNOACTIVATE` flag intended to
    // prevent exactly that -- plausibly firing a real `WM_KILLFOCUS` on
    // whatever window *was* focused, which this port's own `case
    // WM_KILLFOCUS: fl.core.fixFocus(null);` handler responds to by
    // clearing `fl.core.focus()` to `null`, silently breaking every
    // focus-requiring feature (e.g. `fl.core.scaleHandler()`,
    // whose whole Ctrl-+/Ctrl--/Ctrl-0 feature no-ops whenever `focus()`
    // is `null`) until some later, unrelated focus change happens to
    // restore it. Matching FLTK exactly avoids this: create without
    // `WS_VISIBLE`, so the unconditional `ShowWindow()` call below is the
    // only thing that ever makes the window visible, on every code path.
    HWND hwnd = CreateWindowExW(exStyle, wndClassNameW.ptr, win.label().toUTF16z,
        style, devX, devY, devW, devH, parentHwnd, null, GetModuleHandleW(null), null);
    if (hwnd is null) return;

    auto rec = new WindowRecord;
    rec.hwnd = hwnd;
    rec.widget = win;
    // Real, sane default rather than HCURSOR.init (null) -- WM_SETCURSOR
    // below always re-asserts whatever this holds, and a null HCURSOR
    // renders as no cursor at all (invisible) rather than falling back
    // to anything, for every window that never explicitly calls its own
    // .cursor(). Matches the window class's own hCursor default
    // (registerWindowClass()) so both paths agree.
    rec.cursor = LoadCursorW(null, cast(LPCWSTR) 32512 /* IDC_ARROW */);
    rec.next = first_;
    first_ = rec;

    // Reads back the real, already-resolved window position right here
    // rather than depending on the window's very first `WM_MOVE`, which
    // this window's own handler can never see: `CreateWindowExW()` above dispatches `WM_CREATE`/
    // `WM_MOVE`/`WM_SIZE`/etc. to `wndProc()` *synchronously*, before
    // it even returns -- but `rec` (just above) isn't linked into
    // `first_` until after it returns, so `wndProc()`'s own `find(hWnd)
    // is null` early return (see that function's own top) drops every
    // one of those very-first messages, `WM_MOVE` included.
    // For a `CW_USEDEFAULT`-positioned window (`!win.forcePosition()`
    // just above) that `WM_MOVE` would otherwise be the *only* thing that
    // tells this port where Windows actually placed the window --
    // without reading it back here, `win.x()`/`win.y()` would stay at
    // their pre-show default
    // (typically `(0, 0)`) until the user manually moves the window and
    // a *later*, real `WM_MOVE` (now correctly routed, `rec` already
    // registered by then) updates them for the first time, and every popup
    // menu/pulldown computed from `window().x()`/`.y()`
    // (`fl.menu_popup`/`fl.menu_bar`) would inherit that stale value.
    // Reading the
    // real, already-resolved position straight back right here, rather
    // than depending on a `WM_MOVE` that this window's own handler can
    // never actually see, avoids that. `GetClientRect()`+`ClientToScreen()` on the
    // client origin -- not `GetWindowRect()` -- to match `WM_MOVE`'s own
    // lParam convention exactly (MSDN: "the x,y coordinates of the
    // upper-left corner of the *client area*"), which is what `win.x()`/
    // `win.y()` mean throughout this port; `GetWindowRect()` would give
    // the outer, decorated frame's position instead, off by the title
    // bar/border for any bordered window. `resizeBoundsOnly()` (not
    // `resize()`) matches `win.markShown()` not having run yet just
    // below -- pure bookkeeping, no redundant `SetWindowPos()` call back
    // into Windows for a position it already has.
    if (!isSubwindow && !win.forcePosition())
    {
        POINT origin;
        if (ClientToScreen(hwnd, &origin))
        {
            import std.math : round;

            // Reuses `s` (`screenScale(win.screenNum())`), already
            // computed above for the CreateWindowExW() geometry itself.
            int realX = cast(int) round(origin.x / s);
            int realY = cast(int) round(origin.y / s);
            win.resizeBoundsOnly(realX, realY, win.w(), win.h());
        }
    }

    // _NET_WM_ICON's Windows equivalent -- ported from `Fl_x.cxx`'s
    // `make_xid()`, which calls `set_icons()` at this same point
    // See `setIcons()`'s own doc
    // comment for the mechanism. Top-level only -- a subwindow has no
    // taskbar/Alt-Tab presence of its own to set an icon for, matching
    // FLTK's own placement inside the `!w->parent()` branch.
    if (!isSubwindow) setIcons(win);

    // Ported from `Fl_win32.cxx`'s own `show_iconic()`/`show_next_
    // window_iconic` handling: a window whose `iconize()` was called
    // before it was ever `shown()` (`fl.window.Window.iconize()`'s own
    // `!shown()` branch) is created genuinely already-minimized, no
    // visible-then-iconified flash, matching `fl.platform_x11`'s
    // identical `WM_HINTS`/`IconicState` handling.
    bool bornIconic = FlWindow.showNextWindowIconic();
    if (bornIconic) FlWindow.showNextWindowIconic(false);

    win.markShown(hwnd);
    // Ported from `makeWindow()`'s own `ShowWindow(fl_xid(this), (Fl::
    // grab() || (styleEx & WS_EX_TOOLWINDOW)) ? SW_SHOWNOACTIVATE :
    // SW_SHOWNORMAL)`. Deliberately not unconditionally `SW_SHOWNORMAL`
    // regardless of `exStyle`: every borderless top-level window
    // (tooltips, popup menus -- anything `WS_EX_TOOLWINDOW`-flagged just
    // above) would otherwise activate and steal focus on show, exactly the behavior
    // `SW_SHOWNOACTIVATE` exists to suppress. `Fl_TooltipBox`/menu
    // windows are ordinary `Fl_Menu_Window`s in FLTK too, on every
    // platform including Windows.
    // `win.output()` is a
    // deliberate deviation from FLTK, not a faithful port --
    // `Fl_win32.cxx`'s own `makeWindow()` has no
    // `output()` check anywhere, and a window like `fl.core.
    // transientScaleDisplay()`'s Ctrl-+/Ctrl--/Ctrl-0 transient
    // scale-percentage popup keeps its default
    // *bordered* state on both this port and real FLTK (neither
    // ever calls `border(false)` on it), so it never qualifies for the
    // `WS_EX_TOOLWINDOW` branch either way -- real FLTK
    // most likely has this identical gap (a genuine
    // `FLTK_ISSUES.md` candidate, not filed with FLTK without
    // review per this project's own process). An `output()` widget is
    // by definition non-interactive/display-only (`Widget.output()`'s
    // own doc comment), so "never steals activation" is the correct
    // behavior for it regardless of border state, and worth having
    // even where FLTK itself doesn't yet.
    bool showNoActivate = fl.core.grab() !is null || (exStyle & WS_EX_TOOLWINDOW) != 0 || win.output();
    ShowWindow(hwnd, bornIconic ? SW_SHOWMINNOACTIVE
        : (showNoActivate ? SW_SHOWNOACTIVATE : SW_SHOWNORMAL));
    UpdateWindow(hwnd);

    // A brand-new top-level window's real Win32 keyboard focus does end
    // up on this HWND -- WM_KEYDOWN/WM_CHAR arrive and are handled
    // completely normally from the very first keystroke, proving the
    // OS-level focus transfer genuinely happened -- but the WM_SETFOCUS
    // *notification* announcing that transfer doesn't reliably reach this
    // port's
    // own `case WM_SETFOCUS: fl.core.fixFocus(win);` handler, which would
    // leave
    // `fl.core.focus()` stuck at `null` until some *later*, unrelated
    // focus change (e.g. Alt-Tabbing away and back) finally sends a
    // WM_SETFOCUS this WndProc does catch -- affecting every caller that
    // requires a
    // focused widget (e.g. `fl.core.scaleHandler()`,
    // which silently no-ops the entire Ctrl-+/Ctrl--/Ctrl-0 feature
    // whenever `focus()` is null) for the window's entire
    // lifetime until that later event. Rather than chase the exact
    // reason the initial WM_SETFOCUS can go missing (plausibly the same
    // "dispatched synchronously before this window's own bookkeeping
    // catches it" class of race already fixed for WM_MOVE
    // just above in this same function), this establishes
    // `fl.core.focus()` directly here instead of depending on that
    // message arriving at all -- `fixFocus()` is exactly the function
    // WM_SETFOCUS itself would have called, so this produces the
    // identical end state a working WM_SETFOCUS would have, deterministically.
    // Skipped for a subwindow (never independently focus-worthy -- its
    // ancestor top-level's own WM_SETFOCUS, real or substituted, covers
    // it) and for `showNoActivate`/iconic windows (a tooltip or the
    // scale popup taking keyboard focus the moment it appears would be
    // exactly the bug fixed elsewhere in this same session).
    if (!isSubwindow && !showNoActivate && !bornIconic)
        fl.core.fixFocus(win);

    // Real OLE drag-and-drop target registration -- ported from
    // `make_xid()`'s own `RegisterDragDrop((HWND)x->xid, flIDropTarget);`
    // Top-level only -- a subwindow is
    // never itself a drop target independent of its top-level ancestor
    // in this port's own DND scope, and registering the same global
    // `dropTarget_` on every subwindow too would be pure overhead with
    // no real second target to distinguish.
    if (!isSubwindow) RegisterDragDrop(hwnd, dropTarget_);

    // Real `fl.core.modal()` tracking. Ported from `fl.platform_x11.
    // createWindow()`'s own identical `if (win.modal()) {Fl::modal_ =
    // win; fl_fix_focus();}` -- see `destroyWindow()`'s own doc comment
    // for the other half (reassigning/clearing it when
    // the modal window closes again). Other
    // code (`fl.core.handle()`'s own push/move/drag/release/shortcut/
    // mouseWheel/close filtering, per that function's own doc comment)
    // assumes `fl.core.modal()` is kept correctly in sync with which window is
    // really the active modal one.
    if (win.modal())
    {
        fl.core.modal(win);
        fl.core.fixFocus(win);
    }

    // Setup clipboard monitor target if there are registered handlers
    // and no window is targeted yet -- ported from `Fl_win32.cxx`'s own
    // identical `makeWindow()` tail. Matches FLTK in applying to
    // every created window, subwindows included.
    if (!fl.core.clipboardNotifyEmpty() && clipboardWnd_ is null)
        clipboardNotifyTarget(hwnd);

    win.handle(Event.show);
}

/// The direct equivalent of `fl.platform_x11.raiseWindow()` -- called
/// from `Window.show()` when the window is already shown, and from
/// `Window.handle(Event.show)` to remap a subwindow `unmapWindow()`
/// previously hid in place.
///
/// Deliberately not `ShowWindow(hwnd,
/// SW_SHOWNORMAL); SetForegroundWindow(hwnd);`, which is not what real
/// FLTK does. `Fl_WinAPI_Window_Driver::show()`'s own
/// "already shown" branch (`Fl_win32.cxx:2864-2876`) is `if
/// (IsIconic(i->xid)) OpenIcon(i->xid); if (!fl_capture)
/// BringWindowToTop(i->xid);` -- `BringWindowToTop()` raises the
/// window in Z-order *without* giving it keyboard focus/activation,
/// deliberately: FLTK's own comment reads "we would lose the
/// capture if we activated the window." `SetForegroundWindow()`
/// appears nowhere in real FLTK `Fl_win32.cxx` at all. This matters:
/// `fl.tooltip.d`'s `TooltipBox` is a singleton reused across
/// every tooltip display (`if (window_ is null) window_ = new
/// TooltipBox;`), so only its *first* ever show hits `createWindow()`
/// (already correctly non-activating for a borderless/`WS_EX_TOOLWINDOW`
/// window) -- every subsequent tooltip re-show hits
/// *this* function instead, so an unconditional
/// `SetForegroundWindow()` here would steal focus from the real application
/// window every single time. `fl.core.grab()` mirrors FLTK's own `fl_capture` check exactly
/// (both name "is there an active pointer/keyboard grab in progress,
/// e.g. a popup menu" -- raising a window over that would steal the
/// grab).
void raiseWindow(FlWindow win)
{
    if (auto hwnd = hwndFor(win))
    {
        if (IsIconic(hwnd)) OpenIcon(hwnd);
        if (fl.core.grab() is null) BringWindowToTop(hwnd);
    }
}

/// Hides a subwindow in place without destroying its `HWND` or its
/// own window-record bookkeeping -- the Windows equivalent of
/// `fl.platform_x11.unmapWindow()`, called from `Window.handle(
/// Event.hide)` for the common "an ancestor `FlGroup` (not a
/// `Window`) was hidden" case.
void unmapWindow(FlWindow win)
{
    if (auto hwnd = hwndFor(win))
        ShowWindow(hwnd, SW_HIDE);
}

/// Rounds `v * s` to the nearest integer -- for a window's on-screen
/// *position* (which can legitimately be negative). Matches
/// `fl.platform_x11.scaledPos()` exactly (same FLTK `rint(X*s)`
/// source).
private int scaledPos(int v, float s)
{
    if (s == 1) return v;
    import std.math : lround;

    return cast(int) lround(v * cast(double) s);
}

/// Truncates `v * s`, clamped to a minimum of `1` -- for a window's
/// on-screen *dimension*. Matches `fl.platform_x11.scaledDim()` exactly.
private uint scaledDim(int v, float s)
{
    if (s == 1) return v > 0 ? cast(uint) v : 1;
    int r = cast(int)(v * s);
    return r > 0 ? cast(uint) r : 1;
}

private HWND hwndFor(FlWindow win)
{
    for (auto rec = first_; rec !is null; rec = rec.next)
        if (rec.widget is win) return rec.hwnd;
    return null;
}

private WindowRecord* recordFor(FlWindow win)
{
    for (auto rec = first_; rec !is null; rec = rec.next)
        if (rec.widget is win) return rec;
    return null;
}

/// Frees `rec`'s off-screen double-buffer, if it has one -- called both
/// when `WM_PAINT` detects a size mismatch (about to reallocate at the
/// new size) and from `destroyWindow()`. Restores the memory DC's
/// original 1x1 stock bitmap before deleting `offscreenBmp` (a bitmap
/// still selected into a DC is not safe to delete), matching the
/// already-established "deselect before delete" convention `fl.
/// gdi_graphics_driver`'s own `applyLineStyleUnscaled()` doc comment
/// documents the real bug behind.
private void freeOffscreen(WindowRecord* rec)
{
    if (rec.offscreenDc !is null)
    {
        if (rec.offscreenOrigBmp !is null)
            SelectObject(rec.offscreenDc, rec.offscreenOrigBmp);
        DeleteDC(rec.offscreenDc);
        rec.offscreenDc = null;
    }
    if (rec.offscreenBmp !is null)
    {
        DeleteObject(rec.offscreenBmp);
        rec.offscreenBmp = null;
    }
    rec.offscreenOrigBmp = null;
    rec.offscreenW = 0;
    rec.offscreenH = 0;
}

/// (Re)allocates `rec`'s off-screen double-buffer at `w`x`h` device
/// pixels, compatible with `compatDc` (the real on-screen `HDC`
/// `BeginPaint()` just returned -- `CreateCompatibleDC()`/
/// `CreateCompatibleBitmap()` both need a reference DC to match pixel
/// format/color depth against). Always frees whatever was there first
/// (a no-op if nothing was allocated yet).
private void allocOffscreen(WindowRecord* rec, HDC compatDc, int w, int h)
{
    freeOffscreen(rec);
    rec.offscreenDc = CreateCompatibleDC(compatDc);
    if (rec.offscreenDc is null) return;
    rec.offscreenBmp = CreateCompatibleBitmap(compatDc, w, h);
    if (rec.offscreenBmp is null)
    {
        DeleteDC(rec.offscreenDc);
        rec.offscreenDc = null;
        return;
    }
    rec.offscreenOrigBmp = cast(HBITMAP) SelectObject(rec.offscreenDc, rec.offscreenBmp);
    rec.offscreenW = w;
    rec.offscreenH = h;
}

// ---------------------------------------------------------------------
// Application-initiated window move/resize -- ported from
// `Fl_WinAPI_Window_Driver::resize()` (`Fl_win32.cxx:2114-2178`).
// ---------------------------------------------------------------------

/**
 * The real `SetWindowPos()` call -- called from `fl.window.Window.
 * resize()` once it's determined a move/resize isn't an echo of a
 * WM-driven `WM_SIZE`/`WM_MOVE` (matching `fl.platform_x11.
 * resizeWindow()`'s own narrow scope: this port's generic `Group.
 * resize()`/redraw/`resizeBugFix_` handling already lives in
 * `fl.window.d` itself, platform-independent -- this function is only
 * the platform-specific "make it really so" call, same division of
 * labor FLTK's own `XMoveResizeWindow()`/`XResizeWindow()`/
 * `XMoveWindow()` calls have on the X11 side).
 *
 * `fake_X_wm()`'s real border/title-bar negotiation is wired in now
 * (matching FLTK's own `resize()` exactly): `scaledX`/`scaledY`/
 * `scaledW`/`scaledH` are compensated by the real `bx`/`by`/`bt` a
 * bordered window's decorations occupy, not left as plain unadjusted
 * client-rect values.
 *
 * The rest of FLTK's `resize()` -- the maximized-window guard and the
 * rescale-triggered `delayed_fullscreen`/`delayed_maximize` checks --
 * lives in `fl.window.Window.resize()`, which calls
 * `isPlacementMaximized()` below for the guard.
 */
package(fl) void resizeWindow(FlWindow win, int x, int y, int w, int h, bool isMove, bool isResize,
    int exactDevX = int.min, int exactDevY = int.min)
{
    auto hwnd = hwndFor(win);
    if (hwnd is null) return;

    uint flags = SWP_NOSENDCHANGING | SWP_NOZORDER | SWP_NOACTIVATE | SWP_NOOWNERZORDER;
    if (!isMove) flags |= SWP_NOMOVE;
    if (!isResize) flags |= SWP_NOSIZE;
    if (!win.border()) flags |= SWP_NOACTIVATE;

    float s = fl.core.screenScale(win.screenNum());
    import std.math : lround;

    // `exactDevX`/`exactDevY` (set only by `Window.resizeAfterScaleChange()`'s
    // own non-clamped case, via `Window.resize()`'s `exactDeviceTarget_`
    // check) are the window's already-*confirmed* device-pixel position
    // (from `WM_MOVE`'s own `devicePosX_`/`devicePosY_` tracking) --
    // using them instead of recomputing `lround(x * s)` here is what
    // keeps a rescaled window's on-screen position byte-identical rather
    // than drifting by a pixel on a rounding-boundary value, exactly
    // matching `fl.platform_x11.resizeWindow()`'s identical parameter
    // pair.
    int scaledX = exactDevX != int.min ? exactDevX : cast(int) lround(x * cast(double) s);
    int scaledY = exactDevY != int.min ? exactDevY : cast(int) lround(y * cast(double) s);
    int scaledW = cast(int)(w * s);
    int scaledH = cast(int)(h * s);

    int dummyX, dummyY, bt, bx, by;
    if (fakeXWm(win, dummyX, dummyY, bt, bx, by, 0, 0, hwnd))
    {
        scaledX -= bx;
        scaledY -= by + bt;
        scaledW += 2 * bx;
        scaledH += 2 * by + bt;
    }

    if (scaledW <= 0) scaledW = 1;
    if (scaledH <= 0) scaledH = 1;

    SetWindowPos(hwnd, null, scaledX, scaledY, scaledW, scaledH, flags);
}

/// Whether `win` is shown maximized by the system (`SW_SHOWMAXIMIZED`).
/// From `Fl_WinAPI_Window_Driver::resize()`'s "don't obey resize from
/// program when window is maximized" check.
package(fl) bool isPlacementMaximized(FlWindow win)
{
    auto hwnd = hwndFor(win);
    if (hwnd is null) return false;
    WINDOWPLACEMENT wplace;
    wplace.length = WINDOWPLACEMENT.sizeof;
    return GetWindowPlacement(hwnd, &wplace) && wplace.showCmd == SW_SHOWMAXIMIZED;
}

// ---------------------------------------------------------------------
// Cursors -- ported from `Fl_win32.cxx`'s `Fl_WinAPI_Window_Driver::
// set_cursor()` (both overloads) and the file-scope `image_to_icon()`.
// ---------------------------------------------------------------------

/**
 * Sets `win`'s cursor to one of the stock shapes -- ported from
 * `Fl_WinAPI_Window_Driver::set_cursor(Fl_Cursor)` (`Fl_win32.cxx:2760-
 * 2831`), including its exact N/S->NS, NE/SW->NESW, E/W->WE, SE/NW->NWSE
 * aliasing onto the four diagonal/straight resize cursors (FLTK's
 * own comment flags this as a `FIXME`, not a mistake to "improve" here).
 *
 * **`Cursor.default_` deliberately deviates from FLTK's own switch,
 * which has no case for it at all and falls to `default: return 0;`.**
 * That's not actually a "does nothing, harmlessly" gap on this port:
 * a cursor
 * changed by `Fl_Text_Editor.H`/`Fl_Input_.cxx`/etc's own mouse-leave
 * handling, all of which call exactly `window().cursor(Cursor.default_)`,
 * would silently stay stuck at whatever shape was last set: `setCursor()`
 * returning `false` here leaves `rec.cursor` completely untouched, and
 * `WM_SETCURSOR` below unconditionally re-applies that same stale
 * `rec.cursor` on every subsequent mouse move, so the wrong cursor
 * never recovers on its own). Checked against the real FLTK
 * mechanism before deviating, not guessed: `Fl_Window::cursor(Fl_Cursor)`
 * (`fl_cursor.cxx`, the platform-independent caller) is *supposed* to
 * remap `FL_CURSOR_DEFAULT` through a `cursor_default` member before
 * ever reaching a driver, but that member itself starts as
 * `FL_CURSOR_DEFAULT` (0) and nothing but `Fl_Window::default_cursor()`
 * -- never called anywhere in the non-Wayland tree -- ever changes it,
 * so `FL_CURSOR_DEFAULT` really does reach `set_cursor()` raw on every
 * platform including X11's own `Fl_X11_Window_Driver::set_cursor()`
 * (`Fl_x.cxx`), which has the identical no-case-for-it gap. A real,
 * shared FLTK quirk, not a Windows-only miss -- but this port's own
 * `version (linux)` X11 cursor path was never ported this deeply to
 * begin with (no per-widget mouse-leave cursor reset exists on that
 * side yet), so nothing currently exercises the identical gap there the
 * way the Windows text/input widgets already do. Mapping `default_` to
 * the plain arrow here is the obviously-intended behavior (matching
 * what a correctly-seeded `cursor_default` would have produced anyway),
 * not a reinterpretation.
 */
bool setCursor(FlWindow win, CursorShape c)
{
    auto rec = recordFor(win);
    if (rec is null) return false;

    HCURSOR newCursor;
    if (c == CursorShape.none)
    {
        newCursor = null;
    }
    else
    {
        LPCWSTR n;
        switch (c)
        {
        case CursorShape.default_:
        case CursorShape.arrow: n = cast(LPCWSTR) IDC_ARROW; break;
        case CursorShape.cross: n = cast(LPCWSTR) IDC_CROSS; break;
        case CursorShape.wait: n = cast(LPCWSTR) IDC_WAIT; break;
        case CursorShape.insert: n = cast(LPCWSTR) IDC_IBEAM; break;
        case CursorShape.hand: n = cast(LPCWSTR) IDC_HAND; break;
        case CursorShape.help: n = cast(LPCWSTR) IDC_HELP; break;
        case CursorShape.move: n = cast(LPCWSTR) IDC_SIZEALL; break;
        case CursorShape.n:
        case CursorShape.s:
        case CursorShape.ns:
            n = cast(LPCWSTR) IDC_SIZENS;
            break;
        case CursorShape.ne:
        case CursorShape.sw:
        case CursorShape.nesw:
            n = cast(LPCWSTR) IDC_SIZENESW;
            break;
        case CursorShape.e:
        case CursorShape.w:
        case CursorShape.we:
            n = cast(LPCWSTR) IDC_SIZEWE;
            break;
        case CursorShape.se:
        case CursorShape.nw:
        case CursorShape.nwse:
            n = cast(LPCWSTR) IDC_SIZENWSE;
            break;
        default:
            return false;
        }
        newCursor = LoadCursorW(null, n);
        if (newCursor is null) return false;
    }

    if (rec.cursor !is null && rec.customCursor) DestroyIcon(rec.cursor);
    rec.cursor = newCursor;
    rec.customCursor = false;
    SetCursor(rec.cursor);
    return true;
}

/**
 * Sets `win`'s cursor to a custom RGBA image -- ported from
 * `Fl_WinAPI_Window_Driver::set_cursor(const Fl_RGB_Image*, int, int)`.
 */
bool setCursorImage(FlWindow win, const(RGBImage) image, int hotx, int hoty)
{
    auto rec = recordFor(win);
    if (rec is null) return false;

    HCURSOR newCursor = cast(HCURSOR) imageToIcon(image, false, hotx, hoty);
    if (newCursor is null) return false;

    if (rec.cursor !is null && rec.customCursor) DestroyIcon(rec.cursor);
    rec.cursor = newCursor;
    rec.customCursor = true;
    SetCursor(rec.cursor);
    return true;
}

/**
 * Applies a 1-bit-per-pixel mask (`bits`, row-major, LSB first, `(w+7)/8`
 * bytes per row -- the same packing `fl.bitmap.Bitmap.array` uses, and
 * the same format `fl.platform_x11.applyWindowShapeMask()` takes) as
 * `win`'s window shape. Backs `fl.window.Window.shape()`'s Windows
 * branch: `shape()`'s own unconditional `border(false)` runs
 * on every platform, and this applies the real mask on top of it so the
 * window is actually cut down to shape, e.g. `shapedwindow.d`'s own
 * non-rectangular window.
 *
 * Windows has no single call matching `XShapeCombineMask()`'s "hand it a
 * bitmap" simplicity -- a window region (`HRGN`) is built from
 * rectangles, not a bitmap, so this walks the mask one scanline at a
 * time, run-length-encoding each row's contiguous set-bit spans into
 * `CreateRectRgn()` calls unioned together via `CombineRgn(..., RGN_OR)`
 * (the standard Win32 "bitmap to region" technique -- FLTK's own
 * Windows driver, `Fl_WinAPI_Window_Driver`, has no `shape()` override
 * at all and inherits `Fl_Window_Driver::shape()`'s plain "not
 * supported on this platform" no-op, so there's no real FLTK
 * function to port verbatim here; this is a from-scratch, standard-
 * technique implementation instead). `SetWindowRgn()` takes ownership of
 * the region handle on success, matching `imageToIcon()`'s own
 * `CreateIconIndirect()`-owns-nothing-further precedent for "the OS now
 * owns this handle" resource handoffs; `DeleteObject()`s it back out on
 * failure to avoid a leak. Region coordinates are relative to the
 * window's own outer rectangle -- correct here since `shape()` also
 * calls `border(false)`, so a shaped window's outer rectangle already
 * equals its client area (no title bar/frame to offset by).
 */
package(fl) void applyWindowShapeMask(FlWindow win, int w, int h, const(ubyte)[] bits)
{
    auto hwnd = hwndFor(win);
    if (hwnd is null) return;
    if (w <= 0 || h <= 0 || bits.length == 0) return;

    int rowBytes = (w + 7) / 8;
    if (bits.length < cast(size_t) rowBytes * h) return;

    HRGN region = CreateRectRgn(0, 0, 0, 0);
    foreach (y; 0 .. h)
    {
        int x = 0;
        while (x < w)
        {
            while (x < w && (bits[y * rowBytes + x / 8] & (1 << (x % 8))) == 0) x++;
            if (x >= w) break;
            int runStart = x;
            while (x < w && (bits[y * rowBytes + x / 8] & (1 << (x % 8))) != 0) x++;

            HRGN rowRgn = CreateRectRgn(runStart, y, x, y + 1);
            CombineRgn(region, region, rowRgn, RGN_OR);
            DeleteObject(rowRgn);
        }
    }

    if (SetWindowRgn(hwnd, region, TRUE) == 0) DeleteObject(region);
}

/**
 * Ported from the file-scope `image_to_icon()` (`Fl_win32.cxx:2537-
 * 2618`): a real 32bpp ARGB `CreateDIBSection()` bitmap (manual per-
 * pixel channel packing matching the 1/2/3/4-channel source-depth
 * switch exactly -- FLTK's own `switch` has no `default:` case
 * either, since `RGBImage.d()` is always 1-4 by its own contract), a
 * same-size 1bpp mask bitmap (unused for color but required by
 * `CreateIconIndirect()` regardless), and the real `ICONINFO`/
 * `CreateIconIndirect()` call. `isIcon` selects a true icon (used by a
 * future window-icon phase) vs. a cursor (`hotx`/`hoty` only validated,
 * and only meaningful, for the cursor case, matching FLTK's own
 * `if (!is_icon) { validate hotx/hoty }` guard).
 */
private HICON imageToIcon(const(RGBImage) image, bool isIcon, int hotx, int hoty)
{
    if (!isIcon)
    {
        if (hotx < 0 || hotx >= image.dataW()) return null;
        if (hoty < 0 || hoty >= image.dataH()) return null;
    }

    BITMAPV5HEADER bi;
    bi.bV5Size = BITMAPV5HEADER.sizeof;
    bi.bV5Width = image.dataW();
    bi.bV5Height = -image.dataH(); // negative -> top-down DIB
    bi.bV5Planes = 1;
    bi.bV5BitCount = 32;
    bi.bV5Compression = BI_BITFIELDS;
    bi.bV5RedMask = 0x00FF0000;
    bi.bV5GreenMask = 0x0000FF00;
    bi.bV5BlueMask = 0x000000FF;
    bi.bV5AlphaMask = 0xFF000000;

    HDC screenDc = GetDC(null);
    void* bitsPtr;
    HBITMAP bitmap = CreateDIBSection(screenDc, cast(const(BITMAPINFO)*)&bi, DIB_RGB_COLORS, &bitsPtr, null, 0);
    ReleaseDC(null, screenDc);
    if (bitsPtr is null) return null;

    uint* bits = cast(uint*) bitsPtr;
    const(ubyte)[] data = image.array;
    int depth = image.d();
    int stride = image.ld() ? image.ld() : image.dataW() * depth;
    int extraData = stride - image.dataW() * depth;

    size_t i = 0;
    foreach (y; 0 .. image.dataH())
    {
        foreach (x; 0 .. image.dataW())
        {
            uint px;
            switch (depth)
            {
            case 1:
                px = (0xffu << 24) | (cast(uint) data[i] << 16) | (cast(uint) data[i] << 8) | data[i];
                break;
            case 2:
                px = (cast(uint) data[i + 1] << 24) | (cast(uint) data[i] << 16) | (cast(uint) data[i] << 8) | data[i];
                break;
            case 3:
                px = (0xffu << 24) | (cast(uint) data[i] << 16) | (cast(uint) data[i + 1] << 8) | data[i + 2];
                break;
            case 4:
                px = (cast(uint) data[i + 3] << 24) | (cast(uint) data[i] << 16) | (cast(uint) data[i + 1] << 8) | data[i + 2];
                break;
            default:
                px = 0;
                break;
            }
            *bits = px;
            bits++;
            i += depth;
        }
        i += extraData;
    }

    HBITMAP mask = CreateBitmap(image.dataW(), image.dataH(), 1, 1, null);
    if (mask is null)
    {
        DeleteObject(bitmap);
        return null;
    }

    ICONINFO ii;
    ii.fIcon = isIcon ? TRUE : FALSE;
    ii.xHotspot = hotx;
    ii.yHotspot = hoty;
    ii.hbmMask = mask;
    ii.hbmColor = bitmap;

    HICON icon = CreateIconIndirect(&ii);

    DeleteObject(bitmap);
    DeleteObject(mask);

    return icon;
}

/**
 * Destroys `win`'s real on-screen representation -- the direct
 * equivalent of `fl.platform_x11.destroyWindow()`, called from
 * `fl.window.Window.hide()`.
 *
 * **Real subwindow recursion**, matching this
 * port's own X11 side (see the
 * loop just below, straight from `fl.platform_x11.destroyWindow()`'s
 * own identical one). Needed for a real reason, not just symmetry:
 * `DestroyWindow(rec.hwnd)` at the end of this function cascades at
 * the *OS* level, destroying every child `HWND` a subwindow created
 * automatically -- but with no D-level bookkeeping of our own along
 * the way, without this loop every subwindow's own `WindowRecord`
 * would be left dangling in `first_`, pointing at an already-destroyed
 * `HWND`, and its widget would never see `Event.hide` or get marked
 * not-shown. Ported from `Fl_Window_Driver::hide_common()`'s own
 * "recursively remove any subwindows" loop (`src/Fl_Window_Driver.cxx`)
 * -- real FLTK has this same structure on every platform (it's not
 * X11-specific there either). Real `fl.core.modal()` reassignment too
 * (see the re-scan just
 * below, and `createWindow()`'s doc comment for the full mechanism).
 */
void destroyWindow(FlWindow win)
{
    WindowRecord** pp = &first_;
    while (*pp !is null && (*pp).widget !is win)
        pp = &(*pp).next;
    if (*pp is null) return;

    auto rec = *pp;
    *pp = rec.next;

    win.markHidden();

    // See this function's own doc comment -- restarts the scan from the
    // head after each removal (matching FLTK's own `wi = Fl_X::
    // first;` restart, and this port's own X11-side precedent) since
    // destroying a subwindow unlinks its record from `first_` out from
    // under a normal forward iteration.
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

    // The other half of real `fl.core.modal()` tracking (see
    // `createWindow()`'s own doc comment for the full story) -- ported
    // from `fl.platform_x11.destroyWindow()`'s identical re-scan: if the
    // window being destroyed was the active modal one, look for another
    // still-shown modal() window among what's left (`rec` is already
    // unlinked from `first_` above) and reinstate *that* instead of just
    // clearing to null, so a modal dialog that opened another modal
    // dialog on top of it correctly regains exclusivity once the upper
    // one closes.
    if (fl.core.modal() is win)
    {
        FlWindow next;
        for (auto p = first_; p !is null; p = p.next)
            if (p.widget.modal()) { next = p.widget; break; }
        fl.core.modal(next);
    }

    fl.core.throwFocus(win);
    win.handle(Event.hide);

    // Undo RegisterDragDrop() -- ported from `Fl_WinAPI_Window_Driver::
    // hide()`'s own `RevokeDragDrop((HWND)ip->xid);` (issue #569).
    RevokeDragDrop(rec.hwnd);

    // This little trick keeps the current clipboard alive even if we
    // are about to destroy the window that owns it -- ported from
    // `Fl_WinAPI_Window_Driver::hide()`'s own identical
    // `GetClipboardOwner()`/`fl_update_clipboard()` pair (issue #1233).
    if (GetClipboardOwner() == rec.hwnd)
        updateClipboard();

    // Make sure this window is unlinked from the clipboard-viewer
    // chain -- ported from the same function's own
    // `fl_clipboard_notify_retarget()` call, right after the above.
    clipboardNotifyRetarget(rec.hwnd);

    // Free the double-buffer, if this was a DoubleWindow -- see
    // `freeOffscreen()`'s own doc comment; a no-op if none was ever
    // allocated.
    freeOffscreen(rec);

    DestroyWindow(rec.hwnd);
}

/// Called by `fl.window.Window.clearDamageRegion()` for a whole-widget
/// `damage()` call -- invalidates the entire window (a plain
/// `InvalidateRect(hwnd, null, FALSE)`), matching FLTK's own
/// "damage entire window by deleting the region" semantics exactly (see
/// `clearDamageRegion()` just below for the *real* per-window damage-
/// rect bookkeeping this pairs with).
///
/// Skips the `InvalidateRect()` call while `rec.inPaint` is set, exactly
/// like `accumulateDamageRect()`'s own identical guard just below (see
/// that function's doc comment for the full self-sustaining-loop
/// mechanism -- it applies here verbatim, just via the blanket-`damage()`
/// path instead of the rectangle one). This matters because
/// `fl.text_display.TextDisplay.draw()` faithfully mirrors FLTK's own
/// `Fl_Text_Display::draw()`, which unconditionally calls `mVScrollBar->
/// damage(FL_DAMAGE_ALL)`/`mHScrollBar->damage(FL_DAMAGE_ALL)` on every
/// `FL_DAMAGE_ALL`/`FL_DAMAGE_CHILD` redraw (`Fl_Text_Display.cxx:3982-
/// 3983`) -- harmless on X11 (only accumulates for the next real event
/// loop iteration to notice), but on this platform a blanket `damage()`
/// call routes through `clearDamageRegion()` straight back into this
/// function with no defer-until-the-loop-notices primitive, so doing it
/// from inside `WM_PAINT` re-triggers `WM_PAINT` forever until the guard
/// below breaks the cycle. `accumulateDamageRect()`'s own guard doesn't
/// cover this because `Widget.damage(Damage)` (whole-widget, no rect)
/// goes through `clearDamageRegion()`/`invalidateWindow()`, a separate
/// code path from `damage(Damage,x,y,w,h)`'s `accumulateDamageRect()`.
void invalidateWindow(FlWindow win)
{
    auto rec = recordFor(win);
    if (rec !is null && rec.inPaint) return;
    if (auto hwnd = hwndFor(win))
        InvalidateRect(hwnd, null, FALSE);
}

/// Called by `fl.window.Window.accumulateDamageRect()` (`Widget.
/// damage(Damage,x,y,w,h)`'s own window-relative sub-rectangle) --
/// real damage-rectangle tracking, mirroring `fl.platform_x11.accumulateDamage()` almost exactly
/// (same bounding-box-merge algorithm, same `fullRepaintPending`-stays-
/// unclipped short-circuit -- see that function's own doc comment for
/// the full reasoning, not restated here). The one real difference:
/// X11's `Expose` handling only *accumulates*, leaving the actual
/// `InvalidateRect()`-equivalent scheduling to a separate `flushDamage()`
/// pass run once per event-loop iteration -- Windows has no matching
/// "defer until the loop notices" primitive, so this both accumulates
/// *and* triggers the real `WM_PAINT` immediately via `InvalidateRect()`
/// (device pixels -- the one part of this that *does* need scaling,
/// unlike the logical-unit bounding box kept for the clip itself, see
/// `WindowRecord`'s own doc comment).
///
/// Skips the
/// `InvalidateRect()` call while `rec.inPaint` is set -- i.e. while this
/// very window's `WM_PAINT` case (below) is itself in the middle of
/// calling `win.draw()`. This matters because
/// `fl.value_input.ValueInput.draw()` faithfully mirrors
/// FLTK's own `Fl_Value_Input::draw()`, which propagates its own
/// damage to its embedded private `Fl_Input` via `input_->damage(FL_
/// DAMAGE_ALL)` every time it draws -- entirely harmless on X11, where
/// `accumulateDamage()` only ever *accumulates* a rectangle for the
/// *next* natural event-loop pass to pick up (see this same doc
/// comment's own "X11... only accumulates" paragraph above), so marking
/// a widget damaged again *while already drawing it* has no effect
/// until something real (an actual event) drives the next iteration.
/// This platform's own "no defer-until-the-loop-notices primitive"
/// design choice turns that same, otherwise-inert call into an actively
/// self-sustaining loop: `draw()` (inside `WM_PAINT`) marks a child
/// damaged -> that synchronously calls `InvalidateRect()` -> Windows
/// queues a *new* `WM_PAINT` -> which runs `draw()` again -> which marks
/// the child damaged again -> forever, entirely without any real user
/// input, capped only by how fast the message queue can cycle, pegging a
/// full CPU core. Skipping the invalidate here is correct, not just a
/// band-aid: anything marked damaged *during* the current `draw()` call
/// is, by definition, already being redrawn as part of this very paint
/// pass -- there is nothing left to catch up on that scheduling another
/// `WM_PAINT` would accomplish. A window that gets newly damaged from
/// *outside* an active paint (the normal case -- a widget's own
/// `handle()` reacting to real input) is completely unaffected, since
/// `rec.inPaint` is only ever true for the narrow window between
/// `BeginPaint()` and `EndPaint()` below.
void accumulateDamageRect(FlWindow win, int x, int y, int w, int h)
{
    auto rec = recordFor(win);
    if (rec is null) return;

    if (!rec.fullRepaintPending)
    {
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
    }

    if (rec.inPaint) return;

    float s = screenScale(win.screenNum());
    RECT r;
    r.left = scaledPos(x, s);
    r.top = scaledPos(y, s);
    r.right = r.left + cast(int) scaledDim(w, s);
    r.bottom = r.top + cast(int) scaledDim(h, s);
    InvalidateRect(rec.hwnd, &r, FALSE);
}

/// Called by `fl.window.Window.clearDamageRegion()` for a whole-widget
/// `damage()` call -- discards any accumulated partial-damage rectangle
/// (matching `fl.platform_x11.clearDamageRegion()`'s identical
/// `hasDamageRegion = false; fullRepaintPending = true;`, see that
/// function's own doc comment for why: a stale partial rectangle would
/// otherwise wrongly clip the *next* repaint to less than the whole
/// window), then falls through to the existing whole-window
/// `invalidateWindow()` to actually schedule the real repaint.
void clearDamageRegion(FlWindow win)
{
    if (auto rec = recordFor(win))
    {
        rec.hasDamageRegion = false;
        rec.fullRepaintPending = true;
    }
    invalidateWindow(win);
}

// ---------------------------------------------------------------------
// Message pump -- the direct equivalent of `Fl_WinAPI_System_Driver::
// wait(double)` (`Fl_win32.cxx:369-474`).
// ---------------------------------------------------------------------

/// The GUI thread's id, captured once in `ensureGraphicsDriver()` -- see
/// `wakeMainThread()`.
private __gshared DWORD mainThreadId_;

/// An arbitrary, unused message id `PostThreadMessageW()` posts to wake
/// `waitForMessageOrTimeout()`'s blocked `MsgWaitForMultipleObjects()`
/// call -- its own contents are never read, `pumpMessages()`'s
/// `PeekMessageW()`/`DispatchMessageW()` pair just drains it like any
/// other thread message (a `null`-`hwnd` message dispatches to nothing,
/// which is fine -- the actual work happens in `fl.core.drainAwakeQueue()`,
/// called separately, not from `wndProc()`).
private enum uint wakeupMessage = WM_APP + 47;

/// Ported from `Fl_WinAPI_Screen_Driver::awake()` -- backs
/// `fl.core.awake()`'s Windows branch. A worker thread calls this (via
/// `fl.core.awake()`) after `pushAwakeHandler()` has already queued its
/// handler, to make sure the main thread's blocked wait actually notices
/// before the next real window message would have woken it anyway.
/// `PostThreadMessageW()` targets a thread id directly (no window handle
/// needed), and `MsgWaitForMultipleObjects()`'s `QS_ALLINPUT` mask
/// already includes posted thread messages, so this alone is enough to
/// unblock `waitForMessageOrTimeout()` -- draining the actual queued
/// handler is `fl.core.drainAwakeQueue()`'s job, called from `wait()`/
/// `wait(double)`/`check()` below. A no-op before the first window is
/// created (`mainThreadId_` not yet captured), matching FLTK's own
/// `if (thread_id)` guard.
package(fl) void wakeMainThread()
{
    if (mainThreadId_ == 0) return;
    PostThreadMessageW(mainThreadId_, wakeupMessage, 0, 0);
}

void run()
{
    while (first_ !is null) wait();
}

// Order matches `Fl_WinAPI_System_Driver::wait()`: block first, then
// process the message that ended the block and everything else queued,
// then return. Processing *before* blocking (as this used to) handled
// each message one `wait()` late: a caller that reads state after
// `wait()` returns -- `test/keyboard`'s polling loop -- saw a button
// press only once the *next* message (a mouse move) arrived, and the
// repaint its own `value()` change asked for waited just as long.
// Nothing is lost by blocking first: `waitForMessageOrTimeout()`
// returns at once while any message or repaint (`QS_PAINT`) is pending.
void wait()
{
    fl.core.doWidgetDeletion();
    fl.core.processTimeouts();
    fl.core.runChecks();
    fl.core.runIdle();
    pollFds();
    if (first_ is null) return;

    // Block for the next message or due timer, whichever comes first
    // (or, if any addFd() entry is registered, the next fd-poll tick --
    // see waitForMessageOrTimeout()'s own fdPollInterval clamp).
    waitForMessageOrTimeout(hours(24));

    pumpMessages();
    fl.core.drainAwakeQueue();
}

double wait(double timeToWait)
{
    fl.core.doWidgetDeletion();
    fl.core.processTimeouts();
    fl.core.runChecks();
    fl.core.runIdle();
    pollFds();
    if (first_ is null) return 0.0;

    long us = cast(long)(timeToWait * 1_000_000.0);
    if (us < 0) us = 0;
    bool woken = waitForMessageOrTimeout(dur!"usecs"(us));

    bool processed = pumpMessages();
    fl.core.drainAwakeQueue();
    return (woken || processed) && first_ !is null ? 1.0 : 0.0;
}

bool check()
{
    fl.core.doWidgetDeletion();
    fl.core.processTimeouts();
    fl.core.runChecks();
    fl.core.runIdle();

    pumpMessages();
    fl.core.drainAwakeQueue();
    pollFds();
    return first_ !is null;
}

/// Drains every currently-queued message (matching `wait()`'s own need
/// to process everything already pending before considering a block) --
/// returns whether at least one message was processed.
private bool pumpMessages()
{
    bool any;
    MSG msg;
    while (PeekMessageW(&msg, null, 0, 0, PM_REMOVE) != 0)
    {
        any = true;
        if (msg.message == WM_QUIT)
        {
            first_ = null;
            break;
        }
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }
    return any;
}

/// Blocks until a message arrives or `maxWait` (capped by
/// `fl.core.timeToWait()`, the next due timer) elapses -- the direct
/// equivalent of `fl.platform_x11.waitForEventOrTimeout()`, using
/// `MsgWaitForMultipleObjects()` instead of `select()`.
///
/// **`fl.core.addFd()` entries are folded in**, but not via
/// `MsgWaitForMultipleObjects()`'s own handle
/// list the way `select()` folds in arbitrary fds on the X11 side --
/// see `pollFds()`'s own doc comment for why an anonymous pipe (this
/// project's only real `addFd()` consumer,
/// `source/examples/howto_add_fd_and_popen.d`) can't be waited on that
/// way at all on Windows. Instead, whenever any `fdRead` entry is
/// registered, this clamps its own wait duration to `fdPollInterval` so
/// the caller (`wait()`/`wait(double)`/`check()`) comes back around to
/// call `pollFds()` again soon, regardless of whether any real window
/// message ever arrives in the meantime.
///
/// **Real thread-lock release around the blocking call**: this needs the real
/// `fl.core.unlockForWait()`/`lockForWait()` bracket,
/// unlike `fl.platform_x11.waitForEventOrTimeout()`'s identical
/// `select()` call (see that function's own doc comment, matching
/// FLTK's own `Fl_Unix_Screen_Driver::poll_or_select_with_delay()`).
/// `threads.d`'s `main()` calls `fl.lock()` once before spawning
/// any worker thread and never unlocks it again itself (`run()`/`wait()`
/// are documented, both here and FLTK, as holding the lock the
/// entire time *except* while blocked in exactly this call), so every
/// worker thread's own `fl.lock()` call (`primeFunc()`'s `start2`-guard
/// for `tty2`, and the *unconditional* `fl.lock();
/// n += step; fl.unlock();` in the "n is not prime" branch every worker
/// thread hits, `tty1`'s single thread included) needs the main thread to
/// actually release the mutex while blocked here, or it deadlocks
/// permanently within the first few loop iterations, before any worker
/// thread could ever reach a `fl.awake()` call. The
/// `unlockForWait()`/`lockForWait()` bracket around
/// `MsgWaitForMultipleObjects()` is a no-op unless `fl.core.lock()` was
/// ever called (the common, single-threaded case, matching `fl.core`'s
/// own doc comment on both functions), and otherwise what actually lets
/// a worker thread blocked on `fl.lock()` make progress while the main
/// thread is idle here, matching FLTK's exact contract.
private bool waitForMessageOrTimeout(Duration maxWait)
{
    Duration ttw = fl.core.idleActive() ? Duration.zero : fl.core.timeToWait(hours(24));
    if (ttw < Duration.zero) ttw = Duration.zero;
    if (maxWait < ttw) ttw = maxWait;
    if (fl.core.fdEntries().length > 0 && ttw > fdPollInterval) ttw = fdPollInterval;

    uint ms = cast(uint)(ttw.total!"msecs");
    fl.core.unlockForWait();
    // `MWMO_INPUTAVAILABLE` (beyond FLTK's plain `MsgWaitForMultipleObjects()`):
    // also return for a message already in the queue that some earlier
    // `PeekMessageW()` saw but left there (e.g. `keyEvent()`'s
    // `WM_CHAR`-only peek), which the plain call treats as "not new" and
    // would sleep through now that `wait()` blocks before pumping.
    DWORD result = MsgWaitForMultipleObjectsEx(0, null, ms, QS_ALLINPUT, MWMO_INPUTAVAILABLE);
    fl.core.lockForWait();
    return result == WAIT_OBJECT_0;
}

/// How often `waitForMessageOrTimeout()` re-checks `fl.core.addFd()`
/// entries via `pollFds()` while otherwise idle -- short enough that a
/// piped child process's output feels live, long enough not to spin the
/// CPU polling a pipe that has nothing new to say.
private enum fdPollInterval = dur!"msecs"(50);

/**
 * Polls every `fl.core.addFd()`-registered `fdRead` entry for
 * readiness and invokes its callback when ready -- called from
 * `wait()`/`wait(double)`/`check()`, the same three tick points
 * `pumpMessages()` already runs from.
 *
 * Ported in *spirit* from `fl.platform_x11.waitForEventOrTimeout()`'s
 * own `select()`-based fd multiplexing, but structurally different:
 * Windows anonymous pipes -- what `std.process.pipeShell()`'s piped
 * child-stdout descriptor actually is, the only real `addFd()` consumer
 * in this project's samples (`source/examples/
 * howto_add_fd_and_popen.d`) -- cannot be waited on via
 * `WaitForMultipleObjects()`/`MsgWaitForMultipleObjects()` at all, a
 * well-documented Windows limitation (unlike a genuine `HANDLE`-based
 * wait object such as a process or event handle), not an oversight this
 * port could fix by trying harder. `PeekNamedPipe()` is the standard
 * non-blocking workaround instead: it reports how many bytes are
 * currently available to read without consuming them, and fails once
 * the pipe's write end has been closed and fully drained -- which is
 * why this polls on a short timer (`fdPollInterval`, via
 * `waitForMessageOrTimeout()`'s own clamp) rather than blocking on
 * anything real.
 *
 * `entry.fd` is a C-runtime file descriptor (what `std.stdio.File.
 * fileno` returns), not a raw Win32 `HANDLE` -- `_get_osfhandle()`
 * (`core.stdc.stdio`, `CRuntime_Microsoft`-only, matching this
 * project's MSVCRT-linked Windows build, see `PORTING.md`'s Build
 * section) recovers the real handle `PeekNamedPipe()` needs.
 *
 * Only `fdRead` is backed here -- `fdWrite`/`fdExcept` have no
 * `PeekNamedPipe()`-equivalent non-blocking check for an anonymous
 * pipe, and nothing in this project registers for them. A
 * `PeekNamedPipe()` failure (e.g. `ERROR_BROKEN_PIPE` once the child
 * process has exited and its stdout closed) still fires the callback,
 * matching a Unix pipe's own "readable at EOF" behavior -- this is what
 * lets `howto_add_fd_and_popen.d`'s own `handleFd()` correctly observe
 * `gPipes.stdout.eof` and clean up, rather than the callback silently
 * never firing again once the child process ends.
 */
private void pollFds()
{
    import core.stdc.stdio : _get_osfhandle;

    auto entries = fl.core.fdEntries();
    foreach (ref e; entries)
    {
        if (!(e.when & fdRead)) continue;

        HANDLE h = cast(HANDLE) _get_osfhandle(e.fd);
        if (h is null || h == INVALID_HANDLE_VALUE) continue;

        DWORD bytesAvail;
        BOOL ok = PeekNamedPipe(h, null, 0, null, &bytesAvail, null);
        if (ok && bytesAvail == 0) continue; // nothing to read yet

        e.callback(e.fd); // ok && bytesAvail > 0, or !ok (broken pipe/EOF)
    }
}

void beep(Beep type)
{
    MessageBeep(MB_OK);
}

/// The direct equivalent of `Fl_WinAPI_Screen_Driver::flush()` --
/// `GdiFlush()` only. Unlike `fl.platform_x11.flushDamage()`, this has
/// no repaint of its own to perform: Windows already paints synchronously
/// inside `WM_PAINT` (see `wndProc()`'s own case), so there is no
/// deferred damage for a Windows `flush()` to push out the way X11's
/// Expose-driven model needs.
void flush()
{
    GdiFlush();
}

/// Ported from `Fl_WinAPI_Screen_Driver::get_mouse()` -- returns the
/// real containing-screen index and FLTK-unit (scaled) coordinates,
/// matching `fl.platform_x11.getMouse()`'s identical treatment.
int getMouse(out int x, out int y)
{
    POINT pt;
    GetCursorPos(&pt);
    int screen = screenNumUnscaled(pt.x, pt.y);
    if (screen < 0) screen = 0;
    float s = fl.core.screenScale(screen);
    x = cast(int)(pt.x / s);
    y = cast(int)(pt.y / s);
    return screen;
}

// ---------------------------------------------------------------------
// Multi-monitor -- ported from `Fl_WinAPI_Screen_Driver::init()`/
// `screen_cb()`/`screen_xywh()`/`screen_work_area()`/`screen_num_
// unscaled()` (`Fl_WinAPI_Screen_Driver.cxx`).
// ---------------------------------------------------------------------

/// One physical monitor's bounding box and work area, in real device
/// pixels -- the direct equivalent of FLTK's own `Fl_WinAPI_Screen_
/// Driver::screens[MAX_SCREENS]`/`work_area[MAX_SCREENS]` entries, kept
/// as a growable array rather than a fixed-size one (matching
/// `fl.platform_x11.ScreenInfo[]`'s own identical precedent -- no
/// arbitrary cap needed).
private struct ScreenInfo
{
    int x, y, w, h;
    int workX, workY, workW, workH;
}

private ScreenInfo[] screens_;

/// **Deliberate departure from FLTK, explicitly flagged**: FLTK
/// resolves `EnumDisplayMonitors`/`GetMonitorInfoA` via `GetProcAddress`
/// at runtime specifically to keep working on Windows versions
/// predating multi-monitor support (Windows 2000 pre-SP2, per its own
/// comment) -- this project has no stated support target that old, so
/// this links directly against the modern `W`-suffixed entry points
/// (already present in `core.sys.windows.winuser`, always linkable on
/// any realistically targetable Windows version) instead. The actual
/// *behavior* on any Windows version this project could plausibly run
/// on is identical either way; only the (irrelevant) compatibility floor
/// changes.
private extern (Windows) int screenEnumCallback(HMONITOR mon, HDC, LPRECT, LPARAM) nothrow
{
    try
    {
        MONITORINFO mi;
        mi.cbSize = MONITORINFO.sizeof;
        if (GetMonitorInfoW(mon, &mi))
        {
            ScreenInfo s;
            s.x = mi.rcMonitor.left;
            s.y = mi.rcMonitor.top;
            s.w = mi.rcMonitor.right - mi.rcMonitor.left;
            s.h = mi.rcMonitor.bottom - mi.rcMonitor.top;
            s.workX = mi.rcWork.left;
            s.workY = mi.rcWork.top;
            s.workW = mi.rcWork.right - mi.rcWork.left;
            s.workH = mi.rcWork.bottom - mi.rcWork.top;
            screens_ ~= s;
        }
    }
    catch (Exception)
    {
    }
    return TRUE;
}

/// Lazily populates `screens_` -- ported from `Fl_WinAPI_Screen_
/// Driver::init()`: real per-monitor geometry via `EnumDisplayMonitors()`,
/// falling back to a single synthetic screen spanning
/// `GetSystemMetrics(SM_CXSCREEN/SM_CYSCREEN)` only if the enumeration
/// itself returns nothing (matching FLTK's own "assume 1 monitor"
/// fallback, reached there only when the multi-monitor APIs are
/// unavailable at all -- reached here only if `EnumDisplayMonitors()`
/// itself somehow enumerates zero monitors).
private void initScreens()
{
    if (screens_.length > 0) return;

    EnumDisplayMonitors(null, null, &screenEnumCallback, 0);

    if (screens_.length == 0)
    {
        ScreenInfo s;
        s.w = GetSystemMetrics(SM_CXSCREEN);
        s.h = GetSystemMetrics(SM_CYSCREEN);
        s.workW = s.w;
        s.workH = s.h;
        screens_ ~= s;
    }
}

int screenCount()
{
    initScreens();
    return cast(int) screens_.length;
}

/// Real, undivided device-pixel monitor bounds -- the direct equivalent
/// of `Fl_WinAPI_Screen_Driver::screen_xywh_unscaled()`. The one-shared-
/// value `fakeXWm()` (and any other caller already working in real
/// device pixels) wants this, not the scaled public API below.
void screenXYWHUnscaled(out int x, out int y, out int w, out int h, int n)
{
    initScreens();
    if (n < 0 || n >= screens_.length) n = 0;
    x = screens_[n].x;
    y = screens_[n].y;
    w = screens_[n].w;
    h = screens_[n].h;
}

/// The direct equivalent of `Fl_WinAPI_Screen_Driver::screen_xywh()` --
/// FLTK-unit monitor bounds, divided by `fl.core.screenScale(n)`. Matches
/// `fl.platform_x11.screenXYWH()`'s identical scaled/unscaled split --
/// `fakeXWm()` needs the genuinely-unscaled variant, `screenXYWHUnscaled()`
/// below.
void screenXYWH(out int x, out int y, out int w, out int h, int n)
{
    int rx, ry, rw, rh;
    screenXYWHUnscaled(rx, ry, rw, rh, n);
    float s = fl.core.screenScale(n);
    x = cast(int)(rx / s);
    y = cast(int)(ry / s);
    w = cast(int)(rw / s);
    h = cast(int)(rh / s);
}

/// ditto, for the monitor's work area -- direct equivalent of
/// `Fl_WinAPI_Screen_Driver::screen_work_area()`.
void screenWorkAreaUnscaled(out int x, out int y, out int w, out int h, int n)
{
    initScreens();
    if (n < 0 || n >= screens_.length) n = 0;
    x = screens_[n].workX;
    y = screens_[n].workY;
    w = screens_[n].workW;
    h = screens_[n].workH;
}

/// ditto, scaled -- see `screenXYWH()`'s own doc comment for the same
/// reasoning.
void screenWorkArea(out int x, out int y, out int w, out int h, int n)
{
    int rx, ry, rw, rh;
    screenWorkAreaUnscaled(rx, ry, rw, rh, n);
    float s = fl.core.screenScale(n);
    x = cast(int)(rx / s);
    y = cast(int)(ry / s);
    w = cast(int)(rw / s);
    h = cast(int)(rh / s);
}

/// Ported from `Fl_WinAPI_Screen_Driver::screen_num_unscaled()` --
/// returns `-1` if `(x, y)` isn't in any known monitor, matching
/// FLTK exactly. `(x, y)` is a raw, undivided device-pixel point
/// (e.g. `getMouse()`'s own fresh `GetCursorPos()` result).
int screenNumUnscaled(int x, int y)
{
    initScreens();
    foreach (i, ref s; screens_)
        if (x >= s.x && x < s.x + s.w && y >= s.y && y < s.y + s.h) return cast(int) i;
    return -1;
}

/// The FLTK-unit sibling of `screenNumUnscaled()` -- each monitor's
/// bounds divided by its own `fl.core.screenScale()` before the
/// containment test, matching `fl.platform_x11.screenNum(int,int)`'s
/// identical treatment (see that function's own doc comment for the
/// real cross-screen bug this split was already found to fix on the X11
/// side). `fl.core.screenNum(x,y)` is the public, FLTK-unit-facing
/// entry point that calls this.
int screenNum(int x, int y)
{
    initScreens();
    foreach (i, ref s; screens_)
    {
        float sc = fl.core.screenScale(cast(int) i);
        int sx = cast(int)(s.x / sc), sy = cast(int)(s.y / sc);
        int sw = cast(int)(s.w / sc), sh = cast(int)(s.h / sc);
        if (x >= sx && x < sx + sw && y >= sy && y < sy + sh) return cast(int) i;
    }
    return -1;
}

// ---------------------------------------------------------------------
// WndProc -- the direct equivalent of `Fl_win32.cxx`'s own `WndProc()`
// (`:1242`).
// ---------------------------------------------------------------------

private extern (Windows) LRESULT wndProc(HWND hWnd, UINT uMsg, WPARAM wParam, LPARAM lParam) nothrow
{
    try
    {
        auto rec = find(hWnd);
        if (rec is null) return DefWindowProcW(hWnd, uMsg, wParam, lParam);
        auto win = rec.widget;

        switch (uMsg)
        {
        case WM_CLOSE:
            fl.core.dispatch(Event.close, win);
            return 0;

        case WM_DESTROYCLIPBOARD:
            // Ported from Fl_win32.cxx's own `case WM_DESTROYCLIPBOARD:
            // fl_i_own_selection[1] = 0; break;` -- delivered by
            // Windows specifically to whichever HWND last successfully
            // claimed the clipboard (updateClipboard()'s own
            // OpenClipboard(hwnd) target), so it's safe to clear the
            // CLIPBOARD-slot ownership flag unconditionally here
            // regardless of which window's WndProc happens to receive
            // it -- there is only ever one real clipboard owner at a
            // time.
            fl.core.clearSelectionOwnership(1);
            return 0;

        case WM_CHANGECBCHAIN:
            // Ported from `Fl_win32.cxx`'s own `case WM_CHANGECBCHAIN:`
            // -- delivered only to whichever window is currently
            // targeted (`clipboardWnd_`); relink around the window
            // that's leaving the chain, or forward down the chain if
            // it's someone further along.
            if (hWnd == clipboardWnd_ && nextClipboardWnd_ == cast(HWND) wParam)
                nextClipboardWnd_ = cast(HWND) lParam;
            else
                SendMessageW(nextClipboardWnd_, WM_CHANGECBCHAIN, wParam, lParam);
            return 0;

        case WM_DRAWCLIPBOARD:
            // Ported from `Fl_win32.cxx`'s own `case WM_DRAWCLIPBOARD:`
            // -- this is the real notification event `fl.core.
            // addClipboardNotify()` handlers wait for. `find()` mirrors
            // FLTK's `fl_find()`: while the clipboard moves between
            // two of our own windows, the new owner is still one of
            // ours, so no external-change notification should fire (the
            // `WM_DESTROYCLIPBOARD` above already saw our own ownership
            // flag get cleared transiently during that handoff).
            if (!initialClipboard_ && find(GetClipboardOwner()) is null)
                fl.core.triggerClipboardNotify(1);
            initialClipboard_ = false;

            if (nextClipboardWnd_ !is null)
                SendMessageW(nextClipboardWnd_, WM_DRAWCLIPBOARD, wParam, lParam);

            return 0;

        case WM_PAINT:
        {
            PAINTSTRUCT ps;
            HDC hdc = BeginPaint(hWnd, &ps);
            // See accumulateDamageRect()'s own doc comment: true for the
            // whole rest of this case, so any damage() propagated as a
            // side effect of drawing (fl.value_input.ValueInput.draw()'s
            // own embedded-child propagation, e.g.) doesn't schedule a
            // redundant, self-sustaining follow-up WM_PAINT.
            rec.inPaint = true;

            // A GlWindow gets a dedicated repaint path -- see
            // fl.gl_window.flushGlWindow()'s own doc comment for why it
            // can't share the GDI-specific double-buffer/damage-clip
            // logic below (a real GL back buffer, swapped via WGL, not
            // an offscreen GDI bitmap blitted with BitBlt()) -- mirrors
            // fl.platform_x11.flushDamage()'s identical early branch.
            if (auto glWin = cast(GlWindow) win)
            {
                glWindow.flushGlWindow(glWin);
                rec.inPaint = false;
                EndPaint(hWnd, &ps);
                return 0;
            }

            // Real double-buffering. Mirrors `fl.platform_x11.flushDamage()`'s
            // own `doubleBuffered` branch: a `DoubleWindow` draws into
            // `rec.offscreenDc` (an off-screen `HBITMAP`, (re)allocated
            // here on first use or after a size change) instead of the
            // real on-screen `hdc`, then the whole buffer is blitted onto
            // the real window in one `BitBlt()` after `draw()` returns --
            // see this case's own trailing `if (doubleBuffered)` block.
            // Deliberately *not* applied to every window --
            // matches FLTK/X11's own "double-buffering is opt-in via
            // DoubleWindow" scope exactly, staying
            // faithful to FLTK here rather than deviating.
            bool doubleBuffered = win.type() == doubleWindowTypeTag;
            HDC drawDc = hdc;
            if (doubleBuffered)
            {
                float s = screenScale(win.screenNum());
                int devW = cast(int) scaledDim(win.w(), s);
                int devH = cast(int) scaledDim(win.h(), s);
                if (rec.offscreenDc is null || rec.offscreenW != devW || rec.offscreenH != devH)
                {
                    allocOffscreen(rec, hdc, devW, devH);
                    // A freshly (re)allocated buffer's content is
                    // undefined -- force a full, unclipped repaint so
                    // it's completely populated before the first blit,
                    // the same reasoning `win.clearDamage(win.damage() |
                    // damageExpose)` below already applies to a window's
                    // very first paint.
                    rec.hasDamageRegion = false;
                }
                if (rec.offscreenDc !is null) drawDc = rec.offscreenDc;
            }

            // Real (software-simulated) `fl.overlay_window.OverlayWindow`
            // support, matching `fl.platform_x11.flushDamage()`'s
            // identical branch (see `fl.overlay_window`'s own module doc
            // comment for the full mechanism). `OverlayWindow` always
            // keeps `DoubleWindow`'s own type tag (so `doubleBuffered` is
            // already `true` above whenever `overlayWin !is null`), and
            // is "erased" by recopying the clean backbuffer over it
            // (the `BitBlt()` below) then redrawing straight onto the
            // real on-screen `hdc` afterward -- never onto `rec.
            // offscreenDc`, which would just bake the overlay permanently
            // into the "clean" buffer the next erase recopies from.
            auto overlayWin = cast(OverlayWindow) win;
            bool overlayBitSet = overlayWin !is null && (win.damage() & damageOverlay) != 0;
            bool eraseOverlay = overlayWin !is null && (overlayBitSet || overlayWin.overlayActive());
            if (overlayBitSet)
                win.clearDamage(win.damage() & ~damageOverlay);

            gdiDriver_.setHdc(drawDc);
            FlWindow.setCurrentForDraw(win);
            // Ported from Fl_win32.cxx's own WM_PAINT case: every widget
            // (including this window) starts with damage() == 0, so
            // without setting some non-FL_DAMAGE_CHILD bit here first,
            // FlGroup.draw()/drawChildren()'s own `damage() &
            // ~damageChild` checks are both false on a window that was
            // never separately damage()d -- draw() skips the box/label,
            // and drawChildren() falls into its "only redraw children
            // that already have their own damage set" branch, which
            // finds none (freshly-constructed widgets are undamaged
            // too) and draws literally nothing. damageExpose is a
            // distinct bit from damageChild (0x02 vs 0x01), so ORing it
            // in here is enough to make both checks true and force a
            // real, full initial paint -- exactly FLTK's own
            // `window->clear_damage((uchar)(window->damage() |
            // FL_DAMAGE_EXPOSE));` right before its own flush()/draw().
            win.clearDamage(win.damage() | damageExpose);
            // Real damage-rectangle clipping, mirroring
            // `fl.platform_x11.flushDamage()`'s identical pattern: a
            // window with an accumulated partial rectangle (`fl.window.
            // Window.accumulateDamageRect()` -> this module's own
            // `accumulateDamageRect()`) gets its `draw()` clipped to
            // (the bounding box of) everything actually damaged since
            // the last paint, instead of redrawing -- and, on the GDI
            // side, GDI-painting -- every widget in the tree regardless
            // of whether it changed; a window with no accumulated
            // rectangle (whole-widget damage, e.g. `redraw()`, or a
            // first-ever paint) draws completely unclipped, matching
            // FLTK's own `fl_clip_region(flx_->region)` (null region
            // means "no clip installed") exactly. Without this, every
            // widget click would repaint the entire window's worth of
            // GDI drawing calls regardless of how small the
            // actually-changed widget was, causing full-window flicker.
            bool clipped = rec.hasDamageRegion && !eraseOverlay;
            if (clipped)
            {
                // Unions in Windows'
                // own invalid rectangle (`ps.rcPaint`) before clipping --
                // `rec.damageX/Y/W/H` only ever reflects damage *we*
                // explicitly caused via `redraw()`/`damage()` calls, but
                // `WM_PAINT` also fires for reasons this port never
                // tracks at all: a modal dialog closing and revealing
                // this window's area behind it, restoring from minimize,
                // another window dragged off it, .... Clipping to only
                // the internally-tracked rectangle in those cases would
                // paint
                // *less* than Windows itself is asking for, silently
                // leaving stale pixels in the untracked (but genuinely
                // invalid) region -- e.g. `fl.
                // color_chooser`'s modal dialog closing leaving the
                // triggering color-swatch button showing its old color
                // until some *unrelated* later redraw (e.g. a tooltip)
                // happens to cover its rectangle too. `ps.rcPaint` is in
                // device pixels; `pushClip()` wants FLTK logical units
                // (same convention `rec.damageX/Y/W/H` already follow),
                // so this converts before unioning -- rounding the union
                // outward (floor the top-left, ceil the bottom-right) so
                // the clip never ends up *smaller* than the real invalid
                // region due to truncation.
                if (ps.rcPaint.right > ps.rcPaint.left && ps.rcPaint.bottom > ps.rcPaint.top)
                {
                    float s = screenScale(win.screenNum());
                    int px1 = cast(int)(ps.rcPaint.left / s);
                    int py1 = cast(int)(ps.rcPaint.top / s);
                    int px2 = cast(int)((ps.rcPaint.right + s - 1) / s);
                    int py2 = cast(int)((ps.rcPaint.bottom + s - 1) / s);
                    int dx2 = rec.damageX + rec.damageW;
                    int dy2 = rec.damageY + rec.damageH;
                    if (px1 < rec.damageX) rec.damageX = px1;
                    if (py1 < rec.damageY) rec.damageY = py1;
                    if (px2 > dx2) dx2 = px2;
                    if (py2 > dy2) dy2 = py2;
                    rec.damageW = dx2 - rec.damageX;
                    rec.damageH = dy2 - rec.damageY;
                }
                pushClip(rec.damageX, rec.damageY, rec.damageW, rec.damageH);
            }
            win.draw();
            if (clipped)
                popClip();
            rec.hasDamageRegion = false;
            rec.fullRepaintPending = false;
            rec.inPaint = false;
            win.clearDamage();
            gdiDriver_.setHdc(null);
            // Whole-buffer blit, not just the just-drawn clip rect --
            // correct because the buffer persists between paints (its
            // already-correct, previously-drawn pixels outside this
            // pass's own clip are untouched and still valid), and
            // simpler than computing/converting the clip rect to device
            // pixels a second time just for the blit's own source/dest
            // rectangles.
            if (doubleBuffered && rec.offscreenDc !is null)
                BitBlt(hdc, 0, 0, rec.offscreenW, rec.offscreenH, rec.offscreenDc, 0, 0, SRCCOPY);

            if (overlayWin !is null && overlayWin.overlayActive())
            {
                // The blit above just recopied a clean, overlay-free
                // backbuffer onto the real on-screen window (or, if
                // offscreen allocation failed, there was nothing to
                // erase with -- draw the fresh overlay directly
                // regardless, matching FLTK's own lack of a
                // fallback for that pathological case). Drawing onto
                // `hdc` here, never `rec.offscreenDc`, is the whole
                // point: this pixel data is never part of the
                // backbuffer, so it's naturally "erased" next time this
                // branch's own `BitBlt()` recopies the backbuffer over
                // it.
                gdiDriver_.setHdc(hdc);
                overlayWin.drawOverlay();
                gdiDriver_.setHdc(null);
            }

            EndPaint(hWnd, &ps);
            return 0;
        }

        case WM_GETMINMAXINFO:
            // Ported from `Fl_win32.cxx`'s own `case WM_GETMINMAXINFO:
            // ...->set_minmax(...); break;` -- falls through to
            // `DefWindowProcW` afterward (not `return 0`), matching
            // FLTK exactly, so any `MINMAXINFO` field this doesn't
            // touch (`ptMaxPosition`, `ptReserved`) still gets the
            // system's own default.
            setMinMax(win, cast(LPMINMAXINFO) lParam);
            break;

        case WM_SIZE:
        {
            // Ported from `Fl_win32.cxx`'s own `Fl_Window_Driver::
            // driver(window)->is_maximized(wParam == SIZE_MAXIMIZED);`
            // -- keeps `maximizeActive()` in sync with an externally
            // triggered maximize/restore (double-clicking the title
            // bar, the taskbar's own "Maximize"/"Restore" context-menu
            // entry, Win+Up/Win+Down, ...), not just this module's own
            // `maximizeOn()`/`maximizeOff()`. Matches FLTK's own
            // unconditional call on every `WM_SIZE` (any value other
            // than `SIZE_MAXIMIZED` clears the flag, including
            // `SIZE_MINIMIZED` -- FLTK doesn't special-case that
            // combination either).
            if (wParam == SIZE_MAXIMIZED) win.setMaximizedFlag();
            else win.clearMaximizedFlag();

            if (wParam != SIZE_MINIMIZED)
            {
                // Divides the real device-pixel client size back down to
                // FLTK units before calling resize() -- matching
                // `fl.platform_x11`'s own `ConfigureNotify` handler:
                // position rounds to nearest, size rounds *up*, "never
                // under-report a window's size after a scaled resize".
                float s = screenScale(win.screenNum());
                int devW = cast(short) LOWORD(lParam);
                int devH = cast(short) HIWORD(lParam);
                import std.math : ceil;

                int w = cast(int) ceil(devW / cast(double) s);
                int h = cast(int) ceil(devH / cast(double) s);

                // The missing counterpart to `WM_MOVE`'s own
                // `resizeBugFix_ = win;` a few cases below -- without
                // it, this call is indistinguishable from a genuine
                // program-initiated resize, so `Window.resize()`
                // re-issues a real `SetWindowPos()` in response to what
                // is often just an *echo* of a resize we ourselves just
                // requested (e.g. `resizeAfterScaleChange()`'s own
                // `SetWindowPos()` a moment ago). Confirmed as a real,
                // live, reported bug via a captured debug log: each
                // echoed `WM_SIZE`'s real device-pixel client rect came
                // back a few pixels smaller than what was actually
                // requested (a separate, still-open border-compensation
                // rounding gap), and re-issuing `SetWindowPos()` for
                // every one of those slightly-off echoes would compound
                // into a runaway shrink -- the window visibly collapsing
                // to nothing within a fraction of a second of a single
                // DPI change. Matches FLTK's own `resize_bug_fix =
                // window;` placed right before `window->size(...)` in
                // `Fl_win32.cxx`'s own `WM_SIZE` case (its "not currently
                // being dragged by the title bar" branch specifically --
                // this port doesn't yet track that distinct
                // `moving_window` state FLTK also has, so this
                // guards every `WM_SIZE` unconditionally rather than
                // only that one branch).
                resizeBugFix_ = win;
                win.resize(win.x(), win.y(), w, h);
            }
            return 0;
        }

        case WM_MOVE:
        {
            // Ported from `Fl_win32.cxx`'s own `case WM_MOVE:` -- the
            // real counterpart to `WM_SIZE` just above. Without
            // this, a window dragged by its title bar (or snapped/
            // restored by the OS) would never update this port's own tracked
            // `win.x()`/`win.y()`, staying at whatever it was at
            // creation (or the last `position()` call) forever after --
            // e.g. a popup menu computed from `window().x() +
            // widget.x()` (`fl.menu_popup`) would keep appearing at the
            // window's *original* screen location after moving it,
            // since that arithmetic's `window().x()` input would be stale.
            // `fl.platform_x11`'s own `ConfigureNotify` handler is the
            // Linux analogue -- same "relay the WM's/OS's already-applied
            // geometry back into this port's own tracked position" role,
            // same `resizeBugFix_` echo-prevention guard (skip issuing a
            // redundant `SetWindowPos()` back to the OS for a move it
            // just told us about).
            if (!IsIconic(hWnd) && win.parent() is null)
            {
                float s = screenScale(win.screenNum());

                // **Cross-screen-with-*matching*-scale detection, ported
                // from `Fl_win32.cxx`'s own `WM_MOVE` case**: `case
                // dpiChangedMessage:` above alone doesn't cover every
                // cross-screen case. Per
                // Windows' own documented `WM_DPICHANGED` contract ("The
                // current DPI for a window always equals the last DPI
                // sent by WM_DPICHANGED"), Windows never sends `WM_
                // DPICHANGED` for a move between two monitors that happen
                // to share the same scale -- so on a multi-monitor rig
                // with more than one same-scaled screen (e.g. two 100%
                // monitors plus one 150% laptop panel), dragging a window
                // between the two 100%
                // screens would otherwise
                // never relocate its own `screenNum()` cache at all,
                // silently going stale, reachable via
                // `fl.core.rescaleAllWindowsFromScreen()`'s own
                // `screenNum() == screen` filter and `screenWorkArea()`/
                // fullscreen/maximize-clamping, all of which read that
                // same stale cache. Compares `rawDpiXFor()` (the OS's own
                // raw, zoom-unaware per-screen DPI), not `screenScale()`
                // directly -- matching FLTK's own raw `dpi[news][0]
                // == dpi[olds][0]` comparison exactly. Using `screenScale()`
                // here instead would misfire once a screen carries a
                // Ctrl-+/-- zoom: two monitors with the *same* real OS DPI
                // but *different* app-level zoom would wrongly compare as
                // "different screens," and (rarer, but real) two monitors
                // with genuinely different OS DPI could coincidentally
                // compare as "same" if their zoom levels happened to
                // offset the difference -- see `dpiChangedMessage`'s own
                // doc comment for the matching fix there and the concrete
                // zoom-preservation bug this exact substitution caused
                // once already. **Not ported**: FLTK's own Issue #1097
                // fullscreen-restore-ordering special case (`*wd->no_
                // fullscreen_w()`/`_h()` substituted for `window->w()`/
                // `h()` mid-transition) -- a narrow, separate edge case,
                // not needed for the cross-screen scale bug this closes.
                {
                    int olds = win.screenNum();
                    int cX = cast(short) LOWORD(lParam) + cast(int)(win.w() * s / 2);
                    int cY = cast(short) HIWORD(lParam) + cast(int)(win.h() * s / 2);
                    int news = screenNumUnscaled(cX, cY);
                    if (news == -1) news = olds;
                    else if (news != olds && rawDpiXFor(news) == rawDpiXFor(olds))
                    {
                        win.rawScreenNum(news);
                        // Matches FLTK's own `scale = sd->scale(news);`
                        // right after `wd->screen_num(news)` in this same
                        // branch -- without it, the position math just
                        // below still divides by the *old* screen's own
                        // scale, wrong the moment the two same-raw-DPI
                        // monitors carry different Ctrl-+/-- zoom levels.
                        s = screenScale(news);
                        win.redraw();
                    }
                }

                int devX = cast(short) LOWORD(lParam);
                int devY = cast(short) HIWORD(lParam);
                import std.math : round;

                // The window's exact, confirmed device-pixel position,
                // kept live so `Window.resizeAfterScaleChange()` never
                // has to reconstruct an approximation of it from lossier
                // FLTK units -- the direct Windows counterpart of
                // `fl.platform_x11`'s identical `ConfigureNotify`
                // assignment (see `devicePosX_`/`devicePosY_`'s own doc
                // comment for the rounding bug this
                // avoids).
                win.devicePosX_ = devX;
                win.devicePosY_ = devY;

                int newX = cast(int) round(devX / s);
                int newY = cast(int) round(devY / s);
                resizeBugFix_ = win;
                win.resize(newX, newY, win.w(), win.h());
            }
            return 0;
        }

        case dpiChangedMessage:
        {
            // Ported from `Fl_win32.cxx`'s own real `case WM_DPICHANGED:`.
            //
            // **Branches on `rawDpiX_[screen]` (the OS's own raw, zoom-
            // unaware DPI, matching FLTK's `dpi[ns][0]`), not on
            // `fl.core.screenScale()` directly.** `wParam` always carries
            // the *raw* OS DPI, never anything zoom-inclusive, so
            // comparing it against the zoom-inclusive `screenScale()`
            // table can't tell "this screen's own OS-level baseline
            // genuinely changed" apart from "this screen was already
            // known, just zoomed (Ctrl-+/-) differently than its raw DPI
            // alone suggests." Concretely: zoom screen E to 110% via
            // Ctrl-+, then drag a window from a 150% monitor onto E --
            // `wParam` reports E's real, unzoomed 96 DPI (Windows has no
            // concept of FLTK's own app-level zoom); comparing that
            // directly against `screenScale(E) == 1.5` (the arriving
            // window's own prior scale) would look like a genuine change
            // and overwrite E's table entry with 1.0, silently discarding
            // the zoom every other window already on E was drawing at --
            // the exact bug this whole phase fixes, reached through zoom
            // instead of a bare drag. Comparing raw DPI first avoids ever
            // writing the table when the arriving window's destination
            // screen was already correctly known (zoomed or not); the
            // *existing* `screenScale(screen)` is adopted as-is in that
            // case, preserving whatever zoom is already there, matching
            // FLTK's own real `else if (!sizing_window)` branch (this
            // port doesn't track a `sizing_window`-equivalent live-resize
            // flag, so this always takes the "just moved" path rather
            // than also branching on that -- a narrower, separate
            // simplification, unrelated to the zoom-preservation fix
            // here: it only matters for the rare case of a live DPI
            // change arriving *while* a window is being resized by
            // dragging its own border, where FLTK does something
            // different -- see `Fl_win32.cxx`'s own `WM_DPICHANGED`
            // case for the full branch this port doesn't replicate).
            if (win.parent() is null)
            {
                int newDpiX = LOWORD(cast(uint) wParam);

                // The *center* of Windows' suggested new rect, not its
                // top-left corner -- near a monitor boundary the top-left
                // corner can still read as the old monitor while the
                // window's actual bulk (and this DPI notification)
                // already belongs to the new one. `screenNumUnscaled()`,
                // not `fl.core.screenNum()` -- the suggested rect is real,
                // undivided device pixels, and `fl.core.screenNum()`
                // expects FLTK units (it divides each monitor's bounds by
                // its own scale before comparing, see that function's own
                // doc comment). Passing device pixels into it would
                // silently compare against the wrong scaled bounds --
                // exactly the FLTK `screen_num_unscaled()` vs.
                // `screen_num()` distinction this module already tracks
                // (see `screenNumUnscaled()`'s own doc comment).
                auto suggested = cast(RECT*) lParam;
                int screen = suggested !is null
                    ? screenNumUnscaled((suggested.left + suggested.right) / 2,
                        (suggested.top + suggested.bottom) / 2)
                    : win.screenNum();
                if (screen < 0) screen = win.screenNum();

                // This window's own *current, real* client-rect width
                // divided by its own FLTK-unit `w()`, not a per-screen
                // table read -- matches FLTK's own `float old_f =
                // float(r.right) / window->w();` exactly. Immune to
                // ordering when *two* windows already sit on the same
                // screen and a live Settings DPI change fires `WM_
                // DPICHANGED` for both separately, one after another --
                // reading `fl.core.screenScale(win.screenNum())` instead
                // would see whichever value the *first* window's own
                // handler already wrote, not this window's own actual
                // pre-change geometry.
                float targetScale;
                RECT clientRect;
                GetClientRect(hWnd, &clientRect);
                float oldWindowScale = win.w() > 0
                    ? cast(float) clientRect.right / win.w() : 1.0f;

                if (rawDpiXFor(screen) != newDpiX)
                {
                    // Screen `screen`'s own OS-level DPI genuinely
                    // differs from what was last recorded for it --
                    // adopt it as the new baseline, discarding whatever
                    // zoom that screen had (matching FLTK's own
                    // unconditional `Fl::screen_driver()->scale(ns, f)`
                    // here -- a live OS-level Settings DPI change is
                    // rare enough that FLTK doesn't try to preserve
                    // zoom across it either).
                    rawDpiXFor(screen, newDpiX);
                    // FLTK: `sd->dpi[ns][0] = sd->dpi[ns][1] = ...`
                    if (screen >= 0 && screen < rawDpiY_.length) rawDpiY_[screen] = newDpiX;
                    targetScale = newDpiX / 96.0f;
                    fl.core.screenScale(screen, targetScale);
                    // Matches FLTK's own `base_scale(int n) { return
                    // float(dpi[n][0] / 96.); }`, which reads `dpi[n]`
                    // live -- without re-seeding this too, a live Settings
                    // DPI change would leave `fakeXWm()`'s own border
                    // computation and the Ctrl-'0' reset target both
                    // anchored to the *old* baseline for this screen.
                    fl.core.seedBaseScale(screen, targetScale);
                }
                else
                {
                    // Already-known DPI for `screen` -- this window just
                    // arrived there (by drag, or a same-raw-DPI move `WM_
                    // MOVE` already relocated it for). Adopt that
                    // screen's own *existing* scale as-is, zoom included.
                    targetScale = fl.core.screenScale(screen);
                }

                if (targetScale != oldWindowScale)
                    win.resizeAfterScaleChange(screen, oldWindowScale, targetScale);
                else if (win.screenNum() != screen)
                    win.rawScreenNum(screen);
            }
            return 0;
        }

        case WM_LBUTTONDOWN: mouseEvent(win, hWnd, 0, 1, wParam, lParam); return 0;
        case WM_LBUTTONDBLCLK: mouseEvent(win, hWnd, 1, 1, wParam, lParam); return 0;
        case WM_LBUTTONUP: mouseEvent(win, hWnd, 2, 1, wParam, lParam); return 0;
        case WM_MBUTTONDOWN: mouseEvent(win, hWnd, 0, 2, wParam, lParam); return 0;
        case WM_MBUTTONDBLCLK: mouseEvent(win, hWnd, 1, 2, wParam, lParam); return 0;
        case WM_MBUTTONUP: mouseEvent(win, hWnd, 2, 2, wParam, lParam); return 0;
        case WM_RBUTTONDOWN: mouseEvent(win, hWnd, 0, 3, wParam, lParam); return 0;
        case WM_RBUTTONDBLCLK: mouseEvent(win, hWnd, 1, 3, wParam, lParam); return 0;
        case WM_RBUTTONUP: mouseEvent(win, hWnd, 2, 3, wParam, lParam); return 0;
        case WM_XBUTTONDOWN:
            mouseEvent(win, hWnd, 0, 3 + cast(int) HIWORD(wParam), wParam, lParam);
            return TRUE;
        case WM_XBUTTONDBLCLK:
            mouseEvent(win, hWnd, 1, 3 + cast(int) HIWORD(wParam), wParam, lParam);
            return TRUE;
        case WM_XBUTTONUP:
            mouseEvent(win, hWnd, 2, 3 + cast(int) HIWORD(wParam), wParam, lParam);
            return TRUE;
        case WM_MOUSEMOVE:
            mouseEvent(win, hWnd, 3, 0, wParam, lParam);
            return 0;

        case WM_MOUSEWHEEL:
        {
            short delta = cast(short) HIWORD(wParam);
            fl.core.eDx_ = 0;
            fl.core.eDy_ = delta > 0 ? -1 : 1;
            fl.core.dispatch(Event.mouseWheel, win);
            return 0;
        }

        // Horizontal wheel (a tilting scroll wheel or a trackpad's
        // horizontal swipe) -- FLTK's `Fl_win32.cxx` handles this
        // as a separate message, distinct from Shift+WM_MOUSEWHEEL,
        // matching this port's own X11 side (button 6/7, see
        // `fl.platform_x11.d`'s identical `eDx_`-only dispatch). A
        // positive `HIWORD(wParam)` means "rotated right" per MSDN,
        // matching X11 button 7 -> `eDx_ = 1` exactly.
        case WM_MOUSEHWHEEL:
        {
            short delta = cast(short) HIWORD(wParam);
            fl.core.eDy_ = 0;
            fl.core.eDx_ = delta > 0 ? 1 : -1;
            fl.core.dispatch(Event.mouseWheel, win);
            return 0;
        }

        case WM_SETFOCUS:
            // Deliberately routes through `fl.core.fixFocus()` rather
            // than dispatching `Event.
            // focus` *directly* to the window widget -- exactly the
            // mistake `fl.core.fixFocus()`'s own doc comment already
            // documents as a real X11 bug ("Skipping
            // straight to Fl::handle(FL_UNFOCUS, window)-style dispatch
            // ... never reaches the truly-focused child widget at all").
            // On Windows direct dispatch additionally causes genuine infinite
            // recursion, not just a silently-missed notification:
            // `FlGroup.handle(Event.unfocus)` (reached via the window's
            // own `Window.handle()` -> `super.handle()`) sets `saved
            // focus_ = fl.core.oldFocus()`, but `oldFocus_` is only
            // updated by the real ancestor-walk `fl.core.focus(Widget)`
            // performs (one
            // ancestor level at a time) -- direct dispatch bypasses it
            // entirely, so `oldFocus_` could still hold a *stale* value
            // from whatever the last real `focus()` call left it as,
            // including the window itself once that call's own ancestor
            // walk reached the top. If `savedfocus_` became self-
            // referential this way (`savedfocus_ is win`), the next
            // `Event.focus` sent this same direct-dispatch way would hit
            // `FlGroup.handle()`'s own `savedfocus_.takeFocus()` branch,
            // which calls `handle(Event.focus)` on `win` again -- the
            // exact same event, on the exact same widget, forever: an
            // unbroken cycle
            // of `Widget.takeFocus()` -> `Window.handle()` ->
            // `FlGroup.handle()`'s `savedfocus_.takeFocus()` -> back to
            // `Widget.takeFocus()`, exhausting
            // the entire 1MB thread stack (`STATUS_STACK_OVERFLOW`) --
            // reachable via any interaction cycling OS input focus
            // away from and back to the main window, e.g. opening then
            // closing a popup menu or a dialog.
            // `fl.core.fixFocus()`
            // exactly matches `fl.platform_x11`'s own `case FocusIn:`/
            // `case FocusOut:` (see that module's identical doc comment
            // for the full mechanism) -- it performs the real
            // ancestor-aware focus restoration this needs, the same
            // function this module's own `createWindow()` already calls
            // for a newly-shown modal window.
            fl.core.fixFocus(win);
            return 0;

        case WM_KILLFOCUS:
            // ditto -- matches `fl.platform_x11`'s own `case FocusOut:`
            // exactly (`fl.core.fixFocus(null)`, unconditionally, same
            // reasoning: a well-behaved window manager -- Windows itself
            // here -- only ever sends this to whichever window is really
            // losing focus, nothing to disambiguate).
            fl.core.fixFocus(null);
            return 0;

        case WM_SETCURSOR:
            // Ported from `Fl_win32.cxx`'s own `case WM_SETCURSOR:` --
            // Windows resets the cursor to the window class's default
            // (the plain arrow, per `registerWindowClass()`'s own
            // `hCursor`) on every mouse-move over the client area unless
            // this message is handled to re-assert whatever `setCursor()`
            // last stored. Walks up to the top-level the same way
            // `Fl_Window::cursor()` already does before ever calling in
            // here, matching FLTK's own `while (window->parent())
            // window = window->window();`.
            if (cast(int) LOWORD(lParam) == HTCLIENT)
            {
                FlWindow top = win;
                while (top.window() !is null) top = top.window();
                if (auto topRec = recordFor(top))
                    SetCursor(topRec.cursor);
                return 0;
            }
            break;

        case WM_KEYDOWN:
        case WM_SYSKEYDOWN:
        case WM_KEYUP:
        case WM_SYSKEYUP:
            keyEvent(win, hWnd, uMsg, wParam, lParam);
            return 0;

        case WM_CHAR:
        case WM_SYSCHAR:
        case WM_DEADCHAR:
        case WM_SYSDEADCHAR:
            // Normally consumed inline by WM_KEYDOWN/WM_SYSKEYDOWN's own
            // PeekMessageW() lookahead (see keyEvent()) -- reached here
            // directly whenever one of these arrives with no immediately-
            // preceding keydown this module claimed itself, which is
            // exactly how an input method delivers composed/committed
            // text and how the Windows emoji picker (Win+.) delivers a
            // picked character -- see charEvent()'s own doc comment.
            charEvent(win, uMsg, wParam);
            return 0;

        default:
            break;
        }

        return DefWindowProcW(hWnd, uMsg, wParam, lParam);
    }
    catch (Throwable t)
    {
        // Catches `Throwable`, not just `Exception`, so an `Error`
        // (RangeError/AssertError/...) doesn't fall straight through as
        // an unhandled crash with zero D-level diagnostic -- reports
        // before falling back to the same safe default handling.
        // This function stays `nothrow` (a D exception must never
        // unwind back through a Windows-owned callback frame), so the
        // logging call itself is wrapped in its own swallow-everything
        // try/catch.
        try
        {
            import std.stdio : stderr;
            stderr.writefln("fldtk: unhandled %s in WndProc (uMsg=0x%04X): %s",
                typeid(t).name, uMsg, t.toString());
            stderr.flush();
        }
        catch (Throwable) {}
        return DefWindowProcW(hWnd, uMsg, wParam, lParam);
    }
}

/// The direct equivalent of `mouse_event()` (`Fl_win32.cxx:1039-1113`).
/// `what` is 0=press/1=doubleclick/2=release/3=move, `button_` is 1-5+
/// (matching `fl.enumerations`' `leftMouse`/`middleMouse`/`rightMouse`/
/// `backMouse`/`forwardMouse` numbering).
/// Click-vs-drag baseline -- the FLTK-unit root position and
/// `GetMessageTime()` timestamp recorded at the most recent button
/// press, compared against on every subsequent mouse event to decide
/// whether `fl.core.eIsClick_` should still count as a pending click.
/// See `mouseEvent()`'s own doc comment on that field for why this
/// exists at all; mirrors `fl.platform_x11`'s private `px_`/`py_`/
/// `ptime_` (that module's own `checkdouble()`/`setEventXY()`), minus
/// the click-*counting* half (`eClicks_`), which Windows never needs --
/// double-clicks are detected natively via `CS_DBLCLKS`, see `case 1`
/// below.
private int clickX_, clickY_;
private DWORD clickTime_;

/**
 * Ported from `Fl_win32.cxx`'s own `mouse_event()`. Real click-vs-drag
 * detection matters for `Adjuster`'s own `case
 * Event.release: if (fl.core.eventIsClick())` branch, distinguishing a
 * plain click from a drag, and any other widget checking
 * `fl.core.eventIsClick()`. Mirrors `fl.platform_x11.
 * setEventXY()`'s own cancel check (moved more than 3 FLTK units, or
 * more than 1000ms since the press) plus `checkdouble()`'s own
 * press-time `eIsClick_ = true` + baseline reset, folded into this
 * function directly rather than split across two helpers the way X11's
 * `Expose`/`ButtonPress`-vs-every-other-event split needs (Windows
 * already funnels every mouse message through this one function).
 *
 * **Walks up to the real top-level ancestor**: ported from FLTK's own identical `while
 * (window->parent()) { Fl::e_x += window->x(); Fl::e_y += window->y();
 * window = window->window(); }` loop (`Fl_win32.cxx`). Necessary
 * because Win32 delivers a raw mouse message directly to whichever
 * real `HWND` -- a subwindow's own child `HWND`, or the top-level's --
 * is actually under the cursor, unlike this port's X11 side, where a
 * subwindow's reduced event mask (`ExposureMask` only) means only the
 * top-level ever receives one in the first place: `fl.core.dispatch()`/
 * `sendEvent()` (`fl.core.d`, shared by both platforms, authored
 * against exactly that X11 contract) expect `window` to already *be*
 * the top-level and `eX_`/`eY_` already expressed relative to it, so
 * this is the one place that gap needs closing for Windows to present
 * the same shape. `SetCapture()`/`ReleaseCapture()` target the
 * top-level's own `HWND` too, not the originally-clicked subwindow's --
 * matching FLTK's own `SetCapture(fl_xid(window))` call, made
 * *after* this same walk-up (its default, non-`USE_CAPTURE_MOUSE_WIN`
 * build path).
 */
private void mouseEvent(FlWindow win, HWND hWnd, int what, int button_, WPARAM wParam, LPARAM lParam)
{
    int x = cast(short) LOWORD(lParam);
    int y = cast(short) HIWORD(lParam);

    POINT pt = POINT(x, y);
    ClientToScreen(hWnd, &pt);

    // Divides raw device-pixel coordinates down to FLTK units, matching
    // `fl.platform_x11.setEventXY()`'s identical `cast(int)(v / s)`
    // treatment. `win.screenNum()`'s own scale, not a hardcoded screen 0 -- this
    // event's own window's screen.
    float s = screenScale(win.screenNum());
    fl.core.eX_ = cast(int)(x / s);
    fl.core.eY_ = cast(int)(y / s);
    fl.core.eXRoot_ = cast(int)(pt.x / s);
    fl.core.eYRoot_ = cast(int)(pt.y / s);

    FlWindow topWin = win;
    while (topWin.parent() !is null)
    {
        fl.core.eX_ += topWin.x();
        fl.core.eY_ += topWin.y();
        topWin = topWin.window();
    }
    HWND topHwnd = hwndFor(topWin);
    if (topHwnd is null) topHwnd = hWnd;

    fl.core.eState_ = keyModifierState() | mouseButtonState(wParam);

    // The general cancel check -- runs for every event type, including
    // press itself (harmless there: press unconditionally re-arms
    // eIsClick_/the baseline again right below, in the switch, the same
    // order X11's own setEventXY()-then-checkdouble() split uses).
    import std.math : abs;

    DWORD now = GetMessageTime();
    if (abs(fl.core.eXRoot_ - clickX_) + abs(fl.core.eYRoot_ - clickY_) > 3
        || now - clickTime_ > 1000)
        fl.core.eIsClick_ = false;

    switch (what)
    {
    case 0: // press
        fl.core.eClicks_ = 0;
        fl.core.eKeysym_ = cast(Keysym)(button + button_);
        SetCapture(topHwnd);
        fl.core.eIsClick_ = true;
        clickX_ = fl.core.eXRoot_;
        clickY_ = fl.core.eYRoot_;
        clickTime_ = now;
        fl.core.dispatch(Event.push, topWin);
        break;
    case 1: // doubleclick (Windows detects this itself, via CS_DBLCLKS)
        fl.core.eClicks_ = 1;
        fl.core.eKeysym_ = cast(Keysym)(button + button_);
        SetCapture(topHwnd);
        fl.core.eIsClick_ = true;
        clickX_ = fl.core.eXRoot_;
        clickY_ = fl.core.eYRoot_;
        clickTime_ = now;
        fl.core.dispatch(Event.push, topWin);
        break;
    case 2: // release
        fl.core.eKeysym_ = cast(Keysym)(button + button_);
        ReleaseCapture();
        fl.core.dispatch(Event.release, topWin);
        break;
    default: // move (fl.core.handle() upgrades to Event.drag when pushed())
        fl.core.dispatch(Event.move, topWin);
        break;
    }
}

private EventState keyModifierState()
{
    EventState s;
    if (GetKeyState(VK_SHIFT) & 0x8000) s |= stateShift;
    if (GetKeyState(VK_CONTROL) & 0x8000) s |= stateCtrl;
    if (GetKeyState(VK_MENU) & 0x8000) s |= stateAlt;
    if (GetKeyState(VK_CAPITAL) & 1) s |= stateCapsLock;
    if (GetKeyState(VK_NUMLOCK) & 1) s |= stateNumLock;
    return s;
}

private EventState mouseButtonState(WPARAM wParam)
{
    EventState s;
    if (wParam & MK_LBUTTON) s |= stateButton1;
    if (wParam & MK_MBUTTON) s |= stateButton2;
    if (wParam & MK_RBUTTON) s |= stateButton3;
    if (wParam & MK_XBUTTON1) s |= stateButton4;
    if (wParam & MK_XBUTTON2) s |= stateButton5;
    return s;
}

/**
 * The direct equivalent of the combined `WM_KEYDOWN`/`WM_SYSKEYDOWN`/
 * `WM_KEYUP`/`WM_SYSKEYUP`/`WM_CHAR`/`WM_SYSCHAR` case block in
 * `Fl_win32.cxx:1550-1734`: peeks ahead for a `WM_CHAR`/`WM_SYSCHAR`
 * `TranslateMessage()` already queued for this same physical keypress
 * (consuming it if present) so a single `Event.keyDown`/`keyUp` dispatch
 * carries both `eventKey()` and `eventText()` together, matching
 * FLTK's one-dispatch-per-physical-keypress behavior rather than
 * firing twice (once with no text, once with text but a stale keysym).
 *
 * Simplifications (see this module's own top comment). Real surrogate-pair merging (via the shared
 * `decodeCharUnit()` helper -- see that
 * function's own doc comment) and NumLock/keypad remap -- see
 * `numpadOriginalKeysym()`'s own doc comment for the mechanism.
 */
private void keyEvent(FlWindow win, HWND hWnd, uint uMsg, WPARAM wParam, LPARAM lParam)
{
    bool isUp = (uMsg == WM_KEYUP || uMsg == WM_SYSKEYUP);
    bool extended = (lParam & 0x0100_0000) != 0; // lParam bit 24
    uint scanCode = cast(uint)(lParam >> 16) & 0xff; // lParam bits 16-23
    Keysym keysym = vkToKeysym(cast(int) wParam, extended, scanCode);
    // Kludge to allow recognizing ctrl+'-' on keyboards with digits in
    // uppercase positions (e.g. French) -- ported from Fl_win32.cxx's
    // own identical fix (`Fl_win32.cxx:1549-1552`): on such a layout the
    // physical key that types '-' unshifted also types '6' shifted, so
    // `vkToKeysym()` (a shift-independent, purely positional mapping)
    // resolves it to '6' -- indistinguishable, without this check, from
    // the real '6' key elsewhere on the keyboard.
    if (keysym == '6' && (VkKeyScanA('-') & 0xff) == '6')
        keysym = cast(Keysym) '-';
    fl.core.eKeysym_ = keysym;

    // `eOriginalKeysym_` always holds the NumLock-independent "kp +
    // digit/operator" identity for a genuine numpad key, decoupled from
    // whatever `eKeysym_` resolves to live (a digit with NumLock on, an
    // arrow/Home/End/etc. meaning with it off) -- matching
    // `fl.platform_x11`'s identical dual-keysym model (see that
    // module's own NumLock/keypad remap comment). Falls back to
    // `keysym` itself for every non-numpad key, same as before.
    Keysym original = numpadOriginalKeysym(cast(int) wParam, extended);
    fl.core.eOriginalKeysym_ = original != 0 ? original : keysym;
    // Keyboard messages carry no mouse-button state of their own --
    // preserve whatever mouseEvent() last recorded rather than clobbering
    // it, matching FLTK's own `state = Fl::e_state & 0xff000000`.
    fl.core.eState_ = keyModifierState() | (fl.core.eState_ & stateButtons);

    string text;
    MSG charMsg;
    // Upstream peeks the single range `WM_CHAR..WM_SYSDEADCHAR`, which
    // also spans `WM_SYSKEYDOWN`/`WM_SYSKEYUP` and so can swallow the
    // next queued Alt+key press when this key produced no character.
    // Two peeks cover just the four character messages.
    bool gotChar = !isUp
        && (PeekMessageW(&charMsg, hWnd, WM_CHAR, WM_DEADCHAR, PM_REMOVE)
            || PeekMessageW(&charMsg, hWnd, WM_SYSCHAR, WM_SYSDEADCHAR, PM_REMOVE));
    bool isDead = gotChar
        && (charMsg.message == WM_DEADCHAR || charMsg.message == WM_SYSDEADCHAR);
    // A dead key delivers empty text, matching FLTK's (non-
    // FLTK_PREVIEW_DEAD_KEYS) `buffer[0] = 0; Fl::e_length = 0;`.
    if (gotChar && !isDead)
    {
        wchar wc = cast(wchar) charMsg.wParam;
        if (wc >= 0x20 || wc == '\t' || wc == '\r' || wc == '\n')
        {
            // A lone high surrogate here (a physical key producing a
            // supplementary-plane character directly -- essentially
            // never happens via a real keyboard) returns `false` and
            // leaves `text` empty rather than waiting for its pair the
            // way `charEvent()`'s own standalone path does -- this
            // dispatch already has to happen now, alongside the real
            // keysym, so there's no "wait for the next message" option
            // here the way there is for an IME/emoji-picker burst with
            // no keysym involved at all.
            decodeCharUnit(charMsg.wParam, text);
        }
    }
    // A key-up keeps the key-down's text, matching FLTK: its
    // `WM_KEYUP` path leaves the static `buffer` untouched, so
    // `Fl::e_text` still holds what the press produced.
    if (!isUp)
        fl.core.eText_ = text;

    // Kludge to process the '+'-containing key in a cross-platform way
    // when used with Ctrl -- ported from `Fl_win32.cxx:1675-1713`. On
    // most layouts, holding Ctrl while pressing an OEM/punctuation key
    // (unlike a letter key) makes Windows' own `TranslateMessage()`
    // produce no `WM_CHAR` at all -- there's no defined control-code
    // mapping for punctuation the way there is for Ctrl+A..Ctrl+Z -- so
    // the `PeekMessageW()` lookahead above finds nothing, `eText_` stays
    // empty, and `eKeysym_` is whatever `vkToKeysym()`'s shift-
    // independent mapping gives the physical key regardless of whether
    // Shift is actually held (`'='`, never `'+'`, even when the key was
    // typed *as* `'+'` via Shift). Without this, `fl.core.testShortcut()`
    // can never match `stateCommand | '+'` for Ctrl-`+` on any layout
    // where `'+'` needs Shift (essentially all of them): the exact-
    // keysym path fails since Shift's mismatch disqualifies it, and the
    // eventText()-first-char fallback fails since `eText_` is empty --
    // this is what makes Ctrl-`+`/Ctrl-`-`
    // trigger `fl.core.scaleHandler()`'s live rescale on Windows.
    // Only Ctrl-`-`/Ctrl-`0`
    // happened to keep working on a US layout, since neither of *their*
    // characters needs Shift, so the exact-keysym path never needed this
    // fix for them in the first place -- but any layout where `-` or `0`
    // themselves sit behind Shift would hit the identical failure.
    //
    // `VkKeyScanA('+')` reports which physical key types '+' on the
    // *current* layout, and whether it needs Shift there (`0x100` bit) --
    // covers every layout FLTK's own table comment documents (US/UK/
    // etc: '='/'+' on one key; German/Spanish/Italian/Greek/Portuguese:
    // '+'/'*'; Swedish/Finnish/Norwegian: '+'/'?'; Dutch: '+'/'±'; Swiss/
    // Turkish/Hungarian: a digit key doubles as '+'), so this one check
    // handles all of them rather than hard-coding the US '='/'+' pairing.
    if ((fl.core.eState_ & stateCtrl) != 0 && (GetAsyncKeyState(VK_MENU) & 0x8000) == 0)
    {
        import std.conv : to;

        int vkPlusKey = VkKeyScanA('+') & 0xff;
        bool plusShiftPos = (VkKeyScanA('+') & 0x100) != 0;
        dchar plusOtherChar;
        if (plusShiftPos) plusOtherChar = vkToKeysym(vkPlusKey);
        else if ((VkKeyScanA('*') & 0xff) == vkPlusKey) plusOtherChar = '*';
        else if ((VkKeyScanA('?') & 0xff) == vkPlusKey) plusOtherChar = '?';
        else if ((VkKeyScanW('±') & 0xff) == vkPlusKey) plusOtherChar = '±';
        else plusOtherChar = '=';

        // Upstream tests `keysym == '='` for the first case; this port
        // tests the VK code instead, since `oemKeysym()` now gives
        // `VK_OEM_PLUS` the layout's own character (`'+'` on German,
        // not `'='`), which would otherwise skip the `eText_` rewrite.
        if ((vkPlusKey == 0xbb && cast(int) wParam == 0xbb) || (plusShiftPos && keysym == plusOtherChar))
        {
            keysym = cast(Keysym)(plusShiftPos ? plusOtherChar : '+');
            fl.core.eKeysym_ = keysym;
            bool shiftHeld = (fl.core.eState_ & stateShift) != 0;
            dchar outChar = plusShiftPos
                ? (shiftHeld ? '+' : plusOtherChar)
                : (shiftHeld ? plusOtherChar : '+');
            fl.core.eText_ = [outChar].to!string;
        }
    }

    if (fl.core.dispatch(isUp ? Event.keyUp : Event.keyDown, win) && isDead)
        fl.core.markComposeState(1);
}

/// Module-wide surrogate-pair buffer, shared between `keyEvent()`'s own
/// peek-ahead and `charEvent()`'s standalone-arrival path below --
/// exactly one physical keyboard/message-queue's worth of state to
/// track regardless of which entry point sees the high half, matching
/// FLTK's own single file-scope `static wchar_t surrogate_pair[2]`.
private wchar pendingHighSurrogate_;
private bool haveHighSurrogate_;

/**
 * Decodes one `WM_CHAR`/`WM_SYSCHAR` code unit (`wParam`) into real
 * UTF-8 text, merging a genuine UTF-16 surrogate pair across two calls
 * -- ported from the surrogate-handling half of `Fl_win32.cxx`'s shared
 * `WM_CHAR`/`WM_SYSCHAR` body (`IS_HIGH_SURROGATE(u)`/`surrogate_pair`).
 * Matters for real-world input more than
 * it might look: a lone high/low surrogate almost never comes from a
 * physical key directly, but both the Windows emoji picker (Win+.) and
 * some IMEs post exactly this shape for a supplementary-plane character
 * (many emoji, some rarer CJK extension characters).
 *
 * Returns `false` (nothing to dispatch yet) after consuming a lone high
 * surrogate, matching FLTK's own early `Fl::e_length = 0; return
 * 0;` -- the caller should wait for the next `WM_CHAR`/`WM_SYSCHAR`
 * rather than dispatching an event for this one. A low surrogate
 * arriving with no preceding high one (a malformed stream no real IME
 * should ever produce) degrades to empty text rather than feeding an
 * invalid lone surrogate into `std.utf.toUTF8()`, which would throw.
 */
private bool decodeCharUnit(WPARAM wParam, out string text)
{
    wchar wc = cast(wchar) wParam;
    if (wc >= 0xD800 && wc <= 0xDBFF) // high surrogate
    {
        pendingHighSurrogate_ = wc;
        haveHighSurrogate_ = true;
        return false;
    }
    if (wc >= 0xDC00 && wc <= 0xDFFF) // low surrogate
    {
        if (haveHighSurrogate_)
        {
            wchar[2] pair = [pendingHighSurrogate_, wc];
            text = pair[].toUTF8;
        }
        haveHighSurrogate_ = false;
        return true;
    }
    haveHighSurrogate_ = false; // a lone high surrogate never followed up -- don't let it leak into some later unrelated pair
    wchar[1] one = [wc];
    text = one[].toUTF8;
    return true;
}

/**
 * Handles a `WM_CHAR`/`WM_SYSCHAR`/`WM_DEADCHAR`/`WM_SYSDEADCHAR` that
 * arrived as its *own* top-level message, with no immediately-preceding
 * `WM_KEYDOWN`/`WM_SYSKEYDOWN` this module's own `keyEvent()` already
 * claimed via its `PeekMessageW()` lookahead -- exactly how an input
 * method delivers composed/committed text (each composed character is
 * posted as a standalone `WM_CHAR`, not paired with any keydown of this
 * window's own), and how the Windows emoji picker (Win+.) delivers a
 * picked emoji. Ported from the shared tail of `Fl_win32.cxx`'s combined
 * `WM_KEYDOWN`...`WM_SYSCHAR` case block (`Fl_win32.cxx:1564+`) -- the
 * part that runs regardless of which case in that block was actually
 * matched.
 *
 * This is what lets `WndProc()`'s own top-level `case WM_CHAR: case WM_SYSCHAR:`
 * handle exactly this "arrived with no
 * preceding keydown" case, instead of silently dropping the character --
 * without it, no IME composition commit and no emoji-picker selection
 * would reach
 * this port's widgets at all, regardless of how correct the surrogate-
 * pair/dead-key handling below is. See this module's own top comment.
 *
 * `WM_DEADCHAR`/`WM_SYSDEADCHAR` deliver empty text (matching FLTK's
 * real, shipped behavior exactly -- `Fl_win32.cxx`'s own alternative,
 * which would insert the dead key's own un-composed glyph, is gated
 * behind `FLTK_PREVIEW_DEAD_KEYS`, a macro FLTK itself doesn't
 * define by default) and set `fl.core`'s compose state afterward if the
 * dispatch was handled, matching `Fl::compose_state = 1;` exactly -- see
 * `fl.core.compose()`'s own doc comment for how a text-editing widget
 * consumes this on the *next* keystroke.
 */
private void charEvent(FlWindow win, uint uMsg, WPARAM wParam)
{
    bool isDead = (uMsg == WM_DEADCHAR || uMsg == WM_SYSDEADCHAR);
    string text;
    if (isDead)
    {
        // Matches FLTK's real (non-FLTK_PREVIEW_DEAD_KEYS) body
        // exactly: `buffer[0] = 0; Fl::e_length = 0;`.
    }
    else if (!decodeCharUnit(wParam, text))
    {
        return; // a lone high surrogate -- wait for its pair, no dispatch yet
    }

    fl.core.eText_ = text;
    fl.core.eState_ = keyModifierState() | (fl.core.eState_ & stateButtons);

    if (fl.core.dispatch(Event.keyDown, win) && isDead)
        fl.core.markComposeState(1);
}

/// Whether the right Alt ("AltGr") key is currently held -- used by
/// `fl.core.compose()`'s Windows-specific branch (see that function's
/// own doc comment) to avoid misinterpreting an AltGr-modified character
/// (common on many European keyboard layouts, e.g. AltGr+E for "€") as a
/// function-key combination just because Windows also reports AltGr as
/// Ctrl+Alt held together. Ported from `Fl_WinAPI_Screen_Driver::
/// compose()`'s own `GetAsyncKeyState(VK_RMENU) >> 15` check -- the `&
/// 0x8000` form here tests the same high bit without relying on
/// `SHORT`'s signed-arithmetic-right-shift behavior.
package(fl) bool altGrDown()
{
    return (GetAsyncKeyState(VK_RMENU) & 0x8000) != 0;
}

/**
 * Names a keysym for `fl.core.flShortcutLabel()` ("F1", "Home",
 * "KP_5"), or returns null so the caller uses the uppercased character
 * itself. Ported from the generic `Fl_Screen_Driver::
 * shortcut_add_key_name()` (`src/fl_shortcut.cxx`) and its
 * `default_key_table` (`src/Fl_Screen_Driver.cxx`), which the WinAPI
 * driver uses unchanged. Without it, special keys fell through to the
 * uppercased-character fallback and showed as stray glyphs from the
 * U+FFxx block (F1 is keysym 0xFFBE).
 */
string keyName(uint key)
{
    import std.conv : to;
    import fl.enumerations : pause, scrollLock, print, menu, metaL, metaR, kpLast, fLast;

    if (key > f && key <= fLast)
        return "F" ~ to!string(key - f);

    switch (key)
    {
    case ' ': return "Space";
    case backSpace: return "Backspace";
    case tab: return "Tab";
    case 0xff0b: return "Clear"; // XK_Clear
    case enter: return "Enter";
    case pause: return "Pause";
    case scrollLock: return "Scroll_Lock";
    case escape: return "Escape";
    case home: return "Home";
    case left: return "Left";
    case up: return "Up";
    case right: return "Right";
    case down: return "Down";
    case pageUp: return "Page_Up";
    case pageDown: return "Page_Down";
    case end: return "End";
    case print: return "Print";
    case insert: return "Insert";
    case menu: return "Menu";
    case numLock: return "Num_Lock";
    case kpEnter: return "KP_Enter";
    case shiftL: return "Shift_L";
    case shiftR: return "Shift_R";
    case controlL: return "Control_L";
    case controlR: return "Control_R";
    case capsLock: return "Caps_Lock";
    case metaL: return "Meta_L";
    case metaR: return "Meta_R";
    case altL: return "Alt_L";
    case altR: return "Alt_R";
    case deleteKey: return "Delete";
    default: break;
    }

    if (key >= kp && key <= kpLast) // keypad keys get a KP_ prefix
        return "KP_" ~ cast(char)(key & 127);
    return null;
}

/**
 * Converts a keysym to the VK code `GetKeyState()` needs, or 0 for a
 * keysym with no key -- the direct equivalent of `fltk2ms()`
 * (`src/Fl_get_key_win32.cxx`), the inverse of `vkToKeysym()`.
 *
 * Two deliberate deviations, both following `vkToKeysym()`'s own:
 * a printable character other than a letter or digit is looked up on
 * the active layout with `VkKeyScanW()` (so `'ö'` finds the German `ö`
 * key) instead of FLTK's US-only table, which would map `';'` to the
 * key that types `ö` there; and the media/browser/sleep keys and
 * F13-F24 that `vkToKeysym()` now reports are mapped back too.
 * `kpEnter` and `altGr` stay unmapped as in FLTK: Windows has no
 * separate VK code for them.
 */
private int keysymToVk(Keysym k)
{
    import fl.enumerations : isoKey, pause, scrollLock, print, menu, metaL, metaR, sleep,
        back, forward, refresh, stop, search, favorites, homePage, volumeMute, volumeDown,
        volumeUp, mediaNext, mediaPrev, mediaStop, mediaPlay, mail;

    if (k >= '0' && k <= '9') return k;
    if (k >= 'A' && k <= 'Z') return k;
    if (k >= 'a' && k <= 'z') return k - ('a' - 'A');
    if (k > f && k <= f + 24) return k - (f - (VK_F1 - 1));
    if (k >= kp + '0' && k <= kp + '9') return k - (kp + '0' - VK_NUMPAD0);

    // Printable characters, excluding the private-use range the media
    // keysyms (0xEF11+) live in and the 0xFExx/0xFFxx function keysyms.
    if ((k >= 0x20 && k < 0x7f) || (k >= 0xa0 && k < 0xe000))
    {
        short r = VkKeyScanW(cast(wchar) k);
        return (r & 0xff) == 0xff ? 0 : (r & 0xff);
    }

    switch (k)
    {
    case backSpace: return VK_BACK;
    case tab: return VK_TAB;
    case 0xff0b: return VK_CLEAR; // XK_Clear
    case isoKey: return VK_OEM_102;
    case enter: return VK_RETURN;
    case pause: return VK_PAUSE;
    case scrollLock: return VK_SCROLL;
    case escape: return VK_ESCAPE;
    case home: return VK_HOME;
    case left: return VK_LEFT;
    case up: return VK_UP;
    case right: return VK_RIGHT;
    case down: return VK_DOWN;
    case pageUp: return VK_PRIOR;
    case pageDown: return VK_NEXT;
    case end: return VK_END;
    case print: return VK_SNAPSHOT;
    case insert: return VK_INSERT;
    case menu: return VK_APPS;
    case numLock: return VK_NUMLOCK;
    case kp + '*': return VK_MULTIPLY;
    case kp + '+': return VK_ADD;
    case kp + '-': return VK_SUBTRACT;
    case kp + '.': return VK_DECIMAL;
    case kp + '/': return VK_DIVIDE;
    case shiftL: return VK_LSHIFT;
    case shiftR: return VK_RSHIFT;
    case controlL: return VK_LCONTROL;
    case controlR: return VK_RCONTROL;
    case capsLock: return VK_CAPITAL;
    case metaL: return VK_LWIN;
    case metaR: return VK_RWIN;
    case altL: return VK_LMENU;
    case altR: return VK_RMENU;
    case deleteKey: return VK_DELETE;
    case sleep: return VK_SLEEP;
    case back: return VK_BROWSER_BACK;
    case forward: return VK_BROWSER_FORWARD;
    case refresh: return VK_BROWSER_REFRESH;
    case stop: return VK_BROWSER_STOP;
    case search: return VK_BROWSER_SEARCH;
    case favorites: return VK_BROWSER_FAVORITES;
    case homePage: return VK_BROWSER_HOME;
    case volumeMute: return VK_VOLUME_MUTE;
    case volumeDown: return VK_VOLUME_DOWN;
    case volumeUp: return VK_VOLUME_UP;
    case mediaNext: return VK_MEDIA_NEXT_TRACK;
    case mediaPrev: return VK_MEDIA_PREV_TRACK;
    case mediaStop: return VK_MEDIA_STOP;
    case mediaPlay: return VK_MEDIA_PLAY_PAUSE;
    case mail: return VK_LAUNCH_MAIL;
    default: return 0;
    }
}

/**
 * Whether key `k` was held as of the message being processed -- the
 * direct equivalent of `Fl_WinAPI_Screen_Driver::event_key(int)`
 * (`GetKeyState()`, which tracks the thread's message queue rather
 * than the hardware). Mouse buttons (`button + n`) are answered from
 * `fl.core.eventState()` the way `fl.platform_x11.eventKey()` does;
 * FLTK's Windows version has no mouse-button case and returns 0 for
 * them, a deliberate deviation so both platforms agree.
 */
package(fl) bool eventKey(Keysym k)
{
    if (k > button && k <= button + 8)
        return fl.core.eventState(8 << (k - button)) != 0;
    int vk = keysymToVk(k);
    return vk != 0 && (GetKeyState(vk) & 0x8000) != 0;
}

/// The direct equivalent of `Fl_WinAPI_Screen_Driver::get_key(int)`:
/// the same question as `eventKey()`, answered from a fresh
/// `GetKeyboardState()` snapshot.
package(fl) bool getKey(Keysym k)
{
    if (k > button && k <= button + 8)
        return fl.core.eventState(8 << (k - button)) != 0;
    int vk = keysymToVk(k);
    if (vk == 0) return false;
    ubyte[256] keys;
    if (!GetKeyboardState(keys.ptr)) return false;
    return (keys[vk] & 0x80) != 0;
}

/**
 * Ported from `Fl_WinAPI_Screen_Driver::enable_im()`/`disable_im()` --
 * re-associates (or disassociates) every shown top-level window's own
 * IME input context via `ImmAssociateContextEx()`. A rarely-called
 * escape hatch (per `fl.core.d`'s own doc comment) -- most apps never
 * call `Fl::enable_im()`/`disable_im()` at all, since IME composition
 * already works transparently without it.
 *
 * **Deliberately narrower than FLTK's own `Fl_X::first` walk**:
 * FLTK iterates every `Fl_X` (top-level windows *and* subwindows);
 * this walks `fl.core.firstWindow()`/`nextWindow()` (top-level only,
 * matching `Fl::first_window()`/`next_window()`'s own documented scope)
 * -- a subwindow's own HWND never independently receives OS keyboard
 * focus in this port's architecture (or FLTK's), so its own IME
 * association state is unreachable in practice regardless of which list
 * this walks.
 */
package(fl) void enableIm()
{
    for (auto w = fl.core.firstWindow(); w !is null; w = fl.core.nextWindow(w))
        if (auto hwnd = hwndFor(w))
            ImmAssociateContextEx(hwnd, 0, IACE_DEFAULT); // HIMC (0 = "no explicit context") is `uint` in this druntime, not a pointer type -- a real, if odd, legacy Win32 typedef this binding preserves as-is
}

/// ditto (the disabling half) -- ported from `Fl_WinAPI_Screen_Driver::
/// disable_im()`.
package(fl) void disableIm()
{
    for (auto w = fl.core.firstWindow(); w !is null; w = fl.core.nextWindow(w))
        if (auto hwnd = hwndFor(w))
            ImmAssociateContextEx(hwnd, 0, 0);
}

/**
 * Ported from `Fl_WinAPI_Screen_Driver::set_spot()` -- positions the
 * active input method's "over the spot" composition/candidate window at
 * the given widget-reported caret position, so a CJK (or other
 * composing) input method's floating preedit/candidate UI appears next
 * to the text cursor instead of a fixed default location. Called from
 * `fl.core.setSpot()`, itself called by `fl.text_display`'s
 * `drawCursor()` whenever focused -- the same real call site X11's own
 * `platformX11.setSpot()` already serves (see that function's own doc
 * comment for the shared cross-platform picture).
 *
 * `X`/`Y` are `win`'s own local FLTK-unit coordinates (its bottom-left
 * caret corner, matching FLTK's own `set_spot()` contract exactly);
 * `win` need not be the top-level window itself -- `MapWindowPoints()`
 * converts into the top-level's own client coordinates, matching
 * FLTK's identical `MapWindowPoints(fl_xid(win), fl_xid(tw), ...)`
 * call, needed since the IME composition window is always associated
 * with the top-level HWND's own input context, never a subwindow's.
 *
 * **Deliberately not ported**: FLTK's own "best-effort" font hint
 * (`SelectObject()`ing the current default driver's font into its DC
 * before calling this) -- FLTK's own comment concedes it "does
 * good, but still not always effective," and skipping it doesn't change
 * whether the composition window itself ends up in the right place, the
 * actual point of this function. `fontFace`/`fontSize` are accepted for
 * signature parity with `fl.core.setSpot()`'s own FLTK-matching
 * contract, but otherwise unused here for exactly that reason.
 */
package(fl) void setSpot(int fontFace, int fontSize, int X, int Y, int W, int H, FlWindow win)
{
    if (win is null) return;
    FlWindow top = win.topWindow();
    if (top is null) top = win;
    if (!top.shown()) return;

    auto topHwnd = hwndFor(top);
    auto winHwnd = hwndFor(win);
    if (topHwnd is null || winHwnd is null) return;

    HIMC himc = ImmGetContext(topHwnd); // HIMC is `uint` in this druntime, not a pointer type
    if (himc == 0) return;

    float s = fl.core.screenScale(top.screenNum());
    COMPOSITIONFORM cfs;
    cfs.dwStyle = CFS_POINT;
    cfs.ptCurrentPos.x = cast(int)(X * s);
    cfs.ptCurrentPos.y = cast(int)(Y * s) - cast(int)(top.labelsize() * s);
    MapWindowPoints(winHwnd, topHwnd, &cfs.ptCurrentPos, 1);
    ImmSetCompositionWindow(himc, &cfs);
    ImmReleaseContext(topHwnd, himc);
}

/// The direct equivalent of `ms2fltk()` (`Fl_win32.cxx:1118+`) --
/// OEM punctuation keys follow the active layout (`oemKeysym()`), not
/// FLTK's US table.
///
/// `extended` (lParam bit 24) picks the right-hand keysym the way
/// `ms2fltk()`'s third `vktab` column does: right Ctrl/right Alt
/// (AltGr) are extended keys, and so is the numpad Enter key
/// (`kpEnter`). Right Shift is the exception: Windows never sets the
/// extended bit for it, so `ms2fltk()`'s `{VK_SHIFT, FL_Shift_L,
/// FL_Shift_R}` entry can't reach `FL_Shift_R` (see `FLTK_ISSUES.md`).
/// This port tells the two Shift keys apart by `scanCode` (lParam bits
/// 16-23) instead, which `MAPVK_VSC_TO_VK_EX` resolves to `VK_LSHIFT`/
/// `VK_RSHIFT` -- a deliberate deviation beyond upstream. Callers with
/// no real key message (`keyEvent()`'s Ctrl-`+` lookup) leave both at
/// their defaults and get the left/main-keyboard keysym.
///
/// NumLock/keypad remap is real now (see
/// `numpadOriginalKeysym()`'s own doc comment) -- this function only
/// needs to cover the *live*, NumLock-on numpad case, since Windows
/// itself already reports these VK codes only while NumLock is active
/// (the NumLock-off case reuses the ordinary `VK_HOME`/`VK_UP`/etc.
/// cases just below unchanged -- Windows reports the identical VK code
/// either way, live meaning included).
private Keysym vkToKeysym(int vk, bool extended = false, uint scanCode = 0)
{
    import fl.enumerations : pause, scrollLock, print, metaL, metaR, menu, sleep, back,
        forward, refresh, stop, search, favorites, homePage, volumeMute, volumeDown,
        volumeUp, mediaNext, mediaPrev, mediaStop, mediaPlay, mail;

    switch (vk)
    {
    case VK_BACK: return backSpace;
    case VK_TAB: return tab;
    case VK_RETURN: return extended ? kpEnter : enter;
    case VK_ESCAPE: return escape;
    case VK_PRIOR: return pageUp;
    case VK_NEXT: return pageDown;
    case VK_END: return end;
    case VK_HOME: return home;
    case VK_LEFT: return left;
    case VK_UP: return up;
    case VK_RIGHT: return right;
    case VK_DOWN: return down;
    case VK_INSERT: return insert;
    case VK_DELETE: return deleteKey;
    case VK_CLEAR: return cast(Keysym) 0xff0b; // XK_Clear -- numpad-5 with NumLock off (KP_Begin), matching fl.platform_x11's identical kpFunctionTable entry
    case VK_SHIFT:
        return scanCode != 0 && MapVirtualKeyW(scanCode, MAPVK_VSC_TO_VK_EX) == VK_RSHIFT
            ? shiftR : shiftL;
    case VK_CONTROL: return extended ? controlR : controlL;
    case VK_MENU: return extended ? altR : altL;
    case VK_CAPITAL: return capsLock;
    case VK_NUMLOCK: return numLock;

    // The rest of `vktab`'s named keys. Without these, the fallthrough
    // below returned the raw VK code, which for several of them is a
    // printable character (`VK_LWIN` 0x5B came out as `'['`,
    // `VK_SNAPSHOT` 0x2C as `','`). Local import: several of these
    // names (`print`, `menu`, `stop`, `search`, ...) are too generic
    // to bring into module scope.
    case VK_PAUSE: return pause;
    case VK_SCROLL: return scrollLock;
    case VK_SNAPSHOT: return print;
    case VK_LWIN: return metaL;
    case VK_RWIN: return metaR;
    case VK_APPS: return menu;
    case VK_SLEEP: return sleep;
    case VK_BROWSER_BACK: return back;
    case VK_BROWSER_FORWARD: return forward;
    case VK_BROWSER_REFRESH: return refresh;
    case VK_BROWSER_STOP: return stop;
    case VK_BROWSER_SEARCH: return search;
    case VK_BROWSER_FAVORITES: return favorites;
    case VK_BROWSER_HOME: return homePage;
    case VK_VOLUME_MUTE: return volumeMute;
    case VK_VOLUME_DOWN: return volumeDown;
    case VK_VOLUME_UP: return volumeUp;
    case VK_MEDIA_NEXT_TRACK: return mediaNext;
    case VK_MEDIA_PREV_TRACK: return mediaPrev;
    case VK_MEDIA_STOP: return mediaStop;
    case VK_MEDIA_PLAY_PAUSE: return mediaPlay;
    case VK_LAUNCH_MAIL: return mail;

    // Numpad digit/operator keys -- Windows only ever reports these VK
    // codes while NumLock is ON (with it off, the *same* physical keys
    // report as VK_HOME/VK_UP/etc. instead, already handled above).
    // FLTK's own convention (matching `fl.platform_x11`'s identical
    // `keysym1 | kp` -- see that module's NumLock/keypad remap comment)
    // represents a numpad digit press as `kp + '0'..'9'`/`kp +
    // <operator char>`, never a bare ASCII digit -- `myHandler()`-style
    // remapping code (`source/examples/howto_remap_numpad_keyboard_
    // keys.d`) depends on this exact convention to recognize a numpad
    // key at all via `fl.eventOriginalKey()`.
    case VK_NUMPAD0: return cast(Keysym)(kp + '0');
    case VK_NUMPAD1: return cast(Keysym)(kp + '1');
    case VK_NUMPAD2: return cast(Keysym)(kp + '2');
    case VK_NUMPAD3: return cast(Keysym)(kp + '3');
    case VK_NUMPAD4: return cast(Keysym)(kp + '4');
    case VK_NUMPAD5: return cast(Keysym)(kp + '5');
    case VK_NUMPAD6: return cast(Keysym)(kp + '6');
    case VK_NUMPAD7: return cast(Keysym)(kp + '7');
    case VK_NUMPAD8: return cast(Keysym)(kp + '8');
    case VK_NUMPAD9: return cast(Keysym)(kp + '9');
    case VK_DECIMAL: return cast(Keysym)(kp + '.');
    case VK_ADD: return cast(Keysym)(kp + '+');
    case VK_SUBTRACT: return cast(Keysym)(kp + '-');
    case VK_MULTIPLY: return cast(Keysym)(kp + '*');
    case VK_DIVIDE: return cast(Keysym)(kp + '/');

    // OEM punctuation keys: resolved through the active layout, see
    // `oemKeysym()`.
    case VK_OEM_1: case VK_OEM_PLUS: case VK_OEM_COMMA: case VK_OEM_MINUS:
    case VK_OEM_PERIOD: case VK_OEM_2: case VK_OEM_3: case VK_OEM_4:
    case VK_OEM_5: case VK_OEM_6: case VK_OEM_7: case VK_OEM_8: case VK_OEM_102:
        return oemKeysym(vk);

    default: break;
    }
    if (vk >= VK_F1 && vk <= VK_F24) return cast(Keysym)(f + (vk - VK_F1 + 1));
    if (vk >= 'A' && vk <= 'Z') return cast(Keysym)(vk + 0x20); // lowercase, matching FLTK's convention
    return cast(Keysym) vk; // digits: VK_0..VK_9 really do equal ASCII '0'..'9' (a genuine identity, unlike the OEM keys above)
}

/**
 * The keysym for an OEM punctuation key: the character the key types
 * unshifted on the active keyboard layout, lowercased, so the key that
 * types `ö` on a German layout reports `'ö'` (0xF6) rather than `';'`.
 * Dead keys (German `´` and `^`) report their spacing character.
 *
 * Deliberate deviation beyond FLTK, whose `ms2fltk()` hardcodes the US
 * characters for these VK codes (`vktab`'s `{0xba, ';'}, {0xbb, '='},
 * ...`), so on any other layout `Fl::event_key()` names the key by its
 * US label. This matches `fl.platform_x11` instead, where the keysym is
 * already the layout's own unshifted symbol.
 *
 * A table of some kind is needed for these codes either way: unlike
 * `VK_0`..`VK_9`, they aren't ASCII (`VK_OEM_MINUS` is 0xBD, not
 * `'-'`), and Windows sends no `WM_CHAR` for Ctrl+punctuation, so
 * `testShortcut()` has only the keysym to match Ctrl-`-` against.
 * `VK_OEM_PLUS`/`_MINUS`/`_COMMA`/`_PERIOD` name the `+`/`-`/`,`/`.`
 * key on every layout, so those four resolve to the same character as
 * before on US-style layouts; on German, `VK_OEM_PLUS` now reports `'+'`
 * (that key's unshifted character) instead of `'='`.
 *
 * `MapVirtualKeyW()` reads the calling thread's current layout, so a
 * layout switch (Win+Space) takes effect on the next key press. The US
 * table remains as a fallback for a key the layout leaves unmapped;
 * `VK_OEM_102` (the extra key left of Z on ISO keyboards) falls back to
 * `isoKey`, as in FLTK.
 */
private Keysym oemKeysym(int vk)
{
    import std.uni : toLower;
    import fl.enumerations : isoKey;

    // The low word is the character; the dead-key flag lives in the
    // top bit, which this mask drops.
    uint c = MapVirtualKeyW(vk, MAPVK_VK_TO_CHAR) & 0xffff;
    if (c != 0 && (c < 0xd800 || c > 0xdfff))
        return cast(Keysym) toLower(cast(dchar) c);

    switch (vk)
    {
    case VK_OEM_1: return cast(Keysym) ';';
    case VK_OEM_PLUS: return cast(Keysym) '=';
    case VK_OEM_COMMA: return cast(Keysym) ',';
    case VK_OEM_MINUS: return cast(Keysym) '-';
    case VK_OEM_PERIOD: return cast(Keysym) '.';
    case VK_OEM_2: return cast(Keysym) '/';
    case VK_OEM_3: return cast(Keysym) '`';
    case VK_OEM_4: return cast(Keysym) '[';
    case VK_OEM_5: return cast(Keysym) '\\';
    case VK_OEM_6: return cast(Keysym) ']';
    case VK_OEM_7: return cast(Keysym) '\'';
    case VK_OEM_102: return isoKey;
    default: return cast(Keysym) vk;
    }
}

/**
 * Returns the NumLock-independent "kp + digit/operator" identity for a
 * physical numpad key, or `cast(Keysym) 0` if `vk` (with `extended`,
 * lParam bit 24) doesn't come from the numpad at all -- `keyEvent()`'s
 * own doc comment explains how this feeds `eOriginalKeysym_`.
 *
 * Mirrors `fl.platform_x11`'s own `eOriginalKeysym_` computation (see
 * that module's NumLock/keypad remap comment) but reaches it a
 * different way: X11 fetches *two* keysyms per keycode up front
 * (`XKeycodeToKeysym(..., 0)` and `..., 1)`, the "NumLock off"/"NumLock
 * on" meanings) and picks between them with the live `Mod2Mask` bit.
 * Windows gives no such pair -- the OS itself already resolves `wParam`
 * to whichever meaning is live, the same way it resolves `vkToKeysym()`'s
 * own live keysym -- so this function instead has to *reconstruct* the
 * other meaning: for the unambiguous `VK_NUMPAD0`..`VK_DIVIDE` codes
 * (only ever reported with NumLock on) the "original" identity is just
 * `vkToKeysym()`'s own live result; for the ambiguous
 * `VK_HOME`/`VK_UP`/.../`VK_DELETE` codes (NumLock *off* numpad digits
 * reuse literally the same VK codes as the *dedicated* Home/End/arrow/
 * Insert/Delete cluster) the `extended`-key bit is what disambiguates:
 * Windows always reports the dedicated cluster's keys as "extended"
 * (lParam bit 24 set) and the numpad's own NumLock-off digits as *not*
 * extended -- a standard, documented Win32 technique, not guessed.
 * (`VK_DIVIDE` is the one numpad key Windows always reports as
 * "extended" regardless -- irrelevant here since it's already handled,
 * unambiguously, by the first switch below.)
 */
private Keysym numpadOriginalKeysym(int vk, bool extended)
{
    switch (vk)
    {
    case VK_NUMPAD0: return cast(Keysym)(kp + '0');
    case VK_NUMPAD1: return cast(Keysym)(kp + '1');
    case VK_NUMPAD2: return cast(Keysym)(kp + '2');
    case VK_NUMPAD3: return cast(Keysym)(kp + '3');
    case VK_NUMPAD4: return cast(Keysym)(kp + '4');
    case VK_NUMPAD5: return cast(Keysym)(kp + '5');
    case VK_NUMPAD6: return cast(Keysym)(kp + '6');
    case VK_NUMPAD7: return cast(Keysym)(kp + '7');
    case VK_NUMPAD8: return cast(Keysym)(kp + '8');
    case VK_NUMPAD9: return cast(Keysym)(kp + '9');
    case VK_DECIMAL: return cast(Keysym)(kp + '.');
    case VK_ADD: return cast(Keysym)(kp + '+');
    case VK_SUBTRACT: return cast(Keysym)(kp + '-');
    case VK_MULTIPLY: return cast(Keysym)(kp + '*');
    case VK_DIVIDE: return cast(Keysym)(kp + '/');
    default: break;
    }

    if (!extended)
    {
        switch (vk)
        {
        case VK_INSERT: return cast(Keysym)(kp + '0');
        case VK_END: return cast(Keysym)(kp + '1');
        case VK_DOWN: return cast(Keysym)(kp + '2');
        case VK_NEXT: return cast(Keysym)(kp + '3');
        case VK_LEFT: return cast(Keysym)(kp + '4');
        case VK_CLEAR: return cast(Keysym)(kp + '5');
        case VK_RIGHT: return cast(Keysym)(kp + '6');
        case VK_HOME: return cast(Keysym)(kp + '7');
        case VK_UP: return cast(Keysym)(kp + '8');
        case VK_PRIOR: return cast(Keysym)(kp + '9');
        case VK_DELETE: return cast(Keysym)(kp + '.');
        default: break;
        }
    }
    return cast(Keysym) 0;
}

// ---------------------------------------------------------------------
// Clipboard -- ported from `Fl_WinAPI_Screen_Driver::copy()`/`paste()`/
// `clipboard_contains()` and the file-scope `fl_update_clipboard()`/
// `Lf2CrlfConvert` (`Fl_win32.cxx`).
//
// No delayed rendering via `WM_RENDERFORMAT` is involved: `fl_update_clipboard()`
// renders eagerly, synchronously, right inside `copy()` itself
// (`OpenClipboard()`/`EmptyClipboard()`/`SetClipboardData()`, done);
// `paste()` is equally synchronous the other way (`OpenClipboard()`/
// `GetClipboardData()` returns the data immediately, no message-driven
// round trip at all). `WM_RENDERFORMAT` is a real, separate Win32
// mechanism (deferred rendering for a *different* clipboard owner
// pattern) that FLTK's own Windows driver simply never uses -- the
// roadmap's mention of it was a guess made before reading this file,
// not something ported here. Consequently `paste()`'s Windows path
// below doesn't need `pendingPasteReceiver_`'s asynchronous machinery
// the way X11's `SelectionNotify`-driven reply does -- it calls
// `deliverPaste()`/`deliverPasteImage()` immediately, synchronously,
// right after this module hands back the data (see `fl.core.paste()`'s
// own Windows branch).
// ---------------------------------------------------------------------

/// Ported from `Fl_WinAPI_Screen_Driver::copy()`'s own tail (`if
/// (clipboard) fl_update_clipboard();`) -- Windows has no real PRIMARY
/// selection, so `clipboard == 0` is a pure no-op here (the text stays
/// in `fl.core`'s own local buffer only, matching FLTK exactly).
package(fl) void setSelectionOwner(int clipboard)
{
    if (!clipboard) return;
    updateClipboard();
}

/// Ported from the file-scope `fl_update_clipboard()` (`Fl_win32.cxx`):
/// opens the clipboard against the first shown top-level window's own
/// `HWND` (matching FLTK's `fl_xid(Fl::first_window())` -- a no-op
/// if there is none yet, matching FLTK's own `if (!w1) return;`),
/// claims it, and pushes `fl.core`'s own CLIPBOARD-slot text in as real
/// `CF_UNICODETEXT`. `lfToCrlf()` is `Lf2CrlfConvert` ported (old
/// Windows text consumers like Notepad expect `\r\n`).
private void updateClipboard()
{
    auto win = fl.core.firstWindow();
    if (win is null) return;
    auto hwnd = hwndFor(win);
    if (hwnd is null) return;

    if (!OpenClipboard(hwnd)) return;
    EmptyClipboard();

    wstring wtext = lfToCrlf(fl.core.clipboardContents(1)).toUTF16;
    HGLOBAL hMem = GlobalAlloc(GHND, (wtext.length + 1) * wchar.sizeof);
    if (hMem !is null)
    {
        auto mem = cast(wchar*) GlobalLock(hMem);
        if (mem !is null)
        {
            mem[0 .. wtext.length] = wtext[];
            mem[wtext.length] = 0;
            GlobalUnlock(hMem);
            SetClipboardData(CF_UNICODETEXT, hMem);
        }
    }

    CloseClipboard();

    // In case Windows managed to lob off a WM_DESTROYCLIPBOARD during
    // the above (matching FLTK's own identically-worded comment).
    fl.core.markSelectionOwned(1);
}

/// Ported from `Fl_WinAPI_Screen_Driver::paste()`'s plain-text branch
/// (the `else if (clipboard)` half that actually opens the real OS
/// clipboard -- the `!clipboard`/already-owned fast paths are handled
/// entirely in `fl.core.paste()` before this is ever called). Returns
/// `null` if the clipboard couldn't be opened or holds no
/// `CF_UNICODETEXT` at all, matching FLTK's own silent-no-dispatch
/// behavior in both cases.
package(fl) string pasteText()
{
    if (!OpenClipboard(null)) return null;
    scope (exit) CloseClipboard();

    HANDLE h = GetClipboardData(CF_UNICODETEXT);
    if (h is null) return null;

    auto mem = cast(const(wchar)*) GlobalLock(h);
    if (mem is null) return null;
    scope (exit) GlobalUnlock(h);

    size_t len = 0;
    while (mem[len] != 0) len++;
    return crlfToLf(mem[0 .. len].toUTF8);
}

/// Ported from `Fl_WinAPI_Screen_Driver::paste()`'s image branch --
/// Covers all three of FLTK's own decode paths now: the "direct use
/// of the DIB data" fast path (`CF_DIB`, 24/32bpp, `BI_RGB` or standard-
/// mask `BI_BITFIELDS`, no color table -- the common case for anything a
/// modern app puts on the clipboard), the "complex DIB" fallback (a
/// palette-indexed or non-standard-mask/compressed `CF_DIB`, decoded by
/// `decodeComplexDib()`), and the `CF_ENHMETAFILE` fallback (an enhanced-
/// metafile clipboard entry, decoded by `decodeEnhMetaFileClip()`).
///
/// The latter two are real ports, not new designs, backed by
/// `fl.image_surface.ImageSurface`'s Windows offscreen-surface/GDI-image-
/// rendering capability.
///
/// `screenNum` is the receiving widget's own screen (`fl.core.paste()`
/// passes `receiver.topWindow().screenNum()`, `0` if there's no window
/// yet) -- only `decodeEnhMetaFileClip()` needs it, to convert the
/// metafile's `.01mm` logical units to FLTK units at the right GUI
/// scale. See that function's own doc comment for the one FLTK step
/// deliberately not ported (priming the *default* driver's own scale
/// when no window exists yet -- unneeded here, since this port's
/// `fl.core.screenScale(int)` is already a single ambient value every
/// `GdiGraphicsDriver` primitive reads directly, not a per-driver field
/// FLTK has to separately prime).
///
/// **`BI_BITFIELDS` is accepted**, not just `BI_RGB`:
/// `fl.widget_surface.CopySurface`'s Windows support (`SetClipboard
/// Data(CF_BITMAP, ...)`) matters here since Windows' own on-demand
/// `CF_BITMAP` -> `CF_DIB`
/// synthesis for a 32bpp source bitmap produces `BI_BITFIELDS`, not
/// `BI_RGB` -- rejecting any `biCompression != BI_RGB` outright would
/// silently reject every such paste.
/// `BI_BITFIELDS` isn't a single format -- three `DWORD`
/// masks immediately follow the header (reusing `bmiColors`' storage,
/// same as a color table would for a paletted image) naming which bits
/// hold red/green/blue -- so the direct fast path only accepts the
/// *standard*, by far most common 32bpp layout (`0x00ff0000`/
/// `0x0000ff00`/`0x000000ff`, matching plain `BI_RGB`'s own implicit
/// byte order exactly), falling back to `decodeComplexDib()` for
/// anything else rather than guessing.
package(fl) Object pasteImage(int screenNum = 0)
{
    if (!OpenClipboard(null)) return null;
    scope (exit) CloseClipboard();

    HANDLE h = GetClipboardData(CF_DIB);
    if (h !is null)
    {
        auto bi = cast(BITMAPINFO*) GlobalLock(h);
        if (bi is null) return null;
        scope (exit) GlobalUnlock(h);

        int width = bi.bmiHeader.biWidth;
        int height = bi.bmiHeader.biHeight; // negative -> already top-down
        int bitCount = bi.bmiHeader.biBitCount;
        uint compression = bi.bmiHeader.biCompression;

        bool direct = width > 0 && height != 0 && (bitCount == 24 || bitCount == 32)
            && bi.bmiHeader.biClrUsed == 0
            && (compression == BI_RGB || compression == BI_BITFIELDS);

        auto pixelsBase = cast(const(ubyte)*)&bi.bmiColors;
        if (direct && compression == BI_BITFIELDS)
        {
            if (bitCount != 32) direct = false; // BI_BITFIELDS at 24bpp isn't a real DIB shape
            else
            {
                auto masks = cast(const(uint)*) pixelsBase;
                if (masks[0] != 0x00ff0000 || masks[1] != 0x0000ff00 || masks[2] != 0x000000ff)
                    direct = false; // non-standard channel layout -- don't guess
                else
                    pixelsBase += 3 * uint.sizeof; // the 3 DWORD masks sit where a color table would
            }
        }

        if (!direct) return decodeComplexDib(bi, width, height);

        int depth = bitCount / 8;
        int absHeight = height > 0 ? height : -height;
        int linewidth = depth == 3 ? 4 * ((3 * width + 3) / 4) : 4 * width;

        auto rgb = new ubyte[width * absHeight * depth];
        size_t p = 0;
        int step = height > 0 ? -1 : 1;
        int from = height > 0 ? height - 1 : 0;
        int to = height > 0 ? 0 : -height - 1;
        for (int i = from; height > 0 ? i >= to : i <= to; i += step)
        {
            auto r = pixelsBase + i * linewidth;
            foreach (col; 0 .. width)
            {
                ubyte bb = r[0], gg = r[1], rr = r[2];
                r += 3;
                rgb[p++] = rr;
                rgb[p++] = gg;
                rgb[p++] = bb;
                if (depth == 4) { rgb[p++] = *r; r++; }
            }
        }

        return new RGBImage(rgb, width, absHeight, depth);
    }

    HANDLE hEmf = GetClipboardData(CF_ENHMETAFILE);
    if (hEmf !is null) return decodeEnhMetaFileClip(cast(HENHMETAFILE) hEmf, screenNum);

    return null;
}

/**
 * Ported from `Fl_WinAPI_Screen_Driver::paste()`'s "the system will
 * decode a complex DIB" branch -- a paletted, non-standard-mask, or
 * compressed `CF_DIB` that `pasteImage()`'s own direct fast path can't
 * decode by hand. Hands the raw DIB bits to Windows itself
 * (`SetDIBitsToDevice()`, which already knows how to expand any palette/
 * compression) onto a real offscreen `ImageSurface`, then reads the
 * result back as a plain RGB image.
 *
 * `pDibBits`'s default offset (`bmiColors + 256`) assumes a worst-case
 * full 256-entry color table whenever neither of the two narrower cases
 * below applies -- matches FLTK's own formula exactly (even though
 * it over-skips for, say, a real 4bpp DIB with only 16 palette entries);
 * ported as a straight, faithful transliteration of a real FLTK
 * computation, not independently re-derived or "fixed".
 */
private Object decodeComplexDib(BITMAPINFO* bi, int width, int height)
{
    int absHeight = height > 0 ? height : -height;
    auto colors = bi.bmiColors.ptr;
    auto pDibBits = cast(const(void)*)(colors + 256);
    if (bi.bmiHeader.biCompression == BI_BITFIELDS)
        pDibBits = cast(const(void)*)(colors + 3);
    else if (bi.bmiHeader.biClrUsed > 0)
        pDibBits = cast(const(void)*)(colors + bi.bmiHeader.biClrUsed);

    auto surf = new ImageSurface(width, absHeight);
    SurfaceDevice.pushCurrent(surf);
    SetDIBitsToDevice(plainGraphicsDriver().hdc(), 0, 0, cast(DWORD) width,
        cast(DWORD) absHeight, 0, 0, 0, cast(UINT) absHeight, pDibBits, bi, DIB_RGB_COLORS);
    auto img = surf.image();
    SurfaceDevice.popCurrent();
    destroy(surf);
    return img;
}

/**
 * Ported from `Fl_WinAPI_Screen_Driver::paste()`'s `CF_ENHMETAFILE`
 * branch -- rasterizes the metafile via `PlayEnhMetaFile()` onto a
 * white-filled, `highRes`-scaled `ImageSurface`. `GetDeviceCaps(HORZSIZE/
 * HORZRES)` gives the screen's real physical-mm-per-device-pixel ratio,
 * which combined with the receiver's own GUI scale (`fl.core.
 * screenScale(screenNum)`) converts the metafile's `.01mm` logical frame
 * size into FLTK units -- matching FLTK's own conversion exactly.
 *
 * **Deliberately not ported**: FLTK's own `if (!Fl_Window::current())
 * d->scale(scaling);`, which primes the *default* graphics driver's own
 * scale field before any window exists. That exists only because
 * FLTK's `Fl_WinAPI_Screen_Driver` keeps scale as a genuine per-
 * driver/per-screen value (`scale_of_screen[]`) that has to be
 * separately pushed onto whichever driver instance is about to draw;
 * this port's `fl.core.screenScale(int)` is already a single ambient
 * value `GdiGraphicsDriver`'s primitives (`fl_rectf()` included, called
 * below) read directly regardless of which instance is active, so
 * there's nothing to prime.
 */
private Object decodeEnhMetaFileClip(HENHMETAFILE hEmf, int screenNum)
{
    ENHMETAHEADER header;
    GetEnhMetaFileHeader(hEmf, header.sizeof, &header);
    int width = header.rclFrame.right - header.rclFrame.left + 1;
    int height = header.rclFrame.bottom - header.rclFrame.top + 1;

    HDC screenDc = GetDC(null);
    int hmm = GetDeviceCaps(screenDc, HORZSIZE);
    int hdots = GetDeviceCaps(screenDc, HORZRES);
    ReleaseDC(null, screenDc);
    float factor = (100.0f * hmm) / hdots;
    float scaling = fl.core.screenScale(screenNum);

    width = cast(int)(width / (scaling * factor));
    height = cast(int)(height / (scaling * factor));
    if (width <= 0 || height <= 0) return null; // degenerate scale/DPI reading -- don't guess

    auto surf = new ImageSurface(width, height, 1); // highRes -- device-pixel-dense buffer
    SurfaceDevice.pushCurrent(surf);
    fl_color(white);
    fl_rectf(0, 0, width, height);
    RECT rect = RECT(0, 0, cast(LONG)(width * scaling), cast(LONG)(height * scaling));
    PlayEnhMetaFile(plainGraphicsDriver().hdc(), hEmf, &rect);
    auto img = surf.image();
    SurfaceDevice.popCurrent();
    destroy(surf);
    return img;
}

/// Ported from `Fl_WinAPI_Screen_Driver::clipboard_contains()` --
/// checks both `CF_DIB` and `CF_ENHMETAFILE`, matching FLTK exactly
/// (see `pasteImage()`'s own doc comment for its `CF_ENHMETAFILE`
/// fallback).
package(fl) bool clipboardContains(string type)
{
    if (!OpenClipboard(null)) return false;
    scope (exit) CloseClipboard();

    if (type == fl.core.clipboardPlainText || type.length == 0)
        return IsClipboardFormatAvailable(CF_UNICODETEXT) != 0;
    if (type == fl.core.clipboardImage)
        return IsClipboardFormatAvailable(CF_DIB) != 0
            || IsClipboardFormatAvailable(CF_ENHMETAFILE) != 0;
    return false;
}

// ---------------------------------------------------------------------
// Clipboard-change notification -- ported from `Fl_win32.cxx`'s own
// `fl_clipboard_notify_target()`/`fl_clipboard_notify_untarget()`/
// `fl_clipboard_notify_retarget()` and `Fl_WinAPI_Screen_Driver::
// clipboard_notify_change()`, plus the `WM_CHANGECBCHAIN`/
// `WM_DRAWCLIPBOARD` cases in `WndProc()`.
//
// This is the classic clipboard-viewer-chain mechanism (`SetClipboard
// Viewer()`/`WM_DRAWCLIPBOARD`/`ChangeClipboardChain()`), matching
// FLTK exactly -- not the newer `AddClipboardFormatListener()`/
// `WM_CLIPBOARDUPDATE` API, since FLTK itself doesn't use that
// either. Real, event-driven notification, not polling: a registered
// handler only ever fires in reaction to a real `WM_DRAWCLIPBOARD`
// Windows sends us, the same event-driven shape as `fl.platform_x11`'s
// own Xfixes tier (`clipboardNotifyChange()`'s doc comment there).
// ---------------------------------------------------------------------

private HWND clipboardWnd_;
private HWND nextClipboardWnd_;
private bool initialClipboard_ = true;

/// Ported from `fl_clipboard_notify_target()`.
private void clipboardNotifyTarget(HWND wnd)
{
    if (clipboardWnd_ !is null) return;

    // We get one fake WM_DRAWCLIPBOARD immediately, which we therefore
    // need to ignore.
    initialClipboard_ = true;

    clipboardWnd_ = wnd;
    nextClipboardWnd_ = SetClipboardViewer(wnd);
}

/// Ported from `fl_clipboard_notify_untarget()`.
private void clipboardNotifyUntarget(HWND wnd)
{
    if (wnd != clipboardWnd_) return;

    // We might be called late in the cleanup where Windows has already
    // implicitly destroyed our clipboard window. At that point we need
    // to do some extra work to manually repair the clipboard chain.
    if (IsWindow(wnd))
        ChangeClipboardChain(wnd, nextClipboardWnd_);
    else
    {
        immutable(wchar)[] staticClassW = "STATIC\0"w;
        immutable(wchar)[] tmpTitleW = "Temporary FLDTK Clipboard Window\0"w;
        HWND tmp = CreateWindowExW(0, staticClassW.ptr, tmpTitleW.ptr, 0, 0, 0, 0, 0,
            HWND_MESSAGE, null, null, null);
        if (tmp is null) return;

        HWND head = SetClipboardViewer(tmp);
        if (head is null)
            ChangeClipboardChain(tmp, nextClipboardWnd_);
        else
        {
            SendMessageW(head, WM_CHANGECBCHAIN, cast(WPARAM) wnd, cast(LPARAM) nextClipboardWnd_);
            ChangeClipboardChain(tmp, head);
        }

        DestroyWindow(tmp);
    }

    clipboardWnd_ = null;
    nextClipboardWnd_ = null;
}

/// Ported from `fl_clipboard_notify_retarget()` -- called by
/// `destroyWindow()` when the window that currently anchors the
/// clipboard-viewer chain is about to be destroyed, so a still-live
/// window can take over rather than leaving the chain broken.
package(fl) void clipboardNotifyRetarget(HWND wnd)
{
    if (wnd != clipboardWnd_) return;

    clipboardNotifyUntarget(wnd);

    if (auto win = fl.core.firstWindow())
        if (auto hwnd = hwndFor(win))
            clipboardNotifyTarget(hwnd);
}

/// package(fl): called by `fl.core.addClipboardNotify()`/
/// `removeClipboardNotify()` whenever the registered-handler list
/// transitions empty <-> non-empty. Ported from `Fl_WinAPI_Screen_
/// Driver::clipboard_notify_change()`.
package(fl) void clipboardNotifyChange()
{
    // untarget clipboard monitor if no handlers are registered
    if (clipboardWnd_ !is null && fl.core.clipboardNotifyEmpty())
    {
        clipboardNotifyUntarget(clipboardWnd_);
        return;
    }

    // if there are clipboard notify handlers but no window targeted,
    // target the first shown window if available
    if (clipboardWnd_ is null)
        if (auto win = fl.core.firstWindow())
            if (auto hwnd = hwndFor(win))
                clipboardNotifyTarget(hwnd);
}

/// Ported from `Lf2CrlfConvert` (`Fl_win32.cxx`): leaves an existing
/// `"\r\n"` pair untouched, inserts a `\r` before a lone `\n` --
/// two-pass (measure then fill), same shape as FLTK's own
/// constructor, rather than FLTK's raw pointer walk.
private string lfToCrlf(string s)
{
    size_t outlen = 0;
    size_t i = 0;
    while (i < s.length)
    {
        if (s[i] == '\r' && i + 1 < s.length && s[i + 1] == '\n') { i += 2; outlen += 2; }
        else if (s[i] == '\n') { i++; outlen += 2; }
        else { i++; outlen++; }
    }
    if (outlen == s.length) return s;

    auto result = new char[outlen];
    size_t o = 0;
    i = 0;
    while (i < s.length)
    {
        if (s[i] == '\r' && i + 1 < s.length && s[i + 1] == '\n') { result[o++] = s[i++]; result[o++] = s[i++]; }
        else if (s[i] == '\n') { result[o++] = '\r'; result[o++] = s[i++]; }
        else result[o++] = s[i++];
    }
    return cast(string) result;
}

/// The inverse of `lfToCrlf()` -- ported from `paste()`'s own inline
/// `\r\n` -> `\n` strip (`while (*a) { if (*a=='\r' && a[1]=='\n') a++;
/// else *b++=*a++; }`): drops a `\r` immediately followed by `\n`,
/// copies everything else through unchanged.
private string crlfToLf(string s)
{
    if (s.length == 0) return s;
    auto result = new char[s.length];
    size_t o = 0;
    size_t i = 0;
    while (i < s.length)
    {
        if (s[i] == '\r' && i + 1 < s.length && s[i + 1] == '\n') { i++; continue; }
        result[o++] = s[i++];
    }
    return cast(string) result[0 .. o];
}

// ---------------------------------------------------------------------
// Window state -- fullscreen/maximize/iconize, WM_GETMINMAXINFO size-
// range enforcement, and window icons (WM_SETICON). Ported from
// `Fl_WinAPI_Window_Driver::fullscreen_on()`/`fullscreen_off()`/`make_
// fullscreen()`/`maximize()`/`un_maximize()`/`iconize()`/`set_minmax()`/
// `icons()`/`set_icons()` and the file-scope `find_best_icon()`
// (`Fl_win32.cxx`).
// ---------------------------------------------------------------------

/**
 * Real fullscreen -- ported from `Fl_WinAPI_Window_Driver::
 * fullscreen_on()`. Backs `fl.window.Window.fullscreen()`'s Windows
 * branch.
 */
package(fl) void fullscreenOn(FlWindow win)
{
    win.setFullscreenFlag();
    makeFullscreen(win);
    fl.core.dispatch(Event.fullscreen, win);
}

/**
 * Ported from `Fl_WinAPI_Window_Driver::make_fullscreen(int,int,int,
 * int)`: strips `WS_THICKFRAME|WS_CAPTION` (no resize border, no title
 * bar) and moves/resizes the real `HWND` to span the target monitor
 * range (`win.fullscreenScreenTop()`/`Bottom()`/`Left()`/`Right()`,
 * defaulting to the window's own current screen when unset, matching
 * `fl.platform_x11.fullscreenOn()`'s identical fallback). **FLTK's
 * own 4 `int` parameters are plain by-value scratch locals it
 * immediately overwrites with this same monitor-spanning rectangle
 * before ever reading their initial values** -- confirmed by reading
 * `make_fullscreen()`'s body line by line, not assumed -- so this port
 * skips taking them as parameters at all and just uses local scratch
 * variables directly; behaviorally identical either way.
 */
private void makeFullscreen(FlWindow win)
{
    auto hwnd = hwndFor(win);
    if (hwnd is null) return;

    int top = win.fullscreenScreenTop();
    int bottom = win.fullscreenScreenBottom();
    int left = win.fullscreenScreenLeft();
    int right = win.fullscreenScreenRight();
    if (top < 0 || bottom < 0 || left < 0 || right < 0)
        top = bottom = left = right = win.screenNum();

    int X, Y, W, H, sx, sy, sw, sh;
    screenXYWHUnscaled(sx, Y, sw, sh, top);
    screenXYWHUnscaled(sx, sy, sw, sh, bottom);
    H = sy + sh - Y;
    screenXYWHUnscaled(X, sy, sw, sh, left);
    screenXYWHUnscaled(sx, sy, sw, sh, right);
    W = sx + sw - X;

    uint style = cast(uint) GetWindowLong(hwnd, GWL_STYLE);
    style &= ~(WS_THICKFRAME | WS_CAPTION);
    SetWindowLong(hwnd, GWL_STYLE, cast(int) style);

    // SWP_NOSENDCHANGING so a size-range constraint can't override this.
    SetWindowPos(hwnd, HWND_TOP, X, Y, W, H, SWP_NOSENDCHANGING | SWP_FRAMECHANGED);
}

/**
 * Ported from `Fl_WinAPI_Window_Driver::fullscreen_off(int,int,int,
 * int)` -- unlike the Linux/EWMH side (where clearing `_NET_WM_STATE_
 * FULLSCREEN` is enough for a cooperating window manager to restore
 * the window's own pre-fullscreen geometry on its own), Windows has no
 * such automatic restore at all: `(X,Y,W,H)` -- the geometry `fl.window.
 * Window.fullscreenOff()` recorded before entering fullscreen -- is
 * genuinely read and applied here. Backs `fl.window.Window.
 * fullscreenOff(int,int,int,int)`'s Windows branch.
 *
 * The `clearFullscreenFlag()` call below is load-bearing, not
 * defensive. FLTK's own
 * `fullscreen_off()` calls `pWindow->_clear_fullscreen()` as its very
 * first statement -- this port's `fullscreenOn()` mirrors the matching
 * `_set_fullscreen()`/`setFullscreenFlag()` call, and this
 * function needs the corresponding `clearFullscreenFlag()` call
 * (present on the Linux side's own `fl.platform_x11.fullscreenOff()`)
 * too, or `Window.fullscreenActive()` stays wrongly `true` forever
 * after the first `fullscreenOff()` call even though this function's own
 * `SetWindowLong()`/`SetWindowPos()` calls below already correctly
 * restored the window's style and geometry. Two consequences compound
 * from that alone:
 *
 * 1. `source/test/fullscreen.d`'s own `FullscreenWindow.resize()`
 *    schedules `afterResize()` on every resize (including the one this
 *    function's own `SetWindowPos()` just triggered synchronously via
 *    `WM_SIZE`) via `fl.addTimeout(0, ...)`; once that fires, it would read
 *    the wrongly-`true` `fullscreenActive()` and call
 *    `fullscreenButton.set()` -- silently re-lighting the toggle button
 *    behind the user's back (`set()` changes only the value, matching
 *    FLTK's own callback-free semantics), even though the window
 *    itself is genuinely back to normal size/style at this point.
 * 2. The user's very next click would then toggle the button from that
 *    forced `1` back to `0`, re-entering `fullscreenCb()`/
 *    `Window.fullscreenOff()` a *second* time. `noFullscreenX_`/`Y_`
 *    would already be reset to `0` by the first `fullscreenOff()` call's own
 *    unconditional `if (!maximizeActive()) noFullscreenX_ = ... = 0;`
 *    tail, so `Window.fullscreenOff()`'s zero-sentinel check
 *    (`if (noFullscreenX_ == 0 && noFullscreenY_ == 0)`) would re-derive only
 *    `noFullscreenX_`/`Y_` from the window's current position, leaving
 *    `noFullscreenW_`/`H_` at their already-zeroed `0`. With
 *    `fullscreenActive()` (still, wrongly) `true`, this would reach
 *    `platformWin32.fullscreenOff()` a second time with a real `(X,Y)`
 *    but `W=H=0` -- shrinking to whatever minimum size
 *    `WM_GETMINMAXINFO`/`setMinMax()` enforces (`SetWindowPos()` below
 *    still clamps to it, so the requested near-zero size lands at that
 *    floor, not literally 0).
 */
package(fl) void fullscreenOff(FlWindow win, int X, int Y, int W, int H)
{
    win.clearFullscreenFlag();

    auto hwnd = hwndFor(win);
    if (hwnd is null) { fl.core.dispatch(Event.fullscreen, win); return; }

    uint style = cast(uint) GetWindowLong(hwnd, GWL_STYLE);
    if (win.border()) style |= WS_THICKFRAME | WS_SYSMENU | WS_MAXIMIZEBOX | WS_CAPTION;

    // `fakeXWm()`'s own `style == 0 && liveHwnd !is null` "read the
    // live style back" fallback never triggers here since `style` is
    // always explicitly non-zero by this point -- matching FLTK's
    // own real effect (its member-function `fake_X_wm()` reads `fl_xid
    // (pWindow)` internally regardless, so it temporarily zeroes `Fl_X::
    // flx(pWindow)->xid` around this call to suppress that; this port's
    // free-function redesign, which takes an explicit `liveHwnd` used
    // *only* when `style == 0`, makes that dance unnecessary here).
    int wx, wy, bt, bx, by;
    int ret = fakeXWm(win, wx, wy, bt, bx, by, style, 0);
    if (ret == 1) style |= WS_CAPTION;
    SetWindowLong(hwnd, GWL_STYLE, cast(int) style);

    if (!win.maximizeActive())
    {
        float s = fl.core.screenScale(win.screenNum());
        import std.math : ceil;

        int scaledX = cast(int) ceil(X * cast(double) s);
        int scaledY = cast(int) ceil(Y * cast(double) s);
        int scaledW = cast(int) ceil(W * cast(double) s);
        int scaledH = cast(int) ceil(H * cast(double) s);
        if (X != win.x() || Y != win.y())
        {
            scaledX -= bx;
            scaledY -= by + bt;
        }
        scaledW += bx * 2;
        scaledH += by * 2 + bt;
        SetWindowPos(hwnd, null, scaledX, scaledY, scaledW, scaledH,
            SWP_NOACTIVATE | SWP_NOZORDER | SWP_FRAMECHANGED);
    }
    else
    {
        int wx2, wy2, ww2, wh2;
        screenXYWHUnscaled(wx2, wy2, ww2, wh2, win.screenNum());
        SetWindowPos(hwnd, null, wx2, wy2, ww2, wh2,
            SWP_NOACTIVATE | SWP_NOZORDER | SWP_FRAMECHANGED);
    }

    fl.core.dispatch(Event.fullscreen, win);
}

/**
 * Ported from `Fl_WinAPI_Window_Driver::maximize()`/`un_maximize()`
 * -- a real OS-level maximize (`ShowWindow(SW_SHOWMAXIMIZED)`), unlike
 * the EWMH side's *request* to a cooperating window manager.
 *
 * A borderless window takes FLTK's `if (!border()) return
 * Fl_Window_Driver::maximize();` fallback instead
 * (`Window.maximizeByResize()`): hide, resize to the work area, show,
 * since `SW_SHOWMAXIMIZED` on a window without a caption would cover
 * the taskbar. **Deviation**: the maximized flag is set again after
 * that `show()`. In FLTK the `WM_SIZE` the re-shown window receives
 * reports `SIZE_RESTORED`, which clears the flag, so `maximize_active()`
 * is false straight after `maximize()` and `un_maximize()` does nothing
 * (see `FLTK_ISSUES.md`).
 *
 * **Deviation**: `maximizeOff()` picks its path from the window's real
 * state (`IsZoomed()`), not from `border()` as FLTK's `un_maximize()`
 * does, and `maximizeOn()` records the pre-maximize geometry on both
 * paths. `border()` re-creates the window, so it can change between
 * the two calls: maximize with a border, `border(false)`, un-maximize
 * would otherwise take the resize path with no geometry recorded and
 * shrink the window to 0x0 (borderless, so no taskbar entry either).
 */
package(fl) void maximizeOn(FlWindow win)
{
    if (!win.border())
    {
        win.maximizeByResize(true); // FLTK's maximize_needs_hide() is true on Windows
        win.setMaximizedFlag();
        return;
    }
    auto hwnd = hwndFor(win);
    if (hwnd is null) return;
    win.rememberUnmaximizedGeometry();
    ShowWindow(hwnd, SW_SHOWMAXIMIZED);
}

/// ditto, in reverse.
package(fl) void maximizeOff(FlWindow win)
{
    auto hwnd = hwndFor(win);
    if (hwnd !is null && IsZoomed(hwnd))
        ShowWindow(hwnd, SW_SHOWNORMAL);
    else
        win.unMaximizeByResize();
}

/// Ported from `Fl_WinAPI_Window_Driver::iconize()` -- a single
/// `ShowWindow(SW_SHOWMINNOACTIVE)` call. Backs `fl.window.Window.
/// iconize()`'s already-`shown()` branch; the not-yet-`shown()` branch
/// (`showNextWindowIconic()`) is handled entirely in `createWindow()`
/// instead, matching `fl.platform_x11`'s identical split.
package(fl) void iconizeWindow(FlWindow win)
{
    auto hwnd = hwndFor(win);
    if (hwnd is null) return;
    ShowWindow(hwnd, SW_SHOWMINNOACTIVE);
}

/// Ported from `Fl_WinAPI_Window_Driver::set_minmax()` -- called from
/// `wndProc()`'s own `case WM_GETMINMAXINFO:`. Computes the real
/// decoration size via `fakeXWm()` (`style == 0`, `liveHwnd = hwnd`, so
/// it reads the window's own already-set style back, matching
/// FLTK's identical `fake_X_wm(dummy_x, dummy_y, td, wd, hd)`
/// zero-style call) and fills in `minmax`'s track-size/max-size fields
/// from `win.getSizeRange()`, scaled by `fl.core.screenScale()`. A
/// `maxWidth`/`maxHeight` of `0` (`sizeRange()`'s own "no maximum"
/// convention) leaves the corresponding `MINMAXINFO` fields untouched,
/// matching FLTK's own `if (maxw)`/`if (maxh)` guards exactly.
private void setMinMax(FlWindow win, LPMINMAXINFO minmax)
{
    auto hwnd = hwndFor(win);
    if (hwnd is null) return;

    int dummyX, dummyY, bt, bx, by;
    fakeXWm(win, dummyX, dummyY, bt, bx, by, 0, 0, hwnd);
    int wd = bx * 2;
    int hd = by * 2 + bt;

    int minw, minh, maxw, maxh;
    win.getSizeRange(&minw, &minh, &maxw, &maxh);
    float s = fl.core.screenScale(win.screenNum());

    minmax.ptMinTrackSize.x = cast(LONG)(s * minw) + wd;
    minmax.ptMinTrackSize.y = cast(LONG)(s * minh) + hd;
    if (maxw)
    {
        minmax.ptMaxTrackSize.x = cast(LONG)(s * maxw) + wd;
        minmax.ptMaxSize.x = cast(LONG)(s * maxw) + wd;
    }
    if (maxh)
    {
        minmax.ptMaxTrackSize.y = cast(LONG)(s * maxh) + hd;
        minmax.ptMaxSize.y = cast(LONG)(s * maxh) + hd;
    }
}

/// Ported from the file-scope `find_best_icon()` (`Fl_win32.cxx`):
/// picks whichever `icons` entry's `w()` is closest to (without going
/// under) `idealWidth`, or the largest available if every one is
/// smaller than that. `null` if `icons` is empty.
private const(RGBImage) findBestIcon(int idealWidth, const(RGBImage)[] icons)
{
    // Tracks the best candidate's *index* rather than rebinding a
    // `const(RGBImage)` local directly -- unlike a C++ `const C*`, a
    // plain `const(C) best;` local in D makes the variable `best`
    // itself non-reassignable after its (implicit, `null`) initial
    // value, not just the object it refers to, so `best = img;` below
    // doesn't compile (a real error on a real Windows build, not
    // caught when this was authored with no Windows toolchain
    // available -- see this module's own doc comment).
    if (icons.length == 0) return null;
    size_t bestIdx = 0;
    foreach (i, img; icons[1 .. $])
    {
        size_t idx = i + 1;
        if (icons[bestIdx].w() < idealWidth)
        {
            if (img.w() > icons[bestIdx].w()) bestIdx = idx;
        }
        else if (img.w() >= idealWidth && img.w() < icons[bestIdx].w())
            bestIdx = idx;
    }
    return icons[bestIdx];
}

/**
 * Real window icons (taskbar + title bar/Alt-Tab), via `WM_SETICON` --
 * ported from `Fl_WinAPI_Window_Driver::set_icons()`. Backs `fl.window.
 * Window.icons()`/`icon()`'s Windows branch, and is also called once
 * from `createWindow()` itself (matching FLTK's own `make_xid()`
 * call site) so a window's icon is set correctly the first time it's
 * shown, not just on a later `icons()` call.
 *
 * **Deliberately simpler than FLTK's own shared-default-icon
 * cache**: FLTK caches one process-wide `default_big_icon`/
 * `small_icon` pair (via `Fl_WinAPI_Screen_Driver::default_icons()`),
 * reused read-only by every window that hasn't set its own -- which is
 * *why* its own `set_icons()` has to carefully avoid `DestroyIcon()`ing
 * that shared pair (`if (big_icon != default_big_icon) DestroyIcon(...)`)
 * when replacing a window's icon. This port has no such shared cache at
 * all -- every call here recomputes a fresh `HICON` straight from
 * `win.iconsForWM()`/`FlWindow.defaultIconsForWM()`'s `RGBImage`s (via
 * `imageToIcon()`, already built for cursor images) -- so there is
 * nothing shared to protect, and the "destroy whatever `WM_GETICON`
 * currently returns" dance below is safe unconditionally. Observably
 * equivalent: `fl.window.Window.defaultIcons()`'s own doc comment
 * already documents that changing the process-wide default doesn't
 * retroactively touch an already-`setIcons()`'d window either way, on
 * both the real FLTK cache and this recompute-fresh design.
 */
package(fl) void setIcons(FlWindow win)
{
    auto hwnd = hwndFor(win);
    if (hwnd is null) return;

    // Windows doesn't take ownership of an HICON handed to it via
    // WM_SETICON -- the previous one (if any) must be destroyed by
    // hand before replacing it, or every call here leaks one.
    auto oldBig = cast(HICON) SendMessageW(hwnd, WM_GETICON, ICON_BIG, 0);
    if (oldBig !is null) DestroyIcon(oldBig);
    auto oldSmall = cast(HICON) SendMessageW(hwnd, WM_GETICON, ICON_SMALL, 0);
    if (oldSmall !is null) DestroyIcon(oldSmall);

    auto imgs = win.iconsForWM();
    if (imgs.length == 0) imgs = FlWindow.defaultIconsForWM();

    HICON bigIcon, smallIcon;
    if (imgs.length)
    {
        auto bestBig = findBestIcon(GetSystemMetrics(SM_CXICON), imgs);
        auto bestSmall = findBestIcon(GetSystemMetrics(SM_CXSMICON), imgs);
        if (bestBig !is null) bigIcon = imageToIcon(bestBig, true, 0, 0);
        if (bestSmall !is null) smallIcon = imageToIcon(bestSmall, true, 0, 0);
    }

    SendMessageW(hwnd, WM_SETICON, ICON_BIG, cast(LPARAM) bigIcon);
    SendMessageW(hwnd, WM_SETICON, ICON_SMALL, cast(LPARAM) smallIcon);
}

// ---------------------------------------------------------------------
// Drag-and-drop -- ported from the real OLE mechanism (`fl_dnd_win32.
// cxx`'s `FLDropTarget`/`FLDropSource`/`FLDataObject`, `Fl_win32.cxx`'s
// `OleInitialize()`/`RegisterDragDrop()`/`RevokeDragDrop()` call sites,
// and `Fl_WinAPI_Screen_Driver::dnd()`).
//
// **Checked from source before writing any of this, per this phase's
// own standing note**: FLTK's Windows DND is real COM (`IDropTarget`/
// `IDropSource`/`IDataObject`/`DoDragDrop()`/`RegisterDragDrop()`), not
// the much simpler `WM_DROPFILES` shell mechanism a first guess might
// reach for.
//
// **Scope matches this port's own already-established X11 DND scope
// for MIME/format negotiation, not FLTK's full Windows surface**:
// `PORTING.md`'s `FL/x.H` row documents this port's XDND implementation
// as text-only ("DND is text-only... `COMPOUND_TEXT`/other charset
// target variants aren't negotiated either"), deliberately narrower than
// FLTK's own XDND (which also negotiates other MIME types).
// **Correction: the two Windows-only fallback branches this section
// used to list as not-ported gaps are both real now** (`CF_HDROP`
// dropped-file-lists, and the legacy `CF_TEXT`/CP1252 fallback) -- see
// `fillCurrentDragData()`'s own doc comment for the full writeup of each.
// Both stay within this port's existing text-only *delivery* scope
// (everything still arrives as a plain `Event.paste` string, just from
// three different source formats now instead of one), so porting them
// doesn't widen the MIME-negotiation gap the paragraph above describes.
//
// **`FLEnum`/`IEnumFORMATETC` is deliberately not ported at all**:
// checked FLTK's actual `FLDataObject::EnumFormatEtc()` body, not
// assumed -- it's `return E_NOTIMPL;` unconditionally, with the real
// `FLEnum`-returning implementation and the `m_EnumF` field that would
// use it both entirely commented out in FLTK's own source. `FLEnum`
// is real, checked-in, but genuinely dead code FLTK itself never
// executes -- porting it would add a class this session's own D port
// would exercise even less than FLTK does.
// ---------------------------------------------------------------------

/// The single, process-wide `IDropTarget` instance registered for
/// every window via `RegisterDragDrop()` in `createWindow()` -- matches
/// FLTK's own single static `flDropTarget`/`flIDropTarget` exactly
/// (not one instance per window). Created once, in `ensureGraphicsDriver()`.
private FLDropTarget dropTarget_;

/// The FLTK window currently under the drag, or `null` between drags
/// -- ported from the file-scope `Fl_Window *fl_dnd_target_window`
/// (`fl_dnd_win32.cxx`).
private FlWindow dndTargetWindow_;

private DWORD dndLastEffect_;
private int dndPx_, dndPy_;

/// The `IDataObject` `fillCurrentDragData()` last decoded, and the
/// UTF-8 text it decoded from it (if any) -- ported from the file-scope
/// `currDragRef`/`currDragData`/`currDragResult` triple. Comparing
/// against the *reference*, not re-decoding every call, is what makes
/// `DragOver()`'s frequent re-checks cheap -- matches FLTK's own
/// `if (data==currDragRef) return currDragResult;` short-circuit.
private IDataObject dndDataRef_;
private string dndText_;
private bool dndHaveText_;

/// Ported from the file-scope `clearCurrentDragData()`.
private void clearCurrentDragData()
{
    dndDataRef_ = null;
    dndText_ = null;
    dndHaveText_ = false;
}

/**
 * Ported from the file-scope `fillCurrentDragData()`
 * (`fl_dnd_win32.cxx`) -- all three of FLTK's own fallback branches
 * now, closing what this section's own header comment used to list as
 * two deliberate scope gaps: `CF_UNICODETEXT` (preferred), then legacy
 * `CF_TEXT`/CP1252 text, then `CF_HDROP` (a file-manager's dropped-file
 * list, delivered as the same `\n`-separated-path-list `Event.paste`
 * text FLTK sends). `data is null` (matching FLTK's `!data`)
 * re-answers from the already-decoded `dndText_`/`dndHaveText_` without
 * touching the `IDataObject` again -- `DragOver()`'s own repeat calls
 * use this shortcut. Returns whether text is now available.
 */
private bool fillCurrentDragData(IDataObject data)
{
    if (data is null) return dndHaveText_;
    if (data is dndDataRef_) return dndHaveText_;

    clearCurrentDragData();
    dndDataRef_ = data;

    FORMATETC fmt;
    fmt.dwAspect = cast(DWORD) DVASPECT_CONTENT;
    fmt.lindex = -1;
    fmt.tymed = cast(DWORD) TYMED_HGLOBAL;
    STGMEDIUM medium;

    fmt.cfFormat = cast(CLIPFORMAT) CF_UNICODETEXT;
    if (data.GetData(&fmt, &medium) == S_OK)
    {
        auto mem = cast(const(wchar)*) GlobalLock(medium.hGlobal);
        if (mem !is null)
        {
            size_t len = 0;
            while (mem[len] != 0) len++;
            dndText_ = mem[0 .. len].toUTF8;
            GlobalUnlock(medium.hGlobal);
        }
        ReleaseStgMedium(&medium);
        dndHaveText_ = true;
        return dndHaveText_;
    }

    // Legacy CP1252 ("ANSI") text -- FLTK re-decodes it byte-by-byte
    // through `fl_utf8decode()`/`fl_utf8encode()`, whose own fallback
    // table happens to treat an invalid lead byte as CP1252 -- this port
    // has no `fl_utf8decode()` equivalent to reuse, so it goes through
    // the real Win32 codepage conversion (`MultiByteToWideChar(CP_ACP,
    // ...)`) instead, the standard idiom for decoding `CF_TEXT` and
    // observably equivalent for real drag sources (any pre-Unicode app
    // offering `CF_TEXT` at all always encodes it in the system ANSI
    // codepage, which `CP_ACP` names directly).
    fmt.cfFormat = cast(CLIPFORMAT) CF_TEXT;
    if (data.GetData(&fmt, &medium) == S_OK)
    {
        auto mem = cast(const(char)*) GlobalLock(medium.hGlobal);
        if (mem !is null)
        {
            size_t len = 0;
            while (mem[len] != 0) len++;
            int wlen = MultiByteToWideChar(CP_ACP, 0, mem, cast(int) len, null, 0);
            if (wlen > 0)
            {
                auto wbuf = new wchar[wlen];
                MultiByteToWideChar(CP_ACP, 0, mem, cast(int) len, wbuf.ptr, wlen);
                dndText_ = wbuf.toUTF8;
            }
            GlobalUnlock(medium.hGlobal);
        }
        ReleaseStgMedium(&medium);
        dndHaveText_ = true;
        return dndHaveText_;
    }

    // A file-manager drag (dropped file/folder icons) -- no text format
    // of any kind, just a `CF_HDROP` file list. Matches FLTK's own
    // `\n`-joined path list exactly (no trailing separator).
    fmt.cfFormat = cast(CLIPFORMAT) CF_HDROP;
    if (data.GetData(&fmt, &medium) == S_OK)
    {
        HDROP hdrop = cast(HDROP) medium.hGlobal;
        UINT nf = DragQueryFileW(hdrop, cast(UINT) -1, null, 0);
        string[] paths;
        paths.reserve(nf);
        foreach (i; 0 .. nf)
        {
            UINT n = DragQueryFileW(hdrop, i, null, 0);
            auto buf = new wchar[n + 1];
            DragQueryFileW(hdrop, i, buf.ptr, cast(UINT) buf.length);
            paths ~= buf[0 .. n].toUTF8;
        }
        dndText_ = paths.join("\n");
        ReleaseStgMedium(&medium);
        dndHaveText_ = true;
        return dndHaveText_;
    }

    return dndHaveText_;
}

/**
 * Subclasses `IDropTarget` to receive real OLE drops -- ported from
 * `FLDropTarget` (`fl_dnd_win32.cxx`). One shared instance
 * (`dropTarget_`) is registered for every window, so `DragEnter()`
 * has to work out *which* FLTK window the cursor is actually over
 * itself, via `WindowFromPoint()` -- matching FLTK exactly (the
 * per-window HWND is never handed to any of these callbacks directly).
 * `AddRef()`/`Release()` track a real count purely for diagnostics,
 * matching FLTK's own "static object, do not delete this" comment
 * -- this instance lives for the process's whole lifetime regardless
 * of what the count says.
 */
private final class FLDropTarget : IDropTarget
{
    extern (Windows):

    private DWORD refCount_;

    HRESULT QueryInterface(IID* riid, void** ppv)
    {
        if (*riid == IID_IUnknown || *riid == IID_IDropTarget)
        {
            *ppv = cast(void*) cast(IDropTarget) this;
            AddRef();
            return S_OK;
        }
        *ppv = null;
        return E_NOINTERFACE;
    }

    ULONG AddRef() { return ++refCount_; }
    ULONG Release() { return --refCount_; }

    HRESULT DragEnter(IDataObject pDataObj, DWORD grfKeyState, POINTL pt, DWORD* pdwEffect)
    {
        if (pDataObj is null) return E_INVALIDARG;

        POINT screenPt = POINT(pt.x, pt.y);
        HWND hwnd = WindowFromPoint(screenPt);
        auto rec = find(hwnd);
        FlWindow target = rec !is null ? rec.widget : null;
        if (target !is null)
        {
            float s = fl.core.screenScale(target.screenNum());
            fl.core.eXRoot_ = cast(int)(pt.x / s);
            fl.core.eYRoot_ = cast(int)(pt.y / s);
            fl.core.eX_ = fl.core.eXRoot_ - target.x();
            fl.core.eY_ = fl.core.eYRoot_ - target.y();
        }
        dndTargetWindow_ = target;
        dndPx_ = pt.x;
        dndPy_ = pt.y;

        if (fillCurrentDragData(pDataObj))
        {
            // Matches FLTK's own comment: FLTK has no mechanism yet
            // for the different drop effects, so both move and copy are
            // always allowed together.
            *pdwEffect = (target !is null && fl.core.dispatch(Event.dndEnter, target))
                ? (DROPEFFECT_MOVE | DROPEFFECT_COPY) : DROPEFFECT_NONE;
        }
        else
            *pdwEffect = DROPEFFECT_NONE;

        dndLastEffect_ = *pdwEffect;
        return S_OK;
    }

    HRESULT DragOver(DWORD grfKeyState, POINTL pt, DWORD* pdwEffect)
    {
        if (dndPx_ == pt.x && dndPy_ == pt.y)
        {
            *pdwEffect = dndLastEffect_;
            return S_OK;
        }
        if (dndTargetWindow_ is null)
        {
            *pdwEffect = dndLastEffect_ = DROPEFFECT_NONE;
            return S_OK;
        }

        float s = fl.core.screenScale(dndTargetWindow_.screenNum());
        fl.core.eXRoot_ = cast(int)(pt.x / s);
        fl.core.eYRoot_ = cast(int)(pt.y / s);
        fl.core.eX_ = fl.core.eXRoot_ - dndTargetWindow_.x();
        fl.core.eY_ = fl.core.eYRoot_ - dndTargetWindow_.y();

        if (fillCurrentDragData(null))
            *pdwEffect = fl.core.dispatch(Event.dndDrag, dndTargetWindow_)
                ? (DROPEFFECT_MOVE | DROPEFFECT_COPY) : DROPEFFECT_NONE;
        else
            *pdwEffect = DROPEFFECT_NONE;

        dndPx_ = pt.x;
        dndPy_ = pt.y;
        dndLastEffect_ = *pdwEffect;
        // Shows a live insert-position caret when dragging within the
        // same window/process -- matches FLTK's own `Fl::flush();`
        // (STR #3209).
        fl.core.flush();
        return S_OK;
    }

    HRESULT DragLeave()
    {
        if (dndTargetWindow_ !is null && fillCurrentDragData(null))
        {
            fl.core.dispatch(Event.dndLeave, dndTargetWindow_);
            dndTargetWindow_ = null;
            clearCurrentDragData();
        }
        return S_OK;
    }

    HRESULT Drop(IDataObject data, DWORD grfKeyState, POINTL pt, DWORD* pdwEffect)
    {
        if (dndTargetWindow_ is null) return S_OK;
        auto target = dndTargetWindow_;
        dndTargetWindow_ = null;

        float s = fl.core.screenScale(target.screenNum());
        fl.core.eXRoot_ = cast(int)(pt.x / s);
        fl.core.eYRoot_ = cast(int)(pt.y / s);
        fl.core.eX_ = fl.core.eXRoot_ - target.x();
        fl.core.eY_ = fl.core.eYRoot_ - target.y();

        if (!fl.core.dispatch(Event.dndRelease, target)) return S_OK;

        if (fillCurrentDragData(data))
        {
            // Same deliverPaste() infrastructure X11's own drop
            // handling uses (fl.platform_x11's `case ClientMessage:`'s
            // `xdndDrop_` branch) -- Windows just calls it immediately,
            // synchronously, rather than waiting for a later reply.
            fl.core.setPendingPasteReceiver(fl.core.belowmouse());
            fl.core.deliverPaste(crlfToLf(dndText_));

            FlWindow top = target;
            while (top.window() !is null) top = top.window();
            if (auto hwnd = hwndFor(top)) SetForegroundWindow(hwnd);

            clearCurrentDragData();
        }
        return S_OK;
    }
}

/// Ported from `FLDropSource` (`fl_dnd_win32.cxx`) -- lets this
/// process itself be a drag source. A fresh instance per `dnd()` call,
/// matching FLTK's own `new FLDropSource` there (unlike
/// `FLDropTarget`'s single shared instance).
private final class FLDropSource : IDropSource
{
    extern (Windows):

    private DWORD refCount_;

    HRESULT QueryInterface(IID* riid, void** ppv)
    {
        if (*riid == IID_IUnknown || *riid == IID_IDropSource)
        {
            *ppv = cast(void*) cast(IDropSource) this;
            AddRef();
            return S_OK;
        }
        *ppv = null;
        return E_NOINTERFACE;
    }

    ULONG AddRef() { return ++refCount_; }
    ULONG Release() { return --refCount_; }

    HRESULT GiveFeedback(DWORD) { return DRAGDROP_S_USEDEFAULTCURSORS; }

    HRESULT QueryContinueDrag(BOOL esc, DWORD keyState)
    {
        if (esc) return DRAGDROP_S_CANCEL;
        if (!(keyState & (MK_LBUTTON | MK_MBUTTON | MK_RBUTTON))) return DRAGDROP_S_DROP;
        return S_OK;
    }
}

/**
 * The actual object this process hands `DoDragDrop()` to drop
 * somewhere -- ported from `FLDataObject` (`fl_dnd_win32.cxx`), minimal
 * on purpose (matches FLTK's own doc comment: "it should work with
 * all decent Win32 drop targets"). Only `CF_UNICODETEXT` via
 * `GetData()`/`QueryGetData()` is implemented; everything else is
 * `E_NOTIMPL`, matching FLTK's own real body exactly (not a
 * simplification -- FLTK's own `GetDataHere()`/
 * `GetCanonicalFormatEtc()`/`SetData()`/`EnumFormatEtc()`/`DAdvise()`/
 * `DUnadvise()`/`EnumDAdvise()` are *all* already bare `E_NOTIMPL`
 * stubs in the real source, not abbreviated here). A fresh instance
 * per `dnd()` call, matching FLTK's own `new FLDataObject` there.
 */
private final class FLDataObject : IDataObject
{
    extern (Windows):

    private DWORD refCount_ = 1;

    HRESULT QueryInterface(IID* riid, void** ppv)
    {
        if (*riid == IID_IUnknown || *riid == IID_IDataObject)
        {
            *ppv = cast(void*) cast(IDataObject) this;
            AddRef();
            return S_OK;
        }
        *ppv = null;
        return E_NOINTERFACE;
    }

    ULONG AddRef() { return ++refCount_; }
    ULONG Release() { return --refCount_; }

    /// Ported from `FLDataObject::GetData()` -- offers whatever
    /// `fl.core.copy()` most recently placed in the PRIMARY selection
    /// (matching `fl.core.dnd()`'s own doc comment), `\n`-to-`\r\n`
    /// converted (`lfToCrlf()`, already built for the clipboard) the
    /// same way FLTK's own `fl_selection_buffer[0]` gets converted
    /// here.
    HRESULT GetData(FORMATETC* fmt, STGMEDIUM* medium)
    {
        if (!((fmt.dwAspect & cast(DWORD) DVASPECT_CONTENT) && (fmt.tymed & cast(DWORD) TYMED_HGLOBAL)
                && fmt.cfFormat == cast(CLIPFORMAT) CF_UNICODETEXT))
            return DV_E_FORMATETC;

        wstring wtext = lfToCrlf(fl.core.clipboardContents(0)).toUTF16;
        HGLOBAL gh = GlobalAlloc(GHND, (wtext.length + 1) * wchar.sizeof);
        if (gh is null) return E_OUTOFMEMORY;
        auto mem = cast(wchar*) GlobalLock(gh);
        if (mem !is null)
        {
            mem[0 .. wtext.length] = wtext[];
            mem[wtext.length] = 0;
            GlobalUnlock(gh);
        }
        medium.tymed = cast(DWORD) TYMED_HGLOBAL;
        medium.hGlobal = gh;
        medium.pUnkForRelease = null;
        return S_OK;
    }

    HRESULT QueryGetData(FORMATETC* fmt)
    {
        if ((fmt.dwAspect & cast(DWORD) DVASPECT_CONTENT) && (fmt.tymed & cast(DWORD) TYMED_HGLOBAL)
                && fmt.cfFormat == cast(CLIPFORMAT) CF_UNICODETEXT)
            return S_OK;
        return DV_E_FORMATETC;
    }

    HRESULT GetDataHere(FORMATETC*, STGMEDIUM*) { return E_NOTIMPL; }
    HRESULT GetCanonicalFormatEtc(FORMATETC*, FORMATETC*) { return E_NOTIMPL; }
    HRESULT SetData(FORMATETC*, STGMEDIUM*, BOOL) { return E_NOTIMPL; }
    HRESULT EnumFormatEtc(DWORD, IEnumFORMATETC*) { return E_NOTIMPL; }
    HRESULT DAdvise(FORMATETC*, DWORD, IAdviseSink, DWORD*) { return E_NOTIMPL; }
    HRESULT DUnadvise(DWORD) { return E_NOTIMPL; }
    HRESULT EnumDAdvise(IEnumSTATDATA*) { return E_NOTIMPL; }
}

/**
 * Starts a drag-and-drop operation carrying whatever `fl.core.copy()`
 * most recently placed in the PRIMARY selection -- ported from
 * `Fl_WinAPI_Screen_Driver::dnd(int)`. Backs `fl.core.dnd()`'s Windows
 * branch. Unlike X11's `dnd()` (a manual poll loop this port built by
 * hand), `DoDragDrop()` is a single blocking OS call that runs the
 * whole drag internally, calling back into whichever window's
 * `dropTarget_` the cursor is over via the callbacks above.
 */
package(fl) int dnd()
{
    ReleaseCapture();

    auto fdo = new FLDataObject;
    auto fds = new FLDropSource;

    DWORD dropEffect;
    HRESULT ret = DoDragDrop(fdo, fds, DROPEFFECT_MOVE | DROPEFFECT_LINK | DROPEFFECT_COPY, &dropEffect);

    auto w = fl.core.pushed();
    if (w !is null)
    {
        auto oldEvent = fl.core.eNumber_;
        fl.core.eNumber_ = Event.release;
        w.handle(Event.release);
        fl.core.eNumber_ = oldEvent;
        fl.core.pushed(null);
    }

    return ret == DRAGDROP_S_DROP ? 1 : 0;
}
