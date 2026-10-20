/*
 * Port of FL/Fl_Cairo_Window.H (FLTK 1.5.0): a double-buffered window
 * whose content is drawn with Cairo.
 *
 * Only compiled into a Cairo-enabled build (`version (FLDTK_HAVE_CAIRO)`,
 * on by default on Linux, off with dub configuration `linux-no-cairo`; on Windows only with `windows-cairo`),
 * the equivalent of FLTK's CMake option
 * FLTK_OPTION_CAIRO_WINDOW. The draw callback is a D delegate rather than
 * FLTK's plain function pointer, so it can capture whatever state it
 * needs.
 */
module fl.cairo_window;

version (FLDTK_HAVE_CAIRO):

import fl.cairo : cairoAutolinkContext, cairoMakeCurrent, cairoCc, cairoFlush;
import fl.double_window : DoubleWindow;
import fl.cairo_c : cairo_t;

/**
 * An FLTK window with Cairo support.
 *
 * This class overrides `draw()` for you, so the only thing you have to
 * do is provide your Cairo code. All Cairo context handling is done
 * transparently.
 *
 * The default coordinate system for Cairo drawing within a `CairoWindow`
 * is FLTK's: `x,y,w,h` values are relative to the top/left corner of the
 * window, as with regular FLTK drawing, i.e. `0 <= x <= w-1`,
 * `0 <= y <= h-1`. Example:
 * ---
 * void myCairoDrawCb(CairoWindow window, cairo_t* cr)
 * {
 *     // Draw an "X"
 *     immutable double xmax = window.w() - 1;
 *     immutable double ymax = window.h() - 1;
 *     cairo_set_line_width(cr, 1.00);                              // line width for drawing
 *     cairo_set_source_rgb(cr, 1.0, 0.5, 0.0);                     // orange
 *     cairo_move_to(cr, 0.0, 0.0);  cairo_line_to(cr, xmax, ymax); // draw diagonal "\"
 *     cairo_move_to(cr, 0.0, ymax); cairo_line_to(cr, xmax, 0.0);  // draw diagonal "/"
 *     cairo_stroke(cr);                                            // stroke the lines
 * }
 * ---
 *
 * This differs from Cairo's own default coordinate system, which uses
 * normalized `0.0 ... 1.0` values for x and y, so beware when copying
 * Cairo example programs that assume normalized values. If need be, revert
 * to Cairo's coordinate system by calling `cairo_scale()` with the
 * window's `w()` and `h()`:
 * ---
 * void myCairoDrawCb(CairoWindow window, cairo_t* cr)
 * {
 *     cairo_scale(cr, window.w(), window.h()); // use Cairo's default coordinate system
 *     // ... use 0.0 to 1.0 values from here on ...
 * }
 * ---
 *
 * See `source/examples/cairo_draw_x.d` and `source/test/cairo_test.d`.
 *
 * You can alternatively define your own Cairo window by overriding
 * `draw()` and calling `cairoMakeCurrent(Window)` there to attach a
 * context to the window. Do this only when your window is the current
 * window (see `Window.current()`).
 */
class CairoWindow : DoubleWindow
{
    /// Type of the Cairo draw callback: the window, and the Cairo context
    /// to draw with.
    alias CairoDrawCb = void delegate(CairoWindow self, cairo_t* def);

    private CairoDrawCb drawCb_;

    this(int w, int h, string label = null)
    {
        super(w, h, label);
    }

    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
    }

    override void draw()
    {
        super.draw();
        if (drawCb_ !is null) // call the Cairo draw callback
        {
            // manual method? if yes, explicitly get a Cairo context here
            if (!cairoAutolinkContext())
                cairoMakeCurrent(this);
            drawCb_(this, cairoCc());
            // flush Cairo drawings: necessary at least for Windows
            cairoFlush(cairoCc());
        }
    }

    /// Sets the Cairo draw callback that implements your Cairo rendering.
    void setDrawCb(CairoDrawCb cb) { drawCb_ = cb; }
}
