/*
 * Ported from FL/Fl_Input_.H + src/Fl_Input_.cxx (FLTK 1.5.0). Fl_Input_ is the virtual base class below
 * Fl_Input -- all the text-buffer/undo/selection/scrolling logic, minus
 * handle()/draw() themselves (those live in fl.input, mirroring
 * FLTK's split).
 *
 * BIGGEST deliberate deviation from FLTK, applied throughout this
 * file: `value_` is a plain D `string`, not a `const char*` aliasing
 * either a caller-owned literal or a malloc'd `buffer`/`bufsize` the
 * widget grows by hand. FLTK's buffer/bufsize/put_in_buffer()
 * machinery exists purely to avoid copying a caller's static string
 * into an owned buffer until the user actually edits it (C strings have
 * no other way to share ownership safely). D `string` is already
 * immutable and GC-owned, so aliasing a caller's literal *is* always
 * safe -- there is no copy to defer. This eliminates `buffer`/
 * `bufsize`/`put_in_buffer()` entirely: `static_value()` and `value()`
 * collapse into the same implementation, `size()` is just
 * `value_.length` (dropped as a separate field -- it can never desync),
 * and edits in replace()/applyUndo() are plain slice+concatenation
 * rather than malloc/realloc/memmove. The undo buffer gets the same
 * treatment: `Fl_Input_Undo_Action::undobuffer` (a malloc'd byte array
 * with manual resizing) becomes a plain `string` slice/concatenation
 * too, and `Fl_Input_Undo_Action_List` (a hand-grown pointer array)
 * becomes a plain `UndoAction[]` used as a stack. See CONVENTIONS.md's
 * "check for a cleaner D stdlib alternative" porting convention -- this
 * is that principle applied at buffer-ownership granularity, not just
 * to individual libc calls.
 *
 * Other deviations, all narrower:
 *  - UTF-8 helpers (utf8Len/utf8Len1/utf8DecodeAt/utf8Encode) are
 *    imported from fl.text_buffer rather than re-ported from
 *    src/fl_utf8.cxx a second time -- same subset of fl_utf8.cxx, same
 *    behavior, package(fl)-visible for exactly this kind of reuse.
 *  - fl_utf8_next_composed_char()/fl_utf8_previous_composed_char()
 *    (src/fl_utf8.cxx) additionally understand multi-codepoint emoji
 *    sequences (regional-indicator flag pairs, ZWJ joins, Fitzpatrick
 *    modifiers, variation selectors, "tag" subdivision-flag sequences).
 *    Not ported: nextChar()/prevCharStart() below advance/retreat by a
 *    single UTF-8 codepoint only. This affects cursor movement/deletion
 *    granularity for those specific multi-codepoint emoji sequences
 *    only -- ordinary text (any single script, combining marks aside)
 *    is unaffected.
 *  - Fl::compose()/Fl::screen_driver()->has_marked_text()/
 *    Fl::compose_state (IME composition/marked-text underlining): real
 *    dead-key/CJK composition is ported (fl.platform_x11's XOpenIM()/
 *    XCreateIC()/Xutf8LookupString()), so composed text lands correctly
 *    in this widget. What's correctly always-off is just the *visual*
 *    marked-text underline: drawtext()'s marked-text-underline branch
 *    and handletext()'s FL_UNFOCUS mark-reset stay simplified to their
 *    always-off path because `Fl::compose_state` genuinely never
 *    becomes non-zero on X11 even in real FLTK (confirmed
 *    against `Fl_X11_Screen_Driver.cxx`) -- that's not a port gap to
 *    close, it's FLTK's own X11 behavior, ported faithfully.
 *    fl.core.compose()/composeReset() exist and are called from
 *    fl.input's handle_key() for parity with this.
 *  - **`resetSpot()` is real**: `handletext()`'s `FL_UNFOCUS`/`FL_HIDE`
 *    case calls it unconditionally, matching `Fl_Input_::handle()`
 *    exactly. `setSpot()` itself (the "over the spot" preedit-
 *    *positioning* half, as opposed to this clearing half) is
 *    deliberately still not called from here, matching FLTK
 *    exactly -- a plain single-line `Fl_Input`/`Fl_Input_` never
 *    reports its own cursor position for IME positioning in real
 *    FLTK either, only the multi-line `Fl_Text_Display` does
 *    (see that module's row for the real call site).
 *  - Fl::copy()/Fl::paste(): backed by real selection ownership --
 *    fl.core.copy() claims real X11 selection ownership via
 *    XSetSelectionOwner(), and paste() delivers synchronously when
 *    already owned or asynchronously via XConvertSelection() otherwise.
 *    copy()/copyCuts()/handletext()'s FL_PASTE case use it.
 *  - isword(char) truncates a full Unicode codepoint down to its low 8
 *    bits before testing, exactly like FLTK's implicit
 *    `unsigned int` -> `char` narrowing in `isword(index(i))` -- a
 *    faithfully-preserved FLTK quirk (word-boundary detection can
 *    behave oddly on non-Latin1 codepoints), not something this port
 *    introduced.
 *  - up_down_pos/was_up_down (FLTK: `static double`/`static int`
 *    class members, genuinely shared across *every* Fl_Input_ instance
 *    process-wide) map to module-level D globals (upDownPos_/
 *    wasUpDown_) here, matching the fl.slider `offcenter`/fl.roller
 *    `ipos` precedent CONVENTIONS.md documents. `l_secret` (FLTK: a
 *    `static int` at file scope in Fl_Input_.cxx, likewise genuinely
 *    shared) becomes module-level `lSecret_` for the same reason.
 */
module fl.input_;

import std.ascii : isDigit, isHexDigit, isWhite, isAlphaNum;
import std.math : ceil;

import fl.enumerations;
import fl.widget : Widget;
import fl.core;
import fldraw = fl.draw;
import fl.text_buffer : utf8Len, utf8Len1, utf8DecodeAt, utf8Encode;

private enum MAXBUF = 1024;

/// Ported from Fl_Screen_Driver::secret_input_character (default 0x2022,
/// "•") -- the glyph FL_SECRET_INPUT masks every character with.
private enum uint secretInputCharacter = 0x2022;

/// Horizontal cursor position in pixels while moving up/down -- see the
/// module comment on why this is a module-level global, not a field.
private double upDownPos_ = 0;
/// Flag to remember the last cursor move was up/down -- ditto.
private bool wasUpDown_ = false;
/// Byte length of secretInputCharacter's UTF-8 encoding, cached by the
/// last expand() call that needed it -- ditto (mirrors FLTK's
/// file-scope `static int l_secret`).
private int lSecret_ = 0;

/// Ported from static int isword(char) (src/Fl_Input_.cxx). See the
/// module comment on the deliberate truncate-to-8-bits quirk.
private bool isword(uint codepoint)
{
    ubyte c = cast(ubyte) codepoint;
    if (c & 128) return true;
    if (isAlphaNum(cast(char) c)) return true;
    foreach (ch; "#%-@_~")
        if (cast(char) c == ch) return true;
    return false;
}

/// Ported from static int strict_word_start(const char*, int, int).
private int strictWordStart(string s, int i, InputType itype)
{
    if (itype == inputSecret) return 0;
    while (i > 0 && !isWhite(s[i - 1])) i--;
    return i;
}

/// Ported from static int strict_word_end(const char*, int, int, int).
private int strictWordEnd(string s, int len, int i, InputType itype)
{
    if (itype == inputSecret) return len;
    while (i < len && !isWhite(s[i])) i++;
    return i;
}

/**
 * Ported from Fl_Input_Undo_Action -- see the module comment for why
 * `undobuffer` is a plain `string` instead of a malloc'd byte array.
 */
private struct UndoAction
{
    string undobuffer;
    int undoat;       // points after insertion
    int undocut;      // number of bytes deleted there
    int undoinsert;   // number of bytes inserted
    int undoyankcut;  // length of valid contents of undobuffer, even if undocut == 0
}

/**
 * Ported from Fl_Input_ (FL/Fl_Input_.H + src/Fl_Input_.cxx). Virtual
 * base class below Fl_Input (fl.input.d) -- has every Fl_Input member
 * except handle()/draw() themselves. See the module comment for the
 * string-buffer simplification applied throughout.
 */
class Input_ : Widget
{
    private
    {
        string value_ = "";
        int position_;
        int mark_;
        bool tabNav_ = true;
        int xscroll_, yscroll_;
        int muP_;
        int maximumSize_ = 32767;
        int shortcut_;
        bool eraseCursorOnly_;
        Font textfont_;
        Fontsize textsize_;
        Color textcolor_;
        Color cursorColor_;

        UndoAction undo_;
        UndoAction[] undoList_;
        UndoAction[] redoList_;
    }

    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        box(Boxtype.downBox);
        color(fl.enumerations.background2Color, fl.enumerations.selectionColor);
        alignment(alignLeft);
        textsize_ = normalSize;
        textfont_ = helvetica;
        textcolor_ = foregroundColor;
        cursorColor_ = foregroundColor;
        mark_ = position_ = 0;
        value_ = "";
        xscroll_ = yscroll_ = 0;
        maximumSize_ = 32767;
        shortcut_ = 0;
        undo_ = UndoAction.init;
        shortcutLabel(true);
        setFlag(Flag.macUseAccentsMenu);
        needsKeyboard(true);
        tabNav_ = true;
    }

    // -------------------------------------------------------------
    // expand()/expandpos(): text-to-screen-representation machinery
    // -------------------------------------------------------------

    /// Placeholder text drawn while the input is empty.
    private string placeholder_;

    /// Ported from Fl_Input_::expand(const char*, char*). Renders
    /// value_[p..] into buf (control chars as ^X, tabs expanded,
    /// FL_SECRET_INPUT masking, word-wrap truncation), stopping at
    /// MAXBUF-4 output bytes. Returns the byte offset into value_ where
    /// rendering stopped, and the number of bytes written to buf via
    /// outLen.
    private int expand(int p, ref char[MAXBUF] buf, out int outLen) const
    {
        int o = 0;
        int e = MAXBUF - 4;
        int lastspace = p;
        int lastspaceOut = 0;
        double widthToLastspace = 0;
        int wordCount = 0;

        if (inputType() == inputSecret)
        {
            while (o < e && p < size())
            {
                if (utf8Len(value_[p]) >= 1)
                {
                    lSecret_ = utf8Encode(secretInputCharacter, buf[o .. $]);
                    o += lSecret_;
                }
                p++;
            }
        }
        else
        {
            while (o < e)
            {
                if (wrap() && (p >= size() || isWhite(byteAt(p))))
                {
                    int wordWrap = w() - fl.core.boxDw(box()) - 5; // space for cursor + gap (#1414)
                    widthToLastspace += fldraw.width(buf[lastspaceOut .. o]);
                    if (p > lastspace + 1)
                    {
                        if (wordCount && ceil(widthToLastspace) > wordWrap)
                        {
                            p = lastspace;
                            o = lastspaceOut;
                            break;
                        }
                        wordCount++;
                    }
                    lastspace = p;
                    lastspaceOut = o;
                }

                if (p >= size()) break;
                int c = cast(ubyte) value_[p];
                p++;
                if (c < ' ' || c == 127)
                {
                    if (c == '\n' && inputType() == inputMultiline) { p--; break; }
                    if (c == '\t' && inputType() == inputMultiline)
                    {
                        int col = utf8CharCount(buf[0 .. o]) % 8;
                        for (; col < 8 && o < e; col++) buf[o++] = ' ';
                    }
                    else
                    {
                        buf[o++] = '^';
                        buf[o++] = cast(char)(c ^ 0x40);
                    }
                }
                else
                {
                    buf[o++] = cast(char) c;
                }
            }
        }
        outLen = o;
        return p;
    }

    /// Counts UTF-8 *characters* (not bytes) in s -- ported from the
    /// `fl_utf_nb_char((uchar*)buf, (int)(o-buf))` call inside expand().
    private static int utf8CharCount(const(char)[] s)
    {
        int n = 0;
        size_t i = 0;
        while (i < s.length)
        {
            i += utf8Len1(s[i]);
            n++;
        }
        return n;
    }

    /// Ported from Fl_Input_::expandpos(). Computes the pixel width of
    /// value_[p..e) as rendered into buf by expand(), and (via
    /// returnN) the corresponding byte offset into buf.
    private double expandpos(int p, int e, const(char)[] buf, out int returnN) const
    {
        int n = 0;
        int chr = 0;
        if (inputType() == inputSecret)
        {
            while (p < e)
            {
                int l = utf8Len1(byteAt(p));
                n += lSecret_;
                p += l;
            }
        }
        else
        {
            while (p < e)
            {
                int c = cast(ubyte) byteAt(p);
                if (c < ' ' || c == 127)
                {
                    if (c == '\t' && inputType() == inputMultiline)
                    {
                        n += 8 - (chr % 8);
                        chr += 7 - (chr % 8);
                    }
                    else n += 2;
                }
                else
                {
                    n += utf8Len1(byteAt(p));
                }
                chr += (utf8Len(byteAt(p)) >= 1) ? 1 : 0;
                p += utf8Len1(byteAt(p));
            }
        }
        returnN = n;
        return fldraw.width(buf, n);
    }

    // -------------------------------------------------------------
    // minimal_update()
    // -------------------------------------------------------------

    private void minimalUpdate(int p)
    {
        if (damage() & damageAll) return;
        if (damage() & damageExpose)
        {
            if (p < muP_) muP_ = p;
        }
        else
        {
            muP_ = p;
        }
        damage(damageExpose);
        eraseCursorOnly_ = false;
    }

    private void minimalUpdate(int p, int q)
    {
        if (q < p) p = q;
        minimalUpdate(p);
    }

    // -------------------------------------------------------------
    // Byte-level access helpers
    // -------------------------------------------------------------

    /// value_[i], or '\0' past the end -- mirrors FLTK relying on
    /// value_'s C-string nul terminator at value_+size_ (D strings
    /// carry no such terminator, so this stands in for it).
    private char byteAt(int i) const
    {
        return (i >= 0 && i < cast(int) value_.length) ? value_[i] : '\0';
    }

    /// Ported from Fl_Input_::index(int). Returns the Unicode codepoint
    /// at byte index i, or 0 past the end (see byteAt()'s doc comment).
    uint index(int i) const
    {
        if (i < 0 || i >= size()) return 0;
        int len;
        return utf8DecodeAt(value_, i, len);
    }

    /// Simplified stand-in for fl_utf8_next_composed_char() -- see the
    /// module comment. protected: fl.input's kf_delete_char_right()/
    /// kf_move_char_right() need it too.
    protected int nextCharLen(int p) const
    {
        return utf8Len1(byteAt(p));
    }

    /// Simplified stand-in for fl_utf8_previous_composed_char() -- see
    /// the module comment. Returns the byte offset where the character
    /// immediately before p starts. protected for the same reason as
    /// nextCharLen().
    protected int prevCharStart(int p) const
    {
        int i = p - 1;
        while (i > 0 && (cast(ubyte) byteAt(i) & 0xc0) == 0x80) i--;
        return i;
    }

    // -------------------------------------------------------------
    // word_start()/word_end()/line_start()/line_end()
    // -------------------------------------------------------------

    protected int wordEnd(int i) const
    {
        if (inputType() == inputSecret) return size();
        while (i < size() && !isword(index(i))) i++;
        while (i < size() && isword(index(i))) i++;
        return i;
    }

    protected int wordStart(int i) const
    {
        if (inputType() == inputSecret) return 0;
        while (i > 0 && !isword(index(i - 1))) i--;
        while (i > 0 && isword(index(i - 1))) i--;
        return i;
    }

    protected int lineEnd(int i) const
    {
        if (inputType() != inputMultiline) return size();

        if (wrap())
        {
            int j = i;
            while (j > 0 && index(j - 1) != '\n') j--;
            setfont();
            char[MAXBUF] buf;
            for (int p = j; ; )
            {
                int elen;
                int e = expand(p, buf, elen);
                if (e >= i) return e;
                p = e + 1;
            }
        }
        else
        {
            while (i < size() && index(i) != '\n') i++;
            return i;
        }
    }

    protected int lineStart(int i) const
    {
        if (inputType() != inputMultiline) return 0;
        int j = i;
        while (j > 0 && index(j - 1) != '\n') j--;
        if (wrap())
        {
            setfont();
            char[MAXBUF] buf;
            for (int p = j; ; )
            {
                int elen;
                int e = expand(p, buf, elen);
                if (e >= i) return p;
                p = e + 1;
            }
        }
        else return j;
    }

    // -------------------------------------------------------------
    // drawtext()
    // -------------------------------------------------------------

    private void setfont() const
    {
        fldraw.fl_font(textfont(), textsize());
    }

    /// Ported from Fl_Input_::drawtext(int,int,int,int) -- forwards to
    /// the 5-arg overload with draw_active = (fl.core.focus() is this).
    protected void drawtext(int X, int Y, int W, int H)
    {
        drawtext(X, Y, W, H, fl.core.focus() is this);
    }

    /// Ported from Fl_Input_::drawtext(int,int,int,int,bool). Uses D
    /// `goto`/labels matching FLTK's control flow 1:1 (CONTINUE/
    /// CONTINUE2) rather than restructuring it -- the early-exit jumps
    /// are load-bearing (they skip a push_clip()/pop_clip() pair), and
    /// preserving the original shape is the safest way to keep that
    /// correct. Simplified vs FLTK: no IME marked-text
    /// underline/setSpot() (see the module comment).
    protected void drawtext(int X, int Y, int W, int H, bool drawActive)
    {
        bool doMu = !(damage() & damageAll);

        if (!drawActive && size() == 0)
        {
            if (doMu)
            {
                drawBox(box(), X - fl.core.boxDx(box()), Y - fl.core.boxDy(box()),
                    W + fl.core.boxDw(box()), H + fl.core.boxDh(box()), color());
            }
            // An empty input shows its placeholder in a washed-out color.
            if (placeholder_.length)
            {
                Color fg = textcolor();
                Color bg = color();
                if (!activeR())
                {
                    fg = fldraw.inactive(fg);
                    bg = fldraw.inactive(bg);
                }
                fldraw.fl_color(fldraw.colorAverage(fg, bg, .5f));
                fldraw.fl_font(textfont(), textsize());
                fldraw.fl_draw(placeholder_, X, Y, W, H, alignLeft | alignInside);
            }
            return;
        }
        // Clear a previously drawn placeholder once drawActive is set.
        if (size() == 0 && placeholder_.length && doMu)
        {
            drawBox(box(), X - fl.core.boxDx(box()), Y - fl.core.boxDy(box()),
                W + fl.core.boxDw(box()), H + fl.core.boxDh(box()), color());
        }

        int selstart, selend;
        if (!drawActive && fl.core.pushed() !is this)
        {
            selstart = selend = 0;
        }
        else if (insertPosition() <= mark())
        {
            selstart = insertPosition(); selend = mark();
        }
        else
        {
            selend = insertPosition(); selstart = mark();
        }

        setfont();
        char[MAXBUF] buf;

        int height = fldraw.height();
        int threshold = height / 2;
        int lines;
        int curx = 0, cury = 0;
        int p, e, elen;

        for (p = 0, curx = 0, cury = 0, lines = 0; ; )
        {
            e = expand(p, buf, elen);
            if (insertPosition() >= p && insertPosition() <= e)
            {
                int rn;
                curx = cast(int)(expandpos(p, insertPosition(), buf[0 .. elen], rn) + 0.5);
                if (drawActive && !wasUpDown_) upDownPos_ = curx;
                cury = lines * height;
                int newscroll = xscroll_;
                if (curx > newscroll + W - threshold)
                {
                    newscroll = curx + threshold - W;
                    int rn2;
                    int ex = cast(int) expandpos(p, e, buf[0 .. elen], rn2) + 4 - W;
                    if (ex < newscroll) newscroll = ex;
                }
                else if (curx < newscroll + threshold)
                {
                    newscroll = curx - threshold;
                }
                if (newscroll < 0) newscroll = 0;
                if (newscroll != xscroll_)
                {
                    xscroll_ = newscroll;
                    muP_ = 0; eraseCursorOnly_ = false;
                }
            }
            lines++;
            if (e >= size()) break;
            p = e + 1;
        }

        if (inputType() == inputMultiline)
        {
            int newy = yscroll_;
            if (cury < newy) newy = cury;
            if (cury > newy + H - height) newy = cury - H + height;
            if (newy < -1) newy = -1;
            if (newy != yscroll_) { yscroll_ = newy; muP_ = 0; eraseCursorOnly_ = false; }
        }
        else
        {
            yscroll_ = -(H - height) / 2;
        }

        fldraw.pushClip(X, Y, W, H);
        Color tc = activeR() ? textcolor() : fldraw.inactive(textcolor());

        p = 0;
        int desc = height - fldraw.descent();
        int xpos = X - xscroll_ + 1;
        int ypos = -yscroll_;
        int yposCur = 0;

        for (; ypos < H; )
        {
            if (lines > 1) e = expand(p, buf, elen);

            if (ypos <= -height) goto CONTINUE;

            if (doMu)
            {
                int pp = muP_;
                if (e < pp) goto CONTINUE2;
                if (readonly()) eraseCursorOnly_ = false;
                if (eraseCursorOnly_ && p > pp) goto CONTINUE2;

                int r = X + W;
                int xx;
                if (p >= pp)
                {
                    xx = X;
                    if (eraseCursorOnly_) r = xpos + 2;
                    else if (readonly()) xx -= 3;
                }
                else
                {
                    int rn;
                    xx = xpos + cast(int) expandpos(p, pp, buf[0 .. elen], rn);
                    if (eraseCursorOnly_) r = xx + 2;
                    else if (readonly()) xx -= 3;
                }
                fldraw.pushClip(xx - 1 - height / 8, Y + ypos, r - xx + 2 + height / 4, height);
                drawBox(box(), X - fl.core.boxDx(box()), Y - fl.core.boxDy(box()),
                    W + fl.core.boxDw(box()), H + fl.core.boxDh(box()), color());
            }

            if (selstart < selend && selstart <= e && selend > p)
            {
                int pp = selstart;
                int x1 = xpos;
                int offset1 = 0;
                if (pp > p)
                {
                    fldraw.fl_color(tc);
                    int rn;
                    x1 += cast(int) expandpos(p, pp, buf[0 .. elen], rn);
                    offset1 = rn;
                    fldraw.fl_draw(buf[0 .. elen], offset1, xpos, Y + ypos + desc);
                }
                pp = selend;
                int x2 = X + W;
                int offset2;
                if (pp <= e)
                {
                    int rn;
                    x2 = xpos + cast(int) expandpos(p, pp, buf[0 .. elen], rn);
                    offset2 = rn;
                }
                else offset2 = elen;

                fldraw.fl_color(selectionColor());
                fldraw.fl_rectf(cast(int)(x1 + 0.5), Y + ypos, cast(int)(x2 - x1 + 0.5), height);
                fldraw.fl_color(fldraw.contrast(textcolor(), selectionColor()));
                fldraw.fl_draw(buf[offset1 .. elen], offset2 - offset1, x1, Y + ypos + desc);

                if (pp < e)
                {
                    fldraw.fl_color(tc);
                    fldraw.fl_draw(buf[offset2 .. elen], elen - offset2, x2, Y + ypos + desc);
                }
            }
            else
            {
                fldraw.fl_color(tc);
                fldraw.fl_draw(buf[0 .. elen], elen, xpos, Y + ypos + desc);
            }

            if (doMu) fldraw.popClip();

        CONTINUE2:
            if (drawActive && selstart == selend
                && insertPosition() >= p && insertPosition() <= e)
            {
                fldraw.fl_color(cursorColor());
                int rn;
                curx = cast(int)(expandpos(p, insertPosition(), buf[0 .. elen], rn) + 0.5);
                if (readonly())
                {
                    fldraw.fl_line(cast(int)(xpos + curx - 2.5f), Y + ypos + height - 1,
                        cast(int)(xpos + curx + 0.5f), Y + ypos + height - 4,
                        cast(int)(xpos + curx + 3.5f), Y + ypos + height - 1);
                }
                else
                {
                    fldraw.fl_rectf(cast(int)(xpos + curx + 0.5), Y + ypos, 2, height, cursorColor());
                }
                yposCur = ypos + height;
            }

        CONTINUE:
            ypos += height;
            if (e >= size()) break;
            if (byteAt(e) == '\n' || byteAt(e) == ' ') e++;
            p = e;
        }

        if (inputType() == inputMultiline && doMu && ypos < H
            && (!eraseCursorOnly_ || p <= muP_))
        {
            if (ypos < 0) ypos = 0;
            fldraw.pushClip(X, Y + ypos, W, H - ypos);
            drawBox(box(), X - fl.core.boxDx(box()), Y - fl.core.boxDy(box()),
                W + fl.core.boxDw(box()), H + fl.core.boxDh(box()), color());
            fldraw.popClip();
        }

        fldraw.popClip();
    }

    // -------------------------------------------------------------
    // handle_mouse() / up_down_position() / insert_position()
    // -------------------------------------------------------------

    /// Ported from Fl_Input_::handle_mouse(int,int,int,int,int). W/H are
    /// unused, matching FLTK (kept in the signature only so callers
    /// mirror FLTK's own call sites).
    protected void handleMouse(int X, int Y, int W, int H, bool drag = false)
    {
        wasUpDown_ = false;
        if (size() == 0) return;
        setfont();

        char[MAXBUF] buf;
        int elen;

        int theline = (inputType() == inputMultiline)
            ? (fl.core.eventY() - Y + yscroll_) / fldraw.height() : 0;

        int p = 0, e = 0;
        for (p = 0; ; )
        {
            e = expand(p, buf, elen);
            theline--;
            if (theline < 0) break;
            if (e >= size()) break;
            p = e + 1;
        }

        int l = p, r = e;
        double f0 = fl.core.eventX() - X + xscroll_;
        while (l < r)
        {
            int cw = nextCharLen(l);
            int t = l + cw;
            int rn;
            double f = X - xscroll_ + expandpos(p, t, buf[0 .. elen], rn);
            if (f <= fl.core.eventX()) { l = t; f0 = fl.core.eventX() - f; }
            else r = t - cw;
        }
        if (l < e)
        {
            int cw = nextCharLen(l);
            if (cw > 0)
            {
                int rn;
                double f1 = X - xscroll_ + expandpos(p, l + cw, buf[0 .. elen], rn) - fl.core.eventX();
                if (f1 < f0) l = l + cw;
            }
        }
        int newpos = l;

        int newmark = drag ? mark() : newpos;
        if (fl.core.eventClicks())
        {
            if (newpos >= newmark)
            {
                if (newpos == newmark)
                {
                    if (newpos < size()) newpos++;
                    else newmark--;
                }
                if (fl.core.eventClicks() > 1)
                {
                    newpos = lineEnd(newpos);
                    newmark = lineStart(newmark);
                }
                else
                {
                    newpos = strictWordEnd(value_, size(), newpos, inputType());
                    newmark = strictWordStart(value_, newmark, inputType());
                }
            }
            else
            {
                if (fl.core.eventClicks() > 1)
                {
                    newpos = lineStart(newpos);
                    newmark = lineEnd(newmark);
                }
                else
                {
                    newpos = strictWordStart(value_, newpos, inputType());
                    newmark = strictWordEnd(value_, size(), newmark, inputType());
                }
            }
            if (!drag && (mark() > insertPosition()
                    ? (newmark >= insertPosition() && newpos <= mark())
                    : (newmark >= mark() && newpos <= insertPosition())))
            {
                fl.core.eventClicks(0);
                newmark = newpos = l;
            }
        }
        insertPosition(newpos, newmark);
    }

    /// Ported from Fl_Input_::insert_position(int,int).
    int insertPosition(int p, int m)
    {
        bool isSame = false;
        wasUpDown_ = false;
        if (p < 0) p = 0;
        if (p > size()) p = size();
        if (m < 0) m = 0;
        if (m > size()) m = size();
        if (p == m) isSame = true;

        while (p < position_ && p > 0 && (size() - p) > 0 && utf8Len(byteAt(p)) < 1) p--;
        int ul = utf8Len(byteAt(p));
        while (p < size() && p > position_ && ul < 0)
        {
            p++;
            ul = utf8Len(byteAt(p));
        }

        while (m < mark_ && m > 0 && (size() - m) > 0 && utf8Len(byteAt(m)) < 1) m--;
        ul = utf8Len(byteAt(m));
        while (m < size() && m > mark_ && ul < 0)
        {
            m++;
            ul = utf8Len(byteAt(m));
        }
        if (isSame) m = p;
        if (p == position_ && m == mark_) return 0;

        if (p != m)
        {
            if (p != position_) minimalUpdate(position_, p);
            if (m != mark_) minimalUpdate(mark_, m);
        }
        else
        {
            if (position_ == mark_)
            {
                if (fl.core.focus() is this && !(damage() & damageExpose))
                {
                    minimalUpdate(position_);
                    eraseCursorOnly_ = true;
                }
            }
            else
            {
                minimalUpdate(position_, mark_);
            }
        }
        position_ = p;
        mark_ = m;
        return 1;
    }

    int insertPosition(int p) { return insertPosition(p, p); }
    int insertPosition() const { return position_; }

    int mark() const { return mark_; }
    int mark(int m) { return insertPosition(insertPosition(), m); }

    /// Ported from Fl_Input_::up_down_position(int,int).
    protected int upDownPosition(int i, bool keepmark = false)
    {
        setfont();
        char[MAXBUF] buf;
        int elen;
        int p = i;
        int e = expand(p, buf, elen);
        int l = p, r = e;
        while (l < r)
        {
            int t = l + (r - l + 1) / 2;
            int rn;
            double f = expandpos(p, t, buf[0 .. elen], rn);
            if (f <= upDownPos_) l = t; else r = t - 1;
        }
        int j = l;
        j = insertPosition(j, keepmark ? mark_ : j);
        wasUpDown_ = true;
        return j;
    }

    // -------------------------------------------------------------
    // copy() / append() / replace() / undo() / redo()
    // -------------------------------------------------------------

    /// Ported from Fl_Input_::copy(int).
    int copy(int clipboard)
    {
        int b = insertPosition();
        int e = mark();
        if (b != e)
        {
            if (b > e) { b = mark(); e = insertPosition(); }
            if (inputType() == inputSecret) e = b;
            fl.core.copy(value_[b .. e], clipboard);
            return 1;
        }
        return 0;
    }

    int cut() { return replace(insertPosition(), mark(), null); }
    int cut(int n) { return replace(insertPosition(), insertPosition() + n, null); }
    int cut(int a, int b) { return replace(a, b, null); }

    int insert(string t) { return replace(position_, mark_, t); }

    /// Ported from Fl_Input_::append(const char*,int,char).
    int append(string t, bool keepSelection = false)
    {
        int end = size();
        int om = mark_, op = position_;
        int ret = replace(end, end, t);
        if (keepSelection) insertPosition(op, om);
        return ret;
    }

    /**
     * Ported from Fl_Input_::replace(int,int,const char*,int). Deletes
     * value_[b..e) and inserts text there, clamped to UTF-8 character
     * boundaries and maximum_size(). See the module comment for how the
     * undo bookkeeping's malloc'd buffer collapses to plain string
     * slicing here.
     */
    int replace(int b, int e, string text)
    {
        wasUpDown_ = false;

        if (b < 0) b = 0;
        if (e < 0) e = 0;
        if (b > size()) b = size();
        if (e > size()) e = size();
        if (e < b) { int t = b; b = e; e = t; }

        while (b != e && b > 0 && (size() - b) > 0 && utf8Len(byteAt(b)) < 1) b--;
        int ul = utf8Len(byteAt(e));
        while (e < size() && e > 0 && ul < 0) { e++; ul = utf8Len(byteAt(e)); }

        int ilen = cast(int) text.length;
        if (e <= b && ilen == 0) return 0;

        // Count characters (not bytes) outside [b,e) to enforce
        // maximum_size() the same UTF-8-aware way FLTK does.
        int nchars = 0;
        {
            int i = 0;
            while (i < size())
            {
                if (i == b)
                {
                    i = e;
                    if (i >= size()) break;
                }
                int ulen = utf8Len(value_[i]);
                if (ulen < 1) ulen = 1;
                nchars++;
                i += ulen;
            }
        }
        int nlen = 0;
        {
            int i = 0;
            while (i < ilen && nchars < maximumSize_)
            {
                int ulen = utf8Len(text[i]);
                if (ulen < 1) ulen = 1;
                nchars++;
                i += ulen;
                nlen += ulen;
            }
        }
        ilen = nlen;

        if (e > b)
        {
            if (b == undo_.undoat)
            {
                undo_.undobuffer ~= value_[b .. e];
                undo_.undocut += e - b;
            }
            else if (e == undo_.undoat && undo_.undoinsert == 0)
            {
                undo_.undobuffer = value_[b .. e] ~ undo_.undobuffer;
                undo_.undocut += e - b;
            }
            else if (e == undo_.undoat && (e - b) < undo_.undoinsert)
            {
                undo_.undoinsert -= e - b;
            }
            else
            {
                redoList_ = null;
                undoList_ ~= undo_;
                undo_ = UndoAction.init;
                undo_.undobuffer = value_[b .. e];
                undo_.undocut = e - b;
                undo_.undoinsert = 0;
            }
            value_ = value_[0 .. b] ~ value_[e .. $];
            undo_.undoat = b;
            undo_.undoyankcut = (inputType() == inputSecret) ? 0 : undo_.undocut;
        }

        if (ilen)
        {
            if (b == undo_.undoat)
            {
                undo_.undoinsert += ilen;
            }
            else
            {
                redoList_ = null;
                undoList_ ~= undo_;
                undo_ = UndoAction.init;
                undo_.undocut = 0;
                undo_.undoinsert = ilen;
            }
            value_ = value_[0 .. b] ~ text[0 .. ilen] ~ value_[b .. $];
        }

        int om = mark_;
        int op = position_;
        mark_ = position_ = undo_.undoat = b + ilen;

        if (wrap())
        {
            int i;
            for (i = 0; i < ilen; i++) if (text[i] == ' ') break;
            if (i == ilen)
            {
                while (b > 0 && !isWhite(byteAt(b)) && byteAt(b) != '\n') b--;
            }
            else
            {
                while (b > 0 && byteAt(b) != '\n') b--;
            }
        }

        if (om < b) b = om;
        if (op < b) b = op;

        minimalUpdate(b);

        mark_ = position_ = undo_.undoat;

        setChanged();
        if (when() & whenChanged) doCallback(CallbackReason.changed);
        return 1;
    }

    /// Ported from Fl_Input_::apply_undo().
    protected int applyUndo()
    {
        wasUpDown_ = false;
        if (undo_.undocut == 0 && undo_.undoinsert == 0) return 0;

        int ilen = undo_.undocut;
        int xlen = undo_.undoinsert;
        int b = undo_.undoat - xlen;
        int b1 = b;

        minimalUpdate(position_);

        if (ilen)
        {
            value_ = value_[0 .. b] ~ undo_.undobuffer[0 .. ilen] ~ value_[b .. $];
            b += ilen;
        }

        if (xlen)
        {
            undo_.undobuffer = value_[b .. b + xlen];
            value_ = value_[0 .. b] ~ value_[b + xlen .. $];
        }

        undo_.undocut = xlen;
        if (xlen) undo_.undoyankcut = xlen;
        undo_.undoinsert = ilen;
        undo_.undoat = b;
        mark_ = b;
        position_ = b;

        if (wrap())
            while (b1 > 0 && byteAt(b1) != '\n') b1--;
        minimalUpdate(b1);
        setChanged();

        return 1;
    }

    /// Ported from Fl_Input_::undo().
    int undo()
    {
        if (applyUndo() == 0) return 0;

        redoList_ ~= undo_;
        if (undoList_.length > 0)
        {
            undo_ = undoList_[$ - 1];
            undoList_.length -= 1;
        }
        else
        {
            undo_ = UndoAction.init;
        }

        if (when() & whenChanged) doCallback(CallbackReason.changed);

        return 1;
    }

    bool canUndo() const
    {
        return undo_.undocut != 0 || undo_.undoinsert != 0;
    }

    /// Ported from Fl_Input_::redo().
    int redo()
    {
        if (redoList_.length == 0) return 0;
        UndoAction redoAction = redoList_[$ - 1];
        redoList_.length -= 1;

        if (undo_.undocut || undo_.undoinsert)
            undoList_ ~= undo_;
        undo_ = redoAction;

        int ret = applyUndo();
        if (ret && (when() & whenChanged)) doCallback(CallbackReason.changed);

        return ret;
    }

    bool canRedo() const
    {
        return redoList_.length > 0;
    }

    /// Ported from Fl_Input_::copy_cuts().
    int copyCuts()
    {
        if (undo_.undoyankcut == 0 || inputType() == inputSecret) return 0;
        fl.core.copy(undo_.undobuffer[0 .. undo_.undoyankcut], 1);
        return 1;
    }

    // -------------------------------------------------------------
    // maybe_do_callback() / handletext()
    // -------------------------------------------------------------

    protected void maybeDoCallback(CallbackReason reason = CallbackReason.unknown)
    {
        if (changed() || (when() & whenNotChanged)) doCallback(reason);
    }

    /**
     * Ported from Fl_Input_::handletext(int,int,int,int,int) -- the
     * event handling shared by every concrete subclass (called by
     * fl.input's handle() for whatever it doesn't handle itself).
     * Simplified vs FLTK: no drag-and-drop (FL_DND_* -- not ported
     * anywhere in this port, see fl.platform_x11's skip-list) and no
     * IME marked-text/setSpot() (see the module comment).
     */
    protected int handletext(Event event, int X, int Y, int W, int H)
    {
        switch (event)
        {
        case Event.enter:
        case Event.move:
            if (activeR() && window() !is null) window().cursor(Cursor.insert);
            return 1;

        case Event.leave:
            if (activeR() && window() !is null) window().cursor(Cursor.default_);
            return 1;

        case Event.focus:
            if (mark_ == position_)
                minimalUpdate(size() + 1);
            else
                minimalUpdate(mark_, position_);
            return 1;

        case Event.unfocus:
            if (activeR() && window() !is null) window().cursor(Cursor.default_);
            if (mark_ == position_)
            {
                if (!(damage() & damageExpose)) { minimalUpdate(position_); eraseCursorOnly_ = true; }
            }
            else
                minimalUpdate(mark_, position_);
            goto case Event.hide;

        case Event.hide:
            resetSpot();
            if (!readonly() && (when() & whenRelease))
                maybeDoCallback(CallbackReason.lostFocus);
            return 1;

        case Event.push:
            if (activeR() && window() !is null) window().cursor(Cursor.insert);
            handleMouse(X, Y, W, H, fl.core.eventShift());
            if (fl.core.focus() !is this)
            {
                fl.core.focus(this);
                handle(Event.focus);
            }
            return 1;

        case Event.drag:
            handleMouse(X, Y, W, H, true);
            return 1;

        case Event.release:
            copy(0);
            return 1;

        case Event.paste:
        {
            if (readonly())
            {
                fl.core.beep(Beep.error);
                return 1;
            }

            string t = fl.core.eventText();
            if (t.length == 0) return 1;

            size_t tend = t.length;
            if (inputType() != inputMultiline)
                while (tend > 0 && isWhite(t[tend - 1])) tend--;
            if (tend == 0) return 1;
            t = t[0 .. tend];

            if (inputType() == inputInt)
            {
                size_t i = 0;
                while (i < t.length && isWhite(t[i])) i++;
                size_t p = i;
                if (p < t.length && (t[p] == '+' || t[p] == '-')) p++;
                if (p + 1 < t.length && t[p] == '0' && t[p + 1] == 'x')
                {
                    p += 2;
                    while (p < t.length && isHexDigit(t[p])) p++;
                }
                else
                {
                    while (p < t.length && isDigit(t[p])) p++;
                }
                if (p < t.length)
                {
                    fl.core.beep(Beep.error);
                    return 1;
                }
                return replace(0, size(), t[i .. $]);
            }
            else if (inputType() == inputFloat)
            {
                size_t i = 0;
                while (i < t.length && isWhite(t[i])) i++;
                size_t p = i;
                if (p < t.length && (t[p] == '+' || t[p] == '-')) p++;
                while (p < t.length && isDigit(t[p])) p++;
                if (p < t.length && t[p] == '.')
                {
                    p++;
                    while (p < t.length && isDigit(t[p])) p++;
                    if (p < t.length && (t[p] == 'e' || t[p] == 'E'))
                    {
                        p++;
                        if (p < t.length && (t[p] == '+' || t[p] == '-')) p++;
                        while (p < t.length && isDigit(t[p])) p++;
                    }
                }
                if (p < t.length)
                {
                    fl.core.beep(Beep.error);
                    return 1;
                }
                return replace(0, size(), t[i .. $]);
            }
            return replace(insertPosition(), mark(), t);
        }

        case Event.shortcut:
            if (!(shortcut_ != 0 ? fl.core.testShortcut(shortcut_) : testShortcut()))
                return 0;
            if (fl.core.visibleFocus() && handle(Event.focus))
            {
                fl.core.focus(this);
                return 1;
            }
            goto default;

        default:
            return 0;
        }
    }

    // -------------------------------------------------------------
    // Public accessors (FL/Fl_Input_.H's inline definitions)
    // -------------------------------------------------------------

    override void resize(int x, int y, int w, int h)
    {
        if (w != this.w()) xscroll_ = 0;
        if (h != this.h()) yscroll_ = 0;
        super.resize(x, y, w, h);
    }

    /// Ported from Fl_Input_::static_value(const char*,int).
    int staticValue(string str, int len)
    {
        clearChanged();
        undo_ = UndoAction.init;
        undoList_ = null;
        redoList_ = null;
        if (str == value_ && len == size()) return 0;
        if (len)
        {
            if (xscroll_ || yscroll_)
            {
                xscroll_ = yscroll_ = 0;
                minimalUpdate(0);
            }
            else
            {
                int i = 0;
                int oldSize = size();
                for (; i < oldSize && i < len && str[i] == value_[i]; i++) {}
                if (i == oldSize && i == len) return 0;
                minimalUpdate(i);
            }
            value_ = str[0 .. len];
        }
        else
        {
            if (size() == 0) return 0;
            value_ = "";
            xscroll_ = yscroll_ = 0;
            minimalUpdate(0);
        }
        insertPosition(readonly() ? 0 : size());
        return 1;
    }

    int staticValue(string str) { return staticValue(str, str is null ? 0 : cast(int) str.length); }

    /// D `string` is already immutable+GC-owned, so unlike FLTK
    /// there's no separate "copy into an owned buffer" step -- value()
    /// and staticValue() are the same operation here. See the module
    /// comment.
    int value(string str, int len) { return staticValue(str, len); }
    int value(string str) { return staticValue(str); }

    int value(int v)
    {
        import std.conv : to;
        return value(to!string(v));
    }

    int value(double v)
    {
        import std.format : format;
        return value(format("%g", v));
    }

    string value() const { return value_; }

    /// Ported from Fl_Input_::ivalue() -- a lenient atoi()-style parse
    /// (leading whitespace/sign, then digits; anything else is simply
    /// not consumed), not the strict std.conv.to!int.
    int ivalue() const
    {
        size_t i = 0;
        while (i < value_.length && isWhite(value_[i])) i++;
        bool neg = false;
        if (i < value_.length && (value_[i] == '+' || value_[i] == '-'))
        {
            neg = value_[i] == '-';
            i++;
        }
        long result = 0;
        while (i < value_.length && isDigit(value_[i]))
        {
            result = result * 10 + (value_[i] - '0');
            i++;
        }
        return cast(int)(neg ? -result : result);
    }

    /// The text shown, in a lighter color, while the input is empty.
    string placeholder() const { return placeholder_; }
    /// Sets the placeholder text shown while the input is empty.
    void placeholder(string text) { placeholder_ = text; }

    /// Ported from Fl_Input_::dvalue() -- a lenient atof()-style parse.
    double dvalue() const
    {
        import std.conv : parse;
        size_t i = 0;
        while (i < value_.length && isWhite(value_[i])) i++;
        auto s = value_[i .. $];
        try
        {
            return parse!double(s);
        }
        catch (Exception)
        {
            return 0.0;
        }
    }

    int size() const { return cast(int) value_.length; }

    int maximumSize() const { return maximumSize_; }
    void maximumSize(int m) { maximumSize_ = m; }

    int shortcut() const { return shortcut_; }
    void shortcut(int s) { shortcut_ = s; }

    Font textfont() const { return textfont_; }
    void textfont(Font s) { textfont_ = s; }

    Fontsize textsize() const { return textsize_; }
    void textsize(Fontsize s) { textsize_ = s; }

    Color textcolor() const { return textcolor_; }
    void textcolor(Color n) { textcolor_ = n; }

    Color cursorColor() const { return cursorColor_; }
    void cursorColor(Color n) { cursorColor_ = n; }

    /// Returns 0, inputFloat, inputInt, inputMultiline, or inputSecret
    /// -- type() masked to just the input-kind bits (readonly()/wrap()
    /// are separate bits, tested independently).
    InputType inputType() const { return type() & inputTypeMask; }
    void inputType(InputType t) { type(cast(ubyte)(t | readonly())); }

    /// Returns the raw masked bit (0 or inputReadonly), not a plain
    /// bool -- inputType(int)'s `t | readonly()` composition above
    /// relies on that exact value, matching FLTK's `int` return.
    InputType readonly() const { return type() & inputReadonly; }
    void readonly(bool b)
    {
        if (b) type(cast(ubyte)(type() | inputReadonly));
        else type(cast(ubyte)(type() & ~inputReadonly));
    }

    InputType wrap() const { return type() & inputWrap; }
    void wrap(bool b)
    {
        if (b) type(cast(ubyte)(type() | inputWrap));
        else type(cast(ubyte)(type() & ~inputWrap));
    }

    void tabNav(bool val) { tabNav_ = val; }
    bool tabNav() const { return tabNav_; }

    protected int xscroll() const { return xscroll_; }
    protected int yscroll() const { return yscroll_; }
    protected void yscroll(int yOffset) { yscroll_ = yOffset; damage(damageExpose); }

    /// Ported from Fl_Input_::linesPerPage().
    protected int linesPerPage()
    {
        int n = 1;
        if (inputType() == inputMultiline)
        {
            fldraw.fl_font(textfont(), textsize());
            n = h() / fldraw.height();
            if (n <= 0) n = 1;
        }
        return n;
    }
}

// ===========================================================================
// Unit tests
// ===========================================================================

// Input_ is a virtual base class exactly like FLTK's Fl_Input_ ("has
// all the same interfaces, but lacks the handle() and draw() method") --
// draw() stays abstract (inherited from Widget) since nothing here needs
// real pixels; a trivial no-op override is all these tests need to be
// able to construct one.
version (unittest)
private class TestInput : Input_
{
    this(int x, int y, int w, int h, string label = null) { super(x, y, w, h, label); }
    override void draw() {}
}

unittest
{
    import fl.group : FlGroup;

    FlGroup.current(null);
    fl.core.resetForTest();

    auto inp = new TestInput(0, 0, 100, 20);
    assert(inp.box() == Boxtype.downBox);
    assert(inp.value() == "");
    assert(inp.size() == 0);

    inp.value("hello");
    assert(inp.value() == "hello");
    assert(inp.size() == 5);
    assert(inp.insertPosition() == 5); // value() moves cursor to the end

    inp.insertPosition(0);
    assert(inp.insertPosition() == 0);

    inp.insertPosition(2, 4);
    assert(inp.insertPosition() == 2);
    assert(inp.mark() == 4);

    FlGroup.current(null);
    fl.core.resetForTest();
}

unittest
{
    // replace()/undo()/redo() round-trip.
    import fl.group : FlGroup;

    FlGroup.current(null);
    fl.core.resetForTest();

    auto inp = new TestInput(0, 0, 100, 20);
    inp.value("hello world");
    assert(inp.replace(5, 11, "!") == 1);
    assert(inp.value() == "hello!");

    assert(inp.canUndo());
    assert(inp.undo() == 1);
    assert(inp.value() == "hello world");

    assert(inp.canRedo());
    assert(inp.redo() == 1);
    assert(inp.value() == "hello!");

    FlGroup.current(null);
    fl.core.resetForTest();
}

unittest
{
    // cut()/insert()/copy() against the in-process clipboard.
    import fl.group : FlGroup;

    FlGroup.current(null);
    fl.core.resetForTest();

    auto inp = new TestInput(0, 0, 100, 20);
    inp.value("hello world");
    inp.insertPosition(0, 5); // select "hello"
    assert(inp.copy(1) == 1);

    assert(inp.cut() == 1);
    assert(inp.value() == " world");

    inp.insertPosition(0);
    assert(inp.insert("hello") == 1);
    assert(inp.value() == "hello world");

    FlGroup.current(null);
    fl.core.resetForTest();
}

unittest
{
    // ivalue()/dvalue() lenient parsing, and maximumSize() clamping.
    import fl.group : FlGroup;

    FlGroup.current(null);
    fl.core.resetForTest();

    auto inp = new TestInput(0, 0, 100, 20);
    inp.value("  -42abc");
    assert(inp.ivalue() == -42);

    inp.value("3.5e2 trailing");
    assert(inp.dvalue() == 3.5e2);

    inp.maximumSize(3);
    inp.value("");
    inp.insert("hello");
    assert(inp.value() == "hel"); // clamped to 3 characters

    FlGroup.current(null);
    fl.core.resetForTest();
}

unittest
{
    // wordStart()/wordEnd()/lineStart()/lineEnd() on a multiline value.
    import fl.group : FlGroup;

    FlGroup.current(null);
    fl.core.resetForTest();

    auto inp = new TestInput(0, 0, 100, 60);
    inp.type(inputMultiline);
    inp.value("foo bar\nbaz");

    assert(inp.wordEnd(0) == 3);   // end of "foo"
    assert(inp.wordStart(7) == 4); // start of "bar"

    assert(inp.lineStart(5) == 0);
    assert(inp.lineEnd(5) == 7);
    assert(inp.lineStart(9) == 8); // start of "baz"
    assert(inp.lineEnd(9) == 11);

    FlGroup.current(null);
    fl.core.resetForTest();
}
