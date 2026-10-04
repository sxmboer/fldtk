// D transliteration of FLTK's examples/animgifimage.cxx
// (~/Repositories/fltk).
// Part of the samples/ contract -- see samples/README.md.
// Check: ./samples/build.sh animgifimage
//
//  Test program for displaying animated GIF files using the
//  Fl_Anim_GIF_Image class.
import fl;
import std.stdio : writef, writefln;
import std.string : indexOf;
import std.conv : to, ConvException;
import core.stdc.stdlib : exit;

int gGoodCount = 0, gBadCount = 0, gFrameCount = 0;

// Widget.userData()/argument() has no equivalent in this port (see
// CLAUDE.md's callback convention -- callbacks are D delegates that
// capture their own state directly). This sample uses it purely to
// stash the AnimGifImage pointer alongside the window it's decorating
// so main() can destroy it before the window; a plain AA keyed on the
// window stands in, same fix already established in
// samples/test/symbols.d for the same gap.
AnimGifImage[Window] windowAnim;

immutable Color backGroundColor = gray; // use e.g. Color.red to see
                                               // transparent parts better
enum double redrawDelay = 1. / 20; // interval [sec] for forced redraw

void quitCb(Widget w)
{
    exit(0);
}

void setTitle(Window win, AnimGifImage animgif)
{
    string buf = filenameName(animgif.name()) ~ " (" ~ animgif.frames().to!string
        ~ " frames)  " ~ animgif.speed().to!string ~ "x";
    if (animgif.frameUncache())
        buf ~= " U";
    win.copyLabel(buf);
    win.copyTooltip(buf);
}

void cbForcedRedraw()
{
    Window win = fl.firstWindow();
    while (win !is null)
    {
        if (!win.menuWindow())
            win.redraw();
        win = fl.nextWindow(win);
    }
    if (fl.firstWindow())
        fl.repeatTimeout(redrawDelay, cbForcedRedrawDg);
}

// fl.core's timer functions need a stable delegate identity to match
// against for removeTimeout()/hasTimeout() (D delegate equality
// compares function pointer + context, so a fresh `() { ... }`
// literal at each call site would never compare equal to an earlier
// one) -- one shared delegate wrapping the free function, reused at
// every call site below, instead of a literal per call.
void delegate() cbForcedRedrawDg;
static this()
{
    cbForcedRedrawDg = () { cbForcedRedraw(); };
}

Window openFile(string name, string flags, bool close = false)
{
    // determine test options from 'flags'
    bool uncache = flags.indexOf('u') >= 0;
    int debugLevel = 0;
    foreach (c; flags) if (c == 'd') debugLevel++;
    bool optimizeMem = flags.indexOf('m') >= 0;
    bool desaturate = flags.indexOf('D') >= 0;
    bool average = flags.indexOf('A') >= 0;
    bool testTiles = flags.indexOf('T') >= 0;
    bool testForcedRedraw = flags.indexOf('f') >= 0;
    auto rIdx = flags.indexOf('r');
    bool resizable = rIdx >= 0 && !testTiles;
    double scale = 1.0;
    if (rIdx >= 0 && resizable)
    {
        // FLTK uses atof(), which returns 0.0 for a malformed scale
        // factor instead of throwing -- the very next check below
        // already treats an out-of-range scale (0.0 included) as "use
        // the default" -- so 0.0 is the correct, faithful fallback.
        try
            scale = flags[rIdx + 1 .. $].to!double;
        catch (ConvException)
            scale = 0.0;
    }
    if (scale <= 0.1 || scale > 5)
        scale = resizable ? 0.7 : 1.0;

    // setup window
    fl.removeTimeout(cbForcedRedrawDg);
    auto win = new DoubleWindow(300, 300);
    win.color(backGroundColor);
    if (close)
        win.callback((w) { quitCb(w); });
    writef("Loading '%s'%s%s ... ", name,
            uncache ? " (uncached)" : "",
            optimizeMem ? " (optimized)" : "");

    // create a canvas for the animation
    Box canvas = testTiles ? null : new Box(0, 0, 0, 0); // canvas will be resized by animation
    Box canvas2 = null;
    ushort gifFlags = debugLevel ? AnimGifImage.logFlag : 0;
    if (debugLevel > 1)
        gifFlags |= AnimGifImage.debugFlag;
    if (optimizeMem)
        gifFlags |= AnimGifImage.optimizeMemory;

    // create animation, specifying this canvas as display widget
    auto animgif = new AnimGifImage(name, canvas, gifFlags);
    bool good = animgif.ld() == 0 && animgif.valid();
    writefln("%s: %d x %d (%d frames) %s",
            animgif.name(), animgif.w(), animgif.h(), animgif.frames(), good ? "OK" : "ERROR");
    // for the statistics (when run on testsuite):
    gGoodCount += good;
    gBadCount += !good;
    gFrameCount += animgif.frames();

    windowAnim[win] = animgif; // store address of image (see note in main())

    // exercise the optional tests on the animation
    animgif.frameUncache(uncache);
    if (scale != 1.0)
    {
        animgif.resize(scale);
        writefln("TEST: resized %s by %.2f to %d x %d", animgif.name(), scale, animgif.w(), animgif.h());
    }
    if (average)
    {
        writefln("TEST: color_average %s", animgif.name());
        animgif.colorAverage(green, 0.5); // currently hardcoded
    }
    if (desaturate)
    {
        writefln("TEST: desaturate %s", animgif.name());
        animgif.desaturate();
    }
    int w = animgif.w();
    int h = animgif.h();
    if (animgif.frames())
    {
        if (testTiles)
        {
            // demonstrate a way how to use the animation with Fl_Tiled_Image
            writefln("TEST: use %s as tiles", animgif.name());
            w *= 2;
            h *= 2;
            auto tiledImage = new TiledImage(animgif);
            auto group = new FlGroup(0, 0, win.w(), win.h());
            group.image(tiledImage);
            group.alignment(alignInside);
            animgif.canvas(group, AnimGifImage.dontResizeCanvas | AnimGifImage.dontSetAsImage);
            win.resizable(group);
        }
        else
        {
            // demonstrate a way how to use same animation in another canvas simultaneously:
            // as the current implementation allows only automatic redraw of one canvas..
            if (testForcedRedraw)
            {
                if (w < 400)
                {
                    writefln("TEST: open %s in another animation with application redraw", animgif.name());
                    canvas2 = new Box(w, 0, animgif.w(), animgif.h()); // another canvas for animation
                    canvas2.image(animgif); // is set to same animation!
                    w *= 2;
                    fl.addTimeout(redrawDelay, cbForcedRedrawDg); // force periodic redraw
                }
            }
        }
        // make window resizable (must be done before show())
        if (resizable && canvas && !testTiles)
            win.resizable(win);
        win.size(w, h); // change to actual size of canvas
        // start the animation
        win.end();
        win.show();
        win.waitForExpose();
        setTitle(win, animgif);
        if (resizable && !testTiles)
        {
            // need to reposition the widgets (have been moved by setting resizable())
            if (canvas && canvas2)
            {
                canvas.resize(0, 0, w / 2, canvas.h());
                canvas2.resize(w / 2, 0, w / 2, canvas2.h());
            }
            else if (canvas)
            {
                canvas.resize(0, 0, animgif.canvasW(), animgif.canvasH());
            }
        }
        win.initSizes(); // IMPORTANT: otherwise weird things happen at Ctrl+/- scaling
    }
    else
    {
        destroy(win);
        return null;
    }
    if (debugLevel >= 3)
    {
        // open each frame in a separate window
        for (int i = 0; i < animgif.frames(); i++)
        {
            string buf = "Frame #" ~ (i + 1).to!string;
            auto frameWin = new DoubleWindow(animgif.w(), animgif.h());
            frameWin.copyTooltip(buf);
            frameWin.copyLabel(buf);
            frameWin.color(backGroundColor);
            int fw = animgif.image(i).w();
            int fh = animgif.image(i).h();
            // in 'optimize_mem' mode frames must be offsetted to canvas
            int fx = (fw == animgif.w() && fh == animgif.h()) ? 0 : animgif.frameX(i);
            int fy = (fw == animgif.w() && fh == animgif.h()) ? 0 : animgif.frameY(i);
            auto b = new Box(fx, fy, fw, fh);
            // get the frame image
            b.image(animgif.image(i));
            frameWin.end();
            frameWin.show();
        }
    }
    return win;
}

// fl.filename.filenameList() (Fl::filename_list(), a scandir()+
// comparator-callback wrapper over raw `struct dirent**`) was never
// ported -- see PORTING.md's fl.filename row -- and porting the real
// C-style dirent/comparator API just for this one directory-listing
// test-mode branch isn't worth it. std.file.dirEntries covers the
// same job in idiomatic D.
string[] listDirSorted(string dir)
{
    import std.file : dirEntries, SpanMode;
    import std.path : baseName;
    import std.algorithm.sorting : sort;

    string[] names;
    foreach (e; dirEntries(dir, SpanMode.shallow)) names ~= baseName(e.name);
    sort(names);
    return names;
}

bool openDirectory(string dir, string flags)
{
    string[] list = listDirSorted(dir);
    if (list.length == 0)
        return false;
    int cnt = 0;
    foreach (name; list)
    {
        if (name == "." || name == "..") continue;
        auto p = name.indexOf(".gif");
        if (p < 0) p = name.indexOf(".GIF");
        if (p < 0) continue;
        if (p + 4 != name.length) continue; // is no extension!
        string path = dir ~ "/" ~ name;
        string localFlags = flags;
        if (name.indexOf("debug") >= 0) // hack: when name contains 'debug' open single frames
            localFlags ~= "d";
        if (openFile(path, localFlags, cnt == 0))
            cnt++;
    }
    return cnt != 0;
}

void changeSpeed(double delta)
{
    Widget below = fl.belowmouse();
    if (below && below.image())
    {
        AnimGifImage animgif = null;
        // Q: is there a way to determine Fl_Tiled_Image without using dynamic cast?
        auto tiled = cast(TiledImage) below.image();
        animgif = tiled ? cast(AnimGifImage) tiled.image() : cast(AnimGifImage) below.image();
        if (animgif && animgif.playing())
        {
            double speed = animgif.speed();
            if (!delta) speed = 1.;
            else speed += delta;
            if (speed < 0.1) speed = 0.1;
            if (speed > 10) speed = 10;
            animgif.speed(speed);
            setTitle(below.window(), animgif);
        }
    }
}

int events(Event event)
{
    if (event == Event.shortcut)
    {
        if (fl.eventKey() == '+')
            changeSpeed(0.1);
        else if (fl.eventKey() == '-')
            changeSpeed(-0.1);
        else if (fl.eventKey() == '0')
            changeSpeed(0);
        else
            return 0;
        return 1;
    }
    return 0;
}

immutable string testsuite = "testsuite";

void main(string[] args)
{
    registerImages();
    fl.addHandler((e) { return events(e); });
    string openFlags;
    if (args.length > 1)
    {
        // started with argumemts
        if (args[1].indexOf("-h") >= 0)
        {
            writefln("Usage:\n"
                    ~ "   -t [directory] [-{flags}] open all files in directory (default name: %s) [with options]\n"
                    ~ "   filename [-{flags}] open single file [with options] \n"
                    ~ "   No arguments open a fileselector\n"
                    ~ "   {flags} can be: d=debug mode, u=uncached, D=desaturated, A=color averaged, T=tiled\n"
                    ~ "                   m=minimal update, r[scale factor]=resize by 'scale factor'\n"
                    ~ "   Use keys '+'/'-/0' to change speed of the active image (belowmouse).", testsuite);
            return;
        }
        foreach (a; args[1 .. $])
            if (a.length && a[0] == '-')
                openFlags ~= a[1 .. $];
        if (openFlags.indexOf('t') >= 0)
        {
            // open all GIF-files in a given directory
            string dir = testsuite;
            foreach (a; args[2 .. $])
                if (a.length && a[0] != '-')
                    dir = a;
            openDirectory(dir, openFlags);
            writefln("Summary: good=%d, bad=%d, frames=%d", gGoodCount, gBadCount, gFrameCount);
        }
        else
        {
            // open given file(s)
            foreach (a; args[1 .. $])
                if (a.length && a[0] != '-')
                    openFile(a, openFlags, openFlags.indexOf('d') >= 0);
        }
    }
    else
    {
        // started without arguments: choose file
        GifImage.animate = true; // create animated shared .GIF images (e.g. file chooser)
        while (true)
        {
            fl.addTimeout(0.1, cbForcedRedrawDg); // animate images in chooser
            string filename = fileChooser("Select a GIF image file", "*.{gif,GIF}", null);
            fl.removeTimeout(cbForcedRedrawDg);
            if (!filename.length)
                break;
            Window win = openFile(filename, openFlags);
            fl.run();
            // delete last window (which is now just hidden) to test destructors
            // NOTE: it is essential that *before* doing this also the
            //       animated image is destroyed, otherwise it will crash
            //       because it's canvas will be gone.
            //       In order to keep this demo simple, the adress of the
            //       Fl_Anim_GIF_Image has been stored in the window's user_data.
            //       In a real-life application you will probably store
            //       it somewhere in the window's or canvas' object and destroy
            //       the image in the window's or canvas' destructor.
            if (win && (win in windowAnim))
            {
                destroy(windowAnim[win]);
                windowAnim.remove(win);
            }
            destroy(win);
        }
    }
    fl.run();
}
