// D transliteration of FLTK's test/resize-example1.cxx,
// linked with resize-arrows.cxx (see resize_arrows.d).
// Build: rdmd buildsamples.d test resize_example1
import fl;
import resize_arrows;

DoubleWindow window;

// inner box dimensions
int Ax = 0, Bx = 35, Cx = 70, Dx = 105, Nx = 140, Aw = 35, Rw = 70, Mw = 140;
int Ay = 0, Ey = 35, Gy = 70, Iy = 105, My = 140, Ah = 35, Rh = 70, Nh = 175;

// resize box and arrow group dimensions
int TLx = 35, TRx = 245, TGx = 420, TLw = 175, TGw = 140, TAw = 35;
int TLy = 35, BLy = 245, LGy = 420, TLh = 175, LGh = 105, LAh = 35;

// window dimensions
int Ww = 560, Wh = 525;

class Resizebox : FlGroup
{
    this(int X, int Y, int W, int H, string T)
    {
        super(X, Y, W, H, T);
        alignment(alignTopLeft);
        box(Boxtype.upBox);

        Box b;
        b = new Box(Boxtype.engravedBox, X + Ax, Y + Ay, Aw, Ah, "A"); b.color(14);
        b = new Box(Boxtype.engravedBox, X + Bx, Y + Ay, Aw, Ah, "B"); b.color(9);
        b = new Box(Boxtype.engravedBox, X + Cx, Y + Ay, Aw, Ah, "C"); b.color(10);
        b = new Box(Boxtype.engravedBox, X + Dx, Y + Ay, Aw, Ah, "D"); b.color(11);
        b = new Box(Boxtype.engravedBox, X + Ax, Y + Ey, Aw, Ah, "E"); b.color(9);
        b = new Box(Boxtype.engravedBox, X + Bx, Y + Ey, Rw, Rh, " "); b.color(8);
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
        this.resizable(this);
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
        LA = new Harrow(LG.x(), LG.y(), LG.w(), LAh, "Initial\nwidth");
        LG.resizable(LA);
        LG.end();

        FlGroup RG = new FlGroup(X + TRx, Y + LGy, TLw, LGh);
        RG.box(Boxtype.noBox);
        RG.color(white);
        RA = new Harrow(RG.x(), RG.y(), RG.w(), LAh, "Resized\nwidth");
        RG.resizable(RA);
        RG.end();

        FlGroup TG = new FlGroup(X + TGx, Y + TLy, TGw, TLh);
        TG.box(Boxtype.noBox);
        TG.color(white);
        TA = new Varrow(X + TGx, Y + TLy, TAw, TLh, "Initial\nheight");
        TG.resizable(TA);
        TG.end();

        FlGroup BG = new FlGroup(X + TGx, Y + BLy, TGw, TLh);
        BG.box(Boxtype.noBox);
        BG.color(white);
        BA = new Varrow(X + TGx, Y + BLy, TAw, TLh, "Resized\nheight");
        BG.resizable(BA);
        BG.end();

        this.resizable(BR);
        this.end();
    }
}

void main(string[] args)
{
    window = new DoubleWindow(Ww, Wh, "resize-example1");
    window.color(white);
    auto resizables = new Resizables(0, 0, Ww, Wh);
    window.end();
    window.resizable(resizables);
    window.sizeRange(Ww, Wh);
    window.show();
    window.size(Ww + 140, Wh + 35);
    fl.run();
}
