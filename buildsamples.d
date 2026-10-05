#!/usr/bin/env rdmd
/*
 * buildsamples.d [--force|-f] [test|examples] [name]
 *
 * Builds the demo programs under source/test/ and source/examples/ into
 * build/, each under its own name (`build/hello`, `build/table_sort`,
 * ...), doing only whatever staleness-driven work is actually needed --
 * the same Makefile-shaped model as buildfluid.d alongside it.
 *
 * Run: rdmd buildsamples.d          # everything, both categories
 *      rdmd buildsamples.d test      # only source/test/
 *      rdmd buildsamples.d examples  # only source/examples/
 *      rdmd buildsamples.d test hello    # one program by name
 *      rdmd buildsamples.d --force   # ignore mtimes, relink every binary
 *      rdmd buildsamples.d --release [test|examples] [name]
 *          builds against dub.sdl's "linux-release" configuration
 *          instead (build/release/libfldtk-release.so, built with gdc
 *          -- see BUILDING.md's "Release builds" section for why gdc,
 *          not dmd) with gdc as the sample compiler too, into
 *          build/release/ instead of build/ -- a way to exercise the
 *          release library with real programs without touching the
 *          debug libfldtk.so/build/ everything else here uses. Linux
 *          only, matching that dub.sdl configuration.
 *
 * `--force`/`-f` (anywhere in the argument list, combinable with a
 * category/name filter) skips the mtime staleness check entirely and
 * relinks every matching binary regardless -- an escape hatch for
 * whenever the staleness check itself is in doubt (e.g. file timestamps
 * changed by some outside tool) rather than a sign the check is wrong
 * by default; leave it off for normal day-to-day rebuilds.
 *
 * Works from any cwd -- every path is resolved from this script's own
 * location, not $PWD.
 *
 * There is no manifest file and no per-program configuration: a program
 * is simply "a .d file under source/<category>/ (or its generated/
 * subdirectory) that defines main()". Everything else there is a helper
 * module -- CubeView.d, checkers_pieces.d, fracviewer.d, resize_arrows.d
 * -- and gets pulled into whichever program imports it automatically by
 * `dmd -i`, so it needs no declaring anywhere. `-i=-fl` keeps that
 * automatic inclusion from also dragging in the fl.* library modules
 * themselves, which are linked from the already-built libfldtk.so
 * instead. The one exception is the unittest_*.d family: each tab
 * self-registers into unittests.d's registry via a module constructor
 * rather than being imported by it, so there is no import edge for
 * `dmd -i` to follow -- see `extraSources` below for how those get
 * included anyway.
 *
 * Sequence per run:
 *   1. Build libfldtk.so (`dub build`) if it is missing or older than
 *      any source/fl/*.d.
 *   2. Regenerate source/<category>/generated/<name>.d from any
 *      source/<category>/*.fl that is newer than it (or newer than the
 *      fluid binary, which picks up code-generator fixes without
 *      needing a manual delete). Building fluid first if it is missing,
 *      via buildfluid.d's own logic -- this script shells out to it
 *      rather than duplicating that bootstrap dance.
 *   3. Compile each program whose binary is missing or older than any
 *      source file it actually depends on (its own .d plus, recursively,
 *      every local .d it imports) or than libfldtk.so itself.
 */
module buildsamples;

import std.algorithm;
import std.array;
import std.datetime : SysTime;
import std.exception : enforce;
import std.file;
import std.path;
import std.process;
import std.regex : ctRegex, matchAll, matchFirst;
import std.stdio;
import std.string;

version (Windows)
    enum exeSuffix = ".exe";
else
    enum exeSuffix = "";

/// Programs that are known not to build, with the reason. Each is a real,
/// documented gap rather than a regression -- see CONVENTIONS.md's "Deferred:
/// external-library-backed features" and "Out of scope: XForms/Forms
/// Library compatibility" sections. Skipped with their reason printed,
/// so the run stays green and the exceptions stay visible.
enum string[string] skip = [
    "cairo_test":    "needs a Cairo backend (deferred -- no port plan decided yet)",
    "cairo_draw_x":  "needs a Cairo backend (deferred -- no port plan decided yet)",
    "forms":         "XForms/Forms compatibility layer, deliberately out of scope",
    "penpal":        "needs fl.Pen; FLTK has no X11 pen/touch support either",
];

/// Programs skipped only on Windows -- unlike `skip` above (unsupported
/// on every platform), these build and run fine on Linux; they just have
/// no Windows equivalent for what they specifically need. `list_visuals`
/// dumps real X11 `XVisualInfo` records via `fl.xlib`/`fl.platform_x11`,
/// both `version (linux):`-gated modules with no Windows-side API at all
/// -- there's no "Windows visual" concept to substitute, unlike e.g.
/// `fl.gl_window_driver`'s own real GLX-vs-WGL split for GL.
enum string[string] skipWindows = [
    "list_visuals": "dumps real X11 Visuals (Xlib-only, no Windows equivalent)",
];

/// Binary names that deliberately differ from the name of the .d file
/// holding their main(), so each program keeps the name FLTK knows it by.
/// Only these three differ; everything else is named after
/// its own file.
enum string[string] renameBinary = [
    "MyWindow":    "keyboard",
    "DrawingArea": "mandelbrot",
    "CubeViewUI":  "CubeView",
];

/// Extra source files (glob patterns, relative to each search directory)
/// a program needs beyond what `localDeps()` finds by following imports.
/// `unittests.d` is the one case in this project where that's not
/// enough: each unittest_*.d tab self-registers into its registry via a
/// module constructor (`static this() { new UnitTest(...); }`) rather
/// than being imported by the main file, so there is no import edge for
/// `localDeps()`/`dmd -i` to discover -- they have to be named
/// explicitly, the same way the old per-program dub configuration used
/// to list them all in `sourceFiles`.
enum string[][string] extraSources = [
    "unittests": ["unittest_*.d"],
];

/// Extra Windows-only link libraries a program needs beyond the uniform
/// Windows `linkFlags` below. Empty now (2026-09-13) -- `fl.glew`'s
/// Windows branch no longer binds against the real system GLEW library
/// at all (Linux's own branch still does, unchanged -- see that
/// module's own doc comment for the platform split): Windows instead
/// resolves its ~26 modern GL functions itself via
/// `wglGetProcAddress()`, needing no library beyond `opengl32`, already
/// linked unconditionally via `linkFlags` below, so its two consumers
/// (`OpenGL3test`/`OpenGL3_glut_test`) no longer need a `glew32s.lib`
/// entry here either. Kept as a table (rather than deleted outright)
/// since a future sample needing some other genuinely-optional, not-
/// every-dev-machine Windows library would want the exact same per-
/// sample-only treatment GLEW itself used to need here -- unlike GLU
/// (system-standard, safe to link into every sample uniformly, see
/// `linkFlags`' own comment).
enum string[][string] extraLibsWindows = null;

/// True if `file` defines a main() function -- i.e. it is a program
/// rather than a helper module.
bool definesMain(string file)
{
    enum re = ctRegex!(`^[ \t]*(void|int)[ \t]+main[ \t]*\(`, "m");
    return !readText(file).matchFirst(re).empty;
}

/// Every local .d file `mainFile` depends on, found by following its
/// `import` statements recursively and keeping only those that resolve
/// to a real file in one of `searchDirs`. Library (`fl.*`) and Phobos
/// imports resolve to nothing here and are simply skipped -- their
/// staleness is covered by the libfldtk.so check instead.
string[] localDeps(string mainFile, const string[] searchDirs)
{
    enum importRe = ctRegex!(`^[ \t]*(?:public[ \t]+)?import[ \t]+([A-Za-z_][A-Za-z0-9_.]*)`, "m");

    bool[string] seen;
    string[] queue = [mainFile];
    string[] result;

    while (queue.length)
    {
        string current = queue[0];
        queue = queue[1 .. $];
        if (current in seen)
            continue;
        seen[current] = true;
        result ~= current;

        foreach (m; readText(current).matchAll(importRe))
        {
            // Only the leading segment can name a file in these flat
            // directories ("import widget_panel;", "import fracviewer;").
            string mod = m[1].split('.')[0];
            foreach (dir; searchDirs)
            {
                string candidate = buildPath(dir, mod ~ ".d");
                if (exists(candidate) && candidate !in seen)
                    queue ~= candidate;
            }
        }
    }

    return result;
}

/// Latest mtime among `files`; SysTime.min if the list is empty.
SysTime newestMtime(const string[] files)
{
    SysTime newest = SysTime.min;
    foreach (f; files)
    {
        auto t = timeLastModified(f);
        if (t > newest)
            newest = t;
    }
    return newest;
}

int main(string[] args)
{
    string repoRoot = dirName(buildNormalizedPath(__FILE_FULL_PATH__));

    bool force = args.canFind("--force") || args.canFind("-f");
    // --release: build against the GDC release library (dub.sdl's
    // "linux-release" configuration, build/release/libfldtk-release.so)
    // with gdc instead of dmd, for trying a release build without
    // touching the debug libfldtk.so everything else here links against
    // -- see BUILDING.md's "Release builds" section. Linux only: the
    // release configuration is Linux-only (see dub.sdl), and this whole
    // flag exists only to test that one library build.
    bool release = args.canFind("--release");
    string[] positional = args[1 .. $]
        .filter!(a => a != "--force" && a != "-f" && a != "--release").array;

    string categoryFilter = positional.length > 0 ? positional[0] : "";
    string nameFilter = positional.length > 1 ? positional[1] : "";

    if (categoryFilter.length && categoryFilter != "test" && categoryFilter != "examples")
    {
        stderr.writeln("usage: rdmd buildsamples.d [--release] [test|examples] [name]");
        return 1;
    }

    string[] categories = categoryFilter.length ? [categoryFilter] : ["test", "examples"];

    // dub.sdl builds fldtk as a dynamicLibrary on Linux (libfldtk.so)
    // but a staticLibrary on Windows (fldtk.lib, no .dll at all) -- see
    // that file's own comment on why (Windows DLL export-visibility,
    // found 2026-09-09). Only used here as a staleness marker.
    version (Windows)
        string libName = "fldtk.lib";
    else
        string libName = release ? "libfldtk-release.so" : "libfldtk.so";
    string libDir = release ? buildPath(repoRoot, "build", "release") : repoRoot;
    string libPath = buildPath(libDir, libName);
    string fluidBin = buildPath(repoRoot, "fluid" ~ exeSuffix);
    // Release binaries land in their own subdirectory of build/ --
    // never build/ itself -- so they can never collide with (or get
    // mistaken for) the debug binaries of the same name that ordinary,
    // no-flag runs put directly in build/.
    string buildDir = release ? libDir : buildPath(repoRoot, "build");

    // 1. The library itself, if stale.
    auto flSources = dirEntries(buildPath(repoRoot, "source", "fl"), "*.d", SpanMode.depth)
        .map!(e => e.name).array;
    if (!exists(libPath) || newestMtime(flSources) > timeLastModified(libPath))
    {
        writeln("buildsamples: building lib" ~ (release ? "fldtk-release (gdc)" : "fldtk") ~ "...");
        string[] dubArgs = release
            ? ["dub", "build", "--config=linux-release", "--build=release", "--compiler=gdc"]
            : ["dub", "build"];
        auto pid = spawnProcess(dubArgs, cast(string[string]) null, Config.none, repoRoot);
        enforce(wait(pid) == 0, "dub build failed");
    }

    int total, built, skipped;
    string[] failures;

    foreach (category; categories)
    {
        string catDir = buildPath(repoRoot, "source", category);
        string genDir = buildPath(catDir, "generated");

        // 2. Regenerate any stale .fl -> generated/*.d.
        auto flFiles = dirEntries(catDir, "*.fl", SpanMode.shallow).map!(e => e.name).array.sort.array;
        if (flFiles.length)
        {
            foreach (fl; flFiles)
            {
                // A .fl sitting next to a hand-written .d of the same
                // name is not a generator input -- it is the Fluid-
                // editable counterpart of a file that is maintained by
                // hand (source/test/checkers_pieces.fl/.d is the one
                // such pair). Generating it would put a second module
                // of the same name in generated/, and which of the two
                // dmd picked up would come down to -I order.
                if (exists(buildPath(catDir, baseName(fl).stripExtension() ~ ".d")))
                    continue;

                string gen = buildPath(genDir, baseName(fl).stripExtension().replace("-", "_") ~ ".d");

                bool needGen = !exists(gen) || timeLastModified(gen) < timeLastModified(fl);
                if (!needGen && exists(fluidBin) && timeLastModified(gen) < timeLastModified(fluidBin))
                    needGen = true;
                if (!needGen)
                    continue;

                if (!exists(fluidBin))
                {
                    writeln("buildsamples: no fluid binary yet -- running buildfluid.d...");
                    auto fp = spawnProcess(["rdmd", buildPath(repoRoot, "buildfluid.d")],
                        cast(string[string]) null, Config.none, repoRoot);
                    enforce(wait(fp) == 0, "buildfluid.d failed");
                }

                mkdirRecurse(genDir);
                auto gp = spawnProcess([fluidBin, "-c", "-o", gen, fl],
                    cast(string[string]) null, Config.none, repoRoot);
                enforce(wait(gp) == 0, "failed to generate " ~ gen ~ " from " ~ fl);
            }
        }

        // 3. Every .d with a main() is a program; everything else is a
        //    helper dmd -i will pull in on its own.
        string[] searchDirs = [catDir];
        if (exists(genDir))
            searchDirs ~= genDir;

        string[] candidates;
        foreach (dir; searchDirs)
            candidates ~= dirEntries(dir, "*.d", SpanMode.shallow).map!(e => e.name).array;
        candidates.sort();

        foreach (src; candidates)
        {
            string stem = baseName(src).stripExtension();
            if (!definesMain(src))
                continue;

            string name = renameBinary.get(stem, stem);
            if (nameFilter.length && name != nameFilter && stem != nameFilter)
                continue;

            total++;

            auto skipReason = stem in skip;
            version (Windows) if (skipReason is null) skipReason = stem in skipWindows;
            if (skipReason)
            {
                skipped++;
                writefln("%-28s %-9s skipped -- %s", name, category, *skipReason);
                continue;
            }

            string binary = buildPath(buildDir, name ~ exeSuffix);

            string[] extraFiles;
            if (auto patterns = stem in extraSources)
                foreach (pattern; *patterns)
                    foreach (dir; searchDirs)
                        extraFiles ~= dirEntries(dir, pattern, SpanMode.shallow).map!(e => e.name).array;

            auto deps = localDeps(src, searchDirs) ~ extraFiles;

            if (!force && exists(binary))
            {
                auto binMtime = timeLastModified(binary);
                if (newestMtime(deps) <= binMtime && timeLastModified(libPath) <= binMtime)
                    continue; // up to date
            }

            // fldtk's own import lib/search-path/rpath flags, and the
            // GL/Xlib libs some programs call directly (test/cube,
            // test/shape, examples/OpenGL3test, test/list_visuals, ...)
            // rather than only through fldtk. Linux's dmd shells out to
            // `cc`/`ld`, which understands GNU `-L<dir>`/`-l<name>`/
            // `-rpath=` passed through `-L`; Windows' dmd shells out to
            // `lld-link` instead, which has no idea what any of those
            // mean -- it wants `/LIBPATH:`, a bare `.lib` filename (or
            // full path) as a plain positional argument, and has no
            // rpath concept at all (a Windows PE binary resolves its
            // DLL's location via the same directory/PATH, not anything
            // baked in at link time). GLU-direct samples (`glpuzzle`/
            // `fractals`/`glut_test`, via `fl.glu`/`fl.glut`) now link fine
            // too, `glu32.lib` shipping with Windows the same way GLU
            // ships with any Linux OpenGL install. GLEW-direct samples
            // (`OpenGL3test`/`OpenGL3_glut_test`, via `fl.glew`) have real
            // bindings too now, but need `glew32s.lib` (see `extraLibsWindows`
            // below and `fl.glew`'s own doc comment) -- an optional
            // third-party dependency not installed on every dev machine
            // (this one included, as of this port), so it's named per-
            // sample rather than added to the uniform list below, unlike
            // GLU. `list_visuals`'s Xlib-specific visual dump still isn't
            // linkable on Windows -- no Xlib bindings exist for it -- but
            // plain `Fl_Gl_Window` samples (`shape`, `cube`, `gl_overlay`,
            // `gl_image`) are, now that `fl.gl_window_driver` has a real
            // WGL implementation.
            string[] linkFlags;
            version (Windows)
                // gdi32/user32/kernel32/msvcrt120/oldnames/ole32/gdiplus/
                // opengl32: same reason dub.sdl lists them explicitly for
                // the library itself (see that file's own comment) -- the
                // moment *any* explicit .lib is on dmd's Windows link
                // line (fldtk.lib, here), dmd stops auto-injecting its
                // own default runtime libs, so every one of these has to
                // be named by hand or the link fails on undefined CRT/
                // Win32 symbols despite them being trivially resolvable
                // from dmd's own bundled lib64/mingw import libraries.
                linkFlags = [
                    buildPath(repoRoot, "fldtk.lib"),
                    "gdi32.lib", "user32.lib", "kernel32.lib",
                    "msvcrt120.lib", "oldnames.lib", "ole32.lib", "gdiplus.lib",
                    "opengl32.lib", "glu32.lib", "msimg32.lib", "shell32.lib",
                    "comdlg32.lib", "imm32.lib",
                ];
            else if (release)
                // gdc shells out to `cc`/`ld` directly -- unlike dmd,
                // which wants its own linker flags wrapped in `-L...` so
                // it can tell them apart from its own compiler flags,
                // gdc takes plain gcc-style `-L<dir>`/`-l<name>`. The
                // binary lands in build/release, right next to
                // libfldtk-release.so, so `$ORIGIN` alone (not dmd's
                // `$ORIGIN/..` -- the debug binaries sit one level below
                // libfldtk.so, in build/) finds it at run time.
                linkFlags = [
                    "-L" ~ libDir,
                    "-lfldtk-release",
                    "-lGL", "-lGLU", "-lGLEW", "-lX11",
                    "-Wl,-rpath,$ORIGIN",
                ];
            else
                linkFlags = [
                    "-L-L" ~ repoRoot,
                    "-L-lfldtk",
                    "-L-lGL", "-L-lGLU", "-L-lGLEW", "-L-lX11",
                    "-L-rpath=$ORIGIN/..",
                ];
            version (Windows)
                if (auto extra = stem in extraLibsWindows)
                    linkFlags ~= *extra;

            mkdirRecurse(buildDir);
            string[] cmd;
            if (release)
                // gdc has no dmd-style `-i` ("pull in every locally-
                // resolvable import automatically") -- `deps` (already
                // computed above by following `src`'s own imports, the
                // same set `-i` would have pulled in) is passed as an
                // explicit source-file list instead, the way gdc always
                // expects a multi-module program to be named. No
                // `-od`/`-of`: gdc is a gcc frontend, so it takes `-o
                // <path>` for the final binary and leaves no `.o` litter
                // behind for a single compile+link invocation like this.
                cmd = [
                    "gdc",
                    "-I" ~ buildPath(repoRoot, "source"),
                ] ~ searchDirs.map!(d => "-I" ~ d).array ~ deps ~ linkFlags ~ [
                    "-o", binary,
                ];
            else
                cmd = [
                    "dmd",
                    "-i", "-i=-fl",
                    "-I" ~ buildPath(repoRoot, "source"),
                ] ~ searchDirs.map!(d => "-I" ~ d).array ~ extraFiles ~ [
                    src,
                ] ~ linkFlags ~ [
                    // Object files into their own subdirectory rather than
                    // next to the binaries -- build/ should hold programs to
                    // run, not build litter.
                    "-od" ~ buildPath(buildDir, "obj"),
                    "-of" ~ binary,
                ];

//if (verbose) writeln(cmd);
            auto result = execute(cmd, null, Config.none, size_t.max, repoRoot);
            if (result.status == 0)
            {
                built++;
                writefln("%-28s %-9s ok", name, category);
            }
            else
            {
                // Case-insensitive now (found 2026-09-12, a real bug, not
                // a hypothetical one): `lld-link`'s own diagnostics read
                // `lld-link: error: ...`/`lld-link: warning: ...`,
                // lowercase -- the previous case-sensitive `canFind
                // ("Error")` never matched those, so every *linker*
                // failure (as opposed to a dmd-level compile error, which
                // does start with a capital `Error:`) fell through to
                // dmd's own generic wrapper line (`Error: linker exited
                // with status 1`) as the only "reason" ever shown,
                // hiding the one line that actually says what didn't
                // resolve. Confirmed via a real repro: a stale
                // `buildsamples.exe` missing `msimg32.lib` on its link
                // line showed nothing but that generic line for every
                // single sample.
                auto firstError = result.output.splitLines
                    .filter!(l => l.toLower.canFind("error") || l.toLower.canFind("exception"))
                    .array;
                string reason = firstError.length ? firstError[0].strip : "(build failed)";
                failures ~= category ~ "/" ~ name ~ ": " ~ reason;
                writefln("%-28s %-9s FAILED  %s", name, category, reason);
            }
        }
    }

    writeln();
    writefln("buildsamples: %d built, %d skipped, %d failed (of %d)",
        built, skipped, failures.length, total);
    if (failures.length)
    {
        writeln("Failures:");
        foreach (f; failures)
            writeln("  " ~ f);
    }

    return failures.length ? 1 : 0;
}
