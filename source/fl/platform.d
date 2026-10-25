/*
 * The Linux platform layer: the functions the rest of fldtk calls to
 * create and manage windows, run the event loop, use the clipboard and
 * query screens and input state, whichever display server the program
 * runs on.
 *
 * FLTK reaches its platform through driver objects (`Fl_Screen_Driver`,
 * `Fl_Window_Driver`, ...) whose concrete class is chosen at startup;
 * in a Linux build with both backends, `fl_wayland_platform_init.cxx`
 * picks the Wayland or the X11 drivers. fldtk's platform modules are
 * concrete modules of free functions instead (`fl.platform_x11`,
 * `fl.platform_wayland`), so this module is a facade over them:
 * each function forwards to the backend chosen at startup.
 * `backend()` says which one that is.
 *
 * The backend is chosen once, the first time any of these functions
 * runs, following FLTK's `fl_wayland_platform_init.cxx`: the environment
 * variable `FLDTK_BACKEND` (FLTK's `FLTK_BACKEND`, renamed into fldtk's
 * own prefix) set to `x11` or `wayland`, in any case (`X11`, `Wayland`),
 * forces one; FLTK accepts the lowercase words only. Unset,
 * Wayland is used when `XDG_RUNTIME_DIR` is set and a Wayland connection
 * can be made, X11 otherwise. A unittest build uses X11 unless
 * `FLDTK_BACKEND` says otherwise. A build without Wayland support
 * (`linux-no-cairo`) always uses X11.
 *
 * Not part of the facade, because they only mean something on X11:
 * the X `Display*`, screen, visual and colormap (`x11Display()`,
 * `x11Screen()`, `fl_visual`, `fl_colormap`), `setVisual()`,
 * `setDisplayName()`, `getDefaultResource()` and the raw `XEvent*`
 * system handlers. Code using them (GLX, `fl.cairo`, X resources)
 * imports `fl.platform_x11` itself and runs only when `backend()` is
 * `Backend.x11`.
 *
 * Windows has a single backend, `fl.platform_win32`, which callers use
 * directly.
 */
module fl.platform;

version (linux):

import platformX11 = fl.platform_x11;
version (FLDTK_HAVE_WAYLAND) import platformWayland = fl.platform_wayland;
import fl.window : FlWindow = Window;
import fl.image : RGBImage;
import fl.enumerations : Keysym, Beep, CursorShape = Cursor;

/// The display servers fldtk can run on under Linux.
enum Backend
{
    x11,
    wayland,
}

private Backend backend_;
private bool chosen_;

/// The display server this program runs on.
Backend backend()
{
    if (!chosen_) chooseBackend();
    return backend_;
}

private void chooseBackend()
{
    chosen_ = true;
    backend_ = Backend.x11;
    version (FLDTK_HAVE_WAYLAND)
    {
        import std.process : environment;
        import core.stdc.stdlib : exit;
        import std.stdio : stderr;

        import std.uni : toLower;
        string value = environment.get("FLDTK_BACKEND");
        string b = value is null ? null : value.toLower; // X11 and x11 alike
        if (b == "x11") return;
        if (b == "wayland")
        {
            if (!platformWayland.connect())
            {
                stderr.writeln("Error: no Wayland connection available, FLDTK_BACKEND='", value, "'");
                exit(1);
            }
            backend_ = Backend.wayland;
            return;
        }
        if (b !is null)
        {
            stderr.writeln("Error: unexpected value of FLDTK_BACKEND: '", value, "' (x11 or wayland)");
            exit(1);
        }
        // The unit tests are written against X11 (no graphics driver
        // means Xlib); they use Wayland only when FLDTK_BACKEND asks.
        version (unittest) return;
        else if (environment.get("XDG_RUNTIME_DIR") !is null && platformWayland.connect())
            backend_ = Backend.wayland;
    }
}

/// The statements forwarding `call` to the active backend.
private enum fwd(string call) =
    "version (FLDTK_HAVE_WAYLAND) if (backend() == Backend.wayland) return platformWayland."
    ~ call ~ "; return platformX11." ~ call ~ ";";

/**
 * Makes `win` the target of drawing: on X11 its X window, at its
 * screen's scale; on Wayland its draw buffer.
 */
package(fl) void makeCurrent(FlWindow win)
{
    version (FLDTK_HAVE_WAYLAND) if (backend() == Backend.wayland) return platformWayland.makeCurrent(win);
    import fldraw = fl.draw;
    import fl.core : currentScale, screenScale;
    fldraw.setDrawable(win.xid());
    currentScale(screenScale(win.screenNum()));
}

// -- display and event loop ---------------------------------------------

void openDisplay() { mixin(fwd!q{openDisplay()}); }
void run() { mixin(fwd!q{run()}); }
void wait() { mixin(fwd!q{wait()}); }
double wait(double timeToWait) { mixin(fwd!q{wait(timeToWait)}); }
bool check() { mixin(fwd!q{check()}); }
package(fl) bool eventsReady() { mixin(fwd!q{eventsReady()}); }
package(fl) void flushDamage() { mixin(fwd!q{flushDamage()}); }
void beep(Beep type) { mixin(fwd!q{beep(type)}); }

// -- windows ------------------------------------------------------------

void createWindow(FlWindow win) { mixin(fwd!q{createWindow(win)}); }
void destroyWindow(FlWindow win) { mixin(fwd!q{destroyWindow(win)}); }
void raiseWindow(FlWindow win) { mixin(fwd!q{raiseWindow(win)}); }
void unmapWindow(FlWindow win) { mixin(fwd!q{unmapWindow(win)}); }
package(fl) void iconizeWindow(FlWindow win) { mixin(fwd!q{iconizeWindow(win)}); }
package(fl) void waitForExpose(FlWindow win) { mixin(fwd!q{waitForExpose(win)}); }

package(fl) void resizeWindow(FlWindow win, int x, int y, int w, int h, bool isMove, bool isResize,
    int exactDevX = int.min, int exactDevY = int.min)
{ mixin(fwd!q{resizeWindow(win, x, y, w, h, isMove, isResize, exactDevX, exactDevY)}); }

package(fl) void sizeRangeChanged(FlWindow win) { mixin(fwd!q{sizeRangeChanged(win)}); }
package(fl) bool decoratedWinSize(FlWindow win, out int w, out int h) { mixin(fwd!q{decoratedWinSize(win, w, h)}); }
package(fl) void updateWindowLabel(FlWindow win) { mixin(fwd!q{updateWindowLabel(win)}); }
package(fl) void setIcons(FlWindow win) { mixin(fwd!q{setIcons(win)}); }
package(fl) void fullscreenOn(FlWindow win) { mixin(fwd!q{fullscreenOn(win)}); }
package(fl) void fullscreenOff(FlWindow win) { mixin(fwd!q{fullscreenOff(win)}); }
package(fl) void maximizeOn(FlWindow win) { mixin(fwd!q{maximizeOn(win)}); }
package(fl) void maximizeOff(FlWindow win) { mixin(fwd!q{maximizeOff(win)}); }

package(fl) void applyWindowShapeMask(FlWindow win, int w, int h, const(ubyte)[] bits)
{ mixin(fwd!q{applyWindowShapeMask(win, w, h, bits)}); }

package(fl) void setCursor(FlWindow win, CursorShape c) { mixin(fwd!q{setCursor(win, c)}); }

package(fl) bool setCursorImage(FlWindow win, const(RGBImage) image, int hotx, int hoty)
{ mixin(fwd!q{setCursorImage(win, image, hotx, hoty)}); }

package(fl) void accumulateDamage(FlWindow win, int x, int y, int w, int h)
{ mixin(fwd!q{accumulateDamage(win, x, y, w, h)}); }

package(fl) void clearDamageRegion(FlWindow win) { mixin(fwd!q{clearDamageRegion(win)}); }

package(fl) ubyte[] captureWindowPixels(FlWindow win, int x, int y, int w, int h)
{ mixin(fwd!q{captureWindowPixels(win, x, y, w, h)}); }

package(fl) RGBImage captureTitlebarImage(FlWindow win) { mixin(fwd!q{captureTitlebarImage(win)}); }

package(fl) FlWindow firstWindowWidget() { mixin(fwd!q{firstWindowWidget()}); }
package(fl) FlWindow nextWindowWidget(FlWindow win) { mixin(fwd!q{nextWindowWidget(win)}); }
package(fl) void makeWindowFirst(FlWindow win) { mixin(fwd!q{makeWindowFirst(win)}); }

// -- input --------------------------------------------------------------

package(fl) bool eventKey(Keysym k) { mixin(fwd!q{eventKey(k)}); }
package(fl) bool getKey(Keysym k) { mixin(fwd!q{getKey(k)}); }
package(fl) int getMouse(out int x, out int y) { mixin(fwd!q{getMouse(x, y)}); }
string keyName(uint key) { mixin(fwd!q{keyName(key)}); }
package(fl) void grabPointer(FlWindow win) { mixin(fwd!q{grabPointer(win)}); }
package(fl) void ungrabPointer() { mixin(fwd!q{ungrabPointer()}); }

package(fl) void setSpot(int font, int size, int X, int Y, int W, int H)
{ mixin(fwd!q{setSpot(font, size, X, Y, W, H)}); }

package(fl) void resetSpot() { mixin(fwd!q{resetSpot()}); }
package(fl) void resetIC() { mixin(fwd!q{resetIC()}); }

// -- clipboard and drag and drop ----------------------------------------

package(fl) void setSelectionOwner(int clipboard) { mixin(fwd!q{setSelectionOwner(clipboard)}); }
package(fl) void requestSelection(int clipboard) { mixin(fwd!q{requestSelection(clipboard)}); }
package(fl) void requestSelectionImage(int clipboard) { mixin(fwd!q{requestSelectionImage(clipboard)}); }
package(fl) bool clipboardContains(string type) { mixin(fwd!q{clipboardContains(type)}); }
package(fl) void clipboardNotifyChange() { mixin(fwd!q{clipboardNotifyChange()}); }
package(fl) int dnd(bool localOnly) { mixin(fwd!q{dnd(localOnly)}); }

// -- screens ------------------------------------------------------------

package(fl) int screenCount() { mixin(fwd!q{screenCount()}); }

package(fl) void screenXYWH(out int x, out int y, out int w, out int h, int n)
{ mixin(fwd!q{screenXYWH(x, y, w, h, n)}); }

package(fl) void screenWorkArea(out int x, out int y, out int w, out int h, int n)
{ mixin(fwd!q{screenWorkArea(x, y, w, h, n)}); }

package(fl) void screenDpi(out float h, out float v, int n) { mixin(fwd!q{screenDpi(h, v, n)}); }
package(fl) int screenNum(int x, int y) { mixin(fwd!q{screenNum(x, y)}); }
package(fl) int screenNum(int x, int y, int w, int h) { mixin(fwd!q{screenNum(x, y, w, h)}); }
