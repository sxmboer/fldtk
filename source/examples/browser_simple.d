// D transliteration of FLTK's examples/browser-simple.cxx (~/Repositories/fltk).
// Part of the samples/ contract -- see samples/README.md.
// Check: ./samples/build.sh browser-simple
import fl;
import std.stdio : writefln;

// Hold Browser's callback -- invoked whenever an item is clicked.
void holdBrowserCallback(Widget w)
{
    auto brow = cast(HoldBrowser) w;
    int line = brow.value();
    writefln("[hold browser] item %d picked: %s", line, brow.text(line));
}

// Multi Browser's callback -- invoked whenever an item(s) is clicked/selected.
void multiBrowserCallback(Widget w)
{
    auto brow = cast(MultiBrowser) w;
    // Multi browser can have many items selected, so print all selected.
    for (int t = 1; t <= brow.size(); t++)
        if (brow.selected(t))
            writefln("[multi browser] item %d selected: %s", t, brow.text(t));
    writefln("");
}

void main()
{
    scheme("gtk+");
    auto win = new DoubleWindow(250, 220, "Simple Browser");
    win.begin();
    {
        // Create Hold Browser
        auto brow = new HoldBrowser(10, 10, win.w() - 20, 80, "Hold");
        brow.callback((w) { holdBrowserCallback(w); });
        brow.add("One");
        brow.add("Two");
        brow.add("Three");
        brow.add("Four");
        // Preselect first item "One"
        brow.select(1);
    }
    {
        // Create Multi Browser
        auto brow = new MultiBrowser(10, 120, win.w() - 20, 80, "Multi");
        brow.callback((w) { multiBrowserCallback(w); });
        brow.add("Aaa");
        brow.add("Bbb");
        brow.add("Ccc");
        brow.add("Ddd");
        // Preselect first two items "Aaa" and "Bbb"
        brow.select(1);
        brow.select(2);
    }
    win.end();
    win.resizable(win);
    win.show();
    fl.run();
}
