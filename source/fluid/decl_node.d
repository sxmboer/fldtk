/*
 * A top-level `decl { ... }` node -- raw D text (struct/global/
 * function definitions) emitted verbatim at module scope, sitting
 * alongside `Function`/`class` roots rather than nested inside any of
 * them. Needed once a `.fl` file's own generated code needs module-
 * level scaffolding no widget tree or class body can express, e.g.
 * keyboard_ui.fl's `KeyBtn`/`ShiftBtn` structs and the `keyButtons_`/
 * `shiftButtons_` registration arrays its buttons' own `setup` blocks
 * push into. Structurally identical to `CodeNode` (raw text captured
 * generically into `instanceName`, same mechanism every node uses) --
 * kept as its own class purely so `code_writer.d` can tell "module-scope
 * declaration" and "function-body fragment" apart when walking a
 * `.fl` file's root nodes.
 *
 * Ported from FLTK's `Decl_Node` (`fluid/nodes/Function_Node.h`/
 * `.cxx`): `visibility_`/`staticFlag_` mirror its `public_`/`static_`
 * fields (`public`/`private`/`protected`, `local`/`global`), read as
 * bare flags -- no value token follows any of them in `.fl` text, so
 * each needs its own `return true` in `readProperty()` (see
 * `fluid.function_node.FunctionNode`'s own `"private"` case for why:
 * without this, the reader's tolerant-of-unknown-properties fallback
 * eats the *next* property's name token as if it were this one's
 * value, corrupting the rest of the property list). These fields carry
 * no D-codegen meaning at all (this port has no header/`.cxx` visibility
 * split to preserve) -- they exist purely so a `decl {}` node round-
 * trips through `project_writer.d`'s save path without silently
 * dropping flags the `.fl` author wrote (e.g. `terminal.fl`'s `decl
 * {...} { comment {...} private local }`).
 */
module fluid.decl_node;

import fluid.node;
import fluid.project_reader : Reader;

class DeclNode : Node
{
    /// 0 = private, 1 = public, 2 = protected -- matches FLTK's
    /// `Decl_Node::public_` encoding exactly, including its default.
    int visibility_ = 0;

    /// true = "local" (static), false = "global". Matches FLTK's
    /// `Decl_Node::static_` default of 1 (local).
    bool staticFlag_ = true;

    override bool readProperty(Reader r, string name)
    {
        switch (name)
        {
        case "public": visibility_ = 1; return true;
        case "private": visibility_ = 0; return true;
        case "protected": visibility_ = 2; return true;
        case "local": staticFlag_ = true; return true;
        case "global": staticFlag_ = false; return true;
        default: return super.readProperty(r, name);
        }
    }
}
