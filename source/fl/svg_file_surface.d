/*
 * Ported from FL/Fl_SVG_File_Surface.H + src/drivers/SVG/
 * Fl_SVG_File_Surface.cxx (FLTK 1.5.0).
 *
 * **Scope (updated 2026-09-22, third pass)**: FLTK's `Fl_SVG_
 * Graphics_Driver` overrides ~35 `Fl_Graphics_Driver` virtuals. This
 * port's `fl.graphics_driver.GraphicsDriver` now covers rect/line/
 * color/polygon, line style (dash/width/cap/join), clipping, arcs/pies,
 * the vertex-path `end_*()` family, plain (non-rotated) text, and now
 * images too (`drawImage()`/`drawBitmap()`, base64-PNG `<image>`
 * elements -- see those two overrides' own doc comments for the real,
 * documented simplifications vs. FLTK: no `<defs>`/`<use>` reuse
 * caching, PNG only, no JPEG). `SvgGraphicsDriver` below implements
 * exactly that surface; rotated text is the one primitive family left.
 *
 * **`circle()`/`fl_arc(double,...)` need no driver method at all**,
 * unlike FLTK's own `Fl_Graphics_Driver::circle()`/`arc(double,...)`
 * virtuals: in this port those two are pure vertex-path *compositions*
 * (they call `transformedVertex()`/`appendVertexPoint()` in a loop,
 * only usable inside a `beginPolygon()`/`beginLoop()` bracket --
 * see `fl.draw.circle()`'s own doc comment), so they route correctly
 * for free once `endPolygon()`/`endLoop()` dispatch. Only the *standalone*
 * `fl_arc(int,...)`/`fl_pie(int,...)` overloads (used outside any
 * begin/end bracket, e.g. by `fl.dial`'s `fillDial` mode) are genuine
 * `fl.draw` leaves and need a real `arc()`/`pie()` driver method.
 *
 * **`SvgFileSurface.draw(Widget)`/`drawDecoratedWindow()` (inherited
 * from `fl.widget_surface.WidgetSurface`) are safe on a general widget
 * now** -- images were the one remaining real gap (a real widget's
 * `draw()` commonly draws one, e.g. an icon/label image), and
 * `drawImage()`/`drawBitmap()` are both real now (see above). Rotated
 * text (`fl.draw.fl_draw(int angle,...)`) still falls through to
 * `GraphicsDriver.draw(int,...)`'s own non-abstract default (plain,
 * unrotated `draw()`) rather than mixing real window pixels in the way
 * an undispatched primitive used to -- a cosmetic gap (text renders,
 * just not rotated), not a correctness one.
 *
 * Also simplified relative to FLTK: no display-scale-factor
 * wrapping (`<g transform="scale(...)">`) -- `fl.core.screenScale(int)`
 * is real, but this surface doesn't consult it yet, same simplification
 * already made by
 * `fl.image_surface.ImageSurface`'s ignored `highRes` parameter -- so
 * only one `<g transform="translate(0,0)">` wrapper exists here, not
 * FLTK's nested pair, and `close()` emits one closing `</g>`, not
 * two.
 */
module fl.svg_file_surface;

import std.stdio : File;
import std.math : PI, cos, sin, abs;
import std.array : appender, array;
import std.algorithm : map;
import std.format : formattedWrite;
import fl.enumerations : Color;
import fl.graphics_driver : GraphicsDriver, Point;
import fl.widget_surface : WidgetSurface;
import fldraw = fl.draw;

/**
 * Ported (the slice covered by `fl.graphics_driver.GraphicsDriver` --
 * see this module's own top comment) from `Fl_SVG_Graphics_Driver`
 * (`src/drivers/SVG/Fl_SVG_File_Surface.cxx`). Each override emits one
 * SVG element per call, in the current `color()`, matching FLTK's
 * own element shapes (a stroked `<rect>` for `rect()`, a filled one for
 * `rectf()`, `<line>` for the axis-aligned leaves, a closed `<path>`
 * for `polygon()`/the vertex-path `end_*()` family, `<text>` for
 * `draw()`).
 */
class SvgGraphicsDriver : GraphicsDriver
{
    private File file_;
    private ubyte r_, g_, b_;

    /// Line style state, set by `lineStyle()` and consulted by
    /// `rect()`/`line()`/`endLine()`/`endLoop()`/`arc()`/`pie()` --
    /// this class's own equivalent of the real X11 GC's persistent
    /// line-attribute state the native path relies on (`fl.draw`
    /// itself tracks none of this centrally, see `lineStyle()`'s
    /// own "DELIBERATE SIMPLIFICATION" note -- each caller is
    /// responsible for restoring `lineSolid`/width 0 when done, and
    /// this driver just remembers whatever was set last, same as the
    /// GC would).
    private int lineWidth_ = 1;
    private string linecap_ = "butt";
    private string linejoin_ = "miter";
    /// Dash lengths in absolute pixel units at scale 1 (empty = solid).
    /// Kept as numbers, not a pre-formatted string, so `arc()`/`pie()`
    /// can rescale them into the local unit-circle coordinate space
    /// their own `<g transform="... scale(...)">` wrapper uses (see
    /// `dashArrayString()`'s own doc comment) -- matching FLTK's
    /// own `compute_dasharray(scale, ...)` recomputation for exactly
    /// this case.
    private int[] dashLengths_;

    /// Clip nesting depth, used only to generate distinct SVG element
    /// IDs (`FLclip0`, `FLclip1`, ...) -- ported from `Fl_SVG_Graphics_
    /// Driver::clip_count_`. Unlike FLTK, this class keeps no
    /// separate clip-rectangle stack of its own: `fl.draw`'s own
    /// `clipStack_` already tracks nesting correctly and only calls
    /// `pushClip()`/`popClip()` here in matching, balanced pairs (see
    /// `fl.draw.ClipEntry.driverNotified`'s own doc comment) -- an SVG
    /// `<g clip-path="...">` is *itself* already properly nested by
    /// construction as long as opens/closes balance, so there's
    /// nothing else to track.
    private int clipCount_;

    this(File f)
    {
        file_ = f;
    }

    /// The underlying file this driver writes SVG elements to. Ported
    /// from `Fl_SVG_Graphics_Driver::file()`.
    File file() { return file_; }

    override void color(Color c)
    {
        fldraw.colorToRgb8(c, r_, g_, b_);
    }

    override void rectf(int x, int y, int w, int h)
    {
        file_.writef("<rect x=\"%d\" y=\"%d\" width=\"%d\" height=\"%d\" fill=\"rgb(%d,%d,%d)\" />\n",
            x, y, w, h, r_, g_, b_);
    }

    override void rect(int x, int y, int w, int h)
    {
        file_.writef(
            "<rect x=\"%d\" y=\"%d\" width=\"%d\" height=\"%d\" fill=\"none\" stroke=\"rgb(%d,%d,%d)\" stroke-width=\"%d\" stroke-dasharray=\"%s\" stroke-linecap=\"%s\" stroke-linejoin=\"%s\" />\n",
            x, y, w - 1, h - 1, r_, g_, b_, lineWidth_, dashArrayString(), linecap_, linejoin_);
    }

    override void line(int x, int y, int x1, int y1)
    {
        file_.writef(
            "<line x1=\"%d\" y1=\"%d\" x2=\"%d\" y2=\"%d\" style=\"stroke:rgb(%d,%d,%d);stroke-width:%d;stroke-linecap:%s;stroke-linejoin:%s;stroke-dasharray:%s\" />\n",
            x, y, x1, y1, r_, g_, b_, lineWidth_, linecap_, linejoin_, dashArrayString());
    }

    /// `fl.draw.fl_xyline(int,int,int)`'s dispatch target -- a plain
    /// horizontal `line()`, matching FLTK (`Fl_Graphics_Driver`
    /// itself has no separate `xyline()`/`yxline()` SVG override;
    /// they're not part of this port's minimal `GraphicsDriver` either,
    /// so this class supplies the equivalent directly).
    override void xyline(int x, int y, int x1)
    {
        line(x, y, x1, y);
    }

    /// See `xyline()` above -- the vertical counterpart.
    override void yxline(int x, int y, int y1)
    {
        line(x, y, x, y1);
    }

    override void polygon(int x, int y, int x1, int y1, int x2, int y2)
    {
        file_.writef("<path d=\"M %d %d L %d %d L %d %d z\" fill=\"rgb(%d,%d,%d)\" />\n",
            x, y, x1, y1, x2, y2, r_, g_, b_);
    }

    override void polygon(int x, int y, int x1, int y1, int x2, int y2, int x3, int y3)
    {
        file_.writef("<path d=\"M %d %d L %d %d L %d %d L %d %d z\" fill=\"rgb(%d,%d,%d)\" />\n",
            x, y, x1, y1, x2, y2, x3, y3, r_, g_, b_);
    }

    /// Ported from `Fl_SVG_Graphics_Driver::line_style()`, adapted to
    /// this port's simpler `lineStyle()` bit layout (`(style>>8)&3`
    /// for cap, `(style>>12)&3` for join -- see `fl.draw.fl_line_
    /// style()`'s own body, which this table mirrors exactly) rather
    /// than FLTK's own `FL_CAP_*`/`FL_JOIN_*` bitmask comparisons.
    /// Reuses `fl.draw.dashPatternFor()` for the auto-dash-from-style
    /// case instead of re-deriving FLTK's own separate
    /// `compute_dasharray()` math (see that function's own doc comment).
    override void lineStyle(int style, int width, const(ubyte)[] dashes)
    {
        lineWidth_ = width == 0 ? 1 : (width > 0 ? width : -width);
        static immutable string[4] capNames = ["butt", "butt", "round", "square"];
        static immutable string[4] joinNames = ["miter", "miter", "round", "bevel"];
        linecap_ = capNames[(style >> 8) & 3];
        linejoin_ = joinNames[(style >> 12) & 3];

        const(ubyte)[] d = dashes;
        if (d.length == 0 && (style & 0xff) != 0)
            d = fldraw.dashPatternFor(style, lineWidth_);
        dashLengths_ = d.map!(v => cast(int) v).array;
    }

    /// Formats `dashLengths_` as an SVG `stroke-dasharray` value,
    /// `"none"` if solid. `scale`, if not 1, divides each length first --
    /// used by `arc()`/`pie()` to express the dash pattern in the local,
    /// pre-`<g transform="scale(...)">` unit-circle coordinate space
    /// they draw in (matching FLTK's own `compute_dasharray(scale,
    /// user_dash_array_)`/`compute_dasharray(1., ...)` recompute-then-
    /// restore pair around `arc_pie()`) -- `line()`/`rect()` call this
    /// with the default `scale = 1` (their own coordinates are already
    /// absolute pixels, no wrapping transform to compensate for).
    private string dashArrayString(double scale = 1.0)
    {
        if (dashLengths_.length == 0) return "none";
        auto app = appender!string;
        foreach (i, v; dashLengths_)
        {
            if (i) app ~= ",";
            formattedWrite(app, "%g", v / scale);
        }
        return app.data;
    }

    override void pushClip(int x, int y, int w, int h)
    {
        import std.conv : to;

        string id = "FLclip" ~ clipCount_.to!string;
        clipCount_++;
        file_.writef(
            "<clipPath id=\"%s\"><rect x=\"%d\" y=\"%d\" width=\"%d\" height=\"%d\"/></clipPath><g clip-path=\"url(#%s)\">\n",
            id, x, y, w, h, id);
    }

    override void popClip()
    {
        file_.writef("</g>\n");
    }

    override void arc(int x, int y, int w, int h, double a1, double a2)
    {
        arcPie('A', x, y, w, h, a1, a2);
    }

    override void pie(int x, int y, int w, int h, double a1, double a2)
    {
        arcPie('P', x, y, w, h, a1, a2);
    }

    /// Ported from `Fl_SVG_Graphics_Driver::arc_pie()`. Draws into a
    /// local unit-circle coordinate space via a `<g transform=
    /// "translate(cx,cy) scale(sx,sy)">` wrapper (an ellipse becomes a
    /// plain circle of radius 0.5 once uniformly stretched by sx/sy),
    /// which is why `lineWidth_`/the dash array must be rescaled by
    /// `(sx+sy)/2` first -- see `dashArrayString()`'s own doc comment.
    /// `AorP` selects an outline-only `<circle>`/`<path arc>` ('A') vs.
    /// a filled pie wedge closed back through the center ('P'), matching
    /// FLTK's own single shared helper for `arc()`/`pie()`.
    private void arcPie(char AorP, int x, int y, int w, int h, double a1, double a2)
    {
        if (w <= 0 || h <= 0) return;
        bool full = abs(a1 - a2) == 360;
        double a1r = (-a1) / 180.0 * PI;
        double a2r = (-a2) / 180.0 * PI;
        double cx = x + 0.5 * w;
        double cy = y + 0.5 * h - 0.5;
        double r = (w != h) ? 0.5 : (w + h) * 0.25 - 0.5;
        double sx, sy;
        if (w != h) { sx = w - 1; sy = h - 1; }
        else { sx = sy = 2 * r; }
        double scale = (sx + sy) / 2;
        double strokeWidth = scale != 0 ? lineWidth_ / scale : lineWidth_;

        file_.writef("<g transform=\"translate(%g,%g) scale(%g,%g)\">\n", cx, cy, sx, sy);
        if (full)
        {
            file_.writef("<circle cx=\"0\" cy=\"0\" r=\"0.5\" style=\"fill");
            if (AorP == 'A')
                file_.writef(":none;stroke-width:%g;stroke-linecap:%s;stroke-dasharray:%s;stroke",
                    strokeWidth, linecap_, dashArrayString(scale));
        }
        else
        {
            double x1 = 0.5 * cos(a1r), y1 = 0.5 * sin(a1r);
            double x2 = 0.5 * cos(a2r), y2 = 0.5 * sin(a2r);
            int fA = abs(a2r - a1r) > PI ? 1 : 0;
            if (AorP == 'A')
                file_.writef(
                    "<path d=\"M %g,%g A 0.5,0.5 0 %d,0 %g,%g\" style=\"fill:none;stroke-width:%g;stroke-linecap:%s;stroke-dasharray:%s;stroke",
                    x1, y1, fA, x2, y2, strokeWidth, linecap_, dashArrayString(scale));
            else
                file_.writef("<path d=\"M 0,0 L %g,%g A 0.5,0.5 0 %d,0 %g,%g z\" style=\"fill",
                    x1, y1, fA, x2, y2);
        }
        file_.writef(":rgb(%d,%d,%d)\"/></g>\n", r_, g_, b_);
    }

    override void endPoints(const(Point)[] pts)
    {
        foreach (p; pts)
            file_.writef("<path d=\"M %d %d L %d %d\" fill=\"none\" stroke=\"rgb(%d,%d,%d)\" stroke-width=\"%d\" />\n",
                p.x, p.y, p.x, p.y, r_, g_, b_, lineWidth_);
    }

    override void endLine(const(Point)[] pts)
    {
        if (pts.length == 0) return;
        file_.writef(
            "<path d=\"%s\" fill=\"none\" stroke=\"rgb(%d,%d,%d)\" stroke-width=\"%d\" stroke-dasharray=\"%s\" stroke-linecap=\"%s\" stroke-linejoin=\"%s\" />\n",
            pathData(pts), r_, g_, b_, lineWidth_, dashArrayString(), linecap_, linejoin_);
    }

    /// **Not part of FLTK's own override list** -- see
    /// `GraphicsDriver.endLoop()`'s own doc comment. A reasonable,
    /// not-FLTK-sourced choice: `fl.draw.endLoop()` already
    /// re-closes the point list (re-appends the start point) before
    /// dispatching here, so this is just a stroked path through the
    /// same points `endLine()` would draw -- matching what the native
    /// `XDrawLines()` path actually draws for a "loop" (an outline, not
    /// a fill).
    override void endLoop(const(Point)[] pts)
    {
        endLine(pts);
    }

    override void endPolygon(const(Point)[] pts)
    {
        polygonPath(pts);
    }

    override void endComplexPolygon(const(Point)[] pts)
    {
        polygonPath(pts);
    }

    /// An SVG document has no "screen" to be device-pixel-dense
    /// relative to -- same reasoning as `PostscriptGraphicsDriver.
    /// wantsUnscaledVertices()`'s own doc comment (FLTK has no
    /// dedicated SVG graphics-driver class, but its output shares the
    /// same document-coordinate-space contract as PostScript's, not a
    /// screen's device-pixel one). See `GraphicsDriver.
    /// wantsUnscaledVertices()`'s own doc comment for the full story.
    override bool wantsUnscaledVertices() const { return true; }

    private string pathData(const(Point)[] pts)
    {
        auto app = appender!string;
        formattedWrite(app, "M %d %d", pts[0].x, pts[0].y);
        foreach (p; pts[1 .. $]) formattedWrite(app, " L %d %d", p.x, p.y);
        return app.data;
    }

    private void polygonPath(const(Point)[] pts)
    {
        if (pts.length == 0) return;
        file_.writef("<path d=\"%s z\" fill=\"rgb(%d,%d,%d)\" />\n", pathData(pts), r_, g_, b_);
    }

    /**
     * Ported from `Fl_SVG_Graphics_Driver::draw()`/`font_()`. Reads the
     * *current* font/size directly from `fl.draw.fl_font()`/`fl_size()`
     * at draw time (both always real/undispatched, see `GraphicsDriver`'s
     * own doc comment) rather than caching a family/bold/style string at
     * `font()`-call time the way FLTK does -- this port's minimal
     * `GraphicsDriver` has no `font()` dispatch hook at all (native
     * `fl_font()` already has to run unconditionally to keep real Xft
     * metrics valid, so there's nothing to intercept), so recomputing
     * the mapping here, once per `draw()` call, is simpler than adding
     * one just to cache it. Same family/bold/italic-vs-oblique mapping
     * as FLTK's own `font_()` (`face/4` selects Helvetica/Courier/
     * Times, `face%4`'s bits select bold/italic -- see `fl.enumerations.
     * Font`'s own doc comment for why this numbering is safe to rely on).
     * `textLength` comes from `fl.draw.width()`, the same real,
     * undispatched metric FLTK's own `width()` override delegates to
     * the display driver for.
     */
    override void draw(const(char)[] str, int nChars, int x, int y)
    {
        auto face = fldraw.fl_font();
        auto size = fldraw.fl_size();
        int famNum = face / 4;
        string family = famNum == 0 ? "Helvetica" : (famNum == 1 ? "Courier" : "Times");
        int modulo = face % 4;
        bool useBold = modulo == 1 || modulo == 3;
        bool useItalic = modulo >= 2;
        string boldAttr = useBold ? " font-weight=\"bold\"" : "";
        string styleAttr = useItalic
            ? (famNum != 2 ? " font-style=\"oblique\"" : " font-style=\"italic\"") : "";
        int textLen = cast(int) fldraw.width(str[0 .. nChars]);

        file_.writef(
            "<text x=\"%d\" y=\"%d\" font-family=\"%s\"%s%s font-size=\"%d\" xml:space=\"preserve\" fill=\"rgb(%d,%d,%d)\" textLength=\"%d\">",
            x, y, family, boldAttr, styleAttr, size, r_, g_, b_, textLen);
        foreach (c; str[0 .. nChars])
        {
            if (c == '&') file_.writef("&amp;");
            else if (c == '<') file_.writef("&lt;");
            else if (c == '>') file_.writef("&gt;");
            else file_.writef("%c", c);
        }
        file_.writef("</text>\n");
    }

    /**
     * Draws `str` at `(x,y)`, rotated `angle` degrees counterclockwise.
     * Ported from `Fl_SVG_Graphics_Driver::draw(int, const char*, int,
     * int, int)` (`src/drivers/SVG/Fl_SVG_File_Surface.cxx`) -- wraps
     * the plain 3-arg `draw()` above in an SVG `<g>` group with a
     * `translate(x,y) rotate(-angle)` transform (SVG rotates clockwise
     * for positive angles, opposite of `fl_draw()`'s own counterclockwise
     * convention, hence the negation, matching FLTK exactly), then
     * draws the text at the now-local origin `(0,0)`. This is one of the
     * two overriders `GraphicsDriver.draw(int,...)`'s own doc comment
     * anticipates (SVG's `transform="rotate()"`, PostScript's native
     * `rotate` operator) -- unlike this port's screen/offscreen
     * Xft-backed text path, SVG output needs no display connection or
     * font-shaping library to rotate text, so this was reachable
     * immediately once the dispatch hook itself existed.
     */
    override void draw(int angle, const(char)[] str, int nChars, int x, int y)
    {
        file_.writef("<g transform=\"translate(%d,%d) rotate(%d)\">", x, y, -angle);
        draw(str, nChars, 0, 0);
        file_.writef("</g>\n");
    }

    /**
     * Draws an 8-bit-per-channel image as an embedded base64-PNG
     * `<image>` element. Ported from `Fl_SVG_Graphics_Driver::
     * draw_image()` (`src/drivers/SVG/Fl_SVG_File_Surface.cxx`), which
     * FLTK builds by wrapping `buf` in a temporary `Fl_RGB_Image`
     * and re-entering `draw_rgb()`/`define_rgb_png()` polymorphically --
     * this port's `GraphicsDriver.drawImage()` is already the one
     * unified leaf every image draw funnels through (see that method's
     * own doc comment, and `PostscriptGraphicsDriver.drawImage()` for
     * the same collapse already made there), so `emitPngImage()` below
     * just emits the `<image>` element directly instead of re-entering
     * anything.
     *
     * Two deliberate simplifications vs. FLTK:
     *  - No `<defs>`/`<use>` identity-based caching -- FLTK's own
     *    `draw_rgb()` keys a reuse cache on `Fl_Graphics_Driver::
     *    id(rgb)`, a pointer this port's unified `drawImage()` leaf
     *    never receives (its caller already reduced the image to a raw
     *    buffer). Each call emits its own `<image>`; correct, just
     *    larger output for a widget that redraws the same image
     *    repeatedly.
     *  - PNG only, no JPEG variant -- FLTK prefers JPEG for opaque
     *    images and falls back to PNG only when alpha is present
     *    (JPEG has none); PNG alone already covers every `d` here, and
     *    a second embedded-image codec isn't scope this port needs.
     *
     * Negative `d`/`l` (the horizontally-/vertically-flipped source
     * layouts `fl.draw.drawImage()`'s own doc comment documents in
     * full) wrap the `<image>` in one or two `<g transform="...
     * scale(...)">` groups, ported line-for-line from FLTK's own
     * variable reassignment (including emitting the two closing `</g>`
     * tags in FLTK's own fixed textual order rather than strict
     * innermost-first nesting order -- harmless, since neither `<g>`
     * carries a distinguishing id for a parser to mismatch).
     */
    override void drawImage(const(ubyte)* buf, int x, int y, int w, int h, int d, int l)
    {
        if (w <= 0 || h <= 0 || buf is null) return;

        int ad = d < 0 ? -d : d;
        if (d < 0)
        {
            file_.writef("<g transform=\"translate(%d,%d) scale(-1,1)\">\n", x, y);
            buf -= (w - 1) * ad;
            x = -w;
            y = 0;
        }
        int al = l == 0 ? w * ad : (l < 0 ? -l : l);
        if (l < 0)
        {
            file_.writef("<g transform=\"translate(%d,%d) scale(1,-1)\">\n", x, y);
            buf -= (h - 1) * al;
            x = 0;
            y = -h;
        }

        emitPngImage(buf, x, y, w, h, ad, al);

        if (d < 0) file_.writef("</g>\n");
        if (l < 0) file_.writef("</g>\n");
    }

    /**
     * Draws a 1-bit bitmap as an embedded base64-PNG `<image>` element,
     * the current `color()` showing through set bits, fully transparent
     * elsewhere. Ported from `Fl_SVG_Graphics_Driver::draw_bitmap()`,
     * including a real FLTK quirk: the synthesized RGBA image is
     * always built and placed at the bitmap's own native `dataW`x`dataH`
     * size -- `w`/`h` (the requested destination *size*) are genuinely
     * never consulted at all (FLTK's own `rgb->w() == rgb->data_w()`
     * by construction, so its own scale factor `f` always comes out
     * `1`), only `(x-cx, y-cy)` (the destination *position*) is honored.
     * This is a different FLTK function from `Fl_PostScript_
     * Graphics_Driver::draw_bitmap()` (`fl.postscript.
     * PostscriptGraphicsDriver.drawBitmap()`'s own quirk, which *does*
     * scale to `w`/`h` but ignores `cx`/`cy` instead) -- the two drivers
     * genuinely differ FLTK, not a port inconsistency.
     *
     * Bit order matches `fl.bitmap.Bitmap.array` directly (bit 0 =
     * leftmost pixel, LSB-first) -- no reversal needed here, unlike
     * `PostscriptGraphicsDriver.drawBitmap()`'s `swapByte()` (PostScript
     * `imagemask` wants MSB-first; PNG's own row-major byte order has no
     * such requirement).
     */
    override void drawBitmap(const(ubyte)* bits, int dataW, int dataH, int x, int y, int w, int h, int cx, int cy)
    {
        if (dataW <= 0 || dataH <= 0 || bits is null) return;

        auto rgba = new ubyte[dataW * dataH * 4];
        int rowBytes = (dataW + 7) / 8;
        foreach (row; 0 .. dataH)
        {
            const(ubyte)* p = bits + row * rowBytes;
            foreach (byteIdx; 0 .. rowBytes)
            {
                ubyte q = p[byteIdx];
                int last = dataW - 8 * byteIdx;
                if (last > 8) last = 8;
                foreach (k; 0 .. last)
                {
                    if (q & 1)
                    {
                        size_t off = (cast(size_t) row * dataW + byteIdx * 8 + k) * 4;
                        rgba[off] = r_;
                        rgba[off + 1] = g_;
                        rgba[off + 2] = b_;
                        rgba[off + 3] = 255;
                    }
                    q >>= 1;
                }
            }
        }

        emitPngImage(rgba.ptr, x - cx, y - cy, dataW, dataH, 4, dataW * 4);
    }

    /// Shared by `drawImage()`/`drawBitmap()` above: PNG-encodes
    /// `(w,h,d,l)`-shaped pixel data (`fl.png_image.encodePngBytes()`)
    /// and base64-encodes the result (`std.base64.Base64`, a cleaner
    /// choice than transliterating FLTK's own custom streaming
    /// `to_base64()`/`write_by_3()` pair -- this port already holds the
    /// whole PNG in memory by this point, so there's no libpng write
    /// callback to stream through and nothing FLTK's streaming
    /// design was solving here) into a `data:image/png;base64,...`
    /// `<image>` element, matching FLTK's own 80-column line
    /// wrapping (`to_base64()`'s `lline >= 80` check) purely for the
    /// output file's own readability -- not semantically required.
    private void emitPngImage(const(ubyte)* buf, int x, int y, int w, int h, int d, int l)
    {
        import fl.png_image : encodePngBytes;
        import std.base64 : Base64;

        size_t needed = cast(size_t)(h - 1) * l + w * d;
        auto pngBytes = encodePngBytes(buf[0 .. needed], w, h, d, l);
        string b64 = Base64.encode(pngBytes);

        file_.writef("<image x=\"%d\" y=\"%d\" width=\"%d\" height=\"%d\" href=\"data:image/png;base64,\n",
            x, y, w, h);
        for (size_t i = 0; i < b64.length; i += 80)
            file_.writef("%s\n", b64[i .. (i + 80 < b64.length ? i + 80 : b64.length)]);
        file_.writef("\"/>\n");
    }
}

/**
 * Ported from `Fl_SVG_File_Surface` (`FL/Fl_SVG_File_Surface.H`) --
 * see this module's own top comment for what's cut relative to
 * FLTK. Usage mirrors FLTK's own documented example, e.g.:
 * ---
 * auto f = File("out.svg", "w");
 * auto surf = new SvgFileSurface(200, 150, f);
 * SurfaceDevice.pushCurrent(surf);
 * fl_color(red);
 * fl_rectf(10, 10, 60, 40);
 * SurfaceDevice.popCurrent();
 * surf.close(); // the .svg file isn't complete until this runs
 * ---
 */
class SvgFileSurface : WidgetSurface
{
    private int width_, height_;
    private SvgGraphicsDriver svgDriver_;
    private bool closed_;

    /// Ported from `Fl_SVG_File_Surface(int, int, FILE*, int
    /// (*)(FILE*))` -- the `closef` custom-close-function parameter
    /// isn't ported (no caller needs it; `close()`/`~this()` always
    /// `File.close()` the file directly, matching what FLTK's own
    /// default -- `closef == NULL` -- already does). Writes the SVG
    /// header immediately, matching FLTK.
    this(int w, int h, File f)
    {
        auto driver = new SvgGraphicsDriver(f);
        super(driver);
        svgDriver_ = driver;
        width_ = w;
        height_ = h;
        f.writef("<?xml version=\"1.0\" encoding=\"utf-8\" standalone=\"no\"?>\n"
                ~ "<!DOCTYPE svg PUBLIC \"-//W3C//DTD SVG 1.1//EN\" \n"
                ~ "\"http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd\">\n"
                ~ "<svg width=\"%dpx\" height=\"%dpx\" viewBox=\"0 0 %d %d\"\n"
                ~ "xmlns=\"http://www.w3.org/2000/svg\" version=\"1.1\">\n",
            w, h, w, h);
        f.writef("<g transform=\"translate(0,0)\">\n");
    }

    /// Ported from `~Fl_SVG_File_Surface()`: `if (driver()) close();`.
    ~this()
    {
        if (!closed_) close();
    }

    /// The underlying file. Ported from `Fl_SVG_File_Surface::file()`.
    File file() { return svgDriver_.file(); }

    /// Ported from `Fl_SVG_File_Surface::close()`. Closes the one
    /// `<g>` wrapper this port's constructor opened (see this module's
    /// own top comment on why there's only one, not FLTK's nested
    /// pair) and the outer `<svg>`, then closes the file. Safe to call
    /// more than once (matches `~this()`'s own guard).
    int close()
    {
        if (closed_) return 0;
        closed_ = true;
        auto f = svgDriver_.file();
        f.writef("</g></svg>\n");
        f.close();
        return 0;
    }

    /// Ported from `Fl_SVG_File_Surface::translate(int, int)`: opens a
    /// fresh `<g transform="translate(...)">` wrapper -- SVG has no
    /// mutable "current origin" to update in place, so a coordinate
    /// shift becomes a new nested group instead, closed again by
    /// `untranslate()`.
    protected override void translate(int x, int y)
    {
        svgDriver_.file().writef("<g transform=\"translate(%d,%d) \">\n", x, y);
    }

    /// Ported from `Fl_SVG_File_Surface::untranslate()` -- closes the
    /// `<g>` `translate()` opened.
    protected override void untranslate()
    {
        svgDriver_.file().writef("</g>\n");
    }

    /// Ported from `Fl_SVG_File_Surface::origin(int, int)`: closes the
    /// current `<g>` wrapper and opens a new one at the new origin
    /// (same "new nested group, not a mutable offset" reasoning as
    /// `translate()` above), then updates the inherited bookkeeping.
    override void origin(int x, int y)
    {
        svgDriver_.file().writef("</g><g transform=\"translate(%d,%d) \">\n", x, y);
        super.origin(x, y);
    }

    /// Ported from `Fl_SVG_File_Surface::printable_rect()` -- always
    /// succeeds with the surface's own full size, unlike
    /// `WidgetSurface`'s always-failing base.
    override int printableRect(out int w, out int h) const
    {
        w = width_;
        h = height_;
        return 0;
    }
}

unittest
{
    import fl.image_surface : SurfaceDevice;
    import fl.enumerations : red, blue, black, green;
    import graphicsDriver = fl.graphics_driver;
    import std.file : tempDir, exists, remove, readText;
    import std.path : buildPath;
    import std.uuid : randomUUID;
    import std.algorithm : canFind;

    auto path = buildPath(tempDir(), "fldtk-svg-test-" ~ randomUUID().toString() ~ ".svg");
    scope (exit) if (exists(path)) remove(path);

    {
        auto f = File(path, "w");
        auto surf = new SvgFileSurface(200, 150, f);
        SurfaceDevice.pushCurrent(surf);
        assert(graphicsDriver.currentDriver !is null);

        fldraw.fl_color(red);
        fldraw.fl_rectf(10, 10, 60, 40);
        fldraw.fl_color(blue);
        fldraw.fl_rect(80, 10, 60, 40);
        fldraw.fl_color(black);
        fldraw.fl_line(10, 70, 190, 70);
        fldraw.fl_color(green);
        fldraw.fl_polygon(10, 100, 40, 140, 10, 140);

        SurfaceDevice.popCurrent();
        assert(graphicsDriver.currentDriver is null); // back to native

        surf.close();
    }

    assert(exists(path));
    auto text = readText(path);
    assert(text.canFind("<svg"));
    assert(text.canFind("<rect x=\"10\" y=\"10\" width=\"60\" height=\"40\" fill=\"rgb(255,0,0)\""));
    assert(text.canFind("stroke=\"rgb(0,0,255)\""));
    assert(text.canFind("<line x1=\"10\" y1=\"70\" x2=\"190\" y2=\"70\""));
    assert(text.canFind("<path d=\"M 10 100"));
    assert(text.canFind("</svg>"));
}

unittest
{
    // Exercises the 2026-08-11 second-pass primitives: line_style,
    // clipping, arc/pie, the vertex-path end_*() family (via
    // fl_begin_*()/vertex()/fl_end_*()), and plain text.
    import fl.image_surface : SurfaceDevice;
    import fl.enumerations : black, red, helvetica, lineDash;
    import graphicsDriver = fl.graphics_driver;
    import std.file : tempDir, exists, remove, readText;
    import std.path : buildPath;
    import std.uuid : randomUUID;
    import std.algorithm : canFind;

    auto path = buildPath(tempDir(), "fldtk-svg-test2-" ~ randomUUID().toString() ~ ".svg");
    scope (exit) if (exists(path)) remove(path);

    {
        auto f = File(path, "w");
        auto surf = new SvgFileSurface(200, 200, f);
        SurfaceDevice.pushCurrent(surf);

        fldraw.fl_color(black);
        fldraw.lineStyle(lineDash, 2);
        fldraw.fl_line(0, 0, 50, 0);
        fldraw.lineStyle(0); // back to solid, matching fl_line_style()'s own "caller restores" contract

        fldraw.pushClip(0, 0, 100, 100);
        fldraw.popClip();

        fldraw.fl_color(red);
        fldraw.fl_arc(10, 10, 40, 40, 0, 90);
        fldraw.fl_pie(60, 10, 40, 40, 0, 360);

        fldraw.beginPolygon();
        fldraw.vertex(20, 80);
        fldraw.vertex(60, 80);
        fldraw.vertex(40, 110);
        fldraw.endPolygon();

        fldraw.beginLine();
        fldraw.vertex(0, 150);
        fldraw.vertex(50, 150);
        fldraw.vertex(50, 190);
        fldraw.endLine();

        fldraw.fl_font(helvetica, 14);
        fldraw.fl_draw("Hi", 100, 150);

        SurfaceDevice.popCurrent();
        surf.close();
    }

    auto text = readText(path);
    assert(text.canFind("stroke-dasharray:6,2")); // dashPatternFor(lineDash, 2), in fl_line()'s CSS `style="..."` form
    assert(text.canFind("<clipPath id=\"FLclip0\">"));
    assert(text.canFind("<g clip-path=\"url(#FLclip0)\">"));
    assert(text.canFind("A 0.5,0.5 0")); // the outline arc() path
    assert(text.canFind("<circle cx=\"0\" cy=\"0\" r=\"0.5\"")); // the full-circle pie()
    assert(text.canFind("<path d=\"M 20 80 L 60 80 L 40 110 z\" fill=\"rgb(255,0,0)\""));
    assert(text.canFind("<path d=\"M 0 150 L 50 150 L 50 190\""));
    assert(text.canFind("<text x=\"100\" y=\"150\" font-family=\"Helvetica\""));
    assert(text.canFind(">Hi</text>"));
}

unittest
{
    // drawImage()/drawBitmap() (2026-09-22) via a real RGBImage.draw()/
    // Bitmap.draw(), the same real call path a live widget with an
    // image label would use -- mirrors fl.postscript's own equivalent
    // unittest.
    import fl.image : RGBImage;
    import fl.bitmap : Bitmap;
    import fl.image_surface : SurfaceDevice;
    import fl.enumerations : red;
    import fl.png_image : PngImage;
    import std.file : tempDir, exists, remove, readText;
    import std.path : buildPath;
    import std.uuid : randomUUID;
    import std.algorithm : canFind, countUntil, count;
    import std.base64 : Base64;
    import std.array : replace;

    auto path = buildPath(tempDir(), "fldtk-svg-image-test-" ~ randomUUID().toString() ~ ".svg");
    scope (exit) if (exists(path)) remove(path);

    {
        auto f = File(path, "w");
        auto surf = new SvgFileSurface(100, 100, f);
        SurfaceDevice.pushCurrent(surf);

        // A 2x2 RGB image -- exercises the drawImage() path.
        ubyte[] rgb = [255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 0];
        auto img = new RGBImage(rgb, 2, 2, 3);
        img.draw(10, 10, 2, 2);

        // An 8x8 1-bit bitmap (checkerboard) -- exercises the
        // drawBitmap() path, in the current color().
        fldraw.fl_color(red);
        ubyte[] bits = [0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA];
        auto bm = new Bitmap(bits, 8, 8);
        bm.draw(30, 30, 8, 8);

        SurfaceDevice.popCurrent();
        surf.close();
    }

    auto text = readText(path);
    assert(text.canFind("href=\"data:image/png;base64,"));
    // Exactly two embedded images (the RGB image and the bitmap).
    assert(text.count("href=\"data:image/png;base64,") == 2);

    // Decode the first embedded PNG back and confirm it round-trips.
    string marker = "data:image/png;base64,";
    auto afterMarker = text[text.countUntil(marker) + marker.length .. $];
    string b64 = afterMarker[0 .. afterMarker.countUntil("\"/>")].replace("\n", "");
    auto pngBytes = Base64.decode(b64);
    auto decoded = new PngImage("roundtrip", pngBytes);
    assert(!decoded.fail());
    assert(decoded.w() == 2 && decoded.h() == 2 && decoded.d() == 3);
    assert(decoded.array[0 .. 3] == [255, 0, 0]); // red
    assert(decoded.array[3 .. 6] == [0, 255, 0]); // green
    assert(decoded.array[6 .. 9] == [0, 0, 255]); // blue
    assert(decoded.array[9 .. 12] == [255, 255, 0]); // yellow
}
