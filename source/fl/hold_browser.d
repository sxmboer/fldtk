/*
 * Ported from FL/Fl_Hold_Browser.H (FLTK 1.5.0, ~/Repositories/fltk).
 *
 * Trivial type(holdBrowser) subclass of Fl_Browser: exactly one line
 * can be selected at a time and the selection persists until another
 * line is clicked (unlike Fl_Select_Browser) or Up/Down arrow keys
 * navigate it, per fl.browser_'s type(holdBrowser) keyboard branch.
 */
module fl.hold_browser;

import fl.browser;
import fl.browser_ : holdBrowser;

class HoldBrowser : Browser
{
    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        type(holdBrowser);
    }
}

unittest
{
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto b = new HoldBrowser(0, 0, 100, 100);
    b.end();
    assert(b.type() == holdBrowser);

    FlGroup.current(null);
}
