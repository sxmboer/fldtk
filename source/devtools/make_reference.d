#!/usr/bin/env rdmd
/*
 * make_reference.d: writes docs/TECHNICAL_REFERENCE.md.
 *
 * Run: rdmd source/devtools/make_reference.d     (from anywhere)
 *      DC=ldc2 rdmd source/devtools/make_reference.d
 *
 * The text is technical_reference.md, next to this program: written by
 * hand, with lines that ask for a table made from the library's source.
 * The compiler (`DC`, else dmd) writes the source's declarations and doc
 * comments as JSON (`-X`), and each such line becomes a table:
 *
 *   @members Class         the public member functions Class declares
 *                          itself (not the ones it inherits or
 *                          overrides), overloads together, with the
 *                          first sentence of each one's doc comment
 *   @constructor Class     how to make one: `new Class(...)`
 *   @enum Name             the values of the enum `Name`
 *   @constants module [selector ...]
 *                          the module's constants (manifest constants
 *                          and anonymous enum values); with selectors,
 *                          only those they pick: a capitalised one
 *                          (`Color`) picks the values of an anonymous
 *                          enum of that type (`enum : Color {...}`), a
 *                          lower-case one (`align`) the constants whose
 *                          name starts with it
 *   @functions module [name ...]
 *                          the module's public functions, or only those
 *                          named
 *
 * A signature is the declaration as written in the source, without
 * attributes. A member without a doc comment shows its signature only;
 * those are gaps to fill in the source, not in the template.
 */
module make_reference;

import std.algorithm : canFind, startsWith, endsWith, filter, map, any;
import std.array : appender, join, split, replace, array;
import std.conv : to;
import std.file : readText, write, exists, tempDir, dirEntries, SpanMode, remove;
import std.json;
import std.path : buildPath, buildNormalizedPath, dirName, absolutePath, baseName;
import std.process : environment, execute;
import std.regex : regex, replaceAll, matchFirst;
import std.stdio : writeln, stderr;
import std.string : strip, stripLeft, splitLines, indexOf;

string root;                 // the fldtk folder
JSONValue[string] modules;   // by module name
string[][string] sources;    // source lines, by file

int main(string[] args)
{
    root = buildNormalizedPath(absolutePath(buildPath(dirName(__FILE_FULL_PATH__), "..", "..")));
    string templ = buildPath(root, "source", "devtools", "technical_reference.md");
    string output = buildPath(root, "docs", "TECHNICAL_REFERENCE.md");

    // The library's declarations, as JSON.
    string json = buildPath(tempDir(), "fldtk-reference.json");
    string[] files;
    foreach (e; dirEntries(buildPath(root, "source", "fl"), "*.d", SpanMode.shallow))
        files ~= e.name;
    string dc = environment.get("DC", "dmd");
    string[] cmd = [dc, "-o-", "-D", "-Dd=" ~ buildPath(tempDir(), "fldtk-reference-ddoc"),
        "-X", "-Xf=" ~ json, "-I" ~ buildPath(root, "source")] ~ files;
    auto r = execute(cmd);
    if (r.status != 0)
    {
        stderr.writeln("make_reference: ", dc, " failed:\n", r.output);
        return 1;
    }
    foreach (m; parseJSON(readText(json)).array)
        if ("name" in m) modules[m["name"].str] = m;
    remove(json);

    auto o = appender!string();
    o.put("<!-- Written by source/devtools/make_reference.d from "
        ~ "source/devtools/technical_reference.md and the library's source: "
        ~ "edit those, not this file. -->\n\n");
    int line;
    foreach (l; readText(templ).splitLines())
    {
        line++;
        if (!l.startsWith("@"))
        {
            o.put(l);
            o.put('\n');
            continue;
        }
        auto w = l.split();
        string err;
        switch (w[0])
        {
        case "@members": err = members(o, w[1]); break;
        case "@constructor": err = constructor(o, w[1]); break;
        case "@enum": err = enumTable(o, w[1]); break;
        case "@constants": err = constants(o, w[1], w[2 .. $]); break;
        case "@functions": err = functions(o, w[1], w[2 .. $]); break;
        default: err = "unknown directive " ~ w[0];
        }
        if (err.length)
        {
            stderr.writeln("technical_reference.md(", line, "): ", err);
            return 1;
        }
    }
    write(output, o.data);
    writeln("make_reference: wrote ", output);
    return 0;
}

// ---------------------------------------------------------------------
// Finding declarations
// ---------------------------------------------------------------------

string fileOf(JSONValue mod) => buildPath(root, mod["file"].str);

// The class (or struct) `name` in any module, and the module it is in.
bool findType(string name, out JSONValue type, out JSONValue mod)
{
    foreach (m; modules)
        foreach (d; m["members"].array)
            if (("name" in d) && d["name"].str == name
                && (d["kind"].str == "class" || d["kind"].str == "struct"))
            {
                type = d;
                mod = m;
                return true;
            }
    return false;
}

string prot(JSONValue d) => ("protection" in d) ? d["protection"].str : "public";

// The declaration at `line` of `file`, up to its body: one line or
// several, without attributes and without its body.
string signature(string file, long line)
{
    if (file !in sources) sources[file] = readText(file).splitLines();
    auto lines = sources[file];
    string decl;
    int depth;
    for (size_t i = cast(size_t) line - 1; i < lines.length; i++)
    {
        string l = lines[i].strip();
        foreach (k, c; l)
        {
            if (c == '(') depth++;
            else if (c == ')') depth--;
            else if (depth == 0 && (c == '{' || c == ';' || (c == '=' && k + 1 < l.length && l[k + 1] == '>')))
            {
                decl ~= " " ~ l[0 .. k];
                return tidy(decl);
            }
        }
        decl ~= " " ~ l;
        if (depth == 0 && i + 1 < lines.length && lines[i + 1].strip().startsWith("{"))
            return tidy(decl);
    }
    return tidy(decl);
}

string tidy(string decl)
{
    string s = decl.strip();
    foreach (attr; ["override ", "final ", "static ", "@safe ", "@trusted ", "@system ",
            "nothrow ", "pure ", "@nogc ", "@property ", "ref ", "public ", "export "])
        s = s.replace(attr, "");
    foreach (attr; [" const", " nothrow", " pure", " @nogc", " @safe", " @trusted", " scope", " return"])
        while (s.endsWith(attr)) s = s[0 .. $ - attr.length].stripRight();
    s = s.replaceAll(regex(`\s+`), " ");
    return s.strip();
}

string stripRight(string s)
{
    import std.string : sr = stripRight;
    return sr(s);
}

// The first sentence of a doc comment that says what something does:
// not a porting note, not "ditto".
string summary(string comment)
{
    string c = comment.strip();
    if (c.length == 0 || c == "ditto" || c == "ditto.") return null;
    // The first paragraph, as one line.
    auto para = c.split("\n\n")[0].splitLines().map!(l => l.strip()).join(" ");
    // Sentences: split after ". " unless the period ends an abbreviation.
    string[] sentences;
    size_t start;
    for (size_t i = 0; i + 1 < para.length; i++)
    {
        if ((para[i] == '.' || para[i] == '!' || para[i] == '?') && para[i + 1] == ' ')
        {
            string before = para[start .. i + 1];
            if (before.endsWith("e.g.") || before.endsWith("i.e.") || before.endsWith("etc.")
                || before.endsWith("vs."))
                continue;
            sentences ~= before.strip();
            start = i + 2;
        }
    }
    sentences ~= para[start .. $].strip();
    foreach (s; sentences)
    {
        if (s.length == 0 || s.startsWith("Ported from") || s.startsWith("Port of")
            || s.startsWith("Matches FLTK") || s.startsWith("Matching FLTK")
            || s.startsWith("FLTK") || s.startsWith("(") || s == "ditto")
            continue;
        s = s.replaceAll(regex(`^FL_[A-Z0-9_]+:\s*`), "");
        if (s.length == 0) continue;
        return s.replace("|", "\\|");
    }
    return null;
}

string comment(JSONValue d) => ("comment" in d) ? d["comment"].str : null;

// ---------------------------------------------------------------------
// Tables
// ---------------------------------------------------------------------

string constructor(ref typeof(appender!string()) o, string name)
{
    JSONValue t, m;
    if (!findType(name, t, m)) return "no class " ~ name;
    string file = fileOf(m);
    string[] sigs;
    foreach (d; t["members"].array)
        if (d["kind"].str == "constructor" && prot(d) == "public")
            sigs ~= "new " ~ name ~ signature(file, d["line"].integer)["this".length .. $];
    if (sigs.length == 0) return "no public constructor in " ~ name;
    o.put("```D\n");
    foreach (s; sigs) { o.put(s); o.put('\n'); }
    o.put("```\n");
    return null;
}

string members(ref typeof(appender!string()) o, string name)
{
    JSONValue t, m;
    if (!findType(name, t, m)) return "no class " ~ name;
    string file = fileOf(m);

    // Overloads together, in the order of their first declaration.
    string[] order;
    string[][string] sigs;
    string[string] desc;
    foreach (d; t["members"].array)
    {
        string kind = d["kind"].str;
        if (kind != "function" || prot(d) != "public") continue;
        string n = d["name"].str;
        if (n.startsWith("__") || n == "draw" || n == "handle") continue;
        string sig = signature(file, d["line"].integer);
        if (sig.startsWith("override") || sources[file][cast(size_t) d["line"].integer - 1].canFind("override "))
            continue;
        if (n !in sigs) order ~= n;
        sigs[n] ~= sig;
        if (n !in desc || desc[n].length == 0) desc[n] = summary(comment(d));
    }
    if (order.length == 0)
    {
        o.put("No members of its own.\n");
        return null;
    }
    o.put("| Member | What it does |\n|---|---|\n");
    foreach (n; order)
    {
        auto cells = sigs[n].map!(s => "`" ~ s.replace("|", "\\|") ~ "`").join("<br>");
        o.put("| " ~ cells ~ " | " ~ desc.get(n, "") ~ " |\n");
    }
    return null;
}

string enumTable(ref typeof(appender!string()) o, string name)
{
    foreach (m; modules)
        foreach (d; m["members"].array)
            if (("name" in d) && d["name"].str == name && d["kind"].str == "enum")
            {
                o.put("| Value | |\n|---|---|\n");
                foreach (e; d["members"].array)
                    o.put("| `" ~ name ~ "." ~ e["name"].str ~ "` | " ~ summary(comment(e)) ~ " |\n");
                return null;
            }
    return "no enum " ~ name;
}

// The type of the anonymous enum block (`enum : Color`) that the
// declaration at `line` of `file` is in, or null.
string blockType(string file, long line)
{
    if (file !in sources) sources[file] = readText(file).splitLines();
    auto lines = sources[file];
    for (ptrdiff_t i = cast(ptrdiff_t) line - 1; i >= 0; i--)
    {
        auto l = lines[i].strip();
        if (l.startsWith("enum"))
        {
            auto m = matchFirst(l, regex(`^enum\s*:\s*(\w+)`));
            return m.empty ? null : m[1];
        }
        if (l.startsWith("}")) return null;
    }
    return null;
}

string constants(ref typeof(appender!string()) o, string modName, string[] selectors)
{
    import std.ascii : isUpper;
    if (modName !in modules) return "no module " ~ modName;
    auto mod = modules[modName];
    string file = fileOf(mod);
    o.put("| Constant | Value | |\n|---|---|---|\n");
    int n;
    bool picked(string name, long line)
    {
        if (selectors.length == 0) return true;
        foreach (sel; selectors)
        {
            if (isUpper(sel[0]) ? blockType(file, line) == sel : name.startsWith(sel))
                return true;
        }
        return false;
    }
    void row(JSONValue d)
    {
        string name = d["name"].str;
        if (!picked(name, d["line"].integer)) return;
        if (file !in sources) sources[file] = readText(file).splitLines();
        string decl = sources[file][cast(size_t) d["line"].integer - 1].strip();
        auto eq = decl.indexOf('=');
        string value = eq >= 0 ? decl[eq + 1 .. $].strip() : "";
        auto slash = value.indexOf("//");
        if (slash >= 0) value = value[0 .. slash].strip();
        while (value.endsWith(",") || value.endsWith(";")) value = value[0 .. $ - 1];
        o.put("| `" ~ name ~ "` | `" ~ value.replace("|", "\\|") ~ "` | " ~ summary(comment(d)) ~ " |\n");
        n++;
    }
    foreach (d; mod["members"].array)
    {
        string kind = d["kind"].str;
        if (prot(d) != "public") continue;
        if (kind == "enum member") row(d);
        else if (kind == "variable" && ("storageClass" in d)
            && d["storageClass"].array.any!(s => s.str == "enum"))
            row(d);
    }
    if (n == 0) return "no constants in " ~ modName ~ " for " ~ selectors.join(" ");
    return null;
}

string functions(ref typeof(appender!string()) o, string modName, string[] names)
{
    if (modName !in modules) return "no module " ~ modName;
    auto mod = modules[modName];
    string file = fileOf(mod);
    string[] order;
    string[][string] sigs;
    string[string] desc;
    foreach (d; mod["members"].array)
    {
        if (d["kind"].str != "function" || prot(d) != "public") continue;
        string n = d["name"].str;
        if (n.startsWith("__")) continue;
        if (names.length && !names.canFind(n)) continue;
        if (n !in sigs) order ~= n;
        sigs[n] ~= signature(file, d["line"].integer);
        if (n !in desc || desc[n].length == 0) desc[n] = summary(comment(d));
    }
    foreach (n; names)
        if (n !in sigs) return "no public function " ~ n ~ " in " ~ modName;
    if (order.length == 0) return "no public functions in " ~ modName;
    o.put("| Function | What it does |\n|---|---|\n");
    foreach (n; order)
    {
        auto cells = sigs[n].map!(s => "`" ~ s.replace("|", "\\|") ~ "`").join("<br>");
        o.put("| " ~ cells ~ " | " ~ desc.get(n, "") ~ " |\n");
    }
    return null;
}
