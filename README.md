# fldtk

**fldtk** (Full-D-toolkit) is a complete port of [FLTK](https://www.fltk.org/), the
Fast Light Toolkit GUI system, to the D programming language. It is not a binding layer: the
toolkit is reimplemented as native D code, so the only things it links against are
the system's own libraries (Xlib, OpenGL, ...), not a compiled FLTK. It also
includes a port of Fluid, FLTK's UI designer, which exports D source files
instead of C++.

fldtk has the look and feel of FLTK, and its API follows FLTK's closely,
expressed in idiomatic D: callbacks are delegates, labels are `string`s, memory is
garbage-collected, and `Fl_Widget` is `fl.widget.Widget`.

## Direction

Release **v1.0.2** is the version that resembles FLTK as closely as
possible. If you know FLTK and want an easy move to D, use that release.

From here on, fldtk goes its own way. Later releases are for D programmers
who are new to GUI programming and want the ease of a graphical designer,
presented in the simplest, easiest-to-understand way, much like what Visual
Basic did for many people in its day. The rule is KISS: keep it simple.
Where FLTK's way and a simpler way differ, the simpler way wins, so expect
fldtk to move away from FLTK over time.

Simple also means portable: a program written with fldtk, or designed in
Fluid, builds and runs from the same source on Linux and Windows, without
platform-specific code in the program and without extra libraries to
install beyond what the system provides.

## Example

``` D
import fl;
import std;

void main()
{
  auto win = new Window(100, 100, 400, 300, "fldtk smoke test: Button");
  auto btn = new Button(20, 20, 360, 260, "Click!"); // auto-parents into win (Group.current())
  win.end(); // not really needed here
  win.show();

  fl.run();
}
```

which produces a window with a clickable button.

<img width="412" height="333" alt="button" src="https://github.com/user-attachments/assets/c1d54510-d5fb-4408-87cd-b63c48e08104" />

## Status

The library and Fluid run stably on **Linux/X11**, **Linux/Wayland** and
**Windows**; Linux binaries pick Wayland or X11 at run time. macOS is out
of scope for now because I don't have the hardware to test it.

Highlights of v1.0.3:

- **Wayland support is now ahead of FLTK's.** fldtk's native Wayland driver needs no
  libdecor (thereby eliminating dependence on GTK): it draws its own
  title bar where the compositor leaves that to the program, showing only
  the buttons the compositor supports. Fractional desktop scales are drawn
  exactly instead of scaled down from the next whole number, window icons
  work through xdg-toplevel-icon, `fl_beep()` rings the desktop's bell, the
  clipboard reports changes made by other programs, and OpenGL runs through
  EGL. Pen and touch input work on Wayland too; FLTK has no touch support
  there at all.
- **Multi-monitor setups with different scale factors per monitor**
  (Wayland and Windows), as well as manual scaling using CTRL--/CTRL-+ should work
  flawlessly now on all platforms.
- **Multi-touch screens and pens.** Every finger on a touchscreen can be
  followed on its own, one finger acts as the mouse, and pinch, turn,
  two-finger scroll and touchpad swipe gestures arrive as events, on
  Windows, Wayland and X11. Pens and tablets report pressure, tilt, twist,
  hover and the eraser on Windows and Wayland. fldtk has its own unique
  driver support and API for these devices (departure from FLTK).
- **Updated, modern looks.** Since v1.0.3 every icon and picture fldtk and
  Fluid draw themselves is SVG: Fluid's icons, app icon, logo and panel
  tabs, the file chooser, help viewer and adjuster glyphs, cursors and the
  print dialog's pictures. They look clean on any monitor, at any desktop
  scale or zoom.
- **Fluid speaks D only.** A widget's code sections are reduced to the
  ones that mean something in D: `setup`, and `finalize` for code that
  runs after a group's or window's children are built. FLTK's `#include`
  and declare sections, which only fill a C++ header file, are gone.
- **Every FLTK demo, plus new ones.** All of FLTK's test and example programs
  are transliterated to D and run in fldtk (`source/test/`,
  `source/examples/`), except the one for the long-obsolete XForms
  compatibility layer. New demos show what fldtk adds: `pen_test`,
  `touch_test`, `svg_animation`, and `fluid-callback.fl` for building a
  complete program in Fluid.

What is in the box:

- **Widgets:** buttons, valuators and sliders, menus, text input and editing,
  browsers, tables, trees, tabs, scroll, pack, flex and grid layouts, a help
  viewer, a terminal widget, file choosers, dialogs, and the rest of FLTK's
  widget set, with FLTK's box types and schemes (base, gtk+, gleam, plastic, oxy).
- **Fluid**, both the interactive designer and the headless
  `fluid -c file.fl` converter that writes D source.
- **Images**, decoded natively in D: PNG, JPEG, GIF (including animated), SVG,
  BMP, ICO, XPM, XBM and PNM.
- **OpenGL** windows (with FLTK widgets drawn over them) and the GLUT
  compatibility layer.
- **Platform services:** clipboard, drag and drop, multi-monitor and scaling
  support, input methods, pen and touch input, and printing.
- **Cairo and Pango:** `CairoWindow` and the full Cairo and Pango APIs, built
  in on Linux and optional on Windows (see [`BUILDING.md`](BUILDING.md)).
  fldtk itself draws through Cairo, with text through Pango, on Wayland,
  and on X11 when asked to (`FLDTK_GRAPHICS=cairo`).

[`PORTING.md`](PORTING.md) tracks the port file by file: what is complete, what
is partial and why, what is deliberately left out, and what a platform such
as Wayland doesn't allow. Suspected bugs in FLTK
itself, found while porting, are collected in [`FLTK_ISSUES.md`](FLTK_ISSUES.md).

## Building

You need a D compiler (dmd, ldc or gdc) and `dub`. On Linux the development
packages for X11, Xft, Xinerama, fontconfig, Xcursor, Xfixes, Xext, Xi, OpenGL,
GLU and zlib must be installed, which is the case by default on most
Linux distributions. Then, from the repository root:

    dub build              # the library: ./libfldtk.so
    rdmd buildfluid.d      # the Fluid designer: ./fluid
    rdmd buildsamples.d    # the demo programs: ./build/*

[`BUILDING.md`](BUILDING.md) has the details, including how to compile your own
programs against the library and the Windows instructions.
It should be mentioned that dmd and gdc have both been tested to work. ldc has not been tested.

## Documentation

- [`BUILDING.md`](BUILDING.md): building and using the library, Fluid and the samples
- [`PORTING.md`](PORTING.md): porting status, module by module
- [`CONVENTIONS.md`](CONVENTIONS.md): how FLTK maps onto D, and the design decisions behind it
- [`FLUID_DIALECT.md`](FLUID_DIALECT.md): the `.fl` dialect Fluid reads and writes for D
- [`TRANSLITERATION_GUIDE.md`](TRANSLITERATION_GUIDE.md): converting FLTK's C++ `.fl` files to D
- [`BENCHMARKS.md`](BENCHMARKS.md): performance comparisons with FLTK. This document is not very up to date

## Contributing

Bug reports and pull requests are welcome. Where fldtk behaves differently from
FLTK, it may or may not have been by design. Deliberate deviations from FLTK should
have been documented clearly in the source or in PORTING.md.

## License

[Boost Software License 1.0](LICENSE_1_0.txt).
