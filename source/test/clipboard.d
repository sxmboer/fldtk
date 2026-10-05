// D transliteration of FLTK's test/clipboard.cxx.
// Build: rdmd buildsamples.d test clipboard
import fl;
// fl.box's Box is the port of Fl_Box; this program's local "class chess :
// public Fl_Box" needs the real base type, no name collision here since
// the local class keeps its own FLTK name (chess).
import fl.png_image : writePng;
import fl.jpeg_image : writeJpeg;
import std.format : format;

/* Displays and follows the content of the clipboard with either image or text data
 */

Box imageBox;    // to view an image
Box imageSize;   // to view image size
TextDisplay display; // to view clipboard text
Flex flex;       // flexible button layout
Button save;     // save PNG
Button saveJpeg; // save JPEG
CheckButton wrap; // wrap mode
RGBImage clImg;  // image from clipboard

int flMin(int a, int b) { return a < b ? a : b; }

// a box with a chess-like pattern below its image
class Chess : Box
{
    this(int x, int y, int w, int h)
    {
        super(Boxtype.flatBox, x, y, w, h, null);
        alignment(alignCenter | alignClip);
    }

    override void draw()
    {
        drawBox();
        Image img = image();
        if (img !is null) // draw the chess pattern below the box centered image
        {
            int X = x() + (w() - img.w()) / 2;
            int Y = y() + (h() - img.h()) / 2;
            int W = img.w();
            int H = img.h();
            pushClip(X, Y, W, H);
            pushClip(x(), y(), w(), h());
            fl_color(white);
            fl_rectf(X, Y, W, H);
            fl_color(light2);
            enum side = 4, side2 = 2 * side;
            for (int j = Y; j < Y + H; j += side)
                for (int i = X + (j - Y) % side2; i < X + W; i += side2)
                    fl_rectf(i, j, side, side);
            popClip();
            popClip();
        }
        drawLabel(); // draw the box image
    }
}

enum Color tabColor = dark3;

// use tabs to display either the image or textual content of the clipboard
class ClipboardViewer : Tabs
{
    this(int x, int y, int w, int h) { super(x, y, w, h); }

    void layout() // re-arrange buttons depending on tab
    {
        if (value() is display) // text
        {
            save.hide();
            saveJpeg.hide();
            wrap.show();
        }
        else // image
        {
            save.show();
            saveJpeg.show();
            wrap.hide();
        }
        flex.layout();
    }

    override int handle(Event event)
    {
        if (event != Event.paste)
        {
            auto val = value();
            int ret = super.handle(event);
            if (value() !is val) // tabs have been changed
                layout();
            return ret;
        }
        if (fl.eventClipboardType() == fl.clipboardImage) // an image is being pasted
        {
            clImg = cast(RGBImage) fl.eventClipboard(); // get it as an Fl_RGB_Image object
            Image oldimg = imageBox.image();
            if (clImg is null)
            {
                // Deviates from FLTK here (which just does `if
                // (!cl_img) return 1;`): rather than silently doing
                // nothing, switch to the image tab and say so, so a
                // paste that was detected but couldn't be decoded still
                // leaves a visible sign something happened.
                destroy(oldimg);
                imageBox.image(null);
                imageSize.copyLabel("Clipboard image detected, but its format isn't decodable yet");
                value(imageBox.parent());
                window().redraw();
                layout();
                return 1;
            }
            string title = format("%dx%d", clImg.w(), clImg.h()); // display the image original size

            destroy(oldimg);
            if (clImg.w() > imageBox.w() || clImg.h() > imageBox.h())
                clImg.scale(imageBox.w(), imageBox.h());
            imageBox.image(clImg); // show the scaled image
            imageSize.copyLabel(title);
            value(imageBox.parent());
            window().redraw();
        }
        else // text is being pasted
        {
            display.buffer().text(fl.eventText());
            value(display);
            display.redraw();
        }
        layout();
        return 1;
    }
}

// clipboard viewer refresh callback:
// argument must be `ClipboardViewer`
void refreshCb(ClipboardViewer tabs)
{
    if (fl.clipboardContains(fl.clipboardImage))
    {
        fl.paste(tabs, 1, fl.clipboardImage); // try to find image in the clipboard
        return;
    }
    if (fl.clipboardContains(fl.clipboardPlainText))
        fl.paste(tabs, 1, fl.clipboardPlainText); // also try to find text
}

// "Save PNG" callback
void saveCb(Widget)
{
    if (clImg !is null && !clImg.fail())
    {
        auto fnfc = new NativeFileChooser();
        fnfc.title("Please select a .png file");
        fnfc.type(BrowseType.browseSaveFile);
        fnfc.filter("PNG\t*.png\n");
        fnfc.options(saveasConfirm | useFilterExt);
        if (fnfc.show()) return;
        string filename = fnfc.filename();
        if (filename !is null && writePng(filename, clImg) != 0)
            message(format("Failed to save %s", filename));
    }
    else
    {
        message("No image available");
    }
}

// "Save JPEG" callback
void saveJpegCb(Widget)
{
    if (clImg !is null && !clImg.fail())
    {
        auto fnfc = new NativeFileChooser();
        fnfc.title("Please select a .jpg file");
        fnfc.type(BrowseType.browseSaveFile);
        fnfc.filter("JPEG\t*.jpg\n");
        fnfc.options(saveasConfirm | useFilterExt);
        if (fnfc.show()) return;
        string filename = fnfc.filename();
        if (filename !is null && writeJpeg(filename, clImg) != 0)
            message(format("Failed to save %s", filename));
    }
    else
    {
        message("No image available");
    }
}

// "wrap mode" callback (switch wrapping on/off)
void wrapCb(Widget w, TextDisplay disp)
{
    auto wrapButton = cast(CheckButton) w;
    if (wrapButton.value())
        disp.wrapMode(WrapMode.wrapAtBounds, 0);
    else
        disp.wrapMode(WrapMode.wrapNone, 0);
    disp.redraw();
}

// called after clipboard was changed or at application activation
void clipboardCb(int source, ClipboardViewer tabs)
{
    if (source == 1) refreshCb(tabs);
}

void main(string[] args)
{
    fl.registerImages(); // required for the X11 platform to allow pasting of images
    auto win = new Window(500, 550, "FLTK Clipboard Viewer");
    auto tabs = new ClipboardViewer(0, 0, 500, 500);
    auto g = new FlGroup(5, 30, 490, 460, fl.clipboardImage); // will display the image form
    g.box(Boxtype.flatBox);
    imageBox = new Chess(5, 30, 490, 440);
    imageSize = new Box(Boxtype.noBox, 5, 472, 490, 16, null);
    imageSize.alignment(alignCenter | alignClip);
    g.end();
    g.resizable(imageBox);
    g.selectionColor(tabColor);

    auto buffer = new TextBuffer();
    display = new TextDisplay(5, 40, 490, 455, fl.clipboardPlainText); // will display the text form
    display.buffer(buffer);
    display.selectionColor(tabColor);
    display.textfont(courier); // use fixed font for text display
    tabs.end();
    tabs.resizable(display);

    flex = new Flex(0, 510, 550, 25); // flexible button layout
    flex.type(flexHorizontal);
    flex.margin(10, 0, 10, 0);        // margins: left, top, right, bottom
    flex.gap(10);

    auto refresh = new Button(0, 0, 0, 0, "Refresh from clipboard");
    flex.fixed(refresh, 200);
    refresh.callback((w) { refreshCb(tabs); });

    save = new Button(0, 0, 0, 0, "Save PNG");
    flex.fixed(save, 120);
    save.callback((w) { saveCb(w); });

    saveJpeg = new Button(0, 0, 0, 0, "Save JPEG");
    flex.fixed(saveJpeg, 120);
    saveJpeg.callback((w) { saveJpegCb(w); });

    wrap = new CheckButton(0, 0, 0, 0, "wrap mode");
    flex.fixed(wrap, 120);
    wrap.callback((w) { wrapCb(w, display); });
    wrap.box(Boxtype.upBox);
    wrap.visibleFocus(false);
    wrap.value(false);

    flex.end();
    win.end();
    win.resizable(tabs);
    win.sizeRange(380, 300);
    win.show(args);

    clipboardCb(1, tabs); // use clipboard content at start
    fl.addClipboardNotify((source) { clipboardCb(source, tabs); });
    Image.rgbScaling(Image.RGBScaling.bilinear); // set bilinear image scaling method
    fl.run();
}
