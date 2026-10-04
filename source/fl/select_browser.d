/*
 * Ported from FL/Fl_Select_Browser.H (FLTK 1.5.0, ~/Repositories/fltk).
 *
 * Trivial type(selectBrowser) subclass of Fl_Browser: clicking selects
 * a line and invokes the callback, but the selection is not "sticky"
 * -- Fl_Browser_::handle()'s FL_RELEASE case deselects immediately
 * after a select-browser's callback fires (see fl.browser_'s
 * type(selectBrowser) branch in handle()).
 */
module fl.select_browser;

import fl.browser;
import fl.browser_ : selectBrowser;

class SelectBrowser : Browser
{
    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        type(selectBrowser);
    }
}

unittest
{
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto b = new SelectBrowser(0, 0, 100, 100);
    b.end();
    assert(b.type() == selectBrowser);

    FlGroup.current(null);
}
