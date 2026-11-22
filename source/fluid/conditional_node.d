/*
 * A Conditional node: code and widgets that are only there under a
 * condition. `instanceName` holds the header line, which is the
 * condition (`if (x > 0)`, `else`, `static if (...)`, `debug`,
 * `version (Windows)`, `version (none)` to switch code off), and the
 * children go inside `{ ... }` after it. Fluid writes the header as given,
 * so any other D block header works too, and the compiler reports a
 * header that doesn't fit its scope (`if` and `else` only work inside a
 * function).
 *
 * The node works at every scope: at module or class scope its children
 * are declarations, inside a function or among a window's widgets they
 * are statements and widgets (see `code_writer.d`'s
 * `writeConditionalNode()`). An `else` is a Conditional node of its own,
 * following an `if`, `static if`, `version` or `debug` node at the same
 * level.
 *
 * In a `.fl` file the node is `conditional {header} {properties} {children}`.
 * The reader also turns older files' `codeblock` and `declblock` nodes
 * into Conditional nodes; `legacyAfter` holds what such a node had after
 * its closing brace (`while (0)` of a `do` loop), which a Conditional
 * node has no place for, so the reader reports it (`Reader.notes`).
 */
module fluid.conditional_node;

import fluid.node;
import fluid.project_reader : Reader;

class ConditionalNode : Node
{
    /// Text after the closing brace in an older file's `codeblock` or
    /// `declblock`: read so the reader can report it, never written.
    string legacyAfter;

    override bool canHaveChildren() const { return true; }

    override bool readProperty(Reader r, string name)
    {
        switch (name)
        {
        case "after":
            legacyAfter = r.readValue();
            return true;
        // An older `declblock`'s header-file flags: bare `public` and
        // `protected`, and `map N`. They choose where C++ code goes and
        // mean nothing here.
        case "public":
        case "protected":
            return true;
        case "map":
            r.readValue();
            return true;
        default:
            return super.readProperty(r, name);
        }
    }
}
