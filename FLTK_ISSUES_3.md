# FLTK issues found while porting (third batch)

Entries found after the previous batch was shared with the FLTK team. New
entries go here, in the newest `FLTK_ISSUES_n.md`.

## Process

- An entry names the FLTK file and line, what is wrong, and why.
- **Reproduced in FLTK** says whether the bug has been shown in FLTK
  itself, built from a recent git pull of `~/Repositories/fltk`, rather
  than only read in its source or observed in fldtk's port of it:
  - **Yes, at `<commit>`**: an FLTK program built from that commit shows
    the bug. The entry says which program and what to do.
  - **No**: tried at that commit and it doesn't show. The entry says
    what was tried; the bug is then fldtk's own, or needs another setup.
  - **Not yet**: found by reading the source or seen in fldtk only.

  An entry is shared with the FLTK team only once it reads **Yes**.
- **FLTK status** is the outcome on FLTK's side: Open, Reported (with a
  link), Fixed (with the commit), or Not a bug.
- Nothing is filed on FLTK's tracker without explicit review first —
  filing is a visible action on a project fldtk doesn't maintain.
- Once an entry's outcome is known, its entry is updated rather than
  deleted.

| Entry | Reproduced in FLTK | FLTK status |
|---|---|---|
| `capture_gl_rectangle()` reads the back buffer after the swap | Not yet | Open |
| nanosvg applies `gradientTransform` after fitting an `objectBoundingBox` gradient to the shape | Not yet | Open |

### `Fl_Gl_Window_Driver::capture_gl_rectangle()` (`src/Fl_Gl_Window.cxx`): reads the back buffer after the swap

**Reproduced in FLTK:** Not yet. Seen in fldtk, whose capture was a
line-for-line port of this function: on X11 at a scale of 120%, the first
capture of a GL window came back black (or as an older frame) and a
second capture was right (`build/gl_capture`, "captureWindow()" pressed
twice).

**FLTK status:** Open at `3a049d826`.

`capture_gl_rectangle()` (lines 591-627) calls `glw->flush()`, which
draws a frame into the back buffer and swaps it to the screen, and then
calls `glReadPixels()`. For a double-buffered context the read buffer is
`GL_BACK`, whose contents after `swap_buffers()` are undefined: with a
flipping swap it holds the previous frame, or nothing yet after a
resize. Reading before the swap gives the frame just drawn.
`fl_capture_window()`, printing and image surfaces all reach GL through
this function.

**Deviated from in the port**: `fl.gl_window.flushGlWindow()` takes a
callback that runs after drawing and before the swap, and
`captureGlRectangle()` reads its pixels there.

### `nsvg__createGradient()` (`nanosvg/nanosvg.h`): `gradientTransform` applied after the bounding-box mapping

**Reproduced in FLTK:** Not yet. Found reading the source; fldtk's port
behaved the same before the fix: with
`<linearGradient x1="0" x2="1" gradientTransform="rotate(90)">` on
`<rect x="10" y="20" width="100" height="40">`, the gradient runs top to
bottom but covers only 0.1 to 0.5 of its range, instead of 0 to 1. nanosvg is vendored by FLTK, so this may belong
upstream of FLTK, at github.com/memononen/nanosvg.

**FLTK status:** Open at `3a049d826`.

In `gradientUnits="objectBoundingBox"` (the default) the SVG specification
lays the gradient out in the shape's bounding-box units, applies
`gradientTransform` there, and then maps the box onto the shape.
`nsvg__createGradient()` (lines 821-904) first converts the gradient's
coordinates to user space with the box (lines 856-892), then multiplies
`data->xform` (line 896): the transform acts in user space, so a
`rotate(90)` turns the gradient about the user-space origin rather than
the box's corner in box units, and its length is the box's width
where the specification gives the height. A radial gradient's radius is scaled by the
box's diagonal (`sl`, line 867), so on a non-square shape it stays a
circle where the specification gives an ellipse.

**Deviated from in the port**: `fl.nanosvg.createGradient()` builds the
gradient in box units, multiplies `gradientTransform`, then the box, then
the shape's transform.

