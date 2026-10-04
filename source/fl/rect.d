/*
 * Ported from FL/Fl_Rect.H (FLTK 1.5.0). A plain (x, y, w, h) rectangle,
 * used internally by fl.group's child-layout bookkeeping and by other
 * widgets that need to describe a screen area without being a Widget
 * themselves.
 *
 * Not ported: the `friend operator==`/`!=` overloads -- D structs get
 * field-wise equality for free, so opEquals doesn't need to be written
 * by hand.
 */
module fl.rect;

import fl.enumerations : Boxtype;
import fl.widget : Widget;
import fl.core;

struct Rect
{
    private int x_, y_, w_, h_;

    this(int w, int h)
    {
        x_ = 0; y_ = 0; w_ = w; h_ = h;
    }

    this(int x, int y, int w, int h)
    {
        x_ = x; y_ = y; w_ = w; h_ = h;
    }

    this(int x, int y, int w, int h, Boxtype bt)
    {
        x_ = x; y_ = y; w_ = w; h_ = h;
        inset(bt);
    }

    this(const(Widget) widget)
    {
        x_ = widget.x(); y_ = widget.y(); w_ = widget.w(); h_ = widget.h();
    }

    int x() const { return x_; }
    int y() const { return y_; }
    int w() const { return w_; }
    int h() const { return h_; }

    /// Right edge (x + w); outside the rectangle's area, like r-values in Fl_Rect.
    int r() const { return x_ + w_; }
    /// Bottom edge (y + h); outside the rectangle's area, like b-values in Fl_Rect.
    int b() const { return y_ + h_; }

    void x(int v) { x_ = v; }
    void y(int v) { y_ = v; }
    void w(int v) { w_ = v; }
    void h(int v) { h_ = v; }

    void r(int v) { w_ = v - x_; }
    void b(int v) { h_ = v - y_; }

    /// Shrinks the rectangle by d on all sides (enlarges if d is negative).
    void inset(int d)
    {
        x_ += d;
        y_ += d;
        w_ -= 2 * d;
        h_ -= 2 * d;
    }

    /// Shrinks the rectangle by bt's frame width/height on all sides.
    void inset(Boxtype bt)
    {
        x_ += fl.core.boxDx(bt);
        y_ += fl.core.boxDy(bt);
        w_ -= fl.core.boxDw(bt);
        h_ -= fl.core.boxDh(bt);
    }

    void inset(int left, int top, int right, int bottom)
    {
        x_ += left;
        y_ += top;
        w_ -= (left + right);
        h_ -= (top + bottom);
    }

    bool contains(int px, int py) const
    {
        return px >= x_ && px < r() && py >= y_ && py < b();
    }
}

unittest
{
    auto r = Rect(10, 20, 100, 50);
    assert(r.x == 10 && r.y == 20 && r.w == 100 && r.h == 50);
    assert(r.r == 110 && r.b == 70);
    assert(r.contains(10, 20));
    assert(!r.contains(110, 70));

    r.inset(5);
    assert(r == Rect(15, 25, 90, 40));

    assert(Rect(50, 60) == Rect(0, 0, 50, 60));
}
