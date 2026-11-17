#!/usr/bin/env rdmd
/*
 * buildpanels.d
 *
 * Generates Fluid's dialogs, source/fluid/panels/generated/*.d, from
 * source/fluid/panels/*.fl. Fluid's own dub.sdl runs it before every
 * build of Fluid (preGenerateCommands), so `dub build fldtk:fluid` and
 * `dub run fldtk:fluid` work on a fresh checkout and from dub's package
 * cache alike; running it by hand is never needed.
 *
 * The generated files are not checked in, and Fluid can't be built
 * without them, so they are made by fluid-bootstrap: Fluid's code
 * generator without the editor (the "bootstrap" configuration in
 * source/fluid/dub.sdl, main() in source/fluid/bootstrap.d). When any
 * panel is missing or older than its .fl (template_panel.fl also
 * depends on templates/*.fl), this script builds fluid-bootstrap with
 * the compiler in `DC` (dmd when it is not set), regenerates the stale
 * panels with it and deletes it again. Otherwise it does nothing.
 *
 * Paths are taken from this script's own location, so it works from any
 * working directory.
 */
module buildpanels;

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

int main()
{
    // buildNormalizedPath() first: __FILE_FULL_PATH__ keeps a "." segment
    // when the script is run as ./buildpanels.d, and dirName() doesn't
    // collapse it.
    string repoRoot = dirName(buildNormalizedPath(__FILE_FULL_PATH__));
    string fluidDir = buildPath(repoRoot, "source", "fluid");
    string panelsDir = buildPath(fluidDir, "panels");
    string genDir = buildPath(panelsDir, "generated");
    string bootstrapBin = buildPath(repoRoot, "fluid-bootstrap" ~ exeSuffix);

    string[] flFiles = dirEntries(panelsDir, "*.fl", SpanMode.shallow).array.map!(e => e.name).array;
    sort(flFiles);

    string genPathFor(string fl) => buildPath(genDir, baseName(fl).stripExtension() ~ ".d");

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
    if (stale.length == 0)
        return 0;

    writeln("buildpanels: generating ", stale.length, " Fluid panel(s) through fluid-bootstrap...");
    auto pid = spawnProcess(["dub", "build", ":fluid", "--config=bootstrap",
            "--compiler=" ~ environment.get("DC", "dmd")],
        cast(string[string]) null, Config.none, repoRoot);
    enforce(wait(pid) == 0, "dub build :fluid --config=bootstrap failed");

    mkdirRecurse(genDir);
    foreach (fl; stale)
    {
        auto gp = spawnProcess([bootstrapBin, "-c", "-o", genPathFor(fl), fl]);
        enforce(wait(gp) == 0, "failed to generate " ~ fl);
    }

    remove(bootstrapBin);
    return 0;
}
