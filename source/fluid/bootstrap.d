/*
 * Standalone, GUI-free `.fl -> .d` converter -- exactly the same
 * headless conversion `fluid -c`/`-cs`/`-u` already does (both call
 * straight into `fluid.compile`, the one real implementation), but
 * built as its own binary with zero compile-time dependency on
 * `fluid.gui_main`, `fluid.canvas`, or anything under `fluid/panels/`.
 *
 * `fluid/panels/*.fl` are Fluid's own primary source; `fluid/panels/*.d`
 * are `fluid -c` output, gitignored and regenerated rather than checked
 * in (see `CLAUDE.md`'s "Build commands" section). The full `fluid`
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
 * Only `-c`/`-cs`/`-u`/`-h` are supported -- there is no GUI mode here
 * at all, unlike `app.d`'s own bare/no-flag case, so this binary prints
 * usage and exits instead of trying to open an editor window.
 */
module fluid.bootstrap;

import fluid.compile : printCompileUsage, compileFile, normalizeProject;

import std.getopt : getopt, config, GetOptException;

/// Uses `std.getopt` -- mirrors `app.d`'s
/// own identical approach; see that module's own doc comment on `main()` for
/// the full reasoning (a hand-rolled sequential scan would silently drop
/// `-o`/`--dub-header` whenever placed after the input filename).
/// Duplicated here rather than shared since this whole function is
/// already a from-scratch parallel of `app.d`'s compile-mode parsing,
/// not a shared helper -- this binary has no GUI-mode branch or `-c`/
/// `-s`-gated "only parse -o/--dub-header if compiling" wrapper at all,
/// since (per this module's own top comment) there's nothing else this
/// binary ever does with a `.fl` file besides compile it.
void main(string[] args)
{
    string prog = args.length ? args[0] : "fluid-bootstrap";

    if (args.length >= 2 && args[1] == "-help")
    {
        printCompileUsage(prog);
        return;
    }

    if (args.length >= 2 && args[1] == "-u")
    {
        if (args.length < 3)
        {
            printCompileUsage(prog);
            return;
        }
        normalizeProject(args[2]);
        return;
    }

    bool compileFlag;
    bool alsoWriteStrings;
    string outPath;
    bool dubHeaderFlag;
    try
    {
        auto helpInfo = getopt(args,
            config.bundling,
            "c", &compileFlag,
            "s", &alsoWriteStrings,
            "o", &outPath,
            "dub-header", &dubHeaderFlag);
        if (helpInfo.helpWanted)
        {
            printCompileUsage(prog);
            return;
        }
    }
    catch (GetOptException e)
    {
        import std.stdio : stderr;

        stderr.writefln("fluid-bootstrap: %s", e.msg);
        printCompileUsage(prog);
        return;
    }

    string inPath = args.length >= 2 ? args[1] : null;
    if (inPath.length == 0)
    {
        printCompileUsage(prog);
        return;
    }

    compileFile(inPath, outPath, alsoWriteStrings, dubHeaderFlag);
}
