#!/usr/bin/env rdmd
/*
 * buildfluid.d
 *
 * Builds (or rebuilds) the fluid binary in the repo root, doing only
 * whatever staleness-driven work is actually needed to get there, the
 * way a Makefile would -- not a fixed sequence of steps run
 * unconditionally every time.
 *
 * Run: rdmd buildfluid.d   (works from any cwd; every path below is
 * resolved from this script's own location, __FILE_FULL_PATH__, not
 * $PWD).
 *
 * Sequence:
 *
 *  1. source/fluid/panels/generated/*.d are gitignored, generated
 *     output -- a fresh checkout has none. For each panels/*.fl whose
 *     generated/*.d is missing or older than it (editing one .fl
 *     regenerates only that one panel, not the other nine):
 *       - if ./fluid already exists, use it directly to regenerate the
 *         stale panels -- a compiled binary has no further need of its
 *         own source, so panels/generated/*.d being missing or behind
 *         doesn't stop the binary working as the generator;
 *       - otherwise build ./fluid-bootstrap first (`dub build
 *         fldtk:fluid --config=bootstrap` -- the panels-free
 *         configuration exists specifically to break this circularity,
 *         see source/fluid/dub.sdl and bootstrap.d's own top comment),
 *         use it to regenerate the stale panels, then delete the
 *         bootstrap binary -- it has no purpose once panels/generated/
 *         *.d exist.
 *  2. If ./fluid doesn't exist yet, or any panels/generated/*.d or
 *     source/fluid/*.d (the binary's own hand-written source --
 *     gui_main.d, code_writer.d, ...) is newer than it, `dub build
 *     fldtk:fluid` (the real "fluid" configuration).
 *  3. Otherwise nothing needed doing: print "fluid: 'fluid' is up to
 *     date." (matching make's own wording for a target with nothing to
 *     do) and exit.
 *
 * A D/rdmd script rather than a shell script so it runs unchanged on
 * every platform dmd itself supports -- rdmd ships with every dmd
 * install, whereas a .sh needs a POSIX shell Windows users typically
 * don't have. Same reasoning applies to buildsamples.d alongside it.
 */
module buildfluid;

import std.algorithm;
import std.array : array;
import std.datetime : SysTime;
import std.exception : enforce;
import std.file;
import std.path;
import std.process;
import std.stdio;

version (Windows)
    enum exeSuffix = ".exe";
else
    enum exeSuffix = "";

/// Runs `dub build fldtk:fluid`, plus any extra args (e.g. the bootstrap
/// config), from repoRoot. Streams dub's own output straight through.
int dubBuildFluid(string[] extraArgs, string repoRoot)
{
    auto pid = spawnProcess(["dub", "build", "fldtk:fluid"] ~ extraArgs, cast(string[string]) null, Config.none, repoRoot);
    return wait(pid);
}

/// Latest mtime among every *.d file directly in `dir` (not recursing --
/// source/fluid/ has exactly two subdirectories, panels/ and templates/,
/// and neither should count toward this specific check: panels/*.d has
/// its own dedicated staleness check below, and templates/ holds only .fl
/// files embedded into a generated panel). SysTime.min (older
/// than anything) if the directory has no top-level .d files at all.
SysTime newestDSourceMtime(string dir)
{
    SysTime newest = SysTime.min;
    foreach (entry; dirEntries(dir, "*.d", SpanMode.shallow))
    {
        auto t = entry.timeLastModified;
        if (t > newest)
            newest = t;
    }
    return newest;
}

int main(string[] args)
{
    // buildNormalizedPath() first: __FILE_FULL_PATH__ is only the literal
    // concatenation of the compiler's cwd and whatever path was actually
    // typed on the command line, not a resolved/collapsed path -- running
    // this script via its own shebang (`./buildfluid.d`) leaves a literal
    // "." segment in it, and dirName() does not collapse "."/".."
    // segments, it just strips the last path component textually, so an
    // unnormalized path lands one level too shallow.
    string repoRoot = dirName(buildNormalizedPath(__FILE_FULL_PATH__));
    string fluidDir = buildPath(repoRoot, "source", "fluid");
    string panelsDir = buildPath(fluidDir, "panels");
    string genDir = buildPath(panelsDir, "generated");
    string fluidBin = buildPath(repoRoot, "fluid" ~ exeSuffix);
    string bootstrapBin = buildPath(repoRoot, "fluid-bootstrap" ~ exeSuffix);

    string[] flFiles = dirEntries(panelsDir, "*.fl", SpanMode.shallow).array.map!(e => e.name).array;
    sort(flFiles);

    string genPathFor(string fl) => buildPath(genDir, baseName(fl).stripExtension() ~ ".d");

    // template_panel.fl embeds templates/*.fl via `data` nodes, so those
    // are inputs of its generated .d as well.
    SysTime newestTemplate = SysTime.min;
    foreach (entry; dirEntries(buildPath(fluidDir, "templates"), "*.fl", SpanMode.shallow))
        if (entry.timeLastModified > newestTemplate)
            newestTemplate = entry.timeLastModified;

    string[] stale;
    foreach (fl; flFiles)
    {
        string d = genPathFor(fl);
        bool embedsTemplates = baseName(fl) == "template_panel.fl";
        if (!exists(d) || timeLastModified(d) < timeLastModified(fl)
            || (embedsTemplates && timeLastModified(d) < newestTemplate))
            stale ~= fl;
    }

    bool didWork;

    if (stale.length > 0)
    {
        didWork = true;
        string generator;
        bool cleanupBootstrap;

        if (exists(fluidBin))
        {
            generator = fluidBin;
        }
        else
        {
            writeln("buildfluid: source/fluid/panels/generated/*.d missing or stale and no fluid binary yet -- building fluid-bootstrap...");
            enforce(dubBuildFluid(["--config=bootstrap"], repoRoot) == 0, "dub build fldtk:fluid --config=bootstrap failed");
            generator = bootstrapBin;
            cleanupBootstrap = true;
        }

        mkdirRecurse(genDir);
        foreach (fl; stale)
        {
            auto pid = spawnProcess([generator, "-c", "-o", genPathFor(fl), fl]);
            enforce(wait(pid) == 0, "failed to generate " ~ fl);
        }

        if (cleanupBootstrap && exists(bootstrapBin))
            remove(bootstrapBin);
    }

    bool needBuild = !exists(fluidBin);
    if (!needBuild)
    {
        auto binMtime = timeLastModified(fluidBin);

        needBuild = newestDSourceMtime(fluidDir) > binMtime;

        if (!needBuild)
            foreach (fl; flFiles)
            {
                string d = genPathFor(fl);
                if (exists(d) && timeLastModified(d) > binMtime)
                {
                    needBuild = true;
                    break;
                }
            }
    }

    if (needBuild)
    {
        didWork = true;
        writeln("buildfluid: building fluid...");
        enforce(dubBuildFluid([], repoRoot) == 0, "dub build fldtk:fluid failed");
    }

    if (!didWork)
        writeln("buildfluid: 'fluid' is up to date.");

    return 0;
}
