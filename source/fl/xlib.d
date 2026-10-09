/*
 * Minimal `extern(C)` bindings for libX11 (Xlib.h), FLTK's X11 backend
 * dependency. Not a port of an FLTK header -- this is infrastructure,
 * the same role C's own stdlib headers play for the rest of the port.
 * Only the types/constants/functions fl.platform_x11 actually needs
 * are declared; Xlib.h itself has thousands more.
 *
 * Display/Visual/Screen are treated as fully opaque (forward-declared,
 * never dereferenced field-by-field) -- everything about them is
 * queried through real Xlib accessor functions (XDefaultScreen(),
 * XDefaultVisual(), ...) rather than the C macro equivalents
 * (DefaultScreen(), DefaultVisual(), ...), which reach into Display's
 * private internal layout and only exist as preprocessor macros (no
 * D-callable symbol). Xlib ships both forms specifically so bindings
 * for macro-less languages can use the function form; that's what's
 * used throughout here.
 *
 * Linux/X11 only for now, matching this port's current primary target
 * (see CONVENTIONS.md); gated with `version (linux)` so it's inert on
 * other platforms until a Wayland/Windows driver exists alongside it.
 *
 * No `unittest` blocks here -- see fl.platform_x11's module note on
 * why (needs a live X server; `dub test` must stay headless-safe).
 */
module fl.xlib;

version (linux):

import core.stdc.config : c_ulong, c_long;

extern (C):
@nogc:
nothrow:

alias XID = c_ulong;
alias Window = XID;
alias Drawable = XID;
alias Colormap = XID;
alias Atom = XID;
alias Time = XID;
alias Pixmap = XID;
alias Cursor = XID;
alias Bool = int;
alias Status = int;

// Opaque; only ever used behind a pointer, queried via X*() accessor
// functions below rather than direct field access.
struct Display;
struct Visual;
struct Screen;

// Opaque (real name is `struct _XGC`); GCs are only ever created,
// passed to drawing calls, and never inspected field-by-field here.
struct _XGC;
alias GC = _XGC*;

// Opaque input-method/input-context handles (core-roadmap item 9) --
// only ever created/destroyed/passed to the functions below, never
// inspected field-by-field, same treatment as GC above.
struct _XIM;
alias XIM = _XIM*;
struct _XIC;
alias XIC = _XIC*;
alias XIMStyle = c_ulong;

struct XSetWindowAttributes
{
    XID background_pixmap;
    c_ulong background_pixel;
    XID border_pixmap;
    c_ulong border_pixel;
    int bit_gravity;
    int win_gravity;
    int backing_store;
    c_ulong backing_planes;
    c_ulong backing_pixel;
    Bool save_under;
    c_long event_mask;
    c_long do_not_propagate_mask;
    Bool override_redirect;
    Colormap colormap;
    XID cursor;
}

/// `map_state` values for `XWindowAttributes` (`X.h`): whether a window
/// (and, for `IsViewable`, every ancestor up to the root) is actually
/// mapped -- see `waitViewable()` in `fl.platform_x11` for why this
/// matters (a window manager's asynchronous reparent-and-map means
/// `XMapWindow()` returning, or even `XSync()` afterward, doesn't by
/// itself guarantee `IsViewable` yet).
enum int IsUnmapped = 0;
enum int IsUnviewable = 1;
enum int IsViewable = 2;

struct XWindowAttributes
{
    int x, y;
    int width, height;
    int border_width;
    int depth;
    Visual* visual;
    Window root;
    int class_; // `class` FLTK; reserved word in D
    int bit_gravity;
    int win_gravity;
    int backing_store;
    c_ulong backing_planes;
    c_ulong backing_pixel;
    Bool save_under;
    Colormap colormap;
    Bool map_installed;
    int map_state;
    c_long all_event_masks;
    c_long your_event_mask;
    c_long do_not_propagate_mask;
    Bool override_redirect;
    Screen* screen;
}

struct XAnyEvent
{
    int type;
    c_ulong serial;
    Bool send_event;
    Display* display;
    Window window;
}

struct XExposeEvent
{
    int type;
    c_ulong serial;
    Bool send_event;
    Display* display;
    Window window;
    int x, y;
    int width, height;
    int count;
}

struct XConfigureEvent
{
    int type;
    c_ulong serial;
    Bool send_event;
    Display* display;
    Window event;
    Window window;
    int x, y;
    int width, height;
    int border_width;
    Window above;
    Bool override_redirect;
}

struct XClientMessageEvent
{
    int type;
    c_ulong serial;
    Bool send_event;
    Display* display;
    Window window;
    Atom message_type;
    int format;
    union Data
    {
        byte[20] b;
        short[10] s;
        c_long[5] l;
    }

    Data data;
}

struct XKeyEvent
{
    int type;
    c_ulong serial;
    Bool send_event;
    Display* display;
    Window window;
    Window root;
    Window subwindow;
    Time time;
    int x, y;
    int x_root, y_root;
    uint state;
    uint keycode;
    Bool same_screen;
}

struct XButtonEvent
{
    int type;
    c_ulong serial;
    Bool send_event;
    Display* display;
    Window window;
    Window root;
    Window subwindow;
    Time time;
    int x, y;
    int x_root, y_root;
    uint state;
    uint button;
    Bool same_screen;
}

struct XMotionEvent
{
    int type;
    c_ulong serial;
    Bool send_event;
    Display* display;
    Window window;
    Window root;
    Window subwindow;
    Time time;
    int x, y;
    int x_root, y_root;
    uint state;
    byte is_hint;
    Bool same_screen;
}

struct XCrossingEvent
{
    int type;
    c_ulong serial;
    Bool send_event;
    Display* display;
    Window window;
    Window root;
    Window subwindow;
    Time time;
    int x, y;
    int x_root, y_root;
    int mode;
    int detail;
    Bool same_screen;
    Bool focus;
    uint state;
}

struct XPropertyEvent
{
    int type;
    c_ulong serial;
    Bool send_event;
    Display* display;
    Window window;
    Atom atom;
    Time time;
    int state; // PropertyNewValue or PropertyDelete
}

/// KeymapNotify -- automatically generated by the server right after an
/// EnterNotify/FocusIn on a window selecting KeymapStateMask; carries
/// the full 256-key held-state bitmask (`key_vector`, 1 bit per keycode).
/// Unusually for an XEvent, this one has no `time` field at all -- not
/// an omission, FLTK's own real XKeymapEvent (X11/Xlib.h) doesn't
/// have one either.
struct XKeymapEvent
{
    int type;
    c_ulong serial;
    Bool send_event;
    Display* display;
    Window window;
    ubyte[32] key_vector;
}

/// SelectionNotify -- the reply to our own XConvertSelection() request
/// (asking another app's selection owner to hand over its data), or
/// SelectionRequest's own required reply shape (see XSendEvent() call
/// sites in fl.platform_x11 -- FLTK builds and sends one of these
/// by hand for that case too, rather than receiving it).
struct XSelectionEvent
{
    int type;
    c_ulong serial;
    Bool send_event;
    Display* display;
    Window requestor;
    Atom selection;
    Atom target;
    Atom property; // None (0) means "conversion failed"
    Time time;
}

/// SelectionRequest -- another app is asking *us*, as the current
/// selection owner, to convert our selection into some target format.
struct XSelectionRequestEvent
{
    int type;
    c_ulong serial;
    Bool send_event;
    Display* display;
    Window owner;
    Window requestor;
    Atom selection;
    Atom target;
    Atom property;
    Time time;
}

/// SelectionClear -- another app just took ownership of a selection we
/// used to own.
struct XSelectionClearEvent
{
    int type;
    c_ulong serial;
    Bool send_event;
    Display* display;
    Window window;
    Atom selection;
    Time time;
}

/// Matches FLTK's `XEvent` union exactly in spirit: only the
/// members this port actually reads are named, but `pad` reserves the
/// same total size as the real union (24 `long`s) so this can be
/// passed to XNextEvent()/etc. safely regardless of which event type
/// comes back.
union XEvent
{
    int type;
    XAnyEvent xany;
    XExposeEvent xexpose;
    XConfigureEvent xconfigure;
    XClientMessageEvent xclient;
    XKeyEvent xkey;
    XButtonEvent xbutton;
    XMotionEvent xmotion;
    XCrossingEvent xcrossing;
    XPropertyEvent xproperty;
    XKeymapEvent xkeymap;
    XSelectionEvent xselection;
    XSelectionRequestEvent xselectionrequest;
    XSelectionClearEvent xselectionclear;
    c_long[24] pad;
}

// ---------------------------------------------------------------------
// Constants (X11/X.h)
// ---------------------------------------------------------------------

enum Bool True = 1;
enum Bool False = 0;
enum XID None = 0;

enum c_long KeyPressMask = 1L << 0;
enum c_long KeyReleaseMask = 1L << 1;
enum c_long ButtonPressMask = 1L << 2;
enum c_long ButtonReleaseMask = 1L << 3;
enum c_long EnterWindowMask = 1L << 4;
enum c_long LeaveWindowMask = 1L << 5;
enum c_long PointerMotionMask = 1L << 6;
/// Not selected for its own separate event -- per the X11 protocol, a
/// window selecting this mask gets a `KeymapNotify` event automatically
/// generated right after any `EnterNotify`/`FocusIn` it receives,
/// carrying the full 256-key held-state bitmask. See
/// `fl.platform_x11`'s `case KeymapNotify:` handling.
enum c_long KeymapStateMask = 1L << 14;
enum c_long ExposureMask = 1L << 15;
enum c_long StructureNotifyMask = 1L << 17;
enum c_long FocusChangeMask = 1L << 21;
enum c_long SubstructureNotifyMask = 1L << 19;
enum c_long SubstructureRedirectMask = 1L << 20;
enum c_long PropertyChangeMask = 1L << 22;

enum int PropertyNewValue = 0;
enum int PropertyDelete = 1;
enum c_ulong AnyPropertyType = 0;
enum int Success = 0;

enum int KeyPress = 2;
enum int KeyRelease = 3;
enum int ButtonPress = 4;
enum int ButtonRelease = 5;
enum int MotionNotify = 6;
enum int EnterNotify = 7;
enum int LeaveNotify = 8;
enum int FocusIn = 9;
enum int FocusOut = 10;
enum int KeymapNotify = 11;
enum int Expose = 12;
enum int MapNotify = 19;
enum int ConfigureNotify = 22;
enum int SelectionClear = 29;
enum int SelectionRequest = 30;
enum int SelectionNotify = 31;
enum int PropertyNotify = 28;
enum int ClientMessage = 33;

/// Predefined atoms (X11/Xatom.h) -- these are fixed, well-known atom
/// values baked into the X11 protocol itself (no XInternAtom() round
/// trip needed, unlike e.g. `CLIPBOARD`/`UTF8_STRING`/`TARGETS`, which
/// fl.platform_x11 interns at display-open time same as its other
/// custom atoms).
enum Atom XA_PRIMARY = 1;
/// Used as `fl.platform_x11`'s dedicated DND-drop conversion property --
/// never requested by an ordinary `paste()`, so `case SelectionNotify:`
/// can tell a DND drop's reply apart from a normal clipboard one by
/// `property == XA_SECONDARY` alone, matching FLTK's own identical
/// discriminator (`Fl_x.cxx`'s `case SelectionNotify:`).
enum Atom XA_SECONDARY = 2;
enum Atom XA_CARDINAL = 6;
enum Atom XA_WM_ICON_NAME = 37;
enum Atom XA_WM_CLASS = 67;
enum Atom XA_WM_NAME = 39;
enum Atom XA_STRING = 31;

/// `XSetWMProperties()`, called with every struct/array argument
/// `null` except `display`/`w` (matching this port's one real use
/// site, `fl.platform_x11.createWindow()`'s "set WM_CLIENT_MACHINE
/// and WM_LOCALE_NAME" call, ported verbatim from FLTK's own
/// identical all-`NULL`-but-those-two-side-effects call in
/// `Fl_x.cxx`) -- so the struct-pointer parameters are typed `void*`
/// rather than binding the real `XTextProperty`/`XSizeHints`/
/// `XWMHints`/`XClassHint` struct layouts this port has no other need
/// for yet. `argv`/`argc` stay real types since passing `0`/`null` for
/// those is just as valid a call shape as omitting the structs.
void XSetWMProperties(Display* display, Window w, void* windowName, void* iconName,
    char** argv, int argc, void* normalHints, void* wmHints, void* classHints);

/// `detail` values for XCrossingEvent (X11/X.h); only `NotifyInferior`
/// is named -- the one this port checks for (see fl.platform_x11's
/// EnterNotify/LeaveNotify handling), same "only what's read" scoping
/// XEvent's own doc comment describes.
enum int NotifyInferior = 2;

/// Xlib's own modifier/button-held bits in XKeyEvent.state/
/// XButtonEvent.state/XMotionEvent.state; NOT the same numbering as
/// fl.enumerations' stateShift/stateCtrl/etc (those are shifted left
/// by 16 -- see fl.platform_x11's event translation for the mapping).
enum uint ShiftMask = 1 << 0;
enum uint LockMask = 1 << 1;
enum uint ControlMask = 1 << 2;
enum uint Mod1Mask = 1 << 3;
enum uint Mod2Mask = 1 << 4;
enum uint Mod3Mask = 1 << 5;
enum uint Mod4Mask = 1 << 6;
enum uint Mod5Mask = 1 << 7;
enum uint Button1Mask = 1 << 8;
enum uint Button2Mask = 1 << 9;
enum uint Button3Mask = 1 << 10;

/// Raw `XButtonEvent.button` value for the middle mouse button --
/// `fl.platform_x11.dnd()`'s synthetic-middle-click fallback for
/// dropping onto a window that isn't XDND-aware at all (old-school X11
/// compatibility trick, ported from `Fl_X11_Screen_Driver::dnd()`).
enum uint Button2 = 2;

enum c_ulong CWBorderPixel = 1L << 3;
enum c_ulong CWBitGravity = 1L << 4;
enum c_ulong CWBackingStore = 1L << 6;
enum c_ulong CWEventMask = 1L << 11;

/// `backing_store` values for XSetWindowAttributes (X11/X.h).
/// `NotUseful` (the default on most real X servers) tells the server
/// never to preserve occluded pixel content on our behalf -- see
/// createWindow()'s own doc comment for why this port sets it
/// explicitly rather than relying on the server's default.
enum int NotUseful = 0;
enum int WhenMapped = 1;
enum int Always = 2;
enum c_ulong CWOverrideRedirect = 1L << 9;
enum c_ulong CWColormap = 1L << 13;

enum int InputOutput = 1;
enum int StaticGravity = 10;
enum int PropModeReplace = 0;
enum int PropModeAppend = 1;
enum Atom XA_ATOM = 4;

alias KeySym = c_ulong;

/// Glyph indices into the classic X cursor font (X11/cursorfont.h),
/// for XCreateFontCursor(). Only the ones fl.platform_x11's
/// setCursor() actually uses are named -- same "only what's used"
/// scoping this file's other constant blocks follow.
enum uint XC_left_ptr = 68;
enum uint XC_tcross = 130;
enum uint XC_watch = 150;
enum uint XC_xterm = 152;
enum uint XC_hand2 = 60;
enum uint XC_question_arrow = 92;
enum uint XC_fleur = 52;
enum uint XC_sb_v_double_arrow = 116;
enum uint XC_sb_h_double_arrow = 108;
enum uint XC_top_right_corner = 136;
enum uint XC_top_side = 138;
enum uint XC_top_left_corner = 134;
enum uint XC_right_side = 96;
enum uint XC_left_side = 70;
enum uint XC_bottom_right_corner = 14;
enum uint XC_bottom_side = 16;
enum uint XC_bottom_left_corner = 12;

/// `flags` bits for XSizeHints (X11/Xutil.h); only the ones this port's
/// sendSizeHints() (fl.platform_x11) actually sets are named -- same
/// "only what's used" scoping this file's other constant blocks follow.
enum c_long USPosition = 1L << 0;
enum c_long PMinSize = 1L << 4;
enum c_long PMaxSize = 1L << 5;
enum c_long PResizeInc = 1L << 6;
enum c_long PAspect = 1L << 7;
enum c_long PWinGravity = 1L << 9;

/// Matches FLTK's `XColor` (X11/Xlib.h) field-for-field -- used by
/// XCreatePixmapCursor() (fl.platform_x11's invisible-cursor support
/// for `CursorShape.none`), which needs two (unused, since a blank
/// bitmap has no actual foreground/background pixels) XColor pointers.
struct XColor
{
    c_ulong pixel;
    ushort red, green, blue;
    byte flags;
    byte pad;
}

/// Matches FLTK's `XSizeHints` (X11/Xutil.h) field-for-field --
/// unlike XEvent, this isn't a variant type, so there's no "only name
/// what's read" simplification to make; the whole struct is the wire
/// layout XSetWMNormalHints() expects.
struct XSizeHints
{
    c_long flags;
    int x, y;
    int width, height;
    int min_width, min_height;
    int max_width, max_height;
    int width_inc, height_inc;

    struct Aspect
    {
        int x, y;
    }

    Aspect min_aspect, max_aspect;
    int base_width, base_height;
    int win_gravity;
}

/// `flags` bits for `XWMHints` (`X11/Xutil.h`); only the ones this
/// port's `createWindow()` actually sets are named, same "only what's
/// used" scoping `XSizeHints`'s own flags block above follows.
enum c_long InputHint = 1L << 0;
enum c_long StateHint = 1L << 1;

/// `initial_state` values for `XWMHints` (`X11/Xutil.h`); only the two
/// states this port's `createWindow()` can request are named
/// (`WithdrawnState`, value `0`, has no caller yet).
enum int NormalState = 1;
enum int IconicState = 3;

/// Matches FLTK's `XWMHints` (`X11/Xutil.h`) field-for-field --
/// the wire layout `XSetWMHints()` expects. Backs `createWindow()`'s
/// `InputHint` (WM input-focus negotiation -- tells the window manager
/// this port relies on it to call `XSetInputFocus()` rather than the
/// `WM_TAKE_FOCUS` protocol, matching FLTK's own unconditional
/// `hints->input = True` every top-level window gets). The icon/window-
/// group fields have no real caller yet (this port's `setIcons()` uses
/// the modern `_NET_WM_ICON` property instead of the legacy
/// `icon_pixmap` this struct also carries), but are still declared so
/// the struct's layout matches Xlib's exactly.
struct XWMHints
{
    c_long flags;
    Bool input;
    int initial_state;
    Pixmap icon_pixmap;
    Window icon_window;
    int icon_x, icon_y;
    Pixmap icon_mask;
    XID window_group;
}

XWMHints* XAllocWMHints();
int XSetWMHints(Display* display, Window w, XWMHints* hints);

alias VisualID = c_ulong;

/// `XVisualInfo.c_class` values (`X11/X.h`) -- only `StaticColor`/
/// `TrueColor` are actually tested anywhere in this port
/// (`fl.platform_x11.testVisual()`, matching FLTK's own
/// non-`USE_COLORMAP` build path), the rest are here for completeness/
/// `list_visuals.d`'s `classNames` lookup.
enum int StaticGray  = 0;
enum int GrayScale   = 1;
enum int StaticColor = 2;
enum int PseudoColor = 3;
enum int TrueColor   = 4;
enum int DirectColor = 5;

/// `X11/Xutil.h`'s real, field-accessible `XVisualInfo` -- unlike
/// `Display`/`Visual`/`Screen` above, this one is meant to be read
/// field-by-field by callers (that's its entire purpose), so it's not
/// treated as opaque. Field names mix FLTK's raw C spelling
/// (`visualid`/`screen`/`depth`) with camelCase for the three mask
/// fields and `c_class` in place of the reserved word `class` --
/// matches `source/test/list_visuals.d`/`image.d`/`tiled_image.d`
/// (transliterated from `test/list_visuals.cxx` et al. before these
/// bindings existed, already committed to this exact spelling).
struct XVisualInfo
{
    Visual* visual;
    VisualID visualid;
    int screen;
    uint depth;
    int c_class;
    c_ulong redMask;
    c_ulong greenMask;
    c_ulong blueMask;
    int colormapSize;
    int bitsPerRgb;
}

/// `X11/Xlib.h`'s `XPixmapFormatValues`, backing `XListPixmapFormats()`
/// -- used by `list_visuals.d` to look up each visual's actual
/// bits-per-pixel by matching `depth`.
struct XPixmapFormatValues
{
    int depth;
    int bitsPerPixel;
    int scanlinePad;
}

/// `VisualIDMask` (`X11/Xutil.h`), the only `XVisualInfo` template-match
/// bit this port needs -- selects by `visualid` alone, matching every
/// real call site here (`XGetVisualInfo(d, VisualIDMask, &templt, ...)`,
/// both in `Fl_x.cxx`'s own `open_display_()` and the `-v <visid>`
/// diagnostic path `image.cxx`/`tiled_image.cxx` share).
enum c_long VisualIDMask = 0x1;

/// `AllocNone` (`X11/X.h`) -- the `alloc` argument `XCreateColormap()`
/// always uses throughout this port (matching FLTK: a fresh,
/// unshared colormap with no pre-allocated entries).
enum int AllocNone = 0;

// ---------------------------------------------------------------------
// Functions
// ---------------------------------------------------------------------

Display* XOpenDisplay(const(char)* displayName);
int XCloseDisplay(Display* display);

/// The display-name Xlib would have tried, for an error message after
/// `XOpenDisplay()` returns `null` -- matches FLTK's own
/// `XDisplayName(dname)` use in `open_display()`'s failure path
/// (`Fl_x.cxx`, `list_visuals.cxx`'s standalone `fl_open_display()`).
const(char)* XDisplayName(const(char)* string);

Atom XInternAtom(Display* display, const(char)* atomName, Bool onlyIfExists);

int XDefaultScreen(Display* display);
Visual* XDefaultVisual(Display* display, int screenNumber);
int XDefaultDepth(Display* display, int screenNumber);
Colormap XDefaultColormap(Display* display, int screenNumber);
Window XRootWindow(Display* display, int screenNumber);

/// Enumerates every visual the X server offers matching `vinfoTemplate`
/// (filtered by the bits set in `vinfoMask`, e.g. `VisualIDMask`) --
/// backs `Fl::visual()`'s real visual search (`fl.platform_x11.
/// setVisual()`) and `list_visuals.d`'s diagnostic dump. Result must be
/// freed with `XFree()`.
XVisualInfo* XGetVisualInfo(Display* display, c_long vinfoMask,
    XVisualInfo* vinfoTemplate, int* nitemsReturn);

/// The `VisualID` component of `XVisualInfo.visualid` for a given
/// already-open `Visual*` -- backs `list_visuals.d`'s "(default
/// visual)" marker and `fl.platform_x11.openDisplay()`'s own
/// construction of `fl_visual` to match the display's default `Visual`.
VisualID XVisualIDFromVisual(Visual* visual);

/// Every pixmap depth/bits-per-pixel/scanline-pad combination the
/// server supports -- `list_visuals.d` cross-references this against
/// each `XVisualInfo.depth` to print real bits-per-pixel. Result must
/// be freed with `XFree()`.
XPixmapFormatValues* XListPixmapFormats(Display* display, int* countReturn);

/// Creates a new, unshared colormap for `visual` -- backs
/// `fl.platform_x11.setVisual()` (a real, non-default visual found a
/// deeper match) and the `-v <visid>` diagnostic path in
/// `image.d`/`tiled_image.d`.
Colormap XCreateColormap(Display* display, Window w, Visual* visual, int alloc);

/// Only needed for sendSizeHints()'s "guess a value for the maximum
/// dimension the caller didn't constrain" fallback (see that function's
/// doc comment) -- FLTK reaches this same information through
/// `Fl::w()`/`Fl::h()` (Fl_Screen_Driver), not ported here since
/// nothing else in this port needs the wider screen-geometry API yet.
int XDisplayWidth(Display* display, int screenNumber);
int XDisplayHeight(Display* display, int screenNumber);

/// Physical size, in millimeters, of screen `screenNumber` -- backs
/// `fl.core.screenDpi()` (`Fl::screen_dpi()`, `Fl_X11_Screen_Driver::
/// screen_dpi()`'s non-XRandR fallback path).
int XDisplayWidthMM(Display* display, int screenNumber);
int XDisplayHeightMM(Display* display, int screenNumber); /// ditto

/// Bitmask returned by `XParseGeometry()` -- which of x/y/width/height
/// were actually present in the parsed string, and whether x/y were
/// negative (offset from the right/bottom edge rather than the left/top).
enum int XValue = 0x0001;
enum int YValue = 0x0002; /// ditto
enum int WidthValue = 0x0004; /// ditto
enum int HeightValue = 0x0008; /// ditto
enum int XNegative = 0x0010; /// ditto
enum int YNegative = 0x0020; /// ditto

/// Parses a standard X geometry string ("WxH+X+Y", any component
/// optional) -- a pure string parser, no `Display*` needed, always part
/// of libX11. Backs `fl.core.arg()`'s `-geometry` switch and
/// `fl.window.Window.show(string[])`'s consumption of it (`Fl::args()`/
/// `Fl_Window::show(int,char**)`, `src/Fl_arg.cxx`) -- FLTK reaches
/// this through `Fl::screen_driver()->XParseGeometry()` since Windows/
/// macOS have no Xlib to call directly; this port only targets X11, so
/// it's bound and called directly instead.
int XParseGeometry(const(char)* parsestring, int* x, int* y, uint* width, uint* height);

/// Iconifies (minimizes) window `w`, per ICCCM (a `WM_CHANGE_STATE`
/// client message to the root window, handled by the window manager).
/// Backs `fl.window.Window.iconize()` (`XIconifyWindow()`,
/// `Fl_X11_Window_Driver::iconize()`) -- a single standard Xlib call,
/// no protocol details to replicate here.
Status XIconifyWindow(Display* display, Window w, int screenNumber);

Window XCreateWindow(Display* display, Window parent, int x, int y,
    uint width, uint height, uint borderWidth, int depth, uint class_,
    Visual* visual, c_ulong valueMask, XSetWindowAttributes* attributes);
int XDestroyWindow(Display* display, Window w);

int XMapWindow(Display* display, Window w);

/// Unmaps `w` without destroying it -- the X11-protocol half of
/// `Fl_X11_Window_Driver::unmap()`. Used by `fl.platform_x11.
/// unmapWindow()` to hide a subwindow in place (its `Fl_X`/
/// `WindowRecord` and real X resource both survive), matching
/// FLTK's real behavior rather than this port's own fallback of
/// fully destroying and later recreating the resource.
int XUnmapWindow(Display* display, Window w);

/// Restacks `w` to the top of its siblings. Most window managers also
/// raise+focus a newly-mapped top-level window automatically, but not
/// unconditionally -- some focus policies (e.g. strict "click to
/// focus" without auto-raise-on-map) leave a freshly created window
/// wherever it falls in the existing stacking order, which can put it
/// entirely behind an already-visible window. Called explicitly after
/// XMapWindow() in createWindow() for exactly that reason.
int XRaiseWindow(Display* display, Window w);
int XSelectInput(Display* display, Window w, c_long eventMask);

int XChangeProperty(Display* display, Window w, Atom property, Atom type,
    int format, int mode, const(ubyte)* data, int numElements);
int XStoreName(Display* display, Window w, const(char)* windowName);
/// Sets WM_TRANSIENT_FOR, telling the window manager that `w` is a
/// transient (dialog-like) window logically owned by `propWindow` --
/// most window managers use this to keep `w` stacked above/with
/// `propWindow` and to position it sensibly. Used by createWindow()
/// for a modal() window, matching FLTK's own make_xid().
int XSetTransientForHint(Display* display, Window w, Window propWindow);
int XSetWMNormalHints(Display* display, Window w, XSizeHints* hints);

/// Claims ownership of a selection (`PRIMARY`/`CLIPBOARD`) for window
/// `w` -- the real equivalent of this port's old in-process-only
/// copy(). Used by fl.platform_x11.setSelectionOwner().
int XSetSelectionOwner(Display* display, Atom selection, Window w, Time time);

/// Asks the selection's current owner (possibly another X application
/// entirely) to convert it to `target` format and deposit the result as
/// property `property` on window `requestor` -- fires a later,
/// asynchronous `SelectionNotify` event with the result, matching
/// FLTK's own real, non-blocking paste() model. Used by
/// fl.platform_x11.requestSelection().
int XConvertSelection(Display* display, Atom selection, Atom target,
    Atom property, Window requestor, Time time);

/// `shape` is one of the `XC_*` glyph indices above.
Cursor XCreateFontCursor(Display* display, uint shape);
int XDefineCursor(Display* display, Window w, Cursor cursor);
int XFreeCursor(Display* display, Cursor cursor);

/// `revert_to` argument values for XSetInputFocus().
enum int RevertToNone = 0;
enum int RevertToPointerRoot = 1; /// ditto
enum int RevertToParent = 2; /// ditto

enum Time CurrentTime = 0;

/// Used by fl.core's simplified grab() to force keyboard events to a
/// menu popup window regardless of window-manager click-to-focus
/// policy -- see that function's own doc comment for why this port
/// doesn't have a real `XGrabKeyboard()` to rely on instead.
int XSetInputFocus(Display* display, Window w, int revertTo, Time time);
int XSync(Display* display, Bool discard);

/// `pointer_mode`/`keyboard_mode` argument values for XGrabPointer()/
/// XGrabKeyboard().
enum int GrabModeSync = 0;
enum int GrabModeAsync = 1; /// ditto

/// Return values for XGrabPointer()/XGrabKeyboard().
enum int GrabSuccess = 0;
enum int AlreadyGrabbed = 1; /// ditto
enum int GrabInvalidTime = 2; /// ditto
enum int GrabNotViewable = 3; /// ditto
enum int GrabFrozen = 4; /// ditto

enum c_long ButtonMotionMask = 1L << 13;

/// Requests exclusive delivery of pointer events to `grabWindow`
/// (system-wide, not just within this app) until XUngrabPointer() is
/// called -- backs fl.core.grab()'s real implementation. `ownerEvents
/// = True` matches FLTK's own call (`Fl_X11_Screen_Driver::grab()`,
/// `Fl_x.cxx`): events that would normally go to one of *this
/// process's own* windows are still delivered there directly (this is
/// why a click on a sibling menu-triggering widget in the same app
/// still reaches it normally, grab or no grab -- fl.menu_bar.d/
/// fl.menu_popup.d handle that case explicitly rather than relying on
/// the grab to intercept it); everything else (other applications, the
/// window manager's own root-window click handling -- e.g. a virtual-
/// desktop-switch gesture) gets redirected to `grabWindow` instead,
/// which is what makes a real grab "exclusive" from the desktop's
/// point of view. `confineTo = None` (no pointer confinement -- the
/// cursor can still move anywhere on screen, matching FLTK).
int XGrabPointer(Display* display, Window grabWindow, Bool ownerEvents,
    uint eventMask, int pointerMode, int keyboardMode, Window confineTo,
    Cursor cursor, Time time);

/// ditto, for keyboard events -- backs fl.core.grab()'s real keyboard
/// delivery, replacing the XSetInputFocus()-based approximation this
/// port used before (see that function's own doc comment/history).
int XGrabKeyboard(Display* display, Window grabWindow, Bool ownerEvents,
    int pointerMode, int keyboardMode, Time time);

int XUngrabPointer(Display* display, Time time);
int XUngrabKeyboard(Display* display, Time time);

/// XErrorEvent/XSetErrorHandler(): needed because XSetInputFocus() is
/// inherently racy against a freshly `XMapWindow()`-ed, window-manager-
/// reparented window (BadMatch if the window isn't yet viewable when
/// the request is processed -- see fl.platform_x11's own doc comment
/// on `installErrorHandler()` for the full explanation). Xlib's
/// default error handler prints the error and calls `exit()`, which
/// would otherwise take the whole process down over what's really
/// just a lost-the-race, safe-to-ignore focus request.
struct XErrorEvent
{
    int type;
    Display* display;
    XID resourceid;
    c_ulong serial;
    ubyte error_code;
    ubyte request_code;
    ubyte minor_code;
}

alias XErrorHandler = extern (C) int function(Display*, XErrorEvent*) @nogc nothrow;
XErrorHandler XSetErrorHandler(XErrorHandler handler);

enum ubyte BadMatch = 8;
enum ubyte X_SetInputFocus = 42;
enum ubyte X_GetImage = 73;

/// Builds a 1-bit bitmap Pixmap directly from packed bit data (8 bits
/// per byte, row-major, LSB first) -- used by fl.platform_x11's
/// invisible-cursor support (`CursorShape.none`) to create a blank
/// (all-zero) source/mask pair for `XCreatePixmapCursor()`, the same
/// technique FLTK's own `cache_pixmap_cursor()` (Fl_x.cxx) uses for
/// its non-Xcursor-library cursor fallback.
Pixmap XCreateBitmapFromData(Display* display, Drawable d, const(ubyte)* data,
    uint width, uint height);
int XFreePixmap(Display* display, Pixmap pixmap);

/// `fg`/`bg` are ignored by the X server for a fully blank (all-zero)
/// source bitmap, the only case this port ever builds one for, but
/// XCreatePixmapCursor() still requires two non-null XColor pointers.
Cursor XCreatePixmapCursor(Display* display, Pixmap source, Pixmap mask,
    XColor* fg, XColor* bg, uint x, uint y);

int XGetWindowAttributes(Display* display, Window w, XWindowAttributes* attrsReturn);
Bool XTranslateCoordinates(Display* display, Window srcW, Window destW,
    int srcX, int srcY, int* destXReturn, int* destYReturn, Window* childReturn);

/// `children_return` must be freed with `XFree()` when `nchildren_return`
/// is nonzero -- used by `fl.platform_x11.decoratedWinSize()` to find a
/// reparenting window manager's own frame window around a top-level
/// window.
Status XQueryTree(Display* display, Window w, Window* rootReturn,
    Window* parentReturn, Window** childrenReturn, uint* nchildrenReturn);

/// Real, application-initiated top-level window geometry changes
/// (`fl.window.Window.resize()`, via `fl.platform_x11.resizeWindow()`).
int XMoveWindow(Display* display, Window w, int x, int y);
int XResizeWindow(Display* display, Window w, uint width, uint height);
int XMoveResizeWindow(Display* display, Window w, int x, int y, uint width, uint height);

int XNextEvent(Display* display, XEvent* eventReturn);
int XPending(Display* display);
/// The X connection's underlying file descriptor -- a real exported
/// function (used here instead of the `ConnectionNumber()` macro,
/// which reaches into `Display`'s private `_XPrivDisplay` layout that
/// this binding deliberately doesn't declare) so fl.platform_x11's
/// event loop can select()/poll() on it alongside the timer queue.
int XConnectionNumber(Display* display);
/// Copies the next queued event into `eventReturn` without removing it
/// from the queue -- used by fl.platform_x11's autorepeat detection to
/// look ahead one event without consuming it unless it turns out to be
/// the fake KeyRelease/KeyPress pair X generates for a held key.
int XPeekEvent(Display* display, XEvent* eventReturn);
int XFlush(Display* display);

/// Real signature returns a function pointer (`int (*)(Display*)`, the
/// previously-installed "after function"); declared returning `void*`
/// here since no caller needs that value, only the synchronous-mode
/// side effect of calling this at all.
void* XSynchronize(Display* display, Bool onoff);
int XBell(Display* display, int percent);

/// Sends a synthetic event to a window (or, with `propagate` false and
/// the Substructure*Mask bits in `eventMask`, to whichever client
/// selected for that mask on the *destination's parent* -- the trick
/// EWMH client messages to the window manager rely on, since the
/// window manager selects SubstructureRedirectMask on the root
/// window, not on our own window). Used by fl.platform_x11's
/// fullscreen support to ask the window manager to toggle
/// _NET_WM_STATE_FULLSCREEN.
int XSendEvent(Display* display, Window w, Bool propagate, c_long eventMask, XEvent* event);

// `values` is always passed null in this port (valuemask 0, "use
// defaults"), so it's typed as a bare pointer rather than defining the
// large XGCValues struct just to never populate it.
GC XCreateGC(Display* display, Drawable d, c_ulong valueMask, void* values);
int XSetForeground(Display* display, GC gc, c_ulong foreground);
int XFillRectangle(Display* display, Drawable d, GC gc, int x, int y, uint width, uint height);
int XDrawRectangle(Display* display, Drawable d, GC gc, int x, int y, uint width, uint height);

/// Copies a rectangular area from one drawable to another (or, for a
/// same-drawable src/dest pair, shifts pixels within it) -- backs
/// fl.draw's fl_scroll(), matching FLTK's own use in
/// Fl_X11_Window_Driver::scroll(). Server-side, no round trip needed
/// unless graphics_exposures is enabled on `gc` (this port explicitly
/// disables it via XSetGraphicsExposures() -- see fl_scroll()'s own
/// doc comment for why).
int XCopyArea(Display* display, Drawable src, Drawable dest, GC gc,
    int srcX, int srcY, uint width, uint height, int destX, int destY);

/// Enables/disables the server generating GraphicsExpose/NoExpose
/// events after an XCopyArea()/XCopyPlane() call on `gc`. This port
/// always disables it (see fl_scroll()'s doc comment) -- bound mainly
/// so that intent is explicit in code rather than relying on Xlib's
/// own default (which is *enabled*).
int XSetGraphicsExposures(Display* display, GC gc, Bool graphicsExposures);
int XDrawLine(Display* display, Drawable d, GC gc, int x1, int y1, int x2, int y2);

/// `line_style`/`cap_style`/`join_style` values for XSetLineAttributes().
/// The full set now, backing fl.draw's real, general-purpose
/// `lineStyle()` (core-roadmap item 10) -- these are raw X11
/// values (e.g. `CapRound = 2`), distinct from fl.enumerations'
/// FLTK-level `capRound = 0x200` bitmask constant that `lineStyle()`
/// decodes into a choice among these.
enum int LineSolid = 0;
enum int LineOnOffDash = 1; /// ditto
enum int CapButt = 1; /// ditto
enum int CapRound = 2; /// ditto
enum int CapProjecting = 3; /// ditto
enum int JoinMiter = 0; /// ditto
enum int JoinRound = 1; /// ditto
enum int JoinBevel = 2; /// ditto

int XSetLineAttributes(Display* display, GC gc, uint lineWidth, int lineStyle,
    int capStyle, int joinStyle);

/// `dashList` is a list of dash/gap lengths in pixels (e.g. `[1, 1]` for
/// a fine dotted line); only meaningful once `XSetLineAttributes()` has
/// set `LineOnOffDash`.
int XSetDashes(Display* display, GC gc, int dashOffset, const(ubyte)* dashList, int n);

/// `angle1`/`angle2` to XDrawArc()/XFillArc() are in 64ths of a degree,
/// counterclockwise from 3 o'clock -- the same convention fl_arc()/
/// fl_pie() document, so callers just multiply degrees by 64, no
/// conversion needed.
int XDrawArc(Display* display, Drawable d, GC gc, int x, int y, uint width, uint height,
    int angle1, int angle2);
int XFillArc(Display* display, Drawable d, GC gc, int x, int y, uint width, uint height,
    int angle1, int angle2);

struct XPoint
{
    short x, y;
}

/// `shape` argument to XFillPolygon(): a hint the server may use to
/// pick a faster fill algorithm. `Complex` (0) makes no assumption
/// about the vertex order/convexity, which is always safe -- the only
/// value drawCheck() (a concave hexagon) passes.
enum int polygonShapeComplex = 0;
/// `shape` argument to XFillPolygon() for a convex polygon (no vertex
/// pair crosses any line joining two other vertices) -- lets the X
/// server use a faster fill algorithm than `Complex`. Matches FLTK's
/// own Fl_Xlib_Graphics_Driver::end_polygon(), used for fl_end_polygon()
/// (fl.dial's/fl.clock's transform-stack vertex-path shapes, all
/// genuinely convex: triangular clock hands, tick-mark rectangles, the
/// dial knob dot).
enum int polygonShapeConvex = 2;
/// `mode` argument to XFillPolygon()/XDrawLines(): each point is an
/// absolute coordinate (as opposed to `CoordModePrevious`'s
/// relative-to-the-last-point scheme, not used by this port).
enum int coordModeOrigin = 0;

int XFillPolygon(Display* display, Drawable d, GC gc, XPoint* points, int npoints,
    int shape, int mode);
int XDrawLines(Display* display, Drawable d, GC gc, XPoint* points, int npoints, int mode);

/// Draws npoints disconnected pixels -- backs fl.draw's endPoints()
/// (core-roadmap item 10, the beginPoints()/vertex()/
/// endPoints() path). Same `mode` convention as XDrawLines()/
/// XFillPolygon() above.
int XDrawPoints(Display* display, Drawable d, GC gc, XPoint* points, int npoints, int mode);

struct XRectangle
{
    short x, y;
    ushort width, height;
}

/// `ordering` argument to XSetClipRectangles(): no assumption about
/// rectangle order -- the only value this port passes (it only ever
/// passes a single rectangle anyway, see fl.draw's clip stack).
enum int clipRectanglesUnsorted = 0;

int XSetClipMask(Display* display, GC gc, Pixmap pixmap);
int XSetClipRectangles(Display* display, GC gc, int clipXOrigin, int clipYOrigin,
    const(XRectangle)* rectangles, int n, int ordering);

/// Sets where a clip mask's own (0,0) lands relative to the drawable's
/// origin -- backs `Fl_Pixmap`'s transparency (`fl.pixmap`'s row):
/// `XSetClipMask()` alone clips to the mask's *shape*, this positions
/// it. Ported from `XSetClipOrigin()` (`X11/Xlib.h`).
int XSetClipOrigin(Display* display, GC gc, int clipXOrigin, int clipYOrigin);

/// Parses a color spec (`#RRGGBB` hex, or an X11 color-database name
/// like `"red"`) against the X server's own name database. Backs
/// `fl.draw.parseColor()`'s fallback for names this port's own
/// headless-testable hex parser doesn't handle -- `fl.pixmap`'s XPM
/// color-table decoding is the real consumer (`FL/fl_draw.H`'s own
/// `fl_parse_color()`, `src/Fl_get_system_colors.cxx`). Ported from
/// `XParseColor()` (`X11/Xlib.h`).
Status XParseColor(Display* display, Colormap colormap, const(char)* spec, XColor* exactDefReturn);

/// `status_in_out` is always passed null in this port (no compose/
/// dead-key support), so it's typed as a bare pointer rather than
/// defining the unused XComposeStatus struct -- same simplification as
/// XCreateGC()'s `values` param.
int XLookupString(XKeyEvent* eventStruct, char* bufferReturn, int bytesBuffer,
    KeySym* keysymReturn, void* statusInOut);

/// index 0 always requests the "unshifted"/level-0 keysym for the key,
/// which is all this port needs (see fl.platform_x11's event
/// translation for why: keysym-matching is meant to be shift-invariant).
KeySym XKeycodeToKeysym(Display* display, uint keycode, int index);

/// Returns a static, X-server-owned string naming a keysym (e.g.
/// XK_Left -> "Left"), or null if the keysym isn't recognized. Backs
/// fl.core's fl_shortcut_label(), matching
/// Fl_X11_Screen_Driver::shortcut_add_key_name()'s use of the same
/// call.
const(char)* XKeysymToString(KeySym keysym);

/// Reads an entry from the X resource database (`~/.Xdefaults`/
/// `~/.Xresources`/server-loaded `RESOURCE_MANAGER` property) --
/// `"program.option"` (falling back to `"program*option"`) or the
/// class-name equivalents. Returns a static, X-library-owned string
/// (never freed by the caller, same convention as `XKeysymToString()`
/// above), or `null` if no matching entry exists. Backs
/// `fl.core.getSystemScheme()`'s resource-database fallback.
const(char)* XGetDefault(Display* display, const(char)* program, const(char)* option);

alias KeyCode = ubyte;

/// The reverse of XKeycodeToKeysym() -- maps a keysym back to whatever
/// keycode the server's current mapping produces it from (0 if none).
/// Backs Fl::event_key(int)/Fl::get_key(int)'s keysym-to-keycode step,
/// matching Fl_X11_Screen_Driver::event_key()'s own use of the same call.
KeyCode XKeysymToKeycode(Display* display, KeySym keysym);

/// Fills a 32-byte bit vector (one bit per keycode) with the X
/// server's current keyboard state -- backs Fl::get_key(int), matching
/// Fl_X11_Screen_Driver::get_key()'s own use of the same call.
int XQueryKeymap(Display* display, ubyte[32]* keysReturn);

/// Backs Fl::get_mouse(), matching Fl_X11_Screen_Driver::get_mouse()'s
/// own use of the same call. `mask_return`'s bits use Xlib's own
/// Button1Mask/etc. encoding, not fl.core's translated event-state
/// bits -- callers wanting the latter should go through
/// translateState() instead (see fl.platform_x11.getMouse()).
Bool XQueryPointer(Display* display, Window w, Window* rootReturn, Window* childReturn,
    int* rootXReturn, int* rootYReturn, int* winXReturn, int* winYReturn, uint* maskReturn);

// ---------------------------------------------------------------------
// XIM / XIC -- real input-method support (core-roadmap item 9)
// ---------------------------------------------------------------------

/// Tells Xlib to use the system's default locale-dependent input
/// method modifiers -- called once, before opening the display, in
/// FLTK's own `Fl_X11_Screen_Driver::open_display_platform()`
/// (paired with a `setlocale(LC_CTYPE, "")` call this port makes via
/// `core.stdc.locale` directly rather than a binding here, since that's
/// a plain C standard library function, not an Xlib one).
const(char)* XSetLocaleModifiers(const(char)* modifierList);

/// Opens an input method connection -- the direct equivalent of
/// FLTK's `XOpenIM(fl_display, NULL, NULL, NULL)` call in
/// `Fl_X11_Screen_Driver::init_xim()`. `rdb`/`resName`/`resClass` are
/// always passed `null` in this port, matching FLTK exactly (they
/// exist for resource-database-driven IM configuration this port has
/// no other use for).
XIM XOpenIM(Display* display, void* rdb, const(char)* resName, const(char)* resClass);

Status XCloseIM(XIM im);

/// Creates an input context. Deliberately narrower than FLTK's own
/// `XCreateIC()` call (which is a variadic name/value-pair list,
/// negotiated against whichever preedit/status styles the input method
/// actually supports via a separate `XGetIMValues()`/`XIMStyles` query)
/// -- this port always requests the plain `XIMPreeditNothing |
/// XIMStatusNothing` style directly (no on-screen preedit text or
/// status/candidate area at all), which is also FLTK's own
/// fallback when none of its fancier styles are available. Real
/// composition (dead keys, CJK input via `Xutf8LookupString()`) works
/// identically either way -- the preedit/status styles only affect
/// whether the input method draws its own inline UI, which needs a
/// widget to report a text-cursor "spot" via `XNSpotLocation`
/// (FLTK's `fl_set_spot()`, called from individual text-editing
/// widgets) for positioning; no widget in this port calls that yet
/// (out of scope for this core-layer pass, core-roadmap item 9),
/// so there'd be nothing to correctly position an inline preedit
/// against anyway. `name1`/`style`/`term` matches the exact 1-pair
/// variadic call shape this port actually makes
/// (`XCreateIC(im, XNInputStyle, style, NULL)`).
XIC XCreateIC(XIM im, const(char)* name1, XIMStyle style, void* term);

/// A second, wider `XCreateIC()` overload for the one other call shape
/// this port makes (see `fl.platform_x11.newIc()`, ported from
/// FLTK's `Fl_X11_Screen_Driver::new_ic()`): creating an IC with
/// `XIMPreeditPosition | XIMStatusNothing` style needs a third
/// name/value pair, `XNPreeditAttributes`, supplying the nested
/// spot-location/font-set list `XVaCreateNestedList()` built. Both
/// declarations bind the same underlying (genuinely C-variadic)
/// `XCreateIC` symbol -- D resolves which one to call per call site,
/// same technique as this file's other multi-shape Xlib bindings.
XIC XCreateIC(XIM im, const(char)* name1, XIMStyle style,
    const(char)* name2, void* val2, void* term);

void XDestroyIC(XIC ic);

/// Sets 2 name/value pairs then a `NULL` terminator -- matches this
/// port's one actual call shape (`XSetICValues(ic, XNFocusWindow, w,
/// XNClientWindow, w, NULL)`, re-pointing an existing IC at a new
/// focus/client window, ported from `Fl_X11_Screen_Driver::
/// xim_activate()`), not FLTK's fully general variadic API.
void XSetICValues(XIC ic, const(char)* name1, Window val1, const(char)* name2, Window val2, void* term);

/// A second `XSetICValues()` overload for updating a single nested-list
/// attribute -- this port's other call shape is
/// `XSetICValues(ic, XNPreeditAttributes, preeditAttr, NULL)` (see
/// `fl.platform_x11.setSpot()`). Distinguished from the overload above
/// by `val1`'s type (`void*` here vs. `Window` there) -- both bind the
/// same underlying variadic `XSetICValues` symbol.
void XSetICValues(XIC ic, const(char)* name1, void* val1, void* term);

void XSetICFocus(XIC ic);
void XUnsetICFocus(XIC ic);

/// Resets an input context's composition state -- the direct
/// equivalent of FLTK's `Fl_X11_Screen_Driver::compose_reset()`'s
/// `XmbResetIC(xim_ic)` call (still `Xmb`-prefixed even though this
/// port otherwise only ever reads UTF-8 out of an IC via
/// `Xutf8LookupString()` below -- there's no `Xutf8ResetIC()`, `XmbResetIC()`
/// is the real Xlib name regardless of which lookup function pairs with it).
void XmbResetIC(XIC ic);

/// Lets the input method intercept a raw event before this port's own
/// translation runs -- e.g. for a CJK input method's own candidate-
/// selection UI to consume clicks/keys meant for it, not the
/// application. Returns `True` if the event was fully consumed (this
/// port must not process it any further). Ported from `fl_handle()`'s
/// own `if (xim_ic && XFilterEvent(...)) return 1;` (`Fl_x.cxx`).
Bool XFilterEvent(XEvent* event, Window w);

/// The real, UTF-8-aware, input-method-aware replacement for
/// `XLookupString()` -- the direct equivalent of FLTK's
/// `Xutf8LookupString()` (called through FLTK's own `#define
/// XUtf8LookupString Xutf8LookupString` compatibility alias in
/// `Xutf8.h`, itself just the real Xlib function; ported here under
/// its real name). Composes dead-key sequences and full input-method
/// (CJK, etc.) text transparently, producing the final composed
/// character(s) as UTF-8 in `buffer` once a sequence completes --
/// nothing else in this port needs to track compose state itself
/// (confirmed against FLTK: `Fl::compose_state` is never set to
/// non-zero anywhere in the real X11 driver either, only in the
/// Windows one -- see `fl.core.compose()`'s own doc comment).
int Xutf8LookupString(XIC ic, XKeyEvent* event, char* bufferReturn,
    int bytesBuffer, KeySym* keysymReturn, Status* statusReturn);

/// `XIMPreeditNothing`/`XIMStatusNothing`/`XIMPreeditPosition`
/// (`X11/Xlib.h`) -- the only input-style bits this port ever
/// requests. `XIMPreeditPosition | XIMStatusNothing` (real "over the
/// spot" preedit positioning, see `fl.platform_x11.newIc()`/
/// `setSpot()`) is used when the input method supports it;
/// `XIMPreeditNothing | XIMStatusNothing` remains the fallback,
/// matching FLTK's own `new_ic()` exactly (this port never
/// requests `XIMStatusArea` at all -- see that function's own doc
/// comment for why).
enum XIMStyle XIMPreeditNothing = 0x0008;
enum XIMStyle XIMPreeditPosition = 0x0004;
enum XIMStyle XIMStatusNothing = 0x0400;

/// Opaque per-locale font-set handle (`X11/Xlib.h`'s `typedef struct
/// _XOC *XFontSet`) -- this port never reads its fields, only creates
/// one (`XCreateFontSet()`) to satisfy `XNFontSet`'s requirement inside
/// a preedit attribute list (see `newIc()`), matching FLTK's own
/// `-misc-fixed-*` generic-fallback approach exactly (real per-font
/// XLFD lookup is skipped FLTK too under Xft/Cairo -- see that
/// function's own doc comment).
alias XFontSet = void*;

/// Opaque nested-attribute-list handle returned by
/// `XVaCreateNestedList()` (`X11/Xlib.h`'s `typedef void *
/// XVaNestedList`) and consumed by the `XNPreeditAttributes`-carrying
/// `XCreateIC()`/`XSetICValues()` calls.
alias XVaNestedList = void*;

/// The `XIMStyles` an input method supports (`X11/Xlib.h`) -- returned
/// by `XGetIMValues(im, XNQueryInputStyle, &styles, NULL)`, walked by
/// `newIc()` to decide whether `XIMPreeditPosition` is available.
struct XIMStyles
{
    ushort count_styles;
    XIMStyle* supported_styles;
}

/// Queries an input method's own values -- this port's one call shape
/// is `XGetIMValues(im, XNQueryInputStyle, &styles, NULL)` (querying
/// the input method's supported preedit/status styles). Returns `null`
/// on success, matching Xlib's general "returns the name of the first
/// unrecognized/failed attribute, or NULL if every one succeeded"
/// *Values() convention.
const(char)* XGetIMValues(XIM im, const(char)* name1, XIMStyles** val1, void* term);

/// Creates a font set for `baseFontNameList` (an XLFD pattern, e.g.
/// `"-misc-fixed-*"`) in the current locale -- backs `newIc()`'s
/// `XNFontSet` preedit attribute. `missingCharsetList`/
/// `missingCharsetCount`/`defString` are always passed through
/// (matching FLTK) and the missing-charset list freed via
/// `XFreeStringList()` right afterward, same as FLTK -- this port
/// never inspects what's actually missing, matching FLTK's own
/// `-misc-fixed-*` fallback not checking either.
XFontSet XCreateFontSet(Display* display, const(char)* baseFontNameList,
    char*** missingCharsetList, int* missingCharsetCount, char** defString);

void XFreeFontSet(Display* display, XFontSet fontSet);

/// Frees the missing-charset list `XCreateFontSet()` may allocate.
void XFreeStringList(char** list);

/// Builds a `NULL`-terminated nested name/value attribute list for use
/// as an `XNPreeditAttributes` value -- this port's one call shape is
/// `XVaCreateNestedList(0, XNSpotLocation, &rect, XNFontSet, fs,
/// NULL)`. The leading `int` parameter is `XVaCreateNestedList()`'s own
/// always-`0` first argument (a real Xlib API quirk -- FLTK passes
/// literal `0` at every call site too, not a value this port invented
/// meaning for).
XVaNestedList XVaCreateNestedList(int dummy, const(char)* name1, void* val1,
    const(char)* name2, void* val2, void* term);

/// `Xutf8LookupString()`'s `status_return` values (`X11/Xlib.h`).
/// `XBufferOverflow` means `buffer` was too small -- retry with a
/// larger one, matching FLTK's own retry loop.
enum int XBufferOverflow = -1;
enum int XLookupNone = 1;
enum int XLookupChars = 2;
enum int XLookupKeySym = 3;
enum int XLookupBoth = 4;

/// XIC attribute name strings (`X11/Xlib.h`'s `#define XN*` macros --
/// plain C string constants, not integer flags).
enum string XNInputStyle = "inputStyle";
enum string XNFocusWindow = "focusWindow";
enum string XNClientWindow = "clientWindow";
enum string XNQueryInputStyle = "queryInputStyle";
enum string XNPreeditAttributes = "preeditAttributes";
enum string XNSpotLocation = "spotLocation";
enum string XNFontSet = "fontSet";

/// Reads a window property -- backs the `PropertyNotify` handling
/// that recovers `_NET_WM_STATE`'s current atom list (fullscreen/
/// maximized/hidden), matching FLTK's own use in `get_xwinprop()`
/// (`Fl_x.cxx`). `prop_return` comes back as a raw `void*` (the same
/// simplification as `XCreateGC()`'s unused `values` param and
/// `XLookupString()`'s `statusInOut`) since this port only ever reads
/// it as an `Atom[]` (`format == 32`) -- callers cast it themselves;
/// must be freed with `XFree()` regardless of `nitemsReturn`.
int XGetWindowProperty(Display* display, Window w, Atom property, c_long longOffset,
    c_long longLength, Bool delete_, Atom reqType, Atom* actualTypeReturn,
    int* actualFormatReturn, c_ulong* nitemsReturn, c_ulong* bytesAfterReturn,
    void** propReturn);

/// Frees server-allocated data Xlib itself handed back (e.g.
/// XGetWindowProperty()'s prop_return) -- generic `void*` since this
/// port only ever calls it on that one kind of buffer so far.
int XFree(void* data);

// ---------------------------------------------------------------------
// Image drawing (backs fl.image's real Fl_RGB_Image/Fl_Bitmap draw()) --
// see fl.draw's drawImage()/create_bitmask()-equivalent for how
// these get used.
// ---------------------------------------------------------------------

/// Direct port of Xlib.h's `XImage` struct -- field order copied
/// verbatim from the real header (see fl.platform_x11's own
/// `XErrorEvent` note on why this matters: same-fields-wrong-order
/// compiles fine but silently misreads memory). Only ever used as a
/// stack-allocated, manually-filled-in struct passed to `XPutImage()`/
/// `XGetImage()`-style calls -- never through `XCreateImage()`/
/// `XDestroyImage()` (matching FLTK's own `Fl_Xlib_Graphics_Driver_
/// image.cxx`, which keeps one `static XImage xi;` for the same
/// purpose and never destroys it either), so the trailing `f` function-
/// pointer table is never populated or called -- its 6 pointer-sized
/// fields exist here purely to keep the struct's total size/layout
/// correct for the fields X actually reads.
struct XImage
{
    int width, height;
    int xoffset;
    int format;
    char* data;
    int byte_order;
    int bitmap_unit;
    int bitmap_bit_order;
    int bitmap_pad;
    int depth;
    int bytes_per_line;
    int bits_per_pixel;
    c_ulong red_mask, green_mask, blue_mask;
    void* obdata;
    void*[6] f; // funcs: create_image/destroy_image/get_pixel/put_pixel/sub_image/add_pixel
}

/// `XImage.format` values (`X11/X.h`). This port only ever uses `ZPixmap`.
enum int XYBitmap = 0;
enum int XYPixmap = 1;
enum int ZPixmap = 2;

/// `XImage.byte_order`/`bitmap_bit_order` values (`X11/X.h`).
enum int LSBFirst = 0;
enum int MSBFirst = 1;

/// Queries the client-side (Xlib) byte order used for image data --
/// the real function form of FLTK's `ImageByteOrder()` macro
/// (`X11/Xlib.h`), matching this module's own stated preference for
/// function forms over macros (see the module's top comment).
int XImageByteOrder(Display* display);

/// Sends image data to a drawable. Ported from `XPutImage()`
/// (`X11/Xlib.h`).
int XPutImage(Display* display, Drawable d, GC gc, XImage* image,
    int srcX, int srcY, int destX, int destY, uint width, uint height);

/// Reads pixel data back from a drawable -- backs `Fl_Pixmap`'s
/// manual alpha-compositing fallback (`fl.image`'s row, no
/// `XRENDER`/hardware-alpha-compositing binding exists in this port).
/// Ported from `XGetImage()` (`X11/Xlib.h`). Returns an `XImage*` the
/// caller must free with `XDestroyImage()` -- unlike the stack-
/// allocated `XImage` above, this one really is server/library-
/// managed, since Xlib itself allocates `->data` and populates a real
/// `f.destroy_image` to free it correctly.
XImage* XGetImage(Display* display, Drawable d, int x, int y, uint width,
    uint height, c_ulong planeMask, int format);

/// Frees an `XImage*` obtained from `XGetImage()` (calls through its
/// own `f.destroy_image`). Never called on the stack-allocated,
/// manually-built `XImage` this module also uses for `XPutImage()` --
/// see that struct's own doc comment for why.
int XDestroyImage(XImage* image);

/// Queries a drawable's actual size/position -- ported from
/// `XGetGeometry()` (`X11/Xlib.h`). Backs `fl.draw.readPixelsFromDrawable()`'s
/// clamp-to-drawable-bounds step (matching FLTK's own
/// `Fl_X11_Screen_Driver::read_win_rectangle()`, which clamps its
/// request against the target window's own `w()`/`h()` before ever
/// calling `XGetImage()` -- see that function's own doc comment).
Status XGetGeometry(Display* display, Drawable d, Window* rootReturn,
    int* xReturn, int* yReturn, uint* widthReturn, uint* heightReturn,
    uint* borderWidthReturn, uint* depthReturn);

/// All-ones plane mask -- the usual `AllPlanes` argument to
/// `XGetImage()` (`X11/X.h`), meaning "read every plane," matching
/// FLTK's own use.
enum c_ulong AllPlanes = ~0UL;

/// GC fill-style state used for `Fl_Bitmap`'s stipple-based draw
/// (`XSetFillStyle()`/`FillStippled`/`FillSolid`, `X11/X.h`). Values
/// verified against `/usr/include/X11/X.h`. `FillStippled` is `2`;
/// `3` is `FillOpaqueStippled` -- paints the GC's *background* pixel
/// wherever a stipple bit is 0, instead of leaving it transparent,
/// which is why a Bitmap rendered as a solid black square: foreground
/// and background were both black in the normal case, and only
/// visibly diverged -- as a black/gray "negative" -- once
/// `inactive()` dimmed the foreground alone).
enum int FillSolid = 0;
enum int FillStippled = 2;
enum int FillOpaqueStippled = 3;

int XSetStipple(Display* display, GC gc, Pixmap stipple);
int XSetTSOrigin(Display* display, GC gc, int ts_x_origin, int ts_y_origin);
int XSetFillStyle(Display* display, GC gc, int fill_style);
Pixmap XCreatePixmap(Display* display, Drawable d, uint width, uint height, uint depth);
