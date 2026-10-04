// D transliteration of FLTK's examples/tree-as-container.cxx (~/Repositories/fltk).
// Part of the samples/ contract -- see samples/README.md.
// Check: ./samples/build.sh tree-as-container
import fl;
import std.format : format;

enum maxRows = 20_000;
enum maxFields = 5;
enum fieldWidth = 70;
enum fieldHeight = 30;

class MyData : FlGroup
{
    Input[maxFields] fields;

public:
    this(int X, int Y, int W, int H)
    {
        super(X, Y, W, H);
        static immutable uint[maxFields] colors = [
            0xffffdd00, 0xffdddd00, 0xddffff00, 0xddffdd00, 0xddddff00
        ];
        foreach (t; 0 .. maxFields)
        {
            fields[t] = new Input(X + t * fieldWidth, Y, fieldWidth, H);
            fields[t].color(colors[t]);
        }
        end();
    }

    void setData(int col, string val)
    {
        if (col >= 0 && col < maxFields)
            fields[col].value(val);
    }
}

void main()
{
    auto win = new DoubleWindow(450, 400, "Tree As fldtk Widget Container");
    win.begin();
    {
        // Create the tree
        auto tree = new Tree(10, 10, win.w() - 20, win.h() - 20);
        tree.showroot(false); // don't show root of tree
        // Add some regular text nodes
        tree.add("Foo/Bar/001");
        tree.add("Foo/Bar/002");
        tree.add("Foo/Bla/Aaa");
        tree.add("Foo/Bla/Bbb");
        // Add items to the 'Data' node
        foreach (t; 0 .. maxRows)
        {
            // Add item to tree
            auto item = tree.add(format("fldtk Widgets/%d", t));
            // Reconfigure item to be an fldtk widget (MyData)
            tree.begin();
            {
                auto data = new MyData(0, 0, fieldWidth * maxFields, fieldHeight);
                item.widget(data);
                // Initialize widget data
                foreach (c; 0 .. maxFields)
                    data.setData(c, format("%d-%d", t, c));
            }
            tree.end();
        }
    }
    win.end();
    win.resizable(win);
    win.show();
    fl.run();
}
