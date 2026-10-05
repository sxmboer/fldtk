// D transliteration of FLTK's test/menubar.cxx.
// Build: rdmd buildsamples.d test menubar
import fl;
import std.format : format;
import std.stdio : writeln;

enum int terminalHeight = 120;

// Set the constant below to true to test shortcuts usually used for screen
// scaling. This should normally be false, enable only for testing!
// Note: screen scaling does not work with ctrl/+/-/0 if enabled!
enum bool overrideScalingShortcuts = false;

// Globals
Terminal gTty;

void windowCb(Widget w)
{
    writeln("window callback called"); // end of program, so stdout instead of G_tty
    (cast(DoubleWindow) w).hide();
}

void testCb(Widget w)
{
    auto mw = cast(Menu_) w;
    auto m = mw.mvalue();
    if (!m)
        gTty.printf("NULL\n");
    else if (m.shortcut_)
        gTty.printf("%s - %s\n", m.text, flShortcutLabel(m.shortcut_));
    else
        gTty.printf("%s\n", m.text);
}

void quitCb(Widget w)
{
    switch (fl.callbackReason())
    {
    case CallbackReason.selected:
        fl.hideAllWindows();
        break;
    case CallbackReason.gotFocus:
        gTty.printf("Selecting this menu item will quit this application!\n");
        break;
    case CallbackReason.lostFocus:
        gTty.printf("Risk of quitting averted.\n");
        break;
    default:
        break;
    }
}

MenuItem[100] hugemenu;

MenuItem[] menutable;

// Built at module-init time rather than as a static array-literal
// initializer: the "&Huge" entry below takes hugemenu.ptr, and a
// thread-local global's address isn't a compile-time constant in D
// (unlike FLTK C++, where a static array's address is), so the
// literal can't be CTFE'd as a top-level initializer.
static this()
{
    menutable = [
    MenuItem("foo", 0, null, menuInactive),
    MenuItem("&File", 0, null, menuSubmenu),
    MenuItem("&Open", stateAlt + 'o', null, menuInactive),
    MenuItem("&Close", 0, null),
    MenuItem("&Quit", stateAlt + 'q', (w) { quitCb(w); }, menuDivider | menuChatty),

    MenuItem("shortcut", 'a'),
    MenuItem("shortcut", stateShift + 'a'),
    MenuItem("shortcut", stateCtrl + 'a'),
    MenuItem("shortcut", stateCtrl + stateShift + 'a'),
    MenuItem("shortcut", stateAlt + 'a'),
    MenuItem("shortcut", stateAlt + stateShift + 'a'),
    MenuItem("shortcut", stateAlt + stateCtrl + 'a'),
    MenuItem("shortcut", stateAlt + stateShift + stateCtrl + 'a', null, menuDivider),
    MenuItem("shortcut", '\r' /* FL_Enter */ ),
    MenuItem("shortcut", stateCtrl + kpEnter, null, menuDivider),
    MenuItem("shortcut", f + 1),
    MenuItem("shortcut", stateShift + f + 1),
    MenuItem("shortcut", stateCtrl + f + 1),
    MenuItem("shortcut", stateShift + stateCtrl + f + 1),
    MenuItem("shortcut", stateAlt + f + 1),
    MenuItem("shortcut", stateAlt + stateShift + f + 1),
    MenuItem("shortcut", stateAlt + stateCtrl + f + 1),
    MenuItem("shortcut", stateAlt + stateShift + stateCtrl + f + 1, null, menuDivider),
    MenuItem("&Submenus", stateAlt + 'S', null, menuSubmenu),
    MenuItem("A very long menu item"),
    MenuItem("&submenu", stateCtrl + 'S', null, menuSubmenu),
    MenuItem("item 1"),
    MenuItem("item 2"),
    MenuItem("item 3"),
    MenuItem("item 4"),
    MenuItem(null),
    MenuItem("after submenu"),
    MenuItem(null),
    MenuItem(null),
    MenuItem("&Edit", f + 2, null, menuSubmenu),
    MenuItem("Undo", stateAlt + 'z', null),
    MenuItem("Redo", stateAlt + 'r', null, menuDivider),
    MenuItem("Cut", stateAlt + 'x', null),
    MenuItem("Copy", stateAlt + 'c', null),
    MenuItem("Paste", stateAlt + 'v', null),
    MenuItem("Inactive", stateAlt + 'd', null, menuInactive),
    MenuItem("Clear", 0, null, menuDivider),
    MenuItem("Invisible", stateAlt + 'e', null, menuInvisible),
    MenuItem("Preferences", 0, null),
    MenuItem("Size", 0, null),
    MenuItem(null),
    MenuItem("&Checkbox", f + 3, null, menuSubmenu),
    MenuItem("  Greek:  ", 0, null, menuHeadline, Labeltype.normalLabel, bold),
    MenuItem("&Alpha", f + 2, null, menuToggle),
    MenuItem("&Beta", 0, null, menuToggle),
    MenuItem("&Gamma", 0, null, menuToggle),
    MenuItem("&Delta", 0, null, menuToggle | menuValue),
    MenuItem("&Epsilon", 0, null, menuToggle),
    MenuItem("&Pi", 0, null, menuToggle),
    MenuItem("&Mu", 0, null, menuToggle | menuDivider),
    MenuItem("  Colors:  ", 0, null, menuHeadline, Labeltype.normalLabel, bold),
    MenuItem("Red", 0, null, menuToggle, Labeltype.normalLabel, 0, 0, 1),
    MenuItem("Black", 0, null, menuToggle | menuDivider),
    MenuItem("  Digits:  ", 0, null, menuHeadline, Labeltype.normalLabel, bold),
    MenuItem("00", 0, null, menuToggle),
    MenuItem("000", 0, null, menuToggle),
    MenuItem(null),
    MenuItem("&Radio", 0, null, menuSubmenu),
    MenuItem("&Alpha", 0, null, menuRadio),
    MenuItem("&Beta", 0, null, menuRadio),
    MenuItem("&Gamma", 0, null, menuRadio),
    MenuItem("&Delta", 0, null, menuRadio | menuValue),
    MenuItem("&Epsilon", 0, null, menuRadio),
    MenuItem("&Pi", 0, null, menuRadio),
    MenuItem("&Mu", 0, null, menuRadio | menuDivider),
    MenuItem("Red", 0, null, menuRadio),
    MenuItem("Black", 0, null, menuRadio | menuDivider),
    MenuItem("00", 0, null, menuRadio),
    MenuItem("000", 0, null, menuRadio),
    MenuItem(null),
    MenuItem("&Font", 0, null, menuSubmenu /*, 0, bold, 20*/),
    MenuItem("Normal", 0, null, 0, Labeltype.normalLabel, 0, 14),
    MenuItem("Bold", 0, null, 0, Labeltype.normalLabel, bold, 14),
    MenuItem("Italic", 0, null, 0, Labeltype.normalLabel, italic, 14),
    MenuItem("BoldItalic", 0, null, 0, Labeltype.normalLabel, bold + italic, 14),
    MenuItem("Small", 0, null, 0, Labeltype.normalLabel, bold + italic, 10),
    MenuItem("Emboss", 0, null, 0, Labeltype.embossedLabel),
    MenuItem("Engrave", 0, null, 0, Labeltype.engravedLabel),
    MenuItem("Shadow", 0, null, 0, Labeltype.shadowLabel),
    MenuItem("@->", 0, null, 0, Labeltype.normalLabel), // FL_SYMBOL_LABEL is a deprecated alias for FL_NORMAL_LABEL FLTK
    MenuItem(null),
    MenuItem("&International", 0, null, menuSubmenu),
    MenuItem("Sharp Ess", 0x0000df),
    MenuItem("A Umlaut", 0x0000c4),
    MenuItem("a Umlaut", 0x0000e4),
    MenuItem("Euro currency", stateCommand + 0x0020ac),
    MenuItem("the &\xc3\xbc Umlaut"), // &uuml;
    MenuItem("the capital &\xc3\x9c"), // &Uuml;
    MenuItem("convert \xc2\xa5 to &\xc2\xa3"), // Yen to GBP
    MenuItem("convert \xc2\xa5 to &\xe2\x82\xac"), // Yen to Euro
    MenuItem("Hangul character Sios &\xe3\x85\x85"),
    MenuItem("Hangul character Cieuc", 0x003148),
    MenuItem(null),
    MenuItem("E&mpty", 0, null, menuSubmenu),
    MenuItem(null),
    MenuItem("&Inactive", 0, null, menuInactive | menuSubmenu),
    MenuItem("A very long menu item"),
    MenuItem("A very long menu item"),
    MenuItem(null),
    MenuItem("Invisible", 0, null, menuInvisible | menuSubmenu),
    MenuItem("A very long menu item"),
    MenuItem("A very long menu item"),
    MenuItem(null),
    MenuItem("&Huge", 0, null, menuSubmenuPointer, hugemenu.ptr),
    MenuItem("button", f + 4, null, menuToggle),
    MenuItem(null),
    ];
}

MenuItem[] pulldown = [
    MenuItem("Red", stateAlt + 'r'),
    MenuItem("Green", stateAlt + 'g'),
    MenuItem("Blue", stateAlt + 'b'),
    MenuItem("Strange", stateAlt + 's', null, menuInactive),
    MenuItem("&Charm", stateAlt + 'c'),
    MenuItem("Truth", stateAlt + 't'),
    MenuItem("Beauty", stateAlt + 'b'),
    MenuItem(null),
];

version (OSX)
{
    MenuItem[] menuLocation = [
        MenuItem("MenuBar", 0, null, menuValue),
        MenuItem("SysMenuBar"),
        MenuItem(null),
    ];

    SysMenuBar smenubar;

    void menuLocationCb(Widget w, MenuBar menubar)
    {
        if ((cast(Choice) w).value() == 1)
        { // switch to system menu bar
            menubar.hide();
            auto menu = menubar.menu();
            smenubar = new SysMenuBar(0, 0, 0, 30);
            smenubar.menu(menu);
            smenubar.callback((w2) { testCb(w2); });
        }
        else
        { // switch to window menu bar
            menubar.copy(smenubar.menu());
            destroy(smenubar);
            menubar.show();
        }
    }
}

void menuLinespacingCb(Widget w)
{
    auto fvs = cast(ValueSlider) w;
    int val = cast(int) fvs.value();
    fl.menuLinespacing(val); // takes effect when someone opens a new menu..
}

enum int width = 700;

Menu_[4] menus;

void aboutCb(Widget)
{
    message("The menubar test app.");
}

class DynamicChoice : Choice
{
    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
    }

    override int handle(Event event)
    {
        static int flipFlop = 0;
        if (event == Event.beforeMenu)
        {
            // The following line is legal because we used `copy()` to create a
            // writable copy of the menu array when creating this Choice.
            MenuItem* mi = cast(MenuItem*) menu();
            if (flipFlop == 1)
            {
                mi[7].flags |= menuInactive;
                mi[8].flags &= ~menuInactive;
                flipFlop = 0;
            }
            else
            {
                mi[7].flags &= ~menuInactive;
                mi[8].flags |= menuInactive;
                flipFlop = 1;
            }
        }
        return super.handle(event);
    }
}

void main(string[] args)
{
    for (int i = 0; i < 99; i++)
        hugemenu[i].text = format("item %d", i);

    auto window = new DoubleWindow(width, 400 + terminalHeight);

    auto schemeChoice = new SchemeChoice(300, 50, 100, 25, "&scheme");

    gTty = new Terminal(0, 400, width, terminalHeight);

    window.callback((w) { windowCb(w); });
    auto menubar = new MenuBar(0, 0, width, 30);
    menubar.menu(menutable);
    menubar.callback((w) { testCb(w); });
    menus[0] = menubar;
    auto mb1 = new MenuButton(100, 100, 120, 25, "&menubutton");
    mb1.menu(pulldown);
    mb1.tooltip("this is a menu button");
    mb1.callback((w) { testCb(w); });
    menus[1] = mb1;
    auto ch = new DynamicChoice(300, 100, 80, 25, "&choice:");
    ch.copy(pulldown);
    // FLTK's single-string add(const char*) is the |-separated,
    // \t-shortcut Forms-compat convenience form (CONVENTIONS.md's "Out of
    // scope: XForms/Forms Library compatibility" -- fl_old_shortcut()
    // parsing) and isn't ported; neither label has a '|' or '\t', so
    // this is exactly equivalent (see Fl_Menu_::add(const char*)'s own
    // body -- it reduces to add(buf, 0, 0, 0, 0) for a plain label).
    ch.add("Flip", 0, null);
    ch.add("Flop", 0, null);
    ch.tooltip("this is a choice menu");
    ch.callback((w) { testCb(w); });
    menus[2] = ch;
    auto mb = new MenuButton(0, 0, width, 400, "&popup");
    mb.type(MenuButton.PopupButtons.popup3);
    mb.menu(menutable);
    mb.remove(1); // delete the "File" submenu
    mb.callback((w) { testCb(w); });
    menus[3] = mb;
    auto b = new Box(200, 200, 200, 100, "Press right button\nfor a pop-up menu");
    window.resizable(mb);
    window.sizeRange(300, 400, 0, 400 + terminalHeight);

    version (OSX)
    {
        auto ch2 = new Choice(500, 100, 150, 25, "Use:");
        ch2.menu(menuLocation);
        ch2.callback((w) { menuLocationCb(w, menubar); });
        ch2.value(1);
        menuLocationCb(ch2, menubar);
    }

    auto menuLinespacingSlider = new ValueSlider(500, 150, 150, 20, "fl.menuLinespacing()");
    menuLinespacingSlider.tooltip("Changes the line spacing between all menu items");
    menuLinespacingSlider.type(1);
    //menuLinespacingSlider.labelsize(14);
    menuLinespacingSlider.value(fl.menuLinespacing());
    menuLinespacingSlider.color(cast(Color) 46);
    menuLinespacingSlider.selectionColor(cast(Color) 1);
    //menuLinespacingSlider.textsize(10);
    menuLinespacingSlider.alignment(alignLeft);
    menuLinespacingSlider.range(0.1, 50.0);
    menuLinespacingSlider.step(1.0);
    menuLinespacingSlider.callback((w) { menuLinespacingCb(w); });

    window.end();

    SysMenuBar.about((w) { aboutCb(w); });

    version (OSX)
    {
        MenuItem[] custom = [
            MenuItem("Preferences…", 0, (w) { testCb(w); }, menuDivider),
            MenuItem("Radio1", 0, (w) { testCb(w); }, menuRadio | menuValue),
            MenuItem("Radio2", 0, (w) { testCb(w); }, menuRadio | menuDivider),
            MenuItem(null),
        ];
        MacAppMenu.customApplicationMenuItems(custom);
        //SysMenuBar.windowMenuStyle(SysMenuBar.noWindowMenu);
    }

    window.show(args);
    fl.run();
}
