/*
 * The top-level `Function {}` wrapper node from a `.fl` file. Two
 * shapes are supported: the anonymous top-level function == main()
 * (`Function {} {open} { ...window... }`), and a named shared-callback
 * function (`Function {button_cb(Fl_Button *b, void *)} { ... } {
 * code {...} {} }`, e.g. radio.fl's `button_cb`) whose `instanceName`
 * (see `Node`/`fluid.project_reader.Reader.parseNode()`) holds the full C++
 * prototype string. `instanceName.length == 0` is how `code_writer.d`
 * tells the two shapes apart -- see its `generate()`. Parsing the
 * prototype string itself (name + first parameter's type/name) is
 * `code_writer.d`'s `parseFunctionSignature()`'s job, not this class's --
 * this node just stores the raw text, matching how every other node
 * kind stores its own raw `instanceName`. Ported from FLTK's
 * `Function_Node` (`fluid/nodes/Function_Node.h`/`.cxx`).
 */
module fluid.function_node;

import fluid.node;
import fluid.project_reader : Reader;

class FunctionNode : Node
{
    string returnType;

    /// `.fl` flags `private`/`protected` (public, the default, writes
    /// nothing). In a class: the method's protection attribute. Outside
    /// one: `private` makes the function module-private (FLTK's
    /// `static`); `protected` (the panel's "local") declares nothing
    /// extra, as the function "may be declared elsewhere".
    Access access = Access.public_;

    /// `.fl` flag `C`: FLTK's `declare "C"`, a C-linkage function,
    /// generated as `extern (C)`. Only meaningful outside a class.
    bool declareC;

    override bool canHaveChildren() const { return true; }

    override bool readProperty(Reader r, string name)
    {
        switch (name)
        {
        case "return_type":
            returnType = r.readValue();
            return true;
        case "private":
            // A bare flag, like "open"/"selected" -- consumes no value.
            // Without this case, the reader's tolerant-of-unknown-
            // properties fallback (readProperty() returns false ->
            // parseNode() defensively calls readValue()) would eat the
            // *next* property's name token instead (e.g. "return_type"),
            // silently corrupting the rest of this Function's property
            // list. Confirmed against radio.fl's button_cb Function,
            // which writes "open private return_type void" on one line.
            access = Access.private_;
            return true;
        case "protected":
            access = Access.protected_;
            return true;
        case "C":
            declareC = true;
            return true;
        default:
            return super.readProperty(r, name);
        }
    }
}
