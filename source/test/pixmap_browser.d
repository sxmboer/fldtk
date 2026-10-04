// D transliteration of FLTK's test/pixmap_browser.cxx (~/Repositories/fltk).
// Part of the samples/ contract -- see samples/README.md.
// Check: ./samples/build.sh pixmap_browser
import fl;
import filename = fl.filename;
import std.stdio : writeln, stdout, File;

Box b;
DoubleWindow w;
SharedImage img;

static string name;

void cbForcedRedraw(Widget)
{
    Window win = fl.firstWindow();
    while (win !is null)
    {
        if (!win.menuWindow())
            win.redraw();
        win = fl.nextWindow(win);
    }
    if (fl.firstWindow())
        fl.repeatTimeout(1.0 / 10, () { cbForcedRedraw(null); });
}

void loadFile(string n)
{
    if (img)
    {
        (cast(SharedImage) b.image()).release();
        img = null;
    }
    if (filename.filenameIsdir(n))
    {
        b.label("@fileopen"); // show a generic folder
        b.labelsize(64);
        b.labelcolor(light2);
        b.image(null);
        b.redraw();
        return;
    }
    SharedImage img2 = SharedImage.get(n);

    if (!img2)
    {
        b.label("@filenew"); // show an empty document
        b.labelsize(64);
        b.labelcolor(light2);
        b.image(null);
        b.redraw();
        return;
    }
    img = img2;
    b.labelsize(14);
    b.labelcolor(foregroundColor);
    b.image(img);
    img.scale(b.w(), b.h());
    b.label(cast(string) null);
    b.redraw();
}

void fileCb(string n)
{
    if (name == n) return;
    loadFile(n);
    name = n;
    w.label(name);
}

void buttonCb(Widget)
{
    fileChooserCallback((n) { fileCb(n); });
    string fname = fileChooser("Image file?", "*.{bm,bmp,gif,ico,jpg,pbm,pgm,png,ppm,xbm,xpm}", name);
    writeln(fname ? fname : "(null)");
    stdout.flush();
    fileChooserCallback(null);
}

void printCb(Widget widget)
{
    auto printer = new Printer();
    int width, height;
    string err;
    if (printer.beginJob(1, err)) return;
    printer.beginPage();
    printer.printableRect(width, height);
    float fw = widget.window().decoratedW() / cast(float) width;
    float fh = widget.window().decoratedH() / cast(float) height;
    if (fh > fw) fw = fh;
    printer.scale(1 / fw);
    printer.printWindow(widget.window());
    printer.endPage();
    printer.endJob();
}

void svgCb(Widget widget)
{
    auto fnfc = new NativeFileChooser();
    fnfc.title("Pick a .svg file");
    fnfc.type(BrowseType.browseSaveFile);
    fnfc.filter("SVG\t*.svg\n");
    fnfc.options(saveasConfirm | useFilterExt);
    if (fnfc.show()) return;
    auto svg = File(fnfc.filename(), "w");
    auto surf = new SvgFileSurface(widget.window().decoratedW(), widget.window().decoratedH(), svg);
    surf.drawDecoratedWindow(widget.window());
    surf.close();
}

int dvisual = 0;
int animate = 1;
int arg(string[] argv, ref int i)
{
    if (argv[i][1] == '8') { dvisual = 1; i++; return 1; }
    if (argv[i][1] == 'a') { animate = 1; i++; return 1; }
    return 0;
}

/// **Deliberate upgrade over FLTK**: real FLTK's own `test/
/// pixmap_browser.cxx` `copy_cb()` builds the `Fl_Copy_Surface`/temp box
/// from `img->w()`/`img->h()` directly -- but `loadFile()` (above)
/// already called `img.scale(b.w(), b.h())` to fit the image into the
/// preview box, and `Image.scale()` only ever changes `w()`/`h()` (the
/// *display* size), never `dataW()`/`dataH()` (the real underlying pixel
/// data) -- so FLTK's own Copy button silently copies whatever
/// shrunk size the preview happens to be showing, not the original
/// image (a genuine FLTK bug, not a porting gap -- `Fl_Image::
/// scale()`'s own doc comment, `fl.image.d`'s port of it, says so
/// explicitly). Fixed here by temporarily resetting `img`'s display size
/// to its native data size for the duration of this synchronous callback
/// (nothing else runs in between to observe the change), then restoring
/// the preview's own fitted size afterward.
void copyCb(Widget)
{
    if (!img) return;
    int previewW = img.w(), previewH = img.h();
    img.scale(img.dataW(), img.dataH());
    auto surface = new CopySurface(img.w(), img.h());
    auto tmp = new Box(Boxtype.noBox, 0, 0, img.w(), img.h(), "");
    tmp.alignment(alignImageBackdrop);
    tmp.image(img);
    surface.draw(tmp);
    destroy(tmp);
    destroy(surface);
    img.scale(previewW, previewH);
}

void main(string[] args)
{
    int i = 1;

    registerImages();
    loadSystemIcons();

    fl.argsToUtf8(args);
    fl.args(args, i, (a, ref j) => arg(a, j));

    if (animate)
        GifImage.animate = true; // create animated shared .GIF images (e.g. file chooser)

    w = new DoubleWindow(400, 450);
    b = new Box(10, 45, 380, 380);
    b.box(Boxtype.thinDownBox);
    b.alignment(alignInside | alignCenter | alignClip);
    auto button = new Button(150, 5, 100, 30, "load");
    button.callback((wgt) { buttonCb(wgt); });
    if (!dvisual) fl.visual(modeRgb);
    if (args.length > 1) loadFile(args[1]);
    w.resizable(b);
    auto print = new Button(300, 425, 50, 25, "Print");
    print.callback((wgt) { printCb(wgt); });
    auto svg = new Button(190, 425, 100, 25, "save as SVG");
    svg.callback((wgt) { svgCb(wgt); });
    auto copy = new Button(100, 425, 80, 25, "Copy");
    copy.callback((wgt) { copyCb(wgt); });

    w.show(args);
    if (animate)
        fl.addTimeout(1.0 / 10, () { cbForcedRedraw(null); }); // force periodic redraw
    fl.run();
}
