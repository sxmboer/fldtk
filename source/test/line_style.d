// D transliteration of FLTK's test/line_style.cxx.
// Build: rdmd buildsamples.d test line_style
import fl;

DoubleWindow form;
Slider[9] sliders;
Choice[3] choice;
CheckButton drawLine;

class TestBox : DoubleWindow
{
    this(int x, int y, int w, int h, string l = null)
    {
        super(x, y, w, h, l);
    }

    override void draw()
    {
        super.draw();
        fl_color(rgbColor(cast(ubyte) sliders[0].value(), cast(ubyte) sliders[1].value(),
                cast(ubyte) sliders[2].value()));
        // dashes
        char[5] dashes;
        dashes[0] = cast(char) sliders[5].value();
        dashes[1] = cast(char) sliders[6].value();
        dashes[2] = cast(char) sliders[7].value();
        dashes[3] = cast(char) sliders[8].value();
        dashes[4] = 0;
        // fl_line_style()'s dashes param is a real length-bounded slice,
        // not a NUL-terminated char* the way FLTK's own
        // line_style_unscaled() reads it via strlen() -- replicate that
        // same "stop at the first zero byte" semantics here.
        size_t ndashes = 0;
        while (ndashes < 4 && dashes[ndashes] != 0) ndashes++;
        lineStyle(
            styleValues[choice[0].value()] + capValues[choice[1].value()]
                + joinValues[choice[2].value()],
            cast(int) sliders[3].value(), // width
            cast(const(ubyte)[]) dashes[0 .. ndashes]);

        // draw the defined fl_rect and fl_vertex first and then
        // the additional one-pixel line, if enabled
        // sliders[4] = x/y coordinate translation (default = 10)

        for (int i = 0; i < drawLine.value() + 1; i++)
        {
            int move = cast(int) sliders[4].value();
            fl_rect(move, move, w() - 20, h() - 20);
            beginLine();
            vertex(move + 25, move + 25);
            vertex(w() - 45 + move, h() - 45 + move);
            vertex(w() - 50 + move, move + 25);
            vertex(move + 25, h() / 2 - 10 + move);
            endLine();
            // you must reset the line type when done:
            lineStyle(lineSolid);
            fl_color(black);
        }
    }
}

TestBox test;

// MenuItem has no FLTK-style void* user_data/argument() slot (see
// fl.menu_item's own doc comment -- a callback delegate already closes
// over whatever state it needs, so the mechanism was never ported). This
// test needs the value associated with whichever item is *currently
// selected*, read back at draw() time rather than captured by a
// one-shot callback, so a parallel lookup-by-index array stands in for
// FLTK's Fl_Menu_Item::argument() instead.
immutable int[] styleValues = [lineSolid, lineDash, lineDot, lineDashDot, lineDashDotDot];
immutable int[] capValues = [0, capFlat, capRound, capSquare];
immutable int[] joinValues = [0, joinMiter, joinRound, joinBevel];

// Labels use fldtk's own bare D constant spelling (matching
// styleValues/capValues/joinValues just above -- what a D programmer
// actually types), not FLTK's C `FL_*` macro name -- see
// CONVENTIONS.md's convention on this standing rule for GUI text that
// names a constant.
MenuItem[] styleMenu = [
    MenuItem("lineSolid"),
    MenuItem("lineDash"),
    MenuItem("lineDot"),
    MenuItem("lineDashDot"),
    MenuItem("lineDashDotDot"),
    MenuItem(null),
];

MenuItem[] capMenu = [
    MenuItem("default"),
    MenuItem("capFlat"),
    MenuItem("capRound"),
    MenuItem("capSquare"),
    MenuItem(null),
];

MenuItem[] joinMenu = [
    MenuItem("default"),
    MenuItem("joinMiter"),
    MenuItem("joinRound"),
    MenuItem("joinBevel"),
    MenuItem(null),
];

void doRedraw(Widget)
{
    test.redraw();
}

void makeform(string)
{
    form = new DoubleWindow(500, 250, "lineStyle() test");
    sliders[0] = new ValueSlider(280, 10, 180, 20, "R");
    sliders[0].bounds(0, 255);
    sliders[1] = new ValueSlider(280, 30, 180, 20, "G");
    sliders[1].bounds(0, 255);
    sliders[2] = new ValueSlider(280, 50, 180, 20, "B");
    sliders[2].bounds(0, 255);
    choice[0] = new Choice(280, 70, 180, 20, "Style");
    choice[0].menu(styleMenu);
    choice[1] = new Choice(280, 90, 180, 20, "Cap");
    choice[1].menu(capMenu);
    choice[2] = new Choice(280, 110, 180, 20, "Join");
    choice[2].menu(joinMenu);
    sliders[3] = new ValueSlider(280, 130, 180, 20, "Width");
    sliders[3].bounds(0, 20);
    sliders[4] = new ValueSlider(280, 150, 180, 20, "Move");
    sliders[4].bounds(-10, 20);
    drawLine = new CheckButton(280, 170, 20, 20, "&Line");
    drawLine.alignment(alignLeft);
    new Box(305, 170, 160, 20, "add a 1-pixel black line");
    sliders[5] = new Slider(200, 210, 70, 20, "Dash");
    sliders[5].alignment(alignTopLeft);
    sliders[5].bounds(0, 40);
    sliders[6] = new Slider(270, 210, 70, 20);
    sliders[6].bounds(0, 40);
    sliders[7] = new Slider(340, 210, 70, 20);
    sliders[7].bounds(0, 40);
    sliders[8] = new Slider(410, 210, 70, 20);
    sliders[8].bounds(0, 40);
    int i;
    for (i = 0; i < 9; i++)
    {
        sliders[i].type(1);
        if (i < 5)
            sliders[i].alignment(alignLeft);
        sliders[i].callback((w) { doRedraw(w); });
        sliders[i].step(1);
    }
    sliders[0].value(255); // R
    sliders[1].value(100); // G
    sliders[2].value(100); // B
    sliders[4].value(10); // move line coordinates
    drawLine.value(0);
    drawLine.callback((w) { doRedraw(w); });
    for (i = 0; i < 3; i++)
    {
        choice[i].value(0);
        choice[i].callback((w) { doRedraw(w); });
    }
    test = new TestBox(0, 0, 200, 200);
    test.end();
    form.resizable(test);
    form.end();
}

void main(string[] args)
{
    makeform(args.length ? args[0] : null);
    form.show(args);
    fl.run();
}
