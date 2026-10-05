/*
 * Ported from FL/Fl_Text_Display.H + src/Fl_Text_Display.cxx (FLTK 1.5.0). The widget that visually displays an
 * `Fl_Text_Buffer` -> `TextBuffer`: line-start/line-end/word-wrap
 * calculation, vertical+horizontal scrolling (via two `Fl_Scrollbar`s),
 * cursor positioning/blinking, selection highlighting, a secondary
 * "style buffer" for syntax highlighting, mouse/keyboard text
 * navigation, and text-position <-> (row, column) <-> (x, y pixel)
 * conversions. Subclasses `FlGroup`.
 *
 * This is the largest single module ported in this project so far
 * (FLTK's .cxx alone is 4481 lines); both the header and the full
 * implementation were read in full before writing any of this, not
 * just skimmed.
 *
 * Faithfully ported: buffer attachment/modify-callback bookkeeping,
 * highlight_data()/position_style() (the style-table resolution
 * logic), wrap_mode() and the whole continuous-wrap line-counting
 * engine (wrapped_line_counter()/find_wrap_range()/
 * measure_deleted_lines()/find_line_end()/wrap_uses_character()),
 * line-start/line-end/count-lines/skip-lines/rewind-lines (wrap-aware
 * versions of the TextBuffer equivalents), calc_line_starts()/
 * offset_line_starts()/update_line_starts() (the mLineStarts[]
 * bookkeeping), scroll()/scroll_()/recalc_display() (scrollbar
 * min/max/value sync, scrollbar visibility decisions, text-area
 * layout), position<->(row,col)<->(x,y) conversions (position_to_xy(),
 * xy_to_position(), xy_to_rowcol(), position_to_line(),
 * position_to_linecol()), cursor movement (move_up/move_down/move_left/
 * move_right, insert_position(), display_insert()), next_word()/
 * previous_word(), insert()/overstrike(), and handle_vline() -- the
 * "universal pixel machine" that both measures (GET_WIDTH/FIND_INDEX
 * modes, used everywhere above) and draws (DRAW_LINE mode) a line of
 * text, so it's ported in full rather than split into a "real" and a
 * "stub" half.
 *
 * draw()/draw_text()/draw_range()/draw_vline()/draw_string()/
 * draw_cursor()/clear_rect()/draw_line_numbers() are structurally
 * ported, and draw real text now too: fl.draw gained height()/
 * descent()/width()/a positional 4-arg fl_draw()/clipBox()
 * specifically for this module, originally as placeholders (reusing
 * FLTK's own "6px placeholder" convention, TMPFONTWIDTH, rather
 * than inventing a new one) so this module's layout math would produce
 * *some* deterministic answer before real font metrics existed --
 * height()/descent()/width() are backed by real Xft glyph
 * metrics now (see fl.draw's own module comment), so layout runs on
 * real numbers and draw_string()/draw_line_numbers() paint real
 * glyphs. clipBox() is real now too (fl.draw's real clip-region
 * tracking, see that module's "Clipping" section), so text drawing
 * actually gets clipped to the widget's text area.
 *
 * D-const note: many of FLTK's `const` methods (position_to_line(),
 * string_width(), handle_vline(), count_lines(), ...) are ported here
 * as plain non-const methods. They call into TextBuffer/Scrollbar
 * methods that aren't const-qualified in this port (skip_lines()/
 * rewind_lines() in particular), and D's `const` is transitive -- a
 * const method can only call other const methods through a field of
 * `this` -- so keeping every one of these const would require pushing
 * `const` through a much larger slice of fl.text_buffer/fl.scrollbar's
 * API than this module's scope covers. Only genuinely trivial getters
 * (a single `return field_;`, no external calls) stay `const` here.
 * This has no runtime-observable effect; it only affects what the
 * compiler will let a `const(TextDisplay)` caller do, and nothing in
 * this project constructs one of those yet.
 *
 * - **The right-click Cut/Copy/Paste popup menu** (`handle_rmb()`) is
 *   real, built on `fl.menu_item`/`fl.menu_popup` (same popup
 *   engine `fl.menu_button`/`fl.choice` use) -- see `handleRmb()`'s own
 *   doc comment for exactly what's simplified relative to FLTK
 *   (mainly: no `user_data()`/`argument()` slot to stash the picked
 *   action in, recovered via array-index arithmetic instead).
 * - **The X11 clipboard** (`Fl::copy()`/`Fl::paste()`) is real, via
 *   `fl.core.copy()`/`paste()`, including real X11 selection ownership
 *   (`XSetSelectionOwner()`, not just an in-process buffer -- see that
 *   function's own doc comment). Ctrl+C,
 *   Ctrl+A, and "clicking then releasing without dragging" (which
 *   FLTK also copies the click-selection to the `PRIMARY`
 *   selection) all copy for real. **Drag-and-drop-initiated copies
 *   are real too**, via real XDND (see `fl.core.dnd()`/
 *   `fl.platform_x11.dnd()`'s own rows in `PORTING.md`): dragging out of
 *   an existing selection (`dragType_ == dragStartDnd`, set by `FL_PUSH`
 *   landing inside one) copies the selection text via `fl.core.copy()`
 *   and starts a real XDND drag via `fl.core.dnd()`, gated on
 *   `fl.core.dndTextOps()` (`Fl::dnd_text_ops()`, the
 *   `FL/core/options.H` option) exactly like FLTK's
 *   own `FL_DRAG` handler.
 * - **The smooth "auto-scroll while dragging outside the text area"
 *   timer** (`scroll_timer_cb()`) is ported, using `fl.core`'s
 *   timer subsystem, the same one `fl.scrollbar`'s
 *   auto-repeat and `fl.button`'s `simulateKeyAction()` use. DELIBERATE DEVIATION: `scrollDirection_`/
 *   `scrollAmount_`/`scrollX_`/`scrollY_` are per-instance fields here,
 *   not FLTK's shared file-scope statics of the same name.
 *   FLTK's sharing has a confirmed bug (reproduced with a headless
 *   unittest, see FLTK_ISSUES.md): destroying any *other*
 *   `Fl_Text_Display` while a *different* one is mid-drag-scroll zeroes
 *   the shared `scroll_direction` regardless of which instance it
 *   actually belongs to, corrupting the in-progress scroll's
 *   bookkeeping (its real timer keeps firing underneath the now-wrong
 *   flag, and the next `FL_DRAG` event can start a redundant second
 *   timer). Scoping this state per-instance removes the bug outright
 *   and costs nothing -- FLTK's own comment gives no reason the
 *   sharing was intentional beyond "only one drag-scroll happens at a
 *   time," which per-instance fields already guarantee just as well
 *   without the cross-instance-destructor hazard.
 * - **IME / marked-text composition** (`setSpot()`,
 *   `Fl::compose_state`, `Fl::screen_driver()->has_marked_text()`):
 *   real dead-key/CJK composition is ported
 *   (`fl.core.compose()`, `fl.platform_x11`'s XIM support), and
 *   `fl.text_editor`'s own `handleKey()` uses it. **`setSpot()` is
 *   real**: `drawCursor()` calls
 *   `fl.core.setSpot()` with this widget's own live cursor
 *   position whenever it's focused, matching
 *   `Fl_Text_Display::draw_cursor()` exactly -- `fl.platform_x11`
 *   negotiates real `XIMPreeditPosition` support with the input method,
 *   so a CJK/other composing input method (ibus, fcitx, ...) can
 *   position its own floating preedit window at the text cursor
 *   instead of a fixed default location. `draw_string()`'s marked-text
 *   underline stays correctly always-off, since `Fl::compose_state`
 *   never becomes non-zero on X11 even in real FLTK -- not a
 *   port gap, see `fl.core.compose()`'s own doc comment (and
 *   `has_marked_text()`'s own base-class default of `0`, never
 *   overridden by FLTK's own real X11 driver either).
 * - **The printer-surface background fill** in `draw()` is real:
 *   `SurfaceDevice.surface() !is null` (this port's own "the display is
 *   `null`" convention, see `fl.image_surface`'s own doc comment) is the
 *   equivalent of FLTK's `Fl_Surface_Device::surface() !=
 *   Fl_Display_Device::display_device()`.
 * - **`Fl_Text_Display(Fl_Text_Buffer&)`** (a `buffer(Fl_Text_Buffer&)`
 *   reference overload that just forwards to the pointer version).
 *   `buffer(TextBuffer)` already takes a class reference in D, so the
 *   second overload FLTK needs purely for C++'s pointer-vs-
 *   reference distinction has no D equivalent to add.
 * - **`highlight_data()`'s `nStyles`/`cbArg` parameters.** `nStyles` is
 *   redundant with `styleTable.length` in D (a slice, unlike C's bare
 *   pointer+length pair FLTK's `const Style_Table_Entry*` needs).
 *   `cbArg` is dropped per CONVENTIONS.md's delegate-over-function-pointer-
 *   plus-`void*` convention: `UnfinishedStyleCb` is a `void
 *   delegate(int)` that can already close over whatever context it
 *   needs.
 *
 * A faithfully-reproduced apparent **FLTK bug** (not fixed here;
 * logged as a candidate in FLTK_ISSUES.md): `wrapped_line_counter()`
 * ends with `*retLines = buf->next_char(*retLines);` when the buffer
 * ends mid-line -- `next_char()` expects a *buffer byte position*, but
 * `*retLines` at that point holds a *line count*, an apparent type
 * confusion (`next_char()` almost certainly meant to just add 1). Ported
 * verbatim (`retLines = buf.nextChar(retLines);`) rather than "fixed" to
 * `retLines + 1`, since faithfully reproducing FLTK's actual
 * behavior -- bugs included -- is this port's whole point; see the
 * function body for the exact spot.
 */
module fl.text_display;

import std.algorithm.comparison : min, max;
import std.format : format;
import core.memory : GC;

import fl.enumerations;
import fl.rect : Rect;
import fl.widget : Widget;
import fl.group : FlGroup;
import fl.scrollbar : Scrollbar;
import fl.slider : horSlider;
import fl.text_buffer : TextBuffer, TextSelection;
import fl.draw;
import fl.core;
import fl.menu_item : MenuItem;
import fl.menu_popup;
import fl.image_surface : SurfaceDevice;

/// Translatable strings for handleRmb()'s cut/copy/paste popup.
/// FLTK keeps these as static members of the concrete `Fl_Input`
/// class (`Fl_Input::cut_menu_text`/etc.), shared with `Fl_Input`'s own
/// right-click menu. `fl.input`'s own `handleRmb()` now ports that same
/// popup and has its own real `static string cutMenuText`/etc. class
/// members (matching FLTK's placement) -- rather than reach across
/// to that widget class from here, `fl.text_display` keeps its own
/// plain module-level translatable strings, same convention as
/// `fl.ask`'s `no`/`yes`/etc.
string cutMenuText = "Cut";
string copyMenuText = "Copy"; /// ditto
string pasteMenuText = "Paste"; /// ditto

// ---------------------------------------------------------------------
// Text-area margins (src/Fl_Text_Display.cxx's TOP_MARGIN/BOTTOM_MARGIN/
// LEFT_MARGIN/RIGHT_MARGIN). Left & right must stay >= 3 -- there needs
// to be room for the cursor's overhang, same as FLTK's own comment.
// ---------------------------------------------------------------------
private enum topMargin = 1;
private enum bottomMargin = 1;
private enum leftMargin = 3;
private enum rightMargin = 3;

/// FLTK's `NO_HINT` sentinel for mCursorToHint.
private enum noHint = -1;

/// FLTK's own placeholder for real font-metrics-based character
/// width (`#define TMPFONTWIDTH 6 // CET - FIXME`), used by
/// draw_cursor()/xy_to_rowcol() when a *fixed pixel* width is needed
/// rather than a measured one. Kept local to this module, matching
/// FLTK's own file-local `#define`.
private enum tmpFontWidth = 6;


// ---------------------------------------------------------------------
// Style masks (or'd into the `style` int handle_vline()/draw_string()/
// position_style() pass around: low byte is a style-table index,
// high bits are drawing-mode flags). Open/combinable bitmask, so this
// stays a D `alias` + manifest constants per CONVENTIONS.md, like Align/
// Color/Damage.
// ---------------------------------------------------------------------
alias StyleFlags = uint;

enum : StyleFlags
{
    styleFillMask      = 0x0100,
    styleSecondaryMask = 0x0200,
    stylePrimaryMask   = 0x0400,
    styleHighlightMask = 0x0800,
    styleBgOnlyMask    = 0x1000,
    styleTextOnlyMask  = 0x2000,
    styleLookupMask    = 0x00ff,
}

/// Attribute flags in `StyleTableEntry.attr` (FLTK's anonymous enum
/// `ATTR_BGCOLOR`/etc in the header). Also an open bitmask.
enum : uint
{
    attrBgcolor       = 0x0001,
    attrBgcolorExt_   = 0x0002, /// internal use, matches FLTK's own trailing-underscore name
    attrBgcolorExt    = 0x0003,
    attrUnderline     = 0x0004,
    attrGrammar       = 0x0008,
    attrSpelling      = 0x000C,
    attrStrikeThrough = 0x0010,
    attrLinesMask     = 0x001C,
}

/// Text-cursor shapes (FLTK's anonymous enum: NORMAL_CURSOR..
/// SIMPLE_CURSOR). A closed tag set -> real D enum per CONVENTIONS.md.
enum CursorStyle
{
    normalCursor, /// I-beam
    caretCursor,  /// caret under the text
    dimCursor,    /// dim I-beam
    blockCursor,  /// unfilled box under the current character
    heavyCursor,  /// thick I-beam
    simpleCursor, /// as Fl_Input's cursor
}

/// The character position is the left edge of a character, whereas the
/// cursor is thought to be between the centers of two consecutive
/// characters (FLTK's `CURSOR_POS`/`CHARACTER_POS`).
enum PositionType
{
    cursorPos,
    characterPos,
}

/// Drag types -- match `fl.core.eventClicks()` so that a single click
/// selects by character, double-click by word, triple-click by line
/// (FLTK's `DRAG_NONE`..`DRAG_LINE`). Stored in `dragType_` as a
/// plain `int` FLTK (it's assigned directly from `Fl::event_clicks()`,
/// an `int`), but exposed here as a real enum since every comparison
/// site names one of these five values.
enum DragType : int
{
    dragNone     = -2,
    dragStartDnd = -1,
    dragChar     = 0,
    dragWord     = 1,
    dragLine     = 2,
}

/// Wrap modes, passed to wrapMode() (FLTK's `WRAP_NONE`..
/// `WRAP_AT_BOUNDS`).
enum WrapMode
{
    wrapNone,     /// don't wrap text at all
    wrapAtColumn, /// wrap text at the given text column
    wrapAtPixel,  /// wrap text at a pixel position
    wrapAtBounds, /// wrap text so that it fits into the widget width
}

/// Internal drawing-mode selector for handleVline() (FLTK's
/// anonymous `DRAW_LINE`/`FIND_INDEX`/`FIND_INDEX_FROM_ZERO`/
/// `GET_WIDTH`/`FIND_CURSOR_INDEX` enum).
private enum HandleMode
{
    drawLine,
    findIndex,
    findIndexFromZero,
    getWidth,
    findCursorIndex,
}

/// Called when position_style() encounters `unfinishedStyle` in the
/// style buffer, so the caller can lazily re-parse/re-highlight that
/// region on the fly. Matches FLTK's `Unfinished_Style_Cb` minus
/// the `void* cbArg` slot -- per CONVENTIONS.md's delegate convention, a
/// caller needing context just captures it in the delegate.
alias UnfinishedStyleCb = void delegate(int pos);

/**
 * Associates a color/font/size (and further attributes) with a style-
 * buffer entry. Ported verbatim from `Style_Table_Entry`
 * (`FL/Fl_Text_Display.H`) -> `StyleTableEntry`. Set via
 * `TextDisplay.highlightData()`.
 */
struct StyleTableEntry
{
    Color color;      /// text color
    Font font;        /// text font
    Fontsize size;     /// text font size
    uint attr;        /// further attributes, see `attrBgcolor` etc.
    Color bgcolor;    /// background color, if `attrBgcolor`/`attrBgcolorExt` set
}

/// Ported from the private file-static `countlines()` (counts '\n' in a
/// string) in Fl_Text_Display.cxx.
private int countlines(const(char)[] s)
{
    int n = 0;
    foreach (c; s)
        if (c == '\n')
            n++;
    return n;
}

/// Ported from the private file-static `fl_utf8len1()` use inside
/// Fl_Text_Display.cxx. Duplicated (rather than exposed) from
/// fl.text_buffer's own private `utf8Len1()` to keep that module's
/// public surface unchanged -- out of scope for this task. Returns the
/// byte length of the UTF-8 sequence starting with c, or 1 if c can't
/// start a valid sequence (so a scan can always advance).
private int utf8Len1(char c)
{
    ubyte u = cast(ubyte) c;
    if ((u & 0x80) == 0) return 1;
    if ((u & 0xe0) == 0xc0) return 2;
    if ((u & 0xf0) == 0xe0) return 3;
    if ((u & 0xf8) == 0xf0) return 4;
    return 1;
}

/**
 * Ported from Fl_Text_Display -> TextDisplay. See the module comment
 * for exactly what's faithfully ported vs. structurally-ported-but-
 * visually-inert vs. deliberately skipped.
 */
class TextDisplay : FlGroup
{
    private
    {
        int damageRange1Start_ = -1, damageRange1End_ = -1;
        int damageRange2Start_ = -1, damageRange2End_ = -1;

        int cursorPos_;
        bool cursorOn_;
        int cursorOldY_ = -100;
        int cursorToHint_ = noHint;
        CursorStyle cursorStyle_ = CursorStyle.normalCursor;
        int cursorPreferredXPos_ = -1;

        int nBufferLines_;

        TextBuffer buffer_;
        TextBuffer styleBuffer_;

        int firstChar_, lastChar_;

        bool continuousWrap_;
        int wrapMarginPix_;

        int absTopLineNum_ = 1;
        bool needAbsTopLineNum_;

        int topLineNumHint_ = 1;
        int horizOffsetHint_;

        int nStyles_;
        const(StyleTableEntry)[] styleTable_;
        char unfinishedStyle_;
        UnfinishedStyleCb unfinishedHighlightCB_;

        int maxsize_;

        bool suppressResync_;
        int nLinesDeleted_;

        double columnScale_ = 0;

        bool displayNeedsRecalc_;

        Color cursorColor_ = foregroundColor;

        Scrollbar hScrollBar_;
        Scrollbar vScrollBar_;
        int scrollbarWidth_;
        Align scrollbarAlign_ = alignBottomRight;

        bool displayInsertPositionHint_;

        int shortcut_;

        Font textfont_ = helvetica;
        Fontsize textsize_ = 14; // set to fl.enumerations.normalSize in the ctor body (see below)
        Color textcolor_ = foregroundColor;
        Color grammarUnderlineColor_ = blue;
        Color spellingUnderlineColor_ = red;
        Color secondarySelectionColor_ = gray;

        int lineNumLeft_;   // FLTK: unused
        int lineNumWidth_;

        Font linenumberFont_ = helvetica;
        Fontsize linenumberSize_ = 14; // set to fl.enumerations.normalSize in the ctor body (see below)
        Color linenumberFgcolor_ = inactiveColor;
        Color linenumberBgcolor_ = cast(Color) 53; // ~90% gray, matching FLTK literal
        Align linenumberAlign_ = alignRight;
        string linenumberFormat_ = "%d";
    }

    // FLTK (`FL/Fl_Text_Display.H`) declares all of these `protected:`
    // specifically so `Fl_Text_Editor` can reach them directly (arrow/page-
    // key navigation math, drag-selection state) -- see kf_move()/
    // kf_ctrl_move()/kf_meta_move() etc. in `src/Fl_Text_Editor.cxx`. D's
    // `private` is module-scoped, not class-scoped, so a subclass in
    // another module (`fl.text_editor`) can't reach a `private` field the
    // way a C++ subclass reaches a `protected` one -- same reasoning
    // already applied to flTextDragPrepare()/flTextDragMe() below, and to
    // `Widget`'s `Flag`/`setFlag()`/`clearFlag()` (see that module's own
    // comment). `package(fl)`, not `protected`, is the fix: it grants
    // exactly the same "anywhere in this port" reach `Fl_Text_Editor.cxx`
    // gets from FLTK's `protected:`.
    package(fl)
    {
        int nVisibleLines_ = 1;
        int[] lineStarts_;
        int topLineNum_ = 1;
        int horizOffset_;
        int dragPos_;
        DragType dragType_ = DragType.dragChar;
        bool dragging_;
        Rect textArea_;
    }

    private
    {
        // Drag-auto-scroll state -- see the module comment for why
        // these are per-instance fields rather than FLTK's shared
        // file-scope statics (a confirmed cross-instance corruption
        // bug in FLTK; see FLTK_ISSUES.md).
        int scrollDirection_;
        int scrollAmount_;
        int scrollX_;
        int scrollY_;
    }

    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);

        // FlGroup's ctor already called begin(); constructing the
        // scrollbars here auto-adds them as children, matching
        // FLTK's constructor order exactly.
        hScrollBar_ = new Scrollbar(0, 0, 1, 1);
        hScrollBar_.callback((Widget w2) { hScrollbarCb(cast(Scrollbar) w2); });
        hScrollBar_.type(horSlider);

        vScrollBar_ = new Scrollbar(0, 0, 1, 1);
        vScrollBar_.callback((Widget w2) { vScrollbarCb(cast(Scrollbar) w2); });

        lineStarts_ = new int[](nVisibleLines_);
        lineStarts_[0] = 0;

        // fl.enumerations.normalSize is a mutable module-level global
        // (matching FLTK's own mutable FL_NORMAL_SIZE), so it can't
        // be used as a static field initializer -- set here instead.
        textsize_ = fl.enumerations.normalSize;
        linenumberSize_ = fl.enumerations.normalSize;

        color(background2Color, fl.enumerations.selectionColor);
        box(Boxtype.downFrame);
        shortcutLabel(true);
        needsKeyboard(false);

        end();
    }

    ~this()
    {
        // Safe unconditionally, even during GC-driven finalization --
        // only compares delegate identity and mutates fl.core's own
        // timer-queue bookkeeping, doesn't reach into another GC
        // object's fields (see fl.clock's destructor for the same
        // reasoning).
        if (scrollDirection_)
        {
            fl.core.removeTimeout(&scrollTimerCb);
            scrollDirection_ = 0;
        }

        // See CONVENTIONS.md's GC-finalizer note (and fl.widget.d's ~this()
        // for the established pattern): buffer_ is another GC-managed
        // object, so unregistering our callbacks from it is only safe
        // when this destructor runs deterministically.
        if (!GC.inFinalizer())
        {
            if (buffer_ !is null)
            {
                buffer_.removeModifyCallback(&bufferModifiedCb);
                buffer_.removePredeleteCallback(&bufferPredeleteCb);
            }
        }
    }

    /// The `window()->cursor(...)` calls in the `Event.enter`/`move`/
    /// `leave`/`hide`/`push`/`unfocus` cases (switching to an I-beam
    /// cursor over the text area, back to the default arrow elsewhere)
    /// are real, backed by a real `Widget.window()`.
    override int handle(Event event)
    {
        if (buffer_ is null) return 0;

        if (!fl.core.eventInside(textArea_.x, textArea_.y, textArea_.w, textArea_.h)
            && !dragging_
            && event != Event.leave && event != Event.enter && event != Event.move
            && event != Event.focus && event != Event.unfocus
            && event != Event.keyDown && event != Event.keyUp && event != Event.mouseWheel)
            return super.handle(event);

        switch (event)
        {
        case Event.enter:
        case Event.move:
            if (activeR())
            {
                if (fl.core.eventInside(textArea_.x, textArea_.y, textArea_.w, textArea_.h))
                    window().cursor(Cursor.insert);
                else
                    window().cursor(Cursor.default_);
                return 1;
            }
            return 0;

        case Event.leave:
        case Event.hide:
            if (activeR() && window() !is null)
            {
                window().cursor(Cursor.default_);
                return 1;
            }
            return 0;

        case Event.push:
        {
            if (activeR() && window() !is null)
            {
                if (fl.core.eventInside(textArea_.x, textArea_.y, textArea_.w, textArea_.h))
                    window().cursor(Cursor.insert);
                else
                    window().cursor(Cursor.default_);
            }

            if (fl.core.focus() !is this)
            {
                fl.core.focus(this);
                handle(Event.focus);
            }
            if (super.handle(event)) return 1;

            if (fl.core.eventButton() == rightMouse)
            {
                // Base TextDisplay is read-only, so only Copy (2) makes
                // sense out of handleRmb()'s Cut(1)/Copy(2)/Paste(3) --
                // Cut/Paste are already deactivated in the menu itself
                // (the `true` readonly argument), this just performs
                // the actual copy if that's what got picked.
                if (handleRmb(true) == 2)
                {
                    if (buffer_.selected())
                    {
                        string copy = buffer_.selectionText();
                        if (copy.length > 0) fl.core.copy(copy, 1);
                        showInsertPosition();
                    }
                }
                return 1;
            }

            if (fl.core.eventState(stateShift) != 0)
            {
                if (buffer_.primarySelection().selected())
                {
                    int pos = xyToPosition(fl.core.eventX(), fl.core.eventY(), PositionType.cursorPos);
                    flTextDragPrepare(pos, -1, this);
                }
                else
                {
                    dragPos_ = insertPosition();
                }
                return handle(Event.drag);
            }

            dragging_ = true;
            int pos = xyToPosition(fl.core.eventX(), fl.core.eventY(), PositionType.cursorPos);
            dragPos_ = pos;
            if (buffer_.primarySelection().includes(pos))
            {
                dragType_ = DragType.dragStartDnd;
                return 1;
            }
            dragType_ = cast(DragType) fl.core.eventClicks();
            if (dragType_ == DragType.dragChar)
            {
                buffer_.unselect();
            }
            else if (dragType_ == DragType.dragWord)
            {
                buffer_.select(wordStart(pos), wordEnd(pos));
                dragPos_ = wordStart(pos);
            }

            if (buffer_.primarySelection().selected())
                insertPosition(buffer_.primarySelection().end());
            else
                insertPosition(pos);
            showInsertPosition();
            return 1;
        }

        case Event.drag:
        {
            if (dragType_ == DragType.dragNone) return 1;
            if (dragType_ == DragType.dragStartDnd)
            {
                if (!fl.core.eventIsClick() && fl.core.dndTextOps())
                {
                    string copy = buffer_.selectionText();
                    fl.core.copy(copy, 0);
                    fl.core.dnd();
                }
                return 1;
            }

            int X = fl.core.eventX(), Y = fl.core.eventY();
            int pos = insertPosition();
            // Leaving textArea_ starts a repeating timer (see
            // scrollTimerCb()) that scrolls proportionally to how far
            // outside the pointer is, and keeps extending the
            // selection -- ported from FLTK's own comment "if we
            // leave the text_area, we start a timer event that will
            // take care of scrolling and selecting".
            if (Y < textArea_.y)
            {
                scrollX_ = X;
                scrollAmount_ = (Y - textArea_.y) / 5 - 1;
                if (!scrollDirection_) fl.core.addTimeout(0.01, &scrollTimerCb);
                scrollDirection_ = 3;
            }
            else if (Y >= textArea_.y + textArea_.h)
            {
                scrollX_ = X;
                scrollAmount_ = (Y - textArea_.y - textArea_.h) / 5 + 1;
                if (!scrollDirection_) fl.core.addTimeout(0.01, &scrollTimerCb);
                scrollDirection_ = 4;
            }
            else if (X < textArea_.x)
            {
                scrollY_ = Y;
                scrollAmount_ = (X - textArea_.x) / 2 - 1;
                if (!scrollDirection_) fl.core.addTimeout(0.01, &scrollTimerCb);
                scrollDirection_ = 2;
            }
            else if (X >= textArea_.x + textArea_.w)
            {
                scrollY_ = Y;
                scrollAmount_ = (X - textArea_.x - textArea_.w) / 2 + 1;
                if (!scrollDirection_) fl.core.addTimeout(0.01, &scrollTimerCb);
                scrollDirection_ = 1;
            }
            else
            {
                if (scrollDirection_)
                {
                    fl.core.removeTimeout(&scrollTimerCb);
                    scrollDirection_ = 0;
                }
                pos = xyToPosition(X, Y, PositionType.cursorPos);
            }

            flTextDragMe(pos, this);
            return 1;
        }

        case Event.release:
        {
            if (fl.core.eventIsClick() && fl.core.eventClicks() == 0
                && buffer_.primarySelection().includes(dragPos_) && fl.core.eventState(stateShift) == 0)
            {
                buffer_.unselect();
                insertPosition(dragPos_);
                dragType_ = DragType.dragChar;
                return 1;
            }
            else if (fl.core.eventClicks() == cast(int) DragType.dragLine && fl.core.eventButton() == leftMouse)
            {
                buffer_.select(buffer_.lineStart(dragPos_), buffer_.nextChar(buffer_.lineEnd(dragPos_)));
                dragPos_ = lineStart(dragPos_);
                dragType_ = DragType.dragChar;
            }
            else
            {
                dragging_ = false;
                if (scrollDirection_)
                {
                    fl.core.removeTimeout(&scrollTimerCb);
                    scrollDirection_ = 0;
                }
                dragType_ = DragType.dragChar;
            }

            {
                string copy = buffer_.selectionText();
                if (copy.length > 0) fl.core.copy(copy, 0);
            }
            return 1;
        }

        case Event.mouseWheel:
            if (fl.core.eventDy() != 0 && vScrollBar_.visible())
            {
                if (fl.core.eventDy() < 0 && cast(int) vScrollBar_.value() == cast(int) vScrollBar_.minimum()) return 0;
                if (fl.core.eventDy() > 0 && cast(int) vScrollBar_.value() == cast(int) vScrollBar_.maximum()) return 0;
                return vScrollBar_.handle(event);
            }
            else if (fl.core.eventDx() != 0 && hScrollBar_.visible())
            {
                if (fl.core.eventDx() < 0 && cast(int) hScrollBar_.value() == cast(int) hScrollBar_.minimum()) return 0;
                if (fl.core.eventDx() > 0 && cast(int) hScrollBar_.value() == cast(int) hScrollBar_.maximum()) return 0;
                return hScrollBar_.handle(event);
            }
            return 0;

        case Event.unfocus:
        case Event.focus:
        {
            // FLTK's FL_UNFOCUS case has this one extra line before
            // falling through into the shared FL_FOCUS body (no `break`
            // between the two cases in the C++); ported here as a plain
            // guard on which event actually fired, rather than
            // reaching for `goto case`, since the two cases already
            // share one D case-list body.
            if (event == Event.unfocus && activeR() && window() !is null)
                window().cursor(Cursor.default_);

            int start, end;
            if (buffer_.selected() && buffer_.selectionPosition(start, end))
                redisplayRange(start, end);
            if (buffer_.secondarySelected() && buffer_.secondarySelectionPosition(start, end))
                redisplayRange(start, end);
            if (buffer_.highlight() && buffer_.highlightPosition(start, end))
                redisplayRange(start, end);
            return 1;
        }

        case Event.keyDown:
            if (fl.core.eventState(stateCtrl | stateCommand) != 0 && fl.core.eventKey() == 'c')
            {
                if (!buffer_.selected()) return 1;
                string copy = buffer_.selectionText();
                if (copy.length > 0) fl.core.copy(copy, 1);
                return 1;
            }

            if (fl.core.eventState(stateCtrl | stateCommand) != 0 && fl.core.eventKey() == 'a')
            {
                buffer_.select(0, buffer_.length());
                string copy = buffer_.selectionText();
                if (copy.length > 0) fl.core.copy(copy, 0);
                return 1;
            }

            if (vScrollBar_.handle(event)) return 1;
            if (hScrollBar_.handle(event)) return 1;

            break;

        case Event.shortcut:
            if (!(shortcut_ != 0 ? fl.core.testShortcut(cast(uint) shortcut_) : testShortcut()))
                return 0;
            if (fl.core.visibleFocus() && handle(Event.focus))
            {
                fl.core.focus(this);
                return 1;
            }
            break;

        default:
            break;
        }

        return 0;
    }

    // -- Buffer attachment ----------------------------------------------

    /// Attaches buf as the buffer this widget displays, detaching the
    /// previous one (if any) first. Multiple TextDisplays can share one
    /// TextBuffer. The caller remains responsible for the old buffer --
    /// this doesn't delete/destroy it.
    void buffer(TextBuffer buf)
    {
        if (buf is buffer_) return;
        if (buffer_ !is null)
        {
            string deletedText = buffer_.text();
            bufferModifiedCb(0, 0, buffer_.length(), 0, deletedText);
            nBufferLines_ = 0;
            buffer_.removeModifyCallback(&bufferModifiedCb);
            buffer_.removePredeleteCallback(&bufferPredeleteCb);
        }

        buffer_ = buf;
        if (buffer_ !is null)
        {
            buffer_.addModifyCallback(&bufferModifiedCb);
            buffer_.addPredeleteCallback(&bufferPredeleteCb);
            bufferModifiedCb(0, buf.length(), 0, 0, null);
        }

        displayNeedsRecalc();
    }

    /// The attached text buffer, or null.
    TextBuffer buffer() { return buffer_; }
    /// The attached style buffer, or null. See highlightData().
    TextBuffer styleBuffer() { return styleBuffer_; }

    // -- Redisplay / scroll ----------------------------------------------

    /// Marks [startpos, endpos) as needing redraw.
    void redisplayRange(int startpos, int endpos)
    {
        if (damageRange1Start_ == -1 && damageRange1End_ == -1)
        {
            damageRange1Start_ = startpos;
            damageRange1End_ = endpos;
        }
        else if ((startpos >= damageRange1Start_ && startpos <= damageRange1End_)
            || (endpos >= damageRange1Start_ && endpos <= damageRange1End_))
        {
            damageRange1Start_ = min(damageRange1Start_, startpos);
            damageRange1End_ = max(damageRange1End_, endpos);
        }
        else if (damageRange2Start_ == -1 && damageRange2End_ == -1)
        {
            damageRange2Start_ = startpos;
            damageRange2End_ = endpos;
        }
        else
        {
            damageRange2Start_ = min(damageRange2Start_, startpos);
            damageRange2End_ = max(damageRange2End_, endpos);
        }
        damage(damageScroll);
    }

    /// Requests scrolling to topLineNum/horizOffset; actually applied by
    /// the next recalcDisplay() (deferred, same as FLTK).
    void scroll(int topLineNum, int horizOffset)
    {
        topLineNumHint_ = topLineNum;
        horizOffsetHint_ = horizOffset;
        displayNeedsRecalc();
    }

    /// Ported from Fl_Text_Display::scroll_timer_cb(). Fires while the
    /// mouse is being dragged outside textArea_ (see the Event.drag
    /// case in handle()): scrolls proportionally to how far outside
    /// the pointer is, extends the selection to the resulting edge
    /// position, and reschedules itself every 0.1s for as long as
    /// scrollDirection_ says a direction is still active.
    private void scrollTimerCb()
    {
        int pos;
        switch (scrollDirection_)
        {
        case 1: // mouse is to the right, scroll left
            scroll(topLineNum_, horizOffset_ + scrollAmount_);
            pos = xyToPosition(textArea_.x + textArea_.w, scrollY_, PositionType.cursorPos);
            break;
        case 2: // mouse is to the left, scroll right
            scroll(topLineNum_, horizOffset_ + scrollAmount_);
            pos = xyToPosition(textArea_.x, scrollY_, PositionType.cursorPos);
            break;
        case 3: // mouse is above, scroll down
            scroll(topLineNum_ + scrollAmount_, horizOffset_);
            pos = xyToPosition(scrollX_, textArea_.y, PositionType.cursorPos);
            break;
        case 4: // mouse is below, scroll up
            scroll(topLineNum_ + scrollAmount_, horizOffset_);
            pos = xyToPosition(scrollX_, textArea_.y + textArea_.h, PositionType.cursorPos);
            break;
        default:
            return;
        }
        flTextDragMe(pos, this);
        fl.core.repeatTimeout(0.1, &scrollTimerCb);
    }

    // -- Insert / overstrike ----------------------------------------------

    /// Inserts text at the current cursor position, then moves the
    /// cursor past it.
    void insert(const(char)[] text)
    {
        int pos = cursorPos_;
        cursorToHint_ = pos + cast(int) text.length;
        buffer_.insert(pos, text);
        cursorToHint_ = noHint;
    }

    /// Replaces text at the current cursor position (overwrite mode),
    /// padding with spaces if characters with visual width (e.g. tabs)
    /// were only partially consumed.
    void overstrike(const(char)[] text)
    {
        int startPos = cursorPos_;
        int lineStartPos = buffer_.lineStart(startPos);
        int textLen = cast(int) text.length;

        int startIndent = buffer_.countDisplayedCharacters(lineStartPos, startPos);
        int indent = startIndent;
        {
            size_t ci = 0;
            while (ci < text.length) { indent++; ci += utf8Len1(text[ci]); }
        }
        int endIndent = indent;

        indent = startIndent;
        int p = startPos;
        string paddedText;
        bool padded = false;
        for (;;)
        {
            if (p == buffer_.length()) break;
            uint ch = buffer_.charAt(p);
            if (ch == '\n') break;
            indent++;
            if (indent == endIndent) { p = buffer_.nextChar(p); break; }
            else if (indent > endIndent)
            {
                if (ch != '\t')
                {
                    p = buffer_.nextChar(p);
                    char[] buf = text.dup;
                    foreach (i; 0 .. indent - endIndent) buf ~= ' ';
                    paddedText = cast(string) buf;
                    padded = true;
                }
                break;
            }
        }
        int endPos = p;

        cursorToHint_ = startPos + textLen;
        buffer_.replace(startPos, endPos, padded ? paddedText : text);
        cursorToHint_ = noHint;
    }

    // -- Cursor position ---------------------------------------------------

    /// Moves the insert cursor to newPos (clamped into the buffer).
    void insertPosition(int newPos)
    {
        if (newPos == cursorPos_) return;
        if (newPos < 0) newPos = 0;
        if (buffer_ !is null && newPos > buffer_.length()) newPos = buffer_.length();

        cursorPreferredXPos_ = -1;

        if (buffer_ !is null)
            redisplayRange(buffer_.prevCharClipped(cursorPos_), buffer_.nextChar(cursorPos_));

        cursorPos_ = newPos;

        if (buffer_ !is null)
            redisplayRange(buffer_.prevCharClipped(cursorPos_), buffer_.nextChar(cursorPos_));
    }

    /// Byte offset of the insert cursor.
    int insertPosition() const { return cursorPos_; }

    /// Translates pos to a pixel position at the top-left of where its
    /// cursor would be drawn. Returns false (with X=Y=0) if pos is
    /// vertically out of view.
    bool positionToXy(int pos, out int X, out int Y)
    {
        if (pos < firstChar_ || (pos > lastChar_ && !emptyVlines()) || pos > buffer_.length())
        {
            X = 0; Y = 0;
            return false;
        }

        int visLineNum;
        if (!positionToLine(pos, visLineNum) || visLineNum < 0 || visLineNum > nBufferLines_)
        {
            X = 0; Y = 0;
            return false;
        }

        int fontHeight = maxsize_;
        Y = textArea_.y + visLineNum * fontHeight;

        int lineStartPos = lineStarts_[visLineNum];
        if (lineStartPos == -1)
        {
            X = textArea_.x - horizOffset_;
            return true;
        }
        X = textArea_.x + handleVline(HandleMode.getWidth, lineStartPos, pos - lineStartPos, 0, 0, 0, 0, 0, 0)
            - horizOffset_;
        return true;
    }

    /// True if pixel position (x,y) falls inside the primary selection.
    bool inSelection(int X, int Y)
    {
        int pos = xyToPosition(X, Y, PositionType.characterPos);
        return buffer_.primarySelection().includes(pos);
    }

    /// Scrolls (deferred, via the next recalcDisplay()) to bring the
    /// insert cursor into view.
    void showInsertPosition()
    {
        displayInsertPositionHint_ = true;
        displayNeedsRecalc();
    }

    // -- Cursor movement ---------------------------------------------------

    /// Moves the cursor right one character. Returns false at the end
    /// of the buffer.
    bool moveRight()
    {
        if (cursorPos_ >= buffer_.length()) return false;
        insertPosition(buffer_.nextChar(insertPosition()));
        return true;
    }

    /// Moves the cursor left one character. Returns false at the start
    /// of the buffer.
    bool moveLeft()
    {
        if (cursorPos_ <= 0) return false;
        insertPosition(buffer_.prevCharClipped(insertPosition()));
        return true;
    }

    /// Moves the cursor up one (possibly wrapped) line, preserving its
    /// preferred column. Returns false at the start of the buffer.
    bool moveUp()
    {
        int lineStartPos, xPos, prevLineStartPos, newPos, visLineNum;

        if (positionToLine(cursorPos_, visLineNum))
            lineStartPos = lineStarts_[visLineNum];
        else
        {
            lineStartPos = lineStart(cursorPos_);
            visLineNum = -1;
        }
        if (lineStartPos == 0) return false;

        if (cursorPreferredXPos_ >= 0)
            xPos = cursorPreferredXPos_;
        else
            xPos = handleVline(HandleMode.getWidth, lineStartPos, cursorPos_ - lineStartPos, 0, 0, 0, 0, 0, int.max);

        if (visLineNum != -1 && visLineNum != 0)
            prevLineStartPos = lineStarts_[visLineNum - 1];
        else
            prevLineStartPos = rewindLines(lineStartPos, 1);

        int lineEndPos = lineEnd(prevLineStartPos, true);
        newPos = handleVline(HandleMode.findIndexFromZero, prevLineStartPos, lineEndPos - prevLineStartPos,
            0, 0, 0, 0, 0, xPos);

        insertPosition(newPos);
        cursorPreferredXPos_ = xPos;
        return true;
    }

    /// Moves the cursor down one (possibly wrapped) line, preserving
    /// its preferred column. Returns false at the end of the buffer.
    bool moveDown()
    {
        int lineStartPos, xPos, newPos, visLineNum;

        if (cursorPos_ == buffer_.length()) return false;

        if (positionToLine(cursorPos_, visLineNum))
            lineStartPos = lineStarts_[visLineNum];
        else
        {
            lineStartPos = lineStart(cursorPos_);
            visLineNum = -1;
        }
        if (cursorPreferredXPos_ >= 0)
            xPos = cursorPreferredXPos_;
        else
            xPos = handleVline(HandleMode.getWidth, lineStartPos, cursorPos_ - lineStartPos, 0, 0, 0, 0, 0, int.max);

        int nextLineStartPos = skipLines(lineStartPos, 1, true);
        int lineEndPos = lineEnd(nextLineStartPos, true);
        newPos = handleVline(HandleMode.findIndexFromZero, nextLineStartPos, lineEndPos - nextLineStartPos,
            0, 0, 0, 0, 0, xPos);

        insertPosition(newPos);
        cursorPreferredXPos_ = xPos;
        return true;
    }

    // -- Line-aware navigation (wrap-aware TextBuffer equivalents) -------

    /// Same as buffer().countLines(), but wrap-aware. Pass
    /// startPosIsLineStart=true when the caller already knows startPos
    /// is at a line start, to skip an extra scan-back.
    int countLines(int startPos, int endPos, bool startPosIsLineStart)
    {
        if (!continuousWrap_) return buffer_.countLines(startPos, endPos);

        int retLines, retPos, retLineStart, retLineEnd;

        if (buffer_.length() > 16384)
        {
            int nLines = 0;
            int firstVisibleChar = buffer_.rewindLines(firstChar_, 3);
            int lastVisibleChar = buffer_.skipLines(lastChar_, 3);
            if (columnScale_ == 0.0) xToCol(1.0);
            int avgCharsPerLine = wrapMarginPix_;
            if (!avgCharsPerLine) avgCharsPerLine = textArea_.w;
            avgCharsPerLine = cast(int)(avgCharsPerLine / columnScale_) + 1;

            if (startPos < firstVisibleChar)
            {
                int tmpEnd = endPos < firstVisibleChar ? endPos : firstVisibleChar;
                nLines += buffer_.estimateLines(startPos, tmpEnd, avgCharsPerLine);
                startPos = tmpEnd;
            }
            if (startPos < endPos && startPos < lastChar_)
            {
                int tmpEnd = endPos < lastVisibleChar ? endPos : lastVisibleChar;
                wrappedLineCounter(buffer_, startPos, tmpEnd, int.max, startPosIsLineStart, 0,
                    retPos, retLines, retLineStart, retLineEnd);
                nLines += retLines;
                startPos = tmpEnd;
            }
            if (startPos < endPos && startPos >= lastVisibleChar)
                nLines += buffer_.estimateLines(startPos, endPos, avgCharsPerLine);
            return nLines;
        }
        else
        {
            wrappedLineCounter(buffer_, startPos, endPos, int.max, startPosIsLineStart, 0,
                retPos, retLines, retLineStart, retLineEnd);
            return retLines;
        }
    }

    /// Same as buffer().lineStart(pos), but wrap-aware: returns the
    /// character after the last wrap point rather than the last '\n'.
    int lineStart(int pos)
    {
        if (!continuousWrap_) return buffer_.lineStart(pos);
        int retLines, retPos, retLineStart, retLineEnd;
        wrappedLineCounter(buffer_, buffer_.lineStart(pos), pos, int.max, true, 0,
            retPos, retLines, retLineStart, retLineEnd);
        return retLineStart;
    }

    /// Same as buffer().lineEnd(startPos), but wrap-aware.
    int lineEnd(int startPos, bool startPosIsLineStart)
    {
        if (!continuousWrap_) return buffer_.lineEnd(startPos);
        if (startPos == buffer_.length()) return startPos;
        int retLines, retPos, retLineStart, retLineEnd;
        wrappedLineCounter(buffer_, startPos, buffer_.length(), 1, startPosIsLineStart, 0,
            retPos, retLines, retLineStart, retLineEnd);
        return retLineEnd;
    }

    /// Same as buffer().skipLines(), but wrap-aware.
    int skipLines(int startPos, int nLines, bool startPosIsLineStart)
    {
        if (!continuousWrap_) return buffer_.skipLines(startPos, nLines);
        if (nLines == 0) return startPos;
        int retLines, retPos, retLineStart, retLineEnd;
        wrappedLineCounter(buffer_, startPos, buffer_.length(), nLines, startPosIsLineStart, 0,
            retPos, retLines, retLineStart, retLineEnd);
        return retPos;
    }

    /// Same as buffer().rewindLines(), but wrap-aware.
    int rewindLines(int startPos, int nLines)
    {
        if (!continuousWrap_) return buffer_.rewindLines(startPos, nLines);

        int pos = startPos;
        for (;;)
        {
            int ls = buffer_.lineStart(pos);
            int retLines, retPos, retLineStart, retLineEnd;
            wrappedLineCounter(buffer_, ls, pos, int.max, true, 0,
                retPos, retLines, retLineStart, retLineEnd, false);
            if (retLines > nLines)
                return skipLines(ls, retLines - nLines, true);
            nLines -= retLines;
            pos = ls - 1;
            if (pos < 0) return 0;
            nLines -= 1;
        }
    }

    /// Moves the cursor right to the start of the next word.
    void nextWord()
    {
        int pos = insertPosition();
        while (pos < buffer_.length() && !buffer_.isWordSeparator(pos)) pos = buffer_.nextChar(pos);
        while (pos < buffer_.length() && buffer_.isWordSeparator(pos)) pos = buffer_.nextChar(pos);
        insertPosition(pos);
    }

    /// Moves the cursor left to the start of the current/previous word.
    void previousWord()
    {
        int pos = insertPosition();
        if (pos == 0) return;
        pos = buffer_.prevChar(pos);

        while (pos != 0 && buffer_.isWordSeparator(pos)) pos = buffer_.prevChar(pos);
        while (pos != 0 && !buffer_.isWordSeparator(pos)) pos = buffer_.prevChar(pos);

        if (buffer_.isWordSeparator(pos)) pos = buffer_.nextChar(pos);

        insertPosition(pos);
    }

    // -- Cursor appearance -------------------------------------------------

    /// Shows (b=true) or hides (b=false) the text cursor.
    void showCursor(bool b = true)
    {
        cursorOn_ = b;
        if (buffer_ is null) return;
        redisplayRange(buffer_.prevCharClipped(cursorPos_), buffer_.nextChar(cursorPos_));
    }

    /// Hides the text cursor.
    void hideCursor() { showCursor(false); }

    /// Whether the cursor is currently shown (FLTK's `mCursorOn`).
    /// Read by `fl.text_editor`'s `handle()`, which re-invokes
    /// `showCursor(cursorOn())` on focus/unfocus purely to force a
    /// redisplay of the cursor's current on/off state, matching
    /// `Fl_Text_Editor::handle()`'s `show_cursor(mCursorOn)` calls.
    bool cursorOn() const { return cursorOn_; }

    /// Sets the cursor style, switching it on.
    void cursorStyle(CursorStyle style)
    {
        cursorStyle_ = style;
        if (cursorOn_) showCursor();
    }

    CursorStyle cursorStyle() const { return cursorStyle_; }

    Color cursorColor() const { return cursorColor_; }
    void cursorColor(Color n) { cursorColor_ = n; }

    // -- Scrollbar sizing/alignment -----------------------------------------

    /// Deprecated (matching FLTK's own `\deprecated` doc comment):
    /// use scrollbarSize() instead.
    int scrollbarWidth() const { return scrollbarWidth_ ? scrollbarWidth_ : fl.core.scrollbarSize(); }
    /// Deprecated: use scrollbarSize(int) instead. Also sets the
    /// global fl.core.scrollbarSize(), matching FLTK's dual effect.
    void scrollbarWidth(int width) { fl.core.scrollbarSize(width); scrollbarWidth_ = 0; }

    int scrollbarSize() const { return scrollbarWidth_; }
    void scrollbarSize(int newSize) { scrollbarWidth_ = newSize; }

    Align scrollbarAlign() const { return scrollbarAlign_; }
    void scrollbarAlign(Align a) { scrollbarAlign_ = a; }

    // -- Word boundaries ------------------------------------------------

    int wordStart(int pos) { return buffer_.wordStart(pos); }
    int wordEnd(int pos) { return buffer_.wordEnd(pos); }

    // -- Syntax highlighting -------------------------------------------------

    /// Attaches (or detaches, if styleBuffer is null) a parallel style
    /// buffer + style table for syntax highlighting. See
    /// StyleTableEntry's doc comment. unfinishedHighlightCB is called
    /// when position_style() finds a style-buffer entry equal to
    /// unfinishedStyle, to trigger on-the-fly re-highlighting.
    void highlightData(TextBuffer styleBuffer, const(StyleTableEntry)[] styleTable,
        char unfinishedStyle, UnfinishedStyleCb unfinishedHighlightCB)
    {
        styleBuffer_ = styleBuffer;
        styleTable_ = styleTable;
        nStyles_ = cast(int) styleTable.length;
        unfinishedStyle_ = unfinishedStyle;
        unfinishedHighlightCB_ = unfinishedHighlightCB;
        columnScale_ = 0;

        if (styleBuffer_ !is null) styleBuffer_.canUndo(false);
        damage(damageExpose);
    }

    /// Resolves the drawing style (a style-table index plus selection/
    /// highlight mask bits) for the character at byte offset
    /// lineStartPos+lineIndex within a line of length lineLen bytes.
    /// Passing lineStartPos=-1 returns the style for "no text" (an area
    /// beyond the end of the buffer).
    int positionStyle(int lineStartPos, int lineLen, int lineIndex)
    {
        if (lineStartPos == -1 || buffer_ is null) return styleFillMask;

        int pos = lineStartPos + min(lineIndex, lineLen);
        int style = 0;

        if (styleBuffer_ !is null && lineIndex == lineLen && lineLen > 0)
        {
            style = cast(ubyte) styleBuffer_.byteAt(pos - 1);
            if (style == unfinishedStyle_ && unfinishedHighlightCB_ !is null)
            {
                unfinishedHighlightCB_(pos);
                style = cast(ubyte) styleBuffer_.byteAt(pos);
            }
            int si = (style & styleLookupMask) - 'A';
            if (si < 0) si = 0;
            else if (si >= nStyles_) si = nStyles_ - 1;
            if (nStyles_ > 0 && (styleTable_[si].attr & attrBgcolorExt_) == 0)
                style = styleFillMask;
        }
        else if (lineIndex >= lineLen)
        {
            style = styleFillMask;
        }
        else if (styleBuffer_ !is null)
        {
            style = cast(ubyte) styleBuffer_.byteAt(pos);
            if (style == unfinishedStyle_ && unfinishedHighlightCB_ !is null)
            {
                unfinishedHighlightCB_(pos);
                style = cast(ubyte) styleBuffer_.byteAt(pos);
            }
        }
        if (buffer_.primarySelection().includes(pos)) style |= stylePrimaryMask;
        if (buffer_.highlightSelection().includes(pos)) style |= styleHighlightMask;
        if (buffer_.secondarySelection().includes(pos)) style |= styleSecondaryMask;
        return style;
    }

    // -- Misc accessors ---------------------------------------------------

    /// \todo (matching FLTK's own FIXME): shortcut()/shortcut(int)
    /// have no effect on the base TextDisplay -- FL_SHORTCUT reads it
    /// (see handle()), but nothing here ever sets it besides the user.
    int shortcut() const { return shortcut_; }
    void shortcut(int s) { shortcut_ = s; }

    Font textfont() const { return textfont_; }
    void textfont(Font s) { textfont_ = s; columnScale_ = 0; }

    Fontsize textsize() const { return textsize_; }
    void textsize(Fontsize s) { textsize_ = s; columnScale_ = 0; }

    Color textcolor() const { return textcolor_; }
    void textcolor(Color n) { textcolor_ = n; }

    void grammarUnderlineColor(Color c) { grammarUnderlineColor_ = c; }
    Color grammarUnderlineColor() const { return grammarUnderlineColor_; }

    void spellingUnderlineColor(Color c) { spellingUnderlineColor_ = c; }
    Color spellingUnderlineColor() const { return spellingUnderlineColor_; }

    void secondarySelectionColor(Color c) { secondarySelectionColor_ = c; }
    Color secondarySelectionColor() const { return secondarySelectionColor_; }

    // -- Wrapping ---------------------------------------------------------

    /// Column (row, column) -> absolute (non-wrapped) column, adjusting
    /// for continuous-wrap mode.
    int wrappedColumn(int row, int column)
    {
        if (!continuousWrap_ || row < 0 || row > nVisibleLines_) return column;
        int dispLineStart = lineStarts_[row];
        if (dispLineStart == -1) return column;
        int ls = buffer_.lineStart(dispLineStart);
        return column + buffer_.countDisplayedCharacters(ls, dispLineStart);
    }

    /// Wrapped display row -> count of real newlines from the top
    /// displayed line.
    int wrappedRow(int row)
    {
        if (!continuousWrap_ || row < 0 || row > nVisibleLines_) return row;
        return buffer_.countLines(firstChar_, lineStarts_[row]);
    }

    /// Sets the wrap mode/margin. See WrapMode's doc comments.
    void wrapMode(WrapMode wrap, int wrapMargin)
    {
        final switch (wrap)
        {
        case WrapMode.wrapNone:
            wrapMarginPix_ = 0;
            continuousWrap_ = false;
            break;
        case WrapMode.wrapAtColumn:
            wrapMarginPix_ = cast(int) colToX(wrapMargin);
            continuousWrap_ = true;
            break;
        case WrapMode.wrapAtPixel:
            wrapMarginPix_ = wrapMargin;
            continuousWrap_ = true;
            break;
        case WrapMode.wrapAtBounds:
            wrapMarginPix_ = 0;
            continuousWrap_ = true;
            break;
        }

        if (buffer_ !is null)
        {
            nBufferLines_ = countLines(0, buffer_.length(), true);
            firstChar_ = lineStart(firstChar_);
            topLineNum_ = countLines(0, firstChar_, true) + 1;
            resetAbsoluteTopLineNumber();
            calcLineStarts(0, nVisibleLines_);
            calcLastChar();
        }
        else
        {
            nBufferLines_ = 0;
            firstChar_ = 0;
            topLineNum_ = 1;
            absTopLineNum_ = 1;
        }

        displayNeedsRecalc();
    }

    // -- Layout / recalculation --------------------------------------------

    /// Recalculates visible lines, scrollbar geometry/visibility, and
    /// text-area bounds. Can be CPU-intensive on large buffers (same
    /// caveat as FLTK) -- prefer displayNeedsRecalc() to defer this
    /// until the next draw().
    void recalcDisplay()
    {
        if (buffer_ is null) return;

        bool hscrollbarVisible = hScrollBar_.visible();
        bool vscrollbarVisible = vScrollBar_.visible();
        int scrollsize = scrollbarWidth();

        int X = x() + fl.core.boxDx(box());
        int Y = y() + fl.core.boxDy(box());
        int W = w() - fl.core.boxDw(box());
        int H = h() - fl.core.boxDh(box());

        textArea_.x(X + leftMargin + lineNumWidth_);
        textArea_.y(Y + topMargin);
        textArea_.w(W - leftMargin - rightMargin - lineNumWidth_);
        textArea_.h(H - topMargin - bottomMargin);

        maxsize_ = height(textfont_, textsize_);
        foreach (st; styleTable_)
            maxsize_ = max(maxsize_, height(st.font, st.size));

        vScrollBar_.clearVisible();
        hScrollBar_.clearVisible();

        int oldTAWidth = -1;

        if (continuousWrap_ && !wrapMarginPix_)
        {
            int nvlines = (textArea_.h + maxsize_ - 1) / maxsize_;
            int nlines = buffer_.countLines(0, buffer_.length());
            if (nvlines < 1) nvlines = 1;
            if (nlines >= nvlines - 1)
            {
                vScrollBar_.setVisible();
                textArea_.w(textArea_.w - scrollsize);
            }
        }

        for (bool again = true; again;)
        {
            again = false;

            if (continuousWrap_ && !wrapMarginPix_ && textArea_.w != oldTAWidth)
            {
                int oldFirstChar = firstChar_;
                firstChar_ = lineStart(firstChar_);
                topLineNum_ = countLines(0, firstChar_, true) + 1;
                nBufferLines_ = topLineNum_ - 1 + countLines(firstChar_, buffer_.length(), true);
                absoluteTopLineNumber(oldFirstChar);
            }

            oldTAWidth = textArea_.w;

            int nvlines = (textArea_.h + maxsize_ - 1) / maxsize_;
            if (nvlines < 1) nvlines = 1;
            if (nVisibleLines_ != nvlines)
            {
                nVisibleLines_ = nvlines;
                lineStarts_ = new int[](nVisibleLines_);
            }

            calcLineStarts(0, nVisibleLines_);
            calcLastChar();

            if (scrollsize)
            {
                if (!vScrollBar_.visible()
                    && (scrollbarAlign_ & (alignLeft | alignRight)) != 0
                    && nBufferLines_ >= nVisibleLines_ - ((continuousWrap_ && wrapMarginPix_) ? 0 : 1))
                {
                    vScrollBar_.setVisible();
                    textArea_.w(textArea_.w - scrollsize);
                    again = true;
                }

                if (!hScrollBar_.visible()
                    && (scrollbarAlign_ & (alignTop | alignBottom)) != 0
                    && (vScrollBar_.visible() || longestVline() > textArea_.w))
                {
                    bool wrapAtBounds = continuousWrap_ && (wrapMarginPix_ < textArea_.w);
                    if (!wrapAtBounds)
                    {
                        hScrollBar_.setVisible();
                        textArea_.h(textArea_.h - scrollsize);
                        again = true;
                    }
                }
            }
        }

        textArea_.x(X + lineNumWidth_ + leftMargin);
        if (vScrollBar_.visible() && (scrollbarAlign_ & alignLeft) != 0)
            textArea_.x(textArea_.x + scrollsize);

        textArea_.y(Y + topMargin);
        if (hScrollBar_.visible() && (scrollbarAlign_ & alignTop) != 0)
            textArea_.y(textArea_.y + scrollsize);

        if (vScrollBar_.visible())
        {
            if (scrollbarAlign_ & alignLeft)
                vScrollBar_.resize(textArea_.x - leftMargin - scrollsize, textArea_.y - topMargin,
                    scrollsize, textArea_.h + topMargin + bottomMargin);
            else
                vScrollBar_.resize(X + W - scrollsize, textArea_.y - topMargin,
                    scrollsize, textArea_.h + topMargin + bottomMargin);
        }

        if (hScrollBar_.visible())
        {
            if (scrollbarAlign_ & alignTop)
                hScrollBar_.resize(textArea_.x - leftMargin, Y,
                    textArea_.w + leftMargin + rightMargin, scrollsize);
            else
                hScrollBar_.resize(textArea_.x - leftMargin, Y + H - scrollsize,
                    textArea_.w + leftMargin + rightMargin, scrollsize);
        }

        if (topLineNumHint_ != topLineNum_ || horizOffsetHint_ != horizOffset_)
            scrollImpl(topLineNumHint_, horizOffsetHint_);

        if ((nBufferLines_ + 1 < nVisibleLines_) || buffer_ is null || buffer_.length() == 0)
        {
            scrollImpl(1, horizOffset_);
        }
        else
        {
            while (nVisibleLines_ >= 2 && lineStarts_[nVisibleLines_ - 2] == -1
                && scrollImpl(topLineNum_ - 1, horizOffset_)) {}
        }

        if (displayInsertPositionHint_)
            displayInsert();

        int maxhoffset = max(0, longestVline() - textArea_.w);
        if (horizOffset_ > maxhoffset)
            scrollImpl(topLineNumHint_, maxhoffset);

        topLineNumHint_ = topLineNum_;
        horizOffsetHint_ = horizOffset_;
        displayInsertPositionHint_ = false;

        if (continuousWrap_ || hscrollbarVisible != hScrollBar_.visible() || vscrollbarVisible != vScrollBar_.visible())
            redraw();

        updateVScrollbar();
        updateHScrollbar();
    }

    /// Schedules a recalcDisplay() on the next draw(), rather than
    /// recalculating immediately (which can be CPU-intensive if called
    /// repeatedly).
    void displayNeedsRecalc()
    {
        displayNeedsRecalc_ = true;
        redraw();
    }

    override void resize(int X, int Y, int W, int H)
    {
        // Deliberate deviation from FLTK: calls FlGroup's resize()
        // (via `super.resize()`) rather than bypassing it to call
        // Fl_Widget's own resize() directly the way
        // Fl_Text_Display::resize() does. D has no way to select a
        // specific ancestor's (non-immediate-parent's) virtual method
        // the way C++'s `Fl_Widget::resize(...)` explicit-scope call
        // does. This has no observable effect: FlGroup.resize() may
        // temporarily reposition the scrollbar children via its own
        // generic proportional-scaling algorithm, but recalcDisplay()
        // (triggered by displayNeedsRecalc() below, on the same lazy
        // "next draw()" timing FLTK itself uses) always overwrites
        // their exact position/size again before anything is drawn.
        super.resize(X, Y, W, H);
        columnScale_ = 0;
        displayNeedsRecalc();
    }

    /// Converts an x pixel offset (from the left margin) to an
    /// approximate column number, based on an average character width
    /// in the main font -- a real measurement (`stringWidth("Mitg", 4,
    /// 'A') / 4.0`, cached in `columnScale_`), not `tmpFontWidth`'s
    /// fixed-6px placeholder (that one backs `xyToRowcol()` instead,
    /// FLTK's own `TMPFONTWIDTH` split exactly).
    double xToCol(double x)
    {
        if (columnScale_ == 0) columnScale_ = stringWidth("Mitg", 4, 'A') / 4.0;
        return (x / columnScale_) + 0.5;
    }

    /// Inverse of xToCol().
    double colToX(double col)
    {
        if (columnScale_ == 0) xToCol(0);
        return col * columnScale_;
    }

    // -- Line numbers -----------------------------------------------------

    /// Sets the width (in pixels) of the line-number margin. 0 (the
    /// default) disables line numbers.
    void linenumberWidth(int width)
    {
        if (width < 0) return;
        lineNumWidth_ = width;
        displayNeedsRecalc();
        if (width > 0) resetAbsoluteTopLineNumber();
    }
    int linenumberWidth() const { return lineNumWidth_; }

    void linenumberFont(Font val) { linenumberFont_ = val; }
    Font linenumberFont() const { return linenumberFont_; }

    void linenumberSize(Fontsize val) { linenumberSize_ = val; }
    Fontsize linenumberSize() const { return linenumberSize_; }

    void linenumberFgcolor(Color val) { linenumberFgcolor_ = val; }
    Color linenumberFgcolor() const { return linenumberFgcolor_; }

    void linenumberBgcolor(Color val) { linenumberBgcolor_ = val; }
    Color linenumberBgcolor() const { return linenumberBgcolor_; }

    void linenumberAlign(Align val) { linenumberAlign_ = val; }
    Align linenumberAlign() const { return linenumberAlign_; }

    /// A printf-style format string (e.g. "%d", "%03d", "%x", "%o")
    /// used to render each line number -- fed to std.format.format()
    /// rather than a C printf() call, but the same basic numeric
    /// conversions are supported by both.
    void linenumberFormat(string val) { linenumberFormat_ = val; }
    string linenumberFormat() const { return linenumberFormat_; }

    // -- Absolute (non-wrapped) line numbers --------------------------------

    /// Requests (state=true) or stops (state=false) maintaining the
    /// absolute (non-wrapped) top line number even when it isn't needed
    /// for line-number display.
    void maintainAbsoluteTopLineNumber(bool state)
    {
        needAbsTopLineNum_ = state;
        resetAbsoluteTopLineNumber();
    }

    /// The absolute (non-wrapped) line number of the top displayed
    /// line, or 0 if it isn't being maintained.
    int getAbsoluteTopLineNumber()
    {
        if (!continuousWrap_) return topLineNum_;
        if (maintainingAbsoluteTopLineNumber()) return absTopLineNum_;
        return 0;
    }

    int scrollRow() { return topLineNum_; }
    int scrollCol() { return horizOffset_; }

    // ===================================================================
    // protected: layout/draw internals (mirrors FLTK's `protected:`
    // section). See the D-const note in the module comment for why very
    // few of these stay `const`.
    // ===================================================================
    protected:

    override void draw()
    {
        if (buffer_ is null) { drawBox(); return; }

        if (displayNeedsRecalc_ || (damage() & damageAll))
        {
            displayNeedsRecalc_ = false;
            recalcDisplay();
        }

        pushClip(x(), y(), w(), h());

        Color bgcolor = activeR() ? color() : inactive(color());

        if (damage() & damageAll)
        {
            recalcDisplay();

            if (SurfaceDevice.surface() !is null)
            {
                // Printing/off-screen surface, not the display -- fill
                // the text area's background explicitly, matching
                // FLTK's own "if to printer, draw the background"
                // comment (a fresh page has no prior frame to rely on
                // the way an incremental screen redraw would).
                fl_rectf(textArea_.x, textArea_.y, textArea_.w, textArea_.h, bgcolor);
            }

            drawBox(box(), x(), y(), w(), h(), bgcolor);

            fl_color(bgcolor);
            fl_rectf(textArea_.x - leftMargin, textArea_.y - topMargin,
                leftMargin, textArea_.h + topMargin + bottomMargin);
            fl_rectf(textArea_.x + textArea_.w, textArea_.y - topMargin,
                rightMargin, textArea_.h + topMargin + bottomMargin);
            fl_rectf(textArea_.x, textArea_.y - topMargin, textArea_.w, topMargin);
            fl_rectf(textArea_.x, textArea_.y + textArea_.h, textArea_.w, bottomMargin);

            if (vScrollBar_.visible() && hScrollBar_.visible())
            {
                fl_color(backgroundColor);
                fl_rectf(vScrollBar_.x(), hScrollBar_.y(), vScrollBar_.w(), hScrollBar_.h());
            }
        }
        else if (damage() & (damageScroll | damageExpose))
        {
            pushClip(textArea_.x - leftMargin, textArea_.y,
                textArea_.w + leftMargin + rightMargin, textArea_.h);
            fl_color(bgcolor);
            fl_rectf(textArea_.x - leftMargin, cursorOldY_, leftMargin, maxsize_);
            fl_rectf(textArea_.x + textArea_.w, cursorOldY_, rightMargin, maxsize_);
            popClip();
        }

        if (damage() & (damageAll | damageChild))
        {
            vScrollBar_.damage(damageAll);
            hScrollBar_.damage(damageAll);
        }
        updateChild(vScrollBar_);
        updateChild(hScrollBar_);

        if (damage() & (damageAll | damageExpose))
        {
            int X, Y, W, H;
            if (clipBox(textArea_.x, textArea_.y, textArea_.w, textArea_.h, X, Y, W, H))
                drawText(X, Y, W, H);
            else
                drawText(textArea_.x, textArea_.y, textArea_.w, textArea_.h);
        }
        else if (damage() & damageScroll)
        {
            pushClip(textArea_.x, textArea_.y, textArea_.w, textArea_.h);
            drawRange(damageRange1Start_, damageRange1End_);
            if (damageRange2End_ != -1) drawRange(damageRange2Start_, damageRange2End_);
            damageRange1Start_ = damageRange1End_ = -1;
            damageRange2Start_ = damageRange2End_ = -1;
            popClip();
        }

        int start, end;
        bool hasSelection = buffer_.selectionPosition(start, end);
        if ((damage() & (damageAll | damageScroll | damageExpose)) != 0
            && (!hasSelection || cursorPos_ < start || cursorPos_ > end)
            && cursorOn_ && fl.core.focus() is this)
        {
            pushClip(textArea_.x - leftMargin, textArea_.y,
                textArea_.w + leftMargin + rightMargin, textArea_.h);
            int X, Y;
            if (positionToXy(cursorPos_, X, Y))
            {
                drawCursor(X, Y);
                cursorOldY_ = Y;
            }
            popClip();
        }

        drawLineNumbers(true);

        popClip();
    }

    void drawText(int left, int top, int width, int height)
    {
        int fontHeight = maxsize_ ? maxsize_ : textsize_;
        int firstLine = (top - textArea_.y - fontHeight + 1) / fontHeight;
        int lastLine = (top + height - textArea_.y) / fontHeight + 1;

        pushClip(left, top, width, height);
        foreach (line; firstLine .. lastLine + 1)
            drawVline(line, left, left + width, 0, int.max);
        popClip();
    }

    void drawRange(int startpos, int endpos)
    {
        startpos = buffer_.utf8Align(startpos);
        endpos = buffer_.utf8Align(endpos);

        if (endpos < firstChar_ || (startpos > lastChar_ && !emptyVlines())) return;

        if (startpos < 0) startpos = 0;
        if (startpos > buffer_.length()) startpos = buffer_.length();
        if (endpos < 0) endpos = 0;
        if (endpos > buffer_.length()) endpos = buffer_.length();

        if (startpos < firstChar_) startpos = firstChar_;

        int startLine, lastLine;
        if (!positionToLine(startpos, startLine)) startLine = nVisibleLines_ - 1;
        if (endpos >= lastChar_)
            lastLine = nVisibleLines_ - 1;
        else if (!positionToLine(endpos, lastLine))
            lastLine = nVisibleLines_ - 1;

        int startIndex = lineStarts_[startLine] == -1 ? 0 : startpos - lineStarts_[startLine];
        int endIndex;
        if (endpos >= lastChar_) endIndex = int.max;
        else if (lineStarts_[lastLine] == -1) endIndex = 0;
        else endIndex = endpos - lineStarts_[lastLine];

        if (startLine == lastLine)
        {
            drawVline(startLine, 0, int.max, startIndex, endIndex);
            return;
        }

        drawVline(startLine, 0, int.max, startIndex, int.max);
        foreach (i; startLine + 1 .. lastLine)
            drawVline(i, 0, int.max, 0, int.max);
        drawVline(lastLine, 0, int.max, 0, endIndex);
    }

    void drawCursor(int X, int Y)
    {
        static struct Segment { int x1, y1, x2, y2; }
        Segment[5] segs;
        int nSegs = 0;
        int fontWidth = tmpFontWidth;
        int fontHeight = maxsize_;
        int bot = Y + fontHeight - 1;

        if (X < textArea_.x - 1 || X > textArea_.x + textArea_.w) return;

        int cursorWidth = 4;
        int left = X - cursorWidth / 2;
        int right = left + cursorWidth;

        final switch (cursorStyle_)
        {
        case CursorStyle.caretCursor:
        {
            int midY = bot - fontHeight / 5;
            segs[0] = Segment(left, bot, X, midY);
            segs[1] = Segment(X, midY, right, bot);
            segs[2] = Segment(left, bot, X, midY - 1);
            segs[3] = Segment(X, midY - 1, right, bot);
            nSegs = 4;
            break;
        }
        case CursorStyle.normalCursor:
            segs[0] = Segment(left, Y, right, Y);
            segs[1] = Segment(X, Y, X, bot);
            segs[2] = Segment(left, bot, right, bot);
            nSegs = 3;
            break;
        case CursorStyle.heavyCursor:
            segs[0] = Segment(X - 1, Y, X - 1, bot);
            segs[1] = Segment(X, Y, X, bot);
            segs[2] = Segment(X + 1, Y, X + 1, bot);
            segs[3] = Segment(left, Y, right, Y);
            segs[4] = Segment(left, bot, right, bot);
            nSegs = 5;
            break;
        case CursorStyle.dimCursor:
        {
            int midY = Y + fontHeight / 2;
            segs[0] = Segment(X, Y, X, Y);
            segs[1] = Segment(X, midY, X, midY);
            segs[2] = Segment(X, bot, X, bot);
            nSegs = 3;
            break;
        }
        case CursorStyle.blockCursor:
            right = X + fontWidth;
            segs[0] = Segment(X, Y, right, Y);
            segs[1] = Segment(right, Y, right, bot);
            segs[2] = Segment(right, bot, X, bot);
            segs[3] = Segment(X, bot, X, Y);
            nSegs = 4;
            break;
        case CursorStyle.simpleCursor:
            segs[0] = Segment(X, Y, X, bot);
            segs[1] = Segment(X + 1, Y, X + 1, bot);
            nSegs = 2;
            break;
        }

        fl_color(cursorColor_);
        foreach (k; 0 .. nSegs)
            fl_line(segs[k].x1, segs[k].y1, segs[k].x2, segs[k].y2);

        // setSpot() reports the cursor's screen position to the input
        // method for "over the spot" CJK/composing-IME preedit
        // positioning, matching Fl_Text_Display::draw_cursor() exactly
        // (issue #270 FLTK's own comment references).
        if (fl.core.focus() is this)
            setSpot(textfont(), textsize(), X, bot, textArea_.w, textArea_.h, window());
    }

    void drawString(StyleFlags style, int X, int Y, int toX, const(char)[] str, int nChars)
    {
        if (style & styleFillMask)
        {
            if (style & styleTextOnlyMask) return;
            clearRect(style, X, Y, toX - X, maxsize_);
            return;
        }

        const(StyleTableEntry)* styleRec = null;

        Font font = textfont_;
        Fontsize fsize = textsize_;
        Color foreground, background, bgbasecolor;

        if (style & styleLookupMask)
        {
            int si = (style & styleLookupMask) - 'A';
            if (si < 0) si = 0;
            else if (si >= nStyles_) si = nStyles_ - 1;

            styleRec = &styleTable_[si];
            font = styleRec.font;
            fsize = styleRec.size;
            bgbasecolor = (styleRec.attr & attrBgcolor) ? styleRec.bgcolor : color();

            bool focused = fl.core.focus() is this;
            if (style & stylePrimaryMask)
                background = focused ? selectionColor() : colorAverage(bgbasecolor, selectionColor(), 0.4f);
            else if (style & styleHighlightMask)
                background = colorAverage(bgbasecolor, selectionColor(), focused ? 0.5f : 0.6f);
            else if (style & styleSecondaryMask)
                background = colorAverage(bgbasecolor, secondarySelectionColor(), focused ? 0.5f : 0.6f);
            else
                background = bgbasecolor;
            foreground = (style & stylePrimaryMask) ? contrast(styleRec.color, background) : styleRec.color;
        }
        else
        {
            bool focused = fl.core.focus() is this;
            if (style & stylePrimaryMask)
            {
                background = focused ? selectionColor() : colorAverage(color(), selectionColor(), 0.4f);
                foreground = contrast(textcolor_, background);
            }
            else if (style & styleHighlightMask)
            {
                background = colorAverage(color(), selectionColor(), focused ? 0.5f : 0.6f);
                foreground = contrast(textcolor_, background);
            }
            else if (style & styleSecondaryMask)
            {
                background = focused ? secondarySelectionColor()
                    : colorAverage(color(), secondarySelectionColor(), 0.4f);
                foreground = contrast(textcolor_, background);
            }
            else
            {
                foreground = textcolor_;
                background = color();
            }
        }

        if (!activeR())
        {
            foreground = inactive(foreground);
            background = inactive(background);
        }

        if (!(style & styleTextOnlyMask))
        {
            fl_color(background);
            fl_rectf(X, Y, toX - X, maxsize_);
        }
        if (!(style & styleBgOnlyMask))
        {
            fl_color(foreground);
            fl_font(font, fsize);
            int baseline = Y + maxsize_ - descent();
            fl_draw(str, nChars, X, baseline);

            // ATTR_LINES_MASK underline/strike-through rendering, backed
            // by fl.draw's real lineStyle()/antialias(). Ported
            // from Fl_Text_Display::draw_string()'s own ATTR_LINES_MASK
            // switch (src/Fl_Text_Display.cxx).
            if (styleRec !is null && (styleRec.attr & attrLinesMask))
            {
                int pitch = fsize / 7;
                int prevAA = antialias();
                antialias(1);
                switch (styleRec.attr & attrLinesMask)
                {
                case attrUnderline:
                    fl_color(foreground);
                    lineStyle(lineSolid, pitch);
                    fl_xyline(X, baseline + descent() / 2, toX);
                    break;
                case attrGrammar:
                    fl_color(grammarUnderlineColor_);
                    lineStyle(lineDot, pitch);
                    fl_xyline(X, baseline + descent() / 2, toX);
                    break;
                case attrSpelling:
                    fl_color(spellingUnderlineColor_);
                    lineStyle(lineDot, pitch);
                    fl_xyline(X, baseline + descent() / 2, toX);
                    break;
                case attrStrikeThrough:
                    fl_color(foreground);
                    lineStyle(lineSolid, pitch);
                    fl_xyline(X, baseline - (height() - descent()) / 3, toX);
                    break;
                default:
                    break;
                }
                lineStyle(lineSolid, 1);
                antialias(prevAA);
            }
            // IME marked-text underline isn't ported -- gated FLTK
            // on Fl::compose_state, which is confirmed dead on X11 (see
            // fl.core's own compose() doc comment); not a gap here.
        }
    }

    void drawVline(int visLineNum, int leftClip, int rightClip, int leftCharIndex, int rightCharIndex)
    {
        if (visLineNum < 0 || visLineNum >= nVisibleLines_) return;

        int fontHeight = maxsize_;
        int Y = textArea_.y + visLineNum * fontHeight;

        int lineStartPos = lineStarts_[visLineNum];
        int lineLen = lineStartPos == -1 ? 0 : vlineLength(visLineNum);

        leftClip = max(textArea_.x, leftClip);
        rightClip = min(rightClip, textArea_.x + textArea_.w);

        handleVline(HandleMode.drawLine, lineStartPos, lineLen, leftCharIndex, rightCharIndex,
            Y, Y + fontHeight, leftClip, rightClip);
    }

    /// Finds the index of the character at (or closest cursor position
    /// to, if x<0) pixel offset |x| within s.
    int findX(const(char)[] s, int len, int style, int xArg)
    {
        bool cursorPosFlag = xArg < 0;
        int x = cursorPosFlag ? -xArg : xArg;

        int i = 0;
        int lastW = 0;
        while (i < len)
        {
            int cl = utf8Len1(s[i]);
            if (i + cl > len) cl = len - i;
            int w = cast(int) stringWidth(s, i + cl, style);
            if (w > x)
            {
                if (cursorPosFlag && (w - x < x - lastW)) return i + cl;
                return i;
            }
            lastW = w;
            i += cl;
        }
        return len;
    }

    /**
     * The "universal pixel machine": handles measuring (GET_WIDTH),
     * finding the character at a pixel position (FIND_INDEX/
     * FIND_INDEX_FROM_ZERO/FIND_CURSOR_INDEX), and drawing (DRAW_LINE)
     * a single line of text. Ported in full: it's the shared engine
     * behind both testable measurement code (moveUp/moveDown/
     * xyToPosition/positionToXy/measureVline/...) and drawVline().
     */
    int handleVline(HandleMode modeIn, int lineStartPos, int lineLen, int leftChar, int rightChar,
        int Y, int bottomClip, int leftClip, int rightClip)
    {
        bool haveLine = lineStartPos != -1;
        string lineStr = haveLine ? buffer_.textRange(lineStartPos, lineStartPos + lineLen) : null;

        bool cursorPosFlag = false;
        HandleMode mode = modeIn;
        if (mode == HandleMode.findCursorIndex) { mode = HandleMode.findIndex; cursorPosFlag = true; }

        double X;
        if (mode == HandleMode.getWidth) X = 0;
        else if (mode == HandleMode.findIndexFromZero) { X = 0; mode = HandleMode.findIndex; }
        else X = textArea_.x - horizOffset_;

        for (int loop = 1; loop <= 2; loop++)
        {
            StyleFlags mask = (loop == 1) ? styleBgOnlyMask : styleTextOnlyMask;
            double startX = X;
            int startIndex = 0;

            if (!haveLine)
            {
                if (mode == HandleMode.drawLine)
                {
                    int style = positionStyle(lineStartPos, lineLen, -1);
                    if (loop == 1)
                        drawString(style | styleBgOnlyMask, cast(int) textArea_.x, Y,
                            textArea_.x + textArea_.w, null, lineLen);
                }
                if (mode == HandleMode.findIndex) return lineStartPos;
                return 0;
            }

            char currChar = 0, prevChar = 0;
            double styleX = startX;
            int startStyle = startIndex;
            int style = positionStyle(lineStartPos, lineLen, 0);
            int i = 0;
            while (i < lineLen)
            {
                currChar = lineStr[i];
                int len = utf8Len1(currChar);
                int charStyle = positionStyle(lineStartPos, lineLen, i);
                if (charStyle != style || currChar == '\t' || prevChar == '\t')
                {
                    double w = 0;
                    if (prevChar == '\t')
                    {
                        double tab = colToX(buffer_.tabDistance());
                        double xAbs = (mode == HandleMode.getWidth) ? startX : startX + horizOffset_ - textArea_.x;
                        w = ((cast(int)(xAbs / tab) + 1) * tab) - xAbs;
                        styleX = startX + w; startStyle = i;
                        if (mode == HandleMode.drawLine && loop == 1)
                            drawString(style | styleBgOnlyMask, cast(int) startX, Y, cast(int)(startX + w), null, 0);
                        if (mode == HandleMode.findIndex && startX + w > rightClip)
                        {
                            if (cursorPosFlag && (startX + w / 2 < rightClip))
                                return lineStartPos + startIndex + 1;
                            return lineStartPos + startIndex;
                        }
                    }
                    else
                    {
                        if ((style & 0xff) == (charStyle & 0xff))
                            w = stringWidth(lineStr[startStyle .. $], i - startStyle, style) - startX + styleX;
                        else
                            w = stringWidth(lineStr[startIndex .. $], i - startIndex, style);

                        if (mode == HandleMode.drawLine)
                        {
                            if (startIndex != startStyle)
                            {
                                pushClip(cast(int) startX, Y, cast(int) w + 1, maxsize_);
                                drawString(style | mask, cast(int) styleX, Y, cast(int)(startX + w),
                                    lineStr[startStyle .. $], i - startStyle);
                                popClip();
                            }
                            else
                            {
                                drawString(style | mask, cast(int) startX, Y, cast(int)(startX + w),
                                    lineStr[startIndex .. $], i - startIndex);
                            }
                        }
                        if (mode == HandleMode.findIndex && startX + w > rightClip)
                        {
                            int di;
                            if (startIndex != startStyle)
                                di = lineStartPos + startStyle
                                    + findX(lineStr[startStyle .. $], i - startStyle, style, -cast(int)(rightClip - styleX));
                            else
                                di = lineStartPos + startIndex
                                    + findX(lineStr[startIndex .. $], i - startIndex, style, -cast(int)(rightClip - startX));
                            return di;
                        }
                        if ((style & 0xff) != (charStyle & 0xff))
                        {
                            startStyle = i;
                            styleX = startX + w;
                        }
                    }
                    style = charStyle;
                    startX += w;
                    startIndex = i;
                }
                i += len;
                prevChar = currChar;
            }

            double w = 0;
            if (currChar == '\t')
            {
                double tab = colToX(buffer_.tabDistance());
                double xAbs = (mode == HandleMode.getWidth) ? startX : startX + horizOffset_ - textArea_.x;
                w = ((cast(int)(xAbs / tab) + 1) * tab) - xAbs;
                if (mode == HandleMode.drawLine && loop == 1)
                    drawString(style | styleBgOnlyMask, cast(int) startX, Y, cast(int)(startX + w), null, 0);
                if (mode == HandleMode.findIndex)
                {
                    if (cursorPosFlag) return lineStartPos + startIndex + (rightClip - startX > w / 2 ? 1 : 0);
                    return lineStartPos + startIndex + (rightClip - startX > w ? 1 : 0);
                }
            }
            else
            {
                w = stringWidth(lineStr[startIndex .. $], i - startIndex, style);
                if (mode == HandleMode.drawLine)
                {
                    if (startIndex != startStyle)
                    {
                        pushClip(cast(int) startX, Y, cast(int) w + 1, maxsize_);
                        drawString(style | mask, cast(int) styleX, Y, cast(int)(startX + w),
                            lineStr[startStyle .. $], i - startStyle);
                        popClip();
                    }
                    else
                    {
                        drawString(style | mask, cast(int) startX, Y, cast(int)(startX + w),
                            lineStr[startIndex .. $], i - startIndex);
                    }
                }
                if (mode == HandleMode.findIndex)
                {
                    int di;
                    if (startIndex != startStyle)
                        di = lineStartPos + startStyle
                            + findX(lineStr[startStyle .. $], i - startStyle, style, -cast(int)(rightClip - styleX));
                    else
                        di = lineStartPos + startIndex
                            + findX(lineStr[startIndex .. $], i - startIndex, style, -cast(int)(rightClip - startX));
                    return di;
                }
            }
            if (mode == HandleMode.getWidth) return cast(int)(startX + w);

            startX += w;
            style = positionStyle(lineStartPos, lineLen, i);
            if (mode == HandleMode.drawLine && loop == 1)
                drawString(style | styleBgOnlyMask, cast(int) startX, Y, textArea_.x + textArea_.w, lineStr, lineLen);
        }

        return lineStartPos + lineLen;
    }

    /**
     * Adjusts the selection for a right-click at the current event
     * position (clicking inside an existing selection keeps it;
     * clicking a word selects that word; clicking past line/buffer end
     * just repositions the cursor), then pops up a real Cut/Copy/Paste
     * menu (`readonly` deactivates Cut/Paste) via `fl.menu_popup`.
     * Returns 1/2/3 for Cut/Copy/Paste if the user picked one, 0 if
     * the menu was dismissed -- matching FLTK's `argument()`-based
     * return values, just recovered via index into the local
     * `MenuItem[]` instead (this port's `MenuItem` has no `user_data()`/
     * `argument()` slot, see `fl.menu_item`'s doc comment).
     *
     * Skips FLTK's extra `type() == FL_SECRET_INPUT` case in the
     * "keep the existing selection" check: that's an `Fl_Input`-only
     * `type()` value `Fl_Text_Display` never has, so the check is
     * unreachable dead code here (this function is shared verbatim
     * between `Fl_Input`/`Fl_Text_Display` FLTK, `Fl_Input`'s own
     * copy is what that branch is actually for).
     */
    int handleRmb(bool readonly)
    {
        int newpos = xyToPosition(fl.core.eventX(), fl.core.eventY(), PositionType.cursorPos);
        int oldpos = buffer_.primarySelection().start();
        int oldmark = buffer_.primarySelection().end();
        bool insideSelection = (oldpos < newpos && oldmark > newpos) || (oldmark < newpos && oldpos > newpos);
        if (!insideSelection)
        {
            if (buffer_.charAt(newpos) == 0 || buffer_.charAt(newpos) == '\n')
                buffer_.select(newpos, newpos);
            else
                buffer_.select(buffer_.wordStart(newpos), buffer_.wordEnd(newpos));
        }

        auto items = new MenuItem[4]; // Cut, Copy, Paste, sentinel
        items[0] = MenuItem(cutMenuText);
        items[1] = MenuItem(copyMenuText);
        items[2] = MenuItem(pasteMenuText);
        if (readonly)
        {
            items[0].deactivate();
            items[2].deactivate();
        }

        if (window() !is null) window().cursor(Cursor.default_);

        // Deliberate departure from FLTK: always uses the real,
        // current mouse position rather than a computed one -- see
        // fl.input.d's own handleRmb() for the full reasoning (the
        // computed approach is fragile for at least one real widget
        // shape in this port, fl.value_input's embedded Input).
        int screenX, screenY;
        fl.core.getMouse(screenX, screenY);

        auto picked = fl.menu_popup.popup(&items[0], screenX, screenY);
        if (picked is null) return 0;
        return cast(int) (picked - &items[0]) + 1;
    }

    void drawLineNumbers(bool clearAll)
    {
        if (lineNumWidth_ <= 0 || !visibleR()) return;

        int lineHeight = maxsize_;
        bool isActive = activeR();

        int hscrollH = hScrollBar_.visible() ? hScrollBar_.h() : 0;
        int xoff = fl.core.boxDx(box());
        int yoff = textArea_.y - y();

        Color fgcolor = isActive ? linenumberFgcolor_ : inactive(linenumberFgcolor_);
        Color bgcolor = isActive ? linenumberBgcolor_ : inactive(linenumberBgcolor_);

        pushClip(x() + xoff, y() + fl.core.boxDy(box()), lineNumWidth_, h() - fl.core.boxDh(box()));

        fl_color(bgcolor);
        fl_rectf(x() + xoff, y(), lineNumWidth_, h());

        fl_font(linenumberFont_, linenumberSize_);

        int Y = y() + yoff;
        int line = getAbsoluteTopLineNumber();

        fl_color(fgcolor);
        foreach (visLine; 0 .. nVisibleLines_)
        {
            int lineStartPos = lineStarts_[visLine];
            if (lineStartPos != -1 && (lineStartPos == 0 || buffer_.charAt(lineStartPos - 1) == '\n'))
            {
                if (linenumberFormat_.length > 0)
                {
                    string numStr = format(linenumberFormat_, line);
                    int xx = x() + xoff + 3;
                    int ww = lineNumWidth_ - 6;
                    fl_draw(numStr, xx, Y, ww, lineHeight, linenumberAlign_);
                }
                line++;
            }
            else if (visLine == 0) line++;
            Y += lineHeight;
        }

        fl_color(backgroundColor);
        if (scrollbarAlign_ & alignTop)
            fl_rectf(x() + xoff, y() + fl.core.boxDy(box()), lineNumWidth_, hscrollH);
        else
            fl_rectf(x() + xoff, y() + h() - hscrollH - fl.core.boxDy(box()), lineNumWidth_,
                hscrollH + fl.core.boxDy(box()));

        popClip();
    }

    void clearRect(StyleFlags style, int X, int Y, int width, int height)
    {
        if (width == 0) return;

        Color bgbasecolor = color();
        if (style & styleLookupMask)
        {
            int si = (style & styleLookupMask) - 'A';
            if (si < 0) si = 0;
            else if (si >= nStyles_) si = nStyles_ - 1;
            if (nStyles_ > 0 && (styleTable_[si].attr & attrBgcolorExt_) != 0)
                bgbasecolor = styleTable_[si].bgcolor;
        }

        Color c;
        bool focused = fl.core.focus() is this;
        if (style & stylePrimaryMask)
            c = focused ? selectionColor() : colorAverage(bgbasecolor, selectionColor(), 0.4f);
        else if (style & styleHighlightMask)
            c = colorAverage(bgbasecolor, selectionColor(), focused ? 0.5f : 0.6f);
        else
            c = bgbasecolor;

        fl_color(activeR() ? c : inactive(c));
        fl_rectf(X, Y, width, height);
    }

    /// Scrolls to bring the insert cursor into view, matching FLTK's
    /// own comment: doing this without counting lines twice would be
    /// nice, but isn't worth the extra complexity.
    void displayInsert()
    {
        int hOffset = horizOffset_;
        int topLine = topLineNum_;

        if (insertPosition() < firstChar_)
        {
            topLine -= countLines(insertPosition(), firstChar_, false);
        }
        else if (nVisibleLines_ >= 2 && lineStarts_[nVisibleLines_ - 2] != -1)
        {
            int lastCh = lineEnd(lineStarts_[nVisibleLines_ - 2], true);
            if (insertPosition() >= lastCh)
                topLine += countLines(lastCh - (wrapUsesCharacter(lastChar_) ? 0 : 1), insertPosition(), false);
        }

        int X, Y;
        if (!positionToXy(cursorPos_, X, Y))
        {
            scrollImpl(topLine, hOffset);
            if (!positionToXy(cursorPos_, X, Y)) return; // give up, matching FLTK
        }
        if (X > textArea_.x + textArea_.w)
            hOffset += X - (textArea_.x + textArea_.w);
        else if (X < textArea_.x)
            hOffset += X - textArea_.x;

        if (topLine != topLineNum_ || hOffset != horizOffset_)
            scrollImpl(topLine, hOffset);
    }

    void offsetLineStarts(int newTopLineNum)
    {
        int oldTopLineNum = topLineNum_;
        int oldFirstChar = firstChar_;
        int lineDelta = newTopLineNum - oldTopLineNum;
        int nVisLines = nVisibleLines_;

        if (lineDelta == 0) return;

        int lastLineNum = oldTopLineNum + nVisLines - 1;
        if (newTopLineNum < oldTopLineNum && newTopLineNum < -lineDelta)
            firstChar_ = skipLines(0, newTopLineNum - 1, true);
        else if (newTopLineNum < oldTopLineNum)
            firstChar_ = rewindLines(firstChar_, -lineDelta);
        else if (newTopLineNum < lastLineNum)
            firstChar_ = lineStarts_[newTopLineNum - oldTopLineNum];
        else if (newTopLineNum - lastLineNum < nBufferLines_ - newTopLineNum)
            firstChar_ = skipLines(lineStarts_[nVisLines - 1], newTopLineNum - lastLineNum, true);
        else
            firstChar_ = rewindLines(buffer_.length(), nBufferLines_ - newTopLineNum + 1);

        if (lineDelta < 0 && -lineDelta < nVisLines)
        {
            for (int i = nVisLines - 1; i >= -lineDelta; i--)
                lineStarts_[i] = lineStarts_[i + lineDelta];
            calcLineStarts(0, -lineDelta);
        }
        else if (lineDelta > 0 && lineDelta < nVisLines)
        {
            for (int i = 0; i < nVisLines - lineDelta; i++)
                lineStarts_[i] = lineStarts_[i + lineDelta];
            calcLineStarts(nVisLines - lineDelta, nVisLines - 1);
        }
        else
        {
            calcLineStarts(0, nVisLines);
        }

        calcLastChar();
        topLineNum_ = newTopLineNum;

        absoluteTopLineNumber(oldFirstChar);
    }

    void calcLineStarts(int startLine, int endLine)
    {
        int bufLen = buffer_.length();
        int nVis = nVisibleLines_;

        if (endLine < 0) endLine = 0;
        if (endLine >= nVis) endLine = nVis - 1;
        if (startLine < 0) startLine = 0;
        if (startLine >= nVis) startLine = nVis - 1;
        if (startLine > endLine) return;

        if (startLine == 0)
        {
            lineStarts_[0] = firstChar_;
            startLine = 1;
        }
        int startPos = lineStarts_[startLine - 1];

        if (startPos == -1)
        {
            foreach (line; startLine .. endLine + 1) lineStarts_[line] = -1;
            return;
        }

        int line = startLine;
        for (; line <= endLine; line++)
        {
            int lineEndPos, nextLineStart;
            findLineEnd(startPos, true, lineEndPos, nextLineStart);
            startPos = nextLineStart;
            if (startPos >= bufLen)
            {
                if (line == 0 || (lineStarts_[line - 1] != bufLen && lineEndPos != nextLineStart))
                {
                    lineStarts_[line] = bufLen;
                    line++;
                }
                break;
            }
            lineStarts_[line] = startPos;
        }

        for (; line <= endLine; line++) lineStarts_[line] = -1;
    }

    void updateLineStarts(int pos, int charsInserted, int charsDeleted,
        int linesInserted, int linesDeleted, out int scrolled)
    {
        int nVisLines = nVisibleLines_;
        int charDelta = charsInserted - charsDeleted;
        int lineDelta = linesInserted - linesDeleted;

        if (pos + charsDeleted < firstChar_)
        {
            topLineNum_ += lineDelta;
            for (int i = 0; i < nVisLines && lineStarts_[i] != -1; i++)
                lineStarts_[i] += charDelta;
            firstChar_ += charDelta;
            lastChar_ += charDelta;
            scrolled = 0;
            return;
        }

        if (pos < firstChar_)
        {
            int lineOfEnd;
            if (positionToLine(pos + charsDeleted, lineOfEnd) && ++lineOfEnd < nVisLines
                && lineStarts_[lineOfEnd] != -1)
            {
                topLineNum_ = max(1, topLineNum_ + lineDelta);
                firstChar_ = rewindLines(lineStarts_[lineOfEnd] + charDelta, lineOfEnd);
            }
            else
            {
                if (topLineNum_ > nBufferLines_ + lineDelta)
                {
                    topLineNum_ = 1;
                    firstChar_ = 0;
                }
                else
                {
                    firstChar_ = skipLines(0, topLineNum_ - 1, true);
                }
            }
            calcLineStarts(0, nVisLines - 1);
            calcLastChar();
            scrolled = 1;
            return;
        }

        if (pos <= lastChar_)
        {
            int lineOfPos;
            positionToLine(pos, lineOfPos);
            if (lineDelta == 0)
            {
                for (int i = lineOfPos + 1; i < nVisLines && lineStarts_[i] != -1; i++)
                    lineStarts_[i] += charDelta;
            }
            else if (lineDelta > 0)
            {
                for (int i = nVisLines - 1; i >= lineOfPos + lineDelta + 1; i--)
                    lineStarts_[i] = lineStarts_[i - lineDelta] + (lineStarts_[i - lineDelta] == -1 ? 0 : charDelta);
            }
            else
            {
                for (int i = max(0, lineOfPos + 1); i < nVisLines + lineDelta; i++)
                    lineStarts_[i] = lineStarts_[i - lineDelta] + (lineStarts_[i - lineDelta] == -1 ? 0 : charDelta);
            }
            if (linesInserted >= 0)
                calcLineStarts(lineOfPos + 1, lineOfPos + linesInserted);
            if (lineDelta < 0)
                calcLineStarts(nVisLines + lineDelta, nVisLines);
            calcLastChar();
            scrolled = 0;
            return;
        }

        if (emptyVlines())
        {
            int lineOfPos;
            positionToLine(pos, lineOfPos);
            calcLineStarts(lineOfPos, lineOfPos + linesInserted);
            calcLastChar();
            scrolled = 0;
            return;
        }

        scrolled = 0;
    }

    void calcLastChar()
    {
        int i = nVisibleLines_ - 1;
        while (i >= 0 && lineStarts_[i] == -1) i--;
        lastChar_ = i < 0 ? 0 : lineEnd(lineStarts_[i], true);
    }

    bool positionToLine(int pos, out int lineNum)
    {
        lineNum = 0;
        if (pos < firstChar_) return false;
        if (pos > lastChar_)
        {
            if (emptyVlines())
            {
                if (lastChar_ < buffer_.length())
                {
                    if (!positionToLine(lastChar_, lineNum)) return false; // consistency-check failure
                    lineNum++;
                    return lineNum <= nVisibleLines_ - 1;
                }
                else
                {
                    positionToLine(buffer_.prevCharClipped(lastChar_), lineNum);
                    return true;
                }
            }
            return false;
        }

        for (int i = nVisibleLines_ - 1; i >= 0; i--)
        {
            if (lineStarts_[i] != -1 && pos >= lineStarts_[i])
            {
                lineNum = i;
                return true;
            }
        }
        return false;
    }

    double stringWidth(const(char)[] str, int length, int style)
    {
        Font font;
        Fontsize fsize;
        if (nStyles_ != 0 && (style & styleLookupMask) != 0)
        {
            int si = (style & styleLookupMask) - 'A';
            if (si < 0) si = 0;
            else if (si >= nStyles_) si = nStyles_ - 1;
            font = styleTable_[si].font;
            fsize = styleTable_[si].size;
        }
        else
        {
            font = textfont_;
            fsize = textsize_;
        }
        fl_font(font, fsize);
        return width(str, length);
    }

    // -- Scrollbar callbacks -----------------------------------------------

    private void hScrollbarCb(Scrollbar b)
    {
        if (cast(int) b.value() == horizOffset_) return;
        scroll(topLineNum_, cast(int) b.value());
    }

    private void vScrollbarCb(Scrollbar b)
    {
        if (cast(int) b.value() == topLineNum_) return;
        scroll(cast(int) b.value(), horizOffset_);
    }

    private void updateVScrollbar()
    {
        vScrollBar_.value(topLineNum_, nVisibleLines_, 1,
            nBufferLines_ + 1 + ((continuousWrap_ && wrapMarginPix_) ? 0 : 1));
        vScrollBar_.linesize(3);
    }

    private void updateHScrollbar()
    {
        int sliderMax = max(longestVline(), textArea_.w + horizOffset_);
        hScrollBar_.value(horizOffset_, textArea_.w, 0, sliderMax);
    }

    // -- Buffer callbacks --------------------------------------------------

    private void bufferPredeleteCb(int pos, int nDeleted)
    {
        if (continuousWrap_)
            measureDeletedLines(pos, nDeleted);
        else
            suppressResync_ = false;
    }

    private void bufferModifiedCb(int pos, int nInserted, int nDeleted, int nRestyled, const(char)[] deletedText)
    {
        int oldFirstChar = firstChar_;
        int origCursorPos = cursorPos_;
        int wrapModStart = 0, wrapModEnd = 0;
        int linesInserted, linesDeleted;

        if (nInserted != 0 || nDeleted != 0)
            cursorPreferredXPos_ = -1;

        if (continuousWrap_)
            findWrapRange(deletedText, pos, nInserted, nDeleted, wrapModStart, wrapModEnd, linesInserted, linesDeleted);
        else
        {
            linesInserted = nInserted == 0 ? 0 : buffer_.countLines(pos, pos + nInserted);
            linesDeleted = nDeleted == 0 ? 0 : countlines(deletedText);
        }

        int scrolled;
        if (nInserted != 0 || nDeleted != 0)
        {
            if (continuousWrap_)
                updateLineStarts(wrapModStart, wrapModEnd - wrapModStart,
                    nDeleted + pos - wrapModStart + (wrapModEnd - (pos + nInserted)),
                    linesInserted, linesDeleted, scrolled);
            else
                updateLineStarts(pos, nInserted, nDeleted, linesInserted, linesDeleted, scrolled);
        }
        else
        {
            scrolled = 0;
        }

        if (maintainingAbsoluteTopLineNumber() && (nInserted != 0 || nDeleted != 0))
        {
            if (deletedText !is null && (pos + nDeleted < oldFirstChar))
                absTopLineNum_ += buffer_.countLines(pos, pos + nInserted) - countlines(deletedText);
            else if (pos < oldFirstChar)
                resetAbsoluteTopLineNumber();
        }

        nBufferLines_ += linesInserted - linesDeleted;

        if (cursorToHint_ != noHint)
        {
            cursorPos_ = cursorToHint_;
            cursorToHint_ = noHint;
        }
        else if (cursorPos_ > pos)
        {
            if (cursorPos_ < pos + nDeleted) cursorPos_ = pos;
            else cursorPos_ += nInserted - nDeleted;
        }

        displayNeedsRecalc();

        if (!visibleR()) return;

        if (scrolled != 0)
        {
            damage(damageExpose);
            if (styleBuffer_ !is null) styleBuffer_.primarySelection().selected(false);
            return;
        }

        int startDispPos = continuousWrap_ ? wrapModStart : pos;

        if (origCursorPos == startDispPos && cursorPos_ != startDispPos)
            startDispPos = min(startDispPos, buffer_.prevCharClipped(origCursorPos));

        int endDispPos;
        if (linesInserted == linesDeleted)
        {
            if (nInserted == 0 && nDeleted == 0)
                endDispPos = pos + nRestyled;
            else if (continuousWrap_)
                endDispPos = wrapModEnd;
            else
                endDispPos = buffer_.nextChar(buffer_.lineEnd(pos + nInserted));

            if (linesInserted > 1)
                damage(damageExpose);
        }
        else
        {
            endDispPos = buffer_.nextChar(lastChar_);
        }

        if (styleBuffer_ !is null)
            extendRangeForStyles(startDispPos, endDispPos);

        redisplayRange(startDispPos, endDispPos);
    }

    // -- Continuous-wrap engine ----------------------------------------------

    int measureVline(int visLineNum)
    {
        int lineLen = vlineLength(visLineNum);
        int lineStartPos = lineStarts_[visLineNum];
        if (lineStartPos < 0 || lineLen == 0) return 0;
        return handleVline(HandleMode.getWidth, lineStartPos, lineLen, 0, 0, 0, 0, 0, 0);
    }

    int longestVline()
    {
        int longest = 0;
        foreach (i; 0 .. nVisibleLines_)
            longest = max(longest, measureVline(i));
        return longest;
    }

    bool emptyVlines() const
    {
        return nVisibleLines_ > 0 && lineStarts_[nVisibleLines_ - 1] == -1;
    }

    int vlineLength(int visLineNum)
    {
        if (visLineNum < 0 || visLineNum >= nVisibleLines_) return 0;
        int lineStartPos = lineStarts_[visLineNum];
        if (lineStartPos == -1) return 0;
        if (visLineNum + 1 >= nVisibleLines_) return lastChar_ - lineStartPos;
        int nextLineStart = lineStarts_[visLineNum + 1];
        if (nextLineStart == -1) return lastChar_ - lineStartPos;
        int nextLineStartMinus1 = buffer_.prevChar(nextLineStart);
        if (wrapUsesCharacter(nextLineStartMinus1)) return nextLineStartMinus1 - lineStartPos;
        return nextLineStart - lineStartPos;
    }

    int xyToPosition(int X, int Y, PositionType posType = PositionType.characterPos)
    {
        int fontHeight = maxsize_;
        int visLineNum = (Y - textArea_.y) / fontHeight;
        if (visLineNum < 0) return firstChar_;
        if (visLineNum >= nVisibleLines_) visLineNum = nVisibleLines_ - 1;

        int lineStartPos = lineStarts_[visLineNum];
        if (lineStartPos == -1) return buffer_.length();

        int lineLen = vlineLength(visLineNum);
        HandleMode mode = (posType == PositionType.cursorPos) ? HandleMode.findCursorIndex : HandleMode.findIndex;
        return handleVline(mode, lineStartPos, lineLen, 0, 0, 0, 0, textArea_.x, X);
    }

    void xyToRowcol(int X, int Y, out int row, out int column, PositionType posType = PositionType.characterPos)
    {
        int fontHeight = maxsize_;
        int fontWidth = tmpFontWidth;

        row = (Y - textArea_.y) / fontHeight;
        if (row < 0) row = 0;
        if (row >= nVisibleLines_) row = nVisibleLines_ - 1;

        column = ((X - textArea_.x) + horizOffset_ + (posType == PositionType.cursorPos ? fontWidth / 2 : 0)) / fontWidth;
        if (column < 0) column = 0;
    }

    private void absoluteTopLineNumber(int oldFirstChar)
    {
        if (maintainingAbsoluteTopLineNumber() && buffer_ !is null)
        {
            if (firstChar_ < oldFirstChar)
                absTopLineNum_ -= buffer_.countLines(firstChar_, oldFirstChar);
            else
                absTopLineNum_ += buffer_.countLines(oldFirstChar, firstChar_);
        }
    }

    private bool maintainingAbsoluteTopLineNumber() const
    {
        return continuousWrap_ && (lineNumWidth_ != 0 || needAbsTopLineNum_);
    }

    private void resetAbsoluteTopLineNumber()
    {
        absTopLineNum_ = 1;
        absoluteTopLineNumber(0);
    }

    bool positionToLinecol(int pos, out int lineNum, out int column)
    {
        if (continuousWrap_)
        {
            if (!maintainingAbsoluteTopLineNumber() || pos < firstChar_ || pos > lastChar_) return false;
            lineNum = absTopLineNum_ + buffer_.countLines(firstChar_, pos);
            column = buffer_.countDisplayedCharacters(buffer_.lineStart(pos), pos);
            return true;
        }

        bool retVal = positionToLine(pos, lineNum);
        if (retVal)
        {
            column = buffer_.countDisplayedCharacters(lineStarts_[lineNum], pos);
            lineNum += topLineNum_;
        }
        return retVal;
    }

    private bool scrollImpl(int topLineNum, int horizOffset)
    {
        if (topLineNum > nBufferLines_ + 3 - nVisibleLines_)
            topLineNum = nBufferLines_ + 3 - nVisibleLines_;
        if (topLineNum < 1) topLineNum = 1;

        if (horizOffset > longestVline() - textArea_.w)
            horizOffset = longestVline() - textArea_.w;
        if (horizOffset < 0) horizOffset = 0;

        if (horizOffset_ == horizOffset && topLineNum_ == topLineNum) return false;

        offsetLineStarts(topLineNum);
        horizOffset_ = horizOffset;

        damage(damageExpose);
        return true;
    }

    private void extendRangeForStyles(ref int startpos, ref int endpos)
    {
        auto sel = styleBuffer_.primarySelection();
        bool extended = false;

        if (sel.selected())
        {
            if (sel.start() < startpos)
            {
                startpos = buffer_.utf8Align(sel.start());
                extended = true;
            }
            if (sel.end() > endpos)
            {
                endpos = buffer_.utf8Align(sel.end());
                extended = true;
            }
        }

        if (extended) endpos = buffer_.lineEnd(endpos) + 1;
    }

    private void findWrapRange(const(char)[] deletedText, int pos, int nInserted, int nDeleted,
        out int modRangeStart, out int modRangeEnd, out int linesInserted, out int linesDeleted)
    {
        int nVisLines = nVisibleLines_;
        int countFrom, countTo;
        int visLineNum = 0, nLines = 0;
        int lineStart;

        if (pos >= firstChar_ && pos <= lastChar_)
        {
            int i;
            for (i = nVisLines - 1; i > 0; i--)
                if (lineStarts_[i] != -1 && pos >= lineStarts_[i]) break;
            if (i > 0) { countFrom = lineStarts_[i - 1]; visLineNum = i - 1; }
            else countFrom = buffer_.lineStart(pos);
        }
        else
        {
            countFrom = buffer_.lineStart(pos);
        }

        lineStart = countFrom;
        modRangeStart = countFrom;
        for (;;)
        {
            int retPos, retLines, retLineStart, retLineEnd;
            wrappedLineCounter(buffer_, lineStart, buffer_.length(), 1, true, 0,
                retPos, retLines, retLineStart, retLineEnd);
            if (retPos >= buffer_.length())
            {
                countTo = buffer_.length();
                modRangeEnd = countTo;
                if (retPos != retLineEnd) nLines++;
                break;
            }
            else
            {
                lineStart = retPos;
            }
            nLines++;
            if (lineStart > pos + nInserted && buffer_.charAt(buffer_.prevChar(lineStart)) == '\n')
            {
                countTo = lineStart;
                modRangeEnd = lineStart;
                break;
            }

            if (suppressResync_) continue;

            if (lineStart <= pos)
            {
                while (visLineNum < nVisLines && lineStarts_[visLineNum] < lineStart) visLineNum++;
                if (visLineNum < nVisLines && lineStarts_[visLineNum] == lineStart)
                {
                    countFrom = lineStart;
                    nLines = 0;
                    if (visLineNum + 1 < nVisLines && lineStarts_[visLineNum + 1] != -1)
                        modRangeStart = min(pos, buffer_.prevChar(lineStarts_[visLineNum + 1]));
                    else
                        modRangeStart = countFrom;
                }
                else
                    modRangeStart = min(modRangeStart, buffer_.prevChar(lineStart));
            }
            else if (lineStart > pos + nInserted)
            {
                int adjLineStart = lineStart - nInserted + nDeleted;
                while (visLineNum < nVisLines && lineStarts_[visLineNum] < adjLineStart) visLineNum++;
                if (visLineNum < nVisLines && lineStarts_[visLineNum] != -1 && lineStarts_[visLineNum] == adjLineStart)
                {
                    countTo = lineEnd(lineStart, true);
                    modRangeEnd = lineStart;
                    break;
                }
            }
        }
        linesInserted = nLines;

        if (suppressResync_)
        {
            linesDeleted = nLinesDeleted_;
            suppressResync_ = false;
            return;
        }

        int length = (pos - countFrom) + nDeleted + (countTo - (pos + nInserted));
        auto deletedTextBuf = new TextBuffer(length);
        deletedTextBuf.copy(buffer_, countFrom, pos, 0);
        if (nDeleted != 0) deletedTextBuf.insert(pos - countFrom, deletedText);
        deletedTextBuf.copy(buffer_, pos + nInserted, countTo, pos - countFrom + nDeleted);

        int retPos2, retLines2, retLineStart2, retLineEnd2;
        wrappedLineCounter(deletedTextBuf, 0, length, int.max, true, countFrom,
            retPos2, retLines2, retLineStart2, retLineEnd2, false);
        linesDeleted = retLines2;
        suppressResync_ = false;
    }

    private void measureDeletedLines(int pos, int nDeleted)
    {
        int nVisLines = nVisibleLines_;
        int countFrom, lineStart;
        int nLines = 0;

        if (pos >= firstChar_ && pos <= lastChar_)
        {
            int i;
            for (i = nVisLines - 1; i > 0; i--)
                if (lineStarts_[i] != -1 && pos >= lineStarts_[i]) break;
            countFrom = (i > 0) ? lineStarts_[i - 1] : buffer_.lineStart(pos);
        }
        else
        {
            countFrom = buffer_.lineStart(pos);
        }

        lineStart = countFrom;
        for (;;)
        {
            int retPos, retLines, retLineStart, retLineEnd;
            wrappedLineCounter(buffer_, lineStart, buffer_.length(), 1, true, 0,
                retPos, retLines, retLineStart, retLineEnd);
            if (retPos >= buffer_.length())
            {
                if (retPos != retLineEnd) nLines++;
                break;
            }
            else
            {
                lineStart = retPos;
            }
            nLines++;
            if (lineStart > pos + nDeleted && buffer_.charAt(lineStart - 1) == '\n') break;
        }
        nLinesDeleted_ = nLines;
        suppressResync_ = true;
    }

    /**
     * Counts forward from startPos to either maxPos or maxLines
     * (whichever is reached first), computing word-wrap breaks along
     * the way. buf may be a different (partial-copy) buffer than
     * buffer_ -- styleBufOffset then gives the offset to add before
     * indexing into styleBuffer_ for style lookups.
     */
    void wrappedLineCounter(TextBuffer buf, int startPos, int maxPos, int maxLines,
        bool startPosIsLineStart, int styleBufOffset,
        out int retPos, out int retLines, out int retLineStart, out int retLineEnd,
        bool countLastLineMissingNewLine = true)
    {
        int wrapMarginPix = wrapMarginPix_ != 0 ? wrapMarginPix_ : textArea_.w;

        int curLineStart = startPosIsLineStart ? startPos : lineStart(startPos);

        int colNum = 0;
        double width = 0;
        int nLines = 0;

        int p = curLineStart;
        while (p < buf.length())
        {
            uint c = buf.charAt(p);

            if (c == '\n')
            {
                if (p >= maxPos)
                {
                    retPos = maxPos; retLines = nLines; retLineStart = curLineStart; retLineEnd = maxPos;
                    return;
                }
                nLines++;
                int p1 = buf.nextChar(p);
                if (nLines >= maxLines)
                {
                    retPos = p1; retLines = nLines; retLineStart = p1; retLineEnd = p;
                    return;
                }
                curLineStart = p1;
                colNum = 0;
                width = 0;
            }
            else
            {
                colNum++;
                width += measureProportionalCharacter(buf, p, cast(int) width, p + styleBufOffset);
            }

            if (width > wrapMarginPix)
            {
                bool foundBreak = false;
                int b = p;
                int newLineStart = 0;
                for (b = p; b >= curLineStart; b = buf.prevChar(b))
                {
                    uint bc = buf.charAt(b);
                    if (bc == '\t' || bc == ' ')
                    {
                        newLineStart = buf.nextChar(b);
                        colNum = 0;
                        width = 0;
                        int iMax = buf.nextChar(p);
                        for (int ii = buf.nextChar(b); ii < iMax; ii = buf.nextChar(ii))
                        {
                            width += measureProportionalCharacter(buf, ii, cast(int) width, ii + styleBufOffset);
                            colNum++;
                        }
                        foundBreak = true;
                        break;
                    }
                }
                if (b < curLineStart) b = curLineStart;
                if (!foundBreak)
                {
                    newLineStart = max(p, buf.nextChar(curLineStart));
                    colNum++;
                    if (b >= buf.length())
                        width = 0;
                    else
                        width = measureProportionalCharacter(buf, b, 0, p + styleBufOffset);
                }
                if (p >= maxPos)
                {
                    retPos = maxPos;
                    retLines = maxPos < newLineStart ? nLines : nLines + 1;
                    retLineStart = maxPos < newLineStart ? curLineStart : newLineStart;
                    retLineEnd = maxPos;
                    return;
                }
                nLines++;
                if (nLines >= maxLines)
                {
                    retPos = foundBreak ? buf.nextChar(b) : max(p, buf.nextChar(curLineStart));
                    retLines = nLines;
                    retLineStart = curLineStart;
                    retLineEnd = foundBreak ? b : p;
                    return;
                }
                curLineStart = newLineStart;
            }

            p = buf.nextChar(p);
        }

        retPos = buf.length();
        retLines = nLines;
        if (countLastLineMissingNewLine && colNum > 0)
        {
            // NOTE: reproduces an apparent FLTK type-confusion bug
            // verbatim (src/Fl_Text_Display.cxx's wrapped_line_counter(),
            // near `*retLines = buf->next_char(*retLines);`): next_char()
            // expects a *buffer byte position*, but retLines here holds a
            // *line count*. See FLTK_ISSUES.md -- not "fixed" to
            // `retLines + 1` here on purpose; faithfully reproducing
            // FLTK behavior (bugs included) is this port's point.
            retLines = buf.nextChar(retLines);
        }
        retLineStart = curLineStart;
        retLineEnd = buf.length();
    }

    private void findLineEnd(int startPos, bool startPosIsLineStart, out int lineEndOut, out int nextLineStartOut)
    {
        if (!continuousWrap_)
        {
            int le = buffer_.lineEnd(startPos);
            int ls = buffer_.nextChar(le);
            lineEndOut = le;
            nextLineStartOut = min(buffer_.length(), ls);
            return;
        }
        int retLines, retLineStart;
        wrappedLineCounter(buffer_, startPos, buffer_.length(), 1, startPosIsLineStart, 0,
            nextLineStartOut, retLines, retLineStart, lineEndOut);
    }

    private double measureProportionalCharacter(TextBuffer buf, int realPos, int xPix, int stylePos)
    {
        uint ch = buf.charAt(realPos);
        if (ch == '\t')
        {
            int tab = cast(int) colToX(buffer_.tabDistance());
            if (tab <= 0) tab = 1;
            return ((xPix / tab) + 1) * tab - xPix;
        }
        int charLen = buf.nextChar(realPos) - realPos;
        int style = 0;
        if (styleBuffer_ !is null) style = cast(ubyte) styleBuffer_.byteAt(stylePos);
        return stringWidth(buf.textRange(realPos, realPos + charLen), charLen, style);
    }

    private bool wrapUsesCharacter(int lineEndPos)
    {
        if (!continuousWrap_ || lineEndPos == buffer_.length()) return true;
        uint c = buffer_.charAt(lineEndPos);
        return c == '\n' || ((c == '\t' || c == ' ') && lineEndPos + 1 < buffer_.length());
    }
}

// ---------------------------------------------------------------------
// Module-level helpers mirroring FLTK's `friend` functions
// (fl_text_drag_prepare()/fl_text_drag_me()), which need access to
// TextDisplay's private drag/cursor state. In D, module-level privacy
// (not class-level, unlike C++) already gives these direct access since
// they live in this same module -- no `friend` declaration needed.
// `package(fl)` visibility (rather than `private`) is deliberate: the
// module comment on fl_text_drag_me() FLTK notes it's also used by
// Fl_Text_Editor for Shift+arrow-key drag-selection, and this port's
// eventual fl.text_editor (out of scope for this task) will need it
// too.
// ---------------------------------------------------------------------

/// Adjusts dragPos_/cursorPos_ so a shift-click/shift-arrow-key
/// extends the existing selection from the correct end, rather than
/// collapsing it. Returns true if it changed anything.
package(fl) bool flTextDragPrepare(int pos, int key, TextDisplay d)
{
    if (d.buffer_.selected())
    {
        int start, end;
        d.buffer_.selectionPosition(start, end);
        if ((d.dragPos_ != start || d.cursorPos_ != end) && (d.dragPos_ != end || d.cursorPos_ != start))
        {
            if (pos != -1)
            {
                if (pos < start) { d.cursorPos_ = start; d.dragPos_ = end; }
                else { d.cursorPos_ = end; d.dragPos_ = start; }
            }
            else if (key != -1)
            {
                switch (key)
                {
                case home:
                case left:
                case up:
                case pageUp:
                    d.dragPos_ = end; d.cursorPos_ = start;
                    break;
                default:
                    d.dragPos_ = start; d.cursorPos_ = end;
                    break;
                }
            }
            else
            {
                d.dragPos_ = start;
                d.cursorPos_ = end;
            }
            return true;
        }
    }
    return false;
}

/// Extends the selection/cursor to pos according to d.dragType_
/// (character/word/line granularity). Used both for mouse drags and
/// (eventually, in fl.text_editor) Shift+arrow-key selection.
package(fl) void flTextDragMe(int pos, TextDisplay d)
{
    if (d.dragType_ == DragType.dragChar)
    {
        if (pos >= d.dragPos_) d.buffer_.select(d.dragPos_, pos);
        else d.buffer_.select(pos, d.dragPos_);
        d.insertPosition(pos);
    }
    else if (d.dragType_ == DragType.dragWord)
    {
        if (pos >= d.dragPos_)
        {
            d.insertPosition(d.wordEnd(pos));
            d.buffer_.select(d.wordStart(d.dragPos_), d.wordEnd(pos));
        }
        else
        {
            d.insertPosition(d.wordStart(pos));
            d.buffer_.select(d.wordStart(pos), d.wordEnd(d.dragPos_));
        }
    }
    else if (d.dragType_ == DragType.dragLine)
    {
        if (pos >= d.dragPos_)
        {
            d.insertPosition(d.buffer_.lineEnd(pos) + 1);
            d.buffer_.select(d.buffer_.lineStart(d.dragPos_), d.buffer_.lineEnd(pos) + 1);
        }
        else
        {
            d.insertPosition(d.buffer_.lineStart(pos));
            d.buffer_.select(d.buffer_.lineStart(pos), d.buffer_.lineEnd(d.dragPos_) + 1);
        }
    }
}

// =======================================================================
// Unit tests -- structural/logic correctness only (no real pixel output
// is possible yet, see the module comment). Every test constructing a
// FlGroup/TextDisplay brackets with FlGroup.current(null), and every test
// touching handle()/focus ends with fl.core.resetForTest(), per
// CONVENTIONS.md.
// =======================================================================

unittest
{
    // Construction defaults, and buffer() attachment updates layout
    // bookkeeping (nBufferLines_ etc, indirectly observed via
    // scrollRow()/insertPosition()).
    FlGroup.current(null);

    auto td = new TextDisplay(0, 0, 300, 200);
    assert(td.box() == Boxtype.downFrame);
    assert(td.buffer() is null);
    assert(td.insertPosition() == 0);
    assert(td.cursorStyle() == CursorStyle.normalCursor);
    assert(td.scrollbarWidth() > 0); // falls back to fl.core.scrollbarSize()

    auto buf = new TextBuffer();
    buf.text("line one\nline two\nline three");
    td.buffer(buf);
    assert(td.buffer() is buf);
    assert(td.scrollRow() == 1);

    FlGroup.current(null);
}

unittest
{
    // Line-start/line-end/count-lines, unwrapped.
    FlGroup.current(null);

    auto td = new TextDisplay(0, 0, 300, 200);
    auto buf = new TextBuffer();
    buf.text("abc\ndefgh\ni");
    td.buffer(buf);

    assert(td.lineStart(0) == 0);
    assert(td.lineStart(2) == 0);
    assert(td.lineStart(5) == 4); // inside "defgh"
    assert(td.lineEnd(0, true) == 3); // the '\n' after "abc"
    assert(td.countLines(0, buf.length(), true) == 2); // two real newlines

    FlGroup.current(null);
}

unittest
{
    // Word wrap: a long single line, wrapped at a narrow pixel margin,
    // spans multiple visible lines.
    FlGroup.current(null);

    auto td = new TextDisplay(0, 0, 200, 200);
    auto buf = new TextBuffer();
    buf.text("one two three four five six seven eight nine ten");
    td.buffer(buf);

    td.wrapMode(WrapMode.wrapAtPixel, 60); // narrow margin forces several wraps
    td.recalcDisplay();

    // With wrapping on, the single real line should be reported as
    // spanning more than one (soft-wrapped) line.
    assert(td.countLines(0, buf.length(), true) > 1);

    FlGroup.current(null);
}

unittest
{
    // Scroll bookkeeping: scroll()+recalcDisplay() updates
    // scrollRow()/scrollCol(), and the vertical scrollbar's value/
    // bounds track topLineNum_/nBufferLines_.
    FlGroup.current(null);

    auto td = new TextDisplay(0, 0, 300, 100); // short: forces a vertical scrollbar
    auto buf = new TextBuffer();
    string text;
    foreach (i; 0 .. 50) text ~= format("line %d\n", i);
    buf.text(text);
    td.buffer(buf);
    td.recalcDisplay();

    assert(td.scrollRow() == 1);
    td.scroll(5, 0);
    td.recalcDisplay();
    assert(td.scrollRow() == 5);

    FlGroup.current(null);
}

unittest
{
    // Position <-> (row, column)/(x, y) conversions produce *some*
    // deterministic answer (see the module comment on fl.draw's
    // placeholder font metrics) and round-trip sensibly.
    FlGroup.current(null);

    auto td = new TextDisplay(0, 0, 300, 200);
    auto buf = new TextBuffer();
    buf.text("hello\nworld");
    td.buffer(buf);
    td.recalcDisplay();

    int lineNum, col;
    assert(td.positionToLinecol(0, lineNum, col));
    assert(lineNum == 1 && col == 0);
    assert(td.positionToLinecol(8, lineNum, col)); // 'r' in "world" -> line 2, col 2
    assert(lineNum == 2 && col == 2);

    int X, Y;
    assert(td.positionToXy(0, X, Y));
    int pos = td.xyToPosition(X, Y, PositionType.characterPos);
    assert(pos == 0);

    FlGroup.current(null);
}

unittest
{
    // Cursor movement (called directly -- Fl_Text_Display's own
    // handle() doesn't process arrow keys; that's Fl_Text_Editor's job,
    // out of scope for this module).
    FlGroup.current(null);

    auto td = new TextDisplay(0, 0, 300, 200);
    auto buf = new TextBuffer();
    buf.text("abc\ndef\nghi");
    td.buffer(buf);
    td.recalcDisplay();

    assert(td.moveRight());
    assert(td.insertPosition() == 1);
    assert(td.moveLeft());
    assert(td.insertPosition() == 0);
    assert(!td.moveLeft()); // already at start

    td.insertPosition(1); // inside "abc"
    assert(td.moveDown());
    assert(td.insertPosition() == 5); // inside "def", same column

    assert(td.moveUp());
    assert(td.insertPosition() == 1); // back inside "abc"

    FlGroup.current(null);
}

unittest
{
    // Mouse click -> cursor position, drag -> selection.
    FlGroup.current(null);
    fl.core.focus(null);

    auto td = new TextDisplay(0, 0, 300, 200);
    auto buf = new TextBuffer();
    buf.text("hello world");
    td.buffer(buf);
    td.recalcDisplay();

    int x0, y0;
    td.positionToXy(0, x0, y0);
    int x5, y5;
    td.positionToXy(5, x5, y5); // just past "hello"

    fl.core.eX_ = x0;
    fl.core.eY_ = y0;
    assert(td.handle(Event.push) == 1);
    assert(td.insertPosition() == 0);
    assert(!buf.selected());

    fl.core.eX_ = x5;
    fl.core.eY_ = y5;
    assert(td.handle(Event.drag) == 1);
    assert(buf.selected());
    int selStart, selEnd;
    assert(buf.selectionPosition(selStart, selEnd));
    assert(selStart == 0 && selEnd == 5);

    assert(td.handle(Event.release) == 1);

    fl.core.resetForTest();
    FlGroup.current(null);
}

unittest
{
    // Dragging below textArea_ starts the auto-scroll timer
    // (scrollTimerCb()), which keeps firing on its own while the
    // pointer stays outside; releasing cancels it.
    FlGroup.current(null);
    fl.core.focus(null);

    auto td = new TextDisplay(0, 0, 300, 200);
    auto buf = new TextBuffer();
    // Enough lines that scrolling down is actually possible.
    buf.text("line 1\nline 2\nline 3\nline 4\nline 5\nline 6\nline 7\nline 8\n"
        ~ "line 9\nline 10\nline 11\nline 12\nline 13\nline 14\nline 15\n");
    td.buffer(buf);
    td.recalcDisplay();

    fl.core.eX_ = 10;
    fl.core.eY_ = 5;
    assert(td.handle(Event.push) == 1);

    // Drag below the text area (its bottom edge is well within the
    // widget's 200px height) -- starts the repeating scroll timer.
    fl.core.eX_ = 10;
    fl.core.eY_ = 195;
    assert(td.handle(Event.drag) == 1);
    assert(td.scrollDirection_ != 0);
    assert(fl.core.hasTimeout(&td.scrollTimerCb));

    int topBefore = td.topLineNum_;

    import core.thread : Thread;
    import core.time : msecs;
    Thread.sleep(150.msecs);
    fl.core.processTimeouts();
    assert(fl.core.hasTimeout(&td.scrollTimerCb)); // rescheduled itself

    td.recalcDisplay(); // scroll()'s topLineNumHint_ is applied deferred
    assert(td.topLineNum_ > topBefore); // scrolled down

    assert(td.handle(Event.release) == 1);
    assert(td.scrollDirection_ == 0);
    assert(!fl.core.hasTimeout(&td.scrollTimerCb));

    fl.core.resetForTest();
    FlGroup.current(null);
}

unittest
{
    // REGRESSION TEST for a confirmed FLTK bug (see
    // FLTK_ISSUES.md's entry on Fl_Text_Display's scroll_direction/
    // etc file-scope statics): with per-instance drag-scroll state,
    // destroying a *different* TextDisplay while another one is
    // mid-drag-scroll must NOT disturb the one still scrolling.
    //
    // With scrollDirection_ etc as shared module-level
    // globals, matching FLTK, this exact scenario would corrupt b's
    // state: destroying `a` would zero the shared flag even though it
    // belongs to `b`, while b's real timer keeps running underneath the
    // now-wrong flag.
    FlGroup.current(null);
    fl.core.focus(null);

    auto a = new TextDisplay(0, 0, 300, 200);
    auto bufA = new TextBuffer();
    bufA.text("a\n");
    a.buffer(bufA);

    auto b = new TextDisplay(0, 0, 300, 200);
    auto bufB = new TextBuffer();
    bufB.text("line 1\nline 2\nline 3\nline 4\nline 5\nline 6\nline 7\nline 8\n"
        ~ "line 9\nline 10\nline 11\nline 12\nline 13\nline 14\nline 15\n");
    b.buffer(bufB);
    b.recalcDisplay();

    // b starts a real drag-scroll.
    fl.core.eX_ = 10; fl.core.eY_ = 5;
    b.handle(Event.push);
    fl.core.eX_ = 10; fl.core.eY_ = 195;
    b.handle(Event.drag);
    assert(b.scrollDirection_ != 0);
    assert(fl.core.hasTimeout(&b.scrollTimerCb));

    // a was never dragging -- its own scrollDirection_ is (and stays) 0.
    assert(a.scrollDirection_ == 0);
    destroy(a);

    // b's state is completely unaffected by a's destruction.
    assert(b.scrollDirection_ != 0);
    assert(fl.core.hasTimeout(&b.scrollTimerCb));

    b.handle(Event.release);
    assert(b.scrollDirection_ == 0);
    assert(!fl.core.hasTimeout(&b.scrollTimerCb));

    fl.core.resetForTest();
    FlGroup.current(null);
}

unittest
{
    // Style-buffer / StyleTableEntry resolution: positionStyle() picks
    // the right style-table entry independent of color rendering, and
    // reflects the primary selection.
    FlGroup.current(null);

    auto td = new TextDisplay(0, 0, 300, 200);
    auto buf = new TextBuffer();
    buf.text("abcdef");
    td.buffer(buf);

    auto styleBuf = new TextBuffer();
    styleBuf.text("AABBAA"); // 'A' -> style 0, 'B' -> style 1
    immutable StyleTableEntry[2] styles = [
        StyleTableEntry(foregroundColor, helvetica, 14, 0, backgroundColor),
        StyleTableEntry(red, helveticaBold, 14, 0, backgroundColor),
    ];
    td.highlightData(styleBuf, styles[], '\0', null);

    int style0 = td.positionStyle(0, 6, 0); // 'a' -> style entry 0 ('A')
    assert((style0 & styleLookupMask) == 'A');
    int style2 = td.positionStyle(0, 6, 2); // 'c' -> style entry 1 ('B')
    assert((style2 & styleLookupMask) == 'B');

    buf.select(0, 2);
    int styleSelected = td.positionStyle(0, 6, 0);
    assert((styleSelected & stylePrimaryMask) != 0);

    FlGroup.current(null);
}

unittest
{
    // Resize handling recomputes text-area/scrollbar geometry.
    FlGroup.current(null);

    auto td = new TextDisplay(0, 0, 300, 200);
    auto buf = new TextBuffer();
    buf.text("hello");
    td.buffer(buf);
    td.recalcDisplay();

    td.resize(0, 0, 600, 400);
    td.recalcDisplay();

    // The widget's own bounds changed...
    assert(td.w() == 600 && td.h() == 400);
    // ...and recalcDisplay() re-derived a text area consistent with the
    // new size (no vertical scrollbar needed for 5 chars in a 400px
    // tall area, so the visible-line count should have grown).
    assert(td.h() == 400);

    FlGroup.current(null);
}

unittest
{
    // highlightData()'s highlight-triggered redisplay path, and
    // detaching a buffer (removes callbacks without crashing on
    // ~this()).
    FlGroup.current(null);

    auto td = new TextDisplay(0, 0, 300, 200);
    auto buf = new TextBuffer();
    buf.text("first buffer");
    td.buffer(buf);
    assert(td.buffer() is buf);

    auto buf2 = new TextBuffer();
    buf2.text("second buffer");
    td.buffer(buf2); // detaches buf, attaches buf2
    assert(td.buffer() is buf2);

    destroy(td);

    FlGroup.current(null);
}

unittest
{
    // Ctrl+C copies the current selection to the in-process clipboard
    // (fl.core.copy()); Ctrl+A selects everything and copies that too
    // (slot 0, PRIMARY -- distinct from Ctrl+C's slot 1, CLIPBOARD).
    // Previously stubbed TODOs, now that fl.core has a real clipboard.
    FlGroup.current(null);
    fl.core.resetForTest();

    auto td = new TextDisplay(0, 0, 300, 200);
    auto buf = new TextBuffer();
    buf.text("hello world");
    td.buffer(buf);

    // Ctrl+C with nothing selected: consumes the key, copies nothing.
    fl.core.copy("sentinel", 1);
    fl.core.eKeysym_ = cast(Keysym) 'c';
    fl.core.eState_ = stateCtrl;
    assert(td.handle(Event.keyDown) == 1);

    buf.select(0, 5); // "hello"
    fl.core.eKeysym_ = cast(Keysym) 'c';
    fl.core.eState_ = stateCtrl;
    assert(td.handle(Event.keyDown) == 1);

    // Deliver it to a second widget via paste() to observe what got
    // copied, the same round-trip fl.input_'s own clipboard test uses.
    import fl.input : Input;
    auto recv = new Input(0, 0, 100, 20);
    fl.core.paste(recv, 1);
    assert(recv.value() == "hello");

    fl.core.eKeysym_ = cast(Keysym) 'a';
    fl.core.eState_ = stateCtrl;
    assert(td.handle(Event.keyDown) == 1);
    assert(buf.selected());
    auto recv2 = new Input(0, 0, 100, 20);
    fl.core.paste(recv2, 0);
    assert(recv2.value() == "hello world");

    destroy(td);
    fl.core.resetForTest();
    FlGroup.current(null);
}
