// D transliteration of FLTK's test/coordinates.cxx.
// Build: rdmd buildsamples.d test coordinates
import fl;
// fl.box's Box is the port of Fl_Box; FLTK's local "class Box :
// public Fl_Box" collides with that name under the Fl_Foo -> Foo naming
// convention this port already uses, so alias the real one to disambiguate.
import flbox = fl.box;
import std.format : format;

class Box : flbox.Box
{
    this(int x, int y, int w, int h, Color c, string t)
    {
        super(x, y, w, h, t);
        alignment(alignInside | alignCenter);
        box(Boxtype.downBox);
        labelcolor(c);
        labelsize(11);
    }
}

class Title : flbox.Box
{
    this(int x, int y, int w, int h, Color c, string t)
    {
        super(x, y, w, h, t);
        alignment(alignInside | alignCenter | alignTop);
        box(Boxtype.noBox);
        labelcolor(c);
        labelsize(12);
    }
}

class MainWindow : Window
{
    private flbox.Box messageBox;

    this(int x, int y, string t)
    {
        super(x, y, t);

        auto tlWindow = new Window(0, 0, 250, 100);
        tlWindow.box(Boxtype.engravedBox);
        new Title(10, 10, 230, 40, red,
            "Window TL(0, 0, 250, 100)\nx, y relative to main window");
        new Box(25, 50, 200, 40, red,
            "Box tl(25, 50, 200, 40)\nx, y relative to TL window");
        tlWindow.end();

        auto brWindow = new Window(250, 100, 250, 100);
        brWindow.box(Boxtype.engravedBox);
        new Title(10, 10, 230, 40, magenta,
            "Window BR(250, 100, 250, 100)\nx, y relative to main window");
        new Box(25, 50, 200, 40, magenta,
            "Box br(25, 50, 200, 40)\nx, y relative to BR window");
        brWindow.end();

        auto trGroup = new FlGroup(250, 0, 250, 100);
        trGroup.box(Boxtype.engravedBox);
        new Title(260, 10, 230, 40, blue,
            "FlGroup TR(250, 0, 250, 100)\nx, y relative to main window");
        new Box(275, 50, 200, 40, blue,
            "Box tr(275, 50, 200, 40)\nx, y relative to main window");
        trGroup.end();

        auto blGroup = new FlGroup(0, 100, 250, 100);
        blGroup.box(Boxtype.engravedBox);
        new Title(10, 110, 230, 40, black,
            "FlGroup BL(0, 100, 250, 100)\nx, y relative to main window");
        new Box(25, 150, 200, 40, black,
            "Box bl(25, 150, 200, 40)\nx, y relative to main window");
        blGroup.end();

        // member variable
        messageBox = new flbox.Box(0, 201, 500, 30);
        messageBox.alignment(alignInside | alignCenter);
        messageBox.box(Boxtype.engravedBox);
        messageBox.labelfont(courier);
        messageBox.labelsize(12);

        end();
    }

    protected override int handle(Event event)
    {
        int result = super.handle(event);
        switch (event)
        {
        case Event.enter:
        case Event.leave:
            result = 1;
            messageBox.copyLabel("");
            break;
        case Event.move:
        case Event.drag:
            result = 1;
            if (0 < fl.eventX() && fl.eventX() < w() &&
                0 < fl.eventY() && fl.eventY() < h())
            {
                messageBox.copyLabel(format("Mouse position relative to main window: %3d,%3d",
                    fl.eventX(), fl.eventY()));
            }
            else
                messageBox.copyLabel("");
            break;
        default:
            break;
        }
        return result;
    }
}

void main()
{
    auto window = new MainWindow(500, 232, "FLTK Coordinate Systems");
    window.show();
    fl.run();
}
