/*
 * Minimal `extern(C)` bindings for libXft (X11/Xft/Xft.h) and the
 * small slice of libXrender it depends on (X11/extensions/Xrender.h,
 * for XRenderColor/XGlyphInfo). Infrastructure, not a port of an FLTK
 * header -- same role as fl.xlib, which this module builds on for the
 * Display/Drawable/Visual/Colormap/Bool types it shares.
 *
 * Xft is what modern FLTK actually uses for X11 text rendering by
 * default (see src/drivers/Xlib/Fl_Xlib_Graphics_Driver_font_xft.cxx
 * -- there's also a legacy core-X-fonts path,
 * Fl_Xlib_Graphics_Driver_font_x.cxx, used only as a fallback when Xft
 * isn't available; not ported here, Xft is assumed present). Only the
 * handful of functions/structs fl.draw's text primitives need are
 * declared; Xft.h itself has much more (bitmap/alpha XftDraw variants,
 * XftFontOpen's full FcPattern-based matching, UTF-16 overloads,
 * FreeType face access, ...).
 *
 * XftFont's public fields (ascent/descent/height/max_advance_width)
 * are mirrored exactly since fl.draw reads them directly for metrics;
 * the two trailing FcCharSet-pointer/FcPattern-pointer fields are
 * never dereferenced here, so they're kept only as opaque pointers to
 * preserve the struct's layout/size for anything Xft itself returns
 * a pointer to (this binding never allocates an XftFont itself,
 * XftFontOpenName always does, so exact layout beyond "same size and
 * field offsets up to what's read" is what matters).
 */
module fl.xft;

version (linux):

import core.stdc.config : c_ulong;

import fl.xlib : Display, Drawable, Visual, Colormap, Bool, XRectangle;
import fl.fontconfig : FcPattern, FcResult;

extern (C):
@nogc:
nothrow:

// Opaque Fontconfig types, only ever passed through as pointers here.
struct FcCharSet;
struct FcPattern;

struct XftFont
{
    int ascent;
    int descent;
    int height;
    int maxAdvanceWidth;
    FcCharSet* charset;
    FcPattern* pattern;
}

// Opaque (real name is `struct _XftDraw`).
struct _XftDraw;
alias XftDraw = _XftDraw;

struct XRenderColor
{
    ushort red;
    ushort green;
    ushort blue;
    ushort alpha;
}

struct XftColor
{
    c_ulong pixel;
    XRenderColor color;
}

struct XGlyphInfo
{
    ushort width;
    ushort height;
    short x;
    short y;
    short xOff;
    short yOff;
}

XftFont* XftFontOpenName(Display* dpy, int screen, const(char)* name);
void XftFontClose(Display* dpy, XftFont* pub);

/// The `FcPattern`-based font-opening pair `fontopen()` uses FLTK
/// (`Fl_Xlib_Graphics_Driver_font_xft.cxx`) for the one case
/// `XftFontOpenName()`'s simple name-string interface can't express: a
/// rotated font (`FC_MATRIX` needs a real pattern to attach to, not a
/// name string). `XftFontMatch()` resolves `pattern` against the
/// system's installed fonts (the returned match pattern is owned by
/// Fontconfig's own cache -- never `FcPatternDestroy()`'d by the
/// caller, matching FLTK's own comment on this exact call);
/// `XftFontOpenPattern()` then opens it. Used only by `fl.draw`'s
/// angled-font path -- the plain, angle-0 path keeps using
/// `XftFontOpenName()` above, unchanged.
FcPattern* XftFontMatch(Display* dpy, int screen, const(FcPattern)* pattern, FcResult* result);
XftFont* XftFontOpenPattern(Display* dpy, FcPattern* pattern);

XftDraw* XftDrawCreate(Display* dpy, Drawable drawable, Visual* visual, Colormap colormap);
void XftDrawDestroy(XftDraw* draw);
void XftDrawStringUtf8(XftDraw* draw, const(XftColor)* color, XftFont* pub,
    int x, int y, const(ubyte)* str, int len);

Bool XftColorAllocValue(Display* dpy, Visual* visual, Colormap cmap,
    const(XRenderColor)* color, XftColor* result);
void XftColorFree(Display* dpy, Visual* visual, Colormap cmap, XftColor* color);

void XftTextExtentsUtf8(Display* dpy, XftFont* pub, const(ubyte)* str, int len,
    XGlyphInfo* extents);

/// Clears any clip region on draw (the only use this port has for
/// XftDrawSetClip -- it never builds a real X11 Region, so the `r`
/// param is typed as a bare pointer rather than defining the opaque
/// `Region` type just to always pass null/None through it; see
/// fl.draw's restoreClip()).
Bool XftDrawSetClip(XftDraw* draw, void* r);

/// Sets draw's clip to a single rectangle -- this port's clip stack
/// (fl.draw) only ever tracks one effective rectangle at a time (see
/// that module's own note on why a full Region isn't needed), so `n`
/// is always 1 here even though Xft itself allows more.
Bool XftDrawSetClipRectangles(XftDraw* draw, int xOrigin, int yOrigin,
    const(XRectangle)* rects, int n);
