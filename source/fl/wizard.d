/*
 * Ported from FL/Fl_Wizard.H + src/Fl_Wizard.cxx (FLTK 1.5.0,
 * ~/Repositories/fltk). FLTK's own doc comment: "based off the
 * Fl_Tabs widget, but instead of displaying tabs it only changes
 * 'tabs' under program control" -- shows exactly one child at a time,
 * switched via next()/prev()/value(). Navigation buttons are the
 * caller's own responsibility to add.
 *
 * Faithful, complete port of next()/prev()/value()/value(Widget)/
 * value(int)/draw(), including value(Widget)'s mouse-cursor reset
 * (restores the default arrow whenever the visible pane changes, in
 * case the outgoing child left an I-beam or similar behind). One small, documented
 * omission: FLTK declares a private `Fl_Widget *value_` member,
 * sets it to null in the constructor, and never reads it again
 * anywhere -- every method above derives the current child from
 * children's visible() flags each call instead. It's genuinely dead
 * state in FLTK, not a simplification this port made, so it isn't
 * ported: nothing observable changes by omitting a field nothing ever
 * reads.
 */
module fl.wizard;

import fl.group : FlGroup;
import fl.widget : Widget;
import fl.enumerations : Boxtype, damageAll, Cursor;
import fl.draw;

class Wizard : FlGroup
{
    /// The default boxtype is thinUpBox.
    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        box(Boxtype.thinUpBox);
    }

    override void draw()
    {
        Widget kid = value();
        if (damage() & damageAll)
        {
            if (kid !is null)
            {
                drawBox(box(), x(), y(), w(), h(), kid.color());
                drawChild(kid);
            }
            else
                drawBox(box(), x(), y(), w(), h(), color());
        }
        else if (kid !is null)
            updateChild(kid);
    }

    /// Shows the next child. A no-op if the last child is already showing.
    void next()
    {
        auto kids = array();
        size_t i = 0;
        while (i < kids.length && !kids[i].visible()) i++;
        if (i < kids.length && kids.length - i > 1)
            value(kids[i + 1]);
    }

    /// Shows the previous child. A no-op if the first child is already showing.
    void prev()
    {
        auto kids = array();
        size_t i = 0;
        while (i < kids.length && !kids[i].visible()) i++;
        if (i > 0 && i < kids.length)
            value(kids[i - 1]);
    }

    /// Returns the currently visible child. If none currently is, the
    /// last child is made visible (matching FLTK: a freshly-built
    /// Wizard with no explicit value() call shows its last added
    /// child).
    Widget value()
    {
        auto kids = array();
        if (kids.length == 0) return null;

        Widget kid = null;
        foreach (k; kids)
        {
            if (k.visible())
            {
                if (kid !is null)
                    k.hide();
                else
                    kid = k;
            }
        }

        if (kid is null)
        {
            kid = kids[$ - 1];
            kid.show();
        }

        return kid;
    }

    /// Sets the visible child; every other child is hidden. A no-op if
    /// kid isn't one of this Wizard's children.
    void value(Widget kid)
    {
        auto kids = array();
        if (kids.length == 0) return;

        foreach (k; kids)
        {
            if (k is kid)
            {
                if (!k.visible()) k.show();
            }
            else
                k.hide();
        }

        // Restores the default arrow cursor whenever the visible pane
        // changes -- otherwise a text widget that was showing on the
        // *outgoing* pane can leave the system cursor set to an I-beam
        // (or similar) after it's hidden.
        if (window() !is null) window().cursor(Cursor.default_);
    }

    /// Sets the visible child by index. A no-op if ix is out of range.
    void value(int ix)
    {
        if (ix < 0 || ix >= children()) return;
        value(child(ix));
    }
}

// ===========================================================================
// Unit tests
// ===========================================================================

unittest
{
    import fl.box : Box;

    FlGroup.current(null);

    auto w = new Wizard(0, 0, 200, 100);
    assert(w.box() == Boxtype.thinUpBox);

    auto a = new Box(0, 0, 200, 100, "a");
    auto b = new Box(0, 0, 200, 100, "b");
    auto c = new Box(0, 0, 200, 100, "c");
    w.end();

    // No explicit value() yet, and every child starts out visible()
    // (the ordinary default) -- value() picks the first visible child
    // it finds and hides the rest, so page "a" (added first) ends up
    // showing. The last-child fallback only fires when nothing is
    // visible at all (see value()'s doc comment).
    assert(w.value() is a);
    assert(a.visible() && !b.visible() && !c.visible());

    w.next();
    assert(w.value() is b);

    w.next();
    assert(w.value() is c);

    w.next(); // already on the last child -- no-op
    assert(w.value() is c);

    w.prev();
    assert(w.value() is b);

    w.value(0);
    assert(w.value() is a);

    w.prev(); // already on the first child -- no-op
    assert(w.value() is a);

    FlGroup.current(null);
}

unittest
{
    // value()'s fallback: if nothing is visible at all, the last
    // child is made visible.
    import fl.box : Box;

    FlGroup.current(null);

    auto w = new Wizard(0, 0, 200, 100);
    auto a = new Box(0, 0, 200, 100, "a");
    auto b = new Box(0, 0, 200, 100, "b");
    a.hide();
    b.hide();
    w.end();

    assert(w.value() is b);
    assert(b.visible());

    FlGroup.current(null);
}
