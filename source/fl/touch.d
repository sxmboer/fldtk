/*
 * Touch input and gestures, beyond FLTK (whose only gesture is
 * `FL_ZOOM_GESTURE`, sent on macOS only).
 *
 * What a program sees:
 * - A finger on a touchscreen acts as the mouse: a tap is a click, a
 *   drag is a drag. The press waits up to 100 ms for a second finger,
 *   so that starting a pinch on a button doesn't click it.
 * - Two fingers make gestures, as two fingers on a touchpad do:
 *   `Event.zoomGesture` (`eventZoom()`), `Event.rotateGesture`
 *   (`eventRotation()`), and scrolling (`Event.mouseWheel`, the content
 *   following the fingers). Touchpads add `Event.swipeGesture` for three
 *   or more fingers. Every gesture event has a phase
 *   (`eventGesturePhase()`), its finger count (`eventFingers()`), and the
 *   point between the fingers (`eventX()`/`eventY()`), and goes where
 *   the mouse wheel goes: to the widget under the fingers, then out
 *   through its parents.
 * - A widget wanting the raw contacts calls `Touch.subscribe(widget)`:
 *   each finger that lands on it gives it `Event.touchDown`, and if it
 *   returns nonzero, that finger's `touchMove` and `touchUp` (or
 *   `touchCancel`) go to it alone, with `Touch.eventId()` telling the
 *   fingers apart; such a finger makes no mouse events or gestures.
 *
 * Platforms: on Wayland the compositor sends touchscreen contacts
 * (`wl_touch`) and recognized touchpad gestures (pointer-gestures); on
 * X11 the XInput2 extension sends both (touchpad gestures from XInput
 * 2.4, X.Org server 21.1 and later); on Windows the system turns one
 * finger into the mouse and recognizes the touchscreen's pinch, turn
 * and two-finger pan itself (`WM_GESTURE`), and only raw contacts for
 * subscribed widgets come through here. Windows sends a precision
 * touchpad's pinch as Ctrl + mouse wheel, so there it is not a zoom
 * gesture.
 *
 * The platform drivers call `touchDown()`, `touchMotion()`, `touchUp()`,
 * `touchCancel()` and `touchFrame()` (which ends a batch of changes;
 * gestures are worked out there), and `sendGesture()` for gestures the
 * system recognized.
 */
module fl.touch;

import fl.widget : Widget;
import fl.window : Window;
import fl.enumerations : Event, GesturePhase, stateButton1, button;
import fl.core;
import fl.pen : findSubscriberAt, offsetSubwindowEvent;

/// Raw touch contacts for subscribed widgets.
final abstract class Touch
{
    /// Makes `widget` receive `Event.touchDown` when a finger lands on
    /// it (see the module comment). Destroying the widget unsubscribes it.
    static void subscribe(Widget widget)
    {
        if (widget is null) return;
        foreach (s; subscribers_) if (s is widget) return;
        subscribers_ ~= widget;
    }

    /// Stops `widget` receiving touch events.
    static void unsubscribe(Widget widget)
    {
        if (widget !is null) forgetTouchWidget(widget);
    }

    /// During a touch event: the finger's number, the same from its
    /// `touchDown` to its `touchUp`.
    static int eventId() { return eTouchId_; }

    /// During a touch event: the finger's position in the widget's
    /// window, with the fraction `fl.core.eventX()`/`eventY()` drop.
    static double eventX() { return eTouchX_; }
    static double eventY() { return eTouchY_; } /// ditto

    /// The number of fingers on the screen now.
    static int count() { return cast(int) contacts_.length; }
}

private Widget[] subscribers_;
private int eTouchId_;
private double eTouchX_ = 0, eTouchY_ = 0;

/// `w` is being destroyed or unsubscribes: it is no longer sent touch
/// events. Called from `fl.core.clearWidgetPointer()` too.
package(fl) void forgetTouchWidget(Widget w)
{
    import std.algorithm : remove;
    import std.algorithm.searching : countUntil;
    auto i = subscribers_.countUntil!((s) => s is w);
    if (i >= 0) subscribers_ = subscribers_.remove(i);
    foreach (c; contacts_) if (c.owner is w) c.owner = null;
}

/// A finger on the screen.
private final class Contact
{
    int id;
    Window top;         // the toplevel window it landed in
    double x, y;        // in `top`'s FLTK units
    double downX, downY;
    Widget owner;       // a subscriber that took it
    bool taken;         // a subscriber took it (owner may since be gone)
}

private Contact[] contacts_;

// one finger acting as the mouse
private Contact primary_;       // that finger
private bool pressPending_;     // its press waits for a second finger
private bool pressed_;          // its press was sent
private TimeoutHandler pressTimer_;

// two fingers making gestures
private Contact[2] pair_;
private bool gesture_, zoomStarted_, rotateStarted_;
private double prevDistance_, prevAngle_, prevCenterX_, prevCenterY_;

// telling double taps apart
private double lastTapX_ = -1000, lastTapY_ = -1000;
private long lastTapTime_;

private Contact find(int id)
{
    foreach (c; contacts_) if (c.id == id) return c;
    return null;
}

private void removeContact(Contact c)
{
    import std.algorithm : remove;
    import std.algorithm.searching : countUntil;
    auto i = contacts_.countUntil!((e) => e is c);
    if (i >= 0) contacts_ = contacts_.remove(i);
}

/// Sends raw touch event `e` about `c` to its subscriber; returns what
/// the widget returned.
private int sendToOwner(Contact c, Event e, Widget w)
{
    eTouchId_ = c.id;
    eTouchX_ = c.x;
    eTouchY_ = c.y;
    offsetSubwindowEvent(w, eTouchX_, eTouchY_);
    eX_ = cast(int) eTouchX_;
    eY_ = cast(int) eTouchY_;
    eXRoot_ = cast(int)(c.x + c.top.x());
    eYRoot_ = cast(int)(c.y + c.top.y());
    return w.handle(e);
}

/// The mouse event `e` at `c`'s position, in its window.
private void mouseAt(Contact c, Event e)
{
    eX_ = cast(int) c.x;
    eY_ = cast(int) c.y;
    eXRoot_ = cast(int)(c.x + c.top.x());
    eYRoot_ = cast(int)(c.y + c.top.y());
    if (e == Event.push)
    {
        import core.time : MonoTime;
        import std.math : fabs;
        long now = MonoTime.currTime.ticks / (MonoTime.ticksPerSecond / 1000);
        bool again = now - lastTapTime_ < 400 && fabs(c.x - lastTapX_) < 20 && fabs(c.y - lastTapY_) < 20;
        eClicks_ = again ? eClicks_ + 1 : 0;
        lastTapTime_ = now;
        lastTapX_ = c.x;
        lastTapY_ = c.y;
        eState_ |= stateButton1;
        eKeysym_ = button + 1;
        eIsClick_ = true;
    }
    else if (e == Event.release)
    {
        eState_ &= ~stateButton1;
        eKeysym_ = button + 1;
    }
    dispatch(e, c.top);
}

private void sendPress()
{
    if (!pressPending_ || primary_ is null) return;
    pressPending_ = false;
    pressed_ = true;
    mouseAt(primary_, Event.move);
    mouseAt(primary_, Event.push);
}

/// The mouse finger lifts or stops being the mouse: a press not yet sent
/// is sent first when `click` (a tap), and the press is released.
private void endMouse(bool click)
{
    if (pressTimer_ !is null) removeTimeout(pressTimer_);
    if (primary_ !is null && click && pressPending_) sendPress();
    if (primary_ !is null && pressed_) mouseAt(primary_, Event.release);
    pressPending_ = pressed_ = false;
    primary_ = null;
}

/**
 * A finger landed at `(x, y)` in toplevel window `top` (its FLTK units).
 * A subscriber under it may take it; else it acts as the mouse, or with
 * another finger makes gestures -- unless `platformHandlesUntaken`
 * (Windows, which does that itself), when it is forgotten. Returns
 * whether a subscriber took it.
 */
package(fl) bool touchDown(Window top, int id, double x, double y, bool platformHandlesUntaken = false)
{
    if (top is null) return false;
    if (auto old = find(id)) removeContact(old);
    auto c = new Contact;
    c.id = id;
    c.top = top;
    c.x = c.downX = x;
    c.y = c.downY = y;
    if (auto w = findSubscriberAt(subscribers_, top, x, y))
        if (sendToOwner(c, Event.touchDown, w))
        {
            c.owner = w;
            c.taken = true;
            contacts_ ~= c;
            return true;
        }
    if (platformHandlesUntaken) return false;
    contacts_ ~= c;

    if (gesture_) return false; // a third finger plays no part
    if (primary_ is null)
    {
        primary_ = c;
        pressPending_ = true;
        if (pressTimer_ is null) pressTimer_ = () { sendPress(); };
        addTimeout(0.1, pressTimer_);
        return false;
    }
    // a second finger: the mouse stops, the gesture starts
    Contact first = primary_;
    endMouse(false);
    pair_ = [first, c];
    gesture_ = true;
    zoomStarted_ = rotateStarted_ = false;
    gestureMeasure(prevDistance_, prevAngle_, prevCenterX_, prevCenterY_);
    return false;
}

/// Finger `id` moved to `(x, y)`. Returns whether a subscriber has it.
package(fl) bool touchMotion(int id, double x, double y)
{
    auto c = find(id);
    if (c is null) return false;
    c.x = x;
    c.y = y;
    if (c.taken)
    {
        if (c.owner !is null) sendToOwner(c, Event.touchMove, c.owner);
        return true;
    }
    if (c is primary_)
    {
        import std.math : fabs;
        if (pressPending_ && (fabs(x - c.downX) > 8 || fabs(y - c.downY) > 8))
        {
            if (pressTimer_ !is null) removeTimeout(pressTimer_);
            sendPress();
        }
        if (pressed_) mouseAt(c, Event.drag);
    }
    return false;
}

/// Finger `id` left the screen. Returns whether a subscriber had it.
package(fl) bool touchUp(int id)
{
    auto c = find(id);
    if (c is null) return false;
    removeContact(c);
    if (c.taken)
    {
        if (c.owner !is null) sendToOwner(c, Event.touchUp, c.owner);
        return true;
    }
    if (c is primary_) endMouse(true);
    if (gesture_ && (c is pair_[0] || c is pair_[1])) endGesture(GesturePhase.end);
    return false;
}

/// The system took every finger (for a gesture of its own, say).
package(fl) void touchCancel()
{
    auto all = contacts_.dup;
    contacts_ = null;
    foreach (c; all)
        if (c.taken && c.owner !is null) sendToOwner(c, Event.touchCancel, c.owner);
    endMouse(false);
    if (gesture_) endGesture(GesturePhase.cancel);
}

/// A batch of finger changes is complete: two fingers' movement since
/// the last batch becomes zoom, rotate and scroll events.
package(fl) void touchFrame()
{
    if (!gesture_) return;
    double d, angle, cx, cy;
    gestureMeasure(d, angle, cx, cy);
    Window top = pair_[0].top;
    import std.math : fabs, PI;
    if (prevDistance_ > 0 && fabs(d / prevDistance_ - 1) > 0.002)
    {
        sendGesture(Event.zoomGesture, top, cx, cy, zoomStarted_ ? GesturePhase.update : GesturePhase.begin,
            2, cast(float)(d / prevDistance_));
        zoomStarted_ = true;
        prevDistance_ = d;
    }
    double turn = (angle - prevAngle_) * 180 / PI;
    if (turn > 180) turn -= 360;
    if (turn < -180) turn += 360;
    if (fabs(turn) > 0.2)
    {
        sendGesture(Event.rotateGesture, top, cx, cy, rotateStarted_ ? GesturePhase.update : GesturePhase.begin,
            2, 1, cast(float) turn);
        rotateStarted_ = true;
        prevAngle_ = angle;
    }
    double dx = cx - prevCenterX_, dy = cy - prevCenterY_;
    if (fabs(dx) >= 1 || fabs(dy) >= 1)
    {
        // the content follows the fingers, about a wheel step per 10 units
        eX_ = cast(int) cx;
        eY_ = cast(int) cy;
        eXRoot_ = cast(int)(cx + top.x());
        eYRoot_ = cast(int)(cy + top.y());
        setWheelDelta(cast(float)(-dx / 10), cast(float)(-dy / 10));
        if (eDx_ || eDy_) dispatch(Event.mouseWheel, top);
        prevCenterX_ = cx;
        prevCenterY_ = cy;
    }
}

/// Distance, angle and middle of the two gesture fingers.
private void gestureMeasure(out double d, out double angle, out double cx, out double cy)
{
    import std.math : sqrt, atan2;
    double dx = pair_[1].x - pair_[0].x, dy = pair_[1].y - pair_[0].y;
    d = sqrt(dx * dx + dy * dy);
    angle = atan2(dy, dx);
    cx = (pair_[0].x + pair_[1].x) / 2;
    cy = (pair_[0].y + pair_[1].y) / 2;
}

/// The two-finger gesture ends (`end`) or is taken away (`cancel`).
private void endGesture(GesturePhase phase)
{
    double d, angle, cx, cy;
    gestureMeasure(d, angle, cx, cy);
    Window top = pair_[0].top;
    gesture_ = false;
    if (zoomStarted_) sendGesture(Event.zoomGesture, top, cx, cy, phase, 2, 1);
    if (rotateStarted_) sendGesture(Event.rotateGesture, top, cx, cy, phase, 2, 1, 0);
    zoomStarted_ = rotateStarted_ = false;
    pair_ = [null, null];
}

/**
 * Sends gesture event `e` (`zoomGesture`, `rotateGesture` or
 * `swipeGesture`) at `(x, y)` in toplevel window `top` (its FLTK units):
 * `zoom` is the scale since the last zoom event, `rotation` the degrees
 * turned since the last rotate event, `(dx, dy)` a swipe's movement since
 * its last event. For gestures the platform recognized (touchpads,
 * Windows' touchscreen gestures) and those worked out here.
 */
package(fl) void sendGesture(Event e, Window top, double x, double y, GesturePhase phase, int fingers,
    float zoom = 1, float rotation = 0, int dx = 0, int dy = 0)
{
    if (top is null) return;
    eX_ = cast(int) x;
    eY_ = cast(int) y;
    eXRoot_ = cast(int)(x + top.x());
    eYRoot_ = cast(int)(y + top.y());
    ePhase_ = phase;
    eFingers_ = fingers;
    eZoom_ = zoom;
    eRotation_ = rotation;
    if (e == Event.zoomGesture)
    {
        eDx_ = 0;
        eDy_ = cast(int)((zoom - 1) * 1000); // FLTK's macOS magnification
    }
    else
    {
        eDx_ = dx;
        eDy_ = dy;
    }
    dispatch(e, top);
}
