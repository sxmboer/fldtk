/*
 * Infrastructure module: raw `extern(C)` bindings for the small slice of
 * libXext's SHAPE extension (`<X11/extensions/shape.h>`) this port needs --
 * `XShapeCombineMask()`, backing `Window.shape()` (`fl.window`)'s real
 * non-rectangular-window support on X11, and `XShapeCombineRectangles()`,
 * which gives the drag-and-drop preview (`fl.platform_x11.dnd()`) an
 * empty input region so the pointer passes through it. Same role `fl.xfixes`/`fl.xcursor`/
 * `fl.xinerama` play for their own libraries -- SHAPE is yet another
 * separate library (`libXext.so`) with its own link requirement (`-lXext`),
 * so it gets its own small module rather than being folded into `fl.xlib`.
 *
 * Deliberately linked directly rather than `dlopen()`/`dlsym()`d the way
 * FLTK's own `Fl_X11_Window_Driver::combine_mask()` does (a portability
 * hedge against systems lacking libXext entirely) -- this port already links
 * `-lXcursor`/`-lXfixes`/`-lXinerama` directly for the same category of
 * "small, near-universally-present X11 extension library" (see `dub.sdl`),
 * so a direct link is the consistent choice here too; noted as a deliberate
 * deviation in `PORTING.md`.
 *
 * Deliberately not ported: `XShapeCombineRegion()`/
 * `XShapeCombineShape()`/`XShapeOffsetShape()` (nothing here needs them), and the
 * `ShapeNotify` event subsystem (FLTK doesn't use it either for this
 * feature).
 */
module fl.xshape;

version (linux):

import fl.xlib : Display, Window, Pixmap, Bool, XRectangle;

extern (C):

Bool XShapeQueryExtension(Display* display, int* eventBaseReturn, int* errorBaseReturn);

void XShapeCombineMask(Display* display, Window dest, int destKind,
    int xOff, int yOff, Pixmap src, int op);

void XShapeCombineRectangles(Display* display, Window dest, int destKind,
    int xOff, int yOff, XRectangle* rectangles, int nRects, int op, int ordering);

/// `ShapeBounding`/`ShapeClip`/`ShapeInput` -- which of a window's three
/// independent shape regions to affect. `Window.shape()` targets the
/// outer, visible-and-clickable region; the drag preview the input region.
enum int ShapeBounding = 0;
/// ditto
enum int ShapeInput = 2;

/// `ShapeSet`/`ShapeUnion`/`ShapeIntersect`/`ShapeSubtract`/`ShapeInvert` --
/// how the new mask combines with any existing shape. `Window.shape()`
/// always replaces the shape outright, matching FLTK exactly.
enum int ShapeSet = 0;
