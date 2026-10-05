/*
 * Ported from FL/Fl_Multi_Browser.H (FLTK 1.5.0).
 *
 * Trivial type(multiBrowser) subclass of Fl_Browser: any number of
 * lines can be selected at once (Shift/Ctrl-click to extend/toggle,
 * Space/Enter for keyboard selection), per fl.browser_'s
 * type(multiBrowser) branches throughout handle()/select()/deselect().
 */
module fl.multi_browser;

import fl.browser;
import fl.browser_ : multiBrowser;

class MultiBrowser : Browser
{
    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        type(multiBrowser);
    }
}

unittest
{
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto b = new MultiBrowser(0, 0, 100, 100);
    b.add("a");
    b.add("b");
    b.end();
    assert(b.type() == multiBrowser);

    // Multi-select semantics: both lines can be selected at once.
    b.select(1);
    b.select(2);
    assert(b.selected(1) != 0);
    assert(b.selected(2) != 0);

    FlGroup.current(null);
}
