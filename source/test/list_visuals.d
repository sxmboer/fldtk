// D transliteration of FLTK's test/list_visuals.cxx (~/Repositories/fltk).
// Part of the samples/ contract -- see samples/README.md.
// Check: ./samples/build.sh list_visuals
//
// List all the visuals on the screen, and dumps anything interesting
// about them to stdout. Does not use FLTK widgets at all -- it's raw
// Xlib enumeration -- so this transliteration talks to fl.xlib directly
// (aliased to avoid the `Window` name collision with fl.window's
// `Window` class documented in source/fl/package.d) rather than any
// FLTK widget surface.
import fl;
import xlib = fl.xlib;
import std.stdio : writef, writefln, stderr;
import std.string : toStringz, fromStringz;
import std.conv : to;
import core.stdc.stdlib : exit;
import core.stdc.config : c_ulong;

xlib.Display* flDisplay;
int flScreen;
string dname;

void flOpenDisplay()
{
    flDisplay = xlib.XOpenDisplay(dname is null ? null : dname.toStringz());
    if (!flDisplay)
    {
        stderr.writefln("Can't open display: %s",
            fromStringz(xlib.XDisplayName(dname.toStringz())));
        exit(1);
    }
    flScreen = xlib.XDefaultScreen(flDisplay);
}

string[6] classNames = [
    "StaticGray ",
    "GrayScale  ",
    "StaticColor",
    "PseudoColor",
    "TrueColor  ",
    "DirectColor",
];

// SERVER_OVERLAY_VISUALS property element:
struct OverlayInfo
{
    long overlayVisual;
    long transparentType;
    long value;
    long layer;
}

void printMask(xlib.XVisualInfo* p)
{
    int n = 0;
    int what = 0;
    int printAnything = 0;
    char[20] buf;
    size_t q = 0;
    int b;
    uint m;
    for (b = 32, m = 0x80000000; ; b--, m >>= 1)
    {
        int newWhat;
        if (p.redMask & m)
            newWhat = 'r';
        else if (p.greenMask & m)
            newWhat = 'g';
        else if (p.blueMask & m)
            newWhat = 'b';
        else
            newWhat = '?';
        if (newWhat != what)
        {
            if (what && (what != '?' || printAnything))
            {
                auto piece = to!string(n) ~ cast(char) what;
                buf[q .. q + piece.length] = piece[];
                q += piece.length;
                printAnything = 1;
            }
            what = newWhat;
            n = 1;
        }
        else
        {
            n++;
        }
        if (!b)
            break;
    }
    writef("%7s", buf[0 .. q]);
}

void listVisuals()
{
    flOpenDisplay();
    xlib.XVisualInfo vTemplate;
    int num;
    xlib.XVisualInfo* visualList = xlib.XGetVisualInfo(flDisplay, 0, &vTemplate, &num);

    int numpfv;
    xlib.XPixmapFormatValues* pfvlist = xlib.XListPixmapFormats(flDisplay, &numpfv);

    OverlayInfo* overlayInfo = null;
    int numoverlayinfo = 0;
    xlib.Atom overlayVisualsAtom = xlib.XInternAtom(flDisplay,
            "SERVER_OVERLAY_VISUALS".toStringz(), true);
    if (overlayVisualsAtom)
    {
        c_ulong sizeData, bytesLeft;
        xlib.Atom actualType;
        int actualFormat;
        if (!xlib.XGetWindowProperty(flDisplay, xlib.XRootWindow(flDisplay, flScreen),
                overlayVisualsAtom, 0, 10000, false, overlayVisualsAtom,
                &actualType, &actualFormat, &sizeData, &bytesLeft,
                cast(void**)&overlayInfo))
            numoverlayinfo = cast(int)(sizeData / 4);
    }

    for (int i = 0; i < num; i++)
    {
        xlib.XVisualInfo* p = visualList + i;

        xlib.XPixmapFormatValues* pfv;
        for (pfv = pfvlist;; pfv++)
        {
            if (pfv >= pfvlist + numpfv)
            {
                pfv = null;
                break;
            } // should not happen!
            if (pfv.depth == p.depth)
                break;
        }

        int j = pfv ? pfv.bitsPerPixel : 0;
        writef(" %2d: %s %2d/%d", p.visualid, classNames[p.c_class], p.depth, j);
        if (j < 10)
            writef(" ");

        printMask(p);

        for (j = 0; j < numoverlayinfo; j++)
        {
            OverlayInfo* o = &overlayInfo[j];
            if (o.overlayVisual == cast(long) p.visualid)
            {
                writef(" overlay(");
                if (o.transparentType == 1)
                    writef("transparent pixel %d, ", o.value);
                else if (o.transparentType == 2)
                    writef("transparent mask %d, ", o.value);
                else
                    writef("opaque, ");
                writef("layer %d)", o.layer);
            }
        }

        if (p.visualid == xlib.XVisualIDFromVisual(xlib.XDefaultVisual(flDisplay, flScreen)))
            writef(" (default visual)");

        writef("\n");
    }
    if (overlayInfo)
    {
        xlib.XFree(overlayInfo);
        overlayInfo = null;
    }
}

void main(string[] args)
{
    if (args.length == 1)
    {
    }
    else if (args.length == 2 && args[1][0] != '-')
        dname = args[1];
    else
    {
        stderr.writefln("usage: %s <display>", args.length ? args[0] : "list_visuals");
        return;
    }
    listVisuals();
}
