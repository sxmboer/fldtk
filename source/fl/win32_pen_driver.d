/*
 * Pen input on Windows: port of `src/drivers/WinAPI/
 * Fl_WinAPI_Pen_Driver.{H,cxx}`, through Windows' pointer input
 * messages (`WM_POINTER*`, Windows 8 and later). The dispatch to widgets
 * is `fl.pen`'s, shared with the Wayland driver.
 *
 * Every `WM_POINTERDOWN`/`UPDATE`/`UP` message carries the pen's whole
 * state (`GetPointerPenInfo()`), so each one is dispatched at once,
 * comparing with the state dispatched last. Windows also sends mouse
 * messages for the pen, unless the window handled the pointer message:
 * when a subscriber claims a pen event, `handleMessage()` returns true
 * and the window procedure returns without `DefWindowProcW()`, so no
 * mouse message follows; otherwise the mouse messages drive fldtk's
 * normal mouse handling, so nothing is turned into mouse events here.
 *
 * The pointer functions are looked up in user32.dll at run time, not
 * linked: on Windows 7 there are none, and pens act as mice there.
 */
module fl.win32_pen_driver;

version (Windows):

import core.sys.windows.windows;
import fl.pen;
import fl.win32_pointer;
import fl.window : FlWindow = Window;
import fl.core : screenScale;
import platformWin32 = fl.platform_win32;

// ---- pens

/// One pen, by its digitizer device (FLTK's `PenDevice`). Windows gives
/// no pen serial number through this API, so pens are numbered as they
/// are first seen.
private final class WinPen : PenTool
{
    HANDLE sourceDevice;
}

private WinPen[HANDLE] devices_;
private int nextPenId_ = 1;

private enum Pen.Trait penCapabilities = Pen.Trait.driverAvailable | Pen.Trait.penId | Pen.Trait.eraser
    | Pen.Trait.pressure | Pen.Trait.tiltX | Pen.Trait.tiltY | Pen.Trait.twist;

/// Ported from `WinAPI_Driver::traits()`. Windows reports neither barrel
/// pressure nor distance from the screen.
package(fl) Pen.Trait traits()
{
    if (!havePointerApi()) return Pen.Trait.none;
    return penCapabilities | (devices_.length ? Pen.Trait.detected : Pen.Trait.none);
}

/// Ported from `WinAPI_Driver::pen_traits()`.
package(fl) Pen.Trait penTraits(int penId)
{
    foreach (dev; devices_)
        if (penId == 0 ? dev is currentPen_ : dev.penId == penId) return dev.capabilities;
    return Pen.Trait.none;
}

/// Ported from `WinAPI_Driver::release()`.
package(fl) void releaseCaptureIfPushed()
{
    if (penPushed_ !is null) ReleaseCapture();
}

private WinPen deviceOf(HANDLE source)
{
    if (auto p = source in devices_) return *p;
    auto dev = new WinPen;
    dev.sourceDevice = source;
    dev.penId = nextPenId_++;
    dev.capabilities = penCapabilities;
    dev.ev.penId = dev.penId;
    devices_[source] = dev;
    return dev;
}

/// The pen's position in the FLTK units of its toplevel window -- FLTK's
/// `update_position()`.
private void updatePosition(WinPen dev, HWND hwnd, ref const POINTER_INFO pi)
{
    FlWindow win = platformWin32.windowOfHwnd(hwnd);
    if (win is null) return;
    POINT pt = pi.ptPixelLocation;
    ScreenToClient(hwnd, &pt);
    int dx = 0, dy = 0;
    FlWindow top = win;
    while (top.parent !is null && top.window() !is null)
    {
        dx += top.x();
        dy += top.y();
        top = top.window();
    }
    float f = screenScale(top.screenNum());
    dev.ev.x = pt.x / f + dx;
    dev.ev.y = pt.y / f + dy;
    dev.ev.rx = dev.ev.x + top.x();
    dev.ev.ry = dev.ev.y + top.y();
    dev.focusWin = top;
}

/// The tip, eraser and barrel buttons -- FLTK's `compute_pen_state()`.
/// The first button is the tip's contact itself; the second to fifth
/// are the barrel buttons.
private Pen.State penState(ref const POINTER_PEN_INFO pi)
{
    bool contact = (pi.pointerInfo.pointerFlags & POINTER_FLAG_INCONTACT) != 0;
    bool eraser = (pi.penFlags & (PEN_FLAG_INVERTED | PEN_FLAG_ERASER)) != 0;
    Pen.State s = eraser ? (contact ? Pen.State.eraserDown : Pen.State.eraserHovers)
        : (contact ? Pen.State.tipDown : Pen.State.tipHovers);
    auto flags = pi.pointerInfo.pointerFlags;
    if (flags & POINTER_FLAG_SECONDBUTTON) s |= Pen.State.button0;
    if (flags & POINTER_FLAG_THIRDBUTTON) s |= Pen.State.button1;
    if (flags & POINTER_FLAG_FOURTHBUTTON) s |= Pen.State.button2;
    if (flags & POINTER_FLAG_FIFTHBUTTON) s |= Pen.State.button3;
    return s;
}

/// Pressure, tilt and rotation, where the pen reports them -- FLTK's
/// `update_axes()`.
private void updateAxes(WinPen dev, ref const POINTER_PEN_INFO pi)
{
    if (pi.penMask & PEN_MASK_PRESSURE) dev.ev.pressure = pi.pressure / 1024.0;
    if (pi.penMask & PEN_MASK_TILT_X) dev.ev.tiltX = -pi.tiltX / 90.0;
    if (pi.penMask & PEN_MASK_TILT_Y) dev.ev.tiltY = -pi.tiltY / 90.0;
    if (pi.penMask & PEN_MASK_ROTATION)
    {
        double deg = pi.rotation; // clockwise, 0 to 360 -> -180 to 180
        dev.ev.twist = deg > 180 ? deg - 360 : deg;
    }
}

/**
 * A window message: when it is a `WM_POINTER*` message for a pen and
 * widgets are subscribed, it is dispatched -- FLTK's
 * `fl_winapi_pen_handle()`. Returns true when a widget took the event:
 * the window procedure then returns without `DefWindowProcW()`, so
 * Windows sends no mouse message for it.
 */
package(fl) bool handleMessage(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam)
{
    switch (msg)
    {
        case WM_POINTERENTER, WM_POINTERLEAVE, WM_POINTERDOWN, WM_POINTERUP,
            WM_POINTERUPDATE, WM_POINTERCAPTURECHANGED:
            break;
        default:
            return false;
    }
    if (subscribers_.length == 0 || !havePointerApi()) return false;

    UINT32 id = LOWORD(wParam);
    DWORD type;
    if (!getPointerType_(id, &type) || type != PT_PEN) return false; // touch, mouse, ...
    POINTER_PEN_INFO pi;
    if (!getPointerPenInfo_(id, &pi)) return false;
    WinPen dev = deviceOf(pi.pointerInfo.sourceDevice);

    PenPlatform platform;
    platform.sendsMouseEvents = true;
    platform.capture = (FlWindow w) { SetCapture(hwnd); };
    platform.releaseCapture = () { ReleaseCapture(); };

    PenFrame f;
    switch (msg)
    {
        case WM_POINTERENTER:
            updatePosition(dev, hwnd, pi.pointerInfo);
            updateAxes(dev, pi);
            dev.ev.state = penState(pi);
            f.proximityIn = true;
            dispatchPenFrame(dev, f, platform);
            return false; // Windows still sends its mouse messages, as in FLTK

        case WM_POINTERLEAVE:
            if (!(HIWORD(wParam) & POINTER_MESSAGE_FLAG_INRANGE))
            {
                f.proximityOut = true;
                return dispatchPenFrame(dev, f, platform);
            }
            return penLeftWindow(dev);

        case WM_POINTERCAPTURECHANGED:
            return penCaptureLost(dev);

        default: // down, update, up
            double oldX = dev.ev.x, oldY = dev.ev.y;
            Pen.State oldState = dev.prevState;
            updatePosition(dev, hwnd, pi.pointerInfo);
            updateAxes(dev, pi);
            Pen.State state = penState(pi);
            dev.ev.state = state;
            enum Pen.State contact = Pen.State.tipDown | Pen.State.eraserDown;
            enum Pen.State buttons = Pen.State.button0 | Pen.State.button1 | Pen.State.button2 | Pen.State.button3;
            f.down = !(oldState & contact) && (state & contact);
            f.up = (oldState & contact) && !(state & contact);
            f.motion = dev.ev.x != oldX || dev.ev.y != oldY || msg == WM_POINTERUPDATE;
            f.buttonsPressed = cast(Pen.State)(state & ~oldState & buttons);
            f.buttonsReleased = cast(Pen.State)(oldState & ~state & buttons);
            return dispatchPenFrame(dev, f, platform);
    }
}
