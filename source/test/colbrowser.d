// D transliteration of FLTK's test/colbrowser.cxx.
// Build: rdmd buildsamples.d test colbrowser
import fl;
import std.format : format;
import std.stdio : File;

// some constants

enum MAX_RGB = 3000;

enum Color freeCol4 = cast(Color)(freeColor + 3);
enum Color indianRed = cast(Color) 164;

DoubleWindow cl;
Box rescol;
Button dbobj;
HoldBrowser colbr;
ValueSlider rs, gs, bs;

string dbname;

void createFormCl();
bool loadBrowser(string);

struct RGBdb { int r, g, b; }

RGBdb[MAX_RGB] rgbdb;

void main()
{
    // FLTK parses argc/argv here (Fl::args_to_utf8/Fl::args) to pick an
    // optional database filename, falling back to "rgb.txt"; dropped along
    // with argc/argv (see source/test/README.md and test/button.cxx's precedent).
    dbname = "rgb.txt";

    createFormCl();

    if (loadBrowser(dbname))
        dbobj.label(dbname);
    else
        dbobj.label("None");
    dbobj.redraw();

    cl.sizeRange(cl.w(), cl.h(), 2 * cl.w(), 2 * cl.h());

    cl.label("RGB Browser");
    cl.freePosition();
    cl.show();

    fl.run();
}

void setEntry(int i)
{
    RGBdb* db = &rgbdb[i];
    fl.setColor(freeCol4, cast(ubyte) db.r, cast(ubyte) db.g, cast(ubyte) db.b);
    rs.value(db.r);
    gs.value(db.g);
    bs.value(db.b);
    rescol.redraw();
}

void brCb(Widget ob)
{
    int r = (cast(Browser) ob).value();
    if (r <= 0) return;
    setEntry(r - 1);
}

// Parses one "R G B name" line, matching FLTK's sscanf(buf, " %d %d %d
// %n", ...) exactly: optional leading whitespace, then digits.
private bool parseInt(string line, ref size_t pos, out int val)
{
    import std.ascii : isDigit, isWhite;

    while (pos < line.length && isWhite(line[pos])) pos++;
    bool neg;
    if (pos < line.length && (line[pos] == '-' || line[pos] == '+'))
    {
        neg = line[pos] == '-';
        pos++;
    }
    size_t digitsStart = pos;
    int result;
    while (pos < line.length && isDigit(line[pos]))
    {
        result = result * 10 + (line[pos] - '0');
        pos++;
    }
    if (pos == digitsStart) return false;
    val = neg ? -result : result;
    return true;
}

// Ported from FLTK's read_entry(): reads one line, optionally skipping
// a single leading "!"-comment line (rgb.txt's own header), parses "R G B
// name", and squeezes spaces/newline out of the trailing name text. Like
// FLTK, a line with no trailing '\n' (i.e. real end-of-file reached
// while reading it) is treated as unusable and discarded -- matches
// FLTK's own feof()/ferror() check on the fgets() call that produced
// it, faithfully replicated rather than "fixed", since a real rgb.txt ends
// in a newline and never hits this edge in practice.
bool readEntry(ref File fp, out int r, out int g, out int b, out string name)
{
    string line = fp.readln();
    if (line.length == 0) return false;

    if (line[0] == '!')
        line = fp.readln(); // ignore any read failure, matches FLTK's "ignore" comment

    size_t pos = 0;
    if (!parseInt(line, pos, r)) return false;
    if (!parseInt(line, pos, g)) return false;
    if (!parseInt(line, pos, b)) return false;

    while (pos < line.length && (line[pos] == ' ' || line[pos] == '\t')) pos++;

    char[] nameBuf;
    foreach (c; line[pos .. $])
        if (c != ' ' && c != '\n' && c != '\r') nameBuf ~= c;
    name = nameBuf.idup;

    bool hitEof = line.length == 0 || line[$ - 1] != '\n';
    return !hitEof;
}

bool loadBrowser(string fname)
{
    File fp;
    try { fp = File(fname, "r"); }
    catch (Exception)
    {
        alert(format("Load:\nCan't open '%s'", fname));
        return false;
    }

    int idx = 0;
    int lr = -1, lg = -1, lb = -1;
    int r, g, b;
    string name;
    while (idx < MAX_RGB && readEntry(fp, r, g, b, name))
    {
        rgbdb[idx].r = r;
        rgbdb[idx].g = g;
        rgbdb[idx].b = b;

        // unique the entries on the fly
        if (lr != r || lg != g || lb != b)
        {
            idx++;
            lr = r; lg = g; lb = b;
            colbr.add(format("(%3d %3d %3d) %s", r, g, b, name));
        }
    }
    fp.close();

    if (idx < MAX_RGB)
        rgbdb[idx].r = 1000; // sentinel
    else
        rgbdb[idx - 1].r = 1000;

    colbr.topline(1);
    colbr.select(1, true);
    setEntry(0);

    return true;
}

int searchEntry(int r, int g, int b)
{
    int i = 0, j = 0;
    uint mindiff = uint.max;
    // Bounds-checked in addition to FLTK's own bare `while
    // (rgbdb[i].r<256) i++;` sentinel scan: if loadBrowser() never
    // found the database (e.g. running the built binary from a
    // directory that doesn't have "rgb.txt" next to it -- the
    // sentinel `rgbdb[idx].r = 1000` only ever gets written on a
    // successful load), rgbdb stays all-zeroes and the sentinel-only
    // loop would walk straight off the end of a fixed-size D array
    // (RangeError/segfault) -- dragging the R/G/B sliders with no
    // database loaded is what reaches this path.
    while (i < MAX_RGB && rgbdb[i].r < 256)
    {
        int diffr = r - rgbdb[i].r;
        int diffg = g - rgbdb[i].g;
        int diffb = b - rgbdb[i].b;

        uint diff = cast(uint)(3.0 * (diffr * diffr) + 5.9 * (diffg * diffg) + 1.1 * (diffb * diffb));

        if (mindiff > diff)
        {
            mindiff = diff;
            j = i;
        }
        i++;
    }
    return j;
}

void searchRgb(Widget)
{
    int top = colbr.topline();

    int r = cast(int) rs.value();
    int g = cast(int) gs.value();
    int b = cast(int) bs.value();

    fl.setColor(freeCol4, cast(ubyte) r, cast(ubyte) g, cast(ubyte) b);
    rescol.redraw();
    int i = searchEntry(r, g, b);
    // change topline only if necessary
    if (i < top || i > (top + 15))
        colbr.topline(i - 8);
    colbr.select(i + 1, true);
}

// change database
void dbCb(Widget ob)
{
    string p = fl_input("Enter New Database Name", dbname);
    if (p is null || p == dbname) return;

    if (loadBrowser(p))
        dbname = p;
    else
        ob.label(dbname);
}

void doneCb(Widget)
{
    fl.hideAllWindows();
}

void createFormCl()
{
    if (cl !is null) return;

    cl = new DoubleWindow(400, 385);
    cl.box(Boxtype.upBox);
    cl.color(indianRed, backgroundColor); // FL_GRAY is backgroundColor

    auto title = new Box(40, 10, 300, 30, "Color Browser");
    title.box(Boxtype.noBox);
    title.labelcolor(red);
    title.labelsize(32);
    title.labelfont(helveticaBold);
    title.labeltype(Labeltype.shadowLabel);

    dbobj = new Button(40, 50, 300, 25, "");
    dbobj.type(normalButton);
    dbobj.box(Boxtype.borderBox);
    dbobj.color(indianRed, indianRed);
    dbobj.callback((w) { dbCb(w); });

    colbr = new HoldBrowser(10, 90, 280, 240, "");
    colbr.textfont(courier);
    colbr.callback((w) { brCb(w); });
    colbr.box(Boxtype.downBox);

    rescol = new Box(300, 90, 90, 35, "");
    rescol.color(freeCol4, freeCol4);
    rescol.box(Boxtype.borderBox);

    rs = new ValueSlider(300, 130, 30, 200, "");
    rs.type(vertFillSlider);
    rs.color(indianRed, red);
    rs.bounds(0, 255);
    rs.precision(0);
    rs.callback((w) { searchRgb(w); });
    rs.when(whenRelease);

    gs = new ValueSlider(330, 130, 30, 200, "");
    gs.type(vertFillSlider);
    gs.color(indianRed, green);
    gs.bounds(0, 255);
    gs.precision(0);
    gs.callback((w) { searchRgb(w); });
    gs.when(whenRelease);

    bs = new ValueSlider(360, 130, 30, 200, "");
    bs.type(vertFillSlider);
    bs.color(indianRed, blue);
    bs.bounds(0, 255);
    bs.precision(0);
    bs.callback((w) { searchRgb(w); });
    bs.when(whenRelease);

    auto done = new Button(160, 345, 80, 30, "Done");
    done.type(normalButton);
    done.callback((w) { doneCb(w); });

    cl.end();
    cl.resizable(cl);
}
