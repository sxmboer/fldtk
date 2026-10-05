// D transliteration of FLTK's test/resize-example2.cxx,
// linked with resize-arrows.cxx (see resize_arrows.d).
// Build: rdmd buildsamples.d test resize_example2
import fl;
import resize_arrows;

// inner box dimensions
int Ax = 0, Bx = 35, Cx = 70, Dx = 105, Nx = 140, Aw = 35, Rw = 70, Mw = 140;
int Ay = 0, Ey = 35, Gy = 70, Iy = 105, My = 140, Ah = 35, Rh = 70, Nh = 175;

// resize box and arrow group dimensions
int TLx = 35, TRx = 245, TGx = 420, TLw = 175, TGw = 140, TAw = 35;
int TLy = 35, BLy = 245, LGy = 420, TLh = 175, LGh = 105, LAh = 35;

// window dimensions
int Ww = 560, Wh = 525;

DoubleWindow window;

class Resizebox : FlGroup
{
    Box m_box;

    this(int X, int Y, int W, int H, string T)
    {
        super(X, Y, W, H, T);
        this.alignment(alignTopLeft);
        this.box(Boxtype.upBox);

        Box b;
        b = new Box(Boxtype.engravedBox, X + Ax, Y + Ay, Aw, Ah, "A"); b.color(14);
        b = new Box(Boxtype.engravedBox, X + Bx, Y + Ay, Aw, Ah, "B"); b.color(9);
        b = new Box(Boxtype.engravedBox, X + Cx, Y + Ay, Aw, Ah, "C"); b.color(10);
        b = new Box(Boxtype.engravedBox, X + Dx, Y + Ay, Aw, Ah, "D"); b.color(11);
        b = new Box(Boxtype.engravedBox, X + Ax, Y + Ey, Aw, Ah, "E"); b.color(9);
        b = new Box(Boxtype.engravedBox, X + Bx, Y + Ey, Rw, Rh, "R"); b.color(3);
        b.label("resizable");
        m_box = b;
        b = new Box(Boxtype.engravedBox, X + Dx, Y + Ey, Aw, Ah, "F"); b.color(12);
        b = new Box(Boxtype.engravedBox, X + Ax, Y + Gy, Aw, Ah, "G"); b.color(10);
        b = new Box(Boxtype.engravedBox, X + Dx, Y + Gy, Aw, Ah, "H"); b.color(13);
        b = new Box(Boxtype.engravedBox, X + Ax, Y + Iy, Aw, Ah, "I"); b.color(11);
        b = new Box(Boxtype.engravedBox, X + Bx, Y + Iy, Aw, Ah, "J"); b.color(12);
        b = new Box(Boxtype.engravedBox, X + Cx, Y + Iy, Aw, Ah, "K"); b.color(13);
        b = new Box(Boxtype.engravedBox, X + Dx, Y + Iy, Aw, Ah, "L"); b.color(14);
        b = new Box(Boxtype.engravedBox, X + Ax, Y + My, Mw, Ah, "M"); b.color(12);
        b = new Box(Boxtype.engravedBox, X + Nx, Y + Ay, Aw, Nh, "N"); b.color(13);

        this.end();
        this.resizable(m_box);
    }
}

class Resizables : FlGroup
{
    Resizebox TL, TR, BL, BR; // topleft, topright, bottomleft, bottomright
    Harrow LA, RA;            // left arrow, right arrow
    Varrow TA, BA;            // top arrow, bottom arrow

    this(int X, int Y, int W, int H, string T = null)
    {
        super(X, Y, W, H, T);
        this.box(Boxtype.upBox);
        this.color(white);

        TL = new Resizebox(X + TLx, Y + TLy, TLw, TLh, "Original Size");
        TL.resizable(null);
        TR = new Resizebox(X + TRx, Y + TLy, TLw, TLh, "Horizontally Resized");
        BL = new Resizebox(X + TLx, Y + BLy, TLw, TLh, "Vertically Resized");
        BR = new Resizebox(X + TRx, Y + BLy, TLw, TLh, "Horizontally and Vertically Resized");

        FlGroup LG = new FlGroup(X + TLx, Y + LGy, TLw, LGh);
        LG.box(Boxtype.noBox);
        LG.color(white);
        LA = new Harrow(BL.m_box.x(), LG.y(), BL.m_box.w(), LAh, "Initial\nwidth");
        LG.resizable(LA);
        LG.end();

        FlGroup RG = new FlGroup(X + TRx, Y + LGy, TLw, LGh);
        RG.box(Boxtype.noBox);
        RG.color(white);
        RA = new Harrow(BR.m_box.x(), LG.y(), BL.m_box.w(), LAh, "Resized\nwidth");
        RG.resizable(RA);
        RG.end();

        FlGroup TG = new FlGroup(X + TGx, Y + TLy, TGw, TLh);
        TG.box(Boxtype.noBox);
        TG.color(white);
        TA = new Varrow(TG.x(), TR.m_box.y(), TAw, TR.m_box.h(), "Initial\nheight");
        TG.resizable(TA);
        TG.end();

        FlGroup BG = new FlGroup(X + TGx, Y + BLy, TGw, TLh);
        BG.box(Boxtype.noBox);
        BG.color(white);
        BA = new Varrow(BG.x(), BR.m_box.y(), TAw, BR.m_box.h(), "Resized\nheight");
        BG.resizable(BA);
        BG.end();

        this.resizable(BR);
        this.end();
    }
}

void main(string[] args)
{
    window = new DoubleWindow(Ww, Wh, "resize-example2");
    window.color(white);
    auto resizables = new Resizables(0, 0, Ww, Wh);
    window.end();
    window.resizable(resizables);
    window.sizeRange(Ww, Wh);
    window.show();
    window.size(Ww + 140, Wh + 35);
    fl.run();
}
