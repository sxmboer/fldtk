// fldtk test program: capturing windows that contain GL subwindows.
// Build: rdmd buildsamples.d test gl_capture
//
// Two windows, one single-buffered (`Window`) and one double-buffered
// (`DoubleWindow`), each holding a red GL window directly and a blue GL
// window inside a plain subwindow. Each window's buttons capture it
// three ways and show the result in a new, yellow-framed window:
//
//   captureWindow()     `fl.core.captureWindow()`: reads the window's
//                       pixels back (the path `WidgetSurface.
//                       printWindowPart()` and Fluid's template preview
//                       use).
//   ImageSurface.draw() `WidgetSurface.draw()`: redraws the widget tree
//                       onto an image surface (the path printing and
//                       SVG/EPS export use).
//   Print...            `Printer.printWidget()`, to a real printer or a
//                       PDF printer.
//
// A path captures GL correctly when both squares show their color with a
// white triangle, as on screen. A black, grey or empty square means that
// path leaves GL out.
//
// "GL windows" hides and shows all four GL windows, to tell a problem
// with capturing GL apart from one with capturing the windows around it.
import fl;

ColorGlWindow[] glWindows;

/// A GL window filled with one color, with a white triangle on top, so a
/// capture shows at a glance whether its pixels came along.
class ColorGlWindow : GlWindow
{
    float r, g, b;

    this(int x, int y, int w, int h, float r, float g, float b)
    {
        super(x, y, w, h);
        this.r = r;
        this.g = g;
        this.b = b;
    }

    override void draw()
    {
        if (!valid())
        {
            valid(1);
            glLoadIdentity();
            glViewport(0, 0, pixelW(), pixelH());
        }
        glClearColor(r, g, b, 1);
        glClear(GL_COLOR_BUFFER_BIT);
        glColor3f(1, 1, 1);
        glBegin(GL_TRIANGLES);
        glVertex3f(-0.7f, -0.6f, 0);
        glVertex3f(0.7f, -0.6f, 0);
        glVertex3f(0, 0.7f, 0);
        glEnd();
    }
}

void showResult(Image img, string title)
{
    if (img is null)
    {
        message(title ~ ": no image (the capture failed)");
        return;
    }
    auto result = new Window(img.w() + 10, img.h() + 10, title);
    result.color(yellow);
    auto box = new Box(Boxtype.noBox, 5, 5, img.w(), img.h(), null);
    box.image(img);
    result.end();
    result.show();
}

void captureCb(Window win)
{
    // captureWindow() takes device pixels; scale the result back to the
    // window's size so it compares 1:1 with the window on screen.
    float s = screenScale(win.screenNum());
    auto img = captureWindow(win, 0, 0, cast(int)(win.w() * s), cast(int)(win.h() * s));
    if (img !is null) img.scale(win.w(), win.h(), true, true);
    showResult(img, "captureWindow(): " ~ win.label());
}

void imageSurfaceCb(Window win)
{
    auto surf = new ImageSurface(win.w(), win.h(), 1);
    SurfaceDevice.pushCurrent(surf);
    fl_color(yellow);
    fl_rectf(0, 0, win.w(), win.h());
    surf.draw(win);
    Image img = surf.image();
    destroy(surf);
    SurfaceDevice.popCurrent();
    showResult(img, "ImageSurface.draw(): " ~ win.label());
}

void printCb(Window win)
{
    auto printer = new Printer();
    string errMessage;
    if (printer.beginJob(1, errMessage))
    {
        if (errMessage.length) message(errMessage);
        return;
    }
    if (printer.beginPage()) return;
    printer.printWidget(win);
    printer.endPage();
    printer.endJob();
}

Window makeTarget(bool doubleBuffered, int x)
{
    string title = doubleBuffered ? "DoubleWindow" : "Window";
    Window win = doubleBuffered ? new DoubleWindow(x, 60, 480, 300, title)
                                : new Window(x, 60, 480, 300, title);
    new Box(10, 10, 330, 25, doubleBuffered ? "Double-buffered window" : "Single-buffered window");
    auto showGl = new CheckButton(350, 10, 120, 25, "GL windows");
    showGl.value(1);
    showGl.callback((w) {
        bool on = (cast(CheckButton) w).value() != 0;
        foreach (glw; glWindows)
            if (on) glw.show(); else glw.hide();
    });

    // A GL window directly in the top-level window...
    glWindows ~= new ColorGlWindow(40, 45, 160, 160, 0.8f, 0.1f, 0.1f);

    // ...and one inside a plain subwindow, which the capture has to
    // descend into.
    auto sub = new Window(280, 45, 160, 160);
    sub.box(Boxtype.downBox);
    sub.color(cyan);
    new Box(10, 5, 140, 20, "subwindow");
    glWindows ~= new ColorGlWindow(20, 30, 120, 120, 0.1f, 0.2f, 0.8f);
    sub.end();

    auto capture = new Button(10, 255, 150, 30, "captureWindow()");
    capture.labelsize(12);
    capture.callback((w) { captureCb(win); });
    auto surface = new Button(165, 255, 150, 30, "ImageSurface.draw()");
    surface.labelsize(12);
    surface.callback((w) { imageSurfaceCb(win); });
    auto print = new Button(320, 255, 150, 30, "Print...");
    print.labelsize(12);
    print.callback((w) { printCb(win); });

    win.end();
    return win;
}

void main(string[] args)
{
    auto single = makeTarget(false, 20);
    auto dbl = makeTarget(true, 520);
    single.show(args);
    dbl.show();
    fl.run();
}
