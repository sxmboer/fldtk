// D transliteration of FLTK's test/shape.cxx.
// Build: rdmd buildsamples.d test shape
//
// Tiny OpenGL demo, using the real `fl.gl_window.GlWindow` port of
// Fl_Gl_Window. gl*() calls keep their FLTK C names verbatim
// (foreign GL API, not FLTK's own naming surface) -- fl.opengl is the
// raw GL binding module these resolve to; it's not re-exported from
// `fl` (same reasoning as fl.xlib not being re-exported, see
// fl/package.d's own tail comment), so it needs its own explicit
// import alongside the usual `import fl;`.
import fl;
import std.math : cos, sin, PI;

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
        // the valid() property may be used to avoid reinitializing your
        // GL transformation for each redraw:
        if (!valid())
        {
            valid(1);
            glLoadIdentity();
            glViewport(0, 0, pixelW(), pixelH());
        }
        // draw an amazing graphic:
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

void main(string[] args)
{
    fl.useHighResGL(true);
    auto window = new Window(300, 330);

    // the shape window could be it's own window, but here we make it
    // a child window:
    auto sw = new ShapeWindow(10, 10, 280, 280);
    // make it resize:
    window.resizable(sw);
    //  window.sizeRange(300,330,0,0,1,1,1);
    // add a knob to control it:
    auto slider = new HorSlider(50, 295, window.w() - 60, 30, "Sides:");
    slider.alignment(alignLeft);
    slider.callback((o) {
        sw.sides = cast(int)(cast(Slider) o).value();
        sw.redraw();
    });
    slider.value(sw.sides);
    slider.step(1);
    slider.bounds(3, 40);

    window.end();
    window.show(args);

    fl.run();
}
