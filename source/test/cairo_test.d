// D transliteration of FLTK's test/cairo_test.cxx.
// Build: rdmd buildsamples.d test cairo_test
//
// FLTK is entirely conditional on FLTK_HAVE_CAIRO (a CMake option);
// fldtk has no Cairo bindings/support at all yet, so this transliterates
// the Cairo-enabled branch (the interesting one) rather than the
// "Cairo not configured" fallback -- everything cairo_t-shaped is an
// honest, expected gap (no cairo.d binding module exists in fldtk).
import fl;

enum DEF_WIDTH = 0.03;

// draw centered text
void centeredText(cairo_t* cr, double x0, double y0, double w0, double h0, string myText)
{
    cairo_select_font_face(cr, "Sans", CairoSlant.oblique, CairoWeight.bold);
    cairo_set_source_rgba(cr, 0.9, 0.9, 0.4, 0.6);
    CairoTextExtents extents;
    cairo_text_extents(cr, myText, &extents);
    double x = (extents.width / 2 + extents.xBearing);
    double y = (extents.height / 2 + extents.yBearing);
    cairo_move_to(cr, x0 + w0 / 2 - x, y0 + h0 / 2 - y);
    cairo_text_path(cr, myText);
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
    cairo_pattern_set_extend(pat, CairoExtend.reflect);

    cairo_pattern_add_color_stop_rgba(pat, 1.0, r, g, b, 1);
    cairo_pattern_add_color_stop_rgba(pat, 0.0, 1, 1, 1, 1);
    cairo_set_source(cr, pat);
    cairo_fill_preserve(cr);
    cairo_pattern_destroy(pat);

    // cairo_set_source_rgb(cr, 0.5, 0.5, 1); cairo_fill_preserve(cr);
    cairo_set_source_rgba(cr, 0, 0, 0.5, 0.3);
    cairo_stroke(cr);

    cairo_set_font_size(cr, 0.075);
    centeredText(cr, x0, y0, rectWidth, rectHeight, "FLTK loves Cairo!");
}

// draw the entire image (3 buttons), scaled to the given width and height
void drawImage(cairo_t* cr, int w, int h)
{
    cairo_set_line_width(cr, DEF_WIDTH);
    cairo_scale(cr, w, h);

    roundButton(cr, 0.1, 0.1, 0.8, 0.2, 0.4, 1, 0, 0);
    roundButton(cr, 0.1, 0.4, 0.8, 0.2, 0.4, 0, 1, 0);
    roundButton(cr, 0.1, 0.7, 0.8, 0.2, 0.4, 0, 0, 1);
}

// Cairo rendering callback called during CairoWindow.draw().
alias CairoDrawCallback = void delegate(CairoWindow window, cairo_t* cr);

void myCairoDrawCb(CairoWindow window, cairo_t* cr)
{
    drawImage(cr, window.w(), window.h());
}

void main(string[] args)
{
    auto window = new CairoWindow(350, 350, "FLTK loves Cairo");

    window.resizable(window);
    window.color(white);
    window.setDrawCb(&myCairoDrawCb);
    window.show();

    fl.run();
}
