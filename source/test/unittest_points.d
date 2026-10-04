// D transliteration of FLTK's test/unittest_points.cxx (~/Repositories/fltk).
// Part of the samples/ contract -- see samples/README.md. One tab of the
// "unittests" bundle; see samples/test/unittests.d for the registry.
// Check: ./samples/build.sh unittests
module unittest_points;

import fl;
import unittests;

//
//------- test the point drawing capabilities of this implementation ----------
//

class UtNativePointTest : Window
{
    this(int x, int y, int w, int h)
    {
        super(x, y, w, h);
        end();
    }

    override void draw()
    {
        fl_color(white);
        fl_rectf(0, 0, 10, 10);
        fl_color(black);
        for (int i = 0; i < 10; i++)
        {
            point(i, 0);
            point(i, 9);
        }
        for (int i = 0; i < 10; i++)
        {
            point(0, i);
            point(9, i);
        }
    }
}

class UtGlPointTest : GlWindow
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

        int a = -24, b = 5 - 9;
        // Test 1a: pixel size
        fl_color(white); fl_rectf(a + 24, b + 9 - 5, 10, 10);
        fl_color(black);
        for (int i = 0; i < 8; i++)
            for (int j = 0; j < 8; j++)
                if ((i + j) & 1)
                    point(a + i + 24 + 1, b + j + 9 - 5 + 1);
        // Test 2a: pixel color
        static immutable Color[3] lut = [red, green, blue];
        for (int n = 0; n < 3; n++)
        {
            int yy = b + 9 - 5 + 24 + 16 * n;
            fl_color(white); fl_rectf(a + 24, yy, 10, 10);
            fl_color(lut[n]);
            for (int i = 0; i < 8; i++)
                for (int j = 0; j < 8; j++)
                    point(a + i + 24 + 1, yy + j + 1);
        }
        // Test 3a: pixel alignment inside windows (drawing happens in PointTestWin)
        int xx = a + 24, yy = b + 2 * 24 + 2 * 16 + 9 - 5;
        fl_color(red);
        for (int i = 0; i < 10; i++)
        {
            point(xx - 1, yy + i);
            point(xx + 10, yy + i);
        }
        fl_color(black);
        for (int i = 0; i < 10; i++)
        {
            point(xx + i, yy);
            point(xx + i, yy + 9);
        }
        for (int i = 0; i < 10; i++)
        {
            point(xx, yy + i);
            point(xx + 9, yy + i);
        }
        fl_color(white);
        for (int i = 0; i < 8; i++)
            for (int j = 0; j < 8; j++)
                point(xx + i + 1, yy + j + 1);
        // Test 4a: check pixel clipping
        xx = a + 24; yy = b + 3 * 24 + 2 * 16 + 9 - 5;
        pushClip(xx + 1, yy + 1, 9, 9);
        fl_color(red);
        for (int i = 0; i < 10; i++)
        {
            point(xx + i, yy);
            point(xx + i, yy + 9);
        }
        for (int i = 0; i < 10; i++)
        {
            point(xx, yy + i);
            point(xx + 9, yy + i);
        }
        fl_color(black);
        for (int i = 1; i < 9; i++)
        {
            point(xx + i, yy + 1);
            point(xx + i, yy + 8);
        }
        for (int i = 1; i < 9; i++)
        {
            point(xx + 1, yy + i);
            point(xx + 8, yy + i);
        }
        fl_color(white);
        for (int i = 1; i < 7; i++)
            for (int j = 1; j < 7; j++)
                point(xx + i + 1, yy + j + 1);
        popClip();

        drawEnd();
    }
}

//
//------- test the fl_point call ----------
//
class UtPointTest : FlGroup
{
    private UtNativePointTest alignTestWin;
    private UtGlPointTest glTestWin;

    static Widget create()
    {
        return new UtPointTest(UT_TESTAREA_X, UT_TESTAREA_Y, UT_TESTAREA_W, UT_TESTAREA_H);
        // 520x365, resizable
    }

    this(int x, int y, int w, int h)
    {
        super(x, y, w, h);
        label("Testing the point call.");
        alignment(alignInside | alignBottom | alignLeft | alignWrap);
        box(Boxtype.borderBox);

        int a = x + 16, b = y + 34;
        Box t = new Box(a, b - 24, 80, 18, "native");
        t.alignment(alignLeft | alignInside);

        t = new Box(a, b, 18, 18, "1");
        t.box(Boxtype.roundedBox); t.color(yellow);
        t.tooltip(
            "Testing pixel size and antialiasing.\n\n"
            ~ "This draws a checker board of black points on a white background.\n\n"
            ~ "Black and white points should be the same size of one unit (1 pixel in regular mode, 2x2 pixels in hidpi mode)."
            ~ "If black points are smaller than white in hidpi mode, point size must be increased.\n\n"
            ~ "Points should not be blurry. Antialiasing should be switched of and the point coordinates should be centered on the pixel(s).\n\n"
            ~ "If parts of the white border are missing, the size of fl_rect should be adjusted.");

        t = new Box(a, b + 24, 18, 18, "2");
        t.box(Boxtype.roundedBox); t.color(yellow);
        t.tooltip(
            "Testing pixels color.\n\n"
            ~ "This draws three squares in red, green, and blue.\n\n"
            ~ "If the order of colors is different, the byte order when writing into the pixel buffer should be fixed.");

        t = new Box(a, b + 2 * 24 + 2 * 16, 18, 18, "3");
        t.box(Boxtype.roundedBox); t.color(yellow);
        t.tooltip(
            "Testing pixels alignment in windows.\n\n"
            ~ "This draws a black frame around a white square.\n\n"
            ~ "If parts of the black frame are clipped by the window and not visible, pixel offsets must be adjusted.");

        alignTestWin = new UtNativePointTest(a + 24, b + 2 * 24 + 2 * 16 + 9 - 5, 10, 10);

        t = new Box(a, b + 3 * 24 + 2 * 16, 18, 18, "4");
        t.box(Boxtype.roundedBox); t.color(yellow);
        t.tooltip(
            "Testing pixels clipping.\n\n"
            ~ "This draws a black frame around a white square.\n\n"
            ~ "If red pixels are visible or black pixels are missing, graphics clipping is misaligned.");

        a += 100;
        t = new Box(a, b - 24, 80, 18, "OpenGL");
        t.alignment(alignLeft | alignInside);

        t = new Box(a, b, 26, 18, "1a");
        t.box(Boxtype.roundedBox); t.color(yellow);
        t.tooltip(
            "Testing pixel size and antialiasing.\n\n"
            ~ "This draws a checker board of black points on a white background.\n\n"
            ~ "Black and white points should be the same size of one unit (1 pixel in regular mode, 2x2 pixels in hidpi mode)."
            ~ "If black points are smaller than white in hidpi mode, point size must be increased.\n\n"
            ~ "Points should not be blurry. Antialiasing should be switched of and the point coordinates should be centered on the pixel(s).\n\n"
            ~ "If parts of the white border are missing, the size of fl_rect should be adjusted.");

        t = new Box(a, b + 24, 26, 18, "2a");
        t.box(Boxtype.roundedBox); t.color(yellow);
        t.tooltip(
            "Testing pixels color.\n\n"
            ~ "This draws three squares in red, green, and blue.\n\n"
            ~ "If the order of colors is different, the color component order when writing into the pixel buffer should be fixed.");

        t = new Box(a, b + 2 * 24 + 2 * 16, 26, 18, "3a");
        t.box(Boxtype.roundedBox); t.color(yellow);
        t.tooltip(
            "Testing pixels alignment in windows.\n\n"
            ~ "This draws a black frame around a white square, extending to both sides.\n\n"
            ~ "If parts of the black frame are clipped by the window and not visible, pixel offsets must be adjusted horizontally.\n\n"
            ~ "If the horizontal lines are misaligned, vertical pixel offset should be adjusted.");

        t = new Box(a, b + 3 * 24 + 2 * 16, 26, 18, "4a");
        t.box(Boxtype.roundedBox); t.color(yellow);
        t.tooltip(
            "Testing pixels clipping.\n\n"
            ~ "This draws a black frame around a white square. The square is slightly smaller.\n\n"
            ~ "If red pixels are visible or black pixels are missing, graphics clipping is misaligned.");

        glTestWin = new UtGlPointTest(a + 24 + 8, b + 9 - 5, 10, 4 * 24 + 2 * 16);

        t = new Box(x + w - 1, y + h - 1, 1, 1);
        resizable(t);
    }

    override void draw()
    {
        super.draw();
        int a = x() + 16, b = y() + 34;
        // Test 1: pixel size
        fl_color(white); fl_rectf(a + 24, b + 9 - 5, 10, 10);
        fl_color(black);
        for (int i = 0; i < 8; i++)
            for (int j = 0; j < 8; j++)
                if ((i + j) & 1)
                    point(a + i + 24 + 1, b + j + 9 - 5 + 1);
        // Test 2: pixel color
        static immutable Color[3] lut = [red, green, blue];
        for (int n = 0; n < 3; n++)
        {
            int yy = b + 9 - 5 + 24 + 16 * n;
            fl_color(white); fl_rectf(a + 24, yy, 10, 10);
            fl_color(lut[n]);
            for (int i = 0; i < 8; i++)
                for (int j = 0; j < 8; j++)
                    point(a + i + 24 + 1, yy + j + 1);
        }
        // Test 3: pixel alignment inside windows (drawing happens in PointTestWin)
        // Test 4: check pixel clipping
        int xx = a + 24, yy = b + 3 * 24 + 2 * 16 + 9 - 5;
        pushClip(xx, yy, 10, 10);
        fl_color(red);
        for (int i = -1; i < 11; i++)
        {
            point(xx + i, yy - 1);
            point(xx + i, yy + 10);
        }
        for (int i = -1; i < 11; i++)
        {
            point(xx - 1, yy + i);
            point(xx + 10, yy + i);
        }
        fl_color(black);
        for (int i = 0; i < 10; i++)
        {
            point(xx + i, yy);
            point(xx + i, yy + 9);
        }
        for (int i = 0; i < 10; i++)
        {
            point(xx, yy + i);
            point(xx + 9, yy + i);
        }
        fl_color(white);
        for (int i = 0; i < 8; i++)
            for (int j = 0; j < 8; j++)
                point(xx + i + 1, yy + j + 1);
        popClip();
        // Test 3a: pixel alignment inside the OpenGL window
        xx = a + 24 + 108; yy = b + 2 * 24 + 2 * 16 + 9 - 5;
        fl_color(black);
        for (int i = -4; i < 14; i++)
        {
            point(xx + i, yy);
            point(xx + i, yy + 9);
        }
    }
}

static this()
{
    new UnitTest(UT_TEST_POINTS, "Drawing Points", () => UtPointTest.create());
}
