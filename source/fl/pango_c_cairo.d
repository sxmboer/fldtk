/*
 * `extern(C)` bindings for Pango's Cairo backend (`pangocairo.h`): laying
 * out text with Pango and drawing it on a Cairo context. Transcribed and
 * checked the same way as `fl.pango_c` (Pango 1.57); re-exports
 * `fl.pango_c` and `fl.cairo_c`.
 *
 * Only compiled into a build with both Cairo and Pango support
 * (`version (FLDTK_HAVE_CAIRO)` and `version (FLDTK_HAVE_PANGO)`, both on
 * by default on Linux, off with dub configuration `linux-no-cairo`; on Windows only with `windows-cairo`).
 */
module fl.pango_c_cairo;

version (FLDTK_HAVE_PANGO):
version (FLDTK_HAVE_CAIRO):

public import fl.cairo_c;
public import fl.pango_c;

struct PangoCairoFont;
struct PangoCairoFontMap;
alias PangoCairoShapeRendererFunc = extern (C) void function(cairo_t* cr, PangoAttrShape* attr, int do_path, void* data);

extern (C) nothrow @nogc
{
    GType pango_cairo_font_map_get_type();
    PangoFontMap* pango_cairo_font_map_new();
    PangoFontMap* pango_cairo_font_map_new_for_font_type(cairo_font_type_t fonttype);
    PangoFontMap* pango_cairo_font_map_get_default();
    void pango_cairo_font_map_set_default(PangoCairoFontMap* fontmap);
    cairo_font_type_t pango_cairo_font_map_get_font_type(PangoCairoFontMap* fontmap);
    void pango_cairo_font_map_set_resolution(PangoCairoFontMap* fontmap, double dpi);
    double pango_cairo_font_map_get_resolution(PangoCairoFontMap* fontmap);
    deprecated("Use 'pango_font_map_create_context' instead") PangoContext* pango_cairo_font_map_create_context(PangoCairoFontMap* fontmap);
    GType pango_cairo_font_get_type();
    cairo_scaled_font_t* pango_cairo_font_get_scaled_font(PangoCairoFont* font);
    void pango_cairo_update_context(cairo_t* cr, PangoContext* context);
    void pango_cairo_context_set_font_options(PangoContext* context, const(cairo_font_options_t)* options);
    const(cairo_font_options_t)* pango_cairo_context_get_font_options(PangoContext* context);
    void pango_cairo_context_set_resolution(PangoContext* context, double dpi);
    double pango_cairo_context_get_resolution(PangoContext* context);
    void pango_cairo_context_set_shape_renderer(PangoContext* context, PangoCairoShapeRendererFunc func, void* data, GDestroyNotify dnotify);
    PangoCairoShapeRendererFunc pango_cairo_context_get_shape_renderer(PangoContext* context, void** data);
    PangoContext* pango_cairo_create_context(cairo_t* cr);
    PangoLayout* pango_cairo_create_layout(cairo_t* cr);
    void pango_cairo_update_layout(cairo_t* cr, PangoLayout* layout);
    void pango_cairo_show_glyph_string(cairo_t* cr, PangoFont* font, PangoGlyphString* glyphs);
    void pango_cairo_show_glyph_item(cairo_t* cr, const(char)* text, PangoGlyphItem* glyph_item);
    void pango_cairo_show_layout_line(cairo_t* cr, PangoLayoutLine* line);
    void pango_cairo_show_layout(cairo_t* cr, PangoLayout* layout);
    void pango_cairo_show_error_underline(cairo_t* cr, double x, double y, double width, double height);
    void pango_cairo_glyph_string_path(cairo_t* cr, PangoFont* font, PangoGlyphString* glyphs);
    void pango_cairo_layout_line_path(cairo_t* cr, PangoLayoutLine* line);
    void pango_cairo_layout_path(cairo_t* cr, PangoLayout* layout);
    void pango_cairo_error_underline_path(cairo_t* cr, double x, double y, double width, double height);
}

// ---- the PANGO_TYPE_* macros

GType PANGO_TYPE_CAIRO_FONT()() nothrow @nogc { return pango_cairo_font_get_type(); }
GType PANGO_TYPE_CAIRO_FONT_MAP()() nothrow @nogc { return pango_cairo_font_map_get_type(); }

// Headless: lays out and draws text on an image surface, which needs no
// display (only fontconfig and a font, which every Linux desktop has).
unittest
{
    cairo_surface_t* s = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, 200, 50);
    scope (exit) cairo_surface_destroy(s);
    cairo_t* cr = cairo_create(s);
    scope (exit) cairo_destroy(cr);

    PangoLayout* layout = pango_cairo_create_layout(cr);
    scope (exit) g_object_unref(layout);
    PangoFontDescription* desc = pango_font_description_from_string("Sans 12");
    scope (exit) pango_font_description_free(desc);
    pango_layout_set_font_description(layout, desc);
    pango_layout_set_text(layout, "fldtk", -1);

    int w, h;
    pango_layout_get_pixel_size(layout, &w, &h);
    assert(w > 0 && h > 0);

    PangoRectangle ink, logical;
    pango_layout_get_extents(layout, &ink, &logical);
    assert(PANGO_PIXELS(logical.width) == w);

    cairo_set_source_rgb(cr, 0, 0, 0);
    pango_cairo_show_layout(cr, layout);
    cairo_surface_flush(s);

    // Something was drawn: some pixel's alpha is no longer 0.
    auto data = cast(const(uint)*) cairo_image_surface_get_data(s);
    auto stride = cairo_image_surface_get_stride(s) / 4;
    bool drawn = false;
    foreach (y; 0 .. h)
        foreach (x; 0 .. w)
            if (data[y * stride + x] >> 24)
                drawn = true;
    assert(drawn);

    // Bitfield properties are reachable under their C names too.
    PangoLogAttr a;
    a.is_word_start = 1;
    assert(a.isWordStart == 1 && !a.isLineBreak);

    assert(pango_version() >= PANGO_VERSION_ENCODE(1, 57, 0));
    assert(PANGO_TYPE_LAYOUT() == pango_layout_get_type());
}
