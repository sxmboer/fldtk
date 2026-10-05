// D transliteration of FLTK's examples/animgifimage-resize.cxx.
// Build: rdmd buildsamples.d examples animgifimage_resize
//
//  Test program for Fl_Anim_GIF_Image::copy().
import fl;
import std.stdio : writefln, stderr;

AnimGifImage orig;
bool drawGrid = true;

int events(Event event)
{
    if (event == Event.shortcut && fl.firstWindow())
    {
        if (fl.eventKey() == 'g')
        {
            drawGrid = !drawGrid;
            writefln("grid: %s", (drawGrid ? "ON" : "OFF"));
        }
        else if (fl.eventKey() == 'b')
        {
            if (Image.rgbScaling() != Image.RGBScaling.bilinear)
                Image.rgbScaling(Image.RGBScaling.bilinear);
            else
                Image.rgbScaling(Image.RGBScaling.nearest);
            writefln("bilenear: %s", (Image.rgbScaling() != Image.RGBScaling.bilinear ? "OFF" : "ON"));
        }
        else
            return 0;
        fl.firstWindow().redraw();
    }
    return 1;
}

class Canvas : Box
{
    this(int x, int y, int w, int h)
    {
        super(x, y, w, h);
    }

    override void draw()
    {
        if (drawGrid)
        {
            // draw a transparency grid as background
            static immutable Color c1 = rgbColor(0xcc, 0xcc, 0xcc);
            static immutable Color c2 = rgbColor(0x88, 0x88, 0x88);
            enum sz = 8;
            for (int y = 0; y < h(); y += sz)
            {
                for (int x = 0; x < w(); x += sz)
                {
                    fl_color(x % (sz * 2) ? (y % (sz * 2) ? c1 : c2) : (y % (sz * 2) ? c2 : c1));
                    fl_rectf(x, y, 32, 32);
                }
            }
        }
        // draw the current image frame over the grid
        super.draw();
    }

    void doResize(int w, int h)
    {
        if (image() && (image().w() != w || image().h() != h))
        {
            auto animgif = cast(AnimGifImage) image();
            animgif.stop();
            image(null);
            // delete already copied images
            if (animgif !is orig)
                destroy(animgif);
            auto copied = cast(AnimGifImage) orig.copy(w, h);
            if (!copied.valid()) // check success of copy
                writefln("AnimGifImage.copy() %d x %d failed", w, h); // fl.warning() has no equivalent here
            else
                writefln("resized to %d x %d", copied.w(), copied.h());
            copied.canvas(this, AnimGifImage.dontResizeCanvas);
        }
        window().cursor(Cursor.default_);
    }

    private void doResizeCb()
    {
        doResize(w(), h());
    }

    override void resize(int x, int y, int w, int h)
    {
        super.resize(x, y, w, h);
        // decouple resize event from actual resize operation
        // to avoid lockups.. (a bound-method delegate, &doResizeCb,
        // has a stable identity per instance -- unlike a fresh
        // `() { ... }` closure literal per call, which removeTimeout()
        // could never match against a previously-added one)
        fl.removeTimeout(&doResizeCb);
        fl.addTimeout(0.1, &doResizeCb);
        window().cursor(Cursor.wait);
    }
}

void main(string[] args)
{
    // setup play parameters from args
    string fileName;
    bool bilinear = false;
    bool optimize = false;
    bool uncache = false;
    bool debugMode = false;
    for (size_t i = 1; i < args.length; i++)
    {
        if (args[i] == "-b") // turn bilinear scaling on
            bilinear = true;
        else if (args[i] == "-o") // turn optimize on
            optimize = true;
        else if (args[i] == "-g") // disable grid
            drawGrid = false;
        else if (args[i] == "-u") // uncache
            uncache = true;
        else if (args[i] == "-d") // debug
            debugMode = true;
        else if (args[i][0] != '-' && !fileName.length)
            fileName = args[i];
        else if (args[i][0] == '-')
        {
            writefln("Invalid argument: '%s'", args[i]);
            return;
        }
    }
    if (!fileName.length)
    {
        stderr.writefln("Test program for animated copy.");
        stderr.writefln("Usage: %s fileName [-b]ilinear [-o]ptimize [-g]rid [-u]ncache", args[0]);
        return;
    }
    AnimGifImage.minDelay = 0.1; // set a minumum delay for playback

    auto win = new DoubleWindow(640, 480);

    // prepare a canvas for the animation
    // (we want to show it in the center of the window)
    auto canvas = new Canvas(0, 0, win.w(), win.h());
    win.resizable(win);
    win.sizeRange(1, 1);

    win.end();
    win.show();

    // create/load the animated gif and start it immediately.
    // We use the 'DONT_RESIZE_CANVAS' flag here to tell the
    // animation not to change the canvas size (which is the default).
    auto flags = AnimGifImage.dontResizeCanvas;
    if (optimize)
    {
        flags |= AnimGifImage.optimizeMemory;
        writefln("Using memory optimization (if image supports)");
    }
    if (debugMode)
        flags |= AnimGifImage.debugFlag;
    orig = new AnimGifImage(/*name=*/ fileName, /*canvas=*/ canvas, /*flags=*/ flags);

    // check if loading succeeded
    writefln("%s: valid: %d frames: %d uncache: %d",
            orig.name(), orig.valid(), orig.frames(), orig.frameUncache());
    if (orig.valid())
    {
        win.copyLabel(fileName);

        // print information about image optimization
        int n = 0;
        for (int i = 0; i < orig.frames(); i++)
            if (orig.frameX(i) != 0 || orig.frameY(i) != 0) n++;
        writefln("image has %d optimized frames", n);

        Image.rgbScaling(Image.RGBScaling.nearest);
        if (bilinear)
        {
            Image.rgbScaling(Image.RGBScaling.bilinear);
            writefln("Using bilinear scaling - can be slow!");
            // NOTE: this can be *really* slow with large sizes, if FLTK
            //       has to resize on its own without hardware scaling enabled.
        }
        orig.frameUncache(uncache);
        if (uncache)
            writefln("Caching disabled - watch cpu load!");

        // set initial size to fit into window
        double ratio = orig.valid() ? cast(double) orig.w() / orig.h() : 1;
        int w = win.w() - 40;
        int h = cast(int)(w / ratio);
        writefln("original size: %d x %d", orig.w(), orig.h());
        win.size(w, h);
        fl.addHandler((e) { return events(e); });

        fl.run();
    }
}
