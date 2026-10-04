// D transliteration of FLTK's test/fractals.cxx (~/Repositories/fltk),
// linked with fracviewer.cxx/.h (see fracviewer.d).
// Part of the samples/ contract -- see samples/README.md.
// Check: ./samples/build.sh fractals
//
// See fracviewer.d's header comment for an important note: despite
// MANIFEST.json listing test/mandelbrot.h among this program's FLTK
// sources, FLTK's actual test/fractals.cxx is a GLUT fractal-mountain /
// fractal-tree / fractal-island demo (a homework assignment by Philip
// Winston, adapted to run its GLUT window as a child of an FLTK
// window) that shares camera-control code with fracviewer.cxx/.h. It
// has nothing to do with Mandelbrot/Julia sets. This port follows the
// real source.
//
// fldtk has real OpenGL/GLU/GLUT bindings (`fl.opengl`/`fl.glu`/
// `fl.glut`) -- every gl*/glu*/glut* call and type below resolves to
// real, typed declarations, `fl.glut` re-exported through the `fl`
// package itself (unlike `fl.opengl`/`fl.glu`, which still need their
// own explicit imports below, matching every other GL sample).
//
// Invented/adjusted vs. a byte-for-byte transliteration:
//  - DisplayLists (glNewList/glCallList indices) and MenuChoices are
//    closed tag sets (`typedef enum`s FLTK), so per CLAUDE.md they
//    become real D enums rather than a `#define`-style int list.
//    `fractal`/`Rebuild`/`Level`/`DrawAxes` stay plain `int` globals
//    (matching FLTK) since `fractal` in particular is compared
//    against and assigned from these enums interchangeably with plain
//    ints throughout (implicit enum->int conversion covers this).
//  - FLTK's `Fl_Callback`+`void*` adapter overloads
//    (`setlevel(Fl_Widget*, void*)` etc., which just unwrapped the
//    `void*` back into an int and called the GLUT-style `setlevel(int)`
//    /`choosefract(int)`/`handlemenu(int)`) are dropped entirely, per
//    CLAUDE.md's callback convention: a D delegate closes over its
//    data directly, so every `Fl_Button` callback below is a small
//    lambda capturing the int literal it needs
//    (`b.callback((w) { setlevel(0); });`) instead of stashing it in a
//    `void*` argument.
//  - The FLTK global `Pegged[3]` is renamed `peggedEdges` (kept
//    `Verts`/`Slopes` -> `verts`/`slopes` as-is) purely to avoid
//    colliding with `fractalMountain`'s same-named `pegged` parameter
//    once both are lowercased to this project's camelCase convention
//    (FLTK's case-sensitive `Pegged`/`pegged` distinction doesn't
//    survive that lowercasing).
//  - `snprintf`+`char buf[255]` for the on-screen FPS string becomes a
//    plain `std.format.format` call returning a D `string`, matching
//    CLAUDE.md's `label()`/`tooltip()` precedent of preferring GC
//    strings over manual C buffers.
import fl;
import fracviewer;

import std.math : fabs = abs;
import std.format : format;
import std.stdio : stderr;
import std.datetime.systime : Clock;
import std.random : unpredictableSeed, Random, uniform01;

// core.sys.posix.stdlib's drand48()/srand48() are POSIX-only -- not
// part of the Windows CRT at all, so no core.sys.posix substitute
// exists there either (unlike usleep()/popen(), which at least compile
// out silently and only fail at the call site -- see this project's own
// notes on core.sys.posix's version(Posix): guard). Both call sites
// here only need "reseed, then draw one or more values" determinism
// (a mixing/hash function for shared fractal-terrain edges, and
// reproducible-tree-at-a-different-zoom-level playback) -- not
// drand48()'s specific 48-bit LCG algorithm or bit-identical output
// across runs/platforms, so a portable std.random.Random seeded the
// same way is a faithful substitute for what this code actually needs.
private Random rng48_;
private void srand48(long seed) { rng48_.seed(cast(uint) seed); }
private double drand48() { return uniform01(rng48_); }

/*
 * fractals.d [from fractals.cxx / fractals.c]
 *
 * This is a GLUT demo program, with modifications to demonstrate how
 * to add FLTK controls to a GLUT program. The GLUT code is unchanged
 * except for the end (search for FLTK to find changes).
 *
 * Draws fractal mountains and trees -- and an island of mountains in
 * water.
 *
 * Two viewer modes: polar and flying (both restrained to y>0 for up
 * vector). Keyboard 0->9 and +/- control speed when flying.
 *
 * Philip Winston - 3/4/95
 * pwinston@hmc.edu
 */

/// glNewList()/glCallList() display-list indices.
enum DisplayLists
{
    notAllowed, mountain, tree, island, bigMtn, stem, leaf,
    mountainMat, waterMat, leafMat, treeMat, stemAndLeaves,
    axes
}

// Note: maxLevel is the highest level, range is 0..maxLevel
enum int maxLevel = 8;

int rebuild = 1,             // Rebuild display list in next display?
    fractal = DisplayLists.tree, // What fractal are we building
    level   = 4;              // levels of recursion for fractals

int drawAxes = 0;

/***************************************************************/
/************************* VECTOR JUNK *************************/
/***************************************************************/

// print vertex to stderr
void printvert(float[3] v)
{
    stderr.writefln("(%f, %f, %f)", v[0], v[1], v[2]);
}

// calculates normal to the triangle designated by v1, v2, v3
void triagnormal(float[3] v1, float[3] v2, float[3] v3, ref float[3] norm)
{
    float[3] vec1, vec2;

    vec1[0] = v3[0] - v1[0];  vec2[0] = v2[0] - v1[0];
    vec1[1] = v3[1] - v1[1];  vec2[1] = v2[1] - v1[1];
    vec1[2] = v3[2] - v1[2];  vec2[2] = v2[2] - v1[2];

    ncrossprod(vec2, vec1, norm);
}

float xzlength(float[3] v1, float[3] v2)
{
    import std.math : sqrt;

    return sqrt((v1[0] - v2[0]) * (v1[0] - v2[0]) +
                (v1[2] - v2[2]) * (v1[2] - v2[2]));
}

float xzslope(float[3] v1, float[3] v2)
{
    return (v1[0] != v2[0]) ? ((v1[2] - v2[2]) / (v1[0] - v2[0]))
                             : float.max;
}

/***************************************************************/
/************************ MOUNTAIN STUFF ***********************/
/***************************************************************/

GLfloat[maxLevel + 1] dispFactor; // Array of what to multiply random number
                                   // by for a given level to get midpoint
                                   // displacement
GLfloat[maxLevel + 1] dispBias;   // Array of what to add to random number
                                   // before multiplying it by dispFactor

enum int numRands = 191;
float[numRands] randTable; // hash table of random numbers so we can raise
                            // the same midpoints by the same amount

         // The following are for permitting an edge of a mountain to be
         // pegged so it won't be displaced up or down. This makes it
         // easier to setup scenes and makes a single mountain look better

GLfloat[3][3] verts;   // Vertices of outside edges of mountain
GLfloat[3] slopes;     // Slopes between these outside edges
int[3] peggedEdges;    // Is this edge pegged or not (see header note --
                        // renamed from FLTK's `Pegged` to avoid
                        // colliding with fractalMountain()'s `pegged`
                        // parameter once lowercased)

/// Comes up with a new table of random numbers [0,1)
void initRandTable(uint seed)
{
    srand48(cast(int) seed);
    for (int i = 0; i < numRands; i++)
        randTable[i] = cast(float)(drand48() - 0.5);
}

// calculate midpoint and displace it if required
void midpoint(ref GLfloat[3] mid, GLfloat[3] v1, GLfloat[3] v2, int edge, int lvl)
{
    uint hash;

    mid[0] = (v1[0] + v2[0]) / 2;
    mid[1] = (v1[1] + v2[1]) / 2;
    mid[2] = (v1[2] + v2[2]) / 2;
    if (!peggedEdges[edge] || (fabs(xzslope(verts[edge], mid) - slopes[edge]) > 0.00001))
    {
        srand48(cast(int)((v1[0] + v2[0]) * 23344));
        hash = cast(uint)(drand48() * 7334334);
        srand48(cast(int)((v2[2] + v1[2]) * 43433));
        hash = cast(uint)(drand48() * 634344 + hash) % numRands;
        mid[1] += (randTable[hash] + dispBias[lvl]) * dispFactor[lvl];
    }
}

// Recursive mountain drawing routine -- from lecture with addition of
// allowing an edge to be pegged. This function requires the above
// globals to be set, as well as the `level` global for fractal level.
private float cutoff = -1;

void fmr(GLfloat[3] v1, GLfloat[3] v2, GLfloat[3] v3, int lvl)
{
    if (lvl == level)
    {
        GLfloat[3] norm;
        if (v1[1] <= cutoff && v2[1] <= cutoff && v3[1] <= cutoff) return;
        triagnormal(v1, v2, v3, norm);
        glNormal3fv(norm.ptr);
        glVertex3fv(v1.ptr);
        glVertex3fv(v2.ptr);
        glVertex3fv(v3.ptr);
    }
    else
    {
        GLfloat[3] m1, m2, m3;

        midpoint(m1, v1, v2, 0, lvl);
        midpoint(m2, v2, v3, 1, lvl);
        midpoint(m3, v3, v1, 2, lvl);

        fmr(v1, m1, m3, lvl + 1);
        fmr(m1, v2, m2, lvl + 1);
        fmr(m3, m2, v3, lvl + 1);
        fmr(m1, m2, m3, lvl + 1);
    }
}

// sets up lookup tables and calls recursive mountain function
void fractalMountain(GLfloat[3] v1, GLfloat[3] v2, GLfloat[3] v3, int[3] pegged)
{
    GLfloat[maxLevel + 1] lengths;
    GLfloat[8] fraction = [0.3f, 0.3f, 0.4f, 0.2f, 0.3f, 0.2f, 0.4f, 0.4f];
    GLfloat[8] bias     = [0.1f, 0.1f, 0.1f, 0.1f, 0.1f, 0.1f, 0.1f, 0.1f];
    int i;
    float avglen = (xzlength(v1, v2) +
                    xzlength(v2, v3) +
                    xzlength(v3, v1) / 3);

    for (i = 0; i < 3; i++)
    {
        verts[0][i] = v1[i];       // set mountain vertex globals
        verts[1][i] = v2[i];
        verts[2][i] = v3[i];
        peggedEdges[i] = pegged[i];
    }

    slopes[0] = xzslope(verts[0], verts[1]); // set edge slope globals
    slopes[1] = xzslope(verts[1], verts[2]);
    slopes[2] = xzslope(verts[2], verts[0]);

    lengths[0] = avglen;
    for (i = 1; i < level; i++)
        lengths[i] = lengths[i - 1] / 2; // compute edge length for each level

    for (i = 0; i < level; i++) // dispFactor and dispBias arrays
    {
        dispFactor[i] = (lengths[i] * ((i <= 7) ? fraction[i] : fraction[7]));
        dispBias[i]   = ((i <= 7) ? bias[i] : bias[7]);
    }

    glBegin(GL_TRIANGLES);
    fmr(v1, v2, v3, 0); // issues no GL but vertex calls
    glEnd();
}

// draw a mountain and build the display list
void createMountain()
{
    GLfloat[3] v1 = [0, 0, -1], v2 = [-1, 0, 1], v3 = [1, 0, 1];
    int[3] pegged = [1, 1, 1];

    glNewList(DisplayLists.mountain, GL_COMPILE);
    glPushAttrib(GL_LIGHTING_BIT);
    glCallList(DisplayLists.mountainMat);
    fractalMountain(v1, v2, v3, pegged);
    glPopAttrib();
    glEndList();
}

// new random numbers to make a different mountain
void newMountain()
{
    initRandTable(unpredictableSeed);
}

/***************************************************************/
/***************************** TREE ****************************/
/***************************************************************/

long treeSeed; // for srand48 - remember so we can build "same tree" at
                // a different level

// recursive tree drawing thing, fleshed out from class notes pseudocode
void fractalTree(int lvl, long levelSeed)
{
    if (lvl == level)
    {
        glPushMatrix();
        glRotatef(cast(GLfloat)(drand48() * 180), 0, 1, 0);
        glCallList(DisplayLists.stemAndLeaves);
        glPopMatrix();
    }
    else
    {
        glCallList(DisplayLists.stem);
        glPushMatrix();
        glRotatef(cast(GLfloat)(drand48() * 180.0), 0.0f, 1.0f, 0.0f);
        glTranslatef(0.0f, 1.0f, 0.0f);
        glScalef(0.7f, 0.7f, 0.7f);

        srand48(levelSeed + 1);
        glPushMatrix();
        glRotatef(cast(GLfloat)(110.0 + drand48() * 40.0), 0.0f, 1.0f, 0.0f);
        glRotatef(cast(GLfloat)( 30.0 + drand48() * 20.0), 0.0f, 0.0f, 1.0f);
        fractalTree(lvl + 1, levelSeed + 4);
        glPopMatrix();

        srand48(levelSeed + 2);
        glPushMatrix();
        glRotatef(cast(GLfloat)(-130.0 + drand48() * 40.0), 0.0f, 1.0f, 0.0f);
        glRotatef(cast(GLfloat)(  30.0 + drand48() * 20.0), 0.0f, 0.0f, 1.0f);
        fractalTree(lvl + 1, levelSeed + 5);
        glPopMatrix();

        srand48(levelSeed + 3);
        glPushMatrix();
        glRotatef(cast(GLfloat)(-20.0 + drand48() * 40.0), 0.0f, 1.0f, 0.0f);
        glRotatef(cast(GLfloat)( 30.0 + drand48() * 20.0), 0.0f, 0.0f, 1.0f);
        fractalTree(lvl + 1, levelSeed + 6);
        glPopMatrix();

        glPopMatrix();
    }
}

// Create display lists for a leaf, a set of leaves, and a stem
void createTreeLists()
{
    auto cylquad = gluNewQuadric();

    glNewList(DisplayLists.stem, GL_COMPILE);
    glPushMatrix();
    glRotatef(-90.0f, 1.0f, 0.0f, 0.0f);
    gluCylinder(cylquad, 0.1, 0.08, 1, 10, 2);
    glPopMatrix();
    glEndList();

    glNewList(DisplayLists.leaf, GL_COMPILE); // jeff allen's leaf idea
    glBegin(GL_TRIANGLES);
    glNormal3f(-0.1f, 0.00f, 0.25f); // not normalized
    glVertex3f( 0.0f, 0.00f, 0.00f);
    glVertex3f(0.25f, 0.25f, 0.10f);
    glVertex3f(0.00f, 0.50f, 0.00f);

    glNormal3f( 0.10f, 0.00f, 0.25f);
    glVertex3f( 0.00f, 0.00f, 0.00f);
    glVertex3f( 0.00f, 0.50f, 0.00f);
    glVertex3f(-0.25f, 0.25f, 0.10f);
    glEnd();
    glEndList();

    glNewList(DisplayLists.stemAndLeaves, GL_COMPILE);
    glPushMatrix();
    glPushAttrib(GL_LIGHTING_BIT);
    glCallList(DisplayLists.stem);
    glCallList(DisplayLists.leafMat);
    for (int i = 0; i < 3; i++)
    {
        glTranslatef(0.0f, 0.333f, 0.0f);
        glRotatef(90.0f, 0.0f, 1.0f, 0.0f);
        glPushMatrix();
        glRotatef( 0.0f, 0.0f, 1.0f, 0.0f);
        glRotatef(50.0f, 1.0f, 0.0f, 0.0f);
        glCallList(DisplayLists.leaf);
        glPopMatrix();
        glPushMatrix();
        glRotatef(180.0f, 0.0f, 1.0f, 0.0f);
        glRotatef( 60.0f, 1.0f, 0.0f, 0.0f);
        glCallList(DisplayLists.leaf);
        glPopMatrix();
    }
    glPopAttrib();
    glPopMatrix();
    glEndList();

    gluDeleteQuadric(cylquad);
}

// draw and build display list for tree
void createTree()
{
    srand48(treeSeed);

    glNewList(DisplayLists.tree, GL_COMPILE);
    glPushMatrix();
    glPushAttrib(GL_LIGHTING_BIT);
    glCallList(DisplayLists.treeMat);
    glTranslatef(0, -1, 0);
    fractalTree(0, treeSeed);
    glPopAttrib();
    glPopMatrix();
    glEndList();
}

// new seed for a new tree (groan)
void newTree()
{
    treeSeed = cast(long) unpredictableSeed; // use an unpredictable value as random seed
}

/***************************************************************/
/*********************** FRACTAL PLANET ************************/
/***************************************************************/

void createIsland()
{
    cutoff = 0.06f;
    createMountain();
    cutoff = -1;
    glNewList(DisplayLists.island, GL_COMPILE);
    glPushAttrib(GL_LIGHTING_BIT);
    glMatrixMode(GL_MODELVIEW);
    glPushMatrix();
    glCallList(DisplayLists.waterMat);

    glBegin(GL_QUADS);
    glNormal3f(  0.0f, 1.00f,   0.0f);
    glVertex3f( 10.0f, 0.01f,  10.0f);
    glVertex3f( 10.0f, 0.01f, -10.0f);
    glVertex3f(-10.0f, 0.01f, -10.0f);
    glVertex3f(-10.0f, 0.01f,  10.0f);
    glEnd();

    glPushMatrix();
    glTranslatef(0.0f, -0.1f, 0.0f);
    glCallList(DisplayLists.mountain);
    glPopMatrix();

    glPushMatrix();
    glRotatef(135.0f, 0.0f, 1.0f, 0.0f);
    glTranslatef(0.2f, -0.15f, -0.4f);
    glCallList(DisplayLists.mountain);
    glPopMatrix();

    glPushMatrix();
    glRotatef(-60.0f, 0.0f, 1.0f, 0.0f);
    glTranslatef(0.7f, -0.07f, 0.5f);
    glCallList(DisplayLists.mountain);
    glPopMatrix();

    glPushMatrix();
    glRotatef(-175.0f, 0.0f, 1.0f, 0.0f);
    glTranslatef(-0.7f, -0.05f, -0.5f);
    glCallList(DisplayLists.mountain);
    glPopMatrix();

    glPushMatrix();
    glRotatef(165.0f, 0.0f, 1.0f, 0.0f);
    glTranslatef(-0.9f, -0.12f, 0.0f);
    glCallList(DisplayLists.mountain);
    glPopMatrix();

    glPopMatrix();
    glPopAttrib();
    glEndList();
}

void newFractals()
{
    newMountain();
    newTree();
}

void create(int fract)
{
    switch (fract)
    {
    case DisplayLists.mountain:
        createMountain();
        break;
    case DisplayLists.tree:
        createTree();
        break;
    case DisplayLists.island:
        createIsland();
        break;
    default:
        break;
    }
}

/***************************************************************/
/**************************** OPENGL ***************************/
/***************************************************************/

void setupMaterials()
{
    GLfloat[4] mtnAmbuse    = [0.426f, 0.256f, 0.108f, 1.0f];
    GLfloat[4] mtnSpecular  = [0.394f, 0.272f, 0.167f, 1.0f];
    GLfloat[1] mtnShininess = [10.0f];

    GLfloat[4] waterAmbuse    = [0.0f, 0.1f, 0.5f, 1.0f];
    GLfloat[4] waterSpecular  = [0.0f, 0.1f, 0.5f, 1.0f];
    GLfloat[1] waterShininess = [10.0f];

    GLfloat[4] treeAmbuse    = [0.4f, 0.25f, 0.1f, 1.0f];
    GLfloat[4] treeSpecular  = [0.0f, 0.00f, 0.0f, 1.0f];
    GLfloat[1] treeShininess = [0.0f];

    GLfloat[4] leafAmbuse    = [0.0f, 0.8f, 0.0f, 1.0f];
    GLfloat[4] leafSpecular  = [0.0f, 0.8f, 0.0f, 1.0f];
    GLfloat[1] leafShininess = [10.0f];

    glNewList(DisplayLists.mountainMat, GL_COMPILE);
    glMaterialfv(GL_FRONT, GL_AMBIENT_AND_DIFFUSE, mtnAmbuse.ptr);
    glMaterialfv(GL_FRONT, GL_SPECULAR, mtnSpecular.ptr);
    glMaterialfv(GL_FRONT, GL_SHININESS, mtnShininess.ptr);
    glEndList();

    glNewList(DisplayLists.waterMat, GL_COMPILE);
    glMaterialfv(GL_FRONT, GL_AMBIENT_AND_DIFFUSE, waterAmbuse.ptr);
    glMaterialfv(GL_FRONT, GL_SPECULAR, waterSpecular.ptr);
    glMaterialfv(GL_FRONT, GL_SHININESS, waterShininess.ptr);
    glEndList();

    glNewList(DisplayLists.treeMat, GL_COMPILE);
    glMaterialfv(GL_FRONT, GL_AMBIENT_AND_DIFFUSE, treeAmbuse.ptr);
    glMaterialfv(GL_FRONT, GL_SPECULAR, treeSpecular.ptr);
    glMaterialfv(GL_FRONT, GL_SHININESS, treeShininess.ptr);
    glEndList();

    glNewList(DisplayLists.leafMat, GL_COMPILE);
    glMaterialfv(GL_FRONT_AND_BACK, GL_AMBIENT_AND_DIFFUSE, leafAmbuse.ptr);
    glMaterialfv(GL_FRONT_AND_BACK, GL_SPECULAR, leafSpecular.ptr);
    glMaterialfv(GL_FRONT_AND_BACK, GL_SHININESS, leafShininess.ptr);
    glEndList();
}

void myGLInit()
{
    GLfloat[4] lightAmbient  = [0.0f, 0.0f, 0.0f, 1.0f];
    GLfloat[4] lightDiffuse  = [1.0f, 1.0f, 1.0f, 1.0f];
    GLfloat[4] lightSpecular = [1.0f, 1.0f, 1.0f, 1.0f];
    GLfloat[4] lightPosition = [0.0f, 0.3f, 0.3f, 0.0f];

    GLfloat[4] lmodelAmbient = [0.4f, 0.4f, 0.4f, 1.0f];

    glLightfv(GL_LIGHT0, GL_AMBIENT, lightAmbient.ptr);
    glLightfv(GL_LIGHT0, GL_DIFFUSE, lightDiffuse.ptr);
    glLightfv(GL_LIGHT0, GL_SPECULAR, lightSpecular.ptr);
    glLightfv(GL_LIGHT0, GL_POSITION, lightPosition.ptr);

    glLightModelfv(GL_LIGHT_MODEL_AMBIENT, lmodelAmbient.ptr);

    glEnable(GL_LIGHTING);
    glEnable(GL_LIGHT0);

    glDepthFunc(GL_LEQUAL);
    glEnable(GL_DEPTH_TEST);

    glEnable(GL_NORMALIZE);

    glShadeModel(GL_SMOOTH);

    setupMaterials();
    createTreeLists();

    glFlush();
}

/***************************************************************/
/************************ GLUT STUFF ***************************/
/***************************************************************/

int winwidth = 1;
int winheight = 1;

void reshape(int w, int h)
{
    glViewport(0, 0, w, h);

    winwidth  = w;
    winheight = h;
}

void display()
{
    long curtime;
    static long fpstime = 0;
    static int fpscount = 0;
    static int fps = 0;

    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    gluPerspective(60.0, cast(GLdouble) winwidth / winheight, 0.01, 100);
    agvViewTransform();

    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();

    if (rebuild)
    {
        create(fractal);
        rebuild = 0;
    }

    glCallList(fractal);

    if (drawAxes)
        glCallList(DisplayLists.axes);

    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    gluOrtho2D(0.0, winwidth, 0.0, winheight);

    string buf = format("FPS=%d", fps);
    glColor3f(1.0f, 1.0f, 1.0f);
    gl_font(helvetica, 12);
    gl_draw(buf, 10, 10);

    //
    // Use glFinish() instead of glFlush() to avoid getting many frames
    // ahead of the display (problem with some Linux OpenGL implementations...)
    //
    glFinish();

    // Update frames-per-second
    fpscount++;
    curtime = Clock.currTime().toUnixTime();
    if ((curtime - fpstime) >= 2)
    {
        fps      = (fps + fpscount / cast(int)(curtime - fpstime)) / 2;
        fpstime  = curtime;
        fpscount = 0;
    }
}

void visible(int v)
{
    if (v == GLUT_VISIBLE)
        agvSetAllowIdle(1);
    else
    {
        glutIdleFunc(null);
        agvSetAllowIdle(0);
    }
}

void menuuse(int v)
{
    if (v == GLUT_MENU_NOT_IN_USE)
        agvSetAllowIdle(1);
    else
    {
        glutIdleFunc(null);
        agvSetAllowIdle(0);
    }
}

/***************************************************************/
/******************* MENU SETUP & HANDLING *********************/
/***************************************************************/

enum MenuChoices { quit, rand, move, axes }

void setlevel(int value)
{
    level = value;
    rebuild = 1;
    glutPostRedisplay();
}

void choosefract(int value)
{
    fractal = value;
    rebuild = 1;
    glutPostRedisplay();
}

void handlemenu(int value)
{
    switch (value)
    {
    case MenuChoices.quit:
        fl.hideAllWindows();
        break;
    case MenuChoices.rand:
        newFractals();
        rebuild = 1;
        glutPostRedisplay();
        break;
    case MenuChoices.axes:
        drawAxes = !drawAxes;
        glutPostRedisplay();
        break;
    default:
        break;
    }
}

void menuInit()
{
    int submenu1, submenu2, submenu3;

    submenu1 = glutCreateMenu(&setlevel);
    glutAddMenuEntry("0", 0);  glutAddMenuEntry("1", 1);
    glutAddMenuEntry("2", 2);  glutAddMenuEntry("3", 3);
    glutAddMenuEntry("4", 4);  glutAddMenuEntry("5", 5);
    glutAddMenuEntry("6", 6);  glutAddMenuEntry("7", 7);
    glutAddMenuEntry("8", 8);

    submenu2 = glutCreateMenu(&choosefract);
    glutAddMenuEntry("Mountain", DisplayLists.mountain);
    glutAddMenuEntry("Tree", DisplayLists.tree);
    glutAddMenuEntry("Island", DisplayLists.island);

    submenu3 = glutCreateMenu(&agvSwitchMoveMode);
    glutAddMenuEntry("Flying", MovementType.flying);
    glutAddMenuEntry("Polar", MovementType.polar);

    glutCreateMenu(&handlemenu);
    glutAddSubMenu("Level", submenu1);
    glutAddSubMenu("Fractal", submenu2);
    glutAddSubMenu("Movement", submenu3);
    glutAddMenuEntry("New Fractal", MenuChoices.rand);
    glutAddMenuEntry("Toggle Axes", MenuChoices.axes);
    glutAddMenuEntry("Quit", MenuChoices.quit);
    glutAttachMenu(GLUT_RIGHT_BUTTON);
}

/***************************************************************/
/**************************** MAIN *****************************/
/***************************************************************/

// Note: FLTK's Fl_Widget*/void* callback-adapter overloads of
// setlevel/choosefract/handlemenu are intentionally not ported -- see
// the header note. Every Button below captures its int argument in a
// closure instead.

void main(string[] args)
{
    fl.useHighResGL(true);

    // create FLTK window:
    auto window = new Window(512 + 20, 512 + 100);
    window.resizable(window);

    // create a bunch of buttons:
    auto g = new FlGroup(110, 50, 400 - 110, 30, "Level:");
    g.alignment(alignLeft);
    g.begin();
    Button b;
    b = new Button(110, 50, 30, 30, "0"); b.callback((w) { setlevel(0); });
    b = new Button(140, 50, 30, 30, "1"); b.callback((w) { setlevel(1); });
    b = new Button(170, 50, 30, 30, "2"); b.callback((w) { setlevel(2); });
    b = new Button(200, 50, 30, 30, "3"); b.callback((w) { setlevel(3); });
    b = new Button(230, 50, 30, 30, "4"); b.callback((w) { setlevel(4); });
    b = new Button(260, 50, 30, 30, "5"); b.callback((w) { setlevel(5); });
    b = new Button(290, 50, 30, 30, "6"); b.callback((w) { setlevel(6); });
    b = new Button(320, 50, 30, 30, "7"); b.callback((w) { setlevel(7); });
    b = new Button(350, 50, 30, 30, "8"); b.callback((w) { setlevel(8); });
    g.end();

    b = new Button(400, 50, 100, 30, "New Fractal");
    b.callback((w) { handlemenu(MenuChoices.rand); });

    b = new Button( 10, 10, 100, 30, "Mountain");
    b.callback((w) { choosefract(DisplayLists.mountain); });
    b = new Button(110, 10, 100, 30, "Tree");
    b.callback((w) { choosefract(DisplayLists.tree); });
    b = new Button(210, 10, 100, 30, "Island");
    b.callback((w) { choosefract(DisplayLists.island); });
    b = new Button(400, 10, 100, 30, "Quit");
    b.callback((w) { handlemenu(MenuChoices.quit); });

    window.show(args); // glut will die unless parent window visible
    window.begin(); // this will cause Glut window to be a child
    glutInitWindowSize(512, 512);
    glutInitWindowPosition(10, 90); // place it inside parent window
    glutInitDisplayMode(GLUT_DOUBLE | GLUT_RGBA | GLUT_DEPTH | GLUT_MULTISAMPLE);
    glutCreateWindow("Fractal Planet?");
    window.end();
    window.resizable(glutWindow);

    agvInit(1); // 1 cause we don't have our own idle

    glutReshapeFunc(&reshape);
    glutDisplayFunc(&display);
    glutVisibilityFunc(&visible);
    glutMenuStateFunc(&menuuse);

    newFractals();
    agvMakeAxesList(DisplayLists.axes);
    myGLInit();
    menuInit();

    glutMainLoop(); // you could use fl.run() instead
}
