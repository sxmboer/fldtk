// D transliteration of FLTK's test/checkers.cxx.
//
// Only the `#define FLTK` build is ported -- `#define VT100` is
// commented out in the real FLTK source (`//#define VT100`), so
// the VT100 terminal-mode interface, the `#ifdef BOTH` command-line
// `-t` switch, and everything else gated on those two macros were
// never actually compiled by FLTK either; porting only what's
// really built matches this project's own established convention
// (see e.g. `mandelbrot`/`keyboard`'s own driver files).
//
// The 4 checkers-piece PNGs (`checkers_pieces.fl`'s own `data { filename
// ... }` blocks, FLTK Fluid-generated into `checkers_pieces.h`/
// `.cxx` as raw C byte arrays) are ported as `checkers_pieces.d`
// (script-generated from the real PNG files, byte-for-byte -- see that
// file's own top comment) and decoded here via `fl.png_image.PngImage`.
//
// Deliberate simplifications vs. FLTK, both narrow and documented
// at their point of use below:
//  - `Fl_Menu_Item`'s `debug_cb()`/`forced_cb()` mutate the *specific*
//    menu item that was clicked via its own `void*` user-data slot
//    (FLTK passes the item pointer itself as user-data specifically
//    for this). This port has no delegate/user-data equivalent for a
//    `MenuItem*` (`fl.menu_item`'s own `Callback` is `void delegate
//    (Widget)`, matching CONVENTIONS.md's callback convention) -- instead,
//    both toggle items' `.flags` are refreshed from the real `bool`
//    state (`refreshToggleFlags()`) right before either menu is shown,
//    which is the only time the checkbox state is actually observed.
//  - `node` (a manually `malloc()`/free-list-recycled C struct with
//    bitfield flags) becomes a plain GC-managed `class Node` with
//    `bool` fields instead of `unsigned x:1` bitfields -- the bitfields
//    existed purely for C-era memory packing, no reason to carry that
//    over (same substitution CONVENTIONS.md documents elsewhere for packed
//    FLTK types). `killnode()` keeps its real, load-bearing half
//    (recursively decrementing the `nodes` search-bound counter and
//    detaching the subtree) but drops the free-list-recycling half
//    entirely -- that part existed only to avoid `malloc()` overhead,
//    moot under the GC.
//  - `fl.core.flush()` (ported from `Fl::flush()`) -- see that
//    function's own doc comment in `fl.core.d` for why `computer_move()`
//    genuinely needs it (making the wait cursor visible before a long
//    synchronous AI search blocks the event loop).
//  - `evaluateboard()`'s `switch (tb[i])` merges `case ENEMY:` with the
//    `J1:` fallthrough target `case ENEMYKING:` jumps to; `case ENEMY:`
//    resets `deniedmoves`/`undeniedmoves` to `0` before falling into
//    `J1:`, matching FLTK (the `ENEMYKING` case's own `goto` skips
//    that reset deliberately, since it already did the same reset
//    itself a few lines earlier).
//
// Found, NOT fixed (ported faithfully, flagged here rather than
// silently worked around or silently corrected -- see CONVENTIONS.md's
// FLTK-bug process): in `movepiece()`, the kinging check
// `!(oldpiece&KING) && n->who ? (j>=36) : (j<=8)` parses (`&&` binds
// tighter than `?:`) as `(!(oldpiece&KING) && n->who) ? (j>=36) :
// (j<=8)` -- for a piece that's *already* a king, the left side is
// always false regardless of `n->who`, so the check silently degrades
// to plain `j<=8` instead of skipping the kinging branch outright. In
// practice this only sets `n->king` (and OR's in an already-set KING
// bit, a no-op) on an ordinary move by a white king that happens to
// land on a low-numbered square -- mostly harmless *except* that
// `undomove()` reads `n->king` to decide whether to strip the KING bit
// on undo, so undoing such a move could incorrectly demote an
// already-crowned king back to a plain piece. Ported with the exact
// same precedence (not "fixed") in both `movepiece()` call sites below.
//
// `usermoves()`'s own bounds check is one narrow exception to "port
// faithfully": FLTK's `idx > (int)sizeof(_usermoves)-1` (sizeof
// includes the C string's trailing NUL) allows `idx` one past the
// last real character through, reading the harmless NUL byte as a
// board-index sentinel -- FLTK's own array is sized to make that
// safe. A D string's `.length` has no such trailing slot, so the same
// bound would be a real out-of-bounds read here; using `idx >=
// usermovesTable.length` instead (returning '?' one index earlier)
// is a strictly safer match for the same intent, not a behavior
// FLTK depends on anywhere.
module checkers;

import fl;
import checkers_pieces;
import std.format : format;
import std.math : abs;
import std.stdio : writefln;

////////////////////////////////////////////////////////////////
// The algorithm (ported from checkers.cxx's own top section,
// unchanged behavior, `node*`/bitfields -> `class Node`/`bool` per
// this file's own top comment):

int maxevaluate = 2500;         // max number of moves to examine on a turn
int maxnodes = 2500;            // maximum number of nodes in search tree
int maxply = 20;                // maximum depth to look ahead
bool forcejumps = true;         // is forced jumps rule in effect?

// scoring parameters: (all divided by 5 from original code)
// some signs seem to be backwards, marked them with (-) in comment
enum int spiece = 800;          // value of a piece
enum int sking = 1200;          // value of a king
enum int sadvan = 160;          // value of mypieces/theirpieces-1
enum int sallpin = 80;          // mobil == 0
enum int sdeny = 10;            // moves enemy can make that will be jumped
enum int spin = 32;             // enemy pieces that have no move except jumped
enum int sthreat = -10;         // enemy pieces we can jump if not moved (-)
enum int sgrad = 1;             // score of piece positions
enum int sback = 10;            // back row occupied so enemy can't make king
enum int smoc2 = 200;           // more mobility, more center
enum int smoc3 = -8;            // less mobility, less center
enum int smoc4 = -80;           // more mobility, less center
enum int smode2 = -14;          // less mobility, less denied
enum int smode3 = -40;          // more mobility, more denied (-)
enum int sdemmo = -20;          // more denied, more moves (-)
enum int scent = 10;            // pieces in center
enum int skcent = 100;          // kings in center

enum int depthpenalty = 4;      // guess
enum int noise = 2;             // values less or eq to this apart are eq

final class Node
{
    Node father;
    Node son;            // best son
    Node brother;        // next brother
    int value;            // value of this board position to player making move
    int from, to;         // the move to reach this board
    int jump;             // bit map of locations jumped
    int mobil;
    int deny;
    int pin;
    int threat;
    int gradient;
    bool who;             // false = black's move, true = white's move
    bool king;            // true = move causes piece to be kinged
    bool back;
    bool moc2;
    bool moc3;
    bool moc4;
    bool mode2;
    bool mode3;
    bool demmo;
}

int nodes;               // count of nodes

/*      Board positions:        Border positions:

              WHITE               00  01  02  03  04
          05  06  07  08        04  XX  XX  XX  XX
        09  10  11  12            XX  XX  XX  XX  13
          14  15  16  17        13  XX  XX  XX  XX
        18  19  20  21            XX  XX  XX  XX  22
          23  24  25  26        22  XX  XX  XX  XX
        27  28  29  30            XX  XX  XX  XX  31
          32  33  34  36        31  XX  XX  XX  XX
        36  37  38  39            XX  XX  XX  XX  40
              BLACK             40  41  42  43  44

*/

alias Piece = ubyte;

// Piece values so that BLACK and WHITE are bit flags:
enum EMPTY = 0;
enum BLACK = 1;
enum WHITE = 2;
enum KING = 4;
enum BLACKKING = 5;
enum WHITEKING = 6;
enum BLUE = 8;

immutable Piece[9] flip = [EMPTY, WHITE, BLACK, 0, 0, WHITEKING, BLACKKING, 0, BLUE];

immutable int[4][9] offset = [      // legal move directions
    [0, 0, 0, 0],
    [-5, -4, 0, 0],
    [4, 5, 0, 0],
    [0, 0, 0, 0],
    [0, 0, 0, 0],
    [4, 5, -4, -5],
    [4, 5, -4, -5],
    [0, 0, 0, 0],
    [0, 0, 0, 0],
];

Piece[45] b;             // current board position being considered

int evaluated;           // number of moves evaluated this turn

bool[45] centralsquares;
bool[45] isProtected;

Piece[45] flipboard;     // swapped if enemy is black
Piece[] tb;              // slice aliasing either b[] or flipboard[]
enum FRIEND = BLACK;
enum FRIENDKING = BLACKKING;
enum ENEMY = WHITE;
enum ENEMYKING = WHITEKING;

bool check(int target, int direction)
{
    // see if enemy at target can be jumped from direction by our piece
    int dst = target - direction;
    if (tb[dst]) return false;
    int src = target + direction;
    if (tb[src] == FRIENDKING) {}
    else if (direction < 0 || tb[src] != FRIEND) return false;
    Piece aa = tb[target], bb = tb[src];
    tb[target] = EMPTY; tb[src] = EMPTY;
    bool safe =
        ((tb[src - 4] & FRIEND) && (tb[src - 8] & ENEMY))
        || ((tb[src - 5] & FRIEND) && (tb[src - 10] & ENEMY))
        || ((tb[dst - 4] & ENEMY) && !tb[dst + 4])
        || ((tb[dst - 5] & ENEMY) && !tb[dst + 5])
        || ((tb[src + 4] & FRIEND) && tb[src + 8] == ENEMYKING)
        || ((tb[src + 5] & FRIEND) && tb[src + 10] == ENEMYKING)
        || (tb[dst + 4] == ENEMYKING && !tb[dst - 4])
        || (tb[dst + 5] == ENEMYKING && !tb[dst - 5]);
    tb[target] = aa; tb[src] = bb;
    return safe;
}

int deniedmoves, undeniedmoves;
void analyzemove(int direction, int src)
{
    int target = src + direction;
    if (!tb[target])
    {
        if (!tb[target + direction]) isProtected[target] = true;
        Piece a = tb[src]; tb[src] = EMPTY;
        if (check(target, 4) || check(target, 5) ||
            check(target, -4) || check(target, -5) ||
            ((tb[src + 4] & ENEMY) && check(src + 4, 4)) ||
            ((tb[src + 5] & ENEMY) && check(src + 5, 5)) ||
            ((tb[src - 4] & ENEMY) && check(src - 4, -4)) ||
            ((tb[src - 5] & ENEMY) && check(src - 5, -5)))
            deniedmoves++;
        else undeniedmoves++;
        tb[src] = a;
    }
}

void evaluateboard(Node n, bool print)
{
    if (!n.who) tb = b[];  // move was black's
    else
    {
        foreach (i; 0 .. 45) flipboard[44 - i] = flip[b[i]];
        tb = flipboard[];
    }

    isProtected[] = false;
    int friendpieces = 0;
    int enemypieces = 0;
    int friendkings = 0;
    int enemykings = 0;
    int friendkcent = 0;
    int friendcent = 0;
    int enemykcent = 0;
    int enemycent = 0;
    n.mobil = n.deny = n.pin = n.threat = 0;

    int i;
    for (i = 5; i < 40; i++) switch (tb[i])
    {
        case ENEMYKING:
            enemykings++;
            enemykcent += centralsquares[i];
            deniedmoves = 0;
            undeniedmoves = 0;
            if (i > 8)
            {
                analyzemove(-4, i);
                analyzemove(-5, i);
            }
            goto case ENEMY;
        case ENEMY:
            deniedmoves = 0;
            undeniedmoves = 0;
        J1:
            enemypieces++;
            enemycent += centralsquares[i];
            if (i < 36)
            {
                analyzemove(4, i);
                analyzemove(5, i);
            }
            if (deniedmoves && !undeniedmoves) n.pin++;
            n.deny += deniedmoves;
            n.mobil += undeniedmoves;
            break;
        case FRIENDKING:
            friendkings++;
            friendkcent += centralsquares[i];
            if ((tb[i + 4] & ENEMY) && !tb[i + 8] && !(tb[i + 4] == ENEMYKING && !tb[i - 4]))
                n.threat++;
            if ((tb[i + 5] & ENEMY) && !tb[i + 10] && !(tb[i + 5] == ENEMYKING && !tb[i - 5]))
                n.threat++;
            goto case FRIEND;
        case FRIEND:
            friendpieces++;
            friendcent += centralsquares[i];
            if ((tb[i - 4] & ENEMY) && !tb[i - 8] && tb[i + 4]) n.threat++;
            if ((tb[i - 5] & ENEMY) && !tb[i - 10] && tb[i + 5]) n.threat++;
            break;
        default:
            break;
    }

    int[40] gradient;
    for (i = 4; i < 9; i++) gradient[i] = tb[i] ? 0 : 32;
    int total = 0;
    for (i = 9; i < 40; i++)
    {
        int x = (gradient[i - 4] + gradient[i - 5]) / 2;
        if (tb[i] == FRIEND) total += x;
        gradient[i] = (tb[i] & FRIEND || (!tb[i] && !isProtected[i])) ? x : 0;
    }
    n.gradient = total;

    n.back = tb[39] == FRIEND && tb[37] == FRIEND && !enemykings;

    Node f = n.father;

    n.moc2 = f.mobil > n.mobil && friendcent > enemycent;
    n.moc3 = f.mobil <= n.mobil && friendcent < enemycent;
    n.moc4 = f.mobil > n.mobil && friendcent < enemycent;
    n.mode2 = f.mobil <= n.mobil && n.deny < f.deny;
    n.mode3 = f.mobil > n.mobil && n.deny > f.deny;
    n.demmo = n.deny > f.deny && f.deny + f.mobil > n.deny + n.mobil;

    total =
        spiece * (friendpieces - enemypieces) +
        (sking - spiece) * (friendkings - enemykings) +
        sdeny * (n.deny - f.deny) +
        spin * (n.pin - f.pin) +
        sthreat * (n.threat - f.threat) +
        sgrad * (n.gradient - f.gradient) +
        sback * (cast(int) n.back - cast(int) f.back) +
        smoc2 * (cast(int) n.moc2 - cast(int) f.moc2) +
        smoc3 * (cast(int) n.moc3 - cast(int) f.moc3) +
        smoc4 * (cast(int) n.moc4 - cast(int) f.moc4) +
        smode2 * (cast(int) n.mode2 - cast(int) f.mode2) +
        smode3 * (cast(int) n.mode3 - cast(int) f.mode3) +
        sdemmo * (cast(int) n.demmo - cast(int) f.demmo) +
        scent * (friendcent - enemycent) +
        (skcent - scent) * (friendkcent - enemykcent);
    if (!n.mobil) total += sallpin;

    if (!enemypieces) total = 30000;
    else if (friendpieces > enemypieces)
        total += (sadvan * friendpieces) / enemypieces - sadvan;
    else total -= (sadvan * enemypieces) / friendpieces - sadvan;

    if (print)
    {
        writefln("\tParent\tNew\tScore");
        writefln("pieces\t%d\t%d\t%d", enemypieces, friendpieces, spiece * (friendpieces - enemypieces));
        writefln("kings\t%d\t%d\t%d", enemykings, friendkings, (sking - spiece) * (friendkings - enemykings));
        writefln("mobil\t%d\t%d", f.mobil, n.mobil);
        writefln("deny\t%d\t%d\t%d", f.deny, n.deny, sdeny * (n.deny - f.deny));
        writefln("pin\t%d\t%d\t%d", f.pin, n.pin, spin * (n.pin - f.pin));
        writefln("threat\t%d\t%d\t%d", f.threat, n.threat, sthreat * (n.threat - f.threat));
        writefln("grad\t%d\t%d\t%d", f.gradient, n.gradient, sgrad * (n.gradient - f.gradient));
        writefln("back\t%d\t%d\t%d", f.back, n.back, sback * (cast(int) n.back - cast(int) f.back));
        writefln("moc2\t%d\t%d\t%d", f.moc2, n.moc2, smoc2 * (cast(int) n.moc2 - cast(int) f.moc2));
        writefln("moc3\t%d\t%d\t%d", f.moc3, n.moc3, smoc3 * (cast(int) n.moc3 - cast(int) f.moc3));
        writefln("moc4\t%d\t%d\t%d", f.moc4, n.moc4, smoc4 * (cast(int) n.moc4 - cast(int) f.moc4));
        writefln("mode2\t%d\t%d\t%d", f.mode2, n.mode2, smode2 * (cast(int) n.mode2 - cast(int) f.mode2));
        writefln("mode3\t%d\t%d\t%d", f.mode3, n.mode3, smode3 * (cast(int) n.mode3 - cast(int) f.mode3));
        writefln("demmo\t%d\t%d\t%d", f.demmo, n.demmo, sdemmo * (cast(int) n.demmo - cast(int) f.demmo));
        writefln("cent\t%d\t%d\t%d", enemycent, friendcent, scent * (friendcent - enemycent));
        writefln("kcent\t%d\t%d\t%d", enemykcent, friendkcent, skcent * (friendkcent - enemykcent));
        writefln("total:\t\t\t%d", total);
    }
    else
    {
        n.value = total;
        evaluated++;
    }
}       // end of evaluateboard

// --------------------- Tree management -----------------

Node newnode()
{
    nodes++;
    return new Node();
}

void extract(Node n)
{
    Node i = n.father;
    if (i !is null)
    {
        Node j = i.son;
        if (j is n) i.son = n.brother;
        else while (j !is null)
        {
            i = j; j = j.brother;
            if (j is n) { i.brother = n.brother; break; }
        }
    }
    n.brother = null;
}

// Recursively decrements the `nodes` search-bound counter and detaches
// the subtree -- see this file's own top comment for why the C
// original's free-list memory recycling isn't ported (moot under the
// GC).
void killnode(Node x)
{
    if (x is null) return;
    for (Node y = x; ; y = y.brother)
    {
        nodes--;
        killnode(y.son); y.son = null;
        if (y.brother is null) break;
    }
}

int seed;                // current random number

void insert(Node n)
{
    int val = n.value;
    Node* pp;
    for (pp = &(n.father.son); *pp !is null; pp = &((*pp).brother))
    {
        int val1 = (*pp).value;
        if (abs(val - val1) <= noise)
        {
            seed = (seed * 13077 + 5051) % 32768; // 0100000 octal
            if ((seed & 56) >= 48) break; // 070 / 060 octal
        }
        else if (val > val1) break;
    }
    n.brother = *pp;
    *pp = n;
}

// --------------------------------------------------------------

void movepiece(Node f, int i, Node jnode)
{
    static bool jumphappened;

    for (int k = 0; k < 4; k++)
    {
        int direction = offset[b[i]][k];
        if (!direction) break;
        int j = i + direction;
        if (b[j] == EMPTY)
        {
            if (jnode is null && (!forcejumps || f.son is null || !f.son.jump))
            {
                Node n = newnode();
                n.father = f;
                n.who = !f.who;
                n.from = i;
                n.to = j;
                Piece oldpiece = b[i]; b[i] = EMPTY;
                if ((!(oldpiece & KING) && n.who) ? (j >= 36) : (j <= 8))
                {
                    n.king = true;
                    b[j] = cast(Piece)(oldpiece | KING);
                }
                else b[j] = oldpiece;
                evaluateboard(n, false);
                insert(n);
                b[i] = oldpiece; b[j] = EMPTY;
            }
        }
        else if (((b[j] ^ b[i]) & (WHITE | BLACK)) == (WHITE | BLACK) && !b[j + direction])
        {
            if (forcejumps && f.son !is null && !f.son.jump)
            {
                killnode(f.son);
                f.son = null;
            }
            int jumploc = j;
            j += direction;
            Node n = newnode();
            n.father = f;
            n.who = !f.who;
            n.from = i;
            n.to = j;
            n.jump = (1 << (jumploc - 10));
            Piece oldpiece = b[i]; b[i] = EMPTY;
            if ((!(oldpiece & KING) && n.who) ? (j >= 36) : (j <= 8))
            {
                n.king = true;
                b[j] = cast(Piece)(oldpiece | KING);
            }
            else b[j] = oldpiece;
            if (jnode !is null)
            {
                n.from = jnode.from;
                n.jump |= jnode.jump;
                n.king |= jnode.king;
            }
            Piece jumpedpiece = b[jumploc];
            b[jumploc] = EMPTY;
            jumphappened = false;
            movepiece(f, j, n);
            if (forcejumps && jumphappened) killnode(n);
            else { evaluateboard(n, false); insert(n); }
            b[i] = oldpiece; b[j] = EMPTY;
            b[jumploc] = jumpedpiece;
            jumphappened = true;
        }
    }
}

void expandnode(Node f)
{
    if (f.son !is null || f.value > 28000) return;       // already done
    Piece turn = f.who ? BLACK : WHITE;
    for (int i = 5; i < 40; i++) if (b[i] & turn) movepiece(f, i, null);
    if (f.son !is null)
    {
        f.value = -f.son.value;
        if (f.brother !is null) f.value -= depthpenalty;
    }
    else f.value = 30000;
}

void makemove(Node n)
{
    b[n.to] = b[n.from];
    if (n.king) b[n.to] = cast(Piece)(b[n.to] | KING);
    b[n.from] = EMPTY;
    if (n.jump) for (int i = 0; i < 32; i++)
        if (n.jump & (1 << i)) b[10 + i] = EMPTY;
}

bool didabort();

bool fullexpand(Node f, int level)
{
    if (didabort() || nodes > maxnodes - (maxply * 10) || evaluated > maxevaluate) return false;
    expandnode(f);
    if (f.son is null) return true;
    Piece[45] oldboard = b;
    Node n = f.son;
    if (!n.jump && n.brother !is null) { if (level < 1) return true; level--; }
    Node[] sons;
    for (Node nn = n; nn !is null; nn = nn.brother) sons ~= nn;
    bool ret = true;
    foreach (nn; sons)
    {
        if (!ret) break;
        makemove(nn);
        ret = fullexpand(nn, level);
        b = oldboard;
        extract(nn);
        insert(nn);
    }
    f.value = -f.son.value;
    return ret;
}

bool descend(Node f)
{
    static int depth;
    if (didabort() || nodes > maxnodes || depth >= maxply) return false;
    if (f.son !is null)
    {
        Node n = f.son;
        makemove(n);
        depth++;
        bool ret = descend(n);
        depth--;
        extract(n);
        insert(n);
        f.value = -f.son.value;
        return ret;
    }
    else { expandnode(f); return true; }
}

bool debugFlag;      // named to avoid colliding with D's `debug` keyword

Node calcmove(Node root)
{
    expandnode(root);
    if (root.son is null) return null;    // no move due to loss
    if (debugFlag) writefln("calcmove() initial nodes = %d", nodes);
    evaluated = 0;
    if (root.son.brother !is null)
    {
        int x;
        for (x = 1; abs(root.value) < 28000 && fullexpand(root, x); x++) {}
        Piece[45] saveboard = b;
        while (abs(root.value) < 28000)
        {
            bool cont = descend(root);
            b = saveboard;
            if (!cont) break;
        }
    }
    if (debugFlag) writefln(" evaluated %d, nodes = %d", evaluated, nodes);
    return root.son;
}

// the actual game state ----------------

Node root, undoroot;

Piece[45][24] jumpboards;    // saved boards for undoing jumps
int nextjump;

bool user;       // false = black, true = white
bool playing;
bool autoplay;

void newgame()
{
    foreach (n; 0 .. 5) b[n] = BLUE;
    foreach (n; 5 .. 18) b[n] = WHITE;
    foreach (n; 18 .. 27) b[n] = EMPTY;
    foreach (n; 27 .. 40) b[n] = BLACK;
    foreach (n; 40 .. 45) b[n] = BLUE;
    b[13] = b[22] = b[31] = BLUE;

    centralsquares[15] = centralsquares[16] =
        centralsquares[19] = centralsquares[20] =
        centralsquares[24] = centralsquares[25] =
        centralsquares[28] = centralsquares[29] = true;

    // set up initial search tree:
    nextjump = 0;
    killnode(undoroot);
    undoroot = root = newnode();

    // make it white's move, so first move is black:
    root.who = true;
    user = false;
    playing = true;
}

void domove(Node move)
{
    if (move.jump) jumpboards[nextjump++] = b;
    makemove(move);
    extract(move);
    killnode(root.son);
    root.son = move;
    root = move;
    if (debugFlag) evaluateboard(move, true);
}

Node undomove()
{
    Node n = root;
    if (n is undoroot) return null; // no more undo possible
    if (n.jump) b = jumpboards[--nextjump];
    else
    {
        b[n.from] = b[n.to];
        if (n.king) b[n.from] = cast(Piece)(b[n.from] & (WHITE | BLACK));
        b[n.to] = EMPTY;
    }
    root = n.father;
    killnode(n);
    root.son = null;
    root.value = 0;   // prevent it from thinking game is over
    playing = true;
    if (root is undoroot) user = false;
    return n;
}

immutable string usermovesTable =
    "B1D1F1H1A2C2E2G2??B3D3F3H3A4C4E4G4??B5D5F5H5A6C6E6G6??B7D7F7H7A8C8E8G8??";

// See this file's own top comment on the one deliberate deviation from
// FLTK's own bounds check here.
char usermoves(int x, int y)
{
    int idx = 2 * (x - 5) + y - 1;
    if (idx < 0 || idx >= cast(int) usermovesTable.length) return '?';
    return usermovesTable[idx];
}

int abortflag;

bool didabort()
{
    fl.core.check();
    if (abortflag)
    {
        autoplay = false;
        abortflag = false;
        return true;
    }
    return false;
}

////////////////////////////////////////////////////////////////
// fltk interface:

//----------------------------------------------------------------
// Checkers pieces with built in transparency/drop shadows

PngImage[4] png;

void make_pieces()
{
    if (png[0] !is null) return;
    png[0] = new PngImage(null, pixmapsBlackCheckerPng);
    png[1] = new PngImage(null, pixmapsWhiteCheckerPng);
    png[2] = new PngImage(null, pixmapsBlackCheckerKingPng);
    png[3] = new PngImage(null, pixmapsWhiteCheckerKingPng);
    foreach (p; png) p.scale(p.dataW() / 2, p.dataH() / 2);
}

enum ISIZE = 62;        // old: 56

void draw_piece(int which, int x, int y)
{
    if (!notClipped(x, y, ISIZE, ISIZE)) return;
    int idx;
    switch (which)
    {
        case BLACK: idx = 0; break;
        case WHITE: idx = 1; break;
        case BLACKKING: idx = 2; break;
        case WHITEKING: idx = 3; break;
        default: return;
    }
    png[idx].draw(x, y);
}

//----------------------------------------------------------------

enum BOXSIZE = 52;
enum BORDER = 4;
enum BOARDSIZE = 8 * BOXSIZE + BORDER;
enum BMOFFSET = 3;

int erase_this;   // real location of dragging piece, don't draw it
int dragging;     // piece being dragged
int dragx;        // where it is
int dragy;
int showlegal;    // show legal moves

int squarex(int i) { return (usermoves(i, 1) - 'A') * BOXSIZE + BMOFFSET; }
int squarey(int i) { return (usermoves(i, 2) - '1') * BOXSIZE + BMOFFSET; }

class Board : DoubleWindow
{
    this(int w, int h)
    {
        super(w, h, "FLTK Checkers");
        color(15);
    }

    override void draw()
    {
        make_pieces();
        // -- draw the board itself
        drawBoxAt(box(), 0, 0, w(), h(), color());
        // -- draw all dark tiles
        fl_color(cast(Color) 10 /*107*/);
        for (int x = 0; x < 8; x++) for (int y = 0; y < 8; y++)
        {
            if (!((x ^ y) & 1)) fl_rectf(BORDER + x * BOXSIZE, BORDER + y * BOXSIZE,
                BOXSIZE - BORDER, BOXSIZE - BORDER);
        }
        // -- draw outlines around the fields
        fl_color(dark3);
        for (int x = 0; x < 9; x++)
        {
            fl_rectf(x * BOXSIZE, 0, BORDER, h());
            fl_rectf(0, x * BOXSIZE, w(), BORDER);
        }
        for (int j = 5; j < 40; j++) if (j != erase_this)
            draw_piece(b[j], squarex(j), squarey(j));

        if (showlegal)
        {
            fl_color(white);
            for (Node n = root.son; n !is null; n = showlegal == 2 ? n.son : n.brother)
            {
                int x1 = squarex(n.from) + BOXSIZE / 2 - 5;
                int y1 = squarey(n.from) + BOXSIZE / 2 - 5;
                int x2 = squarex(n.to) + BOXSIZE / 2 - 5;
                int y2 = squarey(n.to) + BOXSIZE / 2 - 5;
                fl_line(x1, y1, x2, y2);
                pushMatrix();
                multMatrix(x2 - x1, y2 - y1, y1 - y2, x2 - x1, x2, y2);
                beginPolygon();
                vertex(0, 0);
                vertex(-.3, .1);
                vertex(-.3, -.1);
                endPolygon();
                popMatrix();
            }
            int num = 1;
            fl_color(black);
            fl_font(bold, 10);
            for (Node n = root.son; n !is null; n = showlegal == 2 ? n.son : n.brother)
            {
                int x1 = squarex(n.from) + BOXSIZE / 2 - 5;
                int y1 = squarey(n.from) + BOXSIZE / 2 - 5;
                int x2 = squarex(n.to) + BOXSIZE / 2 - 5;
                int y2 = squarey(n.to) + BOXSIZE / 2 - 5;
                fl_draw(format("%d", num), x1 + cast(int)((x2 - x1) * .85) - 3, y1 + cast(int)((y2 - y1) * .85) + 5);
                num++;
            }
        }
        if (dragging) draw_piece(dragging, dragx, dragy);
    }

    // drag the piece on square i to dx dy, or undo drag if i is zero:
    void drag_piece(int j, int dx, int dy)
    {
        dy = (dy & -2) | (dx & 1); // make halftone shadows line up
        if (j != erase_this) drop_piece(erase_this); // should not happen
        if (!erase_this) // pick up old piece
        {
            dragx = squarex(j); dragy = squarey(j);
            erase_this = j;
            dragging = b[j];
        }
        if (dx != dragx || dy != dragy)
        {
            damage(damageAll, dragx, dragy, ISIZE, ISIZE);
            damage(damageAll, dx, dy, ISIZE, ISIZE);
        }
        dragx = dx;
        dragy = dy;
    }

    // drop currently dragged piece on square i
    void drop_piece(int j)
    {
        if (!erase_this) return; // should not happen!
        erase_this = 0;
        dragging = 0;
        int x = squarex(j);
        int y = squarey(j);
        if (x != dragx || y != dragy)
        {
            // matches FLTK's own literal `4` here (FL_DAMAGE_SCROLL),
            // not FL_DAMAGE_ALL like drag_piece() above uses -- ported
            // faithfully as a real, if probably accidental, FLTK
            // inconsistency, not "fixed."
            damage(4, dragx, dragy, ISIZE, ISIZE);
            damage(4, x, y, ISIZE, ISIZE);
        }
    }

    // show move (call this *before* the move, *after* undo):
    void animate(Node move, bool backwards)
    {
        if (showlegal) { showlegal = 0; redraw(); }
        if (move is null) return;
        int f = move.from;
        int t = move.to;
        if (backwards) { int x = f; f = t; t = x; }
        int x1 = squarex(f);
        int y1 = squarey(f);
        int x2 = squarex(t);
        int y2 = squarey(t);
        enum STEPS = 35;
        for (int j = 0; j < STEPS; j++)
        {
            int x = x1 + (x2 - x1) * j / STEPS;
            int y = y1 + (y2 - y1) * j / STEPS;
            drag_piece(move.from, x, y);
            fl.core.flush();
            fl.wait(0.01);
        }
        drop_piece(t);
        if (move.jump) redraw();
    }

    void computer_move(bool help)
    {
        if (!playing) return;
        cursor(Cursor.wait);
        fl.core.flush();
        busy = true; abortflag = false;
        Node move = calcmove(root);
        busy = false;
        if (move !is null)
        {
            if (!help && move.value <= -30000)
            {
                fl.message(format("%s resigns", move.who ? "White" : "Black"));
                playing = autoplay = false;
                cursor(Cursor.default_);
                return;
            }
            animate(move, false);
            domove(move);
        }
        expandnode(root);
        if (root.son is null)
        {
            fl.message(format("%s has no move", root.who ? "Black" : "White"));
            playing = autoplay = false;
        }
        if (!autoplay) cursor(Cursor.default_);
    }

    override int handle(Event e)
    {
        if (busy)
        {
            const(MenuItem)* m;
            switch (e)
            {
                case Event.push:
                    refreshToggleFlags();
                    m = fl.menu_popup.popup(busymenu.ptr, eventX(), eventY());
                    if (m !is null) m.doCallback(this);
                    return 1;
                case Event.shortcut:
                    m = busymenu[0].testShortcut();
                    if (m !is null) { m.doCallback(this); return 1; }
                    return 0;
                default:
                    return 0;
            }
        }

        static int deltax, deltay;
        const(MenuItem)* m;
        switch (e)
        {
            case Event.push:
                if (eventButton() > 1)
                {
                    refreshToggleFlags();
                    m = fl.menu_popup.popup(menu.ptr, eventX(), eventY());
                    if (m !is null) m.doCallback(this);
                    return 1;
                }
                if (playing)
                {
                    expandnode(root);
                    for (Node t = root.son; t !is null; t = t.brother)
                    {
                        int x = squarex(t.from);
                        int y = squarey(t.from);
                        if (eventInside(x, y, BOXSIZE, BOXSIZE))
                        {
                            deltax = eventX() - x;
                            deltay = eventY() - y;
                            drag_piece(t.from, x, y);
                            return 1;
                        }
                    }
                }
                return 0;
            case Event.shortcut:
                m = menu[0].testShortcut();
                if (m !is null) { m.doCallback(this); return 1; }
                return 0;
            case Event.drag:
                drag_piece(erase_this, eventX() - deltax, eventY() - deltay);
                return 1;
            case Event.release:
                // find the closest legal move he dropped it on:
                int dist = 50 * 50;
                Node n;
                for (Node t = root.son; t !is null; t = t.brother) if (t.from == erase_this)
                {
                    int d1 = eventX() - deltax - squarex(t.to);
                    int d = d1 * d1;
                    d1 = eventY() - deltay - squarey(t.to);
                    d += d1 * d1;
                    if (d < dist) { dist = d; n = t; }
                }
                if (n is null) { drop_piece(erase_this); return 1; } // none found
                drop_piece(n.to);
                domove(n);
                if (showlegal) { showlegal = 0; redraw(); }
                if (n.jump) redraw();
                computer_move(false);
                return 1;
            default:
                return 0;
        }
    }
}

bool busy; // causes pop-up abort menu

void quit_cb(Widget w) { fl.hideAllWindows(); }

void autoplay_cb(Widget bp)
{
    if (autoplay) { autoplay = false; return; }
    if (!playing) return;
    Board board = cast(Board) bp;
    autoplay = true;
    while (autoplay) { board.computer_move(false); board.computer_move(false); }
}

Window copyright_window;
void copyright_cb(Widget w)
{
    if (copyright_window is null)
    {
        copyright_window = new Window(400, 270, "Copyright");
        copyright_window.color(white);
        auto box = new Box(20, 0, 380, 270, copyrightText);
        box.labelsize(10);
        box.alignment(cast(Align)(alignLeft | alignInside | alignWrap));
        copyright_window.end();
    }
    copyright_window.hotspot(copyright_window);
    copyright_window.setNonModal();
    copyright_window.show();
}

// See this file's own top comment: FLTK mutates the *specific*
// clicked MenuItem's own .flags via user-data; this port instead
// refreshes both toggle items' .flags from the real bool state right
// before either menu is shown (Board.handle()'s two Event.push cases),
// so these callbacks only need to flip the underlying bool.
void debug_cb(Widget w)
{
    debugFlag = !debugFlag;
}

void forced_cb(Widget w)
{
    forcejumps = !forcejumps;
    killnode(root.son); root.son = null;
    if (showlegal) { expandnode(root); w.redraw(); }
}

void move_cb(Widget pb)
{
    Board board = cast(Board) pb;
    if (playing) board.computer_move(true);
    if (playing) board.computer_move(false);
}

void newgame_cb(Widget w)
{
    showlegal = 0;
    newgame();
    w.redraw();
}

void legal_cb(Widget pb)
{
    if (showlegal == 1) { showlegal = 0; pb.redraw(); return; }
    if (!playing) return;
    expandnode(root);
    showlegal = 1; pb.redraw();
}

void predict_cb(Widget pb)
{
    if (showlegal == 2) { showlegal = 0; pb.redraw(); return; }
    if (playing) expandnode(root);
    showlegal = 2; pb.redraw();
}

void switch_cb(Widget pb)
{
    user = !user;
    (cast(Board) pb).computer_move(false);
}

void undo_cb(Widget pb)
{
    Board board = cast(Board) pb;
    board.animate(undomove(), true);
    board.animate(undomove(), true);
}

//--------------------------

Window intel_window;
ValueOutput intel_output;

void intel_slider_cb(Widget w)
{
    double v = (cast(Slider) w).value();
    int n = cast(int)(v * v);
    intel_output.value(n);
    maxevaluate = maxnodes = n;
}

void intel_cb(Widget w)
{
    if (intel_window is null)
    {
        intel_window = new Window(200, 25, "Checkers Intelligence");
        auto s = new Slider(60, 0, 140, 25);
        s.type(horNiceSlider);
        s.minimum(1); s.maximum(500); s.value(50);
        s.callback((sw) { intel_slider_cb(sw); });
        intel_output = new ValueOutput(0, 0, 60, 25);
        intel_output.value(maxevaluate);
        intel_window.resizable(s);
    }
    intel_window.hotspot(intel_window);
    intel_window.setNonModal();
    intel_window.show();
}

//---------------------------

void stop_cb(Widget w) { abortflag = true; }

void continue_cb(Widget w) {}

void refreshToggleFlags()
{
    menu[7].flags = forcejumps ? (menuToggle | menuValue) : menuToggle;
    menu[8].flags = debugFlag ? (menuToggle | menuValue) : menuToggle;
    busymenu[3].flags = debugFlag ? (menuToggle | menuValue) : menuToggle;
}

MenuItem[13] menu = [
    MenuItem("Autoplay", 'a', (w) { autoplay_cb(w); }),
    MenuItem("Legal moves", 'l', (w) { legal_cb(w); }),
    MenuItem("Move for me", 'm', (w) { move_cb(w); }),
    MenuItem("New game", 'n', (w) { newgame_cb(w); }),
    MenuItem("Predict", 'p', (w) { predict_cb(w); }),
    MenuItem("Switch sides", 's', (w) { switch_cb(w); }),
    MenuItem("Undo", 'u', (w) { undo_cb(w); }, menuDivider),
    MenuItem("Forced jumps rule", 'f', (w) { forced_cb(w); }, menuToggle | menuValue),
    MenuItem("Debug", 'd', (w) { debug_cb(w); }, menuToggle),
    MenuItem("Intelligence...", 'i', (w) { intel_cb(w); }, menuDivider),
    MenuItem("Copyright", 'c', (w) { copyright_cb(w); }),
    MenuItem("Quit", 'q', (w) { quit_cb(w); }),
    MenuItem(null),
];

MenuItem[8] busymenu = [
    MenuItem("Stop", '.', (w) { stop_cb(w); }),
    MenuItem("Autoplay", 'a', (w) { autoplay_cb(w); }),
    MenuItem("Continue", 0, (w) { continue_cb(w); }),
    MenuItem("Debug", 'd', (w) { debug_cb(w); }, menuToggle),
    MenuItem("Intelligence...", 'i', (w) { intel_cb(w); }),
    MenuItem("Copyright", 'c', (w) { copyright_cb(w); }),
    MenuItem("Quit", 'q', (w) { quit_cb(w); }),
    MenuItem(null),
];

////////////////////////////////////////////////////////////////

immutable string copyrightText =
    "Checkers game\n"
    ~ "Copyright (C) 1997-2010 Bill Spitzak    spitzak@@d2.com\n"
    ~ "Original Pascal code:\n"
    ~ "Copyright 1978, Oregon Minicomputer Software, Inc.\n"
    ~ "2340 SW Canyon Road, Portland, Oregon 97201\n"
    ~ "Written by Steve Poulsen 18-Jan-79\n"
    ~ "\n"
    ~ "This program is free software; you can redistribute it and/or modify "
    ~ "it under the terms of the GNU General Public License as published by "
    ~ "the Free Software Foundation; either version 2 of the License, or "
    ~ "(at your option) any later version.\n"
    ~ "\n"
    ~ "This program is distributed in the hope that it will be useful, "
    ~ "but WITHOUT ANY WARRANTY; without even the implied warranty of "
    ~ "MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the "
    ~ "GNU General Public License for more details.\n"
    ~ "\n"
    ~ "You should have received a copy of the GNU Library General Public "
    ~ "License along with this library; if not, write to the Free Software "
    ~ "Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 "
    ~ "USA.";

void main(string[] args)
{
    import std.random : unpredictableSeed;

    seed = cast(int) unpredictableSeed;
    newgame();

    fl.visual(modeDouble | modeIndex);
    auto board = new Board(BOARDSIZE, BOARDSIZE);
    board.color(backgroundColor);
    board.callback((w) { quit_cb(w); });
    board.show(args);
    fl.run();
}
