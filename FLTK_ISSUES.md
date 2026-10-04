# Upstream FLTK issues found while porting

Reading upstream source line-by-line to port it (rather than skimming docs)
occasionally turns up things in `~/Repositories/fltk` that look like genuine
upstream bugs or inconsistencies, as opposed to behavior this port needs to
replicate faithfully. This file tracks those candidates.

Process:

- When something looks off while porting, add it here with the upstream
  file/line, what looks wrong, and why. Don't fix it in the port unless the
  port's own correctness requires deviating (and if so, say so explicitly in
  the D module's comments, same as any other intentional deviation).
- Entries here are **candidates**, not confirmed bugs. Verify against
  upstream's actual runtime behavior and issue tracker before reporting
  anything upstream.
- Nothing gets filed on FLTK's tracker without explicit review first —
  filing is a visible action on a project we don't maintain.
- Once a candidate is filed (or confirmed not-a-bug, or fixed upstream),
  update its entry with the outcome rather than deleting it.

## Candidates

### `Fl_Window_Driver::resize_after_scale_change()` (`src/Fl_Window_Driver.cxx`): truncating cast drifts window position by 1px per rescale, always toward top-left

```cpp
int X = int(pWindow->x() * old_f / new_f), Y = int(pWindow->y() * old_f / new_f);
```

`int(...)` truncates toward zero rather than rounding to nearest. For a
window at a positive on-screen coordinate, truncation only ever discards a
fractional pixel, never adds one back — so repeatedly toggling the screen
scale (e.g. Ctrl-`+`/Ctrl-`-`/Ctrl-`+`) doesn't average out to zero error,
it can only ever drift the window one pixel left and/or up per rescale,
never right or down. Confirmed on real multi-monitor hardware side by side
against a real, unmodified FLTK build: both drift identically, one pixel
at a time, in the same direction, on the same rescale sequence — this is a
genuine shared quirk, not an artifact of anything this port does
differently (`fl.window.Window.resizeAfterScaleChange()` ported this exact
line as `cast(int)(x() * oldF / newF)`, byte-for-byte).

**Status: not verified against FLTK's issue tracker.** **Deviated from in
the port**: `Window.resizeAfterScaleChange()` (`fl.window`) doesn't
recompute a device-pixel target for the window's top-left corner at all,
since that corner isn't supposed to move. It reads the window's confirmed
on-screen device-pixel position directly (`devicePosX_`/`devicePosY_`,
kept current by `fl.platform_x11`'s `ConfigureNotify` handling), and *when no
screen-boundary clamping is required* — the ordinary case — puts the
window back at that same device-pixel position by construction. Rounding
a recomputed FLTK-unit `X`/`Y` (even with `lround()` rather than a
truncating `cast(int)`) can't do this: an integer FLTK-unit position
can't represent every device-pixel value once the scale isn't a
whole-number ratio, so it leaves occasional ±1px jitter. `x()`/`y()`
bookkeeping is still updated, via one `lround()` conversion of the
*unchanged* device-pixel position under the *new* scale.

The position is requested explicitly rather than omitted: sending a
size-only `XResizeWindow()` and relying on X11's window gravity to leave
the top-left corner alone does not work, because a real window manager
resizes the window *about its centre* instead, substituting its own
placement heuristic for the unspecified position (every corner moves by
`old_centre − new_size/2`). So `exactDeviceX_`/`exactDeviceY_` make
`resize()` issue a real move (`XMoveResizeWindow()`) with the exact,
already-known device-pixel coordinates passed straight through
(`platformX11.resizeWindow()`'s `exactDevX`/`exactDevY` parameters,
bypassing `scaledPos()`'s FLTK-unit recomputation for position only).
An explicit, authoritative position command leaves the window manager
nothing unspecified to apply a heuristic to.

FLTK has no equivalent: this is a deliberate improvement beyond its
algorithm, not just a rounding-convention swap. Only the (rare)
screen-boundary-clamped case and the fullscreen case still use the
approximate `lround()`-based conversion, since those genuinely have to
move/resize to a value that doesn't already exist on screen.

### `fl_box_table` (`src/fl_boxtype.cxx`): inconsistent bg/frame flags for GTK "thin" boxtypes

Found while porting the metrics half of `fl_box_table` to `fl.core.boxTable`
(commit that introduced `boxDx()`/`boxBg()`).

Every other box/frame pair in the table follows the naming convention
consistently: `*_BOX` entries have `flags & 2 == 0` (paints a solid
background) and `*_FRAME` entries have `flags & 2 != 0` (outline only). The
GTK "thin" entries have this backwards:

```
{ fl_gtk_thin_up_box,     1, 1, 2, 2,  3 },   // FL_GTK_THIN_UP_BOX    (flags=3: frame, no bg)
{ fl_gtk_thin_down_box,   1, 1, 2, 2,  3 },   // FL_GTK_THIN_DOWN_BOX  (flags=3: frame, no bg)
{ fl_gtk_thin_up_frame,   1, 1, 2, 2,  1 },   // FL_GTK_THIN_UP_FRAME  (flags=1: has bg)
{ fl_gtk_thin_down_frame, 1, 1, 2, 2,  1 },   // FL_GTK_THIN_DOWN_FRAME (flags=1: has bg)
```

i.e. the `_BOX` variants are flagged as frames and the `_FRAME` variants are
flagged as boxes — looks like the two flags values were swapped by mistake
when these four rows were added. Status: not verified against actual
rendered output; `fl.core.boxBg()` currently reproduces this exactly
(faithful port, see the comment there).

### `fl_box_table`: `FL_OVAL_FRAME` missing the "set" bit

```
{ fl_oval_frame,          1, 1, 2, 2,  2, fl_oval_focus },      // FL_OVAL_FRAME
```

`flags=2` here (bit 0 unset) while every other entry in the table has bit 0
set (`flags` is odd: 1 or 3). Per the table's own doc comment, bit 0 means
"set (fully initialized)". Looks like a plain off-by-one on the flags value
for this one row — probably harmless in practice since nothing currently
reads outside the table for a "not set" boxtype, but inconsistent with every
sibling entry. Status: not verified.

### `fl_box_table`: `FL_PLASTIC_THIN_DOWN_BOX` reuses the non-thin draw function

```
{ fl_plastic_thin_up_box, 2, 2, 4, 4,  1 },   // _FL_PLASTIC_THIN_UP_BOX
{ fl_plastic_down_box,    2, 2, 4, 4,  1 },   // _FL_PLASTIC_THIN_DOWN_BOX
```

The "thin down" row's draw function is `fl_plastic_down_box` — the same
function used for plain `FL_PLASTIC_DOWN_BOX` two rows up — rather than a
distinct thin-variant function (contrast with the "thin up" row right above
it, which does use a distinct `fl_plastic_thin_up_box`). Could be
intentional (no visually distinct "thin" art for the pressed/down plastic
style), could be a copy-paste slip. Status: not verified; this port hasn't
ported the drawing-function-pointer half of the table at all yet, so it
doesn't matter for `fldtk` either way — noted for whenever that part gets
ported.

### `fl_box_table`: `FL_GLEAM_ROUND_UP_BOX`/`DOWN_BOX` reuse the non-round draw functions

```
{ fl_gleam_up_box,        2, 2, 4, 4,  1 },   // _FL_GLEAM_ROUND_UP_BOX
{ fl_gleam_down_box,      2, 2, 4, 4,  1 },   // _FL_GLEAM_ROUND_DOWN_BOX
```

Same pattern as the plastic-thin-down entry above: the "round" gleam
variants draw with the plain (non-round) `fl_gleam_up_box`/`fl_gleam_down_box`
functions. Every other "round" boxtype elsewhere in the table (`roundUpBox`,
`gtkRoundUpBox`, `oxyRoundUpBox`, ...) has its own dedicated round-drawing
function. Status: not verified; same caveat as above re: not yet relevant to
`fldtk` since drawing function pointers aren't ported.

### `Fl_Text_Buffer::text_range()` (`src/Fl_Text_Buffer.cxx:329-365`): doesn't re-clamp `start` after swapping with `end`

Found while porting `fl.text_buffer`'s `textRange()`.

```cpp
char *Fl_Text_Buffer::text_range(int start, int end) const {
  ...
  if (start < 0 || start > mLength) { s = malloc(1); s[0]='\0'; return s; }
  if (end < start) {
    int temp = start; start = end; end = temp;
  }
  if (end > mLength) end = mLength;
  int copiedLength = end - start;
  s = (char *) malloc(copiedLength + 1);
  if (end <= mGapStart) {
    memcpy(s, mBuf + start, copiedLength);   // <- `start` used here, unclamped
  ...
```

`start`'s only bounds check (`start < 0 || start > mLength`) happens *before*
the `end < start` swap. If a caller passes e.g. `text_range(0, -1)` — `start`
(0) passes the initial check, then `end` (-1) `< start` swaps them, leaving
`start = -1`. Nothing re-clamps `start` afterward, so `copiedLength = end -
start` computes as `0 - (-1) = 1` and the subsequent `memcpy(s, mBuf + start,
copiedLength)` reads from `mBuf - 1` — one byte before the allocation.
`remove()` (same file, a few hundred lines down) clamps *both* `start` and
`end` after its own out-of-order swap; `text_range()` only clamps one side.
Looks like a genuine, if narrow, latent OOB-read bug: it requires a caller to
pass an `end` less than 0 (not just less than `start`), which no in-tree
FLTK caller currently does, but nothing in the public API contract rules it
out. Status: not verified against a live crash; `fl.text_buffer.textRange()`
preserves the same input-handling shape (deliberately, per CLAUDE.md's "don't
silently fix upstream bugs" policy) but the consequence differs in the D
port: D's bounds-checked array slicing turns the equivalent access into a
well-defined `RangeError` instead of an out-of-bounds C read, so the *bug
trigger* is preserved faithfully but its *memory-safety consequence* isn't
(this is D's ordinary bounds-checking behavior, not a deliberate workaround
specific to this function).

### `Fl_Text_Buffer::copy()` (`src/Fl_Text_Buffer.cxx:537-572`): `memcpy()` on a self-copy that may overlap

Found while porting `fl.text_buffer`'s `copy()`.

The method's own doc comment (header, `Fl_Text_Buffer.H`) says: "`fromBuf`
source text buffer, **may be the same as this**" — i.e. copying a range of a
buffer's text onto another position *within the same buffer* is documented,
intended usage. But the actual byte transfer uses `memcpy()`:

```cpp
if (fromEnd <= fromBuf->mGapStart) {
  memcpy(&mBuf[toPos], &fromBuf->mBuf[fromStart], copiedLength);
} else if (...) { ... } else { ... }
```

When `fromBuf == this` and the source range `[fromStart, fromEnd)` overlaps
the destination range starting at `toPos`, source and destination alias the
same memory — `memcpy()`'s behavior for overlapping regions is undefined in
C. `memmove()` (available, already used elsewhere in this same file for
`move_gap()`) would be the safe choice for a documented self-copy. Status:
not verified against a live corruption/crash (would need a self-copy with
genuinely overlapping ranges, which may be rare in practice even for
`fromBuf == this` callers); `fl.text_buffer.copy()` uses `memmove()` instead
of `memcpy()` for its three equivalent byte-transfer calls — a strict,
harmless superset (identical result for the non-overlapping case) rather
than a silent behavior change, so this one *is* a deliberate deviation
(documented in the module's own top-of-file comment) rather than a faithful
reproduction of the bug, since reproducing UB isn't meaningfully
"faithful" to begin with.

### `Fl_Text_Display::wrapped_line_counter()` (`src/Fl_Text_Display.cxx`, near line 3739): `next_char()` applied to a line count, not a buffer position

Found while porting `fl.text_display`'s `wrappedLineCounter()` -- the core
continuous-wrap line-counting engine.

At the end of the function, once the scan reaches the end of the buffer
without hitting `maxPos`/`maxLines`:

```cpp
/* reached end of buffer before reaching pos or line target */
*retPos = buf->length();
*retLines = nLines;
if (countLastLineMissingNewLine && colNum > 0)
  *retLines = buf->next_char(*retLines);
*retLineStart = lineStart;
*retLineEnd = buf->length();
```

`Fl_Text_Buffer::next_char(pos)` takes a *byte position into the buffer* and
returns the position of the next UTF-8 character boundary at or after it
(clipped to `length()`). But `*retLines` at this point holds a *line count*
(`nLines`, possibly incremented once more for a final line with no trailing
newline), not a buffer position. Passing a line count into a function that
indexes into the buffer's byte storage and inspects the byte there to decide
UTF-8 sequence length looks like a straightforward type-confusion bug -- this
almost certainly meant `(*retLines)++`/`*retLines = nLines + 1` (bump the
line count by one for the final, newline-less line), not a call to
`next_char()` at all.

In the overwhelmingly common case this happens to produce the same *numeric*
result as `+1` anyway: for any real text buffer of nontrivial length, the
byte at a small integer offset like `nLines` is very likely to be a
plain-ASCII byte (not a UTF-8 continuation/lead byte for anything unusual at
that specific offset), so `next_char(nLines)` typically just returns
`nLines + 1`. But it's not guaranteed -- if the buffer's bytes at that
specific small offset happen to encode a multi-byte UTF-8 sequence, or if the
buffer is shorter than `nLines` bytes (clipping to `length()`), the result
can differ from a plain `+1`, silently miscounting the number of wrapped
lines. Status: not verified against a live miscount (would need a buffer
crafted so this exact offset coincides with specific byte content); ported
verbatim in `fl.text_display.wrappedLineCounter()` (`retLines =
buf.nextChar(retLines);`, with a comment pointing at this entry) rather than
"fixed" to `retLines + 1` -- faithfully reproducing upstream's actual
behavior, bugs included, is this port's whole point, and the fix (if any) is
FLTK's call to make, not this port's.

### `Fl_Grid::widget()` (`src/Fl_Grid.cxx`): off-by-one bounds check allows an out-of-range row/col through to `add_cell()`

```cpp
Fl_Grid::Cell *Fl_Grid::widget(Fl_Widget *wi, int row, int col, int rowspan, int colspan, Fl_Grid_Align align) {
  int child = Fl_Group::find(wi);
  if (child >= children()) return 0;
  if (row < 0 || row > rows_) return 0;
  if (col < 0 || col > cols_) return 0;

  Cell *c = cell(row, col);
  if (!c) {
    c = add_cell(row, col);
  }
  ...
```

`Fl_Grid::cell(row, col)` (the read-only lookup) correctly rejects
`row == rows_`/`col == cols_` with a `>=` check (valid indices are
`0 .. rows_-1`/`0 .. cols_-1`). But `widget()`'s own bounds check just above
uses `>` instead of `>=`, so calling `widget(wi, rows_, 0, ...)` (one row
past the end) passes this check, finds no existing cell via `cell()` (which
correctly returns `0` for the out-of-range row), and falls through to
`add_cell(rows_, 0)`, which does `Row *r = &Rows_[row];` with
`row == rows_` -- one past the end of the `Rows_` array. Same story for
`col == cols_` via `Cols_[col]`. Undefined behavior in C++ (silent
out-of-bounds write, not merely a crash). Status: not verified against a
live crash/corruption; ported faithfully in `fl.grid` (`Grid.widget()`'s
`row > rowCount_`/`col > colCount_` checks, matching upstream's `>`
verbatim) since D's own bounds-checked arrays turn the same off-by-one into
a caught `RangeError` rather than silent corruption -- the bug is upstream's
to fix, not this port's to silently paper over.

Same family, same file: `layout()`'s colspan/rowspan span-accumulation loops
(`ww += Cols_[c+i+1].w_;` / `wh += Rows_[r+i+1].h_;`) have no check that the
span doesn't run past the last column/row -- a cell whose `colspan`/`rowspan`
extends beyond the grid's edge (e.g. `widget(w, 0, cols_-1, 1, 2)`) reads out
of bounds the same way. Not separately verified; not exercised by this
port's colspan/rowspan unittests (both stay within bounds), and not
special-cased in `fl.grid` -- same faithful-transliteration reasoning as the
entry above.

### `Fl_Text_Display`'s drag-auto-scroll state (`src/Fl_Text_Display.cxx`): file-scope statics shared across *all* instances, including in the destructor

`scroll_direction`/`scroll_amount`/`scroll_x`/`scroll_y` (lines 83-86) are
plain file-scope `static int`s, not `Fl_Text_Display` instance members --
genuinely shared across every text display in the process, even though
`scroll_timer_cb(void *user_data)` still targets a specific widget instance
via `user_data`. This is presumably intentional (only one drag-scroll can
be happening at a time in a single-mouse UI), but it has a real edge case
in `~Fl_Text_Display()`:

```cpp
Fl_Text_Display::~Fl_Text_Display() {
  if (scroll_direction) {
    Fl::remove_timeout(scroll_timer_cb, this);
    scroll_direction = 0;
  }
  ...
```

If widget A is destroyed while widget B (a *different* text display) is
the one actually mid-drag-scroll, A's destructor sees the shared
`scroll_direction != 0` (it's B's), calls `Fl::remove_timeout(...,
this)` with `this == A` (a no-op, since the pending timeout's data is
`B`, not `A`), but then unconditionally zeroes the shared
`scroll_direction` anyway -- corrupting B's still-in-progress drag-scroll
bookkeeping (B's own pending timer keeps firing regardless, but B's next
`FL_DRAG` event will see `scroll_direction == 0` and think no timer is
running, potentially starting a redundant second one).

**Status: CONFIRMED** with a headless `fl.text_display` unittest mirroring
the scenario above (two `TextDisplay`s, one mid-drag-scroll, the other
destroyed): the shared flag zeroes exactly as predicted while the real timer
keeps running underneath it. Not filed with FLTK (no review/decision to do so
yet, per this file's process notes). **Deviated from in the port**:
`fl.text_display` scopes `scrollDirection_`/`scrollAmount_`/`scrollX_`/
`scrollY_` as per-instance fields rather than reproducing the shared statics;
see that module's own comment on the fields and its regression test. This was
the first confirmed FLTK bug fixed rather than faithfully replicated.

### `Fl_Xlib_Graphics_Driver::end_points()`/`end_line()` (`src/drivers/Xlib/Fl_Xlib_Graphics_Driver_vertex.cxx:31-41`): a single-point path draws nothing through either entry point

Found while porting `fl_begin_points()`/`fl_end_points()`/`fl_begin_line()`/
`fl_end_line()` to `fl.draw` (core-roadmap item 10).

```cpp
void Fl_Xlib_Graphics_Driver::end_points() {
  if (n>1) XDrawPoints(fl_display, fl_window, gc_, short_point, n, 0);
}

void Fl_Xlib_Graphics_Driver::end_line() {
  if (n < 2) {
    end_points();
    return;
  }
  if (n>1) XDrawLines(fl_display, fl_window, gc_, short_point, n, 0);
}
```

`end_points()` requires `n>1` to draw at all -- a single point added via
`fl_begin_points(); fl_vertex(x,y); fl_end_points();` produces zero calls to
`XDrawPoints()`, i.e. nothing is drawn. `end_line()`'s own `n<2` fallback to
`end_points()` doesn't help either: at `n<2` (0 or 1), `end_points()`'s `n>1`
guard also fails, so a single-vertex "line" draws nothing through *either*
API. `XDrawPoints()` accepts `npoints==1` fine at the Xlib level (there's no
protocol reason to require 2+), so this reads like an off-by-one in the
guard condition (`n>1` where `n>=1` -- or even `n>0` -- would let a lone
point actually render) rather than an intentional restriction.

**Status: not verified against actual rendered output or FLTK's issue
tracker** -- `fl.draw`'s `fl_end_points()`/`fl_end_line()` reproduce this
exactly (a `pts.length > 1` guard on both), ported faithfully per this
file's process notes rather than silently fixed, since the surrounding
begin/end/vertex API is otherwise a straight line-for-line port and this
"fix" would only be a guess at upstream's actual intent.

### `fl_box_table`'s `FL_GLEAM_ROUND_UP_BOX`/`FL_GLEAM_ROUND_DOWN_BOX` rows point at the plain (non-round) gleam box functions (`src/fl_boxtype.cxx:465-466`)

Found while porting the "gleam" scheme's boxtype family to `fl.draw`
(core-roadmap item 11, Phase B).

```cpp
{ fl_gleam_up_box,        2, 2, 4, 4,  1 },   // _FL_GLEAM_ROUND_UP_BOX
{ fl_gleam_down_box,      2, 2, 4, 4,  1 },   // _FL_GLEAM_ROUND_DOWN_BOX
```

Every other scheme family that has its own `*_ROUND_UP_BOX`/
`*_ROUND_DOWN_BOX` pair genuinely draws something round-shaped there:
`FL_GTK_ROUND_UP_BOX`/`FL_GTK_ROUND_DOWN_BOX` point at real
`fl_gtk_round_up_box`/`fl_gtk_round_down_box` functions (`fl_gtk.cxx`), and
likewise for `_FL_PLASTIC_ROUND_UP_BOX`/`_FL_OXY_ROUND_UP_BOX` and their
down-box counterparts. `fl_gleam.cxx` (165 lines total) never defines an
`fl_gleam_round_up_box`/`fl_gleam_round_down_box` at all -- the table
entries for gleam's "round" boxtypes just reuse the same square
`fl_gleam_up_box`/`fl_gleam_down_box` used for the plain (non-round)
boxtypes. `Fl::reload_scheme()`'s own "gleam" branch does call
`set_boxtype(FL_ROUND_UP_BOX, FL_GLEAM_ROUND_UP_BOX)` /
`set_boxtype(FL_ROUND_DOWN_BOX, FL_GLEAM_ROUND_DOWN_BOX)`
(`Fl_get_system_colors.cxx`), so a `RoundButton`/`RadioButton` drawn under
an active "gleam" scheme genuinely gets a square gleam box as its
background rather than a round one -- this looks like a real gap (the
other three schemes all did the round variant properly) rather than an
intentional design choice, but reads as plausible rather than confirmed
since there's no comment either way in `fl_gleam.cxx` or the box table.

**Status: not verified against actual rendered output or FLTK's issue
tracker** -- `fl.draw`'s `drawBoxAt()` reproduces this exactly
(`Boxtype.gleamRoundUpBox`/`gleamRoundDownBox` dispatch to
`flGleamUpBox()`/`flGleamDownBox()`, the same square functions as
`gleamUpBox`/`gleamDownBox`), ported faithfully rather than silently
"fixed" with an invented round-gleam-box shape upstream itself never
specified.

### `fl_draw_arrow()`'s "oxy" branch skips the trailing `fl_color(saved_color)` restore every other branch gets (`src/fl_draw_arrow.cxx:242-289`)

Found while porting the "oxy" scheme's boxtype family (and its dedicated
`oxy_arrow()`) to `fl.draw` (core-roadmap item 11, Phase B, last of
the four scheme families).

```cpp
void fl_draw_arrow(Fl_Rect r, Fl_Arrow_Type t, Fl_Orientation o, Fl_Color col) {

  int ret = 0;
  Fl_Color saved_color = fl_color();

  debug_arrow(r);

  // special case: arrows for the "oxy" scheme

  if (Fl::is_scheme("oxy")) {
    oxy_arrow(r, t, o, col);
    return;
  }

  // implementation of all arrow types for other schemes
  switch(t) {
    ...
  }

  if (!ret) {
    ...
  }

  fl_color(saved_color);

} // fl_draw_arrow()
```

Every other code path through this function -- `FL_ARROW_SINGLE`/
`FL_ARROW_DOUBLE`/`FL_ARROW_CHOICE` under any other scheme, the unknown-type
error-flag fallback -- falls through to the trailing `fl_color(saved_color)`
before returning, restoring the caller's active draw color. The "oxy" branch
is the only one that doesn't: it calls `oxy_arrow()` and `return`s
immediately, several lines before that restore. `oxy_arrow()` itself does
leave `fl_color()` in a color-table-derived state (the last color drawn by
whichever `single_arrow()` call ran last), not necessarily the caller's
original color, so under the "oxy" scheme this function leaks a color change
into whatever the caller draws next -- unlike every other scheme, where the
color is always restored. Reads like a straightforward oversight (the early
`return` was added for the oxy special case without noticing it also skips
the shared cleanup at the bottom) rather than an intentional asymmetry --
there's no comment justifying it either way.

**Status: not verified against actual rendered output or FLTK's issue
tracker** -- `fl.draw`'s `fl_draw_arrow()` reproduces this exactly (its own
`isScheme("oxy")` branch also `return`s immediately after calling
`oxyArrow()`, skipping the trailing `fl_color(old)` restore every other path
gets), ported faithfully per this file's process notes rather than silently
adding a restore upstream itself doesn't have.

### `Fl_Table::row_height(int, int)` grows `_rowheights` one element short, unlike its own `col_width()` twin (`src/Fl_Table.cxx`)

Found while porting `Fl_Table` to `fl.table`.

```cpp
void Fl_Table::row_height(int row, int height) {
  if ( row < 0 ) return;
  if ( row < row_size() && (*_rowheights)[row] == height ) {
    return;
  }
  int now_size = row_size();
  if (row >= now_size) {
    _rowheights->resize(row, height);       // <-- no +1
  }
  (*_rowheights)[row] = height;
  ...
}

void Fl_Table::col_width(int col, int width)
{
  if ( col < 0 ) return;
  if ( col < col_size() && (*_colwidths)[col] == width ) {
    return;
  }
  int now_size = col_size();
  if ( col >= now_size ) {
    _colwidths->resize(col+1, width);       // <-- has +1
  }
  (*_colwidths)[col] = width;
  ...
}
```

Two near-identical functions, one real difference: `col_width()`'s resize call has
`col+1`, `row_height()`'s doesn't. Concretely, when `row == now_size` (the ordinary
"append the next row's height" case, e.g. from `rows(int)` growing the table one
row at a time), `_rowheights->resize(row, height)` resizes the vector to `row`
elements -- but it was *already* `row` elements (`now_size == row`), so this is a
no-op, and the very next line, `(*_rowheights)[row] = height;`, indexes one past
the vector's actual size. `std::vector::operator[]` performs no bounds check, so
this is undefined behavior rather than a guaranteed crash -- most `std::vector`
implementations reserve capacity beyond size, so the out-of-bounds write typically
lands in already-owned-but-uninitialized heap memory rather than visibly
corrupting anything, which plausibly explains how this has gone unnoticed.
`col_width()`'s parallel logic doesn't have the bug, which is what makes the
missing `+1` in `row_height()` read like a plain copy-paste slip between the two
functions rather than an intentional difference -- there's no comment explaining
one growing "eagerly" (`col+1`) and the other "lazily" (`row`).

**Status: not verified against actual rendered output or FLTK's issue
tracker** -- **deviation**: `fl.table`'s `rowHeight(int, int)` uses `row + 1`
(matching `colWidth()`'s own correct pattern) rather than faithfully reproducing
`row`, since D arrays bounds-check by default and faithfully reproducing the
upstream call would turn silent C++ UB into a guaranteed `RangeError` crash on
the first row ever added to a table -- the same "faithful replication would be
actively harmful in a memory-safe language" category as the `Fl_Text_Buffer::copy()`
entry above, the first instance of this exception in this port.

### `Fl_Table::is_fltk_container()` checks a count that can never exceed 3 (`FL/Fl_Table.H`)

Found while porting `Fl_Table` to `fl.table`.

```cpp
int is_fltk_container() const {               // does table contain fltk widgets?
  return( Fl_Group::children() > 3 );         // (ie. more than box and 2 scrollbars?)
}
```

`Fl_Group::children()` here is `Fl_Table`'s own direct child count (not the nested
`table` `Fl_Scroll` container's), which the constructor fixes at exactly 3 for the
object's entire lifetime: `vscrollbar`, `hscrollbar`, and `table` are the only
widgets ever added to `Fl_Table`'s own `Fl_Group::array()` (`Fl_Group::end()` is
called right after constructing those three, and every widget a caller
subsequently adds via `Fl_Table::add()`/`begin()`/`end()` goes into the *nested*
`table`'s own array via `table->begin()`, not `Fl_Table`'s). So `Fl_Group::children()
> 3` can never be true as written -- this method appears to always return 0/false,
regardless of how many FLTK widgets the caller has actually added as cell
content. `is_fltk_container()` is `protected` and (as far as a full read of
`Fl_Table.cxx` shows) never called anywhere internally, so this doesn't affect
`Fl_Table`'s own behavior either way -- it reads like a public convenience method
for subclasses that has quietly been dead/incorrect since some earlier
architecture (maybe one where widgets were once added directly to `Fl_Table`'s
own array instead of the nested `Fl_Scroll`), rather than something actively
relied upon.

**Status: not verified against actual rendered output or FLTK's issue
tracker** -- `fl.table`'s `isFltkContainer()` reproduces this exactly (`super.children()
> 3`, i.e. `Group.children()`, matching the check upstream performs), ported
faithfully rather than "fixed" with a guess at what the original intent was
(e.g. checking the nested container's own count instead).

### `Fl_File_Browser::full_height()` passes a 0-based index to 1-based `find_line()` (`src/Fl_File_Browser.cxx`)

Found while porting `Fl_File_Browser` to `fl.file_browser`.

```cpp
int Fl_File_Browser::full_height() const
{
  int i, th;
  for (i = 0, th = 0; i < size(); i ++)
    th += item_height(find_line(i)) + linespacing();
  return (th);
}
```

`i` runs `0 .. size()-1`, but `Fl_Browser::find_line(int line)` (and every other
caller of it throughout `Fl_Browser`/`Fl_Browser_`) treats line numbers as
strictly 1-based (`1 .. size()`) -- confirmed by hand-tracing
`Fl_Browser::find_line()`'s own cache/bisection logic: `find_line(0)` always
resolves to `NULL` (the `n=1; l=first;` branch immediately walks `l = l->prev`
once since `n=1 > line=0`, landing on `first->prev`, i.e. `NULL`). So this loop
effectively substitutes a bogus "line 0" (`item_height(NULL)`) for the *first*
real item's height, and never reaches the true *last* item at all (the loop's
final iteration, `i == size()-1`, resolves to the second-to-last item) --
`full_height()`'s total is silently off by the difference between the first
item's real height and whatever `item_height(NULL)` returns, minus the true
last item's height entirely.

This doesn't crash upstream only by what looks like an accident of C pointer
arithmetic: `Fl_File_Browser::item_height(NULL)` calls `bline_txt(NULL)` first,
which just computes a `NULL + offsetof(txt)` address (forming a flexible-array-
member pointer, not dereferencing anything) before the function's own
`if (line != NULL)` guard skips ever reading through it. Forming that address is
technically undefined behavior per the C++ standard, but doesn't fault in
practice on any mainstream platform, which is presumably why this has never
been noticed as a crash.

**Status: not verified against actual rendered output or FLTK's issue
tracker** -- **deviation**: `fl.file_browser` does not override `fullHeight()`
at all (relying on `fl.browser.Browser`'s own cached `fullHeight_`, which is
already correctly maintained via `itemHeight()`'s *virtual* dispatch during
`insertNode()` -- no need for this method's buggy from-scratch recomputation),
and `itemHeight()` is ported with an explicit `item is null` guard rather than
depending on the same accidental C pointer-arithmetic non-crash: unlike a raw
C++ pointer, dereferencing a field through a `null` D class reference is a
real, immediate runtime error, so faithfully replicating the 0-based loop
would crash this port on the first `draw()` of any non-empty `FileBrowser`,
the same "faithful replication would be actively harmful in a memory-safe
language" category as the `Fl_Text_Buffer::copy()` and `Fl_Table::rowHeight()`
entries above.

### `load_kde_mimelnk()` (`src/Fl_File_Icon2.cxx`): KDE 1.x icon path built from a stale line buffer, not a directory

Found while porting `fl.file_icon`'s `load_system_icons()` cascade.

```c
static void
load_kde_mimelnk(const char *filename, const char *icondir) {
  ...
  char tmp[1024];
  ...
  if ((fp = fl_fopen(filename, "rb")) != NULL) {
    while (fgets(tmp, sizeof(tmp), fp)) {
      if ((val = get_kde_val(tmp, "Icon")) != NULL)
        strlcpy(iconfilename, val, sizeof(iconfilename));
      ...
    }
    ...
    if (iconfilename[0]) {
      if (iconfilename[0] == '/') { ... }
      else if (!fl_access(icondir, F_OK)) { /* KDE 3.x/2.x path */ }
      else {
        // KDE 1.x icons
        snprintf(full_iconfilename, sizeof(full_iconfilename),
                 "%s/%s", tmp, iconfilename);
        ...
```

`tmp` is the byte buffer `fgets()` reads each line of the `.desktop`/mimelnk
file into -- by the time the `while` loop exits, it holds whichever line was
read *last* (typically unrelated to any directory path; often just the final
key=value line, or leftover/undefined content if the file ended without a
trailing newline touching that exact buffer position again). The "KDE 1.x
icons" fallback branch uses it as if it were a directory prefix
(`"%s/%s"`, `tmp`, `iconfilename`), which reads as a copy/paste leftover --
plausibly `tmp` was originally meant to hold a KDE-1.x icon directory
resolved earlier in the function, but no such assignment exists in the
current source. The practical impact is limited: this branch only runs when
the *outer* KDE 2.x/3.x icon-directory check (`fl_access(icondir, F_OK)`)
already failed, on a desktop old enough to still ship KDE-1.x-style mimelnk
files -- a combination essentially unreachable on any system built after
~2000. **Status: not verified against actual KDE 1.x output or FLTK's issue
tracker.** **Deviation**: `fl.file_icon`'s `loadKdeMimelnk()` reproduces the
same "use whatever the last read line was" value (renamed `lastLine` for
clarity) rather than silently substituting something more sensible, since
correcting it would be guessing at unstated original intent; the resulting
path fails its `exists()` check and the branch returns without loading an
icon either way, on every system this port has been tested on.

### `Fl_Help_View.cxx`: `format()` vs. `draw()` disagree on `<IMG>` sizing when `WIDTH`/`HEIGHT` accompany `SRC`

`format()`'s `IMG` layout branch (`:1538-1541`) unconditionally overwrites
`width`/`height` with the loaded image's real dimensions once `SRC` is
present:

```c
if (get_attr(attrs, "SRC", attr, sizeof(attr))) {
  img    = get_image(attr, width, height);
  width  = img->w();
  height = img->h();
}
```

`draw()`'s own `IMG` branch (`:3043-3047`), doing the equivalent work to
paint the same tag, only fills in a dimension that's still zero:

```c
if (get_attr(attrs, "SRC", attr, sizeof(attr))) {
  img = get_image(attr, width, height);
  if (!width) width = img->w();
  if (!height) height = img->h();
}
```

So a document with `<IMG SRC="x.png" WIDTH="200">` on an image whose real
width differs from 200 gets laid out (space reserved, line-wrapping) using
the image's *real* width, but painted assuming a width of 200 -- the
reserved box and the drawn image can disagree. Status: not verified against
actual rendered output (needs a real, non-square test image). **Deviation**:
this port's `get_image()` substitute always returns a fixed 16x24 size (see
`fl.help_view`'s module comment -- `fl.image` has no real loader yet), so
`fl.help_view.d`'s `format()`/`draw()` reproduce this exact asymmetry
faithfully (`format()`: unconditional `width=16; height=24;`; `draw()`: `if
(width==0) width=16;` etc.) even though the two currently always agree in
practice with this stand-in.

### `Fl_Help_View.cxx`: `FONT SIZE` parsed with `atoi()` in `format()` but `atof()` in `draw()`

`format()`'s `FONT` tag handling (`:1493,:1496`) parses the `SIZE` attribute
with `atoi()`; `draw()`'s otherwise-structurally-identical `FONT` handling
(`:2939,:2942`) parses the same attribute with `atof()`. Harmless for the
integer `SIZE` values real documents use, but a real inconsistency between
two code paths that are supposed to compute the same font size. Status: not
verified against actual rendered output with a fractional `SIZE` value (e.g.
`SIZE="2.5"`). **Deviation**: `fl.help_view.d` uses its own `atoiLike()`
(an `atoi()`-equivalent) in both `format()` and `draw()`, rather than
reproducing the `atof()` variant in `draw()` -- noted as a comment at that
call site rather than silently normalized away without comment.

### `Fl_Help_View.cxx`: `format()`'s `OL_num` stack is declared outside its own retry loop

`format()` (`:886-1714`) has an outer `while (!done)` retry loop that
re-parses the whole document from scratch whenever a word doesn't fit and
`hsize_` needs to grow (`done = 0; break;` at several points, e.g. `:989`).
Every other piece of parse state (`blocks_`, `link_list_`,
`target_line_map_`, etc.) is explicitly reset at the top of each retry
(`:938-941`). `std::vector<int> OL_num` (`:923`) and its initial
`push_back(-1)` (`:925`) are declared *before* the retry loop starts and
never reset inside it, so a retry triggered while inside a nested
`<UL>`/`<OL>` leaves stale entries on the stack for the next attempt --
`<LI>` numbering (`OL_num.back()++` at `:1270`) could come out wrong after a
mid-list retry. Status: not verified against actual rendered output (needs a
document with nested lists wide enough to trigger a real `hsize_` retry).
**Deviation**: `fl.help_view.d`'s `format()` reproduces this exactly (`int[]
olStack = [-1];` declared outside its own `while (!done)` loop), per a
comment at that declaration, rather than silently moving the reset inside.

### `Fl_Help_View.cxx`: `Text_Block::line[32]` silently truncates past 31 lines per block

`Text_Block::line` (`:154`) is a fixed 32-entry array holding each
displayed line's starting X position within the block. `do_align()`
(`:839-872`) guards the increment (`if (line < 31) line++;`) but every call
site that indexes `line[]` for a *new* line (`format()`, `draw()`) has no
corresponding guard against re-using index 31 for every line past the 32nd
-- a block with more than 32 wrapped lines (e.g. one very long `<PRE>`
block, or a paragraph in a very narrow view) silently reuses `line[31]`'s
X position for all of them instead of extending storage or erroring.
Status: not verified against actual rendered output (needs a document
whose single block wraps to 33+ lines). **Deviation**: none needed --
`fl.help_view.d`'s `TextBlock.line` (a `int[32]` field) and its own
`doAlign()` reproduce the same fixed-size cap and guard verbatim; ported
faithfully as a real, if obscure, upstream limitation rather than "fixed"
by switching to a growable array, per this port's practice of not silently
correcting behavior a reader might rely on.

### `Fl_Help_View.cxx`: `draw()`'s `IMG` branch computes `ALT` text that's never used

`draw()`'s `IMG` handling (`:3049-3053`) computes an `ALT` attribute
fallback into a local `attr` buffer (`strcpy(attr, "IMG")` if `ALT` is
absent) whenever the image has no width or height, but `attr` is never
read again anywhere in the rest of the function -- the image is drawn (or
not) via `img->draw()` a few lines later with no text fallback path at all.
Looks like leftover code from a text-fallback feature that was removed or
never finished. Status: not verified against FLTK's issue tracker.
**Deviation**: `fl.help_view.d`'s `draw()` doesn't port this dead
computation at all (nothing would read it either); noted in the module's
top comment rather than silently dropped without a trace.

### `Fl_Help_Dialog::cb_forward__i()` uses the *current* page's scroll position instead of the recorded one (`src/Fl_Help_Dialog.cxx`)

Found while porting `Fl_Help_Dialog` to `fl.help_dialog`.

```cpp
void Fl_Help_Dialog::cb_back__i(Fl_Button*, void*) {
  if (index_ > 0) index_--;
  ...
  int l = line_[index_];                       // <- recorded topline for the TARGET page
  if (strcmp(view_->filename(), file_[index_]) != 0)
    view_->load(file_[index_]);
  view_->topline(l);
}

void Fl_Help_Dialog::cb_forward__i(Fl_Button*, void*) {
  if (index_ < max_) index_++;
  ...
  int l = view_->topline();                    // <- CURRENT page's topline, read BEFORE loading the target
  if (strcmp(view_->filename(), file_[index_]) != 0)
    view_->load(file_[index_]);
  view_->topline(l);
}
```

`cb_back__i` and `cb_forward__i` are structurally identical except for where `l` comes from. Going back correctly restores the *target* page's own recorded scroll position (`line_[index_]`). Going forward instead captures `view_->topline()` -- the scroll position of whatever page is on screen *right now*, before `view_->load()` ever runs -- and applies that stale value to the newly-loaded page.

Two cases:
- If the forward target is a *different file*: `view_->load()` already resets `topline_` to either `0` or an anchor's line internally, and this then overwrites that with the *previous* page's unrelated scroll offset -- landing forward-navigation on an essentially arbitrary vertical position in the new document.
- If the forward target is the *same file* (`load()` is skipped since the filename hasn't changed, e.g. two history entries are different anchors within one document): `view_->topline()` read here is *already* the correct current value before any change is made, so `view_->topline(l)` is a no-op that fails to actually move to `line_[index_]`'s recorded anchor position.

Looks like a copy-paste-and-forgot-to-adjust bug when `cb_forward__i` was derived from `cb_back__i` (or vice versa) -- `line_[index_]` is right there and unused in the forward case.

**Status: not verified against actual rendered output or FLTK's issue tracker** -- **ported faithfully, not fixed**: `fl.help_dialog.HelpDialog.forwardCB()` reproduces the exact same asymmetry (`currentTopline`, captured via `view_.topline()` before `view_.load()`, applied afterward) against `backCB()`'s correct `history_[index_].line` usage, per this project's default of porting bug-for-bug and flagging findings here rather than silently correcting them.

### `Fl_Image::fail()` doesn't detect a too-short `bits_length` for `Fl_RGB_Image` (`src/Fl_Image.cxx`)

Found while porting `Fl_RGB_Image`'s bits_length-checked constructor to `fl.image.RGBImage` (Milestone 1).

```cpp
int Fl_Image::fail() const {
  if ((w_ <= 0) || (h_ <= 0) || (d_ <= 0 && count_ == 0)) {
    if (ld_ == 0) return ERR_NO_IMAGE; else return ld_;
  }
  return 0;
}

Fl_RGB_Image::Fl_RGB_Image(const uchar *bits, int bits_length, int W, int H, int D, int LD) :
  Fl_Image(W,H,D), ...   // w_/h_/d_ set here, from the CALLER'S requested W/H/D --
                          // unconditionally, regardless of whether bits_length checks out below
{
  ...
  if (bits_length >= min_length) { data(...); ld(LD); }
  else { array = NULL; data(NULL, 0); ld(ERR_MEMORY_ACCESS); }  // count_ becomes 0, ld_ becomes ERR_MEMORY_ACCESS
}
```

The doc comment on this constructor (and on `fail()` itself, which lists `ERR_MEMORY_ACCESS` as a real, checkable return value) implies a caller can detect "bits was too short for the claimed W/H/D" via `img.fail()`. But `fail()`'s own condition only consults `ld_` (where `ERR_MEMORY_ACCESS` was stashed) when `w_<=0 || h_<=0 || (d_<=0 && count_==0)` is already true -- and for any normal `Fl_RGB_Image` (D is 1-4, never <= 0), that whole condition is `false` regardless of `count_`, since `d_<=0` alone is already false. So `fail()` returns `0` ("succeeded") even when the constructor's own `else` branch ran and left `array` null -- the only way to actually detect the failure is to check `array == NULL` (or `count() == 0`) directly, not `fail()`.

This isn't hit for `Fl_Bitmap` (where `d_` is always `0`, so the `d_<=0` half of the condition is always true and `count_==0` correctly gates it) or `Fl_PNM_Image`/other loaders that hit file-access/format errors before `Fl_Image::w()`/`h()`/`d()` are ever set to non-trivial values -- it's specific to this one constructor's "valid dimensions requested, but the supplied buffer doesn't back them" case.

**Status: not verified against FLTK's issue tracker.** Ported faithfully in `fl.image.RGBImage`'s single (D-slice-length-checked) constructor: `fail()` has the same `w_<=0||h_<=0||d_<=0` shape (this port doesn't have a `count_` field at all, see that class's own doc comment on why -- the `&& count_==0` term upstream has would be moot here anyway, since it's already dead for this exact case as shown above) and returns `0` for a too-short-buffer construction too; `array.length == 0` is the real, working signal, documented in the constructor's own doc comment and exercised by its unit test.

### `fl_symbols.cxx`'s `fl_draw_symbol()`: arbitrary-rotation `'0'` escape silently drops its first digit

Found while porting `fl_draw_symbol()` to `fl.symbols.fl_draw_symbol()`.

`documentation/src/common.dox`'s own public documentation of the label-symbol
syntax says:

> `[0-9]` - rotates by a multiple of 45 degrees... `'0'`, followed by four
> more digits rotates the symbol by that amount in degrees.

But the actual implementation (`src/fl_symbols.cxx`):

```cpp
switch (*p++) {          // consumes '0', p now points just past it
  case '0':
    rotangle = 1000 * (p[1] - '0') + 100 * (p[2] - '0') + 10 * (p[3] - '0');
    p += 4;
    break;
```

This reads `p[1]`, `p[2]`, `p[3]` -- three digit positions starting *one
character past* where the first of the documented "four more digits" would
be (`p[0]`) -- and never reads or validates `p[0]` at all, while still
advancing `p` by 4 (consistent with having consumed 4 digit characters, just
not the first one as a digit). Net effect: the character immediately after
`'0'` is silently ignored (not even required to be a digit), and only the
following three digits contribute to `rotangle` (so the achievable rotation
range from this escape is 0-999 in 0.1-degree steps via a 3-digit value*10,
not what a caller typing 4 real digits following the documented format would
expect). Looks like a copy-paste/off-by-one bug (`p[1..3]`/`p+=4` where
`p[0..2]`/`p+=3` was probably intended, or the loop was meant to start
reading one position earlier).

**Status: not verified against FLTK's issue tracker.** Ported exactly as
implemented (not as documented) in `fl.symbols.fl_draw_symbol()`'s `case
'0':` branch -- see that function's and the module's own top comment. Very
low real-world impact: this escape is for arbitrary (non-45-degree-multiple)
rotation, a rarely-used feature even among the already-niche `@`-symbol
system, and no `fl.*` caller so far uses it.

### `fl_draw.cxx`: `fl_draw()` and `fl_measure()` use different rules to find a label's trailing `@`-symbol

Found while porting both functions to `fl.draw.d`.

`fl_draw()`'s trailing-symbol search (used when actually drawing a label):

```cpp
if (str && (p = strrchr(str, '@')) != NULL && p > (str + 1) && p[-1] != '@') {
```

finds the **last** `@` in the (post-leading-symbol) string, and requires it
to be at index >= 2 with a non-`@` character immediately before it.

`fl_measure()`'s trailing-symbol search (used when sizing a widget for that
same label, e.g. during layout):

```cpp
if ((p=strchr(sym2,'@')) != NULL && p[1] != '@') {
```

finds the **first** `@` in the same region, with a different, weaker guard
(only "not immediately followed by another `@`" -- no minimum-index check at
all).

For a label with zero or one `@` after its leading symbol (essentially every
real-world label, including the "@->"-style ones this port's investigation
started from) both rules agree, since there's only one candidate `@` for
either to find. But for a label containing **two or more** `@` characters in
that region, the two functions can disagree about which one is "the"
trailing symbol -- `fl_measure()` would size the label for the earlier `@`,
`fl_draw()` would actually render the later one, potentially producing a
mismatched/clipped layout. Looks like an unintentional drift between two
functions that should be measuring and drawing the exact same rule, not a
deliberate design choice (nothing documents a difference).

**Status: not verified against FLTK's issue tracker.** Ported faithfully as
two distinct detection functions (`fl.draw.detectSymbols()` for `fl_draw()`'s
rule, `fl.draw.detectSymbolsForMeasure()` for `fl_measure()`'s), matching
each one's own real behavior rather than silently unifying them.

### `Fl_Window::free_icons()` doesn't re-push `_NET_WM_ICON` the way `icons()` does

Found while porting `FL/Fl_Window.H`'s icon API to `fl.window.d`.

`Fl_Window::icons(const Fl_RGB_Image *icons[], int count)` ->
`Fl_X11_Window_Driver::icons()` (`Fl_x.cxx`):

```cpp
void Fl_X11_Window_Driver::icons(const Fl_RGB_Image *icons[], int count) {
  free_icons();
  if (count > 0) { ... }
  if (Fl_X::flx(pWindow)) set_icons();   // <-- re-pushes the X property
}
```

calls `free_icons()` then unconditionally calls `set_icons()` afterward if
the window is already shown -- so `win->icons(nullptr, 0)` on a shown window
immediately updates the on-screen icon (falling back to the default icon
list, since `icon_->count` is now 0).

But the *public* `Fl_Window::free_icons()` -> `Fl_X11_Window_Driver::
free_icons()` (`Fl_x.cxx`) is just:

```cpp
void Fl_X11_Window_Driver::free_icons() {
  icon_->legacy_icon = 0L;
  if (icon_->icons) { ... }
  icon_->count = 0;
}
```

-- clears the same state but never calls `set_icons()`. So calling
`win->free_icons()` directly on an already-shown window leaves the old
`_NET_WM_ICON` property (and whatever icon the window manager is currently
displaying) untouched until something *else* happens to trigger a
`set_icons()` call later (e.g. a subsequent `icons()`/`icon()` call, or the
window being hidden and re-shown). `icons(nullptr, 0)` and `free_icons()`
end up in the exact same internal state but with different *visible*
effects on a live window, which looks like an unintentional inconsistency
between two entry points that both claim to "clear the icons" rather than a
deliberate design choice (nothing documents a difference, and there's no
comment explaining why `free_icons()` should behave differently from
`icons(icons, 0)`).

**Status: not verified against FLTK's issue tracker.** Ported faithfully:
`fl.window.Window.freeIcons()` matches upstream's own `free_icons()` exactly
(clears state, no immediate `fl.platform_x11.setIcons()` call), while
`Window.icons([])` matches upstream's `icons(icons, 0)` (does call
`setIcons()` when shown) -- see `freeIcons()`'s own doc comment in
`fl.window.d`.

### `FL/names.h`: `fl_fontname_str()` and `fl_callback_reason_str()` both exclude the last valid array entry (off-by-one)

Found while porting `FL/names.h` to `fl.names.d`.

`fl_fontname_str()`:

```cpp
const char * const fl_fontnames[] = { /* 16 entries, indices 0..15 */ };
inline std::string fl_fontname_str(int font) {
  if ((font < 0) || (font >= FL_ZAPF_DINGBATS)) {
    return "FL_FONT_" + std::to_string(font);
  } else {
    return fl_fontnames[font];
  }
}
```

`FL_ZAPF_DINGBATS` is `15`, the *last valid* index into a 16-entry array
(indices 0-15). The check `font >= FL_ZAPF_DINGBATS` is true when
`font == 15`, so `fl_fontname_str(FL_ZAPF_DINGBATS)` falls into the
"invalid" branch and returns the generic `"FL_FONT_15"` fallback instead of
the real name `"FL_ZAPF_DINGBATS"` -- the one array entry that's
unreachable through this function is exactly the last one. The boundary
looks like it should have been `font > FL_ZAPF_DINGBATS` (or
`font >= FL_ZAPF_DINGBATS + 1`).

`fl_callback_reason_str()` has the identical shape of bug, in the same
file, over a 36-entry array (indices 0-35):

```cpp
inline std::string fl_callback_reason_str(int reason) {
  if ((reason < 0) || (reason >= FL_REASON_USER+3) || (fl_callback_reason_names[reason] == nullptr)) {
    return "FL_REASON_" + std::to_string(reason);
  } else {
    return fl_callback_reason_names[reason];
  }
}
```

`FL_REASON_USER+3` is `35`, the last valid index; `reason >= FL_REASON_USER+3`
excludes it the same way, so `fl_callback_reason_str(FL_REASON_USER+3)`
never returns `"FL_REASON_USER+3"`, only the generic `"FL_REASON_35"`
fallback.

Both functions were very likely written from the same template/pattern
(same file, same "off owning array length as the boundary, compared with
`>=`" shape), so this may be one root cause appearing twice rather than two
independent mistakes.

**Status: not verified against FLTK's issue tracker.** Ported faithfully in
`fl.names.fontNameStr()`/`callbackReasonNameStr()` -- both replicate the
exact same off-by-one (see each function's own doc comment), with a
`unittest` pinning down the buggy behavior explicitly so a future faithful-
sync doesn't accidentally "fix" it without noticing the deviation from
upstream.

### `fl_show_colormap.cxx`: `ColorMenu::run()` uses `y()` instead of `h()` for the `which > 255` initial-position branch

`src/fl_show_colormap.cxx`, `ColorMenu::run()`:

```cpp
Fl_Color ColorMenu::run() {
  if (which > 255) {
    position(Fl::event_x_root()-w()/2, Fl::event_y_root()-y()/2);
  } else {
    position(Fl::event_x_root()-(initial%8)*BOXSIZE-BOXSIZE/2-BORDER,
             Fl::event_y_root()-(initial/8)*BOXSIZE-BOXSIZE/2-BORDER);
  }
  ...
```

The horizontal half centers the window on the event point using the
window's own width (`w()/2`); the vertical half, by the same logic,
should presumably use the window's own height (`h()/2`) but instead
uses `y()` -- the window's own not-yet-`show()`n Y position (still
whatever it defaulted to, effectively an arbitrary/stale value, not a
size). This only triggers when `oldcol` (the color to highlight) is a
true-color `Fl_Color` value rather than a palette index (`which > 255`);
the more common index case (the `else` branch) is unaffected and correct.

**Status: not verified against FLTK's issue tracker.** Ported faithfully
in `fl.show_colormap.ColorMenu.run()` (this port's `fl_show_colormap()`),
same `y()` use, with a comment pointing at this entry -- no caller in this
port's samples exercises the `which > 255` branch yet, so the faithful
port is unverified against real upstream behavior for this specific case
either.

### `Fl_EPS_File_Surface::origin()` reads `left_margin`/`top_margin`/`angle` without either ever being initialized on that call path (`src/drivers/PostScript/Fl_PostScript.cxx`)

`Fl_PostScript_Graphics_Driver`'s constructor (`Fl_PostScript.cxx:149-162`,
the `! USE_PANGO` branch) initializes `lang_level_`, `mask`, `bg_r`/`bg_g`/
`bg_b`, `clip_`, and `scale_x`/`scale_y` -- but not `left_margin`,
`top_margin`, or `angle`. `Fl_EPS_File_Surface`'s constructor
(`Fl_PostScript.cxx:1987-2011`) calls `start_eps()`, which also never
touches any of these three fields; only `start_postscript()` (called from
`Fl_PostScript_File_Device::begin_job()`, a different, `Fl_EPS_File_
Surface` never reaches) sets `left_margin`/`top_margin`. `angle` is set
nowhere in the `! USE_PANGO` branch at all outside its declaration.

`Fl_EPS_File_Surface::origin(int, int)` calls `driver()->ps_origin(x, y)`,
whose body is:

```cpp
void Fl_PostScript_Graphics_Driver::ps_origin(int x, int y)
{
  clocale_printf("GR GR GS %d %d TR  %f %f SC %d %d TR %f rotate GS\n",
    left_margin, top_margin, scale_x, scale_y, x, y, angle);
}
```

So any program that constructs an `Fl_EPS_File_Surface` and later calls
its `origin(x, y)` setter reads three uninitialized `int`/`float` class
members (whatever value happened to be on the heap at allocation time)
and emits them into the PostScript stream, producing an unpredictable
translate/scale/rotate rather than the presumably-intended "no shift
beyond the caller's own x/y" (`left_margin`/`top_margin`/`angle` all `0`).
`Fl_EPS_File_Surface`'s own header-documented usage example never calls
`origin()` at all, so this is easy to miss in normal use.

**Status: not verified against FLTK's issue tracker.** Not reproduced in
`fl.postscript.PostscriptGraphicsDriver` -- `leftMargin_`/`topMargin_`/
`angle_` are all explicitly zero-initialized fields (see that class's own
doc comment), which happens to also match what the *intended* behavior
almost certainly is (no unwanted shift), so this is a case where fixing
the uninitialized read was the obviously-correct choice rather than one
requiring a judgment call.

### `Fl_Anim_GIF_Image.cxx`'s `FrameInfo::on_frame_data()`: truthy check on transparent index, not a sign check

```cpp
frame.transparent_color_index = gf.trans && gf.trans < gf.clrs ? gf.trans : -1;
```

`gf.trans` is `has_transparent ? transparent_pixel : -1` (set in
`Fl_GIF_Image::load_gif_()`), so the intended test is "does this frame
have a transparent color, and is it in range" -- which should be
`gf.trans >= 0 && gf.trans < gf.clrs`. Written as a bare truthy check
(`gf.trans &&`) instead, this also excludes the case where the
transparent color index is genuinely `0`: `frame.transparent_color_index`
silently becomes `-1` even though the GIF really does have a transparent
color at index 0. The per-pixel compositing loop just above (`if (c ==
gf.trans) continue;`) doesn't share this bug -- it compares against the
raw `gf.trans` value directly, so transparency at index 0 still renders
correctly. The only fallout is in `FrameInfo::dispose()`/
`set_to_background()`, which consult `frames[frame].transparent_color_index`
to decide what color/alpha to fill a disposed region with -- a frame whose
transparent color is index 0 could get treated as if it had no
transparent color at all when a *later* frame disposes it to background.

**Status: not verified against FLTK's issue tracker.** Ported faithfully
(same truthy check, same behavior) in `fl.anim_gif_image.AnimGifImage.
onFrameData()` -- see that method's own inline comment and
`PORTING.md`'s `FL/Fl_Anim_GIF_Image.H` row.

### `Fl_Anim_GIF_Image.cxx`'s `FrameInfo::dispose()`: wrong source stride for a partial `DISPOSE_PREVIOUS` ancestor frame

```cpp
const char *src = frames[prev].rgb->data()[0];
if (px == 0 && py == 0 && pw == canvas_w && ph == canvas_h)
  memcpy((char *)dst, (char *)src, canvas_w * canvas_h * 4);
else {
  if ( px + pw > canvas_w ) pw = canvas_w - px;
  if ( py + ph > canvas_h ) ph = canvas_h - py;
  for (int y = 0; y < ph; y++)
    memcpy(dst + ( y + py ) * canvas_w * 4 + px, src + y * frames[prev].w * 4, pw * 4);
}
```

`px`/`py`/`pw`/`ph` are `frames[prev]`'s own encoded x/y/w/h. When
`optimize_mem` is *off*, `on_frame_data()` always stores `frame.rgb` as
the full `canvas_w x canvas_h` composited canvas (see the constructor
call right after the `if (optimize_mem) {...} else {...}` split), never
at the frame's own encoded size -- so `src` is always `canvas_w`-strided
in that mode. But the `else` branch above reads it with stride
`frames[prev].w * 4` (the frame's own encoded width), not `canvas_w * 4`.
This is only correct when the fast-path condition on the line above it
already caught the case (`prev`'s own rectangle happens to cover the
whole canvas); when disposing back to a genuine *partial* ancestor frame
(reachable via a chain of `DISPOSE_PREVIOUS` frames whose common
ancestor is itself only a sub-rectangle, `optimize_mem` off), this reads
each row at the wrong offset, corrupting the composited pixels for that
region. Narrow to trigger (needs a real disposal chain plus a genuinely
partial non-full-canvas ancestor frame), so probably rare in practice.

**Status: not verified against FLTK's issue tracker; not reproduced in
practice (no `.gif` test file that exercises this exact path was
available during porting).** Ported faithfully (same stride, same
behavior) in `fl.anim_gif_image.AnimGifImage.disposeFrame()` -- see that
method's own inline comment and `PORTING.md`'s `FL/Fl_Anim_GIF_Image.H`
row.

### `nanosvgrast.h`'s `nsvg__initPaint()`: out-of-bounds read when a gradient has exactly one stop

```c
} else if (grad->nstops == 1) {
    for (i = 0; i < 256; i++)
        cache->colors[i] = nsvg__applyOpacity(grad->stops[i].color, opacity);
```

`grad->stops` is allocated with exactly `nstops` entries (`nsvg__parseGradientStop()`'s
`realloc(grad->stops, sizeof(NSVGgradientStop)*grad->nstops)`). When
`nstops == 1`, this loop indexes `stops[i]` for `i` from 0 to 255 --
reading 255 elements past the end of a 1-element allocation. In C this
is undefined behavior (a real heap over-read, not merely "reads stale
data") rather than a visually-obvious glitch; it would typically read
whatever adjacent heap memory happens to follow the allocation, which
could crash, read genuinely-uninitialized bytes, or (most likely in
practice, since it's a small `malloc` easily coalesced with neighbors)
silently produce garbage colors for most of the 0-255 ramp on any SVG
with a single-stop gradient (e.g. `<linearGradient><stop offset="0"
.../></linearGradient>`, a real, valid, if unusual, SVG construct -- a
gradient with only one color stop, sometimes produced by tools/editors
as a degenerate case rather than collapsing to a solid fill).

**Status: not verified against FLTK's issue tracker.** **Not ported
faithfully** -- the only case in this whole nanosvg/nanosvgrast port
where CLAUDE.md's usual "port faithfully, note the quirk, don't fix it"
rule was overridden: a literal transliteration reads `stops[i]` on a
D dynamic array of length 1 for `i` up to 255, which is a `RangeError`
(D bounds-checks array indexing by default) on every single-stop
gradient, not a faithfully-reproduced quirk -- crashing the whole
rasterizer on a valid, unremarkable SVG input is worse than silently
diverging from an out-of-bounds C read that has no well-defined result
to be faithful *to* in the first place. `fl.nanosvg_rast.NsvgRasterizer.
initPaint()` uses `stops[0]` for every entry instead (arguably closer to
upstream's own likely-in-practice behavior than not, since index 0 is
the only in-bounds read upstream's own loop would have performed before
wandering out of bounds) -- see that call site's own inline comment.

### `nanosvg.h`'s `NSVGparser::pathFlag`: dead "no nested paths" guard, never actually set

```c
} else if (strcmp(el, "path") == 0) {
    if (p->pathFlag)	// Do not allow nested paths.
        return;
    nsvg__pushAttr(p);
    nsvg__parsePath(p, attr);
    nsvg__popAttr(p);
```
```c
static void nsvg__endElement(void* ud, const char* el)
{
    ...
    } else if (strcmp(el, "path") == 0) {
        p->pathFlag = 0;
```

`pathFlag` is read once (guarding against a `<path>` nested inside
another `<path>`, which isn't valid SVG but XML parsers don't
structurally prevent) and cleared once (on `</path>`), but is never set
to `1` anywhere in the file -- `grep -n "pathFlag ="` across all of
`nanosvg.h` finds only the one clearing assignment. The comment's stated
intent ("do not allow nested paths") can never actually fire; a
malformed `<path><path d="..."/></path>` parses both paths as separate
shapes today, contrary to the guard's own purpose.

**Status: not verified against FLTK's issue tracker.** Ported
faithfully (same dead guard, same behavior -- nested `<path>` elements
are not rejected) in `fl.nanosvg`'s `startElement()`/`endElement()`; see
those functions' own bodies (the `case "path":` branch checks
`p.pathFlag` and `endElement()`'s `case "path":` clears it, matching
upstream's shape exactly, dead code and all).

### `test/sudoku.cxx`'s `Sudoku::new_game()`: "start over" retry doesn't actually restart, indexes the grid out of bounds

```cxx
for (j = 0; j < 9; j += 3) {
    for (k = 0; k < 9; k += 3) {
      for (t = 1; t <= 9; t ++) {
        for (count = 0; count < 20; count ++) {
          m = j + (rand() % 3);
          n = k + (rand() % 3);
          if (!grid_values_[m][n]) { ... }
        }

        if (count == 20) {
          // Unable to find a valid puzzle so far, so start over...
          k = 9;
          j = -3;
          memset(grid_values_, 0, sizeof(grid_values_));
        }
      }
    }
}
```

The `if (count == 20)` block sits inside the `t` loop (`for (t = 1; t <=
9; t++)`), not the `k`/`j` loops it's clearly meant to restart -- setting
`j`/`k` here doesn't exit anything immediately. Control returns to the
`t` loop's own `t++`/`t<=9` check, and if `t` hasn't reached 9 yet, the
`t` loop runs one or more further iterations *with the modified `j=-3`,
`k=9` still in effect*, computing `m = j + (rand()%3)` (as low as -3)
and `n = k + (rand()%3)` (as high as 11) -- genuinely out of bounds on
the 9x9 `grid_values_` array, for however many `t` iterations remain
before the loop naturally ends.

In C++ this is undefined behavior with no crash guaranteed: `int
grid_values_[9][9]` is a plain stack/member array with no bounds
checking, so an out-of-range write just corrupts whatever memory
happens to sit adjacent to it (other local variables in `new_game()`,
most likely) -- which can silently produce a subtly-wrong (or
incomplete) generated puzzle without ever visibly crashing, especially
since the retry condition (`count` reaching 20, meaning 20 straight
failed placement attempts) is not exercised on every run.

**Status: not verified against FLTK's issue tracker.** **Not ported
faithfully** -- same reasoning as the nanosvg single-stop-gradient entry
above: a literal transliteration of this exact loop structure is a real,
deterministic `core.exception.ArrayIndexError` crash in D (bounds-checked
static arrays by default), not a faithfully-reproduced quirk, and not
merely theoretical -- reproduced by picking a difficulty level from the
Sudoku menu, `samples/test/sudoku.d(872): index [10] is out of bounds for
array of length 9`. It also plausibly explains the puzzle grid showing no
numbers at all on first launch, as silent grid corruption from this same
out-of-bounds write on a run where it happened to land somewhere that
didn't immediately crash.
Fixed in `samples/test/sudoku.d`'s `Sudoku.newGame()` with a labeled
`continue outer;` so the retry actually jumps back to the outer `j`
loop immediately (matching the comment's own clearly-stated intent)
instead of relying on loop variables the innermost loop doesn't
re-check until several iterations later.

### `print_update_status()` indexes `print_output_mode[]` with an unchecked `Fl_Preferences` value (`src/print_panel.cxx`)

```c
snprintf(name, sizeof(name), "%s/output_mode", printer == NULL ? "" : printer);
print_prefs.get(name, val, 0);
print_output_mode[val]->setonly();
```

`print_output_mode` is a fixed 4-element `Fl_Button*[4]`. `val` comes
straight from `Fl_Preferences::get(const char*, int&, int)`, which reads
whatever integer happens to be stored under that key in the user's
preferences file (`~/.fltk/fltk.org/printers.prefs` or platform
equivalent) -- a file a user could hand-edit, or that could be left over
from a future FLTK version that stores a wider range, or simply
corrupted. Nothing clamps `val` to `0..3` before it's used to index a
4-element C array; an out-of-range value is a real, unchecked
out-of-bounds pointer dereference (`print_output_mode[7]`, say), not
merely a theoretical concern -- `Fl_Preferences::get()` has no way to
validate that a raw integer is "in range" for a caller-specific array
it knows nothing about.

**Status: not verified against FLTK's issue tracker.** **Not ported
faithfully** -- same reasoning as the nanosvgrast single-stop-gradient
entry above: a literal port indexing `printOutputMode_[val]` (a D
`Button[4]` static array) with an unchecked `val` is a real, deterministic
`core.exception.RangeError` on a corrupted or unusually-valued prefs
file, not a faithfully-reproduced quirk. `fl.printer.PrintPanel.
updateStatus()` clamps `val` to `0` whenever it falls outside `0..3`
before indexing, matching the same "closer to upstream's own
likely-in-practice behavior" reasoning used for the nanosvgrast fix
(index 0 is what a freshly-created or default preferences file would
store anyway).

### `Fl_OpenGL_Graphics_Driver::rect()` (`src/drivers/OpenGL/Fl_OpenGL_Graphics_Driver_rect.cxx`) ignores line stipple

Found via `smoke-tests/gl_compositing.d`: a `Button`'s dashed focus
rectangle (`fl_focus_rect()`: `fl_line_style(lineDot, 1);
fl_rect(...); fl_line_style(lineSolid, 0);`) renders as a **solid**
outline when composited over a `GlWindow`'s GL scene, unlike the same
widget's real dashed focus ring under the native Xlib path.

Traced to `Fl_OpenGL_Graphics_Driver::rect(int,int,int,int)` itself:
unlike `Fl_Xlib_Graphics_Driver::rect()` (which strokes via
`XDrawRectangle()`, a GC operation that honors the current dash
pattern), the GL driver fakes a rectangle outline as four filled
`glRectf()` bars (see that function's own body — no reference to
`line_stipple_`/`GL_LINE_STIPPLE` anywhere). `glLineStipple()` only
affects primitives drawn via `glBegin(GL_LINES/GL_LINE_STRIP/
GL_LINE_LOOP)`; a `glRectf()`-filled quad is immune to it regardless of
whether `GL_LINE_STIPPLE` is currently enabled. `line_style()`
(`Fl_OpenGL_Graphics_Driver_line_style.cxx`) itself is implemented
correctly (real `glLineStipple()`/`GL_LINE_STIPPLE` calls) — it's only
`rect()` that never issues a stippleable primitive at all, so any
caller relying on a dashed *rectangle* outline specifically (box
frames drawn with `FL_DOT`/`FL_DASH`, not just focus rings) gets a
solid one under this driver. A genuinely non-rectangular dashed path
(`fl_begin_line()`/`fl_vertex()`/.../`fl_end_line()`, which really does
route through `GL_LINE_STRIP`) would dash correctly.

**Status: not verified against FLTK's issue tracker.** **Ported
faithfully, not fixed** — `fl.gl_graphics_driver.GlGraphicsDriver.rect()`
reproduces the same `glRectf()`-bars body with the same gap (see that
method's own doc comment), matching upstream's real GL-driver behavior
exactly rather than deviating to a stippled `GL_LINE_LOOP` outline
fldtk's own port would draw differently from real FLTK. Revisit only if
explicitly asked to deviate here.

### `test/checkers.cxx`'s `movepiece()`: `&&`/`?:` precedence makes the kinging check ignore "already a king" for one branch

Found while porting `test/checkers.cxx` to `samples/test/checkers.d`.

Both places `movepiece()` decides whether a moved piece should be
crowned use the same expression, once for a plain move and once for a
jump:

```cpp
piece oldpiece = b[i]; b[i] = EMPTY;
if (!(oldpiece&KING) && n->who ? (j>=36) : (j<=8)) {
  n->king = 1;
  b[j] = oldpiece|KING;
}
else b[j] = oldpiece;
```

`&&` binds tighter than `?:` in C++ (same as D), so this parses as
`(!(oldpiece&KING) && n->who) ? (j>=36) : (j<=8)` — not the presumably
intended `!(oldpiece&KING) && (n->who ? (j>=36) : (j<=8))`. The
difference only shows up when `oldpiece` is *already* a king: with the
actual parse, `!(oldpiece&KING)` is `false`, so the left operand of
`&&` is `false` regardless of `n->who`, and the whole ternary collapses
to its **else** branch, `(j<=8)` — evaluated unconditionally, with no
regard for which color is moving or for the fact that the piece was
already a king to begin with. Concretely: a **white king** (not black)
moving to any square with index `<= 8` gets `n->king` set to `1` and
`b[j] = oldpiece|KING` — harmless in itself (OR-ing an already-set bit
is a no-op, and `n->king` isn't consulted anywhere on this immediate
move) — but `undomove()` later reads `n->king` to decide whether to
*strip* the KING bit when reversing the move:

```cpp
if (n->jump) memmove(b,jumpboards[--nextjump],sizeof(b));
else {
  b[n->from] = b[n->to];
  if (n->king) b[n->from] &= (WHITE|BLACK);   // strips KING
  b[n->to] = EMPTY;
}
```

so undoing that specific white-king move incorrectly demotes an
already-crowned king back to a plain piece. Reads like a straightforward
precedence slip (the author likely intended `&&` to short-circuit the
whole kinging decision, not just gate which ternary branch runs) rather
than an intentional design choice — there's no comment justifying
checking `j<=8` unconditionally for an already-crowned piece.

**Status: not verified against FLTK's issue tracker.** **Ported
faithfully, not fixed**: `samples/test/checkers.d`'s `movepiece()`
reproduces the exact same parse at both call sites
(`(!(oldpiece & KING) && n.who) ? (j >= 36) : (j <= 8)`, parens added
only to make the preserved grouping explicit, not to change it) — see
that file's own top comment for the same writeup. No fldtk-specific
consequence beyond reproducing upstream's own gameplay quirk (this
isn't a memory-safety-relevant bug the way some other entries in this
file are, so there's no "faithful replication would crash a
bounds-checked D array" reason to deviate here).

### `fluid::end_with_slash()` (`fluid/tools/filename.cxx`): undefined behavior on an empty string

Found while porting `fluid/tools/filename.cxx` to `fluid/source/fluid/path_util.d`.

```cpp
std::string fluid::end_with_slash(const std::string &str) {
  char last = str[str.size()-1];
  ...
```

`std::string::size()` returns `size_t` (unsigned). For an empty string,
`str.size()-1` underflows to `SIZE_MAX`, and `str[SIZE_MAX]` is an
out-of-bounds `operator[]` call — undefined behavior, not the
well-defined "returns the null terminator" case (`operator[](size())`
is the one index at-or-past `size()` that's specified to be safe;
`SIZE_MAX` isn't `size()` for any non-`SIZE_MAX+1`-length string).

**Status: not verified against FLTK's issue tracker; likely low real-
world impact** — every current caller of `end_with_slash()` passes a
real, non-empty directory path, so this is a latent landmine, not an
observed crash. **Not reproduced in the port**: `fluid.path_util.
endWithSlash("")` returns `""` unchanged rather than indexing out of
bounds — a deliberate, documented deviation (that function's own doc
comment), not an oversight, since D's bounds-checked array indexing
would `RangeError`/panic on the equivalent access rather than silently
reading adjacent memory, and there's no reason to introduce a crash
where returning the (arguably correct) empty-string answer costs
nothing.

### `fl_filename_shortened()` (`fluid/tools/filename.cxx`): unclamped byte-offset math for a very small `max_chars`

Found while porting the same file. `left_chars = (max_chars - ell_bytes)/2`
(`ell_bytes` is `3`, the literal length of `"..."`) can go negative for
`max_chars < 3` (C++ signed integer division truncates toward zero, so
e.g. `(1-3)/2 == -1`), and that negative value is then passed straight
into `fl_utf8strlen(homed_filename.c_str(), left_chars)` as a char
count with no clamp — that function's own contract for a negative
count isn't obviously safe (loops of the form `while (n-- > 0)` on a
plain `int` would run until the string's own null terminator stops
them by accident, not by design, if `n` is passed as a small negative
number cast/promoted awkwardly at the call boundary).

**Status: not verified against FLTK's issue tracker; almost certainly
unreachable in practice** — every real call site passes a title-bar-
sized `max_chars` (tens of characters), never a value anywhere near 3.
**Not reproduced in the port**: `fluid.path_util.filenameShortened()`
clamps `leftChars`/`rightStart` into `[0, numChars]` explicitly before
slicing the `dstring` array it works over — see that function's own
doc comment. This one's more "belt-and-suspenders while already
rewriting the byte-offset arithmetic as codepoint-array slicing
anyway" than a bug anyone is likely to hit, but worth recording since
the clamping is a real, deliberate difference from upstream's own
unchecked math, not something upstream itself also does.

### `Window_Node::newposition()` (`fluid/nodes/Window_Node.cxx`): `FD_BOTTOM` clamp compares against `bt+dx`, not `bt+dy`

Found while porting the interactive editor's mouse-driven move/resize
(`fluid.canvas.ProjectCanvas.applyDrag()`). `newposition()`'s per-widget edge-clamp
logic is otherwise a clean, symmetric X/Y pair — `FD_LEFT`/`FD_RIGHT`
clamp against `bx+dx`/`br+dx` (the horizontal delta), `FD_TOP` clamps
against `by+dy` (the vertical delta) — but `FD_BOTTOM`'s own clamp
reads:

```cxx
if (drag&FD_BOTTOM) {
  if (T==bt) {
    T += dy;
  } else {
    if (T>bt+dx) T = bt+dx;   // <- dx, not dy
  }
}
```

Both the assignment and the comparison in that `else` branch use `dx`
where every other edge in the same function uses the delta matching
its own axis. Since a bottom-edge drag is a vertical operation, this
looks like a straightforward copy-paste typo (`FD_RIGHT`'s block just
above it is the same shape with `dx` throughout) rather than
intentional — it would only actually matter for a *multi-selection*
resize where one selected widget's bottom edge doesn't coincide with
the group's own bottom edge (the `else` branch's whole purpose is
clamping that non-touching-edge case so it can't invert past the new
bound), and only when the horizontal and vertical drag deltas differ,
a fairly narrow combination to notice interactively.

**Status: not verified against FLTK's issue tracker.** **Ported
faithfully, not silently corrected**: `fluid.canvas.ProjectCanvas.
applyDrag()`'s own `dragBottom` branch reproduces the same `dragBt_ +
ddx` comparison (see that function's own doc comment, which points
back here) rather than "fixing" it to `+ ddy` on this port's own
authority — matching CLAUDE.md's "log it, don't quietly fix it" policy
for an unconfirmed upstream bug.

### `widget_panel.fl`'s Size Range fields: tooltips copied from the Values group, not their own

Found while porting every tooltip in `widget_panel.fl` verbatim into
`fluid/panels/widget_panel.d`. The "Minimum Size:"/(unlabeled height) `Fl_Value_
Input`s in the GUI tab's Size Range group (`sr_min_w`/`sr_min_h`, uid
`887c`/`8947`, lines 1447/1465) carry `tooltip {The size of the
slider.}`/`tooltip {The minimum value of the widget.}` — word-for-word
identical to the *unrelated* Values group's own "Size:"/"Minimum:"
tooltips just above them in the same file (uid `0a71`/`9310`, lines
1151/1183), which describe a slider's own size and a valuator's own
minimum, neither of which has anything to do with a window's size-range
constraint. The "Maximum Size:"/(unlabeled) pair right next to them
(`sr_max_w`/`sr_max_h`, lines 1503/1521) do NOT have this problem —
their own tooltips ("The maximum value of the widget."/"The resolution
of the widget value.") are *also* copied from the Values group
(Maximum/Step) rather than written fresh for Size Range, but at least
land on the right general Field within the reused text. Confirmed not
a copy-paste of some OTHER Size-Range-appropriate template that just
happens to say "slider"/"widget" generically -- these four upstream
`Fl_Value_Input`s are consecutive lines in the same file (uid `0a71`,
`9310`, `30ee`, `647f`), and Size Range's own four fields' tooltips
match all four of them in the same order, exactly the shape a whole-
block copy-paste produces.

**Status: not verified against FLTK's issue tracker.** **Ported
faithfully, not silently corrected**: `widget_panel.d`'s
`sizerangeMinW`/`sizerangeMinH` carry the exact same (wrong-context)
tooltip text as FLTK: the policy for this panel is to match FLTK exactly
apart from FLTK-vs-fldtk naming and C++-vs-D differences, and this isn't a
naming/language difference but a content bug, so the port's own copy stays
bug-for-bug faithful rather than silently improved.

### `settings_panel.fl`'s User-tab "Reset" button assigns a color constant to a font field

Found while porting `Node_Browser`'s per-role text-styling
fields (`fluid.node_browser`'s `labelColor`/`classFont`/etc, the User
tab's real backing feature). The "Reset" button's callback
(`~/Repositories/fltk/fluid/panels/settings_panel.fl`, uid `4df2`,
lines ~1904-1922) resets all 12 static fields to their defaults —
eleven of the twelve match `Node_Browser.cxx`'s own real static
initializers exactly, but the twelfth doesn't:

```
Node_Browser::comment_color = FL_DARK_GREEN;
Node_Browser::comment_font = FL_DARK_GREEN;
```

`comment_font` is an `Fl_Font`, not an `Fl_Color` — `Node_Browser.cxx`'s
own static initializer for it is `Fl_Font Node_Browser::comment_font =
FL_HELVETICA;` (line 65), two lines below `comment_color`'s own
`FL_DARK_GREEN` initializer (line 64) that this callback appears to
have accidentally copied down into the font field too. `Fl_Font` is a
plain integer typedef, so this compiles silently in C++ and just sets
the comment line's rendering font to whatever numeric font index
`FL_DARK_GREEN`'s own value happens to be — very likely not a valid/
intended font selection, and definitely not `FL_HELVETICA`, the
field's own real default everywhere else in the file.

**Status: not verified against FLTK's issue tracker.** **Not
replicated in the port**: `fluid.node_browser`'s own reset logic uses
the real default (`commentFont = helvetica`), matching `Node_Browser.
cxx`'s own static initializer rather than this callback's own
apparent copy-paste slip — a visibly-wrong font swap on every Reset
click isn't the kind of subtle behavioral nuance this project's
"preserve genuine quirks" policy is meant to protect, unlike e.g. the
`applyDrag()` entry above.

### `Formula_Input::eval_var()` (`fluid/widgets/Formula_Input.cxx`): doesn't consume the identifier when no variable table is set

```cpp
int Formula_Input::eval_var(uchar *&s) const {
  if (!vars_)
    return 0;
  // find the end of the variable name
  uchar *v = s;
  while (isalpha(*s)) s++;
  ...
```

The early `if (!vars_) return 0;` returns before the `while (isalpha(*s))
s++;` loop ever runs, so `s` is left pointing at the *start* of the
identifier, not past it. The caller (`eval()`) then reads the identifier's
own first letter again as if it were a binary operator, hits the "syntax
error" fallthrough, and the whole expression evaluates short — e.g. `"x+1"`
with no variable table set evaluates to `0`, not `1` (the `+1` is never
reached at all, since the second character of `x` -- which doesn't exist,
so really the *next* character after `x`, `+` itself -- gets consumed
oddly and the parse terminates). Confirmed by porting this function
byte-for-byte and hitting the exact same result in `fluid.formula_input`'s
own unit test. Likely harmless in practice: FLTK's own 4 real callers
(`widget_x_input`/`_y_input`/`_w_input`/`_h_input` in `panels/
widget_panel.fl`) always call `variables(widget_vars, q)` immediately
before every `value()` evaluation, so a real `Formula_Input` in FLTK's own
Fluid never actually evaluates with `vars_` unset -- this only surfaces if
some future caller evaluates before ever calling `variables()`.

**Status: not verified against FLTK's issue tracker.** **Faithfully
replicated in the port** (`fluid.formula_input.FormulaInput.evalVar()`
has the identical early return, and its own unit test documents the exact
`"x+1"` → `0` result as the expected, faithful behavior) rather than
"fixed" to consume-then-return-0, since this port's own 4 callers follow
the identical "always call `variables()` before evaluating" discipline
and never actually hit this path.

### `Fl_GDI_Graphics_Driver::line_style_unscaled()` (`src/drivers/GDI/Fl_GDI_Graphics_Driver_line_style.cxx`): double `DeleteObject()` of the same `HPEN` in the common case

```cpp
HPEN oldpen = (HPEN)SelectObject(gc_, newpen);
DeleteObject(oldpen);
DeleteObject(fl_current_xmap->pen);
fl_current_xmap->pen = newpen;
```

`SelectObject(gc_, newpen)` returns whatever pen was previously selected
into `gc_`. In the overwhelmingly common call pattern — `color()` always
leaves `fl_current_xmap->pen` selected into `gc_` immediately before
`line_style()`/`line_style_unscaled()` runs (the most frequent caller
being `fl_focus_rect()`'s own `fl_line_style(FL_DOT, 1); fl_rect(...);
fl_line_style(FL_SOLID, 0);` sequence, plus `rect_unscaled()`'s own
issue-#1052 `FL_CAP_SQUARE` dance for any solid rectangle stroke wider
than 1px) — `oldpen` and `fl_current_xmap->pen` are the *same* `HPEN`
value, so this deletes one live handle twice: once via `oldpen`, then
again immediately via `fl_current_xmap->pen` (still holding the identical,
now-already-deleted value at that point). `DeleteObject()` on an
already-deleted handle is documented Win32 behavior only for "the handle
is simply invalid"; the second call either silently no-ops (harmless) or,
if the OS has since reissued that same numeric handle value to an
unrelated GDI object created in between (rare, but not impossible — GDI
handle values do get recycled), silently deletes or corrupts that
unrelated object instead. Confirmed by direct inspection, not just
inference: `color()`'s own `SelectObject(gc_, xmap.pen)` call
(`Fl_GDI_Graphics_Driver_color.cxx`) is unconditionally the last thing to
touch `gc_`'s selected pen before either of `line_style_unscaled()`'s two
real-world call sites runs.

**Status: not verified against FLTK's issue tracker.** **Deviated from in
the port** (`fl.gdi_graphics_driver.GdiGraphicsDriver.
applyLineStyleUnscaled()`), not faithfully replicated. The bug is a real
Windows crash (any scheme/focus change after a widget had gained
keyboard focus, i.e. exactly the `fl_focus_rect()` path above), traced
with `AddVectoredExceptionHandler`-based crash diagnostics (see
`fl.platform_win32`'s own doc comment on that mechanism) to a
GDI-handle-table corruption one call removed from the actual fault. Fixed
by deleting only `currentXmap_.pen` — the cache's own retired pen, exactly
once — and never touching whatever `SelectObject()` happened to report as
previously selected, matching the already-safe `setXmap()`/`clearXmap()`
pattern elsewhere in the same file. Same category as this file's
`Fl_Text_Buffer::copy()` entry above: a real, silent-corruption-shaped
bug worth deviating from, not a faithfully-reproducible behavioral quirk
worth preserving.

### `Fl_GDIplus_Graphics_Driver::line_style()` (`src/drivers/GDI/Fl_GDI_Graphics_Driver_line_style.cxx`): cap/join dispatch tests raw bits that overlap, so `FL_CAP_SQUARE`/`FL_JOIN_BEVEL` are unreachable

```cpp
if (style & FL_CAP_ROUND ) {
    pen_->SetStartCap(Gdiplus::LineCapRound);
    ...
} else if (style & FL_CAP_SQUARE ) {
    pen_->SetStartCap(Gdiplus::LineCapSquare);
    ...
} else { /* flat */ }
```

`FL_CAP_ROUND` is `0x200` and `FL_CAP_SQUARE` is `0x300` (`FL/fl_draw.H`).
`0x300 & 0x200 == 0x200`, which is truthy — so a caller requesting
`FL_CAP_SQUARE` (style value `0x300`) hits the `style & FL_CAP_ROUND`
test *first* and takes the round-cap branch; the square-cap `else if`
is dead code, never reachable for any style value. The identical
pattern repeats immediately below for join style: `FL_JOIN_MITER`
(`0x1000`) and `FL_JOIN_BEVEL` (`0x3000`) have the same bit-containment
relationship (`0x3000 & 0x1000 == 0x1000`), so `FL_JOIN_BEVEL` always
takes the miter-join branch instead of its own. Confirmed by reading
the real bit values in `FL/fl_draw.H`, not assumed: these are genuine
2-bit fields (cap at bits 8-9, join at bits 12-13), meant to be tested
via `(style>>8)&3`/`(style>>12)&3`, not via `&` against one of the
field's own encoded values — which is exactly how this same file's own
sibling, `Fl_GDI_Graphics_Driver::line_style_unscaled()` (the plain-GDI
path, immediately above this function in the same file), correctly
extracts them, via a 4-entry `Cap[]`/`Join[]` lookup table indexed by
the shifted-and-masked field. The GDI+ path's own hand-rolled if/else
chain doesn't reuse that already-correct pattern and gets it wrong.
Net effect: any FLTK program built with `USE_GDIPLUS` that explicitly
requests `FL_CAP_SQUARE` or `FL_JOIN_BEVEL` silently gets round caps or
mitered joins instead, GDI+-only (the plain GDI build is unaffected).

**Status: not verified against FLTK's issue tracker.** **Deviated from
in the port** (`fl.gdiplus_graphics_driver.GdiPlusGraphicsDriver.
lineStyle()`), not faithfully replicated — found while porting
the GDI+ driver, by cross-referencing this
function against its own sibling `line_style_unscaled()` in the same
file rather than transliterating in isolation. Fixed by reusing that
sibling's own already-correct `(style>>8)&3`/`(style>>12)&3` table
shape for the GDI+ pen too. A rarely-hit path (square caps and bevel
joins are less commonly requested than the defaults), which plausibly
explains why this went unnoticed — `FL_CAP_SQUARE`/`FL_JOIN_BEVEL`
requests presumably remain rare enough in real-world FLTK/GDI+ programs
that nobody has filed it.

### `test/pixmap_browser.cxx`'s `copy_cb()`: copies the shrunk preview-box size, not the original image, to the clipboard

```cpp
void copy_cb(Fl_Widget *, void *) {
  if (!img) return;
  Fl_Copy_Surface *surface = new Fl_Copy_Surface(img->w(), img->h());
  Fl_Box *tmp = new Fl_Box(FL_NO_BOX, 0, 0, img->w(), img->h(), "");
  ...
```

`file_cb()`/`load_file()` earlier in the same file calls `img->scale(b->w(),
b->h())` to fit the loaded image into the app's fixed-size preview box
(`b`, 380x380). `Fl_Image::scale()` (`src/Fl_Image.cxx`) only ever
changes `w()`/`h()` — the *display* size — never `w(int)`'s own backing
data (`data_w()`/`data_h()` stay the original, full-resolution values;
that's the whole point of `scale()` existing as a separate call from
re-decoding the file). `copy_cb()` then builds its `Fl_Copy_Surface` and
temporary drawing `Fl_Box` from `img->w()`/`img->h()` directly — i.e. from
the already-shrunk-to-fit-the-preview display size, not `img->data_w()`/
`data_h()` — so clicking "Copy" silently places a downscaled copy of the
image on the clipboard, regardless of the original file's real
resolution. Confirmed by reading `Fl_Image::scale()`'s own doc comment
(explicitly: "this does not change the pixel data, only the size that
draw() will use") — this isn't a case of `scale()` doing something
subtle; `copy_cb()` simply reads the wrong pair of accessors for its own
stated purpose (copying *the loaded image*, not *the on-screen preview*).

**Status: not verified against FLTK's issue tracker.** **Deviated from in
the port** (`source/test/pixmap_browser.d`'s `copyCb()`), not faithfully
replicated, since it is a genuine FLTK bug rather than a porting gap:
this port's `copyCb()`
temporarily resets the shared image's display size to its own
`dataW()`/`dataH()` before building the copy surface, then restores the
preview's fitted size afterward, so the clipboard gets the original,
full-resolution image regardless of how small the on-screen preview
currently is.

### `Fl_GDI_Copy_Surface_Driver::~Fl_GDI_Copy_Surface_Driver()`: frees the exact GDI handles it just gave to the clipboard

```cpp
Fl_GDI_Copy_Surface_Driver::~Fl_GDI_Copy_Surface_Driver() {
  ...
  HENHMETAFILE hmf = CloseEnhMetaFile (gc);
  if ( hmf != NULL ) {
    if ( OpenClipboard (NULL) ){
      EmptyClipboard ();
      SetClipboardData (CF_ENHMETAFILE, hmf);
      ...
      Fl_Image_Surface *surf = new Fl_Image_Surface(W, H);
      ...
      SetClipboardData(CF_BITMAP, (HBITMAP)surf->offscreen());
      Fl_Surface_Device::pop_current();
      delete surf;                 // ~Fl_GDI_Image_Surface_Driver() calls
                                    // DeleteObject((HBITMAP)offscreen) here
      CloseClipboard ();
    }
    DeleteEnhMetaFile(hmf);        // frees the same hmf just given away above
  }
  ...
}
```

Per Win32's own `SetClipboardData()` documentation: "If the function
succeeds, the system owns the object identified by the `hMem`
parameter... The application may not free the data after it has been
placed on the clipboard." This function hands both `hmf` (`CF_
ENHMETAFILE`) and `surf->offscreen()` (`CF_BITMAP`) to the clipboard via
exactly that call, then immediately frees both of the very same handles
anyway: `delete surf` reaches `~Fl_GDI_Image_Surface_Driver()`'s own
unconditional `DeleteObject((HBITMAP)offscreen)` (`external_offscreen`
is never set for a surface it created itself), and `DeleteEnhMetaFile
(hmf)` runs right after `CloseClipboard()` regardless of whether
`OpenClipboard()` even succeeded. Not merely a documentation nitpick:
**a real, reproducible failure** in this port —
pasting the resulting clipboard image into another clipboard-viewing
program (`test/clipboard.d`'s own `CF_DIB`-reading paste path, which
Windows synthesizes on demand from whatever `CF_BITMAP` currently sits
on the clipboard) reported "Clipboard image detected, but its format
isn't decodable yet" every time — consistent with the synthesis
silently failing against an already-destroyed source bitmap. Same
category as this file's `Fl_Text_Buffer::copy()` and `Fl_GDI_Graphics_
Driver::line_style_unscaled()` (double `DeleteObject()` of the same
`HPEN`) entries: a real, silent-corruption-shaped bug, not a
faithfully-reproducible behavioral quirk worth preserving.

**Status: not verified against FLTK's issue tracker.** **Deviated from
in the port** (`fl.widget_surface.CopySurface`'s Windows destructor),
not faithfully replicated, since the failure above is reproducible in
practice (not merely a stricter reading of the Win32 docs): this port duplicates each handle (`CopyEnhMetaFileW(hmf, null)`/
`CopyImage(surf.offscreen(), IMAGE_BITMAP, 0, 0, 0)`) and gives the
*duplicate* to `SetClipboardData()`, so the original `hmf`/`surf` stay
this object's own to free normally, and the clipboard's own copies are
never touched by that cleanup.

### `Widget_Node::write_code1()` / `Menu_Item_Node::write_code1()` (`fluid/nodes/Widget_Node.cxx`, `fluid/nodes/Menu_Node.cxx`): `use_FL_COMMAND` swaps the Ctrl and Meta meanings when Fluid runs on X11/Windows

```cpp
if (Fluid.proj.use_FL_COMMAND) {
  if (s & FL_CTRL) { f.write_c("FL_CONTROL|"); s &= ~FL_CTRL; }
  if (s & FL_META) { f.write_c("FL_COMMAND|"); s &= ~FL_META; }
}
```

`FL/platform_types.h` defines `FL_COMMAND` as `FL_CTRL` on X11/Windows and
`FL_META` on macOS, and `FL_CONTROL` as `FL_META` on X11/Windows and
`FL_CTRL` on macOS. The block above maps the `FL_CTRL` bit to the name
`FL_CONTROL` and the `FL_META` bit to `FL_COMMAND`, which keeps each
shortcut's meaning only when Fluid itself runs on macOS. Run on X11 or
Windows, a shortcut recorded as Ctrl+S is written as `FL_CONTROL|'s'`,
and a generated program built for the same platform compiles that to
`FL_META|'s'` (Meta+S) — the opposite modifier — while the checkbox's own
tooltip says it *replaces* `FL_CTRL`/`FL_META` with `FL_COMMAND`, i.e. the
portable spelling. Inferred from reading the macros and the block; not
run against a built upstream Fluid.

**Status: not verified against FLTK's issue tracker.** **Deviated from
in the port** (`fluid.code_writer.shortcutExpression()`): the bit equal
to `stateCommand` is written as `stateCommand` and the bit equal to
`stateControl` as `stateControl`, which preserves each shortcut's meaning
on the platform the port targets (`fl.enumerations` maps them for X11).
The same function also escapes `'` and `\` inside the character literal
(upstream writes `'''` and `'\'`, which are not valid C++/D).

### `Mergeback::analyse_callback()`/`apply_callback()` (`fluid/proj/mergeback.cxx`): menu-item callback edits can never be merged back

```cpp
Node *tp = proj_.tree.find_by_uid(uid);
if (tp && tp->is_true_widget()) { ... }
```

`Menu_Item_Node` overrides `is_true_widget()` to return `0`
(`nodes/Menu_Node.h`), and only `Widget_Node` returns `1`. But
`Menu_Node.cxx` writes `MENU_CALLBACK` tags (with the menu item's own
uid) around each menu callback, and `analyse()`/`apply()` route
`MENU_CALLBACK` and `WIDGET_CALLBACK` tags to the same two functions, so
the lookup for a menu callback's uid always finds a node that fails the
`is_true_widget()` test. Every edited menu callback is therefore counted
as "no Node can be found" and never applied. Inferred from reading the
source; not run against a built upstream Fluid.

Also in `apply()`: `block_end` is only updated when a non-tag line is
read, so a block with no lines between two tags reuses the previous
block's end and can hand `read_and_unindent_block()` a negative size.

**Status: not verified against FLTK's issue tracker.** **Deviated from
in the port** (`fluid.mergeback.Mergeback`): any `WidgetNode`, menu items
included, is a valid callback target, and a block ends at the start of
the tag line that closes it.

### `Fl_Screen_Driver::transient_scale_display()` (`src/Fl_Screen_Driver.cxx`) + `Fl_WinAPI_Window_Driver::makeWindow()` (`Fl_win32.cxx`): the Ctrl-`+`/Ctrl-`-`/Ctrl-`0` percentage popup likely steals focus on real Windows too

`transient_scale_display()` creates its popup with a plain `new
Fl_Window(...)` and never calls `border(0)` on it (`Fl_Screen_
Driver.cxx:454`), despite `win->shape(img)` giving it a custom rounded
shape a moment later -- so on Windows, `makeWindow()`'s own `wintype`
switch (`Fl_win32.cxx:2335-2341`) sees a *bordered* top-level and takes
the `WS_DLGFRAME | WS_CAPTION` branch, not the `WS_POPUP |
WS_EX_TOOLWINDOW` one reserved for borderless windows -- `win->
set_output()`'s call a few lines later has no corresponding check
anywhere in `makeWindow()` at all (confirmed by reading it directly,
not assumed). The later `ShowWindow(..., (Fl::grab() || (styleEx &
WS_EX_TOOLWINDOW)) ? SW_SHOWNOACTIVATE : SW_SHOWNORMAL)` call would
therefore use `SW_SHOWNORMAL` for this window (no grab active, no
`WS_EX_TOOLWINDOW` bit set), which activates it normally on show --
the popup steals keyboard focus from the actual application window
every time it appears, which would explain why rapid-fire Ctrl-`+`
presses on Windows need to wait roughly the popup's own 1-second
lifetime between each one (each press's focus lands on the *new*
popup, not the window whose shortcut handler needs to see the next
press). Inferred from reading the source directly, not run against a
built upstream Windows FLTK (no Windows toolchain available where this
was found) -- consistent with, but not independently confirmed
against, a real user report of the identical symptom in this port.

**Status: not verified against FLTK's issue tracker.** **Deviated from
in the port** (`fl.platform_win32.createWindow()`): a window with
`Widget.output()` set is treated as non-activating regardless of its
`border()` state (`showNoActivate`'s own comment), closing this gap for
fldtk's own port of `transientScaleDisplay()` without waiting on a FLTK
fix.

This only works because `createWindow()` doesn't pass `WS_VISIBLE` to
`CreateWindowExW()`. FLTK's own equivalent call (`Fl_win32.cxx`'s
`makeWindow()`, ~line 2427) never adds `WS_VISIBLE` to `style` for *any*
window kind, precisely so the later, activation-aware `ShowWindow()` call
is the only thing that ever makes the window visible (see that call's own
preceding comment: "Needs to be done before ShowWindow() to get the
correct behavior when we get WM_SETFOCUS"). Creating the window
pre-visible would make Windows show (and activate) it as part of
`CreateWindowExW()` itself, before `ShowWindow(hwnd, showNoActivate ?
SW_SHOWNOACTIVATE : ...)` ever ran, so the `output()`-based
`showNoActivate` flag would be computed correctly but too late to matter.
The port matches FLTK here for every window kind.

### `ms2fltk()` (`src/Fl_win32.cxx:1112-1196`): `FL_Shift_R` is unreachable, so right Shift reports as `FL_Shift_L`

```cpp
{VK_SHIFT,    FL_Shift_L,     FL_Shift_R},
...
Fl::e_keysym = Fl::e_original_keysym = ms2fltk(wParam, lParam & (1 << 24));
```

`vktab`'s third column is used only when the extended-key bit (lParam
bit 24) is set. That works for `VK_CONTROL` and `VK_MENU`, because right
Ctrl and right Alt (AltGr) are extended keys. Right Shift is not: Windows
reports both Shift keys as `VK_SHIFT` without the extended bit, and the
only difference is the scan code (0x2A left, 0x36 right). So the
`FL_Shift_R` entry is never selected, and a program checking
`Fl::event_key() == FL_Shift_R` never sees it on Windows, while it does
on X11. `MapVirtualKeyW(scanCode, MAPVK_VSC_TO_VK_EX)` returns
`VK_LSHIFT`/`VK_RSHIFT` and would fix it. Inferred from reading the
source and the Win32 keyboard-input documentation; not run against a
built upstream FLTK.

**Status: not verified against FLTK's issue tracker.** **Deviated from
in the port** (`fl.platform_win32.vkToKeysym()`): `VK_SHIFT` is resolved
by scan code as above, giving `shiftR` for right Shift. The port's
right Ctrl/right Alt/keypad Enter handling follows upstream's
extended-bit table as-is.

### `ms2fltk()` (`src/Fl_win32.cxx:1164-1174`): punctuation keysyms are the US characters on every layout

```cpp
{0xba,        ';'},
{0xbb,        '='},   // 0xbb == VK_OEM_PLUS (see #1086)
...
{0xde,        '\''},
```

The `VK_OEM_*` codes name a physical key, and each layout assigns its
own characters to it. This table returns the US character regardless,
so on a German layout the key that types `ö` reports `Fl::event_key()
== ';'`, `ü` reports `'['` and `ß` reports `'-'`. On X11, FLTK reports
the layout's own unshifted keysym for the same keys (`XK_odiaeresis`,
etc.), so the two platforms disagree, and a shortcut such as `FL_CTRL |
0xf6` (Ctrl+ö) can never match on Windows. `MapVirtualKeyW(vk,
MAPVK_VK_TO_CHAR)` gives the active layout's unshifted character. This
is a design limitation rather than a bug, and looks deliberate (the
Ctrl-`+` workaround in `fl_handle()` relies on `VK_OEM_PLUS` being
`'='`).

**Status: not verified against FLTK's issue tracker.** **Deviated from
in the port** (`fl.platform_win32.oemKeysym()`):
these keys report the active layout's unshifted character, lowercased,
with the US table kept as a fallback. `keyEvent()`'s Ctrl-`+`
workaround tests the `VK_OEM_PLUS` code instead of `keysym == '='` so
it still fires on layouts where that key's character is `'+'`.
### `Fl_WinAPI_Screen_Driver::event_key(int)`/`get_key(int)` (`src/Fl_get_key_win32.cxx`): mouse buttons always report "not held"

`fltk2ms()` has no case for `FL_Button + n`, so it returns 0 and
`GetKeyState(0)` answers 0 for every mouse button. The X11 driver
(`Fl_get_key.cxx`) special-cases `k > FL_Button && k <= FL_Button+8`
and answers from `Fl::event_state()`, so `Fl::event_key(FL_Button+1)`
works on X11 and never does on Windows (`test/keyboard`'s mouse-button
indicators stay off there). Inferred from reading the source; not run
against a built upstream FLTK.

**Status: not verified against FLTK's issue tracker.** **Deviated from
in the port** (`fl.platform_win32.eventKey()`/`getKey()`): the same
`eventState()` check as `fl.platform_x11.eventKey()`. The reverse
keysym table also follows the port's layout-aware `oemKeysym()` (see
the `ms2fltk()` punctuation entry above): printable characters go
through `VkKeyScanW()` instead of `fltk2ms()`'s US-only table.
### `Fl_WinAPI_Window_Driver::maximize()` (`src/drivers/WinAPI/Fl_WinAPI_Window_Driver.cxx:630`): a borderless window's maximize flag is cleared again at once, so `un_maximize()` does nothing

```cpp
void Fl_WinAPI_Window_Driver::maximize() {
  if (!border()) return Fl_Window_Driver::maximize();
  ...
```

`Fl_Window::maximize()` sets `MAXIMIZED` and calls this. For a
borderless window the generic `Fl_Window_Driver::maximize()` hides the
window (`maximize_needs_hide()` is true on Windows), resizes it to the
work area and shows it again. The re-created window gets a `WM_SIZE`
with `SIZE_RESTORED`, and `Fl_win32.cxx:1799` runs
`is_maximized(wParam == SIZE_MAXIMIZED)` on every `WM_SIZE`, which
clears `MAXIMIZED`. So right after `maximize()` returns,
`maximize_active()` is false, and `un_maximize()` returns early on its
`!maximize_active()` gate without restoring the saved geometry. In
`test/fullscreen` with "Border" off, the maximize toggle would grow the
window but never shrink it back. Inferred from reading the source; not
run against a built upstream FLTK.

**Status: not verified against FLTK's issue tracker.** **Deviated from
in the port** (`fl.platform_win32.maximizeOn()`): the flag is set again
after the fallback's `show()`, so `unMaximize()` restores the window.
A related case (maximize with a border, then `border(0)`, then
`un_maximize()`): `un_maximize()` chooses the
generic path from `border()` at the time of the call, but only the
generic `maximize()` records `no_fullscreen_*`; a system maximize
(`SW_SHOWMAXIMIZED`) records nothing. With the border removed in
between, the generic `un_maximize()` resizes to the zeroed values, i.e.
a 0x0 window at 0,0 -- borderless, so with no taskbar entry either. In
the port the window vanishes exactly this way. Whether FLTK reaches
it depends on `MAXIMIZED` surviving `border(0)`'s hide/show (the
re-created window's first `WM_SIZE` arrives before `fl_find()` can see
it); not checked against a built upstream FLTK. **Deviated from in the
port** (`fl.platform_win32.maximizeOn()`/`maximizeOff()`,
`fl.window.Window.unMaximizeByResize()`): the geometry is recorded on
both paths, the restore path is chosen by `IsZoomed()`, and a resize to
unrecorded geometry is skipped.
### `fl_WndProc()` (`src/Fl_win32.cxx:1554`): the `WM_KEYDOWN` character lookahead spans `WM_SYSKEYDOWN`/`WM_SYSKEYUP`

To find the character a key press produced, `WM_KEYDOWN` peeks the
queue with `PeekMessageW(&fl_msg, hWnd, WM_CHAR, WM_SYSDEADCHAR,
PM_REMOVE)`. That range (0x102-0x107) also contains `WM_SYSKEYDOWN`
(0x104) and `WM_SYSKEYUP` (0x105). When a key produces no character
(F1, an arrow, Ctrl+punctuation) and an Alt+key message is already
queued behind it, the peek removes that message and handles it as the
first key's character: its virtual-key code becomes `Fl::e_text`, and
the Alt+key press itself is lost. Inferred from reading the source; not
run against a built upstream FLTK.

**Status: not verified against FLTK's issue tracker.** **Deviated from
in the port** (`fl.platform_win32.keyEvent()`): two peeks,
`WM_CHAR..WM_DEADCHAR` and `WM_SYSCHAR..WM_SYSDEADCHAR`.

### `Fl_GDI_Graphics_Driver::cache(Fl_RGB_Image*)`/`draw_fixed()` (`src/drivers/GDI/Fl_GDI_Graphics_Driver_image.cxx:555-600`): the dithered-mask fallback ORs transparent pixels into the background

When `fl_can_do_alpha_blending()` is false, `cache()` draws the RGBA
image into an offscreen with its alpha ignored and builds a 1-bit
dither mask with `create_alphamask()`. `draw_fixed()` then blits the
mask with `SRCAND` and the offscreen with `SRCPAINT`. That technique
needs the color image to be black wherever the mask is transparent,
otherwise `SRCPAINT` ORs the image's color into the background the
`SRCAND` pass kept. The offscreen holds the full RGB value at every
pixel, so transparent pixels come out as background OR color: a
washed-out, often near-white blend instead of the background. Inferred
from reading the source; not run against a built upstream FLTK (the
path needs a display or printer driver without `AlphaBlend()`).

**Status: not verified against FLTK's issue tracker.** **Deviated from
in the port** (`fl.gdi_graphics_driver.drawImageDitheredMask()`):
pixels the mask leaves transparent are left black in the color bitmap.
With the fallback forced on, the port's unfixed version showed
`test/image`'s "Image w/Alpha" with its densest background where alpha
is mid-range and none at the fully transparent centre.

### `Fl_GDI_Graphics_Driver::arc_unscaled()`/`pie_unscaled()` (`src/drivers/GDI/Fl_GDI_Graphics_Driver_arci.cxx`): printed arcs and pies are one unit too large at the right and bottom

`arc_unscaled()` widens its bounding box (`w++; h++`) and
`pie_unscaled()` shifts and shrinks it (`x++; y++; w--; h--`) before
calling GDI `Arc()`/`Pie()`. Those adjustments assume
`GM_COMPATIBLE`, where `Arc()`/`Pie()` exclude the bounding rectangle's
right and bottom edges. The printer DC is put in `GM_ADVANCED`
(`Fl_WinAPI_Printer_Driver`, to allow rotation), where those edges are
included, so on paper every arc and pie extends one logical unit (one
point) further right and down than on screen and than the straight
lines drawn next to it. Visible on a printed `FL_ROUND_UP_BOX`: the
bottom edge (`fl_xyline()`) sits above the rounded ends (`fl_arc()`).

**Status: not verified against FLTK's issue tracker.** Confirmed on
real hardware in the port, whose code is identical (printing
`test/device` to Microsoft Print to PDF and to a physical printer);
not run against a built upstream FLTK. **Deviated from in the port**
(`fl.gdi_graphics_driver.GdiGraphicsDriver.advancedModeEdge()`): in
`GM_ADVANCED`, the right/bottom of the rectangle passed to
`Arc()`/`Pie()` is reduced by one.
