/*
 * Ported from FL/Fl_Check_Browser.H + src/Fl_Check_Browser.cxx
 * (FLTK 1.5.0, ~/Repositories/fltk).
 *
 * A scrolling list of text lines that can each be checked/unchecked
 * (a checkbox per row), plus one line at a time can be the "current"
 * highlighted selection for keyboard/mouse navigation purposes.
 * Subclasses fl.browser_.Browser_ directly (not fl.browser.Browser)
 * -- it has its own, simpler `cb_item` linked list, no
 * `'@'`-format-code markup, no columns, no icons.
 *
 * A genuinely confusing (but faithfully ported) FLTK design point,
 * worth documenting since it isn't obvious from the code alone:
 * `item_select()`/`item_selected()` don't mean what they normally mean
 * elsewhere in the Browser_ family. `cb_item.selected` is written
 * nowhere in this class at all (it's initialized false and never
 * set) -- so `itemSelected()` always returns false in practice, and
 * Browser_::draw()'s usual selection-color background fill never
 * activates for a checked/current row (only the checkbox glyph itself
 * and, when focused, a thin focus-rect outline). `itemSelect()`
 * instead *toggles* `checked` as a side effect of Browser_::select()
 * reaching this item (which happens on a mouse click or keyboard nav)
 * -- i.e., "selecting" a row in the base class's sense is repurposed
 * here to mean "flip this row's checkbox". `handle()` calls
 * `deselect()` before forwarding every `FL_PUSH` specifically so that
 * clicking the *same already-current* row twice in a row still
 * toggles it each time: `Browser_::select(item, 1)` no-ops if
 * `selection() is item` already, which would otherwise make every
 * other click on the same row silently fail to toggle its checkbox.
 *
 * `find_item(int)`/`lineno(cb_item*)` are ported as `findItemN()`/
 * `checkLineno()` rather than reusing Browser_'s own `findItem(int)`
 * name -- that name is already taken by
 * `Browser_.findItem(int ypos)` (a *pixel Y position* -> item lookup
 * used internally by mouse hit-testing) with the exact same `int ->
 * Object` signature but completely different meaning (1-based *line
 * number* -> item here). Reusing the name would make this an
 * accidental `override` that silently breaks Browser_'s own mouse
 * hit-testing via virtual dispatch -- a real footgun avoided by simply
 * not colliding on the name.
 */
module fl.check_browser;

import fl.browser_;
import fl.group : FlGroup;
import fl.enumerations;
import fl.core;
import fldraw = fl.draw;
import fl.rect : Rect;

private final class CbItem
{
    CbItem next, prev;
    bool checked;
    bool selected;
    string text;
}

class CheckBrowser : Browser_
{
    private
    {
        CbItem first_, last_, cache_;
        int cachedItem_;
        int nitems_;
        int nchecked_;
    }

    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        type(selectBrowser);
        when(whenNever);
        first_ = last_ = null;
        nitems_ = nchecked_ = 0;
        cachedItem_ = -1;
    }

    // ------------------------------------------------------------
    // Browser_ required overrides
    // ------------------------------------------------------------

    protected override Object itemFirst() const { return cast(Object) first_; }
    protected override Object itemNext(Object item) const { return cast(Object)(cast(CbItem) item).next; }
    protected override Object itemPrev(Object item) const { return cast(Object)(cast(CbItem) item).prev; }
    protected override int itemHeight(Object item) const { return textsize() + 2; }
    protected override const(char)[] itemText(Object item) const { return (cast(CbItem) item).text; }

    protected override Object itemAt(int index) const
    {
        if (index < 1 || index > nitems_) return null;
        Object item = itemFirst();
        for (int i = 1; i < index; i++) item = itemNext(item);
        return item;
    }

    private void swapImpl(CbItem ia, CbItem ib)
    {
        CbItem aNext = ia.next, aPrev = ia.prev;
        CbItem bNext = ib.next, bPrev = ib.prev;

        if (aNext is ib)
        {
            if (aPrev !is null) aPrev.next = ib;
            if (bNext !is null) bNext.prev = ia;
            ib.prev = aPrev;
            ib.next = ia;
            ia.prev = ib;
            ia.next = bNext;
        }
        else if (aPrev is ib)
        {
            if (bPrev !is null) bPrev.next = ia;
            if (aNext !is null) aNext.prev = ib;
            ia.prev = bPrev;
            ia.next = ib;
            ib.prev = ia;
            ib.next = aNext;
        }
        else
        {
            if (aPrev !is null) aPrev.next = ib;
            if (aNext !is null) aNext.prev = ib;
            ia.next = bNext;
            ia.prev = bPrev;

            if (bPrev !is null) bPrev.next = ia;
            if (bNext !is null) bNext.prev = ia;
            ib.next = aNext;
            ib.prev = aPrev;
        }
        if (first_ is ia) first_ = ib;
        if (last_ is ia) last_ = ib;
        cachedItem_ = -1;
        cache_ = null;
    }

    /// Swaps the two 1-based line numbers.
    void itemSwap(int ia, int ib) { swapImpl(cast(CbItem) itemAt(ia), cast(CbItem) itemAt(ib)); }
    protected override void itemSwap(Object a, Object b) { swapImpl(cast(CbItem) a, cast(CbItem) b); }

    protected override int itemWidth(Object item) const
    {
        fldraw.fl_font(textfont(), textsize());
        return cast(int)(fldraw.width((cast(CbItem) item).text) + 0.5) + (textsize() - 2) + 8;
    }

    protected override void itemDraw(Object v, int X, int Y, int W, int H) const
    {
        auto i = cast(CbItem) v;
        Y += (H - itemHeight(v)) / 2;
        int tsize = textsize();
        Color col = activeR() ? textcolor() : fldraw.inactive(textcolor());
        int checkSize_ = tsize - 2;
        int cy = Y + (tsize + 1 - checkSize_) / 2;
        X += 2;

        // The check mark box (always drawn).
        fldraw.fl_color(activeR() ? foregroundColor : fldraw.inactive(foregroundColor));
        fldraw.loop(X, cy, X, cy + checkSize_, X + checkSize_, cy + checkSize_, X + checkSize_, cy);

        // The check mark itself.
        if (i.checked)
            fldraw.drawCheck(Rect(X + 1, cy + 1, checkSize_ - 1, checkSize_ - 1), fldraw.fl_color());

        // The item text.
        fldraw.fl_font(textfont(), tsize);
        if (i.selected) col = fldraw.contrast(col, selectionColor());
        fldraw.fl_color(col);
        fldraw.fl_draw(i.text, cast(int) i.text.length, X + checkSize_ + 8, Y + tsize - 1);
    }

    protected override void itemSelect(Object v, int state = 1)
    {
        auto i = cast(CbItem) v;
        if (state)
        {
            if (i.checked) { i.checked = false; nchecked_--; }
            else { i.checked = true; nchecked_++; }
        }
    }

    protected override int itemSelected(Object v) const { return (cast(CbItem) v).selected ? 1 : 0; }

    // ------------------------------------------------------------
    // 1-based line lookup (see the module comment for why this isn't
    // named findItem()).
    // ------------------------------------------------------------

    private CbItem findItemN(int n) const
    {
        auto self = cast(CheckBrowser) this;
        int i = n;
        CbItem p = self.first_;

        if (n <= 0 || n > nitems_ || p is null) return null;

        if (n == cachedItem_) { p = self.cache_; n = 1; }
        else if (n == cachedItem_ + 1) { p = self.cache_.next; n = 1; }
        else if (n == cachedItem_ - 1) { p = self.cache_.prev; n = 1; }

        while (--n) p = p.next;

        self.cache_ = p;
        self.cachedItem_ = i;
        return p;
    }

    private int checkLineno(CbItem p0) const
    {
        CbItem p = cast(CbItem) first_;
        if (p is null) return 0;
        int i = 1;
        while (p !is null)
        {
            if (p is p0) return i;
            i++;
            p = p.next;
        }
        return 0;
    }

    // ------------------------------------------------------------
    // Public API
    // ------------------------------------------------------------

    /// Adds an unchecked line, returning the new nitems().
    int add(string s) { return add(s, false); }
    /// Adds a line, optionally checked, returning the new nitems().
    int add(string s, bool checked)
    {
        auto p = new CbItem();
        p.next = null;
        p.prev = null;
        p.checked = checked;
        p.selected = false;
        p.text = s;

        if (checked) nchecked_++;

        if (last_ is null) first_ = last_ = p;
        else { last_.next = p; p.prev = last_; last_ = p; }
        nitems_++;

        return nitems_;
    }

    /// Brings FlGroup's remove(int)/remove(Widget) (child-widget removal)
    /// into this class's overload set -- remove(int) below has a
    /// different return type (int, not void) than FlGroup.remove(int),
    /// so it can't be a covariant override, only a same-signature
    /// hide (matching FLTK's own C++ name-hiding here too).
    alias remove = FlGroup.remove;

    /// Removes the given 1-based line, returning the new nitems().
    int remove(int item)
    {
        CbItem p = findItemN(item);
        if (p !is null)
        {
            deleting(p);
            if (p.checked) nchecked_--;
            if (p.prev !is null) p.prev.next = p.next; else first_ = p.next;
            if (p.next !is null) p.next.prev = p.prev; else last_ = p.prev;
            nitems_--;
            cachedItem_ = -1;
        }
        return nitems_;
    }

    /// Removes every line.
    override void clear()
    {
        if (first_ is null) return;
        newList();
        first_ = last_ = null;
        nitems_ = nchecked_ = 0;
        cachedItem_ = -1;
    }

    /// Number of lines in the browser.
    int nitems() const { return nitems_; }
    /// Number of currently checked lines.
    int nchecked() const { return nchecked_; }

    int checked(int item) const
    {
        CbItem p = findItemN(item);
        return p !is null && p.checked ? 1 : 0;
    }

    void checked(int item, bool b)
    {
        CbItem p = findItemN(item);
        if (p !is null && (p.checked != b))
        {
            p.checked = b;
            if (b) nchecked_++; else nchecked_--;
            redraw();
        }
    }

    /// Equivalent to checked(item, true).
    void setChecked(int item) { checked(item, true); }

    void checkAll()
    {
        nchecked_ = nitems_;
        for (CbItem p = first_; p !is null; p = p.next) p.checked = true;
        redraw();
    }

    void checkNone()
    {
        nchecked_ = 0;
        for (CbItem p = first_; p !is null; p = p.next) p.checked = false;
        redraw();
    }

    /// The 1-based line number of the currently selected item, or 0.
    int value() const { return checkLineno(cast(CbItem) selection()); }

    const(char)[] text(int item) const
    {
        CbItem p = findItemN(item);
        return p !is null ? p.text : null;
    }

    override int handle(Event event)
    {
        if (event == Event.push)
        {
            int X, Y, W, H;
            bbox(X, Y, W, H);
            // See the module comment: deselecting first guarantees
            // every click toggles the clicked row's checkbox, even
            // when re-clicking the already-current row.
            if (fl.core.eventInside(X, Y, W, H)) deselect();
        }
        return super.handle(event);
    }
}

unittest
{
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto b = new CheckBrowser(0, 0, 100, 100);
    b.end();

    assert(b.type() == selectBrowser);
    assert(b.when() == whenNever);
    assert(b.nitems() == 0);

    assert(b.add("one") == 1);
    assert(b.add("two", true) == 2);
    assert(b.add("three") == 3);
    assert(b.nitems() == 3);
    assert(b.nchecked() == 1);

    assert(b.text(1) == "one");
    assert(b.text(2) == "two");
    assert(b.checked(2) == 1);
    assert(b.checked(1) == 0);

    FlGroup.current(null);
}

unittest
{
    // checked()/setChecked()/checkAll()/checkNone().
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto b = new CheckBrowser(0, 0, 100, 100);
    b.add("a");
    b.add("b");
    b.add("c");
    b.end();

    b.setChecked(2);
    assert(b.checked(2) == 1);
    assert(b.nchecked() == 1);

    b.checkAll();
    assert(b.nchecked() == 3);
    assert(b.checked(1) == 1 && b.checked(2) == 1 && b.checked(3) == 1);

    b.checkNone();
    assert(b.nchecked() == 0);
    assert(b.checked(1) == 0 && b.checked(2) == 0 && b.checked(3) == 0);

    b.checked(1, true);
    assert(b.checked(1) == 1);
    assert(b.nchecked() == 1);

    FlGroup.current(null);
}

unittest
{
    // remove()/clear().
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto b = new CheckBrowser(0, 0, 100, 100);
    b.add("a");
    b.add("b", true);
    b.add("c");
    b.end();

    assert(b.remove(2) == 2); // removes "b" (which was checked)
    assert(b.nchecked() == 0);
    assert(b.text(1) == "a");
    assert(b.text(2) == "c");

    b.clear();
    assert(b.nitems() == 0);
    assert(b.nchecked() == 0);
    assert(b.children() == 2); // scrollbars survive clear()

    FlGroup.current(null);
}

unittest
{
    // itemSwap(int,int) exchanges two lines' content in place.
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto b = new CheckBrowser(0, 0, 100, 100);
    b.add("a");
    b.add("b", true);
    b.add("c");
    b.end();

    b.itemSwap(1, 3);
    assert(b.text(1) == "c");
    assert(b.text(2) == "b");
    assert(b.text(3) == "a");
    assert(b.checked(2) == 1); // "b"'s checked state travels with it

    FlGroup.current(null);
}

unittest
{
    // itemHeight()/itemWidth()/itemDraw()/handle() -- just confirm no
    // crash headlessly, matching the established pattern for every
    // fl.draw-calling draw() test in this port. Nested inside a real
    // FlGroup so draw()'s parent().color() corner-fill path (see
    // fl.browser's identical test setup note) has a valid parent.
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto win = new FlGroup(0, 0, 300, 300);
    auto b = new CheckBrowser(0, 0, 200, 100);
    b.add("alpha");
    b.add("beta", true);
    win.end();

    foreach (i; 1 .. b.nitems() + 1)
    {
        Object item = b.itemAt(i);
        assert(b.itemHeight(item) > 0);
        assert(b.itemWidth(item) >= 0);
    }
    b.draw();

    assert(b.handle(Event.push) == 0 || b.handle(Event.push) == 1); // no crash

    fl.core.resetForTest();
    FlGroup.current(null);
}
