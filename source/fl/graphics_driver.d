/*
 * New port of FL/Fl_Graphics_Driver.H (FLTK 1.5.0).
 *
 * Deliberately minimal, and deliberately *not* the same "no polymorphic
 * hierarchy" call this port made for `fl.platform_x11`/`fl.draw`'s own
 * X11 rendering: that call was correct as long as there was only ever
 * one concrete backend (X11/Xlib) to draw with, so a driver abstraction
 * would have had nothing to abstract over. That's no longer true.
 * `Fl_SVG_File_Surface` and `Fl_EPS_File_Surface` (see `PORTING.md`'s
 * "Printing / off-screen surfaces" section) both need to intercept the
 * exact same drawing calls every widget already makes (`fl_rect()`,
 * `fl_line()`, `fl_color()`, ...) and redirect them to a text-emitting
 * backend instead of Xlib -- two real, independent concrete
 * implementations (`fl.svg_file_surface.SvgGraphicsDriver`/
 * `fl.postscript.PostscriptGraphicsDriver`), which is exactly the
 * trigger this port's own convention (see `fl.image_surface`'s
 * `SurfaceDevice`, `fl.core`'s module notes) names as justifying an
 * abstraction. `Fl_PostScript_File_Device` (`fl.postscript.
 * PostscriptFileDevice`) is real too now, reusing `PostscriptGraphicsDriver`
 * directly rather than needing a third consumer -- only `Fl_Printer`
 * itself (its own `print_panel` dialog plus `popen` spooling, unrelated
 * to this abstraction) remains unstarted, see `FL/Fl_Printer.H`'s
 * `PORTING.md` row. **A third real consumer**: `fl.gl_graphics_driver.
 * GlGraphicsDriver` redirects the
 * same primitives through OpenGL calls, backing `fl.gl_window.
 * GlWindow`'s "ordinary FLTK widgets composited over a GL scene"
 * support (the `test/cube.cxx` case) -- see that module's own doc
 * comment for which primitives it implements (a strict subset of
 * FLTK's own `Fl_OpenGL_Graphics_Driver`, scoped to what a real
 * widget tree's `draw()` actually reaches).
 *
 * FLTK's `Fl_Graphics_Driver` is ~60 virtual methods covering every
 * primitive fl_draw.H exposes, plus image caching, region/clip
 * bookkeeping, and font-metrics plumbing. Building all of that up front
 * with only one real consumer in view (SVG output) would be exactly the
 * kind of speculative scope CONVENTIONS.md warns against. This starts with
 * the smallest slice that lets one full primitive family (color +
 * filled/outline rects + lines + polygons) round-trip end to end through
 * a real subclass (`fl.svg_file_surface.SvgGraphicsDriver`) -- grow this
 * class's method list the same way, one verified primitive family at a
 * time, as PostScript/further SVG coverage (text, images, clipping, arcs)
 * need more of them. Don't add a virtual here "for completeness" ahead of
 * a real caller.
 *
 * Dispatch model: unlike FLTK, where `fl_graphics_driver` always
 * points at *some* concrete driver (a real `Fl_Xlib_Graphics_Driver` even
 * for plain on-screen drawing), this port's `fl.draw` leaf primitives
 * still call Xlib/Xft directly by default -- there is no
 * "NativeGraphicsDriver" class duplicating that code as a subclass here,
 * matching the reasoning above for why a hierarchy wasn't built for X11
 * alone. `currentDriver is null` means "use fl.draw's existing direct
 * Xlib/Xft path, unchanged"; a non-null `currentDriver` means "delegate
 * to this instead." This mirrors the precedent already established by
 * `fl.image_surface.SurfaceDevice.surface() is null` meaning "the
 * display" -- null-means-default is this codebase's own house style, not
 * a deviation invented for this module.
 */
module fl.graphics_driver;

import fl.enumerations : Color;

/// A single point in a dispatched vertex path (`fl.draw`'s own
/// `VPoint` widened from `short` to `int`, and made public -- a
/// `GraphicsDriver` subclass has no other way to see what
/// `vertex()`/`fl_begin_*()` accumulated). See `GraphicsDriver.
/// endLine()`/`endLoop()`/`endPolygon()`/`endPoints()`/
/// `endComplexPolygon()`.
struct Point
{
    int x, y;
}

/**
 * Ported (minimally, see this module's own top comment) from
 * `Fl_Graphics_Driver` (`FL/Fl_Graphics_Driver.H`). Each abstract method
 * below corresponds to one of `fl.draw`'s own leaf primitives (the ones
 * that call into `fl.xlib`/`fl.xft` directly, as opposed to a primitive
 * that's purely a composition of other primitives, e.g. `fl_rect(...,
 * Color)`, which composes `fl_color()` + `fl_rect(...)` and therefore
 * needs no entry here -- it routes correctly for free once its two
 * leaves dispatch correctly). See each `fl.draw` leaf function's own doc
 * comment for the exact pixel semantics a subclass must match.
 *
 * **Not covered**: rotated text (`fl.draw`'s own `fl_draw(int angle,
 * ...)` composes from the plain `draw()` leaf below and ignores `angle`
 * entirely on the native path, matching FLTK's own base
 * `Fl_Graphics_Driver::draw(int angle,...)` -- only FLTK's SVG/GL/
 * Quartz drivers give this real rotation, which would need its own
 * dispatch leaf here; not added yet since no caller needs it). Images
 * (`drawImage()`/`drawBitmap()` below) *are* covered: `fl.image`'s
 * PNG/JPEG codecs back real embedded-image support in
 * `fl.svg_file_surface.SvgGraphicsDriver`.
 */
abstract class GraphicsDriver
{
    /// See `fl.draw.fl_color(Color)`.
    abstract void color(Color c);

    /// See `fl.draw.fl_rectf(int, int, int, int)` (the 4-arg leaf --
    /// draws in the current color()).
    abstract void rectf(int x, int y, int w, int h);

    /// See `fl.draw.fl_rect(int, int, int, int)` (the 4-arg leaf --
    /// draws in the current color()).
    abstract void rect(int x, int y, int w, int h);

    /// See `fl.draw.fl_line(int, int, int, int)` (the 4-arg leaf).
    abstract void line(int x, int y, int x1, int y1);

    /// See `fl.draw.fl_xyline(int, int, int)` (the 3-arg leaf).
    abstract void xyline(int x, int y, int x1);

    /// See `fl.draw.fl_yxline(int, int, int)` (the 3-arg leaf).
    abstract void yxline(int x, int y, int y1);

    /// See `fl.draw.fl_polygon(int, int, int, int, int, int)` (the
    /// 3-point leaf -- fills in the current color()).
    abstract void polygon(int x, int y, int x1, int y1, int x2, int y2);

    /// See `fl.draw.fl_polygon(int, int, int, int, int, int, int, int)`
    /// (the 4-point leaf -- fills in the current color()).
    abstract void polygon(int x, int y, int x1, int y1, int x2, int y2, int x3, int y3);

    /// See `fl.draw.loop()` (the 3-point outline). The default draws
    /// three `line()`s; the GDI+ driver overrides it with one joined
    /// path, as FLTK's `Fl_GDIplus_Graphics_Driver::loop()` does.
    void loop(int x0, int y0, int x1, int y1, int x2, int y2)
    {
        line(x0, y0, x1, y1);
        line(x1, y1, x2, y2);
        line(x2, y2, x0, y0);
    }

    /// See `fl.draw.loop()` (the 4-point outline). ditto
    void loop(int x0, int y0, int x1, int y1, int x2, int y2, int x3, int y3)
    {
        line(x0, y0, x1, y1);
        line(x1, y1, x2, y2);
        line(x2, y2, x3, y3);
        line(x3, y3, x0, y0);
    }

    /// See `fl.draw.lineStyle(int, int, const(ubyte)[])`. No
    /// implicit "current" tracking is assumed here -- a subclass that
    /// cares about stroke width/dash/cap/join for later `line()`/
    /// `rect()`/etc. calls (as `fl.svg_file_surface.SvgGraphicsDriver`
    /// does) must remember these itself, matching how the native path's
    /// own X11 GC remembers them.
    abstract void lineStyle(int style, int width, const(ubyte)[] dashes);

    /// See `fl.draw.pushClip(int, int, int, int)`. Unlike the other
    /// methods here, this is called with the *already-intersected*
    /// clip rectangle (`fl.draw`'s own clip-stack bookkeeping runs
    /// unconditionally, dispatched driver or not -- see that function's
    /// own doc comment), not the raw incoming arguments.
    abstract void pushClip(int x, int y, int w, int h);

    /// See `fl.draw.popClip()`. `fl.draw`'s own clip-stack pop always
    /// happens regardless of dispatch (same reasoning as `pushClip()`
    /// above); this is purely the driver's own notification to close
    /// whatever `pushClip()` opened. **`fl.draw.pushNoClip()` has
    /// no matching driver hook** -- a real, deliberate gap: FLTK's
    /// own `Fl_SVG_Graphics_Driver::push_no_clip()` closes every
    /// currently-open clip `<g>`, then reopens them all on the matching
    /// `pop_clip()` once the no-clip scope ends, real bookkeeping this
    /// minimal `GraphicsDriver` doesn't have a hook for yet -- no
    /// caller in this port's tree needs it.
    abstract void popClip();

    /// See `fl.draw.fl_arc(int, int, int, int, double, double)` (the
    /// unfilled outline leaf).
    abstract void arc(int x, int y, int w, int h, double a1, double a2);

    /// See `fl.draw.fl_pie(int, int, int, int, double, double)` (the
    /// filled leaf).
    abstract void pie(int x, int y, int w, int h, double a1, double a2);

    /// See `fl.draw.endPoints()` -- ends a `beginPoints()` path.
    /// `pts` is the accumulated, already-transformed vertex list.
    abstract void endPoints(const(Point)[] pts);

    /// See `fl.draw.endLine()` -- ends a `beginLine()` path (an
    /// open polyline).
    abstract void endLine(const(Point)[] pts);

    /// See `fl.draw.endLoop()` -- ends a `beginLoop()` path (a
    /// closed, unfilled outline). **Not part of FLTK's own
    /// `Fl_SVG_Graphics_Driver` override list** -- FLTK's SVG driver
    /// leaves this one to `Fl_Graphics_Driver`'s base implementation
    /// (undocumented what that does without a real device backing it);
    /// this port's own `fl.draw.endLoop()` is a genuine leaf
    /// (calls `XDrawLines()` directly, not routed through `endLine()`),
    /// so it gets a real dispatch hook here regardless -- see
    /// `SvgGraphicsDriver.endLoop()`'s own doc comment for the SVG
    /// element it was given, a reasonable-but-not-FLTK-sourced
    /// choice.
    abstract void endLoop(const(Point)[] pts);

    /// See `fl.draw.endPolygon()` -- ends a `beginPolygon()`
    /// path (closed, filled, convex).
    abstract void endPolygon(const(Point)[] pts);

    /// See `fl.draw.endComplexPolygon()` -- ends a
    /// `beginComplexPolygon()` path (closed, filled, possibly
    /// concave/multi-loop; `fl_gap()` has already split it into
    /// sub-loops by the time this runs, folded into a single flat
    /// `pts` list the same way the native XFillPolygon path uses it).
    abstract void endComplexPolygon(const(Point)[] pts);

    /// What `fl.draw.endComplexPolygon()` actually calls: the same flat
    /// `pts`, plus the point count of each closed sub-loop `fl_gap()`
    /// made (they add up to `pts.length`). The default ignores
    /// `counts`; the GDI driver uses them for `PolyPolygon()`, as FLTK's
    /// `Fl_GDI_Graphics_Driver::end_complex_polygon()` does, because a
    /// single `Polygon()` would outline the edges joining the sub-loops.
    void endComplexPolygonParts(const(Point)[] pts, const(int)[] counts)
    {
        endComplexPolygon(pts);
    }

    /// See `fl.draw.fl_draw(const(char)[], int, int, int)` (the 3-arg
    /// positional leaf every other `fl_draw()` text overload composes
    /// from). Current font/size are *not* passed here -- query
    /// `fl.draw.fl_font()`/`fl.draw.fl_size()` (both always real,
    /// undispatched -- see this class's own doc comment on why text
    /// metrics never dispatch) at call time, matching how FLTK's
    /// own `Fl_SVG_Graphics_Driver::draw()` reads its own `family_`/
    /// `bold_`/`style_` members that `font()` filled in ahead of time.
    abstract void draw(const(char)[] str, int nChars, int x, int y);

    /**
     * Draws `str` at `(x,y)`, rotated `angle` degrees counterclockwise
     * -- see `fl.draw.fl_draw(int, const(char)[], int, int, int)`.
     * Ported from `Fl_Graphics_Driver::draw(int, const char*, int, int,
     * int)` (`src/Fl_Graphics_Driver.cxx`): FLTK's own base
     * implementation is a real, non-abstract default that just ignores
     * `angle` and forwards to the plain `draw()` above -- not a
     * placeholder; most FLTK drivers, including the plain (non-Xft)
     * X11 one, never override it at all (it prints a one-time "rotated
     * text not implemented" warning and draws unrotated instead -- see
     * `Fl_Xlib_Graphics_Driver_font_x.cxx`'s own `draw_unscaled(int
     * angle, ...)`). This D port matches that shape: a real, non-
     * `abstract` default here (so `PostscriptGraphicsDriver`/
     * `SvgGraphicsDriver` don't need to implement it just to compile),
     * overridable by any concrete driver that wants real rotated
     * output (SVG's own `transform="rotate(...)"`, PostScript's own
     * `rotate` operator, ...) -- matching FLTK's own small set of
     * overriders (OpenGL, Quartz, and FLTK's SVG-file-export
     * driver, none of which are ported here yet either). See
     * `fl.draw.fl_draw(int, ...)`'s own doc comment for why this port's
     * *screen/offscreen* Xft-backed text path -- unlike FLTK's own
     * real, default (Xft-enabled) X11 build -- doesn't yet do real
     * rotation either, a genuine, currently-open gap, not FLTK's
     * own angle-ignoring behavior faithfully reproduced.
     */
    void draw(int angle, const(char)[] str, int nChars, int x, int y)
    {
        draw(str, nChars, x, y);
    }

    /**
     * Draws an 8-bit-per-channel image, `buf` pointing at the top-left
     * pixel -- see `fl.draw.drawImage()`. `d` is 1 (gray), 2
     * (gray+alpha), 3 (RGB), or 4 (RGBA), optionally *negated* to mean
     * the horizontally-flipped source layout `fl.draw.drawImage()`'s
     * own doc comment documents in full (pixel pointer steps left,
     * pixel bytes still read forward, `|d|` doing all the sizing and
     * classifying); `l` is the byte stride between rows (0 means
     * `w*|d|`; a negative `l` is the vertical-flip form). An override
     * that can't honor the flipped forms should at minimum size its
     * buffers from `|d|` rather than `d`. Ported from `Fl_Graphics_Driver::draw_image(const uchar*,
     * int,int,int,int,int,int)` -- FLTK splits this from a separate
     * `draw_image_mono()` for the `d<3` case, but this port's own
     * `fl.draw.drawImage()`/`drawImageFixed()` (the only real callers so
     * far -- both `fl.image.RGBImage.draw()` and `fl.pixmap.Pixmap.
     * draw()` already pre-crop/pre-resample to a final raw buffer,
     * already at its real target pixel size, before calling
     * `drawImageFixed()`, for any `d`) already handle every `d` through
     * one entry point,
     * so a concrete override branches internally instead (matching
     * `PostscriptGraphicsDriver.drawImage()`'s own doc comment for the
     * exact split). A real, non-`abstract` no-op default, same "grows
     * one verified primitive family at a time" shape as `draw(int,...)`
     * above; `PostscriptGraphicsDriver`, `SvgGraphicsDriver` (base64-PNG
     * `<image>` elements), `GlGraphicsDriver`, and `GdiGraphicsDriver`
     * (real `StretchDIBits()`/`AlphaBlend()` compositing) all override it
     * for real now.
     */
    void drawImage(const(ubyte)* buf, int x, int y, int w, int h, int d, int l) { }

    /**
     * Draws a buffer that a caller (`fl.image.RGBImage.draw()`/
     * `fl.pixmap.Pixmap.draw()`) has *already* resampled to its exact
     * target device-pixel size -- see `fl.draw.drawImageFixed()`'s own
     * doc comment for the full contract this splits off from
     * `drawImage()` above. `drawW`/`drawH`/`drawL` describe `buf`'s own
     * real pixel dimensions/stride and must be used *exactly as given*,
     * with **no further resampling** -- only `(x,y)` (the FLTK-unit
     * destination position) still needs converting to device pixels.
     *
     * This exists so `fl.draw.drawImageFixed()` can tell a
     * `GraphicsDriver` implementation apart from a plain `drawImage()`
     * call, since both would otherwise dispatch to the exact same
     * `drawImage(buf, x, y, w, h, d, l)` method with no signal that `w`/
     * `h` here already *are* the final device-pixel size rather than an
     * FLTK-unit box still needing its own scale-up (`GdiGraphicsDriver`'s
     * own doc comment on its override has the full story: a driver whose
     * `drawImage()` scales `w`/`h` internally would otherwise
     * double-scale every `drawImageFixed()` call -- every on-screen
     * `Fl_RGB_Image`/`Fl_Pixmap`, in practice, since those are
     * `drawImageFixed()`'s only real callers).
     *
     * The default here just forwards to `drawImage()` unchanged --
     * zero behavior change for `GlGraphicsDriver`/`PostscriptGraphicsDriver`/
     * `SvgGraphicsDriver`, none of which need the distinction (`GlGraphicsDriver`'s
     * own `drawImage()` already blits `buf` at literal `w`x`h` pixels
     * with no internal scale-up, i.e. it was already behaving like this
     * method the whole time; the surface drivers render at a fixed,
     * scale-independent `1.0`). Only `GdiGraphicsDriver` overrides this
     * for real.
     */
    void drawImageFixed(const(ubyte)* buf, int drawW, int drawH, int drawL, int d, int x, int y)
    {
        drawImage(buf, x, y, drawW, drawH, d, drawL);
    }

    /**
     * Draws a 1-bit bitmap (a `Fl_Bitmap`'s stencil pattern, the
     * current `color()` showing through set bits) -- see
     * `fl.draw.drawBitmapFixed()`. `bits` is `dataH` rows of
     * `(dataW+7)/8` bytes each (the bitmap's *full* data, regardless of
     * any `cx`/`cy` crop -- matching a real, faithfully-ported FLTK
     * quirk, see `PostscriptGraphicsDriver.drawBitmap()`'s own doc
     * comment for why); `(x,y,w,h)` is the destination rectangle,
     * `(cx,cy)` the crop offset a concrete driver may honor or ignore.
     * Ported from `Fl_Graphics_Driver::draw_bitmap(Fl_Bitmap*,...)`
     * (FLTK takes the whole `Fl_Bitmap*` object; this port only
     * ever has the raw bits by the point `drawBitmapFixed()` calls this,
     * so the signature is narrowed to just what a driver could actually
     * need). Non-`abstract` no-op default, same reasoning as
     * `drawImage()` above.
     */
    void drawBitmap(const(ubyte)* bits, int dataW, int dataH, int x, int y, int w, int h, int cx, int cy) { }

    /**
     * Gets/sets the "antialias" hint -- see `fl.draw.antialias()`/
     * `antialias(int)`, which forward here. Ported from `Fl_Graphics_
     * Driver::antialias(int)`/`antialias()` (`src/Fl_Graphics_Driver.cxx`):
     * FLTK's own base implementation is a real, non-`abstract`
     * no-op pair -- `antialias(int)`'s body is literally empty, and
     * `antialias()` unconditionally `return 0;`s, not even tracking
     * what was last set. Only FLTK's Cairo/Pango-backed drivers
     * (this port doesn't have) and its Windows GDI+ driver
     * (`fl.gdiplus_graphics_driver.GdiPlusGraphicsDriver`, the first
     * concrete override in this port) actually make this do anything.
     */
    int antialias() { return 0; }
    void antialias(int state) { } /// ditto

    /**
     * Whether this driver wants raw, matrix-transformed-but-not-
     * `screenScale()`-multiplied coordinates from `fl.draw`'s vertex-
     * path family (`vertex()`/`transformedVertex()`/`circle()`/
     * `curve()`, funneled through `appendVertexPoint()`) -- `false`
     * (the default) for a driver that instead wants coordinates
     * pre-scaled to device pixels, the same contract `fl.draw`'s
     * native (`currentDriver is null`) Xlib path and the Windows GDI/
     * GDI+ drivers share.
     *
     * Mirrors a real split in FLTK's own class hierarchy.
     * `Fl_Scalable_Graphics_Driver` -- the class `screenScale()`-baking
     * behavior above is ported from -- is FLTK's base for
     * pixel-raster backends physically tied to one screen's
     * device-pixel density (Xlib/Xft, GDI, Cairo). `Fl_OpenGL_Graphics_
     * Driver` and `Fl_PostScript_Graphics_Driver` both extend the
     * *plain* `Fl_Graphics_Driver` directly instead and receive raw,
     * unscaled coordinates: GL because its `glOrtho()`/`glViewport()`
     * split already maps logical units onto device pixels in hardware
     * (`fl.gl_window.GlWindow.drawBegin()`) -- double-applying
     * `screenScale()` before that hand-off scaled twice -- and
     * PostScript/SVG because a vector document has no "screen" to be
     * device-pixel-dense relative to in the first place.
     * `GlGraphicsDriver`/`PostscriptGraphicsDriver`/`SvgGraphicsDriver`
     * all override this to `true`; `GdiGraphicsDriver`/
     * `GdiPlusGraphicsDriver` (Windows' `currentDriver`, unlike Linux
     * where `currentDriver is null` means "use the native path" --
     * see `fl.platform_win32.ensureGraphicsDriver()`'s own doc comment)
     * correctly keep the default `false`, since GDI *is* this port's
     * `Fl_Scalable_Graphics_Driver`-equivalent backend.
     */
    bool wantsUnscaledVertices() const { return false; }
}

/**
 * The driver `fl.draw`'s leaf primitives dispatch to when non-null (see
 * this module's own top comment for the null-means-native model).
 * Deliberately plain module-level state, not `__gshared`: drawing in
 * this port is main-thread-only already (a single X `Display*`/GC
 * threaded through `fl.draw`'s own module-level state the same way),
 * so D's default thread-local storage is the correct, deliberate choice
 * here, not an oversight -- see CONVENTIONS.md's own note on `__gshared` vs.
 * thread-local globals for when the *other* choice is required (genuine
 * cross-thread state, which this isn't).
 */
package(fl) GraphicsDriver currentDriver;
