/*
 * Ported from FL/Fl_Input.H + src/Fl_Input.cxx (FLTK 1.5.0). The concrete text-input widget -- everything
 * Fl_Input_ (fl.input_.d) doesn't provide: draw(), handle(), and the
 * keybinding logic (kf_*() methods) that turns raw key events into
 * calls against Fl_Input_'s editing primitives.
 *
 * Deliberate deviations from FLTK, on top of the ones already
 * documented in fl.input_'s module comment (string-buffer value_, no
 * IME, simplified next/prevComposedChar, in-process-only clipboard):
 *
 *  - **Drag-and-drop** is real, backed by `fl.core.dnd()` (see
 *    `PORTING.md`'s `FL/Fl.H`/`FL/x.H` rows), the same XDND mechanism
 *    `fl.text_display`/`fl.text_editor` use. Ported
 *    faithfully, from `Fl_Input::handle()`'s own `FL_PUSH`/
 *    `FL_DRAG`/`FL_RELEASE`/`FL_DND_ENTER`/`FL_DND_DRAG`/`FL_DND_LEAVE`/
 *    `FL_DND_RELEASE` cases: a click that lands inside the existing
 *    selection (probed via a save/restore around `handleMouse()`, so
 *    the probe itself never disturbs the real selection) starts a real
 *    XDND drag on the next genuine `Event.drag` (debounced against
 *    `eventIsClick()` the same way FLTK is); dropping text back
 *    onto the same field removes the dragged range, dropping onto a
 *    different widget/app leaves this field's own selection untouched.
 *    FLTK's 4 function-local `static`s (`dnd_save_position`/
 *    `dnd_save_mark`/`drag_start`/`dnd_save_focus`) are ported the same
 *    way as `fl.slider`'s `offcenter`/`fl.roller`'s `ipos` -- plain D
 *    `static` locals inside `handle()`, genuinely shared across every
 *    `Input` instance FLTK too (only one drag can be in progress
 *    process-wide), not per-instance fields.
 *  - handleRmb() (Fl_Input::handle_rmb()) is now fully ported,
 *    including the real Cut/Copy/Paste popup, built on fl.menu_item/
 *    fl.menu_popup (same popup engine fl.menu_button/fl.choice/
 *    fl.text_display's own handleRmb() use). The picked action is
 *    recovered via array-index arithmetic rather than FLTK's
 *    Fl_Menu_Item::argument(), same simplification fl.text_display's
 *    handleRmb() already documents (this port's MenuItem has no
 *    user_data()/argument() slot).
 *  - `Fl::option(Fl::OPTION_ARROW_FOCUS)` is backed by `fl.core.option()`
 *    -- every NORMAL_INPUT_MOVE / `kf_move_char_left()`/`kf_move_char_right()`
 *    call site below reads it live via `normalInputMove()` instead of
 *    a hardcoded default, see that function's own doc comment.
 *  - legal_fp_chars: FLTK builds this list at runtime from the C
 *    locale's decimal_point/mon_decimal_point/positive_sign/
 *    negative_sign (so e.g. a European locale's comma-as-decimal-point
 *    types into a float field). No locale-awareness infrastructure
 *    exists in this port, so it's just the fixed ".eE+-" FLTK falls
 *    back to without HAVE_LOCALECONV.
 *  - Fl::screen_driver()->input_widget_handle_key() IS ported, as
 *    screenDriverHandleKey() below -- inlined directly into this class
 *    rather than added as a separate driver hierarchy, matching this
 *    project's established "no driver abstraction until a second
 *    implementation needs one" rule (see fl.platform_x11's own module
 *    note). Only `Fl_Cocoa_Screen_Driver` overrides it (for Emacs-style
 *    bindings); `Fl_X11_Screen_Driver` never does, so X11 uses
 *    `Fl_Screen_Driver`'s *base* implementation, which is where Delete,
 *    Home/End, Page Up/Down, Ctrl+Backspace/Delete (word deletion),
 *    Ctrl+Left/Right (word movement), and -- critically -- plain
 *    arrow-key movement within the field all actually live. Without
 *    it, none of those keys would do anything (arrow keys would fall
 *    through to Tab-like focus navigation instead, since
 *    kf_move_char_left()/right()/kf_lines_up()/down() would never be
 *    called).
 */
module fl.input;

import std.ascii : isDigit, isHexDigit, isWhite;
import std.algorithm.searching : canFind;

import fl.enumerations;
import fl.input_ : Input_;
import fl.core;
import fl.menu_item : MenuItem;
import fl.menu_popup;
import fl.widget : Widget;

/// Ported from the `Fl::option(Fl::OPTION_ARROW_FOCUS) ? 0 : 1`
/// expression every FLTK `kf_move_char_left()`-style caller below
/// adds to a computed shift position, backed by `fl.core.option()`.
private int normalInputMove() { return option(Option.arrowFocus) ? 0 : 1; }

private char ctrlChar(char x) { return cast(char)(x ^ 0x40); }

private enum string legalFpChars = ".eE+-";

class Input : Input_
{
    /// Ported from Fl_Input::cut_menu_text/copy_menu_text/
    /// paste_menu_text -- translatable labels for handleRmb()'s popup.
    static string cutMenuText = "Cut";
    static string copyMenuText = "Copy"; /// ditto
    static string pasteMenuText = "Paste"; /// ditto

    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
    }

    override void draw()
    {
        if (inputType() == inputHidden) return;
        Boxtype b = box();
        if (damage() & damageAll) drawBox(b, color());
        drawtext(x() + fl.core.boxDx(b), y() + fl.core.boxDy(b),
            w() - fl.core.boxDw(b), h() - fl.core.boxDh(b));
    }

    // -------------------------------------------------------------
    // shift_position()/shift_up_down_position()
    // -------------------------------------------------------------

    private int shiftPosition(int p)
    {
        return insertPosition(p, fl.core.eventShift() ? mark() : p);
    }

    private int shiftUpDownPosition(int p)
    {
        return upDownPosition(p, fl.core.eventShift());
    }

    // -------------------------------------------------------------
    // kf_*() keyboard functions
    // -------------------------------------------------------------

    private int kfLinesUp(int repeatNum)
    {
        int i = insertPosition();
        if (lineStart(i) == 0) return normalInputMove();
        while (repeatNum--)
        {
            i = lineStart(i);
            if (i == 0) break;
            i--;
        }
        shiftUpDownPosition(lineStart(i));
        return 1;
    }

    private int kfLinesDown(int repeatNum)
    {
        int i = insertPosition();
        if (lineEnd(i) >= size()) return normalInputMove();
        while (repeatNum--)
        {
            i = lineEnd(i);
            if (i >= size()) break;
            i++;
        }
        shiftUpDownPosition(i);
        return 1;
    }

    private int kfPageUp() { return kfLinesUp(linesPerPage()); }
    private int kfPageDown() { return kfLinesDown(linesPerPage()); }

    private int kfInsertToggle()
    {
        if (readonly()) { fl.core.beep(); return 1; }
        return 1; // TODO: needs insert mode (not ported FLTK either)
    }

    private int kfDeleteWordRight()
    {
        if (readonly()) { fl.core.beep(); return 1; }
        if (mark() != insertPosition()) return cut();
        cut(insertPosition(), wordEnd(insertPosition()));
        return 1;
    }

    private int kfDeleteWordLeft()
    {
        if (readonly()) { fl.core.beep(); return 1; }
        if (mark() != insertPosition()) return cut();
        cut(wordStart(insertPosition()), insertPosition());
        return 1;
    }

    private int kfDeleteSol()
    {
        if (readonly()) { fl.core.beep(); return 1; }
        if (mark() != insertPosition()) return cut();
        cut(lineStart(insertPosition()), insertPosition());
        return 1;
    }

    private int kfDeleteEol()
    {
        if (readonly()) { fl.core.beep(); return 1; }
        if (mark() != insertPosition()) return cut();
        cut(insertPosition(), lineEnd(insertPosition()));
        return 1;
    }

    private int kfDeleteCharRight()
    {
        if (readonly()) { fl.core.beep(); return 1; }
        if (mark() != insertPosition()) cut();
        else
        {
            int next = insertPosition() + nextCharLen(insertPosition());
            replace(insertPosition(), next, null);
        }
        return 1;
    }

    private int kfDeleteCharLeft()
    {
        if (readonly()) { fl.core.beep(); return 1; }
        if (mark() != insertPosition()) cut();
        else
        {
            int before = prevCharStart(insertPosition());
            replace(insertPosition(), before, null);
        }
        return 1;
    }

    private int kfMoveSol()
    {
        return shiftPosition(lineStart(insertPosition())) + normalInputMove();
    }

    private int kfMoveEol()
    {
        return shiftPosition(lineEnd(insertPosition())) + normalInputMove();
    }

    private int kfClearEol()
    {
        if (readonly()) { fl.core.beep(); return 1; }
        if (insertPosition() >= size()) return 0;
        int i = lineEnd(insertPosition());
        if (i == insertPosition() && i < size()) i++;
        cut(insertPosition(), i);
        return copyCuts();
    }

    private int kfMoveCharLeft()
    {
        // Ported from FLTK's `Fl::option(Fl::OPTION_ARROW_FOCUS) ? i
        // : 1`, `i` being `shift_position()`'s own return value: with
        // Arrow Focus on, `Input.insertPosition(p, m)` (`fl.input_.d`)
        // returns `0` exactly when the cursor was already at the
        // position being moved to (a real text boundary, e.g. already
        // at column 0) -- that's the signal `kfLinesUp()`/`kfLinesDown()`
        // above forward through `normalInputMove()` so
        // `FlGroup.navigation()` can move focus to the next field, and
        // this function needs to forward it the same way so Left/Right
        // can leave a field once the cursor reaches its edge.
        int i = shiftPosition(prevCharStart(insertPosition()));
        return option(Option.arrowFocus) ? i : 1;
    }

    private int kfMoveCharRight()
    {
        int i = shiftPosition(insertPosition() + nextCharLen(insertPosition()));
        return option(Option.arrowFocus) ? i : 1;
    }

    private int kfMoveWordLeft()
    {
        shiftPosition(wordStart(insertPosition()));
        return 1;
    }

    private int kfMoveWordRight()
    {
        shiftPosition(wordEnd(insertPosition()));
        return 1;
    }

    private int kfMoveUpAndSol()
    {
        if (lineStart(insertPosition()) == insertPosition() && insertPosition() > 0)
            return shiftPosition(lineStart(insertPosition() - 1)) + normalInputMove();
        else
            return shiftPosition(lineStart(insertPosition())) + normalInputMove();
    }

    private int kfMoveDownAndEol()
    {
        if (lineEnd(insertPosition()) == insertPosition() && insertPosition() < size())
            return shiftPosition(lineEnd(insertPosition() + 1)) + normalInputMove();
        else
            return shiftPosition(lineEnd(insertPosition())) + normalInputMove();
    }

    private int kfTop() { shiftPosition(0); return 1; }
    private int kfBottom() { shiftPosition(size()); return 1; }

    private int kfSelectAll() { insertPosition(0, size()); return 1; }

    private int kfUndo()
    {
        if (readonly()) { fl.core.beep(); return 1; }
        return undo();
    }

    private int kfRedo()
    {
        if (readonly()) { fl.core.beep(); return 1; }
        return redo();
    }

    private int kfCopy() { return copy(1); }

    private int kfPaste()
    {
        if (readonly()) { fl.core.beep(); return 1; }
        fl.core.paste(this, 1);
        return 1;
    }

    private int kfCopyCut()
    {
        if (readonly()) { fl.core.beep(); return 1; }
        copy(1);
        return cut();
    }

    // -------------------------------------------------------------
    // screen_driver()->input_widget_handle_key()
    // -------------------------------------------------------------

    /// Ported from the base Fl_Screen_Driver::input_widget_handle_key()
    /// (src/Fl_Screen_Driver.cxx) -- see the module comment for why
    /// this (despite the "platform" framing) is exactly what X11 uses.
    /// Returns -1 for "not one of these keys, fall through to
    /// handle_key()'s own switch" (matching FLTK's -1 sentinel).
    private int screenDriverHandleKey(Keysym key, int mods, bool shift)
    {
        switch (key)
        {
        case fl.enumerations.deleteKey:
        {
            bool selected = insertPosition() != mark();
            if (mods == 0 && shift && selected) return kfCopyCut();
            if (mods == 0 && shift && !selected) return kfDeleteCharRight();
            if (mods == 0) return kfDeleteCharRight();
            if (mods == stateCtrl) return kfDeleteWordRight();
            return 0;
        }

        case left:
            if (mods == 0) return kfMoveCharLeft();
            if (mods == stateCtrl) return kfMoveWordLeft();
            if (mods == stateMeta) return kfMoveCharLeft();
            return 0;

        case right:
            if (mods == 0) return kfMoveCharRight();
            if (mods == stateCtrl) return kfMoveWordRight();
            if (mods == stateMeta) return kfMoveCharRight();
            return 0;

        case up:
            if (mods == 0) return kfLinesUp(1);
            if (mods == stateCtrl) return kfMoveUpAndSol();
            return 0;

        case down:
            if (mods == 0) return kfLinesDown(1);
            if (mods == stateCtrl) return kfMoveDownAndEol();
            return 0;

        case pageUp:
            if (mods == 0 || mods == stateCtrl || mods == stateAlt) return kfPageUp();
            return 0;

        case pageDown:
            if (mods == 0 || mods == stateCtrl || mods == stateAlt) return kfPageDown();
            return 0;

        case home:
            if (mods == 0) return kfMoveSol();
            if (mods == stateCtrl) return kfTop();
            return 0;

        case end:
            if (mods == 0) return kfMoveEol();
            if (mods == stateCtrl) return kfBottom();
            return 0;

        case backSpace:
            if (mods == 0) return kfDeleteCharLeft();
            if (mods == stateCtrl) return kfDeleteWordLeft();
            return 0;

        default:
            break;
        }
        return -1;
    }

    // -------------------------------------------------------------
    // handle_key()
    // -------------------------------------------------------------

    /// Ported from Fl_Input::handle_key(). See the module comment for
    /// what's skipped (IME marked-text underline touch-up).
    protected int handleKey()
    {
        char ascii = fl.core.eventText().length > 0 ? fl.core.eventText()[0] : '\0';

        int del;
        if (fl.core.compose(del))
        {
            if (inputType() == inputFloat || inputType() == inputInt)
            {
                fl.core.composeReset();

                int ip = insertPosition() < mark() ? insertPosition() : mark();
                bool legal =
                       (ip == 0 && (ascii == '+' || ascii == '-'))
                    || (ascii >= '0' && ascii <= '9')
                    || (ip == 1 && index(0) == '0' && (ascii == 'x' || ascii == 'X'))
                    || (ip > 1 && index(0) == '0' && (index(1) == 'x' || index(1) == 'X')
                        && ((ascii >= 'A' && ascii <= 'F') || (ascii >= 'a' && ascii <= 'f')))
                    || (inputType() == inputFloat && ascii != 0 && legalFpChars.canFind(ascii));

                if (legal)
                {
                    if (readonly()) fl.core.beep();
                    else replace(insertPosition(), mark(), [ascii]);
                }
                return 1;
            }

            if (del || fl.core.eventLength())
            {
                if (readonly()) fl.core.beep();
                else replace(insertPosition(), del ? insertPosition() - del : mark(), fl.core.eventText());
            }
            return 1;
        }

        int mods = fl.core.eventState() & (stateMeta | stateCtrl | stateAlt);
        bool shift = fl.core.eventShift();
        bool multiline = inputType() == inputMultiline;

        int retval = screenDriverHandleKey(fl.core.eventKey(), mods, shift);
        if (retval >= 0) return retval;

        switch (fl.core.eventKey())
        {
        case fl.enumerations.insert:
            if (mods == 0 && shift) return kfPaste();
            if (mods == 0) return kfInsertToggle();
            if (mods == stateCtrl) return kfCopy();
            return 0;

        case enter:
        case kpEnter:
            if (when() & whenEnterKey)
            {
                insertPosition(size(), 0);
                maybeDoCallback(CallbackReason.enterKey);
                return 1;
            }
            else if (multiline && !readonly())
            {
                return replace(insertPosition(), mark(), "\n");
            }
            return 0;

        case tab:
            if (mods == 0 && !shift && !tabNav() && multiline) break; // insert tab character
            return 0;

        case 'a':
            if (mods == stateCommand) return kfSelectAll();
            break;
        case 'c':
            if (mods == stateCommand) return kfCopy();
            break;
        case 'v':
            if (mods == stateCommand) return kfPaste();
            break;
        case 'x':
            if (mods == stateCommand) return kfCopyCut();
            break;
        case 'z':
            if (mods == stateCommand && !shift)
            {
                if (!kfUndo()) fl.core.beep();
                return 1;
            }
            if (mods == stateCommand && shift)
            {
                if (!kfRedo()) fl.core.beep();
                return 1;
            }
            break;

        default:
            break;
        }

        switch (ascii)
        {
        case ctrlChar('H'):
            return kfDeleteCharLeft();
        case ctrlChar('I'):
        case ctrlChar('J'):
        case ctrlChar('L'):
        case ctrlChar('M'):
            if (readonly()) { fl.core.beep(); return 1; }
            if (inputType() != inputFloat && inputType() != inputInt)
                return replace(insertPosition(), mark(), [ascii]);
            break;
        default:
            break;
        }

        return 0;
    }

    /**
     * Ported from Fl_Input::handle_rmb(): adjusts the selection for a
     * right-click at the current event position (clicking inside an
     * existing selection keeps it, clicking whitespace selects the
     * whitespace run, clicking a word selects the word, clicking past
     * line/buffer end just repositions the cursor), then pops up a
     * real Cut/Copy/Paste menu (readonly() deactivates Cut/Paste) via
     * fl.menu_popup -- same popup engine fl.text_display's own
     * handleRmb() uses, which this is closely modeled on. Picking
     * Cut/Copy/Paste dispatches to kfCopyCut()/kfCopy()/kfPaste()
     * exactly as FLTK's switch on mi->argument() does.
     */
    protected int handleRmb()
    {
        if (fl.core.eventButton() == rightMouse)
        {
            int oldpos = insertPosition(), oldmark = mark();
            Boxtype b = box();
            handleMouse(x() + fl.core.boxDx(b), y() + fl.core.boxDy(b),
                w() - fl.core.boxDw(b), h() - fl.core.boxDh(b), false);
            int newpos = insertPosition();
            if ((oldpos < newpos && oldmark > newpos)
                || (oldmark < newpos && oldpos > newpos)
                || inputType() == inputSecret)
            {
                // clicked inside the existing selection -- keep it
                insertPosition(oldpos, oldmark);
            }
            else if (index(newpos) == 0 || index(newpos) == '\n')
            {
                insertPosition(newpos, newpos);
            }
            else if (isWhite(cast(char) index(newpos)))
            {
                int op = newpos;
                while (op > 0 && isWhite(cast(char) index(op - 1))) op--;
                int om = newpos + 1;
                while (om < size() && isWhite(cast(char) index(om))) om++;
                insertPosition(op, om);
            }
            else
            {
                insertPosition(wordStart(newpos), wordEnd(newpos));
            }

            auto items = new MenuItem[4]; // Cut, Copy, Paste, sentinel
            items[0] = MenuItem(cutMenuText);
            items[1] = MenuItem(copyMenuText);
            items[2] = MenuItem(pasteMenuText);
            if (readonly())
            {
                items[0].deactivate();
                items[2].deactivate();
            }

            if (window() !is null) window().cursor(Cursor.default_);

            // Deliberate departure from FLTK: rather than compute
            // a screen position from topWindowOffset()+eventX()/
            // eventY() (FLTK's own approach, `rmb_menu->popup(
            // Fl::event_x(), Fl::event_y())`), this always asks for
            // the real, current mouse position directly. The computed
            // approach is fragile for any Input whose own (x,y) isn't
            // simply relative to its immediate parent in the usual way
            // -- concretely, fl.value_input.ValueInput's embedded
            // Input shares its outer widget's absolute coordinates
            // rather than being offset from it, which made the
            // computed position land nowhere near the actual click.
            // Simpler and more robust to just ask the server directly;
            // the menu still opens under the pointer either way.
            int screenX, screenY;
            fl.core.getMouse(screenX, screenY);

            auto picked = fl.menu_popup.popup(&items[0], screenX, screenY);
            if (picked !is null)
            {
                switch (cast(int) (picked - &items[0]) + 1)
                {
                case 1:
                    if (inputType() != inputSecret) kfCopyCut();
                    break;
                case 2:
                    if (inputType() != inputSecret) kfCopy();
                    break;
                case 3:
                    kfPaste();
                    break;
                default:
                    break;
                }
            }
        }
        return 1;
    }

    // -------------------------------------------------------------
    // handle()
    // -------------------------------------------------------------

    /// Ported from Fl_Input::handle(int). See the module comment for
    /// what's simplified (FL_UNFOCUS's IME mark-reset, already handled
    /// -- as a no-op -- by Input_.handletext()) and for the
    /// drag-and-drop state's shared-static shape.
    override int handle(Event event)
    {
        static int dndSavePosition_, dndSaveMark_, dragStart_ = -1;
        static Widget dndSaveFocus_;

        switch (event)
        {
        case Event.focus:
            switch (fl.core.eventKey())
            {
            case right: insertPosition(0); break;
            case left: insertPosition(size()); break;
            case down: upDownPosition(0); break;
            case up: upDownPosition(lineStart(size())); break;
            case tab: insertPosition(size(), 0); break;
            default: insertPosition(insertPosition(), mark()); break;
            }
            break;

        case Event.keyDown:
            if (fl.core.eventKey() == tab
                && !fl.core.eventShift()
                && !tabNav()
                && inputType() == inputMultiline
                && size() > 0
                && ((mark() == 0 && insertPosition() == size()) || (insertPosition() == 0 && mark() == size())))
            {
                if (mark() > insertPosition()) insertPosition(mark());
                else insertPosition(insertPosition());
                return 1;
            }
            else
            {
                if (activeR() && window() !is null && this is fl.core.belowmouse())
                    window().cursor(Cursor.none);
                return handleKey();
            }

        case Event.push:
            if (fl.core.dndTextOps() && fl.core.eventButton() != rightMouse)
            {
                int oldpos = insertPosition(), oldmark = mark();
                Boxtype b = box();
                handleMouse(x() + fl.core.boxDx(b), y() + fl.core.boxDy(b),
                    w() - fl.core.boxDw(b), h() - fl.core.boxDh(b), false);
                int newpos = insertPosition();
                insertPosition(oldpos, oldmark);
                if (fl.core.focus() is this && !fl.core.eventShift() && inputType() != inputSecret
                    && ((newpos >= mark() && newpos < insertPosition())
                        || (newpos >= insertPosition() && newpos < mark())))
                {
                    // user clicked in the selection, may be trying to drag
                    dragStart_ = newpos;
                    return 1;
                }
                dragStart_ = -1;
            }

            if (fl.core.focus() !is this)
            {
                fl.core.focus(this);
                handle(Event.focus);
            }
            if (fl.core.eventButton() == rightMouse)
                return handleRmb();
            break;

        case Event.drag:
            if (fl.core.dndTextOps() && dragStart_ >= 0)
            {
                if (fl.core.eventIsClick()) return 1; // debounce the mouse
                dndSavePosition_ = insertPosition();
                dndSaveMark_ = mark();
                dndSaveFocus_ = this;
                copy(0);
                fl.core.dnd();
                return 1;
            }
            break;

        case Event.release:
            if (fl.core.eventButton() == middleMouse)
            {
                fl.core.eventIsClick(false);
                fl.core.paste(this, 0);
            }
            else if (fl.core.eventButton() == rightMouse)
                return 1;
            else if (!fl.core.eventIsClick())
                copy(0);
            else if (fl.core.eventIsClick() && dragStart_ >= 0)
            {
                insertPosition(dragStart_, dragStart_);
                dragStart_ = -1;
            }
            else if (fl.core.eventClicks())
                copy(0);

            if (readonly()) doCallback(CallbackReason.released);
            return 1;

        case Event.dndEnter:
            fl.core.belowmouse(this); // send the leave events first
            if (dndSaveFocus_ !is this)
            {
                dndSavePosition_ = insertPosition();
                dndSaveMark_ = mark();
                dndSaveFocus_ = fl.core.focus();
                fl.core.focus(this);
                handle(Event.focus);
            }
            goto case Event.dndDrag;

        case Event.dndDrag:
        {
            Boxtype b = box();
            handleMouse(x() + fl.core.boxDx(b), y() + fl.core.boxDy(b),
                w() - fl.core.boxDw(b), h() - fl.core.boxDh(b), false);
            return 1;
        }

        case Event.dndLeave:
            insertPosition(dndSavePosition_, dndSaveMark_);
            if (dndSaveFocus_ !is null && dndSaveFocus_ !is this)
            {
                fl.core.focus(dndSaveFocus_);
                handle(Event.unfocus);
            }
            if (fl.core.firstWindow() !is null)
                fl.core.firstWindow().cursor(Cursor.move);
            dndSaveFocus_ = null;
            return 1;

        case Event.dndRelease:
            if (dndSaveFocus_ is this)
            {
                if (!readonly())
                {
                    int oldPosition = insertPosition();
                    if (dndSaveMark_ > dndSavePosition_)
                    {
                        int tmp = dndSaveMark_;
                        dndSaveMark_ = dndSavePosition_;
                        dndSavePosition_ = tmp;
                    }
                    replace(dndSaveMark_, dndSavePosition_, "");
                    if (oldPosition > dndSavePosition_)
                        insertPosition(oldPosition - (dndSavePosition_ - dndSaveMark_));
                    else
                        insertPosition(oldPosition);
                }
            }
            else if (dndSaveFocus_ !is null)
                dndSaveFocus_.handle(Event.unfocus);
            dndSaveFocus_ = null;
            takeFocus();
            return 1;

        default:
            break;
        }
        Boxtype b = box();
        return handletext(event, x() + fl.core.boxDx(b), y() + fl.core.boxDy(b),
            w() - fl.core.boxDw(b), h() - fl.core.boxDh(b));
    }
}

// ===========================================================================
// Unit tests
// ===========================================================================

unittest
{
    import fl.group : FlGroup;

    FlGroup.current(null);
    fl.core.resetForTest();

    auto inp = new Input(0, 0, 100, 20);
    assert(inp.box() == Boxtype.downBox);
    assert(inp.value() == "");

    inp.value("hello");
    assert(inp.value() == "hello");

    FlGroup.current(null);
    fl.core.resetForTest();
}

unittest
{
    // FL_KEYBOARD: typed characters insert at the cursor.
    import fl.group : FlGroup;

    FlGroup.current(null);
    fl.core.resetForTest();

    auto inp = new Input(0, 0, 100, 20);
    fl.core.focus(inp);

    fl.core.eText_ = "a";
    fl.core.eKeysym_ = cast(Keysym) 'a';
    assert(inp.handle(Event.keyDown) == 1);
    assert(inp.value() == "a");

    fl.core.eText_ = "b";
    fl.core.eKeysym_ = cast(Keysym) 'b';
    assert(inp.handle(Event.keyDown) == 1);
    assert(inp.value() == "ab");

    fl.core.eText_ = "";
    fl.core.focus(null);
    FlGroup.current(null);
    fl.core.resetForTest();
}

unittest
{
    // Backspace deletes the character to the left of the cursor.
    import fl.group : FlGroup;

    FlGroup.current(null);
    fl.core.resetForTest();

    auto inp = new Input(0, 0, 100, 20);
    inp.value("abc");
    fl.core.focus(inp);

    fl.core.eText_ = "\x08"; // ctrl('H')
    fl.core.eKeysym_ = backSpace;
    assert(inp.handle(Event.keyDown) == 1);
    assert(inp.value() == "ab");

    fl.core.eText_ = "";
    fl.core.focus(null);
    FlGroup.current(null);
    fl.core.resetForTest();
}

unittest
{
    // FL_FOCUS via FL_Tab selects the whole field (mark 0, cursor at
    // end), matching Fl_Input::handle()'s FL_FOCUS/FL_Tab case.
    import fl.group : FlGroup;

    FlGroup.current(null);
    fl.core.resetForTest();

    auto inp = new Input(0, 0, 100, 20);
    inp.value("hello");
    inp.insertPosition(2);

    fl.core.eKeysym_ = tab;
    assert(inp.handle(Event.focus) == 1);
    assert(inp.insertPosition() == 5);
    assert(inp.mark() == 0);

    fl.core.eKeysym_ = 0;
    FlGroup.current(null);
    fl.core.resetForTest();
}

unittest
{
    // screenDriverHandleKey(): arrow keys move the cursor within the
    // field (not focus navigation), Shift+arrow extends the selection,
    // and Delete removes the character to the right of the cursor.
    // Regression test for the bug where these all silently did nothing
    // -- see the module comment on Fl::screen_driver()->
    // input_widget_handle_key() having been wrongly skipped as
    // "Mac-only" at first.
    import fl.group : FlGroup;

    FlGroup.current(null);
    fl.core.resetForTest();

    auto inp = new Input(0, 0, 100, 20);
    inp.value("hello");
    fl.core.focus(inp);
    fl.core.eText_ = ""; // arrow/delete keys carry no event text on a real X server

    inp.insertPosition(5); // cursor at the end, after value() moved it there
    fl.core.eKeysym_ = left;
    assert(inp.handle(Event.keyDown) == 1);
    assert(inp.insertPosition() == 4); // moved left by one, still inside the field
    assert(inp.mark() == 4);           // and collapsed the selection (no shift)

    fl.core.eState_ = stateShift;
    fl.core.eKeysym_ = left;
    assert(inp.handle(Event.keyDown) == 1);
    assert(inp.insertPosition() == 3);
    assert(inp.mark() == 4); // Shift+Left extended the selection instead of collapsing it
    fl.core.eState_ = 0;

    inp.insertPosition(1, 1);
    fl.core.eKeysym_ = fl.enumerations.deleteKey;
    assert(inp.handle(Event.keyDown) == 1);
    assert(inp.value() == "hllo"); // deleted the 'e' to the right of the cursor

    fl.core.eText_ = "";
    fl.core.eKeysym_ = 0;
    fl.core.focus(null);
    FlGroup.current(null);
    fl.core.resetForTest();
}

unittest
{
    // normalInputMove(): reads the real, live fl.core.Option.arrowFocus.
    // Exercised via kfLinesUp() with the cursor already on the first
    // line: Up arrow returns "handled" (1, cursor movement absorbs the
    // key) when arrowFocus is off -- this port's long-standing default
    // behavior -- and "not handled" (0, falls through to focus
    // navigation instead) once explicitly switched on.
    import fl.group : FlGroup;

    FlGroup.current(null);
    fl.core.resetForTest();

    auto inp = new Input(0, 0, 100, 20);
    inp.value("hello");
    fl.core.focus(inp);
    fl.core.eText_ = "";
    inp.insertPosition(0); // already at the first (only) line

    fl.core.eKeysym_ = up;
    assert(fl.core.option(fl.core.Option.arrowFocus) == false); // default
    assert(inp.handle(Event.keyDown) == 1);

    fl.core.option(fl.core.Option.arrowFocus, true);
    assert(inp.handle(Event.keyDown) == 0);

    fl.core.eKeysym_ = 0;
    fl.core.focus(null);
    FlGroup.current(null);
    fl.core.resetForTest();
}

unittest
{
    // kfMoveCharLeft()/kfMoveCharRight(): same "arrowFocus gates whether
    // a boundary hit falls through to focus navigation" contract the
    // Up-arrow test above already covers for kfLinesUp() -- this locks
    // it in for Left/Right too.
    import fl.group : FlGroup;

    FlGroup.current(null);
    fl.core.resetForTest();

    auto inp = new Input(0, 0, 100, 20);
    inp.value("hello");
    fl.core.focus(inp);
    fl.core.eText_ = "";
    inp.insertPosition(0); // already at the leftmost position

    fl.core.eKeysym_ = left;
    assert(fl.core.option(fl.core.Option.arrowFocus) == false); // default
    assert(inp.handle(Event.keyDown) == 1);

    fl.core.option(fl.core.Option.arrowFocus, true);
    assert(inp.handle(Event.keyDown) == 0);

    inp.insertPosition(inp.size()); // now at the rightmost position
    fl.core.eKeysym_ = right;
    assert(inp.handle(Event.keyDown) == 0);

    fl.core.option(fl.core.Option.arrowFocus, false);
    assert(inp.handle(Event.keyDown) == 1);

    fl.core.eKeysym_ = 0;
    fl.core.focus(null);
    FlGroup.current(null);
    fl.core.resetForTest();
}
