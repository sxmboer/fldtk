// D transliteration of FLTK's examples/cairo-draw-x.cxx.
// Build: rdmd buildsamples.d examples cairo_draw_x
//
// Simple demo of drawing an "X" in Cairo (antialiased lines).
//
// NOTE: FLTK builds one of two entirely different main()s depending
// on whether FLTK was configured with Cairo support (`#ifdef
// FLTK_HAVE_CAIRO`), falling back to a plain fl_message() otherwise.
// fldtk has no build-configuration mechanism (or Cairo binding) yet, so
// this transliterates only the Cairo-enabled branch -- the actual demo.
import fl;
import cairo = fl.cairo;

// Cairo rendering cb called during CairoWindow's draw()
void myCairoDrawCb(CairoWindow window, cairo.cairo_t* cr)
{
    immutable double xmax = window.w() - 1;
    immutable double ymax = window.h() - 1;

    // Set antialiasing mode. We could check the Cairo version at compile time but we'd
    // also have to check the runtime version which would make this demo too complicated.

    // CAIRO_ANTIALIAS_BEST    is available since Cairo version 1.12,
    // CAIRO_ANTIALIAS_DEFAULT is available since Cairo version 1.0.

    cairo.cairo_set_antialias(cr, cairo.CAIRO_ANTIALIAS_DEFAULT); // use default antialiasing

    // Draw orange "X"
    //     Draws an X to four corners of resizable window.
    //     See Fl_Cairo_Window docs for more info.
    cairo.cairo_set_line_width(cr, 1.00);                       // line width for drawing
    cairo.cairo_set_source_rgb(cr, 1.0, 0.5, 0.0);              // orange
    cairo.cairo_move_to(cr, 0.0, 0.0);
    cairo.cairo_line_to(cr, xmax, ymax);                        // draw diagonal "\"
    cairo.cairo_move_to(cr, 0.0, ymax);
    cairo.cairo_line_to(cr, xmax, 0.0);                         // draw diagonal "/"
    cairo.cairo_stroke(cr);                                     // stroke the lines
}

void main()
{
    auto window = new CairoWindow(300, 300, "Cairo Draw 'X'");
    window.color(black);                       // cairo window's default bg color
    window.sizeRange(50, 50, -1, -1);          // allow resize 50,50 and up
    window.resizable(window);                  // allow window to be resized
    window.setDrawCb(&myCairoDrawCb);           // draw callback for cairo drawing
    window.show();
    fl.run();
}
