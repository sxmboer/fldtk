// D transliteration of FLTK's test/penpal.cxx.
// Build: rdmd buildsamples.d test penpal
//
// The Penpal test app is here to test pen/stylus/tablet event distribution
// in the Fl::Pen driver. Our main window has three canvases for drawing.
// The first canvas is a child of the main window. The second canvas is
// inside a group. The third canvas is a subwindow inside the main window.
// A second application window is itself yet another canvas.
//
// We can test if the events are delivered to the right receiver, if the
// mouse and pen offsets are correct. The pen implementation also reacts
// to pen pressure and angles. If handle() returns 1 when receiving
// Fl::Pen::ENTER, the event handler should not send any mouse events until
// Fl::Pen::LEAVE.
//
// FLTK mixes Fl_Widget/Fl_Window with a plain CanvasInterface base via
// C++ multiple inheritance; D classes only support single inheritance, so
// CanvasWidget/CanvasWindow below hold a CanvasInterface member and
// delegate handle()/draw() to it (composition standing in for the C++
// mixin -- the same widget/event structure, just not multiple-inherited).
import fl;
import core.stdc.stdlib : exit;

MenuItem[] appMenu;
int popupAppMenu();
Widget cv1 = null;
Window cvwin = null;

//
// The canvas interface implements incremental drawing and handles draw events.
// It also implements pressure sensitive drawing with a pen or stylus.
// And it implements an overlay plane that visualizes pen event data.
//
class CanvasInterface
{
    Widget widget_;
    bool inWindow_ = false;
    bool firstDraw_ = true;
    Offscreen offscreen_;
    Color color_ = 1;

    enum Overlay
    {
        none,
        hover,
        draw,
        penHover,
        penDraw,
    }

    Overlay overlay_ = Overlay.none;
    int ovX_ = 0;
    int ovY_ = 0;
    float scale_ = 1.0f;

    this(Widget w)
    {
        widget_ = w;
    }

    this(Window w)
    {
        widget_ = w;
        inWindow_ = true;
    }

    ~this()
    {
        if (!firstDraw_)
            deleteOffscreen(offscreen_);
    }

    // D has no C++-style out-of-class `ClassName.method()` definitions --
    // every method body must live directly in the class body, so the
    // FLTK `CanvasInterface::cvHandle()`-style out-of-line
    // definitions below are folded in here instead of forward-declared.

    //
    // Handle mouse and pen events.
    //
    int cvHandle(Event event)
    {
        switch (event)
        {
            // Event handling for pen events:
        case fl.Pen.enter: // Return 1 to receive all pen events and suppress mouse events
            // Pen entered the widget area.
            color_++;
            if (color_ > 6)
                color_ = 1;
            goto case;
        case fl.Pen.hover:
            // Pen move over the surface without touching it.
            overlay_ = Overlay.penHover;
            ovX_ = fl.eventX();
            ovY_ = fl.eventY();
            widget_.redraw();
            return 1;
        case fl.Pen.buttonPush:
            // front barrel button
            if (fl.Pen.eventState(fl.Pen.State.button0))
            {
                popupAppMenu();
                return 0;
            }
            return 0;
        case fl.Pen.touch:
            // Pen tip or eraser just touched the surface.
            if (fl.eventState(stateCtrl))
            {
                popupAppMenu();
                return 0;
            }
            goto case;
        case fl.Pen.draw:
            // Pen is dragged over the surface, or hovers with a button pressed.
            if (fl.Pen.eventState(fl.Pen.State.tipDown | fl.Pen.State.eraserDown))
            {
                overlay_ = Overlay.penDraw;
                ovX_ = fl.eventX();
                ovY_ = fl.eventY();
                cvPenPaint();
                widget_.redraw();
            }
            return 1;
        case fl.Pen.lift:
            // Pen was just lifted from the surface and is now hovering
            return 1;
        case fl.Pen.leave:
            // The pen left the drawing area.
            overlay_ = Overlay.none;
            widget_.redraw();
            return 1;

            // Event handling for mouse events:
        case Event.enter:
            color_++;
            if (color_ > 6)
                color_ = 1;
            goto case;
        case Event.move:
            overlay_ = Overlay.hover;
            ovX_ = fl.eventX();
            ovY_ = fl.eventY();
            widget_.redraw();
            return 1;
        case Event.push:
            if (fl.eventState(stateCtrl) || fl.eventButton() == rightMouse)
            {
                popupAppMenu();
                return 0;
            }
            goto case;
        case Event.drag:
            overlay_ = Overlay.draw;
            ovX_ = fl.eventX();
            ovY_ = fl.eventY();
            cvPaint();
            widget_.redraw();
            return 1;
        case Event.release:
            return 1;
        case Event.leave:
            overlay_ = Overlay.none;
            widget_.redraw();
            return 1;
        default:
            break;
        }
        return 0;
    }

    //
    // Canvas drawing copies the offscreen bitmap and then draws the overlays.
    //
    void cvDraw()
    {
        if (firstDraw_)
        {
            firstDraw_ = false;
            offscreen_ = createOffscreen(widget_.w(), widget_.h());
            beginOffscreen(offscreen_);
            fl_color(white);
            fl_rectf(0, 0, widget_.w(), widget_.h());
            endOffscreen();
            scale_ = fl_graphics_driver.scale();
        }
        if (fl_graphics_driver.scale() != scale_)
        {
            rescaleOffscreen(offscreen_);
            scale_ = fl_graphics_driver.scale();
        }
        int dx = inWindow_ ? 0 : widget_.x(), dy = inWindow_ ? 0 : widget_.y();
        pushClip(dx, dy, widget_.w(), widget_.h());
        copyOffscreen(dx, dy, widget_.w(), widget_.h(), offscreen_, 0, 0);

        // Preset values for overlay
        int r = 10;
        fl_color(black);
        final switch (overlay_)
        {
        case Overlay.none:
            break;
        case Overlay.penHover:
            fl_color(red);
            cvDrawButtons();
            goto case;
        case Overlay.hover:
            fl_xyline(ovX_ - 10, ovY_, ovX_ + 10);
            fl_yxline(ovX_, ovY_ - 10, ovY_ + 10);
            break;
        case Overlay.penDraw:
            r = cast(int)(32.0 * fl.Pen.eventPressure() * fl.Pen.eventPressure());
            if (r < 1)
                r = 1;
            fl_color(red);
            // Tilt indicator
            fl_arc(ovX_ - r / 2 - 40 * fl.Pen.eventTiltX(),
                    ovY_ - r / 2 - 40 * fl.Pen.eventTiltY(), r, r, 0, 360);
            // Eraser indicator
            if (fl.Pen.eventState(fl.Pen.State.eraserDown))
            {
                fl_line(ovX_ - r, ovY_ - r, ovX_ + r, ovY_ + r);
                fl_line(ovX_ - r, ovY_ + r, ovX_ + r, ovY_ - r);
            }
            cvDrawButtons();
            goto case;
        case Overlay.draw:
            // Draw a circle at the mouse or pan position
            fl_arc(ovX_ - r, ovY_ - r, 2 * r, 2 * r, 0, 360);
            break;
        }
        popClip();
    }

    void cvDrawButtons()
    {
        // Button indicators
        fl_rect(ovX_ - 16, ovY_ - 20, 32, 10);
        if (fl.Pen.eventState(fl.Pen.State.button0))
            fl_rectf(ovX_ - 16, ovY_ - 20, 8, 10);
        if (fl.Pen.eventState(fl.Pen.State.button1))
            fl_rectf(ovX_ - 8, ovY_ - 20, 8, 10);
        if (fl.Pen.eventState(fl.Pen.State.button2))
            fl_rectf(ovX_ - 0, ovY_ - 20, 8, 10);
        if (fl.Pen.eventState(fl.Pen.State.button3))
            fl_rectf(ovX_ + 8, ovY_ - 20, 8, 10);
    }

    //
    // Paint a circle with mouse events.
    //
    void cvPaint()
    {
        if (!offscreen_)
            return;
        int dx = inWindow_ ? 0 : widget_.x(), dy = inWindow_ ? 0 : widget_.y();
        beginOffscreen(offscreen_);
        drawCircle(fl.eventX() - dx - 12, fl.eventY() - dy - 12, 24, color_);
        endOffscreen();
    }

    //
    // Paint a circle with pen events. If the eraser is touching the surface,
    // draw a white circle.
    //
    void cvPenPaint()
    {
        float pressure = fl.Pen.eventPressure();
        int r = cast(int)(32.0 * pressure * pressure); // squared to make pressure more visible
        if (r < 1)
            r = 1;
        int dx = inWindow_ ? 0 : widget_.x(), dy = inWindow_ ? 0 : widget_.y();
        Color cc = fl.Pen.eventState(fl.Pen.State.eraserDown) ? white : color_;
        beginOffscreen(offscreen_);
        drawCircle(fl.eventX() - dx - r, fl.eventY() - dy - r, 2 * r, cc);
        endOffscreen();
    }
}

//
// A drawing canvas, based on a minimal widget.
//
class CanvasWidget : Widget
{
    CanvasInterface ci;

    this(int x, int y, int w, int h, string l = null)
    {
        super(x, y, w, h, l);
        ci = new CanvasInterface(this);
    }

    override int handle(Event event)
    {
        // writeln(fl_eventname_str(event));
        auto ret = ci.cvHandle(event);
        return ret ? ret : super.handle(event);
    }

    override void draw()
    {
        return ci.cvDraw();
    }
}

//
// A drawing canvas based on a window. Can be used as a standalone window
// and also as a subwindow inside another window.
//
class CanvasWindow : Window
{
    CanvasInterface ci;

    this(int x, int y, int w, int h, string l = null)
    {
        super(x, y, w, h, l);
        ci = new CanvasInterface(this);
    }

    override int handle(Event event)
    {
        auto ret = ci.cvHandle(event);
        return ret ? ret : super.handle(event);
    }

    override void draw()
    {
        return ci.cvDraw();
    }
}

// -- menu callbacks --

void modalWindowCb(Widget)
{
    message("None of the canvas areas should receive\n"
            ~ "pen events while this window is open.");
}

void nonModalWindowCb(Widget)
{
    auto win = new Window(200, 200, 300, 100, "Non-modal window");
    auto box = new Box(20, 20, 260, 60, "Pen events should still be delivered to the canvases.");
    box.alignment(alignWrap | alignCenter);
    win.end();
    win.setNonModal();
    win.show();
    win.callback((w) { w.hide(); destroy(w); });
}

void subscribeCb(Widget)
{
    if (cv1)
        fl.Pen.subscribe(cv1);
}

void unsubscribeCb(Widget)
{
    if (cv1)
        fl.Pen.unsubscribe(cv1);
}

void deleteCb(Widget)
{
    if (cv1)
    {
        cv1.topWindow().redraw();
        // User *must* unsubscribe before deleting the widget, otherwise the pen driver
        // will keep a dangling pointer to the deleted widget and will crash when trying
        // to send events to it.
        fl.Pen.unsubscribe(cv1);
        destroy(cv1);
        cv1 = null;
    }
}

void quitCb(Widget)
{
    exit(0);
}

// A popup menu with a few test tasks.
static this()
{
    appMenu = [
        MenuItem("with modal window", 0, (w) { modalWindowCb(w); }),
        MenuItem("with non-modal window", 0, (w) { nonModalWindowCb(w); }),
        MenuItem("unsubscribe middle canvas", 0, (w) { unsubscribeCb(w); }),
        MenuItem("resubscribe middle canvas", 0, (w) { subscribeCb(w); }),
        MenuItem("delete middle canvas", 0, (w) { deleteCb(w); }),
        MenuItem(null),
    ];
}

//
// Show the menu and run the callback.
//
int popupAppMenu()
{
    auto mi = appMenu.popup(fl.eventX(), fl.eventY(), "Tests");
    if (mi)
        mi.doCallback(cast(Widget) mi);
    return 1;
}

//
// Main app entry point
//
void main(string[] args)
{
    // Create our main app window
    auto window = new Window(100, 100, 640, 245, "FLTK Pen/Stylus/Tablet test, Ctrl-Tap for menu");

    auto menuBar = new MenuBar(0, 0, 640, 25);
    menuBar.add("PenPal/With Modal Window", 0, (w) { modalWindowCb(w); });
    menuBar.add("PenPal/With Non-Modal Window", 0, (w) {
        nonModalWindowCb(w);
    }, null, menuDivider);
    menuBar.add("PenPal/Unsubscribe Middle Canvas", 0, (w) {
        unsubscribeCb(w);
    });
    menuBar.add("PenPal/Subscribe Middle Canvas", 0, (w) { subscribeCb(w); });
    menuBar.add("PenPal/Delete Middle Canvas", 0, (w) { deleteCb(w); }, null, menuDivider);
    menuBar.add("PenPal/Quit", stateCommand + 'q', (w) { quitCb(w); });
    menuBar.menuEnd();

    // One testing canvas is just a regular child widget of the window
    auto canvasWidget0 = new CanvasWidget(10, 35, 200, 200, "CV0");

    // The second canvas is inside a group
    auto cv1Group = new FlGroup(215, 30, 210, 210);
    cv1Group.box(Boxtype.engravedBox);
    auto canvasWidget1 = cv1 = new CanvasWidget(220, 35, 200, 200, "CV1");
    cv1Group.end();

    // The third canvas is a window inside a window, so we can verify
    // that pen coordinates are calculated correctly.
    auto canvasWidget2 = new CanvasWindow(430, 35, 200, 200, "CV2");
    canvasWidget2.end();

    window.end();

    // A fourth canvas is a top level window by itself.
    auto cvWindow = cvwin = new CanvasWindow(100, 380, 200, 200, "Canvas Window");
    //cvwin.resizable(cvwin);

    // All canvases subscribe to pen events.
    fl.Pen.subscribe(canvasWidget0);
    fl.Pen.subscribe(canvasWidget1);
    fl.Pen.subscribe(canvasWidget2);
    fl.Pen.subscribe(cvWindow);

    window.show(args);
    canvasWidget2.show();
    cvWindow.show();

    fl.run();
}
