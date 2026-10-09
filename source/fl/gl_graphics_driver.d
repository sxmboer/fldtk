/*
 * Port of `src/drivers/OpenGL/Fl_OpenGL_Graphics_Driver*.cxx` (7 files,
 * FLTK 1.5.0): the base class plus `_rect.cxx`/
 * `_color.cxx`/`_arci.cxx`/`_line_style.cxx`/`_vertex.cxx`. See
 * `fl.graphics_driver`'s own doc comment for the dispatch model
 * (`fl.draw`'s leaf primitives call `fl.graphics_driver.currentDriver`'s
 * methods instead of raw Xlib/Xft when one is active) -- this is that
 * abstraction's real GL-backed implementation, alongside
 * `fl.svg_file_surface`/`fl.postscript`.
 *
 * **Scope**: implements exactly `fl.graphics_driver.GraphicsDriver`'s
 * own abstract method set -- not FLTK's full ~20-method
 * `Fl_OpenGL_Graphics_Driver` surface. That set turns out to already
 * cover every leaf a real widget's `draw()` reaches on the way to
 * pixels for the boxtypes/primitives `source/test/cube.d`'s widget
 * tree (`Button`/`LightButton`/`Slider`/`Grid`/`SysMenuBar`) actually
 * uses -- `color`/`rectf`/`rect`/`line`/`xyline`/`yxline`/`polygon`/
 * `lineStyle`/`pushClip`/`popClip`/`arc`/`pie`/the vertex-path `end*()`
 * family/`draw()` -- verified by tracing `fl.draw.drawBoxAt()`'s
 * `upBox`/`downBox`/`thinUpBox`/`flatBox`/`borderBox`/`downFrame`
 * branches (all compose from `fl_color()`+`fl_rectf()`+`fl_xyline()`+
 * `fl_yxline()`+`fl_rect()`, all already dispatched leaves) and
 * `focusRect()`/`drawRadio()` (compose from `lineStyle()`+
 * `fl_rect()` and `fl_arc()`/`fl_pie()` respectively). `drawImage()`
 * (see that method's own doc comment -- `source/test/gl_image.d` needs
 * it) is a deliberately simpler uncached `gl_draw_image()`/
 * `glDrawPixels()` forward rather than FLTK's persistent
 * `GL_TEXTURE_RECTANGLE_ARB` cache. `drawBitmap()` (the 1-bit
 * `Fl_Bitmap` stencil path, see that method's own doc comment) applies
 * the same "no texture cache" simplification to the 1-bit case. Still
 * not overridden here, matching `GraphicsDriver`'s own non-abstract
 * no-op default: `draw(int angle,...)` (no rotated-text consumer in
 * this port's GL path either).
 *
 * **Text**: `draw()` below is a thin wrapper around `fl.gl.gl_draw()`
 * (a real,
 * near-verbatim port of `Fl_OpenGL_Graphics_Driver_font.cxx`'s live
 * branch -- `gl_font()`/`gl_draw()`'s own texture-rectangle-based text
 * cache, see that module's own doc comment for the full mechanism and
 * its one deliberate scope cut: no legacy glut/`glXUseXFont` fallback).
 * `font()` needed no override at all -- `GraphicsDriver` has no
 * `font()` dispatch hook (metrics stay native/undispatched by design),
 * and `fl.gl.gl_font()` is itself just a thin `fl_font()` passthrough,
 * so the ambient font state a widget's `drawLabel()` already
 * established via its own `fl_font()` call is exactly what `fl.gl`
 * reads -- nothing extra to wire up here. GL-composited widget labels
 * render correctly now.
 *
 * **Clipping is simplified relative to FLTK's own `Fl_Gl_Region`
 * stack**: `GraphicsDriver.pushClip(x,y,w,h)` is documented as always
 * receiving the *already-intersected* rectangle (`fl.draw.pushClip()`'s
 * own clip-stack bookkeeping runs unconditionally, driver dispatched or
 * not -- see that function's doc comment), so there's no need to
 * reproduce FLTK's own `set_intersect()`/`kStateFull`/`kStateEmpty`
 * machinery here at all: just convert the given rect to a `glScissor()`
 * box (with the y-flip scissor coordinates need -- window-pixel-space,
 * bottom-left origin, unlike the y-down ortho projection every other
 * primitive here draws in) and push/pop a small stack to restore the
 * previous box. See `setMetrics()`'s own doc comment for how this class
 * learns the current window's height/scale, needed for that flip.
 *
 * **`endComplexPolygon()` drops FLTK's GAP-marker skip branch**:
 * FLTK's own `SLOW_COMPLEX_POLY` scanline fill (its default,
 * `#else` non-tessellating fallback -- OpenGL itself can't fill a
 * concave/multi-loop polygon via a plain `GL_POLYGON`) walks a flat
 * vertex array containing a literal `1e9f` sentinel x-coordinate
 * (`GAP`) between sub-loops, skipping past it. This port's own vertex
 * accumulator (`fl.draw`'s `fl_gap()`/`endComplexPolygon()`) has
 * no such marker -- each sub-loop is already closed (its start point
 * re-appended) and the whole thing handed over as one flat `Point[]`,
 * the same simplification `fl.svg_file_surface.SvgGraphicsDriver.
 * endComplexPolygon()` already makes (a single continuous path/fill,
 * not FLTK's real multi-loop/hole support). Porting the scanline
 * algorithm over that flat array (dropping the GAP check) reproduces
 * the same simplification faithfully rather than trying to reconstruct
 * sub-loop boundaries that this port's data model does not keep.
 */
module fl.gl_graphics_driver;

version (linux) version = FldtkGl;
version (Windows) version = FldtkGl;

version (FldtkGl):

import std.math : sqrt, cos, sin, fabs = abs, PI;

import fl.graphics_driver : GraphicsDriver, Point;
import fl.enumerations : Color, lineSolid, lineDash, lineDot, lineDashDot, lineDashDotDot;
import fl.opengl;

final class GlGraphicsDriver : GraphicsDriver
{
    // Ported from Fl_OpenGL_Graphics_Driver's own public fields.
    private float pixelsPerUnit_ = 1.0f;
    private float lineWidth_ = 1.0f;
    private int lineStipple_ = lineSolid;

    // The FLTK-unit height of the window currently being drawn into --
    // needed only by pushClip()'s y-flip (see this module's own top
    // comment). Not FLTK state at all (FLTK's own Fl_Gl_Region
    // reaches `Fl_Gl_Window::current()->as_gl_window()` directly);
    // tracked explicitly here instead to avoid `fl.gl_graphics_driver`
    // needing to import `fl.gl_window` (which itself will import
    // `fl.gl_display_device`, which imports this module -- a cycle).
    private int windowH_;

    private struct ScissorRect { int x, y, w, h; bool empty; }
    private ScissorRect[] scissorStack_;

    /**
     * Called by `fl.gl_window.GlWindow.drawBegin()` right before
     * `SurfaceDevice.pushCurrent()`, once per frame -- records the
     * window's own `pixelsPerUnit()`/`h()` (needed by `pushClip()`'s
     * y-flip, see this module's top comment) and clears any scissor
     * state left over from a previous frame (defensive: `drawBegin()`/
     * `drawEnd()` always pair up in practice, but resetting here rather
     * than relying on that means a mismatched pair can't leave stale
     * clip state active on the next frame).
     */
    void setMetrics(float pixelsPerUnit, int windowH)
    {
        pixelsPerUnit_ = pixelsPerUnit;
        windowH_ = windowH;
        scissorStack_.length = 0;
    }

    /// The line width `lineStyle()` last set -- read by `GlWindow.
    /// drawBegin()`'s own initial `glLineWidth()` call, matching
    /// FLTK's `glLineWidth((GLfloat)(drv->pixels_per_unit_*
    /// drv->line_width_))` (a public field there; this port keeps
    /// `lineWidth_` private and exposes it through a getter instead,
    /// matching this class's own general field-privacy style).
    float lineWidth() const { return lineWidth_; }

    // ---- fl_color.cxx (Fl_OpenGL_Graphics_Driver_color.cxx) ----

    /// Ported from `Fl_OpenGL_Graphics_Driver::color(Fl_Color)`. Unlike
    /// `fl.draw.colorToRgb8()` (which only ever extracts RGB, matching
    /// the X11 path's own "alpha is inert there" convention -- see that
    /// function's own doc comment), this recovers the real alpha a
    /// packed color carries so a translucent fill actually blends
    /// against the GL scene behind it instead of rendering fully
    /// opaque: `Fl_Color`'s packed format stores `alpha XOR 0xff` in
    /// its low byte (`fl.core.setColor(Color,ubyte,ubyte,ubyte,ubyte)`'s
    /// own doc comment -- the same packing this port already uses), so
    /// `rgba = color ^ 0x000000ff` recovers it, which `drawBegin()`'s
    /// `GL_BLEND`/`GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA` setup then
    /// actually blends with. Applies to both the packed/"free"-color
    /// branch and the indexed-table
    /// branch (`fl.core.colorTableEntry()`, this port's own `fl_cmap[]`
    /// equivalent) -- ported faithfully, including reading through any
    /// `fl.core.setColor()` override on an indexed entry.
    override void color(Color c)
    {
        import fl.core : colorTableEntry;

        uint rgba = (c & 0xFFFFFF00) ? (cast(uint) c) ^ 0x000000FF : colorTableEntry(c) ^ 0x000000FF;
        glColor4ub(cast(ubyte)(rgba >> 24), cast(ubyte)(rgba >> 16),
            cast(ubyte)(rgba >> 8), cast(ubyte) rgba);
    }

    // ---- Fl_OpenGL_Graphics_Driver_rect.cxx ----

    override void rectf(int x, int y, int w, int h)
    {
        if (w <= 0 || h <= 0) return;
        glRectf(cast(GLfloat) x, cast(GLfloat) y, cast(GLfloat)(x + w), cast(GLfloat)(y + h));
    }

    /// Ported verbatim from `Fl_OpenGL_Graphics_Driver::rect()`: draws
    /// the outline as four filled `glRectf()` bars rather than an
    /// actual `GL_LINE_LOOP` stroke. Consequence: a dashed/dotted
    /// `lineStyle()` (e.g. `focusRect()`'s own `lineDot`) has no visible
    /// effect here -- `glLineStipple()`/`GL_LINE_STIPPLE` only affects
    /// `GL_LINES`/`GL_LINE_STRIP`/`GL_LINE_LOOP` primitives, and this
    /// function never issues any of those. A focus rectangle renders
    /// solid under GL compositing, unlike the native Xlib path's real
    /// dashed `XDrawRectangle()`. This is a faithfully-ported FLTK
    /// limitation (same `glRectf()`-bars body, no stipple check), not a
    /// fldtk-introduced regression. See `FLTK_ISSUES.md`'s
    /// `Fl_OpenGL_Graphics_Driver::rect() ignores line stipple` entry.
    override void rect(int x, int y, int w, int h)
    {
        float offset = lineWidth_ / 2.0f;
        float xx = x + 0.5f, yy = y + 0.5f;
        float rr = x + w - 0.5f, bb = y + h - 0.5f;
        glRectf(xx - offset, yy - offset, rr + offset, yy + offset);
        glRectf(xx - offset, bb - offset, rr + offset, bb + offset);
        glRectf(xx - offset, yy - offset, xx + offset, bb + offset);
        glRectf(rr - offset, yy - offset, rr + offset, bb + offset);
    }

    override void line(int x, int y, int x1, int y1)
    {
        if (x == x1 && y == y1) return;
        if (x == x1) { yxline(x, y, y1); return; }
        if (y == y1) { xyline(x, y, x1); return; }

        float xx = x + 0.5f, xx1 = x1 + 0.5f;
        float yy = y + 0.5f, yy1 = y1 + 0.5f;
        if (lineWidth_ == 1.0f)
        {
            glBegin(GL_LINE_STRIP);
            glVertex2f(xx, yy);
            glVertex2f(xx1, yy1);
            glEnd();
        }
        else
        {
            float dx = xx1 - xx, dy = yy1 - yy;
            float len = sqrt(dx * dx + dy * dy);
            dx = dx / len * lineWidth_ * 0.5f;
            dy = dy / len * lineWidth_ * 0.5f;

            glBegin(GL_TRIANGLE_STRIP);
            glVertex2f(xx - dy, yy + dx);
            glVertex2f(xx + dy, yy - dx);
            glVertex2f(xx1 - dy, yy1 + dx);
            glVertex2f(xx1 + dy, yy1 - dx);
            glEnd();
        }
    }

    override void xyline(int x, int y, int x1)
    {
        float offset = lineWidth_ / 2.0f;
        float xx = cast(float) x, yy = y + 0.5f, rr = x1 + 1.0f;
        glRectf(xx, yy - offset, rr, yy + offset);
    }

    override void yxline(int x, int y, int y1)
    {
        float offset = lineWidth_ / 2.0f;
        float xx = x + 0.5f, yy = cast(float) y, bb = y1 + 1.0f;
        glRectf(xx - offset, yy, xx + offset, bb);
    }

    override void polygon(int x0, int y0, int x1, int y1, int x2, int y2)
    {
        glBegin(GL_POLYGON);
        glVertex2i(x0, y0);
        glVertex2i(x1, y1);
        glVertex2i(x2, y2);
        glEnd();
    }

    override void polygon(int x0, int y0, int x1, int y1, int x2, int y2, int x3, int y3)
    {
        glBegin(GL_POLYGON);
        glVertex2i(x0, y0);
        glVertex2i(x1, y1);
        glVertex2i(x2, y2);
        glVertex2i(x3, y3);
        glEnd();
    }

    // ---- Fl_OpenGL_Graphics_Driver_rect.cxx's clip region, adapted --
    // see this module's own top comment for why FLTK's own
    // Fl_Gl_Region intersection logic isn't needed here.

    override void pushClip(int x, int y, int w, int h)
    {
        if (w <= 0 || h <= 0)
        {
            scissorStack_ ~= ScissorRect(0, 0, 0, 0, true);
        }
        else
        {
            int gx = cast(int)(x * pixelsPerUnit_);
            int gy = cast(int)((windowH_ - h - y + 1) * pixelsPerUnit_);
            int gw = cast(int)((w - 1) * pixelsPerUnit_);
            int gh = cast(int)((h - 1) * pixelsPerUnit_);
            scissorStack_ ~= ScissorRect(gx, gy, gw, gh, false);
        }
        applyScissor();
    }

    override void popClip()
    {
        if (scissorStack_.length) scissorStack_ = scissorStack_[0 .. $ - 1];
        applyScissor();
    }

    private void applyScissor()
    {
        if (scissorStack_.length == 0)
        {
            glDisable(GL_SCISSOR_TEST);
            return;
        }
        auto r = scissorStack_[$ - 1];
        if (r.empty || r.w <= 0 || r.h <= 0)
        {
            glScissor(0, 0, 0, 0);
        }
        else
        {
            glScissor(r.x, r.y, r.w, r.h);
        }
        glEnable(GL_SCISSOR_TEST);
    }

    // ---- Fl_OpenGL_Graphics_Driver_arci.cxx ----

    override void arc(int x, int y, int w, int h, double a1, double a2)
    {
        if (w <= 0 || h <= 0) return;
        while (a2 < a1) a2 += 360.0;
        a1 = a1 / 180.0 * PI;
        a2 = a2 / 180.0 * PI;
        double cx = x + 0.5 * w, cy = y + 0.5 * h;
        double rx = 0.5 * w - 0.3, ry = 0.5 * h - 0.3;
        double rMax = (w > h) ? rx : ry;
        int nSeg = cast(int)(10 * sqrt(rMax)) + 1;
        double incr = (a2 - a1) / cast(double) nSeg;

        glBegin(GL_LINE_STRIP);
        foreach (i; 0 .. nSeg + 1)
        {
            glVertex2d(cx + cos(a1) * rx, cy - sin(a1) * ry);
            a1 += incr;
        }
        glEnd();
    }

    override void pie(int x, int y, int w, int h, double a1, double a2)
    {
        if (w <= 0 || h <= 0) return;
        while (a2 < a1) a2 += 360.0;
        a1 = a1 / 180.0 * PI;
        a2 = a2 / 180.0 * PI;
        double cx = x + 0.5 * w, cy = y + 0.5 * h;
        double rx = 0.5 * w, ry = 0.5 * h;
        double rMax = (w > h) ? rx : ry;
        int nSeg = cast(int)(10 * sqrt(rMax)) + 1;
        double incr = (a2 - a1) / cast(double) nSeg;

        glBegin(GL_TRIANGLE_FAN);
        glVertex2d(cx, cy);
        foreach (i; 0 .. nSeg + 1)
        {
            glVertex2d(cx + cos(a1) * rx, cy - sin(a1) * ry);
            a1 += incr;
        }
        glEnd();
    }

    // ---- Fl_OpenGL_Graphics_Driver_line_style.cxx ----
    // OpenGL implementation does not support custom dash patterns
    // (`dashes` is ignored, matching FLTK exactly) or cap/join types.

    override void lineStyle(int style, int width, const(ubyte)[] dashes)
    {
        if (width < 1) width = 1;
        lineWidth_ = cast(float) width;

        int stipple = style & 0x00ff;
        lineStipple_ = stipple;

        if (stipple == lineSolid)
        {
            glLineStipple(1, 0xFFFF);
            glDisable(GL_LINE_STIPPLE);
        }
        else
        {
            bool enable = true;
            switch (stipple)
            {
            case lineDash:
                glLineStipple(cast(GLint)(pixelsPerUnit_ * lineWidth_), 0x0F0F);
                break;
            case lineDot:
                glLineStipple(cast(GLint)(pixelsPerUnit_ * lineWidth_), 0x5555);
                break;
            case lineDashDot:
                glLineStipple(cast(GLint)(pixelsPerUnit_ * lineWidth_), 0x2727);
                break;
            case lineDashDotDot:
                glLineStipple(cast(GLint)(pixelsPerUnit_ * lineWidth_), 0x5757);
                break;
            default:
                glLineStipple(1, 0xFFFF);
                enable = false;
                break;
            }
            if (enable) glEnable(GL_LINE_STIPPLE);
            else glDisable(GL_LINE_STIPPLE);
        }
        glLineWidth(cast(GLfloat)(pixelsPerUnit_ * lineWidth_));
        glPointSize(cast(GLfloat) pixelsPerUnit_);
    }

    // ---- Fl_OpenGL_Graphics_Driver_vertex.cxx's end_*() family,
    // adapted to this port's pre-accumulated Point[] dispatch model
    // (see fl.graphics_driver.GraphicsDriver's own doc comment: by the
    // time any of these run, fl.draw has already applied the current
    // transform matrix to every vertex and handed over the flat,
    // already-int-rounded result -- there's no per-vertex glVertex()
    // call to make "live" the way FLTK's own transformed_vertex()
    // does while a path is still being accumulated).

    override void endPoints(const(Point)[] pts)
    {
        if (pts.length == 0) return;
        glBegin(GL_POINTS);
        foreach (p; pts) glVertex2f(p.x + 0.5f, p.y + 0.5f);
        glEnd();
    }

    override void endLine(const(Point)[] pts)
    {
        if (pts.length == 0) return;
        glBegin(GL_LINE_STRIP);
        foreach (p; pts) glVertex2i(p.x, p.y);
        glEnd();
    }

    override void endLoop(const(Point)[] pts)
    {
        if (pts.length == 0) return;
        glBegin(GL_LINE_LOOP);
        foreach (p; pts) glVertex2i(p.x, p.y);
        glEnd();
    }

    override void endPolygon(const(Point)[] pts)
    {
        if (pts.length == 0) return;
        glBegin(GL_POLYGON);
        foreach (p; pts) glVertex2i(p.x, p.y);
        glEnd();
    }

    /// Ported from `Fl_OpenGL_Graphics_Driver::end_complex_polygon()`'s
    /// `SLOW_COMPLEX_POLY` scanline fill -- see this module's own top
    /// comment for the GAP-marker simplification.
    override void endComplexPolygon(const(Point)[] pts)
    {
        int n = cast(int) pts.length;
        if (n < 2) return;

        static struct FPoint { float x, y; }
        auto v = new FPoint[n];
        foreach (i, p; pts)
            v[i] = FPoint(cast(float) p.x, cast(float) p.y - 0.1f);

        float xMin = v[0].x, xMax = v[0].x;
        int yMin = cast(int) v[0].y, yMax = yMin;
        foreach (i; 1 .. n)
        {
            if (v[i].x <= xMin) xMin = v[i].x;
            if (v[i].x >= xMax) xMax = v[i].x;
            int vy = cast(int) v[i].y;
            if (vy <= yMin) yMin = vy;
            if (vy >= yMax) yMax = vy;
        }

        auto nodeX = new float[n - 1];
        for (int y = yMin; y <= yMax; y++)
        {
            int nNodes = 0;
            foreach (i; 1 .. n)
            {
                auto v0 = v[i - 1];
                auto v1 = v[i];
                if ((v1.y < y && v0.y >= y) || (v0.y < y && v1.y >= y))
                {
                    float dy = v0.y - v1.y;
                    nodeX[nNodes++] = (fabs(dy) > 0.0001f)
                        ? v1.x + ((y - v1.y) / dy) * (v0.x - v1.x) : v1.x;
                }
            }

            int idx = 0;
            while (idx < nNodes - 1)
            {
                if (nodeX[idx] > nodeX[idx + 1])
                {
                    auto tmp = nodeX[idx];
                    nodeX[idx] = nodeX[idx + 1];
                    nodeX[idx + 1] = tmp;
                    if (idx) idx--;
                }
                else idx++;
            }

            for (int i = 0; i < nNodes; i += 2)
            {
                float x0 = nodeX[i];
                if (x0 >= xMax) break;
                float x1 = nodeX[i + 1];
                if (x1 > xMin)
                {
                    if (x0 < xMin) x0 = xMin;
                    if (x1 > xMax) x1 = xMax;
                    glRectf(x0 - 0.25f, cast(float) y, x1 + 0.25f, cast(float)(y + 1));
                }
            }
        }
    }

    // ---- Fl_OpenGL_Graphics_Driver_font.cxx -- see this module's own
    // top comment and fl.gl's own doc comment for the full mechanism.

    override void draw(const(char)[] str, int nChars, int x, int y)
    {
        import fl.gl : gl_draw;

        glRasterPos2i(x, y);
        gl_draw(str, nChars);
    }

    // ---- Fl_OpenGL_Graphics_Driver_image.cxx ----

    /**
     * `ImageBackgroundBox.draw()` (`source/test/gl_image.d`) calling
     * `Image.draw()` always goes through `fl.draw.drawImage()` ->
     * `currentDriver.drawImage()` when a `GraphicsDriver` is active,
     * same dispatch every other primitive in this class already uses.
     *
     * **Deliberately simpler than FLTK's real `Fl_OpenGL_Graphics_
     * Driver::draw_image()`**, which builds and caches a
     * `GL_TEXTURE_RECTANGLE_ARB` texture per source `Fl_Image*`
     * (`image_texture_map_`, with matching teardown machinery,
     * `delete_image_texture()`, for when the source image is freed --
     * the same real GC-lifetime question `fl.gl`'s own text-texture FIFO
     * had to solve for a different reason). This method instead forwards
     * straight to the already-real, already-verbatim-ported public
     * `fl.gl.gl_draw_image()` (FLTK's own simple, uncached
     * `glDrawPixels()`-based `FL/gl.h` function, `src/gl_draw.cxx`) --
     * correct, and re-uploads the pixel data fresh on every redraw
     * rather than caching a texture, but `gl_image.d`'s own repaint
     * cadence (window resize / a newly chosen file, not a
     * continuously-animating scene) makes that a non-issue in practice.
     * Revisit with a real texture cache only if a future GL-composited
     * consumer redraws the same image every frame.
     *
     * **The `glPixelZoom(1,-1)` bracket is required, not decoration**:
     * `glDrawPixels()` places source row 0 at the raster position and
     * extends *upward* in device space as the row index increases (the
     * same bottom-up convention `glReadPixels()` uses, and the classic
     * "OpenGL images render upside-down" gotcha) -- but `buf` here is
     * `fl.image.RGBImage.array`'s ordinary top-down row order (row 0 =
     * the image's own top row), matching every other consumer of this
     * buffer shape in this port (`fl.draw.drawImage()`'s own Xlib
     * path draws it correctly with no flip, since `XPutImage()` is
     * top-down natively). A negative Y zoom factor reverses
     * `glDrawPixels()`'s row-stacking direction to downward instead,
     * which combined with `(x,y)` already anchoring the image's
     * *top*-left corner (this class's own `glOrtho(0,w,h,0,-1,1)` in
     * `GlWindow.drawBegin()` already maps FLTK's top-left-origin,
     * y-down logical space onto device space correctly for that anchor
     * point -- see this module's own top comment) is exactly what's
     * needed to draw the buffer right-side-up.
     *
     * **Row-alignment fix**: `GL_UNPACK_ALIGNMENT` defaults to 4, meaning
     * `glDrawPixels()`/`glTexImage2D()` both assume each source row
     * starts on a 4-byte boundary unless told otherwise -- but `l`
     * (the real row stride) is only guaranteed 4-byte-aligned for
     * `d==4` (RGBA, always a multiple of 4 regardless of width); for
     * `d==3` (RGB, `fl.pixmap.Pixmap.draw()`'s always-3-bytes-per-pixel
     * XPM blit is a real, common example) an arbitrary image width
     * makes `w*3` a multiple of 4 only for 1 out of every 4 widths,
     * with GL silently misinterpreting the other 3/4 as if each row
     * were padded to a stride it isn't -- a classic, well-documented
     * OpenGL gotcha producing exactly this kind of sheared/warped
     * output. Ported from FLTK's own equivalent compensation in
     * `compute_texture_rectangle()` (`Fl_OpenGL_Graphics_Driver_
     * image.cxx`, the texture-cache path's own version of this same
     * fix): force `GL_UNPACK_ALIGNMENT` to `1` (always correct, just
     * forgoes a possible internal fast path) whenever `d<4` and the
     * real row stride isn't already a multiple of 4, restoring the
     * previous value afterward so this doesn't leak into unrelated
     * `glTexImage2D()`/`glReadPixels()` calls elsewhere.
     */
    override void drawImage(const(ubyte)* buf, int x, int y, int w, int h, int d, int l)
    {
        import fl.gl : gl_draw_image;

        int stride = l ? l : w * d;
        GLint prevAlignment;
        bool needsAlignmentFix = d < 4 && (stride % 4 != 0);
        if (needsAlignmentFix)
        {
            glGetIntegerv(GL_UNPACK_ALIGNMENT, &prevAlignment);
            glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
        }

        glPixelZoom(1.0f, -1.0f);
        gl_draw_image(buf, x, y, w, h, d, l);
        glPixelZoom(1.0f, 1.0f);

        if (needsAlignmentFix)
            glPixelStorei(GL_UNPACK_ALIGNMENT, prevAlignment);
    }

    /**
     * Draws a 1-bit stencil (the current `fl.draw` color showing
     * through "set" bits, fully transparent elsewhere). Builds a full
     * RGBA buffer (current color's RGB, alpha 255/0 for
     * set/clear bits -- the same construction `fl.svg_file_surface.
     * SvgGraphicsDriver.drawBitmap()` already uses for an analogous
     * "no per-object caching" driver) and draws it via the same
     * `gl_draw_image()` path `drawImage()` above already uses, leaning
     * on real GL alpha blending (`GL_BLEND`/`GL_SRC_ALPHA,
     * GL_ONE_MINUS_SRC_ALPHA`, already enabled globally -- see
     * `color()`'s own doc comment on `GlWindow.drawBegin()`'s setup)
     * for genuine per-pixel compositing, rather than that driver's own
     * non-compositing `<image>`-element embed.
     *
     * Deliberately NOT FLTK's own `Fl_OpenGL_Graphics_Driver::
     * draw_bitmap()` route (`bitmap_to_rgb1()` + `compute_texture_
     * rectangle()` + a persistent `image_texture_map_` cache keyed by
     * `Fl_Bitmap*`) -- same "no texture cache" simplification
     * `drawImage()` above already makes for the RGB case (see this
     * module's own top comment), just applied to the 1-bit path too:
     * this rebuilds and re-uploads the RGBA buffer fresh every call
     * rather than caching a GL texture keyed by image identity, correct
     * but less efficient for a repeatedly-redrawn bitmap.
     *
     * `w`/`h` (the requested destination *size*) aren't consulted --
     * `gl_draw_image()` has no destination-stretch primitive the way
     * GDI's `StretchBlt()` does (`fl.gdi_graphics_driver.
     * GdiGraphicsDriver.drawBitmap()`'s own real stretch), so the
     * buffer draws at its own native `dataW`x`dataH` pixel size,
     * matching `fl.postscript.PostscriptGraphicsDriver.drawBitmap()`'s
     * faithfully-reproduced FLTK quirk of the same shape (see that
     * method's own doc comment). `cx`/`cy` are honored as a real
     * position offset, matching `SvgGraphicsDriver.drawBitmap()`'s own
     * choice for the same reason -- `GraphicsDriver.drawBitmap()`'s own
     * doc comment leaves this to each concrete driver's discretion.
     */
    override void drawBitmap(const(ubyte)* bits, int dataW, int dataH, int x, int y, int w, int h, int cx, int cy)
    {
        if (dataW <= 0 || dataH <= 0 || bits is null) return;

        import fl.draw : colorToRgb8, fl_color;
        import fl.gl : gl_draw_image;

        ubyte r, g, b;
        colorToRgb8(fl_color(), r, g, b);

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
                        rgba[off] = r;
                        rgba[off + 1] = g;
                        rgba[off + 2] = b;
                        rgba[off + 3] = 255;
                    }
                    q >>= 1;
                }
            }
        }

        glPixelZoom(1.0f, -1.0f);
        gl_draw_image(rgba.ptr, x - cx, y - cy, dataW, dataH, 4, dataW * 4);
        glPixelZoom(1.0f, 1.0f);
    }

    /// Real GL already maps its logical-unit `glOrtho()` range onto the
    /// device-pixel `glViewport()` in hardware (`GlWindow.drawBegin()`),
    /// matching `Fl_OpenGL_Graphics_Driver::transformed_vertex()`'s own
    /// unscaled `glVertex2d()` call -- see `GraphicsDriver.
    /// wantsUnscaledVertices()`'s own doc comment for the full story.
    override bool wantsUnscaledVertices() const { return true; }
}
