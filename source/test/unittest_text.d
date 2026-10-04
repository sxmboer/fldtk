// D transliteration of FLTK's test/unittest_text.cxx (~/Repositories/fltk).
// Part of the samples/ contract -- see samples/README.md. One tab of the
// "unittests" bundle; see samples/test/unittests.d for the registry.
// Check: ./samples/build.sh unittests
module unittest_text;

import fl;
import unittests;

//
// --- fl_text_extents() tests -----------------------------------------------
//
private void cbBaseBt(Widget bt)
{
    bt.parent().redraw();
}

class UtTextExtentsTest : FlGroup
{
    private CheckButton baseBt;

    private void drawTextAndBoxes(string txt, int X, int Y)
    {
        int wm = 0, hm = 0, wt = 0, ht = 0;
        int dx, dy;
        // measure text so we can draw the baseline first
        fl_measure(txt, wm, hm);
        textExtents(txt, dx, dy, wt, ht);
        // Draw a baseline before the boxes
        if (baseBt.value())
        {
            fl_color(blue);
            fl_line(X - 20, Y, X + wt + 20, Y);
        }
        // Then we draw the bounding boxes (fl_measure and fl_text_extents)
        // draw fl_measure() typographical bounding box
        int desc = descent();
        fl_color(red);
        fl_rect(X, Y - hm + desc, wm, hm);
        // draw fl_text_extents() glyph bounding box
        fl_color(green);
        fl_rect(X + dx, Y + dy, wt, ht);
        // Then we draw the text to show how it fits inside each of the two boxes
        fl_color(black);
        fl_draw(txt, X, Y);
    }

    static Widget create()
    {
        return new UtTextExtentsTest(UT_TESTAREA_X, UT_TESTAREA_Y, UT_TESTAREA_W, UT_TESTAREA_H);
    }

    this(int x, int y, int w, int h)
    {
        super(x, y, w, h);
        baseBt = new CheckButton(x + w - 150, 50, 130, 20, "Show Baseline");
        baseBt.box(Boxtype.flatBox);
        baseBt.downBox(Boxtype.downBox);
        baseBt.callback((w) { cbBaseBt(w); });

        Box dummy = new Box(x + w - 4, y + h - 4, 2, 2);
        resizable(dummy);
        end();
    }

    override void draw()
    {
        int x0 = x(); // origin is current window position for Fl_Box
        int y0 = y();
        int w0 = w();
        int h0 = h();
        pushClip(x0, y0, w0, h0); // reset local clipping
        {
            // set the background colour - slightly off-white to enhance the green bounding box
            fl_color(fl_gray_ramp(numGray - 3));
            fl_rectf(x0, y0, w0, h0);

            super.draw();

            fl_font(helvetica, 30);
            int xx = x0 + 55;
            int yy = y0 + 40;
            drawTextAndBoxes("!abcdeABCDE\"#A", xx, yy); yy += 50;     // mixed string
            drawTextAndBoxes("oacs", xx, yy); xx += 100;               // small glyphs
            drawTextAndBoxes("qjgIPT", xx, yy); yy += 50; xx -= 100;   // glyphs with descenders
            drawTextAndBoxes("````````", xx, yy); yy += 50;           // high small glyphs
            drawTextAndBoxes("--------", xx, yy); yy += 50;           // mid small glyphs
            drawTextAndBoxes("________", xx, yy); yy += 50;           // low small glyphs

            fl_font(helvetica, 14);
            fl_color(red);  fl_draw("fl_measure bounding box in RED", xx, yy); yy += 20;
            fl_color(green); fl_draw("textExtents bounding box in GREEN", xx, yy);
            fl_color(black);
            xx = x0 + 10; yy += 30;
            fl_draw("NOTE: On systems with text anti-aliasing (e.g. macOS Quartz)", xx, yy);
            int w0m = 0, h0m = 0; fl_measure("NOTE: ", w0m, h0m);
            xx += w0m; yy += h0m;
            fl_draw("text may leak slightly outside the textExtents()", xx, yy);
        }
        popClip(); // remove the local clip
    }
}

static this()
{
    new UnitTest(UT_TEST_TEXT, "Rendering Text", () => UtTextExtentsTest.create());
}
