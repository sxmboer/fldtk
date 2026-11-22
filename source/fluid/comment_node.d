/*
 * A Comment node: notes in the project tree, and a comment in the
 * generated `.d` file where the node sits. `instanceName` holds the text.
 * `inSource_` false keeps the comment in the project file only (the
 * `.fl` flag `not_in_source`). Older files also carry `in_source`,
 * `in_header` and `not_in_header`, which are read and dropped; there is
 * no header file.
 */
module fluid.comment_node;

import fluid.node;
import fluid.project_reader : Reader;

class CommentNode : Node
{
    bool inSource_ = true;

    override bool readProperty(Reader r, string name)
    {
        switch (name)
        {
        case "in_source": inSource_ = true; return true;
        case "not_in_source": inSource_ = false; return true;
        case "in_header":
        case "not_in_header":
            return true;
        default: return super.readProperty(r, name);
        }
    }
}
