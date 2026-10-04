/*
 * Ported from src/fl_symbols.cxx (FLTK 1.5.0, ~/Repositories/fltk;
 * declared in FL/fl_draw.H alongside fl.draw's other free functions --
 * fl_symbols.cxx has no header of its own). The "@"-leading-symbol
 * glyph system: drawSymbol()/addSymbol() (2 overloads)/
 * removeSymbol(), a 40-entry named-symbol table, and each symbol's
 * own small vector-drawing function, all using fl.draw's already-real
 * transform-stack/vertex-path primitives (fl_push_matrix/fl_translate/
 * fl_scale/fl_rotate/fl_begin_polygon/.../fl_vertex/fl_circle/
 * fl_line_style, ported earlier for fl.dial/fl.clock/the "gtk+"/"oxy"/
 * "plastic" scheme families -- see PORTING.md's fl_draw.H row).
 *
 * Deviations from FLTK, all deliberate:
 *
 *  - **Plain D `function` pointers, not delegates.** CLAUDE.md's
 *    "callbacks are D delegates" convention exists specifically because
 *    FLTK's `Fl_Callback` needs a function-pointer+`void*` pair to
 *    fake per-instance closures in C++. FLTK's symbol-drawing table
 *    has no such user-data slot at all -- it's a plain function-pointer
 *    table with zero closure need, so the faithful (and simplest) D
 *    equivalent is a plain `function` pointer, not a delegate.
 *  - `addSymbol()`'s table is a plain D associative array
 *    (`SymbolEntry[string]`), populated once by a module constructor
 *    (`static this()`), instead of FLTK's function-local
 *    `std::unordered_map` with a static initializer-list.
 *  - `draw_arrow1()`'s `fl_graphics_driver->can_fill_non_convex_polygon()`
 *    branch is hardcoded to the "false" (two separate convex shapes)
 *    path -- not a simplification: FLTK's own real X11 driver
 *    (`Fl_Xlib_Graphics_Driver::can_fill_non_convex_polygon()`,
 *    `Fl_Xlib_Graphics_Driver_vertex.cxx`) always returns `false` too
 *    (its `end_polygon()` always uses X11's `Convex` fill mode, never
 *    `Complex`), and fldtk's own `endPolygon()` matches (always
 *    `polygonShapeConvex`) -- so this is FLTK's actual X11 runtime
 *    behavior, ported exactly, not a driver-capability check this port
 *    lacks the machinery for.
 *  - `draw_returnarrow()` calls `fl.return_button`'s `returnArrow()`
 *    directly (made `package(fl)`-visible for exactly this) instead of
 *    a bare `extern` forward declaration shared across two translation
 *    units -- FLTK's own C++ workaround for not wanting a shared
 *    header just for one internal function; D's module system doesn't
 *    need that workaround.
 *  - **Known, faithfully-ported FLTK quirk, not silently fixed**:
 *    the arbitrary-rotation `'0'` escape (`drawSymbol()`'s
 *    `case '0':` branch) is documented (`documentation/src/common.dox`)
 *    as "'0', followed by four more digits", but the actual
 *    implementation reads only `p[1]`, `p[2]`, `p[3]` (three digits,
 *    skipping the character immediately after '0') while still
 *    advancing `p` by 4 -- silently discarding the first of the four
 *    documented digits rather than using or validating it. Ported
 *    exactly as FLTK behaves (not as documented); see
 *    FLTK_ISSUES.md.
 */
module fl.symbols;

import fl.enumerations : Color, white, light3, dark3, lineSolid;
import fl.draw;
import fl.return_button : returnArrow;
import std.math : cos, sin, PI;

private struct SymbolEntry
{
    union
    {
        void function(Color) drawit;
        void function(int, int, int, int, Color) drawInRect;
    }
    bool scalable;
    bool callWithRect;
}

private SymbolEntry[string] symbolTable_;

/**
 * Registers (or replaces) a named symbol drawn using complex vector
 * drawing -- `drawit` is called with the transform matrix already
 * pushed and translated to the center of the drawing rectangle, and
 * (if `scalable`) pre-scaled so the unit square (-1,-1)-(1,1) maps
 * onto it. `name` excludes the leading `@`.
 */
int addSymbol(string name, void function(Color) drawit, bool scalable = true)
{
    SymbolEntry e;
    e.drawit = drawit;
    e.scalable = scalable;
    e.callWithRect = false;
    symbolTable_[name] = e;
    return 1;
}

/**
 * Registers (or replaces) a named symbol drawn into an explicit pixel
 * rectangle -- for symbols using fast lines, text, or bitmaps, where
 * pixel coordinates are more natural than the (-1,-1)-(1,1) vector
 * space. `name` excludes the leading `@`.
 */
int addSymbol(string name, void function(int, int, int, int, Color) drawInRect,
    bool scalable = true)
{
    SymbolEntry e;
    e.drawInRect = drawInRect;
    e.scalable = scalable;
    e.callWithRect = true;
    symbolTable_[name] = e;
    return 1;
}

/// Removes the named symbol. Does nothing if it isn't defined.
int removeSymbol(string name)
{
    symbolTable_.remove(name);
    return 1;
}

/**
 * Draws the named symbol in `label` (must start with `@`) within
 * (x,y,w,h) using color `col`. Returns 1 on success, 0 if `label`
 * doesn't start with `@` or names an unknown symbol.
 *
 * Ported from `fl_draw_symbol()` (`src/fl_symbols.cxx`) -- parses the
 * optional `#`/`-N`/`+N`/`$`/`%`/rotation-digit modifiers in the exact
 * order and semantics FLTK does (see documentation/src/common.dox
 * for the public-facing format description), then looks up and
 * invokes the named entry.
 */
int drawSymbol(const(char)[] label, int x, int y, int w, int h, Color col)
{
    ensureDefaultSymbols();
    if (label.length == 0 || label[0] != '@') return 0;
    size_t p = 1;

    bool equalscale = false;
    if (p < label.length && label[p] == '#')
    {
        equalscale = true;
        p++;
    }
    if (p + 1 < label.length && label[p] == '-' && label[p + 1] >= '1' && label[p + 1] <= '9')
    {
        int n = label[p + 1] - '0';
        x += n; y += n; w -= 2 * n; h -= 2 * n;
        p += 2;
    }
    else if (p + 1 < label.length && label[p] == '+' && label[p + 1] >= '1' && label[p + 1] <= '9')
    {
        int n = label[p + 1] - '0';
        x -= n; y -= n; w += 2 * n; h += 2 * n;
        p += 2;
    }
    if (w < 10) { x -= (10 - w) / 2; w = 10; }
    if (h < 10) { y -= (10 - h) / 2; h = 10; }
    w = (w - 1) | 1;
    h = (h - 1) | 1;

    bool flipX = false, flipY = false;
    if (p < label.length && label[p] == '$') { flipX = true; p++; }
    if (p < label.length && label[p] == '%') { flipY = true; p++; }

    int rotangle = 0;
    if (p < label.length)
    {
        char c = label[p];
        p++;
        switch (c)
        {
            case '0':
                // See this module's top comment: faithfully reproduces
                // FLTK's own off-by-one (skips the digit right
                // after '0', reads the next three, still advances 4).
                //
                // Bounds-checked departure from FLTK here, not a
                // faithfulness gap: FLTK's C string is NUL-
                // terminated, so a short/malformed "@0" label just
                // reads past the NUL into whatever bytes happen to
                // follow in memory (real, if silent, undefined
                // behavior) and still unconditionally advances p by 4.
                // A D slice has no such give -- advancing p past
                // label.length and then slicing label[p .. $] below is
                // a hard crash (a real
                // core.exception.ArraySliceError, reachable via
                // test/fullscreen). Only
                // advance the full 4 when there's actually a 4th
                // character to land on; otherwise clamp to the end of
                // the string, matching this function's normal
                // "p == label.length means no symbol name follows"
                // handling for every other short-label case just above.
                if (p + 3 < label.length)
                {
                    rotangle = 1000 * (label[p + 1] - '0') + 100 * (label[p + 2] - '0')
                        + 10 * (label[p + 3] - '0');
                    p += 4;
                }
                else
                {
                    p = label.length;
                }
                break;
            case '1': rotangle = 2250; break;
            case '2': rotangle = 2700; break;
            case '3': rotangle = 3150; break;
            case '4': rotangle = 1800; break;
            case '5': case '6': rotangle = 0; break;
            case '7': rotangle = 1350; break;
            case '8': rotangle = 900; break;
            case '9': rotangle = 450; break;
            default:
                rotangle = 0;
                p--;
                break;
        }
    }

    auto entry = label[p .. $] in symbolTable_;
    if (entry is null) return 0;

    if (entry.callWithRect && !entry.scalable)
    {
        entry.drawInRect(x, y, w, h, col);
    }
    else
    {
        pushMatrix();
        fl_translate(x + w / 2, y + h / 2);
        if (entry.scalable)
        {
            int ws = w, hs = h;
            if (equalscale)
            {
                if (ws < hs) hs = ws; else ws = hs;
            }
            fl_scale(0.5 * ws, 0.5 * hs);
            fl_rotate(rotangle / 10.0);
            if (flipX) fl_scale(-1.0, 1.0);
            if (flipY) fl_scale(1.0, -1.0);
        }
        if (entry.callWithRect)
            entry.drawInRect(x, y, w, h, col);
        else
            entry.drawit(col);
        popMatrix();
    }
    return 1;
}

/* ******************** THE DEFAULT SYMBOLS ******************** */

private void setOutlineColor(Color c)
{
    fl_color(darker(c));
}

private void symbolRect(double x, double y, double x2, double y2, Color col)
{
    fl_color(col);
    beginPolygon();
    vertex(x, y);
    vertex(x2, y);
    vertex(x2, y2);
    vertex(x, y2);
    endPolygon();
    setOutlineColor(col);
    beginLoop();
    vertex(x, y);
    vertex(x2, y);
    vertex(x2, y2);
    vertex(x, y2);
    endLoop();
}

private void drawFltk(Color col)
{
    fl_color(col);
    // F fill
    beginComplexPolygon();
    vertex(-2.0, -0.5); vertex(-1.0, -0.5); vertex(-1.0, -0.3);
    vertex(-1.8, -0.3); vertex(-1.8, -0.1); vertex(-1.2, -0.1);
    vertex(-1.2, 0.1); vertex(-1.8, 0.1); vertex(-1.8, 0.5);
    vertex(-2.0, 0.5);
    endComplexPolygon();
    // L fill
    beginComplexPolygon();
    vertex(-1.0, -0.5); vertex(-0.8, -0.5); vertex(-0.8, 0.3);
    vertex(0.0, 0.3); vertex(0.0, 0.5); vertex(-1.0, 0.5);
    endComplexPolygon();
    // T fill
    beginComplexPolygon();
    vertex(-0.1, -0.5); vertex(1.1, -0.5); vertex(1.1, -0.3);
    vertex(0.6, -0.3); vertex(0.6, 0.5); vertex(0.4, 0.5);
    vertex(0.4, -0.3); vertex(-0.1, -0.3);
    endComplexPolygon();
    // K fill
    beginComplexPolygon();
    vertex(1.1, -0.5); vertex(1.3, -0.5); vertex(1.3, -0.15);
    vertex(1.70, -0.5); vertex(2.0, -0.5); vertex(1.43, 0.0);
    vertex(2.0, 0.5); vertex(1.70, 0.5); vertex(1.3, 0.15);
    vertex(1.3, 0.5); vertex(1.1, 0.5);
    endComplexPolygon();
    setOutlineColor(col);
    // F outline
    beginLoop();
    vertex(-2.0, -0.5); vertex(-1.0, -0.5); vertex(-1.0, -0.3);
    vertex(-1.8, -0.3); vertex(-1.8, -0.1); vertex(-1.2, -0.1);
    vertex(-1.2, 0.1); vertex(-1.8, 0.1); vertex(-1.8, 0.5);
    vertex(-2.0, 0.5);
    endLoop();
    // L outline
    beginLoop();
    vertex(-1.0, -0.5); vertex(-0.8, -0.5); vertex(-0.8, 0.3);
    vertex(0.0, 0.3); vertex(0.0, 0.5); vertex(-1.0, 0.5);
    endLoop();
    // T outline
    beginLoop();
    vertex(-0.1, -0.5); vertex(1.1, -0.5); vertex(1.1, -0.3);
    vertex(0.6, -0.3); vertex(0.6, 0.5); vertex(0.4, 0.5);
    vertex(0.4, -0.3); vertex(-0.1, -0.3);
    endLoop();
    // K outline
    beginLoop();
    vertex(1.1, -0.5); vertex(1.3, -0.5); vertex(1.3, -0.15);
    vertex(1.70, -0.5); vertex(2.0, -0.5); vertex(1.43, 0.0);
    vertex(2.0, 0.5); vertex(1.70, 0.5); vertex(1.3, 0.15);
    vertex(1.3, 0.5); vertex(1.1, 0.5);
    endLoop();
}

private void drawSearch(Color col)
{
    fl_color(col);
    beginPolygon();
    vertex(-.4, .13); vertex(-1.0, .73); vertex(-.73, 1.0); vertex(-.13, .4);
    endPolygon();
    setOutlineColor(col);
    lineStyle(lineSolid, 3, null);
    beginLoop();
    circle(.2, -.2, .6);
    endLoop();
    lineStyle(lineSolid, 1, null);
    beginLoop();
    vertex(-.4, .13); vertex(-1.0, .73); vertex(-.73, 1.0); vertex(-.13, .4);
    endLoop();
}

/// Ported from draw_arrow1() -- the `can_fill_non_convex_polygon()`
/// check is hardcoded to the "false" branch; see this module's top
/// comment for why that's FLTK's real X11 behavior, not a gap.
private void drawArrow1(Color col)
{
    fl_color(col);
    beginPolygon();
    vertex(-0.8, -0.4); vertex(-0.8, 0.4); vertex(0.0, 0.4); vertex(0.0, -0.4);
    endPolygon();
    beginPolygon();
    vertex(0.0, 0.8); vertex(0.8, 0.0); vertex(0.0, -0.8); vertex(0.0, -0.4); vertex(0.0, 0.4);
    endPolygon();
    setOutlineColor(col);
    beginLoop();
    vertex(-0.8, -0.4); vertex(-0.8, 0.4); vertex(0.0, 0.4);
    vertex(0.0, 0.8); vertex(0.8, 0.0); vertex(0.0, -0.8); vertex(0.0, -0.4);
    endLoop();
}

private void drawArrow1Bar(Color col)
{
    drawArrow1(col);
    symbolRect(.6, -.8, .9, .8, col);
}

private void drawArrow2(Color col)
{
    fl_color(col);
    beginPolygon();
    vertex(-0.3, 0.8); vertex(0.50, 0.0); vertex(-0.3, -0.8);
    endPolygon();
    setOutlineColor(col);
    beginLoop();
    vertex(-0.3, 0.8); vertex(0.50, 0.0); vertex(-0.3, -0.8);
    endLoop();
}

private void drawArrow3(Color col)
{
    fl_color(col);
    beginPolygon();
    vertex(0.1, 0.8); vertex(0.9, 0.0); vertex(0.1, -0.8);
    endPolygon();
    beginPolygon();
    vertex(-0.7, 0.8); vertex(0.1, 0.0); vertex(-0.7, -0.8);
    endPolygon();
    setOutlineColor(col);
    beginLoop();
    vertex(0.1, 0.8); vertex(0.9, 0.0); vertex(0.1, -0.8);
    endLoop();
    beginLoop();
    vertex(-0.7, 0.8); vertex(0.1, 0.0); vertex(-0.7, -0.8);
    endLoop();
}

private void drawArrowBar(Color col)
{
    fl_color(col);
    beginPolygon();
    vertex(0.2, 0.8); vertex(0.6, 0.8); vertex(0.6, -0.8); vertex(0.2, -0.8);
    endPolygon();
    beginPolygon();
    vertex(-0.6, 0.8); vertex(0.2, 0.0); vertex(-0.6, -0.8);
    endPolygon();
    setOutlineColor(col);
    beginLoop();
    vertex(0.2, 0.8); vertex(0.6, 0.8); vertex(0.6, -0.8); vertex(0.2, -0.8);
    endLoop();
    beginLoop();
    vertex(-0.6, 0.8); vertex(0.2, 0.0); vertex(-0.6, -0.8);
    endLoop();
}

private void drawArrowBox(Color col)
{
    fl_color(col);
    beginPolygon();
    vertex(-0.6, 0.8); vertex(0.2, 0.0); vertex(-0.6, -0.8);
    endPolygon();
    beginLoop();
    vertex(0.2, 0.8); vertex(0.6, 0.8); vertex(0.6, -0.8); vertex(0.2, -0.8);
    endLoop();
    setOutlineColor(col);
    beginLoop();
    vertex(0.2, 0.8); vertex(0.6, 0.8); vertex(0.6, -0.8); vertex(0.2, -0.8);
    endLoop();
    beginLoop();
    vertex(-0.6, 0.8); vertex(0.2, 0.0); vertex(-0.6, -0.8);
    endLoop();
}

private void drawBarArrow(Color col)
{
    fl_color(col);
    beginPolygon();
    vertex(0.1, 0.8); vertex(0.9, 0.0); vertex(0.1, -0.8);
    endPolygon();
    beginPolygon();
    vertex(-0.5, 0.8); vertex(-0.1, 0.8); vertex(-0.1, -0.8); vertex(-0.5, -0.8);
    endPolygon();
    setOutlineColor(col);
    beginLoop();
    vertex(0.1, 0.8); vertex(0.9, 0.0); vertex(0.1, -0.8);
    endLoop();
    beginLoop();
    vertex(-0.5, 0.8); vertex(-0.1, 0.8); vertex(-0.1, -0.8); vertex(-0.5, -0.8);
    endLoop();
}

private void drawDoubleBar(Color col)
{
    symbolRect(-0.6, -0.8, -.1, .8, col);
    symbolRect(.1, -0.8, .6, .8, col);
}

private void drawArrow01(Color col) { fl_rotate(180); drawArrow1(col); }
private void drawArrow02(Color col) { fl_rotate(180); drawArrow2(col); }
private void drawArrow03(Color col) { fl_rotate(180); drawArrow3(col); }
private void draw0ArrowBar(Color col) { fl_rotate(180); drawArrowBar(col); }
private void draw0ArrowBox(Color col) { fl_rotate(180); drawArrowBox(col); }
private void draw0BarArrow(Color col) { fl_rotate(180); drawBarArrow(col); }

private void drawDoubleArrow(Color col)
{
    fl_color(col);
    beginPolygon();
    vertex(-0.35, -0.4); vertex(-0.35, 0.4); vertex(0.35, 0.4); vertex(0.35, -0.4);
    endPolygon();
    beginPolygon();
    vertex(0.15, 0.8); vertex(0.95, 0.0); vertex(0.15, -0.8);
    endPolygon();
    beginPolygon();
    vertex(-0.15, 0.8); vertex(-0.95, 0.0); vertex(-0.15, -0.8);
    endPolygon();
    setOutlineColor(col);
    beginLoop();
    vertex(-0.15, 0.4); vertex(0.15, 0.4); vertex(0.15, 0.8);
    vertex(0.95, 0.0); vertex(0.15, -0.8); vertex(0.15, -0.4);
    vertex(-0.15, -0.4); vertex(-0.15, -0.8); vertex(-0.95, 0.0); vertex(-0.15, 0.8);
    endLoop();
}

private void drawArrow(Color col)
{
    fl_color(col);
    beginPolygon();
    vertex(0.65, 0.1); vertex(1.0, 0.0); vertex(0.65, -0.1);
    endPolygon();
    beginLine();
    vertex(-1.0, 0.0); vertex(0.65, 0.0);
    endLine();
    setOutlineColor(col);
    beginLine();
    vertex(-1.0, 0.0); vertex(0.65, 0.0);
    endLine();
    beginLoop();
    vertex(0.65, 0.1); vertex(1.0, 0.0); vertex(0.65, -0.1);
    endLoop();
}

private void drawReturnArrow(int x, int y, int w, int h, Color color)
{
    returnArrow(x, y, w, h);
}

private void drawSquare(Color col) { symbolRect(-1, -1, 1, 1, col); }

private void drawCircle(Color col)
{
    fl_color(col);
    beginPolygon();
    circle(0, 0, 1);
    endPolygon();
    setOutlineColor(col);
    beginLoop();
    circle(0, 0, 1);
    endLoop();
}

private void drawLine(Color col)
{
    fl_color(col);
    beginLine();
    vertex(-1.0, 0.0); vertex(1.0, 0.0);
    endLine();
}

private void drawPlus(Color col)
{
    fl_color(col);
    beginPolygon();
    vertex(-0.9, -0.15); vertex(-0.9, 0.15); vertex(0.9, 0.15); vertex(0.9, -0.15);
    endPolygon();
    beginPolygon();
    vertex(-0.15, -0.9); vertex(-0.15, 0.9); vertex(0.15, 0.9); vertex(0.15, -0.9);
    endPolygon();
    setOutlineColor(col);
    beginLoop();
    vertex(-0.9, -0.15); vertex(-0.9, 0.15); vertex(-0.15, 0.15);
    vertex(-0.15, 0.9); vertex(0.15, 0.9); vertex(0.15, 0.15);
    vertex(0.9, 0.15); vertex(0.9, -0.15); vertex(0.15, -0.15);
    vertex(0.15, -0.9); vertex(-0.15, -0.9); vertex(-0.15, -0.15);
    endLoop();
}

private void drawUpArrow(Color col)
{
    fl_color(light3);
    beginLine();
    vertex(-.8, .8); vertex(-.8, -.8); vertex(.8, 0);
    endLine();
    fl_color(dark3);
    beginLine();
    vertex(-.8, .8); vertex(.8, 0);
    endLine();
}

private void drawDownArrow(Color col)
{
    fl_color(dark3);
    beginLine();
    vertex(-.8, .8); vertex(-.8, -.8); vertex(.8, 0);
    endLine();
    fl_color(light3);
    beginLine();
    vertex(-.8, .8); vertex(.8, 0);
    endLine();
}

private void drawMenu(Color col)
{
    symbolRect(-0.65, 0.85, 0.65, -0.25, col);
    symbolRect(-0.65, -0.6, 0.65, -1.0, col);
}

private void drawFileNew(Color c)
{
    fl_color(c);
    beginComplexPolygon();
    vertex(-0.7, -1.0); vertex(0.1, -1.0); vertex(0.1, -0.4);
    vertex(0.7, -0.4); vertex(0.7, 1.0); vertex(-0.7, 1.0);
    endComplexPolygon();

    fl_color(lighter(c));
    beginPolygon();
    vertex(0.1, -1.0); vertex(0.1, -0.4); vertex(0.7, -0.4);
    endPolygon();

    fl_color(darker(c));
    beginLoop();
    vertex(-0.7, -1.0); vertex(0.1, -1.0); vertex(0.1, -0.4);
    vertex(0.7, -0.4); vertex(0.7, 1.0); vertex(-0.7, 1.0);
    endLoop();

    beginLine();
    vertex(0.1, -1.0); vertex(0.7, -0.4);
    endLine();
}

private void drawFileOpen(Color c)
{
    fl_color(c);
    beginPolygon();
    vertex(-1.0, -0.7); vertex(-0.9, -0.8); vertex(-0.4, -0.8);
    vertex(-0.3, -0.7); vertex(0.6, -0.7); vertex(0.6, 0.7); vertex(-1.0, 0.7);
    endPolygon();

    fl_color(darker(c));
    beginLoop();
    vertex(-1.0, -0.7); vertex(-0.9, -0.8); vertex(-0.4, -0.8);
    vertex(-0.3, -0.7); vertex(0.6, -0.7); vertex(0.6, 0.7); vertex(-1.0, 0.7);
    endLoop();

    fl_color(lighter(c));
    beginPolygon();
    vertex(-1.0, 0.7); vertex(-0.6, -0.3); vertex(1.0, -0.3); vertex(0.6, 0.7);
    endPolygon();

    fl_color(darker(c));
    beginLoop();
    vertex(-1.0, 0.7); vertex(-0.6, -0.3); vertex(1.0, -0.3); vertex(0.6, 0.7);
    endLoop();
}

private void drawFileSave(Color c)
{
    fl_color(c);
    beginPolygon();
    vertex(-0.9, -1.0); vertex(0.9, -1.0); vertex(1.0, -0.9); vertex(1.0, 0.9);
    vertex(0.9, 1.0); vertex(-0.9, 1.0); vertex(-1.0, 0.9); vertex(-1.0, -0.9);
    endPolygon();

    fl_color(lighter(c));
    beginPolygon();
    vertex(-0.7, -1.0); vertex(0.7, -1.0); vertex(0.7, -0.4); vertex(-0.7, -0.4);
    endPolygon();

    beginPolygon();
    vertex(-0.7, 0.0); vertex(0.7, 0.0); vertex(0.7, 1.0); vertex(-0.7, 1.0);
    endPolygon();

    fl_color(c);
    beginPolygon();
    vertex(-0.5, -0.9); vertex(-0.3, -0.9); vertex(-0.3, -0.5); vertex(-0.5, -0.5);
    endPolygon();

    fl_color(darker(c));
    beginLoop();
    vertex(-0.9, -1.0); vertex(0.9, -1.0); vertex(1.0, -0.9); vertex(1.0, 0.9);
    vertex(0.9, 1.0); vertex(-0.9, 1.0); vertex(-1.0, 0.9); vertex(-1.0, -0.9);
    endLoop();
}

private void drawFileSaveAs(Color c)
{
    drawFileSave(c);

    fl_color(colorAverage(c, white, 0.25f));
    beginPolygon();
    vertex(0.6, -0.8); vertex(1.0, -0.4); vertex(0.0, 0.6); vertex(-0.4, 0.6); vertex(-0.4, 0.2);
    endPolygon();

    fl_color(darker(c));
    beginLoop();
    vertex(0.6, -0.8); vertex(1.0, -0.4); vertex(0.0, 0.6); vertex(-0.4, 0.6); vertex(-0.4, 0.2);
    endLoop();

    beginPolygon();
    vertex(-0.1, 0.6); vertex(-0.4, 0.6); vertex(-0.4, 0.3);
    endPolygon();
}

private void drawFilePrint(Color c)
{
    fl_color(c);
    beginPolygon();
    vertex(-0.8, 0.0); vertex(0.8, 0.0); vertex(1.0, 0.2); vertex(1.0, 1.0);
    vertex(-1.0, 1.0); vertex(-1.0, 0.2);
    endPolygon();

    fl_color(colorAverage(c, white, 0.25f));
    beginPolygon();
    vertex(-0.6, 0.0); vertex(-0.6, -1.0); vertex(0.6, -1.0); vertex(0.6, 0.0);
    endPolygon();

    fl_color(lighter(c));
    beginPolygon();
    vertex(-0.6, 0.6); vertex(0.6, 0.6); vertex(0.6, 1.0); vertex(-0.6, 1.0);
    endPolygon();

    fl_color(darker(c));
    beginLoop();
    vertex(-0.8, 0.0); vertex(-0.6, 0.0); vertex(-0.6, -1.0); vertex(0.6, -1.0);
    vertex(0.6, 0.0); vertex(0.8, 0.0); vertex(1.0, 0.2); vertex(1.0, 1.0);
    vertex(-1.0, 1.0); vertex(-1.0, 0.2);
    endLoop();

    beginLoop();
    vertex(-0.6, 0.6); vertex(0.6, 0.6); vertex(0.6, 1.0); vertex(-0.6, 1.0);
    endLoop();
}

private void drawRoundArrow(Color c, double da = 5.0)
{
    double a, r, dr1 = 0.005, dr2 = 0.015;
    for (int j = 0; j < 2; j++)
    {
        if (j & 1)
        {
            fl_color(c);
            setOutlineColor(c);
            beginLoop();
        }
        else
        {
            fl_color(c);
            beginComplexPolygon();
        }
        vertex(-0.1, 0.0);
        vertex(-1.0, 0.0);
        vertex(-1.0, 0.9);
        int i;
        for (i = 27, a = 140.0, r = 1.0; i > 0; i--, a -= da, r -= dr1)
        {
            double ar = a / 180.0 * PI;
            vertex(cos(ar) * r, sin(ar) * r);
        }
        for (i = 27; i >= 0; a += da, i--, r -= dr2)
        {
            double ar = a / 180.0 * PI;
            vertex(cos(ar) * r, sin(ar) * r);
        }
        if (j & 1) endLoop(); else endComplexPolygon();
    }
}

private void drawRefresh(Color c)
{
    drawRoundArrow(c);
    fl_rotate(180.0);
    drawRoundArrow(c);
    fl_rotate(-180.0);
}

private void drawReload(Color c)
{
    fl_rotate(-135.0);
    drawRoundArrow(c, 10);
    fl_rotate(135.0);
}

private void drawUndo(Color c)
{
    fl_translate(0.0, 0.2);
    fl_scale(1.0, -1.0);
    drawRoundArrow(c, 6);
    fl_scale(1.0, -1.0);
    fl_translate(0.0, -0.2);
}

private void drawRedo(Color c)
{
    fl_scale(-1.0, 1.0);
    drawUndo(c);
    fl_scale(-1.0, 1.0);
}

private void drawOpenBox(Color col)
{
    fl_color(col);
    beginComplexPolygon();
    vertex(-1.0, -1.0); vertex(-0.4, -1.0); vertex(-0.4, -0.75); vertex(-0.75, -0.75);
    vertex(-0.75, 0.75); vertex(0.75, 0.75); vertex(0.75, 0.4); vertex(1.0, 0.4);
    vertex(1.0, 1.0); vertex(-1.0, 1.0);
    endComplexPolygon();
    setOutlineColor(col);
    beginLoop();
    vertex(-1.0, -1.0); vertex(-0.4, -1.0); vertex(-0.4, -0.75); vertex(-0.75, -0.75);
    vertex(-0.75, 0.75); vertex(0.75, 0.75); vertex(0.75, 0.4); vertex(1.0, 0.4);
    vertex(1.0, 1.0); vertex(-1.0, 1.0);
    endLoop();
}

private void drawImport(Color col)
{
    pushMatrix();
    fl_scale(-1.0, 1.0);
    drawOpenBox(col);
    fl_scale(-1.0, 1.0);
    fl_translate(-0.8, -0.3);
    fl_rotate(45.0 + 90);
    drawRoundArrow(col, 3);
    popMatrix();
}

private void drawExport(Color col)
{
    drawOpenBox(col);
    pushMatrix();
    fl_translate(0.7, 0.1);
    fl_rotate(225.0);
    drawRoundArrow(col, 3);
    popMatrix();
}

private bool defaultSymbolsRegistered_ = false;

/// Lazily registers the 40 default symbols on first use, rather than a
/// module constructor (`static this()`) -- a real circular module-
/// constructor dependency exists between fl.symbols and fl.tooltip
/// (both reachable from each other via fl.draw/fl.core), which
/// druntime's `sortCtors()` correctly refuses to resolve at program
/// startup (`Cyclic dependency between module constructors...`,
/// confirmed by trying `static this()` first). Lazy init sidesteps the
/// ordering question entirely: nothing needs the table populated
/// before the first real `drawSymbol()` call, which is always
/// well after every module's `static this()` has already run.
private void ensureDefaultSymbols()
{
    if (defaultSymbolsRegistered_) return;
    defaultSymbolsRegistered_ = true;
    addSymbol("", &drawArrow1, true);
    addSymbol("->", &drawArrow1, true);
    addSymbol(">", &drawArrow2, true);
    addSymbol(">>", &drawArrow3, true);
    addSymbol(">|", &drawArrowBar, true);
    addSymbol(">[]", &drawArrowBox, true);
    addSymbol("|>", &drawBarArrow, true);
    addSymbol("<-", &drawArrow01, true);
    addSymbol("<", &drawArrow02, true);
    addSymbol("<<", &drawArrow03, true);
    addSymbol("|<", &draw0ArrowBar, true);
    addSymbol("[]<", &draw0ArrowBox, true);
    addSymbol("<|", &draw0BarArrow, true);
    addSymbol("<->", &drawDoubleArrow, true);
    addSymbol("-->", &drawArrow, true);
    addSymbol("+", &drawPlus, true);
    addSymbol("->|", &drawArrow1Bar, true);
    addSymbol("arrow", &drawArrow, true);
    addSymbol("returnarrow", &drawReturnArrow, false);
    addSymbol("square", &drawSquare, true);
    addSymbol("circle", &drawCircle, true);
    addSymbol("line", &drawLine, true);
    addSymbol("plus", &drawPlus, true);
    addSymbol("menu", &drawMenu, true);
    addSymbol("UpArrow", &drawUpArrow, true);
    addSymbol("DnArrow", &drawDownArrow, true);
    addSymbol("||", &drawDoubleBar, true);
    addSymbol("search", &drawSearch, true);
    addSymbol("FLTK", &drawFltk, true);
    addSymbol("filenew", &drawFileNew, true);
    addSymbol("fileopen", &drawFileOpen, true);
    addSymbol("filesave", &drawFileSave, true);
    addSymbol("filesaveas", &drawFileSaveAs, true);
    addSymbol("fileprint", &drawFilePrint, true);
    addSymbol("refresh", &drawRefresh, true);
    addSymbol("reload", &drawReload, true);
    addSymbol("undo", &drawUndo, true);
    addSymbol("redo", &drawRedo, true);
    addSymbol("import", &drawImport, true);
    addSymbol("export", &drawExport, true);
}

version (unittest)
{
    // Headless-safe: the drawing functions all gate on fl.draw's
    // `gc_ !is null && drawable_ != 0` (no live display in unittests),
    // so this only exercises drawSymbol()'s lookup/parsing/return
    // value, not any actual pixel output -- matching this module's
    // sibling drawing functions elsewhere in fl.draw.
    unittest
    {
        assert(drawSymbol("->", 0, 0, 20, 20, white) == 0); // no leading '@'
        assert(drawSymbol("@->", 0, 0, 20, 20, white) == 1);
        assert(drawSymbol("@nosuchsymbol", 0, 0, 20, 20, white) == 0);
        assert(drawSymbol("@#->", 0, 0, 20, 20, white) == 1); // '#' equalscale modifier
        assert(drawSymbol("@-2->", 0, 0, 20, 20, white) == 1); // '-N' shrink modifier
        assert(drawSymbol("@+2->", 0, 0, 20, 20, white) == 1); // '+N' grow modifier
        assert(drawSymbol("@$->", 0, 0, 20, 20, white) == 1); // '$' flip-x
        assert(drawSymbol("@%->", 0, 0, 20, 20, white) == 1); // '%' flip-y
        assert(drawSymbol("@1->", 0, 0, 20, 20, white) == 1); // compass rotation digit
        assert(drawSymbol("@circle", 0, 0, 20, 20, white) == 1);
        assert(drawSymbol("@returnarrow", 0, 0, 20, 20, white) == 1); // callWithRect, !scalable
    }

    unittest
    {
        // addSymbol()/removeSymbol() round-trip.
        static void myDraw(Color c) { }
        assert(addSymbol("test-symbol-xyz", &myDraw, true) == 1);
        assert(drawSymbol("@test-symbol-xyz", 0, 0, 20, 20, white) == 1);
        assert(removeSymbol("test-symbol-xyz") == 1);
        assert(drawSymbol("@test-symbol-xyz", 0, 0, 20, 20, white) == 0);
    }

    unittest
    {
        // Regression test for a real, reported crash (test/fullscreen):
        // a literal '@0,0'
        // substring inside ordinary text (e.g. "...1920x1080@0,0" from
        // a %d,%d-formatted coordinate) hits the '0' rotation-digit
        // case with too few trailing characters. Previously this
        // advanced p past label.length unconditionally, crashing the
        // label[p .. $] slice below with a real
        // core.exception.ArraySliceError.
        //
        // Not asserting a specific 0-vs-1 return here: clamping p to
        // label.length when the 3 rotation digits don't all exist means
        // the remaining slice is often "", which *is* a legitimately
        // registered symbol name (the default/unnamed arrow -- see
        // ensureDefaultSymbols()'s `addSymbol("", ...)`, and the
        // existing "@1->"-style tests above where a rotation digit
        // legitimately precedes a real symbol name). Matching that
        // default arrow for leftover text like "@0,0" is a defined,
        // harmless outcome -- not wrong, just not the point of this
        // test. The only thing under test is that none of these
        // truncated/malformed inputs crash.
        drawSymbol("@0,0", 0, 0, 20, 20, white);
        drawSymbol("@0", 0, 0, 20, 20, white);
        drawSymbol("@0,", 0, 0, 20, 20, white);
        drawSymbol("@0,0,0", 0, 0, 20, 20, white);
    }
}
