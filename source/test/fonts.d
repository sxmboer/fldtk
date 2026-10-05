// D transliteration of FLTK's test/fonts.cxx.
// Build: rdmd buildsamples.d test fonts
//
// Notes on this transliteration:
//  - Fl_Tile/Fl_Hold_Browser (fl.tile.Tile/fl.hold_browser.HoldBrowser)
//    are real, ported fldtk widgets, used directly below.
//  - fl_choice()/Fl_File_Chooser aren't used by the actual code path
//    FLTK compiles (the #ifdef __APPLE__ branch always wins, so the
//    fl_choice() "which fonts" prompt is dead code); skipped here too,
//    matching FLTK's effective behavior rather than its unreachable
//    source text.
//  - fl_utf8encode() is already used the same way in utf8.d.
import fl;
import std.format : format;
import std.conv : parse;

DoubleWindow form;
Tile tile;
Window vectorFontEditor = null;

class FontDisplay : Widget
{
    int font, size;

    this(Boxtype b, int x, int y, int w, int h, string l = null)
    {
        super(x, y, w, h, l);
        box(b);
        font = 0;
        size = 14;
    }

    override void draw()
    {
        drawBox();
        fl_font(cast(Font) font, size);
        fl_color(black);
        fl_draw(label(), x() + 3, y() + 3, w() - 6, h() - 6, alignment());
    }
}

FontDisplay textobj;

HoldBrowser fontobj, sizeobj;

int[][] sizes;
int[] numsizes;
int pickedsize = 14;

void fontCb(Widget)
{
    int fn = fontobj.value();
    if (!fn) return;
    fn--;
    textobj.font = fn;
    sizeobj.clear();
    int n = numsizes[fn];
    int[] s = sizes[fn];
    if (!n)
    {
        // no sizes
    }
    else if (s[0] == 0)
    {
        // many sizes
        int j = 1;
        for (int i = 1; i < 64 || i < s[n - 1]; i++)
        {
            string buf;
            if (j < n && i == s[j]) { buf = format("@b%d", i); j++; }
            else buf = format("%d", i);
            sizeobj.add(buf);
        }
        sizeobj.value(pickedsize);
    }
    else
    {
        // some sizes
        int w = 0;
        for (int i = 0; i < n; i++)
        {
            if (s[i] <= pickedsize) w = i;
            string buf = format("@b%d", s[i]);
            sizeobj.add(buf);
        }
        sizeobj.value(w + 1);
    }
    textobj.redraw();
}

void sizeCb(Widget)
{
    int i = sizeobj.value();
    if (!i) return;
    const(char)[] c = sizeobj.text(i);
    size_t ci = 0;
    while (ci < c.length && (c[ci] < '0' || c[ci] > '9')) ci++;
    auto digits = c[ci .. $];
    pickedsize = digits.length ? parse!int(digits) : 0;
    textobj.size = pickedsize;
    textobj.redraw();
}

char[0x1000] label;

ubyte currentChar = 'A';
ubyte[128][255] vec = [[0]];

void createTheForms()
{
    // create the sample string
    int i = 0;
    string hello = "Hello, world!\n";
    label[0 .. hello.length] = hello;
    i = cast(int) hello.length;
    uint c;
    for (c = ' ' + 1; c < 127; c++)
    {
        if (!(c & 0x1f)) label[i++] = '\n';
        if (c == '@') label[i++] = '@';
        label[i++] = cast(char) c;
    }
    label[i++] = '\n';
    int n = 0;
    for (c = 0xA1; c < 0x600; c += 9)
    {
        if (!(++n & 0x1f)) label[i++] = '\n';
        i += utf8Encode(c, label[i .. $]);
    }
    label[i] = 0;

    // create the basic layout
    form = new DoubleWindow(550, 370);

    tile = new Tile(0, 0, 550, 370);

    auto textgroup = new FlGroup(0, 0, 550, 185);
    textgroup.box(Boxtype.flatBox);
    textobj = new FontDisplay(Boxtype.engravedBox, 10, 10, 530, 170, label[0 .. i].idup);
    textobj.alignment(alignTop | alignLeft | alignInside | alignClip);
    textobj.color(cast(Color) 9, cast(Color) 47);
    textgroup.resizable(textobj);
    textgroup.end();

    auto fontgroup = new FlGroup(0, 185, 550, 185);
    fontgroup.box(Boxtype.flatBox);
    fontobj = new HoldBrowser(10, 190, 390, 170);
    fontobj.box(Boxtype.engravedBox);
    fontobj.color(cast(Color) 53, cast(Color) 3);
    fontobj.callback((w) { fontCb(w); });
    sizeobj = new HoldBrowser(410, 190, 130, 170);
    sizeobj.box(Boxtype.engravedBox);
    sizeobj.color(cast(Color) 53, cast(Color) 3);
    sizeobj.callback((w) { sizeCb(w); });
    fontgroup.resizable(fontobj);
    fontgroup.end();

    tile.end();

    form.resizable(tile);
    form.end();
}

void main(string[] args)
{
    scheme(null);
    fl.argsToUtf8(args); // for MSYS2/MinGW
    fl.args(args);
    fl.getSystemColors();
    createTheForms();

    // For the Unicode test, get all fonts...
    int i = 0;
    int k = fl.setFonts(i ? (i > 1 ? "*" : null) : "-*");
    sizes = new int[][k];
    numsizes = new int[k];
    for (i = 0; i < k; i++)
    {
        int t;
        string name = fl.getFontName(cast(Font) i, t);
        string buffer;
        if (t)
        {
            if (t & bold) buffer ~= "@b";
            if (t & italic) buffer ~= "@i";
            buffer ~= "@."; // Suppress subsequent formatting -- some MS fonts have '@' in their name
            buffer ~= name;
            name = buffer;
        }
        fontobj.add(name);
        int[] s;
        int n = fl.getFontSizes(cast(Font) i, s);
        numsizes[i] = n;
        if (n)
        {
            sizes[i] = s.dup;
        }
    }
    fontobj.value(1);
    fontCb(fontobj);
    form.show(args);
    fl.run();
}
