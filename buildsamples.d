#!/usr/bin/env rdmd
/*
 * buildsamples.d [--force|-f] [test|examples] [name]
 *
 * Builds the demo programs under source/test/ and source/examples/ into
 * build/, each under its own name (`build/hello`, `build/table_sort`,
 * ...), doing only whatever staleness-driven work is actually needed --
 * a Makefile-shaped model.
 *
 * Run: rdmd buildsamples.d          # everything, both categories
 *      rdmd buildsamples.d test      # only source/test/
 *      rdmd buildsamples.d examples  # only source/examples/
 *      rdmd buildsamples.d test hello    # one program by name
 *      rdmd buildsamples.d --force   # ignore mtimes: regenerate and relink everything
 *      rdmd buildsamples.d --no-cairo [test|examples] [name]
 *          builds libfldtk.so without Cairo and Pango support (dub.sdl's
 *          "linux-no-cairo" configuration) and compiles every program
 *          without their -version=/-l flags, so the Cairo
 *          samples (cairo_test, cairo_draw_x) show their "needs a Cairo
 *          enabled library" message instead of the real demo -- the
 *          same two ways FLTK builds them, depending on
 *          FLTK_OPTION_CAIRO_WINDOW. Not combinable with --release.
 *          Without it (the default), Linux builds include Cairo and Pango.
 *      rdmd buildsamples.d --cairo [test|examples] [name]      (Windows)
 *          builds fldtk-cairo.lib, the library with Cairo and Pango
 *          support (dub.sdl's "windows-cairo" configuration), and links every program
 *          against the static Cairo/Pango libraries (the lib*.a files
 *          in libraries/, listed in that configuration).
 *          Windows builds leave Cairo and
 *          Pango out otherwise, since they need libraries Windows doesn't
 *          have; see BUILDING.md's "Cairo and Pango on Windows".
 *      rdmd buildsamples.d --release [test|examples] [name]
 *          builds an optimized library, build/release/libfldtk-release.so
 *          (dub.sdl's "linux-release" configuration), and optimized
 *          programs against it, into build/release/ instead of build/,
 *          without touching the debug libfldtk.so and build/. Linux only,
 *          matching that dub.sdl configuration.
 *      DC=ldc2 rdmd buildsamples.d ...   or   DC=gdc rdmd buildsamples.d ...
 *          the compiler: the `DC` environment variable, as for dub, dmd
 *          when it is not set. The library and the programs are always
 *          built with the same compiler: a library or program built
 *          with another one is rebuilt. LDC and GDC are Linux only. See
 *          BUILDING.md, "Choosing the compiler".
 *
 * `--force`/`-f` (anywhere in the argument list, combinable with a
 * category/name filter) skips the mtime staleness check entirely,
 * regenerates every .fl-backed program's code with Fluid and relinks
 * every matching binary regardless. Use it after changing Fluid's code
 * generator, or whenever the staleness check itself is in doubt (e.g.
 * file timestamps changed by some outside tool); leave it off for
 * normal day-to-day rebuilds.
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
 *      source/<category>/*.fl that is newer than it, or from every .fl
 *      with --force, which is how a change to Fluid's code generator
 *      reaches the generated programs. Building fluid first if it is
 *      missing, with `dub build :fluid`.
 *   3. Compile each program whose binary is missing or older than any
 *      source file it actually depends on (its own .d plus, recursively,
 *      every local .d it imports) or than any source/fl/*.d.
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
{
    enum exeSuffix = ".exe";
    enum isWindows = true;
}
else
{
    enum exeSuffix = "";
    enum isWindows = false;
}

/// Programs that are known not to build, with the reason. Each is a real,
/// documented gap rather than a regression -- see CONVENTIONS.md's "Deferred:
/// external-library-backed features" and "Out of scope: XForms/Forms
/// Library compatibility" sections. Skipped with their reason printed,
/// so the run stays green and the exceptions stay visible.
enum string[string] skip = null;

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
/// Windows `linkFlags` below. Empty: `fl.glew` resolves the modern GL
/// functions itself, so no sample needs a GLEW library. Kept as a table
/// for a future sample needing a Windows library not every machine has.
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
    // --release: an optimized library (dub.sdl's "linux-release"
    // configuration, build/release/libfldtk-release.so) and optimized
    // programs, without touching the debug libfldtk.so. Linux only, as
    // that configuration is.
    bool release = args.canFind("--release");

    // The compiler, from DC as dub reads it; dmd by default. `kind` is
    // which of the three D compilers it is.
    string dc = environment.get("DC", "dmd");
    string dcName = baseName(dc);
    string kind = dcName.canFind("ldc") || dcName.canFind("ldmd") ? "ldc"
        : dcName.canFind("gdc") || dcName.canFind("gdmd") ? "gdc" : "dmd";
    version (Windows)
        if (kind != "dmd")
        {
            stderr.writeln("buildsamples: on Windows fldtk builds with dmd only");
            return 1;
        }
    // --no-cairo (Linux): build libfldtk.so without Cairo and Pango
    // support (dub.sdl's "linux-no-cairo" configuration) and compile every
    // program without -version=FLDTK_HAVE_CAIRO/FLDTK_HAVE_PANGO.
    // --cairo (Windows): build with them, against the static lib*.a
    // archives dub.sdl lists. See the usage comment at the top.
    bool noCairo = args.canFind("--no-cairo");
    version (Windows)
        bool cairo = args.canFind("--cairo");
    else
        bool cairo = !noCairo;
    string[] positional = args[1 .. $]
        .filter!(a => a != "--force" && a != "-f" && a != "--release" && a != "--no-cairo" && a != "--cairo").array;

    if (noCairo && release)
    {
        stderr.writeln("buildsamples: --no-cairo can't be combined with --release");
        return 1;
    }

    string categoryFilter = positional.length > 0 ? positional[0] : "";
    string nameFilter = positional.length > 1 ? positional[1] : "";

    if (categoryFilter.length && categoryFilter != "test" && categoryFilter != "examples")
    {
        stderr.writeln("usage: rdmd buildsamples.d [--force] [--release|--no-cairo|--cairo] [test|examples] [name]");
        return 1;
    }

    string[] categories = categoryFilter.length ? [categoryFilter] : ["test", "examples"];

    // dub.sdl builds fldtk as a dynamicLibrary on Linux (libfldtk.so)
    // but a staticLibrary on Windows (fldtk.lib, no .dll at all) -- see
    // that file's own comment on why (Windows DLL export-visibility,
    // found 2026-09-09). Only used here as a staleness marker.
    version (Windows)
        string libName = cairo ? "fldtk-cairo.lib" : "fldtk.lib";
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
    // A library built the other way (with or without Cairo support) is
    // stale too, whatever its mtime. The marker is CairoState's mangled
    // name; fl.cairo's ModuleInfo symbol is no use, since dmd emits it
    // even when the whole module is versioned out. Not needed on Windows,
    // where the two builds are separate libraries (fldtk.lib,
    // fldtk-cairo.lib).
    bool wrongCairoMode = false;
    // A library built with another compiler is stale too: a program and
    // the library must share one D runtime. Told apart by the runtime
    // library each one needs (LDC's and GDC's have their own names).
    bool wrongCompiler = false;
    version (linux)
    {
        if (exists(libPath))
        {
            auto bytes = cast(const(ubyte)[]) read(libPath);
            wrongCairoMode = bytes.canFind(cast(const(ubyte)[]) "_D2fl5cairo10CairoState") != cairo;
            string builtWith = bytes.canFind(cast(const(ubyte)[]) "phobos2-ldc") ? "ldc"
                : bytes.canFind(cast(const(ubyte)[]) "libgphobos") ? "gdc" : "dmd";
            wrongCompiler = builtWith != kind;
        }
    }

    // Windows --cairo: the static Cairo/Pango link line, from dub.sdl.
    version (Windows)
    {
        string[] cairoLinkFlags;
        if (cairo)
        {
            auto libs = windowsCairoLibs(repoRoot);
            if (libs is null)
                return 1;
            cairoLinkFlags = libs;
        }
    }
    if (!exists(libPath) || wrongCairoMode || wrongCompiler || newestMtime(flSources) > timeLastModified(libPath))
    {
        version (Windows)
            bool plainLib = !cairo;
        else
            bool plainLib = noCairo;
        writeln("buildsamples: building lib" ~ (release ? "fldtk-release" : plainLib ? "fldtk (no Cairo)" : "fldtk")
            ~ " with " ~ dc ~ "...");
        string[] dubArgs = (release
            ? ["dub", "build", "--config=linux-release", "--build=release"]
            : noCairo ? ["dub", "build", "--config=linux-no-cairo"]
            : cairo && isWindows ? ["dub", "build", "--config=windows-cairo"]
            : ["dub", "build"]) ~ ["--compiler=" ~ dc];
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
                // hand (although no such pairs exist anymore with fluid -c being fully functional).
                // Generating it would put a second module
                // of the same name in generated/, and which of the two
                // dmd picked up would come down to -I order.
                if (exists(buildPath(catDir, baseName(fl).stripExtension() ~ ".d")))
                    continue;

                string gen = buildPath(genDir, baseName(fl).stripExtension().replace("-", "_") ~ ".d");

                if (!force && exists(gen) && timeLastModified(gen) >= timeLastModified(fl))
                    continue;

                if (!exists(fluidBin))
                {
                    writeln("buildsamples: no fluid binary yet -- building it...");
                    auto fp = spawnProcess(["dub", "build", ":fluid", "--compiler=" ~ environment.get("DC", "dmd")],
                        cast(string[string]) null, Config.none, repoRoot);
                    enforce(wait(fp) == 0, "dub build :fluid failed");
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
            // Hidden files are skipped: editors leave lock files and
            // backups there (Emacs' `.#name.d` is a dangling symlink).
            candidates ~= dirEntries(dir, "*.d", SpanMode.shallow)
                .filter!(e => !baseName(e.name).startsWith("."))
                .map!(e => e.name).array;
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

            // Which way (with Cairo or --no-cairo) the binary was last built, kept
            // next to its object files: switching modes changes what gets
            // compiled (-version=FLDTK_HAVE_CAIRO) without touching any
            // mtime, so a binary built the other way is stale too. No
            // stamp means a build from before Cairo existed, i.e. without it.
            string modeStamp = buildPath(buildDir, "obj", name ~ ".mode");
            string mode = (cairo ? "cairo" : "plain") ~ " " ~ kind;
            string builtMode = exists(modeStamp) ? readText(modeStamp) : "plain dmd";

            if (!force && exists(binary) && builtMode == mode)
            {
                auto binMtime = timeLastModified(binary);
                // Compared with the library's sources, not the library
                // file: dub relinks libfldtk.so when any .d under source/
                // changes, the demo programs' own included, which says
                // nothing about the library's code. A real change to
                // source/fl rebuilds the library in step 1 and every
                // program here.
                if (newestMtime(deps) <= binMtime && newestMtime(flSources) <= binMtime)
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
            // ships with any Linux OpenGL install. GLEW-style samples
            // (`OpenGL3test`/`OpenGL3_glut_test`, via `fl.glew`) need no
            // GLEW library: `fl.glew` resolves the functions itself.
            // `list_visuals`'s Xlib-specific visual dump still isn't
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
            else
            {
                // A release binary lands in build/release, next to
                // libfldtk-release.so, so `$ORIGIN` finds it; a debug one
                // sits in build/, one level below libfldtk.so.
                string lib = release ? "fldtk-release" : "fldtk";
                string rpath = release ? "$ORIGIN" : "$ORIGIN/..";
                if (kind == "gdc")
                    // gdc is a gcc front end: gcc-style linker flags.
                    linkFlags = ["-L" ~ libDir, "-l" ~ lib, "-lGL", "-lGLU", "-lX11",
                        "-Wl,-rpath," ~ rpath];
                else
                    // dmd and ldmd2 want linker flags wrapped in -L.
                    linkFlags = ["-L-L" ~ libDir, "-L-l" ~ lib, "-L-lGL", "-L-lGLU", "-L-lX11",
                        "-L-rpath=" ~ rpath];
            }
            version (Windows)
                if (auto extra = stem in extraLibsWindows)
                    linkFlags ~= *extra;
            version (Windows)
            {
                // The static Cairo/Pango libraries are built against the
                // Universal C runtime (MSYS2 UCRT64), so the whole program
                // links that runtime instead of dmd's msvcrt120
                // (-mscrtlib also stops dmd naming msvcrt120 as the
                // default library in main's object file); the runtime
                // libraries themselves are in cairoLinkFlags, from dub.sdl.
                if (cairo)
                    linkFlags = linkFlags.filter!(f => f != "msvcrt120.lib").array
                        .map!(f => f == buildPath(repoRoot, "fldtk.lib") ? libPath : f).array
                        ~ ["-mscrtlib=vcruntime140",
                           "-version=FLDTK_HAVE_CAIRO", "-version=FLDTK_HAVE_PANGO"]
                        // dub.sdl's /IMPLIB:NUL: lld-link writes its
                        // output through a temporary file renamed into
                        // place, which fails ("permission denied") for
                        // the NUL device, so the import library goes
                        // into build/obj instead, out of the way.
                        ~ cairoLinkFlags.map!(f => f == "-L/IMPLIB:NUL"
                            ? "-L/IMPLIB:" ~ buildPath(buildDir, "obj", stem ~ ".lib") : f).array;
            }
            else if (cairo)
                linkFlags ~= kind == "gdc"
                    ? ["-fversion=FLDTK_HAVE_CAIRO", "-fversion=FLDTK_HAVE_PANGO",
                       "-lcairo", "-lpangocairo-1.0", "-lpango-1.0", "-lgobject-2.0", "-lglib-2.0"]
                    : ["-version=FLDTK_HAVE_CAIRO", "-version=FLDTK_HAVE_PANGO",
                       "-L-lcairo", "-L-lpangocairo-1.0", "-L-lpango-1.0", "-L-lgobject-2.0", "-L-lglib-2.0"];

            mkdirRecurse(buildDir);
            string[] cmd;
            if (kind == "gdc")
                // gdc has no dmd-style `-i` ("pull in every locally-
                // resolvable import automatically") -- `deps` (already
                // computed above by following `src`'s own imports, the
                // same set `-i` would have pulled in) is passed as an
                // explicit source-file list instead. gdc takes `-o
                // <path>` for the binary and leaves no `.o` files behind.
                // -shared-libphobos: the program shares GDC's runtime with
                // libfldtk.so instead of carrying its own copy.
                cmd = [dc, "-shared-libphobos"]
                    ~ (release ? ["-O2", "-frelease"] : [])
                    ~ ["-I" ~ buildPath(repoRoot, "source")]
                    ~ searchDirs.map!(d => "-I" ~ d).array ~ deps ~ linkFlags ~ [
                    "-o", binary,
                ];
            else
                // LDC through ldmd2, its front end that takes dmd's flags.
                // -link-defaultlib-shared: the program shares LDC's runtime
                // with libfldtk.so instead of carrying its own copy.
                cmd = (kind == "ldc" ? ["ldmd2", "-link-defaultlib-shared"] : [dc])
                    ~ (release ? ["-O", "-release", "-inline"] : [])
                    ~ [
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
                mkdirRecurse(buildPath(buildDir, "obj"));
                std.file.write(modeStamp, mode);
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

/*
 * The link line for static Cairo and Pango on Windows, read from dub.sdl's
 * "windows-cairo" configuration (`dub describe`), so the library list
 * lives in one place: its libs become <name>.lib, and its lflags (the
 * static lib*.a archives in libraries/, plus lld-link options)
 * are passed through to the linker with -L. Returns null after printing
 * why if dub fails or a listed archive is missing (see BUILDING.md's
 * "Cairo and Pango on Windows" for where they come from).
 */
string[] windowsCairoLibs(string repoRoot)
{
    string[] describe(string data)
    {
        auto r = execute(["dub", "describe", "--config=windows-cairo", "--data=" ~ data, "--data-list"],
            cast(string[string]) null, Config.none, size_t.max, repoRoot);
        if (r.status != 0)
        {
            stderr.writeln("buildsamples: dub describe failed:\n" ~ r.output);
            return null;
        }
        return r.output.splitLines.filter!(l => l.length).array;
    }

    auto libs = describe("libs");
    auto lflags = describe("lflags");
    if (libs is null || lflags is null)
        return null;
    foreach (f; lflags)
        if (f.endsWith(".a") && !exists(f))
        {
            stderr.writeln("buildsamples: --cairo needs " ~ f
                ~ " (see BUILDING.md's \"Cairo and Pango on Windows\")");
            return null;
        }
    return libs.map!(l => l ~ ".lib").array ~ lflags.map!(f => "-L" ~ f).array;
}
