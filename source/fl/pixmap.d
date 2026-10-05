/*
 * Ported from FL/Fl_Pixmap.H + src/Fl_Pixmap.cxx + src/fl_draw_pixmap.cxx
 * (FLTK 1.5.0): Fl_Pixmap, a color-table-indexed
 * (XPM-style) image with transparency. Milestone 2 of the fl.image
 * port -- see fl.image's own top comment for the overall staging.
 *
 * Real, drawn-pixels support: draw() decodes the XPM color table +
 * pixel-index rows into a plain RGBA byte buffer (ported from
 * fl_convert_pixmap(), pure data logic, no display needed), at
 * whatever resolution the live screen scale calls for (see draw()'s
 * own doc comment), then draws the RGB part via the same
 * fl.draw.drawImageFixed() primitive fl.image.RGBImage uses.
 * Transparency is real too, but *binary*
 * (fully opaque or fully transparent, never a blended alpha) -- a
 * classic XPM color is either successfully parsed (opaque) or is the
 * "None"/unparseable placeholder color (transparent), so the native
 * X11 path uses the same technique FLTK's own non-cached drawing
 * path does: a 1-bit clip mask built from the alpha channel (fl.draw's
 * new setClipMask()/clearClipMask(), reusing fl.bitmap's own
 * createBitmask()/create_bitmask() machinery), not per-pixel alpha
 * compositing -- there is no partial transparency in this format to
 * composite in the first place. Ported from
 * Fl_Xlib_Graphics_Driver::draw_fixed(Fl_Pixmap*,...)/cache(Fl_Pixmap*)
 * and fl_draw_pixmap()'s own mask-building loop.
 *
 * **The mask-based path above is X11/Xlib-only**:
 * `fl.graphics_driver.currentDriver !is null`
 * (drawing while composited over a GL scene, see fl.gl_window/
 * fl.gl_graphics_driver) takes a separate branch entirely, skipping
 * the GC clip mask (which has zero effect on a GL front/back buffer)
 * and drawing the already-decoded RGBA buffer directly as a real
 * per-pixel-alpha `d==4` image instead, letting GL's own blend state
 * composite it correctly. See draw()'s own doc comment at that branch.
 *
 * Deviations from FLTK, matching fl.image/fl.bitmap's established
 * precedent:
 *  - xpmData is a real D `const(string)[]` (row 0 = "W H ncolors
 *    chars_per_pixel" header, then the color table, then the pixel
 *    rows), not FLTK's `char* const*` -- a caller can still pass
 *    a compile-time XPM literal array directly, the single most
 *    common real-world use of this class (embedded icons), including
 *    the idiomatic `static immutable string[]` form (see the
 *    constructor's own doc comment for why `const`, not plain
 *    `string[]`, is what makes that work with no `.dup`).
 *  - No `alloc_data`/`copy_data()` "make an owned mutable copy before
 *    mutating" bookkeeping. FLTK needs this because it mutates
 *    color-table strings *in place* (`strcpy()` over the existing
 *    buffer) inside color_average()/desaturate() -- a real hazard if
 *    the array is a caller-owned compile-time literal. D strings are
 *    immutable, so this port's color_average()/desaturate() build a
 *    *new* string[] with replacement rows instead of ever mutating one
 *    in place; the "don't corrupt the caller's original data" problem
 *    FLTK's copy_data() solves doesn't exist here to begin with.
 *  - `parseColor()`'s named-color lookup (`fl.draw`'s own row) is
 *    real for the common `#RRGGBB`-style hex case without needing a
 *    live display (headless-testable); bare X11 color names (e.g.
 *    "red") need one, matching every other X-server-dependent
 *    primitive in this port.
 */
module fl.pixmap;

import fl.image : Image;
import fl.enumerations : Color;
static import fl.enumerations;
import fldraw = fl.draw;
import fl.graphics_driver : currentDriver;
import std.format : format;
import fl.core; // screenScale() -- circular with fl.core's own `import
// fl.pixmap : Pixmap;`, same precedent as fl.tooltip/fl.core and
// fl.platform_x11/fl.window elsewhere in this port.

class Pixmap : Image
{
    /// The raw XPM data rows -- see the module's own top comment for
    /// the exact layout (header / color table / pixel rows).
    const(string)[] xpmData;

    private ulong maskId_;
    /// The `fl.core.currentScale()` value `maskId_` was last built at
    /// (`0.0` meaning "never built"). `maskId_` is a real X11 1-bit
    /// bitmap, inherently sized in device pixels, so it must be rebuilt
    /// at `dataW()`x`dataH()` scaled to the *current* device-pixel size
    /// whenever the scale changes -- `drawImage()`'s own RGB content
    /// already resamples to the *scaled* device-pixel size, so a mask
    /// left at its native size would end up smaller than the actual
    /// drawn content at scale > 1 (truncating it), or leave mismatched
    /// artifacts at scale < 1. Tracked here so `draw()` can tell "still
    /// valid" from "scale changed, rebuild at the new size" apart, the
    /// same way `fl.draw.currentFontScale_` already does for cached
    /// fonts.
    private float maskScale_ = 0.0f;

    /// Creates a pixmap from XPM data rows. Bad/empty data leaves the
    /// image unmeasured (`w() < 0`, matching FLTK's own `Fl_Image
    /// (-1,0,1)` sentinel construction) -- unlike RGBImage/Bitmap,
    /// `fail()` correctly reports this case directly (`w() <= 0`),
    /// no `hasData()` tracking needed (see fl.image's own note on why
    /// that flag exists at all).
    ///
    /// `const(string)[]`, not `string[]`: a `static immutable string[]`
    /// compile-time XPM literal -- the single most common real-world
    /// way this class gets used -- has type `immutable(string[])`,
    /// which doesn't implicitly convert to a mutable `string[]`
    /// parameter. `const(string)[]` accepts both that and a plain
    /// mutable `string[]` with no caller-side `.dup` needed, and costs
    /// nothing internally: `xpmData` is never mutated in place, only
    /// ever replaced wholesale (see the module's own top comment on
    /// why no `alloc_data`/`copy_data()` bookkeeping exists here).
    this(const(string)[] data)
    {
        super(-1, 0, 1);
        xpmData = data;
        measureImpl();
    }

    ~this()
    {
        uncache();
    }

    alias copy = Image.copy; // re-expose the 0-arg overload the override below hides
    alias draw = Image.draw; // re-expose the 2-arg overload the override below hides

    override void uncache()
    {
        fldraw.freeBitmask(maskId_);
        maskId_ = 0;
        maskScale_ = 0.0f;
        // `scaledCache_` is a real D-side cache too (see its own doc
        // comment below) -- dropped here so `colorAverage()`/
        // `desaturate()` (which both call `uncache()` *before*
        // replacing `xpmData`) can't leave a stale pre-mutation
        // resampled copy behind for the next `draw()` to silently
        // reuse whenever the resampled size happens not to change.
        scaledCache_ = null;
    }

    private void measureImpl()
    {
        if (w() < 0 && xpmData.length > 0)
        {
            int W, H, nc, cpp;
            if (parseHeader(xpmData[0], W, H, nc, cpp))
            {
                w(W);
                h(H);
            }
        }
    }

    /// A real resampled copy at the current live `fl.core.currentScale()`-driven
    /// *device-pixel* target size, rebuilt lazily whenever that target
    /// changes -- see `draw()`'s own use of this. This matches
    /// FLTK's real `Fl_Graphics_Driver::cache_size()` +
    /// `pxm->copy(w2,h2)` exactly: the *target* size is `w()`/`h()`
    /// times the live `fl.core.currentScale()`, always resampled from
    /// `this`'s own pristine `xpmData`, never from a previously-resampled
    /// copy -- resampling from a previously-resampled copy (rather than
    /// always from the pristine native XPM data) would compound two
    /// lossy nearest-neighbor passes into a visibly blockier result than
    /// FLTK's single exact/near-exact resample from full native
    /// resolution, and comparing only the fixed *logical* `w()`/`h()`
    /// against `dataW()`/`dataH()` (rather than the live scale-driven
    /// target size) would leave `scale()` -- `fl.image.Image.scale()`
    /// -- silently inert: it only ever updates `w()`/`h()`, the
    /// *logical* size, so `draw()` needs to consult the live scale
    /// itself to actually render at a different size.
    private Pixmap scaledCache_;

    /// Returns a real resampled copy at the current live-scale-driven
    /// target size (see `scaledCache_`'s own doc comment) if that
    /// differs from the native XPM size (`dataW()`/`dataH()`), or
    /// `this` unchanged if it's an exact match -- the same "hits its
    /// own exact-size fast path, zero resampling" case FLTK's own
    /// `Fl_Pixmap::copy()` gets whenever an icon's native resolution
    /// happens to equal `w()*scale()` (e.g. a 32x32 XPM drawn at 16
    /// logical units, exactly matched at 200%). Split out from
    /// `draw()` (which uses whatever this returns) so the caching
    /// decision itself is headlessly testable without a real drawable.
    /// Takes `scale` as an explicit parameter (rather than reading
    /// `fl.core.currentScale()` itself) for that same headless-
    /// testability -- `draw()`'s own call passes the live value.
    private Pixmap scaledForDraw(float scale)
    {
        int wantW = cast(int)(w() * scale + 0.5f);
        int wantH = cast(int)(h() * scale + 0.5f);
        if (wantW < 1) wantW = 1;
        if (wantH < 1) wantH = 1;
        if (wantW == dataW() && wantH == dataH()) return this;
        if (scaledCache_ is null || scaledCache_.dataW() != wantW || scaledCache_.dataH() != wantH)
            scaledCache_ = copy(wantW, wantH);
        return scaledCache_ !is null ? scaledCache_ : this;
    }

    /**
     * Ported from `Fl_Graphics_Driver::draw_pixmap()`. Decodes the XPM
     * color table + pixel rows into a plain RGBA buffer *once*, at
     * whatever resolution `scaledForDraw()` decides is the right target
     * for the live screen scale (native resolution unchanged, or a
     * cached resampled copy -- see that method's own doc comment), and
     * blits it 1:1 via `fl.draw.drawImageFixed()` -- no further
     * resampling happens at the blit step, matching FLTK's own
     * "cache once, blit unscaled" model exactly (`draw_fixed()`).
     */
    override void draw(int X, int Y, int W, int H, int cx = 0, int cy = 0)
    {
        if (xpmData.length == 0 || dataW() <= 0 || dataH() <= 0)
        {
            drawEmpty(X, Y);
            return;
        }

        float s = fl.core.currentScale();
        auto src = scaledForDraw(s);
        const(string)[] drawXpm = src.xpmData;
        int bufW = src.dataW(), bufH = src.dataH();

        auto rgba = new ubyte[bufW * bufH * 4];
        // The bg color only fills the (masked-out, never actually
        // visible) transparent pixels' RGB channels -- matches
        // FLTK's own cache() hardcoding FL_BLACK for the same
        // reason (the exact value is cosmetically irrelevant).
        if (!convertPixmap(drawXpm, rgba, fl.enumerations.black))
        {
            drawEmpty(X, Y);
            return;
        }

        // Crop math in FLTK/logical units, matching FLTK's own
        // start_image() clamp against img->w()/img->h() (not the
        // native/cached pixel size) -- mapped into the decoded buffer's
        // own pixel coordinates afterward.
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
        if (bufPx + bufPw > bufW) bufPw = bufW - bufPx;
        if (bufPy + bufPh > bufH) bufPh = bufH - bufPy;
        if (bufPw <= 0 || bufPh <= 0) return;

        // `XSetClipMask()` (below, for the transparency mask) and
        // `XSetClipRectangles()` (`fl.draw.restoreClip()`, applying the
        // active `pushClip()` rectangle) are the *same* GC attribute in
        // core X11 -- setting one silently discards the other, there is
        // no automatic combination of the two. FLTK's own
        // `Fl_Xlib_Graphics_Driver::draw_fixed(Fl_Pixmap*,...)` handles
        // this by manually intersecting the draw box with the current
        // clip region before drawing (looping over each rectangle of a
        // general, possibly multi-rectangle `Fl_Region`); this port's
        // clip stack only ever tracks one rectangle at a time (see
        // `fl.draw`'s own note on that simplification), so the
        // equivalent fix is a single `clipBox()` intersection here.
        // Without this step, any `Pixmap` drawn while a smaller clip
        // rectangle is active (e.g. a partial-damage repaint) would have
        // its *mask's* origin/extent silently override that clip,
        // bleeding the full (X,Y,W,H) box onto whatever sits just
        // outside the intended repaint area -- visible via the
        // "plastic" scheme's tiled window background
        // (`fl.tiled_image.TiledImage`, built from a `Pixmap`) painting
        // over a button during a repaint clipped to a *different* small
        // area.
        int drawX = X - cx + px;
        int drawY = Y - cy + py;
        int clipX, clipY, clipW, clipH;
        fldraw.clipBox(drawX, drawY, pw, ph, clipX, clipY, clipW, clipH);
        if (clipW <= 0 || clipH <= 0) return;
        // Shrink the buffer-pixel sub-rect by whatever clipBox() just
        // trimmed off each edge, mapping the trim from FLTK units into
        // buffer pixels the same way the crop above was mapped.
        bufPx += cast(int)((clipX - drawX) * s + 0.5f);
        bufPy += cast(int)((clipY - drawY) * s + 0.5f);
        bufPw = cast(int)(clipW * s + 0.5f);
        bufPh = cast(int)(clipH * s + 0.5f);
        if (bufPx + bufPw > bufW) bufPw = bufW - bufPx;
        if (bufPy + bufPh > bufH) bufPh = bufH - bufPy;
        if (bufPw <= 0 || bufPh <= 0) return;

        // The mask-based transparency below is a pure X11/Xlib GC
        // mechanism (`XSetClipMask()`, applied to
        // the *drawable's* GC) -- it has zero effect while `draw()` is
        // routing through `currentDriver.drawImage()` (a `GlWindow`
        // compositing into its GL front/back buffer, not drawing
        // through the X11 GC at all). Take a GL-native path instead:
        // `rgba` above already has a real, correct per-pixel alpha
        // channel (0 for the XPM "None" color, 255 otherwise, built by
        // `convertPixmap()`) -- draw it directly as a `d==4` image, the
        // same way `fl.image.RGBImage.draw()`'s own RGBA case already
        // does, letting `GlGraphicsDriver.drawImage()`'s real alpha
        // blending (`GL_BLEND`, set up once per frame by `GlWindow.
        // drawBegin()`) do real transparency instead of an all-or-
        // nothing GC clip mask.
        if (currentDriver !is null)
        {
            const(ubyte)* pRgba = rgba.ptr + (bufPy * bufW + bufPx) * 4;
            fldraw.drawImageFixed(pRgba, bufPw, bufPh, bufW * 4, 4, clipX, clipY);
            return;
        }

        if (maskId_ == 0 || maskScale_ != s)
        {
            if (maskId_ != 0) fldraw.freeBitmask(maskId_);

            // `rgba` is already decoded at the exact target resolution
            // (bufW x bufH) the RGB blit below also uses -- no separate
            // resample needed here at all: building the mask from a
            // separately-resampled copy (rather than this same buffer)
            // could desync the two by a rounding pixel or more, since
            // both must derive from the exact same buffer to guarantee
            // they can't drift apart.
            auto maskBits = buildAlphaMask(rgba, bufW, bufH);
            maskId_ = fldraw.createBitmask(bufW, bufH, maskBits.ptr);
            maskScale_ = s;
        }

        // Strip the alpha byte back out for the color blit -- the
        // mask (built above) handles transparency instead.
        auto rgb = new ubyte[bufW * bufH * 3];
        for (size_t i = 0, j = 0; i < rgba.length; i += 4, j += 3)
        {
            rgb[j] = rgba[i];
            rgb[j + 1] = rgba[i + 1];
            rgb[j + 2] = rgba[i + 2];
        }

        if (maskId_ != 0) fldraw.setClipMask(maskId_, X - cx, Y - cy);
        const(ubyte)* p = rgb.ptr + bufPy * bufW * 3 + bufPx * 3;
        fldraw.drawImageFixed(p, bufPw, bufPh, bufW * 3, 3, clipX, clipY);
        if (maskId_ != 0) fldraw.clearClipMask();
    }

    /// Ported from `Fl_Pixmap::copy()` -- resamples the pixel-index
    /// rows via the same nearest-neighbor Bresenham stepping
    /// RGBImage/Bitmap's own copy() use, reusing the source color
    /// table unchanged.
    override Pixmap copy(int W, int H) const
    {
        if (xpmData.length == 0) return new Pixmap(null);
        if (W == dataW() && H == dataH())
            return new Pixmap(xpmData.dup);
        if (W <= 0 || H <= 0) return null;

        int oW, oH, ncolors, cpp;
        if (!parseHeader(xpmData[0], oW, oH, ncolors, cpp)) return null;

        int colorRows = ncolors < 0 ? 1 : ncolors;
        if (1 + colorRows + oH > xpmData.length) return null;

        auto newData = new string[1 + colorRows + H];
        newData[0] = format("%d %d %d %d", W, H, ncolors, cpp);
        newData[1 .. 1 + colorRows] = xpmData[1 .. 1 + colorRows];

        int xmod = oW % W;
        int xstep = (oW / W) * cpp;
        int ymod = oH % H;
        int ystep = oH / H;

        int sy = 0, yerr = H;
        for (int dy = 0; dy < H; dy++)
        {
            string oldRow = xpmData[1 + colorRows + sy];
            auto newRow = new char[W * cpp];
            size_t oldP = 0, newP = 0;
            int xerr = W;
            for (int dx = 0; dx < W; dx++)
            {
                for (int c = 0; c < cpp; c++)
                    newRow[newP++] = oldP + c < oldRow.length ? oldRow[oldP + c] : '\0';
                oldP += xstep;
                xerr -= xmod;
                if (xerr <= 0)
                {
                    xerr += W;
                    oldP += cpp;
                }
            }
            newData[1 + colorRows + dy] = cast(string) newRow;

            sy += ystep;
            yerr -= ymod;
            if (yerr <= 0)
            {
                yerr += H;
                sy++;
            }
        }
        return new Pixmap(newData);
    }

    override void colorAverage(Color c, float i)
    {
        if (xpmData.length == 0) return;
        uncache();

        int W, H, ncolors, cpp;
        if (!parseHeader(xpmData[0], W, H, ncolors, cpp)) return;

        ubyte r, g, b;
        fldraw.colorToRgb8(c, r, g, b);
        if (i < 0.0f) i = 0.0f;
        else if (i > 1.0f) i = 1.0f;
        uint ia = cast(uint)(256 * i);
        uint ir = r * (256 - ia);
        uint ig = g * (256 - ia);
        uint ib = b * (256 - ia);

        auto newData = xpmData.dup;

        if (ncolors < 0)
        {
            int nc = -ncolors;
            auto bytes = cast(ubyte[])(newData[1].dup);
            for (int idx = 0; idx < nc; idx++)
            {
                size_t off = idx * 4;
                if (off + 4 > bytes.length) break;
                bytes[off + 1] = cast(ubyte)((ia * bytes[off + 1] + ir) >> 8);
                bytes[off + 2] = cast(ubyte)((ia * bytes[off + 2] + ig) >> 8);
                bytes[off + 3] = cast(ubyte)((ia * bytes[off + 3] + ib) >> 8);
            }
            newData[1] = cast(string) bytes;
        }
        else
        {
            for (int idx = 0; idx < ncolors && 1 + idx < newData.length; idx++)
            {
                string row = newData[1 + idx];
                if (row.length < cpp) continue;
                string colorWord = findColorWord(row[cpp .. $]);
                ubyte cr, cg, cb;
                if (fldraw.parseColor(colorWord, cr, cg, cb))
                {
                    cr = cast(ubyte)((ia * cr + ir) >> 8);
                    cg = cast(ubyte)((ia * cg + ig) >> 8);
                    cb = cast(ubyte)((ia * cb + ib) >> 8);
                    newData[1 + idx] = format("%s c #%02X%02X%02X", row[0 .. cpp], cr, cg, cb);
                }
            }
        }
        xpmData = newData;
    }

    override void desaturate()
    {
        if (xpmData.length == 0) return;
        uncache();

        int W, H, ncolors, cpp;
        if (!parseHeader(xpmData[0], W, H, ncolors, cpp)) return;

        auto newData = xpmData.dup;

        if (ncolors < 0)
        {
            int nc = -ncolors;
            auto bytes = cast(ubyte[])(newData[1].dup);
            for (int idx = 0; idx < nc; idx++)
            {
                size_t off = idx * 4;
                if (off + 4 > bytes.length) break;
                ubyte gr = cast(ubyte)((31 * bytes[off + 1] + 61 * bytes[off + 2]
                        + 8 * bytes[off + 3]) / 100);
                bytes[off + 1] = gr;
                bytes[off + 2] = gr;
                bytes[off + 3] = gr;
            }
            newData[1] = cast(string) bytes;
        }
        else
        {
            for (int idx = 0; idx < ncolors && 1 + idx < newData.length; idx++)
            {
                string row = newData[1 + idx];
                if (row.length < cpp) continue;
                string colorWord = findColorWord(row[cpp .. $]);
                ubyte r, g, b;
                if (fldraw.parseColor(colorWord, r, g, b))
                {
                    ubyte gr = cast(ubyte)((31 * r + 61 * g + 8 * b) / 100);
                    newData[1 + idx] = format("%s c #%02X%02X%02X", row[0 .. cpp], gr, gr, gr);
                }
            }
        }
        xpmData = newData;
    }
}

/// Parses the header row ("W H ncolors chars_per_pixel", possibly with
/// trailing content this port ignores, matching FLTK's own
/// `sscanf()`-based parse which only ever consumes the first 4
/// numbers). Ported from `fl_measure_pixmap()`.
package(fl) bool parseHeader(string header, out int w, out int h, out int ncolors, out int cpp)
{
    import std.string : split;
    import std.conv : to, ConvException;

    auto parts = header.split();
    if (parts.length < 4) return false;
    try
    {
        w = parts[0].to!int;
        h = parts[1].to!int;
        ncolors = parts[2].to!int;
        cpp = parts[3].to!int;
    }
    catch (ConvException)
    {
        return false;
    }
    if (w <= 0 || h <= 0 || (cpp != 1 && cpp != 2)) return false;
    return true;
}

private bool isSpaceChar(char c)
{
    return c == ' ' || c == '\t' || c == '\n' || c == '\r';
}

/**
 * Finds the "c COLOR" spec within a color-table row's tail (everything
 * after the pixel-index character(s)), falling back to the last
 * key/word pair seen if no "c" key exists at all -- ported line-for-
 * line from `fl_convert_pixmap()`'s inline word-scanning loop
 * (`src/fl_draw_pixmap.cxx`), which FLTK never factored out into
 * its own function; kept as one here since `Pixmap.colorAverage()`/
 * `desaturate()` need the identical scan too. Returns the rest of the
 * row from the found color word onward (not truncated at the next
 * space) -- matching FLTK's own `fl_parse_color((const char*)p,
 * ...)` call exactly, which hands the whole tail to the color parser
 * rather than pre-isolating one token.
 */
package(fl) string findColorWord(string s)
{
    size_t p = 0;
    size_t previousWord = 0;
    for (;;)
    {
        while (p < s.length && isSpaceChar(s[p])) p++;
        if (p >= s.length)
        {
            p = previousWord;
            break;
        }
        char what = s[p];
        p++;
        while (p < s.length && !isSpaceChar(s[p])) p++;
        while (p < s.length && isSpaceChar(s[p])) p++;
        if (p >= s.length)
        {
            p = previousWord;
            break;
        }
        if (what == 'c') break;
        previousWord = p;
        while (p < s.length && !isSpaceChar(s[p])) p++;
    }
    return p <= s.length ? s[p .. $] : "";
}

/**
 * Decodes XPM data (header + color table + pixel rows) into a plain
 * RGBA byte buffer (`dataW()*dataH()*4` bytes, pre-sized by the
 * caller). Ported from `fl_convert_pixmap()` (`src/fl_draw_pixmap.cxx`)
 * -- pure data logic, no display needed (`parseColor()`'s hex path
 * is headless too; only bare X11 color names need one, and only when
 * actually present in the data). `bg` fills a transparent pixel's RGB
 * channels (never actually visible -- see `Pixmap.draw()`'s own doc
 * comment on why the exact value doesn't matter).
 */
package(fl) bool convertPixmap(const(string)[] data, ubyte[] out_, Color bg)
{
    int W, H, ncolors, cpp;
    if (data.length == 0 || !parseHeader(data[0], W, H, ncolors, cpp)) return false;

    size_t tableSize = cpp == 1 ? 256 : 65536;
    auto colors = new ubyte[4][tableSize];

    size_t rowIdx = 1;
    if (ncolors < 0)
    {
        int nc = -ncolors;
        if (rowIdx >= data.length) return false;
        string row = data[rowIdx++];
        size_t p = 0;
        if (p < row.length && row[p] == ' ')
        {
            ubyte r, g, b;
            fldraw.colorToRgb8(bg, r, g, b);
            colors[' '][0] = r;
            colors[' '][1] = g;
            colors[' '][2] = b;
            colors[' '][3] = 0;
            p += 4;
            nc--;
        }
        for (int i = 0; i < nc; i++)
        {
            if (p + 4 > row.length) return false;
            ubyte idx = cast(ubyte) row[p];
            colors[idx][0] = cast(ubyte) row[p + 1];
            colors[idx][1] = cast(ubyte) row[p + 2];
            colors[idx][2] = cast(ubyte) row[p + 3];
            colors[idx][3] = 255;
            p += 4;
        }
    }
    else
    {
        for (int i = 0; i < ncolors; i++)
        {
            if (rowIdx >= data.length) return false;
            string row = data[rowIdx++];
            if (row.length < cpp) return false;
            uint ind = cast(ubyte) row[0];
            size_t p = 1;
            if (cpp > 1)
            {
                ind = (ind << 8) | cast(ubyte) row[1];
                p = 2;
            }
            string colorWord = findColorWord(row[p .. $]);
            ubyte r, g, b;
            if (fldraw.parseColor(colorWord, r, g, b))
            {
                colors[ind][0] = r;
                colors[ind][1] = g;
                colors[ind][2] = b;
                colors[ind][3] = 255;
            }
            else
            {
                fldraw.colorToRgb8(bg, r, g, b);
                colors[ind][0] = r;
                colors[ind][1] = g;
                colors[ind][2] = b;
                colors[ind][3] = 0;
            }
        }
    }

    size_t outIdx = 0;
    for (int y = 0; y < H; y++)
    {
        if (rowIdx >= data.length) return false;
        string row = data[rowIdx++];
        size_t p = 0;
        for (int x = 0; x < W; x++)
        {
            uint ind;
            if (cpp <= 1)
            {
                if (p >= row.length) return false;
                ind = cast(ubyte) row[p++];
            }
            else
            {
                if (p + 2 > row.length) return false;
                ind = (cast(ubyte) row[p] << 8) | cast(ubyte) row[p + 1];
                p += 2;
            }
            out_[outIdx++] = colors[ind][0];
            out_[outIdx++] = colors[ind][1];
            out_[outIdx++] = colors[ind][2];
            out_[outIdx++] = colors[ind][3];
        }
    }
    return true;
}

/// Builds a 1-bit-per-pixel mask array (opaque = 1) from an RGBA
/// buffer's alpha channel -- ported from `fl_draw_pixmap()`'s own
/// mask-building loop (`src/fl_draw_pixmap.cxx`).
package(fl) ubyte[] buildAlphaMask(const(ubyte)[] rgba, int w, int h)
{
    int rowBytes = (w + 7) / 8;
    auto mask = new ubyte[rowBytes * h];
    size_t alphaIdx = 3;
    size_t outIdx = 0;
    for (int y = 0; y < h; y++)
    {
        ubyte b = 0;
        int bit = 1;
        for (int x = 0; x < w; x++)
        {
            if (rgba[alphaIdx] > 127) b |= bit;
            alphaIdx += 4;
            bit <<= 1;
            if (bit > 0x80 || x == w - 1)
            {
                mask[outIdx++] = b;
                bit = 1;
                b = 0;
            }
        }
    }
    return mask;
}

unittest
{
    // parseHeader(): the common case plus a malformed row.
    int w, h, nc, cpp;
    assert(parseHeader("16 16 4 1", w, h, nc, cpp));
    assert(w == 16 && h == 16 && nc == 4 && cpp == 1);

    assert(parseHeader("8 8 -3 1 0 0", w, h, nc, cpp)); // trailing hotspot ignored
    assert(nc == -3);

    assert(!parseHeader("not a header", w, h, nc, cpp));
    assert(!parseHeader("8 8 4 3", w, h, nc, cpp)); // chars_per_pixel must be 1 or 2
}

unittest
{
    // findColorWord(): the "c" key found directly, a non-"c" key
    // skipped over, and the no-"c"-at-all fallback.
    assert(findColorWord(" c #FF0000") == "#FF0000");
    assert(findColorWord(" m black c #00FF00") == "#00FF00");
    assert(findColorWord(" g gray50") == "gray50"); // no "c" key -- falls back to the last word
}

unittest
{
    // convertPixmap(): a real 2x2 standard-XPM-colormap pixmap (one
    // opaque color, one "None" transparent color), and the FLTK
    // compressed-colormap ("ncolors < 0") variant of the same image.
    string[] xpm = [
        "2 2 2 1",
        "R c #FF0000",
        ". c None",
        "R.",
        ".R",
    ];
    auto rgba = new ubyte[2 * 2 * 4];
    assert(convertPixmap(xpm, rgba, fl.enumerations.black));
    assert(rgba[0 .. 4] == [255, 0, 0, 255]); // top-left: opaque red
    assert(rgba[4 .. 8][3] == 0); // top-right: transparent (alpha 0)
    assert(rgba[8 .. 12][3] == 0); // bottom-left: transparent
    assert(rgba[12 .. 16] == [255, 0, 0, 255]); // bottom-right: opaque red

    string[] compressed = [
        "2 2 -2 1",
        "\x20\x00\x00\x00\x52\xFF\x00\x00", // transparent-marker entry (' ', 4 bytes), then 'R'->(255,0,0) (4 bytes)
        "R.",
        ".R",
    ];
    auto rgba2 = new ubyte[2 * 2 * 4];
    assert(convertPixmap(compressed, rgba2, fl.enumerations.black));
    assert(rgba2[0 .. 4] == [255, 0, 0, 255]);
    assert(rgba2[4 .. 8][3] == 0);
}

unittest
{
    // buildAlphaMask(): a checkerboard alpha pattern round-trips to
    // the expected bit pattern.
    ubyte[] rgba = new ubyte[4 * 4];
    // 4 pixels: opaque, transparent, opaque, transparent.
    foreach (i; 0 .. 4)
    {
        rgba[i * 4 .. i * 4 + 3] = [0, 0, 0];
        rgba[i * 4 + 3] = (i % 2 == 0) ? 255 : 0;
    }
    auto mask = buildAlphaMask(rgba, 4, 1);
    assert(mask.length == 1); // (4+7)/8 = 1 byte
    assert(mask[0] == 0b0000_0101); // bits 0 and 2 set (pixels 0 and 2 opaque)
}

unittest
{
    // Pixmap: construction/measure(), fail() for bad data, and a real
    // draw()-adjacent round trip via copy()/colorAverage()/desaturate()
    // -- all pure data logic, safe headless.
    string[] xpm = [
        "2 2 2 1",
        "R c #FF0000",
        ". c None",
        "R.",
        ".R",
    ];
    auto pm = new Pixmap(xpm);
    assert(pm.w() == 2 && pm.h() == 2);
    assert(!pm.fail());

    auto broken = new Pixmap(["not a header"]);
    assert(broken.fail());
    assert(broken.w() < 0);

    auto grown = pm.copy(4, 4);
    assert(grown.w() == 4 && grown.h() == 4);
    auto rgba = new ubyte[4 * 4 * 4];
    assert(convertPixmap(grown.xpmData, rgba, fl.enumerations.black));

    auto averaged = pm.copy(2, 2);
    averaged.colorAverage(fl.enumerations.black, 0.0f); // i=0: fully replaced by black
    auto rgba2 = new ubyte[2 * 2 * 4];
    assert(convertPixmap(averaged.xpmData, rgba2, fl.enumerations.black));
    assert(rgba2[0 .. 3] == [0, 0, 0]); // was red, now black

    auto gray = pm.copy(2, 2);
    gray.desaturate();
    auto rgba3 = new ubyte[2 * 2 * 4];
    assert(convertPixmap(gray.xpmData, rgba3, fl.enumerations.black));
    // 31*255/100 = 79 (integer division)
    assert(rgba3[0] == 79 && rgba3[1] == 79 && rgba3[2] == 79);
}

unittest
{
    // scaledForDraw(scale): draw()
    // respects both the icon's fixed logical size (scale()) *and* the
    // live screen scale now, via a lazily-built-and-reused cached
    // resampled copy -- headless-testable via this split-out helper,
    // since draw() itself still needs a real drawable.
    string[] xpm = [
        "4 4 2 1",
        "R c #FF0000",
        ". c None",
        "RRRR",
        "RRRR",
        "RRRR",
        "RRRR",
    ];
    auto pm = new Pixmap(xpm);
    assert(pm.w() == 4 && pm.h() == 4);

    // No explicit scale() and screen scale 1.0 -- exact match,
    // scaledForDraw() returns `this` unchanged (no resample at all).
    assert(pm.scaledForDraw(1.0f) is pm);

    // Screen scale 0.5 with no explicit scale() -- target (4*0.5=2)
    // differs from native (4), a real resample is needed.
    auto scaled = pm.scaledForDraw(0.5f);
    assert(scaled !is pm);
    assert(scaled.dataW() == 2 && scaled.dataH() == 2);
    assert(scaled.w() == 2 && scaled.h() == 2); // a copy()'s own logical size always equals its native size

    // Calling again with the same live scale reuses the same cached
    // object (not rebuilt every call).
    assert(pm.scaledForDraw(0.5f) is scaled);

    // A different live scale invalidates the cache and rebuilds.
    auto rescaled = pm.scaledForDraw(0.25f);
    assert(rescaled !is scaled);
    assert(rescaled.dataW() == 1 && rescaled.dataH() == 1);

    // Back to scale 1.0 -- exact match again, back to `this`.
    assert(pm.scaledForDraw(1.0f) is pm);
}

unittest
{
    // fluid's widget-panel icons: a 32x32
    // native XPM drawn at a *fixed* 16x16 logical size (`pm.scale(16,
    // 16)`, matching `fluid.pixmaps.load()`'s own real call) -- at a
    // live screen scale of 2.0, the *target* device-pixel size
    // (16*2.0=32) exactly matches the native resolution, so this must
    // hit the zero-resample fast path and return `this` directly,
    // exactly like FLTK's `Fl_Pixmap::copy()` own `W==data_w() &&
    // H==data_h()` branch -- not a cache downscaled to the *logical*
    // 16x16 size first, which would throw away half
    // the native resolution before drawImage()'s own separate
    // nearest-neighbor upscale ever saw it, compounding two lossy
    // passes into a visibly blockier result than FLTK's single
    // exact copy.
    import std.array : replicate;

    auto native = new string[2 + 32];
    native[0] = "32 32 1 1";
    native[1] = "R c #FF0000";
    foreach (i; 0 .. 32) native[2 + i] = "R".replicate(32);
    auto icon = new Pixmap(native);
    icon.scale(16, 16);
    assert(icon.w() == 16 && icon.h() == 16);
    assert(icon.dataW() == 32 && icon.dataH() == 32);

    assert(icon.scaledForDraw(2.0f) is icon, "200% must hit the exact-size fast path, zero resample");

    // At 100%, the target (16) genuinely differs from native (32) --
    // a real downscaled cache is needed and built from `icon`'s own
    // pristine xpmData (verified by re-decoding it below), never from
    // a previously-built cache.
    auto at100 = icon.scaledForDraw(1.0f);
    assert(at100 !is icon);
    assert(at100.dataW() == 16 && at100.dataH() == 16);

    // Going back to 200% returns to the untouched original -- the
    // 100% cache doesn't leak into or replace the native data.
    assert(icon.scaledForDraw(2.0f) is icon);
    assert(icon.dataW() == 32 && icon.dataH() == 32);
}

unittest
{
    // A real 100-wide, 17-color, cpp=1 excerpt of the actual FLTK
    // test/pixmaps/tile.xpm data embedded in
    // source/examples/shapedwindow.d -- 3 real pixel rows instead of
    // the full 100, everything else byte-for-byte identical (header H
    // changed to match). Checks that convertPixmap() decodes this real
    // data correctly, headless and independent of any drawing/masking/
    // X11 involvement.
    string[] realExcerpt = [
        "100 3 17 1",
        " \tc None",
        ".\tc #DCDCDC",
        "+\tc #D9D9D9",
        "@\tc #E4E4E4",
        "#\tc #DFDFDF",
        "$\tc #CECECE",
        "%\tc #D2D2D2",
        "&\tc #C8C8C8",
        "*\tc #CACACA",
        "=\tc #C4C4C4",
        "-\tc #BEBEBE",
        ";\tc #D4D4D4",
        ">\tc #E8E8E8",
        ",\tc #D6D6D6",
        "'\tc #C6C6C6",
        ")\tc #B2B2B2",
        "!\tc #E2E2E2",
        ".+@.##$%%$$$&*=..%$*%-;*>,%$%#>,$,%%*%*.#*%++$;+,,.&&=-%%+.$,#,=;%#,@.+,%>,+=-++@@#%$.++#,--;.=*+,,>",
        "%%.&$@.#,*%*&'%%&$;,*%%,&%;%,#..;$$%';+.+,++.%.;+@@@$'.;'..;@.+$%)&!!,.!>+%@%-*%@>#.+&&+.+$%,++$$#++",
        ",.$&$+#+.%++$%,=$;$&'+.%%&-+++;%;;$%+%+;.#.+@!!..>#+$%;,$.+@,+.%-%%-%>#+.#+$%...%,!>>;$$$.%$+#+*++&*",
    ];

    int W, H, nc, cpp;
    assert(parseHeader(realExcerpt[0], W, H, nc, cpp));
    assert(W == 100 && H == 3 && nc == 17 && cpp == 1);

    auto rgba = new ubyte[100 * 3 * 4];
    assert(convertPixmap(realExcerpt, rgba, fl.enumerations.black));

    // Ground truth read directly off the color table by hand: row 0,
    // col 0 is '.', which maps to #DCDCDC = (220,220,220).
    assert(rgba[0 .. 3] == [220, 220, 220],
        format("row0 col0: got %s, expected [220,220,220]", rgba[0 .. 3]));

    // Row 0, col 1 is '+', #D9D9D9 = (217,217,217).
    assert(rgba[4 .. 7] == [217, 217, 217],
        format("row0 col1: got %s, expected [217,217,217]", rgba[4 .. 7]));

    // Row 1, col 0 is '%', #D2D2D2 = (210,210,210).
    size_t row1col0 = (1 * 100 + 0) * 4;
    assert(rgba[row1col0 .. row1col0 + 3] == [210, 210, 210],
        format("row1 col0: got %s, expected [210,210,210]", rgba[row1col0 .. row1col0 + 3]));

    // Row 2, col 99 (last column) is '*', #CACACA = (202,202,202).
    size_t row2col99 = (2 * 100 + 99) * 4;
    assert(rgba[row2col99 .. row2col99 + 3] == [202, 202, 202],
        format("row2 col99: got %s, expected [202,202,202]", rgba[row2col99 .. row2col99 + 3]));

    // Alpha byte: every one of these colors is real (#RRGGBB), never
    // "None", so every alpha byte must be 255 (opaque) -- if it's 0
    // instead, buildAlphaMask() would treat every pixel as transparent,
    // masking out the entire draw (a live-rendering symptom: mostly
    // black, since the opaque background fill drawn just before would
    // never actually be replaced by anything -- wait, masked-OUT means
    // nothing new is drawn, so this alone wouldn't explain black, but
    // it's the next real thing to rule in/out).
    assert(rgba[3] == 255, format("row0 col0 alpha: got %d, expected 255", rgba[3]));
    assert(rgba[7] == 255, format("row0 col1 alpha: got %d, expected 255", rgba[7]));
    assert(rgba[row1col0 + 3] == 255, format("row1 col0 alpha: got %d, expected 255", rgba[row1col0 + 3]));
    assert(rgba[row2col99 + 3] == 255, format("row2 col99 alpha: got %d, expected 255", rgba[row2col99 + 3]));
}
