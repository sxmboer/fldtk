// D transliteration of FLTK's test/fracviewer.cxx + test/fracviewer.h.
// Shared module imported by fractals.d; not itself runnable (no
// main()), so it has no standalone binary -- see fractals.d for the
// driver and its build command.
//
// fracviewer.cxx/.h is "AGV" (Philip Winston's generic GLUT scene
// viewer, see the file banner ported below as a doc comment) -- free
// functions plus module-global camera state implementing polar-orbit
// and first-person "flying" navigation, driven by GLUT
// mouse/motion/keyboard callbacks and an idle function. It has nothing
// to do with test/mandelbrot.h, which belongs to a different,
// Fluid-generated program.
//
// fldtk has real OpenGL/GLU/GLUT bindings (`fl.opengl`/`fl.glu`/
// `fl.glut`, plus a real `fl.gl_window`) -- every gl*/glu*/glut* call
// and type below resolves to real, typed declarations, matching the
// same `fl.opengl`/`fl.glu` imports cube.d/shape.d/gl_overlay.d/
// glut_test.d already use (`fl.glut` itself is re-exported through the
// `fl` package, so it needs no explicit import of its own). This
// program's *own* free functions (not a foreign API -- Philip Winston's
// original C code, kept as free functions rather than a class, matching
// fl.core's "module is the namespace" convention for what FLTK
// expresses as C globals/functions instead of a class) keep their
// FLTK `agv`-prefixed names verbatim too.
//
// Invented/adjusted vs. a byte-for-byte transliteration:
//  - MovementType is a closed 2-value tag set (`typedef enum { FLYING,
//    POLAR }`), so per CONVENTIONS.md it becomes a real D enum
//    (`flying`/`polar`) rather than an alias+constants pair. moveMode
//    itself stays plain `int` (not MovementType) because
//    agvSwitchMoveMode is registered directly as a GLUT menu callback
//    in fractals.d (`glutCreateMenu(&agvSwitchMoveMode)`), which
//    requires the exact `void(int)` signature GLUT expects -- matching
//    FLTK's own `void agvSwitchMoveMode(int move)` (not
//    `MovementType`) for the same reason.
//  - `#define`d numeric settings (INIT_POLAR_AZ, TORAD/TODEG, etc.)
//    become D `enum` manifest constants / private helper functions.
//  - C's implicit bool->numeric conversion in `agvMakeAxesList`'s
//    `trans*(i==0)` / `glTranslatef(i==0, i==1, i==2)` needs an
//    explicit cast in D (bool doesn't implicitly widen inside these
//    float expressions the way a C `int` comparison result does).
module fracviewer;

import fl;
import std.math : sin, cos, sqrt, fabs = abs, PI;
import std.stdio : stderr;

/*
 * fracviewer.d [from agviewer.h/.c (version 1.0)]
 *
 * AGV: a glut viewer. Routines for viewing a 3d scene w/ glut
 *
 * The two view movement modes are POLAR and FLYING. Both move the eye,
 * NOT THE OBJECT. You can never be upside down or twisted (roll) in
 * either mode.
 *
 * Controls for Polar are just left and middle buttons -- for flying
 * it's those plus 0-9 number keys and +/- for speed adjustment.
 *
 * Philip Winston - 4/11/95
 * pwinston@hmc.edu
 */

/***************************************************************/
/************************** SETTINGS ***************************/
/***************************************************************/

// Initial polar movement settings
private enum float initPolarAz = 0.0f;
private enum float initPolarEl = 30.0f;
private enum float initDist = 4.0f;
private enum float initAzSpin = 0.5f;
private enum float initElSpin = 0.0f;

// Initial flying movement settings
private enum float initEx = 0.0f;
private enum float initEy = -2.0f;
private enum float initEz = -2.0f;
private enum float initMove = 0.01f;
private enum float minMove = 0.001f;

/// Set which movement mode you are in.
enum MovementType { flying, polar }

// Start in this mode
private enum MovementType initMode = MovementType.polar;

// map 0-9 to an EyeMove value when number key is hit in FLYING mode
private float speedFunction(float x) { return x * x * 0.001f; }

// Multiply EyeMove by (1+-MOVEFRACTION) when +/- hit in FLYING mode
private enum float moveFraction = 0.25f;

// What to multiply number of pixels mouse moved by to get rotation amount
private enum float elSens = 0.5f;
private enum float azSens = 0.5f;

// What to multiply number of pixels mouse moved by for movement amounts
private enum float distSens = 0.01f;
private enum float eSens = 0.01f;

// Minimum spin to allow in polar (lower forced to zero)
private enum float minAzSpin = 0.1f;
private enum float minElSpin = 0.1f;

// Factors used in computing dAz and dEl (which determine AzSpin, ElSpin)
private enum float slowDAz = 0.90f;
private enum float slowDEl = 0.90f;
private enum float prevDAz = 0.80f;
private enum float prevDEl = 0.80f;
private enum float curDAz = 0.20f;
private enum float curDEl = 0.20f;

private double toRad(double x) { return (PI / 180.0) * x; }
private double toDeg(double x) { return (180.0 / PI) * x; }

/***************************************************************/
/************************** GLOBALS ****************************/
/***************************************************************/

int moveMode = initMode; // FLYING or POLAR mode?

GLfloat ex = initEx,     // flying parameters
        ey = initEy,
        ez = initEz,
        eyeMove = initMove,

        eyeDist = initDist, // polar params
        azSpin  = initAzSpin,
        elSpin  = initElSpin,

        eyeAz = initPolarAz, // used by both
        eyeEl = initPolarEl;

int agvMoving; // Currently moving?

int downx, downy,  // for tracking mouse position
    lastx, lasty,
    downb = -1;     // and button status

GLfloat downDist, downEl, downAz, // for saving state of things
        downEx, downEy, downEz,   // when button is pressed
        downEyeMove;

GLfloat dAz, dEl, lastAz, lastEl; // to calculate spinning w/ polar motion
int     adjustingAzEl = 0;

int allowIdle, redisplayWindow;
// If allowIdle is 1 it means AGV will install its own idle which will
// update the viewpoint as needed and send glutPostRedisplay() to the
// window redisplayWindow which was set in agvInit(). allowIdle of 0
// means AGV won't install an idle function, and something like
// "if (agvMoving) agvMove();" should exist at the end of the running
// idle function.

/***************************************************************/
/************************ agvInit ******************************/
/***************************************************************/

/*
 * Call agvInit() with glut's current window set to the window in
 * which you want to run the viewer. It registers mouse, motion, and
 * keyboard handlers for that window.
 */
void agvInit(int window)
{
    glutMouseFunc(&agvHandleButton);
    glutMotionFunc(&agvHandleMotion);
    glutKeyboardFunc(&agvHandleKeys);
    redisplayWindow = glutGetWindow();
    agvSetAllowIdle(window);
}

/***************************************************************/
/************************ VIEWPOINT STUFF **********************/
/***************************************************************/

// viewing transformation modified from page 90 of red book
void polarLookFrom(GLfloat dist, GLfloat elevation, GLfloat azimuth)
{
    glTranslatef(0, 0, -dist);
    glRotatef(elevation, 1, 0, 0);
    glRotatef(azimuth, 0, 1, 0);
}

// I took the idea of tracking eye position in absolute coords and
// direction looking in Polar form from denis
void flyLookFrom(GLfloat x, GLfloat y, GLfloat z, GLfloat az, GLfloat el)
{
    float[3] lookat, perp, up;

    lookat[0] = cast(GLfloat)(sin(toRad(az)) * cos(toRad(el)));
    lookat[1] = cast(GLfloat)(sin(toRad(el)));
    lookat[2] = cast(GLfloat)(-cos(toRad(az)) * cos(toRad(el)));
    normalize(lookat);
    perp[0] = lookat[2];
    perp[1] = 0;
    perp[2] = -lookat[0];
    normalize(perp);
    ncrossprod(lookat, perp, up);
    gluLookAt(x, y, z,
              x + lookat[0], y + lookat[1], z + lookat[2],
              up[0], up[1], up[2]);
}

/// Call viewing transformation based on movement mode
void agvViewTransform()
{
    switch (moveMode)
    {
    case MovementType.flying:
        flyLookFrom(ex, ey, ez, eyeAz, eyeEl);
        break;
    case MovementType.polar:
        polarLookFrom(eyeDist, eyeEl, eyeAz);
        break;
    default:
        break;
    }
}

// keep them vertical; makes a lot of things easier
int constrainEl()
{
    if (eyeEl <= -90)
    {
        eyeEl = -89.99f;
        return 1;
    }
    else if (eyeEl >= 90)
    {
        eyeEl = 89.99f;
        return 1;
    }
    return 0;
}

/// Idle Function - moves eyeposition
void agvMove()
{
    switch (moveMode)
    {
    case MovementType.flying:
        ex += cast(GLfloat)(eyeMove * sin(toRad(eyeAz)) * cos(toRad(eyeEl)));
        ey += cast(GLfloat)(eyeMove * sin(toRad(eyeEl)));
        ez -= cast(GLfloat)(eyeMove * cos(toRad(eyeAz)) * cos(toRad(eyeEl)));
        break;

    case MovementType.polar:
        eyeEl += elSpin;
        eyeAz += azSpin;
        if (constrainEl())
        {
            // weird spin thing to make things look better when you are
            // kept from going upside down while spinning - isn't great
            elSpin = -elSpin;
            if (fabs(elSpin) > fabs(azSpin))
                azSpin = cast(GLfloat)(fabs(elSpin) * ((azSpin > 0.0f) ? 1.0f : -1.0f));
        }
        break;
    default:
        break;
    }

    if (adjustingAzEl)
    {
        dAz *= slowDAz;
        dEl *= slowDEl;
    }

    if (allowIdle)
    {
        glutSetWindow(redisplayWindow);
        glutPostRedisplay();
    }
}

// Don't install agvMove as idle unless we will be updating the view
// and we've been given a redisplayWindow
void moveOn(int v)
{
    if (v && ((moveMode == MovementType.flying && eyeMove != 0) ||
              (moveMode == MovementType.polar &&
               (azSpin != 0 || elSpin != 0 || adjustingAzEl))))
    {
        agvMoving = 1;
        if (allowIdle)
            glutIdleFunc(&agvMove);
    }
    else
    {
        agvMoving = 0;
        if (allowIdle)
            glutIdleFunc(null);
    }
}

// set new redisplay window. If <= 0 it means we are not to install an
// idle function and will rely on whoever does install one to put a
// statement like "if (agvMoving) agvMove();" at the end of it
void agvSetAllowIdle(int allowidle)
{
    allowIdle = allowidle;
    if (allowIdle)
        moveOn(1);
}

// when moving to flying we stay in the same spot, moving to polar we
// reset since we have to be looking at the origin
void agvSwitchMoveMode(int move)
{
    switch (move)
    {
    case MovementType.flying:
        if (moveMode == MovementType.flying) return;
        ex    = cast(GLfloat)(-eyeDist * sin(toRad(eyeAz)) * cos(toRad(eyeEl)));
        ey    = cast(GLfloat)( eyeDist * sin(toRad(eyeEl)));
        ez    = cast(GLfloat)( eyeDist * (cos(toRad(eyeAz)) * cos(toRad(eyeEl))));
        eyeEl = -eyeEl;
        eyeMove = initMove;
        break;
    case MovementType.polar:
        eyeDist = initDist;
        eyeAz   = initPolarAz;
        eyeEl   = initPolarEl;
        azSpin  = initAzSpin;
        elSpin  = initElSpin;
        break;
    default:
        break;
    }
    moveMode = move;
    moveOn(1);
    glutPostRedisplay();
}

/***************************************************************/
/*******************    MOUSE HANDLING   ***********************/
/***************************************************************/

void agvHandleButton(int button, int state, int x, int y)
{
    // deal with mouse wheel events, that fltk sends as buttons 3 or 4
    if ((state == GLUT_DOWN) && ((button == 3) || (button == 4)))
    {
        // attempt to process scrollwheel as zoom in/out
        float deltay = 0.25;
        if (button == 3)
            deltay = -0.25;
        downb = -1;
        downDist = eyeDist;
        downEx = ex;
        downEy = ey;
        downEz = ez;
        downEyeMove = eyeMove;
        eyeMove = 0;

        eyeDist = downDist + deltay;
        ex = cast(GLfloat)(downEx - eSens * deltay * sin(toRad(eyeAz)) * cos(toRad(eyeEl)));
        ey = cast(GLfloat)(downEy - eSens * deltay * sin(toRad(eyeEl)));
        ez = cast(GLfloat)(downEz + eSens * deltay * cos(toRad(eyeAz)) * cos(toRad(eyeEl)));

        eyeMove = downEyeMove;
        glutPostRedisplay();
        return;
    }
    else if (button > GLUT_RIGHT_BUTTON)
        return; // ignore any other button...

    if (state == GLUT_DOWN && downb == -1)
    {
        lastx = downx = x;
        lasty = downy = y;
        downb = button;

        switch (button)
        {
        case GLUT_LEFT_BUTTON:
            lastEl = downEl = eyeEl;
            lastAz = downAz = eyeAz;
            azSpin = elSpin = dAz = dEl = 0;
            adjustingAzEl = 1;
            moveOn(1);
            break;

        case GLUT_MIDDLE_BUTTON:
            downDist = eyeDist;
            downEx = ex;
            downEy = ey;
            downEz = ez;
            downEyeMove = eyeMove;
            eyeMove = 0;
            break;
        default:
            break;
        }
    }
    else if (state == GLUT_UP && button == downb)
    {
        downb = -1;

        switch (button)
        {
        case GLUT_LEFT_BUTTON:
            if (moveMode != MovementType.flying)
            {
                azSpin = -dAz;
                if (azSpin < minAzSpin && azSpin > -minAzSpin)
                    azSpin = 0;
                elSpin = -dEl;
                if (elSpin < minElSpin && elSpin > -minElSpin)
                    elSpin = 0;
            }
            adjustingAzEl = 0;
            moveOn(1);
            break;

        case GLUT_MIDDLE_BUTTON:
            eyeMove = downEyeMove;
            break;
        default:
            break;
        }
    }
}

// change EyeEl and EyeAz and position when mouse is moved w/ button down
void agvHandleMotion(int x, int y)
{
    int deltax = x - downx, deltay = y - downy;

    switch (downb)
    {
    case GLUT_LEFT_BUTTON:
        eyeEl  = cast(GLfloat)(downEl + elSens * deltay);
        constrainEl();
        eyeAz  = cast(GLfloat)(downAz + azSens * deltax);
        dAz    = cast(GLfloat)(prevDAz * dAz + curDAz * (lastAz - eyeAz));
        dEl    = cast(GLfloat)(prevDEl * dEl + curDEl * (lastEl - eyeEl));
        lastAz = eyeAz;
        lastEl = eyeEl;
        break;
    case GLUT_MIDDLE_BUTTON:
        eyeDist = cast(GLfloat)(downDist + distSens * deltay);
        ex = cast(GLfloat)(downEx - eSens * deltay * sin(toRad(eyeAz)) * cos(toRad(eyeEl)));
        ey = cast(GLfloat)(downEy - eSens * deltay * sin(toRad(eyeEl)));
        ez = cast(GLfloat)(downEz + eSens * deltay * cos(toRad(eyeAz)) * cos(toRad(eyeEl)));
        break;
    default:
        break;
    }
    glutPostRedisplay();
}

/***************************************************************/
/********************* KEYBOARD HANDLING ***********************/
/***************************************************************/

// set EyeMove (current speed) for FLYING mode
void setMove(float newmove)
{
    if (newmove > minMove)
    {
        eyeMove = newmove;
        moveOn(1);
    }
    else
    {
        eyeMove = 0;
        moveOn(0);
    }
}

// 0->9 set speed, +/- adjust current speed -- in FLYING mode
void agvHandleKeys(ubyte key, int, int)
{
    if (moveMode != MovementType.flying)
        return;

    if (key >= '0' && key <= '9')
        setMove(speedFunction(key - '0'));
    else
        switch (key)
        {
        case '+':
            if (eyeMove == 0)
                setMove(minMove);
            else
                setMove(eyeMove *= (1 + moveFraction));
            break;
        case '-':
            setMove(eyeMove *= (1 - moveFraction));
            break;
        default:
            break;
        }
}

/***************************************************************/
/*********************** VECTOR STUFF **************************/
/***************************************************************/

// normalizes v
private void normalize(ref GLfloat[3] v)
{
    GLfloat d = cast(GLfloat) sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);

    if (d == 0)
        stderr.writeln("Zero length vector in normalize");
    else
    {
        v[0] /= d;
        v[1] /= d;
        v[2] /= d;
    }
}

// calculates a normalized crossproduct to v1, v2
void ncrossprod(float[3] v1, float[3] v2, ref float[3] cp)
{
    cp[0] = v1[1] * v2[2] - v1[2] * v2[1];
    cp[1] = v1[2] * v2[0] - v1[0] * v2[2];
    cp[2] = v1[0] * v2[1] - v1[1] * v2[0];
    normalize(cp);
}

/***************************************************************/
/**************************** AXES *****************************/
/***************************************************************/

// draw axes -- was helpful to debug/design things
void agvMakeAxesList(int displaylistnum)
{
    GLfloat[4] axesAmbuse = [0.5, 0.0, 0.0, 1.0];
    GLfloat trans = -10;
    glNewList(displaylistnum, GL_COMPILE);
    glPushAttrib(GL_LIGHTING_BIT);
    glMatrixMode(GL_MODELVIEW);
    glMaterialfv(GL_FRONT, GL_AMBIENT_AND_DIFFUSE, axesAmbuse.ptr);
    glBegin(GL_LINES);
    glVertex3f(15, 0, 0); glVertex3f(-15, 0, 0);
    glVertex3f(0, 15, 0); glVertex3f(0, -15, 0);
    glVertex3f(0, 0, 15); glVertex3f(0, 0, -15);
    glEnd();
    for (int i = 0; i < 3; i++)
    {
        glPushMatrix();
        // C's implicit bool->int conversion made explicit here (see
        // header note)
        glTranslatef(trans * cast(GLfloat)(i == 0), trans * cast(GLfloat)(i == 1), trans * cast(GLfloat)(i == 2));
        for (int j = 0; j < 21; j++)
        {
            glTranslatef(cast(GLfloat)(i == 0), cast(GLfloat)(i == 1), cast(GLfloat)(i == 2));
        }
        glPopMatrix();
    }
    glPopAttrib();
    glEndList();
}
