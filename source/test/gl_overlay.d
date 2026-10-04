// D transliteration of FLTK's test/gl_overlay.cxx (~/Repositories/fltk).
// Part of the samples/ contract -- see samples/README.md.
// Check: ./samples/build.sh gl_overlay
//
// OpenGL overlay test: a GL polygon whose side count is slider-driven,
// plus a software-simulated-overlay wireframe outline (also slider-
// driven) drawn on top of it without needing to redraw the polygon
// itself, using the real `fl.gl_window.GlWindow.drawOverlay()`/
// `redrawOverlay()`/`canDoOverlay()` support.
import fl;
import std.math : cos, sin, PI;
import std.stdio : writefln;

class ShapeWindow : GlWindow
{
    int sides;
    int overlaySides;

    this(int x, int y, int w, int h, string l = null)
    {
        super(x, y, w, h, l);
        sides = overlaySides = 3;
    }

    override void draw()
    {
        // the valid() property may be used to avoid reinitializing your
        // GL transformation for each redraw:
        if (!valid())
        {
            valid(1);
            glLoadIdentity();
            glViewport(0, 0, pixelW(), pixelH());
        }
        // draw an amazing but slow graphic:
        glClear(GL_COLOR_BUFFER_BIT);
        glBegin(GL_POLYGON);
        for (int j = 0; j < sides; j++)
        {
            double ang = j * 2 * PI / sides;
            glColor3f(cast(float) j / sides, cast(float) j / sides, cast(float) j / sides);
            glVertex3f(cast(GLfloat) cos(ang), cast(GLfloat) sin(ang), 0);
        }
        glEnd();
    }

    override void drawOverlay()
    {
        // the valid() property may be used to avoid reinitializing your
        // GL transformation for each redraw:
        if (!valid())
        {
            valid(1);
            glLoadIdentity();
            glViewport(0, 0, pixelW(), pixelH());
        }
        // draw an amazing graphic:
        gl_color(red);
        glBegin(GL_LINE_LOOP);
        for (int j = 0; j < overlaySides; j++)
        {
            double ang = j * 2 * PI / overlaySides;
            glVertex3f(cast(GLfloat) cos(ang), cast(GLfloat) sin(ang), 0);
        }
        glEnd();
    }
}

void main(string[] args)
{
    fl.useHighResGL(true);
    auto window = new Window(300, 370);

    auto sw = new ShapeWindow(10, 75, window.w() - 20, window.h() - 90);
    //sw.mode(rgbMode);
    window.resizable(sw);

    auto slider = new HorSlider(60, 5, window.w() - 70, 30, "Sides:");
    slider.alignment(alignLeft);
    slider.callback((o) {
        sw.sides = cast(int)(cast(Slider) o).value();
        sw.redraw();
    });
    slider.value(sw.sides);
    slider.step(1);
    slider.bounds(3, 40);

    auto oslider = new HorSlider(60, 40, window.w() - 70, 30, "Overlay:");
    oslider.alignment(alignLeft);
    oslider.callback((o) {
        sw.overlaySides = cast(int)(cast(Slider) o).value();
        sw.redrawOverlay();
    });
    oslider.value(sw.overlaySides);
    oslider.step(1);
    oslider.bounds(3, 40);

    window.end();
    window.show(args);

    writefln("Can do overlay = %d", sw.canDoOverlay());
    sw.show();
    sw.redrawOverlay();

    fl.run();
}
