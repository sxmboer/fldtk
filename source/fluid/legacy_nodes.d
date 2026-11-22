/*
 * The two node kinds older `.fl` files have that Fluid converts as it
 * reads them (`project_reader.d`'s `convertLegacy()`):
 *
 * - `data name { filename {path} }` embeds a file's contents. It becomes
 *   a Code node with D's string import, `immutable ubyte[] name =
 *   cast(immutable ubyte[]) import("path");`, or `immutable string name
 *   = import("path");` for a `textmode` node. The compiler finds the file
 *   through the string import paths (dmd's `-J`), which name the
 *   project's folder. A `compressed` node becomes the same plain import:
 *   the file it names is uncompressed on disk, and the program sees the
 *   same bytes. The variable is named in camelCase
 *   (`pixmaps_black_checker_png` -> `pixmapsBlackCheckerPng`).
 * - `widget_class Name { properties } { children }` is a group or window
 *   designed as a class of its own. It becomes a Class of the same name
 *   with a `make()` method that builds the widgets in a Window.
 */
module fluid.legacy_nodes;

import std.array : appender, replace, split;
import std.format : format;
import std.path : baseName, isAbsolute;
import std.algorithm.searching : canFind;

import std.string : indexOf;

import fluid.node;
import fluid.class_node : ClassNode;
import fluid.code_node : CodeNode;
import fluid.comment_node : CommentNode;
import fluid.conditional_node : ConditionalNode;
import fluid.function_node : FunctionNode;
import fluid.widget_node : WidgetNode;
import fluid.window_node : WindowNode;
import fluid.project_reader : Reader;

/// An older file's `data` node, as read; `dataToCode()` converts it.
class LegacyDataNode : Node
{
    /// Path to the file, relative to the `.fl` file's folder.
    string filename;

    /// `textmode`: the contents are text, a `string`.
    bool asString;

    override bool readProperty(Reader r, string name)
    {
        switch (name)
        {
        case "filename":
            filename = r.readValue();
            return true;
        case "textmode":
        case "std_textmode":
            asString = true;
            return true;
        // The other storage formats (`compressed`, `std_binary`,
        // `std_compressed`) and the header-file flags: the plain import
        // covers them all.
        case "compressed":
        case "std_compressed":
        case "std_binary":
        case "public":
        case "private":
        case "protected":
        case "local":
        case "global":
            return true;
        default:
            return super.readProperty(r, name);
        }
    }
}

/// An older file's `widget_class` node, as read: a group or window
/// designed as a class of its own. `widgetClassToClass()` converts it.
class LegacyWidgetClassNode : WindowNode
{
    override bool readProperty(Reader r, string name)
    {
        switch (name)
        {
        // How the old generated constructor placed the group; a Class
        // builds its window in `make()` instead.
        case "position_relative":
        case "position_relative_rescale":
            return true;
        default:
            return super.readProperty(r, name);
        }
    }
}

/// The Class a `widget_class` node becomes: a Class of the same name
/// whose `make()` method builds the widgets in a Window, the field
/// `window` (the node itself, renamed). Code and Function children, and Conditional
/// nodes without widgets, stay in the class as fields and methods.
ClassNode widgetClassToClass(LegacyWidgetClassNode wc, ref string[] notes)
{
    auto cls = new ClassNode();
    cls.typeName = "class";
    cls.instanceName = wc.instanceName;
    cls.comment = wc.comment;
    cls.uid = wc.uid;

    auto make = new FunctionNode();
    make.typeName = "Function";
    make.instanceName = "make()";

    Node[] keep;
    foreach (c; wc.children)
    {
        if (cast(CodeNode) c || cast(FunctionNode) c || cast(CommentNode) c || cast(ClassNode) c
            || (cast(ConditionalNode) c && !holdsWidget(c)))
            cls.addChild(c);
        else
            keep ~= c;
    }
    wc.children = null;
    foreach (c; keep)
        wc.addChild(c);

    string base = wc.hasClassOverride ? wc.classOverride : "";
    if (base.indexOf("Window") < 0)
    {
        wc.hasClassOverride = false;
        wc.classOverride = null;
    }
    wc.typeName = "Window";
    wc.instanceName = "window";
    wc.comment = null;
    make.addChild(wc);
    cls.addChild(make);

    notes ~= format("Widget Class %s is now a Class whose make() method builds its widgets in a window, "
        ~ "`window`: create it with `auto p = new %s(); p.make();` instead of `new %s(x, y, w, h)`.",
        cls.instanceName, cls.instanceName, cls.instanceName);
    return cls;
}

private bool holdsWidget(Node n)
{
    foreach (c; n.children)
        if (cast(WidgetNode) c || holdsWidget(c))
            return true;
    return false;
}

/// `pixmaps_black_checker_png` -> `pixmapsBlackCheckerPng`.
string snakeToCamel(string s)
{
    auto parts = s.split("_");
    if (parts.length == 0)
        return s;
    auto result = appender!string();
    result.put(parts[0]);
    foreach (p; parts[1 .. $])
    {
        if (p.length == 0)
            continue;
        result.put(cast(char)(p[0] >= 'a' && p[0] <= 'z' ? p[0] - 32 : p[0]));
        result.put(p[1 .. $]);
    }
    return result.data;
}

/// The Code node a `data` node becomes. A string import can't name a
/// file outside its import folders (`..`, an absolute path), so such a
/// file is imported by its own name and `notes` says which folder to add.
CodeNode dataToCode(LegacyDataNode dn, ref string[] notes)
{
    string varName = snakeToCamel(dn.instanceName);
    string path = dn.filename;
    // Backslashes would be escapes in the D string literal.
    path = path.replace("\\", "/");
    if (path.isAbsolute || path.split("/").canFind(".."))
    {
        notes ~= format("Data %s: %s is outside the project's folder. It is now imported as \"%s\"; "
            ~ "add its folder to the string import paths.", dn.instanceName, path, baseName(path));
        path = baseName(path);
    }
    auto cn = new CodeNode();
    cn.typeName = "code";
    cn.comment = dn.comment;
    cn.uid = dn.uid;
    if (path.length == 0)
        cn.instanceName = format("immutable %s %s;", dn.asString ? "string" : "ubyte[]", varName);
    else if (dn.asString)
        cn.instanceName = format(`immutable string %s = import("%s");`, varName, path);
    else
        cn.instanceName = format(`immutable ubyte[] %s = cast(immutable ubyte[]) import("%s");`, varName, path);
    return cn;
}

unittest
{
    string[] notes;
    auto dn = new LegacyDataNode();
    dn.instanceName = "pixmaps_black_checker_png";
    dn.filename = "pixmaps/black_checker.png";
    auto cn = dataToCode(dn, notes);
    assert(cn.instanceName == `immutable ubyte[] pixmapsBlackCheckerPng = cast(immutable ubyte[]) import("pixmaps/black_checker.png");`);
    assert(notes.length == 0);

    dn.asString = true;
    dn.filename = "../templates/license.fl";
    cn = dataToCode(dn, notes);
    assert(cn.instanceName == `immutable string pixmapsBlackCheckerPng = import("license.fl");`);
    assert(notes.length == 1);
}
