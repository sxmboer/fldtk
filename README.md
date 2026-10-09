# fldtk

**fldtk** (Full-D-tick) is a complete port of [FLTK](https://www.fltk.org/), the
Fast Light Toolkit GUI system, to the D programming language. It is not a binding layer: the
toolkit is reimplemented as native D code, so the only things it links against are
the system's own libraries (Xlib, OpenGL, ...), not a compiled FLTK. It also
includes a port of Fluid, FLTK's UI designer, which exports D source files
instead of C++.

fldtk has the look and feel of FLTK, and its API follows FLTK's closely,
expressed in ordinary D: callbacks are delegates, labels are `string`s, memory is
garbage-collected, and `Fl_Widget` is `fl.widget.Widget`.

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

The library and Fluid run stably on **Linux/X11** and on **Windows**. A
**Linux/Wayland** driver has not been started yet; macOS is out of scope for now because
I don't have the hardware to test it.

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
  support, input methods, and printing.
- FLTK's demo and example programs, ported to D (`source/test/`,
  `source/examples/`).

The main known gaps are the Wayland driver, a Cairo backend, and complex-script
text shaping (text is drawn through Xft; replacing it with Pango is planned).
[`PORTING.md`](PORTING.md) tracks the port file by file: what is complete, what
is partial and why, and what is deliberately left out. Suspected bugs in FLTK
itself, found while porting, are collected in [`FLTK_ISSUES.md`](FLTK_ISSUES.md).

## Building

You need a D compiler (dmd, ldc or gdc) and `dub`. On Linux the development
packages for X11, Xft, Xinerama, fontconfig, Xcursor, Xfixes, Xext, OpenGL,
GLU, GLEW and zlib must be installed, which is the case by default on most
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
FLTK, it may or may not have been by design. Deliberatre deviations from FLTK should
have been documented clearly in the source or in PORTING.md.

## License

[Boost Software License 1.0](LICENSE_1_0.txt).
