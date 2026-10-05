// D transliteration of FLTK's examples/tree-custom-sort.cxx.
// Build: rdmd buildsamples.d examples tree_custom_sort
import fl;
import std.conv : to;
import std.random : uniform;

void main()
{
    // Create window with tree
    scheme("gtk+");
    auto win = new DoubleWindow(250, 600, "Numeric Sort Tree");
    win.begin();
    {
        auto tree = new Tree(10, 10, win.w() - 20, win.h() - 60);
        tree.showroot(false);

        // Add 200 random numbers to the tree
        foreach (t; 0 .. 200)
            tree.add(to!string(uniform(0, 1_000_000)));

        // Resort the tree
        void mySortCallback(int dir)
        {
            auto i = tree.root();
            // Bubble sort
            foreach (ax; 0 .. i.children())
            {
                foreach (bx; ax + 1 .. i.children())
                {
                    long a = to!long(i.child(ax).label());
                    long b = to!long(i.child(bx).label());
                    if (dir == 1 && a > b) // fwd
                        i.swapChildren(ax, bx);
                    else if (dir == -1 && a < b) // rev
                        i.swapChildren(ax, bx);
                }
            }
            tree.redraw();
        }

        // Add some sort buttons
        auto fwd = new Button(10, win.h() - 40, 80, 20, "Fwd");
        fwd.callback((w) { mySortCallback(1); });
        auto rev = new Button(20 + 80, win.h() - 40, 80, 20, "Rev");
        rev.callback((w) { mySortCallback(-1); });
    }
    win.end();
    win.resizable(win);
    win.show();
    fl.run();
}
