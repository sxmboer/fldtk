/*
 * OpenGL on Wayland: port of `src/drivers/Wayland/Fl_Wayland_Gl_Window_
 * Driver.{H,cxx}`. `fl.gl_window_driver` forwards here when the program
 * runs on the Wayland backend (`fl.platform_wayland`); like that module
 * it is free functions, with the per-window state FLTK keeps in its
 * driver object held in the window's `WldWindow` instead.
 *
 * How a `GlWindow` is shown:
 * - Its `wl_surface` gets no shared-memory buffer from fldtk. The first
 *   `makeCurrent()` wraps it in a `wl_egl_window` and creates an EGL
 *   window surface on it (`makeCurrentBefore()`), at the window's size
 *   in pixels and its screen's integer buffer scale; EGL attaches its
 *   own buffers to the surface. A GL window doesn't use the compositor's
 *   fractional scale: at a fractional scale the compositor resamples it,
 *   as FLTK does.
 * - Wayland windows are always double-buffered: `find()` adds
 *   `modeDouble` to every mode (FLTK found `EGL_SINGLE_BUFFER` is
 *   reported as a back buffer anyway).
 * - Drawing is paced by frame callbacks, at the screen's refresh rate:
 *   while the last frame of a GL window hasn't been shown, the window
 *   isn't drawn again (`fl.platform_wayland`'s `flushWindow()`), and an
 *   event loop running idle callbacks waits for that frame instead of
 *   spinning (`waitForEventOrTimeout()`), as a blocking buffer swap
 *   makes it wait on X11. A program that animates from an idle callback
 *   thus runs at the same speed on both. EGL's own swap interval is 0,
 *   so a swap never blocks (EGL's wait would freeze the program while
 *   the window is minimized or hidden, when frame callbacks stop).
 *   FLTK draws as often as the program asks and postpones the swap,
 *   showing only the last frame drawn before each refresh.
 *   `swapInterval(0)` turns the pacing off.
 * - The software overlay (`GlWindow.redrawOverlay()`) is drawn into the
 *   back buffer, over a freshly drawn scene, before the swap
 *   (`fl.gl_window.flushGlWindow()`): only a swapped back buffer
 *   reaches the screen, and after a swap the back buffer holds an older
 *   frame, not the scene just shown. FLTK draws the overlay into the
 *   front buffer and copies buffers back and forth with
 *   `glCopyPixels()`, which relies on the back buffer surviving the
 *   swap; on Wayland old overlays then pile up.
 * - A GL subwindow is a `wl_subsurface` like any subwindow; its GL scene
 *   isn't clipped to its parent, as in FLTK.
 *
 * `gl_start()`/`gl_finish()` draw into a non-GL window through a
 * transparent subsurface placed over it with its own EGL surface, as in
 * FLTK. Unlike FLTK, the subsurface is cleared once per repaint of the
 * window rather than at every `gl_start()` (so several widgets can draw
 * GL in one window), the window is always repainted whole while it has
 * one, and its frame is swapped once the window's `draw()` returns
 * (`presentGlStart()`, called from `fl.platform_wayland`), shown together
 * with the window's own next commit; FLTK never swaps it, so its
 * `gl_start()` drawing doesn't reach the screen on Wayland.
 *
 * Only compiled into a build with Wayland support
 * (`version (FLDTK_HAVE_WAYLAND)`).
 */
module fl.wayland_gl_window_driver;

version (FLDTK_HAVE_WAYLAND):

import fl.egl;
import fl.wayland_egl;
import fl.wayland_client;
import fl.wayland_protocol;
import fl.opengl;
import fl.enumerations : modeAlpha, modeRgb8, modeDepth, modeDepth32, modeMultisample, modeStencil;
import fl.window : FlWindow = Window;
import fl.gl_window : GlWindow;
import fl.core : fatal, screenScale;
import platformWayland = fl.platform_wayland;
import fl.platform_wayland : WldWindow;

private EGLDisplay eglDisplay_ = EGL_NO_DISPLAY;
private EGLConfig glStartConf_;  // the config of gl_start()'s surfaces: glVisual()'s
private EGLint swapInterval_ = 1; // 0: GL windows aren't paced by frame callbacks
private EGLint maxSwapInterval_ = 1000;
private EGLint minSwapInterval_ = 0;

/// What `gl_start()` draws into on a non-GL window: a transparent
/// subsurface above the window's own surface (FLTK's
/// `struct gl_start_support`).
package(fl) final class GlStartSurface
{
    wl_surface* surface;
    wl_subsurface* subsurface;
    wl_egl_window* eglWindow;
    EGLSurface eglSurface;
    EGLContext context;     // the gl_start() context, once made current on it
    bool intervalSet;       // its swap interval is set to 0
    bool drawn;             // gl_start() drew into it during this repaint
}

/// Ported from `Fl_Wayland_Gl_Window_Driver::init()`: connects EGL to
/// the Wayland display, once.
private void initEgl()
{
    if (eglDisplay_ != EGL_NO_DISPLAY) return;
    platformWayland.openDisplay();
    eglDisplay_ = eglGetDisplay(cast(EGLNativeDisplayType) platformWayland.waylandDisplay());
    if (eglDisplay_ == EGL_NO_DISPLAY) fatal("Can't create egl display");
    EGLint major, minor;
    if (eglInitialize(eglDisplay_, &major, &minor) != EGL_TRUE) fatal("Can't initialise egl display");
    eglBindAPI(EGL_OPENGL_API);
}

/**
 * The EGL config for `mode` (which already includes `modeDouble`), or
 * null when there is none -- the config-choosing part of
 * `Fl_Wayland_Gl_Window_Driver::find()`. FLTK stops the program when
 * there is no config; returning null lets `GlWindow.canDo()` answer, as
 * on X11. The attribute list (`alist`) of `GlWindow.mode()` is ignored
 * here, as in FLTK.
 */
package(fl) EGLConfig chooseConfig(int mode)
{
    initEgl();
    EGLint[19] attribs = [
        EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
        EGL_RED_SIZE, 8,
        EGL_GREEN_SIZE, 8,
        EGL_BLUE_SIZE, 8,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_BIT,
        EGL_DEPTH_SIZE, 0,      // [11]
        EGL_SAMPLE_BUFFERS, 0,  // [13]
        EGL_STENCIL_SIZE, 0,    // [15]
        EGL_ALPHA_SIZE, 0,      // [17]
        EGL_NONE,
    ];
    if (mode & modeDepth32) attribs[11] = 32;  // at least 32 bits
    else if (mode & modeDepth) attribs[11] = 1; // any size
    if (mode & modeMultisample) attribs[13] = 1;
    if (mode & modeStencil) attribs[15] = 1;
    if (mode & modeAlpha) attribs[17] = (mode & modeRgb8) ? 8 : 1;

    EGLConfig conf;
    EGLint n;
    eglChooseConfig(eglDisplay_, attribs.ptr, &conf, 1, &n);
    if (n == 0 && (mode & modeMultisample))
    {
        attribs[13] = 0;
        eglChooseConfig(eglDisplay_, attribs.ptr, &conf, 1, &n);
    }
    if (n == 0) return null;
    eglGetConfigAttrib(eglDisplay_, conf, EGL_MAX_SWAP_INTERVAL, &maxSwapInterval_);
    eglGetConfigAttrib(eglDisplay_, conf, EGL_MIN_SWAP_INTERVAL, &minSwapInterval_);
    return conf;
}

/// Ported from `Fl_Wayland_Gl_Window_Driver::create_gl_context()`:
/// sharing display lists and textures with `shared_`, the first context
/// created, when there is one.
package(fl) EGLContext createContext(EGLConfig conf, EGLContext shared_)
{
    initEgl();
    static immutable EGLint[3] attribs = [EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE];
    return eglCreateContext(eglDisplay_, conf, shared_ !is null ? shared_ : EGL_NO_CONTEXT, attribs.ptr);
}

/// The integer buffer scale of `win`'s screen, 1 before it is shown --
/// FLTK's `wld_scale()`.
private int bufferScale(const FlWindow win)
{
    return platformWayland.glBufferScale(cast(FlWindow) win);
}

/// Ported from `Fl_Wayland_Gl_Window_Driver::pixels_per_unit()`.
package(fl) float pixelsPerUnit(const FlWindow win)
{
    return bufferScale(win) * screenScale(win.screenNum());
}

/**
 * Ported from `Fl_Wayland_Gl_Window_Driver::make_current_before()`:
 * gives `win`'s surface its `wl_egl_window` and EGL surface the first
 * time it is made current (again after its context was deleted). A
 * subwindow waits until its toplevel window is on a screen, whose scale
 * it needs.
 */
package(fl) void makeCurrentBefore(GlWindow win, EGLConfig conf)
{
    auto w = platformWayland.wldWindowOf(win);
    if (w is null || w.eglWindow !is null || w.surface is null) return;
    if (win.parent !is null)
    {
        platformWayland.waitForScreen(win.topWindow());
        // events handled while waiting may have drawn the window already
        if (w.eglWindow !is null || w.surface is null) return;
    }
    int scale = bufferScale(win);
    int W = win.pixelW() / scale * scale, H = win.pixelH() / scale * scale;
    w.eglWindow = wl_egl_window_create(w.surface, W > 0 ? W : scale, H > 0 ? H : scale);
    if (w.eglWindow is null) fatal("Can't create egl window with wl_egl_window_create()");
    w.eglSurface = eglCreateWindowSurface(eglDisplay_, conf, cast(EGLNativeWindowType) w.eglWindow, null);
    w.eglIntervalSet = false; // set to 0 once current (see the module comment)
    wl_surface_set_buffer_scale(w.surface, scale);
    if (win.mode() & modeAlpha) wl_surface_set_opaque_region(w.surface, null);
}

/**
 * Ported from `Fl_Wayland_Gl_Window_Driver::set_gl_context()`: makes
 * `context` current on `win`'s EGL surface -- or, for a window that is
 * not a `GlWindow` (`gl_start()`), on the transparent surface over it,
 * created here the first time. `cachedWindow` is
 * `fl.gl_window_driver`'s record of the window made current last.
 */
package(fl) void setGlContext(FlWindow win, EGLContext context, ref void* cachedWindow)
{
    auto w = platformWayland.wldWindowOf(win);
    if (w is null) return;
    auto glWin = win.asGlWindow();
    EGLSurface target = w.eglSurface;
    GlStartSurface gs;
    if (target is null && glWin is null)
    {
        if (w.glStart is null) w.glStart = createGlStartSurface(w);
        gs = w.glStart;
        target = gs.eglSurface;
    }
    if (target is null) return;
    if (context != eglGetCurrentContext() || cast(void*) win != cachedWindow)
    {
        cachedWindow = cast(void*) win;
        if (!eglMakeCurrent(eglDisplay_, target, target, context))
        {
            import std.stdio : stderr;
            stderr.writefln("eglMakeCurrent() failed (EGL error 0x%x)", eglGetError());
            return;
        }
    }
    if (gs !is null)
    {
        gs.context = context;
        // Its frames are committed with the window's (a synchronized
        // subsurface), so a swap must never wait for a frame callback.
        if (!gs.intervalSet) eglSwapInterval(eglDisplay_, 0);
        gs.intervalSet = true;
        return;
    }
    w.eglContext = context;
    if (!w.eglIntervalSet)
    {
        eglSwapInterval(eglDisplay_, 0); // applies to the surface just made current
        w.eglIntervalSet = true;
    }
    if (!(glWin.mode() & modeAlpha)) // useful at least for Linux on MacBook hardware (FLTK)
    {
        GLfloat[4] vals;
        glGetFloatv(GL_COLOR_CLEAR_VALUE, vals.ptr);
        if (vals[3] == 0) glClearColor(vals[0], vals[1], vals[2], 1);
    }
}

/// The `gl_start()` surface of window `w` -- the part of FLTK's
/// `set_gl_context()` that creates it. It sits at the window's origin,
/// above the window's own surface.
private GlStartSurface createGlStartSurface(WldWindow w)
{
    FlWindow win = w.widget;
    auto gs = new GlStartSurface;
    int scale = bufferScale(win);
    float f = screenScale(win.screenNum());
    gs.surface = wl_compositor_create_surface(platformWayland.waylandCompositor());
    gs.subsurface = wl_subcompositor_get_subsurface(platformWayland.waylandSubcompositor(), gs.surface, w.surface);
    wl_subsurface_set_position(gs.subsurface, 0, 0);
    wl_subsurface_place_above(gs.subsurface, w.surface);
    int W = cast(int)(win.w() * f) * scale, H = cast(int)(win.h() * f) * scale;
    gs.eglWindow = wl_egl_window_create(gs.surface, W > 0 ? W : scale, H > 0 ? H : scale);
    wl_surface_set_buffer_scale(gs.surface, scale);
    gs.eglSurface = eglCreateWindowSurface(eglDisplay_, glStartConf_, cast(EGLNativeWindowType) gs.eglWindow, null);
    return gs;
}

/**
 * Ported from `Fl_Wayland_Gl_Window_Driver::delete_gl_context()`:
 * destroys `context` and, when `win` is given, the window's EGL surface
 * and `wl_egl_window`, which `makeCurrentBefore()` creates again.
 */
package(fl) void deleteGlContext(FlWindow win, EGLContext context, ref void* cachedWindow)
{
    EGLContext current = eglGetCurrentContext();
    if (current == context)
    {
        cachedWindow = null;
        eglMakeCurrent(eglDisplay_, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    }
    eglDestroyContext(eglDisplay_, context);
    if (win is null) return;
    if (auto w = platformWayland.wldWindowOf(win))
        destroyEglSurface(w);
}

/// Destroys `w`'s EGL surface and `wl_egl_window`, if it has them.
private void destroyEglSurface(WldWindow w)
{
    if (w.eglSurface !is null)
    {
        if (eglGetCurrentSurface(EGL_DRAW) == w.eglSurface)
            eglMakeCurrent(eglDisplay_, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
        eglDestroySurface(eglDisplay_, w.eglSurface);
    }
    w.eglSurface = null;
    w.eglContext = null;
    w.needSwap = false;
    if (w.eglWindow !is null) wl_egl_window_destroy(w.eglWindow);
    w.eglWindow = null;
}

/**
 * Frees the EGL resources still attached to window `w`, which is being
 * hidden: its `gl_start()` surface (FLTK's `Fl_Wayland_Gl_Plugin::
 * destroy()`), and the EGL surface of a GL window whose context the
 * program owns (`GlWindow.context(ctx, 0)`), which `deleteGlContext()`
 * hasn't freed. Must run before the window's `wl_surface` is destroyed.
 */
package(fl) void windowDestroyed(WldWindow w)
{
    if (eglDisplay_ == EGL_NO_DISPLAY) return;
    destroyEglSurface(w);
    if (auto gs = w.glStart)
    {
        if (eglGetCurrentSurface(EGL_DRAW) == gs.eglSurface)
            eglMakeCurrent(eglDisplay_, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
        eglDestroySurface(eglDisplay_, gs.eglSurface);
        wl_egl_window_destroy(gs.eglWindow);
        wl_subsurface_destroy(gs.subsurface);
        wl_surface_destroy(gs.surface);
        w.glStart = null;
    }
}

/// Ported from `Fl_Wayland_Gl_Window_Driver::surface_frame_done()`: a
/// frame callback of a GL window arrived; a postponed swap happens now,
/// with the window's context made current for it.
extern (C) private void glFrameDone(void* data, wl_callback* cb, uint time) nothrow
{
    auto w = cast(WldWindow) data;
    wl_callback_destroy(cb);
    w.frameCb = null;
    if (!w.needSwap || w.eglSurface is null || w.eglContext is null) return;
    w.needSwap = false;
    EGLContext oldContext = eglGetCurrentContext();
    EGLSurface oldDraw = eglGetCurrentSurface(EGL_DRAW);
    EGLSurface oldRead = eglGetCurrentSurface(EGL_READ);
    bool switched = oldContext != w.eglContext || oldDraw != w.eglSurface;
    if (switched) eglMakeCurrent(eglDisplay_, w.eglSurface, w.eglSurface, w.eglContext);
    requestFrame(w);
    eglSwapBuffers(eglDisplay_, w.eglSurface);
    if (switched) eglMakeCurrent(eglDisplay_, oldDraw, oldRead, oldContext);
}

private __gshared wl_callback_listener glFrameListener = { done: &glFrameDone };

private void requestFrame(WldWindow w) nothrow
{
    w.frameCb = wl_surface_frame(w.surface);
    wl_callback_add_listener(w.frameCb, &glFrameListener, cast(void*) w);
}

/**
 * Ported from `Fl_Wayland_Gl_Window_Driver::swap_buffers()`, without its
 * overlay part (see the module comment): swaps `win`'s buffers, or,
 * while a frame callback is pending, notes that the swap is to be done
 * when it arrives.
 */
package(fl) void swapBuffers(GlWindow win)
{
    auto w = platformWayland.wldWindowOf(win);
    if (w is null || w.eglSurface is null) return;
    if (w.frameCb !is null)
    {
        w.needSwap = true;
        return;
    }
    requestFrame(w);
    eglSwapBuffers(eglDisplay_, w.eglSurface);
    w.needSwap = false;
}

/**
 * Ported from `Fl_Wayland_Gl_Window_Driver::resize()`: gives `win`'s
 * `wl_egl_window` the size `W` x `H` (FLTK units) in pixels, at the
 * window's scale. Called before the window takes the new size.
 */
package(fl) void resize(GlWindow win, int W, int H)
{
    auto w = platformWayland.wldWindowOf(win);
    if (w is null || w.eglWindow is null) return;
    float f = screenScale(win.screenNum());
    int s = bufferScale(win);
    W = cast(int)(W * f) * s; // multiples of the buffer scale
    H = cast(int)(H * f) * s;
    if (W <= 0) W = s;
    if (H <= 0) H = s;
    int W2, H2;
    wl_egl_window_get_attached_size(w.eglWindow, &W2, &H2);
    if (W2 != W || H2 != H)
    {
        wl_egl_window_resize(w.eglWindow, W, H, 0, 0);
        wl_surface_set_buffer_scale(w.surface, s);
    }
}

/// `win`'s screen scale changed: its `wl_egl_window` takes the size of
/// the new scale, and its GL state is redone (`valid(false)`) -- what
/// FLTK's `output_done()` and `Fl_Wayland_Gl_Plugin::invalidate()` do
/// for GL windows.
package(fl) void rescale(GlWindow win)
{
    resize(win, win.w(), win.h());
    win.valid(false);
}

/// `Fl_Wayland_Gl_Window_Driver::swap_interval(int)`, whose `eglSwapInterval()`
/// becomes the frame-callback pacing here (see the module comment): 0
/// turns it off, any other value turns it on (every frame callback, so
/// an interval above 1 counts as 1). For every GL window, as in FLTK.
package(fl) void swapInterval(int interval)
{
    if (interval < minSwapInterval_) interval = minSwapInterval_;
    if (interval > maxSwapInterval_) interval = maxSwapInterval_;
    swapInterval_ = interval;
}

/// Whether GL windows are drawn at most once per frame callback.
package(fl) bool pacedByFrames()
{
    return swapInterval_ != 0;
}

/// Ported from `Fl_Wayland_Gl_Window_Driver::swap_interval() const`.
package(fl) int swapInterval()
{
    return swapInterval_;
}

/// Ported from `Fl_Wayland_Gl_Window_Driver::gl_visual()`: the config
/// `gl_start()`'s surfaces are created with.
package(fl) void glVisual(EGLConfig conf)
{
    glStartConf_ = conf;
}

/**
 * Ported from `Fl_Wayland_Gl_Window_Driver::gl_start()`: sizes the
 * `gl_start()` surface of `win` to the window, and clears it to
 * transparent at the first `gl_start()` of a repaint. Returns the
 * number of pixels per FLTK unit of that surface.
 */
package(fl) float glStart(FlWindow win)
{
    auto w = platformWayland.wldWindowOf(win);
    if (w is null || w.glStart is null) return pixelsPerUnit(win);
    auto gs = w.glStart;
    float f = screenScale(win.screenNum());
    int s = bufferScale(win);
    int W = cast(int)(win.w() * f) * s, H = cast(int)(win.h() * f) * s;
    if (W <= 0) W = s;
    if (H <= 0) H = s;
    int W2, H2;
    wl_egl_window_get_attached_size(gs.eglWindow, &W2, &H2);
    if (W2 != W || H2 != H)
    {
        wl_egl_window_resize(gs.eglWindow, W, H, 0, 0);
        wl_surface_set_buffer_scale(gs.surface, s);
    }
    if (!gs.drawn)
    {
        gs.drawn = true;
        glDisable(GL_SCISSOR_TEST);
        glClearColor(0, 0, 0, 0);
        glClear(GL_COLOR_BUFFER_BIT);
    }
    return pixelsPerUnit(win);
}

/// A repaint of window `w` is starting: the next `gl_start()` clears
/// its `gl_start()` surface.
package(fl) void glStartRepaintBegins(WldWindow w)
{
    if (w.glStart !is null) w.glStart.drawn = false;
}

/// A repaint of window `w` is done: what `gl_start()` drew during it is
/// swapped, to be shown with the window's next commit.
package(fl) void presentGlStart(WldWindow w)
{
    auto gs = w.glStart;
    if (gs is null || !gs.drawn || gs.context is null) return;
    if (eglGetCurrentContext() != gs.context || eglGetCurrentSurface(EGL_DRAW) != gs.eglSurface)
    {
        eglMakeCurrent(eglDisplay_, gs.eglSurface, gs.eglSurface, gs.context);
        import glDriver = fl.gl_window_driver;
        glDriver.forgetCachedWindow();
    }
    eglSwapBuffers(eglDisplay_, gs.eglSurface);
}

/// Ported from `Fl_Wayland_Gl_Window_Driver::GetProcAddress()`, which
/// looks the name up in the program's libraries; `eglGetProcAddress()`
/// finds every GL function, core or extension.
package(fl) void* getProcAddress(const(char)* procName)
{
    return eglGetProcAddress(procName);
}
