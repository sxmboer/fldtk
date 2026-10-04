/*
 * `Node` tree -> `.fl` text -- the missing direction from `project_reader.d`
 * (which only reads `.fl` text -> `Node` tree), needed for the
 * interactive editor's real "Save"/"Save As". Ported in spirit from
 * FLTK's `Fd_Project_Writer` (`fluid/io/Project_Writer.h`/`.cxx`),
 * but deliberately GNU-style brace formatting rather than reproducing
 * FLTK's own K&R-ish output style verbatim -- an explicit user
 * decision. Every node's property group and children group each open
 * with a `{` on its own line, indented one level beyond the node's
 * `Type name` header, with the group's contents one level deeper still
 * and the closing `}` aligned with its opening `{`:
 *
 *     Group {}
 *       {
 *         xywh {15 15 80 128}
 *       }
 *       {
 *         Button {}
 *           {
 *             label {b&1}
 *           }
 *       }
 *
 * (the same convention `FLUID_DIALECT.md` documents for hand-authored
 * code bodies, applied to the file's own structure). One-line
 * `name {value}` properties stay inline, and only the file structure is
 * laid out this way -- multi-line values (code bodies) are content and
 * are written through untouched.
 *
 * Scope: round-trips only the field set `Node`/`WidgetNode`/
 * `WindowNode`/`GroupNode` (`project_reader.d`'s actual parse layer) already
 * recognize today -- no new `.fl` properties invented here. Also
 * writes back fields Phase 1's own property panel can't edit yet
 * (`labelfont`, `align`, ...) so a load -> edit-two-fields -> save
 * cycle doesn't silently drop them.
 *
 * Known, deliberate lossiness: `Node.readProperty()`/`WidgetNode.
 * readProperty()` already silently drop anything they don't
 * recognize, and one *recognized* bare flag (`visible`) is parsed as a
 * pure no-op with no backing field at all (see `widget_node.d`'s own
 * doc comment) -- it can't be recovered here, since nothing captured
 * it on the way in. `noborder` has a real `WindowNode.noBorder_` backing field
 * (and this file's own emission line, right below), wired to the "Border"
 * light button in `widget_panel.d`
 * -- it round-trips like any other window
 * flag. The honest round-trip test for this class is "load -> save
 * -> load again -> the two in-memory Node trees agree field-by-field,"
 * not a byte-diff against arbitrary hand-authored `.fl` text.
 */
module fluid.project_writer;

import std.array : Appender, appender, replace;
import std.format : format;

import fluid.node : Node, Access, ensureUniqueUids;
import fluid.project_settings : ProjectSettings;
import fluid.widget_node : WidgetNode;
import fluid.window_node : WindowNode;
import fluid.widget_class_node : WidgetClassNode;
import fluid.group_node : GroupNode;
import fluid.function_node : FunctionNode;
import fluid.class_node : ClassNode;
import fluid.decl_node : DeclNode;
import fluid.decl_block_node : DeclBlockNode;
import fluid.data_node : DataNode;
import fluid.code_block_node : CodeBlockNode;
import fluid.comment_node : CommentNode;
import fluid.grid_node : GridNode, GridCellInfo;
import fluid.flex_node : FlexNode;
import fluid.menu_item_node : MenuItemNode;
import fluid.i18n : I18nSettings, I18nType;
import fluid.layout_suite : LayoutList;
import fluid.shell_command : ShellCommand, ToolStore, writeShellCommandsBlock;

final class ProjectWriter
{
    /// See `generate()`'s own `includeUid` parameter -- a per-call flag,
    /// same shape as `code_writer.d`'s `projectDir_` (set once at the
    /// top of `generate()`, read several calls deep by `writeProperties()`).
    private bool includeUid_;

    /// Inverse of `Reader.readProject()`: a forest of root `Node`s back
    /// into full `.fl` file text, including the header comment/version
    /// line every `.fl` file starts with, (when `i18n.type` isn't
    /// `I18nType.none`) the leading `i18n_*` Option lines -- ported
    /// from FLTK's `fluid::proj::I18n::write()` -- and (when at
    /// least one entry has `ToolStore.project`) the leading
    /// `shell_commands { ... }` Option block, ported from FLTK's
    /// `Fd_Shell_Command_List::write(Project_Writer*)` -- and (when
    /// `layout` is given and has something worth persisting) the
    /// leading `snap { ... }` Option block, ported from FLTK's
    /// `Layout_List::write(Project_Writer*)`. All three default to
    /// "nothing to write" (`I18nSettings.init`, an empty array, `null`)
    /// so every existing caller that never had any of these concepts to
    /// pass keeps generating byte-identical output. `layout`, unlike
    /// `shellCommands`, is the live `LayoutList` itself rather than a
    /// plain filtered array -- `Layout_List::write()` needs the *whole*
    /// list (to decide whether the block is worth emitting at all, see
    /// `LayoutList.writeToProject()`'s own doc comment) and the current
    /// selection, not just its `ToolStore.project` suites.
    ///
    /// `includeUid`: whether to write each node's own `uid` (see
    /// `fluid.node.Node.uid`'s own doc comment) as a plain `uid HHHH`
    /// property. Defaults to `false` -- it would clutter every saved
    /// `.fl` file with meaningless-looking hex ids. Its callers are
    /// `gui_main.d`'s undo/redo snapshots, which pass `true`: text
    /// that's parsed straight back in and never shown to the user or
    /// written to disk, where matching windows by real identity instead
    /// of ordinal position across the reparse is worth it. A project
    /// with MergeBack enabled (`settings.writeMergebackData`) always
    /// writes them, whatever this parameter says.
    ///
    /// `dubHeader`: the persisted counterpart of `Settings -> Project`'s
    /// "dub single-file-package header" checkbox (`code_writer.d`'s own
    /// `Writer.generate()` `dubHeader` parameter does the actual D-code
    /// emission; this just round-trips the *setting* through the `.fl`
    /// project file itself, as a plain `dub_header 1` line, matching
    /// `code_name`'s own "only write when non-default" convention).
    /// Defaults to `false` so every existing `.fl` file/caller stays
    /// byte-identical unless a project opts in.
    ///
    /// `settings`: the project's `fluid.project_settings.ProjectSettings`
    /// flags, each written as a keyword line (`use_FL_COMMAND`,
    /// `mergeback 1`) only when set, so a default `settings` leaves the
    /// output byte-identical. With `writeMergebackData` every node's
    /// `uid` is written too (after `ensureUniqueUids()`), as if
    /// `includeUid` were set.
    string generate(Node[] roots, I18nSettings i18n = I18nSettings.init,
        ShellCommand[] shellCommands = [], string codeFileName = "", LayoutList layout = null,
        bool includeUid = false, bool dubHeader = false, ProjectSettings settings = ProjectSettings.init)
    {
        includeUid_ = includeUid || settings.writeMergebackData;
        if (settings.writeMergebackData)
            ensureUniqueUids(roots);
        auto buf = appender!string();
        buf ~= "# data file for fldtk fluid (Fast Light User Interface Designer)\n";
        buf ~= "version 1.0000\n";
        if (codeFileName.length)
            buf ~= format("code_name %s\n", codeFileName);
        if (dubHeader)
            buf ~= "dub_header 1\n";
        if (settings.useFlCommand)
            buf ~= "use_FL_COMMAND\n";
        if (settings.writeMergebackData)
            buf ~= "mergeback 1\n";
        writeI18n(buf, i18n);
        writeShellCommandsBlock(buf, shellCommands);
        if (layout !is null) layout.writeToProject(buf);
        foreach (r; roots)
            writeNode(buf, r, 0);
        return buf.data;
    }

    private void writeI18n(ref Appender!string buf, I18nSettings i18n)
    {
        if (i18n.type == I18nType.none) return;

        buf ~= format("i18n_type %d\n", cast(int) i18n.type);
        final switch (i18n.type)
        {
        case I18nType.none:
            break;
        case I18nType.gnu:
            buf ~= format("i18n_include %s\n", i18n.gnuInclude.length ? i18n.gnuInclude : "{}");
            buf ~= format("i18n_conditional %s\n", i18n.gnuConditional.length ? i18n.gnuConditional : "{}");
            buf ~= format("i18n_gnu_function %s\n", i18n.gnuFunction);
            buf ~= format("i18n_gnu_static_function %s\n", i18n.gnuStaticFunction);
            break;
        case I18nType.posix:
            buf ~= format("i18n_include %s\n", i18n.posixInclude.length ? i18n.posixInclude : "{}");
            buf ~= format("i18n_conditional %s\n", i18n.posixConditional.length ? i18n.posixConditional : "{}");
            if (i18n.posixFile.length)
                buf ~= format("i18n_pos_file %s\n", i18n.posixFile);
            buf ~= format("i18n_pos_set %s\n", i18n.posixSet);
            break;
        }
    }

    private void indent(ref Appender!string buf, int depth)
    {
        foreach (i; 0 .. depth) buf ~= "  ";
    }

    /// Ported from FLTK's `Node::write(Project_Writer&)`, including
    /// its `proj1`/`proj2` codeview position bookkeeping (there `ftell()`
    /// on the output file; here `buf.data.length` on the in-memory
    /// buffer -- the direct equivalent, and always tracked, since this
    /// writer has no on-disk-only fast path to skip it for). `projSpan1`
    /// covers this node's own property block; `projSpan2` covers the
    /// same span for a leaf node, or just the closing-brace line of its
    /// children block for a container -- see `fluid.node.Node`'s own
    /// doc comment on these two fields.
    private void writeNode(ref Appender!string buf, Node n, int depth)
    {
        n.projSpan1.start = cast(int) buf.data.length;
        n.projSpan2.start = n.projSpan1.start;
        indent(buf, depth);
        buf ~= n.typeName;
        buf ~= " ";
        if (auto cn = cast(ClassNode) n)
            if (cn.prefix.length)
            {
                writeNameToken(buf, cn.prefix);
                buf ~= " ";
            }
        writeNameToken(buf, n.instanceName);
        buf ~= "\n";

        // GNU style, see this module's own top comment: each brace group
        // opens on its own line, one indent level deeper than the node
        // header, with its contents one level deeper still.
        indent(buf, depth + 1);
        buf ~= "{\n";
        writeProperties(buf, n, depth + 2);
        writeParentProperties(buf, n, depth + 2);
        indent(buf, depth + 1);
        buf ~= "}";
        n.projSpan1.end = cast(int) buf.data.length;

        if (n.canHaveChildren())
        {
            buf ~= "\n";
            indent(buf, depth + 1);
            buf ~= "{\n";
            foreach (c; n.children)
                writeNode(buf, c, depth + 2);
            n.projSpan2.start = cast(int) buf.data.length;
            indent(buf, depth + 1);
            buf ~= "}\n";
            n.projSpan2.end = cast(int) buf.data.length;
        }
        else
        {
            n.projSpan2.end = n.projSpan1.end;
            buf ~= "\n";
        }
    }

    /// The instance-name token: a bare word if it's already safe as
    /// one (matches `project_reader.d`'s own `isDelim()`-bounded word shape),
    /// `{}`-quoted otherwise (covers the common "anonymous node" case,
    /// `instanceName == ""`, and Function's own prototype-string names
    /// like `"button_cb(Fl_Button *b, void *)"`, which contain spaces
    /// and parens).
    private void writeNameToken(ref Appender!string buf, string name)
    {
        if (isSafeBareWord(name) && name.length > 0)
            buf ~= name;
        else
        {
            buf ~= "{";
            writeEscaped(buf, name);
            buf ~= "}";
        }
    }

    private static bool isSafeBareWord(string s)
    {
        if (s.length == 0) return false;
        foreach (c; s)
            if (c == ' ' || c == '\t' || c == '\n' || c == '{' || c == '}' || c == '#')
                return false;
        return true;
    }

    private void writeEscaped(ref Appender!string buf, string s)
    {
        foreach (c; s)
        {
            switch (c)
            {
                case '\\': buf ~= `\\`; break;
                case '{': buf ~= `\{`; break;
                case '}': buf ~= `\}`; break;
                case '#': buf ~= `\#`; break;
                // A raw CR would be dropped when the file is read back (the
                // reader strips every '\r'), so control characters other than
                // the newline and tab that stay literal are written as escapes.
                case '\r': buf ~= `\r`; break;
                case '\a': buf ~= `\a`; break;
                case '\b': buf ~= `\b`; break;
                case '\f': buf ~= `\f`; break;
                case '\v': buf ~= `\v`; break;
                default:
                    if (c < 0x20 && c != '\n' && c != '\t')
                        buf ~= format(`\x%02x`, cast(int) c);
                    else
                        buf ~= c;
                    break;
            }
        }
    }

    /// Writes one `name value` line -- `value` is always `{}`-braced
    /// (safe default, matches FLTK's own convention for anything
    /// that isn't a known-safe bare keyword/number -- see this
    /// module's own top comment on why exact FLTK formatting
    /// fidelity isn't the goal here).
    private void writeBracedProp(ref Appender!string buf, int depth, string name, string value)
    {
        indent(buf, depth);
        buf ~= name;
        buf ~= " {";
        writeEscaped(buf, value);
        buf ~= "}\n";
    }

    /// Writes one `name value` line with `value` emitted bare (for
    /// already-safe tokens: numbers, enum keywords, `x y w h` groups).
    private void writeBareProp(ref Appender!string buf, int depth, string name, string value)
    {
        indent(buf, depth);
        buf ~= name;
        buf ~= " ";
        buf ~= value;
        buf ~= "\n";
    }

    /// Writes one `name value` line, `value` bare when it is a single
    /// safe token and `{}`-braced (escaped) otherwise -- for free-text
    /// values that may hold spaces, such as a Function's `return_type`
    /// (`override int`), a widget's `type` (`Vert Fill`) or a `class`
    /// override.
    private void writeWordProp(ref Appender!string buf, int depth, string name, string value)
    {
        if (isSafeBareWord(value)) writeBareProp(buf, depth, name, value);
        else writeBracedProp(buf, depth, name, value);
    }

    private void writeFlag(ref Appender!string buf, int depth, string name)
    {
        indent(buf, depth);
        buf ~= name;
        buf ~= "\n";
    }

    private void writeProperties(ref Appender!string buf, Node n, int depth)
    {
        // -- Node's own universal properties --
        if (includeUid_) writeBareProp(buf, depth, "uid", format("%04x", n.uid));
        if (n.hasLabel) writeBracedProp(buf, depth, "label", n.label);
        if (n.callback.length) writeBracedProp(buf, depth, "callback", n.callback);
        if (n.userData.length) writeBracedProp(buf, depth, "user_data", n.userData);
        if (n.comment.length) writeBracedProp(buf, depth, "comment", n.comment);

        if (auto fn = cast(FunctionNode) n)
        {
            if (fn.returnType.length) writeWordProp(buf, depth, "return_type", fn.returnType);
            final switch (fn.access)
            {
            case Access.private_: writeFlag(buf, depth, "private"); break;
            case Access.public_: break;
            case Access.protected_: writeFlag(buf, depth, "protected"); break;
            }
            if (fn.declareC) writeFlag(buf, depth, "C");
        }

        // `class Name {open : Base}` -- the base class is introduced by a
        // bare `:` token, see `ClassNode.readProperty()`.
        if (auto cn = cast(ClassNode) n)
            if (cn.baseClass.length) writeBracedProp(buf, depth, ":", cn.baseClass);

        if (auto wn = cast(WidgetNode) n)
            writeWidgetProperties(buf, wn, depth);

        // DeclNode's visibility/static flags, matching FLTK's own
        // Decl_Node::write_properties() -- DataNode inherits these too
        // (FLTK: `Data_Node : public Decl_Node`), see below for its
        // own additional "filename" property.
        if (auto dcn = cast(DeclNode) n)
        {
            final switch (dcn.visibility_)
            {
                case 0: writeFlag(buf, depth, "private"); break;
                case 1: writeFlag(buf, depth, "public"); break;
                case 2: writeFlag(buf, depth, "protected"); break;
            }
            writeFlag(buf, depth, dcn.staticFlag_ ? "local" : "global");
        }
        if (auto dan = cast(DataNode) n)
        {
            if (dan.filename.length) writeBracedProp(buf, depth, "filename", dan.filename);
            // Storage format -- see `data_node.d`'s own doc comment for
            // the mapping from FLTK's original 6-value `output_
            // format_` enum down to these two independent flags.
            // Reuses FLTK's own "textmode"/"compressed" bare-flag
            // spellings (both real FLTK `.fl` keywords already),
            // just no longer mutually exclusive with each other the way
            // FLTK's single `Fl_Choice` forced them to be.
            if (dan.asString) writeFlag(buf, depth, "textmode");
            if (dan.compressedFlag) writeFlag(buf, depth, "compressed");
        }

        // `CodeBlockNode`/`DeclBlockNode`'s own "after" text, matching
        // FLTK's own two different write conditions exactly:
        // `CodeBlock_Node::write_properties()` only writes "after" when
        // `end_code()` is non-empty; `DeclBlock_Node::write_properties()`
        // writes it unconditionally (FLTK's own comment on that
        // function says why: "after" always followed by a value token,
        // even an empty one). `writeMap_` mirrors `DeclBlock_Node`'s own
        // "map" property, only emitted when it differs from the default
        // (`CODE_IN_SOURCE`) -- both round-trip-only fields with no
        // D-codegen meaning in this dialect, see `DeclBlockNode`'s own
        // doc comment.
        if (auto cbn = cast(CodeBlockNode) n)
            if (cbn.afterText.length) writeBracedProp(buf, depth, "after", cbn.afterText);
        if (auto dbn = cast(DeclBlockNode) n)
        {
            if ((dbn.writeMap_ & DeclBlockNode.codeInHeader) != 0) writeFlag(buf, depth, "public");
            if (dbn.writeMap_ != DeclBlockNode.codeInSource)
                writeBareProp(buf, depth, "map", format("%d", dbn.writeMap_));
            writeBracedProp(buf, depth, "after", dbn.afterText);
        }
        // `CommentNode.inSource_`/`inHeader_` -- matches FLTK's own
        // `Comment_Node::write_properties()` exactly: both always
        // written (never omitted, even at the default), one of a
        // matched positive/negative pair per flag.
        if (auto comn = cast(CommentNode) n)
        {
            writeFlag(buf, depth, comn.inSource_ ? "in_source" : "not_in_source");
            writeFlag(buf, depth, comn.inHeader_ ? "in_header" : "not_in_header");
        }

        if (auto win = cast(WindowNode) n)
        {
            if (win.modal_) writeFlag(buf, depth, "modal");
            if (win.nonModal_) writeFlag(buf, depth, "non_modal");
            if (win.noBorder_) writeFlag(buf, depth, "noborder");
            if (win.xclass.length) writeBracedProp(buf, depth, "xclass", win.xclass);
            if (win.hasSizeRange)
                writeBareProp(buf, depth, "size_range", format("{%d %d %d %d}",
                    win.sizeRangeMinW, win.sizeRangeMinH, win.sizeRangeMaxW, win.sizeRangeMaxH));
        }

        if (auto wcn = cast(WidgetClassNode) n)
        {
            if (wcn.wcRelative == 1) writeFlag(buf, depth, "position_relative");
            else if (wcn.wcRelative == 2) writeFlag(buf, depth, "position_relative_rescale");
        }

        if (auto gn = cast(GridNode) n) writeGridProperties(buf, gn, depth);
        if (auto flexn = cast(FlexNode) n) writeFlexProperties(buf, flexn, depth);

        // "open"/"selected" are Fluid-editor-only bookkeeping (no D
        // codegen equivalent) but are real, already-parsed .fl
        // properties (node.d's own readProperty()) -- re-emit them so
        // a load->save cycle doesn't silently drop them.
        if (n.open_) writeFlag(buf, depth, "open");
        if (n.selected_) writeFlag(buf, depth, "selected");
    }

    private void writeWidgetProperties(ref Appender!string buf, WidgetNode wn, int depth)
    {
        import std.format : format;

        final switch (wn.access)
        {
        case Access.private_: writeFlag(buf, depth, "private"); break;
        case Access.public_: break;
        case Access.protected_: writeFlag(buf, depth, "protected"); break;
        }
        if (wn.hasXywh)
            writeBareProp(buf, depth, "xywh",
                format("{%d %d %d %d}", wn.x, wn.y, wn.w, wn.h));
        if (wn.hasBoxtype) writeWordProp(buf, depth, "box", wn.boxtype);
        if (wn.hasDownBoxtype) writeWordProp(buf, depth, "down_box", wn.downBoxtype);
        if (wn.color >= 0) writeBareProp(buf, depth, "color", format("%d", wn.color));
        if (wn.selectionColor >= 0)
            writeBareProp(buf, depth, "selection_color", format("%d", wn.selectionColor));
        if (wn.labelfont >= 0) writeBareProp(buf, depth, "labelfont", format("%d", wn.labelfont));
        if (wn.labelsize >= 0) writeBareProp(buf, depth, "labelsize", format("%d", wn.labelsize));
        if (wn.labelcolorRaw >= 0)
            writeBareProp(buf, depth, "labelcolor", format("%d", wn.labelcolorRaw));
        if (wn.labeltype.length) writeWordProp(buf, depth, "labeltype", wn.labeltype);
        if (wn.textsize >= 0) writeBareProp(buf, depth, "textsize", format("%d", wn.textsize));
        if (wn.textfont >= 0) writeBareProp(buf, depth, "textfont", format("%d", wn.textfont));
        if (wn.textcolorRaw >= 0)
            writeBareProp(buf, depth, "textcolor", format("%d", wn.textcolorRaw));
        if (wn.vLabelMargin >= 0)
            writeBareProp(buf, depth, "v_label_margin", format("%d", wn.vLabelMargin));
        if (wn.hLabelMargin >= 0)
            writeBareProp(buf, depth, "h_label_margin", format("%d", wn.hLabelMargin));
        if (wn.imageSpacing >= 0)
            writeBareProp(buf, depth, "image_spacing", format("%d", wn.imageSpacing));
        if (wn.hasValue) writeBracedProp(buf, depth, "value", wn.valueRaw);
        if (wn.hasCompact) writeBracedProp(buf, depth, "compact", wn.compactRaw);
        if (wn.hasMinimum) writeBracedProp(buf, depth, "minimum", wn.minimumRaw);
        if (wn.hasMaximum) writeBracedProp(buf, depth, "maximum", wn.maximumRaw);
        if (wn.hasStep) writeBracedProp(buf, depth, "step", wn.stepRaw);
        if (wn.hasSliderSize) writeBracedProp(buf, depth, "slider_size", wn.sliderSizeRaw);
        if (wn.hasShortcut) writeBracedProp(buf, depth, "shortcut", wn.shortcutRaw);
        if (wn.hasClassOverride) writeWordProp(buf, depth, "class", wn.classOverride);
        if (wn.alignRaw >= 0) writeBareProp(buf, depth, "align", format("%d", wn.alignRaw));
        if (wn.whenRaw >= 0) writeBareProp(buf, depth, "when", format("%d", wn.whenRaw));
        if (wn.typeWord.length) writeWordProp(buf, depth, "type", wn.typeWord);
        if (wn.hasSetupCode) writeBracedProp(buf, depth, "setup", wn.setupCode);
        if (wn.tooltip.length) writeBracedProp(buf, depth, "tooltip", wn.tooltip);
        if (wn.hasImage)
        {
            if (wn.scaleImageW || wn.scaleImageH)
                writeBareProp(buf, depth, "scale_image", format("{%d %d}", wn.scaleImageW, wn.scaleImageH));
            writeBracedProp(buf, depth, "image", wn.imageFilename);
            writeBareProp(buf, depth, "compress_image", format("%d", wn.compressImage ? 1 : 0));
        }
        if (wn.bindImage)
            writeBareProp(buf, depth, "bind_image", "1");
        if (wn.hasDeimage)
        {
            if (wn.scaleDeimageW || wn.scaleDeimageH)
                writeBareProp(buf, depth, "scale_deimage", format("{%d %d}", wn.scaleDeimageW, wn.scaleDeimageH));
            writeBracedProp(buf, depth, "deimage", wn.deimageFilename);
            writeBareProp(buf, depth, "compress_deimage", format("%d", wn.compressDeimage ? 1 : 0));
        }
        if (wn.bindDeimage)
            writeBareProp(buf, depth, "bind_deimage", "1");
        if (wn.hidden) writeFlag(buf, depth, "hide");
        if (wn.deactivated) writeFlag(buf, depth, "deactivate");
        if (wn.resizableFlag) writeFlag(buf, depth, "resizable");
        if (wn.hotspotFlag)
            writeFlag(buf, depth, (cast(MenuItemNode) wn) !is null ? "divider" : "hotspot");
        if (wn.usesFontMenu) writeFlag(buf, depth, "uses_font_menu");
        if (wn.usesColorMenu) writeFlag(buf, depth, "uses_color_menu");
        if (auto mi = cast(MenuItemNode) wn)
            if (mi.headline_) writeFlag(buf, depth, "headline");
        // "visible" is a documented no-op in widget_node.d's own
        // readProperty() (no backing field at all) -- nothing to
        // re-emit, see this module's own top comment.
    }

    private void writeGridProperties(ref Appender!string buf, GridNode gn, int depth)
    {
        if (gn.hasDimensions)
            writeBareProp(buf, depth, "dimensions", format("{%d %d}", gn.rows, gn.cols));
        if (gn.hasMargin)
            writeBareProp(buf, depth, "margin",
                format("{%d %d %d %d}", gn.marginLeft, gn.marginTop, gn.marginRight, gn.marginBottom));
        if (gn.hasGap)
            writeBareProp(buf, depth, "gap", format("{%d %d}", gn.gapRow, gn.gapCol));
        writeIntArrayProp(buf, depth, "rowheights", gn.rowHeights);
        writeIntArrayProp(buf, depth, "rowweights", gn.rowWeights);
        writeIntArrayProp(buf, depth, "rowgaps", gn.rowGaps);
        writeIntArrayProp(buf, depth, "colwidths", gn.colWidths);
        writeIntArrayProp(buf, depth, "colweights", gn.colWeights);
        writeIntArrayProp(buf, depth, "colgaps", gn.colGaps);
    }

    private void writeFlexProperties(ref Appender!string buf, FlexNode fn, int depth)
    {
        if (fn.hasMargin)
            writeBareProp(buf, depth, "margin",
                format("{%d %d %d %d}", fn.marginLeft, fn.marginTop, fn.marginRight, fn.marginBottom));
        if (fn.hasGap)
            writeBareProp(buf, depth, "gap", format("%d", fn.gap));
        if (fn.fixedSizeTuples.length)
        {
            auto pairs = fn.fixedSizeTuples.length / 2;
            auto s = appender!string();
            s ~= format("{%d", pairs);
            foreach (v; fn.fixedSizeTuples) s ~= format(" %d", v);
            s ~= "}";
            writeBareProp(buf, depth, "fixed_size_tuples", s.data);
        }
    }

    private void writeIntArrayProp(ref Appender!string buf, int depth, string name, const(int)[] values)
    {
        if (values.length == 0) return;
        auto s = appender!string();
        s ~= "{";
        foreach (i, v; values)
        {
            if (i) s ~= " ";
            s ~= format("%d", v);
        }
        s ~= "}";
        writeBareProp(buf, depth, name, s.data);
    }

    /// Write-side mirror of `Reader.parseNode()`'s own `parent_properties`
    /// handling -- see `fluid.grid_node`'s module doc comment for the
    /// full mechanism. Matches this file's existing cast-based dispatch
    /// convention (no virtual method on `Node` for the write path,
    /// unlike `Node.readParentProperty()` on the read side).
    private void writeParentProperties(ref Appender!string buf, Node n, int depth)
    {
        auto gridParent = cast(GridNode) n.parent;
        if (gridParent is null) return;
        auto info = n in gridParent.cellOf;
        if (info is null) return;

        indent(buf, depth);
        buf ~= "parent_properties\n";
        indent(buf, depth + 1);
        buf ~= "{\n";
        writeBareProp(buf, depth + 2, "location", format("{%d %d}", info.row, info.col));
        if (info.colspan > 1) writeBareProp(buf, depth + 2, "colspan", format("%d", info.colspan));
        if (info.rowspan > 1) writeBareProp(buf, depth + 2, "rowspan", format("%d", info.rowspan));
        if (info.alignRaw != 0x30) writeBareProp(buf, depth + 2, "align", format("%d", info.alignRaw));
        if (info.minW != 20 || info.minH != 20)
            writeBareProp(buf, depth + 2, "minsize", format("{%d %d}", info.minW, info.minH));
        indent(buf, depth + 1);
        buf ~= "}\n";
    }
}

unittest
{
    import fluid.project_reader : Reader;

    // Free-text values with spaces (`return_type`, `type`) keep their braces,
    // and a CR in a label is written as an escape instead of being lost.
    string source = "version 1.0000\n"
        ~ "Function {handle()} {return_type {override int}\n} {\n"
        ~ "  Window w {xywh {0 0 100 100}} {\n"
        ~ "    Slider s {\n"
        ~ "      label {a\\rb}\n"
        ~ "      xywh {0 0 20 80} type {Vert Fill}\n"
        ~ "    }\n"
        ~ "  }\n"
        ~ "}\n";
    auto roots1 = new Reader(source).readProject();
    auto roots2 = new Reader(new ProjectWriter().generate(roots1)).readProject();
    auto fn = cast(FunctionNode) roots2[0];
    assert(fn.returnType == "override int");
    auto sl = cast(WidgetNode) fn.children[0].children[0];
    assert(sl.typeWord == "Vert Fill");
    assert(sl.label == "a\rb");
}

unittest
{
    import fluid.project_reader : Reader;

    // Load -> save -> load again -> the two in-memory trees agree
    // field-by-field. Not a byte-diff of .fl text (GNU-style
    // formatting is a deliberate reformat, not preserved verbatim) --
    // see this module's own top comment on why that's the honest bar.
    string source = "version 1.0000\n"
        ~ "Function {} {open\n} {\n"
        ~ "  Window mainWin {open selected\n"
        ~ "    xywh {10 20 300 200} type Double resizable hotspot\n"
        ~ "    xclass {myclass} size_range {100 80 400 300} noborder\n"
        ~ "  } {\n"
        ~ "    Box greeting {\n"
        ~ "      label {Hello\nWorld}\n"
        ~ "      xywh {10 10 100 30} box FLAT_BOX color 7\n"
        ~ "      scale_image {32 24} image {pic.png} compress_image 0 bind_image 1 deimage {pic_gray.png} compress_deimage 1\n"
        ~ "      h_label_margin 3 v_label_margin 5 image_spacing 7 uses_font_menu uses_color_menu\n"
        ~ "    }\n"
        ~ "  }\n"
        ~ "}\n";

    auto roots1 = new Reader(source).readProject();
    auto text2 = new ProjectWriter().generate(roots1);
    auto roots2 = new Reader(text2).readProject();

    assert(roots1.length == roots2.length);

    auto fn1 = cast(FunctionNode) roots1[0];
    auto fn2 = cast(FunctionNode) roots2[0];
    assert(fn1 !is null && fn2 !is null);
    assert(fn1.open_ == fn2.open_);
    assert(fn1.children.length == fn2.children.length);

    auto win1 = cast(WindowNode) fn1.children[0];
    auto win2 = cast(WindowNode) fn2.children[0];
    assert(win1.instanceName == win2.instanceName);
    assert(win1.x == win2.x && win1.y == win2.y && win1.w == win2.w && win1.h == win2.h);
    assert(win1.typeWord == win2.typeWord);
    assert(win1.resizableFlag == win2.resizableFlag);
    assert(win1.open_ == win2.open_ && win1.selected_ == win2.selected_);
    assert(win1.xclass == win2.xclass && win1.xclass == "myclass");
    assert(win1.hasSizeRange == win2.hasSizeRange && win1.hasSizeRange);
    assert(win1.sizeRangeMinW == win2.sizeRangeMinW && win1.sizeRangeMinW == 100);
    assert(win1.sizeRangeMinH == win2.sizeRangeMinH && win1.sizeRangeMinH == 80);
    assert(win1.sizeRangeMaxW == win2.sizeRangeMaxW && win1.sizeRangeMaxW == 400);
    assert(win1.sizeRangeMaxH == win2.sizeRangeMaxH && win1.sizeRangeMaxH == 300);
    assert(win1.noBorder_ == win2.noBorder_ && win1.noBorder_);
    // Regression test for an unrecognized bare-flag parser desync:
    // "hotspot" as a bare
    // flag immediately followed by another property with a braced value
    // would desync the whole rest of this node's property list if
    // there were no
    // "hotspot" case at all, since the generic unrecognized-
    // property fallback would defensively eat the *next* property's own name
    // as if it were hotspot's value. Placed here deliberately in that
    // exact shape (`resizable hotspot\n    xclass {...}`), not just as
    // an isolated field check, so a future accidental removal of the
    // "hotspot" case
    // fails loudly via the same "expected '{' " assert this class of
    // bug hits, not just a silently-wrong boolean.
    assert(win1.hotspotFlag == win2.hotspotFlag && win1.hotspotFlag);

    auto box1 = cast(WidgetNode) win1.children[0];
    auto box2 = cast(WidgetNode) win2.children[0];
    assert(box1.label == box2.label);
    assert(box1.x == box2.x && box1.w == box2.w);
    assert(box1.boxtype == box2.boxtype);
    assert(box1.color == box2.color);
    assert(box1.hasImage == box2.hasImage && box1.hasImage);
    assert(box1.imageFilename == box2.imageFilename && box1.imageFilename == "pic.png");
    assert(box1.hasDeimage == box2.hasDeimage && box1.hasDeimage);
    assert(box1.deimageFilename == box2.deimageFilename && box1.deimageFilename == "pic_gray.png");
    assert(box1.compressImage == box2.compressImage && !box1.compressImage);
    assert(box1.compressDeimage == box2.compressDeimage && box1.compressDeimage);
    assert(box1.bindImage == box2.bindImage && box1.bindImage);
    assert(box1.bindDeimage == box2.bindDeimage && !box1.bindDeimage);
    assert(box1.scaleImageW == box2.scaleImageW && box1.scaleImageW == 32);
    assert(box1.scaleImageH == box2.scaleImageH && box1.scaleImageH == 24);
    assert(box1.scaleDeimageW == box2.scaleDeimageW && box1.scaleDeimageW == 0);
    assert(box1.scaleDeimageH == box2.scaleDeimageH && box1.scaleDeimageH == 0);
    assert(box1.usesFontMenu == box2.usesFontMenu && box1.usesFontMenu);
    assert(box1.usesColorMenu == box2.usesColorMenu && box1.usesColorMenu);
    assert(box1.hLabelMargin == box2.hLabelMargin && box1.hLabelMargin == 3);
    assert(box1.vLabelMargin == box2.vLabelMargin && box1.vLabelMargin == 5);
    assert(box1.imageSpacing == box2.imageSpacing && box1.imageSpacing == 7);
}

unittest
{
    // A node ordinarily *nested* deep inside a project (a Box inside a
    // Group inside a Window) round-trips correctly when written as its
    // *own* standalone top-level root -- confirms the exact assumption
    // `gui_main.d`'s Cut/Copy/Paste/Duplicate build on:
    // `ProjectWriter.generate()`/`Reader.readProject()` don't require
    // their `roots` to be project-level node kinds (Function/class/
    // decl/Window) -- the `.fl` grammar is the same at every nesting
    // depth, so any subtree can be serialized and re-parsed standalone,
    // the same way `newProject()`'s own bare `[WindowNode]` roots
    // already prove for a *window*-level root.
    import fluid.project_reader : Reader;
    import fluid.group_node : GroupNode;

    string source = "version 1.0000\n"
        ~ "Function {} {open\n} {\n"
        ~ "  Window mainWin {open\n"
        ~ "    xywh {10 20 300 200}\n"
        ~ "  } {\n"
        ~ "    Group grp {\n"
        ~ "      xywh {0 0 200 200}\n"
        ~ "    } {\n"
        ~ "      Box greeting {\n"
        ~ "        label {Hello}\n"
        ~ "        xywh {10 10 100 30} box FLAT_BOX color 7\n"
        ~ "      }\n"
        ~ "    }\n"
        ~ "  }\n"
        ~ "}\n";

    auto roots = new Reader(source).readProject();
    auto fn = cast(FunctionNode) roots[0];
    auto win = cast(WindowNode) fn.children[0];
    auto grp = cast(GroupNode) win.children[0];
    auto box = cast(WidgetNode) grp.children[0];
    assert(box.instanceName == "greeting");

    // Cut/copy the Box alone, standalone (as topLevelSelection() would
    // hand it to ProjectWriter.generate() -- a bare Node[] of just the
    // selected node, no wrapping Function/Window/Group at all).
    string snippet = new ProjectWriter().generate([cast(Node) box]);
    auto pasted = new Reader(snippet).readProject();
    assert(pasted.length == 1);
    auto box2 = cast(WidgetNode) pasted[0];
    assert(box2 !is null);
    assert(box2.instanceName == "greeting");
    assert(box2.label == "Hello");
    assert(box2.x == 10 && box2.y == 10 && box2.w == 100 && box2.h == 30);
    assert(box2.boxtype == "FLAT_BOX");
    assert(box2.color == 7);

    // Cut/copy the *Group* (with its own Box child) the same way --
    // confirms an arbitrary-depth subtree, not just a single leaf.
    string groupSnippet = new ProjectWriter().generate([cast(Node) grp]);
    auto pastedGroup = new Reader(groupSnippet).readProject();
    assert(pastedGroup.length == 1);
    auto grp2 = cast(GroupNode) pastedGroup[0];
    assert(grp2 !is null);
    assert(grp2.children.length == 1);
    assert((cast(WidgetNode) grp2.children[0]).instanceName == "greeting");
}

unittest
{
    // Grid's own properties (dimensions/margin/gap/row-and-col arrays)
    // plus the parent_properties mechanism (grid-cell placement stored
    // on the *child's* own property block but interpreted by the
    // *parent* -- see grid_node.d's module doc comment) both round-trip.
    import fluid.project_reader : Reader;
    import fluid.grid_node : GridNode;

    string source = "version 1.0000\n"
        ~ "Function {} {open\n} {\n"
        ~ "  Window mainWin {\n"
        ~ "    xywh {0 0 300 200}\n"
        ~ "  } {\n"
        ~ "    Grid myGrid {\n"
        ~ "      xywh {10 10 280 180}\n"
        ~ "      dimensions {2 2}\n"
        ~ "      margin {4 4 4 4}\n"
        ~ "      gap {2 2}\n"
        ~ "      rowheights {0 40}\n"
        ~ "      colweights {50 100}\n"
        ~ "    } {\n"
        ~ "      Box a {\n"
        ~ "        xywh {0 0 100 50}\n"
        ~ "        parent_properties {\n"
        ~ "          location {0 0}\n"
        ~ "        }\n"
        ~ "      }\n"
        ~ "      Box b {\n"
        ~ "        xywh {0 0 100 50}\n"
        ~ "        parent_properties {\n"
        ~ "          location {0 1}\n"
        ~ "          rowspan 2\n"
        ~ "          align 48\n"
        ~ "          minsize {30 30}\n"
        ~ "        }\n"
        ~ "      }\n"
        ~ "    }\n"
        ~ "  }\n"
        ~ "}\n";

    auto roots1 = new Reader(source).readProject();
    auto text2 = new ProjectWriter().generate(roots1);
    auto roots2 = new Reader(text2).readProject();

    auto fn1 = cast(FunctionNode) roots1[0];
    auto fn2 = cast(FunctionNode) roots2[0];
    auto win1 = cast(WindowNode) fn1.children[0];
    auto win2 = cast(WindowNode) fn2.children[0];
    auto grid1 = cast(GridNode) win1.children[0];
    auto grid2 = cast(GridNode) win2.children[0];
    assert(grid1 !is null && grid2 !is null);
    assert(grid1.rows == grid2.rows && grid1.cols == grid2.cols);
    assert(grid1.marginLeft == grid2.marginLeft && grid1.marginTop == grid2.marginTop);
    assert(grid1.gapRow == grid2.gapRow && grid1.gapCol == grid2.gapCol);
    assert(grid1.rowHeights == grid2.rowHeights);
    assert(grid1.colWeights == grid2.colWeights);

    auto a1 = grid1.children[0], a2 = grid2.children[0];
    auto b1 = grid1.children[1], b2 = grid2.children[1];
    auto cellA1 = a1 in grid1.cellOf, cellA2 = a2 in grid2.cellOf;
    assert(cellA1 !is null && cellA2 !is null);
    assert(cellA1.row == cellA2.row && cellA1.col == cellA2.col);
    assert(cellA1.rowspan == 1 && cellA2.rowspan == 1); // default, not written

    auto cellB1 = b1 in grid1.cellOf, cellB2 = b2 in grid2.cellOf;
    assert(cellB1 !is null && cellB2 !is null);
    assert(cellB1.row == cellB2.row && cellB1.col == cellB2.col);
    assert(cellB1.rowspan == 2 && cellB2.rowspan == 2);
    assert(cellB1.alignRaw == cellB2.alignRaw && cellB1.alignRaw == 48);
    assert(cellB1.minW == cellB2.minW && cellB1.minW == 30);
    assert(cellB1.minH == cellB2.minH && cellB1.minH == 30);
}

unittest
{
    // Regression coverage: `SubmenuNode.canHaveChildren() == true` means the
    // reader asserts `open == "{"` for it just like any other
    // container -- including a genuinely empty one, which is the case
    // most likely to be gotten wrong (`writeNode()` always writes the
    // `{ }` children block whenever `canHaveChildren()` is true,
    // regardless of whether there's anything inside it).
    import fluid.project_reader : Reader;
    import fluid.menu_owner_node : MenuOwnerNode;
    import fluid.menu_item_node : SubmenuNode;

    string source = "version 1.0000\n"
        ~ "Function {} {open\n} {\n"
        ~ "  Window mainWin {\n"
        ~ "    xywh {0 0 300 200}\n"
        ~ "  } {\n"
        ~ "    Menu_Button menu {\n"
        ~ "      xywh {10 10 100 24}\n"
        ~ "    } {\n"
        ~ "      Submenu sub {\n"
        ~ "        label {Sub}\n"
        ~ "      } {\n"
        ~ "        MenuItem nested {\n"
        ~ "          label {Nested}\n"
        ~ "        }\n"
        ~ "      }\n"
        ~ "      Submenu empty {\n"
        ~ "        label {Empty}\n"
        ~ "      } {\n"
        ~ "      }\n"
        ~ "      CheckMenuItem check {\n"
        ~ "        label {Check}\n"
        ~ "      }\n"
        ~ "      RadioMenuItem radio {\n"
        ~ "        label {Radio}\n"
        ~ "      }\n"
        ~ "    }\n"
        ~ "  }\n"
        ~ "}\n";

    auto roots1 = new Reader(source).readProject();
    auto text2 = new ProjectWriter().generate(roots1);
    auto roots2 = new Reader(text2).readProject();

    auto fn2 = cast(FunctionNode) roots2[0];
    auto win2 = cast(WindowNode) fn2.children[0];
    auto menu2 = cast(MenuOwnerNode) win2.children[0];
    assert(menu2 !is null);
    assert(menu2.children.length == 4);

    auto sub2 = cast(SubmenuNode) menu2.children[0];
    assert(sub2 !is null);
    assert(sub2.label == "Sub");
    assert(sub2.children.length == 1);
    assert(sub2.children[0].label == "Nested");

    auto empty2 = cast(SubmenuNode) menu2.children[1];
    assert(empty2 !is null);
    assert(empty2.label == "Empty");
    assert(empty2.children.length == 0);

    assert(menu2.children[2].typeName == "CheckMenuItem");
    assert(menu2.children[2].label == "Check");
    assert(menu2.children[3].typeName == "RadioMenuItem");
    assert(menu2.children[3].label == "Radio");
}

unittest
{
    // `DeclBlockNode`/`CodeBlockNode` round-trip -- `after`/`map`/`public` all
    // survive a load-then-save cycle, including FLTK's own two
    // different write conditions (`CodeBlockNode`'s "after" only when
    // non-empty; `DeclBlockNode`'s "after" always written, even empty;
    // "map" only when it differs from the default). Also covers a
    // nested `declblock {}` (a `decl {}` child inside another
    // `declblock {}`) and a `codeblock {}` sitting among a Window's own
    // widget-tree children -- both real, exercised shapes, not just
    // root-level placement.
    import fluid.project_reader : Reader;

    string source = "version 1.0000\n"
        ~ "Function {} {open\n} {\n"
        ~ "  declblock {version (Windows)} {\n"
        ~ "    map 3\n"
        ~ "    after {// win only}\n"
        ~ "  } {\n"
        ~ "    decl {int winOnlyDecl;} {\n"
        ~ "      local\n"
        ~ "    }\n"
        ~ "    declblock {version (Posix)} {\n"
        ~ "      after {}\n"
        ~ "    } {\n"
        ~ "      decl {int posixOnlyDecl;} {\n"
        ~ "        local\n"
        ~ "      }\n"
        ~ "    }\n"
        ~ "  }\n"
        ~ "  Window mainWin {\n"
        ~ "    xywh {0 0 300 200}\n"
        ~ "  } {\n"
        ~ "    codeblock {if (test())} {\n"
        ~ "      after {while (0)}\n"
        ~ "    } {\n"
        ~ "      code {writeln(\"x\");} {\n"
        ~ "      }\n"
        ~ "    }\n"
        ~ "    codeblock {if (other())} {\n"
        ~ "    } {\n"
        ~ "      code {writeln(\"y\");} {\n"
        ~ "      }\n"
        ~ "    }\n"
        ~ "  }\n"
        ~ "}\n";

    auto roots1 = new Reader(source).readProject();
    auto text2 = new ProjectWriter().generate(roots1);
    auto roots2 = new Reader(text2).readProject();

    auto fn1 = cast(FunctionNode) roots1[0];
    auto fn2 = cast(FunctionNode) roots2[0];

    auto dbn1 = cast(DeclBlockNode) fn1.children[0];
    auto dbn2 = cast(DeclBlockNode) fn2.children[0];
    assert(dbn1 !is null && dbn2 !is null);
    assert(dbn1.instanceName == "version (Windows)" && dbn2.instanceName == dbn1.instanceName);
    assert(dbn1.afterText == "// win only" && dbn2.afterText == dbn1.afterText);
    assert(dbn1.writeMap_ == 3 && dbn2.writeMap_ == 3);
    assert((cast(DeclNode) dbn1.children[0]).instanceName == "int winOnlyDecl;");
    assert((cast(DeclNode) dbn2.children[0]).instanceName == "int winOnlyDecl;");

    auto nested1 = cast(DeclBlockNode) dbn1.children[1];
    auto nested2 = cast(DeclBlockNode) dbn2.children[1];
    assert(nested1 !is null && nested2 !is null);
    assert(nested1.instanceName == "version (Posix)" && nested2.instanceName == nested1.instanceName);
    assert(nested1.afterText == "" && nested2.afterText == "");
    // Default write_map_ (CODE_IN_SOURCE) -- "map" line correctly
    // omitted on save, not silently written as 0.
    assert(nested1.writeMap_ == DeclBlockNode.codeInSource);
    assert(nested2.writeMap_ == DeclBlockNode.codeInSource);

    auto win1 = cast(WindowNode) fn1.children[1];
    auto win2 = cast(WindowNode) fn2.children[1];
    auto cb1 = cast(CodeBlockNode) win1.children[0];
    auto cb2 = cast(CodeBlockNode) win2.children[0];
    assert(cb1 !is null && cb2 !is null);
    assert(cb1.instanceName == "if (test())" && cb2.instanceName == cb1.instanceName);
    assert(cb1.afterText == "while (0)" && cb2.afterText == cb1.afterText);

    auto cb1b = cast(CodeBlockNode) win1.children[1];
    auto cb2b = cast(CodeBlockNode) win2.children[1];
    assert(cb1b !is null && cb2b !is null);
    assert(cb1b.afterText == "" && cb2b.afterText == "");
}

unittest
{
    // Flex's own properties (margin/gap/fixed_size_tuples) round-trip.
    import fluid.project_reader : Reader;
    import fluid.flex_node : FlexNode;

    string source = "version 1.0000\n"
        ~ "Function {} {open\n} {\n"
        ~ "  Window mainWin {\n"
        ~ "    xywh {0 0 300 200}\n"
        ~ "  } {\n"
        ~ "    Flex myFlex {\n"
        ~ "      xywh {10 10 280 80}\n"
        ~ "      type HORIZONTAL\n"
        ~ "      margin {2 2 2 2}\n"
        ~ "      gap 4\n"
        ~ "      fixed_size_tuples {1 0 60}\n"
        ~ "    } {\n"
        ~ "      Box c {\n"
        ~ "        xywh {0 0 50 50}\n"
        ~ "      }\n"
        ~ "    }\n"
        ~ "  }\n"
        ~ "}\n";

    auto roots1 = new Reader(source).readProject();
    auto text2 = new ProjectWriter().generate(roots1);
    auto roots2 = new Reader(text2).readProject();

    auto fn1 = cast(FunctionNode) roots1[0];
    auto fn2 = cast(FunctionNode) roots2[0];
    auto win1 = cast(WindowNode) fn1.children[0];
    auto win2 = cast(WindowNode) fn2.children[0];
    auto flex1 = cast(FlexNode) win1.children[0];
    auto flex2 = cast(FlexNode) win2.children[0];
    assert(flex1 !is null && flex2 !is null);
    assert(flex1.typeWord == "HORIZONTAL" && flex2.typeWord == "HORIZONTAL");
    assert(flex1.marginLeft == flex2.marginLeft && flex1.marginTop == flex2.marginTop);
    assert(flex1.gap == flex2.gap && flex1.gap == 4);
    assert(flex1.fixedSizeTuples == flex2.fixedSizeTuples);
    assert(flex1.fixedSizeTuples == [0, 60]);
}

unittest
{
    // Project-wide I18n settings
    // round-trip through `.fl` text, both directions -- `generate()`'s
    // default (`I18nSettings.init`, `I18nType.none`) emits nothing
    // (every pre-existing call site/test above this one relies on
    // exactly that), and a real GNU/POSIX config round-trips losslessly.
    import fluid.project_reader : Reader;
    import fluid.i18n : I18nSettings, I18nType;
    import std.algorithm : canFind;

    // No i18n at all -- generate() must not emit any i18n_* line.
    auto rootsNone = new Reader("version 1.0000\nFunction {} {open\n} {\n}\n").readProject();
    string textNone = new ProjectWriter().generate(rootsNone);
    assert(!textNone.canFind("i18n_type"));

    // GNU gettext, non-default settings throughout.
    I18nSettings gnu;
    gnu.type = I18nType.gnu;
    gnu.gnuInclude = `"gettext.h"`;
    gnu.gnuConditional = "ENABLE_NLS";
    gnu.gnuFunction = "_";
    gnu.gnuStaticFunction = "N_";
    string textGnu = new ProjectWriter().generate(rootsNone, gnu);
    auto readerGnu = new Reader(textGnu);
    readerGnu.readProject();
    assert(readerGnu.i18n.type == I18nType.gnu);
    assert(readerGnu.i18n.gnuInclude == `"gettext.h"`);
    assert(readerGnu.i18n.gnuConditional == "ENABLE_NLS");
    assert(readerGnu.i18n.gnuFunction == "_");
    assert(readerGnu.i18n.gnuStaticFunction == "N_");
    // Untouched POSIX fields keep their own defaults, not the GNU values.
    assert(readerGnu.i18n.posixSet == "1");

    // POSIX catgets, including the optional posix_file field.
    I18nSettings posix;
    posix.type = I18nType.posix;
    posix.posixFile = "my_catalog";
    posix.posixSet = "2";
    string textPosix = new ProjectWriter().generate(rootsNone, posix);
    auto readerPosix = new Reader(textPosix);
    readerPosix.readProject();
    assert(readerPosix.i18n.type == I18nType.posix);
    assert(readerPosix.i18n.posixInclude == ""); // untouched default
    assert(readerPosix.i18n.posixFile == "my_catalog");
    assert(readerPosix.i18n.posixSet == "2");

    // posix_file omitted entirely (FLTK only writes it when non-empty).
    I18nSettings posixNoFile;
    posixNoFile.type = I18nType.posix;
    string textPosixNoFile = new ProjectWriter().generate(rootsNone, posixNoFile);
    assert(!textPosixNoFile.canFind("i18n_pos_file"));
}

unittest
{
    // `fluid.shell_command`'s own `ToolStore.project` persistence:
    // `generate()`'s default (empty array) emits no `shell_commands`
    // block at all, and a real project-stored command round-trips
    // losslessly through `.fl` text -- `ToolStore.user` entries are
    // deliberately never written here (they're not this project's own
    // data to begin with), matching `writeShellCommandsBlock()`'s own
    // storage filter.
    import fluid.project_reader : Reader;
    import fluid.shell_command : ShellCommand, ShellCondition, ToolStore;
    import fluid.shell_process : shellSaveProject, shellSaveStrings;
    import fl.enumerations : stateCtrl;
    import std.algorithm : canFind;

    auto rootsNone = new Reader("version 1.0000\nFunction {} {open\n} {\n}\n").readProject();

    // No shell commands at all -- generate() must not emit the block.
    string textNone = new ProjectWriter().generate(rootsNone);
    assert(!textNone.canFind("shell_commands"));

    // A ToolStore.user entry is never written to the project file.
    auto userCmd = new ShellCommand("User Only");
    userCmd.storage = ToolStore.user;
    string textUserOnly = new ProjectWriter().generate(rootsNone, I18nSettings.init, [userCmd]);
    assert(!textUserOnly.canFind("shell_commands"));

    // A real ToolStore.project entry round-trips every field.
    auto cmd = new ShellCommand();
    cmd.storage = ToolStore.project;
    cmd.name = "Build";
    cmd.label = "&Build";
    cmd.shortcut = stateCtrl + 'b';
    cmd.condition = ShellCondition.uxOnly;
    cmd.command = "dmd @CODEFILE_NAME@";
    cmd.flags = shellSaveProject | shellSaveStrings;

    string text = new ProjectWriter().generate(rootsNone, I18nSettings.init, [userCmd, cmd]);
    assert(text.canFind("shell_commands"));

    auto reader = new Reader(text);
    reader.readProject();
    assert(reader.shellCommands.length == 1); // the ToolStore.user entry never round-trips
    auto back = reader.shellCommands[0];
    assert(back.name == "Build");
    assert(back.label == "&Build");
    assert(back.shortcut == stateCtrl + 'b');
    assert(back.condition == ShellCondition.uxOnly);
    assert(back.command == "dmd @CODEFILE_NAME@");
    assert(back.flags == (shellSaveProject | shellSaveStrings));
    assert(back.storage == ToolStore.project);
}

unittest
{
    // `MenuItemNode.headline_` round-trips through `.fl` text as a bare
    // "headline" flag, matching FLTK's `Menu_Item_Node::headline()`
    // -- distinct storage from `hotspotFlag`'s own "divider" reuse of
    // the same underlying field, both attached to the same MenuItem.
    import fluid.project_reader : Reader;
    import fluid.menu_item_node : MenuItemNode;

    string source = "version 1.0000\n"
        ~ "Function {} {open\n} {\n"
        ~ "  Menu_Button menu {\n"
        ~ "    xywh {0 0 100 25}\n"
        ~ "  } {\n"
        ~ "    MenuItem plain {\n"
        ~ "      label Plain\n"
        ~ "    }\n"
        ~ "    MenuItem section {\n"
        ~ "      label Section\n"
        ~ "      headline\n"
        ~ "      divider\n"
        ~ "    }\n"
        ~ "  }\n"
        ~ "}\n";

    auto roots1 = new Reader(source).readProject();
    auto text2 = new ProjectWriter().generate(roots1);
    auto roots2 = new Reader(text2).readProject();

    auto fn1 = cast(FunctionNode) roots1[0];
    auto fn2 = cast(FunctionNode) roots2[0];
    auto menu1 = fn1.children[0];
    auto menu2 = fn2.children[0];

    auto plain1 = cast(MenuItemNode) menu1.children[0];
    auto plain2 = cast(MenuItemNode) menu2.children[0];
    assert(!plain1.headline_ && !plain2.headline_);
    assert(!plain1.hotspotFlag && !plain2.hotspotFlag);

    auto section1 = cast(MenuItemNode) menu1.children[1];
    auto section2 = cast(MenuItemNode) menu2.children[1];
    assert(section1.headline_ && section2.headline_);
    assert(section1.hotspotFlag && section2.hotspotFlag); // "divider"
}

unittest
{
    // `generate()`'s own `includeUid` parameter -- see
    // `fluid.node.Node.uid`'s and this parameter's own doc comments.
    // Default: never written, matching every pre-existing caller's
    // byte-identical output.
    import fluid.project_reader : Reader;

    string source = "version 1.0000\n"
        ~ "Function {} {open\n} {\n"
        ~ "  Fl_Box b {\n"
        ~ "    xywh {0 0 10 10}\n"
        ~ "  }\n"
        ~ "}\n";
    // A `uid` *property line* specifically -- plain `canFind("uid ")`
    // has a real false-positive here: the header comment's own "fldtk
    // fluid (Fast..." already contains "uid " as a substring of
    // "fluid ".
    import std.string : lineSplitter, strip, startsWith;
    static bool hasUidLine(string text)
    {
        foreach (line; text.lineSplitter())
            if (line.strip().startsWith("uid "))
                return true;
        return false;
    }

    auto roots = new Reader(source).readProject();
    string withoutUid = new ProjectWriter().generate(roots);
    assert(!hasUidLine(withoutUid));

    // `includeUid: true` writes it, and a reparse of that text preserves
    // the exact same id -- the actual property `restoreFromText()`
    // relies on to match a window across an undo/redo reparse by real
    // identity instead of ordinal position.
    string withUid = new ProjectWriter().generate(roots, I18nSettings.init, [], "", null, true);
    assert(hasUidLine(withUid));

    auto roots2 = new Reader(withUid).readProject();
    auto fn1 = cast(FunctionNode) roots[0];
    auto fn2 = cast(FunctionNode) roots2[0];
    assert(fn1.children[0].uid == fn2.children[0].uid);
    assert(fn1.uid == fn2.uid); // the Function root itself round-trips too
}

unittest
{
    // Project-level flags in the leading Options block: `use_FL_COMMAND`
    // round-trips as a bare keyword, defaults write nothing, and the
    // C/C++-only bare flags FLTK writes are consumed without
    // swallowing the token after them.
    import fluid.project_reader : Reader;
    import fluid.project_settings : ProjectSettings;
    import std.algorithm : canFind;

    auto roots = new Reader("version 1.0000\nFunction {} {open\n} {\n}\n").readProject();

    string off = new ProjectWriter().generate(roots);
    assert(!off.canFind("use_FL_COMMAND"));

    ProjectSettings on;
    on.useFlCommand = true;
    string text = new ProjectWriter().generate(roots, I18nSettings.init, [], "", null, false, false, on);
    assert(text.canFind("\nuse_FL_COMMAND\n"));
    auto reader = new Reader(text);
    auto reread = reader.readProject();
    assert(reader.settings.useFlCommand);
    assert(reread.length == 1);

    auto offReader = new Reader(off);
    offReader.readProject();
    assert(!offReader.settings.useFlCommand);

    // A file as real Fluid writes it: bare flags before the i18n and
    // code_name Options, then the first node.
    auto realStyleReader = new Reader("version 1.0000\ndo_not_include_H_from_C\nuse_FL_COMMAND\n"
        ~ "utf8_in_src\navoid_early_includes\ncode_name {out.cxx}\nFunction {} {open\n} {\n}\n");
    auto realStyleRoots = realStyleReader.readProject();
    assert(realStyleReader.settings.useFlCommand);
    assert(realStyleReader.codeFileName == "out.cxx");
    assert(realStyleRoots.length == 1);
}

unittest
{
    // A class's base class survives a save/load round trip.
    import fluid.project_reader : Reader;
    import std.algorithm : canFind;

    auto roots = new Reader("version 1.0000\nclass Foo {open : Fl_Group\n} {\n"
        ~ "  Function {make()} {open\n  } {\n  }\n}\n").readProject();
    auto cn = cast(ClassNode) roots[0];
    assert(cn !is null && cn.baseClass == "Fl_Group");

    string text = new ProjectWriter().generate(roots);
    assert(text.canFind("\n    : {Fl_Group}\n"));
    auto reread = new Reader(text).readProject();
    auto cn2 = cast(ClassNode) reread[0];
    assert(cn2 !is null && cn2.baseClass == "Fl_Group");

    // A class with no base class writes no `:` line.
    auto plain = new Reader("version 1.0000\nclass Bar {\n} {\n}\n").readProject();
    assert(!new ProjectWriter().generate(plain).canFind(" : "));
}

unittest
{
    // A class attribute (FLTK's `Class_Node::prefix()`) is the extra word
    // before the class name; it round-trips and is emitted before `class`.
    import fluid.project_reader : Reader;
    import fluid.code_writer : Writer;
    import std.algorithm : canFind;

    auto roots = new Reader("version 1.0000\nclass final Foo {open : Fl_Group\n} {\n"
        ~ "  Function {make()} {open\n  } {\n  }\n}\n"
        ~ "class {deprecated(\"old\")} Bar {\n} {\n}\n"
        ~ "class Plain {open : Fl_Group\n} {\n}\n").readProject();
    assert(roots.length == 3);
    auto foo = cast(ClassNode) roots[0];
    auto bar = cast(ClassNode) roots[1];
    auto plain = cast(ClassNode) roots[2];
    assert(foo.instanceName == "Foo" && foo.prefix == "final" && foo.baseClass == "Fl_Group");
    assert(bar.instanceName == "Bar" && bar.prefix == "deprecated(\"old\")");
    assert(plain.prefix == "");

    string text = new ProjectWriter().generate(roots);
    assert(text.canFind("class final Foo\n"));
    assert(text.canFind("class deprecated(\"old\") Bar\n"));
    assert(text.canFind("class Plain\n"));
    auto again = new Reader(text).readProject();
    assert((cast(ClassNode) again[0]).prefix == "final" && (cast(ClassNode) again[1]).prefix == "deprecated(\"old\")");

    string d = new Writer().generate(roots);
    assert(d.canFind("final class Foo : Group"));
    assert(d.canFind("deprecated(\"old\") class Bar"));
    assert(d.canFind("\nclass Plain : Group"));
}

unittest
{
    // GNU-style brace layout (see this module's top comment): every
    // property/children group opens with a `{` on its own line, indented
    // one level beyond the node header, contents one level deeper still,
    // closing `}` aligned with its `{`. Byte-exact on purpose -- this
    // *is* the formatting contract. The K&R-style input (also what
    // hand-edited or older `.fl` files look like) must still be read
    // and normalized.
    import fluid.project_reader : Reader;

    string source = "version 1.0000\n"
        ~ "Function {} {\n"
        ~ "  comment {hi there}\n"
        ~ "  selected\n"
        ~ "} {\n"
        ~ "  Window {} {\n"
        ~ "    label {B1-4}\n"
        ~ "    xywh {0 0 187 180}\n"
        ~ "  } {\n"
        ~ "    Group {} {\n"
        ~ "      xywh {15 15 80 128}\n"
        ~ "    } {\n"
        ~ "      Button {} {\n"
        ~ "        label {b&1}\n"
        ~ "        xywh {15 15 80 32}\n"
        ~ "      }\n"
        ~ "    }\n"
        ~ "    LightButton {} {\n"
        ~ "      label {&l}\n"
        ~ "      xywh {104 34 78 22}\n"
        ~ "    }\n"
        ~ "  }\n"
        ~ "}\n";

    string expected = "# data file for fldtk fluid (Fast Light User Interface Designer)\n"
        ~ "version 1.0000\n"
        ~ "Function {}\n"
        ~ "  {\n"
        ~ "    comment {hi there}\n"
        ~ "  }\n"
        ~ "  {\n"
        ~ "    Window {}\n"
        ~ "      {\n"
        ~ "        label {B1-4}\n"
        ~ "        xywh {0 0 187 180}\n"
        ~ "      }\n"
        ~ "      {\n"
        ~ "        Group {}\n"
        ~ "          {\n"
        ~ "            xywh {15 15 80 128}\n"
        ~ "          }\n"
        ~ "          {\n"
        ~ "            Button {}\n"
        ~ "              {\n"
        ~ "                label {b&1}\n"
        ~ "                xywh {15 15 80 32}\n"
        ~ "              }\n"
        ~ "          }\n"
        ~ "        LightButton {}\n"
        ~ "          {\n"
        ~ "            label {&l}\n"
        ~ "            xywh {104 34 78 22}\n"
        ~ "          }\n"
        ~ "      }\n"
        ~ "  }\n";

    auto roots = new Reader(source).readProject();
    string text = new ProjectWriter().generate(roots);
    // `selected` on the Function is editor state and round-trips too.
    text = text.replace("    comment {hi there}\n    selected\n", "    comment {hi there}\n");
    assert(text == expected, text);

    // The new layout reads back to the same tree.
    auto roots2 = new Reader(text).readProject();
    assert(new ProjectWriter().generate(roots2) == text);
}
