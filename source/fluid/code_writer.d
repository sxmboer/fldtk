/*
 * Tree -> D source. Ported from FLTK's `fluid::io::Code_Writer`
 * (`fluid/io/Code_Writer.h`/`.cxx`), but deliberately much smaller --
 * and, since the fldtk-native `.fl` dialect's `setup`/`callback`/`code`
 * blocks already contain literal D (not C++ needing mechanical
 * translation, see `FLUID_DIALECT.md`'s "dialect pivot" section), there
 * is no C++-to-D transpiler layer here at all anymore: the writer's job
 * is tree-assembly and name-wiring, emitting most raw code text close
 * to verbatim.
 *
 * No header/.cxx split (a single-file D program per `.fl`), no
 * write-once #include dedup (a fixed small set of `import` lines
 * covers everything), and no callback-trampoline-plus-cast machinery:
 * FLTK's generated `((Fl_Callback*)cb_x)` + a separate top-level
 * `static void cb_x(Fl_Slider*, void*)` function exists purely because
 * C++ needs a same-signature free-function pointer decoupled from any
 * closure state. This writer just emits a plain delegate literal
 * inline (`.callback((raw) { auto o = cast(X) raw; ... });`), matching
 * CONVENTIONS.md's "Callbacks are D delegates" convention.
 *
 * **The "o" convention**: every callback/`setup` body written in a
 * `.fl` file refers to "the widget this code concerns" as a bare `o`,
 * matching FLTK's own documented `Fl_Callback` parameter-naming
 * convention (`void (*)(Fl_Widget *o, void *v)`) -- see the session
 * notes on "o vs this" for the full reasoning. Two different physical
 * contexts both use this same convention, handled differently here:
 *   - Inside `setup` (construction-time code, attached to a widget's
 *     own property list): `o` means "this widget's own variable",
 *     which already has a real, distinct name (`v` below) --
 *     substituted via `translateOwnSlot()`.
 *   - Inside a `callback { ... }` property: `o` means "the freshly cast closure
 *     local" that this writer itself introduces (`auto o = cast(X)
 *     raw;`) -- already correct verbatim, since the cast variable is
 *     deliberately *named* `o` to match what the `.fl` author wrote, no
 *     substitution needed. The closure's own *outer*, `Widget`-typed
 *     parameter is named `raw` specifically so it doesn't collide with
 *     that inner `o` (D forbids a nested declaration shadowing its own
 *     enclosing lambda parameter).
   - Inside a `callback { ... }` property, a named Function is called
 *     like any other function: `buttonCB(o);`. A callback field always
 *     holds code; a file whose callback field still holds just a name is
 *     converted when it is read (see `fluid.node`'s `callbackFromName()`).
 *
 * Property translation (`translateBoxtype()`/`translateColor()`/etc.)
 * is intentionally small and conservative -- every numeric constant
 * table here is grounded directly in `source/fl/enumerations.d`'s (and
 * the relevant widget module's) real current values, not recalled from
 * memory (this project has been bitten by exactly that mistake before
 * -- see the "Slider type() constant transcription" memory note).
 * `translateColor()`/`translateFont()` take a raw *numeric* `.fl`
 * property, so a `cast(Foo) N` fallback for a value with no name in
 * the lookup table is always correct (if less pretty) -- the number
 * itself is the ground truth either way.
 * `translateBoxtype()`/`translateTypeWord()`/`translateLabeltype()`
 * are different: they take a *keyword string*, which has no numeric
 * fallback that could be correct -- an unrecognized keyword means the
 * `.fl` source names something this table doesn't know, so these three
 * throw instead (matching `emitSnippetLines()`'s own "hard, loud
 * failure" precedent) rather than silently emitting a plausible-looking
 * but wrong default plus an inline TODO comment nobody reads until the
 * generated code already looks wrong on screen.
 */
module fluid.code_writer;

import std.array : appender, Appender, join;
import std.format : format;
import std.string : split, strip, lineSplitter, indexOf, lastIndexOf, toLower, startsWith, replace, stripRight;
import std.regex : regex;
import std.path : buildPath, extension, baseName, absolutePath, relativePath, dirName, buildNormalizedPath;
import std.file : read, exists;

import fl.image : Image, RGBImage;
import fl.pixmap : Pixmap;
import fl.bitmap : Bitmap;
import fl.png_image : PngImage;
import fl.jpeg_image : JpegImage;
import fl.gif_image : GifImage;
import fl.bmp_image : BMPImage;
import fl.xpm_image : XPMImage;
import fl.xbm_image : XBMImage;
import fl.ico_image : ICOImage;
import fl.svg_image : SvgImage;
import fl.pnm_image : PNMImage;

import fluid.node;
import fluid.widget_node;
import fluid.window_node;
import fluid.group_node;
import fluid.function_node;
import fluid.code_node;
import fluid.conditional_node;
import fluid.class_node : ClassNode;
import fluid.grid_node;
import fluid.flex_node;
import fluid.menu_item_node;
import fluid.code_highlight : renameIdentifier;
import fluid.comment_node : CommentNode;
import fluid.i18n : I18nSettings, I18nType;
import fluid.project_settings : ProjectSettings;
import fluid.mergeback : Crc32, Tag, formatTag;
import fluid.subtypes : isDoubleWindow, subtypeFor, subtypePicksClass;
import fl.enumerations : stateAlt, stateCommand, stateControl, stateCtrl, stateMeta, stateShift;

// Grounded directly in source/fl/enumerations.d and each widget's own
// module (checked against source, not recalled from memory -- see this
// module's own doc comment). Covers all 68 real
// `Boxtype` values, matching `instantiate.d`'s own
// `boxtypeMap` (parsing/codegen here vs. live-
// canvas apply/the Style panel's dropdown there) -- otherwise a
// real, pre-existing sample using `ENGRAVED_FRAME` (a genuine FLTK-
// faithful boxtype) would fail to generate code at all with "unknown box
// keyword". Regenerate this list the same mechanical way if
// `Boxtype` ever gains a new member: `Boxtype`'s own enum member list
// (`source/fl/enumerations.d`) minus the 2 non-selectable sentinels
// (`freeBoxtype`/`maxBoxtype`), each name converted from camelCase to
// FLTK's own `UPPER_SNAKE_CASE` spelling.
private immutable string[string] boxtypeMap = [
    "NO_BOX": "Boxtype.noBox",
    "FLAT_BOX": "Boxtype.flatBox",
    "UP_BOX": "Boxtype.upBox",
    "DOWN_BOX": "Boxtype.downBox",
    "UP_FRAME": "Boxtype.upFrame",
    "DOWN_FRAME": "Boxtype.downFrame",
    "THIN_UP_BOX": "Boxtype.thinUpBox",
    "THIN_DOWN_BOX": "Boxtype.thinDownBox",
    "THIN_UP_FRAME": "Boxtype.thinUpFrame",
    "THIN_DOWN_FRAME": "Boxtype.thinDownFrame",
    "ENGRAVED_BOX": "Boxtype.engravedBox",
    "EMBOSSED_BOX": "Boxtype.embossedBox",
    "ENGRAVED_FRAME": "Boxtype.engravedFrame",
    "EMBOSSED_FRAME": "Boxtype.embossedFrame",
    "BORDER_BOX": "Boxtype.borderBox",
    "SHADOW_BOX": "Boxtype.shadowBox",
    "BORDER_FRAME": "Boxtype.borderFrame",
    "SHADOW_FRAME": "Boxtype.shadowFrame",
    "ROUNDED_BOX": "Boxtype.roundedBox",
    "RSHADOW_BOX": "Boxtype.rshadowBox",
    "ROUNDED_FRAME": "Boxtype.roundedFrame",
    "RFLAT_BOX": "Boxtype.rflatBox",
    "ROUND_UP_BOX": "Boxtype.roundUpBox",
    "ROUND_DOWN_BOX": "Boxtype.roundDownBox",
    "DIAMOND_UP_BOX": "Boxtype.diamondUpBox",
    "DIAMOND_DOWN_BOX": "Boxtype.diamondDownBox",
    "OVAL_BOX": "Boxtype.ovalBox",
    "OSHADOW_BOX": "Boxtype.oshadowBox",
    "OVAL_FRAME": "Boxtype.ovalFrame",
    "OFLAT_BOX": "Boxtype.oflatBox",
    "PLASTIC_UP_BOX": "Boxtype.plasticUpBox",
    "PLASTIC_DOWN_BOX": "Boxtype.plasticDownBox",
    "PLASTIC_UP_FRAME": "Boxtype.plasticUpFrame",
    "PLASTIC_DOWN_FRAME": "Boxtype.plasticDownFrame",
    "PLASTIC_THIN_UP_BOX": "Boxtype.plasticThinUpBox",
    "PLASTIC_THIN_DOWN_BOX": "Boxtype.plasticThinDownBox",
    "PLASTIC_ROUND_UP_BOX": "Boxtype.plasticRoundUpBox",
    "PLASTIC_ROUND_DOWN_BOX": "Boxtype.plasticRoundDownBox",
    "GTK_UP_BOX": "Boxtype.gtkUpBox",
    "GTK_DOWN_BOX": "Boxtype.gtkDownBox",
    "GTK_UP_FRAME": "Boxtype.gtkUpFrame",
    "GTK_DOWN_FRAME": "Boxtype.gtkDownFrame",
    "GTK_THIN_UP_BOX": "Boxtype.gtkThinUpBox",
    "GTK_THIN_DOWN_BOX": "Boxtype.gtkThinDownBox",
    "GTK_THIN_UP_FRAME": "Boxtype.gtkThinUpFrame",
    "GTK_THIN_DOWN_FRAME": "Boxtype.gtkThinDownFrame",
    "GTK_ROUND_UP_BOX": "Boxtype.gtkRoundUpBox",
    "GTK_ROUND_DOWN_BOX": "Boxtype.gtkRoundDownBox",
    "GLEAM_UP_BOX": "Boxtype.gleamUpBox",
    "GLEAM_DOWN_BOX": "Boxtype.gleamDownBox",
    "GLEAM_UP_FRAME": "Boxtype.gleamUpFrame",
    "GLEAM_DOWN_FRAME": "Boxtype.gleamDownFrame",
    "GLEAM_THIN_UP_BOX": "Boxtype.gleamThinUpBox",
    "GLEAM_THIN_DOWN_BOX": "Boxtype.gleamThinDownBox",
    "GLEAM_ROUND_UP_BOX": "Boxtype.gleamRoundUpBox",
    "GLEAM_ROUND_DOWN_BOX": "Boxtype.gleamRoundDownBox",
    "OXY_UP_BOX": "Boxtype.oxyUpBox",
    "OXY_DOWN_BOX": "Boxtype.oxyDownBox",
    "OXY_UP_FRAME": "Boxtype.oxyUpFrame",
    "OXY_DOWN_FRAME": "Boxtype.oxyDownFrame",
    "OXY_THIN_UP_BOX": "Boxtype.oxyThinUpBox",
    "OXY_THIN_DOWN_BOX": "Boxtype.oxyThinDownBox",
    "OXY_THIN_UP_FRAME": "Boxtype.oxyThinUpFrame",
    "OXY_THIN_DOWN_FRAME": "Boxtype.oxyThinDownFrame",
    "OXY_ROUND_UP_BOX": "Boxtype.oxyRoundUpBox",
    "OXY_ROUND_DOWN_BOX": "Boxtype.oxyRoundDownBox",
    "OXY_BUTTON_UP_BOX": "Boxtype.oxyButtonUpBox",
    "OXY_BUTTON_DOWN_BOX": "Boxtype.oxyButtonDownBox",
];

// Font index -> name, matching fl.enumerations.d's Font enum exactly
// (the first 16 built-in faces; a registered/custom font beyond that
// has no static name to look up here).
private immutable string[int] fontMap = [
    0: "helvetica", 1: "helveticaBold", 2: "helveticaItalic", 3: "helveticaBoldItalic",
    4: "courier", 5: "courierBold", 6: "courierItalic", 7: "courierBoldItalic",
    8: "times", 9: "timesBold", 10: "timesItalic", 11: "timesBoldItalic",
    12: "symbol", 13: "screen", 14: "screenBold", 15: "zapfDingbats",
];

// The colors `fl.enumerations` names, as FLTK's
// `Widget_Node::write_color()` (`fluid/nodes/Widget_Node.cxx`) names them;
// any other index is written as `cast(Color) N`. `selectionColor` is
// written qualified, because inside a class derived from a widget it would name the
// widget's own `selectionColor()` method.
private immutable string[int] colorNameMap = [
    0: "foregroundColor", 7: "background2Color", 8: "inactiveColor",
    15: "fl.enumerations.selectionColor",
    32: "gray0", 39: "dark3", 45: "dark2", 47: "dark1",
    49: "backgroundColor", 50: "light1", 52: "light2", 54: "light3",
    56: "black", 88: "red", 63: "green", 95: "yellow", 216: "blue",
    248: "magenta", 223: "cyan", 72: "darkRed", 60: "darkGreen",
    76: "darkYellow", 136: "darkBlue", 152: "darkMagenta", 140: "darkCyan",
    255: "white",
];

// `type` keyword -> D `.type(...)` argument. Grounded in
// source/fl/button.d (`radioButton = 102`), source/fl/enumerations.d's
// `InputType` alias (`outputMultiline`), source/fl/slider.d
// (`horSlider`/`vertFillSlider`/etc.), source/fl/valuator.d
// (`horizontalType`), source/fl/counter.d (`simpleCounter`),
// source/fl/spinner.d (`inputFloat`), source/fl/dial.d
// (`lineDial`/`fillDial`) -- checked against source, not recalled from
// memory. Widget-class-specific in principle (a future widget with a
// same-named, differently-valued "type" keyword would need this table
// split per class), but no collision has been hit yet.
private immutable string[string] typeWordMap = [
    "Radio": "radioButton",
    "Multiline": "outputMultiline",
    "Horizontal": "horizontalType",
    "Vert Fill": "vertFillSlider",
    "Vert Knob": "vertNiceSlider",
    "Horz Fill": "horFillSlider",
    "Horz Knob": "horNiceSlider",
    "Simple": "simpleCounter",
    "Float": "inputFloat",
    "Line": "lineDial",
    "Fill": "fillDial",
    // source/fl/flex.d's flexHorizontal/flexVertical, matching
    // FLTK's Group_Node.cxx flex_type_menu (HORIZONTAL/VERTICAL).
    "HORIZONTAL": "flexHorizontal",
    "VERTICAL": "flexVertical",
    // source/fl/browser_.d's holdBrowser (Fl_Browser's own FL_HOLD_BROWSER).
    "Hold": "holdBrowser",
    // source/fl/browser_.d's multiBrowser (Fl_Browser's own FL_MULTI_BROWSER).
    "Multi": "multiBrowser",
    // source/fl/button.d's toggleButton (Fl_Button's own FL_TOGGLE_BUTTON).
    "Toggle": "toggleButton",
];

private immutable string[string] labeltypeMap = [
    "NORMAL_LABEL": "Labeltype.normalLabel",
    "NO_LABEL": "Labeltype.noLabel",
    "SHADOW_LABEL": "Labeltype.shadowLabel",
    "ENGRAVED_LABEL": "Labeltype.engravedLabel",
    "EMBOSSED_LABEL": "Labeltype.embossedLabel",
];

private enum alignInsideBit = 0x10; // fl.enumerations.alignInside

/// The fldtk folder (`fluid.dub_project.fldtkFolder()`) as
/// `generate()`'s dub single-file-package header names it for a file in
/// `dir` (the generated file's folder, `Writer.outputDir`), through
/// `fluid.dub_project.fldtkDubPath()`. `"."` when no fldtk folder is
/// found: a starting point to edit by hand, since the header is an
/// option and not needed for the code itself.
private string fldtkPathFrom(string dir)
{
    import fluid.dub_project : fldtkDubPath, fldtkFolder;

    string root = fldtkFolder(dir);
    return root is null ? "." : fldtkDubPath(dir, root);
}

class Writer
{
    private Appender!string buf;
    private int indent_;
    private string[string] nameMap; // .fl instance name -> D identifier (verbatim; identity map)

    /// The `.fl` file's own directory for this `generate()` call --
    /// resolves every `WidgetNode.imageFilename`/
    /// `.deimageFilename` relative to it, matching FLTK's own
    /// `Fluid.proj.enter_project_dir()` convention (`Data_Node::
    /// write_code1()`). A field rather than a threaded parameter since
    /// it's needed several calls deep into the widget tree (inside
    /// `writeCommonProps()`, called from every `WidgetNode`-family
    /// writer) -- the same shape `inMainFunction_` already uses for a
    /// similar "context flag needed deep in the call tree" need,
    /// reset once per `generate()` call alongside the others below.
    private string projectDir_;

    /// The folder the generated file goes to, for the dub header's
    /// fldtk path, which dub reads relative to the `.d` file. Empty
    /// means the project's folder (`projectDir_`). Set by the callers
    /// that write a file (`fluid.compile`, `gui_main.d`'s
    /// `generateCodeFile()`); kept across `generate()` calls.
    string outputDir;

    /// Project-wide i18n settings (`fluid/proj/i18n` port)
    /// -- consulted by `i18nWrap()` to wrap every emitted label/tooltip
    /// literal in the configured translation call. Defaults to
    /// `I18nSettings.init` (`I18nType.none`), so every existing caller
    /// that never had an i18n concept to pass keeps emitting plain
    /// quoted string literals, byte-identical to before this field
    /// existed.
    private I18nSettings i18n_;

    /// Whether to emit a leading dub single-file-package header comment
    /// (a deliberate fldtk-only convenience): `/+ dub.sdl:` naming
    /// `dependency "fldtk" path="..."`, `subConfiguration "fldtk"
    /// "program"` and `stringImportPaths` (the design's folder, for a
    /// Code node's `import("file")`), then `+/`, letting the generated `.d` file be built
    /// directly via `dub build --single <file>.d`/`dub run --single
    /// <file>.d` with zero manually-typed linker flags -- dub resolves
    /// fldtk's own `libs`/`importPaths`/platform configuration as a
    /// normal dependency instead. Off by default (`Settings -> Project`'s
    /// own checkbox, `settings_panel.fl`'s `dubHeaderButton`, defaults
    /// unchecked too) so every existing generated file stays
    /// byte-identical unless a user opts in. See `generate()`'s own use
    /// of this field for the actual emission and path computation.
    private bool dubHeader_;

    /// Project-wide code-generation flags (`fluid.project_settings`);
    /// currently only `useFlCommand`, consulted by `shortcutExpression()`
    /// at every widget/menu-item shortcut emission site.
    private ProjectSettings settings_;

    /// Offset in `buf` just past the most recent MergeBack tag line (0
    /// before the first): `tag()` checksums `buf.data[tagStart_ .. $]`.
    private size_t tagStart_;

    /// Running per-`generate()`-call counter, incremented once per
    /// `i18nWrap()` call -- backs the message-catalog index a POSIX
    /// `catgets()` call needs. Deliberately *not* FLTK's own
    /// `Node::msgnum()` (a whole-project backward walk over FLTK's
    /// flat doubly-linked-list `Node` model, counting preceding
    /// labels/tooltips by tree position) -- this port's own tree-
    /// shaped `Node` has no `prev`-sibling chain to walk the same way,
    /// and POSIX catgets only needs these numbers to be unique and
    /// stable within one generated file, not to match FLTK's own
    /// numbering scheme byte-for-byte.
    private int msgnum_;

    /// `writeOneImage()`'s own local byte-array variable disambiguator:
    /// the fixed name `imgBytes`/
    /// `deimgBytes` would shadow itself once a second image's own generated
    /// statements land in a scope still nested inside the first image's
    /// declaring scope (widget-constructor blocks nest per child here,
    /// as `settings_panel.fl`'s 8 tab icons in one file do), which dmd
    /// rejects outright (shadowing is an error, not a warning,
    /// under this project's build flags). Suffixed onto the variable
    /// name to guarantee uniqueness regardless of nesting.
    private int imageVarCounter_;

    /// `projectDir` is the `.fl` file's own directory, which widget
    /// image files are read relative to. `i18n` is the project's
    /// `fluid.i18n.I18nSettings` (see that field's own doc comment), and
    /// `settings` its `fluid.project_settings.ProjectSettings`.
    string generate(Node[] roots, string projectDir = ".", I18nSettings i18n = I18nSettings.init,
        bool dubHeader = false, ProjectSettings settings = ProjectSettings.init)
    {
        buf = appender!string();
        nameMap = null;
        projectDir_ = projectDir;
        i18n_ = i18n;
        dubHeader_ = dubHeader;
        settings_ = settings;
        tagStart_ = 0;
        if (settings.writeMergebackData)
            ensureUniqueUids(roots);
        msgnum_ = 0;
        anonNames = null;
        groupDepth_ = 0;
        inMainFunction_ = false;
        indent_ = 0;

        collectNames(roots);
        clearSpans(roots);

        // The top-level nodes are written in tree order. Comment nodes
        // before every other node are the file's header and go above the
        // imports.
        size_t headerEnd = 0;
        while (headerEnd < roots.length && cast(CommentNode) roots[headerEnd])
            headerEnd++;

        // The dub header goes first of all: dub only reads it as the
        // first thing in the file. `program` is fldtk's configuration
        // for programs (see fldtk's dub.sdl): the program links the
        // library in the fldtk folder and finds it there when it runs.
        // `stringImportPaths` names the design's folder, so a Code
        // node's `import("file")` finds files next to the `.fl` file.
        if (dubHeader_)
        {
            import fluid.dub_project : dubPath;

            string dir = outputDir.length ? outputDir : projectDir_;
            buf.put(format("/+ dub.sdl:\ndependency \"fldtk\" path=\"%s\"\nsubConfiguration \"fldtk\" \"program\"\n"
                ~ "stringImportPaths \"%s\"\n+/\n",
                fldtkPathFrom(dir), dubPath(dir, projectDir_)));
        }

        foreach (cn; roots[0 .. headerEnd])
            writeRootComment(cast(CommentNode) cn);
        buf.put("import fl;\n");
        foreach (m; collectClassOverrideImports(roots, localClassNames(roots), moduleCodeTexts(roots)))
            // Selective, not whole-module: a plain "import CubeView;"
            // is genuinely ambiguous when the module and the class it
            // exports share the exact same name (dmd rejects it with
            // "import CubeView.CubeView is
            // used as a type") -- D resolves the bare identifier to the
            // *module* itself, not the class, unless the class symbol
            // is explicitly pulled into scope this way.
            buf.put("import " ~ m ~ " : " ~ m ~ ";\n");
        // A single `import std;` covers every Phobos symbol generated
        // code actually calls (`format`/`writef`/`writefln`/`writeln`/
        // `toStringz`/`to`) -- Phobos's own `std/package.d` `public
        // import`s each of those submodules, confirmed with a real
        // `dmd -run` test, so a single wildcard import covers all of
        // them without four separate
        // selective imports, one per submodule.
        //
        // Nothing here imports `core.stdc.stdlib : atof` -- every place
        // that writes a numeric
        // property (`writeCommonProps()`'s `minimum`/`maximum`/`step`/
        // `value` handling, the raw string captured straight into the
        // generated literal, e.g. `sl.minimum(0.0);`) emits the value as
        // a literal directly, never a runtime string-to-double parse,
        // so there is no real call site for that import to serve.
        //
        // `fl.group.Group`/`fl.clock.Clock` vs `std.algorithm.
        // iteration.Group`/`std.datetime.systime.Clock`: the wildcard `import
        // std;` below pulls in `std.algorithm.iteration.Group`/
        // `std.datetime.systime.Clock`, which share their bare names
        // with two of this port's own `fl.*` classes (also reached via
        // the wildcard `import fl;` just above) -- any generated file
        // naming one would fail to compile with a "matches conflicting
        // symbols" error, since two different wildcard-imported modules
        // would both export the name. Fixed at the source rather than
        // papered over with a selective re-import at this spot:
        // `fl.group.Group`/`fl.clock.Clock` are renamed
        // to `FlGroup`/`FlClock` (the one deliberate exception to
        // this port's usual "drop the `Fl_`/`Fl` prefix" convention --
        // see those two modules' own doc comments), so generated code
        // never names the colliding symbol in the first place.
        // `className()` already emits `FlGroup`/`FlClock`, not `Group`/
        // `Clock`, for a plain `.fl`-dialect "Group"/"Clock" node.
        buf.put("import std;\n\n");
        writeI18nPrologue();
        // The module-level widget variables go before the first Function
        // or Class, so Code nodes above it (imports, types) come first.
        bool declsWritten;
        void writeWidgetDecls()
        {
            if (declsWritten)
                return;
            declsWritten = true;
            writeDecls(roots);
            if (nameMap.length)
                buf.put("\n");
        }
        foreach (r; roots[headerEnd .. $])
        {
            if (auto comn = cast(CommentNode) r)
                writeRootComment(comn);
            else if (cast(CodeNode) r || cast(ConditionalNode) r)
                writeDeclChild(r);
            else if (auto cn = cast(ClassNode) r)
            {
                writeWidgetDecls();
                writeClassNode(cn);
            }
            else if (auto fn = cast(FunctionNode) r)
            {
                writeWidgetDecls();
                if (fn.instanceName.length == 0)
                    writeFunctionBody(fn);
                else
                    writePlainFunction(fn);
            }
            else
                writeSkippedRoot(r);
        }
        writeWidgetDecls();

        return buf.data;
    }

    /// A top-level Comment node: its text, unless it is switched off for
    /// the source (`not_in_source`).
    private void writeRootComment(CommentNode cn)
    {
        if (!cn.inSource_)
            return;
        immutable start = pos();
        writeCommentText(cn.instanceName);
        spanLeaf(cn, start);
        blank();
    }

    /// A top-level node that has no place at module scope (a widget
    /// outside any Function): reported in a comment instead of vanishing.
    private void writeSkippedRoot(Node skipped)
    {
        line(format("// Skipped: a root-level `%s` node has no valid D module-scope", skipped.typeName));
        line("// destination (only declarations, not statements, are legal there) --");
        line("// move its contents inside a Function instead.");
        if (skipped.instanceName.length)
        {
            line("// Its own text:");
            foreach (l; skipped.instanceName.lineSplitter)
                line("//   " ~ l);
        }
        blank();
    }

    private void line(string s)
    {
        foreach (i; 0 .. indent_)
            buf.put("    ");
        buf.put(s);
        buf.put("\n");
    }

    private void blank()
    {
        buf.put("\n");
    }

    /// Current write position in the generated source, in characters --
    /// backs the `setupSpan`/`finalizeSpan` bookkeeping in
    /// `writeWindowNode()`/`writeGroupNode()`/`writeWidgetNode()`/
    /// `writeMenuOwnerNode()` (see `fluid.node.TextSpan`'s own doc
    /// comment). Matches FLTK's `Code_Writer::code_pos()`
    /// (`(int)code_buffer.tellp()`) -- `Appender!string.data.length` is
    /// the direct D equivalent of an `ostringstream`'s own write cursor.
    private int pos() { return cast(int) buf.data.length; }

    /// Forgets the source positions of every node in `nodes` and below,
    /// so a node this `generate()` doesn't write, or a piece of code it no
    /// longer has, is untracked instead of keeping an old position.
    private static void clearSpans(Node[] nodes)
    {
        foreach (n; nodes)
        {
            n.setupSpan = TextSpan.init;
            n.finalizeSpan = TextSpan.init;
            n.blockSpans = null;
            clearSpans(n.children);
        }
    }

    /// Records a node without children whose code runs from `start` to
    /// here: all of it is setup code, and its finalize span is empty.
    private void spanLeaf(Node n, int start)
    {
        n.setupSpan = TextSpan(start, pos());
        n.finalizeSpan = TextSpan(pos(), pos());
    }

    /// Records the end of a container node's opening code (the node's
    /// comment, its header and opening brace), which began at `start`.
    private void spanOpen(Node n, int start)
    {
        n.setupSpan = TextSpan(start, pos());
    }

    /// Records a container node's closing code, from `start` to here.
    private void spanClose(Node n, int start)
    {
        n.finalizeSpan = TextSpan(start, pos());
    }

    /// Only widget-tree nodes get a "TypeName varname;" module-level
    /// decl. Verbatim naming: the .fl instance name IS the D identifier,
    /// no transformation -- the author writes exactly what they want the
    /// D variable to be called (e.g. "cbInfo"). A Class's subtree is
    /// skipped: its named widgets become fields of the class
    /// (`writeClassFields()`), and its own name is the class's name, not
    /// a variable.
    private void collectNames(Node[] nodes)
    {
        foreach (n; nodes)
        {
            if (cast(ClassNode) n)
                continue;
            if (cast(WidgetNode) n && n.instanceName.length)
                nameMap[n.instanceName] = n.instanceName;
            collectNames(n.children);
        }
    }

    private void writeDecls(Node[] nodes)
    {
        foreach (n; nodes)
        {
            // A Class's widgets are its fields (`writeClassFields()`).
            if (cast(ClassNode) n)
                continue;
            if (auto wn = cast(WidgetNode) n)
                if (wn.instanceName.length)
                    line(format("%s%s %s;", wn.access == Access.private_ ? "private " : "",
                        className(n), n.instanceName));
            writeDecls(n.children);
        }
    }

    /// Emits `immutable ubyte[] name = [ ...bytes... ];`, for
    /// `writeOneImage()` (`WidgetNode.imageFilename`/`.deimageFilename`).
    private void writeByteArrayLiteral(string varName, const(ubyte)[] bytes)
    {
        line(format("immutable ubyte[] %s = [", varName));
        indent_++;
        enum perLine = 20;
        for (size_t i = 0; i < bytes.length; i += perLine)
        {
            auto chunk = bytes[i .. (i + perLine < bytes.length ? i + perLine : bytes.length)];
            auto row = appender!string();
            foreach (b; chunk)
            {
                row.put(format("%d, ", b));
            }
            line(row.data);
        }
        indent_--;
        line("];");
    }

    /// Writes one child at module or class scope: a Code node's text
    /// (an import, a variable, a field, a helper type), a Conditional
    /// node whose children are declarations too, a Comment node, a
    /// Function (a method when `classDepth_` says the code is in a class)
    /// or a Class. Shared by `generate()`'s module-scope loop,
    /// `writeClassNode()` for the class body,
    /// and `writeConditionalDecl()` for its children.
    private void writeDeclChild(Node c)
    {
        if (auto code = cast(CodeNode) c)
        {
            immutable start = pos();
            writeNodeComment(code);
            emitSnippetBlock(code.instanceName);
            spanLeaf(code, start);
            blank();
        }
        else if (auto cond = cast(ConditionalNode) c)
            writeConditionalDecl(cond);
        else if (auto comn = cast(CommentNode) c)
        {
            if (comn.inSource_)
            {
                immutable start = pos();
                writeCommentText(comn.instanceName);
                spanLeaf(comn, start);
                blank();
            }
        }
        else if (auto fn = cast(FunctionNode) c)
        {
            if (classDepth_ > 0)
                writeClassMethod(fn);
            else
                writePlainFunction(fn);
        }
        else if (auto cn = cast(ClassNode) c)
            writeClassNode(cn);
    }

    /// How many class bodies are being written around the current node:
    /// a function there is a method, and a class there is a nested
    /// class.
    private int classDepth_;

    /// `static ` for a class nested in another class: like a nested class
    /// in C++, it needs no instance of the outer class to be created.
    private string nestedClassPrefix()
    {
        return classDepth_ > 0 ? "static " : "";
    }

    /// A Conditional node at module or class scope: its header, then its
    /// children (declarations, through `writeDeclChild()`) inside braces.
    private void writeConditionalDecl(ConditionalNode cond)
    {
        immutable start = pos();
        writeNodeComment(cond);
        line(cond.instanceName ~ " {");
        spanOpen(cond, start);
        indent_++;
        foreach (c; cond.children)
            writeDeclChild(c);
        indent_--;
        immutable closeStart = pos();
        line("}");
        spanClose(cond, closeStart);
        blank();
    }

    /// A Conditional node inside a function or among a window's widgets:
    /// its header, then its children (statements and widgets, through
    /// `writeBodyChild()`) inside braces. Its comment is written by the
    /// caller, `writeWidgetTree()`, as for every node there.
    private void writeConditionalBody(ConditionalNode cond)
    {
        immutable start = pos();
        line(cond.instanceName ~ " {");
        spanOpen(cond, start);
        indent_++;
        foreach (c; cond.children)
            writeBodyChild(c);
        indent_--;
        immutable closeStart = pos();
        line("}");
        spanClose(cond, closeStart);
    }

    /// Writes one child of a function body, of a Conditional node in one,
    /// or of a window or group: a Code node's statements, or anything
    /// else through `writeWidgetTree()`.
    private void writeBodyChild(Node c)
    {
        if (auto code = cast(CodeNode) c)
            writeCodeNode(code);
        else
            writeWidgetTree(c);
    }

    /// A Code node's statements, after its comment, tagged for
    /// merge-back.
    private void writeCodeNode(CodeNode code)
    {
        immutable start = pos();
        writeNodeComment(code);
        writeTaggedBlock(Tag.code, code, code.instanceName);
        spanLeaf(code, start);
    }

    /// FLTK: `Code_Writer::write_i18n_prologue()`. Emits the
    /// project's translation-support declarations once, right after the
    /// file's imports: the configured `#include:` field (a D module
    /// name here, not a C header) as an `import`, wrapped in
    /// `version (<Conditional>)` when a conditional is set, with an
    /// `else` branch defining pass-through fallbacks so the file still
    /// compiles with translation switched off. The C-preprocessor
    /// `#ifdef`/`#ifndef`/`#define` trio maps onto D's `version`/`else`/
    /// ordinary function definition.
    ///
    /// GNU: the fallback defines the configured `gettext` function and
    /// static (`gettext_noop`) function as identity functions. POSIX:
    /// the fallback defines a `catgets` pass-through taking any catalog
    /// argument. The POSIX catalog variable itself (`_catalog` or the
    /// configured catalog name) and its `catopen()` call stay the
    /// program's own to declare, next to the module the include field
    /// names.
    ///
    /// Nothing is emitted for `I18nType.none` or an empty include,
    /// matching FLTK's own gate. A C-style include (`<libintl.h>`,
    /// `"gettext.h"`) is not a D module name and is reported in a
    /// comment instead.
    private void writeI18nPrologue()
    {
        string include, conditional;
        string[] fallback;
        final switch (i18n_.type)
        {
        case I18nType.none:
            return;
        case I18nType.gnu:
            include = i18n_.gnuInclude.strip;
            conditional = i18n_.gnuConditional.strip;
            if (i18n_.gnuFunction.length)
                fallback ~= format("string %s(string text) pure nothrow @nogc @safe { return text; }",
                    i18n_.gnuFunction);
            if (i18n_.gnuStaticFunction.length)
                fallback ~= format("string %s(string text) pure nothrow @nogc @safe { return text; }",
                    i18n_.gnuStaticFunction);
            break;
        case I18nType.posix:
            include = i18n_.posixInclude.strip;
            conditional = i18n_.posixConditional.strip;
            fallback ~= "string catgets(C)(C catalog, int set, int msgid, string text) "
                ~ "pure nothrow @nogc @safe { return text; }";
            break;
        }
        if (include.length == 0)
            return;
        if (include[0] == '<' || include[0] == '"')
        {
            line(format("// Skipped i18n include %s: not a D module name.", include));
            blank();
            return;
        }
        if (conditional.length == 0)
        {
            line(format("import %s;", include));
            blank();
            return;
        }
        line(format("version (%s)", conditional));
        line("{");
        indent_++;
        line(format("import %s;", include));
        indent_--;
        line("}");
        line("else");
        line("{");
        indent_++;
        foreach (f; fallback)
            line(f);
        indent_--;
        line("}");
        blank();
    }

    /// `.fl` files store a shortcut as a plain integer (decimal or
    /// `0x` hex). Returns it as a symbolic D expression via
    /// `shortcutExpression()` under the project's `useFlCommand`
    /// setting, or `raw` unchanged when it isn't an integer literal.
    private string shortcutText(string raw)
    {
        import std.conv : to, ConvException;
        try
        {
            uint v = (raw.startsWith("0x") || raw.startsWith("0X"))
                ? to!uint(raw[2 .. $], 16) : to!uint(raw);
            return shortcutExpression(v, settings_.useFlCommand);
        }
        catch (ConvException)
            return raw;
    }

    /// Wraps `text` (a widget/window/group's own literal label or
    /// tooltip, or a `MenuItem`'s own label too,
    /// see `writeMenuItemLiteral()`'s own doc comment for why the same
    /// wrapping applies there with no extra machinery needed) in the
    /// project's configured translation call. Ported from
    /// FLTK's own inline `switch (Fluid.proj.i18n.type)` blocks in
    /// `Widget_Node::write_code1()`/`write_widget_code()`, collapsed
    /// into one shared helper since every call site does the exact
    /// same three-way dispatch. Returns the plain quoted D string
    /// literal unchanged when `i18n_.type` is `I18nType.none`.
    private string i18nWrap(string text)
    {
        string quoted = format(`"%s"`, dStringEscape(text));
        final switch (i18n_.type)
        {
        case I18nType.none:
            return quoted;
        case I18nType.gnu:
            return format("%s(%s)", i18n_.gnuFunction, quoted);
        case I18nType.posix:
            string catalog = i18n_.posixFile.length ? i18n_.posixFile : "_catalog";
            return format("catgets(%s, %s, %d, %s)", catalog, i18n_.posixSet, ++msgnum_, quoted);
        }
    }

    /// Emits `immutable string[] name = [ ...rows... ];` -- the
    /// `Pixmap`-native counterpart of `writeByteArrayLiteral()`, used
    /// by `writeOneImage()`'s native-representation path for XPM (and
    /// GIF's own `Pixmap`-based decoded form, see that function's own
    /// doc comment).
    private void writeStringArrayLiteral(string varName, const(string)[] rows)
    {
        line(format("immutable string[] %s = [", varName));
        indent_++;
        foreach (row; rows)
            line(format(`"%s",`, dStringEscape(row)));
        indent_--;
        line("];");
    }

    /// `WidgetNode.imageFilename`/`.deimageFilename` -- ported from
    /// FLTK's own `Widget_Image` (`fluid/nodes/Widget_Image.h`/
    /// `.cxx`), now including `bind`/`scale_w`/`scale_h` (see
    /// `WidgetNode.bindImage`/`.scaleImageW`/`.scaleImageH`'s own doc
    /// comment).
    private void writeWidgetImage(WidgetNode n, string v)
    {
        if (n.hasImage && n.imageFilename.length)
            writeOneImage(n.imageFilename, v, false, n.compressImage, n.bindImage, n.scaleImageW, n.scaleImageH);
        if (n.hasDeimage && n.deimageFilename.length)
            writeOneImage(n.deimageFilename, v, true, n.compressDeimage, n.bindDeimage, n.scaleDeimageW, n.scaleDeimageH);
    }

    /// Ported from `fluid/proj/Image_Asset.h`/`.cxx`'s `write_static()`
    /// (FLTK's own per-image-slot `compress` toggle, see
    /// `WidgetNode.compressImage`/`.compressDeimage`'s own doc comment
    /// for the full field-level writeup), with the same dispatch order
    /// FLTK's own if/else chain uses:
    ///
    ///  - `compress` set (the default) AND the format has a matching
    ///    fldtk codec `(name, bytes)` constructor (GIF/BMP/JPEG/PNG/
    ///    SVG/SVGZ -- FLTK's own `compressed && ext==...`-guarded
    ///    branches): embed the file's own original bytes, decoded once
    ///    at runtime via that constructor. Smallest generated code,
    ///    needs the matching codec module linked in (already true for
    ///    any project using `fl`, unlike FLTK's per-format
    ///    optional-linking C++ libraries).
    ///  - Otherwise: decode the file now (`fluid` already links
    ///    against every `fl.*` codec) and embed whatever *native*
    ///    in-memory representation that codec's own class holds --
    ///    `Pixmap`'s XPM string rows (covers both `.xpm` files and any
    ///    GIF whose `Fl_GIF_Image`-equivalent decode is `Pixmap`-based,
    ///    matching FLTK's own unconditional `image_->count() > 1`
    ///    branch -- no `compressed &&` guard there either (FLTK),
    ///    `Bitmap`'s bit array (covers `.xbm`, matching FLTK's own
    ///    unconditional `image_->d() == 0` branch), or (every other
    ///    format, including `.ico` and `.pnm`/`.pbm`/`.pgm`/`.ppm` --
    ///    FLTK's own dispatch chain never special-cases either
    ///    extension, so both always fall through to its terminal
    ///    decoded-RGB branch regardless of `compress`) the decoded
    ///    `RGBImage` pixel array. No decode-time linking difference
    ///    from the compressed path in this port (every codec is always
    ///    linked in), so this path exists purely to match FLTK's
    ///    own dispatch/output shape, not to avoid a dependency.
    private void writeOneImage(string filename, string v, bool deimage, bool compress,
        bool bind, int scaleW, int scaleH)
    {
        string cls = imageClassFor(filename);
        if (cls is null)
        {
            line(format(`// fluid: unrecognized image file extension in "%s", skipped`, filename));
            return;
        }

        string path = buildPath(projectDir_, filename);
        string varName = format("%s%d", deimage ? "deimgBytes" : "imgBytes", imageVarCounter_++);
        // `bind` selects `bindImage()`/`bindDeimage()` (ownership-
        // taking, `fl.widget.Widget`'s own already-real equivalent of
        // FLTK's `bind_image()`/`bind_deimage()`) over plain
        // `image()`/`deimage()` -- but the *getter* used by the
        // trailing `.scale()` call below is always the plain one
        // (`image()`/`deimage()`), matching FLTK's own
        // `Widget_Image::write_code()`: `bind_image()` internally
        // calls `image()` and only additionally sets the ownership
        // flag, so the image itself is retrieved the same way either
        // way.
        string setter = bind ? (deimage ? "bindDeimage" : "bindImage") : (deimage ? "deimage" : "image");
        string getter = deimage ? "deimage" : "image";

        bool byteCtorEligible;
        switch (cls)
        {
        case "GifImage": case "BMPImage": case "JpegImage": case "PngImage": case "SvgImage":
            byteCtorEligible = true;
            break;
        default:
            byteCtorEligible = false;
        }

        bool wrote;
        if (compress && byteCtorEligible)
        {
            ubyte[] bytes;
            try
                bytes = cast(ubyte[]) read(path);
            catch (Exception e)
            {
                line(format(`// fluid: could not read image file "%s": %s`, filename, e.msg));
                return;
            }
            writeByteArrayLiteral(varName, bytes);
            line(format(`%s.%s(new %s("%s", %s));`,
                v, setter, cls, dStringEscape(baseName(filename)), varName));
            wrote = true;
        }
        else
        {
            Image img;
            try
                img = loadImageForCodegen(path, cls);
            catch (Exception e)
            {
                line(format(`// fluid: could not read image file "%s": %s`, filename, e.msg));
                return;
            }
            if (img is null || img.fail())
            {
                line(format(`// fluid: could not decode image file "%s"`, filename));
                return;
            }

            if (auto pxm = cast(Pixmap) img)
            {
                writeStringArrayLiteral(varName, pxm.xpmData);
                line(format(`%s.%s(new Pixmap(%s));`, v, setter, varName));
                wrote = true;
            }
            else if (auto bmp = cast(Bitmap) img)
            {
                writeByteArrayLiteral(varName, bmp.array);
                line(format(`%s.%s(new Bitmap(%s, %d, %d));`, v, setter, varName, bmp.dataW(), bmp.dataH()));
                wrote = true;
            }
            else if (auto rgb = cast(RGBImage) img)
            {
                writeByteArrayLiteral(varName, rgb.array);
                line(format(`%s.%s(new RGBImage(%s, %d, %d, %d, %d));`,
                    v, setter, varName, rgb.dataW(), rgb.dataH(), rgb.d(), rgb.ld()));
                wrote = true;
            }
            else
            {
                // Confirmed unreachable given the codec set `loadImageForCodegen()`'s
                // own `switch` can return: `GifImage`/`XPMImage` are
                // `Pixmap` subclasses, `XBMImage` is a `Bitmap` subclass, and
                // `PngImage`/`JpegImage`/`BMPImage`/`ICOImage`/`SvgImage`/`PNMImage`
                // are all `RGBImage` subclasses (`ICOImage : BMPImage`, `AnimGifImage :
                // GifImage`, transitively too) -- every branch above already matches
                // one of the three via `cast()`, which succeeds for a subclass just as
                // much as an exact match. Kept as a defensive fallback, not dead code
                // to delete: a future `fl.image` codec that doesn't descend from one of
                // these three would hit it for real.
                line(format(`// fluid: image file "%s" decoded to an unsupported representation, skipped`, filename));
            }
        }

        // Ported from `Widget_Image::write_code()`'s own trailing
        // `->scale(...)` block: a zero dimension falls back to the
        // image's own already-decoded natural size (`dataW()`/
        // `dataH()`) rather than being treated as "don't scale that
        // axis" -- matching FLTK's own `data_w()`/`data_h()`
        // fallback exactly.
        if (wrote && (scaleW || scaleH))
        {
            string wArg = scaleW > 0 ? format("%d", scaleW) : format("%s.%s().dataW()", v, getter);
            string hArg = scaleH > 0 ? format("%d", scaleH) : format("%s.%s().dataH()", v, getter);
            line(format("%s.%s().scale(%s, %s, false, true);", v, getter, wArg, hArg));
        }
    }

    /// Which of this port's own already-real image codecs to construct
    /// for a given filename, chosen by extension -- FLTK's own
    /// `Fl_Shared_Image` uses a registered-handler mechanism this port
    /// doesn't have, so this is a plain, explicit table instead. `null`
    /// for an unrecognized extension (`writeOneImage()`'s own caller
    /// emits a comment noting the skip rather than erroring the whole
    /// generation).
    private string imageClassFor(string filename)
    {
        switch (filename.extension.toLower)
        {
        case ".png": return "PngImage";
        case ".jpg": case ".jpeg": return "JpegImage";
        case ".gif": return "GifImage";
        case ".bmp": return "BMPImage";
        case ".xpm": return "XPMImage";
        case ".xbm": return "XBMImage";
        case ".ico": return "ICOImage";
        case ".svg": case ".svgz": return "SvgImage";
        case ".pnm": case ".pbm": case ".pgm": case ".ppm": return "PNMImage";
        default: return null;
        }
    }

    /// File-path-constructor counterpart of `imageClassFor()`'s name
    /// table, used only by `writeOneImage()`'s native-representation
    /// path to actually decode the file at codegen time (mirrors
    /// `instantiate.d`'s own `loadImageFile()` dispatch, kept as a
    /// separate small table rather than shared -- same "no registered-
    /// handler mechanism" reasoning as `imageClassFor()` itself, one
    /// level up).
    private Image loadImageForCodegen(string path, string cls)
    {
        switch (cls)
        {
        case "PngImage": return new PngImage(path);
        case "JpegImage": return new JpegImage(path);
        case "GifImage": return new GifImage(path);
        case "BMPImage": return new BMPImage(path);
        case "XPMImage": return new XPMImage(path);
        case "XBMImage": return new XBMImage(path);
        case "ICOImage": return new ICOImage(path);
        case "SvgImage": return new SvgImage(path);
        case "PNMImage": return new PNMImage(path);
        default: return null;
        }
    }

    /// D class name for a node -- strips the "Fl_" prefix (matching
    /// this project's own `Fl_Foo` -> `Foo` naming convention), with
    /// three exceptions: a window's "type Double" property selects
    /// `DoubleWindow` over plain `Window`; a `class Foo` property
    /// (case-1 usage -- names a pre-existing, separately-defined D
    /// subclass, e.g. CubeViewUI.fl's `Fl_Box cube { ... class CubeView }`)
    /// always wins when present; and a `.fl`-dialect "Group"/"Clock"
    /// (or "Fl_Group"/"Fl_Clock") node instantiates `FlGroup`/`FlClock`,
    /// not `Group`/`Clock` -- those two D classes are renamed (see
    /// `fl.group`/`fl.clock`'s own doc comments) specifically because a
    /// bare `Group`/`Clock` collides with `std.algorithm.iteration.
    /// Group`/`std.datetime.systime.Clock` in every generated file's own
    /// wildcard `import std;`. The `.fl` dialect keyword itself stays
    /// "Group"/"Clock" (matching FLTK), only the D type instantiated
    /// changes.
    private string className(Node n)
    {
        if (auto w = cast(WidgetNode) n)
            if (w.hasClassOverride)
                return w.classOverride;
        if (auto wn = cast(WindowNode) n)
            return isDoubleWindow(wn.typeName, wn.typeWord) ? "DoubleWindow" : "Window";
        string s = stripFlPrefix(n.typeName);
        if (s == "MenuBar")
            if (auto mb = cast(WidgetNode) n)
                if (mb.typeWord == "Fl_Sys_Menu_Bar")
                    return "SysMenuBar";
        if (s == "Group") return "FlGroup";
        if (s == "Clock") return "FlClock";
        return s;
    }

    private void writeFunctionBody(FunctionNode fn)
    {
        immutable start = pos();
        writeNodeComment(fn);
        line("void main(string[] args)");
        line("{");
        spanOpen(fn, start);
        indent_++;
        inMainFunction_ = true;
        // A Function's children are usually a widget tree (every
        // widget-based .fl file), but a Function that just wraps
        // hand-written D driver code (fluid_callback.fl, CubeViewUI.fl's
        // merged-in main()) has a single bare `code { ... }` child
        // instead, and a Conditional node can wrap a mix of either --
        // see `writeBodyChild()`.
        foreach (c; fn.children)
            writeBodyChild(c);
        inMainFunction_ = false;
        immutable closeStart = pos();
        blank();
        line("fl.run();");
        indent_--;
        line("}");
        spanClose(fn, closeStart);
    }

    /// Whether the widget tree currently being written is the
    /// top-level main Function's own (which has an `args` parameter in
    /// scope) as opposed to a class method's (e.g. mandelbrot_ui.fl's
    /// `DrawingWindow.makeWindow()`, which has no `args` at all, and,
    /// matching `mandelbrot_nofl.d`, doesn't call `.show()`
    /// itself either; that's left to whatever driver code calls
    /// `makeWindow()`). Read by `writeWindowNode()` to decide whether
    /// emitting `.show(args)` even makes sense.
    private bool inMainFunction_;

    /// A named Function, written as an ordinary top-level D function
    /// (e.g. radio.fl's `buttonCB(Button b)`, valuators.fl's
    /// `valCb(string name)` returning `void delegate(Widget)`, or
    /// CubeViewUI.fl's `makeWindow()`): signature and body emitted
    /// verbatim.
    ///
    /// Return-type auto-inference: when `fn.returnType`
    /// is empty, ported from FLTK's `Function_Node::write_code1()`/
    /// `write_code2()` -- `rtype.empty() ? (havewidgets ? subclassname
    /// (child) : "void")` at the top, `return w;` at the bottom when
    /// that inference fired. This is FLTK's classic "make_window()"
    /// shape: `Function_Node::make()` deliberately leaves `return_type`
    /// empty (a Function that isn't `main()` starts as
    /// `"makeWindow()"`, `fluid.instantiate.defaultNameFor()`) so that
    /// dropping a `Window` inside turns it into a real
    /// `Window makeWindow() { ...; return w; }` with no further typing
    /// needed. D has no C++ pointer-vs-value distinction to resolve via
    /// a `"*"` suffix the way `subclassname(child) + star` does --
    /// `className()` already returns the plain D class name (a
    /// reference type), used directly. Only the *first* widget child's
    /// class matters, matching FLTK's own `child` (the loop
    /// variable FLTK never resets after finding the first widget,
    /// so subsequent widget children can't override it either).
    private void writePlainFunction(FunctionNode fn)
    {
        immutable start = pos();
        writeNodeComment(fn);

        // A named `Function` literally called "main" is *not* what makes
        // this port's own real program entry point -- that's the
        // *anonymous* root `Function` (empty name field, `generate()`'s
        // own `fn.instanceName.length == 0` check, routed to
        // `writeFunctionBody()` instead of this function entirely).
        // Matches FLTK exactly: `Function_Node::ismain()` is
        // literally `name_ == nullptr`, nothing to do with the string
        // "main" -- naming a Function "main()" in real Fluid produces
        // an ordinary member/plain function there too, not a C++ `int
        // main()`. Silently going through the same auto-inference every
        // other named function gets (e.g. `Window main()` for a Function
        // with a `Window` child) is *correct*, faithful behavior -- but
        // it's also a real source of user confusion (expecting `void
        // main()`/`int main()`), so this flags it rather than staying silent.
        if (functionName(fn.instanceName) == "main")
        {
            line("// Note: this Function is named \"main\", but Fluid only treats the");
            line("// *anonymous* root Function (leave its Name field blank) as the");
            line("// program's real entry point -- that one auto-generates .show()/fl.run()");
            line("// for you. This one is an ordinary function like any other, whose return");
            line("// type below was inferred the same way every other named Function's is.");
        }

        WidgetNode firstWidgetChild;
        foreach (c; fn.children)
            if (auto w = cast(WidgetNode) c) { firstWidgetChild = w; break; }

        bool autoReturn = fn.returnType.length == 0 && firstWidgetChild !is null;
        string ret = fn.returnType.length ? fn.returnType
            : (firstWidgetChild !is null ? className(firstWidgetChild) : "void");
        line(functionAttributes(fn, false) ~ format("%s %s", ret, fn.instanceName));
        line("{");
        indent_++;
        // Usually a bare `code { ... }` body (valuators.fl's
        // valCb/spinnerCb), but a plain function can also build a real
        // widget tree instead (keyboard_ui.fl's zero-param
        // `make_window()`, matching FLTK's own real file split --
        // see mandelbrot_ui.fl's identical shape for `makeWindow()`),
        // or wrap either in a Conditional node -- see `writeBodyChild()`.
        // `inMainFunction_` stays false here, same as inside a class
        // method: no `args` in scope, so a Window inside this tree
        // won't call `.show()` either.
        // An anonymous first widget is constructed inside its own `{ }`
        // block, so its variable must be declared out here, before the
        // block, for the trailing `return` to see it -- the block then
        // assigns to it instead of declaring it (`ctorAssign()`), same
        // as FLTK's `Fl_Window* w; { ... w = o; ... } return w;`.
        // A named first widget already has its own declaration elsewhere.
        if (autoReturn && firstWidgetChild.instanceName.length == 0)
        {
            line(format("%s %s;", ret, selfRef(firstWidgetChild)));
            returnVarNodes_[firstWidgetChild] = true;
            // Every further anonymous window in the same function reuses
            // that variable too (FLTK's `wused`), else its own
            // `auto w` would shadow it.
            foreach (c; fn.children)
                if (cast(WindowNode) c && c.instanceName.length == 0)
                    returnVarNodes_[c] = true;
        }
        spanOpen(fn, start);
        foreach (c; fn.children)
            writeBodyChild(c);
        returnVarNodes_ = null;
        immutable closeStart = pos();
        if (autoReturn)
            line(format("return %s;", selfRef(firstWidgetChild)));
        indent_--;
        line("}");
        spanClose(fn, closeStart);
        blank();
    }

    /// A Class (`fluid.class_node`): `class Name : Base`, the named
    /// widgets its methods build as fields, then its children in tree
    /// order -- Code nodes as fields, Functions as methods, Conditional
    /// nodes, Comments, and nested Classes.
    private void writeClassNode(ClassNode cn)
    {
        immutable start = pos();
        writeNodeComment(cn);
        string attribute = nestedClassPrefix() ~ (cn.prefix.length ? cn.prefix ~ " " : "");
        // A base class of "Group" or "Clock" names fl's FlGroup/FlClock,
        // as it does for a widget node (see className()).
        string base = stripFlPrefix(cn.baseClass);
        if (base == "Group") base = "FlGroup";
        else if (base == "Clock") base = "FlClock";
        string header = cn.baseClass.length
            ? format("%sclass %s : %s", attribute, cn.instanceName, base)
            : format("%sclass %s", attribute, cn.instanceName);
        line(header);
        line("{");
        spanOpen(cn, start);
        indent_++;
        classDepth_++;
        if (writeClassFields(cn.children))
            blank();
        foreach (c; cn.children)
            writeDeclChild(c);
        classDepth_--;
        indent_--;
        immutable closeStart = pos();
        line("}");
        spanClose(cn, closeStart);
        blank();
    }

    /// Every named widget found anywhere inside a class's own subtree
    /// becomes a class field -- matching real Fluid's own behavior
    /// (a named widget inside a class-scoped method becomes a member,
    /// not a free-standing global; see `collectNames()`'s doc comment).
    /// Recurses through the widget tree the same way `writeDecls()`
    /// does at module scope, just emitting into the class body instead.
    /// Returns whether anything was written, so the caller knows
    /// whether a blank line is needed before the class's methods.
    private bool writeClassFields(Node[] nodes)
    {
        bool any;
        foreach (n; nodes)
        {
            // A nested class has fields of its own.
            if (cast(ClassNode) n)
                continue;
            if (auto wn = cast(WidgetNode) n)
                if (wn.instanceName.length)
                {
                    final switch (wn.access)
                    {
                    case Access.private_: line(format("private %s %s;", className(n), n.instanceName)); break;
                    case Access.public_: line(format("%s %s;", className(n), n.instanceName)); break;
                    case Access.protected_: line(format("protected %s %s;", className(n), n.instanceName)); break;
                    }
                    any = true;
                }
            if (writeClassFields(n.children))
                any = true;
        }
        return any;
    }

    /// A class's own Function child -- either a real method (its
    /// `instanceName` is already a literal D method signature --
    /// `this(int x, int y, string l)`, `~this()`, `cbBnVirtual(int v)`
    /// -- emitted close to verbatim, body from a bare `code { ... }`
    /// child) or, just like the anonymous main Function, a method whose
    /// own body is a real widget tree (e.g. mandelbrot_ui.fl's
    /// `makeWindow()`) -- walked via `writeWidgetTree()` the same way
    /// `writeFunctionBody()` does. A constructor/destructor spells no
    /// return type at all (D syntax); an ordinary method gets its own
    /// `return_type` property (falling back to `void`, the
    /// overwhelmingly common case, when unset).
    /// D attributes written before a function's signature. Ported from the
    /// visibility handling of `Function_Node::write_code1()`: a class method
    /// gets `private`/`protected`; a plain function gets `private` (FLTK's
    /// `static`) and, with `declare "C"`, `extern (C)`. A plain function's
    /// `protected` ("local") adds nothing, and `declare "C"` means nothing
    /// for a method.
    private string functionAttributes(FunctionNode fn, bool inClass)
    {
        string attrs;
        if (fn.access == Access.private_)
            attrs ~= "private ";
        else if (inClass && fn.access == Access.protected_)
            attrs ~= "protected ";
        if (!inClass && fn.declareC)
            attrs ~= "extern (C) ";
        return attrs;
    }

    private void writeClassMethod(FunctionNode fn)
    {
        immutable start = pos();
        writeNodeComment(fn);
        bool isCtor = fn.instanceName.length >= 5 && fn.instanceName[0 .. 5] == "this(";
        bool isDtor = fn.instanceName.length >= 1 && fn.instanceName[0] == '~';
        string sigLine = (isCtor || isDtor)
            ? fn.instanceName
            : format("%s %s", fn.returnType.length ? fn.returnType : "void", fn.instanceName);
        line(functionAttributes(fn, true) ~ sigLine);
        line("{");
        spanOpen(fn, start);
        indent_++;
        foreach (c; fn.children)
            writeBodyChild(c);
        indent_--;
        immutable closeStart = pos();
        line("}");
        spanClose(fn, closeStart);
        blank();
    }

    private void writeWidgetTree(Node n)
    {
        // A `code {}` among a window's or group's children runs in its
        // place between the widgets around it, as in a function body.
        if (auto code = cast(CodeNode) n)
        {
            writeCodeNode(code);
            return;
        }
        // A Comment node in a function body or a Conditional node:
        // its text, in place, unless it is switched off for the source.
        if (auto comn = cast(CommentNode) n)
        {
            if (comn.inSource_)
            {
                immutable start = pos();
                writeCommentText(comn.instanceName);
                spanLeaf(comn, start);
            }
            return;
        }
        // The node's comment belongs to its own setup code, as in FLTK,
        // where `write_code1()` writes it inside the `setup_node` span:
        // the Code View then highlights the comment with the widget.
        immutable commentStart = pos();
        scope (exit)
            if (n.setupSpan.start > commentStart)
                n.setupSpan.start = commentStart;
        writeNodeComment(n);
        // A Conditional node among a function's statements or a
        // container's widgets.
        if (auto cond = cast(ConditionalNode) n)
        {
            writeConditionalBody(cond);
            return;
        }
        if (auto wn = cast(WindowNode) n)
        {
            writeWindowNode(wn);
            return;
        }
        if (auto gn = cast(GroupNode) n)
        {
            writeGroupNode(gn);
            return;
        }
        if (auto w = cast(WidgetNode) n)
        {
            // `usesFontMenu`/`usesColorMenu` (`fluid.font_menu`'s own
            // doc comment) deliberately have zero `MenuItemNode`
            // children -- the whole point is *not* re-declaring them
            // per instance -- so they need their own way into
            // `writeMenuOwnerNode()`, which the plain "does this node
            // have menu-item children" check below would never route to.
            if (w.usesFontMenu || w.usesColorMenu
                || (w.children.length && cast(MenuItemNode) w.children[0] !is null))
            {
                writeMenuOwnerNode(w);
                return;
            }
            writeWidgetNode(w);
            return;
        }
    }

    private string[Node] anonNames;
    private int groupDepth_;

    /// Per-node local variable name, matching FLTK's own
    /// generated-code convention: every anonymous widget's own
    /// construction block reuses a single conventional name rather than
    /// a per-instance counter (`{ Fl_Button* o = new Fl_Button(...);
    /// ... }`), safe in C++ because each widget's construction is
    /// wrapped in its own `{ }` scope and C++ allows a nested block to
    /// shadow an outer variable of the same name. **D does not allow
    /// that** -- confirmed via a minimal repro (`auto o = 1; { auto o =
    /// 2; ... }` is a hard "shadowing" error, unconditionally, even
    /// when the outer `o` is never referenced again afterward) -- so
    /// naive "everything is o" doesn't port directly. What *does* port:
    /// a widget that never needs referencing again once its own `{ }`
    /// block closes can safely reuse a name, since sibling blocks at
    /// the same nesting level never overlap (confirmed via a second
    /// repro: `{ int o = 2; } { int o = 3; }` compiles fine -- these
    /// are sequential, not nested). Three tiers, by what actually needs
    /// to persist past its own block:
    ///   - Named widgets: their own verbatim `.fl` instance name
    ///     (unchanged -- these are genuinely referenced elsewhere).
    ///   - The top-level window: always `"w"` -- needs to persist for
    ///     `.show(args)`, called after `.end()` (matching FLTK's
    ///     own `Fl_Double_Window* w; { ... Fl_Double_Window* o = ...; w
    ///     = o; ... } w->show(...);` two-name split, just without the
    ///     escape-from-"o" step since we name it "w" from the start).
    ///   - Anonymous containers (`Group`/`GroupNode`) with children of
    ///     their own: named by nesting *depth* (`"g1"`, `"g2"`, ...) --
    ///     a group's own children need "o" for themselves, so a group
    ///     can't reuse "o" either, but sibling groups at the same depth
    ///     never overlap and can safely share a depth-keyed name; only
    ///     genuine nesting (a group inside another anonymous group)
    ///     needs a distinct name, which incrementing depth guarantees.
    ///   - Everything else (anonymous leaf widgets, and `MenuOwnerNode`
    ///     -- its own children are collected into an array literal, not
    ///     nested `{ }` blocks, so it's leaf-like too): plain `"o"`,
    ///     matching FLTK's own convention exactly, since nothing
    ///     ever needs to reference these again once their own block
    ///     closes.
    private string selfRef(Node n)
    {
        if (n.instanceName.length)
            return n.instanceName;
        if (auto p = n in anonNames)
            return *p;
        string name;
        if (cast(WindowNode) n)
            name = "w";
        else if (cast(GroupNode) n)
            name = format("g%d", groupDepth_);
        else
            name = "o";
        anonNames[n] = name;
        return name;
    }

    /// The anonymous widgets whose shared variable `writePlainFunction()`
    /// already declared before their construction blocks (so the function
    /// can `return` it); `ctorAssign()` assigns to it instead of
    /// redeclaring.
    private bool[Node] returnVarNodes_;

    private string ctorAssign(Node n, string cls)
    {
        string v = selfRef(n);
        return (n.instanceName.length || (n in returnVarNodes_))
            ? format("%s = new %s(", v, cls)
            : format("auto %s = new %s(", v, cls);
    }

    /// Whether any *direct* child of `n` is itself marked "resizable"
    /// -- see writeWindowNode()'s own doc comment for why this matters.
    private bool hasResizableChild(Node n)
    {
        foreach (c; n.children)
            if (auto w = cast(WidgetNode) c)
                if (w.resizableFlag)
                    return true;
        return false;
    }

    private void writeWindowNode(WindowNode n)
    {
        string v = selfRef(n);
        string cls = className(n);
        string labelArg = n.hasLabel ? format(", %s", i18nWrap(n.label)) : "";
        n.setupSpan.start = pos();
        line("{");
        indent_++;
        // A window nested in another window is a subwindow at its own
        // position; the (w, h) constructor would make it a top-level window.
        if (isNestedWindow(n))
            line(format("%s%d, %d, %d, %d%s);", ctorAssign(n, cls), n.x, n.y, n.w, n.h, labelArg));
        else
            line(format("%s%d, %d%s);", ctorAssign(n, cls), n.w, n.h, labelArg));
        writeCommonProps(n, v);
        // Matches FLTK's own `Window_Node::write_code1()` call
        // sites exactly (`set_modal()`/`set_non_modal()`, constructor-
        // time, before children).
        // `modal`/`non_modal` are parsed into `WindowNode.modal_`/
        // `nonModal_`, round-tripped correctly by
        // `project_writer.d`'s own `.fl`-text writer, and emitted
        // as real D here, so a `modal` window is real (`fluid/panels/
        // template_panel.fl` is the first `.fl` file in this project to
        // use `modal` rather than `non_modal`).
        if (n.modal_)
            line(format("%s.setModal();", v));
        else if (n.nonModal_)
            line(format("%s.setNonModal();", v));
        // `noborder`, matching `WindowNode.noBorder_`'s real backing
        // field for the
        // "Border" light button's `widget_panel.d` wiring.
        if (n.noBorder_)
            line(format("%s.border(false);", v));
        // `xclass`/`size_range` -- see `panels/widget_panel.fl`'s
        // own "Window:" section.
        if (n.xclass.length)
            line(format(`%s.xclass("%s");`, v, dStringEscape(n.xclass)));
        if (n.hasSizeRange)
            line(format("%s.sizeRange(%d, %d, %d, %d);", v,
                n.sizeRangeMinW, n.sizeRangeMinH, n.sizeRangeMaxW, n.sizeRangeMaxH));
        n.setupSpan.end = pos();
        blank();
        foreach (c; n.children)
            writeWidgetTree(c);
        blank();
        n.finalizeSpan.start = pos();
        // A window's own "resizable" flag only becomes a genuine
        // self-reference when *nothing more specific* already claimed
        // the designation -- confirmed against two real generated
        // outputs: resize.fl (no child marked resizable) emits
        // `o->resizable(o);`, but mandelbrot_ui.fl (whose window AND
        // its child `d` are BOTH marked resizable) emits only
        // `Fl_Group::current()->resizable(d);` for the child, with NO
        // self-reference for the window at all -- the child's own
        // `writeNestedResizable()` call (made while still inside its
        // own block, i.e. before the window's own postscript here)
        // already set the window's resizable_ field, and a later
        // self-reference would silently overwrite/undo it (Fl_Group's
        // resizable_ is a plain last-write-wins field). So: only
        // self-designate if no *direct* child also claims resizable.
        if (n.resizableFlag && !hasResizableChild(n))
            line(format("%s.resizable(%s);", v, v));
        writeFinalizeCode(n, v);
        line(format("%s.end();", v));
        if (inMainFunction_ && !isNestedWindow(n))
            line(format("%s.show(args);", v));
        indent_--;
        line("}");
        n.finalizeSpan.end = pos();
        blank();
    }

    private void writeGroupNode(GroupNode n)
    {
        groupDepth_++;
        string v = selfRef(n);
        string cls = className(n);
        string labelArg = n.hasLabel ? format(", %s", i18nWrap(n.label)) : "";
        n.setupSpan.start = pos();
        line("{");
        indent_++;
        line(format("%s%d, %d, %d, %d%s);", ctorAssign(n, cls), n.x, n.y, n.w, n.h, labelArg));
        writeCommonProps(n, v);
        // Grid's own dimensions/margin/gap/row-or-column arrays have to
        // be set before children are placed into cells -- matches
        // FLTK's `Grid_Node::write_code1()` ordering (construction-
        // time properties, before the children loop). Flex is the
        // opposite: FLTK's `Flex_Node` has no `write_code1`
        // override at all, putting margin/gap/fixed-size entirely into
        // `write_code2()` (after children) -- see `writeFlexExtras()`.
        if (auto grid = cast(GridNode) n) writeGridOwnProps(grid, v);
        n.setupSpan.end = pos();
        blank();
        foreach (c; n.children)
            writeWidgetTree(c);
        blank();
        n.finalizeSpan.start = pos();
        if (auto grid = cast(GridNode) n) writeGridChildPlacement(grid, v);
        else if (auto flex = cast(FlexNode) n) writeFlexExtras(flex, v);
        writeFinalizeCode(n, v);
        line(format("%s.end();", v));
        writeNestedResizable(n, v);
        indent_--;
        line("}");
        n.finalizeSpan.end = pos();
        blank();
        groupDepth_--;
    }

    /// Grid's own `dimensions`/`margin`/`gap`/per-row-or-column arrays --
    /// matches `Grid_Node::write_code1()`'s exact shape (array-setter
    /// overloads, not one call per index) and its "only emit if any
    /// value differs from the default" guards.
    private void writeGridOwnProps(GridNode gn, string v)
    {
        if (gn.hasDimensions)
            line(format("%s.layout(%d, %d);", v, gn.rows, gn.cols));
        if (gn.hasMargin)
            line(format("%s.margin(%d, %d, %d, %d);", v,
                gn.marginLeft, gn.marginTop, gn.marginRight, gn.marginBottom));
        if (gn.hasGap)
            line(format("%s.gap(%d, %d);", v, gn.gapRow, gn.gapCol));
        writeIntArraySetter(v, "rowHeight", gn.rowHeights);
        writeIntArraySetter(v, "rowWeight", gn.rowWeights);
        writeIntArraySetter(v, "rowGap", gn.rowGaps);
        writeIntArraySetter(v, "colWidth", gn.colWidths);
        writeIntArraySetter(v, "colWeight", gn.colWeights);
        writeIntArraySetter(v, "colGap", gn.colGaps);
    }

    private void writeIntArraySetter(string v, string method, const(int)[] values)
    {
        if (values.length == 0) return;
        import std.algorithm : map;
        import std.array : join;
        import std.conv : to;

        line(format("%s.%s([%s]);", v, method, values.map!(to!string).join(", ")));
    }

    /// Per-child cell placement -- matches `Grid_Node::write_code2()`'s
    /// own `var->widget(var->child(i), row, col, rowspan, colspan,
    /// align)` shape exactly: indexes into the parent's already-built
    /// `.child(i)` rather than needing each child's own D variable name
    /// (works whether a child is anonymous "o" or a named variable).
    private void writeGridChildPlacement(GridNode gn, string v)
    {
        foreach (i, c; gn.children)
        {
            auto info = c in gn.cellOf;
            if (info is null) continue;
            line(format("%s.widget(%s.child(%d), %d, %d, %d, %d, %s);",
                v, v, cast(int) i, info.row, info.col, info.rowspan, info.colspan, translateGridAlign(info.alignRaw)));
            if (info.minW != 20 || info.minH != 20)
                line(format("%s.cell(%s.child(%d)).minimumSize(%d, %d);",
                    v, v, cast(int) i, info.minW, info.minH));
        }
    }

    /// Flex's margin/gap/fixed-size -- matches `Flex_Node::
    /// write_code2()`'s own ordering exactly (all three emitted after
    /// children are built, unlike Grid's construction-time margin/gap).
    private void writeFlexExtras(FlexNode fn, string v)
    {
        if (fn.hasMargin)
            line(format("%s.margin(%d, %d, %d, %d);", v,
                fn.marginLeft, fn.marginTop, fn.marginRight, fn.marginBottom));
        if (fn.hasGap)
            line(format("%s.gap(%d);", v, fn.gap));
        for (size_t i = 0; i + 1 < fn.fixedSizeTuples.length; i += 2)
        {
            int idx = fn.fixedSizeTuples[i];
            int size = fn.fixedSizeTuples[i + 1];
            line(format("%s.fixed(%s.child(%d), %d);", v, v, idx, size));
        }
    }

    private void writeWidgetNode(WidgetNode n)
    {
        string v = selfRef(n);
        string cls = className(n);
        string labelArg = n.hasLabel ? format(", %s", i18nWrap(n.label)) : "";
        n.setupSpan.start = pos();
        line("{");
        indent_++;
        line(format("%s%d, %d, %d, %d%s);", ctorAssign(n, cls), n.x, n.y, n.w, n.h, labelArg));
        writeCommonProps(n, v);
        n.setupSpan.end = pos();
        n.finalizeSpan.start = n.setupSpan.end;
        writeNestedResizable(n, v);
        writeFinalizeCode(n, v);
        indent_--;
        line("}");
        n.finalizeSpan.end = pos();
        blank();
    }

    /// A bare "resizable" flag on anything other than a Window means
    /// "once my own construction is done, tell whatever group is now
    /// current (the *enclosing* one) that I'm its resizable child" --
    /// confirmed against real FLTK output (`Fl_Group::current()->
    /// resizable(the_group);` in inactive.cxx, `Group::current()->
    /// resizable(cube);`/`resizable(MainView)` in CubeViewUI.cxx) --
    /// NOT a self-reference the way a Window's own "resizable" is.
    /// `FlGroup.current()` already correctly points at the enclosing
    /// group here, the same way FLTK's own construction-time
    /// group-stack does, since `.end()` (for a container) or simply
    /// "no `begin()` was ever called" (for a leaf) leaves it there.
    private void writeNestedResizable(WidgetNode n, string v)
    {
        if (n.resizableFlag)
            line(format("FlGroup.current().resizable(%s);", v));
    }

    /// A widget whose children are `MenuItem` nodes (not real widgets)
    /// -- collects them into a local `MenuItem[]` array literal, then
    /// wires it up via `.menu(arr)`, matching FLTK's own real
    /// generated shape (a separate `Fl_Menu_Item[]` array + `o->menu(...)`,
    /// confirmed against inactive.cxx's `menu_menu[]`) rather than
    /// walking them as a normal widget subtree.
    private void writeMenuOwnerNode(WidgetNode n)
    {
        string v = selfRef(n);
        string cls = className(n);
        string arrName = v ~ "Menu";
        n.setupSpan.start = pos();
        line("{");
        indent_++;
        // `uses_font_menu` (`fluid.font_menu`'s own doc comment): a
        // shared, single-source-of-truth 16-entry font list instead of
        // literal `MenuItem {}` children re-declared at every
        // font-picking `Choice`.
        // `fontMenuItems()` returns a fresh `MenuItem[]` each call (see
        // `fluid.font_menu`'s own doc comment for why it's a function,
        // not a shared array + `.dup`). Referenced unqualified, not
        // `fluid.font_menu.fontMenuItems()` -- relies on the generated
        // file's own `import fluid;` (every `.fl` project using this
        // flag is, in practice, one of Fluid's own panels, which
        // already declare it) re-exporting the symbol by name; a
        // project with only `import fl;` and no `fluid.font_menu`
        // import of its own would fail to compile, an accepted scoping
        // constraint matching FLTK's own `fontmenu[]` (private to
        // Fluid's own binary, not part of libFLTK either).
        // `uses_color_menu` (`fluid.color_menu`'s own doc comment): same
        // mechanism, for the 14-entry quick-pick color list instead.
        if (n.usesFontMenu)
            line(format("auto %s = fontMenuItems();", arrName));
        else if (n.usesColorMenu)
            line(format("auto %s = colorMenuItems();", arrName));
        else
        {
            line(format("auto %s = [", arrName));
            indent_++;
            writeMenuItemChildren(n);
            // fl.menu_item's own item-array walk relies on a trailing
            // null-text sentinel to know where the array (or an embedded
            // submenu within it) ends: a missing sentinel is a real
            // `validateMenuArray()` runtime exception, not caught by
            // compilation, since it's a data problem, not
            // a type error. Every MenuItem array this writer emits needs
            // one, matching FLTK's own `{0}`/this project's own
            // `MenuItem(null)` spelling.
            line("MenuItem(null),");
            indent_--;
            line("];");
        }
        string labelArg = n.hasLabel ? format(", %s", i18nWrap(n.label)) : "";
        line(format("%s%d, %d, %d, %d%s);", ctorAssign(n, cls), n.x, n.y, n.w, n.h, labelArg));
        // `.menu(...)` must run *before* `writeCommonProps()`:
        // `Menu_.menu(MenuItem[])`
        // (`fl.menu_.d`) unconditionally resets the current selection to
        // index 0 (`value_ = menu_.length ? &menu_[0] : null;`), so any
        // `.value(...)` call `writeCommonProps()` emits -- from a
        // plain `value N` attribute (`n.hasValue`) *or* from `setup{}`
        // code that calls `o.value(...)` -- would otherwise be silently discarded
        // if `.menu(...)` ran right after it (e.g. the Settings dialog's
        // User tab "Class:" font Choice, whose correct default is
        // "Helvetica Bold", index 1, not index 0).
        line(format("%s.menu(%s);", v, arrName));
        writeCommonProps(n, v);
        n.setupSpan.end = pos();
        n.finalizeSpan.start = n.setupSpan.end;
        writeFinalizeCode(n, v);
        indent_--;
        line("}");
        n.finalizeSpan.end = pos();
        blank();
    }

    /// Writes `n`'s own `MenuItemNode` children as literal `MenuItem(...)`
    /// lines, recursing into a `SubmenuNode` child's own children and
    /// closing that nesting level with a `MenuItem(null),` sentinel
    /// before continuing -- matches `fl.menu_item`'s flat, sentinel-
    /// delimited embedded-submenu format (see `fl.menu_item.
    /// validateMenuArray()`'s own doc comment): a `menuSubmenu`-flagged
    /// item's nested items follow it inline in the same array, closed by
    /// a matching null-text entry, even when that submenu has zero
    /// children -- an *unconditional* close, not "only if there's
    /// something to write", since a missing sentinel here produces
    /// exactly the "consumes the rest of the array" hazard that
    /// function's own doc comment describes. Shared by
    /// `writeMenuOwnerNode()` (top level) and this function itself
    /// (recursive descent into a submenu).
    private void writeMenuItemChildren(WidgetNode n)
    {
        foreach (c; n.children)
        {
            auto mi = cast(MenuItemNode) c;
            if (mi is null) continue;
            writeMenuItemLiteral(mi);
            if (mi.canHaveChildren())
            {
                writeMenuItemChildren(mi);
                line("MenuItem(null),");
            }
        }
    }

    /// `mi.label` is wrapped via the same `i18nWrap()` every other
    /// label/tooltip in this file already goes through.
    /// **FLTK's own mechanism is materially more complex than this
    /// needs to be here, and the reason why doesn't apply to this
    /// port**: FLTK's `Fl_Menu_Item[]` is a real C static aggregate
    /// initializer, evaluated before `main()` even runs, so it can't
    /// call a function at all -- the label slot gets `gettext_noop("...")`
    /// (an identity no-op, purely an `xgettext`-extraction marker) at
    /// declaration time, and a *separate* runtime statement afterward
    /// (`Menu_Item_Node::write_code1()`, wrapped in its own `{ Fl_Menu_
    /// Item* o = &array[i]; ... }` initializer block) reassigns
    /// `o->label(gettext(o->label()))` once the array actually exists
    /// at runtime. This port's own generated `MenuItem[]` array is
    /// never a static/module-level initializer -- `writeMenuOwnerNode()`
    /// (just above) always builds it as a plain local `auto arr = [...]`
    /// inside whatever function is already executing (`main()`, a
    /// class constructor), i.e. genuine runtime code from the moment it
    /// exists, exactly like every ordinary widget's `w.label(...)` call
    /// already is. Confirmed against FLTK's own `Widget_Node.cxx`:
    /// its *widget*-label writer (unlike the menu-array one) already
    /// calls `gnu_function`/`gettext()` directly too, for the identical
    /// reason (`Fl_Widget::label()` is also set via ordinary runtime
    /// code in generated C++, not a static initializer) -- this port's
    /// `i18nWrap()` already made that same simplification for widgets;
    /// extending it to menu items isn't a new shortcut, it's applying
    /// the one FLTK itself already draws the same line around, to
    /// the one call site here that had been missed.
    private void writeMenuItemLiteral(MenuItemNode mi)
    {
        // A null label ends the menu array, so an unlabeled item gets an
        // empty string, as in FLTK's `Menu_Item_Node::write_item()`.
        string label = mi.hasLabel && mi.label.length ? i18nWrap(mi.label) : `""`;
        string labeltype = mi.labeltype.length ? translateLabeltype(mi.labeltype) : "Labeltype.normalLabel";
        string labelfont = mi.labelfont >= 0 ? translateFont(mi.labelfont) : "0";
        int labelsize = mi.labelsize >= 0 ? mi.labelsize : 14;
        string labelcolor = mi.labelcolorRaw >= 0 ? translateColor(mi.labelcolorRaw) : "0";
        string flags = menuItemFlags(mi);
        // A MenuItem's own "callback" property -- e.g. preferences.fl's
        // "sandals" item -- becomes an inline delegate literal in the
        // callback slot (`MenuItem.callback_` is the same `Callback =
        // void delegate(Widget)` alias every other widget's callback
        // uses). None of this project's menu-item callbacks so far
        // reference the item itself via "o", so no cast is introduced
        // here the way writeCallback() does for an ordinary widget --
        // add one if a future file's body actually needs it.
        string shortcut = mi.hasShortcut ? shortcutText(mi.shortcutRaw) : "0";
        if (mi.callback.length)
        {
            line(format("MenuItem(%s, %s, (o) {", label, shortcut));
            indent_++;
            writeTaggedBlock(Tag.menuCallback, mi, mi.callback);
            indent_--;
            line(format("}, %s, %s, %s, %d, %s),", flags, labeltype, labelfont, labelsize, labelcolor));
            return;
        }
        line(format("MenuItem(%s, %s, null, %s, %s, %s, %d, %s),",
            label, shortcut, flags, labeltype, labelfont, labelsize, labelcolor));
    }

    /// FLTK: `Menu_Item_Node::flags()` (`Menu_Node.cxx`) -- the generated
    /// `MenuItem`'s flags word: `value` (`FL_MENU_VALUE`), `deactivate`
    /// (`FL_MENU_INACTIVE`), `hide` (`FL_MENU_INVISIBLE`), `hotspotFlag`
    /// (reused as "divider", `FL_MENU_DIVIDER`), `headline_`
    /// (`FL_MENU_HEADLINE`), `canHaveChildren()` (`FL_SUBMENU`, a property
    /// of the node class, `Submenu_Node` vs. plain `Menu_Item_Node`), and
    /// `typeName` (`FL_MENU_TOGGLE`/`FL_MENU_RADIO`, which FLTK stores as
    /// the item's `type()`; see `menu_item_node.d`'s doc comment for why
    /// `typeName` carries it here).
    private string menuItemFlags(MenuItemNode mi)
    {
        string flags;
        void add(string f)
        {
            if (flags.length) flags ~= " | ";
            flags ~= f;
        }
        if (mi.hasValue && mi.valueRaw.strip() != "0") add("menuValue");
        if (mi.deactivated) add("menuInactive");
        if (mi.hidden) add("menuInvisible");
        if (mi.hotspotFlag) add("menuDivider");
        if (mi.headline_) add("menuHeadline");
        if (mi.canHaveChildren()) add("menuSubmenu");
        if (mi.typeName == "CheckMenuItem") add("menuToggle");
        if (mi.typeName == "RadioMenuItem") add("menuRadio");
        return flags.length ? flags : "0";
    }

    private void writeCommonProps(WidgetNode n, string v)
    {
        if (n.hasBoxtype)
            line(format("%s.box(%s);", v, translateBoxtype(n.boxtype)));
        if (n.hasDownBoxtype)
            line(format("%s.downBox(%s);", v, translateBoxtype(n.downBoxtype)));
        if (n.color >= 0)
            line(format("%s.color(%s);", v, translateColor(n.color)));
        if (n.selectionColor >= 0)
            line(format("%s.selectionColor(%s);", v, translateColor(n.selectionColor)));
        if (n.labelfont >= 0)
            line(format("%s.labelfont(%s);", v, translateFont(n.labelfont)));
        if (n.labelsize >= 0)
            line(format("%s.labelsize(%d);", v, n.labelsize));
        if (n.labelcolorRaw >= 0)
            line(format("%s.labelcolor(%s);", v, translateColor(n.labelcolorRaw)));
        if (n.labeltype.length)
            line(format("%s.labeltype(%s);", v, translateLabeltype(n.labeltype)));
        if (n.textsize >= 0)
            line(format("%s.textsize(%d);", v, n.textsize));
        if (n.textfont >= 0)
            line(format("%s.textfont(%s);", v, translateFont(n.textfont)));
        if (n.textcolorRaw >= 0)
            line(format("%s.textcolor(%s);", v, translateColor(n.textcolorRaw)));
        if (n.vLabelMargin >= 0)
            line(format("%s.verticalLabelMargin(%d);", v, n.vLabelMargin));
        if (n.hLabelMargin >= 0)
            line(format("%s.horizontalLabelMargin(%d);", v, n.hLabelMargin));
        if (n.imageSpacing >= 0)
            line(format("%s.labelImageSpacing(%d);", v, n.imageSpacing));
        // A window's own "type Double" selects the DoubleWindow class
        // itself (see className()) rather than a runtime .type() call
        // -- every other widget's "type" keyword *is* a real .type()
        // call (e.g. Fl_Button/Fl_Round_Button's "type Radio").
        if (n.typeWord.length && cast(WindowNode) n is null && !subtypePicksClass(n.typeName))
            line(format("%s.type(%s);", v, translateTypeWord(n.typeWord, n.typeName)));
        if (n.hasMinimum)
            line(format("%s.minimum(%s);", v, n.minimumRaw));
        if (n.hasMaximum)
            line(format("%s.maximum(%s);", v, n.maximumRaw));
        if (n.hasStep)
            line(format("%s.step(%s);", v, n.stepRaw));
        if (n.hasSliderSize)
            line(format("%s.sliderSize(%s);", v, n.sliderSizeRaw));
        if (n.hasShortcut)
            line(format("%s.shortcut(%s);", v, shortcutText(n.shortcutRaw)));
        if (n.hasValue)
            line(format("%s.value(%s);", v, n.valueRaw));
        if (n.hasCompact)
            line(format("%s.compact(%s);", v, n.compactRaw));
        if (n.alignRaw >= 0)
            line(format("%s.alignment(%s);", v, translateAlign(n.alignRaw)));
        // `whenRaw` is
        // parsed by `project_reader.d`, round-tripped by `project_writer.d`
        // to `.fl` text, and emitted here too, matching `panels/widget_panel.fl`'s
        // own When editor.
        if (n.whenRaw >= 0)
            line(format("%s.when(%s);", v, translateWhen(n.whenRaw)));
        if (n.tooltip.length)
            line(format(`%s.tooltip(%s);`, v, i18nWrap(n.tooltip)));
        writeWidgetImage(n, v);
        if (n.hidden)
            line(format("%s.hide();", v));
        if (n.deactivated)
            line(format("%s.deactivate();", v));
        if (n.hotspotFlag && (cast(MenuItemNode) n) is null)
        {
            // FLTK: `Widget_Node::write_widget_code()`'s own
            // `hotspot()` branch -- a window centers itself on itself
            // (`hotspot(var)`, matching real FLTK usage where the
            // flag is set directly on the window being shown, e.g. this
            // very file's own `make_widget_panel()`); a non-window
            // widget goes through its own `window()` instead. A
            // `Menu_Item_Node`'s own reuse of this flag as "divider" has
            // no live-widget-code meaning at all (it only affects how
            // the generated `Fl_Menu_Item` array literal is written,
            // handled elsewhere).
            if ((cast(WindowNode) n) !is null)
                line(format("%s.hotspot(%s);", v, v));
            else
                line(format("%s.window().hotspot(%s);", v, v));
        }
        // `callback` must be assigned *before* `setupCode` runs: a `setup{}` block
        // calling `o.doCallback()` -- a common, idiomatic way to apply a
        // widget's initial value by re-running its own callback -- would
        // otherwise silently invoke whatever callback happened to be set
        // *before* this widget's real one was ever assigned (FLTK's
        // own default no-op `Fl_Widget::default_callback()`), since the
        // real `.callback(...)` assignment wouldn't have executed yet.
        // `test/tree.fl`'s "Selection Mode"
        // `Choice` exercises this: its own `value(2)`
        // call takes effect regardless of this ordering, but the
        // tree itself needs the `doCallback()` there to actually apply
        // the dropdown's choice (`selectMulti`) rather than staying at
        // the class default `selectSingle`. Reordering has no other effect: callback *code* only
        // ever runs later, when actually invoked (a user interaction or
        // an explicit `doCallback()`), never at generation-emission time,
        // so no other widget's behavior changes from this reordering.
        // `user_data {expr}`: the widget's `userData` object, set before the
        // callback so the callback can rely on it. `expr` is D source and
        // must evaluate to an `Object`.
        if (n.userData.length)
            line(format("%s.userData = %s;", v, n.userData));
        if (n.callback.length)
            writeCallback(n, v);
        if (n.hasSetupCode && n.setupCode.length)
            writeTaggedBlock(Tag.setup, n, translateOwnSlot(n.setupCode, v));
    }

    /// A widget's `finalize` code: after its children and, for a group or
    /// window, before its `end()`, as FLTK's `write_code2()` places
    /// `extra_code(3)`. FLTK only tags this block for MergeBack in
    /// `Widget_Node::write_code2()` (widgets without children); here it
    /// is tagged for every widget, groups and windows included.
    private void writeFinalizeCode(WidgetNode n, string v)
    {
        if (n.hasFinalizeCode && n.finalizeCode.length)
            writeTaggedBlock(Tag.finalize, n, translateOwnSlot(n.finalizeCode, v));
    }

    private void writeCallback(WidgetNode n, string v)
    {
        // If this widget's own construction-time variable already IS
        // "o" (an anonymous leaf, per selfRef()'s naming scheme), the
        // closure must NOT redeclare "o" -- it's still lexically open
        // (we're nested inside that widget's own block), and D forbids
        // a nested scope shadowing an outer variable even when the
        // outer one is never used again afterward (confirmed via a
        // minimal repro). Simplest fix: don't redeclare at all -- just
        // capture and reuse the outer "o" directly, which already IS
        // this widget, correctly typed. Only a genuinely different
        // outer name (a named widget's own name, or "w"/"g1"-style
        // container names) needs the closure to introduce a fresh cast.
        if (v == "o")
        {
            line("o.callback((raw_) {");
            indent_++;
            writeTaggedBlock(Tag.widgetCallback, n, n.callback);
            indent_--;
            line("});");
            return;
        }
        line(format("%s.callback((raw) {", v));
        indent_++;
        line(format("auto o = cast(%s) raw;", className(n)));
        writeTaggedBlock(Tag.widgetCallback, n, n.callback);
        indent_--;
        line("});");
    }

    /// Emits `n.comment` as a doc comment immediately before this
    /// node's own generated code block -- matches FLTK's own
    /// `Node::write_comment_c()` (a real comment written into
    /// generated output, not just editor-only metadata the way
    /// `open_`/`selected_` are; confirmed by reading `Node.cxx`'s own
    /// `write_comment_c()`/`write_comment_h()`). Matches
    /// `panels/widget_panel.fl`'s own "Comment:" field:
    /// `comment` is
    /// parsed by `project_reader.d`, `.fl`-round-tripped by
    /// `project_writer.d`, and emitted here too. Called
    /// from every root-node-kind's own writer separately, since none
    /// of them share a single dispatch point the way the widget tree
    /// does: `writeWidgetTree()` (every `WidgetNode`-family node),
    /// `writeClassNode()`, `writeDeclChild()` and `writeCodeNode()` (Code
    /// nodes at every scope), `writeConditionalDecl()`, and all
    /// three `FunctionNode`-writing shapes (`writePlainFunction()`,
    /// `writeFunctionBody()` for the
    /// anonymous main Function, `writeClassMethod()`). Not to be confused with root
    /// *comment-type* nodes (FLTK's `Comment_Node`, a `.fl` file's
    /// own header comment), which are a separate thing entirely and are
    /// written by `writeRootComment()` and `writeWidgetTree()`.
    private void writeNodeComment(Node n)
    {
        writeCommentText(n.comment);
    }

    /// Shared by `writeNodeComment()` (a node's own `.comment`
    /// property) and `generate()` (a Comment node's text): a block
    /// comment with the text's lines as they are, so an editor can
    /// rewrap them freely. Text that contains `*/` would end a `/* */`
    /// comment early, so it goes in D's nesting `/+ +/` instead.
    private void writeCommentText(string text)
    {
        import std.algorithm.searching : canFind;

        if (!text.length) return;
        immutable nesting = text.canFind("*/");
        line(nesting ? "/+" : "/*");
        foreach (ln; text.lineSplitter())
            if (ln.length) line(ln); else blank();
        line(nesting ? "+/" : "*/");
    }

    /// Real C preprocessor directives -- never legal D, so a line
    /// starting with one of these is a hard, unambiguous signal that
    /// the `.fl` being fed to this generator is a raw, unconverted copy
    /// of real FLTK C++ (FLTK's own `.fl` dialect embeds C++ in
    /// `code`/`callback`/`setup` bodies; this project's own dialect
    /// requires literal D there instead -- see this module's own top
    /// comment and `FLUID_DIALECT.md`'s "dialect pivot" section). Found for
    /// real: `panels/widget_panel.fl`, copied verbatim from FLTK as
    /// reference material and never converted, used to run through
    /// `fluid -c` in silence and emit literally-uncompilable `#include`
    /// lines straight into the generated `.d` -- see this file's own
    /// `collectClassOverrideImports()` for the second half of that same
    /// incident (C++ `::`-scoped class names).
    private static immutable string[] cPreprocessorDirectives = [
        "#include", "#define", "#undef", "#ifdef", "#ifndef", "#if",
        "#elif", "#else", "#endif", "#pragma", "#error", "#warning",
    ];

    /// Throws if `trimmed` (a stripped line of snippet text) starts with a
    /// C preprocessor directive -- see `cPreprocessorDirectives`.
    private void rejectPreprocessorDirective(string trimmed)
    {
        foreach (d; cPreprocessorDirectives)
            if (trimmed.startsWith(d))
                throw new Exception(format(
                    "this `.fl` file contains a raw C preprocessor directive (\"%s\") -- "
                    ~ "it looks like an unconverted copy of real FLTK C++, not this "
                    ~ "project's own D-embedded `.fl` dialect. Convert its code/callback/"
                    ~ "setup/decl bodies to real D before running them through `fluid -c` "
                    ~ "(see TRANSLITERATION_GUIDE.md for the technique, or CONVENTIONS.md's "
                    ~ "code_writer.d note on the \"beauty of D\" pivot).", trimmed));
    }

    private void emitSnippetLines(string s)
    {
        foreach (ln; s.lineSplitter())
        {
            auto t = strip(ln);
            if (t.length)
            {
                rejectPreprocessorDirective(t);
                line(t);
            }
        }
    }

    /// Like `emitSnippetLines()`, but keeps each line's own leading
    /// whitespace (after the current indentation) and its blank lines,
    /// so the block in the file is the snippet's text plus a uniform
    /// indent -- what `fluid.mergeback.unindentBlock()` undoes.
    private void emitSnippetBlock(string s)
    {
        foreach (ln; s.lineSplitter())
        {
            if (strip(ln).length == 0)
            {
                blank();
                continue;
            }
            rejectPreprocessorDirective(strip(ln));
            line(ln);
        }
    }

    /// Writes one MergeBack tag line at the current indentation: the
    /// tag carries the CRC of everything written since the previous tag.
    /// Ported from `Code_Writer::tag()`. Does nothing unless the project
    /// has MergeBack enabled.
    private void tag(Tag prevType, Tag nextType, ushort uid)
    {
        if (!settings_.writeMergebackData)
            return;
        Crc32 crc;
        crc.update(buf.data[tagStart_ .. $]);
        foreach (i; 0 .. indent_)
            buf.put("    ");
        buf.put(formatTag(prevType, nextType, uid, crc.value));
        tagStart_ = buf.data.length;
    }

    /// Emits the user-editable text `s` of node `n` (a `code {}`
    /// fragment, a callback body, setup or finalize code) and records
    /// where it went in `n.blockSpans[kind]`. With MergeBack enabled the
    /// block is bracketed by tag lines and written with its own
    /// indentation and blank lines intact; otherwise it is emitted as
    /// plain `emitSnippetLines()`.
    private void writeTaggedBlock(Tag kind, Node n, string s)
    {
        if (!settings_.writeMergebackData)
        {
            immutable start = pos();
            emitSnippetLines(s);
            n.blockSpans[kind] = TextSpan(start, pos());
            return;
        }
        tag(Tag.generic, kind, 0);
        immutable start = pos();
        emitSnippetBlock(s);
        n.blockSpans[kind] = TextSpan(start, pos());
        tag(kind, Tag.generic, n.uid);
    }

    private string translateBoxtype(string kw)
    {
        if (auto p = kw in boxtypeMap)
            return *p;
        throw new Exception(format(`unknown box keyword "%s" -- not one of this dialect's own `
            ~ `boxtype names (see code_writer.d's boxtypeMap)`, kw));
    }

    private static string translateColor(int c)
    {
        if (auto p = c in colorNameMap)
            return *p;
        return format("cast(Color) %d", c);
    }

    private string translateFont(int f)
    {
        if (auto p = f in fontMap)
            return *p;
        return format("cast(Font) %d", f);
    }

    /// The D expression for a widget's `type` keyword: the widget kind's own
    /// subtype table first (`fluid.subtypes`, where the same keyword can mean
    /// different values for different kinds), then the flat `typeWordMap`
    /// for kinds without a table.
    private string translateTypeWord(string kw, string typeName)
    {
        if (auto st = subtypeFor(typeName, kw))
            return st.dName;
        if (auto p = kw in typeWordMap)
            return *p;
        throw new Exception(format(`unknown type keyword "%s" -- not one of this dialect's own `
            ~ `type names (see code_writer.d's typeWordMap)`, kw));
    }

    private string translateLabeltype(string kw)
    {
        if (auto p = kw in labeltypeMap)
            return *p;
        throw new Exception(format(`unknown labeltype keyword "%s" -- not one of this dialect's `
            ~ `own labeltype names (see code_writer.d's labeltypeMap)`, kw));
    }

    /// The D expression for an `align` value: the `fl.enumerations`
    /// names joined with `|` (`alignLeft`, `alignTopLeft | alignInside`),
    /// `alignCenter` for 0. Bits without a name are kept as a hex number.
    private static string translateAlign(int raw)
    {
        static immutable string[int] posNames = [
            0x1: "alignTop", 0x2: "alignBottom", 0x4: "alignLeft", 0x8: "alignRight",
            0x5: "alignTopLeft", 0x9: "alignTopRight",
            0x6: "alignBottomLeft", 0xa: "alignBottomRight",
            0x7: "alignLeftTop", 0xb: "alignRightTop",
            0xd: "alignLeftBottom", 0xe: "alignRightBottom",
        ];
        static immutable string[int] imageNames = [
            0x020: "alignTextOverImage", 0x100: "alignImageNextToText",
            0x120: "alignTextNextToImage", 0x200: "alignImageBackdrop",
        ];
        string[] parts;
        int rest = raw;
        if (auto p = (raw & 0xf) in posNames) { parts ~= *p; rest &= ~0xf; }
        if (auto p = (raw & 0x320) in imageNames) { parts ~= *p; rest &= ~0x320; }
        if (raw & alignInsideBit) { parts ~= "alignInside"; rest &= ~alignInsideBit; }
        if (raw & 0x40) { parts ~= "alignClip"; rest &= ~0x40; }
        if (raw & 0x80) { parts ~= "alignWrap"; rest &= ~0x80; }
        if (rest) parts ~= format("0x%x", rest);
        return parts.length ? parts.join(" | ") : "alignCenter";
    }

    /// `raw` as `fl.enumerations`-style names joined with `|`: `names`
    /// lists each named value, combined ones before the bits they hold,
    /// and every name whose bits are all in what is left is taken. `zero`
    /// is the name for 0; bits without a name are kept as a hex number.
    private struct NamedBits { int value; string name; }

    private static string bitNames(int raw, const NamedBits[] names, string zero)
    {
        string[] parts;
        int rest = raw;
        foreach (nb; names)
            if ((rest & nb.value) == nb.value)
            {
                parts ~= nb.name;
                rest &= ~nb.value;
            }
        if (rest) parts ~= format("0x%x", rest);
        return parts.length ? parts.join(" | ") : zero;
    }

    /// The D expression for a `when` value (`whenChanged | whenRelease`).
    private static string translateWhen(int raw)
    {
        static immutable NamedBits[] names = [
            NamedBits(16, "whenClosed"), NamedBits(11, "whenEnterKeyChanged"), NamedBits(10, "whenEnterKeyAlways"),
            NamedBits(8, "whenEnterKey"), NamedBits(6, "whenReleaseAlways"), NamedBits(4, "whenRelease"),
            NamedBits(2, "whenNotChanged"), NamedBits(1, "whenChanged"),
        ];
        return bitNames(raw, names, "whenNever");
    }

    /// The D expression for a grid cell's alignment (`gridTopLeft`, `gridFill`).
    private static string translateGridAlign(int raw)
    {
        static immutable NamedBits[] names = [
            NamedBits(0x30, "gridFill"), NamedBits(0x10, "gridHorizontal"), NamedBits(0x20, "gridVertical"),
            NamedBits(0x40, "gridProportional"),
            NamedBits(0x5, "gridTopLeft"), NamedBits(0x9, "gridTopRight"), NamedBits(0x6, "gridBottomLeft"),
            NamedBits(0xa, "gridBottomRight"), NamedBits(0x1, "gridTop"), NamedBits(0x2, "gridBottom"),
            NamedBits(0x4, "gridLeft"), NamedBits(0x8, "gridRight"),
        ];
        return bitNames(raw, names, "gridCenter");
    }

    unittest
    {
        assert(translateColor(88) == "red");
        assert(translateColor(49) == "backgroundColor");
        assert(translateColor(15) == "fl.enumerations.selectionColor");
        assert(translateColor(100) == "cast(Color) 100");
    }

    unittest
    {
        assert(translateWhen(0) == "whenNever");
        assert(translateWhen(5) == "whenRelease | whenChanged");
        assert(translateWhen(6) == "whenReleaseAlways");
        assert(translateWhen(11) == "whenEnterKeyChanged");
        assert(translateWhen(16 | 1) == "whenClosed | whenChanged");
        assert(translateWhen(0x20) == "0x20");
        assert(translateGridAlign(0) == "gridCenter");
        assert(translateGridAlign(0x30) == "gridFill");
        assert(translateGridAlign(0x5) == "gridTopLeft");
        assert(translateGridAlign(0x10 | 0x8) == "gridHorizontal | gridRight");
    }

    unittest
    {
        assert(translateAlign(0) == "alignCenter");
        assert(translateAlign(4) == "alignLeft");
        assert(translateAlign(0x5 | 0x10) == "alignTopLeft | alignInside");
        assert(translateAlign(0x4 | 0x10 | 0x80) == "alignLeft | alignInside | alignWrap");
        assert(translateAlign(0x120 | 0x8) == "alignRight | alignTextNextToImage");
        assert(translateAlign(0x3) == "0x3");
    }
}

/// "Fl_Round_Button" -> "RoundButton" -- strips the "Fl_" prefix *and*
/// collapses the remaining underscores (every multi-word FLTK type
/// name is already word-capitalized on each side of its underscores,
/// e.g. "Round_Button", so a plain removal is enough, no re-casing
/// needed). `package(fluid)` (not `private`) so `fluid.instantiate.
/// idealSizeFor()` can reuse it too -- see that function's own note on
/// why it needs the same normalization.
package(fluid) string stripFlPrefix(string typeName)
{
    import std.string : replace;
    string s = (typeName.length > 3 && typeName[0 .. 3] == "Fl_") ? typeName[3 .. $] : typeName;
    return s.replace("_", "");
}

/// Writes a widget/menu-item shortcut integer as a D expression, the
/// modifier bits by name and the key as a character literal when it is
/// printable ASCII, else as an 8-digit hex constant. Ported from the
/// shortcut-writing blocks of `Widget_Node::write_code1()` and
/// `Menu_Item_Node::write_code1()`.
///
/// `useFlCommand` (`ProjectSettings.useFlCommand`): the modifier bit
/// that equals `stateCommand` is written as `stateCommand` and the bit
/// that equals `stateControl` as `stateControl`, so the shortcut keeps
/// its meaning when the generated program is built for a platform that
/// swaps the two (`fl.enumerations` maps them for X11 only, but the
/// names are the portable spelling). FLTK's own block instead
/// writes the `FL_CTRL` bit as `FL_CONTROL` and the `FL_META` bit as
/// `FL_COMMAND`, which only preserves the meaning when Fluid itself
/// runs on macOS (see `FLTK_ISSUES_n.md`).
package(fluid) string shortcutExpression(uint s, bool useFlCommand)
{
    string r;
    if (useFlCommand)
    {
        if (s & stateCommand) { r ~= "stateCommand|"; s &= ~stateCommand; }
        if (s & stateControl) { r ~= "stateControl|"; s &= ~stateControl; }
    }
    else
    {
        if (s & stateCtrl) { r ~= "stateCtrl|"; s &= ~stateCtrl; }
        if (s & stateMeta) { r ~= "stateMeta|"; s &= ~stateMeta; }
    }
    if (s & stateShift) { r ~= "stateShift|"; s &= ~stateShift; }
    if (s & stateAlt) { r ~= "stateAlt|"; s &= ~stateAlt; }
    if (s < 127 && s >= 32)
    {
        char c = cast(char) s;
        if (c == '\'' || c == '\\')
            r ~= format("'\\%c'", c);
        else
            r ~= format("'%c'", c);
    }
    else
        r ~= format("0x%08x", s);
    return r;
}

private string dStringEscape(string s)
{
    auto a = appender!string();
    foreach (c; s)
    {
        if (c == '"') a.put(`\"`);
        else if (c == '\\') a.put(`\\`);
        else if (c == '\n') a.put(`\n`);
        else if (c == '\r') a.put(`\r`);
        else if (c == '\t') a.put(`\t`);
        else a.put(c);
    }
    return a.data;
}

/// The bare name of a named Function, from its `instanceName`, the
/// full D signature text (e.g. "buttonCB(Button b)" -> "buttonCB").
private string functionName(string sig)
{
    auto parenIdx = sig.indexOf('(');
    return (parenIdx < 0 ? sig : sig[0 .. parenIdx]).strip();
}

/// `class Foo` overrides that are already real fldtk classes reachable
/// via the fixed `import fl;` above -- no separate hand-written
/// companion module to import. First real case: tabs.fl's `class
/// Window` (a plain `Fl_Group { ... class Fl_Window }` FLTK node,
/// i.e. "instantiate the real subwindow class here, not a custom
/// subclass" -- confirmed against FLTK's own `Fl_Type::write_c()`
/// dispatch, which special-cases exactly this "class name matches a
/// known base type" case the same way).
///
/// Exhaustive, not a "grown as hit" set:
/// every class name (`class`/`abstract class`) declared across
/// `source/fl/*.d`, plus the two rename-on-import aliases
/// (`ToggleLightButton`/`ToggleRoundButton`, `fl.toggle_light_button`/
/// `fl.toggle_round_button`'s own `public import fl.X : Alias = Real;`
/// re-exports) -- i.e. every name actually reachable via `import fl;`.
/// Regenerate this list
/// the same way (`grep -rhoP '^(public\s+)?(abstract\s+)?class\s+\K\w+'
/// source/fl/*.d | sort -u`, plus the two aliases) if `source/fl/`
/// gains a new public class.
private immutable string[] builtinClassNames = [
    "Adjuster", "AnimGifImage", "BMPImage", "Bitmap", "Box", "Browser", "Browser_",
    "Button", "Cell", "Chart", "CheckBrowser", "CheckButton", "Choice",
    "ClockOutput", "ColorChooser", "CopySurface", "Counter", "Dial", "DoubleWindow",
    "EpsFileSurface", "FileBrowser", "FileChooser", "FileIcon", "FileInput",
    "FillDial", "FillSlider", "FlClock", "FlGroup", "Flex", "FloatInput", "GifImage",
    "GlWindow", "GlutWindow", "GraphicsDriver", "Grid", "HelpDialog", "HelpView", "HtmlDialog", "HtmlView",
    "HoldBrowser", "HorFillSlider", "HorNiceSlider", "HorSlider", "HorValueSlider",
    "ICOImage", "Image", "ImageSurface", "Input", "InputChoice", "Input_",
    "IntInput", "JpegImage", "LightButton", "LineDial", "MarkdownDialog", "MarkdownView", "MenuBar", "MenuButton",
    "MenuWindow", "Menu_", "MultiBrowser", "MultiLabel", "MultilineInput",
    "MultilineOutput", "NativeFileChooser", "NiceSlider", "Output", "OverlayWindow",
    "PNMImage", "Pack", "PagedDevice", "Pixmap", "PngImage", "Positioner",
    "PostscriptFileDevice", "PostscriptGraphicsDriver", "Preferences", "Printer",
    "Progress", "RGBImage", "RadioButton", "RadioLightButton", "RadioRoundButton",
    "RepeatButton", "ReturnButton", "Roller", "RoundButton", "RoundClock",
    "SchemeChoice", "Scroll", "Scrollbar", "SecretInput", "SelectBrowser",
    "SharedImage", "ShortcutButton", "SimpleCounter", "SingleWindow", "Slider",
    "Spinner", "SurfaceDevice", "SvgFileSurface", "SvgGraphicsDriver", "SysMenuBar",
    "Table", "TableRow", "Tabs", "Terminal", "TextBuffer", "TextDisplay",
    "TextEditor", "Tile", "TiledImage", "ToggleButton", "ToggleLightButton",
    "ToggleRoundButton", "Tree", "TreeItem", "TreePrefs", "Valuator", "ValueInput",
    "ValueOutput", "ValueSlider", "Widget", "WidgetSurface", "Window", "Wizard",
    "XBMImage", "XPMImage",
];

/// A `class Foo` property (see `className()`) names a pre-existing D
/// class -- either one of `builtinClassNames` above (already reachable
/// via `import fl;`, nothing more to do), or a hand-written class
/// living in its own module. D resolves an import by the *file's* own
/// name, not any class or module declaration inside it, so this can
/// only guess correctly when the file happens to be named after the
/// class (a real, common convention, but not a guarantee). `moduleCode`
/// -- the text of this file's own root-level Code nodes -- gets first say:
/// if one of them already imports a given class name explicitly (the
/// `.fl` author's own choice, needed whenever the convention doesn't
/// hold), this function leaves that class alone instead of also
/// emitting a guessed import that would either be redundant or wrong.
/// Collects every distinct non-builtin, not-already-imported override
/// across the whole tree (module-level import dedup, same as a
/// hand-written file would only import a module once). **A wildcard
/// Code-node import (`import fluid;`/`import fl;`, no `: sym, ...`
/// restriction) disables guessing entirely for the whole file**
/// (e.g. `widget_panel.fl`'s
/// own many selective `fluid.*` imports, consolidated into one `import fluid;`,
/// via `fluid/package.d`'s aggregator) -- this module has no way
/// to introspect another module's actual exported symbol list at
/// codegen time, so it can't tell *which* override names a wildcard
/// covers, but guessing anyway would be strictly worse than doing
/// nothing whenever it does: an override the wildcard already resolves
/// (`class {FormulaInput}`, real `fluid.formula_input.
/// FormulaInput`) would otherwise get a wrong guessed `import FormulaInput : FormulaInput;`
/// against a nonexistent module `FormulaInput`, instead of
/// none at all. A genuinely uncovered hand-
/// written companion class still needs its own explicit import from
/// the `.fl` author, same as always.
private string[] collectClassOverrideImports(Node[] nodes, bool[string] localClasses, string[] moduleCode)
{
    import std.algorithm.searching : canFind;

    bool[string] explicitlyImported;
    // A wildcard `import fluid;`/`import fl;`-shaped import (no `: sym,
    // ...` restriction at all) can't be resolved to a specific symbol
    // list the way a selective import can -- but it also makes
    // *guessing* strictly worse than doing nothing: a class-override
    // name genuinely covered by the wildcard (e.g. `class {FormulaInput}`,
    // covered by `widget_panel.fl`'s own consolidated
    // `import fluid;`) would
    // otherwise get a wrong guessed `import FormulaInput : FormulaInput;`
    // even though it's already in scope. So any such wildcard disables
    // guessing for the *whole file* rather than trying to track which
    // specific names it covers (this module has no way to introspect
    // another module's actual exported symbol list at codegen time) --
    // a genuinely uncovered hand-written companion class still needs
    // its own explicit import from the `.fl` author, same as always.
    bool haveWildcardImport;
    import std.ascii : isWhite;

    // Each import declaration in the module-scope code: `import x;`,
    // `public import x;`, `import x : a, b;` (a string import,
    // `import("file")`, is an expression and doesn't count).
    foreach (text; moduleCode)
        foreach (statement; text.split(";"))
        {
            string st = statement.strip;
            foreach (attr; ["public ", "private ", "package ", "static "])
                if (st.startsWith(attr)) st = st[attr.length .. $].strip;
            if (!st.startsWith("import") || st.length < 7 || !isWhite(st[6])) continue;
            auto colon = st.indexOf(':');
            if (colon < 0)
            {
                haveWildcardImport = true;
                continue;
            }
            foreach (sym; st[colon + 1 .. $].split(","))
                explicitlyImported[sym.strip] = true;
        }

    if (haveWildcardImport) return [];

    bool[string] seen;
    string[] result;
    // A `class X` override naming a class this same file defines (a
    // Class node, or a class in a Code node, as in terminal.fl, where a
    // Terminal widget uses `MyTerminal`) needs no import either.
    foreach (name; localClasses.byKey)
        seen[name] = true;
    foreach (name; explicitlyImported.byKey)
        seen[name] = true;
    void walk(Node[] ns)
    {
        foreach (n; ns)
        {
            if (auto w = cast(WidgetNode) n)
                if (w.hasClassOverride && w.classOverride !in seen
                    && !builtinClassNames.canFind(w.classOverride))
                {
                    // A C++ `namespace::`-qualified name is never a
                    // valid bare D module/class name -- the same "raw,
                    // unconverted FLTK C++ .fl" signal
                    // `emitSnippetLines()` guards against for
                    // `#include` lines.
                    if (w.classOverride.canFind("::"))
                        throw new Exception(format(
                            "this `.fl` file has a C++ `namespace::`-qualified class override "
                            ~ "(\"%s\") -- it looks like an unconverted copy of real FLTK C++, "
                            ~ "not this project's own D-embedded `.fl` dialect. Rewrite it as a "
                            ~ "plain D module/class name before running it through `fluid -c`.",
                            w.classOverride));
                    seen[w.classOverride] = true;
                    result ~= w.classOverride;
                }
            walk(n.children);
        }
    }
    walk(nodes);
    return result;
}

/// The text of every root-level Code node: the file's module-scope
/// imports and declarations, for `collectClassOverrideImports()`.
string[] moduleCodeTexts(Node[] roots)
{
    string[] texts;
    foreach (r; roots)
        if (cast(CodeNode) r)
            texts ~= r.instanceName;
    return texts;
}

/// The classes a file defines: its Class nodes, anywhere in the tree,
/// and every `class`, `struct` or `interface` declared in a Code node's
/// text, so a widget's `class` override naming one needs no import.
bool[string] localClassNames(Node[] roots)
{
    import std.regex : matchAll, ctRegex;

    bool[string] names;
    void walk(Node[] ns)
    {
        foreach (n; ns)
        {
            if (cast(ClassNode) n)
                names[n.instanceName] = true;
            else if (cast(CodeNode) n)
                foreach (m; n.instanceName.matchAll(ctRegex!`\b(?:class|struct|interface)\s+([A-Za-z_]\w*)`))
                    names[m[1]] = true;
            walk(n.children);
        }
    }
    walk(roots);
    return names;
}

/// Substitutes a bare `o` token (construction-time convention: "this
/// widget's own variable") with its real name, leaving strings, comments
/// and member accesses alone (`fluid.code_highlight.renameIdentifier()`)
/// -- used only for `setup` bodies, which run inline in a widget's own property
/// list, not inside a freshly-introduced closure (contrast
/// `writeCallback()`'s body, which needs no substitution at all -- see
/// this module's own doc comment on the "o" convention).
private string translateOwnSlot(string code, string v)
{
    return renameIdentifier(code, "o", v);
}

unittest
{
    import std.algorithm : canFind;

    // Regression coverage for `writeOneImage()`'s native-
    // representation path (`fluid/proj/Image_Asset` port)
    // against a real XPM fixture already in this repo: it must not
    // emit `new XPMImage("name", bytes)`, a constructor overload
    // `fl.xpm_image.XPMImage` (`this(string filename)` only) doesn't
    // have, which would fail to compile for any `.xpm`/`.xbm` image slot.
    // XPM's `Pixmap`-native dispatch applies
    // regardless of `compressImage` (matching FLTK's own
    // unconditional `image_->count() > 1` branch), so the default
    // `compressImage = true` here is deliberately left at its default,
    // not set to `false` -- this exercises the "compress requested but
    // not eligible for this format" fallback, not just the "compress
    // off" case.
    auto mainFn = new FunctionNode();
    mainFn.typeName = "Function";

    auto win = new WindowNode();
    win.typeName = "Fl_Window";
    win.instanceName = "win";
    win.x = 0; win.y = 0; win.w = 100; win.h = 100;
    win.hasXywh = true;
    mainFn.addChild(win);

    auto box = new WidgetNode();
    box.typeName = "Fl_Box";
    box.instanceName = "box";
    box.x = 0; box.y = 0; box.w = 32; box.h = 32;
    box.hasXywh = true;
    box.imageFilename = "pixmaps/magenta.xpm";
    box.hasImage = true;
    win.addChild(box);

    string text = new Writer().generate([mainFn], "source/test");

    assert(text.canFind("new Pixmap("));
    assert(!text.canFind("new XPMImage("));
    assert(text.canFind("box.image(new Pixmap(imgBytes0));"));
}

unittest
{
    // Conditional nodes: one at the top wrapping a Code node's
    // declaration, and one among a window's widgets wrapping a Code
    // node's statement. The writer supplies the braces around the
    // children.
    import std.algorithm : canFind;

    auto declBlock = new ConditionalNode();
    declBlock.typeName = "conditional";
    declBlock.instanceName = "version (Windows)";

    auto decl = new CodeNode();
    decl.typeName = "code";
    decl.instanceName = "int winOnlyDecl;";
    declBlock.addChild(decl);

    auto win = new WindowNode();
    win.typeName = "Fl_Window";
    win.instanceName = "w";
    win.x = 0; win.y = 0; win.w = 100; win.h = 100;
    win.hasXywh = true;

    auto codeBlock = new ConditionalNode();
    codeBlock.typeName = "conditional";
    codeBlock.instanceName = "if (someCondition())";
    win.addChild(codeBlock);

    auto code = new CodeNode();
    code.typeName = "code";
    code.instanceName = "writeln(\"inside\");";
    codeBlock.addChild(code);

    auto mainFn = new FunctionNode();
    mainFn.typeName = "Function";
    mainFn.addChild(win);

    string text = new Writer().generate([declBlock, mainFn]);

    assert(text.canFind("version (Windows) {"));
    assert(text.canFind("int winOnlyDecl;"));
    assert(text.canFind("if (someCondition()) {"));
    assert(text.canFind("writeln(\"inside\");"));
    assert(!text.canFind("} version"));
    assert(!text.canFind("} if"));
}

unittest
{
    // Plain widget label/tooltip
    // translation wrapping, both GNU and POSIX. No i18n at all keeps
    // emitting a plain quoted literal -- checked first so a regression here can't
    // hide behind the wrapped-output assertions below.
    import std.algorithm : canFind;
    import fluid.i18n : I18nSettings, I18nType;

    auto mainFn = new FunctionNode();
    mainFn.typeName = "Function";

    auto win = new WindowNode();
    win.typeName = "Fl_Window";
    win.instanceName = "win";
    win.x = 0; win.y = 0; win.w = 100; win.h = 100;
    win.hasXywh = true;
    win.label = "Hello";
    win.hasLabel = true;
    mainFn.addChild(win);

    auto box = new WidgetNode();
    box.typeName = "Fl_Box";
    box.instanceName = "box";
    box.x = 0; box.y = 0; box.w = 32; box.h = 32;
    box.hasXywh = true;
    box.label = "World";
    box.hasLabel = true;
    box.tooltip = "A tip";
    win.addChild(box);

    string textNone = new Writer().generate([mainFn]);
    assert(textNone.canFind(`"Hello"`));
    assert(textNone.canFind(`"World"`));
    assert(textNone.canFind(`box.tooltip("A tip");`));

    I18nSettings gnu;
    gnu.type = I18nType.gnu;
    gnu.gnuFunction = "_";
    string textGnu = new Writer().generate([mainFn], ".", gnu);
    assert(textGnu.canFind(`_("Hello")`));
    assert(textGnu.canFind(`_("World")`));
    assert(textGnu.canFind(`box.tooltip(_("A tip"));`));

    I18nSettings posix;
    posix.type = I18nType.posix;
    posix.posixSet = "1";
    string textPosix = new Writer().generate([mainFn], ".", posix);
    assert(textPosix.canFind(`catgets(_catalog, 1, 1, "Hello")`));
    assert(textPosix.canFind(`catgets(_catalog, 1, 2, "World")`));
    assert(textPosix.canFind(`box.tooltip(catgets(_catalog, 1, 3, "A tip"));`));
}

unittest
{
    // A code node among a window's children is written in its place,
    // after the widgets before it and before the ones after it.
    import std.string : indexOf;

    auto mainFn = new FunctionNode();
    mainFn.typeName = "Function";
    auto win = new WindowNode();
    win.typeName = "Window";
    win.w = 100; win.h = 100;
    win.hasXywh = true;
    mainFn.addChild(win);
    auto first = new WidgetNode();
    first.typeName = "Box";
    first.instanceName = "first";
    first.w = 10; first.h = 10;
    first.hasXywh = true;
    win.addChild(first);
    auto code = new CodeNode();
    code.instanceName = `writeln("in the window");`;
    win.addChild(code);
    auto second = new WidgetNode();
    second.typeName = "Box";
    second.instanceName = "second";
    second.w = 10; second.h = 10;
    second.hasXywh = true;
    win.addChild(second);

    string text = new Writer().generate([mainFn]);
    auto at = text.indexOf(`writeln("in the window");`);
    assert(at >= 0);
    assert(text.indexOf("first = new Box(") < at);
    assert(at < text.indexOf("second = new Box("));
}

unittest
{
    // Menu item label translation -- `writeMenuItemLiteral()`
    // wraps `MenuItem` labels via the same `i18nWrap()` every other
    // label goes through, single-phase (`gettext(...)`/`catgets(...)`
    // called directly in the array-literal element, not FLTK's own
    // two-phase static-declare-then-runtime-reassign dance -- see that
    // function's own doc comment for why the reason FLTK needs that
    // doesn't apply to this port's own always-runtime `MenuItem[]`
    // array). No i18n keeps emitting a plain quoted literal, checked
    // first for the same reason the plain-widget-label test above does.
    import std.algorithm : canFind;
    import fluid.i18n : I18nSettings, I18nType;
    import fluid.menu_owner_node : MenuOwnerNode;

    auto mainFn = new FunctionNode();
    mainFn.typeName = "Function";

    auto win = new WindowNode();
    win.typeName = "Fl_Window";
    win.instanceName = "win";
    win.x = 0; win.y = 0; win.w = 200; win.h = 100;
    win.hasXywh = true;
    mainFn.addChild(win);

    auto box = new WidgetNode();
    box.typeName = "Fl_Box";
    box.instanceName = "box";
    box.x = 0; box.y = 0; box.w = 32; box.h = 32;
    box.hasXywh = true;
    box.label = "First";
    box.hasLabel = true;
    win.addChild(box);

    auto menu = new MenuOwnerNode();
    menu.typeName = "Fl_Menu_Button";
    menu.instanceName = "menu";
    menu.x = 0; menu.y = 40; menu.w = 100; menu.h = 24;
    menu.hasXywh = true;
    win.addChild(menu);

    auto item = new MenuItemNode();
    item.typeName = "MenuItem";
    item.label = "Open";
    item.hasLabel = true;
    menu.addChild(item);

    string textNone = new Writer().generate([mainFn]);
    assert(textNone.canFind(`MenuItem("Open"`));

    I18nSettings gnu;
    gnu.type = I18nType.gnu;
    gnu.gnuFunction = "_";
    string textGnu = new Writer().generate([mainFn], ".", gnu);
    assert(textGnu.canFind(`_("First")`));
    assert(textGnu.canFind(`MenuItem(_("Open")`));

    // Continues the same running counter every other label/tooltip in
    // this file shares -- "First" (the box, emitted before the menu)
    // is message 1, "Open" (the menu item) is message 2.
    I18nSettings posix;
    posix.type = I18nType.posix;
    posix.posixSet = "1";
    string textPosix = new Writer().generate([mainFn], ".", posix);
    assert(textPosix.canFind(`catgets(_catalog, 1, 1, "First")`));
    assert(textPosix.canFind(`MenuItem(catgets(_catalog, 1, 2, "Open")`));
}

unittest
{
    // `menuItemFlags()`: `MenuItemNode.hotspotFlag`
    // ("divider" reuse) and `.headline_` are both real,
    // round-tripped properties feeding
    // the flags slot in every emitted `MenuItem(...)` literal. Confirms both bits are combined correctly, independently,
    // and that an item with neither set still emits a plain `0`.
    import std.algorithm : canFind;
    import fluid.menu_owner_node : MenuOwnerNode;

    auto mainFn = new FunctionNode();
    mainFn.typeName = "Function";

    auto win = new WindowNode();
    win.typeName = "Fl_Window";
    win.instanceName = "win";
    win.x = 0; win.y = 0; win.w = 200; win.h = 100;
    win.hasXywh = true;
    mainFn.addChild(win);

    auto menu = new MenuOwnerNode();
    menu.typeName = "Fl_Menu_Button";
    menu.instanceName = "menu";
    menu.x = 0; menu.y = 0; menu.w = 100; menu.h = 24;
    menu.hasXywh = true;
    win.addChild(menu);

    auto plain = new MenuItemNode();
    plain.typeName = "MenuItem";
    plain.label = "Plain";
    plain.hasLabel = true;
    menu.addChild(plain);

    auto divider = new MenuItemNode();
    divider.typeName = "MenuItem";
    divider.label = "Divider";
    divider.hasLabel = true;
    divider.hotspotFlag = true;
    menu.addChild(divider);

    auto section = new MenuItemNode();
    section.typeName = "MenuItem";
    section.label = "Section";
    section.hasLabel = true;
    section.headline_ = true;
    menu.addChild(section);

    auto both = new MenuItemNode();
    both.typeName = "MenuItem";
    both.label = "Both";
    both.hasLabel = true;
    both.hotspotFlag = true;
    both.headline_ = true;
    menu.addChild(both);

    string text = new Writer().generate([mainFn]);
    assert(text.canFind(`MenuItem("Plain", 0, null, 0,`));
    assert(text.canFind(`MenuItem("Divider", 0, null, menuDivider,`));
    assert(text.canFind(`MenuItem("Section", 0, null, menuHeadline,`));
    assert(text.canFind(`MenuItem("Both", 0, null, menuDivider | menuHeadline,`));
}

unittest
{
    // Regression coverage for `menuItemFlags()`'s `menuSubmenu`/`menuToggle`/
    // `menuRadio` cases, and `writeMenuItemChildren()`'s recursive
    // descent into a `SubmenuNode` -- including one with zero children,
    // which must still close with its own `MenuItem(null),` sentinel
    // (see that function's own doc comment for why this isn't optional:
    // a missing one makes `fl.menu_item.validateMenuArray()` throw at
    // runtime, a data problem no compile-time check catches).
    import std.algorithm : canFind, countUntil;
    import fluid.menu_owner_node : MenuOwnerNode;
    import fluid.menu_item_node : SubmenuNode;

    auto mainFn = new FunctionNode();
    mainFn.typeName = "Function";

    auto win = new WindowNode();
    win.typeName = "Fl_Window";
    win.instanceName = "win";
    win.x = 0; win.y = 0; win.w = 200; win.h = 100;
    win.hasXywh = true;
    mainFn.addChild(win);

    auto menu = new MenuOwnerNode();
    menu.typeName = "Fl_Menu_Button";
    menu.instanceName = "menu";
    menu.x = 0; menu.y = 0; menu.w = 100; menu.h = 24;
    menu.hasXywh = true;
    win.addChild(menu);

    auto sub = new SubmenuNode();
    sub.typeName = "Submenu";
    sub.label = "Sub";
    sub.hasLabel = true;
    menu.addChild(sub);

    auto nested = new MenuItemNode();
    nested.typeName = "MenuItem";
    nested.label = "Nested";
    nested.hasLabel = true;
    sub.addChild(nested);

    auto emptySub = new SubmenuNode();
    emptySub.typeName = "Submenu";
    emptySub.label = "Empty";
    emptySub.hasLabel = true;
    menu.addChild(emptySub);

    auto check = new MenuItemNode();
    check.typeName = "CheckMenuItem";
    check.label = "Check";
    check.hasLabel = true;
    menu.addChild(check);

    auto radio = new MenuItemNode();
    radio.typeName = "RadioMenuItem";
    radio.label = "Radio";
    radio.hasLabel = true;
    menu.addChild(radio);

    string text = new Writer().generate([mainFn]);
    assert(text.canFind(`MenuItem("Sub", 0, null, menuSubmenu,`));
    assert(text.canFind(`MenuItem("Nested", 0, null, 0,`));
    assert(text.canFind(`MenuItem("Empty", 0, null, menuSubmenu,`));
    assert(text.canFind(`MenuItem("Check", 0, null, menuToggle,`));
    assert(text.canFind(`MenuItem("Radio", 0, null, menuRadio,`));

    // Structural check: "Nested" is immediately followed by a closing
    // sentinel *before* "Empty" appears, and "Empty" is immediately
    // followed by its own closing sentinel before "Check" -- confirms
    // both submenu levels (including the childless one) are properly
    // closed rather than left open to swallow their siblings.
    auto iNested = text.countUntil(`MenuItem("Nested"`);
    auto iEmpty = text.countUntil(`MenuItem("Empty"`);
    auto iCheck = text.countUntil(`MenuItem("Check"`);
    assert(iNested >= 0 && iEmpty > iNested && iCheck > iEmpty);
    auto between1 = text[iNested .. iEmpty];
    assert(between1.canFind("MenuItem(null),"));
    auto between2 = text[iEmpty .. iCheck];
    assert(between2.canFind("MenuItem(null),"));
}

unittest
{
    // `bind_image`/`scale_image`, compressed
    // byte-buffer path: a real PNG fixture, `bind` selects `bindImage()`
    // over plain `image()`, and a natural-height (`scaleH == 0`) scale
    // falls back to `image().dataH()`, matching FLTK's own
    // `data_h()` fallback.
    import std.algorithm : canFind;

    auto mainFnPng = new FunctionNode();
    mainFnPng.typeName = "Function";
    auto winPng = new WindowNode();
    winPng.typeName = "Fl_Window";
    winPng.instanceName = "win";
    winPng.x = 0; winPng.y = 0; winPng.w = 100; winPng.h = 100;
    winPng.hasXywh = true;
    mainFnPng.addChild(winPng);
    auto boxPng = new WidgetNode();
    boxPng.typeName = "Fl_Box";
    boxPng.instanceName = "box";
    boxPng.x = 0; boxPng.y = 0; boxPng.w = 32; boxPng.h = 32;
    boxPng.hasXywh = true;
    boxPng.imageFilename = "desktop/sudoku-32.png";
    boxPng.hasImage = true;
    boxPng.bindImage = true;
    boxPng.scaleImageW = 16;
    winPng.addChild(boxPng);

    string textPng = new Writer().generate([mainFnPng], "source/test");
    assert(textPng.canFind("box.bindImage(new PngImage("));
    assert(!textPng.canFind("box.image(new PngImage("));
    assert(textPng.canFind("box.image().scale(16, box.image().dataH(), false, true);"));

    // Native-representation path (XPM): same `bind`/`scale` handling
    // applies here too, not just the byte-buffer path above.
    auto mainFnXpm = new FunctionNode();
    mainFnXpm.typeName = "Function";
    auto winXpm = new WindowNode();
    winXpm.typeName = "Fl_Window";
    winXpm.instanceName = "win";
    winXpm.x = 0; winXpm.y = 0; winXpm.w = 100; winXpm.h = 100;
    winXpm.hasXywh = true;
    mainFnXpm.addChild(winXpm);
    auto boxXpm = new WidgetNode();
    boxXpm.typeName = "Fl_Box";
    boxXpm.instanceName = "box";
    boxXpm.x = 0; boxXpm.y = 0; boxXpm.w = 32; boxXpm.h = 32;
    boxXpm.hasXywh = true;
    boxXpm.imageFilename = "pixmaps/magenta.xpm";
    boxXpm.hasImage = true;
    boxXpm.scaleImageW = 16;
    boxXpm.scaleImageH = 16;
    winXpm.addChild(boxXpm);

    string textXpm = new Writer().generate([mainFnXpm], "source/test");
    assert(textXpm.canFind("box.image(new Pixmap("));
    assert(textXpm.canFind("box.image().scale(16, 16, false, true);"));
}

unittest
{
    // `uses_font_menu` (`fluid.font_menu`'s own doc comment): a
    // `Choice` opted into the shared font list has *zero*
    // `MenuItemNode` children (that's the whole point -- nothing to
    // re-declare per instance), so it needs its own way into
    // `writeMenuOwnerNode()` -- the ordinary "does this node have
    // menu-item children" dispatch check would never route here
    // otherwise (a real bug this test would have caught: the first
    // version of this feature left that dispatch unchanged, so this
    // whole code path was silently unreachable).
    import std.algorithm : canFind;

    auto mainFn = new FunctionNode();
    mainFn.typeName = "Function";
    auto win = new WindowNode();
    win.typeName = "Fl_Window";
    win.instanceName = "win";
    win.x = 0; win.y = 0; win.w = 200; win.h = 100;
    win.hasXywh = true;
    mainFn.addChild(win);
    auto choice = new WidgetNode();
    choice.typeName = "Choice";
    choice.instanceName = "styleLabelFont";
    choice.x = 0; choice.y = 0; choice.w = 150; choice.h = 20;
    choice.hasXywh = true;
    choice.usesFontMenu = true;
    win.addChild(choice);

    string text = new Writer().generate([mainFn], ".");
    assert(text.canFind("auto styleLabelFontMenu = fontMenuItems();"));
    assert(text.canFind("styleLabelFont.menu(styleLabelFontMenu);"));
    assert(!text.canFind("MenuItem(\"Helvetica\""));
}

unittest
{
    // `uses_color_menu` (`fluid.color_menu`'s own doc comment) -- same
    // shape as the `uses_font_menu` test just above.
    import std.algorithm : canFind;

    auto mainFn = new FunctionNode();
    mainFn.typeName = "Function";
    auto win = new WindowNode();
    win.typeName = "Fl_Window";
    win.instanceName = "win";
    win.x = 0; win.y = 0; win.w = 200; win.h = 100;
    win.hasXywh = true;
    mainFn.addChild(win);
    auto menuBtn = new WidgetNode();
    menuBtn.typeName = "Menu_Button";
    menuBtn.instanceName = "wLabelcolorMenu";
    menuBtn.x = 0; menuBtn.y = 0; menuBtn.w = 18; menuBtn.h = 20;
    menuBtn.hasXywh = true;
    menuBtn.usesColorMenu = true;
    win.addChild(menuBtn);

    string text = new Writer().generate([mainFn], ".");
    assert(text.canFind("auto wLabelcolorMenuMenu = colorMenuItems();"));
    assert(text.canFind("wLabelcolorMenu.menu(wLabelcolorMenuMenu);"));
    assert(!text.canFind("MenuItem(\"Foreground Color\""));
}

unittest
{
    // An older file's code nodes in their new form: `decl` and `data`
    // become Code nodes, `declblock` and `codeblock` Conditional nodes;
    // a `class` stays a Class, its widgets' imports written at the top.
    import std.algorithm : canFind;
    import fluid.project_reader : Reader;

    auto reader = new Reader("version 1.0000\n"
        ~ "decl {int counter;} {private local}\n"
        ~ "data readme_text {public local filename {README.md} textmode}\n"
        ~ "data logo {filename {pictures/logo.png} compressed}\n"
        ~ "declblock {version (Windows)} {after {}} {\n"
        ~ "  decl {int winOnly;} {}\n"
        ~ "}\n"
        ~ "class Panel {: {Window}} {\n"
        ~ "  decl {int clicks;} {}\n"
        ~ "  Function {build()} {} {\n"
        ~ "    Window {} {xywh {0 0 50 50}} {\n"
        ~ "      Box shown {xywh {0 0 10 10} class Picture}\n"
        ~ "    }\n"
        ~ "  }\n"
        ~ "}\n"
        ~ "Function {} {} {\n"
        ~ "  codeblock {if (counter > 0)} {after {while (false);}} {\n"
        ~ "    code {counter--;} {}\n"
        ~ "  }\n"
        ~ "}\n");
    auto roots = reader.readProject();
    assert(roots.length == 6);
    assert(cast(CodeNode) roots[0] && roots[0].typeName == "code");
    assert(roots[1].instanceName == `immutable string readmeText = import("README.md");`);
    assert(roots[2].instanceName
        == `immutable ubyte[] logo = cast(immutable ubyte[]) import("pictures/logo.png");`);
    assert(cast(ConditionalNode) roots[3] && roots[3].typeName == "conditional");
    assert(cast(CodeNode) roots[3].children[0]);
    assert(cast(ClassNode) roots[4] && roots[4].typeName == "class");
    assert(cast(ConditionalNode) roots[5].children[0]);
    // The end code the Conditional node has no place for.
    assert(reader.notes.length == 1);

    string text = new Writer().generate(roots);
    assert(text.canFind("version (Windows) {"));
    assert(text.canFind("if (counter > 0) {"));
    assert(!text.canFind("while (false)"));
    assert(text.canFind("import Picture : Picture;"));
    assert(text.canFind("class Panel : Window"));
    assert(text.canFind("    int clicks;"));
    assert(text.canFind("    Picture shown;"));
    assert(text.canFind("    void build()"));
}

unittest
{
    // `CommentNode.inSource_` gating a root `comment {}` node's own
    // emission, matching the property panel's own "output to
    // source file" checkbox state.
    import std.algorithm : canFind;

    auto mainFn = new FunctionNode();
    mainFn.typeName = "Function";

    auto shown = new CommentNode();
    shown.typeName = "comment";
    shown.instanceName = "This comment should reach generated D.";
    shown.inSource_ = true;

    string textShown = new Writer().generate([cast(Node) shown, cast(Node) mainFn]);
    assert(textShown.canFind("This comment should reach generated D."));

    auto hidden = new CommentNode();
    hidden.typeName = "comment";
    hidden.instanceName = "This comment should stay .fl-only.";
    hidden.inSource_ = false;

    string textHidden = new Writer().generate([cast(Node) hidden, cast(Node) mainFn]);
    assert(!textHidden.canFind("This comment should stay .fl-only."));
}

unittest
{
    // The dub single-file-package header is the first thing in the
    // file, ahead of the project's comments, and selects fldtk's
    // `program` configuration.
    import std.algorithm : canFind, startsWith;

    auto mainFn = new FunctionNode();
    mainFn.typeName = "Function";
    auto note = new CommentNode();
    note.typeName = "comment";
    note.instanceName = "A file comment.";
    note.inSource_ = true;

    string text = new Writer().generate([cast(Node) note, cast(Node) mainFn], ".",
        I18nSettings.init, true);
    assert(text.startsWith("/+ dub.sdl:\n"));
    assert(text.canFind("\nsubConfiguration \"fldtk\" \"program\"\nstringImportPaths \".\"\n+/\n"));
    assert(text.canFind("A file comment."));

    assert(!new Writer().generate([cast(Node) mainFn]).canFind("dub.sdl"));

    // A code file in another folder names the design's folder from there.
    auto w = new Writer();
    w.outputDir = "source";
    assert(w.generate([cast(Node) mainFn], ".", I18nSettings.init, true)
        .canFind("\nstringImportPaths \"..\"\n+/\n"));
}

unittest
{
    // shortcutExpression(): modifier bits by name, printable keys as
    // character literals, everything else as 8-digit hex.
    assert(shortcutExpression(stateCtrl | 's', false) == "stateCtrl|'s'");
    assert(shortcutExpression(stateMeta | stateShift | stateAlt | 'x', false)
        == "stateMeta|stateShift|stateAlt|'x'");
    assert(shortcutExpression(0xffbe, false) == "0x0000ffbe");
    assert(shortcutExpression(stateCtrl | '\'', false) == "stateCtrl|'\\''");
    assert(shortcutExpression(stateAlt | '\\', false) == "stateAlt|'\\\\'");

    // useFlCommand: the bit equal to stateCommand keeps its meaning under
    // the portable name, and likewise stateControl.
    assert(shortcutExpression(stateCommand | 's', true) == "stateCommand|'s'");
    assert(shortcutExpression(stateControl | stateShift | 'k', true) == "stateControl|stateShift|'k'");
    assert(shortcutExpression(stateCtrl | stateMeta | 'q', true) == "stateCommand|stateControl|'q'");
}

unittest
{
    // Widget and menu-item shortcuts are emitted symbolically and follow
    // ProjectSettings.useFlCommand; a menu item without a shortcut still
    // emits 0 in the shortcut slot.
    import std.algorithm : canFind;
    import fluid.menu_owner_node : MenuOwnerNode;
    import fluid.project_settings : ProjectSettings;

    auto mainFn = new FunctionNode();
    mainFn.typeName = "Function";

    auto win = new WindowNode();
    win.typeName = "Fl_Window";
    win.instanceName = "win";
    win.x = 0; win.y = 0; win.w = 200; win.h = 100;
    win.hasXywh = true;
    mainFn.addChild(win);

    auto btn = new WidgetNode();
    btn.typeName = "Fl_Button";
    btn.instanceName = "btn";
    btn.x = 0; btn.y = 0; btn.w = 32; btn.h = 32;
    btn.hasXywh = true;
    btn.shortcutRaw = "0x40073"; // stateCtrl | 's'
    btn.hasShortcut = true;
    win.addChild(btn);

    auto menu = new MenuOwnerNode();
    menu.typeName = "Fl_Menu_Button";
    menu.instanceName = "menu";
    menu.x = 0; menu.y = 40; menu.w = 100; menu.h = 24;
    menu.hasXywh = true;
    win.addChild(menu);

    auto open = new MenuItemNode();
    open.typeName = "MenuItem";
    open.label = "Open";
    open.hasLabel = true;
    open.shortcutRaw = "0x40073";
    open.hasShortcut = true;
    menu.addChild(open);

    auto plain = new MenuItemNode();
    plain.typeName = "MenuItem";
    plain.label = "Plain";
    plain.hasLabel = true;
    menu.addChild(plain);

    string off = new Writer().generate([mainFn]);
    assert(off.canFind("btn.shortcut(stateCtrl|'s');"));
    assert(off.canFind(`MenuItem("Open", stateCtrl|'s', null,`));
    assert(off.canFind(`MenuItem("Plain", 0, null,`));

    ProjectSettings on;
    on.useFlCommand = true;
    string withCommand = new Writer().generate([mainFn], ".", I18nSettings.init, false, on);
    assert(withCommand.canFind("btn.shortcut(stateCommand|'s');"));
    assert(withCommand.canFind(`MenuItem("Open", stateCommand|'s', null,`));
    assert(withCommand.canFind(`MenuItem("Plain", 0, null,`));

    // A shortcut value that isn't an integer literal passes through as written.
    btn.shortcutRaw = "stateAlt|'z'";
    assert(new Writer().generate([mainFn]).canFind("btn.shortcut(stateAlt|'z');"));
}

unittest
{
    // writeI18nPrologue(): D-module import, optionally version-guarded
    // with pass-through fallbacks; nothing for `none` or an empty include;
    // C-style includes are reported, not emitted.
    import std.algorithm : canFind;
    import fluid.i18n : I18nSettings, I18nType;

    auto mainFn = new FunctionNode();
    mainFn.typeName = "Function";

    string gen(I18nSettings i18n) { return new Writer().generate([mainFn], ".", i18n); }

    assert(!gen(I18nSettings.init).canFind("gettext"));

    I18nSettings gnu;
    gnu.type = I18nType.gnu;
    string plainGnu = gen(gnu);
    assert(plainGnu.canFind("import fl.gettext;\n"));
    assert(!plainGnu.canFind("version ("));

    gnu.gnuConditional = "ENABLE_NLS";
    gnu.gnuFunction = "_";
    gnu.gnuStaticFunction = "N_";
    string guarded = gen(gnu);
    assert(guarded.canFind("version (ENABLE_NLS)\n{\n    import fl.gettext;\n}\nelse\n{\n"));
    assert(guarded.canFind("string _(string text) pure nothrow @nogc @safe { return text; }"));
    assert(guarded.canFind("string N_(string text) pure nothrow @nogc @safe { return text; }"));

    gnu.gnuInclude = "<libintl.h>";
    string cStyle = gen(gnu);
    assert(cStyle.canFind("// Skipped i18n include <libintl.h>: not a D module name."));
    assert(!cStyle.canFind("import <"));

    gnu.gnuInclude = "";
    assert(!gen(gnu).canFind("version ("));

    I18nSettings posix;
    posix.type = I18nType.posix;
    assert(!gen(posix).canFind("catgets(C)"));  // default POSIX include is empty

    posix.posixInclude = "mycatalog";
    posix.posixConditional = "HAVE_CATGETS";
    string posixText = gen(posix);
    assert(posixText.canFind("version (HAVE_CATGETS)\n{\n    import mycatalog;\n}\nelse\n{\n"));
    assert(posixText.canFind("string catgets(C)(C catalog, int set, int msgid, string text)"));
}

unittest
{
    // MergeBack end to end: with the flag on, the generated file carries
    // tag lines whose CRCs the reader recomputes exactly, so an unedited
    // file analyses clean; edits to a widget callback, a menu-item
    // callback and a `code {}` fragment are found and merged back with
    // their relative indentation intact; edits elsewhere are structural.
    import std.algorithm : canFind;
    import std.string : indexOf;
    import fluid.menu_owner_node : MenuOwnerNode;
    import fluid.mergeback : Mergeback;
    import fluid.project_settings : ProjectSettings;

    auto mainFn = new FunctionNode();
    mainFn.typeName = "Function";

    auto win = new WindowNode();
    win.typeName = "Fl_Window";
    win.instanceName = "win";
    win.x = 0; win.y = 0; win.w = 200; win.h = 100;
    win.hasXywh = true;
    mainFn.addChild(win);

    auto btn = new WidgetNode();
    btn.typeName = "Fl_Button";
    btn.instanceName = "btn";
    btn.x = 0; btn.y = 0; btn.w = 32; btn.h = 32;
    btn.hasXywh = true;
    btn.callback = "doThing();\nif (x)\n{\n    y();\n}";
    win.addChild(btn);

    auto menu = new MenuOwnerNode();
    menu.typeName = "Fl_Menu_Button";
    menu.instanceName = "menu";
    menu.x = 0; menu.y = 40; menu.w = 100; menu.h = 24;
    menu.hasXywh = true;
    win.addChild(menu);

    auto item = new MenuItemNode();
    item.typeName = "MenuItem";
    item.label = "Open";
    item.hasLabel = true;
    item.callback = "openIt();";
    menu.addChild(item);

    auto code = new CodeNode();
    code.typeName = "code";
    code.instanceName = "writeln(\"hi\");\n\nwriteln(\"there\");";
    mainFn.addChild(code);

    ProjectSettings on;
    on.writeMergebackData = true;
    string plain = new Writer().generate([mainFn]);
    assert(!plain.canFind("ﬂ"));
    string text = new Writer().generate([mainFn], ".", I18nSettings.init, false, on);
    assert(text.canFind("ﬂ"));
    // Callback text keeps its own indentation and blank lines.
    assert(text.canFind("                if (x)\n                {\n                    y();\n                }\n"));

    auto mb = new Mergeback([mainFn]);
    assert(mb.analyse(text) == 0);
    assert(mb.numChangedCode == 0 && mb.numChangedStructure == 0);
    assert(mb.apply(text) == 0);

    // Edit all three editable blocks in the generated file.
    string edited = text
        .replace("doThing();", "doOther();")
        .replace("openIt();", "openThat();\n                        more();")
        .replace("writeln(\"there\");", "writeln(\"you\");");
    assert(mb.analyse(edited) == 0);
    assert(mb.numChangedCode == 3 && mb.numUidNotFound == 0 && mb.numPossibleOverride == 0);
    assert(mb.numChangedStructure == 0);
    assert(mb.apply(edited) == 1);
    assert(btn.callback == "doOther();\nif (x)\n{\n    y();\n}");
    assert(item.callback == "openThat();\n    more();");
    assert(code.instanceName == "writeln(\"hi\");\n\nwriteln(\"you\");");

    // Regenerating from the merged project gives a file that analyses
    // clean again.
    string regenerated = new Writer().generate([mainFn], ".", I18nSettings.init, false, on);
    assert(mb.analyse(regenerated) == 0 && mb.numChangedCode == 0 && mb.numChangedStructure == 0);

    // An edit outside the editable blocks is structural.
    string structural = regenerated.replace("import fl;", "import fl; // edited");
    assert(mb.analyse(structural) == 0);
    assert(mb.numChangedStructure == 1 && mb.numChangedCode == 0);
    assert(mb.apply(structural) == 0);
}

unittest
{
    // A widget's `setup` code is tagged for MergeBack too. The file shows
    // the widget's own name where the project says `o`, so an edit is
    // merged back with `o` again, for a named and for an unnamed widget.
    import std.algorithm : canFind;
    import fluid.mergeback : Mergeback;
    import fluid.project_settings : ProjectSettings;

    auto mainFn = new FunctionNode();
    mainFn.typeName = "Function";

    auto win = new WindowNode();
    win.typeName = "Fl_Window";
    win.instanceName = "win";
    win.x = 0; win.y = 0; win.w = 200; win.h = 100;
    win.hasXywh = true;
    mainFn.addChild(win);

    auto named = new WidgetNode();
    named.typeName = "Fl_Button";
    named.instanceName = "okButton";
    named.x = 0; named.y = 0; named.w = 32; named.h = 32;
    named.hasXywh = true;
    named.setupCode = "o.tooltip(\"ok\");\no.deactivate();";
    named.hasSetupCode = true;
    win.addChild(named);

    auto anon = new WidgetNode();
    anon.typeName = "Fl_Button";
    anon.x = 40; anon.y = 0; anon.w = 32; anon.h = 32;
    anon.hasXywh = true;
    anon.setupCode = "o.tooltip(\"anon\");";
    anon.hasSetupCode = true;
    win.addChild(anon);

    ProjectSettings on;
    on.writeMergebackData = true;
    string text = new Writer().generate([mainFn], ".", I18nSettings.init, false, on);
    assert(text.canFind("okButton.deactivate();"));

    auto mb = new Mergeback([mainFn]);
    assert(mb.analyse(text) == 0);
    assert(mb.numChangedCode == 0 && mb.numChangedStructure == 0);

    string edited = text
        .replace("okButton.deactivate();", "okButton.activate();")
        .replace("o.tooltip(\"anon\");", "o.tooltip(\"other\");");
    assert(mb.analyse(edited) == 0);
    assert(mb.numChangedCode == 2 && mb.numUidNotFound == 0 && mb.numPossibleOverride == 0);
    assert(mb.apply(edited) == 1);
    assert(named.setupCode == "o.tooltip(\"ok\");\no.activate();");
    assert(anon.setupCode == "o.tooltip(\"other\");");

    // Merged: the file analyses as already applied, and regenerating gives
    // a file that analyses clean.
    assert(mb.analyse(edited) == 0 && mb.numChangedCode == 0);
    string regenerated = new Writer().generate([mainFn], ".", I18nSettings.init, false, on);
    assert(mb.analyse(regenerated) == 0 && mb.numChangedCode == 0 && mb.numChangedStructure == 0);

    // A setup edited in the project after generation is a possible override.
    named.setupCode = "o.tooltip(\"project\");";
    string editedAgain = regenerated.replace("okButton.activate();", "okButton.hide();");
    assert(mb.analyse(editedAgain) == 0);
    assert(mb.numChangedCode == 1 && mb.numPossibleOverride == 1);
}

unittest
{
    // A widget's `finalize` code: written after its children and before a
    // group's or window's `end()`, tagged for MergeBack (groups and
    // windows included), and round-tripped through the .fl text.
    import std.algorithm : canFind;
    import std.string : indexOf;
    import fluid.mergeback : Mergeback;
    import fluid.project_reader : Reader;
    import fluid.project_writer : ProjectWriter;

    auto mainFn = new FunctionNode();
    mainFn.typeName = "Function";

    auto win = new WindowNode();
    win.typeName = "Fl_Window";
    win.instanceName = "win";
    win.x = 0; win.y = 0; win.w = 200; win.h = 100;
    win.hasXywh = true;
    win.finalizeCode = "o.label(\"done\");";
    win.hasFinalizeCode = true;
    mainFn.addChild(win);

    auto grp = new GroupNode();
    grp.typeName = "Fl_Group";
    grp.instanceName = "grp";
    grp.x = 0; grp.y = 0; grp.w = 100; grp.h = 50;
    grp.hasXywh = true;
    grp.setupCode = "o.tooltip(\"before\");";
    grp.hasSetupCode = true;
    grp.finalizeCode = "o.tooltip(\"after\");";
    grp.hasFinalizeCode = true;
    win.addChild(grp);

    auto btn = new WidgetNode();
    btn.typeName = "Fl_Button";
    btn.instanceName = "btn";
    btn.x = 0; btn.y = 0; btn.w = 32; btn.h = 32;
    btn.hasXywh = true;
    btn.finalizeCode = "o.deactivate();";
    btn.hasFinalizeCode = true;
    grp.addChild(btn);

    ProjectSettings on;
    on.writeMergebackData = true;
    string text = new Writer().generate([mainFn], ".", I18nSettings.init, false, on);
    auto setupAt = text.indexOf(`grp.tooltip("before");`);
    auto btnAt = text.indexOf("btn = new");
    auto grpFinalAt = text.indexOf(`grp.tooltip("after");`);
    auto grpEndAt = text.indexOf("grp.end();");
    auto winFinalAt = text.indexOf(`win.label("done");`);
    auto winEndAt = text.indexOf("win.end();");
    assert(setupAt >= 0 && setupAt < btnAt && btnAt < grpFinalAt && grpFinalAt < grpEndAt);
    assert(grpEndAt < winFinalAt && winFinalAt < winEndAt);
    assert(text.canFind("btn.deactivate();"));

    // Every `finalize` block merges back with `o` restored.
    auto mb = new Mergeback([mainFn]);
    assert(mb.analyse(text) == 0 && mb.numChangedCode == 0 && mb.numChangedStructure == 0);
    string edited = text
        .replace(`grp.tooltip("after");`, `grp.tooltip("later");`)
        .replace(`win.label("done");`, `win.label("ready");`)
        .replace("btn.deactivate();", "btn.hide();");
    assert(mb.analyse(edited) == 0);
    assert(mb.numChangedCode == 3 && mb.numUidNotFound == 0 && mb.numPossibleOverride == 0);
    assert(mb.apply(edited) == 1);
    assert(grp.finalizeCode == `o.tooltip("later");`);
    assert(win.finalizeCode == `o.label("ready");`);
    assert(btn.finalizeCode == "o.hide();");
    assert(grp.setupCode == `o.tooltip("before");`);

    // `finalize {}` survives a write and read of the .fl text.
    string fl = new ProjectWriter().generate([mainFn], I18nSettings.init, [], "", null, false, false, on);
    assert(fl.canFind("finalize {o.hide();}"));
    auto again = new Reader(fl).readProject();
    auto grp2 = cast(WidgetNode) again[0].children[0].children[0];
    assert(grp2.hasFinalizeCode && grp2.finalizeCode == `o.tooltip("later");`);
    assert(grp2.hasSetupCode && grp2.setupCode == `o.tooltip("before");`);
}

unittest
{
    // `mergeback 1` and every node's uid round-trip through the .fl text,
    // and a project with duplicate uids is repaired on write.
    import std.algorithm : canFind;
    import fluid.project_reader : Reader;
    import fluid.project_settings : ProjectSettings;
    import fluid.project_writer : ProjectWriter;

    auto roots = new Reader("version 1.0000\nFunction {} {open\n} {\n  code {foo();} {}\n}\n").readProject();
    auto fn = roots[0];
    fn.children[0].uid = fn.uid; // deliberate duplicate

    ProjectSettings on;
    on.writeMergebackData = true;
    string text = new ProjectWriter().generate(roots, I18nSettings.init, [], "", null, false, false, on);
    assert(text.canFind("\nmergeback 1\n"));
    assert(fn.uid != fn.children[0].uid);

    auto reader = new Reader(text);
    auto reread = reader.readProject();
    assert(reader.settings.writeMergebackData);
    assert(reread[0].uid == fn.uid && reread[0].children[0].uid == fn.children[0].uid);

    // Off: no flag, no uids.
    string off = new ProjectWriter().generate(reread);
    assert(!off.canFind("mergeback") && !off.canFind(" uid "));
}

unittest
{
    // A widget's private/protected flag: parsed from `.fl` text, written
    // back, and emitted as a protection attribute on a class field or
    // `private` on a module-level variable; a public widget writes nothing.
    import std.algorithm : canFind;
    import fluid.project_reader : Reader;
    import fluid.project_writer : ProjectWriter;

    string src = "version 1.0000\n"
        ~ "class App {open\n} {\n  Function {make()} {open\n  } {\n"
        ~ "  Fl_Window {} {open\n  xywh {0 0 100 50}\n} {\n"
        ~ "  Fl_Button hidden {\n    private\n    tooltip {tip}\n    xywh {5 5 40 20}\n  }\n"
        ~ "  Fl_Box guarded {\n    protected\n    xywh {50 5 40 20}\n  }\n"
        ~ "  Fl_Box open_ {\n    xywh {50 30 40 20}\n  }\n"
        ~ "}\n}\n}\n"
        ~ "Function {} {open\n} {\n  Fl_Window mw {open\n    xywh {0 0 100 50}\n  } {\n"
        ~ "    Fl_Box mine {\n      private\n      xywh {5 5 40 20}\n    }\n"
        ~ "    Fl_Box shared_ {\n      xywh {5 30 40 20}\n    }\n  }\n}\n";
    auto roots = new Reader(src).readProject();

    string d = new Writer().generate(roots);
    assert(d.canFind("private Button hidden;"));
    assert(d.canFind("protected Box guarded;"));
    assert(d.canFind("    Box open_;"));
    assert(d.canFind("private Box mine;"));
    assert(d.canFind("\nBox shared_;"));
    assert(!d.canFind("private Box shared_"));

    // The tooltip after the flag was not swallowed, and the flags survive a save.
    string text = new ProjectWriter().generate(roots);
    assert(text.canFind("private\n") && text.canFind("protected\n") && text.canFind("tooltip {tip}"));
    auto again = new Writer().generate(new Reader(text).readProject());
    assert(again == d);
}

unittest
{
    // `type` keywords resolve per widget kind: VERTICAL is a Scroll's
    // scrollVertical (2), not a Flex's flexVertical (0), and Multiline is an
    // Input's inputMultiline, not an Output's outputMultiline. Kinds without
    // a table fall back to the flat keyword map.
    import std.algorithm : canFind;
    import fluid.project_reader : Reader;

    string src = "version 1.0000\nFunction {} {open\n} {\n  Fl_Window w {open\n    xywh {0 0 200 200}\n  } {\n"
        ~ "    Fl_Scroll sc {\n      type VERTICAL\n      xywh {0 0 50 50}\n    } {}\n"
        ~ "    Fl_Pack pk {\n      type HORIZONTAL\n      xywh {50 0 50 50}\n    } {}\n"
        ~ "    Fl_Input in_ {\n      type Multiline\n      xywh {0 50 50 20}\n    }\n"
        ~ "    Fl_Output out_ {\n      type Multiline\n      xywh {0 70 50 20}\n    }\n"
        ~ "    Fl_Slider sl {\n      type {Vert Fill}\n      xywh {0 90 50 20}\n    }\n"
        ~ "    Fl_Browser br {\n      type Select\n      xywh {0 110 50 20}\n    }\n"
        ~ "    Fl_Button tg {\n      type Toggle\n      xywh {0 130 50 20}\n    }\n"
        ~ "  }\n}\n";
    string d = new Writer().generate(new Reader(src).readProject());
    assert(d.canFind("sc.type(scrollVertical);"));
    assert(d.canFind("pk.type(packHorizontal);"));
    assert(d.canFind("in_.type(inputMultiline);"));
    assert(d.canFind("out_.type(outputMultiline);"));
    assert(d.canFind("sl.type(vertFillSlider);"));
    assert(d.canFind("br.type(selectBrowser);"));
    assert(d.canFind("tg.type(toggleButton);"));
}

unittest
{
    // A Function's `private`/`protected`/`C` flags (bare flags, FLTK's
    // `Function_Node::public_`/`declare_c_`) parse without swallowing the
    // property after them, round-trip, and become D attributes: a plain
    // function's private is module-private and `C` is extern (C); a class
    // method's private/protected are protection attributes and `C` is ignored.
    import std.algorithm : canFind;
    import fluid.project_reader : Reader;
    import fluid.project_writer : ProjectWriter;

    string src = "version 1.0000\n"
        ~ "Function {hidden(int x)} {\n  private\n  return_type int\n} {\n  code {return x;} {}\n}\n"
        ~ "Function {api(int x)} {\n  C\n  return_type int\n} {\n  code {return x;} {}\n}\n"
        ~ "Function {local_(int x)} {\n  protected\n  return_type int\n} {\n  code {return x;} {}\n}\n"
        ~ "Function {open_(int x)} {\n  return_type int\n} {\n  code {return x;} {}\n}\n"
        ~ "class Foo {open : Fl_Group\n} {\n"
        ~ "  Function {secret()} {\n    private\n    return_type void\n  } {\n    code {} {}\n  }\n"
        ~ "  Function {guarded()} {\n    protected\n    C\n    return_type void\n  } {\n    code {} {}\n  }\n"
        ~ "  Function {visible()} {\n    return_type void\n  } {\n    code {} {}\n  }\n}\n";
    auto roots = new Reader(src).readProject();
    assert(roots.length == 5);

    string d = new Writer().generate(roots);
    assert(d.canFind("private int hidden(int x)"));
    assert(d.canFind("extern (C) int api(int x)"));
    assert(d.canFind("\nint local_(int x)"));
    assert(d.canFind("\nint open_(int x)"));
    assert(d.canFind("    private void secret()"));
    assert(d.canFind("    protected void guarded()"));
    assert(d.canFind("    void visible()"));
    assert(!d.canFind("extern (C) void guarded"));

    string text = new ProjectWriter().generate(roots);
    auto again = new Reader(text).readProject();
    assert(new Writer().generate(again) == d);
}

unittest
{
    // `user_data {expr}` is emitted as `w.userData = expr;`, before the
    // widget's callback is assigned; a widget without it emits nothing.
    import std.algorithm : canFind;
    import fluid.project_reader : Reader;
    import fluid.project_writer : ProjectWriter;

    string src = "version 1.0000\nFunction {} {open\n} {\n  Fl_Window w {open\n    xywh {0 0 100 50}\n  } {\n"
        ~ "    Fl_Button tagged {\n      user_data {new Tag(3)}\n      user_data_type long\n"
        ~ "      callback {doIt();}\n      xywh {5 5 40 20}\n    }\n"
        ~ "    Fl_Button plain {\n      xywh {50 5 40 20}\n    }\n  }\n}\n";
    auto roots = new Reader(src).readProject();
    string d = new Writer().generate(roots);
    auto at = d.indexOf("tagged.userData = new Tag(3);");
    assert(at >= 0);
    assert(d.indexOf("tagged.callback(") > at);
    assert(!d.canFind("plain.userData"));

    // The expression survives a save.
    auto again = new Writer().generate(new Reader(new ProjectWriter().generate(roots)).readProject());
    assert(again == d);
}

unittest
{
    // The three subtypes that select a class or node kind rather than a
    // `type()` value: a window's Double (also spelled by the `Fl_Double_Window`
    // node type), a menu bar's Fl_Sys_Menu_Bar, and a menu item's kind. None of
    // them may emit a `type()` call.
    import std.algorithm : canFind;
    import fluid.project_reader : Reader;

    string src = "version 1.0000\nFunction {} {open\n} {\n"
        ~ "  Fl_Window plain {open\n    xywh {0 0 100 100}\n  } {}\n"
        ~ "  Fl_Window twice {open\n    xywh {0 0 100 100} type Double\n  } {\n"
        ~ "    Fl_Menu_Bar sys {\n      type Fl_Sys_Menu_Bar\n      xywh {0 0 100 20}\n    } {}\n"
        ~ "    Fl_Menu_Bar bar {\n      xywh {0 20 100 20}\n    } {}\n"
        ~ "  }\n"
        ~ "  Fl_Double_Window named {open\n    xywh {0 0 100 100}\n  } {}\n}\n";
    string d = new Writer().generate(new Reader(src).readProject());
    assert(d.canFind("Window plain;"));
    assert(d.canFind("DoubleWindow twice;"));
    assert(d.canFind("DoubleWindow named;"));
    assert(d.canFind("SysMenuBar sys;"));
    assert(d.canFind("MenuBar bar;"));
    assert(!d.canFind("sys.type(") && !d.canFind("twice.type("));
}

unittest
{
    // A named Function is a plain D function, and a callback field
    // holding only a name (an older `.fl` file) is read as a call to it.
    import std.algorithm : canFind;
    import fluid.project_reader : Reader;

    string src = "version 1.0000\n"
        ~ "Function {quitCb(Widget w)} {open return_type void\n} {\n"
        ~ "  code {quitBody();} {}\n}\n"
        ~ "Function {} {open\n} {\n"
        ~ "  Fl_Window win {open\n    xywh {0 0 100 100}\n  } {\n"
        ~ "    Fl_Button {} {\n      callback quitCb\n      xywh {0 0 50 20}\n    }\n"
        ~ "    Fl_Button {} {\n      callback {quitCb}\n      xywh {0 20 50 20}\n    }\n  }\n}\n";
    auto roots = new Reader(src).readProject();
    assert(roots[1].children[0].children[0].callback == "quitCb(o);");
    assert(roots[1].children[0].children[1].callback == "quitCb(o);");
    string d = new Writer().generate(roots);
    assert(d.canFind("void quitCb(Widget w)"));
    assert(!d.canFind("delegate(Widget) quitCb"));
    assert(!d.canFind("static this()"));
}

unittest
{
    // Every kind of node, in every container Fluid lets it be placed in
    // (`acceptsNewNode()` in `gui_main.d`), must reach the generated
    // code: a combination the writer has no branch for would otherwise
    // be dropped without a word. When `acceptsNewNode()` allows a new
    // combination, add it to `allowed` below.
    import std.algorithm : canFind, startsWith;
    import fluid.group_node : GroupNode;

    static T mk(T)(string typeName, string name)
    {
        auto n = new T();
        n.typeName = typeName;
        n.instanceName = name;
        return n;
    }
    static WidgetNode box(string name)
    {
        auto b = mk!WidgetNode("Box", name);
        b.w = 10; b.h = 10; b.hasXywh = true;
        return b;
    }
    static WindowNode win(string name)
    {
        auto w = mk!WindowNode("Window", name);
        w.w = 50; w.h = 50; w.hasXywh = true;
        return w;
    }

    // The node of `kind` to place, carrying `marker` somewhere in what
    // it generates; and the text that proves it was written.
    static Node child(string kind, string marker)
    {
        switch (kind)
        {
        case "code": return mk!CodeNode("code", "int " ~ marker ~ ";");
        case "conditional":
            auto cond = mk!ConditionalNode("conditional", "version (all)");
            cond.addChild(mk!CodeNode("code", "int " ~ marker ~ ";"));
            return cond;
        case "comment": return mk!CommentNode("comment", marker);
        case "Function": return mk!FunctionNode("Function", marker ~ "()");
        case "class": return mk!ClassNode("class", marker);
        case "Window": return win(marker);
        case "widget": return box(marker);
        default: assert(0, kind);
        }
    }
    static string proof(string kind, string marker)
    {
        switch (kind)
        {
        case "Window": case "widget": return marker ~ " = new ";
        case "class": return "class " ~ marker;
        case "Function": return marker ~ "()\n";
        default: return marker;
        }
    }

    // Each container, built around the node under test.
    alias Container = Node[] delegate(Node);
    Container[string] containers = [
        "main()": (Node c) {
            auto f = mk!FunctionNode("Function", "");
            f.addChild(c);
            return [cast(Node) f];
        },
        "function": (Node c) {
            auto f = mk!FunctionNode("Function", "helper()");
            f.addChild(c);
            return [cast(Node) f];
        },
        "callback function": (Node c) {
            auto f = mk!FunctionNode("Function", "cbf(Widget b)");
            f.addChild(c);
            auto m = mk!FunctionNode("Function", "");
            auto w = win("");
            auto b = box("button");
            b.callback = "cbf(o);";
            w.addChild(b);
            m.addChild(w);
            return [cast(Node) f, m];
        },
        "conditional in a function": (Node c) {
            auto f = mk!FunctionNode("Function", "");
            auto cond = mk!ConditionalNode("conditional", "if (true)");
            cond.addChild(c);
            f.addChild(cond);
            return [cast(Node) f];
        },
        "method": (Node c) {
            auto k = mk!ClassNode("class", "Outer");
            auto f = mk!FunctionNode("Function", "method()");
            f.addChild(c);
            k.addChild(f);
            return [cast(Node) k];
        },
        "window": (Node c) {
            auto f = mk!FunctionNode("Function", "");
            auto w = win("");
            w.addChild(c);
            f.addChild(w);
            return [cast(Node) f];
        },
        "group": (Node c) {
            auto f = mk!FunctionNode("Function", "");
            auto w = win("");
            auto g = mk!GroupNode("Group", "");
            g.w = 20; g.h = 20; g.hasXywh = true;
            g.addChild(c);
            w.addChild(g);
            f.addChild(w);
            return [cast(Node) f];
        },
        "conditional at the top": (Node c) {
            auto cond = mk!ConditionalNode("conditional", "version (all)");
            cond.addChild(c);
            return [cast(Node) cond];
        },
        "class": (Node c) {
            auto k = mk!ClassNode("class", "OuterClass");
            k.addChild(c);
            return [cast(Node) k];
        },
        "conditional in a class": (Node c) {
            auto k = mk!ClassNode("class", "OuterClass");
            auto cond = mk!ConditionalNode("conditional", "version (all)");
            cond.addChild(c);
            k.addChild(cond);
            return [cast(Node) k];
        },
        "top level": (Node c) => [c],
    ];

    enum statements = ["code", "conditional", "comment", "Window"];
    enum declarations = ["Function", "code", "conditional", "comment", "class"];
    string[][string] allowed = [
        "main()": statements,
        "function": statements,
        "callback function": statements,
        "conditional in a function": statements,
        "method": statements,
        "window": ["code", "conditional", "comment", "widget", "Window"],
        "group": ["code", "conditional", "comment", "widget"],
        "conditional at the top": declarations,
        "class": declarations,
        "conditional in a class": declarations,
        "top level": declarations,
    ];

    string[] missing;
    int i;
    foreach (where, kinds; allowed)
        foreach (kind; kinds)
        {
            import std.conv : to;
            string marker = "marker" ~ to!string(i++);
            string text = new Writer().generate(containers[where](child(kind, marker)));
            if (!text.canFind(proof(kind, marker)))
                missing ~= kind ~ " in " ~ where;
        }
    assert(missing.length == 0, "not in the generated code: " ~ missing.join(", "));
}

unittest
{
    // Every node written records where its code is, so the Code View can
    // highlight it: a function's span holds its header, a code block's
    // its opening line, a code node's its text.
    import std.algorithm.searching : canFind;
    import fluid.project_reader : Reader;

    auto roots = new Reader("version 1.0000\n"
        ~ "decl {int counter;} {}\n"
        ~ "Function {calculate()} {} {\n"
        ~ "  codeblock {if (counter > 0)} {} {\n"
        ~ "    code {counter--;} {}\n"
        ~ "  }\n"
        ~ "}\n"
        ~ "Function {} {} {\n"
        ~ "  code {calculate();} {}\n"
        ~ "}\n").readProject();
    string text = new Writer().generate(roots);

    string spanText(TextSpan s)
    {
        assert(s.start >= 0 && s.end >= s.start);
        return text[s.start .. s.end];
    }

    auto decl = roots[0];
    auto calc = roots[1];
    auto block = calc.children[0];
    auto code = block.children[0];
    auto mainFn = roots[2];
    assert(spanText(decl.setupSpan).canFind("int counter;"));
    assert(spanText(calc.setupSpan).canFind("calculate()"));
    assert(spanText(calc.finalizeSpan).canFind("}"));
    assert(text[calc.setupSpan.start .. calc.finalizeSpan.end].canFind("counter--;"));
    assert(spanText(block.setupSpan).canFind("if (counter > 0) {"));
    assert(spanText(code.setupSpan).canFind("counter--;"));
    assert(spanText(mainFn.setupSpan).canFind("void main("));
    assert(spanText(mainFn.finalizeSpan).canFind("fl.run();"));
}

unittest
{
    // Every piece of code the user writes in the properties panel has a
    // span holding exactly its text, with MergeBack on and off; a
    // second generate() forgets a piece the node no longer has.
    import std.algorithm : canFind;
    import std.string : strip;
    import fluid.mergeback : Tag;

    static T mk(T)(string typeName, string name)
    {
        auto n = new T();
        n.typeName = typeName;
        n.instanceName = name;
        return n;
    }

    foreach (mergeback; [false, true])
    {
        auto fn = mk!FunctionNode("Function", "");
        auto code = mk!CodeNode("code", "int counter = 1;");
        auto win = mk!WindowNode("Window", "win");
        win.w = 100; win.h = 100; win.hasXywh = true;
        win.finalizeCode = "o.label = \"done\";";
        win.hasFinalizeCode = true;
        auto btn = mk!WidgetNode("Button", "btn");
        btn.w = 50; btn.h = 20; btn.hasXywh = true;
        btn.callback = "counter++;";
        btn.setupCode = "o.tooltip = \"tip\";";
        btn.hasSetupCode = true;
        fn.addChild(code);
        fn.addChild(win);
        win.addChild(btn);

        ProjectSettings settings;
        settings.writeMergebackData = mergeback;
        auto writer = new Writer();
        string text = writer.generate([cast(Node) fn], ".", I18nSettings.init, false, settings);

        string block(Node n, Tag kind)
        {
            auto sp = kind in n.blockSpans;
            assert(sp !is null, "no span");
            return text[sp.start .. sp.end].strip;
        }
        assert(block(code, Tag.code) == "int counter = 1;");
        assert(block(btn, Tag.widgetCallback) == "counter++;");
        // Setup and finalize code name the widget instead of `o`.
        assert(block(btn, Tag.setup) == "btn.tooltip = \"tip\";");
        assert(block(win, Tag.finalize) == "win.label = \"done\";");
        assert(Tag.widgetCallback !in win.blockSpans);
        // The block lies inside its node's own code.
        auto sp = btn.blockSpans[Tag.widgetCallback];
        assert(sp.start >= btn.setupSpan.start && sp.end <= btn.setupSpan.end);

        btn.callback = null;
        text = writer.generate([cast(Node) fn], ".", I18nSettings.init, false, settings);
        assert(Tag.widgetCallback !in btn.blockSpans);
        assert(block(btn, Tag.setup) == "btn.tooltip = \"tip\";");
    }
}
