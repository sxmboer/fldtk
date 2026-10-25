// Touch and gesture test: everything fl.touch provides, to try a
// touchscreen and a touchpad on Wayland, X11 or Windows.
//
// Build: rdmd buildsamples.d examples touch_test
//
// What to try:
// - Raw touch (left): this area subscribes to touch, so every finger on
//   it is shown with its number and its trail, and makes no mouse events.
// - Touch as mouse (middle): tap the buttons, drag the slider, tap the
//   check button; two fingers scroll the list, the content following them.
// - Gestures (right): pinch to zoom the square, turn two fingers to turn
//   it; on a touchpad also pinch, and swipe with three or four fingers.
//   The values of the last gesture event are shown below it. "Reset"
//   puts the square back.
// - The log lists the touch and gesture events.

import fl;
import std.format : format;
import std.math : sin, cos, PI;

Browser logView;

void log(string s)
{
    logView.add(s);
    while (logView.size() > 300) logView.remove(1);
    logView.bottomline(logView.size());
}

string phaseName(GesturePhase p)
{
    final switch (p)
    {
        case GesturePhase.begin: return "begin";
        case GesturePhase.update: return "update";
        case GesturePhase.end: return "end";
        case GesturePhase.cancel: return "cancel";
    }
}

/// Shows every finger on it, by its number, with its trail.
class RawTouchArea : Widget
{
    struct Finger { int id; double x, y; double[] trail; bool down; }
    Finger[] fingers;
    static immutable Color[] colors = [red, blue, darkGreen, darkMagenta, darkCyan, darkYellow];

    this(int x, int y, int w, int h, string l) { super(x, y, w, h, l); }

    Finger* find(int id)
    {
        foreach (ref f; fingers) if (f.id == id) return &f;
        return null;
    }

    override int handle(Event e)
    {
        switch (e)
        {
            case Event.touchDown:
                fingers ~= Finger(Touch.eventId(), Touch.eventX(), Touch.eventY(),
                    [Touch.eventX(), Touch.eventY()], true);
                log(format("touchDown   id %d at %.1f, %.1f  (%d on screen)",
                    Touch.eventId(), Touch.eventX(), Touch.eventY(), Touch.count()));
                redraw();
                return 1; // take the finger
            case Event.touchMove:
                if (auto f = find(Touch.eventId()))
                {
                    f.x = Touch.eventX();
                    f.y = Touch.eventY();
                    f.trail ~= [f.x, f.y];
                }
                redraw();
                return 1;
            case Event.touchUp, Event.touchCancel:
                log(format("%s id %d", e == Event.touchUp ? "touchUp    " : "touchCancel", Touch.eventId()));
                if (auto f = find(Touch.eventId())) f.down = false;
                redraw();
                return 1;
            default:
                return super.handle(e);
        }
    }

    override void draw()
    {
        drawBox(Boxtype.downBox, white);
        pushClip(x() + 2, y() + 2, w() - 4, h() - 4);
        foreach (i, f; fingers)
        {
            fl_color(colors[f.id % colors.length]);
            lineStyle(lineSolid, 2);
            for (size_t k = 2; k + 1 < f.trail.length; k += 2)
                fl_line(cast(int) f.trail[k - 2], cast(int) f.trail[k - 1], cast(int) f.trail[k], cast(int) f.trail[k + 1]);
            lineStyle(lineSolid);
            if (f.down)
            {
                fl_arc(cast(int) f.x - 20, cast(int) f.y - 20, 40, 40, 0, 360);
                fl_font(helveticaBold, 14);
                fl_draw(format("%d", f.id), cast(int) f.x + 22, cast(int) f.y - 22);
            }
        }
        fl_color(black);
        fl_font(helvetica, 12);
        fl_draw("Raw touch: put fingers here", x() + 8, y() + 18);
        popClip();
    }

    void clear()
    {
        fingers = null;
        redraw();
    }
}

/// A square that zooms and turns with gestures, and counts swipes.
class GestureArea : Widget
{
    double zoom = 1, angle = 0;       // the square's
    double panX = 0, panY = 0;        // moved by two-finger scrolling
    int swipeX, swipeY, swipes;       // the current swipe's movement, swipes done
    string last = "(no gesture yet)";

    this(int x, int y, int w, int h, string l) { super(x, y, w, h, l); }

    override int handle(Event e)
    {
        switch (e)
        {
            case Event.zoomGesture:
                zoom *= eventZoom();
                last = format("zoom    %-6s fingers %d  zoom x%.4f (dy %d)  at %d, %d",
                    phaseName(eventGesturePhase()), eventFingers(), eventZoom(), eventDy(), eventX(), eventY());
                log(last);
                redraw();
                return 1;
            case Event.rotateGesture:
                angle += eventRotation();
                last = format("rotate  %-6s fingers %d  %.2f deg", phaseName(eventGesturePhase()),
                    eventFingers(), eventRotation());
                log(last);
                redraw();
                return 1;
            case Event.swipeGesture:
                auto phase = eventGesturePhase();
                if (phase == GesturePhase.begin) swipeX = swipeY = 0;
                swipeX += eventDx();
                swipeY += eventDy();
                if (phase == GesturePhase.end) swipes++;
                last = format("swipe   %-6s fingers %d  moved %d, %d", phaseName(phase), eventFingers(), swipeX, swipeY);
                if (phase != GesturePhase.update) log(last);
                redraw();
                return 1;
            case Event.mouseWheel:
                panX -= eventDx() * 10;
                panY -= eventDy() * 10;
                last = format("scroll  dx %d dy %d", eventDx(), eventDy());
                redraw();
                return 1;
            default:
                return super.handle(e);
        }
    }

    override void draw()
    {
        drawBox(Boxtype.downBox, white);
        pushClip(x() + 2, y() + 2, w() - 4, h() - 4);
        double cx = x() + w() / 2.0 + panX, cy = y() + h() / 2.0 + panY;
        double s = 50 * zoom, a = angle * PI / 180;
        int[8] p;
        foreach (i; 0 .. 4)
        {
            double qa = a + PI / 4 + i * PI / 2;
            p[2 * i] = cast(int)(cx + cos(qa) * s * 1.4142);
            p[2 * i + 1] = cast(int)(cy + sin(qa) * s * 1.4142);
        }
        fl_color(rgbColor(120, 170, 230));
        fl_polygon(p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7]);
        fl_color(red); // marks the square's top
        fl_line(cast(int) cx, cast(int) cy, (p[6] + p[0]) / 2, (p[7] + p[1]) / 2);
        fl_color(black);
        fl_font(helvetica, 12);
        fl_draw("Gestures: pinch, turn, swipe", x() + 8, y() + 18);
        fl_draw(format("zoom %.2f   angle %.1f deg   swipes %d", zoom, angle, swipes), x() + 8, y() + h() - 26);
        fl_draw(last, x() + 8, y() + h() - 10);
        popClip();
    }

    void reset()
    {
        zoom = 1;
        angle = panX = panY = 0;
        swipes = 0;
        redraw();
    }
}

void main(string[] args)
{
    auto window = new DoubleWindow(990, 600, "Touch test");

    auto raw = new RawTouchArea(10, 10, 320, 380, null);
    Touch.subscribe(raw);

    auto mouseGroup = new FlGroup(340, 10, 300, 380, "Touch as mouse");
    mouseGroup.box(Boxtype.engravedBox);
    mouseGroup.alignment(alignTop | alignInside);
    auto b1 = new Button(360, 40, 120, 40, "Tap me");
    b1.callback((w) { log("\"Tap me\" clicked"); });
    auto b2 = new Button(500, 40, 120, 40, "Or me");
    b2.callback((w) { log("\"Or me\" clicked"); });
    auto check = new CheckButton(360, 90, 260, 25, "A check button");
    check.callback((w) { log(format("check button %s", check.value() ? "on" : "off")); });
    auto slider = new HorSlider(360, 125, 260, 25);
    slider.callback((w) { log(format("slider %.2f", slider.value())); });
    auto list = new HoldBrowser(360, 160, 260, 220);
    foreach (i; 1 .. 101) list.add(format("Line %d: scroll with two fingers", i));
    list.callback((w) { log(format("list line %d picked", list.value())); });
    mouseGroup.end();

    auto gestures = new GestureArea(650, 10, 330, 380, null);

    auto reset = new Button(10, 400, 100, 25, "Reset");
    reset.callback((w) {
        raw.clear();
        gestures.reset();
    });
    auto note = new Box(120, 400, 860, 25,
        "Windows sends a touchpad's pinch as Ctrl + mouse wheel, so only touchscreen pinches zoom there.");
    note.alignment(alignLeft | alignInside);
    note.labelsize(12);

    logView = new Browser(10, 435, 970, 155);
    logView.textfont(courier);
    logView.textsize(12);

    window.end();
    window.resizable(logView);
    window.show(args);
    fl.run();
}
