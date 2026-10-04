/*
 * Ported from FL/Enumerations.H (FLTK 1.5.0, ~/Repositories/fltk).
 *
 * Only the subset needed by fl.widget so far is ported; the rest of
 * Enumerations.H (cursors, orientation, fd-watch flags, etc.) will be
 * added as the modules that need them are ported.
 *
 * Convention used throughout this port: closed, non-combinable tag sets
 * (Boxtype, Labeltype, Event, CallbackReason) become real D `enum`s.
 * Open bitmask/index sets that FLTK also expresses as a plain
 * integer typedef plus free constants (Align, Color, Font, When, Damage)
 * stay as an alias plus manifest constants, so combining values with `|`
 * doesn't require casts back to the named type.
 */
module fl.enumerations;

// ---------------------------------------------------------------------
// FL_VERSION / FL_API_VERSION / FL_ABI_VERSION
// ---------------------------------------------------------------------
//
// Ported from Enumerations.H, but reporting *fldtk's own* version
// (1.0.0), not the FLTK release it happens to be ported from at any
// given time (currently 1.5.0, tracked separately -- see CLAUDE.md's
// "Reference source" section and `fltk_version.dat` in the FLTK
// checkout). **Corrected 2026-09-04** (user-reported: `test/fltk-
// versions.d` looked "inconsistent" against fldtk's and Fluid's own
// identity because this used to literally echo the FLTK checkout's
// version number, 1.5.0, as if fldtk itself were release 1.5.0 of
// something -- it isn't; it's a separate, complete reimplementation,
// versioned on its own terms starting at 1.0.0): these three constants
// are fldtk's own semantic version, independent of whichever FLTK
// release a given module's own doc comment says it was ported from.
// Since this port compiles everything into one D module (no separate
// header-vs-shared-library skew the way a C/C++ program linking an old
// .so against new headers could have), fl.core.version_()/
// apiVersion()/abiVersion() below always return these same values --
// there's no real "header says X, library says Y" case to detect here,
// but the constants and query functions are ported anyway for call-site
// compatibility (`test/fltk-versions.cxx`'s whole point is comparing
// them, which now trivially always matches).
enum int FL_MAJOR_VERSION = 1;
enum int FL_MINOR_VERSION = 0;
enum int FL_PATCH_VERSION = 0;
enum double FL_VERSION = FL_MAJOR_VERSION + FL_MINOR_VERSION * 0.01 + FL_PATCH_VERSION * 0.0001;
enum int FL_API_VERSION = FL_MAJOR_VERSION * 10000 + FL_MINOR_VERSION * 100 + FL_PATCH_VERSION;
enum int FL_ABI_VERSION = FL_API_VERSION;

// ---------------------------------------------------------------------
// Fl_Align
// ---------------------------------------------------------------------

alias Align = uint;

enum : Align
{
    alignCenter         = 0x0000,
    alignTop            = 0x0001,
    alignBottom         = 0x0002,
    alignLeft           = 0x0004,
    alignRight          = 0x0008,
    alignInside         = 0x0010,
    alignTextOverImage  = 0x0020,
    alignImageOverText  = 0x0000,
    alignClip           = 0x0040,
    alignWrap           = 0x0080,
    alignImageNextToText = 0x0100,
    alignTextNextToImage = 0x0120,
    alignImageBackdrop  = 0x0200,

    alignTopLeft        = alignTop | alignLeft,
    alignTopRight       = alignTop | alignRight,
    alignBottomLeft     = alignBottom | alignLeft,
    alignBottomRight    = alignBottom | alignRight,

    alignLeftTop        = 0x0007,
    alignRightTop       = 0x000b,
    alignLeftBottom     = 0x000d,
    alignRightBottom    = 0x000e,

    /// Same as alignCenter, kept for back compatibility.
    alignNowrap         = 0x0000,
    /// Tests for the top/bottom/left/right bits (including the "magic
    /// value" outside-position combinations above).
    alignPositionMask   = 0x000f,
    /// Tests for the image-alignment bits.
    alignImageMask      = 0x0320,
}

// ---------------------------------------------------------------------
// Fl_Boxtype
// ---------------------------------------------------------------------

enum Boxtype : ubyte
{
    noBox = 0,
    flatBox,
    upBox,
    downBox,
    upFrame,
    downFrame,
    thinUpBox,
    thinDownBox,
    thinUpFrame,
    thinDownFrame,
    engravedBox,
    embossedBox,
    engravedFrame,
    embossedFrame,
    borderBox,
    shadowBox,
    borderFrame,
    shadowFrame,
    roundedBox,
    rshadowBox,
    roundedFrame,
    rflatBox,
    roundUpBox,
    roundDownBox,
    diamondUpBox,
    diamondDownBox,
    ovalBox,
    oshadowBox,
    ovalFrame,
    oflatBox,
    plasticUpBox,
    plasticDownBox,
    plasticUpFrame,
    plasticDownFrame,
    plasticThinUpBox,
    plasticThinDownBox,
    plasticRoundUpBox,
    plasticRoundDownBox,
    gtkUpBox,
    gtkDownBox,
    gtkUpFrame,
    gtkDownFrame,
    gtkThinUpBox,
    gtkThinDownBox,
    gtkThinUpFrame,
    gtkThinDownFrame,
    gtkRoundUpBox,
    gtkRoundDownBox,
    gleamUpBox,
    gleamDownBox,
    gleamUpFrame,
    gleamDownFrame,
    gleamThinUpBox,
    gleamThinDownBox,
    gleamRoundUpBox,
    gleamRoundDownBox,
    oxyUpBox,
    oxyDownBox,
    oxyUpFrame,
    oxyDownFrame,
    oxyThinUpBox,
    oxyThinDownBox,
    oxyThinUpFrame,
    oxyThinDownFrame,
    oxyRoundUpBox,
    oxyRoundDownBox,
    oxyButtonUpBox,
    oxyButtonDownBox,
    freeBoxtype,
    maxBoxtype = 255,
}

/**
 * Conversions between related boxtypes (upBox <-> downBox <->
 * upFrame/downFrame, etc.), ported verbatim from the inline functions
 * in Enumerations.H. These are pure index arithmetic over Boxtype's
 * declared order, not a lookup table -- and, per FLTK's own
 * documented caveat, "if no such version of a given box exists, the
 * behavior is undefined and some random box or frame is returned".
 * That's true here exactly as much as it is FLTK: the arithmetic
 * only lines up cleanly for the well-defined box/frame quadruples
 * (noBox/flatBox, upBox/downBox/upFrame/downFrame, thinUp.../thinDown...,
 * engraved.../embossed..., border.../shadow...); beyond that (most of
 * the plastic/gtk/gleam/oxy schemes) it's the same "garbage in, garbage
 * out" contract FLTK ships, not a gap specific to this port.
 */
Boxtype fl_box(Boxtype b)
{
    return (b < Boxtype.upBox || b % 4 > 1) ? b : cast(Boxtype)(b - 2);
}

/// ditto
Boxtype fl_down(Boxtype b)
{
    return (b < Boxtype.upBox) ? b : cast(Boxtype)(b | 1);
}

/// ditto
Boxtype fl_frame(Boxtype b)
{
    return (b % 4 < 2) ? b : cast(Boxtype)(b + 2);
}

// ---------------------------------------------------------------------
// Fl_Color
// ---------------------------------------------------------------------

alias Color = uint;

enum : Color
{
    foregroundColor  = 0,
    background2Color = 7,
    inactiveColor    = 8,
    selectionColor   = 15,

    gray0  = 32,
    dark3  = 39,
    dark2  = 45,
    dark1  = 47,

    backgroundColor = 49,
    light1 = 50,
    light2 = 52,
    light3 = 54,

    black   = 56,
    red     = 88,
    green   = 63,
    yellow  = 95,
    blue    = 216,
    magenta = 248,
    cyan    = 223,
    darkRed = 72,

    darkGreen   = 60,
    darkYellow  = 76,
    darkBlue    = 136,
    darkMagenta = 152,
    darkCyan    = 140,

    white = 255,

    freeColor    = 16,
    numFreeColor = 16,
    grayRamp     = 32,
    numGray      = 24,
    gray         = backgroundColor,
    colorCube    = 56,
    numRed       = 5,
    numGreen     = 8,
    numBlue      = 5,
}

/// Returns a gray value out of the gray ramp, ported verbatim from the
/// inline `fl_gray_ramp(int)` in Enumerations.H. `i` ranges from 0
/// (black) to `numGray - 1` (white).
Color fl_gray_ramp(int i) { return cast(Color)(i + grayRamp); }

/**
 * The default 256-entry indexed color table, ported verbatim from
 * src/fl_cmap.h (a mechanically-generated file FLTK, "DO NOT EDIT
 * -- must be generated by util/cmap.cxx"; this is a straight
 * transcription, not hand-derived). Each entry packs RGB as
 * 0xRRGGBB00 (matching Fl::get_color()'s documented packing -- the
 * low byte is always 0).
 *
 * Only covers indexed colors (0-255, i.e. Color values that fit in
 * this table). FLTK also supports "free"/packed-RGB colors above
 * this range (any Color value with nonzero bits above the low byte is
 * self-describing RGB, no table lookup needed) -- not handled by this
 * table lookup itself, see fl.draw's fl_color() for where that
 * distinction is actually made.
 */
immutable uint[256] colorTable = [
    0x00000000, 0xff000000, 0x00ff0000, 0xffff0000, 0x0000ff00, 0xff00ff00,
    0x00ffff00, 0xffffff00, 0x55555500, 0xc6717100, 0x71c67100, 0x8e8e3800,
    0x7171c600, 0x8e388e00, 0x388e8e00, 0x00008000, 0xa8a89800, 0xe8e8d800,
    0x68685800, 0x98a8a800, 0xd8e8e800, 0x58686800, 0x9c9ca800, 0xdcdce800,
    0x5c5c6800, 0x9ca89c00, 0xdce8dc00, 0x5c685c00, 0x90909000, 0xc0c0c000,
    0x50505000, 0xa0a0a000, 0x00000000, 0x0d0d0d00, 0x1a1a1a00, 0x26262600,
    0x31313100, 0x3d3d3d00, 0x48484800, 0x55555500, 0x5f5f5f00, 0x6a6a6a00,
    0x75757500, 0x80808000, 0x8a8a8a00, 0x95959500, 0xa0a0a000, 0xaaaaaa00,
    0xb5b5b500, 0xc0c0c000, 0xcbcbcb00, 0xd5d5d500, 0xe0e0e000, 0xeaeaea00,
    0xf5f5f500, 0xffffff00, 0x00000000, 0x00240000, 0x00480000, 0x006d0000,
    0x00910000, 0x00b60000, 0x00da0000, 0x00ff0000, 0x3f000000, 0x3f240000,
    0x3f480000, 0x3f6d0000, 0x3f910000, 0x3fb60000, 0x3fda0000, 0x3fff0000,
    0x7f000000, 0x7f240000, 0x7f480000, 0x7f6d0000, 0x7f910000, 0x7fb60000,
    0x7fda0000, 0x7fff0000, 0xbf000000, 0xbf240000, 0xbf480000, 0xbf6d0000,
    0xbf910000, 0xbfb60000, 0xbfda0000, 0xbfff0000, 0xff000000, 0xff240000,
    0xff480000, 0xff6d0000, 0xff910000, 0xffb60000, 0xffda0000, 0xffff0000,
    0x00003f00, 0x00243f00, 0x00483f00, 0x006d3f00, 0x00913f00, 0x00b63f00,
    0x00da3f00, 0x00ff3f00, 0x3f003f00, 0x3f243f00, 0x3f483f00, 0x3f6d3f00,
    0x3f913f00, 0x3fb63f00, 0x3fda3f00, 0x3fff3f00, 0x7f003f00, 0x7f243f00,
    0x7f483f00, 0x7f6d3f00, 0x7f913f00, 0x7fb63f00, 0x7fda3f00, 0x7fff3f00,
    0xbf003f00, 0xbf243f00, 0xbf483f00, 0xbf6d3f00, 0xbf913f00, 0xbfb63f00,
    0xbfda3f00, 0xbfff3f00, 0xff003f00, 0xff243f00, 0xff483f00, 0xff6d3f00,
    0xff913f00, 0xffb63f00, 0xffda3f00, 0xffff3f00, 0x00007f00, 0x00247f00,
    0x00487f00, 0x006d7f00, 0x00917f00, 0x00b67f00, 0x00da7f00, 0x00ff7f00,
    0x3f007f00, 0x3f247f00, 0x3f487f00, 0x3f6d7f00, 0x3f917f00, 0x3fb67f00,
    0x3fda7f00, 0x3fff7f00, 0x7f007f00, 0x7f247f00, 0x7f487f00, 0x7f6d7f00,
    0x7f917f00, 0x7fb67f00, 0x7fda7f00, 0x7fff7f00, 0xbf007f00, 0xbf247f00,
    0xbf487f00, 0xbf6d7f00, 0xbf917f00, 0xbfb67f00, 0xbfda7f00, 0xbfff7f00,
    0xff007f00, 0xff247f00, 0xff487f00, 0xff6d7f00, 0xff917f00, 0xffb67f00,
    0xffda7f00, 0xffff7f00, 0x0000bf00, 0x0024bf00, 0x0048bf00, 0x006dbf00,
    0x0091bf00, 0x00b6bf00, 0x00dabf00, 0x00ffbf00, 0x3f00bf00, 0x3f24bf00,
    0x3f48bf00, 0x3f6dbf00, 0x3f91bf00, 0x3fb6bf00, 0x3fdabf00, 0x3fffbf00,
    0x7f00bf00, 0x7f24bf00, 0x7f48bf00, 0x7f6dbf00, 0x7f91bf00, 0x7fb6bf00,
    0x7fdabf00, 0x7fffbf00, 0xbf00bf00, 0xbf24bf00, 0xbf48bf00, 0xbf6dbf00,
    0xbf91bf00, 0xbfb6bf00, 0xbfdabf00, 0xbfffbf00, 0xff00bf00, 0xff24bf00,
    0xff48bf00, 0xff6dbf00, 0xff91bf00, 0xffb6bf00, 0xffdabf00, 0xffffbf00,
    0x0000ff00, 0x0024ff00, 0x0048ff00, 0x006dff00, 0x0091ff00, 0x00b6ff00,
    0x00daff00, 0x00ffff00, 0x3f00ff00, 0x3f24ff00, 0x3f48ff00, 0x3f6dff00,
    0x3f91ff00, 0x3fb6ff00, 0x3fdaff00, 0x3fffff00, 0x7f00ff00, 0x7f24ff00,
    0x7f48ff00, 0x7f6dff00, 0x7f91ff00, 0x7fb6ff00, 0x7fdaff00, 0x7fffff00,
    0xbf00ff00, 0xbf24ff00, 0xbf48ff00, 0xbf6dff00, 0xbf91ff00, 0xbfb6ff00,
    0xbfdaff00, 0xbfffff00, 0xff00ff00, 0xff24ff00, 0xff48ff00, 0xff6dff00,
    0xff91ff00, 0xffb6ff00, 0xffdaff00, 0xffffff00,
];

unittest
{
    assert(colorTable[foregroundColor] == 0x00000000);
    assert(colorTable[black] == 0x00000000);
    assert(colorTable[white] == 0xffffff00);
    assert(colorTable[dark3] == 0x55555500);
    assert(colorTable[backgroundColor] == 0xc0c0c000);
}

// ---------------------------------------------------------------------
// Fl_Font / Fl_Fontsize
// ---------------------------------------------------------------------

alias Font = int;

enum : Font
{
    helvetica            = 0,
    helveticaBold        = 1,
    helveticaItalic      = 2,
    helveticaBoldItalic  = 3,
    courier              = 4,
    courierBold          = 5,
    courierItalic        = 6,
    courierBoldItalic    = 7,
    times                = 8,
    timesBold            = 9,
    timesItalic          = 10,
    timesBoldItalic      = 11,
    symbol               = 12,
    screen               = 13,
    screenBold           = 14,
    zapfDingbats         = 15,

    freeFont  = 16,
    bold      = 1,
    italic    = 2,
    boldItalic = 3,
}

alias Fontsize = int;

/// Default label font size in pixels. Mutable, like FLTK FL_NORMAL_SIZE.
Fontsize normalSize = 14;

// ---------------------------------------------------------------------
// Fl_Labeltype
// ---------------------------------------------------------------------

enum Labeltype : ubyte
{
    normalLabel = 0,
    noLabel,
    shadowLabel,
    engravedLabel,
    embossedLabel,
    multiLabel,
    iconLabel,
    imageLabel,

    freeLabeltype,
}

// ---------------------------------------------------------------------
// Fl_Arrow_Type / Fl_Orientation (used by drawArrow())
// ---------------------------------------------------------------------

enum ArrowType
{
    arrowSingle = 0x01,
    arrowDouble = 0x02,
    arrowChoice = 0x03,
    arrowReturn = 0x04,
}

enum Orientation
{
    orientNone  = 0x00,
    orientRight = 0x00,
    orientNe    = 0x01,
    orientUp    = 0x02,
    orientNw    = 0x03,
    orientLeft  = 0x04,
    orientSw    = 0x05,
    orientDown  = 0x06,
    orientSe    = 0x07,
}

// ---------------------------------------------------------------------
// Fl_Cursor -- closed tag set, ported in full (it's cheap: just named
// constants, unlike the platform code that would make them do anything).
// `default_` carries a trailing underscore only because `default` is a
// D keyword; every other member matches FLTK's name verbatim minus
// the FL_CURSOR_ prefix.
// ---------------------------------------------------------------------

enum Cursor
{
    default_ =   0,
    arrow    =  35,
    cross    =  66,
    wait     =  76,
    insert   =  77,
    hand     =  31,
    help     =  47,
    move     =  27,

    ns       =  78,
    we       =  79,
    nwse     =  80,
    nesw     =  81,
    n        =  70,
    ne       =  69,
    e        =  49,
    se       =   8,
    s        =   9,
    sw       =   7,
    w        =  36,
    nw       =  68,

    none     = 255,
}

// ---------------------------------------------------------------------
// Fl_When (Fl_Widget::when())
// ---------------------------------------------------------------------

alias When = uint;

enum : When
{
    whenNever            = 0,
    whenChanged          = 1,
    whenNotChanged       = 2,
    whenRelease          = 4,
    whenReleaseAlways    = 6,
    whenEnterKey         = 8,
    whenEnterKeyAlways   = 10,
    whenEnterKeyChanged  = 11,
    whenClosed           = 16,
}

// ---------------------------------------------------------------------
// Fl_Mode (window/visual capability flags -- `FL/Enumerations.H`)
// ---------------------------------------------------------------------

/// Combinable capability flags for `Fl::visual()`/`Fl_Gl_Window::mode()`.
/// The GL-window-only members (`modeAccum`/`modeAlpha`/`modeDepth`/
/// `modeStencil`/`modeMultisample`/`modeStereo`/`modeFakeSingle`/
/// `modeOpengl3`/`modeDepth32`) are consumed by `fl.gl_window`; values
/// verbatim from FLTK's `Fl_Mode` (`FL/Enumerations.H`).
alias Mode = int;

enum : Mode
{
    modeRgb         = 0,
    modeIndex       = 1,
    modeSingle      = 0,
    modeDouble      = 2,
    modeAccum       = 4,
    modeAlpha       = 8,
    modeDepth       = 16,
    modeStencil     = 32,
    modeRgb8        = 64,
    modeMultisample = 128,
    modeStereo      = 256,
    modeFakeSingle  = 512,
    modeOpengl3     = 1024,
    modeDepth32     = 2048,
}

// ---------------------------------------------------------------------
// Fl_Callback_Reason
// ---------------------------------------------------------------------

enum CallbackReason
{
    unknown = 0,
    selected,
    deselected,
    reselected,
    opened,
    closed,
    dragged,
    cancelled,
    changed,
    gotFocus,
    lostFocus,
    released,
    enterKey,
    user = 32,
}

// ---------------------------------------------------------------------
// Fl_Beep
// ---------------------------------------------------------------------

/// From FL/fl_ask.H; used by fl.core's beep()/fl.ask's fl_beep().
enum Beep
{
    default_ = 0,
    message,
    error,
    question,
    password,
    notification,
}

// ---------------------------------------------------------------------
// Fl_Event
// ---------------------------------------------------------------------

enum Event
{
    noEvent = 0,
    push,
    release,
    enter,
    leave,
    drag,
    focus,
    unfocus,
    keyDown,
    keyUp,
    close,
    move,
    shortcut,
    deactivate,
    activate,
    hide,
    show,
    paste,
    selectionClear,
    mouseWheel,
    dndEnter,
    dndDrag,
    dndLeave,
    dndRelease,
    screenConfigurationChanged,
    fullscreen,
    zoomGesture,
    zoomEvent,
    beforeTooltip,
    beforeMenu,
    appActivate,
    appDeactivate,
}

/// FL_KEYBOARD is a synonym for FL_KEYDOWN FLTK.
enum keyboard = Event.keyDown;

// ---------------------------------------------------------------------
// Non-ASCII key names (Fl::event_key() values), Fl::event_button()
// mouse-button numbers
// ---------------------------------------------------------------------

/// FLTK has no named typedef for these either -- Fl::event_key()
/// just returns a plain int. Named here only so callers don't have to
/// spell out `int`.
alias Keysym = int;

enum : Keysym
{
    button          = 0xfee8, ///< A mouse button; button + n is mouse button n.
    backSpace       = 0xff08,
    tab             = 0xff09,
    isoKey          = 0xff0c,
    enter           = 0xff0d,
    pause           = 0xff13,
    scrollLock      = 0xff14,
    escape          = 0xff1b,
    kana            = 0xff2e,
    eisu            = 0xff2f,
    yen             = 0xff30,
    jisUnderscore   = 0xff31,
    home            = 0xff50,
    left            = 0xff51,
    up              = 0xff52,
    right           = 0xff53,
    down            = 0xff54,
    pageUp          = 0xff55,
    pageDown        = 0xff56,
    end             = 0xff57,
    print           = 0xff61,
    insert          = 0xff63,
    menu            = 0xff67,
    help            = 0xff68,
    numLock         = 0xff7f,
    kp              = 0xff80, ///< kp + 'n' for keypad digit n.
    kpEnter         = 0xff8d,
    kpLast          = 0xffbd,
    f               = 0xffbd, ///< f + n for function key n.
    fLast           = 0xffe0,
    shiftL          = 0xffe1,
    shiftR          = 0xffe2,
    controlL        = 0xffe3,
    controlR        = 0xffe4,
    capsLock        = 0xffe5,
    metaL           = 0xffe7,
    metaR           = 0xffe8,
    altL            = 0xffe9,
    altR            = 0xffea,
    deleteKey       = 0xffff,
    altGr           = 0xfe03,

    volumeDown      = 0xEF11,
    volumeMute      = 0xEF12,
    volumeUp        = 0xEF13,
    mediaPlay       = 0xEF14,
    mediaStop       = 0xEF15,
    mediaPrev       = 0xEF16,
    mediaNext       = 0xEF17,
    homePage        = 0xEF18,
    mail            = 0xEF19,
    search          = 0xEF1B,
    back            = 0xEF26,
    forward         = 0xEF27,
    stop            = 0xEF28,
    refresh         = 0xEF29,
    sleep           = 0xEF2F,
    favorites       = 0xEF30,
}

/// Button numbers for FL_PUSH/FL_RELEASE events; see Fl::event_button().
enum : int
{
    leftMouse    = 1,
    middleMouse  = 2,
    rightMouse   = 3,
    backMouse    = 4,
    forwardMouse = 5,
}

// ---------------------------------------------------------------------
// Fl::event_state() bits
// ---------------------------------------------------------------------

alias EventState = uint;

enum : EventState
{
    stateShift      = 0x00010000,
    stateCapsLock   = 0x00020000,
    stateCtrl       = 0x00040000,
    stateAlt        = 0x00080000,
    stateNumLock    = 0x00100000,
    stateMeta       = 0x00400000,
    stateScrollLock = 0x00800000,

    stateButton1 = 0x01000000,
    stateButton2 = 0x02000000,
    stateButton3 = 0x04000000,
    stateButton4 = 0x08000000,
    stateButton5 = 0x10000000,
    stateButtons = 0x1f000000,
}

/// Mouse button n (n = 1..5) is pushed, matching stateButton1..stateButton5
/// above. Ported from the `FL_BUTTON(n)` function-style macro
/// (`FL/Enumerations.H`) as a plain function, D having no preprocessor
/// macros to replicate it with.
EventState stateButton(int n) { return cast(EventState)(0x00800000 << n); }

enum : EventState
{
    /// FL_COMMAND/FL_CONTROL are platform aliases FLTK
    /// (FL/platform_types.h): on X11/Wayland/Windows FL_COMMAND is
    /// FL_CTRL and FL_CONTROL is FL_META; only macOS swaps them. Linux
    /// X11/Wayland is this port's primary target (see CLAUDE.md), so
    /// that's the only mapping ported.
    stateCommand = stateCtrl,
    stateControl = stateMeta,

    keyMask = 0x0000ffff,
}

// ---------------------------------------------------------------------
// Fl_Damage
// ---------------------------------------------------------------------

alias Damage = uint;

enum : Damage
{
    damageChild   = 0x01,
    damageExpose  = 0x02,
    damageScroll  = 0x04,
    damageOverlay = 0x08,
    damageUser1   = 0x10,
    damageUser2   = 0x20,
    damageAll     = 0x80,
}

// ---------------------------------------------------------------------
// Fl::add_fd() "when" conditions (FL/Enumerations.H)
// ---------------------------------------------------------------------

/// Open bitmask set (combines via `|`, e.g. `fdRead | fdWrite`) --
/// alias + manifest constants, matching Align/Color/Font/When/Damage's
/// treatment elsewhere in this module. Passed to
/// `fl.core.addFd()`/`removeFd()` (`Fl::add_fd()`/`remove_fd()`,
/// core-roadmap item 6).
alias FdWhen = int;

enum : FdWhen
{
    fdRead   = 1,
    fdWrite  = 4,
    fdExcept = 8,
}

// ---------------------------------------------------------------------
// Fl_Input_ type() values (FL/Fl_Input_.H)
// ---------------------------------------------------------------------

/// Open bitmask/index set (combines via `|`, e.g. `inputMultiline |
/// inputReadonly`) -- alias + manifest constants rather than a real
/// enum, matching Align/Color/Font/When/Damage's treatment elsewhere in
/// this module. Stored in `Widget.type()` (a plain `ubyte`).
alias InputType = ubyte;

enum : InputType
{
    inputNormal         = 0,
    inputFloat          = 1,
    inputInt            = 2,
    inputHidden         = 3,
    inputMultiline      = 4,
    inputSecret         = 5,
    inputTypeMask       = 7,
    inputReadonly       = 8,
    outputNormal        = inputNormal | inputReadonly,
    outputMultiline     = inputMultiline | inputReadonly,
    inputWrap           = 16,
    inputMultilineWrap  = inputMultiline | inputWrap,
    outputMultilineWrap = inputMultiline | inputReadonly | inputWrap,
}

// ---------------------------------------------------------------------
// fl_line_style() style/cap/join values (FL/fl_draw.H)
// ---------------------------------------------------------------------

/// Open bitmask set (combines via `|`, e.g. `lineDash | capRound |
/// joinRound`) -- alias + manifest constants, matching Align/Color/
/// Font/When/Damage/FdWhen/InputType's treatment elsewhere in this
/// module. Passed to `fl.draw.lineStyle()` (core-roadmap item
/// 10). `FL_UNIFORM_WIDTH` (a scaled-display-only line-width-adjustment
/// flag, `Fl_Scalable_Graphics_Driver`'s own concern) is deliberately
/// not ported -- this port has no scaling subsystem at all, so it would
/// have no effect anywhere, matching every other "assumes scale=1"
/// simplification already documented in fl.draw's module comment.
alias LineStyle = int;

enum : LineStyle
{
    lineSolid      = 0,
    lineDash       = 1,
    lineDot        = 2,
    lineDashDot    = 3,
    lineDashDotDot = 4,

    capFlat        = 0x100,
    capRound       = 0x200,
    capSquare      = 0x300,

    joinMiter      = 0x1000,
    joinRound      = 0x2000,
    joinBevel      = 0x3000,
}

unittest
{
    assert(fl_down(Boxtype.upBox) == Boxtype.downBox);
    assert(fl_frame(Boxtype.upBox) == Boxtype.upFrame);
    assert(fl_frame(Boxtype.downBox) == Boxtype.downFrame);

    // fl_box() converts a frame to its filled/box equivalent; applied
    // to an already-filled box, it's the identity.
    assert(fl_box(Boxtype.downFrame) == Boxtype.downBox);
    assert(fl_box(Boxtype.downBox) == Boxtype.downBox);

    // noBox/flatBox are below Boxtype.upBox, so fl_down()/fl_box() leave
    // them unchanged (matching the "b < FL_UP_BOX" FLTK guard).
    assert(fl_down(Boxtype.noBox) == Boxtype.noBox);
    assert(fl_box(Boxtype.flatBox) == Boxtype.flatBox);
}

/// Selects which algorithm `fl.draw.fl_contrast()` uses. Ported from
/// `FL_CONTRAST_NONE`/`FL_CONTRAST_LEGACY`/`FL_CONTRAST_CIELAB`/
/// `FL_CONTRAST_CUSTOM`/`FL_CONTRAST_LAST` (`FL/Enumerations.H`) -- a
/// closed, non-combinable tag set, so a real D `enum` (matching this
/// module's own `Boxtype`/`Labeltype` convention) rather than a plain
/// `alias`+constants set like `Align`/`Color`.
enum ContrastMode
{
    contrastNone   = 0, /// always returns the foreground color
    contrastLegacy = 1, /// legacy (FLTK 1.3.x) contrast function
    contrastCielab = 2, /// current (FLTK 1.4.0+) default function
    contrastCustom = 3, /// caller-registered function, see `fl_contrast_function()`
    contrastLast   = 4, /// internal use only -- invalid contrast mode
}

/// Signature a caller-registered custom contrast function must have.
/// Ported from `Fl_Contrast_Function` (`typedef Fl_Color
/// (Fl_Contrast_Function)(Fl_Color, Fl_Color, int, int);`) -- a D
/// delegate rather than a bare function pointer, this port's usual
/// substitution (see CLAUDE.md's "Callbacks are D delegates" porting
/// convention) even though FLTK's own `Fl_Contrast_Function` has no
/// `void*` user-data slot to motivate it either way; kept for
/// consistency and so a caller's custom function can still close over
/// its own state.
alias ContrastFunction = Color delegate(Color fg, Color bg, int context, int size);
