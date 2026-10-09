/*
 * Ported from FL/Fl_Scroll.H + src/Fl_Scroll.cxx (FLTK 1.5.0).
 *
 * A FlGroup that lets its children be larger than its own bounds,
 * showing scrollbars to pan around them. Faithful port of the layout
 * math (recalcScrollbars()/bbox()), child-management overrides
 * (onInsert()/onMove()/deleteChild()), resize(), and scrollTo().
 *
 * **`drawClip()`'s tiled-scheme-background branch is real**:
 * `drawClip()` draws the
 * tiled `Fl::scheme_bg_` image instead of a plain solid fill whenever
 * this Scroll fills its window directly (`parent() is window()`) and
 * no boxtype background is set, matching `Fl_Scroll::draw_clip()`
 * exactly. `scrollTo()` also picks up FLTK's matching exception:
 * when that tiled background is active, a position change forces a
 * full `damage(damageAll)` instead of the incremental `damageScroll`
 * blit, since `fl_scroll()`'s `XCopyArea` would otherwise drag the
 * tiled background along with the (unrelated) scrolled content.
 *
 * `FL_DAMAGE_SCROLL`'s incremental scroll-and-patch redraw is real,
 * using `fl.draw.fl_scroll()`
 * (an `XCopyArea`-based blit of the still-valid area, only
 * redrawing the newly-exposed strip): `scrollTo()` triggers
 * `damage(damageScroll)` instead of a full `redraw()`, and `oldx_`/
 * `oldy_` (ported from FLTK's `oldx`/`oldy`, `FL/Fl_Scroll.H`) feed
 * `fl_scroll()`'s delta. See `fl_scroll()`'s own doc comment for the
 * one deliberately-skipped edge case (recovering pixels that were
 * themselves obscured by another window during the copy, FLTK's
 * driver-level `GraphicsExpose`/`NoExpose` synchronous wait -- this
 * port's shared GC disables `graphics_exposures` outright instead).
 *
 * Also simplified: unlike FLTK, this port's `deleteChild()`
 * override is the *only* thing protecting `scrollbar`/`hscrollbar` from
 * `FlGroup.clear()`'s/`FlGroup.~this()`'s child-deletion sweep. FLTK
 * needs a second, hand-written copy of that protection in both
 * `Fl_Scroll::clear()` and `~Fl_Scroll()`, because C++ "unwinds" an
 * object's vtable as each destructor in the inheritance chain runs, so
 * a virtual call to `delete_child()` made from inside `~Fl_Group()`
 * can no longer reach `Fl_Scroll`'s override by that point. D doesn't
 * do this -- an object keeps the same vtable for its whole lifetime,
 * including throughout its own destruction -- so `deleteChild()`
 * alone is sufficient here; no `clear()` or `~this()` override needed.
 * See CONVENTIONS.md's "D does not unwind the vtable during destruction"
 * note for the general principle (this module is where it was first
 * worked out) -- worth checking before porting any other FLTK
 * class that leans on the same C++-only defensive-copy pattern.
 */
module fl.scroll;

import fl.enumerations;
import fl.core;
import fl.group : FlGroup;
import fl.widget : Widget;
import fl.scrollbar : Scrollbar;
import fl.slider : horSlider;
import fl.rect : Rect;
import fl.tiled_image : TiledImage;
import fldraw = fl.draw;

/// Values for type(); mirrors Fl_Scroll.H's anonymous enum.
enum ubyte scrollHorizontal = 1;
enum ubyte scrollVertical = 2;
enum ubyte scrollBoth = 3;
enum ubyte scrollAlwaysOn = 4;
enum ubyte scrollHorizontalAlways = 5;
enum ubyte scrollVerticalAlways = 6;
enum ubyte scrollBothAlways = 7;

class Scroll : FlGroup
{
    private
    {
        int xposition_;
        int yposition_;
        int scrollbarSize_;
        // Position as of the last draw() -- feeds fl_scroll()'s delta
        // for the incremental blit-and-patch redraw. Ported from
        // FLTK's `oldx, oldy` (FL/Fl_Scroll.H).
        int oldx_;
        int oldy_;
    }

    Scrollbar scrollbar;
    Scrollbar hscrollbar;

    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);

        int sbs = fl.core.scrollbarSize();
        // Constructed while FlGroup's ctor has already called begin(),
        // so these auto-parent into this Scroll as its first two
        // children -- matching FLTK's member-initializer-list
        // construction (before the body runs), just via D's
        // "current() group" mechanism instead of C++ member order.
        scrollbar = new Scrollbar(x + w - sbs, y, sbs, h - sbs);
        hscrollbar = new Scrollbar(x, y + h - sbs, w - sbs, sbs);

        type(scrollBoth);
        xposition_ = 0;
        yposition_ = 0;
        scrollbarSize_ = 0;
        hscrollbar.type(horSlider);
        hscrollbar.callback((wgt) {
            scrollTo(cast(int)(cast(Scrollbar) wgt).value(), yposition());
        });
        scrollbar.callback((wgt) {
            scrollTo(xposition(), cast(int)(cast(Scrollbar) wgt).value());
        });
    }

    /// Current horizontal scrolling position.
    int xposition() const { return xposition_; }
    /// Current vertical scrolling position.
    int yposition() const { return yposition_; }

    /**
     * Moves the logical origin of the scrolling area to (X, Y) --
     * every non-scrollbar child is repositioned by the resulting
     * delta. A no-op if the position doesn't actually change.
     */
    void scrollTo(int X, int Y)
    {
        int dx = xposition_ - X;
        int dy = yposition_ - Y;
        if (!dx && !dy) return;
        xposition_ = X;
        yposition_ = Y;
        foreach (o; array())
        {
            if (o is hscrollbar || o is scrollbar) continue;
            o.position(o.x() + dx, o.y() + dy);
        }
        // Triggers draw()'s incremental fl_scroll()-based blit-and-patch
        // path instead of a full redraw -- see the module comment for
        // the one deliberately-skipped edge case (GraphicsExpose
        // recovery) that path doesn't handle. Ported exception: an
        // XCopyArea-based blit would drag the tiled scheme background
        // along with the (unrelated) scrolled content, so a full
        // redraw is forced instead whenever that background is active
        // and this Scroll fills its whole window.
        if (parent() is cast(Widget) window() && fl.core.schemeBg() !is null)
            damage(damageAll);
        else
            damage(damageScroll);
    }

    /// Refuses to delete scrollbar/hscrollbar; otherwise forwards to
    /// FlGroup.deleteChild(). See the module comment for why this alone
    /// is enough to also protect them during FlGroup.clear()/~this().
    override int deleteChild(int index)
    {
        if (index < 0 || index >= children()) return 1;
        Widget w = child(index);
        if (w is scrollbar || w is hscrollbar) return 2;
        return super.deleteChild(index);
    }

    protected override int onInsert(Widget candidate, int index)
    {
        if (children() > 1 && index > children() - 2
                && candidate !is scrollbar && candidate !is hscrollbar)
            index = children() - 2;
        return index;
    }

    protected override int onMove(int oldIndex, int newIndex)
    {
        return onInsert(child(oldIndex), newIndex);
    }

    /// Ensures scrollbar/hscrollbar are the last two children (in that
    /// order), in case something bypassed onInsert()/onMove()'s
    /// ordering. Idempotent -- a no-op once they're already in place.
    private void fixScrollbarOrder()
    {
        auto a = array();
        if (children() > 1 && (a[children() - 2] !is scrollbar || a[$ - 1] !is hscrollbar))
        {
            int i = 0;
            for (int j = 0; j < children(); j++)
                if (a[j] !is hscrollbar && a[j] !is scrollbar) a[i++] = a[j];
            a[i++] = scrollbar;
            a[i++] = hscrollbar;
        }
    }

    private static struct ScrollbarData
    {
        int x, y, w, h;
        int pos, size, first, total;
    }

    private static struct ScrollInfo
    {
        int scrollsize;
        Rect innerbox;
        Rect innerchild;
        Rect child;
        bool hneeded, vneeded;
        ScrollbarData hscroll, vscroll;
    }

    /**
     * Calculates scrollbar visibility/size/position and the children's
     * bounding box, without changing anything -- callers (draw(),
     * bbox()) act on the results. Ported from recalc_scrollbars().
     */
    private void recalcScrollbars(ref ScrollInfo si)
    {
        si.innerbox = Rect(x(), y(), w(), h(), box());
        si.child = Rect(si.innerbox.x(), si.innerbox.y(), 0, 0);

        bool first = true;
        foreach (o; array())
        {
            if (o is scrollbar || o is hscrollbar || !o.visible()) continue;
            if (first)
            {
                first = false;
                si.child = Rect(o);
            }
            else
            {
                if (o.x() < si.child.x()) si.child.x(o.x());
                if (o.y() < si.child.y()) si.child.y(o.y());
                if (o.x() + o.w() > si.child.r()) si.child.r(o.x() + o.w());
                if (o.y() + o.h() > si.child.b()) si.child.b(o.y() + o.h());
            }
        }

        {
            int X = si.innerbox.x();
            int Y = si.innerbox.y();
            int W = si.innerbox.w();
            int H = si.innerbox.h();

            si.scrollsize = scrollbarSize_ ? scrollbarSize_ : fl.core.scrollbarSize();
            si.vneeded = false;
            si.hneeded = false;
            if (type() & scrollVertical)
            {
                if ((type() & scrollAlwaysOn) || si.child.y() < Y || si.child.b() > Y + H)
                {
                    si.vneeded = true;
                    W -= si.scrollsize;
                    if (scrollbar.alignment() & alignLeft) X += si.scrollsize;
                }
            }
            if (type() & scrollHorizontal)
            {
                if ((type() & scrollAlwaysOn) || si.child.x() < X || si.child.r() > X + W)
                {
                    si.hneeded = true;
                    H -= si.scrollsize;
                    if (scrollbar.alignment() & alignTop) Y += si.scrollsize;
                    if (!si.vneeded && (type() & scrollVertical))
                    {
                        if ((type() & scrollAlwaysOn) || si.child.y() < Y || si.child.b() > Y + H)
                        {
                            si.vneeded = true;
                            W -= si.scrollsize;
                            if (scrollbar.alignment() & alignLeft) X += si.scrollsize;
                        }
                    }
                }
            }
            si.innerchild.x(X);
            si.innerchild.y(Y);
            si.innerchild.w(W);
            si.innerchild.h(H);
        }

        si.hscroll.x = si.innerchild.x();
        si.hscroll.y = (scrollbar.alignment() & alignTop)
            ? si.innerbox.y() : si.innerbox.b() - si.scrollsize;
        si.hscroll.w = si.innerchild.w();
        si.hscroll.h = si.scrollsize;

        si.vscroll.x = (scrollbar.alignment() & alignLeft)
            ? si.innerbox.x() : si.innerbox.r() - si.scrollsize;
        si.vscroll.y = si.innerchild.y();
        si.vscroll.w = si.scrollsize;
        si.vscroll.h = si.innerchild.h();

        si.hscroll.pos = si.innerchild.x() - si.child.x();
        si.hscroll.size = si.innerchild.w();
        si.hscroll.first = 0;
        si.hscroll.total = si.child.w();
        if (si.hscroll.pos < 0)
        {
            si.hscroll.total += -si.hscroll.pos;
            si.hscroll.first = si.hscroll.pos;
        }

        si.vscroll.pos = si.innerchild.y() - si.child.y();
        si.vscroll.size = si.innerchild.h();
        si.vscroll.first = 0;
        si.vscroll.total = si.child.h();
        if (si.vscroll.pos < 0)
        {
            si.vscroll.total += -si.vscroll.pos;
            si.vscroll.first = si.vscroll.pos;
        }
    }

    /// Bounding box for the interior of the scrolling area, inside the
    /// scrollbars.
    private void bbox(out int X, out int Y, out int W, out int H)
    {
        ScrollInfo si;
        recalcScrollbars(si);
        X = si.innerchild.x();
        Y = si.innerchild.y();
        W = si.innerchild.w();
        H = si.innerchild.h();
    }

    /// Draws the background and every non-scrollbar child within a
    /// clip region. Ported from the static draw_clip(), including the
    /// tiled-scheme-background branch (see the module comment).
    private void drawClip(int X, int Y, int W, int H)
    {
        fldraw.pushClip(X, Y, W, H);

        // Ported from Fl_Scroll::draw_clip()'s background-erase: the
        // tiled-scheme-image path.
        auto bg = cast(TiledImage) fl.core.schemeBg();
        if (!boxBg(box()) && parent() is cast(Widget) window() && bg !is null)
        {
            int iw = bg.image().w();
            int ih = bg.image().h();
            bg.draw(X - (X % iw), Y - (Y % ih), W + iw, H + ih);
        }
        else
        {
            if (activeR())
                fldraw.fl_color(color());
            else
                fldraw.fl_color(fldraw.inactive(color()));
            fldraw.fl_rectf(X, Y, W, H);
        }

        foreach (o; array()[0 .. children() - 2])
        {
            drawChild(o);
            drawOutsideLabel(o);
        }

        fldraw.popClip();
    }

    override void draw()
    {
        fixScrollbarOrder();
        int bx, by, bw, bh;
        bbox(bx, by, bw, bh);

        Damage d = damage();

        if (d & damageAll)
        {
            drawBox(box(), x(), y(), w(), h(), color());
            drawClip(bx, by, bw, bh);
        }
        else
        {
            if (d & damageScroll)
            {
                fldraw.fl_scroll(bx, by, bw, bh, oldx_ - xposition_, oldy_ - yposition_,
                    (cx, cy, cw, ch) { drawClip(cx, cy, cw, ch); });

                // Erase the background as needed (the strip(s) not
                // covered by any non-scrollbar child's new position).
                int L = int.max, R = 0, T = int.max, B = 0;
                foreach (o; array()[0 .. children() - 2])
                {
                    if (o.x() < L) L = o.x();
                    if (o.x() + o.w() > R) R = o.x() + o.w();
                    if (o.y() < T) T = o.y();
                    if (o.y() + o.h() > B) B = o.y() + o.h();
                }
                if (L > bx) drawClip(bx, by, L - bx, bh);
                if (R < bx + bw) drawClip(R, by, bx + bw - R, bh);
                if (T > by) drawClip(bx, by, bw, T - by);
                if (B < by + bh) drawClip(bx, B, bw, by + bh - B);
            }
            if (d & damageChild)
            {
                fldraw.pushClip(bx, by, bw, bh);
                foreach (o; array()[0 .. children() - 2])
                    updateChild(o);
                fldraw.popClip();
            }
        }

        ScrollInfo si;
        recalcScrollbars(si);

        if (si.vneeded && !scrollbar.visible())
        {
            scrollbar.setVisible();
            d = damageAll;
        }
        else if (!si.vneeded && scrollbar.visible())
        {
            scrollbar.clearVisible();
            drawClip(si.vscroll.x, si.vscroll.y, si.vscroll.w, si.vscroll.h);
            d = damageAll;
        }
        if (si.hneeded && !hscrollbar.visible())
        {
            hscrollbar.setVisible();
            d = damageAll;
        }
        else if (!si.hneeded && hscrollbar.visible())
        {
            hscrollbar.clearVisible();
            drawClip(si.hscroll.x, si.hscroll.y, si.hscroll.w, si.hscroll.h);
            d = damageAll;
        }
        else if (hscrollbar.h() != si.scrollsize || scrollbar.w() != si.scrollsize)
        {
            d = damageAll;
        }

        scrollbar.resize(si.vscroll.x, si.vscroll.y, si.vscroll.w, si.vscroll.h);
        oldy_ = yposition_ = si.vscroll.pos;
        scrollbar.value(si.vscroll.pos, si.vscroll.size, si.vscroll.first, si.vscroll.total);

        hscrollbar.resize(si.hscroll.x, si.hscroll.y, si.hscroll.w, si.hscroll.h);
        oldx_ = xposition_ = si.hscroll.pos;
        hscrollbar.value(si.hscroll.pos, si.hscroll.size, si.hscroll.first, si.hscroll.total);

        if (d & damageAll)
        {
            drawChild(scrollbar);
            drawChild(hscrollbar);
            if (scrollbar.visible() && hscrollbar.visible())
            {
                fldraw.fl_color(color());
                fldraw.fl_rectf(scrollbar.x(), hscrollbar.y(), scrollbar.w(), hscrollbar.h());
            }
        }
        else
        {
            updateChild(scrollbar);
            updateChild(hscrollbar);
        }
    }

    /**
     * Resizes the Scroll itself and repositions its children by the
     * same delta (children are never resized, matching FLTK --
     * resizable() is ignored here). Deliberately calls
     * resizeBoundsOnly() rather than super.resize(), matching
     * FLTK's own explicit `Fl_Widget::resize(...)` call that
     * bypasses `Fl_Group::resize()`'s proportional child-layout
     * algorithm entirely.
     */
    override void resize(int X, int Y, int W, int H)
    {
        int dx = X - x();
        int dy = Y - y();
        int dw = W - w();
        int dh = H - h();
        resizeBoundsOnly(X, Y, W, H);
        fixScrollbarOrder();

        foreach (o; array()[0 .. children() - 2])
            o.position(o.x() + dx, o.y() + dy);

        if (dw == 0 && dh == 0)
        {
            bool pad = scrollbar.visible() && hscrollbar.visible();
            bool al = (scrollbar.alignment() & alignLeft) != 0;
            bool at = (scrollbar.alignment() & alignTop) != 0;
            scrollbar.position(al ? X : X + W - scrollbar.w(), (at && pad) ? Y + hscrollbar.h() : Y);
            hscrollbar.position((al && pad) ? X + scrollbar.w() : X, at ? Y : Y + H - hscrollbar.h());
        }
        else
        {
            // Growing while scrolled to the far edge would leave the
            // position past the new maximum; clamp it back.
            ScrollInfo si;
            recalcScrollbars(si);
            int minX = si.hscroll.first;
            int maxX = si.hscroll.first + si.hscroll.total - si.hscroll.size;
            if (maxX < minX) maxX = minX;
            int minY = si.vscroll.first;
            int maxY = si.vscroll.first + si.vscroll.total - si.vscroll.size;
            if (maxY < minY) maxY = minY;
            int newX = xposition_ < minX ? minX : (xposition_ > maxX ? maxX : xposition_);
            int newY = yposition_ < minY ? minY : (yposition_ > maxY ? maxY : yposition_);
            if (newX != xposition_ || newY != yposition_) scrollTo(newX, newY);
            redraw(); // full scrollbar recalculation needed; done in draw()
        }
    }

    override int handle(Event event)
    {
        fixScrollbarOrder();
        if (event == Event.mouseWheel)
        {
            // Children get first refusal, then the scrollbars, even when hidden
            // (a hidden scrollbar takes no events through Group dispatch).
            if (super.handle(event)) return 1;
            if (!scrollbar.visible() && scrollbar.handle(Event.mouseWheel)) return 1;
            if (!hscrollbar.visible() && hscrollbar.handle(Event.mouseWheel)) return 1;
            return 0;
        }
        return super.handle(event);
    }

    /// Gets the current size of the scrollbars' troughs, in pixels, or
    /// 0 if tracking the global fl.core.scrollbarSize().
    int scrollbarSize() const { return scrollbarSize_; }

    /// Sets the pixel size of this instance's scrollbar troughs.
    /// Setting to 0 (default) tracks the global fl.core.scrollbarSize().
    void scrollbarSize(int newSize)
    {
        if (newSize != scrollbarSize_) redraw();
        scrollbarSize_ = newSize;
    }
}

unittest
{
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto s = new Scroll(0, 0, 200, 100);
    assert(s.box() == Boxtype.noBox);
    assert(s.type() == scrollBoth);
    assert(s.children() == 2); // just the two scrollbars so far
    assert(s.child(0) is s.scrollbar);
    assert(s.child(1) is s.hscrollbar);
    s.end();

    FlGroup.current(null);
}

unittest
{
    // Widgets added after construction land *before* the scrollbars
    // (onInsert() clamps their index), regardless of how many are
    // added, keeping the scrollbars as the last two children.
    import fl.group : FlGroup;
    import fl.box : Box;
    FlGroup.current(null);

    auto s = new Scroll(0, 0, 100, 100);
    auto a = new Box(0, 0, 10, 10);
    auto b = new Box(20, 0, 10, 10);
    s.end();

    assert(s.children() == 4);
    assert(s.child(0) is a);
    assert(s.child(1) is b);
    assert(s.child(2) is s.scrollbar);
    assert(s.child(3) is s.hscrollbar);

    FlGroup.current(null);
}

unittest
{
    // deleteChild() refuses to remove either scrollbar, but succeeds
    // for a regular child.
    import fl.group : FlGroup;
    import fl.box : Box;
    FlGroup.current(null);

    auto s = new Scroll(0, 0, 100, 100);
    auto a = new Box(0, 0, 10, 10);
    s.end();

    assert(s.deleteChild(s.find(s.scrollbar)) == 2);
    assert(s.deleteChild(s.find(s.hscrollbar)) == 2);
    assert(s.children() == 3); // nothing actually removed above

    assert(s.deleteChild(s.find(a)) == 0);
    assert(s.children() == 2);

    FlGroup.current(null);
}

unittest
{
    // The *inherited* FlGroup.clear() (Scroll doesn't need its own
    // override -- see the module comment) still leaves the scrollbars
    // intact: its delete-every-child loop calls deleteChild()
    // virtually, which Scroll overrides to refuse exactly those two.
    import fl.group : FlGroup;
    import fl.box : Box;
    FlGroup.current(null);

    auto s = new Scroll(0, 0, 100, 100);
    new Box(0, 0, 10, 10);
    new Box(20, 0, 10, 10);
    s.end();
    assert(s.children() == 4);

    s.clear();
    assert(s.children() == 2);
    assert(s.child(0) is s.scrollbar);
    assert(s.child(1) is s.hscrollbar);

    FlGroup.current(null);
}

unittest
{
    // scrollTo() repositions non-scrollbar children by the delta and
    // is a no-op when the position doesn't change.
    import fl.group : FlGroup;
    import fl.box : Box;
    FlGroup.current(null);

    auto s = new Scroll(0, 0, 100, 100);
    auto a = new Box(10, 10, 10, 10);
    s.end();

    s.scrollTo(5, 5);
    assert(s.xposition() == 5);
    assert(s.yposition() == 5);
    assert(a.x() == 5); // 10 - (5 - 0)
    assert(a.y() == 5);

    int scrollbarX = s.scrollbar.x();
    s.scrollTo(5, 5); // same position: no-op
    assert(s.scrollbar.x() == scrollbarX);

    FlGroup.current(null);
}

unittest
{
    // recalcScrollbars(): a child that fits entirely within the
    // Scroll's bounds needs no scrollbars; scrollAlwaysOn forces them
    // on regardless.
    import fl.group : FlGroup;
    import fl.box : Box;
    FlGroup.current(null);

    auto s = new Scroll(0, 0, 100, 100);
    new Box(0, 0, 50, 50); // fits comfortably
    s.end();

    Scroll.ScrollInfo si;
    s.recalcScrollbars(si);
    assert(!si.vneeded);
    assert(!si.hneeded);

    s.type(scrollBothAlways);
    s.recalcScrollbars(si);
    assert(si.vneeded);
    assert(si.hneeded);

    FlGroup.current(null);
}

unittest
{
    // draw() calls into fl.draw's real-on-Linux-only primitives, which
    // no-op safely without an open display (same pattern as
    // fl.round_button's draw() unittest) -- just confirm no exception.
    import fl.group : FlGroup;
    import fl.box : Box;
    FlGroup.current(null);

    auto s = new Scroll(0, 0, 100, 100);
    new Box(0, 0, 200, 200); // bigger than the scroll: needs both scrollbars
    s.end();
    s.draw();

    FlGroup.current(null);
}

unittest
{
    // scrollTo() sets damageScroll (not damageAll), which draw()'s
    // fl_scroll()-based incremental path handles -- confirms the bit
    // and that oldx_/oldy_ get updated to feed the next scroll's delta
    // (both pure bookkeeping, no display needed), plus that draw()
    // itself still runs the damageScroll branch without crashing
    // headlessly (fl.draw.fl_scroll()'s XCopyArea() call no-ops
    // safely without an open display, same pattern as every other
    // fl.draw-calling draw() unittest in this project).
    import fl.group : FlGroup;
    import fl.box : Box;
    FlGroup.current(null);

    auto s = new Scroll(0, 0, 100, 100);
    new Box(0, 0, 200, 200); // bigger than the scroll: needs both scrollbars
    s.end();
    s.draw(); // first draw: damageAll, also seeds oldx_/oldy_ via si.*scroll.pos
    assert(!(s.damage() & damageScroll));

    s.clearDamage();
    s.scrollTo(10, 15);
    assert(s.damage() & damageScroll);
    assert(!(s.damage() & damageAll));

    s.draw(); // exercises the damageScroll branch specifically
    assert(s.oldx_ == s.xposition());
    assert(s.oldy_ == s.yposition());

    FlGroup.current(null);
}
