// Every widget of Fluid's widget bin, in the bin's order, each with its
// bin icon and name: the pictures for docs/TECHNICAL_REFERENCE.md.
// Build: rdmd buildsamples.d test widget_gallery
// Run:   build/widget_gallery
// Make the pictures, from the fldtk folder:
//        build/widget_gallery --capture docs/widgets
//
// With --capture <folder>, the program shows its window, writes one PNG
// per cell into the folder (named after the widget: button.png,
// value_slider.png, ...) and quits. Each picture is the cell's widget,
// without its icon and name, with a narrow margin of window background
// around it, drawn offscreen at 100% scale. The menu items' picture shows the
// Menu Button with its menu open: the program opens the menu, draws it
// and closes it again with Escape.
//
// One tab per group of the widget bin (Groups, Buttons, Valuators, Text,
// Menus, Browsers, Misc), in the default scheme and colours. Each widget
// sits in its own cell: the bin's icon, the widget's name, and the
// widget below them, with some content to show. The icons are read from
// source/fluid/pixmaps_svg/ (found from build/ or the current folder);
// without them the cells show only the names.
import fl;
import std.file : exists, mkdirRecurse, thisExePath;
import std.path : buildPath, dirName;
import std.stdio : stderr, writeln;

enum int winW = 980, winH = 700;
enum int areaX = 20, areaY = 45, areaW = winW - 40;
enum int iconSize = 24, gap = 20;

string iconDir;
int cx, cy, rowH;   // where the next cell goes, and the height of its row

// One cell, for --capture: the page it is on, the top left corner of its
// widget area, and its widgets, which are the page's children from
// `first` up to the next cell's (`last`, -1 for the page's last cell).
struct Shot
{
    string file;
    FlGroup page;
    int x, y;
    int first, last = -1;
}
Shot[] shots;
FlGroup curPage;
MenuButton menuItemsButton;   // the Menu Button whose open menu is menu_items.png

// Starts a new tab page for a group of the widget bin.
FlGroup page(string label)
{
    auto g = new FlGroup(10, 35, winW - 20, winH - 45, label);
    curPage = g;
    cx = areaX;
    cy = areaY;
    rowH = 0;
    return g;
}

// A cell for one widget: its bin icon (or icons, separated by commas)
// and name, and below them an area of w x h for the widget, whose top
// left corner it returns.
void cell(string name, string icons, int w, int h, out int x, out int y)
{
    import std.algorithm : splitter;
    if (shots.length && shots[$ - 1].page is curPage && shots[$ - 1].last < 0)
        shots[$ - 1].last = curPage.children();
    int ch = iconSize + 6 + h;
    if (cx + w > areaX + areaW)
    {
        cx = areaX;
        cy += rowH + gap;
        rowH = 0;
    }
    int nx = cx;
    foreach (icon; icons.splitter(','))
    {
        if (icon.length == 0) continue;
        auto ib = new Box(nx, cy, iconSize, iconSize);
        string path = iconDir.length ? buildPath(iconDir, icon ~ ".svg") : null;
        if (path.length && exists(path))
        {
            auto img = new SvgImage(path);
            img.scale(iconSize, iconSize);
            ib.image(img);
        }
        nx += iconSize + 6;
    }
    auto nb = new Box(nx, cy, cx + w - nx, iconSize, name);
    nb.labelfont(helveticaBold);
    nb.alignment(alignLeft | alignInside);
    x = cx;
    y = cy + iconSize + 6;
    cx += w + gap;
    shots ~= Shot(shotFile(name), curPage, x, y, curPage.children());
    if (ch > rowH) rowH = ch;
}

// A small table of numbers, with row and column headers.
class GalleryTable : Table
{
    this(int x, int y, int w, int h)
    {
        super(x, y, w, h);
        rows(8);
        cols(5);
        colHeader(true);
        rowHeader(true);
        colWidthAll(56);
        rowHeightAll(22);
        end();
    }

    override protected void drawCell(TableContext context, int R = 0, int C = 0,
        int X = 0, int Y = 0, int W = 0, int H = 0)
    {
        import std.conv : to;
        switch (context)
        {
        case contextStartpage:
            fl_font(helvetica, normalSize);
            return;
        case contextColHeader, contextRowHeader:
            string s = context == contextColHeader ? [cast(immutable char)('A' + C)] : (R + 1).to!string;
            pushClip(X, Y, W, H);
            drawBoxAt(Boxtype.thinUpBox, X, Y, W, H, colHeaderColor());
            fl_color(foregroundColor);
            fl_draw(s, X, Y, W, H, alignCenter);
            popClip();
            return;
        case contextCell:
            pushClip(X, Y, W, H);
            fl_color(background2Color);
            fl_rectf(X, Y, W, H);
            fl_color(foregroundColor);
            fl_draw(((R + 1) * (C + 1)).to!string, X, Y, W - 6, H, alignRight);
            fl_color(light2);
            fl_rect(X, Y, W, H);
            popClip();
            return;
        default:
            return;
        }
    }
}

void groupsPage()
{
    int x, y;
    page("Groups");

    cell("Window", "flWindow", 280, 150, x, y);
    auto sub = new Window(x, y, 280, 150, "Window");
    sub.box(Boxtype.upBox);
    new Box(10, 10, 260, 90, "A program's window holds\nits widgets. Shown here as a\nwindow inside a window.");
    new Button(190, 112, 80, 25, "Close");
    sub.end();

    cell("Group", "flGroup", 280, 150, x, y);
    auto g = new FlGroup(x, y + 15, 280, 135, "Group");
    g.box(Boxtype.engravedFrame);
    g.alignment(alignTopLeft);
    new CheckButton(x + 15, y + 30, 150, 25, "Keep backups");
    new CheckButton(x + 15, y + 60, 150, 25, "Show hidden files");
    new Button(x + 185, y + 110, 80, 25, "Apply");
    g.end();

    cell("Pack", "flPack", 280, 150, x, y);
    auto p = new Pack(x, y, 280, 30);
    p.type(packHorizontal);
    p.spacing(5);
    new Button(0, 0, 80, 30, "One");
    new Button(0, 0, 60, 30, "Two");
    new Button(0, 0, 100, 30, "Three");
    p.end();

    cell("Tabs", "flTabs", 280, 150, x, y);
    auto t = new Tabs(x, y, 280, 150);
    auto t1 = new FlGroup(x, y + 25, 280, 125, "General");
    new Input(x + 80, y + 45, 180, 25, "Name:");
    new Input(x + 80, y + 80, 180, 25, "E-mail:");
    t1.end();
    auto t2 = new FlGroup(x, y + 25, 280, 125, "Advanced");
    t2.end();
    new FlGroup(x, y + 25, 280, 125, "About").end();
    t.end();

    cell("Scroll", "flScroll", 280, 150, x, y);
    auto s = new Scroll(x, y, 280, 150);
    s.box(Boxtype.downBox);
    foreach (r; 0 .. 6)
        foreach (c; 0 .. 4)
        {
            import std.conv : to;
            new Button(x + 5 + c * 90, y + 5 + r * 35, 85, 30, "Button " ~ (r * 4 + c + 1).to!string);
        }
    s.end();

    cell("Flex", "flFlex", 280, 150, x, y);
    auto f = new Flex(x, y, 280, 40, flexHorizontal);
    f.gap(5);
    new Button(0, 0, 0, 0, "Left");
    auto mid = new Button(0, 0, 0, 0, "Fixed 60");
    new Button(0, 0, 0, 0, "Right");
    f.fixed(mid, 60);
    f.end();

    cell("Tile", "flTile", 280, 150, x, y);
    auto tile = new Tile(x, y, 280, 150);
    auto a = new Box(x, y, 120, 150, "Drag the\nborders");
    a.box(Boxtype.downBox);
    auto b = new Box(x + 120, y, 160, 75, "Top right");
    b.box(Boxtype.downBox);
    auto c = new Box(x + 120, y + 75, 160, 75, "Bottom right");
    c.box(Boxtype.downBox);
    tile.end();

    cell("Wizard", "flWizard", 280, 150, x, y);
    auto w = new Wizard(x, y, 280, 150);
    auto w1 = new FlGroup(x, y, 280, 150);
    new Box(x + 10, y + 10, 260, 90, "Page 1 of 3:\none page shows at a time.");
    new Button(x + 190, y + 115, 80, 25, "Next @->");
    w1.end();
    new FlGroup(x, y, 280, 150).end();
    new FlGroup(x, y, 280, 150).end();
    w.end();

    cell("Grid", "flGrid", 280, 150, x, y);
    auto grid = new Grid(x, y, 280, 150);
    grid.layout(3, 3, 5, 5);
    foreach (r; 0 .. 3)
        foreach (col; 0 .. 3)
        {
            if (r == 2 && col > 0) continue;
            import std.conv : to;
            auto bt = new Button(0, 0, 0, 0, r == 2 ? "Spans 3 columns" : (r * 3 + col + 1).to!string);
            if (r == 2) grid.widget(bt, r, col, 1, 3);
            else grid.widget(bt, r, col);
        }
    grid.end();
}

void buttonsPage()
{
    int x, y;
    page("Buttons");
    cell("Button", "flButton", 200, 30, x, y);
    new Button(x, y, 100, 30, "Button");
    cell("Return Button", "flReturnButton", 200, 30, x, y);
    new ReturnButton(x, y, 100, 30, "OK");
    cell("Light Button", "flLightButton", 200, 30, x, y);
    new LightButton(x, y, 100, 30, "Light").value(1);
    cell("Repeat Button", "flRepeatButton", 200, 30, x, y);
    new RepeatButton(x, y, 100, 30, "Repeat");
    cell("Check Button", "flCheckButton", 200, 30, x, y);
    new CheckButton(x, y, 100, 30, "Check").value(1);
    cell("Round Button", "flRoundButton", 200, 30, x, y);
    new RoundButton(x, y, 100, 30, "Round").value(1);
}

void valuatorsPage()
{
    int x, y;
    page("Valuators");
    cell("Slider", "flSlider", 200, 25, x, y);
    auto sl = new Slider(x, y, 200, 25);
    sl.type(horNiceSlider);
    sl.value(0.4);
    cell("Scroll Bar", "flScrollBar", 200, 20, x, y);
    auto sb = new Scrollbar(x, y, 200, 20);
    sb.type(horizontalType);
    sb.value(30, 20, 0, 100);
    cell("Value Slider", "flValueSlider", 200, 25, x, y);
    auto vs = new ValueSlider(x, y, 200, 25);
    vs.type(horNiceSlider);
    vs.value(0.4);
    cell("Value Output", "flValueOutput", 200, 25, x, y);
    new ValueOutput(x, y, 100, 25).value(42);
    cell("Adjuster", "flAdjuster", 200, 25, x, y);
    new Adjuster(x, y, 75, 25);
    cell("Counter", "flCounter", 200, 25, x, y);
    new Counter(x, y, 150, 25).value(12);
    cell("Dial", "flDial", 200, 80, x, y);
    new Dial(x, y, 80, 80).value(0.3);
    cell("Roller", "flRoller", 200, 25, x, y);
    new Roller(x, y, 150, 25).type(horizontalType);
    cell("Spinner", "flSpinner", 200, 25, x, y);
    new Spinner(x, y, 80, 25).value(5);
    cell("Value Input", "flValueInput", 200, 25, x, y);
    new ValueInput(x, y, 100, 25).value(3.14);
}

void textPage()
{
    int x, y;
    page("Text");
    cell("Input", "flInput", 290, 25, x, y);
    new Input(x, y, 290, 25).value("Text to edit");
    cell("Output", "flOutput", 290, 25, x, y);
    new Output(x, y, 290, 25).value("Text to show");
    cell("File Input", "flFileInput", 290, 35, x, y);
    new FileInput(x, y, 290, 35).value("/home/user/projects/hello.d");

    auto editBuf = new TextBuffer();
    editBuf.text("import fl;\n\nvoid main()\n{\n    auto w = new Window(300, 200, \"Hello\");\n    w.show();\n    fl.run();\n}\n");
    cell("Text Edit", "flTextEdit", 450, 190, x, y);
    auto ed = new TextEditor(x, y, 450, 190);
    ed.buffer(editBuf);
    ed.textfont(courier);

    auto showBuf = new TextBuffer();
    showBuf.text("A TextDisplay shows text that is\ntoo long for an Output: many lines,\nwith scroll bars when it doesn't fit.\n\nIt can wrap lines, show line numbers\nand colour parts of the text.\n");
    cell("Text Display", "flTextDisplay", 450, 190, x, y);
    new TextDisplay(x, y, 450, 190).buffer(showBuf);

    cell("Terminal", "flSimpleTerminal", 450, 160, x, y);
    auto term = new Terminal(x, y, 450, 160);
    term.append("$ build/hello\nHello, world!\n$ ");
}

void menusPage()
{
    int x, y;
    page("Menus");
    cell("Input Choice", "flInputChoice", 220, 25, x, y);
    auto ic = new InputChoice(x, y, 150, 25);
    ic.add("Small");
    ic.add("Medium");
    ic.add("Large");
    ic.value("Medium");

    cell("Menu Bar", "flMenubar", 300, 30, x, y);
    auto mb = new MenuBar(x, y, 300, 30);
    mb.add("&File/&Open...", 0, null);
    mb.add("&Edit/&Copy", 0, null);
    mb.add("&View/&Zoom", 0, null);
    mb.add("&Help/&About", 0, null);

    cell("Menu Button", "flMenuButton", 220, 30, x, y);
    auto mbt = new MenuButton(x, y, 120, 30, "Actions");
    mbt.add("Cut", 0, null);
    mbt.add("Copy", 0, null);
    mbt.add("Paste", 0, null);

    cell("Choice", "flChoice", 220, 25, x, y);
    auto ch = new Choice(x, y, 150, 25);
    ch.add("Red", 0, null);
    ch.add("Green", 0, null);
    ch.add("Blue", 0, null);
    ch.value(1);

    // The menu items have no widget of their own: they are the entries
    // of a Menu Bar, Menu Button or Choice. Here, a menu with one of each.
    cell("Menu Item, Checkbox Menu Item, Radio Menu Item, Sub Menu",
        "flMenuitem,flCheckMenuitem,flRadioMenuitem,flSubmenu", 560, 30, x, y);
    auto mi = new MenuButton(x, y, 160, 30, "Open the menu");
    menuItemsButton = mi;
    mi.add("Menu Item", 0, null);
    mi.add("Checkbox Menu Item", 0, null, menuToggle | menuValue);
    mi.add("Radio Menu Item 1", 0, null, menuRadio | menuValue);
    mi.add("Radio Menu Item 2", 0, null, menuRadio);
    mi.add("Sub Menu/Item", 0, null);
}

void browsersPage()
{
    import std.conv : to;
    int x, y;
    page("Browsers");

    cell("Browser", "flBrowser", 280, 160, x, y);
    auto br = new HoldBrowser(x, y, 280, 160);
    foreach (s; ["Apples", "Bananas", "Cherries", "Dates", "Figs", "Grapes", "Kiwis", "Lemons", "Mangoes"])
        br.add(s);
    br.value(3);

    cell("Tree", "flTree", 280, 160, x, y);
    auto tr = new Tree(x, y, 280, 160);
    tr.showroot(false);
    tr.add("Fruit/Apples");
    tr.add("Fruit/Pears");
    tr.add("Vegetables/Carrots");
    tr.add("Vegetables/Leeks");
    tr.close("Vegetables");
    tr.add("Herbs");

    cell("Check Browser", "flCheckBrowser", 280, 160, x, y);
    auto cb = new CheckBrowser(x, y, 280, 160);
    cb.add("Milk", true);
    cb.add("Bread");
    cb.add("Eggs", true);
    cb.add("Butter");

    cell("HTML View", "flHelp", 280, 160, x, y);
    auto hv = new HtmlView(x, y, 280, 160);
    hv.value("<h2>HTML View</h2><p>Shows <b>HTML</b> pages, with "
        ~ "<a href=\"#\">links</a>, lists and tables.</p><ul><li>One</li><li>Two</li></ul>");

    cell("Markdown View", "flMarkdownView", 280, 160, x, y);
    auto mv = new MarkdownView(x, y, 280, 160);
    mv.textsize(12);
    mv.value("## Markdown View\n\nShows **Markdown** documents, such as a "
        ~ "README, with [links](#) and `code`.\n\n- One\n- Two\n\n| A | B |\n|---|---|\n| 1 | 2 |\n");

    cell("File Browser", "flFileBrowser", 280, 160, x, y);
    auto fb = new FileBrowser(x, y, 280, 160);
    fb.loadDirectory(dirName(thisExePath()));

    cell("Table", "flTable", 280, 160, x, y);
    new GalleryTable(x, y, 280, 160);
}

void miscPage()
{
    int x, y;
    page("Misc");
    cell("Box", "flBox", 200, 60, x, y);
    auto b = new Box(x, y, 160, 60, "A label in a box");
    b.box(Boxtype.upBox);
    cell("Clock", "flClock", 200, 120, x, y);
    new FlClock(x, y, 120, 120);
    cell("Progress", "flProgress", 200, 25, x, y);
    auto p = new Progress(x, y, 200, 25, "40%");
    p.minimum(0);
    p.maximum(100);
    p.value(40);
}

// The picture's file name for a cell: the widget's name in lower case,
// with underscores for spaces ("Value Slider" -> value_slider.png).
string shotFile(string name)
{
    import std.algorithm : startsWith;
    import std.string : replace, toLower;
    if (name.startsWith("Menu Item")) return "menu_items.png";
    return name.toLower().replace(" ", "_") ~ ".png";
}

// Draws the area (x, y, w, h) of win, and the given menu windows where
// they are on the screen, with a margin around it, into a PNG file.
// Returns whether the file was written.
bool writeArea(Window win, Window[] menus, int x, int y, int w, int h, string path)
{
    // At most 6, the space between a cell's icon and name and its widget.
    enum margin = 4;
    auto surf = new ImageSurface(w + 2 * margin, h + 2 * margin);
    SurfaceDevice.pushCurrent(surf);
    surf.draw(win, margin - x, margin - y);
    foreach (m; menus)
        surf.draw(m, margin - x + m.x() - win.x(), margin - y + m.y() - win.y());
    auto img = surf.image();
    SurfaceDevice.popCurrent();
    destroy(surf);
    bool ok = img !is null && writePng(path, img) == 0;
    if (ok) writeln(path);
    else stderr.writeln("widget_gallery: can't write ", path);
    return ok;
}

// The area a cell's widgets take: from the cell's top left corner to
// the right and bottom edges of its widgets.
void shotArea(Shot s, out int x, out int y, out int w, out int h)
{
    int r = s.x, b = s.y;
    int last = s.last < 0 ? s.page.children() : s.last;
    foreach (i; s.first .. last)
    {
        auto c = s.page.child(i);
        if (c.x() + c.w() > r) r = c.x() + c.w();
        if (c.y() + c.h() > b) b = c.y() + c.h();
    }
    x = s.x;
    y = s.y;
    w = r - s.x;
    h = b - s.y;
}

// --capture: writes every cell's picture into dir. Returns the number of
// pictures that could not be written.
int captureAll(Window win, Tabs tabs, string dir)
{
    mkdirRecurse(dir);
    // Let the window come up and draw once, so fonts and sizes are settled.
    foreach (i; 0 .. 10) fl.wait(0.05);
    fl.focus(null);

    int failed = 0;
    Shot menuShot;
    foreach (s; shots)
    {
        if (s.file == "menu_items.png") { menuShot = s; continue; }
        tabs.value(s.page);
        int x, y, w, h;
        shotArea(s, x, y, w, h);
        if (!writeArea(win, null, x, y, w, h, buildPath(dir, s.file))) failed++;
    }

    // The menu items: open the Menu Button's menu, and draw it from a
    // timer while it is open; then close it with Escape.
    if (menuShot.page !is null && menuItemsButton !is null)
    {
        tabs.value(menuShot.page);
        bool written;
        fl.addTimeout(0.3, {
            Window[] menus;
            for (auto m = fl.firstWindow(); m !is null; m = fl.nextWindow(m))
                if (cast(MenuWindow) m !is null) menus ~= m;
            int x, y, w, h;
            shotArea(menuShot, x, y, w, h);
            int r = x + w, b = y + h;
            foreach (m; menus)
            {
                int mx = m.x() - win.x(), my = m.y() - win.y();
                if (mx < x) x = mx;
                if (my < y) y = my;
                if (mx + m.w() > r) r = mx + m.w();
                if (my + m.h() > b) b = my + m.h();
            }
            written = writeArea(win, menus, x, y, r - x, b - y,
                buildPath(dir, menuShot.file));
            // While the menu is open, it holds the grab, so the key goes to it.
            fl.eventKeysym(escape);
            if (fl.grab() !is null) fl.handle(Event.keyDown, fl.grab());
        });
        menuItemsButton.popup();
        if (!written) failed++;
    }
    return failed;
}

int main(string[] args)
{
    string captureDir;
    if (args.length >= 3 && args[1] == "--capture")
    {
        captureDir = args[2];
        args = args[0 .. 1] ~ args[3 .. $];
    }

    foreach (dir; [buildPath(dirName(dirName(thisExePath())), "source", "fluid", "pixmaps_svg"),
                   buildPath("source", "fluid", "pixmaps_svg")])
        if (exists(dir)) { iconDir = dir; break; }

    auto win = new DoubleWindow(winW, winH, "Widget gallery");
    auto tabs = new Tabs(10, 10, winW - 20, winH - 20);
    groupsPage();
    group().end();
    buttonsPage();
    group().end();
    valuatorsPage();
    group().end();
    textPage();
    group().end();
    menusPage();
    group().end();
    browsersPage();
    group().end();
    miscPage();
    group().end();
    tabs.end();
    win.end();
    win.show(args);
    if (captureDir.length)
    {
        int failed = captureAll(win, tabs, captureDir);
        win.hide();
        return failed ? 1 : 0;
    }
    fl.run();
    return 0;
}

// The group being filled.
FlGroup group() => FlGroup.current();
