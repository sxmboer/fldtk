/*
 * A `declblock { ... }` node -- wraps its own children (`decl {}`/
 * `data {}` nodes, or another nested `declblock {}`) in a "before"/
 * "after" pair of literal D text, e.g. `"version (Windows)"` around a
 * group of Windows-only declarations. Ported from FLTK's
 * `DeclBlock_Node` (`fluid/nodes/Function_Node.h`/`.cxx`):
 * `instanceName` holds the "before" text (FLTK's `name()`),
 * `afterText` the "after" text (FLTK's `end_code()`, read/written
 * via the `"after"` key).
 *
 * **Deviates from FLTK on purpose: this class's own writer
 * (`code_writer.d`'s `writeDeclBlockNode()`) injects real braces around
 * its children and indents them one level, exactly matching
 * `fluid.code_block_node.CodeBlockNode`'s own shape -- unlike FLTK's
 * `DeclBlock_Node::write_code1()`/`write_code2()`, which emit `name()`/
 * `end_code()` completely raw, no braces at all.** Confirmed necessary,
 * not just simpler, while first drafting this class: FLTK's own
 * design only works because its default content is a bare C
 * preprocessor guard (`"#if 1"` / `"#endif"`), which needs no braces to
 * begin with; D's nearest equivalent conditional-compilation constructs
 * (`version(...)`/`static if(...)`) are real block statements that
 * *do* need a matching `{`/`}`. Letting the `.fl` author supply an
 * unmatched brace directly inside `instanceName`/`afterText` (the
 * originally-planned approach) turns out to be flatly impossible in
 * this dialect's own `.fl` grammar, not just awkward: every property
 * *value* (including the leading braced block every node type captures
 * generically into `instanceName`) is read by `Reader.readBracedContent()`,
 * which requires `{`/`}` to balance back to depth zero *within that one
 * value* before the value ends -- a lone unmatched `{` just keeps the
 * reader consuming everything after it (the next property, the
 * children block, ...) as more "value" text, hunting for a `}` that
 * never brings it back to zero, until parsing breaks somewhere else
 * entirely (a real, reachable `AssertError`, not just a theoretical
 * concern). So
 * `instanceName` for a `declblock {}` in this dialect is always a bare
 * condition with no trailing brace (`"version (Windows)"`), same as
 * `CodeBlockNode`'s own `"if (test())"`.
 *
 * `write_map_` mirrors FLTK's `write_map()` bitmask (`CODE_IN_
 * HEADER`=1/`CODE_IN_SOURCE`=2/`STATIC_IN_HEADER`=4/`STATIC_IN_SOURCE`=8)
 * purely for `.fl` round-trip parity, matching `fluid.decl_node.DeclNode`'s
 * own established precedent for `visibility_`/`staticFlag_`: this
 * dialect has no header/`.cxx` split and no separate "static" emission
 * phase, so none of the four bits affect codegen at all -- they exist
 * only so a hand-authored `.fl` file's `map`/`public` properties survive
 * a load-then-save round trip instead of being silently dropped.
 */
module fluid.decl_block_node;

import fluid.node;
import fluid.project_reader : Reader;
import std.conv : to, ConvException;

class DeclBlockNode : Node
{
    enum codeInHeader = 1;
    enum codeInSource = 2;
    enum staticInHeader = 4;
    enum staticInSource = 8;

    /// Text after all children -- FLTK's `end_code()`. `instanceName`
    /// (the generic captured leading-brace text) holds the "before" text.
    string afterText;

    /// See this module's own doc comment -- round-trip only, no
    /// codegen meaning. Matches FLTK's own default
    /// (`write_map_ = CODE_IN_SOURCE`).
    int writeMap_ = codeInSource;

    override bool canHaveChildren() const { return true; }

    override bool readProperty(Reader r, string name)
    {
        switch (name)
        {
        // FLTK's own deprecated shorthand for "this block is also
        // public" -- kept only so an old-style `.fl` file round-trips
        // without losing the flag, matching `DeclBlock_Node::
        // read_property()`'s own `"public"`/`"protected"` cases exactly
        // (the latter is a documented FLTK no-op -- `// ` with an
        // empty body -- ported as-is, not silently dropped).
        case "public": writeMap_ |= codeInHeader; return true;
        case "protected": return true;
        case "map":
            try writeMap_ = to!int(r.readValue());
            catch (ConvException) writeMap_ = codeInSource;
            return true;
        case "after": afterText = r.readValue(); return true;
        default: return super.readProperty(r, name);
        }
    }
}
