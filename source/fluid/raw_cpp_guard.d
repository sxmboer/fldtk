/*
 * Detects a project tree that's actually raw, unconverted FLTK C++
 * (a `.fl` file whose `code`/`callback`/`setup`/`decl` bodies are real
 * C++, or whose class overrides are C++ namespace-qualified) rather than
 * this project's own D-embedded `.fl` dialect.
 *
 * `code_writer.d`'s `emitSnippetLines()`/`collectClassOverrideImports()`
 * already reject this for the headless `fluid -c` code-generation path
 * (see that module's own doc comment). This module covers the
 * *interactive* editor's own "Save" path
 * (`gui_main.writeProjectTo()`, via `project_writer.d`), which needs the
 * same guard: `project_writer.d`'s own module doc comment already
 * documents that its round-trip is deliberately lossy (drops properties
 * it doesn't recognize), so opening a raw-C++ `.fl` file in the interactive
 * editor and saving it would silently overwrite the file through that lossy
 * writer, with no way to recover the original content short of restoring
 * it from a backup or version control.
 *
 * Deliberately a separate, standalone check rather than reusing
 * `code_writer.d`'s own private guards: those are woven into that
 * module's own line-by-line emission for exact in-context error
 * messages, and duplicating this project's short, stable 12-entry
 * directive list here is cheaper than the coupling a shared entry point
 * would cost for such a small, unlikely-to-change list.
 */
module fluid.raw_cpp_guard;

import std.string : lineSplitter, strip, startsWith;
import std.algorithm.searching : canFind;

import fluid.node : Node;
import fluid.widget_node : WidgetNode;

private static immutable string[] cPreprocessorDirectives = [
    "#include", "#define", "#undef", "#ifdef", "#ifndef", "#if",
    "#elif", "#else", "#endif", "#pragma", "#error", "#warning",
];

private bool hasRawDirective(string s)
{
    foreach (ln; s.lineSplitter())
    {
        auto t = strip(ln);
        if (t.length == 0) continue;
        foreach (d; cPreprocessorDirectives)
            if (t.startsWith(d)) return true;
    }
    return false;
}

/// True if any node in `roots` (recursively) looks like raw,
/// unconverted FLTK C++: a C preprocessor directive in any code-bearing
/// field (`callback`, `comment`, a `DeclNode`'s own text -- stored in
/// the shared `Node.instanceName` slot, see that field's own doc
/// comment -- or a `WidgetNode`'s `setupCode`), or a `::`-scoped
/// (C++ namespace-qualified) class-override name.
bool looksLikeRawCpp(Node[] roots)
{
    bool found = false;
    void walk(Node[] ns)
    {
        foreach (n; ns)
        {
            if (hasRawDirective(n.callback) || hasRawDirective(n.instanceName)
                || hasRawDirective(n.comment))
                found = true;
            if (auto wn = cast(WidgetNode) n)
            {
                if (hasRawDirective(wn.setupCode)) found = true;
                if (wn.hasClassOverride && wn.classOverride.canFind("::")) found = true;
            }
            walk(n.children);
        }
    }
    walk(roots);
    return found;
}

unittest
{
    auto win = new Node();
    win.typeName = "Fl_Window";

    auto plain = new Node();
    plain.typeName = "Fl_Box";
    plain.callback = "propagate_load";
    win.addChild(plain);

    assert(!looksLikeRawCpp([win]));

    auto raw = new Node();
    raw.typeName = "decl";
    raw.instanceName = `#include "Fluid.h"`;
    win.addChild(raw);

    assert(looksLikeRawCpp([win]));
}

unittest
{
    auto win = new WidgetNode();
    win.typeName = "Fl_Window";

    auto w = new WidgetNode();
    w.typeName = "Fl_Input";
    w.hasClassOverride = true;
    w.classOverride = "fluid::widget::Formula_Input";
    win.addChild(w);

    assert(looksLikeRawCpp([win]));
}
