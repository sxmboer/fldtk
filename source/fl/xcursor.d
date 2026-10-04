/*
 * Minimal `extern(C)` bindings for libXcursor (X11/Xcursor/Xcursor.h)
 * -- infrastructure, not a port of an FLTK header, same role as
 * fl.xft/fl.fontconfig. Needed for `Window.cursor(const(RGBImage),
 * int, int)` (`Fl_Window::cursor(const Fl_RGB_Image*, int, int)`),
 * which FLTK's own X11 driver backs with these exact calls
 * (`src/Fl_x.cxx`'s `Fl_X11_Window_Driver::set_cursor(const
 * Fl_RGB_Image*, int, int)`). Only the handful of functions/types
 * actually needed are declared.
 */
module fl.xcursor;

version (linux):

import fl.xlib : Display, Cursor;

extern (C):
@nogc:
nothrow:

alias XcursorUInt = uint;
alias XcursorDim = XcursorUInt;
alias XcursorPixel = XcursorUInt;

struct XcursorImage
{
    XcursorUInt version_; // `version` is a D keyword
    XcursorDim size;
    XcursorDim width;
    XcursorDim height;
    XcursorDim xhot;
    XcursorDim yhot;
    XcursorUInt delay;
    XcursorPixel* pixels;
}

XcursorImage* XcursorImageCreate(int width, int height);
void XcursorImageDestroy(XcursorImage* image);
Cursor XcursorImageLoadCursor(Display* dpy, const(XcursorImage)* image);
