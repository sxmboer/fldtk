// D transliteration of FLTK's test/unittest_scrollbarsize.cxx.
// One tab of the "unittests" bundle; see
// source/test/unittests.d for the registry.
// Build: rdmd buildsamples.d test unittest_scrollbarsize
module unittest_scrollbarsize;

import fl;
import unittests;

import std.string : format;

//
// Test new 1.3.x global vs. local scrollbar sizing
//
class UtTable : Table
{
    // Handle drawing table's cells
    //     Fl_Table calls this function to draw each visible cell in the
    //     table. It's up to us to use FLTK's drawing functions to draw
    //     the cells the way we want.
    override void drawCell(TableContext context, int ROW = 0, int COL = 0,
        int X = 0, int Y = 0, int W = 0, int H = 0)
    {
        switch (context)
        {
        case contextStartpage: // before page is drawn..
            fl_font(helvetica, 8); // set font for drawing operations
            return;
        case contextCell: // Draw data in cells
            string s = format("%c", cast(char)('A' + ROW + COL));
            pushClip(X, Y, W, H);
            // Draw cell bg
            fl_color(white); fl_rectf(X, Y, W, H);
            // Draw cell data
            fl_color(gray0); fl_draw(s, X, Y, W, H, alignCenter);
            // Draw box border
            fl_color(color()); fl_rect(X, Y, W, H);
            popClip();
            return;
        default:
            return;
        }
    }

public this(int X, int Y, int W, int H, string L = null)
    {
        super(X, Y, W, H, L);
        // Rows
        rows(13);           // how many rows
        rowHeightAll(10);   // default height of rows
        // Cols
        cols(13);           // how many columns
        colWidthAll(10);    // default width of columns
        end();              // end the Fl_Table group
    }
}

private immutable string[] phonetics = [
    "Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot",
    "Golf", "Hotel", "India", "Juliet", "Kilo", "Lima", "Mike",
    "November", "Oscar", "Papa", "Quebec", "Romeo", "Sierra", "Tango",
    "Uniform", "Victor", "Whiskey", "X-ray", "Yankee", "Zulu"
];

class UtScrollbarSizeTest : FlGroup
{
    private Browser browA, browB, browC;
    private Tree treeA, treeB, treeC;
    private UtTable tableA, tableB, tableC;
    private TextDisplay textA, textB, textC;
    private Terminal termA, termB, termC;

    private Browser makebrowser(int X, int Y, int W, int H, string L = null)
    {
        Browser b = new Browser(X, Y, W, H, L);
        b.type(multiBrowser);
        b.labelsize(10);
        b.textsize(10);
        b.alignment(alignTop);
        foreach (p; phonetics)
        {
            b.add(p);
            if (p[0] == 'C')
                b.add("Long entry will show h-bar");
        }
        return b;
    }

    private Tree maketree(int X, int Y, int W, int H, string L = null)
    {
        Tree b = new Tree(X, Y, W, H, L);
        b.labelsize(10);
        b.itemLabelsize(10);
        b.type(TreeSelect.selectMulti);
        b.alignment(alignTop);
        foreach (p; phonetics)
        {
            b.add(p);
            if (p[0] == 'C')
                b.add("Long entry will show h-bar");
        }
        return b;
    }

    private UtTable maketable(int X, int Y, int W, int H, string L = null)
    {
        UtTable mta = new UtTable(X, Y, W, H, L);
        mta.labelsize(10);
        mta.alignment(alignTop);
        mta.end();
        return mta;
    }

    private TextDisplay maketextdisplay(int X, int Y, int W, int H, string L = null)
    {
        TextDisplay dpy = new TextDisplay(X, Y, W, H, L);
        TextBuffer buf = new TextBuffer();
        dpy.labelsize(10);
        dpy.textsize(10);
        dpy.buffer(buf);
        foreach (p; phonetics)
        {
            buf.printf("%s\n", p);
            if (p[0] == 'C')
                buf.printf("Long entry will show h-bar\n");
        }
        return dpy;
    }

    private Terminal maketerm(int X, int Y, int W, int H, string L = null)
    {
        Terminal term = new Terminal(X, Y, W, H, L);
        term.labelsize(8);
        term.textsize(8);
        term.end();
        term.displayColumns(40); // force wider than normal to show hscroll
        term.printf("Long entry will show h-bar\n");
        return term;
    }

    private void slideCb2(ValueSlider in_)
    {
        string label = in_.label();
        int val = cast(int) in_.value();
        if (label == "A: Scroll Size")
        {
            browA.scrollbarSize(val);
            treeA.scrollbarSize(val);
            tableA.scrollbarSize(val);
            textA.scrollbarSize(val);
            termA.scrollbarSize(val);
        }
        else
        {
            fl.scrollbarSize(val);
        }
        in_.window().redraw();
    }

    static Widget create()
    {
        return new UtScrollbarSizeTest(UT_TESTAREA_X, UT_TESTAREA_Y, UT_TESTAREA_W, UT_TESTAREA_H);
    }

    // CTOR
    this(int X, int Y, int W, int H)
    {
        super(X, Y, W, H);
        begin();
        //      _____________    _______________
        //     |_____________|  |_______________|
        //                                                ---     -----  <-- tgrpy
        //       brow_a      brow_b      brow_c            v 14     ^
        //     ----------  ----------  ----------         ---       |    <-- browy
        //     |        |  |        |  |        |          ^ browh  |
        //     |        |  |        |  |        |          v        |
        //     ----------  ----------  ----------         ---     tgrph
        //                                                 ^        |
        //       tree_a      tree_b      tree_c            v 20     |
        //     ----------  ----------  ----------         ---       |    <-- treey
        //     |        |  |        |  |        |          ^ treeh  |
        //     |        |  |        |  |        |          v        |
        //     ----------  ----------  ----------         ---       |
        //                                                 ^        |
        //      table_a     table_b     table_c            v 20     |
        //     ----------  ----------  ----------         ---       |    <-- tabley
        //     |        |  |        |  |        |          ^ tableh |
        //     |        |  |        |  |        |          v        |
        //     ----------  ----------  ----------         ---       |
        //                                                 ^        |
        //      term_a      term_b      term_c             v 20     |
        //     ----------  ----------  ----------         ---       |    <-- termy
        //     |        |  |        |  |        |          ^ termh  |
        //     |        |  |        |  |        |          v        v
        //     ----------  ----------  ----------         ---     ------
        //  etc..
        int tgrpy = Y + 30;
        int tgrph = H - 30;
        int ysep = 20;                    // y separation between widgets
        int browy = tgrpy + 14;
        int browh = tgrph / 5 - 20;       // 5: number of widgets vertically
        int treey = browy + browh + ysep;
        int treeh = browh;
        int tabley = treey + treeh + ysep;
        int tableh = browh;
        int texty = tabley + tableh + ysep;
        int texth = browh;
        int termy = texty + texth + ysep;
        browA = makebrowser(X + 10, browy, 100, browh, "Browser A");
        browB = makebrowser(X + 120, browy, 100, browh, "Browser B");
        browC = makebrowser(X + 230, browy, 100, browh, "Browser C");
        treeA = maketree(X + 10, treey, 100, treeh, "Tree A");
        treeB = maketree(X + 120, treey, 100, treeh, "Tree B");
        treeC = maketree(X + 230, treey, 100, treeh, "Tree C");
        tableA = maketable(X + 10, tabley, 100, tableh, "Table A");
        tableB = maketable(X + 120, tabley, 100, tableh, "Table B");
        tableC = maketable(X + 230, tabley, 100, tableh, "Table C");
        textA = maketextdisplay(X + 10, texty, 100, texth, "Text Display A");
        textB = maketextdisplay(X + 120, texty, 100, texth, "Text Display B");
        textC = maketextdisplay(X + 230, texty, 100, texth, "Text Display C");
        termA = maketerm(X + 10, termy, 100, texth, "Term A");
        termB = maketerm(X + 120, termy, 100, texth, "Term B");
        termC = maketerm(X + 230, termy, 100, texth, "Term C");
        ValueSlider slideGlob = new ValueSlider(X + 100, Y, 100, 18, "Global Scroll Size");
        slideGlob.value(16);
        slideGlob.type(horizontalType);
        slideGlob.alignment(alignLeft);
        slideGlob.range(0.0, 30.0);
        slideGlob.step(1.0);
        slideGlob.callback((w) { slideCb2(cast(ValueSlider) w); });
        slideGlob.labelsize(12);
        ValueSlider slideBrowa = new ValueSlider(X + 350, Y, 100, 18, "A: Scroll Size");
        slideBrowa.value(0);
        slideBrowa.type(horizontalType);
        slideBrowa.alignment(alignLeft);
        slideBrowa.range(0.0, 30.0);
        slideBrowa.step(1.0);
        slideBrowa.callback((w) { slideCb2(cast(ValueSlider) w); });
        slideBrowa.labelsize(12);
        int msgboxX = browC.x() + browC.w() + 20;
        int msgboxY = tgrpy;
        int msgboxW = W - (msgboxX - X);
        int msgboxH = tgrph;
        Box msgbox = new Box(msgboxX, msgboxY, msgboxW, msgboxH);
        msgbox.label("\nVerify global scrollbar sizing and per-widget scrollbar sizing. "
            ~ "Scrollbar's size should change interactively as size sliders are changed. "
            ~ "Changing 'Global Scroll Size' should affect all scrollbars AS LONG AS the "
            ~ "'A: Scroll Size' slider is 0. Otherwise its value takes precedence "
            ~ "for all the 'A' group widgets.");
        msgbox.labelsize(12);
        msgbox.alignment(alignInside | alignCenter | alignLeft | alignWrap);
        msgbox.box(Boxtype.flatBox);
        msgbox.color(cast(Color) 53); // 90% gray
        end();
    }
}

static this()
{
    new UnitTest(UT_TEST_SCROLLBARSIZE, "Scrollbar Size", () => UtScrollbarSizeTest.create());
}
