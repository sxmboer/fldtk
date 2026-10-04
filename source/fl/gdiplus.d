/*
 * Hand-written `extern(Windows)` bindings for GDI+'s "flat" C API
 * (`gdiplusflat.h`/`gdiplusinit.h`/`gdiplustypes.h`/`gdiplusenums.h`),
 * used by `fl.gdiplus_graphics_driver`.
 * Infrastructure, not a port of an FLTK header -- same role `fl.xlib`/
 * `fl.opengl` play for their own libraries.
 *
 * **Why the flat C API, not the `Gdiplus::` C++ classes FLTK's own
 * `Fl_GDIplus_Graphics_Driver` uses directly**: GDI+ ships *both* --
 * the C++ wrapper (`Gdiplus::Graphics`/`Gdiplus::Pen`/etc., a set of
 * header-only inline classes with no real ABI of their own) and the
 * underlying flat, `extern "C"`-linkage functions those inline methods
 * each call straight through to (`GdipCreateFromHDC`, `GdipDrawLineI`,
 * ...) -- a real, stable, documented, language-agnostic C ABI designed
 * exactly for non-C++ consumers, the same relationship COM interfaces
 * have to their own C++ wrapper conveniences elsewhere in this port's
 * Windows code. D cannot call into `gdiplus.dll`'s C++ vtables at all
 * (no cross-compiler C++ ABI compatibility, unlike COM's documented
 * binary layout) -- the flat API is the only way in. Each `Gdiplus::`
 * method FLTK calls has a direct, mechanical, same-parameter-order
 * flat-API equivalent (confirmed by cross-referencing the real
 * `gdiplusflat.h`/`gdiplusinit.h` headers, not assumed) -- see
 * `fl.gdiplus_graphics_driver`'s own doc comment for the exact mapping
 * table used while porting.
 *
 * **Verified against real headers, not guessed**: this project's own
 * dev environment has no Windows SDK, but does have a full, real copy
 * of these headers via installed Wine (`/usr/local/include/wine/
 * windows/gdiplus*.h`) -- every signature/struct/enum value below was
 * checked against that copy directly, the same verification standard
 * every other Windows binding in this project gets against the local
 * druntime `core.sys.windows.*` headers. Unlike every phase before this
 * one, though, `core.sys.windows.*` itself has no GDI+ bindings at all
 * (GDI+ predates most of druntime's Windows coverage and was never a
 * priority for it), so this module exists at all for the same reason
 * `fl.xlib`/`fl.opengl` do: the binding simply isn't there to reuse.
 *
 * Scope: only what `fl.gdiplus_graphics_driver` actually calls --
 * startup/shutdown, a `Graphics` context bound to an existing `HDC`,
 * solid pens/brushes, paths, and the draw/fill primitives for
 * lines/arcs/pies/paths. Real GDI+ has hundreds more entry points
 * (gradients, images, text layout, matrices beyond simple scaling, ...)
 * none of which FLTK's own `Fl_GDIplus_Graphics_Driver` uses either.
 */
module fl.gdiplus;

version (Windows):

import core.sys.windows.windef : BOOL, HDC;
import core.sys.windows.basetsd : UINT32;

extern (Windows):
nothrow:

// ---- gdiplustypes.h ----

alias REAL = float;

enum Status
{
    Ok = 0,
    GenericError = 1,
    InvalidParameter = 2,
    OutOfMemory = 3,
    ObjectBusy = 4,
    InsufficientBuffer = 5,
    NotImplemented = 6,
    Win32Error = 7,
    WrongState = 8,
    Aborted = 9,
    FileNotFound = 10,
    ValueOverflow = 11,
    AccessDenied = 12,
    UnknownImageFormat = 13,
    FontFamilyNotFound = 14,
    FontStyleNotFound = 15,
    NotTrueTypeFont = 16,
    UnsupportedGdiplusVersion = 17,
    GdiplusNotInitialized = 18,
    PropertyNotFound = 19,
    PropertyNotSupported = 20,
    ProfileNotFound = 21,
}
alias GpStatus = Status;

struct GpPoint
{
    int X, Y;
}

struct GpPointF
{
    REAL X, Y;
}

// ---- gdipluspixelformats.h ----

/// Packed 0xAARRGGBB, matching `Gdiplus::Color`'s own internal
/// representation exactly (`Gdiplus::Color` has no members beyond one
/// `ARGB value`) -- this port never needs the `Gdiplus::Color` wrapper
/// class itself, just this packed value, built directly from the same
/// `ubyte r, g, b` triple `fl.draw.colorToRgb8()` already hands every
/// other Windows driver in this port (see `fl.gdiplus_graphics_driver.
/// toArgb()`), skipping the `COLORREF` round-trip `Gdiplus::Color::
/// SetFromCOLORREF()` does FLTK (same bytes in, same bytes out).
alias ARGB = uint;

// ---- gdiplusenums.h ----

enum GpUnit
{
    UnitWorld = 0,
    UnitDisplay = 1,
    UnitPixel = 2,
    UnitPoint = 3,
    UnitInch = 4,
    UnitDocument = 5,
    UnitMillimeter = 6,
}

enum GpFillMode
{
    FillModeAlternate = 0,
    FillModeWinding = 1,
}

enum GpLineCap
{
    LineCapFlat = 0x00,
    LineCapSquare = 0x01,
    LineCapRound = 0x02,
    LineCapTriangle = 0x03,
}

enum GpLineJoin
{
    LineJoinMiter = 0,
    LineJoinBevel = 1,
    LineJoinRound = 2,
    LineJoinMiterClipped = 3,
}

enum SmoothingMode
{
    SmoothingModeInvalid = -1,
    SmoothingModeDefault = 0,
    SmoothingModeHighSpeed = 1,
    SmoothingModeHighQuality = 2,
    SmoothingModeNone = 3,
    SmoothingModeAntiAlias = 4,
}

enum GpDashStyle
{
    DashStyleSolid = 0,
    DashStyleDash = 1,
    DashStyleDot = 2,
    DashStyleDashDot = 3,
    DashStyleDashDotDot = 4,
    DashStyleCustom = 5,
}

enum GpMatrixOrder
{
    MatrixOrderPrepend = 0,
    MatrixOrderAppend = 1,
}

// ---- Opaque object handles (gdiplusgpstubs.h -- forward-declared
// structs FLTK too, no members on either side; every real access
// goes through the Gdip* functions below, taking/returning pointers to
// these). ----

struct GpGraphics;
struct GpPen;
struct GpBrush;
struct GpSolidFill;
struct GpPath;

// ---- gdiplusinit.h ----

// Matches druntime's own established convention for a callback typedef
// (e.g. `winuser.d`'s `WNDPROC`) -- the block's own `extern (Windows)
// nothrow` applies to each plain `alias ReturnType function(Params)
// Name;` inside it, rather than repeating the linkage/attribute on
// each alias individually.
extern (Windows) nothrow
{
    alias void function(int, char*) DebugEventProc;
    alias Status function(size_t*) NotificationHookProc;
    alias void function(size_t) NotificationUnhookProc;
}

struct GdiplusStartupInput
{
    UINT32 GdiplusVersion = 1;
    DebugEventProc DebugEventCallback = null;
    BOOL SuppressBackgroundThread = 0;
    BOOL SuppressExternalCodecs = 0;
}

struct GdiplusStartupOutput
{
    NotificationHookProc NotificationHook;
    NotificationUnhookProc NotificationUnhook;
}

Status GdiplusStartup(size_t* token, const(GdiplusStartupInput)* input, GdiplusStartupOutput* output);
void GdiplusShutdown(size_t token);

// ---- gdiplusflat.h ----

// -- Graphics --
GpStatus GdipCreateFromHDC(HDC hdc, GpGraphics** graphics);
GpStatus GdipDeleteGraphics(GpGraphics* graphics);
GpStatus GdipSetSmoothingMode(GpGraphics* graphics, SmoothingMode mode);
GpStatus GdipScaleWorldTransform(GpGraphics* graphics, REAL sx, REAL sy, GpMatrixOrder order);
GpStatus GdipDrawLineI(GpGraphics* graphics, GpPen* pen, int x1, int y1, int x2, int y2);
GpStatus GdipDrawArcI(GpGraphics* graphics, GpPen* pen, int x, int y, int width, int height,
    REAL startAngle, REAL sweepAngle);
GpStatus GdipDrawPieI(GpGraphics* graphics, GpPen* pen, int x, int y, int width, int height,
    REAL startAngle, REAL sweepAngle);
GpStatus GdipFillPieI(GpGraphics* graphics, GpBrush* brush, int x, int y, int width, int height,
    REAL startAngle, REAL sweepAngle);
GpStatus GdipDrawPath(GpGraphics* graphics, GpPen* pen, GpPath* path);
GpStatus GdipFillPath(GpGraphics* graphics, GpBrush* brush, GpPath* path);

// -- Pen --
GpStatus GdipCreatePen1(ARGB color, REAL width, GpUnit unit, GpPen** pen);
GpStatus GdipDeletePen(GpPen* pen);
GpStatus GdipSetPenColor(GpPen* pen, ARGB argb);
GpStatus GdipSetPenWidth(GpPen* pen, REAL width);
GpStatus GdipSetPenLineJoin(GpPen* pen, GpLineJoin lineJoin);
GpStatus GdipSetPenStartCap(GpPen* pen, GpLineCap startCap);
GpStatus GdipSetPenEndCap(GpPen* pen, GpLineCap endCap);
GpStatus GdipSetPenDashStyle(GpPen* pen, GpDashStyle dashStyle);
GpStatus GdipSetPenDashArray(GpPen* pen, const(REAL)* dash, int count);

// -- SolidFill (brush) --
GpStatus GdipCreateSolidFill(ARGB color, GpSolidFill** brush);
GpStatus GdipDeleteBrush(GpBrush* brush);
GpStatus GdipSetSolidFillColor(GpSolidFill* brush, ARGB argb);

// -- Path --
GpStatus GdipCreatePath(GpFillMode fillMode, GpPath** path);
GpStatus GdipDeletePath(GpPath* path);
GpStatus GdipAddPathLineI(GpPath* path, int x1, int y1, int x2, int y2);
GpStatus GdipAddPathLine2I(GpPath* path, const(GpPoint)* points, int count);
GpStatus GdipAddPathLine2(GpPath* path, const(GpPointF)* points, int count);
GpStatus GdipAddPathPolygonI(GpPath* path, const(GpPoint)* points, int count);
GpStatus GdipClosePathFigure(GpPath* path);
