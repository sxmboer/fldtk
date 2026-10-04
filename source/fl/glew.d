/*
 * Bindings for the ~26 modern (GL 2.0+/3.0+) core-profile functions
 * `samples/examples/OpenGL3test.d`/`OpenGL3_glut_test.d` need (shader/
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
 * **Deliberately platform-split, unlike every other binding module in
 * this project**: Linux binds directly to the real system `libGLEW.so`,
 * matching FLTK's own dependency choice exactly (GLEW is genuinely
 * installed and working there). Windows instead resolves the same ~26
 * functions itself via `wglGetProcAddress()` (already linked
 * unconditionally through `opengl32.dll`, no new dependency), matching
 * this project's zero-external-dependency goal for Windows rather than
 * requiring a separate GLEW Windows package (`glew32s.lib`) to be
 * installed. This is the same technique GLEW itself uses internally,
 * and the same one `fl.gl_window_driver.switchToGl1()` already uses for
 * its own single `glUseProgram` lookup ("a driver-
 * internal ad-hoc lookup, not a dependency on GLEW at all -- GLEW is
 * purely a *sample*-level convenience FLTK itself never needs
 * inside the library", per that function's own doc comment) -- just
 * extended here to cover the rest, Windows-only. `dub.sdl`'s Linux
 * config keeps its `GLEW` `libs` entry; the Windows config never needed
 * one in the first place.
 *
 * **Binding shape is identical either way** from the two consumer
 * samples' own point of view: a private function-pointer variable per
 * modern GL function (`__glewCreateShader` etc, matching GLEW's own
 * naming), populated before use, plus a thin real D wrapper function of
 * the familiar GL name that calls through it -- `glCreateShader(...)`
 * reads exactly like every other GL call at the sample's own call
 * sites regardless of which platform branch populated the variable
 * behind it, and neither sample needs a single line changed. The two
 * branches differ only in *how* that variable gets populated: Linux's
 * `extern __gshared` binds directly to GLEW's own exported data symbol
 * (populated by the real `glewInit()` GLEW itself exports); Windows'
 * plain (non-`extern`) `__gshared` is populated by this module's own
 * `glewInit()` instead. `extern (System)`, not `extern (C)`, throughout
 * -- real `GL/glew.h` declares every one of these `GLAPIENTRY`
 * (`APIENTRY`, i.e. `__stdcall` on Windows, plain C on Linux), the same
 * convention `fl.opengl`/`fl.glu` already match for the identical
 * reason: calling through a function pointer via the wrong convention
 * corrupts the stack silently rather than failing to compile, so this
 * one has to be exactly right, not merely "close enough to link".
 *
 * **Scope**: only the ~26 modern GL functions
 * `OpenGL3test.d`/`OpenGL3_glut_test.d` actually call are declared --
 * add more the same way on each platform branch (Linux: an `extern
 * __gshared` for the right `__glew*` symbol; Windows: a `resolve()`
 * line in `glewInit()`) if a future sample needs one.
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

version (linux)
{
    // ---- Real, directly-linkable GLEW library entry points (Linux) ----

    extern (System) @nogc nothrow
    {
        /// Resolves every `__glew*` function-pointer variable below via
        /// `glXGetProcAddress()`. Must be called once, after a GL
        /// context is current, before any of the wrapper functions
        /// below are used -- matches FLTK's own call site exactly
        /// (`OpenGL3test.cxx`'s `handle()`/`OpenGL3-glut-test.cxx`'s
        /// `main()`, both right after `make_current()`/window
        /// creation).
        GLenum glewInit();

        /// Returns a human-readable string for `name` (e.g.
        /// `GLEW_VERSION` -> GLEW's own version string). Ported from
        /// `glewGetString()`.
        const(GLubyte)* glewGetString(GLenum name);
    }

    // ---- Modern GL functions, resolved by glewInit() above at runtime ----

    private extern (System) extern __gshared
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
}
else version (Windows)
{
    // ---- Self-contained loader (Windows only -- no GLEW installed) ----

    import core.sys.windows.windows : wglGetProcAddress;

    /// Resolves `name` to its runtime address via `wglGetProcAddress()`
    /// -- the same mechanism real GLEW itself uses internally on
    /// Windows, just inlined here rather than delegated to that
    /// third-party library (not installed on this project's Windows
    /// dev machine -- see this module's own doc comment). `name` must
    /// be a D string literal or otherwise already NUL-terminated
    /// (`.ptr` is passed straight through to the C-style entry point,
    /// no defensive copy).
    private void* getGlProcAddress(string name) nothrow @nogc
    {
        return cast(void*) wglGetProcAddress(name.ptr);
    }

    /// Resolves every `__glew*` function-pointer variable below. Must
    /// be called once, after a GL context is current, before any of
    /// the wrapper functions below are used -- matches the real-GLEW
    /// `glewInit()` call site exactly (`OpenGL3test.cxx`'s `handle()`/
    /// `OpenGL3-glut-test.cxx`'s `main()`, both right after
    /// `make_current()`/window creation). Returns `GLEW_OK` once every
    /// function resolved, `GLEW_ERROR_NO_GL_VERSION` if any one of them
    /// failed to (e.g. no current GL context, or a driver genuinely
    /// missing the extension).
    GLenum glewInit() nothrow @nogc
    {
        bool ok = true;
        void resolve(T)(ref T fn, string name)
        {
            fn = cast(T) getGlProcAddress(name);
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

    /// Returns a human-readable string for `name` (only `GLEW_VERSION`
    /// is declared above, matching this module's only real caller's
    /// own usage). Since this is Windows' own internal loader, not real
    /// GLEW, this just identifies itself as such rather than reporting
    /// a GLEW version number that would no longer mean anything.
    const(GLubyte)* glewGetString(GLenum name) nothrow @nogc
    {
        static immutable string versionString = "fldtk internal GL-extension loader (Windows, no GLEW)\0";
        return cast(const(GLubyte)*) versionString.ptr;
    }

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
