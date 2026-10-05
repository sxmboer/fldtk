// D transliteration of FLTK's examples/menubar-add.cxx.
// Build: rdmd buildsamples.d examples menubar_add
import fl;
import std.stdio : stderr;

// This callback is invoked whenever the user clicks an item in the menu bar
void myMenuCallback(Widget w)
{
    auto bar = cast(MenuBar) w;         // Get the menubar widget
    auto item = bar.mvalue();           // Get the menu item that was picked

    string ipath = bar.itemPathname();  // Get full pathname of picked item

    stderr.writef("callback: You picked '%s'", item.label()); // Print item picked
    stderr.writef(", item_pathname() is '%s'", ipath);         // ..and full pathname

    if (item.flags & (menuRadio | menuToggle)) // Toggle or radio item?
        stderr.writef(", value is %s", item.value() ? "on" : "off"); // Print item's value
    stderr.writeln();
    if (item.label() == "Google")
    {
        string msg;
        openUri("http://google.com/", msg);
    }
    if (item.label() == "&Quit")
        fl.hideAllWindows();
}

void main()
{
    scheme("gtk+");
    auto win = new Window(400, 200, "menubar-simple");     // Create window
    auto menu = new MenuBar(0, 0, 400, 25);                 // Create menubar, items..
    menu.add("&File/&Open", stateCtrl + 'o', (w) { myMenuCallback(w); });
    menu.add("&File/&Save", stateCtrl + 's', (w) { myMenuCallback(w); }, menuDivider);
    menu.add("&File/&Quit", stateCtrl + 'q', (w) { myMenuCallback(w); });
    menu.add("&Edit/&Copy", stateCtrl + 'c', (w) { myMenuCallback(w); });
    menu.add("&Edit/&Paste", stateCtrl + 'v', (w) { myMenuCallback(w); }, menuDivider);
    menu.add("&Edit/Radio 1", 0, (w) { myMenuCallback(w); }, menuRadio);
    menu.add("&Edit/Radio 2", 0, (w) { myMenuCallback(w); }, menuRadio | menuDivider);
    menu.add("&Edit/Toggle 1", 0, (w) { myMenuCallback(w); }, menuToggle);              // Default: off
    menu.add("&Edit/Toggle 2", 0, (w) { myMenuCallback(w); }, menuToggle);              // Default: off
    menu.add("&Edit/Toggle 3", 0, (w) { myMenuCallback(w); }, menuToggle | menuValue);   // Default: on
    menu.add("&Help/Google", 0, (w) { myMenuCallback(w); });

    // Example: show how we can dynamically change the state of item Toggle #2 (turn it 'on')
    {
        // findItem() returns const(MenuItem)*, matching FLTK's
        // const Fl_Menu_Item* find_item() -- FLTK's sample casts
        // the const away to call the mutating set() below, same here.
        auto item = cast(MenuItem*) menu.findItem("&Edit/Toggle 2"); // Find item
        if (item)
            item.set();                              // Turn it on
        else
            stderr.writeln("'Toggle 2' item not found?!"); // (optional) Not found? complain!
    }

    win.end();
    win.show();
    fl.run();
}
