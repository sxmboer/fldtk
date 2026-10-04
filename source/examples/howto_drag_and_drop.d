// D transliteration of FLTK's examples/howto-drag-and-drop.cxx
// (~/Repositories/fltk).
// Part of the samples/ contract -- see samples/README.md.
// Check: ./samples/build.sh howto-drag-and-drop
import fl;
import std.stdio : stderr;

// SIMPLE SENDER CLASS
class Sender : Box
{
    this(int x, int y, int w, int h)
    {
        super(x, y, w, h);
        box(Boxtype.flatBox);
        color(9);
        label("Drag\nfrom\nhere..");
    }

    // Sender event handler
    override int handle(Event event)
    {
        int ret = super.handle(event);
        switch (event)
        {
        case Event.push: // do 'copy/dnd' when someone clicks on box
            string msg = "It works!";
            fl.copy(msg, 0);
            fl.dnd();
            ret = 1;
            break;
        default:
            break;
        }
        return ret;
    }
}

// SIMPLE RECEIVER CLASS
class Receiver : Box
{
    private bool dndInside;
    private string dndText;

    this(int x, int y, int w, int h)
    {
        super(x, y, w, h);
        box(Boxtype.flatBox);
        color(10);
        label("..to\nhere");
        dndInside = false;
        dndText = null;
    }

    // Receiver event handler
    override int handle(Event event)
    {
        int ret = super.handle(event);
        switch (event)
        {
        case Event.dndEnter: // return(1) for this event to 'accept' dnd
            label("ENTER"); // visible only if you stop the mouse at the widget's border
            stderr.writeln("FL_DND_ENTER");
            dndInside = true; // status: inside the widget, accept drop
            ret = 1;
            break;

        case Event.dndDrag: // return(1) for this event to 'accept' dnd
            label("drop\nhere");
            stderr.writeln("FL_DND_DRAG");
            ret = 1;
            break;

        case Event.dndRelease: // return(1) for this event to 'accept' the payload (drop)
            stderr.writeln("FL_DND_RELEASE");
            if (dndInside)
            {
                ret = 1; // return(1) and expect FL_PASTE event to follow
                label("RELEASE");
            }
            else
            {
                ret = 0; // return(0) to reject the DND payload (drop)
                label("DND\nREJECTED!");
            }
            break;

        case Event.paste: // handle actual drop (paste) operation
            stderr.writeln("FL_PASTE");
            copyLabel(fl.eventText());
            stderr.writefln("Pasted '%s'", fl.eventText());

            // Don't pop up dialog windows in FL_DND_* or FL_PASTE event
            // handling resulting from DND operations. This may hang or
            // even crash the application on *some* platforms. Use a short
            // timer to delay the message display after the event
            // processing is completed.

            dndText = null; // don't leak (just in case)

            if (fl.eventLength() && fl.eventText())
            {
                dndText = fl.eventText().idup;
                fl.addTimeout(0.001, &dndCb); // delay message popup
            }
            ret = 1;
            break;

        case Event.dndLeave: // not strictly necessary to return(1) for this event
            label("..to\nhere"); // reset label
            stderr.writeln("FL_DND_LEAVE");
            dndInside = false; // status: mouse is outside, don't accept drop
            ret = 1; // return(1) anyway..
            break;

        default:
            break;
        }
        return ret;
    }

    // dnd (FL_PASTE) popup method
    void dndCb()
    {
        if (dndText)
        {
            message(dndText);
            dndText = null;
        }
    }
}

void main()
{
    // Create sender window and widget
    auto winA = new Window(0, 0, 200, 100, "Sender");
    auto a = new Sender(0, 0, 100, 100);
    winA.end();
    winA.show();
    // Create receiver window and widget
    auto winB = new Window(400, 0, 200, 100, "Receiver");
    auto b = new Receiver(100, 0, 100, 100);
    winB.end();
    winB.show();
    fl.run();
}
