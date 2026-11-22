/*
 * `extern(C)` bindings for the part of the X Input extension version 2
 * (libXi, `X11/extensions/XInput2.h`) fldtk uses: touchscreen contacts
 * (XInput 2.2) and touchpad gestures (XInput 2.4, X.Org server 21.1 and
 * later) for `fl.platform_x11`, the devices, their events and
 * properties for the pen driver `fl.x11_pen_driver`, plus Xlib's
 * generic-event cookie calls they arrive through. Infrastructure, like
 * `fl.xlib`.
 *
 * Linux only (`version (linux)`); links against `libXi`.
 */
module fl.xinput2;

version (linux):

import core.stdc.config : c_long, c_ulong;
import fl.xlib : Atom, Display, Window, Bool;

extern (C) nothrow @nogc:

alias Time = c_ulong;

/// `GenericEvent`: an event of an extension, read through its cookie.
enum int GenericEvent = 35;

struct XGenericEventCookie
{
    int type;
    c_ulong serial;
    Bool send_event;
    Display* display;
    int extension;
    int evtype;
    uint cookie;
    void* data;
}

Bool XGetEventData(Display* dpy, XGenericEventCookie* cookie);
void XFreeEventData(Display* dpy, XGenericEventCookie* cookie);
Bool XQueryExtension(Display* display, const(char)* name, int* major_opcode_return,
    int* first_event_return, int* first_error_return);

// event types (XI2.h)
enum int XI_ButtonPress = 4;
enum int XI_ButtonRelease = 5;
enum int XI_Motion = 6;
enum int XI_Enter = 7;
enum int XI_Leave = 8;
enum int XI_HierarchyChanged = 11;
enum int XI_PropertyEvent = 12;
enum int XI_TouchBegin = 18;
enum int XI_TouchUpdate = 19;
enum int XI_TouchEnd = 20;
enum int XI_GesturePinchBegin = 27;
enum int XI_GesturePinchUpdate = 28;
enum int XI_GesturePinchEnd = 29;
enum int XI_GestureSwipeBegin = 30;
enum int XI_GestureSwipeUpdate = 31;
enum int XI_GestureSwipeEnd = 32;
enum int XI_LASTEVENT = XI_GestureSwipeEnd;

enum int XIAllDevices = 0;
enum int XIAllMasterDevices = 1;

/// `XIDeviceInfo.use`: a device that moves the master pointer.
enum int XISlavePointer = 3;

/// `XIAnyClassInfo.type`: an axis.
enum int XIValuatorClass = 2;

/// `XIPropertyEvent.what`: the property was deleted.
enum int XIPropertyDeleted = 0;

/// `XIEnterEvent.detail`: the pointer went into a child window.
enum int XINotifyInferior = 2;
/// `XIEnterEvent.mode`: the crossing comes from a grab starting.
enum int XINotifyGrab = 1;

/// A gesture ended without completing (`flags` of a gesture's end event).
enum int XIGesturePinchEventCancelled = 1 << 0;
enum int XIGestureSwipeEventCancelled = 1 << 0;

/// Sets `event`'s bit in an event mask (the `XISetMask()` macro).
void XISetMask(ubyte[] mask, int event) pure @safe
{
    mask[event >> 3] |= cast(ubyte)(1 << (event & 7));
}

/// The length of a mask holding every event up to `event` (`XIMaskLen()`).
enum int XIMaskLen(int event) = (event >> 3) + 1;

struct XIEventMask
{
    int deviceid;
    int mask_len;
    ubyte* mask;
}

struct XIModifierState
{
    int base;
    int latched;
    int locked;
    int effective;
}

alias XIGroupState = XIModifierState;

struct XIButtonState
{
    int mask_len;
    ubyte* mask;
}

struct XIValuatorState
{
    int mask_len;
    ubyte* mask;
    double* values;
}

/// Touch events, and a pen's button and motion events.
struct XIDeviceEvent
{
    int type;
    c_ulong serial;
    Bool send_event;
    Display* display;
    int extension;
    int evtype;
    Time time;
    int deviceid;
    int sourceid;
    int detail;         // the touch's number
    Window root;
    Window event;
    Window child;
    double root_x;
    double root_y;
    double event_x;
    double event_y;
    int flags;
    XIButtonState buttons;
    XIValuatorState valuators;
    XIModifierState mods;
    XIGroupState group;
}

struct XIGesturePinchEvent
{
    int type;
    c_ulong serial;
    Bool send_event;
    Display* display;
    int extension;
    int evtype;
    Time time;
    int deviceid;
    int sourceid;
    int detail;         // the number of fingers
    Window root;
    Window event;
    Window child;
    double root_x;
    double root_y;
    double event_x;
    double event_y;
    double delta_x;
    double delta_y;
    double delta_unaccel_x;
    double delta_unaccel_y;
    double scale;       // since the gesture began
    double delta_angle; // degrees, since the last event
    int flags;
    XIModifierState mods;
    XIGroupState group;
}

struct XIGestureSwipeEvent
{
    int type;
    c_ulong serial;
    Bool send_event;
    Display* display;
    int extension;
    int evtype;
    Time time;
    int deviceid;
    int sourceid;
    int detail;         // the number of fingers
    Window root;
    Window event;
    Window child;
    double root_x;
    double root_y;
    double event_x;
    double event_y;
    double delta_x;
    double delta_y;
    double delta_unaccel_x;
    double delta_unaccel_y;
    int flags;
    XIModifierState mods;
    XIGroupState group;
}

/// A pointer leaving or entering a window.
struct XIEnterEvent
{
    int type;
    c_ulong serial;
    Bool send_event;
    Display* display;
    int extension;
    int evtype;
    Time time;
    int deviceid;
    int sourceid;
    int detail;
    Window root;
    Window event;
    Window child;
    double root_x;
    double root_y;
    double event_x;
    double event_y;
    int mode;
    Bool focus;
    Bool same_screen;
    XIButtonState buttons;
    XIModifierState mods;
    XIGroupState group;
}

/// A device property changed.
struct XIPropertyEvent
{
    int type;
    c_ulong serial;
    Bool send_event;
    Display* display;
    int extension;
    int evtype;
    Time time;
    int deviceid;
    Atom property;
    int what;
}

struct XIAnyClassInfo
{
    int type;
    int sourceid;
}

/// An axis of a device (`type == XIValuatorClass`).
struct XIValuatorClassInfo
{
    int type;
    int sourceid;
    int number;
    Atom label;
    double min;
    double max;
    double value;
    int resolution;
    int mode;
}

struct XIDeviceInfo
{
    int deviceid;
    char* name;
    int use;
    int attachment;
    Bool enabled;
    int num_classes;
    XIAnyClassInfo** classes;
}

int XISelectEvents(Display* dpy, Window win, XIEventMask* masks, int num_masks);
XIDeviceInfo* XIQueryDevice(Display* dpy, int deviceid, int* ndevices_return);
void XIFreeDeviceInfo(XIDeviceInfo* info);
/// Format-32 items come back as 32-bit values, not `long`s.
int XIGetProperty(Display* display, int deviceid, Atom property, c_long offset, c_long length,
    Bool delete_property, Atom type, Atom* type_return, int* format_return,
    c_ulong* num_items_return, c_ulong* bytes_after_return, ubyte** data);
int XIQueryVersion(Display* dpy, int* major_version_inout, int* minor_version_inout);
