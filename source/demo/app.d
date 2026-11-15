/*
 * The `demo` sub-package's program: `dub run :demo` in the fldtk folder,
 * or `dub run fldtk:demo` from anywhere.
 *
 * Builds whatever is missing or out of date, then starts build/demo:
 *   1. the demo programs, with `rdmd buildsamples.d` (which builds the
 *      library first when needed);
 *   2. Fluid and fldtk-options, with `dub build :fluid` and
 *      `dub build :options`, since the demo program's buttons start
 *      them from the fldtk folder.
 * The first run builds every demo program and takes a few minutes; later
 * runs only check and start the demo program. Arguments are passed on to
 * the demo program. A demo program that fails to build is reported by
 * buildsamples.d and doesn't keep the others from starting. The compiler
 * is the `DC` environment variable, dmd when it is not set, as for
 * buildsamples.d.
 */
module app;

import std.file : exists, thisExePath;
import std.path : buildNormalizedPath, buildPath, dirName;
import std.process : Config, environment, spawnProcess, wait;
import std.stdio : stderr;

version (Windows)
    enum exeSuffix = ".exe";
else
    enum exeSuffix = "";

int main(string[] args)
{
    // This program is in build/, one folder below the fldtk folder.
    string root = buildNormalizedPath(dirName(thisExePath()), "..");
    string compiler = "--compiler=" ~ environment.get("DC", "dmd");

    // Runs a command in the fldtk folder, its output going to this
    // program's terminal; returns its exit status, or -1 when it can't
    // be started.
    int run(string[] cmd)
    {
        try return wait(spawnProcess(cmd, null, Config.none, root));
        catch (Exception e)
        {
            stderr.writeln("demo: can't run ", cmd[0], ": ", e.msg);
            return -1;
        }
    }

    bool ok = run(["rdmd", buildPath(root, "buildsamples.d")]) == 0;
    ok = run(["dub", "build", ":fluid", compiler]) == 0 && ok;
    ok = run(["dub", "build", ":options", compiler]) == 0 && ok;

    string demo = buildPath(root, "build", "demo" ~ exeSuffix);
    if (!exists(demo))
    {
        stderr.writeln("demo: ", demo, " was not built; see the messages above");
        return 1;
    }
    if (!ok)
        stderr.writeln("demo: not everything was built; see the messages above");
    try return wait(spawnProcess([demo] ~ args[1 .. $], null, Config.none, root));
    catch (Exception e)
    {
        stderr.writeln("demo: can't start ", demo, ": ", e.msg);
        return 1;
    }
}
