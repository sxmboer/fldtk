/*
 * A `codeblock { ... }` node -- wraps its own children (a mix of raw
 * `code {}` fragments, nested `codeblock {}`s, and/or a real widget
 * tree, same shape as a `Function`'s own body) in a "before"/"after"
 * pair of literal D text, e.g. an `if (test())` condition and its
 * matching close. Ported from FLTK's `CodeBlock_Node`
 * (`fluid/nodes/Function_Node.h`/`.cxx`): `instanceName` (captured
 * generically by `Reader.parseNode()`, same mechanism `CodeNode` uses
 * for its own body text) holds the "before" text (FLTK's `name()`,
 * e.g. `"if (test())"`); `afterText` is this class's own new property,
 * read via the `"after"` key exactly matching FLTK's own
 * `write_properties()`/`read_property()` (FLTK's own `end_code_`,
 * e.g. `"while (0)"` for a do-while, or empty).
 *
 * This class's own writer (`code_writer.d`'s `writeCodeBlockNode()`)
 * injects real braces around the before/after text and indents its own
 * children one level deeper, matching FLTK's `write_code1()`/
 * `write_code2()` exactly (`before + " {\n"`, then indented children,
 * then `"} " + after + "\n"` or bare `"}\n"`). `fluid.decl_block_node.
 * DeclBlockNode`'s own writer now does the identical thing -- a
 * deliberate departure from *its* FLTK shape (`DeclBlock_Node`
 * emits its before/after text completely raw, no braces at all, which
 * only works for its own bare `#if`/`#endif`-style default content) --
 * see that module's own doc comment for why.
 */
module fluid.code_block_node;

import fluid.node;
import fluid.project_reader : Reader;

class CodeBlockNode : Node
{
    /// Text after the closing brace, on the same line -- FLTK's
    /// `end_code_` (e.g. `"while (0)"` for a do-while, empty for a
    /// plain `if`/`{}` block). `instanceName` (the generic captured
    /// leading-brace text every node type uses) holds the "before"
    /// text instead -- matches FLTK's own split between `name()`
    /// and `end_code()`.
    string afterText;

    override bool canHaveChildren() const { return true; }

    override bool readProperty(Reader r, string name)
    {
        if (name == "after")
        {
            afterText = r.readValue();
            return true;
        }
        return super.readProperty(r, name);
    }
}
