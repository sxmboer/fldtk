// D transliteration of FLTK's test/utf8.cxx (~/Repositories/fltk).
// Part of the samples/ contract -- see samples/README.md.
// Check: ./samples/build.sh utf8
import fl;
import std.string : fromStringz;
import std.conv : to, parse, ConvException;
import std.format : format;
import std.math : fabs;
import std.stdio : writeln, writef, writefln, stdout;

//
// Font chooser widget for the Fast Light Tool Kit(FLTK).
//

enum int defSize = 16; // default value for the font size picker

DoubleWindow fntChooserWin;
HoldBrowser fontobj;
HoldBrowser sizeobj;

ValueOutput fntCnt;
Button refreshBtn;
Button chooseBtn;
Output fixProp;
CheckButton ownFace;

int[][] sizes_;
int[] numsizes;
int pickedsize = defSize;
char[1000] label;

DoubleWindow mainWin;
Scroll thescroll;
Font extraFont;

int fontCount = 0;
int firstFree = 0;

// window callback: hide all windows if any window is closed
void cbHideAll(Widget)
{
    fl.hideAllWindows();
}

/*
 Class for displaying sample fonts.
 */
class FontDisplay : Widget
{
    int font, size;

    this(Boxtype b, int x, int y, int w, int h, string l = null)
    {
        super(x, y, w, h, l);
        box(b);
        font = 0;
        size = defSize;
    }

    override void draw()
    {
        drawBox();
        fl_font(cast(Font) font, size);
        fl_color(black);
        fl_draw(label(), x() + 3, y() + 3, w() - 6, h() - 6, alignment());
    }

    // test_fixed_pitch() measures two strings and returns:
    //  1: fixed font, measurements match exactly
    //  2: nearly fixed font, measurements are within 5%
    //  0: proportional font
    int testFixedPitch()
    {
        int w1 = 0, w2 = 0;
        int h1 = 0, h2 = 0;

        fl_font(cast(Font) font, size);

        fl_measure("MHMHWWMHMHMHM###WWX__--HUW", w1, h1);
        fl_measure("iiiiiiiiiiiiiiiiiiiiiiiiii", w2, h2);

        if (w1 == w2)
            return 1; // exact match - fixed pitch

        // Is the font "nearly" fixed pitch? If it is within 5%, say it is...
        double f1 = cast(double) w1;
        double f2 = cast(double) w2;
        double delta = fabs(f1 - f2) * 20.0;
        if (delta <= f1)
            return 2; // nearly fixed pitch...
        return 0; // NOT fixed pitch
    }
}

FontDisplay textobj;

void sizeCb(Widget)
{
    int sizeIdx = sizeobj.value();

    if (!sizeIdx)
        return;

    const(char)[] c = sizeobj.text(sizeIdx);

    size_t ci = 0;
    while (ci < c.length && (c[ci] < '0' || c[ci] > '9'))
        ci++; // find the first numeric char
    // If no digit was found at all, c[ci..$] is empty -- to!int() throws
    // on that instead of FLTK's atoi(), which just returns 0.
    try
        pickedsize = to!int(c[ci .. $]); // convert the number string to a value
    catch (ConvException)
        pickedsize = 0;

    // Now set the font view to the selected size and redraw it.
    textobj.size = pickedsize;
    textobj.redraw();
}

void fontCb(Widget)
{
    int fontIdx = fontobj.value() + firstFree;

    if (!fontIdx)
        return;
    fontIdx--;

    textobj.font = fontIdx;
    sizeobj.clear();

    int sizeCount = numsizes[fontIdx - firstFree];
    int[] sizeArray = sizes_[fontIdx - firstFree];
    if (!sizeCount)
    {
        // no preferred sizes - probably TT fonts etc...
    }
    else if (sizeArray[0] == 0)
    {
        // many sizes, probably a scaleable font with preferred sizes
        int j = 1;
        for (int i = 1; i <= 64 || i < sizeArray[sizeCount - 1]; i++)
        {
            string buf;
            if (j < sizeCount && i == sizeArray[j])
            {
                buf = format("@b%d", i);
                j++;
            }
            else
            {
                buf = format("%d", i);
            }
            sizeobj.add(buf);
        }
        sizeobj.value(pickedsize);
    }
    else
    {
        // some sizes, probably a font with a few fixed sizes available
        int w = 0;
        for (int i = 0; i < sizeCount; i++)
        {
            // find the nearest available size to the current picked size
            if (sizeArray[i] <= pickedsize)
                w = i;

            string buf = format("@b%d", sizeArray[i]);
            sizeobj.add(buf);
        }
        sizeobj.value(w + 1);
    }
    sizeCb(sizeobj); // force selection of nearest valid size, then redraw

    // Now check to see if the font looks like a fixed pitch font or not...
    int looksFixed = textobj.testFixedPitch();
    switch (looksFixed)
    {
    case 1:
        fixProp.value("fixed");
        break;
    case 2:
        fixProp.value("near");
        break;
    default:
        fixProp.value("prop");
        break;
    }
}

void chooseCb(Widget)
{
    int fontIdx = fontobj.value() + firstFree;
    if (!fontIdx)
    {
        writeln("No font chosen");
    }
    else
    {
        int fontType;
        fontIdx -= 1;
        string name = fl.getFontName(cast(Font) fontIdx, fontType);
        writefln("idx %d\nUser name :%s:", fontIdx, name);
        writefln("FLTK name :%s:", fl.getFont(cast(Font) fontIdx));

        fl.setFont(extraFont, cast(Font) fontIdx);
        //          fl.setFont(extraFont, fl.getFont(cast(Font) fontIdx));
    }

    int sizeIdx = sizeobj.value();
    if (!sizeIdx)
    {
        writeln("No size selected");
    }
    else
    {
        const(char)[] c = sizeobj.text(sizeIdx);
        size_t ci = 0;
        while (ci < c.length && (c[ci] < '0' || c[ci] > '9'))
            ci++; // find the first numeric char
        int pickedsize_;
        try
            pickedsize_ = to!int(c[ci .. $]); // convert the number string to a value
        catch (ConvException)
            pickedsize_ = 0;

        writefln("size %d\n", pickedsize_);
    }

    stdout.flush();
    mainWin.redraw();
}

void refreshCb(Widget)
{
    mainWin.redraw();
}

void ownFaceCb(Widget)
{
    int fontIdx;
    int cursorRestore = 0;
    static int iWas = -1; // used to keep track of where we were in the list...

    if (iWas < 0)
    { // not been here before
        iWas = 1;
    }
    else
    {
        iWas = fontobj.topline(); // record which was the topmost visible line
        fontobj.clear();
        // Populating the font widget can be slower than an old dog with three legs
        // on a bad day, show a wait cursor
        fntChooserWin.cursor(Cursor.wait);
        cursorRestore = 1;
    }

    // Populate the font list with the names of the fonts found
    for (fontIdx = firstFree; fontIdx < fontCount; fontIdx++)
    {
        int fontType;
        string name = fl.getFontName(cast(Font) fontIdx, fontType);
        string buffer;

        if (ownFace.value() == 0)
        {
            // if the font is BOLD, set the bold attribute in the list
            if (fontType & bold)
                buffer ~= "@b";
            if (fontType & italic) //  ditto for italic fonts
                buffer ~= "@i";
            // Suppress subsequent formatting - some MS fonts have '@' in their name
            buffer ~= "@.";
            buffer ~= name;
        }
        else
        {
            // Show font in its own face
            // this is neat, but really slow on some systems:
            // uses each font to display its own name
            buffer = format("@F%d@.%s", fontIdx, name);
        }
        fontobj.add(buffer);
    }
    // now put the browser position back the way it was... more or less
    fontobj.topline(iWas);
    // restore the cursor
    if (cursorRestore)
        fntChooserWin.cursor(Cursor.default_);
}

void createFontWidget()
{
    // Create the font sample label
    string lbl = "Font Sample\n";
    int n = 0;
    for (uint c = ' ' + 1; c < 127; c++)
    {
        if (!(c & 0x1f))
            lbl ~= '\n';
        if (c == '@')
            lbl ~= '@';
        lbl ~= cast(char) c;
    }
    lbl ~= '\n';
    for (uint c = 0xA1; c < 0x600; c += 9)
    {
        if (!(++n & 0x1f))
            lbl ~= '\n';
        char[6] enc;
        int elen = utf8Encode(c, enc[]);
        lbl ~= enc[0 .. elen];
    }
    label[0 .. lbl.length] = lbl;

    // Create the window layout
    fntChooserWin = new DoubleWindow(380, 420, "Font Selector");
    {
        auto tile = new Tile(0, 0, 380, 420);
        {
            auto textgroup = new FlGroup(0, 0, 380, 105);
            {
                textobj = new FontDisplay(Boxtype.engravedBox, 10, 10, 360, 90, lbl);
                textobj.alignment(alignTop | alignLeft | alignInside | alignClip);
                textobj.color(cast(Color) 53, cast(Color) 3);

                textgroup.box(Boxtype.flatBox);
                textgroup.resizable(textobj);
                textgroup.end();
            }
            auto fontgroup = new FlGroup(0, 105, 380, 315);
            {
                fontobj = new HoldBrowser(10, 110, 290, 270);
                fontobj.box(Boxtype.engravedBox);
                fontobj.color(cast(Color) 53, cast(Color) 3);
                fontobj.callback((w) { fontCb(w); });
                fntChooserWin.resizable(fontobj);

                sizeobj = new HoldBrowser(310, 110, 60, 270);
                sizeobj.box(Boxtype.engravedBox);
                sizeobj.color(cast(Color) 53, cast(Color) 3);
                sizeobj.callback((w) { sizeCb(w); });

                // Create the status bar
                auto statBar = new FlGroup(10, 385, 380, 30);
                {
                    fntCnt = new ValueOutput(10, 390, 40, 20);
                    fntCnt.label("fonts");
                    fntCnt.alignment(alignRight);

                    fixProp = new Output(100, 390, 40, 20);
                    fixProp.color(backgroundColor);
                    fixProp.value("prop");
                    fixProp.clearVisibleFocus();

                    ownFace = new CheckButton(150, 390, 40, 20, "Self");
                    ownFace.value(0);
                    ownFace.type(toggleButton);
                    ownFace.clearVisibleFocus();
                    ownFace.callback((w) { ownFaceCb(w); });
                    ownFace.tooltip("Display font names in their own face");

                    auto dummy = new Box(220, 390, 1, 1);

                    chooseBtn = new Button(240, 385, 60, 30);
                    chooseBtn.label("Select");
                    chooseBtn.callback((w) { chooseCb(w); });

                    refreshBtn = new Button(310, 385, 60, 30);
                    refreshBtn.label("Refresh");
                    refreshBtn.callback((w) { refreshCb(w); });

                    statBar.resizable(dummy);
                    statBar.end();
                }

                fontgroup.box(Boxtype.flatBox);
                fontgroup.resizable(fontobj);
                fontgroup.end();
            }
            tile.end();
        }
        fntChooserWin.resizable(tile);
        fntChooserWin.end();
        fntChooserWin.callback((w) { cbHideAll(w); });
    }
}

int makeFontChooser()
{
    int fontIdx;

    // create the widget frame
    createFontWidget();

    // Load the system's available fonts
    version (linux)
    {
        // ask for everything that claims to be iso10646 compatible
        fontCount = fl.setFonts("-*-*-*-*-*-*-*-*-*-*-*-*-iso10646-1");
    }
    else
    {
        // ask for everything
        fontCount = fl.setFonts("*");
    }

    // allocate space for the sizes and numsizes array, now we know how many
    // entries it needs
    sizes_ = new int[][](fontCount);
    numsizes = new int[](fontCount);

    // Populate the font list with the names of the fonts found
    firstFree = freeFont;
    for (fontIdx = firstFree; fontIdx < fontCount; fontIdx++)
    {
        // Find out how many sizes are supported for each font face
        int[] sizeArray;
        int sizeCount = fl.getFontSizes(cast(Font) fontIdx, sizeArray);
        numsizes[fontIdx - firstFree] = sizeCount;
        // if the font has multiple sizes, populate the 2-D sizes array
        if (sizeCount)
        {
            sizes_[fontIdx - firstFree] = sizeArray.dup;
        }
    } // end of font list filling loop

    // Call this once to get the font browser loaded up
    ownFaceCb(null);

    fontobj.value(1);
    // optional hard-coded font for testing - do not use!
    //    fontobj.textfont(261);

    fontCb(fontobj);

    fntCnt.value(fontCount);

    return fontCount;
} // make_font_chooser

/* End of Font Chooser Widget code */

/* Unicode Font display widget */

void boxCb(Widget o)
{
    thescroll.box((cast(Button) o).value() ? Boxtype.downFrame : Boxtype.noBox);
    thescroll.redraw();
}

class RightLeftInput : Input
{
    this(int x, int y, int w, int h)
    {
        super(x, y, w, h);
    }

    override void draw()
    {
        if (type() == inputHidden)
            return;
        Boxtype b = box();
        if (damage() & damageAll)
            drawBox(b, color());
        drawtext(x() + fl.boxDx(b) + 3, y() + fl.boxDy(b), w() - fl.boxDw(b) - 6, h() - fl.boxDh(
                b));
    }

    override void drawtext(int X, int Y, int W, int H)
    {
        fl_color(textcolor());
        fl_font(textfont(), textsize());
        rtlDraw(value(), cast(int) value().length, X + W, Y + height() - descent());
    }
}

void i7Cb(Input i7, Input i8)
{
    string nb = "01234567";
    string ptr = i7.value();
    string buf;
    foreach (ch; ptr)
    {
        if (ch < ' ' || ch > 126)
        {
            buf ~= '\\';
            buf ~= nb[(ch >> 6) & 0x3];
            buf ~= nb[(ch >> 3) & 0x7];
            buf ~= nb[ch & 0x7];
        }
        else
        {
            if (ch == '\\')
                buf ~= '\\';
            buf ~= ch;
        }
    }
    i8.value(buf);
}

class UCharDropBox : Output
{
    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        tooltip("Drop one Unicode character here to decode it.\n"
                ~ "Only the first Unicode code point will be displayed.\n"
                ~ "Example: U+1F308 '\U0001F308' 0x{f0,9f,8c,88}");
    }

    override int handle(Event event)
    {
        switch (event)
        {
        case Event.dndEnter:
            return 1;
        case Event.dndDrag:
            return 1;
        case Event.dndRelease:
            return 1;
        case Event.paste:
            string t = fl.eventText();
            int n;
            uint ucode = t.length ? utf8DecodeAt(t, 0, n) : 0;
            if (n == 0)
            {
                value("");
                return 1;
            }
            // Example output length and format:
            // - length = 15: "U+0040 '@' 0x40"              -- UTF-8 encoding = 1 byte (ASCII)
            // - length = 30: "U+1F308 '\U0001F308' 0x{f0,9f,8c,88}" -- UTF-8 encoding = 4 bytes
            // - length = 31: "U+10FFFF '\U0010FFFF' 0x{f4,8f,bf,bf}" -- UTF-8 encoding = 4 bytes
            //
            int tl = utf8Len(t[0]);
            if (tl < 1)
                tl = 1;
            string buffer;
            // add Unicode code point: "U+0000" - "U+10FFFF" (4-6 hex digits)
            buffer ~= "U+";
            buffer ~= format("%04X", ucode);
            // add Unicode character in quotes
            buffer ~= " '";
            buffer ~= t[0 .. tl];
            buffer ~= "'";
            // add hex UTF-8 codes, format: "0xab" or "0x{de,ad,be,ef}"
            buffer ~= " 0x";
            if (n > 1)
                buffer ~= "{";
            for (int i = 0; i < n; i++)
            {
                if (i > 0)
                    buffer ~= ',';
                buffer ~= format("%02x", cast(ubyte) t[i]);
            }
            if (n > 1)
                buffer ~= "}";
            value(buffer);
            // writefln("size: %d", buffer.length); stdout.flush();
            return 1;
        default:
            break;
        }
        return super.handle(event);
    }
}

// Create the layout with widgets. Widget contents will be assigned later.

// constants for window layout
enum int iw_ = 280; // width of input widgets (left col.)
enum int sw_ = 470; // width of 'scroll' incl. scrollbars
enum int ww_ = iw_ + sw_ + 15; // total window width
enum int wh_ = 400; // minimal window height

Input[20] iw; // global widget pointers

// create the Fl_Scroll widget: right column of the main window:
// input: `off` = offset for unicode character display
// returns: the Fl_Scroll widget
Scroll makeScroll(int off)
{
    auto scroll = new Scroll(iw_ + 10, 0, sw_, wh_);

    int endList = 0x10000 / 16;
    if (off > 2)
    {
        if (off > 0x10F000) // would extend higher than Unicode range
            off = 0x10F000;
        endList = off + 0x10000;
        if (endList > 0x10FFFF) // would be greater than Unicode range
            endList = 0x10FFFF;
        off /= 16;
        endList /= 16;
    }

    for (int y = off; y < endList; y++)
    {
        // skip Unicode space reserved for surrogate pairs (U+D800 ... U+DFFF)
        if (y == 0xD80)
        { // U+D800
            auto bx = new Box(iw_ + 10, (y - off) * 25, 450, 25);
            bx.label("U+D800 … U+DFFF: reserved for UTF-16 surrogate pairs");
            bx.color(lighter(yellow));
            bx.box(Boxtype.downBox);
            bx.alignment(alignInside | alignLeft);
            y = 0xE00;
            off += 127;
            if (y >= endList)
                break;
        }
        int o = 0;
        char[6 * 16] buf; // utf8 text
        int i = 16 * y;
        for (int x = 0; x < 16; x++)
        {
            int len = utf8Encode(i, buf[o .. $]);
            if (len < 1)
                len = 1;
            o += len;
            i++;
        }
        string bu = format("0x%06X", y * 16);

        auto b = new Input(iw_ + 10, (y - off) * 25, 80, 25);
        b.textfont(courier);
        b.value(bu);

        b = new Input(iw_ + 90, (y - off) * 25, 370, 25);
        b.textfont(extraFont);
        b.value(buf[0 .. o].idup);
    }
    scroll.end();

    return scroll;
}

// create the "grid" layout of the main window:
// - left column: several widgets; subclasses of Fl_Input
// - right column: one Fl_Scroll; see above: make_scroll()
// input: `off` = offset for unicode character display; used in make_scroll()
// returns: the Fl_Grid widget
Grid makeGrid(int off)
{
    auto grid = new Grid(0, 0, ww_, wh_); // full window size
    grid.layout(10, 2, 5, 5); // rows, cols, margin, gap
    int[2] colWeights = [100, 0]; // resize only first column
    grid.colWeight(colWeights);

    // left column:

    iw[0] = new Input(0, 0, iw_, 25);
    grid.widget(iw[0], 0, 0);

    iw[1] = new Input(0, 0, iw_, 25);
    grid.widget(iw[1], 1, 0);

    iw[2] = new Input(0, 0, iw_, 25);
    grid.widget(iw[2], 2, 0);

    iw[3] = new Input(0, 0, iw_, 25);
    grid.widget(iw[3], 3, 0);
    iw[3].textfont(extraFont);

    iw[4] = new RightLeftInput(0, 0, iw_, 40);
    grid.widget(iw[4], 4, 0);
    iw[4].textfont(extraFont);
    iw[4].textsize(24);

    iw[5] = new RightLeftInput(0, 0, iw_, 40);
    grid.widget(iw[5], 5, 0);
    iw[5].textfont(extraFont);
    iw[5].textsize(24);

    iw[6] = new Input(0, 0, iw_, 25);
    grid.widget(iw[6], 6, 0);

    iw[7] = new Output(0, 0, iw_, 25);
    grid.widget(iw[7], 7, 0);

    iw[6].textsize(20);
    iw[6].when(whenChanged);
    iw[6].tooltip("Edit this field to decode non-ASCII characters\n(in octal bytes) and view the result below");
    iw[6].callback((w) { i7Cb(cast(Input) w, iw[7]); });

    iw[7].tooltip("Edit the field above to decode it\nand display the result in this field");

    iw[8] = new Output(0, 0, iw_, 40);
    grid.widget(iw[8], 8, 0);
    iw[8].textfont(extraFont);
    iw[8].textsize(30);

    iw[9] = new UCharDropBox(0, 0, iw_, 40);
    grid.widget(iw[9], 9, 0);
    iw[9].textsize(20);
    iw[9].value("drop box (see tooltip)");
    iw[9].color(lighter(green));

    // right column:

    thescroll = makeScroll(off);
    grid.widget(thescroll, 0, 1, 10, 1);

    return grid;
}

void main(string[] args)
{
    int off = 2;
    if (args.length > 1)
    {
        // strtoul(..., 0)'s auto base detection: "0x"/"0X" -> hex,
        // leading "0" -> octal, otherwise decimal.
        string s = args[1];
        uint base = 10;
        if (s.length > 1 && s[0] == '0' && (s[1] == 'x' || s[1] == 'X'))
        {
            s = s[2 .. $];
            base = 16;
        }
        else if (s.length > 1 && s[0] == '0')
            base = 8;

        try
            off = cast(int) parse!uint(s, base);
        catch (ConvException)
            off = 0;
    }

    makeFontChooser();
    extraFont = timesBoldItalic;

    /* setup the extra font */
    version (linux)
    {
        fl.setFont(extraFont, "-*-*-*-*-*-*-*-*-*-*-*-*-iso10646-1");
    }

    mainWin = new DoubleWindow(ww_, wh_, "Unicode Display");
    mainWin.begin();

    auto grid = makeGrid(off); // make a grid layout of widgets

    // populate the grid's contents

    string utf8Str = "@ABCabcàèéïßîöüã123 " // latin1 (ISO-8859-1)
        ~ "\U0001F604 " // emoji: grinning face with smiling eyes
        ~ "\U0001F1F8\U0001F1F2 " // emoji: "San Marino flag" encoded via emoji sequence
        ~ "\U0001F308 " // emoji: Rainbow
        ~ "."; // final '.'

    // convert UTF-8 string to lowercase/uppercase -- std.uni's real
    // Unicode case-folding tables are this port's stand-in for
    // fl_utf_tolower()/fl_utf_toupper() (FL/fl_utf8.h, not ported as
    // its own module): a cleaner D-native equivalent for the same
    // job, per CLAUDE.md's "check for a cleaner D stdlib alternative"
    // porting convention -- not a gap, a substitution.
    import std.uni : toLower, toUpper;
    string utf8Lc = utf8Str.toLower;

    // convert UTF-8 string to uppercase
    string utf8Uc = utf8Str.toUpper;

    iw[0].value(utf8Str);
    iw[1].value(utf8Lc);
    iw[2].value(utf8Uc);

    // accented text in two forms:
    //  - e\xCC\x82 = "e" + U+0303 = "e" + "Combining Circumflex Accent"
    // -   \xC3\xAA = U+00ea = "ê" = "Latin Small Letter E with Circumflex"

    string ltrTxt = "\\->ẽ=ê";
    iw[3].value(ltrTxt);

    // right-to-left text

    // fl_utf8fromwc() (FL/fl_utf8.h, wchar_t[] -> UTF-8) isn't ported
    // as its own function -- std.utf.toUTF8 does the identical job
    // directly against a D dstring, another "cleaner D stdlib
    // alternative" substitution (see the toLower/toUpper note above).
    import std.utf : toUTF8;

    dchar[] rToLTxt = [
        1610, 1608, 1606, 1604, 1603, 1608, 1583,
    ];
    string abuf = rToLTxt.toUTF8;

    iw[4].value(abuf);

    dchar[] rToLTxt1 = [
        1610, 0x20, 1608, 0x20, 1606, 0x20,
        1604, 0x20, 1603, 0x20, 1608, 0x20, 1583,
    ];
    abuf = rToLTxt1.toUTF8;

    iw[5].value(abuf);

    iw[6].value(abuf);

    // Greg Ercolano's Japanese test sequence
    // Note: in English: "Do nothing."

    iw[8].value("何も行る。");

    mainWin.end();
    mainWin.callback((w) { cbHideAll(w); });
    mainWin.resizable(grid);
    mainWin.sizeRange(ww_, wh_);

    // fl_set_status(0, 370, 100, 30);

    mainWin.show(args);

    fntChooserWin.show();

    fl.run();
}
