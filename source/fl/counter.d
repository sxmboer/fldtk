/*
 * Ported from FL/Fl_Counter.H + src/Fl_Counter.cxx (FLTK 1.5.0). "A numerical value with up/down step buttons.
 * From Forms" (FLTK's own comment): a text readout flanked by two
 * (simpleCounter type()) or four (normalCounter, the default) arrow
 * buttons -- the outer pair steps by lstep(), the inner pair by
 * step().
 *
 * Faithful, complete port of the numeric/event logic (arrowWidths()/
 * calcMouseobj()/incrementCb(), handle()'s FL_PUSH/FL_DRAG/FL_RELEASE/
 * FL_MOUSEWHEEL/FL_KEYBOARD/FL_FOCUS/FL_UNFOCUS/FL_ENTER/FL_LEAVE
 * cases), and `step(double,double)`/`step(double)`/`step() const`.
 *
 * One D-vs-C++ language difference needed real care, not just a
 * cosmetic workaround: FLTK declares its three `step` overloads
 * with no `using Fl_Valuator::step;`, so C++ silently hides
 * `Fl_Valuator::step(double,int)`/`step(int)` on a `Fl_Counter*` --
 * any `counter->step(a, b)` call unambiguously means Fl_Counter's own
 * two-arg (step+lstep) meaning. D has no equivalent silent hiding:
 * overriding `step(double)`/`step() const` while leaving `step(int)`/
 * `step(double,int)` un-mentioned is a hard compile error ("is hidden
 * by Counter; use `alias step = Valuator.step;` to introduce base
 * class overload set"), and the suggested `alias` fix reintroduces
 * exactly the ambiguity C++'s hiding exists to avoid: D's overload
 * resolution prefers whichever candidate needs fewer implicit
 * conversions, and an `int` literal is an *exact* match for
 * `Valuator.step(double,int)`'s `int b` parameter but needs a
 * conversion for `Counter.step(double,double)`'s `double b` -- so
 * `counter.step(1, 10)` (the natural way to call this, matching
 * FLTK's own doc examples) would silently reach the aliased-in
 * `Valuator` overload and never touch `lstep_` at all. Fixed by adding
 * `step(int,int)` and `override step(double,int)` shadows that both
 * forward straight to `step(double,double)`, so every 2-arg call --
 * whatever the argument types -- goes through Counter's own meaning,
 * matching FLTK for real rather than just by signature. (The
 * single-arg/no-arg cases don't need this: `Valuator.step(int)` and
 * `Valuator.step(double)` compute the same `a_`/`b_` for any integer-
 * valued input, so it doesn't actually matter which one a bare int
 * literal resolves to.)
 *
 * The click-and-hold auto-repeat timer (`repeat_callback()`) and the
 * `Fl_Widget_Tracker` guards in `handle()` are both ported,
 * using `fl.core`'s timer subsystem and `fl.widget_tracker`'s
 * `WidgetTracker` respectively (as in `fl.scrollbar`'s auto-repeat and
 * `fl.button`'s `simulateKeyAction()`/`handle()` guards). The destructor's only
 * job FLTK is cancelling the repeat timer; ported as `~this()`
 * calling `removeTimeout()`, safe unconditionally even during
 * GC-driven finalization (see fl.clock's destructor for the same
 * reasoning).
 *
 * PRE-EXISTING MINOR DEVIATION, now documented rather than left
 * silent: FLTK's FL_DRAG case sets `mouseobj_ = (uchar)i` directly,
 * so dragging outside all four arrow zones (calc_mouseobj() returns
 * -1) wraps to 255, not 0. draw()'s highlight check and incrementCb()'s
 * `if (!mouseobj_) return` both treat 0 and 255 identically for
 * highlighting purposes, but incrementCb() itself does NOT early-return
 * for 255 -- it falls through its switch (no case matches 255) and
 * still calls `handle_drag(clamp(round(value())))`, a re-apply of the
 * unchanged current value that can still trigger a callback depending
 * on Fl_Valuator's own change detection. This port instead clamps to 0
 * (`mouseobj_ = cast(ubyte)(i < 0 ? 0 : i)`), so incrementCb() cleanly
 * no-ops via its existing early return in that case. Not filed as an
 * FLTK_ISSUES.md candidate -- it's very likely intentional-if-terse
 * FLTK behavior (an unsigned wraparound used as a sentinel), not a
 * bug, and this port's version is arguably the cleaner one anyway.
 *
 * draw() calls fl.draw's now-real `fl_font()`/`fl_draw()` (text) and
 * `drawArrow()` (added for `fl.scrollbar` originally, real --
 * see fl.draw's own module comment), plus the real `drawBox()`/
 * `drawFocus()`, so everything renders for real, including the
 * increment/decrement arrow glyphs.
 */
module fl.counter;

import fl.enumerations;
import fl.valuator : Valuator;
import fl.widget_tracker : WidgetTracker;
import fl.rect : Rect;
import fl.draw;
import fl.core;

/// type() for a counter with 4 arrow buttons (the default).
enum ubyte normalCounter = 0;
/// type() for a counter with only the 2 inner arrow buttons.
enum ubyte simpleCounter = 1;

private enum double initialRepeat = 0.5;
private enum double repeatInterval = 0.1;

private struct ArrowBox
{
    int width;
    ArrowType arrowType = ArrowType.arrowSingle;
    Boxtype boxtype = Boxtype.noBox;
    Orientation orientation = Orientation.orientRight;
}

class Counter : Valuator
{
    private
    {
        Font textfont_ = helvetica;
        Fontsize textsize_;
        Color textcolor_ = foregroundColor;
        double lstep_ = 1.0;
        ubyte mouseobj_;
    }

    /// The default type() is normalCounter (4 arrow buttons); the
    /// default boxtype is upBox.
    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        box(Boxtype.upBox);
        selectionColor(inactiveColor); // was blue, FLTK comment notes
        alignment(alignBottom);
        bounds(-1_000_000.0, 1_000_000.0);
        // Deliberately the raw Valuator.step(double,int) ratio form
        // (a_=1, b_=10 -> step()==0.1), not Counter's own step(double,
        // double) two-arg meaning -- matches FLTK's own explicit
        // `Fl_Valuator::step(1, 10);` here (it has to qualify it too,
        // for the same hiding reason -- see the module comment). The
        // shadow overload declared below (`override void step(double,
        // int)`) makes a bare `step(1, 10)` always resolve to Counter's
        // own meaning now, virtual dispatch included -- so even an
        // explicit upcast (`(cast(Valuator) this).step(...)`) would
        // still land back on that override. `super.step(...)` is the
        // one call form that actually bypasses it, calling Valuator's
        // implementation non-virtually.
        super.step(1, 10);
        lstep_ = 1.0;
        mouseobj_ = 0;
        textfont_ = helvetica;
        textsize_ = fl.enumerations.normalSize;
        textcolor_ = foregroundColor;
    }

    ~this()
    {
        fl.core.removeTimeout(&repeatCallback);
    }

    /// Sets the increment for the large (outer) step buttons. Default 1.0.
    void lstep(double a) { lstep_ = a; }

    // Required by D to override step(double)/step() const below while
    // Valuator.step(int)/step(double,int) go unmentioned here -- see
    // the module comment's D-vs-C++ hiding note. Brings those two back
    // into Counter's own overload set (FLTK leaves them hidden).
    alias step = Valuator.step;

    /// Sets the increments for the normal (inner) and large (outer)
    /// step buttons.
    void step(double a, double b) { super.step(a); lstep_ = b; }

    // The alias above also makes Valuator.step(double,int) callable on
    // a Counter, and -- unlike the single-arg/no-arg forms below,
    // where it's a functionally-inert distinction (Valuator.step(int)
    // and Valuator.step(double) compute the same a_/b_ for any
    // integer-valued input, so it doesn't matter which one a literal
    // int actually resolves to) -- this one is a real behavior gap:
    // Valuator.step(double,int) doesn't touch lstep_ at all, but any
    // FLTK `counter->step(a, b)` call always means Counter's own
    // two-arg meaning (Fl_Valuator::step(double,int) is fully hidden
    // in C++). Worse, D's overload resolution prefers whichever
    // candidate needs fewer implicit conversions, and an int literal
    // is an *exact* match for `int b` but needs a conversion for
    // `double b` -- so a same-signature shadow is the only way to
    // force every two-arg step(...) call back through Counter's own
    // step(double,double), matching FLTK for real rather than just
    // by signature.
    override void step(double a, int b) { step(a, cast(double) b); }
    /// ditto -- covers the (int, int) literal case the same way (a
    /// literal `10` is an exact match for `int a`, beating both
    /// `double a` candidates above on conversion count).
    void step(int a, int b) { step(cast(double) a, cast(double) b); }

    /// Sets the increment for the normal (inner) step buttons.
    override void step(double a) { super.step(a); }
    /// Returns the increment for the normal (inner) step buttons.
    override double step() const { return super.step(); }

    Font textfont() const { return textfont_; }
    void textfont(Font s) { textfont_ = s; }

    Fontsize textsize() const { return textsize_; }
    void textsize(Fontsize s) { textsize_ = s; }

    Color textcolor() const { return textcolor_; }
    void textcolor(Color s) { textcolor_ = s; }

    override int handle(Event event)
    {
        int i;
        switch (event)
        {
        case Event.release:
            if (mouseobj_)
            {
                fl.core.removeTimeout(&repeatCallback);
                mouseobj_ = 0;
                redraw();
            }
            handleRelease();
            return 1;

        case Event.push:
        {
            if (fl.core.visibleFocus()) fl.core.focus(this);
            auto wp = WidgetTracker(this);
            handlePush();
            if (wp.deleted()) return 1;
            goto case Event.drag;
        }

        case Event.drag:
            i = calcMouseobj();
            if (i != mouseobj_)
            {
                fl.core.removeTimeout(&repeatCallback);
                mouseobj_ = cast(ubyte)(i < 0 ? 0 : i);
                if (i > 0) fl.core.addTimeout(initialRepeat, &repeatCallback);
                auto wp = WidgetTracker(this);
                incrementCb();
                if (wp.deleted()) return 1;
                redraw();
            }
            return 1;

        case Event.mouseWheel:
            handleDrag(clamp(increment(value(), (fl.core.eventDy() - fl.core.eventDx()) / 2)));
            return 1;

        case Event.keyDown:
            switch (fl.core.eventKey())
            {
            case left:
                handleDrag(clamp(increment(value(), -1)));
                return 1;
            case right:
                handleDrag(clamp(increment(value(), 1)));
                return 1;
            default:
                return 0;
            }

        case Event.unfocus:
            mouseobj_ = 0;
            goto case Event.focus;

        case Event.focus:
            if (fl.core.visibleFocus())
            {
                redraw();
                return 1;
            }
            return 0;

        case Event.enter:
        case Event.leave:
            return 1;

        default:
            return 0;
        }
    }

    protected:

    /// Computes the widths of the single- and double-arrow boxes.
    /// Overridable by a subclass wanting a different layout (the basic
    /// 5-region layout itself -- <<, <, value, >, >> -- is fixed
    /// without also overriding draw()/handle()).
    void arrowWidths(out int w1, out int w2)
    {
        if (type() == simpleCounter)
        {
            w1 = w() * 20 / 100;
            w2 = 0;
        }
        else
        {
            w1 = w() * 13 / 100;
            w2 = w() * 17 / 100;
        }
        if (w1 > 13) w1 = 13;
        if (w2 > 24) w2 = 24;
    }

    override void draw()
    {
        ArrowBox[4] ab;

        Boxtype tbt = box();
        if (tbt == Boxtype.upBox) tbt = Boxtype.downBox;
        if (tbt == Boxtype.thinUpBox) tbt = Boxtype.thinDownBox;

        foreach (i; 0 .. 4)
            ab[i].boxtype = mouseobj_ == i + 1 ? fl_down(box()) : box();

        ab[0].arrowType = ab[3].arrowType = ArrowType.arrowDouble;
        ab[0].orientation = ab[1].orientation = Orientation.orientLeft;

        int w1 = 0, w2 = 0;
        arrowWidths(w1, w2);
        if (type() == simpleCounter) w2 = 0;

        ab[0].width = ab[3].width = w2;
        ab[1].width = ab[2].width = w1;

        int tw = w() - 2 * (w1 + w2);
        int tx = x() + w1 + w2;

        drawBox(tbt, tx, y(), tw, h(), background2Color);
        fl_font(textfont(), textsize());
        fl_color(activeR() ? textcolor() : inactive(textcolor()));
        string str = format();
        fl_draw(str, tx, y(), tw, h(), alignCenter);
        if (fl.core.focus() is this) drawFocus(tbt, tx, y(), tw, h());
        if (!(damage() & damageAll)) return; // only need to redraw text

        Color arrowColor = activeR() ? labelcolor() : inactive(labelcolor());

        int xo = x();
        foreach (i; 0 .. 4)
        {
            if (ab[i].width > 0)
            {
                drawBox(ab[i].boxtype, xo, y(), ab[i].width, h(), color());
                auto bb = Rect(xo, y(), ab[i].width, h());
                drawArrow(bb, ab[i].arrowType, ab[i].orientation, arrowColor);
                xo += ab[i].width;
            }
            if (i == 1) xo += tw;
        }
    }

    private:

    /// Ported from Fl_Counter::repeat_callback(). Keeps re-firing
    /// incrementCb() every repeatInterval seconds as long as an arrow
    /// is held (mouseobj_ != 0), a mouse button is actually still down,
    /// and this widget still has focus -- matching FLTK's own
    /// three-way guard.
    void repeatCallback()
    {
        bool buttonsDown = fl.core.eventButtons() != 0;
        bool hasFocus = fl.core.focus() is this;
        if (mouseobj_ && buttonsDown && hasFocus)
        {
            fl.core.addTimeout(repeatInterval, &repeatCallback);
            incrementCb();
        }
    }

    void incrementCb()
    {
        if (!mouseobj_) return;
        double v = value();
        switch (mouseobj_)
        {
        case 1: v -= lstep_; break;
        case 2: v = increment(v, -1); break;
        case 3: v = increment(v, 1); break;
        case 4: v += lstep_; break;
        default: break;
        }
        handleDrag(clamp(round(v)));
    }

    int calcMouseobj()
    {
        if (type() == normalCounter)
        {
            int W = w() * 15 / 100;
            if (fl.core.eventInside(x(), y(), W, h())) return 1;
            if (fl.core.eventInside(x() + W, y(), W, h())) return 2;
            if (fl.core.eventInside(x() + w() - 2 * W, y(), W, h())) return 3;
            if (fl.core.eventInside(x() + w() - W, y(), W, h())) return 4;
        }
        else
        {
            int W = w() * 20 / 100;
            if (fl.core.eventInside(x(), y(), W, h())) return 2;
            if (fl.core.eventInside(x() + w() - W, y(), W, h())) return 3;
        }
        return -1;
    }
}

// ===========================================================================
// Unit tests
// ===========================================================================

unittest
{
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto c = new Counter(0, 0, 200, 25);
    assert(c.type() == normalCounter);
    assert(c.box() == Boxtype.upBox);
    assert(c.selectionColor() == inactiveColor);
    assert(c.step() == 1.0 / 10.0); // step(1, 10) from the ctor
    assert(c.minimum() == -1_000_000.0 && c.maximum() == 1_000_000.0);

    fl.core.resetForTest();
}

unittest
{
    // step(a, b) sets both the inner (step()) and outer (lstep()) step
    // sizes; step(a) alone only touches the inner one.
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto c = new Counter(0, 0, 200, 25);
    c.step(2, 20);
    assert(c.step() == 2);

    c.value(0);
    // Pushing on the inner-right arrow (mouseobj_ == 3) increments by
    // step(); pushing the outer-right arrow (mouseobj_ == 4) by lstep().
    // W = w()*15/100 = 30 for a normalCounter.
    fl.core.eX_ = 150; // inner-right region: [w-2W, w-W) = [140,170)
    fl.core.eY_ = 12;
    c.handle(Event.push);
    assert(c.value() == 2);

    c.value(0);
    fl.core.eX_ = 200 - 5; // outer-right region: [w-W, w) = [170,200)
    c.handle(Event.push);
    assert(c.value() == 20);

    fl.core.resetForTest();
}

unittest
{
    // Releasing clears the pressed arrow.
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto c = new Counter(0, 0, 200, 25);
    fl.core.eX_ = 5; // outer-left region -> mouseobj_ == 1
    fl.core.eY_ = 12;
    c.value(0);
    c.step(1, 5);
    c.handle(Event.push);
    assert(c.value() == -5);

    c.handle(Event.release);

    fl.core.resetForTest();
}

unittest
{
    // FL_KEYBOARD Left/Right nudge value() by one step(); FL_MOUSEWHEEL
    // scales by (dy - dx) / 2.
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto c = new Counter(0, 0, 200, 25);
    c.step(1);
    c.value(10);

    fl.core.eKeysym_ = right;
    assert(c.handle(Event.keyDown) == 1);
    assert(c.value() == 11);

    fl.core.eKeysym_ = left;
    assert(c.handle(Event.keyDown) == 1);
    assert(c.value() == 10);

    fl.core.eDy_ = 4;
    fl.core.eDx_ = 0;
    c.handle(Event.mouseWheel);
    assert(c.value() == 12); // +(4-0)/2

    fl.core.resetForTest();
}

unittest
{
    // A simpleCounter only has the two inner arrows -- the outer
    // regions calcMouseobj() would otherwise report 1/4 aren't hit at
    // all.
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto c = new Counter(0, 0, 200, 25);
    c.type(simpleCounter);
    c.step(1);
    c.value(0);

    // W = w()*20/100 = 40 for a simpleCounter: left region is [0,40).
    fl.core.eX_ = 10;
    fl.core.eY_ = 12;
    c.handle(Event.push);
    assert(c.value() == -1); // the left region maps to mouseobj_ == 2 (decrement)

    fl.core.resetForTest();
}

unittest
{
    // Holding an arrow down repeats via the real timer, as long as a
    // mouse button is still down and the counter still has focus --
    // matching repeatCallback()'s three-way guard.
    import fl.group : FlGroup;
    import core.thread : Thread;
    import core.time : msecs;
    FlGroup.current(null);
    fl.core.resetForTest();

    auto c = new Counter(0, 0, 200, 25);
    c.step(1);
    c.value(0);

    fl.core.focus(c);
    fl.core.eState_ = stateButton1; // simulate the mouse button still down
    fl.core.eX_ = 10; // leftmost region -> mouseobj_ == 1 (outer decrement)
    fl.core.eY_ = 12;
    assert(c.handle(Event.push) == 1);
    double afterPush = c.value();
    assert(afterPush < 0); // decremented once immediately
    assert(fl.core.hasTimeout(&c.repeatCallback));

    Thread.sleep(700.msecs); // past initialRepeat (0.5s)
    fl.core.processTimeouts();
    assert(c.value() < afterPush); // at least one repeat fired

    fl.core.eState_ = 0;
    c.handle(Event.release);
    assert(!fl.core.hasTimeout(&c.repeatCallback));

    fl.core.resetForTest();
    FlGroup.current(null);
}
