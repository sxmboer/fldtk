/**
 * MergeBack: merging edits made directly in a generated `.d` file back
 * into the `.fl` project that produced it. Ported from FLTK's
 * `fluid/proj/mergeback.cxx`/`.h` (`fluid::proj::Mergeback`) plus the
 * `fluid::CRC32` class from `fluid/io/Code_Writer.cxx`.
 *
 * How it works. When a project has `ProjectSettings.writeMergebackData`
 * set, every node carries a unique `uid` in the `.fl` file, and
 * `fluid.code_writer.Writer` brackets each editable block of generated
 * code -- a `code {}` fragment, a widget callback, a menu-item callback
 * -- with two tag lines (`formatTag()`). A tag line is a `//` comment
 * holding the block kind, the owning node's `uid`, and a CRC32 of all
 * generated text since the previous tag. `Mergeback` re-reads a
 * generated file, recomputes the CRC of each stretch between tags, and
 * compares it with the tag that follows it:
 *
 *  - a mismatch in an editable block means the user edited it; if the
 *    block's node still exists in the project, the edited text can
 *    replace the node's own text (`apply()`);
 *  - a mismatch in a stretch of ordinary generated code is a structural
 *    change, which cannot be merged back and is only reported.
 *
 * The CRC ignores leading whitespace, collapses runs of whitespace and
 * skips `\r` (`Crc32.update()`), so re-indenting a block is not an edit.
 *
 * Differences from FLTK:
 *  - Editable blocks are written at the indentation of the code around
 *    them, and each tag line is indented the same way; the reader
 *    removes that indentation (`unindentBlock()`) instead of FLTK's
 *    fixed two spaces.
 *  - Menu-item callbacks can be merged back. FLTK looks the node up
 *    with `is_true_widget()`, which is false for menu items, so every
 *    menu callback edit is reported as "no node found" there; here any
 *    `WidgetNode`, menu items included, is a valid target.
 *  - The whole code file is read into a string instead of walked with
 *    `fgets()`/`ftell()`, and a block's end is the start of the tag
 *    line that closes it (FLTK's `block_end` keeps a stale value
 *    when a block has no lines).
 *  - The "last code file written for this project" record lives in the
 *    `fldtk`/`fluid-build` preferences, not FLTK's `fltk.org`/
 *    `fluid-build`.
 */
module fluid.mergeback;

import std.file : exists, read;
import std.format : format;
import std.string : indexOf, startsWith;
import std.zlib : zlibCrc32 = crc32;

import fl.ask : choice, message;
import fl.preferences : Preferences, rootUserL;

import fluid.code_node : CodeNode;
import fluid.node : Node;
import fluid.widget_node : WidgetNode;

/// Kind of code block a tag line refers to. FLTK's `Mergeback::Tag`;
/// the numeric values are part of the tag encoding.
enum Tag : ubyte
{
    generic = 0,
    code,
    menuCallback,
    widgetCallback,
    unused_,
}

/// What `Mergeback.mergeBack()` should do. FLTK's `Mergeback::Task`.
enum Task
{
    /// Report findings as bits of the return value only.
    analyse,
    /// Report findings in a dialog and let the user merge or cancel.
    interactive,
    /// Merge everything back without asking.
    apply,
    /// Merge back only if there are no conflicts.
    applyIfSafe,
}

/// CRC32 over a whitespace-normalised view of the text: leading
/// whitespace of every line is ignored, other runs of whitespace count
/// as one space, `\r` is skipped. Ported from `fluid::CRC32`, and
/// matches it byte for byte so the value stored in a tag is the value
/// the reader recomputes.
struct Crc32
{
    private uint crc_;
    private bool multiSpace_;
    private bool lineStart_ = true;

    uint value() const { return crc_; }

    void reset()
    {
        crc_ = 0;
        multiSpace_ = false;
        lineStart_ = true;
    }

    /// Adds `text` to the running checksum; may be called repeatedly,
    /// each call continues where the last stopped.
    void update(const(char)[] text)
    {
        ubyte[] out_;
        size_t i = 0;
        immutable n = text.length;
        scope (exit)
            if (out_.length) crc_ = zlibCrc32(crc_, out_);
        while (i < n)
        {
            char c = text[i];
            if (lineStart_)
            {
                while (i < n && isAsciiSpace(text[i])) i++;
                if (i == n) return;
                lineStart_ = false;
                c = text[i];
            }
            if (c == '\n') lineStart_ = true;
            if (c == '\r') { i++; continue; }
            if (multiSpace_)
            {
                if (isAsciiSpace(c)) { i++; continue; }
                multiSpace_ = false;
            }
            else if (isAsciiSpace(c))
            {
                multiSpace_ = true;
                out_ ~= cast(ubyte) ' ';
                i++;
                continue;
            }
            out_ ~= cast(ubyte) c;
            i++;
        }
    }

    /// CRC of `text` as one block. FLTK's `CRC32::block()`.
    static uint block(const(char)[] text)
    {
        Crc32 c;
        c.update(text);
        return c.value;
    }
}

private bool isAsciiSpace(char c)
{
    return c == ' ' || (c >= '\t' && c <= '\r');
}

// The tag marker starts with U+FB02 (a "fl" ligature), which does not
// occur in ordinary source text.
private enum tagMarker = "//ﬂ ";
private enum tagEnd = " ﬂ//\n";
private enum upTriangle = "▲";    // marks: the text above can be edited
private enum downTriangle = "▼";  // marks: the text below can be edited
private static immutable string[8] trichar = ["--", "-~", "~-", "~~", "-=", "=-", "~=", "=~"];
private static immutable string[4] tagLabel = ["----------", "-- code --", " callback ", " callback "];

/// Formats one tag line, including the trailing newline. Ported from
/// `Mergeback::format_tag()`. `prevType` is the kind of the block that
/// ends at this tag, `nextType` the kind of the block that starts
/// after it, `uid` the node owning the block that ends here, `crc` the
/// CRC of the block that ends here.
string formatTag(Tag prevType, Tag nextType, ushort uid, uint crc)
{
    string decoration;
    if (prevType != Tag.generic) decoration ~= upTriangle;
    if (prevType != Tag.generic && nextType != Tag.generic) decoration ~= "/";
    if (nextType != Tag.generic) decoration ~= downTriangle;

    string result = tagMarker ~ decoration ~ " ";
    uint word = ((cast(uint) prevType << 16) & 0x00ff0000) | uid;
    for (int i = 30; i >= 0; i -= 3)
        result ~= trichar[(word >> i) & 7];
    result ~= tagLabel[cast(uint) nextType % 4];
    for (int i = 30; i >= 0; i -= 3)
        result ~= trichar[(crc >> i) & 7];
    result ~= " " ~ decoration ~ tagEnd;
    return result;
}

/// Decodes 22 characters of `-`, `~` and `=` into a 32 bit value.
/// Ported from `Mergeback::decode_trichar32()`.
private uint decodeTrichar32(const(char)[] text)
{
    uint word = 0;
    size_t p = 0;
    for (int i = 30; i >= 0; i -= 3)
    {
        if (p + 1 >= text.length) break;
        char a = text[p++];
        char b = text[p++];
        uint oct = 0;
        if (a == '-')
            oct = b == '~' ? 1 : b == '=' ? 4 : 0;
        else if (a == '~')
            oct = b == '~' ? 3 : b == '-' ? 2 : b == '=' ? 6 : 0;
        else if (a == '=')
            oct = b == '~' ? 7 : b == '-' ? 5 : 0;
        word |= oct << i;
    }
    return word;
}

/// Index just past the tag marker in `line`, or -1 if the line has none.
private ptrdiff_t findMergebackTag(const(char)[] line)
{
    auto p = line.indexOf(tagMarker);
    return p < 0 ? -1 : p + tagMarker.length;
}

/// Reads the block kind, node id and CRC out of a tag line, given the
/// text after the marker. Ported from `Mergeback::read_tag()`.
private bool readTag(const(char)[] tag, out Tag prevType, out ushort uid, out uint crc)
{
    if (tag.length && tag[0] == ' ') tag = tag[1 .. $];
    if (tag.startsWith(upTriangle)) tag = tag[upTriangle.length .. $];
    if (tag.length && tag[0] == '/') tag = tag[1 .. $];
    if (tag.startsWith(downTriangle)) tag = tag[downTriangle.length .. $];
    if (tag.length && tag[0] == ' ') tag = tag[1 .. $];
    // 22 characters for the first word, 10 for the label, 22 for the second.
    if (tag.length < 32 + 22) return false;
    uint w1 = decodeTrichar32(tag[0 .. 22]);
    uint w2 = decodeTrichar32(tag[32 .. 32 + 22]);
    prevType = cast(Tag) ((w1 >> 16) & 0xff);
    uid = cast(ushort) (w1 & 0xffff);
    crc = w2;
    return true;
}

/// Removes up to `indent.length` leading spaces or tabs from every
/// line of `block`. Ported from `Mergeback::unindent()`, which removes
/// a fixed two.
string unindentBlock(string block, size_t indent)
{
    string result;
    size_t i = 0;
    while (i < block.length)
    {
        size_t skipped = 0;
        while (skipped < indent && i < block.length && (block[i] == ' ' || block[i] == '\t'))
        {
            i++;
            skipped++;
        }
        auto nl = block.indexOf('\n', i);
        size_t end = nl < 0 ? block.length : nl + 1;
        result ~= block[i .. end];
        i = end;
    }
    return result;
}

/// One pass over a generated code file: finds tag lines, recomputes the
/// CRC of the stretch before each, and hands `(tagType, uid, tagCrc,
/// codeCrc, blockStart, blockEnd, indent)` to `visit`. Returns false if
/// a tag line could not be read; `lineNo` is then the offending line.
private bool scanTags(string code, ref int lineNo,
    scope void delegate(Tag type, ushort uid, uint tagCrc, uint codeCrc,
        size_t blockStart, size_t blockEnd, size_t indent) visit)
{
    Crc32 crc;
    size_t blockStart = 0;
    size_t pos = 0;
    lineNo = 0;
    while (pos < code.length)
    {
        auto nl = code.indexOf('\n', pos);
        size_t end = nl < 0 ? code.length : nl + 1;
        string line = code[pos .. end];
        lineNo++;
        auto after = findMergebackTag(line);
        if (after < 0)
            crc.update(line);
        else
        {
            Tag type;
            ushort uid;
            uint tagCrc;
            if (!readTag(line[after .. $], type, uid, tagCrc) || type >= Tag.unused_)
                return false;
            // Whitespace in front of the marker is the indentation the
            // writer gave the block.
            size_t indent = after - tagMarker.length;
            foreach (ch; line[0 .. indent])
                if (ch != ' ' && ch != '\t') { indent = 0; break; }
            visit(type, uid, tagCrc, crc.value, blockStart, pos, indent);
            crc.reset();
            blockStart = end;
        }
        pos = end;
    }
    return true;
}

/// `code {}` fragments and callbacks store their text without a
/// trailing newline; a block read back from the file has one.
private string stripOneNewline(string s)
{
    if (s.length >= 2 && s[$ - 2 .. $] == "\r\n") return s[0 .. $ - 2];
    if (s.length >= 1 && s[$ - 1] == '\n') return s[0 .. $ - 1];
    return s;
}

/// Compares a generated code file against a project and merges edits
/// back. Ported from `fluid::proj::Mergeback`.
class Mergeback
{
    /// The project's node forest to look nodes up in and merge into.
    Node[] roots;

    /// Called once, right before `apply()` changes any node -- the
    /// caller records an undo checkpoint here.
    void delegate() beforeApply;

    /// Set if a tag line could not be read; `lineNo` is its line.
    bool tagError;
    int lineNo;
    /// Edited editable blocks found in the code file.
    int numChangedCode;
    /// Edits outside editable blocks; these cannot be merged back.
    int numChangedStructure;
    /// Edited blocks whose node is not in the project.
    int numUidNotFound;
    /// Edited blocks whose node also changed in the project.
    int numPossibleOverride;

    this(Node[] roots)
    {
        this.roots = roots;
    }

    private Node findByUid(ushort uid)
    {
        Node found;
        void walk(Node[] nodes)
        {
            foreach (n; nodes)
            {
                if (found !is null) return;
                if (n.uid == uid) { found = n; return; }
                walk(n.children);
            }
        }
        walk(roots);
        return found;
    }

    /// The node text a block of `type` maps to, or null (via `ok`) if
    /// `n` is not a valid target for it.
    private bool textOf(Node n, Tag type, out string text)
    {
        if (type == Tag.code)
        {
            if (auto cn = cast(CodeNode) n) { text = cn.instanceName; return true; }
            return false;
        }
        if (auto wn = cast(WidgetNode) n) { text = wn.callback; return true; }
        return false;
    }

    private void setText(Node n, Tag type, string text)
    {
        if (type == Tag.code)
            n.instanceName = text;
        else
            n.callback = text;
    }

    /// Analyses `code` and fills in the `num*` counters. Returns -1 if
    /// a tag could not be read, otherwise 0. Ported from
    /// `Mergeback::analyse()`.
    int analyse(string code)
    {
        tagError = false;
        numChangedCode = 0;
        numChangedStructure = 0;
        numUidNotFound = 0;
        numPossibleOverride = 0;
        bool ok = scanTags(code, lineNo, (type, uid, tagCrc, codeCrc, blockStart, blockEnd, indent) {
            if (codeCrc == tagCrc) return;
            if (type == Tag.generic)
            {
                numChangedStructure++;
                return;
            }
            string text;
            if (!textOf(findByUid(uid), type, text))
            {
                numUidNotFound++;
                numChangedCode++;
                return;
            }
            uint projectCrc = Crc32.block(text ~ "\n");
            // Same CRC as the project: this edit was already merged.
            if (projectCrc == codeCrc) return;
            numChangedCode++;
            // The project's text differs from what the file was
            // generated from, so merging overwrites a project edit.
            if (projectCrc != tagCrc) numPossibleOverride++;
        });
        if (!ok) { tagError = true; return -1; }
        return 0;
    }

    /// Merges every edited block in `code` into the project. Returns -1
    /// if a tag could not be read, 0 if nothing changed, 1 if the
    /// project changed. Ported from `Mergeback::apply()`.
    int apply(string code)
    {
        tagError = false;
        bool changed = false;
        bool notified = false;
        bool ok = scanTags(code, lineNo, (type, uid, tagCrc, codeCrc, blockStart, blockEnd, indent) {
            if (codeCrc == tagCrc || type == Tag.generic) return;
            auto node = findByUid(uid);
            string text;
            if (!textOf(node, type, text)) return;
            if (Crc32.block(text ~ "\n") == codeCrc) return;
            if (!notified && beforeApply !is null)
            {
                beforeApply();
                notified = true;
            }
            setText(node, type, stripOneNewline(unindentBlock(code[blockStart .. blockEnd], indent)));
            changed = true;
        });
        if (!ok) { tagError = true; return -1; }
        return changed ? 1 : 0;
    }

    /// Tells the user what the analysis found and offers to merge.
    /// Returns 1 if the user wants to merge, 0 if there is nothing to
    /// merge (no dialog), -1 if the user cancels or an issue was shown.
    /// Ported from `Mergeback::ask_user_to_merge()`.
    int askUserToMerge(string codeFilename, string projFilename)
    {
        if (tagError)
        {
            message(format("Comparing\n  \"%s\"\nto\n  \"%s\"\n\n"
                ~ "MergeBack found an error in line %d while reading tags\n"
                ~ "from the source code. Merging code back is not possible.",
                codeFilename, projFilename, lineNo));
            return -1;
        }
        if (!numChangedCode && !numChangedStructure)
            return 0;
        if (numChangedStructure && !numChangedCode)
        {
            message(format("Comparing\n  \"%1$s\"\nto\n  \"%2$s\"\n\n"
                ~ "MergeBack found %3$d modifications in the project structure\n"
                ~ "of the source code. These kind of changes can not be\n"
                ~ "merged back and will be lost when the source code is\n"
                ~ "generated again from the open project.",
                codeFilename, projFilename, numChangedStructure));
            return -1;
        }
        string msg = "Comparing\n  \"%1$s\"\nto\n  \"%2$s\"\n\n"
            ~ "MergeBack found %3$d modifications in the source code.";
        if (numPossibleOverride)
            msg ~= "\n\nWARNING: %6$d of these modified blocks appear to also have\n"
                ~ "changed in the project. Merging will override changes in\n"
                ~ "the project with changes from the source code file.";
        if (numUidNotFound)
            msg ~= "\n\nWARNING: no Node can be found for %4$d of these\n"
                ~ "modifications and they can not be merged back.";
        if (!numPossibleOverride && !numUidNotFound)
            msg ~= "\nMerging these changes back appears to be safe.";
        if (numChangedStructure)
            msg ~= "\n\nWARNING: %5$d modifications were found in the project\n"
                ~ "structure. These kind of changes can not be merged back\n"
                ~ "and will be lost when the source code is generated again\n"
                ~ "from the open project.";
        if (numChangedCode == numUidNotFound)
        {
            message(format(msg, codeFilename, projFilename, numChangedCode,
                numUidNotFound, numChangedStructure, numPossibleOverride));
            return -1;
        }
        msg ~= "\n\nClick Cancel to abort the MergeBack operation.\n"
            ~ "Click Merge to merge all code changes back into\n"
            ~ "the open project.";
        int c = choice(format(msg, codeFilename, projFilename, numChangedCode,
            numUidNotFound, numChangedStructure, numPossibleOverride), "Cancel", "Merge", null);
        return c == 0 ? -1 : 1;
    }

    /// Runs `task` against the code file `codeFilename`. Returns -2 if
    /// the file does not exist, -1 if a tag could not be read (or, for
    /// `applyIfSafe`, there were conflicts), otherwise the task's
    /// result: for `analyse` a bit field (1 structure changed, 2 code
    /// changed, 4 a node was not found, 8 a project edit would be
    /// overridden); for the others 0 if the project stays unchanged and
    /// 1 if changes were merged. Ported from `Mergeback::merge_back()`.
    int mergeBack(string codeFilename, string projFilename, Task task)
    {
        if (!exists(codeFilename)) return -2;
        string code = cast(string) read(codeFilename);
        int ret = 0;
        if (task == Task.analyse)
        {
            analyse(code);
            if (tagError) return -1;
            if (numChangedStructure) ret |= 1;
            if (numChangedCode) ret |= 2;
            if (numUidNotFound) ret |= 4;
            if (numPossibleOverride) ret |= 8;
            return ret;
        }
        if (task == Task.interactive)
        {
            analyse(code);
            ret = askUserToMerge(codeFilename, projFilename);
            if (ret != 1) return ret;
            task = Task.apply;
        }
        if (task == Task.applyIfSafe)
        {
            analyse(code);
            if (tagError || numChangedStructure || numPossibleOverride) return -1;
            if (numChangedCode == 0) return 0;
            task = Task.apply;
        }
        // Task.apply: report 1 even if nothing changed, so the caller
        // shows no "no modifications" message after the user said Merge.
        apply(code);
        return 1;
    }
}

/// Preferences holding, per project file, the path of the code file
/// most recently written for it. FLTK's `fltk.org`/`fluid-build`
/// records, under this port's own vendor name.
private Preferences buildRecords()
{
    return new Preferences(rootUserL, "fldtk", "fluid-build");
}

private string normaliseSlashes(string path)
{
    string r;
    foreach (c; path)
        r ~= c == '\\' ? '/' : c;
    return r;
}

/// Records that `codeFile` was generated from `projectFile`, so a
/// later MergeBack finds the code even when a build tool wrote it
/// somewhere other than next to the project. Ported from
/// `Code_Writer::remember_mergeback_paths()`.
void rememberCodePath(string projectFile, string codeFile)
{
    auto root = buildRecords();
    auto path = new Preferences(root, normaliseSlashes(projectFile));
    path.set("code", codeFile);
    root.flush();
}

/// The code file recorded by `rememberCodePath()` for `projectFile`, or
/// an empty string.
string rememberedCodePath(string projectFile)
{
    auto root = buildRecords();
    auto path = new Preferences(root, normaliseSlashes(projectFile));
    string code;
    path.get("code", code, "");
    return code;
}

unittest
{
    // CRC ignores indentation, whitespace runs and carriage returns, and
    // is sensitive to real content.
    assert(Crc32.block("foo();\n") == Crc32.block("    foo();\r\n"));
    assert(Crc32.block("a  =\t1;\n") == Crc32.block("a = 1;\n"));
    assert(Crc32.block("foo();\n\n\n") == Crc32.block("foo();\n"));
    assert(Crc32.block("foo();\n") != Crc32.block("bar();\n"));
    // Incremental updates equal one update.
    Crc32 a;
    a.update("  x = 1;\n  y");
    a.update(" = 2;\n");
    assert(a.value == Crc32.block("x = 1;\ny = 2;\n"));
}

unittest
{
    // Tag lines round-trip, and the decoration follows the block kinds.
    string t = formatTag(Tag.code, Tag.generic, 0xbeef, 0xdeadbeef);
    assert(t.startsWith("//ﬂ ▲ "));
    assert(t[$ - 1] == '\n');
    auto after = findMergebackTag(t);
    assert(after > 0);
    Tag type; ushort uid; uint crc;
    assert(readTag(t[after .. $], type, uid, crc));
    assert(type == Tag.code && uid == 0xbeef && crc == 0xdeadbeef);

    string opening = formatTag(Tag.generic, Tag.widgetCallback, 0, 12345);
    assert(opening.startsWith("//ﬂ ▼ "));
    assert(readTag(opening[findMergebackTag(opening) .. $], type, uid, crc));
    assert(type == Tag.generic && uid == 0 && crc == 12345);

    string both = formatTag(Tag.menuCallback, Tag.widgetCallback, 1, 2);
    assert(both.startsWith("//ﬂ ▲/▼ "));

    // A truncated tag is rejected.
    assert(!readTag("▲ --~~", type, uid, crc));
}

unittest
{
    assert(unindentBlock("    a\n      b\n\n    c\n", 4) == "a\n  b\n\nc\n");
    assert(unindentBlock("  a\n    b\n", 4) == "a\nb\n");
    assert(unindentBlock("\ta\n", 1) == "a\n");
}

unittest
{
    // apply()/analyse() against a hand-built code file: an edited code
    // block is merged, an unedited one is left alone, structural edits
    // are counted but not merged, an unknown uid is reported.
    import fluid.node : Node;

    auto edited = new CodeNode();
    edited.instanceName = "foo();";
    edited.uid = 11;
    auto untouched = new CodeNode();
    untouched.instanceName = "bar();";
    untouched.uid = 12;

    string block(Tag kind, ushort uid, string body_, string before)
    {
        Crc32 pre;
        pre.update(before);
        Crc32 blk;
        blk.update(body_);
        return before ~ formatTag(Tag.generic, kind, 0, pre.value)
            ~ body_ ~ formatTag(kind, Tag.generic, uid, blk.value);
    }

    string generated = block(Tag.code, 11, "    foo();\n", "module x;\n")
        ~ block(Tag.code, 12, "    bar();\n", "// between\n");

    auto mb = new Mergeback([edited, untouched]);
    assert(mb.analyse(generated) == 0);
    assert(mb.numChangedCode == 0 && mb.numChangedStructure == 0);
    assert(mb.apply(generated) == 0);
    assert(edited.instanceName == "foo();");

    // Edit the first block in the file.
    string editedFile = generated.replace1("    foo();\n", "    foo();\n    baz();\n");
    assert(mb.analyse(editedFile) == 0);
    assert(mb.numChangedCode == 1 && mb.numChangedStructure == 0);
    assert(mb.numUidNotFound == 0 && mb.numPossibleOverride == 0);
    bool notified;
    mb.beforeApply = () { notified = true; };
    assert(mb.apply(editedFile) == 1);
    assert(notified);
    assert(edited.instanceName == "    foo();\n    baz();");
    assert(untouched.instanceName == "bar();");
    // Applied again: already merged, nothing left to do.
    assert(mb.analyse(editedFile) == 0 && mb.numChangedCode == 0);

    // A project edit made after generation is flagged as an override.
    untouched.instanceName = "changed();";
    string editedBar = generated.replace1("    bar();\n", "    other();\n");
    mb.analyse(editedBar);
    assert(mb.numChangedCode == 1 && mb.numPossibleOverride == 1);

    // An edit between tags is structural and is never merged.
    string structural = generated.replace1("module x;", "module y;");
    mb.analyse(structural);
    assert(mb.numChangedStructure == 1 && mb.numChangedCode == 0);

    // A tag for a node that no longer exists.
    auto orphan = new Mergeback([]);
    orphan.analyse(editedFile);
    assert(orphan.numUidNotFound == 1 && orphan.numChangedCode == 1);

    // A damaged tag line is an error.
    string damaged = "x\n//ﬂ ▼ ----\n";
    assert(mb.analyse(damaged) == -1 && mb.tagError && mb.lineNo == 2);
}

private string replace1(string s, string from, string to)
{
    auto i = s.indexOf(from);
    assert(i >= 0);
    return s[0 .. i] ~ to ~ s[i + from.length .. $];
}

unittest
{
    // rememberCodePath()/rememberedCodePath() round-trip through the
    // preferences file; run against a private config directory.
    import std.file : mkdirRecurse, rmdirRecurse, tempDir;
    import std.path : buildPath;
    import std.process : environment;

    string dir = buildPath(tempDir(), "fluid_mergeback_unittest");
    mkdirRecurse(dir);
    scope (exit) rmdirRecurse(dir);
    string saved = environment.get("XDG_CONFIG_HOME");
    environment["XDG_CONFIG_HOME"] = dir;
    scope (exit)
    {
        if (saved is null) environment.remove("XDG_CONFIG_HOME");
        else environment["XDG_CONFIG_HOME"] = saved;
    }

    assert(rememberedCodePath("/tmp/none/proj.fl") == "");
    rememberCodePath("/tmp/a/proj.fl", "/tmp/build/out.d");
    rememberCodePath("/tmp/b/proj.fl", "/tmp/other/out.d");
    assert(rememberedCodePath("/tmp/a/proj.fl") == "/tmp/build/out.d");
    assert(rememberedCodePath("/tmp/b/proj.fl") == "/tmp/other/out.d");
    rememberCodePath("/tmp/a/proj.fl", "/tmp/build/newer.d");
    assert(rememberedCodePath("/tmp/a/proj.fl") == "/tmp/build/newer.d");
}
