/*
 * Pen and tablet input: port of `FL/core/pen_events.H` (the `Fl::Pen`
 * API) and `src/drivers/Base/Fl_Base_Pen_Driver.{H,cxx}`, plus the
 * dispatch code FLTK's Wayland, Windows and Cocoa pen drivers each carry
 * a copy of (their "shared helper functions", with a TODO to move them
 * to the base driver): here they are written once and used by every
 * platform driver.
 *
 * A pen is a stylus: on an external tablet (a Wacom Intuos) or on a
 * screen that takes one (a Cintiq, a 2-in-1 laptop's active pen). It
 * reports pressure, tilt, twist, an eraser end, barrel buttons and
 * hovering. Finger touch and touchpads are not pens.
 *
 * Using it: `Pen.subscribe(widget)` makes `widget` receive
 * `Event.penEnter` when the pen comes over it. Returning nonzero there
 * claims the pen: the widget then gets `penTouch`, `penDraw`, `penLift`,
 * `penHover`, `penButtonPush`/`penButtonRelease` and `penLeave`, and no
 * mouse events, while the pen is over it; returning 0 lets the pen act
 * as a mouse. During those events `Pen.eventPressure()`,
 * `Pen.eventTiltX()` and the others give the pen's data, and
 * `fl.core.eventX()`/`eventY()` its position. Every subscriber gets
 * `penDetected`, `penChanged`, `penInRange` and `penOutOfRange`.
 *
 * Differences from FLTK: the pen events are members of `Event`
 * (`Event.penTouch`, ...) rather than a second enum, so a `handle()`
 * override needs no casts; the API is the static members of class
 * `Pen` (`Pen.subscribe()`, `Pen.State.tipDown`), as FLTK's is the
 * namespace `Fl::Pen`; the widget under the pen is found by walking the
 * window's widget tree on every platform (FLTK's Windows driver takes
 * the first subscriber found in its list, whatever the stacking); a
 * widget deleted while it handles a pen event ends the dispatch on
 * every platform (FLTK checks only on Windows).
 *
 * Drivers: `fl.wayland_pen_driver` (the tablet protocol) and
 * `fl.win32_pen_driver` (Windows' pointer input, Windows 8 and later).
 * On X11 there is none, as in FLTK: pens act as mice there.
 */
module fl.pen;

import fl.widget : Widget;
import fl.window : Window;
import fl.group : FlGroup;
import fl.enumerations : Event, stateButton1, button;
import fl.core;

/// The `Fl::Pen` API.
final abstract class Pen
{
    /// What a pen driver, or a pen, can report (FLTK's `Fl::Pen::Trait`).
    enum Trait : uint
    {
        none = 0x0000,
        driverAvailable = 0x0001,  /// the platform has a pen driver
        detected = 0x0002,         /// a pen was seen (maybe only once it came near)
        display = 0x0004,          /// a screen's digitizer, not a separate tablet
        penId = 0x0008,            /// pens are told apart (`eventPenId()`)
        eraser = 0x0010,           /// the pen may have an eraser end
        pressure = 0x0020,         /// `eventPressure()`
        barrelPressure = 0x0040,   /// `eventBarrelPressure()`
        tiltX = 0x0080,            /// `eventTiltX()`
        tiltY = 0x0100,            /// `eventTiltY()`
        twist = 0x0200,            /// `eventTwist()`
        proximity = 0x0400,        /// `eventProximity()`
    }

    /// The pen's tip, eraser and buttons (FLTK's `Fl::Pen::State`).
    enum State : uint
    {
        none = 0x0000,
        tipHovers = 0x0001,      /// the tip is near the surface, not touching it
        tipDown = 0x0002,        /// the tip touches the surface
        eraserHovers = 0x0004,   /// the eraser is near the surface
        eraserDown = 0x0008,     /// the eraser touches the surface
        button0 = 0x0100,        /// barrel button 0, usually the lower one
        button1 = 0x0200,        /// barrel button 1, usually the upper one
        button2 = 0x0400,
        button3 = 0x0800,
        /// every button, the tip and the eraser down
        anyDown = button0 | button1 | button2 | button3 | tipDown | eraserDown,
    }

    /// What the platform's pen driver supports. A pen may support less
    /// (`penTraits()`); values it doesn't report keep their defaults.
    static Trait driverTraits() { return platformTraits(); }

    /// Whether any of `bits` is in `driverTraits()`.
    static bool driverTraits(Trait bits) { return (driverTraits() & bits) != Trait.none; }

    /// What pen `penId` (0: the current pen) reports.
    static Trait penTraits(int penId = 0) { return platformPenTraits(penId); }

    /// Whether any of `bits` is in `penTraits(penId)`.
    static bool penTraits(Trait bits, int penId = 0) { return (penTraits(penId) & bits) != Trait.none; }

    /// Makes `widget` receive `Event.penEnter` when the pen comes over
    /// it (see the module comment). Subscribing again does nothing;
    /// destroying the widget unsubscribes it.
    static void subscribe(Widget widget)
    {
        if (widget is null) return;
        foreach (s; subscribers_) if (s is widget) return;
        bool first = subscribers_.length == 0;
        subscribers_ ~= widget;
        if (first) platformFirstSubscriber();
    }

    /// Stops `widget` receiving pen events.
    static void unsubscribe(Widget widget)
    {
        if (widget is null) return;
        removeSubscriber(widget);
    }

    /// Ends the pen's claim on a widget, so mouse events work normally
    /// again -- call it when a window pops up while a widget handles the
    /// pen. `fl.core.grab()` calls it.
    static void release()
    {
        platformRelease();
        penPushed_ = null;
        belowPen_ = null;
    }

    /// The pen's position in the widget's window, with the fraction
    /// `fl.core.eventX()`/`eventY()` drop.
    static double eventX() { return penEvent_.x; }
    static double eventY() { return penEvent_.y; } /// ditto

    /// The pen's position relative to the screen (on Wayland, the
    /// program's window).
    static double eventXRoot() { return penEvent_.rx; }
    static double eventYRoot() { return penEvent_.ry; } /// ditto

    /// The pen's number, or -1 when the pen or tablet went away.
    static int eventPenId() { return penEvent_.penId; }

    /// Pressure of the tip or eraser, 0 to 1 (1 when not reported).
    static double eventPressure() { return penEvent_.pressure; }

    /// Barrel (tangential) pressure, -1 to 1 (0 when not reported).
    static double eventBarrelPressure() { return penEvent_.barrelPressure; }

    /// Tilt, -1 to 1: X left to right, Y away from and towards the user
    /// (0 when not reported). Most pens give at most about -0.7 to 0.7.
    static double eventTiltX() { return penEvent_.tiltX; }
    static double eventTiltY() { return penEvent_.tiltY; } /// ditto

    /// The pen's rotation about its axis in degrees, -180 to 180, 0 with
    /// the buttons facing up (0 when not reported).
    static double eventTwist() { return penEvent_.twist; }

    /// Distance from the surface, 0 (touching) to 1 (0 when not reported).
    static double eventProximity() { return penEvent_.proximity; }

    /// The tip, eraser and buttons now.
    static State eventState() { return penEvent_.state; }

    /// Whether any of `bits` is in `eventState()`.
    static bool eventState(State bits) { return (penEvent_.state & bits) != State.none; }

    /// The change that caused the event: one bit (`tipDown` for
    /// `penTouch`, `button0` for `penButtonPush`, ...).
    static State eventTrigger() { return penEvent_.trigger; }
}

// ---- shared by the platform drivers (FLTK's Fl_Base_Pen_Driver and the
// helpers its drivers duplicate) ----------------------------------------

/// A pen's data, as the events report it (FLTK's `Fl::Pen::EventData`).
package(fl) struct PenEventData
{
    double x = 0, y = 0, rx = 0, ry = 0;
    double tiltX = 0, tiltY = 0;
    double pressure = 1;
    double proximity = 0;
    double barrelPressure = 0;
    double twist = 0;
    int penId;
    Pen.State state;
    Pen.State trigger;
}

/// The data of the event being handled (FLTK's `Fl::Pen::e`).
package(fl) PenEventData penEvent_;

/// The subscribed widgets, in subscription order.
package(fl) Widget[] subscribers_;

/// The widget the pen pushed (tip down or a button held), and the
/// subscriber under the pen that claimed it (FLTK's `pushed_` and
/// `below_pen_`).
package(fl) Widget penPushed_, belowPen_;

private void removeSubscriber(Widget w)
{
    import std.algorithm : remove;
    import std.algorithm.searching : countUntil;
    auto i = subscribers_.countUntil!((s) => s is w);
    if (i >= 0) subscribers_ = subscribers_.remove(i);
    if (penPushed_ is w) penPushed_ = null;
    if (belowPen_ is w) belowPen_ = null;
}

/// `w` is being destroyed: it is no longer subscribed. Called from
/// `fl.core.clearWidgetPointer()`.
package(fl) void forgetPenWidget(Widget w)
{
    if (subscribers_.length || penPushed_ !is null || belowPen_ !is null) removeSubscriber(w);
}

private bool isSubscriber(Widget w)
{
    foreach (s; subscribers_) if (s is w) return true;
    return false;
}

/// One pen (a tool, on Wayland; a pointer device, on Windows): what the
/// platform driver has gathered about it.
package(fl) class PenTool
{
    int penId;
    Pen.Trait capabilities;
    bool isNew = true;      // until it first comes near
    bool eraser;            // the tool is an eraser (Wayland)
    Window focusWin;        // the toplevel window under it
    PenEventData ev;        // its data now
    Pen.State prevState;    // ev.state after the last dispatch
}

/// The pen used last (FLTK's `g_current_tool`).
package(fl) PenTool currentPen_;

/// What happened to a pen since the last dispatch -- one Wayland tool
/// frame, or one Windows pointer message.
package(fl) struct PenFrame
{
    bool proximityIn, proximityOut, down, up, motion;
    Pen.State buttonsPressed, buttonsReleased;
}

/// Subtracts the origins of `w`'s subwindows from `(x, y)`, toplevel
/// window coordinates, giving coordinates in `w`'s own window.
package(fl) void offsetSubwindowEvent(Widget w, ref double x, ref double y)
{
    for (Widget p = w; p !is null; p = p.parent)
        if (p.asWindow() !is null && p.parent !is null)
        {
            x -= p.x();
            y -= p.y();
        }
}

/// Whether `(x, y)`, toplevel window coordinates, is inside `w`.
private bool eventInside(Widget w, double x, double y)
{
    offsetSubwindowEvent(w, x, y);
    if (w.asWindow() !is null) return x >= 0 && y >= 0 && x < w.w() && y < w.h();
    return x >= w.x() && y >= w.y() && x < w.x() + w.w() && y < w.y() + w.h();
}

/// The topmost widget of `list` at `(x, y)` in toplevel window `top`.
/// Shared with `fl.touch`.
package(fl) Widget findSubscriberAt(const(Widget)[] list, Window top, double x, double y)
{
    bool listed(Widget w)
    {
        foreach (s; list) if (s is w) return true;
        return false;
    }
    Widget findIn(FlGroup g)
    {
        foreach_reverse (i; 0 .. g.children())
        {
            Widget w = g.child(i);
            if (w is null || !w.visible() || !eventInside(w, x, y)) continue;
            if (listed(w)) return w;
            if (auto sg = w.asGroup())
                if (auto found = findIn(sg)) return found;
        }
        return listed(g) ? g : null;
    }
    return top is null ? null : findIn(top);
}

/// The topmost subscribed widget at `(x, y)` in toplevel window `top`.
private Widget findBelowPen(Window top, double x, double y)
{
    return findSubscriberAt(subscribers_, top, x, y);
}

/// Makes `tool`'s data the event's, and sets `fl.core`'s event position.
private void copyState(PenTool tool)
{
    auto trigger = cast(Pen.State)(penEvent_.state ^ tool.ev.state);
    penEvent_ = tool.ev;
    penEvent_.trigger = trigger;
    eX_ = cast(int) tool.ev.x;
    eY_ = cast(int) tool.ev.y;
    eXRoot_ = cast(int) tool.ev.rx;
    eYRoot_ = cast(int) tool.ev.ry;
}

/// Sends pen event `event` to `w`, in `w`'s window's coordinates.
private int penSend(PenTool tool, Widget w, Event event, Pen.State trigger, ref bool copied)
{
    if (!copied)
    {
        copyState(tool);
        copied = true;
    }
    penEvent_.x = tool.ev.x;
    penEvent_.y = tool.ev.y;
    offsetSubwindowEvent(w, penEvent_.x, penEvent_.y);
    eX_ = cast(int) penEvent_.x;
    eY_ = cast(int) penEvent_.y;
    penEvent_.trigger = trigger;
    return w.handle(event);
}

/// Sends `event` to every subscriber.
package(fl) void penSendAll(PenTool tool, Event event)
{
    bool copied = false;
    foreach (w; subscribers_.dup) penSend(tool, w, event, Pen.State.none, copied);
}

private double xDown_, yDown_; // where the tip went down (FLTK's Fl::Private::e_x_down)

/// What a platform driver does around a dispatch.
package(fl) struct PenPlatform
{
    /// The platform also sends mouse events for the pen (Windows):
    /// nothing unclaimed is turned into mouse events here.
    bool sendsMouseEvents;
    /// Keeps the pen's events coming to window `win` while it pushes a
    /// widget, and lets them go (Windows' SetCapture()/ReleaseCapture()).
    void delegate(Window win) capture;
    void delegate() releaseCapture;
}

/**
 * Dispatches what happened to `tool` -- the body of FLTK's Wayland
 * `tool_cb_frame()` and Windows `handle_update()`/`handle_leave()`:
 * pen out of range, pen in range, then for the subscriber under the pen
 * (or the one it pushed) enter/leave, touch, lift, buttons and motion;
 * what no subscriber claims becomes mouse events, unless the platform
 * sends those itself. Returns whether a subscriber handled an event.
 */
package(fl) bool dispatchPenFrame(PenTool tool, ref const PenFrame f, ref const PenPlatform platform)
{
    import fl.tooltip : mouseEnter;
    import fl.widget_tracker : WidgetTracker;

    scope (exit) tool.prevState = tool.ev.state;

    // 1. out of range
    if (f.proximityOut)
    {
        penSendAll(tool, Event.penOutOfRange);
        if (belowPen_ !is null)
        {
            bool copied = false;
            penSend(tool, belowPen_, Event.penLeave, Pen.State.none, copied);
        }
        belowPen_ = null;
        belowmouse(null);
        mouseEnter(null);
        if (penPushed_ !is null)
        {
            pushed(null);
            penPushed_ = null;
            if (platform.releaseCapture !is null) platform.releaseCapture();
        }
        if (currentPen_ is tool) currentPen_ = null;
        tool.focusWin = null;
        return false;
    }

    // 2. in range
    if (f.proximityIn)
    {
        tool.ev.penId = tool.penId;
        if (tool.isNew)
        {
            tool.isNew = false;
            penSendAll(tool, Event.penDetected);
        }
        else if (currentPen_ !is null && currentPen_ !is tool)
            penSendAll(tool, Event.penChanged);
        else
            penSendAll(tool, Event.penInRange);
        currentPen_ = tool;
    }

    if (tool.focusWin is null || subscribers_.length == 0) return false;

    // 3. a grab or a modal window keeps the pen from other windows
    Window eventWindow = tool.focusWin;
    if (auto g = grab()) eventWindow = cast(Window) g;
    else if (auto m = modal()) eventWindow = cast(Window) m;
    if (eventWindow is null) return false;
    bool menu = eventWindow.menuWindow();
    if (!menu && ((grab() !is null && grab() !is eventWindow) || (modal() !is null && modal() !is eventWindow)))
        return false;

    void mouseFallback(bool down, bool up, bool motion)
    {
        if (platform.sendsMouseEvents) return;
        eX_ = cast(int) tool.ev.x;
        eY_ = cast(int) tool.ev.y;
        eXRoot_ = cast(int) tool.ev.rx;
        eYRoot_ = cast(int) tool.ev.ry;
        if (down)
        {
            eState_ |= stateButton1;
            eKeysym_ = button + 1;
            eIsClick_ = true;
            dispatch(Event.push, eventWindow);
        }
        else if (up)
        {
            eState_ &= ~stateButton1;
            eKeysym_ = button + 1;
            dispatch(Event.release, eventWindow);
        }
        else if (motion)
            dispatch(pushed() !is null ? Event.drag : Event.move, eventWindow);
    }

    // 4. the receiver: the widget the pen pushed, or the subscriber under
    // it, which gets enter and leave
    bool copied = false;
    Widget receiver;
    bool isPushed = false;
    if (penPushed_ !is null && pushed() is penPushed_)
    {
        receiver = penPushed_;
        isPushed = true;
    }
    else
    {
        Widget old = belowmouse() is belowPen_ ? belowPen_ : null;
        Widget now = findBelowPen(eventWindow, tool.ev.x, tool.ev.y);
        if (now !is null)
        {
            // a tooltip popping up under the pen doesn't take it away
            auto win = now.asWindow() !is null ? now.asWindow() : now.window();
            if (win !is null && win.tooltipWindow()) now = old;
        }
        if (now !is old)
        {
            if (old !is null) penSend(tool, old, Event.penLeave, Pen.State.none, copied);
            belowPen_ = null;
            if (now !is null)
            {
                auto hover = tool.ev.state & (Pen.State.eraserHovers | Pen.State.eraserDown)
                    ? Pen.State.eraserHovers : Pen.State.tipHovers;
                if (penSend(tool, now, Event.penEnter, hover, copied)) belowPen_ = now;
                // plain widgets under the pen still show their tooltips
                belowmouse(now);
                mouseEnter(now);
            }
            else
            {
                belowmouse(null);
                mouseEnter(null);
            }
        }
        receiver = belowPen_;
    }

    if (receiver is null)
    {
        mouseFallback(f.down, f.up, f.motion);
        return false;
    }

    auto tracker = WidgetTracker(receiver);
    bool handled = false;
    bool eraser = (tool.ev.state & (Pen.State.eraserHovers | Pen.State.eraserDown)) != 0;

    // 5. touch
    if (f.down)
    {
        if (!isPushed)
        {
            penPushed_ = receiver;
            pushed(receiver);
            if (platform.capture !is null) platform.capture(eventWindow);
        }
        eIsClick_ = true;
        xDown_ = tool.ev.x;
        yDown_ = tool.ev.y;
        eClicks_ = 0;
        bool h = penSend(tool, receiver, Event.penTouch,
            tool.ev.state & (Pen.State.tipDown | Pen.State.eraserDown), copied) != 0;
        handled |= h;
        if (tracker.deleted()) return handled;
        if (!h) mouseFallback(true, false, false);
    }

    // 6. lift
    if (f.up)
    {
        if ((tool.ev.state & Pen.State.anyDown) == 0)
        {
            pushed(null);
            penPushed_ = null;
            if (platform.releaseCapture !is null) platform.releaseCapture();
        }
        bool h = penSend(tool, receiver, Event.penLift,
            eraser ? Pen.State.eraserHovers : Pen.State.tipHovers, copied) != 0;
        handled |= h;
        if (tracker.deleted()) return handled;
        if (!h) mouseFallback(false, true, false);
    }

    // 7. barrel buttons (no mouse equivalent)
    foreach (bit; [Pen.State.button0, Pen.State.button1, Pen.State.button2, Pen.State.button3])
    {
        if (f.buttonsPressed & bit)
            handled |= penSend(tool, receiver, Event.penButtonPush, bit, copied) != 0;
        if (tracker.deleted()) return handled;
        if (f.buttonsReleased & bit)
            handled |= penSend(tool, receiver, Event.penButtonRelease, bit, copied) != 0;
        if (tracker.deleted()) return handled;
    }

    // 8. motion
    if (f.motion)
    {
        import std.math : fabs;
        if (eIsClick_ && (fabs(tool.ev.x - xDown_) > 5 || fabs(tool.ev.y - yDown_) > 5))
            eIsClick_ = false;
        bool h = penSend(tool, receiver, isPushed ? Event.penDraw : Event.penHover,
            Pen.State.none, copied) != 0;
        handled |= h;
        if (tracker.deleted()) return handled;
        if (!h) mouseFallback(false, false, true);
    }

    // a menu follows the pen like the mouse, for its highlighting
    if (menu && f.motion) mouseFallback(false, false, true);
    return handled;
}

/// The pen left its window but is still in range (Windows sends no
/// further event that would find the widget under it): the subscriber
/// under it in that window gets `penLeave` -- the in-range half of FLTK's
/// Windows `handle_leave()`. Returns what the widget returned.
package(fl) bool penLeftWindow(PenTool tool)
{
    import fl.core : belowmouse;
    bool r = false;
    if (belowPen_ !is null && belowPen_.topWindow() is tool.focusWin)
    {
        bool copied = false;
        r = penSend(tool, belowPen_, Event.penLeave, Pen.State.none, copied) != 0;
        belowPen_ = null;
        belowmouse(null);
    }
    tool.focusWin = null;
    return r;
}

/// The window lost the pointer capture while the pen pushed a widget (a
/// dialog took it, say): the widget gets `penLift` if the tip or eraser
/// was down, and is no longer pushed -- FLTK's Windows
/// `handle_capture_lost()`. Returns whether a widget was pushed.
package(fl) bool penCaptureLost(PenTool tool)
{
    import fl.core : pushed;
    scope (exit) tool.prevState = tool.ev.state;
    if (penPushed_ is null) return false;
    if (tool.ev.state & (Pen.State.tipDown | Pen.State.eraserDown))
    {
        auto hover = tool.ev.state & (Pen.State.eraserHovers | Pen.State.eraserDown)
            ? Pen.State.eraserHovers : Pen.State.tipHovers;
        bool copied = false;
        penSend(tool, penPushed_, Event.penLift, hover, copied);
        // the tip or eraser is up; the barrel buttons stay as they are
        tool.ev.state = cast(Pen.State)((tool.ev.state & ~(Pen.State.tipDown | Pen.State.eraserDown)) | hover);
    }
    pushed(null);
    penPushed_ = null;
    return true;
}

// ---- the platform drivers ---------------------------------------------

private Pen.Trait platformTraits()
{
    version (Windows)
    {
        import fl.win32_pen_driver : traits;
        return traits();
    }
    else version (FLDTK_HAVE_WAYLAND)
    {
        import platform = fl.platform;
        import fl.wayland_pen_driver : traits;
        if (platform.backend() == platform.Backend.wayland) return traits();
        return Pen.Trait.none;
    }
    else
        return Pen.Trait.none;
}

private Pen.Trait platformPenTraits(int penId)
{
    version (Windows)
    {
        import fl.win32_pen_driver : penTraits;
        return penTraits(penId);
    }
    else version (FLDTK_HAVE_WAYLAND)
    {
        import platform = fl.platform;
        import fl.wayland_pen_driver : penTraits;
        if (platform.backend() == platform.Backend.wayland) return penTraits(penId);
        return Pen.Trait.none;
    }
    else
        return Pen.Trait.none;
}

private void platformFirstSubscriber()
{
    version (FLDTK_HAVE_WAYLAND)
    {
        import platform = fl.platform;
        import fl.wayland_pen_driver : startTablets;
        if (platform.backend() == platform.Backend.wayland) startTablets();
    }
}

private void platformRelease()
{
    version (Windows)
    {
        import fl.win32_pen_driver : releaseCaptureIfPushed;
        releaseCaptureIfPushed();
    }
}
