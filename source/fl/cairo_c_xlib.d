/*
 * `extern(C)` bindings for Cairo's Xlib surface (`cairo-xlib.h`), Cairo
 * 1.18.4: drawing with Cairo onto an X window or pixmap. Kept apart from
 * `fl.cairo_c` because it depends on `fl.xlib`'s `Display`/`Drawable`/
 * `Visual`/`Screen`/`Pixmap`. Cross-checked against GtkD the same way as
 * `fl.cairo_c`; GtkD has no binding for this header, so the C header
 * is the only reference.
 *
 * Only compiled into a Cairo-enabled Linux build
 * (`version (FLDTK_HAVE_CAIRO)`).
 */
module fl.cairo_c_xlib;

version (linux):
version (FLDTK_HAVE_CAIRO):

import fl.cairo_c;
import fl.xlib : Display, Drawable, Visual, Screen, Pixmap;

extern (C) nothrow @nogc
{
    // ---- cairo-xlib.h

    cairo_surface_t* cairo_xlib_surface_create(Display* dpy, Drawable drawable, Visual* visual, int width, int height);
    cairo_surface_t* cairo_xlib_surface_create_for_bitmap(Display* dpy, Pixmap bitmap, Screen* screen, int width, int height);
    void cairo_xlib_surface_set_size(cairo_surface_t* surface, int width, int height);
    void cairo_xlib_surface_set_drawable(cairo_surface_t* surface, Drawable drawable, int width, int height);
    Display* cairo_xlib_surface_get_display(cairo_surface_t* surface);
    Drawable cairo_xlib_surface_get_drawable(cairo_surface_t* surface);
    Screen* cairo_xlib_surface_get_screen(cairo_surface_t* surface);
    Visual* cairo_xlib_surface_get_visual(cairo_surface_t* surface);
    int cairo_xlib_surface_get_depth(cairo_surface_t* surface);
    int cairo_xlib_surface_get_width(cairo_surface_t* surface);
    int cairo_xlib_surface_get_height(cairo_surface_t* surface);
    void cairo_xlib_device_debug_cap_xrender_version(cairo_device_t* device, int major_version, int minor_version);
    void cairo_xlib_device_debug_set_precision(cairo_device_t* device, int precision);
    int cairo_xlib_device_debug_get_precision(cairo_device_t* device);
}
