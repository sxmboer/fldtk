// D transliteration of FLTK's test/fltk-versions.cxx (~/Repositories/fltk).
// Part of the samples/ contract -- see samples/README.md.
// Check: ./samples/build.sh fltk-versions
import fl;
import std.stdio : writef, writefln, stdout;
import std.format : format;
version (linux) import platformX11 = fl.platform_x11;

enum int ww = 640, mw = 750; // initial, max. window width
enum int wh = 200, mh = 300; // initial, max. window height

// Function to determine the platform (system and backend).
// Note: the display must have been opened before this is called.
string getPlatform()
{
    version (linux)
    {
        if (platformX11.x11Display())
            return "Unix/Linux (X11)";
        if (platformX11.wlDisplay())
            return "Unix/Linux (Wayland)";
        return "X11 or Wayland (backend unknown or display not opened)";
    }
    else version (Windows)
    {
        return "Windows";
    }
    else
    {
        return "platform unknown, unsupported, or display not opened";
    }
}

// set box attributes and optionally set a background color (debug mode)
void setAttributes(Widget w, Color col)
{
    w.labelfont(courier);
    w.labelsize(16);
    w.alignment(alignCenter | alignInside);
    // debug mode (disabled, matching FLTK's #if (0)):
    // w.box(Boxtype.flatBox);
    // w.color(col);
}

string[9] version_;
Box[9] box_;

void main(string[] args)
{
    int versions = 0;
    version (linux) platformX11.openDisplay();
    string platform = getPlatform();
    writefln("System/platform   = %s", platform);

    string YES = "OK";
    string NO = "FAIL";

    version_[versions++] = format("FL_VERSION        = %6.4f", FL_VERSION);
    version_[versions++] = format("fl.version_()     = %6.4f", fl.version_());
    version_[versions++] = (FL_VERSION == fl.version_()) ? YES : NO;

    version_[versions++] = format("FL_API_VERSION    = %6d", FL_API_VERSION);
    version_[versions++] = format("fl.apiVersion()   = %6d", fl.apiVersion());
    version_[versions++] = (FL_API_VERSION == fl.apiVersion()) ? YES : NO;

    version_[versions++] = format("FL_ABI_VERSION    = %6d", FL_ABI_VERSION);
    version_[versions++] = format("fl.abiVersion()   = %6d", fl.abiVersion());
    version_[versions++] = (FL_ABI_VERSION == fl.abiVersion()) ? YES : NO;

    for (int i = 0; i < versions; i++)
    {
        if (i % 3 == 1)
            writef("%s  ", version_[i]);
        else
            writefln("%s", version_[i]);
    }
    stdout.flush();

    if (FL_ABI_VERSION != fl.abiVersion())
    {
        writefln("*** FLTK ABI version mismatch: headers = %d, lib = %d ***",
            FL_ABI_VERSION, fl.abiVersion());
        stdout.flush();
        message(format("*** FLTK ABI version mismatch: headers = %d, lib = %d ***",
            FL_ABI_VERSION, fl.abiVersion()));
    }

    auto window = new Window(ww, wh);

    auto grid = new Grid(0, 0, ww, wh);
    grid.layout(4, 3, 20, 5);

    auto title = new Box(0, 0, 0, 0, platform);
    setAttributes(title, yellow);
    title.labelfont(helveticaBold);
    grid.widget(title, 0, 0, 1, 3);
    grid.rowHeight(0, 40);
    title.labelsize(20);

    for (int i = 0; i < 3; i += 1)
    {
        box_[3 * i] = new Box(0, 0, 270, 0, version_[3 * i]);
        box_[3 * i + 1] = new Box(0, 0, 270, 0, version_[3 * i + 1]);
        box_[3 * i + 2] = new Box(0, 0, 40, 0, version_[3 * i + 2]);
        grid.widget(box_[3 * i], i + 1, 0);
        grid.widget(box_[3 * i + 1], i + 1, 1);
        grid.widget(box_[3 * i + 2], i + 1, 2);
        grid.rowHeight(i + 1, 30);
    }

    for (int i = 0; i < 9; i++)
        setAttributes(box_[i], green);

    window.end();
    window.resizable(grid);
    window.sizeRange(ww, wh, mw, mh);
    window.show(args);
    fl.run();
}
