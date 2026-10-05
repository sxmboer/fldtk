/*
 * Minimal bindings for GLU (`GL/glu.h`), the OpenGL Utility Library.
 * Infrastructure, not a port of an FLTK header -- same role `fl.glx`
 * plays for GLX and `fl.opengl` plays for core GL (see those modules'
 * own doc comments): hand-written declarations linked against the
 * system GLU library, not a reimplementation
 * of GLU's own quadric-tessellation geometry logic -- there would be no
 * point rewriting `gluCylinder()`'s math when the whole point of GLU is
 * that reusable implementation, and `libGLU.so` is a standard, always-
 * present part of any Linux OpenGL install (Mesa ships it unconditionally
 * alongside `libGL.so`).
 *
 * Only the 7 functions the GLUT-based samples this port's own
 * GLUT-compatibility work (`fl.glut`, see that module's own doc comment)
 * actually call are declared -- verified by grepping every `glu*` call
 * site across `source/test/glut_test.d`/`glpuzzle.d`/`fractals.d`/
 * `fracviewer.d` and `source/examples/OpenGL3_glut_test.d`/
 * `OpenGL3test.d` (the full set of GLUT-dependent samples):
 * `gluNewQuadric`/`gluCylinder`/`gluDeleteQuadric` (glpuzzle.d's trackball
 * puzzle geometry), `gluLookAt`/`gluPerspective`/`gluPickMatrix`
 * (fracviewer.d's camera), `gluOrtho2D` (fractals.d's 2D overlay
 * projection). GLU's own quadric-sphere/disk/partial-disk functions
 * (`gluSphere`/`gluDisk`/`gluPartialDisk`) and its NURBS/tessellator
 * subsystems have zero call sites in this port's sample tree and aren't
 * declared here -- add them the same way (a direct `extern(C)`
 * declaration, GLU's own C ABI needs no wrapping) if a future sample
 * needs them.
 *
 * Linux and Windows (`version (linux)`/`version (Windows)`) -- GLU is a
 * standard part of any Windows OpenGL install too, `glu32.dll`/`GLU32.lib`
 * shipping alongside `opengl32.dll` since Windows 95/NT (confirmed by
 * reading the real FLTK `FL/glu.h`: on Windows
 * it's `#include <windows.h>` followed by the plain system `<GL/glu.h>`,
 * no different from any other Windows OpenGL header -- no GLEW-style
 * runtime extension resolution needed, unlike `fl.glew`, since GLU's ABI
 * has been stable and directly linkable on every platform since GLU 1.3).
 * Real `GL/glu.h` declares every function `GLAPI ... GLAPIENTRY`, i.e.
 * `__stdcall` on Windows (`APIENTRY`) -- `extern (System)` here matches
 * that exactly, the same convention `fl.opengl` already uses for core GL
 * and for the identical reason (see that module's own doc comment).
 */
module fl.glu;

version (linux) version = FldtkGlu;
version (Windows) version = FldtkGlu;

version (FldtkGlu):

import fl.opengl : GLint, GLenum, GLdouble;

extern (System):
@nogc:
nothrow:

// Opaque GLU quadric object handle -- only ever created/destroyed/passed
// to gluCylinder(), never inspected field-by-field, same treatment
// fl.glx gives GLXContext.
struct GLUquadric;

GLUquadric* gluNewQuadric();
void gluDeleteQuadric(GLUquadric* quad);
void gluCylinder(GLUquadric* quad, GLdouble base, GLdouble top, GLdouble height,
    GLint slices, GLint stacks);

void gluLookAt(GLdouble eyeX, GLdouble eyeY, GLdouble eyeZ,
    GLdouble centerX, GLdouble centerY, GLdouble centerZ,
    GLdouble upX, GLdouble upY, GLdouble upZ);
void gluPerspective(GLdouble fovy, GLdouble aspect, GLdouble zNear, GLdouble zFar);
void gluOrtho2D(GLdouble left, GLdouble right, GLdouble bottom, GLdouble top);
void gluPickMatrix(GLdouble x, GLdouble y, GLdouble delX, GLdouble delY, GLint* viewport);
