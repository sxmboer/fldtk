/*
 * `extern(C)` bindings for Cairo's Win32 surface and font support
 * (`cairo-win32.h`), Cairo 1.18.4: drawing with Cairo onto a Windows
 * device context, and Cairo fonts made from GDI fonts. Kept apart from
 * `fl.cairo_c` because it depends on `core.sys.windows`' `HDC`/`HFONT`/
 * `LOGFONTW`. GtkD has no binding for this header, so the C header is
 * the only reference.
 *
 * Not bound: `cairo-dwrite.h` (DirectWrite font faces), which Cairo
 * itself declares only for C++ because its functions take DirectWrite's
 * COM interfaces.
 *
 * Only compiled into a Cairo-enabled Windows build
 * (`version (FLDTK_HAVE_CAIRO)`).
 */
module fl.cairo_c_win32;

version (Windows):
version (FLDTK_HAVE_CAIRO):

import fl.cairo_c;
import core.sys.windows.windef : HDC, HFONT;
import core.sys.windows.wingdi : LOGFONTW;

extern (C) nothrow @nogc
{
    // ---- cairo-win32.h

    cairo_surface_t* cairo_win32_surface_create(HDC hdc);
    cairo_surface_t* cairo_win32_surface_create_with_format(HDC hdc, cairo_format_t format);
    cairo_surface_t* cairo_win32_printing_surface_create(HDC hdc);
    cairo_surface_t* cairo_win32_surface_create_with_ddb(HDC hdc, cairo_format_t format, int width, int height);
    cairo_surface_t* cairo_win32_surface_create_with_dib(cairo_format_t format, int width, int height);
    HDC cairo_win32_surface_get_dc(cairo_surface_t* surface);
    cairo_surface_t* cairo_win32_surface_get_image(cairo_surface_t* surface);

    // Win32 font support (CAIRO_HAS_WIN32_FONT)

    cairo_font_face_t* cairo_win32_font_face_create_for_logfontw(LOGFONTW* logfont);
    cairo_font_face_t* cairo_win32_font_face_create_for_hfont(HFONT font);
    cairo_font_face_t* cairo_win32_font_face_create_for_logfontw_hfont(LOGFONTW* logfont, HFONT font);
    cairo_status_t cairo_win32_scaled_font_select_font(cairo_scaled_font_t* scaled_font, HDC hdc);
    void cairo_win32_scaled_font_done_font(cairo_scaled_font_t* scaled_font);
    double cairo_win32_scaled_font_get_metrics_factor(cairo_scaled_font_t* scaled_font);
    void cairo_win32_scaled_font_get_logical_to_device(cairo_scaled_font_t* scaled_font, cairo_matrix_t* logical_to_device);
    void cairo_win32_scaled_font_get_device_to_logical(cairo_scaled_font_t* scaled_font, cairo_matrix_t* device_to_logical);
}
