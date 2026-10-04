/*
 * Port of `Fl_GDIplus_Graphics_Driver` (`src/drivers/GDI/Fl_GDI_Graphics_
 * Driver{.cxx,_color.cxx,_rect.cxx,_arci.cxx,_vertex.cxx,_line_style.cxx}`,
 * all under `#if USE_GDIPLUS`, plus the startup/shutdown dance in
 * `src/drivers/WinAPI/fl_WinAPI_platform_init.cxx`/`src/Fl_win32.cxx`).
 * GDI+ is FLTK's default on-screen Windows backend, with plain GDI as
 * the fallback if `GdiplusStartup()` fails.
 *
 * **Architecture matches FLTK's own inheritance shape exactly**:
 * `Fl_GDIplus_Graphics_Driver : public Fl_GDI_Graphics_Driver` overrides
 * only the antialiasing-relevant subset -- color, line/polygon drawing,
 * arcs/pies, line style, and the vertex-path `end*()` family -- while
 * reusing everything else (text, images, clipping, `rect()`/`rectf()`/
 * `xyline()`/`yxline()`) from the base GDI driver completely unchanged.
 * `GdiPlusGraphicsDriver : GdiGraphicsDriver` here does the same;
 * `fl.gdi_graphics_driver.GdiGraphicsDriver` is no longer `final` and
 * exposes `hdc_`/`lineWidth_`/`arcUnscaled()`/`pieUnscaled()` as
 * `protected` for exactly this reuse (see that module's own doc
 * comment on the class declaration).
 *
 * `loop()` (both overloads) is a driver method here as in FLTK, drawn
 * as one closed antialiased path. `circle()` and `vertex()`/
 * `transformed_vertex()` are not driver methods in this port:
 * `fl.draw.circle()` adds a 32-gon of points (see its doc comment) and
 * `vertex()` adds transformed points to `fl.draw`'s own buffer, and
 * both reach this driver through `endLine()`/`endLoop()`/
 * `endPolygon()`, which are antialiased GDI+ paths. The result
 * matches FLTK's except that a circle is a fine polygon rather than
 * a true arc.
 *
 * **A real FLTK bug found while porting `line_style()`, deviated
 * from rather than faithfully reproduced**: FLTK's own cap/join
 * dispatch (`if (style & FL_CAP_ROUND) {...} else if (style &
 * FL_CAP_SQUARE) {...}`) tests raw bits directly against `FL_CAP_ROUND`
 * (`0x200`) and `FL_CAP_SQUARE` (`0x300`) -- but `0x300 & 0x200 ==
 * 0x200` is true, so a caller requesting `FL_CAP_SQUARE` hits the
 * `FL_CAP_ROUND` branch *first* and never reaches its own case at all;
 * the identical pattern repeats for `FL_JOIN_MITER`/`FL_JOIN_BEVEL`
 * (`0x1000`/`0x3000`, same bit-containment problem). Confirmed by
 * checking the real values in `FL/fl_draw.H`, not assumed -- these are
 * genuine 2-bit fields (`(style>>8)&3`/`(style>>12)&3`), and this
 * port's own already-correct, already-shipped plain-GDI `applyLine
 * StyleUnscaled()` (`fl.gdi_graphics_driver`) already extracts them
 * that way, via a 4-entry lookup table. Logged as an `FLTK_ISSUES.md`
 * candidate; deviated from here (not faithfully reproduced) by reusing
 * that exact same, already-proven-correct table shape for the GDI+
 * pen too, matching this project's "verify, then fix" precedent for a
 * confirmed, narrow, safe-to-correct bug rather than preserving one
 * nobody would ever want reproduced on purpose.
 *
 * **A second, related adaptation, also because of a genuine
 * representational difference rather than guesswork**: FLTK's
 * `arc_unscaled()`/`pie_unscaled()` derive a GDI+ pen width from
 * `line_width_` via `(line_width_ <= scale() ? 1 : line_width_) *
 * scale()` -- correct *there* because FLTK's own `line_width_` is
 * itself already the scaled, device-pixel value by the time this runs
 * (confirmed by reading `Fl_Scalable_Graphics_Driver::line_style()`
 * itself: `line_width_ = int(width>0 ? width*scale() : -width*
 * scale());`, i.e. already multiplied by `scale()` once). This port's
 * own `lineWidth_` field is *exactly* that same already-scaled value
 * (same formula, see `GdiGraphicsDriver.lineStyle()`) -- so applying
 * FLTK's formula verbatim here would scale a second time for any
 * already-thick pen (e.g. `lineWidth_ == 10` at `currentScale() == 2`
 * would compute `10 * 2 == 20` instead of the correct `10`). Adapted to
 * `effectiveArcPenWidth()` below, which keeps FLTK's real intent
 * (a thin/unset pen still gets a real, scale-correct device-pixel
 * width; an explicitly thick one is used as-is) without the double
 * multiply -- see that function's own doc comment.
 */
module fl.gdiplus_graphics_driver;

version (Windows):

import fl.gdi_graphics_driver : GdiGraphicsDriver;
import fl.graphics_driver : GraphicsDriver, Point;
import fl.enumerations : Color, black, lineDash, lineDot, lineDashDot, lineDashDotDot;
import fl.core : currentScale;
import fl.draw : colorToRgb8;
import fl.gdiplus;

final class GdiPlusGraphicsDriver : GdiGraphicsDriver
{
    /// The current color, packed as GDI+'s own 0xAARRGGBB `ARGB`
    /// -- ported from `gdiplus_color_` (a real `Gdiplus::Color`
    /// object FLTK; this port only ever needs the packed value
    /// itself, see `toArgb()`'s own doc comment for why the wrapper
    /// class isn't needed at all).
    private ARGB gdiplusColor_;

    /// Ported from `pen_`/`brush_` -- one persistent GDI+ pen/brush,
    /// recolored (and, for the pen, re-styled) in place rather than
    /// recreated per draw call, matching FLTK's own reuse exactly.
    private GpPen* pen_;
    private GpSolidFill* brush_;

    /// Ported from `active` -- backs `antialias()`/`antialias(int)`
    /// below. `false` routes every overridden method straight to its
    /// inherited plain-GDI (`GdiGraphicsDriver`) implementation via
    /// `super`, matching FLTK's own `if (!active) return
    /// Fl_GDI_Graphics_Driver::xxx(...);` guard on every single method
    /// in this class.
    private bool active_ = true;

    /// Ported from the constructor body verbatim, with one considered
    /// simplification: FLTK's own `if (!fl_current_xmap)
    /// color(FL_BLACK);` guards against a *process-wide* global
    /// (`fl_current_xmap`) that could already be non-null from some
    /// earlier driver instance sharing the same file-scope state. This
    /// port's `currentXmap_` (`GdiGraphicsDriver`) is a plain per-
    /// instance field instead, and this constructor runs at most once,
    /// on a brand-new instance, before anything could possibly have
    /// touched it -- so the guard can never be false here, and the
    /// unconditional call below is behaviorally identical without
    /// needing `currentXmap_` promoted to `protected` just to read it.
    this()
    {
        color(black);
        GdipCreatePen1(gdiplusColor_, 1.0f, GpUnit.UnitWorld, &pen_);
        GdipSetPenLineJoin(pen_, GpLineJoin.LineJoinRound);
        GdipSetPenStartCap(pen_, GpLineCap.LineCapFlat);
        GdipSetPenEndCap(pen_, GpLineCap.LineCapFlat);
        GdipCreateSolidFill(gdiplusColor_, &brush_);
    }

    /// Ported from the destructor -- never actually reached in
    /// practice (this driver, like the plain `GdiGraphicsDriver` it
    /// extends, lives for the whole process as a single instance
    /// created once by `fl.platform_win32.ensureGraphicsDriver()`), but
    /// included for the same completeness reason FLTK has one.
    ~this()
    {
        if (pen_ !is null) GdipDeletePen(pen_);
        if (brush_ !is null) GdipDeleteBrush(cast(GpBrush*) brush_);
    }

    /// Ported from `Fl_GDIplus_Graphics_Driver::antialias(int)`/
    /// `antialias()`.
    override void antialias(int state) { active_ = state != 0; }
    override int antialias() { return active_ ? 1 : 0; } /// ditto

    /// Ported from `Fl_GDIplus_Graphics_Driver::color(Fl_Color)`/
    /// `color(uchar,uchar,uchar)` collapsed to one override, matching
    /// how `GdiGraphicsDriver.color()` already unifies both FLTK
    /// overloads behind this port's single `Color` parameter (see that
    /// method's own doc comment). Always updates both representations
    /// regardless of `active_` -- matches FLTK exactly: neither of
    /// its own two `color()` overrides has an `if (!active)` guard at
    /// all, since the plain-GDI pen/brush this updates via `super.
    /// color()` are still needed for whatever `rect()`/`rectf()`/text
    /// this driver draws unchanged either way.
    override void color(Color c)
    {
        super.color(c);
        ubyte r, g, b;
        colorToRgb8(c, r, g, b);
        gdiplusColor_ = toArgb(r, g, b);
    }

    /// Packs `(r,g,b)` as GDI+'s own opaque (alpha=0xFF) `ARGB` --
    /// ported from `Gdiplus::Color::SetFromCOLORREF(fl_RGB())`, but
    /// building the packed value directly from the same `ubyte`
    /// triple every other color path in this port's Windows driver
    /// already has on hand (`fl.draw.colorToRgb8()`) instead of
    /// round-tripping through a `COLORREF` first -- same bytes in,
    /// same bytes out, just skipping the redundant pack/unpack.
    private static ARGB toArgb(ubyte r, ubyte g, ubyte b)
    {
        return 0xFF000000u | (cast(ARGB) r << 16) | (cast(ARGB) g << 8) | cast(ARGB) b;
    }

    // ---- Fl_GDI_Graphics_Driver_rect.cxx's GDI+ block (line/polygon)
    // ----
    //
    // `fl.draw` dispatches `line()`/`polygon()` at raw, unscaled
    // coordinates (see `fl.gdi_graphics_driver`'s own top comment) --
    // matched here via a real `GdipScaleWorldTransform()` on a fresh
    // `Graphics` context per call, exactly mirroring FLTK's own
    // `graphics_.ScaleTransform(scale(), scale())`, rather than
    // `GdiGraphicsDriver`'s own per-coordinate `floorScaled()` (GDI+'s
    // world transform *is* the faithful port of FLTK's actual
    // mechanism here, not a shortcut).

    /// `applyScale` distinguishes which callers of this shared helper
    /// need `GdipScaleWorldTransform(g, s, s, ...)` applied: `arcUnscaled()`/
    /// `pieUnscaled()`/`strokePath()` (`endLine()`/`endLoop()`)/
    /// `fillPolygonPath()` (`endPolygon()`/`endComplexPolygon()`) all
    /// already receive coordinates *pre-scaled* to device pixels (their
    /// own doc comments say so: "Neither FLTK's nor this port's
    /// `_unscaled()` half applies its own `ScaleTransform()`... both
    /// already receive scaled coordinates by this point" for the
    /// arc/pie pair, "`pts` arrives already scaled to device pixels...
    /// no `GdipScaleWorldTransform()` here" for the vertex-path pair),
    /// so applying the transform again here would scale them a second
    /// time, growing and shifting a shape away from its correct
    /// position the further the current scale departs from `1.0`. Only `line()`/
    /// `polygon()`/`fillPath()`'s own `polygon()`-driven call genuinely
    /// receive raw, unscaled FLTK-unit coordinates (this module's own
    /// top-of-section comment) and need `applyScale = true`; every other
    /// caller now explicitly passes `false`.
    private GpGraphics* beginGraphics(bool antialiased, bool applyScale = true)
    {
        GpGraphics* g;
        GdipCreateFromHDC(hdc_, &g);
        if (applyScale)
        {
            float s = currentScale();
            GdipScaleWorldTransform(g, s, s, GpMatrixOrder.MatrixOrderPrepend);
        }
        if (antialiased) GdipSetSmoothingMode(g, SmoothingMode.SmoothingModeAntiAlias);
        return g;
    }

    /// Ported from `Fl_GDIplus_Graphics_Driver::line(x,y,x1,y1)`:
    /// antialiased only when the segment isn't axis-aligned (matching
    /// FLTK's own `AA = !(x==x1||y==y1)` -- a perfectly horizontal
    /// or vertical 1px line looks *worse*, not better, softened).
    override void line(int x, int y, int x1, int y1)
    {
        if (!active_) { super.line(x, y, x1, y1); return; }
        bool aa = !(x == x1 || y == y1);
        auto g = beginGraphics(aa);
        scope (exit) GdipDeleteGraphics(g);
        GdipSetPenColor(pen_, gdiplusColor_);
        GdipDrawLineI(g, pen_, x, y, x1, y1);
    }

    /// Ported from `Fl_GDIplus_Graphics_Driver::loop(x0..x2)`: one
    /// closed, antialiased path, so the corners join.
    override void loop(int x0, int y0, int x1, int y1, int x2, int y2)
    {
        if (!active_) { super.loop(x0, y0, x1, y1, x2, y2); return; }
        GpPoint[3] pts = [GpPoint(x0, y0), GpPoint(x1, y1), GpPoint(x2, y2)];
        GpPath* path;
        GdipCreatePath(GpFillMode.FillModeAlternate, &path);
        scope (exit) GdipDeletePath(path);
        GdipAddPathLine2I(path, pts.ptr, 3);
        GdipClosePathFigure(path);
        auto g = beginGraphics(true);
        scope (exit) GdipDeleteGraphics(g);
        GdipSetPenColor(pen_, gdiplusColor_);
        GdipDrawPath(g, pen_, path);
    }

    /// Ported from `Fl_GDIplus_Graphics_Driver::loop(x0..x3)`: an
    /// axis-aligned rectangle goes to `rect()` (whatever `active_` is,
    /// as in FLTK); any other quad is one closed, antialiased path,
    /// shifted by FLTK's `1 - line_width_/2` so its edges line up with
    /// `rect()`'s.
    override void loop(int x0, int y0, int x1, int y1, int x2, int y2, int x3, int y3)
    {
        if ((x0 == x3 && x1 == x2 && y0 == y1 && y3 == y2) || (x0 == x1 && y1 == y2 && x2 == x3 && y3 == y0))
        {
            import std.algorithm : min, max;

            int left = min(x0, x1, x2, x3);
            int right = max(x0, x1, x2, x3);
            int top = min(y0, y1, y2, y3);
            int bottom = max(y0, y1, y2, y3);
            rect(left, top, right - left + 1, bottom - top + 1);
            return;
        }
        if (!active_) { super.loop(x0, y0, x1, y1, x2, y2, x3, y3); return; }
        REAL d = 1 - lineWidth_ / 2.0f;
        GpPointF[4] pts = [GpPointF(x0 + d, y0 + d), GpPointF(x1 + d, y1 + d),
            GpPointF(x2 + d, y2 + d), GpPointF(x3 + d, y3 + d)];
        GpPath* path;
        GdipCreatePath(GpFillMode.FillModeAlternate, &path);
        scope (exit) GdipDeletePath(path);
        GdipAddPathLine2(path, pts.ptr, 4);
        GdipClosePathFigure(path);
        auto g = beginGraphics(true);
        scope (exit) GdipDeleteGraphics(g);
        GdipSetPenColor(pen_, gdiplusColor_);
        GdipDrawPath(g, pen_, path);
    }

    /// Ported from `Fl_GDIplus_Graphics_Driver::polygon(x0..x2)`.
    override void polygon(int x, int y, int x1, int y1, int x2, int y2)
    {
        if (!active_) { super.polygon(x, y, x1, y1, x2, y2); return; }
        GpPath* path;
        GdipCreatePath(GpFillMode.FillModeAlternate, &path);
        scope (exit) GdipDeletePath(path);
        GdipAddPathLineI(path, x, y, x1, y1);
        GdipAddPathLineI(path, x1, y1, x2, y2);
        GdipClosePathFigure(path);
        fillPath(path, true);
    }

    /// Ported from `Fl_GDIplus_Graphics_Driver::polygon(x0..x3)`,
    /// **including its own axis-aligned-rectangle special case** --
    /// this optimization is genuinely GDI+-specific (checked FLTK's
    /// plain `Fl_GDI_Graphics_Driver::polygon_unscaled(x0..x3)`, and
    /// `GdiGraphicsDriver`'s own already-shipped `polygon()` here in
    /// this port: neither has it, both always draw via a plain 4-point
    /// `Polygon()` regardless of shape). Redirecting a rectangle to
    /// `rectf()` instead of an antialiased path avoids visibly
    /// softening edges that don't need it, matching `line()`'s own
    /// axis-aligned-segment reasoning above.
    override void polygon(int x, int y, int x1, int y1, int x2, int y2, int x3, int y3)
    {
        if (!active_) { super.polygon(x, y, x1, y1, x2, y2, x3, y3); return; }
        if ((x == x3 && x1 == x2 && y == y1 && y3 == y2) || (x == x1 && y1 == y2 && x2 == x3 && y3 == y))
        {
            import std.algorithm : min, max;

            int left = min(x, x1, x2, x3);
            int right = max(x, x1, x2, x3);
            int top = min(y, y1, y2, y3);
            int bottom = max(y, y1, y2, y3);
            rectf(left, top, right - left, bottom - top);
            return;
        }
        GpPath* path;
        GdipCreatePath(GpFillMode.FillModeAlternate, &path);
        scope (exit) GdipDeletePath(path);
        GdipAddPathLineI(path, x, y, x1, y1);
        GdipAddPathLineI(path, x1, y1, x2, y2);
        GdipAddPathLineI(path, x2, y2, x3, y3);
        GdipClosePathFigure(path);
        fillPath(path, true);
    }

    /// `applyScale`: `true` for `polygon()`'s own calls above (raw,
    /// unscaled FLTK-unit coordinates, needing the world-transform
    /// scale), `false` for `fillPolygonPath()`'s (`endPolygon()`/
    /// `endComplexPolygon()`, already-scaled device-pixel coordinates)
    /// -- see `beginGraphics()`'s own doc comment for the bug this
    /// distinction fixes. This one shared function used to always
    /// pass `true`, silently double-scaling every vertex-path fill.
    private void fillPath(GpPath* path, bool applyScale)
    {
        auto g = beginGraphics(true, applyScale);
        scope (exit) GdipDeleteGraphics(g);
        GdipSetSolidFillColor(brush_, gdiplusColor_);
        GdipFillPath(g, cast(GpBrush*) brush_, path);
    }

    // ---- Fl_GDI_Graphics_Driver_arci.cxx's GDI+ block ----
    //
    // Overrides the `protected` `arcUnscaled()`/`pieUnscaled()` hooks
    // `GdiGraphicsDriver.arc()`/`pie()` (unchanged, inherited) already
    // call with real, already-scaled device-pixel `x,y,w,h` -- matching
    // FLTK's own identical split (`Fl_Scalable_Graphics_Driver::
    // arc()`/`pie()`, unchanged, calling `_unscaled()`). Neither
    // FLTK's nor this port's `_unscaled()` half applies its own
    // `ScaleTransform()` -- both already receive scaled coordinates by
    // this point, for the same reason.

    /// Ported from `arc_unscaled()`, adapted for the pen-width formula
    /// -- see this module's own top comment for why (a genuine
    /// already-scaled-vs-scale-again difference, not a guess).
    protected override void arcUnscaled(int x, int y, int w, int h, double a1, double a2)
    {
        if (w <= 0 || h <= 0) return;
        if (!active_) { super.arcUnscaled(x, y, w, h, a1, a2); return; }

        auto g = beginGraphics(true, false);
        scope (exit) GdipDeleteGraphics(g);
        GdipSetPenColor(pen_, gdiplusColor_);
        // GDI+ has no direct "get width" in this port's own narrow
        // binding scope (never needed elsewhere) -- `lastPenWidth_`
        // (kept in sync by `lineStyle()`) tracks the pen's real
        // resting width instead of round-tripping through a
        // GdipGetPenWidth() this module doesn't declare.
        REAL restingWidth = lastPenWidth_;
        GdipSetPenWidth(pen_, effectiveArcPenWidth());
        GdipDrawArcI(g, pen_, x, y, w, h, cast(REAL)(-a1), cast(REAL)(a1 - a2));
        GdipSetPenWidth(pen_, restingWidth);
    }

    /// Ported from `pie_unscaled()`.
    protected override void pieUnscaled(int x, int y, int w, int h, double a1, double a2)
    {
        if (w <= 0 || h <= 0) return;
        if (!active_) { super.pieUnscaled(x, y, w, h, a1, a2); return; }

        auto g = beginGraphics(true, false);
        scope (exit) GdipDeleteGraphics(g);
        GdipSetSolidFillColor(brush_, gdiplusColor_);
        GdipFillPieI(g, cast(GpBrush*) brush_, x, y, w, h, cast(REAL)(-a1), cast(REAL)(a1 - a2));
    }

    /// The pen's "resting" width outside of `arcUnscaled()`'s own
    /// temporary override -- kept in sync by `lineStyle()` below,
    /// read/restored by `arcUnscaled()` so a subsequent non-arc draw
    /// (a `line()`/`polygon()` call right after an arc) doesn't
    /// inherit the arc's own possibly-different width.
    private REAL lastPenWidth_ = 1.0f;

    /// Ported from `arc_unscaled()`'s own `(line_width_ <= scale() ? 1
    /// : line_width_) * scale()`, adapted to this port's already-scaled
    /// `lineWidth_` (see this module's own top comment for the full
    /// reasoning): a thin/unset pen (`lineWidth_ <= currentScale()`,
    /// e.g. `0` or `1` at scale `1`) still gets a real, scale-correct
    /// device-pixel width (`currentScale()` itself -- one device pixel
    /// at any scale); an explicitly thicker pen is used exactly as
    /// already stored, with no second multiply.
    private REAL effectiveArcPenWidth() const
    {
        float s = currentScale();
        return (lineWidth_ <= s) ? cast(REAL) s : cast(REAL) lineWidth_;
    }

    // ---- Fl_GDI_Graphics_Driver_vertex.cxx's GDI+ block (end*()
    // family) ----
    //
    // `pts` arrives already scaled to device pixels (`fl.draw`'s own
    // `vertex()`/`transformedVertex()` scale every point before it
    // reaches any driver's `endXxx()` -- see `GdiGraphicsDriver`'s own
    // top comment) -- unlike `line()`/`polygon()` above, so no
    // `GdipScaleWorldTransform()` here: applying one on top of already-
    // scaled points would scale twice. `end_points()` is deliberately
    // *not* overridden at all -- checked FLTK's own body, not
    // assumed: `Fl_GDIplus_Graphics_Driver::end_points()` just loops
    // calling `point()` (plain `Fl_GDI_Graphics_Driver::point()`,
    // itself just `rectf(x,y,1,1)`) regardless of `active_` -- exactly
    // what `GdiGraphicsDriver`'s own inherited `endPoints()` already
    // does, so overriding it here would only reproduce the identical
    // behavior.

    private static GpPoint[] toGpPoints(const(Point)[] pts)
    {
        auto gp = new GpPoint[pts.length];
        foreach (i, p; pts) gp[i] = GpPoint(p.x, p.y);
        return gp;
    }

    /// Ported from `end_line()`.
    override void endLine(const(Point)[] pts)
    {
        if (!active_) { super.endLine(pts); return; }
        if (pts.length < 2) { endPoints(pts); return; }
        strokePath(toGpPoints(pts), false);
    }

    /// Ported from `end_loop()` -- the one real difference from
    /// `end_line()` (`GdipClosePathFigure()`, giving the loop's own
    /// shared start/end vertex a real joined corner instead of two
    /// independent line caps meeting) is why this isn't just a plain
    /// delegation to `endLine()` the way `GdiGraphicsDriver`'s own
    /// (and FLTK's plain-GDI) `end_loop()` is.
    override void endLoop(const(Point)[] pts)
    {
        if (!active_) { super.endLoop(pts); return; }
        if (pts.length < 2) { endPoints(pts); return; }
        strokePath(toGpPoints(pts), true);
    }

    private void strokePath(GpPoint[] gpPts, bool close)
    {
        GpPath* path;
        GdipCreatePath(GpFillMode.FillModeAlternate, &path);
        scope (exit) GdipDeletePath(path);
        GdipAddPathLine2I(path, gpPts.ptr, cast(int) gpPts.length);
        if (close) GdipClosePathFigure(path);

        auto g = beginGraphics(true, false);
        scope (exit) GdipDeleteGraphics(g);
        GdipSetPenColor(pen_, gdiplusColor_);
        GdipDrawPath(g, pen_, path);
    }

    /// Ported from `end_polygon()`.
    override void endPolygon(const(Point)[] pts)
    {
        if (!active_) { super.endPolygon(pts); return; }
        if (pts.length < 3) { endLine(pts); return; }
        fillPolygonPath(toGpPoints(pts));
    }

    /// Ported from `end_complex_polygon()` -- identical body to
    /// `end_polygon()` FLTK too (both just fill one closed
    /// `AddPolygon()` path), matching `GdiGraphicsDriver`'s own
    /// already-established simplification of drawing this port's
    /// single flat, already-gap-merged point list as one polygon
    /// (see that method's own doc comment) rather than reconstructing
    /// sub-loop boundaries no longer present in the data.
    override void endComplexPolygon(const(Point)[] pts)
    {
        if (!active_) { super.endComplexPolygon(pts); return; }
        if (pts.length < 3) { endLine(pts); return; }
        fillPolygonPath(toGpPoints(pts));
    }

    /// The GDI+ path only fills, so the joining edges between sub-loops
    /// leave no mark and the flat list is drawn as before; with
    /// antialiasing off, the plain GDI `PolyPolygon()` version runs.
    override void endComplexPolygonParts(const(Point)[] pts, const(int)[] counts)
    {
        if (!active_) { super.endComplexPolygonParts(pts, counts); return; }
        endComplexPolygon(pts);
    }

    private void fillPolygonPath(GpPoint[] gpPts)
    {
        GpPath* path;
        GdipCreatePath(GpFillMode.FillModeAlternate, &path);
        scope (exit) GdipDeletePath(path);
        GdipAddPathPolygonI(path, gpPts.ptr, cast(int) gpPts.length);
        GdipClosePathFigure(path);
        fillPath(path, false);
    }

    // ---- Fl_GDI_Graphics_Driver_line_style.cxx's GDI+ block ----

    /// Ported from `Fl_GDIplus_Graphics_Driver::line_style()`.
    /// `super.lineStyle()` runs first (unconditionally, matching
    /// FLTK's own tail call to `Fl_Scalable_Graphics_Driver::
    /// line_style()`, which is what keeps the *plain* GDI pen this
    /// driver's own inherited `rect()`/`rectf()`/`xyline()`/`yxline()`
    /// still use in sync) -- the GDI+ `pen_` update below is
    /// independent and unconditional too, matching FLTK (neither
    /// of FLTK's two pens has an `if (!active)` guard on the style
    /// update itself, only on the later *draw* calls that use them).
    override void lineStyle(int style, int width, const(ubyte)[] dashes)
    {
        super.lineStyle(style, width, dashes);

        int gdiWidth = width != 0 ? width : 1;
        lastPenWidth_ = cast(REAL) gdiWidth;
        GdipSetPenWidth(pen_, lastPenWidth_);

        int standardDash = style & 0x7;
        if (standardDash == lineDash) GdipSetPenDashStyle(pen_, GpDashStyle.DashStyleDash);
        else if (standardDash == lineDot) GdipSetPenDashStyle(pen_, GpDashStyle.DashStyleDot);
        else if (standardDash == lineDashDot) GdipSetPenDashStyle(pen_, GpDashStyle.DashStyleDashDot);
        else if (standardDash == lineDashDotDot) GdipSetPenDashStyle(pen_, GpDashStyle.DashStyleDashDotDot);
        else if (dashes.length == 0 || dashes[0] == 0) GdipSetPenDashStyle(pen_, GpDashStyle.DashStyleSolid);

        // Ported from `(style>>8)&3`/`(style>>12)&3` (`GdiGraphicsDriver.
        // applyLineStyleUnscaled()`'s own already-correct table shape)
        // -- **not** FLTK's own raw `style & FL_CAP_ROUND`/`style &
        // FL_JOIN_MITER` bit tests, a confirmed real FLTK bug (see
        // this module's own top comment).
        static immutable GpLineCap[4] capTable =
            [GpLineCap.LineCapFlat, GpLineCap.LineCapFlat, GpLineCap.LineCapRound, GpLineCap.LineCapSquare];
        static immutable GpLineJoin[4] joinTable =
            [GpLineJoin.LineJoinRound, GpLineJoin.LineJoinMiter, GpLineJoin.LineJoinRound, GpLineJoin.LineJoinBevel];
        auto cap = capTable[(style >> 8) & 3];
        GdipSetPenStartCap(pen_, cap);
        GdipSetPenEndCap(pen_, cap);
        GdipSetPenLineJoin(pen_, joinTable[(style >> 12) & 3]);

        // Ported from the trailing `if (dashes && *dashes) {...
        // SetDashPattern...}` -- GDI+ expresses a custom dash pattern
        // as multiples of the pen width, unlike GDI's own raw-pixel-
        // length dash array, hence the `/ gdiWidth` normalization.
        // `GdipSetPenDashArray()` itself implicitly switches the pen to
        // `DashStyleCustom` (real, documented GDI+ behavior) -- no
        // separate call needed for that.
        if (dashes.length && dashes[0] != 0)
        {
            REAL[] gdiDashes = new REAL[dashes.length];
            foreach (i, d; dashes) gdiDashes[i] = d / cast(REAL) gdiWidth;
            GdipSetPenDashArray(pen_, gdiDashes.ptr, cast(int) gdiDashes.length);
        }
    }
}

/**
 * Ported from `Fl_Graphics_Driver::newMainGraphicsDriver()`'s own
 * `#if USE_GDIPLUS` branch (`fl_WinAPI_platform_init.cxx`). FLTK
 * picks GDI+ vs. plain GDI at *compile* time (`USE_GDIPLUS`, which
 * `CMake/options.cmake`'s own `FLTK_GRAPHICS_GDIPLUS` option defaults
 * **ON** for a real FLTK Windows build -- confirmed by reading that
 * option's own default, not assumed). This port has no compile-time
 * equivalent, so this factory is the runtime substitute `fl.platform_
 * win32.ensureGraphicsDriver()` calls instead -- and matches FLTK's
 * own actual default behavior (GDI+ first, plain GDI only as a real
 * fallback if `GdiplusStartup()` itself fails) rather than defaulting
 * this port to the less-featured, non-default-FLTK plain-GDI path.
 * This is a real, visible behavior change from every prior phase's own
 * testing: antialiased lines/arcs/polygons are now what a real FLTK
 * FLTK.exe actually looks like by default too, not a fldtk-specific
 * embellishment.
 *
 * State-machine fields/logic ported from `Fl_GDIplus_Graphics_Driver::
 * gdiplus_state_`/`gdiplus_token_`/`shutdown()` -- module-level here
 * rather than static class members (this port has no per-class-static
 * field convention elsewhere), same single-process-wide meaning. Plain
 * (thread-local-by-default) module state, not `__gshared` -- this only
 * ever runs from the single-threaded Win32 message-loop thread, same
 * as every other piece of `fl.platform_win32`'s own module state.
 *
 * **Not ported**: FLTK's own `Fl_GDIplus_Graphics_Driver::
 * shutdown()` call site is a global static object's C++ destructor
 * (`Fl_Win32_At_Exit::~Fl_Win32_At_Exit()`, `Fl_win32.cxx`) -- a real
 * process-exit cleanup hook this port has never had an equivalent of
 * for *any* of its Windows resources (the plain GDI xmap pens don't
 * get an exit-time `fl_cleanup_pens()` either, `OleUninitialize()` is
 * never called, etc.) -- adding one just for this one optional feature
 * would be new scope beyond what this phase asked for, and the OS
 * reclaims a `GdiplusShutdown()`-less token on process exit regardless,
 * matching this port's existing, established "OS reclaims everything
 * on exit" precedent.
 */
private enum GdiplusState { closed, startup, open, shutdown }
private GdiplusState gdiplusState_ = GdiplusState.closed;
private size_t gdiplusToken_;

package(fl) GdiGraphicsDriver createGraphicsDriver()
{
    if (gdiplusState_ == GdiplusState.closed)
    {
        gdiplusState_ = GdiplusState.startup;
        GdiplusStartupInput input;
        Status ret = GdiplusStartup(&gdiplusToken_, &input, null);
        if (ret == Status.Ok)
        {
            gdiplusState_ = GdiplusState.open;
        }
        else
        {
            import std.stdio : stderr;

            stderr.writefln("fldtk: GdiplusStartup failed with error code %d.", cast(int) ret);
            gdiplusState_ = GdiplusState.closed;
            return new GdiGraphicsDriver;
        }
    }
    // The `GdiplusState.open`/`startup`/`shutdown` branches below
    // `closed` are unreachable in practice in this port -- unlike
    // FLTK (where several independent call sites can all reach
    // `newMainGraphicsDriver()`), this factory only ever runs once,
    // gated by `fl.platform_win32.ensureGraphicsDriver()`'s own
    // `gdiDriver_ !is null` guard around its one call site. Kept
    // anyway, matching FLTK's own defensive completeness (real
    // states this process could theoretically be in, just never
    // observed from this port's single call site).

    return new GdiPlusGraphicsDriver;
}
