/*
 * Ported from FL/Fl_Menu_Window.H + src/Fl_Menu_Window.cxx (FLTK
 * 1.5.0). FLTK's own version is a trivial Fl_Single_Window
 * subclass whose only real content is opting into the hardware
 * overlay planes when available (so a menu popping up/down doesn't
 * force the window underneath to redraw) -- a hardware feature no
 * driver in this port implements (fl.draw has no overlay-plane
 * concept at all), so this is a plain, faithful `alias`-free subclass
 * with nothing added. `fl.menu_popup`'s MenuPopupWindow builds on this
 * for the actual popup engine (see PORTING.md's Menus rows).
 */
module fl.menu_window;

import fl.single_window;

class MenuWindow : SingleWindow
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
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto w = new MenuWindow(10, 10, 200, 100);
    assert(w.x() == 10 && w.y() == 10 && w.w() == 200 && w.h() == 100);
    FlGroup.current(null);
}
