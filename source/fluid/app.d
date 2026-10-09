/*
 * Fluid, FLTK's UI designer, ported to emit D source files -- and, as
 * of the "Fluid Phase 1" plan, a real (if deliberately thin) start on
 * the interactive GUI editor too (`fluid.gui_main`/`fluid.canvas`/
 * `fluid.node_browser`/`panels/widget_panel.fl`/`fluid.instantiate`/
 * `fluid.project_writer`).
 *
 * One binary, `fluid` (renamed from `fldtk_fluid` -- see
 * `fluid/dub.sdl`'s `targetName`), following FLTK's own real
 * SYNOPSIS in spirit, minus the `-h header-filename` half -- see this file's own
 * `-h`/`--help` note further down for why that specific piece deviates
 * on purpose rather than being copied literally:
 *
 *     fluid [ -c | -cs [ -s strings-filename ] ] [ -o code-filename ] [ --dub-header ] [ filename.fl ]
 *     fluid ( -m | --merge-back-if-safe | --merge-back-info ) [ -c ] [ -o code-filename ] filename.fl
 *
 * Every option has a short and a long spelling (`-c`/`--compile`, ...);
 * `fluid --help` lists them.
 *
 * -- i.e. the default is the interactive GUI editor (`fluid` or
 * `fluid file.fl` opens the editor, empty or pre-loaded), and `-c`
 * switches to FLTK's "batch/headless" behavior instead. `fluidgen.d`
 * (`fluid/fluidgen.d`) calls
 * `fluid -c -o <output.d> <input.fl>`, matching real
 * FLTK usage rather than a positional-args shortcut.
 *
 * `--strings`/`-u` are ported from `fluid/app/args.h`/`.cxx`'s own flag set,
 * the two FLTK flags that actually map onto
 * something this port has: `--strings` with `-c`, i.e. `-cs` (also write the i18n strings file,
 * via `fluid.string_writer`) and `-u` (load, normalize, and resave the
 * `.fl` file -- the "read-modify-write round-trip" `project_writer.d`'s
 * own doc comment names). `-o`
 * names the generated `.d` file, defaulting to the input's own
 * basename with a `.d` extension. `-s` names the strings file (or, starting
 * with '.', its extension), defaulting to the input's own basename with an
 * extension chosen by the project's i18n type; it only matters with `-cs`/`--strings`.
 *
 * `--dub-header` (a deliberate fldtk-only convenience, no FLTK
 * equivalent): prepends a dub single-file-package comment
 * (`/+ dub.sdl: dependency "fldtk" path="..." +/`) to the generated
 * `.d` file, so it builds directly via `dub build --single`/`dub run
 * --single` with no manually-typed linker flags -- the headless-CLI
 * counterpart of `Settings -> Project`'s own checkbox in the
 * interactive editor (`settings_panel.fl`'s `dubHeaderButton`, which
 * persists the choice into the `.fl` project file itself as `dub_header
 * 1`). This flag only ever *adds* the header on top of whatever the
 * project file already says -- see `compile.d`'s `compileFile()` doc
 * comment for why there's no equivalent "force it off" case.
 *
 * `-m`/`--merge-back`, `-mb`/`--merge-back-if-safe` and `-mi`/`--merge-back-info`
 * are the headless entry points to MergeBack (`fluid.mergeback`), the
 * counterparts of FLTK's `-mb=apply` and `-mb=info`. `-m` merges edits
 * made in the generated `.d` file back into the `.fl` project and saves
 * it; `--merge-back-if-safe` does so only if there are no conflicts
 * (exit status 1 otherwise); `--merge-back-info` only reports what would
 * be merged. `-o` names the code file to read, defaulting to the
 * one most recently written for the project, else the default `-c`
 * location; combined with `-c` the merge runs first, then the project
 * is compiled, so a build script can fold external edits in before
 * regenerating.
 *
 * `-h`/`--help` deliberately means something different here than
 * FLTK's own SYNOPSIS line, a real, reasoned deviation, not an
 * oversight. FLTK's
 * `-h <header-filename>` names the generated `.h` file alongside `-o`'s
 * `.cxx` -- meaningless in this port, since generated D has no header/
 * source-file split for a second filename to name at all. An
 * accepted-but-silently-ignored flag would be worse than just not
 * having it: `-h`/
 * `--help`/`-help` are such a near-universal cross-tool convention for
 * "print usage and exit" that reserving the letter for a no-op only
 * serves to confuse. So `-h` prints this file's own usage text instead
 * (exit 0, not an error) -- the flag earns a real, useful meaning
 * instead of a dead one.
 * `-v`/`--version` prints `fluid vX.Y.Z` and exits, with fldtk's own
 * version (`FL_MAJOR_VERSION`/..., see `fl.enumerations`), as FLTK's own
 * Fluid prints its FLTK version.
 *
 * Deliberately NOT ported: `-d` (`Fluid.debug_external_editor`'s own gated
 * `printf()` tracing was never ported, see
 * `fluid.external_code_editor`'s own doc comment), `--autodoc`
 * (`autodoc.h`/`.cxx` itself was deliberately not ported, see
 * `PORTING.md`'s `fluid/tools/` row).
 *
 * **Real side effect of adding `-cs`/`-u`, kept from before**: the
 * compile path threads the loaded project's own `I18nSettings`
 * (`Reader.i18n`) through to `Writer.generate()`, so a project with
 * `i18n_type` set gets its labels/tooltips wrapped correctly instead of
 * emitted as plain literals.
 */
module fluid.app;

import std.stdio : writefln, stderr;
import fl.enumerations : FL_MAJOR_VERSION, FL_MINOR_VERSION, FL_PATCH_VERSION;
static import fl.core;
import fluid.compile : CommandLine, parseCommandLine, compileFile, normalizeProject, mergeBackProject;

/// Applies `--bg`, `--fg`, `--scheme` and `--scaling-factor`, which style
/// the editor itself and don't touch the generated code.
private void applyEditorStyle(const ref CommandLine cl)
{
    version (linux)
    {
        ubyte r, g, b;
        if (cl.bg.length && fl.core.flParseColor(cl.bg, r, g, b)) fl.core.background(r, g, b);
        if (cl.fg.length && fl.core.flParseColor(cl.fg, r, g, b)) fl.core.foreground(r, g, b);
    }
    if (cl.scheme.length) fl.core.scheme(cl.scheme);
    if (cl.scalingFactor != 1.0f) fl.core.normalizedScreenScale(-1, cl.scalingFactor);
}

/// The first line of `--help`; the option list below it is generated
/// from the option descriptions in `compile.d`'s `parseCommandLine()`.
private enum usageLine = "usage: fluid [options] [filename.fl]\n"
    ~ "Without -c, -u, or a merge option: opens the interactive editor.\n"
    ~ "fldtk's standard switches (-geometry, -display, -name, -title, ...) are accepted as well.\n";

/**
 * The command line is parsed by `compile.d`'s `parseCommandLine()`, shared
 * with `bootstrap.d`: one `std.getopt` call with `"short|long"` option
 * strings, so every option works in both spellings, anywhere on the line
 * (before or after the input file), and `--help` lists them from their
 * descriptions. `std.getopt` has no multi-letter single-dash options, so
 * a word like `-cs`, `-mb` or `-scheme` that names an option is rewritten
 * to its long form first (`compile.d`'s `longSpelling()`). `-bg`, `-fg`,
 * `--scheme` and `-sf`/`--scaling-factor` style the editor itself and
 * don't touch the generated code. Whatever the parser doesn't know is
 * handed to `fl.core.args()`, which takes FLTK's other standard switches
 * (`-geometry`, `-display`, `-name`, `-title`, ...).
 *
 * `-h`/`--help` means "show usage" here, unlike FLTK's `-h
 * header-filename`: generated D has no header file for it to name.
 */
void main(string[] args)
{
    CommandLine cl;
    if (!parseCommandLine(args, cl, usageLine, true))
        return;

    // What is left are fldtk's own switches (-bg, -fg, -scheme,
    // -scaling_factor, ...), then the .fl file. They style Fluid itself
    // and have no effect on the generated code.
    int fileIndex;
    if (fl.core.args(args, fileIndex) == 0)
    {
        stderr.writefln("fluid: Unrecognized option %s\nTry 'fluid --help'.", args[fileIndex]);
        return;
    }
    cl.inPath = fileIndex < cast(int) args.length ? args[fileIndex] : null;

    if (cl.showVersion)
    {
        writefln("fluid v%d.%d.%d", FL_MAJOR_VERSION, FL_MINOR_VERSION, FL_PATCH_VERSION);
        return;
    }

    if (cl.update)
    {
        if (cl.inPath.length == 0)
        {
            stderr.writefln("fluid: -u needs a .fl file");
            return;
        }
        normalizeProject(cl.inPath);
        return;
    }

    if (cl.wantsMerge())
    {
        if (cl.inPath.length == 0)
        {
            stderr.writefln("fluid: merging needs a .fl file");
            return;
        }
        int status = mergeBackProject(cl.inPath, cl.output, cl.mergeMode());
        if (status != 0)
        {
            import core.stdc.stdlib : exit;

            exit(status);
        }
        if (!cl.compile)
            return;
    }

    if (!cl.compile)
    {
        import fluid.gui_main : runEditor;

        applyEditorStyle(cl);
        runEditor(cl.inPath.length ? [cl.inPath] : []);
        return;
    }

    if (cl.inPath.length == 0)
    {
        stderr.writefln("fluid: -c needs a .fl file");
        return;
    }

    compileFile(cl.inPath, cl.output, cl.strings, cl.dubHeader, cl.stringsName);
}
