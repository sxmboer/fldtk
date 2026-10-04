// D transliteration of FLTK's examples/tree-of-tables.cxx (~/Repositories/fltk).
// Part of the samples/ contract -- see samples/README.md.
// Check: ./samples/build.sh tree-of-tables
import fl;
import std.format : format;
import std.math : sin, cos, pow, PI;

class MyTable : Table
{
    string mode;

public:
    this(int X, int Y, int W, int H, string mode)
    {
        super(X, Y, W, H);
        rows(11);
        rowHeightAll(20);
        rowHeader(true);
        cols(11);
        colWidthAll(60);
        colHeader(true);
        colResize(true); // enable column resizing
        this.mode = mode;
        end();
    }

    override void resize(int X, int Y, int W, int H)
    {
        if (W > 718)
            W = 718; // don't exceed 700 in width
        super.resize(X, Y, W, h()); // disallow changes in height
    }

    // Handle drawing table's cells
    override void drawCell(TableContext context, int ROW, int COL, int X, int Y, int W, int H)
    {
        final switch (context)
        {
        case contextStartpage: // before page is drawn..
            fl_font(helvetica, 10); // set the font for our drawing operations
            return;
        case contextColHeader: // Drawing column/row headers
        case contextRowHeader:
            int val = context == contextColHeader ? COL : ROW;
            Color col = context == contextColHeader ? colHeaderColor() : rowHeaderColor();
            pushClip(X, Y, W, H);
            string s;
            if (mode == "SinCos")
                s = format("%.2f", ((val / 10.0) * PI));
            else
                s = format("%d", val);
            drawBoxAt(Boxtype.thinUpBox, X, Y, W, H, col);
            fl_color(black);
            fl_draw(s, X, Y, W, H, alignCenter);
            popClip();
            return;
        case contextCell: // Draw data in cells
            Color col = isSelected(ROW, COL) ? yellow : white;
            pushClip(X, Y, W, H);
            string s;
            if (mode == "Addition")
                s = format("%d", ROW + COL);
            else if (mode == "Subtract")
                s = format("%d", ROW - COL);
            else if (mode == "Multiply")
                s = format("%d", ROW * COL);
            else if (mode == "Divide")
            {
                if (COL == 0)
                    s = "N/A";
                else
                    s = format("%.2f", cast(float) ROW / cast(float) COL);
            }
            else if (mode == "Exponent")
                s = format("%g", pow(cast(float) ROW, cast(float) COL));
            else if (mode == "SinCos")
                s = format("%.2f", sin((ROW / 10.0) * PI) * cos((COL / 10.0) * PI));
            else
                s = "???";
            fl_color(col);
            fl_rectf(X, Y, W, H); // bg
            fl_color(gray0);
            fl_draw(s, X, Y, W, H, alignCenter); // text
            fl_color(color());
            fl_rect(X, Y, W, H); // box
            popClip();
            return;
        case contextNone:
        case contextEndpage:
        case contextTable:
        case contextRcResize:
            return;
        }
    }
}

void main()
{
    auto win = new DoubleWindow(700, 400, "Tree of tables");
    win.begin();
    {
        // Create tree
        auto tree = new Tree(10, 10, win.w() - 20, win.h() - 20);
        tree.root().label("Math Tables");
        tree.itemLabelfont(courier); // font to use for items
        tree.linespacing(4); // extra space between items
        tree.itemDrawMode(tree.itemDrawMode() | itemDrawLabelAndWidget | // draw item with widget() next to it
                itemHeightFromWidget); // make item height follow table's height
        tree.selectmode(TreeSelect.selectNone); // font to use for items
        tree.widgetmarginleft(12); // space between item and table
        tree.connectorstyle(TreeConnector.connectorDotted);

        // Create tables, assign each a tree item
        tree.begin();
        {
            MyTable table;
            TreeItem item;

            table = new MyTable(0, 0, 500, 156, "Addition");
            item = tree.add("Arithmetic/Addition");
            item.widget(table);

            table = new MyTable(0, 0, 500, 156, "Subtract");
            item = tree.add("Arithmetic/Subtract");
            item.widget(table);

            table = new MyTable(0, 0, 500, 156, "Multiply");
            item = tree.add("Arithmetic/Multiply");
            item.widget(table);

            table = new MyTable(0, 0, 500, 156, "Divide");
            item = tree.add("Arithmetic/Divide  ");
            item.widget(table);

            table = new MyTable(0, 0, 500, 156, "Exponent");
            item = tree.add("Misc/Exponent");
            item.widget(table);

            table = new MyTable(0, 0, 500, 156, "SinCos");
            item = tree.add("Misc/Sin*Cos ");
            item.widget(table);
        }
        tree.end();
    }
    win.end();
    win.resizable(win);
    win.show();
    fl.run();
}
