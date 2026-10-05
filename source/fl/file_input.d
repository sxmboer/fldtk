/*
 * Ported from FL/Fl_File_Input.H + src/Fl_File_Input.cxx (FLTK 1.5.0). A path-displaying Input subclass with a
 * clickable "breadcrumb" navigation bar above the text field, letting
 * the user click a path component to truncate the value up to (and
 * including) that directory separator.
 *
 * Deliberate deviations from FLTK:
 *  - `ok_entry_`: FLTK declares this field, sets it to 1 in the
 *    constructor, and never reads it again anywhere in
 *    Fl_File_Input.cxx -- genuinely dead state, same situation as
 *    fl.wizard's `value_` field (see that module's comment). Not
 *    ported, for the same reason: nothing observable changes by
 *    omitting a field nothing ever reads.
 *  - `Fl::system_driver()->next_dir_sep()`: a platform-driver hook,
 *    `strchr(start, '/')` on Linux and (`Fl_WinAPI_System_Driver::
 *    next_dir_sep()`) `strchr(start, '/')` falling back to
 *    `strchr(start, '\\')` on Windows. Ported as a single nextDirSep()
 *    below with a `version (Windows)` fallback branch rather than a
 *    driver abstraction (same "concrete function, version() choice, no
 *    driver class for a two-platform port" precedent `fl.filename.
 *    isDirSep()` already establishes).
 *  - `handle_button()`'s `window()->make_current(); draw_buttons();`
 *    (an immediate, synchronous repaint of just the button bar,
 *    bypassing the normal Expose-driven draw cycle for snappier
 *    feedback while dragging across buttons): no Window.makeCurrent()
 *    exists in this port (fl.draw's drawing state is set up by
 *    fl.platform_x11's Expose handler, not available on demand from
 *    arbitrary widget code yet). Simplified to `damage(damageBar)`,
 *    which still repaints the bar, just on the next Expose rather than
 *    synchronously -- a one-frame feedback lag while dragging across
 *    directory buttons, not a correctness difference.
 *  - The truncation path in handle_button() copies value() into a
 *    fixed `char newvalue[FL_PATH_MAX]` buffer FLTK (so it can
 *    write a nul terminator mid-string). D strings need no such
 *    mutable copy -- slicing value() directly is enough -- so there's
 *    no FL_PATH_MAX-length cap here either; not a meaningful behavior
 *    difference for any realistic path.
 *  - `inButtonBar` (FLTK: `static char inButtonBar` local to
 *    Fl_File_Input::handle(), genuinely shared across every
 *    Fl_File_Input instance process-wide): module-level D global here,
 *    matching the fl.slider `offcenter`/fl.roller `ipos` precedent
 *    CONVENTIONS.md documents.
 *
 * handle()'s default case now uses fl.widget_tracker.WidgetTracker to
 * guard against Input::handle(event) having destroyed this widget
 * (e.g. via a callback), matching FLTK's `Fl_Widget_Tracker
 * wp(this); if (Fl_Input::handle(event)) { if (wp.exists())
 * damage(FL_DAMAGE_BAR); ... }` exactly.
 */
module fl.file_input;

import fl.input : Input;
import fl.widget_tracker : WidgetTracker;
import fl.enumerations;
import fl.core;
import fldraw = fl.draw;

private enum int dirHeight = 10;
private enum Damage damageBar = 0x10;

/// See the module comment: genuinely shared across every FileInput,
/// matching FLTK's function-local `static char inButtonBar`.
private bool inButtonBar_ = false;

class FileInput : Input
{
    private
    {
        Boxtype downBox_;
        short[200] buttons_;
        short pressed_ = -1;
    }

    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        buttons_[0] = 0;
        pressed_ = -1;
        downBox(Boxtype.upBox);
    }

    Boxtype downBox() const { return downBox_; }
    void downBox(Boxtype b) { downBox_ = b; }

    import fl.input_ : Input_;
    alias value = Input_.value;

    override int value(string str, int len)
    {
        damage(damageBar);
        return super.value(str, len);
    }

    override int value(string str)
    {
        damage(damageBar);
        return super.value(str);
    }

    /// Ported from Fl_System_Driver::next_dir_sep() -- see the module
    /// comment. Returns the byte offset of the next '/' at or after
    /// `from`, or -1 (FLTK's NULL) if there isn't one. On Windows, falls
    /// back to scanning for '\\' when no '/' exists anywhere in the
    /// remainder -- matching `Fl_WinAPI_System_Driver::next_dir_sep()`'s
    /// own `strchr(start,'/'); if (!p) p = strchr(start,'\\');` exactly,
    /// '/' still wins whenever both appear in the same remaining string.
    private int nextDirSep(string s, int from) const
    {
        for (int i = from; i < cast(int) s.length; i++)
            if (s[i] == '/') return i;
        version (Windows)
            for (int i = from; i < cast(int) s.length; i++)
                if (s[i] == '\\') return i;
        return -1;
    }

    /// Ported from Fl_File_Input::update_buttons().
    private void updateButtons()
    {
        fldraw.fl_font(textfont(), textsize());

        string v = value();
        int start = 0;
        int i = 0;
        while (i < cast(int) buttons_.length - 1)
        {
            int end = nextDirSep(v, start);
            if (end < 0) break;
            end++;
            buttons_[i] = cast(short) fldraw.width(v[start .. end]);
            if (i == 0) buttons_[i] = cast(short)(buttons_[i] + fl.core.boxDx(box()) + 6);
            start = end;
            i++;
        }
        buttons_[i] = 0;
    }

    /// Ported from Fl_File_Input::draw_buttons().
    private void drawButtons()
    {
        if (damage() & (damageBar | damageAll)) updateButtons();

        int X = 0;
        int i = 0;
        for (; buttons_[i]; i++)
        {
            if (X + buttons_[i] > xscroll())
            {
                if (X < xscroll())
                {
                    drawBox(pressed_ == i ? fl_down(downBox()) : downBox(),
                        x(), y(), X + buttons_[i] - xscroll(), dirHeight, gray);
                }
                else if (X + buttons_[i] - xscroll() > w())
                {
                    drawBox(pressed_ == i ? fl_down(downBox()) : downBox(),
                        x() + X - xscroll(), y(), w() - X + xscroll(), dirHeight, gray);
                }
                else
                {
                    drawBox(pressed_ == i ? fl_down(downBox()) : downBox(),
                        x() + X - xscroll(), y(), buttons_[i], dirHeight, gray);
                }
            }
            X += buttons_[i];
        }

        if (X < w())
        {
            drawBox(pressed_ == i ? fl_down(downBox()) : downBox(),
                x() + X - xscroll(), y(), w() - X + xscroll(), dirHeight, gray);
        }
    }

    override void draw()
    {
        Boxtype b = box();
        if (damage() & (damageBar | damageAll)) drawButtons();
        // Keeps Input_.drawtext() from drawing a bogus box (matches
        // FLTK's `must_trick_fl_input_` comment verbatim).
        bool mustTrick = fl.core.focus() !is this && size() == 0 && !(damage() & damageAll);
        if ((damage() & damageAll) || mustTrick)
            drawBox(b, x(), y() + dirHeight, w(), h() - dirHeight, color());
        if (!mustTrick)
            drawtext(x() + fl.core.boxDx(b) + 3, y() + fl.core.boxDy(b) + dirHeight,
                w() - fl.core.boxDw(b) - 6, h() - fl.core.boxDh(b) - dirHeight);
    }

    /// Ported from Fl_File_Input::handle_button().
    private int handleButton(Event event)
    {
        int X = 0;
        int i = 0;
        for (; buttons_[i]; i++)
        {
            X += buttons_[i];
            if (X > xscroll() && fl.core.eventX() < x() + X - xscroll()) break;
        }

        pressed_ = (event == Event.release) ? cast(short)(-1) : cast(short) i;
        damage(damageBar); // see the module comment on make_current()/draw_buttons()

        if (!buttons_[i] || event != Event.release) return 1;

        string newvalue = value();
        int start, end;
        int ii = i;
        for (start = 0, end = start; start >= 0 && ii >= 0; start = end, ii--)
        {
            end = nextDirSep(newvalue, start);
            if (end < 0) break;
            end++;
        }

        if (ii < 0)
        {
            value(newvalue[0 .. start], start);
            setChanged();
            if (when() & (whenChanged | whenRelease)) doCallback(CallbackReason.changed);
        }

        return 1;
    }

    override int handle(Event event)
    {
        switch (event)
        {
        case Event.move:
        case Event.enter:
            if (activeR() && window() !is null)
            {
                if (fl.core.eventY() < y() + dirHeight)
                    window().cursor(Cursor.default_);
                else
                    window().cursor(Cursor.insert);
            }
            return 1;

        case Event.push:
            inButtonBar_ = fl.core.eventY() < y() + dirHeight;
            goto case Event.release;
        case Event.release:
        case Event.drag:
            if (inButtonBar_) return handleButton(event);
            else return super.handle(event);

        default:
        {
            auto wp = WidgetTracker(this);
            if (super.handle(event))
            {
                if (wp.exists()) damage(damageBar);
                return 1;
            }
            return 0;
        }
        }
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

    auto fi = new FileInput(0, 0, 200, 20);
    assert(fi.downBox() == Boxtype.upBox);

    fi.value("/usr/local/bin");
    assert(fi.value() == "/usr/local/bin");

    FlGroup.current(null);
    fl.core.resetForTest();
}

unittest
{
    // nextDirSep() (private, exercised indirectly via updateButtons()'s
    // effect on drawButtons() not crashing) -- a lighter smoke check
    // that setting a multi-component path doesn't throw.
    import fl.group : FlGroup;

    FlGroup.current(null);
    fl.core.resetForTest();

    auto fi = new FileInput(0, 0, 200, 20);
    fi.value("a/b/c/d");
    fi.damage(damageAll);
    fi.draw(); // headless: fl.draw's Xft/X11 calls no-op without a display

    FlGroup.current(null);
    fl.core.resetForTest();
}
