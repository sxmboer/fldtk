/*
 * Ported from FL/Fl_Browser.H + src/Fl_Browser.cxx + src/Fl_Browser_load.cxx
 * (FLTK 1.5.0, ~/Repositories/fltk).
 *
 * The concrete, Forms-compatible scrolling text-line browser: manages
 * storage for a doubly-linked list of lines (FLTK's `FL_BLINE`),
 * each with a text string, optional user data, and an optional icon,
 * plus the `'@'`-format-code text markup (bold/italic/size/color/
 * underline/...) and tab-separated column layout. `Fl_Select_Browser`/
 * `Fl_Hold_Browser`/`Fl_Multi_Browser` (fl.select_browser/
 * fl.hold_browser/fl.multi_browser) are trivial `type()` subclasses of
 * this, matching FLTK exactly.
 *
 * Deliberate deviations:
 *
 *  - FLTK's `FL_BLINE` is a hand-managed variable-length C struct
 *    (`char txt[1]` as a flexible array member, `malloc(sizeof(FL_BLINE)+len)`,
 *    `realloc`-via-new-node-plus-free() whenever text grows past the
 *    node's allocated size). None of that bookkeeping is needed here:
 *    `BLine.txt` is a plain GC-managed D `string`, freely reassignable
 *    to a longer or shorter value with no reallocation dance and no
 *    `length`-vs-actual-string-length distinction to track. This also
 *    means `text(line, newtext)` never needs to replace the node's
 *    *identity* the way FLTK's `Fl_Browser::text()` does (a new
 *    `FL_BLINE*` when growing) -- since `top_`/`selection_`/
 *    `maxWidthItem_` in fl.browser_ key off object identity, and that
 *    identity never changes here, `text()` only needs `redrawLine()`,
 *    not the full `replacing()` pointer-fixup FLTK's growing case
 *    needs. `bline_length()` (the allocated-buffer-size accessor) has
 *    no D equivalent for the same reason and isn't ported.
 *
 *  - `load(filename)` reads the whole file via `std.file.readText()`
 *    and splits on `'\n'` rather than the byte-at-a-time `getc()` loop
 *    FLTK uses (which also arbitrarily truncates any line longer
 *    than 1023 bytes into multiple browser lines -- a buffer-size
 *    artifact, not a real feature, not reproduced here). Splitting on
 *    `'\n'` alone (matching FLTK, which never special-cases `'\r'`
 *    either) naturally reproduces FLTK's two real quirks: a
 *    trailing newline produces one extra empty final line, and a
 *    completely empty file still produces one (empty) line.
 *
 *  - Icon rendering (`Fl_Image* icon`) is real: `item_draw()`'s
 *    icon-drawing branch and `item_height()`/`item_width()`'s icon-size
 *    contribution are all ported faithfully, matching
 *    `Fl_Browser::item_draw()`/`item_height()`/`item_width()` exactly
 *    (the icon draws once, left of the first field, shrinking the
 *    remaining draw area by its own width plus a 2px gap).
 *
 *  - The `'@'`-format-code scanner's one genuinely-undefined-behavior
 *    corner in FLTK (a lone, unescaped trailing `'@'` with no
 *    following character at all reads one byte past the C string's
 *    null terminator inside `item_height()`/`item_width()`'s own
 *    scanning loop) has no meaningful D equivalent to replicate (D
 *    strings aren't null-terminated; reading past `txt.length` is a
 *    `RangeError`, not a few bytes of harmless garbage). This port
 *    instead treats a trailing unescaped `'@'` as "stop scanning,
 *    consume just the `'@'`" -- the same practical outcome FLTK's `switch(0)`
 *    hitting no case would have produced anyway, just reached without
 *    an out-of-bounds read. Not filed as an FLTK_ISSUES.md
 *    candidate: it's a one-byte, harmless-in-practice C string overread
 *    on a corner case (a label ending in a bare `'@'`), not a
 *    consequential behavioral bug worth flagging for FLTK review.
 */
module fl.browser;

import fl.browser_;
import fl.enumerations;
import fl.core;
import fldraw = fl.draw;
import fl.image : Image;
import std.file : readText;
import std.array : split;

private enum char blineSelected     = 1;
private enum char blineNotDisplayed = 2;

private bool isAsciiDigit(char c) { return c >= '0' && c <= '9'; }

/// strtol()-style: parses an optional sign then decimal digits
/// starting at idx, advancing idx past what was consumed. Leaves idx
/// unchanged and returns 0 if no digits are found (matching strtol's
/// "endptr == nptr" case).
private long parseLongAt(const(char)[] s, ref size_t idx)
{
    size_t start = idx;
    bool neg = false;
    if (idx < s.length && (s[idx] == '+' || s[idx] == '-'))
    {
        neg = s[idx] == '-';
        idx++;
    }
    size_t digitsStart = idx;
    while (idx < s.length && isAsciiDigit(s[idx])) idx++;
    if (idx == digitsStart) { idx = start; return 0; }
    long val = 0;
    foreach (c; s[digitsStart .. idx]) val = val * 10 + (c - '0');
    return neg ? -val : val;
}

/// Consumes one `'@'`-introduced format code at txt[idx] (font/size
/// codes shared by item_height()/item_width(); item_draw() has its
/// own richer switch since it also handles color/line/underline
/// drawing side effects). Returns false ('.'  -- stop scanning
/// entirely) or true (continue). Caller has already verified
/// txt[idx] == '@' and it isn't doubled/trailing.
private bool consumeSizeFormatCode(const(char)[] txt, ref size_t idx, ref Font font, ref Fontsize tsize)
{
    idx++; // past '@'
    char code = txt[idx];
    idx++; // past the code letter
    switch (code)
    {
    case 'l': case 'L': tsize = 24; break;
    case 'm': case 'M': tsize = 18; break;
    case 's': tsize = 11; break;
    case 'b': font = font | bold; break;
    case 'i': font = font | italic; break;
    case 'f': case 't': font = courier; break;
    case 'B': case 'C':
        while (idx < txt.length && isAsciiDigit(txt[idx])) idx++;
        break;
    case 'F': font = cast(Font) parseLongAt(txt, idx); break;
    case 'S': tsize = cast(Fontsize) parseLongAt(txt, idx); break;
    case '.': return false;
    default: break;
    }
    return true;
}

/// Advances idx past every leading format code in txt (starting at
/// idx), applying each to font/tsize via consumeSizeFormatCode(). No-op
/// if formatChar is 0 (formatting disabled).
private void skipSizeFormatCodes(const(char)[] txt, char formatChar, ref size_t idx, ref Font font, ref Fontsize tsize)
{
    if (formatChar == 0) return;
    while (idx < txt.length && txt[idx] == formatChar)
    {
        if (idx + 1 >= txt.length || txt[idx + 1] == formatChar)
        {
            idx++; // consume exactly one '@' (doubled-escape or trailing)
            break;
        }
        if (!consumeSizeFormatCode(txt, idx, font, tsize)) break;
    }
}

private static immutable int[1] noColumns = [0];

private final class BLine
{
    BLine prev, next;
    Object data;
    Image icon;
    char flags;
    string txt;
}

class Browser : Browser_
{
    private
    {
        BLine first_, last_, cache_;
        int cacheline_;
        int lines_;
        int fullHeight_;
        const(int)[] columnWidths_;
        char formatChar_;
        char columnChar_;
    }

    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        columnWidths_ = noColumns;
        lines_ = 0;
        fullHeight_ = 0;
        cacheline_ = 0;
        formatChar_ = '@';
        columnChar_ = '\t';
        first_ = last_ = cache_ = null;
    }

    // ------------------------------------------------------------
    // Browser_ required overrides
    // ------------------------------------------------------------

    protected override Object itemFirst() const { return cast(Object) first_; }
    protected override Object itemNext(Object item) const { return cast(Object)(cast(BLine) item).next; }
    protected override Object itemPrev(Object item) const { return cast(Object)(cast(BLine) item).prev; }
    protected override Object itemLast() const { return cast(Object) last_; }

    protected override int itemSelected(Object item) const
    {
        return (cast(BLine) item).flags & blineSelected;
    }
    protected override void itemSelect(Object item, int val = 1)
    {
        auto l = cast(BLine) item;
        if (val) l.flags |= blineSelected;
        else l.flags &= ~blineSelected;
    }

    protected override const(char)[] itemText(Object item) const
    {
        return (cast(BLine) item).txt;
    }

    protected override void itemSwap(Object a, Object b) { swap(cast(BLine) a, cast(BLine) b); }

    protected override Object itemAt(int line) const
    {
        return cast(Object)(cast(Browser) this).findLine(line);
    }

    protected override int fullHeight() const { return fullHeight_; }
    protected override int incrHeight() const { return textsize() + 2 + linespacing(); }

    protected override int itemHeight(Object item) const
    {
        BLine l = cast(BLine) item;
        if (l.flags & blineNotDisplayed) return 0;

        int hmax = 2; // never return zero

        if (l.txt.length == 0)
        {
            fldraw.fl_font(textfont(), textsize());
            int hh = fldraw.height();
            if (hh > hmax) hmax = hh;
        }
        else
        {
            const(int)[] widths = columnWidths();
            size_t ci = 0;
            size_t pos = 0;
            string str = l.txt;
            while (true)
            {
                Font font = textfont();
                Fontsize tsize = textsize();
                size_t p = pos;
                skipSizeFormatCodes(str, formatChar_, p, font, tsize);

                bool hasField = ci < widths.length && widths[ci] != 0;
                ptrdiff_t tab = -1;
                if (hasField)
                {
                    ci++;
                    auto rel = indexOfFrom(str, p, columnChar_);
                    if (rel >= 0) tab = rel;
                }
                size_t fieldEnd = tab >= 0 ? cast(size_t) tab : str.length;

                if ((tab < 0 && p < str.length) || (tab >= 0 && p < fieldEnd) || hmax == 2)
                {
                    fldraw.fl_font(font, tsize);
                    int hh = fldraw.height();
                    if (hh > hmax) hmax = hh;
                }
                if (tab < 0) break;
                pos = fieldEnd + 1;
                if (pos > str.length) break;
            }
        }

        if (l.icon !is null && (l.icon.h() + 2) > hmax)
            hmax = l.icon.h() + 2; // leave 2px above/below

        return hmax;
    }

    protected override int itemWidth(Object item) const
    {
        BLine l = cast(BLine) item;
        string str = l.txt;
        const(int)[] widths = columnWidths();
        int ww = 0;
        size_t pos = 0;
        size_t ci = 0;

        while (ci < widths.length && widths[ci] != 0)
        {
            auto rel = indexOfFrom(str, pos, columnChar_);
            if (rel < 0) break;
            pos = cast(size_t) rel + 1;
            ww += widths[ci];
            ci++;
        }

        Fontsize tsize = textsize();
        Font font = textfont();
        skipSizeFormatCodes(str, formatChar_, pos, font, tsize);

        if (ww == 0 && l.icon !is null) ww = l.icon.w();

        fldraw.fl_font(font, tsize);
        return ww + cast(int)(fldraw.width(str[pos .. $]) + 0.5) + 6;
    }

    protected override void itemDraw(Object item, int X, int Y, int W, int H) const
    {
        BLine l = cast(BLine) item;
        string str = l.txt;
        const(int)[] widths = columnWidths();
        size_t pos = 0;
        size_t ci = 0;
        bool firstLoop = true; // for icon

        while (W > 6)
        {
            int w1 = W;
            ptrdiff_t tab = -1;
            bool hasField = ci < widths.length && widths[ci] != 0;
            if (hasField)
            {
                auto rel = indexOfFrom(str, pos, columnChar_);
                if (rel >= 0) { tab = rel; w1 = widths[ci]; ci++; }
            }
            size_t fieldEnd = tab >= 0 ? cast(size_t) tab : str.length;

            // Icon rendering: drawn once, before the first field,
            // shrinking the remaining draw area exactly like FLTK's
            // own firstLoop-guarded block in Fl_Browser::item_draw().
            if (firstLoop)
            {
                firstLoop = false;
                if (l.icon !is null)
                {
                    l.icon.draw(X + 2, Y + 1); // leave 2px left, 1px above
                    int iconw = l.icon.w() + 2;
                    X += iconw;
                    W -= iconw;
                    w1 -= iconw;
                }
            }

            Fontsize tsize = textsize();
            Font font = textfont();
            Color lcol = textcolor();
            Align talign = alignLeft;

            size_t p = pos;
            if (formatChar_ != 0)
            {
                scanning: while (p < fieldEnd && str[p] == formatChar_)
                {
                    if (p + 1 >= fieldEnd || str[p + 1] == formatChar_)
                    {
                        p++;
                        break;
                    }
                    p++; // past '@'
                    char code = str[p];
                    p++; // past the code letter
                    switch (code)
                    {
                    case 'l': case 'L': tsize = 24; break;
                    case 'm': case 'M': tsize = 18; break;
                    case 's': tsize = 11; break;
                    case 'b': font = font | bold; break;
                    case 'i': font = font | italic; break;
                    case 'f': case 't': font = courier; break;
                    case 'c': talign = alignCenter; break;
                    case 'r': talign = alignRight; break;
                    case 'B':
                        if (!(l.flags & blineSelected))
                        {
                            fldraw.fl_color(cast(Color) parseLongAt(str, p));
                            fldraw.fl_rectf(X, Y, w1, H);
                        }
                        else
                        {
                            while (p < fieldEnd && isAsciiDigit(str[p])) p++;
                        }
                        break;
                    case 'C':
                        lcol = cast(Color) parseLongAt(str, p);
                        break;
                    case 'F':
                        font = cast(Font) parseLongAt(str, p);
                        break;
                    case 'N':
                        lcol = inactiveColor;
                        break;
                    case 'S':
                        tsize = cast(Fontsize) parseLongAt(str, p);
                        break;
                    case '-':
                        fldraw.fl_color(dark3);
                        fldraw.fl_line(X + 3, Y + H / 2, X + w1 - 3, Y + H / 2);
                        fldraw.fl_color(light3);
                        fldraw.fl_line(X + 3, Y + H / 2 + 1, X + w1 - 3, Y + H / 2 + 1);
                        break;
                    case 'u':
                    case '_':
                        fldraw.fl_color(lcol);
                        fldraw.fl_line(X + 3, Y + H - 1, X + w1 - 3, Y + H - 1);
                        break;
                    case '.':
                        break scanning;
                    default:
                        break;
                    }
                }
            }

            fldraw.fl_font(font, tsize);
            if (l.flags & blineSelected) lcol = fldraw.contrast(lcol, selectionColor());
            if (!activeR()) lcol = fldraw.inactive(lcol);
            fldraw.fl_color(lcol);
            // No '@'-symbols in item text: Fl_Browser::item_draw() passes
            // draw_symbols = 0, so "1920x1032@0,0" shows literally.
            fldraw.fl_draw(str[p .. fieldEnd], X + 3, Y, w1 - 6, H,
                tab >= 0 ? cast(Align)(talign | alignClip) : talign, null, 0, false);

            if (tab < 0) break;
            X += w1;
            W -= w1;
            pos = fieldEnd + 1;
        }
    }

    // ------------------------------------------------------------
    // BLine internals (find/insert/remove/swap), and protected
    // accessors mirroring FLTK's bline_* protocol (for
    // fl.file_browser's subclass access).
    // ------------------------------------------------------------

    private BLine findLine(int line) const
    {
        auto self = cast(Browser) this;
        int n;
        BLine l;
        if (line == cacheline_) return self.cache_;
        if (cacheline_ && line > (cacheline_ / 2) && line < ((cacheline_ + lines_) / 2))
        {
            n = cacheline_;
            l = self.cache_;
        }
        else if (line <= (lines_ / 2))
        {
            n = 1;
            l = self.first_;
        }
        else
        {
            n = lines_;
            l = self.last_;
        }
        for (; n < line && l !is null; n++) l = l.next;
        for (; n > line && l !is null; n--) l = l.prev;
        self.cacheline_ = line;
        self.cache_ = l;
        return l;
    }

    private int lineno(BLine item) const
    {
        if (item is null) return 0;
        if (item is cache_) return cacheline_;
        if (item is first_) return 1;
        if (item is last_) return lines_;
        auto self = cast(Browser) this;
        if (cache_ is null)
        {
            self.cache_ = self.first_;
            self.cacheline_ = 1;
        }
        BLine b = self.cache_.prev;
        int bnum = cacheline_ - 1;
        BLine f = self.cache_.next;
        int fnum = cacheline_ + 1;
        int n = 0;
        for (;;)
        {
            if (b is item) { n = bnum; break; }
            if (f is item) { n = fnum; break; }
            if (b !is null) { b = b.prev; bnum--; }
            if (f !is null) { f = f.next; fnum++; }
        }
        self.cache_ = item;
        self.cacheline_ = n;
        return n;
    }

    private BLine removeNode(int line)
    {
        BLine ttt = findLine(line);
        deleting(ttt);

        cacheline_ = line - 1;
        cache_ = ttt.prev;
        lines_--;
        fullHeight_ -= itemHeight(ttt) + linespacing();
        if (ttt.prev !is null) ttt.prev.next = ttt.next; else first_ = ttt.next;
        if (ttt.next !is null) ttt.next.prev = ttt.prev; else last_ = ttt.prev;

        return ttt;
    }

    /// Removes the item at line, one line shorter after. Out-of-range
    /// line numbers are ignored.
    override void remove(int line)
    {
        if (line < 1 || line > lines_) return;
        removeNode(line); // GC reclaims -- no free() needed
    }

    private void insertNode(int line, BLine item)
    {
        if (first_ is null)
        {
            item.prev = item.next = null;
            first_ = last_ = item;
        }
        else if (line <= 1)
        {
            inserting(first_, item);
            item.prev = null;
            item.next = first_;
            item.next.prev = item;
            first_ = item;
        }
        else if (line > lines_)
        {
            item.prev = last_;
            item.prev.next = item;
            item.next = null;
            last_ = item;
        }
        else
        {
            BLine n = findLine(line);
            inserting(n, item);
            item.next = n;
            item.prev = n.prev;
            item.prev.next = item;
            n.prev = item;
        }
        cacheline_ = line;
        cache_ = item;
        lines_++;
        fullHeight_ += itemHeight(item) + linespacing();
        redrawLine(item);
    }

    /// Inserts a new line with text newtext above line, with optional
    /// user data d. If line > size(), appends at the end.
    void insert(int line, string newtext, Object d = null)
    {
        auto t = new BLine();
        t.txt = newtext;
        t.data = d;
        t.icon = null;
        t.flags = 0;
        insertNode(line, t);
    }

    /// Removes line from, reinserts it at to (computed *after* removal).
    void move(int to, int from)
    {
        if (from < 1 || from > lines_) return;
        insertNode(to, removeNode(from));
    }

    void swap(BLine a, BLine b)
    {
        if (a is b || a is null || b is null) return;
        swapping(a, b);
        BLine aprev = a.prev, anext = a.next, bprev = b.prev, bnext = b.next;
        if (b.prev is a)
        {
            if (aprev !is null) aprev.next = b; else first_ = b;
            b.next = a;
            a.next = bnext;
            b.prev = aprev;
            a.prev = b;
            if (bnext !is null) bnext.prev = a; else last_ = a;
        }
        else if (a.prev is b)
        {
            if (bprev !is null) bprev.next = a; else first_ = a;
            a.next = b;
            b.next = anext;
            a.prev = bprev;
            b.prev = a;
            if (anext !is null) anext.prev = b; else last_ = b;
        }
        else
        {
            b.prev = aprev;
            if (anext !is null) anext.prev = b; else last_ = b;
            a.prev = bprev;
            if (bnext !is null) bnext.prev = a; else last_ = a;
            if (aprev !is null) aprev.next = b; else first_ = b;
            b.next = anext;
            if (bprev !is null) bprev.next = a; else first_ = a;
            a.next = bnext;
        }
        cacheline_ = 0;
        cache_ = null;
    }

    /// Swaps the two lines a and b (1-based). Call redraw() to see it.
    void swap(int a, int b)
    {
        if (a < 1 || a > lines_ || b < 1 || b > lines_) return;
        swap(findLine(a), findLine(b));
    }

    // ------------------------------------------------------------
    // Protected bline_* accessors, for fl.file_browser's subclass.
    // ------------------------------------------------------------

    protected const(char)[] blineTxt(Object b) const { return (cast(BLine) b).txt; }
    protected char blineFlags(Object b) const { return (cast(BLine) b).flags; }
    protected Object blineData(Object b) const { return (cast(BLine) b).data; }

    // ------------------------------------------------------------
    // Public API
    // ------------------------------------------------------------

    /// Removes every line.
    override void clear()
    {
        first_ = null;
        last_ = null;
        fullHeight_ = 0;
        lines_ = 0;
        newList();
    }

    /// Adds a new line to the end, with optional user data d.
    void add(string newtext, Object d = null) { insert(lines_ + 1, newtext, d); }

    /// Number of lines; 0 if empty. Also the last valid line number.
    int size() const { return lines_; }
    override void size(int w, int h) { super.size(w, h); } /// ditto (widget resize)

    override Fontsize textsize() const { return super.textsize(); }
    /// Recalculates every item's height and the cached full height --
    /// can be slow with many lines. A no-op if newSize is unchanged.
    override void textsize(Fontsize newSize)
    {
        if (newSize == textsize()) return;
        super.textsize(newSize);
        newList();
        fullHeight_ = 0;
        if (lines_ == 0) return;
        for (BLine itm = first_; itm !is null; itm = itm.next)
            fullHeight_ += itemHeight(itm) + linespacing();
    }

    int topline() const { return lineno(cast(BLine) top()); }

    enum LinePosition { top, bottom, middle }

    /// Scrolls so line appears at the given position.
    void lineposition(int line, LinePosition pos)
    {
        if (line < 1) line = 1;
        if (line > lines_) line = lines_;
        int p = 0;

        BLine l;
        int remaining = line;
        for (l = first_; l !is null && remaining > 1; l = l.next)
        {
            remaining--;
            p += itemHeight(l) + linespacing();
        }
        if (l !is null && pos == LinePosition.bottom) p += itemHeight(l) + linespacing();

        int final_ = p, X, Y, W, H;
        bbox(X, Y, W, H);

        final switch (pos)
        {
        case LinePosition.top: break;
        case LinePosition.bottom: final_ -= H; break;
        case LinePosition.middle: final_ -= H / 2; break;
        }

        if (final_ > (fullHeight() - H)) final_ = fullHeight() - H;
        vposition(final_);
    }

    void topline(int line) { lineposition(line, LinePosition.top); }
    void bottomline(int line) { lineposition(line, LinePosition.bottom); }
    void middleline(int line) { lineposition(line, LinePosition.middle); }

    int select(int line, int val = 1)
    {
        if (line < 1 || line > lines_) return 0;
        return super.select(cast(Object) findLine(line), val);
    }

    int selected(int line) const { return line < 1 || line > lines_ ? 0 : findLine(line).flags & blineSelected; }

    /// Makes line visible/selectable by the user (opposite of hide(int)).
    void show(int line)
    {
        BLine t = findLine(line);
        if (t.flags & blineNotDisplayed)
        {
            t.flags &= ~blineNotDisplayed;
            fullHeight_ += itemHeight(t) + linespacing();
            if (super.displayed(t)) redraw();
        }
    }
    override void show() { super.show(); } /// Shows the whole widget.

    /// Hides line, preventing user selection (still selectable from code).
    void hide(int line)
    {
        BLine t = findLine(line);
        if (!(t.flags & blineNotDisplayed))
        {
            fullHeight_ -= itemHeight(t) + linespacing();
            t.flags |= blineNotDisplayed;
            if (super.displayed(t)) redraw();
        }
    }
    override void hide() { super.hide(); } /// Hides the whole widget.

    void display(int line, int val = 1)
    {
        if (line < 1 || line > lines_) return;
        if (val) show(line); else hide(line);
    }

    int visible(int line) const { return line < 1 || line > lines_ ? 0 : !(findLine(line).flags & blineNotDisplayed); }

    int value() const { return lineno(cast(BLine) selection()); }
    void value(int line) { select(line); }

    const(char)[] text(int line) const { return line < 1 || line > lines_ ? null : findLine(line).txt; }

    /// Changes line's text. Deliberately simpler than FLTK -- see
    /// the module comment (no realloc-driven node replacement needed).
    void text(int line, string newtext)
    {
        if (line < 1 || line > lines_) return;
        BLine t = findLine(line);
        t.txt = newtext is null ? "" : newtext;
        redrawLine(t);
    }

    Object data(int line) const { return line < 1 || line > lines_ ? null : findLine(line).data; }
    void data(int line, Object d) { if (line >= 1 && line <= lines_) findLine(line).data = d; }

    const(int)[] columnWidths() const { return columnWidths_; }
    void columnWidths(const(int)[] arr) { columnWidths_ = arr; }

    char columnChar() const { return columnChar_; }
    void columnChar(char c) { columnChar_ = c; }

    char formatChar() const { return formatChar_; }
    void formatChar(char c) { formatChar_ = c; }

    int displayed(int line) const { return super.displayed(cast(Object) findLine(line)) ? 1 : 0; }

    void makeVisible(int line)
    {
        if (line < 1) super.display(cast(Object) findLine(1));
        else if (line > lines_) super.display(cast(Object) findLine(lines_));
        else super.display(cast(Object) findLine(line));
    }

    void icon(int line, Image ic)
    {
        if (line < 1 || line > lines_) return;
        BLine bl = findLine(line);
        bl.icon = ic;
        redrawLine(bl);
    }
    Image icon(int line) const { return line < 1 || line > lines_ ? null : findLine(line).icon; }
    void removeIcon(int line) { icon(line, null); }

    void replace(int a, string b) { text(a, b); }

    /// Clears the browser and loads filename, one browser line per
    /// source line. See the module comment for exact semantics.
    bool load(string filename)
    {
        clear();
        if (filename.length == 0) return true;
        string content;
        try { content = readText(filename); }
        catch (Exception) return false;
        foreach (line; content.split('\n')) add(line);
        return true;
    }
}

// Finds columnChar starting at offset pos in str; returns -1 if absent.
private ptrdiff_t indexOfFrom(const(char)[] str, size_t pos, char columnChar)
{
    for (size_t i = pos; i < str.length; i++)
        if (str[i] == columnChar) return cast(ptrdiff_t) i;
    return -1;
}

unittest
{
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto b = new Browser(0, 0, 100, 100);
    b.end();

    assert(b.size() == 0);
    b.add("one");
    b.add("two");
    b.add("three");
    assert(b.size() == 3);
    assert(b.text(1) == "one");
    assert(b.text(2) == "two");
    assert(b.text(3) == "three");
    assert(b.text(4) is null); // out of range

    FlGroup.current(null);
}

unittest
{
    // insert()/remove()/move() maintain line numbering correctly.
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto b = new Browser(0, 0, 100, 100);
    b.add("a");
    b.add("c");
    b.insert(2, "b"); // above line 2
    b.end();

    assert(b.text(1) == "a");
    assert(b.text(2) == "b");
    assert(b.text(3) == "c");

    b.remove(2);
    assert(b.size() == 2);
    assert(b.text(1) == "a");
    assert(b.text(2) == "c");

    b.move(1, 2); // remove "c" (line 2), reinsert at 1
    assert(b.text(1) == "c");
    assert(b.text(2) == "a");

    FlGroup.current(null);
}

unittest
{
    // data()/clear().
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto b = new Browser(0, 0, 100, 100);
    auto marker = new Object();
    b.add("x", marker);
    b.end();

    assert(b.data(1) is marker);
    b.data(1, null);
    assert(b.data(1) is null);

    b.clear();
    assert(b.size() == 0);
    assert(b.children() == 2); // scrollbars survive clear()

    FlGroup.current(null);
}

unittest
{
    // select()/selected()/value(), single-selection default type.
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto b = new Browser(0, 0, 100, 100);
    b.add("a");
    b.add("b");
    b.end();

    assert(b.select(1) == 1);
    assert(b.selected(1) != 0);
    assert(b.value() == 1);

    assert(b.select(2) == 1);
    assert(b.selected(1) == 0); // single-select: line 1 deselected
    assert(b.selected(2) != 0);
    assert(b.value() == 2);

    FlGroup.current(null);
}

unittest
{
    // show(int)/hide(int)/visible(int) toggle full_height_ and
    // BLINE_NOTDISPLAYED correctly.
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto b = new Browser(0, 0, 100, 20);
    b.add("a");
    b.add("b");
    b.end();

    assert(b.visible(1) != 0);
    b.hide(1);
    assert(b.visible(1) == 0);
    b.show(1);
    assert(b.visible(1) != 0);

    FlGroup.current(null);
}

unittest
{
    // swap(int,int) exchanges line content.
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto b = new Browser(0, 0, 100, 100);
    b.add("a");
    b.add("b");
    b.add("c");
    b.end();

    b.swap(1, 3);
    assert(b.text(1) == "c");
    assert(b.text(2) == "b");
    assert(b.text(3) == "a");

    FlGroup.current(null);
}

unittest
{
    // columnChar()/columnWidths()/formatChar() accessors.
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto b = new Browser(0, 0, 100, 100);
    b.end();

    assert(b.columnChar() == '\t');
    assert(b.formatChar() == '@');
    b.columnChar(',');
    b.formatChar(0);
    assert(b.columnChar() == ',');
    assert(b.formatChar() == 0);

    static immutable int[3] widths = [50, 50, 0];
    b.columnWidths(widths);
    assert(b.columnWidths() == widths);

    FlGroup.current(null);
}

unittest
{
    // load() splits on '\n' and clears any prior content; a nonexistent
    // file returns false without touching the browser's line count
    // beyond the clear() that already happened.
    import fl.group : FlGroup;
    import std.file : write, remove, exists, tempDir;
    import std.path : buildPath;
    import std.uuid : randomUUID;
    FlGroup.current(null);

    auto b = new Browser(0, 0, 100, 100);
    b.end();

    string path = buildPath(tempDir(), "fldtk-browser-test-" ~ randomUUID().toString() ~ ".txt");
    write(path, "one\ntwo\nthree");
    scope(exit) if (exists(path)) remove(path);

    assert(b.load(path));
    assert(b.size() == 3);
    assert(b.text(1) == "one");
    assert(b.text(3) == "three");

    assert(!b.load(path ~ "-does-not-exist"));

    FlGroup.current(null);
}

unittest
{
    // itemHeight()/itemWidth()/itemDraw() exercise the '@'-format-code
    // scanner (font size/style/color codes) and tab-separated columns.
    // Just confirm no exception/crash headlessly, matching the
    // established pattern for every fl.draw-calling draw() test in
    // this port -- fl.draw's primitives no-op safely without an open
    // display.
    import fl.group : FlGroup;
    FlGroup.current(null);

    // Nested inside a real parent FlGroup -- draw()'s "square between
    // scrollbars" corner-fill (hit when both scrollbars are visible at
    // once, which this test's content deliberately provokes) reads
    // parent().color(), matching FLTK's own unconditional
    // Fl_Widget::parent()->color() assumption that every Browser lives
    // inside some container; a bare top-level Browser (as in the
    // simpler unittests above, which never provoke that corner) has
    // no parent and would crash here exactly as FLTK's own
    // assumption would if violated.
    auto win = new FlGroup(0, 0, 300, 300);
    auto b = new Browser(0, 0, 200, 100);
    b.add("@b@cBold Centered");
    b.add("@C1@.Colored, formatting stopped early");
    b.add("@@literal-at-sign");
    b.add(""); // blank line
    static immutable int[3] widths = [40, 40, 0];
    b.columnWidths(widths);
    b.add("col1\tcol2\trest");
    win.end();

    foreach (i; 1 .. b.size() + 1)
    {
        assert(b.itemHeight(cast(Object) b.itemAt(i)) > 0);
        assert(b.itemWidth(cast(Object) b.itemAt(i)) >= 0);
    }
    b.draw();

    FlGroup.current(null);
}

unittest
{
    // Icon sizing/drawing: a line's icon widens itemHeight() (icon
    // taller than the text) and itemWidth() (icon wider than the
    // tab-column layout would otherwise report for a short/blank line),
    // and itemDraw() doesn't crash with one set -- headless, Image.draw()
    // itself early-returns with no display, same as every other
    // icon-drawing test in this port.
    import fl.group : FlGroup;
    import fl.image : RGBImage;

    FlGroup.current(null);
    auto win = new FlGroup(0, 0, 300, 300);
    auto b = new Browser(0, 0, 200, 100);
    b.add(""); // blank line: itemWidth()'s ww==0 fallback path
    win.end();

    auto item = cast(Object) b.itemAt(1);
    int hNoIcon = b.itemHeight(item);
    int wNoIcon = b.itemWidth(item);

    ubyte[] bits = [255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 0];
    auto icon = new RGBImage(bits, 2, 40, 3); // taller/wider than the blank line's own metrics
    b.icon(1, icon);
    assert(b.icon(1) is icon);

    assert(b.itemHeight(item) >= icon.h() + 2);
    assert(b.itemHeight(item) > hNoIcon);
    assert(b.itemWidth(item) >= icon.w());
    assert(b.itemWidth(item) > wNoIcon);

    b.draw();

    b.removeIcon(1);
    assert(b.icon(1) is null);

    FlGroup.current(null);
}
