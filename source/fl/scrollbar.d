/*
 * Ported from FL/Fl_Scrollbar.H + src/Fl_Scrollbar.cxx (FLTK 1.5.0,
 * ~/Repositories/fltk).
 *
 * Faithful, complete port of the layout/event/draw logic: a Slider with
 * arrow buttons at each end, added for fl.text_display (which needs
 * both a horizontal and vertical Scrollbar) and fl.terminal.
 *
 * FLTK's `int value() const` deliberately hides (via C++ name
 * hiding, no `using Fl_Slider::value;`) the inherited
 * `double Fl_Slider::value() const`, so the ergonomic default for a
 * Fl_Scrollbar is an int read, with the doc comment telling callers to
 * write `Fl_Slider::value()` explicitly for the double version. D can't
 * reproduce that: overloading by return type alone (two `value()`
 * overloads differing only in `int` vs `double`) is a hard compile
 * error here, not a silent shadow -- there is no legal way to declare
 * both. This port keeps `Slider.value()`'s inherited `double`-returning
 * getter as the only zero-arg `value()` (via `alias value =
 * Slider.value;`, which also keeps the inherited `bool value(double)`
 * setter reachable), and adds `value(int)`/`value(int,int,int,int)` as
 * genuinely distinct overloads (different parameter lists, which D
 * *can* disambiguate). Callers wanting an int read do
 * `cast(int) sb.value()`.
 *
 * The auto-repeat-while-held behavior (`timeout_cb()`) is ported now
 * too, using fl.core's timer subsystem (previously skipped -- see
 * fl.button's `simulateKeyAction()`, which had the same gap and is
 * also now ported). `timeout_cb` (FLTK: a `static void(*)(void*)`
 * needing the scrollbar as `void*` data) becomes a private bound
 * method, per the usual callback-porting convention.
 *
 * draw()'s track/slider boxes (drawBox()) and the end-button arrow
 * glyphs both render for real now -- fl.draw's drawArrow() (added
 * here originally) is real too (see fl.draw's header comment).
 */
module fl.scrollbar;

import fl.enumerations;
import fl.slider : Slider, horSlider, vertNiceSlider, horNiceSlider;
import fl.rect : Rect;
import fl.draw;
import fl.core;

private enum double initialRepeat = 0.5;
private enum double repeatInterval = 0.05;

class Scrollbar : Slider
{
    private
    {
        int linesize_;
        int pushed_;
    }

    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        box(Boxtype.flatBox);
        color(dark2);
        slider(Boxtype.upBox);
        linesize_ = 16;
        pushed_ = 0;
        step(1);
    }

    ~this()
    {
        // Safe unconditionally, even during GC-driven finalization --
        // see fl.clock's destructor for the same reasoning (only
        // touches fl.core's own timer-queue bookkeeping, not another
        // GC object's fields).
        if (pushed_) fl.core.removeTimeout(&timeoutCb);
    }

    /// Brings Slider/Valuator's `double value() const` and
    /// `bool value(double)` into this class's `value` overload set --
    /// see the module's top comment for why a same-arity `int
    /// value() const` can't also be declared alongside it in D.
    alias value = Slider.value;

    /// Sets the value (position) of the slider in the scrollbar. Read
    /// it back with `cast(int) value()` (see the module's top comment).
    int value(int p) { super.value(cast(double) p); return p; }

    /**
     * Sets the position, size and range of the slider in the
     * scrollbar. Call this every time your window changes size, your
     * data changes size, or your scroll position changes (even in
     * response to a callback from this scrollbar). All necessary
     * calls to redraw() are done.
     */
    int value(int pos, int windowSize, int firstLine, int totalLines)
    {
        return scrollvalue(pos, windowSize, firstLine, totalLines) ? 1 : 0;
    }

    /// The step, in lines, that the arrow keys/end buttons move.
    int linesize() const { return linesize_; }
    /// Also controls page up/down: they move by the size last sent to
    /// value() minus one linesize(). Default is 16.
    void linesize(int i) { linesize_ = i; }

    override int handle(Event event)
    {
        int area;
        int X = x(); int Y = y(); int W = w(); int H = h();

        if (horizontal())
        {
            if (W >= 3 * H) { X += H; W -= 2 * H; }
        }
        else
        {
            if (H >= 3 * W) { Y += W; H -= 2 * W; }
        }

        int relx;
        int ww;
        if (horizontal())
        {
            relx = fl.core.eventX() - X;
            ww = W;
        }
        else
        {
            relx = fl.core.eventY() - Y;
            ww = H;
        }

        if (relx < 0) area = 1;
        else if (relx >= ww) area = 2;
        else
        {
            int s = cast(int)(sliderSize() * ww + .5);
            int t = (horizontal() ? H : W) / 2 + 1;
            if (type() == vertNiceSlider || type() == horNiceSlider) t += 4;
            if (s < t) s = t;
            double val = (maximum() - minimum())
                ? (value() - minimum()) / (maximum() - minimum()) : 0.5;
            int sliderx;
            if (val >= 1.0) sliderx = ww - s;
            else if (val <= 0.0) sliderx = 0;
            else sliderx = cast(int)(val * (ww - s) + .5);
            if (fl.core.eventButton() == middleMouse) area = 8;
            else if (relx < sliderx) area = 5;
            else if (relx >= sliderx + s) area = 6;
            else area = 8;
        }

        switch (event)
        {
        case Event.enter:
        case Event.leave:
            return 1;

        case Event.release:
            damage(damageAll);
            if (pushed_)
            {
                fl.core.removeTimeout(&timeoutCb);
                pushed_ = 0;
            }
            handleRelease();
            return 1;

        case Event.push:
            if (pushed_) return 1;
            if (area != 8) pushed_ = area;
            if (pushed_)
            {
                handlePush();
                fl.core.addTimeout(initialRepeat, &timeoutCb);
                incrementCb();
                damage(damageAll);
                return 1;
            }
            return handleAt(event, X, Y, W, H);

        case Event.drag:
            if (pushed_) return 1;
            return handleAt(event, X, Y, W, H);

        case Event.mouseWheel:
            if (horizontal())
            {
                if (fl.core.eventDx() == 0) return 0;
                int ls = maximum() >= minimum() ? linesize_ : -linesize_;
                handleDrag(clamp(value() + ls * fl.core.eventDx()));
                return 1;
            }
            else
            {
                if (fl.core.eventDy() == 0) return 0;
                int ls = maximum() >= minimum() ? linesize_ : -linesize_;
                handleDrag(clamp(value() + ls * fl.core.eventDy()));
                return 1;
            }

        case Event.shortcut:
        case Event.keyDown:
        {
            int v = cast(int) value();
            int ls = maximum() >= minimum() ? linesize_ : -linesize_;
            if (horizontal())
            {
                if (fl.core.eventKey() == left) v -= ls;
                else if (fl.core.eventKey() == right) v += ls;
                else return 0;
            }
            else
            {
                if (fl.core.eventKey() == up) v -= ls;
                else if (fl.core.eventKey() == down) v += ls;
                else if (fl.core.eventKey() == pageUp)
                {
                    if (sliderSize() >= 1.0) return 0;
                    v -= cast(int)((maximum() - minimum()) * sliderSize() / (1.0 - sliderSize()));
                    v += ls;
                }
                else if (fl.core.eventKey() == pageDown)
                {
                    if (sliderSize() >= 1.0) return 0;
                    v += cast(int)((maximum() - minimum()) * sliderSize() / (1.0 - sliderSize()));
                    v -= ls;
                }
                else if (fl.core.eventKey() == home) v = cast(int) minimum();
                else if (fl.core.eventKey() == end) v = cast(int) maximum();
                else return 0;
            }
            v = cast(int) clamp(v);
            if (v != value())
            {
                super.value(cast(double) v);
                valueDamage();
                setChanged();
                doCallback(CallbackReason.dragged);
            }
            return 1;
        }

        default:
            return 0;
        }
    }

    override void draw()
    {
        if (damage() & damageAll) drawBox();
        int X = x() + fl.core.boxDx(box());
        int Y = y() + fl.core.boxDy(box());
        int W = w() - fl.core.boxDw(box());
        int H = h() - fl.core.boxDh(box());

        int inset = 2;
        if (W < 8 || H < 8) inset = 1;

        if (horizontal())
        {
            if (W < 3 * H)
            {
                drawSlider(X, Y, W, H);
                return;
            }
            drawSlider(X + H, Y, W - 2 * H, H);
            if (damage() & damageAll)
            {
                drawBox((pushed_ == 1) ? fl_down(slider()) : slider(), X, Y, H, H, selectionColor());
                drawBox((pushed_ == 2) ? fl_down(slider()) : slider(), X + W - H, Y, H, H, selectionColor());

                Color arrowcolor = activeR() ? labelcolor() : inactive(labelcolor());
                Rect ab = Rect(X, Y, H, H);
                ab.inset(inset);
                drawArrow(ab, ArrowType.arrowSingle, Orientation.orientLeft, arrowcolor);
                ab = Rect(X + W - H, Y, H, H);
                ab.inset(inset);
                drawArrow(ab, ArrowType.arrowSingle, Orientation.orientRight, arrowcolor);
            }
        }
        else
        {
            if (H < 3 * W)
            {
                drawSlider(X, Y, W, H);
                return;
            }
            drawSlider(X, Y + W, W, H - 2 * W);
            if (damage() & damageAll)
            {
                drawBox((pushed_ == 1) ? fl_down(slider()) : slider(), X, Y, W, W, selectionColor());
                drawBox((pushed_ == 2) ? fl_down(slider()) : slider(), X, Y + H - W, W, W, selectionColor());

                Color arrowcolor = activeR() ? labelcolor() : inactive(labelcolor());
                Rect ab = Rect(X, Y, W, W);
                ab.inset(inset);
                drawArrow(ab, ArrowType.arrowSingle, Orientation.orientUp, arrowcolor);
                ab = Rect(X, Y + H - W, W, W);
                ab.inset(inset);
                drawArrow(ab, ArrowType.arrowSingle, Orientation.orientDown, arrowcolor);
            }
        }
    }

    /// Ported from Fl_Scrollbar::timeout_cb(). Repeats incrementCb()
    /// every repeatInterval seconds while a button/track area stays
    /// pushed.
    private void timeoutCb()
    {
        incrementCb();
        fl.core.addTimeout(repeatInterval, &timeoutCb);
    }

    /// Ported from Fl_Scrollbar::increment_cb().
    private void incrementCb()
    {
        bool inv = maximum() < minimum();
        int ls = inv ? -linesize_ : linesize_;
        int i;
        switch (pushed_)
        {
        case 1: // clicked on arrow left/up
            i = -ls;
            break;
        case 5: // clicked into the track on the left/above the slider
            i = -cast(int)((maximum() - minimum()) * sliderSize() / (1.0 - sliderSize()));
            if (inv) { if (i < -ls) i = -ls; }
            else { if (i > -ls) i = -ls; }
            break;
        case 6: // clicked into the track on the right/below the slider
            i = cast(int)((maximum() - minimum()) * sliderSize() / (1.0 - sliderSize()));
            if (inv) { if (i > ls) i = ls; }
            else { if (i < ls) i = ls; }
            break;
        default: // clicked on arrow right/down
            i = ls;
            break;
        }
        handleDrag(clamp(value() + i));
    }
}

unittest
{
    import fl.group : FlGroup;

    FlGroup.current(null);

    auto s = new Scrollbar(0, 0, 20, 100);
    assert(s.box() == Boxtype.flatBox);
    assert(s.color() == dark2);
    assert(s.slider() == Boxtype.upBox);
    assert(s.linesize() == 16);
    assert(s.value() == 0);

    s.value(5);
    assert(s.value() == 5);

    FlGroup.current(null);
}

unittest
{
    // value(pos, size, first, total) drives Slider.scrollvalue()'s
    // bounds()/sliderSize() setup, same as fl.slider's own test for it.
    import fl.group : FlGroup;

    FlGroup.current(null);

    auto s = new Scrollbar(0, 0, 20, 100);
    s.value(0, 10, 0, 100);
    assert(s.minimum() == 0);
    assert(s.maximum() == 90);
    assert(s.value() == 0);

    FlGroup.current(null);
}

unittest
{
    // Clicking the top arrow of a vertical scrollbar (relx < 0, i.e.
    // inside the arrow-button strip) increments toward the minimum by
    // one linesize() immediately, and schedules the repeat timer
    // (verified by the next unittest -- this one just checks the
    // immediate click and that releasing cancels it).
    import fl.group : FlGroup;

    FlGroup.current(null);
    fl.core.focus(null);

    auto s = new Scrollbar(0, 0, 20, 200); // vertical, H=200 >= 3*W=60
    s.bounds(0, 100);
    s.value(50);
    s.linesize(5);

    fl.core.eX_ = 10;
    fl.core.eY_ = 2; // inside the top arrow button (H=W=20 here)
    assert(s.handle(Event.push) == 1);
    assert(s.value() == 45); // moved one linesize toward the minimum
    assert(fl.core.hasTimeout(&s.timeoutCb));

    s.handle(Event.release);
    assert(!fl.core.hasTimeout(&s.timeoutCb));

    fl.core.resetForTest();
    FlGroup.current(null);
}

unittest
{
    // Holding the arrow down (not releasing) repeats incrementCb()
    // via the real timer, on top of the initial immediate click.
    import fl.group : FlGroup;
    import core.thread : Thread;
    import core.time : msecs;

    FlGroup.current(null);
    fl.core.focus(null);

    auto s = new Scrollbar(0, 0, 20, 200);
    s.bounds(0, 1000);
    s.value(500);
    s.linesize(5);

    fl.core.eX_ = 10;
    fl.core.eY_ = 2; // top arrow
    assert(s.handle(Event.push) == 1);
    assert(s.value() == 495); // immediate click

    Thread.sleep(700.msecs); // past initialRepeat (0.5s)
    fl.core.processTimeouts();
    assert(s.value() < 495); // at least one repeat fired

    s.handle(Event.release);
    assert(!fl.core.hasTimeout(&s.timeoutCb));

    fl.core.resetForTest();
    FlGroup.current(null);
}

unittest
{
    // Keyboard: Up/Down nudge by linesize() on a vertical scrollbar;
    // Home/End jump to the range ends.
    import fl.group : FlGroup;

    FlGroup.current(null);
    fl.core.focus(null);

    auto s = new Scrollbar(0, 0, 20, 200);
    s.bounds(0, 100);
    s.value(50);
    s.linesize(5);

    fl.core.eKeysym_ = down;
    assert(s.handle(Event.keyDown) == 1);
    assert(s.value() == 55);

    fl.core.eKeysym_ = up;
    assert(s.handle(Event.keyDown) == 1);
    assert(s.value() == 50);

    fl.core.eKeysym_ = end;
    assert(s.handle(Event.keyDown) == 1);
    assert(s.value() == 100);

    fl.core.eKeysym_ = home;
    assert(s.handle(Event.keyDown) == 1);
    assert(s.value() == 0);

    fl.core.eKeysym_ = left; // ignored: this scrollbar is vertical
    assert(s.handle(Event.keyDown) == 0);

    fl.core.resetForTest();
    FlGroup.current(null);
}

unittest
{
    // Mouse wheel scrolls by linesize() per wheel unit.
    import fl.group : FlGroup;

    FlGroup.current(null);
    fl.core.focus(null);

    auto s = new Scrollbar(0, 0, 20, 200);
    s.bounds(0, 100);
    s.value(50);
    s.linesize(5);

    fl.core.eDy_ = 2;
    assert(s.handle(Event.mouseWheel) == 1);
    assert(s.value() == 60);

    fl.core.eDy_ = 0;
    assert(s.handle(Event.mouseWheel) == 0); // no vertical delta -> not handled

    fl.core.resetForTest();
    FlGroup.current(null);
}
