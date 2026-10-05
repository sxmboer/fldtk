// D transliteration of FLTK's test/resize-arrows.cxx / resize-arrows.h.
// Shared module imported by the resize_exampleN programs; not itself
// runnable, so it has no standalone binary beyond compiling as part of
// one of those.
module resize_arrows;

import fl;

/// Harrow is a Box with a horizontal arrow drawn across the middle.
///
/// The arrow is drawn in black on a white background.
/// By default, the box has no border, and the label is below the box.
class Harrow : Box
{
    this(int X, int Y, int W, int H, string T = null)
    {
        super(X, Y, W, H, T);
        alignment(alignBottom);
        box(Boxtype.noBox);
        color(white);
    }

    override void draw()
    {
        Color old = fl_color();
        int dx = 5, dy = 4;
        int my = y() + h() / 2;
        fl_rectf(x(), y(), w(), h(), white);
        fl_color(black);
        fl_polygon(x(), my, x() + dx, my - dy, x() + dx, my + dy);
        fl_line(x() + dx, my, x() + w() - dx, my);
        fl_polygon(x() + w(), my, x() + w() - dx, my + dy, x() + w() - dx, my - dy);
        fl_color(old);
    }
}

/// Varrow is a Box with a vertical arrow drawn down the middle.
///
/// The arrow is drawn in black on a white background.
/// By default, the box has no border, and the label is to the right of the box.
class Varrow : Box
{
    this(int X, int Y, int W, int H, string T = null)
    {
        super(X, Y, W, H, T);
        alignment(alignRight);
        box(Boxtype.noBox);
        color(white);
    }

    override void draw()
    {
        Color old = fl_color();
        int dx = 4, dy = 5;
        int mx = x() + w() / 2;
        fl_rectf(x(), y(), w(), h(), white);
        fl_color(black);
        fl_polygon(mx - dx, y() + dy, mx, y(), mx + dx, y() + dy);
        fl_line(mx, y() + dy, mx, y() + h() - dy);
        fl_polygon(mx - dx, y() + h() - dy, mx + dx, y() + h() - dy, mx, y() + h());
        fl_color(old);
    }
}
