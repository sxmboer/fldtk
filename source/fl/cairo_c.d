/*
 * `extern(C)` bindings for the Cairo 2D graphics library: the complete
 * public API of `cairo.h`, plus the file/recording-style surface headers
 * that ship in the same `libcairo.so` -- `cairo-pdf.h`, `cairo-ps.h`,
 * `cairo-svg.h`, `cairo-script.h` and `cairo-tee.h`. The Xlib surface
 * (`cairo-xlib.h`) is in `fl.cairo_c_xlib`, since it depends on
 * `fl.xlib`. Not a port of an FLTK header -- infrastructure, the same
 * role `fl.xlib` plays for libX11. Named after GtkD's `cairo.c` package
 * (the C-level layer); `fl.cairo` is the port of FLTK's `Fl_Cairo.H`.
 * Not bound: `cairo-ft.h` (needs
 * FreeType/fontconfig types), `cairo-xcb.h`, `cairo-xlib-xrender.h` and
 * `cairo-gobject.h`.
 *
 * Transcribed from the Cairo 1.18.4 headers (`/usr/include/cairo/`), with
 * GtkD's `cairo.c.types`/`cairo.c.functions` used to cross-check every
 * function's presence and parameter count, every enum's members and every
 * struct's layout. Functions and parameter types follow the C headers;
 * `const char*` is `const(char)*`, so D string literals pass directly.
 * API added after GtkD's bindings were made (hairlines, tags, dithering,
 * color fonts, observer surfaces, PDF metadata/outlines, ...) is
 * included.
 *
 * Names follow GtkD's C layer, so code written against GtkD's
 * `cairo.c.*` compiles unchanged: an enum's members drop the type's own
 * prefix (`cairo_format_t.ARGB32`), each enum has a CamelCase alias
 * (`CairoFormat`), and struct fields are camelCase
 * (`cairo_text_extents_t.xBearing`). Every enum member is also available
 * under its C name (`CAIRO_FORMAT_ARGB32`) and every camelCase struct
 * field under its C name (`x_bearing`, an alias), so C examples port
 * verbatim too.
 *
 * Only compiled into a Cairo-enabled build (`version (FLDTK_HAVE_CAIRO)`,
 * on by default on Linux, off with dub configuration `linux-no-cairo`; on Windows only with `windows-cairo`;
 * see BUILDING.md), the equivalent of FLTK's CMake option
 * FLTK_OPTION_CAIRO_WINDOW.
 */
module fl.cairo_c;

version (FLDTK_HAVE_CAIRO):

import core.stdc.config : c_ulong, c_long;

// Runs the static libraries' GCC constructors (pixman's among them) on
// Windows; see fl.mingw_runtime.
version (Windows) import fl.mingw_runtime;

/// The Cairo version these bindings were transcribed from
/// (`cairo-version.h`). `cairo_version()` reports the version of the
/// library actually loaded at run time.
enum CAIRO_VERSION_MAJOR = 1;
/// ditto
enum CAIRO_VERSION_MINOR = 18;
/// ditto
enum CAIRO_VERSION_MICRO = 4;

/// `CAIRO_VERSION_ENCODE()`, a function here instead of a macro.
int CAIRO_VERSION_ENCODE(int major, int minor, int micro) pure nothrow @nogc @safe
{
    return major * 10000 + minor * 100 + micro;
}

/// ditto
enum CAIRO_VERSION = CAIRO_VERSION_ENCODE(CAIRO_VERSION_MAJOR, CAIRO_VERSION_MINOR, CAIRO_VERSION_MICRO);

/// `CAIRO_VERSION_STRING`.
enum CAIRO_VERSION_STRING = "1.18.4";

// ---- cairo.h

alias cairo_bool_t = int;
struct cairo_t;
struct cairo_surface_t;
struct cairo_device_t;
struct cairo_matrix_t
{
    double xx;
    double yx;
    double xy;
    double yy;
    double x0;
    double y0;
}

struct cairo_pattern_t;
alias cairo_destroy_func_t = extern (C) void function(void* data);

struct cairo_user_data_key_t
{
    int unused;
}

enum cairo_status_t
{
    SUCCESS = 0,
    NO_MEMORY,
    INVALID_RESTORE,
    INVALID_POP_GROUP,
    NO_CURRENT_POINT,
    INVALID_MATRIX,
    INVALID_STATUS,
    NULL_POINTER,
    INVALID_STRING,
    INVALID_PATH_DATA,
    READ_ERROR,
    WRITE_ERROR,
    SURFACE_FINISHED,
    SURFACE_TYPE_MISMATCH,
    PATTERN_TYPE_MISMATCH,
    INVALID_CONTENT,
    INVALID_FORMAT,
    INVALID_VISUAL,
    FILE_NOT_FOUND,
    INVALID_DASH,
    INVALID_DSC_COMMENT,
    INVALID_INDEX,
    CLIP_NOT_REPRESENTABLE,
    TEMP_FILE_ERROR,
    INVALID_STRIDE,
    FONT_TYPE_MISMATCH,
    USER_FONT_IMMUTABLE,
    USER_FONT_ERROR,
    NEGATIVE_COUNT,
    INVALID_CLUSTERS,
    INVALID_SLANT,
    INVALID_WEIGHT,
    INVALID_SIZE,
    USER_FONT_NOT_IMPLEMENTED,
    DEVICE_TYPE_MISMATCH,
    DEVICE_ERROR,
    INVALID_MESH_CONSTRUCTION,
    DEVICE_FINISHED,
    JBIG2_GLOBAL_MISSING,
    PNG_ERROR,
    FREETYPE_ERROR,
    WIN32_GDI_ERROR,
    TAG_ERROR,
    DWRITE_ERROR,
    SVG_FONT_ERROR,
    LAST_STATUS,
}
alias CairoStatus = cairo_status_t;
enum CAIRO_STATUS_SUCCESS = cairo_status_t.SUCCESS;
enum CAIRO_STATUS_NO_MEMORY = cairo_status_t.NO_MEMORY;
enum CAIRO_STATUS_INVALID_RESTORE = cairo_status_t.INVALID_RESTORE;
enum CAIRO_STATUS_INVALID_POP_GROUP = cairo_status_t.INVALID_POP_GROUP;
enum CAIRO_STATUS_NO_CURRENT_POINT = cairo_status_t.NO_CURRENT_POINT;
enum CAIRO_STATUS_INVALID_MATRIX = cairo_status_t.INVALID_MATRIX;
enum CAIRO_STATUS_INVALID_STATUS = cairo_status_t.INVALID_STATUS;
enum CAIRO_STATUS_NULL_POINTER = cairo_status_t.NULL_POINTER;
enum CAIRO_STATUS_INVALID_STRING = cairo_status_t.INVALID_STRING;
enum CAIRO_STATUS_INVALID_PATH_DATA = cairo_status_t.INVALID_PATH_DATA;
enum CAIRO_STATUS_READ_ERROR = cairo_status_t.READ_ERROR;
enum CAIRO_STATUS_WRITE_ERROR = cairo_status_t.WRITE_ERROR;
enum CAIRO_STATUS_SURFACE_FINISHED = cairo_status_t.SURFACE_FINISHED;
enum CAIRO_STATUS_SURFACE_TYPE_MISMATCH = cairo_status_t.SURFACE_TYPE_MISMATCH;
enum CAIRO_STATUS_PATTERN_TYPE_MISMATCH = cairo_status_t.PATTERN_TYPE_MISMATCH;
enum CAIRO_STATUS_INVALID_CONTENT = cairo_status_t.INVALID_CONTENT;
enum CAIRO_STATUS_INVALID_FORMAT = cairo_status_t.INVALID_FORMAT;
enum CAIRO_STATUS_INVALID_VISUAL = cairo_status_t.INVALID_VISUAL;
enum CAIRO_STATUS_FILE_NOT_FOUND = cairo_status_t.FILE_NOT_FOUND;
enum CAIRO_STATUS_INVALID_DASH = cairo_status_t.INVALID_DASH;
enum CAIRO_STATUS_INVALID_DSC_COMMENT = cairo_status_t.INVALID_DSC_COMMENT;
enum CAIRO_STATUS_INVALID_INDEX = cairo_status_t.INVALID_INDEX;
enum CAIRO_STATUS_CLIP_NOT_REPRESENTABLE = cairo_status_t.CLIP_NOT_REPRESENTABLE;
enum CAIRO_STATUS_TEMP_FILE_ERROR = cairo_status_t.TEMP_FILE_ERROR;
enum CAIRO_STATUS_INVALID_STRIDE = cairo_status_t.INVALID_STRIDE;
enum CAIRO_STATUS_FONT_TYPE_MISMATCH = cairo_status_t.FONT_TYPE_MISMATCH;
enum CAIRO_STATUS_USER_FONT_IMMUTABLE = cairo_status_t.USER_FONT_IMMUTABLE;
enum CAIRO_STATUS_USER_FONT_ERROR = cairo_status_t.USER_FONT_ERROR;
enum CAIRO_STATUS_NEGATIVE_COUNT = cairo_status_t.NEGATIVE_COUNT;
enum CAIRO_STATUS_INVALID_CLUSTERS = cairo_status_t.INVALID_CLUSTERS;
enum CAIRO_STATUS_INVALID_SLANT = cairo_status_t.INVALID_SLANT;
enum CAIRO_STATUS_INVALID_WEIGHT = cairo_status_t.INVALID_WEIGHT;
enum CAIRO_STATUS_INVALID_SIZE = cairo_status_t.INVALID_SIZE;
enum CAIRO_STATUS_USER_FONT_NOT_IMPLEMENTED = cairo_status_t.USER_FONT_NOT_IMPLEMENTED;
enum CAIRO_STATUS_DEVICE_TYPE_MISMATCH = cairo_status_t.DEVICE_TYPE_MISMATCH;
enum CAIRO_STATUS_DEVICE_ERROR = cairo_status_t.DEVICE_ERROR;
enum CAIRO_STATUS_INVALID_MESH_CONSTRUCTION = cairo_status_t.INVALID_MESH_CONSTRUCTION;
enum CAIRO_STATUS_DEVICE_FINISHED = cairo_status_t.DEVICE_FINISHED;
enum CAIRO_STATUS_JBIG2_GLOBAL_MISSING = cairo_status_t.JBIG2_GLOBAL_MISSING;
enum CAIRO_STATUS_PNG_ERROR = cairo_status_t.PNG_ERROR;
enum CAIRO_STATUS_FREETYPE_ERROR = cairo_status_t.FREETYPE_ERROR;
enum CAIRO_STATUS_WIN32_GDI_ERROR = cairo_status_t.WIN32_GDI_ERROR;
enum CAIRO_STATUS_TAG_ERROR = cairo_status_t.TAG_ERROR;
enum CAIRO_STATUS_DWRITE_ERROR = cairo_status_t.DWRITE_ERROR;
enum CAIRO_STATUS_SVG_FONT_ERROR = cairo_status_t.SVG_FONT_ERROR;
enum CAIRO_STATUS_LAST_STATUS = cairo_status_t.LAST_STATUS;

enum cairo_content_t
{
    COLOR = 0x1000,
    ALPHA = 0x2000,
    COLOR_ALPHA = 0x3000,
}
alias CairoContent = cairo_content_t;
enum CAIRO_CONTENT_COLOR = cairo_content_t.COLOR;
enum CAIRO_CONTENT_ALPHA = cairo_content_t.ALPHA;
enum CAIRO_CONTENT_COLOR_ALPHA = cairo_content_t.COLOR_ALPHA;

enum cairo_format_t
{
    INVALID = -1,
    ARGB32 = 0,
    RGB24 = 1,
    A8 = 2,
    A1 = 3,
    RGB16_565 = 4,
    RGB30 = 5,
    RGB96F = 6,
    RGBA128F = 7,
}
alias CairoFormat = cairo_format_t;
enum CAIRO_FORMAT_INVALID = cairo_format_t.INVALID;
enum CAIRO_FORMAT_ARGB32 = cairo_format_t.ARGB32;
enum CAIRO_FORMAT_RGB24 = cairo_format_t.RGB24;
enum CAIRO_FORMAT_A8 = cairo_format_t.A8;
enum CAIRO_FORMAT_A1 = cairo_format_t.A1;
enum CAIRO_FORMAT_RGB16_565 = cairo_format_t.RGB16_565;
enum CAIRO_FORMAT_RGB30 = cairo_format_t.RGB30;
enum CAIRO_FORMAT_RGB96F = cairo_format_t.RGB96F;
enum CAIRO_FORMAT_RGBA128F = cairo_format_t.RGBA128F;

enum cairo_dither_t
{
    NONE,
    DEFAULT,
    FAST,
    GOOD,
    BEST,
}
alias CairoDither = cairo_dither_t;
enum CAIRO_DITHER_NONE = cairo_dither_t.NONE;
enum CAIRO_DITHER_DEFAULT = cairo_dither_t.DEFAULT;
enum CAIRO_DITHER_FAST = cairo_dither_t.FAST;
enum CAIRO_DITHER_GOOD = cairo_dither_t.GOOD;
enum CAIRO_DITHER_BEST = cairo_dither_t.BEST;

alias cairo_write_func_t = extern (C) cairo_status_t function(void* closure, const(ubyte)* data, uint length_);

alias cairo_read_func_t = extern (C) cairo_status_t function(void* closure, ubyte* data, uint length_);

struct cairo_rectangle_int_t
{
    int x;
    int y;
    int width;
    int height;
}

enum cairo_operator_t
{
    CLEAR,
    SOURCE,
    OVER,
    IN,
    OUT,
    ATOP,
    DEST,
    DEST_OVER,
    DEST_IN,
    DEST_OUT,
    DEST_ATOP,
    XOR,
    ADD,
    SATURATE,
    MULTIPLY,
    SCREEN,
    OVERLAY,
    DARKEN,
    LIGHTEN,
    COLOR_DODGE,
    COLOR_BURN,
    HARD_LIGHT,
    SOFT_LIGHT,
    DIFFERENCE,
    EXCLUSION,
    HSL_HUE,
    HSL_SATURATION,
    HSL_COLOR,
    HSL_LUMINOSITY,
}
alias CairoOperator = cairo_operator_t;
enum CAIRO_OPERATOR_CLEAR = cairo_operator_t.CLEAR;
enum CAIRO_OPERATOR_SOURCE = cairo_operator_t.SOURCE;
enum CAIRO_OPERATOR_OVER = cairo_operator_t.OVER;
enum CAIRO_OPERATOR_IN = cairo_operator_t.IN;
enum CAIRO_OPERATOR_OUT = cairo_operator_t.OUT;
enum CAIRO_OPERATOR_ATOP = cairo_operator_t.ATOP;
enum CAIRO_OPERATOR_DEST = cairo_operator_t.DEST;
enum CAIRO_OPERATOR_DEST_OVER = cairo_operator_t.DEST_OVER;
enum CAIRO_OPERATOR_DEST_IN = cairo_operator_t.DEST_IN;
enum CAIRO_OPERATOR_DEST_OUT = cairo_operator_t.DEST_OUT;
enum CAIRO_OPERATOR_DEST_ATOP = cairo_operator_t.DEST_ATOP;
enum CAIRO_OPERATOR_XOR = cairo_operator_t.XOR;
enum CAIRO_OPERATOR_ADD = cairo_operator_t.ADD;
enum CAIRO_OPERATOR_SATURATE = cairo_operator_t.SATURATE;
enum CAIRO_OPERATOR_MULTIPLY = cairo_operator_t.MULTIPLY;
enum CAIRO_OPERATOR_SCREEN = cairo_operator_t.SCREEN;
enum CAIRO_OPERATOR_OVERLAY = cairo_operator_t.OVERLAY;
enum CAIRO_OPERATOR_DARKEN = cairo_operator_t.DARKEN;
enum CAIRO_OPERATOR_LIGHTEN = cairo_operator_t.LIGHTEN;
enum CAIRO_OPERATOR_COLOR_DODGE = cairo_operator_t.COLOR_DODGE;
enum CAIRO_OPERATOR_COLOR_BURN = cairo_operator_t.COLOR_BURN;
enum CAIRO_OPERATOR_HARD_LIGHT = cairo_operator_t.HARD_LIGHT;
enum CAIRO_OPERATOR_SOFT_LIGHT = cairo_operator_t.SOFT_LIGHT;
enum CAIRO_OPERATOR_DIFFERENCE = cairo_operator_t.DIFFERENCE;
enum CAIRO_OPERATOR_EXCLUSION = cairo_operator_t.EXCLUSION;
enum CAIRO_OPERATOR_HSL_HUE = cairo_operator_t.HSL_HUE;
enum CAIRO_OPERATOR_HSL_SATURATION = cairo_operator_t.HSL_SATURATION;
enum CAIRO_OPERATOR_HSL_COLOR = cairo_operator_t.HSL_COLOR;
enum CAIRO_OPERATOR_HSL_LUMINOSITY = cairo_operator_t.HSL_LUMINOSITY;

enum cairo_antialias_t
{
    DEFAULT,
    NONE,
    GRAY,
    SUBPIXEL,
    FAST,
    GOOD,
    BEST,
}
alias CairoAntialias = cairo_antialias_t;
enum CAIRO_ANTIALIAS_DEFAULT = cairo_antialias_t.DEFAULT;
enum CAIRO_ANTIALIAS_NONE = cairo_antialias_t.NONE;
enum CAIRO_ANTIALIAS_GRAY = cairo_antialias_t.GRAY;
enum CAIRO_ANTIALIAS_SUBPIXEL = cairo_antialias_t.SUBPIXEL;
enum CAIRO_ANTIALIAS_FAST = cairo_antialias_t.FAST;
enum CAIRO_ANTIALIAS_GOOD = cairo_antialias_t.GOOD;
enum CAIRO_ANTIALIAS_BEST = cairo_antialias_t.BEST;

enum cairo_fill_rule_t
{
    WINDING,
    EVEN_ODD,
}
alias CairoFillRule = cairo_fill_rule_t;
enum CAIRO_FILL_RULE_WINDING = cairo_fill_rule_t.WINDING;
enum CAIRO_FILL_RULE_EVEN_ODD = cairo_fill_rule_t.EVEN_ODD;

enum cairo_line_cap_t
{
    BUTT,
    ROUND,
    SQUARE,
}
alias CairoLineCap = cairo_line_cap_t;
enum CAIRO_LINE_CAP_BUTT = cairo_line_cap_t.BUTT;
enum CAIRO_LINE_CAP_ROUND = cairo_line_cap_t.ROUND;
enum CAIRO_LINE_CAP_SQUARE = cairo_line_cap_t.SQUARE;

enum cairo_line_join_t
{
    MITER,
    ROUND,
    BEVEL,
}
alias CairoLineJoin = cairo_line_join_t;
enum CAIRO_LINE_JOIN_MITER = cairo_line_join_t.MITER;
enum CAIRO_LINE_JOIN_ROUND = cairo_line_join_t.ROUND;
enum CAIRO_LINE_JOIN_BEVEL = cairo_line_join_t.BEVEL;

struct cairo_rectangle_t
{
    double x;
    double y;
    double width;
    double height;
}

struct cairo_rectangle_list_t
{
    cairo_status_t status;
    cairo_rectangle_t* rectangles;
    int numRectangles;
    alias num_rectangles = numRectangles; // C name
}

enum CAIRO_TAG_DEST = "cairo.dest";
enum CAIRO_TAG_LINK = "Link";
enum CAIRO_TAG_CONTENT = "cairo.content";
enum CAIRO_TAG_CONTENT_REF = "cairo.content_ref";
struct cairo_scaled_font_t;
struct cairo_font_face_t;
struct cairo_glyph_t
{
    c_ulong index;
    double x;
    double y;
}

struct cairo_text_cluster_t
{
    int numBytes;
    int numGlyphs;
    alias num_bytes = numBytes; // C name
    alias num_glyphs = numGlyphs; // C name
}

enum cairo_text_cluster_flags_t
{
    BACKWARD = 0x00000001,
}
alias CairoTextClusterFlags = cairo_text_cluster_flags_t;
enum CAIRO_TEXT_CLUSTER_FLAG_BACKWARD = cairo_text_cluster_flags_t.BACKWARD;

struct cairo_text_extents_t
{
    double xBearing;
    double yBearing;
    double width;
    double height;
    double xAdvance;
    double yAdvance;
    alias x_bearing = xBearing; // C name
    alias y_bearing = yBearing; // C name
    alias x_advance = xAdvance; // C name
    alias y_advance = yAdvance; // C name
}

struct cairo_font_extents_t
{
    double ascent;
    double descent;
    double height;
    double maxXAdvance;
    double maxYAdvance;
    alias max_x_advance = maxXAdvance; // C name
    alias max_y_advance = maxYAdvance; // C name
}

enum cairo_font_slant_t
{
    NORMAL,
    ITALIC,
    OBLIQUE,
}
alias CairoFontSlant = cairo_font_slant_t;
enum CAIRO_FONT_SLANT_NORMAL = cairo_font_slant_t.NORMAL;
enum CAIRO_FONT_SLANT_ITALIC = cairo_font_slant_t.ITALIC;
enum CAIRO_FONT_SLANT_OBLIQUE = cairo_font_slant_t.OBLIQUE;

enum cairo_font_weight_t
{
    NORMAL,
    BOLD,
}
alias CairoFontWeight = cairo_font_weight_t;
enum CAIRO_FONT_WEIGHT_NORMAL = cairo_font_weight_t.NORMAL;
enum CAIRO_FONT_WEIGHT_BOLD = cairo_font_weight_t.BOLD;

enum cairo_subpixel_order_t
{
    DEFAULT,
    RGB,
    BGR,
    VRGB,
    VBGR,
}
alias CairoSubpixelOrder = cairo_subpixel_order_t;
enum CAIRO_SUBPIXEL_ORDER_DEFAULT = cairo_subpixel_order_t.DEFAULT;
enum CAIRO_SUBPIXEL_ORDER_RGB = cairo_subpixel_order_t.RGB;
enum CAIRO_SUBPIXEL_ORDER_BGR = cairo_subpixel_order_t.BGR;
enum CAIRO_SUBPIXEL_ORDER_VRGB = cairo_subpixel_order_t.VRGB;
enum CAIRO_SUBPIXEL_ORDER_VBGR = cairo_subpixel_order_t.VBGR;

enum cairo_hint_style_t
{
    DEFAULT,
    NONE,
    SLIGHT,
    MEDIUM,
    FULL,
}
alias CairoHintStyle = cairo_hint_style_t;
enum CAIRO_HINT_STYLE_DEFAULT = cairo_hint_style_t.DEFAULT;
enum CAIRO_HINT_STYLE_NONE = cairo_hint_style_t.NONE;
enum CAIRO_HINT_STYLE_SLIGHT = cairo_hint_style_t.SLIGHT;
enum CAIRO_HINT_STYLE_MEDIUM = cairo_hint_style_t.MEDIUM;
enum CAIRO_HINT_STYLE_FULL = cairo_hint_style_t.FULL;

enum cairo_hint_metrics_t
{
    DEFAULT,
    OFF,
    ON,
}
alias CairoHintMetrics = cairo_hint_metrics_t;
enum CAIRO_HINT_METRICS_DEFAULT = cairo_hint_metrics_t.DEFAULT;
enum CAIRO_HINT_METRICS_OFF = cairo_hint_metrics_t.OFF;
enum CAIRO_HINT_METRICS_ON = cairo_hint_metrics_t.ON;

enum cairo_color_mode_t
{
    DEFAULT,
    NO_COLOR,
    COLOR,
}
alias CairoColorMode = cairo_color_mode_t;
enum CAIRO_COLOR_MODE_DEFAULT = cairo_color_mode_t.DEFAULT;
enum CAIRO_COLOR_MODE_NO_COLOR = cairo_color_mode_t.NO_COLOR;
enum CAIRO_COLOR_MODE_COLOR = cairo_color_mode_t.COLOR;

struct cairo_font_options_t;
enum CAIRO_COLOR_PALETTE_DEFAULT = 0;
enum cairo_font_type_t
{
    TOY,
    FT,
    WIN32,
    QUARTZ,
    USER,
    DWRITE,
}
alias CairoFontType = cairo_font_type_t;
enum CAIRO_FONT_TYPE_TOY = cairo_font_type_t.TOY;
enum CAIRO_FONT_TYPE_FT = cairo_font_type_t.FT;
enum CAIRO_FONT_TYPE_WIN32 = cairo_font_type_t.WIN32;
enum CAIRO_FONT_TYPE_QUARTZ = cairo_font_type_t.QUARTZ;
enum CAIRO_FONT_TYPE_USER = cairo_font_type_t.USER;
enum CAIRO_FONT_TYPE_DWRITE = cairo_font_type_t.DWRITE;

alias cairo_user_scaled_font_init_func_t = extern (C) cairo_status_t function(cairo_scaled_font_t* scaled_font, cairo_t* cr, cairo_font_extents_t* extents);

alias cairo_user_scaled_font_render_glyph_func_t = extern (C) cairo_status_t function(cairo_scaled_font_t* scaled_font, c_ulong glyph, cairo_t* cr, cairo_text_extents_t* extents);

alias cairo_user_scaled_font_text_to_glyphs_func_t = extern (C) cairo_status_t function(cairo_scaled_font_t* scaled_font, const(char)* utf8, int utf8_len, cairo_glyph_t** glyphs, int* num_glyphs, cairo_text_cluster_t** clusters, int* num_clusters, cairo_text_cluster_flags_t* cluster_flags);

alias cairo_user_scaled_font_unicode_to_glyph_func_t = extern (C) cairo_status_t function(cairo_scaled_font_t* scaled_font, c_ulong unicode, c_ulong* glyph_index);

enum cairo_path_data_type_t
{
    MOVE_TO,
    LINE_TO,
    CURVE_TO,
    CLOSE_PATH,
}
alias CairoPathDataType = cairo_path_data_type_t;
enum CAIRO_PATH_MOVE_TO = cairo_path_data_type_t.MOVE_TO;
enum CAIRO_PATH_LINE_TO = cairo_path_data_type_t.LINE_TO;
enum CAIRO_PATH_CURVE_TO = cairo_path_data_type_t.CURVE_TO;
enum CAIRO_PATH_CLOSE_PATH = cairo_path_data_type_t.CLOSE_PATH;

union cairo_path_data_t
{
    struct Header
    {
        cairo_path_data_type_t type;
        int length;
    }
    struct Point
    {
        double x, y;
    }
    Header header;
    Point point;
}

struct cairo_path_t
{
    cairo_status_t status;
    cairo_path_data_t* data;
    int numData;
    alias num_data = numData; // C name
}

enum cairo_device_type_t
{
    DRM,
    GL,
    SCRIPT,
    XCB,
    XLIB,
    XML,
    COGL,
    WIN32,
    INVALID = -1,
}
alias CairoDeviceType = cairo_device_type_t;
enum CAIRO_DEVICE_TYPE_DRM = cairo_device_type_t.DRM;
enum CAIRO_DEVICE_TYPE_GL = cairo_device_type_t.GL;
enum CAIRO_DEVICE_TYPE_SCRIPT = cairo_device_type_t.SCRIPT;
enum CAIRO_DEVICE_TYPE_XCB = cairo_device_type_t.XCB;
enum CAIRO_DEVICE_TYPE_XLIB = cairo_device_type_t.XLIB;
enum CAIRO_DEVICE_TYPE_XML = cairo_device_type_t.XML;
enum CAIRO_DEVICE_TYPE_COGL = cairo_device_type_t.COGL;
enum CAIRO_DEVICE_TYPE_WIN32 = cairo_device_type_t.WIN32;
enum CAIRO_DEVICE_TYPE_INVALID = cairo_device_type_t.INVALID;

enum cairo_surface_observer_mode_t
{
    NORMAL = 0,
    RECORD_OPERATIONS = 0x1,
}
alias CairoSurfaceObserverMode = cairo_surface_observer_mode_t;
enum CAIRO_SURFACE_OBSERVER_NORMAL = cairo_surface_observer_mode_t.NORMAL;
enum CAIRO_SURFACE_OBSERVER_RECORD_OPERATIONS = cairo_surface_observer_mode_t.RECORD_OPERATIONS;

alias cairo_surface_observer_callback_t = extern (C) void function(cairo_surface_t* observer, cairo_surface_t* target, void* data);

enum cairo_surface_type_t
{
    IMAGE,
    PDF,
    PS,
    XLIB,
    XCB,
    GLITZ,
    QUARTZ,
    WIN32,
    BEOS,
    DIRECTFB,
    SVG,
    OS2,
    WIN32_PRINTING,
    QUARTZ_IMAGE,
    SCRIPT,
    QT,
    RECORDING,
    VG,
    GL,
    DRM,
    TEE,
    XML,
    SKIA,
    SUBSURFACE,
    COGL,
}
alias CairoSurfaceType = cairo_surface_type_t;
enum CAIRO_SURFACE_TYPE_IMAGE = cairo_surface_type_t.IMAGE;
enum CAIRO_SURFACE_TYPE_PDF = cairo_surface_type_t.PDF;
enum CAIRO_SURFACE_TYPE_PS = cairo_surface_type_t.PS;
enum CAIRO_SURFACE_TYPE_XLIB = cairo_surface_type_t.XLIB;
enum CAIRO_SURFACE_TYPE_XCB = cairo_surface_type_t.XCB;
enum CAIRO_SURFACE_TYPE_GLITZ = cairo_surface_type_t.GLITZ;
enum CAIRO_SURFACE_TYPE_QUARTZ = cairo_surface_type_t.QUARTZ;
enum CAIRO_SURFACE_TYPE_WIN32 = cairo_surface_type_t.WIN32;
enum CAIRO_SURFACE_TYPE_BEOS = cairo_surface_type_t.BEOS;
enum CAIRO_SURFACE_TYPE_DIRECTFB = cairo_surface_type_t.DIRECTFB;
enum CAIRO_SURFACE_TYPE_SVG = cairo_surface_type_t.SVG;
enum CAIRO_SURFACE_TYPE_OS2 = cairo_surface_type_t.OS2;
enum CAIRO_SURFACE_TYPE_WIN32_PRINTING = cairo_surface_type_t.WIN32_PRINTING;
enum CAIRO_SURFACE_TYPE_QUARTZ_IMAGE = cairo_surface_type_t.QUARTZ_IMAGE;
enum CAIRO_SURFACE_TYPE_SCRIPT = cairo_surface_type_t.SCRIPT;
enum CAIRO_SURFACE_TYPE_QT = cairo_surface_type_t.QT;
enum CAIRO_SURFACE_TYPE_RECORDING = cairo_surface_type_t.RECORDING;
enum CAIRO_SURFACE_TYPE_VG = cairo_surface_type_t.VG;
enum CAIRO_SURFACE_TYPE_GL = cairo_surface_type_t.GL;
enum CAIRO_SURFACE_TYPE_DRM = cairo_surface_type_t.DRM;
enum CAIRO_SURFACE_TYPE_TEE = cairo_surface_type_t.TEE;
enum CAIRO_SURFACE_TYPE_XML = cairo_surface_type_t.XML;
enum CAIRO_SURFACE_TYPE_SKIA = cairo_surface_type_t.SKIA;
enum CAIRO_SURFACE_TYPE_SUBSURFACE = cairo_surface_type_t.SUBSURFACE;
enum CAIRO_SURFACE_TYPE_COGL = cairo_surface_type_t.COGL;

enum CAIRO_MIME_TYPE_JPEG = "image/jpeg";
enum CAIRO_MIME_TYPE_PNG = "image/png";
enum CAIRO_MIME_TYPE_JP2 = "image/jp2";
enum CAIRO_MIME_TYPE_URI = "text/x-uri";
enum CAIRO_MIME_TYPE_UNIQUE_ID = "application/x-cairo.uuid";
enum CAIRO_MIME_TYPE_JBIG2 = "application/x-cairo.jbig2";
enum CAIRO_MIME_TYPE_JBIG2_GLOBAL = "application/x-cairo.jbig2-global";
enum CAIRO_MIME_TYPE_JBIG2_GLOBAL_ID = "application/x-cairo.jbig2-global-id";
enum CAIRO_MIME_TYPE_CCITT_FAX = "image/g3fax";
enum CAIRO_MIME_TYPE_CCITT_FAX_PARAMS = "application/x-cairo.ccitt.params";
enum CAIRO_MIME_TYPE_EPS = "application/postscript";
enum CAIRO_MIME_TYPE_EPS_PARAMS = "application/x-cairo.eps.params";
alias cairo_raster_source_acquire_func_t = extern (C) cairo_surface_t* function(cairo_pattern_t* pattern, void* callback_data, cairo_surface_t* target, const(cairo_rectangle_int_t)* extents);

alias cairo_raster_source_release_func_t = extern (C) void function(cairo_pattern_t* pattern, void* callback_data, cairo_surface_t* surface);

alias cairo_raster_source_snapshot_func_t = extern (C) cairo_status_t function(cairo_pattern_t* pattern, void* callback_data);

alias cairo_raster_source_copy_func_t = extern (C) cairo_status_t function(cairo_pattern_t* pattern, void* callback_data, const(cairo_pattern_t)* other);

alias cairo_raster_source_finish_func_t = extern (C) void function(cairo_pattern_t* pattern, void* callback_data);

enum cairo_pattern_type_t
{
    SOLID,
    SURFACE,
    LINEAR,
    RADIAL,
    MESH,
    RASTER_SOURCE,
}
alias CairoPatternType = cairo_pattern_type_t;
enum CAIRO_PATTERN_TYPE_SOLID = cairo_pattern_type_t.SOLID;
enum CAIRO_PATTERN_TYPE_SURFACE = cairo_pattern_type_t.SURFACE;
enum CAIRO_PATTERN_TYPE_LINEAR = cairo_pattern_type_t.LINEAR;
enum CAIRO_PATTERN_TYPE_RADIAL = cairo_pattern_type_t.RADIAL;
enum CAIRO_PATTERN_TYPE_MESH = cairo_pattern_type_t.MESH;
enum CAIRO_PATTERN_TYPE_RASTER_SOURCE = cairo_pattern_type_t.RASTER_SOURCE;

enum cairo_extend_t
{
    NONE,
    REPEAT,
    REFLECT,
    PAD,
}
alias CairoExtend = cairo_extend_t;
enum CAIRO_EXTEND_NONE = cairo_extend_t.NONE;
enum CAIRO_EXTEND_REPEAT = cairo_extend_t.REPEAT;
enum CAIRO_EXTEND_REFLECT = cairo_extend_t.REFLECT;
enum CAIRO_EXTEND_PAD = cairo_extend_t.PAD;

enum cairo_filter_t
{
    FAST,
    GOOD,
    BEST,
    NEAREST,
    BILINEAR,
    GAUSSIAN,
}
alias CairoFilter = cairo_filter_t;
enum CAIRO_FILTER_FAST = cairo_filter_t.FAST;
enum CAIRO_FILTER_GOOD = cairo_filter_t.GOOD;
enum CAIRO_FILTER_BEST = cairo_filter_t.BEST;
enum CAIRO_FILTER_NEAREST = cairo_filter_t.NEAREST;
enum CAIRO_FILTER_BILINEAR = cairo_filter_t.BILINEAR;
enum CAIRO_FILTER_GAUSSIAN = cairo_filter_t.GAUSSIAN;

struct cairo_region_t;
enum cairo_region_overlap_t
{
    IN,
    OUT,
    PART,
}
alias CairoRegionOverlap = cairo_region_overlap_t;
enum CAIRO_REGION_OVERLAP_IN = cairo_region_overlap_t.IN;
enum CAIRO_REGION_OVERLAP_OUT = cairo_region_overlap_t.OUT;
enum CAIRO_REGION_OVERLAP_PART = cairo_region_overlap_t.PART;

// ---- cairo-pdf.h

enum cairo_pdf_version_t
{
    VERSION_1_4,
    VERSION_1_5,
    VERSION_1_6,
    VERSION_1_7,
}
alias CairoPdfVersion = cairo_pdf_version_t;
enum CAIRO_PDF_VERSION_1_4 = cairo_pdf_version_t.VERSION_1_4;
enum CAIRO_PDF_VERSION_1_5 = cairo_pdf_version_t.VERSION_1_5;
enum CAIRO_PDF_VERSION_1_6 = cairo_pdf_version_t.VERSION_1_6;
enum CAIRO_PDF_VERSION_1_7 = cairo_pdf_version_t.VERSION_1_7;

enum cairo_pdf_outline_flags_t
{
    OPEN = 0x1,
    BOLD = 0x2,
    ITALIC = 0x4,
}
alias CairoPdfOutlineFlags = cairo_pdf_outline_flags_t;
enum CAIRO_PDF_OUTLINE_FLAG_OPEN = cairo_pdf_outline_flags_t.OPEN;
enum CAIRO_PDF_OUTLINE_FLAG_BOLD = cairo_pdf_outline_flags_t.BOLD;
enum CAIRO_PDF_OUTLINE_FLAG_ITALIC = cairo_pdf_outline_flags_t.ITALIC;

enum CAIRO_PDF_OUTLINE_ROOT = 0;
enum cairo_pdf_metadata_t
{
    TITLE,
    AUTHOR,
    SUBJECT,
    KEYWORDS,
    CREATOR,
    CREATE_DATE,
    MOD_DATE,
}
alias CairoPdfMetadata = cairo_pdf_metadata_t;
enum CAIRO_PDF_METADATA_TITLE = cairo_pdf_metadata_t.TITLE;
enum CAIRO_PDF_METADATA_AUTHOR = cairo_pdf_metadata_t.AUTHOR;
enum CAIRO_PDF_METADATA_SUBJECT = cairo_pdf_metadata_t.SUBJECT;
enum CAIRO_PDF_METADATA_KEYWORDS = cairo_pdf_metadata_t.KEYWORDS;
enum CAIRO_PDF_METADATA_CREATOR = cairo_pdf_metadata_t.CREATOR;
enum CAIRO_PDF_METADATA_CREATE_DATE = cairo_pdf_metadata_t.CREATE_DATE;
enum CAIRO_PDF_METADATA_MOD_DATE = cairo_pdf_metadata_t.MOD_DATE;

// ---- cairo-ps.h

enum cairo_ps_level_t
{
    LEVEL_2,
    LEVEL_3,
}
alias CairoPsLevel = cairo_ps_level_t;
enum CAIRO_PS_LEVEL_2 = cairo_ps_level_t.LEVEL_2;
enum CAIRO_PS_LEVEL_3 = cairo_ps_level_t.LEVEL_3;

// ---- cairo-svg.h

enum cairo_svg_version_t
{
    VERSION_1_1,
    VERSION_1_2,
}
alias CairoSvgVersion = cairo_svg_version_t;
enum CAIRO_SVG_VERSION_1_1 = cairo_svg_version_t.VERSION_1_1;
enum CAIRO_SVG_VERSION_1_2 = cairo_svg_version_t.VERSION_1_2;

enum cairo_svg_unit_t
{
    USER = 0,
    EM,
    EX,
    PX,
    IN,
    CM,
    MM,
    PT,
    PC,
    PERCENT,
}
alias CairoSvgUnit = cairo_svg_unit_t;
enum CAIRO_SVG_UNIT_USER = cairo_svg_unit_t.USER;
enum CAIRO_SVG_UNIT_EM = cairo_svg_unit_t.EM;
enum CAIRO_SVG_UNIT_EX = cairo_svg_unit_t.EX;
enum CAIRO_SVG_UNIT_PX = cairo_svg_unit_t.PX;
enum CAIRO_SVG_UNIT_IN = cairo_svg_unit_t.IN;
enum CAIRO_SVG_UNIT_CM = cairo_svg_unit_t.CM;
enum CAIRO_SVG_UNIT_MM = cairo_svg_unit_t.MM;
enum CAIRO_SVG_UNIT_PT = cairo_svg_unit_t.PT;
enum CAIRO_SVG_UNIT_PC = cairo_svg_unit_t.PC;
enum CAIRO_SVG_UNIT_PERCENT = cairo_svg_unit_t.PERCENT;

// ---- cairo-script.h

enum cairo_script_mode_t
{
    ASCII,
    BINARY,
}
alias CairoScriptMode = cairo_script_mode_t;
enum CAIRO_SCRIPT_MODE_ASCII = cairo_script_mode_t.ASCII;
enum CAIRO_SCRIPT_MODE_BINARY = cairo_script_mode_t.BINARY;

// ---- cairo-tee.h

extern (C) nothrow @nogc
{
    // ---- cairo.h

    int cairo_version();
    const(char)* cairo_version_string();
    void cairo_pattern_set_dither(cairo_pattern_t* pattern, cairo_dither_t dither);
    cairo_dither_t cairo_pattern_get_dither(cairo_pattern_t* pattern);
    cairo_t* cairo_create(cairo_surface_t* target);
    cairo_t* cairo_reference(cairo_t* cr);
    void cairo_destroy(cairo_t* cr);
    uint cairo_get_reference_count(cairo_t* cr);
    void* cairo_get_user_data(cairo_t* cr, const(cairo_user_data_key_t)* key);
    cairo_status_t cairo_set_user_data(cairo_t* cr, const(cairo_user_data_key_t)* key, void* user_data, cairo_destroy_func_t destroy);
    void cairo_save(cairo_t* cr);
    void cairo_restore(cairo_t* cr);
    void cairo_push_group(cairo_t* cr);
    void cairo_push_group_with_content(cairo_t* cr, cairo_content_t content);
    cairo_pattern_t* cairo_pop_group(cairo_t* cr);
    void cairo_pop_group_to_source(cairo_t* cr);
    void cairo_set_operator(cairo_t* cr, cairo_operator_t op);
    void cairo_set_source(cairo_t* cr, cairo_pattern_t* source);
    void cairo_set_source_rgb(cairo_t* cr, double red, double green, double blue);
    void cairo_set_source_rgba(cairo_t* cr, double red, double green, double blue, double alpha);
    void cairo_set_source_surface(cairo_t* cr, cairo_surface_t* surface, double x, double y);
    void cairo_set_tolerance(cairo_t* cr, double tolerance);
    void cairo_set_antialias(cairo_t* cr, cairo_antialias_t antialias);
    void cairo_set_fill_rule(cairo_t* cr, cairo_fill_rule_t fill_rule);
    void cairo_set_line_width(cairo_t* cr, double width);
    void cairo_set_hairline(cairo_t* cr, cairo_bool_t set_hairline);
    void cairo_set_line_cap(cairo_t* cr, cairo_line_cap_t line_cap);
    void cairo_set_line_join(cairo_t* cr, cairo_line_join_t line_join);
    void cairo_set_dash(cairo_t* cr, const(double)* dashes, int num_dashes, double offset);
    void cairo_set_miter_limit(cairo_t* cr, double limit);
    void cairo_translate(cairo_t* cr, double tx, double ty);
    void cairo_scale(cairo_t* cr, double sx, double sy);
    void cairo_rotate(cairo_t* cr, double angle);
    void cairo_transform(cairo_t* cr, const(cairo_matrix_t)* matrix);
    void cairo_set_matrix(cairo_t* cr, const(cairo_matrix_t)* matrix);
    void cairo_identity_matrix(cairo_t* cr);
    void cairo_user_to_device(cairo_t* cr, double* x, double* y);
    void cairo_user_to_device_distance(cairo_t* cr, double* dx, double* dy);
    void cairo_device_to_user(cairo_t* cr, double* x, double* y);
    void cairo_device_to_user_distance(cairo_t* cr, double* dx, double* dy);
    void cairo_new_path(cairo_t* cr);
    void cairo_move_to(cairo_t* cr, double x, double y);
    void cairo_new_sub_path(cairo_t* cr);
    void cairo_line_to(cairo_t* cr, double x, double y);
    void cairo_curve_to(cairo_t* cr, double x1, double y1, double x2, double y2, double x3, double y3);
    void cairo_arc(cairo_t* cr, double xc, double yc, double radius, double angle1, double angle2);
    void cairo_arc_negative(cairo_t* cr, double xc, double yc, double radius, double angle1, double angle2);
    void cairo_rel_move_to(cairo_t* cr, double dx, double dy);
    void cairo_rel_line_to(cairo_t* cr, double dx, double dy);
    void cairo_rel_curve_to(cairo_t* cr, double dx1, double dy1, double dx2, double dy2, double dx3, double dy3);
    void cairo_rectangle(cairo_t* cr, double x, double y, double width, double height);
    void cairo_close_path(cairo_t* cr);
    void cairo_path_extents(cairo_t* cr, double* x1, double* y1, double* x2, double* y2);
    void cairo_paint(cairo_t* cr);
    void cairo_paint_with_alpha(cairo_t* cr, double alpha);
    void cairo_mask(cairo_t* cr, cairo_pattern_t* pattern);
    void cairo_mask_surface(cairo_t* cr, cairo_surface_t* surface, double surface_x, double surface_y);
    void cairo_stroke(cairo_t* cr);
    void cairo_stroke_preserve(cairo_t* cr);
    void cairo_fill(cairo_t* cr);
    void cairo_fill_preserve(cairo_t* cr);
    void cairo_copy_page(cairo_t* cr);
    void cairo_show_page(cairo_t* cr);
    cairo_bool_t cairo_in_stroke(cairo_t* cr, double x, double y);
    cairo_bool_t cairo_in_fill(cairo_t* cr, double x, double y);
    cairo_bool_t cairo_in_clip(cairo_t* cr, double x, double y);
    void cairo_stroke_extents(cairo_t* cr, double* x1, double* y1, double* x2, double* y2);
    void cairo_fill_extents(cairo_t* cr, double* x1, double* y1, double* x2, double* y2);
    void cairo_reset_clip(cairo_t* cr);
    void cairo_clip(cairo_t* cr);
    void cairo_clip_preserve(cairo_t* cr);
    void cairo_clip_extents(cairo_t* cr, double* x1, double* y1, double* x2, double* y2);
    cairo_rectangle_list_t* cairo_copy_clip_rectangle_list(cairo_t* cr);
    void cairo_rectangle_list_destroy(cairo_rectangle_list_t* rectangle_list);
    void cairo_tag_begin(cairo_t* cr, const(char)* tag_name, const(char)* attributes);
    void cairo_tag_end(cairo_t* cr, const(char)* tag_name);
    cairo_glyph_t* cairo_glyph_allocate(int num_glyphs);
    void cairo_glyph_free(cairo_glyph_t* glyphs);
    cairo_text_cluster_t* cairo_text_cluster_allocate(int num_clusters);
    void cairo_text_cluster_free(cairo_text_cluster_t* clusters);
    cairo_font_options_t* cairo_font_options_create();
    cairo_font_options_t* cairo_font_options_copy(const(cairo_font_options_t)* original);
    void cairo_font_options_destroy(cairo_font_options_t* options);
    cairo_status_t cairo_font_options_status(cairo_font_options_t* options);
    void cairo_font_options_merge(cairo_font_options_t* options, const(cairo_font_options_t)* other);
    cairo_bool_t cairo_font_options_equal(const(cairo_font_options_t)* options, const(cairo_font_options_t)* other);
    c_ulong cairo_font_options_hash(const(cairo_font_options_t)* options);
    void cairo_font_options_set_antialias(cairo_font_options_t* options, cairo_antialias_t antialias);
    cairo_antialias_t cairo_font_options_get_antialias(const(cairo_font_options_t)* options);
    void cairo_font_options_set_subpixel_order(cairo_font_options_t* options, cairo_subpixel_order_t subpixel_order);
    cairo_subpixel_order_t cairo_font_options_get_subpixel_order(const(cairo_font_options_t)* options);
    void cairo_font_options_set_hint_style(cairo_font_options_t* options, cairo_hint_style_t hint_style);
    cairo_hint_style_t cairo_font_options_get_hint_style(const(cairo_font_options_t)* options);
    void cairo_font_options_set_hint_metrics(cairo_font_options_t* options, cairo_hint_metrics_t hint_metrics);
    cairo_hint_metrics_t cairo_font_options_get_hint_metrics(const(cairo_font_options_t)* options);
    const(char)* cairo_font_options_get_variations(cairo_font_options_t* options);
    void cairo_font_options_set_variations(cairo_font_options_t* options, const(char)* variations);
    void cairo_font_options_set_color_mode(cairo_font_options_t* options, cairo_color_mode_t color_mode);
    cairo_color_mode_t cairo_font_options_get_color_mode(const(cairo_font_options_t)* options);
    uint cairo_font_options_get_color_palette(const(cairo_font_options_t)* options);
    void cairo_font_options_set_color_palette(cairo_font_options_t* options, uint palette_index);
    void cairo_font_options_set_custom_palette_color(cairo_font_options_t* options, uint index, double red, double green, double blue, double alpha);
    cairo_status_t cairo_font_options_get_custom_palette_color(cairo_font_options_t* options, uint index, double* red, double* green, double* blue, double* alpha);
    void cairo_select_font_face(cairo_t* cr, const(char)* family, cairo_font_slant_t slant, cairo_font_weight_t weight);
    void cairo_set_font_size(cairo_t* cr, double size);
    void cairo_set_font_matrix(cairo_t* cr, const(cairo_matrix_t)* matrix);
    void cairo_get_font_matrix(cairo_t* cr, cairo_matrix_t* matrix);
    void cairo_set_font_options(cairo_t* cr, const(cairo_font_options_t)* options);
    void cairo_get_font_options(cairo_t* cr, cairo_font_options_t* options);
    void cairo_set_font_face(cairo_t* cr, cairo_font_face_t* font_face);
    cairo_font_face_t* cairo_get_font_face(cairo_t* cr);
    void cairo_set_scaled_font(cairo_t* cr, const(cairo_scaled_font_t)* scaled_font);
    cairo_scaled_font_t* cairo_get_scaled_font(cairo_t* cr);
    void cairo_show_text(cairo_t* cr, const(char)* utf8);
    void cairo_show_glyphs(cairo_t* cr, const(cairo_glyph_t)* glyphs, int num_glyphs);
    void cairo_show_text_glyphs(cairo_t* cr, const(char)* utf8, int utf8_len, const(cairo_glyph_t)* glyphs, int num_glyphs, const(cairo_text_cluster_t)* clusters, int num_clusters, cairo_text_cluster_flags_t cluster_flags);
    void cairo_text_path(cairo_t* cr, const(char)* utf8);
    void cairo_glyph_path(cairo_t* cr, const(cairo_glyph_t)* glyphs, int num_glyphs);
    void cairo_text_extents(cairo_t* cr, const(char)* utf8, cairo_text_extents_t* extents);
    void cairo_glyph_extents(cairo_t* cr, const(cairo_glyph_t)* glyphs, int num_glyphs, cairo_text_extents_t* extents);
    void cairo_font_extents(cairo_t* cr, cairo_font_extents_t* extents);
    cairo_font_face_t* cairo_font_face_reference(cairo_font_face_t* font_face);
    void cairo_font_face_destroy(cairo_font_face_t* font_face);
    uint cairo_font_face_get_reference_count(cairo_font_face_t* font_face);
    cairo_status_t cairo_font_face_status(cairo_font_face_t* font_face);
    cairo_font_type_t cairo_font_face_get_type(cairo_font_face_t* font_face);
    void* cairo_font_face_get_user_data(cairo_font_face_t* font_face, const(cairo_user_data_key_t)* key);
    cairo_status_t cairo_font_face_set_user_data(cairo_font_face_t* font_face, const(cairo_user_data_key_t)* key, void* user_data, cairo_destroy_func_t destroy);
    cairo_scaled_font_t* cairo_scaled_font_create(cairo_font_face_t* font_face, const(cairo_matrix_t)* font_matrix, const(cairo_matrix_t)* ctm, const(cairo_font_options_t)* options);
    cairo_scaled_font_t* cairo_scaled_font_reference(cairo_scaled_font_t* scaled_font);
    void cairo_scaled_font_destroy(cairo_scaled_font_t* scaled_font);
    uint cairo_scaled_font_get_reference_count(cairo_scaled_font_t* scaled_font);
    cairo_status_t cairo_scaled_font_status(cairo_scaled_font_t* scaled_font);
    cairo_font_type_t cairo_scaled_font_get_type(cairo_scaled_font_t* scaled_font);
    void* cairo_scaled_font_get_user_data(cairo_scaled_font_t* scaled_font, const(cairo_user_data_key_t)* key);
    cairo_status_t cairo_scaled_font_set_user_data(cairo_scaled_font_t* scaled_font, const(cairo_user_data_key_t)* key, void* user_data, cairo_destroy_func_t destroy);
    void cairo_scaled_font_extents(cairo_scaled_font_t* scaled_font, cairo_font_extents_t* extents);
    void cairo_scaled_font_text_extents(cairo_scaled_font_t* scaled_font, const(char)* utf8, cairo_text_extents_t* extents);
    void cairo_scaled_font_glyph_extents(cairo_scaled_font_t* scaled_font, const(cairo_glyph_t)* glyphs, int num_glyphs, cairo_text_extents_t* extents);
    cairo_status_t cairo_scaled_font_text_to_glyphs(cairo_scaled_font_t* scaled_font, double x, double y, const(char)* utf8, int utf8_len, cairo_glyph_t** glyphs, int* num_glyphs, cairo_text_cluster_t** clusters, int* num_clusters, cairo_text_cluster_flags_t* cluster_flags);
    cairo_font_face_t* cairo_scaled_font_get_font_face(cairo_scaled_font_t* scaled_font);
    void cairo_scaled_font_get_font_matrix(cairo_scaled_font_t* scaled_font, cairo_matrix_t* font_matrix);
    void cairo_scaled_font_get_ctm(cairo_scaled_font_t* scaled_font, cairo_matrix_t* ctm);
    void cairo_scaled_font_get_scale_matrix(cairo_scaled_font_t* scaled_font, cairo_matrix_t* scale_matrix);
    void cairo_scaled_font_get_font_options(cairo_scaled_font_t* scaled_font, cairo_font_options_t* options);
    cairo_font_face_t* cairo_toy_font_face_create(const(char)* family, cairo_font_slant_t slant, cairo_font_weight_t weight);
    const(char)* cairo_toy_font_face_get_family(cairo_font_face_t* font_face);
    cairo_font_slant_t cairo_toy_font_face_get_slant(cairo_font_face_t* font_face);
    cairo_font_weight_t cairo_toy_font_face_get_weight(cairo_font_face_t* font_face);
    cairo_font_face_t* cairo_user_font_face_create();
    void cairo_user_font_face_set_init_func(cairo_font_face_t* font_face, cairo_user_scaled_font_init_func_t init_func);
    void cairo_user_font_face_set_render_glyph_func(cairo_font_face_t* font_face, cairo_user_scaled_font_render_glyph_func_t render_glyph_func);
    void cairo_user_font_face_set_render_color_glyph_func(cairo_font_face_t* font_face, cairo_user_scaled_font_render_glyph_func_t render_glyph_func);
    void cairo_user_font_face_set_text_to_glyphs_func(cairo_font_face_t* font_face, cairo_user_scaled_font_text_to_glyphs_func_t text_to_glyphs_func);
    void cairo_user_font_face_set_unicode_to_glyph_func(cairo_font_face_t* font_face, cairo_user_scaled_font_unicode_to_glyph_func_t unicode_to_glyph_func);
    cairo_user_scaled_font_init_func_t cairo_user_font_face_get_init_func(cairo_font_face_t* font_face);
    cairo_user_scaled_font_render_glyph_func_t cairo_user_font_face_get_render_glyph_func(cairo_font_face_t* font_face);
    cairo_user_scaled_font_render_glyph_func_t cairo_user_font_face_get_render_color_glyph_func(cairo_font_face_t* font_face);
    cairo_user_scaled_font_text_to_glyphs_func_t cairo_user_font_face_get_text_to_glyphs_func(cairo_font_face_t* font_face);
    cairo_user_scaled_font_unicode_to_glyph_func_t cairo_user_font_face_get_unicode_to_glyph_func(cairo_font_face_t* font_face);
    cairo_pattern_t* cairo_user_scaled_font_get_foreground_marker(cairo_scaled_font_t* scaled_font);
    cairo_pattern_t* cairo_user_scaled_font_get_foreground_source(cairo_scaled_font_t* scaled_font);
    cairo_operator_t cairo_get_operator(cairo_t* cr);
    cairo_pattern_t* cairo_get_source(cairo_t* cr);
    double cairo_get_tolerance(cairo_t* cr);
    cairo_antialias_t cairo_get_antialias(cairo_t* cr);
    cairo_bool_t cairo_has_current_point(cairo_t* cr);
    void cairo_get_current_point(cairo_t* cr, double* x, double* y);
    cairo_fill_rule_t cairo_get_fill_rule(cairo_t* cr);
    double cairo_get_line_width(cairo_t* cr);
    cairo_bool_t cairo_get_hairline(cairo_t* cr);
    cairo_line_cap_t cairo_get_line_cap(cairo_t* cr);
    cairo_line_join_t cairo_get_line_join(cairo_t* cr);
    double cairo_get_miter_limit(cairo_t* cr);
    int cairo_get_dash_count(cairo_t* cr);
    void cairo_get_dash(cairo_t* cr, double* dashes, double* offset);
    void cairo_get_matrix(cairo_t* cr, cairo_matrix_t* matrix);
    cairo_surface_t* cairo_get_target(cairo_t* cr);
    cairo_surface_t* cairo_get_group_target(cairo_t* cr);
    cairo_path_t* cairo_copy_path(cairo_t* cr);
    cairo_path_t* cairo_copy_path_flat(cairo_t* cr);
    void cairo_append_path(cairo_t* cr, const(cairo_path_t)* path);
    void cairo_path_destroy(cairo_path_t* path);
    cairo_status_t cairo_status(cairo_t* cr);
    const(char)* cairo_status_to_string(cairo_status_t status);
    cairo_device_t* cairo_device_reference(cairo_device_t* device);
    cairo_device_type_t cairo_device_get_type(cairo_device_t* device);
    cairo_status_t cairo_device_status(cairo_device_t* device);
    cairo_status_t cairo_device_acquire(cairo_device_t* device);
    void cairo_device_release(cairo_device_t* device);
    void cairo_device_flush(cairo_device_t* device);
    void cairo_device_finish(cairo_device_t* device);
    void cairo_device_destroy(cairo_device_t* device);
    uint cairo_device_get_reference_count(cairo_device_t* device);
    void* cairo_device_get_user_data(cairo_device_t* device, const(cairo_user_data_key_t)* key);
    cairo_status_t cairo_device_set_user_data(cairo_device_t* device, const(cairo_user_data_key_t)* key, void* user_data, cairo_destroy_func_t destroy);
    cairo_surface_t* cairo_surface_create_similar(cairo_surface_t* other, cairo_content_t content, int width, int height);
    cairo_surface_t* cairo_surface_create_similar_image(cairo_surface_t* other, cairo_format_t format, int width, int height);
    cairo_surface_t* cairo_surface_map_to_image(cairo_surface_t* surface, const(cairo_rectangle_int_t)* extents);
    void cairo_surface_unmap_image(cairo_surface_t* surface, cairo_surface_t* image);
    cairo_surface_t* cairo_surface_create_for_rectangle(cairo_surface_t* target, double x, double y, double width, double height);
    cairo_surface_t* cairo_surface_create_observer(cairo_surface_t* target, cairo_surface_observer_mode_t mode);
    cairo_status_t cairo_surface_observer_add_paint_callback(cairo_surface_t* abstract_surface, cairo_surface_observer_callback_t func, void* data);
    cairo_status_t cairo_surface_observer_add_mask_callback(cairo_surface_t* abstract_surface, cairo_surface_observer_callback_t func, void* data);
    cairo_status_t cairo_surface_observer_add_fill_callback(cairo_surface_t* abstract_surface, cairo_surface_observer_callback_t func, void* data);
    cairo_status_t cairo_surface_observer_add_stroke_callback(cairo_surface_t* abstract_surface, cairo_surface_observer_callback_t func, void* data);
    cairo_status_t cairo_surface_observer_add_glyphs_callback(cairo_surface_t* abstract_surface, cairo_surface_observer_callback_t func, void* data);
    cairo_status_t cairo_surface_observer_add_flush_callback(cairo_surface_t* abstract_surface, cairo_surface_observer_callback_t func, void* data);
    cairo_status_t cairo_surface_observer_add_finish_callback(cairo_surface_t* abstract_surface, cairo_surface_observer_callback_t func, void* data);
    cairo_status_t cairo_surface_observer_print(cairo_surface_t* abstract_surface, cairo_write_func_t write_func, void* closure);
    double cairo_surface_observer_elapsed(cairo_surface_t* abstract_surface);
    cairo_status_t cairo_device_observer_print(cairo_device_t* abstract_device, cairo_write_func_t write_func, void* closure);
    double cairo_device_observer_elapsed(cairo_device_t* abstract_device);
    double cairo_device_observer_paint_elapsed(cairo_device_t* abstract_device);
    double cairo_device_observer_mask_elapsed(cairo_device_t* abstract_device);
    double cairo_device_observer_fill_elapsed(cairo_device_t* abstract_device);
    double cairo_device_observer_stroke_elapsed(cairo_device_t* abstract_device);
    double cairo_device_observer_glyphs_elapsed(cairo_device_t* abstract_device);
    cairo_surface_t* cairo_surface_reference(cairo_surface_t* surface);
    void cairo_surface_finish(cairo_surface_t* surface);
    void cairo_surface_destroy(cairo_surface_t* surface);
    cairo_device_t* cairo_surface_get_device(cairo_surface_t* surface);
    uint cairo_surface_get_reference_count(cairo_surface_t* surface);
    cairo_status_t cairo_surface_status(cairo_surface_t* surface);
    cairo_surface_type_t cairo_surface_get_type(cairo_surface_t* surface);
    cairo_content_t cairo_surface_get_content(cairo_surface_t* surface);
    cairo_status_t cairo_surface_write_to_png(cairo_surface_t* surface, const(char)* filename);
    cairo_status_t cairo_surface_write_to_png_stream(cairo_surface_t* surface, cairo_write_func_t write_func, void* closure);
    void* cairo_surface_get_user_data(cairo_surface_t* surface, const(cairo_user_data_key_t)* key);
    cairo_status_t cairo_surface_set_user_data(cairo_surface_t* surface, const(cairo_user_data_key_t)* key, void* user_data, cairo_destroy_func_t destroy);
    void cairo_surface_get_mime_data(cairo_surface_t* surface, const(char)* mime_type, const(ubyte)** data, c_ulong* length_);
    cairo_status_t cairo_surface_set_mime_data(cairo_surface_t* surface, const(char)* mime_type, const(ubyte)* data, c_ulong length_, cairo_destroy_func_t destroy, void* closure);
    cairo_bool_t cairo_surface_supports_mime_type(cairo_surface_t* surface, const(char)* mime_type);
    void cairo_surface_get_font_options(cairo_surface_t* surface, cairo_font_options_t* options);
    void cairo_surface_flush(cairo_surface_t* surface);
    void cairo_surface_mark_dirty(cairo_surface_t* surface);
    void cairo_surface_mark_dirty_rectangle(cairo_surface_t* surface, int x, int y, int width, int height);
    void cairo_surface_set_device_scale(cairo_surface_t* surface, double x_scale, double y_scale);
    void cairo_surface_get_device_scale(cairo_surface_t* surface, double* x_scale, double* y_scale);
    void cairo_surface_set_device_offset(cairo_surface_t* surface, double x_offset, double y_offset);
    void cairo_surface_get_device_offset(cairo_surface_t* surface, double* x_offset, double* y_offset);
    void cairo_surface_set_fallback_resolution(cairo_surface_t* surface, double x_pixels_per_inch, double y_pixels_per_inch);
    void cairo_surface_get_fallback_resolution(cairo_surface_t* surface, double* x_pixels_per_inch, double* y_pixels_per_inch);
    void cairo_surface_copy_page(cairo_surface_t* surface);
    void cairo_surface_show_page(cairo_surface_t* surface);
    cairo_bool_t cairo_surface_has_show_text_glyphs(cairo_surface_t* surface);
    cairo_surface_t* cairo_image_surface_create(cairo_format_t format, int width, int height);
    int cairo_format_stride_for_width(cairo_format_t format, int width);
    cairo_surface_t* cairo_image_surface_create_for_data(ubyte* data, cairo_format_t format, int width, int height, int stride);
    ubyte* cairo_image_surface_get_data(cairo_surface_t* surface);
    cairo_format_t cairo_image_surface_get_format(cairo_surface_t* surface);
    int cairo_image_surface_get_width(cairo_surface_t* surface);
    int cairo_image_surface_get_height(cairo_surface_t* surface);
    int cairo_image_surface_get_stride(cairo_surface_t* surface);
    cairo_surface_t* cairo_image_surface_create_from_png(const(char)* filename);
    cairo_surface_t* cairo_image_surface_create_from_png_stream(cairo_read_func_t read_func, void* closure);
    cairo_surface_t* cairo_recording_surface_create(cairo_content_t content, const(cairo_rectangle_t)* extents);
    void cairo_recording_surface_ink_extents(cairo_surface_t* surface, double* x0, double* y0, double* width, double* height);
    cairo_bool_t cairo_recording_surface_get_extents(cairo_surface_t* surface, cairo_rectangle_t* extents);
    cairo_pattern_t* cairo_pattern_create_raster_source(void* user_data, cairo_content_t content, int width, int height);
    void cairo_raster_source_pattern_set_callback_data(cairo_pattern_t* pattern, void* data);
    void* cairo_raster_source_pattern_get_callback_data(cairo_pattern_t* pattern);
    void cairo_raster_source_pattern_set_acquire(cairo_pattern_t* pattern, cairo_raster_source_acquire_func_t acquire, cairo_raster_source_release_func_t release);
    void cairo_raster_source_pattern_get_acquire(cairo_pattern_t* pattern, cairo_raster_source_acquire_func_t* acquire, cairo_raster_source_release_func_t* release);
    void cairo_raster_source_pattern_set_snapshot(cairo_pattern_t* pattern, cairo_raster_source_snapshot_func_t snapshot);
    cairo_raster_source_snapshot_func_t cairo_raster_source_pattern_get_snapshot(cairo_pattern_t* pattern);
    void cairo_raster_source_pattern_set_copy(cairo_pattern_t* pattern, cairo_raster_source_copy_func_t copy);
    cairo_raster_source_copy_func_t cairo_raster_source_pattern_get_copy(cairo_pattern_t* pattern);
    void cairo_raster_source_pattern_set_finish(cairo_pattern_t* pattern, cairo_raster_source_finish_func_t finish);
    cairo_raster_source_finish_func_t cairo_raster_source_pattern_get_finish(cairo_pattern_t* pattern);
    cairo_pattern_t* cairo_pattern_create_rgb(double red, double green, double blue);
    cairo_pattern_t* cairo_pattern_create_rgba(double red, double green, double blue, double alpha);
    cairo_pattern_t* cairo_pattern_create_for_surface(cairo_surface_t* surface);
    cairo_pattern_t* cairo_pattern_create_linear(double x0, double y0, double x1, double y1);
    cairo_pattern_t* cairo_pattern_create_radial(double cx0, double cy0, double radius0, double cx1, double cy1, double radius1);
    cairo_pattern_t* cairo_pattern_create_mesh();
    cairo_pattern_t* cairo_pattern_reference(cairo_pattern_t* pattern);
    void cairo_pattern_destroy(cairo_pattern_t* pattern);
    uint cairo_pattern_get_reference_count(cairo_pattern_t* pattern);
    cairo_status_t cairo_pattern_status(cairo_pattern_t* pattern);
    void* cairo_pattern_get_user_data(cairo_pattern_t* pattern, const(cairo_user_data_key_t)* key);
    cairo_status_t cairo_pattern_set_user_data(cairo_pattern_t* pattern, const(cairo_user_data_key_t)* key, void* user_data, cairo_destroy_func_t destroy);
    cairo_pattern_type_t cairo_pattern_get_type(cairo_pattern_t* pattern);
    void cairo_pattern_add_color_stop_rgb(cairo_pattern_t* pattern, double offset, double red, double green, double blue);
    void cairo_pattern_add_color_stop_rgba(cairo_pattern_t* pattern, double offset, double red, double green, double blue, double alpha);
    void cairo_mesh_pattern_begin_patch(cairo_pattern_t* pattern);
    void cairo_mesh_pattern_end_patch(cairo_pattern_t* pattern);
    void cairo_mesh_pattern_curve_to(cairo_pattern_t* pattern, double x1, double y1, double x2, double y2, double x3, double y3);
    void cairo_mesh_pattern_line_to(cairo_pattern_t* pattern, double x, double y);
    void cairo_mesh_pattern_move_to(cairo_pattern_t* pattern, double x, double y);
    void cairo_mesh_pattern_set_control_point(cairo_pattern_t* pattern, uint point_num, double x, double y);
    void cairo_mesh_pattern_set_corner_color_rgb(cairo_pattern_t* pattern, uint corner_num, double red, double green, double blue);
    void cairo_mesh_pattern_set_corner_color_rgba(cairo_pattern_t* pattern, uint corner_num, double red, double green, double blue, double alpha);
    void cairo_pattern_set_matrix(cairo_pattern_t* pattern, const(cairo_matrix_t)* matrix);
    void cairo_pattern_get_matrix(cairo_pattern_t* pattern, cairo_matrix_t* matrix);
    void cairo_pattern_set_extend(cairo_pattern_t* pattern, cairo_extend_t extend);
    cairo_extend_t cairo_pattern_get_extend(cairo_pattern_t* pattern);
    void cairo_pattern_set_filter(cairo_pattern_t* pattern, cairo_filter_t filter);
    cairo_filter_t cairo_pattern_get_filter(cairo_pattern_t* pattern);
    cairo_status_t cairo_pattern_get_rgba(cairo_pattern_t* pattern, double* red, double* green, double* blue, double* alpha);
    cairo_status_t cairo_pattern_get_surface(cairo_pattern_t* pattern, cairo_surface_t** surface);
    cairo_status_t cairo_pattern_get_color_stop_rgba(cairo_pattern_t* pattern, int index, double* offset, double* red, double* green, double* blue, double* alpha);
    cairo_status_t cairo_pattern_get_color_stop_count(cairo_pattern_t* pattern, int* count);
    cairo_status_t cairo_pattern_get_linear_points(cairo_pattern_t* pattern, double* x0, double* y0, double* x1, double* y1);
    cairo_status_t cairo_pattern_get_radial_circles(cairo_pattern_t* pattern, double* x0, double* y0, double* r0, double* x1, double* y1, double* r1);
    cairo_status_t cairo_mesh_pattern_get_patch_count(cairo_pattern_t* pattern, uint* count);
    cairo_path_t* cairo_mesh_pattern_get_path(cairo_pattern_t* pattern, uint patch_num);
    cairo_status_t cairo_mesh_pattern_get_corner_color_rgba(cairo_pattern_t* pattern, uint patch_num, uint corner_num, double* red, double* green, double* blue, double* alpha);
    cairo_status_t cairo_mesh_pattern_get_control_point(cairo_pattern_t* pattern, uint patch_num, uint point_num, double* x, double* y);
    void cairo_matrix_init(cairo_matrix_t* matrix, double xx, double yx, double xy, double yy, double x0, double y0);
    void cairo_matrix_init_identity(cairo_matrix_t* matrix);
    void cairo_matrix_init_translate(cairo_matrix_t* matrix, double tx, double ty);
    void cairo_matrix_init_scale(cairo_matrix_t* matrix, double sx, double sy);
    void cairo_matrix_init_rotate(cairo_matrix_t* matrix, double radians);
    void cairo_matrix_translate(cairo_matrix_t* matrix, double tx, double ty);
    void cairo_matrix_scale(cairo_matrix_t* matrix, double sx, double sy);
    void cairo_matrix_rotate(cairo_matrix_t* matrix, double radians);
    cairo_status_t cairo_matrix_invert(cairo_matrix_t* matrix);
    void cairo_matrix_multiply(cairo_matrix_t* result, const(cairo_matrix_t)* a, const(cairo_matrix_t)* b);
    void cairo_matrix_transform_distance(const(cairo_matrix_t)* matrix, double* dx, double* dy);
    void cairo_matrix_transform_point(const(cairo_matrix_t)* matrix, double* x, double* y);
    cairo_region_t* cairo_region_create();
    cairo_region_t* cairo_region_create_rectangle(const(cairo_rectangle_int_t)* rectangle);
    cairo_region_t* cairo_region_create_rectangles(const(cairo_rectangle_int_t)* rects, int count);
    cairo_region_t* cairo_region_copy(const(cairo_region_t)* original);
    cairo_region_t* cairo_region_reference(cairo_region_t* region);
    void cairo_region_destroy(cairo_region_t* region);
    cairo_bool_t cairo_region_equal(const(cairo_region_t)* a, const(cairo_region_t)* b);
    cairo_status_t cairo_region_status(const(cairo_region_t)* region);
    void cairo_region_get_extents(const(cairo_region_t)* region, cairo_rectangle_int_t* extents);
    int cairo_region_num_rectangles(const(cairo_region_t)* region);
    void cairo_region_get_rectangle(const(cairo_region_t)* region, int nth, cairo_rectangle_int_t* rectangle);
    cairo_bool_t cairo_region_is_empty(const(cairo_region_t)* region);
    cairo_region_overlap_t cairo_region_contains_rectangle(const(cairo_region_t)* region, const(cairo_rectangle_int_t)* rectangle);
    cairo_bool_t cairo_region_contains_point(const(cairo_region_t)* region, int x, int y);
    void cairo_region_translate(cairo_region_t* region, int dx, int dy);
    cairo_status_t cairo_region_subtract(cairo_region_t* dst, const(cairo_region_t)* other);
    cairo_status_t cairo_region_subtract_rectangle(cairo_region_t* dst, const(cairo_rectangle_int_t)* rectangle);
    cairo_status_t cairo_region_intersect(cairo_region_t* dst, const(cairo_region_t)* other);
    cairo_status_t cairo_region_intersect_rectangle(cairo_region_t* dst, const(cairo_rectangle_int_t)* rectangle);
    cairo_status_t cairo_region_union(cairo_region_t* dst, const(cairo_region_t)* other);
    cairo_status_t cairo_region_union_rectangle(cairo_region_t* dst, const(cairo_rectangle_int_t)* rectangle);
    cairo_status_t cairo_region_xor(cairo_region_t* dst, const(cairo_region_t)* other);
    cairo_status_t cairo_region_xor_rectangle(cairo_region_t* dst, const(cairo_rectangle_int_t)* rectangle);
    void cairo_debug_reset_static_data();

    // ---- cairo-pdf.h

    cairo_surface_t* cairo_pdf_surface_create(const(char)* filename, double width_in_points, double height_in_points);
    cairo_surface_t* cairo_pdf_surface_create_for_stream(cairo_write_func_t write_func, void* closure, double width_in_points, double height_in_points);
    void cairo_pdf_surface_restrict_to_version(cairo_surface_t* surface, cairo_pdf_version_t version_);
    void cairo_pdf_get_versions(const(cairo_pdf_version_t)** versions, int* num_versions);
    const(char)* cairo_pdf_version_to_string(cairo_pdf_version_t version_);
    void cairo_pdf_surface_set_size(cairo_surface_t* surface, double width_in_points, double height_in_points);
    int cairo_pdf_surface_add_outline(cairo_surface_t* surface, int parent_id, const(char)* utf8, const(char)* link_attribs, cairo_pdf_outline_flags_t flags);
    void cairo_pdf_surface_set_metadata(cairo_surface_t* surface, cairo_pdf_metadata_t metadata, const(char)* utf8);
    void cairo_pdf_surface_set_custom_metadata(cairo_surface_t* surface, const(char)* name, const(char)* value);
    void cairo_pdf_surface_set_page_label(cairo_surface_t* surface, const(char)* utf8);
    void cairo_pdf_surface_set_thumbnail_size(cairo_surface_t* surface, int width, int height);

    // ---- cairo-ps.h

    cairo_surface_t* cairo_ps_surface_create(const(char)* filename, double width_in_points, double height_in_points);
    cairo_surface_t* cairo_ps_surface_create_for_stream(cairo_write_func_t write_func, void* closure, double width_in_points, double height_in_points);
    void cairo_ps_surface_restrict_to_level(cairo_surface_t* surface, cairo_ps_level_t level);
    void cairo_ps_get_levels(const(cairo_ps_level_t)** levels, int* num_levels);
    const(char)* cairo_ps_level_to_string(cairo_ps_level_t level);
    void cairo_ps_surface_set_eps(cairo_surface_t* surface, cairo_bool_t eps);
    cairo_bool_t cairo_ps_surface_get_eps(cairo_surface_t* surface);
    void cairo_ps_surface_set_size(cairo_surface_t* surface, double width_in_points, double height_in_points);
    void cairo_ps_surface_dsc_comment(cairo_surface_t* surface, const(char)* comment);
    void cairo_ps_surface_dsc_begin_setup(cairo_surface_t* surface);
    void cairo_ps_surface_dsc_begin_page_setup(cairo_surface_t* surface);

    // ---- cairo-svg.h

    cairo_surface_t* cairo_svg_surface_create(const(char)* filename, double width_in_points, double height_in_points);
    cairo_surface_t* cairo_svg_surface_create_for_stream(cairo_write_func_t write_func, void* closure, double width_in_points, double height_in_points);
    void cairo_svg_surface_restrict_to_version(cairo_surface_t* surface, cairo_svg_version_t version_);
    void cairo_svg_get_versions(const(cairo_svg_version_t)** versions, int* num_versions);
    const(char)* cairo_svg_version_to_string(cairo_svg_version_t version_);
    void cairo_svg_surface_set_document_unit(cairo_surface_t* surface, cairo_svg_unit_t unit);
    cairo_svg_unit_t cairo_svg_surface_get_document_unit(cairo_surface_t* surface);

    // ---- cairo-script.h

    cairo_device_t* cairo_script_create(const(char)* filename);
    cairo_device_t* cairo_script_create_for_stream(cairo_write_func_t write_func, void* closure);
    void cairo_script_write_comment(cairo_device_t* script, const(char)* comment, int len);
    void cairo_script_set_mode(cairo_device_t* script, cairo_script_mode_t mode);
    cairo_script_mode_t cairo_script_get_mode(cairo_device_t* script);
    cairo_surface_t* cairo_script_surface_create(cairo_device_t* script, cairo_content_t content, double width, double height);
    cairo_surface_t* cairo_script_surface_create_for_target(cairo_device_t* script, cairo_surface_t* target);
    cairo_status_t cairo_script_from_recording_surface(cairo_device_t* script, cairo_surface_t* recording_surface);

    // ---- cairo-tee.h

    cairo_surface_t* cairo_tee_surface_create(cairo_surface_t* primary);
    void cairo_tee_surface_add(cairo_surface_t* abstract_surface, cairo_surface_t* target);
    void cairo_tee_surface_remove(cairo_surface_t* abstract_surface, cairo_surface_t* target);
    cairo_surface_t* cairo_tee_surface_index(cairo_surface_t* abstract_surface, uint index);
}

// Headless: an image surface needs no display.
unittest
{
    assert(cairo_version() >= CAIRO_VERSION_ENCODE(1, 18, 0));

    cairo_surface_t* s = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, 4, 4);
    scope (exit) cairo_surface_destroy(s);
    cairo_t* cr = cairo_create(s);
    cairo_set_source_rgb(cr, 1.0, 0.5, 0.0);
    cairo_rectangle(cr, 0, 0, 2, 4);
    cairo_fill(cr);
    assert(cairo_status(cr) == cairo_status_t.SUCCESS);
    cairo_destroy(cr);
    cairo_surface_flush(s);

    // ARGB32 is native-endian 32-bit words: 0xAARRGGBB.
    auto stride = cairo_image_surface_get_stride(s);
    auto row = cast(const(uint)*) cairo_image_surface_get_data(s);
    assert(row[0] == 0xFFFF8000);
    assert(row[3] == 0); // outside the rectangle: untouched, transparent
    assert(stride >= 4 * 4);

    cairo_matrix_t m;
    cairo_matrix_init_scale(&m, 2, 3);
    double x = 1, y = 1;
    cairo_matrix_transform_point(&m, &x, &y);
    assert(x == 2 && y == 3);

    // C field names alias the GtkD-style camelCase ones.
    cairo_text_extents_t e;
    e.x_bearing = 1.5;
    assert(e.xBearing == 1.5);
}
