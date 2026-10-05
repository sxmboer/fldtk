// D transliteration of FLTK's test/unittest_fast_shapes.cxx.
// One tab of the "unittests" bundle; see
// source/test/unittests.d for the registry.
// Build: rdmd buildsamples.d test unittest_fast_shapes
module unittest_fast_shapes;

import fl;
import unittests;

//
// --- test drawing shapes that are not transformed by the drawing matrix ------
//

void drawFastShapes()
{
    int a = 0, b = 0;
    // 1: draw a filled rectangle (fl_rectf)
    fl_color(green);
    for (int i = 0; i <= 40; i++) { point(a + i, b); point(a + i, b + 20); }
    for (int i = 0; i <= 20; i++) { point(a, b + i); point(a + 40, b + i); }
    fl_color(red);
    for (int i = 1; i <= 39; i++) { point(a + i, b + 1); point(a + i, b + 19); }
    for (int i = 1; i <= 19; i++) { point(a + 1, b + i); point(a + 39, b + i); }
    fl_color(black);
    fl_rectf(a + 1, b + 1, 39, 19);
    // 2: draw a one units wide frame
    b += 24;
    fl_color(green);
    for (int i = 0; i <= 40; i++) { point(a + i, b); point(a + i, b + 20); }
    for (int i = 0; i <= 20; i++) { point(a, b + i); point(a + 40, b + i); }
    fl_color(green);
    for (int i = 2; i <= 38; i++) { point(a + i, b + 2); point(a + i, b + 18); }
    for (int i = 2; i <= 18; i++) { point(a + 2, b + i); point(a + 38, b + i); }
    fl_color(red);
    for (int i = 1; i <= 39; i++) { point(a + i, b + 1); point(a + i, b + 19); }
    for (int i = 1; i <= 19; i++) { point(a + 1, b + i); point(a + 39, b + i); }
    fl_color(black);
    fl_rect(a + 1, b + 1, 39, 19);
    // 3: draw a three units wide frame
    b += 24;
    fl_color(green);
    fl_rect(a, b, 41, 21);
    fl_rect(a + 4, b + 4, 33, 13);
    fl_color(red);
    fl_rect(a + 1, b + 1, 39, 19);
    fl_rect(a + 3, b + 3, 35, 15);
    fl_color(black);
    lineStyle(lineSolid, 3);
    fl_rect(a + 2, b + 2, 37, 17);
    lineStyle(lineSolid, 1);
    // 4: draw fl_xyline
    b += 24;
    fl_color(green);
    fl_rect(a, b + 8, 41, 3);   // single line
    fl_rect(a + 45, b, 41, 3);  // horizontal, then vertical line
    fl_rect(a + 83, b, 3, 21);
    fl_rect(a + 90, b, 21, 3);  // horizontal, vertical, horizontal line
    fl_rect(a + 109, b, 3, 21);
    fl_rect(a + 109, b + 18, 21, 3);
    fl_color(red);
    fl_rectf(a + 1, b + 9, 39, 1);   // single line
    fl_rectf(a + 46, b + 1, 39, 1);  // two lines
    fl_rectf(a + 84, b + 1, 1, 19);
    fl_rectf(a + 91, b + 1, 20, 1);  // three lines
    fl_rectf(a + 110, b + 1, 1, 19);
    fl_rectf(a + 110, b + 19, 19, 1); // three lines
    fl_color(black);
    fl_xyline(a + 1, b + 9, a + 39);
    fl_xyline(a + 46, b + 1, a + 84, b + 19);
    fl_xyline(a + 91, b + 1, a + 110, b + 19, a + 128);
    b += 24;
    fl_color(green);
    fl_rect(a, b + 7, 41, 5);   // single line
    fl_rect(a + 45, b, 41, 5);  // horizontal, then vertical line
    fl_rect(a + 81, b, 5, 21);
    fl_rect(a + 90, b, 22, 5);  // horizontal, vertical, horizontal line
    fl_rect(a + 108, b, 5, 21);
    fl_rect(a + 108, b + 16, 22, 5);
    fl_color(red);
    fl_rectf(a + 1, b + 8, 39, 3);   // single line
    fl_rectf(a + 46, b + 1, 39, 3);  // two lines
    fl_rectf(a + 82, b + 1, 3, 19);
    fl_rectf(a + 91, b + 1, 20, 3);  // three lines
    fl_rectf(a + 109, b + 1, 3, 19);
    fl_rectf(a + 109, b + 17, 20, 3); // three lines
    fl_color(black);
    lineStyle(lineSolid, 3);
    fl_xyline(a + 1, b + 9, a + 39);
    fl_xyline(a + 46, b + 2, a + 83, b + 19);
    fl_xyline(a + 91, b + 2, a + 110, b + 18, a + 128);
    lineStyle(lineSolid, 1);
    // 5: draw fl_yxline
    b += 24;
    fl_color(green);
    fl_rect(a + 9, b, 3, 21);    // single line
    fl_rect(a + 45, b, 3, 21);   // horizontal, then vertical line
    fl_rect(a + 45, b + 18, 41, 3);
    fl_rect(a + 90, b, 3, 11);   // horizontal, vertical, horizontal line
    fl_rect(a + 90, b + 9, 40, 3);
    fl_rect(a + 127, b + 9, 3, 12);
    fl_color(red);
    fl_rectf(a + 10, b + 1, 1, 19);  // single line
    fl_rectf(a + 46, b + 1, 1, 19);  // two lines
    fl_rectf(a + 46, b + 19, 39, 1);
    fl_rectf(a + 91, b + 1, 1, 10);  // three lines
    fl_rectf(a + 91, b + 10, 38, 1);
    fl_rectf(a + 128, b + 10, 1, 10); // three lines
    fl_color(black);
    fl_yxline(a + 10, b + 1, b + 19);
    fl_yxline(a + 46, b + 1, b + 19, a + 84);
    fl_yxline(a + 91, b + 1, b + 10, a + 128, b + 19);
    b += 24;
    fl_color(green);
    fl_rect(a + 8, b, 5, 21);    // single line
    fl_rect(a + 45, b, 5, 21);   // horizontal, then vertical line
    fl_rect(a + 45, b + 16, 41, 5);
    fl_rect(a + 90, b, 5, 11);   // horizontal, vertical, horizontal line
    fl_rect(a + 90, b + 8, 40, 5);
    fl_rect(a + 125, b + 8, 5, 13);
    fl_color(red);
    fl_rectf(a + 9, b + 1, 3, 19);   // single line
    fl_rectf(a + 46, b + 1, 3, 19);  // two lines
    fl_rectf(a + 46, b + 17, 39, 3);
    fl_rectf(a + 91, b + 1, 3, 10);  // three lines
    fl_rectf(a + 91, b + 9, 38, 3);
    fl_rectf(a + 126, b + 9, 3, 11); // three lines
    fl_color(black);
    lineStyle(lineSolid, 3);
    fl_yxline(a + 10, b + 1, b + 19);
    fl_yxline(a + 47, b + 1, b + 18, a + 84);
    fl_yxline(a + 92, b + 1, b + 10, a + 127, b + 19);
    lineStyle(lineSolid, 1);
    // 6: fast diagonal lines
    b += 24;
    fl_color(green);
    point(a, b); point(a + 1, b); point(a, b + 1);
    point(a + 20, b + 20); point(a + 19, b + 20); point(a + 20, b + 19);
    fl_color(red);
    point(a + 1, b + 1); point(a + 19, b + 19);
    fl_color(black);
    fl_line(a + 1, b + 1, a + 19, b + 19);
    fl_color(green);
    point(a + 25 + 1, b); point(a + 25, b + 1); point(a + 25 + 4, b); point(a + 25, b + 4);
    point(a + 25 + 20, b + 19); point(a + 25 + 19, b + 20); point(a + 25 + 16, b + 20); point(a + 25 + 20, b + 16);
    fl_color(red);
    point(a + 25 + 2, b + 2); point(a + 25 + 18, b + 18);
    fl_color(black);
    lineStyle(lineSolid, 5);
    fl_line(a + 25 + 1, b + 1, a + 25 + 19, b + 19);
    fl_line(a + 50 + 1, b + 1, a + 50 + 20, b + 20, a + 50 + 39, b + 1);
    lineStyle(lineSolid, 1);
}

class UtGlRectTest : GlWindow
{
    this(int x, int y, int w, int h)
    {
        super(x, y, w, h);
        box(Boxtype.flatBox);
    }

    override void draw()
    {
        drawBegin();
        fl_color(color());
        fl_rectf(0, 0, w(), h());
        drawFastShapes();
        drawEnd();
    }
}

class UtNativeRectTest : Window
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
        drawFastShapes();
    }
}

class UtRectTest : FlGroup // 520 x 365
{
    static Widget create()
    {
        return new UtRectTest(UT_TESTAREA_X, UT_TESTAREA_Y, UT_TESTAREA_W, UT_TESTAREA_H);
    }

    this(int x, int y, int w, int h)
    {
        super(x, y, w, h);
        label("Testing fldtk fast shape calls.\n"
            ~ "These calls draw horizontal and vertical lines, frames, and rectangles.\n\n"
            ~ "No red pixels should be visible. "
            ~ "If you see bright red lines, or if parts of the green frames are hidden, "
            ~ "drawing alignment is off.");
        alignment(alignInside | alignBottom | alignLeft | alignWrap);
        box(Boxtype.borderBox);

        int a = x + 16, b = y + 34;
        Box t = new Box(a, b - 24, 80, 18, "native");
        t.alignment(alignLeft | alignInside);

        new UtNativeRectTest(a + 23, b - 1, 200, 200);

        t = new Box(a, b, 18, 18, "1");
        t.box(Boxtype.roundedBox); t.color(yellow);
        t.tooltip(
            "Testing filled rectangle alignment.\n\n"
            ~ "This draws a black rectangle, surrounded by a green frame.\n\n"
            ~ "If green pixels are missing, filled rectangles draw too big (see fl_rectf).\n\n"
            ~ "If red pixels are showing, filled rectangles are drawn too small.");
        b += 24;
        t = new Box(a, b, 18, 18, "2");
        t.box(Boxtype.roundedBox); t.color(yellow);
        t.tooltip(
            "Testing rectangle frame alignment.\n\n"
            ~ "This draws a black frame, surrounded on the inside and outside by a green frame.\n\n"
            ~ "If green pixels are missing or red pixels are showing, rectangular frame drawing schould be adjusted (see fl_rect).\n\n"
            ~ "If red pixels show in the corners of the frame in hidpi mode, line endings should be adjusted.");
        b += 24;
        t = new Box(a, b, 18, 18, "3");
        t.box(Boxtype.roundedBox); t.color(yellow);
        t.tooltip(
            "Testing scaled frame alignment.\n\n"
            ~ "This draws a 3 units wide black frame, surrounded on the inside and outside by a green frame.\n\n"
            ~ "If green pixels are missing or red pixels are showing, line width schould be adjusted (see lineStyle).\n\n"
            ~ "If red pixels show in the corners of the frame in hidpi mode, line endings should be adjusted.");
        b += 24;
        t = new Box(a, b, 18, 18, "4");
        t.box(Boxtype.roundedBox); t.color(yellow);
        t.tooltip(
            "Testing fl_xyline.\n\n"
            ~ "This draws 3 versions of fl_xyline surronded with a green outline.\n\n"
            ~ "If green pixels are missing or red pixels are showing, fl_xyline must be adjusted.");
        b += 48;
        t = new Box(a, b, 18, 18, "5");
        t.box(Boxtype.roundedBox); t.color(yellow);
        t.tooltip(
            "Testing fl_yxline.\n\n"
            ~ "This draws 3 versions of fl_yxline surronded with a green outline.\n\n"
            ~ "If green pixels are missing or red pixels are showing, fl_yxline must be adjusted.");
        b += 48;
        t = new Box(a, b, 18, 18, "6");
        t.box(Boxtype.roundedBox); t.color(yellow);
        t.tooltip(
            "Testing fl_line(int...).\n\n"
            ~ "This draws 2 lines at differnet widths, and one connected line.\n\n"
            ~ "Green and red pixels mark the beginning and end of single lines."
            ~ "The line caps should be flat, the joints should be of type \"miter\".");

        a = x + 16 + 250; b = y + 34;
        t = new Box(a, b - 24, 80, 18, "OpenGL");
        t.alignment(alignLeft | alignInside);

        new UtGlRectTest(a + 31, b - 1, 200, 200);

        t = new Box(a, b, 26, 18, "1a");
        t.box(Boxtype.roundedBox); t.color(yellow);
        t.tooltip(
            "Testing filled rectangle alignment.\n\n"
            ~ "This draws a black rectangle, surrounded by a green frame.\n\n"
            ~ "If green pixels are missing, filled rectangles draw too big (see fl_rectf).\n\n"
            ~ "If red pixels are showing, filled rectangles are drawn too small.");

        b += 24;
        t = new Box(a, b, 26, 18, "2a");
        t.box(Boxtype.roundedBox); t.color(yellow);
        t.tooltip(
            "Testing rectangle frame alignment.\n\n"
            ~ "This draws a black frame, surrounded on the inside and outside by a green frame.\n\n"
            ~ "If green pixels are missing or red pixels are showing, rectangular frame drawing schould be adjusted (see fl_rect).\n\n"
            ~ "If red pixels show in the corners of the frame in hidpi mode, line endings should be adjusted.");

        b += 24;
        t = new Box(a, b, 26, 18, "3a");
        t.box(Boxtype.roundedBox); t.color(yellow);
        t.tooltip(
            "Testing scaled frame alignment.\n\n"
            ~ "This draws a 3 units wide black frame, surrounded on the inside and outside by a green frame.\n\n"
            ~ "If green pixels are missing or red pixels are showing, line width schould be adjusted (see lineStyle).\n\n"
            ~ "If red pixels show in the corners of the frame in hidpi mode, line endings should be adjusted.");
        b += 24;
        t = new Box(a, b, 26, 18, "4a");
        t.box(Boxtype.roundedBox); t.color(yellow);
        t.tooltip(
            "Testing fl_xyline.\n\n"
            ~ "This draws 3 versions of fl_xyline surronded with a green outline.\n\n"
            ~ "If green pixels are missing or red pixels are showing, fl_xyline must be adjusted.");
        b += 48;
        t = new Box(a, b, 26, 18, "5a");
        t.box(Boxtype.roundedBox); t.color(yellow);
        t.tooltip(
            "Testing fl_yxline.\n\n"
            ~ "This draws 3 versions of fl_yxline surronded with a green outline.\n\n"
            ~ "If green pixels are missing or red pixels are showing, fl_yxline must be adjusted.");
        b += 48;
        t = new Box(a, b, 26, 18, "6a");
        t.box(Boxtype.roundedBox); t.color(yellow);
        t.tooltip(
            "Testing fl_line(int...).\n\n"
            ~ "This draws 2 lines at differnet widths, and one connected line.\n\n"
            ~ "Green and red pixels mark the beginning and end of single lines."
            ~ "The line caps should be flat, the joints should be of type \"miter\".");

        t = new Box(x + w - 1, y + h - 1, 1, 1);
        resizable(t);
    }
}

static this()
{
    new UnitTest(UT_TEST_FAST_SHAPES, "Fast Shapes", () => UtRectTest.create());
}
