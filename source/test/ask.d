// D transliteration of FLTK's test/ask.cxx.
// Build: rdmd buildsamples.d test ask
import fl;
import std.conv : to;

// Button callback: what == 0 ("input") or 1 ("password")
void renameButton(Widget o, int what)
{
    // fldtk's fl_input()/fl_password() already distinguish cancel
    // (returns null) from an OK'd empty string (returns ""), matching
    // FLTK's separate fl_input_str(int&,...)/fl_password_str(int&,...)
    // ret-out-param overloads -- no need for those separately.
    string input;
    if (what == 0)
    {
        messageIconLabel("§");
        input = fl_input("Input (no size limit, use ctrl/j for newline):", o.label());
    }
    else
    {
        messageIconLabel("€");
        input = password("Enter password (max. 20 characters):", o.label(), 20);
    }
    if (input !is null)
    {
        o.copyLabel(input);
        o.redraw();
    }
}

void windowCallback(Widget win)
{
    int hotspot = messageHotspot();
    messageHotspot(0);
    messageTitle("note: no hotspot set for this dialog");
    int rep = choice("Are you sure you want to quit?", "Cancel", "Quit", "Dunno");
    messageHotspot(hotspot);
    if (rep == 1)
        fl.hideAllWindows();
    else if (rep == 2) // (Dunno)
    {
        messagePosition(win);
        messageTitle("This dialog must be centered over the main window");
        message("Well, maybe you should know before we quit.");
    }
}

/*
  This timer callback shows a message dialog (fl_choice) window
  every 5 seconds to test "recursive" (aka nested) common dialogs.

  The timer can be stopped by clicking the button "Stop these funny popups"
  or pressing the Enter key.
*/
void timerCb()
{
    static bool stop = false;
    static int n = 0;
    enum double delta = 5.0; // delay of popups
    enum int nmax = 10;      // limit no. of popups

    n++;
    if (n >= nmax) stop = true;

    Box messageIcon = fl.ask.messageIcon();

    if (stop)
    {
        messageIcon.color(white);
        return;
    }

    fl.repeatTimeout(delta, () { timerCb(); });

    // Change the icon box color:
    Color c = messageIcon.color();
    c = (c + 1) % 32;
    if (c == messageIcon.labelcolor()) c++;
    messageIcon.color(c);

    // test message title assignment with a local buffer
    {
        string buf = "Message #" ~ n.to!string;
        messageTitle(buf);
    }

    // pop up a message:
    stop = stop || (choice(
        "Timeout. Click the 'Close' button or press Escape.\n"
        ~ "Note: this message had been blocked in FLTK 1.3\n"
        ~ "and earlier if another message window was open.\n"
        ~ "This message should pop up every 5 seconds (max. 10 times)\n"
        ~ "in FLTK 1.4 and later until stopped by clicking the button\n"
        ~ "below or by pressing the Enter (Return) key.\n",
        "Close", "Stop these funny popups", null) != 0);
}

void main(string[] args)
{
    string buffer = "Test text";
    string buffer2 = "MyPassword";

    // This is a test to make sure automatic destructors work. Pop up
    // the question dialog several times and make sure it doesn't crash.

    auto window = new DoubleWindow(200, 105);
    auto b = new ReturnButton(20, 10, 160, 35, buffer);
    b.callback((w) { renameButton(w, 0); });
    auto b2 = new Button(20, 50, 160, 35, buffer2);
    b2.callback((w) { renameButton(w, 1); });
    window.end();
    window.resizable(b);
    window.show(args);

    // Also we test to see if the exit callback works:
    window.callback((w) { windowCallback(w); });

    // Test: multiple (nested, aka "recursive") popups (see timerCb())
    fl.addTimeout(5.0, () { timerCb(); });

    fl.run();
}
