// D transliteration of FLTK's test/handle_keys.cxx.
// Build: rdmd buildsamples.d test handle_keys
import fl;
import flterminal = fl.terminal;
import std.format : format;

// Global variables to simplify the code

CheckButton keydown;
CheckButton keyup;
CheckButton shortcut;
CheckButton scaling;

// Text in the headline and after clearing the terminal buffer. For alignment ...
//          1         2         3         4         5         6         7         8
// 1234567890123456789012345678901234567890123456789012345678901234567890123456789012345
string headlineText = "[nnn] Event           Key     Name,  Flags: C A S M N L  Text  Unicode   UTF-8/hex";

enum int lkn = 14; // length of key name field

// Tooltip for headline and terminal widgets
string tt = "Flags:\n"
    ~ "C=Ctrl, A=Alt, S=Shift, M=Meta\n"
    ~ "N=NumLock, L=CapsLock";

// This table is a duplicate of the table in test/keyboard.cxx.
// In the future this should be moved to the FLTK core so FLTK key
// numbers can be translated to strings (key names) in user programs.
struct KeycodeTable
{
    int n; // key code
    string text; // key name
}

// Display names use fldtk's own bare D constant spelling (matching the
// convention CONVENTIONS.md's convention established for cursor.d/browser.d/
// chart_simple.d), not FLTK's C `FL_*` macro name -- these strings
// exist specifically to teach a D programmer which constant a given key
// maps to, and `Keysym` (fl.enumerations) is an open manifest-constant
// set ported as bare constants, not a closed enum, so no type-qualifying
// prefix is shown either (matching e.g. `When`'s bare `whenNever` style).
KeycodeTable[] keyTable = [
    KeycodeTable(escape, "escape"),
    KeycodeTable(backSpace, "backSpace"),
    KeycodeTable(tab, "tab"),
    KeycodeTable(isoKey, "isoKey"),
    KeycodeTable(fl.enumerations.enter, "enter"),
    KeycodeTable(print, "print"),
    KeycodeTable(scrollLock, "scrollLock"),
    KeycodeTable(pause, "pause"),
    KeycodeTable(insert, "insert"),
    KeycodeTable(home, "home"),
    KeycodeTable(pageUp, "pageUp"),
    KeycodeTable(deleteKey, "deleteKey"),
    KeycodeTable(end, "end"),
    KeycodeTable(pageDown, "pageDown"),
    KeycodeTable(left, "left"),
    KeycodeTable(up, "up"),
    KeycodeTable(right, "right"),
    KeycodeTable(down, "down"),
    KeycodeTable(shiftL, "shiftL"),
    KeycodeTable(shiftR, "shiftR"),
    KeycodeTable(controlL, "controlL"),
    KeycodeTable(controlR, "controlR"),
    KeycodeTable(capsLock, "capsLock"),
    KeycodeTable(altL, "altL"),
    KeycodeTable(altR, "altR"),
    KeycodeTable(metaL, "metaL"),
    KeycodeTable(metaR, "metaR"),
    KeycodeTable(menu, "menu"),
    KeycodeTable(help, "help"),
    KeycodeTable(numLock, "numLock"),
    KeycodeTable(kpEnter, "kpEnter"),
    KeycodeTable(altGr, "altGr"),
];

// This function is very similar to the code in test/keyboard.cxx.
// In the future this should be moved to the FLTK core so FLTK key
// numbers can be translated to strings (key names) in user programs.
//
// Returns:
//  - function return is the key name string
//  - parameter lg returns the length in characters (not bytes)
// The latter can be used to align strings.
//
// Todo: this function may not be complete yet and is
//       maybe not correct for all key values.
string getKeyname(int k, out int lg)
{
    lg = 0;
    if (!k)
    {
        lg = 1;
        return "0";
    }
    else if (k < 32)
    { // control character
        string s = format("^%c", cast(char)(k + 64));
        lg = cast(int) s.length;
        return s;
    }
    else if (k < 128)
    { // ASCII
        string s = format("'%c'", cast(char) k);
        lg = cast(int) s.length;
        return s;
    }
    else if (k >= 0xa0 && k <= 0xff)
    { // ISO-8859-1 (international keyboards)
        char[8] key;
        int kl = utf8Encode(cast(uint) k, key[]);
        string s = format("'%s'", key[0 .. kl]);
        lg = cast(int) s.length;
        return s;
    }
    else if (k > f && k <= fLast)
    {
        string s = format("f+%d", k - f);
        lg = cast(int) s.length;
        return s;
    }
    else if (k >= kp && k <= kpLast)
    {
        string s;
        if (k == kpEnter)
            s = "kpEnter";
        else
            s = format("kp+'%c'", k - kp);
        lg = cast(int) s.length;
        return s;
    }
    else if (k >= button && k <= button + 7)
    {
        string s = format("button+%d", k - button);
        lg = cast(int) s.length;
        return s;
    }
    else
    {
        foreach (entry; keyTable)
        {
            if (entry.n == k)
            {
                lg = cast(int) entry.text.length;
                return entry.text;
            }
        }
        string s = format("0x%04x", k);
        lg = cast(int) s.length;
        return s;
    }
}

class Terminal : flterminal.Terminal
{
    override int handle(Event ev)
    {
        switch (ev)
        {
        case Event.keyDown:
        case Event.keyUp:
        case Event.shortcut:
            return 0;
        default:
            break;
        }
        return super.handle(ev);
    }

    this(int x, int y, int w, int h)
    {
        super(x, y, w, h);
    }
}

// Class to handle events
class App : DoubleWindow
{
    // storage for the last event
    int eventnum;
    string eventname;
    Terminal tty;
    Box headline;

    this(int x, int y, int w, int h, string l = null)
    {
        super(x, y, w, h, l);
        eventname = null;
        eventnum = 0;
        headline = new Box(2, 0, w - 4, 25);
        headline.color(light2);
        headline.box(Boxtype.flatBox);
        headline.alignment(alignLeft | alignInside);
        headline.labelfont(courier);
        headline.labelsize(12);
        headline.label(headlineText);
        headline.tooltip(tt);
        tty = new Terminal(0, 25, w, h - 100);
        tty.color(white);
        tty.textfgcolor(darker(blue));
        tty.selectionbgcolor(blue);
        tty.selectionfgcolor(white);
        tty.textfont(courier);
        tty.textsize(12);
        // tty.selectionColor(red);
        tty.tooltip(tt);
    }

    // print_event() counts and prints the current event.
    // Returns 1 if printed (used), 0 if suppressed.
    // The event counter is incremented only if the event is printed
    // and wraps at 1000.
    int printEvent(Event ev)
    {
        switch (ev)
        {
        case Event.keyDown:
            if (!keydown.value())
                return 0;
            tty.textfgcolor(black);
            break;
        case Event.keyUp:
            if (!keyup.value())
                return 0;
            tty.textfgcolor(blue);
            break;
        case Event.shortcut:
            if (!shortcut.value())
                return 0;
            tty.textfgcolor(cast(Color) 0x00aa0000); // dark green
            break;
        default:
            return 0;
        }
        eventnum++;
        eventnum %= 1000;
        eventname = eventNames[ev];
        tty.printf("[%3d] %-12s", eventnum, eventname);
        return 1;
    } // app::print_event()

protected:
    // Event handling
    override int handle(Event ev)
    {
        int res = super.handle(ev);
        // filter and output keyboard events only
        if (!printEvent(ev))
            return res;

        string etxt = fl.eventText();
        int ekey = fl.eventKey();
        int elen = cast(int) fl.eventLength();
        char ctrl = (fl.eventState() & stateCtrl) ? 'C' : '.';
        char alt = (fl.eventState() & stateAlt) ? 'A' : '.';
        char shift = (fl.eventState() & stateShift) ? 'S' : '.';
        char meta = (fl.eventState() & stateMeta) ? 'M' : '.';
        char numlk = (fl.eventState() & stateNumLock) ? 'N' : '.';
        char capslk = (fl.eventState() & stateCapsLock) ? 'L' : '.';

        int lg = 0;
        string ekns = format("0x%04x", ekey); // may be up to 10 chars
        tty.printf("%10s  ", ekns); // event key number (hex)

        tty.printf("%s", getKeyname(ekey, lg));
        if (lg < lkn)
        {
            for (int i = 0; i < lkn - lg; i++)
                tty.appendAscii(" ");
        }

        tty.printf("%c %c %c %c %c %c  ", ctrl, alt, shift, meta, numlk, capslk);

        if (elen)
        {
            if (elen == 1 && etxt[0] < 32)
            { // control character (0-31)
                tty.printf("'^%c' ", cast(char)(etxt[0] + 64));
            }
            else
            {
                tty.printf("'%s'  ", etxt);
            }
            int n;
            uint ucs = utf8DecodeAt(etxt, 0, n);
            tty.printf(" U+%04x   ", ucs);
            for (int i = 0; i < elen; i++)
                tty.printf(" %02x", etxt[i] & 0xff);
        }
        else
        {
            tty.printf("'' ");
        }
        tty.textfgcolor(black);
        tty.printf("\n");
        return res;
    } // app::handle()
}

// Quit button callback: closes the window
void quitCb(Widget w)
{
    w.window().hide();
}

// Clear button callback: clears the terminal widget
void clearCb(Button b)
{
    auto tty = (cast(App) b.window()).tty;
    tty.clearScreenHome();
    tty.clearHistory();
    tty.printf("%s\n", headlineText); // helpful if copied to the clipboard
    tty.redraw();
    tty.takeFocus();
}

// Copy button callback: copies the selected text to the clipboard
void copyCb(Widget b)
{
    auto tty = (cast(App) b.window()).tty;
    string what = "Full";
    string text;
    int tlen = tty.selectionTextLen();
    if (tlen > 0)
    {
        text = tty.selectionText();
        what = "Selected";
    }
    else
    {
        text = tty.text();
    }
    tlen = cast(int) text.length;
    fl.copy(text, 1); // 1 == CLIPBOARD selection; fldtk's copy() is text-only, no type param needed
    tty.printf("[%s text copied to clipboard, length = %d]\n", what, tlen);
    tty.takeFocus();
}

// Callback for all (light) buttons
void toggleCb(Widget w)
{
    auto tty = (cast(App) w.window()).tty;
    tty.takeFocus();
}

// Toggle recognition of GUI scaling shortcuts
void toggleScaling(Widget w)
{
    int toggle = (cast(Button) w).value() ? 1 : 0;
    fl.keyboardScreenScaling(toggle != 0);
    if (toggle)
    {
        auto tty = (cast(App) w.window()).tty;
        bool simpleZoom = fl.option(Option.simpleZoomShortcut);
        tty.printf("GUI-Scaling = %s, OPTION_SIMPLE_ZOOM_SHORTCUT = %s\n",
                toggle ? "ON" : "OFF", simpleZoom ? "ON" : "OFF");
    }
    toggleCb(w); // give focus to 'app'
}

// Window close callback (Esc does not close the window)
void closeCb(Widget win)
{
    if (fl.event() == Event.shortcut)
        return;
    win.hide();
}

// Main program
void main(string[] args)
{
    enum int ww = 700, wh = 400;
    auto win = new App(0, 0, ww, wh);
    win.tty.box(Boxtype.downBox);
    win.tty.showUnknown(true);
    win.tty.textfgcolor(black);
    win.tty.printf("Please press any key ...\n");

    auto grid = new Grid(0, wh - 75, ww, 75);
    grid.layout(2, 5, 5, 5);

    keydown = new CheckButton(0, 0, 80, 30, "Keydown");
    grid.widget(keydown, 0, 0);
    keydown.value(1);
    keydown.callback((w) { toggleCb(w); });
    keydown.tooltip("Show FL_KEYDOWN aka FL_KEYBOARD events");

    keyup = new CheckButton(0, 0, 80, 30, "Keyup");
    grid.widget(keyup, 0, 1);
    keyup.value(0);
    keyup.callback((w) { toggleCb(w); });
    keyup.tooltip("Show FL_KEYUP events");

    shortcut = new CheckButton(0, 0, 80, 30, "Shortcut");
    grid.widget(shortcut, 0, 2);
    shortcut.value(0);
    shortcut.callback((w) { toggleCb(w); });
    shortcut.tooltip("Show FL_SHORTCUT events");

    scaling = new CheckButton(0, 0, 80, 30, "GUI scaling");
    grid.widget(scaling, 0, 3);
    scaling.value(0);
    scaling.callback((w) { toggleScaling(w); });
    scaling.tooltip("Use GUI scaling shortcuts");
    toggleScaling(scaling);

    auto clear = new Button(0, 0, 80, 30, "Clear");
    grid.widget(clear, 1, 0);
    clear.callback((w) { clearCb(cast(Button) w); });
    clear.tooltip("Clear the display");

    auto copy = new Button(0, 0, 80, 30, "Copy");
    grid.widget(copy, 1, 1);
    copy.callback((w) { copyCb(w); });
    copy.tooltip("Copy terminal contents to clipboard");

    auto quit = new Button(ww - 70, wh - 50, 80, 30, "Quit");
    grid.widget(quit, 1, 4);
    quit.box(Boxtype.thinUpBox);
    quit.callback((w) { quitCb(w); });
    quit.tooltip("Exit the program");

    grid.end();
    win.end();
    win.callback((w) { closeCb(w); });
    win.resizable(win.tty);
    win.sizeRange(660, 300);
    win.show(args);
    fl.run();
}
