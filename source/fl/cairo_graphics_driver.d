/*
 * Port of FLTK's Cairo graphics driver (`src/drivers/Cairo/
 * Fl_Cairo_Graphics_Driver.H`/`.cxx`): every `fl.draw` primitive drawn
 * through Cairo, and text laid out and drawn through Pango.
 *
 * It is the display graphics driver on Wayland, which has no Xlib/Xft,
 * and an alternative to `fl.draw`'s own Xlib/Xft path on X11 (see
 * `fl.draw.useCairoDisplay()`). A target is given to it with
 * `setCairo()`; `fl.draw` creates the Cairo context for each window or
 * offscreen buffer it draws into.
 *
 * Coordinates arrive in FLTK units, except vertex paths (see
 * `wantsUnscaledVertices()`); the driver's base matrix maps them to device pixels: a translation by
 * the current `fl.draw` offset (in device pixels), the drawing scale,
 * and FLTK's half-pixel shift that puts one-unit lines on pixel
 * centers. The scale is read from `fl.core.currentScale()` and the
 * matrix is rebuilt whenever that changes, as
 * `Fl_X11_Cairo_Graphics_Driver::scale()` does.
 *
 * Differences from FLTK's driver:
 *
 * - Clipping follows `fl.draw`'s clip stack: `setClip()` replaces
 *   Cairo's clip with the stack's top rectangle whenever it changes,
 *   instead of a `cairo_save()`/`cairo_restore()` per push/pop. That
 *   also covers `fl.draw.pushNoClip()`, and a pop can no longer restore
 *   an older source color.
 * - The clip, filled rectangles, thin solid horizontal/vertical lines
 *   and rectangle outlines are placed on whole device pixels rounded
 *   down, as on the Xlib path (see `fillDevice()`).
 * - Images arrive as raw buffers, not `Fl_RGB_Image` objects, so a
 *   Cairo pattern is built per draw instead of cached per image.
 * - Vertex paths (`fl.draw.vertex()`, `circle()`, `curve()`) arrive as
 *   point lists already transformed, flattened and scaled to device
 *   pixels by `fl.draw`, not as Cairo path commands.
 * - Indexed colors are always opaque; `fl.core.setColor()` has no alpha.
 * - The context is never null: until `setCairo()` is first called the
 *   driver draws into a small private image surface, so measuring or
 *   drawing before a window exists is harmless (FLTK makes the same
 *   dummy context, but only in `font()`).
 */
module fl.cairo_graphics_driver;

version (FLDTK_HAVE_CAIRO):

import core.stdc.math : ceil, floor, fabs;
import std.math : PI;

import fl.pango_c_cairo;
import fl.enumerations : Color, Font, Fontsize, lineSolid, capFlat, capRound, capSquare,
    joinMiter, joinRound, joinBevel;
import fl.graphics_driver : GraphicsDriver, Point;

/// FLTK's built-in font table for Pango (`built_in_table` in
/// `Fl_Cairo_Graphics_Driver.cxx`), indexed by `Font` 0-15.
private immutable string[16] builtInPangoFonts = [
    "Sans", "Sans Bold", "Sans Italic", "Sans Bold Italic",
    "Monospace", "Monospace Bold", "Monospace Italic", "Monospace Bold Italic",
    "Serif", "Serif Bold", "Serif Italic", "Serif Bold Italic",
    "Standard Symbols PS", // symbol
    "Monospace",           // screen
    "Monospace Bold",      // screenBold
    "D050000L",            // zapfDingbats
];

/**
 * The Pango name of font `fnum`. A built-in font that hasn't been
 * renamed with `fl.draw.setFont()` gets FLTK's own Pango name. A
 * renamed or added font keeps its name, except that a leading style
 * character in the X11 naming used by `fl.draw.getFont()`/
 * `fl.draw.setFonts()` (`' '` plain, `'B'` bold, `'I'` italic, `'P'`
 * bold italic) becomes the matching Pango style suffix.
 */
string pangoFontName(Font fnum, string flName, bool renamed)
{
    if (!renamed && fnum >= 0 && fnum < builtInPangoFonts.length)
        return builtInPangoFonts[fnum];
    if (flName.length < 2) return flName.length ? flName : "Sans";
    switch (flName[0])
    {
        case ' ': return flName[1 .. $];
        case 'B': return flName[1 .. $] ~ " Bold";
        case 'I': return flName[1 .. $] ~ " Italic";
        case 'P': return flName[1 .. $] ~ " Bold Italic";
        default: return flName;
    }
}

unittest
{
    assert(pangoFontName(0, " sans", false) == "Sans");
    assert(pangoFontName(13, " screen", false) == "Monospace");
    assert(pangoFontName(0, "PDejaVu Sans", true) == "DejaVu Sans Bold Italic");
    assert(pangoFontName(16, " Noto Serif", false) == "Noto Serif");
    assert(pangoFontName(16, "Noto Serif", false) == "Noto Serif");
}

/// Replaces invalid UTF-8 with U+FFFD -- FLTK's `fl_utf8_clean()`.
/// Returns `s` itself when it is already valid.
private const(char)[] utf8Clean(const(char)[] s)
{
    import std.utf : decode, UTFException;
    import std.encoding : sanitize;

    size_t i = 0;
    try
    {
        while (i < s.length) decode(s, i);
        return s;
    }
    catch (UTFException)
    {
        return sanitize(s.idup);
    }
}

/// Ported from `Fl_Cairo_Font_Descriptor`: one Pango font at one size,
/// with its metrics in Pango units and a cache of single-character
/// widths for the Basic Multilingual Plane.
private final class FontDescriptor
{
    PangoFontDescription* fontref;
    int ascent, descent, lineHeight;
    int[][] widths; // 64 pages of 1024 widths, -1 = not measured yet

    this(string name, Fontsize size, PangoContext* context)
    {
        import std.format : format;
        import std.string : toStringz;

        fontref = pango_font_description_from_string(format("%s %dpx", name, size).toStringz);
        PangoFontset* fontset = pango_font_map_load_fontset(pango_cairo_font_map_get_default(),
            context, fontref, pango_language_get_default());
        PangoFontMetrics* metrics = pango_fontset_get_metrics(fontset);
        ascent = pango_font_metrics_get_ascent(metrics);
        descent = pango_font_metrics_get_descent(metrics);
        lineHeight = pango_font_metrics_get_height(metrics);
        pango_font_metrics_unref(metrics);
        g_object_unref(fontset);
    }
}

/// Ported from `Fl_Cairo_Graphics_Driver`. See this module's top
/// comment.
class CairoGraphicsDriver : GraphicsDriver
{
    private cairo_t* cairo_;
    private cairo_t* dummyCairo_;
    private PangoContext* pangoContext_;
    private PangoLayout* pangoLayout_;
    private FontDescriptor[string] fontCache_;
    private FontDescriptor font_;
    private int lineStyle_ = lineSolid;
    private Color color_;
    private float appliedScale_ = 0; // 0 forces the first applyBaseMatrix()
    private int offsetX_, offsetY_;
    private bool clipActive_;
    private int clipX_, clipY_, clipW_, clipH_;
    private string fontKey_;
    private bool hairline_ = true; // solid, undashed, default width

    this()
    {
        cairo_surface_t* surf = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, 100, 100);
        dummyCairo_ = cairo_create(surf);
        cairo_surface_destroy(surf);
        cairo_ = dummyCairo_;
        applyBaseMatrix();
    }

    ~this()
    {
        import core.memory : GC;
        if (GC.inFinalizer()) return;
        if (pangoLayout_ !is null) g_object_unref(pangoLayout_);
        if (pangoContext_ !is null) g_object_unref(pangoContext_);
        if (dummyCairo_ !is null) cairo_destroy(dummyCairo_);
    }

    /// The Cairo context drawing currently goes to.
    cairo_t* cr() { return cairo_; }

    /**
     * Makes `cr` the drawing target -- ported from
     * `Fl_Cairo_Graphics_Driver::set_cairo()`. The caller keeps
     * ownership of `cr`. `null` returns to the private dummy context.
     * The line style is reset to the default and the current color is
     * reapplied.
     */
    void setCairo(cairo_t* cr)
    {
        cairo_ = cr !is null ? cr : dummyCairo_;
        clipActive_ = false;
        appliedScale_ = 0;
        applyBaseMatrix();
        lineStyle(lineSolid, 0, null);
        color(color_);
    }

    /// Sets the device-pixel offset `fl.draw.pushTranslate()` adds to
    /// every coordinate.
    void setOffset(int x, int y)
    {
        offsetX_ = x;
        offsetY_ = y;
        appliedScale_ = 0;
        applyBaseMatrix();
    }

    /**
     * Replaces the clip with `(x, y, w, h)` in FLTK units, or removes
     * it when `active` is false. Called by `fl.draw` whenever the top of
     * its clip stack changes (see this module's top comment).
     */
    void setClip(bool active, int x, int y, int w, int h)
    {
        clipActive_ = active;
        clipX_ = x;
        clipY_ = y;
        clipW_ = w;
        clipH_ = h;
        prepare();
        applyClip();
    }

    /// Cairo keeps the clip in device pixels, so it is rebuilt whenever
    /// the base matrix changes (`applyBaseMatrix()`), not only when
    /// `fl.draw`'s clip stack does.
    ///
    /// The rectangle's edges are rounded down to whole device pixels
    /// (`scaledFloor()`), as on the Xlib path, rather than left where
    /// the scale puts them: Cairo would round an edge that falls on half
    /// a pixel to the nearest pixel, so at a fractional scale the clip
    /// could miss a row that `fl.draw.fl_scroll()`'s `XCopyArea()`
    /// (rounded down) left for the redraw to fill -- leaving stale
    /// pixels behind while scrolling.
    private void applyClip()
    {
        cairo_reset_clip(cairo_);
        if (!clipActive_) return;
        int w = clipW_ > 0 ? clipW_ : 0, h = clipH_ > 0 ? clipH_ : 0;
        int xs = scaledFloor(clipX_), ys = scaledFloor(clipY_);
        cairo_matrix_t m;
        cairo_get_matrix(cairo_, &m);
        cairo_identity_matrix(cairo_);
        cairo_translate(cairo_, offsetX_, offsetY_);
        cairo_rectangle(cairo_, xs, ys, scaledFloor(clipX_ + w) - xs, scaledFloor(clipY_ + h) - ys);
        cairo_set_antialias(cairo_, CAIRO_ANTIALIAS_NONE);
        cairo_clip(cairo_);
        cairo_set_antialias(cairo_, CAIRO_ANTIALIAS_DEFAULT);
        cairo_set_matrix(cairo_, &m);
    }

    /// Rebuilds the base matrix if the drawing scale changed since it
    /// was last built. Called at the start of every primitive.
    private void prepare()
    {
        import fl.core : currentScale;
        if (currentScale() != appliedScale_) applyBaseMatrix();
    }

    private void applyBaseMatrix()
    {
        import fl.core : currentScale;
        float s = currentScale();
        appliedScale_ = s;
        cairo_identity_matrix(cairo_);
        cairo_translate(cairo_, offsetX_, offsetY_);
        cairo_scale(cairo_, s, s);
        cairo_translate(cairo_, 0.5, 0.5);
        applyClip();
    }

    /// `fl.draw`'s scaled-coordinate rounding (`scaledFloor()`, from
    /// `Fl_Scalable_Graphics_Driver::floor()`).
    private int scaledFloor(int x) const
    {
        float s = appliedScale_;
        if (s == 1) return x;
        int r = cast(int)((x < 0 ? -x : x) * s + 0.001f);
        return x >= 0 ? r : -r;
    }

    /// Marks that something was drawn. Wayland uses this to know a
    /// buffer needs committing (FLTK's `surface_needs_commit()`); X11
    /// has nothing to do.
    void delegate() onDraw;

    private void drew()
    {
        if (onDraw !is null) onDraw();
    }

    // -- colors ---------------------------------------------------------

    override void color(Color c)
    {
        import fl.draw : colorToRgb8;
        color_ = c;
        ubyte r, g, b;
        colorToRgb8(c, r, g, b);
        cairo_set_source_rgb(cairo_, r / 255.0, g / 255.0, b / 255.0);
    }

    // -- rectangles and lines ------------------------------------------

    /**
     * Fills whole device pixels `[xs, xs + ws) x [ys, ys + hs)`.
     *
     * Filled rectangles, thin solid horizontal/vertical lines and
     * rectangle outlines are drawn on whole device pixels whose edges
     * are rounded down (`scaledFloor()`), as on the Xlib path, rather
     * than where the scale puts them as FLTK's Cairo driver does. The
     * clip, `fl.draw.fl_scroll()`'s `XCopyArea()` and the double
     * buffer's copy all round down; an edge Cairo rounded to the
     * nearest pixel instead would leave a row or column unpainted at
     * fractional scales such as 110% and 133%.
     */
    private void fillDevice(int xs, int ys, int ws, int hs)
    {
        if (ws <= 0 || hs <= 0) return;
        cairo_matrix_t m;
        cairo_get_matrix(cairo_, &m);
        cairo_identity_matrix(cairo_);
        cairo_translate(cairo_, offsetX_, offsetY_);
        cairo_rectangle(cairo_, xs, ys, ws, hs);
        cairo_set_antialias(cairo_, CAIRO_ANTIALIAS_NONE);
        cairo_fill(cairo_);
        cairo_set_antialias(cairo_, CAIRO_ANTIALIAS_DEFAULT);
        cairo_set_matrix(cairo_, &m);
    }

    /// `fillDevice()` for the FLTK-unit rectangle `(x, y, w, h)`.
    private void fillSnapped(int x, int y, int w, int h)
    {
        int xs = scaledFloor(x), ys = scaledFloor(y);
        fillDevice(xs, ys, scaledFloor(x + w) - xs, scaledFloor(y + h) - ys);
    }

    override void rectf(int x, int y, int w, int h)
    {
        if (w < 1 || h < 1) return;
        prepare();
        fillSnapped(x, y, w, h);
        drew();
    }

    override void rect(int x, int y, int w, int h)
    {
        if (w <= 1 || h <= 1) return;
        prepare();
        if (hairline_)
        {
            fillSnapped(x, y, w, 1);
            fillSnapped(x, y + h - 1, w, 1);
            fillSnapped(x, y + 1, 1, h - 2);
            fillSnapped(x + w - 1, y + 1, 1, h - 2);
            drew();
            return;
        }
        cairo_rectangle(cairo_, x, y, w - 1, h - 1);
        if (lineStyle_ == lineSolid) cairo_set_antialias(cairo_, CAIRO_ANTIALIAS_NONE);
        cairo_stroke(cairo_);
        if (lineStyle_ == lineSolid) cairo_set_antialias(cairo_, CAIRO_ANTIALIAS_DEFAULT);
        drew();
    }

    /// FLTK's `need_antialias_none()`: thin solid lines are drawn
    /// without antialiasing so they stay one crisp pixel wide.
    private bool needAntialiasNone()
    {
        cairo_matrix_t m;
        cairo_get_matrix(cairo_, &m);
        double width = cairo_get_line_width(cairo_) * m.xx;
        bool needIt = lineStyle_ == lineSolid && width < 1.5;
        if (needIt) cairo_set_antialias(cairo_, CAIRO_ANTIALIAS_NONE);
        return needIt;
    }

    override void line(int x1, int y1, int x2, int y2)
    {
        prepare();
        cairo_new_path(cairo_);
        cairo_move_to(cairo_, x1, y1);
        cairo_line_to(cairo_, x2, y2);
        bool needIt = needAntialiasNone();
        cairo_stroke(cairo_);
        if (needIt) cairo_set_antialias(cairo_, CAIRO_ANTIALIAS_DEFAULT);
        drew();
    }

    override void xyline(int x, int y, int x1)
    {
        prepare();
        if (hairline_)
        {
            // as fl.draw's Xlib fl_xyline(): both end pixels included
            int ys = scaledFloor(y), hs = scaledFloor(y + 1) - ys;
            int xs = scaledFloor(x < x1 ? x : x1);
            int xe = scaledFloor((x < x1 ? x1 : x) + 1);
            fillDevice(xs, ys, xe - xs, hs < 1 ? 1 : hs);
            drew();
            return;
        }
        cairo_move_to(cairo_, x, y);
        cairo_line_to(cairo_, x1, y);
        cairo_set_antialias(cairo_, CAIRO_ANTIALIAS_NONE);
        cairo_stroke(cairo_);
        cairo_set_antialias(cairo_, CAIRO_ANTIALIAS_DEFAULT);
        drew();
    }

    override void yxline(int x, int y, int y1)
    {
        prepare();
        if (hairline_)
        {
            int xs = scaledFloor(x), ws = scaledFloor(x + 1) - xs;
            int ys = scaledFloor(y < y1 ? y : y1);
            int ye = scaledFloor((y < y1 ? y1 : y) + 1);
            fillDevice(xs, ys, ws < 1 ? 1 : ws, ye - ys);
            drew();
            return;
        }
        cairo_move_to(cairo_, x, y);
        cairo_line_to(cairo_, x, y1);
        cairo_set_antialias(cairo_, CAIRO_ANTIALIAS_NONE);
        cairo_stroke(cairo_);
        cairo_set_antialias(cairo_, CAIRO_ANTIALIAS_DEFAULT);
        drew();
    }

    /// True when the 4 points make an axis-aligned rectangle, which
    /// FLTK draws without antialiasing.
    private static bool isAxisAligned(int x0, int y0, int x1, int y1, int x2, int y2, int x3, int y3)
    {
        return (y0 == y1 && x1 == x2 && y2 == y3 && x3 == x0)
            || (x0 == x1 && y1 == y2 && x2 == x3 && y3 == y0);
    }

    override void loop(int x0, int y0, int x1, int y1, int x2, int y2)
    {
        prepare();
        cairo_save(cairo_);
        cairo_new_path(cairo_);
        cairo_move_to(cairo_, x0, y0);
        cairo_line_to(cairo_, x1, y1);
        cairo_line_to(cairo_, x2, y2);
        cairo_close_path(cairo_);
        cairo_stroke(cairo_);
        cairo_restore(cairo_);
        drew();
    }

    override void loop(int x0, int y0, int x1, int y1, int x2, int y2, int x3, int y3)
    {
        prepare();
        cairo_save(cairo_);
        cairo_new_path(cairo_);
        cairo_move_to(cairo_, x0, y0);
        cairo_line_to(cairo_, x1, y1);
        cairo_line_to(cairo_, x2, y2);
        cairo_line_to(cairo_, x3, y3);
        cairo_close_path(cairo_);
        if (isAxisAligned(x0, y0, x1, y1, x2, y2, x3, y3))
            cairo_set_antialias(cairo_, CAIRO_ANTIALIAS_NONE);
        cairo_stroke(cairo_);
        cairo_restore(cairo_);
        drew();
    }

    override void polygon(int x0, int y0, int x1, int y1, int x2, int y2)
    {
        prepare();
        cairo_save(cairo_);
        cairo_new_path(cairo_);
        cairo_move_to(cairo_, x0, y0);
        cairo_line_to(cairo_, x1, y1);
        cairo_line_to(cairo_, x2, y2);
        cairo_close_path(cairo_);
        cairo_fill(cairo_);
        cairo_restore(cairo_);
        drew();
    }

    override void polygon(int x0, int y0, int x1, int y1, int x2, int y2, int x3, int y3)
    {
        prepare();
        cairo_save(cairo_);
        cairo_new_path(cairo_);
        cairo_move_to(cairo_, x0, y0);
        cairo_line_to(cairo_, x1, y1);
        cairo_line_to(cairo_, x2, y2);
        cairo_line_to(cairo_, x3, y3);
        cairo_close_path(cairo_);
        if (isAxisAligned(x0, y0, x1, y1, x2, y2, x3, y3))
            cairo_set_antialias(cairo_, CAIRO_ANTIALIAS_NONE);
        cairo_fill(cairo_);
        cairo_restore(cairo_);
        drew();
    }

    // FLTK's `Fl_Graphics_Driver::dashes_flat`/`dashes_cap`, indexed by
    // the line style's low byte; -1 ends a pattern.
    private static immutable int[7][5] dashesFlat = [
        [-1, 0, 0, 0, 0, 0, 0],
        [3, 1, -1, 0, 0, 0, 0],
        [1, 1, -1, 0, 0, 0, 0],
        [3, 1, 1, 1, -1, 0, 0],
        [3, 1, 1, 1, 1, 1, -1],
    ];
    private static immutable double[7][5] dashesCap = [
        [-1, 0, 0, 0, 0, 0, 0],
        [2, 2, -1, 0, 0, 0, 0],
        [0.01, 1.99, -1, 0, 0, 0, 0],
        [2, 2, 0.01, 1.99, -1, 0, 0],
        [2, 2, 0.01, 1.99, 0.01, 1.99, -1],
    ];

    override void lineStyle(int style, int width, const(ubyte)[] dashes)
    {
        prepare();
        lineStyle_ = style;
        hairline_ = style == 0 && dashes.length == 0 && width <= 1;
        bool width0 = false;
        if (width == 0)
        {
            width = 1; // for screen drawing compatibility
            width0 = true;
        }
        cairo_set_line_width(cairo_, width);

        if (style == 0 && dashes.length == 0 && width0) // system lines
            style = capSquare;

        int cap = style & 0xf00;
        cairo_line_cap_t cCap = cap == capSquare ? CAIRO_LINE_CAP_SQUARE
            : cap == capRound ? CAIRO_LINE_CAP_ROUND : CAIRO_LINE_CAP_BUTT;
        cairo_set_line_cap(cairo_, cCap);

        int join = style & 0xf000;
        cairo_line_join_t cJoin = join == joinRound ? CAIRO_LINE_JOIN_ROUND
            : join == joinBevel ? CAIRO_LINE_JOIN_BEVEL : CAIRO_LINE_JOIN_MITER;
        cairo_set_line_join(cairo_, cJoin);

        double[] d;
        if (dashes.length)
        {
            foreach (b; dashes)
            {
                if (b == 0) break;
                d ~= b;
            }
        }
        else if ((style & 0xff) && (style & 0xff) < 5)
        {
            if (style & 0x200) // round and square caps: dash lengths are adjusted
            {
                foreach (v; dashesCap[style & 0xff])
                {
                    if (v < 0) break;
                    d ~= width * v;
                }
            }
            else
            {
                foreach (v; dashesFlat[style & 0xff])
                {
                    if (v < 0) break;
                    d ~= width * v;
                }
            }
        }
        cairo_set_dash(cairo_, d.ptr, cast(int) d.length, 0);
        cairo_set_antialias(cairo_, d.length ? CAIRO_ANTIALIAS_NONE : CAIRO_ANTIALIAS_DEFAULT);
    }

    // -- clipping -------------------------------------------------------

    /// `fl.draw.pushClip()` passes the already-intersected rectangle,
    /// which `setClip()` makes the whole clip; `fl.draw.restoreClip()`
    /// then calls `setClip()` again with the same rectangle.
    override void pushClip(int x, int y, int w, int h)
    {
        setClip(true, x, y, w, h);
    }

    /// Nothing to undo: `fl.draw.popClip()` follows with `setClip()`
    /// for the new top of its clip stack.
    override void popClip() { }

    // -- arcs and pies --------------------------------------------------

    override void arc(int x, int y, int w, int h, double a1, double a2)
    {
        if (w <= 1 || h <= 1) return;
        prepare();
        cairo_save(cairo_);
        cairo_new_path(cairo_);
        cairo_translate(cairo_, x + w / 2.0 - 0.5, y + h / 2.0 - 0.5);
        cairo_scale(cairo_, (w - 1) / 2.0, (h - 1) / 2.0);
        arcPath(a2, a1);
        // Stroke after restoring the matrix (the path survives it), so
        // the ellipse's scale doesn't also stretch the line width
        // (FLTK's end_line() after undoing its scale).
        cairo_restore(cairo_);
        cairo_stroke(cairo_);
        drew();
    }

    override void pie(int x, int y, int w, int h, double a1, double a2)
    {
        prepare();
        cairo_save(cairo_);
        cairo_new_path(cairo_);
        cairo_translate(cairo_, x + w / 2.0 - 0.5, y + h / 2.0 - 0.5);
        cairo_scale(cairo_, w / 2.0, h / 2.0);
        cairo_move_to(cairo_, 0, 0);
        arcPath(a2, a1);
        cairo_close_path(cairo_);
        cairo_fill(cairo_);
        cairo_restore(cairo_);
        drew();
    }

    /// FLTK's `arc(double x, double y, double r, double start, double a)`
    /// on the unit circle at the origin, appended to the current path.
    /// Angles are degrees counterclockwise, as in FLTK.
    private void arcPath(double start, double a)
    {
        if (start > a)
            cairo_arc(cairo_, 0, 0, 1, -start * PI / 180, -a * PI / 180);
        else
            cairo_arc_negative(cairo_, 0, 0, 1, -start * PI / 180, -a * PI / 180);
    }

    // -- vertex paths ---------------------------------------------------

    /**
     * Vertex paths arrive in device pixels (`fl.draw` scales them
     * before rounding to integers), not in FLTK units: FLTK-unit
     * integers would put every vertex on a grid as coarse as the
     * drawing scale. The path is built in device space, shifted by
     * the same half unit as the base matrix, and stroked under the
     * base matrix so line widths still scale.
     */
    override bool wantsUnscaledVertices() const { return false; }

    /// Appends `pts` as one path in device space; leaves the base
    /// matrix in effect for the stroke or fill that follows.
    private void pathFrom(const(Point)[] pts, bool close)
    {
        prepare();
        cairo_save(cairo_);
        cairo_identity_matrix(cairo_);
        cairo_translate(cairo_, offsetX_ + 0.5 * appliedScale_, offsetY_ + 0.5 * appliedScale_);
        cairo_new_path(cairo_);
        foreach (i, p; pts)
        {
            if (i == 0) cairo_move_to(cairo_, p.x, p.y);
            else cairo_line_to(cairo_, p.x, p.y);
        }
        if (close) cairo_close_path(cairo_);
        cairo_restore(cairo_); // the path survives the restore
    }

    /// Ported from `end_points()`: one point-sized square per point,
    /// in device pixels.
    override void endPoints(const(Point)[] pts)
    {
        if (pts.length == 0) return;
        prepare();
        cairo_save(cairo_);
        cairo_identity_matrix(cairo_);
        cairo_translate(cairo_, offsetX_, offsetY_);
        double size = appliedScale_ < 1 ? 1 : appliedScale_;
        foreach (p; pts) cairo_rectangle(cairo_, p.x, p.y, size, size);
        cairo_set_antialias(cairo_, CAIRO_ANTIALIAS_NONE);
        cairo_fill(cairo_);
        cairo_restore(cairo_);
        drew();
    }

    override void endLine(const(Point)[] pts)
    {
        if (pts.length == 0) return;
        pathFrom(pts, false);
        cairo_stroke(cairo_);
        drew();
    }

    override void endLoop(const(Point)[] pts)
    {
        if (pts.length == 0) return;
        pathFrom(pts, true);
        cairo_stroke(cairo_);
        drew();
    }

    override void endPolygon(const(Point)[] pts)
    {
        if (pts.length == 0) return;
        pathFrom(pts, true);
        cairo_fill(cairo_);
        drew();
    }

    override void endComplexPolygon(const(Point)[] pts)
    {
        endPolygon(pts);
    }

    /// Each sub-loop `fl.draw.gap()` made becomes its own closed
    /// sub-path, filled together with the even-odd rule so holes stay
    /// empty -- FLTK's `begin_complex_polygon()`/`gap()` on Cairo start a
    /// new sub-path at each gap the same way.
    override void endComplexPolygonParts(const(Point)[] pts, const(int)[] counts)
    {
        if (pts.length == 0) return;
        prepare();
        cairo_save(cairo_);
        cairo_identity_matrix(cairo_);
        cairo_translate(cairo_, offsetX_ + 0.5 * appliedScale_, offsetY_ + 0.5 * appliedScale_);
        cairo_new_path(cairo_);
        size_t i = 0;
        foreach (n; counts)
        {
            foreach (k; 0 .. n)
            {
                if (i >= pts.length) break;
                if (k == 0) cairo_move_to(cairo_, pts[i].x, pts[i].y);
                else cairo_line_to(cairo_, pts[i].x, pts[i].y);
                i++;
            }
            cairo_close_path(cairo_);
        }
        cairo_restore(cairo_);
        cairo_set_fill_rule(cairo_, CAIRO_FILL_RULE_EVEN_ODD);
        cairo_fill(cairo_);
        cairo_set_fill_rule(cairo_, CAIRO_FILL_RULE_WINDING);
        drew();
    }

    // -- text -----------------------------------------------------------

    /**
     * Selects font `fnum` at `size` FLTK units -- ported from
     * `Fl_Cairo_Graphics_Driver::font()`. `pangoName` is the font's
     * Pango name (see `pangoFontName()`). Pango fonts are sized in
     * pixels here and scaled by the base matrix like everything else,
     * so measurements are in FLTK units at every drawing scale.
     */
    void font(string pangoName, Fontsize size)
    {
        if (size <= 0) return;
        if (pangoContext_ is null)
        {
            pangoContext_ = pango_font_map_create_context(pango_cairo_font_map_get_default());
            pangoLayout_ = pango_layout_new(pangoContext_);
        }
        import std.conv : to;
        string key = pangoName ~ "\0" ~ size.to!string;
        if (font_ !is null && key == fontKey_) return;
        fontKey_ = key;
        if (auto p = key in fontCache_)
            font_ = *p;
        else
            fontCache_[key] = font_ = new FontDescriptor(pangoName, size, pangoContext_);
        pango_context_set_font_description(pangoContext_, font_.fontref);
        pango_layout_context_changed(pangoLayout_);
    }

    /// Whether `font()` has been called yet.
    bool hasFont() const { return font_ !is null; }

    /// Ported from `height()`: the font's line height, rounded up.
    int height()
    {
        if (font_ is null) return 0;
        return cast(int) ceil(font_.lineHeight / cast(float) PANGO_SCALE);
    }

    /// Ported from `descent()`.
    int descent()
    {
        if (font_ is null) return 0;
        return cast(int)(font_.descent / cast(float) PANGO_SCALE + 0.5f);
    }

    private int layoutWidth(const(char)[] str)
    {
        if (str.length == 0) return 0;
        str = utf8Clean(str);
        pango_layout_set_text(pangoLayout_, str.ptr, cast(int) str.length);
        PangoRectangle logical;
        pango_layout_get_extents(pangoLayout_, null, &logical);
        return logical.width;
    }

    /**
     * Ported from `width(const char*, int)`. A single character's width
     * is cached per font, as FLTK does; kerning makes a longer string's
     * width differ from the sum of its characters', so that is measured
     * whole.
     */
    double width(const(char)[] str)
    {
        if (font_ is null) return -1;
        if (str.length == 0) return 0;
        import std.utf : decode, stride, UTFException;
        try
        {
            if (stride(str, 0) == str.length)
            {
                size_t i = 0;
                return width(decode(str, i));
            }
        }
        catch (UTFException) { }
        return layoutWidth(str) / cast(double) PANGO_SCALE;
    }

    /// Ported from `width(unsigned)`: the width of one Unicode
    /// character, cached for the Basic Multilingual Plane.
    double width(dchar c)
    {
        if (font_ is null) return -1;
        uint u = c;
        if (u <= 0xFFFF)
        {
            if (font_.widths.length == 0) font_.widths = new int[][](64);
            auto page = &font_.widths[u >> 10];
            if (page.length == 0)
            {
                *page = new int[](1024);
                (*page)[] = -1;
            }
            else if ((*page)[u & 0x3FF] >= 0)
                return (*page)[u & 0x3FF] / cast(double) PANGO_SCALE;
        }
        import std.utf : encode;
        char[4] buf;
        size_t n = encode(buf, c);
        int w = layoutWidth(buf[0 .. n]);
        if (u <= 0xFFFF) font_.widths[u >> 10][u & 0x3FF] = w;
        return w / cast(double) PANGO_SCALE;
    }

    /// Ported from `text_extents()`: the ink rectangle of `str`, relative
    /// to the pen position on the baseline.
    void textExtents(const(char)[] str, out int dx, out int dy, out int w, out int h)
    {
        if (font_ is null || str.length == 0) return;
        str = utf8Clean(str);
        pango_layout_set_text(pangoLayout_, str.ptr, cast(int) str.length);
        PangoRectangle ink;
        pango_layout_get_extents(pangoLayout_, &ink, null);
        double f = PANGO_SCALE;
        dx = cast(int)(ink.x / f);
        dy = cast(int)((ink.y - font_.ascent) / f);
        w = cast(int) ceil(ink.width / f);
        h = cast(int) ceil(ink.height / f);
    }

    /// Ported from `draw(const char*, int, float, float)`: `str` with
    /// its baseline's left end at `(x, y)`.
    override void draw(const(char)[] str, int nChars, int x, int y)
    {
        if (nChars <= 0 || font_ is null) return;
        if (nChars < str.length) str = str[0 .. nChars];
        prepare();
        cairo_save(cairo_);
        cairo_translate(cairo_, x - 0.5, y - font_.ascent / cast(float) PANGO_SCALE - 0.5);
        str = utf8Clean(str);
        pango_layout_set_text(pangoLayout_, str.ptr, cast(int) str.length);
        pango_cairo_show_layout(cairo_, pangoLayout_);
        cairo_restore(cairo_);
        drew();
    }

    /// Ported from `draw(int rotation, ...)`: rotated `angle` degrees
    /// counterclockwise about `(x, y)`.
    override void draw(int angle, const(char)[] str, int nChars, int x, int y)
    {
        prepare();
        cairo_save(cairo_);
        cairo_translate(cairo_, x, y);
        cairo_rotate(cairo_, -angle * PI / 180);
        draw(str, nChars, 0, 0);
        cairo_restore(cairo_);
    }

    // -- images ---------------------------------------------------------

    private static cairo_user_data_key_t dataKey;

    /// Converts an 8-bit-per-channel buffer to a premultiplied ARGB32
    /// image surface -- ported from `cache(Fl_RGB_Image*)`. `d`/`l`
    /// follow `fl.draw.drawImage()`: a negative `d` steps the pixel
    /// pointer leftwards, a negative `l` steps rows upwards, 0 for `l`
    /// means `w * |d|`.
    private static cairo_surface_t* surfaceFromBuffer(const(ubyte)* buf, int w, int h, int d, int l)
    {
        int ad = d < 0 ? -d : d;
        if (l == 0) l = w * ad;
        int stride = cairo_format_stride_for_width(CAIRO_FORMAT_ARGB32, w);
        auto data = new ubyte[](stride * h);
        foreach (j; 0 .. h)
        {
            auto q = cast(uint*)(data.ptr + j * stride);
            const(ubyte)* rowp = buf + cast(ptrdiff_t) j * l;
            foreach (i; 0 .. w)
            {
                const(ubyte)* p = rowp + cast(ptrdiff_t) i * d;
                uint a = 0xff, r, g, b;
                if (ad >= 3)
                {
                    r = p[0]; g = p[1]; b = p[2];
                    if (ad == 4) a = p[3];
                }
                else
                {
                    r = g = b = p[0];
                    if (ad == 2) a = p[1];
                }
                if (a != 0xff)
                {
                    float f = a / 255.0f;
                    r = cast(ubyte)(r * f);
                    g = cast(ubyte)(g * f);
                    b = cast(ubyte)(b * f);
                }
                q[i] = a << 24 | r << 16 | g << 8 | b;
            }
        }
        return surfaceOwning(data, CAIRO_FORMAT_ARGB32, w, h, stride);
    }

    /// An image surface over GC-allocated `data`, kept alive until Cairo
    /// destroys the surface.
    private static cairo_surface_t* surfaceOwning(ubyte[] data, cairo_format_t fmt, int w, int h, int stride)
    {
        import core.memory : GC;
        cairo_surface_t* surf = cairo_image_surface_create_for_data(data.ptr, fmt, w, h, stride);
        GC.addRoot(data.ptr);
        cairo_surface_set_user_data(surf, &dataKey, data.ptr, &releaseRoot);
        return surf;
    }

    private extern (C) static void releaseRoot(void* p) nothrow
    {
        import core.memory : GC;
        GC.removeRoot(p);
    }

    /**
     * Paints `surf` (`srcW` x `srcH` pixels) into the device-pixel
     * rectangle `(xs, ys, ws, hs)`, scaling it to fit -- the core of
     * FLTK's `draw_cached_pattern_()`. `originX`/`originY` place the
     * image's top-left corner when it is drawn unscaled and cropped.
     * With `asMask`, the current color is painted through the surface's
     * alpha instead.
     */
    private void paintSurface(cairo_surface_t* surf, int srcW, int srcH,
        int xs, int ys, int ws, int hs, int originX, int originY, bool scaleToFit, bool asMask)
    {
        if (ws <= 0 || hs <= 0) return;
        prepare();
        cairo_save(cairo_);
        cairo_identity_matrix(cairo_);
        cairo_translate(cairo_, offsetX_, offsetY_);
        cairo_rectangle(cairo_, xs, ys, ws, hs);
        cairo_set_antialias(cairo_, CAIRO_ANTIALIAS_NONE);
        cairo_clip(cairo_);
        cairo_set_antialias(cairo_, CAIRO_ANTIALIAS_DEFAULT);
        cairo_pattern_t* pat = cairo_pattern_create_for_surface(surf);
        cairo_matrix_t m;
        if (scaleToFit)
        {
            cairo_matrix_init_scale(&m, srcW / cast(double) ws, srcH / cast(double) hs);
            cairo_matrix_translate(&m, -xs, -ys);
            if (ws != srcW || hs != srcH)
            {
                bool smooth = fabs(ws / cast(double) srcW - 1) > 0.02 || fabs(hs / cast(double) srcH - 1) > 0.02;
                cairo_pattern_set_filter(pat, smooth ? CAIRO_FILTER_GOOD : CAIRO_FILTER_FAST);
                cairo_pattern_set_extend(pat, CAIRO_EXTEND_PAD);
            }
        }
        else
            cairo_matrix_init_translate(&m, -originX, -originY);
        cairo_pattern_set_matrix(pat, &m);
        if (asMask)
            cairo_mask(cairo_, pat);
        else
        {
            cairo_set_source(cairo_, pat);
            cairo_paint(cairo_);
        }
        cairo_pattern_destroy(pat);
        cairo_restore(cairo_);
        drew();
    }

    /// `w` x `h` pixels from `buf`, stretched over the FLTK-unit box
    /// `(x, y, w, h)` -- ported from `draw_image()`.
    override void drawImage(const(ubyte)* buf, int x, int y, int w, int h, int d, int l)
    {
        if (buf is null || w <= 0 || h <= 0 || d == 0) return;
        prepare();
        cairo_surface_t* surf = surfaceFromBuffer(buf, w, h, d, l);
        int xs = scaledFloor(x), ys = scaledFloor(y);
        paintSurface(surf, w, h, xs, ys, scaledFloor(x + w) - xs, scaledFloor(y + h) - ys,
            0, 0, true, false);
        cairo_surface_destroy(surf);
    }

    /// `drawW` x `drawH` pixels from `buf`, already at device size,
    /// drawn one-to-one with their top-left corner at FLTK-unit `(x, y)`.
    override void drawImageFixed(const(ubyte)* buf, int drawW, int drawH, int drawL, int d, int x, int y)
    {
        if (buf is null || drawW <= 0 || drawH <= 0 || d == 0) return;
        prepare();
        cairo_surface_t* surf = surfaceFromBuffer(buf, drawW, drawH, d, drawL);
        int xs = scaledFloor(x), ys = scaledFloor(y);
        paintSurface(surf, drawW, drawH, xs, ys, drawW, drawH, xs, ys, false, false);
        cairo_surface_destroy(surf);
    }

    /**
     * A 1-bit bitmap (`dataW` x `dataH`, rows of `(dataW + 7) / 8`
     * bytes, least significant bit first), already at device size,
     * painted in the current color into the FLTK-unit box `(x, y, w, h)`
     * with the bitmap's `(cx, cy)` at the box's corner -- ported from
     * `bitmap_to_pattern()` and `draw_fixed(Fl_Bitmap*, ...)`.
     */
    override void drawBitmap(const(ubyte)* bits, int dataW, int dataH, int x, int y, int w, int h, int cx, int cy)
    {
        if (bits is null || dataW <= 0 || dataH <= 0) return;
        prepare();
        int stride = cairo_format_stride_for_width(CAIRO_FORMAT_A1, dataW);
        int rowBytes = (dataW + 7) / 8;
        auto data = new ubyte[](stride * dataH);
        foreach (j; 0 .. dataH)
        {
            const(ubyte)* r = bits + j * rowBytes;
            auto q = cast(uint*)(data.ptr + j * stride);
            foreach (i; 0 .. dataW)
            {
                if (r[i >> 3] & (1 << (i & 7)))
                {
                    version (BigEndian) q[i >> 5] |= 0x80000000u >> (i & 31);
                    else q[i >> 5] |= 1u << (i & 31);
                }
            }
        }
        cairo_surface_t* surf = surfaceOwning(data, CAIRO_FORMAT_A1, dataW, dataH, stride);
        int xs = scaledFloor(x), ys = scaledFloor(y);
        paintSurface(surf, dataW, dataH, xs, ys, scaledFloor(x + w) - xs, scaledFloor(y + h) - ys,
            xs - scaledFloor(cx), ys - scaledFloor(cy), false, true);
        cairo_surface_destroy(surf);
    }

    // -- antialiasing ---------------------------------------------------

    override int antialias()
    {
        return cairo_get_antialias(cairo_) != CAIRO_ANTIALIAS_NONE;
    }

    override void antialias(int state)
    {
        cairo_set_antialias(cairo_, state ? CAIRO_ANTIALIAS_DEFAULT : CAIRO_ANTIALIAS_NONE);
    }
}
