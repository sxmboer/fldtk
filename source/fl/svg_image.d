/*
 * Ported from FL/Fl_SVG_Image.H + src/Fl_SVG_Image.cxx (FLTK 1.5.0): Fl_SVG_Image, an Fl_RGB_Image subclass that
 * renders an SVG document (`fl.nanosvg`'s parser + `fl.nanosvg_rast`'s
 * rasterizer -- see those two modules' own top comments for why porting
 * nanosvg itself, rather than a "which external library" decision, was
 * the right call here) into a real RGBA pixel buffer.
 *
 * Deliberate simplifications vs. FLTK:
 *  - FLTK wraps the parsed `NSVGimage*` in a manually-refcounted
 *    `counted_NSVGimage` (`ref_count`, freed via `nsvgDelete()` when it
 *    hits zero) purely so a `copy()`'d `Fl_SVG_Image` can share the same
 *    parsed document without a second parse. `fl.nanosvg.NsvgImage` is a
 *    plain GC-managed class -- two `SvgImage` instances can just hold the
 *    same reference directly; the GC reclaims it once nothing points to
 *    it anymore, no manual ref-count/`nsvgDelete()` bookkeeping needed
 *    (same substitution `fl.gif_image`'s own note makes for its GIF
 *    frame data).
 *  - The rasterizer (`fl.nanosvg_rast.NsvgRasterizer`) is a single
 *    module-level instance reused across every `SvgImage.rasterize_()`
 *    call, matching FLTK's own `static NSVGrasterizer* rasterizer`
 *    inside `rasterize_()` -- both assume the single-threaded UI-thread-
 *    does-all-rendering model this whole port already assumes elsewhere
 *    (fl.core's event-state globals are the same shape: plain module-
 *    level state, not `__gshared`, since only the UI thread touches it).
 *  - **`.svgz` (gzip-compressed SVG) is supported now (2026-08-18)**,
 *    via `std.zlib.UnCompress(HeaderFormat.gzip)` -- Phobos's own zlib
 *    binding, already linked (`dub.sdl`'s `"z"` `libs` entry) once
 *    `fl.png_image` started needing it for real PNG decode/encode.
 *    FLTK's own gate here is `HAVE_LIBZ`; this port's equivalent
 *    gate (CONVENTIONS.md's "Deferred: external-library-backed features"
 *    zlib-or-not question) was resolved the same day PNG landed, so
 *    this was just a matter of wiring it up. Ported from FLTK's own
 *    `svg_inflate()` (`src/Fl_SVG_Image.cxx`) in spirit, not letter --
 *    that function hand-rolls a chunked `z_stream`/`inflate()` loop
 *    purely because raw zlib's C API has no growable-output concept;
 *    `std.zlib.UnCompress` already handles exactly that internally, so
 *    there's nothing to reimplement, just call it. A gzip-magic-byte
 *    input that fails to decompress (corrupt/truncated, or genuinely
 *    not gzip despite the matching first two bytes) fails gracefully
 *    (`ld() == errFormat`) exactly like malformed plain SVG text does,
 *    not a crash/exception escaping the constructor.
 *  - `svgz`/file-reading uses `std.file.read()` instead of transliterating
 *    FLTK's manual `fl_fopen()`/`fseek()`/`fread()` dance -- no
 *    functional difference, D's stdlib already does this safely.
 */
module fl.svg_image;

import fl.image : Image, RGBImage;
import fl.enumerations : Color, black;
import fl.nanosvg : NsvgImage, nsvgParse;
import fl.nanosvg_rast : NsvgRasterizer;
import std.file : exists, read;

private NsvgRasterizer sharedRasterizer;

/// Ported from `Fl_SVG_Image`.
final class SvgImage : RGBImage
{
    private NsvgImage svgImage_;
    private bool proportional_ = true;
    private bool toDesaturate_;
    private Color averageColor_ = black;
    private float averageWeight_ = 1;
    private bool rasterized_;
    private int rasterW_, rasterH_;

    /// Loads an SVG image from a `.svg` or gzip-compressed `.svgz` file
    /// (detected by content, not filename extension, matching FLTK).
    this(string filename)
    {
        super(null, 0, 0, 4, 0);
        init_(null, cast(const(ubyte)[]) null, filename);
    }

    /// Loads an SVG image from in-memory text. FLTK registers a
    /// non-null `sharedname` with `Fl_Shared_Image` (`new Fl_Shared_Image
    /// (sharedname, this); si->add();`) so a later `Fl_Shared_Image::get
    /// (sharedname)` finds this same instance. `fl.shared_image.SharedImage`
    /// is a real, done port (not a missing subsystem) but its name-
    /// registration constructor/`add()` are module-private -- deliberately
    /// not exposed to other modules yet, since nothing needed cross-module
    /// registration before this. Wiring `sharedname` through would need a
    /// small `package(fl)`-visibility addition there; not done in this
    /// pass, so `sharedname` is accepted for API parity but currently
    /// unused beyond being a non-null/null check FLTK itself never
    /// actually relies on for parsing.
    this(string sharedname, string svgData)
    {
        super(null, 0, 0, 4, 0);
        init_(sharedname, cast(const(ubyte)[]) svgData, null);
    }

    /// Loads an SVG image from in-memory bytes -- either UTF-8 SVG text
    /// or gzip-compressed `.svgz` bytes (detected via the gzip magic
    /// number and decompressed automatically -- see this module's own
    /// top comment).
    this(string name, const(ubyte)[] svgData)
    {
        super(null, 0, 0, 4, 0);
        init_(name, svgData, null);
    }

    // Private constructor for copy() -- shares the parsed svgImage_
    // rather than re-parsing (matching FLTK's ref-counted sharing,
    // see this module's own top comment).
    private this(const SvgImage source)
    {
        super(null, 0, 0, 4, 0);
        svgImage_ = cast(NsvgImage) source.svgImage_;
        proportional_ = source.proportional_;
        w(source.w());
        h(source.h());
    }

    private float svgScaling_(int W, int H) const
    {
        float f1 = cast(float) W / cast(int)(svgImage_.width + 0.5f);
        float f2 = cast(float) H / cast(int)(svgImage_.height + 0.5f);
        return f1 < f2 ? f1 : f2;
    }

    private void init_(string sharedname, const(ubyte)[] inData, string filename)
    {
        d(-1);
        ld(errFormat);
        rasterized_ = false;
        rasterW_ = rasterH_ = 0;

        const(ubyte)[] data = inData;
        if (data is null && filename !is null)
        {
            if (!exists(filename)) return;
            try
                data = cast(const(ubyte)[]) read(filename);
            catch (Exception)
                return;
        }
        if (data is null || data.length == 0) return;

        // gzip magic bytes -- .svgz, decompressed via std.zlib (see this
        // module's own top comment).
        if (data.length > 2 && data[0] == 0x1f && data[1] == 0x8b)
        {
            import std.zlib : UnCompress, HeaderFormat;

            try
            {
                auto u = new UnCompress(HeaderFormat.gzip);
                ubyte[] inflated;
                inflated ~= cast(ubyte[]) u.uncompress(data);
                inflated ~= cast(ubyte[]) u.flush();
                data = inflated;
            }
            catch (Exception)
            {
                return;
            }
            if (data.length == 0) return;
        }

        auto buf = (cast(const(char)[]) data).dup; // nsvgParse mutates its input in place
        svgImage_ = nsvgParse(buf, "px", 96);

        if (svgImage_ !is null && svgImage_.width != 0 && svgImage_.height != 0)
        {
            w(cast(int)(svgImage_.width + 0.5f));
            h(cast(int)(svgImage_.height + 0.5f));
            d(4);
            ld(0);
        }
    }

    private void rasterize_(int W, int H)
    {
        if (sharedRasterizer is null) sharedRasterizer = new NsvgRasterizer();

        float fx, fy;
        if (proportional_)
        {
            fx = svgScaling_(W, H);
            fy = fx;
        }
        else
        {
            fx = cast(float) W / svgImage_.width;
            fy = cast(float) H / svgImage_.height;
        }
        auto arr = new ubyte[W * H * 4];
        sharedRasterizer.rasterizeXY(svgImage_, 0, 0, fx, fy, arr, W, H, W * 4);
        array = arr;
        d(4);
        if (toDesaturate_) super.desaturate();
        if (averageWeight_ < 1) super.colorAverage(averageColor_, averageWeight_);
        rasterized_ = true;
        rasterW_ = W;
        rasterH_ = H;
    }

    alias copy = Image.copy; // re-expose the 0-arg overload the override below hides

    override SvgImage copy(int W, int H) const
    {
        auto svg2 = new SvgImage(this);
        svg2.toDesaturate_ = toDesaturate_;
        svg2.averageWeight_ = averageWeight_;
        svg2.averageColor_ = averageColor_;
        svg2.proportional_ = proportional_;
        svg2.w(W);
        svg2.h(H);
        return svg2;
    }

    /**
     * (Re-)rasterizes the SVG data at approximately `width`x`height` (the
     * resulting `w()`/`h()` may differ slightly to preserve aspect ratio
     * when `proportional` is set, matching FLTK's own rounding
     * behavior). Ported from `Fl_SVG_Image::resize()`.
     */
    void resize(int width, int height)
    {
        if (fail() || width <= 0 || height <= 0) return;
        int w1 = width, h1 = height;
        if (proportional_)
        {
            float f = svgScaling_(width, height);
            w1 = cast(int)(svgImage_.width * f + 0.5f);
            h1 = cast(int)(svgImage_.height * f + 0.5f);
        }
        w(w1);
        h(h1);
        if (rasterized_ && w1 == rasterW_ && h1 == rasterH_) return;
        array = null;
        uncache();
        rasterize_(w1, h1);
    }

    /// Whether `resize()` preserves the SVG's own aspect ratio (default
    /// `true`). Ported from the `proportional` field (public FLTK,
    /// exposed here as a getter/setter pair matching this port's usual
    /// property style).
    bool proportional() const { return proportional_; }
    void proportional(bool p) { proportional_ = p; } /// ditto

    /**
     * Ported from `Fl_SVG_Image::draw()`: re-rasterizes at the drawing
     * surface's device-pixel size (`w()*fl.core.currentScale()`), then restores
     * the logical `w()`/`h()` via `scale()`, so `RGBImage.draw()` finds
     * the data already at its target size and blits it without
     * resampling -- a crisp render at any scale, same as FLTK.
     *
     * One deliberate deviation: FLTK calls `resize()` here, whose
     * proportional re-rounding (`svg.width * f + 0.5`) can land 1px off
     * from `RGBImage.draw()`'s own `w()*scale+0.5` target. FLTK's
     * `Fl_RGB_Image::draw()` tolerates that; this port's would instead
     * try to resample via the virtual `copy()`, which `SvgImage`
     * overrides to return a lazy, not-yet-rasterized copy with an empty
     * `array` -- and fall back to drawing the raw buffer unscaled. So
     * the raster buffer is sized with `RGBImage.draw()`'s exact rounding
     * instead (`rasterize_()` still fits the SVG proportionally inside
     * it when `proportional()` is set).
     */
    override void draw(int X, int Y, int W, int H, int cx = 0, int cy = 0)
    {
        import fl.core : currentScale;

        if (fail())
        {
            super.draw(X, Y, W, H, cx, cy);
            return;
        }
        int w1 = w(), h1 = h();
        float f = currentScale();
        int w2 = cast(int)(w1 * f + 0.5f);
        int h2 = cast(int)(h1 * f + 0.5f);
        if (w2 < 1) w2 = 1;
        if (h2 < 1) h2 = 1;
        if (!(rasterized_ && w2 == rasterW_ && h2 == rasterH_) || dataW() != w2 || dataH() != h2)
        {
            w(w2);
            h(h2);
            array = null;
            uncache();
            rasterize_(w2, h2);
        }
        scale(w1, h1, false, true);
        super.draw(X, Y, W, H, cx, cy);
    }

    alias draw = Image.draw; // re-expose the 2-arg overload the override above hides

    override void desaturate()
    {
        toDesaturate_ = true;
        super.desaturate();
    }

    override void colorAverage(Color c, float i)
    {
        averageColor_ = c;
        averageWeight_ = i;
        super.colorAverage(c, i);
    }

    /// Ensures the SVG has been rasterized at least once (at its current
    /// `w()`/`h()`) -- ported from `Fl_SVG_Image::normalize()`.
    void normalize()
    {
        if (array.length == 0) resize(w(), h());
    }

    override void scale(int width, int height, bool proportional = true, bool canExpand = true)
    {
        super.scale(width, height, proportional, true);
    }
}

unittest
{
    // Load from in-memory text, confirm dimensions and a real rasterized
    // pixel once draw()/normalize() forces the lazy render.
    string svg = `<svg width="10" height="10"><rect x="0" y="0" width="10" height="10" fill="#00ff00"/></svg>`;
    auto img = new SvgImage(null, svg);
    assert(!img.fail());
    assert(img.w() == 10 && img.h() == 10);
    assert(img.array.length == 0); // not rasterized yet -- lazy

    img.normalize();
    assert(img.array.length == 10 * 10 * 4);
    size_t off = (5 * 10 + 5) * 4;
    assert(img.array[off + 1] == 255); // green
    assert(img.array[off + 3] == 255); // opaque
}

unittest
{
    // resize() re-rasterizes at a new size (proportional).
    string svg = `<svg width="10" height="20"><rect width="10" height="20" fill="#ff0000"/></svg>`;
    auto img = new SvgImage(null, svg);
    img.resize(20, 20); // proportional -> capped to 10x20 aspect within 20x20
    assert(img.w() <= 20 && img.h() <= 20);
    assert(img.array.length == cast(size_t) img.w() * img.h() * 4);
}

unittest
{
    // copy() shares the parsed document but rasterizes independently at
    // its own requested size.
    string svg = `<svg width="10" height="10"><rect width="10" height="10" fill="#0000ff"/></svg>`;
    auto img = new SvgImage(null, svg);
    auto img2 = img.copy(5, 5);
    assert(img2.w() == 5 && img2.h() == 5);
    img2.normalize();
    assert(img2.array.length == 5 * 5 * 4);
    // Original is untouched by the copy's own rasterization.
    assert(img.array.length == 0);
}

unittest
{
    // Malformed/empty input -> fail(), matching FLTK's ld(ERR_FORMAT)
    // contract; a nonexistent file behaves the same way.
    auto bad = new SvgImage("/nonexistent/path/does-not-exist.svg");
    assert(bad.fail());

    auto empty = new SvgImage(null, "");
    assert(empty.fail());
}

unittest
{
    // .svgz (gzip-compressed SVG) round-trips through real decompression
    // -- compressed in-process via std.zlib.Compress rather than shelling
    // out to a real `gzip` binary, same real gzip container either way
    // (confirmed against a real `gzip`-produced file while developing this).
    import std.zlib : Compress, HeaderFormat;

    string svg = `<svg width="10" height="10"><rect width="10" height="10" fill="#00ff00"/></svg>`;
    auto c = new Compress(6, HeaderFormat.gzip);
    ubyte[] compressed;
    compressed ~= cast(ubyte[]) c.compress(cast(ubyte[]) svg);
    compressed ~= cast(ubyte[]) c.flush();
    assert(compressed[0] == 0x1f && compressed[1] == 0x8b); // real gzip magic

    auto img = new SvgImage("fake.svgz", compressed);
    assert(!img.fail());
    assert(img.w() == 10 && img.h() == 10);

    img.normalize();
    assert(img.array.length == 10 * 10 * 4);
    size_t off = (5 * 10 + 5) * 4;
    assert(img.array[off + 1] == 255); // green
    assert(img.array[off + 3] == 255); // opaque
}

unittest
{
    // Malformed gzip (right magic, garbage payload) fails gracefully.
    ubyte[] badGzip = [0x1f, 0x8b, 0x08, 0x00, 0x00, 0xff, 0xff, 0xff, 0xff];
    auto img = new SvgImage("fake.svgz", badGzip);
    assert(img.fail());
}
