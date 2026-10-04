/*
 * Infrastructure module: raw `extern(C)` bindings for the small slice
 * of libXfixes this port needs -- instant, event-driven notification
 * when another application takes ownership of the PRIMARY or CLIPBOARD
 * selection, backing `fl.core.addClipboardNotify()`'s real-time path
 * (see `fl.platform_x11`'s own doc comments on where this is wired in).
 * Same role `fl.xinerama`/`fl.xcursor` play for their own libraries --
 * Xfixes is yet another separate library (`libXfixes.so`,
 * `<X11/extensions/Xfixes.h>`) with its own link requirement
 * (`-lXfixes`), so it gets its own small module rather than being
 * folded into `fl.xlib`.
 *
 * Deliberately not ported: `XFixesQueryVersion()` (a capability/version
 * probe this port doesn't need -- `XFixesQueryExtension()` alone is
 * sufficient to know whether the extension exists at all), every
 * cursor-image/region/save-set function Xfixes also provides (no
 * consumer here needs them -- this port's only use for the library is
 * selection-change notification), and the two other notify masks
 * (`XFixesSelectionWindowDestroyNotifyMask`/
 * `XFixesSelectionClientCloseNotifyMask`) -- matching FLTK's own
 * `Fl_x.cxx`, which only ever requests `XFixesSetSelectionOwnerNotifyMask`.
 */
module fl.xfixes;

version (linux):

import fl.xlib : Display, Window, Atom, Time, Bool;
import core.stdc.config : c_ulong;

extern (C):

Bool XFixesQueryExtension(Display* dpy, int* event_base_return, int* error_base_return);

void XFixesSelectSelectionInput(Display* dpy, Window win, Atom selection, c_ulong eventMask);

enum c_ulong XFixesSetSelectionOwnerNotifyMask = 1L << 0;

/// The XFixes extension's own event-subtype offset for a selection-
/// ownership-change notification -- added to the extension's runtime-
/// assigned `event_base` (from `XFixesQueryExtension()`) to get the
/// real X event `type` value to compare a raw `XEvent.type` against.
enum int XFixesSelectionNotify = 0;

/// Mirrors FLTK's real `XFixesSelectionNotifyEvent`
/// (`X11/extensions/Xfixes.h`) field-for-field.
struct XFixesSelectionNotifyEvent
{
    int type;
    c_ulong serial;
    Bool send_event;
    Display* display;
    Window window;
    int subtype;
    Window owner;
    Atom selection;
    Time timestamp;
    Time selection_timestamp;
}
