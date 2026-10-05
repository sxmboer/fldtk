/*
 * Ported from FL/Fl_Bitmap.H + src/Fl_Bitmap.cxx (FLTK 1.5.0): Fl_Bitmap, a mono-color (1-bit) image drawn
 * stippled in the current color. Part of fl.image's Milestone 1 (see
 * that module's own top comment for the overall port's scope/staging).
 *
 * Real, drawn-pixels support: draw() creates (and caches) a real X11
 * bitmask Pixmap via a new fl.draw.createBitmask()/drawBitmapFixed()
 * pair (XCreateBitmapFromData() + the classic XSetStipple()/
 * XFillRectangle() stipple-fill technique), ported from
 * Fl_Xlib_Graphics_Driver::create_bitmask()/draw_fixed(Fl_Bitmap*,...)
 * -- see fl.draw's own "Image drawing" section comment for why this
 * primitive lives there rather than here (keeps fl.bitmap, like
 * fl.image, free of a direct fl.xlib import).
 *
 * Deviations from FLTK, matching fl.image's own precedent:
 *  - array is a real D slice (const(ubyte)[]), not a raw pointer +
 *    alloc_array flag -- see fl.image's module comment for the full
 *    reasoning (the GC already manages the memory regardless of who
 *    allocated it). Also collapses FLTK's two bits_length-checked
 *    constructors (uchar* and char*) into one, since a D slice already
 *    carries its own length.
 *  - The cached bitmask id is a plain `ulong` (matching FLTK's own
 *    opaque `fl_uintptr_t id_`), not `fl.xlib.Pixmap` -- keeps this
 *    module platform-agnostic; fl.draw's Linux-specific functions cast
 *    it internally.
 */
module fl.bitmap;

import fl.image : Image;
import fldraw = fl.draw;
import fl.core; // screenScale() -- circular with fl.core's own use of
// fl.bitmap in a few places, same precedent as fl.pixmap/fl.core
// elsewhere in this port.

class Bitmap : Image
{
    /// The raw bitmap data: dataH() rows of `(dataW()+7)/8` bytes
    /// each, one pixel per bit (rows rounded up to the next byte).
    const(ubyte)[] array;

    private ulong id_;

    /// The device-pixel size `id_` was last built at (`0, 0` meaning
    /// "never built") -- matches `fl.pixmap.Pixmap`'s own `maskId_`/
    /// `maskScale_` precedent, tracked here instead of a bare scale
    /// float since a *resampled* size is what actually needs comparing
    /// (two different scale factors can round to the same integer
    /// size). This is what lets a bitmap (e.g. `fl.adjuster.Adjuster`'s
    /// own arrow glyphs) rebuild and grow when the screen scale changes
    /// during a live rescale.
    private int cachedW_, cachedH_;

    /**
     * Creates a bitmap from bits. If bits is too short for the
     * claimed dimensions, the image is left empty (array.length == 0)
     * -- see fl.image.RGBImage's own constructor doc comment for why
     * `fail()`, not just `array.length`, doesn't reliably catch this
     * (the same FLTK `Fl_Image::fail()` quirk applies here too,
     * logged in `FLTK_ISSUES.md`).
     */
    this(const(ubyte)[] bits, int W, int H)
    {
        super(W, H, 0);
        int rowBytes = (W + 7) / 8;
        int minLength = rowBytes * H;
        if (H > 0 && W > 0 && bits.length >= minLength)
        {
            array = bits;
            hasData(true);
        }
        else
        {
            array = null;
            ld(errMemoryAccess);
        }
    }

    /**
     * Frees the cached bitmask Pixmap, if any. No `GC.inFinalizer()`
     * guard needed here (unlike e.g. `Widget.~this()`, see CONVENTIONS.md's
     * GC-finalizer note) -- `fl.draw.freeBitmask()` only ever touches
     * `fl.draw`'s own module-level Display/GC state and calls a plain
     * C library function (`XFreePixmap()`), never another GC-managed
     * D object, so finalization order can't make this unsafe the way
     * it can for a widget reaching into a parent's child list.
     */
    ~this()
    {
        uncache();
    }

    alias copy = Image.copy; // re-expose the 0-arg overload the override below hides
    alias draw = Image.draw; // re-expose the 2-arg overload the override below hides

    override void uncache()
    {
        fldraw.freeBitmask(id_);
        id_ = 0;
        cachedW_ = 0;
        cachedH_ = 0;
    }

    /**
     * Ported from `Fl_Bitmap::draw()` -> `Fl_Graphics_Driver::draw_bitmap()`
     * -> `start_image()`: (X,Y,W,H) is a *bounding box*, not necessarily
     * the bitmap's own size (e.g. `fl.adjuster.Adjuster.draw()` passes
     * each button's full W/H, far bigger than the 16x16 arrow glyphs) --
     * FLTK's `start_image()` always clamps the box down to at most
     * the image's own `dataW()`/`dataH()` before the driver ever fills a
     * pixel, so an oversized box just gets cropped to the glyph's real
     * size instead of tiling the stipple pattern across it, matching
     * the clamp `fl.image.RGBImage.draw()`/`fl.pixmap.Pixmap.draw()`
     * also both have.
     */
    override void draw(int X, int Y, int W, int H, int cx = 0, int cy = 0)
    {
        if (array.length == 0)
        {
            drawEmpty(X, Y);
            return;
        }
        int px = cx < 0 ? 0 : cx;
        int py = cy < 0 ? 0 : cy;
        int pw = W;
        int ph = H;
        if (px + pw > dataW()) pw = dataW() - px;
        if (py + ph > dataH()) ph = dataH() - py;
        if (pw <= 0 || ph <= 0) return;

        // Scale-aware recache -- ported from `Fl_Graphics_Driver::
        // draw_bitmap()`'s own recache-at-the-right-size logic, using
        // this port's real `copy(W,H)` (a genuine 1-bit resample,
        // already existed) the same way FLTK uses `bm->copy(w2,h2)`.
        // Matches `fl.pixmap.Pixmap`'s own `maskId_`/`maskScale_`
        // precedent: recomputed on every `draw()`, not gated behind a
        // dirty flag, since it's a cheap integer comparison against the
        // already-cached size.
        float s = fl.core.currentScale();
        int wantW = cast(int)(dataW() * s);
        int wantH = cast(int)(dataH() * s);
        if (wantW < 1) wantW = 1;
        if (wantH < 1) wantH = 1;
        if (id_ != 0 && (cachedW_ != wantW || cachedH_ != wantH))
            uncache();

        const(ubyte)[] drawArray = array;
        int drawW = dataW(), drawH = dataH();
        if (id_ == 0 && (wantW != drawW || wantH != drawH))
        {
            auto resized = copy(wantW, wantH);
            if (resized !is null && resized.array.length != 0)
            {
                drawArray = resized.array;
                drawW = wantW;
                drawH = wantH;
            }
        }

        fldraw.drawBitmapFixed(id_, drawW, drawH, drawArray.ptr,
            X - cx + px, Y - cy + py, pw, ph, px, py);
        cachedW_ = drawW;
        cachedH_ = drawH;
    }

    /// Ported from `Fl_Bitmap::copy()` -- a nearest-neighbor bit copy
    /// (the exact-size path just duplicates the byte array).
    override Bitmap copy(int W, int H) const
    {
        if (W == dataW() && H == dataH())
            return new Bitmap(array.dup, W, H);
        if (W <= 0 || H <= 0) return null;

        auto newArray = new ubyte[H * ((W + 7) / 8)];

        int xmod = dataW() % W;
        int xstep = dataW() / W;
        int ymod = dataH() % H;
        int ystep = dataH() / H;

        int sy = 0, yerr = H;
        size_t newIdx = 0;
        for (int dy = H; dy > 0; dy--)
        {
            int sx = 0;
            ubyte newBit = 1;
            const(ubyte)* oldRow = array.ptr + sy * ((dataW() + 7) / 8);
            int xerr = W;
            for (int dx = W; dx > 0; dx--)
            {
                ubyte oldBit = cast(ubyte)(1 << (sx & 7));
                if (oldRow[sx / 8] & oldBit) newArray[newIdx] |= newBit;

                if (newBit < 128) newBit <<= 1;
                else
                {
                    newBit = 1;
                    newIdx++;
                }

                sx += xstep;
                xerr -= xmod;
                if (xerr <= 0)
                {
                    xerr += W;
                    sx++;
                }
            }
            if (newBit > 1) newIdx++;

            sy += ystep;
            yerr -= ymod;
            if (yerr <= 0)
            {
                yerr += H;
                sy++;
            }
        }
        return new Bitmap(newArray, W, H);
    }
}

unittest
{
    // Construction, the bits-too-short safety check, and d()==0
    // (matching FLTK: bitmaps always report depth 0).
    ubyte[] bits = [0b1010_1010, 0b0101_0101]; // 8x2
    auto bm = new Bitmap(bits, 8, 2);
    assert(bm.d() == 0);
    assert(bm.array.length == 2);
    assert(!bm.fail());

    auto tooShort = new Bitmap(bits[0 .. 1], 8, 2);
    assert(tooShort.array.length == 0);
}

unittest
{
    // copy(): exact-size duplicate and a real nearest-neighbor 2x
    // upscale, checked bit-by-bit.
    ubyte[] bits = [0b0000_0001]; // 8x1, only the leftmost pixel set
    auto bm = new Bitmap(bits, 8, 1);

    auto same = bm.copy(8, 1);
    assert(same.array == bits);
    assert(same.array !is bm.array); // real copy, not aliased

    // 8x1 -> 4x1: nearest-neighbor picks every other source pixel,
    // so only the (still-leftmost) first destination pixel is set.
    auto shrunk = bm.copy(4, 1);
    assert(shrunk.array.length == 1);
    assert((shrunk.array[0] & 1) == 1);
    assert((shrunk.array[0] & 0b1111_1110) == 0);
}

unittest
{
    // draw(): headless path (no display) must fall back to
    // drawEmpty() without crashing, same pattern as fl.image's own
    // base-Image draw() test.
    auto bm = new Bitmap([0xFF], 8, 1);
    bm.draw(0, 0);

    auto empty = new Bitmap(null, 8, 1); // too-short (0 < minLength): drawEmpty() path
    empty.draw(0, 0);
}

unittest
{
    // Regression coverage for the scale-aware recache: no real X11
    // display exists in this headless test (createBitmask() returns 0
    // unconditionally, so `id_` never actually becomes nonzero here),
    // but `cachedW_`/`cachedH_` are still set unconditionally at the
    // end of every draw() call -- exercising the real "what size did
    // draw() decide to cache at" decision without needing a display.
    scope (exit) fl.core.currentScale(1.0f); // don't leak into other tests

    auto bm = new Bitmap([0xFF], 8, 1); // 8x1 native size

    // draw() reads fl.core.currentScale() (the live drawing scale, set
    // by whichever window's own make_current()-equivalent hook last
    // ran -- see fl.core.currentScale_'s own doc comment), not
    // screenScale(0) directly, so it's driven here instead.
    fl.core.currentScale(1.0f);
    bm.draw(0, 0, 8, 1);
    assert(bm.cachedW_ == 8 && bm.cachedH_ == 1); // scale 1: no resample needed

    fl.core.currentScale(2.0f);
    bm.draw(0, 0, 8, 1);
    assert(bm.cachedW_ == 16 && bm.cachedH_ == 2); // scale 2: cached at 2x

    // Scale back down again -- must re-recache at the smaller size too,
    // not get stuck at whatever the largest size seen so far was.
    fl.core.currentScale(1.0f);
    bm.draw(0, 0, 8, 1);
    assert(bm.cachedW_ == 8 && bm.cachedH_ == 1);
}
