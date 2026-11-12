/*
 * Port of FL/Fl_Cairo.H and src/Fl_Cairo.cxx (FLTK 1.5.0): Cairo
 * contexts for FLTK windows.
 *
 * `CairoState` is `Fl_Cairo_State`. The `Fl::cairo_*()` functions FLTK
 * declares in FL/Fl.H live here as free functions (`cairoMakeCurrent()`,
 * `cairoCc()`, `cairoFlush()`, `cairoAutolinkContext()`) and are also
 * reachable through `fl.core`, which re-exports them in a Cairo-enabled
 * build, so `Fl::cairo_make_current(w)` reads `fl.core.cairoMakeCurrent(w)`
 * or, with `import fl;`, just `cairoMakeCurrent(w)`.
 *
 * Only compiled into a Cairo-enabled build (`version (FLDTK_HAVE_CAIRO)`,
 * on by default on Linux, off with dub configuration `linux-no-cairo`; on Windows only with `windows-cairo`),
 * the equivalent of FLTK's CMake options FLTK_OPTION_CAIRO_WINDOW and
 * FLTK_OPTION_CAIRO_EXT: after `cairoAutolinkContext(true)`, every window
 * gets a Cairo context as it is drawn or made current
 * (`cairoAutolinkWindow()`), and `cairoCc()` returns it inside `draw()`.
 *
 * The X11, Wayland and Windows branches of src/Fl_Cairo.cxx are ported.
 * On X11 the Cairo surface wraps the drawable drawing currently targets
 * (a window, or a double window's back buffer during its `draw()`); on
 * Wayland the context is the one the window's draw buffer is drawn with;
 * on Windows it wraps the current device context (`cairo-win32.h`). The
 * macOS branch is not ported.
 *
 * On X11 the program's context is a surface of its own on the drawable,
 * also when the Cairo graphics driver draws the window. The driver's
 * pending drawing is sent to the X server before the context is handed
 * out, and `cairoFlush()` tells the driver its drawable changed, so the
 * two draw in the order the program called them.
 */
module fl.cairo;

version (FLDTK_HAVE_CAIRO):

import fl.cairo_c;
import fl.window : Window;

version (linux)
{
    import fl.cairo_c_xlib : cairo_xlib_surface_create;
    import fldraw = fl.draw;
    import fl.platform_x11 : x11Display, fl_visual;

    // FLTK's fl_gc: unused by the X11 surface, but tracked by CairoState.
    private void* currentGc() { return cast(void*) fldraw.currentGc(); }
    // FLTK's fl_window: the drawable drawing currently targets.
    private void* currentWindow() { return cast(void*) fldraw.currentDrawable(); }
}
else version (Windows)
{
    import fl.cairo_c_win32 : cairo_win32_surface_create;
    import fl.gdi_graphics_driver : GdiGraphicsDriver;
    import fl.graphics_driver : currentDriver;
    import core.sys.windows.windef : HDC;

    // FLTK's fl_gc: the device context drawing currently targets.
    private void* currentGc()
    {
        auto driver = cast(GdiGraphicsDriver) currentDriver;
        return driver !is null ? cast(void*) driver.hdc() : null;
    }
    // FLTK's fl_window: the window being drawn.
    private void* currentWindow()
    {
        auto w = Window.current();
        return w !is null ? cast(void*) w.xid() : null;
    }
}
else
    static assert(false, "Cairo support is only implemented for X11 and Windows");

/**
 * Contains all the necessary info on the current Cairo context.
 * A private internal and unique corresponding object is created to
 * permit Cairo context state handling while keeping it opaque.
 * For internal use only.
 */
final class CairoState
{
    private cairo_t* cc_;        // the unique auto-updated Cairo context
    private bool ownCc_;         // whether we must delete the cc
    private bool autolink_;      // false by default, prevents automatic Cairo mapping on FLTK windows
    private void* window_, gc_;  // the last window+gc a cc was made for
    private int w_, h_;          // the size and scale it was made for
    private float scale_ = 0;

    /// Gets the current Cairo context.
    cairo_t* cc() { return cc_; }

    /// Gets the autolink option. See `cairoAutolinkContext(bool)`.
    bool autolink() const { return autolink_; }

    /**
     * Sets the current Cairo context.
     *
     * `own == true` (the default) means the Cairo context `c` is
     * destroyed internally when another cc is set later; `own == false`
     * means its deletion is handled by the program.
     */
    void cc(cairo_t* c, bool own = true)
    {
        if (cc_ !is null && ownCc_)
            cairo_destroy(cc_);
        cc_ = c;
        scale_ = 0; // cairoMakeCurrent(Window) doesn't reuse a context set here
        if (cc_ is null)
            window_ = null;
        ownCc_ = own;
    }

    /// Sets the autolink option. See `cairoAutolinkContext(bool)`.
    void autolink(bool b) { autolink_ = b; }

    /// Sets the window `w` to keep track of.
    void window(void* w) { window_ = w; }
    /// Gets the last window attached to a cc.
    void* window() { return window_; }
    /// Sets the gc `c` to keep track of.
    void gc(void* c) { gc_ = c; }
    /// Gets the last gc attached to a cc.
    void* gc() { return gc_; }
}

private CairoState cairoState_; // Fl::Private::cairo_state_

private CairoState cairoState()
{
    if (cairoState_ is null)
        cairoState_ = new CairoState;
    return cairoState_;
}

/**
 * When `cairoAutolinkContext()` is true, any current window dc is linked
 * to a current Cairo context. This is not the default, because it may not
 * be necessary to add Cairo support to all FLTK windows. When you wish to
 * associate a Cairo context in this mode, call `cairoMakeCurrent(Window)`
 * explicitly in your overridden `draw()` method.
 *
 * With autolink on, a window's `draw()` can use `cairoCc()` directly:
 * ---
 * override void draw()
 * {
 *     super.draw();
 *     cairo_t* cc = cairoCc(); // the context for this window
 *     // ... your Cairo drawing ...
 *     cairoFlush(cc);
 * }
 * ---
 * GL windows get no context.
 */
void cairoAutolinkContext(bool alink)
{
    cairoState().autolink(alink);
}

/**
 * Gets the current autolink mode for Cairo support: false if no Cairo
 * context autolink is made for each window (the default).
 */
bool cairoAutolinkContext()
{
    return cairoState().autolink();
}

/// Makes a Cairo context for `w` when autolink is on: called as each
/// window is drawn and from `Window.makeCurrent()`.
package(fl) void cairoAutolinkWindow(Window w)
{
    if (cairoState_ !is null && cairoState_.autolink())
        cairoMakeCurrent(w);
}

/// Gets the current Cairo context linked with an FLTK window.
cairo_t* cairoCc()
{
    return cairoState().cc();
}

/// Sets the current Cairo context to `c`. Set `own` to true if you want
/// FLTK to handle this cc's deletion.
void cairoCc(cairo_t* c, bool own = false)
{
    cairoState().cc(c, own);
}

/**
 * Provides a Cairo context for window `wi`.
 *
 * This is needed in a `draw()` override if `cairoAutolinkContext()`
 * returns false, which is the default. The context does not need to be
 * freed, as it is freed every time a new Cairo context is created.
 *
 * The context is kept while the drawing target, size and screen scale
 * stay the same; each call then returns it in the state it was made in
 * (scaled to the screen, nothing else set). After this call,
 * `cairoCc()` returns this context.
 *
 * Returns: the Cairo context for this window, or `null` if `wi` is `null`.
 */
cairo_t* cairoMakeCurrent(Window wi)
{
    if (wi is null)
        return null;
    cairo_t* cairoCtxt;

    version (FLDTK_HAVE_WAYLAND)
    {
        // On Wayland the window's own draw buffer is the context.
        import platform = fl.platform;
        import platformWayland = fl.platform_wayland;
        if (platform.backend() == platform.Backend.wayland)
        {
            cairoCtxt = platformWayland.windowCairo(wi);
            if (cairoCtxt is null) return null; // not shown yet
            cairoCc(cairoCtxt, false);
            return cairoCtxt;
        }
    }

    void* gc = currentGc();
    if (gc is null) // means remove current cc
    {
        cairoCc(null); // destroy any previous cc
        cairoState().window(null);
        return null;
    }

    version (linux) fldraw.flushDrawable(); // the driver's own drawing goes first

    import fl.core : screenScale;
    float scale = screenScale(wi.screenNum()); // get the screen scaling factor
    int w = wi.w(), h = wi.h();
    version (linux)
    {
        w = cast(int)(w * scale);
        h = cast(int)(h * scale);
    }

    // The same target, size and scale: reuse the context, back in the
    // fresh state saved when it was made, so neither the scale nor the
    // program's own drawing state carries over from an earlier draw.
    auto st = cairoState();
    void* target = currentWindow();
    if (st.cc() !is null && gc == st.gc() && target == st.window()
        && w == st.w_ && h == st.h_ && scale == st.scale_)
    {
        cairo_restore(st.cc());
        cairo_save(st.cc());
        return st.cc();
    }

    cairoCtxt = cairoMakeCurrent(gc, w, h);
    st.window(target);
    st.w_ = w;
    st.h_ = h;
    st.scale_ = scale;
    cairo_scale(cairoCtxt, scale, scale);
    cairo_save(cairoCtxt);
    return cairoCtxt;
}

/*
  Creates a cairo_surface_t object for what drawing currently targets.
  `gc` is an HDC on Windows and unused on X11; `w` and `h` are unused on
  Windows.
*/
private cairo_surface_t* cairoCreateSurface(void* gc, int w, int h)
{
    version (linux)
        return cairo_xlib_surface_create(x11Display(), fldraw.currentDrawable(), fl_visual.visual, w, h);
    else
        return cairo_win32_surface_create(cast(HDC) gc);
}

/// Creates a fresh Cairo context from a `gc` and the given size
/// (`Fl::Private::cairo_make_current()`), replacing the current one.
package(fl) cairo_t* cairoMakeCurrent(void* gc, int w, int h)
{
    cairoState().gc(gc); // keep track for next time
    cairo_surface_t* s = cairoCreateSurface(gc, w, h);

    cairo_t* c = cairo_create(s);

    cairoState().cc(c); // and purge any previously owned context
    cairo_surface_destroy(s);
    return c;
}

/**
 * Flushes Cairo drawings on Cairo context `c`.
 *
 * Call this when all your drawing on the Cairo context is finished. A
 * `CairoWindow` does this automatically after its draw callback returns.
 * In an overridden `draw()` of your own window class:
 * ---
 * cairo_t* cc = cairoMakeCurrent(this); // get the Cairo context for this window
 * // ... your Cairo drawing ...
 * cairoFlush(cc);                       // flush Cairo drawing to the device
 * ---
 */
void cairoFlush(cairo_t* c)
{
    // flush Cairo drawings: necessary at least for Windows
    cairo_surface_t* s = cairo_get_target(c);
    cairo_surface_flush(s);
    version (linux) fldraw.markDrawableDirty();
}
