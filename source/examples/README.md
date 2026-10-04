# Example programs

D transliterations of FLTK's `examples/` directory. These programs
meant to demonstrate good, idiomatic usage of the fldtk API, as distinct
from `source/test/` (a much larger set of programs whose job is closer
to stress-testing widget behavior and correctness, transliterated from
FLTK's `test/`). The `*_simple.d` files are the best starting
point if you're new to fldtk.

These programs are not built as part of `dub build`; see "Building"
below.

## Building

```
rdmd buildsamples.d examples              # every example
rdmd buildsamples.d examples table_sort   # a single one, by name
```

Binaries land in `build/` under their own name (`build/table_sort`,
...). A program is simply a `.d` file here that defines `main()` —
there is no manifest and nothing to register; add a file and it is
picked up on the next run. See `BUILDING.md` at the repo root for the
full build model, including how a helper module shared between several
examples (there are currently none in this directory, unlike
`source/test/`) gets pulled in automatically.

One example, `fluid-callback.fl`, is Fluid source rather than a
hand-written `.d` file. Its D output is regenerated into
`generated/fluid_callback.d` (gitignored) as needed, the same way
Fluid-backed programs under `source/test/` work.

## Naming conventions

Matching FLTK's own convention, with `-` replaced by `_`
throughout (D file/module names can't contain a hyphen, unlike C++
filenames):

    xxx_simple.d          Simplest possible example of widget xxx,
                           e.g. table_simple.d

    xxx_<technique>.d     A particular technique using widget xxx,
                           e.g. table_spreadsheet.d

    howto_<technique>.d   Demonstrates a technique not tied to one
                           widget, e.g. howto_drag_and_drop.d

A widget with several distinct uses worth showing separately gets one
file per use rather than one do-everything file. See the `table_*.d`
and `tree_*.d` families here for the pattern.

## Adding a new example

Keep it short and idiomatic: clear enough to read top to bottom, using
the fldtk API the way a real application would, not exercising every
edge case (that's what `source/test/` is for). If you're transliterating
a new program from FLTK's own `examples/`, see
`TRANSLITERATION_GUIDE.md` at the repo root for the conventions this
project already follows for that.

## Bugs

Found one? Please report it:
https://github.com/sxmboer/fldtk
