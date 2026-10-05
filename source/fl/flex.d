/*
 * Ported from FL/Fl_Flex.H + src/Fl_Flex.cxx (FLTK 1.5.0). "A container (layout) widget for one row or
 * one column of widgets" (FLTK's own doc comment): every
 * non-fixed-size child shares the remaining space evenly along the
 * row/column axis, and is stretched to the full cross-axis size (minus
 * margins/box insets). FLTK positions it as the 1.4+ recommended
 * replacement for `fl.pack.Pack` -- more predictable sizing, since it
 * doesn't shrink-wrap itself around its children the way Pack does.
 *
 * Faithful, complete port of init()/draw()/resize()/layout()/end()/
 * fixed()/margin()/gap(), including the "resize the widget via
 * Widget.resizeBoundsOnly() then relayout, bypassing Fl_Group's own
 * child-layout algorithm" pattern already established by fl.pack (see
 * that module's and Widget.resizeBoundsOnly()'s doc comments for the
 * full explanation of why D needs a dedicated helper for this C++-only
 * explicit-base-qualification idiom).
 *
 * One deliberate simplification: FLTK's `fixed_size_` is a raw
 * `Fl_Widget**` grown by hand (`fixed_size_alloc_`/`realloc()`/
 * `alloc_size()` -- the last one a virtual hook purely so a subclass
 * can override the growth strategy). A D `Widget[]` dynamic array
 * already has amortized growth built into the runtime, so none of
 * that bookkeeping -- including the `alloc_size()` customization
 * point, which would have nothing left to customize -- is ported; see
 * CONVENTIONS.md's "check for a cleaner D stdlib alternative" convention.
 * Similarly, FLTK's `fixed(Fl_Widget&, int)` inline overload
 * exists only so C++ callers can pass either a reference or a
 * pointer; D references are already reference types, so there's only
 * one `fixed(Widget, int)` here (same collapse CONVENTIONS.md documents for
 * `Fl_Callback` vs. D delegates).
 */
module fl.flex;

import std.algorithm.searching : canFind, countUntil;

import fl.group : FlGroup;
import fl.widget : Widget;
import fl.enumerations : Boxtype;
import fl.core;

/// type() for a single column (the default, for consistency with
/// fl.pack.Pack).
enum ubyte flexVertical = 0;
/// type() for a single row.
enum ubyte flexHorizontal = 1;
/// Alias for flexVertical.
enum ubyte flexColumn = flexVertical;
/// Alias for flexHorizontal.
enum ubyte flexRow = flexHorizontal;

class Flex : FlGroup
{
    private
    {
        int marginLeft_, marginTop_, marginRight_, marginBottom_;
        int gap_;
        Widget[] fixedSize_;
        bool needLayout_;
    }

    /// The FLTK-standard constructor. The default type() is
    /// flexVertical (a single column); use type(flexHorizontal) or the
    /// direction-taking constructors below for a row.
    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        init(flexVertical);
    }

    /// Position and size (0,0,0,0) -- suitable for a nested Flex whose
    /// real bounds come from its own parent's layout.
    this(ubyte direction)
    {
        super(0, 0, 0, 0, null);
        init(direction);
    }

    /// Position (0,0) -- suitable for a nested Flex.
    this(int w, int h, ubyte direction)
    {
        super(0, 0, w, h, null);
        init(direction);
    }

    /// Explicit position, size, and direction; no label (use label()
    /// afterward if one is needed).
    this(int x, int y, int w, int h, ubyte direction)
    {
        super(x, y, w, h, null);
        init(direction);
    }

    protected void init(ubyte t = flexVertical)
    {
        marginLeft_ = marginTop_ = marginRight_ = marginBottom_ = 0;
        gap_ = 0;
        fixedSize_ = [];
        needLayout_ = false;

        // Matches FLTK exactly: always set horizontal first, then
        // only override to vertical for the *exact* value flexVertical
        // -- any other (invalid) value ends up flexHorizontal, not a
        // plain `type(t)`.
        type(flexHorizontal);
        if (t == flexVertical) type(flexVertical);
    }

    /// Set or reset the request to recalculate layout before the next
    /// draw(). Normally internal -- attribute/gap/margin setters and
    /// resize() already call this; use it directly only if you change
    /// child sizes/visibility without going through those.
    void needLayout(bool set) { needLayout_ = set; }
    /// Whether layout() needs to run before the next draw().
    bool needLayout() const { return needLayout_; }

    override void draw()
    {
        if (needLayout()) layout();
        super.draw();
    }

    /// Resizing a Flex recalculates every child's position/size (see
    /// layout()), rather than Fl_Group's proportional child-scaling
    /// algorithm.
    override void resize(int x, int y, int w, int h)
    {
        resizeBoundsOnly(x, y, w, h);
        layout();
    }

    override void end()
    {
        super.end();
        needLayout(1);
    }

    protected override void onRemove(int index)
    {
        fixed(child(index), 0);
        needLayout(1);
    }

    /// Returns the left margin (the free space inside the box frame,
    /// around all children, on that side). Useful only if every margin
    /// is the same size; see the 4-out-param overload otherwise.
    int margin() const { return marginLeft_; }

    /// Reports every margin size via the (required, individually
    /// nullable) out params, and returns whether all four are equal.
    bool margin(int* left, int* top, int* right, int* bottom) const
    {
        if (left) *left = marginLeft_;
        if (top) *top = marginTop_;
        if (right) *right = marginRight_;
        if (bottom) *bottom = marginBottom_;
        return marginLeft_ == marginTop_ && marginTop_ == marginRight_
            && marginRight_ == marginBottom_;
    }

    /// Sets all four margins to m (clamped to >= 0), and optionally the
    /// gap size too (g < 0, the default, leaves it unchanged).
    void margin(int m, int g = -1)
    {
        if (m < 0) m = 0;
        marginLeft_ = marginTop_ = marginRight_ = marginBottom_ = m;
        if (g >= 0) gap_ = g;
        needLayout(1);
    }

    /// Sets each margin independently (each clamped to >= 0).
    void margin(int left, int top, int right, int bottom)
    {
        marginLeft_ = left < 0 ? 0 : left;
        marginTop_ = top < 0 ? 0 : top;
        marginRight_ = right < 0 ? 0 : right;
        marginBottom_ = bottom < 0 ? 0 : bottom;
        needLayout(1);
    }

    /// Free space between children (same concept as fl.pack.Pack's
    /// spacing() -- spacing()/gap() are interchangeable names for it,
    /// kept both so Flex can be a drop-in Pack replacement).
    int gap() const { return gap_; }
    /// ditto
    void gap(int g)
    {
        gap_ = g < 0 ? 0 : g;
        needLayout(1);
    }
    /// ditto
    int spacing() const { return gap_; }
    /// ditto
    void spacing(int i)
    {
        gap(i);
        needLayout(1);
    }

    /// True if type() == flexHorizontal (a row); false for a column.
    bool horizontal() const { return type() == flexHorizontal; }

    /// Gives child a fixed width (flexHorizontal) or height
    /// (flexVertical) instead of sharing the remaining space evenly
    /// with the other non-fixed children. size <= 0 resets it back to
    /// flexible.
    void fixed(Widget child, int size)
    {
        if (size <= 0) size = 0;

        auto idx = fixedSize_.countUntil(child);

        if (size == 0 && idx >= 0)
        {
            fixedSize_ = fixedSize_[0 .. idx] ~ fixedSize_[idx + 1 .. $];
            needLayout(1);
            return;
        }
        if (size == 0) return;

        if (idx == -1)
            fixedSize_ ~= child;

        if (horizontal())
            child.size(size, h() - marginTop_ - marginBottom_ - fl.core.boxDh(box()));
        else
            child.size(w() - marginLeft_ - marginRight_ - fl.core.boxDw(box()), size);
        needLayout(1);
    }

    /// Whether child has a fixed size (set via fixed(child, size))
    /// rather than sharing the remaining space dynamically.
    bool fixed(const(Widget) child) const
    {
        return fixedSize_.canFind(child);
    }

    /// Recalculates every child's position/size along the row/column
    /// axis and redraws. Call this directly only if you changed
    /// children (add/remove/hide/show) without going through end() or
    /// a setter that already calls needLayout(1) -- draw() calls it
    /// automatically whenever needLayout() is set.
    void layout()
    {
        const int nc = children();

        int dx = fl.core.boxDx(box());
        int dy = fl.core.boxDy(box());
        int dw = fl.core.boxDw(box());
        int dh = fl.core.boxDh(box());

        int gaps = nc > 1 ? nc - 1 : 0;
        bool hori = horizontal();
        int space = hori ? (w() - dw - marginLeft_ - marginRight_)
                          : (h() - dh - marginTop_ - marginBottom_);

        int xp = x() + dx + marginLeft_;
        int yp = y() + dy + marginTop_;
        int hh = h() - dh - marginTop_ - marginBottom_; // horizontal: constant child height
        int vw = w() - dw - marginLeft_ - marginRight_; // vertical: constant child width

        int fw = nc; // number of flexible (non-fixed, visible) widgets

        for (int i = 0; i < nc; i++)
        {
            Widget c = child(i);
            if (c.visible())
            {
                if (fixed(c))
                {
                    space -= (hori ? c.w() : c.h());
                    fw--;
                }
            }
            else
            {
                fw--;
                gaps--;
            }
        }

        if (gaps > 0) space -= gaps * gap_;

        int sp = 0;  // width or height of a flexible widget
        int rem = 0; // remainder, distributed one pixel at a time
        if (fw > 0)
        {
            sp = space / fw;
            rem = space % fw;
            if (rem) sp++;
        }

        for (int i = 0; i < nc; i++)
        {
            Widget c = child(i);
            if (!c.visible()) continue;

            if (hori)
            {
                if (fixed(c))
                    c.resize(xp, yp, c.w(), hh);
                else
                {
                    c.resize(xp, yp, sp, hh);
                    if (--rem == 0) sp--;
                }
                xp += c.w() + gap_;
            }
            else
            {
                if (fixed(c))
                    c.resize(xp, yp, vw, c.h());
                else
                {
                    c.resize(xp, yp, vw, sp);
                    if (--rem == 0) sp--;
                }
                yp += c.h() + gap_;
            }
        }

        needLayout(false);
        redraw();
    }
}

// ===========================================================================
// Unit tests
// ===========================================================================

unittest
{
    import fl.box : Box;

    FlGroup.current(null);

    auto f = new Flex(0, 0, 300, 50);
    assert(f.type() == flexVertical);
    assert(f.gap() == 0 && f.margin() == 0);

    auto row = new Flex(flexRow);
    assert(row.type() == flexHorizontal);
    assert(row.x() == 0 && row.y() == 0 && row.w() == 0 && row.h() == 0);

    auto sized = new Flex(400, 30, flexHorizontal);
    assert(sized.x() == 0 && sized.y() == 0 && sized.w() == 400 && sized.h() == 30);

    auto full = new Flex(5, 5, 400, 30, flexHorizontal);
    assert(full.x() == 5 && full.y() == 5 && full.type() == flexHorizontal);

    FlGroup.current(null);
}

unittest
{
    // Horizontal layout: three flexible children share the width
    // evenly (remainder distributed one pixel at a time to the first
    // widgets), each stretched to the full height.
    import fl.box : Box;

    FlGroup.current(null);

    auto f = new Flex(0, 0, 301, 40, flexHorizontal); // 301 -> remainder 1
    auto a = new Box(0, 0, 0, 0, "a");
    auto b = new Box(0, 0, 0, 0, "b");
    auto c = new Box(0, 0, 0, 0, "c");
    f.end();
    f.layout(); // end() only requests layout (needLayout(1)); draw() would
                // normally apply it -- call directly since nothing draws here.

    // 301 / 3 = 100 rem 1 -> widths 101, 100, 100
    assert(a.x() == 0 && a.w() == 101 && a.h() == 40);
    assert(b.x() == 101 && b.w() == 100 && b.h() == 40);
    assert(c.x() == 201 && c.w() == 100 && c.h() == 40);

    FlGroup.current(null);
}

unittest
{
    // fixed() gives a child a fixed width and excludes it from the
    // even split; the example from Fl_Flex.H's own doc comment.
    import fl.box : Box;
    import fl.button : Button;

    FlGroup.current(null);

    auto flex = new Flex(5, 5, 400, 30, flexHorizontal);
    auto b1 = new Button(0, 0, 0, 0, "File");
    auto b2 = new Button(0, 0, 0, 0, "Save");
    auto bx = new Box(0, 0, 0, 0);
    auto b3 = new Button(0, 0, 0, 0, "Exit");
    flex.fixed(bx, 60);
    flex.gap(10);
    flex.end();
    flex.layout();

    assert(flex.fixed(bx));
    assert(!flex.fixed(b1));
    assert(bx.w() == 60);

    // Remaining width for 3 flexible buttons: 400 - 60 (fixed) - 3*10 (gaps) = 310 -> 103,103,104
    assert(b1.w() + b2.w() + b3.w() == 310);

    FlGroup.current(null);
}

unittest
{
    // Hidden children are skipped entirely (excluded from both the
    // flexible-widget count and the gap count).
    import fl.box : Box;

    FlGroup.current(null);

    auto f = new Flex(0, 0, 200, 40, flexHorizontal);
    auto a = new Box(0, 0, 0, 0, "a");
    auto b = new Box(0, 0, 0, 0, "b");
    f.end();
    b.hide();

    f.layout();

    assert(a.x() == 0 && a.w() == 200); // b excluded: a alone gets the full width

    FlGroup.current(null);
}

unittest
{
    // fixed(child, 0) (or removing a child) resets it back to flexible.
    import fl.box : Box;

    FlGroup.current(null);

    auto f = new Flex(0, 0, 300, 40, flexHorizontal);
    auto a = new Box(0, 0, 0, 0, "a");
    auto b = new Box(0, 0, 0, 0, "b");
    f.end();

    f.fixed(a, 50);
    assert(f.fixed(a));
    f.fixed(a, 0);
    assert(!f.fixed(a));

    f.layout();
    assert(a.w() == 150 && b.w() == 150); // back to an even split

    FlGroup.current(null);
}
