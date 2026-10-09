/*
 * Minimal `extern(C)` binding to the one piece of libXrandr that
 * `fl.platform_x11.screenDpi()` needs: the RandR 1.5 monitor list, which
 * carries each monitor's physical size in millimeters. Xinerama
 * (`fl.xinerama`) reports pixel geometry only.
 *
 * Linked as `-lXrandr`, like the other X extension libraries.
 */
module fl.xrandr;

version (linux):

import fl.xlib : Display, Window, Atom, XID, Bool, Status;

extern (C):

/// Mirrors `XRRMonitorInfo` (`X11/extensions/Xrandr.h`) field-for-field.
struct XRRMonitorInfo
{
    Atom name;
    Bool primary;
    Bool automatic;
    int noutput;
    int x, y;
    int width, height;
    int mwidth, mheight;
    XID* outputs;
}

/// Non-zero when the server has the RandR extension; fills in its version.
Status XRRQueryVersion(Display* dpy, int* major, int* minor);

/// Requires RandR 1.5 or newer. Returns `null` on failure. With
/// `getActive` set, only monitors that are switched on are listed. The
/// result is freed with `XRRFreeMonitors()`.
XRRMonitorInfo* XRRGetMonitors(Display* dpy, Window window, Bool getActive, int* nmonitors);

void XRRFreeMonitors(XRRMonitorInfo* monitors);
