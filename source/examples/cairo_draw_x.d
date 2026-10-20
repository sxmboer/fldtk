// D transliteration of FLTK's examples/cairo-draw-x.cxx.
// Build: rdmd buildsamples.d examples cairo_draw_x
//
// Simple demo of drawing an "X" in Cairo (antialiased lines).
//
// Like FLTK's, this builds either way: with a Cairo-enabled library
// (-version=FLDTK_HAVE_CAIRO; the default on Linux, `--cairo` on Windows)
// it is the real demo; without one it just says it needs one.
import fl;

version (FLDTK_HAVE_CAIRO) // Builds example code only if cairo enabled
{
    import std.functional : toDelegate;

    // Cairo rendering cb called during CairoWindow.draw()
    void myCairoDrawCb(CairoWindow window, cairo_t* cr)
    {
        immutable double xmax = window.w() - 1;
        immutable double ymax = window.h() - 1;

        // Set antialiasing mode. We could check the Cairo version at compile time but we'd
        // also have to check the runtime version which would make this demo too complicated.

        // CAIRO_ANTIALIAS_BEST    is available since Cairo version 1.12,
        // CAIRO_ANTIALIAS_DEFAULT is available since Cairo version 1.0.

        cairo_set_antialias(cr, CAIRO_ANTIALIAS_DEFAULT);             // use default antialiasing

        // Draw orange "X"
        //     Draws an X to four corners of resizable window.
        //     See CairoWindow's docs for more info.
        //
        cairo_set_line_width(cr, 1.00);                               // line width for drawing
        cairo_set_source_rgb(cr, 1.0, 0.5, 0.0);                      // orange
        cairo_move_to(cr, 0.0, 0.0);  cairo_line_to(cr, xmax, ymax);  // draw diagonal "\"
        cairo_move_to(cr, 0.0, ymax); cairo_line_to(cr, xmax, 0.0);   // draw diagonal "/"
        cairo_stroke(cr);                                             // stroke the lines
    }

    void main(string[] args)
    {
        auto window = new CairoWindow(300, 300, "Cairo Draw 'X'");
        window.color(black);                                          // cairo window's default bg color
        // FLTK's example passes -1, -1 as the maximum; only 0 means "no
        // maximum", and on Windows -1 caps the window at its border size
        // (see FLTK_ISSUES.md).
        window.sizeRange(50, 50);                                     // allow resize 50,50 and up
        window.resizable(window);                                     // allow window to be resized
        window.setDrawCb(toDelegate(&myCairoDrawCb));                 // draw callback for cairo drawing
        window.show(args);
        fl.run();
    }
}
// The code that follows just allows the example to build even if cairo wasn't enabled.
else
{
    void main(string[] args)
    {
        messageTitle("This program needs a Cairo enabled FLTK library");
        message("Please build fldtk with Cairo enabled: the default on Linux\n"
            ~ "(not dub configuration linux-no-cairo), and\n"
            ~ "rdmd buildsamples.d --cairo on Windows (see BUILDING.md).");
    }
}
