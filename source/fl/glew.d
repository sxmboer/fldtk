/*
 * Bindings for the ~26 modern (GL 2.0+/3.0+) core-profile functions
 * `source/examples/OpenGL3test.d`/`OpenGL3_glut_test.d` need (shader/
 * program creation & introspection, VAO/VBO management, vertex-
 * attribute/uniform setup) -- infrastructure, not a port of an FLTK
 * header, same role `fl.opengl`/`fl.glx`/`fl.glu` play for their own
 * foreign C libraries.
 *
 * **Why these functions need resolving at all**: unlike the classic GL
 * 1.x functions `fl.opengl` declares as plain linkable symbols, neither
 * the Linux nor the Windows OpenGL ABI *guarantees* these as directly
 * linkable exports -- Linux's `libGL.so` only guarantees functions up
 * through OpenGL 1.2, and Windows' `opengl32.dll` only guarantees OpenGL
 * 1.1; everything past that (essentially the entire shader/VBO/VAO
 * feature set) is meant to be resolved at *runtime*, per-function, via
 * `glXGetProcAddress()`/`wglGetProcAddress()`, since which extensions/
 * versions are actually available depends on the driver. Verified
 * against the real FLTK source rather than assumed:
 * `examples/OpenGL3test.cxx`/`OpenGL3-glut-test.cxx` handle this the
 * same way on *both* platforms -- they depend on **GLEW** (the OpenGL
 * Extension Wrangler Library), a third-party library whose whole job is
 * doing exactly this resolution and exposing the results as normal-
 * looking function calls.
 *
 * **fldtk resolves them itself, without GLEW**: `glewInit()` below looks
 * each function up through `fl.gl_window_driver.getProcAddress()`, the
 * same lookup FLTK's driver uses for `glUseProgram` in
 * `switchToGl1()` -- `glXGetProcAddressARB()` on X11,
 * `eglGetProcAddress()` on Wayland, `wglGetProcAddress()` on Windows.
 * This is what GLEW itself does internally; doing it here needs no extra
 * library, and works on every backend (a GLEW built for GLX fails
 * `glewInit()` on an EGL context).
 *
 * **Binding shape** from the two consumer samples' point of view: a
 * private function-pointer variable per modern GL function
 * (`__glewCreateShader` etc, matching GLEW's own naming), populated by
 * `glewInit()`, plus a thin D wrapper function of the familiar GL name
 * that calls through it -- `glCreateShader(...)` reads exactly like every
 * other GL call at the sample's call sites, and the samples keep FLTK's
 * `glewInit()`/`glewGetString()` calls unchanged. `extern (System)`, not
 * `extern (C)`, throughout -- real `GL/glew.h` declares every one of
 * these `GLAPIENTRY` (`APIENTRY`, i.e. `__stdcall` on Windows, plain C on
 * Linux), the same convention `fl.opengl`/`fl.glu` match for the
 * identical reason: calling through a function pointer via the wrong
 * convention corrupts the stack silently rather than failing to compile.
 *
 * **Scope**: only the ~26 modern GL functions
 * `OpenGL3test.d`/`OpenGL3_glut_test.d` actually call are declared --
 * add more the same way (a variable, a `resolve()` line in `glewInit()`,
 * a wrapper) if a future sample needs one.
 *
 * Linux and Windows (`version (linux)`/`version (Windows)`), matching
 * fl.xlib/fl.opengl/fl.glx/fl.glu.
 */
module fl.glew;

version (linux) version = FldtkGlew;
version (Windows) version = FldtkGlew;

version (FldtkGlew):

import fl.opengl : GLenum, GLuint, GLint, GLsizei, GLchar, GLfloat, GLboolean,
    GLintptr, GLsizeiptr, GLubyte;

enum GLEW_OK = 0;
enum GLEW_ERROR_NO_GL_VERSION = 1;
enum GLEW_ERROR_GL_VERSION_10_ONLY = 2;
enum GLEW_ERROR_GLX_VERSION_11_ONLY = 3;
enum GLEW_ERROR_NO_GLX_DISPLAY = 4;
enum GLEW_VERSION = 1;

import glDriver = fl.gl_window_driver;

/// Resolves every `__glew*` function-pointer variable below through
/// `fl.gl_window_driver.getProcAddress()` (`glXGetProcAddressARB()` on
/// X11, `eglGetProcAddress()` on Wayland, `wglGetProcAddress()` on
/// Windows) -- what GLEW's own `glewInit()` does. Must be called once,
/// after a GL context is current, before any of the wrapper functions
/// below are used, as with GLEW (`OpenGL3test.cxx`'s `handle()`/
/// `OpenGL3-glut-test.cxx`'s `main()`, both right after `make_current()`/
/// window creation). Returns `GLEW_OK` once every function resolved,
/// `GLEW_ERROR_NO_GL_VERSION` if any one of them failed to (no current
/// GL context, or a driver without the function).
GLenum glewInit()
{
    bool ok = true;
    void resolve(T)(ref T fn, string name)
    {
        // name is a string literal, so NUL-terminated
        fn = cast(T) glDriver.getProcAddress(name.ptr);
        if (fn is null) ok = false;
    }

    resolve(__glewCreateShader, "glCreateShader");
    resolve(__glewShaderSource, "glShaderSource");
    resolve(__glewCompileShader, "glCompileShader");
    resolve(__glewCreateProgram, "glCreateProgram");
    resolve(__glewAttachShader, "glAttachShader");
    resolve(__glewLinkProgram, "glLinkProgram");
    resolve(__glewUseProgram, "glUseProgram");
    resolve(__glewDeleteShader, "glDeleteShader");
    resolve(__glewGetShaderiv, "glGetShaderiv");
    resolve(__glewGetShaderInfoLog, "glGetShaderInfoLog");
    resolve(__glewGetProgramiv, "glGetProgramiv");
    resolve(__glewGetProgramInfoLog, "glGetProgramInfoLog");
    resolve(__glewGenVertexArrays, "glGenVertexArrays");
    resolve(__glewBindVertexArray, "glBindVertexArray");
    resolve(__glewGenBuffers, "glGenBuffers");
    resolve(__glewBindBuffer, "glBindBuffer");
    resolve(__glewBufferData, "glBufferData");
    resolve(__glewBufferSubData, "glBufferSubData");
    resolve(__glewGetBufferSubData, "glGetBufferSubData");
    resolve(__glewEnableVertexAttribArray, "glEnableVertexAttribArray");
    resolve(__glewVertexAttribPointer, "glVertexAttribPointer");
    resolve(__glewVertexAttrib3f, "glVertexAttrib3f");
    resolve(__glewGetUniformLocation, "glGetUniformLocation");
    resolve(__glewGetAttribLocation, "glGetAttribLocation");
    resolve(__glewUniform2fv, "glUniform2fv");
    resolve(__glewBindFragDataLocation, "glBindFragDataLocation");
    resolve(__glewBindAttribLocation, "glBindAttribLocation");

    return ok ? GLEW_OK : GLEW_ERROR_NO_GL_VERSION;
}

/// Returns a human-readable string for `name` (only `GLEW_VERSION` is
/// declared above, the only one the samples ask for). This is fldtk's
/// own loader, not GLEW, so it names itself rather than reporting a
/// GLEW version.
const(GLubyte)* glewGetString(GLenum name) nothrow @nogc
{
    static immutable string versionString = "fldtk internal GL-extension loader\0";
    return cast(const(GLubyte)*) versionString.ptr;
}

// ---- Modern GL functions, resolved by glewInit() above at runtime ----

private extern (System) __gshared
{
    GLuint function(GLenum type) __glewCreateShader;
    void function(GLuint shader, GLsizei count, const(GLchar*)* string_, const(GLint)* length) __glewShaderSource;
    void function(GLuint shader) __glewCompileShader;
    GLuint function() __glewCreateProgram;
    void function(GLuint program, GLuint shader) __glewAttachShader;
    void function(GLuint program) __glewLinkProgram;
    void function(GLuint program) __glewUseProgram;
    void function(GLuint shader) __glewDeleteShader;
    void function(GLuint shader, GLenum pname, GLint* param) __glewGetShaderiv;
    void function(GLuint shader, GLsizei bufSize, GLsizei* length, GLchar* infoLog) __glewGetShaderInfoLog;
    void function(GLuint program, GLenum pname, GLint* param) __glewGetProgramiv;
    void function(GLuint program, GLsizei bufSize, GLsizei* length, GLchar* infoLog) __glewGetProgramInfoLog;
    void function(GLsizei n, GLuint* arrays) __glewGenVertexArrays;
    void function(GLuint array) __glewBindVertexArray;
    void function(GLsizei n, GLuint* buffers) __glewGenBuffers;
    void function(GLenum target, GLuint buffer) __glewBindBuffer;
    void function(GLenum target, GLsizeiptr size, const(void)* data, GLenum usage) __glewBufferData;
    void function(GLenum target, GLintptr offset, GLsizeiptr size, const(void)* data) __glewBufferSubData;
    void function(GLenum target, GLintptr offset, GLsizeiptr size, void* data) __glewGetBufferSubData;
    void function(GLuint index) __glewEnableVertexAttribArray;
    void function(GLuint index, GLint size, GLenum type, GLboolean normalized, GLsizei stride, const(void)* pointer) __glewVertexAttribPointer;
    void function(GLuint index, GLfloat x, GLfloat y, GLfloat z) __glewVertexAttrib3f;
    GLint function(GLuint program, const(GLchar)* name) __glewGetUniformLocation;
    GLint function(GLuint program, const(GLchar)* name) __glewGetAttribLocation;
    void function(GLint location, GLsizei count, const(GLfloat)* value) __glewUniform2fv;
    void function(GLuint program, GLuint colorNumber, const(GLchar)* name) __glewBindFragDataLocation;
    void function(GLuint program, GLuint index, const(GLchar)* name) __glewBindAttribLocation;
}

// ---- Thin D wrapper functions (shared -- identical on both platforms) ----

GLuint glCreateShader(GLenum type) { return __glewCreateShader(type); }
void glShaderSource(GLuint shader, GLsizei count, const(GLchar*)* string_, const(GLint)* length)
{
    __glewShaderSource(shader, count, string_, length);
}
void glCompileShader(GLuint shader) { __glewCompileShader(shader); }
GLuint glCreateProgram() { return __glewCreateProgram(); }
void glAttachShader(GLuint program, GLuint shader) { __glewAttachShader(program, shader); }
void glLinkProgram(GLuint program) { __glewLinkProgram(program); }
void glUseProgram(GLuint program) { __glewUseProgram(program); }
void glDeleteShader(GLuint shader) { __glewDeleteShader(shader); }
void glGetShaderiv(GLuint shader, GLenum pname, GLint* param) { __glewGetShaderiv(shader, pname, param); }
void glGetShaderInfoLog(GLuint shader, GLsizei bufSize, GLsizei* length, GLchar* infoLog)
{
    __glewGetShaderInfoLog(shader, bufSize, length, infoLog);
}
void glGetProgramiv(GLuint program, GLenum pname, GLint* param) { __glewGetProgramiv(program, pname, param); }
void glGetProgramInfoLog(GLuint program, GLsizei bufSize, GLsizei* length, GLchar* infoLog)
{
    __glewGetProgramInfoLog(program, bufSize, length, infoLog);
}
void glGenVertexArrays(GLsizei n, GLuint* arrays) { __glewGenVertexArrays(n, arrays); }
void glBindVertexArray(GLuint array) { __glewBindVertexArray(array); }
void glGenBuffers(GLsizei n, GLuint* buffers) { __glewGenBuffers(n, buffers); }
void glBindBuffer(GLenum target, GLuint buffer) { __glewBindBuffer(target, buffer); }
void glBufferData(GLenum target, GLsizeiptr size, const(void)* data, GLenum usage)
{
    __glewBufferData(target, size, data, usage);
}
void glBufferSubData(GLenum target, GLintptr offset, GLsizeiptr size, const(void)* data)
{
    __glewBufferSubData(target, offset, size, data);
}
void glGetBufferSubData(GLenum target, GLintptr offset, GLsizeiptr size, void* data)
{
    __glewGetBufferSubData(target, offset, size, data);
}
void glEnableVertexAttribArray(GLuint index) { __glewEnableVertexAttribArray(index); }
void glVertexAttribPointer(GLuint index, GLint size, GLenum type, GLboolean normalized,
    GLsizei stride, const(void)* pointer)
{
    __glewVertexAttribPointer(index, size, type, normalized, stride, pointer);
}
void glVertexAttrib3f(GLuint index, GLfloat x, GLfloat y, GLfloat z)
{
    __glewVertexAttrib3f(index, x, y, z);
}
GLint glGetUniformLocation(GLuint program, const(GLchar)* name) { return __glewGetUniformLocation(program, name); }
GLint glGetAttribLocation(GLuint program, const(GLchar)* name) { return __glewGetAttribLocation(program, name); }
void glUniform2fv(GLint location, GLsizei count, const(GLfloat)* value)
{
    __glewUniform2fv(location, count, value);
}
void glBindFragDataLocation(GLuint program, GLuint colorNumber, const(GLchar)* name)
{
    __glewBindFragDataLocation(program, colorNumber, name);
}
void glBindAttribLocation(GLuint program, GLuint index, const(GLchar)* name)
{
    __glewBindAttribLocation(program, index, name);
}
