// D transliteration of FLTK's test/image.cxx (~/Repositories/fltk).
// Part of the samples/ contract -- see samples/README.md.
// Check: ./samples/build.sh image
import fl;
import xlib = fl.xlib;
import platformX11 = fl.platform_x11;
import fldraw = fl.draw;
import std.math : sqrt;

int width = 100;
int height = 100;
ubyte[] image;

void makeImage()
{
    image = new ubyte[4 * width * height];
    size_t p = 0;
    for (int y = 0; y < height; y++)
    {
        double Y = double(y) / (height - 1);
        for (int x = 0; x < width; x++)
        {
            double X = double(x) / (width - 1);
            image[p++] = cast(ubyte)(255 * ((1 - X) * (1 - Y))); // red in upper-left
            image[p++] = cast(ubyte)(255 * ((1 - X) * Y));       // green in lower-left
            image[p++] = cast(ubyte)(255 * (X * Y));             // blue in lower-right
            X -= 0.5;
            Y -= 0.5;
            int alpha = cast(int)(255 * sqrt(X * X + Y * Y));
            if (alpha < 255) image[p++] = cast(ubyte) alpha; // alpha transparency
            else image[p++] = 255;
            Y += 0.5;
        }
    }
}

ToggleButton leftb, rightb, topb, bottomb, insideb, overb, inactb;
Button b;
DoubleWindow w;

void buttonCb(Widget wgt)
{
    Align i = 0;
    if (leftb.value()) i |= alignLeft;
    if (rightb.value()) i |= alignRight;
    if (topb.value()) i |= alignTop;
    if (bottomb.value()) i |= alignBottom;
    if (insideb.value()) i |= alignInside;
    if (overb.value()) i |= alignTextOverImage;
    b.alignment(i);
    if (inactb.value()) b.deactivate();
    else b.activate();
    w.redraw();
}

int visid = -1;
int arg(string[] argv, ref int i)
{
    if (argv[i][1] == 'v')
    {
        if (i + 1 >= argv.length) return 0;
        import std.conv : to, ConvException;
        // FLTK uses atoi(), which returns 0 for a malformed -v
        // argument instead of throwing.
        try
            visid = to!int(argv[i + 1]);
        catch (ConvException)
            visid = 0;
        i += 2;
        return 2;
    }
    return 0;
}

void main(string[] args)
{
    int i = 1;
    fl.args(args, i, (argv, ref j) => arg(argv, j));

    if (visid >= 0)
    {
        // `-v <id>` selects a specific X11 Visual by numeric id -- a
        // pure X11/Xlib concept (`fl.xlib`/`fl.platform_x11`, both
        // `version (linux):`-gated modules) with no Windows equivalent
        // at all, matching `list_visuals`'s own identical scope (see
        // `buildsamples.d`'s `skipWindows` table). Real on Linux;
        // Windows just reports the flag as unsupported and falls back
        // to the default RGB visual, rather than failing to build.
        version (linux)
        {
            // fl.xlib has no fl_open_display()/fl_display/fl_visual/
            // fl_colormap of its own -- the real equivalents live in
            // fl.platform_x11 (plain process-global state, matching
            // FLTK's own fl_visual/fl_colormap architecture; see that
            // module's own doc comment on fl_visual for why it's there
            // and not here).
            platformX11.openDisplay();
            xlib.XVisualInfo templt;
            int num;
            templt.visualid = visid;
            platformX11.fl_visual = xlib.XGetVisualInfo(
                platformX11.x11Display(), xlib.VisualIDMask, &templt, &num);
            if (!platformX11.fl_visual)
            {
                import std.stdio : stderr;
                // Each samples/test/*.d program is its own standalone
                // binary (unlike FLTK's `#include "list_visuals.cxx"`
                // textual inlining, which has no D equivalent via
                // `import`), so this points at the separate `list_visuals`
                // program instead of duplicating its ~150-line dump here.
                stderr.writefln("No visual with id %d -- run `list_visuals` to see what's available.", visid);
                return;
            }
            platformX11.fl_colormap = xlib.XCreateColormap(platformX11.x11Display(),
                xlib.XRootWindow(platformX11.x11Display(), platformX11.x11Screen()),
                platformX11.fl_visual.visual, xlib.AllocNone);
            fldraw.xpixel(black); // make sure black is allocated in overlay visuals
        }
        else
        {
            import std.stdio : stderr;
            stderr.writeln("-v (visual selection) is only supported on X11; ignoring on this platform.");
            fl.visual(modeRgb);
        }
    }
    else
    {
        fl.visual(modeRgb);
    }

    w = new DoubleWindow(400, 400);
    w.color(white);
    b = new Button(140, 160, 120, 120, "Image w/Alpha");

    RGBImage rgb;
    Image dergb;

    makeImage();
    rgb = new RGBImage(image, width, height, 4);
    dergb = rgb.copy();
    dergb.inactive();

    b.image(rgb);
    b.deimage(dergb);

    leftb = new ToggleButton(25, 50, 50, 25, "left");
    leftb.callback((wgt) { buttonCb(wgt); });
    rightb = new ToggleButton(75, 50, 50, 25, "right");
    rightb.callback((wgt) { buttonCb(wgt); });
    topb = new ToggleButton(125, 50, 50, 25, "top");
    topb.callback((wgt) { buttonCb(wgt); });
    bottomb = new ToggleButton(175, 50, 50, 25, "bottom");
    bottomb.callback((wgt) { buttonCb(wgt); });
    insideb = new ToggleButton(225, 50, 50, 25, "inside");
    insideb.callback((wgt) { buttonCb(wgt); });
    overb = new ToggleButton(25, 75, 100, 25, "text over");
    overb.callback((wgt) { buttonCb(wgt); });
    inactb = new ToggleButton(125, 75, 100, 25, "inactive");
    inactb.callback((wgt) { buttonCb(wgt); });
    w.resizable(w);
    w.end();
    w.show(args);
    fl.run();
}
