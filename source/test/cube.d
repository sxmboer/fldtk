// D transliteration of FLTK's test/cube.cxx (~/Repositories/fltk).
// Part of the samples/ contract -- see samples/README.md.
// Check: ./samples/build.sh cube
//
// OpenGL test with 2 cubes (to test multiple GL contexts), including
// ordinary FLTK widgets (buttons/sliders/radio buttons) composited over
// each GL scene, using the real `GlWindow`/`Grid`/`SysMenuBar`/
// `Printer`/`Timestamp`/`fl_choice()` API. `gl_color()`/`gl_font()`/
// `gl_draw()` (`FL/gl.h`'s own GL-native text-drawing port, used below
// for the "Cube: wire"/"Cube: flat" label drawn directly into each GL
// scene) are real too. Everything in this file builds and runs against
// real fldtk API.
import fl;
import std.stdio : writefln;
import std.format : format;

// Global constants and variables
enum double fps = 25.0;       // desired frame rate (independent of speed slider)
enum double delay = 1.0 / fps; // calculated timer delay
int count = -2;                // initialize loop (draw) counter
int done = 0;                  // set to 1 in exit button callback
Timestamp start;                // taken at start of main or after reset

// Global pointers to widgets
Window form;
Slider speed, size;
Button exitButton;
LightButton wire, flat;
Button statsButton;
CubeBox ltCube, rtCube;

/* The cube definition */
float[3] v0 = [0.0, 0.0, 0.0];
float[3] v1 = [1.0, 0.0, 0.0];
float[3] v2 = [1.0, 1.0, 0.0];
float[3] v3 = [0.0, 1.0, 0.0];
float[3] v4 = [0.0, 0.0, 1.0];
float[3] v5 = [1.0, 0.0, 1.0];
float[3] v6 = [1.0, 1.0, 1.0];
float[3] v7 = [0.0, 1.0, 1.0];

void v3f(float[3] x) { glVertex3fv(x.ptr); }

void drawcube(int wire)
{
    /* Draw a colored cube */
    glBegin(wire ? GL_LINE_LOOP : GL_POLYGON);
    glColor3ub(0, 0, 255);
    v3f(v0); v3f(v1); v3f(v2); v3f(v3);
    glEnd();
    glBegin(wire ? GL_LINE_LOOP : GL_POLYGON);
    glColor3ub(0, 255, 255); v3f(v4); v3f(v5); v3f(v6); v3f(v7);
    glEnd();
    glBegin(wire ? GL_LINE_LOOP : GL_POLYGON);
    glColor3ub(255, 0, 255); v3f(v0); v3f(v1); v3f(v5); v3f(v4);
    glEnd();
    glBegin(wire ? GL_LINE_LOOP : GL_POLYGON);
    glColor3ub(255, 255, 0); v3f(v2); v3f(v3); v3f(v7); v3f(v6);
    glEnd();
    glBegin(wire ? GL_LINE_LOOP : GL_POLYGON);
    glColor3ub(0, 255, 0); v3f(v0); v3f(v4); v3f(v7); v3f(v3);
    glEnd();
    glBegin(wire ? GL_LINE_LOOP : GL_POLYGON);
    glColor3ub(255, 0, 0); v3f(v1); v3f(v2); v3f(v6); v3f(v5);
    glEnd();
}

class CubeBox : GlWindow
{
    double lasttime;
    int wire;
    double size;
    double speed;

    this(int x, int y, int w, int h, string l = null)
    {
        super(x, y, w, h, l);
        end();
        lasttime = 0.0;
        box(Boxtype.downFrame);
    }

    override void draw()
    {
        lasttime = lasttime + speed;
        if (!valid())
        {
            glLoadIdentity();
            glViewport(0, 0, pixelW(), pixelH());
            glEnable(GL_DEPTH_TEST);
            glFrustum(-1, 1, -1, 1, 2, 10000);
            glTranslatef(0, 0, -10);
            glClearColor(0.4f, 0.4f, 0.4f, 0);
        }
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
        glPushMatrix();
        glRotatef(cast(float)(lasttime * 1.6), 0, 0, 1);
        glRotatef(cast(float)(lasttime * 4.2), 1, 0, 0);
        glRotatef(cast(float)(lasttime * 2.3), 0, 1, 0);
        glTranslatef(-1.0f, 1.2f, -1.5f);
        glScalef(cast(float) size, cast(float) size, cast(float) size);
        drawcube(wire);
        glPopMatrix();
        gl_color(gray); // NOT gray0 -- matches FLTK's `gl_color(FL_GRAY)`
        // (test/cube.cxx). `gray0`/`FL_GRAY0` is the *darkest* end of the
        // 24-entry gray ramp -- background()'s power-curve fit forces
        // ramp position 0 to exactly (0,0,0) by construction, regardless
        // of the actual background color -- so it's essentially always
        // black by design, not merely "uninitialized". `gray` (this
        // port's alias for `backgroundColor`/`FL_GRAY`, the ordinary
        // mid-tone widget gray) is the constant FLTK actually uses
        // here.
        glDisable(GL_DEPTH_TEST);
        gl_font(helveticaBold, 16);
        gl_draw(wire ? "Cube: wire" : "Cube: flat", -4.5f, -4.5f);
        glEnable(GL_DEPTH_TEST);

        // draw additional FLTK widgets and graphics
        super.draw();
    }

    override int handle(Event e)
    {
        switch (e)
        {
        case Event.enter: cursor(Cursor.cross); break;
        case Event.leave: cursor(Cursor.default_); break;
        default: break;
        }
        return super.handle(e);
    }
}

// callback for overlay button (Button on OpenGL scene)
void showInfoCb(Widget w)
{
    message("This is an example of using FLTK widgets inside OpenGL windows.\n" ~
               "Multiple widgets can be added to GlWindows. They will be\n" ~
               "rendered as overlays over the scene.");
}

// overlay a button onto an OpenGL window (CubeBox)
// but don't change the current group FlGroup.current()
//
// FLTK's own label text is "FLTK Over GL"; renamed to this port's
// own name here since it's fldtk demonstrating the feature, not FLTK
// itself. Sized to fit the label rather than a hardcoded 120px: the
// button's own GL-text-rendering path (Widget.drawLabel() -> the same
// alphaMaskForString()/computeTexture() machinery gl_draw() uses)
// draws the label at its own real font metrics
// regardless of the button's width, so a too-narrow fixed size just
// clips the label instead of shrinking it -- "fldtk over GL" is a
// couple characters longer than FLTK's original text too, making an
// already-tight fit worse. `fl_measure()` (this port's own
// text-measurement leaf, the same one `Widget.drawLabel()` itself uses
// internally) gives the real on-screen size for the button's own
// default label font/size (`helvetica`/`normalSize`, `Widget`'s own
// constructor defaults -- this `Button` never overrides either), so
// this generalizes to any future label text change instead of relying
// on a fixed guess.
void overlayButton(CubeBox cube)
{
    FlGroup curr = FlGroup.current();
    FlGroup.current(null);
    enum label = "fldtk over GL";
    fl_font(helvetica, normalSize);
    int lw, lh;
    fl_measure(label, lw, lh);
    auto w = new Button(10, 10, lw + 20, lh + 10, label);
    w.color(freeColor);
    w.box(Boxtype.borderBox);
    w.callback((w) { showInfoCb(w); });
    cube.add(w);
    FlGroup.current(curr);
}

void exitCb(Widget w = null)
{
    done = 1;
    fl.hideAllWindows();
}

void statsCb(Widget w = null)
{
    // display performance data on stdout and (for Windows!) in a message window
    double runtime = fl.secondsSince(start);

    string buffer = format("Count =%5d, time = %7.3f sec, fps = %5.2f, requested: %5.2f",
                            count, runtime, count / runtime, fps);
    writefln("%s", buffer);

    int choice = choice(buffer, "E&xit", "&Continue", "&Reset");
    switch (choice)
    {
    case 0: // exit program, close all windows
        done = 1;
        fl.hideAllWindows();
        break;
    case 2: // reset
        count = -2;
        writefln("*** RESET ***");
        break;
    default: // continue
        break;
    }
}

void timerCb()
{
    static Timestamp last;
    static Timestamp now;
    count++;
    if (count == 0)
    {
        start = fl.now();
        last = start;
    }
    else if (count > 0)
    {
        now = fl.now();
    }

    ltCube.redraw();
    rtCube.redraw();
    fl.repeatTimeout(delay, () { timerCb(); });
    last = fl.now();
}

void speedCb(Widget w)
{
    ltCube.speed = rtCube.speed = (cast(Slider) w).value();
}

void sizeCb(Widget w)
{
    ltCube.size = rtCube.size = (cast(Slider) w).value();
}

void flatCb(Widget w)
{
    int f = (cast(LightButton) w).value();
    ltCube.wire = 1 - f;
    rtCube.wire = f;
}

void wireCb(Widget w)
{
    int wireVal = (cast(LightButton) w).value();
    ltCube.wire = wireVal;
    rtCube.wire = 1 - wireVal;
}

// print screen demo
void printCb(Widget w)
{
    auto printer = new Printer();
    Window win = fl.firstWindow();
    if (win is null) return;
    string errMessage;
    if (printer.beginJob(1, errMessage)) return;
    if (printer.beginPage()) return;
    printer.scale(0.5, 0.5);
    printer.printWidget(win);
    printer.endPage();
    printer.endJob();
}

// Create a form that allows resizing for A and C (GL windows) with B fixed size/centered:
//
//      |<--------------------------------------->|<---------------------->|
//      .          ltCube             center      :       rtCube          .
//      .            350                100       :         350            .
//      .  |<------------------->|  |<-------->|  |<------------------->|  .
//      ....................................................................
//      :  .......................  ............  .......................  :  __
//      :  :                     :  :          :  :                     :  :
//      :  :          A          :  :    B     :  :          C          :  :     h = 350
//      :  :                     :  :          :  :                     :  :
//      :  :.....................:  :..........:  :.....................:  :  __
//      :..................................................................:  __ MARGIN
//
//      |  |                     |  |          |  |
//     MARGIN                    GAP           GAP

int MENUBAR_H = 25; // menubar height - updated by sys menubar
enum int MARGIN = 20; // fixed margin around widgets
enum int GAP = 20;    // fixed gap between widgets

void makeform(string name)
{
    // Widget's XYWH's
    int formW = 800 + 2 * MARGIN + 2 * GAP;   // main window width
    int formH = 350 + MENUBAR_H + 2 * MARGIN; // main window height

    // main window
    form = new Window(formW, formH, name);
    form.callback((w) { exitCb(w); });
    // menu bar
    auto menubar = new SysMenuBar(0, 0, formW, MENUBAR_H);
    menubar.add("File/Print window", stateCommand + 'p', (w) { printCb(w); });
    menubar.add("File/Quit", stateCommand + 'q', (w) { exitCb(w); });

    // update menubar height if there is a system menu bar (e.g. on macOS)
    if (menubar.isGlobal())
        MENUBAR_H = 0;

    // Grid (layout)
    auto grid = new Grid(0, MENUBAR_H, formW, formH - MENUBAR_H);
    grid.layout(5, 4, MARGIN, GAP);
    grid.box(Boxtype.flatBox);

    // set column and row weights to control resizing behavior
    int[4] cwe = [50, 0, 0, 50];   // column weights
    int[5] rwe = [0, 0, 50, 0, 0]; // row weights
    grid.colWeight(cwe);           // set weights for resizing
    grid.rowWeight(rwe);           // set weights for resizing

    // set non-default gaps for special layout purposes and labels
    grid.rowGap(0, 0);   // no gap below wire button
    grid.rowGap(2, 30);  // gap below sliders for labels
    grid.rowGap(3, 0);   // no gap below statisctics button

    // left GL window
    ltCube = new CubeBox(0, 0, 350, 350);

    // center group
    wire = new RadioLightButton(0, 0, 100, 25, "Wire");
    flat = new RadioLightButton(0, 0, 100, 25, "Flat");
    speed = new Slider(vertSlider, 0, 0, 40, 90, "Speed");
    size = new Slider(vertSlider, 0, 0, 40, 90, "Size");
    statsButton = new Button(0, 0, 100, 25, "Statistics");
    statsButton.callback((w) { statsCb(w); });
    statsButton.tooltip("Display a dialog box with soem statistics (fps)\n");
    exitButton = new Button(0, 0, 100, 25, "E&xit");
    exitButton.callback((w) { exitCb(w); });

    // right GL window
    rtCube = new CubeBox(0, 0, 350, 350);

    // assign widgets to grid positions (R=row, C=col) and sizes
    // RS=rowspan, CS=colspan: R, C, RS, CS, optional alignment
    grid.widget(ltCube, 0, 0, 5, 1);
    grid.widget(wire, 0, 1, 1, 2);
    grid.widget(flat, 1, 1, 1, 2);
    grid.widget(speed, 2, 1, 1, 1, gridVertical);
    grid.widget(size, 2, 2, 1, 1, gridVertical);
    grid.widget(statsButton, 3, 1, 1, 2);
    grid.widget(exitButton, 4, 1, 1, 2);
    grid.widget(rtCube, 0, 3, 5, 1);

    overlayButton(ltCube); // overlay a button onto the OpenGL window

    form.end();
    form.resizable(grid);
    form.sizeRange(form.w(), form.h()); // minimum window size
}

void main(string[] args)
{
    fl.useHighResGL(true);
    fl.setColor(freeColor, 255, 255, 0, 75);
    makeform(args[0]);

    speed.bounds(6, 0);
    speed.value(ltCube.speed = rtCube.speed = 2.0);
    speed.callback((w) { speedCb(w); });

    size.bounds(4, 0.2);
    size.value(ltCube.size = rtCube.size = 2.0);
    size.callback((w) { sizeCb(w); });

    flat.value(1);
    flat.callback((w) { flatCb(w); });
    wire.value(0);
    wire.callback((w) { wireCb(w); });

    form.label("Cube Demo");
    form.show(args); // NOT plain show() -- matches FLTK's own
    // `form->show(argc,argv)` (test/cube.cxx), which is what actually
    // triggers Fl::args()/Fl::get_system_colors() (fl.core.
    // getSystemColors(), only wired up on Window.show(string[]), never
    // the plain no-args show()). Without it, the gray ramp
    // (fl.enumerations.gray0..gray0+23) stays at its static default
    // table values -- gray0 itself defaults to literal 0x00000000,
    // only ever overwritten by a real background()/getSystemColors()
    // call -- so gl_color(gray0) for the "Cube: wire"/"Cube: flat"
    // label would render as pure black instead of the intended gray.
    ltCube.show();
    rtCube.show();

    ltCube.wire = wire.value();
    rtCube.wire = !wire.value();
    ltCube.size = rtCube.size = size.value();
    ltCube.speed = rtCube.speed = speed.value();
    ltCube.redraw();
    rtCube.redraw();

    // with GL: use a timer for drawing and measure performance
    form.waitForExpose();
    fl.addTimeout(0.1, () { timerCb(); }); // start timer
    fl.run();
}
