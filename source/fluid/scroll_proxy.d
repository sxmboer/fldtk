/*
 * The `Scroll` shown on the design canvas. A plain `Scroll` scrolls by
 * copying the pixels already on the window and patching the exposed strip,
 * which assumes nothing but its own children was painted there. On the
 * canvas the window also paints a background pattern and container
 * outlines under and over the children, and those would be dragged along
 * with the copy. So every scroll repaints the whole canvas window instead.
 * Live Resize and generated code use a plain `fl.scroll.Scroll`.
 */
module fluid.scroll_proxy;

import fl;

final class ScrollProxy : Scroll
{
    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
    }

    override void scrollTo(int X, int Y)
    {
        int oldX = xposition(), oldY = yposition();
        super.scrollTo(X, Y);
        if (oldX == xposition() && oldY == yposition()) return;
        if (auto win = window())
            win.redraw();
    }
}
