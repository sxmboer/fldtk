/*
 * Ported from FL/Fl_Double_Window.H + src/Fl_Double_Window.cxx (FLTK
 * 1.5.0, ~/Repositories/fltk). FLTK's own doc comment: "provides a
 * double-buffered window. It will draw the window data into an
 * off-screen pixmap, and then copy it to the on-screen window."
 *
 * **Real double-buffering, done 2026-08-02** (this comment previously
 * called it an API-only tag with no actual buffering -- stale as of
 * that date, corrected 2026-08-12 during an unrelated stub sweep):
 * `fl.platform_x11`'s `flushDamage()` allocates a real off-screen
 * `Pixmap` (`WindowRecord.offscreen`, sized to the window and
 * reallocated on resize) for any window whose `type() ==
 * doubleWindowTypeTag`, draws the widget tree into that pixmap, then
 * blits the damaged region onto the real on-screen window via a single
 * `XCopyArea()` -- matching FLTK's own draw-into-pixmap-then-copy
 * scheme exactly, just triggered by a `type()` check rather than a
 * separate `Fl_Window_Driver` virtual-method override, and living
 * entirely in the platform layer rather than in this class. The
 * offscreen pixmap is freed on window destruction
 * (`fl.platform_x11.destroyWindow()`) and on every reallocation.
 *
 * That's why `DoubleWindow` itself stays this thin: unlike FLTK,
 * where `resize()`/`hide()`/`show()`/`flush()` all need overrides here
 * purely to forward into `Fl_Window_Driver`'s own double-buffer
 * management, this port's buffer lifecycle is driven entirely by
 * `fl.platform_x11` keying off `type()` -- no per-window virtual
 * override is needed for any of the four. `flush()` specifically also
 * has no base method to override at all in this port -- repaint
 * happens by calling a widget's `draw()` directly, not through a
 * virtual `flush()` hook (see `fl.platform_x11.flushDamage()`'s own
 * doc comment for the full mechanism).
 */
module fl.double_window;

import fl.window : Window;
import fl.group : FlGroup;

/// FL_DOUBLE_WINDOW's type() tag (0xF1) -- one past fl.widget's
/// windowTypeTag (FL_WINDOW, 0xF0), matching FLTK's "all window
/// subclasses have type() >= FL_WINDOW" contract.
enum ubyte doubleWindowTypeTag = 0xF1;

class DoubleWindow : Window
{
    /// Same as Window(w, h, label), tagged type() doubleWindowTypeTag.
    this(int w, int h, string label = null)
    {
        super(w, h, label);
        type(doubleWindowTypeTag);
    }

    /// Same as Window(x, y, w, h, label), tagged type()
    /// doubleWindowTypeTag.
    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        type(doubleWindowTypeTag);
    }
}

unittest
{
    FlGroup.current(null);

    auto w = new DoubleWindow(320, 200, "unpositioned");
    assert(w.type() == doubleWindowTypeTag);
    assert(w.x() == 0 && w.y() == 0 && w.w() == 320 && w.h() == 200);

    auto w2 = new DoubleWindow(10, 10, 320, 200, "positioned");
    assert(w2.type() == doubleWindowTypeTag);
    assert(w2.x() == 10 && w2.y() == 10);

    FlGroup.current(null);
}
