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
 * the equivalent of FLTK's CMake option
 * FLTK_OPTION_CAIRO_WINDOW. FLTK_OPTION_CAIRO_EXT (FLTK_HAVE_CAIROEXT: a
 * Cairo context attached automatically to every window as it is made
 * current) is not ported, so `cairoAutolinkContext(true)` is a fatal
 * error, exactly as in an FLTK library built without that option.
 *
 * The X11, Wayland and Windows branches of src/Fl_Cairo.cxx are ported.
 * On X11 the Cairo surface wraps the drawable drawing currently targets
 * (a window, or a double window's back buffer during its `draw()`); on
 * Wayland the context is the one the window's draw buffer is drawn with;
 * on Windows it wraps the current device context (`cairo-win32.h`). The
 * macOS branch is not ported.
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
        if (cc_ is null)
            window_ = null;
        ownCc_ = own;
    }

    /// Sets the autolink option. Only available in FLTK with
    /// FLTK_OPTION_CAIRO_EXT, which is not ported: always fatal.
    void autolink(bool b)
    {
        import fl.core : fatal;
        fatal("In Fl::autolink(bool): Cairo autolink() feature is only "
            ~ "available with CMake FLTK_OPTION_CAIRO_EXT.\n"
            ~ "Quitting now.");
    }

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
 * Needs FLTK_OPTION_CAIRO_EXT, which is not ported: always fatal.
 */
void cairoAutolinkContext(bool alink)
{
    cairoState().autolink(alink);
}

/**
 * Gets the current autolink mode for Cairo support: false if no Cairo
 * context autolink is made for each window (always the case here).
 */
bool cairoAutolinkContext()
{
    return cairoState().autolink();
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
 * A new Cairo context is not always re-created: if the current graphics
 * context and the current window didn't change between two calls, the
 * previous one is kept. After this call, `cairoCc()` returns this context.
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

    // don't re-create a context if it's the same gc/window combination
    if (gc == cairoState().gc() && cast(void*) wi.xid() == cairoState().window())
        return cairoCc();

    // Scale the Cairo context appropriately.
    import fl.core : screenScale;
    float scale = screenScale(wi.screenNum()); // get the screen scaling factor

    version (linux)
        cairoCtxt = cairoMakeCurrent(null, cast(int)(wi.w() * scale), cast(int)(wi.h() * scale));
    else // on Windows, the size is not used
        cairoCtxt = cairoMakeCurrent(gc, wi.w(), wi.h());

    cairoState().window(cast(void*) wi.xid());

    cairo_scale(cairoCtxt, scale, scale);
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

/// Creates a Cairo context from a `gc` and the given size
/// (`Fl::Private::cairo_make_current()`).
package(fl) cairo_t* cairoMakeCurrent(void* gc, int w, int h)
{
    if (gc == cairoState().gc()
        && currentWindow() == cairoState().window()
        && cairoState().cc() !is null) // no need to create a cc, just return that one
        return cairoState().cc();

    // we need to (re-)create a fresh cc ...
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
}
