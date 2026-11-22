/*
 * A Code node: raw D at any scope. At module scope it holds imports,
 * module variables, helper types and functions; directly in a Class it
 * holds the class's fields; inside a Function, or among a window's
 * widgets, it holds statements, run in their place. `instanceName` holds
 * the text and `comment` an optional comment written before it.
 * `code_writer.d` decides which of these the text is from where the node
 * sits (`isDeclarationScope()`).
 *
 * The reader also turns older files' `decl` and `data` nodes and their
 * old-style `class` nodes into Code nodes (`project_reader.d`'s
 * `parseNode()`). A `decl`'s header-file flags (`public`, `private`,
 * `protected`, `local`, `global`) choose where C++ code goes and mean
 * nothing here; they are read and dropped.
 */
module fluid.code_node;

import fluid.node;
import fluid.project_reader : Reader;

class CodeNode : Node
{
    override bool readProperty(Reader r, string name)
    {
        switch (name)
        {
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
