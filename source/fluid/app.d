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
 *     fluid [ -c [ -o code-filename ] [ --dub-header ] ] [ filename.fl ]
 *     fluid ( -mb | -mbs ) [ -c ] [ -o code-filename ] filename.fl
 *
 * -- i.e. the default is the interactive GUI editor (`fluid` or
 * `fluid file.fl` opens the editor, empty or pre-loaded), and `-c`
 * switches to FLTK's "batch/headless" behavior instead. `fluidgen.d`
 * (`fluid/fluidgen.d`) calls
 * `fluid -c -o <output.d> <input.fl>`, matching real
 * FLTK usage rather than a positional-args shortcut.
 *
 * `-cs`/`-u` are ported from `fluid/app/args.h`/`.cxx`'s own flag set,
 * the two FLTK flags that actually map onto
 * something this port has: `-cs` (also write the i18n strings file,
 * via `fluid.string_writer`) and `-u` (load, normalize, and resave the
 * `.fl` file -- the "read-modify-write round-trip" `project_writer.d`'s
 * own doc comment names). `-o`
 * names the generated `.d` file, defaulting to the input's own
 * basename with a `.d` extension.
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
 * `-mb`/`--merge-back` and `-mbs`/`--merge-back-if-safe` are the
 * headless entry points to MergeBack (`fluid.mergeback`), the two
 * options FLTK's `mergeback.cxx` lists as TODO. `-mb` merges edits
 * made in the generated `.d` file back into the `.fl` project and
 * saves it; `-mbs` does so only if there are no conflicts (exit status
 * 1 otherwise). `-o` names the code file to read, defaulting to the
 * one most recently written for the project, else the default `-c`
 * location; combined with `-c` the merge runs first, then the project
 * is compiled, so a build script can fold external edits in before
 * regenerating. Both are matched by hand before `getopt()` runs:
 * `config.bundling` would otherwise read `-mb` as `-m -b`.
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
 * Deliberately NOT ported: `-v`/`--version` (this project has no
 * version-number concept at all yet -- no `dub.sdl` `version` field, no
 * release tagging -- inventing one just to answer this flag isn't this
 * file's call to make), `-d` (`Fluid.debug_external_editor`'s own gated
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
import std.getopt : getopt, config, GetOptException;

import fluid.compile : printCompileUsage, compileFile, normalizeProject, mergeBackProject;

/// Ported in spirit from FLTK's own usage text, minus the `-h
/// header-filename` half -- see this module's own top comment on why
/// `-h` means "show this text" here instead. Shared by every call site
/// that needs it (an explicit `-h`/`--help`/`-help`, and the two
/// missing-argument error paths below) rather than duplicated per site.
/// The `-c`/`-cs`/`-u` lines themselves come from `compile.d`'s
/// own `printCompileUsage()` -- shared with `bootstrap.d`, which prints
/// the exact same three lines and nothing else (no GUI mode to
/// describe) -- this just adds the one line only the full GUI binary
/// has anything to say about.
private void printUsage(string prog)
{
    printCompileUsage(prog);
    stderr.writefln("       %s -mb [-c] [-o code-filename] <input.fl>    (merge edits made in the generated .d file back into the .fl file)", prog);
    stderr.writefln("       %s -mbs [-c] [-o code-filename] <input.fl>   (same, but only if there are no conflicts)", prog);
    stderr.writefln("       %s -h | --help | -help                 (show this text)", prog);
}

/**
 * Uses `std.getopt`: a hand-rolled sequential scan that only looks for `-o`/
 * `--dub-header` in the narrow window right after `-c`/`-cs` would silently
 * drop
 * `fluid -c file.fl --dub-header` -- the flag placed *after* the
 * filename -- since such a scan stops advancing the moment it sees a
 * token that isn't a recognized flag. `getopt()` scans
 * the *whole* argument list regardless of where positional arguments
 * fall, so `-c`/`-o`/`--dub-header` (any subset, any order, before or
 * after `file.fl`) all resolve correctly, and mutates `args` down to
 * just the program name plus whatever wasn't consumed as an option --
 * `args[1]`, if present, is always the input file.
 *
 * `-c`/`-s` are registered as separate single-letter flags with
 * `config.bundling` enabled specifically so `-cs` keeps meaning
 * "compile, also write strings" exactly as before (bundling glues
 * consecutive single-letter flags after one dash together, so `-cs`
 * parses as `-c -s`) -- observably identical to the old hardcoded
 * `"-cs"` string check, just derived from real flag composition
 * instead of a special-cased literal.
 *
 * `-u`/`-h`/`--help`/`-help` stay outside `getopt()` entirely: `-u`
 * is a genuinely separate mode, not composable with `-c`/`-o`/
 * `--dub-header` at all (this port's own established constraint, see
 * this module's own top comment), so it's resolved before `getopt()`
 * ever runs; `-h`/`--help` are `getopt()`'s own built-in recognized
 * spellings (its `helpWanted` result flag), but `-help` (single dash)
 * isn't one of those two, so it's still checked by hand alongside them.
 */
void main(string[] args)
{
    string prog = args.length ? args[0] : "fluid";

    if (args.length >= 2 && args[1] == "-help")
    {
        printUsage(prog);
        return;
    }

    if (args.length >= 2 && args[1] == "-u")
    {
        // Standalone only, matching this port's own established -u
        // behavior -- FLTK allows "-u" combined with "-c"/"-cs" (
        // normalize, then also compile) but this port has never
        // supported that combination and isn't widening it here, a
        // real, separate follow-up if ever needed.
        if (args.length < 3)
        {
            printUsage(prog);
            return;
        }
        normalizeProject(args[2]);
        return;
    }

    // -mb/-mbs, matched by hand -- see this module's top comment.
    bool mergeBack = takeFlag(args, ["-mb", "--merge-back"]);
    bool mergeBackIfSafe = takeFlag(args, ["-mbs", "--merge-back-if-safe"]);
    if (mergeBack && mergeBackIfSafe)
    {
        stderr.writefln("fluid: -mb and -mbs cannot be combined");
        printUsage(prog);
        return;
    }

    bool compile;
    bool alsoWriteStrings;
    string outPath;
    bool dubHeaderFlag;
    try
    {
        auto helpInfo = getopt(args,
            config.bundling,
            "c", &compile,
            "s", &alsoWriteStrings,
            "o", &outPath,
            "dub-header", &dubHeaderFlag);
        if (helpInfo.helpWanted)
        {
            printUsage(prog);
            return;
        }
    }
    catch (GetOptException e)
    {
        stderr.writefln("fluid: %s", e.msg);
        printUsage(prog);
        return;
    }

    string inPath = args.length >= 2 ? args[1] : null;

    if (mergeBack || mergeBackIfSafe)
    {
        if (inPath.length == 0)
        {
            printUsage(prog);
            return;
        }
        int status = mergeBackProject(inPath, outPath, mergeBackIfSafe);
        if (status != 0)
        {
            import core.stdc.stdlib : exit;

            exit(status);
        }
        if (!compile)
            return;
    }

    if (!compile)
    {
        import fluid.gui_main : runEditor;

        runEditor(inPath.length ? [inPath] : []);
        return;
    }

    if (inPath.length == 0)
    {
        printUsage(prog);
        return;
    }

    compileFile(inPath, outPath, alsoWriteStrings, dubHeaderFlag);
}

/// Removes every argument after the program name that equals one of
/// `names` and returns whether any was present.
private bool takeFlag(ref string[] args, string[] names)
{
    string[] kept = args.length ? [args[0]] : [];
    bool found;
    foreach (a; args.length ? args[1 .. $] : [])
    {
        bool match;
        foreach (n; names)
            if (a == n) match = true;
        if (match) found = true;
        else kept ~= a;
    }
    args = kept;
    return found;
}
