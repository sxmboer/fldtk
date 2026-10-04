/*
 * Ported from FL/Fl_Tile.H + src/Fl_Tile.cxx (FLTK 1.5.0,
 * ~/Repositories/fltk).
 *
 * A FlGroup whose children can be resized by dragging the borders where
 * they touch. Has no draw() of its own (relies entirely on
 * FlGroup.draw()/drawChildren()) -- all of the substance here is
 * layout/constraint math in handle()/resize()/moveIntersection()/
 * dragIntersection(), which is ported in full, including the
 * size_range mode (per-child minimum-size constraints enforced while
 * dragging an intersection or resizing the Tile itself). This is
 * *not* a faithful-subset situation the way some other modules are --
 * size_range is load-bearing throughout resize()/drag_intersection(),
 * so there's no smaller "classic mode only" port that wouldn't
 * silently drop real FLTK behavior.
 *
 * Deliberate simplifications, none of which touch the constraint math
 * itself:
 *
 *  - `size_range_`/`size_range_size_`/`size_range_capacity_` (a
 *    manually `realloc()`-grown C array, because C++ has nothing
 *    better at hand) collapse into a single D dynamic array
 *    (`sizeRange_`, null when size-range mode is off, matching
 *    FLTK's NULL-pointer check). `onInsert()`/`onMove()`/
 *    `onRemove()` splice it with slicing/concatenation instead of
 *    `memmove()` + manual capacity bookkeeping -- same rationale as
 *    fl.text_buffer's memcpy-vs-memmove note in CLAUDE.md: the
 *    observable behavior (grow/shrink/reorder one slot) is identical,
 *    only the storage-management technique changes.
 *  - `request_grow_{l,r,t,b}`'s C++ signature takes `new_l`/etc. by
 *    `int&`, but none of the four ever assign through it (grep
 *    confirms: read-only). Ported as plain `int` parameters -- an
 *    unread `ref` is unobservable at every call site, so dropping it
 *    changes nothing.
 *  - `set_cursor()`'s `window()->cursor(...)` call is real end to end
 *    now: `Widget.window()` (fl.widget) walks the parent chain for
 *    real (was an always-null stub), `Window.cursor()` forwards to
 *    `fl.platform_x11.setCursor()` (an `XDefineCursor()` call), which
 *    is real too -- so hovering a drag handle now actually changes the
 *    system cursor to indicate the resize direction, matching FLTK.
 *  - The deprecated 4-arg `position(int,int,int,int)` (a >=1.4.0
 *    back-compat shim for move_intersection()) and the trivial 2-arg
 *    `position(int,int)` override (which FLTK only needs to
 *    disambiguate overload resolution against that deprecated
 *    overload -- a C++-only problem) are both skipped. Without the
 *    deprecated overload to disambiguate against, Widget's own
 *    position() already resolves correctly: it calls resize(), which
 *    dispatches virtually to Tile's own override exactly as the C++
 *    passthrough would have.
 *  - No `~this()`: `size_range_`'s manual `::free()` in FLTK's
 *    destructor has no D equivalent to port -- the GC reclaims
 *    `sizeRange_` on its own.
 *
 * `Fl_Cursor` is ported in full (fl.enumerations.Cursor) since it's
 * cheap -- just named integer constants, not a subsystem.
 */
module fl.tile;

import fl.enumerations : Event, Cursor, CallbackReason;
import fl.core;
import fl.group : FlGroup;
import fl.widget : Widget;
import fl.window : Window;
import fl.rect : Rect;
import std.algorithm : min, max;
import std.math : abs;

/// Mouse-grab radius (pixels) around a border/intersection, and the
/// default per-child minimum size once size_range mode is enabled.
/// FLTK's GRABAREA macro serves both purposes; kept as one
/// constant here for the same reason.
private enum int grabArea = 4;

private enum int dragH = 1;
private enum int dragV = 2;

private struct SizeRange { int minw, minh, maxw, maxh; }

private static immutable Cursor[4] tileCursors = [
    Cursor.default_, // 0: normal
    Cursor.we,       // 1: dragging horizontally
    Cursor.ns,       // 2: dragging vertically
    Cursor.move,     // 3: dragging an intersection
];

class Tile : FlGroup
{
    protected int cursor_;
    protected const(Cursor)[] cursors_ = tileCursors;

    private SizeRange[] sizeRange_;

    /**
     * Tracks whether size_range mode has been enabled, independently of
     * `sizeRange_`'s own contents. Testing
     * `sizeRange_ is null`/`!is null` directly as a stand-in for "is
     * size_range mode on," mirroring FLTK's own `if (size_range_)`
     * (a plain non-null-pointer check in C++), is not a safe D
     * equivalent: `initSizeRange()` calling `sizeRange_ = new
     * SizeRange[children()]` when `children() == 0` (i.e. calling it
     * *before* adding any children -- the documented, common usage this
     * class's own doc comment recommends, and exactly what both
     * FLTK's `test/tile.cxx` and this port's own
     * `samples/test/tile.d` do) produces a zero-length array, and a
     * zero-length D dynamic array `is null` **evaluates to `true`**
     * (`new SizeRange[0] is null` -> `true`).
     * Every subsequent `sizeRange_ !is null` check anywhere in this
     * class would then read size_range mode as *off*, silently, even
     * though `initSizeRange()` was genuinely called and the caller has
     * every reason to believe it's on.
     *
     * Concretely, with `r` (the drag-clamp bounds in `handle()`)
     * silently staying `resizable()`'s own widget instead of falling
     * back to `this` (the whole Tile): dragging *any* vertical divider
     * gets clamped to `resizable()`'s own y-range instead of the
     * Tile's, so a divider below that range's bottom edge snaps back up
     * to it the instant you try to drag past there -- exactly "jumps up
     * and can't be reopened." Separately, `dragIntersection()` and
     * `moveIntersection()` both silently take their *classic-mode*
     * branches (no per-child minimum-size enforcement, and
     * `moveIntersection()`'s heavier full-recompute path firing on
     * every single drag event instead of only on release) instead of
     * the intended size_range-aware ones -- a plausible source of stale
     * redraw trails too.
     *
     * This dedicated boolean, set once in `initSizeRange()`
     * and checked everywhere else in this class instead of testing
     * `sizeRange_`'s nullness, avoids the whole trap -- `sizeRange_`
     * itself is untouched, still `null` until
     * `initSizeRange()`/`onInsert()` populate it.
     */
    private bool sizeRangeEnabled_;

    private int defaultMinW_ = grabArea;
    private int defaultMinH_ = grabArea;

    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
    }

    protected Cursor cursor(int n) { return cursors_[n]; }

    private void setCursor(int n)
    {
        if (n < 0 || n > 3) n = 0;
        if (cursor_ == n) return;
        cursor_ = n;
        if (window() !is null) window().cursor(cursor(n));
    }

    // -- size_range constraint helpers --------------------------------
    // Ported one at a time per l/r/t/b axis (not batch-copied) -- the
    // four request_shrink_* and four request_grow_* bodies are
    // near-identical, textbook territory for a sign/axis transcription
    // slip.

    /**
     * Requests that every child whose left edge is at oldL shrink
     * toward newL (growing rightward-touching neighbors as needed, up
     * to their minimum widths). Updates newL in place to the maximum
     * shrinkage actually achievable. When finalSize is non-null, also
     * records the resulting position/size of every affected child.
     */
    protected void requestShrinkL(int oldL, ref int newL, Rect[] finalSize)
    {
        Rect[] bnds = bounds();
        int minL = newL;
        for (int i = 0; i < children(); i++)
        {
            const ri = bnds[i + 2];
            if (ri.x() != oldL) continue;
            if (ri.w() == 0)
            {
                if (finalSize !is null) finalSize[i].x(newL);
            }
            else
            {
                int minW = sizeRange_[i].minw;
                int mayL = min(newL, ri.r() - minW);
                int newLRight = ri.r();
                if (mayL < newL)
                {
                    int missingW = newL - mayL;
                    newLRight = ri.r() + missingW;
                    requestShrinkL(ri.r(), newLRight, null);
                    newLRight = min(newLRight, bnds[0].r());
                    if (finalSize !is null)
                    {
                        requestShrinkL(ri.r(), newLRight, finalSize);
                        requestGrowR(ri.r(), newLRight, finalSize);
                    }
                    minL = min(minL, newLRight - minW);
                }
                if (finalSize !is null)
                {
                    finalSize[i].x(newL);
                    finalSize[i].w(newLRight - newL);
                }
            }
        }
        newL = minL;
    }

    /// Mirror of requestShrinkL() for the right edge, shrinking toward
    /// the left.
    protected void requestShrinkR(int oldR, ref int newR, Rect[] finalSize)
    {
        Rect[] bnds = bounds();
        int minR = newR;
        for (int i = 0; i < children(); i++)
        {
            const ri = bnds[i + 2];
            if (ri.r() != oldR) continue;
            if (ri.w() == 0)
            {
                if (finalSize !is null) finalSize[i].x(newR);
            }
            else
            {
                int minW = sizeRange_[i].minw;
                int mayR = max(newR, ri.x() + minW);
                int newRLeft = ri.x();
                if (mayR > newR)
                {
                    int missingW = mayR - newR;
                    newRLeft = ri.x() - missingW;
                    requestShrinkR(ri.x(), newRLeft, null);
                    newRLeft = max(newRLeft, bnds[0].x());
                    if (finalSize !is null)
                    {
                        requestShrinkR(ri.x(), newRLeft, finalSize);
                        requestGrowL(ri.x(), newRLeft, finalSize);
                    }
                    minR = max(minR, newRLeft + minW);
                }
                if (finalSize !is null)
                {
                    finalSize[i].x(newRLeft);
                    finalSize[i].w(newR - newRLeft);
                }
            }
        }
        newR = minR;
    }

    /// Mirror of requestShrinkL() for the top edge (vertical axis),
    /// shrinking toward the bottom.
    protected void requestShrinkT(int oldT, ref int newT, Rect[] finalSize)
    {
        Rect[] bnds = bounds();
        int minY = newT;
        for (int i = 0; i < children(); i++)
        {
            const ri = bnds[i + 2];
            if (ri.y() != oldT) continue;
            if (ri.h() == 0)
            {
                if (finalSize !is null) finalSize[i].y(newT);
            }
            else
            {
                int minH = sizeRange_[i].minh;
                int mayY = min(newT, ri.b() - minH);
                int newYBelow = ri.b();
                if (mayY < newT)
                {
                    int missingH = newT - mayY;
                    newYBelow = ri.b() + missingH;
                    requestShrinkT(ri.b(), newYBelow, null);
                    newYBelow = min(newYBelow, bnds[0].b());
                    if (finalSize !is null)
                    {
                        requestShrinkT(ri.b(), newYBelow, finalSize);
                        requestGrowB(ri.b(), newYBelow, finalSize);
                    }
                    minY = min(minY, newYBelow - minH);
                }
                if (finalSize !is null)
                {
                    finalSize[i].y(newT);
                    finalSize[i].h(newYBelow - newT);
                }
            }
        }
        newT = minY;
    }

    /// Mirror of requestShrinkR() for the bottom edge (vertical axis),
    /// shrinking toward the top.
    protected void requestShrinkB(int oldB, ref int newB, Rect[] finalSize)
    {
        Rect[] bnds = bounds();
        int minB = newB;
        for (int i = 0; i < children(); i++)
        {
            const ri = bnds[i + 2];
            if (ri.b() != oldB) continue;
            if (ri.h() == 0)
            {
                if (finalSize !is null) finalSize[i].y(newB);
            }
            else
            {
                int minH = sizeRange_[i].minh;
                int mayB = max(newB, ri.y() + minH);
                int newBAbove = ri.y();
                if (mayB > newB)
                {
                    int missingH = mayB - newB;
                    newBAbove = ri.y() - missingH;
                    requestShrinkB(ri.y(), newBAbove, null);
                    newBAbove = max(newBAbove, bnds[0].y());
                    if (finalSize !is null)
                    {
                        requestShrinkB(ri.y(), newBAbove, finalSize);
                        requestGrowT(ri.y(), newBAbove, finalSize);
                    }
                    minB = max(minB, newBAbove + minH);
                }
                if (finalSize !is null)
                {
                    finalSize[i].y(newBAbove);
                    finalSize[i].h(newB - newBAbove);
                }
            }
        }
        newB = minB;
    }

    /// Grows every child whose left edge is at oldL out to newL (maxw
    /// currently ignored, matching FLTK -- always grows exactly to
    /// newL). Unlike the shrink_* siblings, never recurses and always
    /// writes into finalSize (never called with a null one).
    protected void requestGrowL(int oldL, int newL, Rect[] finalSize)
    {
        Rect[] bnds = bounds();
        for (int i = 0; i < children(); i++)
        {
            const ri = bnds[i + 2];
            if (ri.x() == oldL)
            {
                finalSize[i].w(finalSize[i].r() - newL);
                finalSize[i].x(newL);
            }
        }
    }

    /// Mirror of requestGrowL() for the right edge.
    protected void requestGrowR(int oldR, int newR, Rect[] finalSize)
    {
        Rect[] bnds = bounds();
        for (int i = 0; i < children(); i++)
        {
            const ri = bnds[i + 2];
            if (ri.r() == oldR)
                finalSize[i].r(newR);
        }
    }

    /// Mirror of requestGrowL() for the top edge (vertical axis).
    protected void requestGrowT(int oldT, int newT, Rect[] finalSize)
    {
        Rect[] bnds = bounds();
        for (int i = 0; i < children(); i++)
        {
            const ri = bnds[i + 2];
            if (ri.y() == oldT)
            {
                finalSize[i].h(finalSize[i].b() - newT);
                finalSize[i].y(newT);
            }
        }
    }

    /// Mirror of requestGrowR() for the bottom edge (vertical axis).
    protected void requestGrowB(int oldB, int newB, Rect[] finalSize)
    {
        Rect[] bnds = bounds();
        for (int i = 0; i < children(); i++)
        {
            const ri = bnds[i + 2];
            if (ri.b() == oldB)
                finalSize[i].b(newB);
        }
    }

    /**
     * Drags the intersection at (oldx, oldy) to as close to (newx,
     * newy) as constraints allow, redrawing every affected child.
     * Without size_range mode, this just clamps every touching
     * child edge to the new coordinate directly (no min-size
     * enforcement, no recursion). With size_range mode, delegates to
     * dragIntersection() and then calls initSizes() to re-cache the
     * new layout as the baseline for future resize() calls -- pass 0
     * for oldx or oldy to leave that axis alone.
     */
    void moveIntersection(int oldx, int oldy, int newx, int newy)
    {
        if (sizeRangeEnabled_)
        {
            dragIntersection(oldx, oldy, newx, newy);
            initSizes();
        }
        else
        {
            auto a = array();
            Rect[] bnds = bounds();
            for (int i = 0; i < children(); i++)
            {
                Widget o = a[i];
                if (o is resizable()) continue;
                const pi = bnds[i + 2];
                int X = o.x();
                int R = X + o.w();
                if (oldx != 0)
                {
                    int t = pi.x();
                    if (t == oldx || (t > oldx && X < newx) || (t < oldx && X > newx)) X = newx;
                    t = pi.r();
                    if (t == oldx || (t > oldx && R < newx) || (t < oldx && R > newx)) R = newx;
                }
                int Y = o.y();
                int B = Y + o.h();
                if (oldy != 0)
                {
                    int t = pi.y();
                    if (t == oldy || (t > oldy && Y < newy) || (t < oldy && Y > newy)) Y = newy;
                    t = pi.b();
                    if (t == oldy || (t > oldy && B < newy) || (t < oldy && B > newy)) B = newy;
                }
                o.damageResize(X, Y, R - X, B - Y);
            }
        }
    }

    /**
     * Like moveIntersection(), but doesn't call initSizes() --
     * intended for interactive mouse dragging (handle() calls this on
     * FL_DRAG, moveIntersection() on FL_RELEASE) so the cached layout
     * baseline only updates once the drag finishes.
     */
    void dragIntersection(int oldx, int oldy, int newx, int newy)
    {
        if (sizeRangeEnabled_)
        {
            Rect[] bnds = bounds();
            Rect[] finalSize = bnds[2 .. 2 + children()].dup;

            if (oldy != 0 && oldy != newy)
            {
                if (newy <= oldy)
                {
                    int newY = newy;
                    requestShrinkB(oldy, newY, null);
                    requestShrinkB(oldy, newY, finalSize);
                    requestGrowT(oldy, newY, finalSize);
                }
                if (newy > oldy)
                {
                    int newY = newy;
                    requestShrinkT(oldy, newY, null);
                    requestShrinkT(oldy, newY, finalSize);
                    requestGrowB(oldy, newY, finalSize);
                }
            }
            if (oldx != 0 && oldx != newx)
            {
                if (newx <= oldx)
                {
                    int newX = newx;
                    requestShrinkR(oldx, newX, null);
                    requestShrinkR(oldx, newX, finalSize);
                    requestGrowL(oldx, newX, finalSize);
                }
                if (newx > oldx)
                {
                    int newX = newx;
                    requestShrinkL(oldx, newX, null);
                    requestShrinkL(oldx, newX, finalSize);
                    requestGrowR(oldx, newX, finalSize);
                }
            }

            for (int i = 0; i < children(); i++)
            {
                const r = finalSize[i];
                child(i).damageResize(r.x(), r.y(), r.w(), r.h());
            }
        }
        else
        {
            moveIntersection(oldx, oldy, newx, newy);
        }
    }

    /**
     * Resizes the Tile and its children. Tile implements its own
     * layout here rather than using FlGroup.resize()'s proportional
     * scaling -- see the class-level module comment for why size_range
     * mode can't be split out into a smaller faithful subset.
     */
    override void resize(int X, int Y, int W, int H)
    {
        if (sizeRangeEnabled_)
        {
            int dx = X - x();
            int dy = Y - y();
            int dw = w() - W;
            int dh = h() - H;

            if (dw == 0 && dh == 0)
            {
                super.resize(X, Y, W, H);
                initSizes();
                redraw();
                return;
            }

            if (dx != 0 || dy != 0)
            {
                foreach (o; array())
                    o.position(o.x() + dx, o.y() + dy);
            }

            initSizes();
            Rect[] bnds = bounds();
            int bbr = X, bbb = Y;
            for (int i = 0; i < children(); i++)
            {
                bbr = max(bbr, bnds[i + 2].r());
                bbb = max(bbb, bnds[i + 2].b());
            }

            int r2 = X + W;
            requestShrinkR(bbr, r2, null);
            dw = bbr - r2;

            int b2 = Y + H;
            requestShrinkB(bbb, b2, null);
            dh = bbb - b2;

            if (dw != 0 || dh != 0)
            {
                Widget r = resizable();
                int trr = 0, trb = 0;
                if (r !is null)
                {
                    trr = r.x() + r.w() - dw;
                    trb = r.y() + r.h() - dh;
                }

                if (dw < 0 && dh < 0)
                    moveIntersection(bbr, bbb, bbr - dw, bbb - dh);
                else if (dw < 0)
                    moveIntersection(bbr, bbb, bbr - dw, bbb);
                else if (dh < 0)
                    moveIntersection(bbr, bbb, bbr, bbb - dh);

                if (r !is null)
                {
                    int rr = r.x() + r.w();
                    int rb = r.y() + r.h();
                    moveIntersection(rr, rb, trr, trb);
                }

                if (dw > 0 && dh > 0)
                    moveIntersection(bbr, bbb, bbr - dw, bbb - dh);
                else if (dw > 0)
                    moveIntersection(bbr, bbb, bbr - dw, bbb);
                else if (dh > 0)
                    moveIntersection(bbr, bbb, bbr, bbb - dh);

                initSizes();
            }

            // FLTK also guards this with Fl_Window::is_a_rescale()
            // to pick Fl_Widget::resize() during a pure DPI rescale
            // instead of re-running Fl_Group's own layout; Window's
            // isARescale() always reports false here (no scaling
            // subsystem exists yet), so that branch is unreachable
            // exactly as it already is in FLTK's own
            // no-rescale-pending default.
            if (Window.isARescale())
                super.resize(X, Y, W, H);
            else
                resizeBoundsOnly(X, Y, W, H);
            return;
        }

        // Classic mode: resize this widget directly (skip FlGroup's
        // proportional child-layout pass entirely -- same
        // resizeBoundsOnly() pattern fl.scroll and fl.pack use to
        // reach Fl_Widget::resize() by explicit qualification).
        int dx = X - x();
        int dy = Y - y();
        int dw = W - w();
        int dh = H - h();
        Rect[] bnds = bounds();
        resizeBoundsOnly(X, Y, W, H);

        int OR = bnds[1].r();
        int NR = X + W - (bnds[0].r() - OR);
        int OB = bnds[1].b();
        int NB = Y + H - (bnds[0].b() - OB);

        auto a = array();
        for (int i = 0; i < children(); i++)
        {
            Widget o = a[i];
            const pi = bnds[i + 2];
            int xx = o.x() + dx;
            int R = xx + o.w();
            if (pi.x() >= OR) xx += dw; else if (xx > NR) xx = NR;
            if (pi.r() >= OR) R += dw; else if (R > NR) R = NR;
            int yy = o.y() + dy;
            int B = yy + o.h();
            if (pi.y() >= OB) yy += dh; else if (yy > NB) yy = NB;
            if (pi.b() >= OB) B += dh; else if (B > NB) B = NB;
            o.resize(xx, yy, R - xx, B - yy);
            // Deliberately not o.redraw()ing here -- matches FLTK's
            // own comment: doing so sets the wrong damage areas for a
            // Tile nested inside a Scroll.
        }
    }

    override int handle(Event event)
    {
        static int sdrag;
        static int sdx, sdy;
        static int sx, sy;

        int mx = fl.core.eventX();
        int my = fl.core.eventY();

        switch (event)
        {
        case Event.move:
        case Event.enter:
        case Event.push:
            if (!active()) break; // will cascade to FlGroup.handle() below
            {
                int mindx = 100;
                int mindy = 100;
                int oldx = 0;
                int oldy = 0;
                auto a = array();
                Rect[] bnds = bounds();
                for (int i = 0; i < children(); i++)
                {
                    Widget o = a[i];
                    if (!sizeRangeEnabled_ && o is resizable()) continue;
                    const pi = bnds[i + 2];
                    if (pi.r() < bnds[0].r() && o.y() <= my + grabArea && o.y() + o.h() >= my - grabArea)
                    {
                        int t = mx - (o.x() + o.w());
                        if (abs(t) < mindx)
                        {
                            sdx = t;
                            mindx = abs(t);
                            oldx = pi.r();
                        }
                    }
                    if (pi.b() < bnds[0].b() && o.x() <= mx + grabArea && o.x() + o.w() >= mx - grabArea)
                    {
                        int t = my - (o.y() + o.h());
                        if (abs(t) < mindy)
                        {
                            sdy = t;
                            mindy = abs(t);
                            oldy = pi.b();
                        }
                    }
                }
                sdrag = 0; sx = 0; sy = 0;
                if (mindx <= grabArea) { sdrag = dragH; sx = oldx; }
                if (mindy <= grabArea) { sdrag |= dragV; sy = oldy; }
                setCursor(sdrag);
                if (sdrag) return 1;
                return super.handle(event);
            }

        case Event.leave:
            setCursor(0);
            break;

        case Event.drag:
        case Event.release:
        {
            if (!sdrag) break;
            Widget r = resizable();
            if (sizeRangeEnabled_ || r is null) r = this;
            int newx;
            if (sdrag & dragH)
            {
                newx = fl.core.eventX() - sdx;
                if (newx < r.x()) newx = r.x();
                else if (newx > r.x() + r.w()) newx = r.x() + r.w();
            }
            else
                newx = sx;
            int newy;
            if (sdrag & dragV)
            {
                newy = fl.core.eventY() - sdy;
                if (newy < r.y()) newy = r.y();
                else if (newy > r.y() + r.h()) newy = r.y() + r.h();
            }
            else
                newy = sy;

            if (event == Event.drag)
            {
                dragIntersection(sx, sy, newx, newy);
                setChanged();
                doCallback(CallbackReason.dragged);
            }
            else
            {
                moveIntersection(sx, sy, newx, newy);
                doCallback(CallbackReason.changed);
            }
            return 1;
        }

        default:
            break;
        }

        return super.handle(event);
    }

    protected override int onInsert(Widget candidate, int index)
    {
        if (sizeRangeEnabled_)
        {
            SizeRange sr;
            sr.minw = defaultMinW_;
            sr.minh = defaultMinH_;
            sr.maxw = int.max;
            sr.maxh = int.max;
            if (index >= sizeRange_.length)
                sizeRange_ ~= sr;
            else
                sizeRange_ = sizeRange_[0 .. index] ~ sr ~ sizeRange_[index .. $];
        }
        return index;
    }

    protected override int onMove(int oldIndex, int newIndex)
    {
        if (sizeRangeEnabled_ && oldIndex != newIndex)
        {
            SizeRange sr = sizeRange_[oldIndex];
            sizeRange_ = sizeRange_[0 .. oldIndex] ~ sizeRange_[oldIndex + 1 .. $];
            sizeRange_ = sizeRange_[0 .. newIndex] ~ sr ~ sizeRange_[newIndex .. $];
        }
        return newIndex;
    }

    protected override void onRemove(int index)
    {
        if (sizeRangeEnabled_)
            sizeRange_ = sizeRange_[0 .. index] ~ sizeRange_[index + 1 .. $];
    }

    /// Sets the allowed minimum (and, currently ignored, maximum) size
    /// for the child at index, enabling size_range mode if it isn't
    /// already on.
    void sizeRange(int index, int minw, int minh, int maxw = int.max, int maxh = int.max)
    {
        if (!sizeRangeEnabled_) initSizeRange();
        if (index >= 0 && index < children())
        {
            sizeRange_[index].minw = minw;
            sizeRange_[index].minh = minh;
            sizeRange_[index].maxw = maxw;
            sizeRange_[index].maxh = maxh;
        }
    }

    /// Same as sizeRange(int, ...), but looked up by widget.
    void sizeRange(Widget w, int minw, int minh, int maxw = int.max, int maxh = int.max)
    {
        int index = find(w);
        if (index >= 0 && index < children())
            sizeRange(index, minw, minh, maxw, maxh);
    }

    /// Enables size_range mode with the given default minimum size for
    /// any child that doesn't get its own sizeRange() call. A no-op if
    /// size_range mode is already on (matching FLTK: only the
    /// defaults change, existing per-child entries are untouched).
    void initSizeRange(int defaultMinW = -1, int defaultMinH = -1)
    {
        if (defaultMinW > 0) defaultMinW_ = defaultMinW;
        if (defaultMinH > 0) defaultMinH_ = defaultMinH;
        if (!sizeRangeEnabled_)
        {
            sizeRangeEnabled_ = true;
            sizeRange_ = new SizeRange[children()];
            foreach (ref sr; sizeRange_)
            {
                sr.minw = defaultMinW_;
                sr.minh = defaultMinH_;
                sr.maxw = int.max;
                sr.maxh = int.max;
            }
        }
    }
}

unittest
{
    import fl.enumerations : Boxtype;
    FlGroup.current(null);

    auto t = new Tile(0, 0, 200, 100);
    assert(t.box() == Boxtype.noBox);
    assert(t.resizable() is t);
    assert(t.children() == 0);
    t.end();

    FlGroup.current(null);
}

unittest
{
    // Classic mode: dragging the intersection between two side-by-side
    // children (touching at x=100) moves both edges together.
    import fl.box : Box;
    FlGroup.current(null);

    auto t = new Tile(0, 0, 200, 100);
    auto left = new Box(0, 0, 100, 100);
    auto right = new Box(100, 0, 100, 100);
    t.end();

    t.moveIntersection(100, 0, 60, 0);
    assert(left.w() == 60);
    assert(right.x() == 60);
    assert(right.w() == 140);

    FlGroup.current(null);
}

unittest
{
    // size_range mode: dragging past a child's minimum width stops the
    // intersection at the constraint instead of shrinking it further.
    import fl.box : Box;
    FlGroup.current(null);

    auto t = new Tile(0, 0, 200, 100);
    auto left = new Box(0, 0, 100, 100);
    auto right = new Box(100, 0, 100, 100);
    t.end();

    t.initSizeRange();
    t.sizeRange(left, 40, 20);
    t.sizeRange(right, 40, 20);

    // Try to drag the shared edge to x=10 -- left's minw (40) should
    // win, clamping the edge at x=40, not x=10.
    t.moveIntersection(100, 0, 10, 0);
    assert(left.w() == 40);
    assert(right.x() == 40);
    assert(right.w() == 160);

    FlGroup.current(null);
}

unittest
{
    // handle(): pushing near a shared vertical border arms a
    // horizontal drag; dragging it moves the border (still respecting
    // size_range constraints), and release finalizes + fires the
    // "changed" callback reason.
    import fl.box : Box;
    FlGroup.current(null);

    auto t = new Tile(0, 0, 200, 100);
    auto left = new Box(0, 0, 100, 100);
    auto right = new Box(100, 0, 100, 100);
    t.end();

    t.initSizeRange();
    t.sizeRange(left, 20, 20);
    t.sizeRange(right, 20, 20);

    CallbackReason lastReason;
    t.callback((w) { lastReason = fl.core.callbackReason(); });

    fl.core.eX_ = 100;
    fl.core.eY_ = 50;
    assert(t.handle(Event.push) == 1);

    fl.core.eX_ = 70;
    assert(t.handle(Event.drag) == 1);
    assert(left.w() == 70);

    assert(t.handle(Event.release) == 1);
    assert(left.w() == 70);
    assert(right.x() == 70);

    fl.core.resetForTest();
    FlGroup.current(null);
}

unittest
{
    // onInsert()/onMove()/onRemove() keep sizeRange_ in sync with
    // children() order and count once size_range mode is active.
    import fl.box : Box;
    FlGroup.current(null);

    auto t = new Tile(0, 0, 200, 100);
    auto a = new Box(0, 0, 50, 100);
    auto b = new Box(50, 0, 50, 100);
    t.end();

    t.initSizeRange(8, 8);
    t.sizeRange(a, 30, 8);
    t.sizeRange(b, 40, 8);

    auto c = new Box(100, 0, 50, 100);
    t.insert(c, 1); // between a and b
    assert(t.children() == 3);
    assert(t.child(1) is c);

    t.deleteChild(t.find(c));
    assert(t.children() == 2);

    FlGroup.current(null);
}

unittest
{
    // resize() in classic mode (no size_range): growing the Tile
    // extends whichever child touches the trailing edge of
    // resizable() (which defaults to the tile itself, so here that's
    // the tile's own old right edge, x=200) -- matches the class doc's
    // own description: "enlarging works by moving the lower-right
    // corner and resizing the bottom and right border widgets
    // accordingly." The other child, not touching that edge, is left
    // untouched.
    import fl.box : Box;
    FlGroup.current(null);

    auto t = new Tile(0, 0, 200, 100);
    auto left = new Box(0, 0, 100, 100);
    auto right = new Box(100, 0, 100, 100);
    t.end();

    t.resize(0, 0, 300, 100);
    assert(left.x() == 0 && left.w() == 100);     // untouched
    assert(right.x() == 100 && right.w() == 200); // absorbs the +100

    FlGroup.current(null);
}

unittest
{
    // resize() in size_range mode, growing: the resizable() child
    // absorbs all of the added width; a sibling not touching the
    // resizable child keeps its own width, only its trailing neighbor
    // repositions to stay adjacent to the new edge. Matches the class
    // doc's "the child marked resizable() will behave as it would in a
    // regular Fl_Group widget" description for the growing case.
    import fl.box : Box;
    FlGroup.current(null);

    auto t = new Tile(0, 0, 300, 100);
    auto left = new Box(0, 0, 80, 100);
    auto document = new Box(80, 0, 140, 100);
    auto right = new Box(220, 0, 80, 100);
    t.end();

    t.initSizeRange(40, 40);
    t.resizable(document);

    t.resize(0, 0, 340, 100);

    assert(left.x() == 0 && left.w() == 80);         // untouched
    assert(document.x() == 80 && document.w() == 180); // absorbs the +40
    assert(right.x() == 260 && right.w() == 80);       // repositioned, same width

    FlGroup.current(null);
}

unittest
{
    // resize() in size_range mode, shrinking past the combined
    // minimums: each child stops at its own minw rather than
    // shrinking further or going negative/inverted. Two 100px-wide
    // children (minw 30 each, combined min 60) squeezed into a 50px
    // tile can only feasibly reach 60px total -- both end up pinned at
    // exactly their minimum width. (The Tile's own w() still reports
    // the requested 50, per the class doc's own caveat that size_range
    // isn't enforced on the Tile's *own* resize -- only on dragging --
    // so callers are expected to bound this via the enclosing window's
    // size_range() instead; this test is about the children, not the
    // Tile's own reported size.)
    import fl.box : Box;
    FlGroup.current(null);

    auto t = new Tile(0, 0, 200, 100);
    auto left = new Box(0, 0, 100, 100);
    auto right = new Box(100, 0, 100, 100);
    t.end();

    t.initSizeRange(30, 30);

    t.resize(0, 0, 50, 100);

    assert(left.x() == 0 && left.w() == 30);   // pinned at its minw
    assert(right.x() == 30 && right.w() == 30); // pinned at its minw, touching left

    FlGroup.current(null);
}

unittest
{
    // Vertical axis, size_range mode: same clamp-at-minimum check as
    // the earlier horizontal moveIntersection() test, rotated 90
    // degrees -- exercises requestShrinkT()/requestShrinkB()/
    // requestGrowT()/requestGrowB(), the hand-mirrored copies of the
    // L/R helpers already covered above (and the likeliest place for
    // an axis-transcription slip, since they were ported by mirroring
    // rather than independently derived).
    import fl.box : Box;
    FlGroup.current(null);

    auto t = new Tile(0, 0, 100, 200);
    auto top = new Box(0, 0, 100, 100);
    auto bottom = new Box(0, 100, 100, 100);
    t.end();

    t.initSizeRange(40, 40);

    t.moveIntersection(0, 100, 0, 10);
    assert(top.h() == 40);    // pinned at its minh, not shrunk to 10
    assert(bottom.y() == 40);
    assert(bottom.h() == 160);

    FlGroup.current(null);
}

unittest
{
    // Same fixture, opposite drag direction: this exercises
    // requestShrinkT()/requestGrowB() specifically (the previous test
    // only reached requestShrinkB()/requestGrowT() -- dragging the
    // other way is needed to hit this pair's own hand-transcribed
    // y/b/minh accessors).
    import fl.box : Box;
    FlGroup.current(null);

    auto t = new Tile(0, 0, 100, 200);
    auto top = new Box(0, 0, 100, 100);
    auto bottom = new Box(0, 100, 100, 100);
    t.end();

    t.initSizeRange(40, 40);

    t.moveIntersection(0, 100, 0, 190);
    assert(top.h() == 160);
    assert(bottom.y() == 160);
    assert(bottom.h() == 40); // pinned at its minh (not the requested 200-190=10)

    FlGroup.current(null);
}

unittest
{
    // onMove(): moving an already-parented child to a new index (the
    // FlGroup.insert() path that calls onMove(), as opposed to
    // onInsert() for a brand-new child) keeps each child's size_range
    // entry attached to the right widget, not left behind at the old
    // index.
    import fl.box : Box;
    FlGroup.current(null);

    auto t = new Tile(0, 0, 200, 100);
    auto a = new Box(0, 0, 50, 100);
    auto b = new Box(50, 0, 50, 100);
    auto c = new Box(100, 0, 50, 100);
    t.end();

    t.initSizeRange();
    t.sizeRange(a, 10, 10);
    t.sizeRange(b, 20, 20);
    t.sizeRange(c, 30, 30);

    t.insert(c, 0); // move c (currently index 2) to the front

    assert(t.child(0) is c);
    assert(t.child(1) is a);
    assert(t.child(2) is b);
    assert(t.sizeRange_[t.find(a)].minw == 10);
    assert(t.sizeRange_[t.find(b)].minw == 20);
    assert(t.sizeRange_[t.find(c)].minw == 30);

    FlGroup.current(null);
}

unittest
{
    // Regression test (see sizeRangeEnabled_'s own doc comment for the
    // full story):
    // initSizeRange() called *before* any children exist (the
    // documented, common usage -- matching FLTK's own test/tile.cxx
    // and this port's samples/test/tile.d) would otherwise leave
    // size_range mode silently "off" everywhere else in this class,
    // because `sizeRange_ = new SizeRange[0]` -- a zero-length D array
    // -- `is null` in D, the same as an uninitialized one. Every other
    // test in this file calls initSizeRange() *after* adding children
    // (a non-empty array from the start), so this is the one test that
    // exercises the empty-array case.
    import fl.box : Box;
    FlGroup.current(null);

    auto t = new Tile(0, 0, 300, 300);
    t.initSizeRange(30, 30); // *before* any children -- the trap
    auto resizableBox = new Box(0, 0, 300, 150);   // top half, full width
    auto other = new Box(0, 150, 300, 150);        // bottom half, full width
    t.resizable(resizableBox);
    t.end();

    // The bug: handle()'s drag-clamp `r` silently stayed
    // `resizable()`'s own widget (150x150) instead of falling back to
    // the whole Tile (300x300), so any vertical drag got clamped to
    // resizable()'s own y-range -- never able to move an intersection
    // below y=150 at all. Simulate a vertical drag close to the tile's
    // own bottom, past resizable()'s bounds, and confirm it isn't
    // wrongly clamped back up to 150.
    fl.core.eX_ = 150;
    fl.core.eY_ = 150;
    assert(t.handle(Event.push) == 1); // arms a vertical drag on the shared border

    fl.core.eY_ = 250; // well past resizableBox's own 150px height
    assert(t.handle(Event.drag) == 1);
    assert(other.y() == 250); // moved all the way, not clamped back to 150

    fl.core.resetForTest();
    FlGroup.current(null);
}
