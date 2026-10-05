# fldtk conventions

How fldtk maps FLTK onto D, and the decisions behind it. Source comments and
the other documents refer here for the reasoning; per-module status is in
[`PORTING.md`](PORTING.md), build instructions are in
[`BUILDING.md`](BUILDING.md).

fldtk (Full-D-tick) is a complete D port of FLTK, not just a binding layer:
FLTK's functionality is reimplemented as native D code, including support
in Fluid (FLTK's UI designer) for exporting D source files instead of C++.

## Reference source

Every port starts from FLTK's real headers (`FL/*.H`) and implementation
(`src/*.cxx`), not from memory of its API or from other bindings projects.
fldtk tracks FLTK 1.5.0 (the version in `fltk_version.dat` of a current
checkout of FLTK's `master` branch). FLTK's `CHANGES_*.txt` files lag its
code, so current behavior is always verified against the headers and sources
themselves.

One structural change worth knowing about: in 1.5 `Fl` is no longer one
monolithic static class. It is `namespace Fl { ... }`, with its members
split across `FL/core/events.H`, `FL/core/options.H`,
`FL/core/function_types.H` and `FL/core/pen_events.H`. For example
`Fl::visible_focus()` now routes through a general `Fl_Option`/`option()`
mechanism instead of a dedicated static bool.

Where a likely bug in FLTK itself is found while reading its source, it is
recorded in [`FLTK_ISSUES.md`](FLTK_ISSUES.md) (with file, line and
reasoning) rather than silently worked around or fixed in the port.

FLTK's own graphics backend may be Cairo+Pango rather than classic Xlib+Xft,
depending on how it was built. Cairo antialiases every fill (including plain
polygon fills such as the checkmark drawn by `fl_draw_check()`), while this
port's Xlib `XFillPolygon()` is hard-edged, and Pango's text shaping and
hinting differ visibly from raw Xft's simple name matching. Differences of
that kind when comparing against a Cairo/Pango build of FLTK are expected and
are not fldtk bugs; compare against a build with `FLTK_GRAPHICS_CAIRO=OFF`
and `FLTK_USE_PANGO=OFF` for a same-driver comparison.

## Where this port intentionally exceeds FLTK

By default fldtk ports faithfully: it matches FLTK's behavior, structure and
API shape unless there is a specific, reasoned deviation (the conventions
below are the established examples). In a few areas going beyond FLTK is the
agreed direction:

- **Pen/touch input beyond X11.** FLTK's `Fl::Pen` namespace
  (`FL/core/pen_events.H`) has real driver implementations for Wayland and
  Windows but none for X11. Once fldtk's Wayland driver exists and proves out
  the pen-event model, retrofitting equivalent support onto the X11 driver
  via the XInput2 extension is in scope.
- **Pango for text instead of Xft.** `fl.draw`'s text primitives are backed
  by `fl.xft`, matching FLTK's own X11 approach (simple name-string font
  matching via `XftFontOpenName()`, no complex-script shaping). Replacing
  that layer with Pango, for real shaping and internationalization, is
  sanctioned. It is a rewrite of a layer every labelled widget depends on,
  not an incremental patch.
- **Native image codecs instead of FLTK's bundled libraries.** XBM, XPM, PNM,
  BMP, ICO, GIF (including animated), SVG, PNG and JPEG are all decoded by D
  code in this repository (see the next section).

Other ideas of the form "FLTK does X, but we could do better" are raised
before acting on them rather than assumed to be covered here.

## Deferred: external-library-backed features

Some FLTK features depend on an external C library, and for each one there is
a decision between writing a small, clean D reimplementation of just the
format or protocol that is needed (avoiding a permanent dependency on a
library's moving-target API) and binding directly to the C library.

Decided and done:

- **GIF/AnimGIF and SVG** never needed that decision: GIF's LZW decoder is
  self-contained C++, and nanosvg/nanosvgrast are vendored, zlib-licensed,
  single-header C sources, not external libraries. All three are ported
  (`fl.gif_image`, `fl.anim_gif_image`, `fl.nanosvg`, `fl.nanosvg_rast`,
  `fl.svg_image`).
- **PNG** adapts Adam D. Ruppe's high-level D `arsd.png`, retargeted onto
  `fl.image.RGBImage`, with only `std.zlib` (Phobos' zlib binding) for the
  DEFLATE/INFLATE work PNG genuinely requires (`fl.png_image`). Gaps narrower
  than FLTK: no Adam7 interlacing and no grey/truecolor `tRNS` color-keying.
- **JPEG** is a D implementation of Rich Geldreich's public-domain jpgd/jpge,
  following the structure of Ketmar's D translation in `arsd`'s `jpeg.d`
  (`fl.jpeg_decoder`, `fl.jpeg_encoder`, `fl.jpeg_common`, glued by
  `fl.jpeg_image`). It is written as ordinary D: garbage-collected arrays and
  slices instead of malloc'd blocks and pointer arithmetic, a `JpegException`
  instead of status codes, and every table index and block coordinate read
  from a file validated before use. Attribution for the public-domain
  originals is in each module's header.
- **OpenGL** uses hand-written `extern(C)` D bindings against the system
  `libGL` (the same treatment as `fl.xlib` for Xlib), not a third-party D
  binding package. `Fl_Gl_Window`, GL text, overlays, the GL3/core-profile
  samples (via GLEW) and the GLUT compatibility layer (`fl.glut`/`fl.glu`) are
  all in. A GL module that is not re-exported from `fl` (`fl.opengl`,
  `fl.glx`, `fl.gl_choice`, `fl.gl_window_driver`) needs its own explicit
  import in a program.

Still deferred, because they wait on a decision: the **Cairo** rendering
backend (`FLTK_GRAPHICS_CAIRO`, and with it the `cairo_test` and
`cairo_draw_x` samples) and **Pango** text (see above). A stub whose only
blocker is one of these is a deliberate gap, marked `Deferred` in
`PORTING.md`, not an oversight.

## Out of scope: XForms/Forms Library compatibility

Much of FLTK's history is bound up with the old Forms Library (a 1990s SGI GL
toolkit, later ported to X11 as XForms). FLTK carries a compatibility layer
whose only purpose is to let that old C/C++ code keep compiling:
`FL/forms.H`, `Fl_Object` (an alias for `Fl_Widget`),
`Fl_FormsBitmap`/`Fl_FormsPixmap`, `Fl_Free`, `Fl_Timer` (which says in its
own doc comment that it only emulates the Forms timer and that
`Fl::add_timeout()` should be called directly), and smaller shims scattered
through the widget headers (the `|`-separated multi-item form of
`Fl_Menu_::add()`, the `FL_PUP_*` aliases, `fl_old_shortcut()`).

None of it is ported. fldtk is new code on a clean slate; there is no corpus
of Forms-era programs that could ever link against it, so the reason this
layer exists simply does not apply. `PORTING.md` marks these files **Not
applicable** (not "Deferred": nothing is waiting to be revisited).

It does not cover widgets that merely originated for Forms compatibility but
are ordinary, current FLTK API with no dependency on the old library:
`Fl_Clock`, `Fl_Chart` and `Fl_Positioner` all say "provided for Forms
compatibility" in their doc comments, and all are ported (`fl.clock`,
`fl.chart`, `fl.positioner`).

## Architecture

### Namespace mapping: `fl.*`

FLTK's `Fl_Widget`/`Fl_Window`/`fl_draw()` naming maps to D as: package `fl`,
one module per FLTK header (`FL/Fl_Widget.H` -> `fl.widget`, `FL/Fl_Group.H`
-> `fl.group`, ...), PascalCase types (`Fl_Widget` -> `Widget`), camelCase
methods (`label_image_spacing()` -> `labelImageSpacing()`).

`namespace Fl { ... }` (FLTK's core static/global state: event state, focus,
options, the application loop) maps to the D module `fl.core`, using free
functions and module-level state rather than a static-method class. D modules
already behave like namespaces, which is a closer structural match than a
wrapper class.

### Porting conventions

- **Two named exceptions to dropping the `Fl_`/`Fl` prefix**: `Fl_Group` is
  `FlGroup` (`source/fl/group.d`) and `Fl_Clock` is `FlClock`
  (`source/fl/clock.d`). Generated `.fl` -> `.d` files do a wildcard
  `import fl; import std;`, and a bare `Group` or `Clock` collides with
  Phobos' own `std.algorithm.iteration.Group` and
  `std.datetime.systime.Clock` as soon as it is named. The `.fl` dialect still
  accepts the keywords "Group" and "Clock" (matching FLTK's vocabulary); the
  code generator maps them to `FlGroup`/`FlClock`. Further `Fl`-prefix
  exceptions are only added for a real, confirmed collision of this kind.
- **Private storage fields keep FLTK's trailing-underscore names** (`x_`,
  `y_`, `flags_`, `label_`, ...) so they never collide with their public
  accessors of the same name minus the underscore (`x()`, `flags()`,
  `label()`).
- **Use the real D enum where FLTK stores a raw `uchar`/`int`** purely to stay
  open to out-of-range values (box types, label types, a widget's `type()`):
  `Boxtype box_` rather than `ubyte box_`. D enums allow a forward-cast
  (`cast(Boxtype) n`) when open-endedness is actually needed, so nothing is
  lost by being more strongly typed.
- **Closed, non-combinable tag sets** (`Boxtype`, `Labeltype`, `Event`,
  `CallbackReason`) become real D `enum`s. **Open bitmask/index sets** that
  FLTK expresses as an integer typedef plus free constants (`Align`, `Color`,
  `Font`, `When`, `Damage`) stay a D `alias` plus manifest constants, so
  combining values with `|` needs no casts back to the named type.
- **`label()`/`tooltip()` use D `string`** (GC-owned, immutable) rather than
  `const char*`. FLTK's `COPIED_LABEL`/`COPIED_TOOLTIP` flags exist because
  plain C strings need malloc/free bookkeeping to know who owns a copy; under
  the GC that bookkeeping is unnecessary. `copyLabel()`/`copyTooltip()` still
  exist and still set the flag (so `isLabelCopied()` etc. keep working); they
  just skip the manual `free()`.
- **Callbacks are D delegates, not function pointer + `void*`.** `Callback`
  is `void delegate(Widget)`. FLTK's `Fl_Callback` is a plain C function
  pointer plus a `void* user_data()`/`argument()` slot (and
  `Fl_Callback_User_Data`/`AUTO_DELETE_USER_DATA` for owned data) purely
  because C++ function pointers cannot close over state. A D delegate carries
  its own captured context, so none of that machinery is ported for
  callbacks. Callers needing per-widget data capture it:
  `btn.callback((w) { doThing(id); });` instead of
  `btn.callback(fn, cast(void*) id)`. The same substitution applies anywhere
  else FLTK uses the pattern (`Fl_Callback0`/`Fl_Callback1`, menu item
  callbacks).

  Delegates replace `user_data()`/`argument()` only for passing context to a
  callback. FLTK also uses `user_data()` as a plain per-widget tag,
  independent of any callback; that use is ported as
  `Widget.userData()`/`userData(Object)`, an `Object` reference (GC-owned,
  like `TreeItem.userData`). Fluid's `user_data {expr}` property emits
  `w.userData = expr;` before the widget's callback is assigned. Menu items
  have no user-data slot.
- **Check for a cleaner D stdlib alternative before transliterating a raw C
  library call.** FLTK reaches for `memcpy`/`memmove`/`strlen`/etc. because
  C++ has nothing better at hand; a D port usually does. For example, for
  non-overlapping byte transfers `std.algorithm.mutation.copy()`'s array
  specialization lowers to the same bulk-copy path as `memcpy()` and is less
  to audit than raw pointer arithmetic. The default is to look for the cleaner
  alternative, but to verify that it preserves the semantics (overlap-safety,
  error handling, ...) before swapping: a genuinely overlapping copy on a hot,
  potentially large path is where `core.stdc.string.memmove()` still beats
  `copy()`, whose overlap-safe path walks element by element. (`fl.text_buffer`
  uses `memmove()` for `copy()` for this reason, which also avoids a latent
  FLTK bug: undefined behavior on the documented self-copy-with-overlap case.)
- **A widget composing a private, non-tree-managed child widget still gives it
  a real `parent()`.** `Fl_Value_Input` embeds a real `Fl_Input` while itself
  extending `Fl_Valuator`, not `Fl_Group`; FLTK force-casts
  `input.parent((Fl_Group*)this)`, and its own comment calls that a kludge.
  `Widget.parent_` is deliberately typed as plain `Widget`, not `Group`, so
  the problem is solved once, correctly: `child.parent(this)` (the
  `package(fl)` setter) gives the child a real parent, and every consumer of
  `.parent`/`.parent_` (`contains()`, `damage()`, `window()`, focus and
  belowmouse ancestor walks) works without special cases. Only code that
  needs `Group`-specific behavior on a parent (`Group.insert()`, `fl.pack`'s
  resize, ...) needs an explicit `cast(Group)`; for a normal widget that cast
  is always safe, and only fails for a deliberately composed child like this
  one. Leaving `parent_` null and patching each consumer separately is the
  wrong response.
- **GC finalizer hazard.** `Widget.~this()` mirrors FLTK's destructor (detach
  from parent, throw focus, ...), but those steps touch other GC-managed
  objects, which is only safe when the destructor runs deterministically
  (explicit `destroy(widget)`). During GC-driven finalization (program exit, a
  collection sweep) the finalization order across objects is undefined, so
  touching another object is a use-after-free waiting to happen. Guard
  cross-object work in a destructor with `core.memory.GC.inFinalizer()` and
  skip it when true (safe, because if the collector reclaimed the object,
  nothing reachable, including a parent's child list, was still pointing at
  it). Apply this to every class whose destructor reaches into other objects.
  Likewise, a widget deleting itself from inside its own callback (`delete
  this;` in C++) must call `fl.core.deleteWidget(this)`, not `destroy(this)`.
- **D does not unwind the vtable during destruction; C++ does.** In C++ a
  virtual call made from a base class's destructor dispatches to the base's
  own method, because the vtable pointer is rewound as each destructor in the
  chain runs. In D an object keeps one vtable for its whole lifetime, so a
  virtual call from a base `~this()` still reaches the most-derived override.
  FLTK sometimes relies on the C++ behavior: `Fl_Scroll` protects its built-in
  scrollbars from `Fl_Group::clear()`'s child-deletion sweep with a
  `delete_child()` override, and because that cannot be reached from
  `~Fl_Group()` it also hand-removes the scrollbars a second time in
  `Fl_Scroll::clear()` and `~Fl_Scroll()`. None of that duplication is needed
  here: `Group.clear()` and `Group.~this()` call `deleteChild()` virtually, so
  a single override suffices. Do not transliterate the extra C++-only
  defensive copies, but check whether D already provides the protection before
  adding them.
- **D does not build up the vtable progressively during construction; C++
  does.** In C++, while a base class constructor body runs, virtual calls
  dispatch to that base's own methods. In D the vtable is the most-derived
  class's from the moment `new Derived(...)` begins, so a virtual call from
  inside `Base`'s constructor already reaches `Derived`'s override, even
  though `Derived`'s fields are not initialized yet. `fl.table.Table` hit this
  for real: `Group`'s constructor calls `begin()`, and constructing `Table`'s
  own scrollbars triggers `Widget`'s auto-parenting (`Group.current().add(this)`,
  dispatched virtually), so `Table`'s overrides of `begin()`/`add()`/
  `children()`/etc. ran before its nested `table_` container existed and
  dereferenced null. Every such override is guarded on `table_ !is null` and
  falls back to `super`. Any class that overrides a method its base class's
  constructor calls (directly, or through another object's constructor
  reaching back in) must account for this; see `fl.table`'s "Child group
  management" section for a worked example.
- **D module-level variables are thread-local by default; C++ globals are
  shared across threads.** A plain module-scope `Terminal tty1;` gives each
  `core.thread.Thread` its own separately initialized copy, so writes made by
  one thread are invisible to another, which sees the type's `.init` value
  (`null` for a class reference). `source/test/threads.d` hit this: workers
  read their own `null` copies, a comparison silently became `null is null`,
  and the program deadlocked. Mark globals that need cross-thread visibility
  `__gshared`.
- **A `core.thread.Thread` that never returns needs `isDaemon = true`.** In
  C++, `main()` returning calls `exit()`, killing every thread regardless of
  joins, so a worker with an intentional `for(;;)` is harmless. druntime's
  shutdown path calls `thread_joinAll()`, which blocks on every non-daemon
  thread, so such a worker hangs the process after `main()` returns. Set
  `t.isDaemon = true;` before `.start()` to restore FLTK's "process exit kills
  everything" semantics.
- **Shared static state needs hermetic tests.** `Group.current()`/`begin()`/
  `end()` use a single process-wide static, and every `Group` constructor
  calls `begin()`. A `unittest` that constructs a `Group` and does not reset
  `Group.current(null)` leaks that group into the next test's widget
  construction, which silently auto-parents into it. Start (and ideally end)
  any test touching `Group` with `Group.current(null);`. `fl.core` has the
  same problem for its event-state globals and for the default callback queue
  behind `readqueue()`; call **`core.resetForTest()`** at the end of any test
  that exercises `handle()`, drag-and-release or `doCallback()`.
- **Demo and test programs name constants the way a D programmer types
  them.** Where a sample displays the name of a constant in its UI (a menu of
  box types, a table of key names), it uses fldtk's own bare D spelling
  (`Boxtype.noBox`, `rgbAliceBlue`), not FLTK's C macro name (`FL_NO_BOX`),
  because the point of such text is to show what to write in D.
- **Port the real surface, not just the part a sample happens to call.** A
  module is ported in full (the whole GLUT compatibility layer, for example),
  not as the subset the current demos need: demo-scoped coverage leaves gaps
  that only show up later.
- **Modules that are intentionally not a complete port** say so in a comment
  at the top, list what is missing and point at the FLTK file with the real
  logic. Source comments are written as plain, current facts about the code,
  and a gap that has been filled must not leave a stale "TODO" or "stub"
  comment behind.

## Platform scope

The primary targets are **Linux X11 and Wayland**; **Windows** is secondary.
macOS is out of scope for testing (no hardware available), though the driver
abstraction should still leave room for a Cocoa backend later, matching
FLTK's own structure. Only X11 and Windows drivers exist so far.

This applies to GL too: `fl.gl_window`/`fl.gl_window_driver` cover Linux/X11
(GLX) and Windows (WGL). Wayland's GL story is EGL-based, a genuinely
different API from GLX/WGL, so it waits for a Wayland driver. Cocoa (NSOpenGL)
is out of scope.

## Build commands

See [`BUILDING.md`](BUILDING.md) for the full walkthrough. In summary:
`dub build` builds the library, `dub test` runs the unit tests,
`rdmd buildfluid.d` builds Fluid and `rdmd buildsamples.d [test|examples]
[name]` builds the demo programs.

Fluid's own interface panels (`source/fluid/panels/*.fl`) are its primary
source, the same self-hosting model FLTK uses for its own panels. The
`source/fluid/panels/generated/*.d` files are `fluid -c` output: generated
rather than checked in, rebuilt by `rdmd buildfluid.d`, and edited only by
editing the `.fl` and regenerating. Before authoring or editing a `.fl` file,
read [`FLUID_DIALECT.md`](FLUID_DIALECT.md); before converting a raw C++ `.fl`
file, read [`TRANSLITERATION_GUIDE.md`](TRANSLITERATION_GUIDE.md).
