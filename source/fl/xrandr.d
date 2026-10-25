/*
 * Minimal `extern(C)` binding to the parts of libXrandr that
 * `fl.platform_x11` needs: the RandR 1.5 monitor list, which carries each
 * monitor's physical size in millimeters (Xinerama, `fl.xinerama`,
 * reports pixel geometry only), and the screen-change notification that
 * tells it the monitors or the root window size changed.
 *
 * Linked as `-lXrandr`, like the other X extension libraries.
 */
module fl.xrandr;

version (linux):

import fl.xlib : Display, Window, Atom, XID, Bool, Status, XEvent;

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

/// `XRRSelectInput()` mask bit for `RRScreenChangeNotify` events.
enum int RRScreenChangeNotifyMask = 1 << 0;

/// Offset of `RRScreenChangeNotify` from the extension's event base.
enum int RRScreenChangeNotify = 0;

/// Non-zero when the server has the RandR extension; fills in the base
/// number of its event and error codes.
Bool XRRQueryExtension(Display* dpy, int* eventBase, int* errorBase);

/// Selects which RandR events `window` receives.
void XRRSelectInput(Display* dpy, Window window, int mask);

/// Updates Xlib's cached screen size from an `RRScreenChangeNotify`
/// event, so `XDisplayWidth()`/`XDisplayHeight()` report the new size.
int XRRUpdateConfiguration(XEvent* event);
