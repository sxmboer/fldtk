// Pen and tablet test: every part of fldtk's pen API (fl.pen), to try a
// stylus on Windows, Wayland, or a tablet: what the driver and the pen
// report, every value live, the events as they arrive, and a canvas that
// draws with pressure, tilt, the barrel buttons and the eraser.
//
// Build: rdmd buildsamples.d examples pen_test
//
// What to try:
// - Hover over the canvas: the red crosshair follows the pen; the green
//   line shows the tilt, the blue tick the twist, the gray circle the
//   distance from the surface (pens that report them).
// - Draw: the line is as thick as the pressure; hold a barrel button for
//   another color; turn the pen over to erase with its eraser end.
// - The panel shows every value and which state bits are set; the
//   traits show what the driver and this pen can report.
// - The log lists the events; "Log hover/draw" adds the frequent ones.
// - The small canvas is a subwindow: its crosshair must sit under the pen
//   too. "Unsubscribed button" isn't subscribed, so the pen clicks it as
//   a mouse would. "Modal dialog" checks that the canvases get no pen
//   events while a modal window is open.

import fl;
import std.format : format;
import std.math : sin, cos, PI;

Browser logView;
CheckButton logMotion;
ValuePanel panel;

/// Adds a line to the event log, keeping it short and scrolled down.
void log(string s)
{
    logView.add(s);
    while (logView.size() > 300) logView.remove(1);
    logView.bottomline(logView.size());
}

/// A pen event's name and the change that caused it.
string describe(Event e)
{
    string trigger;
    auto t = Pen.eventTrigger();
    foreach (name, bit; stateBits) if (t & bit) trigger ~= (trigger.length ? "|" : "") ~ name;
    return format("%-22s pen %d  (%.1f, %.1f)%s", eventNameStr(e), Pen.eventPenId(),
        Pen.eventX(), Pen.eventY(), trigger.length ? "  trigger " ~ trigger : "");
}

immutable Pen.State[string] stateBits;
immutable string[] stateOrder = ["tipHovers", "tipDown", "eraserHovers", "eraserDown",
    "button0", "button1", "button2", "button3"];
immutable Pen.Trait[string] traitBits;
immutable string[] traitOrder = ["driverAvailable", "detected", "display", "penId", "eraser",
    "pressure", "barrelPressure", "tiltX", "tiltY", "twist", "proximity"];

shared static this()
{
    stateBits = [
        "tipHovers": Pen.State.tipHovers, "tipDown": Pen.State.tipDown,
        "eraserHovers": Pen.State.eraserHovers, "eraserDown": Pen.State.eraserDown,
        "button0": Pen.State.button0, "button1": Pen.State.button1,
        "button2": Pen.State.button2, "button3": Pen.State.button3,
    ];
    traitBits = [
        "driverAvailable": Pen.Trait.driverAvailable, "detected": Pen.Trait.detected,
        "display": Pen.Trait.display, "penId": Pen.Trait.penId, "eraser": Pen.Trait.eraser,
        "pressure": Pen.Trait.pressure, "barrelPressure": Pen.Trait.barrelPressure,
        "tiltX": Pen.Trait.tiltX, "tiltY": Pen.Trait.tiltY, "twist": Pen.Trait.twist,
        "proximity": Pen.Trait.proximity,
    ];
}

/// A drawing canvas taking the pen: strokes in an offscreen buffer, and
/// an overlay showing where the pen is and how it is held.
class Canvas
{
    Widget widget;
    bool inWindow;          // the canvas is a window (coordinates start at 0)
    Offscreen buffer;
    float scale = 0;        // the scale the buffer is at
    bool hovering, drawing;
    double px, py;          // the pen, in the widget's window
    double lastX, lastY;    // the previous point of the stroke

    this(Widget w, bool inWindow)
    {
        widget = w;
        this.inWindow = inWindow;
    }

    int ox() { return inWindow ? 0 : widget.x(); }
    int oy() { return inWindow ? 0 : widget.y(); }

    void clear()
    {
        if (buffer == Offscreen.init) return;
        beginOffscreen(buffer);
        fl_color(white);
        fl_rectf(0, 0, widget.w(), widget.h());
        endOffscreen();
        widget.redraw();
    }

    /// The stroke's color: black, blue with button 0, red with button 1,
    /// green with buttons 2 or 3; white (erasing) with the eraser.
    Color strokeColor()
    {
        if (Pen.eventState(Pen.State.eraserDown)) return white;
        if (Pen.eventState(Pen.State.button0)) return blue;
        if (Pen.eventState(Pen.State.button1)) return red;
        if (Pen.eventState(Pen.State.button2 | Pen.State.button3)) return darkGreen;
        return black;
    }

    void stroke()
    {
        double p = Pen.eventPressure();
        int width = 1 + cast(int)(p * p * 24);
        if (Pen.eventState(Pen.State.eraserDown)) width = 8 + cast(int)(p * 40);
        beginOffscreen(buffer);
        fl_color(strokeColor());
        lineStyle(lineSolid | capRound | joinRound, width);
        fl_line(cast(int)(lastX - ox()), cast(int)(lastY - oy()), cast(int)(px - ox()), cast(int)(py - oy()));
        lineStyle(lineSolid);
        endOffscreen();
        lastX = px;
        lastY = py;
    }

    int handle(Event e)
    {
        switch (e)
        {
            case Event.penDetected, Event.penChanged, Event.penInRange, Event.penOutOfRange:
                log(describe(e));
                panel.update(e);
                return 1;
            case Event.penEnter:
                hovering = true;
                goto case Event.penHover;
            case Event.penHover:
                px = Pen.eventX();
                py = Pen.eventY();
                break;
            case Event.penTouch:
                drawing = true;
                px = lastX = Pen.eventX();
                py = lastY = Pen.eventY();
                stroke();
                break;
            case Event.penDraw:
                px = Pen.eventX();
                py = Pen.eventY();
                if (drawing && Pen.eventState(Pen.State.tipDown | Pen.State.eraserDown)) stroke();
                break;
            case Event.penLift:
                drawing = false;
                break;
            case Event.penLeave:
                hovering = drawing = false;
                break;
            case Event.penButtonPush, Event.penButtonRelease:
                break;
            default:
                return 0;
        }
        bool frequent = e == Event.penHover || e == Event.penDraw;
        if (!frequent || logMotion.value()) log(describe(e));
        panel.update(e);
        widget.redraw();
        return 1; // take the pen: no mouse events while it is over the canvas
    }

    void draw()
    {
        if (buffer == Offscreen.init)
        {
            buffer = createOffscreen(widget.w(), widget.h());
            scale = fl_graphics_driver.scale();
            clear();
        }
        else if (fl_graphics_driver.scale() != scale)
        {
            // the window moved to a screen with another scale, or Ctrl +/-
            rescaleOffscreen(buffer);
            scale = fl_graphics_driver.scale();
        }
        pushClip(ox(), oy(), widget.w(), widget.h());
        copyOffscreen(ox(), oy(), widget.w(), widget.h(), buffer, 0, 0);
        if (hovering)
        {
            int x = cast(int) px, y = cast(int) py;
            // distance from the surface
            if (Pen.penTraits(Pen.Trait.proximity) && !drawing)
            {
                int r = 4 + cast(int)(Pen.eventProximity() * 40);
                fl_color(gray);
                fl_arc(x - r, y - r, 2 * r, 2 * r, 0, 360);
            }
            // tilt: where the pen leans
            fl_color(darkGreen);
            lineStyle(lineSolid, 2);
            fl_line(x, y, x + cast(int)(Pen.eventTiltX() * 60), y + cast(int)(Pen.eventTiltY() * 60));
            // twist: a tick turning with the pen
            double a = Pen.eventTwist() * PI / 180;
            fl_color(blue);
            fl_line(x + cast(int)(sin(a) * 14), y - cast(int)(cos(a) * 14),
                x + cast(int)(sin(a) * 24), y - cast(int)(cos(a) * 24));
            lineStyle(lineSolid);
            // the tip
            fl_color(red);
            fl_xyline(x - 10, y, x + 10);
            fl_yxline(x, y - 10, y + 10);
        }
        popClip();
    }
}

class CanvasWidget : Widget
{
    Canvas canvas;
    this(int x, int y, int w, int h, string l = null)
    {
        super(x, y, w, h, l);
        canvas = new Canvas(this, false);
    }
    override int handle(Event e) { auto r = canvas.handle(e); return r ? r : super.handle(e); }
    override void draw() { canvas.draw(); }
}

class CanvasWindow : DoubleWindow
{
    Canvas canvas;
    this(int x, int y, int w, int h, string l = null)
    {
        super(x, y, w, h, l);
        canvas = new Canvas(this, true);
    }
    override int handle(Event e) { auto r = canvas.handle(e); return r ? r : super.handle(e); }
    override void draw() { canvas.draw(); }
}

/// Every pen value, the state and trigger bits, and the traits.
class ValuePanel : Widget
{
    string eventName = "(no pen event yet)";

    this(int x, int y, int w, int h) { super(x, y, w, h); }

    void update(Event e)
    {
        eventName = eventNameStr(e);
        redraw();
    }

    override void draw()
    {
        drawBox(Boxtype.downBox, backgroundColor);
        pushClip(x() + 2, y() + 2, w() - 4, h() - 4);
        fl_font(helvetica, 12);
        int lx = x() + 8, ly = y() + 16;
        void line(string s, Color c = black)
        {
            fl_color(c);
            fl_draw(s, lx, ly);
            ly += 16;
        }
        line("Event: " ~ eventName, blue);
        line(format("Pen id: %d", Pen.eventPenId()));
        line(format("Position: %.2f, %.2f   root %.2f, %.2f",
            Pen.eventX(), Pen.eventY(), Pen.eventXRoot(), Pen.eventYRoot()));

        // gauges
        void bar(string name, double v, double lo, double hi, string text)
        {
            fl_color(black);
            fl_draw(name, lx, ly);
            int bx = lx + 110, bw = 140, by = ly - 10;
            fl_color(white);
            fl_rectf(bx, by, bw, 12);
            fl_color(rgbColor(70, 130, 220));
            double t = (v - lo) / (hi - lo);
            if (t < 0) t = 0;
            if (t > 1) t = 1;
            if (lo < 0)
            {
                int mid = bx + bw / 2, end = bx + cast(int)(t * bw);
                fl_rectf(mid < end ? mid : end, by, mid < end ? end - mid : mid - end, 12);
            }
            else
                fl_rectf(bx, by, cast(int)(t * bw), 12);
            fl_color(black);
            fl_rect(bx, by, bw, 12);
            fl_draw(text, bx + bw + 8, ly);
            ly += 18;
        }
        bar("Pressure", Pen.eventPressure(), 0, 1, format("%.3f", Pen.eventPressure()));
        bar("Barrel pressure", Pen.eventBarrelPressure(), -1, 1, format("%.3f", Pen.eventBarrelPressure()));
        bar("Tilt X", Pen.eventTiltX(), -1, 1, format("%.3f", Pen.eventTiltX()));
        bar("Tilt Y", Pen.eventTiltY(), -1, 1, format("%.3f", Pen.eventTiltY()));
        bar("Twist", Pen.eventTwist(), -180, 180, format("%.1f deg", Pen.eventTwist()));
        bar("Proximity", Pen.eventProximity(), 0, 1, format("%.3f", Pen.eventProximity()));

        // state and trigger bits
        ly += 4;
        line("State bits (filled: set; red frame: the trigger):");
        int bx = lx;
        foreach (name; stateOrder)
        {
            bool on = Pen.eventState(stateBits[name]);
            bool trig = (Pen.eventTrigger() & stateBits[name]) != 0;
            int bw = 12 + cast(int) name.length * 7;
            if (bx + bw > x() + w() - 8)
            {
                bx = lx;
                ly += 22;
            }
            fl_color(on ? rgbColor(120, 200, 120) : white);
            fl_rectf(bx, ly - 13, bw, 18);
            fl_color(trig ? red : black);
            fl_rect(bx, ly - 13, bw, 18);
            fl_color(black);
            fl_draw(name, bx + 5, ly);
            bx += bw + 4;
        }
        ly += 28;

        // traits
        line("Traits: driver / this pen");
        foreach (i, name; traitOrder)
        {
            int col = cast(int)(i % 2), row = cast(int)(i / 2);
            int tx = lx + col * 200, ty = ly + row * 16;
            void light(int at, bool on)
            {
                fl_color(on ? rgbColor(60, 180, 60) : rgbColor(200, 200, 200));
                fl_rectf(at, ty - 10, 10, 10);
            }
            light(tx, Pen.driverTraits(traitBits[name]));
            light(tx + 14, Pen.penTraits(traitBits[name]));
            fl_color(black);
            fl_draw(name, tx + 30, ty);
        }
        popClip();
    }
}

void main(string[] args)
{
    auto window = new DoubleWindow(980, 640, "Pen test");

    auto canvasWidget = new CanvasWidget(10, 10, 520, 400);
    auto sub = new CanvasWindow(540, 10, 160, 160, "subwindow");
    sub.end();
    panel = new ValuePanel(710, 10, 260, 400);
    panel.labelsize(11);

    auto clearButton = new Button(10, 420, 100, 25, "Clear");
    clearButton.callback((w) {
        canvasWidget.canvas.clear();
        sub.canvas.clear();
    });

    auto subscribed = new CheckButton(120, 420, 150, 25, "Canvas subscribed");
    subscribed.value(true);
    subscribed.callback((w) {
        if (subscribed.value()) Pen.subscribe(canvasWidget);
        else Pen.unsubscribe(canvasWidget);
        log(subscribed.value() ? "canvas subscribed" : "canvas unsubscribed: the pen acts as a mouse there");
    });

    logMotion = new CheckButton(280, 420, 140, 25, "Log hover/draw");

    auto mouseButton = new Button(540, 180, 160, 40, "Unsubscribed button");
    mouseButton.tooltip("Not subscribed: the pen clicks it as a mouse");
    mouseButton.callback((w) { log("unsubscribed button clicked (the pen acting as a mouse)"); });

    auto modalButton = new Button(540, 230, 160, 40, "Modal dialog");
    modalButton.callback((w) {
        message("No canvas should receive pen events while this dialog is open.");
    });

    auto info = new Box(540, 280, 160, 130,
        "The canvases take the pen. Draw; hover; tilt and twist the pen; press its buttons; erase.");
    info.alignment(alignWrap | alignInside | alignTop | alignLeft);
    info.labelsize(12);

    logView = new Browser(10, 455, 960, 175);
    logView.textfont(courier);
    logView.textsize(12);

    window.end();
    window.resizable(logView);

    Pen.subscribe(canvasWidget);
    Pen.subscribe(sub);

    log(Pen.driverTraits(Pen.Trait.driverAvailable)
        ? "This platform has a pen driver; bring the pen near the tablet."
        : "No pen driver here (X11, or Windows before 8): the pen acts as a mouse.");
    window.show(args);
    sub.show();
    fl.run();
}
