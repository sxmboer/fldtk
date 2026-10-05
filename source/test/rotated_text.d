// D transliteration of FLTK's test/rotated_text.cxx.
// Build: rdmd buildsamples.d test rotated_text
import fl;
import std.math : PI, sin, cos;

ToggleButton leftb, rightb, clipb;
Input input;
HorValueSlider fonts;
HorValueSlider sizes;
HorValueSlider angles;
DoubleWindow window;

// code taken from fl_engraved_label.cxx
class RotatedLabelBox : Widget
{
    this(int x, int y, int w, int h, string l = null)
    {
        super(x, y, w, h, l);
        rtAngle = 0;
        rtAlign = 0;
        rtText = input.value();
    }

    int rtAngle;
    string rtText;
    Align rtAlign;

protected:
    override void draw()
    {
        drawBox();
        fl_font(labelfont(), labelsize());
        fl_color(labelcolor());
        int dx = 0, dy = 0;

        if (rtAlign & alignClip)
            pushClip(x(), y(), w(), h());
        else
            pushNoClip();
        fl_measure(rtText, dx, dy);
        if (rtAlign & alignLeft)
        {
            dx = dy = 0;
        }
        else if (rtAlign & alignRight)
        {
            dy = cast(int)(-sin(PI * cast(double)(rtAngle + 180) / 180.0) * cast(double) dx);
            dx = cast(int)(cos(PI * cast(double)(rtAngle + 180) / 180.0) * cast(double) dx);
        }
        else
        {
            dy = cast(int)(sin(PI * cast(double) rtAngle / 180.0) * cast(double) dx);
            dx = cast(int)(-cos(PI * cast(double) rtAngle / 180.0) * cast(double) dx);
            dx /= 2;
            dy /= 2;
        }
        if (labeltype() == Labeltype.shadowLabel)
            shadowLabel(x() + w() / 2 + dx, y() + h() / 2 + dy);
        else if (labeltype() == Labeltype.engravedLabel)
            engravedLabel(x() + w() / 2 + dx, y() + h() / 2 + dy);
        else if (labeltype() == Labeltype.embossedLabel)
            embossedLabel(x() + w() / 2 + dx, y() + h() / 2 + dy);
        else
        {
            fl_draw(rtAngle, rtText, x() + w() / 2 + dx, y() + h() / 2 + dy);
        }
        popClip();
        drawLabel();
    }

private:
    void innards(int X, int Y, int[3][] data, int n)
    {
        for (int i = 0; i < n; i++)
        {
            fl_color(cast(Color)(i < n - 1 ? data[i][2] : labelcolor()));
            fl_draw(rtAngle, rtText, X + data[i][0], Y + data[i][1]);
        }
    }

    void shadowLabel(int X, int Y)
    {
        static int[3][2] data = [[2, 2, dark3], [0, 0, 0]];
        innards(X, Y, data, 2);
    }

    void engravedLabel(int X, int Y)
    {
        static int[3][7] data = [
            [1, 0, light3], [1, 1, light3], [0, 1, light3],
            [-1, 0, dark3], [-1, -1, dark3], [0, -1, dark3],
            [0, 0, 0],
        ];
        innards(X, Y, data, 7);
    }

    void embossedLabel(int X, int Y)
    {
        static int[3][7] data = [
            [-1, 0, light3], [-1, -1, light3], [0, -1, light3],
            [1, 0, dark3], [1, 1, dark3], [0, 1, dark3],
            [0, 0, 0],
        ];
        innards(X, Y, data, 7);
    }
}

RotatedLabelBox text;

void buttonCb(Widget)
{
    int i = 0;
    if (leftb.value())
        i |= alignLeft;
    if (rightb.value())
        i |= alignRight;
    if (clipb.value())
        i |= alignClip;
    text.rtAlign = cast(Align) i;
    window.redraw();
}

void fontCb(Widget)
{
    text.labelfont(cast(Font) fonts.value());
    window.redraw();
}

void sizeCb(Widget)
{
    text.labelsize(cast(Fontsize) sizes.value());
    window.redraw();
}

void angleCb(Widget)
{
    text.rtAngle = cast(int) angles.value();
    window.redraw();
}

void inputCb(Widget)
{
    text.rtText = input.value();
    window.redraw();
}

void normalCb(Widget)
{
    text.labeltype(Labeltype.normalLabel);
    window.redraw();
}

void shadowCb(Widget)
{
    text.labeltype(Labeltype.shadowLabel);
    window.redraw();
}

void embossedCb(Widget)
{
    text.labeltype(Labeltype.embossedLabel);
    window.redraw();
}

void engravedCb(Widget)
{
    text.labeltype(Labeltype.engravedLabel);
    window.redraw();
}

// Labels use fldtk's own D spelling -- `Labeltype` is a closed enum, so
// shown qualified (`Labeltype.normalLabel`), matching what a D programmer
// actually types -- not FLTK's C `FL_*` macro name. See CONVENTIONS.md's
// memory notes on this standing rule for GUI text that names a constant.
MenuItem[] choices = [
    MenuItem("Labeltype.normalLabel", 0, (w) { normalCb(w); }),
    MenuItem("Labeltype.shadowLabel", 0, (w) { shadowCb(w); }),
    MenuItem("Labeltype.engravedLabel", 0, (w) { engravedCb(w); }),
    MenuItem("Labeltype.embossedLabel", 0, (w) { embossedCb(w); }),
    MenuItem(null),
];

void main(string[] args)
{
    window = new DoubleWindow(400, 425);

    angles = new HorValueSlider(50, 400, 350, 25, "Angle:");
    angles.alignment(alignLeft);
    angles.bounds(-360, 360);
    angles.step(1);
    angles.value(0);
    angles.callback((w) { angleCb(w); });

    input = new Input(50, 375, 350, 25);
    input.staticValue("Rotate Me!!!");
    input.when(whenChanged);
    input.callback((w) { inputCb(w); });

    sizes = new HorValueSlider(50, 350, 350, 25, "Size:");
    sizes.alignment(alignLeft);
    sizes.bounds(1, 64);
    sizes.step(1);
    sizes.value(14);
    sizes.callback((w) { sizeCb(w); });

    fonts = new HorValueSlider(50, 325, 350, 25, "Font:");
    fonts.alignment(alignLeft);
    fonts.bounds(0, 15);
    fonts.step(1);
    fonts.value(0);
    fonts.callback((w) { fontCb(w); });

    auto g = new FlGroup(50, 300, 350, 25);
    leftb = new ToggleButton(50, 300, 50, 25, "left");
    leftb.callback((w) { buttonCb(w); });
    rightb = new ToggleButton(100, 300, 50, 25, "right");
    rightb.callback((w) { buttonCb(w); });
    clipb = new ToggleButton(350, 300, 50, 25, "clip");
    clipb.callback((w) { buttonCb(w); });
    g.resizable(rightb);
    g.end();

    auto c = new Choice(50, 275, 200, 25);
    c.menu(choices);

    text = new RotatedLabelBox(100, 75, 200, 100, "Widget with rotated text");
    text.box(Boxtype.engravedBox);
    text.alignment(alignBottom);
    window.resizable(text);
    window.end();
    window.show(args);
    fl.run();
}
