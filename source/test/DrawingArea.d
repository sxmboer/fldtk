// D transliteration of FLTK's test/mandelbrot.cxx + test/mandelbrot.h
// (~/Repositories/fltk). Part of the samples/ contract -- see
// samples/README.md.
//
// mandelbrot_ui.fl (Fluid-generated -- see samples/test/generated/
// mandelbrot_ui.d once built) provides the `DrawingWindow` class's
// makeWindow() only -- see that .fl file's own top comment for the
// full split. This file provides everything FLTK's own
// mandelbrot.cxx/.h hand-write: the DrawingArea class (the actual
// Mandelbrot/Julia renderer), main(), the idle-callback render loop,
// and updateLabel() (added to DrawingWindow via UFCS, since D has no
// way to define a class's method body from a separate file the way
// C++'s `ClassWindow::method() {}` can).
module DrawingArea;

import fl;
import mandelbrot_ui;
import std.format : format;

// Ported verbatim from mandelbrot.cxx's own `palette[]` -- a
// hand-picked red-to-blue-to-yellow gradient used by getColor() below
// when DrawingArea.useColors is set.
private immutable uint[] palette = [
    0xCC0000, 0xCA0002, 0xC90004, 0xC70006, 0xC60008, 0xC4000A, 0xC3000C, 0xC1000E, 0xBF0010, 0xBE0012,
    0xBC0014, 0xBB0016, 0xB90018, 0xB8001A, 0xB6001B, 0xB4001D, 0xB3001F, 0xB10021, 0xB00023, 0xAE0025,
    0xAD0027, 0xAB0029, 0xA9002B, 0xA8002D, 0xA6002F, 0xA50031, 0xA30033, 0xA20035, 0xA00037, 0x9E0039,
    0x9D003B, 0x9B003D, 0x9A003F, 0x980041, 0x970043, 0x950045, 0x940047, 0x920049, 0x90004B, 0x8F004D,
    0x8D004E, 0x8C0050, 0x8A0052, 0x890054, 0x870056, 0x850058, 0x84005A, 0x82005C, 0x81005E, 0x7F0060,
    0x7E0062, 0x7C0064, 0x7A0066, 0x790068, 0x77006A, 0x76006C, 0x74006E, 0x730070, 0x710072, 0x6F0074,
    0x6E0076, 0x6C0078, 0x6B007A, 0x69007C, 0x68007E, 0x660080, 0x640081, 0x630083, 0x610085, 0x600087,
    0x5E0089, 0x5D008B, 0x5B008D, 0x59008F, 0x580091, 0x560093, 0x550095, 0x530097, 0x520099, 0x50009B,
    0x4E009D, 0x4D009F, 0x4B00A1, 0x4A00A3, 0x4800A5, 0x4700A7, 0x4500A9, 0x4300AB, 0x4200AD, 0x4000AF,
    0x3F00B1, 0x3D00B3, 0x3C00B4, 0x3A00B6, 0x3800B8, 0x3700BA, 0x3500BC, 0x3400BE, 0x3200C0, 0x3100C2,
    0x2F00C4, 0x2E00C6, 0x2C00C8, 0x2A00CA, 0x2900CC, 0x2700CE, 0x2600D0, 0x2400D2, 0x2300D4, 0x2100D6,
    0x1F00D8, 0x1E00DA, 0x1C00DC, 0x1B00DE, 0x1900E0, 0x1800E2, 0x1600E4, 0x1400E6, 0x1300E7, 0x1100E9,
    0x1000EB, 0x0E00ED, 0x0D00EF, 0x0B00F1, 0x0900F3, 0x0800F5, 0x0600F7, 0x0500F9, 0x0300FB, 0x0200FD,
    0x0000FF, 0x0202FD, 0x0404FB, 0x0606F9, 0x0808F7, 0x0A0AF5, 0x0C0CF3, 0x0E0EF1, 0x1010EF, 0x1212ED,
    0x1414EB, 0x1616E9, 0x1818E7, 0x1A1AE6, 0x1B1BE4, 0x1D1DE2, 0x1F1FE0, 0x2121DE, 0x2323DC, 0x2525DA,
    0x2727D8, 0x2929D6, 0x2B2BD4, 0x2D2DD2, 0x2F2FD0, 0x3131CE, 0x3333CC, 0x3535CA, 0x3737C8, 0x3939C6,
    0x3B3BC4, 0x3D3DC2, 0x3F3FC0, 0x4141BE, 0x4343BC, 0x4545BA, 0x4747B8, 0x4949B6, 0x4B4BB4, 0x4D4DB3,
    0x4E4EB1, 0x5050AF, 0x5252AD, 0x5454AB, 0x5656A9, 0x5858A7, 0x5A5AA5, 0x5C5CA3, 0x5E5EA1, 0x60609F,
    0x62629D, 0x64649B, 0x666699, 0x686897, 0x6A6A95, 0x6C6C93, 0x6E6E91, 0x70708F, 0x72728D, 0x74748B,
    0x767689, 0x787887, 0x7A7A85, 0x7C7C83, 0x7E7E81, 0x808080, 0x81817E, 0x83837C, 0x85857A, 0x878778,
    0x898976, 0x8B8B74, 0x8D8D72, 0x8F8F70, 0x91916E, 0x93936C, 0x95956A, 0x979768, 0x999966, 0x9B9B64,
    0x9D9D62, 0x9F9F60, 0xA1A15E, 0xA3A35C, 0xA5A55A, 0xA7A758, 0xA9A956, 0xABAB54, 0xADAD52, 0xAFAF50,
    0xB1B14E, 0xB3B34D, 0xB4B44B, 0xB6B649, 0xB8B847, 0xBABA45, 0xBCBC43, 0xBEBE41, 0xC0C03F, 0xC2C23D,
    0xC4C43B, 0xC6C639, 0xC8C837, 0xCACA35, 0xCCCC33, 0xCECE31, 0xD0D02F, 0xD2D22D, 0xD4D42B, 0xD6D629,
    0xD8D827, 0xDADA25, 0xDCDC23, 0xDEDE21, 0xE0E01F, 0xE2E21D, 0xE4E41B, 0xE6E61A, 0xE7E718, 0xE9E916,
    0xEBEB14, 0xEFEF10, 0xF3F30C, 0xF7F708, 0xFBFB04, 0xFFFF00,
];

private void getColor(float t, out ubyte r, out ubyte g, out ubyte b)
{
    int index = cast(int)((1 - t) * palette.length);
    fl.core.getColor(cast(Color)(palette[index % palette.length] << 8), r, g, b);
}

class DrawingArea : Box
{
    // Ported from Drawing_Area's own anonymous enum.
    enum
    {
        maxBrightness = 16,
        defaultBrightness = 16,
        defaultBrightnessColor = 8,
        maxIterations = 14,
        defaultIterations = 7,
    }

    ubyte[] buffer;
    int useColors;
    int W, H;
    int dx, dy, dw, dh; // drawing box offsets
    int nextline;
    int drawn;
    int julia;
    int iterations;
    int brightness;
    double jX, jY;
    double X, Y, scale;
    int sx, sy, sw, sh; // selection box

    // The .fl-generated makeWindow() sets this right after construction
    // (`d.owner = this;`) -- replaces FLTK's `user_data()`-as-
    // `Drawing_Window*` cast trick (see handle()'s FL_RELEASE case).
    DrawingWindow owner;

    this(int x, int y, int w, int h)
    {
        super(x, y, w, h);
        useColors = 0; // FLTK's USE_COLORS; change to 1 to start in color mode
        W = w;
        H = h;
        dx = dy = 0; // NOTE: as the box type is set *after* the constructor
        dw = dh = 0; //       the actual offsets are determined in draw()
        nextline = 0;
        drawn = 0;
        julia = 0;
        X = Y = 0;
        scale = 4.0;
        iterations = 1 << defaultIterations;
        brightness = useColors ? defaultBrightnessColor : defaultBrightness;
        sx = sy = sw = sh = 0;
    }

    override void draw()
    {
        if (dx == 0)
        {
            dx = boxDx(box());
            dy = boxDy(box());
            dw = boxDw(box());
            dh = boxDh(box());
            W -= dw;
            H -= dh;
        }
        drawBox();
        drawn = 0;
        setIdle();
    }

    int idle()
    {
        auto win = window();
        if (win is null || !win.visible()) return 0;

        if (drawn < nextline)
        {
            win.makeCurrent();
            int yy = drawn + y() + dy;
            if (yy >= sy && yy <= sy + sh) eraseBox();
            if (useColors)
                drawImage(buffer.ptr + drawn * W * 3, x() + dx, yy, W, 1, 3);
            else
                drawImageMono(buffer.ptr + drawn * W, x() + dx, yy, W, 1, 1, W);
            drawn++;
            return 1;
        }

        int linebytes = useColors ? W * 3 : W;
        if (nextline < H)
        {
            if (buffer is null) buffer = new ubyte[linebytes * H];
            double yy = Y + (H / 2 - nextline) * scale / W;
            double yi = yy;
            if (julia) yy = jY;
            size_t pIdx = nextline * linebytes;
            for (int xi = 0; xi < W; xi++)
            {
                double xx = X + (xi - W / 2) * scale / W;
                double wx = xx, wy = yi;
                if (julia) xx = jX;
                for (int i = 0; ; i++)
                {
                    if (i >= iterations)
                    {
                        buffer[pIdx] = 0;
                        if (useColors)
                        {
                            buffer[pIdx + 1] = 0;
                            buffer[pIdx + 2] = 0;
                        }
                        break;
                    }
                    double t = wx * wx - wy * wy + xx;
                    wy = 2 * wx * wy + yy;
                    wx = t;
                    if (wx * wx + wy * wy > 4)
                    {
                        wx = t = 1 - cast(double) i / (1 << 10);
                        if (t <= 0) t = 0; else for (i = brightness; i--;) t *= wx;
                        if (useColors)
                        {
                            ubyte r, g, b;
                            getColor(cast(float) t, r, g, b);
                            buffer[pIdx] = r;
                            buffer[pIdx + 1] = g;
                            buffer[pIdx + 2] = b;
                        }
                        else
                        {
                            buffer[pIdx] = cast(ubyte)(255 - cast(int)(254 * t));
                        }
                        break;
                    }
                }
                pIdx += useColors ? 3 : 1;
            }
            nextline++;
            return nextline <= H ? 1 : 0;
        }
        return 0;
    }

    private void eraseBox()
    {
        window().makeCurrent();
        overlayClear();
    }

    override int handle(Event event)
    {
        static int ix, iy;
        static bool dragged;
        static int button;
        int x2, y2;
        switch (event)
        {
            case Event.push:
                eraseBox();
                ix = eventX(); if (ix < x()) ix = x(); if (ix >= x() + w()) ix = x() + w() - 1;
                iy = eventY(); if (iy < y()) iy = y(); if (iy >= y() + h()) iy = y() + h() - 1;
                dragged = false;
                button = eventButton();
                return 1;

            case Event.drag:
                dragged = true;
                eraseBox();
                x2 = eventX(); if (x2 < x()) x2 = x(); if (x2 >= x() + w()) x2 = x() + w() - 1;
                y2 = eventY(); if (y2 < y()) y2 = y(); if (y2 >= y() + h()) y2 = y() + h() - 1;
                if (button != 1) { ix = x2; iy = y2; return 1; }
                if (ix < x2) { sx = ix; sw = x2 - ix; } else { sx = x2; sw = ix - x2; }
                if (iy < y2) { sy = iy; sh = y2 - iy; } else { sy = y2; sh = iy - y2; }
                window().makeCurrent();
                overlayRect(sx, sy, sw, sh);
                return 1;

            case Event.release:
                if (button == 1)
                {
                    eraseBox();
                    if (dragged && sw > 3 && sh > 3)
                    {
                        X = X + (sx + sw / 2 - x() - W / 2) * scale / W;
                        Y = Y + (-sy - sh / 2 + y() + H / 2) * scale / W;
                        scale = sw * scale / W;
                    }
                    else if (!dragged)
                    {
                        scale = 2 * scale;
                        if (julia)
                        {
                            if (scale >= 4) { scale = 4; X = Y = 0; }
                        }
                        else
                        {
                            if (scale >= 2.5) { scale = 2.5; X = -.75; Y = 0; }
                        }
                    }
                    else return 1;
                    owner.updateLabel();
                    newDisplay();
                }
                else if (!julia)
                {
                    if (jbrot is null) jbrot = new DrawingWindow();
                    if (jbrot.d is null)
                    {
                        jbrot.makeWindow();
                        jbrot.d.julia = 1;
                        jbrot.d.X = 0;
                        jbrot.d.Y = 0;
                        jbrot.d.scale = 4;
                        jbrot.d.useColors = mbrot.d.useColors;
                        jbrot.updateLabel();
                    }
                    jbrot.d.jX = X + (ix - x() - W / 2) * scale / W;
                    jbrot.d.jY = Y + (H / 2 - iy + y()) * scale / W;
                    jbrot.window.label(format("Julia %.7f %.7f", jbrot.d.jX, jbrot.d.jY));
                    jbrot.window.show();
                    jbrot.d.newDisplay();
                }
                return 1;

            default:
                break;
        }
        return 0;
    }

    void newDisplay()
    {
        drawn = nextline = 0;
        setIdle();
    }

    void newBuffer()
    {
        if (buffer !is null) { buffer = null; newDisplay(); }
    }

    override void resize(int xx, int yy, int ww, int hh)
    {
        if (ww != w() || hh != h())
        {
            W = ww - dw;
            H = hh - dh;
            if (buffer !is null) { buffer = null; newDisplay(); }
        }
        super.resize(xx, yy, ww, hh);
    }
}

// D has no way to define a class's own method body in a separate file
// the way C++'s `ClassWindow::method() {}` can -- added via UFCS
// instead (`dw.updateLabel()` resolves to `updateLabel(dw)`), matching
// mandelbrot_ui.fl's own comment on this.
void updateLabel(DrawingWindow dw)
{
    dw.xInput.value(format("%+.10f", dw.d.X));
    dw.yInput.value(format("%+.10f", dw.d.Y));
    dw.wInput.value(format("%.2g", dw.d.scale));
}

DrawingWindow mbrot;
DrawingWindow jbrot;

// A single stored delegate value, added/removed by identity -- a
// module-level lambda literal is created fresh (and so compares
// unequal to itself) every time it's written out, so it has to be
// created exactly once and reused for both addIdle()/removeIdle()
// calls below. Matches FLTK's `Fl::add_idle(idle)`/
// `Fl::remove_idle(idle)`, which can reuse a plain function pointer
// for the same purpose.
private IdleHandler idleHandler_;

private void idleCb()
{
    if (!mbrot.d.idle() && !(jbrot !is null && jbrot.d !is null && jbrot.d.idle()))
        fl.removeIdle(idleHandler_);
}

private void setIdle()
{
    if (idleHandler_ is null) idleHandler_ = { idleCb(); };
    fl.addIdle(idleHandler_);
}

private void windowCallback(Widget o)
{
    fl.hideAllWindows();
}

private void printCb(Widget o)
{
    auto printer = new Printer();
    auto win = o.window();
    if (win is null || !win.visible()) return;
    win.makeCurrent();
    ubyte[] imageData = readImage(0, 0, win.w(), win.h());
    string errMessage;
    if (printer.beginJob(1, errMessage)) return;
    if (printer.beginPage()) return;
    printer.scale(.7f, .7f);
    drawImage(imageData.ptr, 0, 0, win.w(), win.h());
    printer.endPage();
    printer.endJob();
}

private void toggleColorCb(Widget o)
{
    mbrot.d.useColors = !mbrot.d.useColors;
    mbrot.d.newBuffer();
    if (jbrot !is null && jbrot.d !is null)
    {
        jbrot.d.useColors = mbrot.d.useColors;
        jbrot.d.newBuffer();
    }
}

void main(string[] args)
{
    mbrot = new DrawingWindow();
    mbrot.makeWindow();

    mbrot.window.begin();
    auto printBtn = new Button(0, 0, 0, 0, null);
    printBtn.callback((w) { printCb(w); });
    printBtn.shortcut(stateCtrl + 'p');
    auto toggleBtn = new Button(0, 0, 0, 0, null);
    toggleBtn.callback((w) { toggleColorCb(w); });
    toggleBtn.shortcut(stateCtrl + 'm');
    mbrot.window.end();

    mbrot.d.X = -.75;
    mbrot.d.scale = 2.5;
    mbrot.updateLabel();

    int i = 0;
    if (fl.args(args, i) < args.length) fl.fatal(fl.argsHelp);
    fl.visual(modeRgb);
    mbrot.window.callback((w) { windowCallback(w); });
    mbrot.window.show(args);
    fl.run();
}
