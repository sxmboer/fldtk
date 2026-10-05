/*
 * Ported from FL/Fl_Clock.H + src/Fl_Clock.cxx (FLTK 1.5.0). Two classes, both in the one FLTK header:
 * `Fl_Clock_Output` (a program-driven analog clock face, no
 * interactivity) and `Fl_Clock` (adds a 1-second auto-refresh via
 * `Fl::add_timeout()`).
 *
 * `ClockOutput` is a faithful, complete port -- `value()`/`hour()`/
 * `minute()`/`second()`/`shadow()` and `draw()` (drawn with the same
 * transform-stack + vertex-path API `fl.dial` added: pushMatrix()/
 * fl_translate()/fl_scale()/fl_rotate()/beginPolygon()/vertex()/
 * endPolygon()/beginLoop()/endLoop()/circle(), all real
 * now in fl.draw -- see that module's own comment. Verified visually
 * (testing/smoke_dial_clock.d): both a square and a round ClockOutput
 * show three hands plus 12 tick marks at the correct angles).
 *
 * `Fl_Clock` is ported as `FlClock`, not `Clock` -- the one deliberate
 * exception to this port's usual "drop the `Fl_`/`Fl` prefix" naming
 * convention (see `CONVENTIONS.md`'s "Porting conventions" section), because
 * a bare `Clock` collides with `std.datetime.systime.Clock` the moment
 * generated code (which does a wildcard `import fl; import std;`) names
 * one -- confirmed as a real regression (`source/test/tabs.fl`'s own
 * clock widget failing to compile) before the rename. `fl.group.FlGroup`
 * got the same treatment for the same reason (`std.algorithm.iteration.
 * FlGroup`) -- see that module's own doc comment.
 *
 * `FlClock` now ports FLTK's `handle()` override and destructor too,
 * now that `fl.core` has a real timer subsystem (previously skipped,
 * same gap as `fl.button`'s `simulateKeyAction()` and `fl.scrollbar`'s
 * auto-repeat -- both now also ported). `tick()` (FLTK: a free
 * function taking the clock as `void*`) becomes a private bound
 * method; note it schedules itself with plain `addTimeout()`, not
 * `repeatTimeout()`, matching FLTK exactly -- each call recomputes
 * its own delay fresh from the actual wall-clock microsecond offset
 * (so the next tick lands as close to the real next second boundary as
 * possible), so there's no "previous due time" to drift-correct from
 * the way `repeatTimeout()` exists for. Uses
 * `std.datetime.systime.Clock.currTime()` for wall-clock time with
 * sub-second resolution, rather than transliterating FLTK's
 * `Fl::system_driver()->gettime()` -- same "prefer a real D stdlib
 * alternative" reasoning as `value(ulong)`'s existing `SysTime` use
 * just below. No import alias needed for it now that this module's own
 * class is `FlClock`, not `Clock`.
 */
module fl.clock;

import std.datetime.systime : SysTime, Clock;

import fl.enumerations;
import fl.widget : Widget;
import fl.draw;
import fl.core;

/// type() of the square (default) clock variant.
enum ubyte squareClock = 0;
/// type() of the round clock variant.
enum ubyte roundClock = 1;
/// An analog clock is square.
enum ubyte analogClock = squareClock;
/// Not yet implemented, FLTK or here.
enum ubyte digitalClock = squareClock;

private immutable float[2][4] hourhand = [
    [-0.5f, 0], [0, 1.5f], [0.5f, 0], [0, -7.0f]
];
private immutable float[2][4] minhand = [
    [-0.5f, 0], [0, 1.5f], [0.5f, 0], [0, -11.5f]
];
private immutable float[2][4] sechand = [
    [-0.1f, 0], [0, 2.0f], [0.1f, 0], [0, -11.5f]
];

private void drawHand(double ang, ref immutable float[2][4] v, Color fill, Color line)
{
    pushMatrix();
    fl_rotate(ang);
    fl_color(fill);
    beginPolygon();
    foreach (p; v) vertex(p[0], p[1]);
    endPolygon();
    fl_color(line);
    beginLoop();
    foreach (p; v) vertex(p[0], p[1]);
    endLoop();
    popMatrix();
}

private void drawTick(double x, double y, double w, double h)
{
    double r = x + w;
    double t = y + h;
    beginPolygon();
    vertex(x, y);
    vertex(r, y);
    vertex(r, t);
    vertex(x, t);
    endPolygon();
}

/// This widget can be used to display a program-supplied time. The
/// time shown on the clock is not updated -- for that, use FlClock
/// instead.
class ClockOutput : Widget
{
    private
    {
        int hour_, minute_, second_;
        ulong value_;
        bool shadow_;
    }

    /// The default type() is squareClock and the default boxtype is
    /// upBox.
    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        box(Boxtype.upBox);
        selectionColor(fl_gray_ramp(5));
        alignment(alignBottom);
        hour_ = 0;
        minute_ = 0;
        second_ = 0;
        value_ = 0;
        shadow_ = true;
    }

    /// Sets the displayed time in hours, minutes, and seconds.
    void value(int H, int m, int s)
    {
        if (H != hour_ || m != minute_ || s != second_)
        {
            hour_ = H;
            minute_ = m;
            second_ = s;
            value_ = (H * 60 + m) * 60 + s;
            damage(damageChild);
        }
    }

    /// Sets the displayed time to this Unix time (seconds since the
    /// UNIX epoch, interpreted in the local timezone).
    void value(ulong v)
    {
        value_ = v;
        // FLTK reaches for the C library's localtime() here, whose
        // returned struct tm* points into non-reentrant static storage
        // -- std.datetime's SysTime has no such hazard and reads just
        // as directly (CONVENTIONS.md: prefer a real D stdlib alternative
        // over a transliterated raw C call).
        auto local = SysTime.fromUnixTime(cast(long) v).toLocalTime();
        value(local.hour, local.minute, local.second);
    }

    /// Returns the displayed time in seconds since the UNIX epoch.
    ulong value() const { return value_; }
    /// Returns the displayed hour (0 to 23).
    int hour() const { return hour_; }
    /// Returns the displayed minute (0 to 59).
    int minute() const { return minute_; }
    /// Returns the displayed second (0 to 60, 60 = leap second).
    int second() const { return second_; }

    /// Whether the hands are drawn with a drop shadow (default true).
    bool shadow() const { return shadow_; }
    /// ditto
    void shadow(bool mode) { shadow_ = mode; }

    override void draw() { draw(x(), y(), w(), h()); drawLabel(); }

    protected:

    /// Draws the clock within (X, Y, W, H) instead of this widget's
    /// full bounds.
    void draw(int X, int Y, int W, int H)
    {
        Color boxColor = type() == roundClock ? gray : color();
        drawBox(box(), X, Y, W, H, boxColor);
        pushMatrix();
        fl_translate(X + W / 2.0 - .5, Y + H / 2.0 - .5);
        fl_scale((W - 1) / 28.0, (H - 1) / 28.0);
        if (type() == roundClock)
        {
            fl_color(activeR() ? color() : inactive(color()));
            beginPolygon();
            circle(0, 0, 14);
            endPolygon();
            fl_color(activeR() ? foregroundColor : inactive(foregroundColor));
            beginLoop();
            circle(0, 0, 14);
            endLoop();
        }

        // draw the shadows:
        if (shadow_)
        {
            Color shadowColor = colorAverage(boxColor, black, 0.5f);
            pushMatrix();
            fl_translate(0.60, 0.60);
            drawHands(shadowColor, shadowColor);
            popMatrix();
        }

        // draw the tick marks:
        pushMatrix();
        fl_color(activeR() ? foregroundColor : inactive(foregroundColor));
        for (int i = 0; i < 12; i++)
        {
            if (i == 6) drawTick(-0.5, 9, 1, 2);
            else if (i == 3 || i == 0 || i == 9) drawTick(-0.5, 9.5, 1, 1);
            else drawTick(-0.25, 9.5, .5, 1);
            fl_rotate(-30);
        }
        popMatrix();

        // draw the hands:
        drawHands(selectionColor(), foregroundColor);
        popMatrix();
    }

    private void drawHands(Color fill, Color line)
    {
        Color f = fill, l = line;
        if (!activeR())
        {
            f = inactive(fill);
            l = inactive(line);
        }
        drawHand(-360 * (hour() + minute() / 60.0) / 12, hourhand, f, l);
        drawHand(-360 * (minute() + second() / 60.0) / 60, minhand, f, l);
        drawHand(-360 * (second() / 60.0), sechand, f, l);
    }
}

/// This widget provides a round analog clock display, provided for
/// Forms compatibility. Ticks live once a second while shown (see the
/// module comment) -- callers only need to drive value() themselves
/// for a plain ClockOutput.
class FlClock : ClockOutput
{
    /// The default type() is squareClock and the default boxtype is
    /// upBox.
    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
    }

    /// Same as FlClock(x, y, w, h, label), but presets type() to t
    /// (squareClock or roundClock) and, for roundClock, resets box()
    /// to noBox.
    this(ubyte t, int x, int y, int w, int h, string label)
    {
        super(x, y, w, h, label);
        type(t);
        box(t == roundClock ? Boxtype.noBox : Boxtype.upBox);
    }

    ~this()
    {
        // Safe unconditionally, even during GC-driven finalization --
        // this only compares delegate identity and mutates fl.core's
        // own module-level timer queue, it doesn't reach into another
        // GC object's fields (see the GC-finalizer note in CONVENTIONS.md
        // and fl.widget's own destructor for the pattern this follows).
        fl.core.removeTimeout(&tick);
    }

    override int handle(Event event)
    {
        switch (event)
        {
        case Event.show:
            tick();
            break;
        case Event.hide:
            fl.core.removeTimeout(&tick);
            break;
        default:
            break;
        }
        return super.handle(event);
    }

    /// Ported from the free function `tick(void*)` in src/Fl_Clock.cxx.
    /// Sets value() to the current wall-clock time, then reschedules
    /// itself to fire right at the next second boundary. See the
    /// module comment for why this uses addTimeout(), not
    /// repeatTimeout().
    private void tick()
    {
        auto now = Clock.currTime();
        long sec = now.toUnixTime();
        double usecFraction = now.fracSecs.total!"usecs" / 1_000_000.0;
        double delta = 1.0 - usecFraction; // time till next second
        // if current time is just before a full second, show that full
        // second and wait one more second (FLTK: STR 3516)
        if (delta < 0.1)
        {
            delta += 1.0;
            sec++;
        }
        value(cast(ulong) sec);
        fl.core.addTimeout(delta, &tick);
    }
}

// ===========================================================================
// Unit tests
// ===========================================================================

unittest
{
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto c = new ClockOutput(0, 0, 100, 100);
    assert(c.type() == squareClock);
    assert(c.box() == Boxtype.upBox);
    assert(c.selectionColor() == fl_gray_ramp(5));
    assert(c.shadow() == true);
    assert(c.hour() == 0 && c.minute() == 0 && c.second() == 0);
    assert(c.value() == 0);

    fl.core.resetForTest();
}

unittest
{
    // value(H, m, s) only marks damage when something actually
    // changed, and derives value() as seconds-since-midnight.
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto c = new ClockOutput(0, 0, 100, 100);
    c.value(13, 5, 30);
    assert(c.hour() == 13 && c.minute() == 5 && c.second() == 30);
    assert(c.value() == (13 * 60 + 5) * 60 + 30);

    fl.core.resetForTest();
}

unittest
{
    // value(ulong) round-trips through localtime() -- exercised with
    // a fixed epoch second rather than asserting a specific wall-clock
    // hour (that depends on the test machine's timezone), so just
    // check the seconds-since-midnight identity holds.
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto c = new ClockOutput(0, 0, 100, 100);
    c.value(cast(ulong) 1_700_000_000);
    assert(c.value() == (c.hour() * 60 + c.minute()) * 60 + c.second());

    fl.core.resetForTest();
}

unittest
{
    // The type-taking FlClock constructor presets box() to noBox for
    // roundClock and leaves upBox for squareClock.
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto square = new FlClock(squareClock, 0, 0, 100, 100, null);
    assert(square.type() == squareClock);
    assert(square.box() == Boxtype.upBox);

    auto round = new FlClock(roundClock, 0, 0, 100, 100, null);
    assert(round.type() == roundClock);
    assert(round.box() == Boxtype.noBox);

    fl.core.resetForTest();
}

unittest
{
    // FL_SHOW starts the 1-second tick (value() becomes "now" right
    // away, and a timer is scheduled); FL_HIDE stops it.
    import fl.group : FlGroup;
    FlGroup.current(null);
    fl.core.resetForTest();

    auto c = new FlClock(0, 0, 100, 100);
    assert(c.value() == 0);

    c.handle(Event.show);
    // c.value() is seconds-since-midnight in local time (see
    // ClockOutput.value(ulong)), not a raw Unix timestamp -- compare
    // against the local wall-clock hour/minute instead, with a couple
    // seconds of slop against the two currTime() reads landing on
    // different seconds.
    auto localNow = Clock.currTime().toLocalTime();
    assert(c.hour() == localNow.hour);
    assert(c.minute() == localNow.minute || c.minute() == (localNow.minute + 1) % 60);
    assert(fl.core.hasTimeout(&c.tick));

    c.handle(Event.hide);
    assert(!fl.core.hasTimeout(&c.tick));

    fl.core.resetForTest();
}

unittest
{
    // destroy() (deterministic, not GC finalization) cancels any
    // pending tick timer.
    import fl.group : FlGroup;
    FlGroup.current(null);
    fl.core.resetForTest();

    auto c = new FlClock(0, 0, 100, 100);
    c.handle(Event.show);
    assert(fl.core.hasTimeout(&c.tick));

    destroy(c);
    assert(!fl.core.hasTimeout(&c.tick));

    fl.core.resetForTest();
}
