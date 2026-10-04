/*
 * Port of `FL/Fl_OpenGL_Display_Device.H` + `src/drivers/OpenGL/
 * Fl_OpenGL_Display_Device.cxx` (FLTK 1.5.0, ~/Repositories/fltk).
 *
 * The `SurfaceDevice` that redirects `fl.draw`'s leaf primitives to
 * `fl.gl_graphics_driver.GlGraphicsDriver` -- see
 * `fl.gl_window.GlWindow.drawBegin()`/`drawEnd()` for the real
 * `SurfaceDevice.pushCurrent()`/`popCurrent()` pair this backs, and
 * `fl.graphics_driver`'s own doc comment for the null-means-native
 * dispatch model this plugs into.
 *
 * FLTK's own `display_device()` is a function-local C++ `static`
 * (lazily constructed on first call, one instance for the whole
 * process). This port's module-level `instance_` plus a lazy-init
 * accessor is the direct D equivalent -- thread-local, not `__gshared`,
 * matching `fl.graphics_driver.currentDriver`'s own reasoning (drawing
 * in this port is main-thread-only already).
 */
module fl.gl_display_device;

version (linux) version = FldtkGl;
version (Windows) version = FldtkGl;

version (FldtkGl):

import fl.image_surface : SurfaceDevice;
import fl.gl_graphics_driver : GlGraphicsDriver;

final class GlDisplayDevice : SurfaceDevice
{
    private GlGraphicsDriver glDriver_;

    private this(GlGraphicsDriver driver)
    {
        super(driver);
        glDriver_ = driver;
    }

    /// The concrete GL graphics driver this surface dispatches to --
    /// needed by `GlWindow.drawBegin()` to call `setMetrics()` before
    /// pushing this surface current each frame.
    GlGraphicsDriver glDriver() { return glDriver_; }

    private static GlDisplayDevice instance_;

    /// Ported from `Fl_OpenGL_Display_Device::display_device()`.
    static GlDisplayDevice displayDevice()
    {
        if (instance_ is null)
            instance_ = new GlDisplayDevice(new GlGraphicsDriver());
        return instance_;
    }
}
