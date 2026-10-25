# FLTK issues found while porting (second batch)

Entries found after `FLTK_ISSUES.md` was shared with the FLTK team. The
format, the meaning of each **FLTK status** line, and the process are the
same as in `FLTK_ISSUES.md`; new entries go here.

| Entry | FLTK status |
|---|---|
| `make_xid()` window without a cursor | Open |
| `Fl_X11_Screen_Driver::dnd()` `XdndPosition` on every pass | Open |
| Wayland: a drag that another program accepts never ends | Open |
| Wayland: `Fl::add_clipboard_notify()` handlers never run | Open |
| Wayland: a borderless window can't move itself (`examples/shapedwindow`) | Open |
| Wayland: fractional desktop scales are drawn blurred | Open |
| Wayland: GTK's accessibility warnings flood the console | Open |
| Wayland: mouse buttons beyond 5 are ignored, and numbered unlike X11 | Open |
| Wayland: `Fl_Window::icon()` has no effect | Open |
| Wayland: a postponed GL swap runs with another window's context current | Open |
| Wayland: `gl_start()` drawing is never swapped | Open |
| Wayland: the GL software overlay piles up | Open |
| Wayland: offscreens made while drawing on a HiDPI screen get its scale twice | Open |
| `fluid/pixmaps/flTable.xpm`: a color with seven hex digits | Open |
| nanosvg: unitless gradient coordinates in `objectBoundingBox` units | Open |

### `make_xid()` (`src/Fl_x.cxx`): a new window has no cursor until `cursor()` is called, so it shows the root window's cursor

**FLTK status:** Open. Observed: FLTK's `fluid`, forced onto X11 with
`FLTK_BACKEND=x11` under labwc (rootless Xwayland), shows the X server's
built-in "X" cursor over its windows until something calls
`Fl_Window::cursor()` (opening a menu, hovering a resize edge); after that
the window shows a normal arrow. fltk/fltk's GitHub issues and pull
requests have not been searched for an existing report yet.

`make_xid()` creates the window without `CWCursor`, and nothing calls
`XDefineCursor()` until `Fl_X11_Window_Driver::set_cursor()` runs, so the
window inherits the root window's cursor. A desktop's window manager
normally replaces the root cursor with the theme's arrow; a rootless
Xwayland server under a wlroots compositor such as labwc keeps the X
server's default. FLTK's Wayland backend is not affected. A fix is to
define the default cursor on each top-level window when it is created.

**Deviated from in the port**: `fl.platform_x11`'s `createWindow()` calls
`cursor(Cursor.default_)` on every top-level window once it is shown.

### `Fl_X11_Screen_Driver::dnd()` (`src/fl_dnd_x.cxx`): an `XdndPosition` is sent on every loop pass, so source and target answer each other nonstop

**FLTK status:** Open at `a3bc8b705`. Observed: FLTK's
`examples/howto-drag-and-drop`, built from `a3bc8b705` and forced onto X11 with `FLTK_BACKEND=x11` under GNOME on Wayland (Mutter,
Xwayland), makes the desktop stall and repaint erratically for several
seconds once a drag crosses the desktop; dragging straight into a
neighboring window works. fltk/fltk's GitHub issues and pull requests
have not been searched for an existing report yet.

The drag loop sends `XdndPosition` to an XDND-aware target on every pass
through `while (Fl::pushed()) { ... Fl::wait(); }`, whether or not the
pointer moved. The target's `XdndStatus` reply is itself an event that
ends the `Fl::wait()`, so each reply triggers another position message
and the two sides exchange messages as fast as the server allows. The
XDND specification asks the source to send a new `XdndPosition` only
after the previous `XdndStatus` arrived and the pointer moved. Over a
Wayland surface the target is Mutter's Xwayland drag bridge, which
forwards each position to the Wayland side and falls behind. A fix is to
send `XdndPosition` only when the target window or the root position
changed since the last one.

**Deviated from in the port**: `fl.platform_x11`'s `dnd()` remembers the
last position it sent and its target, and skips the message when neither
changed.

### `fl_wayland_clipboard_dnd.cxx`: a drag that another program accepts never ends, and later drops from other programs paste FLTK's own text

**FLTK status:** Open at `3a049d826`. Found by reading the source, not
reproduced. fltk/fltk's GitHub issues and pull requests have not been
searched for an existing report yet.

`doing_dnd` is set by `Fl_Wayland_Screen_Driver::dnd()` and cleared only
by `data_source_handle_cancelled()`. FLTK binds `wl_data_device_manager`
at version 3 (`Fl_Wayland_Screen_Driver.cxx`), and from version 3 on a
drop that the target accepts ends with `wl_data_source.dnd_finished`, not
`cancelled`; `data_source_handle_dnd_finished()` only looks at the last
action. After dragging text into another program, `doing_dnd` therefore
stays true, the `wl_data_source` is never destroyed, and the target
window never gets its `FL_RELEASE`. The next drop *from* another program
onto an FLTK widget then takes `data_device_handle_drop()`'s `doing_dnd`
branch and pastes `selection_string[0]`, FLTK's own earlier text,
instead of the dropped data. A fix is to do what the `cancelled` handler
does (destroy the source, clear `doing_dnd`, send `FL_RELEASE`) in the
`dnd_finished` handler too.

**Deviated from in the port**: `fl.platform_wayland`'s `dnd()` ends the
drag on `dnd_finished` as well as on `cancelled`, and also gives up when
the compositor never starts it (no `data_device.enter` before a
roundtrip, as with a stale serial).

### Wayland driver: `Fl::add_clipboard_notify()` handlers never run

**FLTK status:** Open at `3a049d826`. Found by reading the source.

`Fl_X11_Screen_Driver` and `Fl_WinAPI_Screen_Driver` override
`clipboard_notify_change()` and call `fl_trigger_clipboard_notify()` when
another program changes the clipboard; `Fl_Wayland_Screen_Driver`
overrides neither, so on Wayland the handlers are never called. The
`wl_data_device.selection` event (`data_device_handle_selection()`)
already tells FLTK when the clipboard changes; calling
`fl_trigger_clipboard_notify(1)` there, when the new offer isn't FLTK's
own data source, would make them work.

**Deviated from in the port**: `fl.platform_wayland`'s
`dataDeviceSelection()` calls `fl.core.triggerClipboardNotify(1)` when
another program set the clipboard.

### Wayland driver: a borderless window can't move itself, so `examples/shapedwindow` can't be dragged

**FLTK status:** Open at `3a049d826`. Observed: FLTK's
`examples/shapedwindow` under GNOME on Wayland doesn't move when dragged
by its content.

The example moves its window with `Fl_Window::position()` on `FL_DRAG`.
A Wayland client can't place its windows, so the call has no effect
there. The protocol's way to let the user drag a window is
`xdg_toplevel_move(toplevel, seat, serial)` (or `libdecor_frame_move()`
for a decorated window) with the serial of the button press, after which
the compositor moves the window; FLTK could start such a move when a
window repositions itself while a mouse button is held.

**Deviated from in the port**: `fl.platform_wayland`'s
`startInteractiveMove()` does that, once per button press, and sends the
widget the `FL_RELEASE` the compositor keeps for itself.

### Wayland driver: fractional desktop scales (125%, 150%, ...) are drawn blurred

**FLTK status:** Open at `3a049d826`; an enhancement rather than a bug.

FLTK draws each window at the next integer output scale and lets the
compositor shrink the buffer to the fractional scale, which blurs text
and lines (GNOME's display settings warn about this for applications
without fractional-scaling support). With `wp_fractional_scale_v1` the
compositor tells each surface its exact scale, and with `wp_viewporter`
the client gives the surface's logical size, so the buffer can be drawn
at the exact scale.

**Deviated from in the port**: `fl.platform_wayland` draws at the exact
scale when the compositor offers both protocols (`deviceScale()`), and
falls back to FLTK's integer scale otherwise.

### Wayland driver: GTK's accessibility bridge floods the console with AT-SPI warnings

**FLTK status:** Open at `3a049d826`. Observed: FLTK's `test/clock` under
GNOME on Wayland prints a stream of warnings such as
`AT-SPI: Could not obtain desktop path or name` and
`atk-bridge: GetRegisteredEvents returned message with unknown signature`.

libdecor's GTK plugin starts GTK in the process to draw the title bar,
and GTK loads its accessibility bridge (atk-bridge), which complains when
the accessibility bus doesn't answer as it expects. The bridge would only
expose the GTK-drawn title bar to screen readers; FLTK's own widgets
don't take part in accessibility. GTK skips the bridge when the
environment variable `NO_AT_BRIDGE` is `1`; setting it (without
overriding a value the user set) before `libdecor_new()` silences the
warnings.

**Not applicable to the port**: fldtk doesn't use libdecor; it draws
its own title bar (`fl.wayland_decoration`), so GTK never runs in the
process.

### Wayland driver: mouse buttons beyond 5 are ignored, and back/forward are numbered unlike on X11

**FLTK status:** Open at `3a049d826`; a consistency issue rather than a
bug.

`pointer_button()` (`Fl_Wayland_Screen_Driver.cxx`) makes `BTN_SIDE` and
`BTN_BACK` button 4 and `BTN_EXTRA` and `BTN_FORWARD` button 5, and
ignores every other button code. On X11 the same mouse under Xwayland
gives `BTN_SIDE` as X button 8 and `BTN_EXTRA` as 9 (which FLTK makes 4
and 5) and, by Xwayland's mapping as understood here (not checked
against Xwayland's source), `BTN_FORWARD` as 10 and `BTN_BACK` as 11,
which FLTK ignores there. A gesture button that reports X button 10 on
X11 has been observed with fldtk. A program therefore sees different buttons on the two backends,
and a mouse's extra buttons (a gesture button, for instance) can't be
used on either. Numbering the codes after `BTN_EXTRA` as 10, 11, ... on
Wayland, as Xwayland does, and passing them on would make both backends
agree.

**Deviated from in the port**: on both backends fldtk reports any
button: side buttons 4 and 5, the next ones 10, 11, ...
(`fl.platform_wayland`'s `pointerButton()`, `fl.platform_x11`'s
`ButtonPress` case), with `Fl::event_state()`'s button bits still
limited to buttons 1-5.

### Wayland driver: `Fl_Window::icon()` has no effect

**FLTK status:** Open at `3a049d826`; an enhancement rather than a bug.

`Fl_Wayland_Window_Driver` doesn't override `Fl_Window_Driver::icons()`,
so a window's icons are dropped on Wayland; the desktop shows the icon of
the `.desktop` file matching the window's app id, or a generic one. The
staging protocol xdg-toplevel-icon (`xdg_toplevel_icon_manager_v1`)
lets a client give its toplevel an icon from `wl_shm` buffers (they must
be square). Not every compositor offers it: KDE Plasma 5.27's KWin
doesn't (Plasma 6 does), nor does GNOME yet; there the desktop file stays
the only way.

**Deviated from in the port**: `fl.platform_wayland`'s `setIcons()`
gives the window's icons, each centred on a transparent square, through
xdg-toplevel-icon when the compositor offers it.

### Wayland GL driver: a postponed buffer swap runs with whatever context is current

**FLTK status:** Open at `3a049d826`. Found by reading the source; not
reproduced against FLTK.

`Fl_Wayland_Gl_Window_Driver::swap_buffers()` postpones the swap while
the window's frame callback is pending (`need_swap`), and
`surface_frame_done()` then calls `eglSwapBuffers()` on the window's EGL
surface without making its context current. EGL requires the surface to
be the current context's draw surface (Mesa returns `EGL_BAD_SURFACE`
otherwise), so with two GL windows the postponed swap fails whenever the
other window's context is current, and the frame stays unshown until
the window is drawn again. Making the window's context current around
the swap, and restoring the previous one, fixes it.

**Deviated from in the port**: `fl.wayland_gl_window_driver`'s
`glFrameDone()` makes the window's own context current for the
postponed swap and restores the previous context afterwards.

### Wayland GL driver: what `gl_start()` draws is never swapped

**FLTK status:** Open at `3a049d826`. Found by reading the source; not
reproduced against FLTK.

On Wayland, `gl_start()` draws into a subsurface over the window with its
own double-buffered EGL surface (`Fl_Wayland_Gl_Window_Driver::
set_gl_context()`), and sets `glDrawBuffer(GL_FRONT)`; nothing ever calls
`eglSwapBuffers()` on that surface, and on Wayland only a swapped buffer
reaches the compositor, so the drawing shouldn't appear. Also,
`Fl_Wayland_Gl_Window_Driver::gl_start()` clears the whole surface at every
`gl_start()`, so in a window where two widgets draw with
`gl_start()`/`gl_finish()` the second erases the first; and the
subsurface is placed at the window's `x()`/`y()`, which for a subwindow
is an offset from its parent, not from its own surface.

**Deviated from in the port**: `fl.wayland_gl_window_driver` draws
`gl_start()` into the back buffer, clears the surface once per repaint of
the window, swaps it after the window's `draw()` (shown with the
window's next commit, the subsurface being synchronized), redraws such a
window whole, and places the subsurface at (0, 0).

### Wayland GL driver: the software overlay piles up instead of being redrawn

**FLTK status:** Open at `3a049d826`. Not run against FLTK; seen in
fldtk's port of the same algorithm: in `test/gl_overlay` under GNOME,
dragging the overlay slider leaves every earlier red outline on screen.

`Fl_Wayland_Gl_Window_Driver::swap_buffers()` emulates the overlay by
copying the back buffer to the front buffer (`glCopyPixels()`), drawing
the overlay into the front buffer, then copying the front buffer back
and calling `eglSwapBuffers()`; an overlay-only redraw skips `draw()`
and starts again from the back buffer. That relies on the back buffer
still holding the clean scene after the swap. EGL doesn't promise it
(`EGL_BUFFER_DESTROYED` is the default swap behavior): on Wayland, after
a swap the back buffer is an older buffer, which already has an overlay
in it, so overlays accumulate. Redrawing the scene for an overlay-only
redraw and drawing the overlay into the back buffer before the swap is
always correct.

**Deviated from in the port**: `fl.gl_window.flushGlWindow()` does that
on Wayland (`fl.gl_window_driver.overlayInBackBuffer()`).

### Wayland driver: an offscreen made while drawing on a HiDPI screen gets the screen's scale twice

**FLTK status:** Open at `3a049d826`. Observed: FLTK's `test/penpal` on
Wayland (KDE Plasma 5.27), its window dragged from a scale-1 screen to a
screen with a higher scale, no longer shows its canvases right, while
with `FLTK_BACKEND=x11` it works; fldtk's port of `penpal` works after
the same move, on Wayland and on X11. The
cause below was found by reading the source, not by tracing FLTK.

While a window is drawn, `Fl_Wayland_Window_Driver::make_current()` sets
the display driver's scale to `Fl::screen_scale() * wld_scale()`
(`set_cairo(..., f * wld_s)`), so the screen's integer scale is already
in it. `Fl_Wayland_Image_Surface_Driver`'s constructor, which
`fl_create_offscreen()` and `fl_rescale_offscreen()` (through
`Fl_Image_Surface::rescale()`) both reach, takes
`s = Fl_Graphics_Driver::default_driver().scale()` -- that same product --
and multiplies it by `d = wld_scale()` of `Fl::first_window()`, sizing
and scaling the buffer by `d * s`. On a scale-2 screen a buffer made or
rescaled during drawing (as `penpal`'s `cv_draw()` does, when it sees
`fl_graphics_driver->scale()` change) gets scale 4; and `d` is the scale
of whichever window is first in FLTK's list, not necessarily the one
being drawn. Using the drawing scale alone when it is set (inside
`make_current()`), and the window's own `wld_scale()` otherwise, would
give the buffer the scale it is drawn at.

**Not applicable to the port**: fldtk's offscreens record the scale
they are made at (`fl.draw.createOffscreen()`, the current drawing
scale, which on Wayland includes the screen's), draw at it
(`beginOffscreen()`) and are remade at a new one by `rescaleOffscreen()`.

### `fluid/pixmaps/flTable.xpm`: a color with seven hex digits

**FLTK status:** Open at `3a049d826`.

Line 12 of `fluid/pixmaps/flTable.xpm` defines the color `"x c #9999999"`:
seven hex digits, where an XPM color needs 3, 6, 9 or 12. FLTK reads it
as `#999999` only by accident: `Fl_Screen_Driver::parse_color()`
(`src/Fl_Screen_Driver.cxx`) takes `strlen / 3` = 2 digits per channel
and `sscanf("%2x%2x%2x")` silently ignores the seventh digit. Stricter
readers reject the color instead (`XParseColor()`, and fldtk's own
`fl.draw.parseHexColor()`, which requires a length divisible by 3), so
the same file shows those pixels wrongly elsewhere. `"x c #999999"` is
what was meant.

**Not applicable to the port**: Fluid's icons in fldtk are SVG
(`source/fluid/pixmaps_svg/`), not FLTK's XPMs.

### nanosvg (`nanosvg/nanosvg.h`): unitless gradient coordinates in `objectBoundingBox` units are taken as absolute positions

**FLTK status:** Open at `3a049d826`. The code is the same in
memononen/nanosvg, which FLTK's fork (`fltk/nanosvg`) is based on, so
this may belong there too.

With `gradientUnits="objectBoundingBox"` (the default), the SVG
specification says a gradient coordinate given as a plain number is a
fraction of the shape's bounding box: `x1="0" x2="1"` runs the gradient
across the whole shape, the same as `x2="100%"`. Inkscape writes
gradients this way. `nsvg__createGradient()` passes every coordinate
through `nsvg__convertToPixels()` (lines 789 and 871-882), whose
`NSVG_UNITS_USER` case returns the number unchanged, so `x2="1"` becomes
an absolute position one unit from the origin. The gradient then sits
inside the shape's first pixel, and an `Fl_SVG_Image` shows the shape in
the last stop's colour. Percentages work, which is why the defaults
(`0%`/`100%`) look right.

In object space, mapping a unitless coordinate to
`orig + value * length` before falling back to `nsvg__convertToPixels()`
fixes it.

**Deviated from in the port**: `fl.nanosvg.createGradient()` does that,
for linear and radial gradients.

### `fl_show_colormap.cxx`: the popup jumps to the primary monitor from a monitor with negative coordinates

**FLTK status:** Open at `d15af5089`.

`ColorMenu::handle()` (`src/fl_show_colormap.cxx`, lines 114-121)
moves the popup so the picked swatch stays on screen. It first clamps to
the bounds of the monitor under the mouse (`Fl::screen_xywh()`), then
does:

```cpp
if (px+bx < BORDER) px = BORDER-bx;
if (py+by < BORDER) py = BORDER-by;
```

That compares against 0, the primary monitor's origin, rather than
`scr_x`/`scr_y`. On a monitor left of or above the primary, every
position is negative, so the first click or drag moves the popup onto
the primary monitor; the button release then lands outside it and the
pick is lost. `scr_x+BORDER`/`scr_y+BORDER` in place of `BORDER` fixes
it.

**Deviated from in the port**: `fl.show_colormap.ColorMenu.handle()`
measures from `scrX`/`scrY`.
