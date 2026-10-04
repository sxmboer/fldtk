/*
 * Ported from FL/Fl_Terminal.H + src/Fl_Terminal.cxx (FLTK 1.5.0,
 * ~/Repositories/fltk). A ~5400-line VT100/ANSI/xterm-style terminal
 * output widget -- a ring buffer of Unicode display cells (scrollback
 * history + active display), mouse text selection, and real
 * escape-sequence-driven colors/attributes/cursor control. See
 * README-Fl_Terminal.txt (same directory FLTK) for the design
 * rationale behind the ring-buffer indexing math this module ports
 * faithfully.
 *
 * **Milestone 1**: the core data structures (`Utf8Char`, `CharStyle`,
 * `Cursor`, `Margin`, `RingBuffer`, `Selection`, `PartialUtf8Buf`),
 * plain ASCII/UTF-8 text output (`append()`/`print_char()`/
 * `plot_char()`), cursor movement, tabstops, clear operations,
 * insert/delete rows/chars, scrolling, mouse text selection + copy
 * (Ctrl-C/Ctrl-A/middle-mouse), `draw()`/`resize()`/`handle()`, and
 * both scrollbars.
 *
 * **Milestone 2**: real ANSI/VT100/xterm escape-sequence parsing --
 * `EscapeSeq::parse()`'s full character-by-character state machine,
 * `handle_escseq()`'s CSI-code dispatch table (cursor positioning,
 * clearing, scrolling, insert/delete, tabstops, save/restore cursor),
 * and `handle_SGR()` (colors -- both the 8-color xterm palette and the
 * 24-bit RGB extension -- plus bold/dim/italic/underline/inverse/
 * strikeout attributes). `ansi(false)` still falls back to showing
 * every ESC byte as the "unknown character" placeholder, matching
 * FLTK exactly.
 *
 * **Milestone 3** (this pass, small): autoscroll while dragging a
 * selection past the visible top/bottom edge
 * (`handle_selection_autoscroll()`/`autoscroll_timer_cb()`), the one
 * item Milestone 2 tracked as not-yet-ported. This closes out
 * `fl.terminal`'s feature set against FLTK's own public API --
 * nothing else is deliberately deferred.
 *
 * **Known, deliberately deferred gap:** `samples/test/contrast.d`'s
 * embedded terminal shows 9 display rows where real FLTK shows 10, when
 * constructed via the 4-arg constructor (`fontsize_defer_ = false`,
 * used by `contrast.d` and its own FLTK `.cxx`) *before* any window has
 * been `show()`n (as `contrast.d` does -- `Terminal` before
 * `window.show()`, matching FLTK's own construction order exactly): no
 * X display exists yet at that point in this port, so `height()`'s
 * immediate `CharStyle.update()` call silently falls back to a
 * placeholder value (`size + 4`) instead of the font's real
 * ascent+descent, and that wrong value is never recomputed once a
 * display does exist. `height()`'s own formula matches FLTK's
 * `ascent+descent` exactly once a display exists (a same-size
 * standalone `Terminal` built *after* a window is shown computes the
 * same 10 rows real FLTK does) -- this is a *timing* bug, not a formula
 * bug. Root cause:
 * FLTK's `fontopen()` (`Fl_Xlib_Graphics_Driver_font_xft.cxx`)
 * calls `fl_open_display()` **unconditionally** on every font lookup,
 * so FLTK's very first `fl_font()` call anywhere always has a real
 * display to measure against, window-shown or not. This port's
 * `fl.draw.xftFontFor()` deliberately does *not* do that (returns
 * `null` and lets the caller retry later) specifically so `dub test`'s
 * ~114 headless unittest modules -- which call `fl_font()`/`height()`
 * freely -- don't need a real X server at all; matching FLTK's
 * unconditional-open behavior here would need to fail gracefully
 * rather than throwing when no display is reachable, to preserve that.
 * Left as a known limitation rather than changing `fl.draw`'s
 * font-opening behavior project-wide -- revisit if this
 * construct-before-`show()` pattern turns out to affect more than just
 * `Terminal`.
 *
 * Deliberate deviations:
 *
 *  - **No `const`-qualified drawing/read helpers.** FLTK marks
 *    `draw_row()`/`draw_row_bg()`/`draw_buff()`, and every `u8c_xxx_row()`
 *    accessor, `const` -- a promise "this doesn't mutate", enforced
 *    losslessly in C++ via a `const_cast`-based "Effective C++" pair
 *    (a `const` overload doing the real work, a non-`const` overload
 *    forwarding through a cast). D's `const` propagates strictly with
 *    no escape hatch, and nothing in this port ever calls these
 *    methods through a `const Terminal` reference, so the promise has
 *    no actual caller to serve -- this port skips `const` on these
 *    methods entirely rather than fighting D's stricter propagation
 *    the way `fl.browser`'s `findLine()` had to (see that module's own
 *    `cast(Browser) this` workaround). Also means only ONE `u8c_xxx_row()`
 *    overload per accessor is needed, not FLTK's const/non-const pair.
 *
 *  - **`tabstops_` is a growable `bool[]`, not a `malloc()`'d `char*`
 *    plus a separate `tabstops_size_` length field.** D arrays track
 *    their own length and grow in place with no manual `realloc()`/
 *    `free()` bookkeeping -- `tabstops_.length = newsize` already does
 *    exactly what `init_tabstops()`'s manual copy-into-a-bigger-buffer
 *    loop exists to accomplish, so that loop collapses into filling
 *    just the newly-added slots with the default tabstop pattern.
 *
 *  - **`Utf8Char` and `CharStyle` are plain D `struct`s, not
 *    heap-allocated/pointer-managed classes.** FLTK's C++ needs
 *    an explicit copy constructor + `operator=` on `Utf8Char` purely
 *    to manage its fixed `char[4]` buffer correctly during a raw
 *    memberwise copy; a D struct's default memberwise copy already
 *    does the right thing with no custom code, since there's no owned
 *    heap memory involved (just inline fixed-size fields) -- so
 *    neither is ported. `RingBuffer.ringChars_` is therefore a plain
 *    `Utf8Char[]` (a contiguous value-type array, matching FLTK's
 *    `Utf8Char*` C array's memory layout exactly), and pointers into
 *    it (`Utf8Char*`) are taken the same way FLTK's raw pointers
 *    are, valid for as long as no resize reallocates the array
 *    (matching FLTK's own pointer-invalidation-on-resize contract
 *    exactly, not a new hazard this port introduces).
 *
 *  - **`printf()`/`vprintf()` use `std.format` instead of a fixed
 *    1024-byte `vsnprintf()` buffer.** FLTK's own doc comment
 *    calls out the 1024-char cap as a real, documented limitation
 *    ("For printing longer strings, use append()"); `std.format.format()`
 *    has no such cap, so this port's `printf()` has none either --
 *    string interpolation replaces C varargs entirely (no `va_list`
 *    concept exists in D the way it does in C++), matching this
 *    project's usual delegate/D-native substitution for C-only
 *    mechanisms.
 *
 *  - **`Selection` is a genuine (non-`static`) nested D class**, not a
 *    struct holding a raw `Fl_Terminal*` back-pointer -- D's nested
 *    class syntax gives automatic, safe access to the enclosing
 *    `Terminal` instance (`ring_cols()` etc. resolve directly, no
 *    explicit `terminal_.` prefix needed), which is exactly what
 *    FLTK's manually-stored `terminal_` pointer exists to provide
 *    in C++.
 *
 *  - **`EscapeSeq` accumulates each CSI parameter directly as an
 *    `int`**, not into a small text buffer later parsed with
 *    `sscanf()`. See that struct's own doc comment for the full
 *    reasoning -- observably identical to FLTK for every real
 *    escape sequence, and `buff_`/`buffp_`/`buffendp_`/`valbuffp_`/
 *    `append_buff()` have no D equivalent needed at all as a result.
 */
module fl.terminal;

import fl.group : FlGroup;
import fl.widget : Widget;
import fl.scrollbar : Scrollbar;
import fl.slider : horSlider;
import fl.rect : Rect;
import fl.enumerations;
import fl.draw;
import fl.core;
import fl.text_buffer : utf8Len;

version (unittest) import std.algorithm.searching : canFind;

// ---------------------------------------------------------------------
// Small pure helpers -- kept as free functions (not Terminal methods)
// so they're headless-unittestable without a live X display, matching
// this project's usual "pure logic only" testing convention.
// ---------------------------------------------------------------------

private int clamp(int val, int mn, int mx) => (val < mn) ? mn : (val > mx) ? mx : val;

package(fl) int normalizeRow(int row, int maxrows)
{
    row = row % maxrows;
    if (row < 0) row = maxrows + row;
    return row;
}

private int redOf(Color v) => cast(int)((v & 0xff000000) >> 24);
private int grnOf(Color v) => cast(int)((v & 0x00ff0000) >> 16);
private int bluOf(Color v) => cast(int)((v & 0x0000ff00) >> 8);
private Color rgbOf(int r, int g, int b) => cast(Color)((r << 24) | (g << 16) | (b << 8));

package(fl) Color dimColor(Color val)
{
    int r = clamp(redOf(val) - 0x20, 0, 255);
    int g = clamp(grnOf(val) - 0x20, 0, 255);
    int b = clamp(bluOf(val) - 0x20, 0, 255);
    return rgbOf(r, g, b);
}

package(fl) Color boldColor(Color val)
{
    int r = clamp(redOf(val) + 0x20, 0, 255);
    int g = clamp(grnOf(val) + 0x20, 0, 255);
    int b = clamp(bluOf(val) + 0x20, 0, 255);
    return rgbOf(r, g, b);
}

private bool isFrameBox(Boxtype b)
{
    return b == Boxtype.upFrame || b == Boxtype.downFrame
        || b == Boxtype.thinUpFrame || b == Boxtype.thinDownFrame
        || b == Boxtype.engravedFrame || b == Boxtype.embossedFrame
        || b == Boxtype.borderFrame;
}

private bool isUtf8Continuation(char c) => (cast(ubyte) c & 0xc0) == 0x80;

/// Per-character attribute bits (Fl_Terminal::Attrib). Prefixed
/// `term*` to avoid colliding with fl.enumerations' `bold`/`italic`
/// (Font style bits) once both modules are imported together.
alias Attrib = ubyte;
enum Attrib termNormal    = 0x00;
enum Attrib termBold      = 0x01;
enum Attrib termDim       = 0x02;
enum Attrib termItalic    = 0x04;
enum Attrib termUnderline = 0x08;
enum Attrib termInverse   = 0x20;
enum Attrib termStrikeout = 0x80;

/// Per-character flags (Fl_Terminal::CharFlags) -- xterm-color bookkeeping.
alias CharFlags = ubyte;
enum CharFlags cfFgXterm   = 0x01;
enum CharFlags cfBgXterm   = 0x02;
enum CharFlags cfEol       = 0x04;
enum CharFlags cfColorMask = cfFgXterm | cfBgXterm;

/// Output translation flags (Fl_Terminal::OutFlags).
alias OutFlags = ubyte;
enum OutFlags outOff      = 0x00;
enum OutFlags outCrToLf   = 0x01;
enum OutFlags outLfToCr   = 0x02;
enum OutFlags outLfToCrlf = 0x04;

class Terminal : FlGroup
{
    /// Determines when Terminal calls redraw() as new text arrives.
    enum RedrawStyle
    {
        noRedraw,    /// app must call redraw() as needed
        rateLimited, /// timer-controlled redraws (default)
        perWrite,    /// redraw after every append()/printf()/etc.
    }

    /// Horizontal scrollbar visibility behavior.
    enum ScrollbarStyle
    {
        off,      /// always invisible
        autoShow, /// visible only if content is wider than the widget (default)
        on,       /// always visible
    }

    // ------------------------------------------------------------
    // Margin -- space (in pixels) around the text display area.
    // ------------------------------------------------------------
    private struct Margin
    {
        int left_ = 3, right_ = 3, top_ = 3, bottom_ = 3;

        int left() const => left_;
        int right() const => right_;
        int top() const => top_;
        int bottom() const => bottom_;
        void left(int v) { left_ = v; }
        void right(int v) { right_ = v; }
        void top(int v) { top_ = v; }
        void bottom(int v) { bottom_ = v; }
    }

    // ------------------------------------------------------------
    // CharStyle -- current font/attribute/color state, plus cached
    // font metrics.
    // ------------------------------------------------------------
    private struct CharStyle
    {
        Attrib attrib_;
        CharFlags charflags_;
        Color fgcolor_;
        Color bgcolor_;
        Color defaultfgcolor_;
        Color defaultbgcolor_;
        Font fontface_;
        Fontsize fontsize_;
        int fontheight_;
        int fontdescent_;
        int charwidth_;

        this(bool fontsizeDefer)
        {
            attrib_ = termNormal;
            charflags_ = cfFgXterm | cfBgXterm;
            defaultfgcolor_ = 0xd0d0d000; // off white
            defaultbgcolor_ = 0xffffffff; // special "see through" color
            fgcolor_ = defaultfgcolor_;
            bgcolor_ = defaultbgcolor_;
            fontface_ = courier;
            fontsize_ = 14;
            if (!fontsizeDefer) update();
            else updateFake();
        }

        void update()
        {
            fl_font(fontface_, fontsize_);
            fontheight_ = cast(int)(height() + 0.5);
            fontdescent_ = cast(int)(descent() + 0.5);
            charwidth_ = cast(int)(width("X") + 0.5);
        }

        // Deliberately absurd placeholder values until the first real
        // draw() calls update() -- matches FLTK's own "issue 837"
        // workaround (defers font-system calls in headless/fluid
        // contexts where opening a font too early can misbehave).
        void updateFake()
        {
            fontheight_ = 99;
            fontdescent_ = 99;
            charwidth_ = 99;
        }

        Attrib attrib() const => attrib_;
        CharFlags charflags() const => charflags_;

        Color fltkFgColor(ubyte ci) const
        {
            static immutable Color[8] xtermFg = [
                0x00000000, 0xd0000000, 0x00d00000, 0xd0d00000,
                0x0000d000, 0xd000d000, 0x00d0d000, 0xd0d0d000
            ];
            if (ci == 39) return defaultfgcolor_;
            if (ci == 49) return defaultbgcolor_;
            return xtermFg[ci & 0x07];
        }

        Color fltkBgColor(ubyte ci) const
        {
            static immutable Color[8] xtermBg = [
                0x00000000, 0xc0000000, 0x00c00000, 0xc0c00000,
                0x0000c000, 0xc000c000, 0x00c0c000, 0xc0c0c000
            ];
            if (ci == 39) return defaultfgcolor_;
            if (ci == 49) return defaultbgcolor_;
            return xtermBg[ci & 0x07];
        }

        Color fgcolor() const => fgcolor_;
        Color bgcolor() const => bgcolor_;
        Color defaultfgcolor() const => defaultfgcolor_;
        Color defaultbgcolor() const => defaultbgcolor_;
        Font fontface() const => fontface_;
        Fontsize fontsize() const => fontsize_;
        int fontheight() const => fontheight_;
        int fontdescent() const => fontdescent_;
        int charwidth() const => charwidth_;

        CharFlags colorbitsOnly(CharFlags inflags) const => cast(CharFlags)((inflags & ~cfColorMask) | (charflags_ & cfColorMask));

        void attrib(Attrib val) { attrib_ = val; }
        void charflags(CharFlags val) { charflags_ = val; }
        void setCharflag(CharFlags val) { charflags_ |= val; }
        void clrCharflag(CharFlags val) { charflags_ &= ~val; }

        void fgcolor(int r, int g, int b) { fgcolor_ = rgbOf(r, g, b); clrCharflag(cfFgXterm); }
        void bgcolor(int r, int g, int b) { bgcolor_ = rgbOf(r, g, b); clrCharflag(cfBgXterm); }
        void fgcolor(Color val) { fgcolor_ = val; clrCharflag(cfFgXterm); }
        void bgcolor(Color val) { bgcolor_ = val; clrCharflag(cfBgXterm); }
        void fgcolorXterm(Color val) { fgcolor_ = val; setCharflag(cfFgXterm); }
        void bgcolorXterm(Color val) { bgcolor_ = val; setCharflag(cfBgXterm); }
        void fgcolorXterm(ubyte val) { fgcolor_ = fltkFgColor(val); setCharflag(cfFgXterm); }
        void bgcolorXterm(ubyte val) { bgcolor_ = fltkBgColor(val); setCharflag(cfBgXterm); }

        void defaultfgcolor(Color val) { defaultfgcolor_ = val; }
        void defaultbgcolor(Color val) { defaultbgcolor_ = val; }
        void fontface(Font val) { fontface_ = val; update(); }
        void fontsize(Fontsize val) { fontsize_ = val; update(); }

        void sgrReset()
        {
            attrib(termNormal);
            if (charflags() & cfFgXterm) fgcolorXterm(defaultfgcolor_);
            else fgcolor(defaultfgcolor_);
            if (charflags() & cfBgXterm) bgcolorXterm(defaultbgcolor_);
            else bgcolor(defaultbgcolor_);
        }

        private Attrib onoff(bool flag, Attrib a) const => cast(Attrib)(flag ? (attrib_ | a) : (attrib_ & ~a));
        void sgrBold(bool val) { attrib_ = onoff(val, termBold); }
        void sgrDim(bool val) { attrib_ = onoff(val, termDim); }
        void sgrItalic(bool val) { attrib_ = onoff(val, termItalic); }
        void sgrUnderline(bool val) { attrib_ = onoff(val, termUnderline); }
        void sgrDblUnder(bool val) { attrib_ = onoff(val, termUnderline); } // TODO: real double-underline
        void sgrBlink(bool val) { } // not implemented, matches FLTK
        void sgrInverse(bool val) { attrib_ = onoff(val, termInverse); }
        void sgrStrike(bool val) { attrib_ = onoff(val, termStrikeout); }
    }

    // ------------------------------------------------------------
    // Cursor -- position, height, colors.
    // ------------------------------------------------------------
    private struct Cursor
    {
        int col_, row_;
        int h_ = 10;
        Color fgcolor_ = 0xfffff000;
        Color bgcolor_ = 0x00d00000;

        int col() const => col_;
        int row() const => row_;
        int h() const => h_;
        Color fgcolor() const => fgcolor_;
        Color bgcolor() const => bgcolor_;
        void col(int val) { col_ = val >= 0 ? val : 0; }
        void row(int val) { row_ = val >= 0 ? val : 0; }
        void h(int val) { h_ = val; }
        void fgcolor(Color val) { fgcolor_ = val; }
        void bgcolor(Color val) { bgcolor_ = val; }
        int left() { col_ = (col_ > 0) ? (col_ - 1) : 0; return col_; }
        int right() => ++col_;
        int up() { row_ = (row_ > 0) ? (row_ - 1) : 0; return row_; }
        int down() => ++row_;
        bool isRowcol(int drow, int dcol) const => drow == row_ && dcol == col_;
        void scroll(int nrows) { row_ = row_ - nrows > 0 ? row_ - nrows : 0; }
        void home() { row_ = 0; col_ = 0; }
    }

    // ------------------------------------------------------------
    // Utf8Char -- one display cell: text, attributes, colors.
    // ------------------------------------------------------------
    // protected, not private, matching FLTK's own `protected:` section
    // (Fl_Terminal.H:539) -- a real subclass (e.g. one that overrides
    // update_ring()-style ring-buffer introspection for debugging, as
    // test/terminal.cxx's own MyTerminal does) needs to read a cell's
    // attrib()/fgcolor()/bgcolor()/textUtf8() directly. D's `private` is
    // module-scoped (no subclass exception the way C++'s is), so a plain
    // `private` here would make u8cRingRow()'s already-`protected` return
    // type unusable from any subclass outside this module -- confirmed
    // while porting terminal.fl's own MyTerminal.
    protected struct Utf8Char
    {
        enum maxUtf8 = 4;
        char[maxUtf8] text_;
        ubyte len_ = 1;
        Attrib attrib_;
        CharFlags charflags_;
        Color fgcolor_ = 0xffffff00;
        Color bgcolor_ = 0xffffffff;

        static Utf8Char make()
        {
            Utf8Char u;
            u.text_[0] = ' ';
            return u;
        }

        private void textUtf8Raw(const(char)[] text)
        {
            text_[0 .. text.length] = text[];
            len_ = cast(ubyte) text.length;
        }

        void textUtf8(const(char)[] text, const CharStyle style)
        {
            textUtf8Raw(text);
            attrib_ = style.attrib();
            charflags_ = style.colorbitsOnly(charflags_);
            fgcolor_ = style.fgcolor();
            bgcolor_ = style.bgcolor();
        }

        void textAscii(char c, const CharStyle style)
        {
            if (c < 0x20 || c >= 0x7e) return;
            char[1] one = [c];
            textUtf8(one[], style);
        }

        void flFontSet(const CharStyle style) const
        {
            Font face = style.fontface()
                | ((attrib_ & termBold) ? bold : 0)
                | ((attrib_ & termItalic) ? italic : 0);
            fl_font(face, style.fontsize());
        }

        const(char)[] textUtf8() const => text_[0 .. len_];
        Attrib attrib() const => attrib_;
        CharFlags charflags() const => charflags_;
        Color fgcolor() const => fgcolor_;
        Color bgcolor() const => bgcolor_;
        int length() const => cast(int) len_;

        double pwidth() const => width(cast(string) text_[0 .. len_]);
        int pwidthInt() const => cast(int)(pwidth() + 0.5);

        void clear(const CharStyle style)
        {
            textAscii(' ', style);
            charflags_ = 0;
            attrib_ = 0;
        }

        bool isChar(char c) const => text_[0] == c;

        private Color attrColor(Color col, const Widget grp) const
        {
            if (grp !is null && (col == 0xffffffff || col == grp.color())) return grp.color();
            switch (attrib_ & (termBold | termDim))
            {
            case termBold: return boldColor(col);
            case termDim: return dimColor(col);
            default: return col;
            }
        }

        Color attrFgColor(const Widget grp) const
        {
            if (grp !is null && fgcolor_ == 0xffffffff) return grp.color();
            return (charflags_ & cfFgXterm) ? attrColor(fgcolor(), grp) : fgcolor();
        }

        Color attrBgColor(const Widget grp) const
        {
            if (grp !is null && bgcolor_ == 0xffffffff) return grp.color();
            return (charflags_ & cfBgXterm) ? attrColor(bgcolor(), grp) : bgcolor();
        }
    }

    // ------------------------------------------------------------
    // RingBuffer -- the history+display ring buffer. See
    // README-Fl_Terminal.txt for the indexing math this ports.
    // ------------------------------------------------------------
    private struct RingBuffer
    {
        Utf8Char[] ringChars_;
        int ringRows_, ringCols_, nchars_;
        int histRows_, histUse_, dispRows_;
        int offset_;

        void clear()
        {
            ringChars_ = null;
            ringRows_ = ringCols_ = nchars_ = histRows_ = histUse_ = dispRows_ = offset_ = 0;
        }

        void clearHist() { histUse_ = 0; }

        int ringRows() const => ringRows_;
        int ringCols() const => ringCols_;
        int ringSrow() const => 0;
        int ringErow() const => ringRows_ - 1;
        int histRows() const => histRows_;
        int histCols() const => ringCols_;
        int histSrow() const => (offset_ + 0) % ringRows_;
        int histErow() const => (offset_ + histRows_ - 1) % ringRows_;
        int dispRows() const => dispRows_;
        int dispCols() const => ringCols_;
        int dispSrow() const => (offset_ + histRows_) % ringRows_;
        int dispErow() const => (offset_ + histRows_ + dispRows_ - 1) % ringRows_;
        int offset() const => offset_;

        void offsetAdjust(int rows)
        {
            if (!rows) return;
            if (rows > 0)
            {
                offset_ = (offset_ + rows) % ringRows_;
            }
            else
            {
                rows = clamp(-rows, 1, ringRows_);
                offset_ -= rows;
                if (offset_ < 0) offset_ += ringRows_;
            }
        }

        void histRows(int val) { histRows_ = val; }
        void dispRows(int val) { dispRows_ = val; }

        int histUse() const => histUse_;
        void histUse(int val) { histUse_ = val; }
        int histUseSrow() const => (offset_ + histRows_ - histUse_) % ringRows_;

        Utf8Char[] ringChars() => ringChars_;

        bool isHistRingRow(int grow) const
        {
            grow %= ringRows_;
            grow -= offset_;
            if (grow < 0) grow = ringRows_ + grow;
            return grow >= 0 && grow <= histRows_ - 1;
        }

        bool isDispRingRow(int grow) const
        {
            grow %= ringRows_;
            grow -= offset_;
            if (grow < 0) grow = ringRows_ + grow;
            int dtop = histRows_;
            int dbot = histRows_ + dispRows_ - 1;
            return grow >= dtop && grow <= dbot;
        }

        Utf8Char* u8cRingRow(int row)
        {
            row = normalizeRow(row, ringRows());
            return &ringChars_[row * ringCols()];
        }

        Utf8Char* u8cHistRow(int hrow)
        {
            int rowi = normalizeRow(hrow, histRows());
            rowi = (rowi + offset_) % ringRows_;
            return &ringChars_[rowi * ringCols()];
        }

        Utf8Char* u8cHistUseRow(int hurow)
        {
            if (histUse_ == 0) return null;
            hurow = hurow % histUse_;
            hurow = histRows_ - histUse_ + hurow;
            hurow = (hurow + offset_) % ringRows_;
            return &ringChars_[hurow * ringCols()];
        }

        Utf8Char* u8cDispRow(int drow)
        {
            int rowi = normalizeRow(drow, dispRows());
            rowi = (histRows_ + rowi + offset_) % ringRows_;
            return &ringChars_[rowi * ringCols()];
        }

        void moveDispRow(int srcRow, int dstRow)
        {
            Utf8Char* src = u8cDispRow(srcRow);
            Utf8Char* dst = u8cDispRow(dstRow);
            for (int col = 0; col < dispCols(); col++) *dst++ = *src++;
        }

        void clearDispRows(int sdrow, int edrow, const CharStyle style)
        {
            for (int drow = sdrow; drow <= edrow; drow++)
            {
                int row = histRows_ + drow + offset_;
                Utf8Char* u8c = u8cRingRow(row);
                for (int col = 0; col < dispCols(); col++) (u8c++).clear(style);
            }
        }

        void scroll(int rows, const CharStyle style)
        {
            if (rows > 0)
            {
                rows = clamp(rows, 1, dispRows());
                offsetAdjust(rows);
                histUse_ = clamp(histUse_ + rows, 0, histRows_);
                int srow = (dispRows() - rows) % dispRows();
                int erow = dispRows() - 1;
                clearDispRows(srow, erow, style);
            }
            else
            {
                rows = clamp(-rows, 1, dispRows());
                for (int row = dispRows() - 1; row >= 0; row--)
                {
                    int srcRow = row - rows;
                    int dstRow = row;
                    if (srcRow >= 0) moveDispRow(srcRow, dstRow);
                    else clearDispRows(dstRow, dstRow, style);
                }
            }
        }

        void create(int drows, int dcols, int hrows)
        {
            clear();
            histRows_ = hrows;
            histUse_ = 0;
            dispRows_ = drows;
            ringRows_ = histRows_ + dispRows_;
            ringCols_ = dcols;
            nchars_ = ringRows_ * ringCols_;
            ringChars_ = new Utf8Char[](nchars_);
            foreach (ref c; ringChars_) c = Utf8Char.make();
        }

        // Ported from new_copy(): rebuild the ring at a new size,
        // preserving as much of the old display+history as fits,
        // starting from the bottom of the old display and working
        // backwards. See README-Fl_Terminal.txt's diagram.
        private void newCopy(int drows, int dcols, int hrows)
        {
            int addhist = dispRows() - drows;
            int newRingRows = drows + hrows;
            int newHistUse = clamp(histUse_ + addhist, 0, hrows);
            int newNchars = newRingRows * dcols;
            auto newRingChars = new Utf8Char[](newNchars);
            foreach (ref c; newRingChars) c = Utf8Char.make();

            int dstCols = dcols;
            int srcStopRow = histUseSrow();
            int tcols = dcols < ringCols() ? dcols : ringCols();
            int srcRow = histUseSrow() + histUse_ + dispRows_ - 1;
            int dstRow = newRingRows - 1;
            while (srcRow >= srcStopRow && dstRow >= 0)
            {
                Utf8Char* src = u8cRingRow(srcRow);
                Utf8Char[] dst = newRingChars[dstRow * dstCols .. dstRow * dstCols + tcols];
                for (int col = 0; col < tcols; col++) dst[col] = src[col];
                srcRow--;
                dstRow--;
            }

            ringChars_ = newRingChars;
            ringRows_ = newRingRows;
            ringCols_ = dcols;
            nchars_ = newNchars;
            histRows_ = hrows;
            histUse_ = newHistUse;
            dispRows_ = drows;
            offset_ = 0;
        }

        void resize(int drows, int dcols, int hrows, const CharStyle style)
        {
            int newRows = drows + hrows;
            int oldRows = dispRows() + histRows();
            bool colsChanged = dcols != dispCols();
            bool rowsChanged = newRows != oldRows;
            if (colsChanged || rowsChanged)
            {
                newCopy(drows, dcols, hrows);
            }
            else
            {
                int addhist = dispRows() - drows;
                histRows_ = hrows;
                dispRows_ = drows;
                histUse_ = clamp(histUse_ + addhist, 0, hrows);
            }
        }

        void changeDispRows(int drows, const CharStyle style) { resize(drows, ringCols(), histRows(), style); }
        void changeDispCols(int dcols, const CharStyle style) { resize(dispRows(), dcols, histRows(), style); }
    }

    // ------------------------------------------------------------
    // EscapeSeq -- ESC-sequence parsing state machine (Milestone 2).
    //
    // Deliberate deviation: FLTK accumulates each CSI parameter's
    // digits into a small text buffer (`buff_[80]`) and converts it
    // with `sscanf()` once the parameter ends (on `;` or the final
    // letter). This port accumulates the value directly as an `int`
    // while digits arrive (`curVal_`/`curValStarted_`) instead --
    // `buff_`/`buffp_`/`buffendp_`/`valbuffp_`/`append_buff()` have no
    // D equivalent needed at all, since nothing outside this struct
    // ever reads the raw sequence text (only the parsed `vals_[]`/
    // `esc_mode_`/`is_csi()` are exposed). Observably identical to
    // FLTK for every real escape sequence (values 0-1023, per
    // `& 0x3ff`'s own DoS-prevention clamp -- applied after *every*
    // digit here rather than once at the end, since without a text
    // buffer there's no natural "end" to clamp at; this only differs
    // from FLTK's result for deliberately-pathological >4-digit
    // parameters, which have no legitimate meaning in any real
    // sequence either way).
    // ------------------------------------------------------------
    private struct EscapeSeq
    {
        enum maxvals = 20;
        enum success = 0;
        enum fail = -1;
        enum completed = 1;

        // Explicit `= 0` is load-bearing, not decoration: D's `char.init`
        // is 0xFF (an invalid UTF-8 lead byte, the language's designated
        // "uninitialized char" sentinel), not `0` -- unlike C++, where a
        // freshly-constructed `char esc_mode_` member is whatever
        // garbage was on the stack until Fl_Terminal::EscapeSeq's own
        // ctor calls reset() to zero it. Without this initializer,
        // parseInProgress() (`escMode_ != 0`) reads true from the
        // moment this struct is default-constructed as a Terminal
        // field, permanently short-circuiting printChar() into the
        // "escape sequence in progress" branch for every character
        // ever printed -- caught via a real test failure (append()
        // silently not advancing the cursor at all) in Milestone 1,
        // before being traced back to this.
        char escMode_ = 0;
        bool csi_;
        int[maxvals] vals_;
        int vali_;
        int saveRow_ = -1, saveCol_ = -1;

        private bool curValStarted_;
        private int curVal_;

        void reset()
        {
            escMode_ = 0;
            csi_ = false;
            vali_ = 0;
            vals_[] = 0;
            curValStarted_ = false;
            curVal_ = 0;
        }

        char escMode() const => escMode_;
        void escMode(char val) { escMode_ = val; }
        int totalVals() const => vali_;
        int val(int i) const => vals_[i];
        bool parseInProgress() const => escMode_ != 0;
        bool isCsi() const => csi_;
        int defvalmax(int dval, int max) const => totalVals() == 0 ? dval : clamp(vals_[0], 0, max);

        void saveCursor(int row, int col) { saveRow_ = row; saveCol_ = col; }
        void restoreCursor(out int row, out int col) { row = saveRow_; col = saveCol_; }

        // Ported from append_val(): commits the currently-accumulated
        // parameter (or 0, if no digits were seen at all -- matching
        // FLTK, this deliberately does NOT advance vali_ in that
        // case, e.g. so consecutive ';'s without digits between them
        // keep overwriting the same still-uncommitted slot, exactly
        // as FLTK's own `!valbuffp_` branch does).
        private bool appendVal()
        {
            if (vali_ >= maxvals) { vali_ = maxvals - 1; return false; }
            vals_[vali_] = curValStarted_ ? curVal_ : 0;
            if (curValStarted_ && ++vali_ >= maxvals) { vali_ = maxvals - 1; return false; }
            curValStarted_ = false;
            curVal_ = 0;
            return true;
        }

        /**
         * Ported from EscapeSeq::parse(). Feed one character at a
         * time; call only while parseInProgress() is true (except for
         * the very first ESC byte, which always resets and starts a
         * new sequence regardless). Returns `success` (still parsing),
         * `completed` (a full sequence was parsed -- `escMode()`/
         * `isCsi()`/`totalVals()`/`val()` now describe it), or `fail`
         * (invalid sequence; this struct is already reset()).
         */
        int parse(char c)
        {
            if (c == 0) return success;
            if (c == 0x1b)
            {
                reset();
                escMode_ = 0x1b;
                return success;
            }
            if (c < ' ' || c >= 0x7f) { reset(); return fail; }

            if (escMode_ == 0x1b)
            {
                if (c == '[')
                {
                    escMode_ = c;
                    csi_ = true;
                    vali_ = 0;
                    curValStarted_ = false;
                    curVal_ = 0;
                    return success;
                }
                else if ((c >= '@' && c <= 'Z') || (c >= 'a' && c <= 'z'))
                {
                    escMode_ = c;
                    csi_ = false;
                    vali_ = 0;
                    curValStarted_ = false;
                    curVal_ = 0;
                    return completed;
                }
                else
                {
                    reset();
                    return fail;
                }
            }
            else if (escMode_ == '[')
            {
                if (c == ';')
                {
                    if (!appendVal()) { reset(); return fail; }
                    return success;
                }
                if (c >= '0' && c <= '9')
                {
                    if (!curValStarted_) { curValStarted_ = true; curVal_ = 0; }
                    curVal_ = clamp(curVal_ * 10 + (c - '0'), 0, 0x3ff);
                    return success;
                }
                // Not ';' or a digit? Fall thru to the [A-Z,a-z] check below.
            }
            else
            {
                reset();
                return fail;
            }

            if ((c >= '@' && c <= 'Z') || (c >= 'a' && c <= 'z'))
            {
                if (!appendVal()) { reset(); return fail; }
                escMode_ = c;
                return completed;
            }
            reset();
            return fail;
        }
    }

    // ------------------------------------------------------------
    // PartialUtf8Buf -- buffers a UTF-8 char split across write calls.
    // ------------------------------------------------------------
    private struct PartialUtf8Buf
    {
        char[10] buf_;
        int buflen_, clen_;

        void clear() { buflen_ = 0; clen_ = 0; }
        bool isContinuation(char c) const => isUtf8Continuation(c);
        const(char)[] buf() const => buf_[0 .. buflen_];
        int buflen() const => buflen_;

        bool append(const(char)[] p)
        {
            if (p.length == 0) return true;
            if (buflen_ + cast(int) p.length >= buf_.length) { clear(); return false; }
            if (buflen_ == 0) clen_ = utf8Len(p[0]);
            buf_[buflen_ .. buflen_ + p.length] = p[];
            buflen_ += cast(int) p.length;
            return true;
        }

        bool isComplete() const => buflen_ != 0 && buflen_ == clen_;
    }

    // ------------------------------------------------------------
    // Selection -- mouse text selection state. A genuine (non-static)
    // nested class, so it can reach the enclosing Terminal's
    // ringCols() directly -- see the module comment.
    // ------------------------------------------------------------
    private final class Selection
    {
        int srow_, scol_, erow_, ecol_;
        int pushRow_ = -1, pushCol_ = -1;
        bool pushCharRight_;
        Color selectionbgcolor_ = 0xffffff00;
        Color selectionfgcolor_ = 0x00000000;
        int state_;
        bool isSelection_;

        int srow() const => srow_;
        int scol() const => scol_;
        int erow() const => erow_;
        int ecol() const => ecol_;

        void pushClear() { pushRow_ = pushCol_ = -1; pushCharRight_ = false; }
        void pushRowcol(int row, int col, bool charRight) { pushRow_ = row; pushCol_ = col; pushCharRight_ = charRight; }
        void startPush() { start(pushRow_, pushCol_, pushCharRight_); }
        bool draggedOff(int row, int col, bool charRight) const =>
            pushRow_ != row || (pushCol_ + (pushCharRight_ ? 1 : 0)) != (col + (charRight ? 1 : 0));

        void selectionfgcolor(Color val) { selectionfgcolor_ = val; }
        void selectionbgcolor(Color val) { selectionbgcolor_ = val; }
        Color selectionfgcolor() const => selectionfgcolor_;
        Color selectionbgcolor() const => selectionbgcolor_;
        bool isSelection() const => isSelection_;

        bool getSelection(out int srowOut, out int scolOut, out int erowOut, out int ecolOut) const
        {
            srowOut = srow_;
            scolOut = scol_;
            erowOut = erow_;
            ecolOut = ecol_;
            if (!isSelection_) return false;
            if (srow_ == erow_ && scol_ > ecol_)
            {
                int t = scolOut;
                scolOut = ecolOut;
                ecolOut = t;
            }
            if (srow_ > erow_)
            {
                int t = srowOut;
                srowOut = erowOut;
                erowOut = t;
                t = scolOut;
                scolOut = ecolOut;
                ecolOut = t;
            }
            return true;
        }

        bool start(int row, int col, bool charRight)
        {
            srow_ = erow_ = row;
            scol_ = ecol_ = col;
            state_ = 1;
            isSelection_ = true;
            return true;
        }

        bool extend(int row, int col, bool charRight)
        {
            int osrow = srow_, oerow = erow_, oscol = scol_, oecol = ecol_;
            bool oselection = isSelection_;
            if (state_ == 0) return start(row, col, charRight);
            state_ = 2;

            int cr = charRight ? 1 : 0;
            int pcr = pushCharRight_ ? 1 : 0;
            if (row == pushRow_ && (col + cr) == (pushCol_ + pcr))
            {
                srow_ = erow_ = row;
                scol_ = ecol_ = col;
                isSelection_ = false;
            }
            else if (row > pushRow_ || (row == pushRow_ && (col + cr) > (pushCol_ + pcr)))
            {
                scol_ = pushCol_ + pcr;
                ecol_ = col - 1 + cr;
                isSelection_ = true;
            }
            else
            {
                scol_ = pushCol_ - 1 + pcr;
                ecol_ = col + cr;
                isSelection_ = true;
            }

            if (scol_ < 0) scol_ = 0;
            if (ecol_ < 0) ecol_ = 0;
            int maxCol = ringCols() - 1;
            if (scol_ > maxCol) scol_ = maxCol;
            if (ecol_ > maxCol) ecol_ = maxCol;
            srow_ = pushRow_;
            erow_ = row;

            bool changed = osrow != srow_ || oerow != erow_ || oscol != scol_ || oecol != ecol_ || oselection != isSelection_;
            return !changed;
        }

        void end()
        {
            state_ = 3;
            if (erow_ < srow_)
            {
                int t = srow_;
                srow_ = erow_;
                erow_ = t;
                t = scol_;
                scol_ = ecol_;
                ecol_ = t;
            }
            if (erow_ == srow_ && scol_ > ecol_)
            {
                int t = scol_;
                scol_ = ecol_;
                ecol_ = t;
            }
        }

        void select(int srow, int scol, int erow, int ecol)
        {
            srow_ = srow;
            scol_ = scol;
            erow_ = erow;
            ecol_ = ecol;
            state_ = 3;
            isSelection_ = true;
        }

        bool clear()
        {
            bool wasSelected = isSelection();
            srow_ = scol_ = erow_ = ecol_ = 0;
            state_ = 0;
            isSelection_ = false;
            return wasSelected;
        }

        int state() const => state_;

        void scroll(int nrows)
        {
            if (isSelection())
            {
                srow_ -= nrows;
                erow_ -= nrows;
                if (srow_ < 0 || erow_ < 0) clear();
            }
        }
    }

    // ------------------------------------------------------------
    // Terminal fields
    // ------------------------------------------------------------

    /// Vertical scrollbar. Public, matching FLTK.
    Scrollbar scrollbar;
    /// Horizontal scrollbar. Public, matching FLTK.
    Scrollbar hscrollbar;

    private string errorChar_ = "¿"; // "¿"
    private bool fontsizeDefer_;
    private int scrollbarSize_;
    private ScrollbarStyle hscrollbarStyle_;
    private CharStyle currentStyle_;
    private OutFlags oflags_;

    private RingBuffer ring_;
    private Cursor cursor_;
    private Margin margin_;
    private Selection select_;
    private EscapeSeq escseq_;
    private bool showUnknown_;
    private bool ansi_;
    private bool[] tabstops_;
    private Rect scrn_;
    private int autoscrollDir_; // 0=off, 3=scrolling up, 4=scrolling down
    private int autoscrollAmt_; // #pixels above/below edge; sign indicates direction
    private RedrawStyle redrawStyle_;
    private float redrawRate_ = 0.10f;
    private bool redrawModified_;
    private bool redrawTimer_;
    private PartialUtf8Buf pub_;

    /// Default constructor: rows/cols are computed from (W,H) and the
    /// current default font.
    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        select_ = new Selection();
        init_(x, y, w, h, -1, -1, 100, false);
    }

    /// Ported from the FLTK overload that lets the caller force
    /// exact rows/cols/history sizes, bypassing font-system calls at
    /// construction time (FLTK's own "issue 837" comment: fluid
    /// needs this in headless mode).
    this(int x, int y, int w, int h, string label, int rows, int cols, int hist)
    {
        super(x, y, w, h, label);
        select_ = new Selection();
        init_(x, y, w, h, rows, cols, hist, true);
    }

    private void init_(int x, int y, int w, int h, int rows, int cols, int hist, bool fontsizeDefer)
    {
        fontsizeDefer_ = fontsizeDefer;
        currentStyle_ = CharStyle(fontsizeDefer);
        oflags_ = outLfToCrlf;
        scrollbarSize_ = 0;
        // Calls the *base* box() setter directly, matching FLTK's
        // own explicit `Fl_Group::box(FL_DOWN_FRAME)` qualification --
        // the virtual override below calls updateScreen(), which
        // reaches updateScrollbar(), which needs scrollbar/hscrollbar
        // to already exist; those aren't created until later in this
        // same constructor. Same category of "don't call an override
        // that touches not-yet-initialized state from your own
        // constructor" pitfall as fl.table.Table's construction-order
        // note in CLAUDE.md, just via an explicit same-object call
        // here rather than virtual dispatch during base construction.
        super.box(Boxtype.downFrame);
        updateScreenXywh();

        if (rows < 0 || cols < 0)
        {
            int newrows = hToRow(scrn_.h());
            int newcols = wToCol(scrn_.w());
            if (newrows < 1) newrows = 1;
            if (newcols < 1) newcols = 1;
            createRing(newrows, newcols, hist);
        }
        else
        {
            // FLTK hardcodes `100` here instead of using `hist` --
            // a real bug (see FLTK_ISSUES.md): the explicit-size
            // constructor's own doc comment says it lets the caller
            // "force the rows, columns and history to specific
            // sizes", but `hist` is silently discarded whenever
            // rows/cols are both given (the only case this
            // constructor is ever actually used for -- the other
            // branch, `rows<0||cols<0`, is only reachable from the
            // *other*, 4-arg constructor, which always passes -1/-1).
            // Fixed here rather than replicated, since the fix is
            // obvious, zero-risk, and faithfully replicating it would
            // defeat this constructor's entire documented purpose.
            createRing(rows, cols, hist);
        }

        redrawStyle_ = RedrawStyle.rateLimited;
        redrawRate_ = 0.10f;
        redrawModified_ = false;
        redrawTimer_ = false;

        scrollbar = new Scrollbar(this.x(), this.y(), scrollbarActualSize(), this.h());
        scrollbar.value(0);
        scrollbar.linesize(3);
        scrollbar.callback((wd) { redraw(); });

        hscrollbar = new Scrollbar(this.x(), this.y(), this.w(), scrollbarActualSize());
        hscrollbar.type(horSlider);
        hscrollbar.value(0);
        hscrollbar.callback((wd) { redraw(); });

        hscrollbarStyle_ = ScrollbarStyle.autoShow;

        resizable(null);
        clipChildren(true);
        color(0x00000000); // black bg by default
        updateScreen(true);
        clearScreenHome();
        clearHistory();
        showUnknown_ = false;
        ansi_ = true;
        end();
    }

    ~this()
    {
        if (autoscrollDir_)
        {
            fl.core.removeTimeout(&autoscrollTimerCb);
            autoscrollDir_ = 0;
        }
        if (redrawTimer_)
        {
            fl.core.removeTimeout(&redrawTimerCb);
            redrawTimer_ = false;
        }
    }

    // ------------------------------------------------------------
    // Ring buffer access (protected: internal short names, matching
    // FLTK's own "don't make these public" comment).
    // ------------------------------------------------------------

    protected int ringRows() const => ring_.ringRows();
    protected int ringCols() const => ring_.ringCols();
    protected int ringSrow() const => ring_.ringSrow();
    protected int ringErow() const => ring_.ringErow();
    protected int histRows() const => ring_.histRows();
    protected int histCols() const => ring_.histCols();
    protected int histSrow() const => ring_.histSrow();
    protected int histErow() const => ring_.histErow();
    protected int histUse() const => ring_.histUse();
    protected int histUseSrow() const => ring_.histUseSrow();
    protected int dispRows() const => ring_.dispRows();
    protected int dispCols() const => ring_.dispCols();
    protected int dispSrow() const => ring_.dispSrow();
    protected int dispErow() const => ring_.dispErow();
    protected int offset() const => ring_.offset();

    protected Utf8Char* u8cRingRow(int grow) => ring_.u8cRingRow(grow);
    protected Utf8Char* u8cHistRow(int hrow) => ring_.u8cHistRow(hrow);
    protected Utf8Char* u8cHistUseRow(int hurow) => ring_.u8cHistUseRow(hurow);
    protected Utf8Char* u8cDispRow(int drow) => ring_.u8cDispRow(drow);
    private Utf8Char* u8cCursor() => u8cDispRow(cursor_.row()) + cursor_.col();

    private void createRing(int drows, int dcols, int hrows)
    {
        if (dcols != ring_.ringCols()) initTabstops(dcols);
        ring_.create(drows, dcols, hrows);
        cursor_.home();
    }

    // ------------------------------------------------------------
    // Tabstops -- a growable bool[] replaces FLTK's malloc()'d
    // char* + separate size field (see the module comment).
    // ------------------------------------------------------------

    private void initTabstops(int newsize)
    {
        if (newsize > cast(int) tabstops_.length)
        {
            int oldsize = cast(int) tabstops_.length;
            tabstops_.length = newsize;
            for (int t = oldsize; t < newsize; t++)
                tabstops_[t] = (t % 8) == 0;
        }
    }

    private void defaultTabstops()
    {
        initTabstops(ringCols());
        for (int t = 1; t < cast(int) tabstops_.length; t++)
            tabstops_[t] = (t % 8) == 0;
    }

    private void clearAllTabstops() { tabstops_[] = false; }

    private void setTabstop()
    {
        int index = clamp(cursorCol(), 0, cast(int) tabstops_.length - 1);
        tabstops_[index] = true;
    }

    private void clearTabstop()
    {
        int index = clamp(cursorCol(), 0, cast(int) tabstops_.length - 1);
        tabstops_[index] = false;
    }

    // ------------------------------------------------------------
    // Scrollbars
    // ------------------------------------------------------------

    private void setScrollbarParams(Scrollbar scroll, int mn, int mx)
    {
        bool isHor = scroll.type() == horSlider;
        int diff = mx - mn;
        int length = isHor ? scroll.w() : scroll.h();
        double tabsize = mn / cast(double) mx;
        double minpix = cast(double)(10 > scrollbarActualSize() ? 10 : scrollbarActualSize());
        double minfrac = minpix / length;
        tabsize = minfrac > tabsize ? minfrac : tabsize;
        scroll.sliderSize(tabsize);
        if (isHor) scroll.range(0, diff);
        else scroll.range(diff, 0);
        scroll.step(0.25);
    }

    private void updateScrollbar()
    {
        int valueBefore = cast(int) scrollbar.value();
        {
            int trows = dispRows() + historyUse();
            int vrows = dispRows();
            setScrollbarParams(scrollbar, vrows, trows);
        }
        if (valueBefore == 0) scrollbar.value(0);

        updateScreenXywh();
        int sx = scrn_.r() + margin_.right();
        int sy = scrn_.y() - margin_.top();
        int sw = scrollbarActualSize();
        int sh = scrn_.h() + margin_.top() + margin_.bottom();
        bool vchanged = scrollbar.x() != sx || scrollbar.y() != sy || scrollbar.w() != sw || scrollbar.h() != sh;
        if (vchanged) scrollbar.resize(sx, sy, sw, sh);

        int hh;
        int hx = scrn_.x() - margin_.left();
        int hy = scrn_.b() + margin_.bottom();
        int hw = scrn_.w() + margin_.left() + margin_.right();
        bool hv = hscrollbar.visible();
        int vcols = wToCol(scrn_.w());
        int tcols = dispCols();
        if (vcols > tcols) vcols = tcols;
        setScrollbarParams(hscrollbar, vcols, tcols);
        if (hscrollbarStyle_ == ScrollbarStyle.off)
        {
            hscrollbar.hide();
            hh = 0;
        }
        else if (vcols < tcols || hscrollbarStyle_ == ScrollbarStyle.on)
        {
            hscrollbar.show();
            hh = scrollbarActualSize();
        }
        else
        {
            hscrollbar.hide();
            hh = 0;
        }
        bool hchanged = hscrollbar.x() != hx || hscrollbar.y() != hy || hscrollbar.w() != hw
            || hscrollbar.h() != hh || hscrollbar.visible() != hv;
        if (hchanged) hscrollbar.resize(hx, hy, hw, hh);
        if (vchanged || hchanged)
        {
            initSizes();
            updateScreenXywh();
            displayModified();
        }
        scrollbar.redraw();
    }

    // ------------------------------------------------------------
    // Resizing / refitting (xterm-style; see README-Fl_Terminal.txt).
    // ------------------------------------------------------------

    private void refitDispToScreen()
    {
        int dh = hToRow(scrn_.h());
        int dw = wToCol(scrn_.w()) > dispCols() ? wToCol(scrn_.w()) : dispCols();
        int drows = clamp(dh, 2, dh);
        int dcols = clamp(dw, 10, dw);
        int drowDiff = drows - dispRows();
        bool isEnlarge = drows >= dispRows();

        scrollbar.value(0);

        if (drowDiff)
        {
            if (isEnlarge)
            {
                for (int i = 0; i < drowDiff; i++)
                {
                    if (historyUse() > 0) cursor_.scroll(-1);
                    else scroll(1);
                    ring_.resize(dispRows() + 1, dcols, histRows(), currentStyle_);
                }
            }
            else
            {
                for (int i = 0; i < -drowDiff; i++)
                {
                    int curRow = cursor_.row();
                    bool belowCur = drows > curRow;
                    if (belowCur)
                    {
                        ring_.dispRows(dispRows() - 1);
                    }
                    else
                    {
                        cursorUp(1, false);
                        ring_.resize(dispRows() - 1, dcols, histRows(), currentStyle_);
                    }
                }
            }
        }
        clearMouseSelection();
        updateScreen(false);
    }

    private void resizeDisplayRows(int drows)
    {
        int drowDiff = drows - ring_.dispRows();
        if (drowDiff == 0) return;
        int newDcols = ringCols();
        int newHrows = histRows() - drowDiff;
        if (newHrows < 0) newHrows = 0;
        ring_.resize(drows, newDcols, newHrows, currentStyle_);
        cursor_.scroll(-drowDiff);
        select_.clear();
        updateScrollbar();
    }

    private void resizeDisplayColumns(int dcols)
    {
        if (dcols == dispCols()) return;
        ring_.resize(dispRows(), dcols, histRows(), currentStyle_);
        updateScrollbar();
    }

    private void updateScreenXywh()
    {
        scrn_ = Rect(this);
        scrn_.inset(box());
        scrn_.inset(margin_.left(), margin_.top(), margin_.right(), margin_.bottom());
        scrn_.inset(0, 0, scrollbarActualSize(), 0);
        if (hscrollbar !is null && hscrollbar.visible())
            scrn_.inset(0, 0, 0, scrollbarActualSize());
    }

    private void updateScreen(bool fontChanged)
    {
        if (fontChanged)
        {
            if (!fontsizeDefer_) fl_font(currentStyle_.fontface(), currentStyle_.fontsize());
            cursor_.h(currentStyle_.fontheight());
        }
        updateScreenXywh();
        updateScrollbar();
    }

    // ------------------------------------------------------------
    // API: History / display sizing
    // ------------------------------------------------------------

    int historyRows() const => histRows();
    void historyRows(int hrows)
    {
        if (hrows == historyRows()) return;
        ring_.resize(dispRows(), dispCols(), hrows, currentStyle_);
        updateScreen(false);
        displayModified();
    }

    int historyUse() const => ring_.histUse();

    int displayRows() const => ring_.dispRows();
    void displayRows(int drows)
    {
        if (drows == dispRows()) return;
        ring_.resize(drows, dispCols(), histRows(), currentStyle_);
        updateScreen(false);
        refitDispToScreen();
    }

    int displayColumns() const => ring_.dispCols();
    void displayColumns(int dcols)
    {
        if (dcols == dispCols()) return;
        ring_.resize(dispRows(), dcols, histRows(), currentStyle_);
        updateScreen(false);
        refitDispToScreen();
    }

    protected ref CharStyle currentStyle() return => currentStyle_;
    protected void currentStyle(const CharStyle sty) { currentStyle_ = sty; }

    // ------------------------------------------------------------
    // API: Margins
    // ------------------------------------------------------------

    int marginLeft() const => margin_.left();
    int marginRight() const => margin_.right();
    int marginTop() const => margin_.top();
    int marginBottom() const => margin_.bottom();

    void marginLeft(int val) { margin_.left(clamp(val, 0, w() - 1)); updateScreen(true); refitDispToScreen(); }
    void marginRight(int val) { margin_.right(clamp(val, 0, w() - 1)); updateScreen(true); refitDispToScreen(); }
    void marginTop(int val) { margin_.top(clamp(val, 0, h() - 1)); updateScreen(true); refitDispToScreen(); }
    void marginBottom(int val) { margin_.bottom(clamp(val, 0, h() - 1)); updateScreen(true); refitDispToScreen(); }

    // ------------------------------------------------------------
    // API: Box
    // ------------------------------------------------------------

    override void box(Boxtype val) { super.box(val); updateScreen(false); }
    override Boxtype box() const => super.box();

    // ------------------------------------------------------------
    // API: Text font/size/color
    // ------------------------------------------------------------

    void textfont(Font val) { currentStyle_.fontface(val); updateScreen(true); displayModified(); }
    void textsize(Fontsize val) { currentStyle_.fontsize(val); updateScreen(true); refitDispToScreen(); displayModified(); }

    Font textfont() const => currentStyle_.fontface();
    Fontsize textsize() const => currentStyle_.fontsize();

    void textfgcolorXterm(ubyte val) { currentStyle_.fgcolorXterm(val); }
    void textbgcolorXterm(ubyte val) { currentStyle_.bgcolorXterm(val); }

    void textcolor(Color val) { textfgcolor(val); textfgcolorDefault(val); }
    Color textcolor() const => textfgcolorDefault();

    void textfgcolor(Color val) { currentStyle_.fgcolor(val); }
    void textbgcolor(Color val) { currentStyle_.bgcolor(val); }
    Color textfgcolor() const => currentStyle_.fgcolor();
    Color textbgcolor() const => currentStyle_.bgcolor();

    void textfgcolorDefault(Color val) { currentStyle_.defaultfgcolor(val); }
    void textbgcolorDefault(Color val) { currentStyle_.defaultbgcolor(val); }
    Color textfgcolorDefault() const => currentStyle_.defaultfgcolor();
    Color textbgcolorDefault() const => currentStyle_.defaultbgcolor();

    void selectionfgcolor(Color val) { select_.selectionfgcolor(val); }
    void selectionbgcolor(Color val) { select_.selectionbgcolor(val); }
    Color selectionfgcolor() const => select_.selectionfgcolor();
    Color selectionbgcolor() const => select_.selectionbgcolor();

    void textattrib(Attrib val) { currentStyle_.attrib(val); }
    Attrib textattrib() const => currentStyle_.attrib();

    // ------------------------------------------------------------
    // Mouse coordinate mapping
    // ------------------------------------------------------------

    private int xToGlobCol(int X, int grow, out int gcol, out bool gcr) const
    {
        int cx = scrn_.x();
        auto self = cast(Terminal) this;
        const(Utf8Char)* u8c = self.utf8CharAtGlob(grow, 0);
        for (gcol = 0; gcol < ringCols(); gcol++, u8c++)
        {
            u8c.flFontSet(currentStyle_);
            int cx2 = cx + u8c.pwidthInt();
            if (X >= cx && X < cx2)
            {
                gcr = X > (cx + cx2) / 2;
                return 1;
            }
            cx += u8c.pwidthInt();
        }
        gcol = ringCols() - 1;
        return 0;
    }

    private int xyToGlobRowcol(int X, int Y, out int grow, out int gcol, out bool gcr) const
    {
        if (Y < scrn_.y()) return -1;
        if (Y > scrn_.b()) return -2;
        if (X < scrn_.x()) return -3;
        if (X > scrn_.r()) return -4;
        int toprow = dispSrow() - cast(int) scrollbar.value();
        grow = toprow + (Y - scrn_.y()) / currentStyle_.fontheight();
        return xToGlobCol(X, grow, gcol, gcr);
    }

    // ------------------------------------------------------------
    // API: Clearing
    // ------------------------------------------------------------

    override void clear() { clearScreenHome(); }

    void clear(Color val)
    {
        Color save = textbgcolor();
        textbgcolor(val);
        clearScreenHome();
        textbgcolor(save);
    }

    void clearScreen(bool scrollToHist = true)
    {
        if (scrollToHist) { scroll(dispRows()); return; }
        for (int drow = 0; drow < dispRows(); drow++)
            for (int dcol = 0; dcol < dispCols(); dcol++)
                clearCharAtDisp(drow, dcol);
        clearMouseSelection();
    }

    void clearScreenHome(bool scrollToHist = true) { cursorHome(); clearScreen(scrollToHist); }

    protected void clearSod()
    {
        for (int drow = 0; drow <= cursor_.row(); drow++)
        {
            if (drow == cursor_.row())
                for (int dcol = 0; dcol <= cursor_.col(); dcol++) plotChar(' ', drow, dcol);
            else
                for (int dcol = 0; dcol < dispCols(); dcol++) plotChar(' ', drow, dcol);
        }
    }

    protected void clearEod()
    {
        for (int drow = cursor_.row(); drow < dispRows(); drow++)
        {
            if (drow == cursor_.row())
                for (int dcol = cursor_.col(); dcol < dispCols(); dcol++) plotChar(' ', drow, dcol);
            else
                for (int dcol = 0; dcol < dispCols(); dcol++) plotChar(' ', drow, dcol);
        }
    }

    protected void clearEol()
    {
        Utf8Char* u8c = u8cDispRow(cursor_.row()) + cursor_.col();
        for (int col = cursor_.col(); col < dispCols(); col++) (u8c++).clear(currentStyle_);
    }

    protected void clearSol()
    {
        Utf8Char* u8c = u8cDispRow(cursor_.row());
        for (int col = 0; col <= cursor_.col(); col++) (u8c++).clear(currentStyle_);
    }

    protected void clearLine(int drow)
    {
        Utf8Char* u8c = u8cDispRow(drow);
        for (int col = 0; col < dispCols(); col++) (u8c++).clear(currentStyle_);
    }

    protected void clearLine() { clearLine(cursor_.row()); }

    void clearHistory()
    {
        ring_.clearHist();
        scrollbar.value(0);
        for (int hrow = 0; hrow < histRows(); hrow++)
        {
            Utf8Char* u8c = u8cHistRow(hrow);
            for (int hcol = 0; hcol < histCols(); hcol++) (u8c++).clear(currentStyle_);
        }
        updateScrollbar();
    }

    void resetTerminal()
    {
        currentStyle_.sgrReset();
        clearScreenHome();
        clearHistory();
        clearMouseSelection();
        defaultTabstops();
    }

    void cursorHome() { cursor_.col(0); cursor_.row(0); }

    // ------------------------------------------------------------
    // API: Mouse selection
    // ------------------------------------------------------------

    protected bool isSelection() const => select_.isSelection();

    protected const(Utf8Char)* walkSelection(const(Utf8Char)* u8c, ref int row, ref int col) const
    {
        auto self = cast(Terminal) this;
        if (u8c is null)
        {
            int erow, ecol;
            if (!getSelection(row, col, erow, ecol)) return null;
            return self.u8cRingRow(row);
        }
        else
        {
            int srow, scol, erow, ecol;
            if (!getSelection(srow, scol, erow, ecol)) return null;
            if (row == erow && col == ecol) return null;
            if (++col >= ringCols()) { col = 0; ++row; }
        }
        return self.u8cRingRow(row) + col;
    }

    protected bool getSelection(out int srow, out int scol, out int erow, out int ecol) const =>
        select_.getSelection(srow, scol, erow, ecol);

    protected bool isInsideSelection(int grow, int gcol) const
    {
        if (!isSelection()) return false;
        int ncols = ringCols();
        int check = grow * ncols + gcol;
        int start = select_.srow() * ncols + select_.scol();
        int end = select_.erow() * ncols + select_.ecol();
        if (start > end) { int t = start; start = end; end = t; }
        return check >= start && check <= end;
    }

    protected bool isDispRingRow(int grow) const => ring_.isDispRingRow(grow);

    int selectionTextLen() const
    {
        int row, col, len;
        const(Utf8Char)* u8c = null;
        while ((u8c = walkSelection(u8c, row, col)) !is null) len += u8c.length();
        return len;
    }

    string selectionText() const
    {
        if (!isSelection()) return "";
        char[] buf;
        buf.reserve(selectionTextLen());
        size_t nspc = 0;
        int row, col;
        const(Utf8Char)* u8c = null;
        while ((u8c = walkSelection(u8c, row, col)) !is null)
        {
            buf ~= u8c.textUtf8();
            if (!u8c.isChar(' ')) nspc = buf.length;
            if (col >= ringCols() - 1)
            {
                if (nspc != buf.length)
                {
                    buf.length = nspc;
                    buf ~= '\n';
                    nspc = buf.length;
                }
            }
        }
        return cast(string) buf;
    }

    protected void clearMouseSelection() { select_.clear(); }

    protected bool selectionExtend(int X, int Y)
    {
        if (isSelection())
        {
            int grow, gcol;
            bool gcr;
            if (xyToGlobRowcol(X, Y, grow, gcol, gcr) > 0)
            {
                select_.extend(grow, gcol, gcr);
                return true;
            }
        }
        return false;
    }

    protected void selectWord(int grow, int gcol)
    {
        int r = grow, c = gcol;
        Utf8Char* row = u8cRingRow(r);
        int n = ringCols();
        if (c >= n) return;
        int c0, c1, i;
        if (row[c].textUtf8()[0] == ' ')
        {
            for (i = c; i > 0; i--) if (row[i - 1].textUtf8()[0] != ' ') break;
            c0 = i;
            for (i = c; i < n - 2; i++) if (row[i + 1].textUtf8()[0] != ' ') break;
            c1 = i;
        }
        else
        {
            for (i = c; i > 0; i--) if (row[i - 1].textUtf8()[0] == ' ') break;
            c0 = i;
            for (i = c; i < n - 2; i++) if (row[i + 1].textUtf8()[0] == ' ') break;
            c1 = i;
        }
        select_.select(r, c0, r, c1);
    }

    protected void selectLine(int grow) { select_.select(grow, 0, grow, ringCols() - 1); }

    // ------------------------------------------------------------
    // API: Scrolling / row & char insert-delete
    // ------------------------------------------------------------

    protected void scroll(int rows)
    {
        ring_.scroll(rows, currentStyle_);
        if (rows > 0) updateScrollbar();
        else clearMouseSelection();
    }

    protected void insertRows(int count)
    {
        int dstDrow = dispRows() - 1;
        int srcDrow = clamp(dstDrow - count, 1, dispRows() - 1);
        while (srcDrow >= cursor_.row())
        {
            Utf8Char* src = u8cDispRow(srcDrow--);
            Utf8Char* dst = u8cDispRow(dstDrow--);
            for (int dcol = 0; dcol < dispCols(); dcol++) *dst++ = *src++;
        }
        while (dstDrow >= cursor_.row())
        {
            Utf8Char* dst = u8cDispRow(dstDrow--);
            for (int dcol = 0; dcol < dispCols(); dcol++) (dst++).clear(currentStyle_);
        }
        clearMouseSelection();
    }

    protected void deleteRows(int count)
    {
        int dstDrow = cursor_.row();
        int srcDrow = clamp(dstDrow + count, 1, dispRows() - 1);
        while (srcDrow < dispRows())
        {
            Utf8Char* src = u8cDispRow(srcDrow++);
            Utf8Char* dst = u8cDispRow(dstDrow++);
            for (int dcol = 0; dcol < dispCols(); dcol++) *dst++ = *src++;
        }
        while (dstDrow < dispRows())
        {
            Utf8Char* dst = u8cDispRow(dstDrow++);
            for (int dcol = 0; dcol < dispCols(); dcol++) (dst++).clear(currentStyle_);
        }
        clearMouseSelection();
    }

    private void repeatChar(char c, int rep)
    {
        rep = clamp(rep, 1, dispCols());
        while (rep-- > 0 && cursor_.col() < dispCols()) printChar(c);
    }

    protected void insertCharEol(char c, int drow, int dcol, int rep)
    {
        rep = clamp(rep, 0, dispCols());
        if (rep == 0) return;
        const style = currentStyle_;
        Utf8Char* src = u8cDispRow(drow) + dispCols() - 1 - rep;
        Utf8Char* dst = u8cDispRow(drow) + dispCols() - 1;
        for (int col = dispCols() - 1; col >= dcol; col--)
        {
            if (col >= dcol + rep) *dst-- = *src--;
            else (dst--).textAscii(c, style);
        }
    }

    protected void insertChar(char c, int rep) { insertCharEol(c, cursor_.row(), cursor_.col(), rep); }

    protected void deleteChars(int drow, int dcol, int rep)
    {
        rep = clamp(rep, 0, dispCols());
        if (rep == 0) return;
        const style = currentStyle_;
        Utf8Char* u8c = u8cDispRow(drow);
        for (int col = dcol; col < dispCols(); col++)
        {
            if (col + rep >= dispCols()) u8c[col].textAscii(' ', style);
            else u8c[col] = u8c[col + rep];
        }
    }

    protected void deleteChars(int rep) { deleteChars(cursor_.row(), cursor_.col(), rep); }

    // ------------------------------------------------------------
    // API: Cursor
    // ------------------------------------------------------------

    void cursorfgcolor(Color val) { cursor_.fgcolor(val); }
    void cursorbgcolor(Color val) { cursor_.bgcolor(val); }
    Color cursorfgcolor() const => cursor_.fgcolor();
    Color cursorbgcolor() const => cursor_.bgcolor();

    protected void cursorRow(int row) { cursor_.row(clamp(row, 0, dispRows() - 1)); }
    protected void cursorCol(int col) { cursor_.col(clamp(col, 0, dispCols() - 1)); }
    int cursorRow() const => cursor_.row();
    int cursorCol() const => cursor_.col();

    protected void cursorUp(int count = 1, bool doScroll = false)
    {
        count = clamp(count, 1, dispRows() * 2);
        while (count-- > 0)
        {
            if (cursor_.up() <= 0)
            {
                cursor_.row(0);
                if (doScroll) scroll(-1);
                else return;
            }
        }
    }

    protected void cursorDown(int count = 1, bool doScroll = false)
    {
        count = clamp(count, 1, ringRows());
        while (count-- > 0)
        {
            if (cursor_.down() >= dispRows())
            {
                cursor_.row(dispRows() - 1);
                if (!doScroll) break;
                scroll(1);
            }
        }
    }

    protected void cursorLeft(int count = 1)
    {
        count = clamp(count, 1, dispCols());
        while (count-- > 0)
            if (cursor_.left() < 0) { cursorSol(); return; }
    }

    protected void cursorRight(int count = 1, bool doScroll = false)
    {
        while (count-- > 0)
        {
            if (cursor_.right() >= dispCols())
            {
                if (!doScroll) { cursorEol(); return; }
                else cursorCrlf(1);
            }
        }
    }

    protected void cursorEol() { cursor_.col(dispCols() - 1); }
    protected void cursorSol() { cursor_.col(0); }
    protected void cursorCr() { cursorSol(); }

    protected void cursorCrlf(int count = 1)
    {
        count = clamp(count, 1, ringRows());
        cursorSol();
        cursorDown(count, true);
    }

    protected void cursorTabRight(int count = 1)
    {
        count = clamp(count, 1, dispCols());
        int X = cursor_.col();
        while (count-- > 0)
        {
            while (++X < dispCols())
                if (X < cast(int) tabstops_.length && tabstops_[X]) { cursor_.col(X); return; }
        }
        cursorEol();
    }

    protected void cursorTabLeft(int count = 1)
    {
        count = clamp(count, 1, dispCols());
        int X = cursor_.col();
        while (count-- > 0)
            while (--X > 0)
                if (X < cast(int) tabstops_.length && tabstops_[X]) { cursor_.col(X); return; }
        cursorSol();
    }

    protected void saveCursor() { escseq_.saveCursor(cursor_.row(), cursor_.col()); }
    protected void restoreCursor()
    {
        int row, col;
        escseq_.restoreCursor(row, col);
        if (row != -1 && col != -1) { cursor_.row(row); cursor_.col(col); }
    }

    // ------------------------------------------------------------
    // Printing
    // ------------------------------------------------------------

    private void handleCr()
    {
        if (oflags_ & outCrToLf) cursorDown(1, true);
        else cursorCr();
    }

    private void handleLf()
    {
        if (oflags_ & outLfToCr) cursorCr();
        else if (oflags_ & outLfToCrlf) cursorCrlf();
        else cursorDown(1, true);
    }

    private void handleEsc()
    {
        if (!ansi_) { handleUnknownChar(); return; }
        if (escseq_.escMode() == 0x1b) { handleUnknownChar(); }
        if (escseq_.parse(0x1b) == EscapeSeq.fail) { handleUnknownChar(); return; }
    }

    /**
     * Ported from handle_escseq(): call once per character while
     * escseq_.parseInProgress() is true. Feeds `c` to the parser and,
     * once a full sequence is parsed, dispatches to the right cursor/
     * clear/scroll/SGR operation. See FLTK's own class doc
     * comment table (this module's header) for the ESC-code-to-
     * public-API mapping.
     */
    private void handleEscseq(char c)
    {
        immutable bool doScroll = true;
        immutable bool noScroll = false;

        switch (escseq_.parse(c))
        {
        case EscapeSeq.fail:
            escseq_.reset();
            handleUnknownChar();
            printChar(c);
            return;
        case EscapeSeq.success:
            return;
        default: // EscapeSeq.completed
            break; // fall through to handle the operation below
        }

        char mode = escseq_.escMode();
        int tot = escseq_.totalVals();
        int val0 = tot == 0 ? 0 : escseq_.val(0);
        int val1 = tot < 2 ? 0 : escseq_.val(1);
        int dw = dispCols();
        int dh = dispRows();

        if (escseq_.isCsi())
        {
            switch (mode)
            {
            case '@': // ICH -- insert blank chars (default 1)
                insertChar(' ', escseq_.defvalmax(1, dw));
                break;
            case 'A': // CUU -- cursor up, no scroll/wrap
                cursorUp(escseq_.defvalmax(1, dh));
                break;
            case 'B': // CUD -- cursor down, no scroll/wrap
                cursorDown(escseq_.defvalmax(1, dh), noScroll);
                break;
            case 'C': // CUF -- cursor right, no wrap
                cursorRight(escseq_.defvalmax(1, dw), noScroll);
                break;
            case 'D': // CUB -- cursor left, no wrap
                cursorLeft(escseq_.defvalmax(1, dw));
                break;
            case 'E': // CNL -- cursor next line (crlf)
                cursorCrlf(escseq_.defvalmax(1, dh));
                break;
            case 'F': // CPL -- move to sol, up # lines
                cursorCr();
                cursorUp(escseq_.defvalmax(1, dh));
                break;
            case 'G': // CHA -- cursor horizontal absolute
                switch (clamp(tot, 0, 1))
                {
                case 0: cursorSol(); break;
                case 1: cursorCol(clamp(val0, 1, dw) - 1); break;
                default: break;
                }
                break;
            case 'H': // CUP -- cursor position (1-based)
                switch (clamp(tot, 0, 2))
                {
                case 0: cursorHome(); break;
                case 1: cursorRow(clamp(val0, 1, dh) - 1); cursorCol(0); break;
                case 2: cursorRow(clamp(val0, 1, dh) - 1); cursorCol(clamp(val1, 1, dw) - 1); break;
                default: break;
                }
                break;
            case 'I': // CHT -- cursor forward tab (default 1)
                switch (clamp(tot, 0, 1))
                {
                case 0: cursorTabRight(1); break;
                case 1: cursorTabRight(clamp(val0, 1, dw)); break;
                default: break;
                }
                break;
            case 'J': // ED -- erase in display
                switch (clamp(tot, 0, 1))
                {
                case 0: clearEol(); break;
                case 1:
                    switch (clamp(val0, 0, 3))
                    {
                    case 0: clearEod(); break;
                    case 1: clearSod(); break;
                    case 2: clearScreen(); break;
                    case 3: clearHistory(); break;
                    default: break;
                    }
                    break;
                default: break;
                }
                break;
            case 'K': // EL -- erase in line
                switch (clamp(tot, 0, 1))
                {
                case 0: clearEol(); break;
                case 1:
                    switch (clamp(val0, 0, 2))
                    {
                    case 0: clearEol(); break;
                    case 1: clearSol(); break;
                    case 2: clearLine(); break;
                    default: break;
                    }
                    break;
                default: break;
                }
                break;
            case 'L': // insert # lines (default 1)
                insertRows(escseq_.defvalmax(1, dh));
                break;
            case 'M': // delete # lines (default 1)
                deleteRows(escseq_.defvalmax(1, dh));
                break;
            case 'P': // delete # chars (default 1)
                deleteChars(escseq_.defvalmax(1, dh));
                break;
            case 'S': // scroll up # lines (default 1)
                scroll(+escseq_.defvalmax(1, dh));
                break;
            case 'T': // scroll down # lines (default 1)
                scroll(-escseq_.defvalmax(1, dh));
                break;
            case 'X': // ECH -- erase characters (default 1)
                repeatChar(' ', escseq_.defvalmax(1, dw));
                break;
            case 'Z': // backtab # tabs
                switch (clamp(tot, 0, 1))
                {
                case 0: cursorTabLeft(1); break;
                case 1: cursorTabLeft(clamp(val0, 1, dw)); break;
                default: break;
                }
                break;
            case 'a': // HPR -- TODO, matching FLTK
            case 'b': // REP -- TODO
            case 'd': // VPA -- TODO
            case 'e': // relative line pos -- TODO
                handleUnknownChar();
                break;
            case 'f': // CUP, same as 'H'
                goto case 'H';
            case 'g': // TBC -- tabulation clear
                switch (val0)
                {
                case 0: clearTabstop(); break;
                case 3: clearAllTabstops(); break;
                default: handleUnknownChar(); break;
                }
                break;
            case 'm': handleSGR(); break; // SGR -- set character attributes
            case 's': saveCursor(); break;
            case 'u': restoreCursor(); break;
            case 'q': // set cursor style -- TODO?, matching FLTK
            case 'r': // set scroll region -- TODO
                handleUnknownChar();
                break;
            case 't': handleDECRARA(); break; // DECRARA
            default:
                handleUnknownChar();
                break;
            }
        }
        else
        {
            // Not CSI -- a C1 control code (<ESC>D, etc).
            switch (escseq_.escMode())
            {
            case 'c': resetTerminal(); break; // RIS -- reset to initial state
            case 'D': cursorDown(1, doScroll); break; // down a line, scroll at bottom
            case 'E': cursorCrlf(); break;
            case 'H': setTabstop(); break;
            case 'M': cursorUp(1, true); break; // RI -- reverse index (up w/scroll)
            case '7': handleUnknownChar(); break; // save cursor & attrs -- TODO
            case '8': handleUnknownChar(); break; // restore cursor & attrs -- TODO
            default:
                handleUnknownChar();
                break;
            }
        }
        escseq_.reset();
    }

    /**
     * Ported from handle_SGR(): ESC[...m -- Set Graphics Rendition.
     * Handles the combined-values form (e.g. ESC[1;31m for bold red)
     * and the 24-bit RGB extension (ESC[38;2;r;g;bm / ESC[48;2;r;g;bm).
     */
    private void handleSGR()
    {
        int tot = escseq_.totalVals();
        if (tot == 0) { currentStyle_.sgrReset(); return; }

        int rgbcode, rgbmode, r, g, b;
        for (int i = 0; i < tot; i++)
        {
            int val = escseq_.val(i);
            bool skipRest = false;

            switch (rgbmode)
            {
            case 0:
                if (val == 38 || val == 48) { rgbmode = 1; rgbcode = val; skipRest = true; }
                break;
            case 1:
                if (val == 2) { rgbmode++; skipRest = true; }
                else { rgbcode = rgbmode = 0; handleUnknownChar(); }
                break;
            case 2:
                r = clamp(val, 0, 255);
                rgbmode++;
                skipRest = true;
                break;
            case 3:
                g = clamp(val, 0, 255);
                rgbmode++;
                skipRest = true;
                break;
            case 4:
                b = clamp(val, 0, 255);
                if (rgbcode == 38) currentStyle_.fgcolor(r, g, b);
                else if (rgbcode == 48) currentStyle_.bgcolor(r, g, b);
                rgbcode = rgbmode = 0;
                skipRest = true;
                break;
            default:
                break;
            }
            if (skipRest) continue;

            if (val < 10)
            {
                switch (val)
                {
                case 0: currentStyle_.sgrReset(); break;
                case 1: currentStyle_.sgrBold(true); break;
                case 2: currentStyle_.sgrDim(true); break;
                case 3: currentStyle_.sgrItalic(true); break;
                case 4: currentStyle_.sgrUnderline(true); break;
                case 5: currentStyle_.sgrBlink(true); break;
                case 6: handleUnknownChar(); break;
                case 7: currentStyle_.sgrInverse(true); break;
                case 8: handleUnknownChar(); break;
                case 9: currentStyle_.sgrStrike(true); break;
                default: break;
                }
            }
            else if (val >= 21 && val <= 29)
            {
                switch (val)
                {
                case 21: currentStyle_.sgrDblUnder(true); break;
                case 22: currentStyle_.sgrDim(false); currentStyle_.sgrBold(false); break;
                case 23: currentStyle_.sgrItalic(false); break;
                case 24: currentStyle_.sgrUnderline(false); break;
                case 25: currentStyle_.sgrBlink(false); break;
                case 26: handleUnknownChar(); break;
                case 27: currentStyle_.sgrInverse(false); break;
                case 28: handleUnknownChar(); break;
                case 29: currentStyle_.sgrStrike(false); break;
                default: break;
                }
            }
            else if (val >= 30 && val <= 37)
            {
                currentStyle_.fgcolorXterm(cast(ubyte)(val - 30));
            }
            else if (val == 39)
            {
                currentStyle_.fgcolorXterm(currentStyle_.defaultfgcolor());
            }
            else if (val >= 40 && val <= 47)
            {
                currentStyle_.bgcolorXterm(cast(ubyte)(val - 40));
            }
            else if (val == 49)
            {
                currentStyle_.bgcolorXterm(currentStyle_.defaultbgcolor());
            }
            else
            {
                handleUnknownChar();
            }
        }
    }

    /// Ported from handle_DECRARA() -- FLTK's own body is just a
    /// `// TODO: MAYBE NEVER` comment, i.e. a permanent, deliberate
    /// stub (DECRARA reverses attributes within a rectangular screen
    /// region; xterm supports it, gnome-terminal doesn't, and
    /// FLTK never implemented it either). Ported as the same
    /// permanent no-op, not a Milestone-3-or-later gap.
    private void handleDECRARA() { }

    void outputTranslate(OutFlags val) { oflags_ = val; }
    OutFlags outputTranslate() const => oflags_;

    private void handleCtrl(char c)
    {
        switch (c)
        {
        case '\b': cursorLeft(); return;
        case '\r': handleCr(); return;
        case '\n': handleLf(); return;
        case '\t': cursorTabRight(); return;
        case 0x1b: handleEsc(); return;
        default: handleUnknownChar(); return;
        }
    }

    private static bool isPrintable(char c) => c >= 0x20 && c <= 0x7e;
    private static bool isCtrl(char c) => c >= 0x00 && c < 0x20;

    private void displayModifiedClear() { redrawModified_ = false; }

    void displayModified()
    {
        if (redrawStyle_ == RedrawStyle.rateLimited)
        {
            if (!redrawModified_)
            {
                if (!redrawTimer_)
                {
                    fl.core.addTimeout(0.01, &redrawTimerCb);
                    redrawTimer_ = true;
                }
                redrawModified_ = true;
            }
        }
        else if (redrawStyle_ == RedrawStyle.perWrite)
        {
            if (!redrawModified_)
            {
                redrawModified_ = true;
                redraw();
            }
        }
    }

    private void redrawTimerCb()
    {
        if (redrawModified_)
        {
            redraw();
            redrawModified_ = false;
            fl.core.repeatTimeout(redrawRate_, &redrawTimerCb);
        }
        else
        {
            fl.core.removeTimeout(&redrawTimerCb);
            redrawTimer_ = false;
        }
    }

    private void clearCharAtDisp(int drow, int dcol) { (u8cDispRow(drow) + dcol).clear(currentStyle_); }

    protected const(Utf8Char)* utf8CharAtDisp(int drow, int dcol) const
    {
        auto self = cast(Terminal) this;
        return self.u8cDispRow(drow) + dcol;
    }

    protected const(Utf8Char)* utf8CharAtGlob(int grow, int gcol) const
    {
        auto self = cast(Terminal) this;
        return self.u8cRingRow(grow) + gcol;
    }

    void plotChar(const(char)[] text, int drow, int dcol)
    {
        Utf8Char* u8c = u8cDispRow(drow) + dcol;
        if (text.length < 1 || text.length > Utf8Char.maxUtf8 || cast(int) text.length != utf8Len(text[0]))
        {
            handleUnknownChar(drow, dcol);
            return;
        }
        u8c.textUtf8(text, currentStyle_);
    }

    void plotChar(char c, int drow, int dcol)
    {
        if (!isPrintable(c)) { handleUnknownChar(drow, dcol); return; }
        Utf8Char* u8c = u8cDispRow(drow) + dcol;
        u8c.textAscii(c, currentStyle_);
    }

    void printChar(const(char)[] text)
    {
        if (text.length == 0) return;
        if (isCtrl(text[0]))
        {
            handleCtrl(text[0]);
        }
        else if (escseq_.parseInProgress())
        {
            // Escape sequences are always pure ASCII -- matching
            // FLTK, only the first byte of a (possibly multi-byte
            // UTF-8) char is ever fed to the parser here.
            handleEscseq(text[0]);
        }
        else
        {
            plotChar(text, cursorRow(), cursorCol());
            cursorRight(1, true);
        }
    }

    void printChar(char c)
    {
        if (isCtrl(c))
        {
            handleCtrl(c);
        }
        else if (escseq_.parseInProgress())
        {
            handleEscseq(c);
        }
        else
        {
            plotChar(c, cursorRow(), cursorCol());
            cursorRight(1, true);
        }
    }

    private void utf8CacheClear() { pub_.clear(); }
    private void utf8CacheFlush()
    {
        if (pub_.buflen() > 0) printChar(pub_.buf());
        pub_.clear();
    }

    void appendUtf8(const(char)[] buf)
    {
        bool mod;
        if (buf.length == 0) return;
        size_t i;

        if (pub_.buflen() > 0)
        {
            while (i < buf.length && pub_.isContinuation(buf[i]))
            {
                if (!pub_.append(buf[i .. i + 1])) { mod |= handleUnknownChar() != 0; break; }
                i++;
            }
            if (pub_.isComplete()) utf8CacheFlush();
            if (i >= buf.length)
            {
                if (mod) displayModified();
                return;
            }
        }

        while (i < buf.length)
        {
            int clen = utf8Len(buf[i]);
            if (clen == -1)
            {
                mod |= handleUnknownChar() != 0;
                i++;
            }
            else
            {
                size_t remaining = buf.length - i;
                if (cast(size_t) clen > remaining)
                {
                    if (!pub_.append(buf[i .. $])) { mod |= handleUnknownChar() != 0; utf8CacheClear(); }
                    break;
                }
                printChar(buf[i .. i + clen]);
                i += clen;
                mod = true;
            }
        }
        if (mod) displayModified();
    }

    /// Clears the partial-UTF-8 cache -- call before/after a manual
    /// block-read loop, matching FLTK's `append(nullptr)` contract
    /// (a null D string can't be distinguished from an empty one the
    /// same way, so this is a separate, explicitly-named method).
    void appendUtf8Clear() { utf8CacheClear(); }

    void appendAscii(const(char)[] s)
    {
        foreach (c; s) printChar(c);
        displayModified();
    }

    void append(const(char)[] s) { appendUtf8(s); }

    int handleUnknownChar()
    {
        if (!showUnknown_) return 0;
        escseq_.reset();
        printChar(errorChar_);
        return 1;
    }

    int handleUnknownChar(int drow, int dcol)
    {
        if (!showUnknown_) return 0;
        Utf8Char* u8c = u8cDispRow(drow) + dcol;
        u8c.textUtf8(errorChar_, currentStyle_);
        return 1;
    }

    // ------------------------------------------------------------
    // Drawing
    // ------------------------------------------------------------

    private void drawRowBg(int grow, int X, int Y)
    {
        int bgH = currentStyle_.fontheight();
        int bgY = Y;
        int startCol = hscrollbar.visible() ? cast(int) hscrollbar.value() : 0;
        int endCol = dispCols();
        Utf8Char* u8c = u8cRingRow(grow) + startCol;
        Attrib lastattr = u8c.attrib();
        for (int gcol = startCol; gcol < endCol; gcol++, u8c++)
        {
            if (gcol == 0 || u8c.attrib() != lastattr)
            {
                u8c.flFontSet(currentStyle_);
                lastattr = u8c.attrib();
            }
            int pwidth = u8c.pwidthInt();
            Color bgCol = isInsideSelection(grow, gcol)
                ? select_.selectionbgcolor()
                : (u8c.attrib() & termInverse) ? u8c.attrFgColor(this) : u8c.attrBgColor(this);
            if (bgCol != 0xffffffff && bgCol != color())
            {
                fl_color(bgCol);
                fl_rectf(X, bgY, pwidth, bgH);
            }
            X += pwidth;
        }
    }

    private void drawRow(int grow, int Y)
    {
        int X = scrn_.x();
        drawRowBg(grow, X, Y);

        int baseline = Y + currentStyle_.fontheight() - currentStyle_.fontdescent();
        int scrollval = cast(int) scrollbar.value();
        int dispTop = dispSrow() - scrollval;
        int drow = grow - dispTop;
        bool insideDisplay = isDispRingRow(grow);
        int strikeoutY = baseline - currentStyle_.fontheight() / 3;
        int underlineY = baseline;
        Attrib lastattr = 0xff;
        int startCol = hscrollbar.visible() ? cast(int) hscrollbar.value() : 0;
        int endCol = dispCols();
        Utf8Char* u8c = u8cRingRow(grow) + startCol;
        for (int gcol = startCol; gcol < endCol; gcol++, u8c++)
        {
            int dcol = gcol;
            bool isCursor = insideDisplay ? cursor_.isRowcol(drow - scrollval, dcol) : false;
            if (u8c.attrib() != lastattr)
            {
                u8c.flFontSet(currentStyle_);
                lastattr = u8c.attrib();
            }
            int pwidth = u8c.pwidthInt();
            if (isCursor)
            {
                int cx = X;
                int cy = Y + currentStyle_.fontheight() - cursor_.h();
                int cw = pwidth;
                int ch = cursor_.h();
                fl_color(cursorbgcolor());
                if (fl.core.focus() is this) fl_rectf(cx, cy, cw, ch);
                else fl_rect(cx, cy, cw, ch);
            }
            Color fg;
            if (isCursor) fg = cursorfgcolor();
            else fg = isInsideSelection(grow, gcol)
                ? select_.selectionfgcolor()
                : (u8c.attrib() & termInverse) ? u8c.attrBgColor(this) : u8c.attrFgColor(this);
            fl_color(fg);
            if (isCursor)
            {
                // Force BOLD for text under the cursor -- this D port
                // has no fl_font()/fl_size() zero-arg getters for
                // "whatever font is currently set" (unlike FLTK's
                // fl_font()/fl_size()), so the forced-bold face is
                // recomputed directly from u8c's own attrib bits
                // instead of read back from global state.
                Font face = currentStyle_.fontface() | bold | ((u8c.attrib() & termItalic) ? italic : 0);
                fl_font(face, currentStyle_.fontsize());
                lastattr = 0xff;
            }
            if (!u8c.isChar(' ')) fl_draw(cast(string) u8c.textUtf8(), u8c.length(), X, baseline);
            if (u8c.attrib() & termUnderline) fl_line(X, underlineY, X + pwidth, underlineY);
            if (u8c.attrib() & termStrikeout) fl_line(X, strikeoutY, X + pwidth, strikeoutY);
            X += pwidth;
        }
    }

    private void drawBuff(int Y)
    {
        int srow = dispSrow() - cast(int) scrollbar.value();
        int erow = srow + dispRows();
        int rowheight = currentStyle_.fontheight();
        for (int grow = srow; grow < erow && Y < scrn_.b(); grow++)
        {
            drawRow(grow, Y);
            Y += rowheight;
        }
    }

    override void draw()
    {
        if (fontsizeDefer_)
        {
            fontsizeDefer_ = false;
            currentStyle_.update();
            updateScreen(true);
        }
        if (scrollbarSize_ == 0
            && ((scrollbar.visible() && scrollbar.w() != fl.core.scrollbarSize())
                || (hscrollbar.visible() && hscrollbar.h() != fl.core.scrollbarSize())))
        {
            updateScrollbar();
        }
        super.draw();
        if (scrollbar.visible() && hscrollbar.visible())
        {
            int cx = x() + boxDx(box());
            int cy = y() + boxDy(box());
            int cw = w() - boxDw(box());
            int ch = h() - boxDh(box());
            pushClip(cx, cy, cw, ch);
            fl_color(parent().color());
            fl_rectf(scrollbar.x(), hscrollbar.y(), scrollbarActualSize(), scrollbarActualSize());
            popClip();
        }
        if (isFrameBox(box()))
        {
            fl_color(color());
            fl_rectf(scrn_.x(), scrn_.y(), scrn_.w(), scrn_.h());
        }
        pushClip(scrn_.x(), scrn_.y(), scrn_.w(), scrn_.h());
        drawBuff(scrn_.y());
        popClip();
    }

    private int wToCol(int W) const => W / currentStyle_.charwidth();
    private int hToRow(int H) const => H / currentStyle_.fontheight();

    override void resize(int X, int Y, int W, int H)
    {
        super.resize(X, Y, W, H);
        updateScreen(false);
        refitDispToScreen();
    }

    /**
     * Ported from handle_selection_autoscroll(): call while dragging a
     * selection to start/continue/stop the autoscroll timer, based on
     * how far the mouse has strayed above/below the visible screen
     * area (`scrn_`). Only the vertical direction autoscrolls,
     * matching FLTK (no horizontal autoscroll exists here either).
     */
    private void handleSelectionAutoscroll()
    {
        int Y = fl.core.eventY();
        int top = scrn_.y();
        int bot = scrn_.b();
        int dist = Y < top ? Y - top : (Y > bot ? Y - bot : 0);
        if (dist == 0)
        {
            if (autoscrollDir_) fl.core.removeTimeout(&autoscrollTimerCb);
            autoscrollDir_ = 0;
        }
        else
        {
            if (!autoscrollDir_) fl.core.addTimeout(0.01, &autoscrollTimerCb);
            autoscrollAmt_ = dist;
            autoscrollDir_ = dist < 0 ? 3 : 4;
        }
    }

    /// Ported from autoscroll_timer_cb2(): moves the vertical
    /// scrollbar towards the drag direction and extends the selection
    /// to match, then reschedules itself while the timer stays active.
    private void autoscrollTimerCb()
    {
        // NOTE: scrollbar is inverted -- 0 is the tab at the bottom,
        // so minimum() is really the "scrolled all the way back" max.
        int amt = autoscrollAmt_;
        int val = cast(int) scrollbar.value();
        int mx = cast(int)(scrollbar.minimum() + 0.5);
        if (amt < 0) val = val + clamp(-amt / 10, 1, 5);
        else if (amt > 0) val = val - clamp(amt / 10, 1, 5);
        val = clamp(val, 0, mx);
        int diff = val - cast(int) scrollbar.value();
        if (diff < 0) diff = -diff;
        scrollbar.value(val);

        if (diff)
        {
            int srow = select_.srow(), scol = select_.scol();
            int erow = select_.erow(), ecol = select_.ecol();
            int ltcol = 0, rtcol = ringCols() - 1;
            if (amt < 0) { erow -= diff; ecol = ltcol; }
            if (amt > 0) { erow += diff; ecol = rtcol; }
            select_.select(srow, scol, erow, ecol);
        }

        fl.core.repeatTimeout(0.1, &autoscrollTimerCb);
        redraw();
    }

    private int handleSelection(Event e)
    {
        int grow, gcol;
        bool gcr;
        bool isRowcol = xyToGlobRowcol(fl.core.eventX(), fl.core.eventY(), grow, gcol, gcr) > 0;
        switch (e)
        {
        case Event.push:
            if (fl.core.eventState(stateShift))
            {
                if (isSelection())
                {
                    selectionExtend(fl.core.eventX(), fl.core.eventY());
                    redraw();
                    return 1;
                }
            }
            else
            {
                select_.pushRowcol(grow, gcol, gcr);
                if (select_.clear()) redraw();
                if (isRowcol)
                {
                    switch (fl.core.eventClicks())
                    {
                    case 1: selectWord(grow, gcol); break;
                    case 2: selectLine(grow); break;
                    default: break;
                    }
                    return 1;
                }
            }
            if (!fl.core.eventState(stateShift))
            {
                select_.pushClear();
                clearMouseSelection();
                redraw();
            }
            return 0;

        case Event.drag:
            if (isRowcol)
            {
                if (!isSelection())
                {
                    if (select_.draggedOff(grow, gcol, gcr)) select_.startPush();
                }
                else
                {
                    if (select_.extend(grow, gcol, gcr)) redraw();
                }
            }
            // If we leave the screen area, start/continue the
            // autoscroll-select timer.
            handleSelectionAutoscroll();
            return 1;

        case Event.release:
            select_.end();
            if (isSelection())
            {
                string copy = selectionText();
                if (copy.length > 0) fl.core.copy(copy, 0);
            }
            return 1;

        default:
            break;
        }
        return 0;
    }

    override int handle(Event e)
    {
        int ret = super.handle(e);
        if (fl.core.eventInside(scrollbar)) return ret;
        if (fl.core.eventInside(hscrollbar)) return ret;
        switch (e)
        {
        case Event.enter:
        case Event.leave:
            return 1;
        case Event.unfocus:
        case Event.focus:
            redraw();
            return fl.core.visibleFocus() ? 1 : 0;
        case Event.keyDown:
            if (fl.core.eventState(stateCtrl | stateCommand) && fl.core.eventKey() == 'c')
            {
                string copy = isSelection() ? selectionText() : " ";
                if (copy.length > 0) fl.core.copy(copy, 1);
                return 1;
            }
            if (fl.core.eventState(stateCtrl | stateCommand) && fl.core.eventKey() == 'a')
            {
                int srow = dispSrow() - historyUse();
                int erow = dispSrow() + dispRows() - 1;
                select_.select(srow, 0, erow, dispCols() - 1);
                string copy = selectionText();
                if (copy.length > 0) fl.core.copy(copy, 0);
                redraw();
                return 1;
            }
            if (fl.core.focus() is this)
            {
                switch (fl.core.eventKey())
                {
                case pageUp:
                case pageDown:
                case up:
                case down:
                case left:
                case right:
                    return scrollbar.handle(e);
                default:
                    break;
                }
            }
            break;
        case Event.push:
            if (handle(Event.focus)) fl.core.focus(this);
            if (fl.core.eventButton() == leftMouse) ret = handleSelection(Event.push);
            break;
        case Event.drag:
            if (fl.core.eventButton() == leftMouse) ret = handleSelection(Event.drag);
            break;
        case Event.release:
            if (fl.core.eventButton() == leftMouse) ret = handleSelection(Event.release);
            if (autoscrollDir_)
            {
                fl.core.removeTimeout(&autoscrollTimerCb);
                autoscrollDir_ = 0;
            }
            break;
        default:
            break;
        }
        return ret;
    }

    /// Return a copy of all lines in the terminal (including
    /// scrollback history). If `linesBelowCursor` is false (default),
    /// lines below the cursor are omitted.
    string text(bool linesBelowCursor = false) const
    {
        auto self = cast(Terminal) this;
        char[] lines;
        int disprows = linesBelowCursor ? dispRows() - 1 : cursorRow();
        int srow = histUseSrow();
        int erow = srow + historyUse() + disprows;
        for (int row = srow; row <= erow; row++)
        {
            Utf8Char* u8c = self.u8cRingRow(row);
            size_t trim = 0;
            for (int col = 0; col < ringCols(); col++, u8c++)
            {
                lines ~= u8c.textUtf8();
                if (u8c.length() == 1 && u8c.isChar(' ')) trim++;
                else trim = 0;
            }
            if (trim) lines.length -= trim;
            lines ~= '\n';
        }
        return cast(string) lines;
    }

    // ------------------------------------------------------------
    // API: Redraw style/rate, unknown-char, ansi mode
    // ------------------------------------------------------------

    RedrawStyle redrawStyle() const => redrawStyle_;
    void redrawStyle(RedrawStyle val)
    {
        redrawStyle_ = val;
        if (redrawStyle_ != RedrawStyle.rateLimited && redrawTimer_)
        {
            fl.core.removeTimeout(&redrawTimerCb);
            redrawTimer_ = false;
        }
    }

    float redrawRate() const => redrawRate_;
    void redrawRate(float val) { redrawRate_ = val; }

    bool showUnknown() const => showUnknown_;
    void showUnknown(bool val) { showUnknown_ = val; }
    void errorChar(string val) { errorChar_ = val; }
    string errorChar() const => errorChar_;

    bool ansi() const => ansi_;
    void ansi(bool val)
    {
        ansi_ = val;
        if (!ansi_) escseq_.reset();
    }

    int historyLines() const => historyRows();
    void historyLines(int val) { historyRows(val); }

    // ------------------------------------------------------------
    // API: Scrollbar
    // ------------------------------------------------------------

    int scrollbarActualSize() const => scrollbarSize_ != 0 ? scrollbarSize_ : fl.core.scrollbarSize();
    int scrollbarSize() const => scrollbarSize_;
    void scrollbarSize(int val)
    {
        scrollbarSize_ = val;
        updateScrollbar();
        refitDispToScreen();
    }

    ScrollbarStyle hscrollbarStyle() const => hscrollbarStyle_;
    void hscrollbarStyle(ScrollbarStyle val)
    {
        hscrollbarStyle_ = val;
        updateScrollbar();
        refitDispToScreen();
    }

    // ------------------------------------------------------------
    // API: printf() -- uses std.format instead of a fixed 1024-byte
    // vsnprintf() buffer; see the module comment.
    // ------------------------------------------------------------

    void printf(Args...)(string fmt, Args args)
    {
        import std.format : format;

        append(format(fmt, args));
    }
}

unittest
{
    // normalizeRow(): wraps negative and overflowing indices into
    // [0, maxrows).
    assert(normalizeRow(0, 10) == 0);
    assert(normalizeRow(9, 10) == 9);
    assert(normalizeRow(10, 10) == 0);
    assert(normalizeRow(15, 10) == 5);
    assert(normalizeRow(-1, 10) == 9);
    assert(normalizeRow(-10, 10) == 0);
}

unittest
{
    // dimColor()/boldColor(): shift each channel by 0x20, clamped.
    assert(dimColor(0x80808000) == 0x60606000);
    assert(boldColor(0x80808000) == 0xa0a0a000);
    assert(dimColor(0x00000000) == 0x00000000); // clamps at 0
    assert(boldColor(0xffffff00) == 0xffffff00); // clamps at 255
}

unittest
{
    // CharStyle: SGR reset restores default colors/attrib; xterm
    // color setters set the FG_XTERM/BG_XTERM charflag bits.
    auto style = Terminal.CharStyle(true);
    assert(style.attrib() == termNormal);

    style.sgrBold(true);
    assert(style.attrib() & termBold);
    style.sgrBold(false);
    assert(!(style.attrib() & termBold));

    style.fgcolorXterm(cast(ubyte) 1); // red
    assert(style.charflags() & cfFgXterm);
    style.fgcolor(0x12345600); // explicit RGB clears the xterm flag
    assert(!(style.charflags() & cfFgXterm));

    style.sgrBold(true);
    style.sgrReset();
    assert(style.attrib() == termNormal);
    assert(style.fgcolor() == style.defaultfgcolor());
}

unittest
{
    // Utf8Char: default state, ASCII/UTF-8 text assignment, clear().
    auto style = Terminal.CharStyle(true);
    auto u = Terminal.Utf8Char.make();
    assert(u.textUtf8() == " ");
    assert(u.length() == 1);

    u.textAscii('X', style);
    assert(u.textUtf8() == "X");
    assert(u.isChar('X'));

    u.textUtf8("é", style); // 'é', 2 UTF-8 bytes
    assert(u.length() == 2);

    u.clear(style);
    assert(u.textUtf8() == " ");
    assert(u.attrib() == 0);
}

unittest
{
    // Cursor: movement primitives clamp at 0, home() resets both axes.
    Terminal.Cursor c;
    c.row(5);
    c.col(5);
    assert(c.up() == 4);
    assert(c.left() == 4);
    assert(c.right() == 5);
    assert(c.down() == 5);
    c.row(0);
    assert(c.up() == 0); // clamped, doesn't go negative
    c.home();
    assert(c.row() == 0 && c.col() == 0);
}

unittest
{
    // RingBuffer: create()/dispSrow()/histSrow() indexing, and
    // scroll() moving a display row into history.
    Terminal.RingBuffer rb;
    auto style = Terminal.CharStyle(true);
    rb.create(5, 10, 20); // 5 disp rows, 10 cols, 20 hist rows
    assert(rb.ringRows() == 25);
    assert(rb.histRows() == 20);
    assert(rb.dispRows() == 5);
    assert(rb.histUse() == 0);
    assert(rb.dispSrow() == 20); // display starts right after history

    rb.u8cDispRow(0)[0].textAscii('A', style);
    rb.scroll(1, style); // scroll one line into history
    assert(rb.histUse() == 1);
    // The scrolled line ('A') should now be the last "in use" history row.
    assert(rb.u8cHistUseRow(0).isChar('A'));
    // The display's own top row should now be blank (freshly scrolled in).
    assert(rb.u8cDispRow(rb.dispRows() - 1).isChar(' '));
}

unittest
{
    // Full Terminal: construct with explicit rows/cols/hist (the
    // fontsize-deferred ctor, avoiding any dependency on real font
    // metrics), append plain ASCII text, and confirm cursor position
    // and text() round-trip. Matches this project's usual headless
    // widget-construction testing convention (FlGroup.current(null)).
    import fl.group : FlGroup;

    FlGroup.current(null);
    auto t = new Terminal(0, 0, 400, 300, null, 10, 20, 50);

    assert(t.displayRows() == 10);
    assert(t.displayColumns() == 20);
    assert(t.historyRows() == 50);
    assert(t.cursorRow() == 0 && t.cursorCol() == 0);

    t.append("Hello");
    assert(t.cursorRow() == 0 && t.cursorCol() == 5);
    assert(t.text().canFind("Hello"));

    t.append("\n");
    assert(t.cursorRow() == 1 && t.cursorCol() == 0);

    FlGroup.current(null);
}

unittest
{
    // Clear operations, scrolling into history, and select-all text
    // extraction (Ctrl-A path's underlying select_.select()).
    import fl.group : FlGroup;

    FlGroup.current(null);
    auto t = new Terminal(0, 0, 400, 300, null, 4, 10, 20);

    t.append("one\ntwo\nthree\nfour\n"); // fills all 4 display rows, scrolls
    assert(t.historyUse() > 0); // at least one line pushed into history

    t.clearScreen(false); // clear without scrolling to history
    assert(!t.text().canFind("four"));

    FlGroup.current(null);
}

unittest
{
    // Milestone 2: SGR (ESC[...m) -- xterm color indices, bold/dim/
    // underline/inverse/strikeout attribute bits, and reset.
    import fl.group : FlGroup;

    FlGroup.current(null);
    auto t = new Terminal(0, 0, 400, 300, null, 5, 20, 10);

    t.append("\033[31m"); // fg red (xterm index 1)
    assert(t.textfgcolor() == t.currentStyle().fltkFgColor(1));

    t.append("\033[1m"); // bold
    assert(t.textattrib() & termBold);
    t.append("\033[4m"); // underline
    assert(t.textattrib() & (termBold | termUnderline));

    t.append("\033[0m"); // reset -- clears attrib and restores default colors
    assert(t.textattrib() == termNormal);
    assert(t.textfgcolor() == t.textfgcolorDefault());

    // ESC[7m sets inverse; ESC[27m clears just that bit.
    t.append("\033[7m");
    assert(t.textattrib() & termInverse);
    t.append("\033[27m");
    assert(!(t.textattrib() & termInverse));

    FlGroup.current(null);
}

unittest
{
    // Milestone 2: SGR 24-bit RGB extension (ESC[38;2;r;g;bm / 48;...).
    import fl.group : FlGroup;

    FlGroup.current(null);
    auto t = new Terminal(0, 0, 400, 300, null, 5, 20, 10);

    t.append("\033[38;2;10;20;30m");
    assert(t.textfgcolor() == rgbOf(10, 20, 30));

    t.append("\033[48;2;40;50;60m");
    assert(t.textbgcolor() == rgbOf(40, 50, 60));

    FlGroup.current(null);
}

unittest
{
    // Milestone 2: cursor positioning (CUP/H), clear-in-display (J),
    // clear-in-line (K), and save/restore cursor (s/u).
    import fl.group : FlGroup;

    FlGroup.current(null);
    auto t = new Terminal(0, 0, 400, 300, null, 10, 20, 10);

    t.append("\033[5;3H"); // 1-based row 5, col 3 -> 0-based (4,2)
    assert(t.cursorRow() == 4 && t.cursorCol() == 2);

    t.append("\033[H"); // no args -- home
    assert(t.cursorRow() == 0 && t.cursorCol() == 0);

    t.append("Hello, world!");
    assert(t.cursorCol() == 13);

    t.append("\033[s"); // save cursor position
    t.append("\033[H"); // move away
    assert(t.cursorCol() == 0);
    t.append("\033[u"); // restore
    assert(t.cursorRow() == 0 && t.cursorCol() == 13);

    // ESC[2J's default (no arg) behavior scrolls the display's
    // content into history rather than erasing it outright (matching
    // a real terminal's "clear screen, keep scrollback" semantics --
    // see clearScreen()'s own `scrollToHist` parameter) -- so "Hello"
    // is still reachable via history, but the display itself is blank.
    int histBefore = t.historyUse();
    t.append("\033[2J");
    assert(t.historyUse() > histBefore);
    assert(t.text(true).canFind("Hello")); // preserved, now in scrollback
    assert(t.utf8CharAtDisp(0, 0).isChar(' ')); // display itself is blank

    FlGroup.current(null);
}

unittest
{
    // Milestone 2: reset (ESC c, non-CSI C1 code) and cursor
    // up/down/left/right (A/B/C/D).
    import fl.group : FlGroup;

    FlGroup.current(null);
    auto t = new Terminal(0, 0, 400, 300, null, 10, 20, 10);

    t.append("\033[1m"); // bold
    t.append("\033[10;10H"); // move away from home
    assert(t.textattrib() & termBold);
    assert(t.cursorRow() == 9 && t.cursorCol() == 9);

    t.append("\033c"); // RIS -- full reset
    assert(t.textattrib() == termNormal);
    assert(t.cursorRow() == 0 && t.cursorCol() == 0);

    t.append("\033[3B"); // cursor down 3 (no scroll)
    assert(t.cursorRow() == 3);
    t.append("\033[2A"); // cursor up 2
    assert(t.cursorRow() == 1);
    t.append("\033[5C"); // cursor right 5
    assert(t.cursorCol() == 5);
    t.append("\033[2D"); // cursor left 2
    assert(t.cursorCol() == 3);

    FlGroup.current(null);
}

unittest
{
    // Milestone 2: an unrecognized final character shows the
    // "unknown char" placeholder (when show_unknown() is on) rather
    // than corrupting parser state or crashing.
    import fl.group : FlGroup;

    FlGroup.current(null);
    auto t = new Terminal(0, 0, 400, 300, null, 5, 20, 10);
    t.showUnknown(true);

    t.append("\033[999zX"); // 'z' isn't a recognized CSI final char
    assert(t.text().canFind(t.errorChar()));
    assert(t.text().canFind("X")); // parsing recovers; 'X' still prints normally

    FlGroup.current(null);
}

unittest
{
    // Milestone 2: tabstops -- default every 8th column, plus
    // ESC H (set) / ESC[g (clear) via the C1/CSI forms.
    import fl.group : FlGroup;

    FlGroup.current(null);
    auto t = new Terminal(0, 0, 400, 300, null, 5, 40, 10);

    t.append("\t");
    assert(t.cursorCol() == 8); // first default tabstop

    t.append("\033[3;20H"); // move to column 19 (0-based)
    t.append("\033H"); // set a custom tabstop here (ESC H, non-CSI)
    t.append("\033[3;1H"); // back to column 0, same row
    t.append("\t");
    assert(t.cursorCol() == 8); // still hits the default stop first
    t.append("\t");
    assert(t.cursorCol() == 16);
    t.append("\t");
    assert(t.cursorCol() == 19); // ...then the custom one just set

    FlGroup.current(null);
}

unittest
{
    // handleSelectionAutoscroll(): starts the timer only once the
    // mouse strays above/below the visible screen area, and stops it
    // once back inside -- pure state-transition logic, no need to
    // wait for a real timer tick to verify start/stop.
    import fl.group : FlGroup;

    FlGroup.current(null);
    auto t = new Terminal(0, 0, 400, 300, null, 10, 20, 20);

    assert(t.autoscrollDir_ == 0);

    fl.core.eY_ = t.scrn_.y() + 5; // inside the screen area
    t.handleSelectionAutoscroll();
    assert(t.autoscrollDir_ == 0); // no autoscroll while inside

    fl.core.eY_ = t.scrn_.b() + 20; // below the bottom edge
    t.handleSelectionAutoscroll();
    assert(t.autoscrollDir_ == 4); // "scrolling down"

    fl.core.eY_ = t.scrn_.y() - 20; // above the top edge
    t.handleSelectionAutoscroll();
    assert(t.autoscrollDir_ == 3); // "scrolling up"

    fl.core.eY_ = t.scrn_.y() + 5; // back inside -- stops the timer
    t.handleSelectionAutoscroll();
    assert(t.autoscrollDir_ == 0);

    fl.core.resetForTest();
    FlGroup.current(null);
}

