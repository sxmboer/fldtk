/*
 * Fluid's dub knowledge: where the fldtk folder is, which dub project a
 * design belongs to, and the dub.sdl lines a program built with fldtk
 * needs. Used by the generated code's dub single-file-package header
 * (`fluid.code_writer`), by File > Run and by File > Set Up dub Project
 * (`fluid.gui_main`).
 *
 * Everything here works on paths and text only and starts no process;
 * `fluid.run_program` runs dub.
 *
 * Set Up dub Project writes the files `dub init -n -f sdl` would write
 * (`dub.sdl`, `.gitignore`, `source/`) itself, because `dub init`
 * refuses a folder that already has a `source/` folder. A project
 * described by `dub.json` is not edited: `fldtkLinesJson()` gives the
 * lines to add by hand.
 */
module fluid.dub_project;

import std.algorithm : canFind, startsWith, endsWith;
import std.array : appender, join, replace, split;
import std.file : exists, isDir, isFile, readText;
import std.path : absolutePath, baseName, buildNormalizedPath, buildPath, dirName, relativePath, stripExtension;
import std.string : strip, toLower, splitLines;
import std.uni : isAlphaNum;

import fluid.app_prefs : appPrefs;

/// The preference key of Settings > General > fldtk Folder.
enum fldtkFolderPrefKey = "fldtk_folder";

/// Whether `dir` is a fldtk checkout: it has a `dub.sdl` whose package
/// is named `fldtk`.
bool isFldtkFolder(string dir)
{
    if (dir.length == 0) return false;
    string sdl = buildPath(dir, "dub.sdl");
    if (!exists(sdl) || !isFile(sdl)) return false;
    try
    {
        foreach (line; readText(sdl).splitLines())
            if (line.strip() == `name "fldtk"`)
                return true;
    }
    catch (Exception) {}
    return false;
}

/// Finds the fldtk folder, trying in this order: `preferred` (the
/// fldtk Folder setting), `exeDir` (the folder Fluid itself is in,
/// where `rdmd buildfluid.d` puts it), then `startDir` and each folder
/// above it. Returns an absolute, normalised path, or null when none of
/// them is a fldtk folder (`isFldtkFolder()`).
string findFldtkFolder(string preferred, string exeDir, string startDir)
{
    foreach (candidate; [preferred, exeDir])
        if (candidate.length && isFldtkFolder(candidate))
            return buildNormalizedPath(absolutePath(candidate));

    if (startDir.length == 0) return null;
    string cur = buildNormalizedPath(absolutePath(startDir));
    while (true)
    {
        if (isFldtkFolder(cur)) return cur;
        string parent = dirName(cur);
        if (parent == cur) return null;
        cur = parent;
    }
}

/// `findFldtkFolder()` with the fldtk Folder setting and Fluid's own
/// folder.
string fldtkFolder(string startDir)
{
    import std.file : thisExePath;

    string preferred;
    appPrefs.get(fldtkFolderPrefKey, preferred, "");
    string exeDir;
    try exeDir = dirName(thisExePath());
    catch (Exception) {}
    return findFldtkFolder(preferred, exeDir, startDir);
}

/// The path from folder `from` to `to` as dub.sdl writes it, with
/// forward slashes: relative when it goes up at most three folders
/// (`../fldtk`, `../../fldtk`), so the two folders can move together;
/// otherwise, or on Windows across drives, absolute.
string dubPath(string from, string to)
{
    string absFrom = buildNormalizedPath(absolutePath(from));
    string absTo = buildNormalizedPath(absolutePath(to));
    string rel = relativePath(absTo, absFrom);
    size_t ups;
    foreach (part; rel.replace('\\', '/').split("/"))
        if (part == "..") ups++;
    string path = ups > 3 || rel == absTo ? absTo : rel.length ? rel : ".";
    return path.replace('\\', '/');
}

/// The fldtk folder `fldtkDir` as the `dependency "fldtk" path=` of a
/// recipe in folder `from`, with forward slashes. Absolute, so the
/// project can be moved without breaking its build; relative only when
/// `from` is inside the fldtk folder, which then moves along with it.
string fldtkDubPath(string from, string fldtkDir)
{
    if (isInside(from, fldtkDir)) return dubPath(from, fldtkDir);
    return buildNormalizedPath(absolutePath(fldtkDir)).replace('\\', '/');
}

/// Whether `path` is `dir` or lies inside it.
bool isInside(string path, string dir)
{
    import std.path : dirSeparator, filenameCmp;

    string p = buildNormalizedPath(absolutePath(path));
    string d = buildNormalizedPath(absolutePath(dir));
    if (filenameCmp(p, d) == 0) return true;
    if (!d.endsWith(dirSeparator)) d ~= dirSeparator;
    return p.length > d.length && filenameCmp(p[0 .. d.length], d) == 0;
}

/// The dub project a design in folder `flDir` belongs to: the nearest
/// folder at or above `flDir` with a `dub.sdl` or `dub.json`. A recipe
/// inside the fldtk folder `fldtkDir` (fldtk's own, or Fluid's) does
/// not count, so a design kept in the fldtk checkout has no project.
/// Returns an absolute path, or null.
string findDubProject(string flDir, string fldtkDir)
{
    string cur = buildNormalizedPath(absolutePath(flDir));
    while (true)
    {
        if (fldtkDir.length && isInside(cur, fldtkDir)) return null;
        if (exists(buildPath(cur, "dub.sdl")) || exists(buildPath(cur, "dub.json")))
            return cur;
        string parent = dirName(cur);
        if (parent == cur) return null;
        cur = parent;
    }
}

/// Whether `name` (a file name without its extension) can be the name of
/// a D source file. A generated code file has no `module` line, so the
/// compiler takes its module name from the file name, which then has to
/// be made of letters, digits and underscores, not starting with a digit.
bool isDModuleName(string name)
{
    import std.uni : isAlpha;
    import std.ascii : isDigit;

    if (name.length == 0 || isDigit(name[0])) return false;
    foreach (dchar c; name)
        if (c != '_' && !isDigit(c) && !isAlpha(c)) return false;
    return true;
}

unittest
{
    assert(isDModuleName("hello"));
    assert(isDModuleName("my_app2"));
    assert(isDModuleName("_tmp"));
    assert(isDModuleName("import"));
    assert(!isDModuleName(""));
    assert(!isDModuleName("my-app"));
    assert(!isDModuleName("my app"));
    assert(!isDModuleName("my.app"));
    assert(!isDModuleName("2app"));
}

/// A dub package name made from `s` (usually the design's file name):
/// dub wants lower case letters, digits, `-` and `_`. Anything else
/// becomes `-`; an empty result becomes `app`.
string dubPackageName(string s)
{
    auto r = appender!string;
    foreach (dchar c; s.toLower())
    {
        if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_' || c == '-')
            r.put(c);
        else if (r.data.length && !r.data.endsWith("-"))
            r.put('-');
    }
    string name = r.data;
    while (name.endsWith("-")) name = name[0 .. $ - 1];
    return name.length ? name : "app";
}

/// What a dub.sdl needs for a program built with fldtk, given its
/// project folder's path to the fldtk folder (`fldtkPath`, as
/// `fldtkDubPath()` gives it) and to the design (`flPath`, ditto). The
/// `preGenerateCommands` lines run `fluid -c` before every build, so a
/// `dub build` or `dub run` typed in a terminal also uses the latest
/// design.
string[] fldtkSdlLines(string fldtkPath, string flPath)
{
    // In an SDL string, `\\` is one backslash.
    string flWin = flPath.replace("/", `\\`);
    return [
        `targetType "executable"`,
        `dependency "fldtk" path="` ~ fldtkPath ~ `"`,
        `subConfiguration "fldtk" "program"`,
        `preGenerateCommands "\"$FLDTK_PACKAGE_DIR/fluid\" -c \"$PACKAGE_DIR/` ~ flPath ~ `\"" platform="linux"`,
        `preGenerateCommands "\"$FLDTK_PACKAGE_DIR\\fluid.exe\" -c \"$PACKAGE_DIR\\` ~ flWin ~ `\"" platform="windows"`,
    ];
}

/// The same as `fldtkSdlLines()` in dub.json's notation, to show to the
/// user of a `dub.json` project.
string fldtkLinesJson(string fldtkPath, string flPath)
{
    // In a JSON string, as in SDL, `\\` is one backslash.
    string flWin = flPath.replace("/", `\\`);
    return `"targetType": "executable",` ~ "\n"
        ~ `"dependencies": { "fldtk": { "path": "` ~ fldtkPath ~ `" } },` ~ "\n"
        ~ `"subConfigurations": { "fldtk": "program" },` ~ "\n"
        ~ `"preGenerateCommands-linux": [ "\"$FLDTK_PACKAGE_DIR/fluid\" -c \"$PACKAGE_DIR/` ~ flPath ~ `\"" ],` ~ "\n"
        ~ `"preGenerateCommands-windows": [ "\"$FLDTK_PACKAGE_DIR\\fluid.exe\" -c \"$PACKAGE_DIR\\` ~ flWin ~ `\"" ]`;
}

/// A new dub.sdl for package `name`, with the lines `dub init` writes
/// followed by `fldtkSdlLines()`.
string newDubSdl(string name, string author, string fldtkPath, string flPath)
{
    string[] lines = [
        `name "` ~ name ~ `"`,
        `description "A program made with Fluid and fldtk."`,
        `authors "` ~ (author.length ? author : "you") ~ `"`,
        `license "proprietary"`,
    ];
    return (lines ~ fldtkSdlLines(fldtkPath, flPath)).join("\n") ~ "\n";
}

/// Whether the dub.sdl text `sdl` already depends on fldtk.
bool sdlUsesFldtk(string sdl)
{
    foreach (line; sdl.splitLines())
        if (line.strip().startsWith(`dependency "fldtk"`))
            return true;
    return false;
}

/// Adds to the dub.sdl text `sdl` those of `fldtkSdlLines()` it lacks,
/// at its end, and returns the new text; `added` receives the lines
/// added (none when it already had them all). A line counts as present
/// when the recipe's top level has a line with the same directive for
/// the same thing: any `targetType`, `dependency "fldtk"`,
/// `subConfiguration "fldtk"`, or a `preGenerateCommands` for the same
/// platform that runs fluid. Existing lines are never changed, so a
/// `dependency "fldtk"` with another path keeps it.
string addFldtkSdlLines(string sdl, string fldtkPath, string flPath, out string[] added)
{
    bool[string] have;
    foreach (raw; sdl.splitLines())
    {
        // Only top-level lines: a directive inside a configuration block
        // is indented, and applies to that configuration only.
        if (raw.length == 0 || raw[0] == ' ' || raw[0] == '\t') continue;
        string line = raw.strip();
        if (line.startsWith("targetType ")) have["targetType"] = true;
        if (line.startsWith(`dependency "fldtk"`)) have["dependency"] = true;
        if (line.startsWith(`subConfiguration "fldtk"`)) have["subConfiguration"] = true;
        if (line.startsWith("preGenerateCommands") && line.canFind("fluid"))
        {
            if (line.canFind(`platform="windows"`)) have["pre-windows"] = true;
            else if (line.canFind(`platform="linux"`)) have["pre-linux"] = true;
            else { have["pre-windows"] = true; have["pre-linux"] = true; }
        }
    }

    static immutable string[] keys = ["targetType", "dependency", "subConfiguration", "pre-linux", "pre-windows"];
    auto lines = fldtkSdlLines(fldtkPath, flPath);
    foreach (i, key; keys)
        if (key !in have)
            added ~= lines[i];

    if (added.length == 0) return sdl;
    string text = sdl;
    if (text.length && !text.endsWith("\n")) text ~= "\n";
    return text ~ added.join("\n") ~ "\n";
}

/// The `.gitignore` `dub init` writes for package `name`.
string dubGitignore(string name)
{
    return [".dub", "docs.json", "__dummy.html", "docs/", "/" ~ name, name ~ ".so", name ~ ".dylib",
        name ~ ".dll", "lib" ~ name ~ ".a", name ~ ".a", name ~ ".lib", name ~ "-test-*",
        "*.exe", "*.pdb", "*.o", "*.obj", "*.lst"].join("\n") ~ "\n";
}

/// Whether the file `path` is the placeholder `source/app.d` that
/// `dub init` writes, unchanged.
bool isDubInitPlaceholder(string path)
{
    import std.array : replace;
    import std.string : strip;

    if (!exists(path)) return false;
    try
    {
        string text = readText(path).replace("\r\n", "\n").replace("    ", "\t").strip();
        return text == "import std.stdio;\n\nvoid main()\n{\n\twriteln(\"Edit source/app.d to start your project.\");\n}";
    }
    catch (Exception) { return false; }
}

/// The user's name for a new dub.sdl's `authors` line, from the
/// environment; empty when unknown.
string userName()
{
    import std.process : environment;
    foreach (var; ["USER", "USERNAME", "LOGNAME"])
    {
        string v = environment.get(var, "");
        if (v.length) return v;
    }
    return "";
}

/// Splits `data` after its last complete UTF-8 sequence: returns the
/// complete part and leaves an incomplete trailing sequence in `rest`,
/// so output read from a pipe in pieces is never shown cut through a
/// character.
const(char)[] completeUtf8(const(char)[] data, out const(char)[] rest)
{
    size_t n = data.length;
    // Walk back over at most 3 continuation bytes to the lead byte.
    size_t i = n;
    size_t back = 0;
    while (i > 0 && back < 4 && (data[i - 1] & 0xC0) == 0x80) { i--; back++; }
    if (i == 0) return data;
    ubyte lead = data[i - 1];
    size_t need = lead < 0x80 ? 1 : (lead & 0xE0) == 0xC0 ? 2 : (lead & 0xF0) == 0xE0 ? 3 : (lead & 0xF8) == 0xF0 ? 4 : 1;
    if (back + 1 < need)
    {
        rest = data[i - 1 .. $];
        return data[0 .. i - 1];
    }
    return data;
}

unittest
{
    import std.file : mkdirRecurse, rmdirRecurse, tempDir, write;

    string root = buildPath(tempDir(), "fluid_dub_project_unittest");
    if (exists(root)) rmdirRecurse(root);
    scope (exit) rmdirRecurse(root);

    // A fldtk folder, a design inside it, and a project next to it.
    mkdirRecurse(buildPath(root, "fldtk", "source", "test"));
    write(buildPath(root, "fldtk", "dub.sdl"), "name \"fldtk\"\n");
    mkdirRecurse(buildPath(root, "fldtk", "source", "fluid"));
    write(buildPath(root, "fldtk", "source", "fluid", "dub.sdl"), "name \"fluid\"\n");
    mkdirRecurse(buildPath(root, "hello", "ui"));
    write(buildPath(root, "hello", "dub.sdl"), "name \"hello\"\n");
    mkdirRecurse(buildPath(root, "other"));
    mkdirRecurse(buildPath(root, "notfldtk"));
    write(buildPath(root, "notfldtk", "dub.sdl"), "name \"x\"\n");

    string fl = buildPath(root, "fldtk");
    assert(isFldtkFolder(fl));
    assert(!isFldtkFolder(buildPath(root, "notfldtk")));

    // The setting wins, then Fluid's folder, then the folders above.
    assert(findFldtkFolder(fl, buildPath(root, "notfldtk"), buildPath(root, "other")) == fl);
    assert(findFldtkFolder("", fl, buildPath(root, "other")) == fl);
    assert(findFldtkFolder(buildPath(root, "notfldtk"), "", buildPath(fl, "source", "test")) == fl);
    assert(findFldtkFolder("", "", buildPath(root, "other")) is null);

    // The nearest recipe counts, but not one in the fldtk folder.
    assert(findDubProject(buildPath(root, "hello", "ui"), fl) == buildPath(root, "hello"));
    assert(findDubProject(buildPath(fl, "source", "fluid"), fl) is null);
    assert(findDubProject(buildPath(fl, "source", "test"), fl) is null);

    assert(dubPath(buildPath(root, "hello"), fl) == "../fldtk");
    assert(dubPath(fl, fl) == ".");
    assert(dubPath(buildPath(root, "a", "b", "c", "d"), fl) == buildNormalizedPath(fl).replace('\\', '/'));
    assert(fldtkDubPath(buildPath(root, "hello"), fl) == buildNormalizedPath(fl).replace('\\', '/'));
    assert(fldtkDubPath(buildPath(fl, "source", "test"), fl) == "../..");
    assert(isInside(buildPath(fl, "source"), fl));
    assert(!isInside(buildPath(root, "fldtk2"), fl));
}

unittest
{
    assert(dubPackageName("Hello") == "hello");
    assert(dubPackageName("My Proj") == "my-proj");
    assert(dubPackageName("four_buttons2") == "four_buttons2");
    assert(dubPackageName("  !!") == "app");
    assert(dubPackageName("a..b!") == "a-b");
}

unittest
{
    // A new dub.sdl has dub init's lines and fldtk's.
    string sdl = newDubSdl("hello", "me", "../fldtk", "hello.fl");
    assert(sdl.canFind(`name "hello"`));
    assert(sdl.canFind(`dependency "fldtk" path="../fldtk"`));
    assert(sdl.canFind(`"\"$FLDTK_PACKAGE_DIR/fluid\" -c \"$PACKAGE_DIR/hello.fl\"" platform="linux"`));
    assert(sdl.canFind(`"\"$FLDTK_PACKAGE_DIR\\fluid.exe\" -c \"$PACKAGE_DIR\\hello.fl\"" platform="windows"`));
    assert(sdlUsesFldtk(sdl));

    // Nothing is added to a complete one.
    string[] added;
    assert(addFldtkSdlLines(sdl, "../fldtk", "hello.fl", added) == sdl);
    assert(added.length == 0);

    // dub init's dub.sdl gets every line, after its own (no trailing
    // newline in the original).
    string init = "name \"hello\"\ndescription \"A minimal D application.\"";
    string result = addFldtkSdlLines(init, "../fldtk", "ui/hello.fl", added);
    assert(added.length == 5);
    assert(result.startsWith(init ~ "\n"));
    assert(result.canFind(`$PACKAGE_DIR/ui/hello.fl`));
    assert(result.canFind(`$PACKAGE_DIR\\ui\\hello.fl`));
    assert(!sdlUsesFldtk(init) && sdlUsesFldtk(result));

    // Existing lines are kept; only the missing ones are added, and a
    // line inside a configuration block doesn't count.
    string partial = "name \"x\"\ntargetType \"executable\"\ndependency \"fldtk\" path=\"/opt/fldtk\"\n"
        ~ "configuration \"a\" {\n    subConfiguration \"fldtk\" \"program\"\n}\n";
    result = addFldtkSdlLines(partial, "../fldtk", "x.fl", added);
    assert(added.length == 3);
    assert(added[0] == `subConfiguration "fldtk" "program"`);
    assert(!result.canFind(`path="../fldtk"`));
}

unittest
{
    const(char)[] rest;
    assert(completeUtf8("abc", rest) == "abc" && rest.length == 0);
    string e = "a\u00e9"; // é is two bytes
    assert(completeUtf8(e[0 .. 2], rest) == "a" && rest == e[1 .. 2]);
    assert(completeUtf8(e, rest) == e && rest.length == 0);
    string euro = "\u20ac"; // three bytes
    assert(completeUtf8(euro[0 .. 2], rest).length == 0 && rest == euro[0 .. 2]);
}

unittest
{
    // Only dub init's untouched placeholder counts.
    import std.file : tempDir, write, remove;
    string p = buildPath(tempDir, "fluid_dub_init_placeholder.d");
    scope (exit) if (exists(p)) remove(p);

    write(p, "import std.stdio;\n\nvoid main()\n{\n\twriteln(\"Edit source/app.d to start your project.\");\n}\n");
    assert(isDubInitPlaceholder(p));
    write(p, "import std.stdio;\r\n\r\nvoid main()\r\n{\r\n    writeln(\"Edit source/app.d to start your project.\");\r\n}\r\n");
    assert(isDubInitPlaceholder(p));
    write(p, "import std.stdio;\n\nvoid main()\n{\n\twriteln(\"Edit source/app.d to start your project.\");\n\twriteln(\"mine\");\n}\n");
    assert(!isDubInitPlaceholder(p));
    remove(p);
    assert(!isDubInitPlaceholder(p));
}
