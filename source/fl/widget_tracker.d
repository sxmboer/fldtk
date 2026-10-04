/*
 * Ported from FL/Fl_Widget_Tracker.H (FLTK 1.5.0, ~/Repositories/fltk).
 * Watches a widget so calling code can tell whether it was destroyed as
 * a side effect of something risky it just did -- typically, whether a
 * callback closed/destroyed the very widget that's about to keep
 * running code after the callback returns (see fl.button's handle()
 * FL_RELEASE case and triggeredByKeyboard() for the concrete use).
 *
 * DELIBERATE D-APPROPRIATE REDESIGN, not a straight port (see
 * CLAUDE.md's GC-finalizer note). The mechanism
 * FLTK needs and the mechanism this port needs turn out to be the
 * same *shape* (a global watch-list of registered pointer-to-pointer
 * slots, nulled out by the watched widget's own destructor) for a
 * subtler reason than "stay faithful": a simpler design -- a
 * `bool destroyed_` field set at the top of
 * `Widget.~this()` -- does NOT work in D: `destroy()` on a class
 * instance runs `~this()` (during which the flag
 * genuinely gets set), but druntime then reinitializes the *entire
 * object's memory* back to its `.init` state immediately afterward,
 * silently wiping that flag back to `false` before any caller could
 * observe it. So a self-reported "am I destroyed" field on the widget
 * itself is fundamentally unusable for this purpose in D -- the state
 * has to live *outside* the watched object, exactly like FLTK's
 * external watch-list, just for a D-specific reason (post-destructor
 * reinitialization) rather than C++'s (a `delete`d pointer dangles).
 *
 * `Fl::watch_widget_pointer(Fl_Widget*&)`/`release_widget_pointer()`
 * (which take a *reference to a pointer*, so the registry can null the
 * caller's own pointer variable in place) map directly to
 * `fl.core.watchWidgetPointer(ref Widget)`/`releaseWidgetPointer(ref
 * Widget)` -- D's `ref` parameters are exactly FLTK's `T*&`.
 * `Fl::clear_widget_pointer()` (called from `Widget.~this()`, see
 * fl.widget) walks that registry and nulls any entry pointing at the
 * widget being destroyed -- see fl.core's own comment on why this is
 * safe unconditionally, even during GC-driven finalization (the
 * watched slots are always plain stack memory for every intended use
 * in this port, never another GC object's fields).
 *
 * A `struct`, not a `class`, matching FLTK's "intended to be used
 * as an automatic (local/stack) variable" primary use case (D structs
 * get deterministic RAII-style destructor calls at scope exit, same as
 * C++ locals). Copying/moving is disabled, matching FLTK's deleted
 * copy/move constructors and assignment operators -- a copy's own
 * `wp_` field would live at a different address than the one actually
 * registered in the watch-list, silently making the copy untracked.
 * Heap-allocating a WidgetTracker via `new` (FLTK explicitly
 * documents this as also supported) isn't supported here: nothing in
 * this port needs it, and it would reintroduce the "another GC object's
 * fields" hazard clearWidgetPointer()'s doc comment says doesn't apply
 * -- stack-only keeps that guarantee simple and true.
 */
module fl.widget_tracker;

import fl.widget : Widget;
import fl.core;

struct WidgetTracker
{
    private Widget wp_;

    @disable this();
    @disable this(this);

    this(Widget wi)
    {
        wp_ = wi;
        fl.core.watchWidgetPointer(wp_);
    }

    ~this()
    {
        fl.core.releaseWidgetPointer(wp_);
    }

    /// Clears the watched pointer without waiting for the widget to
    /// actually be destroyed.
    void clear() { wp_ = null; }

    /// The watched widget, or null if it's been destroyed.
    Widget widget() { return wp_; }

    /// True if the watched widget has been destroyed since this
    /// tracker was created.
    bool deleted() const { return wp_ is null; }

    /// True if the watched widget still exists.
    bool exists() const { return wp_ !is null; }
}

// ===========================================================================
// Unit tests
// ===========================================================================

unittest
{
    import fl.group : FlGroup;
    import fl.box : Box;

    FlGroup.current(null);
    fl.core.resetForTest();

    auto b = new Box(0, 0, 10, 10);
    {
        auto wp = WidgetTracker(b);
        assert(wp.exists());
        assert(!wp.deleted());
        assert(wp.widget() is b);
    }
    // wp went out of scope and unregistered itself -- b is untouched.
    assert(b !is null);

    fl.core.resetForTest();
    FlGroup.current(null);
}

unittest
{
    // The core guarantee: destroying the watched widget mid-scope is
    // observed by the tracker.
    import fl.group : FlGroup;
    import fl.box : Box;

    FlGroup.current(null);
    fl.core.resetForTest();

    auto b = new Box(0, 0, 10, 10);
    auto wp = WidgetTracker(b);
    assert(wp.exists());

    destroy(b);

    assert(wp.deleted());
    assert(!wp.exists());
    assert(wp.widget() is null);

    fl.core.resetForTest();
    FlGroup.current(null);
}

unittest
{
    // Two trackers watching the same widget are both cleared
    // independently.
    import fl.group : FlGroup;
    import fl.box : Box;

    FlGroup.current(null);
    fl.core.resetForTest();

    auto b = new Box(0, 0, 10, 10);
    auto wp1 = WidgetTracker(b);
    auto wp2 = WidgetTracker(b);

    destroy(b);

    assert(wp1.deleted());
    assert(wp2.deleted());

    fl.core.resetForTest();
    FlGroup.current(null);
}

unittest
{
    // A tracker watching a *different* widget is unaffected.
    import fl.group : FlGroup;
    import fl.box : Box;

    FlGroup.current(null);
    fl.core.resetForTest();

    auto a = new Box(0, 0, 10, 10);
    auto b = new Box(0, 0, 10, 10);
    auto wpA = WidgetTracker(a);
    auto wpB = WidgetTracker(b);

    destroy(a);

    assert(wpA.deleted());
    assert(wpB.exists());
    assert(wpB.widget() is b);

    fl.core.resetForTest();
    FlGroup.current(null);
}
