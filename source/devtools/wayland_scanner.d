#!/usr/bin/env rdmd
/*
 * Generates a D binding module from a Wayland protocol XML file -- what
 * `wayland-scanner client-header` plus `wayland-scanner private-code`
 * produce for C, in one D module.
 *
 * Usage:
 *     rdmd source/devtools/wayland_scanner.d [--core] [--import <module>]... <protocol.xml> <module name> <output.d>
 *
 * For example, the modules checked in under source/fl/ are made with:
 *     rdmd source/devtools/wayland_scanner.d --core /usr/share/wayland/wayland.xml \
 *         fl.wayland_protocol source/fl/wayland_protocol.d
 *     rdmd source/devtools/wayland_scanner.d \
 *         /usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml \
 *         fl.xdg_shell_protocol source/fl/xdg_shell_protocol.d
 *     rdmd source/devtools/wayland_scanner.d \
 *         /usr/share/wayland-protocols/stable/tablet/tablet-v2.xml \
 *         fl.tablet_protocol source/fl/tablet_protocol.d
 *     rdmd source/devtools/wayland_scanner.d --import fl.tablet_protocol \
 *         /usr/share/wayland-protocols/staging/cursor-shape/cursor-shape-v1.xml \
 *         fl.cursor_shape_protocol source/fl/cursor_shape_protocol.d
 *     rdmd source/devtools/wayland_scanner.d \
 *         /usr/share/wayland-protocols/unstable/primary-selection/primary-selection-unstable-v1.xml \
 *         fl.primary_selection_protocol source/fl/primary_selection_protocol.d
 *     rdmd source/devtools/wayland_scanner.d \
 *         /usr/share/wayland-protocols/unstable/text-input/text-input-unstable-v3.xml \
 *         fl.text_input_protocol source/fl/text_input_protocol.d
 *     rdmd source/devtools/wayland_scanner.d \
 *         /usr/share/wayland-protocols/staging/fractional-scale/fractional-scale-v1.xml \
 *         fl.fractional_scale_protocol source/fl/fractional_scale_protocol.d
 *     rdmd source/devtools/wayland_scanner.d \
 *         /usr/share/wayland-protocols/stable/viewporter/viewporter.xml \
 *         fl.viewporter_protocol source/fl/viewporter_protocol.d
 *     rdmd source/devtools/wayland_scanner.d /usr/share/wayland-protocols/staging/xdg-activation/xdg-activation-v1.xml \
 *         fl.xdg_activation_protocol source/fl/xdg_activation_protocol.d
 *     rdmd source/devtools/wayland_scanner.d --import fl.xdg_shell_protocol /usr/share/wayland-protocols/staging/xdg-dialog/xdg-dialog-v1.xml \
 *         fl.xdg_dialog_protocol source/fl/xdg_dialog_protocol.d
 *     rdmd source/devtools/wayland_scanner.d --import fl.xdg_shell_protocol /usr/share/wayland-protocols/staging/xdg-toplevel-icon/xdg-toplevel-icon-v1.xml \
 *         fl.xdg_toplevel_icon_protocol source/fl/xdg_toplevel_icon_protocol.d
 *     rdmd source/devtools/wayland_scanner.d /usr/share/wayland-protocols/unstable/xdg-output/xdg-output-unstable-v1.xml \
 *         fl.xdg_output_protocol source/fl/xdg_output_protocol.d
 *     rdmd source/devtools/wayland_scanner.d --import fl.xdg_shell_protocol /usr/share/wayland-protocols/unstable/xdg-decoration/xdg-decoration-unstable-v1.xml \
 *         fl.xdg_decoration_protocol source/fl/xdg_decoration_protocol.d
 *     rdmd source/devtools/wayland_scanner.d /usr/share/wayland-protocols/staging/xdg-system-bell/xdg-system-bell-v1.xml \
 *         fl.xdg_system_bell_protocol source/fl/xdg_system_bell_protocol.d
 *     rdmd source/devtools/wayland_scanner.d /usr/share/wayland-protocols/unstable/pointer-gestures/pointer-gestures-unstable-v1.xml \
 *         fl.pointer_gestures_protocol source/fl/pointer_gestures_protocol.d
 *
 * `--core` is for the core protocol (`wayland.xml`): libwayland-client
 * exports its `wl_*_interface` tables, so the module declares them
 * `extern` instead of defining them. Any other protocol's tables are
 * defined in the module (D-mangled, so they never clash with a copy in
 * another library) and its references to the core
 * protocol's interfaces come from `fl.wayland_protocol`; `--import`
 * names further modules whose interfaces this protocol refers to.
 *
 * The generated module has, per interface: an opaque struct type; its
 * enums as C-named `uint` constants (no type per enum: C keeps enum tags
 * apart from function names, D doesn't, and `wl_shell_surface_resize`
 * is both); one constant per request opcode and per
 * `since` version; a listener struct of `extern(C)` function pointers
 * for its events; `_add_listener()`, `_set_user_data()`,
 * `_get_user_data()`, `_get_version()` and, where the protocol has no
 * `destroy` request, `_destroy()`; and one wrapper function per request,
 * marshalling through `wl_proxy_marshal_flags()`. Names are the C
 * names, so code ported from C reads the same.
 *
 * The XML reader handles exactly what protocol files contain: elements,
 * attributes, comments, text and the five predefined entities.
 */
module wayland_scanner;

import std.algorithm : canFind, map, startsWith;
import std.array : appender, join, replace, split;
import std.conv : to;
import std.file : readText, write;
import std.format : format;
import std.stdio : stderr, writeln;
import std.string : strip, stripRight, toUpper;

struct Node
{
    string name;
    string[string] attrs;
    Node[] children;
    string text;

    string attr(string k, string def = null) const
    {
        auto p = k in attrs;
        return p ? *p : def;
    }

    const(Node)[] all(string tag) const
    {
        const(Node)[] r;
        foreach (ref c; children)
            if (c.name == tag) r ~= c;
        return r;
    }

    const(Node)* first(string tag) const
    {
        foreach (ref c; children)
            if (c.name == tag) return &c;
        return null;
    }
}

string decodeEntities(string s)
{
    return s.replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", "\"")
        .replace("&apos;", "'").replace("&amp;", "&");
}

/// Parses the document into a tree rooted at a synthetic node.
Node parseXml(string src)
{
    Node root;
    Node*[] stack = [&root];
    size_t i = 0;
    while (i < src.length)
    {
        if (src[i] != '<')
        {
            size_t j = i;
            while (j < src.length && src[j] != '<') j++;
            stack[$ - 1].text ~= decodeEntities(src[i .. j]);
            i = j;
            continue;
        }
        if (src[i .. $].startsWith("<!--"))
        {
            import std.string : indexOf;
            auto e = src[i .. $].indexOf("-->");
            i += e + 3;
            continue;
        }
        if (src[i .. $].startsWith("<?") || src[i .. $].startsWith("<!"))
        {
            while (src[i] != '>') i++;
            i++;
            continue;
        }
        if (src[i + 1] == '/')
        {
            while (src[i] != '>') i++;
            i++;
            stack.length--;
            continue;
        }
        // start tag
        i++;
        size_t j = i;
        while (src[j] != ' ' && src[j] != '>' && src[j] != '/' && src[j] != '\n' && src[j] != '\t') j++;
        Node n;
        n.name = src[i .. j];
        i = j;
        bool selfClosing = false;
        for (;;)
        {
            while (src[i] == ' ' || src[i] == '\n' || src[i] == '\t' || src[i] == '\r') i++;
            if (src[i] == '/') { selfClosing = true; i++; continue; }
            if (src[i] == '>') { i++; break; }
            size_t k = i;
            while (src[k] != '=') k++;
            string key = src[i .. k].strip;
            k++;
            while (src[k] != '"' && src[k] != '\'') k++;
            char q = src[k];
            size_t v = k + 1;
            size_t ve = v;
            while (src[ve] != q) ve++;
            n.attrs[key] = decodeEntities(src[v .. ve]);
            i = ve + 1;
        }
        stack[$ - 1].children ~= n;
        if (!selfClosing) stack ~= &stack[$ - 1].children[$ - 1];
    }
    return root;
}

struct Arg
{
    string name, type, iface, enumName;
    bool allowNull;
}

struct Message
{
    string name, summary;
    int since = 1;
    bool destructor;
    Arg[] args;
}

Arg[] argsOf(const ref Node m)
{
    Arg[] r;
    foreach (a; m.all("arg"))
        r ~= Arg(a.attr("name"), a.attr("type"), a.attr("interface"), a.attr("enum"),
            a.attr("allow-null") == "true");
    return r;
}

Message messageOf(const ref Node m)
{
    Message msg;
    msg.name = m.attr("name");
    msg.since = m.attr("since", "1").to!int;
    msg.destructor = m.attr("type") == "destructor";
    if (auto d = m.first("description")) msg.summary = d.attr("summary");
    msg.args = argsOf(m);
    return msg;
}

/// D names that are keywords get a trailing underscore.
string dIdent(string s)
{
    static immutable keywords = ["version", "interface", "function", "delegate", "module",
        "import", "class", "struct", "union", "enum", "alias", "body", "in", "out",
        "ref", "scope", "default", "switch", "case", "string", "object", "debug",
        "new", "delete", "cast", "is", "align", "shared", "pure", "final", "abstract"];
    return keywords.canFind(s) ? s ~ "_" : s;
}

string cType(const ref Arg a, bool forEvent)
{
    switch (a.type)
    {
        case "int": return "int";
        case "uint": return "uint";
        case "fixed": return "wl_fixed_t";
        case "string": return "const(char)*";
        case "fd": return "int";
        case "array": return "wl_array*";
        case "object":
        case "new_id":
            return a.iface.length ? a.iface ~ "*" : (forEvent ? "void*" : "void*");
        default: assert(0, "unknown arg type " ~ a.type);
    }
}

char sigChar(string type)
{
    switch (type)
    {
        case "int": return 'i';
        case "uint": return 'u';
        case "fixed": return 'f';
        case "string": return 's';
        case "object": return 'o';
        case "new_id": return 'n';
        case "array": return 'a';
        case "fd": return 'h';
        default: assert(0, "unknown arg type " ~ type);
    }
}

string signature(const ref Message m)
{
    string s = m.since > 1 ? m.since.to!string : "";
    foreach (a; m.args)
    {
        if (a.allowNull) s ~= "?";
        if (a.type == "new_id" && a.iface.length == 0) s ~= "su";
        s ~= sigChar(a.type);
    }
    return s;
}

/// Doc comment text for a summary attribute, on one line.
string summaryComment(string s, string indent)
{
    if (s.length == 0) return "";
    return indent ~ "/// " ~ s.strip.replace("\n", " ") ~ "\n";
}

int main(string[] args)
{
    bool core = false;
    string[] imports;
    for (;;)
    {
        if (args.length > 1 && args[1] == "--core")
        {
            core = true;
            args = args[0] ~ args[2 .. $];
        }
        else if (args.length > 2 && args[1] == "--import")
        {
            imports ~= args[2];
            args = args[0] ~ args[3 .. $];
        }
        else break;
    }
    if (args.length != 4)
    {
        stderr.writeln("usage: rdmd source/devtools/wayland_scanner.d [--core] [--import <module>]... <protocol.xml> <module name> <output.d>");
        return 1;
    }
    string xmlPath = args[1], moduleName = args[2], outPath = args[3];
    Node doc = parseXml(readText(xmlPath));
    const(Node)* proto = doc.first("protocol");
    if (proto is null)
    {
        stderr.writeln("no <protocol> element in ", xmlPath);
        return 1;
    }

    auto o = appender!string;
    o ~= "/*\n * Generated by source/devtools/wayland_scanner.d from " ~ xmlPath ~ "\n";
    o ~= " * (protocol \"" ~ proto.attr("name") ~ "\"). Do not edit; regenerate instead.\n";
    if (auto c = proto.first("copyright"))
    {
        o ~= " *\n";
        foreach (line; c.text.strip.split("\n"))
            o ~= (" * " ~ line.strip).stripRight ~ "\n";
    }
    o ~= " */\n";
    o ~= "module " ~ moduleName ~ ";\n\n";
    o ~= "version (FLDTK_HAVE_WAYLAND):\n\n";
    o ~= "import fl.wayland_client;\n";
    if (!core) o ~= "import fl.wayland_protocol;\n";
    foreach (m; imports) o ~= "import " ~ m ~ ";\n";
    o ~= "\n";

    // Interfaces defined by this protocol, to tell local references from
    // references to the core protocol.
    string[] local;
    foreach (ifc; proto.all("interface")) local ~= ifc.attr("name");

    // -- interface tables -------------------------------------------------
    if (!core)
    {
        // One shared types array, as wayland-scanner emits: each message
        // points at its own slice of it.
        string[] types;
        size_t[string] typesOffset; // "iface/r|e/name" -> offset
        foreach (ifc; proto.all("interface"))
        {
            foreach (kind; ["request", "event"])
                foreach (mn; ifc.all(kind))
                {
                    auto m = messageOf(mn);
                    typesOffset[ifc.attr("name") ~ "/" ~ kind ~ "/" ~ m.name] = types.length;
                    foreach (a; m.args)
                    {
                        if (a.type == "new_id" && a.iface.length == 0)
                            types ~= ["null", "null", "null"];
                        else if ((a.type == "object" || a.type == "new_id") && a.iface.length)
                            types ~= "&" ~ a.iface ~ "_interface";
                        else
                            types ~= "null";
                    }
                }
        }
        o ~= "private __gshared const(wl_interface)*[" ~ (types.length ? types.length : 1).to!string
            ~ "] types_ = [\n";
        if (types.length == 0) o ~= "    null,\n";
        foreach (t; types) o ~= "    " ~ t ~ ",\n";
        o ~= "];\n\n";

        foreach (ifc; proto.all("interface"))
        {
            string n = ifc.attr("name");
            foreach (kind; ["request", "event"])
            {
                auto ms = ifc.all(kind);
                if (ms.length == 0) continue;
                o ~= "private __gshared wl_message[" ~ ms.length.to!string ~ "] " ~ n ~ "_" ~ kind ~ "s_ = [\n";
                foreach (mn; ms)
                {
                    auto m = messageOf(mn);
                    // a message without arguments never reads its types
                    size_t off = m.args.length ? typesOffset[n ~ "/" ~ kind ~ "/" ~ m.name] : 0;
                    o ~= format("    wl_message(\"%s\", \"%s\", &types_[%d]),\n", m.name, signature(m), off);
                }
                o ~= "];\n\n";
            }
        }
        foreach (ifc; proto.all("interface"))
        {
            string n = ifc.attr("name");
            auto reqs = ifc.all("request"), evs = ifc.all("event");
            o ~= summaryComment(ifc.first("description") ? ifc.first("description").attr("summary") : "", "");
            o ~= format("__gshared wl_interface %s_interface = wl_interface(\"%s\", %s, %d, %s, %d, %s);\n\n",
                n, n, ifc.attr("version"), reqs.length, reqs.length ? n ~ "_requests_.ptr" : "null",
                evs.length, evs.length ? n ~ "_events_.ptr" : "null");
        }
    }
    else
    {
        o ~= "// The interface tables are exported by libwayland-client.\n";
        o ~= "extern (C) extern __gshared\n{\n";
        foreach (ifc; proto.all("interface"))
            o ~= "    const wl_interface " ~ ifc.attr("name") ~ "_interface;\n";
        o ~= "}\n\n";
    }

    // -- per interface ----------------------------------------------------
    foreach (ifc; proto.all("interface"))
    {
        string n = ifc.attr("name");
        string N = n.toUpper;
        o ~= "// ---- " ~ n ~ " " ~ "-".replicate(60 - n.length) ~ "\n\n";
        o ~= summaryComment(ifc.first("description") ? ifc.first("description").attr("summary") : "", "");
        if (n != "wl_display" || !core)
            o ~= "struct " ~ n ~ ";\n\n";

        foreach (e; ifc.all("enum"))
        {
            string en = e.attr("name");
            o ~= summaryComment(e.first("description") ? e.first("description").attr("summary") : "", "");
            foreach (entry; e.all("entry"))
            {
                o ~= summaryComment(entry.attr("summary"), "");
                o ~= format("enum uint %s_%s_%s = %s;\n", N, en.toUpper, entry.attr("name").toUpper,
                    entry.attr("value"));
            }
            o ~= "\n";
        }

        // listener
        auto evs = ifc.all("event");
        if (evs.length)
        {
            o ~= "/// Event handlers for `" ~ n ~ "`, passed to `" ~ n ~ "_add_listener()`.\n";
            o ~= "struct " ~ n ~ "_listener\n{\n";
            foreach (en; evs)
            {
                auto m = messageOf(en);
                o ~= summaryComment(m.summary, "    ");
                string[] ps = ["void* data", n ~ "* " ~ dIdent(n)];
                foreach (a; m.args) ps ~= cType(a, true) ~ " " ~ dIdent(a.name);
                o ~= "    extern (C) void function(" ~ ps.join(", ") ~ ") " ~ dIdent(m.name) ~ ";\n";
            }
            o ~= "}\n\n";
            o ~= "int " ~ n ~ "_add_listener(" ~ n ~ "* obj, const(" ~ n ~ "_listener)* listener, void* data) nothrow @nogc\n{\n";
            o ~= "    return wl_proxy_add_listener(cast(wl_proxy*) obj, cast(void*) listener, data);\n}\n\n";
        }

        // opcodes and since versions
        auto reqs = ifc.all("request");
        foreach (i, rn; reqs)
            o ~= format("enum uint %s_%s = %d;\n", N, rn.attr("name").toUpper, i);
        foreach (en; evs)
            o ~= format("enum uint %s_%s_SINCE_VERSION = %s;\n", N, en.attr("name").toUpper, en.attr("since", "1"));
        foreach (rn; reqs)
            o ~= format("enum uint %s_%s_SINCE_VERSION = %s;\n", N, rn.attr("name").toUpper, rn.attr("since", "1"));
        o ~= "\n";

        o ~= "void " ~ n ~ "_set_user_data(" ~ n ~ "* obj, void* user_data) nothrow @nogc\n{\n"
            ~ "    wl_proxy_set_user_data(cast(wl_proxy*) obj, user_data);\n}\n\n";
        o ~= "void* " ~ n ~ "_get_user_data(" ~ n ~ "* obj) nothrow @nogc\n{\n"
            ~ "    return wl_proxy_get_user_data(cast(wl_proxy*) obj);\n}\n\n";
        o ~= "uint " ~ n ~ "_get_version(" ~ n ~ "* obj) nothrow @nogc\n{\n"
            ~ "    return wl_proxy_get_version(cast(wl_proxy*) obj);\n}\n\n";

        bool hasDestroy = false;
        foreach (rn; reqs) if (rn.attr("name") == "destroy") hasDestroy = true;
        if (!hasDestroy && n != "wl_display")
            o ~= "void " ~ n ~ "_destroy(" ~ n ~ "* obj) nothrow @nogc\n{\n"
                ~ "    wl_proxy_destroy(cast(wl_proxy*) obj);\n}\n\n";

        foreach (rn; reqs)
        {
            auto m = messageOf(rn);
            string fname = n ~ "_" ~ m.name;
            string opcode = N ~ "_" ~ m.name.toUpper;
            string flags = m.destructor ? "WL_MARSHAL_FLAG_DESTROY" : "0";
            const(Arg)* newId;
            foreach (ref a; m.args) if (a.type == "new_id") newId = &a;

            string[] params = [n ~ "* " ~ dIdent(n)];
            string[] callArgs;
            string ret = "void";
            string ifaceExpr = "null";
            string versionExpr = "wl_proxy_get_version(cast(wl_proxy*) " ~ dIdent(n) ~ ")";
            foreach (a; m.args)
            {
                if (a.type == "new_id")
                {
                    if (a.iface.length)
                    {
                        ret = a.iface ~ "*";
                        ifaceExpr = "&" ~ a.iface ~ "_interface";
                        callArgs ~= "null";
                    }
                    else
                    {
                        ret = "void*";
                        params ~= "const(wl_interface)* interface_";
                        params ~= "uint version_";
                        ifaceExpr = "interface_";
                        versionExpr = "version_";
                        callArgs ~= ["interface_.name", "version_", "null"];
                    }
                    continue;
                }
                params ~= cType(a, false) ~ " " ~ dIdent(a.name);
                callArgs ~= dIdent(a.name);
            }
            o ~= summaryComment(m.summary, "");
            o ~= ret ~ " " ~ fname ~ "(" ~ params.join(", ") ~ ") nothrow @nogc\n{\n";
            string call = "wl_proxy_marshal_flags(cast(wl_proxy*) " ~ dIdent(n) ~ ", " ~ opcode ~ ", "
                ~ ifaceExpr ~ ", " ~ versionExpr ~ ", " ~ flags
                ~ (callArgs.length ? ", " ~ callArgs.join(", ") : "") ~ ")";
            if (ret == "void")
                o ~= "    " ~ call ~ ";\n";
            else
                o ~= "    return cast(" ~ ret ~ ") " ~ call ~ ";\n";
            o ~= "}\n\n";
        }
    }

    write(outPath, o.data);
    writeln("wrote ", outPath);
    return 0;
}

string replicate(string s, size_t n)
{
    string r;
    foreach (_; 0 .. n) r ~= s;
    return r;
}
