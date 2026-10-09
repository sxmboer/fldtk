/*
 * Ported from FL/Fl_Image.H + src/Fl_Image.cxx (FLTK 1.5.0): Fl_Image, the base class for image caching,
 * scaling, and drawing, and Fl_RGB_Image, the full-color (1-4 channel)
 * image subclass -- both live in the same FLTK file, so they stay
 * together here too (FLTK's own separate FL/Fl_RGB_Image.H is only
 * a "for compatibility reasons #include this instead" forwarding
 * header, the real class is defined in Fl_Image.H).
 *
 * Milestone 1 of the fl.image port (Image, RGBImage, and -- in
 * fl.bitmap -- Bitmap): the base class plus the two image kinds that
 * don't need external codec libraries and don't need Fl_Pixmap's own
 * color-table decoding first. Fl_Pixmap (Milestone 2) and the XBM/XPM/
 * PNM file readers (Milestone 3) build on this. JPEG/PNG/SVG (real
 * external-library codecs) were deliberately out of scope for this
 * pass -- see CONVENTIONS.md's "Deferred: external-library-backed features"
 * section. JPEG, PNG, and SVG are all done (`fl.
 * jpeg_image`, `fl.png_image`, `fl.svg_image` -- see PORTING.md's own
 * rows for each); no external-codec gap remains for `fl.image` itself.
 *
 * Real, drawn-pixels support: RGBImage.draw() resamples itself to the
 * live screen-scale-driven target size (see draw()'s own doc comment)
 * and blits via fl.draw.drawImageFixed() (Xlib XPutImage-based),
 * radically simplified from FLTK's own multi-visual-depth/colormap/
 * byte-order converter table -- this port already assumes a plain 8-8-8
 * TrueColor visual everywhere else (see fl.draw's fl_color() doc
 * comment), so the image primitive does too. See that function's own
 * doc comment for the full simplification list.
 *
 * Deliberate deviations from FLTK, all documented at their point
 * of use below:
 *  - No generic Image.data()/count() polymorphic pointer-array
 *    accessor. FLTK's Fl_Image::data() exists so code holding only
 *    a base Fl_Image* can still reach a subclass's raw pixel data
 *    without knowing its concrete type; nothing in this port ever does
 *    that (every real consumer already has the concrete subclass type
 *    in hand), so each subclass just exposes its own typed data field
 *    directly (RGBImage.array, Bitmap.array) instead.
 *  - RGBImage.array is a real D slice (const(ubyte)[]), not a raw
 *    pointer + separate alloc_array "should this be freed" flag --
 *    the GC already manages the memory regardless of who allocated it
 *    (a caller-supplied compile-time literal array is just as GC-safe
 *    as one this port allocates itself), so the C-memory-ownership
 *    distinction alloc_array exists to track is moot, same substitution
 *    CONVENTIONS.md documents for Widget.label()'s COPIED_LABEL flag. This
 *    also collapses FLTK's two RGB constructors (a raw-pointer one
 *    with no bounds checking, and a bits_length-checked one) into a
 *    single constructor -- a D slice already carries its own length,
 *    so the bounds check FLTK's second constructor exists for is
 *    just `bits.length >= minLength`, always available, never
 *    something a caller can accidentally skip.
 *  - release() calls uncache() (releases any cached X-server-side
 *    resource right away, matching FLTK's immediate-release
 *    intent) but does not itself destroy the D object -- the GC
 *    reclaims it normally. FLTK's `delete this` has no D
 *    equivalent that isn't its own separate hazard (see CONVENTIONS.md's
 *    GC-finalizer note); nothing in this class's shape needs it either
 *    (an Image holds no references to other GC-managed objects the
 *    way Widget does).
 */
module fl.image;

import fl.enumerations : Color, foregroundColor, gray;
import fl.pixmap : Pixmap, convertPixmap;
import fldraw = fl.draw;
import fl.core; // screenScale() -- circular with fl.core's own use of
// fl.image in a few places, same precedent as fl.pixmap/fl.core
// elsewhere in this port.

class Image
{
    enum errNoImage = -1;
    enum errFileAccess = -2;
    enum errFormat = -3;
    enum errMemoryAccess = -4;

    /// Ported from `Fl_RGB_Scaling` (`FL/Fl_Image.H`) -- which
    /// algorithm `RGBImage.copy(w,h)` (and so `draw()`'s own lazy
    /// resample, see that function's own doc comment) uses when
    /// resizing pixel data. A small closed set, so a real D `enum`
    /// (matching CONVENTIONS.md's established "closed, non-combinable tag
    /// sets become real D enums" convention -- same category as
    /// `Boxtype`/`Labeltype`, not the open bitmask sets that stay
    /// manifest constants), unlike FLTK's own plain C enum whose
    /// members (`FL_RGB_SCALING_NEAREST`/`_BILINEAR`) are used
    /// unqualified.
    enum RGBScaling
    {
        nearest,
        bilinear,
    }

    private static RGBScaling rgbScaling_ = RGBScaling.nearest;

    /// Sets the algorithm used to shrink/grow RGB image data --
    /// process-wide, matching FLTK's own `static` storage. Ported
    /// from `Fl_Image::RGB_scaling(Fl_RGB_Scaling)`. This is the
    /// *explicit*, program-called `copy(w,h)` default (nearest) --
    /// see `scalingAlgorithm()` just below for the separate setting
    /// that governs *automatic* display-scale resampling instead.
    static void rgbScaling(RGBScaling m) { rgbScaling_ = m; }
    /// ditto
    static RGBScaling rgbScaling() { return rgbScaling_; }

    private static RGBScaling scalingAlgorithm_ = RGBScaling.bilinear;

    /// Sets the algorithm `RGBImage.draw()` uses for its own
    /// *automatic* resample to the live `fl.core.currentScale()`-driven target
    /// size -- a separate, independently-defaulted setting from
    /// `rgbScaling()` above. Ported from `Fl_Image::scaling_algorithm(
    /// Fl_RGB_Scaling)`; FLTK's own `Fl_Graphics_Driver::draw_rgb()`
    /// temporarily overrides `RGB_scaling()`'s nearest default with
    /// this (default bilinear) around its one internal `img->copy(w2,
    /// h2)` call, specifically so an image *drawn* at a non-native
    /// size looks smoother than the blockier nearest-neighbor result a
    /// program gets from calling `copy()` itself (e.g. for a fast
    /// thumbnail list) -- `RGBImage.draw()` does the same temporary-
    /// override dance around its own scale-aware `copy()` call.
    static void scalingAlgorithm(RGBScaling m) { scalingAlgorithm_ = m; }
    /// ditto
    static RGBScaling scalingAlgorithm() { return scalingAlgorithm_; }

    private int w_, h_, d_, ld_;
    private int dataW_, dataH_;
    private int count_;

    this(int W, int H, int D)
    {
        w_ = W;
        h_ = H;
        d_ = D;
        ld_ = 0;
        dataW_ = W;
        dataH_ = H;
    }

    /// The current image drawing width/height, in FLTK units. Equal to
    /// dataW()/dataH() unless scale() has been called.
    int w() const { return w_; }
    int h() const { return h_; } /// ditto

    /// The width/height of the raw image data -- fixed at construction,
    /// unlike w()/h() which scale() can change.
    int dataW() const { return dataW_; }
    int dataH() const { return dataH_; } /// ditto

    /// Image depth: 0 for bitmaps, 1 for pixmaps, 1-4 for color images.
    int d() const { return d_; }

    /// Line data size in bytes (row stride) -- 0 means dataW()*d().
    int ld() const { return ld_; }

    /// Sets both w() and dataW() together -- protected, matching
    /// FLTK's own `void w(int W) {w_ = W; data_w_ = W;}`. Not used
    /// by scale() (see that function's own doc comment for why it sets
    /// w_/h_ directly instead).
    protected void w(int W)
    {
        w_ = W;
        dataW_ = W;
    }
    protected void h(int H) /// ditto
    {
        h_ = H;
        dataH_ = H;
    }
    protected void d(int D) { d_ = D; }
    protected void ld(int LD) { ld_ = LD; }

    /**
     * Sets whether this image currently has real backing data (matches
     * FLTK's `count_`, the number of data pointers an image has --
     * 0 or 1 for every subclass this port has so far, never generally
     * queryable the way FLTK's `count()`/`data()` are, see the
     * module's own top comment for why). Only `fail()` below actually
     * needs this: for a subclass whose valid `d()` is always `<= 0` by
     * design (`Bitmap`, `d() == 0` always, matching FLTK exactly),
     * `d() <= 0` alone can't distinguish "valid bitmap" from "failed
     * load" -- `hasData(true)` on success / left `false` (the default)
     * on failure is what FLTK's own `count_` accomplishes for
     * exactly this case.
     */
    protected void hasData(bool has) { count_ = has ? 1 : 0; }

    /// Non-zero if there is currently no usable image (a failed load,
    /// or a default-constructed placeholder). Ported from `fail()`,
    /// including its exact condition shape (`d_ <= 0 && count_ == 0`)
    /// -- see `hasData()`'s own doc comment for why `count_` still
    /// matters here even though the rest of FLTK's `count_`/
    /// `data()` mechanism isn't ported.
    int fail() const
    {
        if (w_ <= 0 || h_ <= 0 || (d_ <= 0 && count_ == 0))
        {
            if (ld_ == 0) return errNoImage;
            return ld_;
        }
        return 0;
    }

    /// Releases any cached server-side resource now (see the module's
    /// own top comment for why this doesn't also destroy the D object
    /// the way FLTK's `delete this` does).
    void release()
    {
        uncache();
    }

    /// If the image has been cached for display, releases that cache
    /// -- lets the underlying data be changed and redrawn without
    /// recreating the image object. Base implementation is a no-op
    /// (nothing to release at this level); real subclasses override.
    void uncache() { }

    /// Draws a box with an X in it -- used for any image that lacks
    /// real data (the base class's own draw(), or a subclass's draw()
    /// on failed/empty data). Ported from `draw_empty()`.
    protected void drawEmpty(int X, int Y)
    {
        if (w() > 0 && h() > 0)
        {
            fldraw.fl_color(foregroundColor);
            fldraw.fl_rect(X, Y, w(), h());
            fldraw.fl_line(X, Y, X + w() - 1, Y + h() - 1);
            fldraw.fl_line(X, Y + h() - 1, X + w() - 1, Y);
        }
    }

    /// Draws the image to the current drawing surface with a bounding
    /// box (X,Y,W,H), with the image's own origin offset by (cx,cy).
    /// The base class has no real image data, so this always draws the
    /// "box with an X" placeholder -- real subclasses override.
    void draw(int X, int Y, int W, int H, int cx = 0, int cy = 0)
    {
        drawEmpty(X, Y);
    }

    /// ditto, at the image's own natural size.
    final void draw(int X, int Y)
    {
        draw(X, Y, w(), h(), 0, 0);
    }

    /// Creates a resized copy of the image (W == dataW() == the new
    /// w()/dataW(), same for H). Base implementation returns an empty
    /// Image of the requested size (matching FLTK: `new
    /// Fl_Image(W, H, d())`) -- real subclasses override with their
    /// own real pixel-resampling copy.
    Image copy(int W, int H) const
    {
        return new Image(W, H, d());
    }

    /// ditto, at the image's own current size.
    final Image copy() const
    {
        return copy(w(), h());
    }

    /// Averages the image's colors with c (i = 1.0 means no blend, 0.0
    /// means a constant-color image). Base implementation is a no-op
    /// (nothing to average at this level); real subclasses override.
    void colorAverage(Color c, float i) { }

    /// Calls colorAverage(gray, 0.33) to produce a grayed-out
    /// "disabled" look. Ported from `inactive()`.
    final void inactive()
    {
        colorAverage(gray, 0.33f);
    }

    /// Converts the image to grayscale (preserving any alpha channel).
    /// Base implementation is a no-op; real subclasses override.
    void desaturate() { }

    /**
     * Sets the drawing size of the image (what w()/h() return) without
     * changing dataW()/dataH(). `proportional` keeps w()/h() in the
     * same aspect ratio as dataW()/dataH(); `canExpand` allows w()/h()
     * to grow past dataW()/dataH() (otherwise capped at the data
     * size). Ported line-for-line from `Fl_Image::scale()`
     * (`src/Fl_Image.cxx`) -- pure arithmetic, no drawing/data-copying
     * involved (the actual resampling, if any, happens lazily at
     * draw() time). Deliberately sets w_/h_ directly rather than going
     * through the protected w(int)/h(int) setters above, matching
     * FLTK's own distinction: those setters also update
     * dataW()/dataH(), which scale() must never touch.
     */
    void scale(int width, int height, bool proportional = true, bool canExpand = false)
    {
        if ((width <= dataW() && height <= dataH()) || canExpand)
        {
            w_ = width;
            h_ = height;
        }
        if (fail()) return;
        if (!proportional && canExpand) return;
        if (!proportional && width <= dataW() && height <= dataH()) return;

        float fw = dataW() / cast(float) width;
        float fh = dataH() / cast(float) height;
        if (proportional)
        {
            if (fh > fw) fw = fh;
            else fh = fw;
        }
        if (!canExpand)
        {
            if (fw < 1) fw = 1;
            if (fh < 1) fh = 1;
        }
        w_ = cast(int)((dataW() / fw) + 0.5);
        h_ = cast(int)((dataH() / fh) + 0.5);
    }
}

/**
 * The full-color image class: 1-4 channels of 8-bit-per-sample color
 * data (1 = grayscale, 2 = grayscale + alpha, 3 = RGB, 4 = RGBA).
 * Ported from Fl_RGB_Image (`FL/Fl_Image.H` + `src/Fl_Image.cxx`) --
 * see the module's own top comment for the array/alloc_array and
 * constructor-collapsing deviations.
 */
class RGBImage : Image
{
    /// Makes sure the pixel array is present; a no-op except for lazily
    /// rasterized subclasses (SvgImage).
    void normalize() {}

    /// The raw pixel data: dataH() rows of dataW()*d() bytes each
    /// (or ld() bytes each if ld() is set for row padding).
    const(ubyte)[] array;

    /**
     * Creates an image from bits (dataW()*dataH()*D bytes, or more if
     * LD pads each row). If bits is too short for the claimed
     * dimensions, the image is left empty (array.length == 0) --
     * matching FLTK's own bits_length-checked constructor exactly,
     * just unconditionally (see the module's own top comment for why
     * the unchecked raw-pointer constructor FLTK also has isn't
     * ported). **Check `array.length == 0`, not `fail()`, to detect
     * this** -- `fail()` doesn't actually catch this specific case, a
     * real, faithfully-reproduced FLTK quirk (`ld()` is set to
     * `errMemoryAccess`, but `fail()`'s own condition never consults
     * `ld()` for a normal positive `D`; see `FLTK_ISSUES.md`).
     */
    this(const(ubyte)[] bits, int W, int H, int D = 3, int LD = 0)
    {
        super(W, H, D);
        int effD = D == 0 ? 3 : D;
        int minLength = LD ? LD * (H - 1) + W * effD : W * effD * H;
        if (H > 0 && W > 0 && bits.length >= minLength)
        {
            array = bits;
            ld(LD);
            hasData(true);
        }
        else
        {
            array = null;
            ld(errMemoryAccess);
        }
    }

    /**
     * Creates an RGBA image from pxm's pixel data, decoding via
     * fl.pixmap's convertPixmap() -- the same routine Pixmap.draw()
     * itself uses. Pixels the XPM color table maps to "None"
     * (transparent) become bg, fully transparent. A real converting
     * *constructor*, not a cast operator (see this constructor's own
     * addition note below for why) -- ported directly from FLTK's
     * own `Fl_RGB_Image(const Fl_Pixmap *pxm, Fl_Color bg = FL_GRAY)`
     * (`src/Fl_Image.cxx`), which is itself a constructor, not a
     * conversion operator. D does support `opCast(T)()` for
     * cast-style conversions, but that idiom fits a cheap, "free"
     * reinterpretation (numeric conversions, upcasts) -- this does
     * real work (allocates a new pixel buffer and decodes the whole
     * color table into it), which a constructor communicates more
     * honestly than a `cast()` expression would, and matches FLTK
     * exactly besides.
     */
    this(const(Pixmap) pxm, Color bg = gray)
    {
        int w = pxm !is null ? pxm.dataW() : 0;
        int h = pxm !is null ? pxm.dataH() : 0;
        super(w, h, 4);
        if (pxm !is null && w > 0 && h > 0)
        {
            auto arr = new ubyte[w * h * 4];
            convertPixmap(pxm.xpmData, arr, bg);
            array = arr;
            hasData(true);
        }
        if (pxm !is null) scale(pxm.w(), pxm.h(), false, true);
    }

    alias copy = Image.copy; // re-expose the 0-arg overload the override below hides
    alias draw = Image.draw; // re-expose the 2-arg overload the override below hides

    /// A real resampled copy at the current live `fl.core.currentScale()`-driven
    /// *device-pixel* target size, rebuilt lazily whenever that target
    /// changes -- see `draw()`'s own use of this. Mirrors `fl.pixmap.
    /// Pixmap.scaledCache_`/`fl.bitmap.Bitmap.cachedW_`/`cachedH_`'s
    /// identical precedent exactly (see `draw()`'s own doc comment for
    /// the bug this fixes).
    private RGBImage scaledCache_;

    override void uncache()
    {
        // No offscreen-Pixmap/X11 cache exists in this port (see
        // fl.draw.drawImage()'s own doc comment) -- every draw()
        // re-blits directly, so there is no server-side resource to
        // release here. `scaledCache_` *is* a real cache, though (see
        // draw()'s own doc comment) -- dropped here so a caller that
        // mutates `array` in place (there is no such mutator today, but
        // colorAverage()-style FLTK siblings exist for other Image
        // subclasses) can't leave a stale resampled copy behind, the
        // same class of bug `fl.pixmap.Pixmap.uncache()` was fixed to
        // avoid alongside this same change.
        scaledCache_ = null;
    }

    /**
     * Ported from `Fl_Graphics_Driver::draw_rgb()`. Resamples *once*,
     * from this image's own pristine native `array`, to the *device-
     * pixel* target size (`w()`/`h()` -- the fixed logical size -- times
     * the live `fl.core.currentScale()`), then blits that result 1:1
     * via `fl.draw.drawImageFixed()`.
     *
     * Resampling straight to `w()`/`h()` whenever those differ from
     * `dataW()`/`dataH()` (i.e. only when an explicit `Image.scale()`
     * call had been made) would ignore the live screen scale, and hand
     * that already-downscaled buffer to plain `fl.draw.drawImage()` --
     * which resamples *again* on top, to fit the actual device-pixel
     * box.
     * Two lossy nearest-neighbor passes compound (downscale-then-
     * upscale), producing a visibly blockier result than FLTK's
     * single exact/near-exact resample from full native resolution.
     * This is what made `fluid`'s widget-panel icons (32x32 native XPMs -- see `fl.pixmap.
     * Pixmap.draw()`'s identical fix and its own doc comment for the
     * full mechanism -- 32x32-native RGB images hit the exact same
     * shape) turned pixelated when the display was scaled to 200%,
     * while real FLTK's stayed sharp because its own `cache_size()`
     * computes the *same* target size FLTK's `Fl_Pixmap`/`Fl_RGB_
     * Image::copy()` then hits its own exact-size fast path against --
     * zero resampling at all, not just one pass instead of two.
     *
     * The resample step itself also forces bilinear (via a
     * temporary `rgbScaling()` override, mirroring FLTK's own
     * `draw_rgb()` `scaling_algorithm()` trick exactly -- see
     * `scalingAlgorithm()`'s own doc comment), rather than whatever
     * `rgbScaling()`'s own default (nearest) happens to be -- that
     * default is for an explicit, program-called `copy()` only.
     */
    override void draw(int X, int Y, int W, int H, int cx = 0, int cy = 0)
    {
        if (array.length == 0 || d() == 0)
        {
            drawEmpty(X, Y);
            return;
        }

        float s = fl.core.currentScale();
        int wantW = cast(int)(w() * s + 0.5f);
        int wantH = cast(int)(h() * s + 0.5f);
        if (wantW < 1) wantW = 1;
        if (wantH < 1) wantH = 1;

        const(ubyte)[] drawArray = array;
        int drawW = dataW(), drawH = dataH();
        int drawLd = ld() ? ld() : dataW() * d();
        if (wantW != dataW() || wantH != dataH())
        {
            if (scaledCache_ is null || scaledCache_.dataW() != wantW || scaledCache_.dataH() != wantH)
            {
                auto keep = rgbScaling();
                rgbScaling(scalingAlgorithm());
                scaledCache_ = copy(wantW, wantH);
                scaledCache_.normalize(); // a copied SvgImage has no pixels until rasterized
                rgbScaling(keep);
            }
            if (scaledCache_ !is null && scaledCache_.array.length != 0)
            {
                drawArray = scaledCache_.array;
                drawW = scaledCache_.dataW();
                drawH = scaledCache_.dataH();
                drawLd = drawW * d();
            }
        }

        // (X,Y,W,H,cx,cy) select a sub-rectangle of the image's own
        // logical w()xh() box, matching FLTK's own cropping
        // semantics (`Fl_Graphics_Driver::start_image()` clamps against
        // `img->w()`/`img->h()`, not the native/cached pixel size) --
        // mapped into the (possibly-resampled) buffer's own pixel
        // coordinates afterward.
        int px = cx < 0 ? 0 : cx;
        int py = cy < 0 ? 0 : cy;
        int pw = W;
        int ph = H;
        if (px + pw > w()) pw = w() - px;
        if (py + ph > h()) ph = h() - py;
        if (pw <= 0 || ph <= 0) return;

        int bufPx = cast(int)(px * s + 0.5f);
        int bufPy = cast(int)(py * s + 0.5f);
        int bufPw = cast(int)(pw * s + 0.5f);
        int bufPh = cast(int)(ph * s + 0.5f);
        if (bufPx + bufPw > drawW) bufPw = drawW - bufPx;
        if (bufPy + bufPh > drawH) bufPh = drawH - bufPy;
        if (bufPw <= 0 || bufPh <= 0) return;

        const(ubyte)* p = drawArray.ptr + bufPy * drawLd + bufPx * d();
        fldraw.drawImageFixed(p, bufPw, bufPh, drawLd, d(), X - cx + px, Y - cy + py);
    }

    /**
     * Ported from `Fl_RGB_Image::copy(int, int)`. Dispatches on
     * `Image.rgbScaling()`: nearest-neighbor is a single direct pass
     * (`copyNearestNeighbor()`); bilinear first halves the image down
     * (`copyScaleDown2h()`/`copyScaleDown2v()`) until it's within 2x
     * of the target size in both dimensions, then does one final
     * `copyBilinear()` pass -- matching FLTK's own two-stage
     * approach exactly (a single bilinear pass on a >2x downscale
     * would alias/moire, per FLTK's own source comment; the
     * coarse box-filter prepass avoids that at a fraction of the
     * cost of, say, always resampling at full precision).
     */
    override RGBImage copy(int W, int H) const
    {
        if ((W == dataW() && H == dataH()) || array.length == 0)
            return copyOptimize(W, H);
        if (W <= 0 || H <= 0) return null;
        if (rgbScaling() == RGBScaling.nearest)
            return copyNearestNeighbor(W, H);

        import std.typecons : Rebindable;

        Rebindable!(const RGBImage) img = this;
        while (img.dataW() >= 2 * W || img.dataH() >= 2 * H)
        {
            if (img.dataW() >= 2 * W)
            {
                auto scaled = img.copyScaleDown2h();
                if (scaled is null) break;
                img = scaled;
            }
            if (img.dataH() >= 2 * H)
            {
                auto scaled = img.copyScaleDown2v();
                if (scaled is null) break;
                img = scaled;
            }
        }
        if (img.dataW() == W && img.dataH() == H)
            // img is never `this` here: the exact-size case for the
            // original image was already handled at the top of this
            // function, before rgbScaling()/this loop are even
            // reached -- matches FLTK's own defensive "should not
            // happen" branch (`img == this`), which is dead code there
            // for the identical reason.
            return cast(RGBImage) img.get();
        return img.copyBilinear(W, H);
    }

    private RGBImage copyOptimize(int W, int H) const
    {
        if (array.length == 0) return new RGBImage(array, W, H, d(), ld());
        auto newArray = new ubyte[W * H * d()];
        int srcLd = ld() ? ld() : dataW() * d();
        if (ld() && ld() != W * d())
        {
            int rowBytes = W * d();
            for (int y = 0; y < H; y++)
                newArray[y * rowBytes .. (y + 1) * rowBytes] =
                    array[y * srcLd .. y * srcLd + rowBytes];
        }
        else
        {
            newArray[] = array[0 .. newArray.length];
        }
        return new RGBImage(newArray, W, H, d());
    }

    /// Ported from `Fl_RGB_Image::copy_nearest_neighbor_()`.
    private RGBImage copyNearestNeighbor(int W, int H) const
    {
        auto newArray = new ubyte[W * H * d()];
        int lineD = ld() ? ld() : dataW() * d();

        int xmod = dataW() % W;
        int xstep = (dataW() / W) * d();
        int ymod = dataH() % H;
        int ystep = dataH() / H;

        int sy = 0, yerr = H;
        size_t newIdx = 0;
        for (int dy = H; dy > 0; dy--)
        {
            const(ubyte)* oldPtr = array.ptr + sy * lineD;
            int xerr = W;
            for (int dx = W; dx > 0; dx--)
            {
                for (int c = 0; c < d(); c++) newArray[newIdx++] = oldPtr[c];
                oldPtr += xstep;
                xerr -= xmod;
                if (xerr <= 0)
                {
                    xerr += W;
                    oldPtr += d();
                }
            }
            sy += ystep;
            yerr -= ymod;
            if (yerr <= 0)
            {
                yerr += H;
                sy++;
            }
        }
        return new RGBImage(newArray, W, H, d());
    }

    /**
     * Ported from `Fl_RGB_Image::copy_scale_down_2h_()`/
     * `copy_scale_down_2v_()` -- box-filter halving passes
     * `copy(int,int)`'s bilinear path uses to coarsely pre-shrink a
     * >2x downscale before the one precise `copyBilinear()` pass (see
     * that function's own doc comment for why). Collapsed into a
     * single `d()`-channel loop rather than FLTK's 4 near-
     * identical hand-unrolled `switch(D)` cases (1/2/3/4-channel) --
     * same output, no duplicated bodies to keep in sync; a cleaner D
     * alternative CONVENTIONS.md's porting conventions ask to prefer when
     * one doesn't change behavior.
     */
    private RGBImage copyScaleDown2h() const
    {
        int W = dataW() / 2;
        int H = dataH();
        int D = d();
        int lineD = ld() ? ld() : dataW() * D;
        if (W == 0 || H == 0 || D == 0) return null;

        auto newArray = new ubyte[W * H * D];
        size_t dst = 0;
        foreach (y; 0 .. H)
        {
            size_t src = cast(size_t) y * lineD;
            foreach (x; 0 .. W)
            {
                foreach (c; 0 .. D)
                    newArray[dst + c] = cast(ubyte)((cast(uint) array[src + c] + array[src + D + c]) >> 1);
                dst += D;
                src += 2 * D;
            }
        }
        return new RGBImage(newArray, W, H, D);
    }

    /// ditto -- the vertical (row-pair-averaging) counterpart.
    private RGBImage copyScaleDown2v() const
    {
        int W = dataW();
        int H = dataH() / 2;
        int D = d();
        int lineD = ld() ? ld() : dataW() * D;
        if (W == 0 || H == 0 || D == 0) return null;

        auto newArray = new ubyte[W * H * D];
        size_t dst = 0;
        foreach (y; 0 .. H)
        {
            size_t s0 = cast(size_t) 2 * y * lineD;
            size_t s1 = s0 + lineD;
            foreach (x; 0 .. W * D)
                newArray[dst++] = cast(ubyte)((cast(uint) array[s0 + x] + array[s1 + x]) >> 1);
        }
        return new RGBImage(newArray, W, H, D);
    }

    /**
     * Ported from `Fl_RGB_Image::copy_bilinear_(int, int)` -- a real
     * bilinear resample (4-tap interpolation between the 2x2 nearest
     * source pixels, pixel-center mapping, 8-bit fixed-point weights
     * with precomputed per-row/column offsets), used by `copy(int,int)`
     * for the final pass once `copyScaleDown2h()`/`copyScaleDown2v()`
     * have brought the source within 2x of the target in both
     * dimensions. Deliberately differs from FLTK for `d() == 4`: color
     * channels are premultiplied by alpha before blending and
     * unpremultiplied after, since interpolating straight alpha would
     * bleed a fully-transparent neighbor's color into the result.
     */
    private RGBImage copyBilinear(int W, int H) const
    {
        immutable int D = d();
        immutable int SW = dataW();
        immutable int SH = dataH();
        immutable size_t SLD = ld() ? ld() : cast(size_t) SW * D;
        auto newArray = new ubyte[cast(size_t) W * H * D];

        // Per destination column/row: the two source samples and the
        // weight of the second one (0..256), mapping pixel centers so it
        // works for both scaling up and down.
        static void mapAxis(int dstN, int srcN, int unit, size_t[] off0, size_t[] off1, uint[] weight1)
        {
            foreach (i; 0 .. dstN)
            {
                float sx = ((i + 0.5f) * srcN) / cast(float) dstN - 0.5f;
                int x0 = cast(int) sx;
                if (sx < 0.0f && cast(float) x0 != sx) x0--; // floor for negatives
                float fx = sx - x0;
                if (x0 < 0) { x0 = 0; fx = 0.0f; }
                else if (x0 >= srcN - 1) { x0 = srcN - 1; fx = 0.0f; }
                int x1 = x0 < srcN - 1 ? x0 + 1 : x0;
                int wgt = cast(int)(fx * 256.0f + 0.5f);
                if (wgt < 0) wgt = 0; else if (wgt > 256) wgt = 256;
                off0[i] = cast(size_t) x0 * unit;
                off1[i] = cast(size_t) x1 * unit;
                weight1[i] = wgt;
            }
        }
        auto x0Off = new size_t[W], x1Off = new size_t[W];
        auto wx1 = new uint[W];
        auto y0Off = new size_t[H], y1Off = new size_t[H];
        auto wy1 = new uint[H];
        mapAxis(W, SW, D, x0Off, x1Off, wx1);
        mapAxis(H, SH, cast(int) SLD, y0Off, y1Off, wy1);

        foreach (y; 0 .. H)
        {
            auto row0 = array[y0Off[y] .. $];
            auto row1 = array[y1Off[y] .. $];
            immutable uint wy = wy1[y];
            immutable uint wy0 = 256 - wy;
            size_t dst = cast(size_t) y * W * D;

            foreach (x; 0 .. W)
            {
                immutable uint wx = wx1[x];
                immutable uint wx0 = 256 - wx;
                auto p00 = row0[x0Off[x] .. $];
                auto p10 = row0[x1Off[x] .. $];
                auto p01 = row1[x0Off[x] .. $];
                auto p11 = row1[x1Off[x] .. $];

                // Blend alpha with the color channels premultiplied, so a
                // transparent neighbor's color doesn't bleed into the result.
                uint[4] v;
                foreach (c; 0 .. D)
                {
                    uint s00 = p00[c], s10 = p10[c], s01 = p01[c], s11 = p11[c];
                    if (D == 4 && c < 3)
                    {
                        s00 = s00 * p00[3] / 255; s10 = s10 * p10[3] / 255;
                        s01 = s01 * p01[3] / 255; s11 = s11 * p11[3] / 255;
                    }
                    uint top = s00 * wx0 + s10 * wx;
                    uint bot = s01 * wx0 + s11 * wx;
                    v[c] = (top * wy0 + bot * wy + 32768) >> 16;
                }
                if (D == 4 && v[3] != 0)
                    foreach (c; 0 .. 3)
                    {
                        uint u = v[c] * 255 / v[3];
                        v[c] = u > 255 ? 255 : u;
                    }
                foreach (c; 0 .. D) newArray[dst + c] = cast(ubyte) v[c];
                dst += D;
            }
        }
        return new RGBImage(newArray, W, H, D);
    }

    override void colorAverage(Color c, float i)
    {
        if (w() == 0 || h() == 0 || d() == 0 || array.length == 0) return;
        uncache();

        ubyte r, g, b;
        fldraw.colorToRgb8(c, r, g, b);
        if (i < 0.0f) i = 0.0f;
        else if (i > 1.0f) i = 1.0f;

        uint ia = cast(uint)(256 * i);
        uint ir = r * (256 - ia);
        uint ig = g * (256 - ia);
        uint ib = b * (256 - ia);

        auto newArray = new ubyte[dataH() * dataW() * d()];
        int lineI = ld() ? ld() - (dataW() * d()) : 0;
        size_t oldIdx = 0, newIdx = 0;

        if (d() < 3)
        {
            uint igray = (r * 31 + g * 61 + b * 8) / 100 * (256 - ia);
            for (int y = 0; y < dataH(); y++)
            {
                for (int x = 0; x < dataW(); x++)
                {
                    newArray[newIdx++] = cast(ubyte)((array[oldIdx++] * ia + igray) >> 8);
                    if (d() > 1) newArray[newIdx++] = array[oldIdx++];
                }
                oldIdx += lineI;
            }
        }
        else
        {
            for (int y = 0; y < dataH(); y++)
            {
                for (int x = 0; x < dataW(); x++)
                {
                    newArray[newIdx++] = cast(ubyte)((array[oldIdx++] * ia + ir) >> 8);
                    newArray[newIdx++] = cast(ubyte)((array[oldIdx++] * ia + ig) >> 8);
                    newArray[newIdx++] = cast(ubyte)((array[oldIdx++] * ia + ib) >> 8);
                    if (d() > 3) newArray[newIdx++] = array[oldIdx++];
                }
                oldIdx += lineI;
            }
        }
        array = newArray;
        ld(0);
    }

    override void desaturate()
    {
        if (w() == 0 || h() == 0 || d() == 0 || array.length == 0) return;
        if (d() < 3) return;
        uncache();

        int newD = d() - 2;
        auto newArray = new ubyte[dataH() * dataW() * newD];
        int lineI = ld() ? ld() - (dataW() * d()) : 0;
        size_t oldIdx = 0, newIdx = 0;

        for (int y = 0; y < dataH(); y++)
        {
            for (int x = 0; x < dataW(); x++)
            {
                newArray[newIdx++] = cast(ubyte)((31 * array[oldIdx] + 61 * array[oldIdx + 1]
                        + 8 * array[oldIdx + 2]) / 100);
                if (d() > 3) newArray[newIdx++] = array[oldIdx + 3];
                oldIdx += d();
            }
            oldIdx += lineI;
        }
        array = newArray;
        ld(0);
        d(newD);
    }
}

unittest
{
    // Base Image: construction, fail(), scale(), copy(), draw_empty()
    // (headless: fl_rect()/fl_line() early-return with no display, but
    // must not crash).
    auto img = new Image(10, 20, 3);
    assert(img.w() == 10 && img.h() == 20 && img.dataW() == 10 && img.dataH() == 20);
    assert(img.d() == 3);
    assert(img.fail() == 0);

    auto empty = new Image(0, 0, 0);
    assert(empty.fail() == Image.errNoImage);

    img.draw(0, 0); // draw_empty() path -- must not crash headlessly

    auto c = img.copy(5, 5);
    assert(c.w() == 5 && c.h() == 5 && c.d() == 3);
}

unittest
{
    // Image.scale(): matches FLTK's own two worked doc-comment
    // examples (see fl.window's defaultSizeRange() test for the same
    // "confirm against FLTK's own examples" pattern).
    auto img = new Image(400, 400, 3);
    img.scale(100, 100); // proportional, no expand: same aspect, capped
    assert(img.w() == 100 && img.h() == 100);
    assert(img.dataW() == 400 && img.dataH() == 400); // data size unaffected

    auto img2 = new Image(200, 100, 3);
    img2.scale(50, 50); // proportional: keeps 2:1 aspect
    assert(img2.w() == 50 && img2.h() == 25);
}

unittest
{
    // RGBImage: construction, the bits-too-short safety check,
    // fail(), and a real 3-channel array round trip.
    ubyte[] bits = new ubyte[4 * 4 * 3];
    bits[] = 128;
    auto img = new RGBImage(bits, 4, 4, 3);
    assert(!img.fail());
    assert(img.array.length == 4 * 4 * 3);
    assert(img.d() == 3);

    // fail() itself doesn't actually catch this case -- a real,
    // faithfully-reproduced FLTK quirk (Fl_Image::fail()'s own
    // condition never consults ld_ when d_ is a normal positive depth,
    // see FLTK_ISSUES.md). array.length == 0 is the real signal.
    auto tooShort = new RGBImage(bits[0 .. 4], 4, 4, 3);
    assert(tooShort.fail() == 0);
    assert(tooShort.array.length == 0);
}

unittest
{
    // RGBImage.copy(): exact-size optimize path and a real
    // nearest-neighbor downscale, checked against hand-computed pixels.
    ubyte[] bits = [
        255, 0, 0, /**/ 0, 255, 0, // row 0: red, green
        0, 0, 255, /**/ 255, 255, 0, // row 1: blue, yellow
    ];
    auto img = new RGBImage(bits, 2, 2, 3);

    auto same = img.copy(2, 2);
    assert(same.array == bits);

    auto shrunk = img.copy(1, 1);
    assert(shrunk.array.length == 3);
    // Nearest-neighbor of a 2x2 down to 1x1 picks the top-left source
    // pixel (red), matching the Bresenham step math ported verbatim.
    assert(shrunk.array == [255, 0, 0]);
}

unittest
{
    // RGBImage.colorAverage()/desaturate(): pure data manipulation, no
    // display needed.
    import fl.enumerations : black;

    ubyte[] bits = [200, 100, 50, 10, 20, 30];
    auto img = new RGBImage(bits.dup, 2, 1, 3);

    img.colorAverage(black, 1.0f); // i=1.0: no blend at all
    assert(img.array == [200, 100, 50, 10, 20, 30]);

    auto img2 = new RGBImage(bits.dup, 2, 1, 3);
    img2.colorAverage(black, 0.0f); // i=0.0: fully replaced by black
    assert(img2.array == [0, 0, 0, 0, 0, 0]);

    auto img3 = new RGBImage(bits.dup, 2, 1, 3);
    img3.desaturate();
    assert(img3.d() == 1); // RGB (3) desaturates to plain gray (3-2=1), no alpha to preserve
    // 31*200+61*100+8*50 = 6200+6100+400 = 12700 / 100 = 127
    assert(img3.array[0] == 127);
    // second source pixel: 31*10+61*20+8*30 = 310+1220+240 = 1770 / 100 = 17
    assert(img3.array[1] == 17);
}

unittest
{
    // RGBImage(Pixmap, bg): the converting constructor ported from
    // Fl_RGB_Image(const Fl_Pixmap*, Fl_Color) -- confirms the opaque
    // pixel decodes to real RGBA bytes and the transparent ("None")
    // pixel becomes bg with alpha 0, matching FLTK's own documented
    // behavior exactly ("the transparent area... is assigned the bg
    // color with full transparency").
    import fl.pixmap : Pixmap;
    import fl.enumerations : red;

    string[] xpm = [
        "2 1 2 1",
        "R c #FF0000",
        ". c None",
        "R.",
    ];
    auto pm = new Pixmap(xpm);
    auto rgb = new RGBImage(pm, red);

    assert(rgb.d() == 4);
    assert(rgb.dataW() == 2 && rgb.dataH() == 1);
    assert(rgb.array[0 .. 4] == [255, 0, 0, 255]); // opaque red
    assert(rgb.array[4 .. 7] == [255, 0, 0]); // bg (red) substituted for "None"
    assert(rgb.array[7] == 0); // fully transparent

    // null pxm: an empty, zero-sized image, not a crash.
    auto empty = new RGBImage(cast(const(Pixmap)) null);
    assert(empty.w() == 0 && empty.h() == 0);
}
