/*
 * Ported from FL/Fl_Device.H (the `Fl_Surface_Device` half only) and
 * FL/Fl_Image_Surface.H + src/Fl_Image_Surface.cxx +
 * src/drivers/Xlib/Fl_Xlib_Image_Surface_Driver.cxx (FLTK 1.5.0).
 *
 * Deliberately minimal, matching this port's "no polymorphic hierarchy
 * for a single implementation" precedent (see `fl.platform_x11`'s own
 * top comment; `fl.graphics_driver.GraphicsDriver` is not an
 * example of that precedent -- `Fl_SVG_File_Surface`/
 * `Fl_PostScript_File_Device` are real second/third consumers, see
 * that module's own doc comment): FLTK
 * splits this across an abstract `Fl_Image_Surface` (public API) plus a
 * per-platform
 * `Fl_Image_Surface_Driver` subclass (`Fl_Xlib_Image_Surface_Driver` on
 * X11); with only X11 targeted, that split has no second implementation
 * to justify it, so `ImageSurface` here folds the Xlib driver's own body
 * straight into the concrete class. Likewise `Fl_Surface_Device` here is
 * `SurfaceDevice`, kept only because the samples that need `ImageSurface`
 * (`examples/shapedwindow.cxx`, `test/device.cxx`) name it directly
 * (`Fl_Surface_Device::push_current()`/`pop_current()`).
 *
 * `ImageSurface` reuses `fl.draw`'s own existing
 * `beginOffscreen()`/`endOffscreen()` (a real, already-tested
 * drawable-redirect stack, ported for `test/offscreen.cxx`) to actually
 * redirect drawing, rather than duplicating that stack here -- `doSetCurrent()`/
 * `doEndCurrent()` are thin calls into it. `image()` reads the finished
 * offscreen buffer back via `fl.draw.readPixelsFromDrawable()` (the same
 * `XGetImage()`-based primitive `fl.core`'s clipboard-image and
 * `fl_read_image()` already use).
 *
 * `ImageSurface` extends `fl.widget_surface.WidgetSurface` (not
 * `SurfaceDevice` directly), which is where `draw(Widget)`/
 * `drawDecoratedWindow()` live -- see that module for the full
 * `Fl_Widget_Surface` port, backing `test/device.cxx`'s
 * "Fl_Image_Surface" demo button.
 *
 * `test/device.cxx`'s "Fl_Image_Surface" radio button is only one of
 * five surface types it exercises (`Fl_Copy_Surface`, `Fl_PDF_File_Surface`,
 * `Fl_SVG_File_Surface`, and `ImageSurface.mask()`'s shaped-window-in-
 * miniature demo are the other four) -- none of those are ported here,
 * so `test/device.cxx` still doesn't build. See `PORTING.md`'s
 * `FL/Fl_Copy_Surface.H`/`FL/Fl_PDF_File_Surface.H`/
 * `FL/Fl_SVG_File_Surface.H` rows for the current status of each.
 *
 * `mask()` is ported from
 * `Fl_Xlib_Image_Surface_Driver::mask()`'s non-Cairo branch (the `#else`
 * half of `src/drivers/Xlib/Fl_Xlib_Image_Surface_Driver.cxx`, matching
 * this port's own plain-Xlib drawing stack, not the Cairo branch): it
 * doesn't install a live clip during drawing at all -- it snapshots the
 * surface's current content into a separate `maskBackground_` pixmap
 * (`fl.draw.createOffscreenBuffer()`/`copyPixmapToPixmap()`, the latter
 * a new primitive since `mask()`'s own doc comment, matching FLTK,
 * requires the surface NOT be current when called, so the existing
 * current-drawable-only `copyOffscreen()` doesn't apply), then the
 * actual masking happens lazily, later, inside `image()`: it blends the
 * "before" (`maskBackground_`) and "after" (whatever got drawn on top
 * since `mask()`) pixmaps pixel-by-pixel, weighted by a depth-1
 * luminance mask derived from the caller's RGB mask image
 * (`rgb3ToRgb1()`/`copyWithMask()` below, ported from
 * `Fl_Image_Surface_Driver::RGB3_to_RGB1()`/`copy_with_mask()`, the
 * shared, platform-independent halves in `src/Fl_Image_Surface.cxx`),
 * then writes the blended result back into the surface's own offscreen
 * buffer (via the existing `beginOffscreen()`/`endOffscreen()`
 * stack, so a subsequent independent `mask()` call after a further
 * `image()` call works too, matching FLTK's own documented "several
 * masks in succession" support) before returning it as the caller's
 * `RGBImage`.
 *
 * On Windows, `mask()` follows `Fl_GDI_Image_Surface_Driver::mask()`/
 * `image()` the same way: the snapshot is the offscreen's pixels read
 * back as RGB, and the blend is written back with
 * `fl.draw.writePixelsToDrawable()` (FLTK's `SetDIBits()`).
 *
 * `highRes`/`rescale()`/`printableRect()` are all real:
 * `highRes` (`device.d`/`sudoku.d` both already
 * construct with it) sizes the offscreen buffer at
 * `fl.core.currentScale()` device pixels per FLTK unit, matching every
 * `Fl_*_Image_Surface_Driver` constructor's own `if (d != 1 &&
 * high_res) { w = int(w*d); h = int(h*d); }`; `image()` scales the
 * returned `RGBImage`'s display size back down to the surface's logical
 * FLTK-unit size (`Fl_Image_Surface::image()`'s own `img->scale(...)`
 * call); and `rescale()`/`printableRect()` are real ports of their own
 * FLTK namesakes. Still not ported: `highres_image()` (a documented
 * `Fl_Shared_Image`-returning `deprecated` convenience wrapper around
 * `image()`+`printable_rect()`, both already real here -- no caller
 * needs the wrapper itself) and the externally-owned-offscreen
 * constructor overload (`Fl_Offscreen off` parameter) -- no caller needs
 * either.
 */
module fl.image_surface;

import fl.image : RGBImage;
import fl.widget_surface : WidgetSurface;
import fldraw = fl.draw;
import graphicsDriver = fl.graphics_driver;
import fl.graphics_driver : GraphicsDriver;
version (linux) import platformX11 = fl.platform_x11;
version (Windows) import platformWin32 = fl.platform_win32;

/**
 * Ported from `Fl_Surface_Device` (`FL/Fl_Device.H` + `src/Fl_Device.cxx`).
 * Tracks which drawing surface is "current" -- a real stack, matching
 * FLTK's own `push_current()`/`pop_current()` semantics (nested
 * `pushCurrent()`/`popCurrent()` pairs are fully supported, even though
 * no sample in this port's tree nests them today). `surface()`
 * returning `null` for "the display" (rather than a real
 * `Fl_Display_Device` singleton) is the one deliberate simplification --
 * nothing in this port needs to distinguish "no surface pushed" from "a
 * distinct display-device object," since ordinary widget drawing already
 * works correctly with `fl.draw`'s own default drawable untouched.
 */
class SurfaceDevice
{
    private static SurfaceDevice current_;
    private static SurfaceDevice[] stack_;
    // Parallel to `stack_` -- the real `graphicsDriver.currentDriver`
    // value in effect *before* each `pushCurrent()`, so `popCurrent()`
    // can restore it exactly rather than re-derive it from the restored
    // surface's own `driver_` (see `pushCurrent()`'s own doc comment for
    // why re-deriving it that way is wrong).
    private static GraphicsDriver[] driverStack_;
    private GraphicsDriver driver_;

    /// Ported from `Fl_Surface_Device(Fl_Graphics_Driver*)`. `driver`
    /// is `null` for any surface that draws by redirecting `fl.draw`'s
    /// existing Xlib output somewhere else (`ImageSurface`/`CopySurface`
    /// redirect the X11 drawable itself via `doSetCurrent()`/
    /// `doEndCurrent()`, see those classes) rather than by intercepting
    /// individual primitive calls -- only a real `GraphicsDriver`
    /// subclass (e.g. `fl.svg_file_surface.SvgGraphicsDriver`) passes
    /// one here.
    this(GraphicsDriver driver = null)
    {
        driver_ = driver;
    }

    /// Ported from `Fl_Surface_Device::driver()`.
    final GraphicsDriver driver() { return driver_; }

    /// Ported from `Fl_Surface_Device::surface()`. `null` means "the
    /// display" -- see this class's own doc comment.
    static SurfaceDevice surface() { return current_; }

    /// Ported from `Fl_Surface_Device::is_current()`.
    final bool isCurrent() const { return current_ is this; }

    /**
     * Ported from `~Fl_Surface_Device()`: `if (surface_ == this)
     * surface_ = NULL;`. Not just a formality -- both `shapedwindow.d`
     * and `test/device.cxx` faithfully transliterate FLTK's own
     * `delete surf; SurfaceDevice.popCurrent();` ordering (`prepare_
     * shape()`, `examples/shapedwindow.cxx`), deleting a still-current
     * surface *before* popping it. FLTK relies on exactly this
     * destructor to make that safe: `pop_current()` calls `set_current()`
     * on the *restored* (previous) surface, which internally does `if
     * (surface_) surface_->end_current();` -- without this guard,
     * `surface_` would still point at the just-deleted object, so that
     * call would dispatch a virtual method through a dangling pointer.
     * Without the guard `popCurrent()` crashes inside
     * `current_.doEndCurrent()` on a destroyed `ImageSurface`.
     * No `GC.inFinalizer()` concern (see CONVENTIONS.md's own note on that
     * hazard) -- this only nulls a static reference, never dereferences
     * another object.
     */
    ~this()
    {
        if (current_ is this) current_ = null;
    }

    /// Hook for a concrete surface to redirect drawing to itself.
    /// Ported from the *body* of each driver's own `set_current()`
    /// override (e.g. `Fl_Xlib_Image_Surface_Driver::set_current()`) --
    /// `Fl_Surface_Device::set_current()` itself (the dispatch/bookkeeping
    /// half) is handled by `pushCurrent()`/`popCurrent()` below instead.
    protected void doSetCurrent() {}

    /// Hook for a concrete surface to undo whatever `doSetCurrent()` did.
    /// Ported from each driver's own `end_current()` override.
    protected void doEndCurrent() {}

    /**
     * Ported from `Fl_Surface_Device::push_current(Fl_Surface_Device*)`.
     * Also syncs `fl.draw`'s `currentDriver` to `newCurrent`'s own
     * `driver()` when it actually has one (matching FLTK's
     * `Fl_Surface_Device::surface()->driver()`/`fl_graphics_driver`
     * invariant: whichever driver the newly-current surface names is
     * what every `fl.draw` leaf primitive dispatches to from here on) --
     * see `fl.graphics_driver`'s own doc comment for the null-means-
     * native model this composes with.
     *
     * Whether a driver-less surface overwrites `currentDriver` with
     * `null` (rather than leaving the ambient driver alone) is
     * platform-specific, not a single universal answer.
     *
     * On Linux, `fl.draw` genuinely treats `currentDriver == null` as
     * "the native Xlib/Xft path" (see `fl.graphics_driver`'s own doc
     * comment) -- exactly the fallback `ImageSurface`/`CopySurface`
     * want when pushed over *any* other driver, GL included, so Linux
     * always follows `driver_` verbatim, `null` included. This matters:
     * `alphaMaskForString()` pushes a driver-less `ImageSurface` to
     * render a GL label's texture via the plain, native `fl_draw()`
     * leaf, so `currentDriver` must actually become `null` there rather
     * than staying `GlGraphicsDriver` -- otherwise `fl_draw()` would
     * dispatch straight back into `GlGraphicsDriver.draw()` ->
     * `gl_draw()` -> `drawStringWithTexture()` -> `computeTexture()` ->
     * `alphaMaskForString()` -> ... forever, exhausting the stack.
     *
     * On Windows, there is no such native fallback -- every `fl.draw`
     * primitive requires a real `GdiGraphicsDriver` to do anything at
     * all. `ImageSurface`/`CopySurface` have `driver_ == null` for a
     * completely different reason there (see this class's own
     * constructor doc comment: they redirect the *existing* driver's
     * output via `doSetCurrent()`, they don't want no driver at all), so
     * unconditionally overwriting `currentDriver` to `null` right before
     * `doSetCurrent()` -> `beginOffscreen()` needs it would silently
     * break every `fl.draw` primitive for the rest of the surface's
     * lifetime (`beginOffscreen()`'s own `if (driver is null...) return;`
     * guard) -- and, since this port's `ensureGraphicsDriver()` is
     * idempotent (`if (gdiDriver_ !is null) return;`), nothing would
     * ever re-fix it afterward either, breaking the real window's own
     * later drawing too. Windows only overwrites `currentDriver` when
     * the surface actually names a driver of its own.
     *
     * Either way, saving/restoring the *real* previous `currentDriver`
     * value on a parallel stack (`driverStack_`) is what makes both
     * platforms' behavior correct, rather than re-deriving it from the
     * surface being restored's own `driver_` -- re-deriving it that way
     * would "restore" to `null` when popping back to a driver-less
     * surface or to the display, discarding whatever ambient driver --
     * the real `GdiGraphicsDriver` on Windows -- was actually active
     * before any of this pushing started.
     */
    static void pushCurrent(SurfaceDevice newCurrent)
    {
        stack_ ~= current_;
        driverStack_ ~= graphicsDriver.currentDriver;
        current_ = newCurrent;
        version (linux)
            graphicsDriver.currentDriver = newCurrent !is null ? newCurrent.driver_ : null;
        else
        {
            if (newCurrent !is null && newCurrent.driver_ !is null)
                graphicsDriver.currentDriver = newCurrent.driver_;
        }
        if (newCurrent !is null) newCurrent.doSetCurrent();
    }

    /// Ported from `Fl_Surface_Device::pop_current()`. Restores
    /// `fl.draw`'s `currentDriver` to exactly what it was before the
    /// matching `pushCurrent()` -- see that function's own doc comment
    /// for why this is a real saved/restored value (`driverStack_`), not
    /// re-derived from the surface being popped back to.
    static SurfaceDevice popCurrent()
    {
        if (stack_.length == 0) return current_;
        if (current_ !is null) current_.doEndCurrent();
        current_ = stack_[$ - 1];
        stack_.length -= 1;
        graphicsDriver.currentDriver = driverStack_[$ - 1];
        driverStack_.length -= 1;
        return current_;
    }
}

/**
 * Ported from `Fl_Image_Surface` (`FL/Fl_Image_Surface.H`) +
 * `Fl_Xlib_Image_Surface_Driver` (`src/drivers/Xlib/
 * Fl_Xlib_Image_Surface_Driver.cxx`) -- see this module's own top
 * comment for what's folded together and what's cut. Directs all
 * `fl.draw` drawing requests to an off-screen buffer while current
 * (`SurfaceDevice.pushCurrent(surf)` ... draw ... `SurfaceDevice.popCurrent()`),
 * then `image()` reads the result back as a real `RGBImage`.
 */
/// `fldraw.Offscreen` is `Pixmap` (an integer `XID`) on Linux but
/// `HBITMAP` (a pointer-based handle) on Windows -- `!= 0`/`!is null`
/// aren't interchangeable across the two, so every "is this a real
/// offscreen buffer" check in this module goes through this one helper
/// instead of repeating a `version` block at each call site.
private bool offscreenValid(fldraw.Offscreen o)
{
    version (linux) return o != 0;
    else version (Windows) return o !is null;
    else return false;
}

class ImageSurface : WidgetSurface
{
    private int w_, h_; // actual offscreen buffer size, in device pixels
    private int logicalW_, logicalH_; // the constructor's own w/h args, FLTK units
    private bool highRes_;
    private fldraw.Offscreen offscreen_;

    /// The GUI scale factor this surface's pixel buffer should be sized
    /// for -- ported from the constructor-time read of `Fl::screen_
    /// scale(int)` every `Fl_*_Image_Surface_Driver` constructor does.
    /// Reads `fl.core.currentScale()`, the live drawing scale (see that
    /// function's own doc comment) -- the same value every other
    /// `fl.draw` primitive reads, matching FLTK's own per-surface
    /// `driver()->scale(scaling)` copy at construction time.
    private static double currentScale()
    {
        import fl.core : coreCurrentScale = currentScale;

        return coreCurrentScale();
    }

    /// Ported from `Fl_Xlib_Image_Surface_Driver::translate()`/
    /// `untranslate()` -- straight passthroughs to `fl.draw`'s own
    /// reversible offset stack, matching
    /// `fl.widget_surface.CopySurface`'s identical override (see that
    /// class's own doc comment for the full mechanism).
    version (linux)
    {
        protected override void translate(int x, int y) { fldraw.pushTranslate(x, y); }
        protected override void untranslate() { fldraw.popTranslate(); }
    }

    // mask() state -- see this module's own top comment for the full
    // mechanism. Both null/0 when no mask is currently pending (the
    // common case); set by mask(), consumed and cleared by image().
    private RGBImage maskData_; // depth-1 luminance mask, surface-sized
    version (linux) private fldraw.Offscreen maskBackground_; // pre-mask() snapshot
    version (Windows) private ubyte[] maskBackgroundPixels_; // pre-mask() snapshot, RGB

    /// Ported from `Fl_Image_Surface(int w, int h, int high_res = 0,
    /// Fl_Offscreen off = 0)`. The `off` (externally-owned offscreen)
    /// overload isn't ported -- no caller in this port's tree needs it.
    ///
    /// **Calls `fl.platform_x11.openDisplay()` first**, matching
    /// FLTK's own `Fl_Xlib_Image_Surface_Driver` constructor
    /// (`fl_open_display()`) -- an `ImageSurface` is a legitimate way to
    /// get a live X connection before any window has ever been shown
    /// (`examples/shapedwindow.cxx`'s own `main()` builds one before its
    /// first `win->show()` call), so this can't assume `fl.draw`'s
    /// display state is already open the way `fl_create_offscreen()`
    /// itself does for its own, already-`show()`n-window caller
    /// (`test/offscreen.cxx`). Skipping this crashed for real: `XftDraw
    /// Create()` (called from `fl.draw.setDrawable()`, itself called
    /// from `beginOffscreen()`) segfaulted on a null `Display*`.
    ///
    /// On Windows, this class's `offscreen_`/constructor/destructor/
    /// `doSetCurrent()`/`doEndCurrent()` need a real offscreen buffer to
    /// read back from, backed by `fl.draw`'s `createOffscreen()`/
    /// `deleteOffscreen()`/`beginOffscreen()`/`endOffscreen()` (the same
    /// ones `test/offscreen.cxx` uses).
    ///
    /// Windows also needs a `platformX11.openDisplay()` equivalent,
    /// just a different one: `platformX11.openDisplay()` gets a live X
    /// connection before any window exists; the Windows analogue is
    /// `platformWin32.ensureGraphicsDriver()`, since every `fl.draw`
    /// primitive on this platform routes through a `GdiGraphicsDriver`
    /// (`fl.graphics_driver.currentDriver`) that otherwise doesn't exist
    /// until the *first real window* is shown
    /// (`platformWin32.createWindow()`'s own call site) -- exactly
    /// `shapedwindow.d`'s own shape, which builds and draws into an
    /// `ImageSurface` in `main()` *before* its first `win.show()`.
    /// Without this, `beginOffscreen()`'s own `if (driver is null ...)
    /// return;` guard would silently no-op every drawing call into the
    /// surface, leaving its offscreen bitmap all-black -- which
    /// `computeShapeBitmap()` would then faithfully (and correctly,
    /// given its all-black input) turn into a mask with nothing set at
    /// all.
    ///
    /// Explicitly names its own `driver()` on Windows too, closing the
    /// gap `pushCurrent()`'s own doc comment describes (search that
    /// function for "platform-specific, not a single universal
    /// answer"). Passing `driver = null` here means "I have no opinion,
    /// leave `currentDriver` as whatever it already is" on Windows --
    /// correct when nothing GL-related is involved, but wrong the
    /// moment an `ImageSurface` is pushed *while a `GlGraphicsDriver` is
    /// already active* (`fl.gl.alphaMaskForString()`'s own offscreen
    /// text rasterization, reached from `cube`'s GL-drawn labels): with
    /// no explicit driver, `currentDriver` would stay the GL driver, so
    /// the plain `fl_draw()` call meant to rasterize text into this
    /// surface would dispatch straight back into `GlGraphicsDriver.draw()`
    /// -> the same texture-building call that needed the rasterized text
    /// in the first place (`gl_draw` -> `drawStringWithTexture` ->
    /// `computeTexture` -> `alphaMaskForString` -> `fl_draw` ->
    /// `GlGraphicsDriver.draw` -> `gl_draw` -> ...), overflowing the
    /// stack. Naming `platformWin32.plainGraphicsDriver()` explicitly
    /// instead makes `pushCurrent()`'s logic do the right thing
    /// unprompted: pushing this surface actively *switches away* from
    /// whatever was active (GL included) to the one plain GDI(+) driver
    /// every other `ImageSurface` use already needs, and popping
    /// restores the suspended GL driver afterward via the same
    /// `driverStack_` mechanism.
    this(int w, int h, int highRes = 0)
    {
        version (Windows) super(platformWin32.plainGraphicsDriver());
        logicalW_ = w;
        logicalH_ = h;
        highRes_ = highRes != 0;
        version (linux) platformX11.openDisplay();
        // Matching every `Fl_*_Image_Surface_Driver` constructor's own
        // `if (d != 1 && high_res) { w = int(w*d); h = int(h*d); }`,
        // the offscreen's actual pixel buffer is sized at the current
        // GUI scale factor when `highRes` is set, letting `fl.draw`'s already
        // scale-aware primitives (which multiply every FLTK-unit
        // coordinate by this same global scale regardless of which
        // drawable is current) draw into it at full device-pixel
        // density instead of overflowing/clipping a buffer sized for
        // scale 1. A `highRes == 0` surface keeps the old, exact `w x h`
        // sizing -- matching FLTK's own "meaningful only for
        // non-zero high_res" scope for this whole feature.
        //
        // **A `highRes == 0` surface drawn into at any GUI scale other
        // than 100% gets exactly the clipping this paragraph warns
        // about** -- confirmed live twice now (`fl.core.
        // transientScaleDisplay()`'s own doc comment, and
        // `examples/shapedwindow.d`'s `prepareShape()`, both hit it
        // independently, at 133%/150%): `fl.draw`'s primitives don't
        // check which surface is current before applying the live
        // scale, so a `highRes == 0` surface is only safe to draw into
        // as-is when the caller *knows* the scale is `1`. From inside
        // `fl.*` itself, save/force/restore `fl.core.currentScale()`
        // around the drawing block (`transientScaleDisplay()`'s
        // pattern); from a caller outside `fl.*` (that setter is
        // `package(fl)`), pass `highRes: 1` here instead
        // (`shapedwindow.d`'s fix) -- it sizes this buffer to match
        // what the live scale is about to draw at, so nothing needs
        // forcing.
        double scale = highRes_ ? currentScale() : 1.0;
        w_ = highRes_ ? cast(int)(w * scale) : w;
        h_ = highRes_ ? cast(int)(h * scale) : h;
        offscreen_ = fldraw.createOffscreen(w_, h_);
    }

    /// Ported from `~Fl_Image_Surface()`. Frees the offscreen buffer
    /// this surface owns, not the `RGBImage` any earlier `image()` call
    /// returned (matching FLTK's own "delete the image_surface
    /// object, but not the image itself" contract, see the class doc
    /// comment FLTK and `shapedwindow.d`'s own usage). No
    /// `GC.inFinalizer()` guard needed -- same reasoning as
    /// `fl.bitmap.Bitmap.~this()`: this only touches plain module-level
    /// state (`SurfaceDevice.current_`, `fl.draw`'s own offscreen
    /// stack) and a plain C library function (`XFreePixmap()` via
    /// `deleteOffscreen()`), never reaches into another GC-managed
    /// object.
    ///
    /// **`doEndCurrent()`'s guard** (`fl.widget_surface.CopySurface`
    /// needs the exact same guard -- see that class's own doc
    /// comment): `shapedwindow.d`/`test/device.cxx` both faithfully
    /// transliterate FLTK's own `delete surf; SurfaceDevice.
    /// popCurrent();` ordering (destroying a still-*current* surface
    /// before popping it). `SurfaceDevice.~this()`'s own guard (see
    /// that class) only clears the *static tracking reference*
    /// (`current_`), so a subsequent `popCurrent()` doesn't dispatch
    /// through a dangling object -- it doesn't touch `fl.draw`'s
    /// separate `beginOffscreen()`/`endOffscreen()` stack.
    /// Without this call, that stack's saved "what to restore
    /// drawing to afterward" entry is *never restored*, leaving
    /// `fl.draw`'s active drawable pointed at this object's
    /// about-to-be-freed offscreen buffer until some unrelated later
    /// call happens to overwrite it -- latent, not usually observed
    /// (the next `Expose`-driven repaint's own `setDrawable()` call
    /// almost always overwrites it first), but a real gap matching
    /// FLTK's own explicit `if (is_current()) end_current();` in
    /// `~Fl_Xlib_Image_Surface_Driver()`/`~Fl_Xlib_Copy_Surface_Driver()`.
    ~this()
    {
        if (isCurrent()) doEndCurrent();
        if (offscreenValid(offscreen_)) fldraw.deleteOffscreen(offscreen_);
        // A pending mask() never consumed by a following image()
        // call -- free its snapshot pixmap too, matching FLTK's
        // own `~Fl_Xlib_Image_Surface_Driver()`
        // `if (shape_data_) { XFreePixmap(...); delete ...->mask; }`.
        // On Windows the snapshot is a GC-managed pixel array.
        version (linux) if (maskBackground_ != 0) fldraw.deleteOffscreen(maskBackground_);
    }

    protected override void doSetCurrent()
    {
        fldraw.beginOffscreen(offscreen_);
    }

    protected override void doEndCurrent()
    {
        fldraw.endOffscreen();
    }

    /// The underlying offscreen buffer this surface draws into (a
    /// `Pixmap` on Linux, an `HBITMAP` on Windows). Ported from
    /// `Fl_Image_Surface::offscreen()` -- the one real caller so far is
    /// `fl.widget_surface.CopySurface`'s Windows destructor, which needs
    /// the raw `HBITMAP` to hand to `SetClipboardData(CF_BITMAP, ...)`
    /// (matching FLTK's own `Fl_GDI_Copy_Surface_Driver`'s identical
    /// `surf->offscreen()` call).
    fldraw.Offscreen offscreen() const { return cast(fldraw.Offscreen) offscreen_; }

    /// Ported from `Fl_Image_Surface::image()` (the non-`mask()`-tainted
    /// path -- see this module's own top comment for why `mask()` itself
    /// isn't ported, Windows included). Reads the offscreen buffer back
    /// via `fl.draw.readPixelsFromDrawable()` -- the same `XGetImage()`-
    /// based primitive `fl_read_image()` uses on Linux; on Windows, the
    /// `BitBlt()`+`GetDIBits()` pair that function's own doc comment
    /// describes. Returns `null` if there's no real offscreen buffer, or
    /// if the read-back fails (e.g. no live display on Linux).
    RGBImage image()
    {
        version (linux)
        {
            if (offscreen_ == 0) return null;

            if (maskData_ !is null)
            {
                // Masked path -- ported from
                // `Fl_Xlib_Image_Surface_Driver::image()`'s non-Cairo
                // branch: blend the "after" content (offscreen_, drawn
                // since mask() was called) over the "before" snapshot
                // (maskBackground_), weighted by the depth-1 mask, then
                // write the blend back into offscreen_ itself (so a
                // subsequent mask()+draw() cycle on this same surface
                // sees the composited result, matching FLTK's
                // documented "several masks in succession" support).
                auto pixelsMain = fldraw.readPixelsFromDrawable(offscreen_, 0, 0, w_, h_, 0);
                auto pixelsBg = fldraw.readPixelsFromDrawable(maskBackground_, 0, 0, w_, h_, 0);
                if (pixelsMain !is null && pixelsBg !is null)
                {
                    copyWithMask(maskData_, pixelsBg, pixelsMain, w_ * 3);
                    fldraw.beginOffscreen(offscreen_);
                    fldraw.drawImage(pixelsBg.ptr, 0, 0, w_, h_, 3, 0);
                    fldraw.endOffscreen();
                }
                fldraw.deleteOffscreen(maskBackground_);
                maskBackground_ = 0;
                maskData_ = null;
            }

            auto pixels = fldraw.readPixelsFromDrawable(offscreen_, 0, 0, w_, h_, 0);
            if (pixels is null) return null;
            auto rgbImg = new RGBImage(pixels, w_, h_, 3);
            // Ported from `Fl_Image_Surface::image()`'s own
            // `img->scale(platform_surface->width, platform_surface->
            // height, 1, 1);` -- sets the *display* size (w()/h()) back
            // to the surface's logical FLTK-unit size, independent of
            // the pixel buffer's own (possibly higher-resolution, see
            // the constructor's own `highRes` doc comment) `dataW()`/
            // `dataH()`. A no-op for a `highRes == 0` surface, where
            // logicalW_/logicalH_ already equal w_/h_.
            rgbImg.scale(logicalW_, logicalH_, true, true);
            return rgbImg;
        }
        else version (Windows)
        {
            if (!offscreenValid(offscreen_)) return null;

            // A real GDI constraint, not a logic error: `shapedwindow.d`
            // (matching FLTK's own documented usage) calls `image()`
            // *while this surface is still current* (`popCurrent()`
            // comes *after*), so `offscreen_` is still selected into the
            // DC `doSetCurrent()`/`beginOffscreen()` created. Passing
            // `cast(size_t) offscreen_` here would make
            // `readPixelsFromDrawable()` call `makeDcFor(offscreen_)`,
            // which tries to `SelectObject()` that *same* bitmap into a
            // *second*, brand-new DC -- Windows does not allow one
            // bitmap to be selected into two DCs at once, so that second
            // selection silently fails/corrupts things, and the
            // subsequent `BitBlt()`+`GetDIBits()` reads back garbage
            // (all-zero) instead of the real drawn content. Passing
            // `d = 0` ("read from whatever's currently active") instead,
            // whenever this surface actually *is* still current, avoids
            // this -- `beginOffscreen()` already pointed
            // `GdiGraphicsDriver.hdc()` at `offscreen_`'s own DC, so no
            // second `SelectObject()` is needed at all in that case.
            // Falls back to the original `cast(size_t) offscreen_` path
            // (a fresh temporary DC, safe once nothing else has this
            // bitmap selected) for the less common case of `image()`
            // being called after this surface was already popped.
            size_t src = isCurrent() ? 0 : cast(size_t) offscreen_;

            if (maskData_ !is null)
            {
                // Masked path -- ported from
                // `Fl_GDI_Image_Surface_Driver::image()`: blend what was
                // drawn since mask() over the pre-mask() snapshot,
                // weighted by the mask, and store the blend in
                // offscreen_ (FLTK's `SetDIBits()`), so a further
                // mask() starts from the composited result.
                auto pixelsMain = fldraw.readPixelsFromDrawable(src, 0, 0, w_, h_, 0);
                if (pixelsMain !is null && maskBackgroundPixels_ !is null)
                {
                    copyWithMask(maskData_, maskBackgroundPixels_, pixelsMain, w_ * 3);
                    fldraw.writePixelsToDrawable(src, maskBackgroundPixels_, w_, h_);
                }
                maskBackgroundPixels_ = null;
                maskData_ = null;
            }

            auto pixels = fldraw.readPixelsFromDrawable(src, 0, 0, w_, h_, 0);
            if (pixels is null) return null;
            auto rgbImg = new RGBImage(pixels, w_, h_, 3);
            // Ported from `Fl_Image_Surface::image()`'s own
            // `img->scale(platform_surface->width, platform_surface->
            // height, 1, 1);` -- sets the *display* size (w()/h()) back
            // to the surface's logical FLTK-unit size, independent of
            // the pixel buffer's own (possibly higher-resolution, see
            // the constructor's own `highRes` doc comment) `dataW()`/
            // `dataH()`. A no-op for a `highRes == 0` surface, where
            // logicalW_/logicalH_ already equal w_/h_.
            rgbImg.scale(logicalW_, logicalH_, true, true);
            return rgbImg;
        }
        else return null;
    }

    /// Ported from `Fl_Image_Surface::printable_rect()` /
    /// `Fl_Image_Surface_Driver::printable_rect()` (`*w=width; *h=height;
    /// return 0;`) -- always succeeds with this surface's own logical
    /// FLTK-unit size (`logicalW_`/`logicalH_`, the constructor's own `w`/
    /// `h` args), unlike `WidgetSurface`'s always-failing base.
    override int printableRect(out int w, out int h) const
    {
        w = logicalW_;
        h = logicalH_;
        return 0;
    }

    /**
     * Adapts this surface to the *current* GUI scale factor -- ported
     * from `Fl_Image_Surface::rescale()`, backed by `fl.core.
     * screenScale(int)` (see the constructor's own `highRes` doc comment
     * for the matching sizing logic). Matching
     * FLTK's own doc comment, "useful only for an object constructed
     * with non-zero `highRes`" -- calling it on a plain `highRes == 0`
     * surface recreates an identically-sized buffer and is a harmless
     * no-op-ish redraw, not a documented use case.
     *
     * Reads back whatever was drawn so far (`image()`), frees the old
     * offscreen, recreates it sized for the current scale (the same
     * `highRes`-aware sizing the constructor itself now does, forcing
     * `highRes_` the way FLTK's own `newImageSurfaceDriver(w, h, 1,
     * 0)` call unconditionally passes `high_res = 1`), then redraws the
     * previous content at logical `(0,0)` -- `fl.draw`'s own primitives,
     * already scale-aware (see the constructor's own doc comment), do
     * the actual resampling to the new pixel density as a side effect of
     * that redraw, exactly as FLTK's `rgb->draw(0,0)` relies on its
     * own scale-aware graphics driver to do.
     *
     * **Faithfully inherits a real FLTK interaction, not a bug this
     * port introduced**: `image()` also consumes any pending `mask()`
     * (blends it in and clears `maskData_`/`maskBackground_`, see that
     * method's own doc comment) as a side effect of being called at
     * all -- `rescale()` calling `image()` to grab the "before" content
     * therefore silently finalizes a pending mask too, exactly as
     * FLTK's own `rescale()` does by calling through the identical
     * `image()`. Call `mask()` again after `rescale()` if a fresh one is
     * still wanted.
     */
    void rescale()
    {
        auto rgb = image();
        if (rgb is null) return;

        if (offscreenValid(offscreen_)) fldraw.deleteOffscreen(offscreen_);
        highRes_ = true;
        double scale = currentScale();
        w_ = cast(int)(logicalW_ * scale);
        h_ = cast(int)(logicalH_ * scale);
        offscreen_ = fldraw.createOffscreen(w_, h_);

        SurfaceDevice.pushCurrent(this);
        rgb.draw(0, 0);
        SurfaceDevice.popCurrent();
    }

    /**
     * Defines a mask applied to drawings made after this call -- ported
     * from `Fl_Image_Surface::mask(const Fl_RGB_Image*)`. See this
     * module's own top comment for the full deferred-blend mechanism;
     * the caller's own FLTK-matching contract still applies here:
     * `maskImage` is not used after this call returns (safe to `delete`/
     * let it go out of scope immediately), and this surface must NOT be
     * the currently active drawing surface when `mask()` is called
     * (push/pop it first) -- see FLTK's own doc comment for why
     * (`copyPixmapToPixmap()` below needs `offscreen_` to still hold
     * this surface's *finished* pre-mask content, which isn't
     * guaranteed mid-draw).
     */
    void mask(const(RGBImage) maskImage)
    {
        version (linux)
        {
            if (offscreen_ == 0 || maskImage is null) return;
            // A previous mask() was never consumed by image() -- free
            // it first rather than leaking maskBackground_.
            if (maskBackground_ != 0) fldraw.deleteOffscreen(maskBackground_);

            maskData_ = rgb3ToRgb1(maskImage, w_, h_);
            maskBackground_ = fldraw.createOffscreenBuffer(offscreen_, w_, h_);
            fldraw.copyPixmapToPixmap(offscreen_, maskBackground_, 0, 0, w_, h_, 0, 0);
        }
        else version (Windows)
        {
            // Ported from `Fl_GDI_Image_Surface_Driver::mask()`, which
            // copies the offscreen into a DIB section; a pixel array
            // read back the same way serves here.
            if (!offscreenValid(offscreen_) || maskImage is null) return;
            size_t src = isCurrent() ? 0 : cast(size_t) offscreen_;
            maskBackgroundPixels_ = fldraw.readPixelsFromDrawable(src, 0, 0, w_, h_, 0);
            maskData_ = maskBackgroundPixels_ !is null ? rgb3ToRgb1(maskImage, w_, h_) : null;
        }
    }

    int w() const { return w_; }
    int h() const { return h_; } /// ditto
}

/// Ported from `Fl_Image_Surface_Driver::RGB3_to_RGB1()`
/// (`src/Fl_Image_Surface.cxx`): collapses a depth-3 (or more) RGB image
/// to a depth-1 luminance mask sized exactly `(W, H)`, resampling first
/// via `RGBImage.copy()` if the source is a different size (matching
/// `mask()`'s own doc comment: "the mask can have any size").
private RGBImage rgb3ToRgb1(const(RGBImage) rgb3, int W, int H)
{
    const(RGBImage) src = (W != rgb3.dataW() || H != rgb3.dataH()) ? rgb3.copy(W, H) : rgb3;
    auto data = new ubyte[W * H];
    int ld = src.ld() ? src.ld() : 3 * W;
    size_t p = 0;
    foreach (i; 0 .. H)
    {
        size_t rowOff = i * ld;
        foreach (j; 0 .. W)
        {
            size_t idx = rowOff + j * 3;
            data[p++] = cast(ubyte)((src.array[idx] + src.array[idx + 1] + src.array[idx + 2]) / 3);
        }
    }
    return new RGBImage(data, W, H, 1);
}

/// Ported from `Fl_Image_Surface_Driver::copy_with_mask()`
/// (`src/Fl_Image_Surface.cxx`, used by the Windows and non-Cairo X11
/// drivers): blends `dibSrc` over `dibDst` *in place*, weighted per
/// pixel by `mask`'s depth-1 luminance value (255 = fully `dibSrc`, 0 =
/// fully the original `dibDst`). `mask` is assumed tightly packed
/// (`rgb3ToRgb1()`'s own output always is), matching FLTK's own
/// `mask->array + i*w` indexing exactly -- unlike FLTK, the
/// `bottom_to_top` parameter isn't ported (only the GDI/Windows driver
/// ever passes `true`; this port's only caller always wants top-to-bottom).
private void copyWithMask(const(RGBImage) mask, ubyte[] dibDst, const(ubyte)[] dibSrc, int lineSize)
{
    int w = mask.dataW();
    int h = mask.dataH();
    foreach (i; 0 .. h)
    {
        size_t alphaOff = i * w;
        size_t rowOff = i * lineSize;
        foreach (j; 0 .. w)
        {
            ubyte u = mask.array[alphaOff + j];
            ubyte v = cast(ubyte)(255 - u);
            size_t o = rowOff + j * 3;
            dibDst[o] = cast(ubyte)((dibDst[o] * v + dibSrc[o] * u) / 255);
            dibDst[o + 1] = cast(ubyte)((dibDst[o + 1] * v + dibSrc[o + 1] * u) / 255);
            dibDst[o + 2] = cast(ubyte)((dibDst[o + 2] * v + dibSrc[o + 2] * u) / 255);
        }
    }
}

unittest
{
    // rgb3ToRgb1(): a 2x1 image, pure white then pure black, should
    // collapse to luminance 255 then 0 -- same size as the source, so
    // no resample path is exercised here.
    auto rgb = new RGBImage([255, 255, 255, 0, 0, 0], 2, 1, 3);
    auto rgb1 = rgb3ToRgb1(rgb, 2, 1);
    assert(rgb1.dataW() == 2 && rgb1.dataH() == 1 && rgb1.d() == 1);
    assert(rgb1.array[0] == 255);
    assert(rgb1.array[1] == 0);

    // A mixed-gray pixel averages its 3 channels.
    auto rgb2 = new RGBImage([100, 150, 200], 1, 1, 3);
    auto rgb1b = rgb3ToRgb1(rgb2, 1, 1);
    assert(rgb1b.array[0] == (100 + 150 + 200) / 3);
}

unittest
{
    // copyWithMask(): a fully-white (255) mask pixel should leave dst
    // as pure src; a fully-black (0) mask pixel should leave dst
    // completely untouched (the original background).
    auto mask = new RGBImage([255, 0], 2, 1, 1);
    ubyte[] dst = [10, 20, 30, 40, 50, 60]; // 2 pixels, RGB
    const(ubyte)[] src = [200, 210, 220, 1, 2, 3];
    copyWithMask(mask, dst, src, 6);
    assert(dst[0 .. 3] == [200, 210, 220]); // fully replaced by src
    assert(dst[3 .. 6] == [40, 50, 60]); // fully kept as original dst
}
