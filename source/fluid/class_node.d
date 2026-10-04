/*
 * A real `class Name : Base { ... }` node -- used only when the class
 * genuinely extends an FLTK widget type (a real inheritance
 * relationship: `super()`/virtual dispatch/being usable wherever a
 * `Widget` is expected all matter). Confirmed via `fluid-callback.fl`'s
 * `class App : Fl_Window`.
 *
 * A `class Name { ... }` with *no* base (FLTK's own convenience
 * wrapper letting per-widget static callback trampolines reach sibling
 * widgets without globals -- a workaround for C++'s lack of closures,
 * confirmed against `CubeViewUI.fl`/`.cxx`) is NOT represented by this
 * node at all: that shape is flattened directly in the `.fl` source
 * itself into plain module-level widget globals + a named builder
 * Function -- see `FLUID_DIALECT.md`'s "`Class_Node`: only for a real
 * base-class relationship" section for the full reasoning. So
 * `baseClass` is never empty in practice for a node this class actually
 * produces, but the reader doesn't enforce that -- see `readProperty()`.
 *
 * `instanceName` (set generically by `Reader.parseNode()`, same
 * mechanism every other node type uses) holds the class's own name,
 * e.g. "App". Children are `Function` nodes -- a constructor
 * (`this(...)`), a destructor (`~this()`), and/or ordinary instance
 * methods -- see `code_writer.d`'s `writeClassNode()`/`writeClassMethod()`.
 */
module fluid.class_node;

import fluid.node;
import fluid.project_reader : Reader;

class ClassNode : Node
{
    string baseClass;   // "" if none

    /// Attributes written before the `class` keyword in generated code
    /// (`final`, `abstract`, `export`, `deprecated("...")`, ...): FLTK's
    /// `Class_Node::prefix()`, the class attribute of C++'s
    /// `class ATTRIBUTE Name`. In a `.fl` file it is the extra word before
    /// the name, `class final Foo {`.
    string prefix;

    override bool acceptLeadingAttribute(string word)
    {
        prefix = word;
        return true;
    }

    override bool canHaveChildren() const { return true; }

    override bool readProperty(Reader r, string name)
    {
        // "class App {open : Fl_Window}" -- the base-class name is
        // introduced by a bare ":" token, not a named property. Without
        // this explicit case, the reader's tolerant-of-unknown-
        // properties fallback would still consume the right value token
        // (readValue() right after) but silently discard it instead of
        // recording it here -- the same class of bug the "private"
        // fallback issue in function_node.d already caught once.
        if (name == ":")
        {
            baseClass = r.readValue();
            return true;
        }
        return super.readProperty(r, name);
    }
}
