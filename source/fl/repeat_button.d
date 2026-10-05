/*
 * Ported from FL/Fl_Repeat_Button.H + src/Fl_Repeat_Button.cxx (FLTK
 * 1.5.0). A Button that repeats its callback while
 * held down, using fl.core's timer subsystem (addTimeout()/
 * repeatTimeout()/removeTimeout()) -- previously blocked entirely on
 * that not existing (see PORTING.md's history for this row).
 *
 * Faithful, complete port. One structural deviation: FLTK's
 * `handle()` uses `goto J1` to jump from the FL_HIDE/FL_DEACTIVATE/
 * FL_RELEASE case into the middle of the FL_PUSH/FL_DRAG case body,
 * skipping just the `newval = Fl::event_inside(this)` line. D's
 * `switch` doesn't support jumping into the middle of another case's
 * body (only `goto case`, which re-enters at the case's *start*), so
 * the shared tail (`if (!active()) newval = false; if (value(newval))
 * {...}`) is factored out to run unconditionally after the switch
 * instead -- same control flow, no goto. `repeat_callback` (FLTK:
 * a `static void(*)(void*)` needing the button passed as `void*` data,
 * since a plain C function pointer can't close over it) becomes a
 * private bound method instead, per CONVENTIONS.md's callback-porting
 * convention -- also why removeTimeout()/addTimeout() below only pass
 * one argument where FLTK passes two (cb, data): a D delegate's
 * context pointer already carries what `data` exists to carry.
 */
module fl.repeat_button;

import fl.button : Button;
import fl.enumerations;
import fl.core;

private enum double initialRepeat = 0.5;
private enum double repeatInterval = 0.1;

class RepeatButton : Button
{
    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
    }

    override void deactivate()
    {
        fl.core.removeTimeout(&repeatCallback);
        super.deactivate();
    }

    private void repeatCallback()
    {
        fl.core.repeatTimeout(repeatInterval, &repeatCallback);
        doCallback(CallbackReason.reselected);
    }

    override int handle(Event event)
    {
        bool newval;
        switch (event)
        {
        case Event.hide:
        case Event.deactivate:
        case Event.release:
            newval = false;
            break;

        case Event.push:
        case Event.drag:
            if (fl.core.visibleFocus()) fl.core.focus(this);
            newval = fl.core.eventInside(this);
            break;

        default:
            return super.handle(event);
        }

        if (!active()) newval = false;
        if (value(newval))
        {
            if (newval)
            {
                fl.core.addTimeout(initialRepeat, &repeatCallback);
                doCallback(CallbackReason.selected);
            }
            else
            {
                fl.core.removeTimeout(&repeatCallback);
            }
        }
        return 1;
    }
}

// ===========================================================================
// Unit tests
// ===========================================================================

unittest
{
    import fl.group : FlGroup;

    FlGroup.current(null);
    fl.core.resetForTest();

    auto b = new RepeatButton(0, 0, 80, 20, "Repeat");
    assert(b.box() == Boxtype.upBox); // inherited from Button

    // Pressing schedules the initial-repeat timer and fires SELECTED.
    fl.core.eX_ = 10;
    fl.core.eY_ = 10;
    CallbackReason lastReason;
    int calls;
    b.callback((w) { calls++; lastReason = fl.core.callbackReason(); });

    assert(b.handle(Event.push) == 1);
    assert(b.value());
    assert(calls == 1);
    assert(fl.core.hasTimeout(&b.repeatCallback));

    // Releasing removes the pending timer.
    assert(b.handle(Event.release) == 1);
    assert(!b.value());
    assert(!fl.core.hasTimeout(&b.repeatCallback));

    fl.core.eX_ = 0;
    fl.core.eY_ = 0;
    FlGroup.current(null);
    fl.core.resetForTest();
}

unittest
{
    // deactivate() cancels any pending repeat timer.
    import fl.group : FlGroup;

    FlGroup.current(null);
    fl.core.resetForTest();

    auto b = new RepeatButton(0, 0, 80, 20);
    fl.core.eX_ = 10;
    fl.core.eY_ = 10;
    b.handle(Event.push);
    assert(fl.core.hasTimeout(&b.repeatCallback));

    b.deactivate();
    assert(!fl.core.hasTimeout(&b.repeatCallback));

    fl.core.eX_ = 0;
    fl.core.eY_ = 0;
    FlGroup.current(null);
    fl.core.resetForTest();
}
