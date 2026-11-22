/*
 * The Class node: `class Name : Base { ... }`, a plain D class written in
 * the project tree. `instanceName` holds the name, `baseClass` the base
 * ("" for none) and `prefix` attributes written before `class` (`final`,
 * `abstract`). In a `.fl` file the node is `class Name {: {Base}}
 * {children}`, and `class final Name` gives the prefix.
 *
 * Its children make up the class body (`code_writer.d`'s
 * `writeClassNode()`): Code nodes are fields, Function nodes methods (a
 * Function named `this(...)` is a constructor, `~this()` the destructor),
 * Conditional nodes hold fields or methods under a condition, and a Class
 * inside is a nested class. A method can build a Window with widgets; the
 * named widgets in it become fields of the class, so every instance has
 * its own.
 */
module fluid.class_node;

import fluid.node;
import fluid.project_reader : Reader;

class ClassNode : Node
{
    /// The base class after `:`, or "" for none.
    string baseClass;

    /// Attributes written before `class` (`final`, `abstract`, ...).
    string prefix;

    override bool acceptLeadingAttribute(string word)
    {
        prefix = word;
        return true;
    }

    override bool canHaveChildren() const { return true; }

    override bool readProperty(Reader r, string name)
    {
        switch (name)
        {
        case ":":
            baseClass = r.readValue();
            return true;
        // Older files' C++ header-file flags.
        case "public":
        case "private":
        case "protected":
            return true;
        default:
            return super.readProperty(r, name);
        }
    }
}
