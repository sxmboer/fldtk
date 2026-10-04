// D transliteration of FLTK's test/resize-example4a.cxx (~/Repositories/fltk),
// linked with resize-arrows.cxx (see resize_arrows.d).
// Part of the samples/ contract -- see samples/README.md.
// Check: ./samples/build.sh resize-example4a
import fl;
import resize_arrows;

// window, simplex and arrow dimensions
int TLx = 35, TRx = 320, TLw = 260, Ww = 620;
int TLy = 35, LGy = 100, TLh = 65, LGh = 70, LAh = 35, Wh = 200;

DoubleWindow window;

class Simplex : FlGroup
{
    Box m_button1, m_input1, m_button2, m_input2;

    this(int X, int Y, int W, int H, string T = null)
    {
        super(X, Y, W, H, T);
        this.box(Boxtype.upBox);
        FlGroup group = new FlGroup(X + 10, Y + 10, 240, 45);
        group.box(Boxtype.noBox);
        m_button1 = new Box(X + 20, Y + 20, 40, 25, "btn");
        m_button1.box(Boxtype.upBox);
        m_input1 = new Box(X + 70, Y + 20, 50, 25, "input");
        m_input1.box(Boxtype.upBox);
        m_button2 = new Box(X + 140, Y + 20, 40, 25, "btn");
        m_button2.box(Boxtype.upBox);
        m_input2 = new Box(X + 190, Y + 20, 50, 25, "input");
        m_input2.box(Boxtype.upBox);
        m_input2.color(yellow);
        group.resizable(m_input2);
        group.end();
        this.resizable(group);
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

        TR = new Simplex(X + TRx, Y + TLy, TLw, TLh, "Horizonally Resized");
        TR.alignment(alignTopLeft);

        FlGroup LG = new FlGroup(X + TLx, Y + LGy, TLw, LGh);
        LG.box(Boxtype.noBox);
        LG.color(white);
        LA = new Harrow(TL.m_input2.x(), LG.y(), TL.m_input2.w(), LAh, "Initial\nwidth");
        LG.resizable(LA);
        LG.end();

        FlGroup RG = new FlGroup(X + TRx, Y + LGy, TLw, LGh);
        RG.box(Boxtype.noBox);
        RG.color(white);
        RA = new Harrow(TR.m_input2.x(), RG.y(), TR.m_input2.w(), LAh, "Resized\nwidth");
        RG.resizable(RA);
        RG.end();

        this.resizable(TR);
        this.end();
    }
}

void main(string[] args)
{
    window = new DoubleWindow(Ww, Wh, "resize-example4a");
    window.color(white);
    auto resizables = new Resizables(0, 0, Ww, Wh);
    window.end();
    window.resizable(resizables);
    window.sizeRange(Ww, Wh);
    window.show();
    window.size(Ww + 90, Wh);
    fl.run();
}
