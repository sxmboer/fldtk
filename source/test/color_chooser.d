// D transliteration of FLTK's test/color_chooser.cxx.
// Build: rdmd buildsamples.d test color_chooser
import fl;
import std.format : format;
import std.stdio : writefln;
import core.stdc.stdlib : exit;

int width = 100;
int height = 100;
ubyte[] image;
Box hint;

void makeImage()
{
    image = new ubyte[3 * width * height];
    size_t p = 0;
    for (int y = 0; y < height; y++)
    {
        double Y = cast(double) y / (height - 1);
        for (int x = 0; x < width; x++)
        {
            double X = cast(double) x / (width - 1);
            image[p++] = cast(ubyte)(255 * ((1 - X) * (1 - Y))); // red in upper-left
            image[p++] = cast(ubyte)(255 * ((1 - X) * Y));       // green in lower-left
            image[p++] = cast(ubyte)(255 * (X * Y));             // blue in lower-right
        }
    }
}

class Pens : Box
{
    this(int x, int y, int w, int h, string l) { super(x, y, w, h, l); }

    override void draw()
    {
        // use every color in the gray ramp:
        for (int i = 0; i < 3 * 8; i++)
        {
            fl_color(cast(Color)(grayRamp + i));
            fl_line(x() + i, y(), x() + i, y() + h());
        }
    }
}

Color c = backgroundColor; // FL_GRAY
enum Color fullcolorCell = freeColor;

void cb1(Widget, Box b)
{
    c = showColormap(c);
    b.color(c);
    hint.labelcolor(contrast(black, c));
    b.parent().redraw();
}

void cb2(Widget, Box bx)
{
    ubyte r, g, b;
    fl.getColor(c, r, g, b);
    if (!colorChooser("New color:", r, g, b, 3)) return;
    c = fullcolorCell;
    fl.setColor(fullcolorCell, r, g, b);
    bx.color(fullcolorCell);
    hint.labelcolor(contrast(black, fullcolorCell));
    bx.parent().redraw();
}

class SampleBox : Box
{
    this(int x, int y, int w, int h, string label = null) { super(x, y, w, h, label); }

    override int handle(Event event)
    {
        if (event == Event.beforeTooltip)
        {
            ubyte r, g, b;
            fl.getColor(color(), r, g, b);
            string buf;
            if ((color() & 255) && (color() != 16))
                buf = format("Background color is:\npalette no. %d = r:%d, g:%d, b:%d", color(), r, g, b);
            else
                buf = format("Background color is:\nr:%d, g:%d, b:%d", r, g, b);
            return overrideText(buf);
        }
        return super.handle(event);
    }
}

void main(string[] args)
{
    fl.setColor(fullcolorCell, 145, 159, 170);
    auto window = new Window(400, 400);
    auto box = new SampleBox(30, 30, 340, 340);
    box.tooltip("Show RGB values");
    box.box(Boxtype.thinDownBox);
    c = fullcolorCell;
    box.color(c);
    auto hintbox = new Box(40, 40, 320, 30, "Pick background color with buttons:");
    hintbox.alignment(alignInside);
    hint = hintbox;
    auto b1 = new Button(120, 80, 180, 30, "showColormap()");
    b1.callback((w) { cb1(w, box); });
    auto b2 = new Button(120, 120, 180, 30, "colorChooser()");
    b2.callback((w) { cb2(w, box); });
    auto imageBox = new Box(160, 190, width, height, null);
    makeImage();
    // Fl_Image::label(Fl_Widget*) is FLTK's own deprecated way to
    // set a widget's image (its doc comment says to use
    // Fl_Widget::image() instead) -- not ported, so use the modern
    // replacement directly.
    imageBox.image(new RGBImage(image, width, height));
    auto b = new Box(160, 310, 120, 30, "Example of drawImage()");
    auto p = new Pens(60, 180, 3 * 8, 120, "lines");
    p.alignment(alignTop);

    // FLTK parses argc/argv here to pick an X11 visual (Fl::args/
    // Fl::visual/Fl::own_colormap); dropped along with argc/argv (see
    // source/test/README.md and test/button.cxx's precedent).

    window.show(args);
    fl.run();
}
