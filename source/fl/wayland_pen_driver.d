/*
 * Pen input on Wayland: port of `src/drivers/Wayland/
 * Fl_Wayland_Pen_Driver.{H,cxx}`, through the tablet protocol
 * (`zwp_tablet_v2`, `fl.tablet_protocol`). The dispatch to widgets is
 * `fl.pen`'s, shared with the Windows driver.
 *
 * The tablet seat is made when the first widget subscribes to pen
 * events (`startTablets()`), as in FLTK: until then the compositor
 * turns the pen into the mouse for this program. Once it exists, the
 * compositor sends the pen's events through the protocol only, so what
 * no subscriber claims is turned into mouse events here (`fl.pen`'s
 * dispatch).
 *
 * The protocol splits a pen's data over many events (motion, pressure,
 * tilt, down, buttons, ...), each tool's ended by a `frame` event: the
 * data is gathered per tool and dispatched at `frame`.
 *
 * Differences from FLTK: over the title bar fldtk draws (`fl.
 * wayland_decoration`), the pen moves, resizes, minimizes, maximizes
 * and closes the window as the mouse does (FLTK has a proof of concept
 * moving a window by libdecor's GTK title bar only); the tablet's
 * `bustype` event (tablet protocol version 2) is accepted and ignored.
 *
 * Only compiled into a build with Wayland support
 * (`version (FLDTK_HAVE_WAYLAND)`).
 */
module fl.wayland_pen_driver;

version (FLDTK_HAVE_WAYLAND):

import fl.tablet_protocol;
import fl.wayland_client;
import fl.wayland_protocol;
import fl.pen;
import fl.window : FlWindow = Window;
import fl.core : screenScale;
import platformWayland = fl.platform_wayland;

// linux/input-event-codes.h
private enum uint BTN_STYLUS = 0x14b;   // first barrel button
private enum uint BTN_STYLUS2 = 0x14c;  // second barrel button
private enum uint BTN_STYLUS3 = 0x149;  // third barrel button (uncommon)

/// One tablet tool (a pen, an eraser, an airbrush, ...).
private final class WaylandTool : PenTool
{
    zwp_tablet_tool_v2* tool;
    uint type = ZWP_TABLET_TOOL_V2_TYPE_PEN;
    ulong hardwareSerial;
    wl_surface* focusSurface;
    uint serial;            // of the last tip down: what moving or resizing a window needs
    uint time;              // of the last frame
    wl_fixed_t surfaceX, surfaceY; // the last position on focusSurface
    PenFrame frame;         // what happened since the last frame
}

private __gshared zwp_tablet_manager_v2* manager_;
private __gshared zwp_tablet_seat_v2* tabletSeat_;
private WaylandTool[] tools_;
private int nextPenId_ = 1;

/// The compositor offers the tablet protocol (called from the registry).
package(fl) void setTabletManager(zwp_tablet_manager_v2* manager)
{
    manager_ = manager;
}

/// Makes the tablet seat, so pen events come through the tablet protocol
/// -- FLTK's `Wayland_Driver::subscribe()` for the first subscriber.
package(fl) void startTablets()
{
    if (tabletSeat_ !is null) return;
    platformWayland.openDisplay();
    auto seat = platformWayland.waylandSeat();
    if (manager_ is null || seat is null) return;
    tabletSeat_ = zwp_tablet_manager_v2_get_tablet_seat(manager_, seat);
    zwp_tablet_seat_v2_add_listener(tabletSeat_, &seatListener, null);
}

/// Ported from `Wayland_Driver::traits()`.
package(fl) Pen.Trait traits()
{
    if (tabletSeat_ is null) return Pen.Trait.none;
    return Pen.Trait.driverAvailable | Pen.Trait.penId | Pen.Trait.eraser | Pen.Trait.pressure
        | Pen.Trait.barrelPressure | Pen.Trait.tiltX | Pen.Trait.tiltY | Pen.Trait.twist
        | (tools_.length ? Pen.Trait.detected : Pen.Trait.none);
}

/// Ported from `Wayland_Driver::pen_traits()`.
package(fl) Pen.Trait penTraits(int penId)
{
    foreach (t; tools_)
        if (penId == 0 ? t is currentPen_ : t.penId == penId) return t.capabilities;
    return Pen.Trait.none;
}

/// Window `surface` is being destroyed: a pen over it forgets it, and
/// a widget of it the pen pushed or is over is let go -- FLTK's
/// `fl_wayland_tablet_surface_destroyed()`.
package(fl) void surfaceDestroyed(wl_surface* surface)
{
    if (surface is null) return;
    foreach (t; tools_)
    {
        if (t.focusSurface !is surface) continue;
        FlWindow closing = t.focusWin;
        if (belowPen_ !is null && belowPen_.topWindow() is closing)
        {
            import fl.enumerations : Event;
            import fl.core : belowmouse;
            belowPen_.handle(Event.penLeave);
            belowPen_ = null;
            belowmouse(null);
        }
        if (penPushed_ !is null && penPushed_.topWindow() is closing)
        {
            import fl.core : pushed;
            pushed(null);
            penPushed_ = null;
        }
        t.focusSurface = null;
        t.focusWin = null;
        t.frame = PenFrame.init;
    }
}

// ---- the tool's events, gathered until its frame

/// Sets `tool`'s position from surface coordinates -- FLTK's
/// `coords_from_surface()`: in the toplevel window's FLTK units.
private void coordsFromSurface(WaylandTool tool, wl_fixed_t sx, wl_fixed_t sy)
{
    if (tool.focusSurface is null) return;
    FlWindow win = platformWayland.windowOfSurfaceWidget(tool.focusSurface);
    if (win is null) return;
    int dx = 0, dy = 0;
    FlWindow top = win;
    while (top.parent !is null && top.window() !is null)
    {
        dx += top.x();
        dy += top.y();
        top = top.window();
    }
    float f = screenScale(top.screenNum());
    tool.ev.x = wl_fixed_to_double(sx) / f + dx;
    tool.ev.y = wl_fixed_to_double(sy) / f + dy;
    tool.ev.rx = tool.ev.x + top.x();
    tool.ev.ry = tool.ev.y + top.y();
    tool.focusWin = top;
}

private enum Pen.State buttonBits = Pen.State.button0 | Pen.State.button1 | Pen.State.button2 | Pen.State.button3;

extern (C) private void toolType(void* data, zwp_tablet_tool_v2* t, uint type) nothrow
{
    (cast(WaylandTool) data).type = type;
}

extern (C) private void toolHardwareSerial(void* data, zwp_tablet_tool_v2* t, uint hi, uint lo) nothrow
{
    auto tool = cast(WaylandTool) data;
    tool.hardwareSerial = (cast(ulong) hi << 32) | lo;
    // a positive pen number; one counted up when there is no serial
    tool.penId = tool.hardwareSerial ? cast(int)(tool.hardwareSerial & 0x7fffffff) : nextPenId_++;
}

extern (C) private void toolHardwareIdWacom(void* data, zwp_tablet_tool_v2* t, uint hi, uint lo) nothrow { }

extern (C) private void toolCapability(void* data, zwp_tablet_tool_v2* t, uint cap) nothrow
{
    auto tool = cast(WaylandTool) data;
    switch (cap)
    {
        case ZWP_TABLET_TOOL_V2_CAPABILITY_PRESSURE: tool.capabilities |= Pen.Trait.pressure; break;
        case ZWP_TABLET_TOOL_V2_CAPABILITY_TILT: tool.capabilities |= Pen.Trait.tiltX | Pen.Trait.tiltY; break;
        case ZWP_TABLET_TOOL_V2_CAPABILITY_ROTATION: tool.capabilities |= Pen.Trait.twist; break;
        case ZWP_TABLET_TOOL_V2_CAPABILITY_SLIDER: tool.capabilities |= Pen.Trait.barrelPressure; break;
        case ZWP_TABLET_TOOL_V2_CAPABILITY_DISTANCE: tool.capabilities |= Pen.Trait.proximity; break;
        default: break; // the wheel isn't part of the pen API
    }
}

extern (C) private void toolDone(void* data, zwp_tablet_tool_v2* t) nothrow
{
    auto tool = cast(WaylandTool) data;
    if (tool.penId == 0) tool.penId = nextPenId_++;
    tool.capabilities |= Pen.Trait.driverAvailable | Pen.Trait.penId;
    tool.eraser = tool.type == ZWP_TABLET_TOOL_V2_TYPE_ERASER;
    if (tool.eraser) tool.capabilities |= Pen.Trait.eraser;
    tool.ev.penId = tool.penId;
}

extern (C) private void toolRemoved(void* data, zwp_tablet_tool_v2* t) nothrow
{
    auto tool = cast(WaylandTool) data;
    if (currentPen_ is tool) currentPen_ = null;
    import std.algorithm : remove;
    import std.algorithm.searching : countUntil;
    auto i = tools_.countUntil!((e) => e is tool);
    if (i >= 0) tools_ = tools_.remove(i);
    zwp_tablet_tool_v2_destroy(t);
}

extern (C) private void toolProximityIn(void* data, zwp_tablet_tool_v2* t, uint serial,
    zwp_tablet_v2* tablet, wl_surface* surface) nothrow
{
    auto tool = cast(WaylandTool) data;
    tool.focusSurface = surface;
    platformWayland.guardedCall({ tool.focusWin = platformWayland.windowOfSurfaceWidget(surface); });
    tool.frame.proximityIn = true;
    tool.ev.state = (tool.eraser ? Pen.State.eraserHovers : Pen.State.tipHovers) | (tool.ev.state & buttonBits);
}

extern (C) private void toolProximityOut(void* data, zwp_tablet_tool_v2* t) nothrow
{
    (cast(WaylandTool) data).frame.proximityOut = true;
}

extern (C) private void toolDown(void* data, zwp_tablet_tool_v2* t, uint serial) nothrow
{
    auto tool = cast(WaylandTool) data;
    tool.serial = serial;
    tool.ev.state = (tool.eraser ? Pen.State.eraserDown : Pen.State.tipDown) | (tool.ev.state & buttonBits);
    tool.frame.down = true;
}

extern (C) private void toolUp(void* data, zwp_tablet_tool_v2* t) nothrow
{
    auto tool = cast(WaylandTool) data;
    tool.ev.state = (tool.eraser ? Pen.State.eraserHovers : Pen.State.tipHovers) | (tool.ev.state & buttonBits);
    tool.frame.up = true;
}

extern (C) private void toolMotion(void* data, zwp_tablet_tool_v2* t, wl_fixed_t x, wl_fixed_t y) nothrow
{
    auto tool = cast(WaylandTool) data;
    tool.frame.motion = true;
    tool.surfaceX = x;
    tool.surfaceY = y;
    platformWayland.guardedCall({ coordsFromSurface(tool, x, y); });
}

extern (C) private void toolPressure(void* data, zwp_tablet_tool_v2* t, uint pressure) nothrow
{
    (cast(WaylandTool) data).ev.pressure = pressure / 65535.0; // [0, 65535] -> [0, 1]
}

extern (C) private void toolDistance(void* data, zwp_tablet_tool_v2* t, uint distance) nothrow
{
    (cast(WaylandTool) data).ev.proximity = distance / 65535.0;
}

extern (C) private void toolTilt(void* data, zwp_tablet_tool_v2* t, wl_fixed_t tx, wl_fixed_t ty) nothrow
{
    // degrees, -90 to 90 -> -1 to 1, X negated as FLTK's Cocoa driver does
    auto tool = cast(WaylandTool) data;
    tool.ev.tiltX = -wl_fixed_to_double(tx) / 90.0;
    tool.ev.tiltY = -wl_fixed_to_double(ty) / 90.0;
}

extern (C) private void toolRotation(void* data, zwp_tablet_tool_v2* t, wl_fixed_t degrees) nothrow
{
    // clockwise, 0 to 360 -> -180 to 180, as fl.pen documents
    double d = wl_fixed_to_double(degrees);
    (cast(WaylandTool) data).ev.twist = d > 180 ? d - 360 : d;
}

extern (C) private void toolSlider(void* data, zwp_tablet_tool_v2* t, int position) nothrow
{
    (cast(WaylandTool) data).ev.barrelPressure = position / 65535.0; // [-65535, 65535] -> [-1, 1]
}

extern (C) private void toolWheel(void* data, zwp_tablet_tool_v2* t, wl_fixed_t degrees, int clicks) nothrow { }

extern (C) private void toolButton(void* data, zwp_tablet_tool_v2* t, uint serial, uint btn, uint state) nothrow
{
    auto tool = cast(WaylandTool) data;
    Pen.State bit;
    switch (btn)
    {
        case BTN_STYLUS: bit = Pen.State.button1; break;   // upper barrel button
        case BTN_STYLUS2: bit = Pen.State.button0; break;  // lower barrel button, nearer the tip
        case BTN_STYLUS3: bit = Pen.State.button2; break;
        default: return;
    }
    if (state == ZWP_TABLET_TOOL_V2_BUTTON_STATE_PRESSED)
    {
        tool.ev.state |= bit;
        tool.frame.buttonsPressed |= bit;
    }
    else
    {
        tool.ev.state = cast(Pen.State)(tool.ev.state & ~bit);
        tool.frame.buttonsReleased |= bit;
    }
}

/// The tool's frame: what it gathered is dispatched -- FLTK's
/// `tool_cb_frame()`. Over a window's frame (fldtk's own title bar),
/// the pen works the frame as the mouse does.
extern (C) private void toolFrame(void* data, zwp_tablet_tool_v2* t, uint time) nothrow
{
    auto tool = cast(WaylandTool) data;
    tool.time = time;
    platformWayland.guardedCall({
        auto f = tool.frame;
        tool.frame = PenFrame.init;
        if (tool.focusSurface !is null
            && platformWayland.penOnFrame(tool.focusSurface, tool.surfaceX, tool.surfaceY,
                f.down, f.up, f.proximityOut, tool.serial, time))
        {
            tool.prevState = tool.ev.state;
            if (f.proximityOut) tool.focusSurface = null;
            return;
        }
        PenPlatform platform; // the compositor sends no mouse events for the pen
        dispatchPenFrame(tool, f, platform);
        if (f.proximityOut)
        {
            tool.focusSurface = null;
            tool.focusWin = null;
        }
    });
}

private __gshared zwp_tablet_tool_v2_listener toolListener = {
    type: &toolType,
    hardware_serial: &toolHardwareSerial,
    hardware_id_wacom: &toolHardwareIdWacom,
    capability: &toolCapability,
    done: &toolDone,
    removed: &toolRemoved,
    proximity_in: &toolProximityIn,
    proximity_out: &toolProximityOut,
    down: &toolDown,
    up: &toolUp,
    motion: &toolMotion,
    pressure: &toolPressure,
    distance: &toolDistance,
    tilt: &toolTilt,
    rotation: &toolRotation,
    slider: &toolSlider,
    wheel: &toolWheel,
    button: &toolButton,
    frame: &toolFrame,
};

// ---- tablets and the tablet seat (no per-tablet state is needed)

extern (C) private void tabletName(void* data, zwp_tablet_v2* t, const(char)* name) nothrow { }
extern (C) private void tabletId(void* data, zwp_tablet_v2* t, uint vid, uint pid) nothrow { }
extern (C) private void tabletPath(void* data, zwp_tablet_v2* t, const(char)* path) nothrow { }
extern (C) private void tabletDone(void* data, zwp_tablet_v2* t) nothrow { }
extern (C) private void tabletRemoved(void* data, zwp_tablet_v2* t) nothrow { zwp_tablet_v2_destroy(t); }
extern (C) private void tabletBustype(void* data, zwp_tablet_v2* t, uint bustype) nothrow { }

private __gshared zwp_tablet_v2_listener tabletListener = {
    name: &tabletName,
    id: &tabletId,
    path: &tabletPath,
    done: &tabletDone,
    removed: &tabletRemoved,
    bustype: &tabletBustype,
};

extern (C) private void seatTabletAdded(void* data, zwp_tablet_seat_v2* s, zwp_tablet_v2* tablet) nothrow
{
    zwp_tablet_v2_add_listener(tablet, &tabletListener, null);
}

extern (C) private void seatToolAdded(void* data, zwp_tablet_seat_v2* s, zwp_tablet_tool_v2* t) nothrow
{
    auto tool = new WaylandTool;
    tool.tool = t;
    tools_ ~= tool;
    zwp_tablet_tool_v2_add_listener(t, &toolListener, cast(void*) tool);
}

extern (C) private void seatPadAdded(void* data, zwp_tablet_seat_v2* s, zwp_tablet_pad_v2* pad) nothrow
{
    // the tablet's own buttons, rings and strips aren't part of the pen API
    zwp_tablet_pad_v2_destroy(pad);
}

private __gshared zwp_tablet_seat_v2_listener seatListener = {
    tablet_added: &seatTabletAdded,
    tool_added: &seatToolAdded,
    pad_added: &seatPadAdded,
};
