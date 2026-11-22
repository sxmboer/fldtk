/*
 * The pen driver of the X11 backend, through the X Input extension
 * version 2 (`fl.xinput2`). The dispatch to widgets is `fl.pen`'s.
 *
 * How it works (the design, with what Qt and GTK do and what a real
 * tablet sends, is in `docs/X11_PEN_DRIVER.md`; tested with a Veikk
 * VK1060 Pro and the Wacom X driver):
 *
 * - The X server lists each pen as an input device of its own (a
 *   "slave pointer"): a tablet's stylus and eraser are two devices. A
 *   pointer device with a pressure axis whose name doesn't say it is a
 *   pad or a touch surface counts as a pen; it is an eraser when its
 *   name contains "eraser". The devices are looked up when the first
 *   widget subscribes to pen events, and again when devices come and go
 *   (`XI_HierarchyChanged`).
 * - Each toplevel window asks for the pens' button, motion and leave
 *   events. Every event carries the axes that changed (pressure, tilt);
 *   the driver keeps the last value of each.
 * - XInput2 has no "pen came near / went away" events. With the Wacom X
 *   driver, the device property "Wacom Serial IDs" names the tool near
 *   the tablet, and its changes are the pen coming into range and going
 *   out of it. Without that property, the pen comes into range with its
 *   first event and goes out of it when it leaves the window.
 * - The X server also moves the mouse pointer for the pen and sends the
 *   program the ordinary mouse events, each with the same timestamp as
 *   the pen event, which comes first. A pen no subscriber claims works
 *   as a mouse through those; while a subscriber handles the pen,
 *   `fl.platform_x11` drops them (`isClaimedCopy()`).
 *
 * Not ported: barrel buttons arrive as buttons 2 and 3 when the tablet
 * sends them as pen buttons (some tablets send key presses instead);
 * twist, barrel pressure and the distance from the surface are not
 * read.
 */
module fl.x11_pen_driver;

version (linux):

import core.stdc.config : c_ulong;
import std.string : fromStringz, toLower;
import std.algorithm : canFind;
import fl.pen;
import fl.xinput2;
import fl.xlib : Atom, Display, Window, XInternAtom, XFree, XRootWindow, XDefaultScreen;
import fl.window : FlWindow = Window;
import fl.core : screenScale;
import platformX11 = fl.platform_x11;

/// One pen device: a stylus, an eraser, ...
private final class X11Pen : PenTool
{
    int deviceId;
    int pressureAxis = -1, tiltXAxis = -1, tiltYAxis = -1;
    double[] min, max, last;  // per axis number
    bool wacom;               // has "Wacom Serial IDs": proximity comes from it
    bool inRange;
}

private __gshared X11Pen[] pens_;
private __gshared bool started_;
private __gshared Atom serialIdsAtom_, pressureAtom_, tiltXAtom_, tiltYAtom_;
private __gshared bool claimed_;   // the last pen event was handled by a subscriber
private __gshared c_ulong claimedTime_;

private enum Pen.State buttonBits = Pen.State.button0 | Pen.State.button1 | Pen.State.button2 | Pen.State.button3;

/// What the driver offers: nothing without XInput 2.
package(fl) Pen.Trait traits()
{
    if (!platformX11.xinput2Available()) return Pen.Trait.none;
    return Pen.Trait.driverAvailable | Pen.Trait.penId | Pen.Trait.eraser | Pen.Trait.pressure
        | Pen.Trait.tiltX | Pen.Trait.tiltY | (pens_.length ? Pen.Trait.detected : Pen.Trait.none);
}

/// What pen `penId` (0: the current pen) reports.
package(fl) Pen.Trait penTraits(int penId)
{
    foreach (p; pens_)
        if (penId == 0 ? p is currentPen_ : p.penId == penId) return p.capabilities;
    return Pen.Trait.none;
}

/// The first widget subscribed: the pens are looked up, and every
/// toplevel window shown so far asks for their events.
package(fl) void start()
{
    if (started_) return;
    platformX11.openDisplay();
    if (!platformX11.xinput2Available()) return;
    started_ = true;
    auto display = platformX11.x11Display();
    serialIdsAtom_ = XInternAtom(display, "Wacom Serial IDs", 0);
    pressureAtom_ = XInternAtom(display, "Abs Pressure", 0);
    tiltXAtom_ = XInternAtom(display, "Abs Tilt X", 0);
    tiltYAtom_ = XInternAtom(display, "Abs Tilt Y", 0);

    // devices coming and going, and property changes, on the root window
    ubyte[XIMaskLen!XI_LASTEVENT] bits;
    XISetMask(bits[], XI_HierarchyChanged);
    XISetMask(bits[], XI_PropertyEvent);
    XIEventMask mask = { deviceid: XIAllDevices, mask_len: cast(int) bits.length, mask: bits.ptr };
    XISelectEvents(display, XRootWindow(display, XDefaultScreen(display)), &mask, 1);

    findPens();
}

/// Toplevel window `xid` was made: it asks for the pens' events.
package(fl) void selectWindow(Window xid)
{
    if (!started_ || pens_.length == 0) return;
    ubyte[XIMaskLen!XI_LASTEVENT] bits;
    XISetMask(bits[], XI_ButtonPress);
    XISetMask(bits[], XI_ButtonRelease);
    XISetMask(bits[], XI_Motion);
    XISetMask(bits[], XI_Leave);
    XIEventMask[] masks;
    foreach (p; pens_)
        masks ~= XIEventMask(p.deviceId, cast(int) bits.length, bits.ptr);
    XISelectEvents(platformX11.x11Display(), xid, masks.ptr, cast(int) masks.length);
}

/// Whether a core mouse event with timestamp `time` is the copy of a pen
/// event a subscriber handled, to be dropped.
package(fl) bool isClaimedCopy(c_ulong time)
{
    return claimed_ && time == claimedTime_;
}

/// The event types `handle()` takes.
package(fl) bool isPenEventType(int evtype)
{
    switch (evtype)
    {
        case XI_ButtonPress, XI_ButtonRelease, XI_Motion, XI_Leave,
            XI_HierarchyChanged, XI_PropertyEvent:
            return started_;
        default:
            return false;
    }
}

/// An XInput2 event of a type `isPenEventType()` accepts, its data read
/// from the cookie.
package(fl) void handle(int evtype, void* data)
{
    switch (evtype)
    {
        case XI_HierarchyChanged:
            findPens();
            break;
        case XI_PropertyEvent:
            propertyChanged(cast(XIPropertyEvent*) data);
            break;
        case XI_Leave:
            left(cast(XIEnterEvent*) data);
            break;
        default:
            deviceEvent(evtype, cast(XIDeviceEvent*) data);
            break;
    }
}

// ---- the devices -----------------------------------------------------

private X11Pen penOf(int deviceId)
{
    foreach (p; pens_) if (p.deviceId == deviceId) return p;
    return null;
}

// Looks the pens up (again), keeping what is known of those already
// there, and makes every toplevel window ask for their events.
private void findPens()
{
    auto display = platformX11.x11Display();
    X11Pen[] found;
    int n;
    XIDeviceInfo* infos = XIQueryDevice(display, XIAllDevices, &n);
    foreach (ref info; infos[0 .. n])
    {
        if (info.use != XISlavePointer || !info.enabled) continue;
        string name = fromStringz(info.name).idup.toLower;
        if (name.canFind("pad") || name.canFind("touch") || name.canFind("finger")) continue;

        int pressure = -1, tiltX = -1, tiltY = -1, axes = 0;
        double[] min, max;
        foreach (c; info.classes[0 .. info.num_classes])
        {
            if (c.type != XIValuatorClass) continue;
            auto v = cast(XIValuatorClassInfo*) c;
            if (v.number >= axes)
            {
                axes = v.number + 1;
                min.length = max.length = axes;
            }
            min[v.number] = v.min;
            max[v.number] = v.max;
            if (v.label == pressureAtom_) pressure = v.number;
            else if (v.label == tiltXAtom_) tiltX = v.number;
            else if (v.label == tiltYAtom_) tiltY = v.number;
        }
        if (pressure < 0) continue; // a mouse, a touchpad, ...

        auto pen = penOf(info.deviceid);
        if (pen is null)
        {
            pen = new X11Pen;
            pen.deviceId = info.deviceid;
            pen.penId = info.deviceid;
        }
        pen.pressureAxis = pressure;
        pen.tiltXAxis = tiltX;
        pen.tiltYAxis = tiltY;
        pen.min = min;
        pen.max = max;
        pen.last.length = axes;
        pen.eraser = name.canFind("eraser");
        pen.wacom = toolId(info.deviceid) >= 0;
        pen.capabilities = Pen.Trait.pressure
            | (tiltX >= 0 ? Pen.Trait.tiltX : Pen.Trait.none)
            | (tiltY >= 0 ? Pen.Trait.tiltY : Pen.Trait.none)
            | (pen.eraser ? Pen.Trait.eraser : Pen.Trait.none);
        found ~= pen;
    }
    if (infos !is null) XIFreeDeviceInfo(infos);

    // a pen in range that is gone goes out of range first
    foreach (old; pens_)
        if (old.inRange && !found.canFind(old)) outOfRange(old);
    pens_ = found;

    foreach (xid; platformX11.toplevelXids()) selectWindow(xid);
}

// The tool near the tablet according to the device's "Wacom Serial IDs"
// property: its id (0 when none is), or -1 when the device has no such
// property.
private long toolId(int deviceId)
{
    Atom type;
    int format;
    c_ulong items, after;
    ubyte* data;
    if (XIGetProperty(platformX11.x11Display(), deviceId, serialIdsAtom_, 0, 5, 0, 0 /* any type */,
            &type, &format, &items, &after, &data) != 0)
        return -1;
    scope (exit) if (data !is null) XFree(data);
    if (format != 32 || items < 5) return -1;
    auto ids = cast(uint*) data;
    // the tool's id, or on some tablets only its serial number
    return ids[4] ? ids[4] : ids[3];
}

// ---- the events ------------------------------------------------------

private void dispatch(X11Pen pen, ref PenFrame f, c_ulong time)
{
    PenPlatform platform;
    platform.sendsMouseEvents = true; // the X server moves the mouse for the pen
    claimed_ = dispatchPenFrame(pen, f, platform);
    claimedTime_ = time;
}

private void outOfRange(X11Pen pen)
{
    pen.inRange = false;
    PenFrame f;
    f.proximityOut = true;
    pen.ev.state = cast(Pen.State)(pen.ev.state & buttonBits);
    dispatch(pen, f, 0);
    pen.focusWin = null;
}

private void propertyChanged(XIPropertyEvent* e)
{
    if (e.property != serialIdsAtom_) return;
    auto pen = penOf(e.deviceid);
    if (pen is null) return;
    long tool = e.what == XIPropertyDeleted ? 0 : toolId(pen.deviceId);
    if (tool > 0 && !pen.inRange)
    {
        pen.inRange = true;
        pen.ev.state = (pen.eraser ? Pen.State.eraserHovers : Pen.State.tipHovers) | (pen.ev.state & buttonBits);
        PenFrame f;
        f.proximityIn = true;
        dispatch(pen, f, e.time);
    }
    else if (tool == 0 && pen.inRange)
        outOfRange(pen);
}

private void left(XIEnterEvent* e)
{
    auto pen = penOf(e.sourceid);
    if (pen is null || !pen.inRange) return;
    if (e.detail == XINotifyInferior || e.mode == XINotifyGrab) return;
    if (pen.wacom)
    {
        // still in range, only no longer over this window
        claimed_ = penLeftWindow(pen);
        claimedTime_ = e.time;
        pen.focusWin = null;
    }
    else
        outOfRange(pen);
}

private void deviceEvent(int evtype, XIDeviceEvent* e)
{
    auto pen = penOf(e.sourceid);
    if (pen is null) return;
    FlWindow top = platformX11.windowOfXid(e.event);
    if (top is null) return;
    Pen.State bit;
    if (evtype != XI_Motion)
    {
        switch (e.detail)
        {
            case 1: break;                          // the tip
            case 2: bit = Pen.State.button0; break; // lower barrel button
            case 3: bit = Pen.State.button1; break; // upper barrel button
            default: return;                        // wheel buttons: mouse events
        }
    }

    // the axes that changed, in axis order
    int i = 0;
    foreach (axis; 0 .. e.valuators.mask_len * 8)
        if (e.valuators.mask[axis >> 3] & (1 << (axis & 7)))
        {
            double v = e.valuators.values[i++];
            if (axis < pen.last.length) pen.last[axis] = v;
        }

    float scale = screenScale(top.screenNum());
    pen.ev.x = e.event_x / scale;
    pen.ev.y = e.event_y / scale;
    pen.ev.rx = pen.ev.x + top.x();
    pen.ev.ry = pen.ev.y + top.y();
    pen.ev.pressure = normalized(pen, pen.pressureAxis);
    // degrees, -64 to 63 -> about -0.7 to 0.7; X negated as the Wayland driver does
    if (pen.tiltXAxis >= 0) pen.ev.tiltX = -pen.last[pen.tiltXAxis] / 90.0;
    if (pen.tiltYAxis >= 0) pen.ev.tiltY = -pen.last[pen.tiltYAxis] / 90.0;
    pen.focusWin = top;

    Pen.State hover = pen.eraser ? Pen.State.eraserHovers : Pen.State.tipHovers;
    Pen.State down = pen.eraser ? Pen.State.eraserDown : Pen.State.tipDown;
    PenFrame f;
    if (!pen.inRange)
    {
        pen.inRange = true;
        f.proximityIn = true;
        pen.ev.state = hover | (pen.ev.state & buttonBits);
    }

    switch (evtype)
    {
        case XI_ButtonPress:
            if (e.detail == 1)
            {
                pen.ev.state = down | (pen.ev.state & buttonBits);
                f.down = true;
            }
            else
            {
                pen.ev.state |= bit;
                f.buttonsPressed |= bit;
            }
            break;
        case XI_ButtonRelease:
            if (e.detail == 1)
            {
                pen.ev.state = hover | (pen.ev.state & buttonBits);
                f.up = true;
            }
            else
            {
                pen.ev.state = cast(Pen.State)(pen.ev.state & ~bit);
                f.buttonsReleased |= bit;
            }
            break;
        default:
            f.motion = true;
            break;
    }
    dispatch(pen, f, e.time);
}

private double normalized(X11Pen pen, int axis)
{
    if (axis < 0) return 1; // fl.pen: 1 when not reported
    double range = pen.max[axis] - pen.min[axis];
    if (range <= 0) return 1;
    double v = (pen.last[axis] - pen.min[axis]) / range;
    return v < 0 ? 0 : v > 1 ? 1 : v;
}
