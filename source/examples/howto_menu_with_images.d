// D transliteration of FLTK's examples/howto-menu-with-images.cxx.
// Build: rdmd buildsamples.d examples howto_menu_with_images
import fl;
import std.format : format;

// Document icon
immutable string[] documentXpm = [
    "13 11 3 1",
    "   c None",
    "x  c #d8d8f8",
    "@  c #202060",
    " @@@@@@@@@   ",
    " @xxxxxxx@   ",
    " @xxxxxxx@   ",
    " @xxxxxxx@   ",
    " @xxxxxxx@   ",
    " @xxxxxxx@   ",
    " @xxxxxxx@   ",
    " @xxxxxxx@   ",
    " @xxxxxxx@   ",
    " @xxxxxxx@   ",
    " @@@@@@@@@   ",
];
Pixmap documentPixmap;

// Folder icon
immutable string[] folderXpm = [
    "13 11 3 1",
    "   c None",
    "x  c #d8d833",
    "@  c #808011",
    "             ",
    "     @@@@    ",
    "    @xxxx@   ",
    "@@@@@xxxx@@  ",
    "@xxxxxxxxx@  ",
    "@xxxxxxxxx@  ",
    "@xxxxxxxxx@  ",
    "@xxxxxxxxx@  ",
    "@xxxxxxxxx@  ",
    "@xxxxxxxxx@  ",
    "@@@@@@@@@@@  ",
];
Pixmap folderPixmap;

// Red "X"
immutable string[] redxXpm = [
    "13 11 5 1",
    "   c None",
    "+  c #222222",
    "x  c #555555",
    "-  c #882222",
    "@  c #ffffff",
    "   x+++x     ",
    "  ++---++    ",
    " ++-----++   ",
    "++-@@-@@-++  ",
    "++--@@@--++  ",
    "++---@---++  ",
    "++--@@@--++  ",
    "++-@@-@@-++  ",
    " ++-----++   ",
    "  ++---++    ",
    "   x+++x     ",
];
Pixmap redxPixmap;

// Handle the different menu items.. -- one callback per item, each
// capturing its own item name directly rather than stashing it in the
// menu item's void* user_data (see CONVENTIONS.md's callback-delegate note,
// which calls out menu item callbacks by name).
void menuCb(Widget w, string itemname)
{
    if (itemname == "Quit")
        w.window().hide();
    else
        message(format("'%s' would happen here", itemname));
}

// Add an image in front of item's text
int addItemToMenu(Menu_ menu,          // menu to add item to
    string labeltext,                 // label text
    int shortcut,                     // shortcut (e.g. stateCommand+'a')
    string itemname,                  // name passed to menuCb
    Pixmap pixmap,                    // image (if any) to add to item
    int flags = 0)                    // menu flags (e.g. menuDivider..)
{
    // Add a new menu item
    int i = menu.add(labeltext, shortcut, (w) { menuCb(w, itemname); }, flags);

    if (!pixmap)
        return i;
    // menu() returns const(MenuItem)*, matching FLTK's own const
    // Fl_Menu_Item* menu() -- FLTK's own sample casts the const away
    // to mutate the found item in place (multilabel() below), same here.
    MenuItem* item = cast(MenuItem*)(menu.menu() + i);

    // Create a multi label, assign it an image + text
    auto ml = new MultiLabel;

    // Left side of label is image
    ml.imageA = pixmap;

    // Right side of label is text (typeB already defaults to normalLabel)
    ml.textB = item.label();

    // Assign multilabel to item -- the recommended way since 1.4.0.
    item.multiLabel(ml);

    return i;
}

// Create Menu Items
//    This same technique works for Menu-derived widgets,
//    e.g. MenuBar, MenuButton, Choice..
void createMenuItems(Menu_ menu)
{
    // Add items with LABELS AND IMAGES using MultiLabel..
    addItemToMenu(menu, "File/New", stateCommand + 'n', "New", documentPixmap);
    addItemToMenu(menu, "File/Open", stateCommand + 'o', "Open", folderPixmap, menuDivider);
    addItemToMenu(menu, "File/Quit", stateCommand + 'q', "Quit", redxPixmap);

    // Create menu bar items with JUST LABELS
    menu.add("Edit/Copy", stateCommand + 'c', (w) { menuCb(w, "Copy"); });
    menu.add("Edit/Paste", stateCommand + 'v', (w) { menuCb(w, "Paste"); });

    // Create menu bar items with JUST IMAGES (no labels)
    //    This shows why you need MultiLabel; the item.label()
    //    gets clobbered by the item.image() setting.
    int i;
    MenuItem* item;

    // Unlike FLTK's item->image(), which pointer-puns the image
    // over the label storage and so clobbers the text as a side effect
    // (see fl.menu_item's own doc comment on why this port keeps them
    // as two separate fields instead), fldtk's image() composes
    // alongside the existing text rather than replacing it -- so
    // getting the same "image only, no label" look this demo is
    // showing off needs an explicit empty label() here too. Deliberately
    // "" and not a real `null`: this item's `text` field doing double
    // duty as the flat menu array's own end-of-(sub)menu sentinel means
    // a `null` here would silently truncate "Two"/"Three" (and anything
    // after) right out of the menu -- see fl.menu_item's next()/size()
    // doc comments. `""` is a non-null, zero-length string in D, so it
    // draws nothing without disturbing the array structure.
    i = menu.add("Images/One", 0, (w) { menuCb(w, "One"); });
    item = cast(MenuItem*)(menu.menu() + i);
    item.image(documentPixmap);
    item.label("");

    i = menu.add("Images/Two", 0, (w) { menuCb(w, "Two"); });
    item = cast(MenuItem*)(menu.menu() + i);
    item.image(folderPixmap);
    item.label("");

    i = menu.add("Images/Three", 0, (w) { menuCb(w, "Three"); });
    item = cast(MenuItem*)(menu.menu() + i);
    item.image(redxPixmap);
    item.label("");
}

void main(string[] args)
{
    documentPixmap = new Pixmap(documentXpm);
    folderPixmap = new Pixmap(folderXpm);
    redxPixmap = new Pixmap(redxXpm);

    auto win = new DoubleWindow(400, 400, "Menu items with images");
    win.tooltip("Right click on window background\nfor popup menu");

    // Help message
    auto box = new Box(100, 100, 200, 200);
    box.label(win.tooltip()); // no need to copyLabel() because it's static
    box.alignment(alignCenter | alignInside);

    // Menu bar
    auto menubar = new MenuBar(0, 0, win.w(), 25);
    createMenuItems(menubar);

    // Right click context menu
    auto menubutt = new MenuButton(0, 25, win.w(), win.h() - 25);
    createMenuItems(menubutt);
    menubutt.type(MenuButton.PopupButtons.popup3);

    // Chooser menu
    auto choice = new Choice(140, 50, 200, 25, "Choice");
    createMenuItems(choice);
    choice.value(1);

    // TODO: Show complex labels with MultiLabel. From docs:
    //
    //     "More complex labels can be constructed by setting labelb as
    //     another MultiLabel and thus chaining up a series of label
    //     elements."

    win.end();
    win.resizable(win);
    win.show(args);
    fl.run();
}
