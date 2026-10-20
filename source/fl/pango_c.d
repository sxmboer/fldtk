/*
 * `extern(C)` bindings for Pango, the text layout and rendering library:
 * the complete public API of `pango.h` (every header it includes,
 * deprecated ones too). Pango's Cairo backend (`pangocairo.h`) is in
 * `fl.pango_c_cairo`. Not a port of an FLTK header -- infrastructure,
 * the same role `fl.cairo_c` plays for Cairo. Not bound: `pangoft2.h`,
 * `pangofc-*.h`, `pangoxft*.h` (the FreeType, fontconfig and Xft
 * backends, which need those libraries' types) and `pango-ot.h`
 * (deprecated, not part of `pango.h`).
 *
 * Transcribed mechanically from the Pango 1.57 headers
 * (`/usr/include/pango-1.0/pango/`), with GtkD's `pango.c.types`/
 * `pango.c.functions` used to cross-check every function's presence and
 * parameter count and every enum's members. Struct sizes, field
 * offsets, bitfield positions and enum values were compared against the
 * C headers with a C compiler, and every declared function against the
 * library's exported symbols. API newer than GtkD's bindings is
 * included. Where the header and GtkD disagree, the header wins (GtkD's
 * `PANGO_SCALE_X_SMALL` is 0.6444; the header's is 0.6944).
 *
 * Names follow GtkD's C layer: Pango's own type names are kept, an enum's
 * members drop the type's prefix (`PangoAlignment.LEFT`), and struct
 * fields are camelCase (`PangoRectangle.x`, `PangoLogAttr.isLineBreak`).
 * Every enum member is also available under its C name
 * (`PANGO_ALIGN_LEFT`) and every camelCase field under its C name
 * (`is_line_break`, an alias). C bitfields are `std.bitmanip.bitfields`
 * properties. Functions Pango marks deprecated are `deprecated` here
 * too, with Pango's replacement hint as the message.
 *
 * Pango's function-like macros are D functions (`PANGO_PIXELS()`,
 * `PANGO_UNITS_ROUND()`, `PANGO_ASCENT()`, ...), and its `PANGO_TYPE_*`
 * macros are functions returning the `GType`. Not ported: the
 * GObject cast/check macros (`PANGO_LAYOUT(obj)`, `PANGO_IS_FONT(obj)`,
 * `PANGO_*_GET_CLASS(obj)`; use a D cast), the per-version availability
 * macros (`PANGO_VERSION_1_44`, `PANGO_AVAILABLE_IN_*`, ...), the module
 * and engine type-definition macros (`PANGO_ENGINE_DEFINE_TYPE`, ...),
 * and the `glib_autoptr` cleanup helpers (use `scope (exit)`). The GLib
 * types Pango uses come from `fl.glib_c`, which this module re-exports.
 *
 * Only compiled into a Pango-enabled build (`version (FLDTK_HAVE_PANGO)`,
 * on by default on Linux, off with dub configuration `linux-no-cairo`; on Windows only with `windows-cairo`).
 */
module fl.pango_c;

version (FLDTK_HAVE_PANGO):

public import fl.glib_c;
import core.stdc.config : c_long, c_ulong;
import core.stdc.stdio : FILE;

/// The Pango version these bindings were transcribed from
/// (`pango-features.h`). `pango_version()` reports the version of the
/// library actually loaded at run time.
enum PANGO_VERSION_MAJOR = 1;
/// ditto
enum PANGO_VERSION_MINOR = 57;
/// ditto
enum PANGO_VERSION_MICRO = 0;
/// ditto
enum PANGO_VERSION_STRING = "1.57.0";

/// `PANGO_VERSION_ENCODE()`.
int PANGO_VERSION_ENCODE(int major, int minor, int micro) pure nothrow @nogc @safe
{
    return major * 10000 + minor * 100 + micro;
}

/// `PANGO_VERSION`: the version these bindings were transcribed from,
/// encoded.
enum PANGO_VERSION = PANGO_VERSION_ENCODE(PANGO_VERSION_MAJOR, PANGO_VERSION_MINOR, PANGO_VERSION_MICRO);

/// `PANGO_VERSION_CHECK()`: whether these bindings are at least this version.
bool PANGO_VERSION_CHECK(int major, int minor, int micro) pure nothrow @nogc @safe
{
    return PANGO_VERSION >= PANGO_VERSION_ENCODE(major, minor, micro);
}

// ---- pango-types.h

/// Pango units per device unit (`PANGO_SCALE`).
enum PANGO_SCALE = 1024;

/// Converts Pango units to device units, rounding to the nearest
/// (`PANGO_PIXELS()`).
int PANGO_PIXELS(double d) pure nothrow @nogc @safe { return (cast(int) d + 512) >> 10; }
/// ditto, rounding down (`PANGO_PIXELS_FLOOR()`).
int PANGO_PIXELS_FLOOR(double d) pure nothrow @nogc @safe { return (cast(int) d) >> 10; }
/// ditto, rounding up (`PANGO_PIXELS_CEIL()`).
int PANGO_PIXELS_CEIL(double d) pure nothrow @nogc @safe { return (cast(int) d + 1023) >> 10; }

/// Rounds a value in Pango units down to a whole device unit
/// (`PANGO_UNITS_FLOOR()`).
int PANGO_UNITS_FLOOR(int d) pure nothrow @nogc @safe { return d & ~(PANGO_SCALE - 1); }
/// ditto, up (`PANGO_UNITS_CEIL()`).
int PANGO_UNITS_CEIL(int d) pure nothrow @nogc @safe { return (d + (PANGO_SCALE - 1)) & ~(PANGO_SCALE - 1); }
/// ditto, to the nearest (`PANGO_UNITS_ROUND()`).
int PANGO_UNITS_ROUND(int d) pure nothrow @nogc @safe { return (d + (PANGO_SCALE >> 1)) & ~(PANGO_SCALE - 1); }

/// Extents of a glyph or line rectangle: ascent (`PANGO_ASCENT()`).
int PANGO_ASCENT(PangoRectangle rect) pure nothrow @nogc @safe { return -rect.y; }
/// ditto: descent (`PANGO_DESCENT()`).
int PANGO_DESCENT(PangoRectangle rect) pure nothrow @nogc @safe { return rect.y + rect.height; }
/// ditto: left bearing (`PANGO_LBEARING()`).
int PANGO_LBEARING(PangoRectangle rect) pure nothrow @nogc @safe { return rect.x; }
/// ditto: right bearing (`PANGO_RBEARING()`).
int PANGO_RBEARING(PangoRectangle rect) pure nothrow @nogc @safe { return rect.x + rect.width; }

// ---- pango-gravity.h

/// Whether `gravity` is vertical (`PANGO_GRAVITY_IS_VERTICAL()`).
bool PANGO_GRAVITY_IS_VERTICAL(PangoGravity gravity) pure nothrow @nogc @safe
{
    return gravity == PANGO_GRAVITY_EAST || gravity == PANGO_GRAVITY_WEST;
}

/// Whether `gravity` is improper, i.e. upside down
/// (`PANGO_GRAVITY_IS_IMPROPER()`).
bool PANGO_GRAVITY_IS_IMPROPER(PangoGravity gravity) pure nothrow @nogc @safe
{
    return gravity == PANGO_GRAVITY_WEST || gravity == PANGO_GRAVITY_NORTH;
}

// ---- pango-matrix.h

/// The identity matrix (`PANGO_MATRIX_INIT`).
enum PangoMatrix PANGO_MATRIX_INIT = PangoMatrix(1.0, 0.0, 0.0, 1.0, 0.0, 0.0);

// ---- pango-font.h

/// Scale factors for font sizes (`PANGO_SCALE_XX_SMALL` ...
/// `PANGO_SCALE_XX_LARGE`), steps of 1.2.
enum double PANGO_SCALE_XX_SMALL = 0.5787037037037;
/// ditto
enum double PANGO_SCALE_X_SMALL = 0.6944444444444;
/// ditto
enum double PANGO_SCALE_SMALL = 0.8333333333333;
/// ditto
enum double PANGO_SCALE_MEDIUM = 1.0;
/// ditto
enum double PANGO_SCALE_LARGE = 1.2;
/// ditto
enum double PANGO_SCALE_X_LARGE = 1.44;
/// ditto
enum double PANGO_SCALE_XX_LARGE = 1.728;

/// Glyph value for an empty glyph (`PANGO_GLYPH_EMPTY`).
enum PangoGlyph PANGO_GLYPH_EMPTY = 0x0FFFFFFF;
/// Glyph value for invalid input (`PANGO_GLYPH_INVALID_INPUT`).
enum PangoGlyph PANGO_GLYPH_INVALID_INPUT = 0xFFFFFFFF;
/// Flag marking an unknown glyph (`PANGO_GLYPH_UNKNOWN_FLAG`).
enum PangoGlyph PANGO_GLYPH_UNKNOWN_FLAG = 0x10000000;

/// The unknown glyph for character `wc` (`PANGO_GET_UNKNOWN_GLYPH()`).
PangoGlyph PANGO_GET_UNKNOWN_GLYPH(dchar wc) pure nothrow @nogc @safe
{
    return cast(PangoGlyph) wc | PANGO_GLYPH_UNKNOWN_FLAG;
}

/// Size of an unknown glyph's box (`PANGO_UNKNOWN_GLYPH_WIDTH`).
enum PANGO_UNKNOWN_GLYPH_WIDTH = 10;
/// ditto (`PANGO_UNKNOWN_GLYPH_HEIGHT`).
enum PANGO_UNKNOWN_GLYPH_HEIGHT = 14;

// ---- pango-attributes.h

/// Attribute start index meaning "from the start of the text"
/// (`PANGO_ATTR_INDEX_FROM_TEXT_BEGINNING`).
enum uint PANGO_ATTR_INDEX_FROM_TEXT_BEGINNING = 0;
/// Attribute end index meaning "to the end of the text"
/// (`PANGO_ATTR_INDEX_TO_TEXT_END`).
enum uint PANGO_ATTR_INDEX_TO_TEXT_END = uint.max;

// ---- pango-item.h

/// `PangoAnalysis.flags` bits (`PANGO_ANALYSIS_FLAG_*`).
enum PANGO_ANALYSIS_FLAG_CENTERED_BASELINE = 1 << 0;
/// ditto
enum PANGO_ANALYSIS_FLAG_IS_ELLIPSIS = 1 << 1;
/// ditto
enum PANGO_ANALYSIS_FLAG_NEED_HYPHEN = 1 << 2;

// ---- HarfBuzz types Pango's API exposes (hb.h)

/// A HarfBuzz font object (`hb_font_t`), opaque.
struct hb_font_t;

/// A four-byte OpenType tag (`hb_tag_t`).
alias hb_tag_t = uint;

/// A font feature setting (`hb_feature_t`).
struct hb_feature_t
{
    hb_tag_t tag;
    uint value;
    uint start;
    uint end;
}

struct PangoCoverage;
enum PangoCoverageLevel
{
    NONE,
    FALLBACK,
    APPROXIMATE,
    EXACT,
}
enum PANGO_COVERAGE_NONE = PangoCoverageLevel.NONE; /// ditto
enum PANGO_COVERAGE_FALLBACK = PangoCoverageLevel.FALLBACK; /// ditto
enum PANGO_COVERAGE_APPROXIMATE = PangoCoverageLevel.APPROXIMATE; /// ditto
enum PANGO_COVERAGE_EXACT = PangoCoverageLevel.EXACT; /// ditto

struct PangoLogAttr
{
    import std.bitmanip : bitfields;
    mixin(bitfields!(
        uint, "isLineBreak", 1,
        uint, "isMandatoryBreak", 1,
        uint, "isCharBreak", 1,
        uint, "isWhite", 1,
        uint, "isCursorPosition", 1,
        uint, "isWordStart", 1,
        uint, "isWordEnd", 1,
        uint, "isSentenceBoundary", 1,
        uint, "isSentenceStart", 1,
        uint, "isSentenceEnd", 1,
        uint, "backspaceDeletesCharacter", 1,
        uint, "isExpandableSpace", 1,
        uint, "isWordBoundary", 1,
        uint, "breakInsertsHyphen", 1,
        uint, "breakRemovesPreceding", 1,
        uint, "reserved", 17
    ));
    alias is_line_break = isLineBreak; // C name
    alias is_mandatory_break = isMandatoryBreak; // C name
    alias is_char_break = isCharBreak; // C name
    alias is_white = isWhite; // C name
    alias is_cursor_position = isCursorPosition; // C name
    alias is_word_start = isWordStart; // C name
    alias is_word_end = isWordEnd; // C name
    alias is_sentence_boundary = isSentenceBoundary; // C name
    alias is_sentence_start = isSentenceStart; // C name
    alias is_sentence_end = isSentenceEnd; // C name
    alias backspace_deletes_character = backspaceDeletesCharacter; // C name
    alias is_expandable_space = isExpandableSpace; // C name
    alias is_word_boundary = isWordBoundary; // C name
    alias break_inserts_hyphen = breakInsertsHyphen; // C name
    alias break_removes_preceding = breakRemovesPreceding; // C name
}

struct PangoEngineLang
{
    PangoEngine parentInstance;
    alias parent_instance = parentInstance; // C name
}

struct PangoEngineShape
{
    PangoEngine parentInstance;
    alias parent_instance = parentInstance; // C name
}

struct PangoFont
{
    GObject parentInstance;
    alias parent_instance = parentInstance; // C name
}

struct PangoFontMap
{
    GObject parentInstance;
    alias parent_instance = parentInstance; // C name
}

struct PangoRectangle
{
    int x;
    int y;
    int width;
    int height;
}

struct PangoContext;
struct PangoLanguage;
alias PangoGlyph = uint;
enum PangoGravity
{
    SOUTH,
    EAST,
    NORTH,
    WEST,
    AUTO,
}
enum PANGO_GRAVITY_SOUTH = PangoGravity.SOUTH; /// ditto
enum PANGO_GRAVITY_EAST = PangoGravity.EAST; /// ditto
enum PANGO_GRAVITY_NORTH = PangoGravity.NORTH; /// ditto
enum PANGO_GRAVITY_WEST = PangoGravity.WEST; /// ditto
enum PANGO_GRAVITY_AUTO = PangoGravity.AUTO; /// ditto

enum PangoGravityHint
{
    NATURAL,
    STRONG,
    LINE,
}
enum PANGO_GRAVITY_HINT_NATURAL = PangoGravityHint.NATURAL; /// ditto
enum PANGO_GRAVITY_HINT_STRONG = PangoGravityHint.STRONG; /// ditto
enum PANGO_GRAVITY_HINT_LINE = PangoGravityHint.LINE; /// ditto

struct PangoMatrix
{
    double xx;
    double xy;
    double yx;
    double yy;
    double x0;
    double y0;
}

struct PangoScriptIter;
enum PangoScript
{
    INVALID_CODE = -1,
    COMMON = 0,
    INHERITED,
    ARABIC,
    ARMENIAN,
    BENGALI,
    BOPOMOFO,
    CHEROKEE,
    COPTIC,
    CYRILLIC,
    DESERET,
    DEVANAGARI,
    ETHIOPIC,
    GEORGIAN,
    GOTHIC,
    GREEK,
    GUJARATI,
    GURMUKHI,
    HAN,
    HANGUL,
    HEBREW,
    HIRAGANA,
    KANNADA,
    KATAKANA,
    KHMER,
    LAO,
    LATIN,
    MALAYALAM,
    MONGOLIAN,
    MYANMAR,
    OGHAM,
    OLD_ITALIC,
    ORIYA,
    RUNIC,
    SINHALA,
    SYRIAC,
    TAMIL,
    TELUGU,
    THAANA,
    THAI,
    TIBETAN,
    CANADIAN_ABORIGINAL,
    YI,
    TAGALOG,
    HANUNOO,
    BUHID,
    TAGBANWA,
    BRAILLE,
    CYPRIOT,
    LIMBU,
    OSMANYA,
    SHAVIAN,
    LINEAR_B,
    TAI_LE,
    UGARITIC,
    NEW_TAI_LUE,
    BUGINESE,
    GLAGOLITIC,
    TIFINAGH,
    SYLOTI_NAGRI,
    OLD_PERSIAN,
    KHAROSHTHI,
    UNKNOWN,
    BALINESE,
    CUNEIFORM,
    PHOENICIAN,
    PHAGS_PA,
    NKO,
    KAYAH_LI,
    LEPCHA,
    REJANG,
    SUNDANESE,
    SAURASHTRA,
    CHAM,
    OL_CHIKI,
    VAI,
    CARIAN,
    LYCIAN,
    LYDIAN,
    BATAK,
    BRAHMI,
    MANDAIC,
    CHAKMA,
    MEROITIC_CURSIVE,
    MEROITIC_HIEROGLYPHS,
    MIAO,
    SHARADA,
    SORA_SOMPENG,
    TAKRI,
    BASSA_VAH,
    CAUCASIAN_ALBANIAN,
    DUPLOYAN,
    ELBASAN,
    GRANTHA,
    KHOJKI,
    KHUDAWADI,
    LINEAR_A,
    MAHAJANI,
    MANICHAEAN,
    MENDE_KIKAKUI,
    MODI,
    MRO,
    NABATAEAN,
    OLD_NORTH_ARABIAN,
    OLD_PERMIC,
    PAHAWH_HMONG,
    PALMYRENE,
    PAU_CIN_HAU,
    PSALTER_PAHLAVI,
    SIDDHAM,
    TIRHUTA,
    WARANG_CITI,
    AHOM,
    ANATOLIAN_HIEROGLYPHS,
    HATRAN,
    MULTANI,
    OLD_HUNGARIAN,
    SIGNWRITING,
}
enum PANGO_SCRIPT_INVALID_CODE = PangoScript.INVALID_CODE; /// ditto
enum PANGO_SCRIPT_COMMON = PangoScript.COMMON; /// ditto
enum PANGO_SCRIPT_INHERITED = PangoScript.INHERITED; /// ditto
enum PANGO_SCRIPT_ARABIC = PangoScript.ARABIC; /// ditto
enum PANGO_SCRIPT_ARMENIAN = PangoScript.ARMENIAN; /// ditto
enum PANGO_SCRIPT_BENGALI = PangoScript.BENGALI; /// ditto
enum PANGO_SCRIPT_BOPOMOFO = PangoScript.BOPOMOFO; /// ditto
enum PANGO_SCRIPT_CHEROKEE = PangoScript.CHEROKEE; /// ditto
enum PANGO_SCRIPT_COPTIC = PangoScript.COPTIC; /// ditto
enum PANGO_SCRIPT_CYRILLIC = PangoScript.CYRILLIC; /// ditto
enum PANGO_SCRIPT_DESERET = PangoScript.DESERET; /// ditto
enum PANGO_SCRIPT_DEVANAGARI = PangoScript.DEVANAGARI; /// ditto
enum PANGO_SCRIPT_ETHIOPIC = PangoScript.ETHIOPIC; /// ditto
enum PANGO_SCRIPT_GEORGIAN = PangoScript.GEORGIAN; /// ditto
enum PANGO_SCRIPT_GOTHIC = PangoScript.GOTHIC; /// ditto
enum PANGO_SCRIPT_GREEK = PangoScript.GREEK; /// ditto
enum PANGO_SCRIPT_GUJARATI = PangoScript.GUJARATI; /// ditto
enum PANGO_SCRIPT_GURMUKHI = PangoScript.GURMUKHI; /// ditto
enum PANGO_SCRIPT_HAN = PangoScript.HAN; /// ditto
enum PANGO_SCRIPT_HANGUL = PangoScript.HANGUL; /// ditto
enum PANGO_SCRIPT_HEBREW = PangoScript.HEBREW; /// ditto
enum PANGO_SCRIPT_HIRAGANA = PangoScript.HIRAGANA; /// ditto
enum PANGO_SCRIPT_KANNADA = PangoScript.KANNADA; /// ditto
enum PANGO_SCRIPT_KATAKANA = PangoScript.KATAKANA; /// ditto
enum PANGO_SCRIPT_KHMER = PangoScript.KHMER; /// ditto
enum PANGO_SCRIPT_LAO = PangoScript.LAO; /// ditto
enum PANGO_SCRIPT_LATIN = PangoScript.LATIN; /// ditto
enum PANGO_SCRIPT_MALAYALAM = PangoScript.MALAYALAM; /// ditto
enum PANGO_SCRIPT_MONGOLIAN = PangoScript.MONGOLIAN; /// ditto
enum PANGO_SCRIPT_MYANMAR = PangoScript.MYANMAR; /// ditto
enum PANGO_SCRIPT_OGHAM = PangoScript.OGHAM; /// ditto
enum PANGO_SCRIPT_OLD_ITALIC = PangoScript.OLD_ITALIC; /// ditto
enum PANGO_SCRIPT_ORIYA = PangoScript.ORIYA; /// ditto
enum PANGO_SCRIPT_RUNIC = PangoScript.RUNIC; /// ditto
enum PANGO_SCRIPT_SINHALA = PangoScript.SINHALA; /// ditto
enum PANGO_SCRIPT_SYRIAC = PangoScript.SYRIAC; /// ditto
enum PANGO_SCRIPT_TAMIL = PangoScript.TAMIL; /// ditto
enum PANGO_SCRIPT_TELUGU = PangoScript.TELUGU; /// ditto
enum PANGO_SCRIPT_THAANA = PangoScript.THAANA; /// ditto
enum PANGO_SCRIPT_THAI = PangoScript.THAI; /// ditto
enum PANGO_SCRIPT_TIBETAN = PangoScript.TIBETAN; /// ditto
enum PANGO_SCRIPT_CANADIAN_ABORIGINAL = PangoScript.CANADIAN_ABORIGINAL; /// ditto
enum PANGO_SCRIPT_YI = PangoScript.YI; /// ditto
enum PANGO_SCRIPT_TAGALOG = PangoScript.TAGALOG; /// ditto
enum PANGO_SCRIPT_HANUNOO = PangoScript.HANUNOO; /// ditto
enum PANGO_SCRIPT_BUHID = PangoScript.BUHID; /// ditto
enum PANGO_SCRIPT_TAGBANWA = PangoScript.TAGBANWA; /// ditto
enum PANGO_SCRIPT_BRAILLE = PangoScript.BRAILLE; /// ditto
enum PANGO_SCRIPT_CYPRIOT = PangoScript.CYPRIOT; /// ditto
enum PANGO_SCRIPT_LIMBU = PangoScript.LIMBU; /// ditto
enum PANGO_SCRIPT_OSMANYA = PangoScript.OSMANYA; /// ditto
enum PANGO_SCRIPT_SHAVIAN = PangoScript.SHAVIAN; /// ditto
enum PANGO_SCRIPT_LINEAR_B = PangoScript.LINEAR_B; /// ditto
enum PANGO_SCRIPT_TAI_LE = PangoScript.TAI_LE; /// ditto
enum PANGO_SCRIPT_UGARITIC = PangoScript.UGARITIC; /// ditto
enum PANGO_SCRIPT_NEW_TAI_LUE = PangoScript.NEW_TAI_LUE; /// ditto
enum PANGO_SCRIPT_BUGINESE = PangoScript.BUGINESE; /// ditto
enum PANGO_SCRIPT_GLAGOLITIC = PangoScript.GLAGOLITIC; /// ditto
enum PANGO_SCRIPT_TIFINAGH = PangoScript.TIFINAGH; /// ditto
enum PANGO_SCRIPT_SYLOTI_NAGRI = PangoScript.SYLOTI_NAGRI; /// ditto
enum PANGO_SCRIPT_OLD_PERSIAN = PangoScript.OLD_PERSIAN; /// ditto
enum PANGO_SCRIPT_KHAROSHTHI = PangoScript.KHAROSHTHI; /// ditto
enum PANGO_SCRIPT_UNKNOWN = PangoScript.UNKNOWN; /// ditto
enum PANGO_SCRIPT_BALINESE = PangoScript.BALINESE; /// ditto
enum PANGO_SCRIPT_CUNEIFORM = PangoScript.CUNEIFORM; /// ditto
enum PANGO_SCRIPT_PHOENICIAN = PangoScript.PHOENICIAN; /// ditto
enum PANGO_SCRIPT_PHAGS_PA = PangoScript.PHAGS_PA; /// ditto
enum PANGO_SCRIPT_NKO = PangoScript.NKO; /// ditto
enum PANGO_SCRIPT_KAYAH_LI = PangoScript.KAYAH_LI; /// ditto
enum PANGO_SCRIPT_LEPCHA = PangoScript.LEPCHA; /// ditto
enum PANGO_SCRIPT_REJANG = PangoScript.REJANG; /// ditto
enum PANGO_SCRIPT_SUNDANESE = PangoScript.SUNDANESE; /// ditto
enum PANGO_SCRIPT_SAURASHTRA = PangoScript.SAURASHTRA; /// ditto
enum PANGO_SCRIPT_CHAM = PangoScript.CHAM; /// ditto
enum PANGO_SCRIPT_OL_CHIKI = PangoScript.OL_CHIKI; /// ditto
enum PANGO_SCRIPT_VAI = PangoScript.VAI; /// ditto
enum PANGO_SCRIPT_CARIAN = PangoScript.CARIAN; /// ditto
enum PANGO_SCRIPT_LYCIAN = PangoScript.LYCIAN; /// ditto
enum PANGO_SCRIPT_LYDIAN = PangoScript.LYDIAN; /// ditto
enum PANGO_SCRIPT_BATAK = PangoScript.BATAK; /// ditto
enum PANGO_SCRIPT_BRAHMI = PangoScript.BRAHMI; /// ditto
enum PANGO_SCRIPT_MANDAIC = PangoScript.MANDAIC; /// ditto
enum PANGO_SCRIPT_CHAKMA = PangoScript.CHAKMA; /// ditto
enum PANGO_SCRIPT_MEROITIC_CURSIVE = PangoScript.MEROITIC_CURSIVE; /// ditto
enum PANGO_SCRIPT_MEROITIC_HIEROGLYPHS = PangoScript.MEROITIC_HIEROGLYPHS; /// ditto
enum PANGO_SCRIPT_MIAO = PangoScript.MIAO; /// ditto
enum PANGO_SCRIPT_SHARADA = PangoScript.SHARADA; /// ditto
enum PANGO_SCRIPT_SORA_SOMPENG = PangoScript.SORA_SOMPENG; /// ditto
enum PANGO_SCRIPT_TAKRI = PangoScript.TAKRI; /// ditto
enum PANGO_SCRIPT_BASSA_VAH = PangoScript.BASSA_VAH; /// ditto
enum PANGO_SCRIPT_CAUCASIAN_ALBANIAN = PangoScript.CAUCASIAN_ALBANIAN; /// ditto
enum PANGO_SCRIPT_DUPLOYAN = PangoScript.DUPLOYAN; /// ditto
enum PANGO_SCRIPT_ELBASAN = PangoScript.ELBASAN; /// ditto
enum PANGO_SCRIPT_GRANTHA = PangoScript.GRANTHA; /// ditto
enum PANGO_SCRIPT_KHOJKI = PangoScript.KHOJKI; /// ditto
enum PANGO_SCRIPT_KHUDAWADI = PangoScript.KHUDAWADI; /// ditto
enum PANGO_SCRIPT_LINEAR_A = PangoScript.LINEAR_A; /// ditto
enum PANGO_SCRIPT_MAHAJANI = PangoScript.MAHAJANI; /// ditto
enum PANGO_SCRIPT_MANICHAEAN = PangoScript.MANICHAEAN; /// ditto
enum PANGO_SCRIPT_MENDE_KIKAKUI = PangoScript.MENDE_KIKAKUI; /// ditto
enum PANGO_SCRIPT_MODI = PangoScript.MODI; /// ditto
enum PANGO_SCRIPT_MRO = PangoScript.MRO; /// ditto
enum PANGO_SCRIPT_NABATAEAN = PangoScript.NABATAEAN; /// ditto
enum PANGO_SCRIPT_OLD_NORTH_ARABIAN = PangoScript.OLD_NORTH_ARABIAN; /// ditto
enum PANGO_SCRIPT_OLD_PERMIC = PangoScript.OLD_PERMIC; /// ditto
enum PANGO_SCRIPT_PAHAWH_HMONG = PangoScript.PAHAWH_HMONG; /// ditto
enum PANGO_SCRIPT_PALMYRENE = PangoScript.PALMYRENE; /// ditto
enum PANGO_SCRIPT_PAU_CIN_HAU = PangoScript.PAU_CIN_HAU; /// ditto
enum PANGO_SCRIPT_PSALTER_PAHLAVI = PangoScript.PSALTER_PAHLAVI; /// ditto
enum PANGO_SCRIPT_SIDDHAM = PangoScript.SIDDHAM; /// ditto
enum PANGO_SCRIPT_TIRHUTA = PangoScript.TIRHUTA; /// ditto
enum PANGO_SCRIPT_WARANG_CITI = PangoScript.WARANG_CITI; /// ditto
enum PANGO_SCRIPT_AHOM = PangoScript.AHOM; /// ditto
enum PANGO_SCRIPT_ANATOLIAN_HIEROGLYPHS = PangoScript.ANATOLIAN_HIEROGLYPHS; /// ditto
enum PANGO_SCRIPT_HATRAN = PangoScript.HATRAN; /// ditto
enum PANGO_SCRIPT_MULTANI = PangoScript.MULTANI; /// ditto
enum PANGO_SCRIPT_OLD_HUNGARIAN = PangoScript.OLD_HUNGARIAN; /// ditto
enum PANGO_SCRIPT_SIGNWRITING = PangoScript.SIGNWRITING; /// ditto

enum PangoDirection
{
    LTR,
    RTL,
    TTB_LTR,
    TTB_RTL,
    WEAK_LTR,
    WEAK_RTL,
    NEUTRAL,
}
enum PANGO_DIRECTION_LTR = PangoDirection.LTR; /// ditto
enum PANGO_DIRECTION_RTL = PangoDirection.RTL; /// ditto
enum PANGO_DIRECTION_TTB_LTR = PangoDirection.TTB_LTR; /// ditto
enum PANGO_DIRECTION_TTB_RTL = PangoDirection.TTB_RTL; /// ditto
enum PANGO_DIRECTION_WEAK_LTR = PangoDirection.WEAK_LTR; /// ditto
enum PANGO_DIRECTION_WEAK_RTL = PangoDirection.WEAK_RTL; /// ditto
enum PANGO_DIRECTION_NEUTRAL = PangoDirection.NEUTRAL; /// ditto

enum PangoBidiType
{
    L,
    LRE,
    LRO,
    R,
    AL,
    RLE,
    RLO,
    PDF,
    EN,
    ES,
    ET,
    AN,
    CS,
    NSM,
    BN,
    B,
    S,
    WS,
    ON,
    LRI,
    RLI,
    FSI,
    PDI,
}
enum PANGO_BIDI_TYPE_L = PangoBidiType.L; /// ditto
enum PANGO_BIDI_TYPE_LRE = PangoBidiType.LRE; /// ditto
enum PANGO_BIDI_TYPE_LRO = PangoBidiType.LRO; /// ditto
enum PANGO_BIDI_TYPE_R = PangoBidiType.R; /// ditto
enum PANGO_BIDI_TYPE_AL = PangoBidiType.AL; /// ditto
enum PANGO_BIDI_TYPE_RLE = PangoBidiType.RLE; /// ditto
enum PANGO_BIDI_TYPE_RLO = PangoBidiType.RLO; /// ditto
enum PANGO_BIDI_TYPE_PDF = PangoBidiType.PDF; /// ditto
enum PANGO_BIDI_TYPE_EN = PangoBidiType.EN; /// ditto
enum PANGO_BIDI_TYPE_ES = PangoBidiType.ES; /// ditto
enum PANGO_BIDI_TYPE_ET = PangoBidiType.ET; /// ditto
enum PANGO_BIDI_TYPE_AN = PangoBidiType.AN; /// ditto
enum PANGO_BIDI_TYPE_CS = PangoBidiType.CS; /// ditto
enum PANGO_BIDI_TYPE_NSM = PangoBidiType.NSM; /// ditto
enum PANGO_BIDI_TYPE_BN = PangoBidiType.BN; /// ditto
enum PANGO_BIDI_TYPE_B = PangoBidiType.B; /// ditto
enum PANGO_BIDI_TYPE_S = PangoBidiType.S; /// ditto
enum PANGO_BIDI_TYPE_WS = PangoBidiType.WS; /// ditto
enum PANGO_BIDI_TYPE_ON = PangoBidiType.ON; /// ditto
enum PANGO_BIDI_TYPE_LRI = PangoBidiType.LRI; /// ditto
enum PANGO_BIDI_TYPE_RLI = PangoBidiType.RLI; /// ditto
enum PANGO_BIDI_TYPE_FSI = PangoBidiType.FSI; /// ditto
enum PANGO_BIDI_TYPE_PDI = PangoBidiType.PDI; /// ditto

struct PangoFontDescription;
struct PangoFontMetrics
{
    uint refCount;
    int ascent;
    int descent;
    int height;
    int approximateCharWidth;
    int approximateDigitWidth;
    int underlinePosition;
    int underlineThickness;
    int strikethroughPosition;
    int strikethroughThickness;
    alias ref_count = refCount; // C name
    alias approximate_char_width = approximateCharWidth; // C name
    alias approximate_digit_width = approximateDigitWidth; // C name
    alias underline_position = underlinePosition; // C name
    alias underline_thickness = underlineThickness; // C name
    alias strikethrough_position = strikethroughPosition; // C name
    alias strikethrough_thickness = strikethroughThickness; // C name
}

enum PangoStyle
{
    NORMAL,
    OBLIQUE,
    ITALIC,
}
enum PANGO_STYLE_NORMAL = PangoStyle.NORMAL; /// ditto
enum PANGO_STYLE_OBLIQUE = PangoStyle.OBLIQUE; /// ditto
enum PANGO_STYLE_ITALIC = PangoStyle.ITALIC; /// ditto

enum PangoVariant
{
    NORMAL,
    SMALL_CAPS,
    ALL_SMALL_CAPS,
    PETITE_CAPS,
    ALL_PETITE_CAPS,
    UNICASE,
    TITLE_CAPS,
}
enum PANGO_VARIANT_NORMAL = PangoVariant.NORMAL; /// ditto
enum PANGO_VARIANT_SMALL_CAPS = PangoVariant.SMALL_CAPS; /// ditto
enum PANGO_VARIANT_ALL_SMALL_CAPS = PangoVariant.ALL_SMALL_CAPS; /// ditto
enum PANGO_VARIANT_PETITE_CAPS = PangoVariant.PETITE_CAPS; /// ditto
enum PANGO_VARIANT_ALL_PETITE_CAPS = PangoVariant.ALL_PETITE_CAPS; /// ditto
enum PANGO_VARIANT_UNICASE = PangoVariant.UNICASE; /// ditto
enum PANGO_VARIANT_TITLE_CAPS = PangoVariant.TITLE_CAPS; /// ditto

enum PangoWeight
{
    THIN = 100,
    ULTRALIGHT = 200,
    LIGHT = 300,
    SEMILIGHT = 350,
    BOOK = 380,
    NORMAL = 400,
    MEDIUM = 500,
    SEMIBOLD = 600,
    BOLD = 700,
    ULTRABOLD = 800,
    HEAVY = 900,
    ULTRAHEAVY = 1000,
}
enum PANGO_WEIGHT_THIN = PangoWeight.THIN; /// ditto
enum PANGO_WEIGHT_ULTRALIGHT = PangoWeight.ULTRALIGHT; /// ditto
enum PANGO_WEIGHT_LIGHT = PangoWeight.LIGHT; /// ditto
enum PANGO_WEIGHT_SEMILIGHT = PangoWeight.SEMILIGHT; /// ditto
enum PANGO_WEIGHT_BOOK = PangoWeight.BOOK; /// ditto
enum PANGO_WEIGHT_NORMAL = PangoWeight.NORMAL; /// ditto
enum PANGO_WEIGHT_MEDIUM = PangoWeight.MEDIUM; /// ditto
enum PANGO_WEIGHT_SEMIBOLD = PangoWeight.SEMIBOLD; /// ditto
enum PANGO_WEIGHT_BOLD = PangoWeight.BOLD; /// ditto
enum PANGO_WEIGHT_ULTRABOLD = PangoWeight.ULTRABOLD; /// ditto
enum PANGO_WEIGHT_HEAVY = PangoWeight.HEAVY; /// ditto
enum PANGO_WEIGHT_ULTRAHEAVY = PangoWeight.ULTRAHEAVY; /// ditto

enum PangoStretch
{
    ULTRA_CONDENSED,
    EXTRA_CONDENSED,
    CONDENSED,
    SEMI_CONDENSED,
    NORMAL,
    SEMI_EXPANDED,
    EXPANDED,
    EXTRA_EXPANDED,
    ULTRA_EXPANDED,
}
enum PANGO_STRETCH_ULTRA_CONDENSED = PangoStretch.ULTRA_CONDENSED; /// ditto
enum PANGO_STRETCH_EXTRA_CONDENSED = PangoStretch.EXTRA_CONDENSED; /// ditto
enum PANGO_STRETCH_CONDENSED = PangoStretch.CONDENSED; /// ditto
enum PANGO_STRETCH_SEMI_CONDENSED = PangoStretch.SEMI_CONDENSED; /// ditto
enum PANGO_STRETCH_NORMAL = PangoStretch.NORMAL; /// ditto
enum PANGO_STRETCH_SEMI_EXPANDED = PangoStretch.SEMI_EXPANDED; /// ditto
enum PANGO_STRETCH_EXPANDED = PangoStretch.EXPANDED; /// ditto
enum PANGO_STRETCH_EXTRA_EXPANDED = PangoStretch.EXTRA_EXPANDED; /// ditto
enum PANGO_STRETCH_ULTRA_EXPANDED = PangoStretch.ULTRA_EXPANDED; /// ditto

enum PangoFontMask
{
    FAMILY = 1 << 0,
    STYLE = 1 << 1,
    VARIANT = 1 << 2,
    WEIGHT = 1 << 3,
    STRETCH = 1 << 4,
    SIZE = 1 << 5,
    GRAVITY = 1 << 6,
    VARIATIONS = 1 << 7,
    FEATURES = 1 << 8,
    COLOR = 1 << 9,
}
enum PANGO_FONT_MASK_FAMILY = PangoFontMask.FAMILY; /// ditto
enum PANGO_FONT_MASK_STYLE = PangoFontMask.STYLE; /// ditto
enum PANGO_FONT_MASK_VARIANT = PangoFontMask.VARIANT; /// ditto
enum PANGO_FONT_MASK_WEIGHT = PangoFontMask.WEIGHT; /// ditto
enum PANGO_FONT_MASK_STRETCH = PangoFontMask.STRETCH; /// ditto
enum PANGO_FONT_MASK_SIZE = PangoFontMask.SIZE; /// ditto
enum PANGO_FONT_MASK_GRAVITY = PangoFontMask.GRAVITY; /// ditto
enum PANGO_FONT_MASK_VARIATIONS = PangoFontMask.VARIATIONS; /// ditto
enum PANGO_FONT_MASK_FEATURES = PangoFontMask.FEATURES; /// ditto
enum PANGO_FONT_MASK_COLOR = PangoFontMask.COLOR; /// ditto

enum PangoFontColor
{
    FORBIDDEN,
    REQUIRED,
    DONT_CARE,
}
enum PANGO_FONT_COLOR_FORBIDDEN = PangoFontColor.FORBIDDEN; /// ditto
enum PANGO_FONT_COLOR_REQUIRED = PangoFontColor.REQUIRED; /// ditto
enum PANGO_FONT_COLOR_DONT_CARE = PangoFontColor.DONT_CARE; /// ditto

struct PangoFontFace
{
    GObject parentInstance;
    alias parent_instance = parentInstance; // C name
}

struct PangoFontFamily
{
    GObject parentInstance;
    alias parent_instance = parentInstance; // C name
}

struct PangoFontFamilyClass
{
    GObjectClass parentClass;
    extern (C) void function(PangoFontFamily* family, PangoFontFace*** faces, int* n_faces) listFaces;
    extern (C) const(char)* function(PangoFontFamily* family) getName;
    extern (C) int function(PangoFontFamily* family) isMonospace;
    extern (C) int function(PangoFontFamily* family) isVariable;
    extern (C) PangoFontFace* function(PangoFontFamily* family, const(char)* name) getFace;
    extern (C) void function() PangoReserved2;
    alias parent_class = parentClass; // C name
    alias list_faces = listFaces; // C name
    alias get_name = getName; // C name
    alias is_monospace = isMonospace; // C name
    alias is_variable = isVariable; // C name
    alias get_face = getFace; // C name
    alias _pango_reserved2 = PangoReserved2; // C name
}

struct PangoFontFaceClass
{
    GObjectClass parentClass;
    extern (C) const(char)* function(PangoFontFace* face) getFaceName;
    extern (C) PangoFontDescription* function(PangoFontFace* face) describe;
    extern (C) void function(PangoFontFace* face, int** sizes, int* n_sizes) listSizes;
    extern (C) int function(PangoFontFace* face) isSynthesized;
    extern (C) PangoFontFamily* function(PangoFontFace* face) getFamily;
    extern (C) void function() PangoReserved3;
    extern (C) void function() PangoReserved4;
    alias parent_class = parentClass; // C name
    alias get_face_name = getFaceName; // C name
    alias list_sizes = listSizes; // C name
    alias is_synthesized = isSynthesized; // C name
    alias get_family = getFamily; // C name
    alias _pango_reserved3 = PangoReserved3; // C name
    alias _pango_reserved4 = PangoReserved4; // C name
}

struct PangoFontClass
{
    GObjectClass parentClass;
    extern (C) PangoFontDescription* function(PangoFont* font) describe;
    extern (C) PangoCoverage* function(PangoFont* font, PangoLanguage* language) getCoverage;
    extern (C) void function(PangoFont* font, PangoGlyph glyph, PangoRectangle* ink_rect, PangoRectangle* logical_rect) getGlyphExtents;
    extern (C) PangoFontMetrics* function(PangoFont* font, PangoLanguage* language) getMetrics;
    extern (C) PangoFontMap* function(PangoFont* font) getFontMap;
    extern (C) PangoFontDescription* function(PangoFont* font) describeAbsolute;
    extern (C) void function(PangoFont* font, hb_feature_t* features, uint len, uint* num_features) getFeatures;
    extern (C) hb_font_t* function(PangoFont* font) createHbFont;
    alias parent_class = parentClass; // C name
    alias get_coverage = getCoverage; // C name
    alias get_glyph_extents = getGlyphExtents; // C name
    alias get_metrics = getMetrics; // C name
    alias get_font_map = getFontMap; // C name
    alias describe_absolute = describeAbsolute; // C name
    alias get_features = getFeatures; // C name
    alias create_hb_font = createHbFont; // C name
}

struct PangoColor
{
    ushort red;
    ushort green;
    ushort blue;
}

struct PangoAttribute
{
    const(PangoAttrClass)* klass;
    uint startIndex;
    uint endIndex;
    alias start_index = startIndex; // C name
    alias end_index = endIndex; // C name
}

struct PangoAttrClass
{
    PangoAttrType type;
    extern (C) PangoAttribute* function(const(PangoAttribute)* attr) copy;
    extern (C) void function(PangoAttribute* attr) destroy;
    extern (C) int function(const(PangoAttribute)* attr1, const(PangoAttribute)* attr2) equal;
}

struct PangoAttrString
{
    PangoAttribute attr;
    char* value;
}

struct PangoAttrLanguage
{
    PangoAttribute attr;
    PangoLanguage* value;
}

struct PangoAttrInt
{
    PangoAttribute attr;
    int value;
}

struct PangoAttrSize
{
    import std.bitmanip : bitfields;
    PangoAttribute attr;
    int size;
    mixin(bitfields!(
        uint, "absolute", 1,
        uint, "", 31
    ));
}

struct PangoAttrFloat
{
    PangoAttribute attr;
    double value;
}

struct PangoAttrColor
{
    PangoAttribute attr;
    PangoColor color;
}

struct PangoAttrFontDesc
{
    PangoAttribute attr;
    PangoFontDescription* desc;
}

struct PangoAttrShape
{
    PangoAttribute attr;
    PangoRectangle inkRect;
    PangoRectangle logicalRect;
    void* data;
    PangoAttrDataCopyFunc copyFunc;
    GDestroyNotify destroyFunc;
    alias ink_rect = inkRect; // C name
    alias logical_rect = logicalRect; // C name
    alias copy_func = copyFunc; // C name
    alias destroy_func = destroyFunc; // C name
}

struct PangoAttrFontFeatures
{
    PangoAttribute attr;
    char* features;
}

enum PangoAttrType
{
    INVALID,
    LANGUAGE,
    FAMILY,
    STYLE,
    WEIGHT,
    VARIANT,
    STRETCH,
    SIZE,
    FONT_DESC,
    FOREGROUND,
    BACKGROUND,
    UNDERLINE,
    STRIKETHROUGH,
    RISE,
    SHAPE,
    SCALE,
    FALLBACK,
    LETTER_SPACING,
    UNDERLINE_COLOR,
    STRIKETHROUGH_COLOR,
    ABSOLUTE_SIZE,
    GRAVITY,
    GRAVITY_HINT,
    FONT_FEATURES,
    FOREGROUND_ALPHA,
    BACKGROUND_ALPHA,
    ALLOW_BREAKS,
    SHOW,
    INSERT_HYPHENS,
    OVERLINE,
    OVERLINE_COLOR,
    LINE_HEIGHT,
    ABSOLUTE_LINE_HEIGHT,
    TEXT_TRANSFORM,
    WORD,
    SENTENCE,
    BASELINE_SHIFT,
    FONT_SCALE,
}
enum PANGO_ATTR_INVALID = PangoAttrType.INVALID; /// ditto
enum PANGO_ATTR_LANGUAGE = PangoAttrType.LANGUAGE; /// ditto
enum PANGO_ATTR_FAMILY = PangoAttrType.FAMILY; /// ditto
enum PANGO_ATTR_STYLE = PangoAttrType.STYLE; /// ditto
enum PANGO_ATTR_WEIGHT = PangoAttrType.WEIGHT; /// ditto
enum PANGO_ATTR_VARIANT = PangoAttrType.VARIANT; /// ditto
enum PANGO_ATTR_STRETCH = PangoAttrType.STRETCH; /// ditto
enum PANGO_ATTR_SIZE = PangoAttrType.SIZE; /// ditto
enum PANGO_ATTR_FONT_DESC = PangoAttrType.FONT_DESC; /// ditto
enum PANGO_ATTR_FOREGROUND = PangoAttrType.FOREGROUND; /// ditto
enum PANGO_ATTR_BACKGROUND = PangoAttrType.BACKGROUND; /// ditto
enum PANGO_ATTR_UNDERLINE = PangoAttrType.UNDERLINE; /// ditto
enum PANGO_ATTR_STRIKETHROUGH = PangoAttrType.STRIKETHROUGH; /// ditto
enum PANGO_ATTR_RISE = PangoAttrType.RISE; /// ditto
enum PANGO_ATTR_SHAPE = PangoAttrType.SHAPE; /// ditto
enum PANGO_ATTR_SCALE = PangoAttrType.SCALE; /// ditto
enum PANGO_ATTR_FALLBACK = PangoAttrType.FALLBACK; /// ditto
enum PANGO_ATTR_LETTER_SPACING = PangoAttrType.LETTER_SPACING; /// ditto
enum PANGO_ATTR_UNDERLINE_COLOR = PangoAttrType.UNDERLINE_COLOR; /// ditto
enum PANGO_ATTR_STRIKETHROUGH_COLOR = PangoAttrType.STRIKETHROUGH_COLOR; /// ditto
enum PANGO_ATTR_ABSOLUTE_SIZE = PangoAttrType.ABSOLUTE_SIZE; /// ditto
enum PANGO_ATTR_GRAVITY = PangoAttrType.GRAVITY; /// ditto
enum PANGO_ATTR_GRAVITY_HINT = PangoAttrType.GRAVITY_HINT; /// ditto
enum PANGO_ATTR_FONT_FEATURES = PangoAttrType.FONT_FEATURES; /// ditto
enum PANGO_ATTR_FOREGROUND_ALPHA = PangoAttrType.FOREGROUND_ALPHA; /// ditto
enum PANGO_ATTR_BACKGROUND_ALPHA = PangoAttrType.BACKGROUND_ALPHA; /// ditto
enum PANGO_ATTR_ALLOW_BREAKS = PangoAttrType.ALLOW_BREAKS; /// ditto
enum PANGO_ATTR_SHOW = PangoAttrType.SHOW; /// ditto
enum PANGO_ATTR_INSERT_HYPHENS = PangoAttrType.INSERT_HYPHENS; /// ditto
enum PANGO_ATTR_OVERLINE = PangoAttrType.OVERLINE; /// ditto
enum PANGO_ATTR_OVERLINE_COLOR = PangoAttrType.OVERLINE_COLOR; /// ditto
enum PANGO_ATTR_LINE_HEIGHT = PangoAttrType.LINE_HEIGHT; /// ditto
enum PANGO_ATTR_ABSOLUTE_LINE_HEIGHT = PangoAttrType.ABSOLUTE_LINE_HEIGHT; /// ditto
enum PANGO_ATTR_TEXT_TRANSFORM = PangoAttrType.TEXT_TRANSFORM; /// ditto
enum PANGO_ATTR_WORD = PangoAttrType.WORD; /// ditto
enum PANGO_ATTR_SENTENCE = PangoAttrType.SENTENCE; /// ditto
enum PANGO_ATTR_BASELINE_SHIFT = PangoAttrType.BASELINE_SHIFT; /// ditto
enum PANGO_ATTR_FONT_SCALE = PangoAttrType.FONT_SCALE; /// ditto

enum PangoUnderline
{
    NONE,
    SINGLE,
    DOUBLE,
    LOW,
    ERROR,
    SINGLE_LINE,
    DOUBLE_LINE,
    ERROR_LINE,
}
enum PANGO_UNDERLINE_NONE = PangoUnderline.NONE; /// ditto
enum PANGO_UNDERLINE_SINGLE = PangoUnderline.SINGLE; /// ditto
enum PANGO_UNDERLINE_DOUBLE = PangoUnderline.DOUBLE; /// ditto
enum PANGO_UNDERLINE_LOW = PangoUnderline.LOW; /// ditto
enum PANGO_UNDERLINE_ERROR = PangoUnderline.ERROR; /// ditto
enum PANGO_UNDERLINE_SINGLE_LINE = PangoUnderline.SINGLE_LINE; /// ditto
enum PANGO_UNDERLINE_DOUBLE_LINE = PangoUnderline.DOUBLE_LINE; /// ditto
enum PANGO_UNDERLINE_ERROR_LINE = PangoUnderline.ERROR_LINE; /// ditto

enum PangoOverline
{
    NONE,
    SINGLE,
}
enum PANGO_OVERLINE_NONE = PangoOverline.NONE; /// ditto
enum PANGO_OVERLINE_SINGLE = PangoOverline.SINGLE; /// ditto

enum PangoShowFlags
{
    NONE = 0,
    SPACES = 1 << 0,
    LINE_BREAKS = 1 << 1,
    IGNORABLES = 1 << 2,
}
enum PANGO_SHOW_NONE = PangoShowFlags.NONE; /// ditto
enum PANGO_SHOW_SPACES = PangoShowFlags.SPACES; /// ditto
enum PANGO_SHOW_LINE_BREAKS = PangoShowFlags.LINE_BREAKS; /// ditto
enum PANGO_SHOW_IGNORABLES = PangoShowFlags.IGNORABLES; /// ditto

enum PangoTextTransform
{
    NONE,
    LOWERCASE,
    UPPERCASE,
    CAPITALIZE,
}
enum PANGO_TEXT_TRANSFORM_NONE = PangoTextTransform.NONE; /// ditto
enum PANGO_TEXT_TRANSFORM_LOWERCASE = PangoTextTransform.LOWERCASE; /// ditto
enum PANGO_TEXT_TRANSFORM_UPPERCASE = PangoTextTransform.UPPERCASE; /// ditto
enum PANGO_TEXT_TRANSFORM_CAPITALIZE = PangoTextTransform.CAPITALIZE; /// ditto

enum PangoBaselineShift
{
    NONE,
    SUPERSCRIPT,
    SUBSCRIPT,
}
enum PANGO_BASELINE_SHIFT_NONE = PangoBaselineShift.NONE; /// ditto
enum PANGO_BASELINE_SHIFT_SUPERSCRIPT = PangoBaselineShift.SUPERSCRIPT; /// ditto
enum PANGO_BASELINE_SHIFT_SUBSCRIPT = PangoBaselineShift.SUBSCRIPT; /// ditto

enum PangoFontScale
{
    NONE,
    SUPERSCRIPT,
    SUBSCRIPT,
    SMALL_CAPS,
}
enum PANGO_FONT_SCALE_NONE = PangoFontScale.NONE; /// ditto
enum PANGO_FONT_SCALE_SUPERSCRIPT = PangoFontScale.SUPERSCRIPT; /// ditto
enum PANGO_FONT_SCALE_SUBSCRIPT = PangoFontScale.SUBSCRIPT; /// ditto
enum PANGO_FONT_SCALE_SMALL_CAPS = PangoFontScale.SMALL_CAPS; /// ditto

alias PangoAttrFilterFunc = extern (C) int function(PangoAttribute* attribute, void* user_data);

alias PangoAttrDataCopyFunc = extern (C) void* function(const(void)* user_data);

struct PangoAttrList;
struct PangoAttrIterator;
struct PangoAnalysis
{
    PangoEngineShape* shapeEngine;
    PangoEngineLang* langEngine;
    PangoFont* font;
    ubyte level;
    ubyte gravity;
    ubyte flags;
    ubyte script;
    PangoLanguage* language;
    GSList* extraAttrs;
    alias shape_engine = shapeEngine; // C name
    alias lang_engine = langEngine; // C name
    alias extra_attrs = extraAttrs; // C name
}

struct PangoItem
{
    int offset;
    int length;
    int numChars;
    PangoAnalysis analysis;
    alias num_chars = numChars; // C name
}

struct PangoFontset
{
    GObject parentInstance;
    alias parent_instance = parentInstance; // C name
}

struct PangoFontsetClass
{
    GObjectClass parentClass;
    extern (C) PangoFont* function(PangoFontset* fontset, uint wc) getFont;
    extern (C) PangoFontMetrics* function(PangoFontset* fontset) getMetrics;
    extern (C) PangoLanguage* function(PangoFontset* fontset) getLanguage;
    extern (C) void function(PangoFontset* fontset, PangoFontsetForeachFunc func, void* data) foreach_;
    extern (C) void function() PangoReserved1;
    extern (C) void function() PangoReserved2;
    extern (C) void function() PangoReserved3;
    extern (C) void function() PangoReserved4;
    alias parent_class = parentClass; // C name
    alias get_font = getFont; // C name
    alias get_metrics = getMetrics; // C name
    alias get_language = getLanguage; // C name
    alias _pango_reserved1 = PangoReserved1; // C name
    alias _pango_reserved2 = PangoReserved2; // C name
    alias _pango_reserved3 = PangoReserved3; // C name
    alias _pango_reserved4 = PangoReserved4; // C name
}

alias PangoFontsetForeachFunc = extern (C) int function(PangoFontset* fontset, PangoFont* font, void* user_data);

struct PangoFontMapClass
{
    GObjectClass parentClass;
    extern (C) PangoFont* function(PangoFontMap* fontmap, PangoContext* context, const(PangoFontDescription)* desc) loadFont;
    extern (C) void function(PangoFontMap* fontmap, PangoFontFamily*** families, int* n_families) listFamilies;
    extern (C) PangoFontset* function(PangoFontMap* fontmap, PangoContext* context, const(PangoFontDescription)* desc, PangoLanguage* language) loadFontset;
    const(char)* shapeEngineType;
    extern (C) uint function(PangoFontMap* fontmap) getSerial;
    extern (C) void function(PangoFontMap* fontmap) changed;
    extern (C) PangoFontFamily* function(PangoFontMap* fontmap, const(char)* name) getFamily;
    extern (C) PangoFontFace* function(PangoFontMap* fontmap, PangoFont* font) getFace;
    alias parent_class = parentClass; // C name
    alias load_font = loadFont; // C name
    alias list_families = listFamilies; // C name
    alias load_fontset = loadFontset; // C name
    alias shape_engine_type = shapeEngineType; // C name
    alias get_serial = getSerial; // C name
    alias get_family = getFamily; // C name
    alias get_face = getFace; // C name
}

struct PangoContextClass;
struct PangoGlyphGeometry
{
    PangoGlyphUnit width;
    PangoGlyphUnit xOffset;
    PangoGlyphUnit yOffset;
    alias x_offset = xOffset; // C name
    alias y_offset = yOffset; // C name
}

struct PangoGlyphVisAttr
{
    import std.bitmanip : bitfields;
    mixin(bitfields!(
        uint, "isClusterStart", 1,
        uint, "isColor", 1,
        uint, "", 30
    ));
    alias is_cluster_start = isClusterStart; // C name
    alias is_color = isColor; // C name
}

struct PangoGlyphInfo
{
    PangoGlyph glyph;
    PangoGlyphGeometry geometry;
    PangoGlyphVisAttr attr;
}

struct PangoGlyphString
{
    int numGlyphs;
    PangoGlyphInfo* glyphs;
    int* logClusters;
    int space;
    alias num_glyphs = numGlyphs; // C name
    alias log_clusters = logClusters; // C name
}

alias PangoGlyphUnit = int;
enum PangoShapeFlags
{
    NONE = 0,
    ROUND_POSITIONS = 1 << 0,
}
enum PANGO_SHAPE_NONE = PangoShapeFlags.NONE; /// ditto
enum PANGO_SHAPE_ROUND_POSITIONS = PangoShapeFlags.ROUND_POSITIONS; /// ditto

struct PangoEngine
{
    GObject parentInstance;
    alias parent_instance = parentInstance; // C name
}

struct PangoEngineClass
{
    GObjectClass parentClass;
    alias parent_class = parentClass; // C name
}

struct PangoEngineLangClass
{
    PangoEngineClass parentClass;
    extern (C) void function(PangoEngineLang* engine, const(char)* text, int len, PangoAnalysis* analysis, PangoLogAttr* attrs, int attrs_len) scriptBreak;
    alias parent_class = parentClass; // C name
    alias script_break = scriptBreak; // C name
}

struct PangoEngineShapeClass
{
    PangoEngineClass parentClass;
    extern (C) void function(PangoEngineShape* engine, PangoFont* font, const(char)* item_text, uint item_length, const(PangoAnalysis)* analysis, PangoGlyphString* glyphs, const(char)* paragraph_text, uint paragraph_length) scriptShape;
    extern (C) PangoCoverageLevel function(PangoEngineShape* engine, PangoFont* font, PangoLanguage* language, dchar wc) covers;
    alias parent_class = parentClass; // C name
    alias script_shape = scriptShape; // C name
}

struct PangoEngineInfo
{
    const(char)* id;
    const(char)* engineType;
    const(char)* renderType;
    PangoEngineScriptInfo* scripts;
    int nScripts;
    alias engine_type = engineType; // C name
    alias render_type = renderType; // C name
    alias n_scripts = nScripts; // C name
}

struct PangoEngineScriptInfo
{
    PangoScript script;
    const(char)* langs;
}

struct PangoFontsetSimple;
struct PangoFontsetSimpleClass;
struct PangoGlyphItem
{
    PangoItem* item;
    PangoGlyphString* glyphs;
    int yOffset;
    int startXOffset;
    int endXOffset;
    alias y_offset = yOffset; // C name
    alias start_x_offset = startXOffset; // C name
    alias end_x_offset = endXOffset; // C name
}

struct PangoGlyphItemIter
{
    PangoGlyphItem* glyphItem;
    const(char)* text;
    int startGlyph;
    int startIndex;
    int startChar;
    int endGlyph;
    int endIndex;
    int endChar;
    alias glyph_item = glyphItem; // C name
    alias start_glyph = startGlyph; // C name
    alias start_index = startIndex; // C name
    alias start_char = startChar; // C name
    alias end_glyph = endGlyph; // C name
    alias end_index = endIndex; // C name
    alias end_char = endChar; // C name
}

struct PangoTabArray;
enum PangoTabAlign
{
    LEFT,
    RIGHT,
    CENTER,
    DECIMAL,
}
enum PANGO_TAB_LEFT = PangoTabAlign.LEFT; /// ditto
enum PANGO_TAB_RIGHT = PangoTabAlign.RIGHT; /// ditto
enum PANGO_TAB_CENTER = PangoTabAlign.CENTER; /// ditto
enum PANGO_TAB_DECIMAL = PangoTabAlign.DECIMAL; /// ditto

struct PangoLayout;
struct PangoLayoutClass;
struct PangoLayoutLine
{
    import std.bitmanip : bitfields;
    PangoLayout* layout;
    int startIndex;
    int length;
    GSList* runs;
    mixin(bitfields!(
        uint, "isParagraphStart", 1,
        uint, "resolvedDir", 3,
        uint, "", 28
    ));
    alias start_index = startIndex; // C name
    alias is_paragraph_start = isParagraphStart; // C name
    alias resolved_dir = resolvedDir; // C name
}

alias PangoLayoutRun = PangoGlyphItem;
enum PangoAlignment
{
    LEFT,
    CENTER,
    RIGHT,
}
enum PANGO_ALIGN_LEFT = PangoAlignment.LEFT; /// ditto
enum PANGO_ALIGN_CENTER = PangoAlignment.CENTER; /// ditto
enum PANGO_ALIGN_RIGHT = PangoAlignment.RIGHT; /// ditto

enum PangoWrapMode
{
    WORD,
    CHAR,
    WORD_CHAR,
    NONE,
}
enum PANGO_WRAP_WORD = PangoWrapMode.WORD; /// ditto
enum PANGO_WRAP_CHAR = PangoWrapMode.CHAR; /// ditto
enum PANGO_WRAP_WORD_CHAR = PangoWrapMode.WORD_CHAR; /// ditto
enum PANGO_WRAP_NONE = PangoWrapMode.NONE; /// ditto

enum PangoEllipsizeMode
{
    NONE,
    START,
    MIDDLE,
    END,
}
enum PANGO_ELLIPSIZE_NONE = PangoEllipsizeMode.NONE; /// ditto
enum PANGO_ELLIPSIZE_START = PangoEllipsizeMode.START; /// ditto
enum PANGO_ELLIPSIZE_MIDDLE = PangoEllipsizeMode.MIDDLE; /// ditto
enum PANGO_ELLIPSIZE_END = PangoEllipsizeMode.END; /// ditto

enum PangoLayoutSerializeFlags
{
    DEFAULT = 0,
    CONTEXT = 1 << 0,
    OUTPUT = 1 << 1,
}
enum PANGO_LAYOUT_SERIALIZE_DEFAULT = PangoLayoutSerializeFlags.DEFAULT; /// ditto
enum PANGO_LAYOUT_SERIALIZE_CONTEXT = PangoLayoutSerializeFlags.CONTEXT; /// ditto
enum PANGO_LAYOUT_SERIALIZE_OUTPUT = PangoLayoutSerializeFlags.OUTPUT; /// ditto

enum PangoLayoutDeserializeError
{
    INVALID,
    INVALID_VALUE,
    MISSING_VALUE,
}
enum PANGO_LAYOUT_DESERIALIZE_INVALID = PangoLayoutDeserializeError.INVALID; /// ditto
enum PANGO_LAYOUT_DESERIALIZE_INVALID_VALUE = PangoLayoutDeserializeError.INVALID_VALUE; /// ditto
enum PANGO_LAYOUT_DESERIALIZE_MISSING_VALUE = PangoLayoutDeserializeError.MISSING_VALUE; /// ditto

enum PangoLayoutDeserializeFlags
{
    DEFAULT = 0,
    CONTEXT = 1 << 0,
}
enum PANGO_LAYOUT_DESERIALIZE_DEFAULT = PangoLayoutDeserializeFlags.DEFAULT; /// ditto
enum PANGO_LAYOUT_DESERIALIZE_CONTEXT = PangoLayoutDeserializeFlags.CONTEXT; /// ditto

struct PangoLayoutIter;
struct PangoRenderer
{
    GObject parentInstance;
    PangoUnderline underline;
    int strikethrough;
    int activeCount;
    PangoMatrix* matrix;
    PangoRendererPrivate* priv;
    alias parent_instance = parentInstance; // C name
    alias active_count = activeCount; // C name
}

struct PangoRendererClass
{
    GObjectClass parentClass;
    extern (C) void function(PangoRenderer* renderer, PangoFont* font, PangoGlyphString* glyphs, int x, int y) drawGlyphs;
    extern (C) void function(PangoRenderer* renderer, PangoRenderPart part, int x, int y, int width, int height) drawRectangle;
    extern (C) void function(PangoRenderer* renderer, int x, int y, int width, int height) drawErrorUnderline;
    extern (C) void function(PangoRenderer* renderer, PangoAttrShape* attr, int x, int y) drawShape;
    extern (C) void function(PangoRenderer* renderer, PangoRenderPart part, double y1_, double x11, double x21, double y2, double x12, double x22) drawTrapezoid;
    extern (C) void function(PangoRenderer* renderer, PangoFont* font, PangoGlyph glyph, double x, double y) drawGlyph;
    extern (C) void function(PangoRenderer* renderer, PangoRenderPart part) partChanged;
    extern (C) void function(PangoRenderer* renderer) begin;
    extern (C) void function(PangoRenderer* renderer) end;
    extern (C) void function(PangoRenderer* renderer, PangoLayoutRun* run) prepareRun;
    extern (C) void function(PangoRenderer* renderer, const(char)* text, PangoGlyphItem* glyph_item, int x, int y) drawGlyphItem;
    extern (C) void function() PangoReserved2;
    extern (C) void function() PangoReserved3;
    extern (C) void function() PangoReserved4;
    alias parent_class = parentClass; // C name
    alias draw_glyphs = drawGlyphs; // C name
    alias draw_rectangle = drawRectangle; // C name
    alias draw_error_underline = drawErrorUnderline; // C name
    alias draw_shape = drawShape; // C name
    alias draw_trapezoid = drawTrapezoid; // C name
    alias draw_glyph = drawGlyph; // C name
    alias part_changed = partChanged; // C name
    alias prepare_run = prepareRun; // C name
    alias draw_glyph_item = drawGlyphItem; // C name
    alias _pango_reserved2 = PangoReserved2; // C name
    alias _pango_reserved3 = PangoReserved3; // C name
    alias _pango_reserved4 = PangoReserved4; // C name
}

struct PangoRendererPrivate;
enum PangoRenderPart
{
    FOREGROUND,
    BACKGROUND,
    UNDERLINE,
    STRIKETHROUGH,
    OVERLINE,
}
enum PANGO_RENDER_PART_FOREGROUND = PangoRenderPart.FOREGROUND; /// ditto
enum PANGO_RENDER_PART_BACKGROUND = PangoRenderPart.BACKGROUND; /// ditto
enum PANGO_RENDER_PART_UNDERLINE = PangoRenderPart.UNDERLINE; /// ditto
enum PANGO_RENDER_PART_STRIKETHROUGH = PangoRenderPart.STRIKETHROUGH; /// ditto
enum PANGO_RENDER_PART_OVERLINE = PangoRenderPart.OVERLINE; /// ditto

extern (C) nothrow @nogc
{
    GType pango_coverage_get_type();
    PangoCoverage* pango_coverage_new();
    deprecated("Use 'g_object_ref' instead") PangoCoverage* pango_coverage_ref(PangoCoverage* coverage);
    deprecated("Use 'g_object_unref' instead") void pango_coverage_unref(PangoCoverage* coverage);
    PangoCoverage* pango_coverage_copy(PangoCoverage* coverage);
    PangoCoverageLevel pango_coverage_get(PangoCoverage* coverage, int index_);
    void pango_coverage_set(PangoCoverage* coverage, int index_, PangoCoverageLevel level);
    deprecated void pango_coverage_max(PangoCoverage* coverage, PangoCoverage* other);
    deprecated void pango_coverage_to_bytes(PangoCoverage* coverage, ubyte** bytes, int* n_bytes);
    deprecated PangoCoverage* pango_coverage_from_bytes(ubyte* bytes, int n_bytes);
    int pango_units_from_double(double d);
    double pango_units_to_double(int i);
    void pango_extents_to_pixels(PangoRectangle* inclusive, PangoRectangle* nearest);
    GType pango_matrix_get_type();
    PangoMatrix* pango_matrix_copy(const(PangoMatrix)* matrix);
    void pango_matrix_free(PangoMatrix* matrix);
    void pango_matrix_translate(PangoMatrix* matrix, double tx, double ty);
    void pango_matrix_scale(PangoMatrix* matrix, double scale_x, double scale_y);
    void pango_matrix_rotate(PangoMatrix* matrix, double degrees);
    void pango_matrix_concat(PangoMatrix* matrix, const(PangoMatrix)* new_matrix);
    void pango_matrix_transform_point(const(PangoMatrix)* matrix, double* x, double* y);
    void pango_matrix_transform_distance(const(PangoMatrix)* matrix, double* dx, double* dy);
    void pango_matrix_transform_rectangle(const(PangoMatrix)* matrix, PangoRectangle* rect);
    void pango_matrix_transform_pixel_rectangle(const(PangoMatrix)* matrix, PangoRectangle* rect);
    double pango_matrix_get_font_scale_factor(const(PangoMatrix)* matrix);
    void pango_matrix_get_font_scale_factors(const(PangoMatrix)* matrix, double* xscale, double* yscale);
    double pango_matrix_get_slant_ratio(const(PangoMatrix)* matrix);
    deprecated("Use 'g_unichar_get_script' instead") PangoScript pango_script_for_unichar(dchar ch);
    GType pango_script_iter_get_type();
    PangoScriptIter* pango_script_iter_new(const(char)* text, int length);
    void pango_script_iter_get_range(PangoScriptIter* iter, const(char)** start, const(char)** end, PangoScript* script);
    int pango_script_iter_next(PangoScriptIter* iter);
    void pango_script_iter_free(PangoScriptIter* iter);
    GType pango_language_get_type();
    PangoLanguage* pango_language_get_default();
    PangoLanguage** pango_language_get_preferred();
    PangoLanguage* pango_language_from_string(const(char)* language);
    const(char)* pango_language_to_string(PangoLanguage* language);
    const(char)* pango_language_get_sample_string(PangoLanguage* language);
    int pango_language_matches(PangoLanguage* language, const(char)* range_list);
    int pango_language_includes_script(PangoLanguage* language, PangoScript script);
    const(PangoScript)* pango_language_get_scripts(PangoLanguage* language, int* num_scripts);
    PangoLanguage* pango_script_get_sample_language(PangoScript script);
    double pango_gravity_to_rotation(PangoGravity gravity);
    PangoGravity pango_gravity_get_for_matrix(const(PangoMatrix)* matrix);
    PangoGravity pango_gravity_get_for_script(PangoScript script, PangoGravity base_gravity, PangoGravityHint hint);
    PangoGravity pango_gravity_get_for_script_and_width(PangoScript script, int wide, PangoGravity base_gravity, PangoGravityHint hint);
    deprecated PangoBidiType pango_bidi_type_for_unichar(dchar ch);
    deprecated PangoDirection pango_unichar_direction(dchar ch);
    deprecated PangoDirection pango_find_base_dir(const(char)* text, int length);
    deprecated("Use 'g_unichar_get_mirror_char' instead") int pango_get_mirror_char(dchar ch, dchar* mirrored_ch);
    GType pango_font_description_get_type();
    PangoFontDescription* pango_font_description_new();
    PangoFontDescription* pango_font_description_copy(const(PangoFontDescription)* desc);
    PangoFontDescription* pango_font_description_copy_static(const(PangoFontDescription)* desc);
    uint pango_font_description_hash(const(PangoFontDescription)* desc);
    int pango_font_description_equal(const(PangoFontDescription)* desc1, const(PangoFontDescription)* desc2);
    void pango_font_description_free(PangoFontDescription* desc);
    deprecated void pango_font_descriptions_free(PangoFontDescription** descs, int n_descs);
    void pango_font_description_set_family(PangoFontDescription* desc, const(char)* family);
    void pango_font_description_set_family_static(PangoFontDescription* desc, const(char)* family);
    const(char)* pango_font_description_get_family(const(PangoFontDescription)* desc);
    void pango_font_description_set_style(PangoFontDescription* desc, PangoStyle style);
    PangoStyle pango_font_description_get_style(const(PangoFontDescription)* desc);
    void pango_font_description_set_variant(PangoFontDescription* desc, PangoVariant variant);
    PangoVariant pango_font_description_get_variant(const(PangoFontDescription)* desc);
    void pango_font_description_set_weight(PangoFontDescription* desc, PangoWeight weight);
    PangoWeight pango_font_description_get_weight(const(PangoFontDescription)* desc);
    void pango_font_description_set_stretch(PangoFontDescription* desc, PangoStretch stretch);
    PangoStretch pango_font_description_get_stretch(const(PangoFontDescription)* desc);
    void pango_font_description_set_size(PangoFontDescription* desc, int size);
    int pango_font_description_get_size(const(PangoFontDescription)* desc);
    void pango_font_description_set_absolute_size(PangoFontDescription* desc, double size);
    int pango_font_description_get_size_is_absolute(const(PangoFontDescription)* desc);
    void pango_font_description_set_gravity(PangoFontDescription* desc, PangoGravity gravity);
    PangoGravity pango_font_description_get_gravity(const(PangoFontDescription)* desc);
    void pango_font_description_set_variations_static(PangoFontDescription* desc, const(char)* variations);
    void pango_font_description_set_variations(PangoFontDescription* desc, const(char)* variations);
    const(char)* pango_font_description_get_variations(const(PangoFontDescription)* desc);
    void pango_font_description_set_features_static(PangoFontDescription* desc, const(char)* features);
    void pango_font_description_set_features(PangoFontDescription* desc, const(char)* features);
    const(char)* pango_font_description_get_features(const(PangoFontDescription)* desc);
    void pango_font_description_set_color(PangoFontDescription* desc, PangoFontColor color);
    PangoFontColor pango_font_description_get_color(const(PangoFontDescription)* desc);
    PangoFontMask pango_font_description_get_set_fields(const(PangoFontDescription)* desc);
    void pango_font_description_unset_fields(PangoFontDescription* desc, PangoFontMask to_unset);
    void pango_font_description_merge(PangoFontDescription* desc, const(PangoFontDescription)* desc_to_merge, int replace_existing);
    void pango_font_description_merge_static(PangoFontDescription* desc, const(PangoFontDescription)* desc_to_merge, int replace_existing);
    int pango_font_description_better_match(const(PangoFontDescription)* desc, const(PangoFontDescription)* old_match, const(PangoFontDescription)* new_match);
    PangoFontDescription* pango_font_description_from_string(const(char)* str);
    char* pango_font_description_to_string(const(PangoFontDescription)* desc);
    char* pango_font_description_to_filename(const(PangoFontDescription)* desc);
    GType pango_font_metrics_get_type();
    PangoFontMetrics* pango_font_metrics_ref(PangoFontMetrics* metrics);
    void pango_font_metrics_unref(PangoFontMetrics* metrics);
    int pango_font_metrics_get_ascent(PangoFontMetrics* metrics);
    int pango_font_metrics_get_descent(PangoFontMetrics* metrics);
    int pango_font_metrics_get_height(PangoFontMetrics* metrics);
    int pango_font_metrics_get_approximate_char_width(PangoFontMetrics* metrics);
    int pango_font_metrics_get_approximate_digit_width(PangoFontMetrics* metrics);
    int pango_font_metrics_get_underline_position(PangoFontMetrics* metrics);
    int pango_font_metrics_get_underline_thickness(PangoFontMetrics* metrics);
    int pango_font_metrics_get_strikethrough_position(PangoFontMetrics* metrics);
    int pango_font_metrics_get_strikethrough_thickness(PangoFontMetrics* metrics);
    GType pango_font_family_get_type();
    void pango_font_family_list_faces(PangoFontFamily* family, PangoFontFace*** faces, int* n_faces);
    const(char)* pango_font_family_get_name(PangoFontFamily* family);
    int pango_font_family_is_monospace(PangoFontFamily* family);
    int pango_font_family_is_variable(PangoFontFamily* family);
    PangoFontFace* pango_font_family_get_face(PangoFontFamily* family, const(char)* name);
    GType pango_font_face_get_type();
    PangoFontDescription* pango_font_face_describe(PangoFontFace* face);
    const(char)* pango_font_face_get_face_name(PangoFontFace* face);
    void pango_font_face_list_sizes(PangoFontFace* face, int** sizes, int* n_sizes);
    int pango_font_face_is_synthesized(PangoFontFace* face);
    PangoFontFamily* pango_font_face_get_family(PangoFontFace* face);
    GType pango_font_get_type();
    PangoFontDescription* pango_font_describe(PangoFont* font);
    PangoFontDescription* pango_font_describe_with_absolute_size(PangoFont* font);
    PangoCoverage* pango_font_get_coverage(PangoFont* font, PangoLanguage* language);
    deprecated PangoEngineShape* pango_font_find_shaper(PangoFont* font, PangoLanguage* language, uint ch);
    PangoFontMetrics* pango_font_get_metrics(PangoFont* font, PangoLanguage* language);
    void pango_font_get_glyph_extents(PangoFont* font, PangoGlyph glyph, PangoRectangle* ink_rect, PangoRectangle* logical_rect);
    PangoFontMap* pango_font_get_font_map(PangoFont* font);
    PangoFontFace* pango_font_get_face(PangoFont* font);
    int pango_font_has_char(PangoFont* font, dchar wc);
    void pango_font_get_features(PangoFont* font, hb_feature_t* features, uint len, uint* num_features);
    hb_font_t* pango_font_get_hb_font(PangoFont* font);
    PangoLanguage** pango_font_get_languages(PangoFont* font);
    GBytes* pango_font_serialize(PangoFont* font);
    PangoFont* pango_font_deserialize(PangoContext* context, GBytes* bytes, GError** error);
    GType pango_color_get_type();
    PangoColor* pango_color_copy(const(PangoColor)* src);
    void pango_color_free(PangoColor* color);
    int pango_color_parse(PangoColor* color, const(char)* spec);
    int pango_color_parse_with_alpha(PangoColor* color, ushort* alpha, const(char)* spec);
    char* pango_color_to_string(const(PangoColor)* color);
    GType pango_attribute_get_type();
    PangoAttrType pango_attr_type_register(const(char)* name);
    const(char)* pango_attr_type_get_name(PangoAttrType type);
    void pango_attribute_init(PangoAttribute* attr, const(PangoAttrClass)* klass);
    PangoAttribute* pango_attribute_copy(const(PangoAttribute)* attr);
    void pango_attribute_destroy(PangoAttribute* attr);
    int pango_attribute_equal(const(PangoAttribute)* attr1, const(PangoAttribute)* attr2);
    PangoAttribute* pango_attr_language_new(PangoLanguage* language);
    PangoAttribute* pango_attr_family_new(const(char)* family);
    PangoAttribute* pango_attr_foreground_new(ushort red, ushort green, ushort blue);
    PangoAttribute* pango_attr_background_new(ushort red, ushort green, ushort blue);
    PangoAttribute* pango_attr_size_new(int size);
    PangoAttribute* pango_attr_size_new_absolute(int size);
    PangoAttribute* pango_attr_style_new(PangoStyle style);
    PangoAttribute* pango_attr_weight_new(PangoWeight weight);
    PangoAttribute* pango_attr_variant_new(PangoVariant variant);
    PangoAttribute* pango_attr_stretch_new(PangoStretch stretch);
    PangoAttribute* pango_attr_font_desc_new(const(PangoFontDescription)* desc);
    PangoAttribute* pango_attr_underline_new(PangoUnderline underline);
    PangoAttribute* pango_attr_underline_color_new(ushort red, ushort green, ushort blue);
    PangoAttribute* pango_attr_strikethrough_new(int strikethrough);
    PangoAttribute* pango_attr_strikethrough_color_new(ushort red, ushort green, ushort blue);
    PangoAttribute* pango_attr_rise_new(int rise);
    PangoAttribute* pango_attr_baseline_shift_new(int shift);
    PangoAttribute* pango_attr_font_scale_new(PangoFontScale scale);
    PangoAttribute* pango_attr_scale_new(double scale_factor);
    PangoAttribute* pango_attr_fallback_new(int enable_fallback);
    PangoAttribute* pango_attr_letter_spacing_new(int letter_spacing);
    PangoAttribute* pango_attr_shape_new(const(PangoRectangle)* ink_rect, const(PangoRectangle)* logical_rect);
    PangoAttribute* pango_attr_shape_new_with_data(const(PangoRectangle)* ink_rect, const(PangoRectangle)* logical_rect, void* data, PangoAttrDataCopyFunc copy_func, GDestroyNotify destroy_func);
    PangoAttribute* pango_attr_gravity_new(PangoGravity gravity);
    PangoAttribute* pango_attr_gravity_hint_new(PangoGravityHint hint);
    PangoAttribute* pango_attr_font_features_new(const(char)* features);
    PangoAttribute* pango_attr_foreground_alpha_new(ushort alpha);
    PangoAttribute* pango_attr_background_alpha_new(ushort alpha);
    PangoAttribute* pango_attr_allow_breaks_new(int allow_breaks);
    PangoAttribute* pango_attr_word_new();
    PangoAttribute* pango_attr_sentence_new();
    PangoAttribute* pango_attr_insert_hyphens_new(int insert_hyphens);
    PangoAttribute* pango_attr_overline_new(PangoOverline overline);
    PangoAttribute* pango_attr_overline_color_new(ushort red, ushort green, ushort blue);
    PangoAttribute* pango_attr_show_new(PangoShowFlags flags);
    PangoAttribute* pango_attr_line_height_new(double factor);
    PangoAttribute* pango_attr_line_height_new_absolute(int height);
    PangoAttribute* pango_attr_text_transform_new(PangoTextTransform transform);
    PangoAttrString* pango_attribute_as_string(PangoAttribute* attr);
    PangoAttrLanguage* pango_attribute_as_language(PangoAttribute* attr);
    PangoAttrInt* pango_attribute_as_int(PangoAttribute* attr);
    PangoAttrSize* pango_attribute_as_size(PangoAttribute* attr);
    PangoAttrFloat* pango_attribute_as_float(PangoAttribute* attr);
    PangoAttrColor* pango_attribute_as_color(PangoAttribute* attr);
    PangoAttrFontDesc* pango_attribute_as_font_desc(PangoAttribute* attr);
    PangoAttrShape* pango_attribute_as_shape(PangoAttribute* attr);
    PangoAttrFontFeatures* pango_attribute_as_font_features(PangoAttribute* attr);
    GType pango_attr_list_get_type();
    PangoAttrList* pango_attr_list_new();
    PangoAttrList* pango_attr_list_ref(PangoAttrList* list);
    void pango_attr_list_unref(PangoAttrList* list);
    PangoAttrList* pango_attr_list_copy(PangoAttrList* list);
    void pango_attr_list_insert(PangoAttrList* list, PangoAttribute* attr);
    void pango_attr_list_insert_before(PangoAttrList* list, PangoAttribute* attr);
    void pango_attr_list_change(PangoAttrList* list, PangoAttribute* attr);
    void pango_attr_list_splice(PangoAttrList* list, PangoAttrList* other, int pos, int len);
    void pango_attr_list_update(PangoAttrList* list, int pos, int remove, int add);
    PangoAttrList* pango_attr_list_filter(PangoAttrList* list, PangoAttrFilterFunc func, void* data);
    GSList* pango_attr_list_get_attributes(PangoAttrList* list);
    int pango_attr_list_equal(PangoAttrList* list, PangoAttrList* other_list);
    char* pango_attr_list_to_string(PangoAttrList* list);
    PangoAttrList* pango_attr_list_from_string(const(char)* text);
    GType pango_attr_iterator_get_type();
    PangoAttrIterator* pango_attr_list_get_iterator(PangoAttrList* list);
    void pango_attr_iterator_range(PangoAttrIterator* iterator, int* start, int* end);
    int pango_attr_iterator_next(PangoAttrIterator* iterator);
    PangoAttrIterator* pango_attr_iterator_copy(PangoAttrIterator* iterator);
    void pango_attr_iterator_destroy(PangoAttrIterator* iterator);
    PangoAttribute* pango_attr_iterator_get(PangoAttrIterator* iterator, PangoAttrType type);
    void pango_attr_iterator_get_font(PangoAttrIterator* iterator, PangoFontDescription* desc, PangoLanguage** language, GSList** extra_attrs);
    GSList* pango_attr_iterator_get_attrs(PangoAttrIterator* iterator);
    GType pango_item_get_type();
    PangoItem* pango_item_new();
    PangoItem* pango_item_copy(PangoItem* item);
    void pango_item_free(PangoItem* item);
    int pango_item_get_char_offset(PangoItem* item);
    PangoItem* pango_item_split(PangoItem* orig, int split_index, int split_offset);
    void pango_item_apply_attrs(PangoItem* item, PangoAttrIterator* iter);
    GList* pango_reorder_items(GList* items);
    GList* pango_itemize(PangoContext* context, const(char)* text, int start_index, int length, PangoAttrList* attrs, PangoAttrIterator* cached_iter);
    GList* pango_itemize_with_base_dir(PangoContext* context, PangoDirection base_dir, const(char)* text, int start_index, int length, PangoAttrList* attrs, PangoAttrIterator* cached_iter);
    deprecated void pango_break(const(char)* text, int length, PangoAnalysis* analysis, PangoLogAttr* attrs, int attrs_len);
    void pango_get_log_attrs(const(char)* text, int length, int level, PangoLanguage* language, PangoLogAttr* attrs, int attrs_len);
    void pango_default_break(const(char)* text, int length, PangoAnalysis* analysis, PangoLogAttr* attrs, int attrs_len);
    void pango_tailor_break(const(char)* text, int length, PangoAnalysis* analysis, int offset, PangoLogAttr* attrs, int attrs_len);
    void pango_attr_break(const(char)* text, int length, PangoAttrList* attr_list, int offset, PangoLogAttr* attrs, int attrs_len);
    GType pango_fontset_get_type();
    PangoFont* pango_fontset_get_font(PangoFontset* fontset, uint wc);
    PangoFontMetrics* pango_fontset_get_metrics(PangoFontset* fontset);
    void pango_fontset_foreach(PangoFontset* fontset, PangoFontsetForeachFunc func, void* data);
    GType pango_font_map_get_type();
    PangoContext* pango_font_map_create_context(PangoFontMap* fontmap);
    PangoFont* pango_font_map_load_font(PangoFontMap* fontmap, PangoContext* context, const(PangoFontDescription)* desc);
    PangoFontset* pango_font_map_load_fontset(PangoFontMap* fontmap, PangoContext* context, const(PangoFontDescription)* desc, PangoLanguage* language);
    void pango_font_map_list_families(PangoFontMap* fontmap, PangoFontFamily*** families, int* n_families);
    uint pango_font_map_get_serial(PangoFontMap* fontmap);
    void pango_font_map_changed(PangoFontMap* fontmap);
    PangoFontFamily* pango_font_map_get_family(PangoFontMap* fontmap, const(char)* name);
    PangoFont* pango_font_map_reload_font(PangoFontMap* fontmap, PangoFont* font, double scale, PangoContext* context, const(char)* variations);
    int pango_font_map_add_font_file(PangoFontMap* fontmap, const(char)* filename, GError** error);
    GType pango_context_get_type();
    PangoContext* pango_context_new();
    void pango_context_changed(PangoContext* context);
    void pango_context_set_font_map(PangoContext* context, PangoFontMap* font_map);
    PangoFontMap* pango_context_get_font_map(PangoContext* context);
    uint pango_context_get_serial(PangoContext* context);
    void pango_context_list_families(PangoContext* context, PangoFontFamily*** families, int* n_families);
    PangoFont* pango_context_load_font(PangoContext* context, const(PangoFontDescription)* desc);
    PangoFontset* pango_context_load_fontset(PangoContext* context, const(PangoFontDescription)* desc, PangoLanguage* language);
    PangoFontMetrics* pango_context_get_metrics(PangoContext* context, const(PangoFontDescription)* desc, PangoLanguage* language);
    void pango_context_set_font_description(PangoContext* context, const(PangoFontDescription)* desc);
    PangoFontDescription* pango_context_get_font_description(PangoContext* context);
    PangoLanguage* pango_context_get_language(PangoContext* context);
    void pango_context_set_language(PangoContext* context, PangoLanguage* language);
    void pango_context_set_base_dir(PangoContext* context, PangoDirection direction);
    PangoDirection pango_context_get_base_dir(PangoContext* context);
    void pango_context_set_base_gravity(PangoContext* context, PangoGravity gravity);
    PangoGravity pango_context_get_base_gravity(PangoContext* context);
    PangoGravity pango_context_get_gravity(PangoContext* context);
    void pango_context_set_gravity_hint(PangoContext* context, PangoGravityHint hint);
    PangoGravityHint pango_context_get_gravity_hint(PangoContext* context);
    void pango_context_set_matrix(PangoContext* context, const(PangoMatrix)* matrix);
    const(PangoMatrix)* pango_context_get_matrix(PangoContext* context);
    void pango_context_set_round_glyph_positions(PangoContext* context, int round_positions);
    int pango_context_get_round_glyph_positions(PangoContext* context);
    GType pango_glyph_string_get_type();
    PangoGlyphString* pango_glyph_string_new();
    void pango_glyph_string_set_size(PangoGlyphString* string, int new_len);
    PangoGlyphString* pango_glyph_string_copy(PangoGlyphString* string);
    void pango_glyph_string_free(PangoGlyphString* string);
    void pango_glyph_string_extents(PangoGlyphString* glyphs, PangoFont* font, PangoRectangle* ink_rect, PangoRectangle* logical_rect);
    int pango_glyph_string_get_width(PangoGlyphString* glyphs);
    void pango_glyph_string_extents_range(PangoGlyphString* glyphs, int start, int end, PangoFont* font, PangoRectangle* ink_rect, PangoRectangle* logical_rect);
    void pango_glyph_string_get_logical_widths(PangoGlyphString* glyphs, const(char)* text, int length, int embedding_level, int* logical_widths);
    void pango_glyph_string_index_to_x(PangoGlyphString* glyphs, const(char)* text, int length, PangoAnalysis* analysis, int index_, int trailing, int* x_pos);
    void pango_glyph_string_x_to_index(PangoGlyphString* glyphs, const(char)* text, int length, PangoAnalysis* analysis, int x_pos, int* index_, int* trailing);
    void pango_glyph_string_index_to_x_full(PangoGlyphString* glyphs, const(char)* text, int length, PangoAnalysis* analysis, PangoLogAttr* attrs, int index_, int trailing, int* x_pos);
    void pango_shape(const(char)* text, int length, const(PangoAnalysis)* analysis, PangoGlyphString* glyphs);
    void pango_shape_full(const(char)* item_text, int item_length, const(char)* paragraph_text, int paragraph_length, const(PangoAnalysis)* analysis, PangoGlyphString* glyphs);
    void pango_shape_with_flags(const(char)* item_text, int item_length, const(char)* paragraph_text, int paragraph_length, const(PangoAnalysis)* analysis, PangoGlyphString* glyphs, PangoShapeFlags flags);
    void pango_shape_item(PangoItem* item, const(char)* paragraph_text, int paragraph_length, PangoLogAttr* log_attrs, PangoGlyphString* glyphs, PangoShapeFlags flags);
    deprecated GType pango_engine_get_type();
    deprecated GType pango_engine_lang_get_type();
    deprecated GType pango_engine_shape_get_type();
    GType pango_attr_type_get_type();
    GType pango_underline_get_type();
    GType pango_overline_get_type();
    GType pango_show_flags_get_type();
    GType pango_text_transform_get_type();
    GType pango_baseline_shift_get_type();
    GType pango_font_scale_get_type();
    GType pango_bidi_type_get_type();
    GType pango_coverage_level_get_type();
    GType pango_direction_get_type();
    GType pango_style_get_type();
    GType pango_variant_get_type();
    GType pango_weight_get_type();
    GType pango_stretch_get_type();
    GType pango_font_mask_get_type();
    GType pango_font_color_get_type();
    GType pango_shape_flags_get_type();
    GType pango_gravity_get_type();
    GType pango_gravity_hint_get_type();
    GType pango_alignment_get_type();
    GType pango_wrap_mode_get_type();
    GType pango_ellipsize_mode_get_type();
    GType pango_layout_serialize_flags_get_type();
    GType pango_layout_deserialize_error_get_type();
    GType pango_layout_deserialize_flags_get_type();
    GType pango_render_part_get_type();
    GType pango_script_get_type();
    GType pango_tab_align_get_type();
    GType pango_fontset_simple_get_type();
    PangoFontsetSimple* pango_fontset_simple_new(PangoLanguage* language);
    void pango_fontset_simple_append(PangoFontsetSimple* fontset, PangoFont* font);
    int pango_fontset_simple_size(PangoFontsetSimple* fontset);
    GType pango_glyph_item_get_type();
    PangoGlyphItem* pango_glyph_item_split(PangoGlyphItem* orig, const(char)* text, int split_index);
    PangoGlyphItem* pango_glyph_item_copy(PangoGlyphItem* orig);
    void pango_glyph_item_free(PangoGlyphItem* glyph_item);
    GSList* pango_glyph_item_apply_attrs(PangoGlyphItem* glyph_item, const(char)* text, PangoAttrList* list);
    void pango_glyph_item_letter_space(PangoGlyphItem* glyph_item, const(char)* text, PangoLogAttr* log_attrs, int letter_spacing);
    void pango_glyph_item_get_logical_widths(PangoGlyphItem* glyph_item, const(char)* text, int* logical_widths);
    GType pango_glyph_item_iter_get_type();
    PangoGlyphItemIter* pango_glyph_item_iter_copy(PangoGlyphItemIter* orig);
    void pango_glyph_item_iter_free(PangoGlyphItemIter* iter);
    int pango_glyph_item_iter_init_start(PangoGlyphItemIter* iter, PangoGlyphItem* glyph_item, const(char)* text);
    int pango_glyph_item_iter_init_end(PangoGlyphItemIter* iter, PangoGlyphItem* glyph_item, const(char)* text);
    int pango_glyph_item_iter_next_cluster(PangoGlyphItemIter* iter);
    int pango_glyph_item_iter_prev_cluster(PangoGlyphItemIter* iter);
    PangoTabArray* pango_tab_array_new(int initial_size, int positions_in_pixels);
    PangoTabArray* pango_tab_array_new_with_positions(int size, int positions_in_pixels, PangoTabAlign first_alignment, int first_position, ...);
    GType pango_tab_array_get_type();
    PangoTabArray* pango_tab_array_copy(PangoTabArray* src);
    void pango_tab_array_free(PangoTabArray* tab_array);
    int pango_tab_array_get_size(PangoTabArray* tab_array);
    void pango_tab_array_resize(PangoTabArray* tab_array, int new_size);
    void pango_tab_array_set_tab(PangoTabArray* tab_array, int tab_index, PangoTabAlign alignment, int location);
    void pango_tab_array_get_tab(PangoTabArray* tab_array, int tab_index, PangoTabAlign* alignment, int* location);
    void pango_tab_array_get_tabs(PangoTabArray* tab_array, PangoTabAlign** alignments, int** locations);
    int pango_tab_array_get_positions_in_pixels(PangoTabArray* tab_array);
    void pango_tab_array_set_positions_in_pixels(PangoTabArray* tab_array, int positions_in_pixels);
    char* pango_tab_array_to_string(PangoTabArray* tab_array);
    PangoTabArray* pango_tab_array_from_string(const(char)* text);
    void pango_tab_array_set_decimal_point(PangoTabArray* tab_array, int tab_index, dchar decimal_point);
    dchar pango_tab_array_get_decimal_point(PangoTabArray* tab_array, int tab_index);
    void pango_tab_array_sort(PangoTabArray* tab_array);
    GType pango_layout_get_type();
    PangoLayout* pango_layout_new(PangoContext* context);
    PangoLayout* pango_layout_copy(PangoLayout* src);
    PangoContext* pango_layout_get_context(PangoLayout* layout);
    void pango_layout_set_attributes(PangoLayout* layout, PangoAttrList* attrs);
    PangoAttrList* pango_layout_get_attributes(PangoLayout* layout);
    void pango_layout_set_text(PangoLayout* layout, const(char)* text, int length);
    const(char)* pango_layout_get_text(PangoLayout* layout);
    int pango_layout_get_character_count(PangoLayout* layout);
    void pango_layout_set_markup(PangoLayout* layout, const(char)* markup, int length);
    void pango_layout_set_markup_with_accel(PangoLayout* layout, const(char)* markup, int length, dchar accel_marker, dchar* accel_char);
    void pango_layout_set_font_description(PangoLayout* layout, const(PangoFontDescription)* desc);
    const(PangoFontDescription)* pango_layout_get_font_description(PangoLayout* layout);
    void pango_layout_set_width(PangoLayout* layout, int width);
    int pango_layout_get_width(PangoLayout* layout);
    void pango_layout_set_height(PangoLayout* layout, int height);
    int pango_layout_get_height(PangoLayout* layout);
    void pango_layout_set_wrap(PangoLayout* layout, PangoWrapMode wrap);
    PangoWrapMode pango_layout_get_wrap(PangoLayout* layout);
    int pango_layout_is_wrapped(PangoLayout* layout);
    void pango_layout_set_indent(PangoLayout* layout, int indent);
    int pango_layout_get_indent(PangoLayout* layout);
    void pango_layout_set_spacing(PangoLayout* layout, int spacing);
    int pango_layout_get_spacing(PangoLayout* layout);
    void pango_layout_set_line_spacing(PangoLayout* layout, float factor);
    float pango_layout_get_line_spacing(PangoLayout* layout);
    void pango_layout_set_justify(PangoLayout* layout, int justify);
    int pango_layout_get_justify(PangoLayout* layout);
    void pango_layout_set_justify_last_line(PangoLayout* layout, int justify);
    int pango_layout_get_justify_last_line(PangoLayout* layout);
    void pango_layout_set_auto_dir(PangoLayout* layout, int auto_dir);
    int pango_layout_get_auto_dir(PangoLayout* layout);
    void pango_layout_set_alignment(PangoLayout* layout, PangoAlignment alignment);
    PangoAlignment pango_layout_get_alignment(PangoLayout* layout);
    void pango_layout_set_tabs(PangoLayout* layout, PangoTabArray* tabs);
    PangoTabArray* pango_layout_get_tabs(PangoLayout* layout);
    void pango_layout_set_single_paragraph_mode(PangoLayout* layout, int setting);
    int pango_layout_get_single_paragraph_mode(PangoLayout* layout);
    void pango_layout_set_ellipsize(PangoLayout* layout, PangoEllipsizeMode ellipsize);
    PangoEllipsizeMode pango_layout_get_ellipsize(PangoLayout* layout);
    int pango_layout_is_ellipsized(PangoLayout* layout);
    int pango_layout_get_unknown_glyphs_count(PangoLayout* layout);
    PangoDirection pango_layout_get_direction(PangoLayout* layout, int index);
    void pango_layout_context_changed(PangoLayout* layout);
    uint pango_layout_get_serial(PangoLayout* layout);
    void pango_layout_get_log_attrs(PangoLayout* layout, PangoLogAttr** attrs, int* n_attrs);
    const(PangoLogAttr)* pango_layout_get_log_attrs_readonly(PangoLayout* layout, int* n_attrs);
    void pango_layout_index_to_pos(PangoLayout* layout, int index_, PangoRectangle* pos);
    void pango_layout_index_to_line_x(PangoLayout* layout, int index_, int trailing, int* line, int* x_pos);
    void pango_layout_get_cursor_pos(PangoLayout* layout, int index_, PangoRectangle* strong_pos, PangoRectangle* weak_pos);
    void pango_layout_get_caret_pos(PangoLayout* layout, int index_, PangoRectangle* strong_pos, PangoRectangle* weak_pos);
    void pango_layout_move_cursor_visually(PangoLayout* layout, int strong, int old_index, int old_trailing, int direction, int* new_index, int* new_trailing);
    int pango_layout_xy_to_index(PangoLayout* layout, int x, int y, int* index_, int* trailing);
    void pango_layout_get_extents(PangoLayout* layout, PangoRectangle* ink_rect, PangoRectangle* logical_rect);
    void pango_layout_get_pixel_extents(PangoLayout* layout, PangoRectangle* ink_rect, PangoRectangle* logical_rect);
    void pango_layout_get_size(PangoLayout* layout, int* width, int* height);
    void pango_layout_get_pixel_size(PangoLayout* layout, int* width, int* height);
    int pango_layout_get_baseline(PangoLayout* layout);
    int pango_layout_get_line_count(PangoLayout* layout);
    PangoLayoutLine* pango_layout_get_line(PangoLayout* layout, int line);
    PangoLayoutLine* pango_layout_get_line_readonly(PangoLayout* layout, int line);
    GSList* pango_layout_get_lines(PangoLayout* layout);
    GSList* pango_layout_get_lines_readonly(PangoLayout* layout);
    GBytes* pango_layout_serialize(PangoLayout* layout, PangoLayoutSerializeFlags flags);
    int pango_layout_write_to_file(PangoLayout* layout, PangoLayoutSerializeFlags flags, const(char)* filename, GError** error);
    GQuark pango_layout_deserialize_error_quark();
    PangoLayout* pango_layout_deserialize(PangoContext* context, GBytes* bytes, PangoLayoutDeserializeFlags flags, GError** error);
    GType pango_layout_line_get_type();
    PangoLayoutLine* pango_layout_line_ref(PangoLayoutLine* line);
    void pango_layout_line_unref(PangoLayoutLine* line);
    int pango_layout_line_get_start_index(PangoLayoutLine* line);
    int pango_layout_line_get_length(PangoLayoutLine* line);
    int pango_layout_line_is_paragraph_start(PangoLayoutLine* line);
    PangoDirection pango_layout_line_get_resolved_direction(PangoLayoutLine* line);
    int pango_layout_line_x_to_index(PangoLayoutLine* line, int x_pos, int* index_, int* trailing);
    void pango_layout_line_index_to_x(PangoLayoutLine* line, int index_, int trailing, int* x_pos);
    void pango_layout_line_get_x_ranges(PangoLayoutLine* line, int start_index, int end_index, int** ranges, int* n_ranges);
    void pango_layout_line_get_extents(PangoLayoutLine* line, PangoRectangle* ink_rect, PangoRectangle* logical_rect);
    void pango_layout_line_get_height(PangoLayoutLine* line, int* height);
    void pango_layout_line_get_pixel_extents(PangoLayoutLine* layout_line, PangoRectangle* ink_rect, PangoRectangle* logical_rect);
    GType pango_layout_iter_get_type();
    PangoLayoutIter* pango_layout_get_iter(PangoLayout* layout);
    PangoLayoutIter* pango_layout_iter_copy(PangoLayoutIter* iter);
    void pango_layout_iter_free(PangoLayoutIter* iter);
    int pango_layout_iter_get_index(PangoLayoutIter* iter);
    PangoLayoutRun* pango_layout_iter_get_run(PangoLayoutIter* iter);
    PangoLayoutRun* pango_layout_iter_get_run_readonly(PangoLayoutIter* iter);
    PangoLayoutLine* pango_layout_iter_get_line(PangoLayoutIter* iter);
    PangoLayoutLine* pango_layout_iter_get_line_readonly(PangoLayoutIter* iter);
    int pango_layout_iter_at_last_line(PangoLayoutIter* iter);
    PangoLayout* pango_layout_iter_get_layout(PangoLayoutIter* iter);
    int pango_layout_iter_next_char(PangoLayoutIter* iter);
    int pango_layout_iter_next_cluster(PangoLayoutIter* iter);
    int pango_layout_iter_next_run(PangoLayoutIter* iter);
    int pango_layout_iter_next_line(PangoLayoutIter* iter);
    void pango_layout_iter_get_char_extents(PangoLayoutIter* iter, PangoRectangle* logical_rect);
    void pango_layout_iter_get_cluster_extents(PangoLayoutIter* iter, PangoRectangle* ink_rect, PangoRectangle* logical_rect);
    void pango_layout_iter_get_run_extents(PangoLayoutIter* iter, PangoRectangle* ink_rect, PangoRectangle* logical_rect);
    void pango_layout_iter_get_line_extents(PangoLayoutIter* iter, PangoRectangle* ink_rect, PangoRectangle* logical_rect);
    void pango_layout_iter_get_line_yrange(PangoLayoutIter* iter, int* y0_, int* y1_);
    void pango_layout_iter_get_layout_extents(PangoLayoutIter* iter, PangoRectangle* ink_rect, PangoRectangle* logical_rect);
    int pango_layout_iter_get_baseline(PangoLayoutIter* iter);
    int pango_layout_iter_get_run_baseline(PangoLayoutIter* iter);
    GMarkupParseContext* pango_markup_parser_new(dchar accel_marker);
    int pango_markup_parser_finish(GMarkupParseContext* context, PangoAttrList** attr_list, char** text, dchar* accel_char, GError** error);
    int pango_parse_markup(const(char)* markup_text, int length, dchar accel_marker, PangoAttrList** attr_list, char** text, dchar* accel_char, GError** error);
    GType pango_renderer_get_type();
    void pango_renderer_draw_layout(PangoRenderer* renderer, PangoLayout* layout, int x, int y);
    void pango_renderer_draw_layout_line(PangoRenderer* renderer, PangoLayoutLine* line, int x, int y);
    void pango_renderer_draw_glyphs(PangoRenderer* renderer, PangoFont* font, PangoGlyphString* glyphs, int x, int y);
    void pango_renderer_draw_glyph_item(PangoRenderer* renderer, const(char)* text, PangoGlyphItem* glyph_item, int x, int y);
    void pango_renderer_draw_rectangle(PangoRenderer* renderer, PangoRenderPart part, int x, int y, int width, int height);
    void pango_renderer_draw_error_underline(PangoRenderer* renderer, int x, int y, int width, int height);
    void pango_renderer_draw_trapezoid(PangoRenderer* renderer, PangoRenderPart part, double y1_, double x11, double x21, double y2, double x12, double x22);
    void pango_renderer_draw_glyph(PangoRenderer* renderer, PangoFont* font, PangoGlyph glyph, double x, double y);
    void pango_renderer_activate(PangoRenderer* renderer);
    void pango_renderer_deactivate(PangoRenderer* renderer);
    void pango_renderer_part_changed(PangoRenderer* renderer, PangoRenderPart part);
    void pango_renderer_set_color(PangoRenderer* renderer, PangoRenderPart part, const(PangoColor)* color);
    PangoColor* pango_renderer_get_color(PangoRenderer* renderer, PangoRenderPart part);
    void pango_renderer_set_alpha(PangoRenderer* renderer, PangoRenderPart part, ushort alpha);
    ushort pango_renderer_get_alpha(PangoRenderer* renderer, PangoRenderPart part);
    void pango_renderer_set_matrix(PangoRenderer* renderer, const(PangoMatrix)* matrix);
    const(PangoMatrix)* pango_renderer_get_matrix(PangoRenderer* renderer);
    PangoLayout* pango_renderer_get_layout(PangoRenderer* renderer);
    PangoLayoutLine* pango_renderer_get_layout_line(PangoRenderer* renderer);
    deprecated char** pango_split_file_list(const(char)* str);
    deprecated char* pango_trim_string(const(char)* str);
    deprecated int pango_read_line(FILE* stream, GString* str);
    deprecated int pango_skip_space(const(char)** pos);
    deprecated int pango_scan_word(const(char)** pos, GString* out_);
    deprecated int pango_scan_string(const(char)** pos, GString* out_);
    deprecated int pango_scan_int(const(char)** pos, int* out_);
    deprecated int pango_parse_enum(GType type, const(char)* str, int* value, int warn, char** possible_values);
    int pango_parse_style(const(char)* str, PangoStyle* style, int warn);
    int pango_parse_variant(const(char)* str, PangoVariant* variant, int warn);
    int pango_parse_weight(const(char)* str, PangoWeight* weight, int warn);
    int pango_parse_stretch(const(char)* str, PangoStretch* stretch, int warn);
    void pango_quantize_line_geometry(int* thickness, int* position);
    ubyte* pango_log2vis_get_embedding_levels(const(char)* text, int length, PangoDirection* pbase_dir);
    int pango_is_zero_width(dchar ch);
    void pango_find_paragraph_boundary(const(char)* text, int length, int* paragraph_delimiter_index, int* next_paragraph_start);
    int pango_version();
    const(char)* pango_version_string();
    const(char)* pango_version_check(int required_major, int required_minor, int required_micro);
}

// ---- the PANGO_TYPE_* macros

GType PANGO_TYPE_ALIGNMENT()() nothrow @nogc { return pango_alignment_get_type(); }
GType PANGO_TYPE_ATTR_LIST()() nothrow @nogc { return pango_attr_list_get_type(); }
GType PANGO_TYPE_ATTR_TYPE()() nothrow @nogc { return pango_attr_type_get_type(); }
GType PANGO_TYPE_BASELINE_SHIFT()() nothrow @nogc { return pango_baseline_shift_get_type(); }
GType PANGO_TYPE_BIDI_TYPE()() nothrow @nogc { return pango_bidi_type_get_type(); }
GType PANGO_TYPE_COLOR()() nothrow @nogc { return pango_color_get_type(); }
GType PANGO_TYPE_CONTEXT()() nothrow @nogc { return pango_context_get_type(); }
GType PANGO_TYPE_COVERAGE_LEVEL()() nothrow @nogc { return pango_coverage_level_get_type(); }
GType PANGO_TYPE_DIRECTION()() nothrow @nogc { return pango_direction_get_type(); }
GType PANGO_TYPE_ELLIPSIZE_MODE()() nothrow @nogc { return pango_ellipsize_mode_get_type(); }
GType PANGO_TYPE_ENGINE()() nothrow @nogc { return pango_engine_get_type(); }
GType PANGO_TYPE_ENGINE_LANG()() nothrow @nogc { return pango_engine_lang_get_type(); }
GType PANGO_TYPE_ENGINE_SHAPE()() nothrow @nogc { return pango_engine_shape_get_type(); }
GType PANGO_TYPE_FONT()() nothrow @nogc { return pango_font_get_type(); }
GType PANGO_TYPE_FONTSET()() nothrow @nogc { return pango_fontset_get_type(); }
GType PANGO_TYPE_FONTSET_SIMPLE()() nothrow @nogc { return pango_fontset_simple_get_type(); }
GType PANGO_TYPE_FONT_COLOR()() nothrow @nogc { return pango_font_color_get_type(); }
GType PANGO_TYPE_FONT_DESCRIPTION()() nothrow @nogc { return pango_font_description_get_type(); }
GType PANGO_TYPE_FONT_FACE()() nothrow @nogc { return pango_font_face_get_type(); }
GType PANGO_TYPE_FONT_FAMILY()() nothrow @nogc { return pango_font_family_get_type(); }
GType PANGO_TYPE_FONT_MAP()() nothrow @nogc { return pango_font_map_get_type(); }
GType PANGO_TYPE_FONT_MASK()() nothrow @nogc { return pango_font_mask_get_type(); }
GType PANGO_TYPE_FONT_METRICS()() nothrow @nogc { return pango_font_metrics_get_type(); }
GType PANGO_TYPE_FONT_SCALE()() nothrow @nogc { return pango_font_scale_get_type(); }
GType PANGO_TYPE_GLYPH_ITEM()() nothrow @nogc { return pango_glyph_item_get_type(); }
GType PANGO_TYPE_GLYPH_ITEM_ITER()() nothrow @nogc { return pango_glyph_item_iter_get_type(); }
GType PANGO_TYPE_GLYPH_STRING()() nothrow @nogc { return pango_glyph_string_get_type(); }
GType PANGO_TYPE_GRAVITY()() nothrow @nogc { return pango_gravity_get_type(); }
GType PANGO_TYPE_GRAVITY_HINT()() nothrow @nogc { return pango_gravity_hint_get_type(); }
GType PANGO_TYPE_ITEM()() nothrow @nogc { return pango_item_get_type(); }
GType PANGO_TYPE_LANGUAGE()() nothrow @nogc { return pango_language_get_type(); }
GType PANGO_TYPE_LAYOUT()() nothrow @nogc { return pango_layout_get_type(); }
GType PANGO_TYPE_LAYOUT_DESERIALIZE_ERROR()() nothrow @nogc { return pango_layout_deserialize_error_get_type(); }
GType PANGO_TYPE_LAYOUT_DESERIALIZE_FLAGS()() nothrow @nogc { return pango_layout_deserialize_flags_get_type(); }
GType PANGO_TYPE_LAYOUT_ITER()() nothrow @nogc { return pango_layout_iter_get_type(); }
GType PANGO_TYPE_LAYOUT_LINE()() nothrow @nogc { return pango_layout_line_get_type(); }
GType PANGO_TYPE_LAYOUT_SERIALIZE_FLAGS()() nothrow @nogc { return pango_layout_serialize_flags_get_type(); }
GType PANGO_TYPE_MATRIX()() nothrow @nogc { return pango_matrix_get_type(); }
GType PANGO_TYPE_OVERLINE()() nothrow @nogc { return pango_overline_get_type(); }
GType PANGO_TYPE_RENDERER()() nothrow @nogc { return pango_renderer_get_type(); }
GType PANGO_TYPE_RENDER_PART()() nothrow @nogc { return pango_render_part_get_type(); }
GType PANGO_TYPE_SCRIPT()() nothrow @nogc { return pango_script_get_type(); }
GType PANGO_TYPE_SHAPE_FLAGS()() nothrow @nogc { return pango_shape_flags_get_type(); }
GType PANGO_TYPE_SHOW_FLAGS()() nothrow @nogc { return pango_show_flags_get_type(); }
GType PANGO_TYPE_STRETCH()() nothrow @nogc { return pango_stretch_get_type(); }
GType PANGO_TYPE_STYLE()() nothrow @nogc { return pango_style_get_type(); }
GType PANGO_TYPE_TAB_ALIGN()() nothrow @nogc { return pango_tab_align_get_type(); }
GType PANGO_TYPE_TAB_ARRAY()() nothrow @nogc { return pango_tab_array_get_type(); }
GType PANGO_TYPE_TEXT_TRANSFORM()() nothrow @nogc { return pango_text_transform_get_type(); }
GType PANGO_TYPE_UNDERLINE()() nothrow @nogc { return pango_underline_get_type(); }
GType PANGO_TYPE_VARIANT()() nothrow @nogc { return pango_variant_get_type(); }
GType PANGO_TYPE_WEIGHT()() nothrow @nogc { return pango_weight_get_type(); }
GType PANGO_TYPE_WRAP_MODE()() nothrow @nogc { return pango_wrap_mode_get_type(); }
