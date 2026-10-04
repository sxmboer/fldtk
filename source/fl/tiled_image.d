/*
 * Ported from FL/Fl_Tiled_Image.H + src/Fl_Tiled_Image.cxx (FLTK 1.5.0,
 * ~/Repositories/fltk): Fl_Tiled_Image, a thin wrapper that repeats a
 * source image across a given area. Genuinely self-contained -- draws
 * by calling the wrapped image's own already-real draw() repeatedly
 * within a clip rectangle, no new drawing primitive needed at all.
 *
 * The `W == 0 && H == 0` "tile the whole current window" case is real:
 * `examples/shapedwindow.cxx`'s
 * `Dragbox` binds exactly such a zero-sized tile as its
 * background (see that program's own use of `new TiledImage(pxm)`
 * with no explicit W/H). Backed by `fl.window.Window.current()`
 * (ported from `Fl_Window::current()`/`current_` -- see that function's own doc comment for the small,
 * genuinely separate bit of infrastructure this needed, wired into
 * `fl.platform_x11.flushDamage()`). FLTK's own doc comment still
 * flags this whole area as fragile ("Fix Fl_Tiled_Image as background
 * image for widgets and windows" is a standing `\todo` there), so this
 * is a faithful port of an already-acknowledged-imperfect FLTK
 * feature, not a new guarantee -- `draw(X, Y, 0, 0)` fills whatever
 * window is currently being drawn, exactly matching FLTK, quirks
 * and all.
 */
module fl.tiled_image;

import fl.image : Image;
import fl.enumerations : Color;
import fldraw = fl.draw;
import fl.window : Window;

class TiledImage : Image
{
    protected Image image_;
    protected bool allocImage_;

    /// Tiles image i across a W x H area (0, 0 means "fill the area
    /// passed to draw()", except for the whole-current-window case --
    /// see the module's own top comment).
    this(Image i, int W = 0, int H = 0)
    {
        super(W, H, 0);
        image_ = i;
    }

    alias copy = Image.copy; // re-expose the 0-arg overload the override below hides
    alias draw = Image.draw; // re-expose the 2-arg overload the override below hides

    /// The image being tiled.
    inout(Image) image() inout { return image_; }

    override TiledImage copy(int W, int H) const
    {
        return new TiledImage(cast(Image) image_, W, H);
    }

    /**
     * Blends the tiled image with c. The source image isn't copied
     * unless/until this (or desaturate()) is called -- matches
     * FLTK's own "make our own private copy the first time we
     * need to mutate it" lazy-copy exactly (the tile might otherwise
     * be a widely-shared Image the caller expects to stay unmodified).
     */
    override void colorAverage(Color c, float i)
    {
        ensureOwnCopy();
        image_.colorAverage(c, i);
    }

    /// ditto, for desaturate().
    override void desaturate()
    {
        ensureOwnCopy();
        image_.desaturate();
    }

    private void ensureOwnCopy()
    {
        if (allocImage_) return;
        int w = image_.w(), h = image_.h();
        image_ = image_.copy(image_.dataW(), image_.dataH());
        image_.scale(w, h, false, true);
        allocImage_ = true;
    }

    /**
     * Draws the tile repeatedly across (X,Y,W,H), cropped by (cx,cy)
     * (must be >= 0; ignored if negative, matching FLTK). See the
     * module's own top comment for the `W == 0 && H == 0` "fill the
     * current window" fallback.
     */
    override void draw(int X, int Y, int W, int H, int cx = 0, int cy = 0)
    {
        int iw = image_.w();
        int ih = image_.h();
        if (iw == 0 || ih == 0) return;
        if (cx >= iw || cy >= ih) return;

        if (cx < 0) cx = 0;
        if (cy < 0) cy = 0;

        // W and H null means the image is potentially as large as the
        // current window or widget -- the latter can't be checked here
        // (matching FLTK's own comment on this exact limitation),
        // so this relies on the caller's own clip region.
        if (W == 0 && H == 0 && Window.current() !is null)
        {
            W = Window.current().w();
            H = Window.current().h();
            X = Y = 0;
        }
        if (W == 0 || H == 0) return;

        fldraw.pushClip(X, Y, W, H);

        if (cx > 0) iw -= cx;
        if (cy > 0) ih -= cy;

        for (int yy = Y; yy < Y + H; yy += ih)
        {
            if (fldraw.notClipped(X, yy, W, ih))
            {
                for (int xx = X; xx < X + W; xx += iw)
                {
                    if (fldraw.notClipped(xx, yy, iw, ih))
                        image_.draw(xx, yy, iw, ih, cx, cy);
                }
            }
        }
        fldraw.popClip();
    }
}

unittest
{
    // TiledImage: construction, image()/copy(), and the pure-arithmetic
    // guard clauses in draw() (headless: pushClip()/popClip()/
    // notClipped() work without a display, and image_.draw() with no
    // display just early-returns, matching every other draw()-adjacent
    // test in this port).
    import fl.image : RGBImage;

    ubyte[] bits = [255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 0];
    auto src = new RGBImage(bits, 2, 2, 3);
    auto tile = new TiledImage(src, 40, 40);

    assert(tile.image() is src);
    assert(tile.w() == 40 && tile.h() == 40);

    auto c = tile.copy(80, 20);
    assert(c.w() == 80 && c.h() == 20);
    assert(c.image() is src); // copy() doesn't touch the wrapped image

    // Guard clauses: an empty source image and W==0/H==0 must not crash.
    auto emptySrc = new RGBImage(null, 0, 0, 3);
    auto emptyTile = new TiledImage(emptySrc, 10, 10);
    emptyTile.draw(0, 0, 10, 10);

    tile.draw(0, 0, 0, 0); // W==0 && H==0, Window.current() is null headlessly -- must not crash
    tile.draw(0, 0, 100, 100); // the real, supported path -- must not crash headlessly
}

unittest
{
    // colorAverage()/desaturate(): the lazy-copy-on-first-mutation
    // behavior -- confirms the *original* source image is never
    // touched, only the tile's own private copy.
    import fl.image : RGBImage;
    import fl.enumerations : black;

    ubyte[] bits = [200, 100, 50, 10, 20, 30];
    auto src = new RGBImage(bits.dup, 2, 1, 3);
    auto tile = new TiledImage(src, 40, 40);

    tile.colorAverage(black, 0.0f); // fully replaced by black
    assert((cast(RGBImage) tile.image()).array == [0, 0, 0, 0, 0, 0]);
    assert(src.array == [200, 100, 50, 10, 20, 30]); // untouched
    assert(tile.image() !is src); // ensureOwnCopy() really made a copy
}
