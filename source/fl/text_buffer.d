/*
 * Ported from FL/Fl_Text_Buffer.H + src/Fl_Text_Buffer.cxx (FLTK 1.5.0). Scope: the data model only (Fl_Text_Selection ->
 * TextSelection, Fl_Text_Buffer -> TextBuffer, and the two undo-support
 * classes defined only in the .cxx, Fl_Text_Undo_Action/
 * Fl_Text_Undo_Action_List -> TextUndoAction/TextUndoActionList, ported
 * as `private` types below). fl.text_display/fl.text_editor (the widgets
 * that *display* a TextBuffer) are explicitly out of scope -- this module
 * has no widget/GUI/drawing dependency at all.
 *
 * `Fl_Text_Selection` becomes a D `struct`, not a `class`: FLTK copies
 * it by value everywhere (`Fl_Text_Selection oldSelection = mPrimary;`
 * before mutating `mPrimary`, to diff old vs. new for
 * `redisplay_selection()`), never allocates it separately, and has no
 * inheritance/virtual dispatch -- a D struct gives the same copy
 * semantics for free, where a class would need a hand-written `dup()`.
 * `TextBuffer.primarySelection()` returns `TextSelection*`/
 * `const(TextSelection)*`, mirroring FLTK's pointer-returning
 * accessors.
 *
 * Deliberate deviations from a byte-for-byte port, each also called out
 * at its point of use:
 *
 * - **Emoji/composed-character clustering is ported**:
 *   `nextChar()`/`prevChar()` step over a whole emoji sequence --
 *   regional-indicator flag pairs, ZWJ-joined sequences, skin-tone
 *   modifiers, keycaps, subdivision-flag tag sequences -- as a single
 *   "character", matching FLTK's `next_char()`/`prev_char()` ->
 *   `fl_utf8_next_composed_char()`/`fl_utf8_previous_composed_char()`
 *   exactly (see `utf8NextComposedCharLen()`/
 *   `utf8PreviousComposedCharIndex()`'s own doc comments for the two
 *   small, deliberate bounds-checking deviations D's memory safety
 *   needs that FLTK's raw pointers don't). This is FLTK's own
 *   curated emoji-sequence heuristic, not a general Unicode
 *   grapheme-cluster algorithm (it doesn't, for example, cluster an
 *   arbitrary base character plus combining diacritics the way a full
 *   UAX #29 implementation would) -- ported faithfully at that same
 *   scope rather than widened, since widening it would be a behavior
 *   change from FLTK, not a bug fix.
 * - **`fl_tolower()`'s hand-rolled Unicode case table is not ported.**
 *   Case-insensitive comparison (`searchForward`/`searchBackward` with
 *   `matchCase == false`) uses `std.uni.toLower()` on the decoded
 *   codepoint instead -- a more complete Unicode case-folding table than
 *   FLTK's own (which FLTK's own doc comment on `fl_tolower()`
 *   admits is "a relatively naive algorithm... limited to 0x0-0xffff").
 * - **`printf()`/`vprintf()` (the `va_list`/C-varargs convenience
 *   wrappers around `append()`) are not ported.** D has no ergonomic
 *   equivalent of a public API that accepts a C `va_list` the way
 *   FLTK's `vprintf(const char*, va_list)` does, and re-purposing D's
 *   own variadic templates would mean accepting D's `std.format` spec
 *   instead of a C `printf` spec -- a real behavior change for the same
 *   method name, not a faithful port. Callers can just write
 *   `buf.append(text.format(args))` (`std.format`) or
 *   `buf.append(text.format!"%d"(n))` directly today.
 * - **File I/O (`insertfile`/`outputfile`) reads/writes the whole file in
 *   one shot** (`std.file.read()` / `std.stdio.File.rawWrite()`) rather
 *   than FLTK's chunked, re-fillable `line[]`/`buffer[]` pair sized
 *   by the `buflen` parameter. Same transcoding behavior (invalid/non-
 *   UTF-8 bytes decode through the same CP1252/ISO-8859-1 fallback table
 *   `fl_utf8decode()` uses, and get re-encoded to real UTF-8, flagging
 *   `inputFileWasTranscoded`), just not streamed -- a memory/perf
 *   difference for very large files, not a correctness one. `buflen` is
 *   still accepted for API-signature fidelity but is otherwise unused.
 * - `text_str()` (FLTK's `std::string`-returning twin of the
 *   malloc'd-`char*`-returning `text()`, added purely because C++ needs
 *   two shapes to give callers a choice) collapses into the single
 *   `text()` below, since it already returns a GC-owned D `string` --
 *   same substitution CONVENTIONS.md documents for `Widget.label()`/
 *   `tooltip()`.
 * - `Fl_Text_Buffer::copy()`'s three `memcpy()` calls become `memmove()`
 *   here. FLTK's own doc comment says `fromBuf` "may be the same as
 *   this", i.e. a self-copy with potentially *overlapping* source/dest
 *   ranges is a documented, intended use -- for which `memcpy()` is
 *   undefined behavior in C. This looks like a genuine latent FLTK
 *   bug; see `FLTK_ISSUES.md`. `memmove()` is a strict, harmless
 *   superset (identical result for the non-overlapping case) so this
 *   isn't a behavior change for any call that wasn't already relying on
 *   UB.
 *
 * No GC-finalizer hazard applies here (see CONVENTIONS.md's note on
 * `Widget.~this()`): `TextBuffer` never reaches into another *live*
 * GC-managed object from a destructor, because it doesn't need a
 * destructor at all -- `buf_`, the undo/redo lists, and the callback
 * arrays are all plain GC arrays, and FLTK's own `~Fl_Text_Buffer()`
 * does nothing but `free()`/`delete` those same pieces, which the D GC
 * already does automatically.
 */
module fl.text_buffer;

import std.algorithm.comparison : min, max;
import std.uni : toLower;
import core.stdc.string : memmove;

// ---------------------------------------------------------------------
// UTF-8 helpers (ported from the subset of src/fl_utf8.cxx that
// Fl_Text_Buffer.cxx actually calls: fl_utf8len()/fl_utf8len1(),
// fl_utf8decode(), fl_utf8encode()). Free functions, not TextBuffer
// methods -- used both against the buffer's raw storage and against
// plain string arguments (search strings, file bytes). Public,
// matching FLTK's own public global `fl_utf8encode()`/etc. --
// `fl.input_` needing this exact same subset is why they exist as free
// functions rather than TextBuffer methods.
// ---------------------------------------------------------------------

/// Codes 0x80..0x9f from the Microsoft CP1252 character set, translated
/// to Unicode -- verbatim port of the table in src/fl_utf8.cxx, used by
/// fl_utf8decode()'s default build flags (ERRORS_TO_CP1252=1).
private immutable ushort[32] cp1252Table = [
    0x20ac, 0x0081, 0x201a, 0x0192, 0x201e, 0x2026, 0x2020, 0x2021,
    0x02c6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008d, 0x017d, 0x008f,
    0x0090, 0x2018, 0x2019, 0x201c, 0x201d, 0x2022, 0x2013, 0x2014,
    0x02dc, 0x2122, 0x0161, 0x203a, 0x0153, 0x009d, 0x017e, 0x0178
];

/// Ported from fl_utf8len(): the byte length of the UTF-8 sequence
/// starting with c, or -1 if c isn't a valid leading byte (a continuation
/// byte, C0/C1, or F5-FF). Examines only c, not the rest of the sequence.
int utf8Len(char c)
{
    ubyte u = cast(ubyte) c;
    if (u <= 0x7f) return 1;
    if (u >= 0xc2 && u <= 0xdf) return 2;
    if (u >= 0xe0 && u <= 0xef) return 3;
    if (u >= 0xf0 && u <= 0xf4) return 4;
    return -1; // continuation byte, C0/C1, F5-FF (incl. obsolete 5/6-byte leaders)
}

/// Ported from fl_utf8len1(): same as utf8Len(), but returns 1 (instead
/// of -1) for an invalid lead byte, so a scan can always advance.
int utf8Len1(char c)
{
    int l = utf8Len(c);
    return l < 0 ? 1 : l;
}

/// Ported from fl_utf8decode(p, end, len), with FLTK's default build
/// flags (ERRORS_TO_ISO8859_1=1, ERRORS_TO_CP1252=1, STRICT_RFC3629=0):
/// an invalid or truncated sequence decodes as a single raw byte (through
/// the CP1252 table for 0x80-0x9f, verbatim otherwise) rather than the
/// Unicode replacement character. `s`/`idx` stand in for FLTK's `p`;
/// `s.length` stands in for FLTK's `end` (TextBuffer always
/// effectively bounds decode by "however much raw storage/search-string
/// is left", the same role `end` plays at every call site in
/// Fl_Text_Buffer.cxx).
uint utf8DecodeAt(const(char)[] s, size_t idx, out int len)
{
    size_t n = s.length;
    ubyte b(size_t i) { return cast(ubyte) s[idx + i]; }
    bool cont(size_t i) { return idx + i < n && (b(i) & 0xc0) == 0x80; }

    ubyte c = b(0);
    if (c < 0x80) { len = 1; return c; }
    if (c < 0xa0) { len = 1; return cp1252Table[c - 0x80]; }
    if (c >= 0xc2 && cont(1))
    {
        if (c < 0xe0)
        {
            len = 2;
            return ((c & 0x1f) << 6) | (b(1) & 0x3f);
        }
        bool okLead3 = !(c == 0xe0 && b(1) < 0xa0); // reject overlong 3-byte
        if (okLead3 && c < 0xf0 && cont(2))
        {
            len = 3;
            return ((c & 0x0f) << 12) | ((b(1) & 0x3f) << 6) | (b(2) & 0x3f);
        }
        bool okLead4 = okLead3
            && !(c == 0xf0 && b(1) < 0x90)  // reject overlong 4-byte
            && !(c == 0xf4 && b(1) > 0x8f); // cap at U+10FFFF
        if (okLead4 && c >= 0xf0 && c < 0xf5 && cont(2) && cont(3))
        {
            len = 4;
            return ((c & 0x07) << 18) | ((b(1) & 0x3f) << 12) | ((b(2) & 0x3f) << 6) | (b(3) & 0x3f);
        }
    }
    len = 1;
    return c;
}

/// Ported from fl_utf8encode(): writes the UTF-8 encoding of ucs into
/// buf (which must have room for at least 4 bytes) and returns the
/// number of bytes written. Values above U+10FFFF (illegal) encode as
/// U+FFFD, matching FLTK.
int utf8Encode(uint ucs, char[] buf)
{
    if (ucs < 0x80) { buf[0] = cast(char) ucs; return 1; }
    if (ucs < 0x800)
    {
        buf[0] = cast(char) (0xc0 | (ucs >> 6));
        buf[1] = cast(char) (0x80 | (ucs & 0x3f));
        return 2;
    }
    if (ucs < 0x10000)
    {
        buf[0] = cast(char) (0xe0 | (ucs >> 12));
        buf[1] = cast(char) (0x80 | ((ucs >> 6) & 0x3f));
        buf[2] = cast(char) (0x80 | (ucs & 0x3f));
        return 3;
    }
    if (ucs <= 0x10ffff)
    {
        buf[0] = cast(char) (0xf0 | (ucs >> 18));
        buf[1] = cast(char) (0x80 | ((ucs >> 12) & 0x3f));
        buf[2] = cast(char) (0x80 | ((ucs >> 6) & 0x3f));
        buf[3] = cast(char) (0x80 | (ucs & 0x3f));
        return 4;
    }
    buf[0] = cast(char) 0xef;
    buf[1] = cast(char) 0xbf;
    buf[2] = cast(char) 0xbd;
    return 3;
}

/// Ported from fl_utf8back(): steps `p` backward to the start of the
/// UTF-8 sequence it falls within, scoped to a local `window` slice
/// (index 0 is the lower bound) instead of FLTK's pointer pair --
/// the same "begin"-bounded backward alignment TextBuffer.utf8Align()
/// already does over the full gap buffer, reused here at window scope.
/// Simplification vs. FLTK's own `fl_utf8back()`: no
/// decoded-length cross-check against the original position -- fine
/// for the well-formed UTF-8 this module always stores (the cross-check
/// exists FLTK purely to characterize *malformed* input).
private size_t utf8BackInWindow(const(char)[] window, size_t p)
{
    while (p > 0 && (cast(ubyte) window[p] & 0xc0) == 0x80)
        p--;
    return p;
}

/**
 * Ported from `fl_utf8_next_composed_char()` (`src/fl_utf8.cxx`):
 * given a short buffer starting exactly on a codepoint boundary,
 * returns the byte length of the first "composed character" there --
 * either one ordinary codepoint, or a whole flag (regional-indicator
 * pair)/subdivision-flag (waving-flag + tag-sequence)/ZWJ-joined/
 * variation-selected/skin-toned/keycap emoji sequence, matching
 * FLTK's own curated heuristic exactly (not a general Unicode
 * grapheme-cluster algorithm -- see this module's own top comment).
 * Backs `TextBuffer.nextChar()`.
 *
 * Deviation from FLTK: each step re-validates the buffer isn't
 * exhausted before decoding (FLTK's raw-pointer `end` bound
 * tolerates reading exactly one byte at `end` since its caller's
 * stack buffer always has a trailing NUL there; a bounds-checked D
 * slice has no such byte to read).
 */
private int utf8NextComposedCharLen(const(char)[] buf)
{
    int skip = utf8Len(buf[0]);
    if (skip == -1) return 1;

    if (skip >= 4)
    {
        int dlen;
        uint u = utf8DecodeAt(buf, 0, dlen);
        if (u >= 0x1F1E6 && u <= 0x1F1FF) // 1st regional indicator: maybe a flag
        {
            if (cast(size_t) skip < buf.length)
            {
                int dlen2;
                uint u2 = utf8DecodeAt(buf, skip, dlen2);
                if (u2 >= 0x1F1E6 && u2 <= 0x1F1FF) // 2nd regional indicator: it's a flag
                    return 2 * skip;
            }
        }
        else if (u == 0x1F3F4) // waving black flag: maybe subdivision flags
        {
            size_t next = skip;
            while (next < buf.length)
            {
                int dlen2;
                uint u2 = utf8DecodeAt(buf, next, dlen2);
                next += utf8Len1(buf[next]);
                if (u2 == 0xE007F) return cast(int) next; // ends with "cancel tag"
                if (!(u2 >= 0xE0020 && u2 <= 0xE007E)) break; // not a "tag component"
            }
        }
    }

    size_t from = skip; // skip 1st codepoint
    while (from < buf.length)
    {
        int dlen;
        uint u = utf8DecodeAt(buf, from, dlen);
        if (u == 0x200D) // zero-width joiner
        {
            from += utf8Len1(buf[from]); // skip joiner
            if (from >= buf.length) break;
            int skip2 = utf8Len(buf[from]);
            if (skip2 < 1) break;
            from += (skip2 < cast(int)(buf.length - from)) ? skip2 : cast(int)(buf.length - from); // skip joined codepoint
        }
        else if (u >= 0xFE00 && u <= 0xFE0F) from += utf8Len1(buf[from]); // variation selector
        else if (u >= 0x1F3FB && u <= 0x1F3FF) from += utf8Len1(buf[from]); // EMOJI MODIFIER FITZPATRICK
        else if (u == 0x20E3) from += utf8Len1(buf[from]); // combining enclosing keycap
        else break;
    }
    return cast(int) from;
}

/**
 * Ported from `fl_utf8_previous_composed_char()`, specialized for this
 * module's one caller (`TextBuffer.prevCharClipped()`): `window` is the
 * captured lookback bytes ending exactly at the position being stepped
 * back from -- matching that call shape exactly (FLTK's own `from`
 * there always points at its stack buffer's trailing NUL, so its
 * `if (*from)` branch never fires for this caller and isn't ported).
 * Returns the index within `window` of the start of the previous
 * composed character.
 *
 * Deviation from FLTK: every decode uses the *whole* window as its
 * upper bound rather than FLTK's tighter, per-call `end`/`keep`
 * pointer -- harmless for the well-formed UTF-8 this module always
 * stores (a valid lead byte's decoded length never overruns its own
 * codepoint regardless of how much further the bound extends; the
 * tighter bound FLTK uses exists to characterize malformed input,
 * which can't occur here).
 */
private size_t utf8PreviousComposedCharIndex(const(char)[] window)
{
    if (window.length == 0) return 0;
    size_t from = utf8BackInWindow(window, window.length - 1);
    int len;
    uint u = utf8DecodeAt(window, from, len);

    if (u >= 0x1F1E6 && u <= 0x1F1FF) // a 1st regional indicator symbol can be a flag
    {
        if (from > 0)
        {
            size_t previous = utf8BackInWindow(window, from - 1);
            int len2;
            uint u2 = utf8DecodeAt(window, previous, len2);
            if (u2 >= 0x1F1E6 && u2 <= 0x1F1FF) // a 2nd regional indicator symbol gives a flag
                return previous;
        }
    }
    else if (u == 0xE007F) // ends with "cancel tag"
    {
        size_t previous = from;
        while (true)
        {
            if (previous == 0) return 0;
            previous = utf8BackInWindow(window, previous - 1);
            u = utf8DecodeAt(window, previous, len);
            if (u == 0x1F3F4) return previous; // "waving black flag" starts subdivision flags
            if (!(u >= 0xE0020 && u <= 0xE007E)) break; // any series of "tag components"
        }
    }

    while (from > 0)
    {
        u = utf8DecodeAt(window, from, len);
        if (u >= 0xFE00 && u <= 0xFE0F) // a variation selector
            from = utf8BackInWindow(window, from - 1);
        else if (u >= 0x1F3FB && u <= 0x1F3FF) // EMOJI MODIFIER FITZPATRICK
            from = utf8BackInWindow(window, from - 1);
        else if (u == 0x20E3) // combining enclosing keycap
            from = utf8BackInWindow(window, from - 1);
        else
        {
            size_t prevStart = utf8BackInWindow(window, from - 1);
            int lenPrev;
            uint uPrev = utf8DecodeAt(window, prevStart, lenPrev);
            if (uPrev == 0x200D) // zero-width joiner
            {
                from = prevStart == 0 ? 0 : utf8BackInWindow(window, prevStart - 1);
                continue;
            }
            return from;
        }
    }
    return from;
}

// ---------------------------------------------------------------------
// Fl_Text_Selection -> TextSelection
// ---------------------------------------------------------------------

/**
 * Ported from Fl_Text_Selection (declared in the header, implemented
 * across Fl_Text_Buffer.cxx). A D `struct`, not a `class` -- see the
 * module comment for why. All offsets are *byte* offsets into the owning
 * TextBuffer, on UTF-8 character boundaries by caller contract (nothing
 * here enforces that -- same as FLTK).
 *
 * FLTK 1.4+ behavior (preserved here, see the dedicated unittest below):
 * when `selected()` is false, `start()`/`end()` always read back as 0,
 * even though the underlying `start_`/`end_` fields are left untouched
 * by `selected(false)` -- FLTK's own header doc comment flags this
 * as a behavior *change* from 1.3.x, where a stale non-zero start()/end()
 * could leak through after deselecting.
 */
struct TextSelection
{
    private
    {
        int start_;
        int end_;
        bool selected_;
    }

    /// Sets the selection range; selected() becomes true iff startpos !=
    /// endpos. Swaps the two first if given out of order.
    void set(int startpos, int endpos)
    {
        selected_ = (startpos != endpos);
        start_ = min(startpos, endpos);
        end_ = max(startpos, endpos);
    }

    /// Adjusts this selection for a buffer edit at pos (nDeleted bytes
    /// removed, nInserted bytes inserted there), exactly mirroring
    /// Fl_Text_Selection::update().
    void update(int pos, int nDeleted, int nInserted)
    {
        if (!selected_ || pos > end_) return;
        if (pos + nDeleted <= start_)
        {
            start_ += nInserted - nDeleted;
            end_ += nInserted - nDeleted;
        }
        else if (pos <= start_ && pos + nDeleted >= end_)
        {
            start_ = pos;
            end_ = pos;
            selected_ = false;
        }
        else if (pos <= start_ && pos + nDeleted < end_)
        {
            start_ = pos;
            end_ = nInserted + end_ - nDeleted;
        }
        else if (pos < end_)
        {
            end_ += nInserted - nDeleted;
            if (end_ <= start_) selected_ = false;
        }
    }

    /// Byte offset to the first selected character, or 0 if not selected
    /// (FLTK 1.4+ behavior -- see the struct doc comment).
    int start() const { return selected_ ? start_ : 0; }
    /// Byte offset just past the last selected character, or 0 if not
    /// selected (FLTK 1.4+ behavior).
    int end() const { return selected_ ? end_ : 0; }
    bool selected() const { return selected_; }
    void selected(bool b) { selected_ = b; }
    /// Size in bytes of the selection, or 0 if not selected.
    int length() const { return selected_ ? end_ - start_ : 0; }

    /// True if pos falls within [start(), end()).
    bool includes(int pos) const { return selected() && pos >= start() && pos < end(); }

    /// Returns selected(), and (via out params) start()/end() -- both 0
    /// if not selected. FLTK returns int (0/1) through the same
    /// method name (`selected(int*, int*)`); D's bool return + out
    /// params is the natural fit (see CONVENTIONS.md's preference for real
    /// types over C's int-as-bool).
    bool selected(out int startpos, out int endpos) const
    {
        if (!selected_) { startpos = 0; endpos = 0; return false; }
        startpos = start_;
        endpos = end_;
        return true;
    }
}

// ---------------------------------------------------------------------
// Modify / predelete callbacks
// ---------------------------------------------------------------------

/**
 * Called after the buffer is modified (insert/delete/replace, or a
 * selection boundary redisplay -- see redisplaySelection()'s callers).
 * Matches Fl_Text_Modify_Cb's parameter order verbatim, minus the `void*
 * cbArg` slot: per CONVENTIONS.md's delegate-over-function-pointer
 * convention, callers just capture whatever context they need instead.
 */
alias TextModifyCb = void delegate(int pos, int nInserted, int nDeleted, int nRestyled, const(char)[] deletedText);

/// Called just before text is deleted from the buffer. Matches
/// Fl_Text_Predelete_Cb minus the `void* cbArg` slot, same as above.
alias TextPredeleteCb = void delegate(int pos, int nDeleted);

// ---------------------------------------------------------------------
// Fl_Text_Undo_Action / Fl_Text_Undo_Action_List -- internal to
// Fl_Text_Buffer.cxx FLTK (not declared in the header at all), so
// private here too.
// ---------------------------------------------------------------------

/**
 * Ported from Fl_Text_Undo_Action (defined only in Fl_Text_Buffer.cxx).
 * A single pending undo action. Deleting text stores the number of bytes
 * deleted in `undocut` and the deleted bytes themselves in `undobuffer`;
 * `undoat` is the position. Inserting text stores the number of bytes
 * inserted in `undoinsert`, with `undoat` pointing just after the
 * inserted run. Deleting then inserting at the same position (a "yank
 * cut") stores the deleted byte count in `undoyankcut` as well as
 * `undobuffer`. There's no separate action-*type* enum FLTK --
 * which of insert/delete/yankcut an action represents is inferred from
 * which of undocut/undoinsert/undoyankcut are nonzero (see applyUndo()),
 * so none is invented here either.
 */
private final class TextUndoAction
{
    char[] undobuffer;
    int undoat;      /// points after insertion
    int undocut;     /// number of bytes deleted there
    int undoinsert;  /// number of bytes inserted
    int undoyankcut; /// length of valid contents of undobuffer, even if undocut == 0

    /// Grows undobuffer to hold at least n bytes. Unlike FLTK's
    /// manual realloc()-with-headroom, D's dynamic array handles the
    /// "keep existing content" part for free; the "+128" headroom is
    /// kept anyway, purely to match FLTK's amortized-growth shape.
    void undobuffersize(int n)
    {
        if (n > cast(int) undobuffer.length) undobuffer.length = n + 128;
    }

    void clear() { undocut = 0; undoinsert = 0; }
    bool empty() const { return undocut == 0 && undoinsert == 0; }
}

/**
 * Ported from Fl_Text_Undo_Action_List (also defined only in
 * Fl_Text_Buffer.cxx). A lockable LIFO undo/redo stack: locking protects
 * it from being cleared while an undo/redo action is being replayed (see
 * TextBuffer.applyUndo()).
 */
private final class TextUndoActionList
{
    private
    {
        TextUndoAction[] list_;
        bool locked_;
    }

    int size() const { return cast(int) list_.length; }

    void push(TextUndoAction action) { list_ ~= action; }

    TextUndoAction pop()
    {
        if (list_.length == 0) return null;
        auto a = list_[$ - 1];
        list_ = list_[0 .. $ - 1];
        return a;
    }

    void clear()
    {
        if (locked_) return;
        list_ = [];
    }

    void lock() { locked_ = true; }
    void unlock() { locked_ = false; }
}

// ---------------------------------------------------------------------
// Fl_Text_Buffer -> TextBuffer
// ---------------------------------------------------------------------

/**
 * Ported from Fl_Text_Buffer. A gap-buffer text store: `buf_` is one
 * contiguous allocation with a movable empty region [`gapStart_`,
 * `gapEnd_`) that absorbs cheap sequential insertion; `rawIndex(pos)`
 * (FLTK's `address(pos)`, minus the pointer) computes `pos <
 * gapStart_ ? pos : pos + gapEnd_ - gapStart_`. All positions are *byte*
 * offsets that callers must keep UTF-8-character-aligned -- nothing here
 * enforces that beyond `utf8Align()`. See the module comment for the
 * handful of deliberate deviations from a byte-for-byte port.
 */
class TextBuffer
{
    private
    {
        TextSelection primary_;
        TextSelection secondary_;
        TextSelection highlight_;
        int length_;
        char[] buf_;
        int gapStart_;
        int gapEnd_;
        int tabDist_;
        TextModifyCb[] modifyProcs_;
        TextPredeleteCb[] predeleteProcs_;
        int cursorPosHint_;
        bool canUndo_;
        int preferredGapSize_;
        TextUndoAction undo_;
        TextUndoActionList undoList_;
        TextUndoActionList redoList_;
    }

    /// True if the most recent insertfile()/loadfile() had to transcode
    /// non-UTF-8 input (e.g. CP1252) on the way in.
    bool inputFileWasTranscoded;

    /// Shown (by convention) when a loaded file wasn't UTF-8 encoded.
    /// FLTK's `static const char* file_encoding_warning_message`.
    static string fileEncodingWarningMessage =
        "Displayed text contains the UTF-8 transcoding\n" ~
        "of the input file which was not UTF-8 encoded.\n" ~
        "Some changes may have occurred.";

    /// Called after insertfile()/loadfile() transcodes non-UTF-8 input.
    /// FLTK's default implementation calls alert() with
    /// fileEncodingWarningMessage. alert() lives in fl.ask, which
    /// depends on widgets, and this module has no GUI dependency, so
    /// this defaults to null. FLTK's own contract already covers
    /// that: "No warning message is displayed if this pointer is set
    /// to NULL."
    void delegate(TextBuffer) transcodingWarningAction;

    /// Creates an empty text buffer. requestedSize preallocates room to
    /// avoid early reallocation if the caller knows roughly how big the
    /// text will get; preferredGapSize is the gap's initial (and,
    /// per-reallocation, target) size.
    this(int requestedSize = 0, int preferredGapSize = 1024)
    {
        length_ = 0;
        preferredGapSize_ = preferredGapSize;
        buf_ = new char[requestedSize + preferredGapSize];
        gapStart_ = 0;
        gapEnd_ = requestedSize + preferredGapSize;
        tabDist_ = 8;
        cursorPosHint_ = 0;
        canUndo_ = true;
        undo_ = new TextUndoAction();
        undoList_ = new TextUndoActionList();
        redoList_ = new TextUndoActionList();
        inputFileWasTranscoded = false;
        transcodingWarningAction = null;
    }

    // No destructor: see the module comment on why none is needed.

    /// Number of bytes in the buffer.
    int length() const { return length_; }

    /// Returns a copy of the entire buffer contents.
    string text() const
    {
        if (length_ == 0) return "";
        auto t = new char[length_];
        t[0 .. gapStart_] = buf_[0 .. gapStart_];
        t[gapStart_ .. length_] = buf_[gapEnd_ .. gapEnd_ + (length_ - gapStart_)];
        return cast(string) t;
    }

    /// Replaces the entire buffer contents with t, firing predelete/
    /// modify callbacks and clearing undo/redo history (matching
    /// FLTK). Also resets any selections, since their positions no
    /// longer refer to anything meaningful.
    void text(const(char)[] t)
    {
        callPredeleteCallbacks(0, length_);
        string deletedText = text();
        int deletedLength = length_;

        int insertedLength = cast(int) t.length;
        buf_ = new char[insertedLength + preferredGapSize_];
        length_ = insertedLength;
        gapStart_ = insertedLength;
        gapEnd_ = gapStart_ + preferredGapSize_;
        buf_[0 .. insertedLength] = t[];

        updateSelections(0, deletedLength, 0);
        callModifyCallbacks(0, deletedLength, insertedLength, 0, deletedText);

        if (canUndo_)
        {
            undo_.clear();
            undoList_.clear();
            redoList_.clear();
        }
    }

    /// Returns a copy of the text between byte offsets start and end
    /// (end exclusive). Clamped/swapped the same way FLTK is; see
    /// FLTK_ISSUES.md for one input shape (end < 0) this inherits
    /// from FLTK without also inheriting its C out-of-bounds-read
    /// consequence -- D's bounds-checked slicing turns that into a
    /// well-defined RangeError instead.
    string textRange(int start, int end) const
    {
        if (start < 0 || start > length_) return "";
        if (end < start)
        {
            auto tmp = start;
            start = end;
            end = tmp;
        }
        if (end > length_) end = length_;
        int copiedLength = end - start;
        auto s = new char[copiedLength];
        if (end <= gapStart_)
            s[0 .. copiedLength] = buf_[start .. start + copiedLength];
        else if (start >= gapStart_)
            s[0 .. copiedLength] = buf_[start + (gapEnd_ - gapStart_) .. start + (gapEnd_ - gapStart_) + copiedLength];
        else
        {
            int part1Length = gapStart_ - start;
            s[0 .. part1Length] = buf_[start .. gapStart_];
            s[part1Length .. copiedLength] = buf_[gapEnd_ .. gapEnd_ + (copiedLength - part1Length)];
        }
        return cast(string) s;
    }

    /// The UCS-4 codepoint at pos (which must be on a UTF-8 character
    /// boundary), or 0 if pos is out of range.
    uint charAt(int pos) const
    {
        if (pos < 0 || pos >= length_) return 0;
        int len;
        return utf8DecodeAt(buf_, rawIndex(pos), len);
    }

    /// The raw byte at pos, ignoring UTF-8 encoding entirely, or 0 if
    /// pos is out of range.
    char byteAt(int pos) const
    {
        if (pos < 0 || pos >= length_) return '\0';
        return buf_[rawIndex(pos)];
    }

    /// Converts a byte offset into a raw pointer into the gap-buffer
    /// storage. Like FLTK, the pointer is only meaningful up to the
    /// next gap boundary/buffer mutation -- callers reading multiple
    /// bytes forward from it are responsible for not crossing mGapStart,
    /// same contract as FLTK's own address().
    const(char)* address(int pos) const { return buf_.ptr + rawIndex(pos); }
    /// ditto
    char* address(int pos) { return buf_.ptr + rawIndex(pos); } // @suppress(dscanner.style.doc_missing_returns)

    private int rawIndex(int pos) const { return pos < gapStart_ ? pos : pos + gapEnd_ - gapStart_; }

    /// Inserts text at pos (which must be on a UTF-8 character
    /// boundary), clamping pos into range first. insertedLength defaults
    /// to text.length; pass fewer bytes to insert only a prefix of text.
    void insert(int pos, const(char)[] text, int insertedLength = -1)
    {
        if (text.length == 0) return;
        if (pos > length_) pos = length_;
        if (pos < 0) pos = 0;

        callPredeleteCallbacks(pos, 0);
        int nInserted = insert_(pos, text, insertedLength);
        cursorPosHint_ = pos + nInserted;
        callModifyCallbacks(pos, 0, nInserted, 0, null);
    }

    /// Appends text to the end of the buffer.
    void append(const(char)[] text, int addedLength = -1) { insert(length_, text, addedLength); }

    /// Formats text and appends it to the end of the buffer. Ported
    /// from `Fl_Text_Buffer::printf()`/`vprintf()` (`src/Fl_Text_
    /// Buffer.cxx`) -- FLTK uses a fixed 1024-byte `vsnprintf()`
    /// buffer (truncating longer output); this port uses `std.format`
    /// instead, so it has no such cap, matching the same substitution
    /// `fl.terminal.Terminal.printf()` already made (see that module's
    /// own comment).
    void printf(Args...)(string fmt, Args args)
    {
        import std.format : format;

        append(format(fmt, args));
    }

    /// Deletes the byte range [start, end), inserting text in its place.
    void replace(int start, int end, const(char)[] text, int insertedLength = -1)
    {
        if (start < 0) start = 0;
        if (end > length_) end = length_;

        callPredeleteCallbacks(start, end - start);
        string deletedText = textRange(start, end);
        remove_(start, end);
        int nInserted = insert_(start, text, insertedLength);
        cursorPosHint_ = start + nInserted;
        callModifyCallbacks(start, end - start, nInserted, 0, deletedText);
    }

    /// Deletes the byte range [start, end), swapping/clamping out-of-
    /// order or out-of-range arguments first.
    void remove(int start, int end)
    {
        if (start > end)
        {
            auto tmp = start;
            start = end;
            end = tmp;
        }
        if (start > length_) start = length_;
        if (start < 0) start = 0;
        if (end > length_) end = length_;
        if (end < 0) end = 0;
        if (start == end) return;

        callPredeleteCallbacks(start, end - start);
        string deletedText = textRange(start, end);
        remove_(start, end);
        cursorPosHint_ = start;
        callModifyCallbacks(start, end - start, 0, 0, deletedText);
    }

    /// Copies text from another TextBuffer (which may be this one) into
    /// this buffer at toPos. See the module comment on why this uses
    /// memmove() rather than FLTK's memcpy() for the actual byte
    /// transfer.
    void copy(TextBuffer fromBuf, int fromStart, int fromEnd, int toPos)
    {
        int copiedLength = fromEnd - fromStart;
        if (copiedLength > gapEnd_ - gapStart_)
            reallocateWithGap(toPos, copiedLength + preferredGapSize_);
        else if (toPos != gapStart_)
            moveGap(toPos);

        if (fromEnd <= fromBuf.gapStart_)
        {
            memmove(buf_.ptr + toPos, fromBuf.buf_.ptr + fromStart, copiedLength);
        }
        else if (fromStart >= fromBuf.gapStart_)
        {
            memmove(buf_.ptr + toPos,
                    fromBuf.buf_.ptr + fromStart + (fromBuf.gapEnd_ - fromBuf.gapStart_), copiedLength);
        }
        else
        {
            int part1Length = fromBuf.gapStart_ - fromStart;
            memmove(buf_.ptr + toPos, fromBuf.buf_.ptr + fromStart, part1Length);
            memmove(buf_.ptr + toPos + part1Length, fromBuf.buf_.ptr + fromBuf.gapEnd_,
                    copiedLength - part1Length);
        }

        gapStart_ += copiedLength;
        length_ += copiedLength;
        updateSelections(toPos, 0, copiedLength);
    }

    // -- Undo / redo --------------------------------------------------

    /// Applies action (the pending action, or a popped redo/undo
    /// action), generating the matching inverse action in undo_ as a
    /// side effect -- see the class doc comment on TextUndoAction.
    protected int applyUndo(TextUndoAction action, int* cursorPos)
    {
        if (action.empty()) return 0;

        redoList_.lock();

        int ilen = action.undocut;
        int xlen = action.undoinsert;
        int b = action.undoat - xlen;

        if (xlen && action.undoyankcut && !ilen) ilen = action.undoyankcut;

        if (xlen && ilen)
        {
            replace(b, action.undoat, action.undobuffer[0 .. ilen]);
            if (cursorPos) *cursorPos = cursorPosHint_;
        }
        else if (xlen)
        {
            remove(b, action.undoat);
            if (cursorPos) *cursorPos = cursorPosHint_;
        }
        else if (ilen)
        {
            insert(action.undoat, action.undobuffer[0 .. ilen]);
            if (cursorPos) *cursorPos = cursorPosHint_;
            action.undoyankcut = 0;
        }

        redoList_.unlock();
        return 1;
    }

    /// Undoes the most recent change, returning the previous cursor
    /// position through cursorPos if non-null. Returns nonzero if an
    /// undo was actually applied.
    int undo(int* cursorPos = null)
    {
        if (!canUndo_ || undo_.empty()) return 0;

        // Save the pending undo action and install an empty placeholder
        // to avoid generating a spurious yankcut while replaying it.
        auto action = undo_;
        undo_ = new TextUndoAction();

        int ret = applyUndo(action, cursorPos);

        if (ret)
        {
            // applyUndo() generated the matching redo action in undo_
            // (and, in the process, may have pushed the still-empty
            // placeholder onto undoList_ -- see insert_()'s bookkeeping).
            redoList_.push(undo_);
            undo_ = undoList_.pop();
            if (undo_ !is null)
            {
                // That was the empty placeholder; discard it and pop the
                // real previous undo action from underneath it.
                undo_ = undoList_.pop();
                if (undo_ is null) undo_ = new TextUndoAction();
            }
        }

        return ret;
    }

    /// True if undo is enabled and there's a pending action to undo.
    bool canUndo() const { return canUndo_ && undo_ !is null && !undo_.empty(); }

    /// Enables or disables undo tracking for this buffer. Disabling
    /// drops the current pending action; re-enabling starts fresh (no
    /// history is retained across a disable/enable cycle, matching
    /// FLTK). Unlike FLTK's `canUndo(char flag=1)`, flag has no
    /// default here: a default would make `canUndo()` ambiguous with
    /// the 0-arg getter of the same name above (D overloads by
    /// signature, and both would become callable with zero arguments).
    void canUndo(bool flag)
    {
        if (flag)
        {
            if (!canUndo_) undo_ = new TextUndoAction();
        }
        else
        {
            if (canUndo_) undo_ = null;
        }
        canUndo_ = flag;
    }

    /// Redoes the most recently undone action, returning the resulting
    /// cursor position through cursorPos if non-null. Returns nonzero if
    /// a redo was actually applied.
    int redo(int* cursorPos = null)
    {
        if (!canUndo_) return 0;
        auto redoAction = redoList_.pop();
        if (redoAction is null) return 0;
        return applyUndo(redoAction, cursorPos);
    }

    /// True if undo is enabled and there's a pending action to redo.
    bool canRedo() const { return canUndo_ && redoList_.size() > 0; }

    // -- Tab distance ---------------------------------------------------

    /// The tab width, in characters (an average-character-width multiple
    /// is used to turn this into pixels; see the header's own comment on
    /// why "columns" can't be a fixed pixel width once fonts are
    /// proportional).
    int tabDistance() const { return tabDist_; }

    /// Sets the tab width, firing predelete/modify callbacks over the
    /// whole buffer to force a full redisplay (tabs are a purely visual
    /// hint -- no text actually changes -- but FLTK keeps this for
    /// back-compat, so this port does too).
    void tabDistance(int tabDist)
    {
        callPredeleteCallbacks(0, length_);
        tabDist_ = tabDist;
        string deletedText = text();
        callModifyCallbacks(0, length_, length_, 0, deletedText);
    }

    // -- Selections -----------------------------------------------------

    /// Selects [start, end) as the primary selection.
    void select(int start, int end)
    {
        auto oldSelection = primary_;
        primary_.set(start, end);
        redisplaySelection(oldSelection, primary_);
    }

    /// True if any text is primary-selected.
    bool selected() const { return primary_.selected(); }

    /// Clears the primary selection.
    void unselect()
    {
        auto oldSelection = primary_;
        primary_.selected_ = false;
        redisplaySelection(oldSelection, primary_);
    }

    /// Gets the primary selection's range; returns false (with both out
    /// params set to 0) if nothing is selected.
    bool selectionPosition(out int start, out int end) const { return primary_.selected(start, end); }

    /// Returns the primary-selected text, or "" if nothing is selected.
    string selectionText() const { return selectionText_(primary_); }

    /// Removes the primary-selected text from the buffer.
    void removeSelection() { removeSelection_(primary_); }

    /// Replaces the primary-selected text, then clears the selection
    /// (its range no longer refers to anything meaningful).
    void replaceSelection(const(char)[] text) { replaceSelection_(primary_, text); }

    /// Selects [start, end) as the secondary selection.
    void secondarySelect(int start, int end)
    {
        auto oldSelection = secondary_;
        secondary_.set(start, end);
        redisplaySelection(oldSelection, secondary_);
    }

    /// True if any text is secondary-selected.
    bool secondarySelected() const { return secondary_.selected(); }

    /// Clears the secondary selection.
    void secondaryUnselect()
    {
        auto oldSelection = secondary_;
        secondary_.selected_ = false;
        redisplaySelection(oldSelection, secondary_);
    }

    /// Gets the secondary selection's range; see selectionPosition().
    bool secondarySelectionPosition(out int start, out int end) const { return secondary_.selected(start, end); }

    /// Returns the secondary-selected text, or "" if none.
    string secondarySelectionText() const { return selectionText_(secondary_); }

    /// Removes the secondary-selected text from the buffer.
    void removeSecondarySelection() { removeSelection_(secondary_); }

    /// Replaces the secondary-selected text, then clears the selection.
    void replaceSecondarySelection(const(char)[] text) { replaceSelection_(secondary_, text); }

    /// Highlights [start, end).
    void highlight(int start, int end)
    {
        auto oldSelection = highlight_;
        highlight_.set(start, end);
        redisplaySelection(oldSelection, highlight_);
    }

    /// True if any text is highlighted.
    bool highlight() const { return highlight_.selected(); }

    /// Clears the highlight.
    void unhighlight()
    {
        auto oldSelection = highlight_;
        highlight_.selected_ = false;
        redisplaySelection(oldSelection, highlight_);
    }

    /// Gets the highlight's range; see selectionPosition().
    bool highlightPosition(out int start, out int end) const { return highlight_.selected(start, end); }

    /// Returns the highlighted text, or "" if none.
    string highlightText() const { return selectionText_(highlight_); }

    /// The primary selection, mutable.
    TextSelection* primarySelection() { return &primary_; }
    /// ditto, read-only.
    const(TextSelection)* primarySelection() const { return &primary_; }
    /// The secondary selection, read-only (FLTK exposes no mutable
    /// accessor for this one either).
    const(TextSelection)* secondarySelection() const { return &secondary_; }
    /// The highlight selection, read-only.
    const(TextSelection)* highlightSelection() const { return &highlight_; }

    // -- Callbacks --------------------------------------------------------

    /// Registers cb to be called on every buffer modification, most-
    /// recently-added first (matching FLTK's ordering).
    void addModifyCallback(TextModifyCb cb) { modifyProcs_ = cb ~ modifyProcs_; }

    /// Unregisters cb (the first match, by delegate equality -- context
    /// pointer and all, standing in for FLTK's `(fn, void*)` pair
    /// match). Writes a diagnostic to stderr if not found, matching
    /// FLTK's Fl::error() call (which this port doesn't have a
    /// wired-up equivalent of yet -- see fl.core's row in PORTING.md).
    void removeModifyCallback(TextModifyCb cb)
    {
        foreach (i, existing; modifyProcs_)
        {
            if (existing == cb)
            {
                modifyProcs_ = modifyProcs_[0 .. i] ~ modifyProcs_[i + 1 .. $];
                return;
            }
        }
        diagnostic("TextBuffer.removeModifyCallback(): can't find modify callback to remove");
    }

    /// Calls every registered modify callback with (pos, nInserted,
    /// nDeleted, nRestyled, deletedText).
    protected void callModifyCallbacks(int pos, int nDeleted, int nInserted, int nRestyled,
                                        const(char)[] deletedText) const
    {
        foreach (cb; modifyProcs_) cb(pos, nInserted, nDeleted, nRestyled, deletedText);
    }

    /// Calls every registered modify callback with all-zero/null
    /// arguments (a generic "something changed, redisplay everything"
    /// notification).
    void callModifyCallbacks() const { callModifyCallbacks(0, 0, 0, 0, null); }

    /// Registers cb to be called just before text is deleted, most-
    /// recently-added first.
    void addPredeleteCallback(TextPredeleteCb cb) { predeleteProcs_ = cb ~ predeleteProcs_; }

    /// Unregisters cb; see removeModifyCallback()'s doc comment.
    void removePredeleteCallback(TextPredeleteCb cb)
    {
        foreach (i, existing; predeleteProcs_)
        {
            if (existing == cb)
            {
                predeleteProcs_ = predeleteProcs_[0 .. i] ~ predeleteProcs_[i + 1 .. $];
                return;
            }
        }
        diagnostic("TextBuffer.removePredeleteCallback(): can't find pre-delete callback to remove");
    }

    /// Calls every registered predelete callback with (pos, nDeleted).
    protected void callPredeleteCallbacks(int pos, int nDeleted) const
    {
        foreach (cb; predeleteProcs_) cb(pos, nDeleted);
    }

    /// Calls every registered predelete callback with (0, 0).
    void callPredeleteCallbacks() const { callPredeleteCallbacks(0, 0); }

    // -- Line / word navigation ------------------------------------------

    /// Returns the entire line containing pos.
    string lineText(int pos) const { return textRange(lineStart(pos), lineEnd(pos)); }

    /// Returns the byte offset of the start of the line containing pos.
    int lineStart(int pos) const
    {
        int foundPos;
        if (!findcharBackward(pos, '\n', foundPos)) return 0;
        return foundPos + 1;
    }

    /// Returns the byte offset just past the end of the line containing
    /// pos (the position of the newline, or length() if pos's line is
    /// the last, unterminated one).
    int lineEnd(int pos) const
    {
        int foundPos;
        if (!findcharForward(pos, '\n', foundPos)) foundPos = length_;
        return foundPos;
    }

    /// True if the character at pos is a word separator: any non-
    /// alphanumeric, non-'_' ASCII character, NO-BREAK SPACE (U+00A0),
    /// or an IDEOGRAPHIC punctuation mark (U+3000-U+301F).
    bool isWordSeparator(int pos) const
    {
        import std.ascii : isAlphaNum;

        uint c = charAt(pos);
        if (c < 128) return !(isAlphaNum(cast(char) c) || c == '_');
        return c == 0xA0 || (c >= 0x3000 && c <= 0x301F);
    }

    /// Returns the byte offset of the start of the word containing pos.
    int wordStart(int pos) const
    {
        while (pos > 0 && !isWordSeparator(pos)) pos = prevChar(pos);
        if (isWordSeparator(pos)) pos = nextChar(pos);
        return pos;
    }

    /// Returns the byte offset just past the end of the word containing
    /// pos.
    int wordEnd(int pos) const
    {
        while (pos < length_ && !isWordSeparator(pos)) pos = nextChar(pos);
        return pos;
    }

    /// Counts displayed characters (tabs/control characters expanded --
    /// but see the module comment: this port doesn't do that expansion,
    /// so this currently just counts codepoints) between lineStartPos
    /// and targetPos.
    int countDisplayedCharacters(int lineStartPos, int targetPos) const
    {
        int charCount = 0;
        int pos = lineStartPos;
        while (pos < targetPos)
        {
            pos = nextChar(pos);
            charCount++;
        }
        return charCount;
    }

    /// Advances nChars displayed characters forward from lineStartPos,
    /// stopping early at a newline. See countDisplayedCharacters()'s note
    /// on tab/control-character expansion not being ported.
    int skipDisplayedCharacters(int lineStartPos, int nChars)
    {
        int pos = lineStartPos;
        for (int charCount = 0; charCount < nChars && pos < length_; charCount++)
        {
            if (charAt(pos) == '\n') return pos;
            pos = nextChar(pos);
        }
        return pos;
    }

    /// Counts the newlines between startPos and endPos (endPos itself
    /// not counted). Scans the raw gap-buffer storage directly rather
    /// than going through byteAt()/nextChar(), same optimization
    /// FLTK makes.
    int countLines(int startPos, int endPos) const
    {
        int gapLen = gapEnd_ - gapStart_;
        int lineCount = 0;
        int pos = startPos;
        while (pos < gapStart_)
        {
            if (pos == endPos) return lineCount;
            if (buf_[pos++] == '\n') lineCount++;
        }
        while (pos < length_)
        {
            if (pos == endPos) return lineCount;
            if (buf_[pos++ + gapLen] == '\n') lineCount++;
        }
        return lineCount;
    }

    /// Estimates the number of newlines between startPos and endPos,
    /// additionally counting a soft break every lineLen characters
    /// within a line (to account for line wrapping).
    int estimateLines(int startPos, int endPos, int lineLen) const
    {
        int gapLen = gapEnd_ - gapStart_;
        int lineCount = 0;
        int softLineBreaks = 0;
        int softLineBreakCount = lineLen;
        int pos = startPos;
        while (pos < gapStart_)
        {
            if (pos == endPos) return lineCount + softLineBreaks;
            if (buf_[pos++] == '\n') { softLineBreakCount = lineLen; lineCount++; }
            if (--softLineBreakCount == 0) { softLineBreakCount = lineLen; softLineBreaks++; }
        }
        while (pos < length_)
        {
            if (pos == endPos) return lineCount + softLineBreaks;
            if (buf_[pos++ + gapLen] == '\n') { softLineBreakCount = lineLen; lineCount++; }
            if (--softLineBreakCount == 0) { softLineBreakCount = lineLen; softLineBreaks++; }
        }
        return lineCount + softLineBreaks;
    }

    /// Returns the byte offset of the first character of the line nLines
    /// forward from startPos.
    int skipLines(int startPos, int nLines)
    {
        if (nLines == 0) return startPos;
        int gapLen = gapEnd_ - gapStart_;
        int pos = startPos;
        int lineCount = 0;
        while (pos < gapStart_)
        {
            if (buf_[pos++] == '\n')
            {
                lineCount++;
                if (lineCount == nLines) return pos;
            }
        }
        while (pos < length_)
        {
            if (buf_[pos++ + gapLen] == '\n')
            {
                lineCount++;
                if (lineCount >= nLines) return pos;
            }
        }
        return pos;
    }

    /// Returns the byte offset of the first character of the line nLines
    /// backward from startPos (not counting a newline exactly at
    /// startPos). nLines == 0 means "the start of startPos's own line".
    int rewindLines(int startPos, int nLines)
    {
        int pos = startPos - 1;
        if (pos <= 0) return 0;
        int gapLen = gapEnd_ - gapStart_;
        int lineCount = -1;
        while (pos >= gapStart_)
        {
            if (buf_[pos + gapLen] == '\n')
                if (++lineCount >= nLines) return pos + 1;
            pos--;
        }
        while (pos >= 0)
        {
            if (buf_[pos] == '\n')
                if (++lineCount >= nLines) return pos + 1;
            pos--;
        }
        return 0;
    }

    // -- Character / string search ----------------------------------------

    /// Searches forward from startPos for searchChar (a UCS-4
    /// codepoint); returns true and sets foundPos if found, else returns
    /// false and sets foundPos to length().
    bool findcharForward(int startPos, uint searchChar, out int foundPos) const
    {
        if (startPos >= length_) { foundPos = length_; return false; }
        if (startPos < 0) startPos = 0;
        for (; startPos < length_; startPos = nextChar(startPos))
        {
            if (searchChar == charAt(startPos)) { foundPos = startPos; return true; }
        }
        foundPos = length_;
        return false;
    }

    /// Searches backward from just before startPos for searchChar;
    /// returns true and sets foundPos if found, else returns false and
    /// sets foundPos to 0.
    bool findcharBackward(int startPos, uint searchChar, out int foundPos) const
    {
        if (startPos <= 0) { foundPos = 0; return false; }
        if (startPos > length_) startPos = length_;
        for (startPos = prevChar(startPos); startPos >= 0; startPos = prevChar(startPos))
        {
            if (searchChar == charAt(startPos)) { foundPos = startPos; return true; }
        }
        foundPos = 0;
        return false;
    }

    /// Searches forward from startPos for searchString; returns true and
    /// sets foundPos to the match start if found. matchCase selects
    /// exact vs. case-insensitive comparison -- see the module comment
    /// on the case-folding substitution used here.
    bool searchForward(int startPos, const(char)[] searchString, out int foundPos, bool matchCase = false) const
    {
        while (startPos < length_)
        {
            int bp = startPos;
            size_t sp = 0;
            for (;;)
            {
                if (sp >= searchString.length) { foundPos = startPos; return true; }
                if (matchCase)
                {
                    if (byteAt(bp) != searchString[sp]) break;
                    sp += 1;
                    bp += 1;
                }
                else
                {
                    int lp;
                    uint bc = charAt(bp);
                    uint sc = utf8DecodeAt(searchString, sp, lp);
                    if (toLower(cast(dchar) bc) != toLower(cast(dchar) sc)) break;
                    sp += lp;
                    bp = nextChar(bp);
                }
            }
            startPos = nextChar(startPos);
        }
        foundPos = 0;
        return false;
    }

    /// Searches backward, starting the match attempt *at* startPos (not
    /// before it); returns true and sets foundPos to the match start if
    /// found.
    bool searchBackward(int startPos, const(char)[] searchString, out int foundPos, bool matchCase = false) const
    {
        while (startPos >= 0)
        {
            int bp = startPos;
            size_t sp = 0;
            for (;;)
            {
                if (sp >= searchString.length) { foundPos = startPos; return true; }
                if (matchCase)
                {
                    if (byteAt(bp) != searchString[sp]) break;
                    sp += 1;
                    bp += 1;
                }
                else
                {
                    int lp;
                    uint bc = charAt(bp);
                    uint sc = utf8DecodeAt(searchString, sp, lp);
                    if (toLower(cast(dchar) bc) != toLower(cast(dchar) sc)) break;
                    sp += lp;
                    bp = nextChar(bp);
                }
            }
            startPos = prevChar(startPos);
        }
        foundPos = 0;
        return false;
    }

    // -- Character stepping / UTF-8 alignment -----------------------------

    /// Returns the byte offset of the character after pos, clipped to
    /// length() at the end of the buffer. **Emoji-sequence-aware**:
    /// steps over a whole flag/ZWJ-joined/skin-toned/keycap/
    /// subdivision-flag emoji sequence as one "character", matching
    /// FLTK's `next_char()` -> `fl_utf8_next_composed_char()`
    /// exactly (not a general Unicode grapheme-cluster algorithm --
    /// FLTK's own curated heuristic, ported verbatim, see
    /// `utf8NextComposedCharLen()` below).
    int nextChar(int pos) const
    {
        if (pos >= length_) return length_;

        int len = utf8Len(byteAt(pos));
        if (len > 0) // possible start of an emoji sequence
        {
            // Ported from Fl_Text_Buffer::next_char()'s own 40-byte
            // lookahead window -- "longest emoji sequences I know use
            // 28 bytes in UTF8 (e.g. the Wales flag)", FLTK's own
            // comment.
            char[40] t;
            int tlen;
            int p = pos;
            int countPoints;
            while (p < length_ && tlen < t.length)
            {
                char b = byteAt(p++);
                t[tlen++] = b;
                int ll = utf8Len1(b);
                countPoints++;
                for (int i = 1; i < ll && tlen < t.length; i++)
                    t[tlen++] = byteAt(p++);
                if (countPoints > 1 && (ll == 1 || ll == 2))
                    break; // short codepoint, but not the 1st -- stop
            }
            len = tlen > 0 ? utf8NextComposedCharLen(t[0 .. tlen]) : 0;
        }
        else if (len == -1)
            len = 1;

        pos += len;
        return pos >= length_ ? length_ : pos;
    }

    /// Same as nextChar() -- FLTK's next_char_clipped() is a plain
    /// alias for next_char() too (next_char() already clips to
    /// length()).
    int nextCharClipped(int pos) const { return nextChar(pos); }

    /// Returns the byte offset of the character before pos, clipped to
    /// 0 at the start of the buffer. **Emoji-sequence-aware**
    /// (see nextChar()'s doc comment): the backward twin,
    /// ported from `prev_char_clipped()` -> `fl_utf8_previous_composed_
    /// char()`.
    int prevCharClipped(int pos) const
    {
        if (pos <= 0) return 0;

        // Ported from Fl_Text_Buffer::prev_char_clipped()'s own
        // 40-byte lookback window.
        enum lt = 40;
        char[lt] t;
        int len = lt;
        int p = pos;
        for (int i = lt; i > 0 && p > 0; i--)
        {
            t[--len] = byteAt(--p);
            int ll = utf8Len(t[len]); // -1 (not 1) for a continuation byte -- see nextChar()'s sibling window-fill loop, which uses utf8Len1() instead because FLTK does too
            if (ll == 1 || ll == 2) break;
        }
        auto window = t[len .. lt];
        size_t previous = utf8PreviousComposedCharIndex(window);
        return pos - cast(int) window.length + cast(int) previous;
    }

    /// Returns the byte offset of the character before pos, or -1 if pos
    /// is already 0 (FLTK's "ran off the start" sentinel).
    int prevChar(int pos) const { return pos == 0 ? -1 : prevCharClipped(pos); }

    /// Aligns pos backward to the start of the UTF-8 sequence it falls
    /// within (a no-op if it's already on a boundary).
    int utf8Align(int pos) const
    {
        char c = byteAt(pos);
        while ((cast(ubyte) c & 0xc0) == 0x80)
        {
            pos--;
            c = byteAt(pos);
        }
        return pos;
    }

    // -- File I/O -----------------------------------------------------------
    // See the module comment: bulk read/write via std.file/std.stdio
    // rather than FLTK's chunked, re-fillable line buffer. buflen is
    // accepted for signature fidelity but unused.

    /// Inserts the contents of file at pos. Returns 0 on success, 1 if
    /// the file couldn't be opened for reading, 2 on a read error
    /// (partial data may have been inserted). Non-UTF-8 input is
    /// transcoded through the same CP1252/ISO-8859-1 fallback
    /// utf8DecodeAt() uses elsewhere; inputFileWasTranscoded reports
    /// whether that happened, and transcodingWarningAction (if set) is
    /// called afterward.
    int insertfile(string file, int pos, int buflen = 128 * 1024)
    {
        import std.file : read;

        ubyte[] raw;
        try
        {
            raw = cast(ubyte[]) read(file);
        }
        catch (Exception)
        {
            return 1;
        }

        bool transcoded;
        string utf8Text;
        try
        {
            utf8Text = transcodeToUtf8(raw, transcoded);
        }
        catch (Exception)
        {
            return 2;
        }

        inputFileWasTranscoded = transcoded;
        insert(pos, utf8Text);

        if (transcoded && transcodingWarningAction !is null) transcodingWarningAction(this);

        return 0;
    }

    /// Appends the contents of file to the end of the buffer.
    int appendfile(string file, int buflen = 128 * 1024) { return insertfile(file, length_, buflen); }

    /// Replaces the entire buffer with the contents of file.
    int loadfile(string file, int buflen = 128 * 1024)
    {
        select(0, length_);
        removeSelection();
        return appendfile(file, buflen);
    }

    /// Writes the byte range [start, end) to file. Returns 0 on success,
    /// 1 if the file couldn't be opened for writing, 2 on a write error.
    int outputfile(string file, int start, int end, int buflen = 128 * 1024)
    {
        import std.stdio : File;

        File fp;
        try
        {
            fp = File(file, "wb");
        }
        catch (Exception)
        {
            return 1;
        }
        try
        {
            fp.rawWrite(textRange(start, end));
        }
        catch (Exception)
        {
            return 2;
        }
        return 0;
    }

    /// Writes the entire buffer to file.
    int savefile(string file, int buflen = 128 * 1024) { return outputfile(file, 0, length_, buflen); }

    // -----------------------------------------------------------------
    // Internal helpers
    // -----------------------------------------------------------------

    /// Internal (non-notifying) insert: no predelete/modify callbacks,
    /// but does update selections and undo history. Returns the number
    /// of bytes actually inserted.
    protected int insert_(int pos, const(char)[] text, int insertedLength = -1)
    {
        if (text.length == 0) return 0;
        int n = insertedLength < 0 ? cast(int) text.length : insertedLength;
        if (n == 0) return 0;
        text = text[0 .. n];

        if (n > gapEnd_ - gapStart_)
            reallocateWithGap(pos, n + preferredGapSize_);
        else if (pos != gapStart_)
            moveGap(pos);

        buf_[pos .. pos + n] = text[];
        gapStart_ += n;
        length_ += n;
        updateSelections(pos, 0, n);

        if (canUndo_)
        {
            if (undo_.undoat == pos && undo_.undoinsert)
            {
                undo_.undoinsert += n;
            }
            else
            {
                int yankcut = (undo_.undoat == pos) ? undo_.undocut : 0;
                if (!yankcut)
                {
                    redoList_.clear();
                    undoList_.push(undo_);
                    undo_ = new TextUndoAction();
                }
                undo_.undoinsert = n;
                undo_.undoyankcut = yankcut;
            }
            undo_.undoat = pos + n;
            undo_.undocut = 0;
        }

        return n;
    }

    /// Internal (non-notifying) remove: no predelete/modify callbacks,
    /// but does update selections and undo history, and moves the gap
    /// to the deletion site.
    protected void remove_(int start, int end)
    {
        if (start >= end) return;

        if (canUndo_)
        {
            if (undo_.undoat == end && undo_.undocut)
            {
                undo_.undobuffersize(undo_.undocut + end - start + 1);
                auto shifted = undo_.undobuffer[0 .. undo_.undocut].dup;
                undo_.undobuffer[end - start .. end - start + undo_.undocut] = shifted;
                undo_.undocut += end - start;
            }
            else
            {
                redoList_.clear();
                undoList_.push(undo_);
                undo_ = new TextUndoAction();
                undo_.undocut = end - start;
                undo_.undobuffersize(undo_.undocut);
            }
            undo_.undoat = start;
            undo_.undoinsert = 0;
            undo_.undoyankcut = 0;
        }

        if (start > gapStart_)
        {
            if (canUndo_)
                undo_.undobuffer[0 .. end - start] =
                    buf_[(gapEnd_ - gapStart_) + start .. (gapEnd_ - gapStart_) + end];
            moveGap(start);
        }
        else if (end < gapStart_)
        {
            if (canUndo_) undo_.undobuffer[0 .. end - start] = buf_[start .. end];
            moveGap(end);
        }
        else
        {
            int prelen = gapStart_ - start;
            if (canUndo_)
            {
                undo_.undobuffer[0 .. prelen] = buf_[start .. gapStart_];
                undo_.undobuffer[prelen .. end - start] = buf_[gapEnd_ .. gapEnd_ + (end - start - prelen)];
            }
        }

        gapEnd_ += end - gapStart_;
        gapStart_ = start;
        length_ -= end - start;
        updateSelections(start, end - start, 0);
    }

    /// Notifies redisplay callbacks of a selection boundary change,
    /// splitting old vs. new into the minimal set of changed sub-ranges.
    protected void redisplaySelection(TextSelection oldSelection, TextSelection newSelection) const
    {
        int oldStart = oldSelection.start_;
        int newStart = newSelection.start_;
        int oldEnd = oldSelection.end_;
        int newEnd = newSelection.end_;

        if (!oldSelection.selected_ && !newSelection.selected_) return;
        if (!oldSelection.selected_)
        {
            callModifyCallbacks(newStart, 0, 0, newEnd - newStart, null);
            return;
        }
        if (!newSelection.selected_)
        {
            callModifyCallbacks(oldStart, 0, 0, oldEnd - oldStart, null);
            return;
        }
        if (oldEnd < newStart || newEnd < oldStart)
        {
            callModifyCallbacks(oldStart, 0, 0, oldEnd - oldStart, null);
            callModifyCallbacks(newStart, 0, 0, newEnd - newStart, null);
            return;
        }

        int ch1Start = min(oldStart, newStart);
        int ch2End = max(oldEnd, newEnd);
        int ch1End = max(oldStart, newStart);
        int ch2Start = min(oldEnd, newEnd);
        if (ch1Start != ch1End) callModifyCallbacks(ch1Start, 0, 0, ch1End - ch1Start, null);
        if (ch2Start != ch2End) callModifyCallbacks(ch2Start, 0, 0, ch2End - ch2Start, null);
    }

    /// Moves the gap to start at pos, without changing logical content.
    protected void moveGap(int pos)
    {
        int gapLen = gapEnd_ - gapStart_;
        if (pos > gapStart_)
            memmove(buf_.ptr + gapStart_, buf_.ptr + gapEnd_, pos - gapStart_);
        else
            memmove(buf_.ptr + pos + gapLen, buf_.ptr + pos, gapStart_ - pos);
        gapEnd_ += pos - gapStart_;
        gapStart_ = pos; // FLTK writes this as `mGapStart += pos - mGapStart`
    }

    /// Reallocates storage so the gap starts at newGapStart with length
    /// newGapLen, preserving current content.
    protected void reallocateWithGap(int newGapStart, int newGapLen)
    {
        auto newBuf = new char[length_ + newGapLen];
        int newGapEnd = newGapStart + newGapLen;

        if (newGapStart <= gapStart_)
        {
            newBuf[0 .. newGapStart] = buf_[0 .. newGapStart];
            newBuf[newGapEnd .. newGapEnd + (gapStart_ - newGapStart)] = buf_[newGapStart .. gapStart_];
            newBuf[newGapEnd + gapStart_ - newGapStart .. newGapEnd + gapStart_ - newGapStart + (length_ - gapStart_)]
                = buf_[gapEnd_ .. gapEnd_ + (length_ - gapStart_)];
        }
        else
        {
            newBuf[0 .. gapStart_] = buf_[0 .. gapStart_];
            newBuf[gapStart_ .. newGapStart] = buf_[gapEnd_ .. gapEnd_ + (newGapStart - gapStart_)];
            newBuf[newGapEnd .. newGapEnd + (length_ - newGapStart)] =
                buf_[gapEnd_ + newGapStart - gapStart_ .. gapEnd_ + newGapStart - gapStart_ + (length_ - newGapStart)];
        }

        buf_ = newBuf;
        gapStart_ = newGapStart;
        gapEnd_ = newGapEnd;
    }

    /// Returns a copy of sel's selected text, or "" if sel isn't
    /// selected.
    protected string selectionText_(TextSelection sel) const
    {
        int start, end;
        if (!sel.selected(start, end)) return "";
        return textRange(start, end);
    }

    /// Removes sel's selected text from the buffer (a no-op if sel isn't
    /// selected).
    protected void removeSelection_(TextSelection sel)
    {
        int start, end;
        if (!sel.selected(start, end)) return;
        remove(start, end);
    }

    /// Replaces sel's selected text, then clears sel (mutates it through
    /// ref, since replaceSelection()/replaceSecondarySelection() need
    /// the clear to propagate back to the actual primary_/secondary_
    /// field).
    protected void replaceSelection_(ref TextSelection sel, const(char)[] text)
    {
        auto oldSelection = sel;
        int start, end;
        if (!sel.selected(start, end)) return;
        replace(start, end, text);
        sel.selected_ = false;
        redisplaySelection(oldSelection, sel);
    }

    /// Adjusts all three selections for a buffer edit at pos.
    protected void updateSelections(int pos, int nDeleted, int nInserted)
    {
        primary_.update(pos, nDeleted, nInserted);
        secondary_.update(pos, nDeleted, nInserted);
        highlight_.update(pos, nDeleted, nInserted);
    }
}

/// Transcodes raw file bytes to UTF-8, matching src/fl_utf8.cxx's
/// utf8_input_filter(): decode each sequence via utf8DecodeAt() (with
/// the CP1252/ISO-8859-1 fallback for anything that isn't valid UTF-8),
/// then re-encode it, so the result is always well-formed UTF-8.
/// wasTranscoded is set if the output ever differs from a literal
/// byte-for-byte copy of the input.
private string transcodeToUtf8(const(ubyte)[] raw, out bool wasTranscoded)
{
    auto s = cast(const(char)[]) raw;
    char[] outBuf;
    outBuf.reserve(s.length);
    size_t i = 0;
    wasTranscoded = false;
    while (i < s.length)
    {
        int predictedLen = utf8Len1(s[i]);
        size_t windowEnd = i + predictedLen;
        if (windowEnd > s.length) windowEnd = s.length;
        int lp;
        uint u = utf8DecodeAt(s[0 .. windowEnd], i, lp);
        char[4] enc;
        int lq = utf8Encode(u, enc[]);
        if (lp != predictedLen || lq != predictedLen) wasTranscoded = true;
        outBuf ~= enc[0 .. lq];
        i += lp;
    }
    return outBuf.idup;
}

private void diagnostic(string message)
{
    import std.stdio : stderr;

    stderr.writeln(message);
}

// =======================================================================
// Tests
// =======================================================================

unittest
{
    // Basic insert at start/middle/end of an empty and non-empty buffer.
    auto buf = new TextBuffer();
    assert(buf.length() == 0);
    assert(buf.text() == "");

    buf.insert(0, "hello");
    assert(buf.text() == "hello");
    assert(buf.length() == 5);

    buf.insert(5, " world"); // end
    assert(buf.text() == "hello world");

    buf.insert(5, ","); // middle
    assert(buf.text() == "hello, world");

    buf.insert(0, ">> "); // start
    assert(buf.text() == ">> hello, world");
}

unittest
{
    // append(), remove() at start/middle/end, replace().
    auto buf = new TextBuffer();
    buf.append("0123456789");
    assert(buf.text() == "0123456789");

    buf.remove(0, 2); // start
    assert(buf.text() == "23456789");

    buf.remove(buf.length() - 2, buf.length()); // end
    assert(buf.text() == "234567");

    buf.remove(2, 4); // middle
    assert(buf.text() == "2367");

    buf.replace(1, 3, "XY");
    assert(buf.text() == "2XY7");

    // remove() swaps out-of-order args and clamps out-of-range ones.
    buf.text("abcdef");
    buf.remove(4, 2);
    assert(buf.text() == "abef");
    buf.remove(-5, 1000);
    assert(buf.text() == "");
}

unittest
{
    // Gap buffer correctness under repeated insertions at varying
    // locations, forcing the gap to move (and, with a tiny preferred gap
    // size, to reallocate) repeatedly.
    auto buf = new TextBuffer(0, 4);
    string expected = "";

    buf.insert(0, "m");
    expected = "m";
    assert(buf.text() == expected);

    buf.insert(0, "a"); // before the gap's current position
    expected = "a" ~ expected;
    assert(buf.text() == expected);

    buf.append("z"); // after
    expected ~= "z";
    assert(buf.text() == expected);

    buf.insert(1, "b"); // middle, forces the gap to move backward
    expected = expected[0 .. 1] ~ "b" ~ expected[1 .. $];
    assert(buf.text() == expected);

    foreach (i; 0 .. 40)
    {
        int pos = (i * 7) % (cast(int) expected.length + 1);
        string s = [cast(char) ('A' + (i % 26))];
        buf.insert(pos, s);
        expected = expected[0 .. pos] ~ s ~ expected[pos .. $];
    }
    assert(buf.text() == expected);
    assert(buf.length() == cast(int) expected.length);
}

unittest
{
    // text()/textRange()/charAt()/byteAt() round-tripping.
    auto buf = new TextBuffer();
    buf.text("The quick brown fox");

    assert(buf.text() == "The quick brown fox");
    assert(buf.textRange(4, 9) == "quick");
    assert(buf.textRange(0, 3) == "The");
    assert(buf.textRange(0, 0) == "");
    assert(buf.textRange(1000, 2000) == ""); // start out of range -> ""

    foreach (i, c; "The quick brown fox")
        assert(buf.charAt(cast(int) i) == cast(uint) c);
    foreach (i, c; "The quick brown fox")
        assert(buf.byteAt(cast(int) i) == c);

    assert(buf.charAt(-1) == 0);
    assert(buf.charAt(1000) == 0);
    assert(buf.byteAt(-1) == '\0');
    assert(buf.byteAt(1000) == '\0');
}

unittest
{
    // UTF-8: multi-byte characters, charAt() decoding to the right
    // codepoint, and utf8Align().
    auto buf = new TextBuffer();
    // "café" -- 'é' is U+00E9, 2 bytes in UTF-8 (0xC3 0xA9).
    buf.text("café");
    assert(buf.length() == 5); // 4 ASCII bytes + 2 bytes for 'é' = wait: c,a,f = 3 bytes + 2 = 5
    assert(buf.charAt(3) == 0x00e9);
    assert(buf.byteAt(3) == cast(char) 0xc3);
    assert(buf.byteAt(4) == cast(char) 0xa9);

    // utf8Align() on the trailing continuation byte lands back on the lead byte.
    assert(buf.utf8Align(4) == 3);
    assert(buf.utf8Align(3) == 3); // already aligned

    // nextChar()/prevChar() step by whole codepoints, not raw bytes.
    assert(buf.nextChar(3) == 5); // over the whole 2-byte 'é'
    assert(buf.prevChar(5) == 3);
    assert(buf.prevChar(0) == -1); // FLTK's "ran off the start" sentinel

    // A 3-byte and a 4-byte codepoint: CJK "文" (U+6587) and an emoji
    // outside the BMP, U+1F600 (4 bytes).
    auto buf2 = new TextBuffer();
    buf2.text("a文b\U0001F600c");
    int pos = 0;
    assert(buf2.charAt(pos) == 'a'); pos = buf2.nextChar(pos);
    assert(buf2.charAt(pos) == 0x6587); pos = buf2.nextChar(pos);
    assert(buf2.charAt(pos) == 'b'); pos = buf2.nextChar(pos);
    assert(buf2.charAt(pos) == 0x1F600); pos = buf2.nextChar(pos);
    assert(buf2.charAt(pos) == 'c'); pos = buf2.nextChar(pos);
    assert(pos == buf2.length());
}

unittest
{
    // nextChar()/prevChar() step over a whole emoji sequence as one
    // "character", matching FLTK's fl_utf8_next_composed_char()/
    // fl_utf8_previous_composed_char() -- see this module's top
    // comment and nextChar()'s own doc comment. Each sequence is
    // embedded between two ASCII marker letters so nextChar()/
    // prevChar() land on real boundaries on both sides, not just at
    // the buffer's own start/end (where the lookahead/lookback window
    // has fewer real bytes of context to work with).
    void checkComposed(string seq, size_t expectedBytes)
    {
        assert(seq.length == expectedBytes, seq);
        auto buf = new TextBuffer();
        buf.text("a" ~ seq ~ "b");
        int start = 1; // just after 'a'
        int end = 1 + cast(int) seq.length; // just before 'b'
        assert(buf.nextChar(start) == end);
        assert(buf.prevChar(end) == start);
    }

    // Flag: two regional-indicator symbols (Netherlands, "NL").
    checkComposed("\U0001F1F3\U0001F1F1", 8);

    // Keycap: '9' + variation selector + combining enclosing keycap.
    checkComposed("9\U0000FE0F\U000020E3", 7);

    // Skin tone: thumbs-up + Fitzpatrick modifier.
    checkComposed("\U0001F44D\U0001F3FB", 8);

    // ZWJ-joined family: man-ZWJ-woman-ZWJ-girl-ZWJ-boy.
    checkComposed("\U0001F468\U0000200D\U0001F469\U0000200D"
        ~ "\U0001F467\U0000200D\U0001F466", 25);

    // Subdivision flag (Wales): waving black flag + 6 tag characters
    // (g,b,w,l,s,cancel) -- FLTK's own "28 bytes, longest I know"
    // example, and the one that sizes the 40-byte lookahead/lookback
    // window in the first place.
    checkComposed("\U0001F3F4\U000E0067\U000E0062\U000E0077"
        ~ "\U000E006C\U000E0073\U000E007F", 28);

    // A lone emoji with nothing to join to steps as a single ordinary
    // codepoint, not merged with unrelated neighboring text (already
    // covered by buf2 above, e.g. U+1F600 between 'b' and 'c'; keeping
    // that coverage in place rather than duplicating it here).
}

unittest
{
    // Selections: set/clear/position for all three kinds, and
    // specifically the FLTK 1.4+ "unselected returns 0" behavior --
    // this would catch a regression to the old 1.3.x behavior where a
    // stale start()/end() could leak through after deselecting.
    auto buf = new TextBuffer();
    buf.text("0123456789");

    buf.select(2, 5);
    assert(buf.selected());
    int s, e;
    assert(buf.selectionPosition(s, e));
    assert(s == 2 && e == 5);
    assert(buf.selectionText() == "234");

    buf.unselect();
    assert(!buf.selected());
    // The 1.4+ contract: start()/end() must read back as 0 once
    // unselected, even though the struct's raw fields (still 2 and 5)
    // are left untouched by unselect() -- see TextSelection's doc
    // comment and Fl_Text_Selection's own header note on this being a
    // deliberate behavior *change* from 1.3.x.
    assert(buf.primarySelection().start() == 0);
    assert(buf.primarySelection().end() == 0);
    assert(!buf.selectionPosition(s, e));
    assert(s == 0 && e == 0);
    assert(buf.selectionText() == "");

    buf.secondarySelect(1, 3);
    assert(buf.secondarySelected());
    assert(buf.secondarySelectionText() == "12");
    buf.secondaryUnselect();
    assert(!buf.secondarySelected());
    assert(buf.secondarySelection().start() == 0);
    assert(buf.secondarySelection().end() == 0);

    buf.highlight(4, 6);
    assert(buf.highlight());
    assert(buf.highlightText() == "45");
    buf.unhighlight();
    assert(!buf.highlight());
    assert(buf.highlightSelection().start() == 0);
    assert(buf.highlightSelection().end() == 0);

    // removeSelection()/replaceSelection().
    buf.select(0, 4);
    buf.replaceSelection("XY");
    assert(buf.text() == "XY456789");
    assert(!buf.selected()); // cleared by replaceSelection()

    buf.select(0, 2);
    buf.removeSelection();
    assert(buf.text() == "456789");
}

unittest
{
    // TextSelection in isolation: set()/update()/includes()/length().
    TextSelection sel;
    assert(!sel.selected());
    assert(sel.start() == 0 && sel.end() == 0 && sel.length() == 0);

    sel.set(5, 10);
    assert(sel.selected());
    assert(sel.start() == 5 && sel.end() == 10 && sel.length() == 5);
    assert(sel.includes(5));
    assert(sel.includes(9));
    assert(!sel.includes(10)); // end is exclusive
    assert(!sel.includes(4));

    sel.set(10, 5); // out of order -> swapped
    assert(sel.start() == 5 && sel.end() == 10);

    sel.set(3, 3); // empty range -> not selected
    assert(!sel.selected());

    // update(): insertion entirely before the selection shifts it.
    sel.set(10, 20);
    sel.update(0, 0, 5);
    assert(sel.start() == 15 && sel.end() == 25);

    // update(): deletion that entirely covers the selection clears it.
    sel.set(10, 20);
    sel.update(5, 30, 0);
    assert(!sel.selected());
}

unittest
{
    // Undo/redo: insert-then-undo, delete-then-undo, redo-after-undo.
    auto buf = new TextBuffer();

    buf.insert(0, "hello");
    assert(buf.canUndo());
    int cp;
    assert(buf.undo(&cp) != 0);
    assert(buf.text() == "");
    assert(!buf.canUndo());

    assert(buf.canRedo());
    assert(buf.redo(&cp) != 0);
    assert(buf.text() == "hello");

    // Delete-then-undo.
    buf.remove(1, 3); // removes "el" -> "hlo"
    assert(buf.text() == "hlo");
    assert(buf.undo() != 0);
    assert(buf.text() == "hello");

    // Multiple, *non-contiguous* edits undo in reverse order. (Two
    // insertions at the same running cursor position -- e.g. pos 3 right
    // after a 3-byte insert at pos 0 -- merge into a single undo action,
    // same as consecutive typing FLTK; inserting at pos 0 both times
    // keeps them as two distinct actions instead.)
    buf.text("");
    buf.insert(0, "AAA");
    buf.insert(0, "BBB"); // prepend -> "BBBAAA", a non-contiguous edit
    assert(buf.text() == "BBBAAA");
    assert(buf.undo() != 0);
    assert(buf.text() == "AAA");
    assert(buf.undo() != 0);
    assert(buf.text() == "");
    assert(!buf.canUndo());

    // Redo replays them back in the same order they were made.
    assert(buf.redo() != 0);
    assert(buf.text() == "AAA");
    assert(buf.redo() != 0);
    assert(buf.text() == "BBBAAA");
    assert(!buf.canRedo());
}

unittest
{
    // canUndo(false) disables undo tracking; canUndo(true) re-enables it
    // (without resurrecting old history).
    auto buf = new TextBuffer();
    buf.insert(0, "x");
    assert(buf.canUndo());

    buf.canUndo(false);
    assert(!buf.canUndo());
    buf.insert(1, "y"); // not tracked
    assert(buf.undo() == 0); // nothing to undo -- tracking was off
    assert(buf.text() == "xy");

    buf.canUndo(true);
    buf.insert(2, "z");
    assert(buf.canUndo());
    assert(buf.undo() != 0);
    assert(buf.text() == "xy");
}

unittest
{
    // A yank-cut (delete immediately followed by insert at the same
    // position, e.g. typing over a selection) undoes as a single step.
    auto buf = new TextBuffer();
    buf.text("hello world");
    buf.replace(0, 5, "goodbye"); // delete "hello", insert "goodbye" at 0
    assert(buf.text() == "goodbye world");
    assert(buf.undo() != 0);
    assert(buf.text() == "hello world");
}

unittest
{
    // Line navigation: lineStart()/lineEnd()/lineText()/countLines()/
    // skipLines()/rewindLines().
    auto buf = new TextBuffer();
    buf.text("line one\nline two\nline three");
    //         0        9        18

    assert(buf.lineStart(0) == 0);
    assert(buf.lineStart(3) == 0); // middle of first line
    assert(buf.lineStart(9) == 9); // right after the first '\n'
    assert(buf.lineStart(12) == 9);

    assert(buf.lineEnd(0) == 8); // the '\n' after "line one"
    assert(buf.lineEnd(20) == buf.length()); // last line has no trailing newline

    assert(buf.lineText(0) == "line one");
    assert(buf.lineText(9) == "line two");
    assert(buf.lineText(19) == "line three");

    assert(buf.countLines(0, buf.length()) == 2);
    assert(buf.countLines(0, 8) == 0); // up to (not including) the first newline

    assert(buf.skipLines(0, 1) == 9);
    assert(buf.skipLines(0, 2) == 18);

    assert(buf.rewindLines(buf.length(), 0) == 18); // start of the current (last) line
    assert(buf.rewindLines(19, 1) == 9);
    assert(buf.rewindLines(9, 1) == 0);
}

unittest
{
    // Word navigation: wordStart()/wordEnd()/isWordSeparator().
    auto buf = new TextBuffer();
    buf.text("one two, three!");
    //         0123456789...

    assert(buf.isWordSeparator(3)); // the space after "one"
    assert(!buf.isWordSeparator(0)); // 'o'

    assert(buf.wordStart(1) == 0); // middle of "one"
    assert(buf.wordEnd(1) == 3);

    assert(buf.wordStart(5) == 4); // middle of "two"
    assert(buf.wordEnd(5) == 7); // up to (not including) the comma

    assert(buf.wordStart(12) == 9); // middle of "three"
    assert(buf.wordEnd(12) == 14); // up to (not including) the '!'
}

unittest
{
    // Character search forward/backward, and case-(in)sensitive string
    // search.
    auto buf = new TextBuffer();
    buf.text("abcabcabc");

    int pos;
    assert(buf.findcharForward(0, 'b', pos));
    assert(pos == 1);
    assert(buf.findcharForward(2, 'b', pos));
    assert(pos == 4);
    assert(!buf.findcharForward(0, 'z', pos));
    assert(pos == buf.length());

    assert(buf.findcharBackward(9, 'c', pos));
    assert(pos == 8);
    assert(buf.findcharBackward(8, 'c', pos));
    assert(pos == 5);
    assert(!buf.findcharBackward(9, 'z', pos));
    assert(pos == 0);

    buf.text("The Quick Brown Fox");
    assert(buf.searchForward(0, "Quick", pos, true));
    assert(pos == 4);
    assert(!buf.searchForward(0, "quick", pos, true)); // case-sensitive miss
    assert(buf.searchForward(0, "quick", pos, false)); // case-insensitive hit
    assert(pos == 4);

    assert(buf.searchBackward(buf.length() - 1, "Brown", pos, true));
    assert(pos == 10);
    assert(buf.searchBackward(buf.length() - 1, "brown", pos, false));
    assert(pos == 10);

    // Empty search string matches immediately at the start position
    // (matches FLTK: only a NULL search string is rejected, not an
    // empty one).
    assert(buf.searchForward(3, "", pos));
    assert(pos == 3);
}

unittest
{
    // Modify/predelete callback firing, with correct parameters.
    auto buf = new TextBuffer();
    buf.text("hello");

    struct ModifyCall { int pos, nInserted, nDeleted, nRestyled; string deletedText; }
    struct PredeleteCall { int pos, nDeleted; }
    ModifyCall[] modifyCalls;
    PredeleteCall[] predeleteCalls;

    buf.addModifyCallback((pos, nInserted, nDeleted, nRestyled, deletedText) {
        modifyCalls ~= ModifyCall(pos, nInserted, nDeleted, nRestyled, deletedText.idup);
    });
    buf.addPredeleteCallback((pos, nDeleted) {
        predeleteCalls ~= PredeleteCall(pos, nDeleted);
    });

    buf.insert(5, " world");
    assert(modifyCalls.length == 1);
    assert(modifyCalls[0] == ModifyCall(5, 6, 0, 0, ""));
    assert(predeleteCalls.length == 1);
    assert(predeleteCalls[0] == PredeleteCall(5, 0));

    buf.remove(0, 5); // removes "hello"
    assert(modifyCalls.length == 2);
    assert(modifyCalls[1] == ModifyCall(0, 0, 5, 0, "hello"));
    assert(predeleteCalls.length == 2);
    assert(predeleteCalls[1] == PredeleteCall(0, 5));

    buf.replace(0, 1, "W"); // " world" -> "World"
    assert(modifyCalls.length == 3);
    assert(modifyCalls[2] == ModifyCall(0, 1, 1, 0, " "));

    // removeModifyCallback()/removePredeleteCallback() actually stop
    // further notifications.
    auto lastLen = modifyCalls.length;
    void delegate(int, int, int, int, const(char)[]) noop = (a, b, c, d, e) {};
    buf.addModifyCallback(noop);
    buf.removeModifyCallback(noop);
    buf.insert(0, "!");
    assert(modifyCalls.length == lastLen + 1); // the removed callback didn't fire twice
}

unittest
{
    // Tab distance: getter/setter, and that the setter fires a
    // full-buffer modify callback (matching FLTK's back-compat
    // behavior, even though no text actually changes).
    auto buf = new TextBuffer();
    assert(buf.tabDistance() == 8); // FLTK's default

    buf.text("x\ty");
    int calls = 0;
    buf.addModifyCallback((pos, nInserted, nDeleted, nRestyled, deletedText) { calls++; });

    buf.tabDistance(4);
    assert(buf.tabDistance() == 4);
    assert(calls == 1);
}

unittest
{
    // insertfile()/outputfile() round-trip through a real temp file,
    // including a case that needs CP1252 transcoding.
    import std.file : tempDir, remove, exists;
    import std.path : buildPath;
    import std.uuid : randomUUID;

    auto path = buildPath(tempDir(), "fldtk-text-buffer-test-" ~ randomUUID().toString() ~ ".txt");
    scope (exit) if (exists(path)) remove(path);

    auto outBuf = new TextBuffer();
    outBuf.text("line one\nline two\n");
    assert(outBuf.savefile(path) == 0);

    auto inBuf = new TextBuffer();
    assert(inBuf.loadfile(path) == 0);
    assert(inBuf.text() == "line one\nline two\n");
    assert(!inBuf.inputFileWasTranscoded);

    // A file with a raw CP1252 byte (0x93, "left double quotation mark")
    // where valid UTF-8 would never have that byte as a lead byte.
    import std.file : write;

    write(path, cast(ubyte[]) [0x41, 0x93, 0x42]); // "A" 0x93 "B"
    auto transBuf = new TextBuffer();
    assert(transBuf.loadfile(path) == 0);
    assert(transBuf.inputFileWasTranscoded);
    assert(transBuf.charAt(1) == 0x201C); // CP1252 0x93 -> U+201C

    // insertfile() on a nonexistent file reports an error, not a crash.
    auto missBuf = new TextBuffer();
    assert(missBuf.insertfile(path ~ ".does-not-exist", 0) == 1);
}

unittest
{
    // Every other test in this file builds its buffer via text(string),
    // which parks the gap at the very end (gapStart_ == length_). That
    // means textRange()'s "straddle" branch and the second half of
    // countLines()/estimateLines()/skipLines()/rewindLines() (the
    // post-gap `buf_[pos + gapLen]` reads) have never actually run.
    // Force the gap into the middle of the buffer with a real insert,
    // then cross-check every gap-position-sensitive function against a
    // same-content reference buffer whose gap sits at the end, across a
    // spread of positions before/at/after the gap.
    immutable content = "aaa\nbbbXY\nccc\nddd";

    auto reference = new TextBuffer();
    reference.text(content); // gap parked at the end

    auto midGap = new TextBuffer();
    midGap.text("aaa\nbbb\nccc\nddd");
    midGap.insert(7, "XY"); // strands the gap at index 9, mid-buffer
    assert(midGap.text() == content);
    assert(midGap.gapStart_ > 0 && midGap.gapStart_ < midGap.length());

    assert(reference.text() == midGap.text());
    immutable n = midGap.length();

    // textRange: every combination straddles, precedes, or follows the
    // gap depending on start/end relative to gapStart_ (9).
    foreach (start; 0 .. n + 1)
        foreach (end; start .. n + 1)
            assert(midGap.textRange(start, end) == reference.textRange(start, end));

    // countLines/estimateLines/skipLines/rewindLines from every position.
    foreach (pos; 0 .. n + 1)
    {
        assert(midGap.countLines(0, pos) == reference.countLines(0, pos));
        assert(midGap.estimateLines(0, pos, 1000) == reference.estimateLines(0, pos, 1000));
    }
    foreach (nLines; 0 .. 5)
    {
        assert(midGap.skipLines(0, nLines) == reference.skipLines(0, nLines));
        assert(midGap.rewindLines(n, nLines) == reference.rewindLines(n, nLines));
    }

    // lineStart/lineEnd/lineText, which route through textRange/findchar.
    foreach (pos; 0 .. n)
    {
        assert(midGap.lineStart(pos) == reference.lineStart(pos));
        assert(midGap.lineEnd(pos) == reference.lineEnd(pos));
        assert(midGap.lineText(pos) == reference.lineText(pos));
    }
}
