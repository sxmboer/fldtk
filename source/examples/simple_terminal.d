// D transliteration of FLTK's examples/simple-terminal.cxx.
// Build: rdmd buildsamples.d examples simple_terminal
import fl;
import std.datetime.systime : Clock;

enum terminalHeight = 120;

// Globals
DoubleWindow gWin;
Box gBox;
Terminal gTty;

// Append a date/time message to the terminal every 2 seconds
void tickCb()
{
    auto now = Clock.currTime();
    gTty.printf("Timer tick: \033[32m%s\033[0m\n", now.toSimpleString());
    fl.repeatTimeout(2.0, () { tickCb(); });
}

void main()
{
    gWin = new DoubleWindow(500, 200 + terminalHeight, "Your App");
    gWin.begin();

    gBox = new Box(0, 0, gWin.w(), 200,
            "Your app GUI in this area.\n\n"
            ~ "Your app's debugging output in tty below");

    // Add simple terminal to bottom of app window for scrolling history of status messages.
    gTty = new Terminal(0, 200, gWin.w(), terminalHeight);
    gTty.ansi(true); // enable use of "\033[32m"

    gWin.end();
    gWin.resizable(gWin);
    gWin.show();
    fl.addTimeout(0.5, () { tickCb(); });
    fl.run();
}
