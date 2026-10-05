// D transliteration of FLTK's test/unittest_symbol.cxx.
// One tab of the
// "unittests" bundle; see source/test/unittests.d for the registry.
// Build: rdmd buildsamples.d test unittest_symbol
module unittest_symbol;

import fl;
import unittests;

//
// Test symbol rendering
//
class UtSymbolTest : Widget
{
    private void drawTextAndBoxes(string txt, int X, int Y)
    {
        int wo = 0, ho = 0;
        fl_measure(txt, wo, ho);
        // Draw fl_measure() rect
        fl_color(red);
        fl_rect(X, Y, wo, ho);
        // //////////////////////////////////////////////////////////////////////
        // NOTE: fl_text_extents() currently does not support multiline strings..
        //       until it does, let's leave this out, as we do multiline tests..
        // //////////////////////////////////////////////////////////////////////
        // // draw fl_text_extents() glyph bounding box
        // int dx,dy;
        // fl_text_extents(txt, dx, dy, wo, ho);
        // fl_color(FL_GREEN);
        // fl_rect(X+dx, Y+dy, wo, ho);
        //
        // Draw text with symbols enabled
        fl_color(black);
        fl_draw(txt, X, Y, 10, 10, alignInside | alignTop | alignLeft, null);
    }

    static Widget create()
    {
        return new UtSymbolTest(UT_TESTAREA_X, UT_TESTAREA_Y, UT_TESTAREA_W, UT_TESTAREA_H);
    }

    this(int x, int y, int w, int h)
    {
        super(x, y, w, h);
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
            int fsize = 25;
            fl_font(helvetica, fsize);
            int xx = x0 + 10;
            int yy = y0 + 10;
            drawTextAndBoxes("Text", xx, yy); yy += fsize + 10;                    // check no symbols
            drawTextAndBoxes("@->", xx, yy); yy += fsize + 10;                     // check symbol alone
            drawTextAndBoxes("@-> ", xx, yy); yy += fsize + 10;                    // check symbol with trailing space
            drawTextAndBoxes("@-> Rt Arrow", xx, yy); yy += fsize + 10;            // check symbol at left edge
            drawTextAndBoxes("Lt Arrow @<-", xx, yy); yy += fsize + 10;            // check symbol at right edge
            drawTextAndBoxes("@-> Rt/Lt @<-", xx, yy); yy += fsize + 10;           // check symbol at lt+rt edges
            drawTextAndBoxes("@@ At/Lt @<-", xx, yy); yy += fsize + 10;            // check @@ at left, symbol at right
            drawTextAndBoxes("@-> Lt/At @@", xx, yy); yy += fsize + 10;            // check symbol at left, @@ at right
            drawTextAndBoxes("@@ At/At @@", xx, yy); yy += fsize + 10;             // check @@ at left+right
            xx = x0 + 200;
            yy = y0 + 10;
            drawTextAndBoxes("Line1\nLine2", xx, yy); yy += (fsize + 10) * 2;                    // check 2 lines, no symbol
            drawTextAndBoxes("@-> Line1\nLine2 @<-", xx, yy); yy += (fsize + 10) * 2;            // check 2 lines, lt+rt symbols
            drawTextAndBoxes("@-> Line1\nLine2\nLine3 @<-", xx, yy); yy += (fsize + 10) * 3;     // check 3 lines, lt+rt symbols
            drawTextAndBoxes("@@@@", xx, yy); yy += fsize + 10;                                  // check abutting @@'s
            drawTextAndBoxes("@@ @@", xx, yy); yy += fsize + 10;                                 // check @@'s with space sep

            fl_font(helvetica, 14);
            fl_color(red);
            fl_draw("fl_measure bounding box in RED", x0 + 10, y0 + h0 - 20);
        }
        popClip(); // remove the local clip
    }
}

static this()
{
    new UnitTest(UT_TEST_SYBOL, "Symbol Text", () => UtSymbolTest.create());
}
