// D transliteration of FLTK's test/handle_events.cxx.
// Build: rdmd buildsamples.d test handle_events
import fl;
import std.stdio : stderr;

// define WindowType as either GlWindow or DoubleWindow
alias WindowType = DoubleWindow;

// Class to handle events
class App : WindowType
{
    // storage for the last event
    int eventnum, ex, ey;
    string eventname;

    this(int x, int y, int w, int h, string l = null)
    {
        super(x, y, w, h, l);
        eventname = null;
        eventnum = 0;
    }

    // evaluates and prints the current event
    void printEvent(Event ev)
    {
        eventnum++;
        ex = fl.eventX();
        ey = fl.eventY();
        int scrNum = screenNum();
        // fldtk has no per-monitor DPI scaling yet (Fl::screen_scale()
        // isn't ported -- see PORTING.md), so this always reports 100%
        // rather than calling a nonexistent fl.screenScale().
        int scale = 100;
        eventname = eventNames[ev];
        stderr.writef("[%3d, win(%d,%d,%d,%d), screen %d, scale %3d%%] %-18.18s at (%4d, %4d)",
                eventnum, x(), y(), w(), h(), scrNum, scale, eventname, ex, ey);
        eventnum %= 999;
    }

protected:
    // Event handling
    override int handle(Event ev)
    {
        printEvent(ev); // common for all events
        int res = super.handle(ev);
        int buttons = fl.eventButtons() >> 24; // bits: 1=left, 2=middle, 4=right button
        switch (ev)
        {
        case Event.push:
            stderr.writef(", button %d down, buttons = 0x%x", fl.eventButton(), buttons);
            res = 1;
            break;
        case Event.release:
            stderr.writef(", button %d up,   buttons = 0x%x", fl.eventButton(), buttons);
            res = 1;
            break;
        case Event.mouseWheel:
            stderr.writef(", dx = %d, dy = %d", fl.eventDx(), fl.eventDy());
            res = 1;
            break;
        case Event.enter:
        case Event.leave:
            res = 1;
            break;
        case Event.move:
        case Event.drag:
            stderr.writef(",          mouse buttons = 0x%x", buttons);
            res = 1;
            break;
        case Event.keyDown:
            if (fl.eventText()[0] >= 'a' && fl.eventText()[0] <= 'z')
            {
                stderr.writef(", Text = '%s'", fl.eventText());
                res = 1;
            }
            else
            { // "ignore" everything else
                stderr.writef(", ignored '%s'", fl.eventText());
            }
            break;
        case Event.keyUp:
            res = 1;
            break;
        case Event.focus:
        case Event.unfocus:
            res = 1;
            break;
        default:
            break;
        }
        stderr.writef("\n");
        stderr.flush();
        return res;
    } /* end of handle() method */
}

// Quit button callback (closes the window)
void quitCb(Button b)
{
    b.window().hide();
}

// main program
void main(string[] args)
{
    auto win = new App(10, 10, 240, 240);
    auto quit = new Button(90, 100, 60, 40, "Quit");
    quit.box(Boxtype.thinUpBox);
    quit.callback((w) { quitCb(cast(Button) w); });
    win.end();
    win.resizable(win);
    win.show(args);
    fl.run();
}
