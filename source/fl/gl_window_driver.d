/*
 * Port of `src/Fl_Gl_Window_Driver.H` + `src/Fl_Gl_Choice.cxx` +
 * `src/drivers/X11/Fl_X11_Gl_Window_Driver.{H,cxx}` (FLTK 1.5.0), merged into one module of free functions plus
 * module-level state, one concrete module per FLTK driver pair
 * rather than a virtual `Fl_Gl_Window_Driver`/`Fl_X11_Gl_Window_Driver`
 * hierarchy -- `fl.gl_choice` gets the same treatment. This mirrors the
 * existing `fl.platform_x11` <-> `fl.window` relationship exactly (free
 * functions operating on a
 * widget passed in, rather than a separate per-window driver object
 * FLTK needs only because it has several platform subclasses to
 * choose between at runtime -- this port has one).
 *
 * FLTK keeps most of this state as `static` members of
 * `Fl_Gl_Window_Driver` (`context_list`, `nContext`, `first`,
 * `cached_window`, `copy`) precisely because it's genuinely
 * process-global, shared across every `Fl_Gl_Window`/GL context in the
 * program -- not per-window state. That maps directly onto plain
 * module-level variables here, the same translation CONVENTIONS.md's
 * "D module-level variables are thread-local by default" note already
 * covers for other single-threaded-by-convention global state in this
 * port (GL context/window creation only ever happens on the main
 * thread here, matching FLTK's own single-threaded-GUI assumption
 * -- no `__gshared` needed).
 *
 * **Scope**: visual selection, context create/set/delete, buffer swap +
 * swap interval, `waitGL()`, `glStart()`, `glVisual()`, `getProcAddress()`,
 * `captureGlRectangle()`. (`Fl_Gl_Window_Driver::invalidate()`'s own
 * body is purely overlay-related bookkeeping, so it isn't ported here
 * at all; `fl.gl_window.GlWindow.invalidate()` implements the rest of
 * `Fl_Gl_Window::invalidate()` directly instead of calling into this
 * module.) Deliberately not ported: the legacy `glXUseXFont`-based
 * bitmap-font text path (`drawStringLegacy*`, `glBitmapFont`, `getList`,
 * `genlistsize`, `fontnumToFontdescriptor`) -- `fl.gl` targets the
 * texture-rectangle path only, see that module's own doc comment for the
 * scope decision (`alphaMaskForString()`/`drawStringWithTexture()`, that
 * same path's own implementation, live there, not here).
 * `switchToGl1()`/`switchBack()` are real, below -- called from
 * `GlWindow.drawBegin()`/`drawEnd()` whenever `mode() & modeOpengl3`. The
 * overlay methods
 * (`makeOverlay`/`hideOverlay`/`makeOverlayCurrent`/`redrawOverlay`/
 * `canDoOverlay`) live directly on `fl.gl_window.GlWindow` itself, not
 * this module, matching where `Fl_Gl_Window`'s own public methods of
 * the same names sit FLTK (only `swapBuffers()`'s
 * `glCopyPixels()`-based overlay-copy branch, from
 * `Fl_X11_Gl_Window_Driver::swap_buffers()`, actually lives in this
 * driver module -- see that function's own doc comment).
 *
 * **Windows (WGL) support**: ported from `Fl_WinAPI_Gl_Window_Driver`
 * (`src/drivers/WinAPI/Fl_WinAPI_Gl_Window_Driver.cxx`), matching this
 * module's own scope exactly -- the base-class-default methods that
 * file's real FLTK source confirms Windows never overrides at all
 * (`waitGL()`, `gl_visual()`'s X11-only `fl_visual`/`fl_colormap`
 * reassignment, `before_show()`) stay no-ops/base-behavior here too, not
 * guessed. **Real hardware overlay-plane support
 * (`Fl_WinAPI_Gl_Window_Driver`'s own `#if HAVE_GL_OVERLAY` block --
 * `wglDescribeLayerPlane()`/`wglSetLayerPaletteEntries()`/
 * `wglSwapLayerBuffers()`) is deliberately NOT ported**: it's a real,
 * separate mechanism from the software-simulated (`glCopyPixels()`-
 * based) overlay this port already has for X11, needs hardware/driver
 * support that's been effectively obsolete for decades, and FLTK's
 * own base-class fallback (no hardware overlay -- `can_do_overlay()`
 * returns false, `swap_buffers()`/`make_overlay_current()` skip the
 * `#if` block entirely) is exactly what X11 already uses here
 * unconditionally. So Windows reuses the *same* software-simulated
 * overlay path X11 does (`GlWindow`'s own `redrawOverlay()`/
 * `makeOverlayCurrent()`/etc, and this module's `swapBuffers()` below)
 * rather than a second, hardware-specific implementation -- observably
 * identical to a real Windows FLTK build on any GPU without a working
 * overlay plane, which by now is effectively all of them.
 */
module fl.gl_window_driver;

version (linux) version = FldtkGl;
version (Windows) version = FldtkGl;

version (FldtkGl):

import fl.opengl;
import fl.gl_choice : GlChoice;
import fl.enumerations : Mode, modeIndex, modeRgb8, modeAlpha, modeAccum, modeDouble,
    modeDepth32, modeDepth, modeStencil, modeStereo, modeMultisample;
import fl.window : FlWindow = Window;
import fl.image : RGBImage;

version (linux)
{
    import fl.glx;
    import fl.xlib : XVisualInfo, Colormap, Display, Window, AllocNone, XRootWindow,
        XCreateColormap;
    import platformX11 = fl.platform_x11;
}
else version (Windows)
{
    import core.sys.windows.windows;

    /// Matches `fl.glx.GLXContext`'s role for the rest of this module's
    /// (mostly platform-independent) code -- an opaque GL context
    /// handle, real type `HGLRC` here.
    alias GLXContext = HGLRC;
}

/// Ported from `Fl_Gl_Window::flush()`'s local `SWAP_TYPE` values
/// (`src/Fl_Gl_Window.cxx`) -- what's left in the back buffer after
/// `glXSwapBuffers()`. Only `undefined_`/`copy_` are reachable
/// (`swapType()` always returns `copy_` below, matching FLTK's own X11
/// driver default -- see that function's doc comment); the other two
/// exist so `fl.gl_window`'s real `flush()` port can use the same enum
/// without renumbering.
private enum : char
{
    undefined_ = 1,
    swap_ = 2,
    copy_ = 3,
    nodamage_ = 4,
}

/// `Fl_X11_Gl_Choice` in FLTK (a plain data holder, `vis`/
/// `colormap` on `GlChoice` itself -- see that module's doc comment).
private GlChoice first_;

/// `Fl_Gl_Window_Driver::context_list`/`nContext` -- every GL context
/// created by `createGlContext()`, in creation order. `context_list[0]`
/// (the *first* one ever created) is what every subsequently created
/// context shares display lists/textures with, matching FLTK's
/// `create_gl_context()` (`shared_ctx = context_list ? context_list[0]
/// : 0`).
private GLXContext[] contextList_;

/// `Fl_Gl_Window_Driver::cached_window` -- de-dupes redundant
/// `glXMakeCurrent()` calls in `setGlContext()` when the same
/// (window, context) pair is already current.
private void* cachedWindow_;

void addContext(GLXContext ctx)
{
    if (!ctx) return;
    contextList_ ~= ctx;
}

void delContext(GLXContext ctx)
{
    foreach (i, c; contextList_)
    {
        if (c == ctx)
        {
            contextList_ = contextList_[0 .. i] ~ contextList_[i + 1 .. $];
            break;
        }
    }
    // FLTK also calls gl_remove_displaylist_fonts() here once the
    // list empties -- a Phase 3 (text/font) concern, not applicable yet.
}

/// Ported from `Fl_Gl_Window_Driver::find_begin()` -- searches already-
/// created choices for one matching this exact (mode, alist) pair
/// before `find()` goes to the trouble of calling `glXChooseVisual()`
/// again.
GlChoice findBegin(int mode, const(int)* alist)
{
    for (auto g = first_; g !is null; g = g.next)
        if (g.mode == mode && g.alist == alist)
            return g;
    return null;
}

version (linux)
{
/**
 * Ported from `Fl_X11_Gl_Window_Driver::find()`. Builds a GLX
 * attribute list from an `Fl_Mode` bitmask (unless the caller supplied
 * a raw one directly via `alistp`), asks GLX for a matching visual,
 * and picks a colormap for it: the display's own default colormap when
 * the chosen visual happens to match the display's default visual
 * (the common case), otherwise a fresh one built specifically for that
 * visual.
 */
GlChoice find(int mode, const(int)* alistp)
{
    if (auto g = findBegin(mode, alistp))
        return g;

    int[32] list;
    const(int)* blist;

    if (alistp)
        blist = alistp;
    else
    {
        int n = 0;
        if (mode & modeIndex)
        {
            list[n++] = GLX_BUFFER_SIZE;
            list[n++] = 8;
        }
        else
        {
            list[n++] = GLX_RGBA;
            list[n++] = GLX_GREEN_SIZE;
            list[n++] = (mode & modeRgb8) ? 8 : 1;
            if (mode & modeAlpha)
            {
                list[n++] = GLX_ALPHA_SIZE;
                list[n++] = (mode & modeRgb8) ? 8 : 1;
            }
            if (mode & modeAccum)
            {
                list[n++] = GLX_ACCUM_GREEN_SIZE;
                list[n++] = 1;
                if (mode & modeAlpha)
                {
                    list[n++] = GLX_ACCUM_ALPHA_SIZE;
                    list[n++] = 1;
                }
            }
        }
        if (mode & modeDouble)
            list[n++] = GLX_DOUBLEBUFFER;
        if (mode & modeDepth32)
        {
            list[n++] = GLX_DEPTH_SIZE;
            list[n++] = 32;
        }
        else if (mode & modeDepth)
        {
            list[n++] = GLX_DEPTH_SIZE;
            list[n++] = 1;
        }
        if (mode & modeStencil)
        {
            list[n++] = GLX_STENCIL_SIZE;
            list[n++] = 1;
        }
        if (mode & modeStereo)
            list[n++] = GLX_STEREO;
        if (mode & modeMultisample)
        {
            list[n++] = GLX_SAMPLES_SGIS;
            list[n++] = 4;
        }
        list[n] = 0;
        blist = list.ptr;
    }

    platformX11.openDisplay();
    auto visp = glXChooseVisual(platformX11.x11Display(), platformX11.x11Screen(), cast(int*) blist);
    if (!visp)
    {
        if (mode & modeMultisample)
            return find(mode & ~modeMultisample, null);
        return null;
    }

    auto g = new GlChoice(mode, alistp, first_);
    first_ = g;
    g.vis = visp;

    import std.process : environment;

    if (visp.visualid == platformX11.fl_visual.visualid && environment.get("MESA_PRIVATE_CMAP") is null)
        g.colormap = platformX11.fl_colormap;
    else
        g.colormap = XCreateColormap(platformX11.x11Display(),
            XRootWindow(platformX11.x11Display(), platformX11.x11Screen()), visp.visual, AllocNone);

    return g;
}
}
else version (Windows)
{
/**
 * Ported from `Fl_WinAPI_Gl_Window_Driver::find()`. Unlike GLX's
 * attribute-list-based `glXChooseVisual()`, Windows has no equivalent
 * single call -- this walks every pixel format the system reports via
 * `DescribePixelFormat()` and picks the best one satisfying `mode`'s
 * requirements, ported verbatim from FLTK's own scoring loop
 * (prefers hardware-accelerated over generic/software, then a format
 * offering an overlay plane, then one supporting desktop composition,
 * then more color/depth bits, up to 32 total -- matching the real
 * source's own comments, including the historical `STR #3119`
 * reference). Queried against the whole screen's own DC
 * (`GetDC(null)`) rather than FLTK's `fl_graphics_driver->gc()`
 * preference -- this port has no equivalent "current gc" accessor
 * exposed from `fl.gdi_graphics_driver`, and the reported pixel-format
 * list is a property of the GPU driver, not of which specific DC is
 * queried, so this is an observably-identical simplification, not a
 * behavior change.
 */
GlChoice find(int mode, const(int)* alistp)
{
    if (auto g = findBegin(mode, alistp))
        return g;

    HDC gc = GetDC(null);
    scope (exit) ReleaseDC(null, gc);

    int pixelformat = 0;
    PIXELFORMATDESCRIPTOR chosenPfd;
    for (int i = 1; ; i++)
    {
        PIXELFORMATDESCRIPTOR pfd;
        if (!DescribePixelFormat(gc, i, PIXELFORMATDESCRIPTOR.sizeof, &pfd)) break;

        if ((~pfd.dwFlags & (PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL)) != 0) continue;
        if (pfd.iPixelType != ((mode & modeIndex) ? PFD_TYPE_COLORINDEX : PFD_TYPE_RGBA)) continue;
        if ((mode & modeAlpha) && !pfd.cAlphaBits) continue;
        if ((mode & modeAccum) && !pfd.cAccumBits) continue;
        if ((!(mode & modeDouble)) != (!(pfd.dwFlags & PFD_DOUBLEBUFFER))) continue;
        if ((!(mode & modeStereo)) != (!(pfd.dwFlags & PFD_STEREO))) continue;
        if ((mode & modeDepth) && !pfd.cDepthBits) continue;
        if ((mode & modeDepth32) && pfd.cDepthBits < 32) continue;
        if ((mode & modeStencil) && !pfd.cStencilBits) continue;

        if (pixelformat)
        {
            if (!(chosenPfd.dwFlags & PFD_GENERIC_FORMAT) && (pfd.dwFlags & PFD_GENERIC_FORMAT))
                continue;
            else if (!(chosenPfd.bReserved & 15) && (pfd.bReserved & 15)) { }
            else if ((chosenPfd.dwFlags & PFD_SUPPORT_COMPOSITION) && !(pfd.dwFlags & PFD_SUPPORT_COMPOSITION))
                continue;
            else if (pfd.cColorBits > 32 || chosenPfd.cColorBits > pfd.cColorBits)
                continue;
            else if (chosenPfd.cDepthBits > pfd.cDepthBits)
                continue;
        }
        pixelformat = i;
        chosenPfd = pfd;
    }

    if (!pixelformat) return null;

    auto g = new GlChoice(mode, alistp, first_);
    first_ = g;
    g.pixelformat = pixelformat;
    g.pfd = chosenPfd;
    return g;
}
}

version (linux)
{
/// Ported from `Fl_X11_Gl_Window_Driver::create_gl_context()`. `win` is
/// unused here (X11 needs only the chosen visual, not the window
/// itself) -- accepted only so `fl.gl_window.GlWindow.makeCurrent()` has
/// one call shape shared with the Windows implementation below, which
/// genuinely does need it.
GLXContext createGlContext(FlWindow win, GlChoice g)
{
    GLXContext shared_ = contextList_.length ? contextList_[0] : null;
    auto ctx = glXCreateContext(platformX11.x11Display(), g.vis, shared_, true);
    if (ctx)
        addContext(ctx);
    return ctx;
}

/// Ported from `Fl_X11_Gl_Window_Driver::set_gl_context()`. `windowKey`
/// is an opaque per-window identity (the owning `GlWindow` instance,
/// as `void*`) standing in for FLTK's raw `Fl_Window*` -- only
/// ever compared for identity, never dereferenced here.
void setGlContext(void* windowKey, Window xid, GLXContext context)
{
    auto current = glXGetCurrentContext();
    if (context != current || windowKey != cachedWindow_)
    {
        cachedWindow_ = windowKey;
        glXMakeCurrent(platformX11.x11Display(), xid, context);
    }
}

/// Ported from `Fl_X11_Gl_Window_Driver::delete_gl_context()`.
void deleteGlContext(GLXContext context)
{
    if (glXGetCurrentContext() == context)
    {
        cachedWindow_ = null;
        glXMakeCurrent(platformX11.x11Display(), 0, null);
    }
    glXDestroyContext(platformX11.x11Display(), context);
    delContext(context);
}
}
else version (Windows)
{
/// `Fl_WinAPI_Window_Driver::private_dc`'s equivalent -- a cached
/// per-`HWND` device context with its pixel format already set (real
/// Win32 constraint: `SetPixelFormat()` may be called at most once ever
/// for a given window), matching FLTK's own per-window `private_dc`
/// field (this port has no per-window driver object to hang it off of,
/// so it lives here instead, keyed by the window handle). Lazily
/// created by `createGlContext()` below; `deleteGlContext()`
/// deliberately does NOT release/remove it, matching FLTK's own
/// `Fl_WinAPI_Window_Driver::~Fl_WinAPI_Window_Driver()`, which likewise
/// never releases `private_dc` explicitly -- the window's own real
/// destruction reclaims it along with the `HWND` itself.
private HDC[HWND] privateDcCache_;

/// Ported from `Fl_WinAPI_Gl_Window_Driver::do_create_gl_context()` +
/// `create_gl_context()` (the `layer` parameter is always 0 here --
/// FLTK's own layer-context path is only reachable from the
/// hardware-overlay code this port deliberately doesn't port, see this
/// module's own top comment).
GLXContext createGlContext(FlWindow win, GlChoice g)
{
    HWND hwnd = win.xid();
    HDC hdc = privateDcCache_.get(hwnd, null);
    if (hdc is null)
    {
        hdc = GetDCEx(hwnd, null, DCX_CACHE);
        SetPixelFormat(hdc, g.pixelformat, &g.pfd);
        privateDcCache_[hwnd] = hdc;
    }
    auto ctx = wglCreateContext(hdc);
    if (ctx)
    {
        if (contextList_.length)
            wglShareLists(contextList_[0], ctx);
        addContext(ctx);
    }
    return ctx;
}

/// Ported from `Fl_WinAPI_Gl_Window_Driver::set_gl_context()`.
/// `windowKey` is an opaque per-window identity (the owning `GlWindow`
/// instance, as `void*`) standing in for FLTK's raw `Fl_Window*`.
void setGlContext(void* windowKey, HWND hwnd, GLXContext context)
{
    auto current = wglGetCurrentContext();
    if (context != current || windowKey != cachedWindow_)
    {
        cachedWindow_ = windowKey;
        wglMakeCurrent(privateDcCache_.get(hwnd, null), context);
    }
}

/// Ported from `Fl_WinAPI_Gl_Window_Driver::delete_gl_context()`.
void deleteGlContext(GLXContext context)
{
    if (wglGetCurrentContext() == context)
    {
        cachedWindow_ = null;
        wglMakeCurrent(null, null);
    }
    wglDeleteContext(context);
    delContext(context);
}
}

/**
 * The shared, 100% portable half of `swapBuffers()` (below) -- ported
 * from `Fl_X11_Gl_Window_Driver::swap_buffers()`'s software-simulated-
 * overlay branch (`Fl_Gl_Overlay.cxx`), pure immediate-mode GL calls
 * with no platform-specific dependency at all: a
 * `glCopyPixels()` of the back buffer onto the front buffer, bracketed
 * by pushing/restoring an identity ortho projection and the current
 * raster position via a temporary `GL_PROJECTION`/`GL_MODELVIEW` matrix
 * save/restore -- ported line-for-line, this bookkeeping has no simpler
 * D-native equivalent, it's just raw GL state juggling. This is what
 * lets `fl.gl_window.flushGlWindow()` draw fresh overlay content
 * directly into the front buffer afterward without losing the clean,
 * already-drawn back buffer underneath it (a real buffer-present call
 * would instead present *and discard* it) -- see `swapBuffers()`'s own
 * doc comment for the platform-specific "real swap" half this replaces
 * when no overlay is active.
 */
private void copyBackToFrontForOverlay(int pixelW, int pixelH)
{
    GLint matrixmode;
    GLfloat[4] pos;
    glGetIntegerv(GL_MATRIX_MODE, &matrixmode);
    glGetFloatv(GL_CURRENT_RASTER_POSITION, pos.ptr);
    glMatrixMode(GL_PROJECTION);
    glPushMatrix();
    glLoadIdentity();
    glMatrixMode(GL_MODELVIEW);
    glPushMatrix();
    glLoadIdentity();
    glScalef(2.0f / pixelW, 2.0f / pixelH, 1.0f);
    glTranslatef(-pixelW / 2.0f, -pixelH / 2.0f, 0.0f);
    glRasterPos2i(0, 0);
    glReadBuffer(GL_BACK);
    glDrawBuffer(GL_FRONT);
    glCopyPixels(0, 0, pixelW, pixelH, GL_COLOR);
    glPopMatrix(); // GL_MODELVIEW
    glMatrixMode(GL_PROJECTION);
    glPopMatrix();
    glMatrixMode(matrixmode);
    glRasterPos3f(pos[0], pos[1], pos[2]);
}

version (linux)
{
/// Ported from `Fl_X11_Gl_Window_Driver::swap_buffers()`. When
/// `overlayActive` is false this is just `glXSwapBuffers()`; when true,
/// see `copyBackToFrontForOverlay()`'s own doc comment above.
void swapBuffers(Window xid, int pixelW, int pixelH, bool overlayActive)
{
    if (!xid) return;
    if (overlayActive)
        copyBackToFrontForOverlay(pixelW, pixelH);
    else
        glXSwapBuffers(platformX11.x11Display(), xid);
}
}
else version (Windows)
{
/// Ported from `Fl_WinAPI_Gl_Window_Driver::swap_buffers()` (its base,
/// non-`HAVE_GL_OVERLAY` case -- see this module's own top comment for
/// why real hardware overlay-plane support isn't ported). When
/// `overlayActive` is false this is just `SwapBuffers()` on the
/// window's cached private DC; when true, see
/// `copyBackToFrontForOverlay()`'s own doc comment above.
void swapBuffers(HWND hwnd, int pixelW, int pixelH, bool overlayActive)
{
    if (!hwnd) return;
    if (overlayActive)
        copyBackToFrontForOverlay(pixelW, pixelH);
    else
        SwapBuffers(privateDcCache_.get(hwnd, null));
}
}

/// Ported from `Fl_X11_Gl_Window_Driver::swap_type()` -- FLTK's
/// X11 driver unconditionally returns `copy_` (`COPY`); the
/// environment-variable override (`GL_SWAP_TYPE`) lives in
/// `fl.gl_window`'s own `Fl_Gl_Window::flush()` port, not here.
char swapType()
{
    return copy_;
}

/// `Fl_Gl_Window_Driver::gl_start_context`'s own `gl_choice` -- the
/// process-wide default GL visual `glVisual()` below records, read by
/// `fl.gl.gl_start()` to know whether one was ever selected. `package(fl)`
/// rather than a getter/setter pair: `fl.gl` only ever reads it, never
/// writes it directly (writing goes through `glVisual()`, which also
/// applies the platform-specific side effect X11 needs).
package(fl) GlChoice glChoice_;

version (linux)
{
    // -- swap_interval: same three-extension dance as FLTK, ported
    // faithfully (Fl_X11_Gl_Window_Driver.cxx's own file-local statics
    // become module-level state here instead).

    private
    {
        // -1 = not yet initialized, 0 = none found, 1 = EXT, 2 = MESA, 3 = SGI
        byte swapIntervalType_ = -1;

        alias SetIntervalExt = void function(Display*, Window, int);
        alias SetIntervalMesa = int function(uint);
        alias GetIntervalMesa = int function();
        alias SetIntervalSgi = int function(int);

        SetIntervalExt setIntervalExt_;
        SetIntervalMesa setIntervalMesa_;
        GetIntervalMesa getIntervalMesa_;
        SetIntervalSgi setIntervalSgi_;

        void initSwapInterval()
        {
            if (swapIntervalType_ != -1) return;
            int major = 1, minor = 0;
            glXQueryVersion(platformX11.x11Display(), &major, &minor);
            swapIntervalType_ = 0;
            auto extensions = glXQueryExtensionsString(platformX11.x11Display(), platformX11.x11Screen());

            import std.string : fromStringz;
            import std.algorithm.searching : canFind;

            auto extensionsStr = fromStringz(extensions);
            if (extensionsStr.canFind("GLX_EXT_swap_control") && (major > 1 || minor >= 3))
            {
                setIntervalExt_ = cast(SetIntervalExt) glXGetProcAddressARB(cast(const(ubyte)*) "glXSwapIntervalEXT".ptr);
                swapIntervalType_ = 1;
            }
            else if (extensionsStr.canFind("GLX_MESA_swap_control"))
            {
                setIntervalMesa_ = cast(SetIntervalMesa) glXGetProcAddressARB(
                    cast(const(ubyte)*) "glXSwapIntervalMESA".ptr);
                getIntervalMesa_ = cast(GetIntervalMesa) glXGetProcAddressARB(
                    cast(const(ubyte)*) "glXGetSwapIntervalMESA".ptr);
                swapIntervalType_ = 2;
            }
            else if (extensionsStr.canFind("GLX_SGI_swap_control"))
            {
                setIntervalSgi_ = cast(SetIntervalSgi) glXGetProcAddressARB(cast(const(ubyte)*) "glXSwapIntervalSGI".ptr);
                swapIntervalType_ = 3;
            }
        }
    }

    /// Ported from `Fl_X11_Gl_Window_Driver::swap_interval(int)`.
    void swapInterval(Window xid, int interval)
    {
        if (!xid) return;
        if (swapIntervalType_ == -1) initSwapInterval();
        final switch (swapIntervalType_)
        {
        case 1:
            if (setIntervalExt_) setIntervalExt_(platformX11.x11Display(), xid, interval);
            break;
        case 2:
            if (setIntervalMesa_) setIntervalMesa_(cast(uint) interval);
            break;
        case 3:
            if (setIntervalSgi_) setIntervalSgi_(interval);
            break;
        case 0:
            break;
        }
    }

    /// Ported from `Fl_X11_Gl_Window_Driver::swap_interval() const`.
    int swapInterval(Window xid)
    {
        if (!xid) return -1;
        if (swapIntervalType_ == -1) initSwapInterval();
        int interval = -1;
        switch (swapIntervalType_)
        {
        case 1:
            uint val = 0;
            glXQueryDrawable(platformX11.x11Display(), xid, GLX_SWAP_INTERVAL_EXT, &val);
            interval = cast(int) val;
            break;
        case 2:
            if (getIntervalMesa_) interval = getIntervalMesa_();
            break;
        default:
            break;
        }
        return interval;
    }

    /// Ported from `Fl_X11_Gl_Window_Driver::waitGL()`.
    void waitGL()
    {
        glXWaitGL();
    }

    /// Ported from `Fl_X11_Gl_Window_Driver::gl_start()` -- backs
    /// `fl.gl.gl_start()`'s own per-platform hook (FLTK's base
    /// `Fl_Gl_Window_Driver::gl_start()` is an empty no-op; X11 overrides
    /// it with a `glXWaitX()`, ensuring any pending native-X drawing has
    /// landed before GL starts drawing into the same window).
    void glStart()
    {
        glXWaitX();
    }

    /// Ported from `Fl_X11_Gl_Window_Driver::before_show()`: creates the
    /// window's real X resource against the GLX-chosen visual/colormap
    /// rather than the display default (see `createWindow()`'s own doc
    /// comment in fl.platform_x11 for why a per-call override is used
    /// instead of temporarily reassigning `fl_visual`/`fl_colormap`).
    void beforeShow(FlWindow win, GlChoice g)
    {
        platformX11.createWindow(win, g.vis, g.colormap);
    }

    /**
     * Ported from `Fl_X11_Gl_Window_Driver::gl_visual()` (which itself
     * chains to the base `Fl_Gl_Window_Driver::gl_visual()` in
     * `gl_start.cxx` first) -- backs `Fl::gl_visual()`: reassigns the
     * process-wide default visual/colormap (`fl.platform_x11.fl_visual`/
     * `fl_colormap`) to a GL-compatible one, so every window created
     * afterward (not just `Fl_Gl_Window`s) gets it, matching FLTK's
     * plain-global architecture exactly (see `fl_visual`'s own doc comment
     * in `fl.platform_x11`).
     */
    void glVisual(GlChoice c)
    {
        glChoice_ = c;
        platformX11.fl_visual = c.vis;
        platformX11.fl_colormap = c.colormap;
    }

    /// Ported from `Fl_Gl_Window_Driver::GetProcAddress()`'s X11/GLX
    /// branch (`HAVE_GLXGETPROCADDRESSARB` -- the only one relevant here,
    /// GLX always has this; FLTK's `dlsym()` fallback is Windows/older-
    /// GLX-only and not needed on any target this port builds for).
    void* getProcAddress(const(char)* procName)
    {
        return glXGetProcAddressARB(cast(const(ubyte)*) procName);
    }
}
else version (Windows)
{
    // -- swap_interval: WGL's single WGL_EXT_swap_control extension,
    // resolved the same lazy, cached way as GLX's own three-extension
    // dance above -- ported from Fl_WinAPI_Gl_Window_Driver.cxx's own
    // file-local statics/init_swap_interval().

    private
    {
        // -1 = not yet initialized, 0 = none found, 1 = EXT
        byte swapIntervalType_ = -1;

        alias WglGetExtensionsStringProc = extern (Windows) const(char)* function();
        alias WglSwapIntervalProc = extern (Windows) BOOL function(int);
        alias WglGetSwapIntervalProc = extern (Windows) int function();

        WglSwapIntervalProc wglSwapIntervalExt_;
        WglGetSwapIntervalProc wglGetSwapIntervalExt_;

        void initSwapInterval()
        {
            if (swapIntervalType_ != -1) return;
            swapIntervalType_ = 0;

            auto wglGetExtensionsStringExt = cast(WglGetExtensionsStringProc)
                wglGetProcAddress("wglGetExtensionsStringEXT".ptr);
            if (wglGetExtensionsStringExt is null) return;

            import std.string : fromStringz;
            import std.algorithm.searching : canFind;

            auto extensions = wglGetExtensionsStringExt();
            if (extensions !is null && fromStringz(extensions).canFind("WGL_EXT_swap_control"))
            {
                wglSwapIntervalExt_ = cast(WglSwapIntervalProc) wglGetProcAddress("wglSwapIntervalEXT".ptr);
                wglGetSwapIntervalExt_ = cast(WglGetSwapIntervalProc) wglGetProcAddress("wglGetSwapIntervalEXT".ptr);
                swapIntervalType_ = 1;
            }
        }
    }

    /// Ported from `Fl_WinAPI_Gl_Window_Driver::swap_interval(int)`.
    /// `hwnd` is unused -- WGL's swap interval is a per-*context*
    /// (current-context-wide) setting, not a per-window one, matching
    /// FLTK's own identical parameter-ignoring implementation.
    void swapInterval(HWND hwnd, int interval)
    {
        if (swapIntervalType_ == -1) initSwapInterval();
        if (swapIntervalType_ == 1 && wglSwapIntervalExt_ !is null)
            wglSwapIntervalExt_(interval);
    }

    /// Ported from `Fl_WinAPI_Gl_Window_Driver::swap_interval() const`.
    int swapInterval(HWND hwnd)
    {
        if (swapIntervalType_ == -1) initSwapInterval();
        if (swapIntervalType_ == 1 && wglGetSwapIntervalExt_ !is null)
            return wglGetSwapIntervalExt_();
        return -1;
    }

    /// Ported from the base `Fl_Gl_Window_Driver::waitGL()` -- Windows
    /// never overrides it (confirmed against the real source: no
    /// `Fl_WinAPI_Gl_Window_Driver::waitGL()` exists), so the base
    /// empty-`{}` default applies here too.
    void waitGL()
    {
    }

    /// Ported from the base `Fl_Gl_Window_Driver::gl_start()` -- Windows
    /// never overrides it either (confirmed against the real source: no
    /// `Fl_WinAPI_Gl_Window_Driver::gl_start()` exists), so the base
    /// empty-`{}` default applies here too.
    void glStart()
    {
    }

    /// Ported from the base `Fl_Gl_Window_Driver::before_show()` --
    /// Windows never overrides it either (confirmed against the real
    /// source: no `Fl_WinAPI_Gl_Window_Driver::before_show()` exists).
    /// Unlike X11, a Windows pixel format is set lazily on the window's
    /// own device context the first time a GL context is actually
    /// created for it (`createGlContext()` above), not at window-creation
    /// time -- so there is genuinely nothing to do here, matching
    /// FLTK's own empty base-class behavior rather than a narrowed
    /// port of it.
    void beforeShow(FlWindow win, GlChoice g)
    {
    }

    /**
     * Ported from the base `Fl_Gl_Window_Driver::gl_visual()`
     * (`gl_choice = c;`) -- Windows never overrides it with X11's own
     * additional `fl_visual`/`fl_colormap` reassignment (confirmed
     * against the real source: `Fl_WinAPI_Gl_Window_Driver` has no
     * `gl_visual()` override at all), since Windows has no equivalent
     * shared "default visual" concept for `Fl::gl_visual()` to
     * retarget -- each window's own pixel format is set individually,
     * lazily, in `createGlContext()`.
     */
    void glVisual(GlChoice c)
    {
        glChoice_ = c;
    }

    /// Ported from `Fl_WinAPI_Gl_Window_Driver::GetProcAddress()`.
    void* getProcAddress(const(char)* procName)
    {
        return cast(void*) wglGetProcAddress(procName);
    }
}

// -- switch_to_GL1/switch_back: detaches/restores whatever shader
// program a modeOpengl3 GlWindow's own draw() left bound, around the
// fixed-function-style 2D widget compositing GlWindow.drawBegin()/
// drawEnd() do (fl.gl_graphics_driver.GlGraphicsDriver's glRectf()/
// glBegin()/glColor4ub()/etc calls only work correctly with no custom
// shader active -- a bound GL3 vertex/fragment shader intercepts them
// instead, since it doesn't feed the generic vertex attributes those
// fixed-function calls use, producing wrong/missing geometry). Ported
// from Fl_Gl_Window_Driver::switch_to_GL1()/switch_back()
// (src/Fl_Gl_Choice.cxx) -- `glUseProgram` is resolved lazily via
// getProcAddress() above rather than fl.glew's own binding, matching
// FLTK's own mechanism exactly (a driver-internal ad-hoc lookup,
// not a dependency on GLEW at all -- GLEW is purely a *sample*-level
// convenience FLTK itself never needs inside the library).
private
{
    alias GlUseProgramFn = extern (System) void function(GLuint);
    GlUseProgramFn glUseProgramFn_;
    GLint currentProg_;
}

/**
 * Ported from `Fl_Gl_Window_Driver::switch_to_GL1()`: records whatever
 * shader program is currently bound (`GL_CURRENT_PROGRAM`) and detaches
 * it (`glUseProgram(0)`) so the fixed-function pipeline is active again.
 * Call from `GlWindow.drawBegin()`, guarded on `mode() & modeOpengl3`
 * (only `modeOpengl3` windows ever bind a custom shader in the first
 * place -- calling this unconditionally would be harmless too, since
 * `currentProg_` would just always read back `0`, but FLTK itself
 * gates the call, so this does too).
 */
void switchToGl1()
{
    if (glUseProgramFn_ is null)
        glUseProgramFn_ = cast(GlUseProgramFn) getProcAddress("glUseProgram".ptr);
    glGetIntegerv(GL_CURRENT_PROGRAM, &currentProg_);
    if (currentProg_ && glUseProgramFn_ !is null)
        glUseProgramFn_(0);
}

/// Ported from `Fl_Gl_Window_Driver::switch_back()`: re-binds whatever
/// shader `switchToGl1()` detached. Call from `GlWindow.drawEnd()`,
/// matching `switchToGl1()`'s own `mode() & modeOpengl3` guard.
void switchBack()
{
    if (currentProg_ && glUseProgramFn_ !is null)
        glUseProgramFn_(cast(GLuint) currentProg_);
}

/**
 * Ported from `Fl_Gl_Window_Driver::capture_gl_rectangle()` (the
 * platform-independent version -- no driver override exists for X11).
 * Takes primitive geometry plus a `forceFlush` callback (rather than a
 * `GlWindow` reference directly) to avoid a circular import between
 * this module and `fl.gl_window` -- `fl.gl_window.GlWindow.capture()`
 * is the real public entry point, and passes its own `flush()` as
 * `forceFlush`, matching FLTK's own `glw->flush()` call at the top
 * of this function exactly ("forces a GL redraw, necessary for the
 * glpuzzle demo").
 */
RGBImage captureGlRectangle(void delegate() forceFlush, float pixelsPerUnit,
    int pixelH, int x, int y, int w, int h)
{
    forceFlush();

    glPushClientAttrib(GL_CLIENT_PIXEL_STORE_BIT);
    glPixelStorei(GL_PACK_ALIGNMENT, 4);
    glPixelStorei(GL_PACK_ROW_LENGTH, 0);
    glPixelStorei(GL_PACK_SKIP_ROWS, 0);
    glPixelStorei(GL_PACK_SKIP_PIXELS, 0);

    if (pixelsPerUnit != 1)
    {
        x = cast(int)(x * pixelsPerUnit);
        y = cast(int)(y * pixelsPerUnit);
        w = cast(int)(w * pixelsPerUnit);
        h = cast(int)(h * pixelsPerUnit);
    }

    int byteWidth = w * 3;
    byteWidth = (byteWidth + 3) & ~3;
    auto baseAddress = new ubyte[byteWidth * h];
    glReadPixels(x, pixelH - (y + h), w, h, GL_RGB, GL_UNSIGNED_BYTE, baseAddress.ptr);
    glPopClientAttrib();

    // GL gives a bottom-to-top image; flip it top-to-bottom to match
    // Fl_RGB_Image's own row order.
    auto tmp = new ubyte[byteWidth];
    for (int i = 0; i < h / 2; i++)
    {
        auto p = baseAddress[i * byteWidth .. (i + 1) * byteWidth];
        auto q = baseAddress[(h - 1 - i) * byteWidth .. (h - i) * byteWidth];
        tmp[] = p[];
        p[] = q[];
        q[] = tmp[];
    }

    return new RGBImage(baseAddress, w, h, 3, byteWidth);
}
