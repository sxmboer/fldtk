// D transliteration of FLTK's test/resize-example3b.cxx (~/Repositories/fltk),
// linked with resize-arrows.cxx (see resize_arrows.d).
// Part of the samples/ contract -- see samples/README.md.
// Check: ./samples/build.sh resize-example3b
import fl;
import resize_arrows;

// resize dialog and arrow dimensions
int TLx = 35, TRx = 270, TGx = 470, TLw = 200, TGw = 120, TAw = 35;
int TLy = 35, BLy = 160, LGy = 250, TLh = 90, LGh = 90, LAh = 35;

// window dimensions
int Ww = 590, Wh = 340;

DoubleWindow window;

class ResizeDialog : FlGroup
{
    Box m_icon;
    Box m_message;
    Button m_button;

    this(int X, int Y, int W, int H, string T = null)
    {
        super(X, Y, W, H, T);
        this.alignment(alignTopLeft);
        this.box(Boxtype.upBox);

        m_icon = new Box(X + 10, Y + 10, 30, 30, "!");
        m_icon.box(Boxtype.downBox);
        m_message = new Box(X + 50, Y + 10, 140, 30, "Out of Memory");
        m_message.box(Boxtype.downBox);
        m_message.color(yellow);
        m_button = new Button(X + 140, Y + 50, 50, 30, "Darn!");

        this.end();
        this.resizable(m_message);
    }
}

class Resizables : FlGroup
{
    ResizeDialog TL, TR, BL, BR; // topleft, topright, bottomleft, bottomright
    Harrow LA, RA;               // left arrow, right arrow
    Varrow TA, BA;               // top arrow, bottom arrow

    this(int X, int Y, int W, int H, string T = null)
    {
        super(X, Y, W, H, T);
        this.box(Boxtype.upBox);
        this.color(white);

        TL = new ResizeDialog(X + TLx, Y + TLy, TLw, TLh, "Original Size");
        TL.resizable(null);
        TR = new ResizeDialog(X + TRx, Y + TLy, TLw, TLh, "Horizontally Resized");
        BL = new ResizeDialog(X + TLx, Y + BLy, TLw, TLh, "Vertically Resized");
        BR = new ResizeDialog(X + TRx, Y + BLy, TLw, TLh, "Horizontally and Vertically Resized");

        FlGroup LG = new FlGroup(X + TLx, Y + LGy, TLw, LGh);
        LG.box(Boxtype.noBox);
        LG.color(white);
        LA = new Harrow(BL.m_message.x(), LG.y(), BL.m_message.w(), LAh, "Initial\nwidth");
        LG.resizable(LA);
        LG.end();

        FlGroup RG = new FlGroup(X + TRx, Y + LGy, TLw, LGh);
        RG.box(Boxtype.noBox);
        RG.color(white);
        RA = new Harrow(BR.m_message.x(), LG.y(), BL.m_message.w(), LAh, "Resized\nwidth");
        RG.resizable(RA);
        RG.end();

        FlGroup TG = new FlGroup(X + TGx, Y + TLy, TGw, TLh);
        TG.box(Boxtype.noBox);
        TG.color(white);
        TA = new Varrow(TG.x(), TR.m_message.y(), TAw, TR.m_message.h(), "Initial\nheight");
        TG.resizable(TA);
        TG.end();

        FlGroup BG = new FlGroup(X + TGx, Y + BLy, TGw, TLh);
        BG.box(Boxtype.noBox);
        BG.color(white);
        BA = new Varrow(BG.x(), BR.m_message.y(), TAw, BR.m_message.h(), "Resized\nheight");
        BG.resizable(BA);
        BG.end();

        this.resizable(BR);
        this.end();
    }
}

void main(string[] args)
{
    window = new DoubleWindow(Ww, Wh, "resize-example3b");
    window.color(white);
    auto resizables = new Resizables(0, 0, Ww, Wh);
    window.end();
    window.resizable(resizables);
    window.sizeRange(Ww, Wh);
    window.show();
    window.size(Ww + 50, Wh + 35);
    fl.visibleFocus(false); // suppress focus box
    fl.run();
}
