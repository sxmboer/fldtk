/*
 * Ported from FL/Fl_Single_Window.H + src/Fl_Single_Window.cxx (FLTK
 * 1.5.0, ~/Repositories/fltk). FLTK's own doc comment: "This is
 * the same as Fl_Window. However, it is possible that some
 * implementations will provide double-buffered windows by default.
 * This subclass can be used to force single-buffering."
 *
 * Trivial, faithful port: no behavior differs from fl.window.Window at
 * all today (this port has no double-buffer-by-default behavior for
 * this to opt out of -- see fl.double_window's module comment), so
 * FLTK's show()/flush() forwarding overrides have nothing to
 * differentiate and aren't ported; SingleWindow exists purely as a
 * distinctly-named/typed subclass for source compatibility with code
 * that asks for one specifically.
 */
module fl.single_window;

import fl.window : Window;
import fl.group : FlGroup;

class SingleWindow : Window
{
    this(int w, int h, string label = null)
    {
        super(w, h, label);
    }

    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
    }
}

unittest
{
    FlGroup.current(null);

    auto w = new SingleWindow(320, 200, "unpositioned");
    assert(w.x() == 0 && w.y() == 0 && w.w() == 320 && w.h() == 200);

    auto w2 = new SingleWindow(10, 10, 320, 200, "positioned");
    assert(w2.x() == 10 && w2.y() == 10);

    FlGroup.current(null);
}
