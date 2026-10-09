# Porting status

fldtk (`fl.*`) is a native D reimplementation of FLTK, not a binding layer.
This document tracks, module by module, how each piece of FLTK maps onto this
port: what's done, what's partial (and why), and what's deliberately left out.

Comments and docs sometimes cite a "core-roadmap item N" (1-11). These are
the eleven foundational gaps closed before the widget-level work.

Source links point at FLTK's GitHub mirror
(`https://github.com/fltk/fltk/blob/master/...`). fldtk tracks FLTK 1.5.0 (per
`fltk_version.dat` in the reference checkout) — see `CONVENTIONS.md`'s version note
for caveats about that checkout's own changelog lagging its code.

## Status legend

- **Complete** — faithfully ported, no known gaps.
- **Partial** — usable, but with named missing pieces (see each row).
- **Deferred** — deliberately not ported yet, for a stated reason (usually a
  library decision not yet made, or no consumer exists yet). Revisit when the
  blocking reason changes.
- **Not applicable** — no D port makes sense: pure C/C++-language scaffolding
  (macros, export-visibility annotations), or FLTK's XForms/Forms-compatibility
  layer, which has no reason to exist in a from-scratch D project (see
  `CONVENTIONS.md`'s "Out of scope" section).
- **Not started** — no D module yet, no decision made either way.

Every row also lists **differences from FLTK**: D-specific idioms
(delegates instead of function-pointer+`void*`, `string` instead of `char*`,
etc. — the general conventions are catalogued once in `CONVENTIONS.md`'s "Porting
conventions" and not repeated per module unless a module deviates from them
specifically) and any deliberate simplifications or scope cuts.

**Maintaining this file**: this is a status snapshot, not a change log —
when a module's status or gaps change, edit that row's own `**Status:**`
line and bullets in place to describe the *current* truth, rather than
appending a new dated bullet on top of the old one. Per-change narrative
history belongs in git commit messages, not here.

## Core / support

### `FL/Enumerations.H`

**Status:** Complete — `fl.enumerations`
([header](https://github.com/fltk/fltk/blob/master/FL/Enumerations.H))

Covers `Align`/`Boxtype`/`Color`/`Font`/`Fontsize`/`Labeltype`/`When`/
`CallbackReason`/`Event`/`Damage`, non-ASCII key names (`Keysym`), mouse
button numbers, `Fl::event_state()` bits, `Cursor`, `Fl_Arrow_Type`/
`Fl_Orientation`, `ContrastMode`/`ContrastFunction`, and `colorTable` (the
256-entry default system color table, actually from `src/fl_cmap.h` but
grouped here with `Color`).

- `FL_BUTTON(n)` (a function-style macro in FLTK) is a plain function,
  `stateButton(int n)` — D has no function-like macros.
- `Fl_Contrast_Function` becomes a D delegate (`ContrastFunction`) rather than
  a bare function pointer.

### `FL/Fl.H`

**Status:** Partial — `fl.core`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl.H),
[src/Fl.cxx](https://github.com/fltk/fltk/blob/master/src/Fl.cxx))

The large majority of this header is ported and real: the event loop
(`run()`/`wait()`/`wait(double)`/`check()`/`flush()`), timers/idle/check
callbacks, `add_fd()`, thread locking (`lock()`/`unlock()`/`awake()`),
scheme handling (`scheme()`/`is_scheme()`/`reload_scheme()`), the mutable
color table (`get_color()`/`set_color()`), font registration/enumeration,
X11 clipboard (text and image) with real selection ownership, drag-and-drop
(`Fl::dnd()`), multi-monitor/Xinerama geometry, IME/XIM composition,
`Fl::modal()`/`Fl::grab()`, the `add_handler()`/`add_system_handler()`/
`event_dispatch()` escape hatches, command-line argument parsing
(`Fl::args()`), and `Fl::visual()`. **GUI/display scaling is real and
complete**, confirmed working correctly and consistently on both Linux
and Windows, including real multi-monitor hardware:
`screenScale(int)`/`screenScale(int, float)`/`screenScalingSupported()`
are a genuine per-screen array (`screenScalingSupported() == 2` on
Linux/Windows, matching FLTK's own X11/Windows drivers' real
`PER_SCREEN_APP_SCALING` report), each screen keeping its own
independent factor exactly like FLTK. `fl.draw`'s primitives, and
every other module that draws (`fl.image`/`fl.pixmap`/`fl.bitmap`/
`fl.svg_image`/`fl.gdi_graphics_driver`/`fl.gdiplus_graphics_driver`),
read a separate live "current window's own scale" cache
(`fl.core.currentScale()`) instead of that table directly — refreshed at
every `make_current()`-equivalent call site, mirroring FLTK's own
split between `Fl_Screen_Driver::scale(n)` (the persisted table) and
`Fl_Graphics_Driver::scale()` (the live per-surface value). Real window
creation/resize (both application- and window-manager-initiated) with
correctly-translated incoming mouse-event coordinates (each event
dividing by *its own window's* screen, not a fixed index),
`WM_NORMAL_HINTS`, `decoratedW()`/`decoratedH()`,
`screenXYWH()`/`screenWorkArea()`, the actual Ctrl-+/Ctrl--/Ctrl-0
live-rescale keybinding (`keyboardScreenScaling()`) with its "137 %"
indicator popup, and startup detection (`Xft.dpi` resource on Linux,
genuine independent per-monitor `GetDpiForMonitor()` queries on
Windows, `FLTK_SCALING_FACTOR` env var on both).
**One deliberate fldtk-only addition beyond FLTK**: the last
interactively-chosen scale persists across restarts via `fl.preferences`
(`fl.core.loadPersistedScaleFactor()`/`persistScaleFactor()`), as a single
global value applying to all applications at once rather than a
per-monitor preference. It lives at `~/.config/fldtk/core.prefs` — fldtk's
own vendor namespace, deliberately not FLTK's `"fltk.org"`, since this
feature has no FLTK counterpart at all (FLTK's `scale_handler()`/
`rescale()` chain never uses `Fl_Preferences` to persist it) — and is
applied before `FLTK_SCALING_FACTOR`. Linux only so far; Windows has no
persistence wired up.

**`Fl::fatal()`/`Fl::set_abort()`** are real, with one deliberate
deviation from FLTK's default: `fl.core.fatal(string)` calls a settable
handler (`setAbort(AbortHandler)`/`abortHandler()`), matching
`Fl::set_abort()`'s shape (a D delegate here, per this port's usual
callback substitution). FLTK's own *default* handler prints to stderr then
calls `exit(1)`; this port's default deliberately doesn't call `exit()`,
since a library unilaterally tearing down its host application's process
is what this project avoids everywhere (`fl.platform_x11.openDisplay()`'s
`XOpenDisplay()`-failure path routes through the same mechanism). The
default still prints to stderr first, matching FLTK's always-prints
behavior, then throws a `fl.core.FatalError` — FLTK's own doc comment on
`Fl::fatal()` names throwing an exception as an acceptable way to satisfy
"must not return," so this is a choice of *default*, not a deviation from
the handler's documented contract. An app that wants FLTK's literal
exit-on-fatal behavior can opt into it via `setAbort()`.

Differences from FLTK:
- Callbacks throughout are D delegates, not function-pointer+`void*` pairs
  (`Fl_Awake_Handler`, `Fl_Args_Handler`, `Fl_Idle_Handler`, `Fl_Timeout_
  Handler`, `Fl_FD_Handler`, ...) — this port's usual substitution, see
  `CONVENTIONS.md`.
- The X11 clipboard's `paste()` uses a real async `XConvertSelection()`
  round trip rather than FLTK's `mkstemp()`-plus-`Fl_Shared_Image`
  temp-file dance for image data (this port's `BMPImage`/`PngImage` already
  support in-memory buffers).
- `Fl::clipboard_contains()` faithfully reproduces a real FLTK wart: a
  synchronous, blocking event-discarding loop (see `FLTK_ISSUES.md`).
- `Fl_Option`/`Fl::option()` persistence reads system/user `fl.preferences`
  files but the setter, matching FLTK, never writes them back.
- **Point-based screen lookup** is split the way FLTK splits it:
  `screenNum(x,y)`/`screenNum(x,y,w,h)` (used by `screenXYWH(...,mx,my)`
  and friends, and by `createWindow()`'s initial-screen lookup) compare
  FLTK-unit input against each screen's own *scaled* bounds (matching
  `Fl_Screen_Driver::screen_num()`), while `screenNumUnscaled(x,y)`
  compares against raw device-pixel Xinerama data (matching
  `Fl_X11_Screen_Driver::screen_num_unscaled()`) for the one caller that
  already has a device-pixel point, `getMouse()`'s `XQueryPointer()`
  result. Mixing the two returns the wrong monitor as soon as a second,
  non-origin-aligned or differently-scaled monitor exists.

Missing:
- **`Fl::atclose()`** — not ported; no consumer has needed it yet.
- **`use_high_res_GL()`** remains a real, honest no-op — needs GL
  high-res backing-store support, unrelated to the scaling work above.
- **The drawing-function-pointer half of `fl_box_table`** — only the
  metrics half (`box_dx`/`dy`/`dw`/`dh`/`box_bg`) is ported; box *drawing*
  dispatch happens through `fl.draw.drawBoxAt()`'s own switch instead of a
  function-pointer table, so this half was never needed.

### `FL/core/events.H`

**Status:** Complete — `fl.core`
([header](https://github.com/fltk/fltk/blob/master/FL/core/events.H))

Event state (`e_number`/`e_state`/`e_x`/`e_y`/... and their accessors),
`focus()`/`belowmouse()`/`pushed()`, `test_shortcut()`, `handle()`/
`handle_()` (collapsed into one `handle(Event, Widget)` — the split only
existed in FLTK to support `event_dispatch()`, ported separately as
`dispatch()`), `grab()` (with real `XGrabPointer()`/`XGrabKeyboard()`),
`get_mouse()`/`get_key()`, and `add_handler()`/`add_system_handler()`/
`event_dispatch()`.

- `FL_SCREEN_CONFIGURATION_CHANGED` has no real trigger yet, so there
  is nothing to dispatch — not a gap in this file's own port, just
  nothing yet to wire up. `FL_APP_ACTIVATE`/`_DEACTIVATE` are real on
  X11 under an EWMH window manager (from `_NET_ACTIVE_WINDOW` changes
  on the root window). `Event.zoomEvent`
  (`FL_ZOOM_EVENT`) is real and dispatched (`fl.core.scaleHandler()`
  calls `dispatch(Event.zoomEvent, null)` after every successful live
  rescale), so it is not one of these gaps.

### `FL/core/options.H`

**Status:** Complete — `fl.core`
([header](https://github.com/fltk/fltk/blob/master/FL/core/options.H))

The full `Fl_Option`/`Fl::option()` mechanism, including its two-tier
system-wide/per-user `Fl_Preferences`-backed persistence (`fl.preferences`
is a complete port — see that row). `visibleFocus()`/`dndTextOps()` are
thin wrappers over it, matching FLTK's own named convenience functions.
The setter (`option(Option, bool)`) forces the lazy preferences read
first (calling the getter for its side effect, matching FLTK's own
`if (!Private::options_read_) { option(opt); }`) before applying the
override — calling the setter as the very first touch of the options
system (the normal usage pattern: `fl.option(Fl.Option.arrowFocus,
true);` at the top of `main()`, before any widget exists) must not have
its override silently clobbered the next time anything calls the
getter, which is what a straight `optionValues_[opt] = val` without that
guard does.

### `FL/core/function_types.H`

**Status:** Deferred — n/a
([header](https://github.com/fltk/fltk/blob/master/FL/core/function_types.H))

None of these C function-pointer *typedefs* need a literal D port: every
subsystem that uses one (timers, `add_fd()`, `add_idle()`, clipboard
notify, `args()`) defines its own local D delegate alias instead, per this
port's callback convention. `Fl_Abort_Handler` is ported as
`fl.core.AbortHandler` (see `FL/Fl.H`'s row). Genuinely still unported:
`Fl_Atclose_Handler` (no consumer, see `FL/Fl.H`'s row) and the box/label drawing-function-pointer typedefs
(`Fl_Box_Draw_F` and friends — superseded by `fl.draw.drawBoxAt()`'s direct
dispatch, see `FL/Fl.H`'s row).

### `FL/core/pen_events.H`

**Status:** Deferred — n/a
([header](https://github.com/fltk/fltk/blob/master/FL/core/pen_events.H))

Pen/tablet events. FLTK itself has no X11 implementation of this either
(only Wayland and Windows) — see `CONVENTIONS.md`'s "Where this port
intentionally exceeds FLTK" for the plan to eventually add X11 pen
support (via XInput2) once fldtk's Wayland driver exists to validate the
event model first.

### `FL/Fl_Export.H`

**Status:** Not applicable — n/a

`__declspec(dllexport)`-style export macros; D doesn't need them.

### `FL/Fl_Object.H`

**Status:** Not applicable — n/a

XForms/Forms-compatibility alias (`#define Fl_Object Fl_Widget`) — see
`CONVENTIONS.md`'s "Out of scope" section.

### `FL/Fl_Rect.H`

**Status:** Complete — `fl.rect`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Rect.H))

### `FL/Fl_Widget_Tracker.H`

**Status:** Complete — `fl.widget_tracker`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Widget_Tracker.H))

The "was this widget destroyed mid-callback" safety net used everywhere a
widget fires more than one callback in a row.

- **Real D-specific redesign, not a straight port.** A `bool destroyed_`
  field set at the top of `~this()` doesn't work in D:
  `destroy()` on a class instance reinitializes the *entire object's
  memory* back to `.init` right after the destructor runs, silently wiping
  such a flag before any caller could observe it. So, like in FLTK, the
  state lives in an external registry (`fl.core`'s
  `watchWidgetPointer()`/`releaseWidgetPointer()`/`clearWidgetPointer()`)
  — same shape as FLTK's own external watch-list, but for a different
  reason (D's post-destructor reinitialization, vs. C++'s dangling
  pointer). `WidgetTracker` itself is a stack-only `struct` (RAII via D's
  deterministic scope-exit destructors), copying/heap-allocation disabled.

### `FL/Fl_Plugin.H`

**Status:** Deferred — n/a
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Plugin.H))

Runtime plugin-loading mechanism; no consumer anywhere else in this port.

### `FL/Fl_Device.H`

**Status:** Partial — `fl.image_surface`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Device.H))

`Fl_Surface_Device` is ported as `SurfaceDevice`: a real `pushCurrent()`/
`popCurrent()` stack plus `surface()`/`isCurrent()`. A real class family
sits beneath it: directly,
`fl.widget_surface.WidgetSurface` (itself base to `ImageSurface`/
`CopySurface`/`fl.svg_file_surface.SvgFileSurface`/`fl.postscript.
EpsFileSurface`/`fl.paged_device.PagedDevice`, the last with its own
subclasses `fl.postscript.PostscriptFileDevice` and `fl.printer_posix.
Printer`/`fl.printer_win32.Printer` — see `FL/Fl_Widget_Surface.H`'s row)
and `fl.gl_display_device.GlDisplayDevice` (a real port of
`Fl_OpenGL_Display_Device`'s own `display_device()` singleton pattern,
redirecting `fl.draw`'s leaf primitives through
`fl.gl_graphics_driver.GlGraphicsDriver`).

Differences from FLTK:
- No polymorphic *per-platform driver* hierarchy underneath
  `SurfaceDevice` itself (i.e. no `Fl_Xlib_Image_Surface_Driver`-style
  split) — `SurfaceDevice` exposes two protected hooks (`doSetCurrent()`/
  `doEndCurrent()`) instead, folding each concrete surface's X11 body
  directly into its own class. This is orthogonal to the real subclass
  family above, which is about distinct *surface kinds* (image capture,
  SVG/PostScript/print export, GL), not per-platform driver variants of
  one kind.
- The *base* `Fl_Display_Device` (plain on-screen X11/Win32 drawing) has
  no distinct singleton object of its own — `surface() is null` means
  "the display" in this port. `GlDisplayDevice` above is the one real
  exception, needed because GL rendering genuinely does redirect through
  a `SurfaceDevice`/`GraphicsDriver` pair the way an export surface does.

Missing:
- `Fl_Device_Plugin` itself — a C++ runtime-registration pattern that lets
  FLTK's core library call into `fltk_gl` only when that optional library
  is actually linked into the final program. This port always links GL
  (`dub.sdl`'s unconditional `libs "GL"`), so the whole reason the pattern
  exists doesn't apply — not a narrowed port, a structural non-issue. The
  capability the plugin provides on the GL side is real and used directly:
  `GlWindow.capture()` (`FL/Fl_Gl_Window.H`'s row) calls
  `captureGlRectangle()` without needing a plugin indirection. The one
  piece genuinely not ported: `fl.core.captureWindow()`/`readImage()`/a
  print-to-PDF export don't special-case a `GlWindow` found while walking
  a widget tree the way FLTK's `traverse_to_gl_subwindows()` does — on
  this port's tested local-Mesa-direct-rendering setup a plain X11 pixel
  grab already picks up GL-rendered content correctly, so this only
  matters for indirect rendering/remote X, neither in this port's testing
  scope.

### `FL/Fl_Graphics_Driver.H`

**Status:** Partial — `fl.graphics_driver`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Graphics_Driver.H))

A deliberately minimal abstract `GraphicsDriver` class covers the
primitive families real consumers need (rect/line/color/polygon, line
style, clipping, arcs/pies, the vertex-path `end_*()` family, plain and
rotated text, raster/bitmap images) rather than FLTK's full ~60-virtual
surface. Real consumers: `fl.svg_file_surface.SvgGraphicsDriver`,
`fl.postscript.PostscriptGraphicsDriver`,
`fl.gl_graphics_driver.GlGraphicsDriver`, and
`fl.gdi_graphics_driver.GdiGraphicsDriver`/
`fl.gdiplus_graphics_driver.GdiPlusGraphicsDriver` (the latter a subclass
of the former, see `FL/win32.H`'s row). The two Windows drivers are the
ones where `currentDriver` stays live for real, interactive on-screen
rendering rather than an offscreen/export surface.

Differences from FLTK:
- FLTK's `fl_graphics_driver` global always points at *some* concrete
  driver, even for plain on-screen drawing. This port's `fl.draw` leaf
  primitives call Xlib/Xft directly by default — `currentDriver is null`
  means "use that direct path unchanged"; non-null means "delegate to this
  driver instead." There's no `NativeGraphicsDriver` subclass duplicating
  the X11 path.
- Text metrics (`width()`/`height()`/`descent()`/`text_extents()`) and
  `fl_font()` are never dispatched through a driver at all, matching
  FLTK's own `Fl_SVG_Graphics_Driver` (metrics always come from the real
  display driver, since a file-surface driver has no font-metrics
  capability of its own).

Rotated-text output: the dispatch hook (`draw(int angle,...)`) exists
and three real drivers override it (PostScript's `rotate` operator,
SVG's `transform="rotate(...)"`, and Windows' `GdiGraphicsDriver` via a
real angle-keyed `HFONT` cache) — but rotation isn't limited to
dispatched drivers: this port's own native on-screen Xft path
(`fl.draw`, `currentDriver is null`) rotates for real too, via a
hand-built `FcPattern` carrying an `FC_MATRIX` rotation (`fl.xft`'s
`XftFontMatch()`/`XftFontOpenPattern()`, since `XftFontOpenName()`'s
simple name-string interface can't express a rotation matrix at all),
cached per `(face, size, angle)` — see `FL/fl_draw.H`'s row for the full
writeup.

Missing:
- Image drawing dispatch (`draw_rgb()`/`draw_pixmap()`/`draw_bitmap()`/
  `draw_image()`) beyond the two leaves (`drawImage()`/`drawBitmap()`)
  that `PostscriptGraphicsDriver`, `SvgGraphicsDriver`, `GlGraphicsDriver`
  and the GDI drivers share — no consumer needs the per-image-class
  variants.

### `FL/Fl_Paged_Device.H`

**Status:** Complete — `fl.paged_device`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Paged_Device.H))

Thinner than it looks: `Fl_Paged_Device` itself is just `Fl_Widget_Surface`
plus the `page_formats[]` table and a handful of "not implemented" default
virtuals — all the real multi-page emission logic lives in the concrete
subclasses (`fl.postscript.PostscriptFileDevice`, `fl.printer.Printer`).

- `Page_Format`/`Page_Layout` are ported as `alias`-plus-manifest-constants
  rather than real D `enum`s, since FLTK itself ORs values from the two
  together (this port's usual convention for open, combinable sets).
- `margins()`'s `int*` out-parameters become D `out int` parameters
  (always provided) rather than nullable pointers.

### `FL/Fl_Widget_Surface.H`

**Status:** Partial — `fl.widget_surface` — see "Printing / off-screen
surfaces" below (`FL/Fl_Copy_Surface.H`'s row) for the full writeup; this
header's own content is covered there, not duplicated here.

### `FL/Fl_Scheme.H`

**Status:** Complete — `fl.core` + `fl.draw`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Scheme.H))

FLTK's own header comment calls this class "intentionally not fully
documented... subject to change," so this port targets `Fl::scheme()`/
`Fl::is_scheme()`/`Fl::reload_scheme()`'s real behavior
(`src/Fl_get_system_colors.cxx`) instead of the sparse header itself: all
four named schemes (gtk+/plastic/gleam/oxy) have real, complete boxtype-
drawing families (see `FL/fl_draw.H`'s row).

### `FL/Fl_Scheme_Choice.H`

**Status:** Complete — `fl.scheme_choice`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Scheme_Choice.H))

A `Choice` pre-populated from `fl.scheme.names()`, switching
`fl.core.scheme()` on selection.

- One deviation: FLTK's own callback selection relies on `reload_scheme()`'s
  own every-open-window redraw walk; this port's callback redraws only its
  own `window()` — correct for the single-window case every consumer here
  uses so far.

### `FL/filename.H`

**Status:** Partial — `fl.filename`
([header](https://github.com/fltk/fltk/blob/master/FL/filename.H))

Path/string utilities (`filenameName`/`filenamePath`/`filenameExt`/
`filenameSetExt`/`filenameExpand`/`filenameAbsolute`/`filenameRelative`/
`filenameMatch`/`filenameIsdir`) plus `openUri()`. No GUI dependency.

- Only the D-`string`-returning shape is ported — the original `char* +
  tolen` buffer API is skipped, matching this port's usual `string`-over-
  `char*` substitution.
- `Fl_File_Sort_F`'s real substitute is `fl.file_chooser.FileSortFunc` (a
  `string`-comparing delegate), not a port of the typedef itself.

Missing:
- `fl_filename_list()`/`fl_decode_uri()` — `fl.file_chooser` lists
  directories directly via `std.file.dirEntries()` instead, so this
  remains a real but low-priority gap.
- `filenameRelative()`'s case-insensitive (Windows/macOS) comparison mode
  — only the case-sensitive Linux/Wayland behavior is ported.

### `FL/names.h`

**Status:** Complete — `fl.names`
([header](https://github.com/fltk/fltk/blob/master/FL/names.h))

`eventNames`/`fontNames`/`callbackReasonNames` plus their `*Str()` lookup
helpers — pure debug/introspection tables, no internal consumer.

- `eventNames` skips FLTK's 11 trailing `Fl::Pen::*` entries (pen events
  are deferred — see `FL/core/pen_events.H`'s row); every other entry is
  ported.
- Two real FLTK off-by-one bugs (`fl_fontname_str()`/
  `fl_callback_reason_str()` both bounds-check against the wrong index, so
  each array-based path is unreachable for its own last entry) are ported
  *faithfully*, not fixed — see `FLTK_ISSUES.md`.

### `FL/fl_ask.H`

**Status:** Complete — `fl.ask`
([header](https://github.com/fltk/fltk/blob/master/FL/fl_ask.H))

`fl_beep()`, the translatable string globals (`no`/`yes`/`ok`/
`fl_cancel`/`fl_close`), `message()`/`alert()`/`fl_input()`/`password()`/
`choice()`/`choiceN()`, and the `fl_message_*()` per-call dialog
configuration functions (hotspot/position/title/icon), built on a private
`MessageDialog` (this port's equivalent of FLTK's internal `Fl_Message`).
Genuinely modal, via `fl.core.modal()` (not a `grab()`-based substitute;
see `fl.ask.d`'s module comment for why).

Differences from FLTK:
- Takes plain D `string`, not a printf-style `const char*, ...` format
  string.
- `fl_ask()` isn't ported (FLTK itself deprecates it in favor of
  `choice()`, which is ported). `fl_input_str()`/`fl_password_str()` have
  no D equivalent — the C-string-ownership split they exist for doesn't
  apply.
- `resizeform()` sizes the dialog to an *unwrapped* message, matching
  FLTK: a message with no explicit `\n`s produces an arbitrarily wide
  dialog rather than wrapping, even though this port's `fl_draw()` does
  support real word-wrap elsewhere.
- `messagePosition(int*, int*)` (the position-*query* overload) isn't
  ported — no consumer, and its nullable-`int*` shape doesn't map cleanly
  onto a single D signature.

### `FL/fl_callback_macros.H`

**Status:** Not applicable — n/a

C++ macro helpers for binding member functions as callbacks; D's real
closures/delegates make these unnecessary.

### `FL/fl_casts.H`

**Status:** Not applicable — n/a

C++ cast-helper macros; not needed in D.

### `FL/fl_draw.H`

**Status:** Partial — `fl.draw`
([header](https://github.com/fltk/fltk/blob/master/FL/fl_draw.H))

The large majority of FLTK's drawing API is real: solid/lined/filled
primitives, all boxtype families (built-in, rounded, oval/round/diamond,
and all four schemes — gtk+/plastic/gleam/oxy), real text via a Xft
binding (`fl.xft`) including word-wrap, FLTK's line-splitting rule (a
trailing `\n` doesn't start another line — `splitTextLines()`, shared by
both `fl_draw()` overloads and `fl_measure()`), shortcut-underline drawing, `@`-
symbol glyphs, RTL glyph-order reversal, rotated text (`fl_draw(int
angle,...)`, a real `FC_MATRIX`-rotated `FcPattern`, cached per
`(face, size, angle)`), and text-metrics queries; color
math (`fl_color_average()`/`fl_inactive()`/`fl_contrast()`, including the
real CIELAB-based default, not just the legacy algorithm); a rectangle-
stack clip system; the transform-stack/vertex-path family (`fl_begin_*()`/
`fl_vertex()`/`fl_curve()`/complex polygons); arrows; image drawing/
reading (`fl_draw_image()`, `fl_read_image()`, `fl_capture_window()`);
offscreen buffers; and overlay rubber-band rectangles.

Differences from FLTK:
- Assumes a plain TrueColor/DirectColor visual — no colormap/palette
  support, single monitor for pixel-level ops (screen geometry itself is
  Xinerama-aware, see `FL/Fl.H`'s row).
- Image drawing (`fl_draw_image()`/`fl_draw_image_mono()`, raw-buffer
  and callback forms) honors **negative deltas** the same way FLTK's own
  `innards()` does: a negative `l` flips vertically (`buf` points at the
  last row), a negative `d` flips horizontally (`buf` points at the
  first byte of the last pixel of its first row, the pixel pointer steps
  left, each pixel's own bytes are still read forward), and every size
  or classification — `l`'s `w*|d|` default, the gray-vs-color test
  (FLTK's `mono = (d>-3 && d<3)`), the alpha gate — comes from `|d|`.
  Sizing must use `|d|`, not the raw signed `d`: a `-3` delta
  would sign-extend `new ubyte[sw*sh*d]` into an `OutOfMemoryError` inside
  `resampleImageNearest()`, and give a backwards implicit row stride in
  the unscaled path. Headless `unittest`s cover `resampleImageNearest()`/
  `blendOverRgb()`, the parts of the path that don't need a live X
  display. `test/unittest_images`' FLIPH/LX toggles are the interactive
  exercise. One **deliberate deviation**: the raw-buffer `drawImage()`
  does real per-pixel alpha compositing for `|d| == 2`/`4`
  (`alphaBlendImage()`), where FLTK's own `fl_draw_image()` only honors
  alpha when the caller sets `FL_IMAGE_WITH_ALPHA` (so its RGBA/
  gray+alpha quadrants in that test render opaque on X11, and this
  port's don't).
- Font matching goes through `XftFontOpenName()`'s simple name-string
  matching rather than FLTK's hand-built `XftPattern`/`XftFontMatch`/core-
  font-fallback pipeline for the common, unrotated case — see
  `CONVENTIONS.md`'s note on the planned Pango rewrite. Rotated text
  (`fl_draw(int angle,...)`) is the one exception: it does build a real
  `XftPattern`/`XftFontMatch`/`XftFontOpenPattern` chain (`fl.xft`'s
  `xftFontForAngled()`), since `XftFontOpenName()`'s name-string
  interface has no way to attach an `FC_MATRIX` rotation at all — no
  core-font fallback either way, matching the unrotated path's own
  simplification. Only the 12 classic built-in font faces plus symbol/
  screen/screen-bold/Zapf-Dingbats resolve to a real family. The built-in Helvetica/Courier/Times faces
  map to the *generic* Fontconfig aliases "sans"/"mono"/"serif", matching
  FLTK 1.5.0's own tables (both `Fl_Xlib_Graphics_Driver_font_xft.cxx`'s
  and `Fl_Cairo_Graphics_Driver.cxx`'s), not the literal names
  "helvetica"/"courier"/"times": with a URW "Nimbus" family installed
  those resolve to different font files with different metrics
  (`fc-match helvetica` picks Nimbus Sans, ~15px ascent+descent at 14px,
  while `fc-match sans` picks the desktop's default sans-serif, e.g. Noto
  Sans at ~19px), so the alias choice is not cosmetic — see `getFont()`'s
  own doc comment in `fl.draw`. The `XftFontOpenName()`-vs-`XftPattern`/
  `XftFontMatch` *matching pipeline* difference itself is believed to be
  a minor (sub-pixel-rounding-scale) simplification;
  `smoke-tests/browser_height_probe_fltk.cxx` and
  `smoke-tests/text_baseline.d` are the diagnostic tests for vertical
  metrics.
- Clipping is a plain rectangle stack, not FLTK's general `Fl_Region` (via
  `XCreateRegion()` et al.) — every clip this port ever pushes is a single
  axis-aligned rectangle, so a rectangle stack is exactly as capable with
  no `XRegion` API needed.
- `fl_circle()`/vertex-path arcs use fixed-segment-count polygon
  approximations rather than FLTK's adaptive chord-length-epsilon
  algorithm.
- `contrastMode`/`contrastLevel`/`contrastFunction` are real and
  runtime-switchable (CIELAB default, legacy FLTK-1.3.x-compatible
  algorithm as an alternative).
- `fl.core.screenScale(int)`/`screenScale(int, float)` are real: a
  settable, genuinely per-screen GUI scale factor array, matching
  FLTK's own X11 driver exactly (`PER_SCREEN_APP_SCALING`), threaded
  through every drawing primitive on the direct-Xlib path:
  - rect/line/polygon (`fl_rectf()`/`fl_rect()`/`fl_line()`/
    `fl_xyline()`/`fl_yxline()`/`fl_polygon()`/`fl_scroll()`), via a
    `scaledFloor()` helper ported from
    `Fl_Scalable_Graphics_Driver::floor(int,float)`.
  - `fl_xyline()`/`fl_yxline()` draw filled rectangles (`XFillRectangle()`)
    whose thickness is proportional: `scaledFloor(y+1) - scaledFloor(y)`
    device pixels for the default pen, or the explicit width a prior
    `lineStyle(lineSolid, N)` set (`explicitWideLineWidthPx_`, consulted
    only by these two functions). A fixed-1px `XDrawLine()` would leave
    device-pixel gaps between adjacent 1-unit lines (e.g. `flFrame2()`'s
    multi-line bevel behind every plain up/down boxtype) at any scale
    other than 1. This matches the effect of FLTK's
    `Fl_Scalable_Graphics_Driver::xyline()`/`yxline()` pen-width widening
    without needing persistent GC line-width state (see this module's
    "General line style" section comment).
  - `beginLoop()`/`vertex()`/`endLoop()` polygon outlines, and
    `drawLineStrip()` (behind `endLine()`/`endComplexPolygon()`'s
    too-few-points fallback), go through a shared `drawLinesScaled()`
    that temporarily widens the GC line width to `int(currentScale())`
    via `XSetLineAttributes()` for whole-number scales, then resets it
    to 0. A diagonal segment has no axis to widen into a filled
    rectangle, so this uses FLTK's pen-width-widening approach
    literally. A fractional scale (150%, say) still draws a
    1-device-pixel outline: FLTK's further fractional-scale centering
    would need the persistent state this module deliberately doesn't
    carry, so that narrower case is a known gap.
  - text/fonts: `fl_font()` opens the real Xft font at
    `size * currentScale()` device pixels while `fl_size()` keeps
    reporting the FLTK-unit size; `height()`/`descent()`/`width()`/
    `textExtents()` divide their Xft-measured device-pixel results back
    down to FLTK units; `fl_draw()`'s pen position scales the same way.
  - images: `drawImage()`/`drawImageMono()` (raw-buffer and
    callback-based forms) resample the source buffer via
    nearest-neighbor `resampleImageNearest()` when the scaled size
    differs, a starting approximation for FLTK's real
    `draw_image_rescale()`.
  - the vertex/transform-stack family: `vertex()`/`transformedVertex()`/
    `circle()`/`curve()` all funnel through one `appendVertexPoint()`
    choke point, so every `begin*()`/`end*()` pair is covered. This is
    for a native on-screen draw only; a driver that declares
    `fl.graphics_driver.GraphicsDriver.wantsUnscaledVertices()`
    (`GlGraphicsDriver` chief among them, see that method's own doc
    comment) gets the raw, unscaled point instead.
  - `fl_arc()`/`fl_pie()`/`drawCircle()`/`drawCheck()`, and clipping
    (`restoreClip()` scales after adding the offset, matching
    `Fl_Xlib_Graphics_Driver::scale_clip()`'s order).

  Every scaled path is a byte-for-byte no-op at `currentScale() == 1`.
  Window creation/resize and the Ctrl-+/-/0 keybinding are real too (see
  `FL/Fl.H`'s row). `releaseDrawable()` (called by
  `fl.platform_x11.destroyWindow()` right before every window teardown)
  resets both the cached `XftDraw` handle and this module's own
  `drawable_` tracker (`setDrawable()`'s "last window actually drawn
  into" state, which `createOffscreen()` reads as a reference drawable
  for a new, unrelated Pixmap) when they match — otherwise a short-lived
  popup destroyed while still the last thing painted would leave
  `drawable_` dangling and break the next `createOffscreen()` call.
  Two deliberately-deferred gaps: `drawBitmapFixed()` (1-bit XBM stipple
  bitmaps) isn't scaled — FLTK's real version recaches an actual resized
  bitmap rather than scaling the destination rect, machinery `fl.bitmap`
  doesn't have; and `copyOffscreen()`/double-buffer sizing (window/buffer
  allocation size) is a separate concern from the rect/line/polygon
  scaling above. `rescaleOffscreen()` is a real no-op for the same
  reason — see that function's own doc comment.
- `fl.platform_x11`'s `case Expose:` translates raw device-pixel
  coordinates into FLTK units before passing them to `Widget.damage()`,
  matching every other incoming-event coordinate translation
  (`ConfigureNotify`, mouse/keyboard events); `setClipMask()`'s origin
  is scaled to match `drawImage()`'s own destination scaling (called
  right after by `fl.pixmap.Pixmap.draw()`), keeping a Pixmap's
  transparency mask aligned with its own image data at any scale != 1.
  `fl.core.transientScaleDisplay()`'s own shape-mask rendering (into an
  `ImageSurface`) saves/restores `currentScale()` to `1` around just
  that rendering block, avoiding double-scaling on top of that
  function's own manual pixel pre-multiplication — **not generalized**:
  anything else drawn into an `ImageSurface`/`CopySurface`/
  `WidgetSurface` while the screen's own scale is != 1 likely has the
  same latent issue (screenshot/thumbnail capture, printer output, SVG
  export), a real, deliberately-deferred follow-up.
- The non-integer-scale fractional-pen-width adjustment FLTK's
  `xyline()`/`yxline()` make when the active line width doesn't evenly
  divide the scale factor, and the active-line-width term FLTK's
  real `arc()`/`pie()` factor in, are deliberately not ported —
  documented simplifications.

Missing:
- Per-boxtype custom focus-ring shapes: `drawFocus()` always draws a
  generic dashed rectangle (plus real matching shaped rings for the
  rounded/round/diamond/oval boxtype families specifically) rather than
  consulting FLTK's full per-boxtype function-pointer table.

### `FL/fl_ask.H` (compat alias)

**Status:** Not applicable — n/a

Old-name `#include "fl_ask.H"` compatibility header; no separate content.

### `FL/fl_show_colormap.H`

**Status:** Complete — `fl.show_colormap`
([header](https://github.com/fltk/fltk/blob/master/FL/fl_show_colormap.H))

`showColormap()`/`ColorMenu`: a 256-swatch grid picker, modal via
`fl.core.grab()` (a single-widget grab-owner, the same category as the
popup-menu engine — not `fl.ask`'s `modal()` mechanism).

- Ported faithfully including one likely FLTK bug in `ColorMenu::run()`'s
  `which > 255` branch (`y()` used where `h()` looks intended) — see
  `FLTK_ISSUES.md`.

### `FL/fl_show_input.H`

**Status:** Not applicable — n/a

Old-name `#include "fl_ask.H"` compatibility header; no separate content.

### `FL/forms.H`

**Status:** Not applicable — n/a

The whole XForms/Forms-Library compatibility layer, plus
`fl_show_file_selector()` — see `CONVENTIONS.md`'s "Out of scope" section.

### `FL/gl_draw.H`

**Status:** Not applicable — `fl.gl`
([header](https://github.com/fltk/fltk/blob/master/FL/gl_draw.H))

A 19-line forwarding shim over `gl.h` (real, see that row) plus one extra
declaration, `gl_remove_displaylist_fonts()` — a cleanup routine for the
legacy `glXUseXFont()`-display-list text path this port's GL text support
deliberately never uses (texture-rectangle-only, see `FL/gl.h`'s row).
With no legacy display-list fonts ever created, there's nothing for an
equivalent to clean up.

### `FL/glut.H`

**Status:** Complete — `fl.glut`
([header](https://github.com/fltk/fltk/blob/master/FL/glut.H))

The real GLUT-compatibility layer FLTK itself ships
(`src/glut_compatibility.cxx`, ~500 lines): a real `Fl_Glut_Window` built
directly on `fl.gl_window.GlWindow` (including its software-simulated
overlay support), plus every window-management/menu/callback-
registration/`glutGet()`-family function the header declares that isn't
itself commented out in FLTK.

**Deliberately not ported**: FLTK's own ~7300-line geometry/teapot/
stroke-font/bitmap-font surface (`glutWire*`/`glutSolid*`/`glutStroke*`/
`glutBitmap*`, `src/freeglut_geometry.cxx`/`freeglut_teapot*`/
`freeglut_stroke_roman.cxx`/`freeglut_stroke_mono_roman.cxx`/
`src/glut_font.cxx`). Scoped by grepping every `glut*` call site across
this port's GLUT-dependent samples rather than assumed: zero of them call
any of these primitives, so there is nothing to port them for. A
deliberate choice, not an oversight or a gap left for later — that
stands unless a future sample actually calls one of these primitives.

- Callback registration keeps GLUT's own plain-function-pointer shape
  verbatim (not this port's usual delegate convention) since that's
  GLUT's real C API contract; menu-item callbacks bridge into this port's
  real `Callback` type via closures instead of FLTK's own
  `Fl_Menu_Item::callback_` type-punning trick.
- `glutInit()` takes `args` by value rather than reproducing FLTK's
  in-place `argc`/`argv` filtering.
- Spaceball/dial/tablet/window-status/colormap functions aren't declared
  — dead API even in real GLUT-on-FLTK.

### `GL/glu.h`

**Status:** Complete — `fl.glu`

Minimal hand-written `extern(C)` bindings against the system `libGLU`
(bind, don't reimplement — matching `FL/gl.h`'s own choice for GL
itself). Only the 7 functions any sample actually calls are declared
(`gluNewQuadric`/`gluCylinder`/`gluDeleteQuadric`/`gluLookAt`/
`gluOrtho2D`/`gluPerspective`/`gluPickMatrix` plus the opaque `GLUquadric`
handle) — GLU's sphere/disk/NURBS/tessellator surface isn't. Not
re-exported from the top-level `fl` package, same as `fl.opengl`/`fl.glx`
— infrastructure, not a header port.

### `GL/glew.h`

**Status:** Complete — `fl.glew`

Not an FLTK header — GLEW (the OpenGL Extension Wrangler), a third-party
C library, bound the same way `fl.glu` binds GLU, **but only on Linux**
(see the platform-split note below). Needed because OpenGL functions from
1.3 onward aren't guaranteed linkable symbols in `libGL.so`/
`opengl32.dll` (they're meant to be resolved via `glXGetProcAddress()`/
`wglGetProcAddress()` at runtime); FLTK's own GL3-core-profile samples
depend on real GLEW for exactly this, so Linux matches that dependency
choice exactly.

**Windows is deliberately different**: real GLEW (`glew32s.lib`) isn't
required, so a Windows dev machine needs no GLEW install (a static-library
`dub build` wouldn't notice the missing symbols, but a fully-linked `dub
test` binary would). `fl.glew`'s Windows branch instead resolves the same
~26 functions itself via `wglGetProcAddress()` — already linked
unconditionally through `opengl32.dll`, no new dependency of any kind —
the same technique GLEW uses internally, just inlined here rather than
delegated to the third-party library, and the same one
`fl.gl_window_driver.switchToGl1()` uses for its own single
`glUseProgram` lookup. See `fl.glew`'s own module doc comment for the
full writeup of both branches.

- Both branches expose the identical binding shape: a private function-
  pointer variable per modern GL function (`__glewCreateShader` etc,
  matching GLEW's own naming), populated before use (by real GLEW on
  Linux, by this module's own `glewInit()` on Windows), each wrapped in
  a thin real D function of the familiar GL name -- the two consumer
  samples need zero platform-specific code of their own either way.
- Covers only the ~26 modern GL functions this project's samples actually
  call (shader/program creation, VAO/VBO management, uniform/attribute
  setup) plus `glewInit()`/`glewGetString()` (Windows' own
  `glewGetString()` just self-identifies as this internal loader rather
  than reporting a real GLEW version number). Not re-exported from the
  top-level `fl` package, same as `fl.glu`.

### `FL/rgb_colors.H`

**Status:** Complete — `fl.rgb_colors`
([header](https://github.com/fltk/fltk/blob/master/FL/rgb_colors.H))

490 named `Fl_Color` constants from the X11 `rgb.txt` table
(`FL_RGB_ALICE_BLUE` → `rgbAliceBlue`), generated mechanically from the
header rather than hand-transcribed.

## Platform / windowing headers

### `FL/platform.H`

**Status:** Not started — *(planned: `fl.platform`)*
([header](https://github.com/fltk/fltk/blob/master/FL/platform.H))

### `FL/x.H` + `FL/x11.H` + `src/drivers/X11/*` + `src/drivers/Xlib/*` (rect/color/font parts)

**Status:** Partial — `fl.platform_x11` + `fl.xlib` + `fl.xft`
([FL/x.H](https://github.com/fltk/fltk/blob/master/FL/x.H),
[FL/x11.H](https://github.com/fltk/fltk/blob/master/FL/x11.H),
[src/Fl_x.cxx](https://github.com/fltk/fltk/blob/master/src/Fl_x.cxx))

This is the module that makes fldtk a real, running GUI toolkit on Linux:
window creation/destruction (including real subwindows), a `select()`-based
event loop multiplexing the X connection, the timer queue, `Fl::add_fd()`
entries, and idle callbacks; full mouse/keyboard/focus/crossing event
translation (including autorepeat detection, double/triple-click, NumLock/
keypad remap, side mouse buttons, and — deliberately beyond FLTK — *any*
mouse button number, not just the ones FLTK itself remaps); cursor shapes;
damage-rectangle-clipped repainting; window manager negotiation (size
hints, fullscreen/maximize/iconify via EWMH, icons via `_NET_WM_ICON`,
`WM_CLASS`/`_NET_WM_PID`/etc.); real X11 clipboard ownership (text and
image, with instant Xfixes-based change notification and a polling
fallback); full XDND drag-and-drop (same-process and cross-application);
real XIM/IME composition (including "preedit at cursor spot" positioning);
and multi-monitor/Xinerama-aware screen geometry.

Differences from FLTK:
- **Architecture**: a concrete, non-virtual module rather than FLTK's
  `Fl_Screen_Driver`/`Fl_Window_Driver` abstract base classes plus
  `Fl_X11_*` concrete subclasses. Windows has its own platform driver
  (`fl.platform_win32`), and the hierarchy wasn't extracted for it,
  deliberately: the criterion this project uses is sharper than raw
  platform count. `fl.graphics_driver.GraphicsDriver` (see that header's
  own row) is polymorphic precisely because several concrete backends
  (SVG/PostScript/GL/GDI) coexist and are chosen *at runtime, within one
  running process*. X11 and Windows never do that — a compiled fldtk
  binary targets exactly one OS, so which windowing backend is active is
  a `version()` choice D's compiler resolves at build time, the same role
  FLTK's own `newScreenDriver()`/`newWindowDriver()` factory functions
  play in a per-platform C++ build. So `fl.platform_win32` is a second
  concrete module, exactly like this one, with `fl.window`/`fl.core`
  holding `version (Windows)` twins beside their `version (linux)`
  branches — not a new abstract base class underneath both.
- **Naming**: flat `fl.platform_x11`, not a nested `fl.platform.x11` —
  matches this project's actual convention (no subpackages exist yet).
- `fl.xlib`/`fl.xft` are raw `extern(C)` infrastructure bindings (Xlib,
  and the slice of libXft/libXrender `fl.draw`'s text primitives need)
  with no direct FLTK header equivalent — the same role C's own stdlib
  headers play for the rest of this port. `fl.fontconfig`, `fl.xcursor`,
  `fl.xfixes`, `fl.xinerama`, `fl.xrandr` and `fl.xshape` are the same kind
  of binding for the libraries named by the matching `-l` flags.
- Popup windows (`Widget.Flag.menuWindow`) are made X11
  override-redirect, sidestepping window-manager reparenting races
  entirely, rather than relying on `XSync()`-based timing, which is racy
  against a real window manager.
- `Fl::visual()` generalizes pixel packing to the selected visual's real
  channel masks/shifts (`figureOutVisual()`), but the single shared GC is
  still created once against the *default* visual's depth and never
  recreated for a later-selected, different-depth visual — matching
  FLTK's own identical, undocumented limitation, not a regression.
- **`Fl::enable_im()`/`disable_im()`** (the opt-out from XIM input) are
  no-ops on X11, as in FLTK, where the base driver's versions are empty and
  only the Windows driver overrides them.
- **Multi-monitor/Xinerama** code paths are verified against real
  multi-head hardware; see `FL/Fl.H`'s row for the `screenNum(x,y)`
  FLTK-unit-vs-device-pixel split.
- **Per-monitor DPI** (`fl.core.screenDpi()`): beyond FLTK, which gives every
  monitor the DPI of the primary monitor's RandR millimeters. Here each
  Xinerama monitor is matched by position and size to its RandR 1.5 monitor
  (`XRRGetMonitors()`, bound in `fl.xrandr`) and gets its own DPI. Without
  RandR 1.5, or when a monitor reports 0 mm, the older pixels-over-X-screen-
  millimeters formula applies. The startup scale does not use this value; it
  comes from the `Xft.dpi` resource. `smoke-tests/screen_dpi.d` prints both
  formulas per monitor.
- **Cross-screen window moves** follow FLTK's `ConfigureNotify` handling
  (`Fl_x.cxx`): when a window's *centre* crosses into a different,
  differently-scaled screen, the real re-clamp is deferred a full tick via
  `Fl::add_timeout()` (`Fl_X11_Window_Driver::resize_after_screen_change()`/
  `data_for_resize_window_between_screens_`) — "calling it a second later
  gives a more pleasant user experience when moving windows between
  distinct screens," per FLTK's own comment — rather than reacting inline
  with whatever scale happened to be cached for the *old* screen. Ported
  into `fl.platform_x11`'s `case ConfigureNotify:`: the screen-change
  detection, the single shared `busy`/deferred-timeout state (a
  module-level struct matching FLTK's own single static, not per-window),
  the position-only-while-busy branching, and the modal-menu-closing aside
  for an open popup caught mid-transition. Verify with
  `smoke-tests/screen_scale_live.d` on a satellite monitor: Ctrl-+/- must
  not jump on the first rescale.
- **`flushDamage()`'s partial-rectangle blit** converts a
  `Widget.damage(Damage,x,y,w,h)` rectangle to device pixels for
  `fldraw.copyOffscreen()` by rounding the rectangle's two *corners*
  outward (floor the near corner, ceil the far corner), which guarantees
  the device-pixel rectangle fully contains the mapped FLTK-unit one,
  clamped against the offscreen buffer's own allocated size so the
  rounded-up edge can't read past it. Converting position and size
  independently with `scaledPos()`/`scaledDim()` doesn't work: `scaledDim()`
  truncates, so the copied rectangle's far edge could land up to 1 device
  pixel short of the true dirty area whenever the scale factor didn't
  divide it evenly, leaving a sliver of stale pixels (visible at 150%,
  e.g. a `menubar_add` dropdown's old "open" highlight).

Missing:
- **Wayland, macOS backends** — see their own rows below. Windows has
  its own platform driver (`FL/win32.H`'s row); X11 and Windows are the
  only two implemented platform drivers.
- **Image/file-data drag-and-drop** — DND is text-only (matching this
  port's existing clipboard-negotiation scope); `COMPOUND_TEXT`/other
  charset target variants aren't negotiated either.
- **Legacy `XWMHints.icon_pixmap` single-bitmap icons** — superseded by
  `_NET_WM_ICON`, which every modern desktop honors; not ported.
- **`readPixelsFromDrawable()`'s read-side pixel-format handling** stays a
  fixed 16/24/32bpp-layout simplification (the write/pack side was
  generalized to the active visual's real format, the read side wasn't —
  a smaller, still-documented gap).
- **The `XKeysymToUcs()` correction in the non-XIM input fallback** —
  about 300 lines of keysym-to-Unicode table, only needed when no input
  method is available.
- **A real CJK input method (ibus/fcitx) has never been tried.** Dead-key
  composition through XIM is confirmed; `smoke-tests/ime.d` is the test.
- **Multi-rectangle damage regions** — only a single bounding-box
  rectangle is tracked per flush (matching `fl.draw`'s own clip-stack
  simplification), not FLTK's general possibly-disjoint `Fl_Region`; never
  produces wrong pixels (redraw is idempotent), only occasionally repaints
  a slightly larger area than strictly necessary.

### `FL/wayland.H`

**Status:** Not started — *(planned: `fl.platform_wayland`, flat like
`fl.platform_x11`/`fl.platform_win32` — this project has no subpackages
anywhere, so there is no nested `fl.platform.wayland`)*
([header](https://github.com/fltk/fltk/blob/master/FL/wayland.H))

Note: Wayland support will introduce external dependencies:

- Cairo: advanced font rendering
- Pango / Fontconfig: Required for international text layouts, complex scripts,
UTF-8 parsing, and anti-aliased systemic font lookups. 
- libdecor: Required for managing system window decorations (min/max/close
buttons) natively inside Wayland environments. 

### `FL/win32.H`

**Status:** Partial — `fl.platform_win32` + `fl.gdi_graphics_driver` +
`fl.gdiplus_graphics_driver`
([header](https://github.com/fltk/fltk/blob/master/FL/win32.H))

fldtk's secondary platform target, mirroring `fl.platform_x11`'s
architecture exactly: a second concrete, non-virtual module (not a new
`Fl_Screen_Driver`/`Fl_Window_Driver` abstract hierarchy underneath both
— see `FL/x.H`'s row for the full reasoning), with `fl.window`/`fl.core`
growing `version (Windows)` twins beside their existing `version (linux)`
branches. Unlike every other platform-specific module in this port
(`fl.xlib`/`fl.xft`/`fl.opengl`/etc., all hand-written because druntime
ships no bindings for those C libraries), D's druntime already ships a
mature `core.sys.windows.*` Win32 binding surface, so
`fl.platform_win32`/`fl.gdi_graphics_driver` import
`core.sys.windows.windows` directly — no `fl.win32` binding module
exists or is needed.

**Window/event loop**: a real top-level `HWND`, with real subwindow
support: `createWindow()`'s `WS_CHILD` branch creates
a real child `HWND` for any `win.parent() !is null`, and destruction
recurses through nested subwindows at the OS level too (matching
FLTK's `Fl_win32.cxx`, including skipping WM negotiation entirely
for a subwindow, the same precedent `fl.platform_x11`'s own subwindow
support already established). A
`MsgWaitForMultipleObjects()`-based message pump integrated with
`fl.core`'s existing timer queue, and full mouse/keyboard/paint/resize/
close/focus translation into `fl.core`'s existing event-state fields,
dispatched via the same `fl.core.dispatch()` mechanism `fl.platform_x11`
uses. A real `fake_X_wm()` port (`fakeXWm()`) — `AdjustWindowRectEx()`-
based border/title-bar geometry, falling back to `GetSystemMetrics()`
estimates exactly as FLTK's own fallback branch does — feeds both
initial window creation (real style-flag computation matching FLTK's
`wintype` switch: `WS_POPUP`/`WS_DLGFRAME|WS_CAPTION`/`WS_THICKFRAME|
WS_CAPTION` depending on `border()`/`isResizable()`/`modal()`) and
application-initiated resize (`resizeWindow()`, border-compensated
`SetWindowPos()`); the same geometry backs real `WM_GETMINMAXINFO` live
size-range enforcement during an interactive resize drag. Windows' own
native double-click detection (`CS_DBLCLKS`/`WM_*BUTTONDBLCLK`) is used
directly rather than porting X11's manual click-timing heuristic — a
genuine platform capability difference, not a simplification. Keyboard
translation peeks ahead for a `WM_CHAR`/`WM_SYSCHAR` already queued by
`TranslateMessage()` (mirroring `Fl_win32.cxx`'s own
`PeekMessageW(..., PM_REMOVE)` technique) so one physical keypress
produces one `Event.keyDown`/`keyUp` dispatch carrying both
`eventKey()` and `eventText()` together, rather than firing twice.
`createWindow()`'s `ShowWindow()` call follows FLTK's
`ShowWindow(..., (Fl::grab() || (styleEx & WS_EX_TOOLWINDOW)) ?
SW_SHOWNOACTIVATE : SW_SHOWNORMAL)`, so any borderless top-level window
(tooltips, popup menus; `WS_EX_TOOLWINDOW`) is shown without activating
it and doesn't steal focus from the application's main window. FLTK's
tooltip/menu windows are ordinary `Fl_Menu_Window`s on every platform
including Windows.

**Drawing**: `fl.gdi_graphics_driver.GdiGraphicsDriver` covers
`fl.graphics_driver.GraphicsDriver`'s full abstract surface (color/rect/
line/polygon/lineStyle/clip/arc/pie/vertex-path/text) with real GDI
calls; `fl.graphics_driver.currentDriver` stays live for real,
interactive on-screen rendering rather than an offscreen/export surface.
A real per-index `Fl_XMap`-style 256-entry
color table plus a 16-slot brush LRU (`fl_brush_action()`-style
usage-count eviction) replaces a naive recreate-every-call approach.
Coordinate-taking primitives (`rectf`/`rect`/`line`/`xyline`/`yxline`/
`polygon`/`arc`/`pie`/`pushClip`/`drawImage`/`drawImageAlphaBlended`/
`drawBitmap`) scale directly (this port has no `Fl_Scalable_Graphics_
Driver`-equivalent decorator, matching the "fold scaling directly in"
precedent already established for X11) from `fl.core.currentScale()`,
the live drawing-scale cache, refreshed from each window's own
independent per-screen DPI (`fl.core.screenScale(win.screenNum())`) at
every `make_current()`-equivalent call site. `pushClip`/`drawImage`/`drawImageAlphaBlended`/`drawBitmap` take their
rectangles through `floorScaled()` like every sibling primitive, so a
clip region matches the content drawn into it and any `Fl_RGB_Image`/
`Fl_Pixmap`/`Fl_Bitmap`-drawn content (including
`fl.adjuster.Adjuster`'s own arrow glyphs) grows with the display. The
vertex-path `end*()` family needs no scaling of its own, since
`fl.draw`'s own `vertex()`/`transformedVertex()` already scale every
point before handing it to a driver that wants scaled coordinates —
GDI/GDI+ included, since both keep `GraphicsDriver.
wantsUnscaledVertices()`'s default `false` (unlike `GlGraphicsDriver`/
`PostscriptGraphicsDriver`/`SvgGraphicsDriver`, which override it to
`true` — see that method's own doc comment for the full split).
By default, on-screen drawing
actually goes through `fl.gdiplus_graphics_driver.GdiPlusGraphicsDriver`
instead (see below) — plain `GdiGraphicsDriver` is the fallback if GDI+
initialization fails; `GdiPlusGraphicsDriver` doesn't override any of
`pushClip`/`drawImage`/`drawBitmap`/font handling, so this fix (and the
font scaling below) apply to both drivers.

**Fonts/text**: a real per-`(face,size,angle)` `HFONT` cache
(`CreateFontW()`/`GetTextMetricsW()`), family names resolved from
`fl.draw.getFont()` to real Windows font names (FLTK's own
per-platform `built_in_table[]` choice — "Microsoft Sans Serif"/
"Courier New"/"Times New Roman"/"Symbol"/"Terminal"/"Wingdings",
distinct from Xft's generic Fontconfig aliases), a real per-codepoint
width cache with FLTK's genuine multi-vs-single-codepoint
measurement split, tight `GetGlyphIndicesW()`/`GetGlyphOutlineW()`
glyph-ink `textExtents()` (falling back to `GetCharacterPlacementW()`
for UTF-16 surrogate pairs, and only to a typographical approximation if
neither succeeds), real rotated text via the angle-keyed font cache
(`draw(int angle, ...)` — matching this port's own X11/Xft path, which
rotates on-screen text too, see `FL/fl_draw.H`'s row), and real
font/size enumeration (`setFonts()`/`getFontSizes()` via
`EnumFontFamiliesW()`, including FLTK's own "only synthesize
bold/bold-italic variants from a face's regular weight" quirk).
`nonspacing()` is ported (`fl.nonspacing`, mechanically generated from
FLTK's `spacing.h` range tables rather than hand-typed, with each table's
compile-time length assertion guarding against miscounts):
`textWidth()`'s per-codepoint loop skips a combining mark's own advance
width, as FLTK does. `smoke-tests/nonspacing_width.d` is the check: a
combining acute accent and a combining left-harpoon-above both measure
`0` alone, while their base letters and the same accent measured as part
of a whole string are unaffected.

Font size is scaled: `fontFor()`'s `CreateFontW()` takes the size
multiplied by the scale (`scaledFontSize()`, matching
`Fl_Scalable_Graphics_Driver::font()`: `font_unscaled(face,
Fl_Fontsize(size * scale()));`), and every reported metric —
`heightFor()`, `fontHeight()`, `fontDescent()`, `textWidth()`,
`textExtents()` — is divided back down by the same factor before
returning, matching `Fl_Scalable_Graphics_Driver::height()`/`descent()`/
`width()`/`text_extents()`'s own unconditional `/scale()` divisions.
Without this, glyphs stay pinned at their native 100%-scale pixel size
while the box/line primitives around them grow with the display.

`fl.draw.d`'s text-primitive composition layer (the box-aligned/wrapped/
symbol-and-underline-aware `fl_draw()` overload and its thinner
forwarding siblings, `rtlDraw()`, `width(str)`/`textExtents(str,...)`)
is 100% platform-independent — built entirely from leaf functions
(`fl_font()`, `height()`, `descent()`, `width()`) with zero direct
Xft/GDI calls of its own, so it's a single shared implementation serving
Windows and any future non-Linux platform for free; only the true
per-platform leaves get their own `version (Windows) {} else {}` split
(see `FL/fl_draw.H`'s row).

**Cursors**: the full `Fl_WinAPI_Window_Driver::set_cursor(Fl_Cursor)`
switch (every stock `IDC_*` mapping, including FLTK's own N/S->NS
etc. aliasing and the real `Cursor.default_`-has-no-case gap, faithfully
reproduced rather than fixed), `WM_SETCURSOR` handling that keeps
re-asserting the stored per-window cursor (seeded with the real arrow
cursor at window-creation time, so a window that never sets a custom
cursor still gets a sane default instead of `WM_SETCURSOR` re-asserting
nothing), and a full `image_to_icon()` port (`BITMAPV5HEADER`/
`CreateDIBSection()` ARGB bitmap, 1bpp mask, `CreateIconIndirect()`) for
custom RGBA cursors.

**Multi-monitor/DPI**: real `EnumDisplayMonitors()`/`GetMonitorInfoW()`
screen enumeration (a dynamic array, matching
`fl.platform_x11.ScreenInfo[]`'s own precedent rather than FLTK's
fixed `MAX_SCREENS`), real per-monitor work areas, and a scaled/unscaled
split throughout (`screenXYWH()`/`screenWorkArea()`/`screenNum()`/
`getMouse()`, matching `fl.platform_x11`'s identical convention) so
every FLTK-unit-facing caller divides by the real scale rather than
seeing raw device pixels. DPI-awareness activation
(`SetProcessDpiAwarenessContext`/`SetProcessDpiAwareness` fallback chain,
resolved via `GetProcAddress()`/`LoadLibrary()` since these Shcore.dll-
era APIs aren't declared in this project's druntime version) seeds
`fl.core.screenScale()`'s real per-screen array from each monitor's own
independent DPI (`GetDpiForMonitor()` via `MonitorFromRect()` per
screen), matching FLTK's genuine independent per-monitor
`Fl_WinAPI_Screen_Driver::desktop_scale_factor()` loop exactly.
`WM_DPICHANGED` resizes only the window it fired for, and a
cross-screen move correctly relocates a shown window's own screen
cache. Two windows open simultaneously on two differently-scaled
monitors are both correct at once — confirmed on real multi-monitor
hardware (`smoke-tests/multi_monitor_scale.d`).

**Live DPI change**: `wndProc()`'s `case dpiChangedMessage:`
(`WM_DPICHANGED`'s `0x02E0` isn't declared in this druntime version)
resolves the new screen via the real `screenNumUnscaled()` on the
*center* of Windows' suggested new-window rect (matching `Fl_win32.cxx`'s
own `screen_num_unscaled(centerX, centerY)`), then resizes/relocates that
one window directly via `Window.resizeAfterScaleChange()` — **not**
`fl.core.rescaleAllWindowsFromScreen()`'s sibling-broadcasting version:
Windows delivers `WM_DPICHANGED` per-window already, so broadcasting to
every window on the destination screen would duplicate work and could
overwrite an already-correct sibling's own Ctrl-+/-- zoom. Two guards
matter here: `WM_SIZE` has the `resizeBugFix_` echo-guard `WM_MOVE` also
has (matching FLTK's `resize_bug_fix = window;` before `window->size(...)`),
without which the synchronous `WM_SIZE` echo of a rescale's own
`SetWindowPos()` call re-issues *another* real resize on every message,
a runaway cascade that collapses the window; and
`seedScaleFromPrimaryMonitor()` queries `MonitorFromPoint()` at literal
`(0, 0)` rather than `screens_[0]`'s origin, since monitor enumeration
order doesn't necessarily put the real primary first. As in FLTK, a
window created without an explicit position opens via
`CW_USEDEFAULT`, with no active-monitor logic.

**Clipboard**: real, fully synchronous `OpenClipboard()`/
`SetClipboardData(CF_UNICODETEXT, ...)` for `copy()` and
`GetClipboardData()` for `paste()` (FLTK's Windows clipboard never
uses delayed `WM_RENDERFORMAT` rendering at all) — text always, image
for the common direct-`CF_DIB` case (`BI_RGB`, 24/32bpp, no color
table). Windows has no real PRIMARY selection: `copy(..., 0)`/
`paste(..., 0)` stay this-process-local, matching FLTK's own
unconditional `!clipboard` branch. `Fl::add_clipboard_notify()` uses the
`SetClipboardViewer()`/`WM_DRAWCLIPBOARD`/`ChangeClipboardChain()`
viewer-chain mechanism, ported verbatim from `Fl_win32.cxx`'s file-scope
`fl_clipboard_notify_*()` functions and `WndProc()`'s own
`WM_CHANGECBCHAIN`/`WM_DRAWCLIPBOARD` cases (`source/test/clipboard.d`
exercises it).
Both of FLTK's image-paste fallbacks are ported, both built on a real
Windows offscreen surface (`fl.image_surface.ImageSurface`): the
"complex DIB" fallback (palette-indexed/compressed `CF_DIB`, decoded by
handing the raw bits to Windows itself via `SetDIBitsToDevice()` onto an
offscreen `ImageSurface`) and the `CF_ENHMETAFILE` fallback (rasterized
via `PlayEnhMetaFile()` onto a `highRes`-scaled `ImageSurface`).
`clipboardContains()` checks both `CF_DIB` and `CF_ENHMETAFILE`, matching
FLTK exactly. `smoke-tests/clipboard_image_fallbacks.d` manufactures both
tricky payloads itself via direct GDI calls rather than depending on a
third-party app that happens to produce one; both a hand-built
palette-indexed `CF_DIB` and a `CF_ENHMETAFILE`-only clipboard entry (no
`CF_DIB`/`CF_BITMAP` alongside it) decode and display correctly.

**Window state**: real fullscreen (monitor-spanning move/resize
stripping `WS_THICKFRAME|WS_CAPTION`; `fullscreenOff()` genuinely
re-applies the pre-fullscreen geometry itself, since Windows — unlike a
cooperating EWMH window manager — never restores it automatically), real
OS-level maximize/iconize (`ShowWindow(SW_SHOWMAXIMIZED)`/
`SW_SHOWNORMAL`/`SW_SHOWMINNOACTIVE)`), `WM_SIZE`-based tracking of an
externally-triggered maximize/restore (double-clicking the title bar,
Win+Up/Down) into `maximizeActive()`, a genuinely born-iconic window
when `iconize()` is called before the first `show()` (matching
`fl.platform_x11`'s identical `WM_HINTS`/`IconicState` mechanism), and
real window icons via `WM_SETICON` (reusing the `image_to_icon()` helper
built for custom cursors, plus a `find_best_icon()` port choosing the
closest available size to `GetSystemMetrics(SM_CXICON)`/`SM_CXSMICON`).
One deliberate simplification: no shared process-wide default-icon
cache (a fresh `HICON` is built on every call instead, since there's no
shared mutable state to worry about corrupting). One deliberately-
unported piece: FLTK's manual resize-to-work-area fallback for
maximizing a borderless window, since this port's Linux side doesn't
implement that fallback either.

**`Fl::add_fd()`** is real, though structurally different from the Linux
side's `select()`-based multiplexing:
Windows anonymous pipes (this project's only real consumer,
`source/examples/howto_add_fd_and_popen.d`'s piped child-process
stdout) can't be waited on via `WaitForMultipleObjects()`/
`MsgWaitForMultipleObjects()` at all — a genuine Windows platform
limitation, not a gap this port could close by trying harder — so
`fl.platform_win32.pollFds()` polls every registered `fdRead` entry via
`PeekNamedPipe()` on a short timer (`fdPollInterval`, 50ms) instead of
truly blocking on it. `fdWrite`/`fdExcept` aren't backed (no
`PeekNamedPipe()`-equivalent non-blocking check exists for those on an
anonymous pipe, and nothing in this project registers for them).

**Drag-and-drop**: the genuine FLTK COM mechanism (`fl_dnd_win32.
cxx`'s `FLDropTarget`/`FLDropSource`/`FLDataObject`, `IDropTarget`/
`IDropSource`/`IDataObject`, `DoDragDrop()`/`RegisterDragDrop()`), not
the simpler `WM_DROPFILES` shell mechanism
— this project's first COM interop of any kind, with every interface
signature cross-checked against the real
`core.sys.windows.{oleidl,objidl,unknwn,uuid}` headers. A single
process-wide `FLDropTarget` (matching FLTK's own single static
instance) receives real drops, dispatching into the same platform-
independent `fl.core.handle()`/`deliverPaste()` machinery X11's own XDND
already uses; the drag-source half is a single blocking `DoDragDrop()`
call, replacing X11's own hand-built poll loop. Text-only *delivery*,
matching this port's already-established X11/XDND MIME-negotiation
scope (see `FL/x.H`'s row) — but `fillCurrentDragData()` covers all
three of FLTK's own source formats: `CF_UNICODETEXT`
(preferred), legacy `CF_TEXT`/CP1252 (decoded via `MultiByteToWideChar
(CP_ACP, ...)`, the standard Win32 idiom, rather than transliterating
FLTK's own `fl_utf8decode()`/`fl_utf8encode()` byte-reinterpretation
trick, which this port has no equivalent of to reuse), and `CF_HDROP`
(a file-manager's dropped-file list, delivered as the same `\n`-joined
path-list `Event.paste` text FLTK sends). `FLEnum`/`IEnumFORMATETC`
is still skipped entirely since FLTK's own `EnumFormatEtc()` is
unconditional `E_NOTIMPL` with `FLEnum` itself commented out in the real
source — genuinely dead code FLTK never executes, not a port gap.
`source/examples/howto_drag_and_drop.d` confirms dragging one or more
files from Explorer onto an fldtk window lists their names. The legacy
`CF_TEXT`/CP1252 branch is unconfirmed on real hardware (no legacy
ANSI-only drag source was tried), but is a straight port of the standard
`MultiByteToWideChar(CP_ACP, ...)` idiom.

**GDI+ (antialiased rendering, on by default)**: `fl.gdiplus` (a
hand-written binding against GDI+'s flat C API, verified against a real
local copy of Wine's own GDI+ headers, since D can't call GDI+'s C++
wrapper classes at all and this dev environment has no Windows SDK)
backs `fl.gdiplus_graphics_driver.GdiPlusGraphicsDriver :
GdiGraphicsDriver`, overriding only the antialiasing-relevant subset
(`color()`, `line()`, `polygon()`, `arcUnscaled()`/`pieUnscaled()`,
`lineStyle()`, the vertex-path `end*()` family) and reusing everything
else (text, images, clipping, `rect()`/`rectf()`/`xyline()`/`yxline()`)
from the plain GDI driver unchanged, mirroring FLTK's own
`Fl_GDIplus_Graphics_Driver` inheritance shape exactly.
`fl.platform_win32.ensureGraphicsDriver()` creates this driver by
default, falling back to plain GDI only if `GdiplusStartup()` itself
fails — matching FLTK's own `FLTK_GRAPHICS_GDIPLUS` CMake option,
which defaults **ON** for a real FLTK Windows build, not a
fldtk-only embellishment. `circle()`/`vertex()`/`loop()` don't exist as
driver-level methods in this port at all (both `fl.draw.circle()`'s
32-gon decomposition and `fl.draw.loop()`'s multi-segment `line()`
decomposition predate this driver), so neither needed a GDI+ override —
both still gain real antialiasing for free through the driver methods
they already funnel through, with one narrow, documented cosmetic
difference: a loop's shared vertices get N separately end-capped
antialiased segments meeting at a point instead of FLTK's one
continuously joined path. One confirmed real FLTK bug (`line_
style()`'s cap/join dispatch tests overlapping raw bits, silently
turning any `FL_CAP_SQUARE`/`FL_JOIN_BEVEL` request into round-cap/
miter-join) is deviated from rather than faithfully reproduced (see
`FLTK_ISSUES.md`); one real representational adaptation was needed
for arc/pie pen width, since this port's `lineWidth_` is already the
scaled value FLTK's own same-named formula assumes is still raw at
that point. No `GdiplusShutdown()` exit hook — this port has never had
an equivalent process-exit cleanup hook for any Windows GDI resource, so
GDI+ doesn't get a new one either; the OS reclaims the token on process
exit regardless.

**Build**: `dub.sdl` builds fldtk as a **static** library on Windows
(the `windows-default` configuration's `targetType "staticLibrary"`, vs.
`targetType "dynamicLibrary"` in the Linux configurations) rather than a dynamic one
— a Windows DLL only exports symbols explicitly marked with D's `export`
attribute, which none of `fl.*` has ever needed since Linux was always
the primary target, so a static library sidesteps the question entirely;
real Windows DLL support would need an `export`-annotation audit across
the whole `fl.*` surface, not attempted. The Windows `libs` line needs
`gdi32`/`user32`/`ole32`/`gdiplus` for the real Win32/COM/GDI+ calls this
port makes, plus `kernel32`/`msvcrt120`/`oldnames` explicitly — dmd only
auto-injects its own default runtime libraries when *no* explicit `.lib`
is given on the command line at all, so listing any Windows lib at all
(as this port must) requires listing the CRT ones too, sidestepping
dmd's default-injection logic entirely rather than depending on it. No
external Windows SDK or Visual Studio C++ workload install is needed:
dmd bundles a complete MinGW-w64-derived import-library set covering the
whole Win32 API surface, which `lld-link` finds automatically.

**Native on-screen image/bitmap drawing**: `GdiGraphicsDriver.drawImage()` blits via `StretchDIBits()` for the
opaque case and real per-pixel `AlphaBlend()` compositing (`msimg32.dll`,
via `CreateDIBSection()` + a premultiplied BGRA DIB) for `d==2`/`4` when
available, falling back to a fixed-white-background blend otherwise —
ported from `Fl_GDI_Graphics_Driver::draw_rgb()`'s own `alpha_blend_()`
call, but rebuilding the DIB fresh per call rather than FLTK's
persistent per-`Fl_RGB_Image` cache (this port has no image-object cache
anywhere, matching the Linux side's own established scope). `drawBitmap()`
uses the classic two-pass masked `StretchBlt()` technique (`SRCAND` then
`SRCPAINT` against a real monochrome `HBITMAP`, GDI's own documented
mono-to-color "color expansion" rule) rather than `MaskBlt()`/
`TransparentBlt()` (`msimg32.lib`-only) — and, unlike `fl.postscript.
PostscriptGraphicsDriver.drawBitmap()`'s faithfully-preserved FLTK
quirk of ignoring `cx`/`cy`, this one honors them for real (a genuine
sub-rectangle crop before scaling), since `GraphicsDriver.drawBitmap()`'s
own doc comment leaves that choice to each concrete driver and honoring
it is the more useful behavior for an interactive on-screen driver.
`RGBImage`/`Bitmap`/`Pixmap`-labeled widgets render on Windows;
surface-device capture (EPS/SVG export) forwards through `currentDriver`
regardless of platform.

Missing: FLTK's manual resize-to-work-area fallback for maximizing a
borderless window, and `IEnumFORMATETC` (dead code FLTK itself never
executes, not a port gap).

**Damage-rectangle-clipped repaint**: `InvalidateRect()` is called with
the real accumulated damage rectangle, not `null` (whole-window),
matching `fl.platform_x11`'s per-window damage-rectangle tracking.

**IME**: composed/committed input-method text (CJK, the Windows emoji
picker) arrives as a standalone `WM_CHAR` with no preceding keydown, and
`WndProc()` forwards it to the widgets rather than discarding it. Also
real: UTF-16 surrogate-pair merging, AltGr-aware dead-key composition
(`fl.core.compose()`'s Windows branch), and `enableIm()`/`disableIm()`/
`setSpot()` (the explicit IME on/off toggle, and "over the spot"
composition-window positioning for `fl.text_display`'s existing call
site) — see `fl.platform_win32`'s own module comment. `smoke-tests/ime.d`
confirms the Windows emoji picker (Win+.) delivers correct text,
including a surrogate-pair emoji. Keyboard translation is layout-aware
for punctuation keys, beyond FLTK's US-only table (see `oemKeysym()`).

Verified on a real Windows 11 machine (dmd, no Visual Studio/Windows SDK
installed): `dub build`, `dub test`, and real sample programs
(`buildsamples.d`) all build and link end-to-end, and the interactive
Windows smoke tests (`window_win32.d`, `fullscreen.d`, `size_range.d`,
`born_iconic.d`, `icons.d`, `ime.d`) have been run and confirmed there.
Known FLTK bugs found on the way are in `FLTK_ISSUES.md`.

### `FL/mac.H`

**Status:** Not started — *(planned: `fl.platform.cocoa`)*
([header](https://github.com/fltk/fltk/blob/master/FL/mac.H))

Out of scope for testing (no macOS hardware available), but the driver
abstraction is meant to leave room for a Cocoa backend later.

### `FL/Fl_Sys_Menu_Bar.H`

**Status:** Complete (minimal) — `fl.sys_menu_bar`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Sys_Menu_Bar.H))

A trivial subclass of `fl.menu_bar.MenuBar`. FLTK's every instance method
follows an `if (driver()) driver()->X(); else Fl_Menu_Bar::X();` shape —
with no macOS driver in this port at all (`driver()` permanently null),
every one of those degenerates to plain `MenuBar` behavior, inherited for
free. Only the genuinely Mac-only surface exists as real API:
`about(Callback)` (a permanently inert no-op — FLTK's own doc comment
says it's effective only on macOS) and `isGlobal()` (always `false`).
`windowMenuStyle()`/`createWindowMenu()` (macOS-only static
configuration) aren't ported.

## Printing / off-screen surfaces

### `FL/Fl_Copy_Surface.H`

**Status:** Complete — `fl.widget_surface.CopySurface`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Copy_Surface.H))

Draws into an off-screen `Pixmap`; on destruction, reads it back and
claims real X11 selection ownership of it as `image/bmp`.

- Folds FLTK's abstract `Fl_Copy_Surface` and its X11 driver body
  (`Fl_Xlib_Copy_Surface_Driver`) into one class — this port's usual "no
  polymorphic driver hierarchy for a single implementation" rule.
- `translate()`/`untranslate()` are real, backed by `fl.draw`'s general
  `pushTranslate()`/`popTranslate()` coordinate-offset stack (also used by
  `ImageSurface`, see below).

### `FL/Fl_Image_Surface.H`

**Status:** Partial — `fl.image_surface.ImageSurface`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Image_Surface.H))

Folds FLTK's abstract `Fl_Image_Surface` and its X11 driver body into one
class, same "no polymorphic hierarchy for one implementation" rule as
`CopySurface`. Real `mask()` support (matching FLTK's own lazy,
snapshot-then-blend-on-`image()` design, several masks in succession
supported). **`highRes`/`rescale()`/`printableRect()`** are real: `highRes` sizes
the offscreen buffer at `fl.core.currentScale()` device pixels per FLTK
unit (matching every `Fl_*_Image_Surface_Driver` constructor's own
scale-aware sizing), and `image()` scales the returned `RGBImage` back
down to the surface's logical FLTK-unit size, so a `highRes`-constructed
surface's image has real, higher-resolution pixel data while still
reporting its original `w()`/`h()`. `rescale()` recreates the offscreen
for the *current* scale and redraws the previous content into it,
letting `fl.draw`'s own already scale-aware primitives resample as a side
effect — matching FLTK's own `rgb->draw(0,0)`-onto-a-freshly-scaled-driver
approach.
Missing:
- The externally-owned-offscreen constructor overload (`Fl_Offscreen off`
  parameter) and `highres_image()` (a `deprecated` `Fl_Shared_Image`-
  returning convenience wrapper around `image()`+`printable_rect()`,
  both real here already) — no caller needs either.
- `print_window_part()` (needs GL-subwindow-aware on-screen capture-and-
  composite, no caller) — inherited from `WidgetSurface`, see that row.

### `FL/Fl_Widget_Surface.H`

**Status:** Partial — `fl.widget_surface.WidgetSurface`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Widget_Surface.H))

A real base class (unlike `fl.platform_x11`/`GraphicsDriver`'s "fold the
driver away" precedent — FLTK itself has multiple real public subclasses
of `Fl_Widget_Surface`, not just per-platform driver variants of one).
`draw(Widget)`/`traverse()` (recursing into subwindows), `origin()`, and
`drawDecoratedWindow()` (capturing a real on-screen title bar) are real.
Current subclasses: `ImageSurface`, `CopySurface`,
`fl.svg_file_surface.SvgFileSurface`, `fl.postscript.EpsFileSurface`, and
`fl.paged_device.PagedDevice` (itself base to `fl.postscript.
PostscriptFileDevice`, in turn base to `fl.printer_posix.Printer`;
`fl.printer_win32.Printer` extends `PagedDevice` directly — see
`FL/Fl_Printer.H`'s row).

- `drawDecoratedWindow()` faithfully reproduces a real FLTK asymmetry on
  Linux: only the *top* title-bar image is ever populated; left/right/
  bottom stay permanently null.

Missing:
- `print_window_part()` — no caller (needs GL-subwindow compositing).
- `printableRect()`'s real per-subclass override stays FLTK's own trivial
  "always fails" base body here too — only `Fl_Printer`/
  `Fl_PostScript_File_Device` give it a real answer in FLTK itself, and
  both are ported (see their own rows).

**D-specific gotcha, not a FLTK difference**: `draw(Widget, int,
int)` reads the surface's current origin via `xOffset_`/`yOffset_`
directly rather than calling `origin(out int, out int)`. Calling the
getter by name (`origin(oldX, oldY)`, two plain `int` locals) is
ambiguous with the *setter* `origin(int, int)` declared right next to it
— both are viable overloads for two `int` lvalue arguments — and once a
subclass overrides the setter (`fl.printer_win32.Printer`,
`fl.postscript.PostscriptFileDevice`, ...), D resolves the call to that
*overridden setter*, not the getter. That would silently re-apply
`origin(0, 0)` on every widget draw, discarding whatever page-centering
origin the caller had set (printed output would center around the page's
top-left corner instead of its center). It is a D overload-resolution
gotcha in shared code, so it would affect PostScript export identically.
`fl.postscript.PostscriptFileDevice.rotate()` has the identical call
shape and likewise reads `xOffset_`/`yOffset_` directly instead of
calling `origin(x, y)`.

### `FL/Fl_Printer.H`

**Status:** Partial — `fl.printer.Printer`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Printer.H))

`fl.printer` is a thin `version()` dispatcher: FLTK's own
`Fl_Printer::newPrinterDriver()` returns a completely different concrete
driver per platform, and this port has real, independent
implementations for both — `fl.printer_posix.Printer` (Linux/Wayland/any
other non-Windows platform) and `fl.printer_win32.Printer` (Windows),
each providing its own `Printer` class, matching the same one-module-
per-platform split already used for the windowing layer
(`fl.platform_x11`/`fl.platform_win32`). Unlike that split,
`fl.printer_posix` itself has no `version()` guard and compiles on every
platform — `fl.printer`'s dispatcher only *selects* it by default on
non-Windows platforms; on Windows it stays available for direct
construction so `smoke-tests/printer_fltk_dialog.d` can preview the
FLTK-drawn `PrintPanel` dialog there (printer enumeration and job
submission are both inert on that platform, since they shell out to
`lpstat`/`lp`/`lpr` — see that smoke test's own header comment).

`fl.printer_posix.Printer` folds FLTK's `Fl_Printer` and
`Fl_Posix_Printer_Driver` into one class extending `fl.postscript.
PostscriptFileDevice`. `beginJob()` shows a real, interactive print
dialog (a faithful port of FLTK's own Fluid-generated `print_panel`/
`print_properties_panel`, including the page-size/output-mode Properties
sub-panel and real Collate handling), then either falls back to file
output or pipes finished PostScript to `lp`/`lpr` via
`std.process.pipeShell()`.

Differences from FLTK (POSIX half):
- The Collate checkbox is real/reachable here, unlike FLTK's own dialog,
  where the reactivating branch of `cb_print_copies()` is dead code —
  a deliberate deviation completing that dead code's evident intent.
- `Fl_Menu_Item::user_data()`'s printer-name-per-choice-entry smuggling
  becomes a plain parallel `string[]` array. `popen()`/`pclose()` become
  `std.process.pipeShell()`/`wait()`. `lpstat -p -d`/`/etc/printcap`
  parsing is factored into pure, independently-tested functions separate
  from the subprocess-spawning glue.
- Per-printer page-size/output-mode preferences persist via
  `fl.preferences`, same scope/key FLTK uses — but the stored `output_mode`
  index is clamped before use rather than trusted straight from an
  unvalidated preferences file (FLTK's own read is an unchecked
  out-of-bounds risk on a corrupted prefs file — see `FLTK_ISSUES.md`).

Missing (POSIX half):
- `Fl_GTK_Printer_Driver` (the `dlopen()`-at-runtime GTK dialog) — FLTK's
  own doc comment calls it a cosmetic enhancement layered on top of the
  dialog this port already has, not a functional requirement.

`fl.printer_win32.Printer` extends `fl.paged_device.PagedDevice`
directly (not `PostscriptFileDevice` — nothing here is PostScript-shaped),
matching FLTK's own `Fl_WinAPI_Printer_Driver`. It runs the native
`PrintDlg()` common dialog (Windows' own OS-provided printer picker,
querying the print spooler directly — there's no FLTK-drawn dialog on
this platform at all, so no `PrintPanel`-equivalent exists here), then
drives the job via plain GDI (`StartDoc()`/`StartPage()`/`EndPage()`/
`EndDoc()`) straight into the printer's own `HDC`, reusing this port's
existing on-screen `fl.gdi_graphics_driver.GdiGraphicsDriver` (a fresh
instance per `Printer`, matching FLTK's own fresh-instance-per-job
`Fl_GDI_Printer_Graphics_Driver`) for the actual drawing.

Differences from FLTK (Windows half):
- No dedicated `Fl_GDI_Printer_Graphics_Driver`-equivalent subclass:
  text/rects/lines/polygons/arcs/clipping all draw identically against a
  printer `HDC` via the same `GdiGraphicsDriver` this port already has,
  so only two real printer-specific pieces were needed on top of it — a
  per-instance `useFixedScale(1.0)` (a printer's own `MM_ANISOTROPIC`
  logical-coordinate mapping already accounts for the physical page size
  independent of the *screen's* DPI, so the driver's normal DPI-scaling
  multiplier must be neutralized for print output — see
  `GdiGraphicsDriver.useFixedScale()`'s own doc comment), and the
  page/job-lifecycle math (`margins()`/`origin()`/`scale()`/`rotate()`/
  `translate()`/`untranslate()`) `PagedDevice` itself doesn't provide.
  `GdiGraphicsDriver.drawImage()` has a real dithered-mask fallback
  (ported from `Fl_GDI_Graphics_Driver::create_alphamask()`) for the
  case a printer is most likely to hit — a printer driver whose DDI
  doesn't implement `AlphaBlend()` — giving genuine, if coarser
  (screen-door dithered, not smoothly blended), per-pixel transparency
  instead of a flat opaque blend. `Fl_Bitmap`/`Fl_Pixmap` printing uses
  this port's plain on-screen `drawBitmap()` body rather than FLTK's
  printer-specific `TransparentBlt()` workaround; that workaround exists
  to route around an undocumented "secret" ternary ROP code this port's
  `drawBitmap()` never uses (it uses the standard, documented two-pass
  AND/OR `StretchBlt()` technique), so the risk it addresses is narrower
  here. No sample in this port's own tree prints a transparent image.
- `printableRect()` caches its result (refreshed by `beginPage()`/
  `scale()`) rather than recomputing — with real side effects, including
  resetting the HDC's window origin — on every single call the way
  FLTK's own `absolute_printable_rect()` does: `fl.widget_surface.
  WidgetSurface.printableRect()` is `const` (every other subclass's
  override is a pure read), and the paper size/DPI can't change mid-job
  regardless, so this is a type-system accommodation with no observable
  behavior difference for any real caller.
- `beginPage()` also calls `fl.draw.resetClipStack()` where FLTK calls
  `fl_clip_region(0)` — ported for its *effect*, not its mechanism, since
  the two aren't structurally equivalent: FLTK's clip stack
  (`Fl_Graphics_Driver::rstack`) is a member of each
  `Fl_Graphics_Driver` instance, so a fresh per-job driver already
  starts clean and that call is close to a no-op there; this port's
  clip stack (`fl.draw`'s `clipStack_`) is a single module-level stack
  shared by every surface/driver, so without an explicit reset a fresh
  print job's first `pushClip()` could in principle inherit a rectangle
  the last on-screen draw left active.
- **Printer clip regions**: `GdiGraphicsDriver.pushClip()` (`fl.gdi_graphics_
  driver.d`) maps the clip rectangle's 4 corners through `LPtoDP()` and
  builds a polygon region from the mapped points (4 corners, not 2, since
  a rotation may be in effect) whenever `useFixedScale()` is active,
  matching `Fl_GDI_Graphics_Driver::XRectangleRegion()`'s off-screen
  branch. A plain rect region built from the raw logical-space rectangle
  is right for an on-screen `MM_TEXT` surface (logical and device units
  are 1:1, modulo this port's separate `effectiveScale()` DPI
  multiplier) but wrong for the printer's `MM_ANISOTROPIC` mapping (plus
  a possible `GM_ADVANCED` world-transform rotation), where logical
  points and device pixels differ, often by a factor of several, and
  `useFixedScale(1.0)` leaves nothing else to convert the units.
  `SelectClipRgn()`, unlike ordinary GDI drawing calls, takes its region
  in device units and does *not* auto-convert via the current mapping
  mode, so an unconverted region would clip everything down to a tiny
  corner of the real, much larger device canvas.
- **Printed-page origin**: `fl.widget_surface.WidgetSurface.draw()` reads
  the current origin via `xOffset_`/`yOffset_` directly rather than
  `origin(oldX, oldY)`, which D would resolve to the overridden *setter*
  `Printer`/`PostscriptFileDevice` define (see `FL/Fl_Widget_Surface.H`'s
  row for the mechanism). Otherwise the origin is reset to `(0, 0)` right
  before every widget draw, discarding the page-centering origin the
  caller set (`device.d`'s `p.origin(w/2, h/2)`), and the whole printed
  window lands around the page's top-left corner. With both fixes
  `device`'s "Printer" output prints the full target window, correctly
  scaled and centered on the page, matching FLTK.

Missing (Windows half):
- `Fl_PDF_GDI_File_Surface` (FLTK's own `Fl_PDF_File_Surface` backing
  implementation, via Windows' "Microsoft Print to PDF" virtual printer)
  — `fl.pdf_file_surface` itself is `Deferred` project-wide (see
  `CONVENTIONS.md`'s Pango note), so there's no PDF surface class for this to
  back yet. Revisit together with that decision.

### `FL/Fl_PDF_File_Surface.H`

**Status:** Deferred (Pango) — *(planned: `fl.pdf_file_surface`)*
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_PDF_File_Surface.H))

FLTK's own implementation is unconditionally gated on Pango on Linux
(`new_platform_pdf_surface_()` returns a hard error without it, confirmed
by reading the real source, not just the doc comment) — genuinely blocked
on the same Pango decision already deferred project-wide (see
`CONVENTIONS.md`'s "Where this port intentionally exceeds FLTK"), not a
fresh gap.

### `FL/Fl_PostScript.H`

**Status:** Partial — `fl.postscript`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_PostScript.H))

Covers `Fl_EPS_File_Surface` (`EpsFileSurface`) and
`Fl_PostScript_File_Device` (`PostscriptFileDevice`) — only FLTK's own
non-Pango/non-Cairo code path is relevant here (both are `Deferred`
project-wide). `PostscriptGraphicsDriver` implements the same primitive
family as `fl.graphics_driver.GraphicsDriver` declares, including real
vectorized text (Latin + Latin Extended-A + PostScript's standard extra-
character set, real selectable/zoomable glyphs, not bitmaps), rotated
text, and RGB/RGBA/gray image plus 1-bit bitmap drawing (RLE+ASCII85-
encoded, no PNG/JPEG codec needed — PostScript image embedding works on
raw decoded pixel bytes).

Differences from FLTK:
- FLTK's vertex-path `concat()`/`reconcat()`/`gap_` state machine
  isn't ported: this port's `fl.draw` already resolves every vertex
  through the transform before a `GraphicsDriver` call ever sees it, so
  there's nothing left for that machinery to do.
- Since this driver's language level is always 2, FLTK's own real-
  transparency-masking machinery (Floyd-Steinberg dithering, level-3-only)
  is dead code even in FLTK itself at that level and isn't ported;
  RGBA/gray+alpha images alpha-blend against the page background instead,
  matching FLTK's own real level-2 fallback.
- A `Pixmap`'s transparent-color masking (native-GC-only state) isn't
  preserved under this driver — a printed `Pixmap` with a transparent
  color prints fully opaque.
- `close_command()`'s function-pointer customization hook collapses to a
  plain bool. `set_current()`/`end_current()` (saving/restoring the
  *display* driver's own cached font state across a print job) aren't
  ported — this port's `draw()` never mutates that global state, so
  there's nothing to disturb.

Missing:
- `transformed_draw_extra()`'s bitmap-fallback path (for fonts/codepoints
  outside the vector-text table) and `rtl_draw()` — a draw call that hits
  an unhandled font/codepoint draws nothing rather than mis-rendering.
- `EpsFileSurface.draw(Widget)`/`drawDecoratedWindow()` aren't safe on a
  general widget yet, since image dispatch, while real, wasn't exercised
  against every image kind — drive the surface directly until confirmed.

### `FL/Fl_SVG_File_Surface.H`

**Status:** Partial — `fl.svg_file_surface`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_SVG_File_Surface.H))

`SvgGraphicsDriver`/`SvgFileSurface` cover the full current
`GraphicsDriver` surface (rect/line/color/polygon, line style, clipping,
arcs/pies, the vertex-path family, plain and rotated text, and
images), ported faithfully from `Fl_SVG_Graphics_Driver`'s own element
shapes (same `rgb(r,g,b)` format, same transform-wrapped unit-circle
construction for arcs/pies).

Differences from FLTK:
- `pushClip()`/`popClip()` keep no separate clip-rectangle list of their
  own (unlike FLTK's `Clip*` linked list) — `fl.draw`'s own clip stack
  already tracks nesting correctly; only a monotonic id counter is needed.
- `endLoop()` has no FLTK counterpart to port from at all (FLTK's own
  driver never defines one) — implemented as a stroked path through the
  same points, matching `endLine()`.
- **Embedded images**: `drawImage()`/
  `drawBitmap()` both emit base64-PNG `<image>` elements (`fl.png_image`'s
  `encodePngBytes()` + `std.base64`). Two deliberate simplifications vs.
  FLTK's own `draw_rgb()`/`draw_pixmap()`/`define_rgb_png()`: no
  `<defs>`/`<use>` identity-based reuse caching (this port's unified
  `drawImage()` leaf never sees the source `RGBImage`/`Pixmap` object,
  only a raw buffer, so there's no pointer to key a cache on — each call
  emits its own `<image>`, larger output for a repeatedly-redrawn image
  but still correct), and PNG only, no JPEG variant (FLTK prefers JPEG
  for opaque images; PNG alone covers every channel depth here). Because
  images are embedded, `SvgFileSurface.draw(Widget)`/
  `drawDecoratedWindow()` are safe on a general widget: a widget that
  draws an image (icons, `Label.image`) doesn't mix real window pixels
  into what should be pure SVG output.

Missing:
- Nothing beyond what `FL/Fl_Graphics_Driver.H`'s row lists as not yet
  covered by `GraphicsDriver` itself (rotated text has no SVG-specific
  gap left — `SvgGraphicsDriver.draw(int,...)` already overrides it for
  real, see that method's own doc comment).

### `FL/Fl_Cairo.H`

**Status:** Deferred (Cairo) — *(planned: `fl.cairo`)*
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Cairo.H))

Matches `CONVENTIONS.md`'s "Deferred: external-library-backed features" list —
the Cairo rendering-backend decision hasn't been made project-wide.

### `FL/Fl_Cairo_Window.H`

**Status:** Deferred (Cairo) — *(planned: `fl.cairo_window`)*
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Cairo_Window.H))

A `Fl_Window` subclass whose entire purpose is exposing a Cairo drawing
context — same reasoning as `FL/Fl_Cairo.H`.

## Widget base, windows

### `FL/Fl_Widget.H`

**Status:** Complete — `fl.widget`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Widget.H))

The full base widget: geometry, label, callbacks, flags, focus/active/
visible, damage-bit propagation and accumulation (including a precise,
window-bounded damage rectangle, not a whole-widget fallback), `'&'`-
shortcut parsing/matching, real box/label/focus-ring drawing (all label
types including shadow/engraved/embossed effects and image-plus-text
composition), `window()`/`topWindow()`, and the `WidgetTracker`-guarded
`doCallback()`.

Differences from FLTK:
- `user_data()` as a plain per-widget tag is `userData()`/`userData(Object)`,
  an `Object` reference rather than a `void*`. `argument()` and
  `Fl_Callback_User_Data`/`AUTO_DELETE_USER_DATA` are not ported: callbacks
  are D delegates that capture their own context, and the GC owns the
  object. Fluid's `user_data {expr}` property emits `w.userData = expr;`
  for widgets (not menu items, which have no such slot) and is not applied
  to the live design canvas, since the expression is D source that cannot
  be evaluated at design time; `user_data_type` is read and dropped.
- `Widget.parent()`/`parent_` is typed as plain `Widget`, not `Group` —
  FLTK's own `Fl_Widget::parent()` returns `Fl_Group*`, which forces an
  unsafe cast (FLTK's own source comment calls it "a kludge") for a
  composed-but-not-actually-a-`Group` widget like `Fl_Value_Input`'s
  embedded `Fl_Input`. D's type system rejects that cast, so `parent_` was
  widened once at the source instead — every ancestor-walk consumer
  (`contains()`, `damage()`, `window()`, focus/belowmouse walks) only ever
  needs `Widget`-level information anyway; the few call sites that do need
  `Group`-specific behavior cast back explicitly.
- `imageLabel`'s pointer-punning-through-`text` mechanism isn't ported —
  FLTK's own doc comment calls it obsolete in favor of the `image()`/
  `deimage()` fields this port already has real.
- Box-fill/border dimming when `!activeR()` is real and matches FLTK's
  two-mechanism split exactly: a per-call `fl_inactive()` color transform
  for fills, and a scoped `drawBoxActive()` flag (mirroring FLTK's global
  `draw_it_active`) swapping between two pre-baked gray ramps for beveled
  frame/border rendering. Both mechanisms are required: dimming only
  labels, or only fills, leaves the other half visibly un-dimmed.

### `FL/Fl_Group.H`

**Status:** Complete — `fl.group`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Group.H))

**Ported as `FlGroup`, not `Group`** — the one deliberate exception (along
with `fl.clock`'s `Clock` -> `FlClock`) to this port's usual "drop the
`Fl_`/`Fl` prefix" naming convention: a bare `Group` collides with
`std.algorithm.iteration.Group` the moment generated code (which does a
wildcard `import fl; import std;`) names one. `fl.group`'s own doc comment has the full
reasoning. The rest of this section still says "Group" as shorthand for
the concept/FLTK's `Fl_Group`, not the literal D symbol, except where
noted.

Container/child-management surface, `resizable()`/`resize()`'s real
layout algorithm, `clipChildren()` (real clipping), `current()`/
`begin()`/`end()`, and `handle()`/`navigation()`.

- `sizes()`/`sizes_` (pre-1.4 compatibility) isn't ported — not applicable
  at FLTK 1.5.0.
- `handle(Event.focus)` preserves FLTK's C++ switch-fallthrough
  semantics: when the event isn't itself a navigation keystroke
  (`navkey()` returns 0 — focus assigned programmatically, or reached at
  a moment when the last real key event was something unrelated, e.g.
  Enter committing a text-input edit), it tries `savedfocus_` first but,
  if that fails, falls through into the same forward-order child scan
  the right/down case uses rather than giving up — FLTK's `default:`
  case has no `return`/`break` before falling into `case FL_Right: case
  FL_Down:`. A flattened `if`/`else if` translation missing this
  fallthrough is an easy mistake and silently breaks focus re-derivation any time something calls `takeFocus()` on a
  window/group outside of an actual arrow-key/Tab keystroke — e.g.
  `fl.core.throwFocus()`'s own re-derivation call.
- `array()`/`children()`/`child()`/`find()` are non-virtual in FLTK's own
  header, so FLTK's *internal* code (`draw_children()`, `handle()`,
  `resize()`, ...) always calls the true base implementation regardless of
  a subclass's override. Since D methods are virtual by default, this
  port restores that non-overridable semantics with genuinely
  non-virtual internal variants (`rawArray()`/`rawChildren()`) used by
  every one of `Group`'s own internal call sites. The public overloads
  stay virtual for legitimate external-caller overriding (e.g.
  `fl.table.Table`), matching FLTK's own C++ name-hiding intent.
- **Known, reproducible gap, matching FLTK's own real behavior**
  (reproduces via Fluid's Settings dialog — General tab's "Scheme:"/
  "# Recent Files:" and Shell tab's "Store:"/"Condition:"/"Shell
  script:" labels going permanently blank after another window is
  dragged over then away): `drawChild()`'s
  `notClipped()` guard only tests a would-be-skipped child's *own*
  bounding box against the active clip — for a `Group` child, that
  misses the case where one of *its own* direct children has an
  outside label (`drawOutsideLabel()`) extending past the parent
  `Group`'s own box, exactly the shape `settings_panel.fl`'s real
  FLTK layout uses for several rows (a `Fl_Choice`/`Fl_Spinner`/
  etc. wrapped in an invisible helper `Group` positioned at the *same*
  x as the widget itself, purely so Fluid's live-resize "filler box"
  trick has somewhere to live). A narrow `Expose`-driven repaint whose
  damage rectangle happens to land on just the label (not the widget
  it's attached to) skips the whole wrapper `Group`'s subtree —
  including the label — leaving it stale until the next full repaint.
  This matches real FLTK's own code shape exactly
  (`Fl_Group::draw_child()`'s own `fl_not_clipped()` guard is exactly
  this narrow, unmodified). Special-casing `drawChild()` to also test
  descendants' outside-label extents is not a viable fix on its own: it
  causes a serious repaint-latency regression (multiple seconds of
  visible redraw lag trailing a dragged window) that a caching layer does
  not resolve. A
  real fix needs a real multi-rectangle clip region (matching
  FLTK's actual `Fl_X::region`/`XUnionRectWithRegion()` mechanism,
  a bigger architectural change to `fl.draw`'s clip stack) rather than
  patching `FlGroup.drawChild()` directly.

### `FL/Fl_Window.H`

**Status:** Complete (Linux/X11) — `fl.window`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Window.H),
[src/Fl_Window.cxx](https://github.com/fltk/fltk/blob/master/src/Fl_Window.cxx))

Every X11-side piece is real: `show()`/`hide()`, size-range negotiation,
named and custom-image cursors, fullscreen/maximize (including tracking
externally-triggered changes and multi-monitor targeting), `modal()`
(cooperating with `fl.core.modal()`'s cross-window enforcement), real
subwindows, shape masks (`shape()`), iconize (including "born iconic"),
window icons, decorated size (`decoratedW()`/`decoratedH()`), live
title/label updates on an already-shown window, and real double-buffered
repainting with no corruption (see the note below). `~this()` is real:
ported from `Fl_Window::~Fl_Window()`'s
own body (just `hide();`, before implicitly chaining to `~Fl_Group()`/
`~Fl_Widget()`), guarded by `GC.inFinalizer()` the same way `Widget`/
`Group`'s own destructors already are — needed because `destroy()`ing
(or letting the GC collect) a still-*shown* window without it leaves
its `fl.platform_x11` registry entry dangling, which the next
`flushDamage()` would walk and crash on.

Differences from FLTK:
- The default `WM_CLASS`/xclass sentinel is `"fldtk"`, not FLTK's own
  `"FLTK"` — deliberate, so an fldtk-built app's window doesn't
  misidentify itself as FLTK itself to anything keying off that property.
- `WM_TRANSIENT_FOR`/`XSetTransientForHint()` (in `fl.platform_x11.
  createWindow()`) applies to any `Window.nonModal()` window, not just
  `modal()` ones — `Window.nonModal()` matches FLTK's own combined
  `Fl_Window::non_modal()` semantics (true for either the `MODAL` or
  `NON_MODAL` flag), so a plain non-modal "utility panel" window (like
  Fluid's own Tools window) gets the hint too, matching FLTK's real
  behavior — most window managers style a `WM_TRANSIENT_FOR` window
  without full title-bar decorations.
- `hotspot()` is single-monitor and skips FLTK's decoration-size query
  (`Fl::screen_work_area()`/driver `decoration_sizes()` aren't ported).
- `decoratedW()`/`decoratedH()` divide by `fl.core.screenScale(int)`,
  matching FLTK's own `w = attributes.width / s`.

`resizeAfterScaleChange()` (backing the
Ctrl-+/-/0 live rescale tracked under `FL/Fl.H`'s row) is real: a
faithful port of `Fl_Window_Driver::resize_after_scale_change()`,
including its own shared `is_a_rescale_` flag (`isARescale_` here),
needed because this function routinely computes the *same* FLTK-unit
geometry `resize()` already has (its own FLTK-unit size never changes
just because the scale did) — without the flag forcing `resize()`'s
`isMove`/`isResize` checks true, the real `resizeWindow()` X11 call
that actually updates the window's on-screen pixel size would be
silently skipped.

**Deliberately exceeds FLTK**: FLTK recomputes the window's
position on every rescale as `int(x() * old_f / new_f)` — a lossy
round-trip through an intermediate integer FLTK-unit value — and always
re-sends it via `XMoveResizeWindow()`, even when the window doesn't
need to move at all. Side by side with an unmodified FLTK build on real
multi-monitor hardware, that drifts the window 1px left and/or up on
every single rescale toggle, monotonically (`int()`/`cast(int)`
truncates toward zero, never rounding up) — see `FLTK_ISSUES.md`'s
`resize_after_scale_change()` entry.

This port's own `resizeAfterScaleChange()` sidesteps the round-trip
entirely in the common case (no screen-boundary clamping needed): it
reads the window's exact, *confirmed* device-pixel position —
`Window.devicePosX_`/`devicePosY_`, kept live-updated by
`fl.platform_x11`'s `ConfigureNotify` handler on every real geometry
confirmation (a drag, a WM-driven move, a rescale, anything) — and
tells the platform layer to request *that exact position* explicitly
(`platformX11.resizeWindow()`'s `exactDevX`/`exactDevY` parameters,
bypassing `scaledPos()`'s FLTK-unit conversion for position only) while
only the size changes. Explicitly re-asserting the unchanged position,
rather than omitting it and relying on X11's window-gravity default,
matters in practice: a real window manager isn't obligated to honor an
unspecified position on a plain resize, and at least one resizes about
the window's *centre* instead, pushing a window's title bar out of reach
if it started near a screen edge. Reading the *confirmed* device-pixel
position (rather than reconstructing an approximation of it from
`x()`/`y()` — themselves already-rounded FLTK-unit values from a
*previous* rescale) matters too: reconstructing via `lround(x() * oldF)`
is not guaranteed to invert cleanly (`x()==185` at `oldF==1.7`
reconstructs to `315`, not the `314` that produced it, since `185*1.7`
lands exactly on a rounding boundary), which shows up as a small drift in
an `xwininfo` measurement.

This makes the fix completely independent of monitor topology (single-
or multi-head, it's the same "tell the WM the position hasn't changed"
logic either way) rather than a targeted patch for the multi-monitor
case specifically. Only the rare clamped case (window centre would land
outside its screen) and the fullscreen case (whose FLTK-unit size
genuinely must change) still use the old, approximate, `lround()`-based
conversion, since those really do need to land on a position/size that
doesn't already exist on screen.

`exactDevX`/`exactDevY` are gated by a third static, `exactDeviceTarget_`
(the specific `Window` instance they were computed for) — `Window.resize()`
only forwards them to `platformX11.resizeWindow()` when `this is
exactDeviceTarget_`, passing `int.min` (the normal "compute it yourself"
sentinel) to any other window. This matters because `isARescale_` (see
above) deliberately keeps forcing `isMove`/`isResize` true for the whole
duration of the top-level window's own `resize()` call, including the
recursive `FlGroup.resize()` cascade into every child that call triggers
— reaching a nested subwindow with its own real X11 resource (e.g.
`source/test/CubeViewUI.fl`'s `cube`, a `GlWindow`) exactly as intended.
Without the target check, that subwindow's own `resize()` call would read
the *top-level* window's absolute screen-device position through the same
two static fields and ask the X server to move itself there — an
absolute screen coordinate applied to a window whose real X11 parent is
the top-level window, not the root, landing it at the wrong position
(and sometimes the wrong size) on every rescale.

`forcePosition()`/`forcePosition(bool)` are real: `fl.platform_x11.
sendSizeHints()` consults `Flag.forcePosition` to add `USPosition`
(plus scaled `x`/`y`) to `WM_NORMAL_HINTS`, matching FLTK's own
`sendxjunk()` exactly — used by the Ctrl-+/-/0 scale
indicator to center itself on screen rather than being placed
wherever the window manager chooses.

`shape()`'s mask is real-device-pixel-sized: `applyShapeMaskIfNeeded()`
resizes the `XShapeCombineMask` mask to `w()*scale`/`h()*scale` (an X11
shape mask is inherently device-pixel-sized, unlike FLTK-unit
geometry), with change-detection compared against that scaled size
too, matching FLTK's own `Fl_X11_Window_Driver::combine_mask()`/
`draw_begin()` exactly (`shape_data_->lw_ = w()*s;`, `lw_ != int(s*w())`).
`fl.pixmap.Pixmap`'s own 1-bit clip mask follows the identical
scaling rule — see that row's own writeup.

Missing:
- The Wayland and macOS backends (see the "Platform / windowing headers"
  section above). The Windows twins of this module's platform-specific
  branches live in `fl.window`'s `version (Windows)` code and
  `fl.platform_win32`.
- A `Pixmap`-family shape image with more than one underlying data array
  (`Image.count() >= 2` in FLTK) — this port's `Image` base has no
  generic `count()`/`data()`, a documented `fl.image` simplification with
  no current consumer needing it.

### `FL/Fl_Double_Window.H`

**Status:** Complete — `fl.double_window`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Double_Window.H))

Real double-buffering: an off-screen `Pixmap`, allocated/reallocated
lazily on size change, drawn into and blitted onto the real window each
flush. A plain `Window` is completely unaffected (`type()` check skips
this path entirely).

- The blit decision (whole fresh buffer, unclipped, vs. a specific
  damaged rectangle) is snapshotted into local variables before
  `draw()` runs, matching FLTK's own `flush_double()` — necessary
  because a widget's `draw()` can itself mutate the same live damage-
  region fields `flushDamage()` reads both before *and* after `draw()`
  runs (see `fl.platform_x11`'s note on `flushDamage()`), which would
  otherwise retroactively clobber an already-decided "paint the whole
  fresh buffer" choice back down to a stale rectangle.
- `Fl_Overlay_Window`'s extra overlay-plane machinery is a separate
  subclass (see below), out of scope for this row.

### `FL/Fl_Single_Window.H`

**Status:** Complete — `fl.single_window`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Single_Window.H))

Genuinely trivial here: this port has no double-buffer-by-default
behavior for FLTK's own `show()`/`flush()` overrides to opt out of, so
neither is ported — nothing for them to differentiate.

### `FL/Fl_Overlay_Window.H`

**Status:** Complete — `fl.overlay_window`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Overlay_Window.H))

A `DoubleWindow` subclass adding `drawOverlay()`/`redrawOverlay()`.
`canDoOverlay()` always returns `false` (matching FLTK's own X11 driver —
no hardware overlay plane exists there either), so only the documented
software-simulated path runs: the whole backbuffer is recopied over the
window on every flush while active, then `drawOverlay()` draws straight
onto the window — including FLTK's own "will blink" tradeoff. The
overlay works on Windows too: `fl.platform_win32`'s `WM_PAINT` case
mirrors `fl.platform_x11.flushDamage()`'s identical overlay branch.
`redrawOverlay()` calls the real, invalidating `damage()` setter rather
than the raw, non-invalidating `clearDamage()` setter FLTK's own
`Fl_Window_Driver::redraw_overlay()` uses: FLTK's version is followed by a
global `Fl::damage(FL_DAMAGE_CHILD)` kick this port has no equivalent of,
so without the invalidating setter nothing would guarantee a repaint got
scheduled unless some other same-window widget happened to trigger one.

- `show()`/`hide()`/`resize()`'s cascade-to-a-separate-hardware-overlay-
  window overrides aren't ported — dead code by construction here, since
  `canDoOverlay()` is hardwired false.

### `FL/Fl_Menu_Window.H`

**Status:** Complete — `fl.menu_window`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Menu_Window.H))

Trivial `Fl_Single_Window` subclass — FLTK's only real content here is
opting into hardware overlay planes, which no driver in this port
implements. Used as the concrete window class the popup-menu engine shows
each open cascade level in.

### `FL/Fl_Gl_Window.H`

**Status:** Complete — `fl.gl_window`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Gl_Window.H))

fldtk's first external-library dependency. Real context creation/`makeCurrent()`/buffer
swap; real compositing of ordinary FLTK child widgets over a GL scene,
including real text (texture-rectangle-based); real software-simulated
overlay support; GL1/GL3 context-program switching for `modeOpengl3`;
`gl_start()`/`gl_finish()` for drawing GL directly into an arbitrary,
non-`GlWindow` window (`fl.gl`). A `GlWindow` works as a top-level window,
a subwindow, or nested inside a plain `Window`.

- Text rendering targets `GL_EXT_texture_rectangle`/`GL_ARB_texture_
  rectangle` only — no legacy `glXUseXFont()`-display-list or
  `glutStrokeString()` fallback (a silent no-op on hardware without that
  extension, vanishingly rare in practice).
- Linux/X11 (GLX) and Windows (WGL) — see `CONVENTIONS.md`'s own "Platform
  scope" section for why Wayland (EGL) is a genuinely separate
  undertaking. `GlWindow`/`fl.gl_graphics_driver`/`fl.gl_display_device`/
  `fl.gl` themselves needed zero platform-specific code to support
  Windows too (every platform-specific call already goes through
  `fl.gl_window_driver`, which has the real per-platform split, or
  `Window.xid()`, which already resolves to the right handle type per
  platform) — see `FL/win32.H`'s row for the Windows-specific work that
  *did* need doing.
- Hardware overlay planes are not applicable on either of this port's
  drivers (X11 and Windows both use the software-simulated overlay
  instead), matching FLTK's own X11 driver exactly and its Windows driver
  in the near-universal case of no working overlay-plane hardware.

### `FL/gl.h`

**Status:** Partial — `fl.opengl` (raw GL bindings, Linux and Windows) +
`fl.glx` (raw GLX bindings, Linux only — Windows' WGL equivalent needs no
binding module at all, druntime's `core.sys.windows.wingdi` already has
it) + `fl.gl` (the FLTK wrapper functions this header declares)

Infrastructure, not a literal header port — the same role `fl.xlib` plays
for Xlib. `fl.opengl`'s own declarations use `extern (System)`
(`__stdcall` on Windows, matching real `GL/gl.h`'s own `WINGDIAPI ...
APIENTRY`; plain C everywhere else) rather than `extern (C)`, so the
same declarations serve both platforms with no `version` branching
needed. `fl.gl` ports FLTK's own `gl_color()`/`gl_rect()`/`gl_font()`/
`gl_draw()` (7 overloads) et al. for real, backed by a bounded-FIFO
texture cache (matching FLTK's own `gl_texture_fifo`, not an unbounded
cache) rather than leaking GPU memory for one-off strings.

The text-texture path (`drawStringWithTexture()`/`computeTexture()`/
`alphaMaskForString()`) reads the real per-screen scale
(`fl.core.screenScale(win.screenNum())`, matching
`GlWindow.pixelsPerUnit()`'s own call) rather than a hardcoded `1.0`.
`computeTexture()` measures the glyph string at its plain, unscaled
`size` (this port's `fl_font()` already opens the font at `size *
currentScale()` device pixels internally, so pre-multiplying by `scale`
again here would double-scale it) and sizes the offscreen texture from
`fldraw.width(str)`/`height()` scaled explicitly back up to real device
pixels (those two, like `fl_font()`, divide their own result back down
to logical/FLTK-unit units internally).

`alphaMaskForString()` itself renders entirely in device pixels: it
forces `currentScale()` to `1` for the duration of its own offscreen
`ImageSurface` render (restored after, the same technique
`fl.core.transientScaleDisplay()` uses for this identical class of
bug), receives an already-device-pixel font size from its caller, and
fills/draws using the surface's own real `w`/`h` directly — this
guarantees the black background fill covers the *entire* real surface,
by construction. Filling/drawing at logical coordinates instead would
rely on `fl_rectf()`/`fl_draw()`'s internal `scaledFloor()` rescaling
landing on the same `w`/`h` the caller separately computed via
ceiling/rounding; the two roundings rarely agree exactly, leaving a
never-filled strip of raw offscreen-pixmap memory along the bottom/right
edges, whose nonzero green-channel garbage gets misread as opaque alpha
and shows up as a stray ghost line/tick around every GL-rendered label.

`gl_start()`/`gl_finish()` (`Fl::gl_visual()`, ported as `glVisual()` to
keep `fl.core` GL-free) live here too — see `FL/Fl_Gl_Window.H`'s row.
The modern core-profile GL API needs no binding here: it needs runtime
`glXGetProcAddress` loading, and FLTK's own GL usage in this header never
reaches past OpenGL 1.x either (`GL/glew.h`, above, covers this port's
own GL3 sample support instead, a separate concern from this header).

### `FL/glu.h`

**Status:** Not applicable — n/a

Nothing in FLTK's own GL usage calls a GLU function — this header is a
pure convenience pass-through to the system header for *application*
code. (Contrast with `GL/glu.h` under "Core / support" above, which this
port *does* bind, for the samples that need it directly.)

### `src/Fl_Gl_Choice.H`

**Status:** Complete — `fl.gl_choice`

FLTK's `Fl_Gl_Choice` and its X11 subclass merged into one concrete
`GlChoice` class — this port's usual "one platform driver, nothing to
abstract over" rule.

### `src/Fl_Gl_Window_Driver.H`

**Status:** Complete — `fl.gl_window_driver`

FLTK's `Fl_Gl_Window_Driver` and its X11 subclass merged into one module
of free functions, same rule as `fl.gl_choice`. Visual selection, context
creation, buffer swap (including the real swap-interval extension dance),
and `modeOpengl3`'s GL1/GL3 shader-program switching are all real.

## Buttons



### `FL/Fl_Button.H`

**Status:** Complete — `fl.button`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Button.H))

`value()`/`setonly()`/`shortcut()`/`downBox()`/`compact()`, real `draw()`
(including `contrast()`-based label recoloring when pressed, and
`compact()`'s parent-spanning box clipped back to the button's own area),
and a real timed "flash back to off" revert for keyboard-triggered
activation (`simulateKeyAction()`).

- `Button.~this()` cancels its own pending revert timer on destruction,
  needed because a keyboard-triggered button destroyed before its
  0.15s timer fires (e.g. `ReturnButton` closing its own dialog on
  Enter) would otherwise leave a dangling timer callback. FLTK avoids
  this via a `Fl_Widget_Tracker` null-check inside a *free* timeout
  function; this port's timeout is a bound instance-method delegate,
  which can't null-check itself the same way, so cancelling the timer
  outright at destruction time is the equivalent here.

### `FL/Fl_Light_Button.H`

**Status:** Complete — `fl.light_button`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Light_Button.H))

Every branch of `draw()`/`handle()` ported, including the "gtk+"/"plastic"
scheme-specific checkbox/radio glyph variants.

### `FL/Fl_Check_Button.H`

**Status:** Complete — `fl.check_button`

Trivial subclass of `fl.light_button`.

### `FL/Fl_Radio_Button.H`

**Status:** Complete — `fl.radio_button`

Trivial `type(radioButton)` subclass of `fl.button`.

### `FL/Fl_Radio_Light_Button.H`

**Status:** Complete — `fl.radio_light_button`

Trivial `type(radioButton)` subclass of `fl.light_button`.

### `FL/Fl_Radio_Round_Button.H`

**Status:** Complete — `fl.radio_round_button`

Trivial `type(radioButton)` subclass of `fl.round_button`.

### `FL/Fl_Repeat_Button.H`

**Status:** Complete — `fl.repeat_button`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Repeat_Button.H))

Faithful, complete port of `handle()`/`repeat_callback()`/`deactivate()`.

- FLTK's `handle()` uses `goto` to jump into the middle of another
  `case`'s body — not expressible in D, so the shared tail logic is
  factored into an unconditional post-`switch` call instead. Same control
  flow, no `goto`.

### `FL/Fl_Return_Button.H`

**Status:** Complete — `fl.return_button`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Return_Button.H))

Faithful, complete port including `fl_return_arrow()` (the carriage-return
glyph).

### `FL/Fl_Round_Button.H`

**Status:** Complete — `fl.round_button`

Trivial subclass of `fl.light_button`.

### `FL/Fl_Shortcut_Button.H`

**Status:** Complete — `fl.shortcut_button`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Shortcut_Button.H))

Faithful port of every live code path.

- `value()`/`value(Fl_Shortcut)` are named `shortcutValue()`/
  `shortcutValue(uint)` here — D hides every base-class overload of a name
  once a subclass declares its own same-signature, different-return-type
  method of that name (unlike C++, which only hides same-signature
  members); there's no D overload that can coexist with `Button.value()`,
  so the name had to change.
- Two pieces are skipped, both because they're dead/disabled *in FLTK
  itself*, not a cut this port made: the whole "default shortcut" reverse
  button (`#if 0`-disabled in FLTK, "until successful review of the UI"),
  and a macOS-only Alt-key accommodation that can never trigger on X11.

### `FL/Fl_Toggle_Button.H`

**Status:** Complete — `fl.toggle_button`

Trivial `type(toggleButton)` subclass of `fl.button`.

### `FL/Fl_Toggle_Light_Button.H`

**Status:** Complete — `fl.toggle_light_button`

FLTK itself is a back-compat `#define` alias for `Fl_Light_Button`, not a
real class — ported as a D `alias ToggleLightButton = LightButton`.

### `FL/Fl_Toggle_Round_Button.H`

**Status:** Complete — `fl.toggle_round_button`

Same story: `alias ToggleRoundButton = RoundButton`.

## Menus

### `FL/Fl_Menu.H`

**Status:** Complete — n/a

FLTK's own file is a pure back-compat forwarding header for code that
only knew about the pre-split "Fl_Menu" name. D's module system has no
equivalent legacy-header need — `fl.menu_item.MenuItem` is the direct
equivalent.

### `FL/Fl_Menu_.H`

**Status:** Complete — `fl.menu_`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Menu_.H))

`Menu_`, the base class of every menu-owning widget (`draw()`/`handle()`
stay abstract, matching FLTK — neither is defined on `Fl_Menu_` itself
either).

Differences from FLTK:
- **The menu array is a genuine GC-backed `MenuItem[]`**, not a raw
  `Fl_Menu_Item*` — FLTK's entire `alloc`-flag/manual-`free()`/singleton-
  ownership bookkeeping around the array doesn't exist at all;
  `add()`/`insert()`/`remove()`/`replace()`/`clear()`/`copy()` mutate or
  replace the array directly. This is why this ported at a fraction of
  FLTK's combined `Fl_Menu_.cxx` + `Fl_Menu_add.cxx` size.
- `add()`/`insert()`'s "split label at `/` into automatic submenus"
  feature is ported; its legacy Forms-era escape hatches (leading
  `_`-divider shorthand, leading-`/`-means-literal-filename) aren't —
  FLTK's own header comment calls that whole variant "actually a totally
  unnecessary feature."
- `find_item_with_user_data()`/`find_item_with_argument()` aren't ported
  — no `user_data()` concept exists in this port at all (see
  `fl.menu_item`'s row).
- `global()` is real — a single process-wide global menu, matching FLTK's
  own documented one-at-a-time limitation.

### `FL/Fl_Menu_Item.H`

**Status:** Complete — `fl.menu_item`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Menu_Item.H))

The flat-array `MenuItem` struct: array walking (`next()`/`first()`/
`size()`), every flag-bit accessor, label/shortcut handling, `measure()`/
`draw()` (real pixels — text, checkbox/radio glyphs, background/
selection, including per-scheme color variants), and images. `draw()`'s
non-title selection box applies `fl.core.menuLinespacing()`'s vertical
adjustment (`y-(linespacing-2)/2`, `h+(linespacing-2)`) exactly like
FLTK's `fl_draw_box()` call.

Differences from FLTK:
- `callback_` is a D delegate with no `user_data()` slot; a dedicated
  `submenuItems_` field replaces `FL_SUBMENU_POINTER`'s reuse of that slot
  for tree structure.
- `measure()`/`draw()` take a new `MenuStyle` struct (font/size/color/
  selection-color/down-box) instead of a `const Fl_Menu_*` — arguably a
  *closer* match to FLTK's own "works standalone, no owning widget" spirit
  for `popup()`/`pulldown()` than a forward reference to `Fl_Menu_` would
  be.
- `add()`/`insert()` aren't ported onto `MenuItem` itself — FLTK's own
  source comment calls the bare-array versions "quite depreciated,"
  ported instead on `fl.menu_.Menu_`, a much better fit for a GC-backed
  dynamic array than hand-managed pointer/realloc bookkeeping.
- `image_label()`/`_FL_IMAGE_LABEL` pointer-punning isn't ported — a real
  typed `image()` field already covers it. Getting the same pixels for an
  image-only item (no visible label text) depends on `measure()`/`draw()`
  passing `null`, not `""`, into the `Label` they build whenever `text` is
  empty — `text` itself must stay non-null (it's the flat array's own
  end-of-(sub)menu sentinel), but a genuinely non-null `""` would make
  `fl.draw`'s `fl_draw()` reserve a real text line above the image (FLTK's
  own `if (str) {...}` line-counting, correct for a real non-null-empty
  label but not what an image-only item means here). Without the `null`
  substitution each image-only item (see `examples/howto-menu-with-images`)
  draws shifted up by about half an item's height.
- Several convenience constructor overloads exist that FLTK doesn't need
  (C++ call sites can skip trailing default parameters in ways D's
  overload resolution can't match with one signature).
- Array walking uses unchecked pointer arithmetic on purpose, matching
  FLTK's own raw-pointer walk (the flat embedded-submenu array format is
  inherent to FLTK's menu-array API) — but a separate, bounds-checked
  `validateMenuArray()` (over a real D slice) validates any array handed
  to a `Menu_`-owning widget before it's ever converted to that raw
  pointer, throwing a clear exception on a malformed array instead of
  reading past its end (guards against, e.g., a missing sentinel in a
  caller's own array literal). This validation
  doesn't cover a bare array handed directly to `fl.menu_popup.pulldown()`/
  `popup()` without going through a `Menu_`-owning widget — matching
  FLTK's own identical "no length, no validation possible" limitation
  there.

### `fl.menu_popup` *(new infrastructure — no direct FLTK header, built to
back `Fl_Menu_Item::popup()`/`pulldown()`)*

**Status:** Partial — `fl.menu_popup`

A real, cascading, keyboard-and-mouse-navigable popup-menu engine, built
on substantially less platform machinery than FLTK's own file-static
`Menu_State`/`Menu_Window`/`Menu_Title_Window` machinery
(`src/Fl_Menu.cxx`). Each open cascade level is a real, override-redirect
`fl.menu_window.MenuWindow`. Covers: click, press-drag-release, and
click-click gestures (all through one hover/release mechanism, not
FLTK's separate `PUSHED`/`MENU_PUSHED` states); outside-click
cancellation via real geometric hit-testing (not the `pushed()`-polling
approach, which doesn't work under a real `XGrabPointer`); full
keyboard navigation (arrows, mnemonic/shortcut-key matching while open,
Left/Right switching between top-level sibling menus); autoscroll for an
oversized menu (keyboard- and mouse-hover-triggered); shortcut-key text
and cascade-arrow rendering; the `popup()` title window; and multi-
monitor-aware positioning (stable per-level home-monitor tracking, to
avoid a scroll-triggered monitor-boundary miscalculation).

- A cross-widget reentrancy mechanism (`activeEngine_`/`forceClose()`)
  handles same-app sibling clicks dispatching synchronously into a
  second, nested popup call before the first one's suspended loop can
  react (a consequence of a real X grab) — see the module's own doc
  comment and `fl.menu_bar`'s row.

- `Event.release` finalizes using the last-highlighted item rather than
  re-hit-testing the release position — a design choice of this port's
  `levelAtRoot()`-based dispatch, not a gap.
- A `Fl_Widget_Tracker`-style "menu owner deleted mid-loop" guard exists for
  every caller (`MenuButton`/`Choice`/`InputChoice`/`MenuBar`).

Missing:
- Tear-off/draggable title windows (`fl.menu_bar.MenuBar` already covers
  the same visual effect its own way — no caller needs this mode).

### `FL/Fl_Menu_Bar.H`

**Status:** Complete — `fl.menu_bar`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Menu_Bar.H))

`draw()`/`handle()` ported, plus real blue highlight-while-open,
hover-driven auto-switch between top-level items, and Left/Right
keyboard navigation between them.

Differences from FLTK:
- **Structural**: FLTK hands its entire menu array to one
  `pulldown(..., menubar=1)` call and lets the deep engine lay out level 0
  horizontally itself. `fl.menu_popup`'s engine only ever renders vertical
  lists, so `MenuBar` draws and hit-tests its own horizontal top-level row
  directly and only calls into `fl.menu_popup.pulldown()` for the vertical
  dropdown of whichever top-level item was clicked — observably the same
  behavior, restructured around this port's popup-engine scope boundary.
- The highlight-while-open and hover-auto-switch tracking fields have no
  FLTK equivalent to port 1:1 for the same structural reason — FLTK's own
  shared, deep engine handles that uniformly across every level, since
  level 0 *is* a level to it.
- For the same reason, a plain (non-submenu) top-level item is tracked by
  `MenuBar` itself: pressed while the mouse button is held over it,
  dragged on to whichever bar item is under the mouse (none off the bar,
  a submenu title opening its menu), and picked on release — the
  menubar-button case of `Menu_State::handle_mouse_events()`. A push with
  no mouse button down (a synthesized event) picks the item at once.

### `FL/Fl_Menu_Button.H`

**Status:** Complete — `fl.menu_button`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Menu_Button.H))

Faithful port of `draw()`/`popup()`/`handle()`.

- `popup()` converts to screen-absolute coordinates via
  `Widget.topWindowOffset()` instead of FLTK's internal window-chain walk.
  `Fl_Window_Driver::current_menu_button` (driver-internal plumbing for a
  driver hierarchy this port doesn't have) isn't ported.

### `FL/Fl_Choice.H`

**Status:** Complete — `fl.choice`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Choice.H))

Faithful port of `draw()`/`handle()`/`value()`, including every
scheme-gated drawing branch (gtk+/gleam/oxy each draw their own divider
style, matching FLTK's own per-scheme asymmetry, including one branch
FLTK's own source comments as "weird (why?)" and ported as-is).

- One minor, accepted simplification: the closed choice's current-value
  text always goes through the same `MenuItem.draw()` call FLTK uses for
  scheme mode, rather than FLTK's separate raw-`Fl_Label` path for the
  no-scheme case — in practice only a skipped checkbox/radio glyph (rare
  for a plain `Choice` item) and a few pixels of inset differ.

### `FL/Fl_Input_Choice.H`

**Status:** Complete — `fl.input_choice`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Input_Choice.H))

Faithful port of the composite `Input` + private `InputMenuButton`
widget, including the combined-widget `changed()` bookkeeping subtlety
(qualified calls that avoid also touching the input field's own changed
flag, preserved exactly).

- `InputMenuButton.handle()` doesn't need to be re-declared at all, unlike
  FLTK, which duplicates the entire `Fl_Menu_Button::handle()` body into
  it purely because `Fl_Menu_Button::popup()` isn't `virtual` in C++ (so
  `handle()`'s internal call wouldn't dispatch to an override without also
  overriding `handle()` itself). D methods are virtual by default, so the
  inherited `handle()`'s call to `popup()` already reaches the override
  correctly — a simplification D's semantics give for free, not a cut
  corner.
- `add(string)` doesn't split on `|` — that Forms-compatible variant isn't
  ported onto `fl.menu_` at all (see that row).

## Text input

### `FL/Fl_Input_.H`

**Status:** Complete — `fl.input_`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Input_.H))

The whole editing/undo/selection/scrolling engine: `expand()`, word/line
navigation, real-pixel `drawtext()`, mouse-position mapping, `replace()`/
`undo()`/`redo()`/`copy()`, IME composition (real text composition; the marked-text underline is
never drawn, since `Fl::compose_state` never becomes non-zero on X11, as
in FLTK), and real X11 clipboard-backed `copy()`/`paste()`.

Differences from FLTK:
- **`value_` is a plain D `string`**, not a manually-grown `char*`
  buffer — since a D `string` is already immutable/GC-owned, the whole
  "copy into an owned buffer" subsystem (and the parallel malloc'd undo
  buffer/hand-grown undo-action list) collapses to plain slicing/
  concatenation and an array-backed undo stack. `size()` is just
  `value_.length`.
- UTF-8 helpers are imported from `fl.text_buffer` (public API) rather
  than re-ported a second time.
- `fl_utf8_next_composed_char()`/`_previous_composed_char()` (emoji/ZWJ/
  regional-indicator-flag sequence awareness) reduce to single-codepoint
  advance/retreat.
- `isword()` faithfully preserves an FLTK quirk: it truncates a full
  Unicode codepoint to 8 bits before testing (an implicit C++ narrowing
  cast), ported as-is rather than corrected.
- Genuinely process-wide FLTK statics (`up_down_pos`/`was_up_down`/
  `l_secret`) become module-level D globals, matching the precedent
  already established for `fl.slider`'s `offcenter`/`fl.roller`'s `ipos`.

### `FL/Fl_Input.H`

**Status:** Complete — `fl.input`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Input.H))

Every `kf_*()` keybinding method, `handle_key()` including FLTK's
`Fl_Screen_Driver::input_widget_handle_key()` hook (inlined directly
rather than via a driver hierarchy this port doesn't have — this is
where Delete/Home/End/Page Up/Down/Ctrl+word-navigation actually live on
X11, since only the Cocoa driver overrides it in FLTK; X11 uses the base
implementation), real drag-and-drop (matching `fl.text_display`/
`fl.text_editor`'s XDND handling), and a full right-click Cut/Copy/Paste
popup (`handle_rmb()`, built on `fl.menu_item`/`fl.menu_popup`).

Differences from FLTK:
- The right-click popup's position always comes from a fresh mouse-position
  query rather than FLTK's own event-position-relative-to-window
  computation — deliberate: the computed approach proved fragile for at
  least one real widget shape in this port (`fl.value_input.ValueInput`'s
  embedded `Input`, whose coordinates aren't parent-relative in the usual
  sense), and a direct query is robust regardless of widget-tree shape.
- The picked popup action is recovered via array-index arithmetic instead
  of `Fl_Menu_Item::argument()` — this port's `MenuItem` has no
  `user_data()`/`argument()` slot.
- `legal_fp_chars` is the fixed `".eE+-"` fallback, not FLTK's
  locale-derived character list — no locale infrastructure in this port.

### `FL/Fl_Float_Input.H`

**Status:** Complete — `fl.float_input`

Trivial `type(inputFloat)` subclass.

### `FL/Fl_Int_Input.H`

**Status:** Complete — `fl.int_input`

Trivial `type(inputInt)` subclass.

### `FL/Fl_Multiline_Input.H`

**Status:** Complete — `fl.multiline_input`

Trivial `type(inputMultiline)` subclass.

### `FL/Fl_Multiline_Output.H`

**Status:** Complete — `fl.multiline_output`

Trivial `type(outputMultiline)` subclass of `fl.output`.

### `FL/Fl_Output.H`

**Status:** Complete — `fl.output`

Trivial `type(outputNormal)` subclass.

### `FL/Fl_Secret_Input.H`

**Status:** Complete — `fl.secret_input`

Trivial `type(inputSecret)` subclass.

- FLTK's own `handle()` override (suppressing the IME marked-text
  underline) isn't ported: the underline is never drawn on X11, so there
  is nothing to suppress.

### `FL/Fl_File_Input.H`

**Status:** Complete — `fl.file_input`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_File_Input.H))

Faithful port of the breadcrumb navigation bar (path-component
click-to-truncate).

- `ok_entry_` isn't ported — FLTK sets it and never reads it again
  anywhere, a genuinely dead field.
- `Fl::system_driver()->next_dir_sep()` (a platform hook, `strchr(start,
  '/')` on Linux, falling back to `strchr(start,'\\')` on Windows) is a
  plain function with a `version (Windows)` branch, not a driver
  abstraction.
- Dragging across the breadcrumb buttons redraws on the next repaint
  cycle instead of synchronously mid-drag — a one-frame lag, not a
  correctness difference.

### `FL/Fl_Spinner.H`

**Status:** Complete — `fl.spinner`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Spinner.H))

Faithful port, using real arrow-drawing and real `RepeatButton` up/down
buttons — holding one down repeats continuously, matching FLTK.

## Text display / editor

### `FL/Fl_Text_Buffer.H`

**Status:** Complete — `fl.text_buffer`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Text_Buffer.H),
[src/Fl_Text_Buffer.cxx](https://github.com/fltk/fltk/blob/master/src/Fl_Text_Buffer.cxx))

The gap-buffer data model, faithfully ported with no widget/GUI/drawing
dependency: insert/remove/replace/copy, gap-buffer mechanics, all three
selections (primary/secondary/highlight), undo/redo, modify/predelete
callbacks (as D delegate arrays), line/word navigation, forward/backward
search, and bulk file I/O (including the same CP1252/ISO-8859-1
transcoding fallback for non-UTF-8 input FLTK itself has).

Differences from FLTK:
- `Fl_Text_Selection` becomes a D `struct` (`TextSelection`), not a
  `class` — FLTK copies it by value everywhere, so a struct gives that for
  free.
- Emoji/composed-character clustering (`nextChar()`/`prevChar()` stepping
  over a whole grapheme — regional-indicator flags, ZWJ-joined sequences,
  skin-tone modifiers, keycaps, subdivision-flag tags) is a faithful port
  of FLTK's own `fl_utf8_next_composed_char()`/`_previous_composed_char()`,
  not a widened general Unicode grapheme-cluster algorithm — deliberately
  matches FLTK's actual (narrower) behavior rather than "improving" on it.
- Case-insensitive search uses `std.uni.toLower()` on the decoded
  codepoint instead of FLTK's own hand-rolled, admittedly "naive... 0x0-
  0xffff"-only Unicode case table — broader coverage as a side effect.
- `printf()` accepts `std.format`'s format-string syntax under the same
  method name, not C `printf`'s — a real, deliberate behavior difference,
  though every real call site in this project's own tree uses only plain
  `%s`-style substitution, which both syntaxes handle identically.
  `vprintf()` (the separate `va_list`-taking overload) isn't ported.
- `text_str()` (FLTK's `std::string`-returning twin of `text()`, existing
  purely for C++ callers to pick malloc'd-`char*` vs. `std::string`)
  collapses into the single `text()`, which already returns a GC-owned
  `string`.
- `canUndo(bool)`'s setter has no default-argument overload the way
  FLTK's `can_undo(char flag=1)` does — a default there would collide with
  the 0-arg getter's own overload once both camelCase to the same name.

### `FL/Fl_Text_Display.H`

**Status:** Complete — `fl.text_display`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Text_Display.H),
[src/Fl_Text_Display.cxx](https://github.com/fltk/fltk/blob/master/src/Fl_Text_Display.cxx))

The widget that visually displays a `TextBuffer`: line-start/line-end/
word-wrap calculation, scrolling, cursor positioning/blinking, selection
highlighting, a style buffer for syntax highlighting, mouse/keyboard text
navigation, position↔(row,col)↔(x,y) conversions, real underline/
strikethrough attribute rendering, real X11 clipboard support (including
DND-initiated copies), a right-click Cut/Copy/Paste popup, and real
"preedit at cursor spot" IME positioning (`fl_set_spot()` negotiates real
`XIMPreeditPosition` with the input method). This is the largest single
module in this port (FLTK's own `.cxx` alone is 4481 lines).

Differences from FLTK:
- `scrollDirection_`/`scrollAmount_`/`scrollX_`/`scrollY_` (the
  auto-scroll-while-dragging state) are per-instance fields here, not
  FLTK's shared file-scope statics — FLTK's sharing has a real
  bug (destroying one `Fl_Text_Display` while a *different* one is
  mid-drag-scroll corrupts the in-progress scroll, see
  `FLTK_ISSUES.md`), fixed here rather than faithfully reproduced,
  since FLTK's own single-active-drag assumption holds either way — the
  fix costs nothing.
- The right-click popup's action is recovered via array-index arithmetic,
  not `Fl_Menu_Item::argument()` (no `user_data()` slot in this port's
  `MenuItem`); its position comes from a fresh mouse-position query, same
  deliberate deviation as `fl.input`'s own popup (see that row).
- `fl_set_spot()` never negotiates the separate `XIMStatusArea` style — no
  widget-level concept of positioning a status/candidate-list area exists.
- `highlight_data()`'s `nStyles`/`cbArg` parameters are dropped —
  `nStyles` is redundant with a D slice's own `.length`; `cbArg` is
  dropped per this port's delegate-over-`void*` convention.
- One FLTK bug is faithfully reproduced, not fixed: `wrapped_line_
  counter()`'s end-of-buffer path passes a *line count* to a function
  expecting a *buffer byte position* — see `FLTK_ISSUES.md`.

### `FL/Fl_Text_Editor.H`

**Status:** Complete — `fl.text_editor`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Text_Editor.H),
[src/Fl_Text_Editor.cxx](https://github.com/fltk/fltk/blob/master/src/Fl_Text_Editor.cxx))

Adds editing on top of `fl.text_display`: a per-instance and process-wide
key/modifier-state → handler-function key-binding dispatcher, all ~25
default `kf_*` handlers, `handle()` (mouse/keyboard/focus/shortcut/DND
dispatch, including real drag-and-drop), `tab_nav()`, and custom key
binding registration.

Differences from FLTK:
- `Key_Func` stays a plain D function pointer, not a delegate — there's no
  `void*` user-data slot to eliminate in the first place, so this port's
  usual delegate substitution doesn't apply.
- `Fl::screen_driver()->text_editor_extra_key_bindings` (platform-specific
  extra default bindings, e.g. macOS's Cmd-based set) isn't ported — but
  this isn't actually a gap for X11: FLTK's own base driver default is
  `NULL` too, only Cocoa/WinAPI set a real table.

### `FL/Fl_Terminal.H`

**Status:** Partial — `fl.terminal`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Terminal.H))

A ~5400-line VT100/ANSI/xterm-style terminal output widget: a ring buffer
of Unicode display cells (scrollback + active display), mouse text
selection, and full escape-sequence-driven colors/attributes/cursor
control (CSI dispatch, SGR — 8-color xterm palette, 24-bit RGB, bold/dim/
italic/underline/inverse/strikeout), plus autoscroll while dragging a
selection past the visible edge.

Differences from FLTK:
- No `const` overload pair on drawing/ring-buffer-reading methods — D's
  stricter const propagation (no `const_cast`) isn't worth fighting for a
  case nothing in this port calls through a `const Terminal` reference
  anyway.
- `tabstops_` is a growable `bool[]`, not a manually-resized buffer.
- `Utf8Char`/`CharStyle` are plain D `struct`s, not heap-allocated
  classes — D's default memberwise copy already does what FLTK's
  hand-written copy-ctor/`operator=` exist to manage.
- `printf()` uses `std.format` instead of a fixed 1024-byte `vsnprintf()`
  buffer — FLTK's own doc comment already flags that cap as a real
  limitation; this port has no length cap.
- `EscapeSeq` accumulates each CSI parameter directly as an `int` rather
  than into a text buffer parsed later with `sscanf()` — observably
  identical for every real escape sequence, same DoS-prevention value
  clamp applied per-digit instead of once at finalize time.
- One real FLTK bug is fixed here, not faithfully reproduced: the
  explicit-rows/cols/history constructor's `init_()` hardcoded a history
  size, silently discarding the caller's own `hist` argument — see
  `FLTK_ISSUES.md`.

Missing:
- A `Terminal` constructed before any window is shown gets a placeholder
  font-metrics fallback that never recomputes once a real display opens
  (fewer visible rows than FLTK shows in the same scenario) — a known,
  narrow timing gap, left as-is deliberately to avoid a project-wide
  change to `fl.draw`'s font-opening behavior (which is relied on to stay
  headless-safe for `dub test`).

## Valuators

### `FL/Fl_Valuator.H`

**Status:** Complete — `fl.valuator`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Valuator.H))

Pure numeric bookkeeping (range/step/value/rounding/clamping), no drawing
of its own. `format(char*)`/`format_str()` collapse into a single
`format()` returning a D `string`.

### `FL/Fl_Adjuster.H`

**Status:** Complete — `fl.adjuster`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Adjuster.H))

Full 3-button drag/click/keyboard step math, real box/focus drawing, and
the three directional-arrow glyphs (transcribed verbatim from FLTK's own
16×16 XBM bit patterns).

### `FL/Fl_Counter.H`

**Status:** Complete — `fl.counter`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Counter.H))

Faithful, complete port including real increment/decrement arrow glyphs
and auto-repeat-while-held.

- A genuine D-vs-C++ language corner: FLTK's `Fl_Counter::step(double,
  double)` overload set silently hides `Fl_Valuator::step(double,int)` in
  C++ with no `using` needed; D requires an explicit `alias` to re-expose
  the base overloads, which then makes D's overload resolution route a
  plain 2-argument call to the wrong (aliased-in base) overload. Fixed
  with same-signature shadow overloads on `Counter` that force every
  2-arg call back through `Counter`'s own meaning, and explicit `super.`
  calls (not casts, which still dispatch virtually to the shadow) where
  the true base form is needed.
- One documented, harmless deviation: dragging outside all four arrow
  zones clamps an internal index to 0 here, where FLTK's `(uchar)i` wraps
  `-1` to `255` — both behave identically for the highlight-drawing check;
  FLTK's wraparound reads as an intentional sentinel, not a bug, so this
  wasn't filed as an FLTK issue, just documented as a deviation.

### `FL/Fl_Simple_Counter.H`

**Status:** Complete — `fl.simple_counter`

Trivial `type(simpleCounter)` subclass of `fl.counter`.

### `FL/Fl_Dial.H`

**Status:** Complete — `fl.dial`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Dial.H))

Faithful, complete port, including the `protected` `draw(int,int,int,
int)`/`handle(int,int,int,int,int)` overloads FLTK exposes for
subclasses. Draws real pixels for every `type()` via `fl.draw`'s
transform-stack + vertex-path drawing API.

### `FL/Fl_Fill_Dial.H`

**Status:** Complete — `fl.fill_dial`

Trivial `type(fillDial)` subclass of `fl.dial`.

### `FL/Fl_Line_Dial.H`

**Status:** Complete — `fl.line_dial`

Trivial `type(lineDial)` subclass of `fl.dial`.

### `FL/Fl_Roller.H`

**Status:** Complete — `fl.roller`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Roller.H))

`handle()`'s drag/wheel/keyboard math faithfully ported, including a
genuinely process-wide FLTK function-local static (`ipos`), same category
as `fl.slider`'s `offcenter`. Draws real pixels.

### `FL/Fl_Clock.H`

**Status:** Complete — `fl.clock`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Clock.H))

**Ported as `FlClock`, not `Clock`** — same deliberate exception as
`fl.group`'s `Group` -> `FlGroup` (see that row): a bare `Clock` collides
with `std.datetime.systime.Clock` in generated code's own wildcard
`import std;`. `fl.clock`'s own doc comment has the full reasoning.

`ClockOutput` (numeric/event logic) and `FlClock` (self-rescheduling
1-second tick, started/stopped on show/hide) both faithfully ported, with
real hand/tick-mark drawing via the transform-stack API.

- `tick()` uses `std.datetime.systime.Clock.currTime()` for wall-clock
  time rather than transliterating FLTK's `gettime()`, and deliberately
  reschedules with a plain one-shot timeout (not the drift-corrected
  repeating one) since each call recomputes its delay fresh from the
  actual microsecond offset to land close to the real next second
  boundary — there's no "previous due time" to drift-correct from.
- `value(ulong)`'s epoch-to-local-time conversion uses `std.datetime.
  SysTime` rather than transliterating `localtime()` — that C function's
  returned struct points into non-reentrant static storage, a real hazard
  `SysTime` doesn't have.

### `FL/Fl_Round_Clock.H`

**Status:** Complete — `fl.round_clock`

Trivial `type(roundClock)`/`box(noBox)` subclass of `fl.clock`.

### `FL/Fl_Slider.H`

**Status:** Complete — `fl.slider`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Slider.H))

`handle()`'s drag/keyboard math (linear + logarithmic scale,
`scrollvalue()`) faithfully ported, including a genuinely process-wide
FLTK function-local static (`offcenter`). Draws real pixels.
`drawSlider()`/`handleAt()`/`drawTicks()` are `protected`, matching FLTK
— needed by `fl.value_slider`.

### `FL/Fl_Nice_Slider.H`

**Status:** Complete — `fl.nice_slider`

Trivial `type(vertNiceSlider)`/`box(flatBox)` subclass of `fl.slider`.

### `FL/Fl_Fill_Slider.H`

**Status:** Complete — `fl.fill_slider`

Trivial `type(vertFillSlider)` subclass of `fl.slider`.

### `FL/Fl_Hor_Slider.H`

**Status:** Complete — `fl.hor_slider`

Trivial `type(horSlider)` subclass of `fl.slider`.

### `FL/Fl_Hor_Fill_Slider.H`

**Status:** Complete — `fl.hor_fill_slider`

Trivial `type(horFillSlider)` subclass of `fl.slider`.

### `FL/Fl_Hor_Nice_Slider.H`

**Status:** Complete — `fl.hor_nice_slider`

Trivial `type(horNiceSlider)`/`box(flatBox)` subclass of `fl.slider`.

### `FL/Fl_Hor_Value_Slider.H`

**Status:** Complete — `fl.hor_value_slider`

Trivial `type(horSlider)` subclass of `fl.value_slider`.

### `FL/Fl_Value_Slider.H`

**Status:** Complete — `fl.value_slider`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Value_Slider.H))

Faithful, complete port of the numeric/layout logic; real text readout.

### `FL/Fl_Value_Output.H`

**Status:** Complete — `fl.value_output`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Value_Output.H))

Faithful, complete port (drag math scaled 1×/10×/100× by which mouse
button is held); real text readout.

### `FL/Fl_Value_Input.H`

**Status:** Complete — `fl.value_input`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Value_Input.H))

Faithful, complete port: drag math, an embedded real `Input` kept in sync
with `value()` in both directions.

- The embedded `Input`'s parent is a real `this` (`input_.parent(this)`),
  made possible by `Widget.parent_` being typed as plain `Widget`, not `Group`
  (see `CONVENTIONS.md`'s porting conventions) — FLTK itself
  needs an unsafe cast here (`Fl_Value_Input` extends `Fl_Valuator`, not
  `Fl_Group`, yet embeds a real `Fl_Input` child; FLTK's own source
  comment calls this "a kludge"), which D's type system correctly
  refuses. With a real parent, `contains()`/`damage()`/`window()`/focus
  ancestor-walks all work for the embedded input for free.
- `handle()`'s value-adjustment gesture is exactly FLTK's own: a left/
  middle/right-button horizontal pixel drag (1x/10x/100x `step()` per
  pixel), with no mouse-wheel handling (FLTK has none either, unlike
  `Counter`/`Roller`/`Scrollbar`). A wheel-adjusts-the-value binding is
  planned as a beyond-FLTK addition, for `ValueInput` and likewise
  `Slider`/`ValueSlider`/`Adjuster`/`Dial`; `fluid.formula_input.
  FormulaInput` already implements the behavior (an integer adjusted by
  `eventDy()` per notch, no acceleration) for Fluid's own X/Y/W/H fields.

### `FL/Fl_Scrollbar.H`

**Status:** Complete — `fl.scrollbar`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Scrollbar.H))

Faithful, complete port of `handle()`'s area-hit-testing/drag/keyboard/
wheel logic and `draw()`'s layout, including real end-button arrow glyphs
and auto-repeat-while-held.

- `int value() const` can't be declared alongside the inherited `double
  value() const` — D has no return-type-only overloading, unlike C++'s
  name hiding — so `value()` stays the inherited double getter; the
  distinct-signature `value(int)`/`value(int,int,int,int)` setters port
  as-is.

### `FL/Fl_Positioner.H`

**Status:** Complete — `fl.positioner`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Positioner.H))

Faithful, complete port — a direct `Widget` subclass (not
`Valuator`-based, unlike the rest of this section, since it needs two
independent X/Y value axes), including the `protected` overloads FLTK
exposes so a subclass can confine the crosshair to less than the full
widget bounds. Draws real pixels.

## Browsers, trees, tables, file choosers

### `FL/Fl_Browser_.H`

**Status:** Complete — `fl.browser_`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Browser_.H))

The abstract base class for every browser: scrollbar layout, the full
`draw()` loop, scroll-into-view/selection logic, `sort()`, and the
complete keyboard-navigation + mouse state machine for all four `type()`
values.

Differences from FLTK:
- `void* item` becomes `Object item` throughout — a D class reference
  gives the same opaque-pointer-with-identity-comparison semantics FLTK's
  storage-agnostic protocol needs, for free.
- FLTK's `handle()`-local `static` variables are genuinely process-wide
  state shared by every `Fl_Browser_` instance, not per-object — ported
  as module-level D globals, same treatment as `fl.slider`'s `offcenter`.
- Icon support is deferred entirely to `fl.browser` — this base class has
  no icon concept in FLTK either.

### `FL/Fl_Browser.H`

**Status:** Complete — `fl.browser`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Browser.H))

The concrete, Forms-compatible scrolling text browser: a linked list of
lines, the `'@'`-format-code markup (bold/italic/size/color/underline/
background-fill/align, escaping), tab-separated column layout, and real
icon rendering.

Differences from FLTK:
- A line's text is a plain GC `string`, not a hand-`malloc()`'d flexible
  array member — FLTK's `text(line, newtext)` replaces the whole node
  purely to manage a fixed C buffer; since a node's identity never
  changes here, no pointer-fixup bookkeeping (`replacing()`) is needed
  either.
- `load(filename)` reads the whole file and splits on `'\n'` rather than
  FLTK's byte-at-a-time read (which also arbitrarily truncates any line
  over 1023 bytes — not reproduced here).
- One FLTK bug is faithfully reproduced, not fixed: the `'@'`-format-code
  scanner has a real C++ one-byte out-of-bounds read on a lone trailing
  unescaped `'@'` — harmless in practice, not filed as a bug in FLTK.

### `FL/Fl_Select_Browser.H`

**Status:** Complete — `fl.select_browser`

Trivial `type(selectBrowser)` subclass of `fl.browser`.

### `FL/Fl_Hold_Browser.H`

**Status:** Complete — `fl.hold_browser`

Trivial `type(holdBrowser)` subclass of `fl.browser`.

### `FL/Fl_Multi_Browser.H`

**Status:** Complete — `fl.multi_browser`

Trivial `type(multiBrowser)` subclass of `fl.browser`.

### `FL/Fl_Check_Browser.H`

**Status:** Complete — `fl.check_browser`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Check_Browser.H))

A scrolling list of checkable text lines, subclassing `fl.browser_`
directly with its own simpler item list (no `'@'`-codes, columns, or
icons). Faithfully preserves a genuinely confusing FLTK design point: the
usual `item_select()`/`item_selected()` meaning is repurposed here to
mean "toggle the checkbox," not "row selection highlight" — documented
at length in the module's own top comment.

- `find_item(int)`/`lineno()` are named `findItemN()`/`checkLineno()`,
  not `findItem()`/`lineno()` — `Browser_.findItem(int)` already exists
  with the same signature but a completely different meaning (pixel-Y
  hit-testing); reusing the name would silently become an accidental
  override.

### `FL/Fl_File_Browser.H`

**Status:** Complete — `fl.file_browser`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_File_Browser.H))

An `fl.browser.Browser` subclass for filenames: multi-line item height,
bold directories with a trailing `/`, and real per-line icons (via
`fl.file_icon`).

Differences from FLTK:
- `load()` for a directory listing is named `loadDirectory()`, not an
  overload of `load()` — a default-valued sort parameter would make a
  single-string call genuinely ambiguous against the inherited
  `load(filename)` once both were named `load()` in one D overload set
  (unlike C++, where arity alone keeps them apart without issue).
- Lists directories directly via `std.file.dirEntries()` instead of a
  platform-specific driver hook; the sort parameter is a `string`-
  comparing delegate instead of a `dirent**`-comparing function pointer.
- `load("")` (list all mount points) isn't supported — genuinely
  platform-specific, out of scope.
- A synthetic `".."` entry is added explicitly to every listing — `std.
  file.dirEntries()` never yields `"."`/`".."` the way POSIX `readdir()`
  does, but FLTK's own loader relies on `".."` being present in the raw
  listing to show a real, clickable "go up" row (needed so an empty
  directory still shows a "../" row instead of nothing).
- `full_height()` isn't overridden; the base class's cached total is
  already correct. (FLTK's own override passed a 0-based index to the
  1-based `find_line()` until FLTK `6b20e13c7`.)

### `FL/Fl_File_Icon.H`

**Status:** Complete — `fl.file_icon`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_File_Icon.H))

A small vector-icon format (opcodes in a `short[]` array), drawn via
`fl.draw`'s transform-stack/vertex-path primitives. Real `.fti`
vector-format parsing and real raster-icon loading (via `fl.shared_image`,
walked into the same run-length polygon approximation FLTK itself uses).

Differences from FLTK:
- `void* item`/pointer-returning `add()` becomes a plain `int` index into
  a GC `short[]` — no C buffer to invalidate.
- Raster loading doesn't re-derive FLTK's own manual XPM colormap
  parsing (~140 lines) for multi-color images — an XPM's `Pixmap`
  converts to an already-decoded `RGBImage` first, so every pixel format
  walks one unified loop. A 1-bit XBM `Bitmap` isn't handled, matching
  FLTK's own generic switch having no real case for it either.
- `load_system_icons()`'s KDE-mimelnk/GNOME/CDE/SGI legacy detection
  cascade is ported faithfully but is effectively dead on any system
  built after ~2005 (confirmed by reading its own `exists()` guards) — it
  falls through to three built-in vector icons (plain/image/dir) in
  practice, same as it would in FLTK on a modern system.

### `FL/Fl_File_Chooser.H`

**Status:** Complete — `fl.file_chooser`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_File_Chooser.H))

The FLTK-native file-selection dialog: directory listing, filename input,
filter dropdown, a favorites menu (backed by `fl.preferences`), a preview
pane (text and image), hidden-file toggling, and the `fl_file_chooser()`/
`fl_dir_chooser()` convenience wrappers.

Differences from FLTK:
- No `cb_xxx_i`/`cb_xxx` static-trampoline pairs — FLTK's fluid-generated
  code exists almost entirely to work around a plain-function-pointer
  callback type; every one collapses into a single D closure.
- `FileChooser` is not a `Widget` (matching FLTK: a plain class wrapping
  two real windows) — `callback()` takes a `void delegate(FileChooser)`
  directly; `user_data()` isn't ported (capture what you need instead).
- Every fixed-size `char[]` buffer becomes a plain D `string`.
- The preview updates as soon as a file is selected; FLTK waits one second.
- `Fl::system_driver()`-gated platform hooks (`colon_is_drive()`, etc.)
  collapse to their fixed POSIX answers — not a driver abstraction
  skipped, one that was never needed for a single-platform port.

### `FL/Fl_Native_File_Chooser.H`

**Status:** Complete (Linux/X11) — `fl.native_file_chooser`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Native_File_Chooser.H))

Only FLTK's own FLTK-styled backend is ported. **On Linux this is a
deliberate, permanent design decision, not a gap**: FLTK itself offers
GTK (via `dlopen()`) and Kdialog/Zenity (via subprocess spawning) as
alternative "native" backends, but there is no single native look on
Linux the way there is on Windows/macOS — correctly detecting "which
desktop environment is native here" at runtime would mean depending on
both GTK and Qt/KDE to cover the common cases, conflicting with this
project's minimal-dependency stance (the same reasoning `CONVENTIONS.md`'s
external-library-decision section applies elsewhere). The FLTK-styled
dialog already ported *is* the intended, final Linux behavior — GTK/Kdialog/Zenity are out of scope on
Linux permanently, not "not yet decided."

- The Windows-native and macOS-native backends aren't ported; the
  FLTK-styled dialog is used on every platform.
- No separate driver abstract base — this port's usual "concrete
  implementation until a second backend needs one" rule.
- `strnew()`/`strfree()`/`strapp()`/`chrcat()` (C buffer-management
  helpers) aren't ported — every field they backed is a plain GC
  `string`.

### `FL/Fl_Tree_Prefs.H`

**Status:** Complete — `fl.tree_prefs`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Tree_Prefs.H))

The tree's settings object (fonts, colors, margins, icons, selection/
connector style), including real deactivated-icon derivation
(grayed-out copies via `Image.copy()`/`.inactive()`) and real icon sizes.

- Ported as a D `class` (reference semantics) — a `Tree` and every
  `TreeItem` share one instance, matching FLTK's own single-shared-object
  usage; a `struct` would silently break the sharing.
- `tree_connector_style()`/`tree_draw_expando_button()` (`Fl_System_
  Driver` hooks FLTK adds purely so a future non-X11 platform could theme
  these) aren't ported as a driver abstraction — this port has no such
  hierarchy at all; the actual drawing logic lives as a plain function in
  `fl.tree_item` instead.

### `FL/Fl_Tree_Item_Array.H`

**Status:** Not applicable — n/a *(absorbed into `fl.tree_item`)*

FLTK's own hand-managed `Fl_Tree_Item**` array class exists purely
because pre-C++11 FLTK avoids STL/templates. This port uses a plain
`TreeItem[]` GC array directly on `fl.tree_item.TreeItem` instead — the
same substitution as `fl.menu_`'s `MenuItem[]`. There's no future in
which a separate array-wrapper class becomes the right design here.

### `FL/Fl_Tree_Item.H`

**Status:** Complete — `fl.tree_item`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Tree_Item.H))

A single tree node: label, per-item font/color overrides, real icons, an
optional child widget, and recursive children.

Differences from FLTK:
- `user_data()`/`void*` becomes `Object userData_` — unlike a callback's
  `user_data()` (dropped entirely in favor of D closures), this is an
  arbitrary opaque per-node payload unrelated to any callback, so a
  type-safe `Object` reference is the natural equivalent.
- The bit-packed flags field becomes four separate `bool` fields — this
  bitmask is a private implementation detail never exposed to callers as
  a raw bitmask, so there's no combinable-bitmask API to preserve.
- The deprecated no-tree constructor isn't ported — FLTK's own doc
  comment says it's genuinely degraded, not just an old name ("you must
  use `Fl_Tree_Item(Fl_Tree*)` for proper horizontal scrollbar
  behavior"); every method here already assumes a non-null owning tree.

### `FL/Fl_Tree.H`

**Status:** Complete — `fl.tree`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Tree.H))

The `Group`-derived widget: a hierarchical browser of `TreeItem`s with
real scrollbars, open/close subtrees, four selection modes (including
drag-to-reorder), and full keyboard navigation. Also ports
`load(Fl_Preferences&)` (a debug/inspection method with no matching
`save()` even in FLTK).

Differences from FLTK:
- No separate `Fl_Tree_Reason` enum — FLTK's own header already defines
  every value as a literal alias of the generic `CallbackReason` value
  space, so `callbackReason()` uses that directly.
- Path-taking methods return `string`, not `char*`+`len`.
- `get_selected_items(Fl_Tree_Item_Array&)` becomes `selectedItems()`
  returning `TreeItem[]` directly.
- `resize()`'s branch between two different ancestor classes' behavior
  (a real choice C++ has and D's single-level `super.resize()` can't
  directly express) simplifies to always taking the `Group.resize()`
  path — behaviorally identical for this port's default configuration,
  since the geometry recompute that follows either branch is
  unconditional anyway.
- New `package(fl)` bridge methods on `Tree` let `fl.tree_item` reach
  `Group`'s `protected` child-drawing methods and `Tree`'s own inner
  geometry — `TreeItem` isn't a `Group` subclass, so it can't reach them
  the way `Tree` itself can.
- Public `add(TreeItem parentItem, string name, TreeItem item)`
  overload, forwarding to `TreeItem.add(prefs, name, item)` — needed by
  `fluid.node_browser`'s custom `NodeBrowserItem`, since
  the pre-existing 2-arg `add(parentItem, name)` wrapper only reached
  the plain-label-only variant one level down, with no way for a caller
  outside `fl.tree_item` itself to insert a pre-built custom `TreeItem`
  subclass (needed for per-item custom `drawItemContent()`/
  `calcItemHeight()` overrides, e.g. a project-tree row that draws a
  bold class name plus a plain instance name instead of one flat
  string).
- `recalcTree()` is public, matching FLTK's own `Fl_Tree::recalc_
  tree()` (`FL/Fl_Tree.H`, public there too) — needed since
  `NodeBrowserItem`'s row content depends on mutable data the tree
  doesn't own (a `Node`'s `comment`/`instanceName`, edited live from a
  separate dialog in the `fluid` package), so a caller outside `fl`
  itself needs a way to tell the tree its cached item geometry may be
  stale after such an edit.

### `FL/Fl_Table.H`

**Status:** Complete — `fl.table`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Table.H))

Base widget for tables of cells drawn via a `drawCell()` virtual hook, row/
column headers, interactive resizing, real scrolling (a nested
`fl.scroll.Scroll` for the "table as container of real widgets" use
case), and full keyboard navigation.

Differences from FLTK:
- One real FLTK bug is fixed, not replicated: `row_height(int,int)`
  grows its backing array one element short of `col_width()`'s otherwise-
  identical logic — invisible UB in C++'s unchecked vector indexing, a
  guaranteed crash under D's bounds checking. See `FLTK_ISSUES.md`.
- `TableContext` stays an open bitmask (`alias int` + constants), not a
  closed `enum`, since real call sites combine values with `&`.
- `std::vector<int>` becomes plain `int[]`.
- `Fl::flush()` (forcing an immediate synchronous repaint mid-autoscroll-
  drag) isn't called here; autoscroll animates via the timer +
  `fl.core.check()`, a minor smoothness difference only.
- `Group`'s constructor calls `begin()` *virtually*, and D resolves
  virtual dispatch to the most-derived override from the start of
  construction (unlike C++), so `Table`'s own `begin()`/`end()`/etc.
  overrides (forwarding to its nested `Scroll`, matching FLTK's own thin
  forwarders) can be reached before that `Scroll` exists. Every such
  override guards on the nested container being non-null, falling back
  to plain `Group` behavior during that window — see `CONVENTIONS.md`'s "D
  also does not build up the vtable progressively during construction"
  note for the general lesson. The same class of problem applies at a
  second, separate call site: `Table`'s own constructor
  calls `tableResized()` → `tableScrolled()`, which unconditionally
  calls the user-overridable `drawCell()` — safe in FLTK C++ only
  because its vtable still points at `Fl_Table`'s own empty
  `draw_cell()` base implementation during `Fl_Table`'s own
  constructor, never reaching a subclass's real override until that
  subclass's own constructor body runs. `table_ !is null` (the guard
  used everywhere else in this class) doesn't help here, since
  `table_` is already assigned by the time this call happens — a
  separate `constructed_` flag, set true only once `Table`'s own
  constructor body finishes, guards this one instead. Without that
  flag, `source/examples/table_spreadsheet.d`'s own
  `Spreadsheet.drawCell()` crashes with a `SIGSEGV` via this exact path,
  called before `Spreadsheet`'s own fields exist; every sample under
  `source/examples/table_*.d` and `source/test/table.d` overrides
  `drawCell()` the same way and is exposed alike.

### `FL/Fl_Table_Row.H`

**Status:** Complete — `fl.table_row`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Table_Row.H))

A row-selection specialization of `Table` (click/Ctrl-toggle/Shift-
extend/drag whole-row selection), three selection modes.

- `type(TableRowSelectMode)`/`type()` are renamed `selectMode(...)`/
  `selectMode()` — FLTK reuses the generic `Fl_Widget::type()` name for
  an unrelated concept via C++ method-hiding, which D can't express for
  two same-arity overloads differing only in return type; nothing about
  `Widget.type()`'s byte is meaningful for a `TableRow`, so a clearer,
  non-colliding name is used instead of an `alias`-based workaround.

## Layout containers

### `FL/Fl_Pack.H`

**Status:** Complete — `fl.pack`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Pack.H))

Faithful, complete port, including the "last child, if also
`resizable()`, takes all remaining room" special case. Draws real pixels.

- A new `Widget.resizeBoundsOnly()` helper backs `draw()`'s own resize —
  the D structural equivalent of FLTK's C++-only pattern of explicitly
  qualifying `Fl_Widget::resize(...)` to skip every override between the
  caller and the base class (D's `super.foo()` only reaches the
  *immediate* parent, not an arbitrary ancestor).

### `FL/Fl_Scroll.H`

**Status:** Complete — `fl.scroll`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Scroll.H))

Faithful port of the layout math, child-management overrides, `resize()`,
`scrollTo()`, real tiled-scheme-background drawing, and the incremental
`FL_DAMAGE_SCROLL` blit-and-patch repaint path (`fl.draw.fl_scroll()`, a
new `XCopyArea()`-based primitive).

Differences from FLTK:
- FLTK's synchronous wait for `GraphicsExpose`/`NoExpose` after a scroll
  blit (to recover pixels that were themselves obscured by another window
  at blit time) isn't ported — a blocking wait for a specific event type
  from inside a widget's `draw()`, nested inside this port's own single
  event loop, was judged too much reentrancy risk for a rare edge case.
  The shared GC disables `graphics_exposures` outright instead, rather
  than silently dropping events it doesn't handle.
- Protecting the built-in `scrollbar`/`hscrollbar` members from
  `Group.clear()`'s child-deletion sweep needs only one `deleteChild()`
  override here, where FLTK needs that override *plus* a hand-written
  second copy of the same protection in both `clear()` and the destructor
  — because C++ unwinds an object's vtable as each destructor in the
  chain runs, while D keeps the same vtable for an object's entire
  lifetime including through its own destructor chain (see `CONVENTIONS.md`'s
  "D does not unwind the vtable during destruction" note).

### `FL/Fl_Tabs.H`

**Status:** Complete — `fl.tabs`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Tabs.H))

Faithful, complete port of tab layout (including the shrink-around-the-
selected-tab overflow algorithm), hit-testing, drag/keyboard/shortcut
`handle()`, a real overflow popup menu, real tooltip integration, and a
real close-button glyph (via `fl.symbols`).

- Storage simplification, not touching layout/hit-test logic: FLTK's
  manually-`malloc()`-sized C arrays (a perf optimization, only
  reallocated when child count changes) collapse to plain D dynamic
  arrays resized unconditionally on every layout pass — D's `.length =`
  is already cheap when unchanged, so the "did it actually change?" guard
  had nothing left to optimize.
- A tab's `&`-shortcut marker renders with an underline: this port's
  `tabPositions()`/`drawTab()` equivalents save/set/restore the
  *global* shortcut-underline flag around their own label calls,
  matching FLTK's own `tab_positions()`/`draw_tab()` — needed since a
  plain `Fl_Group` tab page never sets its own shortcut flag the way a
  button does.

### `FL/Fl_Tile.H`

**Status:** Complete — `fl.tile`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Tile.H))

Faithful, complete port including `size_range` mode (per-child
minimum-size constraints) — load-bearing throughout FLTK 1.5.0's own
resize/drag methods, so there's no smaller faithful subset that drops it.
Real resize-cursor changes while hovering/dragging a divider.

- FLTK's manually-`realloc()`-grown size-range array collapses to a plain
  D dynamic array. FLTK's own "null pointer = size_range mode off" check
  is deliberately *not* ported as "D array `is null`": **a zero-length D
  dynamic array `is null` evaluates to `true`**, which would be
  indistinguishable from "mode never turned on" the moment a caller
  initializes the size-range table *before* adding any children (the
  commonly recommended usage, exercised by FLTK's own sample and this
  port's own). A dedicated `sizeRangeEnabled_` boolean tracks the mode
  instead.
- The deprecated 4-arg `position()` shim and a C++-only-disambiguation
  2-arg override aren't ported — D's own `Widget.position()` already
  dispatches virtually to `Tile.resize()` without needing them.

### `FL/Fl_Wizard.H`

**Status:** Complete — `fl.wizard`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Wizard.H))

Faithful, complete port, including the mouse-cursor reset to the default
arrow whenever the visible pane changes (in case the outgoing child left
an I-beam or similar behind).

- One documented omission: FLTK's own private `value_` member is set in
  the constructor and never read again anywhere — genuinely dead state in
  FLTK itself, not ported.

### `FL/Fl_Flex.H`

**Status:** Complete — `fl.flex`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Flex.H))

Faithful, complete port of `init()`/`draw()`/`resize()`/`layout()`/
`fixed()`/`margin()`/`gap()`.

- FLTK's hand-grown fixed-size array (with its own growth-strategy
  virtual hook) collapses to a plain D `Widget[]` — the runtime's own
  amortized array growth leaves nothing for that customization point to
  customize.

### `FL/Fl_Grid.H`

**Status:** Complete — `fl.grid`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Grid.H))

Faithful, complete port of the row/column layout math (min-size/weight-
distribution/span/alignment passes) and cell bookkeeping, verified with
`layout()`-level tests on both axes independently (the column and row
code are separately hand-transcribed mirrors of each other, not one
shared axis-parameterized routine).

Differences from FLTK:
- FLTK's manually-grown C arrays collapse to plain D dynamic arrays;
  each row's hand-rolled singly-linked cell list (a wart FLTK's own doc
  comment calls out, GitHub issue #937) becomes a plain column-sorted
  `Cell[]`.
- Out-parameter getters (`minimum_size(int*,int*)`, `margin(...)`,
  `gap(...)`) aren't ported as such — each has the exact same arity as an
  existing same-named setter overload (the same ambiguous-overload trap
  `fl.chart`'s `bounds()` hit earlier in this port), so they're separate,
  differently-named plain-return getters instead
  (`minWidth()`/`minHeight()`, `marginLeft()` etc., `gapRow()`/`gapCol()`).
- `Cell::align()`/`Fl_Grid::debug()` are renamed `alignment()`/
  `dumpLayout()` — `align`/`debug` are both D keywords.
- One likely FLTK off-by-one is faithfully reproduced, not fixed:
  `widget()`'s bounds check uses `>` where `>=` looks intended, letting a
  one-past-the-end index slip through — harmless UB in C++, a caught
  `RangeError` here. See `FLTK_ISSUES.md`.

## Misc widgets

### `FL/Fl_Box.H`

**Status:** Complete — `fl.box`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Box.H))

Faithful, complete port — the first concrete widget in this project.

### `FL/Fl_Chart.H`

**Status:** Complete — `fl.chart`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Chart.H))

Faithful, complete port of the data-management API and all 7 chart-type
draw routines (bar/horizontal-bar/line/fill/spike/pie/special-pie).

- FLTK's manually `calloc()`/`realloc()`'d entries array collapses to a
  plain `ChartEntry[]`; the `maxsize()` sliding-window cap is faithfully
  preserved, including its asymmetry between `add()` (drops oldest) and
  `insert()` (silently drops newest), matching FLTK's own growth
  condition.
- `bounds(double*, double*)`'s getter becomes two plain getters
  (`boundsMin()`/`boundsMax()`) rather than an `out`-parameter overload
  alongside the setter — an `out`-parameter overload is genuinely
  ambiguous with the setter at a D call site (passing plain locals
  matches both, and D silently picks the setter), so this shape avoids
  that ambiguity outright.

### `FL/Fl_Progress.H`

**Status:** Complete — `fl.progress`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Progress.H))

Faithful, complete port — a plain `Widget` subclass (not
`Valuator`-based), drawn as two real, correctly clipped regions.

### `FL/Fl_Color_Chooser.H`

**Status:** Complete — `fl.color_chooser`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Color_Chooser.H))

Faithful, complete port: the hue/saturation wheel, brightness bar, RGB/
byte/hex/HSV mode dropdown, and the ready-made modal `fl_color_chooser()`
popup. The hue/value gradients draw via a real batched `fl_draw_image()`
call (one `XPutImage()` per redraw) rather than a per-pixel loop, which
would cost one X protocol request per pixel (~13,000 for a 115×115 hue
box per drag event) and be visibly slower than FLTK.

- `rgb2hsv()`'s H/S output parameters are `ref`, not `out` — FLTK's plain
  `double&` leaves H/S untouched (retaining the caller's prior value)
  whenever R==G==B, since hue/saturation are undefined for gray; D's
  `out` would unconditionally reset to NaN regardless of whether the
  function body assigns it, silently poisoning the next round-trip for
  black specifically.

### `FL/Fl_Help_View.H`

**Status:** Complete — `fl.help_view`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Help_View.H))

A ~4600-line mini HTML-subset layout/rendering engine — the largest
single port in this project besides Fluid itself. Full HTML tokenizer/
layout (including real `<TABLE>`/`<TR>`/`<TD>`/`<TH>` support), text
selection, `find()`, `load()` (local files and non-`file:` schemes), the
right-click copy menu, and real `<IMG>` rendering (including a real
broken-image fallback glyph).

Differences from FLTK:
- **Structural**: FLTK splits into a public shell class plus a private
  `Impl` class holding all real state, purely for C++ ABI stability (its
  own doc comment says so explicitly) — this port collapses both into one
  `HelpView : Group` class, since D has no such ABI constraint.
- **Mechanism**: FLTK measures character positions under the mouse by
  re-entering `draw()` redirected to an offscreen buffer; this port has
  no offscreen-buffer primitive in `fl.draw`, so a degenerate zero-size
  clip substitutes instead — real `pushClip()`/`popClip()` suppress pixel
  output through the same real `draw()` call while every measurement side
  effect still runs correctly. One side effect of this substitution
  is guarded explicitly: a scrollbar-geometry-correction side effect
  inside `draw()` is skipped so a mouse-drag-driven
  measurement pass doesn't mutate scrollbar geometry as a side effect.
- Growable D arrays replace FLTK's fixed `int[MAX_COLUMNS]` table-column
  caps (a 200-column limit no real document would approach).
- Several FLTK bugs/inconsistencies are faithfully reproduced, not fixed
  — see `FLTK_ISSUES.md`: `format()` unconditionally overwrites
  `WIDTH`/`HEIGHT` once `SRC` is present while `draw()` only fills in a
  missing dimension; `atof()` vs. `atoi()` used inconsistently for the
  same attribute across two functions; a list-numbering stack declared
  outside its own retry loop; a dead, never-read attribute computation.

### `FL/Fl_Help_Dialog.H`

**Status:** Complete — `fl.help_dialog`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Help_Dialog.H))

A small toolbar (Back/Forward, text-size buttons, a find field) over an
embedded `HelpView`, plus navigation history — the wrapper `fl.help_view`
needs for real `<IMG>` GIF/SVG rendering to actually be reachable.

- Growable navigation history (`HistoryEntry[]`) replaces FLTK's own
  fixed 100-entry arrays — FLTK's own source comment already flags this
  as a wart it wants removed (`// FIXME: we must remove those static
  numbers`), so this isn't an independent judgment call.
- `show(int argc, char **argv)` isn't ported — no argv-parsing entry
  point exists in this port's window-creation path to forward to.
- One FLTK bug is faithfully reproduced, not fixed: the Back and Forward
  callbacks are structurally identical except Back correctly uses the
  recorded scroll position for the target page while Forward instead uses
  the *current* page's position (read before the target loads) — see
  `FLTK_ISSUES.md`.

### `FL/Fl_Tooltip.H`

**Status:** Complete — `fl.tooltip`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Tooltip.H))

Faithful port of the real behavior: hover/show/hide-delay timers, the
popup window, target tracking, the "recently shown, pop up again fast"
hover-chain logic, dynamic tooltip-text computation, real word-wrap, and
`@`-symbol image glyphs.

Differences from FLTK:
- The popup window reuses `Widget.Flag.menuWindow` for its override-
  redirect X11 treatment, rather than porting FLTK's separate
  `TOOLTIP_WINDOW` flag — that flag's only functional X11 effect is a
  cosmetic EWMH hint suppressing compositor animations, skipped here.
- Integration with `fl.core.handle()`/`belowmouse()` doesn't replicate
  FLTK's lazy function-pointer wiring trick (a C++ static-linking
  mechanism with no D equivalent, and unnecessary here since this library
  is already one compiled unit) — `fl.core` calls straight into this
  module instead, centralizing "call `enter()` when `belowmouse()`
  changes" into `belowmouse()`'s own setter rather than replicating every
  scattered FLTK call site individually.
- `enter(Widget)` is named `mouseEnter(Widget)` — a bare `enter()` would
  collide with the `Enter` keysym constant, both reachable unqualified
  under a single `import fl;`.
- **Hover-intent behavior**, a deliberate improvement beyond FLTK, not a
  faithful port: a tooltip stays open while the mouse is over it, instead
  of dismissing itself the instant the mouse touches it. A mouse
  verifiably over the popup keeps it open, left exactly where it is (no
  repositioning — `layout()`'s own math reads the live mouse position, so
  calling it while hovering the popup would make it chase the cursor and
  appear to run away). Landing anywhere else with no tooltip of its own —
  including a `null` `belowmouse()` target, which `fl.platform_x11`'s
  `LeaveNotify` handling fires unconditionally the moment the pointer
  leaves the target widget's own top-level window, before it could
  possibly have reached the separate top-level popup window yet, and
  including the small screen-space gap `TooltipBox.layout()` leaves
  between the widget and the popup — starts a short grace timer
  (`hoverdelay()`) instead of hiding instantly, cancelled if the mouse
  reaches the popup or the original widget before it fires. There is no
  FLTK mechanism to port: FLTK hides synchronously on every such
  transition with no grace period, and its own "reposition, but don't
  move if unchanged" branch doesn't reliably prevent that either, since
  its position recompute reads the live mouse coordinate and so
  essentially always reports "moved" once the cursor is genuinely over
  the popup. The explicit keypress-dismiss case is unaffected: it calls a
  separate `dismissNow()` (the one real immediate-hide entry point), not
  `mouseEnter(null)`. The mouse being over the popup also suspends the
  separate stale-tooltip auto-hide (`hidedelay()`, 12s default) for as
  long as it stays there — that timer still runs its full course while the
  mouse merely sits still over the *source* widget instead.
- **Windows focus-stealing**: `fl.platform_win32.createWindow()` shows a
  borderless top-level window (tooltips included) without activating it,
  honoring the `WS_EX_TOOLWINDOW` style it sets for exactly this case —
  see `FL/win32.H`'s row. This matches FLTK's own behavior: its tooltip
  window is an ordinary `Fl_Menu_Window` on every platform, Windows
  included, and its Windows driver takes care not to activate one on show.

### `FL/Fl_Preferences.H`

**Status:** Complete — `fl.preferences`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Preferences.H))

A tree of named groups, each holding key/value entries and child groups,
backed by a per-database root that resolves the on-disk file path and
does real read/write. The on-disk file format is ported byte-for-byte
(header comments, `[group]` sections, 80-column wrap continuations,
backslash/octal text escaping, hex binary encoding), including the
Unix-specific `/etc/fltk/` world-readable permission protection on
system-wide preference files.

Differences from FLTK:
- Both Linux/Unix and Windows path resolution are ported (Unix via
  `$XDG_CONFIG_HOME`/`$HOME/.config`, matching `Fl_Unix_System_Driver`;
  Windows via a real `SHGetFolderPathW(CSIDL_APPDATA`/
  `CSIDL_COMMON_APPDATA)` call, matching
  `Fl_WinAPI_System_Driver::preference_rootnode()` — not a plain
  `%APPDATA%` environment-variable read, since that wouldn't reliably
  reflect a redirected/roaming profile the way the real API does).
  There's no driver-class abstraction backing the split (matching this
  port's general preference for a plain `version (Windows)`/
  `version (Posix)` branch inside one concrete function over a
  polymorphic driver hierarchy when only two platforms exist) — see
  `preferenceRootnode()`'s own dispatch in `fl.preferences`. UUID
  generation likewise isn't platform-split: `newUUID()` uses Phobos'
  `std.uuid.randomUUID()` on every platform instead of transliterating
  FLTK's own per-platform raw entropy-gathering fallback.
- A group's child list is a plain chronologically-ordered D array, not
  FLTK's prepend-to-head linked list plus a separately-maintained
  reversed index cache — traced through FLTK's own indexing math to
  confirm this is a faithful behavioral match (FLTK's own newest-first
  internal order is compensated for everywhere it's read, so the net
  observable order is already chronological), not just a convenient
  simplification.
- `Fl_Preferences::Name` (a C++-only printf-into-a-temporary RAII trick)
  isn't ported — superseded by `std.format.format()`, since every name
  parameter here is already a plain `string`.
- `ID` is the real `PreferencesNode` class (FLTK: `Node`; see below), not a `void*` — no translation-unit-hiding
  concern exists in a single-compiled-unit D library.
- `Node` itself is ported as `PreferencesNode`, not `Node` — a
  deliberate naming deviation from FLTK (not faithfulness-by-default),
  made to avoid a name clash with `fluid.node.Node` (Fluid's own, far
  more pervasively used, project-tree node type): with both in scope
  under a plain `import fl;`, every file needing `fluid.node.Node` would
  have to fall back on a selective import (`import fluid.node : Node;`)
  to disambiguate. Renaming this side rather than Fluid's own `Node` was
  the smaller-blast-radius choice: this type's own name is referenced
  only within this file itself, versus `fluid.node.Node` being the single
  most pervasively used identifier across the entire `fluid/` tree.
- No automatic flush-on-GC-collection can be relied on for timely disk
  writes — the destructor is still a best-effort fallback, but callers
  that need data saved reliably must call `.flush()` explicitly, loudly
  documented rather than silently assumed.
- Number formatting is always locale-independent regardless of the
  `C_LOCALE` flag's value — confirmed that `std.format`/`std.conv` never
  consult the process locale at all (unlike C's `printf`/`atof`), so
  there's no legacy locale-dependent path to port; the flag is still real
  for file-format fidelity, just has no observable effect here.

### `FL/Fl_Multi_Label.H`

**Status:** Complete — `fl.multi_label`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Multi_Label.H))

Faithful port of the two-part label positioning algorithm (draw part A,
shrink the box by whatever it measured, draw part B in what's left),
including real image parts and chained `MultiLabel`s.

- **The one real structural deviation**: FLTK stores both label parts as
  a single `const char*`, reinterpreted per a type tag as literal text,
  an `Fl_Image*`, or a chained `Fl_Multi_Label*` — a tagged-union-via-
  pointer-cast trick that only works because C++ doesn't check what a
  `const char*` actually points to. This port's `Label.text` is a real
  GC-owned `string` that can't be punned to another type, so each
  alternative gets its own typed field instead — a tagged union in
  spirit, not in memory layout. This needed one small, additive change to
  `fl.widget` itself: a new `Label.multi` field plus a
  `Labeltype.multiLabel` dispatch case, and a new `Widget.label(MultiLabel)`
  setter (the D-native replacement for FLTK's `Fl::set_labeltype()`
  registration call) — `fl.widget` and `fl.multi_label` end up mutually
  recursive, confirmed to compile and link fine (D resolves the whole
  symbol table before codegen, unlike C's textual `#include`).

### `FL/Fl_Timer.H`

**Status:** Not applicable — n/a

**Not to be confused with the real timer subsystem**, which is ported
and in active use (`fl.core.addTimeout()`/`repeatTimeout()`/etc.). `Fl_
Timer` itself is a distinct, separate XForms/Forms-Library compatibility
widget — FLTK's own doc comment calls it "provided only to emulate the
Forms Timer widget... you should directly call `Fl::add_timeout()`
instead" — see `CONVENTIONS.md`'s "Out of scope" section.

### `FL/Fl_Free.H`

**Status:** Not applicable — n/a

XForms/Forms-Library "free" widget compatibility shim — see `CONVENTIONS.md`'s
"Out of scope" section.

### `FL/Fl_FormsBitmap.H`

**Status:** Not applicable — n/a

XForms/Forms-Library image-loading compatibility shim, superseded by
`Fl_Image`'s modern subclasses — see `CONVENTIONS.md`'s "Out of scope" section.

### `FL/Fl_FormsPixmap.H`

**Status:** Not applicable — n/a

Same as `FL/Fl_FormsBitmap.H` — see `CONVENTIONS.md`'s "Out of scope" section.

## Images

### `FL/Fl_Image.H`

**Status:** Complete — `fl.image`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Image.H))

The base `Image` class and `RGBImage` (1-4 channel full-color images).
Real drawn pixels, real alpha (d==2/4) source-over-dest compositing
(source-over blend against the destination, matching FLTK's own non-
XRender fallback bit-for-bit), and real bilinear or nearest-neighbor
resampling (`RGBScaling`).

`draw()` is scale-aware and resamples from pristine native data exactly
once per target size, matching FLTK's real `Fl_Graphics_Driver::
draw_rgb()`: the target device-pixel size is `w()`/`h()` (the image's
fixed logical size) times the live `fl.core.currentScale()`, always
computed against `array`/`dataW()`/`dataH()` directly, never against a
previously-resampled copy. When that target equals the native
resolution (no explicit `scale()` call, or an image with native
resolution ahead of its logical display size — the common "2x headroom"
icon-asset case — landing exactly on an integer scale), `draw()` uses
`array` untouched, hitting the same zero-resample fast path FLTK's own
`Fl_RGB_Image::copy()` does. Otherwise a resampled copy (`scaledCache_`)
is built once via `copy(w,h)` and reused until the target size changes
again. The resample step itself forces bilinear via `scalingAlgorithm()`
(a separate static default from `rgbScaling()`'s own nearest default),
mirroring FLTK's own `Fl_Image::scaling_algorithm()`/`draw_rgb()`
temporary-override trick — `rgbScaling()` only governs an explicit,
program-called `copy()`. The scaled result is blitted 1:1, unscaled, via
`fl.draw.drawImageFixed()` (see that function's own doc comment).

Differences from FLTK:
- No generic `Image.data()`/`count()` polymorphic accessor — nothing in
  this port needs to reach a subclass's raw data without already knowing
  its concrete type; each subclass exposes its own typed field instead.
- `RGBImage.array` is a real D slice, not a raw pointer plus an
  "should this be freed" ownership flag — the GC already manages the
  memory regardless of who allocated it. This collapses FLTK's two RGB
  constructors (unchecked raw-pointer, and a length-checked one) into
  one, since a D slice already carries its own length.
- No colormap fallback, no honoring of a *negative* `ld()` on an
  `RGBImage` itself (the flipped-row form — `array` is a bounds-checked
  D slice, so an already-offset-and-walked-backwards pointer has no
  direct equivalent; the raw-buffer `fl.draw.drawImage()` primitive does
  support negative `d`/`l`, see `FL/fl_draw.H`'s row), and no
  offscreen-`Pixmap`/X11-resource image
  cache — `scaledCache_` (above) is a real D-side resampled-pixel-data
  cache, but there's still no server-side resource to release, matching
  this port's drawing model everywhere else.
- One real FLTK inconsistency, faithfully reproduced: `Fl_Image::fail()`'s
  condition never actually detects a too-short buffer for a normal
  `Fl_RGB_Image` — see `FLTK_ISSUES.md`.
- **No remaining external-codec gap** — GIF/SVG/PNG/JPEG (below) are all
  real; none of the four needed the from-scratch-vs-bind-to-a-C-library
  decision `CONVENTIONS.md`'s "Deferred" section covers for the codecs that
  still do.

### `FL/Fl_Pixmap.H`

**Status:** Complete — `fl.pixmap`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Pixmap.H))

Color-table-indexed (XPM-style) images with transparency, including
FLTK's non-standard "compressed" colormap extension.

Differences from FLTK:
- Transparency is deliberately binary, not alpha-blended — a classic XPM
  color is either successfully parsed (opaque) or the "None"/unparseable
  placeholder (transparent); there's no partial alpha to composite in the
  first place, so this port uses the same 1-bit X11 clip-mask technique
  FLTK's own native drawing path does.
- No `alloc_data`/`copy_data()` bookkeeping — FLTK needs it because it
  mutates color-table strings in place, a real hazard for a caller-owned
  literal array; D strings are immutable, so `colorAverage()`/
  `desaturate()` just build a new array instead, and the "don't corrupt
  the caller's original data" problem doesn't arise to begin with.
- When composited via a non-native driver (e.g. over a GL scene), the
  clip-mask mechanism is skipped in favor of drawing the already-computed
  RGBA buffer directly as a `d==4` image, so real alpha compositing
  works there too — the GC clip-mask trick has zero effect when
  drawing never touches a GC at all (as with a `Pixmap` drawn over a
  GL scene), so it can't be relied on in that case.

`draw()` is scale-aware, matching FLTK's real `Fl_Graphics_Driver::
draw_pixmap()`/`cache_size()` exactly: the target device-pixel size is
`w()`/`h()` (the icon's fixed logical size) times the live `fl.core.
currentScale()`, always resampled from `this`'s own pristine `xpmData`
via a lazily-built-and-reused cache (`scaledForDraw()`/`scaledCache_`).
When that target equals the native XPM resolution — the common case for
icon assets shipped at 2x their default logical display size, e.g. a
32x32 XPM drawn at 16 logical units, landing exactly on 32 at 200% — no
resampling happens at all, matching FLTK's own `Fl_Pixmap::copy()`
`W==data_w() && H==data_h()` fast path.

The cache-size decision is scale-aware: comparing the fixed *logical*
`w()`/`h()` against `dataW()`/`dataH()` while ignoring the live screen
scale would always downscale to the logical size first (throwing away the
native detail an icon like the one above has specifically to avoid
this), then hand that already-degraded buffer to `fl.draw.drawImage()`,
which resamples *again* to fit the actual device-pixel box — two lossy
nearest-neighbor passes compounding into a visibly blockier result than
FLTK's single, often-exact resample. `fl.draw.drawImageFixed()` is a
position-only blit primitive for buffers already resampled to their
final size, so the scale conversion happens only once (see that
function's own doc comment in `fl.draw`).

The 1-bit `XSetClipMask` transparency mask (`maskId_`) tracks
`fl.core.screenScale()` too, but doesn't resample independently: it's
built directly from the same already-correctly-sized RGBA buffer the RGB
blit uses (whatever `scaledForDraw()` decided on), so the two can't
drift apart by a rounding pixel the way two independent resample
computations could — the same mechanism as `fl.window.
Window`'s own `XShapeCombineMask` mask (`FL/Fl_Window.H`'s row).

### `FL/Fl_Bitmap.H`

**Status:** Complete — `fl.bitmap`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Bitmap.H))

Mono-color (1-bit) images, drawn stippled in the current color via a real
cached X11 bitmask `Pixmap`.

- Same `array`-as-D-slice deviation as `RGBImage`, collapsing FLTK's two
  length-checked constructors into one.

### `FL/Fl_Shared_Image.H`

**Status:** Complete — `fl.shared_image`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Shared_Image.H))

A filename-keyed, reference-counted image cache. Format detection covers
XBM/XPM/PNM (hardcoded, matching FLTK's own treatment of XBM/XPM — PNM is
hardcoded here too, unlike FLTK, where it's only ever added via the
external handler mechanism, since `fl.pnm_image` is just as much a core
part of this port) plus BMP/ICO/GIF/SVG/PNG/JPEG, registered through the
same real, public `addHandler()`/`removeHandler()` extension point FLTK
exposes (`fl_register_images()`). As in FLTK, a PNG, JPEG or SVG image
constructed from memory with a name is added to the pool under that
name (`SharedImage.addNamed()`), so `get(name)` and a `HelpView`
`<img src>` find it.

Differences from FLTK:
- The image pool is a plain linear-scan D array, not a hand-`qsort()`-
  sorted-and-`bsearch()`-searched C array — a typical app has at most
  dozens of shared images, where a linear scan costs nothing measurable.
- The non-`const` refcount-bump-and-return-self `copy()` overload is
  renamed `retain()` — FLTK genuinely has three different `copy()`
  overloads selected partly by whether the caller's own reference happens
  to be `const`, which is a confusing surface to preserve faithfully; a
  distinct name removes an easy-to-misuse footgun.

### `FL/Fl_Tiled_Image.H`

**Status:** Complete — `fl.tiled_image`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Tiled_Image.H))

A thin wrapper repeating a source image across an area, including the
`W==0 && H==0` "tile the whole current window" case (needed `Window.
current()`, see that row).

- FLTK's own doc comment still flags this whole area as fragile (a
  standing `\todo` to "fix Fl_Tiled_Image as background image for widgets
  and windows") — this port faithfully reproduces that same imperfect
  behavior (only the window currently being drawn gets filled, not
  necessarily the exact widget's bounds), not a new guarantee beyond what
  FLTK itself provides.

### `FL/Fl_Anim_GIF_Image.H`

**Status:** Complete — `fl.anim_gif_image`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_Anim_GIF_Image.H))

`AnimGifImage`, a real `fl.gif_image.GifImage` subclass: full multi-frame
GIF playback, compositing every decoded frame into a persistent
canvas-sized offscreen RGBA buffer, all 4 GIF disposal methods, the
Netscape loop-count extension, and real timer-driven playback.

- No `Fl_Shared_Image`-backed "scalable" cache for scaled playback — this
  port's `Image.scale()` is already lazy/metadata-only, so `.scale()` is
  just called before each frame draw instead of maintaining a second
  cached copy.
- Two FLTK oddities are faithfully reproduced, not fixed (candidates for
  `FLTK_ISSUES.md`): a truthy (not `>= 0`) check on the transparent-
  pixel index silently misfires when that index is 0; a disposal copy
  uses the *previous* frame's own encoded width as source stride even
  when frames are stored full-canvas-sized, a narrow latent bug inherited
  as-is.

### `FL/Fl_BMP_Image.H`

**Status:** Complete — `fl.bmp_image`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_BMP_Image.H))

Windows Bitmap (BMP) reader and writer — needs no external library at all
(uncompressed or simple RLE4/RLE8, decoded by FLTK itself), so this
shipped well before the JPEG/PNG library decision was resolved. Both old
OS/2 and new Windows headers, every pixel depth FLTK supports, RLE
decompression, and the trailing-alpha-mask heuristic older icon-style
BMPs use are all ported. `createBmp()` is the write-side counterpart,
used by `fl.core.copyImage()`.

- Reads the whole file into memory and walks it with a small private
  cursor struct instead of porting FLTK's dual file-or-memory reader
  helper class — this port's usual "slurp, then walk a cursor over a
  `ubyte[]`" convention, already established for `fl.pnm_image`.
- Not ported: `Fl_RGB_Image::max_size()`'s configurable safety cap — a
  rarely-tuned defensive limit not worth a subsystem for one caller.

### `FL/Fl_GIF_Image.H`

**Status:** Complete — `fl.gif_image`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_GIF_Image.H))

`GifImage`, a real `fl.pixmap.Pixmap` subclass matching FLTK's own class
hierarchy exactly: decoded pixel-index rows convert into `Pixmap`'s
existing "compressed colormap" XPM format rather than a second RGBA image
type, reusing `Pixmap`'s already-real drawing/transparency machinery as
is. Full LZW decompression (including interlaced de-interlacing).

- Needs no external library — GIF's LZW decompression is fully
  self-contained C++ in FLTK, the same shape as `fl.bmp_image`'s own
  native RLE decoder, so it never involves a "which library" decision.
- Faithfully reproduces a real, unstated FLTK quirk: the reported color
  count is unconditionally derived from the LZW minimum-code-size's bit
  depth, not the color table's own real declared entry count — a
  2-color GIF commonly reports 4 colors, the two extras defaulted to
  black.
- Not ported: the GIF-version-string mismatch warning — this port has no
  `Fl::warning()` equivalent anywhere, an established gap, not new here.

### `FL/Fl_ICO_Image.H`

**Status:** Complete — `fl.ico_image`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_ICO_Image.H))

Windows Icon (.ico) reader, genuinely subclassing `fl.bmp_image.
BMPImage` matching FLTK's own class hierarchy — an `.ico` file is a small
directory of embedded resources, each either a bare BMP bitmap or a full
embedded PNG. Directory parsing and all three selector modes (auto-pick
highest-resolution, directory-only, specific entry) are real.
PNG-embedded resources decode by delegating to
`fl.png_image.PngImage`'s in-memory-buffer constructor — shaped for
"decode a slice of an already-open buffer" (its `readPng()` stops at the
first `IEND` chunk and ignores anything after), matching FLTK's own memory-buffer branch
(`rdr.is_data()`) exactly; FLTK's *other* branch — reopening the source
file by name and seeking — has no equivalent here, since `ByteReader`
always wraps a fully-read in-memory buffer regardless of whether
`ICOImage` was constructed from a filename or raw data.

### `FL/Fl_JPEG_Image.H`

**Status:** Complete — `fl.jpeg_image` (+ `fl.jpeg_decoder`,
`fl.jpeg_encoder` and `fl.jpeg_common` for the codec)
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_JPEG_Image.H))

`JpegImage : RGBImage` (always decodes to RGB8 regardless of source
grayscale/color, matching FLTK's own unconditional behavior) and
`writeJpeg()`.

- **The codec is native D, not libjpeg.** `fl.jpeg_decoder` and
  `fl.jpeg_encoder` implement Rich Geldreich's public-domain jpgd/jpge
  (following Ketmar's D translation in `arsd`'s `jpeg.d`) with
  garbage-collected arrays and slices, exceptions (`JpegException`) and
  validated input; they produce the same pixels and bytes as that
  original. Decoding covers baseline and progressive 8-bit Huffman JPEGs
  with 1 (gray) or 3 (YCbCr) components and the H1V1, H2V1, H1V2 and H2V2
  subsamplings; arithmetic coding, 12-bit samples and CMYK/YCCK are
  rejected. Encoding writes baseline JPEGs from 1-, 3- or 4-channel
  pixels, with optional optimized Huffman tables (the default; two
  passes), quality 1–100 and any of those subsamplings.
- H2V2 chroma is upsampled in the frequency domain (jpgd's method), not
  with libjpeg's default triangle filter, so decoded pixels differ from
  libjpeg's by a small rounding amount (mean absolute difference 0.18–0.66
  per channel out of 255 against ImageMagick's decode of two real JPEGs).
- EXIF orientation is not applied, matching libjpeg.
- Tested by round-trip tests (JPEG is lossy, so those compare against a
  tolerance) and by decoding real JPEGs and comparing against
  ImageMagick's reference decode.

### `FL/Fl_PNG_Image.H`

**Status:** Partial — `fl.png_image`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_PNG_Image.H))

`PngImage : RGBImage` and `writePng()`.

- **Resolved as: adapt an already-real D translation, not bind libpng or
  write a decoder from scratch.** Built on Adam D. Ruppe's `arsd.png`
  (Boost Software License 1.0) — its low-level chunk/filter-
  reconstruction API is cleanly separated from its
  own `arsd.color`-based convenience layer, so retargeting it onto
  `RGBImage` needed only `std.zlib` (Phobos's own zlib binding) for the
  actual DEFLATE/INFLATE work, since PNG's compression genuinely is zlib
  by spec.

Missing:
- No Adam7 interlacing support (rejected with `errFormat`, not silently
  scrambled).
- No `tRNS`-based single-color-key transparency for plain greyscale/
  truecolor images (types 0/2 always load opaque) — indexed-image `tRNS`
  *is* supported, since that path was nearly free once the palette was
  already being resolved.

Verified byte-for-byte against ImageMagick's reference decode on 6 real,
adaptively-filtered PNGs (this port's own encoder only emits filter-type
0, so a self-round-trip alone can't exercise the decoder's Sub/Up/
Average/Paeth reconstruction).

### `FL/Fl_PNM_Image.H`

**Status:** Complete — `fl.pnm_image`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_PNM_Image.H))

Portable Anymap (PBM/PGM/PPM, formats P1–P6, plus XV's P7 thumbnail
extension) reader, working over a raw byte buffer with an explicit
cursor (header is whitespace-delimited ASCII, pixel data for the binary
formats is raw bytes with no delimiter).

- Real, specific error codes (file-access vs. malformed-format), not just
  a generic failure.
- Not ported: `Fl_RGB_Image::max_size()`'s configurable safety cap — same
  skip as `fl.bmp_image`'s row.

### `FL/Fl_SVG_Image.H`

**Status:** Complete — `fl.svg_image` (glue) + `fl.nanosvg` (parser) +
`fl.nanosvg_rast` (rasterizer)
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_SVG_Image.H))

SVG *input* — parsing an existing SVG document and rasterizing it into a
real `RGBImage` (distinct from `fl.svg_file_surface`, SVG *output*, see
that row under "Printing / off-screen surfaces"). `.svgz` (gzip-
compressed SVG) is supported too, via `std.zlib`.

- **Resolved as: port and own the vendored source, not a "which library"
  decision.** FLTK's own `nanosvg`/`nanosvgrast` are vendored, zlib-
  licensed, single-header C source with no `find_package()` anywhere in
  FLTK's own CMake config (confirmed directly, unlike JPEG/PNG, which do
  use `find_package()` and link a system library by default) — a much
  bigger port than GIF (nanosvg.h is 3106 lines, nanosvgrast.h 1483) but
  the same "vendored source to port and own" shape, not an external-
  library decision at all.
- The scanline/active-edge-table rasterization algorithm, fixed-point
  math, and stroke join/cap geometry are ported byte-for-byte faithful —
  only C-specific allocation plumbing (bump allocators, freelists,
  `malloc()`/`realloc()` capacity tracking) is simplified to plain D
  classes and dynamic arrays.
- `copy()` shares the parsed document (a plain GC reference) rather than
  re-parsing — replacing FLTK's manual reference-counting wrapper, which
  existed purely for the same sharing without a second parse.

### `FL/Fl_XBM_Image.H`

**Status:** Complete — `fl.xbm_image`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_XBM_Image.H))

X Bitmap (XBM) reader, a `Bitmap` subclass — reads the whole file as text
and splits into lines rather than FLTK's byte-at-a-time read (safe, since
XBM files are plain ASCII text throughout, this port's usual substitution
for this class of loader).

### `FL/Fl_XPM_Image.H`

**Status:** Complete — `fl.xpm_image`
([header](https://github.com/fltk/fltk/blob/master/FL/Fl_XPM_Image.H))

X Pixmap (XPM) reader, a `Pixmap` subclass — reads the whole file as text
and decodes each C-string-literal data row via a faithful port of FLTK's
own escape decoder.

- FLTK's mid-string `\<newline>` line-continuation escape isn't ported —
  no real-world XPM file needs it in practice; this reader stops decoding
  a row at its own line's end.

## Platform drivers (`src/drivers/*`)

FLTK has no `FL/*.H` headers for these — they're internal to `src/`, and
this port doesn't mirror FLTK's own abstract driver-class hierarchy for
them at all (see `CONVENTIONS.md`'s "Porting conventions": a concrete module
per target, not a polymorphic base/derived split, until a second real
implementation actually needs one). Where real functionality exists, it
lives in the concrete module named below, tracked on that module's own
row elsewhere in this document — not as a literal `Fl_X11_*`/
`Fl_Xlib_*`-class port.

| FLTK directory | Real functionality lives in | Status |
|---|---|---|
| `src/drivers/Base/`, `src/drivers/Posix/`, `src/drivers/Unix/` | (shared base/POSIX/X11+Wayland helper classes) | Not started — no consumer besides the concrete modules below |
| `src/drivers/X11/` | `fl.platform_x11` (screen/window driver) | See `FL/x.H`+`FL/x11.H`'s row above |
| `src/drivers/Xlib/` | `fl.draw` (rect/color) + `fl.xft` (text) | See `FL/fl_draw.H`'s row above |
| `src/drivers/OpenGL/` | `fl.gl_graphics_driver` + `fl.gl_display_device` | Partial — see below |
| `src/drivers/PostScript/` | `fl.postscript` + `fl.printer` | See `FL/Fl_PostScript.H`'s/`FL/Fl_Printer.H`'s rows above |
| `src/drivers/SVG/` | `fl.svg_file_surface` | See `FL/Fl_SVG_File_Surface.H`'s row above |
| `src/drivers/Wayland/`, `src/drivers/Cairo/` | — | Not started — primary target (Linux), not yet begun |
| `src/drivers/WinAPI/`, `src/drivers/GDI/` | `fl.platform_win32` (screen/window driver) + `fl.gdi_graphics_driver`/`fl.gdiplus_graphics_driver` (drawing) | See `FL/win32.H`'s row above |
| `src/drivers/Cocoa/`, `src/drivers/Quartz/`, `src/drivers/Darwin/` | — | Not started — out of scope for testing (no macOS hardware), driver abstraction left open for it |

### `src/drivers/OpenGL/` — `Fl_OpenGL_Graphics_Driver` / `Fl_OpenGL_Display_Device`

**Status:** Partial — `fl.gl_graphics_driver` (+ `fl.gl_display_device`)

`GlGraphicsDriver` extends `fl.graphics_driver.GraphicsDriver` as its
third real consumer (alongside `fl.svg_file_surface`/`fl.postscript`) —
color/rect/line/polygon, line style, clipping (`glScissor()`-based, no
need to reproduce FLTK's own rectangle-intersection stack since
`fl.draw.pushClip()` already hands over the final, already-intersected
rectangle), arcs/pies, the full vertex-path family, and real text (via
`fl.gl.gl_draw()`) and image drawing (via `fl.gl.gl_draw_image()`, needing
one real fix: a `glPixelZoom(1,-1)` bracket to counter `glDrawPixels()`'s
own upside-down row order versus this port's top-down `RGBImage.array`).

Differences from FLTK:
- `drawImage()` forwards to the already-ported, *uncached* public
  `gl_draw_image()` (`glDrawPixels()`-based) instead of FLTK's own
  persistent `GL_TEXTURE_RECTANGLE_ARB` texture cache keyed off a live
  image — correct and a non-issue for this port's own repaint cadence
  (resize/reload, not a continuously-animating scene); a real cache would
  only be worth adding for a future consumer that redraws the same image
  every frame.
- `drawBitmap()` (the 1-bit `Bitmap`/XBM stencil path) is real, the same
  uncached-simplification family as `drawImage()` above rather than FLTK's own texture-cache route
  (`bitmap_to_rgb1()`/`compute_texture_rectangle()`/`image_texture_map_`):
  builds a full RGBA buffer (current color, alpha 255/0 for set/clear
  bits) fresh per call and draws it via the same `gl_draw_image()` path,
  leaning on real GL alpha blending (already enabled globally for GL
  compositing) rather than a cached alpha-only texture. `w`/`h` (the
  requested destination size) aren't consulted — no GL-side stretch
  primitive exists here the way `fl.gdi_graphics_driver.
  GdiGraphicsDriver.drawBitmap()`'s real `StretchBlt()` has — so the
  buffer draws at its own native pixel size; `cx`/`cy` are honored as a
  real position offset.

Missing:
- `draw(int angle,...)` (rotated text) — no consumer.

## Fluid (the UI designer / D-source exporter)

FLTK's `fluid/` is a full application, not a single file — tracked here
per subdirectory, matching FLTK's own layout. The binary is `fluid`
(`dub build fldtk:fluid`), following FLTK's real SYNOPSIS in spirit:
bare `fluid [file.fl]` opens the interactive editor; `-c [-o out.d]`
selects headless `.fl → .d` code generation instead of a header-filename
flag (this dialect emits a single D source file per project, so there's
no header/`.cxx` split for `-h` to name — `-h`/`--help` print usage
instead, the near-universal convention for that letter).

**Both the headless code generator and the interactive GUI editor exist and
work.** The headless path (`fluid -c`)
reads a `.fl` project and emits D source that compiles clean and matches
a hand-transliterated reference file property-for-property. The
interactive editor renders a project's widget tree with real, live `fl.*`
widgets in a real window, supports click-to-select (synced with a
tree-based node browser), a full property panel, a widget-creation
palette (including real drag-and-drop from a literal, geometry-faithful
port of FLTK's own Tools window), mouse-driven move/resize, alignment/
distribution commands, undo/redo, and save-back-to-`.fl`.

**Deliberate dialect differences from FLTK's own generated C++**, true
throughout every node/writer below:
- **No header/`.cxx` split** — one D source file per `.fl` project,
  matching every hand-transliterated sample in this project's own
  `source/test/` and `source/examples/`.
- **No callback-trampoline-plus-cast machinery** — FLTK's generated code
  needs `static void cb_x(Fl_Widget*, void*)` free-function trampolines
  purely because C++ callbacks are plain function pointers; this port's
  writer emits a plain delegate literal inline instead, per `CONVENTIONS.md`'s
  callback convention.
- **A real tree** (`Node.children`, a plain array with real `parent`/
  `children` links) instead of FLTK's flat doubly-linked list plus an
  integer nesting level — a C-era space optimization with nothing to
  carry over, since every consumer here only ever needs child/parent
  access.
- **GNU-style `.fl`-text output**, not a byte-for-byte match of FLTK's own
  formatting quirks — there's no legacy `.fl`-authoring tooling or
  backward-compatibility obligation forcing this project's own writer to
  match FLTK's habits. Every node's property group and children group each
  open with a `{` on its own line, one indent level deeper than the `Type
  name` header, contents one level deeper still, closing `}` aligned with
  its `{` (`ProjectWriter.writeNode()`; `parent_properties` and the
  `shell_commands`/`snap` option blocks likewise). The
  reader is whitespace-insensitive, so K&R-style `.fl` files (FLTK's own,
  and this repo's older hand-authored ones) still load and are normalized
  on the next save.
- **Save As appends `.fl`** when the typed name doesn't already end in it
  (`fluid.path_util.ensureFlExtension()`, case-insensitive, so `example` →
  `example.fl` and `example.fl` never becomes `example.fl.fl`); FLTK's
  Fluid writes the chooser's result verbatim. Because the chooser's own
  "replace?" prompt ran against the name as typed, an appended name that
  collides with an existing file gets its own confirmation.
- The bare Options flag `use_FL_COMMAND` is real (`fluid.project_settings.
  ProjectSettings`, `Reader.settings`, written back by `ProjectWriter`):
  generated widget and menu-item shortcuts are written symbolically
  (`stateCtrl|'s'`), with `stateCommand`/`stateControl` names when the
  flag is set (a deliberate fix of FLTK's Ctrl/Meta swap on non-macOS
  platforms, see `FLTK_ISSUES.md`). The other bare header-file flags
  (`do_not_include_H_from_C`, `utf8_in_src`, `avoid_early_includes`) are
  parsed and dropped.
- `mergeback 1` (Options block) turns on MergeBack, see the
  `mergeback.h`/`.cxx` row below: `ProjectWriter` then writes every
  node's `uid` (after `ensureUniqueUids()`) and `Writer` emits tag
  lines around editable blocks.

**Code-block structure: kept close to FLTK, under review for D.**
Fluid's per-widget code slots (`declare`, `setup`, `final`, `callback`,
`import`) and its `decl`/`declblock`/`class`/`Function`/`code`/`codeblock`
nodes keep FLTK's structure on purpose, so `.fl` files, the node model and
the panels stay comparable with FLTK's own. That structure is organized
around what C++ needs: separate header and source files, and
declaration-before-use. Of the five per-widget slots only `setup` and
`callback` are stored (`WidgetNode.setupCode`/`callback`), written to the
`.fl` file and generated; the panel's `import`, `declare` and `final` pages
are not stored anywhere, so what is typed there is ignored (their tooltips
say so). D needs neither, so some of it is redundant and
some of its vocabulary clashes with D. These differences are being
weighed, and none of them has been changed yet:
- **`final`** is a D keyword with an unrelated meaning. The slot runs
  code after a widget and all its children exist, so `before`/`after`
  (paired with today's `setup`) would describe it better than
  `setup`/`final`.
- **`declare`** exists in FLTK to place a declaration in the right file.
  Generated D has one file and no ordering constraint, so a declaration
  lands in the same place as `setup` code and the slot may be obsolete.
  The same applies to the `in header`/`in source` controls on
  `decl`/`class`/`Function` nodes, which carry no meaning in D output.
- **`import`** is written once near the top of the generated file, but
  the property panel places its button after `// comment`. Left of
  `// comment` would follow the order things appear in the output.

### Deliberately not ported

Fluid features and FLTK Fluid behavior that this port leaves out on purpose.
None of them is waiting on work.

- **Internationalization support code** (GNU gettext and POSIX catgets).
  D and fldtk handle UTF-8 natively, so there is no `fl.gettext` module and
  no catgets binding. The Locale tab shows the "GNU gettext" and "POSIX
  catgets" choices inactive. A project file that already selects one still
  round-trips and generates the `import` and the wrapped label/tooltip
  calls, but the developer supplies the module named in the Import field.
- **The `.fd` (fdesign) file format.** Every `.fl` file here is the modern
  format.
- **Rebuilding `fluid` when its help-page chart changes.** `buildfluid.d`
  rebuilds when a `.d` file changed, so an edit to
  `documentation/fluid_flow_chart_paths.svg` needs a touched `.d` file or a
  deleted `./fluid` to be picked up. The file practically never changes.
- **C/C++ header-file settings**: Header File, Include Header from Code,
  Include Guard, Allow Unicode UTF-8 in source code, and Avoid early include
  of Fl.H. They gate mechanisms D has no equivalent of; the matching `.fl`
  options are parsed and dropped.
- **`-h header-filename`** on the command line: generated D has no header
  file to name, so `-h`/`--help`/`-help` print usage. `-d` (external editor
  tracing) and `--autodoc` are not ported either.
- **`autodoc.h`/`.cxx`**, an internal tool for FLTK's own documentation
  screenshots, and **`ExternalCodeEditor_WIN32`**, which is Windows-only.

### `fluid/Fluid.cxx` / `.h`, `fluid/main.cxx` / `.h`

**Status:** Partial — `source/fluid/app.d` (headless CLI) +
`source/fluid/gui_main.d` (interactive shell)

Not a literal port of FLTK's own `Application` class (which owns undo/
i18n/layout-preset/external-editor state as one object) — `app.d` is the
headless `.fl → .d` driver; `gui_main.d`'s `runEditor()` is the
interactive shell: one menu-bar+browser "shelf" window, matching FLTK's real proportions, not FLTK's fuller
`Application` object model. Several of FLTK `Fluid.cxx`'s pieces are
covered under a different name: `confirmDiscardChanges()` ≈
`confirm_project_clear()`, ad-hoc per-panel `Preferences`-based position
saves ≈ `position_window()`/`save_position()`, immediate-apply property-
panel fields ≈ `flush_text_widgets()` having nothing to flush. Genuinely
inapplicable: Layout Presets, Mac-specific bits, the
header/`.cxx`-split settings (no such split in this dialect). The
`&Edit` menu's Cut/Copy/Paste/Duplicate/Select All/Select None entries
are all real (`cutSelected()`/`copySelected()`/`pasteFromClipboard()`/
`duplicateSelected()`/`selectAll()`/`selectNone()`; Select All/None walk
outward from the current selection's parent as FLTK's do, scoped to the
canvas's window while a canvas runs the command, FLTK's `in_this_only`), via an in-memory
`clipboardText_` (real `.fl` text) rather than FLTK's own `cutfname()`
temp file. **Sort/Earlier/Later/Group/Ungroup and `show_help()`** are real —
`sortSelectedCmd()`/`earlierSelectedCmd()`/
`laterSelectedCmd()` (`fluid.node_order`, ported from `Widget_Node.cxx`'s
`sort()` and `Node.cxx`'s `earlier_cb()`/`later_cb()`) and
`groupSelectedCmd()`/`ungroupSelectedCmd()` (`fluid.group_ungroup`,
ported from `Group_Node.cxx`'s `group_cb()`/`ungroup_cb()`) both build on
two new `Node` primitives, `prevSibling()`/`nextSibling()`/`moveBefore()`
(`fluid.node`) — trivial here since this port's `Node` is a real tree
(`children`, a plain array) rather than FLTK's own flat doubly-linked
list plus an integer nesting `level`. On a menu item, Group/Ungroup
group the selected items into a new submenu after the current item, or
move them out of their submenu to just before it (deleting the submenu
once empty) — `group_selected_menuitems()`/`ungroup_selected_menuitems()`
from `Menu_Node.cxx`, as `groupSelectedMenuItems()`/
`ungroupSelectedMenuItems()`. FLTK's
`Fluid.proj.tree.allow_layout` gate around `Flex`/`Grid` relayout is
`ProjectCanvas.allowLayout` (see the `Menu.cxx` entry's "Synchronized
Resize"); these three commands call the relayout unconditionally, which
matches FLTK's own *effective* behavior at exactly these call sites
regardless of that toggle's state.
`fluid.flex_node.FlexNode.fixedSizeTuples` (positional child indices)
needs re-anchoring after any of these five reorder a `Flex`'s own
children, or a saved project would silently apply a fixed size to the
wrong child — `fluid.flex_node.reindexFlexIfNeeded()`, called from both
new modules right after every child-order/-membership change, handles
it (`fluid.grid_node`'s own per-child cell placement is keyed by `Node`
identity instead, immune to this). `show_help()`
(`gui_main.d`'s `showHelp()`) wires up `&Help/&Rapid development with
FLUID.../&FLTK Programmers Manual...` via `fl.help_dialog`, falling back
to `fl.openUri()` for the "index.html" case exactly like FLTK's own
`fl_open_uri()` call. Its canned "fluid.html" page describes the D
workflow and shows a D flow chart in place of FLTK's C++ one
(`source/fluid/documentation/fluid_flow_chart.svg`, embedded as an SVG
with its text converted to outlines, `fluid_flow_chart_paths.svg`, since
`fl.nanosvg` draws no text): one generated `.d` module with
images and data embedded, imported by the user's own modules, compiled
and linked with `libfldtk` in one step, and MergeBack's path back into
the `.fl` file. Cut/Copy/Duplicate/Paste/
Delete reach a selected top-level Code-group node (`Function`/`decl`/
`comment`/...) too: `topLevelSelection()` doesn't exclude every node
with `n.parent is null`, and selecting such a node in the browser doesn't
zero `activeWindow_`/the active canvas (a Code-group node has no
enclosing `WindowNode` to resolve one from, so `ProjectCanvas.selected()`
alone would never see it). `allSelectedNodes()` merges the canvas's own
click-ordered selection with the node browser's own authoritative one,
and `pasteFromClipboard()`'s *target*-selection logic resolves the paste
anchor from both, treating a top-level Code-group node as a valid paste
target (see that function's own doc comment). **`print_snapshots()`** is real —
`gui_main.d`'s `printSnapshots()`, wired to `&File/&Print...`. It is built
entirely on `fl.printer.Printer` (the real interactive print dialog) and
`fl.paged_device.PagedDevice.printWindow()` (a real port of
`Fl_Paged_Device::print_window()`, itself a synonym for
`drawDecoratedWindow()` — captures the title bar too, not just widget
content). Prints one page per currently-*shown* design window
(`findAllWindowRoots(projectRoots_)` + a `canvases_` lookup, the same
Node-to-live-canvas mapping `saveAsTemplate()` above already uses),
each scaled down — never up — to fit the page and centered, with a
date/time, page-count, and project-basename header line, matching
FLTK's own layout exactly.

### `fluid/Project.cxx` / `.h`

**Status:** Partial — spread across `source/fluid/project_reader.d`
/ `project_writer.d` / `gui_main.d`

The narrower "read one `.fl` file into a tree, save it back out" piece is
real and complete (see `fluid/io/`'s row). FLTK's own full editing-*
session* model (dirty tracking beyond a single undo stack, multi-file
project state, project-relative-path resolution as a first-class object)
isn't ported as a distinct class — the pieces that exist live directly on
`gui_main.d`'s own state instead, and `dirty_`/`updateShelfTitle()`
together already cover what `set_modflag()` does.

### `fluid/nodes/` (28 files)

**Status:** Partial — `source/fluid/*_node.d`

Every node kind any real `.fl` file in this project's own `source/test/`/`source/examples/`/
`source/fluid/panels/`/`source/fluid/templates/` needs is ported: `Node` (base:
label/callback/user_data/comment/open/selected), `WidgetNode` (the
workhorse — covers the property set nearly every simple leaf widget
needs with no further subclass at all, confirmed against FLTK's own
source: only 19 of its own node classes override read/write behavior
beyond the equivalent base class), `WindowNode` (modal/xclass/noborder/
size_range, container support), `GroupNode`, `GridNode`/`FlexNode`,
`MenuOwnerNode`/`MenuItemNode`, `ClassNode` (a genuine base-class
relationship only — a base-less `class Name {}` flattens directly in the
`.fl` source instead), `WidgetClassNode` (generates a real D `class Name
: BaseClass` with named children as fields, rather than a factory
function), `CodeNode`/`DeclNode`/`DataNode` (raw code/declaration/binary-
asset fragments), `CodeBlockNode`/`DeclBlockNode` (wrap their own
children — a widget tree/`code {}` mix for the former, `decl {}`/`data
{}`/another nested `declblock {}` for the latter — in a "before"/"after"
pair of literal D text; see `fluid.decl_block_node.DeclBlockNode`'s own
doc comment for one deliberate divergence: unlike FLTK's own
`DeclBlock_Node`, which emits its before/after text completely raw
since its own default content is a bare `#if`/`#endif` pair needing no
braces, this port's version injects real braces and indents its
children — confirmed necessary, not just simpler, since D's own nearest
equivalent conditional-compilation constructs, `version()`/`static if`,
need real braces the `.fl` grammar's own per-value balanced-brace
requirement makes impossible for the `.fl` author to supply directly),
`FunctionNode` (top-level `main()`, both named-Function shapes, and
a class's own constructor/destructor/methods), and `CommentNode` (a
standalone project-tree comment entry — `in_h_`/`in_c_` real fields,
round-tripped through `project_writer.d` — distinct from every node
type's own generic `comment` property, matching FLTK's own
`Comment_Node : Node` — the generic `Node` fallback `fluid.factory`
wires every other unrecognized node kind to does not represent this
one correctly, which is why it has its own real class).

A widget's `type` property is resolved per widget kind
(`fluid.subtypes`, ported from `Widget_Node::subtypes()` and its
`*_type_menu[]` tables): buttons, Pack, Flex, Scroll, sliders,
scrollbars, rollers, Input, Output, Spinner, Counter, Dial, Browser and
MenuButton have a table, and the widget panel's Subtype choice edits it.
Windows (Single/Double picks `Window` or `DoubleWindow`, and the
`Fl_Double_Window` node type means the same), menu items (Normal/Toggle/
Radio is the node kind `MenuItem`/`CheckMenuItem`/`RadioMenuItem`) and
menu bars (`type Fl_Sys_Menu_Bar` picks `SysMenuBar`) have tables too,
but keep the choice in the class or node kind instead of a `type()`
value; `widget_class` has none, as FLTK. `WidgetNode.access`
is FLTK's `public_`: the bare flags `private`/`protected` in the `.fl`
file, emitted as a protection attribute on a class field and as `private`
on a module-level variable. `FunctionNode` has the same `access` plus
`declareC` (the `.fl` flags `private`/`protected`/`C`): a method gets a
protection attribute, a plain function `private` (FLTK's `static`)
and, with `declare "C"`, `extern (C)`. `ClassNode.prefix` is FLTK's
`Class_Node::prefix()`, the extra word before a class's name in the `.fl`
file (`class final Foo {`); C++ puts it after `class`, D puts attributes
before it, so it is emitted as `final class Foo`, and the panel's
Attribute field edits it. An inline-data node with no filename generates
an empty array, and one whose file can't be read generates
`static assert(false, "Can't include data from file. Can't open ...")`
in place of FLTK's `#error` line; Write Code also alerts it, and
`fluid -c` prints it as `FLUID ERROR:`, as FLTK does.

Differences from FLTK:
- `DataNode`'s storage format is two independent flags (`asString`,
  `compressedFlag`) instead of FLTK's 6-value `output_format_`
  enum — the raw-array-vs-`std::vector` axis FLTK's own choice
  bundles in has no D equivalent (a `ubyte[]`/`string` already is what
  `std::vector` reaches for) and collapses away entirely; text-vs-binary
  and compressed-vs-not are both real, ported, and freely combinable
  (unlike FLTK's own menu, which has no "compressed text" entry at
  all). `.fl`-text round-trips via FLTK's own `textmode`/`compressed`
  bare-flag spellings, which are not mutually exclusive; `std_binary`/
  `std_textmode`/`std_compressed` are still accepted on read (for a
  real FLTK-authored file) but never written. The property panel's
  "Storage Format:" group (renamed from FLTK's "Output:") exposes
  both.
- Grid child-cell placement (`location`/`colspan`/`rowspan`/`align`/
  `minsize`) needed a genuinely new mechanism, `parent_properties`: the
  reader threads the in-progress parent `Node` through its own recursive
  descent so a child's property block can be interpreted by its parent
  (`GridNode` is the only real consumer so far).
- On the canvas a `Grid` is a `fluid.grid_proxy.GridProxy` (FLTK's
  `Fl_Grid_Proxy`): selecting it, or dragging one of its children, draws
  the row/column cell lines in the overlay (`drawOverlay()`).
  Edits on the Grid and Grid Child tabs reach the live grid through
  `fluid.instantiate.syncLayoutToLive()`: changing a child's row, column,
  span, alignment or minimum size moves it within the grid (as FLTK's
  `grid_child_cb()` does), and the node is set to what the grid accepted.
  A `Flex` child's rectangle likewise belongs to the flex layout, and
  editing a flex or its children's fixed sizes re-applies them to the
  live flex (`syncFlexToLive()`).
  Dragging, resizing or arrow-keying a grid or flex child on the canvas
  hands it to its container (`fluid.layout_edit`: a grid child moves to
  the cell under the pointer or one cell per arrow key, a resized one
  updates its cell's minimum size; a flex child moves to the nearest
  slot or one place per arrow key, a resized one gets a fixed size), as
  `Window_Node::moveallchildren()` does. The node model follows the
  live container (`syncLayoutFromLive()`): each child's rectangle, a grid
  child's cell, a flex's child order and fixed sizes. That runs after
  inserts, paste and duplicate (a pasted grid child takes the next free
  cell), panel edits, drags, and before the project is saved or code is
  generated, so the saved rectangles are the laid-out ones, as in FLTK.
- On the canvas a `Scroll` is a real, scrollable
  `fluid.scroll_proxy.ScrollProxy`, where FLTK builds a plain `Fl_Group`
  because a scrolled `Fl_Scroll` shifts its children's coordinates. A node
  stores the unscrolled coordinate and a live child sits at `node - scroll
  position`; `fluid.instantiate`'s `scrollOffsetAbove()`/
  `scrollOffsetWithin()`/`geometryFromLive()`/`syncDescendantsFromLive()`
  convert wherever live and node coordinates cross (drag and nudge commit,
  `syncLayoutFromLive()`, `applyProperties()`, the Align/Space commands,
  adding a widget, the property panel's X/Y/W/H fields and formula
  variables). Moving or resizing any container writes its descendants'
  geometry back to their nodes. `ScrollProxy` repaints the whole canvas
  window on every scroll, since `Scroll`'s copy-and-patch scrolling would
  drag the canvas's background pattern and container outlines along with
  the children. Rebuilding the canvas from the nodes (undo, reload) resets a
  Scroll to position 0.
- A `widget_class` with `position_relative`/`position_relative_rescale`
  ends its constructor with `position(x, y)`/`resize(x, y, w, h)`, as
  FLTK's does, so the class is placed where its caller asks (the
  property panel's Grid tabs depend on this to sit inside the tab bar).
- `Image_Asset`'s embedding logic matches FLTK's own dispatch order
  exactly: `Pixmap`-shaped decodes (XPM, GIF) and `Bitmap`-shaped decodes
  (XBM) always embed via their native in-memory form regardless of the
  `compress` flag; everything else embeds compressed bytes when `compress`
  is set, or a decoded RGB buffer otherwise. `bind_image`/`bind_deimage`
  (ownership transfer) and `scale_image`/`scale_deimage` are both real,
  round-tripped, and consumed by both codegen and the live canvas —
  `Widget.bindImage()`/`bindDeimage()` are a complete port of FLTK's own
  image-ownership methods. Codegen and the live canvas both apply
  `scale_image`/`scale_deimage` through the same `fl.image.Image.scale()`,
  so a widget's icon has the same size while editing as in generated code.

Missing:
- `Image_Asset_Map`'s weak-reference decode cache — not needed yet, since
  nothing here shares one decoded image object across multiple nodes.

**Image Options dialog**: the property panel has its own UI for `compress`/
`bind`/`scale`. `panels/widget_panel.fl`'s `makeImagePanel()`/
`propagateLoadImagePanel()`/`runImagePanel()` (the "..." button next to
the Image/Inactive-image fields) is a complete, real "Image Options"
dialog: `imagePanelImageW`/`imagePanelImageH` (`scaleImageW`/
`scaleImageH`, plus a Reset button), `imagePanelConvert`
(`compressImage`, inverted — the checkbox reads "convert to raw pixel
data"), and `imagePanelBind` (`bindImage`), each
with a real callback writing straight to the selected `WidgetNode`s,
plus the same three for the inactive/"deimage" side
(`imagePanelDeimageW`/`H`/`imagePanelDeconvert`/`imagePanelDebind` →
`scaleDeimageW`/`H`/`compressDeimage`/`bindDeimage`). One disclosed
simplification: the scale-width/height fields write straight to the
node but don't re-scale a live `Fl_Image` or trigger a redraw (no live
widget to reach from this dialog) — the dimension readout itself is
real, loading the image file via `SharedImage.get()` to report its
natural size.

### `fluid/io/`

**Status:** Complete — `project_reader.d` / `code_writer.d` /
`project_writer.d` / `string_writer.d` / `file_chooser.d`

This is the D-source-export path central to this project's stated goal.
`project_reader.d` (tokenizer + recursive tree builder, grounded directly
in FLTK's own documented `.fl` escape rules — `\n\t\r\a\b\f\v`, `\xHH`
hex, `\NNN` octal, line-continuation, comment handling) and
`code_writer.d` (tree → D source) form the headless codegen path.
`project_writer.d` (tree → `.fl` text, needed for the interactive editor's
Save) round-trips every field the reader recognizes, verified via a real
headless load→save→load unit test. `string_writer.d` exports every
widget label/tooltip as a flat i18n text catalog (`.txt`/`.po`/`.msg`).
`file_chooser.d` is the shared file-picker wrapper every Fluid dialog
funnels through.

- `string_writer.d`'s escaping is byte-for-byte, not codepoint-for-
  codepoint, faithfully matching an FLTK limitation FLTK's own doc
  comment already acknowledges but hasn't fixed.
- `file_chooser.d`'s error-outcome parameter is accepted for API parity
  but unreachable — faithful, not a gap: FLTK's own
  `Fl_Native_File_Chooser_FLTK_Driver::show()` never produces its `-1`
  error case either, and its own private `errmsg()` setter is never
  called anywhere in that file. Both `-1`/`errmsg()` only become real once a GTK/Kdialog/Zenity
  backend exists to have an actual OS-level failure to report — see
  that row under "Browsers, trees, tables, file choosers" for the
  already-tracked "Deferred" status of those backends.
- **`code_writer.d` emits a widget's `.callback(...)` assignment before
  its `setup{}` code**: a `setup{}` block calling `o.doCallback()` (an
  idiomatic way to apply a widget's initial value by re-running its own
  callback) must invoke the widget's real callback, not whatever callback
  happened to be set earlier. `test/tree.fl`'s "Selection Mode" `Choice`
  is the example: its `setup{}` `doCallback()` must reach the real
  callback so the tree takes the dropdown's initial choice instead of
  staying at its class default `selectSingle`. Changing this ordering
  changes generated output, so `panels/generated/*.d` and
  `test/generated/*.d` must be regenerated, not just recompiled.

### `source/fluid/panels/` (10 `.fl` files)

**Status:** Real and live. `source/fluid/panels/widget_panel.fl` (plus its two
embedded sub-panels, `source/fluid/panels/widget_panel_grid_tab.fl`/
`widget_panel_grid_child_tab.fl` — each defines a `widget_class`
[`GridTab`/`GridChildTab`] under a different name than its own file;
`widget_panel.fl` imports each one explicitly by its real file name)
is FLTK's own real widget-
properties panel, converted in full to this project's own flat,
`Function`-based D dialect — the same shape every other converted panel
in this project uses, no class at all. All three files generate via
`fluid -c`, compile together cleanly against every real library this
port has, and are what `gui_main.d` actually imports and drives
(`make_widget_panel()`, `load()`, `current()`, `refreshCodeFromNode()`,
`wireEditHooks()`, the `onBeforeEdit`/`onEdited`/`onOpenExternalEditor`
delegate hooks, `overlayCb`/`okCb`/`liveModeCb`/`thePanel`/`widgetTabs`)
— there is no hand-written property-panel class anywhere in the live
app any more. `liveModeCb` (Live Resize — a standalone, genuinely
resizable duplicate of the selected widget-tree node, verifying real
`resizable()`/layout behavior the design canvas itself deliberately
never reflows during editing) is real too, via `fluid.instantiate.
instantiateStandalone()`; `overlayCb` forwards to the already-real
`toggleOverlays()`; `okCb` closes the panel (every field in this
dialog already applies its own edit live, unlike FLTK's own
"apply everything on OK" sweep), after FLTK's `c_check()` bracket/quote
balance check of the widget's code, callback and user data
(`fluid.code_check`, extended for D's backtick/`r"..."` strings and
`/+ +/` comments): an unbalanced one reports "Error in code/callback/
user_data: ..." and keeps the panel open. An image file that can't be
opened or decoded is reported with FLTK's "Can't open image file" /
"Can't read image file" messages, once per path per loaded project.
`rdmd buildfluid.d` regenerates all three files like every other panel,
no exclusions. The one remaining difference from FLTK's dialog is that
the design canvas always shows a plain window and menu bar whichever
Single/Double or `Fl_Sys_Menu_Bar` choice is made. The conversion needed a
real `code_writer.d` addition for the Grid sub-panels (`widget_class` support
for `decl {}` fields and `Function {}` methods, alongside the
constructor-body widget tree it already supported). Edits made in the
dialog apply to every selected node, as FLTK's do.

FLTK's generic `propagate_load()`-with-sentinel-pointer callback
convention isn't ported: the panel refreshes itself through `load()`,
which calls one `propagateLoad*()` function per page (widget, function,
class, decl, data, comment, code and so on), and every field's callback
stores its own value.

Several of FLTK's own Fluid-app resource files (not test samples — Fluid's
*own* UI, `source/fluid/panels/`+`source/fluid/templates/`+`fluid_icon.fl`) are ported
as real `.fl` files run through this project's own code generator:
`fluid_icon.fl` (app icon), `fldtkLicense.fl` (the bundled
project template), `about_panel.fl`, `template_panel.fl` ("New from
Template", shared with `&File/Save As &Template...`, see `fluid/app/`'s
`templates.h` entry), `codeview_panel.fl` (Source/Project tabs, Find, and node↔text-
position sync all work — selecting a node in the widget editor or the
project tree pans both text views to that node's own generated block
and highlights it, matching FLTK's click-a-widget behavior; the
Auto-Position toggle, the reduced 3-entry code-choice dropdown
(instantiate/setup/finalize — no "prolog"/"static", neither of which
applies to this dialect's single-file, no-separate-declaration-phase
generator), and the "Reveal" button (text position → Node, wired back
into `gui_main.d` via the `cvOnReveal` delegate) are all real too. No
Header/Strings tabs, since neither applies to this dialect. The
Auto-Refresh light button is real: `gui_main.d` calls a shared
`codeviewAutoRefresh()` from every one of its own project-mutating
entry points (in place of FLTK's single `codeview_defer_update()`
call site inside `Project::set_modflag()`, which this dialect has no
equivalent centralized hook for), and unchecking it stops those
calls from refreshing (with the button on, each call site refreshes
whenever the panel is visible). No debounce timer, unlike FLTK: each call
site already fires at most once per discrete edit, not once per drag
frame, so there's nothing to coalesce. The plain "Refresh" button stays
unconditional either way, and re-applies the current selection's
highlight on every refresh so it's never lost), and `settings_panel.fl` (all six of FLTK's
tabs are placed at FLTK's own exact 360x585 dialog size and per-
widget coordinates, including real tab icons in `source/fluid/panels/
pixmaps/`). General and Locale tabs are fully functional; Shell
keeps its pre-existing real wiring (`source/fluid/shell_settings.d`),
repositioned into FLTK's narrower single-column layout; Project's
Code File field is wired (`gui_main.codeFileName()`, round-tripped
through the `.fl` file as a real `code_name` Option, the interactive
equivalent of `fluid -c -o`) while Header File/Include Header from
Code/Include Guard, plus (inapplicable, not just deferred) Allow Unicode UTF-8 in source code/
Avoid early include of Fl.H, were dropped outright rather than left
unwired — all five gate a mechanism with no equivalent in this
dialect's single-generated-`.d`-file model at all (C/C++ header-file
concepts, or C-string-literal-escaping/textual-`\#include`-ordering
concerns D's own module system and UTF-8-native source don't have),
not just a missing backing subsystem. **Layout and User are both fully
wired:** Layout backs `fluid.layout_suite`'s real named-suite
persistence; User drives all 12 of `fluid.node_browser`'s per-role
tree-row color/font fields, including the row-kind-specific ones
(`func`/`code`) that only became visible once `NodeBrowserItem`'s own
row-shape dispatch existed (see the `fluid/widgets/` row further down).
FLTK's custom
Fluid-app `@fd_beaker`/`@fd_user`/`@fd_project`/`@fd_file`/`@fd_zoom`
glyphs are registered `fl.symbols` glyphs (`fluid.pixmaps`) and used by
the storage menus, suite names and the big-editor button, and the Shell
tab's list shows a per-row storage icon (`Browser.icon()`).

### `fluid/proj/`

**Status:** Partial

- **`undo.h`/`.cxx`** — ported, deliberately divergent: in-memory `.fl`-
  text snapshots (via the already-real reader/writer round-trip) rather
  than FLTK's numbered-temp-file-on-disk approach, justified by this
  editor's own project scale. FLTK's `Undo::checkpoint(OnceType)` is
  ported as `gui_main.d`'s `checkpointOnce()`: a window resize drag sends
  many resize events and records one undo step (`OnceType.windowResize`),
  and any other checkpoint, undo or redo ends the run. Undoing or redoing
  a resize also restores the window's size on its canvas. The *Code* text
  editor's own equivalent problem (`panels/widget_panel.fl`'s
  `TextBuffer` modify callback firing per keystroke) has a separate
  coalescing mechanism instead (`fluid.edit_session`).
- **`align_widget.h`/`.cxx`** — ported faithfully (Align/Space Evenly/
  Make Same Size/Center in Group). Two FLTK quirks are faithfully
  preserved, not bugs: `BREAK_ON_FIRST` means "align to the first
  selected widget," not the most extreme one across the selection; this
  port's selection order is click-order, not document-tree order (only
  matters for which widget counts as "first").
- **`Image_Asset.h`/`.cxx`** — see `fluid/nodes/`'s row above (the actual
  code lives in `code_writer.d`/`widget_node.d`, tracked there).
- **`i18n.h`/`.cxx`** — ported as `fluid.i18n.I18nSettings`, with real
  parse/round-trip and real codegen consumption (labels/tooltips,
  including `MenuItem` labels, wrapped in a configured `gettext()`/
  `catgets()`-shaped call), plus the prologue: the include field is a D
  module name emitted as an `import`, inside `version (<conditional>)`
  with pass-through fallback functions in the `else` branch when a
  conditional is set (D has no text-substitution macros, so FLTK's
  `#ifndef gettext #define gettext(text) text` becomes an ordinary
  identity function). A C-style include from an FLTK `.fl` file is
  reported in a comment, not emitted. **Not applicable: gettext/catgets.** D and fldtk handle UTF-8 natively, so the project does not provide translation support: no `fl.gettext` module exists, and the Locale tab's "GNU gettext" and "POSIX catgets" choices are shown inactive. A project file that already selects one still round-trips and generates the `import` and wrapped calls, but the developer must supply the module named in the Import field themselves. Menu item label translation is deliberately *simpler*
  than FLTK's own mechanism, not a partial port of it: FLTK needs a
  two-phase `gettext_noop()`-at-declaration/`gettext()`-at-runtime dance
  purely because its `Fl_Menu_Item[]` is a real C static aggregate
  initializer that can't call a function; this port's generated
  `MenuItem[]` is always a plain local runtime array, so a single direct
  call at the array-literal element does the same job.
- **`mergeback.h`/`.cxx`** — ported as `fluid.mergeback` (`Mergeback`,
  `Crc32`, `formatTag()`), plus the `Code_Writer::tag()` half in
  `code_writer.d` and `ProjectSettings.writeMergebackData`. Status:
  Done. With the project flag on, `code_writer.d` brackets each
  `code {}` fragment, widget callback, menu-item callback and widget
  `setup` code with CRC-tagged `//` lines; `Mergeback.analyse()`/`apply()` recompute the
  CRCs from a generated file, report edits and copy edited blocks back
  into the matching nodes by `uid`. `&File/MergeBack Code` (visible
  only while the flag is on; interactive dialog with merge/cancel),
  merge-on-project-open and merge-on-app-activate
  (`Event.appActivate`, delivered on X11 under an EWMH window manager)
  are all wired in `gui_main.d`; the last code file written for
  a project is remembered (`rememberCodePath()`, also from `fluid -c`)
  so a build-step-generated file is found. Differences from FLTK:
  blocks keep their own indentation and are un-indented by the tag
  line's indentation rather than a fixed two spaces; `setup` code is
  written with the widget's own name in place of `o` and merged back with
  `o` restored; FLTK's `CODE0`/`CODE1`/`FINALIZE` tags have no
  counterpart because the panel's `import`, `declare` and `final` pages
  are not stored in the project; menu-item
  callbacks merge back (FLTK's `is_true_widget()` lookup rejects
  them, see `FLTK_ISSUES.md`). The headless entry points are
  `-m`/`--merge-back`, `-mb`/`--merge-back-if-safe` and
  `-mi`/`--merge-back-info` (`compile.d`'s `mergeBackProject()`; FLTK's
  `-mb=apply`/`-mb=info`, without its `-mb=ask`, which needs a dialog):
  they merge into the `.fl` file and save it (the info mode only
  reports), exit status 1 on an unreadable tag or an unsafe
  `--merge-back-if-safe` merge, and combine with `-c` to fold edits in
  before regenerating.

### `fluid/app/`

**Status:** Partial

- **`history.h`/`.cxx`** — ported as `project_history.d` (`History`), the
  recent-projects list, persisted via `fl.preferences`. Rebuilds the whole
  "Recent Files" menu section on each change rather than relabeling
  pre-allocated slots in place (this port's `Menu_` has no by-index
  relabel/hide primitive) — observably equivalent.
- **`args.h`/`.cxx`** — not ported as a literal `Args` class; this port's
  CLI is deliberately different (the editor opens unless `-c` asks for
  compiling). It is one `std.getopt` call (`compile.d`'s
  `parseCommandLine()`, shared by `fluid` and `fluid-bootstrap`) with
  `"short|long"` option strings, so `--help` lists every option from its
  description. Two FLTK flags mapped onto something real: `--strings` (with `-c`,
  i.e. `-cs`/`--compile-strings`: also write the i18n strings file) and `-u` (load,
  normalize, and resave a `.fl` file, keeping its shell commands and
  layout suites). The merge options are extra, see the
  `mergeback.h`/`.cxx` row. `-v`/`--version` prints the version. Not
  ported: `-pr` (output paths are always relative to the project file),
  `-d`, `--autodoc`. `-s <name>` (`--strings-file`) names the strings file
  written by `-cs`, or its extension when it starts with '.'. `-bg`/`-fg`/
  `--scheme`/`-sf` (`--scaling-factor`) are in the same table and style
  the editor; FLTK's other standard switches (`-geometry`, `-display`, ...)
  are handed to `fl.core.args()`.
- **`templates.h`/`.cxx`** — both halves are real: the load path
  (`template_panel.fl`'s dialog, `newFromTemplate()`) and `&File/Save
  As &Template...` (`gui_main.d`'s `saveAsTemplate()`, ported from
  `save_template()` — sanitizes the name, resolves the templates
  directory, writes the project via `ProjectWriter`, and captures a PNG
  preview via `fl.core.captureWindow()`/`fl.png_image.writePng()`).
  `template_panel.fl`'s row-to-file association uses `fl.browser.
  Browser`'s real per-row `data()`, matching FLTK's own
  `template_browser->data(item)` exactly.
- **`Menu.cxx`/`.h`** — not ported as a literal file; superseded
  piecemeal by `gui_main.d`'s own menu-building code, matching FLTK's
  real structure item-for-item.

  **Top level**: File, Edit, New, Layout, Shell, Help — no separate
  top-level View menu; the widget-bin/code-view toggles nest inside
  &Edit, matching FLTK's own placement.

  **&File**: order/shortcuts/dividers match exactly. Real: New, Open,
  Save, Save As, New From Template, Save As Template, Write Code
  (`writeCodeFile()`), MergeBack Code (hidden unless the
  project enables MergeBack), Write Strings, Print, Revert (FLTK's
  `revert_project()`), Insert (`merge_project_file()`: the file's nodes
  are placed as a paste would be, and the options it sets are applied to
  the open project; into an empty project it loads the file), Save a
  Copy (`save_project_file()` with `v == 2`), the recent-files list,
  Quit. Quit asks first while a shell
  command is still running, and every action that would drop unsaved
  changes asks FLTK's Cancel / Save / Don't Save question
  (`confirm_project_clear()`).

  **&Edit**: order/shortcuts/dividers match exactly. Real: Undo, Redo,
  Cut, Copy, Paste, Duplicate, Delete, Select All, Select None, Sort,
  Earlier, Later, Group, Ungroup, Hide Overlays (`toggleOverlays()`,
  shared with the Widget Properties panel's own button so the two
  triggers can't drift), Hide Guides, Hide Restricted, Show Widget Bin,
  Show Code View, Settings. The item names follow FLTK's menu text (as with `&New`'s
  `&Group` below): `&Delete`, not `&Delete Selected`, and `Show Widget
  &Bin...` (the window it opens is titled "Widget Bin" —
  `function_panel.fl`'s own `widgetbin_panel`), not `&Tools`. Properties (F1) opens the
  current node's editor, or says "Please select a widget"
  (`edit_selected()`).

  **&Layout**: Align/Space Evenly/Make Same Size/Center In Group are
  real and unchanged. Real: a nested `&Presets` submenu (a radio group
  dynamically rebuilt from `fluid.layout_suite.layoutList` itself —
  `gui_main.d`'s `rebuildLayoutMenu()` — so any suite the Settings
  dialog's Layout tab adds/renames/removes shows up here too, not just
  the two built-in "FLTK"/"Grid" suites) plus a separate flat
  `&Application`/`&Dialog`/`&Toolbox` radio triple (selecting the
  active preset *within* the current suite) — a slightly unusual
  structure: "Presets" is genuinely its own nested submenu, while
  "Application"/"Dialog"/"Toolbox" are flat *siblings* of "Presets"
  under &Layout, not nested inside it. Also real: "Grid and Size
  Settings..." opens the Settings dialog straight to the (fully
  wired) Layout tab,
  matching FLTK's own `show_grid_cb()`. **Synchronized Resize**
  is real (`fluid.canvas.ProjectCanvas.allowLayout` -- FLTK's own
  `tree.allow_layout` flag, gated per-canvas the same
  "one shared preference, every open canvas carries its own mirrored
  copy" way `showGuides`/etc. already work): interactively resizing a
  `Group`/`Window`-family widget only resizes/repositions its
  unselected children to match real runtime behavior when the toggle
  is on, matching FLTK's own default-off `Fl_Group_Proxy::resize()`
  gate. A plain move always drags children along regardless (matching
  FLTK's own separate, unconditional per-descendant translation),
  and `Flex`/`Grid` always self-layout on resize regardless too
  (matching FLTK's own forced bracket around exactly those two
  node kinds) -- both disclosed simplifications from FLTK's own,
  more involved `moveallchildren()` mechanism, documented on
  `allowLayout`'s own doc comment.

  **&New**: group order/names match `New_Menu[]` exactly (Code, Group,
  Buttons, Valuators, Text, Menus, Browsers, Other). `&Menus` has all 8
  of FLTK's real entries, and all 4 menu-item-editing leaves
  (Menu Item/Submenu/Checkbox Menu Item/Radio Menu Item) are real:
  `fluid.factory`'s registry has `"MenuItem"`/`"CheckMenuItem"`/
  `"RadioMenuItem"` (all plain `fluid.menu_item_node.MenuItemNode`s --
  see that class's own doc comment for why `CheckMenuItem`/
  `RadioMenuItem` don't need dedicated D subclasses the way FLTK's
  C++ factory dispatch requires; `mi.typeName` alone tells them apart)
  and `"Submenu"` (a real `SubmenuNode`, `canHaveChildren() == true` so
  its own nested `MenuItem`/`Submenu`/... children parse and can
  themselves be added under it). Non-widget nodes are placed by
  `gui_main.d`'s `placeNewNode()`, FLTK's `..._Node::make()` placement
  walk plus `Node::add()`: from the selection (as its last child if it
  can hold children, else right after it) climb to the nearest parent
  the new kind may live in (`acceptsNewNode()`: a menu item in a menu
  widget or submenu; Code in a Function, Code Block, Widget Class or
  group; Code Block, Comment in a code block; Window in a Function or
  Code Block; Function, Declaration, Inline Data, Declaration Block,
  Class in a Declaration Block or Class; Widget Class likewise but not in
  another Widget Class), inserting after the ancestor the climb passed
  through. Menu items, Code, Code Block, Window and widgets cannot be
  created without such a parent; instead of refusing, the node creation
  assistant (`assistNodeCreation()`, from FLTK's
  `Node::node_creation_assistant()`) asks whether to create the missing
  containers: a Function (or a method of the selected class) for Code,
  Code Block and Window; a Window, and a Function if needed, for a
  widget; a Menu Button (a Menu Bar for a submenu) with its Window and
  Function for a menu item. The whole assisted creation is one undo step,
  and declining creates nothing. The others go to the top
  level (after the selection's top-level node, or first in the project
  with nothing selected). Paste places each pasted node through the same
  walk (FLTK's `add_new_widget_from_file()`), widgets needing a group or
  window; a refused node is skipped. With nothing selected, Paste targets the active window. A new
  Widget Class gets a window's starting geometry (480x320, centered, as
  FLTK's `add_new_widget_from_user()` gives every window-shaped node) and
  opens its own canvas. New nodes start with FLTK's
  defaults: a widget gets the label its FLTK `..._Node::widget()`
  constructor passes (`instantiate.d`'s `defaultLabelFor()`), and a
  code-group node the name its `..._Node::make()` gives it, in D form
  (`defaultNameFor()`: `makeWindow()`, `writeln("Hello, World!");`,
  `if (test())`, `int x;`, `version (all)`, `myInlineData`, `my comment`,
  `UserInterface`). A user-created item is
  labeled "item" (a submenu "submenu"), as in `Menu_Item_Node::make()`,
  and a new `Menu_Button`/`Choice`/`Input_Choice` gets FLTK's starting
  label ("menu"/"choice:"/"input choice:"); an item-less `Choice`/
  `Input_Choice` shows FLTK's one-item "CHOICE" placeholder menu.
  `instantiate.d`'s `applyMenuItems()` is the port of `Menu_Base_Node::
  build_menu()`: it reruns whenever a menu item is added, deleted, or has
  a property edited in the Widget Properties panel (FLTK's
  `Widget_Node::redraw()` route), so the on-canvas menu never goes stale
  — `gui_main.d`'s `refreshLiveMenu()` (add/delete) and the panel's
  `refreshLiveMenuOf()` (edits) walk up to the nearest live
  `MenuOwnerNode` and rebuild it, clearing the menu once its last item is
  gone. An unlabeled item shows "(nolabel)" on the canvas and is
  generated with an empty label, since a null label marks the end of a
  menu array. Item flags cover value/deactivate/hide as well as
  divider/headline/submenu/toggle/radio, on the canvas and in generated
  code (`Menu_Item_Node::flags()`). Clicking an unselected menu widget on
  the canvas pops its menu up and selects the picked item's node
  (`Menu_Base_Node::click_test()`). Item shortcuts show in the canvas
  menu; the canvas window takes every shortcut itself and tests it only
  against Fluid's main menu (`ProjectCanvas.onShortcut`, from
  `Window_Node::handle()`'s `FL_SHORTCUT` case), and, like FLTK's
  `Overlay_Window::handle()`, keeps pointer-crossing and focus events
  from the design's widgets, so none of them can become the focus or the
  widget under the mouse and take a key from Fluid first. In the Widget
  Properties panel a menu item has FLTK's field availability: position,
  alignment, label margins, box, colors, text style, class and When are
  inactive; Down Box is active (FLTK's `Menu_Item_Node` is a
  `Button_Node`); Value (the item's checked state) and Shortcut are
  active except on a submenu, which also has no subtype. Clicking an
  unselected menu widget on the canvas runs its live menu: a picked item
  is selected and opened in the properties panel, as in FLTK's
  `Window_Node::handle()`.
  Every real *and* deactivated leaf item carries the same 16x16 icon the widget
  palette's own buttons use (`fluid.pixmaps.pixmapFor()`, via
  `fl.menu_.Menu_.multiLabel(int, MultiLabel)` — an accessor needed since
  this port builds its menus through `add()` rather than FLTK's
  direct `Fl_Menu_Item` array indexing), matching FLTK's own
  `fill_in_New_Menu()`/`make_iconlabel()` exactly, including the
  leading-space-plus-"..." text suffix (every real item already opens
  the Widget Properties panel right after creating its node, so "..."
  is meaningful here, not decorative). Deliberately *not* a plain
  `Menu_.image(int, Image)` (a real accessor too, kept for general use,
  but the wrong one for this): an `Fl_Menu_Item`'s own `image()` field
  falls back to `fl.widget.Label`'s default "image above text"
  stacking with no `alignImageNextToText` bit set, matching FLTK's
  own `fl_normal_measure()`/`fl_normal_label()` exactly — which is
  *why* FLTK's own `make_iconlabel()` reaches for an
  `Fl_Multi_Label` here instead of `Fl_Menu_Item::image()`:
  `Fl_Multi_Label`'s own `draw()`/`measure()` always lay their two
  parts out left-to-right. One remaining, deliberate text deviation:
  ordinary widget leaf labels use spaced words plus `&`-mnemonics
  ("Return Button") rather than FLTK's own literal auto-derived
  text (`fill_in_New_Menu()` strips `Fl_` off `type_name()` and uses
  what's left as-is — underscored, e.g. "Return_Button" — and
  FLTK's own `New_Menu[]` has no mnemonics at all, a flat ~50-item
  list where single-letter mnemonics would collide). Kept deliberately:
  it matches the mnemonic convention every other menu in `gui_main.d`
  already uses. Category *names* are not part of this exception — they
  match FLTK's own `New_Menu[]` strings exactly.

  **&Shell**: see `fluid/app/`'s own `shell_command.h`/`.cxx` row.

  **&Help**: order/names/divider match exactly. Real: &Rapid development
  with FLUID..., &FLTK Programmers Manual..., &About (all three via
  `showHelp()`/`showAboutPanel()` — see this file's own top comment for
  `showHelp()`'s writeup).

  `rebuildRecentFilesMenu()`/`rebuildShellMenu()` both locate the item
  to attach the divider before (`&Quit`/`&Customize...`) via
  `Menu_.add()`'s own return value, captured directly at the point the
  last item is added — not a `Menu_.findIndex(lastAddedPath)`-style
  text lookup, which would be ambiguous whenever two entries share
  display text (e.g. two different projects both named `test.fl` in
  different directories, or two shell commands sharing a label).
- **`Snap_Action.h`/`.cxx`** — real mouse-driven move/resize exists
  (drag-to-move, 8-direction drag-to-resize, undo-checkpointed), and
  the drag-time guide/alignment/grid-snapping rule engine is real too
  (`fluid.snap_action`): all 30 snap actions FLTK registers
  (`Snap_Action::list[]`) — window
  edge/margin, group edge/margin, tabs margin, sibling alignment, widget-ideal-size
  resize feedback, and window/group grid snapping (including the real
  grid-dot overlay drawn during a drag, `drawGrid()`) all snap and draw
  for real, gated by `ProjectCanvas.showGuides`. Inside a `Tabs`, the
  tabs margins replace the group margins. A menu item with an image shows it
  in its canvas menu, beside its label if it has one. Rubber-band multi-select and keyboard
  arrow-key nudge are both real (`fluid.canvas`'s `dragBox`/
  `finishBoxSelect()` and its `Event.keyDown` handling). One likely FLTK
  typo in the edge-clamping math is faithfully reproduced — see
  `FLTK_ISSUES.md`.
- **`shell_command.h`/`.cxx`** — ported in two pieces, matching the two
  distinct concerns the FLTK file itself mixes together. The
  process-spawning/output-streaming half (`Fl_Process`/
  `run_shell_command()`/`expand_macros()`/the `Fl::add_fd()`/
  `Fl::add_timeout()` wiring) is `fluid.shell_process` — `Fl_Process`
  itself wasn't ported, deliberately: it exists in C++ only to paper
  over a missing portable "run a command, get pipes" primitive, which
  `std.process.pipeShell()` already is. The named/savable command
  database (`Fd_Shell_Command`/`Fd_Shell_Command_List` — conditions,
  shortcuts, storage location, save-flags) is `fluid.shell_command`
  (`ShellCommand`/`ShellCommandList`), with its Settings-dialog "Shell"
  tab in `source/fluid/shell_settings.d` (backing
  `settings_panel.fl`'s real Shell tab) and its live-output window in
  `source/fluid/panels/shell_run_window.fl`/`.d`. `gui_main.d` wires the
  `&Shell` menu, `appPrefs`-backed persistence for user-stored
  commands, and `.fl`-project round-tripping for project-stored ones.

### `fluid/tools/`

**Status:** Partial

- **`filename.h`/`.cxx`** — ported as `path_util.d` (`filenameShortened()`
  et al.), reimplemented over Unicode codepoints rather than FLTK's
  manual byte-offset pointer arithmetic. `fluid.project_history.History`
  calls `filenameShortened(path, 48)` at exactly the two call sites
  FLTK's own `history.cxx` does (loading persisted recent-file paths
  and adding a newly-opened one), populating `History.relpath[]`, which
  `gui_main.d`'s own Recent Files menu-building code reads directly to
  label each entry. Two real FLTK edge-case bugs here are not reproduced —
  see `FLTK_ISSUES.md`.
- **`ExternalCodeEditor_UNIX.h`/`.cxx`** — ported as
  `external_code_editor.d` (`ExternalCodeEditor`): launches and tracks an
  external text editor process, with change polling and reap-on-exit.
  `std.process`/`std.file` replace FLTK's raw `fork()`/`execvp()`/
  `waitpid()`/`pipe()` entirely — `spawnProcess()` throwing synchronously
  on a failed launch eliminates FLTK's entire self-pipe error-relay
  mechanism (needed in C++ purely because a failed `execvp()` in a forked
  child has no safe way to signal the parent). UI wiring is real: an
  "Edit Externally..." button in `panels/widget_panel.fl`'s Code
  section, plus "External Editor:"/"Use for Code Nodes" controls on
  `settings_panel.fl`'s General tab. `gui_main.d` owns one
  `ExternalCodeEditor` per code-bearing node and the app-wide 2-second
  poll timer (ported from `Fluid.cxx`'s own `external_editor_timer()`)
  that walks the whole project tree pulling in out-of-band changes.
- **`ExternalCodeEditor_WIN32.h`/`.cxx`** — out of scope, Windows-only.
- **`autodoc.h`/`.cxx`** — deliberately not ported: an internal tool for
  generating annotated screenshots for FLTK's *own* documentation; this
  project has no documentation-generation pipeline that would call it.

### `fluid/widgets/`

**Status:** Partial

FLTK's own Fluid-internal UI widgets, built on `fl.*` (essentially the
whole classic widget set is ported, so nothing here is blocked on a
missing base widget). `node_browser.d`'s `NodeBrowser` is a deliberate,
architecturally-honest substitute for FLTK's own `Node_Browser`, built on
`fl.tree.Tree` rather than `Fl_Browser_` — FLTK's own choice follows from
*its* `Node` model being a flat doubly-linked list, exactly `Fl_Browser_`'s
native shape; this port's tree-shaped `Node` is exactly `Tree`'s native
shape instead, so porting a `Browser_`-based `Node_Browser` here would
mean building a fake flat-list adapter this project doesn't need.
`Bin_Button` is a real, literal, geometry-faithful port (`BinButton`,
including the click-vs-drag XDND-drag-source split), backing a real,
literal port of `panels/function_panel.fl` (FLTK's own "Tools" widget-bin
window, all 8 groups and all 57 buttons present at their real FLTK
coordinates, every one of them live). The "Window" button is `Bin_Window_Button`: a click calls
`createWindowNode()`, and dragging it shows a borderless preview window
that follows the pointer; releasing it creates the new top-level window at
the drop position on the desktop (`fluid.bin_button.onWindowDropped`). **`rsrcs/pixmaps.h`/`.cxx`'s own
per-node-type icon table is real** — `fluid.pixmaps`
(`pixmapFor()`/`loadPixmaps()`, backed by 62 embedded XPMs in `fluid.
pixmaps_xpm`), wired into both `function_panel.fl`'s real buttons and
`node_browser.d`'s own per-row icon (`fl.tree_item.TreeItem.usericon()`).
**`Node_Browser::item_draw()`/`item_height()`'s own row format is
real** — a `NodeBrowserItem : TreeItem` (`node_browser.d`) overrides
`calcItemHeight()`/`drawItemContent()` (both real, documented
`TreeItem` extension points) to match FLTK's row layout: bold
class name (`Fl_` prefix stripped) followed by a plain instance name,
falling back to a quoted `label` with no instance name, an optional
dark-green comment sub-line above the row, and a thin separator along
the bottom edge of every unselected row. Needed one small `fl.tree.
Tree` API addition: `add(TreeItem parentItem, string name, TreeItem
item)`, so a caller can insert a pre-built custom `TreeItem` subclass
instead of only the plain-label-only 2-arg overload. **The function/
comment/code "code block" row variants** are real
(`rowKind()`/`nodeTitle()`, ported from FLTK's own `item_draw()`
else-branch dispatch: `is_code_block() && (level == 0 || parent->
is_class())` for `Function`/top-level-or-in-class `CodeBlock`, else
`Comment_Node`, else everything else -- `Code`/`Decl`/`DeclBlock`/
`Data`/other-`CodeBlock`) — each gets its own single-segment
`func_font+func_color`/`comment_font+comment_color`/`code_font+
code_color` row instead of falling through to the class-name-plus-
instance-name format. Rows also get FLTK's overlay tags on the type icon:
a lock for a private widget or function, a mark for a protected one (a
declaration or declaration block never gets either, since generated D has no
header/source split for its visibility to choose), and an "invisible"
mark for a hidden widget (not in a Tabs or Wizard, not a window).
`syncSelection()` (the canvas → browser
direction) scrolls the tree to bring the primary selection into view
when it's currently scrolled off-screen — FLTK has no equivalent:
clicking a widget in its own editor window highlights the matching
`Node_Browser` row but never scrolls to it, so a selection outside the
browser's current scroll position stays silently invisible there.

`Pack`/`Scroll`/`Tile` (Groups), `RepeatButton` (Buttons), `TextEditor`/
`FileInput` (Text), `Tree`/`CheckBrowser`/`HelpView`/`FileBrowser`/`Table`
(Browsers), and `Progress` (Misc) are registered like the rest:
`fluid.factory`/`fluid.instantiate` register each against its `fl.*` widget
(`fl.pack` through `fl.progress` are fully ported; the Fluid-specific
node/instantiate/pixmap-alias registrations are what each button needs),
`fluid.pixmaps` carries the handful of bare-name icon
aliases the `"Fl_" ~ typeName` fallback can't cover on its own
(`RepeatButton`/`FileInput`/`CheckBrowser`/`FileBrowser`/`HelpView`),
and `gui_main.d`'s `&New` menu has matching entries (a dedicated
`&Browsers` category holds the 6 browser-kind entries). `TextEditor`
is also registered for `settings_panel.fl`'s own Shell-tab editor;
its palette button uses the same registration.
`Tree`/`HelpView` are `Fl_Group` subclasses in C++ but, matching
FLTK's own comments in `factory.cxx` ("FLUID does not support extended
Fl_Tree", "supporting children is not useful"), are registered as leaf
`WidgetNode`s here too — their `fl.*` constructors already call `end()`
internally (the same pattern `fl.text_display`/`fl.terminal` already
relied on), so no live-tree children are exposed for them. `Table` is a
`GroupNode`, as FLTK's `Table_Node` is a `Group_Node`: on the canvas it
is a `fluid.table_proxy.TableProxy` (FLTK's `Fl_Table_Proxy`: 14 rows by
7 columns of sample data with `A`-`G`/`000:` headers), it accepts child
widgets, and adding the first one shows FLTK's "not recommended"
message. Generated code creates a plain `fl.table.Table`.
**The Code group (9: `Function`/`Class`/`comment`/`Code`/
`CodeBlock`/`widget_class`/`decl`/`declblock`/`data`) is real**,
inserted through a dedicated, non-widget-shaped path (`gui_main.d`'s
`addNode()`, the counterpart to `insertWidget()` for nodes with no live
`Fl_Widget`), placed by FLTK's per-kind placement walk (see the
`Fluid.cxx` row: `placeNewNode()`/`acceptsNewNode()`). `NodeBrowser.
build()` renders the whole `projectRoots_` forest, not just a single
window root. Cut/Copy/Paste/Duplicate/Delete all reach top-level Code
nodes too (see `gui_main.d`'s own top comment and `allSelectedNodes()`'s
doc comment).

`Fl_Window`'s own bin button/`&New` menu item is real too, via a third,
dedicated path, `createWindowNode()`, ported from `Window_Node::make()`
(not `addWidget()`'s canvas-only insertion path): places the
new `WindowNode` in the nearest Function, Code Block or window (FLTK's
"code block, not a widget_class" rule, where a window counts as a code
block, through the same `placeNewNode()` walk as `addNode()`), or, if
there is none, offers to create a Function for it. A window created
inside another window is a subwindow; it starts at 10,10 in its parent
with the usual 480x320 size capped to fit, where FLTK would place it at
the screen-centered position computed for top-level windows, outside its
parent. "Current selection" (`gui_main.d`'s
`currentSelection()`, shared by `createWindowNode()`/`addNode()`/
`addWidget()`) checks the active canvas's selection first, falling back
to the node browser's (`NodeBrowser.selectedNodes()`) when there is no
active canvas — needed because, unlike FLTK's single project-wide
`Fluid.proj.tree.current` pointer, this port tracks selection in the
canvases and the browser, and a project has no canvas until it has a
window.
`addWidget()` shows FLTK's own matching real message ("Please
select a group widget or window", `Widget_Node::make()`) under the same
condition, instead of a silent no-op.

**Startup and `&File/&New` match FLTK's real "no project is
ever truly absent" model.** `Application::new_project()` (`Fluid.cxx`)
just calls `Project::reset()`, which deletes every node and nothing
else — a brand-new project has *zero* top-level nodes, not an
auto-inserted `Function`/`Window` pair; "Untitled.fl" in the title bar
is purely `Project::set_modflag()`'s own display fallback for "no
filename set" (`if (!proj_filename) basename = "Untitled.fl";`), with
no bearing on whether the tree has content. `runEditor()` reaches this
same empty-but-ready state directly at startup (calling `newProject()`
itself when no file argument is given, rather than leaving every
project-related field at its plain `.init`/null default until an
explicit `&File/&New` "initializes" something) — so a fresh launch
lets the user add a `Function` and then a `Window` immediately, with no
conditioning step required. `openNode()`/`selectFromBrowser()` both
work with no canvas at all (loading the properties panel off
`LiveTree.init`), so selecting/opening a `Function` node in a
windowless project works. Every window gets its own canvas
(`canvases_`, keyed by `WindowNode`; `showWindowCanvas()` creates one for
a new top-level window). A window nested inside another window's widget
tree is a subwindow whose `ProjectCanvas` is built inside its parent's
canvas (`instantiate.d`'s `nestedWindowFactory`) and registered by
`registerNestedCanvases()`; its children's coordinates are relative to
it, as in FLTK, and the project tree, selection, Properties panel, undo,
paste and delete all treat it like any other window. Generated code
constructs a nested window with `Window(x, y, w, h)` so it becomes a
subwindow. All 4
menu-item buttons in the widget *bin* (Submenu/Menu Item/Checkbox Menu
Item/Radio Menu Item) are real: a click goes through `addNode()` like the
`&New` menu's entries, and dropping one on a menu owner or submenu adds
it there.

Every widget-bin button works both by dragging onto the canvas and by
a plain click (both add a widget); the 9 Code-group buttons are
click-only, matching FLTK exactly (only 49 of `function_panel.fl`'s
57 buttons are drag-capable `Bin_Button`s FLTK too; the 4 menu-item
buttons are drag-capable here, as the drop target decides where the
item goes).
`gui_main.d`'s `openNode(Node n)` (load into the property panel +
show/raise) matches FLTK's `Node::open()` ("what happens when you
double-click"); called from `insertWidget()`/`addNode()` (matching
FLTK's own `add_new_widget_from_user()`'s `and_open=true` default)
and from `NodeBrowser.onOpen` on a real double-click.

The widget-creation path (`gui_main.d`'s equivalent of FLTK's
`add_new_widget_from_user()`, the function that runs for every newly
created widget) has real per-type default geometry
(`fluid.instantiate.idealSizeFor()`, backed by the real `fluid.
layout_suite` preset values — see below — rather than a flat `90x25`),
Grid/Flex position-aware placement on drop (`gui_main.d`'s
`insertIntoGroup()`: Flex gets the real closest-neighbor-to-drop-point
insert, Grid gets the cell under the drop or right-click point, else the
first free cell, via `fluid.grid_proxy.GridProxy.moveCell()`, which keeps
a widget dropped on an occupied cell as a transient overlay on it, and
the resulting cell is recorded in `GridNode.cellOf`), and
Menu_Bar-as-first-child-of-window auto-full-width. Not yet resolved: whether `Node::layout_widget()`'s re-layout-on-child-change role
is actually needed here at all, given `fl.grid.Grid`/`fl.flex.Flex`
are real *live* widgets with their own runtime layout logic (unlike
FLTK's own mostly-non-live editing model).

The `Snap_Action` drag-time guide/alignment system (see the
`Snap_Action.h`/`.cxx` entry above for its coverage) is wired into `fluid.canvas.ProjectCanvas`'s own drag/draw
pipeline at the same two call sites FLTK's `Window_Node::newdx()`/
`draw_overlay()` use. `fluid.layout_suite` (`Layout_Preset`/
`Layout_Suite`/`Layout_List` — both of FLTK's real built-in
suites, "FLTK" and "Grid", ported verbatim) backs `idealSizeFor()`
with the real preset values. Custom-suite persistence and a Settings-
dialog editing UI are both real too: the Settings dialog's Layout tab
and `ToolStore.user`/
`.project`/`.file` persistence to `appPrefs`/the `.fl` project file/a
standalone `.fll` file, respectively.

**`Formula_Input`** (`fluid.formula_input.FormulaInput`) is a faithful,
self-contained port of the small
integer-formula interpreter (unary `+`/`-`, `+ - * /`, parentheses,
named variables, mouse-wheel adjust) — `text()`/`text(v)` for the raw
string (matching FLTK's own naming, needed since `value()`/`value(int)`
are repurposed here to evaluate/set the formula as an `int`, hiding
`Input_`'s own plain-string accessors the same way FLTK's own class
hides `Fl_Input`'s). Wired into all 4 of `widget_panel.fl`'s Position
group fields (`widgetXInput`/`Y`/`W`/`H`, via the `class FormulaInput`
`.fl` override property, the same "subclass a built-in leaf type"
mechanism `WidgetNode.classOverride` already provides for a real user's
own project) with the full `i`/`x`/`y`/`w`/`h`/`px`/`py`/`pw`/`ph`/
`sx`/`sy`/`sw`/`sh`/`cx`/`cy`/`cw`/`ch` variable set FLTK's own
`widget_vars[]` table provides, each read from the live canvas via
`liveTree_.widgetOf` (parent/previous-sibling/children-bounding-box
lookups) — matching FLTK's own `vars_x_cb()`-style callbacks reading
`current_widget`'s live `Fl_Widget`. `i` is the zero-based index of the
widget among the selected ones (the field callbacks loop the whole
selection). A real FLTK bug in `eval_var()` is logged in
`FLTK_ISSUES.md` and faithfully preserved, not fixed. The Image Options dialog's 4 analogous
scale-width/height fields (`image_panel_imagew`/`h`, `_deimagew`/`h` in
FLTK) use `Formula_Input` too, wired the same way — arithmetic only,
matching FLTK's own source, which never calls `variables()` for these
2 fields either.

`Code_Editor`/`Code_Viewer`/`Style_Parser` are ported as
`fluid.code_highlight`, which highlights D rather than C++: a lexer
(`styleParse()`), a style table, `enableHighlighting()` (attaches a style
buffer to any `TextDisplay`, restyling the whole buffer on each change like
`Code_Editor`) and `enableAutoIndent()` (Enter keeps the line's indentation).
The token classes follow nano's `d.syntax`, with colors chosen for a
white background. It is used by the D code editors of the widget panel
(callback, setup code, code and decl text, function name and return type) and
by Code View's Source pane; comment editors, the `.fl` text pane and shell
script editors stay plain. `Code_Viewer`'s draw-time swap of the global selection color for a light
gray is `fluid.code_viewer.CodeViewer`, the class of Code View's Source and
Project panes, so the node highlight stays readable over the syntax colors.

Missing:
- `App_Menu_Bar`/`Text_Viewer` — none needed yet.

## Samples

### `source/examples/` and `source/test/`

**Status:** Partial

D transliterations of FLTK's own `examples/*.cxx`/`test/*.cxx`, built by
`rdmd buildsamples.d` into `build/`. Most samples build and match FLTK's
own behavior; a program calling a library API this port doesn't have yet
is expected and not tracked here unless it's blocked on something still
open. `buildsamples.d` itself skips four programs, each for a reason
already tracked against the header it needs:

- `test/cairo_test.d`, `examples/cairo_draw_x.d` — need a Cairo backend,
  see `FL/Fl_Cairo.H`.
- `test/penpal.d` — needs pen/tablet input, see `FL/core/pen_events.H`.
- `test/forms.d` — FLTK's XForms-compatibility demo, permanently out of
  scope, see `FL/forms.H`.

Waiting on a library decision that isn't tied to any FLTK header:
`test/blocks.d`'s `BlockSound` and `test/sudoku.d`'s `SudokuSound` are
silent, since this port has no ALSA bindings. Their `snd_pcm_*` code is
kept verbatim behind `version (none)`, ready to flip on once bindings
exist.

Two known bugs live in the sample code itself, not in the library
underneath:

- `test/handle_events.d`'s `printEvent()` hardcodes `scale = 100`
  instead of calling `fl.core.screenScale(screenNum())` (real and
  complete, see `FL/Fl.H`); the sample's own comment claiming the
  function doesn't exist is wrong.
- `examples/animgifimage_play.d`'s `-s <speed>` argument-parsing branch
  never blanks the consumed value slot the way FLTK's own `argv[i] = 0`
  does, so `nextFile()`'s later file-cycling (the `n` key) can mistake
  the numeric speed value for a filename. Low priority: only affects
  `-s` combined with multiple files and pressing `n`.
