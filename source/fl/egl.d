/*
 * `extern(C)` bindings for EGL (`EGL/egl.h`), the interface between
 * OpenGL and the window system on Wayland. Infrastructure, not a port of
 * an FLTK header -- the same role `fl.glx` plays for GLX on X11. Only
 * what `fl.wayland_gl_window_driver` calls is declared: the EGL functions
 * FLTK's `Fl_Wayland_Gl_Window_Driver.cxx` uses, plus `eglGetError()` for
 * error messages.
 *
 * The native display and window types are declared as `void*`: on
 * Wayland they are a `wl_display*` and a `wl_egl_window*`
 * (`fl.wayland_egl`).
 *
 * Only compiled into a build with Wayland support
 * (`version (FLDTK_HAVE_WAYLAND)`); links against `libEGL`.
 */
module fl.egl;

version (FLDTK_HAVE_WAYLAND):

extern (C) nothrow @nogc:

alias EGLint = int;
alias EGLBoolean = uint;
alias EGLenum = uint;
alias EGLDisplay = void*;
alias EGLConfig = void*;
alias EGLContext = void*;
alias EGLSurface = void*;
alias EGLNativeDisplayType = void*;
alias EGLNativeWindowType = void*;

enum EGLBoolean EGL_FALSE = 0;
enum EGLBoolean EGL_TRUE = 1;

enum EGLDisplay EGL_NO_DISPLAY = null;
enum EGLContext EGL_NO_CONTEXT = null;
enum EGLSurface EGL_NO_SURFACE = null;

// errors (eglGetError())
enum EGLint EGL_SUCCESS = 0x3000;

// config attributes
enum EGLint EGL_ALPHA_SIZE = 0x3021;
enum EGLint EGL_BLUE_SIZE = 0x3022;
enum EGLint EGL_GREEN_SIZE = 0x3023;
enum EGLint EGL_RED_SIZE = 0x3024;
enum EGLint EGL_DEPTH_SIZE = 0x3025;
enum EGLint EGL_STENCIL_SIZE = 0x3026;
enum EGLint EGL_SAMPLES = 0x3031;
enum EGLint EGL_SAMPLE_BUFFERS = 0x3032;
enum EGLint EGL_SURFACE_TYPE = 0x3033;
enum EGLint EGL_NONE = 0x3038;
enum EGLint EGL_MIN_SWAP_INTERVAL = 0x303B;
enum EGLint EGL_MAX_SWAP_INTERVAL = 0x303C;
enum EGLint EGL_RENDERABLE_TYPE = 0x3040;

// EGL_SURFACE_TYPE bits
enum EGLint EGL_WINDOW_BIT = 0x0004;

// EGL_RENDERABLE_TYPE bits
enum EGLint EGL_OPENGL_BIT = 0x0008;

// context attributes
enum EGLint EGL_CONTEXT_CLIENT_VERSION = 0x3098;

// eglBindAPI()
enum EGLenum EGL_OPENGL_API = 0x30A2;

EGLint eglGetError();
EGLDisplay eglGetDisplay(EGLNativeDisplayType display_id);
EGLBoolean eglInitialize(EGLDisplay dpy, EGLint* major, EGLint* minor);
EGLBoolean eglBindAPI(EGLenum api);
EGLBoolean eglChooseConfig(EGLDisplay dpy, const(EGLint)* attrib_list, EGLConfig* configs,
    EGLint config_size, EGLint* num_config);
EGLBoolean eglGetConfigAttrib(EGLDisplay dpy, EGLConfig config, EGLint attribute, EGLint* value);
EGLContext eglCreateContext(EGLDisplay dpy, EGLConfig config, EGLContext share_context,
    const(EGLint)* attrib_list);
EGLBoolean eglDestroyContext(EGLDisplay dpy, EGLContext ctx);
EGLSurface eglCreateWindowSurface(EGLDisplay dpy, EGLConfig config, EGLNativeWindowType win,
    const(EGLint)* attrib_list);
EGLBoolean eglDestroySurface(EGLDisplay dpy, EGLSurface surface);
EGLBoolean eglMakeCurrent(EGLDisplay dpy, EGLSurface draw, EGLSurface read, EGLContext ctx);
EGLContext eglGetCurrentContext();
EGLSurface eglGetCurrentSurface(EGLint readdraw);
EGLBoolean eglSwapBuffers(EGLDisplay dpy, EGLSurface surface);
EGLBoolean eglSwapInterval(EGLDisplay dpy, EGLint interval);
void* eglGetProcAddress(const(char)* procname);

// eglGetCurrentSurface()
enum EGLint EGL_DRAW = 0x3059;
enum EGLint EGL_READ = 0x305A;
