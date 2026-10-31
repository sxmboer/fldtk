# Performance benchmarks: fldtk vs. FLTK

Informal, reproducible timing comparisons between this port and real FLTK
FLTK, built from a local FLTK checkout. These are
not a rigorous benchmark suite -- just concrete numbers gathered while
investigating specific, observed behavior, kept here so they're not lost and
can be redone later (see "Future work" below).

**Current build config for every number below**: `dmd`, no `-O`, no
`-release` -- a plain debug build of `libfldtk.so` (array bounds checks,
contracts, and asserts all still enabled) linked against FLTK's own
default CMake `Release`-configured build. This is *not* an apples-to-apples
optimization-level comparison yet; see "Future work."

## Methodology

Every timing here was taken against a headless `Xvfb` virtual display (`Xvfb
:99 -screen 0 1024x768x24`), not the real desktop session: a program is
launched against a fully isolated headless display with zero interaction,
purely to observe its own timing/exit behavior, so nothing ever drives the
real mouse or keyboard.

Two different measurement techniques were needed:

- **Wall-clock / CPU time to first window**: launch the program in the
  background, poll (read-only `xwininfo -root -tree`, no synthetic input)
  until a window with the expected title appears, then send `SIGTERM`
  immediately. Wall time is measured from process launch to the window
  appearing; CPU `user`/`sys` time is read from `/proc/<pid>/stat` right
  before the kill signal. `SIGTERM` does not run druntime's normal shutdown
  path, so this technique cannot report GC profiling stats -- only raw
  timing.
- **GC profiling** (collection count/total time): needs the process to reach
  a *normal* exit, since druntime's `--DRT-gcopt=profile:1` summary prints
  from its own termination hook, which `SIGTERM` (and even `core.stdc.exit()`,
  which bypasses druntime's own runtime-termination path the same way)
  skips entirely. For this, a scratch-only copy of the sample had a
  `fl.addTimeout(0.2, () { win.hide(); });` line added right after
  `win.show()`, so the program drives its own clean shutdown through the
  ordinary `Window.hide()` path and `main()` returns normally. This variant
  is not committed anywhere -- it exists only to get real profiler numbers
  and was discarded after use.

## `tree-as-container` (`source/examples/tree_as_container.d`, FLTK
`examples/tree-as-container.cxx`)

Builds an `Fl_Tree`/`Tree` containing 20,000 rows x 5 `Fl_Input`/`Input`
fields each (100,000 input widgets total, `MAX_ROWS`/`MAX_FIELDS` in the
FLTK source) -- a single large, allocation-heavy burst of long-lived
widget construction, all before the window is ever shown.

### Time to first window appearance

| Build | time to window | user CPU | sys CPU |
|---|---|---|---|
| fldtk, `--DRT-gcopt=disable:1` (GC collection off) | 6.9 - 7.0s | 6.2 - 6.4s | 0.6 - 0.7s |
| fldtk, default GC (parallel marking on) | 10.85s | 17.83s | 0.14s |
| fldtk, `--DRT-gcopt=parallel:0` (marking single-threaded) | 12.99s | 12.94s | 0.03s |
| real FLTK (C++, manual memory management) | 14.20s | 14.13s | 0.05s |

`user` exceeding wall-clock time means genuine multi-core work, not a
measurement artifact -- druntime's default GC supports parallel heap marking
(`core.cpuid.threadsPerCPU - 1` worker threads by default) and this workload
triggers it. With parallel marking forced off, fldtk's `user` time collapses
back to match wall time almost exactly, i.e. genuinely single-threaded,
directly confirming parallel marking (not anything in fldtk's own code) as
the source of the multi-core usage in the default row.

### GC collection profile (`--DRT-gcopt=profile:1`, self-terminating scratch
variant -- see Methodology)

| GC mode | collections | total GC time | mark time | heap at exit |
|---|---|---|---|---|
| default (parallel marking) | 430 | 2975ms | 2901ms | 70 MB |
| `parallel:0` | 430 | 5249ms | 5185ms | 70 MB |
| `disable:1` | 1 | 20ms | 19ms | 1739 MB |

**Interpretation**: this is not a bug, and the cost is not really "GC
overhead" in the generic sense people usually mean by that -- it's specific
to D's *default* GC being non-generational and conservative. A
non-generational collector cannot cheaply rescan just what's allocated since
the last pass; every collection is a full heap walk. This workload allocates
~100,000 objects that are (almost) all genuinely live UI state, not garbage
-- exactly the access pattern generational collectors exist to make cheap
(scan a small young generation, promote long-lived survivors instead of
rescanning them forever) and that a non-generational collector handles at
close to its worst case: `heapSizeFactor`'s default 2x-growth trigger fired
430 separate times as the tree grew, and each of those 430 passes re-walked
a larger set of objects that were already confirmed live in every prior
pass. The *single* shutdown-time collection (present in all three rows, via
druntime's default `cleanup:collect` termination behavior) took only ~20ms
even over the full ~1.7GB `disable:1` heap in one pass -- so a full scan
itself is cheap; doing it 430 times is what's expensive.

Disabling collection entirely is a genuine win here on speed (both the
fastest wall-clock time to window *and* the only row where `user` CPU time
comes in **below** wall-clock time, i.e. real idle time rather than
saturated computation) but is a real time/memory trade, not a free lunch:
heap size at exit balloons to 1739 MB vs. 70 MB with collection left on,
since nothing is ever reclaimed. Appropriate for a short-lived burst-then-
mostly-static-UI construction phase like this one; not a blanket
recommendation to disable collection for the lifetime of a long-running,
continuously-allocating app.

## Future work

- **Re-run with this file's own methodology now that a `-release` build
  exists (GDC only -- see `BUILDING.md`'s "Release builds" section).**
  `rdmd buildsamples.d --release` links every sample against it. The
  only numbers gathered against it so far are informal: on
  `tree_as_container`, the GDC release build ran slightly faster than
  real FLTK's own binary, and this file's plain dmd debug
  baseline above ran about twice as slow -- consistent with debug
  bounds-checks/contracts/asserts still being on for the debug build,
  but not yet a real measurement by this file's own methodology (Xvfb,
  wall-clock + `/proc` CPU time). Re-run and record it properly before
  drawing any conclusion from it.
- **A build's speed is only meaningful once its correctness is
  established.** A partial `-O`/`-inline` DMD build described in
  `BUILDING.md`'s "Release builds" section draws wrong pixels and
  segfaults on some programs; numbers from a build in that state aren't
  evidence of a real optimization win, since silently skipping or
  truncating work looks exactly like speed on a clock. Any future
  "faster" claim about a build needs a correctness check first --
  same pixels, same clean exit -- not just a timer. The GDC release
  build above passes this check: every sample has been run and behaves
  identically to its plain dmd debug build, so its own (still informal)
  `tree_as_container` timing above is trustworthy in a way the old
  partial DMD build's numbers never were.
- Extend this file with more sample programs as they come up naturally
  (don't go benchmark every program speculatively -- add an entry when a
  real investigation like this one produces numbers worth keeping, the same
  way this first entry came from a user-noticed timing anomaly, not a
  planned benchmarking pass).

## Reproduction: exact scripts and scratch code used for `tree-as-container`

Kept here verbatim so the whole investigation can be rerun identically later
-- none of this is committed anywhere else in the repo (the two `.d`
variants are throwaway scratch copies of `source/examples/tree_as_container.d`,
never meant to be tracked; the `.sh` wrapper is a standalone diagnostic tool,
not part of `buildsamples.d`).

### `timewin.sh` -- wall-clock/CPU-time-to-window measurement

Launches a program under `DISPLAY=:99`, polls (read-only `xwininfo`, no
synthetic input) until a window with the given title appears, `SIGTERM`s it
immediately, and reports wall time to appearance plus the process's own
`user`/`sys` CPU time read from `/proc/<pid>/stat` right before the kill.

```bash
#!/usr/bin/env bash
# Launches $1 (with args $3..) under DISPLAY=:99, polls (read-only,
# xwininfo -tree) until a window titled $2 appears, then SIGTERMs the
# process immediately -- no synthetic mouse/keyboard input at any point.
# Reports wall time to first-window-appearance, wall time to process
# exit after the kill, and the process's own accumulated CPU user/sys
# time (from /proc/<pid>/stat, sampled right before the kill signal).
set -uo pipefail
PROG="$1"
TITLE="$2"
shift 2

DISPLAY=:99 "$PROG" "$@" &
PID=$!
START=$(date +%s.%N)

FOUND=0
for i in $(seq 1 1200); do
    if ! kill -0 "$PID" 2>/dev/null; then
        break
    fi
    if DISPLAY=:99 xwininfo -root -tree 2>/dev/null | grep -qF "$TITLE"; then
        FOUND=1
        break
    fi
    sleep 0.05
done
APPEARED=$(date +%s.%N)

CLKTCK=$(getconf CLK_TCK)
UTIME=0
STIME=0
if [[ -r /proc/$PID/stat ]]; then
    STATLINE=$(cat /proc/$PID/stat)
    REST=${STATLINE#*) }
    read -r -a FIELDS <<< "$REST"
    UTIME=${FIELDS[11]}
    STIME=${FIELDS[12]}
fi

kill -TERM "$PID" 2>/dev/null
wait "$PID" 2>/dev/null
END=$(date +%s.%N)

if [[ $FOUND -eq 1 ]]; then
    printf 'window appeared after: %.3fs\n' "$(echo "$APPEARED - $START" | bc)"
else
    printf 'window NEVER appeared (process exited or 60s cap hit)\n'
fi
printf 'wall (launch -> killed+reaped): %.3fs\n' "$(echo "$END - $START" | bc)"
printf 'cpu at kill-time: user %.3fs, sys %.3fs\n' "$(echo "$UTIME/$CLKTCK" | bc -l)" "$(echo "$STIME/$CLKTCK" | bc -l)"
```

### `tree_as_container_gcdisabled.d` -- scratch copy with `GC.disable()`

Identical to `source/examples/tree_as_container.d` except for the added
`import core.memory : GC;` and the `GC.disable();` as the first line of
`main()`:

```d
// D transliteration of FLTK's examples/tree-as-container.cxx.
// Build: rdmd buildsamples.d examples tree_as_container
import fl;
import std.format : format;
import core.memory : GC;

enum maxRows = 20_000;
enum maxFields = 5;
enum fieldWidth = 70;
enum fieldHeight = 30;

class MyData : Group
{
    Input[maxFields] fields;

public:
    this(int X, int Y, int W, int H)
    {
        super(X, Y, W, H);
        static immutable uint[maxFields] colors = [
            0xffffdd00, 0xffdddd00, 0xddffff00, 0xddffdd00, 0xddddff00
        ];
        foreach (t; 0 .. maxFields)
        {
            fields[t] = new Input(X + t * fieldWidth, Y, fieldWidth, H);
            fields[t].color(colors[t]);
        }
        end();
    }

    void setData(int col, string val)
    {
        if (col >= 0 && col < maxFields)
            fields[col].value(val);
    }
}

void main()
{
    GC.disable();
    auto win = new DoubleWindow(450, 400, "Tree As FLTK Widget Container");
    win.begin();
    {
        // Create the tree
        auto tree = new Tree(10, 10, win.w() - 20, win.h() - 20);
        tree.showroot(false); // don't show root of tree
        // Add some regular text nodes
        tree.add("Foo/Bar/001");
        tree.add("Foo/Bar/002");
        tree.add("Foo/Bla/Aaa");
        tree.add("Foo/Bla/Bbb");
        // Add items to the 'Data' node
        foreach (t; 0 .. maxRows)
        {
            // Add item to tree
            auto item = tree.add(format("FLTK Widgets/%d", t));
            // Reconfigure item to be an FLTK widget (MyData)
            tree.begin();
            {
                auto data = new MyData(0, 0, fieldWidth * maxFields, fieldHeight);
                item.widget(data);
                // Initialize widget data
                foreach (c; 0 .. maxFields)
                    data.setData(c, format("%d-%d", t, c));
            }
            tree.end();
        }
    }
    win.end();
    win.resizable(win);
    win.show();
    fl.run();
}
```

### `tree_as_container_profiled.d` -- scratch copy for `--DRT-gcopt=profile:1`

Identical to `source/examples/tree_as_container.d` except for one added
line right after `win.show();`, so the program drives its own ordinary
shutdown path (`Window.hide()`) instead of being `SIGTERM`ed -- required
for druntime's GC profile summary to print at all, since both `SIGTERM`
and `core.stdc.exit()` skip its termination hook:

```d
    win.end();
    win.resizable(win);
    win.show();
    fl.addTimeout(0.2, () { win.hide(); });
    fl.run();
}
```
(every other line identical to the original file above, minus `GC.disable()`)

### Commands, start to finish

```bash
cd /path/to/fldtk
SCRATCH=/path/to/some/scratch/dir   # anywhere outside the repo is fine

# 1. Headless display
Xvfb :99 -screen 0 1024x768x24 &>/tmp/xvfb99.log & disown
sleep 1

# 2. Make sure libfldtk.so is current
dub build

# 3. Wall-clock/CPU comparison (timewin.sh from above, made executable)
chmod +x "$SCRATCH/timewin.sh"
"$SCRATCH/timewin.sh" build/tree_as_container "Tree As FLTK Widget Container"
"$SCRATCH/timewin.sh" /path/to/fltk/build/bin/examples/tree-as-container "Tree As FLTK Widget Container"

# GC.disable() variant: compile the scratch copy above, then:
dmd -Isource -od="$SCRATCH" -of="$SCRATCH/tree-as-container-gcdisabled" \
    "$SCRATCH/tree_as_container_gcdisabled.d" \
    libfldtk.so -L-lX11 -L-lXft "-L-rpath=$(pwd)"
"$SCRATCH/timewin.sh" "$SCRATCH/tree-as-container-gcdisabled" "Tree As FLTK Widget Container"

# parallel:0 variant: no separate binary needed, just pass the flag through
# timewin.sh's "$@" pass-through:
"$SCRATCH/timewin.sh" build/tree_as_container "Tree As FLTK Widget Container" \
    --DRT-gcopt=parallel:0

# 4. GC profiler numbers (profiled variant from above)
dmd -Isource -od="$SCRATCH" -of="$SCRATCH/tree-as-container-profiled" \
    "$SCRATCH/tree_as_container_profiled.d" \
    libfldtk.so -L-lX11 -L-lXft "-L-rpath=$(pwd)"
DISPLAY=:99 "$SCRATCH/tree-as-container-profiled" --DRT-gcopt=profile:1
DISPLAY=:99 "$SCRATCH/tree-as-container-profiled" "--DRT-gcopt=profile:1 parallel:0"
DISPLAY=:99 "$SCRATCH/tree-as-container-profiled" "--DRT-gcopt=profile:1 disable:1"

# 5. Cleanup
pkill -f "Xvfb :99"
rm -f "$SCRATCH/tree-as-container-gcdisabled" "$SCRATCH/tree-as-container-profiled" \
      "$SCRATCH"/*.o "$SCRATCH"/tree_as_container_*.d
```
