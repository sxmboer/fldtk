/*
 * Port of `FL/Fl_Gl_Window.H` + `src/Fl_Gl_Window.cxx` (FLTK 1.5.0). See `PORTING.md`'s own row for current status.
 *
 * A `GlWindow` subclass that overrides `draw()` with plain immediate-
 * mode GL calls and never calls `super.draw()` -- the common case,
 * matching `test/shape.cxx` -- is fully supported: visual selection,
 * context creation, `makeCurrent()`, buffer swap, resize, `mode()`.
 *
 * **Compositing ordinary FLTK child widgets over the GL scene** (the
 * `test/cube.cxx` style: `draw()` calls `Fl_Gl_Window::draw()`, whose
 * default body draws the 2D widget tree between `drawBegin()`/
 * `drawEnd()`): `drawBegin()`/`drawEnd()` bracket a real
 * `SurfaceDevice.pushCurrent(GlDisplayDevice.displayDevice())`/
 * `popCurrent()` pair, so `fl.draw`'s leaf primitives redirect through
 * `fl.gl_graphics_driver.GlGraphicsDriver` while a `GlWindow` is
 * drawing -- including text (`GlGraphicsDriver.draw()` wraps
 * `fl.gl.gl_draw()`), so widget labels render correctly while
 * composited over a GL scene too, not just boxes/frames. See
 * `fl.gl_graphics_driver`'s own doc comment for the exact primitive
 * coverage.
 *
 * **The software-simulated overlay** (`test/gl_overlay.cxx` style):
 * `drawOverlay()` (override this, matching FLTK's own
 * empty-by-default `Fl_Gl_Window::draw_overlay()`), `canDoOverlay()`
 * (always `false` here, same as FLTK's own X11 driver -- no
 * hardware overlay-plane path exists on this platform either),
 * `redrawOverlay()`/`makeOverlayCurrent()`/`hideOverlay()`. Ported from
 * `Fl_Gl_Overlay.cxx` + `Fl_X11_Gl_Window_Driver`'s `swap_buffers()`/
 * `make_overlay_current()`/`redraw_overlay()` overrides -- see
 * `fl.platform_x11.flushGlWindow()`'s own doc comment for the full
 * repaint-order mechanism (skip `draw()` on an overlay-only redraw,
 * `glCopyPixels()` the back buffer onto the front buffer instead of a
 * real `glXSwapBuffers()`, then draw fresh overlay content straight
 * into the front buffer).
 *
 * `modeOpengl3`'s GL1/GL3 context-program switching is real too
 * (`fl.gl_window_driver.switchToGl1()`/`switchBack()`, called from
 * `drawBegin()`/`drawEnd()`). `gl_start()`/`gl_finish()` (drawing GL
 * directly into a non-`Fl_Gl_Window`) are real too, see `fl.gl`'s
 * own doc comment -- unrelated to `GlWindow` itself, ported there.
 *
 * `flush()` itself is still simplified relative to FLTK's
 * `Fl_Gl_Window::flush()` in one respect: only the `SWAP_TYPE==COPY`
 * branch is ported (both platform drivers' `swapType()` unconditionally
 * report `COPY`, matching their own FLTK defaults -- the
 * `NODAMAGE`/`SWAP`/`UNDEFINED` branches are genuinely unreachable
 * here). This port's repaint model has no per-window virtual `flush()`
 * hook at all (see `fl.double_window`'s own module doc comment for why
 * -- repaint goes through `fl.platform_x11.flushDamage()`/
 * `fl.platform_win32`'s own `WM_PAINT` case calling `draw()` directly);
 * a `GlWindow` is repainted via a dedicated branch in each,
 * `flushGlWindow()` below.
 *
 * **Windows (WGL) support**: real, same scope as the X11/GLX path above
 * (context creation/`makeCurrent()`/buffer swap/`mode()`, Phase 2
 * compositing, and the software-simulated overlay) -- this whole class
 * needed no code changes at all beyond widening its own `version` guard
 * and the `GLXContext` alias just below, since every platform-specific
 * call already goes through `glDriver.*` (`fl.gl_window_driver`, which
 * has the real per-platform split) or `xid()` (`fl.window.Window`,
 * which already resolves to the right handle type per platform). See
 * `fl.gl_window_driver`'s own top comment for what Windows deliberately
 * doesn't port (real hardware overlay-plane support).
 */
module fl.gl_window;

version (linux) version = FldtkGl;
version (Windows) version = FldtkGl;

version (FldtkGl):

import fl.window : Window;
import fl.core : screenScale;
import fl.enumerations : Boxtype, Mode, Event, modeRgb, modeDepth, modeDouble,
    modeFakeSingle, modeOpengl3, damageAll, Damage, damageOverlay;
import fl.image : RGBImage;
import glDriver = fl.gl_window_driver;
import fl.gl_choice : GlChoice;
import fl.opengl : glDrawBuffer, glReadBuffer, GL_FRONT, GL_BACK, glFlush, glLoadIdentity,
    glViewport, glOrtho, GLint, glGetIntegerv, GL_MAX_VIEWPORT_DIMS;

version (linux) import fl.glx : GLXContext;
else version (Windows) import core.sys.windows.windef : GLXContext = HGLRC;

private enum int nonLocalContext = 0x8000_0000; // FLTK's NON_LOCAL_CONTEXT

class GlWindow : Window
{
private:
    int mode_ = modeRgb | modeDepth | modeDouble;
    const(int)* alist_;
    GlChoice g_;
    GLXContext context_;
    ubyte validF_;

    void init()
    {
        box(Boxtype.noBox);
        end();
    }

public:
    this(int w, int h, string label = null)
    {
        super(w, h, label);
        init();
    }

    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        init();
    }

    ~this()
    {
        import core.memory : GC;

        // See fl.group's ~this() for why cross-object work is guarded
        // like this. Matches FLTK's own `~Fl_Gl_Window() { hide();
        // delete pGlWindowDriver; }` -- this port has no separate
        // driver object to delete (fl.gl_window_driver is free
        // functions), so only the hide()/context-teardown half applies.
        if (!GC.inFinalizer())
            hide();
    }

    /// Returns non-zero if the hardware supports the given (or, with
    /// no arguments, this window's current) OpenGL mode.
    static bool canDo(int m, const(int)* a = null)
    {
        return glDriver.find(m, a) !is null;
    }

    bool canDo() const
    {
        return glDriver.find(mode_, alist_) !is null;
    }

    /// The current OpenGL capability flags (`fl.enumerations.Mode`).
    Mode mode() const
    {
        return mode_;
    }

    /// Sets the OpenGL capability flags. Ported from `Fl_Gl_Window::
    /// mode(int)` -- destroys and recreates the window if it's already
    /// shown() and the visual actually needs to change (matching
    /// FLTK's own "yuck!" comment: X can't change a live window's
    /// visual in place).
    void mode(int m)
    {
        if (m == mode_ && alist_ is null) return;
        applyMode(m, null);
    }

    private void applyMode(int m, const(int)* a)
    {
        int oldmode = mode_;
        GlChoice oldg = g_;
        context(null, 0);
        mode_ = m;
        alist_ = a;
        if (shown())
        {
            g_ = glDriver.find(m, a);
            bool visualChanged = g_ is null || oldg is null;
            version (linux)
                visualChanged = visualChanged || g_.vis.visualid != oldg.vis.visualid;
            else version (Windows)
                visualChanged = visualChanged || g_.pixelformat != oldg.pixelformat;
            if (visualChanged || ((oldmode ^ m) & modeDouble) != 0)
            {
                hide();
                show();
            }
        }
        else
        {
            g_ = null;
        }
    }

    override void show()
    {
        if (!shown())
        {
            if (g_ is null)
            {
                g_ = glDriver.find(mode_, alist_);
                if (g_ is null)
                {
                    // FLTK calls Fl::error("Insufficient GL support")
                    // here -- this port has no Fl::error() equivalent
                    // (an established convention, see e.g.
                    // fl.platform_x11's own doc comments on the same
                    // point); the caller simply doesn't get a shown
                    // window.
                    return;
                }
            }
            glDriver.beforeShow(this, g_);
        }
        super.show();
    }

    override void hide()
    {
        context(null, 0);
        super.hide();
    }

    /// Same as `Window.show(string[])` -- ported from FLTK's own
    /// explicit `Fl_Gl_Window::show(int,char**){Fl_Window::show(a,b);}`
    /// (`FL/Fl_Gl_Window.H`). Needed for the same reason FLTK itself
    /// spells it out rather than relying on inheritance alone: a derived
    /// class's own `show()` override (this class's no-arg `show()`
    /// above, real GL-context setup) hides the base class's whole
    /// `show` overload set by name -- both in C++ and in D -- so a
    /// `GlWindow` used directly as a top-level window (not nested inside
    /// a plain `Window`, e.g. `source/test/gl_image.d`'s
    /// `GlImageWindow`) needs its own forwarder to reach
    /// `Window.show(string[])`'s args-parsing/system-colors setup at
    /// all. `super.show(args)` still ends by virtually dispatching to
    /// this class's own no-arg `show()` override (see that method's own
    /// body, ending in a plain `show();` call), so GL context creation
    /// still happens correctly either way.
    override void show(string[] args)
    {
        super.show(args);
    }

    /// Ported from `Fl_Gl_Window::resize()`, with its own
    /// `|| is_a_rescale()` clause: during a live Ctrl-+/Ctrl-- rescale,
    /// a GL window's FLTK-unit `W`/`H` don't change (only the real
    /// device-pixel size does -- the whole point of DPI scaling), so
    /// the plain `W != w() || H != h()` check alone would stay false in
    /// that case, `valid(false)` would never run, and the next `draw()`
    /// would keep the stale GL viewport/ortho projection from before
    /// the rescale -- the cube staying its old on-screen size while the
    /// real X11 subwindow underneath it (correctly resized by
    /// `Window.resize()`'s own `isARescale()` check, see that method's
    /// own doc comment) grows, leaving newly-exposed area unpainted.
    /// FLTK's own `pGlWindowDriver->resize(is_a_resize,
    /// W, H)` call isn't ported -- the base (non-Wayland-overridden)
    /// `Fl_Gl_Window_Driver::resize()` FLTK itself falls back to is
    /// an empty no-op, so there's nothing for the X11-only driver here
    /// to do at this call.
    override void resize(int X, int Y, int W, int H)
    {
        bool isResize = (W != w() || H != h() || Window.isARescale());
        if (isResize) valid(false);
        super.resize(X, Y, W, H);
    }

    /// Is turned off when a new context is created for this window or
    /// the window resizes, and turned back on after draw() runs.
    bool valid() const
    {
        return (validF_ & 1) != 0;
    }

    void valid(bool v)
    {
        if (v) validF_ |= 1;
        else validF_ &= 0xfe;
    }

    /// Set only when the OpenGL context is (re)created.
    bool contextValid() const
    {
        return (validF_ & 2) != 0;
    }

    void contextValid(bool v)
    {
        if (v) validF_ |= 2;
        else validF_ &= 0xfd;
    }

    void invalidate()
    {
        valid(false);
        contextValid(false);
        // Ported from Fl_Gl_Window_Driver::invalidate()'s remaining
        // body: `if (pWindow->overlay) { ((Fl_Gl_Window*)pWindow->
        // overlay)->valid(0); ...->context_valid(0); }`. On X11
        // `overlay` is always either null or pWindow itself (see
        // `redrawOverlay()`'s own doc comment -- no separate hardware-
        // overlay window object ever exists here), so this is a no-op
        // in practice (re-invalidating the same window this method
        // just invalidated above) -- kept for faithfulness rather than
        // silently dropped, in case a future real hardware-overlay
        // driver ever gives `overlay_` a genuinely different value.
        if (overlay_ !is null)
        {
            overlay_.valid(false);
            overlay_.contextValid(false);
        }
    }

    /// `null` until the first `redrawOverlay()` call, `this` from then
    /// on (never anything else in this port -- see `canDoOverlay()`'s
    /// own doc comment). Mirrors FLTK's private `void *overlay`
    /// field (`Fl_Gl_Window_Driver::make_overlay(void*&o){o=pWindow;}`
    /// -- X11 never gives it any other value), same design
    /// `fl.overlay_window.OverlayWindow.overlay_` already uses for the
    /// analogous plain-2D-window case.
    package(fl) GlWindow overlay_;

    /// Override this to draw into the overlay -- called after the main
    /// scene is drawn/swapped, straight on top of it, whenever the
    /// overlay needs a fresh paint (see `fl.platform_x11.
    /// flushGlWindow()`'s overlay branch for exactly when). The default
    /// (matching FLTK's own `Fl_Gl_Window::draw_overlay() {}`,
    /// `src/Fl_Gl_Window.cxx`) does nothing -- only a subclass that
    /// overrides it and calls `redrawOverlay()` ever sees this run.
    void drawOverlay() {}

    /// Returns true if there's hardware overlay-plane support. Always
    /// `false` in this port -- ported from `Fl_Gl_Window::can_do_
    /// overlay()`/`Fl_Gl_Window_Driver::can_do_overlay()`'s
    /// unconditional `return 0;`: X11 has no override for it anywhere
    /// in `Fl_X11_Gl_Window_Driver.cxx` either (only WinAPI/Cocoa have
    /// a real one, for OpenGL's own separate overlay-plane extension --
    /// out of scope here, matching `fl.overlay_window`'s identical
    /// "the software-simulated path is the *only* path here, same as
    /// real FLTK on X11" reasoning for the plain-2D case).
    bool canDoOverlay() const { return false; }

    /// Backs `fl.platform_x11.flushGlWindow()`'s overlay branch.
    package(fl) bool overlayActive() const { return overlay_ !is null; }

    /**
     * Call this to indicate the overlay needs to be redrawn. The
     * overlay stays clear until the first call to this (so call it
     * right after `show()` if you want an initial display). Ported
     * from `Fl_Gl_Window::redraw_overlay()` + `Fl_Gl_Window_Driver::
     * make_overlay()` + `Fl_X11_Gl_Window_Driver::redraw_overlay()`/
     * `Fl_WinAPI_Gl_Window_Driver::redraw_overlay()`: FLTK splits
     * "point `overlay` at the (on X11/Windows, always-this-same) window"
     * and "flag it damaged" across two virtual calls, both collapsed
     * into this one method here.
     *
     * Uses the real, invalidating `damage()` setter, not
     * `clearDamage()`: both `Fl_X11_Gl_Window_Driver::redraw_overlay()`
     * and `Fl_WinAPI_Gl_Window_Driver::redraw_overlay()` call the real,
     * invalidating `pWindow->damage(FL_DAMAGE_OVERLAY)` directly --
     * unlike `Fl_Window_Driver::redraw_overlay()`'s own plain-2D version
     * (`fl.overlay_window`'s row), which uses `clear_damage()` but
     * compensates with a separate global `Fl::damage(FL_DAMAGE_CHILD)`
     * kick this port has no equivalent of at all. Without a real
     * invalidate here, nothing schedules a repaint of `sw` (a genuine
     * subwindow, not sharing its parent `window`'s own HWND/X window the
     * way `test/overlay.d`'s buttons happen to share `ovl`'s) purely
     * from `redrawOverlay()` -- it would only get (re)drawn as an
     * incidental side effect of some other widget's own `redraw()` call
     * triggering a genuine repaint that happened to also notice the
     * quietly-set damage bit.
     */
    void redrawOverlay()
    {
        if (!shown()) return;
        overlay_ = this;
        damage(damageOverlay);
    }

    /**
     * Selects the OpenGL context for the overlay. Called automatically
     * before `drawOverlay()` (see `fl.platform_x11.flushGlWindow()`),
     * and also usable directly from `handle()` to implement feedback/
     * selection. Ported from `Fl_Gl_Window::make_overlay_current()` +
     * `Fl_X11_Gl_Window_Driver::make_overlay_current()`
     * (`glDrawBuffer(GL_FRONT)` -- the overlay is simulated by drawing
     * straight into the front buffer, see this module's own top
     * comment and `fl.platform_x11.flushGlWindow()`'s doc comment for
     * the full mechanism).
     */
    void makeOverlayCurrent()
    {
        overlay_ = this;
        glDrawBuffer(GL_FRONT);
    }

    /// Hides the hardware overlay-plane window, if there is a separate
    /// one. A no-op in this port, matching `Fl_Gl_Window_Driver::hide_
    /// overlay()`'s own base-class default (`{}`, no X11-specific
    /// override) -- ported from `Fl_Gl_Window::hide_overlay()`. There's
    /// never a separate overlay window to hide here (see
    /// `canDoOverlay()`'s own doc comment), so this genuinely has
    /// nothing to do on this platform, same as FLTK's own X11
    /// build.
    void hideOverlay() {}

    /// The window's OpenGL rendering context, or sets it. `destroyFlag`
    /// controls whether fldtk destroys the context when the window is
    /// destroyed / mode() changes / context() is called again --
    /// matches FLTK's `Fl_Gl_Window::context(GLContext, int)`.
    GLXContext context()
    {
        return context_;
    }

    void context(GLXContext v, int destroyFlag = 0)
    {
        if (context_ && !(mode_ & nonLocalContext))
            glDriver.deleteGlContext(context_);
        context_ = v;
        if (destroyFlag) mode_ &= ~nonLocalContext;
        else mode_ |= nonLocalContext;
    }

    /// Selects this window's OpenGL context, creating it first if
    /// necessary. Called automatically before draw(); also usable from
    /// handle() for feedback/selection.
    ///
    /// `override`s `Window.makeCurrent()` (that method's own doc
    /// comment: points `fl.draw` at this window's real X resource, this
    /// port's own addition for offscreen-buffer support -- not an
    /// FLTK `Fl_Window` method at all). Still calling `super.
    /// makeCurrent()` first is harmless and keeps that mechanism
    /// consistent for a GL window too (e.g. `Window.current()`
    /// tracking) before doing the real GLX work FLTK's
    /// `Fl_Gl_Window::make_current()` is actually ported from.
    override void makeCurrent()
    {
        super.makeCurrent();
        if (!shown()) return;
        if (!context_)
        {
            mode_ &= ~nonLocalContext;
            context_ = glDriver.createGlContext(this, g_);
            valid(false);
            contextValid(false);
        }
        glDriver.setGlContext(cast(void*) this, xid(), context_);
        if (mode_ & modeFakeSingle)
        {
            glDrawBuffer(GL_FRONT);
            glReadBuffer(GL_FRONT);
        }
    }

    /// Swaps the back and front buffers -- or, while the software-
    /// simulated overlay is active, copies the back buffer onto the
    /// front buffer instead (`glXSwapBuffers()` would discard the back
    /// buffer's contents, which still need to survive so the next
    /// overlay-only redraw can recopy them without re-running `draw()`;
    /// see `Fl_X11_Gl_Window_Driver::swap_buffers()`'s own `if
    /// (overlay())` branch). Called automatically after draw() by
    /// `fl.platform_x11.flushGlWindow()`.
    void swapBuffers()
    {
        glDriver.swapBuffers(xid(), pixelW(), pixelH(), overlayActive());
    }

    void swapInterval(int frames)
    {
        glDriver.swapInterval(xid(), frames);
    }

    int swapInterval() const
    {
        return glDriver.swapInterval(xid());
    }

    /// Sets the projection so (0,0) is the lower-left corner and each
    /// pixel is one unit wide/tall. Ported from `Fl_Gl_Window::ortho()`
    /// (the simple, non-`_M_ALPHA` branch -- that #ifdef is Alpha-NT-
    /// specific dead code on any target this port builds for).
    void ortho()
    {
        GLint[2] v;
        glGetIntegerv(GL_MAX_VIEWPORT_DIMS, v.ptr);
        glLoadIdentity();
        glViewport(pixelW() - v[0], pixelH() - v[1], v[0], v[1]);
        glOrtho(pixelW() - v[0], pixelW(), pixelH() - v[1], pixelH(), -1, 1);
    }

    /// The number of pixels per FLTK unit of length for this window --
    /// ported from `Fl_X11_Gl_Window_Driver::pixels_per_unit()`
    /// (`return Fl::screen_driver()->scale(ns);`), not the base
    /// (non-X11-overridden) `Fl_Gl_Window_Driver::pixels_per_unit()`
    /// default. `screenNum()` already resolves correctly for a
    /// `GlWindow` nested as a subwindow (delegates to `topWindow().
    /// screenNum()`), matching FLTK's own `pWindow->screen_num()`.
    float pixelsPerUnit() const
    {
        return screenScale(screenNum());
    }

    int pixelW() const
    {
        return cast(int)(pixelsPerUnit() * w() + 0.5f);
    }

    int pixelH() const
    {
        return cast(int)(pixelsPerUnit() * h() + 0.5f);
    }

    /// Ported from `Fl_Gl_Window::draw_begin()`: the GL-state setup
    /// (viewport/ortho/attrib push) plus the `Fl_Surface_Device::
    /// push_current(Fl_OpenGL_Display_Device::display_device())` half
    /// that redirects ordinary
    /// `fl.draw` 2D drawing through `fl.gl_graphics_driver.
    /// GlGraphicsDriver` -- see that module's own doc comment for
    /// exactly which primitives are real (boxes/frames/focus rings/
    /// clipping/arcs) vs. still a documented no-op (text -- Phase 3).
    protected void drawBegin()
    {
        import fl.image_surface : SurfaceDevice;
        import fl.gl_display_device : GlDisplayDevice;

        // Ported from Fl_Gl_Window::draw_begin()'s own leading line --
        // detaches whatever shader a modeOpengl3 window's own draw()
        // left bound, so the fixed-function-style 2D widget compositing
        // below (GlGraphicsDriver's glRectf()/glBegin()/etc) renders
        // correctly instead of being intercepted by that shader. See
        // fl.gl_window_driver.switchToGl1()'s own doc comment for the
        // full mechanism.
        if (mode_ & modeOpengl3) glDriver.switchToGl1();

        damage(damageAll);

        auto dd = GlDisplayDevice.displayDevice();
        SurfaceDevice.pushCurrent(dd);
        dd.glDriver().setMetrics(pixelsPerUnit(), h());

        if (!valid())
        {
            glViewport(0, 0, pixelW(), pixelH());
            valid(true);
        }

        import fl.opengl : glPushAttrib, glMatrixMode, glPushMatrix, GL_PROJECTION,
            GL_MODELVIEW, glDisable, glEnable, GL_DEPTH_TEST, GL_LIGHTING, GL_TEXTURE_2D,
            GL_POINT_SMOOTH, glLineWidth, glPointSize, glBlendFunc, GL_SRC_ALPHA,
            GL_ONE_MINUS_SRC_ALPHA, GL_BLEND, GL_SCISSOR_TEST, GL_ALL_ATTRIB_BITS;

        glPushAttrib(GL_ALL_ATTRIB_BITS);

        glMatrixMode(GL_PROJECTION);
        glPushMatrix();
        glLoadIdentity();
        glOrtho(0.0, w(), h(), 0.0, -1.0, 1.0);

        glMatrixMode(GL_MODELVIEW);
        glPushMatrix();
        glLoadIdentity();

        glDisable(GL_DEPTH_TEST);
        glDisable(GL_LIGHTING);
        glDisable(GL_TEXTURE_2D);
        glEnable(GL_POINT_SMOOTH);

        glLineWidth(cast(float)(pixelsPerUnit() * dd.glDriver().lineWidth()));
        glPointSize(cast(float) pixelsPerUnit());
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
        glEnable(GL_BLEND);
        glDisable(GL_SCISSOR_TEST);
    }

    /// Matches `drawBegin()` -- pops the GL state pushed there, then
    /// pops the `Fl_Surface_Device` `drawBegin()` pushed, restoring
    /// whatever surface (native Xlib/Xft, or a nested surface) was
    /// current before this frame's `drawBegin()` ran.
    protected void drawEnd()
    {
        import fl.opengl : glPopMatrix, glMatrixMode, GL_MODELVIEW, GL_PROJECTION, glPopAttrib;
        import fl.image_surface : SurfaceDevice;

        glMatrixMode(GL_MODELVIEW);
        glPopMatrix();
        glMatrixMode(GL_PROJECTION);
        glPopMatrix();
        glPopAttrib();

        SurfaceDevice.popCurrent();
        // Ported from Fl_Gl_Window::draw_end()'s own trailing line --
        // matches drawBegin()'s switchToGl1() call, re-binding whatever
        // shader was detached there.
        if (mode_ & modeOpengl3) glDriver.switchBack();
    }

    /// Default draw(): a subclass overriding this and calling
    /// `super.draw()` gets `drawBegin()`/ordinary FLTK child-widget
    /// drawing/`drawEnd()`, matching FLTK's structure -- but see
    /// this module's top comment for the real caveat (child-widget
    /// compositing isn't correctly GL-routed until Phase 2). The common
    /// case (`test/shape.cxx`-style: override `draw()`, call plain GL
    /// functions, never call `super.draw()`) is unaffected.
    override void draw()
    {
        drawBegin();
        super.draw();
        drawEnd();
    }

    override int handle(Event event)
    {
        return super.handle(event);
    }

    /// Captures a rectangle of this window's current GL content as an
    /// `RGBImage`. Forces a redraw first (matching FLTK's own
    /// `glw->flush()` call -- "necessary for the glpuzzle demo").
    RGBImage capture(int x, int y, int w, int h)
    {
        return glDriver.captureGlRectangle(&forceFlush, pixelsPerUnit(), pixelH(), x, y, w, h);
    }

    private void forceFlush()
    {
        flushGlWindow(this);
    }
}

/**
 * A `GlWindow`'s repaint path -- deliberately separate from
 * `fl.platform_x11.flushDamage()`'s/`fl.platform_win32`'s own `WM_PAINT`
 * case's double-buffer/overlay logic, which are all built around this
 * port's own offscreen-buffer double-buffering scheme (`fl.double_window`)
 * and platform-specific 2D-drawing redirection. Neither applies to a
 * `GlWindow`: its "back buffer" (when `modeDouble` is set) is a real
 * GL back buffer maintained by the driver/hardware, swapped via
 * `win.swapBuffers()`, not a blitted offscreen buffer; and its content
 * is painted by `win.draw()` calling straight OpenGL functions.
 *
 * Entirely platform-independent (every platform-specific call is inside
 * `win.makeCurrent()`/`win.swapBuffers()`/etc, which dispatch through
 * `fl.gl_window_driver`'s own per-platform split) -- lives here, next
 * to `GlWindow` itself, rather than in either platform module, so
 * `fl.platform_x11.flushDamage()` and `fl.platform_win32`'s `WM_PAINT`
 * case can both call the exact same implementation instead of
 * maintaining two copies.
 *
 * Simplified relative to FLTK's `Fl_Gl_Window::flush()`: no
 * `SWAP_TYPE`-based `NODAMAGE`/`SWAP`/`UNDEFINED` dispatch (every
 * platform driver here always reports `COPY` from `swapType()` anyway,
 * matching their own FLTK defaults -- see that function's doc
 * comment) -- but the `COPY` branch itself, including its software-
 * simulated-overlay handling (from `Fl_Gl_Overlay.cxx`), is ported in
 * full below: skip the possibly
 * expensive `win.draw()` call when the only reason this flush is
 * running is an overlay-only redraw, and draw fresh overlay content
 * directly into the front buffer afterward. `package(fl)` (not
 * `private`) since `GlWindow.capture()` also calls this directly to
 * force a fresh frame before reading pixels back, matching FLTK's
 * own `glw->flush()` call at the top of `Fl_Gl_Window_Driver::
 * capture_gl_rectangle()`.
 */
package(fl) void flushGlWindow(GlWindow win)
{
    if (!win.shown()) return;
    // Read before makeCurrent(), which may itself clear valid() when
    // (re)creating the context -- matching FLTK's own `uchar
    // save_valid = valid_f_ & 1;` read, taken before `make_current()`
    // runs, for exactly this reason.
    bool saveValid = win.valid();
    win.makeCurrent();

    if (win.mode() & modeDouble)
    {
        glDrawBuffer(GL_BACK);

        // Ported from Fl_Gl_Window::flush()'s `SWAP_TYPE == COPY`
        // branch: `if (damage() != FL_DAMAGE_OVERLAY || !save_valid)
        // draw();` -- an overlay-only redraw with an already-valid
        // context has nothing new to paint into the back buffer;
        // swapBuffers() below (via win.overlayActive()) recopies that
        // still-good back buffer onto the front buffer instead of
        // presenting a stale one.
        if (win.damage() != damageOverlay || !saveValid)
        {
            Window.setCurrentForDraw(win);
            win.draw();
        }
        win.swapBuffers();

        // Ported from flush()'s trailing `if (overlay==this &&
        // SWAP_TYPE != SWAP) { glDrawBuffer(GL_FRONT); draw_overlay();
        // glDrawBuffer(GL_BACK); glFlush(); }` -- neither platform
        // driver here ever reaches SWAP_TYPE==SWAP (see this function's
        // own doc comment), so that half of the FLTK condition is
        // always true here and isn't reproduced. Drawing straight into
        // GL_FRONT here, on top of whatever swapBuffers() just
        // presented/recopied, is the whole simulated-overlay trick:
        // it's never part of the back buffer, so it's naturally
        // "erased" the next time swapBuffers() recopies a clean back
        // buffer over it.
        if (win.overlayActive())
        {
            glDrawBuffer(GL_FRONT);
            win.drawOverlay();
            glDrawBuffer(GL_BACK);
            glFlush();
        }
    }
    else
    {
        // Ported from Fl_Gl_Window::flush()'s own `else` branch
        // (FLTK's single-buffered path is a genuinely separate,
        // simpler branch, not a fallback through the SWAP_TYPE-dispatch/
        // `swap_buffers()` path at all): draw unconditionally (no
        // overlay-only-damage skip -- FLTK's own single-buffered
        // branch has none either), draw the overlay if active, then
        // `glFlush()` -- which is what actually guarantees the rendered
        // frame reaches the display for a context with no back buffer
        // to present via a swap.
        Window.setCurrentForDraw(win);
        win.draw();
        if (win.overlayActive())
            win.drawOverlay();
        glFlush();
    }

    win.clearDamage(0);
    win.valid(true);
    win.contextValid(true);
}
