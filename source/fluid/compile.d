/*
 * The real body of `fluid`'s headless `-c`/`-s`/`-u`/`-m` flags -- factored
 * out of `fluid.app`'s own `main()` so it has exactly one
 * implementation, shared by two different binaries: the full
 * interactive `fluid` app (`app.d`, still the only place the GUI
 * branch lives) and `fluid.bootstrap` (a second, standalone, GUI-free
 * binary -- see that module's own top comment for why it exists: it
 * lets `fluid/panels/*.d` be regenerated from `fluid/panels/*.fl`
 * *before* a working `fluid` binary exists at all, breaking the
 * circular dependency `CONVENTIONS.md`'s own "Fluid's own primary source"
 * note describes).
 *
 * This module -- like `fluid.node`/`fluid.project_reader`/
 * `fluid.project_writer`/`fluid.code_writer` themselves -- has no
 * dependency on anything under `fluid/panels/` or on `fluid.gui_main`/
 * `fluid.canvas`. Keep it that way: anything added here needs to stay
 * safe for `bootstrap.d` to import.
 */
module fluid.compile;

import std.stdio : writefln, stderr;
import std.file : exists, read, readText, write;
import std.path : stripExtension, dirName, baseName, buildPath, isAbsolute, extension, absolutePath;

import fl.filename : filenameSetExt;

import fluid.node : Node;
import fluid.project_reader : Reader;
import fluid.project_writer : ProjectWriter;
import fluid.code_writer : Writer;
import fluid.mergeback : Mergeback, rememberCodePath, rememberedCodePath;
import fluid.layout_suite : LayoutList;
import fluid.raw_cpp_guard : looksLikeRawCpp;
import fluid.i18n : I18nType, I18nSettings;

/// What to do with a project's MergeBack data (`-m`, `--merge-back-if-safe`,
/// `--merge-back-info`).
enum MergeMode { merge, ifSafe, info }

/// The command line shared by `fluid` (`app.d`) and `fluid-bootstrap`
/// (`bootstrap.d`), filled in by `parseCommandLine()`.
struct CommandLine
{
    bool compile;           /// -c: generate the .d file
    bool strings;           /// -cs, --strings: also write the i18n strings file
    bool update;            /// -u: load, normalize and resave the .fl file
    bool mergeBack;         /// -m: merge edits from the generated file back
    bool mergeBackIfSafe;   /// only when nothing conflicts
    bool mergeBackInfo;     /// only report what would be merged
    bool dubHeader;         /// --dub-header
    bool showVersion;       /// -v
    string output;          /// -o: code file name
    string stringsName;     /// -s: strings file name, or its extension if it starts with '.'
    string bg, fg;          /// -bg/-fg: the editor's colors
    string scheme;          /// --scheme: the editor's FLTK scheme
    float scalingFactor = 1.0f; /// -sf: scale the editor's windows
    string inPath;          /// the .fl file, or null

    /// The merge to run, if any.
    bool wantsMerge() const { return mergeBack || mergeBackIfSafe || mergeBackInfo; }
    MergeMode mergeMode() const
    {
        return mergeBackInfo ? MergeMode.info : mergeBackIfSafe ? MergeMode.ifSafe : MergeMode.merge;
    }
}

// The option strings, `"short|long"`, shared by the `getopt()` call and the
// spelling pass in `parseCommandLine()`.
private enum optCompile = "c|compile";
private enum optCompileStrings = "cs|compile-strings";
private enum optStrings = "strings";
private enum optStringsFile = "s|strings-file";
private enum optOutput = "o|output";
private enum optDubHeader = "dub-header";
private enum optUpdate = "u|update";
private enum optMerge = "m|merge-back";
private enum optMergeIfSafe = "mb|merge-back-if-safe";
private enum optMergeInfo = "mi|merge-back-info";
private enum optVersion = "v|version";
private enum optBackground = "bg|background";
private enum optForeground = "fg|foreground";
private enum optScheme = "scheme";
private enum optScalingFactor = "sf|scaling-factor";

private immutable string[] allOptions = [optCompile, optCompileStrings, optStrings, optStringsFile, optOutput,
    optDubHeader, optUpdate, optMerge, optMergeIfSafe, optMergeInfo, optVersion,
    optBackground, optForeground, optScheme, optScalingFactor];

/// `std.getopt` matches only single-letter options after one dash. FLTK
/// programs write `-scheme`, and fluid has `-cs`, `-mb`, `-bg`, ...: a
/// single-dash word that names one of the options above (either spelling)
/// is rewritten to its long form, `--name`.
private string longSpelling(string arg)
{
    import std.algorithm : splitter;
    import std.array : array;

    if (arg.length < 3 || arg[0] != '-' || arg[1] == '-') return arg;
    foreach (opt; allOptions)
    {
        auto names = opt.splitter('|').array;
        foreach (n; names)
            if (n == arg[1 .. $]) return "--" ~ names[$ - 1];
    }
    return arg;
}

/// Parses `args` (consuming every option, so `args[1]` is the input file
/// if any). Short and long spellings come from one `"short|long"` option
/// string each, and `--help` lists them with the descriptions given here.
/// A single-dash multi-letter spelling (`-cs`, `-mb`, `-scheme`) is
/// accepted too, see `longSpelling()`.
/// With `allowUnknown`, options this parser doesn't know stay in `args`
/// for the caller (`fluid` hands them to `fl.core.args()`, which takes
/// FLTK's own `-geometry`, `-display`, ...) and `cl.inPath` is left for it
/// to set; otherwise an unknown option is an error. Returns false after
/// printing help or an error, meaning the caller should just exit.
bool parseCommandLine(ref string[] args, out CommandLine cl, string usageLine, bool allowUnknown = false)
{
    import std.getopt : getopt, config, defaultGetoptPrinter, GetOptException;

    string prog = args.length ? args[0] : "fluid";
    string[] spelled = args.length ? [args[0]] : [];
    foreach (a; args.length ? args[1 .. $] : [])
        spelled ~= a == "-help" ? "--help" : longSpelling(a); // -help: FLTK's spelling
    args = spelled;

    CommandLine c; // the handlers below can't capture the `out` parameter
    try
    {
        auto info = getopt(args, config.passThrough,
            optCompile, "generate the D source file from the .fl project", &c.compile,
            optCompileStrings, "generate the D source file and the i18n strings file", { c.compile = true; c.strings = true; },
            optStrings, "with -c: also write the i18n strings file", &c.strings,
            optStringsFile, "name of the i18n strings file, or its extension if it starts with '.' (with -cs or --strings)", &c.stringsName,
            optOutput, "name of the generated D file (default: the project's code file, else <input>.d)", &c.output,
            optDubHeader, "with -c: prepend a dub single-file-package comment so the file builds with `dub build --single`", &c.dubHeader,
            optUpdate, "load, normalize and resave the .fl file", &c.update,
            optMerge, "merge edits made in the generated file back into the .fl file", &c.mergeBack,
            optMergeIfSafe, "like -m, but only when no block was also changed in the project (exit status 1 otherwise)", &c.mergeBackIfSafe,
            optMergeInfo, "report what -m would merge, change nothing", &c.mergeBackInfo,
            optVersion, "print the version", &c.showVersion,
            optBackground, "color of the editor's windows, e.g. red or #c0c0c0", &c.bg,
            optForeground, "color of the editor's text", &c.fg,
            optScheme, "FLTK scheme of the editor: base, gtk+, gleam, oxy or plastic", &c.scheme,
            optScalingFactor, "scale the editor's windows, 0.25 to 4.0", &c.scalingFactor);
        if (info.helpWanted)
        {
            defaultGetoptPrinter(usageLine, info.options);
            return false;
        }
    }
    catch (GetOptException e)
    {
        stderr.writefln("%s: %s\nTry '%s --help'.", prog, e.msg, prog);
        return false;
    }
    cl = c;

    if (int(cl.mergeBack) + int(cl.mergeBackIfSafe) + int(cl.mergeBackInfo) > 1)
    {
        stderr.writefln("%s: --merge-back, --merge-back-if-safe and --merge-back-info cannot be combined", prog);
        return false;
    }
    if (cl.update && (cl.compile || cl.wantsMerge()))
    {
        stderr.writefln("%s: -u cannot be combined with -c or merging", prog);
        return false;
    }
    if (!(cl.scalingFactor >= 0.25f && cl.scalingFactor <= 4.0f))
    {
        stderr.writefln("%s: --scaling-factor must be between 0.25 and 4.0", prog);
        return false;
    }
    if (!allowUnknown)
    {
        foreach (a; args[1 .. $])
            if (a.length > 1 && a[0] == '-')
            {
                stderr.writefln("%s: Unrecognized option %s\nTry '%s --help'.", prog, a, prog);
                return false;
            }
        cl.inPath = args.length >= 2 ? args[1] : null;
    }
    return true;
}

/// Where the generated `.d` file goes when no `-o` names it: the
/// project's own persisted `code_name` (`Settings -> Project`'s "Code
/// File:" field, resolved the same way `gui_main.d`'s `codeFilePath_()`
/// does), else the input file's own basename with a `.d` extension.
private string defaultCodePath(string inPath, string codeFileName)
{
    if (codeFileName.length == 0)
        return inPath.stripExtension() ~ ".d";
    string name = codeFileName;
    if (name.extension().length == 0) name ~= ".d";
    return name.isAbsolute() ? name : buildPath(dirName(inPath), name);
}

/// The text of `.fl` file `reader` just parsed into `roots`, written
/// back the way the interactive editor's Save writes it: the project's
/// shell commands and layout suites are carried over too, not just the
/// node tree.
private string projectText(Reader reader, Node[] roots)
{
    auto layout = new LayoutList();
    foreach (suite; reader.layoutSuites)
        layout.add(suite);
    if (reader.hasSnap)
    {
        if (reader.layoutCurrentSuite.length) layout.currentSuite(reader.layoutCurrentSuite);
        layout.currentPreset(reader.layoutCurrentPreset);
    }
    return new ProjectWriter().generate(roots, reader.i18n, reader.shellCommands, reader.codeFileName,
        layout, false, reader.dubHeader, reader.settings);
}

/// Headless `.fl -> .d` conversion -- `-c`'s (and `-cs`'s) entire
/// real body. `outPath` may be empty, meaning "resolve it the same
/// way FLTK does" (see the body below); `alsoWriteStrings` is
/// `-cs`'s own extra i18n-strings-file output. `forceDubHeader` is
/// `fluid.app`'s own `--dub-header` flag,
/// ORed with the project's own persisted `dub_header` setting (`Settings
/// -> Project`'s checkbox, round-tripped via `reader.dubHeader`), same
/// "command line can only add, never silently suppress a saved project
/// setting" precedence already established -- unlike `-o`, which always
/// overrides `code_name` outright, there is no real use case for forcing
/// the header *off* from the command line when the project file itself
/// asked for it, so this only ever ORs, never overrides to `false`.
void compileFile(string inPath, string outPath, bool alsoWriteStrings, bool forceDubHeader = false,
    string stringsName = null)
{
    bool outPathFromCommandLine = outPath.length != 0;

    auto source = readText(inPath);
    auto reader = new Reader(source);
    auto roots = reader.readProject();

    // FLTK: `-o` (`outPathFromCommandLine`) always wins, matching
    // `code_file_set`'s own "command-line override beats whatever the
    // project file itself says" precedence (`Project_Reader.cxx`'s own
    // `if (!proj_.code_file_set) proj_.code_file_name = read_word();`).
    // Absent `-o`, fall back to the project's own persisted `code_name`
    // (`settings_panel.fl`'s Project-tab "Code File:" field, same
    // resolution `gui_main.d`'s `writeCodeFile()` uses interactively),
    // then to the input file's own basename.
    if (!outPathFromCommandLine)
        outPath = defaultCodePath(inPath, reader.codeFileName);

    auto writer = new Writer();
    string code;
    try
        code = writer.generate(roots, dirName(inPath), reader.i18n, forceDubHeader || reader.dubHeader,
            reader.settings);
    catch (Exception e)
    {
        // A hard, loud failure here is deliberate -- see code_writer.d's
        // own `emitSnippetLines()`/`collectClassOverrideImports()` doc
        // comments for the incident (`panels/widget_panel.fl`) this
        // guards against: a raw, unconverted FLTK-C++ `.fl` file used to
        // run through `fluid -c` in total silence and produce
        // uncompilable garbage instead of ever being caught here.
        stderr.writefln("fluid: %s: %s", inPath, e.msg);
        import core.stdc.stdlib : exit;

        exit(1);
    }
    // FLTK's batch-mode report of an unreadable inline-data file.
    foreach (err; writer.dataErrors)
        stderr.writef("FLUID ERROR: %s", err);

    write(outPath, code);
    writefln("fluid: %s -> %s", inPath, outPath);
    // Lets the interactive editor's MergeBack find this file even when
    // it was written away from the project (e.g. by a build step).
    if (reader.settings.writeMergebackData)
        rememberCodePath(absolutePath(inPath), absolutePath(outPath));

    if (alsoWriteStrings)
        writeStringsFor(inPath, roots, reader.i18n, stringsName);
}

/// `-u`: load, then immediately resave -- the same "normalize a hand-
/// authored `.fl` file's formatting to this port's own GNU-style
/// output" round-trip `project_writer.d`'s own doc comment named as a
/// still-open follow-up.
void normalizeProject(string path)
{
    auto source = readText(path);
    auto reader = new Reader(source);
    auto roots = reader.readProject();
    if (looksLikeRawCpp(roots))
    {
        stderr.writefln("fluid: %s: contains raw FLTK C++, not this project's D-embedded `.fl` "
            ~ "dialect; not rewritten", path);
        import core.stdc.stdlib : exit;

        exit(1);
    }
    write(path, projectText(reader, roots));
    writefln("fluid: normalized %s", path);
}

/// `-m`/`--merge-back-if-safe`/`--merge-back-info`: merges edits made directly in the generated `.d` file
/// back into the `.fl` project and saves the project, without a GUI.
/// `codePathArg` (`-o`) names the code file; without it the file most
/// recently written for this project (`rememberCodePath()`) is used if
/// it still exists, else the default location `-c` would write to.
/// `MergeMode.ifSafe` refuses to merge when a block was also changed
/// in the project or the file has edits outside the editable blocks;
/// `MergeMode.merge` (`-m`) merges regardless and only warns;
/// `MergeMode.info` only reports. Returns the process
/// exit status: 0 when the merge succeeded, nothing needed merging,
/// MergeBack is not enabled or there is no code file yet (so a build
/// script can run this before every `-c`), 1 for an unreadable tag or
/// an unsafe merge under `--merge-back-if-safe`.
int mergeBackProject(string inPath, string codePathArg, MergeMode mode)
{
    auto reader = new Reader(readText(inPath));
    auto roots = reader.readProject();
    if (!reader.settings.writeMergebackData)
    {
        stderr.writefln("fluid: %s: MergeBack is not enabled for this project (no `mergeback 1`)", inPath);
        return 0;
    }

    string codePath = codePathArg;
    if (codePath.length == 0)
    {
        codePath = rememberedCodePath(absolutePath(inPath));
        if (codePath.length == 0 || !exists(codePath))
            codePath = defaultCodePath(inPath, reader.codeFileName);
    }
    if (!exists(codePath))
    {
        writefln("fluid: %s: no code file found, nothing to merge", codePath);
        return 0;
    }

    string code = cast(string) read(codePath);
    auto mergeback = new Mergeback(roots);
    mergeback.analyse(code);
    if (mergeback.tagError)
    {
        stderr.writefln("fluid: %s: unreadable MergeBack tag in line %d; nothing merged",
            codePath, mergeback.lineNo);
        return 1;
    }
    if (mergeback.numChangedStructure)
        stderr.writefln("fluid: %s: %d edit(s) outside the editable blocks cannot be merged back and "
            ~ "will be lost when the code is generated again", codePath, mergeback.numChangedStructure);
    if (mergeback.numUidNotFound)
        stderr.writefln("fluid: %s: %d edited block(s) belong to nodes not in the project and cannot "
            ~ "be merged back", codePath, mergeback.numUidNotFound);
    if (mergeback.numPossibleOverride)
        stderr.writefln("fluid: %s: %d edited block(s) also changed in the project; merging overrides "
            ~ "the project's text", codePath, mergeback.numPossibleOverride);

    int mergeable = mergeback.numChangedCode - mergeback.numUidNotFound;
    if (mode == MergeMode.ifSafe && (mergeback.numChangedStructure || mergeback.numPossibleOverride))
    {
        stderr.writefln("fluid: %s: not merging (conflicts found, see above)", codePath);
        return 1;
    }
    if (mergeable <= 0)
    {
        writefln("fluid: %s: no external modifications to merge", codePath);
        return 0;
    }
    if (mode == MergeMode.info)
    {
        writefln("fluid: %s: %d block(s) can be merged back; nothing changed", codePath, mergeable);
        return 0;
    }
    if (looksLikeRawCpp(roots))
    {
        stderr.writefln("fluid: %s: contains raw FLTK C++, not this project's D-embedded `.fl` "
            ~ "dialect; not rewritten", inPath);
        return 1;
    }

    mergeback.apply(code);
    write(inPath, projectText(reader, roots));
    writefln("fluid: %s -> %s (%d block(s) merged)", codePath, inPath, mergeable);
    return 0;
}

/// `-cs`'s own second output -- ported from FLTK's `Project::
/// stringsfile_name()`. With no `-s` name, the file is named like the input
/// `.fl` file, in its directory, with an extension chosen by `i18n.type`.
/// A `stringsName` starting with '.' replaces that extension. Any other
/// `stringsName` is the file to write, used as given like `-o`.
private void writeStringsFor(string inPath, Node[] roots, I18nSettings i18n, string stringsName = null)
{
    import fluid.string_writer : writeStrings;

    string ext;
    final switch (i18n.type)
    {
    case I18nType.none: ext = ".txt"; break;
    case I18nType.gnu: ext = ".po"; break;
    case I18nType.posix: ext = ".msg"; break;
    }

    string stringsPath;
    if (stringsName.length && stringsName[0] != '.')
        stringsPath = stringsName;
    else
        stringsPath = buildPath(dirName(inPath),
            filenameSetExt(baseName(inPath), stringsName.length ? stringsName : ext));
    if (writeStrings(roots, i18n, stringsPath) == 0)
        writefln("fluid: %s -> %s", inPath, stringsPath);
    else
        stderr.writefln("fluid: could not write %s", stringsPath);
}

unittest
{
    // -m/--merge-back-if-safe/--merge-back-info end to end on real files, with the remembered-code-path
    // record pointed at a private config directory; and -u keeping the
    // project's shell commands.
    import std.algorithm : canFind;
    import std.file : mkdirRecurse, rmdirRecurse, tempDir;
    import std.path : buildPath;
    import std.process : environment;
    import std.string : replace;
    import fluid.shell_command : ShellCommand, ToolStore;

    string dir = buildPath(tempDir(), "fluid_compile_unittest");
    mkdirRecurse(dir);
    scope (exit) rmdirRecurse(dir);
    string saved = environment.get("XDG_CONFIG_HOME");
    environment["XDG_CONFIG_HOME"] = buildPath(dir, "cfg");
    scope (exit)
    {
        if (saved is null) environment.remove("XDG_CONFIG_HOME");
        else environment["XDG_CONFIG_HOME"] = saved;
    }

    string fl = buildPath(dir, "demo.fl");
    string d = buildPath(dir, "demo.d");
    write(fl, "version 1.0000\nmergeback 1\nFunction {} {open\n} {\n"
        ~ "  Fl_Window w {open\n    xywh {0 0 100 50}\n  } {\n"
        ~ "    Fl_Button b {\n      uid 00a1\n      label Go\n      callback {run();}\n"
        ~ "      xywh {5 5 40 20}\n    }\n  }\n}\n");

    // No code file yet: nothing to do, not an error.
    assert(mergeBackProject(fl, "", MergeMode.merge) == 0);

    compileFile(fl, "", false);
    assert(exists(d));
    assert(mergeBackProject(fl, "", MergeMode.merge) == 0);
    assert(readText(fl).canFind("callback {run();}"));

    // An edit in the generated file is merged back.
    write(d, readText(d).replace("run();", "runFaster();"));
    // ...but the info mode only reports it.
    assert(mergeBackProject(fl, "", MergeMode.info) == 0);
    assert(readText(fl).canFind("run();") && !readText(fl).canFind("runFaster();"));
    assert(mergeBackProject(fl, "", MergeMode.ifSafe) == 0);
    assert(readText(fl).canFind("runFaster();"));

    // Now the project side changes too: --merge-back-if-safe refuses, -m overrides.
    write(fl, readText(fl).replace("runFaster();", "projectSide();"));
    write(d, readText(d).replace("runFaster();", "codeSide();"));
    assert(mergeBackProject(fl, "", MergeMode.ifSafe) == 1);
    assert(readText(fl).canFind("projectSide();"));
    assert(mergeBackProject(fl, "", MergeMode.merge) == 0);
    assert(readText(fl).canFind("codeSide();"));

    // Without `mergeback 1` nothing happens.
    string plain = buildPath(dir, "plain.fl");
    write(plain, "version 1.0000\nFunction {} {open\n} {\n}\n");
    assert(mergeBackProject(plain, "", MergeMode.merge) == 0);

    // -u keeps project shell commands.
    auto reader = new Reader("version 1.0000\nFunction {} {open\n} {\n}\n");
    auto roots = reader.readProject();
    auto cmd = new ShellCommand("build");
    cmd.storage = ToolStore.project;
    cmd.command = "dub build";
    string withShell = new ProjectWriter().generate(roots, I18nSettings.init, [cmd]);
    assert(withShell.canFind("shell_commands"));
    string shellFl = buildPath(dir, "shell.fl");
    write(shellFl, withShell);
    normalizeProject(shellFl);
    assert(readText(shellFl).canFind("dub build"));
}
