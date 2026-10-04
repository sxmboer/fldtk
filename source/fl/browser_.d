/*
 * Ported from FL/Fl_Browser_.H + src/Fl_Browser_.cxx (FLTK 1.5.0,
 * ~/Repositories/fltk).
 *
 * The base class for browsers -- to be useful it must be subclassed
 * with the item_* virtuals defined (see fl.browser, fl.check_browser).
 * Faithful, essentially complete port of the scrolling/selection
 * mechanism: bbox()/resize()/draw() (including the "redraw, then
 * re-check scrollbar visibility, goto redraw once more if it changed"
 * loop FLTK's draw() itself does via `goto J1`, ported here as a
 * `while(true)`/`continue` loop instead, since D lacks `goto` crossing
 * variable-declaration boundaries as freely as C++ allows here),
 * update_top()'s "step from head or from the current top_, whichever
 * is closer" search, display()'s "search up and down the list at the
 * same time" item-scroll-into-view logic, select()/deselect()/
 * select_only(), and handle()'s full keyboard-navigation +
 * push/drag/release mouse selection state machine (Normal/Select/
 * Hold/Multi browser semantics all faithfully reproduced).
 *
 * Deliberate deviations:
 *
 *  - `void* item` becomes `Object item` throughout. FLTK's item_*
 *    protocol is deliberately storage-agnostic (the item pointer is
 *    opaque to this base class -- only next()/prev()/first()/last()
 *    give it meaning), which is exactly what a D `Object` reference
 *    gives for free: identity comparison via `is`/`!is` (matching
 *    FLTK's raw pointer-equality checks throughout), GC-managed
 *    lifetime (no manual free() bookkeeping needed the way FLTK's
 *    subclasses need for their own item structs), and no `void*`-cast
 *    unsafety at every call site. Concrete subclasses (fl.browser's
 *    `BLine`, fl.check_browser's `CbItem`) are ordinary D classes.
 *
 *  - FLTK's C++ static-local variables inside handle()
 *    (`static void* initsel; static char change; static char
 *    whichway; static int py;`) are genuinely process-wide state
 *    shared across *every* Fl_Browser_ instance, not per-object state
 *    -- the same kind of quirk already documented in fl.slider's
 *    `static int offcenter` and fl.roller's `static int ipos`. Ported
 *    the same way: private module-level variables, not fields.
 *
 *  - Icon support (`Fl_Image* icon` fields/`icon()` accessors) is
 *    deferred to fl.browser -- Browser_ itself has no icon concept
 *    FLTK either (that's Fl_Browser::item_height/width/draw's own
 *    doing, not Fl_Browser_'s).
 *
 *  - Sorting's case-insensitive path uses `std.uni.sicmp` in place of
 *    FLTK's `fl_utf_strcasecmp()` -- both are simple-casefold
 *    Unicode-aware comparisons; `std.uni.sicmp` is the closer D-stdlib
 *    match (no per-project caseless-compare helper existed anywhere
 *    else in this port to reuse instead).
 */
module fl.browser_;

import fl.group;
import fl.widget;
import fl.widget_tracker : WidgetTracker;
import fl.scrollbar : Scrollbar;
import fl.slider : horSlider;
import fl.enumerations;
import fl.core;
import fldraw = fl.draw;
import std.uni : sicmp;
import std.algorithm.comparison : cmp;

/// type() values for Fl_Browser and its subclasses (FL_NORMAL_BROWSER
/// et al, FL/Fl_Browser_.H).
enum ubyte normalBrowser = 0;
enum ubyte selectBrowser = 1;
enum ubyte holdBrowser   = 2;
enum ubyte multiBrowser  = 3;

/// sort() flags (FL_SORT_ASCENDING et al).
enum int sortAscending       = 0;
enum int sortDescending      = 1;
enum int sortCaseInsensitive = 0x2;

/// has_scrollbar() mode bits -- open bitmask set (combines via `|`),
/// matching Align/Damage/etc.'s alias-plus-manifest-constants
/// treatment elsewhere in this port (see fl.scroll's identical
/// treatment of its own anonymous scrollbar-mode enum for precedent).
enum ubyte browserHorizontal        = 1;
enum ubyte browserVertical          = 2;
enum ubyte browserBoth              = 3;
enum ubyte browserAlwaysOn          = 4;
enum ubyte browserHorizontalAlways  = 5;
enum ubyte browserVerticalAlways    = 6;
enum ubyte browserBothAlways        = 7;

// Genuinely process-wide state shared by every Browser_ instance's
// handle() -- see the module comment.
private Object handleInitsel_;
private bool handleChange_;
private bool handleWhichway_;
private int handlePy_;

abstract class Browser_ : FlGroup
{
    private
    {
        int position_;
        int realPosition_;
        int hposition_;
        int realHposition_;
        int offset_;
        int maxWidth_;
        ubyte hasScrollbar_;
        Font textfont_;
        Fontsize textsize_;
        Color textcolor_;
        Object top_;
        Object selection_;
        Object redraw1_, redraw2_;
        Object maxWidthItem_;
        int scrollbarSize_;
        int linespacing_;
    }

    /// Vertical scrollbar. Public, so it can be accessed directly. Use
    /// scrollbarLeft()/scrollbarRight() to change which side it's on.
    Scrollbar scrollbar;
    /// Horizontal scrollbar. Public, so it can be accessed directly.
    Scrollbar hscrollbar;

    protected this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);

        // Auto-parent into this Browser_ as its first two children,
        // matching FLTK's member-initializer-list construction
        // order (FlGroup's own ctor already called begin()) -- same
        // pattern as fl.scroll's Scroll ctor.
        scrollbar = new Scrollbar(0, 0, 0, 0);
        hscrollbar = new Scrollbar(0, 0, 0, 0);

        box(Boxtype.noBox);
        alignment(alignBottom);
        position_ = realPosition_ = 0;
        hposition_ = realHposition_ = 0;
        offset_ = 0;
        top_ = null;
        when(whenReleaseAlways);
        selection_ = null;
        color(fl.enumerations.background2Color, fl.enumerations.selectionColor);
        scrollbar.callback((wgt) { vposition(cast(int)(cast(Scrollbar) wgt).value()); });
        hscrollbar.callback((wgt) { hposition(cast(int)(cast(Scrollbar) wgt).value()); });
        hscrollbar.type(horSlider);
        textfont_ = helvetica;
        textsize_ = normalSize;
        textcolor_ = foregroundColor;
        hasScrollbar_ = browserBoth;
        maxWidth_ = 0;
        maxWidthItem_ = null;
        scrollbarSize_ = 0;
        redraw1_ = redraw2_ = null;
        end();
    }

    // ----------------------------------------------------------------
    // Subclass-provided item protocol
    // ----------------------------------------------------------------

    protected abstract Object itemFirst() const;
    protected abstract Object itemNext(Object item) const;
    protected abstract Object itemPrev(Object item) const;
    protected Object itemLast() const { return null; }
    protected abstract int itemHeight(Object item) const;
    protected abstract int itemWidth(Object item) const;
    protected int itemQuickHeight(Object item) const { return itemHeight(item); }
    protected abstract void itemDraw(Object item, int X, int Y, int W, int H) const;
    protected const(char)[] itemText(Object item) const { return null; }
    protected void itemSwap(Object a, Object b) { }
    protected Object itemAt(int index) const { return null; }

    protected int fullWidth() const { return maxWidth_; }
    protected int fullHeight() const
    {
        int t = 0;
        for (Object p = itemFirst(); p !is null; p = itemNext(p))
            t += itemQuickHeight(p);
        return t;
    }
    protected int incrHeight() const { return itemQuickHeight(itemFirst()) + linespacing(); }

    /// Must be overridden to support Fl_Multi_Browser-style selection.
    protected void itemSelect(Object item, int val = 1) { }
    /// ditto
    protected int itemSelected(Object item) const { return item is selection_ ? 1 : 0; }

    // ----------------------------------------------------------------
    // Things the subclass may want to call
    // ----------------------------------------------------------------

    protected Object top() const { return cast(Object) top_; }
    protected Object selection() const { return cast(Object) selection_; }

    /// Completely clobber all data, as though the list was replaced.
    protected void newList()
    {
        top_ = null;
        position_ = realPosition_ = 0;
        hposition_ = realHposition_ = 0;
        selection_ = null;
        offset_ = 0;
        maxWidth_ = 0;
        maxWidthItem_ = null;
        redrawLines();
    }

    /// Get rid of any pointers to item -- it's being deleted.
    protected void deleting(Object item)
    {
        if (displayed(item))
        {
            redrawLines();
            if (item is top_)
            {
                realPosition_ -= offset_;
                offset_ = 0;
                top_ = itemNext(item);
                if (top_ is null) top_ = itemPrev(item);
            }
        }
        else
        {
            realPosition_ = 0;
            offset_ = 0;
            top_ = null;
        }
        if (item is selection_) selection_ = null;
        if (item is maxWidthItem_) { maxWidthItem_ = null; maxWidth_ = 0; }
    }

    /// item a is being replaced by item b.
    protected void replacing(Object a, Object b)
    {
        redrawLine(a);
        if (a is selection_) selection_ = b;
        if (a is top_) top_ = b;
        if (a is maxWidthItem_) { maxWidthItem_ = null; maxWidth_ = 0; }
    }

    /// items a and b are being swapped.
    protected void swapping(Object a, Object b)
    {
        redrawLine(a);
        redrawLine(b);
        if (a is selection_) selection_ = b;
        else if (b is selection_) selection_ = a;
        if (a is top_) top_ = b;
        else if (b is top_) top_ = a;
    }

    /// item b is being inserted near a.
    protected void inserting(Object a, Object b)
    {
        if (displayed(a)) redrawLines();
        if (a is top_) top_ = b;
    }

    /// True if item is currently displayed (visible in the window).
    protected bool displayed(Object item) const
    {
        int X, Y, W, H;
        bbox(X, Y, W, H);
        int yy = H + offset_;
        for (Object l = cast(Object) top_; l !is null && yy > 0; l = itemNext(l))
        {
            if (l is item) return true;
            yy -= itemHeight(l) + linespacing();
        }
        return false;
    }

    /// Minimal-update redraw: contents of item changed, not its height.
    protected void redrawLine(Object item)
    {
        if (redraw1_ is null || redraw1_ is item) { redraw1_ = item; damage(damageExpose); }
        else if (redraw2_ is null || redraw2_ is item) { redraw2_ = item; damage(damageExpose); }
        else damage(damageScroll);
    }

    /// Causes the entire list to be redrawn.
    protected void redrawLines() { damage(damageScroll); }

    /// Bounding box for the interior of the list's display window,
    /// inside the scrollbars.
    protected void bbox(out int X, out int Y, out int W, out int H) const
    {
        int scrollsize = scrollbarSize_ ? scrollbarSize_ : fl.core.scrollbarSize();
        Boxtype b = box() ? box() : Boxtype.downBox;
        X = x() + fl.core.boxDx(b);
        Y = y() + fl.core.boxDy(b);
        W = w() - fl.core.boxDw(b);
        H = h() - fl.core.boxDh(b);
        if (scrollbar.visible())
        {
            W -= scrollsize;
            if (scrollbar.alignment() & alignLeft) X += scrollsize;
        }
        if (W < 0) W = 0;
        if (hscrollbar.visible())
        {
            H -= scrollsize;
            if (scrollbar.alignment() & alignTop) Y += scrollsize;
        }
        if (H < 0) H = 0;
    }

    /// X position of the left edge of the list area, past the
    /// scrollbar/border, if any.
    protected int leftedge() const
    {
        int X, Y, W, H;
        bbox(X, Y, W, H);
        return X;
    }

    /// Item under mouse y position ypos, or null.
    protected Object findItem(int ypos)
    {
        updateTop();
        int X, Y, W, H;
        bbox(X, Y, W, H);
        int yy = Y - offset_;
        for (Object l = top_; l !is null; l = itemNext(l))
        {
            int hh = itemHeight(l);
            if (hh <= 0) continue;
            yy += hh + linespacing();
            if (ypos <= yy || yy >= (Y + H)) return l;
        }
        return null;
    }

    // Figure out top_ based on position_.
    private void updateTop()
    {
        if (top_ is null) top_ = itemFirst();
        if (position_ == realPosition_) return;

        Object l;
        int ly;
        int yy = position_;
        if (top_ is null || yy <= (realPosition_ / 2))
        {
            l = itemFirst();
            ly = 0;
        }
        else
        {
            l = top_;
            ly = realPosition_ - offset_;
        }
        if (l is null)
        {
            top_ = null;
            offset_ = 0;
            realPosition_ = 0;
        }
        else
        {
            int hh = itemQuickHeight(l) + linespacing();
            while (ly > yy)
            {
                Object l1 = itemPrev(l);
                if (l1 is null) { ly = 0; break; }
                l = l1;
                hh = itemQuickHeight(l) + linespacing();
                ly -= hh;
            }
            while ((ly + hh) <= yy)
            {
                Object l1 = itemNext(l);
                if (l1 is null) { yy = ly + hh - 1; break; }
                l = l1;
                ly += hh;
                hh = itemQuickHeight(l) + linespacing();
            }
            for (;;)
            {
                hh = itemHeight(l) + linespacing();
                if ((ly + hh) > yy) break;
                Object l1 = itemPrev(l);
                if (l1 is null) { ly = yy = 0; break; }
                l = l1;
                yy = position_ = ly = ly - itemQuickHeight(l) + linespacing();
            }
            top_ = l;
            offset_ = yy - ly;
            realPosition_ = yy;
        }
        damage(damageScroll);
    }

    // ----------------------------------------------------------------
    // Public API
    // ----------------------------------------------------------------

    /// Vertical scroll position, in pixels scrolled off the top.
    int vposition() const { return position_; }
    /// ditto
    void vposition(int pos)
    {
        if (pos < 0) pos = 0;
        if (pos == position_) return;
        position_ = pos;
        if (pos != realPosition_) redrawLines();
    }

    /// Horizontal scroll position, in pixels scrolled off the left.
    int hposition() const { return hposition_; }
    /// ditto
    void hposition(int pos)
    {
        if (pos < 0) pos = 0;
        if (pos == hposition_) return;
        hposition_ = pos;
        if (pos != realHposition_) redrawLines();
    }

    /// Scrolls the list so item is shown.
    void display(Object item)
    {
        updateTop();
        if (item is itemFirst()) { vposition(0); return; }

        int X, Y, W, H, Yp;
        bbox(X, Y, W, H);
        Object l = top_;
        Y = Yp = -offset_;
        int h1;

        if (l is item) { vposition(realPosition_ + Y); return; }

        Object lp = itemPrev(l);
        if (lp is item) { vposition(realPosition_ + Y - itemQuickHeight(lp) - linespacing()); return; }

        // Search both up and down the list at once -- evens up the
        // execution time for the two cases.
        while (l !is null || lp !is null)
        {
            if (l !is null)
            {
                h1 = itemQuickHeight(l) + linespacing();
                if (l is item)
                {
                    if (Y <= H)
                    {
                        Y = Y + h1 - H;
                        if (Y > 0) vposition(realPosition_ + Y);
                    }
                    else
                    {
                        vposition(realPosition_ + Y - (H - h1) / 2);
                    }
                    return;
                }
                Y += h1;
                l = itemNext(l);
            }
            if (lp !is null)
            {
                h1 = itemQuickHeight(lp) + linespacing();
                Yp -= h1;
                if (lp is item)
                {
                    if ((Yp + h1) >= 0) vposition(realPosition_ + Yp);
                    else vposition(realPosition_ + Yp - (H - h1) / 2);
                    return;
                }
                lp = itemPrev(lp);
            }
        }
    }

    /// Scrollbar mode: see browserHorizontal/browserVertical/
    /// browserBoth/browserAlwaysOn and combinations.
    ubyte hasScrollbar() const { return hasScrollbar_; }
    void hasScrollbar(ubyte mode) { hasScrollbar_ = mode; } /// ditto

    Font textfont() const { return textfont_; }
    void textfont(Font f) { textfont_ = f; } /// ditto

    Fontsize textsize() const { return textsize_; }
    void textsize(Fontsize s) { textsize_ = s; } /// ditto

    Color textcolor() const { return textcolor_; }
    void textcolor(Color c) { textcolor_ = c; } /// ditto

    /// Size (in pixels) of the scrollbars' troughs, or 0 to track the
    /// global fl.core.scrollbarSize().
    int scrollbarSize() const { return scrollbarSize_; }
    void scrollbarSize(int newSize) { scrollbarSize_ = newSize; } /// ditto

    /// Moves the vertical scrollbar to the righthand side.
    void scrollbarRight() { scrollbar.alignment(alignRight); }
    /// Moves the vertical scrollbar to the lefthand side.
    void scrollbarLeft() { scrollbar.alignment(alignLeft); }

    /// Additional pixels of spacing between browser lines.
    void linespacing(int pixels) { linespacing_ = pixels; }
    int linespacing() const { return linespacing_; } /// ditto

    /// Sets the selection state of item; returns true if it changed.
    int select(Object item, int val = 1, int docallbacks = 0)
    {
        if (type() == multiBrowser)
        {
            if (selection_ !is item)
            {
                if (selection_ !is null) redrawLine(selection_);
                selection_ = item;
                redrawLine(item);
            }
            if ((!val) == (!itemSelected(item))) return 0;
            itemSelect(item, val);
            redrawLine(item);
        }
        else
        {
            if (val && selection_ is item) return 0;
            if (!val && selection_ !is item) return 0;
            if (selection_ !is null)
            {
                itemSelect(selection_, 0);
                redrawLine(selection_);
                selection_ = null;
            }
            if (val)
            {
                itemSelect(item, 1);
                selection_ = item;
                redrawLine(item);
                display(item);
            }
        }
        if (docallbacks)
        {
            setChanged();
            doCallback(CallbackReason.changed);
        }
        return 1;
    }

    /// Deselects all items; returns true if the state changed.
    int deselect(int docallbacks = 0)
    {
        if (type() == multiBrowser)
        {
            int change = 0;
            for (Object p = itemFirst(); p !is null; p = itemNext(p))
                change |= select(p, 0, docallbacks);
            return change;
        }
        else
        {
            if (selection_ is null) return 0;
            itemSelect(selection_, 0);
            redrawLine(selection_);
            selection_ = null;
            if (docallbacks)
            {
                setChanged();
                doCallback(CallbackReason.changed);
            }
            return 1;
        }
    }

    /// Selects only item, deselecting everything else.
    int selectOnly(Object item, int docallbacks = 0)
    {
        if (item is null) return deselect(docallbacks);
        int change = 0;
        auto wp = WidgetTracker(this);
        if (type() == multiBrowser)
        {
            for (Object p = itemFirst(); p !is null; p = itemNext(p))
            {
                if (p !is item) change |= select(p, 0, docallbacks);
                if (wp.deleted()) return change;
            }
        }
        change |= select(item, 1, docallbacks);
        if (wp.deleted()) return change;
        display(item);
        return change;
    }

    /// Sort the items based on flags (sortAscending/sortDescending,
    /// optionally |sortCaseInsensitive). itemSwap()/itemText() must be
    /// implemented by the subclass. Simple bubble sort, matching
    /// FLTK's own admittedly-lazy implementation verbatim.
    void sort(int flags = 0)
    {
        int n = -1;
        bool desc = (flags & sortDescending) == sortDescending;
        bool caseinsensitive = (flags & sortCaseInsensitive) != 0;
        Object a = itemFirst();
        if (a is null) return;
        while (a !is null) { a = itemNext(a); n++; }

        for (int i = n; i > 0; i--)
        {
            bool swapped = false;
            a = itemFirst();
            Object b = itemNext(a);
            for (int j = 0; j < i; j++)
            {
                const(char)[] ta = itemText(a);
                const(char)[] tb = itemText(b);
                Object c = itemNext(b);
                int order = caseinsensitive ? sicmp(ta, tb) : cmp(ta, tb);
                if (desc ? (order < 0) : (order > 0))
                {
                    itemSwap(a, b);
                    swapped = true;
                }
                if (c is null) break;
                b = c;
                a = itemPrev(b);
            }
            if (!swapped) break;
        }
    }

    override void resize(int X, int Y, int W, int H)
    {
        int scrollsize = scrollbarSize_ ? scrollbarSize_ : fl.core.scrollbarSize();
        resizeBoundsOnly(X, Y, W, H);
        int bx, by, bw, bh;
        bbox(bx, by, bw, bh);
        scrollbar.resize(
            (scrollbar.alignment() & alignLeft) ? bx - scrollsize : bx + bw,
            by, scrollsize, bh);
        hscrollbar.resize(
            bx, (scrollbar.alignment() & alignTop) ? by - scrollsize : by + bh,
            bw, scrollsize);
        maxWidth_ = 0;
    }

    override void draw()
    {
        bool drawsquare = false;
        updateTop();
        int fullWidth_ = fullWidth();
        int fullHeight_ = fullHeight();
        int X, Y, W, H;
        bbox(X, Y, W, H);
        bool dontRepeat = false;

        while (true)
        {
            Damage d0 = damage();
            if (d0 & damageAll)
            {
                Boxtype b = box() ? box() : Boxtype.downBox;
                drawBox(b, x(), y(), w(), h(), color());
                drawsquare = true;
            }

            if ((hasScrollbar_ & browserVertical) &&
                ((hasScrollbar_ & browserAlwaysOn) || position_ || fullHeight_ > H))
            {
                if (!scrollbar.visible())
                {
                    scrollbar.setVisible();
                    drawsquare = true;
                    bbox(X, Y, W, H);
                }
            }
            else
            {
                top_ = itemFirst();
                realPosition_ = offset_ = 0;
                if (scrollbar.visible())
                {
                    scrollbar.clearVisible();
                    clearDamage(damage() | damageScroll);
                }
            }

            if ((hasScrollbar_ & browserHorizontal) &&
                ((hasScrollbar_ & browserAlwaysOn) || hposition_ || fullWidth_ > W))
            {
                if (!hscrollbar.visible())
                {
                    hscrollbar.setVisible();
                    drawsquare = true;
                    bbox(X, Y, W, H);
                }
            }
            else
            {
                realHposition_ = 0;
                if (hscrollbar.visible())
                {
                    hscrollbar.clearVisible();
                    clearDamage(damage() | damageScroll);
                }
            }

            // Re-check the vertical scrollbar in case the horizontal
            // one being drawn changed the available height.
            if ((hasScrollbar_ & browserVertical) &&
                ((hasScrollbar_ & browserAlwaysOn) || position_ || fullHeight_ > H))
            {
                if (!scrollbar.visible())
                {
                    scrollbar.setVisible();
                    drawsquare = true;
                    bbox(X, Y, W, H);
                }
            }
            else
            {
                top_ = itemFirst();
                realPosition_ = offset_ = 0;
                if (scrollbar.visible())
                {
                    scrollbar.clearVisible();
                    clearDamage(damage() | damageScroll);
                }
            }

            bbox(X, Y, W, H);

            fldraw.pushClip(X, Y, W, H);
            Object l = top();
            int yy = -offset_;
            for (; l !is null && yy < H; l = itemNext(l))
            {
                int hh = itemHeight(l) + linespacing();
                if (hh <= 0) continue;
                if ((damage() & (damageScroll | damageAll)) || l is redraw1_ || l is redraw2_)
                {
                    if (itemSelected(l))
                    {
                        fldraw.fl_color(activeR() ? selectionColor() : fldraw.inactive(selectionColor()));
                        fldraw.fl_rectf(X, yy + Y, W, hh);
                    }
                    else if (!(damage() & damageAll))
                    {
                        fldraw.pushClip(X, yy + Y, W, hh);
                        drawBox(box() ? box() : Boxtype.downBox, x(), y(), w(), h(), color());
                        fldraw.popClip();
                    }
                    itemDraw(l, X - hposition_, yy + Y, W + hposition_, hh);
                    if (l is selection_ && fl.core.focus() is this)
                    {
                        drawBox(Boxtype.borderFrame, X, yy + Y, W, hh, color());
                        drawFocus(Boxtype.noBox, X, yy + Y, W + 1, hh + 1);
                    }
                    int ww = itemWidth(l);
                    if (ww > maxWidth_) { maxWidth_ = ww; maxWidthItem_ = l; }
                }
                yy += hh;
            }
            if (!(damage() & damageAll) && yy < H)
            {
                fldraw.pushClip(X, yy + Y, W, H - yy);
                drawBox(box() ? box() : Boxtype.downBox, x(), y(), w(), h(), color());
                fldraw.popClip();
            }
            fldraw.popClip();

            fldraw.pushClip(x(), y(), w(), h());
            redraw1_ = redraw2_ = null;

            bool again = false;
            if (!dontRepeat)
            {
                dontRepeat = true;
                fullHeight_ = fullHeight();
                fullWidth_ = fullWidth();
                if ((hasScrollbar_ & browserVertical) &&
                    ((hasScrollbar_ & browserAlwaysOn) || position_ || fullHeight_ > H))
                {
                    if (!scrollbar.visible()) { damage(damageAll); fldraw.popClip(); again = true; }
                }
                else
                {
                    if (scrollbar.visible()) { damage(damageAll); fldraw.popClip(); again = true; }
                }
                if (!again)
                {
                    if ((hasScrollbar_ & browserHorizontal) &&
                        ((hasScrollbar_ & browserAlwaysOn) || hposition_ || fullWidth_ > W))
                    {
                        if (!hscrollbar.visible()) { damage(damageAll); fldraw.popClip(); again = true; }
                    }
                    else
                    {
                        if (hscrollbar.visible()) { damage(damageAll); fldraw.popClip(); again = true; }
                    }
                }
            }
            if (again) continue;

            int scrollsize = scrollbarSize_ ? scrollbarSize_ : fl.core.scrollbarSize();
            int dy = top_ !is null ? itemQuickHeight(top_) + linespacing() : 0;
            if (dy < 10) dy = 10;
            if (scrollbar.visible())
            {
                scrollbar.damageResize(
                    (scrollbar.alignment() & alignLeft) ? X - scrollsize : X + W,
                    Y, scrollsize, H);
                scrollbar.value(position_, H, 0, fullHeight_);
                scrollbar.linesize(dy);
                if (drawsquare) drawChild(scrollbar); else updateChild(scrollbar);
            }
            if (hscrollbar.visible())
            {
                hscrollbar.damageResize(
                    X, (scrollbar.alignment() & alignTop) ? Y - scrollsize : Y + H,
                    W, scrollsize);
                hscrollbar.value(hposition_, W, 0, fullWidth_);
                hscrollbar.linesize(dy);
                if (drawsquare) drawChild(hscrollbar); else updateChild(hscrollbar);
            }

            if (drawsquare && scrollbar.visible() && hscrollbar.visible())
            {
                fldraw.fl_color(parent().color());
                fldraw.fl_rectf(scrollbar.x(), hscrollbar.y(), scrollsize, scrollsize);
            }

            realHposition_ = hposition_;
            fldraw.popClip();
            break;
        }
    }

    override int handle(Event event)
    {
        auto wp = WidgetTracker(this);

        if (event == Event.enter || event == Event.leave) return 1;
        if (event == Event.keyDown && type() >= holdBrowser)
        {
            Object l = selection_;
            if (l is null) l = top_;
            if (l is null) l = itemFirst();
            if (l !is null)
            {
                if (type() == holdBrowser)
                {
                    if (fl.core.eventKey() == down)
                    {
                        if (selection_ !is null) l = itemNext(selection_);
                        while (l !is null)
                        {
                            if (itemHeight(l) > 0) { selectOnly(l, when() & ~whenNotChanged); break; }
                            l = itemNext(l);
                        }
                        return 1;
                    }
                    else if (fl.core.eventKey() == up)
                    {
                        if (selection_ !is null)
                            l = itemPrev(selection_);
                        else
                        {
                            l = findItem(y() + h() - incrHeight() / 2);
                            if (l is null) l = itemLast();
                        }
                        while (l !is null)
                        {
                            if (itemHeight(l) > 0) { selectOnly(l, when() & ~whenNotChanged); break; }
                            l = itemPrev(l);
                        }
                        return 1;
                    }
                }
                else
                {
                    if (fl.core.eventKey() == enter || fl.core.eventKey() == kpEnter)
                    {
                        selectOnly(l, when() & ~whenEnterKey);
                        if (wp.deleted()) return 1;
                        if (when() & whenEnterKey)
                        {
                            setChanged();
                            doCallback(CallbackReason.changed);
                        }
                        return 1;
                    }
                    else if (fl.core.eventKey() == ' ')
                    {
                        selection_ = l;
                        select(l, !itemSelected(l), when() & ~whenEnterKey);
                        return 1;
                    }
                    else if (fl.core.eventKey() == down)
                    {
                        while ((l = itemNext(l)) !is null)
                        {
                            if (fl.core.eventState(stateShift | stateCtrl))
                                select(l, selection_ !is null ? itemSelected(selection_) : 1, when());
                            if (wp.deleted()) return 1;
                            if (itemHeight(l) > 0) goto foundDown;
                        }
                        return 1;
                    foundDown:
                        if (selection_ !is null) redrawLine(selection_);
                        selection_ = l;
                        redrawLine(l);
                        display(l);
                        return 1;
                    }
                    else if (fl.core.eventKey() == up)
                    {
                        while ((l = itemPrev(l)) !is null)
                        {
                            if (fl.core.eventState(stateShift | stateCtrl))
                                select(l, selection_ !is null ? itemSelected(selection_) : 1, when());
                            if (wp.deleted()) return 1;
                            if (itemHeight(l) > 0) goto foundUp;
                        }
                        return 1;
                    foundUp:
                        if (selection_ !is null) redrawLine(selection_);
                        selection_ = l;
                        redrawLine(l);
                        display(l);
                        return 1;
                    }
                }
            }
        }

        if (super.handle(event)) return 1;
        if (wp.deleted()) return 1;

        int X, Y, W, H;
        bbox(X, Y, W, H);
        int my;

        switch (event)
        {
        case Event.push:
            if (!fl.core.eventInside(X, Y, W, H)) return 0;
            if (fl.core.visibleFocus())
            {
                fl.core.focus(this);
                redraw();
            }
            my = handlePy_ = fl.core.eventY();
            handleInitsel_ = selection_;
            handleChange_ = false;
            if (type() == normalBrowser || top_ is null)
            {
                // nothing
            }
            else if (type() != multiBrowser)
            {
                // Was `select(findItem(my), 0)` -- a mistranscription of
                // FLTK's `select_only(find_item(my), 0)`
                // (Fl_Browser_::handle()'s FL_PUSH case): `select()`'s
                // 2nd argument is `val` (1 = select, 0 = deselect), so
                // passing 0 there asked to *deselect* the clicked item,
                // which is a no-op whenever it wasn't already the
                // current selection -- i.e. on every plain click on a
                // *different* row. `selectOnly()`'s same-looking 2nd
                // argument is `docallbacks` (0 = don't fire the
                // callback yet, matching FLTK's own call here),
                // a completely different parameter for a completely
                // different function; the two just happen to share a
                // name prefix. Confirmed interactively: a quick click
                // (no drag) on a fl.file_browser/fl.browser row
                // selected nothing, while Event.drag's own handler a
                // few lines down (already correctly calling
                // selectOnly()) meant only a click-and-hold-with-motion
                // happened to work by accident.
                handleChange_ = selectOnly(findItem(my), 0) != 0;
                if (wp.deleted()) return 1;
                if (handleChange_ && (when() & whenChanged))
                {
                    setChanged();
                    doCallback(CallbackReason.changed);
                    if (wp.deleted()) return 1;
                }
            }
            else
            {
                Object l = findItem(my);
                handleWhichway_ = true;
                if (fl.core.eventState(stateCommand))
                {
                    handleWhichway_ = l !is null ? !itemSelected(l) : true;
                    if (l !is null)
                    {
                        handleChange_ = select(l, handleWhichway_ ? 1 : 0, 0) != 0;
                        if (wp.deleted()) return 1;
                        if (handleChange_ && (when() & whenChanged))
                        {
                            setChanged();
                            doCallback(CallbackReason.changed);
                            if (wp.deleted()) return 1;
                        }
                    }
                }
                else if (fl.core.eventState(stateShift))
                {
                    if (l is selection_)
                    {
                        handleWhichway_ = !itemSelected(l);
                        handleChange_ = select(l, handleWhichway_ ? 1 : 0, 0) != 0;
                        if (wp.deleted()) return 1;
                        if (handleChange_ && (when() & whenChanged))
                        {
                            setChanged();
                            doCallback(CallbackReason.changed);
                            if (wp.deleted()) return 1;
                        }
                    }
                    else
                    {
                        handleWhichway_ = l !is null ? !itemSelected(l) : true;
                        bool down_;
                        if (l is null) down_ = true;
                        else
                        {
                            down_ = false;
                            for (Object m = selection_;; m = itemNext(m))
                            {
                                if (m is l) { down_ = true; break; }
                                if (m is null) { down_ = false; break; }
                            }
                        }
                        if (down_)
                        {
                            for (Object m = selection_; m !is l; m = itemNext(m))
                            {
                                select(m, handleWhichway_ ? 1 : 0, when() & whenChanged);
                                if (wp.deleted()) return 1;
                            }
                        }
                        else
                        {
                            Object e = selection_;
                            for (Object m = itemNext(l); m !is null; m = itemNext(m))
                            {
                                select(m, handleWhichway_ ? 1 : 0, when() & whenChanged);
                                if (wp.deleted()) return 1;
                                if (m is e) break;
                            }
                        }
                        handleChange_ = true;
                        if (l !is null) select(l, handleWhichway_ ? 1 : 0, when() & whenChanged);
                        if (wp.deleted()) return 1;
                    }
                }
                else
                {
                    handleChange_ = selectOnly(l, 0) != 0;
                    if (wp.deleted()) return 1;
                    if (handleChange_ && (when() & whenChanged))
                    {
                        setChanged();
                        doCallback(CallbackReason.changed);
                        if (wp.deleted()) return 1;
                    }
                }
            }
            return 1;

        case Event.drag:
            my = fl.core.eventY();
            if (my < Y && my < handlePy_)
            {
                int p = realPosition_ + my - Y;
                if (p < 0) p = 0;
                vposition(p);
            }
            else if (my > (Y + H) && my > handlePy_)
            {
                int p = realPosition_ + my - (Y + H);
                int hh = fullHeight() - H;
                if (p > hh) p = hh;
                if (p < 0) p = 0;
                vposition(p);
            }
            if (type() == normalBrowser || top_ is null)
            {
                // nothing
            }
            else if (type() == multiBrowser)
            {
                Object l = findItem(my);
                Object t, b;
                if (my > handlePy_)
                {
                    t = selection_ !is null ? itemNext(selection_) : null;
                    b = l !is null ? itemNext(l) : null;
                }
                else
                {
                    t = l;
                    b = selection_;
                }
                for (; t !is null && t !is b; t = itemNext(t))
                {
                    bool changeT = select(t, handleWhichway_ ? 1 : 0, 0) != 0;
                    if (wp.deleted()) return 1;
                    handleChange_ |= changeT;
                    if (changeT && (when() & whenChanged))
                    {
                        setChanged();
                        doCallback(CallbackReason.changed);
                        if (wp.deleted()) return 1;
                    }
                }
                if (l !is null) selection_ = l;
            }
            else
            {
                Object l = (fl.core.eventX() < x() || fl.core.eventX() > x() + w())
                    ? selection_ : findItem(my);
                handleChange_ = l !is handleInitsel_;
                selectOnly(l, when() & whenChanged);
                if (wp.deleted()) return 1;
            }
            handlePy_ = my;
            return 1;

        case Event.release:
            if (type() == selectBrowser)
            {
                Object t = selection_;
                deselect();
                if (wp.deleted()) return 1;
                selection_ = t;
            }
            if (handleChange_)
            {
                setChanged();
                if (when() & whenRelease) doCallback(CallbackReason.changed);
            }
            else
            {
                if (when() & whenNotChanged) doCallback(CallbackReason.reselected);
            }
            if (wp.deleted()) return 1;

            if (fl.core.eventClicks() && (when() & whenEnterKey))
            {
                setChanged();
                doCallback(CallbackReason.changed);
            }
            return 1;

        case Event.focus:
        case Event.unfocus:
            if (type() >= holdBrowser && fl.core.visibleFocus())
            {
                redraw();
                return 1;
            }
            return 0;

        default:
            break;
        }

        return 0;
    }
}

version (unittest)
{
    // Minimal concrete test double: a simple doubly-linked list of
    // fixed-height/width items, just enough to exercise Browser_'s own
    // scrolling/selection logic in isolation from fl.browser's much
    // larger text-formatting machinery.
    private final class TItem
    {
        TItem prev, next;
        string text;
        this(string t) { text = t; }
    }

    private final class TBrowser : Browser_
    {
        TItem first_, last_;

        this(int x, int y, int w, int h) { super(x, y, w, h); }

        void append(string text)
        {
            auto it = new TItem(text);
            if (last_ is null) { first_ = last_ = it; }
            else { it.prev = last_; last_.next = it; last_ = it; }
        }

        protected override Object itemFirst() const { return cast(Object) first_; }
        protected override Object itemNext(Object item) const { return cast(Object)(cast(TItem) item).next; }
        protected override Object itemPrev(Object item) const { return cast(Object)(cast(TItem) item).prev; }
        protected override Object itemLast() const { return cast(Object) last_; }
        protected override int itemHeight(Object item) const { return 20; }
        protected override int itemWidth(Object item) const { return 100; }
        protected override void itemDraw(Object item, int X, int Y, int W, int H) const { }
        protected override const(char)[] itemText(Object item) const { return (cast(TItem) item).text; }
        protected override void itemSwap(Object a, Object b)
        {
            auto ta = cast(TItem) a;
            auto tb = cast(TItem) b;
            auto tmp = ta.text;
            ta.text = tb.text;
            tb.text = tmp;
        }

        // Multi-selection support, mirroring fl.browser's BLINE flag.
        private bool[TItem] selected_;
        protected override void itemSelect(Object item, int val = 1)
        {
            auto t = cast(TItem) item;
            if (val) selected_[t] = true; else selected_.remove(t);
        }
        protected override int itemSelected(Object item) const
        {
            auto t = cast(TItem) item;
            return (t in cast(bool[TItem]) selected_) ? 1 : 0;
        }
    }
}

unittest
{
    FlGroup.current(null);
    auto b = new TBrowser(0, 0, 100, 100);
    b.end();

    assert(b.box() == Boxtype.noBox);
    assert(b.type() == normalBrowser);
    assert(b.when() == whenReleaseAlways);
    assert(b.hasScrollbar() == browserBoth);
    assert(b.textfont() == helvetica);
    assert(b.textsize() == normalSize);
    assert(b.children() == 2); // just the two scrollbars

    FlGroup.current(null);
}

unittest
{
    // select()/deselect()/selectOnly() on a single-selection (default,
    // non-multi) browser.
    FlGroup.current(null);
    auto b = new TBrowser(0, 0, 100, 100);
    b.append("one");
    b.append("two");
    b.append("three");
    b.end();

    Object a = b.itemFirst();
    Object c = b.itemNext(a);

    assert(b.select(a) == 1);
    assert(b.itemSelected(a) == 1);
    assert(b.selection() is a);

    // Selecting a different item deselects the first (single-select).
    assert(b.select(c) == 1);
    assert(b.itemSelected(a) == 0);
    assert(b.itemSelected(c) == 1);

    assert(b.deselect() == 1);
    assert(b.itemSelected(c) == 0);
    assert(b.selection() is null);

    FlGroup.current(null);
}

unittest
{
    // Multi-selection browser: select() adds without clearing others.
    FlGroup.current(null);
    auto b = new TBrowser(0, 0, 100, 100);
    b.append("one");
    b.append("two");
    b.type(multiBrowser);
    b.end();

    Object a = b.itemFirst();
    Object c = b.itemNext(a);

    b.select(a);
    b.select(c);
    assert(b.itemSelected(a) == 1);
    assert(b.itemSelected(c) == 1);

    // selectOnly() clears everything else first.
    b.selectOnly(a);
    assert(b.itemSelected(a) == 1);
    assert(b.itemSelected(c) == 0);

    FlGroup.current(null);
}

unittest
{
    // vposition()/hposition() clamp negative values to 0 and are
    // no-ops when unchanged.
    FlGroup.current(null);
    auto b = new TBrowser(0, 0, 100, 100);
    b.end();

    b.vposition(-5);
    assert(b.vposition() == 0);
    b.vposition(42);
    assert(b.vposition() == 42);

    b.hposition(-3);
    assert(b.hposition() == 0);
    b.hposition(17);
    assert(b.hposition() == 17);

    FlGroup.current(null);
}

unittest
{
    // sort() in ascending/descending order using itemSwap()/itemText().
    FlGroup.current(null);
    auto b = new TBrowser(0, 0, 100, 100);
    b.append("banana");
    b.append("apple");
    b.append("cherry");
    b.end();

    b.sort(sortAscending);
    Object p = b.itemFirst();
    assert(b.itemText(p) == "apple");
    p = b.itemNext(p);
    assert(b.itemText(p) == "banana");
    p = b.itemNext(p);
    assert(b.itemText(p) == "cherry");

    b.sort(sortDescending);
    p = b.itemFirst();
    assert(b.itemText(p) == "cherry");
    p = b.itemNext(p);
    assert(b.itemText(p) == "banana");
    p = b.itemNext(p);
    assert(b.itemText(p) == "apple");

    FlGroup.current(null);
}

unittest
{
    // draw()/handle() exercise fl.draw's real-on-Linux-only primitives
    // and fl.core's event-state globals; just confirm no exception,
    // matching the established pattern for every other widget's draw()
    // unittest in this port.
    FlGroup.current(null);
    auto b = new TBrowser(0, 0, 100, 100);
    b.append("one");
    b.append("two");
    b.end();
    b.draw();

    assert(b.handle(Event.enter) == 1);
    assert(b.handle(Event.leave) == 1);

    fl.core.resetForTest();
    FlGroup.current(null);
}
