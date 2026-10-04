/*
 * Ported from FL/Fl_Box.H + src/Fl_Box.cxx (FLTK 1.5.0, ~/Repositories/fltk).
 *
 * Faithful, complete port. Fl_Box is FLTK's simplest widget: it
 * just draws its box and label, and eats FL_ENTER/FL_LEAVE so hovering
 * over one doesn't propagate to whatever's behind it. draw() forwards
 * to Widget.drawBox()/drawLabel(), both real now (see fl.widget's own
 * top-of-file comment), so a Box paints real pixels -- box and label
 * both -- for every boxtype fl.draw's drawBoxAt() covers (see that
 * module's own note for which ones).
 */
module fl.box;

import fl.enumerations : Boxtype, Event;
import fl.widget : Widget;

class Box : Widget
{
    /// Box defaults to Boxtype.noBox (invisible); use the other
    /// constructor, or box(Boxtype), for a visible one. An invisible
    /// Box is still useful as a placeholder or a FlGroup.resizable().
    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
    }

    this(Boxtype b, int x, int y, int w, int h, string label)
    {
        super(x, y, w, h, label);
        box(b);
    }

    override void draw()
    {
        drawBox();
        drawLabel();
    }

    override int handle(Event event)
    {
        if (event == Event.enter || event == Event.leave) return 1;
        return 0;
    }
}

unittest
{
    import fl.group : FlGroup;

    FlGroup.current(null);

    auto b = new Box(10, 20, 100, 50, "hello");
    assert(b.x == 10 && b.y == 20 && b.w == 100 && b.h == 50);
    assert(b.label == "hello");
    assert(b.box == Boxtype.noBox);

    assert(b.handle(Event.enter) == 1);
    assert(b.handle(Event.leave) == 1);
    assert(b.handle(Event.push) == 0);

    FlGroup.current(null);
}

unittest
{
    import fl.group : FlGroup;

    FlGroup.current(null);

    auto b = new Box(Boxtype.upBox, 0, 0, 10, 10, "x");
    assert(b.box == Boxtype.upBox);

    FlGroup.current(null);
}
