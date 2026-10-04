/*
 * Minimal `extern(C)` bindings for GLX (`GL/glx.h`), the X11 binding
 * of OpenGL. Infrastructure, not a port of an FLTK header -- same role
 * `fl.xlib` plays for Xlib and `fl.opengl` plays for core GL (see
 * those modules' own doc comments). Only what `fl.gl_choice`/
 * `fl.gl_window_driver` actually call is declared -- this is every GLX
 * entry point the real FLTK X11 GL driver, `Fl_X11_Gl_Window_Driver.cxx`,
 * calls.
 *
 * `glXSwapIntervalEXT`/`glXSwapIntervalMESA`/`glXSwapIntervalSGI` are
 * deliberately NOT declared as direct-link `extern(C)` functions below:
 * they're GLX *extensions*, not guaranteed to exist in every GLX
 * implementation, and FLTK itself only ever reaches them via
 * runtime `glXGetProcAddressARB()` lookup + a function-pointer cast
 * (see `fl.gl_window_driver`'s `initSwapInterval()`, ported from
 * `Fl_X11_Gl_Window_Driver.cxx`'s `init_swap_interval()`) -- declaring
 * them here as if they were ordinary linked symbols would be wrong,
 * not just redundant.
 *
 * Linux only (`version (linux)`), matching fl.xlib/fl.opengl.
 */
module fl.glx;

version (linux):

import fl.xlib : Display, Window, Colormap, XVisualInfo, Bool;
import core.stdc.config : c_ulong;

extern (C):
@nogc:
nothrow:

// Opaque GLX context handle (real name is `struct __GLXcontextRec`) --
// only ever created/destroyed/passed to the functions below, never
// inspected field-by-field, same treatment fl.xlib gives GC/XIM/XIC.
struct __GLXcontextRec;
alias GLXContext = __GLXcontextRec*;
alias GLXDrawable = Window;
alias GLXPixmap = Window;

// glXChooseVisual()/glXGetConfig() attribute list tokens (GL/glx.h)
enum GLX_USE_GL = 1;
enum GLX_BUFFER_SIZE = 2;
enum GLX_LEVEL = 3;
enum GLX_RGBA = 4;
enum GLX_DOUBLEBUFFER = 5;
enum GLX_STEREO = 6;
enum GLX_AUX_BUFFERS = 7;
enum GLX_RED_SIZE = 8;
enum GLX_GREEN_SIZE = 9;
enum GLX_BLUE_SIZE = 10;
enum GLX_ALPHA_SIZE = 11;
enum GLX_DEPTH_SIZE = 12;
enum GLX_STENCIL_SIZE = 13;
enum GLX_ACCUM_RED_SIZE = 14;
enum GLX_ACCUM_GREEN_SIZE = 15;
enum GLX_ACCUM_BLUE_SIZE = 16;
enum GLX_ACCUM_ALPHA_SIZE = 17;
// GLX_SGIS_multisample
enum GLX_SAMPLES_SGIS = 100001;
// GLX_EXT_swap_control (glXQueryDrawable() attribute)
enum GLX_SWAP_INTERVAL_EXT = 0x20F1;

XVisualInfo* glXChooseVisual(Display* dpy, int screen, int* attribList);
GLXContext glXCreateContext(Display* dpy, XVisualInfo* vis, GLXContext shareList, Bool direct);
void glXDestroyContext(Display* dpy, GLXContext ctx);
Bool glXMakeCurrent(Display* dpy, GLXDrawable drawable, GLXContext ctx);
GLXContext glXGetCurrentContext();
void glXSwapBuffers(Display* dpy, GLXDrawable drawable);
Bool glXQueryVersion(Display* dpy, int* major, int* minor);
const(char)* glXQueryExtensionsString(Display* dpy, int screen);
void* glXGetProcAddressARB(const(ubyte)* procName);
void glXWaitGL();
void glXWaitX();
void glXUseXFont(c_ulong font, int first, int count, int listBase);
int glXQueryDrawable(Display* dpy, GLXDrawable draw, int attribute, uint* value);
