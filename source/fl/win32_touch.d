/*
 * Touch and gestures on Windows, beyond FLTK (see `fl.touch`).
 *
 * Windows itself turns a touchscreen finger into the mouse and
 * recognizes its gestures (`WM_GESTURE`, Windows 7 and later): fldtk
 * asks each window for pinch, turn and two-finger pan, with
 * single-finger pan off so one finger keeps acting as the mouse
 * (`configureGestures()`), and turns them into `Event.zoomGesture`,
 * `Event.rotateGesture` and scrolling (`handleGesture()`). Raw contacts
 * for widgets subscribed with `fl.touch.Touch.subscribe()` come from
 * the pointer messages (`WM_POINTER*` of type touch, Windows 8 and
 * later; `handlePointerMessage()`): a contact a widget takes is handled
 * here, so Windows makes no mouse events or gestures of it.
 *
 * A precision touchpad's pinch reaches programs as Ctrl + mouse wheel
 * on Windows, so it is no zoom gesture here.
 */
module fl.win32_touch;

version (Windows):

import core.sys.windows.windows;
import fl.win32_pointer;
import fl.window : FlWindow = Window;
import fl.enumerations : Event, GesturePhase;
import fl.core : screenScale, setWheelDelta, dispatch, eX_, eY_, eXRoot_, eYRoot_, eDx_, eDy_;
import touchEngine = fl.touch;
import platformWin32 = fl.platform_win32;

/// Asks Windows for pinch, turn and two-finger pan on window `hwnd`,
/// and not single-finger pan, so one finger acts as the mouse.
package(fl) void configureGestures(HWND hwnd)
{
    if (!haveGestureApi()) return;
    GESTURECONFIG[3] config = [
        GESTURECONFIG(GID_ZOOM, GC_ZOOM, 0),
        GESTURECONFIG(GID_ROTATE, GC_ROTATE, 0),
        GESTURECONFIG(GID_PAN, GC_PAN | GC_PAN_WITH_INERTIA,
            GC_PAN_WITH_SINGLE_FINGER_VERTICALLY | GC_PAN_WITH_SINGLE_FINGER_HORIZONTALLY | GC_PAN_WITH_GUTTER),
    ];
    setGestureConfig_(hwnd, 0, cast(UINT) config.length, config.ptr, GESTURECONFIG.sizeof);
}

/// The toplevel window of `hwnd` and the screen point `screen` in its
/// FLTK units.
private FlWindow topCoords(HWND hwnd, POINT screen, out double x, out double y)
{
    FlWindow win = platformWin32.windowOfHwnd(hwnd);
    if (win is null) return null;
    ScreenToClient(hwnd, &screen);
    int dx = 0, dy = 0;
    FlWindow top = win;
    while (top.parent !is null && top.window() !is null)
    {
        dx += top.x();
        dy += top.y();
        top = top.window();
    }
    float f = screenScale(top.screenNum());
    x = screen.x / f + dx;
    y = screen.y / f + dy;
    return top;
}

// the gesture in progress
private double lastZoom_ = 0, lastAngle_ = 0;
private double lastPanX_, lastPanY_;
private bool zoomStarted_, rotateStarted_;

/**
 * `WM_GESTURE`: a zoom becomes `Event.zoomGesture`, a turn
 * `Event.rotateGesture` and a two-finger pan scrolling. Returns whether
 * it was handled; the window procedure then returns 0, else it calls
 * `DefWindowProcW()`.
 */
package(fl) bool handleGesture(HWND hwnd, WPARAM wParam, LPARAM lParam)
{
    if (!haveGestureApi()) return false;
    GESTUREINFO gi;
    gi.cbSize = GESTUREINFO.sizeof;
    if (!getGestureInfo_(cast(HANDLE) lParam, &gi)) return false;
    double x, y;
    FlWindow top = topCoords(hwnd, POINT(gi.ptsLocation.x, gi.ptsLocation.y), x, y);
    if (top is null) return false;
    bool begin = (gi.dwFlags & GF_BEGIN) != 0, end = (gi.dwFlags & GF_END) != 0;
    bool handled = true;
    switch (gi.dwID)
    {
        case GID_ZOOM: // the distance between the fingers
        {
            double d = cast(double) gi.ullArguments;
            if (begin)
            {
                lastZoom_ = d;
                zoomStarted_ = true;
                touchEngine.sendGesture(Event.zoomGesture, top, x, y, GesturePhase.begin, 2, 1);
            }
            else if (zoomStarted_ && lastZoom_ > 0 && d > 0)
            {
                touchEngine.sendGesture(Event.zoomGesture, top, x, y,
                    end ? GesturePhase.end : GesturePhase.update, 2, cast(float)(d / lastZoom_));
                lastZoom_ = d;
            }
            if (end) zoomStarted_ = false;
            break;
        }
        case GID_ROTATE: // radians from the start, encoded (GID_ROTATE_ANGLE_FROM_ARGUMENT)
        {
            import std.math : PI;
            double a = cast(double) gi.ullArguments / 65535.0 * 4.0 * PI - 2.0 * PI;
            if (begin)
            {
                lastAngle_ = 0;
                rotateStarted_ = true;
                touchEngine.sendGesture(Event.rotateGesture, top, x, y, GesturePhase.begin, 2, 1, 0);
            }
            else if (rotateStarted_)
            {
                // Windows counts counterclockwise; fldtk clockwise
                double turn = -(a - lastAngle_) * 180 / PI;
                touchEngine.sendGesture(Event.rotateGesture, top, x, y,
                    end ? GesturePhase.end : GesturePhase.update, 2, 1, cast(float) turn);
                lastAngle_ = a;
            }
            if (end) rotateStarted_ = false;
            break;
        }
        case GID_PAN: // two fingers moving together: scrolling, the content following them
        {
            if (!begin)
            {
                eX_ = cast(int) x;
                eY_ = cast(int) y;
                eXRoot_ = cast(int)(x + top.x());
                eYRoot_ = cast(int)(y + top.y());
                setWheelDelta(cast(float)(-(x - lastPanX_) / 10), cast(float)(-(y - lastPanY_) / 10));
                if (eDx_ || eDy_) dispatch(Event.mouseWheel, top);
            }
            lastPanX_ = x;
            lastPanY_ = y;
            break;
        }
        default:
            handled = false; // GID_BEGIN, GID_END and the taps go to DefWindowProcW()
            break;
    }
    if (handled) closeGestureInfoHandle_(cast(HANDLE) lParam);
    return handled;
}

/**
 * A `WM_POINTER*` message of a touch contact: given to `fl.touch`, which
 * hands it to a subscribed widget under it, if one takes it. Returns
 * whether a widget has the contact: the window procedure then returns
 * without `DefWindowProcW()`, so Windows makes no mouse event or
 * gesture of it.
 */
package(fl) bool handlePointerMessage(HWND hwnd, UINT msg, WPARAM wParam)
{
    if (!isPointerMessage(msg) || !havePointerApi() || getPointerInfo_ is null) return false;
    UINT32 id = LOWORD(wParam);
    DWORD type;
    if (!getPointerType_(id, &type) || type != PT_TOUCH) return false;
    POINTER_INFO pi;
    if (!getPointerInfo_(id, &pi)) return false;
    double x, y;
    switch (msg)
    {
        case WM_POINTERDOWN:
        {
            FlWindow top = topCoords(hwnd, pi.ptPixelLocation, x, y);
            return top !is null && touchEngine.touchDown(top, id, x, y, true);
        }
        case WM_POINTERUPDATE:
        {
            FlWindow top = topCoords(hwnd, pi.ptPixelLocation, x, y);
            return top !is null && touchEngine.touchMotion(id, x, y);
        }
        case WM_POINTERUP:
            return touchEngine.touchUp(id);
        default:
            return false;
    }
}
