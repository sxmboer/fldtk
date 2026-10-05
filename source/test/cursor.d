// D transliteration of FLTK's test/cursor.cxx.
// Build: rdmd buildsamples.d test cursor
import fl;

// fluid/pixmaps/compressed.xpm, transcribed verbatim from the FLTK file.
immutable string[] compressedXpm = [
    "32 32 6 1",
    "- c #000",
    "= c #444",
    "c c none",
    "d c #cccccc",
    ". c #888",
    ", c #888",
    "cccccccccccccccccccccccccccccccc",
    "cccccccccccccccccccccccccccccccc",
    "ccccccc==================ccccccc",
    "cccccccc================cccccccc",
    "ccccccccc==============ccccccccc",
    "cccccccccc============cccccccccc",
    "ccccccccccc==========ccccccccccc",
    "cccccccccccc========cccccccccccc",
    "ccccccccccccc======ccccccccccccc",
    "cccccccccccccc====cccccccccccccc",
    "cc==.cccccccccc==ccccccccccc==cc",
    "cc.====..cccccccccccccc..====.cc",
    "cccc.======================.cccc",
    "cccccccc..============..cccccccc",
    "cccccccccccccccccccccccccccccccc",
    "cccccccccccccccccccccccccccccccc",
    "cccccccc..============..cccccccc",
    "cccc.======================.cccc",
    "cc.====..cccccccccccccc..====.cc",
    "cc==.cccccccccc==ccccccccccc==cc",
    "cccccccccccccc====cccccccccccccc",
    "ccccccccccccc======ccccccccccccc",
    "cccccccccccc========cccccccccccc",
    "ccccccccccc==========ccccccccccc",
    "cccccccccc============cccccccccc",
    "ccccccccc==============ccccccccc",
    "cccccccc================cccccccc",
    "ccccccc==================ccccccc",
    "cccccccccccccccccccccccccccccccc",
    "cccccccccccccccccccccccccccccccc",
    "cccccccccccccccccccccccccccccccc",
    "cccccccccccccccccccccccccccccccc",
];

Cursor cursor = Cursor.default_;

HorValueSlider cursorSlider;

void choiceCb(Widget w, Cursor v)
{
    cursor = v;
    cursorSlider.value(cursor);
    w.topWindow().cursor(cursor);
}

void customCb(Widget widget)
{
    auto pxm = new Pixmap(compressedXpm);
    auto rgb = new RGBImage(pxm);
    rgb.scale(16, 16);
    widget.topWindow().cursor(rgb, rgb.w() / 2, rgb.h() / 2);
}

// Labels are the D-side `Cursor` enum spelling, not FLTK's C `FL_
// CURSOR_*` macro names -- a deliberate deviation from this port's usual
// faithful-transliteration default: this sample exists to teach a D
// programmer which `fldtk` symbol to reach for, not to document what
// the original C++ constant was called. Applies to any other sample
// whose menu/label text exists purely to name an enum value for the
// viewer (see `browser.d`'s/`chart_simple.d`'s own `FL_*`-labeled
// menus).
MenuItem[] choices = [
    MenuItem("Cursor.default_", (w) { choiceCb(w, Cursor.default_); }),
    MenuItem("Cursor.arrow", (w) { choiceCb(w, Cursor.arrow); }),
    MenuItem("Cursor.cross", (w) { choiceCb(w, Cursor.cross); }),
    MenuItem("Cursor.wait", (w) { choiceCb(w, Cursor.wait); }),
    MenuItem("Cursor.insert", (w) { choiceCb(w, Cursor.insert); }),
    MenuItem("Cursor.hand", (w) { choiceCb(w, Cursor.hand); }),
    MenuItem("Cursor.help", (w) { choiceCb(w, Cursor.help); }),
    MenuItem("Cursor.move", (w) { choiceCb(w, Cursor.move); }),
    MenuItem("Cursor.ns", (w) { choiceCb(w, Cursor.ns); }),
    MenuItem("Cursor.we", (w) { choiceCb(w, Cursor.we); }),
    MenuItem("Cursor.nwse", (w) { choiceCb(w, Cursor.nwse); }),
    MenuItem("Cursor.nesw", (w) { choiceCb(w, Cursor.nesw); }),
    MenuItem("Cursor.n", (w) { choiceCb(w, Cursor.n); }),
    MenuItem("Cursor.ne", (w) { choiceCb(w, Cursor.ne); }),
    MenuItem("Cursor.e", (w) { choiceCb(w, Cursor.e); }),
    MenuItem("Cursor.se", (w) { choiceCb(w, Cursor.se); }),
    MenuItem("Cursor.s", (w) { choiceCb(w, Cursor.s); }),
    MenuItem("Cursor.sw", (w) { choiceCb(w, Cursor.sw); }),
    MenuItem("Cursor.w", (w) { choiceCb(w, Cursor.w); }),
    MenuItem("Cursor.nw", (w) { choiceCb(w, Cursor.nw); }),
    MenuItem("Cursor.none", (w) { choiceCb(w, Cursor.none); }),
    MenuItem("custom cursor", (w) { customCb(w); }),
    MenuItem.init, // trailing null-text sentinel -- fl.menu_popup's
                   // item-array walk is pointer-arithmetic-based (looks
                   // for MenuItem.text is null to know where the array
                   // ends), so an array without this reads past its own
                   // end into whatever memory follows -- see
                   // PORTING.md's FL/Fl_Menu_Item.H row.
];

void setcursor(Widget o)
{
    auto slider = cast(HorValueSlider) o;
    cursor = cast(Cursor) cast(int) slider.value();
    o.topWindow().cursor(cursor);
}

// draw the label without any ^C or \nnn conversions:
class CharBox : Box
{
    this(int x, int y, int w, int h, string l) { super(x, y, w, h, l); }

    override void draw()
    {
        fl_font(freeFont, 14);
        fl_draw(label(), x() + w() / 2, y() + h() / 2);
    }
}

void main(string[] args)
{
    auto window = new DoubleWindow(400, 300);

    auto choice = new Choice(80, 100, 200, 25, "Cursor:");
    choice.menu(choices);
    choice.callback((w) {});
    choice.when(whenRelease | whenNotChanged);

    auto slider1 = new HorValueSlider(80, 180, 310, 30, "Cursor:");
    cursorSlider = slider1;
    slider1.alignment(alignLeft);
    slider1.step(1);
    slider1.precision(0);
    slider1.bounds(0, 255);
    slider1.value(0);
    slider1.callback((w) { setcursor(w); });
    slider1.value(cursor);

    window.resizable(window);
    window.end();
    window.show(args);
    fl.run();
}
