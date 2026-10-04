/*
 * Minimal `extern(C)` bindings for libGL's classic/fixed-function
 * OpenGL 1.x API (`GL/gl.h`). Infrastructure, not a port of an FLTK
 * header -- same role `fl.xlib` plays for Xlib (see that module's own
 * doc comment). Only the types/constants/functions fldtk's own GL
 * support (`fl.gl_choice`, `fl.gl_window_driver`, `fl.gl_window`, and
 * `fl.gl`'s `gl_draw()`/`gl_font()` text helpers) actually needs are
 * declared; real `GL/gl.h` has hundreds more, including the entire
 * modern core-profile API that isn't linkable directly from libGL.so on
 * Linux at all (it needs runtime `glXGetProcAddress` loading) -- FLTK's
 * own GL usage never reaches past OpenGL 1.x fixed-function calls, so
 * none of that is needed here (`GL/glew.h`/`fl.glew` covers this port's
 * own GL3 sample support instead, a separate concern from this module).
 *
 * Linux and Windows (`version (linux)`/`version (Windows)`) -- OpenGL's
 * classic API surface is identical on both, so this one module serves
 * `fl.gl_window_driver`'s GLX-backed X11 implementation and its
 * WGL-backed Windows one equally. Wayland's GL story is EGL-based and
 * genuinely different, so it's out of scope until this port has a
 * Wayland driver at all; Cocoa is out of scope like the rest of this
 * port's macOS-untested code (see `CLAUDE.md`'s own "Platform scope"
 * section).
 *
 * `extern (System)` rather than `extern (C)`: real `GL/gl.h` declares
 * every function `WINGDIAPI ... APIENTRY` on Windows, where `APIENTRY`
 * is `__stdcall` -- matching the same native-calling-convention split
 * `extern (System)` already exists to express (`__stdcall` on Windows,
 * plain C everywhere else), rather than hand-writing a `version`
 * branch for something the language already has a keyword for.
 *
 * No `unittest` blocks here -- same reasoning as fl.xlib: every real
 * call needs a live GL context (which needs a live display + a
 * GL-compatible pixel format/visual), so nothing here is meaningfully
 * testable headlessly.
 */
module fl.opengl;

version (linux) version = FldtkGl;
version (Windows) version = FldtkGl;

version (FldtkGl):

extern (System):
@nogc:
nothrow:

// GL scalar types (GL/gl.h)
alias GLenum = uint;
alias GLboolean = ubyte;
alias GLbitfield = uint;
alias GLvoid = void;
alias GLbyte = byte;
alias GLshort = short;
alias GLint = int;
alias GLsizei = int;
alias GLubyte = ubyte;
alias GLushort = ushort;
alias GLuint = uint;
alias GLfloat = float;
alias GLclampf = float;
alias GLdouble = double;
alias GLchar = char;
alias GLintptr = ptrdiff_t;
alias GLsizeiptr = ptrdiff_t;
alias GLclampd = double;

// Booleans
enum GL_FALSE = 0;
enum GL_TRUE = 1;

// Begin modes
enum GL_POINTS = 0x0000;
enum GL_LINES = 0x0001;
enum GL_LINE_LOOP = 0x0002;
enum GL_LINE_STRIP = 0x0003;
enum GL_TRIANGLES = 0x0004;
enum GL_TRIANGLE_STRIP = 0x0005;
enum GL_TRIANGLE_FAN = 0x0006;
enum GL_QUADS = 0x0007;
enum GL_QUAD_STRIP = 0x0008;
enum GL_POLYGON = 0x0009;

// glClear buffer bits
enum GL_DEPTH_BUFFER_BIT = 0x00000100;
enum GL_ACCUM_BUFFER_BIT = 0x00000200;
enum GL_STENCIL_BUFFER_BIT = 0x00000400;
enum GL_COLOR_BUFFER_BIT = 0x00004000;

// Data types (glTexImage2D, etc)
enum GL_BYTE = 0x1400;
enum GL_UNSIGNED_BYTE = 0x1401;
enum GL_SHORT = 0x1402;
enum GL_UNSIGNED_SHORT = 0x1403;
enum GL_INT = 0x1404;
enum GL_UNSIGNED_INT = 0x1405;
enum GL_FLOAT = 0x1406;

// glMatrixMode
enum GL_MODELVIEW = 0x1700;
enum GL_PROJECTION = 0x1701;
enum GL_TEXTURE = 0x1702;
enum GL_MATRIX_MODE = 0x0BA0;

// Buffers (glDrawBuffer/glReadBuffer)
enum GL_FRONT = 0x0404;
enum GL_BACK = 0x0405;

// Pixel formats
enum GL_COLOR = 0x1800;
enum GL_DEPTH = 0x1801;
enum GL_STENCIL = 0x1802;
enum GL_RGB = 0x1907;
enum GL_RGBA = 0x1908;

// glEnable/glDisable capabilities
enum GL_POINT_SMOOTH = 0x0B10;
enum GL_LINE_SMOOTH = 0x0B20;
enum GL_CULL_FACE = 0x0B44;
enum GL_DEPTH_TEST = 0x0B71;
enum GL_STENCIL_TEST = 0x0B90;
enum GL_LIGHTING = 0x0B50;
enum GL_LIGHT0 = 0x4000;
enum GL_COLOR_MATERIAL = 0x0B57;
enum GL_BLEND = 0x0BE2;
enum GL_SCISSOR_TEST = 0x0C11;
enum GL_TEXTURE_2D = 0x0DE1;

// Lighting/material parameter names (glLightfv/glLightModelfv/glMaterialfv)
enum GL_AMBIENT = 0x1200;
enum GL_DIFFUSE = 0x1201;
enum GL_SPECULAR = 0x1202;
enum GL_POSITION = 0x1203;
enum GL_SHININESS = 0x1601;
enum GL_LIGHT_MODEL_LOCAL_VIEWER = 0x0B51;
enum GL_LIGHT_MODEL_TWO_SIDE = 0x0B52;
enum GL_LIGHT_MODEL_AMBIENT = 0x0B53;
enum GL_FRONT_AND_BACK = 0x0408;
enum GL_AMBIENT_AND_DIFFUSE = 0x1602;

// glShadeModel() modes
enum GL_FLAT = 0x1D00;
enum GL_SMOOTH = 0x1D01;

// glRenderMode() modes
enum GL_RENDER = 0x1C00;
enum GL_SELECT = 0x1C02;
enum GL_FEEDBACK = 0x1C01;

// glDepthFunc() comparison functions
enum GL_LEQUAL = 0x0203;

// glEnable()/glPushAttrib() bits used by fractals.d/fracviewer.d
enum GL_NORMALIZE = 0x0BA1;
enum GL_LIGHTING_BIT = 0x00000040;

// glNewList() modes
enum GL_COMPILE = 0x1300;
enum GL_COMPILE_AND_EXECUTE = 0x1301;

// Modern (GL 2.0+/3.0+) core-profile constants -- the actual *functions*
// for these (glCreateShader/glGenVertexArrays/etc) are runtime-resolved
// via GLEW instead of declared here, see fl.glew's own doc comment for
// why; the plain numeric constants they take, unlike the functions
// themselves, need no such resolution (they're just numbers, not
// symbols).
enum GL_ARRAY_BUFFER = 0x8892;
enum GL_STATIC_DRAW = 0x88E4;
enum GL_FRAGMENT_SHADER = 0x8B30;
enum GL_VERTEX_SHADER = 0x8B31;
enum GL_COMPILE_STATUS = 0x8B81;
enum GL_LINK_STATUS = 0x8B82;
enum GL_INFO_LOG_LENGTH = 0x8B84;
enum GL_SHADING_LANGUAGE_VERSION = 0x8B8C;

// glGetIntegerv() names for the current matrix (glpuzzle.d's own
// picking/camera code reads these back directly)
enum GL_MODELVIEW_MATRIX = 0x0BA6;
enum GL_PROJECTION_MATRIX = 0x0BA7;

// Blend functions
enum GL_SRC_ALPHA = 0x0302;
enum GL_ONE_MINUS_SRC_ALPHA = 0x0303;

// glGetIntegerv/glGetFloatv/glGetDoublev/glGetString names
enum GL_VIEWPORT = 0x0BA2;
enum GL_MAX_VIEWPORT_DIMS = 0x0D3A;
enum GL_CURRENT_RASTER_POSITION = 0x0B07;
enum GL_CURRENT_RASTER_POSITION_VALID = 0x0B08;
enum GL_CURRENT_PROGRAM = 0x8B8D;
enum GL_VENDOR = 0x1F00;

// Per-buffer bit-depth queries, plus GL_DOUBLEBUFFER/GL_STEREO/GL_SAMPLES
// -- added for `fl.glut`'s `GLUT_WINDOW_*_SIZE` family (`FL/glut.H`'s own
// `#define GLUT_WINDOW_STENCIL_SIZE GL_STENCIL_BITS` etc, plain numeric
// aliases with no logic of their own, resolved via `glGetIntegerv()`).
enum GL_RED_BITS = 0x0D52;
enum GL_GREEN_BITS = 0x0D53;
enum GL_BLUE_BITS = 0x0D54;
enum GL_ALPHA_BITS = 0x0D55;
enum GL_DEPTH_BITS = 0x0D56;
enum GL_STENCIL_BITS = 0x0D57;
enum GL_ACCUM_RED_BITS = 0x0D58;
enum GL_ACCUM_GREEN_BITS = 0x0D59;
enum GL_ACCUM_BLUE_BITS = 0x0D5A;
enum GL_ACCUM_ALPHA_BITS = 0x0D5B;
enum GL_INDEX_BITS = 0x0D51;
enum GL_DOUBLEBUFFER = 0x0C32;
enum GL_STEREO = 0x0C33;
enum GL_SAMPLES = 0x80A9;
enum GL_RENDERER = 0x1F01;
enum GL_VERSION = 0x1F02;
enum GL_EXTENSIONS = 0x1F03;

// glPixelStorei names
enum GL_PACK_ALIGNMENT = 0x0D05;
enum GL_PACK_ROW_LENGTH = 0x0D02;
enum GL_PACK_SKIP_ROWS = 0x0D03;
enum GL_PACK_SKIP_PIXELS = 0x0D04;
enum GL_UNPACK_ALIGNMENT = 0x0CF5;
enum GL_UNPACK_ROW_LENGTH = 0x0CF2;
enum GL_UNPACK_SKIP_ROWS = 0x0CF3;
enum GL_UNPACK_SKIP_PIXELS = 0x0CF4;

// glPushAttrib mask (individual bits; GL_COLOR_BUFFER_BIT is already
// declared above for glClear() and reuses the same value here, matching
// real GL/gl.h)
enum GL_ALL_ATTRIB_BITS = 0xFFFFFFFF;
enum GL_TRANSFORM_BIT = 0x00001000;
enum GL_ENABLE_BIT = 0x00002000;
enum GL_TEXTURE_BIT = 0x00040000;

// glPushClientAttrib mask
enum GL_CLIENT_PIXEL_STORE_BIT = 0x00000001;

// Texture parameters
enum GL_TEXTURE_WIDTH = 0x1000;
enum GL_TEXTURE_HEIGHT = 0x1001;
enum GL_TEXTURE_MIN_FILTER = 0x2801;
enum GL_TEXTURE_MAG_FILTER = 0x2800;
enum GL_NEAREST = 0x2600;
enum GL_LINEAR = 0x2601;
enum GL_ALPHA = 0x1906;
enum GL_LUMINANCE = 0x1909;
enum GL_LUMINANCE_ALPHA = 0x190A;
enum GL_ALPHA8 = 0x803C;

// GL_EXT_texture_rectangle / GL_ARB_texture_rectangle (fl.gl's own
// texture-cache text rendering -- see that module's own doc comment
// for why no runtime fallback path exists)
enum GL_TEXTURE_RECTANGLE_ARB = 0x84F5;

// glListBase / display lists
// (no extra constants needed beyond the functions themselves)

void glBegin(GLenum mode);
void glDrawArrays(GLenum mode, GLint first, GLsizei count);
void glEnd();
void glVertex2i(GLint x, GLint y);
void glVertex2f(GLfloat x, GLfloat y);
void glVertex2d(GLdouble x, GLdouble y);
void glVertex3f(GLfloat x, GLfloat y, GLfloat z);
void glVertex3d(GLdouble x, GLdouble y, GLdouble z);
void glColor3f(GLfloat r, GLfloat g, GLfloat b);
void glColor3ub(GLubyte r, GLubyte g, GLubyte b);
void glColor3ubv(const(GLubyte)* v);
void glColor4f(GLfloat r, GLfloat g, GLfloat b, GLfloat a);
void glColor4ub(GLubyte r, GLubyte g, GLubyte b, GLubyte a);
void glNormal3f(GLfloat nx, GLfloat ny, GLfloat nz);
void glNormal3fv(const(GLfloat)* v);
void glTexCoord2f(GLfloat s, GLfloat t);
void glRasterPos2i(GLint x, GLint y);
void glRasterPos2d(GLdouble x, GLdouble y);
void glRasterPos2f(GLfloat x, GLfloat y);
void glRasterPos3f(GLfloat x, GLfloat y, GLfloat z);
void glRecti(GLint x1, GLint y1, GLint x2, GLint y2);

void glClear(GLbitfield mask);
void glClearColor(GLclampf r, GLclampf g, GLclampf b, GLclampf a);
void glClearDepth(GLclampd depth);
void glFlush();
void glFinish();

void glCullFace(GLenum mode);
void glShadeModel(GLenum mode);
void glColorMaterial(GLenum face, GLenum mode);
void glLightfv(GLenum light, GLenum pname, const(GLfloat)* params);
void glLightModelfv(GLenum pname, const(GLfloat)* params);
void glMaterialfv(GLenum face, GLenum pname, const(GLfloat)* params);

// Selection-mode (picking) API -- glpuzzle.d's own click-to-select-a-
// puzzle-piece implementation.
void glInitNames();
void glPushName(GLuint name);
void glLoadName(GLuint name);
GLint glRenderMode(GLenum mode);
void glSelectBuffer(GLsizei size, GLuint* buffer);

void glMatrixMode(GLenum mode);
void glLoadIdentity();
void glLoadMatrixf(const(GLfloat)* m);
void glLoadMatrixd(const(GLdouble)* m);
void glMultMatrixf(const(GLfloat)* m);
void glMultMatrixd(const(GLdouble)* m);
void glPushMatrix();
void glPopMatrix();
void glOrtho(GLdouble left, GLdouble right, GLdouble bottom, GLdouble top,
    GLdouble near, GLdouble far);
void glFrustum(GLdouble left, GLdouble right, GLdouble bottom, GLdouble top,
    GLdouble near, GLdouble far);
void glTranslatef(GLfloat x, GLfloat y, GLfloat z);
void glTranslated(GLdouble x, GLdouble y, GLdouble z);
void glScalef(GLfloat x, GLfloat y, GLfloat z);
void glScaled(GLdouble x, GLdouble y, GLdouble z);
void glRotatef(GLfloat angle, GLfloat x, GLfloat y, GLfloat z);
void glRotated(GLdouble angle, GLdouble x, GLdouble y, GLdouble z);
void glViewport(GLint x, GLint y, GLsizei w, GLsizei h);

void glEnable(GLenum cap);
void glDisable(GLenum cap);
void glDepthFunc(GLenum func);
GLboolean glIsEnabled(GLenum cap);
void glBlendFunc(GLenum sfactor, GLenum dfactor);
void glLineWidth(GLfloat width);
void glPointSize(GLfloat size);

void glDrawBuffer(GLenum mode);
void glReadBuffer(GLenum mode);
void glCopyPixels(GLint x, GLint y, GLsizei w, GLsizei h, GLenum type);
void glDrawPixels(GLsizei w, GLsizei h, GLenum format, GLenum type, const(void)* pixels);
void glReadPixels(GLint x, GLint y, GLsizei w, GLsizei h, GLenum format,
    GLenum type, void* pixels);
void glPixelStorei(GLenum pname, GLint param);
void glPixelZoom(GLfloat xfactor, GLfloat yfactor);

void glPushAttrib(GLbitfield mask);
void glPopAttrib();
void glPushClientAttrib(GLbitfield mask);
void glPopClientAttrib();

void glGetIntegerv(GLenum pname, GLint* params);
void glGetFloatv(GLenum pname, GLfloat* params);
void glGetDoublev(GLenum pname, GLdouble* params);
void glGetBooleanv(GLenum pname, GLboolean* params);
const(GLubyte)* glGetString(GLenum name);
void glGetTexLevelParameteriv(GLenum target, GLint level, GLenum pname, GLint* params);

GLuint glGenLists(GLsizei range);
void glDeleteLists(GLuint list, GLsizei range);
void glListBase(GLuint base);
void glCallList(GLuint list);
void glCallLists(GLsizei n, GLenum type, const(void)* lists);
void glNewList(GLuint list, GLenum mode);
void glEndList();

void glGenTextures(GLsizei n, GLuint* textures);
void glDeleteTextures(GLsizei n, const(GLuint)* textures);
void glBindTexture(GLenum target, GLuint texture);
void glTexImage2D(GLenum target, GLint level, GLint internalformat, GLsizei w,
    GLsizei h, GLint border, GLenum format, GLenum type, const(void)* pixels);
void glTexParameteri(GLenum target, GLenum pname, GLint param);

void glScissor(GLint x, GLint y, GLsizei w, GLsizei h);

// Line stipple (fl.gl_graphics_driver.GlGraphicsDriver.lineStyle())
enum GL_LINE_STIPPLE = 0x0B24;
void glLineStipple(GLint factor, GLushort pattern);

// Rectangles as filled quads, GLfloat coordinates (fl.gl_graphics_driver)
void glRectf(GLfloat x1, GLfloat y1, GLfloat x2, GLfloat y2);

// 3-component vertex from an array pointer (samples/test/cube.d's own
// v3f() helper -- FLTK's test/cube.cxx calls this directly too).
void glVertex3fv(const(GLfloat)* v);
