// D transliteration of FLTK's test/browser.cxx (~/Repositories/fltk).
// Part of the samples/ contract -- see samples/README.md.
// Check: ./samples/build.sh browser
import fl;
import std.format : format;
import std.conv : to, ConvException;
import std.string : strip;

SelectBrowser browser;
Button top, bottom, middle, visible, swap, sort;
Choice btype;
Choice wtype;
IntInput field;
Terminal tty;

struct WhenItem
{
    string name;
    When wvalue;
}

// `When` chooser -- labels are the D-side `fl.enumerations` constant
// spelling, not FLTK's C `FL_WHEN_*` macro names: this sample
// exists to teach a D programmer which `fldtk` symbol to reach for, not
// to document what the original C++ constant was called.
WhenItem[] whenItems = [
    WhenItem("whenNever", whenNever),
    WhenItem("whenChanged", whenChanged),
    WhenItem("whenNotChanged", whenNotChanged),
    WhenItem("whenRelease", whenRelease),
    WhenItem("whenReleaseAlways", whenReleaseAlways),
    WhenItem("whenEnterKey", whenEnterKey),
    WhenItem("whenEnterKeyAlways", whenEnterKeyAlways),
    WhenItem("whenEnterKeyChanged", whenEnterKeyChanged),
    WhenItem("whenEnterKey + whenReleaseAlways", whenEnterKey + whenReleaseAlways),
    // TODO: Perhaps other When combos are relevant
];

void bCb(Widget o)
{
    tty.printf("callback, selection = \033[31m%d\033[0m, event_clicks = \033[32m%d\033[0m\n",
        (cast(Browser) o).value(), fl.eventClicks());
}

void showCb(Widget o)
{
    // FLTK reads this via atoi(), which silently returns 0 for an
    // unparseable (here: empty -- field is an IntInput, so anything
    // typed is already digits-only) string rather than throwing;
    // to!int() has no such fallback, so a `ConvException` needs
    // catching to match atoi()'s "0 on empty input" behavior.
    int line = 0;
    try line = field.value().to!int;
    catch (ConvException) {}

    if (!line)
    {
        alert("Please enter a number in the text field\n"
            ~ "before clicking on the buttons.");
        return;
    }

    if (o is top)
        browser.topline(line);
    else if (o is bottom)
        browser.bottomline(line);
    else if (o is middle)
        browser.middleline(line);
    else
        browser.makeVisible(line);
}

void swapCb(Widget)
{
    int a = -1, b = -1;
    for (int t = 0; t < browser.size(); t++) // find two selected items
    {
        if (browser.selected(t))
        {
            if (a < 0) a = t;
            else { b = t; break; }
        }
    }
    browser.swap(a, b); // swap them
}

void sortCb(Widget)
{
    browser.sort(sortAscending);
}

void btypeCb(Widget)
{
    // Switching browser type is not a typical use, so we want to make sure that
    // everything is deselected, resetting internal variables.
    browser.deselect(true);
    if (btype.text() == "Normal") browser.type(normalBrowser);
    else if (btype.text() == "Select") browser.type(selectBrowser);
    else if (btype.text() == "Hold") browser.type(holdBrowser);
    else if (btype.text() == "Multi") browser.type(multiBrowser);
    // Reset the selections again, so all class member variables are matching
    // the new browser type.
    browser.deselect(false);
    // Set the focus rect to the topmost item without selecting it.
    browser.select(1, false);
    browser.redraw();
}

void wtypeCb(Widget)
{
    if (wtype.value() < 0) return;
    browser.when(whenItems[wtype.value()].wvalue); // when value based on array
}

void main()
{
    // FLTK parses argc/argv here (Fl::args_to_utf8/Fl::args) to pick an
    // optional filename to load into the browser, falling back to its own
    // source file; dropped along with argc/argv (see samples/README.md and
    // test/button.cxx's precedent), keeping just the fallback filename.
    // ".d", not FLTK's ".cxx" -- this port's own source file, not
    // FLTK's.
    string fname = "browser.d";
    auto window = new DoubleWindow(720, 520, fname);
    browser = new SelectBrowser(0, 0, window.w(), 350, null);
    browser.type(multiBrowser);
    browser.callback((w) { bCb(w); });
    if (!browser.load(fname))
    {
        message(format("Can't load '%s'\n", fname));
        browser.add("This is a test of how the browser draws lines.");
        browser.add("This is a second line.");
        browser.add("This is a third.");
        browser.add("@bBold text");
        browser.add("@iItalic text");
    }
    browser.vposition(0);

    field = new IntInput(55, 350, window.w() - 55, 25, "Line #:");
    field.callback((w) { showCb(w); });

    top = new Button(0, 375, 80, 25, "Top");
    top.callback((w) { showCb(w); });

    bottom = new Button(80, 375, 80, 25, "Bottom");
    bottom.callback((w) { showCb(w); });

    middle = new Button(160, 375, 80, 25, "Middle");
    middle.callback((w) { showCb(w); });

    visible = new Button(240, 375, 80, 25, "Make Vis.");
    visible.callback((w) { showCb(w); });

    swap = new Button(320, 375, 80, 25, "Swap");
    swap.callback((w) { swapCb(w); });
    swap.tooltip("Swaps two selected lines\n(Use CTRL-click to select two lines)");

    sort = new Button(400, 375, 80, 25, "Sort");
    sort.callback((w) { sortCb(w); });

    btype = new Choice(480, 375, 80, 25);
    btype.add("Normal", 0, null);
    btype.add("Select", 0, null);
    btype.add("Hold", 0, null);
    btype.add("Multi", 0, null);
    btype.callback((w) { btypeCb(w); });
    btype.value(3);
    btype.tooltip("Changes the browser type()");

    wtype = new Choice(560, 375, 160, 25);
    wtype.textsize(8);
    // Append items from whenItems[] array
    foreach (item; whenItems)
        wtype.add(item.name, 0, null);
    wtype.callback((w) { wtypeCb(w); });
    wtype.value(4); // whenReleaseAlways is Fl_Browser's default

    // Small terminal window for callback messages
    tty = new Terminal(0, 400, 720, 120);
    tty.historyLines(50);
    tty.ansi(true);

    window.resizable(browser);
    window.show();
    fl.run();
}
