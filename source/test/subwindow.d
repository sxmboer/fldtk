// D transliteration of FLTK's test/subwindow.cxx (~/Repositories/fltk).
// Part of the samples/ contract -- see samples/README.md.
// Check: ./samples/build.sh subwindow
//
// FLTK guards a positioning test with #ifdef DEBUG / DEBUG_POS (both
// undefined by default) -- neither is transliterated since they're dead
// code in the shipped program.
import fl;

class EnterExit : Box
{
    this(int x, int y, int w, int h, string l)
    {
        super(Boxtype.borderBox, x, y, w, h, l);
    }

    override int handle(Event event)
    {
        if (event == Event.enter) { color(red); redraw(); return 1; }
        else if (event == Event.leave) { color(gray); redraw(); return 1; }
        else return 0;
    }
}

class TestWindow : Window
{
    int cx, cy;
    char key;
    Cursor crsr;

    // FLTK: testwindow(Fl_Boxtype b,int x,int y,const char *l)
    //   : Fl_Window(x,y,l), crsr(FL_CURSOR_DEFAULT)
    // Fl_Window(x,y,l) is FLTK's auto-positioned (w,h,label) ctor --
    // fldtk's Window has the same real (w, h, label) constructor.
    this(Boxtype b, int x, int y, string l)
    {
        super(x, y, l);
        crsr = Cursor.default_;
        box(b);
        key = 0;
    }

    // FLTK: testwindow(Fl_Boxtype b,int x,int y,int w,int h,const char *l)
    //   : Fl_Window(x,y,w,h,l)
    this(Boxtype b, int x, int y, int w, int h, string l)
    {
        super(x, y, w, h, l);
        box(b);
        key = 0;
    }

    void useCursor(Cursor c) { crsr = c; }

    override void draw()
    {
        super.draw();
    }

    override int handle(Event event)
    {
        if (crsr != Cursor.default_)
        {
            if (event == Event.enter)
                cursor(crsr);
            if (event == Event.leave)
                cursor(Cursor.default_);
        }
        if (super.handle(event)) return 1;
        if (event == Event.focus) return 1;
        if (event == Event.push) { fl.focus(this); return 1; }
        if (event == Event.keyDown && fl.eventText().length > 0)
        {
            if (fl.eventKey() == escape || fl.eventCommand()) return 0;
            key = fl.eventText()[0];
            cx = fl.eventX();
            cy = fl.eventY();
            redraw();
            return 1;
        }
        return 0;
    }
}

MenuButton popup;

immutable string bigmess = "this|is|only|a test";

// FLTK's Fl_Menu_::add(const char*) '|'-separated multi-item form is
// the Forms-compatible shim CLAUDE.md marks out of scope; split locally
// and add each item via the real 4-arg add() instead.
void addPipeItems(Menu_ m, string items)
{
    import std.string : split;

    foreach (item; items.split('|'))
        m.add(item, 0, null);
}

void main()
{
    auto window = new TestWindow(Boxtype.upBox, 400, 400, "outer");
    new ToggleButton(310, 310, 80, 80, "&outer");
    new EnterExit(10, 310, 80, 80, "enterexit");
    new Input(160, 310, 140, 25, "input1:");
    new Input(160, 340, 140, 25, "input2:");
    addPipeItems(new MenuButton(5, 150, 80, 25, "menu&1"), bigmess);
    auto subwindow = new TestWindow(Boxtype.downBox, 100, 100, 200, 200, "inner");
    new ToggleButton(110, 110, 80, 80, "&inner");
    new EnterExit(10, 110, 80, 80, "enterexit");
    addPipeItems(new MenuButton(50, 20, 80, 25, "menu&2"), bigmess);
    new Input(55, 50, 140, 25, "input1:");
    new Input(55, 80, 140, 25, "input2:");
    subwindow.resizable(subwindow);
    window.resizable(subwindow);
    subwindow.end();
    subwindow.useCursor(Cursor.hand);
    (new Box(Boxtype.noBox, 0, 0, 400, 100,
        "A child Window with children of its own may "
        ~ "be useful for imbedding controls into a GL or display "
        ~ "that needs a different visual.  There are bugs with the "
        ~ "origins being different between drawing and events, "
        ~ "which I hope I have solved."
        )).alignment(alignWrap);
    popup = new MenuButton(0, 0, 400, 400);
    popup.type(MenuButton.PopupButtons.popup3);
    addPipeItems(popup, "This|is|a popup|menu");
    addPipeItems(popup, bigmess);
    window.show();
    fl.run();
}
