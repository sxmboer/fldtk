// D transliteration of FLTK's test/glpuzzle.cxx and test/trackball.c/.h.
// Build: rdmd buildsamples.d test glpuzzle
//
// A GLUT demo program exercising fltk's GLUT emulation (FL/glut.H) to
// render a 3D sliding-block puzzle. fldtk has no GL/GLUT support at all
// yet (no fl.gl_window module, no gl_*/glu*/glut* bindings) -- the raw
// gl*/glu*/glut* calls below keep their FLTK C names verbatim
// (foreign GL/GLU/GLUT API, not FLTK's own naming surface), following
// the IDENTICAL convention already established in cube.d/shape.d
// (GL calls) and glut_test.d (GLUT calls). GLfloat/GLint/GLuint/GLsizei/
// GLenum are likewise kept as the FLTK GL type names, matching
// shape.d/gl_overlay.d/OpenGL3_glut_test.d. This program is essentially
// a straight GLUT program (not FLTK-widget-tree-based like cube.d/
// shape.d), so main()/the callback setup mirrors glut_test.d's style
// rather than instantiating a Window/GlWindow pair.
//
// Notes on what's invented/adapted here, beyond the gl*/glu*/glut* names:
//  - trackball.c/.h's quaternion/vector math (trackball(), add_quats(),
//    build_rotmatrix(), axis_to_quat(), the v*() vector helpers) is pure
//    numerical code, not FLTK API surface -- per the batch instructions
//    it keeps its original snake_case C names and is ported faithfully
//    as ordinary D functions rather than being renamed to fit fldtk's
//    Widget-porting conventions. Its `float q[4]`/`float v[3]` C
//    array-decays-to-pointer out-parameters are transliterated as D
//    `float[]` slices (the natural D equivalent of a mutable pointer
//    into the caller's array -- passing a `float[4]` static array where
//    a `float[]` is expected implicitly slices it, so mutations still
//    propagate back to the caller exactly like the C pointer semantics
//    they replace). add_quats()'s function-local `static int count`
//    (renormalizing every RENORMCOUNT calls) is kept as a genuine D
//    function-local static, the same pattern CONVENTIONS.md documents for
//    fl.slider's `offcenter`/fl.roller's `ipos`.
//  - multMatrices()/makeIdentity()/invertMatrix() are likewise plain
//    matrix numerics (not FLTK API) and are ported faithfully the same
//    way, operating on GLfloat[16] (the flattened 4x4 layout FLTK
//    uses for these three helpers specifically, as opposed to
//    build_rotmatrix()'s float[4][4]).
//  - struct puzzle/struct puzzlelist (malloc'd, manually free()'d linked
//    lists/hashtable buckets in C) become GC-managed D classes `Puzzle`/
//    `PuzzleList`; freeSolutions() drops the root references instead of
//    walking every node to call free() on it, matching the malloc/free
//    -> GC substitution CONVENTIONS.md documents for Fl_Widget::label()'s
//    COPIED_LABEL bookkeeping.
//  - `goto nomatch`/`goto found_piece` (addConfig()/continueSolving())
//    are re-expressed as labeled `break` out of the equivalent nested
//    loop -- D's goto forbids jumping into the scope of a variable
//    declared with an initializer, which the literal C control flow
//    here would trip depending on statement order, so the idiomatic D
//    labeled-loop-break is used instead; the decision logic and end
//    state are unchanged.
//  - Fl::use_high_res_GL(1) -> fl.useHighResGL(true), matching the
//    convention already used in cube.d/shape.d/gl_overlay.d.
import fl;
import std.format : format;
import std.math : sqrt, sin, cos, asin, abs;
import std.stdio : writeln;
import core.stdc.stdlib : exit;

enum int WIDTH = 4;
enum int HEIGHT = 5;
enum int PIECES = 10;
enum float OFFSETX = -2.0f;
enum float OFFSETY = -2.5f;
enum float OFFSETZ = -0.5f;

alias Config = ubyte[WIDTH][HEIGHT];

class Puzzle
{
    Puzzle backptr;
    Puzzle solnptr;
    Config pieces;
    Puzzle next;
    uint hashvalue;
}

enum int HASHSIZE = 10691;

class PuzzleList
{
    Puzzle puzzle;
    PuzzleList next;
}

static immutable ubyte[PIECES + 1] convert =
    [0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 4];

static immutable ubyte[3][PIECES + 1] colors =
[
    [0, 0, 0],
    [255, 255, 127],
    [255, 255, 127],
    [255, 255, 127],
    [255, 255, 127],
    [255, 127, 255],
    [255, 127, 255],
    [255, 127, 255],
    [255, 127, 255],
    [255, 127, 127],
    [255, 255, 255],
];

Puzzle[HASHSIZE] hashtable;
Puzzle startPuzzle;
PuzzleList puzzles;
PuzzleList lastentry;

int curX, curY, visible;

enum float MOVE_SPEED = 0.2f;
ubyte movingPiece;
float move_x, move_y;
float[4] curquat;
bool doubleBuffer = true;
int depth = 1;

static immutable ubyte[PIECES + 1] xsize =
    [0, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2];
static immutable ubyte[PIECES + 1] ysize =
    [0, 1, 1, 1, 1, 2, 2, 2, 2, 1, 2];
static immutable float[PIECES + 1] zsize =
    [0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0.6f];

static immutable Config startConfig =
[
    [8, 10, 10, 7],
    [8, 10, 10, 7],
    [6, 9, 9, 5],
    [6, 4, 3, 5],
    [2, 0, 0, 1],
];

Config thePuzzle =
[
    [8, 10, 10, 7],
    [8, 10, 10, 7],
    [6, 9, 9, 5],
    [6, 4, 3, 5],
    [2, 0, 0, 1],
];

static immutable int[4] xadds = [-1, 0, 1, 0];
static immutable int[4] yadds = [0, -1, 0, 1];

long W = 400, H = 300;
GLint[4] viewport;

uint hash(in Config config)
{
    int value = 0;
    foreach (i; 0 .. HEIGHT)
        foreach (j; 0 .. WIDTH)
        {
            value = value + convert[config[i][j]];
            value *= 6;
        }
    return cast(uint) value;
}

bool solution(in Config config)
{
    return config[4][1] == 10 && config[4][2] == 10;
}

// --- Box / container geometry (test/glpuzzle.cxx's flat vertex tables) ---

static immutable float[3][] boxcoords =
[
    [0.2f, 0.2f, 0.9f],
    [0.8f, 0.2f, 0.9f],
    [0.8f, 0.8f, 0.9f],
    [0.2f, 0.8f, 0.9f],
    [0.2f, 0.1f, 0.8f],
    [0.8f, 0.1f, 0.8f],
    [0.9f, 0.2f, 0.8f],
    [0.9f, 0.8f, 0.8f],
    [0.8f, 0.9f, 0.8f],
    [0.2f, 0.9f, 0.8f],
    [0.1f, 0.8f, 0.8f],
    [0.1f, 0.2f, 0.8f],
    [0.2f, 0.1f, 0.2f],
    [0.8f, 0.1f, 0.2f],
    [0.9f, 0.2f, 0.2f],
    [0.9f, 0.8f, 0.2f],
    [0.8f, 0.9f, 0.2f],
    [0.2f, 0.9f, 0.2f],
    [0.1f, 0.8f, 0.2f],
    [0.1f, 0.2f, 0.2f],
    [0.2f, 0.2f, 0.1f],
    [0.8f, 0.2f, 0.1f],
    [0.8f, 0.8f, 0.1f],
    [0.2f, 0.8f, 0.1f],
];

static immutable float[3][] boxnormals =
[
    [0, 0, 1],             /* 0 */
    [0, 1, 0],
    [1, 0, 0],
    [0, 0, -1],
    [0, -1, 0],
    [-1, 0, 0],
    [0.7071f, 0.7071f, 0.0000f],   /* 6 */
    [0.7071f, -0.7071f, 0.0000f],
    [-0.7071f, 0.7071f, 0.0000f],
    [-0.7071f, -0.7071f, 0.0000f],
    [0.7071f, 0.0000f, 0.7071f],   /* 10 */
    [0.7071f, 0.0000f, -0.7071f],
    [-0.7071f, 0.0000f, 0.7071f],
    [-0.7071f, 0.0000f, -0.7071f],
    [0.0000f, 0.7071f, 0.7071f],   /* 14 */
    [0.0000f, 0.7071f, -0.7071f],
    [0.0000f, -0.7071f, 0.7071f],
    [0.0000f, -0.7071f, -0.7071f],
    [0.5774f, 0.5774f, 0.5774f],   /* 18 */
    [0.5774f, 0.5774f, -0.5774f],
    [0.5774f, -0.5774f, 0.5774f],
    [0.5774f, -0.5774f, -0.5774f],
    [-0.5774f, 0.5774f, 0.5774f],
    [-0.5774f, 0.5774f, -0.5774f],
    [-0.5774f, -0.5774f, 0.5774f],
    [-0.5774f, -0.5774f, -0.5774f],
];

static immutable int[4][] boxfaces =
[
    [0, 1, 2, 3],           /* 0 */
    [9, 8, 16, 17],
    [6, 14, 15, 7],
    [20, 23, 22, 21],
    [12, 13, 5, 4],
    [19, 11, 10, 18],
    [7, 15, 16, 8],         /* 6 */
    [13, 14, 6, 5],
    [18, 10, 9, 17],
    [19, 12, 4, 11],
    [1, 6, 7, 2],           /* 10 */
    [14, 21, 22, 15],
    [11, 0, 3, 10],
    [20, 19, 18, 23],
    [3, 2, 8, 9],           /* 14 */
    [17, 16, 22, 23],
    [4, 5, 1, 0],
    [20, 21, 13, 12],
    [2, 7, 8, -1],          /* 18 */
    [16, 15, 22, -1],
    [5, 6, 1, -1],
    [13, 21, 14, -1],
    [10, 3, 9, -1],
    [18, 17, 23, -1],
    [11, 4, 0, -1],
    [20, 12, 19, -1],
];

/* Draw a box.  Bevel as desired. */
void drawBox(int piece, float xoff, float yoff)
{
    int xlen = xsize[piece];
    int ylen = ysize[piece];
    float zlen = zsize[piece];

    glColor3ubv(colors[piece].ptr);
    glBegin(GL_QUADS);
    foreach (i; 0 .. 18)
    {
        glNormal3fv(boxnormals[i].ptr);
        foreach (k; 0 .. 4)
        {
            if (boxfaces[i][k] == -1)
                continue;
            auto v = boxcoords[boxfaces[i][k]];
            float x = v[0] + OFFSETX;
            if (v[0] > 0.5f)
                x += xlen - 1;
            float y = v[1] + OFFSETY;
            if (v[1] > 0.5f)
                y += ylen - 1;
            float z = v[2] + OFFSETZ;
            if (v[2] > 0.5f)
                z += zlen - 1;
            glVertex3f(xoff + x, yoff + y, z);
        }
    }
    glEnd();
    glBegin(GL_TRIANGLES);
    foreach (i; 18 .. boxfaces.length)
    {
        glNormal3fv(boxnormals[i].ptr);
        foreach (k; 0 .. 3)
        {
            if (boxfaces[i][k] == -1)
                continue;
            auto v = boxcoords[boxfaces[i][k]];
            float x = v[0] + OFFSETX;
            if (v[0] > 0.5f)
                x += xlen - 1;
            float y = v[1] + OFFSETY;
            if (v[1] > 0.5f)
                y += ylen - 1;
            float z = v[2] + OFFSETZ;
            if (v[2] > 0.5f)
                z += zlen - 1;
            glVertex3f(xoff + x, yoff + y, z);
        }
    }
    glEnd();
}

static immutable float[3][] containercoords =
[
    [-0.1f, -0.1f, 1.0f],
    [-0.1f, -0.1f, -0.1f],
    [4.1f, -0.1f, -0.1f],
    [4.1f, -0.1f, 1.0f],
    [1.0f, -0.1f, 0.6f],      /* 4 */
    [3.0f, -0.1f, 0.6f],
    [1.0f, -0.1f, 0.0f],
    [3.0f, -0.1f, 0.0f],
    [1.0f, 0.0f, 0.0f],       /* 8 */
    [3.0f, 0.0f, 0.0f],
    [3.0f, 0.0f, 0.6f],
    [1.0f, 0.0f, 0.6f],
    [0.0f, 0.0f, 1.0f],       /* 12 */
    [4.0f, 0.0f, 1.0f],
    [4.0f, 0.0f, 0.0f],
    [0.0f, 0.0f, 0.0f],
    [0.0f, 5.0f, 0.0f],       /* 16 */
    [0.0f, 5.0f, 1.0f],
    [4.0f, 5.0f, 1.0f],
    [4.0f, 5.0f, 0.0f],
    [-0.1f, 5.1f, -0.1f],     /* 20 */
    [4.1f, 5.1f, -0.1f],
    [4.1f, 5.1f, 1.0f],
    [-0.1f, 5.1f, 1.0f],
];

static immutable float[3][] containernormals =
[
    [0, -1, 0],
    [0, -1, 0],
    [0, -1, 0],
    [0, -1, 0],
    [0, -1, 0],
    [0, 1, 0],
    [0, 1, 0],
    [0, 1, 0],
    [1, 0, 0],
    [1, 0, 0],
    [1, 0, 0],
    [-1, 0, 0],
    [-1, 0, 0],
    [-1, 0, 0],
    [0, 1, 0],
    [0, 0, -1],
    [0, 0, -1],
    [0, 0, 1],
    [0, 0, 1],
    [0, 0, 1],
    [0, 0, 1],
    [0, 0, 1],
    [0, 0, 1],
    [0, 0, 1],
];

static immutable int[4][] containerfaces =
[
    [1, 6, 4, 0],
    [0, 4, 5, 3],
    [1, 2, 7, 6],
    [7, 2, 3, 5],
    [16, 19, 18, 17],

    [23, 22, 21, 20],
    [12, 11, 8, 15],
    [10, 13, 14, 9],

    [15, 16, 17, 12],
    [2, 21, 22, 3],
    [6, 8, 11, 4],

    [1, 0, 23, 20],
    [14, 13, 18, 19],
    [9, 7, 5, 10],

    [12, 13, 10, 11],

    [1, 20, 21, 2],
    [4, 11, 10, 5],

    [15, 8, 19, 16],
    [19, 8, 9, 14],
    [8, 6, 7, 9],
    [0, 3, 13, 12],
    [13, 3, 22, 18],
    [18, 22, 23, 17],
    [17, 23, 0, 12],
];

/* Draw the container */
void drawContainer()
{
    /* Y is reversed here because the model has it reversed */

    /* Arbitrary bright wood-like color */
    glColor3ub(209, 103, 23);
    glBegin(GL_QUADS);
    foreach (i; 0 .. containerfaces.length)
    {
        auto v = containernormals[i];
        glNormal3f(v[0], -v[1], v[2]);
        for (int k = 3; k >= 0; k--)
        {
            auto c = containercoords[containerfaces[i][k]];
            glVertex3f(c[0] + OFFSETX, -(c[1] + OFFSETY), c[2] + OFFSETZ);
        }
    }
    glEnd();
}

void drawAll()
{
    bool[PIECES + 1] done;
    float[4][4] m;

    build_rotmatrix(m, curquat);
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();
    glTranslatef(0, 0, -10);
    glMultMatrixf(&m[0][0]);
    glRotatef(180, 0, 0, 1);

    if (depth)
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    else
        glClear(GL_COLOR_BUFFER_BIT);

    glLoadName(0);
    drawContainer();
    foreach (i; 0 .. HEIGHT)
        foreach (j; 0 .. WIDTH)
        {
            int piece = thePuzzle[i][j];
            if (piece == 0)
                continue;
            if (done[piece])
                continue;
            done[piece] = true;
            glLoadName(piece);
            if (piece == movingPiece)
                drawBox(piece, move_x, move_y);
            else
                drawBox(piece, cast(float) j, cast(float) i);
        }
}

void redraw()
{
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    gluPerspective(45, viewport[2] * 1.0 / viewport[3], 0.1, 100.0);

    drawAll();

    if (doubleBuffer)
        glutSwapBuffers();
    else
        glFinish();
}

void solidifyChain(Puzzle puzzle)
{
    int i = 0;
    while (puzzle.backptr !is null)
    {
        i++;
        puzzle.backptr.solnptr = puzzle;
        puzzle = puzzle.backptr;
    }
    glutSetWindowTitle(format("%d moves to complete!", i));
}

int addConfig(in Config config, Puzzle back)
{
    uint hashvalue = hash(config);

    Puzzle newpiece = hashtable[hashvalue % HASHSIZE];
    while (newpiece !is null)
    {
        if (newpiece.hashvalue == hashvalue)
        {
            bool matches = true;
        matchLoop:
            foreach (i; 0 .. WIDTH)
                foreach (j; 0 .. HEIGHT)
                    if (convert[config[j][i]] != convert[newpiece.pieces[j][i]])
                    {
                        matches = false;
                        break matchLoop;
                    }
            if (matches)
                return 0;
        }
        newpiece = newpiece.next;
    }

    newpiece = new Puzzle();
    newpiece.next = hashtable[hashvalue % HASHSIZE];
    newpiece.hashvalue = hashvalue;
    newpiece.pieces = config;
    newpiece.backptr = back;
    newpiece.solnptr = null;
    hashtable[hashvalue % HASHSIZE] = newpiece;

    auto newlistentry = new PuzzleList();
    newlistentry.puzzle = newpiece;
    newlistentry.next = null;

    if (lastentry !is null)
        lastentry.next = newlistentry;
    else
        puzzles = newlistentry;
    lastentry = newlistentry;

    if (back is null)
        startPuzzle = newpiece;
    if (solution(config))
    {
        solidifyChain(newpiece);
        return 1;
    }
    return 0;
}

/* Checks if a space can move */
int canmove0(in Config pieces, int x, int y, int dir, ref Config newpieces)
{
    int xadd = xadds[dir];
    int yadd = yadds[dir];

    if (x + xadd < 0 || x + xadd >= WIDTH || y + yadd < 0 || y + yadd >= HEIGHT)
        return 0;
    ubyte piece = pieces[y + yadd][x + xadd];
    if (piece == 0)
        return 0;
    newpieces = pieces;
    foreach (l; 0 .. WIDTH)
        foreach (m; 0 .. HEIGHT)
            if (newpieces[m][l] == piece)
                newpieces[m][l] = 0;
    xadd = -xadd;
    yadd = -yadd;
    foreach (l; 0 .. WIDTH)
        foreach (m; 0 .. HEIGHT)
            if (pieces[m][l] == piece)
            {
                int newx = l + xadd;
                int newy = m + yadd;
                if (newx < 0 || newx >= WIDTH || newy < 0 || newy >= HEIGHT)
                    return 0;
                if (newpieces[newy][newx] != 0)
                    return 0;
                newpieces[newy][newx] = piece;
            }
    return 1;
}

/* Checks if a piece can move */
int canmove(in Config pieces, int x, int y, int dir, ref Config newpieces)
{
    int xadd = xadds[dir];
    int yadd = yadds[dir];

    if (x + xadd < 0 || x + xadd >= WIDTH || y + yadd < 0 || y + yadd >= HEIGHT)
        return 0;
    if (pieces[y + yadd][x + xadd] == pieces[y][x])
        return canmove(pieces, x + xadd, y + yadd, dir, newpieces);
    if (pieces[y + yadd][x + xadd] != 0)
        return 0;
    return canmove0(pieces, x + xadd, y + yadd, (dir + 2) % 4, newpieces);
}

int generateNewConfigs(Puzzle puzzle)
{
    Config pieces = puzzle.pieces;
    Config newpieces;

    foreach (i; 0 .. WIDTH)
        foreach (j; 0 .. HEIGHT)
            if (pieces[j][i] == 0)
                foreach (k; 0 .. 4)
                    if (canmove0(pieces, i, j, k, newpieces))
                        if (addConfig(newpieces, puzzle))
                            return 1;
    return 0;
}

void freeSolutions()
{
    // GC-managed (see header note): drop the roots instead of walking
    // every node to call free() on it.
    puzzles = null;
    lastentry = null;
    foreach (i; 0 .. HASHSIZE)
        hashtable[i] = null;
    startPuzzle = null;
}

int continueSolving()
{
    if (startPuzzle is null)
        return 0;
    if (startPuzzle.solnptr is null)
    {
        freeSolutions();
        return 0;
    }
    Puzzle nextpuz = startPuzzle.solnptr;
    int movedPiece = 0;
    int movedir = 0;
    int fromx, fromy;
    bool found = false;

search:
    foreach (i; 0 .. HEIGHT)
        foreach (j; 0 .. WIDTH)
            if (startPuzzle.pieces[i][j] != nextpuz.pieces[i][j])
            {
                if (startPuzzle.pieces[i][j])
                {
                    movedPiece = startPuzzle.pieces[i][j];
                    fromx = j;
                    fromy = i;
                    if (i < HEIGHT - 1 && nextpuz.pieces[i + 1][j] == movedPiece)
                        movedir = 3;
                    else
                        movedir = 2;
                }
                else
                {
                    movedPiece = nextpuz.pieces[i][j];
                    if (i < HEIGHT - 1 && startPuzzle.pieces[i + 1][j] == movedPiece)
                    {
                        fromx = j;
                        fromy = i + 1;
                        movedir = 1;
                    }
                    else
                    {
                        fromx = j + 1;
                        fromy = i;
                        movedir = 0;
                    }
                }
                found = true;
                break search;
            }

    if (!found)
    {
        glutSetWindowTitle("What!  No change?");
        freeSolutions();
        return 0;
    }

    if (!movingPiece)
    {
        movingPiece = cast(ubyte) movedPiece;
        move_x = cast(float) fromx;
        move_y = cast(float) fromy;
    }
    move_x += xadds[movedir] * MOVE_SPEED;
    move_y += yadds[movedir] * MOVE_SPEED;

    int tox = fromx + xadds[movedir];
    int toy = fromy + yadds[movedir];

    if (move_x > tox - MOVE_SPEED / 2 && move_x < tox + MOVE_SPEED / 2 &&
        move_y > toy - MOVE_SPEED / 2 && move_y < toy + MOVE_SPEED / 2)
    {
        startPuzzle = nextpuz;
        movingPiece = 0;
    }
    thePuzzle = startPuzzle.pieces;
    changeState();
    return 1;
}

int solvePuzzle()
{
    if (solution(thePuzzle))
    {
        glutSetWindowTitle("Puzzle already solved!");
        return 0;
    }
    addConfig(thePuzzle, null);
    int i = 0;

    while (puzzles !is null)
    {
        i++;
        if (generateNewConfigs(puzzles.puzzle))
            break;
        puzzles = puzzles.next;
    }
    if (puzzles is null)
    {
        freeSolutions();
        glutSetWindowTitle(format("I can't solve it! (%d positions examined)", i));
        return 1;
    }
    return 1;
}

int selectPiece(int mousex, int mousey)
{
    GLuint[1024] selectBuf;
    GLuint closest;
    GLuint dist;

    glSelectBuffer(1024, selectBuf.ptr);
    glRenderMode(GL_SELECT);
    glInitNames();

    /* Because LoadName() won't work with no names on the stack */
    glPushName(0);

    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    gluPickMatrix(mousex, H - mousey, 4, 4, viewport.ptr);
    gluPerspective(45, viewport[2] * 1.0 / viewport[3], 0.1, 100.0);

    drawAll();

    long hits = glRenderMode(GL_RENDER);
    if (hits <= 0)
        return 0;
    closest = 0;
    dist = 0xFFFFFFFFU;
    while (hits)
    {
        auto idx = cast(size_t)((hits - 1) * 4);
        if (selectBuf[idx + 1] < dist)
        {
            dist = selectBuf[idx + 1];
            closest = selectBuf[idx + 3];
        }
        hits--;
    }
    return cast(int) closest;
}

void nukePiece(int piece)
{
    foreach (i; 0 .. HEIGHT)
        foreach (j; 0 .. WIDTH)
            if (thePuzzle[i][j] == piece)
                thePuzzle[i][j] = 0;
}

// --- Plain 4x4-matrix numerics (not FLTK API -- see header note) ---

void multMatrices(in GLfloat[16] a, in GLfloat[16] b, ref GLfloat[16] r)
{
    foreach (i; 0 .. 4)
        foreach (j; 0 .. 4)
            r[i * 4 + j] =
                a[i * 4 + 0] * b[0 * 4 + j] +
                a[i * 4 + 1] * b[1 * 4 + j] +
                a[i * 4 + 2] * b[2 * 4 + j] +
                a[i * 4 + 3] * b[3 * 4 + j];
}

void makeIdentity(ref GLfloat[16] m)
{
    m[0 + 4 * 0] = 1;
    m[0 + 4 * 1] = 0;
    m[0 + 4 * 2] = 0;
    m[0 + 4 * 3] = 0;
    m[1 + 4 * 0] = 0;
    m[1 + 4 * 1] = 1;
    m[1 + 4 * 2] = 0;
    m[1 + 4 * 3] = 0;
    m[2 + 4 * 0] = 0;
    m[2 + 4 * 1] = 0;
    m[2 + 4 * 2] = 1;
    m[2 + 4 * 3] = 0;
    m[3 + 4 * 0] = 0;
    m[3 + 4 * 1] = 0;
    m[3 + 4 * 2] = 0;
    m[3 + 4 * 3] = 1;
}

/* inverse = invert(src) */
int invertMatrix(in GLfloat[16] src, ref GLfloat[16] inverse)
{
    GLfloat[4][4] temp;

    foreach (i; 0 .. 4)
        foreach (j; 0 .. 4)
            temp[i][j] = src[i * 4 + j];
    makeIdentity(inverse);

    foreach (i; 0 .. 4)
    {
        /* Look for largest element in column */
        int swap = i;
        foreach (j; i + 1 .. 4)
            if (abs(temp[j][i]) > abs(temp[i][i]))
                swap = j;

        if (swap != i)
        {
            /* Swap rows. */
            foreach (k; 0 .. 4)
            {
                float t = temp[i][k];
                temp[i][k] = temp[swap][k];
                temp[swap][k] = t;

                t = inverse[i * 4 + k];
                inverse[i * 4 + k] = inverse[swap * 4 + k];
                inverse[swap * 4 + k] = t;
            }
        }
        if (temp[i][i] == 0)
        {
            /* No non-zero pivot.  The matrix is singular, which
               shouldn't happen.  This means the caller gave us a
               bad matrix. */
            return 0;
        }
        float t = temp[i][i];
        foreach (k; 0 .. 4)
        {
            temp[i][k] /= t;
            inverse[i * 4 + k] /= t;
        }
        foreach (j; 0 .. 4)
        {
            if (j != i)
            {
                t = temp[j][i];
                foreach (k; 0 .. 4)
                {
                    temp[j][k] -= temp[i][k] * t;
                    inverse[j * 4 + k] -= inverse[i * 4 + k] * t;
                }
            }
        }
    }
    return 1;
}

/*
 * This is a screwball function.  What it does is the following:
 * Given screen x and y coordinates, compute the corresponding object
 * space x and y coordinates given that the object space z is
 * 0.9 + OFFSETZ. Since the tops of (most) pieces are at z = 0.9 +
 * OFFSETZ, we use that number.
 */
int computeCoords(int piece, int mousex, int mousey, GLfloat* selx, GLfloat* sely)
{
    GLfloat[16] modelMatrix;
    GLfloat[16] projMatrix;
    GLfloat[16] finalMatrix;
    GLfloat[4] inp;
    GLfloat a, b, c, d;
    GLfloat top, bot;
    GLfloat z;
    GLfloat w;
    GLfloat height;

    if (piece == 0)
        return 0;
    height = zsize[piece] - 0.1f + OFFSETZ;

    glGetFloatv(GL_PROJECTION_MATRIX, projMatrix.ptr);
    glGetFloatv(GL_MODELVIEW_MATRIX, modelMatrix.ptr);
    multMatrices(modelMatrix, projMatrix, finalMatrix);
    if (!invertMatrix(finalMatrix, finalMatrix))
        return 0;

    inp[0] = (2.0f * (mousex - viewport[0]) / viewport[2]) - 1;
    inp[1] = (2.0f * ((H - mousey) - viewport[1]) / viewport[3]) - 1;

    a = inp[0] * finalMatrix[0 * 4 + 2] +
        inp[1] * finalMatrix[1 * 4 + 2] +
        finalMatrix[3 * 4 + 2];
    b = finalMatrix[2 * 4 + 2];
    c = inp[0] * finalMatrix[0 * 4 + 3] +
        inp[1] * finalMatrix[1 * 4 + 3] +
        finalMatrix[3 * 4 + 3];
    d = finalMatrix[2 * 4 + 3];

    /*
     * Solve for z:  (a + b z) / (c + d z) = height
     *   ==>  a + b z = height c + height d z
     *   ==>  bz - height d z = height c - a
     *   ==>  z = (height c - a) / (b - height d)
     */
    top = height * c - a;
    bot = b - height * d;
    if (bot == 0.0f)
        return 0;

    z = top / bot;

    /* w = c + d z, then solve for x and y. */
    w = c + d * z;

    *selx = (inp[0] * finalMatrix[0 * 4 + 0] +
        inp[1] * finalMatrix[1 * 4 + 0] +
        z * finalMatrix[2 * 4 + 0] +
        finalMatrix[3 * 4 + 0]) / w - OFFSETX;
    *sely = (inp[0] * finalMatrix[0 * 4 + 1] +
        inp[1] * finalMatrix[1 * 4 + 1] +
        z * finalMatrix[2 * 4 + 1] +
        finalMatrix[3 * 4 + 1]) / w - OFFSETY;
    return 1;
}

int selected;
int selectx, selecty;
float selstartx, selstarty;

void grabPiece(int piece, float selx, float sely)
{
    selectx = cast(int) selx;
    selecty = cast(int) sely;
    if (selectx < 0 || selecty < 0 || selectx >= WIDTH || selecty >= HEIGHT)
        return;
    int hit = thePuzzle[selecty][selectx];
    if (hit != piece)
        return;
    if (hit)
    {
        movingPiece = cast(ubyte) hit;
        while (selectx > 0 && thePuzzle[selecty][selectx - 1] == movingPiece)
            selectx--;
        while (selecty > 0 && thePuzzle[selecty - 1][selectx] == movingPiece)
            selecty--;
        move_x = cast(float) selectx;
        move_y = cast(float) selecty;
        selected = 1;
        selstartx = selx;
        selstarty = sely;
    }
    else
    {
        selected = 0;
    }
    changeState();
}

void moveSelection(float selx, float sely)
{
    if (!selected)
        return;
    float deltax = selx - selstartx;
    float deltay = sely - selstarty;
    int dir;
    Config newpieces;

    if (abs(deltax) > abs(deltay))
    {
        deltay = 0;
        if (deltax > 0)
        {
            if (deltax > 1)
                deltax = 1;
            dir = 2;
        }
        else
        {
            if (deltax < -1)
                deltax = -1;
            dir = 0;
        }
    }
    else
    {
        deltax = 0;
        if (deltay > 0)
        {
            if (deltay > 1)
                deltay = 1;
            dir = 3;
        }
        else
        {
            if (deltay < -1)
                deltay = -1;
            dir = 1;
        }
    }
    if (canmove(thePuzzle, selectx, selecty, dir, newpieces))
    {
        move_x = deltax + selectx;
        move_y = deltay + selecty;
        if (deltax > 0.5f)
        {
            thePuzzle = newpieces;
            selectx++;
            selstartx++;
        }
        else if (deltax < -0.5f)
        {
            thePuzzle = newpieces;
            selectx--;
            selstartx--;
        }
        else if (deltay > 0.5f)
        {
            thePuzzle = newpieces;
            selecty++;
            selstarty++;
        }
        else if (deltay < -0.5f)
        {
            thePuzzle = newpieces;
            selecty--;
            selstarty--;
        }
    }
    else
    {
        if (deltay > 0 && thePuzzle[selecty][selectx] == 10 &&
            selectx == 1 && selecty == 3)
        {
            /* Allow visual movement of solution piece outside of the box */
            move_x = cast(float) selectx;
            move_y = sely - selstarty + selecty;
        }
        else
        {
            move_x = cast(float) selectx;
            move_y = cast(float) selecty;
        }
    }
}

void dropSelection()
{
    if (!selected)
        return;
    movingPiece = 0;
    selected = 0;
    changeState();
}

int left_mouse, middle_mouse;
int mousex, mousey;
int solving;
int spinning;
int enable_spinning = 1;
float[4] lastquat;
int sel_piece;
int timer_active = 0;   // restart another timer at the end of `animate`
int timer_pending = 0;  // a timer is waiting to be triggered
int timer_delay = 13;   // timeout in msec (13ms = 72 frames per second)

void Reshape(int width, int height)
{
    W = width;
    H = height;
    glViewport(0, 0, cast(GLsizei) W, cast(GLsizei) H);
    glGetIntegerv(GL_VIEWPORT, viewport.ptr);
}

void toggleSolve()
{
    if (solving)
    {
        freeSolutions();
        solving = 0;
        glutChangeToMenuEntry(2, "Solve", 2);
        glutSetWindowTitle("glpuzzle");
        movingPiece = 0;
    }
    else
    {
        glutChangeToMenuEntry(2, "Stop solving", 2);
        glutSetWindowTitle("Solving...");
        if (solvePuzzle())
            solving = 1;
    }
    changeState();
    glutPostRedisplay();
}

void reset_position()
{
    spinning = 0;
    trackball(curquat, 0.0f, 0.0f, 0.0f, 0.0f); // reset position
    if (!timer_pending)
    {
        timer_pending = 1;
        glutTimerFunc(timer_delay, &animate, 0);
    }
}

void reset()
{
    reset_position();
    if (solving)
    {
        freeSolutions();
        solving = 0;
        glutChangeToMenuEntry(2, "Solve", 2);
        glutSetWindowTitle("glpuzzle");
        movingPiece = 0;
        changeState();
    }
    thePuzzle = startConfig;
    glutPostRedisplay();
}

void keyboard(ubyte c, int x, int y)
{
    int piece;

    switch (c)
    {
    case 27:
        fl.hideAllWindows();
        break;
    case ' ':
    case 'n':
    case 'N':
        reset_position();
        break;
    case 'D':
    case 'd':
        if (solving)
        {
            freeSolutions();
            solving = 0;
            glutChangeToMenuEntry(2, "Solve", 2);
            glutSetWindowTitle("glpuzzle");
            movingPiece = 0;
            changeState();
        }
        piece = selectPiece(x, y);
        if (piece)
            nukePiece(piece);
        glutPostRedisplay();
        break;
    case 'R':
    case 'r':
        reset();
        break;
    case 'S':
    case 's':
        toggleSolve();
        break;
    case 'b':
    case 'B':
        depth = 1 - depth;
        if (depth)
            glEnable(GL_DEPTH_TEST);
        else
            glDisable(GL_DEPTH_TEST);
        glutPostRedisplay();
        break;
    default:
        break;
    }
}

void motion(int x, int y)
{
    float selx, sely;

    if (middle_mouse && !left_mouse)
    {
        if (mousex != x || mousey != y)
        {
            trackball(lastquat,
                (2.0f * mousex - W) / W,
                (H - 2.0f * mousey) / H,
                (2.0f * x - W) / W,
                (H - 2.0f * y) / H);
            spinning = enable_spinning; // 1 = yes, 0 = disabled (commandline -n)
        }
        else
        {
            spinning = 0;
        }
        changeState();
    }
    else
    {
        computeCoords(sel_piece, x, y, &selx, &sely);
        moveSelection(selx, sely);
    }
    mousex = x;
    mousey = y;
    glutPostRedisplay();
}

void mouse(int b, int s, int x, int y)
{
    float selx, sely;

    mousex = x;
    mousey = y;
    curX = x;
    curY = y;
    if (s == GLUT_DOWN)
    {
        switch (b)
        {
        case GLUT_LEFT_BUTTON:
            if (solving)
            {
                freeSolutions();
                solving = 0;
                glutChangeToMenuEntry(2, "Solve", 2);
                glutSetWindowTitle("glpuzzle");
                movingPiece = 0;
            }
            left_mouse = GL_TRUE;
            sel_piece = selectPiece(mousex, mousey);
            if (!sel_piece)
            {
                left_mouse = GL_FALSE;
                middle_mouse = GL_TRUE; // let it rotate object
            }
            else if (computeCoords(sel_piece, mousex, mousey, &selx, &sely))
            {
                grabPiece(sel_piece, selx, sely);
            }
            glutPostRedisplay();
            break;
        case GLUT_MIDDLE_BUTTON:
            middle_mouse = GL_TRUE;
            glutPostRedisplay();
            break;
        default:
            break;
        }
    }
    else
    {
        if (left_mouse)
        {
            left_mouse = GL_FALSE;
            dropSelection();
            glutPostRedisplay();
        }
        else if (middle_mouse)
        {
            middle_mouse = GL_FALSE;
            glutPostRedisplay();
        }
    }
    motion(x, y);
}

void animate(int)
{
    timer_pending = 0;
    if (spinning)
        add_quats(lastquat, curquat, curquat);
    glutPostRedisplay();
    if (solving)
    {
        if (!continueSolving())
        {
            solving = 0;
            glutChangeToMenuEntry(2, "Solve", 2);
            glutSetWindowTitle("glpuzzle");
        }
    }
    if ((!solving && !spinning) || !visible)
        timer_active = 0;
    if (timer_active && !timer_pending)
    {
        timer_pending = 1;
        glutTimerFunc(timer_delay, &animate, 0);
    }
}

void changeState()
{
    if (visible)
    {
        if (!solving && !spinning)
        {
            timer_active = 0;
        }
        else
        {
            timer_active = 1;
            if (!timer_pending)
            {
                timer_pending = 1;
                glutTimerFunc(timer_delay, &animate, 0);
            }
        }
    }
    else
    {
        timer_active = 0;
    }
}

void init()
{
    static immutable float[4] lmodelAmbient = [0.0f, 0.0f, 0.0f, 0.0f];
    static immutable float[1] lmodelTwoside = [GL_FALSE];
    static immutable float[1] lmodelLocal = [GL_FALSE];
    static immutable float[4] light0Ambient = [0.1f, 0.1f, 0.1f, 1.0f];
    static immutable float[4] light0Diffuse = [1.0f, 1.0f, 1.0f, 0.0f];
    static immutable float[4] light0Position = [0.8660254f, 0.5f, 1, 0];
    static immutable float[4] light0Specular = [0.0f, 0.0f, 0.0f, 0.0f];
    static immutable float[4] bevelMatAmbient = [0.0f, 0.0f, 0.0f, 1.0f];
    static immutable float[1] bevelMatShininess = [40.0f];
    static immutable float[4] bevelMatSpecular = [0.0f, 0.0f, 0.0f, 0.0f];
    static immutable float[4] bevelMatDiffuse = [1.0f, 0.0f, 0.0f, 0.0f];

    glEnable(GL_CULL_FACE);
    glCullFace(GL_BACK);
    glEnable(GL_DEPTH_TEST);
    glClearDepth(1.0);

    glClearColor(0.5, 0.5, 0.5, 0.0);
    glLightfv(GL_LIGHT0, GL_AMBIENT, light0Ambient.ptr);
    glLightfv(GL_LIGHT0, GL_DIFFUSE, light0Diffuse.ptr);
    glLightfv(GL_LIGHT0, GL_SPECULAR, light0Specular.ptr);
    glLightfv(GL_LIGHT0, GL_POSITION, light0Position.ptr);
    glEnable(GL_LIGHT0);

    glLightModelfv(GL_LIGHT_MODEL_LOCAL_VIEWER, lmodelLocal.ptr);
    glLightModelfv(GL_LIGHT_MODEL_TWO_SIDE, lmodelTwoside.ptr);
    glLightModelfv(GL_LIGHT_MODEL_AMBIENT, lmodelAmbient.ptr);
    glEnable(GL_LIGHTING);

    glMaterialfv(GL_FRONT, GL_AMBIENT, bevelMatAmbient.ptr);
    glMaterialfv(GL_FRONT, GL_SHININESS, bevelMatShininess.ptr);
    glMaterialfv(GL_FRONT, GL_SPECULAR, bevelMatSpecular.ptr);
    glMaterialfv(GL_FRONT, GL_DIFFUSE, bevelMatDiffuse.ptr);

    glColorMaterial(GL_FRONT_AND_BACK, GL_DIFFUSE);
    glEnable(GL_COLOR_MATERIAL);
    glShadeModel(GL_FLAT);

    trackball(curquat, 0.0f, 0.0f, 0.0f, 0.0f);
}

void Usage()
{
    writeln("Usage: puzzle [-s]");
    writeln("   -s:  Run in single buffered mode");
    exit(-1);
}

void visibility(int v)
{
    visible = (v == GLUT_VISIBLE) ? 1 : 0;
    changeState();
}

void menu(int choice)
{
    switch (choice)
    {
    case 1:
        reset_position();
        break;
    case 2:
        toggleSolve();
        break;
    case 3:
        reset();
        break;
    case 4:
        fl.hideAllWindows();
        break;
    default:
        break;
    }
}

void main(string[] args)
{
    fl.useHighResGL(true);
    glutInit(args);
    foreach (arg; args[1 .. $])
    {
        if (arg.length >= 2 && arg[0] == '-')
        {
            switch (arg[1])
            {
            case 'n':
                enable_spinning = 0; // disable (sometimes annoying) spinning behaviour
                break;
            case 's':
                doubleBuffer = false;
                break;
            default:
                Usage();
            }
        }
        else
        {
            Usage();
        }
    }

    glutInitWindowSize(cast(int) W, cast(int) H);
    if (doubleBuffer)
        glutInitDisplayMode(GLUT_DEPTH | GLUT_RGB | GLUT_DOUBLE | GLUT_MULTISAMPLE);
    else
        glutInitDisplayMode(GLUT_DEPTH | GLUT_RGB | GLUT_SINGLE | GLUT_MULTISAMPLE);

    glutCreateWindow("glpuzzle");
    visible = 1; // added for fltk, bug in original program?

    init();

    glGetIntegerv(GL_VIEWPORT, viewport.ptr);

    writeln();
    writeln("n   Normal position - stop spinning");
    writeln("r   Reset puzzle");
    writeln("s   Solve puzzle (may take a few seconds to compute)");
    writeln("d   Destroy a piece - makes the puzzle easier");
    writeln("b   Toggles the depth buffer on and off");
    writeln();
    writeln("Left mouse moves pieces");
    writeln("Middle mouse spins the puzzle");
    writeln("Right mouse has menu");

    glutReshapeFunc(&Reshape);
    glutDisplayFunc(&redraw);
    glutKeyboardFunc(&keyboard);
    glutMotionFunc(&motion);
    glutMouseFunc(&mouse);
    glutVisibilityFunc(&visibility);
    glutCreateMenu(&menu);
    glutAddMenuEntry("Normal pos", 1);
    glutAddMenuEntry("Solve", 2);
    glutAddMenuEntry("Reset", 3);
    glutAddMenuEntry("Quit", 4);
    glutAttachMenu(GLUT_RIGHT_BUTTON);
    glutMainLoop();
}

// --- trackball.c/.h -- virtual trackball / quaternion math -------------
//
// Plain numerical code (not FLTK API), ported faithfully with its
// original snake_case names -- see the header note above. `float*`/
// `float[3]`/`float[4]` C parameters (which decay to pointers, i.e.
// mutable views into the caller's array) become D `float[]` slices;
// passing a `float[4]`/`float[3]` static array where a slice is
// expected implicitly creates a slice over that same memory, so
// in-place mutation still propagates back to the caller.

enum float TRACKBALLSIZE = 0.8f;
float max_velocity = 0.1f;

void vzero(float[] v)
{
    v[0] = 0.0f;
    v[1] = 0.0f;
    v[2] = 0.0f;
}

void vset(float[] v, float x, float y, float z)
{
    v[0] = x;
    v[1] = y;
    v[2] = z;
}

void vsub(in float[] src1, in float[] src2, float[] dst)
{
    dst[0] = src1[0] - src2[0];
    dst[1] = src1[1] - src2[1];
    dst[2] = src1[2] - src2[2];
}

void vcopy(in float[] v1, float[] v2)
{
    foreach (i; 0 .. 3)
        v2[i] = v1[i];
}

void vcross(in float[] v1, in float[] v2, float[] cross)
{
    float[3] temp;
    temp[0] = (v1[1] * v2[2]) - (v1[2] * v2[1]);
    temp[1] = (v1[2] * v2[0]) - (v1[0] * v2[2]);
    temp[2] = (v1[0] * v2[1]) - (v1[1] * v2[0]);
    vcopy(temp, cross);
}

float vlength(in float[] v)
{
    return sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
}

void vscale(float[] v, float div)
{
    v[0] *= div;
    v[1] *= div;
    v[2] *= div;
}

void vnormal(float[] v)
{
    vscale(v, 1.0f / vlength(v));
}

float vdot(in float[] v1, in float[] v2)
{
    return v1[0] * v2[0] + v1[1] * v2[1] + v1[2] * v2[2];
}

void vadd(in float[] src1, in float[] src2, float[] dst)
{
    dst[0] = src1[0] + src2[0];
    dst[1] = src1[1] + src2[1];
    dst[2] = src1[2] + src2[2];
}

/*
 * Ok, simulate a track-ball.  Project the points onto the virtual
 * trackball, then figure out the axis of rotation, which is the cross
 * product of P1 P2 and O P1 (O is the center of the ball, 0,0,0)
 * Note:  This is a deformed trackball-- is a trackball in the center,
 * but is deformed into a hyperbolic sheet of rotation away from the
 * center.  This particular function was chosen after trying out
 * several variations.
 *
 * It is assumed that the arguments to this routine are in the range
 * (-1.0 ... 1.0)
 */
void trackball(float[] q, float p1x, float p1y, float p2x, float p2y)
{
    float[3] a; /* Axis of rotation */
    float phi;  /* how much to rotate about axis */
    float[3] p1, p2, d;
    float t;

    if (p1x == p2x && p1y == p2y)
    {
        /* Zero rotation */
        vzero(q);
        q[3] = 1.0f;
        return;
    }

    /*
     * First, figure out z-coordinates for projection of P1 and P2 to
     * deformed sphere
     */
    vset(p1, p1x, p1y, tb_project_to_sphere(TRACKBALLSIZE, p1x, p1y));
    vset(p2, p2x, p2y, tb_project_to_sphere(TRACKBALLSIZE, p2x, p2y));

    /* Now, we want the cross product of P1 and P2 */
    vcross(p2, p1, a);

    /* Figure out how much to rotate around that axis. */
    vsub(p1, p2, d);
    t = vlength(d) / (2.0f * TRACKBALLSIZE);

    /* Avoid problems with out-of-control values... */
    if (t > max_velocity)
        t = max_velocity;
    if (t < -max_velocity)
        t = -max_velocity;
    phi = 2.0f * asin(t);

    axis_to_quat(a, phi, q);
}

/* Given an axis and angle, compute quaternion. */
void axis_to_quat(float[] a, float phi, float[] q)
{
    vnormal(a);
    vcopy(a, q);
    vscale(q, sin(phi / 2.0f));
    q[3] = cos(phi / 2.0f);
}

/*
 * Project an x,y pair onto a sphere of radius r OR a hyperbolic sheet
 * if we are away from the center of the sphere.
 */
float tb_project_to_sphere(float r, float x, float y)
{
    float d = sqrt(x * x + y * y);
    float z;
    if (d < r * 0.70710678118654752440f) /* Inside sphere */
    {
        z = sqrt(r * r - d * d);
    }
    else /* On hyperbola */
    {
        float t = r / 1.41421356237309504880f;
        z = t * t / d;
    }
    return z;
}

/*
 * Given two rotations, e1 and e2, expressed as quaternion rotations,
 * figure out the equivalent single rotation and stuff it into dest.
 *
 * This routine also normalizes the result every RENORMCOUNT times it
 * is called, to keep error from creeping in.
 *
 * NOTE: This routine is written so that q1 or q2 may be the same as
 * dest (or each other).
 */
enum int RENORMCOUNT = 97;

void add_quats(float[] q1, float[] q2, float[] dest)
{
    static int count = 0;
    float[4] t1, t2, t3, tf;

    vcopy(q1, t1);
    vscale(t1, q2[3]);

    vcopy(q2, t2);
    vscale(t2, q1[3]);

    vcross(q2, q1, t3);
    vadd(t1, t2, tf);
    vadd(t3, tf, tf);
    tf[3] = q1[3] * q2[3] - vdot(q1, q2);

    dest[0] = tf[0];
    dest[1] = tf[1];
    dest[2] = tf[2];
    dest[3] = tf[3];

    count++;
    if (count > RENORMCOUNT)
    {
        count = 0;
        normalize_quat(dest);
    }
}

/*
 * Quaternions always obey:  a^2 + b^2 + c^2 + d^2 = 1.0
 * If they don't add up to 1.0, dividing by their magnitude will
 * renormalize them.
 */
void normalize_quat(float[] q)
{
    float mag = q[0] * q[0] + q[1] * q[1] + q[2] * q[2] + q[3] * q[3];
    foreach (i; 0 .. 4)
        q[i] /= mag;
}

/* Build a rotation matrix, given a quaternion rotation. */
void build_rotmatrix(ref float[4][4] m, in float[] q)
{
    m[0][0] = 1.0f - 2.0f * (q[1] * q[1] + q[2] * q[2]);
    m[0][1] = 2.0f * (q[0] * q[1] - q[2] * q[3]);
    m[0][2] = 2.0f * (q[2] * q[0] + q[1] * q[3]);
    m[0][3] = 0.0f;

    m[1][0] = 2.0f * (q[0] * q[1] + q[2] * q[3]);
    m[1][1] = 1.0f - 2.0f * (q[2] * q[2] + q[0] * q[0]);
    m[1][2] = 2.0f * (q[1] * q[2] - q[0] * q[3]);
    m[1][3] = 0.0f;

    m[2][0] = 2.0f * (q[2] * q[0] - q[1] * q[3]);
    m[2][1] = 2.0f * (q[1] * q[2] + q[0] * q[3]);
    m[2][2] = 1.0f - 2.0f * (q[1] * q[1] + q[0] * q[0]);
    m[2][3] = 0.0f;

    m[3][0] = 0.0f;
    m[3][1] = 0.0f;
    m[3][2] = 0.0f;
    m[3][3] = 1.0f;
}
