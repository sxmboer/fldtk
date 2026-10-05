// D transliteration of FLTK's examples/animgifimage-play.cxx.
// Build: rdmd buildsamples.d examples animgifimage_play
//
//  Demonstrates how to play an animated GIF file under application
//  control frame by frame if this is needed. Also demonstrates how to
//  use a single animation object to load multiple animations.
//
//  animgifimage <file> [-r] [-s speed_factor]
//
//  Multiple files can be specified e.g. testsuite/*
//
//  Use keys '+'/'-'/Enter to change speed, ' ' to pause.
//  Right key changes to next frame in paused mode.
//  'n' changes to next file, 'r' toggles reverse play.
import fl;
import std.stdio : writefln, stderr;
import std.conv : to, ConvException;

double speedFactor = 1.;    // slow down/speed up playback by factor
bool reverse = false;       // true = play animation backwards
bool paused = false;        // flag for paused animation
bool frameInfo = false;     // flag to update current frame info in title
// FLTK's `Fl_Anim_GIF_Image animgif;` is a plain global *value*
// (default-constructs automatically); a D class variable is a null
// reference until explicitly `new`ed, so this needs its own
// initialization (see static this() below) -- otherwise every access
// before the first real load() is a null dereference.
AnimGifImage animgif;       // the animation object
string[] gArgs;             // copy of main()'s args
int currentArg = 0;         // current index in gArgs

int nextArg()
{
    while (true)
    {
        currentArg++;
        if (currentArg >= gArgs.length)
            currentArg = 1;
        if (gArgs[currentArg].length)
            break;
    }
    return currentArg;
}

string nextFile()
{
    while (gArgs[nextArg()][0] == '-')
    {
    }
    return gArgs[currentArg];
}

void setTitle()
{
    string fi = frameInfo
        ? "frame " ~ (animgif.frame() + 1).to!string ~ "/" ~ animgif.frames().to!string
        : animgif.frames().to!string ~ " frames";
    string buf = gArgs[currentArg] ~ " (" ~ fi ~ ") x "
        ~ speedFactor.to!string ~ " " ~ (reverse ? "reverse" : "")
        ~ (paused ? " PAUSED" : "");

    fl.firstWindow().copyLabel(buf);
}

void cbAnim(AnimGifImage* d)
{
    AnimGifImage anim = *d;
    int frame = anim.frame();

    // switch to next/previous frame
    if (reverse)
    {
        anim.canvas().window().redraw();
        frame--;
        if (frame < 0)
            frame = anim.frames() - 1;
    }
    else
    {
        frame++;
        if (frame >= anim.frames())
            frame = 0;
    }
    // set the frame (and update canvas)
    anim.frame(frame);

    // setup timer for next frame
    if (!paused && anim.delay(frame))
        fl.repeatTimeout(anim.delay(frame) / speedFactor, cbAnimDg);
    if (frameInfo)
        setTitle();
}

// fl.core's timer functions need a stable delegate identity to match
// against for removeTimeout() (D delegate equality compares function
// pointer + context; a fresh `() { cbAnim(&animgif); }` literal per
// call site would never compare equal to an earlier one) -- one
// shared delegate, reused at every call site below.
void delegate() cbAnimDg;
static this()
{
    animgif = new AnimGifImage();
    cbAnimDg = () { cbAnim(&animgif); };
}

void nextFrame()
{
    cbAnim(&animgif);
}

void togglePause()
{
    paused = !paused;
    setTitle();
    if (paused)
        fl.removeTimeout(cbAnimDg);
    else
        nextFrame();
    setTitle();
}

void toggleInfo()
{
    frameInfo = !frameInfo;
    setTitle();
}

void toggleReverse()
{
    reverse = !reverse;
    setTitle();
}

void zoom(bool out_)
{
    int w = animgif.w();
    int h = animgif.h();
    // Note: deliberately no range check (use key 'N' to reset)
    enum double f = 1.05;
    if (out_)
        animgif.resize(cast(int)(w / f), cast(int)(h / f));
    else
        animgif.resize(cast(int)(f * w), cast(int)(f * h));
}

void changeSpeed(int dir)
{
    if (dir > 0)
    {
        speedFactor += (speedFactor < 1) ? 0.01 : 0.1;
        if (speedFactor > 100)
            speedFactor = 100.;
    }
    else if (dir < 0)
    {
        speedFactor -= (speedFactor > 1) ? 0.1 : 0.01;
        if (speedFactor < 0.01)
            speedFactor = 0.01;
    }
    else
    {
        speedFactor = 1.;
    }
    setTitle();
}

void loadNext()
{
    fl.removeTimeout(cbAnimDg);
    paused = false;
    animgif.load(nextFile());
    animgif.canvas().window().redraw();
    // check if loading succeeded
    writefln("valid: %d frames: %d", animgif.valid(), animgif.frames());
    if (animgif.valid())
    {
        writefln("play '%s'%s with %3.2f x speed", animgif.name(),
                (reverse ? " reverse" : ""), speedFactor);
        animgif.frame(reverse ? animgif.frames() - 1 : 0);
        // setup first timeout, but check for zero-delay (normal GIF)!
        if (animgif.delay(animgif.frame()))
            fl.addTimeout(animgif.delay(animgif.frame()) / speedFactor, cbAnimDg);
    }
    setTitle();
}

int events(Event event)
{
    if (event == Event.shortcut && fl.firstWindow())
    {
        switch (fl.eventKey())
        {
        case '+':
            changeSpeed(1);
            break;
        case '-':
            changeSpeed(-1);
            break;
        case enter:
            changeSpeed(0);
            break;
        case 'n':
            loadNext();
            break;
        case 'z':
            zoom(fl.eventShift());
            break;
        case 'i':
            toggleInfo(); // Note: this can raise cpu usage considerably!
            break;
        case 'r':
            toggleReverse();
            break;
        case ' ':
            togglePause();
            break;
        case right:
            if (paused && fl.getKey(right))
                nextFrame();
            break;
        default:
            return 0;
        }
        fl.firstWindow().redraw();
        return 1;
    }
    return 0;
}

void main(string[] args)
{
    // setup play parameters from args
    gArgs = args;
    int n = 0;
    for (size_t i = 1; i < args.length; i++)
    {
        if (args[i] == "-r")
            reverse = !reverse;
        else if (args[i] == "-s" && i + 1 < args.length)
        {
            i++;
            // FLTK uses atof(), which returns 0.0 for a malformed
            // -s argument instead of throwing.
            try
                speedFactor = args[i].to!double;
            catch (ConvException)
                speedFactor = 0.0;
        }
        else if (args[i][0] != '-')
        {
            n++;
            continue;
        }
        else
        {
            writefln("Invalid argument: '%s'", args[i]);
            return;
        }
    }
    if (!n)
    {
        stderr.writefln("Test program for application controlled GIF animation.");
        stderr.writefln("Please specify one or more image files!");
        return;
    }
    if (speedFactor < 0.01 || speedFactor > 100)
        speedFactor = 1.;

    auto win = new DoubleWindow(800, 600);

    // prepare a canvas for the animation
    // (we want to show it in the center of the window)
    auto canvas = new Box(0, 0, win.w(), win.h());
    auto help = new Box(0, win.h() - 20, win.w(), 20,
            "Keys: N=next file, I=toggle info, R=play reverse, +/-/Enter/Space=change speed, Z=Zoom");
    win.resizable(win);

    win.end();
    win.show();
    fl.addHandler((e) { return events(e); });

    // use the 'DONT_RESIZE_CANVAS' flag to tell the animation
    // not to change the canvas size (which is the default).
    auto flags = AnimGifImage.dontResizeCanvas;
    //  flags |= AnimGifImage.debugFlag | AnimGifImage.logFlag;
    animgif.canvas(canvas, flags);

    loadNext();
    fl.run();
}
