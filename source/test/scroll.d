// D transliteration of FLTK's test/scroll.cxx (~/Repositories/fltk).
// Part of the samples/ contract -- see samples/README.md.
// Check: ./samples/build.sh scroll
import fl;
import std.math : PI, cos, sin;

class Drawing : Widget
{
    this(int x, int y, int w, int h, string label)
    {
        super(x, y, w, h, label);
        alignment(alignTop);
        box(Boxtype.flatBox);
        color(white);
    }

    override void draw()
    {
        drawBox();
        pushMatrix();
        fl_translate(x + w / 2, y + h / 2);
        fl_scale(w / 2, h / 2);
        fl_color(black);
        for (int i = 0; i < 20; i++)
        {
            for (int j = i + 1; j < 20; j++)
            {
                beginLine();
                vertex(cos(PI * i / 10 + .1), sin(PI * i / 10 + .1));
                vertex(cos(PI * j / 10 + .1), sin(PI * j / 10 + .1));
                endLine();
            }
        }
        popMatrix();
    }
}

Scroll thescroll;

void boxCb(Widget o)
{
    thescroll.box((cast(LightButton) o).value() ? Boxtype.downFrame : Boxtype.noBox);
    thescroll.redraw();
}

void typeCb(ubyte v)
{
    thescroll.type(v);
    thescroll.redraw();
}

MenuItem[] choices = [
    MenuItem("0", 0, (w) { typeCb(0); }),
    MenuItem("HORIZONTAL", 0, (w) { typeCb(scrollHorizontal); }),
    MenuItem("VERTICAL", 0, (w) { typeCb(scrollVertical); }),
    MenuItem("BOTH", 0, (w) { typeCb(scrollBoth); }),
    MenuItem("HORIZONTAL_ALWAYS", 0, (w) { typeCb(scrollHorizontalAlways); }),
    MenuItem("VERTICAL_ALWAYS", 0, (w) { typeCb(scrollVerticalAlways); }),
    MenuItem("BOTH_ALWAYS", 0, (w) { typeCb(scrollBothAlways); }),
    MenuItem.init, // trailing null-text sentinel -- see cursor.d's copy
                   // of this same fix for the full reasoning
                   // (PORTING.md's FL/Fl_Menu_Item.H row has the writeup).
];

void alignCb(Align v)
{
    thescroll.scrollbar.alignment(v);
    thescroll.redraw();
}

MenuItem[] alignChoices = [
    MenuItem("left+top", 0, (w) { alignCb(alignLeft + alignTop); }),
    MenuItem("left+bottom", 0, (w) { alignCb(alignLeft + alignBottom); }),
    MenuItem("right+top", 0, (w) { alignCb(alignRight + alignTop); }),
    MenuItem("right+bottom", 0, (w) { alignCb(alignRight + alignBottom); }),
    MenuItem.init, // trailing null-text sentinel -- see cursor.d's copy
                   // of this same fix for the full reasoning.
];

void main(string[] args)
{
    auto window = new Window(5 * 75, 400);
    window.box(Boxtype.noBox);
    auto scroll = new Scroll(0, 0, 5 * 75, 300);

    int n = 0;
    for (int y = 0; y < 16; y++)
        for (int x = 0; x < 5; x++)
        {
            import std.format : format;

            string buf = format("%d", n++);
            auto b = new Button(x * 75, y * 25 + (y >= 8 ? 5 * 75 : 0), 75, 25);
            b.copyLabel(buf);
            b.color(n);
            b.labelcolor(white);
        }
    auto drawing = new Drawing(0, 8 * 25, 5 * 75, 5 * 75, null);
    scroll.end();
    window.resizable(scroll);

    auto box = new Box(0, 300, 5 * 75, window.h - 300); // gray area below the scroll
    box.box(Boxtype.flatBox);

    auto but1 = new LightButton(150, 310, 200, 25, "box");
    but1.callback((w) { boxCb(w); });

    auto choice = new Choice(150, 335, 200, 25, "type():");
    choice.menu(choices);
    choice.value(3);

    auto achoice = new Choice(150, 360, 200, 25, "scrollbar.align():");
    achoice.menu(alignChoices);
    achoice.value(3);

    thescroll = scroll;

    window.end();
    window.show(args);
    fl.run();
}
