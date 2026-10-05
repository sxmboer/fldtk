// D transliteration of FLTK's examples/howto-draw-an-x.cxx.
// Build: rdmd buildsamples.d examples howto_draw_an_x
import fl;

class DrawX : Widget
{
    this(int X, int Y, int W, int H, string L = null)
    {
        super(X, Y, W, H, L);
    }

    override void draw()
    {
        // Draw background - a white filled rectangle
        fl_color(white);
        fl_rectf(x(), y(), w(), h());
        // Draw black 'X' over base widget's background
        fl_color(black);
        int x1 = x(), y1 = y();
        int x2 = x() + w() - 1, y2 = y() + h() - 1;
        fl_line(x1, y1, x2, y2);
        fl_line(x1, y2, x2, y1);
    }
}

void main()
{
    auto win = new DoubleWindow(200, 200, "Draw X");
    auto drawX = new DrawX(10, 10, win.w() - 20, win.h() - 20); // put our widget 10 pixels within window edges
    drawX.color(white); // make widget's background white
    win.resizable(drawX);
    win.show();
    fl.run();
}
