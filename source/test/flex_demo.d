// D transliteration of FLTK's test/flex_demo.cxx (~/Repositories/fltk).
// Part of the samples/ contract -- see samples/README.md.
// Check: ./samples/build.sh flex_demo
import fl;
import std.stdio : writefln;

enum bool DEBUG_GROUP = false;

void debugGroup(FlGroup g)
{
    static if (DEBUG_GROUP)
    {
        writefln("\nFlGroup (%s) has %d children:", g, g.children());
        for (int i = 0; i < g.children(); i++)
        {
            auto c = g.child(i);
            writefln("  child %2d: hidden = %-5s, (x,y,w,h) = (%3d, %3d, %3d, %3d), label = '%s'",
                i, !c.visible(), c.x(), c.y(), c.w(), c.h(),
                c.label() is null ? "(null)" : c.label());
        }
    }
}

Button createButton(string caption)
{
    auto rtn = new Button(0, 0, 120, 30, caption);
    rtn.color(rgbColor(225, 225, 225));
    return rtn;
}

Flex createRow()
{
    auto row = new Flex(flexRow);
    {
        auto toggle = createButton("hide OK button");
        toggle.tooltip("hide() or show() OK button");
        auto box2 = new Box(0, 0, 120, 10, "Box2");
        auto okay = createButton("OK");
        new Input(0, 0, 120, 10, "");

        toggle.callback((w) {
            static Box b = null;
            auto flex = cast(Flex) okay.parent();
            if (okay.visible())
            {
                okay.hide();
                w.label("show OK button");
                flex.child(1).hide(); // hide Box
            }
            else
            {
                okay.show();
                w.label("hide OK button");
                flex.child(1).show(); // show Box
            }
            flex.layout();

            debugGroup(flex);

            // Yet another test: modify the first (top) Fl_Flex widget

            flex = cast(Flex)(cast(FlGroup) flex.parent()).child(0);
            FlGroup.current(null);
            if (b is null)
            {
                b = new Box(0, 0, 0, 0, "Box3");
                flex.insert(b, flex.children() - 1);
            }
            else
            {
                destroy(b);
                b = null;
            }
            flex.layout();
            debugGroup(flex);
        });

        auto col2 = new Flex(flexColumn);
        {
            createButton("Top2");
            createButton("Bottom2");
            col2.end();
            col2.margin(0, 5);
            col2.box(Boxtype.flatBox);
            col2.color(rgbColor(255, 128, 128));
        }

        row.fixed(box2, 50);
        row.fixed(col2, 100);
        row.end();

        // TEST
        row.box(Boxtype.downBox);
        row.color(green);
    }

    return row;
}

void main()
{
    Window window = new DoubleWindow(100, 100, "Simple GUI Example");
    auto col = new Flex(5, 5, 90, 90, flexColumn);
    auto row1 = new Flex(flexRow);
    row1.color(yellow);
    row1.box(Boxtype.flatBox);
    createButton("Cancel");
    new Box(0, 0, 120, 10, "Box1");
    createButton("OK");
    new Input(0, 0, 120, 10, "");

    auto col1 = new Flex(flexColumn);
    createButton("Top1");
    createButton("Bottom1");
    col1.box(Boxtype.flatBox);
    col1.color(rgbColor(255, 128, 128));
    col1.margin(5, 5);
    col1.end();
    row1.end();

    col.fixed(createRow(), 90); // sets height of created (anonymous) row #2

    createButton("Something1"); // "row" #3

    auto row4 = new Flex(flexRow);
    auto cancel = createButton("Cancel");
    auto ok = createButton("OK");
    new Input(0, 0, 120, 10, "");
    row4.fixed(cancel, 100);
    row4.fixed(ok, 100);
    row4.end();

    createButton("Something2"); // "row" #5

    col.fixed(row4, 30);
    col.margin(6, 10, 6, 10);
    col.gap(6);
    col.end();

    window.resizable(col);
    window.color(rgbColor(160, 180, 240));
    window.box(Boxtype.flatBox);
    window.end();

    window.sizeRange(550, 330);
    window.resize(0, 0, 640, 480);
    window.show();

    fl.run();
    destroy(window); // not necessary but useful to test for memory leaks
}
