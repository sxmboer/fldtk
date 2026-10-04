/*
 * Port of `src/Fl_Gl_Choice.H` + the per-platform subclass that adds
 * what each platform's own context-creation call actually needs:
 * `Fl_X11_Gl_Choice` (`src/drivers/X11/Fl_X11_Gl_Window_Driver.cxx`) on
 * Linux, `Fl_WinAPI_Gl_Choice` (`src/drivers/WinAPI/
 * Fl_WinAPI_Gl_Window_Driver.cxx`) on Windows -- both merged into this
 * one concrete class rather than FLTK's real base/derived split,
 * matching the precedent already established for
 * `fl.platform_x11`/`fl.platform_win32`/`fl.window` (see
 * `fl.gl_window_driver`'s own doc comment for the full reasoning).
 *
 * Describes what's needed to create an OpenGL context for a given
 * `Fl_Mode` bitmask (or a raw platform-specific attribute list).
 * `fl.gl_window_driver`'s `find()` builds these:
 *
 * - **Linux**: the GLX-chosen X visual and a colormap compatible with
 *   it. `fl.window`'s `createWindow()` needs the `vis`/`colormap` pair
 *   to create the underlying X window against the right visual instead
 *   of the display default one (required -- see `FL/gl.h`'s own doc
 *   comment: "Mesa will crash if you try to use a visual not returned
 *   by glXChooseVisual").
 * - **Windows**: a `DescribePixelFormat()`-chosen pixel-format index
 *   plus its own `PIXELFORMATDESCRIPTOR` (`SetPixelFormat()` needs
 *   both). Unlike X11, Windows needs no visual/colormap at window-
 *   creation time at all -- `SetPixelFormat()` is called lazily, once,
 *   on the window's own device context the first time a GL context is
 *   actually created for it (`fl.gl_window_driver.createGlContext()`),
 *   matching FLTK's own `Fl_WinAPI_Gl_Window_Driver::before_show()`
 *   being an unmodified empty override (the base `Fl_Gl_Window_Driver::
 *   before_show()` no-op) -- confirmed by reading the real source, not
 *   assumed.
 */
module fl.gl_choice;

version (linux) version = FldtkGl;
version (Windows) version = FldtkGl;

version (FldtkGl):

version (linux) import fl.xlib : XVisualInfo, Colormap;
version (Windows) import core.sys.windows.wingdi : PIXELFORMATDESCRIPTOR;

/// Port of `Fl_Gl_Choice` (+ `Fl_X11_Gl_Choice`/`Fl_WinAPI_Gl_Choice`).
/// A singly linked list node -- `fl.gl_window_driver.first`/
/// `findBegin()` walk `next` the same way FLTK's static
/// `Fl_Gl_Choice::first`/`find_begin()` do.
final class GlChoice
{
    int mode;
    const(int)* alist;
    GlChoice next;

    // X11-specific (Fl_X11_Gl_Choice in FLTK)
    version (linux)
    {
        XVisualInfo* vis;
        Colormap colormap;
    }

    // Windows-specific (Fl_WinAPI_Gl_Choice in FLTK)
    version (Windows)
    {
        int pixelformat;
        PIXELFORMATDESCRIPTOR pfd;
    }

    this(int mode, const(int)* alist, GlChoice next)
    {
        this.mode = mode;
        this.alist = alist;
        this.next = next;
    }
}
