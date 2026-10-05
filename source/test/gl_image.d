// D transliteration of FLTK's test/gl_image.cxx.
// Build: rdmd buildsamples.d test gl_image
//
// OpenGL image-drawing test: draws an Fl_Image composited over a plain
// GL polka-dot background (Fl_Gl_Window's default draw() compositing
// FLTK child widgets on top of GL), with a menu bar to pick a new image
// file, using the real `fl.gl_window`/`fl.image`/`fl.shared_image`/
// `fl.menu_bar`/`fl.menu_item` API.
import fl;

class ImageBackgroundBox : Widget
{
    this(int x, int y, int w, int h)
    {
        super(x, y, w, h, null);
    }

    override void draw()
    {
        gl_color(white);
        gl_rectf(x(), y(), w(), h());
        gl_color(color());
        int startX;
        for (int Y = y(); Y < y() + h(); Y += 5)
        {
            startX = Y % 10;
            for (int X = startX; X < w(); X += 10)
                gl_rectf(X, Y, 5, 5);
        }
        fl_color(darkBlue); // Effective only when the drawn image is a Bitmap
        Image img = image();
        if (img !is null)
            img.draw((w() - img.w()) / 2, y() + (h() - img.h()) / 2);
    }
}

void closeCb(Widget widget)
{
    fl.firstWindow().hide();
}

MenuItem[] items;

class GlImageWindow : GlWindow
{
    private Image img_;
    private ImageBackgroundBox box_;

    this(int w, int h, string t)
    {
        super(w, h, t);
        img_ = null;
        begin();
        auto bar = new MenuBar(0, 0, w, 30);
        bar.menu(items);
        box_ = new ImageBackgroundBox(0, 30, w, h - 30);
        box_.color(gray);
        end();
        resizable(box_);
    }

    void setImage(Image img)
    {
        if (img_ !is null) img_.release();
        img_ = img;
        box_.image(img);
        img.scale(box_.w(), box_.h());
        redraw();
    }

    override void resize(int x, int y, int w, int h)
    {
        super.resize(x, y, w, h);
        if (img_ !is null) img_.scale(box_.w(), box_.h());
    }

    override void draw()
    {
        super.draw(); // Draw FLTK child widgets.
    }
}

void chooserCb(Widget widget, GlImageWindow mainwin)
{
    string fname = fileChooser("select image file", "*.{png,jpg,gif,svg,svgz,xbm,xpm,ico}", null, 0);
    if (fname !is null)
    {
        SharedImage sharedImg = SharedImage.get(fname);
        if (sharedImg !is null && !sharedImg.fail())
        {
            mainwin.copyLabel(fname);
            mainwin.setImage(sharedImg);
        }
    }
}

void main(string[] args)
{
    fl.useHighResGL(true);
    registerImages();

    GlImageWindow mainwin;

    items = [
        MenuItem("File", 0, null, menuSubmenu),
        MenuItem("Choose image file…", 0, (w) { chooserCb(w, mainwin); }, 0),
        MenuItem("Quit", 0, (w) { closeCb(w); }, 0),
        MenuItem(null, 0, null, 0),
        MenuItem(null, 0, null, 0),
    ];

    mainwin = new GlImageWindow(600, 600, "GL Image Viewer");
    mainwin.show(args);
    fl.run();
    destroy(mainwin.child(1).image());
}
