/*
 * A `data name { filename {path} }` node -- the contents of an
 * external file (an image, in every real `.fl` file so far) inlined
 * into the generated source. Ported from FLTK's `Data_Node :
 * public Decl_Node` (`fluid/nodes/Function_Node.h`/`.cxx`) -- see
 * `fluid.decl_node.DeclNode` for the shared public/private/protected/
 * local/global visibility flags this class inherits (they carry no
 * D-codegen meaning here, same as for a plain `decl {}`, but still
 * need to parse/round-trip correctly -- this port has no header/`.cxx`
 * split for "in source file only"/"in header file only"/etc. to mean
 * anything, so the whole FLTK "Visibility:" choice built on top of
 * them stays deliberately un-placed in the property panel).
 *
 * Needed by `checkers_pieces.fl` (`source/test/`), whose entire root
 * node list is four sibling `data` nodes with no enclosing `Function`/
 * `class` at all -- see `code_writer.d`'s `generate()` for how a bare
 * `data` root is handled alongside `decl`/`class`/`Function` roots.
 *
 * **Storage format**: FLTK's own "Output:" `Fl_Choice` offers 6
 * values (`output_format_`, `0`..`5`: binary array / text `const
 * char*` / compressed binary / binary `std::vector` / text
 * `std::string` / compressed `std::vector`) -- really two independent
 * axes tangled into one enum for C++'s sake: raw-array-vs-`std::vector`
 * (a pure STL-container choice with no D equivalent worth inventing --
 * a D `ubyte[]`/`string` already *is* what `std::vector` reaches for)
 * crossed with text-vs-binary and compressed-vs-not (both genuinely
 * useful regardless of language). Ported as those two real, orthogonal
 * flags instead of FLTK's 6-way enum: `asString` (text vs binary)
 * and `compressedFlag` -- independently combinable, unlike FLTK's
 * own menu (which has no "compressed text" entry at all; nothing about
 * zlib-decompressing into a `string` afterward is actually harder than
 * decompressing into a `ubyte[]`, so this port doesn't reproduce that
 * gap). `.fl`-text round-trip reuses FLTK's own "textmode"/
 * "compressed" bare-flag spellings (real FLTK keywords already,
 * just no longer forced mutually exclusive) for reading and writing;
 * `std_binary`/`std_textmode`/`std_compressed` (FLTK's 3 vector-
 * flavored values) are still accepted on read for compatibility with a
 * real FLTK-authored `.fl` file, collapsing onto the same two
 * flags their non-vector counterparts do, but this port only ever
 * writes the two plain forms.
 */
module fluid.data_node;

import fluid.decl_node;
import fluid.project_reader : Reader;

class DataNode : DeclNode
{
    /// Path to the external file, relative to the `.fl` file's own
    /// directory (matching FLTK's `Fluid.proj.enter_project_dir()`
    /// convention) -- e.g. "pixmaps/black_checker.png".
    string filename;

    /// Storage format -- see this module's own top comment. `false`
    /// (the default) emits `immutable ubyte[]`, matching every `data`
    /// node in this project's own `.fl` files today; `true` emits a
    /// `string` literal instead (UTF-8, matching FLTK's own
    /// "textmode").
    bool asString;

    /// zlib-compresses the embedded data at codegen time, decompressed
    /// once at runtime (`code_writer.d`'s own `writeDataNode()`) --
    /// independent of `asString`, see this module's own top comment.
    bool compressedFlag;

    override bool readProperty(Reader r, string name)
    {
        switch (name)
        {
        case "filename":
            filename = r.readValue();
            return true;
        case "textmode":
        case "std_textmode":
            asString = true;
            return true;
        case "compressed":
        case "std_compressed":
            compressedFlag = true;
            return true;
        case "std_binary":
            // The vector-vs-array axis has no D equivalent (see this
            // module's own top comment) -- collapses onto the same
            // plain-binary default `output_format_ == 0` already is.
            return true;
        default:
            return super.readProperty(r, name);
        }
    }
}
