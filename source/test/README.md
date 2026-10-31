# Test programs

D versions of FLTK's `test/` programs, plus fldtk's own (see "Programs
not in FLTK" below) — a much larger, more
exhaustive set of programs than `source/examples/`, whose job is
closer to stress-testing widget behavior and edge cases than
demonstrating clean API usage. Many of these were written to reproduce
or guard against a specific bug, or to exercise a corner of a widget's
behavior a typical application would never touch.

Not every program here is meant to be *read* as a good example of how
to write an fldtk application — some intentionally do unusual things
to probe a specific behavior. If you're looking for idiomatic usage
examples instead, see `source/examples/`.

## Building

```
rdmd buildsamples.d test          # every test program
rdmd buildsamples.d test cube     # a single one, by name
```

Binaries land in `build/` under their own name (`build/cube`, ...). A
program is simply a `.d` file here that defines `main()` — there is no
manifest and nothing to register; add a file and it is picked up on
the next run. See `docs/BUILDING.md` at the repo root for the full build
model, including how a helper module shared between several programs
(`CubeView.d`, `checkers_pieces.d`, `fracviewer.d`, `resize_arrows.d`)
gets pulled in automatically.

One program is knowingly skipped, printing why when you build: `forms`
(the XForms compatibility layer, out of scope for this port). On
Windows, `list_visuals` (it lists X11 visuals) is skipped too.

## Programs not in FLTK

- `svg_animation`: SVG images that move. Each frame the program writes
  the SVG text for what should be on screen and shows it as a new
  `SvgImage`, so the pictures (a wind gauge following a slider, and a
  sea at sunset whose waves grow with the wind) stay sharp at any scale.
- `gl_capture`: captures a single-buffered and a double-buffered window,
  each holding GL subwindows, three ways (`captureWindow()`,
  `ImageSurface.draw()`, printing), to show which paths include the GL
  pixels.
- `svg_gradients`: SVG gradients in bounding-box units, rotated, scaled
  and moved with `gradientTransform`, each labelled with how it should
  look.
- `gl_text`: text in a GL window, through textures or through the
  platform's bitmap fonts (switched while it runs), and rotated text
  drawn both in a plain window and over a GL scene.
- `value_wheel`: every value widget, changed with the mouse wheel (10
  steps a notch, 1 with Shift, 100 with Ctrl), with a readout of the
  last change.

## The `unittests` program

`unittests.d` plus its 14 `unittest_*.d` tab files together form one
program (`build/unittests`) — a browsable GUI harness of small,
focused widget tests, not to be confused with this project's own
`dub test` (Phobos-style `unittest {}` blocks in `source/fl/`). See
`README-unittests.md` for how to add a new tab.

Unlike every other multi-file program here, the tabs don't get pulled
in by `dmd -i` automatically — each one self-registers into
`unittests.d`'s registry via a module constructor
(`static this() { new UnitTest(...); }`) rather than being imported by
it, so there's no import edge to follow. `buildsamples.d` knows to
include `unittest_*.d` explicitly for this one program; see that
script's own `extraSources` table.

## Naming conventions

Matching FLTK's own convention, with `-` replaced by `_` throughout (D
file/module names can't contain a hyphen, unlike C++ filenames) — see
`source/examples/README.md`'s own "Naming conventions" section for the
full pattern (`xxx_simple.d`, `xxx_<technique>.d`, `howto_<technique>.d`).
Most files here are simply named after the widget or feature they
exercise (`table.d`, `scroll.d`, `clipboard.d`, ...).

## Bugs

Found one? Please report it:
https://github.com/sxmboer/fldtk
