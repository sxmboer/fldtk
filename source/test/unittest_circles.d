// D transliteration of FLTK's test/unittest_circles.cxx.
// One tab of the
// "unittests" bundle; see source/test/unittests.d for the registry.
// Build: rdmd buildsamples.d test unittest_circles
module unittest_circles;

import fl;
import unittests;

import std.math : PI, cos, sin;

//
// --- test drawing circles and arcs ------
//

void arc(int xi, int yi, int w, int h, double a1, double a2)
{
    if (a2 <= a1) return;

    double rx = w / 2.0;
    double ry = h / 2.0;
    double x = xi + rx + 0.5;
    double y = yi + ry + 0.5;
    double circ = PI * 0.5 * (rx + ry);
    int segs = cast(int)(circ * (a2 - a1) / 100);
    if (segs < 3) segs = 3;

    a1 = a1 / 180 * PI;
    a2 = a2 / 180 * PI;
    double step = (a2 - a1) / segs;

    int nx = cast(int)(x + cos(a1) * rx);
    int ny = cast(int)(y - sin(a1) * ry);
    point(nx, ny);
    for (int i = segs; i > 0; i--)
    {
        a1 += step;
        nx = cast(int)(x + cos(a1) * rx);
        ny = cast(int)(y - sin(a1) * ry);
        point(nx, ny);
    }
}

void drawCircles()
{
    int a = 0, b = 0, w = 40, h = 40;
    // ---- 1: draw a circle and a filled circle
    fl_color(red);
    arc(a + 1, b + 1, w - 2, h - 2, 0.0, 360.0);
    fl_color(green);
    arc(a, b, w, h, 0.0, 360.0);
    arc(a + 2, b + 2, w - 4, h - 4, 0.0, 360.0);
    fl_color(black);
    fl_arc(a + 1, b + 1, w - 1, h - 1, 0.0, 360.0);
    // ----
    fl_color(red);
    arc(a + 1 + 50, b + 1, w - 2, h - 2, 0.0, 360.0);
    fl_color(green);
    arc(a + 50, b, w, h, 0.0, 360.0);
    fl_color(black);
    fl_pie(a + 1 + 50, b + 1, w - 1, h - 1, 0.0, 360.0);
    b += 44;
    // ---- 2: draw arcs and pies
    fl_color(red);
    arc(a + 1, b + 1, w - 2, h - 2, 45.0, 315.0);
    fl_color(green);
    arc(a, b, w, h, 45.0, 315.0);
    arc(a + 2, b + 2, w - 4, h - 4, 45.0, 315.0);
    fl_color(black);
    fl_arc(a + 1, b + 1, w - 1, h - 1, 45.0, 315.0);
    fl_color(red);
    // ----
    arc(a + 1 + 50, b + 1, w - 2, h - 2, 45.0, 315.0);
    fl_line(a + 50 + 20, b + 20, a + 50 + 20 + 14, b + 20 - 14);
    fl_line(a + 50 + 20, b + 20, a + 50 + 20 + 14, b + 20 + 14);
    fl_color(green);
    arc(a + 50, b, w, h, 45.0, 315.0);
    fl_line(a + 50 + 21, b + 20, a + 50 + 21 + 14, b + 20 - 14);
    fl_line(a + 50 + 21, b + 20, a + 50 + 21 + 14, b + 20 + 14);
    fl_color(black);
    fl_pie(a + 1 + 50, b + 1, w - 1, h - 1, 45.0, 315.0);
}

class UtGlCircleTest : GlWindow
{
    this(int x, int y, int w, int h)
    {
        super(x, y, w, h);
        box(Boxtype.flatBox);
    }

    override void draw()
    {
        drawBegin();
        super.draw();
        drawCircles();
        drawEnd();
    }
}

class UtNativeCircleTest : Window
{
    this(int x, int y, int w, int h)
    {
        super(x, y, w, h);
        box(Boxtype.flatBox);
        end();
    }

    override void draw()
    {
        super.draw();
        drawCircles();
    }
}

//
//------- test the circle drawing capabilities of this implementation ----------
//
class UtCircleTest : FlGroup
{
    static Widget create()
    {
        return new UtCircleTest(UT_TESTAREA_X, UT_TESTAREA_Y, UT_TESTAREA_W, UT_TESTAREA_H);
    }

    this(int x, int y, int w, int h)
    {
        super(x, y, w, h);
        label("Testing fast circle, arc, and pie drawing\n\n"
            ~ "No red lines should be visible. "
            ~ "The green outlines should not be overwritten by circle drawings.");
        alignment(alignInside | alignBottom | alignLeft | alignWrap);
        box(Boxtype.borderBox);

        int a = x + 16, b = y + 34;
        Box t = new Box(a, b - 24, 80, 18, "native");
        t.alignment(alignLeft | alignInside);

        new UtNativeCircleTest(a + 23, b - 1, 200, 200);

        t = new Box(a, b, 18, 18, "1");
        t.box(Boxtype.roundedBox); t.color(yellow);
        t.tooltip(
            "Testing circle alignment.\n\n"
            ~ "This draws a black circle and a black disc, surrounded by a green frame.\n\n"
            ~ "If green pixels are missing, circle drawing must be adjusted (see fl_arc, fl_pie).\n\n"
            ~ "If red pixels are showing, line width or aligment may be off.");
        b += 44;
        t = new Box(a, b, 18, 18, "2");
        t.box(Boxtype.roundedBox); t.color(yellow);
        t.tooltip(
            "Testing arc and pie drawing.\n\n"
            ~ "This draws a black frame, surrounded on the inside and outside by a green frame.\n\n"
            ~ "If green pixels are missing or red pixels are showing, rectangular frame drawing schould be adjusted (see fl_rect).\n\n"
            ~ "If red pixels show in the corners of the frame in hidpi mode, line endings should be adjusted.");

        a = x + 16 + 250; b = y + 34;
        t = new Box(a, b - 24, 80, 18, "OpenGL");
        t.alignment(alignLeft | alignInside);

        new UtGlCircleTest(a + 31, b - 1, 200, 200);

        t = new Box(a, b, 26, 18, "1a");
        t.box(Boxtype.roundedBox); t.color(yellow);
        t.tooltip(
            "Testing circle alignment.\n\n"
            ~ "This draws a black circle and a black disc, surrounded by a green frame.\n\n"
            ~ "If green pixels are missing, circle drawing must be adjusted (see fl_arc, fl_pie).\n\n"
            ~ "If red pixels are showing, line width or aligment may be off.");
        b += 44;
        t = new Box(a, b, 26, 18, "2a");
        t.box(Boxtype.roundedBox); t.color(yellow);
        t.tooltip(
            "Testing arc and pie drawing.\n\n"
            ~ "This draws a black frame, surrounded on the inside and outside by a green frame.\n\n"
            ~ "If green pixels are missing or red pixels are showing, rectangular frame drawing schould be adjusted (see fl_rect).\n\n"
            ~ "If red pixels show in the corners of the frame in hidpi mode, line endings should be adjusted.");

        t = new Box(x + w - 1, y + h - 1, 1, 1);
        resizable(t);
    }
}

static this()
{
    new UnitTest(UT_TEST_CIRCLES, "Circles and Arcs", () => UtCircleTest.create());
}
