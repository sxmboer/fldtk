// D transliteration of FLTK's test/fullscreen.cxx.
// Build: rdmd buildsamples.d test fullscreen
//
// Fullscreen test program. FLTK conditionally builds a GL-drawn
// shape_window when HAVE_GL, or a plain 2D-drawn one otherwise; this
// port takes the real `#if HAVE_GL` branch, using the same plain
// immediate-mode GL draw() override source/test/shape.d already uses.
import fl;
import std.math : PI, cos, sin;
import std.format : format;

class ShapeWindow : GlWindow
{
    int sides;

    this(int x, int y, int w, int h, string l = null)
    {
        super(x, y, w, h, l);
        sides = 3;
    }

    override void draw()
    {
        if (!valid())
        {
            valid(1);
            glLoadIdentity();
            glViewport(0, 0, pixelW(), pixelH());
        }
        glClear(GL_COLOR_BUFFER_BIT);
        glColor3f(.5f, .6f, .7f);
        glBegin(GL_POLYGON);
        for (int j = 0; j < sides; j++)
        {
            double ang = j * 2 * PI / sides;
            glVertex3f(cast(GLfloat) cos(ang), cast(GLfloat) sin(ang), 0);
        }
        glEnd();
    }
}

class FullscreenWindow : SingleWindow
{
    this(int w, int h, string t = null)
    {
        super(w, h, t);
    }

    override void resize(int x, int y, int w, int h)
    {
        super.resize(x, y, w, h);
        fl.addTimeout(0, () { afterResize(this); });
    }

    ToggleLightButton borderButton;
    ToggleLightButton maximizeButton;
    ToggleLightButton fullscreenButton;
    ToggleLightButton allscreensButton;
}

void afterResize(FullscreenWindow win)
{
    if (win.maximizeActive())
        win.maximizeButton.set();
    else
        win.maximizeButton.clear();
    win.maximizeButton.redraw();
    if (win.fullscreenActive())
        win.fullscreenButton.set();
    else
        win.fullscreenButton.clear();
    win.fullscreenButton.redraw();
}

void sidesCb(Widget o, ShapeWindow sw)
{
    sw.sides = cast(int)(cast(Slider) o).value();
    sw.redraw();
}

void doubleCb(Widget o, ShapeWindow sw)
{
    int d = (cast(Button) o).value();
    sw.mode(d ? (modeDouble | modeRgb) : modeRgb);
}

void borderCb(Button b, Window w)
{
    int d = b.value();
    w.border(d != 0);
    // border change may have been refused (e.g. with fullscreen window)
    if (w.border() != (d != 0))
        b.value(w.border());
}

void maximizeCb(Button b, Window w)
{
    if (w.fullscreenActive())
    {
        b.value(1 - b.value());
        return;
    }
    if (w.maximizeActive())
        w.unMaximize();
    else
        w.maximize();
}

void fullscreenCb(Button b, Window w)
{
    if (w.maximizeActive())
    {
        b.value(1 - b.value());
        return;
    }
    if (b.value())
        w.fullscreen();
    else
        w.fullscreenOff();
}

void allscreensCb(Widget o, Window w)
{
    int d = (cast(Button) o).value();
    if (d)
    {
        int top, bottom, left, right;
        int topY, bottomY, leftX, rightX;

        int sx, sy, sw, sh;

        top = bottom = left = right = 0;

        fl.screenXYWH(sx, sy, sw, sh, 0);
        topY = sy;
        bottomY = sy + sh;
        leftX = sx;
        rightX = sx + sw;

        for (int i = 1; i < fl.screenCount(); i++)
        {
            fl.screenXYWH(sx, sy, sw, sh, i);
            if (sy < topY)
            {
                top = i;
                topY = sy;
            }
            if ((sy + sh) > bottomY)
            {
                bottom = i;
                bottomY = sy + sh;
            }
            if (sx < leftX)
            {
                left = i;
                leftX = sx;
            }
            if ((sx + sw) > rightX)
            {
                right = i;
                rightX = sx + sw;
            }
        }

        w.fullscreenScreens(top, bottom, left, right);
    }
    else
    {
        w.fullscreenScreens(-1, -1, -1, -1);
    }
}

void updateScreeninfo(Widget b, Browser browser)
{
    browser.clear();

    browser.add(format("Main screen work area: %dx%d@%d,%d", fl.w(), fl.h(), fl.x(), fl.y()));
    int x, y, w, h;
    fl.screenWorkArea(x, y, w, h);
    browser.add(format("Mouse screen work area: %dx%d@%d,%d", w, h, x, y));
    for (int n = 0; n < fl.screenCount(); n++)
    {
        float dpih, dpiv;
        fl.screenXYWH(x, y, w, h, n);
        fl.screenDpi(dpih, dpiv, n);
        browser.add(format("Screen %d: %dx%d@%d,%d DPI:%.1fx%.1f scale:%.2f",
                n, w, h, x, y, dpih, dpiv, fl.screenScale(n)));
        fl.screenWorkArea(x, y, w, h, n);
        browser.add(format("Work area %d: %dx%d@%d,%d", n, w, h, x, y));
    }
}

void exitCb(Widget)
{
    fl.hideAllWindows();
}

enum int numb = 9;

bool twowindow = false;
bool initfull = false;

bool parseArg(string[] argv, ref int i)
{
    if (argv[i][1] == '2')
    {
        twowindow = true;
        i++;
        return true;
    }
    if (argv[i][1] == 'f')
    {
        initfull = true;
        i++;
        return true;
    }
    return false;
}

void main(string[] args)
{
    fl.useHighResGL(true);
    int i = 0;
    if (fl.args(args, i, (argv, ref j) => parseArg(argv, j) ? 1 : 0) < args.length)
        fl.fatal(format("Options are:\n -2 = 2 windows\n -f = startup fullscreen\n%s", fl.argsHelp));

    auto window = new FullscreenWindow(460, 400 + 30 * numb);
    window.end();

    auto sw = new ShapeWindow(10, 10, window.w() - 20, window.h() - 30 * numb - 120);
    sw.setVisible(); // necessary because sw is not a child of window
    sw.mode(modeRgb);

    Window w;
    if (twowindow)
    { // make its own window
        sw.resizable(sw);
        w = sw;
        window.setModal(); // makes controls stay on top when fullscreen pushed
        sw.show();
    }
    else
    { // otherwise make a subwindow
        window.add(sw);
        window.resizable(sw);
        w = window;
    }

    window.begin();

    int y = window.h() - 30 * numb - 105;
    auto slider = new HorSlider(50, y, window.w() - 60, 30, "Sides:");
    slider.alignment(alignLeft);
    slider.callback((o) { sidesCb(o, sw); });
    slider.value(sw.sides);
    slider.step(1);
    slider.bounds(3, 40);
    y += 30;

    auto b1 = new ToggleLightButton(50, y, window.w() - 60, 30, "Double Buffered");
    b1.callback((o) { doubleCb(o, sw); });
    y += 30;

    auto i1 = new Input(50, y, window.w() - 60, 30, "Input");
    y += 30;

    window.borderButton = new ToggleLightButton(50, y, window.w() - 60, 30, "Border");
    window.borderButton.callback((o) { borderCb(cast(Button) o, w); });
    window.borderButton.set();
    y += 30;

    window.fullscreenButton = new ToggleLightButton(50, y, window.w() - 60, 30, "FullScreen");
    window.fullscreenButton.callback((o) { fullscreenCb(cast(Button) o, w); });
    y += 30;

    window.maximizeButton = new ToggleLightButton(50, y, window.w() - 60, 30, "Maximize");
    window.maximizeButton.callback((o) { maximizeCb(cast(Button) o, w); });
    y += 30;

    window.allscreensButton = new ToggleLightButton(50, y, window.w() - 60, 30, "All Screens");
    window.allscreensButton.callback((o) { allscreensCb(o, w); });
    y += 30;

    auto eb = new Button(50, y, window.w() - 60, 30, "Exit");
    eb.callback((o) { exitCb(o); });
    y += 30;

    auto browser = new Browser(50, y, window.w() - 60, 100);
    updateScreeninfo(null, browser);
    y += 100;

    auto update = new Button(50, y, window.w() - 60, 30, "Update");
    update.callback((o) { updateScreeninfo(o, browser); });
    y += 30;

    if (initfull)
    {
        window.fullscreenButton.set();
        window.fullscreenButton.doCallback();
    }

    window.end();
    window.show(args);

    fl.run();
}
