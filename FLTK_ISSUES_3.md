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
| Help dialog's Find keeps finding the same match | Yes, at `3a049d826` | Open |
| Cairo text sits too low on a line with a CJK or emoji character | Not yet | Open |
| `Fl_Text_Display` without a style table highlights marked text as well as underlining it | Not yet | Open |
| `Fl_Group::draw_child()` skips a group whose children's outside labels reach into the clip | Not yet | Open |
| `Fl_Float_Input` refuses a pasted `1e5` that can be typed | Not yet | Open |

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

### `Fl_Help_Dialog` find callback (`src/Fl_Help_Dialog.fl` line 123): Find keeps finding the same match

**Reproduced in FLTK:** Yes, at `3a049d826`: in FLTK's help dialog,
pressing Enter in the find field again stays on the same match.

**FLTK status:** Open at `3a049d826`.

The callback is `find_pos_ = view_->find(find_->value(), find_pos_);`.
`Fl_Help_View::find(s, p)` searches from byte offset `p` inclusive and
returns the offset where the match starts, so the next Find starts at that
same match and returns it again: pressing Enter in the find field never
moves past the first match after the current position.

**Deviated from in the port**: `fl.help_dialog`'s `findCB()` continues at
the match's offset plus one, and starts over at 0 after the last match.

### `Fl_Cairo_Graphics_Driver::draw(const char*, int, float, float)` (`src/drivers/Cairo/Fl_Cairo_Graphics_Driver.cxx` line 1241): text sits too low on a line with a fallback-font character

**Reproduced in FLTK:** Not yet. Seen in fldtk, whose Cairo driver
placed text the same way: in `build/editor` with `FLDTK_GRAPHICS=cairo`,
a line starting with 京 had the bottom pixels of every character cut off,
and an underscore drew as a space.

**FLTK status:** Open.

The text is placed by translating up by `fd->ascent`, the ascent of the
font's fontset metrics, on the assumption that the layout's baseline is
that far below its top. Pango lays a line out with the largest ascent of
the fonts it actually uses, so a character taken from a fallback font
with a larger ascent (CJK, emoji) moves the baseline down: for "Sans 14px",
`pango_layout_get_baseline()` is 15 px for `R@390_` and 17 px for `京_`.
Everything on such a line is drawn that much below the requested
baseline, and a widget that clips to its line height (`Fl_Text_Display`,
`Fl_Input`) cuts off the bottom. `text_extents()` has the same offset in
its `dy`.

**Deviated from in the port**: `fl.cairo_graphics_driver`'s `showText()`
and `textExtents()` use `pango_layout_get_baseline()` of the layout being
drawn.

### `Fl_Text_Display::draw_string()` (`src/Fl_Text_Display.cxx` lines 2383-2412): marked text highlighted and underlined without a style table

**Reproduced in FLTK:** Not yet. Found by reading the source.

**FLTK status:** Open.

With a style table, a primary selection in a focused display gets the
plain background while there is marked text (`has_marked_text() &&
Fl::compose_state`, line 2385), so the input method's provisional text
shows only the underline drawn at line 2485. The branch for a display
without a style table (`else if (style & PRIMARY_MASK)`, line 2409) has
no such test: there the marked text gets `selection_color()` behind it
and the underline as well. On Wayland, typing a dead key or composing
with an input method in a plain `Fl_Text_Editor` shows the provisional
text highlighted like a selection.

**Deviated from in the port**: `fl.text_display`'s `drawString()` uses the
plain background for marked text in both branches.

### `Fl_Xlib_Graphics_Driver::pie_unscaled()` (`src/drivers/Xlib/Fl_Xlib_Graphics_Driver_arci.cxx` line 39) and `Fl_GDI_Graphics_Driver::pie_unscaled()` (`src/drivers/GDI/Fl_GDI_Graphics_Driver_arci.cxx`): a pie grows with the line width

**Reproduced in FLTK:** Not yet. Seen in fldtk's port of the same code
(`source/test/arc_width.d`).

**FLTK status:** Open.

On X11 a pie is drawn as `XDrawArc()` plus `XFillArc()`, and the
`XDrawArc()` uses the GC's current line width and dashes. GDI's `Pie()`
strokes its edge with the selected pen. After `fl_line_style(FL_SOLID, 8)`
a `fl_pie()` is therefore about 8 pixels larger than the same pie drawn
with the default line, while the Cairo and GDI+ drivers only fill it and
keep it the same size. A pie is a fill, so its size should not depend on
the line style.

**Deviated from in the port**: `fl.draw`'s `fl_pie()` (X11) and
`fl.gdi_graphics_driver`'s `pieUnscaled()` draw the edge with the default
line and put the line style back afterwards.

### `Fl_Group::draw_child()` and `update_child()` (`src/Fl_Group.cxx` lines 944-965): a child group is skipped although its children's outside labels reach into the clip

**Reproduced in FLTK:** Not yet. Seen in fldtk's port of the same code:
Fluid's Settings dialog after dragging another window across it, and
`smoke-tests/group_label_overhang.d`.

To test it in FLTK, save this program as `group_label_overhang.cxx`, the
FLTK version of `smoke-tests/group_label_overhang.d`:

```cpp
#include <FL/Fl.H>
#include <FL/Fl_Window.H>
#include <FL/Fl_Group.H>
#include <FL/Fl_Input.H>
#include <FL/Fl_Button.H>

static Fl_Window *win;
static Fl_Group *group;
static Fl_Input *input;

static void change_cb(Fl_Widget *, void *) {
  input->label(input->label()[0] == '1'
               ? "2222 this label reaches out of its group:"
               : "1111 this label reaches out of its group:");
  // Repaint only the strip left of the group.
  win->damage(FL_DAMAGE_ALL, 0, group->y(), group->x(), group->h());
}

int main(int argc, char **argv) {
  win = new Fl_Window(520, 200, "Group label overhang");
  group = new Fl_Group(260, 30, 240, 80);
  group->box(FL_ENGRAVED_FRAME);
  input = new Fl_Input(330, 55, 150, 25, "1111 this label reaches out of its group:");
  group->end();
  Fl_Button *change = new Fl_Button(20, 150, 140, 30, "Change label");
  change->callback(change_cb);
  win->end();
  win->show(argc, argv);
  return Fl::run();
}
```

Build it against the local FLTK build and run it:

    B=~/Repositories/fltk/build
    c++ -I$B -I$HOME/Repositories/fltk -o group_label_overhang group_label_overhang.cxx -L$B/lib $($B/bin/fltk-config --ldflags)
    ./group_label_overhang

Press "Change label". Only the strip left of the group's frame is
repainted. If the bug is in FLTK, the label's start (the part left of the
frame) goes blank, and the label reads only from the frame onwards.

**FLTK status:** Open.

Both functions draw a child only if `fl_not_clipped()` is true for the
child's own box. When the child is an `Fl_Group`, its `draw_children()`
draws the outside labels of its own children in the space between each
child and the group's edge. A label larger than that space overflows it,
and its text then lies outside the group's box. A repaint of only that
area (an expose from a window dragged across it, or a
`damage(FL_DAMAGE_ALL, x, y, w, h)` of it) clears the background there but
never draws the label, since the group is clipped away; the area stays
blank until a larger repaint.

**Deviated from in the port**: `fl.group`'s `drawChild()`/`updateChild()`
also draw a group that doesn't clip its children when one of its
children, or such a child's outside label measured with
`measureLabel()`, is in the clip (`paintsInClip()`).

### `Fl_Input_::handle()` `FL_PASTE` (`src/Fl_Input_.cxx` lines 1273-1291): `Fl_Float_Input` refuses a pasted number that can be typed

**Reproduced in FLTK:** Not yet. Found reading fldtk's port of the same
code (`fl.input_.Input_.handle()`, `Event.paste`), which matches FLTK
line for line.

**FLTK status:** Open at `3a049d826`.

Typing into an `Fl_Float_Input` checks each character on its own
(`Fl_Input::handle_key()`, `src/Fl_Input.cxx` line 397): digits, the
characters of `legal_fp_chars` (`.eE+-`, plus the locale's decimal
point and signs when built with `HAVE_LOCALECONV`), and `0x` followed by
hex digits. Pasting checks the whole text against a number pattern
instead: an optional sign, digits, and only then an optional `.`
followed by digits and an optional exponent. The exponent is only looked
for inside the `if (*p == '.')` branch, so:

- `1e5` can be typed but not pasted (beep, nothing inserted), while
  `1.e5` and `1.0e5` paste;
- `0x1F` can be typed but not pasted;
- with a locale whose decimal point is `,` (`HAVE_LOCALECONV` and
  `setlocale(LC_NUMERIC, ...)`), `1,5` can be typed but not pasted.

`strtod()` accepts all of these, so the paste check is stricter than
both the typing check and the conversion the value goes through. Moving
the exponent test out of the `.` branch fixes the first case; the other
two need the paste check to accept what the typing check does.

To test it in FLTK, save this program as `float_input_paste.cxx`:

```cpp
#include <FL/Fl.H>
#include <FL/Fl_Window.H>
#include <FL/Fl_Float_Input.H>
#include <FL/Fl_Output.H>

int main(int argc, char **argv) {
  Fl_Window win(340, 110, "Float input paste");
  Fl_Output source(110, 20, 200, 25, "Copy from:");
  source.value("1e5   1.e5   0x1F");
  Fl_Float_Input input(110, 60, 200, 25, "Paste into:");
  win.end();
  win.show(argc, argv);
  return Fl::run();
}
```

Build it against the local FLTK tree:

    B=~/Repositories/fltk/build
    c++ -I$B -I$HOME/Repositories/fltk -o float_input_paste float_input_paste.cxx -L$B/lib $($B/bin/fltk-config --ldflags)

Run it, select `1e5` in the top field, copy it with Ctrl+C, click the
bottom field and paste with Ctrl+V: it beeps and stays empty. Typing
`1e5` there works. Selecting and pasting `1.e5` works; `0x1F` is
refused like `1e5`.

**Not yet fixed in the port**: `fl.input_.Input_.handle()` has the same
check.
