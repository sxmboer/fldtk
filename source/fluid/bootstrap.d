/*
 * Standalone, GUI-free `.fl -> .d` converter -- exactly the same
 * headless conversion `fluid -c`/`-s`/`-u` already does (both call
 * straight into `fluid.compile`, the one real implementation), but
 * built as its own binary with zero compile-time dependency on
 * `fluid.gui_main`, `fluid.canvas`, or anything under `fluid/panels/`.
 *
 * `fluid/panels/*.fl` are Fluid's own primary source; `fluid/panels/*.d`
 * are `fluid -c` output, gitignored and regenerated rather than checked
 * in (see `CONVENTIONS.md`'s "Build commands" section). The full `fluid`
 * binary (`app.d`, `fluid/dub.sdl`'s default `"fluid"` configuration)
 * can't be the tool that regenerates those files on a checkout that
 * only ships the `.fl` sources: building `fluid` itself requires
 * `gui_main.d` to compile, and `gui_main.d` imports the generated
 * panels directly. This binary breaks that circularity: it's built
 * from `fluid/dub.sdl`'s `"bootstrap"` configuration, which excludes
 * `gui_main.d`/`canvas.d`/`app.d` and all of `panels/` from compilation
 * entirely, so it only ever needs `fluid/source/`'s own parse/codegen
 * layer (`fluid.node`, `fluid.project_reader`, `fluid.project_writer`,
 * `fluid.code_writer`, `fluid.compile`) -- none of which import
 * anything panels-generated (`fluid.shell_command`'s own
 * `showShellRunWindowHook` delegate, wired only by `gui_main.d`, is
 * what keeps that one indirect path clear too -- see that module's own
 * top comment).
 *
 * `fluid/buildfluid.d` (`rdmd fluid/buildfluid.d`) drives this binary
 * end to end -- building it, regenerating every missing panel through
 * it, deleting it again, and building the real `fluid` binary -- doing
 * only whichever of those steps is actually needed each time.
 *
 * Supports the same options as `fluid` -- there is no GUI mode here
 * at all, unlike `app.d`'s own bare/no-flag case, so this binary reports
 * a missing input file instead of trying to open an editor window.
 */
module fluid.bootstrap;

import fluid.compile : CommandLine, parseCommandLine, compileFile, normalizeProject, mergeBackProject;

import std.stdio : stderr;

private enum usageLine = "usage: fluid-bootstrap [options] filename.fl\n"
    ~ "The GUI-free converter: the same options as `fluid`, but it never opens the editor.\n"
    ~ "(The editor-styling options are accepted and ignored.)\n";

/// Parses the same options as `fluid` (see `app.d`'s `main()`), through
/// the shared `parseCommandLine()`.
void main(string[] args)
{
    CommandLine cl;
    if (!parseCommandLine(args, cl, usageLine))
        return;

    if (cl.showVersion)
        return;

    if (cl.inPath.length == 0)
    {
        stderr.writefln("fluid-bootstrap: needs a .fl file (try --help)");
        return;
    }

    if (cl.update)
    {
        normalizeProject(cl.inPath);
        return;
    }

    if (cl.wantsMerge())
    {
        int status = mergeBackProject(cl.inPath, cl.output, cl.mergeMode());
        if (status != 0)
        {
            import core.stdc.stdlib : exit;

            exit(status);
        }
        if (!cl.compile)
            return;
    }

    compileFile(cl.inPath, cl.output, cl.strings, cl.dubHeader, cl.stringsName);
}
