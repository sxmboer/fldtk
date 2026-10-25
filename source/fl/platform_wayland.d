/*
 * The Wayland backend: ported from FLTK's `src/drivers/Wayland/`
 * (`Fl_Wayland_Screen_Driver.cxx`, `Fl_Wayland_Window_Driver.cxx`,
 * `Fl_Wayland_Graphics_Driver.cxx`), as a concrete module of free
 * functions like `fl.platform_x11`. The rest of fldtk reaches it through
 * `fl.platform`, which chooses this backend at startup when a Wayland
 * connection can be made (see `connect()`).
 *
 * What it does:
 * - Opens the display: binds `wl_compositor`, `wl_subcompositor`,
 *   `wl_shm`, `xdg_wm_base` (answering its pings), every `wl_output`
 *   and the protocols below.
 * - Windows: toplevel windows are `xdg_toplevel`s. A window with a border
 *   asks the compositor to draw its title bar and borders
 *   (xdg-decoration); when the compositor leaves them to the program
 *   (GNOME, Weston), fldtk draws its own frame on a subsurface below the
 *   window (`updateFrame()`, `fl.wayland_decoration`). FLTK uses libdecor
 *   for this; fldtk needs no library for it. Toplevel windows have no
 *   position on Wayland: their origin is always (0, 0).
 * - Subwindows are `wl_subsurface`s of their parent, desynchronized,
 *   each with its own buffer; their pointer events go to the toplevel
 *   window, in its coordinates, as on X11.
 * - Menus and tooltips are `xdg_popup`s, placed where fldtk's menu
 *   engine puts them (relative to the program window, whose origin is
 *   (0, 0)); the compositor keeps them on screen, and where it actually
 *   put one is written back into the window.
 * - Drawing: each window has a private Cairo image surface that
 *   `fl.cairo_graphics_driver` draws into (`makeCurrent()`). To show it,
 *   `commit()` copies it into a shared-memory `wl_buffer`, attaches that
 *   buffer, damages and commits the surface, and asks for a frame
 *   callback; while one is pending, further commits wait for it. Drawing
 *   done outside a repaint is committed by the next `flushDamage()`.
 *   Offscreen buffers are Cairo image surfaces too (in `fl.draw`).
 * - The event loop is `fl.core`'s: the Wayland socket is registered with
 *   `fl.core.addFd()`, and `dispatchEvents()` reads and dispatches its
 *   events. An exception thrown while handling an event is kept and
 *   rethrown once the call into libwayland returns.
 * - Screens come from `wl_output`: size in pixels, and the integer
 *   output scale, which becomes the buffer scale of the windows on it.
 *   Where the compositor gives a window its exact, possibly fractional
 *   scale (wp-fractional-scale), the window is drawn at that scale and
 *   a viewport gives its logical size -- beyond FLTK, which uses
 *   integer scales only. `fl.core.screenScale()` (Ctrl +/-) multiplies
 *   on top of either.
 * - Input: the seat's pointer (enter, leave, motion, buttons, wheel,
 *   double clicks) and keyboard (xkbcommon keymap, modifiers, key
 *   repeat at the compositor's rate, dead keys and compose sequences),
 *   input methods (text-input-v3), and cursors, through the
 *   compositor's cursor-shape protocol or a cursor theme.
 * - The clipboard (`wl_data_device`), the selection buffer pasted with
 *   the middle button (the primary-selection protocol) and drag and
 *   drop of text, both ways.
 *
 * - Also: cursors made from images, mouse buttons beyond 5 (numbered as
 *   on X11), window icons (xdg-toplevel-icon), shaped windows (pixels
 *   outside the shape cleared to transparent), subwindows clipped to
 *   their parent, xdg-dialog for modal and non-modal windows, and
 *   xdg-activation to bring a shown window to the front.
 *
 * - Overlay windows' overlay, drawn over a copy of the window's pixels;
 *   screens' logical geometry from xdg-output; the dragged text as the
 *   drag's icon.
 *
 * - OpenGL windows: EGL draws into their surface, which gets no buffer
 *   from this module; their repaint is `fl.gl_window.flushGlWindow()`,
 *   and their EGL side is `fl.wayland_gl_window_driver`, which also
 *   gives a window `gl_start()` draws into a GL surface over it.
 *
 * Not ported: the work area (screen 0's whole area is reported; FLTK
 * measures it with maximized test windows).
 * A Wayland program can't place its windows, so their positions are
 * the compositor's.
 */
module fl.platform_wayland;

version (FLDTK_HAVE_WAYLAND):

import core.stdc.string : memcpy, memset;
import std.string : toStringz, fromStringz;

import fl.wayland_client;
import fl.wayland_protocol;
import fl.xdg_shell_protocol;
import fl.xdg_decoration_protocol;
import fl.xdg_system_bell_protocol;
import fl.pointer_gestures_protocol;
import touchEngine = fl.touch;
import deco = fl.wayland_decoration;
import fl.cairo_c;
import fl.cursor_shape_protocol;
import fl.wayland_cursor;
import fl.xkbcommon;
import fl.primary_selection_protocol;
import fl.text_input_protocol;
import fl.fractional_scale_protocol;
import fl.viewporter_protocol;
import fl.xdg_activation_protocol;
import fl.xdg_dialog_protocol;
import fl.xdg_toplevel_icon_protocol;
import fl.xdg_output_protocol;
import fl.wayland_egl : wl_egl_window;
import eglDriver = fl.wayland_gl_window_driver;

import fl.window : FlWindow = Window, resizeBugFix_;
import fl.overlay_window : OverlayWindow;
import fl.gl_window : GlWindow, flushGlWindow;
import fl.widget : Widget;
import fl.group : FlGroup;
import fl.image : RGBImage;
import fl.enumerations : Event, Damage, damageAll, damageOverlay, Keysym, Beep, CursorShape = Cursor,
    EventState, stateShift, stateCapsLock, stateCtrl, stateAlt, stateNumLock, stateMeta,
    stateButton1, stateButtons, button, tab, metaL, metaR, shiftL, altR, home, left, up, right, down,
    pageUp, pageDown, end, insert, deleteKey;
import fl.core;
import fldraw = fl.draw;

// -- display ------------------------------------------------------------

/**
 * Every protocol event reaches this module in an `extern(C)` listener,
 * called from inside libwayland. A D exception (an `assert`
 * in a widget, say) must not unwind through their C frames: each
 * listener runs its body through `guarded()`, which keeps the first
 * exception, and `rethrowPending()` throws it once the call into the C
 * library has returned.
 */
private Throwable pending_;

private void guarded(scope void delegate() body_) nothrow
{
    if (pending_ !is null) return;
    try body_();
    catch (Throwable t) pending_ = t;
}

/// `guarded()`, for the listeners of other Wayland modules
/// (`fl.wayland_pen_driver`).
package(fl) void guardedCall(scope void delegate() body_) nothrow
{
    guarded(body_);
}

private void rethrowPending()
{
    if (auto t = pending_)
    {
        pending_ = null;
        throw t;
    }
}

private __gshared wl_display* display_;
private __gshared wl_registry* registry_;
private __gshared wl_compositor* compositor_;
private __gshared wl_subcompositor* subcompositor_;
private __gshared wl_shm* shm_;
private __gshared xdg_wm_base* wmBase_;
private __gshared zxdg_decoration_manager_v1* decorationManager_;
private __gshared xdg_system_bell_v1* systemBell_;
private __gshared wp_cursor_shape_manager_v1* cursorShapeManager_;
private __gshared wp_fractional_scale_manager_v1* fractionalManager_;
private __gshared wp_viewporter* viewporter_;
private __gshared xdg_activation_v1* activation_;
private __gshared xdg_wm_dialog_v1* dialogManager_;
private __gshared xdg_toplevel_icon_manager_v1* iconManager_;
private bool opened_;

/// One screen (`Fl_Wayland_Screen_Driver::output`).
private final class Output
{
    wl_output* output;
    uint id;
    int x, y;              // pixels
    int pixelW, pixelH;    // pixels
    int wldScale = 1;      // the compositor's integer scale for this screen
    bool done;
    // The screen's place and size in logical pixels (xdg-output), which
    // the integer scale can't give when the desktop scale is fractional;
    // logicalW is 0 until known.
    zxdg_output_v1* xdgOutput;
    int logicalX, logicalY, logicalW, logicalH;
}

private __gshared zxdg_output_manager_v1* xdgOutputManager_;

/// Asks for `o`'s logical geometry, when the compositor offers it.
private void attachXdgOutput(Output o)
{
    if (xdgOutputManager_ is null || o.xdgOutput !is null) return;
    o.xdgOutput = zxdg_output_manager_v1_get_xdg_output(xdgOutputManager_, o.output);
    zxdg_output_v1_add_listener(o.xdgOutput, &xdgOutputListener, cast(void*) o);
}

extern (C) private void xdgOutputLogicalPosition(void* data, zxdg_output_v1* xo, int x, int y) nothrow
{
    guarded({
    auto o = cast(Output) data;
    o.logicalX = x;
    o.logicalY = y;
    });
}

extern (C) private void xdgOutputLogicalSize(void* data, zxdg_output_v1* xo, int width, int height) nothrow
{
    guarded({
    auto o = cast(Output) data;
    o.logicalW = width;
    o.logicalH = height;
    });
}

extern (C) private void xdgOutputDone(void* data, zxdg_output_v1* xo) nothrow { }
extern (C) private void xdgOutputName(void* data, zxdg_output_v1* xo, const(char)* name) nothrow { }
extern (C) private void xdgOutputDescription(void* data, zxdg_output_v1* xo, const(char)* d) nothrow { }

private __gshared zxdg_output_v1_listener xdgOutputListener = {
    logical_position: &xdgOutputLogicalPosition,
    logical_size: &xdgOutputLogicalSize,
    done: &xdgOutputDone,
    name: &xdgOutputName,
    description: &xdgOutputDescription,
};

private Output[] outputs_;

/// Tags this module's own `wl_output` proxies: another library on the
/// same connection may bind outputs too, and a surface's enter/leave
/// events then also arrive with those, whose user data isn't an `Output`
/// -- FLTK's `proxy_tag`/`own_output()`.
private __gshared const(char)* proxyTag_ = "fldtk for Wayland";

private bool ownOutput(wl_output* output)
{
    return wl_proxy_get_tag(cast(wl_proxy*) output) is &proxyTag_;
}

/**
 * Connects to the Wayland compositor, without binding anything yet.
 * Returns false when there is no compositor to connect to. Called by
 * `fl.platform` once, to choose the backend.
 */
package(fl) bool connect()
{
    if (display_ is null) display_ = wl_display_connect(null);
    return display_ !is null;
}

/// The Wayland connection, or null.
package(fl) wl_display* waylandDisplay() { return display_; }

extern (C) private void registryGlobal(void* data, wl_registry* registry, uint id,
    const(char)* iface, uint version_) nothrow
{
    guarded({
    string name = fromStringz(iface).idup;
    if (name == "wl_compositor")
    {
        if (version_ < 4) fatal("wl_compositor version >= 4 required");
        compositor_ = cast(wl_compositor*) wl_registry_bind(registry, id, &wl_compositor_interface, 4);
    }
    else if (name == "wl_subcompositor")
        subcompositor_ = cast(wl_subcompositor*) wl_registry_bind(registry, id, &wl_subcompositor_interface, 1);
    else if (name == "wl_shm")
        shm_ = cast(wl_shm*) wl_registry_bind(registry, id, &wl_shm_interface, 1);
    else if (name == "wl_output")
    {
        if (version_ < 2) fatal("wl_output version 2 required");
        auto o = new Output;
        o.id = id;
        uint v = version_ < WL_OUTPUT_RELEASE_SINCE_VERSION ? version_ : WL_OUTPUT_RELEASE_SINCE_VERSION;
        o.output = cast(wl_output*) wl_registry_bind(registry, id, &wl_output_interface, v);
        wl_proxy_set_tag(cast(wl_proxy*) o.output, &proxyTag_);
        wl_output_add_listener(o.output, &outputListener, cast(void*) o);
        outputs_ ~= o;
        attachXdgOutput(o);
    }
    else if (name == "wl_seat")
    {
        if (version_ < 3) fatal("wl_seat version 3 required");
        // version 4: the pointer events after it (frame, axis_source, ...)
        // aren't handled, as in FLTK
        seat_ = cast(wl_seat*) wl_registry_bind(registry, id, &wl_seat_interface, version_ < 4 ? version_ : 4);
        initKeyboardContext();
        wl_seat_add_listener(seat_, &seatListener, null);
    }
    else if (name == "wl_data_device_manager")
        dataDeviceManager_ = cast(wl_data_device_manager*) wl_registry_bind(registry, id,
            &wl_data_device_manager_interface, version_ < 3 ? version_ : 3);
    else if (name == "zwp_primary_selection_device_manager_v1")
        primaryManager_ = cast(zwp_primary_selection_device_manager_v1*) wl_registry_bind(registry, id,
            &zwp_primary_selection_device_manager_v1_interface, 1);
    else if (name == "wp_fractional_scale_manager_v1")
        fractionalManager_ = cast(wp_fractional_scale_manager_v1*) wl_registry_bind(registry, id,
            &wp_fractional_scale_manager_v1_interface, 1);
    else if (name == "wp_viewporter")
        viewporter_ = cast(wp_viewporter*) wl_registry_bind(registry, id, &wp_viewporter_interface, 1);
    else if (name == "zxdg_output_manager_v1")
    {
        xdgOutputManager_ = cast(zxdg_output_manager_v1*) wl_registry_bind(registry, id,
            &zxdg_output_manager_v1_interface, version_ < 3 ? version_ : 3);
        foreach (o; outputs_) attachXdgOutput(o);
    }
    else if (name == "zwp_tablet_manager_v2")
    {
        import fl.tablet_protocol : zwp_tablet_manager_v2, zwp_tablet_manager_v2_interface;
        import penDriver = fl.wayland_pen_driver;
        penDriver.setTabletManager(cast(zwp_tablet_manager_v2*) wl_registry_bind(registry, id,
            &zwp_tablet_manager_v2_interface, version_ < 2 ? version_ : 2));
    }
    else if (name == "zwp_pointer_gestures_v1")
        pointerGestures_ = cast(zwp_pointer_gestures_v1*) wl_registry_bind(registry, id,
            &zwp_pointer_gestures_v1_interface, 1);
    else if (name == "zxdg_decoration_manager_v1")
        decorationManager_ = cast(zxdg_decoration_manager_v1*) wl_registry_bind(registry, id,
            &zxdg_decoration_manager_v1_interface, 1);
    else if (name == "xdg_system_bell_v1")
        systemBell_ = cast(xdg_system_bell_v1*) wl_registry_bind(registry, id, &xdg_system_bell_v1_interface, 1);
    else if (name == "xdg_activation_v1")
        activation_ = cast(xdg_activation_v1*) wl_registry_bind(registry, id, &xdg_activation_v1_interface, 1);
    else if (name == "xdg_wm_dialog_v1")
        dialogManager_ = cast(xdg_wm_dialog_v1*) wl_registry_bind(registry, id, &xdg_wm_dialog_v1_interface, 1);
    else if (name == "xdg_toplevel_icon_manager_v1")
    {
        iconManager_ = cast(xdg_toplevel_icon_manager_v1*) wl_registry_bind(registry, id,
            &xdg_toplevel_icon_manager_v1_interface, 1);
        xdg_toplevel_icon_manager_v1_add_listener(iconManager_, &iconManagerListener, null);
    }
    else if (name == "zwp_text_input_manager_v3")
        textInputManager_ = cast(zwp_text_input_manager_v3*) wl_registry_bind(registry, id,
            &zwp_text_input_manager_v3_interface, 1);
    else if (name == "wp_cursor_shape_manager_v1")
        cursorShapeManager_ = cast(wp_cursor_shape_manager_v1*) wl_registry_bind(registry, id,
            &wp_cursor_shape_manager_v1_interface, 1);
    else if (name == "xdg_wm_base")
    {
        // version 3 for xdg_popup.reposition, 5 for xdg_toplevel.wm_capabilities
        wmBase_ = cast(xdg_wm_base*) wl_registry_bind(registry, id, &xdg_wm_base_interface,
            version_ < 5 ? version_ : 5);
        xdg_wm_base_add_listener(wmBase_, &wmBaseListener, null);
    }
    });
}

extern (C) private void registryGlobalRemove(void* data, wl_registry* registry, uint name) nothrow
{
    guarded({
    foreach (i, o; outputs_)
    {
        if (o.id != name) continue;
        if (o.xdgOutput !is null) zxdg_output_v1_destroy(o.xdgOutput);
        wl_output_destroy(o.output);
        outputs_ = outputs_[0 .. i] ~ outputs_[i + 1 .. $];
        foreach (w; windows_) w.outputs = removeOutput(w.outputs, o);
        return;
    }
    });
}

private __gshared wl_registry_listener registryListener = {
    global: &registryGlobal,
    global_remove: &registryGlobalRemove,
};

extern (C) private void wmBasePing(void* data, xdg_wm_base* base, uint serial) nothrow
{
    guarded({
    xdg_wm_base_pong(base, serial);
    });
}

private __gshared xdg_wm_base_listener wmBaseListener = { ping: &wmBasePing };

extern (C) private void outputGeometry(void* data, wl_output* output, int x, int y,
    int physicalWidth, int physicalHeight, int subpixel, const(char)* make,
    const(char)* model, int transform) nothrow
{
    guarded({
    auto o = cast(Output) data;
    o.x = x;
    o.y = y;
    });
}

extern (C) private void outputMode(void* data, wl_output* output, uint flags,
    int width, int height, int refresh) nothrow
{
    guarded({
    auto o = cast(Output) data;
    o.pixelW = width;
    o.pixelH = height;
    });
}

/// Runs at startup, and whenever a screen's configuration (its scale,
/// say) changes: windows are redrawn at the new scale.
extern (C) private void outputDone(void* data, wl_output* output) nothrow
{
    guarded({
    auto o = cast(Output) data;
    if (o.done) // a change after startup
    {
        foreach (w; windows_)
        {
            if (auto gw = w.widget.asGlWindow())
            {
                eglDriver.rescale(gw);
                gw.redraw();
                flushWindow(w);
                continue;
            }
            updateFrame(w);
            if (w.buffer is null) continue;
            releaseBuffer(w);
            w.widget.redraw();
            flushWindow(w);
        }
    }
    o.done = true;
    });
}

extern (C) private void outputScale(void* data, wl_output* output, int factor) nothrow
{
    guarded({
    (cast(Output) data).wldScale = factor;
    });
}

extern (C) private void outputName(void* data, wl_output* output, const(char)* name) nothrow { }
extern (C) private void outputDescription(void* data, wl_output* output, const(char)* d) nothrow { }

private __gshared wl_output_listener outputListener = {
    geometry: &outputGeometry,
    mode: &outputMode,
    done: &outputDone,
    scale: &outputScale,
    name: &outputName,
    description: &outputDescription,
};

import std.conv : to;

/**
 * Opens the display -- ported from `Fl_Wayland_Screen_Driver::
 * open_display_platform()`: binds the globals the compositor offers,
 * waits until every screen has reported its geometry, and registers
 * the Wayland socket with the event loop.
 */
void openDisplay()
{
    if (opened_) return;
    opened_ = true;
    if (!connect()) fatal("No Wayland connection");

    registry_ = wl_display_get_registry(display_);
    wl_registry_add_listener(registry_, &registryListener, null);
    wl_display_roundtrip(display_); // runs registryGlobal() for each global
    rethrowPending();
    foreach (o; outputs_)
        while (!o.done)
        {
            wl_display_dispatch(display_);
            rethrowPending();
        }
    if (xdgOutputManager_ !is null)
    {
        wl_display_roundtrip(display_); // the screens' logical geometry
        rethrowPending();
    }
    if (compositor_ is null || shm_ is null || wmBase_ is null)
        fatal("The Wayland compositor lacks wl_compositor, wl_shm or xdg_wm_base");
    initDataDevices();

    addFd(wl_display_get_fd(display_), (int fd) { socketReadable(); });
    fldraw.useCairoDisplay();
    useStartupScaleFactor();
    installScaleHandler(); // Ctrl +/-/0
}

/**
 * The startup GUI scale: `FLTK_SCALING_FACTOR` (default 1), times the
 * zoom last chosen with Ctrl +/- (`fl.core.loadPersistedZoom()`, a fldtk
 * addition) -- FLTK's `Fl_Screen_Driver::use_startup_scale_factor()`.
 * The compositor's own scale for each screen comes on top as the buffer
 * scale.
 */
private void useStartupScaleFactor()
{
    import std.process : environment;
    import std.conv : parse, ConvException;
    float factor = 1.0f;
    if (auto str = environment.get("FLTK_SCALING_FACTOR"))
    {
        try factor = parse!float(str);
        catch (ConvException) factor = 1.0f;
    }
    if (factor <= 0) factor = 1.0f;
    import std.math : isNaN;
    float zoom = loadPersistedZoom();
    float effective = factor * (isNaN(zoom) ? 1.0f : zoom);
    foreach (i; 0 .. screenCount())
    {
        seedBaseScale(i, factor);
        screenScale(i, effective);
    }
    currentScale(effective);
}

/// The Wayland socket has data: read and dispatch its events -- FLTK's
/// `wld_socket_callback()`.
private void socketReadable()
{
    int r = dispatchEvents(0);
    rethrowPending();
    if (r >= 0) return;
    import core.stdc.errno : errno, EPROTO;
    if (wl_display_get_error(display_) == EPROTO)
    {
        const(wl_interface)* iface;
        uint code = wl_display_get_protocol_error(display_, &iface, null);
        fatal("Fatal error " ~ code.to!string ~ " in Wayland protocol: "
            ~ (iface !is null ? fromStringz(iface.name).idup : "unknown"));
    }
    fatal("Fatal error while communicating with Wayland server");
}

/**
 * Dispatches the events already queued, then reads and dispatches what
 * arrives within `timeout` milliseconds (-1: waits for something; 0:
 * doesn't wait). Returns the number of events dispatched, or -1 on a
 * connection error. The read is done with libwayland's prepare/read
 * protocol, so it can't race another reader of the connection (EGL's).
 */
private int dispatchEvents(int timeout)
{
    import core.sys.posix.poll : pollfd, poll, POLLIN;
    import core.stdc.errno : errno, EAGAIN;
    int count = 0;
    while (wl_display_prepare_read(display_) != 0)
    {
        int n = wl_display_dispatch_pending(display_);
        if (n < 0) return -1;
        count += n;
    }
    if (wl_display_flush(display_) < 0 && errno != EAGAIN)
    {
        wl_display_cancel_read(display_);
        return -1;
    }
    pollfd fd = pollfd(wl_display_get_fd(display_), POLLIN, 0);
    int r = poll(&fd, 1, timeout);
    if (r > 0 && (fd.revents & POLLIN))
    {
        if (wl_display_read_events(display_) < 0) return -1;
        int n = wl_display_dispatch_pending(display_);
        return n < 0 ? -1 : count + n;
    }
    wl_display_cancel_read(display_);
    return r < 0 ? -1 : count;
}

// -- windows ------------------------------------------------------------

/// The private draw buffer of a window and the shared-memory buffer it
/// is copied into to be shown (`Fl_Wayland_Graphics_Driver::wld_buffer`).
private final class Buffer
{
    ubyte[] pixels;        // what Cairo draws into
    cairo_t* cr;
    int width, height, stride; // pixels
    wl_buffer* wlBuffer;   // created on first commit
    void* shmData;
    size_t shmSize;
    bool inUse;            // the compositor may still be reading it
    bool released;         // the window no longer uses it
    bool needsCommit = true;
    // An overlay window's overlay: the window's pixels with the overlay
    // drawn over them, shown instead of `pixels` while it is active.
    ubyte[] overlayPixels;
    cairo_t* overlayCr;
}

/// Buffers the compositor may still read after their window let go of
/// them; kept here so the garbage collector doesn't free them while a
/// `wl_buffer` listener can still reach them.
private Buffer[] liveBuffers_;

private enum Kind { decorated, unframed, popup, subwindow }

/// A shown window (FLTK's `struct wld_window`). `fl.window.Window`'s
/// `xid()` holds a pointer to it.
package(fl) final class WldWindow
{
    FlWindow widget;
    Kind kind;
    wl_surface* surface;
    zxdg_toplevel_decoration_v1* decoration; // decorated windows, with xdg-decoration
    bool serverSide;            // the compositor draws its decorations
    deco.FrameState frameState; // what fldtk's own frame shows
    wl_surface* frameSurface;   // fldtk's own frame, when it has one
    wl_subsurface* frameSubsurface;
    wp_viewport* frameViewport;
    Buffer frameBuffer;
    uint lastTitleClick;        // time of the last click on the title bar
    int pendingW, pendingH;     // what the last xdg_toplevel.configure asked for
    bool pendingMaximized, pendingFullscreen, pendingActivated, pendingTiled;
    uint commits;               // surface commits done by commit()
    int sizeRangeTitle;         // the title bar height the size range was given with
    bool haveWmCapabilities;    // the compositor said which of the next it supports
    bool canMaximize = true, canMinimize = true, canWindowMenu = true, canFullscreen = true;
    xdg_surface* xdgSurface;
    xdg_toplevel* xdgToplevel;  // unframed windows
    xdg_popup* xdgPopup;        // menus and tooltips
    wl_subsurface* subsurface;  // subwindows, while mapped
    wp_fractional_scale_v1* fractional; // the compositor's exact scale for it
    wp_viewport* viewport;      // its logical size, when drawn at that scale
    uint scale120;              // that scale in 120ths; 0 until known
    ShmImage customCursor;      // a cursor made from an image, if any
    int cursorHotX, cursorHotY; // its hot spot, in logical pixels
    int cursorScale = 1;        // the scale it was made at
    ShmImage[] iconImages;      // the window icon's buffers
    xdg_dialog_v1* dialog;      // modal and non-modal windows
    const(ubyte)[] shapeBits;   // shaped windows: X bitmap, set = visible
    int shapeW, shapeH;
    int subClipX, subClipY, subClipW = -1, subClipH = -1; // subwindows: the part inside the parent
    WldWindow popupParent;      // the window a popup is placed against
    Buffer buffer;
    wl_callback* frameCb;
    int configuredW, configuredH; // FLTK units; 0 until the first configure
    int floatingW, floatingH;     // logical pixels, while neither maximized, fullscreen nor tiled
    bool waitingForExpose = true; // until the first configure has been drawn
    int configures;               // configure events received
    Output[] outputs;             // the screens the window is on
    bool hasDamageRegion, fullRepaintPending;
    int damageX, damageY, damageW, damageH;
    CursorShape cursor = CursorShape.default_; // shown while the pointer is over it
    // GL windows (fl.wayland_gl_window_driver)
    wl_egl_window* eglWindow;   // wraps `surface` for EGL
    void* eglSurface;           // the EGL surface on it
    void* eglContext;           // the context last made current on it
    bool needSwap;              // a swap waits for the frame callback
    bool eglIntervalSet;        // EGL's swap interval of its surface is 0
    eglDriver.GlStartSurface glStart; // what gl_start() draws into on a non-GL window
}

/// Shown windows, most recently shown or raised first (FLTK's
/// `Fl_X::first` list).
private WldWindow[] windows_;

private WldWindow find(FlWindow win)
{
    foreach (w; windows_) if (w.widget is win) return w;
    return null;
}

/// The seat, for `fl.wayland_pen_driver`.
package(fl) wl_seat* waylandSeat() { return seat_; }

/// The window whose surface is `surface`, or null (a frame's surface,
/// say), for `fl.wayland_pen_driver`.
package(fl) FlWindow windowOfSurfaceWidget(wl_surface* surface)
{
    auto w = windowOfSurface(surface);
    return w !is null ? w.widget : null;
}

/// The shown window of `win`, for `fl.wayland_gl_window_driver`.
package(fl) WldWindow wldWindowOf(FlWindow win) { return find(win); }

package(fl) wl_compositor* waylandCompositor() { return compositor_; }
package(fl) wl_subcompositor* waylandSubcompositor() { return subcompositor_; }

/// The integer buffer scale a GL window `win` is drawn at (FLTK's
/// `wld_scale()`); 1 when it isn't shown.
package(fl) int glBufferScale(FlWindow win)
{
    auto w = find(win);
    return w !is null ? wldScale(w) : 1;
}

/// Waits until toplevel window `top` is on a screen, so its scale is
/// known -- what FLTK's GL driver does before sizing a GL subwindow.
package(fl) void waitForScreen(FlWindow top)
{
    auto w = find(top);
    while (w !is null && w.surface !is null && w.outputs.length == 0)
    {
        int r = dispatchEvents(-1);
        rethrowPending();
        if (r < 0) break;
    }
}

/// A GL window, and the GL subwindows of a toplevel window, take a new
/// screen scale (see `fl.wayland_gl_window_driver.rescale()`).
private void rescaleGl(WldWindow w)
{
    foreach (e; windows_)
        if (e is w || (e.kind == Kind.subwindow && e.widget.topWindow() is w.widget))
            if (auto gw = e.widget.asGlWindow())
            {
                eglDriver.rescale(gw);
                gw.redraw();
            }
}

private Output[] removeOutput(Output[] list, Output o)
{
    Output[] r;
    foreach (e; list) if (e !is o) r ~= e;
    return r;
}

/// The buffer scale of `w`: the integer scale of the first screen it is
/// on, or the largest one before it has entered any -- FLTK's
/// `wld_scale()`.
private int wldScale(WldWindow w)
{
    if (w !is null && w.kind == Kind.subwindow)
        if (auto top = find(w.widget.topWindow()))
            if (top !is w) return wldScale(top);
    if (w !is null && w.outputs.length) return w.outputs[0].wldScale;
    int s = 1;
    foreach (o; outputs_) if (o.wldScale > s) s = o.wldScale;
    return s;
}

/**
 * The scale `w` is drawn at, in device pixels per logical unit: the
 * compositor's exact (possibly fractional) scale when it gives one
 * (wp_fractional_scale_v1; FLTK uses only integer scales and lets the
 * compositor shrink its buffers), else the integer buffer scale. A
 * subwindow is drawn at its toplevel's.
 */
private float deviceScale(WldWindow w)
{
    if (w !is null && w.kind == Kind.subwindow)
        if (auto top = find(w.widget.topWindow()))
            if (top !is w) return deviceScale(top);
    if (w !is null && w.scale120 > 0 && w.viewport !is null) return w.scale120 / 120.0f;
    return wldScale(w);
}

/// Asks for `w`'s exact scale, when the compositor offers it.
private void attachFractionalScale(WldWindow w)
{
    if (fractionalManager_ is null || viewporter_ is null) return;
    if (w.widget.asGlWindow() !is null) return; // drawn at the integer buffer scale
    w.fractional = wp_fractional_scale_manager_v1_get_fractional_scale(fractionalManager_, w.surface);
    wp_fractional_scale_v1_add_listener(w.fractional, &fractionalListener, cast(void*) w);
    w.viewport = wp_viewporter_get_viewport(viewporter_, w.surface);
}

/// The compositor's scale for the window changed (it moved to another
/// screen, or the desktop's scale changed): redraw at it.
extern (C) private void fractionalPreferredScale(void* data, wp_fractional_scale_v1* fs, uint scale) nothrow
{
    guarded({
    auto w = cast(WldWindow) data;
    if (scale == w.scale120) return;
    w.scale120 = scale;
    releaseBuffer(w);
    w.widget.redraw();
    updateFrame(w); // shown with the redrawn window
    // subwindows are drawn at their toplevel's scale
    foreach (sub; windows_)
        if (sub.kind == Kind.subwindow && sub.widget.topWindow() is w.widget)
        {
            releaseBuffer(sub);
            sub.widget.redraw();
        }
    });
}

private __gshared wp_fractional_scale_v1_listener fractionalListener = {
    preferred_scale: &fractionalPreferredScale,
};

/// The number of `o` in the list of screens.
private int outputIndex(Output o)
{
    foreach (i, e; outputs_) if (e is o) return cast(int) i;
    return 0;
}

extern (C) private void surfaceEnter(void* data, wl_surface* surface, wl_output* output) nothrow
{
    guarded({
    if (!ownOutput(output)) return;
    auto w = cast(WldWindow) data;
    auto o = cast(Output) wl_output_get_user_data(output);
    if (o is null) return;
    bool wasEmpty = w.outputs.length == 0;
    w.outputs ~= o;
    if (wasEmpty && w.kind != Kind.subwindow) changeScale(w, o, 0);
    });
}

extern (C) private void surfaceLeave(void* data, wl_surface* surface, wl_output* output) nothrow
{
    guarded({
    if (!ownOutput(output)) return;
    auto w = cast(WldWindow) data;
    auto o = cast(Output) wl_output_get_user_data(output);
    float preScale = screenScale(w.widget.screenNum()) * deviceScale(w);
    bool wasFirst = w.outputs.length && w.outputs[0] is o;
    w.outputs = removeOutput(w.outputs, o);
    if (wasFirst && w.outputs.length && w.kind != Kind.subwindow) changeScale(w, w.outputs[0], preScale);
    });
}

private __gshared wl_surface_listener surfaceListener = {
    enter: &surfaceEnter,
    leave: &surfaceLeave,
    preferred_buffer_scale: null,
    preferred_buffer_transform: null,
};

/// The window now shows first on screen `o`: take that screen's number
/// and redraw at its scale -- FLTK's `change_scale()`.
private void changeScale(WldWindow w, Output o, float preScale)
{
    w.widget.rawScreenNum(outputIndex(o));
    float postScale = screenScale(w.widget.screenNum()) * deviceScale(w);
    if (postScale == preScale) return;
    sizeRangeChanged(w.widget);
    releaseBuffer(w);
    w.widget.redraw();
    rescaleGl(w);
    toplevelGeometryChanged(w);
}

// ---- toplevel windows: configure

/// The height of the title bar fldtk draws over `w`, 0 when it draws none.
private int titleOffset(WldWindow w)
{
    if (w.kind != Kind.decorated || w.serverSide) return 0;
    return deco.titleHeight(w.frameState);
}

/// Whether the user may resize `win`: it is resizable and its size range
/// isn't a single size.
private bool userResizable(FlWindow win)
{
    if (!win.isResizable()) return false;
    int minw, minh, maxw, maxh, dw, dh;
    bool aspect;
    win.getSizeRange(&minw, &minh, &maxw, &maxh, &dw, &dh, &aspect);
    return !(maxw && maxh && (minw >= maxw || minh >= maxh));
}

/// Ported from `xdg_toplevel_configure()`:
/// the size and states the compositor asks for, applied at the
/// `xdg_surface.configure` that follows.
extern (C) private void xdgToplevelConfigure(void* data, xdg_toplevel* toplevel,
    int width, int height, wl_array* states) nothrow
{
    guarded({
    auto w = cast(WldWindow) data;
    w.pendingW = width;
    w.pendingH = height;
    w.pendingMaximized = w.pendingFullscreen = w.pendingActivated = w.pendingTiled = false;
    auto p = cast(const(uint)*) states.data;
    foreach (i; 0 .. states.size / uint.sizeof)
    {
        switch (p[i])
        {
            case XDG_TOPLEVEL_STATE_MAXIMIZED: w.pendingMaximized = true; break;
            case XDG_TOPLEVEL_STATE_FULLSCREEN: w.pendingFullscreen = true; break;
            case XDG_TOPLEVEL_STATE_ACTIVATED: w.pendingActivated = true; break;
            case XDG_TOPLEVEL_STATE_TILED_LEFT: .. case XDG_TOPLEVEL_STATE_TILED_BOTTOM:
                w.pendingTiled = true;
                break;
            default: break;
        }
    }
    });
}

/**
 * Applies the configuration a toplevel window was given -- what FLTK's
 * `handle_configure()` does for a decorated window: the window takes the
 * size asked for, less the title bar fldtk draws (or its own floating
 * size when the compositor leaves the size to it, or always when the
 * user can't resize it), and its frame follows.
 */
private void applyToplevelConfigure(WldWindow w)
{
    FlWindow win = w.widget;
    float f = screenScale(win.screenNum());
    auto st = &w.frameState;
    // the window's maximized and fullscreen flags follow the compositor,
    // which may change them itself (FLTK's is_maximized() from the
    // configure; a fullscreen change it makes is reported to the window
    // as on X11)
    if (w.pendingMaximized) win.setMaximizedFlag();
    else win.clearMaximizedFlag();
    if (w.pendingFullscreen != st.fullscreen && w.pendingFullscreen != win.fullscreenActive())
    {
        if (w.pendingFullscreen) win.setFullscreenFlag();
        else win.clearFullscreenFlag();
        dispatch(Event.fullscreen, win);
    }
    st.maximized = w.pendingMaximized;
    st.fullscreen = w.pendingFullscreen;
    st.active = w.pendingActivated;
    st.tiled = w.pendingTiled;
    st.resizable = userResizable(win);
    st.zoom = f;
    bool floating = !st.maximized && !st.fullscreen && !st.tiled;
    int t = titleOffset(w);
    int cw = w.pendingW, ch = w.pendingH - t; // logical pixels
    if (w.pendingW <= 0 || w.pendingH <= 0)
    {
        cw = w.floatingW;
        ch = w.floatingH;
    }
    if (!st.resizable && floating)
    {
        cw = cast(int)(win.w() * f);
        ch = cast(int)(win.h() * f);
    }
    import std.math : ceil;
    int fw = cast(int) ceil(cw / f), fh = cast(int) ceil(ch / f);
    applyConfiguredSize(w, fw > 0 ? fw : 1, fh > 0 ? fh : 1);
    if (floating)
    {
        w.floatingW = cast(int)(win.w() * f);
        w.floatingH = cast(int)(win.h() * f);
    }
    toplevelGeometryChanged(w);
    // the size range includes the title bar, known only now
    if (titleOffset(w) != w.sizeRangeTitle) sizeRangeChanged(win);
}

/**
 * The window geometry of toplevel `w` (its content, and the title bar
 * fldtk draws above it) after its size, scale or decorations changed:
 * told to the compositor, and the frame redrawn to match. Shown at the
 * window's next commit.
 */
private void toplevelGeometryChanged(WldWindow w)
{
    if (w.xdgSurface is null || (w.kind != Kind.decorated && w.kind != Kind.unframed)) return;
    FlWindow win = w.widget;
    float f = screenScale(win.screenNum());
    auto st = &w.frameState;
    st.zoom = f;
    st.width = cast(int)(win.w() * f);
    st.height = cast(int)(win.h() * f);
    int t = titleOffset(w);
    xdg_surface_set_window_geometry(w.xdgSurface, 0, -t, st.width, st.height + t);
    updateFrame(w);
}

/// Resizes the window to `(fw, fh)` FLTK units as told by the
/// compositor, without asking the compositor for it again
/// (`resizeBugFix_`), and drops a draw buffer of the old size.
private void applyConfiguredSize(WldWindow w, int fw, int fh)
{
    if (fw != w.widget.w() || fh != w.widget.h() || w.configuredW == 0)
    {
        resizeBugFix_ = w.widget;
        w.widget.resize(0, 0, fw, fh);
    }
    if (w.buffer !is null && (fw != w.configuredW || fh != w.configuredH))
        releaseBuffer(w);
    w.configuredW = fw;
    w.configuredH = fh;
}

/// xdg-decoration: whether the compositor draws the window's decorations
/// or leaves them to fldtk. Applied at the next `xdg_surface.configure`.
extern (C) private void decorationConfigure(void* data, zxdg_toplevel_decoration_v1* decoration, uint mode) nothrow
{
    guarded({
    auto w = cast(WldWindow) data;
    w.serverSide = mode == ZXDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE;
    });
}

private __gshared zxdg_toplevel_decoration_v1_listener decorationListener = { configure: &decorationConfigure };

/// Ported from `xdg_surface_configure()`: acknowledges the configuration
/// and draws the window in it. When nothing needed drawing, the surface
/// is committed anyway, so the acknowledgement (and a changed frame)
/// takes effect.
extern (C) private void xdgSurfaceConfigure(void* data, xdg_surface* surface, uint serial) nothrow
{
    guarded({
    auto w = cast(WldWindow) data;
    xdg_surface_ack_configure(surface, serial);
    w.configures++;
    if (w.kind == Kind.decorated || w.kind == Kind.unframed)
        applyToplevelConfigure(w);
    else
    {
        if (w.buffer !is null && (w.widget.w() != w.configuredW || w.widget.h() != w.configuredH))
            releaseBuffer(w);
        w.configuredW = w.widget.w();
        w.configuredH = w.widget.h();
    }
    w.waitingForExpose = false;
    uint commits = w.commits;
    flushWindow(w);
    w.widget.clearDamage();
    if (w.commits == commits && w.surface !is null) wl_surface_commit(w.surface);
    });
}

private __gshared xdg_surface_listener xdgSurfaceListener = { configure: &xdgSurfaceConfigure };

extern (C) private void xdgToplevelClose(void* data, xdg_toplevel* toplevel) nothrow
{
    guarded({
    auto w = cast(WldWindow) data;
    dispatch(Event.close, w.widget);
    });
}

extern (C) private void xdgToplevelConfigureBounds(void* data, xdg_toplevel* toplevel, int width, int height) nothrow { }
/// What the compositor can do with toplevel windows (xdg-shell version
/// 5): fldtk's own title bar then shows only the buttons that work.
/// Without this event, everything is supported.
extern (C) private void xdgToplevelWmCapabilities(void* data, xdg_toplevel* toplevel, wl_array* caps) nothrow
{
    guarded({
    auto w = cast(WldWindow) data;
    w.haveWmCapabilities = true;
    w.canMaximize = w.canMinimize = w.canWindowMenu = w.canFullscreen = false;
    auto p = cast(const(uint)*) caps.data;
    foreach (i; 0 .. caps.size / uint.sizeof)
    {
        switch (p[i])
        {
            case XDG_TOPLEVEL_WM_CAPABILITIES_WINDOW_MENU: w.canWindowMenu = true; break;
            case XDG_TOPLEVEL_WM_CAPABILITIES_MAXIMIZE: w.canMaximize = true; break;
            case XDG_TOPLEVEL_WM_CAPABILITIES_FULLSCREEN: w.canFullscreen = true; break;
            case XDG_TOPLEVEL_WM_CAPABILITIES_MINIMIZE: w.canMinimize = true; break;
            default: break;
        }
    }
    w.frameState.canMaximize = w.canMaximize;
    w.frameState.canMinimize = w.canMinimize;
    });
}

private __gshared xdg_toplevel_listener xdgToplevelListener = {
    configure: &xdgToplevelConfigure,
    close: &xdgToplevelClose,
    configure_bounds: &xdgToplevelConfigureBounds,
    wm_capabilities: &xdgToplevelWmCapabilities,
};

// ---- fldtk's own window frame (fl.wayland_decoration)

/**
 * Shows, redraws or removes `w`'s frame: a subsurface below the window's
 * surface, with the title bar above the window and a margin round it
 * that resizes it. A decorated window has one unless the compositor
 * draws its decorations, or the window is fullscreen. Changes show at
 * the window's next commit (the subsurface is synchronized).
 */
private void updateFrame(WldWindow w)
{
    if (w.kind != Kind.decorated || w.surface is null) return;
    auto st = &w.frameState;
    if (w.configures == 0 || st.width <= 0 || st.height <= 0) return; // its size comes with the first configure
    if (w.serverSide || !deco.visible(*st))
    {
        destroyFrame(w);
        return;
    }
    if (w.frameSurface is null)
    {
        w.frameSurface = wl_compositor_create_surface(compositor_);
        w.frameSubsurface = wl_subcompositor_get_subsurface(subcompositor_, w.frameSurface, w.surface);
        wl_subsurface_place_below(w.frameSubsurface, w.surface);
        if (viewporter_ !is null) w.frameViewport = wp_viewporter_get_viewport(viewporter_, w.frameSurface);
    }
    int fw, fh, fx, fy;
    deco.frameSize(*st, fw, fh);
    deco.framePosition(*st, fx, fy);
    wl_subsurface_set_position(w.frameSubsurface, fx, fy);

    // drawn at the window's scale; a fractional one needs the viewport
    float scale = w.frameViewport !is null ? deviceScale(w) : wldScale(w);
    import std.math : ceil;
    int bw = cast(int) ceil(fw * scale), bh = cast(int) ceil(fh * scale);
    auto b = w.frameBuffer;
    if (b !is null && (b.inUse || b.width != bw || b.height != bh))
    {
        retireBuffer(b);
        b = w.frameBuffer = null;
    }
    if (b is null)
    {
        b = w.frameBuffer = newBuffer(bw > 0 ? bw : 1, bh > 0 ? bh : 1);
        createShmBuffer(b);
    }
    deco.drawFrame(b.cr, *st, w.widget.label(), scale);
    cairo_surface_flush(cairo_get_target(b.cr));
    memcpy(b.shmData, b.pixels.ptr, b.shmSize);
    wl_surface_attach(w.frameSurface, b.wlBuffer, 0, 0);
    wl_surface_damage_buffer(w.frameSurface, 0, 0, b.width, b.height);
    b.inUse = true;
    if (w.frameViewport !is null)
    {
        wl_surface_set_buffer_scale(w.frameSurface, 1);
        wp_viewport_set_destination(w.frameViewport, fw, fh);
    }
    else
        wl_surface_set_buffer_scale(w.frameSurface, cast(int) scale);
    wl_surface_commit(w.frameSurface);
}

/// Redraws `w`'s frame and shows it at once (the pointer moved over its
/// buttons, its title changed, ...).
private void redrawFrame(WldWindow w)
{
    if (w.frameSurface is null) return;
    updateFrame(w);
    wl_surface_commit(w.surface);
}

/// Removes `w`'s frame.
private void destroyFrame(WldWindow w)
{
    if (w.frameSurface is null) return;
    if (pointerFocus_ is w.frameSurface) pointerFocus_ = null;
    if (w.frameBuffer !is null) retireBuffer(w.frameBuffer);
    w.frameBuffer = null;
    if (w.frameViewport !is null) wp_viewport_destroy(w.frameViewport);
    wl_subsurface_destroy(w.frameSubsurface);
    wl_surface_destroy(w.frameSurface);
    w.frameViewport = null;
    w.frameSubsurface = null;
    w.frameSurface = null;
}

/// The window whose frame `surface` is, or null.
private WldWindow frameOwner(wl_surface* surface)
{
    if (surface is null) return null;
    foreach (w; windows_) if (w.frameSurface is surface) return w;
    return null;
}

/// The cursor over each part of a frame.
private CursorShape frameCursor(deco.Part p)
{
    switch (p)
    {
        case deco.Part.resizeTop: return CursorShape.n;
        case deco.Part.resizeBottom: return CursorShape.s;
        case deco.Part.resizeLeft: return CursorShape.w;
        case deco.Part.resizeRight: return CursorShape.e;
        case deco.Part.resizeTopLeft: return CursorShape.nw;
        case deco.Part.resizeTopRight: return CursorShape.ne;
        case deco.Part.resizeBottomLeft: return CursorShape.sw;
        case deco.Part.resizeBottomRight: return CursorShape.se;
        default: return CursorShape.default_;
    }
}

/// The `xdg_toplevel.resize` edge of each resizing part of a frame.
private uint resizeEdge(deco.Part p)
{
    switch (p)
    {
        case deco.Part.resizeTop: return XDG_TOPLEVEL_RESIZE_EDGE_TOP;
        case deco.Part.resizeBottom: return XDG_TOPLEVEL_RESIZE_EDGE_BOTTOM;
        case deco.Part.resizeLeft: return XDG_TOPLEVEL_RESIZE_EDGE_LEFT;
        case deco.Part.resizeRight: return XDG_TOPLEVEL_RESIZE_EDGE_RIGHT;
        case deco.Part.resizeTopLeft: return XDG_TOPLEVEL_RESIZE_EDGE_TOP_LEFT;
        case deco.Part.resizeTopRight: return XDG_TOPLEVEL_RESIZE_EDGE_TOP_RIGHT;
        case deco.Part.resizeBottomLeft: return XDG_TOPLEVEL_RESIZE_EDGE_BOTTOM_LEFT;
        case deco.Part.resizeBottomRight: return XDG_TOPLEVEL_RESIZE_EDGE_BOTTOM_RIGHT;
        default: return XDG_TOPLEVEL_RESIZE_EDGE_NONE;
    }
}

private int framePointerX_, framePointerY_; // the pointer on a frame, frame-surface coordinates

/// The pointer is over `w`'s frame at `(sx, sy)`: the part under it is
/// highlighted and gets its cursor.
private void framePointerAt(WldWindow w, wl_fixed_t sx, wl_fixed_t sy, bool entered)
{
    framePointerX_ = wl_fixed_to_int(sx);
    framePointerY_ = wl_fixed_to_int(sy);
    auto part = deco.partAt(w.frameState, framePointerX_, framePointerY_);
    if (part == w.frameState.hovered && !entered) return;
    bool redraw = isFrameButton(part) || isFrameButton(w.frameState.hovered);
    w.frameState.hovered = part;
    applyCursor(frameCursor(part));
    if (redraw) redrawFrame(w);
}

private bool isFrameButton(deco.Part p)
{
    return p == deco.Part.close || p == deco.Part.maximize || p == deco.Part.minimize;
}

/// The pointer left `w`'s frame.
private void framePointerLeft(WldWindow w)
{
    bool redraw = isFrameButton(w.frameState.hovered) || w.frameState.pressed != deco.Part.none;
    w.frameState.hovered = deco.Part.none;
    w.frameState.pressed = deco.Part.none;
    if (redraw) redrawFrame(w);
}

/**
 * A mouse button on `w`'s frame: the title bar moves the window (a
 * double click maximizes or restores it, the right button opens the
 * compositor's window menu), the margin resizes it, and the buttons
 * minimize, maximize or close it when released over them.
 */
private void frameButton(WldWindow w, uint serial, uint time, uint btn, bool pressed)
{
    auto st = &w.frameState;
    auto top = w.xdgToplevel;
    if (top is null || seat_ is null) return;
    auto part = deco.partAt(*st, framePointerX_, framePointerY_);
    if (btn == BTN_RIGHT && pressed && part == deco.Part.title && w.canWindowMenu)
    {
        int m = deco.margin(*st);
        xdg_toplevel_show_window_menu(top, seat_, serial, framePointerX_ - m, framePointerY_ - m);
        return;
    }
    if (btn != BTN_LEFT) return;
    if (pressed)
    {
        if (part == deco.Part.title)
        {
            bool doubleClick = time - w.lastTitleClick < 400;
            w.lastTitleClick = doubleClick ? 0 : time;
            if (doubleClick) toggleMaximized(w);
            else xdg_toplevel_move(top, seat_, serial);
        }
        else if (resizeEdge(part) != XDG_TOPLEVEL_RESIZE_EDGE_NONE)
            xdg_toplevel_resize(top, seat_, serial, resizeEdge(part));
        else if (isFrameButton(part))
        {
            st.pressed = part;
            redrawFrame(w);
        }
        return;
    }
    auto was = st.pressed;
    st.pressed = deco.Part.none;
    if (!isFrameButton(was)) return;
    redrawFrame(w);
    if (part != was) return;
    FlWindow win = w.widget;
    final switch (was)
    {
        case deco.Part.close:
            // after the pointer event is done, as for the compositor's close button
            addTimeout(0.0, () { if (win.shown()) dispatch(Event.close, win); });
            break;
        case deco.Part.maximize:
            toggleMaximized(w);
            break;
        case deco.Part.minimize:
            xdg_toplevel_set_minimized(top);
            break;
        case deco.Part.none, deco.Part.title, deco.Part.resizeTop, deco.Part.resizeBottom,
            deco.Part.resizeLeft, deco.Part.resizeRight, deco.Part.resizeTopLeft,
            deco.Part.resizeTopRight, deco.Part.resizeBottomLeft, deco.Part.resizeBottomRight:
            break;
    }
}

/**
 * A pen over `surface` at `(sx, sy)`: when it is a window's frame (fldtk's
 * own title bar), the pen works it as the left mouse button does --
 * the part under it is highlighted, touching moves or resizes the
 * window or presses a button, lifting releases it -- and true is
 * returned; else false. `left`: the pen left the surface.
 */
package(fl) bool penOnFrame(wl_surface* surface, wl_fixed_t sx, wl_fixed_t sy, bool down, bool up,
    bool left, uint serial, uint time)
{
    auto w = frameOwner(surface);
    if (w is null) return false;
    if (left)
    {
        framePointerLeft(w);
        return true;
    }
    framePointerX_ = wl_fixed_to_int(sx);
    framePointerY_ = wl_fixed_to_int(sy);
    auto part = deco.partAt(w.frameState, framePointerX_, framePointerY_);
    if (part != w.frameState.hovered)
    {
        bool redraw = isFrameButton(part) || isFrameButton(w.frameState.hovered);
        w.frameState.hovered = part;
        if (redraw) redrawFrame(w);
    }
    if (down) frameButton(w, serial, time, BTN_LEFT, true);
    if (up) frameButton(w, serial, time, BTN_LEFT, false);
    return true;
}

/// Maximizes `w`, or restores it when it is maximized.
private void toggleMaximized(WldWindow w)
{
    if (w.xdgToplevel is null || !w.frameState.resizable || !w.canMaximize) return;
    if (w.frameState.maximized) xdg_toplevel_unset_maximized(w.xdgToplevel);
    else xdg_toplevel_set_maximized(w.xdgToplevel);
}

/// The program's name, for the window's app id when it has no
/// `xclass()` -- FLTK's `get_prog_name()`.
private string programName()
{
    import core.runtime : Runtime;
    import std.path : baseName;
    auto args = Runtime.args;
    return args.length ? baseName(args[0]) : "fldtk";
}

/**
 * Shows `win` -- ported from `Fl_Wayland_Window_Driver::makeWindow()`.
 * A subwindow is not shown yet (see this module's top comment).
 */
void createWindow(FlWindow win)
{
    openDisplay();
    FlGroup.current(null); // the common mistake of a missing end()
    if (win.parent !is null)
    {
        // A subwindow is shown with its parent window (Event.show).
        FlWindow parentWin = win.window();
        auto pw = parentWin !is null ? find(parentWin) : null;
        if (pw is null)
        {
            win.setVisible();
            return;
        }
        createSubwindow(win, pw);
        return;
    }
    if (win.rawScreenNum() < 0) win.rawScreenNum(0);

    // A toplevel window has no position on Wayland (a popup keeps the
    // one fldtk placed it at, relative to the program window).
    if (!isPopupWindow(win) && (win.x() != 0 || win.y() != 0))
    {
        resizeBugFix_ = win;
        win.resize(0, 0, win.w(), win.h());
    }

    auto w = new WldWindow;
    w.widget = win;
    w.surface = wl_compositor_create_surface(compositor_);
    wl_surface_add_listener(w.surface, &surfaceListener, cast(void*) w);
    attachFractionalScale(w);

    // rectangular windows are opaque
    wl_region* opaque = wl_compositor_create_region(compositor_);
    wl_region_add(opaque, 0, 0, 1_000_000, 1_000_000);
    wl_surface_set_opaque_region(w.surface, opaque);
    wl_region_destroy(opaque);

    string appId = win.xclass().length ? win.xclass() : programName();
    WldWindow parentOfPopup = isPopupWindow(win) ? popupParentFor(win) : null;
    if (parentOfPopup !is null)
        createPopup(w, parentOfPopup);
    else
    {
        // A window with a border asks the compositor to draw its
        // decorations (xdg-decoration); when it won't, fldtk draws them
        // (updateFrame()).
        w.kind = win.border() && !isPopupWindow(win) ? Kind.decorated : Kind.unframed;
        w.xdgSurface = xdg_wm_base_get_xdg_surface(wmBase_, w.surface);
        xdg_surface_add_listener(w.xdgSurface, &xdgSurfaceListener, cast(void*) w);
        w.xdgToplevel = xdg_surface_get_toplevel(w.xdgSurface);
        xdg_toplevel_add_listener(w.xdgToplevel, &xdgToplevelListener, cast(void*) w);
        xdg_toplevel_set_app_id(w.xdgToplevel, appId.toStringz);
        if (win.label().length) xdg_toplevel_set_title(w.xdgToplevel, win.label().toStringz);
        float f = screenScale(win.screenNum());
        w.floatingW = cast(int)(win.w() * f);
        w.floatingH = cast(int)(win.h() * f);
        w.frameState.zoom = f;
        w.frameState.resizable = userResizable(win);
        if (w.kind == Kind.decorated && decorationManager_ !is null)
        {
            w.decoration = zxdg_decoration_manager_v1_get_toplevel_decoration(decorationManager_, w.xdgToplevel);
            zxdg_toplevel_decoration_v1_add_listener(w.decoration, &decorationListener, cast(void*) w);
            zxdg_toplevel_decoration_v1_set_mode(w.decoration, ZXDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE);
        }
        wl_surface_commit(w.surface);
    }

    if (win.modal() || win.nonModal())
    {
        WldWindow parent;
        foreach (e; windows_) if (isToplevel(e)) { parent = e; break; }
        if (parent !is null && w.xdgToplevel !is null)
        {
            auto pt = toplevelOf(parent);
            if (pt !is null) xdg_toplevel_set_parent(w.xdgToplevel, pt);
        }
    }

    windows_ = w ~ windows_;
    import fl.xlib : XlibWindow = Window;
    win.markShown(cast(XlibWindow) cast(void*) w);
    sizeRangeChanged(win);
    toplevelReady(w);

    if (win.modal())
    {
        modal(win);
        fixFocus(win);
    }
    win.handle(Event.show);
    win.redraw();
    wl_display_flush(display_);
}

/**
 * What needs the window's `xdg_toplevel`: its icons, and for a modal or
 * non-modal window, telling the compositor it is a dialog (xdg-dialog).
 */
private void toplevelReady(WldWindow w)
{
    if (w.kind == Kind.popup || w.kind == Kind.subwindow) return;
    auto top = toplevelOf(w);
    if (top is null) return;
    FlWindow win = w.widget;
    if (w.dialog is null && dialogManager_ !is null && (win.modal() || win.nonModal()))
    {
        w.dialog = xdg_wm_dialog_v1_get_xdg_dialog(dialogManager_, top);
        if (win.modal()) xdg_dialog_v1_set_modal(w.dialog);
    }
    if (w.iconImages.length == 0) setIcons(win);
}

private xdg_toplevel* toplevelOf(WldWindow w)
{
    return w.xdgToplevel;
}

// ---- subwindows

/// Places `w`'s surface in its parent's as a subsurface -- the
/// subwindow part of FLTK's `makeWindow()` and `map()`. It is
/// desynchronized, so it shows each commit at once; the parent is
/// committed for the subsurface itself to appear.
private void mapSubsurface(WldWindow w, WldWindow pw)
{
    FlWindow win = w.widget;
    float f = screenScale(win.topWindow().screenNum());
    w.subsurface = wl_subcompositor_get_subsurface(subcompositor_, w.surface, pw.surface);
    wl_subsurface_set_position(w.subsurface, cast(int)(win.x() * f), cast(int)(win.y() * f));
    wl_subsurface_set_desync(w.subsurface);
    wl_subsurface_place_above(w.subsurface, pw.surface);
    w.configuredW = win.w() > 0 ? win.w() : 1;
    w.configuredH = win.h() > 0 ? win.h() : 1;
    w.waitingForExpose = false;
    wl_surface_commit(pw.surface);
}

/// Shows subwindow `win` inside `pw`.
private void createSubwindow(FlWindow win, WldWindow pw)
{
    if (subcompositor_ is null)
    {
        win.setVisible();
        return;
    }
    auto w = new WldWindow;
    w.widget = win;
    w.kind = Kind.subwindow;
    w.surface = wl_compositor_create_surface(compositor_);
    wl_surface_add_listener(w.surface, &surfaceListener, cast(void*) w);
    attachFractionalScale(w);
    win.rawScreenNum(win.topWindow().screenNum());
    mapSubsurface(w, pw);
    // after the first window, as FLTK's Fl_X list does
    windows_ = windows_.length ? windows_[0 .. 1] ~ w ~ windows_[1 .. $] : [w];
    import fl.xlib : XlibWindow = Window;
    win.markShown(cast(XlibWindow) cast(void*) w);
    win.handle(Event.show);
    win.redraw();
}

// ---- popups: menus and tooltips

/// A program window (not a popup or a subwindow) that can parent popups.
private bool isToplevel(WldWindow w)
{
    return (w.kind == Kind.decorated || w.kind == Kind.unframed) && w.xdgSurface !is null;
}

/// Menus and tooltips are popups -- FLTK's `popup_window()`.
private bool isPopupWindow(FlWindow win)
{
    return win.menuWindow() || win.tooltipWindow();
}

/**
 * The shown window a new popup is placed against: for a menu level, the
 * menu level shown last (a cascade); otherwise the program window under
 * the pointer, or the most recently used one.
 */
private WldWindow popupParentFor(FlWindow win)
{
    if (win.menuWindow())
        foreach (w; windows_)
            if (w.kind == Kind.popup && w.widget.menuWindow() && w.xdgSurface !is null) return w;
    if (auto b = belowmouse())
        if (auto top = b.topWindow())
            if (auto w = find(top))
                if (isToplevel(w)) return w;
    foreach (w; windows_)
        if (isToplevel(w)) return w;
    return null;
}

/// Where `w`'s top-left corner should be, relative to its parent's
/// window geometry, in pixels: fldtk places menus and tooltips in the
/// coordinates of the program window, whose toplevel origin is (0, 0).
private void popupPlacement(WldWindow w, out int x, out int y)
{
    auto parent = w.popupParent;
    float f = screenScale(parent.widget.screenNum());
    x = cast(int)((w.widget.x() - parent.widget.x()) * f);
    y = cast(int)((w.widget.y() - parent.widget.y()) * f) + titleOffset(parent);
}

/// The area of `parent`'s content in its window geometry, as far as
/// popups go: below the title bar fldtk draws, if any.
private void popupParentArea(WldWindow parent, out int x0, out int y0, out int x1, out int y1)
{
    float f = screenScale(parent.widget.screenNum());
    int t = titleOffset(parent);
    x0 = 0;
    y0 = t;
    x1 = cast(int)(parent.widget.w() * f) - 1;
    y1 = cast(int)(parent.widget.h() * f) - 1 + t;
}

/**
 * A positioner putting `w` where fldtk placed it -- the part of FLTK's
 * `process_menu_or_tooltip()` that applies to fldtk's menu engine, which
 * computes every menu level's position itself. The anchor point is
 * that position, kept inside the parent (an anchor outside it is a
 * protocol error) and completed by an offset; the compositor slides a
 * menu, and slides or flips a tooltip, to keep it on screen.
 */
private xdg_positioner* popupPositioner(WldWindow w)
{
    int x, y;
    popupPlacement(w, x, y);
    int x0, y0, x1, y1;
    popupParentArea(w.popupParent, x0, y0, x1, y1);
    int ax = x < x0 ? x0 : x > x1 ? x1 : x;
    int ay = y < y0 ? y0 : y > y1 ? y1 : y;
    float f = screenScale(w.popupParent.widget.screenNum());
    xdg_positioner* pos = xdg_wm_base_create_positioner(wmBase_);
    xdg_positioner_set_size(pos, cast(int)(w.widget.w() * f) > 0 ? cast(int)(w.widget.w() * f) : 1,
        cast(int)(w.widget.h() * f) > 0 ? cast(int)(w.widget.h() * f) : 1);
    xdg_positioner_set_anchor_rect(pos, ax, ay, 1, 1);
    xdg_positioner_set_anchor(pos, XDG_POSITIONER_ANCHOR_TOP_LEFT);
    xdg_positioner_set_gravity(pos, XDG_POSITIONER_GRAVITY_BOTTOM_RIGHT);
    xdg_positioner_set_offset(pos, x - ax, y - ay);
    uint constraint = XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_SLIDE_X | XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_SLIDE_Y;
    if (w.widget.tooltipWindow())
        constraint = XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_SLIDE_X | XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_FLIP_Y;
    xdg_positioner_set_constraint_adjustment(pos, constraint);
    return pos;
}

/// Makes `w` a popup of `parent`.
private void createPopup(WldWindow w, WldWindow parent)
{
    w.kind = Kind.popup;
    w.popupParent = parent;
    w.xdgSurface = xdg_wm_base_get_xdg_surface(wmBase_, w.surface);
    xdg_surface_add_listener(w.xdgSurface, &xdgSurfaceListener, cast(void*) w);
    xdg_positioner* pos = popupPositioner(w);
    w.xdgPopup = xdg_surface_get_popup(w.xdgSurface, parent.xdgSurface, pos);
    xdg_positioner_destroy(pos);
    xdg_popup_add_listener(w.xdgPopup, &popupListener, cast(void*) w);
    w.widget.rawScreenNum(parent.widget.screenNum());
    wl_surface_commit(w.surface);
}

/// Moves `w` to where fldtk now places it (a menu scrolled to keep its
/// selected item visible, say).
private void repositionPopup(WldWindow w)
{
    if (w.xdgPopup is null || w.popupParent is null) return;
    if (xdg_popup_get_version(w.xdgPopup) < XDG_POPUP_REPOSITION_SINCE_VERSION) return;
    xdg_positioner* pos = popupPositioner(w);
    static uint token;
    xdg_popup_reposition(w.xdgPopup, pos, ++token);
    xdg_positioner_destroy(pos);
}

/// Where the compositor put the popup, relative to its parent: written
/// back into the window, so the menu engine's hit tests match what is on
/// screen.
extern (C) private void popupConfigure(void* data, xdg_popup* popup, int x, int y, int width, int height) nothrow
{
    guarded({
    auto w = cast(WldWindow) data;
    auto parent = w.popupParent;
    if (parent is null) return;
    int ox = 0, oy = titleOffset(parent);
    float f = screenScale(parent.widget.screenNum());
    int nx = parent.widget.x() + cast(int)((x - ox) / f);
    int ny = parent.widget.y() + cast(int)((y - oy) / f);
    if (nx != w.widget.x() || ny != w.widget.y())
    {
        resizeBugFix_ = w.widget;
        w.widget.resize(nx, ny, w.widget.w(), w.widget.h());
    }
    });
}

/// The compositor dismissed the popup (the program lost the focus, say)
/// -- FLTK's `popup_done()`: the window is hidden, so fldtk and the
/// compositor agree.
extern (C) private void popupDone(void* data, xdg_popup* popup) nothrow
{
    guarded({
    auto w = cast(WldWindow) data;
    FlWindow win = w.widget;
    addTimeout(0.0, () { if (win.shown()) win.hide(); });
    });
}

extern (C) private void popupRepositioned(void* data, xdg_popup* popup, uint token) nothrow { }

private __gshared xdg_popup_listener popupListener = {
    configure: &popupConfigure,
    popup_done: &popupDone,
    repositioned: &popupRepositioned,
};

/**
 * Hides `win` and frees what showing it created -- ported from
 * `Fl_Wayland_Window_Driver::hide()`.
 */
void destroyWindow(FlWindow win)
{
    auto w = find(win);
    if (w is null) return;
    import std.algorithm : remove;
    import std.algorithm.searching : countUntil;
    windows_ = windows_.remove(windows_.countUntil(w));
    win.markHidden();

    if (modal() is win)
    {
        FlWindow next;
        foreach (e; windows_) if (e.widget.modal()) { next = e.widget; break; }
        modal(next);
    }
    throwFocus(win);
    win.handle(Event.hide);

    // a popup's own popups must go first (xdg-shell requires it), and a
    // window's subwindows go with it
    foreach (child; windows_.dup)
        if (child.popupParent is w || (child.kind == Kind.subwindow && child.widget.window() is win))
            child.widget.hide();

    releaseBuffer(w);
    eglDriver.windowDestroyed(w);
    {
        import penDriver = fl.wayland_pen_driver;
        penDriver.surfaceDestroyed(w.surface);
        if (w.frameSurface !is null) penDriver.surfaceDestroyed(w.frameSurface);
    }
    if (w.frameCb !is null) { wl_callback_destroy(w.frameCb); w.frameCb = null; }
    if (w.xdgPopup !is null)
    {
        xdg_popup_destroy(w.xdgPopup);
        w.xdgPopup = null;
    }
    if (w.subsurface !is null)
    {
        wl_subsurface_destroy(w.subsurface);
        w.subsurface = null;
    }
    w.popupParent = null;
    destroyFrame(w);
    if (w.decoration !is null) zxdg_toplevel_decoration_v1_destroy(w.decoration); // before its toplevel
    w.decoration = null;
    {
        if (w.xdgToplevel !is null) xdg_toplevel_destroy(w.xdgToplevel);
        if (w.xdgSurface !is null) xdg_surface_destroy(w.xdgSurface);
        w.xdgToplevel = null;
        w.xdgSurface = null;
    }
    if (w.dialog !is null) { xdg_dialog_v1_destroy(w.dialog); w.dialog = null; }
    foreach (img; w.iconImages) img.destroy();
    w.iconImages = null;
    if (w.customCursor !is null) { w.customCursor.destroy(); w.customCursor = null; }
    if (w.viewport !is null) { wp_viewport_destroy(w.viewport); w.viewport = null; }
    if (w.fractional !is null) { wp_fractional_scale_v1_destroy(w.fractional); w.fractional = null; }
    if (w.surface !is null)
    {
        if (pointerFocus_ is w.surface) pointerFocus_ = null;
        if (keyboardSurface_ is w.surface) keyboardSurface_ = null;
        wl_surface_destroy(w.surface);
    }
    w.surface = null;
    w.outputs = null;
    wl_display_flush(display_);
}

/// Shows a hidden subwindow again -- FLTK's `map()` -- or brings a
/// toplevel window to the front (`activateWindow()`).
void raiseWindow(FlWindow win)
{
    auto w = find(win);
    if (w !is null && isToplevel(w))
    {
        activateWindow(w);
        return;
    }
    if (w is null || w.kind != Kind.subwindow || w.subsurface !is null) return;
    auto pw = find(win.window());
    if (pw is null) return;
    mapSubsurface(w, pw);
    win.redraw();
}

/// Hides a subwindow without destroying it -- FLTK's `unmap()`.
void unmapWindow(FlWindow win)
{
    auto w = find(win);
    if (w is null || w.kind != Kind.subwindow || w.subsurface is null) return;
    wl_surface_attach(w.surface, null, 0, 0);
    wl_surface_commit(w.surface);
    releaseBuffer(w);
    // an unmapped surface gets no frame callbacks (a GL window's swaps wait for one)
    if (w.frameCb !is null) { wl_callback_destroy(w.frameCb); w.frameCb = null; }
    wl_subsurface_destroy(w.subsurface);
    w.subsurface = null;
}

/// Ported from `Fl_Wayland_Window_Driver::iconize()`.
package(fl) void iconizeWindow(FlWindow win)
{
    auto w = find(win);
    if (w is null) return;
    if (w.xdgToplevel !is null) xdg_toplevel_set_minimized(w.xdgToplevel);
}

/// Waits until `win` has been configured and drawn once -- ported from
/// `Fl_Wayland_Window_Driver::wait_for_expose()`.
package(fl) void waitForExpose(FlWindow win)
{
    auto w = find(win);
    while (w !is null && w.surface !is null && w.waitingForExpose)
    {
        int r = dispatchEvents(-1);
        rethrowPending();
        if (r < 0) break;
    }
}

/**
 * A resize or move asked for by the program -- ported from the parts of
 * `Fl_Wayland_Window_Driver::resize()` that apply to toplevel windows:
 * they can't move, and a new size is offered to the compositor.
 */
package(fl) void resizeWindow(FlWindow win, int x, int y, int w_, int h, bool isMove, bool isResize,
    int exactDevX = int.min, int exactDevY = int.min)
{
    auto w = find(win);
    if (w is null) return;
    if (w.kind == Kind.popup)
    {
        if (isResize) releaseBuffer(w);
        repositionPopup(w);
        win.redraw();
        return;
    }
    if (w.kind == Kind.subwindow)
    {
        if (w.subsurface !is null)
        {
            float sf = screenScale(win.topWindow().screenNum());
            wl_subsurface_set_position(w.subsurface, cast(int)(x * sf), cast(int)(y * sf));
            if (auto pw = find(win.window())) wl_surface_commit(pw.surface); // applies the position
        }
        if (isResize)
        {
            releaseBuffer(w);
            w.configuredW = w_ > 0 ? w_ : 1;
            w.configuredH = h > 0 ? h : 1;
        }
        win.redraw();
        return;
    }
    if (isMove && (win.x() != 0 || win.y() != 0))
    {
        resizeBugFix_ = win;
        win.resize(0, 0, win.w(), win.h());
        startInteractiveMove(w);
    }
    if (!isResize) return;
    float f = screenScale(win.screenNum());
    releaseBuffer(w);
    w.configuredW = w_;
    w.configuredH = h;
    auto st = &w.frameState;
    if (!st.maximized && !st.fullscreen && !st.tiled)
    {
        w.floatingW = cast(int)(w_ * f);
        w.floatingH = cast(int)(h * f);
    }
    toplevelGeometryChanged(w);
    win.redraw();
}

private uint movedForSerial_; // the button press a move was last started for

/**
 * A window moving itself while a mouse button is held (a borderless
 * window dragged by its content, as `examples/shapedwindow` does) gets
 * the compositor to move it instead, once per press -- Wayland never
 * lets a program place its own window. Beyond FLTK, where such a
 * window doesn't move on Wayland.
 */
private void startInteractiveMove(WldWindow w)
{
    if (seat_ is null || !(eState_ & stateButtons) || buttonSerial_ == movedForSerial_) return;
    movedForSerial_ = buttonSerial_;
    if (w.xdgToplevel !is null)
        xdg_toplevel_move(w.xdgToplevel, seat_, buttonSerial_);
    else
        return;
    // The compositor keeps the button release; the widget gets it once
    // the event that moved the window is done.
    FlWindow win = w.widget;
    addTimeout(0.0, () {
        if (!win.shown() || !(eState_ & stateButtons)) return;
        eState_ &= ~stateButtons;
        dispatch(Event.release, win);
    });
}

/// Ported from `Fl_Wayland_Window_Driver::size_range()`.
package(fl) void sizeRangeChanged(FlWindow win)
{
    auto w = find(win);
    if (w is null) return;
    float f = screenScale(win.screenNum());
    int minw, minh, maxw, maxh, dw, dh;
    bool aspect;
    win.getSizeRange(&minw, &minh, &maxw, &maxh, &dw, &dh, &aspect);
    if (w.xdgToplevel is null) return;
    // the window geometry includes the title bar fldtk draws
    int t = titleOffset(w);
    w.sizeRangeTitle = t;
    xdg_toplevel_set_min_size(w.xdgToplevel, cast(int)(minw * f), cast(int)(minh * f) + t);
    if (maxw && maxh)
        xdg_toplevel_set_max_size(w.xdgToplevel, cast(int)(maxw * f), cast(int)(maxh * f) + t);
    else
        xdg_toplevel_set_max_size(w.xdgToplevel, 0, 0);
    bool resizable = userResizable(win);
    if (resizable != w.frameState.resizable)
    {
        w.frameState.resizable = resizable;
        redrawFrame(w);
    }
}

/// Window decorations belong to the compositor or are drawn by fldtk on
/// a surface of their own; either way they are not part of the window.
package(fl) bool decoratedWinSize(FlWindow win, out int w, out int h)
{
    w = win.w();
    h = win.h();
    return false;
}

/// Ported from `Fl_Wayland_Window_Driver::label()`.
package(fl) void updateWindowLabel(FlWindow win)
{
    auto w = find(win);
    if (w is null) return;
    if (w.xdgToplevel !is null) xdg_toplevel_set_title(w.xdgToplevel, win.label().toStringz);
    redrawFrame(w);
}


/// Ported from `fullscreen_on()`, for decorated and unframed windows.
package(fl) void fullscreenOn(FlWindow win)
{
    auto w = find(win);
    if (w is null || w.xdgToplevel is null) return;
    wl_output* output = win.screenNum() < outputs_.length ? outputs_[win.screenNum()].output : null;
    xdg_toplevel_set_fullscreen(w.xdgToplevel, output);
    win.setFullscreenFlag();
    dispatch(Event.fullscreen, win);
}

/// Ported from `fullscreen_off()`. The compositor gives the window back
/// its size from before (or leaves it to the program, which then takes
/// the size it last had while floating, `applyToplevelConfigure()`).
package(fl) void fullscreenOff(FlWindow win)
{
    auto w = find(win);
    if (w is null || w.xdgToplevel is null) return;
    xdg_toplevel_unset_fullscreen(w.xdgToplevel);
    win.clearFullscreenFlag();
    dispatch(Event.fullscreen, win);
}

/// Ported from `maximize()`.
package(fl) void maximizeOn(FlWindow win)
{
    auto w = find(win);
    if (w is null) return;
    if (w.xdgToplevel !is null) xdg_toplevel_set_maximized(w.xdgToplevel);
}

/// Ported from `un_maximize()`.
package(fl) void maximizeOff(FlWindow win)
{
    auto w = find(win);
    if (w is null) return;
    if (w.xdgToplevel !is null) xdg_toplevel_unset_maximized(w.xdgToplevel);
}



/// The X11 module's bounding-box damage tracking, for the same reason
/// (see `fl.platform_x11.accumulateDamage()`).
package(fl) void accumulateDamage(FlWindow win, int x, int y, int w, int h)
{
    auto r = find(win);
    if (r is null || r.fullRepaintPending) return;
    if (!r.hasDamageRegion)
    {
        r.hasDamageRegion = true;
        r.damageX = x;
        r.damageY = y;
        r.damageW = w;
        r.damageH = h;
        return;
    }
    int x2 = r.damageX + r.damageW, y2 = r.damageY + r.damageH;
    if (x < r.damageX) r.damageX = x;
    if (y < r.damageY) r.damageY = y;
    if (x + w > x2) x2 = x + w;
    if (y + h > y2) y2 = y + h;
    r.damageW = x2 - r.damageX;
    r.damageH = y2 - r.damageY;
}

/// ditto
package(fl) void clearDamageRegion(FlWindow win)
{
    auto r = find(win);
    if (r is null) return;
    r.hasDamageRegion = false;
    r.fullRepaintPending = true;
}

/// `(x, y, w, h)` (pixels) of `win`'s draw buffer, as RGB.
package(fl) ubyte[] captureWindowPixels(FlWindow win, int x, int y, int w, int h)
{
    auto r = find(win);
    if (r is null || r.buffer is null || w <= 0 || h <= 0) return null;
    auto b = r.buffer;
    cairo_surface_flush(cairo_get_target(b.cr));
    auto rgb = new ubyte[w * h * 3];
    foreach (j; 0 .. h)
        foreach (i; 0 .. w)
        {
            int px = x + i, py = y + j;
            if (px < 0 || py < 0 || px >= b.width || py >= b.height) continue;
            uint p = *cast(uint*)(b.pixels.ptr + py * b.stride + px * 4);
            auto q = rgb.ptr + (j * w + i) * 3;
            q[0] = cast(ubyte)(p >> 16);
            q[1] = cast(ubyte)(p >> 8);
            q[2] = cast(ubyte) p;
        }
    return rgb;
}

/// The title bar belongs to the compositor or to fldtk's own frame,
/// neither of which is captured.
package(fl) RGBImage captureTitlebarImage(FlWindow win) { return null; }

package(fl) FlWindow firstWindowWidget()
{
    return windows_.length ? windows_[0].widget : null;
}

package(fl) FlWindow nextWindowWidget(FlWindow win)
{
    foreach (i, w; windows_)
        if (w.widget is win) return i + 1 < windows_.length ? windows_[i + 1].widget : null;
    return null;
}

package(fl) void makeWindowFirst(FlWindow win)
{
    auto w = find(win);
    if (w is null || windows_[0] is w) return;
    import std.algorithm : remove;
    import std.algorithm.searching : countUntil;
    windows_ = w ~ windows_.remove(windows_.countUntil(w));
}

// ---- images in shared memory: cursors and icons

/// A premultiplied ARGB image in a shared-memory `wl_buffer`, for the
/// compositor to show as it is (cursor images, window icons).
private final class ShmImage
{
    wl_buffer* buffer;
    void* data;
    size_t size;
    int w, h;

    void destroy()
    {
        import core.sys.posix.sys.mman : munmap;
        if (buffer !is null) wl_buffer_destroy(buffer);
        if (data !is null) munmap(data, size);
        buffer = null;
        data = null;
    }
}

/// `image` at `w` x `h` pixels, placed at `(dx, dy)` in an `outW` x
/// `outH` image (transparent around it), as premultiplied ARGB in
/// shared memory -- the pixel conversion `fl.platform_x11.
/// setCursorImage()` makes for Xcursor.
private ShmImage shmImageFrom(const(RGBImage) image, int w, int h, int outW, int outH, int dx, int dy)
{
    import core.sys.posix.sys.mman : mmap, PROT_READ, PROT_WRITE, MAP_SHARED, MAP_FAILED;
    import core.sys.posix.unistd : ftruncate, close;
    if (image is null || w <= 0 || h <= 0 || outW <= 0 || outH <= 0) return null;
    auto resampled = image.copy(w, h);
    if (resampled is null) return null;
    resampled.normalize(); // an SvgImage's copy is rasterized only on demand
    if (resampled.array.length == 0) return null;
    int d = resampled.d();
    if (d < 1 || d > 4) return null;
    int ld = resampled.ld() ? resampled.ld() : w * d;

    auto img = new ShmImage;
    img.w = outW;
    img.h = outH;
    img.size = cast(size_t) outW * outH * 4;
    int fd = memfd_create("fldtk-image", MFD_CLOEXEC);
    if (fd < 0 || ftruncate(fd, img.size) < 0) return null;
    img.data = mmap(null, img.size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (img.data == MAP_FAILED) { close(fd); return null; }
    auto px = (cast(uint*) img.data)[0 .. outW * outH];
    px[] = 0;
    foreach (y; 0 .. h)
    {
        const(ubyte)* row = resampled.array.ptr + y * ld;
        foreach (x; 0 .. w)
        {
            if (x + dx < 0 || x + dx >= outW || y + dy < 0 || y + dy >= outH) continue;
            const(ubyte)* p = row + x * d;
            uint r, g, b, a = 0xff;
            final switch (d)
            {
                case 1: r = g = b = p[0]; break;
                case 2: r = g = b = p[0]; a = p[1]; break;
                case 3: r = p[0]; g = p[1]; b = p[2]; break;
                case 4: r = p[0]; g = p[1]; b = p[2]; a = p[3]; break;
            }
            px[(y + dy) * outW + x + dx] = a << 24 | (r * a / 255) << 16 | (g * a / 255) << 8 | (b * a / 255);
        }
    }
    wl_shm_pool* pool = wl_shm_create_pool(shm_, fd, cast(int) img.size);
    img.buffer = wl_shm_pool_create_buffer(pool, 0, outW, outH, outW * 4, WL_SHM_FORMAT_ARGB8888);
    wl_shm_pool_destroy(pool);
    close(fd);
    return img;
}

/// The scale cursor images are made at: the largest screen scale.
private int cursorImageScale()
{
    int s = 1;
    foreach (o; outputs_) if (o.wldScale > s) s = o.wldScale;
    return s;
}

// ---- window icons (xdg-toplevel-icon)

extern (C) private void iconManagerIconSize(void* data, xdg_toplevel_icon_manager_v1* m, int size) nothrow { }
extern (C) private void iconManagerDone(void* data, xdg_toplevel_icon_manager_v1* m) nothrow { }

private __gshared xdg_toplevel_icon_manager_v1_listener iconManagerListener = {
    icon_size: &iconManagerIconSize,
    done: &iconManagerDone,
};

/**
 * Gives `win`'s icons (`Window.icons()`, else the default icons) to the
 * compositor, through xdg-toplevel-icon when it has that protocol --
 * beyond FLTK, which leaves the icon to the desktop file named by the
 * app id. Without the protocol (KDE Plasma 5.27, GNOME) nothing is done,
 * and the desktop shows the desktop file's icon or a generic one.
 * Icons must be square: each is centred on a transparent square.
 */
package(fl) void setIcons(FlWindow win)
{
    auto w = find(win);
    if (w is null || iconManager_ is null) return;
    auto top = toplevelOf(w);
    if (top is null) return;
    auto icons = win.iconsForWM();
    if (icons.length == 0) icons = FlWindow.defaultIconsForWM();
    foreach (img; w.iconImages) img.destroy();
    w.iconImages = null;
    if (icons.length == 0)
    {
        xdg_toplevel_icon_manager_v1_set_icon(iconManager_, top, null);
        return;
    }
    xdg_toplevel_icon_v1* icon = xdg_toplevel_icon_manager_v1_create_icon(iconManager_);
    foreach (img; icons)
    {
        int iw = img.w(), ih = img.h();
        int n = iw > ih ? iw : ih;
        auto sq = shmImageFrom(img, iw, ih, n, n, (n - iw) / 2, (n - ih) / 2);
        if (sq is null) continue;
        xdg_toplevel_icon_v1_add_buffer(icon, sq.buffer, 1);
        w.iconImages ~= sq;
    }
    xdg_toplevel_icon_manager_v1_set_icon(iconManager_, top, icon);
    xdg_toplevel_icon_v1_destroy(icon);
}

// ---- activation (xdg-activation)

extern (C) private void activationDone(void* data, xdg_activation_token_v1* token, const(char)* tokenString) nothrow
{
    guarded({
    auto target = cast(WldWindow) data;
    if (target.surface !is null) xdg_activation_v1_activate(activation_, tokenString, target.surface);
    xdg_activation_token_v1_destroy(token);
    });
}

private __gshared xdg_activation_token_v1_listener activationListener = { done: &activationDone };

/// Lets the window that has the keyboard activate `target` -- FLTK's
/// `activate_()` and `take_focus()`. Without xdg-activation, setting and
/// unsetting a parent brings `target` to the front.
private void activateWindow(WldWindow target)
{
    WldWindow current;
    foreach (e; windows_) if (isToplevel(e)) { current = e; break; }
    if (current is null || current is target || toplevelOf(target) is null) return;
    if (activation_ !is null)
    {
        xdg_activation_token_v1* token = xdg_activation_v1_get_activation_token(activation_);
        string appId = target.widget.xclass().length ? target.widget.xclass() : programName();
        xdg_activation_token_v1_set_app_id(token, appId.toStringz);
        xdg_activation_token_v1_set_surface(token, current.surface);
        if (seat_ !is null) xdg_activation_token_v1_set_serial(token, serial_, seat_);
        xdg_activation_token_v1_add_listener(token, &activationListener, cast(void*) target);
        xdg_activation_token_v1_commit(token);
    }
    else if (auto top = toplevelOf(target))
    {
        xdg_toplevel_set_parent(top, toplevelOf(current));
        xdg_toplevel_set_parent(top, null);
        wl_surface_commit(target.surface);
    }
}

// ---- shaped windows

/// Clears the pixels of `w`'s buffer outside its shape, which become
/// transparent -- FLTK's `draw_end()` masking. The mask is scaled to the
/// buffer.
private void applyShape(WldWindow w)
{
    auto b = w.buffer;
    if (b is null || w.shapeBits.length == 0 || w.shapeW <= 0 || w.shapeH <= 0) return;
    cairo_surface_flush(cairo_get_target(b.cr));
    int rowBytes = (w.shapeW + 7) / 8;
    foreach (y; 0 .. b.height)
    {
        int my = y * w.shapeH / b.height;
        auto row = cast(uint*)(b.pixels.ptr + y * b.stride);
        foreach (x; 0 .. b.width)
        {
            int mx = x * w.shapeW / b.width;
            size_t i = my * rowBytes + mx / 8;
            if (i >= w.shapeBits.length || !(w.shapeBits[i] & (1 << (mx & 7)))) row[x] = 0;
        }
    }
    cairo_surface_mark_dirty(cairo_get_target(b.cr));
}

/// Gives `win` the shape of a bitmap (`w` x `h`, X bitmap rows, a set
/// bit visible) -- FLTK's `shape()` on Wayland: outside the shape the
/// window's pixels are transparent, and it is no longer marked opaque.
package(fl) void applyWindowShapeMask(FlWindow win, int w_, int h, const(ubyte)[] bits)
{
    auto w = find(win);
    if (w is null || w_ <= 0 || h <= 0 || bits.length == 0) return;
    w.shapeBits = bits.idup;
    w.shapeW = w_;
    w.shapeH = h;
    if (w.surface !is null) wl_surface_set_opaque_region(w.surface, null);
    win.redraw();
}

// ---- subwindows: staying inside the parent

/// The part of subwindow `w` inside all its parents, in its own
/// coordinates -- FLTK's `checkSubwindowFrame()`. Drawing is clipped to
/// it, and the rest of the buffer stays transparent.
private void subwindowVisibleArea(WldWindow w, out int x, out int y, out int cw, out int ch)
{
    FlWindow win = w.widget;
    int x0 = 0, y0 = 0, x1 = win.w(), y1 = win.h();
    int fromX = 0, fromY = 0;
    FlWindow from = win;
    for (FlWindow parent = from.window(); parent !is null; parent = from.window())
    {
        fromX -= from.x();
        fromY -= from.y();
        if (fromX > x0) x0 = fromX;
        if (fromY > y0) y0 = fromY;
        if (fromX + parent.w() < x1) x1 = fromX + parent.w();
        if (fromY + parent.h() < y1) y1 = fromY + parent.h();
        from = parent;
    }
    x = x0;
    y = y0;
    cw = x1 > x0 ? x1 - x0 : 0;
    ch = y1 > y0 ? y1 - y0 : 0;
}

// -- drawing ------------------------------------------------------------

/// Creates `w`'s draw buffer at its current size and scale -- ported
/// from `create_wld_buffer()`/`cairo_init()`.
private Buffer newBuffer(int width, int height)
{
    auto b = new Buffer;
    b.width = width;
    b.height = height;
    b.stride = cairo_format_stride_for_width(CAIRO_FORMAT_ARGB32, width);
    b.pixels = new ubyte[](b.stride * height);
    cairo_surface_t* surf = cairo_image_surface_create_for_data(b.pixels.ptr, CAIRO_FORMAT_ARGB32,
        width, height, b.stride);
    b.cr = cairo_create(surf);
    cairo_surface_destroy(surf);
    return b;
}

/**
 * Makes `win` the target of drawing -- ported from
 * `Fl_Wayland_Window_Driver::make_current()`: creates the draw buffer
 * when the window has none (first draw, or after a resize or scale
 * change) and points the Cairo driver at it, at the window's scale.
 */
package(fl) void makeCurrent(FlWindow win)
{
    auto w = find(win);
    if (w is null) return;
    float f = screenScale(win.screenNum());
    if (win.asGlWindow() !is null)
    {
        // EGL draws into a GL window's surface (fl.wayland_gl_window_driver)
        currentScale(f);
        return;
    }
    float s = deviceScale(w);
    if (w.buffer is null)
    {
        // the logical size, times the device scale
        int lw = cast(int)(win.w() * f), lh = cast(int)(win.h() * f);
        int bw = cast(int)(lw * s + 0.5f), bh = cast(int)(lh * s + 0.5f);
        w.buffer = newBuffer(bw > 0 ? bw : 1, bh > 0 ? bh : 1);
        win.damage(damageAll);
        w.hasDamageRegion = false;
    }
    currentScale(f * s);
    fldraw.setCairoTarget(w.buffer.cr);
    // Drawing outside a repaint (an overlay rectangle, a program drawing
    // in response to an event) is shown by the next flushDamage() --
    // FLTK's "progressive drawing" commit in make_current().
    auto b = w.buffer;
    fldraw.cairoDisplayDriver().onDraw = () { b.needsCommit = true; };
}

/// The Cairo context of `win`'s draw buffer, or null before it is
/// drawn -- what FLTK's `Fl::cairo_make_current()` hands out on Wayland.
package(fl) cairo_t* windowCairo(FlWindow win)
{
    auto w = find(win);
    return w !is null && w.buffer !is null ? w.buffer.cr : null;
}

/// Frees `w`'s draw buffer; its shared-memory buffer goes once the
/// compositor no longer reads it -- ported from `buffer_release()`.
private void releaseBuffer(WldWindow w)
{
    auto b = w.buffer;
    if (b is null) return;
    w.buffer = null;
    if (w.frameCb !is null) { wl_callback_destroy(w.frameCb); w.frameCb = null; }
    fldraw.forgetCairoTarget(b.cr);
    cairo_destroy(b.cr);
    b.cr = null;
    b.pixels = null;
    if (b.overlayCr !is null)
    {
        fldraw.forgetCairoTarget(b.overlayCr);
        cairo_destroy(b.overlayCr);
        b.overlayCr = null;
    }
    b.overlayPixels = null;
    retireBuffer(b);
}

/// `b` is no longer drawn into or shown: its shared memory goes once the
/// compositor no longer reads it.
private void retireBuffer(Buffer b)
{
    if (b.cr !is null)
    {
        cairo_destroy(b.cr);
        b.cr = null;
        b.pixels = null;
    }
    b.released = true;
    if (!b.inUse) freeShm(b);
}

private void freeShm(Buffer b)
{
    import core.sys.posix.sys.mman : munmap;
    if (b.wlBuffer !is null) wl_buffer_destroy(b.wlBuffer);
    if (b.shmData !is null) munmap(b.shmData, b.shmSize);
    b.wlBuffer = null;
    b.shmData = null;
    import std.algorithm : remove;
    import std.algorithm.searching : countUntil;
    auto i = liveBuffers_.countUntil(b);
    if (i >= 0) liveBuffers_ = liveBuffers_.remove(i);
}

extern (C) private void bufferRelease(void* data, wl_buffer* wlBuffer) nothrow
{
    guarded({
    auto b = cast(Buffer) data;
    b.inUse = false;
    if (b.released) freeShm(b);
    });
}

private __gshared wl_buffer_listener bufferListener = { release: &bufferRelease };

// glibc's memfd_create(), not in druntime's bindings
extern (C) private int memfd_create(const(char)* name, uint flags) nothrow @nogc;
private enum uint MFD_CLOEXEC = 1;

/// Creates the shared-memory `wl_buffer` that `b` is copied into --
/// FLTK's `create_shm_buffer()`, with one pool per buffer instead of
/// FLTK's shared pools.
private void createShmBuffer(Buffer b)
{

    import core.sys.posix.sys.mman : mmap, PROT_READ, PROT_WRITE, MAP_SHARED, MAP_FAILED;
    import core.sys.posix.unistd : ftruncate, close;

    b.shmSize = cast(size_t) b.stride * b.height;
    int fd = memfd_create("fldtk-buffer", MFD_CLOEXEC);
    if (fd < 0 || ftruncate(fd, b.shmSize) < 0) fatal("Can't create a shared-memory buffer");
    b.shmData = mmap(null, b.shmSize, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (b.shmData == MAP_FAILED) fatal("mmap failed");
    wl_shm_pool* pool = wl_shm_create_pool(shm_, fd, cast(int) b.shmSize);
    b.wlBuffer = wl_shm_pool_create_buffer(pool, 0, b.width, b.height, b.stride, WL_SHM_FORMAT_ARGB8888);
    wl_shm_pool_destroy(pool); // the buffer keeps the memory
    close(fd);
    wl_buffer_add_listener(b.wlBuffer, &bufferListener, cast(void*) b);
    liveBuffers_ ~= b;
}

extern (C) private void frameDone(void* data, wl_callback* cb, uint time) nothrow
{
    guarded({
    auto w = cast(WldWindow) data;
    wl_callback_destroy(cb);
    w.frameCb = null;
    if (w.buffer !is null && w.buffer.needsCommit) commit(w);
    });
}

private __gshared wl_callback_listener frameListener = { done: &frameDone };

/**
 * Shows what was drawn into `w`'s draw buffer -- ported from
 * `buffer_commit()`: copies it into the shared-memory buffer, attaches
 * that, damages the surface and commits it, asking for a frame callback
 * that paces the next commit.
 */
private void commit(WldWindow w)
{
    auto b = w.buffer;
    if (b is null || w.surface is null) return;
    if (b.wlBuffer is null) createShmBuffer(b);
    cairo_surface_flush(cairo_get_target(b.cr));
    bool overlay = b.overlayCr !is null && overlayShown(w);
    if (overlay) cairo_surface_flush(cairo_get_target(b.overlayCr));
    memcpy(b.shmData, overlay ? b.overlayPixels.ptr : b.pixels.ptr, b.shmSize);
    wl_surface_damage_buffer(w.surface, 0, 0, b.width, b.height);
    b.inUse = true;
    wl_surface_attach(w.surface, b.wlBuffer, 0, 0);
    if (w.viewport !is null && (w.scale120 > 0 || w.kind == Kind.subwindow) && deviceScale(w) != wldScale(w))
    {
        // drawn at a fractional scale: the viewport gives the logical size
        float f = screenScale(w.widget.screenNum());
        int dw = cast(int)(w.widget.w() * f), dh = cast(int)(w.widget.h() * f);
        wl_surface_set_buffer_scale(w.surface, 1);
        // a viewport's size must be positive (a protocol error otherwise)
        wp_viewport_set_destination(w.viewport, dw > 0 ? dw : 1, dh > 0 ? dh : 1);
    }
    else
    {
        if (w.viewport !is null) wp_viewport_set_destination(w.viewport, -1, -1);
        wl_surface_set_buffer_scale(w.surface, wldScale(w));
    }
    w.frameCb = wl_surface_frame(w.surface);
    wl_callback_add_listener(w.frameCb, &frameListener, cast(void*) w);
    wl_surface_commit(w.surface);
    w.commits++;
    b.needsCommit = false;
}

/// Whether `w` is an overlay window whose overlay is showing.
private bool overlayShown(WldWindow w)
{
    auto ow = cast(OverlayWindow) w.widget;
    return ow !is null && ow.overlayActive();
}

/**
 * Draws an overlay window's overlay -- the Wayland form of FLTK's
 * `flush_overlay()`: the window's pixels are copied into a second
 * buffer and the overlay drawn over them, and that buffer is shown;
 * the window's own buffer stays clean, so the overlay is erased by
 * copying it again.
 */
private void drawOverlayOf(WldWindow w, OverlayWindow ow)
{
    auto b = w.buffer;
    if (b.overlayCr is null)
    {
        b.overlayPixels = new ubyte[](b.pixels.length);
        cairo_surface_t* surf = cairo_image_surface_create_for_data(b.overlayPixels.ptr,
            CAIRO_FORMAT_ARGB32, b.width, b.height, b.stride);
        b.overlayCr = cairo_create(surf);
        cairo_surface_destroy(surf);
    }
    cairo_surface_flush(cairo_get_target(b.cr));
    b.overlayPixels[] = b.pixels[];
    cairo_surface_mark_dirty(cairo_get_target(b.overlayCr));
    FlWindow.setCurrentForDraw(ow);
    makeCurrent(ow);
    fldraw.setCairoTarget(b.overlayCr);
    ow.drawOverlay();
    fldraw.setCairoTarget(b.cr);
    b.needsCommit = true;
}

/// Draws `w` if it has damage and commits the result -- ported from
/// `Fl_Wayland_Window_Driver::flush()`.
private void flushWindow(WldWindow w)
{
    FlWindow win = w.widget;
    if (w.configuredW == 0 || w.surface is null) return;
    if (auto glWin = win.asGlWindow())
    {
        // FLTK's flush() of a GL window; drawn again once its last frame
        // is shown (see fl.wayland_gl_window_driver's module comment)
        if (!win.damage() || glWaitsForFrame(w)) return;
        flushGlWindow(glWin);
        return;
    }
    // an overlay window's overlay changing alone doesn't redraw the window
    auto overlayWin = cast(OverlayWindow) win;
    bool overlayDirty = overlayWin !is null && (win.damage() & damageOverlay) != 0;
    if (overlayDirty) win.clearDamage(cast(Damage)(win.damage() & ~damageOverlay));
    bool drewWindow = false;
    if (win.damage() || w.buffer is null)
    {
        drewWindow = true;
        // A subwindow sticking out of its parent is drawn only inside
        // it; when that part changes, the buffer starts over transparent.
        bool subClipped = false;
        if (w.kind == Kind.subwindow)
        {
            int cx, cy, cw, ch;
            subwindowVisibleArea(w, cx, cy, cw, ch);
            if (cx != w.subClipX || cy != w.subClipY || cw != w.subClipW || ch != w.subClipH)
            {
                w.subClipX = cx; w.subClipY = cy; w.subClipW = cw; w.subClipH = ch;
                releaseBuffer(w);
            }
            subClipped = cx != 0 || cy != 0 || cw != win.w() || ch != win.h();
        }
        // setCurrentForDraw() sets the drawing scale to fldtk's own zoom
        // only; makeCurrent(), after it, multiplies in the compositor's.
        FlWindow.setCurrentForDraw(win);
        makeCurrent(win);
        if (subClipped) fldraw.pushClip(w.subClipX, w.subClipY, w.subClipW, w.subClipH);
        // gl_start() drawing is redone whole at each repaint
        bool clipped = w.hasDamageRegion && w.glStart is null;
        if (clipped) fldraw.pushClip(w.damageX, w.damageY, w.damageW, w.damageH);
        eglDriver.glStartRepaintBegins(w);
        win.draw();
        eglDriver.presentGlStart(w);
        if (clipped) fldraw.popClip();
        if (subClipped) fldraw.popClip();
        applyShape(w);
        win.clearDamage();
        w.hasDamageRegion = false;
        w.fullRepaintPending = false;
        w.buffer.needsCommit = true;
    }
    if (overlayWin !is null && overlayWin.overlayActive() && w.buffer !is null
        && (drewWindow || overlayDirty || w.buffer.overlayCr is null))
        drawOverlayOf(w, overlayWin);
    if (w.buffer !is null && w.buffer.needsCommit && w.frameCb is null) commit(w);
}

/// Whether GL window `w` has a frame not yet shown, before which it isn't
/// drawn again.
private bool glWaitsForFrame(WldWindow w)
{
    return w.frameCb !is null && w.eglSurface !is null && eglDriver.pacedByFrames()
        && w.widget.asGlWindow() !is null;
}

/// Whether a GL window needs drawing but waits for its last frame to be
/// shown.
private bool glWindowWaitingForFrame()
{
    foreach (w; windows_)
        if (w.widget.damage() && w.widget.visible() && glWaitsForFrame(w)) return true;
    return false;
}

/// Repaints every shown window with pending damage -- `Fl::flush()`.
package(fl) void flushDamage()
{
    if (display_ is null) return;
    foreach (w; windows_.dup)
    {
        if (w.widget.damage() && w.widget.visible()) flushWindow(w);
        else if (w.buffer !is null && w.buffer.needsCommit && w.frameCb is null && w.configuredW) commit(w);
    }
    wl_display_flush(display_);
}

// -- event loop ---------------------------------------------------------

/// Runs until every window is closed -- `Fl::run()`.
void run()
{
    while (windows_.length) wait();
}

/// One iteration of the event loop, blocking until something happens
/// -- `Fl::wait()`. The same steps as `fl.platform_x11.wait()`, with the
/// Wayland socket among `fl.core.addFd()`'s descriptors.
void wait()
{
    iteration();
    if (windows_.length) waitForEventOrTimeout();
}

/// ditto, blocking at most `timeToWait` seconds -- `Fl::wait(double)`.
double wait(double timeToWait)
{
    iteration();
    if (!windows_.length) return 0.0;
    import core.time : dur;
    long us = cast(long)(timeToWait * 1_000_000.0);
    if (us < 0) us = 0;
    return waitForEventOrTimeout(dur!"usecs"(us)) ? 1.0 : 0.0;
}

/// One iteration that doesn't block -- `Fl::check()`.
bool check()
{
    iteration();
    if (windows_.length) dispatchEvents(0);
    rethrowPending();
    return windows_.length != 0;
}

private void iteration()
{
    doWidgetDeletion();
    processTimeouts();
    runChecks();
    runIdle();
    flushDamage();
    if (opened_) dispatchEvents(0); // events already read
    rethrowPending();
}

import core.time : Duration;

private bool waitForEventOrTimeout(Duration maxWait = Duration.max)
{
    import core.sys.posix.sys.select : select, fd_set, FD_ZERO, FD_SET, FD_ISSET;
    import core.sys.posix.sys.time : timeval;
    import core.time : hours;
    import fl.enumerations : FdWhen, fdRead, fdWrite, fdExcept;

    import core.time : msecs;
    // With idle callbacks the loop doesn't wait -- unless a GL window
    // waits for its last frame to be shown: then it waits for that frame,
    // so a program animating from an idle callback runs at the screen's
    // refresh rate, as a blocking buffer swap makes it on X11. At most
    // 50 ms, since a hidden window gets no frames.
    Duration ttw = !idleActive() ? timeToWait(hours(24))
        : glWindowWaitingForFrame() ? timeToWait(msecs(50))
        : Duration.zero;
    if (ttw < Duration.zero) ttw = Duration.zero;
    if (maxWait < ttw) ttw = maxWait;

    wl_display_flush(display_);

    fd_set rfds, wfds, efds;
    FD_ZERO(&rfds);
    FD_ZERO(&wfds);
    FD_ZERO(&efds);
    int maxfd = -1;
    auto entries = fdEntries();
    foreach (ref e; entries)
    {
        if (e.when & fdRead) FD_SET(e.fd, &rfds);
        if (e.when & fdWrite) FD_SET(e.fd, &wfds);
        if (e.when & fdExcept) FD_SET(e.fd, &efds);
        if (e.fd > maxfd) maxfd = e.fd;
    }
    long us = ttw.total!"usecs";
    timeval tv;
    tv.tv_sec = cast(typeof(tv.tv_sec))(us / 1_000_000);
    tv.tv_usec = cast(typeof(tv.tv_usec))(us % 1_000_000);

    unlockForWait();
    int n = select(maxfd + 1, &rfds, &wfds, &efds, &tv);
    lockForWait();
    if (n <= 0) return false;
    foreach (ref e; entries)
    {
        FdWhen revents = 0;
        if (FD_ISSET(e.fd, &rfds)) revents |= fdRead;
        if (FD_ISSET(e.fd, &wfds)) revents |= fdWrite;
        if (FD_ISSET(e.fd, &efds)) revents |= fdExcept;
        if (e.when & revents) e.callback(e.fd);
    }
    return true;
}

/// Whether events are waiting to be handled.
package(fl) bool eventsReady()
{
    import core.sys.posix.poll : poll, pollfd, POLLIN;
    if (display_ is null) return false;
    pollfd p = pollfd(wl_display_get_fd(display_), POLLIN, 0);
    return poll(&p, 1, 0) > 0;
}

/// `fl_beep()`: the terminal bell, as FLTK does on Wayland.
/**
 * Rings the desktop's bell -- `Fl::beep()`. Through xdg-system-bell when
 * the compositor offers it, associated with the window that has the
 * keyboard focus, so the compositor can also flash it (beyond FLTK);
 * else, as FLTK does, a BEL character to stderr, which only a terminal
 * running the program turns into a bell. Every `Beep` type rings the
 * same bell.
 */
void beep(Beep type)
{
    if (systemBell_ !is null)
    {
        xdg_system_bell_v1_ring(systemBell_, keyboardSurface_);
        wl_display_flush(display_);
        return;
    }
    import core.stdc.stdio : fputs, stderr;
    fputs("\007", stderr);
}

// -- input --------------------------------------------------------------

private __gshared wl_seat* seat_;
private __gshared wl_pointer* pointer_;
private __gshared wl_keyboard* keyboard_;
private __gshared wp_cursor_shape_device_v1* cursorShapeDevice_;
private __gshared xkb_context* xkbContext_;
private __gshared xkb_keymap* xkbKeymap_;
private __gshared xkb_state* xkbState_;
private __gshared xkb_compose_state* xkbCompose_;

private wl_surface* pointerFocus_;   // the surface under the pointer: a window's, or its frame's
private wl_surface* keyboardSurface_;
private uint serial_;                // of the latest input event
private uint pointerEnterSerial_;    // what wl_pointer_set_cursor() needs
private uint keyboardEnterSerial_;   // what wl_data_device_set_selection() needs
private uint buttonSerial_;          // of the latest button press: what start_drag() needs

/// The window whose surface is `surface`, or null for any other surface
/// (a window's frame, say) -- FLTK's `surface_to_window()`.
private WldWindow windowOfSurface(wl_surface* surface)
{
    if (surface is null) return null;
    foreach (w; windows_) if (w.surface is surface) return w;
    return null;
}

/// Creates the xkbcommon context and the compose state for the user's
/// locale -- the keyboard part of FLTK's `registry_handle_global()` for
/// `wl_seat`.
private void initKeyboardContext()
{
    import std.process : environment;
    if (xkbContext_ !is null) return;
    xkbContext_ = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
    if (xkbContext_ is null) return;
    string locale = environment.get("LC_ALL");
    if (locale.length == 0) locale = environment.get("LC_CTYPE");
    if (locale.length == 0) locale = environment.get("LANG");
    if (locale.length == 0) locale = "C";
    xkb_compose_table* table = xkb_compose_table_new_from_locale(xkbContext_, locale.toStringz,
        XKB_COMPOSE_COMPILE_NO_FLAGS);
    if (table !is null)
    {
        xkbCompose_ = xkb_compose_state_new(table, XKB_COMPOSE_STATE_NO_FLAGS);
        xkb_compose_table_unref(table);
    }
}

/// Ported from `seat_capabilities()`.
extern (C) private void seatCapabilities(void* data, wl_seat* seat, uint capabilities) nothrow
{
    guarded({
    if ((capabilities & WL_SEAT_CAPABILITY_POINTER) && pointer_ is null)
    {
        pointer_ = wl_seat_get_pointer(seat);
        wl_pointer_add_listener(pointer_, &pointerListener, null);
        if (cursorShapeManager_ !is null)
            cursorShapeDevice_ = wp_cursor_shape_manager_v1_get_pointer(cursorShapeManager_, pointer_);
        if (pointerGestures_ !is null)
        {
            pinch_ = zwp_pointer_gestures_v1_get_pinch_gesture(pointerGestures_, pointer_);
            zwp_pointer_gesture_pinch_v1_add_listener(pinch_, &pinchListener, null);
            swipe_ = zwp_pointer_gestures_v1_get_swipe_gesture(pointerGestures_, pointer_);
            zwp_pointer_gesture_swipe_v1_add_listener(swipe_, &swipeListener, null);
        }
    }
    else if (!(capabilities & WL_SEAT_CAPABILITY_POINTER) && pointer_ !is null)
    {
        if (cursorShapeDevice_ !is null) wp_cursor_shape_device_v1_destroy(cursorShapeDevice_);
        cursorShapeDevice_ = null;
        if (pinch_ !is null) zwp_pointer_gesture_pinch_v1_destroy(pinch_);
        if (swipe_ !is null) zwp_pointer_gesture_swipe_v1_destroy(swipe_);
        pinch_ = null;
        swipe_ = null;
        wl_pointer_release(pointer_);
        pointer_ = null;
    }
    if ((capabilities & WL_SEAT_CAPABILITY_TOUCH) && touch_ is null)
    {
        touch_ = wl_seat_get_touch(seat);
        wl_touch_add_listener(touch_, &touchListener, null);
    }
    else if (!(capabilities & WL_SEAT_CAPABILITY_TOUCH) && touch_ !is null)
    {
        wl_touch_release(touch_);
        touch_ = null;
    }
    enableIm();
    bool haveKeyboard = xkbContext_ !is null && (capabilities & WL_SEAT_CAPABILITY_KEYBOARD);
    if (haveKeyboard && keyboard_ is null)
    {
        keyboard_ = wl_seat_get_keyboard(seat);
        wl_keyboard_add_listener(keyboard_, &keyboardListener, null);
    }
    else if (!haveKeyboard && keyboard_ !is null)
    {
        wl_keyboard_release(keyboard_);
        keyboard_ = null;
    }
    });
}

extern (C) private void seatName(void* data, wl_seat* seat, const(char)* name) nothrow { }

private __gshared wl_seat_listener seatListener = {
    capabilities: &seatCapabilities,
    name: &seatName,
};

// ---- touchscreen (wl_touch) and touchpad gestures (pointer-gestures):
// see fl.touch, which turns them into mouse and gesture events

private __gshared wl_touch* touch_;
private __gshared zwp_pointer_gestures_v1* pointerGestures_;
private __gshared zwp_pointer_gesture_pinch_v1* pinch_;
private __gshared zwp_pointer_gesture_swipe_v1* swipe_;

private wl_surface*[int] touchSurfaces_; // the surface each finger landed on
private bool[int] frameTouches_;         // fingers on a window's frame (fldtk's title bar)

/// The toplevel window of `surface` and the position `(sx, sy)` on it in
/// that window's FLTK units, as for the pointer.
private FlWindow touchCoords(wl_surface* surface, wl_fixed_t sx, wl_fixed_t sy, out double x, out double y)
{
    auto w = windowOfSurface(surface);
    if (w is null) return null;
    FlWindow win = w.widget;
    int dx = 0, dy = 0;
    while (win.parent !is null && win.window() !is null)
    {
        dx += win.x();
        dy += win.y();
        win = win.window();
    }
    float f = screenScale(win.screenNum());
    x = wl_fixed_to_double(sx) / f + dx;
    y = wl_fixed_to_double(sy) / f + dy;
    return win;
}

extern (C) private void touchDownCb(void* data, wl_touch* t, uint serial, uint time, wl_surface* surface,
    int id, wl_fixed_t sx, wl_fixed_t sy) nothrow
{
    guarded({
    serial_ = serial;
    // a finger on fldtk's title bar works it as the pen does
    if (penOnFrame(surface, sx, sy, true, false, false, serial, time))
    {
        frameTouches_[id] = true;
        touchSurfaces_[id] = surface;
        return;
    }
    double x, y;
    FlWindow top = touchCoords(surface, sx, sy, x, y);
    if (top is null) return;
    touchSurfaces_[id] = surface;
    touchEngine.touchDown(top, id, x, y);
    });
}

extern (C) private void touchUpCb(void* data, wl_touch* t, uint serial, uint time, int id) nothrow
{
    guarded({
    serial_ = serial;
    auto surface = touchSurfaces_.get(id, null);
    touchSurfaces_.remove(id);
    if (id in frameTouches_)
    {
        frameTouches_.remove(id);
        penOnFrame(surface, framePointerX_ << 8, framePointerY_ << 8, false, true, false, serial, time);
        penOnFrame(surface, 0, 0, false, false, true, serial, time);
        return;
    }
    touchEngine.touchUp(id);
    });
}

extern (C) private void touchMotionCb(void* data, wl_touch* t, uint time, int id, wl_fixed_t sx, wl_fixed_t sy) nothrow
{
    guarded({
    if (id in frameTouches_) return; // the compositor moves or resizes the window
    auto surface = touchSurfaces_.get(id, null);
    double x, y;
    if (surface is null || touchCoords(surface, sx, sy, x, y) is null) return;
    touchEngine.touchMotion(id, x, y);
    });
}

extern (C) private void touchFrameCb(void* data, wl_touch* t) nothrow
{
    guarded({ touchEngine.touchFrame(); });
}

extern (C) private void touchCancelCb(void* data, wl_touch* t) nothrow
{
    guarded({
    touchSurfaces_ = null;
    frameTouches_ = null;
    touchEngine.touchCancel();
    });
}

extern (C) private void touchShapeCb(void* data, wl_touch* t, int id, wl_fixed_t major, wl_fixed_t minor) nothrow { }
extern (C) private void touchOrientationCb(void* data, wl_touch* t, int id, wl_fixed_t orientation) nothrow { }

private __gshared wl_touch_listener touchListener = {
    down: &touchDownCb,
    up: &touchUpCb,
    motion: &touchMotionCb,
    frame: &touchFrameCb,
    cancel: &touchCancelCb,
    shape: &touchShapeCb,
    orientation: &touchOrientationCb,
};

// a touchpad pinch: zoom and rotate gestures where the pointer is
private FlWindow gestureWin_;
private int gestureX_, gestureY_, gestureFingers_;
private double pinchScale_ = 1;
private bool pinchZoomed_, pinchRotated_;
private double swipeDx_ = 0, swipeDy_ = 0; // swipe movement not yet sent (fractions)

/// Where a touchpad gesture over `surface` happens: its toplevel window
/// and the pointer's position there.
private bool beginTouchpadGesture(wl_surface* surface, uint fingers)
{
    auto w = windowOfSurface(surface);
    gestureWin_ = w !is null ? w.widget.topWindow() : null;
    gestureX_ = eX_;
    gestureY_ = eY_;
    gestureFingers_ = cast(int) fingers;
    return gestureWin_ !is null;
}

extern (C) private void pinchBegin(void* data, zwp_pointer_gesture_pinch_v1* p, uint serial, uint time,
    wl_surface* surface, uint fingers) nothrow
{
    guarded({
    beginTouchpadGesture(surface, fingers);
    pinchScale_ = 1;
    pinchZoomed_ = pinchRotated_ = false;
    });
}

extern (C) private void pinchUpdate(void* data, zwp_pointer_gesture_pinch_v1* p, uint time, wl_fixed_t dx,
    wl_fixed_t dy, wl_fixed_t scale, wl_fixed_t rotation) nothrow
{
    guarded({
    import fl.enumerations : GesturePhase;
    if (gestureWin_ is null) return;
    double s = wl_fixed_to_double(scale), r = wl_fixed_to_double(rotation);
    if (s > 0 && s != pinchScale_)
    {
        touchEngine.sendGesture(Event.zoomGesture, gestureWin_, gestureX_, gestureY_,
            pinchZoomed_ ? GesturePhase.update : GesturePhase.begin, gestureFingers_, cast(float)(s / pinchScale_));
        pinchScale_ = s;
        pinchZoomed_ = true;
    }
    if (r != 0)
    {
        touchEngine.sendGesture(Event.rotateGesture, gestureWin_, gestureX_, gestureY_,
            pinchRotated_ ? GesturePhase.update : GesturePhase.begin, gestureFingers_, 1, cast(float) r);
        pinchRotated_ = true;
    }
    });
}

extern (C) private void pinchEnd(void* data, zwp_pointer_gesture_pinch_v1* p, uint serial, uint time, int cancelled) nothrow
{
    guarded({
    import fl.enumerations : GesturePhase;
    if (gestureWin_ is null) return;
    auto phase = cancelled ? GesturePhase.cancel : GesturePhase.end;
    if (pinchZoomed_)
        touchEngine.sendGesture(Event.zoomGesture, gestureWin_, gestureX_, gestureY_, phase, gestureFingers_, 1);
    if (pinchRotated_)
        touchEngine.sendGesture(Event.rotateGesture, gestureWin_, gestureX_, gestureY_, phase, gestureFingers_, 1, 0);
    gestureWin_ = null;
    });
}

private __gshared zwp_pointer_gesture_pinch_v1_listener pinchListener = {
    begin: &pinchBegin,
    update: &pinchUpdate,
    end: &pinchEnd,
};

extern (C) private void swipeBegin(void* data, zwp_pointer_gesture_swipe_v1* p, uint serial, uint time,
    wl_surface* surface, uint fingers) nothrow
{
    guarded({
    import fl.enumerations : GesturePhase;
    swipeDx_ = swipeDy_ = 0;
    if (beginTouchpadGesture(surface, fingers))
        touchEngine.sendGesture(Event.swipeGesture, gestureWin_, gestureX_, gestureY_, GesturePhase.begin,
            gestureFingers_);
    });
}

extern (C) private void swipeUpdate(void* data, zwp_pointer_gesture_swipe_v1* p, uint time, wl_fixed_t dx, wl_fixed_t dy) nothrow
{
    guarded({
    import fl.enumerations : GesturePhase;
    import std.math : trunc;
    if (gestureWin_ is null) return;
    float f = screenScale(gestureWin_.screenNum());
    swipeDx_ += wl_fixed_to_double(dx) / f;
    swipeDy_ += wl_fixed_to_double(dy) / f;
    int ix = cast(int) trunc(swipeDx_), iy = cast(int) trunc(swipeDy_);
    if (ix == 0 && iy == 0) return;
    swipeDx_ -= ix;
    swipeDy_ -= iy;
    touchEngine.sendGesture(Event.swipeGesture, gestureWin_, gestureX_, gestureY_, GesturePhase.update,
        gestureFingers_, 1, 0, ix, iy);
    });
}

extern (C) private void swipeEnd(void* data, zwp_pointer_gesture_swipe_v1* p, uint serial, uint time, int cancelled) nothrow
{
    guarded({
    import fl.enumerations : GesturePhase;
    if (gestureWin_ is null) return;
    touchEngine.sendGesture(Event.swipeGesture, gestureWin_, gestureX_, gestureY_,
        cancelled ? GesturePhase.cancel : GesturePhase.end, gestureFingers_);
    gestureWin_ = null;
    });
}

private __gshared zwp_pointer_gesture_swipe_v1_listener swipeListener = {
    begin: &swipeBegin,
    update: &swipeUpdate,
    end: &swipeEnd,
};

// ---- pointer

private int px_, py_;          // where the last click was (FLTK units)
private uint ptime_;           // when it was
private uint eventTime_;       // time of the latest event
private Keysym lastClickKeysym_;

/// Turns off "is a click" once the pointer has moved or waited too long
/// since the last press -- FLTK's `set_event_xy()`.
private void setEventXY()
{
    import std.math : abs;
    if (abs(eXRoot_ - px_) + abs(eYRoot_ - py_) > 3 || eventTime_ >= ptime_ + 1000)
        eIsClick_ = false;
}

/// Counts repeated clicks of the same button -- FLTK's `checkdouble()`.
private void checkDouble()
{
    if (eIsClick_ && lastClickKeysym_ == eKeysym_)
        eClicks_++;
    else
        eClicks_ = 0;
    lastClickKeysym_ = eKeysym_;
    eIsClick_ = true;
    px_ = eXRoot_;
    py_ = eYRoot_;
    ptime_ = eventTime_;
}

/// Sets the event coordinates from a position on `surface` and returns
/// its window -- FLTK's `event_coords_from_surface()`. A toplevel window
/// is at (0, 0), so the "root" coordinates are window coordinates too.
private FlWindow eventCoordsFromSurface(wl_surface* surface, wl_fixed_t sx, wl_fixed_t sy)
{
    auto w = windowOfSurface(surface);
    if (w is null) return null;
    // a subwindow's event goes to its toplevel, in its coordinates, as on X11
    FlWindow win = w.widget;
    int dx = 0, dy = 0;
    while (win.parent !is null && win.window() !is null)
    {
        dx += win.x();
        dy += win.y();
        win = win.window();
    }
    float f = screenScale(win.screenNum());
    eX_ = cast(int)(wl_fixed_to_int(sx) / f) + dx;
    eY_ = cast(int)(wl_fixed_to_int(sy) / f) + dy;
    eXRoot_ = eX_ + win.x();
    eYRoot_ = eY_ + win.y();
    return win;
}

private FlWindow needLeave_;

/// Ported from `pointer_enter()`.
extern (C) private void pointerEnter(void* data, wl_pointer* pointer, uint serial,
    wl_surface* surface, wl_fixed_t sx, wl_fixed_t sy) nothrow
{
    guarded({
    if (auto fw = frameOwner(surface))
    {
        pointerFocus_ = surface;
        serial_ = serial;
        pointerEnterSerial_ = serial;
        framePointerAt(fw, sx, sy, true);
        return;
    }
    FlWindow win = eventCoordsFromSurface(surface, sx, sy);
    if (win is null) return;
    pointerFocus_ = surface;
    serial_ = serial;
    pointerEnterSerial_ = serial;
    applyWindowCursor(find(win));
    checkDouble();
    setEventXY();
    needLeave_ = null;
    if (windowOfSurface(surface).kind != Kind.subwindow) dispatch(Event.enter, win);
    });
}

/// Ported from `pointer_leave()`: a roundtrip lets the pointer's entry
/// into another of the program's windows arrive first, so leaving one
/// window for another sends no `Event.leave`.
extern (C) private void pointerLeave(void* data, wl_pointer* pointer, uint serial, wl_surface* surface) nothrow
{
    guarded({
    if (pointerFocus_ is surface) pointerFocus_ = null;
    if (auto fw = frameOwner(surface))
    {
        framePointerLeft(fw);
        return;
    }
    auto w = windowOfSurface(surface);
    if (w is null) return;
    setEventXY();
    needLeave_ = w.widget.topWindow();
    wl_display_roundtrip(display_);
    if (needLeave_ !is null)
    {
        FlWindow win = needLeave_;
        needLeave_ = null;
        dispatch(Event.leave, win);
    }
    });
}

/// Ported from `pointer_motion()`.
extern (C) private void pointerMotion(void* data, wl_pointer* pointer, uint time,
    wl_fixed_t sx, wl_fixed_t sy) nothrow
{
    guarded({
    if (auto fw = frameOwner(pointerFocus_))
    {
        framePointerAt(fw, sx, sy, false);
        return;
    }
    FlWindow win = eventCoordsFromSurface(pointerFocus_, sx, sy);
    if (win is null) return;
    import fl.widget : Widget;
    auto g = grab();
    if (g !is null && g !is win && !(g.flags() & Widget.Flag.menuWindow))
        eXRoot_ = 1_000_000; // outside every window while another one has the grab
    eventTime_ = time;
    setEventXY();
    dispatch(Event.move, win);
    });
}

// linux/input-event-codes.h
private enum uint BTN_LEFT = 0x110, BTN_RIGHT = 0x111, BTN_MIDDLE = 0x112,
    BTN_SIDE = 0x113, BTN_EXTRA = 0x114, BTN_FORWARD = 0x115, BTN_BACK = 0x116;

/// Ported from `pointer_button()`. The buttons are numbered as on X11:
/// 1 left, 2 middle, 3 right, 4 back, 5 forward.
extern (C) private void pointerButton(void* data, wl_pointer* pointer, uint serial, uint time,
    uint btn, uint state) nothrow
{
    guarded({
    serial_ = serial;
    if (auto fw = frameOwner(pointerFocus_))
    {
        frameButton(fw, serial, time, btn, state == WL_POINTER_BUTTON_STATE_PRESSED);
        return;
    }
    auto w = windowOfSurface(pointerFocus_);
    if (w is null) return;
    eventTime_ = time;
    // Numbered as fldtk numbers them on X11, where Xwayland makes
    // BTN_SIDE button 8, BTN_EXTRA 9 and the next codes 10, 11, ...;
    // fldtk's X11 backend turns 8 and 9 into 4 and 5 and passes the
    // others on. (FLTK on Wayland makes BTN_BACK 4 and BTN_FORWARD 5 too,
    // and ignores the rest.)
    int b;
    switch (btn)
    {
        case BTN_LEFT: b = 1; break;
        case BTN_MIDDLE: b = 2; break;
        case BTN_RIGHT: b = 3; break;
        case BTN_SIDE: b = 4; break;
        case BTN_EXTRA: b = 5; break;
        default:
            if (btn < BTN_SIDE || btn > 0x11f) return;
            b = 8 + cast(int)(btn - BTN_SIDE);
            break;
    }
    bool pressed = state == WL_POINTER_BUTTON_STATE_PRESSED;
    if (pressed) buttonSerial_ = serial;
    // the held-buttons state has room for buttons 1-5 only, as on X11
    if (b <= 5)
    {
        if (pressed) eState_ |= stateButton1 << (b - 1);
        else eState_ &= ~(stateButton1 << (b - 1));
    }
    eKeysym_ = button + b;
    eDx_ = eDy_ = 0;
    setEventXY();
    FlWindow top = w.widget.topWindow();
    if (pressed)
    {
        checkDouble();
        dispatch(Event.push, top);
    }
    else
        dispatch(Event.release, top);
    });
}

/// Ported from `pointer_axis()`: Wayland gives scroll distances in
/// pixels, about 10 per wheel notch, and FLTK counts lines. With Shift
/// held, vertical scrolling becomes horizontal and the other way round.
extern (C) private void pointerAxis(void* data, wl_pointer* pointer, uint time, uint axis, wl_fixed_t value) nothrow
{
    guarded({
    auto w = windowOfSurface(pointerFocus_);
    if (w is null) return;
    eventTime_ = time;
    float delta = cast(float) wl_fixed_to_double(value) / 10.0f;
    bool horizontal = axis == WL_POINTER_AXIS_HORIZONTAL_SCROLL;
    if ((eState_ & stateShift) != 0) horizontal = !horizontal;
    if (horizontal) setWheelDelta(delta, 0);
    else setWheelDelta(0, delta);
    dispatch(Event.mouseWheel, w.widget.topWindow());
    });
}

extern (C) private void pointerFrame(void* data, wl_pointer* pointer) nothrow { }
extern (C) private void pointerAxisSource(void* data, wl_pointer* pointer, uint source) nothrow { }
extern (C) private void pointerAxisStop(void* data, wl_pointer* pointer, uint time, uint axis) nothrow { }
extern (C) private void pointerAxisDiscrete(void* data, wl_pointer* pointer, uint axis, int discrete) nothrow { }
extern (C) private void pointerAxisValue120(void* data, wl_pointer* pointer, uint axis, int value120) nothrow { }
extern (C) private void pointerAxisRelativeDirection(void* data, wl_pointer* pointer, uint axis, uint direction) nothrow { }

private __gshared wl_pointer_listener pointerListener = {
    enter: &pointerEnter,
    leave: &pointerLeave,
    motion: &pointerMotion,
    button: &pointerButton,
    axis: &pointerAxis,
    frame: &pointerFrame,
    axis_source: &pointerAxisSource,
    axis_stop: &pointerAxisStop,
    axis_discrete: &pointerAxisDiscrete,
    axis_value120: &pointerAxisValue120,
    axis_relative_direction: &pointerAxisRelativeDirection,
};

// ---- cursors

private __gshared wl_cursor_theme* cursorTheme_;
private __gshared wl_surface* cursorSurface_;
private int cursorThemeScale_;

/// The cursor-shape protocol's shape for each fldtk cursor (FLTK's
/// `cursor_shape_map`).
private uint shapeOf(CursorShape c)
{
    switch (c)
    {
        case CursorShape.cross: return WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_CROSSHAIR;
        case CursorShape.wait: return WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_WAIT;
        case CursorShape.insert: return WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_TEXT;
        case CursorShape.hand: return WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_GRAB;
        case CursorShape.help: return WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_HELP;
        case CursorShape.move: return WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_MOVE;
        case CursorShape.n: return WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_N_RESIZE;
        case CursorShape.e: return WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_E_RESIZE;
        case CursorShape.w: return WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_W_RESIZE;
        case CursorShape.s: return WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_S_RESIZE;
        case CursorShape.ns: return WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_NS_RESIZE;
        case CursorShape.we: return WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_EW_RESIZE;
        case CursorShape.sw: return WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_SW_RESIZE;
        case CursorShape.se: return WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_SE_RESIZE;
        case CursorShape.ne: return WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_NE_RESIZE;
        case CursorShape.nw: return WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_NW_RESIZE;
        case CursorShape.nesw: return WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_NESW_RESIZE;
        case CursorShape.nwse: return WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_NWSE_RESIZE;
        default: return WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_DEFAULT;
    }
}

/// The cursor theme's file name for each fldtk cursor (FLTK's
/// `cursor_file_array`).
private string themeNameOf(CursorShape c)
{
    switch (c)
    {
        case CursorShape.cross: return "cross";
        case CursorShape.wait: return "watch";
        case CursorShape.insert: return "xterm";
        case CursorShape.hand: return "hand1";
        case CursorShape.help: return "help";
        case CursorShape.move: return "move";
        case CursorShape.n: return "top_side";
        case CursorShape.e: return "right_side";
        case CursorShape.w: return "left_side";
        case CursorShape.s: return "bottom_side";
        case CursorShape.ns: return "sb_v_double_arrow";
        case CursorShape.we: return "sb_h_double_arrow";
        case CursorShape.sw: return "bottom_left_corner";
        case CursorShape.se: return "bottom_right_corner";
        case CursorShape.ne: return "top_right_corner";
        case CursorShape.nw: return "top_left_corner";
        case CursorShape.nesw: return "fd_double_arrow";
        case CursorShape.nwse: return "bd_double_arrow";
        default: return "left_ptr";
    }
}

/**
 * Shows cursor `c` for the pointer -- FLTK's `do_set_cursor()`. With
 * the compositor's cursor-shape protocol the compositor draws it; without
 * it, it comes from the cursor theme named by `XCURSOR_THEME` at the size
 * `XCURSOR_SIZE` (default 24), loaded through libwayland-cursor. FLTK
 * asks its own copy of libdecor for the desktop's theme settings.
 */
private void applyCursor(CursorShape c)
{
    if (pointer_ is null) return;
    if (c == CursorShape.none)
    {
        wl_pointer_set_cursor(pointer_, pointerEnterSerial_, null, 0, 0);
        return;
    }
    if (cursorShapeDevice_ !is null)
    {
        wp_cursor_shape_device_v1_set_shape(cursorShapeDevice_, pointerEnterSerial_, shapeOf(c));
        return;
    }
    int scale = 1;
    foreach (o; outputs_) if (o.wldScale > scale) scale = o.wldScale;
    if (cursorTheme_ is null || cursorThemeScale_ != scale)
    {
        import std.process : environment;
        import std.conv : to, ConvException;
        if (cursorTheme_ !is null) wl_cursor_theme_destroy(cursorTheme_);
        string name = environment.get("XCURSOR_THEME");
        int size = 24;
        try { if (auto v = environment.get("XCURSOR_SIZE")) size = v.to!int; }
        catch (ConvException) { }
        cursorTheme_ = wl_cursor_theme_load(name.length ? name.toStringz : null, size * scale, shm_);
        cursorThemeScale_ = scale;
    }
    if (cursorTheme_ is null) return;
    wl_cursor* cursor = wl_cursor_theme_get_cursor(cursorTheme_, themeNameOf(c).toStringz);
    if (cursor is null) cursor = wl_cursor_theme_get_cursor(cursorTheme_, "left_ptr");
    if (cursor is null || cursor.image_count == 0) return;
    if (cursorSurface_ is null) cursorSurface_ = wl_compositor_create_surface(compositor_);
    wl_cursor_image* image = cursor.images[0];
    wl_pointer_set_cursor(pointer_, pointerEnterSerial_, cursorSurface_,
        image.hotspot_x / scale, image.hotspot_y / scale);
    wl_surface_attach(cursorSurface_, wl_cursor_image_get_buffer(image), 0, 0);
    wl_surface_set_buffer_scale(cursorSurface_, scale);
    wl_surface_damage_buffer(cursorSurface_, 0, 0, image.width, image.height);
    wl_surface_commit(cursorSurface_);
}

/// Shows `w`'s cursor: its image cursor if it has one, else its shape.
private void applyWindowCursor(WldWindow w)
{
    if (w is null) { applyCursor(CursorShape.default_); return; }
    auto img = w.customCursor;
    if (img is null) { applyCursor(w.cursor); return; }
    if (pointer_ is null) return;
    if (cursorSurface_ is null) cursorSurface_ = wl_compositor_create_surface(compositor_);
    wl_pointer_set_cursor(pointer_, pointerEnterSerial_, cursorSurface_, w.cursorHotX, w.cursorHotY);
    wl_surface_attach(cursorSurface_, img.buffer, 0, 0);
    wl_surface_set_buffer_scale(cursorSurface_, w.cursorScale);
    wl_surface_damage_buffer(cursorSurface_, 0, 0, img.w, img.h);
    wl_surface_commit(cursorSurface_);
}

/// Whether the pointer is over `win` or one of its subwindows.
private bool pointerOver(FlWindow win)
{
    auto under = windowOfSurface(pointerFocus_);
    return under !is null && under.widget.topWindow() is win;
}

/// Sets the cursor shown over `win` -- FLTK's `set_cursor(Fl_Cursor)`.
package(fl) void setCursor(FlWindow win, CursorShape c)
{
    auto w = find(win);
    if (w is null) return;
    w.cursor = c;
    if (w.customCursor !is null) { w.customCursor.destroy(); w.customCursor = null; }
    if (pointerOver(win)) applyCursor(c);
}

/**
 * A cursor made from `image`, its hot spot at `(hotx, hoty)` -- FLTK's
 * `set_cursor_4args()`: the image is made at the largest screen scale
 * and shown on the pointer's own surface.
 */
package(fl) bool setCursorImage(FlWindow win, const(RGBImage) image, int hotx, int hoty)
{
    auto w = find(win);
    if (w is null || image is null || image.array.length == 0) return false;
    if (hotx < 0 || hotx >= image.w() || hoty < 0 || hoty >= image.h()) return false;
    int s = cursorImageScale();
    auto img = shmImageFrom(image, image.w() * s, image.h() * s, image.w() * s, image.h() * s, 0, 0);
    if (img is null) return false;
    if (w.customCursor !is null) w.customCursor.destroy();
    w.customCursor = img;
    w.cursorHotX = hotx;
    w.cursorHotY = hoty;
    w.cursorScale = s;
    if (pointerOver(win)) applyWindowCursor(w);
    return true;
}

// ---- keyboard

/// The keys held down, as keysyms (FLTK's `key_vector`).
private Keysym[] keyVector_;

/// Keysym of the Wayland key code `key`, and the value `eventKey()`
/// tracks for it -- FLTK's `process_wld_key()`.
private Keysym processKey(uint key, out uint keycode, out xkb_keysym_t sym)
{
    keycode = key + 8;
    sym = xkbState_ !is null ? xkb_state_key_get_one_sym(xkbState_, keycode) : 0;
    if (sym == 0xfe20) sym = tab;      // ISO_Left_Tab
    if (sym == 0xffeb) sym = metaL;    // repair what libxkbcommon gives for Meta_L
    if (sym == 0xffec) sym = metaR;    // ... and Meta_R
    if (sym >= 'A' && sym <= 'Z') sym += 32;
    Keysym forKeyVector = sym;
    // the number keys of the main block, whatever their shifted symbols
    if (keycode >= 10 && keycode <= 18) forKeyVector = '1' + (keycode - 10);
    else if (keycode == 19) forKeyVector = '0';
    return forKeyVector;
}

private void addKey(Keysym k)
{
    foreach (e; keyVector_) if (e == k) return;
    keyVector_ ~= k;
}

private void removeKey(Keysym k)
{
    foreach (i, e; keyVector_)
        if (e == k) { keyVector_ = keyVector_[0 .. i] ~ keyVector_[i + 1 .. $]; return; }
}

/// Ported from `wl_keyboard_keymap()`.
extern (C) private void keyboardKeymap(void* data, wl_keyboard* keyboard, uint format, int fd, uint size) nothrow
{
    guarded({
    import core.sys.posix.sys.mman : mmap, munmap, PROT_READ, MAP_PRIVATE, MAP_SHARED, MAP_FAILED;
    import core.sys.posix.unistd : close;
    scope (exit) close(fd);
    if (format != WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1) return;
    void* map = mmap(null, size, PROT_READ,
        wl_keyboard_get_version(keyboard) >= 7 ? MAP_PRIVATE : MAP_SHARED, fd, 0);
    if (map == MAP_FAILED) return;
    xkb_keymap* keymap = xkb_keymap_new_from_string(xkbContext_, cast(const(char)*) map,
        XKB_KEYMAP_FORMAT_TEXT_V1, XKB_KEYMAP_COMPILE_NO_FLAGS);
    munmap(map, size);
    if (keymap is null) return;
    if (xkbState_ !is null) xkb_state_unref(xkbState_);
    if (xkbKeymap_ !is null) xkb_keymap_unref(xkbKeymap_);
    xkbKeymap_ = keymap;
    xkbState_ = xkb_state_new(keymap);
    });
}

private uint lastKeyDownSerial_; // 0 when no key is repeating
private double keyRepeatDelay_ = 0.5, keyRepeatInterval_ = 0.05; // seconds

/// Ported from `wl_keyboard_enter()`.
extern (C) private void keyboardEnter(void* data, wl_keyboard* keyboard, uint serial,
    wl_surface* surface, wl_array* keys) nothrow
{
    guarded({
    keyVector_ = null;
    auto held = (cast(uint*) keys.data)[0 .. keys.size / uint.sizeof];
    foreach (k; held)
    {
        uint keycode;
        xkb_keysym_t sym;
        addKey(processKey(k, keycode, sym));
    }
    keyboardSurface_ = surface;
    serial_ = serial;
    keyboardEnterSerial_ = serial;
    lastKeyDownSerial_ = 0;
    auto w = windowOfSurface(surface);
    if (w !is null)
    {
        // As on X11 (FocusIn): FLTK's FL_FOCUS for a window ends in
        // fl_fix_focus(), which gives the focus back to the child that
        // had it. Sending Event.focus to the window itself instead
        // would make it remember itself as that child.
        fixFocus(w.widget);
        makeWindowFirst(w.widget);
    }
    });
}

/// Ported from `wl_keyboard_leave()`.
extern (C) private void keyboardLeave(void* data, wl_keyboard* keyboard, uint serial, wl_surface* surface) nothrow
{
    guarded({
    keyboardSurface_ = null;
    lastKeyDownSerial_ = 0;
    fixFocus(null); // as on X11 (FocusOut): FLTK's FL_UNFOCUS for a window
    keyVector_ = null;
    });
}

/// Sends a repeat of the key pressed with `serial` while it is still
/// held -- FLTK's `key_repeat_timer_cb()`.
private void keyRepeat(uint serial, FlWindow win)
{
    if (lastKeyDownSerial_ != serial || keyRepeatInterval_ <= 0 || !win.shown()) return;
    dispatch(Event.keyDown, win);
    addTimeout(keyRepeatInterval_, () { keyRepeat(serial, win); });
}

/**
 * Ported from `wl_keyboard_key()`, including dead keys and compose
 * sequences when no input method handles them (see below).
 */
extern (C) private void keyboardKey(void* data, wl_keyboard* keyboard, uint serial, uint time,
    uint key, uint state) nothrow
{
    guarded({
    serial_ = serial;
    uint keycode;
    xkb_keysym_t sym;
    Keysym forKeyVector = processKey(key, keycode, sym);
    char[128] buf;
    int n = xkbState_ !is null ? xkb_state_key_get_utf8(xkbState_, keycode, buf.ptr, buf.length) : 0;
    if (n < 0) n = 0;
    if (n >= buf.length) n = cast(int) buf.length - 1;

    eKeysym_ = eOriginalKeysym_ = forKeyVector;
    if (!(eState_ & stateNumLock) && sym >= 0xff95 && sym <= 0xff9f) // KP_Home .. KP_Delete
    {
        // keypad keys with NumLock off
        static immutable Keysym[11] table = [home, left, up, right, down, pageUp, pageDown,
            end, 0xff0b, insert, deleteKey];
        static immutable Keysym[11] tableOriginal = [0xffb7, 0xffb4, 0xffb8, 0xffb6, 0xffb2,
            0xffb9, 0xffb3, 0xffb1, 0xffb5, 0xffb0, 0xffac];
        eKeysym_ = table[sym - 0xff95];
        eOriginalKeysym_ = tableOriginal[sym - 0xff95];
        forKeyVector = eOriginalKeysym_;
    }
    bool pressed = state == WL_KEYBOARD_KEY_STATE_PRESSED;
    if (pressed) addKey(forKeyVector);
    else
    {
        lastKeyDownSerial_ = 0;
        removeKey(forKeyVector);
    }

    string text = buf[0 .. n].idup;
    bool isModifier = sym >= shiftL && sym <= altR;
    int composeStatus = XKB_COMPOSE_NOTHING;
    // Dead keys and compose sequences, when the compositor has no
    // text-input protocol to do it: a dead key shows its accent as
    // marked text, which the composed character then replaces
    // (fl.core.compose()).
    if (xkbCompose_ !is null && pressed && !isModifier && sym != 0xfe03) // not ISO_Level3_Shift
    {
        xkb_compose_state_feed(xkbCompose_, sym);
        composeStatus = xkb_compose_state_get_status(xkbCompose_);
        if (composeStatus == XKB_COMPOSE_COMPOSING)
        {
            if (text.length == 0) // a dead key
            {
                text = deadKeyAccent(sym);
                markComposeState(0);
            }
            nextMarkedLength_ = cast(int) text.length;
        }
        else if (composeStatus == XKB_COMPOSE_COMPOSED)
        {
            int m = xkb_compose_state_get_utf8(xkbCompose_, buf.ptr, buf.length);
            if (m < 0) m = 0;
            if (m >= buf.length) m = cast(int) buf.length - 1;
            text = buf[0 .. m].idup;
            markComposeState(nextMarkedLength_);
            nextMarkedLength_ = 0;
        }
        else if (composeStatus == XKB_COMPOSE_CANCELLED)
        {
            text = "";
            markComposeState(nextMarkedLength_);
            nextMarkedLength_ = 0;
        }
    }
    eText_ = text;

    eventTime_ = time;
    Event event = pressed ? Event.keyDown : Event.keyUp;
    // to the focus widget's window as FLTK sees it, else the one the
    // compositor gave the keyboard to
    FlWindow win = focus() !is null ? focus().topWindow() : null;
    if (win is null)
    {
        auto w = windowOfSurface(keyboardSurface_);
        if (w !is null) win = w.widget;
    }
    if (pressed && composeStatus == XKB_COMPOSE_NOTHING && !isModifier && win !is null)
    {
        // Repeats are detected by serial: it changes with every key press
        // and release on every compositor FLTK was tried with.
        lastKeyDownSerial_ = serial;
        FlWindow target = win;
        addTimeout(keyRepeatDelay_, () { keyRepeat(serial, target); });
    }
    if (win !is null)
    {
        setEventXY();
        eIsClick_ = false;
        dispatch(event, win);
    }
    });
}

/// Ported from `wl_keyboard_modifiers()`.
extern (C) private void keyboardModifiers(void* data, wl_keyboard* keyboard, uint serial,
    uint depressed, uint latched, uint locked, uint group) nothrow
{
    guarded({
    if (xkbState_ is null) return;
    xkb_state_update_mask(xkbState_, depressed, latched, locked, 0, 0, group);
    eState_ &= ~(stateShift | stateCtrl | stateAlt | stateMeta | stateCapsLock | stateNumLock);
    bool active(string name, int type) { return xkb_state_mod_name_is_active(xkbState_, name.ptr, type) > 0; }
    if (active(XKB_MOD_NAME_SHIFT, XKB_STATE_MODS_DEPRESSED)) eState_ |= stateShift;
    if (active(XKB_MOD_NAME_CTRL, XKB_STATE_MODS_DEPRESSED)) eState_ |= stateCtrl;
    if (active(XKB_MOD_NAME_ALT, XKB_STATE_MODS_DEPRESSED)) eState_ |= stateAlt;
    if (active(XKB_MOD_NAME_LOGO, XKB_STATE_MODS_DEPRESSED)) eState_ |= stateMeta;
    if (active(XKB_MOD_NAME_CAPS, XKB_STATE_MODS_LOCKED)) eState_ |= stateCapsLock;
    if (active(XKB_MOD_NAME_NUM, XKB_STATE_MODS_LOCKED)) eState_ |= stateNumLock;
    });
}

/// Ported from `wl_keyboard_repeat_info()`.
extern (C) private void keyboardRepeatInfo(void* data, wl_keyboard* keyboard, int rate, int delay) nothrow
{
    guarded({
    keyRepeatDelay_ = delay / 1000.0;
    keyRepeatInterval_ = rate > 0 ? 1.0 / rate : 0;
    });
}

private __gshared wl_keyboard_listener keyboardListener = {
    keymap: &keyboardKeymap,
    enter: &keyboardEnter,
    leave: &keyboardLeave,
    key: &keyboardKey,
    modifiers: &keyboardModifiers,
    repeat_info: &keyboardRepeatInfo,
};

/// Whether key `k` was held during the latest event; for a mouse button
/// (`button + n`), whether that button was.
package(fl) bool eventKey(Keysym k)
{
    if (k > button && k <= button + 8)
        return (eState_ & (stateButton1 << (k - button - 1))) != 0;
    foreach (e; keyVector_) if (e == k) return true;
    return false;
}

/// Whether key `k` is held now: what the latest keyboard events say, as
/// in FLTK on Wayland, which can't ask the compositor.
package(fl) bool getKey(Keysym k) { return eventKey(k); }

/// The name of key `key`: fldtk's key codes are X keysyms, named by
/// libX11's table, which needs no X connection.
string keyName(uint key)
{
    import platformX11 = fl.platform_x11;
    return platformX11.keyName(key);
}

/// Wayland doesn't tell a client where the pointer is outside its
/// windows: the position of the latest pointer event in its window, and
/// that window's screen.
package(fl) int getMouse(out int x, out int y)
{
    x = eXRoot_;
    y = eYRoot_;
    auto w = windowOfSurface(pointerFocus_);
    return w !is null ? w.widget.screenNum() : 0;
}

/// A grab only changes where `fl.core` sends events on Wayland; the
/// compositor has no pointer grab for ordinary windows.
package(fl) void grabPointer(FlWindow win) { }
/// ditto
package(fl) void ungrabPointer() { }

// ---- text input methods (text-input-v3)
//
// Ported from FLTK's text-input-unstable-v3 support: with an input
// method (IBus, Fcitx), the compositor sends the text being composed as
// a preedit string, shown as marked text that the next one replaces,
// and the finished text as a commit string. fldtk reports where the
// text cursor is (setSpot()), so the input method's candidate window
// opens there.

private __gshared zwp_text_input_manager_v3* textInputManager_;
private __gshared zwp_text_input_v3* textInput_;
private wl_surface* textInputSurface_;  // the surface it is enabled on
private uint textInputCommits_;          // what done() events must match
private string currentPreedit_, pendingPreedit_, pendingCommit_;
private bool havePendingPreedit_, havePendingCommit_;
private int nextMarkedLength_;           // see fl.core.compose()

/// The length of the marked text just sent, for `fl.core.compose()`.
package(fl) int nextMarkedLength() { return nextMarkedLength_; }

/// The accent a dead key shows while it waits for its letter (FLTK's
/// `dead_keys` table).
private string deadKeyAccent(xkb_keysym_t sym)
{
    switch (sym)
    {
        case 0xfe50: return "`";   // dead_grave
        case 0xfe51: return "´";   // dead_acute
        case 0xfe52: return "^";   // dead_circumflex
        case 0xfe53: return "~";   // dead_tilde
        case 0xfe54: return "¯";   // dead_macron
        case 0xfe55: return "˘";   // dead_breve
        case 0xfe56: return "˙";   // dead_abovedot
        case 0xfe57: return "¨";   // dead_diaeresis
        case 0xfe58: return "˚";   // dead_abovering
        case 0xfe59: return "˝";   // dead_doubleacute
        case 0xfe5a: return "ˇ";   // dead_caron
        case 0xfe5b: return "¸";   // dead_cedilla
        case 0xfe5c: return "˛";   // dead_ogonek
        case 0xfe5d: return "ι";   // dead_iota
        case 0xfe66: return " ̏";  // dead_doublegrave
        default: return "";
    }
}

private void textInputCommit()
{
    zwp_text_input_v3_commit(textInput_);
    textInputCommits_++;
}

/// Creates the text input object once the seat and the manager are
/// known -- FLTK's `enable_im()`.
private void enableIm()
{
    if (textInputManager_ is null || seat_ is null || textInput_ !is null) return;
    textInput_ = zwp_text_input_manager_v3_get_text_input(textInputManager_, seat_);
    zwp_text_input_v3_add_listener(textInput_, &textInputListener, null);
}

private bool cursorKnown_;
private int cursorX_, cursorY_, cursorW_, cursorH_; // surface coordinates
private int lastSpotX_ = int.min, lastSpotY_, lastSpotH_;

/// Tells the input method where the text cursor is -- FLTK's
/// `insertion_point_location()`. `(x, y)` is the cursor's baseline in
/// the focus widget's window, `height` its height.
package(fl) void setSpot(int font, int height, int X, int Y, int W, int H)
{
    if (textInput_ is null) return;
    if (X == lastSpotX_ && Y == lastSpotY_ && height == lastSpotH_) return;
    lastSpotX_ = X;
    lastSpotY_ = Y;
    lastSpotH_ = height;
    int x = X, y = Y;
    FlWindow top;
    if (auto fw = focus())
    {
        auto win = fw.window();
        while (win !is null && win.parent !is null)
        {
            x += win.x();
            y += win.y();
            win = win.window();
        }
        top = win;
    }
    float s = top !is null ? screenScale(top.screenNum()) : screenScale(0);
    cursorKnown_ = true;
    cursorX_ = cast(int)(s * x);
    cursorY_ = cast(int)(s * (y - height));
    cursorW_ = cast(int)(s * 5);
    cursorH_ = cast(int)(s * height);
    if (textInputSurface_ !is null)
    {
        zwp_text_input_v3_set_cursor_rectangle(textInput_, cursorX_, cursorY_, cursorW_, cursorH_);
        textInputCommit();
    }
}

/// FLTK's `reset_spot()` does nothing on Wayland.
package(fl) void resetSpot() { }

/// Ported from `text_input_enter()`: the text input follows the
/// keyboard focus to one of our surfaces.
extern (C) private void textInputEnter(void* data, zwp_text_input_v3* ti, wl_surface* surface) nothrow
{
    guarded({
    textInputSurface_ = surface;
    zwp_text_input_v3_enable(ti);
    zwp_text_input_v3_set_content_type(ti, ZWP_TEXT_INPUT_V3_CONTENT_HINT_NONE,
        ZWP_TEXT_INPUT_V3_CONTENT_PURPOSE_NORMAL);
    if (cursorKnown_) zwp_text_input_v3_set_cursor_rectangle(ti, cursorX_, cursorY_, cursorW_, cursorH_);
    textInputCommit();
    });
}

/// Ported from `text_input_leave()`.
extern (C) private void textInputLeave(void* data, zwp_text_input_v3* ti, wl_surface* surface) nothrow
{
    guarded({
    zwp_text_input_v3_disable(ti);
    textInputSurface_ = null;
    textInputCommit();
    currentPreedit_ = pendingPreedit_ = pendingCommit_ = null;
    havePendingPreedit_ = havePendingCommit_ = false;
    });
}

extern (C) private void textInputPreedit(void* data, zwp_text_input_v3* ti, const(char)* text,
    int cursorBegin, int cursorEnd) nothrow
{
    guarded({
    pendingPreedit_ = text !is null ? fromStringz(text).idup : null;
    havePendingPreedit_ = true;
    });
}

extern (C) private void textInputCommitString(void* data, zwp_text_input_v3* ti, const(char)* text) nothrow
{
    guarded({
    pendingCommit_ = text !is null ? fromStringz(text).idup : null;
    havePendingCommit_ = true;
    });
}

extern (C) private void textInputDeleteSurrounding(void* data, zwp_text_input_v3* ti,
    uint before, uint after) nothrow { }

/// Sends `text` to the focus widget as typed text -- FLTK's
/// `send_text_to_fltk()`: marked (provisional) text when `marked`.
private void sendTextToWidgets(string text, bool marked)
{
    auto w = windowOfSurface(textInputSurface_);
    FlWindow win = focus() !is null ? focus().topWindow() : (w !is null ? w.widget.topWindow() : null);
    if (win is null) return;
    eText_ = text;
    eKeysym_ = 'a'; // a plain key
    setEventXY();
    eIsClick_ = false;
    nextMarkedLength_ = marked ? cast(int) text.length : 0;
    dispatch(Event.keyDown, win);
    if (!marked && text.length) markComposeState(0);
}

/// Ported from `text_input_done()`: applies the preedit and commit
/// strings received since the last `done`. A preedit that answers an
/// older request than our latest one is shown as plain text.
extern (C) private void textInputDone(void* data, zwp_text_input_v3* ti, uint serial) nothrow
{
    guarded({
    bool current = serial == textInputCommits_;
    if (havePendingPreedit_ && pendingPreedit_ != currentPreedit_)
    {
        currentPreedit_ = pendingPreedit_;
        sendTextToWidgets(currentPreedit_, current && currentPreedit_.length);
    }
    havePendingPreedit_ = false;
    pendingPreedit_ = null;
    if (havePendingCommit_ && pendingCommit_ !is null)
        sendTextToWidgets(pendingCommit_, false);
    havePendingCommit_ = false;
    pendingCommit_ = null;
    });
}

private __gshared zwp_text_input_v3_listener textInputListener = {
    enter: &textInputEnter,
    leave: &textInputLeave,
    preedit_string: &textInputPreedit,
    commit_string: &textInputCommitString,
    delete_surrounding_text: &textInputDeleteSurrounding,
    done: &textInputDone,
};
/// Abandons a dead key or compose sequence in progress --
/// FLTK's `compose_reset()`.
package(fl) void resetIC()
{
    nextMarkedLength_ = 0;
    if (xkbCompose_ !is null) xkb_compose_state_reset(xkbCompose_);
}

// -- clipboard and drag and drop -----------------------------------------
//
// Ported from FLTK's fl_wayland_clipboard_dnd.cxx. Other programs offer
// data as a wl_data_offer listing its MIME types; it is read through a
// pipe. fldtk offers its own through a wl_data_source, written to the
// pipe the reader passes. The selection buffer (clipboard 0, pasted with
// the middle button) goes through the primary-selection protocol.

private __gshared wl_data_device_manager* dataDeviceManager_;
private __gshared wl_data_device* dataDevice_;
private __gshared zwp_primary_selection_device_manager_v1* primaryManager_;
private __gshared zwp_primary_selection_device_v1* primaryDevice_;

private wl_data_source* dataSource_;               // our clipboard, while we own it
private zwp_primary_selection_source_v1* primarySource_;
private wl_data_offer* selectionOffer_;            // the clipboard of another program
private zwp_primary_selection_offer_v1* primaryOffer_;

/// The MIME type Wayland uses for text.
private enum plainTextMime = "text/plain;charset=utf-8";

/// The best MIME type an offer has for text and for an image, by FLTK's
/// priorities (`clipboard_mimetypes_map`).
private struct OfferTypes
{
    string text, image;
    int textPrio, imagePrio;
}
private OfferTypes[void*] offerTypes_;

private void noteOfferType(void* offer, string mime)
{
    int textPrio = mime == plainTextMime || mime == "text/plain" ? 3
        : mime == "UTF8_STRING" ? 2 : mime == "text/uri-list" ? 1 : 0;
    int imagePrio = mime == "image/bmp" ? 2 : mime == "image/png" ? 1 : 0;
    auto t = offer in offerTypes_;
    if (t is null) { offerTypes_[offer] = OfferTypes.init; t = offer in offerTypes_; }
    if (textPrio > t.textPrio) { t.textPrio = textPrio; t.text = mime; }
    if (imagePrio > t.imagePrio) { t.imagePrio = imagePrio; t.image = mime; }
}

/// Creates the data devices once the seat and the managers are known.
private void initDataDevices()
{
    if (seat_ is null) return;
    enableIm();
    if (dataDeviceManager_ !is null && dataDevice_ is null)
    {
        dataDevice_ = wl_data_device_manager_get_data_device(dataDeviceManager_, seat_);
        wl_data_device_add_listener(dataDevice_, &dataDeviceListener, null);
    }
    if (primaryManager_ !is null && primaryDevice_ is null)
    {
        primaryDevice_ = zwp_primary_selection_device_manager_v1_get_device(primaryManager_, seat_);
        zwp_primary_selection_device_v1_add_listener(primaryDevice_, &primaryDeviceListener, null);
    }
}

// ---- reading what another program offers

/// Reads everything `receive` sends through a pipe -- FLTK's
/// `get_clipboard_or_dragged_text()` and `get_clipboard_image()`: the
/// request is flushed to the compositor and the pipe read to its end.
private ubyte[] readOffer(scope void delegate(int fd) receive)
{
    import core.sys.posix.unistd : pipe, read, close;
    int[2] fds;
    if (pipe(fds) != 0) return null;
    receive(fds[1]);
    close(fds[1]);
    wl_display_flush(display_);
    ubyte[] data;
    ubyte[4096] buf;
    for (;;)
    {
        auto n = read(fds[0], buf.ptr, buf.length);
        if (n <= 0) break;
        data ~= buf[0 .. n];
    }
    close(fds[0]);
    return data;
}

/// The text of `offer` as `mime`; a `text/uri-list` (files dragged from a
/// file manager) becomes one decoded path per line, as in FLTK.
private string readOfferText(wl_data_offer* offer, string mime)
{
    auto data = readOffer((int fd) { wl_data_offer_receive(offer, mime.toStringz, fd); });
    string text = cast(string) data.idup;
    if (mime == "text/uri-list")
    {
        import std.uri : decodeComponent;
        import std.string : lineSplitter, startsWith;
        import std.array : join;
        string[] lines;
        foreach (line; text.lineSplitter)
        {
            string l = line.idup;
            if (l.startsWith("file://")) l = l[7 .. $];
            try l = decodeComponent(l);
            catch (Exception) { }
            if (l.length) lines ~= l;
        }
        text = lines.join("\n");
    }
    return text;
}

package(fl) void requestSelection(int clipboard)
{
    if (clipboard == 0)
    {
        if (primaryOffer_ is null) { deliverPaste(null); return; }
        auto offer = primaryOffer_;
        auto data = readOffer((int fd) {
            zwp_primary_selection_offer_v1_receive(offer, plainTextMime.ptr, fd);
        });
        deliverPaste(cast(string) data.idup);
        return;
    }
    auto t = selectionOffer_ !is null ? cast(void*) selectionOffer_ in offerTypes_ : null;
    if (t is null || t.text is null) { deliverPaste(null); return; }
    deliverPaste(readOfferText(selectionOffer_, t.text));
}

/// Ported from `get_clipboard_image()`: a PNG or BMP image from the
/// clipboard.
package(fl) void requestSelectionImage(int clipboard)
{
    import fl.bmp_image : BMPImage;
    import fl.png_image : PngImage;
    auto t = clipboard == 1 && selectionOffer_ !is null ? cast(void*) selectionOffer_ in offerTypes_ : null;
    if (t is null || t.image is null) { deliverPasteImage(null); return; }
    string mime = t.image;
    auto offer = selectionOffer_;
    auto data = readOffer((int fd) { wl_data_offer_receive(offer, mime.toStringz, fd); }).idup;
    Object img;
    if (mime == "image/png")
    {
        auto png = new PngImage("clipboard", data);
        if (!png.fail()) img = png;
    }
    else
    {
        auto bmp = new BMPImage("clipboard", data);
        if (!bmp.fail()) img = bmp;
    }
    deliverPasteImage(img);
}

/// Ported from `Fl_Wayland_Screen_Driver::clipboard_contains()`.
package(fl) bool clipboardContains(string type)
{
    import fl.core : clipboardPlainText, clipboardImage;
    auto t = selectionOffer_ !is null ? cast(void*) selectionOffer_ in offerTypes_ : null;
    if (t is null) return false;
    if (type == clipboardPlainText) return t.text !is null;
    if (type == clipboardImage) return t.image !is null;
    return false;
}

/// FLTK on Wayland has no clipboard-change notification; fldtk sends it
/// when another program sets the clipboard (`dataDeviceSelection()`), so
/// nothing needs switching on here.
package(fl) void clipboardNotifyChange() { }

// ---- offering our own data

/// Writes `data` to `fd` as the reader takes it -- FLTK's
/// `write_data_source_cb()`, with the descriptor non-blocking.
private void writeToReader(int fd, immutable(ubyte)[] data)
{
    import core.sys.posix.fcntl : fcntl, F_GETFL, F_SETFL, O_NONBLOCK;
    import core.sys.posix.unistd : write, close;
    import fl.enumerations : fdWrite;
    fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK);
    size_t done = 0;
    addFd(fd, fdWrite, (int f) {
        import core.stdc.errno : errno, EAGAIN;
        while (done < data.length)
        {
            auto n = write(f, data.ptr + done, data.length - done);
            if (n < 0)
            {
                if (errno == EAGAIN) return;
                break;
            }
            done += n;
        }
        removeFd(f, fdWrite);
        close(f);
    });
}

/// What clipboard `rank` (0 the selection buffer, 1 the clipboard) holds,
/// as `mime`, or null if it isn't held as that type.
private immutable(ubyte)[] ownedData(int rank, string mime)
{
    import fl.core : clipboardPlainText, clipboardImage;
    string type = selectionOwnedType(rank);
    if ((mime == plainTextMime || mime == "text/plain") && type == clipboardPlainText)
        return cast(immutable(ubyte)[]) clipboardContents(rank);
    if (mime == "image/bmp" && type == clipboardImage)
        return ownedImageBmpBytes(rank).idup;
    return null;
}

/// Ported from `data_source_handle_send()`; `data` is 1 for the
/// clipboard, 0 for a drag.
extern (C) private void dataSourceSend(void* data, wl_data_source* source, const(char)* mimeType, int fd) nothrow
{
    guarded({
    import core.sys.posix.unistd : close;
    int rank = data !is null ? 1 : 0;
    auto bytes = ownedData(rank, fromStringz(mimeType).idup);
    if (bytes is null) close(fd);
    else writeToReader(fd, bytes);
    });
}

private FlWindow dndTargetWindow_;
private wl_surface* dndTargetSurface_;
private bool doingDnd_;
private bool dndStarted_; // the compositor took our drag (it entered a surface)

/// Ported from `data_source_handle_cancelled()`: another program took the
/// clipboard, or a drag ended.
extern (C) private void dataSourceCancelled(void* data, wl_data_source* source) nothrow
{
    guarded({
    wl_data_source_destroy(source);
    if (source is dataSource_)
    {
        dataSource_ = null;
        clearSelectionOwnership(1);
    }
    if (data is null) endDrag();
    });
}

/// The end of a drag we started: the window it was dropped on gets the
/// button release the compositor kept from it.
private void endDrag()
{
    if (!doingDnd_) return;
    doingDnd_ = false;
    if (dndTargetWindow_ !is null)
    {
        auto win = dndTargetWindow_;
        dndTargetWindow_ = null;
        dispatch(Event.release, win);
    }
    pushed(null);
}

extern (C) private void dataSourceTarget(void* data, wl_data_source* source, const(char)* mimeType) nothrow { }
extern (C) private void dataSourceDropPerformed(void* data, wl_data_source* source) nothrow { }

/// The drop finished; the source is ours to destroy (a copy has nothing
/// left to do).
extern (C) private void dataSourceDndFinished(void* data, wl_data_source* source) nothrow
{
    guarded({
    wl_data_source_destroy(source);
    endDrag();
    });
}

extern (C) private void dataSourceAction(void* data, wl_data_source* source, uint action) nothrow { }

private __gshared wl_data_source_listener dataSourceListener = {
    target: &dataSourceTarget,
    send: &dataSourceSend,
    cancelled: &dataSourceCancelled,
    dnd_drop_performed: &dataSourceDropPerformed,
    dnd_finished: &dataSourceDndFinished,
    action: &dataSourceAction,
};

extern (C) private void primarySourceSend(void* data, zwp_primary_selection_source_v1* source,
    const(char)* mimeType, int fd) nothrow
{
    guarded({
    import core.sys.posix.unistd : close;
    auto bytes = ownedData(0, fromStringz(mimeType).idup);
    if (bytes is null) close(fd);
    else writeToReader(fd, bytes);
    });
}

extern (C) private void primarySourceCancelled(void* data, zwp_primary_selection_source_v1* source) nothrow
{
    guarded({
    zwp_primary_selection_source_v1_destroy(source);
    if (source is primarySource_)
    {
        primarySource_ = null;
        clearSelectionOwnership(0);
    }
    });
}

private __gshared zwp_primary_selection_source_v1_listener primarySourceListener = {
    send: &primarySourceSend,
    cancelled: &primarySourceCancelled,
};

/**
 * Offers what `fl.core.copy()`/`copyImage()` stored to other programs --
 * the platform half of FLTK's `Fl_Wayland_Screen_Driver::copy()` and
 * `copy_image()`.
 */
package(fl) void setSelectionOwner(int clipboard)
{
    import fl.core : clipboardImage;
    openDisplay();
    if (clipboard == 1)
    {
        if (dataDeviceManager_ is null || dataDevice_ is null) return;
        if (dataSource_ !is null) wl_data_source_destroy(dataSource_);
        dataSource_ = wl_data_device_manager_create_data_source(dataDeviceManager_);
        wl_data_source_add_listener(dataSource_, &dataSourceListener, cast(void*) 1);
        if (selectionOwnedType(1) == clipboardImage)
            wl_data_source_offer(dataSource_, "image/bmp");
        else
        {
            wl_data_source_offer(dataSource_, plainTextMime.ptr);
            wl_data_source_offer(dataSource_, "text/plain");
        }
        wl_data_device_set_selection(dataDevice_, dataSource_, keyboardEnterSerial_);
    }
    else if (primaryManager_ !is null && primaryDevice_ !is null)
    {
        if (primarySource_ !is null) zwp_primary_selection_source_v1_destroy(primarySource_);
        primarySource_ = zwp_primary_selection_device_manager_v1_create_source(primaryManager_);
        zwp_primary_selection_source_v1_add_listener(primarySource_, &primarySourceListener, null);
        zwp_primary_selection_source_v1_offer(primarySource_, plainTextMime.ptr);
        zwp_primary_selection_device_v1_set_selection(primaryDevice_, primarySource_, serial_);
    }
    wl_display_flush(display_);
}

// ---- the data device: offers, the clipboard, drops

extern (C) private void dataOfferOffer(void* data, wl_data_offer* offer, const(char)* mimeType) nothrow
{
    guarded({
    noteOfferType(cast(void*) offer, fromStringz(mimeType).idup);
    });
}

extern (C) private void dataOfferSourceActions(void* data, wl_data_offer* offer, uint actions) nothrow { }
extern (C) private void dataOfferAction(void* data, wl_data_offer* offer, uint action) nothrow { }

private __gshared wl_data_offer_listener dataOfferListener = {
    offer: &dataOfferOffer,
    source_actions: &dataOfferSourceActions,
    action: &dataOfferAction,
};

private void destroyOffer(wl_data_offer* offer)
{
    if (offer is null) return;
    offerTypes_.remove(cast(void*) offer);
    wl_data_offer_destroy(offer);
}

/// A new offer, from the clipboard or a drag: its MIME types follow.
extern (C) private void dataDeviceDataOffer(void* data, wl_data_device* device, wl_data_offer* offer) nothrow
{
    guarded({
    offerTypes_[cast(void*) offer] = OfferTypes.init;
    wl_data_offer_add_listener(offer, &dataOfferListener, null);
    });
}

/// The clipboard changed -- FLTK's `data_device_handle_selection()`. When
/// another program set it, the clipboard-change handlers run
/// (`fl.core.addClipboardNotify()`; FLTK doesn't call them on Wayland).
extern (C) private void dataDeviceSelection(void* data, wl_data_device* device, wl_data_offer* offer) nothrow
{
    guarded({
    destroyOffer(selectionOffer_);
    selectionOffer_ = offer;
    if (offer !is null && dataSource_ is null) triggerClipboardNotify(1);
    });
}

private wl_data_offer* dragOffer_;
private uint dndSerial_;

/// Sets the event coordinates for a drag over `surface`.
private FlWindow dragCoords(wl_surface* surface, wl_fixed_t x, wl_fixed_t y)
{
    return eventCoordsFromSurface(surface, x, y);
}

/// Ported from `data_device_handle_enter()`.
extern (C) private void dataDeviceEnter(void* data, wl_data_device* device, uint serial,
    wl_surface* surface, wl_fixed_t x, wl_fixed_t y, wl_data_offer* offer) nothrow
{
    guarded({
    if (doingDnd_) dndStarted_ = true;
    FlWindow win = dragCoords(surface, x, y);
    dndTargetWindow_ = win;
    dndTargetSurface_ = win !is null ? surface : null;
    if (win !is null)
    {
        dispatch(Event.dndEnter, win);
        dragOffer_ = offer;
        dndSerial_ = serial;
    }
    if (offer !is null)
        wl_data_offer_set_actions(offer, WL_DATA_DEVICE_MANAGER_DND_ACTION_COPY,
            WL_DATA_DEVICE_MANAGER_DND_ACTION_COPY);
    });
}

/// Ported from `data_device_handle_motion()`: the widget under the drag
/// says whether it would take a drop.
extern (C) private void dataDeviceMotion(void* data, wl_data_device* device, uint time,
    wl_fixed_t x, wl_fixed_t y) nothrow
{
    guarded({
    if (dragOffer_ is null) return;
    int ret = 0;
    if (dndTargetWindow_ !is null)
    {
        dragCoords(dndTargetSurface_, x, y);
        ret = dispatch(Event.dndDrag, dndTargetWindow_);
        if (auto b = belowmouse()) b.takeFocus();
    }
    uint actions = ret && (pushed() !is null || !doingDnd_)
        ? WL_DATA_DEVICE_MANAGER_DND_ACTION_COPY : WL_DATA_DEVICE_MANAGER_DND_ACTION_NONE;
    wl_data_offer_set_actions(dragOffer_, actions, actions);
    wl_data_offer_accept(dragOffer_, dndSerial_, ret ? "text/plain".ptr : null);
    });
}

extern (C) private void dataDeviceLeave(void* data, wl_data_device* device) nothrow
{
    guarded({
    if (dragOffer_ !is null && dndTargetWindow_ !is null) dispatch(Event.dndLeave, dndTargetWindow_);
    if (dragOffer_ !is null && !doingDnd_) destroyOffer(dragOffer_);
    dragOffer_ = null;
    });
}

/// Ported from `data_device_handle_drop()`: the widget under the drop
/// gets the text as an `Event.paste`.
extern (C) private void dataDeviceDrop(void* data, wl_data_device* device) nothrow
{
    guarded({
    if (dragOffer_ is null) return;
    auto offer = dragOffer_;
    dragOffer_ = null;
    FlWindow win = dndTargetWindow_;
    if (win is null) { destroyOffer(offer); return; }
    dispatch(Event.enter, win); // sets belowmouse()
    if (!dispatch(Event.dndRelease, win))
    {
        destroyOffer(offer);
        return;
    }
    string text;
    if (doingDnd_)
        text = clipboardContents(0);
    else
    {
        auto t = cast(void*) offer in offerTypes_;
        if (t !is null && t.text !is null) text = readOfferText(offer, t.text);
    }
    if (auto b = belowmouse())
    {
        auto savedText = eText_, savedEvent = eNumber_;
        eText_ = text;
        eNumber_ = Event.paste;
        b.handle(Event.paste);
        eText_ = savedText;
        eNumber_ = savedEvent;
    }
    wl_data_offer_finish(offer);
    destroyOffer(offer);
    });
}

private __gshared wl_data_device_listener dataDeviceListener = {
    data_offer: &dataDeviceDataOffer,
    enter: &dataDeviceEnter,
    leave: &dataDeviceLeave,
    motion: &dataDeviceMotion,
    drop: &dataDeviceDrop,
    selection: &dataDeviceSelection,
};

// ---- the primary selection device

extern (C) private void primaryOfferOffer(void* data, zwp_primary_selection_offer_v1* offer, const(char)* mime) nothrow { }

private __gshared zwp_primary_selection_offer_v1_listener primaryOfferListener = {
    offer: &primaryOfferOffer,
};

extern (C) private void primaryDeviceDataOffer(void* data, zwp_primary_selection_device_v1* device,
    zwp_primary_selection_offer_v1* offer) nothrow
{
    guarded({
    zwp_primary_selection_offer_v1_add_listener(offer, &primaryOfferListener, null);
    });
}

extern (C) private void primaryDeviceSelection(void* data, zwp_primary_selection_device_v1* device,
    zwp_primary_selection_offer_v1* offer) nothrow
{
    guarded({
    if (primaryOffer_ !is null) zwp_primary_selection_offer_v1_destroy(primaryOffer_);
    primaryOffer_ = offer;
    });
}

private __gshared zwp_primary_selection_device_v1_listener primaryDeviceListener = {
    data_offer: &primaryDeviceDataOffer,
    selection: &primaryDeviceSelection,
};

private ShmImage dragIcon_;
private wl_surface* dragIconSurface_;

/**
 * The dragged text as the drag's icon -- FLTK's `offscreen_from_text()`:
 * up to 20 lines in 10-point Helvetica, at most 300 units wide, at
 * `scale` pixels per unit. FLTK draws it on a transparent background;
 * fldtk's image surfaces have no alpha, so it is black on white here.
 */
private ShmImage dragIconFor(string text, int scale)
{
    import std.string : lineSplitter;
    import fl.image_surface : ImageSurface, SurfaceDevice;
    import fl.enumerations : helvetica, black, white, Fontsize;
    if (text.length == 0) return null;
    string[] lines;
    foreach (l; text.lineSplitter)
    {
        if (lines.length == 20) break;
        lines ~= l;
    }
    fldraw.fl_font(helvetica, cast(Fontsize)(10 * scale));
    int width = 0;
    foreach (l; lines)
    {
        int lw = cast(int) fldraw.width(l);
        if (lw > width) width = lw;
    }
    if (width > 300 * scale) width = 300 * scale;
    int lh = fldraw.height();
    int w = (width + 6 + scale - 1) / scale * scale;
    int h = (cast(int) lines.length * lh + 3 + scale - 1) / scale * scale;
    if (w <= 0 || h <= 0) return null;
    float saved = currentScale();
    currentScale(1.0f);
    scope (exit) currentScale(saved);
    auto surf = new ImageSurface(w, h);
    SurfaceDevice.pushCurrent(surf);
    fldraw.fl_color(white);
    fldraw.fl_rectf(0, 0, w, h);
    fldraw.fl_color(black);
    fldraw.fl_font(helvetica, cast(Fontsize)(10 * scale));
    foreach (i, l; lines) fldraw.fl_draw(l, 3, cast(int)(i + 1) * lh);
    auto img = surf.image();
    SurfaceDevice.popCurrent();
    destroy(surf);
    return img !is null ? shmImageFrom(img, w, h, w, h, 0, 0) : null;
}

private void freeDragIcon()
{
    if (dragIconSurface_ !is null) wl_surface_destroy(dragIconSurface_);
    dragIconSurface_ = null;
    if (dragIcon_ !is null) dragIcon_.destroy();
    dragIcon_ = null;
}

/**
 * Drags the selection buffer's text (`fl.core.copy(text, 0)`) -- ported
 * from `Fl_Wayland_Screen_Driver::dnd()`, the text itself shown as the
 * drag's icon. Returns once the drag is over, as on X11 and Windows. The
 * compositor decides who may receive it: `localOnly` (no FLTK
 * equivalent) can't be honored, and other programs see the drag too.
 */
package(fl) int dnd(bool localOnly)
{
    if (dataDeviceManager_ is null || dataDevice_ is null || pointerFocus_ is null) return 0;
    wl_data_source* source = wl_data_device_manager_create_data_source(dataDeviceManager_);
    wl_data_source_add_listener(source, &dataSourceListener, null);
    wl_data_source_offer(source, plainTextMime.ptr);
    wl_data_source_offer(source, "text/plain");
    wl_data_source_set_actions(source, WL_DATA_DEVICE_MANAGER_DND_ACTION_COPY);
    doingDnd_ = true;
    dndStarted_ = false;
    int iconScale = cursorImageScale();
    dragIcon_ = dragIconFor(clipboardContents(0), iconScale);
    if (dragIcon_ !is null) dragIconSurface_ = wl_compositor_create_surface(compositor_);
    wl_data_device_start_drag(dataDevice_, source, pointerFocus_, dragIconSurface_, buttonSerial_);
    if (dragIconSurface_ !is null)
    {
        wl_surface_attach(dragIconSurface_, dragIcon_.buffer, 0, 0);
        wl_surface_set_buffer_scale(dragIconSurface_, iconScale);
        wl_surface_damage_buffer(dragIconSurface_, 0, 0, dragIcon_.w, dragIcon_.h);
        wl_surface_commit(dragIconSurface_);
    }
    // A compositor that refuses a drag (a stale serial, say) says
    // nothing; one that takes it enters the surface under the pointer,
    // ours, before this roundtrip returns.
    wl_display_roundtrip(display_);
    rethrowPending();
    if (!dndStarted_)
    {
        if (doingDnd_) wl_data_source_destroy(source); // not cancelled, still ours
        doingDnd_ = false;
        freeDragIcon();
        return 0;
    }
    while (doingDnd_ && windows_.length) wait();
    freeDragIcon();
    return 1;
}

// -- screens --------------------------------------------------------------

package(fl) int screenCount()
{
    openDisplay();
    return outputs_.length ? cast(int) outputs_.length : 1;
}

/// Ported from `Fl_Wayland_Screen_Driver::screen_xywh()`.
package(fl) void screenXYWH(out int x, out int y, out int w, out int h, int n)
{
    openDisplay();
    if (outputs_.length == 0) { w = 1024; h = 768; return; }
    if (n < 0 || n >= outputs_.length) n = 0;
    auto o = outputs_[n];
    if (o.logicalW > 0)
    {
        // logical pixels, right at a fractional desktop scale too
        float g = screenScale(n);
        x = cast(int)(o.logicalX / g);
        y = cast(int)(o.logicalY / g);
        w = cast(int)(o.logicalW / g);
        h = cast(int)(o.logicalH / g);
        return;
    }
    float s = screenScale(n) * o.wldScale;
    x = cast(int)(o.x / s);
    y = cast(int)(o.y / s);
    w = cast(int)(o.pixelW / s);
    h = cast(int)(o.pixelH / s);
}

/// The whole screen: FLTK finds the work area by maximizing test
/// windows, which isn't ported.
package(fl) void screenWorkArea(out int x, out int y, out int w, out int h, int n)
{
    screenXYWH(x, y, w, h, n);
}

/// 96 dpi, as FLTK reports on Wayland.
package(fl) void screenDpi(out float h, out float v, int n)
{
    openDisplay();
    h = v = (n >= 0 && n < screenCount()) ? 96.0f : 0.0f;
}

/// The screen containing `(x, y)`, in FLTK units.
package(fl) int screenNum(int x, int y)
{
    foreach (i; 0 .. screenCount())
    {
        int X, Y, W, H;
        screenXYWH(X, Y, W, H, i);
        if (x >= X && x < X + W && y >= Y && y < Y + H) return i;
    }
    return 0;
}

/// The screen overlapping `(x, y, w, h)` the most.
package(fl) int screenNum(int x, int y, int w, int h)
{
    int best = 0, bestArea = -1;
    foreach (i; 0 .. screenCount())
    {
        int X, Y, W, H;
        screenXYWH(X, Y, W, H, i);
        int ix = (x > X ? x : X), iy = (y > Y ? y : Y);
        int ix2 = (x + w < X + W ? x + w : X + W), iy2 = (y + h < Y + H ? y + h : Y + H);
        int area = (ix2 > ix && iy2 > iy) ? (ix2 - ix) * (iy2 - iy) : 0;
        if (area > bestArea) { bestArea = area; best = i; }
    }
    return best;
}
