/*
 * A standalone `comment { ... }` project-tree node -- a raw comment
 * block emitted into generated code output as its own tree entry,
 * independent of any other node's own `comment` property (every node
 * type already has one of those, via the generic `Node.comment` field
 * -- this is a different thing: an explicit, selectable "Comment" row
 * a Fluid user can insert directly, matching FLTK's `Comment_Node`
 * (`fluid/nodes/Function_Node.h`/`.cxx`) exactly).
 *
 * `instanceName` (captured generically by `Reader.parseNode()`, the
 * same mechanism `CodeNode`/`DeclNode` use for their own raw text)
 * holds the comment's own text (FLTK's `name()`). `inHeader_`/
 * `inSource_` mirror FLTK's `in_h_`/`in_c_` (both default `true`,
 * matching FLTK's own `Comment_Node()` field initializers) --
 * round-trip only for now, same "no D-codegen meaning yet" category as
 * `fluid.decl_block_node.DeclBlockNode`'s own `writeMap_` (this port's
 * code generator doesn't split output between a header and a source
 * file at all).
 */
module fluid.comment_node;

import fluid.node;
import fluid.project_reader : Reader;

class CommentNode : Node
{
    bool inHeader_ = true;
    bool inSource_ = true;

    override bool readProperty(Reader r, string name)
    {
        switch (name)
        {
        case "in_source": inSource_ = true; return true;
        case "not_in_source": inSource_ = false; return true;
        case "in_header": inHeader_ = true; return true;
        case "not_in_header": inHeader_ = false; return true;
        default: return super.readProperty(r, name);
        }
    }
}
