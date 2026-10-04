/*
 * A raw `code { ... }` fragment inside a `Function`'s children (e.g.
 * radio.fl's `button_cb` body). No fields of its own: `parseNode()`
 * (`fluid/project_reader.d`) already captures a node's leading braced block
 * into `instanceName` generically for every node type -- a `code`
 * node just happens to use that slot for raw C++ source text instead
 * of a widget instance name, the same way FLTK's own `Code_Node`
 * (`fluid/nodes/Code_Node.h`/`.cxx`) reuses its `name()` slot for the
 * same purpose. This class exists purely so `code_writer.d` can `cast(CodeNode)`
 * to tell a code fragment apart from a widget/window/group node.
 */
module fluid.code_node;

import fluid.node;

class CodeNode : Node
{
}
