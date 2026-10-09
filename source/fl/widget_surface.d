/*
 * Ported from FL/Fl_Widget_Surface.H + src/Fl_Widget_Surface.cxx
 * (FLTK 1.5.0).
 *
 * `WidgetSurface` is the real base class `fl.image_surface.ImageSurface`
 * extends instead of `SurfaceDevice` directly.
 * Unlike the "no polymorphic hierarchy for a
 * single implementation" call this port has made for `fl.platform_x11`
 * (still true there -- only one platform is targeted), this one *is* a
 * real, multi-subclass public base FLTK too (`Fl_Copy_Surface`,
 * `Fl_PDF_File_Surface`, `Fl_SVG_File_Surface`, `Fl_EPS_File_Surface`,
 * `Fl_Paged_Device`/`Fl_Printer` all extend it for real, shared
 * behavior), so it stays a real base class here. This port's own
 * subclasses: `fl.image_surface.ImageSurface`,
 * `CopySurface` (this file), `fl.svg_file_surface.SvgFileSurface`,
 * `fl.postscript.EpsFileSurface`, and `fl.paged_device.PagedDevice`
 * (itself `abstract`, so not directly instantiable -- but it does have
 * a real subclass of its own, `fl.postscript.PostscriptFileDevice`;
 * only `Fl_Printer` remains unported). `fl.
 * graphics_driver.GraphicsDriver` is a similar real, if deliberately
 * minimal, polymorphic base class now -- see that module's own doc
 * comment.
 *
 * Not ported: `print_window_part()` (needs
 * `Fl_Screen_Driver::traverse_to_gl_subwindows()`, a real on-screen
 * capture-and-composite routine with GL-subwindow handling this port
 * has no caller for yet) and `printableRect()`'s real per-subclass
 * override (FLTK's own base-class body is trivial -- always
 * "fails" -- and stays that way here too, including in `fl.paged_
 * device.PagedDevice` itself, which faithfully doesn't override it
 * either, matching FLTK's own `Fl_Paged_Device`; `fl.postscript.
 * PostscriptFileDevice` (a real concrete subclass now) does give it a
 * real answer, same as FLTK's own `Fl_PostScript_File_Device` --
 * only `Fl_Printer`'s own override remains unported).
 */
module fl.widget_surface;

import fl.image_surface : SurfaceDevice, ImageSurface;
import fl.graphics_driver : GraphicsDriver;
import fl.widget : Widget;
import fl.group : FlGroup;
import fl.window : Window;
import fl.overlay_window : OverlayWindow;
import fl.enumerations : damageAll, damageChild, white;
import fl.image : RGBImage;
import fldraw = fl.draw;
import fl.core;
version (linux) import platformX11 = fl.platform_x11;
version (Windows)
{
    import core.sys.windows.windows;
    import fl.gdi_graphics_driver : GdiGraphicsDriver;
    import platformWin32 = fl.platform_win32;
}

/**
 * Ported from `Fl_Widget_Surface` (`FL/Fl_Widget_Surface.H` +
 * `src/Fl_Widget_Surface.cxx`) -- the base for any `SurfaceDevice`
 * that can capture a widget (or a whole decorated window) rather than
 * only accepting raw `fl.draw` primitive calls.
 */
class WidgetSurface : SurfaceDevice
{
    /// Ported from `Fl_Widget_Surface::x_offset`/`y_offset` -- `protected`
    /// there too (not `private`), since `Fl_PostScript_File_Device::
    /// begin_page()` (`fl.postscript.PostscriptFileDevice`) needs to
    /// reset these directly, bypassing the virtual `origin()` setter's
    /// side effects (it establishes a fresh coordinate system of its own
    /// via `page()`'s own emitted PostScript, so re-emitting `ps_origin()`
    /// on top would be redundant/wrong).
    protected int xOffset_, yOffset_;

    /// Forwards to `SurfaceDevice(GraphicsDriver)` -- needed explicitly
    /// because a derived class (`ImageSurface`/`CopySurface`'s own
    /// `this(int, int, ...)` constructors, and now `fl.svg_file_surface.
    /// SvgFileSurface`'s `this(int, int, File)`) must be able to pass a
    /// real driver up through this class to `SurfaceDevice`; without
    /// this, D's implicit no-arg default constructor here would only
    /// ever forward `super()` (i.e. `driver == null`).
    this(GraphicsDriver driver = null)
    {
        super(driver);
    }

    /// Ported from `Fl_Widget_Surface::translate()`/`untranslate()` --
    /// no-ops in the base class, same as FLTK. `fl.paged_device.
    /// PagedDevice` (ported, real) doesn't override these either,
    /// matching FLTK's own `Fl_Paged_Device`, which also leaves
    /// them as no-ops -- both `fl.postscript.EpsFileSurface` and
    /// `PostscriptFileDevice` give these real bodies (via the driver's
    /// shared `psTranslate()`/`psUntranslate()`, ported from `Fl_
    /// PostScript_Graphics_Driver::ps_translate()`/`ps_untranslate()`),
    /// matching FLTK's own `Fl_EPS_File_Surface`/`Fl_PostScript_
    /// File_Device` exactly.
    protected void translate(int x, int y) {}
    protected void untranslate() {} /// ditto

    /// Ported from `Fl_Widget_Surface::origin(int*, int*)`.
    void origin(out int x, out int y) const
    {
        x = xOffset_;
        y = yOffset_;
    }

    /// Ported from `Fl_Widget_Surface::origin(int, int)`.
    void origin(int x, int y)
    {
        xOffset_ = x;
        yOffset_ = y;
    }

    /// Ported from `Fl_Widget_Surface::printable_rect()` -- FLTK's
    /// own base-class body always "fails" (returns non-zero); neither
    /// it nor `fl.paged_device.PagedDevice` override this (matching
    /// FLTK's own `Fl_Paged_Device`, which doesn't either) -- only
    /// `Fl_PostScript_File_Device`/`Fl_Printer` give it a real answer
    /// FLTK, and neither is ported (see this module's own top
    /// comment).
    int printableRect(out int w, out int h) const
    {
        w = 0;
        h = 0;
        return 1;
    }

    /**
     * Draws widget onto this surface at the current origin() (plus
     * deltaX/deltaY). Ported from `Fl_Widget_Surface::draw(Fl_Widget*,
     * int, int)` -- faithful line-for-line port apart from the GL-
     * plugin detour FLTK takes for an `Fl_Gl_Window` (`Fl_Gl_Window`
     * isn't ported at all yet, see `PORTING.md`'s deferred-external-
     * library section, so that branch is simply never reachable here,
     * same effective behavior as FLTK's own `drawn_by_plugin == 0`
     * fallback path).
     */
    void draw(Widget widget, int deltaX = 0, int deltaY = 0)
    {
        if (!widget.visible()) return;
        bool needPush = !isCurrent();
        if (needPush) SurfaceDevice.pushCurrent(this);

        Window win = widget.asWindow();
        bool isWindow = win !is null;
        auto oldDamage = widget.damage();
        widget.damage(damageAll);

        // Deliberately not `int oldX, oldY; origin(oldX, oldY);`: both
        // `origin(out int, out int) const` (the getter,
        // declared right above) and `origin(int, int)` (the setter) are
        // viable overloads for two plain `int` lvalue arguments, and the
        // moment a subclass (`fl.printer_win32.Printer`, `fl.postscript.
        // PostscriptFileDevice`, ...) overrides *just* the setter, D
        // resolves `origin(oldX, oldY)` to that overridden *setter*
        // instead of the getter. That would silently re-apply
        // `origin(0, 0)`, discarding whatever page-centering origin the
        // caller (`device.d`'s own `p.origin(w/2, h/2)`) had just set,
        // right before every widget draw. Reading the fields directly
        // (this method already has `protected` access to them) sidesteps
        // the overload ambiguity entirely instead of trying to force a
        // particular resolution.
        int oldX = xOffset_, oldY = yOffset_;
        int newX = oldX + deltaX;
        int newY = oldY + deltaY;
        if (!isWindow)
        {
            newX -= widget.x();
            newY -= widget.y();
        }
        if (newX != oldX || newY != oldY)
            translate(newX - oldX, newY - oldY);

        if (isWindow)
            fldraw.pushClip(0, 0, widget.w(), widget.h());

        widget.draw();
        if (isWindow)
        {
            auto over = cast(OverlayWindow) win;
            if (over !is null) over.drawOverlay();
        }

        if (isWindow) fldraw.popClip();

        traverse(widget);

        if (newX != oldX || newY != oldY)
            untranslate();

        if ((oldDamage & damageChild) == 0) widget.clearDamage(oldDamage);
        else widget.damage(damageAll);

        if (needPush) SurfaceDevice.popCurrent();
    }

    /// Ported from `Fl_Widget_Surface::traverse()` -- recurses into a
    /// group's children, capturing any nested window (subwindow)
    /// found along the way via a fresh `draw()` call at its own
    /// x()/y() offset.
    private void traverse(Widget widget)
    {
        FlGroup g = widget.asGroup();
        if (g is null) return;
        int n = g.children();
        for (int i = 0; i < n; i++)
        {
            Widget c = g.child(i);
            if (c is null || !c.visible()) continue;
            if (c.asWindow() !is null) draw(c, c.x(), c.y());
            else traverse(c);
        }
    }

    /**
     * Draws win, including its window-manager title bar/frame if it
     * has one, at (winOffsetX, winOffsetY) relative to the current
     * origin(). Ported from
     * `Fl_Widget_Surface::draw_decorated_window()`. Equivalent to
     * plain `draw()` for a subwindow or a `border(false)` window.
     * See `fl.window.Window.decoratedW()`/`decoratedH()` to size a
     * surface for the result up front.
     *
     * The `winOffsetY + toph` shift
     * meant to draw the actual window content *below* a captured
     * title-bar strip relies on `translate()` being real, which it
     * is for both `fl.image_surface.ImageSurface` and `CopySurface`
     * (this module) -- see `CopySurface`'s own doc comment for the full
     * mechanism (`fl.draw.pushTranslate()`/`popTranslate()`). A captured
     * title bar with nonzero height doesn't overlap the window
     * content drawn after it.
     */
    void drawDecoratedWindow(Window win, int winOffsetX = 0, int winOffsetY = 0)
    {
        RGBImage top;
        version (linux)
        {
            if (win.shown() && win.border() && win.parent() is null)
                top = platformX11.captureTitlebarImage(win);
        }

        bool needPush = !isCurrent();
        if (needPush) SurfaceDevice.pushCurrent(this);

        // wsides would come from a captured `left` image FLTK --
        // permanently null on X11 (see captureTitlebarImage()'s own
        // doc comment), so this is always 0 here, matching FLTK's
        // real Linux behavior exactly.
        int wsides = 0;
        int toph = top !is null ? top.h() : 0;
        if (top !is null)
            top.draw(winOffsetX, winOffsetY);

        draw(win, winOffsetX + wsides, winOffsetY + toph);

        if (needPush) SurfaceDevice.popCurrent();
    }
}

/**
 * Ported from `Fl_Copy_Surface` (`FL/Fl_Copy_Surface.H`) + the X11
 * driver's own non-Cairo body (`Fl_Xlib_Copy_Surface_Driver`,
 * `src/drivers/Xlib/Fl_Xlib_Copy_Surface_Driver.cxx`) -- same "fold the
 * one real platform driver into the concrete class" precedent as
 * `fl.image_surface.ImageSurface`. Draws into an internal off-screen
 * buffer (the same `fl.draw.createOffscreen()`/
 * `beginOffscreen()`/`endOffscreen()` primitives `ImageSurface`
 * itself uses); when destroyed, reads the buffer back and claims real
 * X11 selection ownership of it as a BMP image via the new
 * `fl.core.copyImage()` (see that function's own doc comment) --
 * matching FLTK's own "delete the Fl_Copy_Surface object to load
 * the clipboard with the graphical data" contract exactly.
 *
 * **`translate()`/`untranslate()` are real**. FLTK's own non-Cairo
 * Xlib driver backs these with `Fl_Xlib_Graphics_Driver::
 * translate_all()`/`untranslate_all()`: a persistent `(offset_x_,
 * offset_y_)` pair added into every one of that driver's own drawing
 * primitives (rects, lines, clip regions, image blits) at the point
 * each one computes real X11 coordinates. `fl.draw` has the direct
 * equivalent -- `pushTranslate()`/`popTranslate()`, threaded into
 * every native drawing primitive's own raw Xlib call -- so this class
 * overrides `translate()`/`untranslate()` for real, matching FLTK's
 * own `Fl_Copy_Surface::translate()`/`Fl_Xlib_Copy_Surface_Driver::
 * translate()` exactly (both call straight through to the graphics
 * driver's `translate_all()`/`untranslate_all()`, no extra logic of
 * their own). See `WidgetSurface.drawDecoratedWindow()`'s own doc
 * comment for the concrete consequence this fixes.
 *
 * **Windows is real too**, via its own separate mechanism -- `fl.core.
 * copyImage()` (the Linux destructor's own clipboard call, genuinely
 * "a no-op on non-Linux platforms") isn't involved at all on Windows;
 * this class's own `version (Windows)` half places the clipboard data
 * directly. Ported faithfully from
 * `Fl_GDI_Copy_Surface_Driver` (`src/drivers/GDI/
 * Fl_GDI_Copy_Surface_Driver.cxx`), which takes a materially different
 * approach from the Xlib/BMP-selection path above: draw into a real
 * `CreateEnhMetaFile()` *vector* recording surface, then rasterize that
 * same metafile into an offscreen bitmap via `PlayEnhMetaFile()`, and
 * place *both* `CF_ENHMETAFILE` (resolution-independent) and
 * `CF_BITMAP` (raster) on the clipboard -- other apps then pick
 * whichever format they understand best. `translate()`/`untranslate()`
 * need their own Windows mechanism too, since `fl.draw.pushTranslate()`/
 * `popTranslate()` only ever affects the *native* (`currentDriver is
 * null`) drawing path (see that function's own doc comment) and this
 * class always has a real `currentDriver` (the shared `GdiGraphicsDriver`
 * singleton, temporarily repointed at the EMF recording DC) -- ported
 * as `fl.gdi_graphics_driver.GdiGraphicsDriver.translateAll()`/
 * `untranslateAll()` instead, a direct `SetWindowOrgEx()`/
 * `GetWindowOrgEx()` port of FLTK's own `Fl_GDI_Graphics_Driver::
 * translate_all()`/`untranslate_all()` (see that method's own doc
 * comment). Reuses the already-established singleton-driver-reuse
 * pattern `fl.image_surface.ImageSurface`'s own Windows half set:
 * `platformWin32.plainGraphicsDriver()`'s `setHdc()`/`hdc()` accessors
 * (added for `fl.draw`'s `beginOffscreen()`/`endOffscreen()`) are reused
 * here too, rather than constructing FLTK's own fresh `Fl_GDI_
 * Graphics_Driver` instance per surface -- the shared singleton, with
 * its HDC saved and restored around this surface's own lifetime,
 * behaves identically for this purpose.
 */
class CopySurface : WidgetSurface
{
    private int w_, h_;
    version (linux) private fldraw.Offscreen offscreen_;
    version (Windows)
    {
        /// The `CreateEnhMetaFile()` recording DC every draw call while
        /// this surface is current targets -- ported from `Fl_GDI_Copy_
        /// Surface_Driver::gc`.
        private HDC gc_;
        /// Whatever HDC `platformWin32.plainGraphicsDriver()` was
        /// pointed at immediately before this surface last became
        /// current -- restored by `doEndCurrent()`. Ported from
        /// `Fl_GDI_Copy_Surface_Driver::oldgc`, but saved/restored per
        /// `doSetCurrent()`/`doEndCurrent()` pair (matching this port's
        /// own `beginOffscreen()`/`endOffscreen()` convention) rather
        /// than once in the constructor/destructor -- more robust for a
        /// surface `draw()`n more than once, and behaviorally identical
        /// for the common single-`draw()` case every real caller uses.
        private HDC savedHdc_;
        /// The live drawing scale at construction time -- ported from
        /// FLTK's own `driver()->scale(scaling)` (there, copied into
        /// a *fresh* per-surface driver instance's own field; here, the
        /// shared singleton driver already reads `fl.core.currentScale()`
        /// directly wherever it needs it, so this is only kept for the
        /// destructor's own metafile-to-bitmap size computation, matching
        /// FLTK's `Fl_Scalable_Graphics_Driver::floor(width, scaling)`
        /// call there).
        private float scaling_ = 1.0f;
    }

    /// Ported from `Fl_Xlib_Copy_Surface_Driver::translate()`/
    /// `untranslate()` -- straight passthroughs to `fl.draw`'s own
    /// reversible offset stack (see `CopySurface`'s own doc comment).
    version (linux)
    {
        protected override void translate(int x, int y) { fldraw.pushTranslate(x, y); }
        protected override void untranslate() { fldraw.popTranslate(); }
    }

    /// Ported from `Fl_GDI_Copy_Surface_Driver::translate()`/
    /// `untranslate()` -- straight passthroughs to the shared GDI
    /// driver's own `translateAll()`/`untranslateAll()` (see this
    /// class's own doc comment for why `fl.draw.pushTranslate()` isn't
    /// usable here the way the Linux half above uses it).
    version (Windows)
    {
        protected override void translate(int x, int y)
        {
            platformWin32.plainGraphicsDriver().translateAll(x, y);
        }

        protected override void untranslate()
        {
            platformWin32.plainGraphicsDriver().untranslateAll();
        }
    }

    /// Ported from `Fl_Copy_Surface(int w, int h)` +
    /// `Fl_Xlib_Copy_Surface_Driver`'s own constructor (the non-Cairo
    /// half) on Linux: creates the offscreen buffer and clears it to
    /// white, matching FLTK's own background fill exactly. On
    /// Windows, ported from `Fl_GDI_Copy_Surface_Driver`'s own
    /// constructor: computes the screen's real mm-per-device-unit
    /// factors (needed to size the metafile in its own 0.01mm units,
    /// matching `CreateEnhMetaFile()`'s documented coordinate space)
    /// and opens the recording DC.
    this(int w, int h)
    {
        version (Windows) super(platformWin32.plainGraphicsDriver());
        w_ = w;
        h_ = h;
        version (linux)
        {
            platformX11.openDisplay();
            offscreen_ = fldraw.createOffscreen(w, h);
            fldraw.beginOffscreen(offscreen_);
            fldraw.fl_color(white);
            fldraw.fl_rectf(0, 0, w, h);
            fldraw.endOffscreen();
        }
        version (Windows)
        {
            HDC hdc = GetDC(null);
            int hmm = GetDeviceCaps(hdc, HORZSIZE);
            int hdots = GetDeviceCaps(hdc, HORZRES);
            int vmm = GetDeviceCaps(hdc, VERTSIZE);
            int vdots = GetDeviceCaps(hdc, VERTRES);
            ReleaseDC(null, hdc);
            float factorw = (100.0f * hmm) / hdots;
            float factorh = (100.0f * vmm) / vdots;
            scaling_ = currentScale();
            RECT rect;
            rect.left = 0;
            rect.top = 0;
            rect.right = cast(LONG)((w * scaling_) * factorw);
            rect.bottom = cast(LONG)((h * scaling_) * factorh);
            gc_ = CreateEnhMetaFileW(null, null, &rect, null);
            if (gc_ !is null)
            {
                SetTextAlign(gc_, TA_BASELINE | TA_LEFT);
                SetBkMode(gc_, TRANSPARENT);
            }
        }
    }

    /**
     * Ported from `~Fl_Copy_Surface()`/`~Fl_Xlib_Copy_Surface_Driver()`:
     * reads the finished buffer back and loads it into the real X11
     * CLIPBOARD selection (slot 1, matching FLTK's own hardcoded
     * `copy_image(..., 1)` -- a copy-to-clipboard surface never targets
     * the PRIMARY selection) as an image, via the new
     * `fl.core.copyImage()`.
     *
     * `if (isCurrent()) doEndCurrent();` first, matching FLTK's own
     * `if (is_current()) end_current();` -- both `shapedwindow.d`-style
     * samples and `test/device.cxx` destroy a surface while it's still
     * current (before the matching `SurfaceDevice.popCurrent()`); see
     * `fl.image_surface.ImageSurface.~this()`'s own doc comment (same
     * guard, added alongside this class) for exactly why this matters:
     * without it, `fl.draw`'s offscreen-redirect stack never gets
     * popped back, leaving the active drawable pointed at this
     * object's about-to-be-freed buffer.
     *
     * Windows: ported from `~Fl_GDI_Copy_Surface_Driver()`, with one
     * deliberate deviation. FLTK hands `hmf`/`surf->offscreen()` to
     * `SetClipboardData()` and then frees both (`DeleteEnhMetaFile(hmf)`
     * after `CloseClipboard()`; `delete surf` reaches
     * `~Fl_GDI_Image_Surface_Driver()`'s `DeleteObject((HBITMAP)
     * offscreen)`). Win32's documented clipboard contract says the
     * application may not free a handle once the clipboard owns it. No
     * failure is known from FLTK's version, but this port follows the
     * contract: it gives the clipboard duplicates
     * (`CopyEnhMetaFileW()`/`CopyImage(..., IMAGE_BITMAP, ...)`), so the
     * cleanup below only frees this object's own `hmf`/`surf`. See
     * `FLTK_ISSUES.md`'s matching entry.
     */
    ~this()
    {
        version (linux)
        {
            if (offscreen_ != 0)
            {
                if (isCurrent()) doEndCurrent();
                auto pixels = fldraw.readPixelsFromDrawable(offscreen_, 0, 0, w_, h_);
                if (pixels !is null) fl.core.copyImage(pixels, w_, h_, 1);
                fldraw.deleteOffscreen(offscreen_);
            }
        }
        version (Windows)
        {
            if (gc_ !is null)
            {
                if (isCurrent()) doEndCurrent();
                HENHMETAFILE hmf = CloseEnhMetaFile(gc_);
                if (hmf !is null)
                {
                    if (OpenClipboard(null))
                    {
                        EmptyClipboard();
                        HENHMETAFILE hmfForClipboard = CopyEnhMetaFileW(hmf, null);
                        if (hmfForClipboard !is null)
                            SetClipboardData(CF_ENHMETAFILE, cast(HANDLE) hmfForClipboard);
                        int W = cast(int)(w_ * scaling_ + 0.001f);
                        int H = cast(int)(h_ * scaling_ + 0.001f);
                        RECT rect;
                        rect.left = 0;
                        rect.top = 0;
                        rect.right = W;
                        rect.bottom = H;
                        auto surf = new ImageSurface(W, H);
                        SurfaceDevice.pushCurrent(surf);
                        fldraw.fl_color(white);
                        fldraw.fl_rectf(0, 0, W, H);
                        PlayEnhMetaFile(platformWin32.plainGraphicsDriver().hdc(), hmf, &rect);
                        HANDLE bmpForClipboard = CopyImage(cast(HANDLE) surf.offscreen(), IMAGE_BITMAP, 0, 0, 0);
                        if (bmpForClipboard !is null)
                            SetClipboardData(CF_BITMAP, bmpForClipboard);
                        SurfaceDevice.popCurrent();
                        destroy(surf);
                        CloseClipboard();
                    }
                    DeleteEnhMetaFile(hmf);
                }
                DeleteDC(gc_);
            }
        }
    }

    protected override void doSetCurrent()
    {
        version (linux) fldraw.beginOffscreen(offscreen_);
        version (Windows)
        {
            auto driver = platformWin32.plainGraphicsDriver();
            savedHdc_ = driver.hdc();
            driver.setHdc(gc_);
        }
    }

    protected override void doEndCurrent()
    {
        version (linux) fldraw.endOffscreen();
        version (Windows) platformWin32.plainGraphicsDriver().setHdc(savedHdc_);
    }

    /// Ported from `Fl_Copy_Surface::w()`/`h()`.
    int w() const { return w_; }
    int h() const { return h_; } /// ditto

    /// Ported from `Fl_Copy_Surface_Driver::printable_rect()` -- unlike
    /// `WidgetSurface`'s own always-failing base, this always succeeds
    /// with the surface's own full size.
    override int printableRect(out int w, out int h) const
    {
        w = w_;
        h = h_;
        return 0;
    }
}
