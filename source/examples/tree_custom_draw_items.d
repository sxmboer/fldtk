// D transliteration of FLTK's examples/tree-custom-draw-items.cxx (~/Repositories/fltk).
// Part of the samples/ contract -- see samples/README.md.
// Check: ./samples/build.sh tree-custom-draw-items
import fl;
import std.format : format;
import std.algorithm : max;
import std.datetime : Clock, SysTime;

// DERIVE CUSTOM CLASS FROM TreeItem TO IMPLEMENT SHOWING THE TIME OF DAY
//     This demonstrates that item content can be dynamic and highly customized.
class MyTimeItem : TreeItem
{
    string timeFormat;

protected:
    SysTime getTimeStruct()
    {
        auto now = Clock.currTime();
        if (timeFormat == "Local")
            return now.toLocalTime();
        if (timeFormat == "GMT")
            return now.toUTC();
        return now;
    }

public:
    this(Tree tree, string timeFormat)
    {
        super(tree);
        label(timeFormat);
        this.timeFormat = timeFormat;
    }

    // Handle custom drawing of the item
    //    Tree has already handled drawing everything to the left
    //    of the label area, including any 'user icon', collapse buttons,
    //    connector lines, etc.
    //
    //    All we're responsible for is drawing the 'label' area of the item
    //    and it's background. Tree gives us a hint as to what the
    //    foreground and background colors should be via the fg/bg parameters,
    //    and whether we're supposed to render anything or not.
    //
    //    The only other thing we must do is return the maximum X position
    //    of scrollable content, i.e. the right most X position of content
    //    that we want the user to be able to use the horizontal scrollbar
    //    to reach.
    override int drawItemContent(bool render)
    {
        Color fg = drawfgcolor();
        Color bg = drawbgcolor();
        // Our item's label dimensions
        int X = labelX(), Y = labelY(), W = labelW(), H = labelH();
        // Render background
        if (render)
        {
            if (isSelected())
                drawBoxAt(prefs().selectbox(), X, Y, W, H, bg); // Selected? Use selectbox() style
            else
            {
                fl_color(bg);
                fl_rectf(X, Y, W, H); // Not Selected? use plain filled rectangle
            }
        }
        // Render the label
        int dx = fl.boxDx(prefs().selectbox()) + 1;
        int dw = fl.boxDw(prefs().selectbox()) + 2;
        if (render)
        {
            fl_color(fg);
            if (label())
                fl_draw(label(), X + dx, Y, W - dw, H, alignLeft);
        }
        int lw = 0, lh = 0;
        if (label())
            fl_measure(label(), lw, lh);
        X += lw + 8;
        // Draw some red/grn/blu boxes
        if (render)
        {
            fl_color(red);
            fl_rectf(X + 0, Y + 2, 10, H - 4);
            fl_color(green);
            fl_rectf(X + 10, Y + 2, 10, H - 4);
            fl_color(blue);
            fl_rectf(X + 20, Y + 2, 10, H - 4);
        }
        X += 35;
        // Render the date and time, one over the other
        fl_font(labelfont(), 8); // small font
        fl_color(fg);
        auto tm = getTimeStruct();
        string s = format("Date: %02d/%02d/%02d", tm.month, tm.day, tm.year % 100);
        lw = 0;
        lh = 0;
        fl_measure(s, lw, lh); // get box around text (including white space)
        if (render)
            fl_draw(s, X, Y + 4, W, H, alignLeft | alignTop);
        s = format("Time: %02d:%02d:%02d", tm.hour, tm.minute, tm.second);
        if (render)
            fl_draw(s, X, Y + H / 2, W, H / 2, alignLeft | alignTop);
        int lw2 = 0, lh2 = 0;
        fl_measure(s, lw2, lh2);
        X += max(lw, lw2);
        return X; // return right most edge of what we've rendered
    }
}

// TIMER TO HANDLE DYNAMIC CONTENT IN THE TREE
void timerCb(Tree tree)
{
    tree.redraw(); // keeps time updated
    fl.repeatTimeout(0.2, () { timerCb(tree); });
}

void main()
{
    scheme("gtk+"); // default scheme: can be overridden by commandline
    Tree tree;
    auto win = new DoubleWindow(350, 450, "Tree Custom Draw Items");
    win.begin();
    {
        // Create the tree
        tree = new Tree(0, 0, win.w(), win.h() - 50);
        tree.showroot(false); // don't show root of tree
        tree.selectmode(TreeSelect.selectMulti); // multiselect

        // Add some items
        tree.add("Flintstones/Fred");
        tree.add("Flintstones/Wilma");
        tree.add("Flintstones/Pebbles");
        {
            auto myitem = new MyTimeItem(tree, "Local"); // create custom item
            myitem.labelsize(20);
            tree.add("Time Add Item/Local", myitem);

            myitem = new MyTimeItem(tree, "GMT"); // create custom item
            myitem.labelsize(20);
            tree.add("Time Add Item/GMT", myitem);
        }
        // 'Replace' approach
        {
            auto item = tree.add("Time Replace Item/Local Time");
            // Replace the 'Local' item with our own
            auto myitem = new MyTimeItem(tree, "Local"); // create custom item
            myitem.labelsize(20);
            item.replace(myitem); // replace normal item with custom

            item = tree.add("Time Replace Item/GMT Time");
            // Replace the 'GMT' item with our own
            myitem = new MyTimeItem(tree, "GMT"); // create custom item
            myitem.labelsize(20);
            item.replace(myitem); // replace normal item with custom
        }
        tree.add("Superjail/Warden");
        tree.add("Superjail/Jared");
        tree.add("Superjail/Alice");
        tree.add("Superjail/Jailbot");

        tree.showSelf();

        // Start with some items closed
        tree.close("Superjail");

        // Optional: set a "special" selection color (light blue)
        tree.selectionColor(0xcceeff00);

        // Optional: set a "special" box type for the selection box
        tree.selectbox(Boxtype.thinUpBox);

        // Create the scheme choice box
        new SchemeChoice((win.w() - 130) / 2, win.h() - 40, 130, 30, "Scheme: ");

        // Set up a timer to keep time in tree updated
        fl.addTimeout(0.2, () { timerCb(tree); });
    }
    win.end();
    win.resizable(tree);
    win.sizeRange(300, 350);
    win.show();
    fl.run();
}
