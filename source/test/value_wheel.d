// fldtk test program: changing values with the mouse wheel.
// Build: rdmd buildsamples.d test value_wheel
//
// Every value widget, each with a step of 1 and a readout of its value
// and of the wheel movement the platform reported (dx: sideways, right
// positive; dy: down positive). Point at one and turn the wheel.
import fl;
import std.format : format;

void main(string[] args)
{
    auto win = new Window(520, 600, "Value widgets and the mouse wheel");

    auto help = new Box(20, 10, 480, 85,
        "Point at a widget and turn the wheel: a notch is 10 steps, "
        ~ "1 with Shift held, 100 with Ctrl. Up, or a sideways wheel to "
        ~ "the right, adds. The adjuster's notch is the speed of the "
        ~ "button under the mouse. Sliders and dials can still be dragged. "
        ~ "The positioner's wheel moves its crosshair: up and down for y, "
        ~ "sideways for x.");
    help.alignment(alignInside | alignLeft | alignTop | alignWrap);
    help.labelsize(13);

    auto readout = new Box(20, 550, 480, 30, "Turn the wheel over a widget");
    readout.box(Boxtype.downBox);
    readout.color(white);

    void showText(string s)
    {
        if (event() == Event.mouseWheel)
            s ~= format("   (wheel dx=%d dy=%d)", eventDx(), eventDy());
        readout.copyLabel(s);
    }

    void show(string name, double value)
    {
        showText(format("%s: %g", name, value));
    }

    void watch(Valuator v, string name)
    {
        v.bounds(0, 1000);
        v.step(1);
        v.value(500);
        v.callback((w) { show(name, (cast(Valuator) w).value()); });
    }

    int y = 100;
    auto vi = new ValueInput(120, y, 100, 25, "ValueInput");
    watch(vi, "ValueInput");

    y += 40;
    auto co = new Counter(120, y, 150, 25, "Counter");
    co.alignment(alignLeft);
    watch(co, "Counter");
    auto ad = new Adjuster(370, y, 75, 25, "Adjuster");
    ad.alignment(alignLeft);
    watch(ad, "Adjuster");
    auto adOut = new ValueOutput(450, y, 50, 25);
    ad.callback((w) {
        adOut.value(ad.value());
        show("Adjuster", ad.value());
    });
    adOut.value(ad.value());

    y += 40;
    auto sp = new Spinner(120, y, 100, 25, "Spinner");
    sp.range(0, 1000);
    sp.step(1);
    sp.value(500);
    sp.callback((w) { show("Spinner", sp.value()); });

    y += 40;
    auto hs = new ValueSlider(120, y, 380, 25, "ValueSlider");
    hs.type(horSlider);
    hs.alignment(alignLeft);
    watch(hs, "Horizontal ValueSlider");

    y += 40;
    auto vs = new Slider(30, y, 25, 150, "Slider");
    watch(vs, "Vertical Slider");
    auto ro = new Roller(130, y, 25, 150, "Roller");
    watch(ro, "Roller");
    auto di = new Dial(230, y + 20, 100, 100, "Dial");
    watch(di, "Dial");
    auto hsl = new Slider(360, y + 10, 140, 25, "Horizontal Slider");
    hsl.type(horSlider);
    watch(hsl, "Horizontal Slider");
    auto hro = new Roller(360, y + 80, 140, 25, "Horizontal Roller");
    hro.type(horizontalType);
    watch(hro, "Horizontal Roller");

    y += 170;
    auto po = new Positioner(120, y, 200, 100, "Positioner");
    po.alignment(alignLeft);
    po.xbounds(0, 1000);
    po.ybounds(0, 1000);
    po.xstep(1);
    po.ystep(1);
    po.value(500, 500);
    po.callback((w) { showText(format("Positioner: x=%g y=%g", po.xvalue(), po.yvalue())); });

    win.end();
    win.show(args);
    run();
}
