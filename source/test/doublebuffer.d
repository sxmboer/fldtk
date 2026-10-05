// D transliteration of FLTK's test/doublebuffer.cxx.
// Build: rdmd buildsamples.d test doublebuffer
import fl;
import std.math : cos, sin, PI;

// this purposely draws each line 10 times to be slow:
void star(int w, int h, int n)
{
    pushMatrix();
    fl_translate(w / 2, h / 2);
    fl_scale(w / 2, h / 2);
    for (int i = 0; i < n; i++)
    {
        for (int j = i + 1; j < n; j++)
        {
            beginLine();
            vertex(cos(2 * PI * i / n + .1), sin(2 * PI * i / n + .1));
            vertex(cos(2 * PI * j / n + .1), sin(2 * PI * j / n + .1));
            endLine();
        }
    }
    popMatrix();
}

int[2] sides = [20, 20];

void sliderCb(Widget o, int v)
{
    sides[v] = cast(int)(cast(Slider) o).value();
    o.parent().redraw();
}

void badDraw(int w, int h, int which)
{
    fl_color(black);
    fl_rectf(0, 0, w, h);
    fl_color(white);
    star(w, h, sides[which]);
}

class SingleBlinkWindow : SingleWindow
{
    override void draw()
    {
        badDraw(w(), h(), 0);
        drawChild(child(0));
    }

    this(int x, int y, int w, int h, string l)
    {
        super(x, y, w, h, l);
        resizable(this);
    }
}

class DoubleBlinkWindow : DoubleWindow
{
    override void draw()
    {
        badDraw(w(), h(), 1);
        drawChild(child(0));
    }

    this(int x, int y, int w, int h, string l)
    {
        super(x, y, w, h, l);
        resizable(this);
    }
}

void main()
{
    auto w01 = new Window(420, 420, "SingleWindow");
    w01.box(Boxtype.flatBox);
    auto w1 = new SingleBlinkWindow(10, 10, 400, 400, "SingleWindow");
    w1.box(Boxtype.flatBox);
    w1.color(black);
    auto slider0 = new HorSlider(20, 370, 360, 25);
    slider0.range(2, 30);
    slider0.step(1);
    slider0.value(sides[0]);
    slider0.callback((w) { sliderCb(w, 0); });
    w1.end();
    w01.end();

    auto w02 = new Window(420, 420, "DoubleWindow");
    w02.box(Boxtype.flatBox);
    auto w2 = new DoubleBlinkWindow(10, 10, 400, 400, "DoubleWindow");
    w2.box(Boxtype.flatBox);
    w2.color(black);
    auto slider1 = new HorSlider(20, 370, 360, 25);
    slider1.range(2, 30);
    slider1.step(1);
    slider1.value(sides[0]);
    slider1.callback((w) { sliderCb(w, 1); });
    w2.end();
    w02.end();

    w01.show();
    w1.show();
    w02.show();
    w2.show();
    fl.run();
}
