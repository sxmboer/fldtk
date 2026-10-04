/*
 * Infrastructure module: raw `extern(C)` bindings for the small slice of
 * libXinerama this port needs (core-roadmap item 8 -- multi-monitor
 * geometry query only: which physical monitors exist and where they
 * sit within the X server's single combined screen). No direct
 * FLTK header equivalent -- the same role `fl.xlib` plays for core
 * Xlib and `fl.xft` plays for the libXft/libXrender slice `fl.draw`
 * needs; Xinerama is yet another separate library (`libXinerama.so`,
 * `<X11/extensions/Xinerama.h>`) with its own link requirement
 * (`-lXinerama`), so it gets its own small module rather than being
 * folded into `fl.xlib` alongside plain Xlib itself.
 *
 * Deliberately not ported: `XineramaQueryExtension()`/
 * `XineramaQueryVersion()` (capability/version probes this port doesn't
 * need -- `XineramaIsActive()` alone is sufficient to know whether
 * `XineramaQueryScreens()` will return anything useful).
 */
module fl.xinerama;

version (linux):

import fl.xlib : Display, Bool;

extern (C):

/// Mirrors FLTK's real `XineramaScreenInfo` (`X11/extensions/
/// Xinerama.h`) field-for-field.
struct XineramaScreenInfo
{
    int screen_number;
    short x_org;
    short y_org;
    short width;
    short height;
}

Bool XineramaIsActive(Display* dpy);

/// Returns the number of physical monitors and a pointer to a
/// server-allocated array describing each one's position/size --
/// `null`/`0` if Xinerama isn't active. The returned array must be
/// freed with `fl.xlib.XFree()`, matching FLTK's own doc comment.
XineramaScreenInfo* XineramaQueryScreens(Display* dpy, int* number);
