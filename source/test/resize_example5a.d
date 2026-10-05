// D transliteration of FLTK's test/resize-example5a.cxx,
// linked with resize-arrows.cxx (see resize_arrows.d).
// Build: rdmd buildsamples.d test resize_example5a
import fl;
import resize_arrows;

// window, simplex and arrow dimensions
int TLx = 35, TRx = 320, TLw = 260, Ww = 620;
int TLy = 35, LGy = 100, TLh = 65, LGh = 70, LAh = 35, Wh = 175;

DoubleWindow window;

class Simplex : FlGroup
{
    Box m_boxA, m_boxB, m_boxC;
    FlGroup m_group;

    this(int X, int Y, int W, int H, string T = null)
    {
        super(X, Y, W, H, T);
        this.box(Boxtype.upBox);
        m_group = new FlGroup(X + 10, Y + 10, 240, 45);
        m_group.box(Boxtype.upBox);
        m_boxA = new Box(X + 20, Y + 20, 80, 25, "A");
        m_boxA.box(Boxtype.upBox);
        m_boxB = new Box(X + 110, Y + 20, 40, 25, "B");
        m_boxB.box(Boxtype.upBox);
        m_boxC = new Box(X + 160, Y + 20, 80, 25, "C");
        m_boxC.box(Boxtype.upBox);
        m_group.color(yellow);
        m_group.end();
        this.resizable(m_group);
        this.end();
    }
}

class Resizables : FlGroup
{
    Simplex TL, TR; // top left, top right
    Harrow LA, RA;  // left arrow, right arrow

    this(int X, int Y, int W, int H, string T = null)
    {
        super(X, Y, W, H, T);
        TL = new Simplex(X + TLx, Y + TLy, TLw, TLh, "Original");
        TL.alignment(alignTopLeft);

        TR = new Simplex(X + TRx, Y + TLy, TLw, TLh, "Horizontally Resized");
        TR.alignment(alignTopLeft);

        FlGroup LG = new FlGroup(X + TLx, Y + LGy, TLw, LGh);
        LG.box(Boxtype.noBox);
        LG.color(white);
        LA = new Harrow(TL.m_group.x(), LG.y(), TL.m_group.w(), LAh, "Initial\nwidth");
        LG.resizable(LA);
        LG.end();

        FlGroup RG = new FlGroup(X + TRx, Y + LGy, TLw, LGh);
        RG.box(Boxtype.noBox);
        RG.color(white);
        RA = new Harrow(TR.m_group.x(), RG.y(), TR.m_group.w(), LAh, "Resized\nwidth");
        RG.resizable(RA);
        RG.end();

        this.resizable(TR);
        this.end();
    }
}

void main(string[] args)
{
    window = new DoubleWindow(Ww, Wh, "resize-example5a");
    window.color(white);
    auto resizables = new Resizables(0, 0, Ww, Wh);
    window.end();
    window.resizable(resizables);
    window.sizeRange(Ww, Wh);
    window.show();
    window.size(Ww + 90, Wh);
    fl.run();
}
