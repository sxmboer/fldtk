// D transliteration of FLTK's test/unittest_viewport.cxx (~/Repositories/fltk).
// Part of the samples/ contract -- see samples/README.md. One tab of the
// "unittests" bundle; see samples/test/unittests.d for the registry
// (including `mainwin`, whose testAlignment() this tab drives).
// Check: ./samples/build.sh unittests
module unittest_viewport;

import fl;
import unittests;

//
//------- test viewport clipping ----------
//
class UtViewportTest : Box
{
    static Widget create()
    {
        return new UtViewportTest(UT_TESTAREA_X, UT_TESTAREA_Y, UT_TESTAREA_W, UT_TESTAREA_H);
    }

    this(int x, int y, int w, int h)
    {
        super(x, y, w, h);
        label("Testing Viewport Alignment\n\n"
            ~ "Only green lines should be visible.\n"
            ~ "If red lines are visible in the corners of this window,\n"
            ~ "your viewport alignment and clipping is off.\n"
            ~ "If there is a space between the green lines and the window border,\n"
            ~ "the viewport is off, but some clipping may be working.\n"
            ~ "Also, your window size may be off to begin with.");
        alignment(alignInside | alignCenter | alignWrap);
        box(Boxtype.borderBox);
    }

    override void show()
    {
        super.show();
        mainwin.testAlignment(1);
    }

    override void hide()
    {
        super.hide();
        mainwin.testAlignment(0);
    }
}

static this()
{
    new UnitTest(UT_TEST_VIEWPORT, "Viewport Test", () => UtViewportTest.create());
}
