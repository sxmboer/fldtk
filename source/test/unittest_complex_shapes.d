// D transliteration of FLTK's test/unittest_complex_shapes.cxx.
// One tab of the "unittests" bundle; see
// source/test/unittests.d for the registry.
// Build: rdmd buildsamples.d test unittest_complex_shapes
module unittest_complex_shapes;

import fl;
import unittests;

//
// --- test drawing complex shapes ------
//

// D resolves forward references within a module automatically, unlike
// C++ -- no forward declaration of UtComplexShapesTest/drawComplex()
// needed before their use below (FLTK needs both, since C++
// compiles top-to-bottom within a translation unit).

class UtGlComplexShapesTest : GlWindow
{
    this(int x, int y, int w, int h)
    {
        super(x, y, w, h);
        box(Boxtype.flatBox);
        end();
    }

    override void draw()
    {
        drawBegin();
        super.draw();
        drawComplex(cast(UtComplexShapesTest) parent());
        drawEnd();
    }
}

class UtNativeComplexShapesTest : Window
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
        drawComplex(cast(UtComplexShapesTest) parent());
    }
}

//
//------- test the complex shape drawing capabilities of this implementation ----------
//
class UtComplexShapesTest : FlGroup
{
    private UtNativeComplexShapesTest nativeTestWindow;
    private UtGlComplexShapesTest glTestWindow;

    private static void updateCb(Widget w, UtComplexShapesTest This)
    {
        This.nativeTestWindow.redraw();
        This.glTestWindow.redraw();
    }

    HorValueSlider scale;
    Dial rotate;
    Positioner position;

    void setTransformation()
    {
        fl_translate(position.xvalue(), position.yvalue());
        fl_rotate(-rotate.value());
        fl_scale(scale.value(), scale.value());
    }

    static Widget create()
    {
        return new UtComplexShapesTest(UT_TESTAREA_X, UT_TESTAREA_Y, UT_TESTAREA_W, UT_TESTAREA_H);
    }

    this(int x, int y, int w, int h)
    {
        super(x, y, w, h);
        label("Testing complex shape drawing.");
        alignment(alignInside | alignBottom | alignLeft | alignWrap);
        box(Boxtype.borderBox);

        int a = x + 16, b = y + 34;
        Box t = new Box(a, b - 24, 80, 18, "native");
        t.alignment(alignLeft | alignInside);

        nativeTestWindow = new UtNativeComplexShapesTest(a + 23, b - 1, 200, 200);

        t = new Box(a, b, 18, 18, "1");
        t.box(Boxtype.roundedBox); t.color(yellow);
        t.tooltip(
            "Testing complex drawing with transformations.\n\n"
            ~ "Draw a point pattern, an open line, a closed line, and a covenx polygon.\n\n"
            ~ "Use the controls at the bottom right to scale, rotate, and move the patterns.");
        b += 44;
        t = new Box(a, b, 18, 18, "2");
        t.box(Boxtype.roundedBox); t.color(yellow);
        t.tooltip(
            "Testing complex polygons.\n\n"
            ~ "Draw polygons at different leves of complexity. "
            ~ "All polygons should be within the blue boundaries\n\n"
            ~ "1: a convex polygon\n"
            ~ "2: a non-convex polygon\n"
            ~ "3: two polygons in a single operation\n"
            ~ "4: a polygon with a square hole in it");
        b += 44;
        t = new Box(a, b, 18, 18, "3");
        t.box(Boxtype.roundedBox); t.color(yellow);
        t.tooltip(
            "Testing complex polygons with arcs.\n\n"
            ~ "Draw polygons with an arc section. "
            ~ "All polygons should be within the blue boundaries\n\n"
            ~ "1: a polygon with a camel hump\n"
            ~ "2: a polygon with a camel dip");

        a = x + 16 + 250; b = y + 34;
        t = new Box(a, b - 24, 80, 18, "OpenGL");
        t.alignment(alignLeft | alignInside);

        glTestWindow = new UtGlComplexShapesTest(a + 31, b - 1, 200, 200);

        t = new Box(a, b, 26, 18, "1a");
        t.box(Boxtype.roundedBox); t.color(yellow);
        t.tooltip(
            "Testing complex drawing with transformations.\n\n"
            ~ "Draw a point pattern, an open line, a closed line, and a convex polygon.\n\n"
            ~ "Use the controls at the bottom right to scale, rotate, and move the patterns.");
        b += 44;
        t = new Box(a, b, 28, 18, "2a");
        t.box(Boxtype.roundedBox); t.color(yellow);
        t.tooltip(
            "Testing complex polygons.\n\n"
            ~ "Draw polygons at different leves of complexity. "
            ~ "All polygons should be within the blue boundaries\n\n"
            ~ "1: a convex polygon\n"
            ~ "2: a non-convex polygon\n"
            ~ "3: two polygons in a single operation\n"
            ~ "4: a polygon with a square hole in it");
        b += 44;
        t = new Box(a, b, 28, 18, "3a");
        t.box(Boxtype.roundedBox); t.color(yellow);
        t.tooltip(
            "Testing complex polygons with arcs.\n\n"
            ~ "Draw polygons with an arc section. "
            ~ "All polygons should be within the blue boundaries\n\n"
            ~ "1: a polygon with a camel hump\n"
            ~ "2: a polygon with a camel dip");

        a = UT_TESTAREA_X + UT_TESTAREA_W - 250;
        b = UT_TESTAREA_Y + UT_TESTAREA_H - 50;

        scale = new HorValueSlider(a, b + 10, 120, 20, "Scale:");
        scale.alignment(alignTopLeft);
        scale.range(0.8, 1.2);
        scale.value(1.0);
        scale.callback((w) { updateCb(w, this); });

        rotate = new Dial(a + 140, b, 40, 40, "Rotate:");
        rotate.alignment(alignTopLeft);
        rotate.angles(0, 360);
        rotate.range(-180.0, 180.0);
        rotate.value(0.0);
        rotate.callback((w) { updateCb(w, this); });

        position = new Positioner(a + 200, b, 40, 40, "Offset:");
        position.alignment(alignTopLeft);
        position.xbounds(-10, 10);
        position.ybounds(-10, 10);
        position.value(0.0, 0.0);
        position.callback((w) { updateCb(w, this); });

        t = new Box(a - 1, b - 1, 1, 1);
        resizable(t);
    }
}

void convexShape(int w, int h)
{
    vertex(-w / 2, -h);
    vertex(w / 2, -h);
    vertex(w, 0);
    vertex(w, h);
    vertex(0, h);
    vertex(-w, h / 2);
    vertex(-w, -h / 2);
}

void complexShape(int w, int h)
{
    vertex(-w / 2, -h);
    vertex(0, -h / 2);
    vertex(w / 2, -h);
    vertex(w, 0);
    vertex(w, h);
    vertex(0, h);
    vertex(-w, h / 2);
    vertex(-w / 2, 0);
    vertex(-w, -h / 2);
}

void twoComplexShapes(int w, int h)
{
    vertex(-w / 2, -h);
    vertex(w / 2, -h);
    vertex(w, 0);
    vertex(w, h - 3);
    fl_gap();
    vertex(w - 3, h);
    vertex(0, h);
    vertex(-w, h / 2);
    vertex(-w, -h / 2);
}

void complexShapeWithHole(int w, int h)
{
    int w2 = w / 3, h2 = h / 3;
    // clockwise
    vertex(-w / 2, -h);
    vertex(w / 2, -h);
    vertex(w, 0);
    vertex(w, h);
    vertex(0, h);
    vertex(-w, h / 2);
    vertex(-w, -h / 2);
    fl_gap();
    // counterclockwise
    vertex(-w2, -h2);
    vertex(-w2, h2);
    vertex(w2, h2);
    vertex(w2, -h2);
}

void drawComplex(UtComplexShapesTest p)
{
    int a = 0, b = 0, dx = 20, dy = 20, w = 10, h = 10;
    int w2 = w / 3, h2 = h / 3;
    // ---- 1: draw a random shape
    fl_color(black);
    // -- points
    pushMatrix();
    fl_translate(a + dx, b + dy);
    p.setTransformation();
    beginPoints();
    convexShape(w, h);
    endPoints();
    popMatrix();
    // -- lines
    pushMatrix();
    fl_translate(a + dx + 50, b + dy);
    p.setTransformation();
    beginLine();
    convexShape(w, h);
    endLine();
    popMatrix();
    // -- line loop
    pushMatrix();
    fl_translate(a + dx + 100, b + dy);
    p.setTransformation();
    beginLoop();
    convexShape(w, h);
    endLoop();
    popMatrix();
    // -- polygon
    pushMatrix();
    fl_translate(a + dx + 150, b + dy);
    p.setTransformation();
    beginPolygon();
    convexShape(w, h);
    endPolygon();
    popMatrix();

    // ---- 2: draw a complex shape
    b += 44;
    // -- convex polygon drawn in complex mode
    pushMatrix();
    fl_translate(a + dx, b + dy);
    p.setTransformation();
    fl_color(dark2);
    beginComplexPolygon();
    convexShape(w, h);
    endComplexPolygon();
    fl_color(blue);
    beginLoop();
    convexShape(w, h);
    endLoop();
    popMatrix();
    // -- non-convex polygon drawn in complex mode
    pushMatrix();
    fl_translate(a + dx + 50, b + dy);
    p.setTransformation();
    fl_color(dark2);
    beginComplexPolygon();
    complexShape(w, h);
    endComplexPolygon();
    fl_color(blue);
    beginLoop();
    complexShape(w, h);
    endLoop();
    popMatrix();
    // -- two part polygon with gap
    pushMatrix();
    fl_translate(a + dx + 100, b + dy);
    p.setTransformation();
    fl_color(dark2);
    beginComplexPolygon();
    twoComplexShapes(w, h);
    endComplexPolygon();
    fl_color(blue);
    beginLoop();
    vertex(-w / 2, -h);
    vertex(w / 2, -h);
    vertex(w, 0);
    vertex(w, h - 3);
    endLoop();
    beginLoop();
    vertex(w - 3, h);
    vertex(0, h);
    vertex(-w, h / 2);
    vertex(-w, -h / 2);
    endLoop();
    popMatrix();
    // -- polygon with a hole
    pushMatrix();
    fl_translate(a + dx + 150, b + dy);
    p.setTransformation();
    fl_color(dark2);
    beginComplexPolygon();
    complexShapeWithHole(w, h);
    endComplexPolygon();
    fl_color(blue);
    beginLoop();
    vertex(-w / 2, -h);
    vertex(w / 2, -h);
    vertex(w, 0);
    vertex(w, h);
    vertex(0, h);
    vertex(-w, h / 2);
    vertex(-w, -h / 2);
    endLoop();
    beginLoop();
    vertex(-w2, -h2);
    vertex(-w2, h2);
    vertex(w2, h2);
    vertex(w2, -h2);
    endLoop();
    popMatrix();

    // ---- 3: draw polygons with arcs
    b += 44;
    // -- a rectangle with a camel hump
    pushMatrix();
    fl_translate(a + dx, b + dy);
    p.setTransformation();
    fl_color(dark2);
    beginComplexPolygon();
    vertex(-w, 0); fl_arc(0, 0, w - 3, 180.0, 0.0); vertex(w, 0);
    vertex(w, h); vertex(-w, h);
    endComplexPolygon();
    fl_color(blue);
    beginLoop();
    vertex(-w, 0); fl_arc(0, 0, w - 3, 180.0, 0.0); vertex(w, 0);
    vertex(w, h); vertex(-w, h);
    endLoop();
    popMatrix();
    // -- a rectangle with a camel dip
    pushMatrix();
    fl_translate(a + dx + 50, b + dy);
    p.setTransformation();
    fl_color(dark2);
    beginComplexPolygon();
    vertex(-w, 0); fl_arc(0, 0, w - 3, 180.0, 360.0); vertex(w, 0);
    vertex(w, h); vertex(-w, h);
    endComplexPolygon();
    fl_color(blue);
    beginLoop();
    vertex(-w, 0); fl_arc(0, 0, w - 3, 180.0, 360.0); vertex(w, 0);
    vertex(w, h); vertex(-w, h);
    endLoop();
    popMatrix();
    // -- a rectangle with a bezier curve top
    pushMatrix();
    fl_translate(a + dx + 100, b + dy);
    p.setTransformation();
    fl_color(dark2);
    beginComplexPolygon();
    vertex(-w, 0);
    curve(-w + 3, 0, 0, -h, 0, h, w - 3, 0);
    vertex(w, 0);
    vertex(w, h); vertex(-w, h);
    endComplexPolygon();
    fl_color(blue);
    beginLoop();
    vertex(-w, 0);
    curve(-w + 3, 0, 0, -h, 0, h, w - 3, 0);
    vertex(w, 0);
    vertex(w, h); vertex(-w, h);
    endLoop();
    popMatrix();
}

static this()
{
    new UnitTest(UT_TEST_COMPLEX_SHAPES, "Complex Shapes", () => UtComplexShapesTest.create());
}
