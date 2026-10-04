/*
 * Minimal `extern(C)` bindings for libfontconfig (fontconfig/fontconfig.h)
 * -- infrastructure, not a port of an FLTK header, same role as fl.xft
 * (which this module is a sibling to: Xft itself is built on
 * fontconfig, but fl.xft's own bindings only cover font *opening* by
 * name, never enumeration). Needed for `fl.core.setFonts()`/
 * `getFontSizes()` (`Fl::set_fonts()`/`Fl::get_font_sizes()`), which
 * FLTK's own Xft driver backs with raw `Fc*` calls directly
 * (`src/drivers/Xlib/Fl_Xlib_Graphics_Driver_font_xft.cxx`) rather than
 * anything in `Xft.h` itself -- see that module's `set_fonts()` for the
 * exact real calls this binds.
 *
 * Only the handful of functions/types actually needed are declared.
 * `FcObjectSetBuild()` (FLTK's own choice, a C-varargs,
 * NULL-sentinel-terminated function) is deliberately not bound --
 * `FcObjectSetCreate()` + repeated `FcObjectSetAdd()` calls build the
 * same object set without needing a C-variadic `extern(C)` declaration
 * on the D side.
 */
module fl.fontconfig;

version (linux):

extern (C):
@nogc:
nothrow:

alias FcChar8 = ubyte;
alias FcBool = int;

// Opaque -- only ever passed through as a pointer here.
struct FcPattern;

struct FcObjectSet
{
    int nobject;
    int sobject;
    const(char)** objects;
}

struct FcFontSet
{
    int nfont;
    int sfont;
    FcPattern** fonts;
}

enum FcResult
{
    fcResultMatch = 0,
    fcResultNoMatch = 1,
    fcResultTypeMismatch = 2,
    fcResultNoId = 3,
    fcResultOutOfMemory = 4,
}

/// A 2x2 font transformation matrix -- what `FC_MATRIX` takes. Built
/// directly rather than via `FcMatrixInit()`/`FcMatrixRotate()` (both
/// trivial macros/functions this binding skips): starting from the
/// identity matrix and rotating by `angle` degrees always produces
/// exactly `{cos, -sin, sin, cos}` (`FcMatrixRotate()`'s own body is
/// `r = {c, -s, s, c}; FcMatrixMultiply(m, m, &r);`, and multiplying by
/// the identity leaves `r` unchanged) -- see `fl.xft`'s rotated-font
/// helper for the one real call site.
struct FcMatrix
{
    double xx, xy, yx, yy;
}

enum FC_FAMILY = "family";
enum FC_STYLE = "style";
enum FC_PIXEL_SIZE = "pixelsize";
enum FC_WEIGHT = "weight";
enum FC_SLANT = "slant";
enum FC_MATRIX = "matrix";

enum FC_WEIGHT_MEDIUM = 100;
enum FC_WEIGHT_BOLD = 200;
enum FC_SLANT_ROMAN = 0;
enum FC_SLANT_ITALIC = 100;

FcBool FcInit();

FcPattern* FcPatternCreate();
void FcPatternDestroy(FcPattern* p);
FcBool FcPatternAddString(FcPattern* p, const(char)* object, const(FcChar8)* s);
FcBool FcPatternAddInteger(FcPattern* p, const(char)* object, int i);
FcBool FcPatternAddDouble(FcPattern* p, const(char)* object, double d);
FcBool FcPatternAddMatrix(FcPattern* p, const(char)* object, const(FcMatrix)* m);
FcResult FcPatternGetDouble(const(FcPattern)* p, const(char)* object, int n, double* d);

FcObjectSet* FcObjectSetCreate();
FcBool FcObjectSetAdd(FcObjectSet* os, const(char)* object);
void FcObjectSetDestroy(FcObjectSet* os);

FcFontSet* FcFontList(void* config, FcPattern* p, FcObjectSet* os);
void FcFontSetDestroy(FcFontSet* s);

/// Caller must release the result with `core.stdc.stdlib.free()`
/// (matching FLTK's own `free(font)` call on this exact return
/// value in `Fl_Xlib_Graphics_Driver::set_fonts()` -- not the more
/// "correct" `FcStrFree()` fontconfig itself also provides, faithfully
/// replicated here rather than silently corrected).
FcChar8* FcNameUnparse(FcPattern* pat);
