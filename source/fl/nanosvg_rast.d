/*
 * D transliteration of nanosvgrast.h (not the original distribution --
 * see the license notice below, required by its own clause 2).
 *
 * Original nanosvgrast.h:
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
 *   The polygon rasterization is heavily based on the stb_truetype
 *   rasterizer by Sean Barrett - http://nothings.org/
 *
 *   Modified by FLTK to support non-square X,Y axes scaling (added
 *   `nsvgRasterizeXY()`).
 *
 * This is a D transliteration -- per the notice above (clause 2), this is
 * plainly marked as an altered/derived version, not the original nanosvg
 * distribution.
 *
 * Ported for fldtk (a D port of FLTK): the rasterizer half of the same
 * nanosvg library `fl.nanosvg` (the parser half) ports -- see that
 * module's own top comment for why this is a "port it, own it" case
 * rather than a "which external library" decision. `fl.svg_image` is the
 * `Fl_SVG_Image` glue on top of both.
 *
 * Deliberate simplifications vs. the C original (allocation plumbing only
 * -- the scanline/active-edge-table algorithm itself, the fixed-point
 * math, and the stroke join/cap geometry are ported faithfully, unchanged):
 *  - The `NSVGmemPage` bump-allocator + `NSVGactiveEdge` freelist exist
 *    purely to dodge `malloc()` churn for one C struct type. Under the GC
 *    this collapses to plain `new NsvgActiveEdge()` per edge -- no pool,
 *    no freelist, no `resetPool()`/`nsvg__alloc()` equivalents needed.
 *  - Growable arrays (`edges`, `points`, `points2`, `scanline`) are D
 *    dynamic arrays (`~=`, `.length = 0` to reset) instead of manual
 *    `realloc()` capacity tracking.
 *  - `qsort(r->edges, ..., nsvg__cmpEdge)` becomes `std.algorithm.sorting.
 *    sort` on the same D array -- same comparison, same "only y0 order
 *    matters, ties are broken by the scanline algorithm regardless"
 *    property FLTK itself relies on, so sort stability differences
 *    (if any) don't change the result.
 *  - The destination pixel buffer is a `ubyte[]` slice with explicit
 *    index arithmetic instead of raw `unsigned char*` pointer walking --
 *    same memory layout (4 bytes/pixel RGBA, `stride` bytes/row), just
 *    bounds-checked D array indexing instead of C pointer increments.
 *  - `nsvgCreateRasterizer()`/`nsvgDeleteRasterizer()` become a plain
 *    `NsvgRasterizer` class constructor -- no manual `free()`-walk needed
 *    under the GC (matches `fl.nanosvg`'s own `nsvgDelete()` gap note).
 */
module fl.nanosvg_rast;

import fl.nanosvg : NsvgImage, NsvgShape, NsvgPath, NsvgPaint, NsvgPaintType,
    NsvgGradient, NsvgFillRule, NsvgLineJoin, NsvgLineCap, NsvgFlags;
import std.algorithm.sorting : sort;
import std.algorithm.comparison : min, max;
import std.math : sqrt, sin, cos, atan2, acos, ceil, floor, fmod, PI;

private float absf(float x) { return x < 0 ? -x : x; }
private float roundf(float x) { return (x >= 0) ? floor(x + 0.5f) : ceil(x - 0.5f); }
private float clampf(float a, float mn, float mx) { return a < mn ? mn : (a > mx ? mx : a); }

private enum NSVG_PI = 3.14159265358979323846264338327f;
private enum NSVG__SUBSAMPLES = 5;
private enum NSVG__FIXSHIFT = 10;
private enum NSVG__FIX = 1 << NSVG__FIXSHIFT;
private enum NSVG__FIXMASK = NSVG__FIX - 1;

private struct NsvgEdge
{
    float x0 = 0, y0 = 0, x1 = 0, y1 = 0;
    int dir;
}

private struct NsvgPoint
{
    float x = 0, y = 0;
    float dx = 0, dy = 0;
    float len = 0;
    float dmx = 0, dmy = 0;
    ubyte flags;
}

private enum PointFlags : ubyte
{
    corner = 0x01,
    bevel = 0x02,
    left = 0x04,
}

private final class NsvgActiveEdge
{
    int x, dx;
    float ey = 0;
    int dir;
    NsvgActiveEdge next;
}

private struct NsvgCachedPaint
{
    NsvgPaintType type;
    ubyte spread;
    float[6] xform = [1, 0, 0, 1, 0, 0];
    uint[256] colors;
}

/// Ported from `NSVGrasterizer` -- reusable rasterization context (holds
/// scratch buffers only; create once, call `rasterize()` for as many
/// images as needed, matching FLTK's own usage note).
final class NsvgRasterizer
{
    private float tessTol = 0.25f;
    private float distTol = 0.01f;

    private NsvgEdge[] edges;
    private NsvgPoint[] points;
    private NsvgPoint[] points2;
    private ubyte[] scanline;

    private ubyte[] bitmap;
    private int width, height, stride;

    private bool ptEquals(float x1, float y1, float x2, float y2, float tol)
    {
        float dx = x2 - x1, dy = y2 - y1;
        return dx * dx + dy * dy < tol * tol;
    }

    private void addPathPoint(float x, float y, ubyte flags)
    {
        if (points.length > 0)
        {
            auto pt = &points[$ - 1];
            if (ptEquals(pt.x, pt.y, x, y, distTol))
            {
                pt.flags |= flags;
                return;
            }
        }
        NsvgPoint pt;
        pt.x = x; pt.y = y; pt.flags = flags;
        points ~= pt;
    }

    private void appendPathPoint(NsvgPoint pt) { points ~= pt; }

    private void duplicatePoints() { points2 = points.dup; }

    private void addEdge(float x0, float y0, float x1, float y1)
    {
        if (y0 == y1) return; // skip horizontal edges

        NsvgEdge e;
        if (y0 < y1)
        {
            e.x0 = x0; e.y0 = y0; e.x1 = x1; e.y1 = y1; e.dir = 1;
        }
        else
        {
            e.x0 = x1; e.y0 = y1; e.x1 = x0; e.y1 = y0; e.dir = -1;
        }
        edges ~= e;
    }

    private static float normalize(ref float x, ref float y)
    {
        float d = sqrt(x * x + y * y);
        if (d > 1e-6f)
        {
            float id = 1.0f / d;
            x *= id;
            y *= id;
        }
        return d;
    }

    private void flattenCubicBez(float x1, float y1, float x2, float y2,
            float x3, float y3, float x4, float y4, int level, ubyte type)
    {
        if (level > 10) return;

        float x12 = (x1 + x2) * 0.5f, y12 = (y1 + y2) * 0.5f;
        float x23 = (x2 + x3) * 0.5f, y23 = (y2 + y3) * 0.5f;
        float x34 = (x3 + x4) * 0.5f, y34 = (y3 + y4) * 0.5f;
        float x123 = (x12 + x23) * 0.5f, y123 = (y12 + y23) * 0.5f;

        float dx = x4 - x1, dy = y4 - y1;
        float d2 = absf((x2 - x4) * dy - (y2 - y4) * dx);
        float d3 = absf((x3 - x4) * dy - (y3 - y4) * dx);

        if ((d2 + d3) * (d2 + d3) < tessTol * (dx * dx + dy * dy))
        {
            addPathPoint(x4, y4, type);
            return;
        }

        float x234 = (x23 + x34) * 0.5f, y234 = (y23 + y34) * 0.5f;
        float x1234 = (x123 + x234) * 0.5f, y1234 = (y123 + y234) * 0.5f;

        flattenCubicBez(x1, y1, x12, y12, x123, y123, x1234, y1234, level + 1, 0);
        flattenCubicBez(x1234, y1234, x234, y234, x34, y34, x4, y4, level + 1, type);
    }

    private void flattenShape(NsvgShape shape, float sx, float sy)
    {
        for (auto path = shape.paths; path !is null; path = path.next)
        {
            points.length = 0;
            addPathPoint(path.pts[0] * sx, path.pts[1] * sy, 0);
            for (int i = 0; i < cast(int)(path.pts.length / 2) - 1; i += 3)
            {
                auto p = path.pts[i * 2 .. i * 2 + 8];
                flattenCubicBez(p[0] * sx, p[1] * sy, p[2] * sx, p[3] * sy,
                        p[4] * sx, p[5] * sy, p[6] * sx, p[7] * sy, 0, 0);
            }
            addPathPoint(path.pts[0] * sx, path.pts[1] * sy, 0);
            for (size_t i = 0, j = points.length - 1; i < points.length; j = i++)
                addEdge(points[j].x, points[j].y, points[i].x, points[i].y);
        }
    }

    // -- stroke expansion: joins, caps, dashing --------------------------

    private void initClosed(ref NsvgPoint left, ref NsvgPoint right, NsvgPoint* p0, NsvgPoint* p1, float lineWidth)
    {
        float w = lineWidth * 0.5f;
        float dx = p1.x - p0.x, dy = p1.y - p0.y;
        float len = normalize(dx, dy);
        float px = p0.x + dx * len * 0.5f, py = p0.y + dy * len * 0.5f;
        float dlx = dy, dly = -dx;
        left.x = px - dlx * w; left.y = py - dly * w;
        right.x = px + dlx * w; right.y = py + dly * w;
    }

    private void buttCap(ref NsvgPoint left, ref NsvgPoint right, NsvgPoint* p, float dx, float dy, float lineWidth, bool connect)
    {
        float w = lineWidth * 0.5f;
        float px = p.x, py = p.y;
        float dlx = dy, dly = -dx;
        float lx = px - dlx * w, ly = py - dly * w;
        float rx = px + dlx * w, ry = py + dly * w;

        addEdge(lx, ly, rx, ry);

        if (connect)
        {
            addEdge(left.x, left.y, lx, ly);
            addEdge(rx, ry, right.x, right.y);
        }
        left.x = lx; left.y = ly;
        right.x = rx; right.y = ry;
    }

    private void squareCap(ref NsvgPoint left, ref NsvgPoint right, NsvgPoint* p, float dx, float dy, float lineWidth, bool connect)
    {
        float w = lineWidth * 0.5f;
        float px = p.x - dx * w, py = p.y - dy * w;
        float dlx = dy, dly = -dx;
        float lx = px - dlx * w, ly = py - dly * w;
        float rx = px + dlx * w, ry = py + dly * w;

        addEdge(lx, ly, rx, ry);

        if (connect)
        {
            addEdge(left.x, left.y, lx, ly);
            addEdge(rx, ry, right.x, right.y);
        }
        left.x = lx; left.y = ly;
        right.x = rx; right.y = ry;
    }

    private void roundCap(ref NsvgPoint left, ref NsvgPoint right, NsvgPoint* p, float dx, float dy, float lineWidth, int ncap, bool connect)
    {
        float w = lineWidth * 0.5f;
        float px = p.x, py = p.y;
        float dlx = dy, dly = -dx;
        float lx = 0, ly = 0, rx = 0, ry = 0, prevx = 0, prevy = 0;

        for (int i = 0; i < ncap; i++)
        {
            float a = cast(float) i / cast(float)(ncap - 1) * NSVG_PI;
            float ax = cos(a) * w, ay = sin(a) * w;
            float x = px - dlx * ax - dx * ay;
            float y = py - dly * ax - dy * ay;

            if (i > 0) addEdge(prevx, prevy, x, y);

            prevx = x; prevy = y;

            if (i == 0) { lx = x; ly = y; }
            else if (i == ncap - 1) { rx = x; ry = y; }
        }

        if (connect)
        {
            addEdge(left.x, left.y, lx, ly);
            addEdge(rx, ry, right.x, right.y);
        }

        left.x = lx; left.y = ly;
        right.x = rx; right.y = ry;
    }

    private void bevelJoin(ref NsvgPoint left, ref NsvgPoint right, NsvgPoint* p0, NsvgPoint* p1, float lineWidth)
    {
        float w = lineWidth * 0.5f;
        float dlx0 = p0.dy, dly0 = -p0.dx;
        float dlx1 = p1.dy, dly1 = -p1.dx;
        float lx0 = p1.x - dlx0 * w, ly0 = p1.y - dly0 * w;
        float rx0 = p1.x + dlx0 * w, ry0 = p1.y + dly0 * w;
        float lx1 = p1.x - dlx1 * w, ly1 = p1.y - dly1 * w;
        float rx1 = p1.x + dlx1 * w, ry1 = p1.y + dly1 * w;

        addEdge(lx0, ly0, left.x, left.y);
        addEdge(lx1, ly1, lx0, ly0);

        addEdge(right.x, right.y, rx0, ry0);
        addEdge(rx0, ry0, rx1, ry1);

        left.x = lx1; left.y = ly1;
        right.x = rx1; right.y = ry1;
    }

    private void miterJoin(ref NsvgPoint left, ref NsvgPoint right, NsvgPoint* p0, NsvgPoint* p1, float lineWidth)
    {
        float w = lineWidth * 0.5f;
        float dlx0 = p0.dy, dly0 = -p0.dx;
        float dlx1 = p1.dy, dly1 = -p1.dx;
        float lx0, rx0, lx1, rx1, ly0, ry0, ly1, ry1;

        if (p1.flags & PointFlags.left)
        {
            lx0 = lx1 = p1.x - p1.dmx * w;
            ly0 = ly1 = p1.y - p1.dmy * w;
            addEdge(lx1, ly1, left.x, left.y);

            rx0 = p1.x + dlx0 * w; ry0 = p1.y + dly0 * w;
            rx1 = p1.x + dlx1 * w; ry1 = p1.y + dly1 * w;
            addEdge(right.x, right.y, rx0, ry0);
            addEdge(rx0, ry0, rx1, ry1);
        }
        else
        {
            lx0 = p1.x - dlx0 * w; ly0 = p1.y - dly0 * w;
            lx1 = p1.x - dlx1 * w; ly1 = p1.y - dly1 * w;
            addEdge(lx0, ly0, left.x, left.y);
            addEdge(lx1, ly1, lx0, ly0);

            rx0 = rx1 = p1.x + p1.dmx * w;
            ry0 = ry1 = p1.y + p1.dmy * w;
            addEdge(right.x, right.y, rx1, ry1);
        }

        left.x = lx1; left.y = ly1;
        right.x = rx1; right.y = ry1;
    }

    private void roundJoin(ref NsvgPoint left, ref NsvgPoint right, NsvgPoint* p0, NsvgPoint* p1, float lineWidth, int ncap)
    {
        float w = lineWidth * 0.5f;
        float dlx0 = p0.dy, dly0 = -p0.dx;
        float dlx1 = p1.dy, dly1 = -p1.dx;
        float a0 = atan2(dly0, dlx0);
        float a1 = atan2(dly1, dlx1);
        float da = a1 - a0;

        if (da < NSVG_PI) da += NSVG_PI * 2;
        if (da > NSVG_PI) da -= NSVG_PI * 2;

        int n = cast(int) ceil((absf(da) / NSVG_PI) * ncap);
        if (n < 2) n = 2;
        if (n > ncap) n = ncap;

        float lx = left.x, ly = left.y, rx = right.x, ry = right.y;

        for (int i = 0; i < n; i++)
        {
            float u = cast(float) i / cast(float)(n - 1);
            float a = a0 + u * da;
            float ax = cos(a) * w, ay = sin(a) * w;
            float lx1 = p1.x - ax, ly1 = p1.y - ay;
            float rx1 = p1.x + ax, ry1 = p1.y + ay;

            addEdge(lx1, ly1, lx, ly);
            addEdge(rx, ry, rx1, ry1);

            lx = lx1; ly = ly1;
            rx = rx1; ry = ry1;
        }

        left.x = lx; left.y = ly;
        right.x = rx; right.y = ry;
    }

    private void straightJoin(ref NsvgPoint left, ref NsvgPoint right, NsvgPoint* p1, float lineWidth)
    {
        float w = lineWidth * 0.5f;
        float lx = p1.x - p1.dmx * w, ly = p1.y - p1.dmy * w;
        float rx = p1.x + p1.dmx * w, ry = p1.y + p1.dmy * w;

        addEdge(lx, ly, left.x, left.y);
        addEdge(right.x, right.y, rx, ry);

        left.x = lx; left.y = ly;
        right.x = rx; right.y = ry;
    }

    private int curveDivs(float r, float arc, float tol)
    {
        float da = acos(r / (r + tol)) * 2.0f;
        int divs = cast(int) ceil(arc / da);
        if (divs < 2) divs = 2;
        return divs;
    }

    private void expandStroke(NsvgPoint[] pts, bool closed, NsvgLineJoin lineJoin, NsvgLineCap lineCap, float lineWidth)
    {
        int ncap = curveDivs(lineWidth * 0.5f, NSVG_PI, tessTol);
        NsvgPoint left, right, firstLeft, firstRight;
        NsvgPoint* p0, p1;
        int s, e;

        if (closed)
        {
            p0 = &pts[$ - 1];
            p1 = &pts[0];
            s = 0;
            e = cast(int) pts.length;
        }
        else
        {
            p0 = &pts[0];
            p1 = &pts[1];
            s = 1;
            e = cast(int) pts.length - 1;
        }

        if (closed)
        {
            initClosed(left, right, p0, p1, lineWidth);
            firstLeft = left;
            firstRight = right;
        }
        else
        {
            float dx = p1.x - p0.x, dy = p1.y - p0.y;
            normalize(dx, dy);
            final switch (lineCap)
            {
            case NsvgLineCap.butt: buttCap(left, right, p0, dx, dy, lineWidth, false); break;
            case NsvgLineCap.square: squareCap(left, right, p0, dx, dy, lineWidth, false); break;
            case NsvgLineCap.round: roundCap(left, right, p0, dx, dy, lineWidth, ncap, false); break;
            }
        }

        for (int j = s; j < e; j++)
        {
            if (p1.flags & PointFlags.corner)
            {
                if (lineJoin == NsvgLineJoin.round)
                    roundJoin(left, right, p0, p1, lineWidth, ncap);
                else if (lineJoin == NsvgLineJoin.bevel || (p1.flags & PointFlags.bevel))
                    bevelJoin(left, right, p0, p1, lineWidth);
                else
                    miterJoin(left, right, p0, p1, lineWidth);
            }
            else
                straightJoin(left, right, p1, lineWidth);
            p0 = p1;
            p1 = (j + 1 < pts.length) ? &pts[j + 1] : p1;
        }

        if (closed)
        {
            addEdge(firstLeft.x, firstLeft.y, left.x, left.y);
            addEdge(right.x, right.y, firstRight.x, firstRight.y);
        }
        else
        {
            float dx = p1.x - p0.x, dy = p1.y - p0.y;
            normalize(dx, dy);
            final switch (lineCap)
            {
            case NsvgLineCap.butt: buttCap(right, left, p1, -dx, -dy, lineWidth, true); break;
            case NsvgLineCap.square: squareCap(right, left, p1, -dx, -dy, lineWidth, true); break;
            case NsvgLineCap.round: roundCap(right, left, p1, -dx, -dy, lineWidth, ncap, true); break;
            }
        }
    }

    private void prepareStroke(float miterLimit, NsvgLineJoin lineJoin)
    {
        NsvgPoint* p0 = &points[$ - 1];
        NsvgPoint* p1 = &points[0];
        for (size_t i = 0; i < points.length; i++)
        {
            p0.dx = p1.x - p0.x;
            p0.dy = p1.y - p0.y;
            p0.len = normalize(p0.dx, p0.dy);
            p0 = p1;
            p1 = (i + 1 < points.length) ? &points[i + 1] : p1;
        }

        p0 = &points[$ - 1];
        p1 = &points[0];
        for (size_t j = 0; j < points.length; j++)
        {
            float dlx0 = p0.dy, dly0 = -p0.dx;
            float dlx1 = p1.dy, dly1 = -p1.dx;
            p1.dmx = (dlx0 + dlx1) * 0.5f;
            p1.dmy = (dly0 + dly1) * 0.5f;
            float dmr2 = p1.dmx * p1.dmx + p1.dmy * p1.dmy;
            if (dmr2 > 0.000001f)
            {
                float s2 = 1.0f / dmr2;
                if (s2 > 600.0f) s2 = 600.0f;
                p1.dmx *= s2;
                p1.dmy *= s2;
            }

            p1.flags = (p1.flags & PointFlags.corner) ? PointFlags.corner : 0;

            float cross = p1.dx * p0.dy - p0.dx * p1.dy;
            if (cross > 0.0f) p1.flags |= PointFlags.left;

            if (p1.flags & PointFlags.corner)
            {
                if ((dmr2 * miterLimit * miterLimit) < 1.0f
                        || lineJoin == NsvgLineJoin.bevel || lineJoin == NsvgLineJoin.round)
                    p1.flags |= PointFlags.bevel;
            }

            p0 = p1;
            p1 = (j + 1 < points.length) ? &points[j + 1] : p1;
        }
    }

    private void flattenShapeStroke(NsvgShape shape, float sx, float sy)
    {
        float miterLimit = shape.miterLimit;
        auto lineJoin = shape.strokeLineJoin;
        auto lineCap = shape.strokeLineCap;
        float sw = (sx + sy) / 2;
        float lineWidth = shape.strokeWidth * sw;

        for (auto path = shape.paths; path !is null; path = path.next)
        {
            points.length = 0;
            addPathPoint(path.pts[0] * sx, path.pts[1] * sy, PointFlags.corner);
            for (int i = 0; i < cast(int)(path.pts.length / 2) - 1; i += 3)
            {
                auto p = path.pts[i * 2 .. i * 2 + 8];
                flattenCubicBez(p[0] * sx, p[1] * sy, p[2] * sx, p[3] * sy,
                        p[4] * sx, p[5] * sy, p[6] * sx, p[7] * sy, 0, PointFlags.corner);
            }
            if (points.length < 2) continue;

            bool closed = path.closed;

            if (ptEquals(points[$ - 1].x, points[$ - 1].y, points[0].x, points[0].y, distTol))
            {
                points.length--;
                closed = true;
            }

            if (shape.strokeDashCount > 0)
            {
                int idash = 0;
                bool dashState = true;
                float totalDist = 0;

                if (closed) appendPathPoint(points[0]);

                duplicatePoints();

                points.length = 0;
                NsvgPoint cur = points2[0];
                appendPathPoint(cur);

                float allDashLen = 0;
                for (int j = 0; j < shape.strokeDashCount; j++)
                    allDashLen += shape.strokeDashArray[j];
                if (shape.strokeDashCount & 1) allDashLen *= 2.0f;
                float dashOffset = fmod(shape.strokeDashOffset, allDashLen);
                if (dashOffset < 0.0f) dashOffset += allDashLen;

                while (dashOffset > shape.strokeDashArray[idash])
                {
                    dashOffset -= shape.strokeDashArray[idash];
                    idash = (idash + 1) % shape.strokeDashCount;
                }
                float dashLen = (shape.strokeDashArray[idash] - dashOffset) * sw;

                size_t j = 1;
                while (j < points2.length)
                {
                    float dx = points2[j].x - cur.x;
                    float dy = points2[j].y - cur.y;
                    float dist = sqrt(dx * dx + dy * dy);

                    if ((totalDist + dist) > dashLen)
                    {
                        float d = (dashLen - totalDist) / dist;
                        float x = cur.x + dx * d;
                        float y = cur.y + dy * d;
                        addPathPoint(x, y, PointFlags.corner);

                        if (points.length > 1 && dashState)
                        {
                            prepareStroke(miterLimit, lineJoin);
                            expandStroke(points, false, lineJoin, lineCap, lineWidth);
                        }
                        dashState = !dashState;
                        idash = (idash + 1) % shape.strokeDashCount;
                        dashLen = shape.strokeDashArray[idash] * sw;
                        cur.x = x; cur.y = y; cur.flags = PointFlags.corner;
                        totalDist = 0.0f;
                        points.length = 0;
                        appendPathPoint(cur);
                    }
                    else
                    {
                        totalDist += dist;
                        cur = points2[j];
                        appendPathPoint(cur);
                        j++;
                    }
                }
                if (points.length > 1 && dashState)
                    expandStroke(points, false, lineJoin, lineCap, lineWidth);
            }
            else
            {
                prepareStroke(miterLimit, lineJoin);
                expandStroke(points, closed, lineJoin, lineCap, lineWidth);
            }
        }
    }

    // -- scanline fill ----------------------------------------------------

    private NsvgActiveEdge addActive(ref NsvgEdge e, float startPoint)
    {
        auto z = new NsvgActiveEdge();
        float dxdy = (e.x1 - e.x0) / (e.y1 - e.y0);
        if (dxdy < 0)
            z.dx = cast(int)(-roundf(NSVG__FIX * -dxdy));
        else
            z.dx = cast(int) roundf(NSVG__FIX * dxdy);
        z.x = cast(int) roundf(NSVG__FIX * (e.x0 + dxdy * (startPoint - e.y0)));
        z.ey = e.y1;
        z.next = null;
        z.dir = e.dir;
        return z;
    }

    private static void fillScanline(ubyte[] scanline, int len, int x0, int x1, int maxWeight, ref int xmin, ref int xmax)
    {
        int i = x0 >> NSVG__FIXSHIFT;
        int j = x1 >> NSVG__FIXSHIFT;
        if (i < xmin) xmin = i;
        if (j > xmax) xmax = j;
        if (i < len && j >= 0)
        {
            if (i == j)
            {
                scanline[i] = cast(ubyte)(scanline[i] + ((x1 - x0) * maxWeight >> NSVG__FIXSHIFT));
            }
            else
            {
                if (i >= 0)
                    scanline[i] = cast(ubyte)(scanline[i] + (((NSVG__FIX - (x0 & NSVG__FIXMASK)) * maxWeight) >> NSVG__FIXSHIFT));
                else
                    i = -1;

                if (j < len)
                    scanline[j] = cast(ubyte)(scanline[j] + (((x1 & NSVG__FIXMASK) * maxWeight) >> NSVG__FIXSHIFT));
                else
                    j = len;

                for (++i; i < j; ++i)
                    scanline[i] = cast(ubyte)(scanline[i] + maxWeight);
            }
        }
    }

    private static void fillActiveEdges(ubyte[] scanline, int len, NsvgActiveEdge e, int maxWeight, ref int xmin, ref int xmax, NsvgFillRule fillRule)
    {
        int x0 = 0, w = 0;

        if (fillRule == NsvgFillRule.nonzero)
        {
            while (e !is null)
            {
                if (w == 0) { x0 = e.x; w += e.dir; }
                else
                {
                    int x1 = e.x; w += e.dir;
                    if (w == 0) fillScanline(scanline, len, x0, x1, maxWeight, xmin, xmax);
                }
                e = e.next;
            }
        }
        else if (fillRule == NsvgFillRule.evenodd)
        {
            while (e !is null)
            {
                if (w == 0) { x0 = e.x; w = 1; }
                else
                {
                    int x1 = e.x; w = 0;
                    fillScanline(scanline, len, x0, x1, maxWeight, xmin, xmax);
                }
                e = e.next;
            }
        }
    }

    private static uint packRGBA(ubyte r, ubyte g, ubyte b, ubyte a)
    {
        return cast(uint) r | (cast(uint) g << 8) | (cast(uint) b << 16) | (cast(uint) a << 24);
    }

    private static uint lerpRGBA(uint c0, uint c1, float u)
    {
        int iu = cast(int)(clampf(u, 0.0f, 1.0f) * 256.0f);
        int r = ((c0 & 0xff) * (256 - iu) + ((c1 & 0xff) * iu)) >> 8;
        int g = (((c0 >> 8) & 0xff) * (256 - iu) + (((c1 >> 8) & 0xff) * iu)) >> 8;
        int b = (((c0 >> 16) & 0xff) * (256 - iu) + (((c1 >> 16) & 0xff) * iu)) >> 8;
        int a = (((c0 >> 24) & 0xff) * (256 - iu) + (((c1 >> 24) & 0xff) * iu)) >> 8;
        return packRGBA(cast(ubyte) r, cast(ubyte) g, cast(ubyte) b, cast(ubyte) a);
    }

    private static uint applyOpacity(uint c, float u)
    {
        int iu = cast(int)(clampf(u, 0.0f, 1.0f) * 256.0f);
        int r = c & 0xff;
        int g = (c >> 8) & 0xff;
        int b = (c >> 16) & 0xff;
        int a = (((c >> 24) & 0xff) * iu) >> 8;
        return packRGBA(cast(ubyte) r, cast(ubyte) g, cast(ubyte) b, cast(ubyte) a);
    }

    private static int div255(int x) { return ((x + 1) * 257) >> 16; }

    private void scanlineSolid(ubyte[] dst, size_t dstOff, int count, ubyte[] cover, size_t coverOff,
            int x, int y, float tx, float ty, float sx, float sy, ref NsvgCachedPaint cache)
    {
        if (cache.type == NsvgPaintType.color)
        {
            int cr = cache.colors[0] & 0xff;
            int cg = (cache.colors[0] >> 8) & 0xff;
            int cb = (cache.colors[0] >> 16) & 0xff;
            int ca = (cache.colors[0] >> 24) & 0xff;

            for (int i = 0; i < count; i++)
            {
                int a = div255(cast(int) cover[coverOff] * ca);
                int ia = 255 - a;
                int r = div255(cr * a);
                int g = div255(cg * a);
                int b = div255(cb * a);

                r += div255(ia * cast(int) dst[dstOff + 0]);
                g += div255(ia * cast(int) dst[dstOff + 1]);
                b += div255(ia * cast(int) dst[dstOff + 2]);
                a += div255(ia * cast(int) dst[dstOff + 3]);

                dst[dstOff + 0] = cast(ubyte) r;
                dst[dstOff + 1] = cast(ubyte) g;
                dst[dstOff + 2] = cast(ubyte) b;
                dst[dstOff + 3] = cast(ubyte) a;

                coverOff++;
                dstOff += 4;
            }
        }
        else if (cache.type == NsvgPaintType.linearGradient)
        {
            float[6] t = cache.xform;
            float fx = (x - tx) / sx;
            float fy = (y - ty) / sy;
            float dx = 1.0f / sx;

            for (int i = 0; i < count; i++)
            {
                float gy = fx * t[1] + fy * t[3] + t[5];
                uint c = cache.colors[cast(int) clampf(gy * 255.0f, 0, 255.0f)];
                int cr = c & 0xff, cg = (c >> 8) & 0xff, cb = (c >> 16) & 0xff, ca = (c >> 24) & 0xff;

                int a = div255(cast(int) cover[coverOff] * ca);
                int ia = 255 - a;
                int r = div255(cr * a);
                int g = div255(cg * a);
                int b = div255(cb * a);

                r += div255(ia * cast(int) dst[dstOff + 0]);
                g += div255(ia * cast(int) dst[dstOff + 1]);
                b += div255(ia * cast(int) dst[dstOff + 2]);
                a += div255(ia * cast(int) dst[dstOff + 3]);

                dst[dstOff + 0] = cast(ubyte) r;
                dst[dstOff + 1] = cast(ubyte) g;
                dst[dstOff + 2] = cast(ubyte) b;
                dst[dstOff + 3] = cast(ubyte) a;

                coverOff++;
                dstOff += 4;
                fx += dx;
            }
        }
        else if (cache.type == NsvgPaintType.radialGradient)
        {
            float[6] t = cache.xform;
            float fx = (x - tx) / sx;
            float fy = (y - ty) / sy;
            float dx = 1.0f / sx;

            for (int i = 0; i < count; i++)
            {
                float gx = fx * t[0] + fy * t[2] + t[4];
                float gy = fx * t[1] + fy * t[3] + t[5];
                float gd = sqrt(gx * gx + gy * gy);
                uint c = cache.colors[cast(int) clampf(gd * 255.0f, 0, 255.0f)];
                int cr = c & 0xff, cg = (c >> 8) & 0xff, cb = (c >> 16) & 0xff, ca = (c >> 24) & 0xff;

                int a = div255(cast(int) cover[coverOff] * ca);
                int ia = 255 - a;
                int r = div255(cr * a);
                int g = div255(cg * a);
                int b = div255(cb * a);

                r += div255(ia * cast(int) dst[dstOff + 0]);
                g += div255(ia * cast(int) dst[dstOff + 1]);
                b += div255(ia * cast(int) dst[dstOff + 2]);
                a += div255(ia * cast(int) dst[dstOff + 3]);

                dst[dstOff + 0] = cast(ubyte) r;
                dst[dstOff + 1] = cast(ubyte) g;
                dst[dstOff + 2] = cast(ubyte) b;
                dst[dstOff + 3] = cast(ubyte) a;

                coverOff++;
                dstOff += 4;
                fx += dx;
            }
        }
    }

    private void rasterizeSortedEdges(float tx, float ty, float sx, float sy, ref NsvgCachedPaint cache, NsvgFillRule fillRule)
    {
        NsvgActiveEdge active = null;
        int e = 0;
        int maxWeight = 255 / NSVG__SUBSAMPLES;

        for (int y = 0; y < height; y++)
        {
            scanline[] = 0;
            int xmin = width, xmax = 0;
            for (int s = 0; s < NSVG__SUBSAMPLES; s++)
            {
                float scany = (y * NSVG__SUBSAMPLES + s) + 0.5f;

                // Remove edges that end before this scanline's center; advance the rest.
                NsvgActiveEdge* step = &active;
                while (*step !is null)
                {
                    auto z = *step;
                    if (z.ey <= scany)
                        *step = z.next;
                    else
                    {
                        z.x += z.dx;
                        step = &(*step).next;
                    }
                }

                // Insertion-sort the active list by x (bubble pass to fixed point, matching FLTK).
                for (;;)
                {
                    bool changed = false;
                    step = &active;
                    while (*step !is null && (*step).next !is null)
                    {
                        if ((*step).x > (*step).next.x)
                        {
                            auto t = *step;
                            auto q = t.next;
                            t.next = q.next;
                            q.next = t;
                            *step = q;
                            changed = true;
                        }
                        step = &(*step).next;
                    }
                    if (!changed) break;
                }

                // Insert edges that start before this scanline's center.
                while (e < edges.length && edges[e].y0 <= scany)
                {
                    if (edges[e].y1 > scany)
                    {
                        auto z = addActive(edges[e], scany);
                        if (active is null)
                            active = z;
                        else if (z.x < active.x)
                        {
                            z.next = active;
                            active = z;
                        }
                        else
                        {
                            auto p = active;
                            while (p.next !is null && p.next.x < z.x) p = p.next;
                            z.next = p.next;
                            p.next = z;
                        }
                    }
                    e++;
                }

                if (active !is null)
                    fillActiveEdges(scanline, width, active, maxWeight, xmin, xmax, fillRule);
            }

            if (xmin < 0) xmin = 0;
            if (xmax > width - 1) xmax = width - 1;
            if (xmin <= xmax)
                scanlineSolid(bitmap, cast(size_t)(y * stride + xmin * 4), xmax - xmin + 1,
                        scanline, cast(size_t) xmin, xmin, y, tx, ty, sx, sy, cache);
        }
    }

    private static void unpremultiplyAlpha(ubyte[] image, int w, int h, int stride)
    {
        for (int y = 0; y < h; y++)
        {
            size_t row = cast(size_t) y * stride;
            for (int x = 0; x < w; x++)
            {
                int r = image[row], g = image[row + 1], b = image[row + 2], a = image[row + 3];
                if (a != 0)
                {
                    image[row] = cast(ubyte)(r * 255 / a);
                    image[row + 1] = cast(ubyte)(g * 255 / a);
                    image[row + 2] = cast(ubyte)(b * 255 / a);
                }
                row += 4;
            }
        }

        for (int y = 0; y < h; y++)
        {
            size_t row = cast(size_t) y * stride;
            for (int x = 0; x < w; x++)
            {
                int r = 0, g = 0, b = 0, n = 0;
                int a = image[row + 3];
                if (a == 0)
                {
                    if (x - 1 > 0 && image[row - 1] != 0)
                    {
                        r += image[row - 4]; g += image[row - 3]; b += image[row - 2]; n++;
                    }
                    if (x + 1 < w && image[row + 7] != 0)
                    {
                        r += image[row + 4]; g += image[row + 5]; b += image[row + 6]; n++;
                    }
                    if (y - 1 > 0 && image[row - stride + 3] != 0)
                    {
                        r += image[row - stride]; g += image[row - stride + 1]; b += image[row - stride + 2]; n++;
                    }
                    if (y + 1 < h && image[row + stride + 3] != 0)
                    {
                        r += image[row + stride]; g += image[row + stride + 1]; b += image[row + stride + 2]; n++;
                    }
                    if (n > 0)
                    {
                        image[row] = cast(ubyte)(r / n);
                        image[row + 1] = cast(ubyte)(g / n);
                        image[row + 2] = cast(ubyte)(b / n);
                    }
                }
                row += 4;
            }
        }
    }

    private void initPaint(ref NsvgCachedPaint cache, ref NsvgPaint paint, float opacity)
    {
        cache.type = paint.type;

        if (paint.type == NsvgPaintType.color)
        {
            cache.colors[0] = applyOpacity(paint.color, opacity);
            return;
        }

        auto grad = paint.gradient;
        cache.xform = grad.xform;

        auto stops = grad.stops;
        if (stops.length == 0)
        {
            cache.colors[] = 0;
        }
        else if (stops.length == 1)
        {
            // FLTK's own `nstops == 1` branch is `for (i = 0; i < 256;
            // i++) cache->colors[i] = nsvg__applyOpacity(grad->stops[i].color,
            // opacity);` -- reading `stops[i]` for i up to 255 when the
            // array holds exactly 1 element, a real out-of-bounds C read
            // (filed as an FLTK_ISSUES.md candidate). A literal
            // transliteration would be a D `RangeError` on every one-stop
            // gradient, not a faithfully-reproduced quirk -- this is the
            // one deliberate correction in this port's nanosvg transliteration
            // (everywhere else, faithfully-reproduced-not-fixed is the
            // rule): `stops[0]` for every entry, which is what the *first*
            // iteration of FLTK's own out-of-bounds loop would have
            // read anyway before it wandered into adjacent heap memory.
            foreach (ref c; cache.colors) c = applyOpacity(stops[0].color, opacity);
        }
        else
        {
            uint ca = applyOpacity(stops[0].color, opacity);
            uint cb = 0;
            float ua = clampf(stops[0].offset, 0, 1);
            float ub = clampf(stops[$ - 1].offset, ua, 1);
            int ia = cast(int)(ua * 255.0f);
            int ib = cast(int)(ub * 255.0f);
            for (int i = 0; i < ia; i++) cache.colors[i] = ca;

            for (size_t i = 0; i + 1 < stops.length; i++)
            {
                ca = applyOpacity(stops[i].color, opacity);
                cb = applyOpacity(stops[i + 1].color, opacity);
                ua = clampf(stops[i].offset, 0, 1);
                ub = clampf(stops[i + 1].offset, 0, 1);
                ia = cast(int)(ua * 255.0f);
                ib = cast(int)(ub * 255.0f);
                int count = ib - ia;
                if (count <= 0) continue;
                float u = 0;
                float du = 1.0f / count;
                for (int j = 0; j < count; j++)
                {
                    cache.colors[ia + j] = lerpRGBA(ca, cb, u);
                    u += du;
                }
            }

            for (int i = ib; i < 256; i++) cache.colors[i] = cb;
        }
    }

    /// Ported from `nsvgRasterizeXY()` -- rasterizes `image` into `dst`
    /// (RGBA, non-premultiplied alpha, 4 bytes/pixel, `stride` bytes/row;
    /// must already be sized `h*stride` or larger). `tx`/`ty` offset the
    /// image after scaling; `sx`/`sy` scale the X/Y axes independently
    /// (FLTK's own addition over stock nanosvg, which only had the
    /// uniform-scale `nsvgRasterize()`/`rasterize()` below).
    void rasterizeXY(NsvgImage image, float tx, float ty, float sx, float sy,
            ubyte[] dst, int w, int h, int stride)
    {
        bitmap = dst;
        width = w;
        height = h;
        this.stride = stride;

        if (scanline.length < w) scanline.length = w;

        dst[] = 0;

        for (auto shape = image.shapes; shape !is null; shape = shape.next)
        {
            if (!(shape.flags & NsvgFlags.visible)) continue;

            if (shape.fill.type != NsvgPaintType.none)
            {
                edges.length = 0;

                flattenShape(shape, sx, sy);

                foreach (ref e; edges)
                {
                    e.x0 = tx + e.x0;
                    e.y0 = (ty + e.y0) * NSVG__SUBSAMPLES;
                    e.x1 = tx + e.x1;
                    e.y1 = (ty + e.y1) * NSVG__SUBSAMPLES;
                }

                if (edges.length != 0) sort!((a, b) => a.y0 < b.y0)(edges);

                NsvgCachedPaint cache;
                initPaint(cache, shape.fill, shape.opacity);

                rasterizeSortedEdges(tx, ty, sx, sy, cache, shape.fillRule);
            }
            if (shape.stroke.type != NsvgPaintType.none && (shape.strokeWidth * sx) > 0.01f)
            {
                edges.length = 0;

                flattenShapeStroke(shape, sx, sy);

                foreach (ref e; edges)
                {
                    e.x0 = tx + e.x0;
                    e.y0 = (ty + e.y0) * NSVG__SUBSAMPLES;
                    e.x1 = tx + e.x1;
                    e.y1 = (ty + e.y1) * NSVG__SUBSAMPLES;
                }

                if (edges.length != 0) sort!((a, b) => a.y0 < b.y0)(edges);

                NsvgCachedPaint cache;
                initPaint(cache, shape.stroke, shape.opacity);

                rasterizeSortedEdges(tx, ty, sx, sy, cache, NsvgFillRule.nonzero);
            }
        }

        unpremultiplyAlpha(dst, w, h, stride);

        bitmap = null;
        width = 0;
        height = 0;
        this.stride = 0;
    }

    /// Ported from `nsvgRasterize()` -- same as `rasterizeXY()` with a
    /// single uniform `scale` for both axes.
    void rasterize(NsvgImage image, float tx, float ty, float scale, ubyte[] dst, int w, int h, int stride)
    {
        rasterizeXY(image, tx, ty, scale, scale, dst, w, h, stride);
    }
}

unittest
{
    import fl.nanosvg : nsvgParse;

    // A single 10x10 fully-opaque red square, rasterized 1:1 -- verifies
    // the fill path (flatten -> edges -> scanline AA -> unpremultiply)
    // produces the exact expected solid color/alpha, and that pixels
    // outside the shape stay transparent.
    string svg = `<svg width="10" height="10"><rect x="0" y="0" width="10" height="10" fill="#ff0000"/></svg>`;
    auto buf = svg.dup;
    auto img = nsvgParse(buf, "px", 96);

    auto rast = new NsvgRasterizer();
    auto dst = new ubyte[10 * 10 * 4];
    rast.rasterize(img, 0, 0, 1.0f, dst, 10, 10, 10 * 4);

    // Center pixel (5,5): fully red, fully opaque.
    size_t off = (5 * 10 + 5) * 4;
    assert(dst[off + 0] == 255);
    assert(dst[off + 1] == 0);
    assert(dst[off + 2] == 0);
    assert(dst[off + 3] == 255);
}

unittest
{
    import fl.nanosvg : nsvgParse;

    // A small circle centered in a larger transparent canvas -- confirms
    // corners stay transparent (nothing drawn there) while the center is
    // opaque, and that antialiasing produces intermediate alpha somewhere
    // near the circle's edge (not a hard binary mask).
    string svg = `<svg width="20" height="20"><circle cx="10" cy="10" r="8" fill="#00ff00"/></svg>`;
    auto buf = svg.dup;
    auto img = nsvgParse(buf, "px", 96);

    auto rast = new NsvgRasterizer();
    auto dst = new ubyte[20 * 20 * 4];
    rast.rasterize(img, 0, 0, 1.0f, dst, 20, 20, 20 * 4);

    // Corner: untouched, fully transparent.
    assert(dst[3] == 0);

    // Center: opaque green.
    size_t centerOff = (10 * 20 + 10) * 4;
    assert(dst[centerOff + 1] == 255);
    assert(dst[centerOff + 3] == 255);

    // Somewhere along a horizontal scan through the circle's right edge
    // (x ~= 18, the r=8 boundary from cx=10) there should be at least one
    // partially-covered (antialiased) pixel, not just a hard 0/255 jump.
    bool foundPartial = false;
    for (int x = 15; x < 20; x++)
    {
        size_t o = (10 * 20 + x) * 4;
        if (dst[o + 3] > 0 && dst[o + 3] < 255) foundPartial = true;
    }
    assert(foundPartial);
}

unittest
{
    import fl.nanosvg : nsvgParse;

    // Stroke-only shape (no fill) -- exercises expandStroke()'s cap/join
    // path separately from the fill path above. A thick horizontal line
    // should paint a band of opaque pixels centered on y=10, and leave
    // pixels well above/below the line transparent.
    string svg = `<svg width="20" height="20"><line x1="2" y1="10" x2="18" y2="10" stroke="#0000ff" stroke-width="4"/></svg>`;
    auto buf = svg.dup;
    auto img = nsvgParse(buf, "px", 96);

    auto rast = new NsvgRasterizer();
    auto dst = new ubyte[20 * 20 * 4];
    rast.rasterize(img, 0, 0, 1.0f, dst, 20, 20, 20 * 4);

    size_t onLine = (10 * 20 + 10) * 4;
    assert(dst[onLine + 2] == 255); // blue channel
    assert(dst[onLine + 3] == 255);

    size_t farAbove = (1 * 20 + 10) * 4;
    assert(dst[farAbove + 3] == 0);
}

unittest
{
    import fl.nanosvg : nsvgParse;

    // Two-stop horizontal linear gradient (red at x=0% -> blue at x=100%)
    // -- exercises createGradient()/initPaint()'s multi-stop lerp branch
    // and scanlineSolid()'s linearGradient case, neither touched by the
    // solid-fill/stroke tests above. Confirms the ramp actually runs left
    // (red) to right (blue), not just "some gradient-shaped output".
    string svg = `<svg width="100" height="20">`
        ~ `<defs><linearGradient id="g" x1="0%" y1="0%" x2="100%" y2="0%">`
        ~ `<stop offset="0%" stop-color="#ff0000"/>`
        ~ `<stop offset="100%" stop-color="#0000ff"/>`
        ~ `</linearGradient></defs>`
        ~ `<rect x="0" y="0" width="100" height="20" fill="url(#g)"/>`
        ~ `</svg>`;
    auto buf = svg.dup;
    auto img = nsvgParse(buf, "px", 96);

    auto rast = new NsvgRasterizer();
    auto dst = new ubyte[100 * 20 * 4];
    rast.rasterize(img, 0, 0, 1.0f, dst, 100, 20, 100 * 4);

    size_t left = (10 * 100 + 5) * 4; // near x=0: mostly red
    size_t right = (10 * 100 + 95) * 4; // near x=100: mostly blue
    assert(dst[left + 0] > 200 && dst[left + 2] < 60);
    assert(dst[right + 2] > 200 && dst[right + 0] < 60);
    assert(dst[left + 3] == 255 && dst[right + 3] == 255);
}

unittest
{
    import fl.nanosvg : nsvgParse;

    // A gradient with exactly one <stop> -- a real, valid, if unusual SVG
    // construct. Exercises initPaint()'s nstops==1 branch directly, which
    // FLTK's own C reads out of bounds for (`stops[i]` up to i=255 on
    // a 1-element array -- see FLTK_ISSUES.md's nsvg__initPaint()
    // entry). This is the one place this port deliberately deviates from
    // "port faithfully, don't fix" -- a literal transliteration would be a
    // D RangeError on every single-stop gradient. This test's real job is
    // confirming that deviation actually works: no crash, and the whole
    // shape renders as a uniform solid color matching the one stop.
    string svg = `<svg width="20" height="20">`
        ~ `<defs><linearGradient id="g"><stop offset="0" stop-color="#00ff00"/></linearGradient></defs>`
        ~ `<rect x="0" y="0" width="20" height="20" fill="url(#g)"/>`
        ~ `</svg>`;
    auto buf = svg.dup;
    auto img = nsvgParse(buf, "px", 96);

    auto rast = new NsvgRasterizer();
    auto dst = new ubyte[20 * 20 * 4];
    rast.rasterize(img, 0, 0, 1.0f, dst, 20, 20, 20 * 4); // must not RangeError

    size_t center = (10 * 20 + 10) * 4;
    assert(dst[center + 1] == 255 && dst[center + 0] == 0 && dst[center + 2] == 0);
    assert(dst[center + 3] == 255);
}
