/*
 * The parts of Windows' pointer input (Windows 8) and gesture (Windows
 * 7) APIs fldtk uses (`winuser.h`), which druntime doesn't declare:
 * shared by `fl.win32_pen_driver` and `fl.win32_touch`. The functions
 * are looked up in user32.dll at run time, so a program still starts on
 * a Windows without them.
 */
module fl.win32_pointer;

version (Windows):

import core.sys.windows.windows;

package(fl) enum : UINT
{
    WM_POINTERUPDATE = 0x0245,
    WM_POINTERDOWN = 0x0246,
    WM_POINTERUP = 0x0247,
    WM_POINTERENTER = 0x0249,
    WM_POINTERLEAVE = 0x024A,
    WM_POINTERCAPTURECHANGED = 0x024C,
}

package(fl) enum DWORD PT_PEN = 3; // POINTER_INPUT_TYPE

package(fl) enum : UINT32
{
    POINTER_FLAG_INCONTACT = 0x0004,
    POINTER_FLAG_SECONDBUTTON = 0x0020,
    POINTER_FLAG_THIRDBUTTON = 0x0040,
    POINTER_FLAG_FOURTHBUTTON = 0x0080,
    POINTER_FLAG_FIFTHBUTTON = 0x0100,
}

package(fl) enum UINT32 POINTER_MESSAGE_FLAG_INRANGE = 0x0002; // in HIWORD(wParam)

package(fl) enum : UINT32
{
    PEN_FLAG_INVERTED = 0x0002, // the eraser end is towards the screen
    PEN_FLAG_ERASER = 0x0004,   // the eraser end touches it
    PEN_MASK_PRESSURE = 0x0001,
    PEN_MASK_ROTATION = 0x0002,
    PEN_MASK_TILT_X = 0x0004,
    PEN_MASK_TILT_Y = 0x0008,
}

package(fl) struct POINTER_INFO
{
    DWORD pointerType;
    UINT32 pointerId;
    UINT32 frameId;
    UINT32 pointerFlags;
    HANDLE sourceDevice;
    HWND hwndTarget;
    POINT ptPixelLocation;
    POINT ptHimetricLocation;
    POINT ptPixelLocationRaw;
    POINT ptHimetricLocationRaw;
    DWORD dwTime;
    UINT32 historyCount;
    INT32 InputData;
    DWORD dwKeyStates;
    ulong PerformanceCount;
    int ButtonChangeType;
}

package(fl) struct POINTER_PEN_INFO
{
    POINTER_INFO pointerInfo;
    UINT32 penFlags;
    UINT32 penMask;
    UINT32 pressure;    // 0 to 1024
    UINT32 rotation;    // 0 to 359 degrees
    INT32 tiltX;        // -90 to 90 degrees
    INT32 tiltY;
}

package(fl) alias GetPointerTypeFn = extern (Windows) BOOL function(UINT32, DWORD*) nothrow @nogc;
package(fl) alias GetPointerPenInfoFn = extern (Windows) BOOL function(UINT32, POINTER_PEN_INFO*) nothrow @nogc;

package(fl) __gshared GetPointerTypeFn getPointerType_;
package(fl) __gshared GetPointerPenInfoFn getPointerPenInfo_;
package(fl) __gshared bool apiLooked_;

/// Whether this Windows has the pointer input API (Windows 8 and later).
package(fl) bool havePointerApi()
{
    if (!apiLooked_)
    {
        apiLooked_ = true;
        HMODULE user32 = GetModuleHandleA("user32.dll");
        if (user32 !is null)
        {
            getPointerType_ = cast(GetPointerTypeFn) GetProcAddress(user32, "GetPointerType");
            getPointerPenInfo_ = cast(GetPointerPenInfoFn) GetProcAddress(user32, "GetPointerPenInfo");
            getPointerInfo_ = cast(GetPointerInfoFn) GetProcAddress(user32, "GetPointerInfo");
        }
    }
    return getPointerType_ !is null && getPointerPenInfo_ !is null;
}


/// `WM_POINTER*` messages: the pointer's number is in the low word.
package(fl) bool isPointerMessage(UINT msg)
{
    switch (msg)
    {
        case WM_POINTERENTER, WM_POINTERLEAVE, WM_POINTERDOWN, WM_POINTERUP,
            WM_POINTERUPDATE, WM_POINTERCAPTURECHANGED:
            return true;
        default:
            return false;
    }
}

package(fl) enum DWORD PT_TOUCH = 2; // POINTER_INPUT_TYPE

package(fl) alias GetPointerInfoFn = extern (Windows) BOOL function(UINT32, POINTER_INFO*) nothrow @nogc;
package(fl) __gshared GetPointerInfoFn getPointerInfo_;

// ---- gestures (Windows 7)

package(fl) enum UINT WM_GESTURE = 0x0119;

package(fl) enum : DWORD
{
    GID_BEGIN = 1,
    GID_END = 2,
    GID_ZOOM = 3,
    GID_PAN = 4,
    GID_ROTATE = 5,
}

package(fl) enum : DWORD
{
    GF_BEGIN = 0x0001,
    GF_INERTIA = 0x0002,
    GF_END = 0x0004,
}

package(fl) enum : DWORD
{
    GC_ZOOM = 0x0001,
    GC_ROTATE = 0x0001,
    GC_PAN = 0x0001,
    GC_PAN_WITH_SINGLE_FINGER_VERTICALLY = 0x0002,
    GC_PAN_WITH_SINGLE_FINGER_HORIZONTALLY = 0x0004,
    GC_PAN_WITH_GUTTER = 0x0008,
    GC_PAN_WITH_INERTIA = 0x0010,
}

package(fl) struct GESTUREINFO
{
    UINT cbSize;
    DWORD dwFlags;
    DWORD dwID;
    HWND hwndTarget;
    POINTS ptsLocation;     // screen coordinates
    DWORD dwInstanceID;
    DWORD dwSequenceID;
    ulong ullArguments;
    UINT cbExtraArgs;
}

package(fl) struct GESTURECONFIG
{
    DWORD dwID;
    DWORD dwWant;
    DWORD dwBlock;
}

package(fl) alias GetGestureInfoFn = extern (Windows) BOOL function(HANDLE, GESTUREINFO*) nothrow @nogc;
package(fl) alias CloseGestureInfoHandleFn = extern (Windows) BOOL function(HANDLE) nothrow @nogc;
package(fl) alias SetGestureConfigFn = extern (Windows) BOOL function(HWND, DWORD, UINT, GESTURECONFIG*, UINT) nothrow @nogc;

package(fl) __gshared GetGestureInfoFn getGestureInfo_;
package(fl) __gshared CloseGestureInfoHandleFn closeGestureInfoHandle_;
package(fl) __gshared SetGestureConfigFn setGestureConfig_;
private __gshared bool gestureApiLooked_;

/// Whether this Windows has the gesture API (Windows 7 and later).
package(fl) bool haveGestureApi()
{
    if (!gestureApiLooked_)
    {
        gestureApiLooked_ = true;
        HMODULE user32 = GetModuleHandleA("user32.dll");
        if (user32 !is null)
        {
            getGestureInfo_ = cast(GetGestureInfoFn) GetProcAddress(user32, "GetGestureInfo");
            closeGestureInfoHandle_ = cast(CloseGestureInfoHandleFn) GetProcAddress(user32, "CloseGestureInfoHandle");
            setGestureConfig_ = cast(SetGestureConfigFn) GetProcAddress(user32, "SetGestureConfig");
        }
    }
    return getGestureInfo_ !is null && closeGestureInfoHandle_ !is null && setGestureConfig_ !is null;
}
