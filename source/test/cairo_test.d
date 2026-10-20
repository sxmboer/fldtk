// D transliteration of FLTK's test/cairo_test.cxx.
// Build: rdmd buildsamples.d test cairo_test
//
// Like FLTK's, this builds either way: with a Cairo-enabled library
// (-version=FLDTK_HAVE_CAIRO; the default on Linux, `--cairo` on Windows)
// it is the real demo; without one it just says it needs one.
import fl;

version (FLDTK_HAVE_CAIRO)
{
    import std.functional : toDelegate;
    import std.string : toStringz;

    enum DEF_WIDTH = 0.03;

    // This demo program can be used in 3 modes. All 3 modes require a
    // Cairo-enabled library (the default dub configuration).
    //
    // 1) using class CairoWindow, useful when all the content of a window
    //    is drawn with Cairo.
    //    This is achieved setting USE_FL_CAIRO_WINDOW = true below
    // or
    // 2) showing how to draw in a DoubleWindow using both Cairo and
    //    the FLTK drawing API.
    //    This is achieved setting USE_FL_CAIRO_WINDOW = false below
    // or
    // 3) showing how to use "cairo extended use".
    //    This needs FLTK's CMake option FLTK_OPTION_CAIRO_EXT
    //    (FLTK_HAVE_CAIROEXT), which fldtk doesn't port.
    //    If cairoAutolinkContext(true) is called at the beginning
    //    of main(), any overridden draw() function gets access to an adequate
    //    Cairo context with cairoCc() without having to call
    //    cairoMakeCurrent(Window).

    enum USE_FL_CAIRO_WINDOW = true;

    // draw centered text

    void centeredText(cairo_t* cr, double x0, double y0, double w0, double h0, string myText)
    {
        auto text = myText.toStringz;
        cairo_select_font_face(cr, "Sans", CAIRO_FONT_SLANT_OBLIQUE, CAIRO_FONT_WEIGHT_BOLD);
        cairo_set_source_rgba(cr, 0.9, 0.9, 0.4, 0.6);
        cairo_text_extents_t extents;
        cairo_text_extents(cr, text, &extents);
        double x = (extents.width / 2 + extents.xBearing);
        double y = (extents.height / 2 + extents.yBearing);
        cairo_move_to(cr, x0 + w0 / 2 - x, y0 + h0 / 2 - y);
        cairo_text_path(cr, text);
        cairo_fill_preserve(cr);
        cairo_set_source_rgba(cr, 0, 0, 0, 1);
        cairo_set_line_width(cr, 0.004);
        cairo_stroke(cr);
        cairo_set_line_width(cr, DEF_WIDTH);
    }

    // draw a button object with rounded corners and a label

    void roundButton(cairo_t* cr, double x0, double y0,
                     double rectWidth, double rectHeight, double radius,
                     double r, double g, double b)
    {
        double x1, y1;
        x1 = x0 + rectWidth;
        y1 = y0 + rectHeight;
        if (!rectWidth || !rectHeight)
            return;
        if (rectWidth / 2 < radius)
        {
            if (rectHeight / 2 < radius)
            {
                cairo_move_to(cr, x0, (y0 + y1) / 2);
                cairo_curve_to(cr, x0, y0, x0, y0, (x0 + x1) / 2, y0);
                cairo_curve_to(cr, x1, y0, x1, y0, x1, (y0 + y1) / 2);
                cairo_curve_to(cr, x1, y1, x1, y1, (x1 + x0) / 2, y1);
                cairo_curve_to(cr, x0, y1, x0, y1, x0, (y0 + y1) / 2);
            }
            else
            {
                cairo_move_to(cr, x0, y0 + radius);
                cairo_curve_to(cr, x0, y0, x0, y0, (x0 + x1) / 2, y0);
                cairo_curve_to(cr, x1, y0, x1, y0, x1, y0 + radius);
                cairo_line_to(cr, x1, y1 - radius);
                cairo_curve_to(cr, x1, y1, x1, y1, (x1 + x0) / 2, y1);
                cairo_curve_to(cr, x0, y1, x0, y1, x0, y1 - radius);
            }
        }
        else
        {
            if (rectHeight / 2 < radius)
            {
                cairo_move_to(cr, x0, (y0 + y1) / 2);
                cairo_curve_to(cr, x0, y0, x0, y0, x0 + radius, y0);
                cairo_line_to(cr, x1 - radius, y0);
                cairo_curve_to(cr, x1, y0, x1, y0, x1, (y0 + y1) / 2);
                cairo_curve_to(cr, x1, y1, x1, y1, x1 - radius, y1);
                cairo_line_to(cr, x0 + radius, y1);
                cairo_curve_to(cr, x0, y1, x0, y1, x0, (y0 + y1) / 2);
            }
            else
            {
                cairo_move_to(cr, x0, y0 + radius);
                cairo_curve_to(cr, x0, y0, x0, y0, x0 + radius, y0);
                cairo_line_to(cr, x1 - radius, y0);
                cairo_curve_to(cr, x1, y0, x1, y0, x1, y0 + radius);
                cairo_line_to(cr, x1, y1 - radius);
                cairo_curve_to(cr, x1, y1, x1, y1, x1 - radius, y1);
                cairo_line_to(cr, x0 + radius, y1);
                cairo_curve_to(cr, x0, y1, x0, y1, x0, y1 - radius);
            }
        }
        cairo_close_path(cr);

        cairo_pattern_t* pat =
            // cairo_pattern_create_linear(0.0, 0.0, 0.0, 1.0);
            cairo_pattern_create_radial(0.25, 0.24, 0.11, 0.24, 0.14, 0.35);
        cairo_pattern_set_extend(pat, CAIRO_EXTEND_REFLECT);

        cairo_pattern_add_color_stop_rgba(pat, 1.0, r, g, b, 1);
        cairo_pattern_add_color_stop_rgba(pat, 0.0, 1, 1, 1, 1);
        cairo_set_source(cr, pat);
        cairo_fill_preserve(cr);
        cairo_pattern_destroy(pat);

        // cairo_set_source_rgb(cr, 0.5, 0.5, 1); cairo_fill_preserve(cr);
        cairo_set_source_rgba(cr, 0, 0, 0.5, 0.3);
        cairo_stroke(cr);

        cairo_set_font_size(cr, 0.075);
        centeredText(cr, x0, y0, rectWidth, rectHeight, "fldtk loves Cairo!");
    }

    // draw the entire image (3 buttons), scaled to the given width and height

    void drawImage(cairo_t* cr, int w, int h)
    {
        cairo_set_line_width(cr, DEF_WIDTH);
        cairo_scale(cr, w, h);

        roundButton(cr, 0.1, 0.1, 0.8, 0.2, 0.4, 1, 0, 0);
        roundButton(cr, 0.1, 0.4, 0.8, 0.2, 0.4, 0, 1, 0);
        roundButton(cr, 0.1, 0.7, 0.8, 0.2, 0.4, 0, 0, 1);
    } // drawImage()

    static if (USE_FL_CAIRO_WINDOW)
    {
        alias CairoUsingWindow = CairoWindow;
    }
    else
    {
        class CairoUsingWindow : DoubleWindow
        {
            private void delegate(CairoUsingWindow, cairo_t*) drawWithCairo_;

            this(int w, int h, string title)
            {
                super(w, h, title);
                auto box = new Box(Boxtype.noBox, 0, 0, w, 25,
                                   "Cairo and fldtk API in DoubleWindow");
                box.labelfont(timesBold);
                box.labelsize(12);
                box.labelcolor(blue);
            }

            override void draw()
            {
                Window.draw(); // perform drawings with the fldtk API
                cairoMakeCurrent(this);  // announce Cairo will be used in this window
                cairo_t* cc = cairoCc(); // get the adequate Cairo context
                drawWithCairo_(this, cc); // draw in this window using Cairo

                // flush Cairo drawings: necessary at least for Windows
                cairoFlush(cc);
            }

            void setDrawCb(void delegate(CairoUsingWindow, cairo_t*) cb)
            {
                drawWithCairo_ = cb;
            }
        }
    }

    // Cairo rendering cb called during CairoWindow.draw()
    // or CairoUsingWindow.draw().
    void myCairoDrawCb(CairoUsingWindow window, cairo_t* cr)
    {
        drawImage(cr, window.w(), window.h());
    }

    void main(string[] args)
    {
        auto window = new CairoUsingWindow(350, 350, "Fldtk loves Cairo");

        window.resizable(window);
        window.color(white);
        window.setDrawCb(toDelegate(&myCairoDrawCb));
        window.show(args);

        fl.run();
    }
}
else // (!FLDTK_HAVE_CAIRO)
{
    void main(string[] args)
    {
        fl.args(args);
        messageTitle("This program needs a Cairo enabled fldtk library");
        message("Please build fldtk with Cairo enabled: the default on Linux\n"
            ~ "(not dub configuration linux-no-cairo), and\n"
            ~ "rdmd buildsamples.d --cairo on Windows (see BUILDING.md).");
    }
}
