/*
 * Ported from FL/Fl_Pack.H + src/Fl_Pack.cxx (FLTK 1.5.0). "Designed to add the functionality of
 * compressing and aligning widgets" (FLTK's own doc comment):
 * lays its children out end-to-end (horizontally or vertically per
 * type()), skipping hidden ones, and resizes itself to exactly wrap
 * them every time it draws.
 *
 * Faithful, complete port of draw()/drawFiller()/resize()/clear(),
 * including the two FLTK quirks it depends on: the "last child,
 * if it's also resizable(), takes all remaining room" special case,
 * and resizing the Pack itself from inside draw() via
 * Widget.resizeBoundsOnly() -- the D equivalent of FLTK's
 * explicit `Fl_Widget::resize(...)` qualification, which bypasses
 * both Fl_Group's child-layout algorithm and Fl_Pack's own
 * resize()-triggers-redraw() override (see that method's doc comment
 * in fl.widget for the full explanation).
 *
 * draw() calls fl.draw's pushClip()/popClip() (real now -- only
 * reached when box() has a background AND spacing() leaves a gap to
 * fill, e.g. a _BOX boxtype with spacing() > 0), and draws real pixels
 * everywhere else too (its children, fl_rectf(), drawBox()).
 */
module fl.pack;

import fl.group : FlGroup;
import fl.widget : Widget;
import fl.rect : Rect;
import fl.enumerations;
import fl.draw;
import fl.core;

/// type() for vertical stacking (the default): children are resized
/// to this Pack's width and stacked top to bottom.
enum ubyte packVertical = 0;
/// type() for horizontal stacking: children are resized to this
/// Pack's height and placed left to right.
enum ubyte packHorizontal = 1;

class Pack : FlGroup
{
    private int spacing_;

    /// The default boxtype is noBox and the default type() is
    /// packVertical. resizable() starts null (unlike a plain FlGroup,
    /// whose resizable() defaults to itself).
    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        resizable(null);
        spacing_ = 0;
    }

    /// Extra pixels of blank space added between children.
    int spacing() const { return spacing_; }
    /// ditto
    void spacing(int i) { spacing_ = i; }

    /// Non-zero if this Pack's alignment is horizontal (type() ==
    /// packHorizontal).
    ubyte horizontal() const { return type(); }

    override void draw()
    {
        int tx = x() + fl.core.boxDx(box());
        int ty = y() + fl.core.boxDy(box());
        int tw = w() - fl.core.boxDw(box());
        int th = h() - fl.core.boxDh(box());
        int rw, rh;
        int currentPosition = horizontal() ? tx : ty;
        int maximumPosition = currentPosition;
        Damage d = damage();
        auto a = array();

        if (horizontal())
        {
            rw = -spacing_;
            rh = th;
            for (int i = children(); i--;)
                if (child(i).visible())
                {
                    if (child(i) !is this.resizable()) rw += child(i).w();
                    rw += spacing_;
                }
        }
        else
        {
            rw = tw;
            rh = -spacing_;
            for (int i = children(); i--;)
                if (child(i).visible())
                {
                    if (child(i) !is this.resizable()) rh += child(i).h();
                    rh += spacing_;
                }
        }

        int idx = 0;
        for (int i = children(); i--;)
        {
            Widget o = a[idx++];
            if (o.visible())
            {
                int X, Y, W, H;
                if (horizontal())
                {
                    X = currentPosition;
                    W = o.w();
                    Y = ty;
                    H = th;
                }
                else
                {
                    X = tx;
                    W = tw;
                    Y = currentPosition;
                    H = o.h();
                }
                // Last child, if resizable, takes all remaining room.
                if (i == 0 && o is this.resizable())
                {
                    if (horizontal()) W = tw - rw;
                    else H = th - rh;
                }
                if (spacing_ && currentPosition > maximumPosition && box() != Boxtype.noBox
                    && (X != o.x() || Y != o.y() || (d & damageAll)))
                {
                    if (horizontal())
                        drawFiller(Rect(maximumPosition, ty, spacing_, th));
                    else
                        drawFiller(Rect(tx, maximumPosition, tw, spacing_));
                }
                if (X != o.x() || Y != o.y() || W != o.w() || H != o.h())
                {
                    o.resize(X, Y, W, H);
                    // Clear all damage flags, but *set* damageAll, even
                    // if the widget may be clipped by the parent and
                    // needs no redraw.
                    o.clearDamage(damageAll);
                }
                if (d & damageAll)
                {
                    drawChild(o);
                    drawOutsideLabel(o);
                }
                else
                    updateChild(o);
                // Make sure that all damage flags are cleared.
                o.clearDamage();
                // Child's draw() can change its size, so use the new size:
                currentPosition += horizontal() ? o.w() : o.h();
                if (currentPosition > maximumPosition)
                    maximumPosition = currentPosition;
                currentPosition += spacing_;
            }
        }

        if (horizontal())
        {
            if (maximumPosition < tx + tw && box() != Boxtype.noBox)
                drawFiller(Rect(maximumPosition, ty, tx + tw - maximumPosition, th));
            tw = maximumPosition - tx;
        }
        else
        {
            if (maximumPosition < ty + th && box() != Boxtype.noBox)
                drawFiller(Rect(tx, maximumPosition, tw, ty + th - maximumPosition));
            th = maximumPosition - ty;
        }

        tw += fl.core.boxDw(box());
        if (tw <= 0) tw = 1;
        th += fl.core.boxDh(box());
        if (th <= 0) th = 1;
        if (tw != w() || th != h())
        {
            resizeBoundsOnly(x(), y(), tw, th);
            // Cast always safe: a real FlGroup's own parent is always
            // itself a FlGroup or null (see Widget.parent()'s own doc
            // comment / FlGroup.end()'s identical cast).
            FlGroup p = cast(FlGroup) this.parent();
            if (p !is null) p.initSizes();
            d = damageAll;
        }

        if (d & damageAll)
        {
            if (fl.core.boxBg(box()))
                // Only draw the frame part -- children/fillers are
                // already rendered at this point.
                drawBox(fl_frame(box()), x(), y(), w(), h(), color());
            else
                drawBox();
            drawLabel();
        }
    }

    /// Resizing a Pack never resizes its children directly; it just
    /// redraws, which recomputes every child's position/size from
    /// scratch (see draw()).
    override void resize(int X, int Y, int W, int H)
    {
        resizeBoundsOnly(X, Y, W, H);
        redraw();
    }

    /// Deletes all child widgets (FlGroup.clear()) and resets
    /// resizable() to null (a plain FlGroup's clear() resets it to the
    /// group itself; Pack's default is null instead, see the
    /// constructor).
    override void clear()
    {
        super.clear();
        resizable(null);
    }

    /// Fills rect as background: clips to it and draws box() if it has
    /// a background (a `_BOX` boxtype), otherwise just fills it with
    /// color().
    protected void drawFiller(Rect rect)
    {
        if (fl.core.boxBg(box()))
        {
            pushClip(rect.x(), rect.y(), rect.w(), rect.h());
            drawBox();
            popClip();
        }
        else
        {
            fl_rectf(rect.x(), rect.y(), rect.w(), rect.h(), color());
        }
    }
}

// ===========================================================================
// Unit tests
// ===========================================================================

unittest
{
    import fl.box : Box;

    FlGroup.current(null);

    auto p = new Pack(0, 0, 200, 100);
    assert(p.box() == Boxtype.noBox);
    assert(p.type() == packVertical);
    assert(p.resizable() is null);
    assert(p.spacing() == 0);

    p.spacing(5);
    assert(p.spacing() == 5);

    FlGroup.current(null);
}

unittest
{
    // Vertical (default) stacking: draw() lays out visible children
    // top to bottom at this Pack's width, skipping hidden ones, and
    // shrink-wraps itself to their total height.
    import fl.box : Box;

    FlGroup.current(null);

    auto p = new Pack(10, 20, 200, 500);
    auto a = new Box(0, 0, 30, 40, "a");
    auto b = new Box(0, 0, 30, 60, "b");
    auto c = new Box(0, 0, 30, 25, "c");
    p.end();
    b.hide();

    p.draw();

    assert(a.x() == 10 && a.y() == 20 && a.w() == 200 && a.h() == 40);
    // b is hidden -- skipped entirely, keeps its old bounds untouched.
    assert(b.x() == 0 && b.y() == 0);
    assert(c.x() == 10 && c.y() == 60 && c.w() == 200 && c.h() == 25);

    // Shrink-wrapped to the visible children's total height (40 + 25).
    assert(p.h() == 65);

    FlGroup.current(null);
}

unittest
{
    // Horizontal stacking with spacing(): children are placed left to
    // right at this Pack's height, separated by spacing() pixels.
    import fl.box : Box;

    FlGroup.current(null);

    auto p = new Pack(0, 0, 500, 50);
    p.type(packHorizontal);
    p.spacing(10);
    auto a = new Box(0, 0, 40, 0, "a");
    auto b = new Box(0, 0, 60, 0, "b");
    p.end();

    p.draw();

    assert(a.x() == 0 && a.w() == 40 && a.h() == 50);
    assert(b.x() == 50 && b.w() == 60 && b.h() == 50); // 40 + spacing(10)
    assert(p.w() == 110); // 40 + 10 + 60

    FlGroup.current(null);
}

unittest
{
    // The last child, if it's also resizable(), takes all remaining
    // room instead of its own natural size.
    import fl.box : Box;

    FlGroup.current(null);

    auto p = new Pack(0, 0, 300, 100);
    p.type(packHorizontal);
    auto a = new Box(0, 0, 50, 0, "a");
    auto b = new Box(0, 0, 9999, 0, "b"); // natural size irrelevant once resizable
    p.resizable(b);
    p.end();

    p.draw();

    assert(a.w() == 50);
    assert(b.x() == 50 && b.w() == 250); // fills the rest of 300

    FlGroup.current(null);
}
