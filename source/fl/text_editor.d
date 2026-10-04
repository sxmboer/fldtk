/*
 * Ported from FL/Fl_Text_Editor.H + src/Fl_Text_Editor.cxx (FLTK 1.5.0,
 * ~/Repositories/fltk). `Fl_Text_Editor` -> `TextEditor` adds editing
 * (as opposed to `fl.text_display`'s read-only display/selection/
 * scrolling) on top of `TextDisplay`: a keyboard-event dispatcher built
 * around a per-instance (and a process-wide global) linked list of
 * key/modifier-state -> handler-function bindings, plus the ~25 default
 * `kf_*` handler functions themselves (insert/backspace/enter/arrow-key
 * movement in four modifier combinations/select-all/undo/redo/cut/copy/
 * paste).
 *
 * `Key_Binding`'s FLTK `Key_Func` is `int (*)(int, Fl_Text_Editor*)`
 * -- a plain C function pointer with no accompanying `void*` user-data
 * slot (unlike `Fl_Callback`), so CLAUDE.md's function-pointer -> D-
 * delegate convention doesn't apply here: there's no captured state to
 * eliminate. `KeyFunc` stays a plain D `function` pointer, and
 * `Key_Binding`'s `new`/`delete`d linked-list nodes become a GC-managed
 * `class` with no manual freeing anywhere FLTK had to `delete` one
 * (`remove_key_binding()`/`remove_all_key_bindings()`/`~Fl_Text_Editor()`
 * all just drop references here; the GC reclaims unreferenced nodes on
 * its own).
 *
 * `global_key_bindings` is a genuine process-wide mutable static
 * (FLTK: `static Key_Binding* global_key_bindings`), same hazard
 * category CLAUDE.md flags for `FlGroup.current_`/`fl.core`'s event-state
 * globals. Nothing in this module's own unittests mutates it (they all
 * go through a `TextEditor`'s own per-instance `keyBindings_` list
 * instead) specifically to avoid needing a reset hook; a future test
 * that does mutate it must reset it back to `null` afterward.
 *
 * `fl.text_display.TextDisplay` keeps its storage fields `private`
 * (module-scoped in D, unlike C++'s class-scoped `private`/`protected`
 * split) except for the handful FLTK declares `protected:` purely
 * for this module's benefit (drag-selection state, visible-line/
 * scroll-position bookkeeping) -- promoted there to `package(fl)` for
 * exactly that reason; see that module's own comment at the field
 * declarations for the full reasoning.
 *
 * A few gaps remain, each also flagged as a `// TODO:` comment at
 * its point of use:
 *
 * - **IME/marked-text composition** (`Fl::compose()`): `fl.core.compose()` is
 *   real and `handleKey()` calls it first, matching FLTK's own
 *   `Fl_Text_Editor::handle_key()` structure. Still not ported: the
 *   `has_marked_text() && Fl::compose_state`-gated re-selection inside
 *   that same FLTK branch, since `Fl::compose_state` never becomes
 *   non-zero on X11 even in real FLTK -- genuinely dead code,
 *   not a gap.
 * - **Drag-and-drop** (`FL_DND_*` handling here mirrors FLTK) is
 *   real and reachable, via real
 *   XDND (see `fl.core.dnd()`/`fl.platform_x11.dnd()`'s
 *   own rows in `PORTING.md`): `Event.dndEnter`/`dndDrag`/`dndLeave`
 *   route through the ordinary widget tree exactly like mouse motion --
 *   see `fl.group`'s `handle()`, no special per-widget registration
 *   needed. A `TextEditor` dragged into (from another instance's own
 *   `dragStartDnd` handling, see `fl.text_display`'s module note, or
 *   from another application) shows a live insertion-point cursor that
 *   tracks the drag and finalizes via the normal `Event.paste` path on
 *   drop, matching FLTK exactly.
 * - **`Fl::screen_driver()->text_editor_extra_key_bindings`**
 *   (platform-specific extra default bindings, e.g. macOS's Cmd-based
 *   set). No screen-driver abstraction exists in this port (see
 *   `fl.platform_x11`'s module note), so `addDefaultKeyBindings()` only
 *   installs the platform-independent table -- but this isn't actually
 *   a gap for the X11 target: FLTK's own base `Fl_Screen_Driver`
 *   default is `NULL` (`Fl_Screen_Driver.cxx`), and only the Cocoa/
 *   WinAPI drivers ever set it to something real. X11 gets `NULL` in
 *   real FLTK too, so this port matches it exactly as-is;
 *   revisit only once a macOS/Windows driver exists to port the real
 *   platform-specific tables for.
 */
module fl.text_editor;

import fl.enumerations;
import fl.text_display;
import fl.text_buffer : TextBuffer;
import fl.group : FlGroup;
import fl.ask : fl_beep;
import fl.core;

/// Matches in any modifier state (FLTK's `FL_TEXT_EDITOR_ANY_STATE`).
enum textEditorAnyState = -1;

/// A key-function binding callback (FLTK's `Key_Func`). Plain
/// function pointer, not a delegate -- see the module comment for why
/// CLAUDE.md's delegate convention doesn't apply here.
alias KeyFunc = int function(int key, TextEditor editor);

/// One key/state -> function binding, linked-list node (FLTK's
/// `Key_Binding` struct). A `class`, not a `struct`, since every use
/// FLTK is through a pointer/identity, never copied by value
/// (contrast `fl.text_buffer.TextSelection`, which FLTK does copy
/// by value and which is ported as a `struct` for that reason).
private final class KeyBinding
{
    int key;
    int state;
    KeyFunc func;
    KeyBinding next;
}

/**
 * Ported from Fl_Text_Editor -> TextEditor. See the module comment for
 * exactly what's faithfully ported vs. deliberately skipped.
 */
class TextEditor : TextDisplay
{
    private
    {
        bool insertMode_ = true;
        KeyBinding keyBindings_;
        KeyFunc defaultKeyFunction_;
    }

    /// Process-wide default bindings shared by every `TextEditor`
    /// instance (FLTK's `static Key_Binding* global_key_bindings`).
    /// See the module comment's shared-static-hazard note.
    private static KeyBinding globalKeyBindings_;

    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);

        showCursor(true); // buffer() is null here, so this only sets
                           // cursorOn_ -- see fl.text_display's
                           // showCursor(), matching FLTK's direct
                           // `mCursorOn = 1;` assignment exactly.
        insertMode_ = true;
        keyBindings_ = null;
        setFlag(Flag.macUseAccentsMenu);
        needsKeyboard(true);

        addDefaultKeyBindings(keyBindings_);

        defaultKeyFunction_ = &kfDefault;
    }

    /// If non-zero, new text is inserted before the current cursor
    /// position; otherwise new text replaces text at the current cursor
    /// position (overstrike mode).
    void insertMode(bool b) { insertMode_ = b; }
    bool insertMode() const { return insertMode_; }

    /// Enables (val=true) or disables (val=false, the default) Tab
    /// navigating focus to the next widget instead of inserting a tab
    /// character. Implemented, as FLTK notes, as a convenience that
    /// just adjusts the Tab key binding.
    void tabNav(bool val)
    {
        if (val) addKeyBinding(tab, 0, &kfIgnore);
        else removeKeyBinding(tab, 0);
    }

    bool tabNav()
    {
        return boundKeyFunction(tab, 0) == &kfIgnore;
    }

    /// Adds a key/state binding with function f to list.
    void addKeyBinding(int key, int state, KeyFunc f, ref KeyBinding list)
    {
        auto kb = new KeyBinding();
        kb.key = key;
        kb.state = state;
        kb.func = f;
        kb.next = list;
        list = kb;
    }

    /// Adds a key/state binding with function f to this editor's own
    /// binding list.
    void addKeyBinding(int key, int state, KeyFunc f) { addKeyBinding(key, state, f, keyBindings_); }

    /// Removes the key/state binding from list, if present.
    void removeKeyBinding(int key, int state, ref KeyBinding list)
    {
        KeyBinding cur = list, last;
        for (; cur !is null; last = cur, cur = cur.next)
            if (cur.key == key && cur.state == state) break;
        if (cur is null) return;
        if (last !is null) last.next = cur.next;
        else list = cur.next;
        // No `delete cur;` needed (unlike FLTK): the GC reclaims it
        // once nothing (including `list`/`last.next`, both just
        // rewritten above) references it anymore.
    }

    /// Removes the key/state binding from this editor's own binding
    /// list, if present.
    void removeKeyBinding(int key, int state) { removeKeyBinding(key, state, keyBindings_); }

    /// Removes every binding from list.
    void removeAllKeyBindings(ref KeyBinding list) { list = null; }

    /// Removes every binding from this editor's own binding list.
    void removeAllKeyBindings() { removeAllKeyBindings(keyBindings_); }

    /// Adds every built-in default binding (arrow keys, Home/End,
    /// Backspace/Delete, Ctrl+Z/Ctrl+Shift+Z undo/redo, Ctrl+X/C/V/A
    /// cut/copy/paste/select-all, ...) to list.
    void addDefaultKeyBindings(ref KeyBinding list)
    {
        foreach (b; defaultKeyBindingsTable)
            addKeyBinding(b.key, b.state, b.func, list);
    }

    /// Returns the function bound to key/state in list, or null.
    KeyFunc boundKeyFunction(int key, int state, KeyBinding list)
    {
        KeyBinding cur = list;
        for (; cur !is null; cur = cur.next)
            if (cur.key == key && (cur.state == textEditorAnyState || cur.state == state))
                break;
        return cur is null ? null : cur.func;
    }

    /// Returns the function bound to key/state in this editor's own
    /// binding list, or null.
    KeyFunc boundKeyFunction(int key, int state) { return boundKeyFunction(key, state, keyBindings_); }

    /// Sets the fallback function used for keys with no explicit
    /// binding (the default, kfDefault(), inserts/overstrikes a
    /// printable character).
    void defaultKeyFunction(KeyFunc f) { defaultKeyFunction_ = f; }

    /// The `window()->cursor(...)` calls in the `Event.keyDown`/`push`
    /// (right-button) cases -- hiding the cursor while typing, and the
    /// insert/default cursor toggle on right-click, matching
    /// `fl.text_display`'s left-click handling -- are real.
    override int handle(Event event)
    {
        static int dndCursorPos;

        if (buffer() is null) return 0;

        switch (event)
        {
        case Event.focus:
            showCursor(cursorOn()); // redraws the cursor
            if (buffer().selected()) redraw(); // Redraw selections...
            fl.core.focus(this);
            return 1;

        case Event.unfocus:
            showCursor(cursorOn()); // redraws the cursor
            // TODO: IME/marked-text unfocus handling
            // (Fl::screen_driver()->has_marked_text()/resetSpot())
            // isn't ported -- see module comment.
            if (buffer().selected()) redraw(); // Redraw selections...
            goto case Event.hide;

        case Event.hide:
            if (when() & whenRelease) maybeDoCallback(CallbackReason.lostFocus);
            return 1;

        case Event.keyDown:
            // Hide the cursor while typing, matching FLTK --
            // reappears on the next mouse move (Event.enter/move,
            // TextDisplay.handle()). Only when the mouse is actually
            // over this widget right now (`this == Fl::belowmouse()`
            // FLTK), not just whichever widget has keyboard focus.
            if (activeR() && window() !is null && this is fl.core.belowmouse())
                window().cursor(Cursor.none);
            return handleKey();

        case Event.paste:
            if (fl.core.eventText().length == 0)
            {
                fl_beep();
                return 1;
            }
            buffer().removeSelection();
            if (insertMode()) insert(fl.core.eventText());
            else overstrike(fl.core.eventText());
            showInsertPosition();
            setChanged();
            if (when() & whenChanged) doCallback(CallbackReason.changed);
            return 1;

        case Event.enter:
            showCursor(cursorOn());
            return 1;

        case Event.push:
            if (fl.core.eventButton() == middleMouse)
            {
                // Don't let TextDisplay's own handle() see this event --
                // bypass straight to FlGroup's, matching FLTK's
                // explicit `Fl_Group::handle(event)`.
                if (FlGroup.handle(event)) return 1;
                dragType_ = DragType.dragNone;
                if (buffer().selected()) buffer().unselect();
                int pos = xyToPosition(fl.core.eventX(), fl.core.eventY(), PositionType.cursorPos);
                insertPosition(pos);
                fl.core.paste(this, 0);
                fl.core.focus(this);
                setChanged();
                if (when() & whenChanged) doCallback(CallbackReason.changed);
                return 1;
            }

            if (fl.core.eventButton() == rightMouse)
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
                switch (handleRmb(false))
                {
                case 1: kfCut(0, this); break;
                case 2: kfCopy(0, this); break;
                case 3: kfPaste(0, this); break;
                default: break;
                }
                return 1;
            }

            break;

        case Event.shortcut:
            if (!(shortcut() != 0 ? fl.core.testShortcut(cast(uint) shortcut()) : testShortcut()))
                return 0;
            if (fl.core.visibleFocus() && handle(Event.focus))
            {
                fl.core.focus(this);
                return 1;
            }
            break;

        // Simplified drag-and-drop handling, allowing DND onto the
        // scrollbars. See module comment: currently unreachable, since
        // nothing in this port dispatches FL_DND_* events yet.
        case Event.dndEnter: // save the current cursor position
            if (fl.core.visibleFocus() && handle(Event.focus))
                fl.core.focus(this);
            showCursor(cursorOn());
            dndCursorPos = insertPosition();
            goto case Event.dndDrag;

        case Event.dndDrag: // show a temporary insertion cursor
            insertPosition(xyToPosition(fl.core.eventX(), fl.core.eventY(), PositionType.cursorPos));
            return 1;

        case Event.dndLeave: // restore original cursor
            insertPosition(dndCursorPos);
            return 1;

        case Event.dndRelease: // keep insertion cursor, wait for Event.paste
            if (!dragging_) buffer().unselect(); // Event.paste must not destroy a
                                                  // selection dragged in from outside
            return 1;

        default:
            break;
        }

        return super.handle(event);
    }

    protected:

    /// Handles a key press: first tries `fl.core.compose()`'s ordinary-
    /// printable-text path (matching FLTK's own `Fl::compose(del)`
    /// call, first thing in `Fl_Text_Editor::handle_key()`), then falls
    /// back to the global/per-instance key-binding list and
    /// defaultKeyFunction_() for unbound keys with no modifiers held.
    ///
    /// This calls `fl.core.compose()` first, not just the plain
    /// key-binding lookup, because compose() is
    /// FLTK's *primary* path for ordinary printable-text insertion
    /// (any keypress with no Ctrl/Alt/Meta held and a non-control
    /// ASCII byte), and it deliberately does NOT gate on Shift. The
    /// key-binding fallback below does, via `state == 0` on
    /// defaultKeyFunction_ -- so a Shift-combo character (an uppercase
    /// letter, or any shifted symbol like `!`/`@`) has `stateShift` set
    /// in `state`, fails that `== 0` check, and matches no bound key
    /// function either (none of the default bindings cover plain
    /// shifted characters) -- skipping compose() would silently swallow
    /// it: nothing would get
    /// inserted. See FLTK's own `Fl_Text_Editor::
    /// handle_key()` (`src/Fl_Text_Editor.cxx:633-665`) and this file's
    /// own default key-binding table (only Shift+navigation/cut/paste
    /// are bound, never Shift+printable). Not ported: the
    /// `has_marked_text() && Fl::compose_state`-gated re-selection
    /// FLTK's own compose() branch also does -- genuinely dead code
    /// even in real FLTK on X11, since `Fl::compose_state`
    /// never becomes non-zero there
    /// (see `fl.core.compose()`'s own doc comment).
    int handleKey()
    {
        int del;
        if (fl.core.compose(del))
        {
            if (del)
            {
                int dp = insertPosition() - del;
                if (dp < 0) dp = 0;
                buffer().select(dp, insertPosition());
            }
            killSelection(this);
            if (fl.core.eventLength())
            {
                string text = fl.core.eventText();
                if (insertMode()) insert(text);
                else overstrike(text);
            }
            showInsertPosition();
            setChanged();
            if (when() & whenChanged) doCallback(CallbackReason.changed);
            return 1;
        }

        int key = fl.core.eventKey();
        int state = cast(int) fl.core.eventState() & (stateShift | stateCtrl | stateAlt | stateMeta);
        string text = fl.core.eventText();
        int c = text.length ? cast(int) text[0] : 0;

        KeyFunc f = boundKeyFunction(key, state, globalKeyBindings_);
        if (f is null) f = boundKeyFunction(key, state, keyBindings_);

        if (f == &kfUndo || f == &kfRedo)
        {
            // never propagate undo and redo up to another widget
            if (!f(key, this)) fl_beep();
            return 1;
        }
        else if (f !is null)
        {
            return f(key, this);
        }
        if (defaultKeyFunction_ !is null && state == 0) return defaultKeyFunction_(c, this);
        return 0;
    }

    /// Does or does not a callback according to changed() and when()
    /// settings.
    void maybeDoCallback(CallbackReason reason = CallbackReason.changed)
    {
        if (changed() || (when() & whenNotChanged)) doCallback(reason);
    }

    // -- Built-in default key-binding functions -----------------------
    //
    // Public in FLTK (FL/Fl_Text_Editor.H): the whole kf_* family,
    // including these, is declared *before* that header's own
    // `protected:` label (which only covers handle_key()/
    // maybe_do_callback()/internal fields) -- so every kf* function
    // below is genuinely part of the public API (`test/editor.cxx`
    // calls e.g. `Fl_Text_Editor::kf_undo(0, e)` directly), not just an
    // internal implementation detail -- kept public here, not under the
    // same `protected:` block as
    // handleKey()/maybeDoCallback() above, matching samples/test/editor.d
    // (which calls TextEditor.kfUndo()
    // etc. directly, matching FLTK's own test/editor.cxx exactly).

    public:

    /// Inserts the text associated with key c. Honors the current
    /// selection and insert/overstrike mode.
    static int kfDefault(int c, TextEditor e)
    {
        // FIXME (FLTK too): this function is a mess.
        if (c == 0 || (!(c > 0 && c < 127 && c >= 0x20) && c != tab)) return 0;
        string s = [cast(immutable(char)) c];
        killSelection(e);
        if (e.insertMode()) e.insert(s);
        else e.overstrike(s);
        e.showInsertPosition();
        e.setChanged();
        if (e.when() & whenChanged) e.doCallback(CallbackReason.changed);
        return 1;
    }

    /// Ignores the key; useful for disabling a key that would otherwise
    /// be handled or entered as text (e.g. Tab, when tabNav() is on).
    static int kfIgnore(int, TextEditor) { return 0; }

    /// Deletes the selection, or the character to the left of the
    /// cursor if there is no selection.
    static int kfBackspace(int, TextEditor e)
    {
        if (!e.buffer().selected() && e.moveLeft())
        {
            int p1 = e.insertPosition();
            int p2 = e.buffer().nextChar(p1);
            e.buffer().select(p1, p2);
        }
        killSelection(e);
        e.showInsertPosition();
        e.setChanged();
        if (e.when() & whenChanged) e.doCallback(CallbackReason.changed);
        return 1;
    }

    /// Inserts a newline at the current cursor position.
    static int kfEnter(int, TextEditor e)
    {
        killSelection(e);
        e.insert("\n");
        e.showInsertPosition();
        e.setChanged();
        if (e.when() & whenChanged) e.doCallback(CallbackReason.changed);
        return 1;
    }

    /// Moves the text cursor in the direction indicated by key c
    /// (Home/End/Left/Right/Up/Down/Page_Up/Page_Down).
    static int kfMove(int c, TextEditor e)
    {
        bool selected = e.buffer().selected();
        if (!selected) e.dragPos_ = e.insertPosition();
        e.buffer().unselect();
        fl.core.copy("", 0); // clears the PRIMARY selection
        switch (c)
        {
        case home:
            e.insertPosition(e.lineStart(e.insertPosition()));
            break;
        case fl.enumerations.end:
            e.insertPosition(e.lineEnd(e.insertPosition(), false));
            break;
        case left:
            e.moveLeft();
            break;
        case right:
            e.moveRight();
            break;
        case up:
            e.moveUp();
            break;
        case down:
            e.moveDown();
            break;
        case pageUp:
            foreach (i; 0 .. e.nVisibleLines_ - 1) e.moveUp();
            break;
        case pageDown:
            foreach (i; 0 .. e.nVisibleLines_ - 1) e.moveDown();
            break;
        default:
            break;
        }
        e.showInsertPosition();
        return 1;
    }

    /// Extends the current selection in the direction of key c.
    static int kfShiftMove(int c, TextEditor e)
    {
        flTextDragPrepare(-1, c, e);
        kfMove(c, e);
        flTextDragMe(e.insertPosition(), e);
        // Unconditional (not gated on non-empty), matching FLTK's
        // own `if (copy)` -- selectionText() never returns a null
        // pointer to begin with (unlike kfCopy()'s `if (*copy)`, a
        // genuine non-empty check), so this always runs, clearing the
        // PRIMARY selection even when the shift-move didn't end up
        // selecting anything.
        fl.core.copy(e.buffer().selectionText(), 0);
        return 1;
    }

    /// Moves the cursor by word/document-edge/scroll-by-line/page-top-
    /// bottom in the direction indicated by control key c.
    static int kfCtrlMove(int c, TextEditor e)
    {
        if (!e.buffer().selected()) e.dragPos_ = e.insertPosition();
        if (c != up && c != down)
        {
            e.buffer().unselect();
            fl.core.copy("", 0); // clears the PRIMARY selection
            e.showInsertPosition();
        }
        switch (c)
        {
        case home:
            e.insertPosition(0);
            e.scroll(0, 0);
            break;
        case fl.enumerations.end:
            e.insertPosition(e.buffer().length());
            e.scroll(e.countLines(0, e.buffer().length(), true), 0);
            break;
        case left:
            e.previousWord();
            break;
        case right:
            e.nextWord();
            break;
        case up:
            e.scroll(e.topLineNum_ - 1, e.horizOffset_);
            break;
        case down:
            e.scroll(e.topLineNum_ + 1, e.horizOffset_);
            break;
        case pageUp:
            e.insertPosition(e.lineStarts_[0]);
            break;
        case pageDown:
            e.insertPosition(e.lineStarts_[e.nVisibleLines_ - 2]);
            break;
        default:
            break;
        }
        return 1;
    }

    /// Moves the cursor to the beginning/end of the document, or the
    /// current line, in the direction indicated by meta key c.
    static int kfMetaMove(int c, TextEditor e)
    {
        if (!e.buffer().selected()) e.dragPos_ = e.insertPosition();
        if (c != up && c != down)
        {
            e.buffer().unselect();
            fl.core.copy("", 0); // clears the PRIMARY selection
            e.showInsertPosition();
        }
        switch (c)
        {
        case up: // top of buffer
            e.insertPosition(0);
            e.scroll(0, 0);
            break;
        case down: // end of buffer
            e.insertPosition(e.buffer().length());
            e.scroll(e.countLines(0, e.buffer().length(), true), 0);
            break;
        case left: // beginning of line
            kfMove(home, e);
            break;
        case right: // end of line
            kfMove(fl.enumerations.end, e);
            break;
        default:
            break;
        }
        return 1;
    }

    /// Extends the current selection in the direction indicated by meta
    /// key c. See kfMetaMove().
    static int kfMSMove(int c, TextEditor e)
    {
        flTextDragPrepare(-1, c, e);
        kfMetaMove(c, e);
        flTextDragMe(e.insertPosition(), e);
        return 1;
    }

    /// Extends the current selection in the direction indicated by
    /// control key c. See kfCtrlMove().
    static int kfCSMove(int c, TextEditor e)
    {
        flTextDragPrepare(-1, c, e);
        kfCtrlMove(c, e);
        flTextDragMe(e.insertPosition(), e);
        return 1;
    }

    /// Moves the text cursor to the beginning of the current line. Same
    /// as kfMove(home, e).
    static int kfHome(int, TextEditor e) { return kfMove(home, e); }

    /// Moves the text cursor to the end of the current line. Same as
    /// kfMove(end, e).
    static int kfEnd(int, TextEditor e) { return kfMove(fl.enumerations.end, e); }

    /// Moves the text cursor one character left. Same as kfMove(left, e).
    static int kfLeft(int, TextEditor e) { return kfMove(left, e); }

    /// Moves the text cursor one line up. Same as kfMove(up, e).
    static int kfUp(int, TextEditor e) { return kfMove(up, e); }

    /// Moves the text cursor one character right. Same as
    /// kfMove(right, e).
    static int kfRight(int, TextEditor e) { return kfMove(right, e); }

    /// Moves the text cursor one line down. Same as kfMove(down, e).
    static int kfDown(int, TextEditor e) { return kfMove(down, e); }

    /// Moves the text cursor up one page. Same as kfMove(pageUp, e).
    static int kfPageUp(int, TextEditor e) { return kfMove(pageUp, e); }

    /// Moves the text cursor down one page. Same as kfMove(pageDown, e).
    static int kfPageDown(int, TextEditor e) { return kfMove(pageDown, e); }

    /// Toggles insert/overstrike mode.
    static int kfInsert(int, TextEditor e)
    {
        e.insertMode(!e.insertMode());
        return 1;
    }

    /// Deletes the selection, or the character under the cursor if
    /// there is no selection.
    static int kfDelete(int, TextEditor e)
    {
        if (!e.buffer().selected())
        {
            int p1 = e.insertPosition();
            int p2 = e.buffer().nextChar(p1);
            e.buffer().select(p1, p2);
        }
        killSelection(e);
        e.showInsertPosition();
        e.setChanged();
        if (e.when() & whenChanged) e.doCallback(CallbackReason.changed);
        return 1;
    }

    /// Copies the selection to the clipboard.
    static int kfCopy(int, TextEditor e)
    {
        if (!e.buffer().selected()) return 1;
        string copy = e.buffer().selectionText();
        if (copy.length > 0) fl.core.copy(copy, 1);
        e.showInsertPosition();
        return 1;
    }

    /// Cuts the selection to the clipboard.
    static int kfCut(int c, TextEditor e)
    {
        kfCopy(c, e);
        killSelection(e);
        e.setChanged();
        if (e.when() & whenChanged) e.doCallback(CallbackReason.changed);
        return 1;
    }

    /// Pastes the clipboard, replacing any current selection.
    static int kfPaste(int, TextEditor e)
    {
        killSelection(e);
        fl.core.paste(e, 1);
        e.showInsertPosition();
        e.setChanged();
        if (e.when() & whenChanged) e.doCallback(CallbackReason.changed);
        return 1;
    }

    /// Selects the entire buffer.
    static int kfSelectAll(int, TextEditor e)
    {
        e.buffer().select(0, e.buffer().length());
        string copy = e.buffer().selectionText();
        if (copy.length > 0) fl.core.copy(copy, 0);
        return 1;
    }

    /// Undoes the last edit. Also deselects any current selection.
    static int kfUndo(int, TextEditor e)
    {
        e.buffer().unselect();
        fl.core.copy("", 0);
        int crsr = e.insertPosition();
        int ret = e.buffer().undo(&crsr);
        e.insertPosition(crsr);
        e.showInsertPosition();
        e.setChanged();
        if (e.when() & whenChanged) e.doCallback();
        return ret;
    }

    /// Redoes the last undone edit. Also deselects any current
    /// selection.
    static int kfRedo(int, TextEditor e)
    {
        e.buffer().unselect();
        fl.core.copy("", 0);
        int crsr = e.insertPosition();
        int ret = e.buffer().redo(&crsr);
        e.insertPosition(crsr);
        e.showInsertPosition();
        e.setChanged();
        if (e.when() & whenChanged) e.doCallback();
        return ret;
    }
}

/// Deselects the current selection, moving the cursor to where it
/// started (FLTK's file-static `kill_selection()`).
private void killSelection(TextEditor e)
{
    if (e.buffer().selected())
    {
        e.insertPosition(e.buffer().primarySelection().start());
        e.buffer().removeSelection();
    }
}

private struct DefaultBinding
{
    int key;
    int state;
    KeyFunc func;
}

/// The built-in default key bindings every TextEditor starts with
/// (FLTK's file-static `default_key_bindings[]`).
private immutable DefaultBinding[] defaultKeyBindingsTable = [
    DefaultBinding(escape,    textEditorAnyState, &TextEditor.kfIgnore),
    DefaultBinding(enter,     textEditorAnyState, &TextEditor.kfEnter),
    DefaultBinding(kpEnter,   textEditorAnyState, &TextEditor.kfEnter),
    DefaultBinding(backSpace, textEditorAnyState, &TextEditor.kfBackspace),
    DefaultBinding(insert,    textEditorAnyState, &TextEditor.kfInsert),
    DefaultBinding(deleteKey, textEditorAnyState, &TextEditor.kfDelete),
    DefaultBinding(home,      0, &TextEditor.kfMove),
    DefaultBinding(end,       0, &TextEditor.kfMove),
    DefaultBinding(left,      0, &TextEditor.kfMove),
    DefaultBinding(up,        0, &TextEditor.kfMove),
    DefaultBinding(right,     0, &TextEditor.kfMove),
    DefaultBinding(down,      0, &TextEditor.kfMove),
    DefaultBinding(pageUp,    0, &TextEditor.kfMove),
    DefaultBinding(pageDown,  0, &TextEditor.kfMove),
    DefaultBinding(home,      stateShift, &TextEditor.kfShiftMove),
    DefaultBinding(end,       stateShift, &TextEditor.kfShiftMove),
    DefaultBinding(left,      stateShift, &TextEditor.kfShiftMove),
    DefaultBinding(up,        stateShift, &TextEditor.kfShiftMove),
    DefaultBinding(right,     stateShift, &TextEditor.kfShiftMove),
    DefaultBinding(down,      stateShift, &TextEditor.kfShiftMove),
    DefaultBinding(pageUp,    stateShift, &TextEditor.kfShiftMove),
    DefaultBinding(pageDown,  stateShift, &TextEditor.kfShiftMove),
    DefaultBinding(home,      stateCtrl, &TextEditor.kfCtrlMove),
    DefaultBinding(end,       stateCtrl, &TextEditor.kfCtrlMove),
    DefaultBinding(left,      stateCtrl, &TextEditor.kfCtrlMove),
    DefaultBinding(up,        stateCtrl, &TextEditor.kfCtrlMove),
    DefaultBinding(right,     stateCtrl, &TextEditor.kfCtrlMove),
    DefaultBinding(down,      stateCtrl, &TextEditor.kfCtrlMove),
    DefaultBinding(pageUp,    stateCtrl, &TextEditor.kfCtrlMove),
    DefaultBinding(pageDown,  stateCtrl, &TextEditor.kfCtrlMove),
    DefaultBinding(home,      stateCtrl | stateShift, &TextEditor.kfCSMove),
    DefaultBinding(end,       stateCtrl | stateShift, &TextEditor.kfCSMove),
    DefaultBinding(left,      stateCtrl | stateShift, &TextEditor.kfCSMove),
    DefaultBinding(up,        stateCtrl | stateShift, &TextEditor.kfCSMove),
    DefaultBinding(right,     stateCtrl | stateShift, &TextEditor.kfCSMove),
    DefaultBinding(down,      stateCtrl | stateShift, &TextEditor.kfCSMove),
    DefaultBinding(pageUp,    stateCtrl | stateShift, &TextEditor.kfCSMove),
    DefaultBinding(pageDown,  stateCtrl | stateShift, &TextEditor.kfCSMove),
    DefaultBinding(cast(int) 'z', stateCtrl, &TextEditor.kfUndo),
    DefaultBinding(cast(int) 'z', stateCtrl | stateShift, &TextEditor.kfRedo), // Windows screen driver also defines Ctrl-Y
    DefaultBinding(cast(int) '/', stateCtrl, &TextEditor.kfUndo), // Emacs
    DefaultBinding(cast(int) '?', stateCtrl, &TextEditor.kfRedo), // Emacs
    DefaultBinding(cast(int) 'x', stateCtrl, &TextEditor.kfCut),
    DefaultBinding(deleteKey, stateShift, &TextEditor.kfCut),
    DefaultBinding(cast(int) 'c', stateCtrl, &TextEditor.kfCopy),
    DefaultBinding(insert,    stateCtrl, &TextEditor.kfCopy),
    DefaultBinding(cast(int) 'v', stateCtrl, &TextEditor.kfPaste),
    DefaultBinding(insert,    stateShift, &TextEditor.kfPaste),
    DefaultBinding(cast(int) 'a', stateCtrl, &TextEditor.kfSelectAll),
];

// =======================================================================
// Unit tests
// =======================================================================

unittest
{
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto e = new TextEditor(0, 0, 100, 100);
    auto buf = new TextBuffer();
    e.buffer(buf);

    assert(e.insertMode());
    e.insertMode(false);
    assert(!e.insertMode());
    e.insertMode(true);

    // Default key bindings are installed (per-instance, not global).
    assert(e.boundKeyFunction(enter, textEditorAnyState) == &TextEditor.kfEnter);
    assert(e.boundKeyFunction(left, 0) == &TextEditor.kfMove);
    assert(e.boundKeyFunction(left, stateShift) == &TextEditor.kfShiftMove);
    assert(e.boundKeyFunction(cast(int) 'z', stateCtrl) == &TextEditor.kfUndo);
    assert(e.boundKeyFunction(cast(int) 'q', 0) is null);

    fl.core.resetForTest();
}

unittest
{
    // kfDefault(): typing a plain printable character inserts it and
    // advances the cursor; a non-printable, non-tab key is refused.
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto e = new TextEditor(0, 0, 100, 100);
    auto buf = new TextBuffer();
    e.buffer(buf);

    assert(TextEditor.kfDefault(cast(int) 'x', e) == 1);
    assert(buf.text() == "x");
    assert(e.insertPosition() == 1);

    assert(TextEditor.kfDefault(0, e) == 0);
    assert(buf.text() == "x"); // unchanged

    fl.core.resetForTest();
}

unittest
{
    // Regression test (see
    // handleKey()'s own doc comment): a Shift-combo printable character
    // (e.g. an uppercase letter) must actually get inserted via
    // fl.core.compose()'s primary text-insertion path, not silently
    // swallowed by the key-binding fallback's `state == 0` gate, which
    // has no matching bound key function for a Shift-held keypress.
    FlGroup.current(null);

    auto e = new TextEditor(0, 0, 100, 100);
    auto buf = new TextBuffer();
    e.buffer(buf);

    fl.core.eText_ = "A";
    fl.core.eKeysym_ = cast(Keysym) 'A';
    fl.core.eState_ = stateShift;

    assert(e.handleKey() == 1);
    assert(buf.text() == "A");
    assert(e.insertPosition() == 1);

    fl.core.resetForTest();
}

unittest
{
    // kfBackspace()/kfDelete(): with no selection, delete the
    // neighboring character; with a selection, delete the selection
    // instead (and don't move an extra character).
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto e = new TextEditor(0, 0, 100, 100);
    auto buf = new TextBuffer();
    buf.text("abcde");
    e.buffer(buf);

    e.insertPosition(3); // between 'c' and 'd'
    TextEditor.kfBackspace(0, e);
    assert(buf.text() == "abde");
    assert(e.insertPosition() == 2);

    TextEditor.kfDelete(0, e);
    assert(buf.text() == "abe");
    assert(e.insertPosition() == 2);

    buf.select(0, 2); // "ab"
    TextEditor.kfDelete(0, e);
    assert(buf.text() == "e");
    assert(!buf.selected());

    fl.core.resetForTest();
}

unittest
{
    // kfEnter(): inserts a newline and moves the cursor past it.
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto e = new TextEditor(0, 0, 100, 100);
    auto buf = new TextBuffer();
    buf.text("ab");
    e.buffer(buf);
    e.insertPosition(1);

    TextEditor.kfEnter(0, e);
    assert(buf.text() == "a\nb");
    assert(e.insertPosition() == 2);

    fl.core.resetForTest();
}

unittest
{
    // kfMove(): plain arrow keys move the cursor and clear any
    // selection; Home/End go to line start/end.
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto e = new TextEditor(0, 0, 100, 100);
    auto buf = new TextBuffer();
    buf.text("hello\nworld");
    e.buffer(buf);

    e.insertPosition(2);
    buf.select(0, 2);
    TextEditor.kfMove(right, e);
    assert(!buf.selected());
    assert(e.insertPosition() == 3);

    TextEditor.kfMove(home, e);
    assert(e.insertPosition() == 0);

    TextEditor.kfMove(end, e);
    assert(e.insertPosition() == 5); // just before the '\n'

    fl.core.resetForTest();
}

unittest
{
    // kfShiftMove(): extends a selection instead of collapsing it.
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto e = new TextEditor(0, 0, 100, 100);
    auto buf = new TextBuffer();
    buf.text("hello world");
    e.buffer(buf);
    e.insertPosition(0);

    foreach (i; 0 .. 5) TextEditor.kfShiftMove(right, e);
    assert(buf.selected());
    int start, end;
    assert(buf.selectionPosition(start, end));
    assert(start == 0 && end == 5);
    assert(e.insertPosition() == 5);

    fl.core.resetForTest();
}

unittest
{
    // kfUndo()/kfRedo(): round-trip through the buffer's own undo
    // stack, and reposition the cursor to where the buffer reports.
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto e = new TextEditor(0, 0, 100, 100);
    auto buf = new TextBuffer();
    e.buffer(buf);

    buf.insert(0, "hello");
    e.insertPosition(5);

    assert(TextEditor.kfUndo(0, e) == 1);
    assert(buf.text() == "");
    assert(e.insertPosition() == 0);

    assert(TextEditor.kfRedo(0, e) == 1);
    assert(buf.text() == "hello");
    assert(e.insertPosition() == 5);

    fl.core.resetForTest();
}

unittest
{
    // kfSelectAll(): selects the whole buffer.
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto e = new TextEditor(0, 0, 100, 100);
    auto buf = new TextBuffer();
    buf.text("abcdef");
    e.buffer(buf);

    TextEditor.kfSelectAll(0, e);
    int start, end;
    assert(buf.selectionPosition(start, end));
    assert(start == 0 && end == 6);

    fl.core.resetForTest();
}

unittest
{
    // Custom (per-instance) key bindings take priority over the
    // default-key-function fallback, and removeKeyBinding() undoes
    // that. addKeyBinding()/removeKeyBinding() operate on this
    // editor's own list, never the process-wide global one.
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto e = new TextEditor(0, 0, 100, 100);
    auto buf = new TextBuffer();
    e.buffer(buf);

    static int marker;
    static int markFn(int c, TextEditor ed) { marker = c; return 1; }

    marker = 0;
    e.addKeyBinding(cast(int) 'q', 0, &markFn);
    assert(e.boundKeyFunction(cast(int) 'q', 0) == &markFn);

    e.removeKeyBinding(cast(int) 'q', 0);
    assert(e.boundKeyFunction(cast(int) 'q', 0) is null);

    fl.core.resetForTest();
}

unittest
{
    // tabNav(): toggling installs/removes a Tab -> kfIgnore binding.
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto e = new TextEditor(0, 0, 100, 100);
    auto buf = new TextBuffer();
    e.buffer(buf);

    assert(!e.tabNav());
    e.tabNav(true);
    assert(e.tabNav());
    assert(e.boundKeyFunction(tab, 0) == &TextEditor.kfIgnore);

    e.tabNav(false);
    assert(!e.tabNav());
    assert(e.boundKeyFunction(tab, 0) is null);

    fl.core.resetForTest();
}

unittest
{
    // kfCopy()/kfCut()/kfPaste()/kfSelectAll() against
    // fl.core.copy()/paste() (see fl.input_'s own copy()/cut()/
    // insert() unittest for the same pattern).
    import fl.group : FlGroup;

    FlGroup.current(null);
    fl.core.resetForTest();

    auto e = new TextEditor(0, 0, 100, 100);
    auto buf = new TextBuffer();
    e.buffer(buf);
    buf.text("hello world");

    buf.select(0, 5); // "hello"
    assert(TextEditor.kfCopy(0, e) == 1);
    buf.unselect(); // kfPaste()'s killSelection() would otherwise eat this

    e.insertPosition(6);
    assert(TextEditor.kfPaste(0, e) == 1);
    assert(buf.text() == "hello helloworld"); // "hello" pasted between "hello " and "world"

    buf.text("hello world");
    buf.select(0, 5);
    assert(TextEditor.kfCut(0, e) == 1);
    assert(buf.text() == " world"); // "hello" cut...
    e.insertPosition(0);
    assert(TextEditor.kfPaste(0, e) == 1);
    assert(buf.text() == "hello world"); // ...and pasted back at the start

    assert(TextEditor.kfSelectAll(0, e) == 1);
    assert(buf.selected());

    FlGroup.current(null);
    fl.core.resetForTest();
}
