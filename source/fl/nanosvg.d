/*
 * D transliteration of nanosvg.h (not the original distribution --
 * see the license notice below, required by its own clause 2).
 *
 * Original nanosvg.h:
 *   Copyright (c) 2013-14 Mikko Mononen memon@inside.org
 *
 *   This software is provided 'as-is', without any express or implied
 *   warranty. In no event will the authors be held liable for any damages
 *   arising from the use of this software.
 *
 *   Permission is granted to anyone to use this software for any purpose,
 *   including commercial applications, and to alter it and redistribute it
 *   freely, subject to the following restrictions:
 *
 *   1. The origin of this software must not be misrepresented; you must not
 *   claim that you wrote the original software. If you use this software
 *   in a product, an acknowledgment in the product documentation would be
 *   appreciated but is not required.
 *   2. Altered source versions must be plainly marked as such, and must not
 *   be misrepresented as being the original software.
 *   3. This notice may not be removed or altered from any source
 *   distribution.
 *
 *   The SVG parser is based on Anti-Grain Geometry 2.4 SVG example
 *   Copyright (C) 2002-2004 Maxim Shemanarev (McSeem) (http://www.antigrain.com/)
 *
 *   Arc calculation code based on canvg (https://code.google.com/p/canvg/)
 *
 *   Bounding box calculation based on
 *   http://blog.hackers-cafe.net/2009/06/how-to-calculate-bezier-curves-bounding.html
 *
 * This is a D transliteration -- per the notice above (clause 2), this is
 * plainly marked as an altered/derived version, not the original nanosvg
 * distribution.
 *
 * Ported for fldtk (a D port of FLTK, ~/Repositories/fltk): FLTK's
 * `Fl_SVG_Image` (`FL/Fl_SVG_Image.H` + `src/Fl_SVG_Image.cxx`) vendors this
 * exact library as source (`~/Repositories/fltk/nanosvg/nanosvg.h` +
 * `nanosvgrast.h`, built via `src/nanosvg.cxx`), not a linked external
 * library -- no `find_package()`, unlike JPEG/PNG (see CLAUDE.md's
 * "Deferred: external-library-backed features" section). This module
 * is the parser half (nanosvg.h);
 * `fl.nanosvg_rast` is the rasterizer half (nanosvgrast.h); `fl.svg_image`
 * is the `Fl_SVG_Image` glue on top of both.
 *
 * Deliberate simplifications vs. the C original (matching CLAUDE.md's "check
 * for a cleaner D alternative" rule for allocation plumbing -- the algorithm
 * itself, the numeric/string parsing quirks, and the two faithfully-ported
 * FLTK oddities below are NOT touched):
 *  - Linked lists (`NSVGpath::next`, `NSVGshape::next`, `NSVGgradientData::next`)
 *    become D classes with `next` references instead of `malloc`'d C structs
 *    with manual `free()` -- GC-managed, same traversal order/shape, no
 *    `nsvgDelete()`-style deep-free walk needed (dropping the last reference
 *    is enough under the GC; `nsvgDelete()` itself is not ported for this
 *    reason -- see `fl.svg_image`'s own note on this).
 *  - Growable float/stop arrays (`NSVGparser::pts`, `NSVGgradientData::stops`)
 *    are plain D dynamic arrays (`~=`) instead of manual `realloc()` capacity
 *    tracking.
 *  - The attribute stack (`NSVGparser::attr[NSVG_MAX_ATTR]` + `attrHead`
 *    index) is a D dynamic array used as a stack (`~=`/`.length--`) instead
 *    of a fixed 128-entry C array -- this drops the artificial
 *    `NSVG_MAX_ATTR` depth cap (that cap exists in C only to bound a fixed
 *    buffer); a pathologically deeply-nested `<g>` tree parses correctly
 *    here where FLTK would silently stop pushing past depth 127.
 *  - Fixed `char[64]` id/ref buffers (`NSVGshape::id`, `::fillGradient`,
 *    `::strokeGradient`, `NSVGgradientData::id`, `::ref`) become D `string`
 *    -- also drops the 63-character truncation `strncpy(...,63)` imposes in
 *    C; not needed once there's no fixed buffer to overflow.
 *  - `NSVGpaint`'s C `union { color; gradient* }` becomes a plain struct
 *    with both fields present (no union) -- a union containing a GC
 *    reference is something to avoid outright (the GC's conservative
 *    scanner would still treat non-pointer bit patterns stored in the same
 *    union slot as a potential pointer, which is harmless here but not
 *    worth relying on); the extra field is a few bytes, not a real cost.
 *  - The XML parser's `void* ud` + separate callback function pointers
 *    become D delegates closing directly over the `NsvgParser` (matching
 *    CLAUDE.md's established "delegates over function-pointer+void*"
 *    convention, e.g. `fl.widget`'s `Callback`).
 *  - `nsvgParseFromFile()` and `nsvgDuplicatePath()` are not ported --
 *    neither is called anywhere in `Fl_SVG_Image.cxx` (it reads the file
 *    itself via `fl_fopen()`/`fread()` and calls `nsvgParse()` directly),
 *    so there's no caller in this port either. Easy to add later if a real
 *    caller needs them.
 *
 * Faithfully ported, not "fixed", despite looking odd on a close read:
 *  - `nsvg__atof()`/`nsvg__parseNumber()` deliberately do NOT use
 *    `std.conv.to!float`/libc's locale-sensitive `atof()` -- FLTK's own
 *    comment explains why ("we roll our own... because the std library one
 *    uses locale and messes things up"). This is the opposite case from
 *    CLAUDE.md's usual "check for a cleaner D alternative" guidance: the
 *    custom parser exists for a specific, still-valid reason, so it's
 *    ported verbatim rather than swapped for a stdlib call.
 *  - `nsvg__parseXML()` mutates its input buffer in place (writing `\0`
 *    tag/attribute terminators as it scans) -- this is why `parseXml()`
 *    below takes `char[]`, not `string`, matching `Fl_SVG_Image.cxx`'s own
 *    "nsvgParse is destructive" comment and its resulting duplicate-before-
 *    parse workaround (ported in `fl.svg_image`, not here).
 */
module fl.nanosvg;

import std.math : sqrt, sin, cos, tan, PI, fabs = abs, atan2, acos;
import std.string : indexOf;


private enum NSVG_PI = 3.14159265358979323846264338327f;
private enum NSVG_KAPPA90 = 0.5522847493f;
private enum NSVG_MAX_DASHES = 8;
private enum NSVG_EPSILON = 1e-12;

private enum AlignType { none = 0, meet = 1, slice = 2 }
private enum AlignPos { min = 0, mid = 1, max = 2 }

/// Fill/stroke paint kind. `undef` means "not yet resolved" (e.g. a
/// `url(#id)` reference that hasn't been matched to a `<gradient>` element
/// yet), matching FLTK's `NSVG_PAINT_UNDEF`.
enum NsvgPaintType : byte { undef = -1, none = 0, color = 1, linearGradient = 2, radialGradient = 3 }
enum NsvgSpreadType : byte { pad = 0, reflect = 1, repeat = 2 }
enum NsvgLineJoin : byte { miter = 0, round = 1, bevel = 2 }
enum NsvgLineCap : byte { butt = 0, round = 1, square = 2 }
enum NsvgFillRule : byte { nonzero = 0, evenodd = 1 }
enum NsvgFlags : ubyte { visible = 0x01 }
enum NsvgUnits { user, px, pt, pc, mm, cm, in_, percent, em, ex }
private enum NsvgGradientUnits : byte { userSpace = 0, objectSpace = 1 }

struct NsvgCoordinate
{
    float value = 0;
    NsvgUnits units = NsvgUnits.user;
}

struct NsvgGradientStop
{
    uint color;
    float offset = 0;
}

/// Ported from `NSVGgradient`. A resolved, ready-to-shade gradient
/// (transform + stop list), created by `createGradient()` once parsing is
/// complete -- distinct from `NsvgGradientData` below, which only exists
/// during parsing.
final class NsvgGradient
{
    float[6] xform = [1, 0, 0, 1, 0, 0];
    NsvgSpreadType spread;
    float fx = 0, fy = 0;
    NsvgGradientStop[] stops;
}

/// No C-style union (see this module's own top comment) -- `color` is
/// meaningful only when `type == color`, `gradient` only when `type` is one
/// of the two gradient kinds, matching FLTK's own discipline just
/// without the union.
struct NsvgPaint
{
    NsvgPaintType type = NsvgPaintType.undef;
    uint color;
    NsvgGradient gradient;
}

/// Ported from `NSVGpath`. `pts` holds cubic bezier points: `x0,y0,
/// [cpx1,cpy1,cpx2,cpy2,x1,y1], ...` -- `npts` FLTK's own count is just
/// `pts.length/2` here since `pts` is a real D array, not a `malloc()`'d
/// buffer with a separately-tracked length.
final class NsvgPath
{
    float[] pts;
    bool closed;
    float[4] bounds = 0;
    NsvgPath next;
}

/// Ported from `NSVGshape`.
final class NsvgShape
{
    string id;
    NsvgPaint fill;
    NsvgPaint stroke;
    float opacity = 1;
    float strokeWidth = 1;
    float strokeDashOffset = 0;
    float[NSVG_MAX_DASHES] strokeDashArray = 0;
    int strokeDashCount;
    NsvgLineJoin strokeLineJoin;
    NsvgLineCap strokeLineCap;
    float miterLimit = 4;
    NsvgFillRule fillRule;
    ubyte flags;
    float[4] bounds = 0;
    string fillGradient;
    string strokeGradient;
    float[6] xform = [1, 0, 0, 1, 0, 0];
    NsvgPath paths;
    NsvgShape next;
}

/// Ported from `NSVGimage`, the parser's public result.
final class NsvgImage
{
    float width = 0;
    float height = 0;
    NsvgShape shapes;
}

// ---------------------------------------------------------------------
// Transform math -- ported from nanosvg.h's `nsvg__xform*()` family.
// ---------------------------------------------------------------------

private void xformIdentity(ref float[6] t)
{
    t[0] = 1; t[1] = 0;
    t[2] = 0; t[3] = 1;
    t[4] = 0; t[5] = 0;
}

private void xformSetTranslation(ref float[6] t, float tx, float ty)
{
    t[0] = 1; t[1] = 0;
    t[2] = 0; t[3] = 1;
    t[4] = tx; t[5] = ty;
}

private void xformSetScale(ref float[6] t, float sx, float sy)
{
    t[0] = sx; t[1] = 0;
    t[2] = 0; t[3] = sy;
    t[4] = 0; t[5] = 0;
}

private void xformSetSkewX(ref float[6] t, float a)
{
    t[0] = 1; t[1] = 0;
    t[2] = tan(a); t[3] = 1;
    t[4] = 0; t[5] = 0;
}

private void xformSetSkewY(ref float[6] t, float a)
{
    t[0] = 1; t[1] = tan(a);
    t[2] = 0; t[3] = 1;
    t[4] = 0; t[5] = 0;
}

private void xformSetRotation(ref float[6] t, float a)
{
    float cs = cos(a), sn = sin(a);
    t[0] = cs; t[1] = sn;
    t[2] = -sn; t[3] = cs;
    t[4] = 0; t[5] = 0;
}

private void xformMultiply(ref float[6] t, ref float[6] s)
{
    float t0 = t[0] * s[0] + t[1] * s[2];
    float t2 = t[2] * s[0] + t[3] * s[2];
    float t4 = t[4] * s[0] + t[5] * s[2] + s[4];
    t[1] = t[0] * s[1] + t[1] * s[3];
    t[3] = t[2] * s[1] + t[3] * s[3];
    t[5] = t[4] * s[1] + t[5] * s[3] + s[5];
    t[0] = t0;
    t[2] = t2;
    t[4] = t4;
}

private void xformInverse(ref float[6] inv, ref float[6] t)
{
    double det = cast(double) t[0] * t[3] - cast(double) t[2] * t[1];
    if (det > -1e-6 && det < 1e-6)
    {
        xformIdentity(t);
        return;
    }
    double invdet = 1.0 / det;
    inv[0] = t[3] * invdet;
    inv[2] = -t[2] * invdet;
    inv[4] = (cast(double) t[2] * t[5] - cast(double) t[3] * t[4]) * invdet;
    inv[1] = -t[1] * invdet;
    inv[3] = t[0] * invdet;
    inv[5] = (cast(double) t[1] * t[4] - cast(double) t[0] * t[5]) * invdet;
}

private void xformPremultiply(ref float[6] t, ref float[6] s)
{
    float[6] s2 = s;
    xformMultiply(s2, t);
    t = s2;
}

private void xformPoint(out float dx, out float dy, float x, float y, ref float[6] t)
{
    dx = x * t[0] + y * t[2] + t[4];
    dy = x * t[1] + y * t[3] + t[5];
}

private void xformVec(out float dx, out float dy, float x, float y, ref float[6] t)
{
    dx = x * t[0] + y * t[2];
    dy = x * t[1] + y * t[3];
}

private float minf(float a, float b) { return a < b ? a : b; }
private float maxf(float a, float b) { return a > b ? a : b; }

private bool ptInBounds(float[2] pt, float[4] bounds)
{
    return pt[0] >= bounds[0] && pt[0] <= bounds[2] && pt[1] >= bounds[1] && pt[1] <= bounds[3];
}

private double evalBezier(double t, double p0, double p1, double p2, double p3)
{
    double it = 1.0 - t;
    return it * it * it * p0 + 3.0 * it * it * t * p1 + 3.0 * it * t * t * p2 + t * t * t * p3;
}

private void curveBounds(out float[4] bounds, float[8] curve)
{
    float[2] v0 = curve[0 .. 2];
    float[2] v1 = curve[2 .. 4];
    float[2] v2 = curve[4 .. 6];
    float[2] v3 = curve[6 .. 8];

    bounds[0] = minf(v0[0], v3[0]);
    bounds[1] = minf(v0[1], v3[1]);
    bounds[2] = maxf(v0[0], v3[0]);
    bounds[3] = maxf(v0[1], v3[1]);

    if (ptInBounds(v1, bounds) && ptInBounds(v2, bounds))
        return;

    double[2] roots;
    for (int i = 0; i < 2; i++)
    {
        double a = -3.0 * v0[i] + 9.0 * v1[i] - 9.0 * v2[i] + 3.0 * v3[i];
        double b = 6.0 * v0[i] - 12.0 * v1[i] + 6.0 * v2[i];
        double c = 3.0 * v1[i] - 3.0 * v0[i];
        int count = 0;
        if (fabs(a) < NSVG_EPSILON)
        {
            if (fabs(b) > NSVG_EPSILON)
            {
                double t = -c / b;
                if (t > NSVG_EPSILON && t < 1.0 - NSVG_EPSILON)
                    roots[count++] = t;
            }
        }
        else
        {
            double b2ac = b * b - 4.0 * c * a;
            if (b2ac > NSVG_EPSILON)
            {
                double t = (-b + sqrt(b2ac)) / (2.0 * a);
                if (t > NSVG_EPSILON && t < 1.0 - NSVG_EPSILON)
                    roots[count++] = t;
                t = (-b - sqrt(b2ac)) / (2.0 * a);
                if (t > NSVG_EPSILON && t < 1.0 - NSVG_EPSILON)
                    roots[count++] = t;
            }
        }
        for (int j = 0; j < count; j++)
        {
            double v = evalBezier(roots[j], v0[i], v1[i], v2[i], v3[i]);
            bounds[0 + i] = minf(bounds[0 + i], v);
            bounds[2 + i] = maxf(bounds[2 + i], v);
        }
    }
}

// ---------------------------------------------------------------------
// Parser state -- ported from `NSVGattrib`/`NSVGparser`.
// ---------------------------------------------------------------------

private struct NsvgAttrib
{
    string id;
    float[6] xform = [1, 0, 0, 1, 0, 0];
    uint fillColor;
    uint strokeColor;
    float opacity = 1;
    float fillOpacity = 1;
    float strokeOpacity = 1;
    string fillGradient;
    string strokeGradient;
    float strokeWidth = 1;
    float strokeDashOffset = 0;
    float[NSVG_MAX_DASHES] strokeDashArray = 0;
    int strokeDashCount;
    NsvgLineJoin strokeLineJoin = NsvgLineJoin.miter;
    NsvgLineCap strokeLineCap = NsvgLineCap.butt;
    float miterLimit = 4;
    NsvgFillRule fillRule;
    float fontSize = 0;
    uint stopColor;
    float stopOpacity = 1;
    float stopOffset = 0;
    ubyte hasFill = 1; // 0=none 1=color 2=url(#id)
    ubyte hasStroke = 0;
    bool visible = true;
}

private struct NsvgLinearData { NsvgCoordinate x1, y1, x2, y2; }
private struct NsvgRadialData { NsvgCoordinate cx, cy, r, fx, fy; }

/// Only exists during parsing -- ported from `NSVGgradientData`, resolved
/// into a real `NsvgGradient` by `createGradient()` once the whole document
/// has been scanned (gradients can be defined after they're referenced).
private final class NsvgGradientData
{
    string id;
    string ref_;
    NsvgPaintType type;
    NsvgLinearData linear;
    NsvgRadialData radial;
    NsvgSpreadType spread;
    NsvgGradientUnits units;
    float[6] xform = [1, 0, 0, 1, 0, 0];
    NsvgGradientStop[] stops;
    NsvgGradientData next;
}

private final class NsvgParser
{
    NsvgAttrib[] attrStack;
    float[] pts;
    NsvgPath plist;
    NsvgImage image;
    NsvgGradientData gradients;
    NsvgShape shapesTail;
    float viewMinx = 0, viewMiny = 0, viewWidth = 0, viewHeight = 0;
    AlignPos alignX, alignY;
    AlignType alignType;
    float dpi = 96;
    bool pathFlag;
    bool defsFlag;

    ref NsvgAttrib attr() { return attrStack[$ - 1]; }
}

private NsvgParser createParser()
{
    auto p = new NsvgParser();
    p.image = new NsvgImage();

    NsvgAttrib a;
    xformIdentity(a.xform);
    a.fillColor = 0; // black
    a.strokeColor = 0;
    a.opacity = 1;
    a.fillOpacity = 1;
    a.strokeOpacity = 1;
    a.stopOpacity = 1;
    a.strokeWidth = 1;
    a.strokeLineJoin = NsvgLineJoin.miter;
    a.strokeLineCap = NsvgLineCap.butt;
    a.miterLimit = 4;
    a.fillRule = NsvgFillRule.nonzero;
    a.hasFill = 1;
    a.visible = true;
    p.attrStack ~= a;

    return p;
}

private void resetPath(NsvgParser p) { p.pts.length = 0; }

private void addPoint(NsvgParser p, float x, float y) { p.pts ~= [x, y]; }

private void moveTo(NsvgParser p, float x, float y)
{
    if (p.pts.length > 0)
    {
        p.pts[$ - 2] = x;
        p.pts[$ - 1] = y;
    }
    else
    {
        addPoint(p, x, y);
    }
}

private void lineTo(NsvgParser p, float x, float y)
{
    if (p.pts.length > 0)
    {
        float px = p.pts[$ - 2], py = p.pts[$ - 1];
        float dx = x - px, dy = y - py;
        addPoint(p, px + dx / 3.0f, py + dy / 3.0f);
        addPoint(p, x - dx / 3.0f, y - dy / 3.0f);
        addPoint(p, x, y);
    }
}

private void cubicBezTo(NsvgParser p, float cpx1, float cpy1, float cpx2, float cpy2, float x, float y)
{
    if (p.pts.length > 0)
    {
        addPoint(p, cpx1, cpy1);
        addPoint(p, cpx2, cpy2);
        addPoint(p, x, y);
    }
}

private float actualOrigX(NsvgParser p) { return p.viewMinx; }
private float actualOrigY(NsvgParser p) { return p.viewMiny; }
private float actualWidth(NsvgParser p) { return p.viewWidth; }
private float actualHeight(NsvgParser p) { return p.viewHeight; }

private float actualLength(NsvgParser p)
{
    float w = actualWidth(p), h = actualHeight(p);
    return sqrt(w * w + h * h) / sqrt(2.0f);
}

private float convertToPixels(NsvgParser p, NsvgCoordinate c, float orig, float length)
{
    final switch (c.units)
    {
    case NsvgUnits.user: return c.value;
    case NsvgUnits.px: return c.value;
    case NsvgUnits.pt: return c.value / 72.0f * p.dpi;
    case NsvgUnits.pc: return c.value / 6.0f * p.dpi;
    case NsvgUnits.mm: return c.value / 25.4f * p.dpi;
    case NsvgUnits.cm: return c.value / 2.54f * p.dpi;
    case NsvgUnits.in_: return c.value * p.dpi;
    case NsvgUnits.em: return c.value * p.attr.fontSize;
    case NsvgUnits.ex: return c.value * p.attr.fontSize * 0.52f;
    case NsvgUnits.percent: return orig + c.value / 100.0f * length;
    }
}

private NsvgGradientData findGradientData(NsvgParser p, string id)
{
    if (id.length == 0) return null;
    for (auto grad = p.gradients; grad !is null; grad = grad.next)
        if (grad.id == id) return grad;
    return null;
}

private NsvgGradient createGradient(NsvgParser p, string id, float[4] localBounds,
        ref float[6] xform, out NsvgPaintType paintType)
{
    auto data = findGradientData(p, id);
    if (data is null) return null;

    NsvgGradientStop[] stops;
    auto ref_ = data;
    int refIter = 0;
    while (ref_ !is null)
    {
        if (stops.length == 0 && ref_.stops.length != 0)
        {
            stops = ref_.stops;
            break;
        }
        auto nextRef = findGradientData(p, ref_.ref_);
        if (nextRef is ref_) break;
        ref_ = nextRef;
        refIter++;
        if (refIter > 32) break;
    }
    if (stops.length == 0) return null;

    auto grad = new NsvgGradient();

    float ox, oy, sw, sh;
    if (data.units == NsvgGradientUnits.objectSpace)
    {
        ox = localBounds[0];
        oy = localBounds[1];
        sw = localBounds[2] - localBounds[0];
        sh = localBounds[3] - localBounds[1];
    }
    else
    {
        ox = actualOrigX(p);
        oy = actualOrigY(p);
        sw = actualWidth(p);
        sh = actualHeight(p);
    }
    float sl = sqrt(sw * sw + sh * sh) / sqrt(2.0f);

    if (data.type == NsvgPaintType.linearGradient)
    {
        float x1 = convertToPixels(p, data.linear.x1, ox, sw);
        float y1 = convertToPixels(p, data.linear.y1, oy, sh);
        float x2 = convertToPixels(p, data.linear.x2, ox, sw);
        float y2 = convertToPixels(p, data.linear.y2, oy, sh);
        float dx = x2 - x1, dy = y2 - y1;
        grad.xform[0] = dy; grad.xform[1] = -dx;
        grad.xform[2] = dx; grad.xform[3] = dy;
        grad.xform[4] = x1; grad.xform[5] = y1;
    }
    else
    {
        float cx = convertToPixels(p, data.radial.cx, ox, sw);
        float cy = convertToPixels(p, data.radial.cy, oy, sh);
        float fx = convertToPixels(p, data.radial.fx, ox, sw);
        float fy = convertToPixels(p, data.radial.fy, oy, sh);
        float r = convertToPixels(p, data.radial.r, 0, sl);
        grad.xform[0] = r; grad.xform[1] = 0;
        grad.xform[2] = 0; grad.xform[3] = r;
        grad.xform[4] = cx; grad.xform[5] = cy;
        grad.fx = r != 0 ? fx / r : 0;
        grad.fy = r != 0 ? fy / r : 0;
    }

    xformMultiply(grad.xform, data.xform);
    xformMultiply(grad.xform, xform);

    grad.spread = data.spread;
    grad.stops = stops.dup;

    paintType = data.type;
    return grad;
}

private float getAverageScale(ref float[6] t)
{
    float sx = sqrt(t[0] * t[0] + t[2] * t[2]);
    float sy = sqrt(t[1] * t[1] + t[3] * t[3]);
    return (sx + sy) * 0.5f;
}

private void getLocalBounds(out float[4] bounds, NsvgShape shape, ref float[6] xform)
{
    bool first = true;
    for (auto path = shape.paths; path !is null; path = path.next)
    {
        float[8] curve;
        xformPoint(curve[0], curve[1], path.pts[0], path.pts[1], xform);
        for (int i = 0; i < cast(int) (path.pts.length / 2) - 1; i += 3)
        {
            xformPoint(curve[2], curve[3], path.pts[(i + 1) * 2], path.pts[(i + 1) * 2 + 1], xform);
            xformPoint(curve[4], curve[5], path.pts[(i + 2) * 2], path.pts[(i + 2) * 2 + 1], xform);
            xformPoint(curve[6], curve[7], path.pts[(i + 3) * 2], path.pts[(i + 3) * 2 + 1], xform);
            float[4] curveBoundsOut;
            curveBounds(curveBoundsOut, curve);
            if (first)
            {
                bounds = curveBoundsOut;
                first = false;
            }
            else
            {
                bounds[0] = minf(bounds[0], curveBoundsOut[0]);
                bounds[1] = minf(bounds[1], curveBoundsOut[1]);
                bounds[2] = maxf(bounds[2], curveBoundsOut[2]);
                bounds[3] = maxf(bounds[3], curveBoundsOut[3]);
            }
            curve[0] = curve[6];
            curve[1] = curve[7];
        }
    }
}

private void addShape(NsvgParser p)
{
    if (p.plist is null) return;

    auto attr = p.attr;
    auto shape = new NsvgShape();

    shape.id = attr.id;
    shape.fillGradient = attr.fillGradient;
    shape.strokeGradient = attr.strokeGradient;
    shape.xform = attr.xform;
    float scale = getAverageScale(attr.xform);
    shape.strokeWidth = attr.strokeWidth * scale;
    shape.strokeDashOffset = attr.strokeDashOffset * scale;
    shape.strokeDashCount = attr.strokeDashCount;
    for (int i = 0; i < attr.strokeDashCount; i++)
        shape.strokeDashArray[i] = attr.strokeDashArray[i] * scale;
    shape.strokeLineJoin = attr.strokeLineJoin;
    shape.strokeLineCap = attr.strokeLineCap;
    shape.miterLimit = attr.miterLimit;
    shape.fillRule = attr.fillRule;
    shape.opacity = attr.opacity;

    shape.paths = p.plist;
    p.plist = null;

    shape.bounds = shape.paths.bounds;
    for (auto path = shape.paths.next; path !is null; path = path.next)
    {
        shape.bounds[0] = minf(shape.bounds[0], path.bounds[0]);
        shape.bounds[1] = minf(shape.bounds[1], path.bounds[1]);
        shape.bounds[2] = maxf(shape.bounds[2], path.bounds[2]);
        shape.bounds[3] = maxf(shape.bounds[3], path.bounds[3]);
    }

    if (attr.hasFill == 0)
        shape.fill.type = NsvgPaintType.none;
    else if (attr.hasFill == 1)
    {
        shape.fill.type = NsvgPaintType.color;
        shape.fill.color = attr.fillColor | (cast(uint)(attr.fillOpacity * 255) << 24);
    }
    else if (attr.hasFill == 2)
        shape.fill.type = NsvgPaintType.undef;

    if (attr.hasStroke == 0)
        shape.stroke.type = NsvgPaintType.none;
    else if (attr.hasStroke == 1)
    {
        shape.stroke.type = NsvgPaintType.color;
        shape.stroke.color = attr.strokeColor | (cast(uint)(attr.strokeOpacity * 255) << 24);
    }
    else if (attr.hasStroke == 2)
        shape.stroke.type = NsvgPaintType.undef;

    shape.flags = attr.visible ? NsvgFlags.visible : 0;

    if (p.image.shapes is null)
        p.image.shapes = shape;
    else
        p.shapesTail.next = shape;
    p.shapesTail = shape;
}

private void addPath(NsvgParser p, bool closed)
{
    auto attr = p.attr;

    if (p.pts.length < 8) return; // < 4 points (x,y pairs)

    if (closed) lineTo(p, p.pts[0], p.pts[1]);

    // Expect 1 + N*3 points (N = number of cubic bezier segments).
    size_t npts = p.pts.length / 2;
    if ((npts % 3) != 1) return;

    auto path = new NsvgPath();
    path.pts.length = p.pts.length;
    path.closed = closed;

    for (size_t i = 0; i < npts; i++)
    {
        float dx, dy;
        xformPoint(dx, dy, p.pts[i * 2], p.pts[i * 2 + 1], attr.xform);
        path.pts[i * 2] = dx;
        path.pts[i * 2 + 1] = dy;
    }

    for (int i = 0; i < cast(int) npts - 1; i += 3)
    {
        float[8] curve = path.pts[i * 2 .. i * 2 + 8];
        float[4] bounds;
        curveBounds(bounds, curve);
        if (i == 0)
            path.bounds = bounds;
        else
        {
            path.bounds[0] = minf(path.bounds[0], bounds[0]);
            path.bounds[1] = minf(path.bounds[1], bounds[1]);
            path.bounds[2] = maxf(path.bounds[2], bounds[2]);
            path.bounds[3] = maxf(path.bounds[3], bounds[3]);
        }
    }

    path.next = p.plist;
    p.plist = path;
}

// ---------------------------------------------------------------------
// Number/string parsing -- ported from nanosvg.h's hand-rolled scanners
// (deliberately not swapped for std.conv, see this module's own top
// comment: locale-independence is the whole point of these).
// ---------------------------------------------------------------------

private bool isSpace(char c) { return c == ' ' || c == '\t' || c == '\n' || c == '\v' || c == '\f' || c == '\r'; }
private bool isDigit(char c) { return c >= '0' && c <= '9'; }

private double nsvgAtof(string s)
{
    size_t cur = 0;
    double sign = 1.0;
    double res = 0.0;
    bool hasIntPart = false, hasFracPart = false;

    if (cur < s.length && s[cur] == '+') cur++;
    else if (cur < s.length && s[cur] == '-') { sign = -1; cur++; }

    if (cur < s.length && isDigit(s[cur]))
    {
        double intPart = 0;
        while (cur < s.length && isDigit(s[cur])) { intPart = intPart * 10 + (s[cur] - '0'); cur++; hasIntPart = true; }
        res = intPart;
    }

    if (cur < s.length && s[cur] == '.')
    {
        cur++;
        if (cur < s.length && isDigit(s[cur]))
        {
            double fracPart = 0;
            size_t fracDigits = 0;
            while (cur < s.length && isDigit(s[cur])) { fracPart = fracPart * 10 + (s[cur] - '0'); cur++; fracDigits++; hasFracPart = true; }
            double denom = 1.0;
            foreach (_; 0 .. fracDigits) denom *= 10.0;
            res += fracPart / denom;
        }
    }

    if (!hasIntPart && !hasFracPart) return 0.0;

    if (cur < s.length && (s[cur] == 'e' || s[cur] == 'E'))
    {
        cur++;
        bool expNeg = false;
        if (cur < s.length && (s[cur] == '-' || s[cur] == '+')) { expNeg = s[cur] == '-'; cur++; }
        if (cur < s.length && isDigit(s[cur]))
        {
            int expPart = 0;
            while (cur < s.length && isDigit(s[cur])) { expPart = expPart * 10 + (s[cur] - '0'); cur++; }
            double mag = 1.0;
            foreach (_; 0 .. expPart) mag *= 10.0;
            res *= expNeg ? 1.0 / mag : mag;
        }
    }

    return res * sign;
}

/// Extracts a maximal-munch numeric substring starting at `s[pos]`, matching
/// FLTK's `nsvg__parseNumber(const char* s, char* it, int size)` -- the
/// buffer-size cap doesn't apply here (D strings aren't fixed buffers), so
/// this always captures the whole token.
private size_t parseNumberLen(string s, size_t pos)
{
    size_t start = pos;
    if (pos < s.length && (s[pos] == '-' || s[pos] == '+')) pos++;
    while (pos < s.length && isDigit(s[pos])) pos++;
    if (pos < s.length && s[pos] == '.')
    {
        pos++;
        while (pos < s.length && isDigit(s[pos])) pos++;
    }
    if (pos < s.length && (s[pos] == 'e' || s[pos] == 'E')
            && !(pos + 1 < s.length && (s[pos + 1] == 'm' || s[pos + 1] == 'x')))
    {
        pos++;
        if (pos < s.length && (s[pos] == '-' || s[pos] == '+')) pos++;
        while (pos < s.length && isDigit(s[pos])) pos++;
    }
    return pos - start;
}

private size_t skipSpacesCommas(string s, size_t pos)
{
    while (pos < s.length && (isSpace(s[pos]) || s[pos] == ',')) pos++;
    return pos;
}

/// Ported from `nsvg__getNextPathItemWhenArcFlag()` -- an elliptical arc's
/// `large-arc-flag`/`sweep-flag` args are single 0/1 digits with no
/// separator required (`a30,50,0,001,1` is legal), so they need their own
/// single-character scan instead of the general numeric one.
private size_t getNextPathItemArcFlag(string s, ref size_t pos, out string item)
{
    pos = skipSpacesCommas(s, pos);
    if (pos >= s.length) { item = ""; return pos; }
    if (s[pos] == '0' || s[pos] == '1')
    {
        item = s[pos .. pos + 1];
        pos++;
    }
    else item = "";
    return pos;
}

private void getNextPathItem(string s, ref size_t pos, out string item)
{
    pos = skipSpacesCommas(s, pos);
    if (pos >= s.length) { item = ""; return; }
    if (s[pos] == '-' || s[pos] == '+' || s[pos] == '.' || isDigit(s[pos]))
    {
        size_t len = parseNumberLen(s, pos);
        item = s[pos .. pos + len];
        pos += len;
    }
    else
    {
        item = s[pos .. pos + 1];
        pos++;
    }
}

// ---------------------------------------------------------------------
// Color parsing.
// ---------------------------------------------------------------------

private uint rgb(uint r, uint g, uint b) { return r | (g << 8) | (b << 16); }

private int hexVal(char c)
{
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

private uint parseColorHex(string str)
{
    // str starts with '#'.
    auto hex = str[1 .. $];
    if (hex.length >= 6)
    {
        int r0 = hexVal(hex[0]), r1 = hexVal(hex[1]);
        int g0 = hexVal(hex[2]), g1 = hexVal(hex[3]);
        int b0 = hexVal(hex[4]), b1 = hexVal(hex[5]);
        if (r0 >= 0 && r1 >= 0 && g0 >= 0 && g1 >= 0 && b0 >= 0 && b1 >= 0)
            return rgb(r0 * 16 + r1, g0 * 16 + g1, b0 * 16 + b1);
    }
    if (hex.length >= 3)
    {
        int r = hexVal(hex[0]), g = hexVal(hex[1]), b = hexVal(hex[2]);
        if (r >= 0 && g >= 0 && b >= 0)
            return rgb(r * 17, g * 17, b * 17);
    }
    return rgb(128, 128, 128);
}

/// Matches `sscanf(str, "rgb(%u, %u, %u)", ...)`'s literal-plus-whitespace
/// semantics: whitespace in the format string means "skip zero or more
/// whitespace chars here", non-whitespace literal chars must match exactly.
private bool tryParseColorRGBInts(string str, out uint[3] rgbi)
{
    size_t pos = 0;
    bool lit(string l)
    {
        foreach (c; l)
        {
            if (isSpace(c))
                while (pos < str.length && isSpace(str[pos])) pos++;
            else
            {
                if (pos >= str.length || str[pos] != c) return false;
                pos++;
            }
        }
        return true;
    }
    bool parseUint(out uint v)
    {
        while (pos < str.length && isSpace(str[pos])) pos++;
        size_t start = pos;
        while (pos < str.length && isDigit(str[pos])) pos++;
        if (pos == start) return false;
        v = 0;
        foreach (c; str[start .. pos]) v = v * 10 + (c - '0');
        return true;
    }
    return lit("rgb(") && parseUint(rgbi[0]) && lit(",") && parseUint(rgbi[1])
        && lit(",") && parseUint(rgbi[2]) && lit(")");
}

private uint parseColorRGB(string str)
{
    // Try decimal integers first (the common case), matching FLTK's
    // own `sscanf(str, "rgb(%u, %u, %u)", ...)` fast path.
    uint[3] rgbi;
    if (tryParseColorRGBInts(str, rgbi))
    {
        foreach (ref v; rgbi) if (v > 255) v = 255;
        return rgb(rgbi[0], rgbi[1], rgbi[2]);
    }

    // Integers failed -- try percent values (float, locale-independent).
    auto s = str[4 .. $];
    size_t pos = 0;
    float[3] rgbf;
    char[3] delimiter = [',', ',', ')'];
    int i;
    for (i = 0; i < 3; i++)
    {
        while (pos < s.length && isSpace(s[pos])) pos++;
        if (pos < s.length && s[pos] == '+') pos++;
        if (pos >= s.length) break;
        size_t numLen = parseNumberLen(s, pos);
        if (numLen == 0) break;
        rgbf[i] = nsvgAtof(s[pos .. pos + numLen]);
        pos += numLen;
        if (pos < s.length && s[pos] == '%') pos++; else break;
        while (pos < s.length && isSpace(s[pos])) pos++;
        if (pos < s.length && s[pos] == delimiter[i]) pos++;
        else break;
    }
    if (i == 3)
    {
        import std.math : lround;
        rgbi[0] = cast(uint) lround(rgbf[0] * 2.55f);
        rgbi[1] = cast(uint) lround(rgbf[1] * 2.55f);
        rgbi[2] = cast(uint) lround(rgbf[2] * 2.55f);
    }
    else
        rgbi[0] = rgbi[1] = rgbi[2] = 128;
    foreach (ref v; rgbi) if (v > 255) v = 255;
    return rgb(rgbi[0], rgbi[1], rgbi[2]);
}

// Named CSS colors -- ported from nsvg__colors[] with NANOSVG_ALL_COLOR_KEYWORDS
// defined (matching FLTK's own nanosvg.cxx build, which defines it).
private immutable(uint[string]) buildNamedColors()
{
    uint[string] m;
    m["red"] = rgb(255, 0, 0);
    m["green"] = rgb(0, 128, 0);
    m["blue"] = rgb(0, 0, 255);
    m["yellow"] = rgb(255, 255, 0);
    m["cyan"] = rgb(0, 255, 255);
    m["magenta"] = rgb(255, 0, 255);
    m["black"] = rgb(0, 0, 0);
    m["grey"] = rgb(128, 128, 128);
    m["gray"] = rgb(128, 128, 128);
    m["white"] = rgb(255, 255, 255);
    m["aliceblue"] = rgb(240, 248, 255);
    m["antiquewhite"] = rgb(250, 235, 215);
    m["aqua"] = rgb(0, 255, 255);
    m["aquamarine"] = rgb(127, 255, 212);
    m["azure"] = rgb(240, 255, 255);
    m["beige"] = rgb(245, 245, 220);
    m["bisque"] = rgb(255, 228, 196);
    m["blanchedalmond"] = rgb(255, 235, 205);
    m["blueviolet"] = rgb(138, 43, 226);
    m["brown"] = rgb(165, 42, 42);
    m["burlywood"] = rgb(222, 184, 135);
    m["cadetblue"] = rgb(95, 158, 160);
    m["chartreuse"] = rgb(127, 255, 0);
    m["chocolate"] = rgb(210, 105, 30);
    m["coral"] = rgb(255, 127, 80);
    m["cornflowerblue"] = rgb(100, 149, 237);
    m["cornsilk"] = rgb(255, 248, 220);
    m["crimson"] = rgb(220, 20, 60);
    m["darkblue"] = rgb(0, 0, 139);
    m["darkcyan"] = rgb(0, 139, 139);
    m["darkgoldenrod"] = rgb(184, 134, 11);
    m["darkgray"] = rgb(169, 169, 169);
    m["darkgreen"] = rgb(0, 100, 0);
    m["darkgrey"] = rgb(169, 169, 169);
    m["darkkhaki"] = rgb(189, 183, 107);
    m["darkmagenta"] = rgb(139, 0, 139);
    m["darkolivegreen"] = rgb(85, 107, 47);
    m["darkorange"] = rgb(255, 140, 0);
    m["darkorchid"] = rgb(153, 50, 204);
    m["darkred"] = rgb(139, 0, 0);
    m["darksalmon"] = rgb(233, 150, 122);
    m["darkseagreen"] = rgb(143, 188, 143);
    m["darkslateblue"] = rgb(72, 61, 139);
    m["darkslategray"] = rgb(47, 79, 79);
    m["darkslategrey"] = rgb(47, 79, 79);
    m["darkturquoise"] = rgb(0, 206, 209);
    m["darkviolet"] = rgb(148, 0, 211);
    m["deeppink"] = rgb(255, 20, 147);
    m["deepskyblue"] = rgb(0, 191, 255);
    m["dimgray"] = rgb(105, 105, 105);
    m["dimgrey"] = rgb(105, 105, 105);
    m["dodgerblue"] = rgb(30, 144, 255);
    m["firebrick"] = rgb(178, 34, 34);
    m["floralwhite"] = rgb(255, 250, 240);
    m["forestgreen"] = rgb(34, 139, 34);
    m["fuchsia"] = rgb(255, 0, 255);
    m["gainsboro"] = rgb(220, 220, 220);
    m["ghostwhite"] = rgb(248, 248, 255);
    m["gold"] = rgb(255, 215, 0);
    m["goldenrod"] = rgb(218, 165, 32);
    m["greenyellow"] = rgb(173, 255, 47);
    m["honeydew"] = rgb(240, 255, 240);
    m["hotpink"] = rgb(255, 105, 180);
    m["indianred"] = rgb(205, 92, 92);
    m["indigo"] = rgb(75, 0, 130);
    m["ivory"] = rgb(255, 255, 240);
    m["khaki"] = rgb(240, 230, 140);
    m["lavender"] = rgb(230, 230, 250);
    m["lavenderblush"] = rgb(255, 240, 245);
    m["lawngreen"] = rgb(124, 252, 0);
    m["lemonchiffon"] = rgb(255, 250, 205);
    m["lightblue"] = rgb(173, 216, 230);
    m["lightcoral"] = rgb(240, 128, 128);
    m["lightcyan"] = rgb(224, 255, 255);
    m["lightgoldenrodyellow"] = rgb(250, 250, 210);
    m["lightgray"] = rgb(211, 211, 211);
    m["lightgreen"] = rgb(144, 238, 144);
    m["lightgrey"] = rgb(211, 211, 211);
    m["lightpink"] = rgb(255, 182, 193);
    m["lightsalmon"] = rgb(255, 160, 122);
    m["lightseagreen"] = rgb(32, 178, 170);
    m["lightskyblue"] = rgb(135, 206, 250);
    m["lightslategray"] = rgb(119, 136, 153);
    m["lightslategrey"] = rgb(119, 136, 153);
    m["lightsteelblue"] = rgb(176, 196, 222);
    m["lightyellow"] = rgb(255, 255, 224);
    m["lime"] = rgb(0, 255, 0);
    m["limegreen"] = rgb(50, 205, 50);
    m["linen"] = rgb(250, 240, 230);
    m["maroon"] = rgb(128, 0, 0);
    m["mediumaquamarine"] = rgb(102, 205, 170);
    m["mediumblue"] = rgb(0, 0, 205);
    m["mediumorchid"] = rgb(186, 85, 211);
    m["mediumpurple"] = rgb(147, 112, 219);
    m["mediumseagreen"] = rgb(60, 179, 113);
    m["mediumslateblue"] = rgb(123, 104, 238);
    m["mediumspringgreen"] = rgb(0, 250, 154);
    m["mediumturquoise"] = rgb(72, 209, 204);
    m["mediumvioletred"] = rgb(199, 21, 133);
    m["midnightblue"] = rgb(25, 25, 112);
    m["mintcream"] = rgb(245, 255, 250);
    m["mistyrose"] = rgb(255, 228, 225);
    m["moccasin"] = rgb(255, 228, 181);
    m["navajowhite"] = rgb(255, 222, 173);
    m["navy"] = rgb(0, 0, 128);
    m["oldlace"] = rgb(253, 245, 230);
    m["olive"] = rgb(128, 128, 0);
    m["olivedrab"] = rgb(107, 142, 35);
    m["orange"] = rgb(255, 165, 0);
    m["orangered"] = rgb(255, 69, 0);
    m["orchid"] = rgb(218, 112, 214);
    m["palegoldenrod"] = rgb(238, 232, 170);
    m["palegreen"] = rgb(152, 251, 152);
    m["paleturquoise"] = rgb(175, 238, 238);
    m["palevioletred"] = rgb(219, 112, 147);
    m["papayawhip"] = rgb(255, 239, 213);
    m["peachpuff"] = rgb(255, 218, 185);
    m["peru"] = rgb(205, 133, 63);
    m["pink"] = rgb(255, 192, 203);
    m["plum"] = rgb(221, 160, 221);
    m["powderblue"] = rgb(176, 224, 230);
    m["purple"] = rgb(128, 0, 128);
    m["rosybrown"] = rgb(188, 143, 143);
    m["royalblue"] = rgb(65, 105, 225);
    m["saddlebrown"] = rgb(139, 69, 19);
    m["salmon"] = rgb(250, 128, 114);
    m["sandybrown"] = rgb(244, 164, 96);
    m["seagreen"] = rgb(46, 139, 87);
    m["seashell"] = rgb(255, 245, 238);
    m["sienna"] = rgb(160, 82, 45);
    m["silver"] = rgb(192, 192, 192);
    m["skyblue"] = rgb(135, 206, 235);
    m["slateblue"] = rgb(106, 90, 205);
    m["slategray"] = rgb(112, 128, 144);
    m["slategrey"] = rgb(112, 128, 144);
    m["snow"] = rgb(255, 250, 250);
    m["springgreen"] = rgb(0, 255, 127);
    m["steelblue"] = rgb(70, 130, 180);
    m["tan"] = rgb(210, 180, 140);
    m["teal"] = rgb(0, 128, 128);
    m["thistle"] = rgb(216, 191, 216);
    m["tomato"] = rgb(255, 99, 71);
    m["turquoise"] = rgb(64, 224, 208);
    m["violet"] = rgb(238, 130, 238);
    m["wheat"] = rgb(245, 222, 179);
    m["whitesmoke"] = rgb(245, 245, 245);
    m["yellowgreen"] = rgb(154, 205, 50);
    return cast(immutable) m;
}

private immutable(uint[string]) namedColorTable;

shared static this()
{
    namedColorTable = buildNamedColors();
}

private uint parseColorName(string str)
{
    if (auto c = str in namedColorTable) return *c;
    return rgb(128, 128, 128);
}

private uint parseColor(string str)
{
    size_t i = 0;
    while (i < str.length && str[i] == ' ') i++;
    str = str[i .. $];
    if (str.length >= 1 && str[0] == '#')
        return parseColorHex(str);
    else if (str.length >= 4 && str[0] == 'r' && str[1] == 'g' && str[2] == 'b' && str[3] == '(')
        return parseColorRGB(str);
    return parseColorName(str);
}

private float parseOpacity(string str)
{
    float val = nsvgAtof(str);
    if (val < 0) val = 0;
    if (val > 1) val = 1;
    return val;
}

private float parseMiterLimit(string str)
{
    float val = nsvgAtof(str);
    return val < 0 ? 0 : val;
}

private NsvgUnits parseUnits(string units)
{
    if (units.length >= 2 && units[0] == 'p' && units[1] == 'x') return NsvgUnits.px;
    if (units.length >= 2 && units[0] == 'p' && units[1] == 't') return NsvgUnits.pt;
    if (units.length >= 2 && units[0] == 'p' && units[1] == 'c') return NsvgUnits.pc;
    if (units.length >= 2 && units[0] == 'm' && units[1] == 'm') return NsvgUnits.mm;
    if (units.length >= 2 && units[0] == 'c' && units[1] == 'm') return NsvgUnits.cm;
    if (units.length >= 2 && units[0] == 'i' && units[1] == 'n') return NsvgUnits.in_;
    if (units.length >= 1 && units[0] == '%') return NsvgUnits.percent;
    if (units.length >= 2 && units[0] == 'e' && units[1] == 'm') return NsvgUnits.em;
    if (units.length >= 2 && units[0] == 'e' && units[1] == 'x') return NsvgUnits.ex;
    return NsvgUnits.user;
}

private bool isCoordinateStart(string s)
{
    size_t i = 0;
    if (i < s.length && (s[i] == '-' || s[i] == '+')) i++;
    return i < s.length && (isDigit(s[i]) || s[i] == '.');
}

private NsvgCoordinate parseCoordinateRaw(string str)
{
    size_t numLen = parseNumberLen(str, 0);
    NsvgCoordinate coord;
    coord.units = parseUnits(str[numLen .. $]);
    coord.value = nsvgAtof(str[0 .. numLen]);
    return coord;
}

private NsvgCoordinate coord(float v, NsvgUnits units) { return NsvgCoordinate(v, units); }

private float parseCoordinate(NsvgParser p, string str, float orig, float length)
{
    return convertToPixels(p, parseCoordinateRaw(str), orig, length);
}

/// Returns the byte length of the matched `func(...)` span (0 if the
/// closing paren is missing), matching FLTK's own `int` return that
/// doubles as both a length and a not-found sentinel.
private size_t parseTransformArgs(string str, float[] args, ref int na)
{
    na = 0;
    size_t start = 0;
    while (start < str.length && str[start] != '(') start++;
    if (start >= str.length) return 0;
    size_t end = start;
    while (end < str.length && str[end] != ')') end++;
    if (end >= str.length) return 0;

    size_t ptr = start;
    while (ptr < end)
    {
        if (str[ptr] == '-' || str[ptr] == '+' || str[ptr] == '.' || isDigit(str[ptr]))
        {
            // Matches FLTK's own `if (*na >= maxNa) return 0;` --
            // more numbers than the transform function expects (e.g.
            // `matrix(1,2,3,4,5,6,7)`) makes the whole match report as
            // "not found" (0), not "found, here's how far to skip" --
            // the caller (parseTransform()) then only advances one
            // character and keeps scanning, rather than silently
            // accepting a truncated/overflowing arg list.
            if (na >= args.length) return 0;
            size_t len = parseNumberLen(str, ptr);
            args[na++] = nsvgAtof(str[ptr .. ptr + len]);
            ptr += len;
        }
        else ptr++;
    }
    return end;
}

private size_t parseMatrix(out float[6] xform, string str)
{
    float[6] t;
    int na;
    size_t len = parseTransformArgs(str, t, na);
    if (na != 6) return len;
    xform = t;
    return len;
}

private size_t parseTranslate(out float[6] xform, string str)
{
    float[2] args;
    int na;
    size_t len = parseTransformArgs(str, args, na);
    if (na == 1) args[1] = 0;
    float[6] t;
    xformSetTranslation(t, args[0], args[1]);
    xform = t;
    return len;
}

private size_t parseScale(out float[6] xform, string str)
{
    float[2] args;
    int na;
    size_t len = parseTransformArgs(str, args, na);
    if (na == 1) args[1] = args[0];
    float[6] t;
    xformSetScale(t, args[0], args[1]);
    xform = t;
    return len;
}

private size_t parseSkewX(out float[6] xform, string str)
{
    float[1] args;
    int na;
    size_t len = parseTransformArgs(str, args, na);
    float[6] t;
    xformSetSkewX(t, args[0] / 180.0f * NSVG_PI);
    xform = t;
    return len;
}

private size_t parseSkewY(out float[6] xform, string str)
{
    float[1] args;
    int na;
    size_t len = parseTransformArgs(str, args, na);
    float[6] t;
    xformSetSkewY(t, args[0] / 180.0f * NSVG_PI);
    xform = t;
    return len;
}

private size_t parseRotate(out float[6] xform, string str)
{
    float[3] args;
    int na;
    size_t len = parseTransformArgs(str, args, na);
    if (na == 1) args[1] = args[2] = 0;
    float[6] m, t;
    xformIdentity(m);
    if (na > 1)
    {
        xformSetTranslation(t, -args[1], -args[2]);
        xformMultiply(m, t);
    }
    xformSetRotation(t, args[0] / 180.0f * NSVG_PI);
    xformMultiply(m, t);
    if (na > 1)
    {
        xformSetTranslation(t, args[1], args[2]);
        xformMultiply(m, t);
    }
    xform = m;
    return len;
}

private bool startsWith(string s, string prefix)
{
    return s.length >= prefix.length && s[0 .. prefix.length] == prefix;
}

private void parseTransform(out float[6] xform, string str)
{
    xformIdentity(xform);
    while (str.length > 0)
    {
        float[6] t;
        size_t len;
        if (startsWith(str, "matrix")) len = parseMatrix(t, str);
        else if (startsWith(str, "translate")) len = parseTranslate(t, str);
        else if (startsWith(str, "scale")) len = parseScale(t, str);
        else if (startsWith(str, "rotate")) len = parseRotate(t, str);
        else if (startsWith(str, "skewX")) len = parseSkewX(t, str);
        else if (startsWith(str, "skewY")) len = parseSkewY(t, str);
        else { str = str[1 .. $]; continue; }

        if (len != 0) str = str[len .. $];
        else { str = str[1 .. $]; continue; }

        xformPremultiply(xform, t);
    }
}

private string parseUrl(string str)
{
    // str starts with "url(".
    auto s = str[4 .. $];
    if (s.length > 0 && s[0] == '#') s = s[1 .. $];
    size_t i = 0;
    while (i < s.length && s[i] != ')') i++;
    return s[0 .. i];
}

private NsvgLineCap parseLineCap(string str)
{
    if (str == "butt") return NsvgLineCap.butt;
    if (str == "round") return NsvgLineCap.round;
    if (str == "square") return NsvgLineCap.square;
    return NsvgLineCap.butt;
}

private NsvgLineJoin parseLineJoin(string str)
{
    if (str == "miter") return NsvgLineJoin.miter;
    if (str == "round") return NsvgLineJoin.round;
    if (str == "bevel") return NsvgLineJoin.bevel;
    return NsvgLineJoin.miter;
}

private NsvgFillRule parseFillRule(string str)
{
    if (str == "nonzero") return NsvgFillRule.nonzero;
    if (str == "evenodd") return NsvgFillRule.evenodd;
    return NsvgFillRule.nonzero;
}

private int parseStrokeDashArray(NsvgParser p, string str, ref float[NSVG_MAX_DASHES] strokeDashArray)
{
    if (str.length > 0 && str[0] == 'n') return 0; // "none"

    int count = 0;
    size_t pos = 0;
    while (pos < str.length)
    {
        pos = skipSpacesCommas(str, pos);
        size_t start = pos;
        while (pos < str.length && !isSpace(str[pos]) && str[pos] != ',') pos++;
        if (pos == start) break;
        string item = str[start .. pos];
        if (count < NSVG_MAX_DASHES)
            strokeDashArray[count++] = fabs(parseCoordinate(p, item, 0.0f, actualLength(p)));
    }

    float sum = 0;
    for (int i = 0; i < count; i++) sum += strokeDashArray[i];
    if (sum <= 1e-6f) count = 0;

    return count;
}

private void parseStyle(NsvgParser p, string str);

private bool parseAttr(NsvgParser p, string name, string value)
{
    ref attr() { return p.attr; }

    switch (name)
    {
    case "style":
        parseStyle(p, value);
        break;
    case "display":
        if (value == "none") attr.visible = false;
        break;
    case "fill":
        if (value == "none") attr.hasFill = 0;
        else if (startsWith(value, "url(")) { attr.hasFill = 2; attr.fillGradient = parseUrl(value); }
        else { attr.hasFill = 1; attr.fillColor = parseColor(value); }
        break;
    case "opacity":
        attr.opacity = parseOpacity(value);
        break;
    case "fill-opacity":
        attr.fillOpacity = parseOpacity(value);
        break;
    case "stroke":
        if (value == "none") attr.hasStroke = 0;
        else if (startsWith(value, "url(")) { attr.hasStroke = 2; attr.strokeGradient = parseUrl(value); }
        else { attr.hasStroke = 1; attr.strokeColor = parseColor(value); }
        break;
    case "stroke-width":
        attr.strokeWidth = parseCoordinate(p, value, 0.0f, actualLength(p));
        break;
    case "stroke-dasharray":
        attr.strokeDashCount = parseStrokeDashArray(p, value, attr.strokeDashArray);
        break;
    case "stroke-dashoffset":
        attr.strokeDashOffset = parseCoordinate(p, value, 0.0f, actualLength(p));
        break;
    case "stroke-opacity":
        attr.strokeOpacity = parseOpacity(value);
        break;
    case "stroke-linecap":
        attr.strokeLineCap = parseLineCap(value);
        break;
    case "stroke-linejoin":
        attr.strokeLineJoin = parseLineJoin(value);
        break;
    case "stroke-miterlimit":
        attr.miterLimit = parseMiterLimit(value);
        break;
    case "fill-rule":
        attr.fillRule = parseFillRule(value);
        break;
    case "font-size":
        attr.fontSize = parseCoordinate(p, value, 0.0f, actualLength(p));
        break;
    case "transform":
        float[6] xform;
        parseTransform(xform, value);
        xformPremultiply(attr.xform, xform);
        break;
    case "stop-color":
        attr.stopColor = parseColor(value);
        break;
    case "stop-opacity":
        attr.stopOpacity = parseOpacity(value);
        break;
    case "offset":
        attr.stopOffset = parseCoordinate(p, value, 0.0f, 1.0f);
        break;
    case "id":
        attr.id = value;
        break;
    default:
        return false;
    }
    return true;
}

private void parseNameValue(NsvgParser p, string s)
{
    size_t colon = 0;
    while (colon < s.length && s[colon] != ':') colon++;

    size_t nameEnd = colon;
    while (nameEnd > 0 && isSpace(s[nameEnd - 1])) nameEnd--;
    string name = s[0 .. nameEnd];

    size_t valStart = colon < s.length ? colon + 1 : colon;
    while (valStart < s.length && isSpace(s[valStart])) valStart++;
    string value = s[valStart .. $];

    parseAttr(p, name, value);
}

private void parseStyle(NsvgParser p, string str)
{
    size_t pos = 0;
    while (pos < str.length)
    {
        while (pos < str.length && isSpace(str[pos])) pos++;
        size_t start = pos;
        while (pos < str.length && str[pos] != ';') pos++;
        size_t end = pos;
        while (end > start && isSpace(str[end - 1])) end--;

        parseNameValue(p, str[start .. end]);
        if (pos < str.length) pos++;
    }
}

private void parseAttribs(NsvgParser p, string[] attr)
{
    for (size_t i = 0; i + 1 < attr.length; i += 2)
    {
        if (attr[i] == "style") parseStyle(p, attr[i + 1]);
        else parseAttr(p, attr[i], attr[i + 1]);
    }
}

private int getArgsPerElement(char cmd)
{
    switch (cmd)
    {
    case 'v': case 'V': case 'h': case 'H': return 1;
    case 'm': case 'M': case 'l': case 'L': case 't': case 'T': return 2;
    case 'q': case 'Q': case 's': case 'S': return 4;
    case 'c': case 'C': return 6;
    case 'a': case 'A': return 7;
    case 'z': case 'Z': return 0;
    default: return -1;
    }
}

private void pathMoveTo(NsvgParser p, ref float cpx, ref float cpy, float[] args, bool rel)
{
    if (rel) { cpx += args[0]; cpy += args[1]; }
    else { cpx = args[0]; cpy = args[1]; }
    moveTo(p, cpx, cpy);
}

private void pathLineTo(NsvgParser p, ref float cpx, ref float cpy, float[] args, bool rel)
{
    if (rel) { cpx += args[0]; cpy += args[1]; }
    else { cpx = args[0]; cpy = args[1]; }
    lineTo(p, cpx, cpy);
}

private void pathHLineTo(NsvgParser p, ref float cpx, ref float cpy, float[] args, bool rel)
{
    if (rel) cpx += args[0]; else cpx = args[0];
    lineTo(p, cpx, cpy);
}

private void pathVLineTo(NsvgParser p, ref float cpx, ref float cpy, float[] args, bool rel)
{
    if (rel) cpy += args[0]; else cpy = args[0];
    lineTo(p, cpx, cpy);
}

private void pathCubicBezTo(NsvgParser p, ref float cpx, ref float cpy, ref float cpx2, ref float cpy2, float[] args, bool rel)
{
    float x2, y2, cx1, cy1, cx2, cy2;
    if (rel)
    {
        cx1 = cpx + args[0]; cy1 = cpy + args[1];
        cx2 = cpx + args[2]; cy2 = cpy + args[3];
        x2 = cpx + args[4]; y2 = cpy + args[5];
    }
    else
    {
        cx1 = args[0]; cy1 = args[1];
        cx2 = args[2]; cy2 = args[3];
        x2 = args[4]; y2 = args[5];
    }
    cubicBezTo(p, cx1, cy1, cx2, cy2, x2, y2);
    cpx2 = cx2; cpy2 = cy2;
    cpx = x2; cpy = y2;
}

private void pathCubicBezShortTo(NsvgParser p, ref float cpx, ref float cpy, ref float cpx2, ref float cpy2, float[] args, bool rel)
{
    float x1 = cpx, y1 = cpy;
    float x2, y2, cx2, cy2;
    if (rel) { cx2 = cpx + args[0]; cy2 = cpy + args[1]; x2 = cpx + args[2]; y2 = cpy + args[3]; }
    else { cx2 = args[0]; cy2 = args[1]; x2 = args[2]; y2 = args[3]; }
    float cx1 = 2 * x1 - cpx2;
    float cy1 = 2 * y1 - cpy2;
    cubicBezTo(p, cx1, cy1, cx2, cy2, x2, y2);
    cpx2 = cx2; cpy2 = cy2;
    cpx = x2; cpy = y2;
}

private void pathQuadBezTo(NsvgParser p, ref float cpx, ref float cpy, ref float cpx2, ref float cpy2, float[] args, bool rel)
{
    float x1 = cpx, y1 = cpy;
    float x2, y2, cx, cy;
    if (rel) { cx = cpx + args[0]; cy = cpy + args[1]; x2 = cpx + args[2]; y2 = cpy + args[3]; }
    else { cx = args[0]; cy = args[1]; x2 = args[2]; y2 = args[3]; }
    float cx1 = x1 + 2.0f / 3.0f * (cx - x1);
    float cy1 = y1 + 2.0f / 3.0f * (cy - y1);
    float cx2 = x2 + 2.0f / 3.0f * (cx - x2);
    float cy2 = y2 + 2.0f / 3.0f * (cy - y2);
    cubicBezTo(p, cx1, cy1, cx2, cy2, x2, y2);
    cpx2 = cx; cpy2 = cy;
    cpx = x2; cpy = y2;
}

private void pathQuadBezShortTo(NsvgParser p, ref float cpx, ref float cpy, ref float cpx2, ref float cpy2, float[] args, bool rel)
{
    float x1 = cpx, y1 = cpy;
    float x2, y2;
    if (rel) { x2 = cpx + args[0]; y2 = cpy + args[1]; }
    else { x2 = args[0]; y2 = args[1]; }
    float cx = 2 * x1 - cpx2;
    float cy = 2 * y1 - cpy2;
    float cx1 = x1 + 2.0f / 3.0f * (cx - x1);
    float cy1 = y1 + 2.0f / 3.0f * (cy - y1);
    float cx2 = x2 + 2.0f / 3.0f * (cx - x2);
    float cy2 = y2 + 2.0f / 3.0f * (cy - y2);
    cubicBezTo(p, cx1, cy1, cx2, cy2, x2, y2);
    cpx2 = cx; cpy2 = cy;
    cpx = x2; cpy = y2;
}

private float sq(float x) { return x * x; }
private float vmag(float x, float y) { return sqrt(x * x + y * y); }

private float vecrat(float ux, float uy, float vx, float vy)
{
    return (ux * vx + uy * vy) / (vmag(ux, uy) * vmag(vx, vy));
}

private float vecang(float ux, float uy, float vx, float vy)
{
    float r = vecrat(ux, uy, vx, vy);
    if (r < -1.0f) r = -1.0f;
    if (r > 1.0f) r = 1.0f;
    return ((ux * vy < uy * vx) ? -1.0f : 1.0f) * acos(r);
}

/// Elliptical arc-to-cubic-bezier conversion, ported from canvg
/// (https://code.google.com/p/canvg/) via nanosvg.h, per that file's own
/// attribution.
private void pathArcTo(NsvgParser p, ref float cpx, ref float cpy, float[] args, bool rel)
{
    float rx = fabs(args[0]);
    float ry = fabs(args[1]);
    float rotx = args[2] / 180.0f * NSVG_PI;
    int fa = fabs(args[3]) > 1e-6 ? 1 : 0;
    int fs = fabs(args[4]) > 1e-6 ? 1 : 0;
    float x1 = cpx, y1 = cpy;
    float x2, y2;
    if (rel) { x2 = cpx + args[5]; y2 = cpy + args[6]; }
    else { x2 = args[5]; y2 = args[6]; }

    float dx = x1 - x2, dy = y1 - y2;
    float d = sqrt(dx * dx + dy * dy);
    if (d < 1e-6f || rx < 1e-6f || ry < 1e-6f)
    {
        lineTo(p, x2, y2);
        cpx = x2; cpy = y2;
        return;
    }

    float sinrx = sin(rotx);
    float cosrx = cos(rotx);

    float x1p = cosrx * dx / 2.0f + sinrx * dy / 2.0f;
    float y1p = -sinrx * dx / 2.0f + cosrx * dy / 2.0f;
    d = sq(x1p) / sq(rx) + sq(y1p) / sq(ry);
    if (d > 1)
    {
        d = sqrt(d);
        rx *= d;
        ry *= d;
    }

    float s = 0.0f;
    float sa = sq(rx) * sq(ry) - sq(rx) * sq(y1p) - sq(ry) * sq(x1p);
    float sb = sq(rx) * sq(y1p) + sq(ry) * sq(x1p);
    if (sa < 0.0f) sa = 0.0f;
    if (sb > 0.0f) s = sqrt(sa / sb);
    if (fa == fs) s = -s;
    float cxp = s * rx * y1p / ry;
    float cyp = s * -ry * x1p / rx;

    float cx = (x1 + x2) / 2.0f + cosrx * cxp - sinrx * cyp;
    float cy = (y1 + y2) / 2.0f + sinrx * cxp + cosrx * cyp;

    float ux = (x1p - cxp) / rx;
    float uy = (y1p - cyp) / ry;
    float vx = (-x1p - cxp) / rx;
    float vy = (-y1p - cyp) / ry;
    float a1 = vecang(1.0f, 0.0f, ux, uy);
    float da = vecang(ux, uy, vx, vy);

    if (fs == 0 && da > 0) da -= 2 * NSVG_PI;
    else if (fs == 1 && da < 0) da += 2 * NSVG_PI;

    float[6] t = [cosrx, sinrx, -sinrx, cosrx, cx, cy];

    int ndivs = cast(int)(fabs(da) / (NSVG_PI * 0.5f) + 1.0f);
    float hda = (da / ndivs) / 2.0f;
    if (hda < 1e-3f && hda > -1e-3f) hda *= 0.5f;
    else hda = (1.0f - cos(hda)) / sin(hda);
    float kappa = fabs(4.0f / 3.0f * hda);
    if (da < 0.0f) kappa = -kappa;

    float px = 0, py = 0, ptanx = 0, ptany = 0;
    float x = 0, y = 0;
    for (int i = 0; i <= ndivs; i++)
    {
        float a = a1 + da * (cast(float) i / cast(float) ndivs);
        float adx = cos(a), ady = sin(a);
        float tanx, tany;
        xformPoint(x, y, adx * rx, ady * ry, t);
        xformVec(tanx, tany, -ady * rx * kappa, adx * ry * kappa, t);
        if (i > 0)
            cubicBezTo(p, px + ptanx, py + ptany, x - tanx, y - tany, x, y);
        px = x; py = y;
        ptanx = tanx; ptany = tany;
    }

    cpx = x2; cpy = y2;
}

private bool isCoordinate(string item) { return isCoordinateStart(item); }

private void parsePath(NsvgParser p, string[] attr)
{
    string d;
    string[] rest;
    for (size_t i = 0; i + 1 < attr.length; i += 2)
    {
        if (attr[i] == "d") d = attr[i + 1];
        else rest ~= [attr[i], attr[i + 1]];
    }
    if (rest.length) parseAttribs(p, rest);

    if (d.length)
    {
        resetPath(p);
        float cpx = 0, cpy = 0, cpx2 = 0, cpy2 = 0;
        bool initPoint = false;
        bool closedFlag = false;
        char cmd = '\0';
        int rargs = 0;
        float[10] args;
        int nargs = 0;

        size_t pos = 0;
        while (pos < d.length)
        {
            string item;
            if ((cmd == 'A' || cmd == 'a') && (nargs == 3 || nargs == 4))
                getNextPathItemArcFlag(d, pos, item);
            if (item.length == 0)
                getNextPathItem(d, pos, item);
            if (item.length == 0) break;

            if (cmd != '\0' && isCoordinate(item))
            {
                if (nargs < 10) args[nargs++] = nsvgAtof(item);
                if (nargs >= rargs)
                {
                    switch (cmd)
                    {
                    case 'm': case 'M':
                        pathMoveTo(p, cpx, cpy, args[0 .. nargs], cmd == 'm');
                        cmd = (cmd == 'm') ? 'l' : 'L';
                        rargs = getArgsPerElement(cmd);
                        cpx2 = cpx; cpy2 = cpy;
                        initPoint = true;
                        break;
                    case 'l': case 'L':
                        pathLineTo(p, cpx, cpy, args[0 .. nargs], cmd == 'l');
                        cpx2 = cpx; cpy2 = cpy;
                        break;
                    case 'H': case 'h':
                        pathHLineTo(p, cpx, cpy, args[0 .. nargs], cmd == 'h');
                        cpx2 = cpx; cpy2 = cpy;
                        break;
                    case 'V': case 'v':
                        pathVLineTo(p, cpx, cpy, args[0 .. nargs], cmd == 'v');
                        cpx2 = cpx; cpy2 = cpy;
                        break;
                    case 'C': case 'c':
                        pathCubicBezTo(p, cpx, cpy, cpx2, cpy2, args[0 .. nargs], cmd == 'c');
                        break;
                    case 'S': case 's':
                        pathCubicBezShortTo(p, cpx, cpy, cpx2, cpy2, args[0 .. nargs], cmd == 's');
                        break;
                    case 'Q': case 'q':
                        pathQuadBezTo(p, cpx, cpy, cpx2, cpy2, args[0 .. nargs], cmd == 'q');
                        break;
                    case 'T': case 't':
                        pathQuadBezShortTo(p, cpx, cpy, cpx2, cpy2, args[0 .. nargs], cmd == 't');
                        break;
                    case 'A': case 'a':
                        pathArcTo(p, cpx, cpy, args[0 .. nargs], cmd == 'a');
                        cpx2 = cpx; cpy2 = cpy;
                        break;
                    default:
                        if (nargs >= 2)
                        {
                            cpx = args[nargs - 2];
                            cpy = args[nargs - 1];
                            cpx2 = cpx; cpy2 = cpy;
                        }
                        break;
                    }
                    nargs = 0;
                }
            }
            else
            {
                cmd = item[0];
                if (cmd == 'M' || cmd == 'm')
                {
                    if (p.pts.length > 0) addPath(p, closedFlag);
                    resetPath(p);
                    closedFlag = false;
                    nargs = 0;
                }
                else if (!initPoint)
                {
                    cmd = '\0';
                }
                if (cmd == 'Z' || cmd == 'z')
                {
                    closedFlag = true;
                    if (p.pts.length > 0)
                    {
                        cpx = p.pts[0];
                        cpy = p.pts[1];
                        cpx2 = cpx; cpy2 = cpy;
                        addPath(p, closedFlag);
                    }
                    resetPath(p);
                    moveTo(p, cpx, cpy);
                    closedFlag = false;
                    nargs = 0;
                }
                rargs = getArgsPerElement(cmd);
                if (rargs == -1) { cmd = '\0'; rargs = 0; }
            }
        }
        if (p.pts.length) addPath(p, closedFlag);
    }

    addShape(p);
}

private void parseRect(NsvgParser p, string[] attr)
{
    float x = 0, y = 0, w = 0, h = 0, rx = -1, ry = -1;
    for (size_t i = 0; i + 1 < attr.length; i += 2)
    {
        if (!parseAttr(p, attr[i], attr[i + 1]))
        {
            switch (attr[i])
            {
            case "x": x = parseCoordinate(p, attr[i + 1], actualOrigX(p), actualWidth(p)); break;
            case "y": y = parseCoordinate(p, attr[i + 1], actualOrigY(p), actualHeight(p)); break;
            case "width": w = parseCoordinate(p, attr[i + 1], 0.0f, actualWidth(p)); break;
            case "height": h = parseCoordinate(p, attr[i + 1], 0.0f, actualHeight(p)); break;
            case "rx": rx = fabs(parseCoordinate(p, attr[i + 1], 0.0f, actualWidth(p))); break;
            case "ry": ry = fabs(parseCoordinate(p, attr[i + 1], 0.0f, actualHeight(p))); break;
            default: break;
            }
        }
    }

    if (rx < 0.0f && ry > 0.0f) rx = ry;
    if (ry < 0.0f && rx > 0.0f) ry = rx;
    if (rx < 0.0f) rx = 0.0f;
    if (ry < 0.0f) ry = 0.0f;
    if (rx > w / 2.0f) rx = w / 2.0f;
    if (ry > h / 2.0f) ry = h / 2.0f;

    if (w != 0.0f && h != 0.0f)
    {
        resetPath(p);
        if (rx < 0.00001f || ry < 0.0001f)
        {
            moveTo(p, x, y);
            lineTo(p, x + w, y);
            lineTo(p, x + w, y + h);
            lineTo(p, x, y + h);
        }
        else
        {
            moveTo(p, x + rx, y);
            lineTo(p, x + w - rx, y);
            cubicBezTo(p, x + w - rx * (1 - NSVG_KAPPA90), y, x + w, y + ry * (1 - NSVG_KAPPA90), x + w, y + ry);
            lineTo(p, x + w, y + h - ry);
            cubicBezTo(p, x + w, y + h - ry * (1 - NSVG_KAPPA90), x + w - rx * (1 - NSVG_KAPPA90), y + h, x + w - rx, y + h);
            lineTo(p, x + rx, y + h);
            cubicBezTo(p, x + rx * (1 - NSVG_KAPPA90), y + h, x, y + h - ry * (1 - NSVG_KAPPA90), x, y + h - ry);
            lineTo(p, x, y + ry);
            cubicBezTo(p, x, y + ry * (1 - NSVG_KAPPA90), x + rx * (1 - NSVG_KAPPA90), y, x + rx, y);
        }
        addPath(p, true);
        addShape(p);
    }
}

private void parseCircle(NsvgParser p, string[] attr)
{
    float cx = 0, cy = 0, r = 0;
    for (size_t i = 0; i + 1 < attr.length; i += 2)
    {
        if (!parseAttr(p, attr[i], attr[i + 1]))
        {
            switch (attr[i])
            {
            case "cx": cx = parseCoordinate(p, attr[i + 1], actualOrigX(p), actualWidth(p)); break;
            case "cy": cy = parseCoordinate(p, attr[i + 1], actualOrigY(p), actualHeight(p)); break;
            case "r": r = fabs(parseCoordinate(p, attr[i + 1], 0.0f, actualLength(p))); break;
            default: break;
            }
        }
    }

    if (r > 0.0f)
    {
        resetPath(p);
        moveTo(p, cx + r, cy);
        cubicBezTo(p, cx + r, cy + r * NSVG_KAPPA90, cx + r * NSVG_KAPPA90, cy + r, cx, cy + r);
        cubicBezTo(p, cx - r * NSVG_KAPPA90, cy + r, cx - r, cy + r * NSVG_KAPPA90, cx - r, cy);
        cubicBezTo(p, cx - r, cy - r * NSVG_KAPPA90, cx - r * NSVG_KAPPA90, cy - r, cx, cy - r);
        cubicBezTo(p, cx + r * NSVG_KAPPA90, cy - r, cx + r, cy - r * NSVG_KAPPA90, cx + r, cy);
        addPath(p, true);
        addShape(p);
    }
}

private void parseEllipse(NsvgParser p, string[] attr)
{
    float cx = 0, cy = 0, rx = 0, ry = 0;
    for (size_t i = 0; i + 1 < attr.length; i += 2)
    {
        if (!parseAttr(p, attr[i], attr[i + 1]))
        {
            switch (attr[i])
            {
            case "cx": cx = parseCoordinate(p, attr[i + 1], actualOrigX(p), actualWidth(p)); break;
            case "cy": cy = parseCoordinate(p, attr[i + 1], actualOrigY(p), actualHeight(p)); break;
            case "rx": rx = fabs(parseCoordinate(p, attr[i + 1], 0.0f, actualWidth(p))); break;
            case "ry": ry = fabs(parseCoordinate(p, attr[i + 1], 0.0f, actualHeight(p))); break;
            default: break;
            }
        }
    }

    if (rx > 0.0f && ry > 0.0f)
    {
        resetPath(p);
        moveTo(p, cx + rx, cy);
        cubicBezTo(p, cx + rx, cy + ry * NSVG_KAPPA90, cx + rx * NSVG_KAPPA90, cy + ry, cx, cy + ry);
        cubicBezTo(p, cx - rx * NSVG_KAPPA90, cy + ry, cx - rx, cy + ry * NSVG_KAPPA90, cx - rx, cy);
        cubicBezTo(p, cx - rx, cy - ry * NSVG_KAPPA90, cx - rx * NSVG_KAPPA90, cy - ry, cx, cy - ry);
        cubicBezTo(p, cx + rx * NSVG_KAPPA90, cy - ry, cx + rx, cy - ry * NSVG_KAPPA90, cx + rx, cy);
        addPath(p, true);
        addShape(p);
    }
}

private void parseLine(NsvgParser p, string[] attr)
{
    float x1 = 0, y1 = 0, x2 = 0, y2 = 0;
    for (size_t i = 0; i + 1 < attr.length; i += 2)
    {
        if (!parseAttr(p, attr[i], attr[i + 1]))
        {
            switch (attr[i])
            {
            case "x1": x1 = parseCoordinate(p, attr[i + 1], actualOrigX(p), actualWidth(p)); break;
            case "y1": y1 = parseCoordinate(p, attr[i + 1], actualOrigY(p), actualHeight(p)); break;
            case "x2": x2 = parseCoordinate(p, attr[i + 1], actualOrigX(p), actualWidth(p)); break;
            case "y2": y2 = parseCoordinate(p, attr[i + 1], actualOrigY(p), actualHeight(p)); break;
            default: break;
            }
        }
    }

    resetPath(p);
    moveTo(p, x1, y1);
    lineTo(p, x2, y2);
    addPath(p, false);
    addShape(p);
}

private void parsePoly(NsvgParser p, string[] attr, bool closeFlag)
{
    resetPath(p);
    for (size_t i = 0; i + 1 < attr.length; i += 2)
    {
        if (!parseAttr(p, attr[i], attr[i + 1]))
        {
            if (attr[i] == "points")
            {
                string s = attr[i + 1];
                size_t pos = 0;
                float[2] args;
                int nargs = 0;
                int npts = 0;
                while (pos < s.length)
                {
                    string item;
                    getNextPathItem(s, pos, item);
                    if (item.length == 0) break;
                    args[nargs++] = nsvgAtof(item);
                    if (nargs >= 2)
                    {
                        if (npts == 0) moveTo(p, args[0], args[1]);
                        else lineTo(p, args[0], args[1]);
                        nargs = 0;
                        npts++;
                    }
                }
            }
        }
    }
    addPath(p, closeFlag);
    addShape(p);
}

private void parseSVG(NsvgParser p, string[] attr)
{
    for (size_t i = 0; i + 1 < attr.length; i += 2)
    {
        if (!parseAttr(p, attr[i], attr[i + 1]))
        {
            if (attr[i] == "width")
                p.image.width = parseCoordinate(p, attr[i + 1], 0.0f, 0.0f);
            else if (attr[i] == "height")
                p.image.height = parseCoordinate(p, attr[i + 1], 0.0f, 0.0f);
            else if (attr[i] == "viewBox")
            {
                string s = attr[i + 1];
                size_t pos = 0;
                size_t len = parseNumberLen(s, pos);
                p.viewMinx = nsvgAtof(s[pos .. pos + len]);
                pos += len;
                pos = skipVbSep(s, pos);
                if (pos >= s.length) continue;
                len = parseNumberLen(s, pos);
                p.viewMiny = nsvgAtof(s[pos .. pos + len]);
                pos += len;
                pos = skipVbSep(s, pos);
                if (pos >= s.length) continue;
                len = parseNumberLen(s, pos);
                p.viewWidth = nsvgAtof(s[pos .. pos + len]);
                pos += len;
                pos = skipVbSep(s, pos);
                if (pos >= s.length) continue;
                len = parseNumberLen(s, pos);
                p.viewHeight = nsvgAtof(s[pos .. pos + len]);
            }
            else if (attr[i] == "preserveAspectRatio")
            {
                string v = attr[i + 1];
                if (v.indexOf("none") >= 0)
                    p.alignType = AlignType.none;
                else
                {
                    if (v.indexOf("xMin") >= 0) p.alignX = AlignPos.min;
                    else if (v.indexOf("xMid") >= 0) p.alignX = AlignPos.mid;
                    else if (v.indexOf("xMax") >= 0) p.alignX = AlignPos.max;
                    if (v.indexOf("yMin") >= 0) p.alignY = AlignPos.min;
                    else if (v.indexOf("yMid") >= 0) p.alignY = AlignPos.mid;
                    else if (v.indexOf("yMax") >= 0) p.alignY = AlignPos.max;
                    p.alignType = v.indexOf("slice") >= 0 ? AlignType.slice : AlignType.meet;
                }
            }
        }
    }
}

private size_t skipVbSep(string s, size_t pos)
{
    while (pos < s.length && (isSpace(s[pos]) || s[pos] == '%' || s[pos] == ',')) pos++;
    return pos;
}

private void parseGradient(NsvgParser p, string[] attr, NsvgPaintType type)
{
    auto grad = new NsvgGradientData();
    grad.units = NsvgGradientUnits.objectSpace;
    grad.type = type;
    if (grad.type == NsvgPaintType.linearGradient)
    {
        grad.linear.x1 = coord(0.0f, NsvgUnits.percent);
        grad.linear.y1 = coord(0.0f, NsvgUnits.percent);
        grad.linear.x2 = coord(100.0f, NsvgUnits.percent);
        grad.linear.y2 = coord(0.0f, NsvgUnits.percent);
    }
    else if (grad.type == NsvgPaintType.radialGradient)
    {
        grad.radial.cx = coord(50.0f, NsvgUnits.percent);
        grad.radial.cy = coord(50.0f, NsvgUnits.percent);
        grad.radial.r = coord(50.0f, NsvgUnits.percent);
    }
    xformIdentity(grad.xform);

    for (size_t i = 0; i + 1 < attr.length; i += 2)
    {
        if (attr[i] == "id")
        {
            grad.id = attr[i + 1];
        }
        else if (!parseAttr(p, attr[i], attr[i + 1]))
        {
            switch (attr[i])
            {
            case "gradientUnits":
                grad.units = attr[i + 1] == "objectBoundingBox" ? NsvgGradientUnits.objectSpace : NsvgGradientUnits.userSpace;
                break;
            case "gradientTransform":
                parseTransform(grad.xform, attr[i + 1]);
                break;
            case "cx": grad.radial.cx = parseCoordinateRaw(attr[i + 1]); break;
            case "cy": grad.radial.cy = parseCoordinateRaw(attr[i + 1]); break;
            case "r": grad.radial.r = parseCoordinateRaw(attr[i + 1]); break;
            case "fx": grad.radial.fx = parseCoordinateRaw(attr[i + 1]); break;
            case "fy": grad.radial.fy = parseCoordinateRaw(attr[i + 1]); break;
            case "x1": grad.linear.x1 = parseCoordinateRaw(attr[i + 1]); break;
            case "y1": grad.linear.y1 = parseCoordinateRaw(attr[i + 1]); break;
            case "x2": grad.linear.x2 = parseCoordinateRaw(attr[i + 1]); break;
            case "y2": grad.linear.y2 = parseCoordinateRaw(attr[i + 1]); break;
            case "spreadMethod":
                if (attr[i + 1] == "pad") grad.spread = NsvgSpreadType.pad;
                else if (attr[i + 1] == "reflect") grad.spread = NsvgSpreadType.reflect;
                else if (attr[i + 1] == "repeat") grad.spread = NsvgSpreadType.repeat;
                break;
            case "xlink:href":
                auto href = attr[i + 1];
                grad.ref_ = href.length > 1 ? href[1 .. $] : "";
                break;
            default: break;
            }
        }
    }

    grad.next = p.gradients;
    p.gradients = grad;
}

private void parseGradientStop(NsvgParser p, string[] attr)
{
    p.attr.stopOffset = 0;
    p.attr.stopColor = 0;
    p.attr.stopOpacity = 1.0f;

    for (size_t i = 0; i + 1 < attr.length; i += 2)
        parseAttr(p, attr[i], attr[i + 1]);

    auto grad = p.gradients;
    if (grad is null) return;

    NsvgGradientStop stop;
    stop.color = p.attr.stopColor | (cast(uint)(p.attr.stopOpacity * 255) << 24);
    stop.offset = p.attr.stopOffset;

    size_t idx = grad.stops.length;
    foreach (i, ref s; grad.stops)
    {
        if (stop.offset < s.offset) { idx = i; break; }
    }
    grad.stops.length++;
    for (size_t i = grad.stops.length - 1; i > idx; i--)
        grad.stops[i] = grad.stops[i - 1];
    grad.stops[idx] = stop;
}

private void startElement(NsvgParser p, string el, string[] attr)
{
    if (p.defsFlag)
    {
        if (el == "linearGradient") parseGradient(p, attr, NsvgPaintType.linearGradient);
        else if (el == "radialGradient") parseGradient(p, attr, NsvgPaintType.radialGradient);
        else if (el == "stop") parseGradientStop(p, attr);
        return;
    }

    switch (el)
    {
    case "g":
        p.attrStack ~= p.attr;
        parseAttribs(p, attr);
        break;
    case "path":
        if (p.pathFlag) break; // no nested paths
        p.attrStack ~= p.attr;
        parsePath(p, attr);
        p.attrStack.length--;
        break;
    case "rect":
        p.attrStack ~= p.attr;
        parseRect(p, attr);
        p.attrStack.length--;
        break;
    case "circle":
        p.attrStack ~= p.attr;
        parseCircle(p, attr);
        p.attrStack.length--;
        break;
    case "ellipse":
        p.attrStack ~= p.attr;
        parseEllipse(p, attr);
        p.attrStack.length--;
        break;
    case "line":
        p.attrStack ~= p.attr;
        parseLine(p, attr);
        p.attrStack.length--;
        break;
    case "polyline":
        p.attrStack ~= p.attr;
        parsePoly(p, attr, false);
        p.attrStack.length--;
        break;
    case "polygon":
        p.attrStack ~= p.attr;
        parsePoly(p, attr, true);
        p.attrStack.length--;
        break;
    case "linearGradient":
        parseGradient(p, attr, NsvgPaintType.linearGradient);
        break;
    case "radialGradient":
        parseGradient(p, attr, NsvgPaintType.radialGradient);
        break;
    case "stop":
        parseGradientStop(p, attr);
        break;
    case "defs":
        p.defsFlag = true;
        break;
    case "svg":
        parseSVG(p, attr);
        break;
    default:
        break;
    }
}

private void endElement(NsvgParser p, string el)
{
    switch (el)
    {
    case "g": if (p.attrStack.length > 1) p.attrStack.length--; break;
    case "path": p.pathFlag = false; break;
    case "defs": p.defsFlag = false; break;
    default: break;
    }
}

// ---------------------------------------------------------------------
// XML parser -- ported from nanosvg.h's `nsvg__parseXML()` family.
// Mutates `input` in place (writes '\0' tag/attribute terminators as it
// scans, exactly like the C original) -- callers must own a private,
// mutable copy (see this module's own top comment and `fl.svg_image`'s
// "duplicate before parse" step).
// ---------------------------------------------------------------------

private enum XmlState { content, tag }
private enum NSVG_XML_MAX_ATTRIBS = 256;

private void parseXmlContent(char[] s, void delegate(string) contentCb)
{
    size_t i = 0;
    while (i < s.length && isSpace(s[i])) i++;
    if (i >= s.length) return;
    if (contentCb) contentCb(cast(string) s[i .. $]);
}

private void parseXmlElement(char[] s, void delegate(string, string[]) startCb, void delegate(string) endCb)
{
    string[NSVG_XML_MAX_ATTRIBS * 2] attrBuf;
    int nattr = 0;
    bool start = false, end = false;

    size_t i = 0;
    while (i < s.length && isSpace(s[i])) i++;

    if (i < s.length && s[i] == '/') { i++; end = true; }
    else start = true;

    if (i >= s.length || s[i] == '?' || s[i] == '!') return;

    size_t nameStart = i;
    while (i < s.length && !isSpace(s[i])) i++;
    string name = cast(string) s[nameStart .. i];
    if (i < s.length) { s[i] = '\0'; name = cast(string) s[nameStart .. i]; i++; }

    while (!end && i < s.length && nattr < (NSVG_XML_MAX_ATTRIBS - 3) * 2)
    {
        while (i < s.length && isSpace(s[i])) i++;
        if (i >= s.length) break;
        if (s[i] == '/') { end = true; break; }

        size_t attrNameStart = i;
        while (i < s.length && !isSpace(s[i]) && s[i] != '=') i++;
        if (i >= s.length) break;
        string attrName = cast(string) s[attrNameStart .. i];
        s[i] = '\0'; i++;

        while (i < s.length && s[i] != '"' && s[i] != '\'') i++;
        if (i >= s.length) break;
        char quote = s[i];
        i++;
        size_t attrValStart = i;
        while (i < s.length && s[i] != quote) i++;
        string attrValue = cast(string) s[attrValStart .. i];
        if (i < s.length) { s[i] = '\0'; i++; }

        if (attrName.length && attrValue !is null)
        {
            attrBuf[nattr++] = attrName;
            attrBuf[nattr++] = attrValue;
        }
    }

    auto attrs = attrBuf[0 .. nattr].dup;

    if (start && startCb) startCb(name, attrs);
    if (end && endCb) endCb(name);
}

private void parseXml(char[] input, void delegate(string, string[]) startCb,
        void delegate(string) endCb, void delegate(string) contentCb)
{
    size_t mark = 0;
    XmlState state = XmlState.content;
    size_t i = 0;
    while (i < input.length)
    {
        if (input[i] == '<' && state == XmlState.content)
        {
            input[i] = '\0';
            parseXmlContent(input[mark .. i], contentCb);
            i++;
            mark = i;
            state = XmlState.tag;
        }
        else if (input[i] == '>' && state == XmlState.tag)
        {
            input[i] = '\0';
            parseXmlElement(input[mark .. i], startCb, endCb);
            i++;
            mark = i;
            state = XmlState.content;
        }
        else i++;
    }
}

// ---------------------------------------------------------------------
// viewBox scaling / gradient resolution / public entry point.
// ---------------------------------------------------------------------

private void imageBounds(NsvgParser p, out float[4] bounds)
{
    auto shape = p.image.shapes;
    if (shape is null) { bounds[] = 0; return; }
    bounds = shape.bounds;
    for (shape = shape.next; shape !is null; shape = shape.next)
    {
        bounds[0] = minf(bounds[0], shape.bounds[0]);
        bounds[1] = minf(bounds[1], shape.bounds[1]);
        bounds[2] = maxf(bounds[2], shape.bounds[2]);
        bounds[3] = maxf(bounds[3], shape.bounds[3]);
    }
}

private float viewAlign(float content, float container, AlignPos type)
{
    if (type == AlignPos.min) return 0;
    if (type == AlignPos.max) return container - content;
    return (container - content) * 0.5f;
}

private void scaleGradient(NsvgGradient grad, float tx, float ty, float sx, float sy)
{
    float[6] t;
    xformSetTranslation(t, tx, ty);
    xformMultiply(grad.xform, t);
    xformSetScale(t, sx, sy);
    xformMultiply(grad.xform, t);
}

private void scaleToViewbox(NsvgParser p, string units)
{
    float[4] bounds;
    imageBounds(p, bounds);

    if (p.viewWidth == 0)
    {
        if (p.image.width > 0) p.viewWidth = p.image.width;
        else { p.viewMinx = bounds[0]; p.viewWidth = bounds[2] - bounds[0]; }
    }
    if (p.viewHeight == 0)
    {
        if (p.image.height > 0) p.viewHeight = p.image.height;
        else { p.viewMiny = bounds[1]; p.viewHeight = bounds[3] - bounds[1]; }
    }
    if (p.image.width == 0) p.image.width = p.viewWidth;
    if (p.image.height == 0) p.image.height = p.viewHeight;

    float tx = -p.viewMinx;
    float ty = -p.viewMiny;
    float sx = p.viewWidth > 0 ? p.image.width / p.viewWidth : 0;
    float sy = p.viewHeight > 0 ? p.image.height / p.viewHeight : 0;
    float us = 1.0f / convertToPixels(p, coord(1.0f, parseUnits(units)), 0.0f, 1.0f);

    if (p.alignType == AlignType.meet)
    {
        sx = sy = minf(sx, sy);
        tx += viewAlign(p.viewWidth * sx, p.image.width, p.alignX) / sx;
        ty += viewAlign(p.viewHeight * sy, p.image.height, p.alignY) / sy;
    }
    else if (p.alignType == AlignType.slice)
    {
        sx = sy = maxf(sx, sy);
        tx += viewAlign(p.viewWidth * sx, p.image.width, p.alignX) / sx;
        ty += viewAlign(p.viewHeight * sy, p.image.height, p.alignY) / sy;
    }

    sx *= us;
    sy *= us;
    float avgs = (sx + sy) / 2.0f;
    for (auto shape = p.image.shapes; shape !is null; shape = shape.next)
    {
        shape.bounds[0] = (shape.bounds[0] + tx) * sx;
        shape.bounds[1] = (shape.bounds[1] + ty) * sy;
        shape.bounds[2] = (shape.bounds[2] + tx) * sx;
        shape.bounds[3] = (shape.bounds[3] + ty) * sy;
        for (auto path = shape.paths; path !is null; path = path.next)
        {
            path.bounds[0] = (path.bounds[0] + tx) * sx;
            path.bounds[1] = (path.bounds[1] + ty) * sy;
            path.bounds[2] = (path.bounds[2] + tx) * sx;
            path.bounds[3] = (path.bounds[3] + ty) * sy;
            for (size_t i = 0; i < path.pts.length / 2; i++)
            {
                path.pts[i * 2] = (path.pts[i * 2] + tx) * sx;
                path.pts[i * 2 + 1] = (path.pts[i * 2 + 1] + ty) * sy;
            }
        }

        if (shape.fill.type == NsvgPaintType.linearGradient || shape.fill.type == NsvgPaintType.radialGradient)
        {
            scaleGradient(shape.fill.gradient, tx, ty, sx, sy);
            float[6] t = shape.fill.gradient.xform;
            xformInverse(shape.fill.gradient.xform, t);
        }
        if (shape.stroke.type == NsvgPaintType.linearGradient || shape.stroke.type == NsvgPaintType.radialGradient)
        {
            scaleGradient(shape.stroke.gradient, tx, ty, sx, sy);
            float[6] t = shape.stroke.gradient.xform;
            xformInverse(shape.stroke.gradient.xform, t);
        }

        shape.strokeWidth *= avgs;
        shape.strokeDashOffset *= avgs;
        for (int i = 0; i < shape.strokeDashCount; i++)
            shape.strokeDashArray[i] *= avgs;
    }
}

private void createGradients(NsvgParser p)
{
    for (auto shape = p.image.shapes; shape !is null; shape = shape.next)
    {
        if (shape.fill.type == NsvgPaintType.undef)
        {
            if (shape.fillGradient.length)
            {
                float[6] inv;
                xformInverse(inv, shape.xform);
                float[4] localBounds;
                getLocalBounds(localBounds, shape, inv);
                NsvgPaintType t;
                shape.fill.gradient = createGradient(p, shape.fillGradient, localBounds, shape.xform, t);
                shape.fill.type = t;
            }
            if (shape.fill.type == NsvgPaintType.undef) shape.fill.type = NsvgPaintType.none;
        }
        if (shape.stroke.type == NsvgPaintType.undef)
        {
            if (shape.strokeGradient.length)
            {
                float[6] inv;
                xformInverse(inv, shape.xform);
                float[4] localBounds;
                getLocalBounds(localBounds, shape, inv);
                NsvgPaintType t;
                shape.stroke.gradient = createGradient(p, shape.strokeGradient, localBounds, shape.xform, t);
                shape.stroke.type = t;
            }
            if (shape.stroke.type == NsvgPaintType.undef) shape.stroke.type = NsvgPaintType.none;
        }
    }
}

/// Parses an SVG document from `input`, which is **mutated in place**
/// (matching FLTK's own `nsvgParse(char* input, ...)` -- see this
/// module's own top comment). `units` should be one of "px", "pt", "pc",
/// "mm", "cm", "in"; "px" is the common case. `dpi` controls unit
/// conversion; 96 if you don't otherwise care.
NsvgImage nsvgParse(char[] input, string units, float dpi)
{
    auto p = createParser();
    p.dpi = dpi;

    parseXml(input, (el, attr) => startElement(p, el, attr), (el) => endElement(p, el), (s) {});

    createGradients(p);
    scaleToViewbox(p, units);

    return p.image;
}

unittest
{
    // Minimal single-path, single-subpath SVG: exercises moveTo/lineTo,
    // the closing 'Z', hex color parsing, and viewBox-less width/height
    // sizing (falls back to the image's own bounds).
    string svg = `<svg width="10" height="10"><path d="M0 0 L10 0 L10 10 Z" fill="#ff0000"/></svg>`;
    auto buf = svg.dup;
    auto img = nsvgParse(buf, "px", 96);
    assert(img !is null);
    assert(img.width > 0 && img.height > 0);
    assert(img.shapes !is null);
    assert(img.shapes.next is null);
    assert(img.shapes.paths !is null);
    assert(img.shapes.paths.next is null);
    assert(img.shapes.paths.pts.length >= 8); // at least 4 points (x,y pairs)
    assert(img.shapes.fill.type == NsvgPaintType.color);
    assert((img.shapes.fill.color & 0xffffff) == 0x0000ff); // r=255,g=0,b=0 packed low-to-high
    assert((img.shapes.fill.color >> 24) == 255); // fully opaque
}

unittest
{
    // Named color + rgb() + opacity + viewBox scaling.
    string svg = `<svg width="100" height="100" viewBox="0 0 50 50">`
        ~ `<circle cx="25" cy="25" r="10" fill="blue" opacity="0.5"/>`
        ~ `<rect x="0" y="0" width="5" height="5" stroke="rgb(0, 255, 0)"/>`
        ~ `</svg>`;
    auto buf = svg.dup;
    auto img = nsvgParse(buf, "px", 96);
    assert(img.width == 100 && img.height == 100);
    assert(img.shapes !is null);
    // circle first (document order becomes a reverse-built-then... no,
    // addShape appends to shapesTail, so document order is preserved).
    auto circle = img.shapes;
    assert(circle.fill.type == NsvgPaintType.color);
    assert((circle.fill.color & 0xffffff) == rgb(0, 0, 255));
    // opacity="0.5" sets the shape's overall opacity (a separate field from
    // fill-opacity, which alone feeds the fill color's alpha channel) --
    // matches FLTK's distinct NSVGattrib::opacity vs. ::fillOpacity.
    assert(circle.opacity > 0.49f && circle.opacity < 0.51f);
    assert((circle.fill.color >> 24) == 255); // fillOpacity still defaults to 1

    auto rect = circle.next;
    assert(rect !is null);
    assert(rect.stroke.type == NsvgPaintType.color);
    assert((rect.stroke.color & 0xffffff) == rgb(0, 255, 0));

    // viewBox 0 0 50 50 scaled to a 100x100 image is a 2x scale factor;
    // circle radius 10 user units (20-wide bounding box) becomes 40 wide
    // in image space.
    float w = circle.bounds[2] - circle.bounds[0];
    assert(w > 39.0f && w < 41.0f);
}

unittest
{
    // The FLTK-logo SVG fixture used by samples/examples/howto_simple_svg.d
    // -- a real, non-trivial multi-subpath <path> (several disjoint glyph
    // outlines in one `d` attribute) plus a rect-shaped outer border,
    // exercising cubic beziers and multiple 'M' subpath restarts for real
    // (not just the hand-built single-line fixtures above).
    string svgLogo =
        "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
        ~ "<svg version=\"1.1\" id=\"Layer_1\" xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" x=\"0px\" y=\"0px\"\n"
        ~ "    width=\"640px\" height=\"480px\" viewBox=\"0 0 640 480\" enable-background=\"new 0 0 640 480\" xml:space=\"preserve\">\n"
        ~ "<path d=\"M282.658,250.271c0,5.31-1.031,10.156-3.087,14.543c-2.059,4.387-4.984,8.152-8.774,11.293\n"
        ~ "   c-3.793,3.144-8.477,5.58-14.055,7.312c-5.581,1.731-11.836,2.601-18.767,2.601c-9.968,0-18.605-1.572-25.917-4.713\n"
        ~ "   s-13.299-6.986-17.955-11.536l13.812-15.111c4.116,3.684,8.584,6.499,13.405,8.449c4.819,1.95,9.993,2.925,15.518,2.925\n"
        ~ "   c5.525,0,9.856-1.219,12.999-3.656c3.141-2.438,4.712-5.769,4.712-9.993c0-2.056-0.3-3.844-0.894-5.361\n"
        ~ "   c-0.596-1.517-1.653-2.925-3.168-4.226c-1.518-1.3-3.549-2.519-6.093-3.655c-2.546-1.138-5.768-2.301-9.668-3.494\n"
        ~ "   c-6.5-2.056-11.943-4.25-16.33-6.58c-4.387-2.328-7.937-4.9-10.643-7.719c-2.709-2.815-4.659-5.931-5.849-9.343\n"
        ~ "   c-1.193-3.412-1.788-7.23-1.788-11.455c0-5.2,1.082-9.831,3.25-13.893c2.166-4.062,5.144-7.5,8.937-10.318\n"
        ~ "   c3.791-2.815,8.178-4.956,13.162-6.418c4.981-1.462,10.343-2.193,16.086-2.193c8.449,0,15.842,1.247,22.179,3.737\n"
        ~ "   c6.337,2.493,11.997,6.121,16.98,10.887l-12.674,14.624c-7.583-6.281-15.655-9.424-24.21-9.424c-4.875,0-8.721,0.95-11.537,2.844\n"
        ~ "   c-2.818,1.896-4.225,4.578-4.225,8.043c0,1.843,0.297,3.412,0.894,4.712c0.594,1.3,1.65,2.519,3.168,3.656\n"
        ~ "   c1.516,1.137,3.656,2.249,6.418,3.331c2.763,1.084,6.309,2.33,10.643,3.736c5.306,1.734,10.046,3.631,14.218,5.688\n"
        ~ "   c4.169,2.06,7.662,4.524,10.48,7.394c2.815,2.871,4.981,6.174,6.5,9.911C281.898,240.603,282.658,245.071,282.658,250.271z\n"
        ~ "    M335.953,260.833l20.637-90.181h27.46l-32.011,112.604h-33.634l-32.173-112.604h28.598l20.311,90.181H335.953z M437.832,286.019\n"
        ~ "   c-16.357,0-28.896-5.01-37.615-15.03c-8.722-10.019-13.081-24.779-13.081-44.278c0-9.531,1.407-17.98,4.225-25.348\n"
        ~ "   c2.815-7.366,6.688-13.54,11.618-18.524c4.928-4.981,10.668-8.747,17.223-11.293c6.555-2.544,13.568-3.818,21.043-3.818\n"
        ~ "   c8.23,0,15.436,1.3,21.611,3.899c6.174,2.6,11.537,5.959,16.086,10.075l-14.137,14.624c-3.467-3.032-6.906-5.281-10.318-6.744\n"
        ~ "   s-7.393-2.193-11.941-2.193c-4.01,0-7.693,0.731-11.051,2.193s-6.256,3.793-8.691,6.987c-2.438,3.196-4.334,7.287-5.688,12.268\n"
        ~ "   c-1.355,4.984-2.031,10.996-2.031,18.037c0,7.367,0.486,13.567,1.463,18.604c0.975,5.037,2.408,9.1,4.305,12.187\n"
        ~ "   c1.895,3.087,4.307,5.309,7.23,6.662c2.926,1.355,6.338,2.031,10.238,2.031c5.631,0,10.613-1.244,14.947-3.737v-25.186h-14.785\n"
        ~ "   l-2.6-18.849h43.547v55.57c-5.85,3.793-12.297,6.718-19.336,8.774C453.051,284.987,445.631,286.019,437.832,286.019z M523.5,151.5\n"
        ~ "   c0-6.627-5.373-12-12-12h-343c-6.627,0-12,5.373-12,12v150c0,6.627,5.373,12,12,12h343c6.627,0,12-5.373,12-12V151.5z\"/>\n"
        ~ "</svg>\n";

    auto buf = svgLogo.dup;
    auto img = nsvgParse(buf, "px", 96);
    assert(img !is null);
    assert(img.width == 640 && img.height == 480);

    // One <path> element -> one shape.
    assert(img.shapes !is null);
    assert(img.shapes.next is null);

    // 4 'M' subpaths in the `d` attribute -> 4 linked NsvgPath entries.
    int pathCount = 0;
    for (auto path = img.shapes.paths; path !is null; path = path.next)
        pathCount++;
    assert(pathCount == 4);

    // Every subpath is closed ('z' at the end of each) and has real,
    // non-degenerate bezier point data -- proves the LZW-free but
    // still-nontrivial cubic-bezier command path (relative 'c'/'l'/'s'/'v'/
    // 'h' commands, not just the hand-built fixtures' plain M/L/Z) works on
    // real, densely-packed relative path data.
    for (auto path = img.shapes.paths; path !is null; path = path.next)
    {
        assert(path.closed);
        assert(path.pts.length >= 8);
        assert(path.bounds[2] > path.bounds[0]);
        assert(path.bounds[3] > path.bounds[1]);
    }

    // Default fill is black, fully opaque (no fill="..." attr on this
    // <path>, matching FLTK's default black-fill-visible-widget
    // convention).
    assert(img.shapes.fill.type == NsvgPaintType.color);
    assert((img.shapes.fill.color & 0xffffff) == 0);
    assert((img.shapes.fill.color >> 24) == 255);

    // Bounds should sit within the declared 640x480 viewBox/canvas.
    assert(img.shapes.bounds[0] >= 0 && img.shapes.bounds[2] <= 640);
    assert(img.shapes.bounds[1] >= 0 && img.shapes.bounds[3] <= 480);
}

unittest
{
    // transform="translate(...) rotate(...)" composition, and a <g> group
    // wrapping two children that both inherit the group's transform/fill.
    string svg = `<svg width="20" height="20">`
        ~ `<g transform="translate(5,5)" fill="#00ff00">`
        ~ `<rect x="0" y="0" width="2" height="2"/>`
        ~ `<rect x="10" y="10" width="2" height="2"/>`
        ~ `</g>`
        ~ `</svg>`;
    auto buf = svg.dup;
    auto img = nsvgParse(buf, "px", 96);
    assert(img.shapes !is null);
    auto r1 = img.shapes;
    auto r2 = r1.next;
    assert(r2 !is null && r2.next is null);
    foreach (r; [r1, r2])
    {
        assert(r.fill.type == NsvgPaintType.color);
        assert((r.fill.color & 0xffffff) == rgb(0, 255, 0));
    }
    // r1's rect at (0,0) translated by (5,5) -> bounds start at x=5,y=5.
    assert(r1.bounds[0] > 4.5f && r1.bounds[0] < 5.5f);
    // r2's rect at (10,10) translated by (5,5) -> bounds start at x=15,y=15.
    assert(r2.bounds[0] > 14.5f && r2.bounds[0] < 15.5f);
}
