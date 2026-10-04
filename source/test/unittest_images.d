// D transliteration of FLTK's test/unittest_images.cxx (~/Repositories/fltk).
// Part of the samples/ contract -- see samples/README.md. One tab of the
// "unittests" bundle; see samples/test/unittests.d for the registry.
// Check: ./samples/build.sh unittests
//
// Note: currently (March 2010, FLTK) fl_draw_image() supports
// transparency with alpha channel only on Apple (Mac OS X), but
// Fl_RGB_Image->draw() supports transparency on all platforms!
module unittest_images;

import fl;
import unittests;

import core.stdc.stdlib : malloc, free;
import core.stdc.string : memset;

//
//------- test the image drawing capabilities of this implementation ----------
//

// Parameters for fine tuning for developers.
// Default values: CB=1, DX=0, IMG=1, LX=0, FLIPH=0

private int cb = 1;      // 1 to show the checker board background for alpha images, 0 otherwise
private int dx = 0;      // additional (undefined (0)) pixels per line, must be >= 0
                          // ignored (irrelevant), if LX == 0 (see below)
private int img = 1;     // 1 to use Fl_RGB_Image for drawing images with transparency,
                          // 0 to use fl_draw_image() instead.
private int lx = 0;      // 0 for default: ld() = 0, i.e. ld() defaults (internally) to w()*d()
                          // +1: ld() = (w() + DX) * d()
                          // -1 to flip image vertically: ld() = - ((w() + DX) * d())
private int flipH = 0;   // 1 = Flip image horizontally (only if IMG == 0)
                          // 0 = Draw image normal, w/o horizontal flipping

// ----------------------------------------------------------------------
//  Test scenario for fl_draw_image() with pos. and neg. d and ld args:
// ----------------------------------------------------------------------
//  (1) set img    =  0: normal, but w/o transparency: no checker board
//  (2) set lx     = -1: images flipped vertically
//  (3) set flip_h =  1: images flipped vertically and horizontally
//  (4) set lx     =  0: images flipped horizontally
//  (5) set flip_h =  0, IMG = 1: back to default (with transparency)
// ----------------------------------------------------------------------

class UtImageTest : FlGroup
{
    private static void buildImgs()
    {
        ubyte* dg, dga, drgb, drgba;
        dg = imgGray = imgGrayBase = cast(ubyte*) malloc((128 + dx) * 128 * 1);
        dga = imgGrayA = imgGrayABase = cast(ubyte*) malloc((128 + dx) * 128 * 2);
        drgb = imgRgb = imgRgbBase = cast(ubyte*) malloc((128 + dx) * 128 * 3);
        drgba = imgRgba = imgRgbaBase = cast(ubyte*) malloc((128 + dx) * 128 * 4);
        for (int y = 0; y < 128; y++)
        {
            for (int x = 0; x < 128; x++)
            {
                *drgba++ = *drgb++ = *dga++ = *dg++ = cast(ubyte)(y << 1);
                *drgba++ = *drgb++ = cast(ubyte)(x << 1);
                *drgba++ = *drgb++ = cast(ubyte)((127 - x) << 1);
                *drgba++ = *dga++ = cast(ubyte)(x + y);
            }
            if (dx > 0 && lx != 0)
            {
                memset(dg, 0, 1 * dx); dg += 1 * dx;
                memset(dga, 0, 2 * dx); dga += 2 * dx;
                memset(drgb, 0, 3 * dx); drgb += 3 * dx;
                memset(drgba, 0, 4 * dx); drgba += 4 * dx;
            }
        }
        if (lx < 0)
        {
            imgGray += 127 * (128 + dx);
            imgGrayA += 127 * (128 + dx) * 2;
            imgRgb += 127 * (128 + dx) * 3;
            imgRgba += 127 * (128 + dx) * 4;
        }
        if (flipH && !img)
        {
            imgGray += 127;
            imgGrayA += 127 * 2;
            imgRgb += 127 * 3;
            imgRgba += 127 * 4;
        }
        // RGBImage takes a bounds-checked D slice, not a raw pointer --
        // the lx<0/lx>0 cases above deliberately hand it a pointer
        // that's already offset into the malloc'd buffer (paired with
        // a negative/positive ld), so the slice length here is the
        // *original* malloc'd buffer size for that pointer, not
        // (w*h*d) relative to the offset pointer -- matching what the
        // C pointer itself is still valid to read via ld-based row
        // arithmetic in draw(), same as FLTK's raw pointer.
        iG = new RGBImage(imgGray[0 .. (128 + dx) * 128 * 1], 128, 128, 1, lx * (128 + dx));
        iGa = new RGBImage(imgGrayA[0 .. (128 + dx) * 128 * 2], 128, 128, 2, lx * (128 + dx) * 2);
        iRgb = new RGBImage(imgRgb[0 .. (128 + dx) * 128 * 3], 128, 128, 3, lx * (128 + dx) * 3);
        iRgba = new RGBImage(imgRgba[0 .. (128 + dx) * 128 * 4], 128, 128, 4, lx * (128 + dx) * 4);
    } // buildImgs method ends

    private void freeImages()
    {
        if (iRgba !is null) { destroy(iRgba); iRgba = null; }
        if (iRgb !is null) { destroy(iRgb); iRgb = null; }
        if (iGa !is null) { destroy(iGa); iGa = null; }
        if (iG !is null) { destroy(iG); iG = null; }
        if (imgRgbaBase !is null) { free(imgRgbaBase); imgRgbaBase = null; }
        if (imgRgbBase !is null) { free(imgRgbBase); imgRgbBase = null; }
        if (imgGrayABase !is null) { free(imgGrayABase); imgGrayABase = null; }
        if (imgGrayBase !is null) { free(imgGrayBase); imgGrayBase = null; }
    } // end of freeImages method

    private static void refreshImgsCb(Widget, UtImageTest it)
    {
        it.freeImages(); // release the previous images
        // determine the state for the next images
        cb = it.ckCB.value();
        img = it.ckIMG.value();
        flipH = it.ckFLIPH.value();
        // read the LX state radio buttons
        if (it.rbLXp1.value()) { lx = 1; }
        else if (it.rbLXm1.value()) { lx = -1; }
        else { lx = 0; }
        // construct the next images
        buildImgs();
        it.redraw();
    }

    static Widget create()
    {
        buildImgs();
        return new UtImageTest(UT_TESTAREA_X, UT_TESTAREA_Y, UT_TESTAREA_W, UT_TESTAREA_H);
    } // create method ends

    private static ubyte* imgGrayBase;
    private static ubyte* imgGrayABase;
    private static ubyte* imgRgbBase;
    private static ubyte* imgRgbaBase;
    private static ubyte* imgGray;
    private static ubyte* imgGrayA;
    private static ubyte* imgRgb;
    private static ubyte* imgRgba;
    private static RGBImage iG;
    private static RGBImage iGa;
    private static RGBImage iRgb;
    private static RGBImage iRgba;

    // control widgets
    private FlGroup ctrGrp;
    private CheckButton ckCB;
    private CheckButton ckIMG;
    private CheckButton ckFLIPH;
    private RadioButton rbLXm1;
    private RadioButton rbLX0;
    private RadioButton rbLXp1;
    private Button refresh;

    this(int x, int y, int w, int h)
    {
        super(x, y, w, h);
        label("Testing Image Drawing\n\n"
            ~ "This test renders four images, two of them with a checker board\n"
            ~ "visible through the graphics. Color and gray gradients should be\n"
            ~ "visible. This does not test any image formats such as JPEG.");
        alignment(alignInside | alignBottom | alignLeft | alignWrap);
        box(Boxtype.borderBox);
        int cw = 90;
        int ch = 200;
        int cx = x + w - cw - 5;
        int cy = y + 10;
        ctrGrp = new FlGroup(cx, cy, cw, ch);

        ckCB = new CheckButton(cx + 10, cy + 10, cw - 20, 30, "CB");
        ckCB.callback((wgt) { refreshImgsCb(wgt, this); });
        ckCB.value(cb != 0);
        ckCB.tooltip("1 to show the checker board background for alpha images,\n"
            ~ "0 otherwise");

        ckIMG = new CheckButton(cx + 10, cy + 40, cw - 20, 30, "IMG");
        ckIMG.callback((wgt) { refreshImgsCb(wgt, this); });
        ckIMG.value(img != 0);
        ckIMG.tooltip("1 to use RGBImage for drawing images with transparency,\n"
            ~ "0 to use drawImage() instead.");

        ckFLIPH = new CheckButton(cx + 10, cy + 70, cw - 20, 30, "FLIPH");
        ckFLIPH.callback((wgt) { refreshImgsCb(wgt, this); });
        ckFLIPH.value(flipH != 0);
        ckFLIPH.tooltip("1 = Flip image horizontally (only if IMG == 0)\n"
            ~ "0 = Draw image normal, w/o horizontal flipping");

        FlGroup rdGrp = new FlGroup(cx + 10, cy + 100, cw - 20, 90, "LX");

        rbLXp1 = new RadioButton(cx + 15, cy + 105, cw - 30, 20, "+1");
        rbLXp1.callback((wgt) { refreshImgsCb(wgt, this); });
        rbLX0 = new RadioButton(cx + 15, cy + 125, cw - 30, 20, "0");
        rbLX0.callback((wgt) { refreshImgsCb(wgt, this); });
        rbLX0.tooltip("0 for default: ld() = 0, i.e. ld() defaults (internally) to w()*d()\n"
            ~ "+1: ld() = (w() + DX) * d()\n"
            ~ "-1 to flip image vertically: ld() = - ((w() + DX) * d())");
        rbLXm1 = new RadioButton(cx + 15, cy + 145, cw - 30, 20, "-1");
        rbLXm1.callback((wgt) { refreshImgsCb(wgt, this); });
        rbLX0.value(true);

        rdGrp.box(Boxtype.borderBox);
        rdGrp.alignment(alignInside | alignBottom | alignCenter);
        rdGrp.end();

        ctrGrp.box(Boxtype.borderBox);
        ctrGrp.end();
        end(); // make sure this ImageTest group is closed
    } // constructor ends

    override void draw()
    {
        super.draw();

        // top left: RGB

        int xx = x() + 10, yy = y() + 10;
        fl_color(black); fl_rect(xx, yy, 130, 130);
        if (img)
        {
            iRgb.draw(xx + 1, yy + 1);
        }
        else
        {
            if (!flipH)
                drawImage(imgRgb, xx + 1, yy + 1, 128, 128, 3, lx * ((128 + dx) * 3));
            else
                drawImage(imgRgb, xx + 1, yy + 1, 128, 128, -3, lx * ((128 + dx) * 3));
        }
        fl_draw("RGB", xx + 134, yy + 64);

        // bottom left: RGBA

        xx = x() + 10; yy = y() + 10 + 134;
        fl_color(black); fl_rect(xx, yy, 130, 130);       // black frame
        fl_color(white); fl_rectf(xx + 1, yy + 1, 128, 128); // white background
        if (cb)
        { // checker board
            fl_color(black); fl_rectf(xx + 65, yy + 1, 64, 64);
            fl_color(black); fl_rectf(xx + 1, yy + 65, 64, 64);
        }
        if (img)
        {
            iRgba.draw(xx + 1, yy + 1);
        }
        else
        {
            if (!flipH)
                drawImage(imgRgba, xx + 1, yy + 1, 128, 128, 4, lx * ((128 + dx) * 4));
            else
                drawImage(imgRgba, xx + 1, yy + 1, 128, 128, -4, lx * ((128 + dx) * 4));
        }
        fl_color(black); fl_draw("RGBA", xx + 134, yy + 64);

        // top right: Gray

        xx = x() + 10 + 200; yy = y() + 10;
        fl_color(black); fl_rect(xx, yy, 130, 130);
        if (img)
        {
            iG.draw(xx + 1, yy + 1);
        }
        else
        {
            if (!flipH)
                drawImage(imgGray, xx + 1, yy + 1, 128, 128, 1, lx * ((128 + dx) * 1));
            else
                drawImage(imgGray, xx + 1, yy + 1, 128, 128, -1, lx * ((128 + dx) * 1));
        }
        fl_draw("Gray", xx + 134, yy + 64);

        // bottom right: Gray+Alpha

        xx = x() + 10 + 200; yy = y() + 10 + 134;
        fl_color(black); fl_rect(xx, yy, 130, 130);       // black frame
        fl_color(white); fl_rectf(xx + 1, yy + 1, 128, 128); // white background
        if (cb)
        { // checker board
            fl_color(black); fl_rectf(xx + 65, yy + 1, 64, 64);
            fl_color(black); fl_rectf(xx + 1, yy + 65, 64, 64);
        }
        if (img)
        {
            iGa.draw(xx + 1, yy + 1);
        }
        else
        {
            if (!flipH)
                drawImage(imgGrayA, xx + 1, yy + 1, 128, 128, 2, lx * ((128 + dx) * 2));
            else
                drawImage(imgGrayA, xx + 1, yy + 1, 128, 128, -2, lx * ((128 + dx) * 2));
        }
        fl_color(black); fl_draw("Gray+Alpha", xx + 134, yy + 64);
    } // draw method end
}

static this()
{
    new UnitTest(UT_TEST_IMAGES, "Drawing Images", () => UtImageTest.create());
}
