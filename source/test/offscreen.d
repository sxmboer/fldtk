// D transliteration of FLTK's test/offscreen.cxx (~/Repositories/fltk).
// Part of the samples/ contract -- see samples/README.md.
// Check: ./samples/build.sh offscreen
import fl;

static DoubleWindow mainWindow = null;

// constants to define the view etc.
enum int offscreenSize = 1000;
enum int winSize = 512;
enum int firstUsefulColor = 56;
enum int lastUsefulColor = 255;
enum int numIterations = 300;
enum int maxLineWidth = 9;
enum double deltaTime = 0.1;

/*****************************************************************************/
class OscrBox : Box
{
public:
    this(int x, int y, int w, int h)
    {
        super(x, y, w, h);
        oscr = Offscreen.init;
        x1 = 0;
        y1 = 0;
        drag_state = 0;
        page_x = (offscreenSize - winSize) / 2;
        page_y = (offscreenSize - winSize) / 2;
        offsc_w = 0;
        offsc_h = 0;
        iters = numIterations + 1;
    }

    bool hasOscr() const
    {
        if (oscr) return true;
        return false;
    }

    // draw()/handle() are private in FLTK's C++ (only ever called
    // virtually through a Fl_Widget*); D requires override visibility to
    // be at least as public as the base declaration, so they stay public
    // here.
    override void draw()
    {
        int wd = w();
        int ht = h();
        int xo = x();
        int yo = y();

        fl_color(fl_gray_ramp(19)); // a light grey background shade
        fl_rectf(xo, yo, wd, ht); // fill the box with this colour

        // then add the offscreen on top of the grey background
        if (hasOscr()) // offscreen exists
        {
            if (scale != DisplayScaleDriver.defaultDriver().scale())
            {
                // the screen scaling factor has changed
                rescaleOffscreen(oscr);
                scale = DisplayScaleDriver.defaultDriver().scale();
            }
            copyOffscreen(xo, yo, wd, ht, oscr, page_x, page_y);
        }
        else // create offscreen
        {
            // some hosts may need a valid window context to base the offscreen on...
            mainWindow.makeCurrent();
            offsc_w = offscreenSize;
            offsc_h = offscreenSize;
            oscr = createOffscreen(offsc_w, offsc_h);
            scale = DisplayScaleDriver.defaultDriver().scale();
        }
    }

    override int handle(Event ev)
    {
        int ret = super.handle(ev);

        // handle dragging of visible page area - if a valid context exists
        if (hasOscr())
        {
            switch (ev)
            {
            case Event.enter:
                mainWindow.cursor(Cursor.move);
                ret = 1;
                break;

            case Event.leave:
                mainWindow.cursor(Cursor.default_);
                ret = 1;
                break;

            case Event.push:
                x1 = fl.eventXRoot();
                y1 = fl.eventYRoot();
                drag_state = 1; // drag
                ret = 1;
                break;

            case Event.drag:
                if (drag_state == 1) // dragging page
                {
                    int x2 = fl.eventXRoot();
                    int y2 = fl.eventYRoot();
                    xoff = x1 - x2;
                    yoff = y1 - y2;
                    x1 = x2;
                    y1 = y2;
                    page_x += xoff;
                    page_y += yoff;
                    // check the page bounds
                    if (page_x < -w())
                    {
                        page_x = -w();
                    }
                    else if (page_x > offsc_w)
                    {
                        page_x = offsc_w;
                    }
                    if (page_y < -h())
                    {
                        page_y = -h();
                    }
                    else if (page_y > offsc_h)
                    {
                        page_y = offsc_h;
                    }
                    redraw();
                }
                ret = 1;
                break;

            case Event.release:
                drag_state = 0;
                ret = 1;
                break;

            default:
                break;
            }
        }
        return ret;
    }

    // Generate "random" values for the line display
    double randomVal(int v) const
    {
        import std.random : uniform;
        return uniform(0.0, cast(double) v); // 0 to v
    }

public:
    void oscrDrawing()
    {
        Color col;
        static int icol = firstUsefulColor;
        static int ox = (offscreenSize / 2);
        static int oy = (offscreenSize / 2);

        if (!hasOscr())
        {
            return; // no valid offscreen, nothing to do here
        }

        beginOffscreen(oscr); // Open the offscreen context for drawing
        {
            if (iters > numIterations) // clear the offscreen and start afresh
            {
                fl_color(white);
                fl_rectf(0, 0, offsc_w, offsc_h);
                iters = 0;
            }
            iters++;

            icol++;
            if (icol > lastUsefulColor)
            {
                icol = firstUsefulColor;
            }
            col = cast(Color) icol;
            fl_color(col); // set the colour

            double drx = randomVal(offsc_w);
            double dry = randomVal(offsc_h);
            double drt = randomVal(maxLineWidth);

            int ex = cast(int) drx;
            int ey = cast(int) dry;
            lineStyle(lineSolid, cast(int) drt);
            fl_line(ox, oy, ex, ey);
            ox = ex;
            oy = ey;
        }
        lineStyle(lineSolid, 0);
        endOffscreen(); // close the offscreen context
        redraw();
    }

private:
    // The offscreen surface
    Offscreen oscr;
    // variables used to handle "dragging" of the view within the box
    int x1, y1; // drag start positions
    int xoff, yoff; // drag offsets
    int drag_state; // non-zero if drag is in progress
    int page_x, page_y; // top left of view area
    // Width and height of the offscreen surface
    int offsc_w, offsc_h;
    int iters; // Must be set on first pass!
    float scale; // current screen scaling factor value
}

/*****************************************************************************/
static OscrBox osBox = null;

/*****************************************************************************/
static void oscrAnim()
{
    osBox.oscrDrawing(); // if the offscreen exists, draw something
    fl.repeatTimeout(deltaTime, () { oscrAnim(); });
}

/*****************************************************************************/
void main(string[] args)
{
    int dim1 = winSize;
    mainWindow = new DoubleWindow(dim1, dim1, "Offscreen demo");
    mainWindow.begin();

    dim1 -= 10;
    osBox = new OscrBox(5, 5, dim1, dim1);
    mainWindow.end();
    mainWindow.resizable(osBox);

    mainWindow.show();

    fl.addTimeout(deltaTime, () { oscrAnim(); });

    fl.run();
}
