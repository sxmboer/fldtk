/*
 * Runtime twin of `factory.d` (`.fl` type-keyword -> `Node` subclass
 * constructor) and `code_writer.d`'s `className()`/property-emission (`.fl`
 * type-keyword -> D *source text* that builds the widget) -- this
 * module builds a REAL, live `fl.widget.Widget` tree from an already-
 * parsed `Node` tree instead, for the interactive editor's design
 * canvas (`fluid.canvas`) to render and let the user click on.
 *
 * Covers the same ~40 widget
 * types `factory.d` registers, and the property subset
 * `applyProperties()` applies -- growing alongside
 * `panels/widget_panel.fl`'s own matching edit fields (xywh/label/box/color/
 * selection color/hide/deactivate/tooltip, labelfont/labelsize,
 * down_box/labeltype/align/when, resizableFlag, labelcolor/text font-size-color/label
 * margins/compact -- see `applyProperties()`'s own comments for the
 * full field list; declarative `MenuItem {}` children (a `Choice`/
 * `Menu_Button`/`Menu_Bar`/`Input_Choice` populated the real, literal-
 * child-node way) are real via `applyMenuItems()`,
 * its own separate small entry point since a menu-owning widget isn't
 * a `Group` and so never goes through the generic child-instantiation
 * path at all; `value`/`minimum`/`maximum`/`step`/
 * `shortcutRaw` are all real (`Valuator`/`Spinner`/`Button`/
 * `Input_`/`ValueInput`/`TextDisplay`, see `applyProperties()`'s own
 * comments on those two blocks). `shortcutRaw` needs no
 * D-expression interpreter at all: FLTK's own `Widget_Node::read_property()`/
 * `write_properties()` store `shortcut` as a **plain integer**
 * (`strtol(..., 0)` / `"shortcut 0x%x"`), never an arbitrary C++
 * expression, and this port's own `shortcutRaw` matches that
 * (`widget_node.d`'s own doc comment always called it "a raw int/hex
 * literal") -- the same best-effort literal parse `value`/`minimum`/
 * etc. use is all it needs.
 *
 * Callbacks/setup code are different: unlike `shortcutRaw`, both really are
 * arbitrary D source text with no simpler literal form hiding
 * underneath, and applying them live genuinely would require
 * evaluating arbitrary D at runtime. FLTK doesn't do this
 * either -- `Widget_Node`'s own
 * `callback`/`extra_code` handling only ever appears in `write_code1()`/
 * `write_code2()` (C++ *codegen*, emitted to the `.h`/`.cxx` output
 * files), never applied to the live `Fl_Widget* o` shown in FLTK's
 * own design canvas -- unsurprising, since doing so would need an
 * embedded C++ interpreter/compiler, which FLTK's Fluid has never had.
 * So this is faithful to FLTK's own real limitation, not
 * a gap that could be filled the same mechanical way `value`/
 * `shortcutRaw` were -- there's no live-execution mechanism to grow into
 * here, FLTK's own editor doesn't have one either. This is also
 * why a `MenuItemNode`'s own `callback` text specifically stays
 * unapplied even though its *appearance* is live: same reason, not a
 * separate one.
 */
module fluid.instantiate;

import fluid.subtypes : subtypeFor;
import fl;
import std.path : buildPath;
import std.format : format;
import std.conv : to;

import fluid.node : Node;
import fluid.widget_node : WidgetNode;
import fluid.window_node : WindowNode;
import fluid.group_node : GroupNode;
import fluid.grid_node : GridNode;
import fluid.flex_node : FlexNode;
import fluid.code_block_node : CodeBlockNode;
import fluid.menu_item_node : MenuItemNode, SubmenuNode;
import fluid.font_menu : fontMenuItems;
import fluid.color_menu : colorMenuItems;

/// The result of `instantiate()`: the live widget tree plus both
/// directions of the Node<->Widget association, needed by the canvas
/// (hit-testing a click back to a `Node`) and the property panel
/// (finding the live `Widget` a selected `Node` should edit). Kept as
/// a separate returned struct, not a field on `Node`/`Widget`
/// themselves, so `fluid.node`/`fluid.widget_node` stay free of any
/// `import fl` at all -- preserves the existing parse-layer/toolkit-
/// layer separation `project_reader.d`/`code_writer.d` already have.
struct LiveTree
{
    Widget[Node] widgetOf;
    Node[Widget] nodeOf;
}

private alias WidgetCtor = Widget delegate(int x, int y, int w, int h, string label);

private WidgetCtor[string] registry;

private void reg(string bareName, WidgetCtor ctor)
{
    registry["Fl_" ~ bareName] = ctor;
    registry[bareName] = ctor;
}

static this()
{
    reg("Group", (x, y, w, h, l) => new FlGroup(x, y, w, h, l));
    reg("Tabs", (x, y, w, h, l) => new Tabs(x, y, w, h, l));
    reg("Wizard", (x, y, w, h, l) => new Wizard(x, y, w, h, l));
    reg("Grid", (x, y, w, h, l) => new Grid(x, y, w, h, l));
    // Fl_Flex has no (x,y,w,h,label) constructor overload (see
    // source/fl/flex.d) -- label applied separately, matching how every
    // other Widget subtype without a label-taking ctor would need to.
    reg("Flex", (x, y, w, h, l) {
        auto f = new Flex(x, y, w, h);
        if (l !is null) f.label(l);
        return f;
    });
    reg("Pack", (x, y, w, h, l) => new Pack(x, y, w, h, l));
    reg("Scroll", (x, y, w, h, l) => new Scroll(x, y, w, h, l));
    reg("Tile", (x, y, w, h, l) => new Tile(x, y, w, h, l));

    reg("Slider", (x, y, w, h, l) => new Slider(x, y, w, h, l));
    reg("Box", (x, y, w, h, l) => new Box(x, y, w, h, l));
    reg("Button", (x, y, w, h, l) => new Button(x, y, w, h, l));
    reg("Return_Button", (x, y, w, h, l) => new ReturnButton(x, y, w, h, l));
    registry["ReturnButton"] = (x, y, w, h, l) => new ReturnButton(x, y, w, h, l);
    reg("Light_Button", (x, y, w, h, l) => new LightButton(x, y, w, h, l));
    registry["LightButton"] = (x, y, w, h, l) => new LightButton(x, y, w, h, l);
    reg("Check_Button", (x, y, w, h, l) => new CheckButton(x, y, w, h, l));
    registry["CheckButton"] = (x, y, w, h, l) => new CheckButton(x, y, w, h, l);
    reg("Round_Button", (x, y, w, h, l) => new RoundButton(x, y, w, h, l));
    registry["RoundButton"] = (x, y, w, h, l) => new RoundButton(x, y, w, h, l);
    reg("Shortcut_Button", (x, y, w, h, l) => new ShortcutButton(x, y, w, h, l));
    registry["ShortcutButton"] = (x, y, w, h, l) => new ShortcutButton(x, y, w, h, l);
    reg("Repeat_Button", (x, y, w, h, l) => new RepeatButton(x, y, w, h, l));
    registry["RepeatButton"] = (x, y, w, h, l) => new RepeatButton(x, y, w, h, l);
    // Placeholder content on a freshly-built live widget -- ported from
    // FLTK's own `..._Node::widget()` overrides (`nodes/factory.h`/
    // `.cxx`): in real FLTK,
    // all the widgets default to some sort of mock entry. None of
    // this is a round-tripped `.fl` property for these widget kinds --
    // `Widget_Node::read_property()`'s own `"value"` case only applies
    // to `Valuator_Node`/`Spinner_Node` (numeric sliders/counters/etc,
    // stored as raw D-expression text this port's own live canvas
    // doesn't evaluate either -- see `applyProperties()`'s own top
    // comment, "Still not applied: value/...") -- so seeding it here
    // unconditionally can never clobber a real saved value, and applies
    // equally whether the widget is freshly dropped from the palette,
    // rebuilt by Live Resize, or reconstructed on project load/undo.
    reg("Output", (x, y, w, h, l) {
        auto o = new Output(x, y, w, h, l);
        o.value("Text Output");
        return o;
    });
    reg("Input", (x, y, w, h, l) {
        auto o = new Input(x, y, w, h, l);
        o.value("Text Input");
        return o;
    });
    reg("Float_Input", (x, y, w, h, l) => new FloatInput(x, y, w, h, l));
    registry["FloatInput"] = (x, y, w, h, l) => new FloatInput(x, y, w, h, l);
    reg("Int_Input", (x, y, w, h, l) => new IntInput(x, y, w, h, l));
    registry["IntInput"] = (x, y, w, h, l) => new IntInput(x, y, w, h, l);
    reg("Value_Output", (x, y, w, h, l) => new ValueOutput(x, y, w, h, l));
    registry["ValueOutput"] = (x, y, w, h, l) => new ValueOutput(x, y, w, h, l);
    reg("Value_Slider", (x, y, w, h, l) => new ValueSlider(x, y, w, h, l));
    registry["ValueSlider"] = (x, y, w, h, l) => new ValueSlider(x, y, w, h, l);
    reg("Value_Input", (x, y, w, h, l) => new ValueInput(x, y, w, h, l));
    registry["ValueInput"] = (x, y, w, h, l) => new ValueInput(x, y, w, h, l);
    reg("Scrollbar", (x, y, w, h, l) => new Scrollbar(x, y, w, h, l));
    reg("Roller", (x, y, w, h, l) => new Roller(x, y, w, h, l));
    reg("Dial", (x, y, w, h, l) => new Dial(x, y, w, h, l));
    reg("Clock", (x, y, w, h, l) => new FlClock(x, y, w, h, l));
    reg("Clock_Output", (x, y, w, h, l) => new ClockOutput(x, y, w, h, l));
    registry["ClockOutput"] = (x, y, w, h, l) => new ClockOutput(x, y, w, h, l);
    reg("Adjuster", (x, y, w, h, l) => new Adjuster(x, y, w, h, l));
    reg("Counter", (x, y, w, h, l) => new Counter(x, y, w, h, l));
    reg("Spinner", (x, y, w, h, l) => new Spinner(x, y, w, h, l));
    // Terminal: still a bare `new Terminal(...)`, no mock content --
    // FLTK's own `Terminal_Node::widget()` builds a private,
    // editor-only `Fl_Terminal_Proxy` specifically to show sample text
    // via `print_sample_text()`, the same per-node-kind live-editing
    // proxy pattern this port deliberately doesn't replicate elsewhere
    // (`canvas.d`'s own "concrete, not polymorphic" stance) -- a real,
    // disclosed gap, not attempted here.
    reg("Terminal", (x, y, w, h, l) => new Terminal(x, y, w, h, l));
    reg("Browser", (x, y, w, h, l) {
        auto o = new Browser(x, y, w, h, l);
        foreach (i; 1 .. 21)
            o.add(format("Browser Line %d", i));
        return o;
    });
    reg("TextDisplay", (x, y, w, h, l) {
        auto o = new TextDisplay(x, y, w, h, l);
        auto b = new TextBuffer();
        b.text("Lorem ipsum dolor\nsit amet, consetetur\nsadipscing elitr");
        o.buffer(b);
        return o;
    });
    reg("Text_Editor", (x, y, w, h, l) {
        auto o = new TextEditor(x, y, w, h, l);
        auto b = new TextBuffer();
        b.text("Lorem ipsum dolor\nsit amet, consetetur\nsadipscing elitr");
        o.buffer(b);
        return o;
    });
    registry["TextEditor"] = registry["Fl_Text_Editor"];
    // FLTK's own factory.cxx unconditionally constructs a File_Input
    // with a placeholder "file:" label so a freshly-dropped one isn't
    // blank; matched here only when the node itself has no real label
    // yet (the common "just dropped from the palette" case -- an
    // explicit `.fl` label always wins, same as every other type here).
    // The mock *value* (a real path in FLTK's own source tree, kept
    // verbatim for faithful visual parity -- purely a placeholder
    // string, no functional meaning) is new, same reasoning as Input/
    // Output above.
    reg("File_Input", (x, y, w, h, l) {
        auto o = new FileInput(x, y, w, h, l !is null ? l : "file:");
        o.value("/usr/include/FL/Fl.H");
        return o;
    });
    registry["FileInput"] = registry["Fl_File_Input"];
    // Tree/Help_View/Table: Fl_Group subclasses in C++ that FLUID itself
    // treats as leaf types (see factory.d's matching entries for the
    // full reasoning) -- their own fl.* constructors already call end()
    // internally, so no extra FlGroup.current() handling is needed here.
    reg("Tree", (x, y, w, h, l) {
        auto o = new Tree(x, y, w, h, l);
        o.add("/A1/B1/C1");
        o.add("/A1/B1/C2");
        o.add("/A1/B2/C1");
        o.add("/A1/B2/C2");
        o.add("/A2/B1/C1");
        o.add("/A2/B1/C2");
        o.add("/A2/B2/C1");
        o.add("/A2/B2/C2");
        return o;
    });
    reg("Help_View", (x, y, w, h, l) {
        auto o = new HelpView(x, y, w, h, l);
        o.value("<HTML><BODY><H1>Fl_Help_View Widget</H1>"
            ~ "<P>This is a Fl_Help_View widget.</P></BODY></HTML>");
        return o;
    });
    registry["HelpView"] = registry["Fl_Help_View"];
    reg("Check_Browser", (x, y, w, h, l) {
        auto o = new CheckBrowser(x, y, w, h, l);
        foreach (i; 1 .. 21)
            o.add(format("Browser Line %d", i));
        return o;
    });
    registry["CheckBrowser"] = registry["Fl_Check_Browser"];
    reg("File_Browser", (x, y, w, h, l) {
        auto o = new FileBrowser(x, y, w, h, l);
        o.loadDirectory(".");
        return o;
    });
    registry["FileBrowser"] = registry["Fl_File_Browser"];
    reg("Table", (x, y, w, h, l) => new Table(x, y, w, h, l));
    // FLTK's own factory.cxx sets a 50% default value so a freshly-
    // dropped progress bar shows a visible fill instead of looking empty
    // (Fl_Progress's own default value is 0).
    reg("Progress", (x, y, w, h, l) {
        auto p = new Progress(x, y, w, h, l);
        p.value(50.0f);
        return p;
    });

    reg("Menu_Button", (x, y, w, h, l) => new MenuButton(x, y, w, h, l));
    registry["MenuButton"] = (x, y, w, h, l) => new MenuButton(x, y, w, h, l);
    reg("Choice", (x, y, w, h, l) => new Choice(x, y, w, h, l));
    // See factory.d's own matching entries' doc comment: `Menu_Bar`/
    // `Input_Choice` are `Menu_Manager_Node` subclasses in FLTK, the
    // same role `Menu_Button`/`Choice` already fill here.
    reg("Menu_Bar", (x, y, w, h, l) => new MenuBar(x, y, w, h, l));
    registry["MenuBar"] = (x, y, w, h, l) => new MenuBar(x, y, w, h, l);
    reg("Input_Choice", (x, y, w, h, l) => new InputChoice(x, y, w, h, l));
    registry["InputChoice"] = (x, y, w, h, l) => new InputChoice(x, y, w, h, l);

    // "Function"/"code"/"class"/"comment"/"decl"/"MenuItem" (factory.d's
    // other non-widget entries) have no live-widget counterpart at all
    // -- callers only ever reach into this registry for a WidgetNode's
    // *children*, never for those node kinds.
}

/// Public, not `private`: reused by `widget_panel.fl`'s own "Box"/
/// "Down Box" dropdowns (both need the same `.fl` boxtype-keyword ->
/// real `Boxtype` mapping -- one to *apply* it live, the other to
/// *offer* and apply it from the UI -- no reason for a second,
/// separately-maintained copy of the same table), and by
/// `panels/widget_panel.fl`'s own generated code too -- that file
/// compiles as a bare top-level module (no `module fluid.xxx;`
/// statement, matching every other generated `panels/*.d` file, see
/// `code_writer.d`'s own module-header note), not a member of the
/// `fluid` package the way `widget_panel.d`/`factory.d` are, so this
/// needs `package(fluid)` visibility, not just same-package access.
/// Covers all 68 real `Boxtype` values: every `fl.enumerations.Boxtype` member
/// except the 2 sentinels (`freeBoxtype`/`maxBoxtype`, neither a real
/// selectable boxtype) is mapped, matching FLTK's own full
/// `boxmenu[]` coverage (`nodes/Widget_Node.cxx`) -- FLTK splits
/// those into two `FL_SUBMENU`s ("boxes"/"frames"); this port keeps a
/// single flat, alphabetically-sorted list (`widget_panel.fl`'s
/// own `boxtypeNames`) rather than porting that submenu structure too.
immutable Boxtype[string] boxtypeMap;

/// Same reasoning and same two-maps-not-one split as `boxtypeMap` just
/// above: `code_writer.d`'s own private `typeWordMap` maps a `.fl`
/// `type` keyword to a string of D *source text* (an identifier to
/// emit into generated code, e.g. `"HORIZONTAL"` -> `"flexHorizontal"`),
/// which is no use here -- this is the same keyword set resolved to
/// the actual runtime `ubyte` value instead, applied directly to the
/// live canvas widget via `Widget.type(ubyte)`. `WidgetNode.typeWord` is
/// parsed/round-tripped/D-codegen'd and live-applied too,
/// most visibly on a `Flex`, whose orientation (`flexHorizontal`/
/// `flexVertical`) changes its entire layout.
immutable ubyte[string] typeWordValueMap;

shared static this()
{
    boxtypeMap = [
        "NO_BOX": Boxtype.noBox,
        "FLAT_BOX": Boxtype.flatBox,
        "UP_BOX": Boxtype.upBox,
        "DOWN_BOX": Boxtype.downBox,
        "UP_FRAME": Boxtype.upFrame,
        "DOWN_FRAME": Boxtype.downFrame,
        "THIN_UP_BOX": Boxtype.thinUpBox,
        "THIN_DOWN_BOX": Boxtype.thinDownBox,
        "THIN_UP_FRAME": Boxtype.thinUpFrame,
        "THIN_DOWN_FRAME": Boxtype.thinDownFrame,
        "ENGRAVED_BOX": Boxtype.engravedBox,
        "EMBOSSED_BOX": Boxtype.embossedBox,
        "ENGRAVED_FRAME": Boxtype.engravedFrame,
        "EMBOSSED_FRAME": Boxtype.embossedFrame,
        "BORDER_BOX": Boxtype.borderBox,
        "SHADOW_BOX": Boxtype.shadowBox,
        "BORDER_FRAME": Boxtype.borderFrame,
        "SHADOW_FRAME": Boxtype.shadowFrame,
        "ROUNDED_BOX": Boxtype.roundedBox,
        "RSHADOW_BOX": Boxtype.rshadowBox,
        "ROUNDED_FRAME": Boxtype.roundedFrame,
        "RFLAT_BOX": Boxtype.rflatBox,
        "ROUND_UP_BOX": Boxtype.roundUpBox,
        "ROUND_DOWN_BOX": Boxtype.roundDownBox,
        "DIAMOND_UP_BOX": Boxtype.diamondUpBox,
        "DIAMOND_DOWN_BOX": Boxtype.diamondDownBox,
        "OVAL_BOX": Boxtype.ovalBox,
        "OSHADOW_BOX": Boxtype.oshadowBox,
        "OVAL_FRAME": Boxtype.ovalFrame,
        "OFLAT_BOX": Boxtype.oflatBox,
        "PLASTIC_UP_BOX": Boxtype.plasticUpBox,
        "PLASTIC_DOWN_BOX": Boxtype.plasticDownBox,
        "PLASTIC_UP_FRAME": Boxtype.plasticUpFrame,
        "PLASTIC_DOWN_FRAME": Boxtype.plasticDownFrame,
        "PLASTIC_THIN_UP_BOX": Boxtype.plasticThinUpBox,
        "PLASTIC_THIN_DOWN_BOX": Boxtype.plasticThinDownBox,
        "PLASTIC_ROUND_UP_BOX": Boxtype.plasticRoundUpBox,
        "PLASTIC_ROUND_DOWN_BOX": Boxtype.plasticRoundDownBox,
        "GTK_UP_BOX": Boxtype.gtkUpBox,
        "GTK_DOWN_BOX": Boxtype.gtkDownBox,
        "GTK_UP_FRAME": Boxtype.gtkUpFrame,
        "GTK_DOWN_FRAME": Boxtype.gtkDownFrame,
        "GTK_THIN_UP_BOX": Boxtype.gtkThinUpBox,
        "GTK_THIN_DOWN_BOX": Boxtype.gtkThinDownBox,
        "GTK_THIN_UP_FRAME": Boxtype.gtkThinUpFrame,
        "GTK_THIN_DOWN_FRAME": Boxtype.gtkThinDownFrame,
        "GTK_ROUND_UP_BOX": Boxtype.gtkRoundUpBox,
        "GTK_ROUND_DOWN_BOX": Boxtype.gtkRoundDownBox,
        "GLEAM_UP_BOX": Boxtype.gleamUpBox,
        "GLEAM_DOWN_BOX": Boxtype.gleamDownBox,
        "GLEAM_UP_FRAME": Boxtype.gleamUpFrame,
        "GLEAM_DOWN_FRAME": Boxtype.gleamDownFrame,
        "GLEAM_THIN_UP_BOX": Boxtype.gleamThinUpBox,
        "GLEAM_THIN_DOWN_BOX": Boxtype.gleamThinDownBox,
        "GLEAM_ROUND_UP_BOX": Boxtype.gleamRoundUpBox,
        "GLEAM_ROUND_DOWN_BOX": Boxtype.gleamRoundDownBox,
        "OXY_UP_BOX": Boxtype.oxyUpBox,
        "OXY_DOWN_BOX": Boxtype.oxyDownBox,
        "OXY_UP_FRAME": Boxtype.oxyUpFrame,
        "OXY_DOWN_FRAME": Boxtype.oxyDownFrame,
        "OXY_THIN_UP_BOX": Boxtype.oxyThinUpBox,
        "OXY_THIN_DOWN_BOX": Boxtype.oxyThinDownBox,
        "OXY_THIN_UP_FRAME": Boxtype.oxyThinUpFrame,
        "OXY_THIN_DOWN_FRAME": Boxtype.oxyThinDownFrame,
        "OXY_ROUND_UP_BOX": Boxtype.oxyRoundUpBox,
        "OXY_ROUND_DOWN_BOX": Boxtype.oxyRoundDownBox,
        "OXY_BUTTON_UP_BOX": Boxtype.oxyButtonUpBox,
        "OXY_BUTTON_DOWN_BOX": Boxtype.oxyButtonDownBox,
    ];

    // Keys match `code_writer.d`'s own `typeWordMap` exactly -- keep
    // both in sync if a new widget's `type` keyword is ever added.
    typeWordValueMap = [
        "Radio": radioButton,
        "Multiline": outputMultiline,
        "Horizontal": horizontalType,
        "Vert Fill": vertFillSlider,
        "Vert Knob": vertNiceSlider,
        "Horz Fill": horFillSlider,
        "Horz Knob": horNiceSlider,
        "Simple": simpleCounter,
        "Float": inputFloat,
        "Line": lineDial,
        "Fill": fillDial,
        "HORIZONTAL": flexHorizontal,
        "VERTICAL": flexVertical,
        "Hold": holdBrowser,
        "Multi": multiBrowser,
        "Toggle": toggleButton,
    ];
}

/**
 * Builds a live widget tree from `root` (a parsed project's top-level
 * window) directly into `into` -- `into` (the design canvas, itself an
 * `fl.overlay_window.OverlayWindow`) *is* the live embodiment of the
 * root window Node, so unlike every other node it is never constructed
 * via `registry`; its own properties are applied directly onto `into`
 * instead. Nested windows (a `WindowNode` anywhere below `root`) are
 * out of scope for Phase 1 (multi-window projects) and are skipped
 * with nothing rendered for them, rather than attempted.
 */
LiveTree instantiate(WindowNode root, Window into, string projectDir = ".")
{
    LiveTree live;

    // Don't assume ambient state -- every Widget ctor auto-adds itself
    // to FlGroup.current(), so a stray leftover group (e.g. from the
    // shelf window/property panel construction) would silently steal
    // this project's own widgets otherwise.
    FlGroup.current(null);

    applyProperties(root, into, projectDir, false); // false: the canvas
                                         // is already sized/positioned
                                         // as a real top-level window;
                                         // don't reapply the root's own
                                         // recorded editor-session xywh
    // xclass/size_range: added alongside `panels/widget_panel.fl`'s own
    // "Window:" section. `modal`/
    // `non_modal` are deliberately still not live-applied here -- the
    // canvas is a design surface, not shown modally, so there is
    // nothing for that flag to visibly do on it (matches this
    // function's own existing scope: only properties with an actual
    // observable effect on the live canvas get applied).
    if (root.xclass.length) into.xclass(root.xclass);
    if (root.hasSizeRange)
        into.sizeRange(root.sizeRangeMinW, root.sizeRangeMinH,
            root.sizeRangeMaxW, root.sizeRangeMaxH);
    live.widgetOf[root] = into;
    live.nodeOf[into] = root;

    into.begin();
    foreach (child; root.children)
        instantiateChild(child, live, projectDir);
    into.end();

    return live;
}

/// Builds a standalone, freestanding live widget (plus every
/// descendant, if `n` is a container) for `n` alone -- unlike
/// `instantiate()` above (which builds directly into an already-
/// existing top-level `Window`, since the design canvas itself *is*
/// the live embodiment of a project's root window) or `instantiateChild()`
/// below (which only ever adds to an already-open ambient
/// `FlGroup.current()`), this constructs `n` itself as a brand-new,
/// unparented object: a real `fl.window.Window` if `n` is a
/// `WindowNode`, or the ordinary registry-constructed widget otherwise.
/// Registers everything it builds into `live`, the same as either of
/// those two.
///
/// Backs Live Resize (`widget_panel.fl`'s `liveModeCb()`) -- ported
/// from FLTK's own `Node::enter_live_mode()`, but as one function
/// rather than a virtual method overridden per node kind
/// (`Group_Node`/`Grid_Node`/`Flex_Node`/`Tabs_Node`/`Scroll_Node`/
/// `Tile_Node`/... each supply their own override in FLTK, all but
/// three of them (see below) doing nothing but "construct the right
/// concrete class, then call the shared `propagate_live_mode()`" --
/// `instantiate.d` already unifies that per-kind construction dispatch
/// in one place, `instantiateChild()`'s own `WidgetNode`/`GridNode`/
/// `FlexNode` branches, covering every widget/group/grid/flex kind
/// this project's factory knows how to build, so there is no separate
/// `enter_live_mode()`-per-subclass pattern to reproduce here.
///
/// A container's own children are built using their real, already-
/// absolute stored `x`/`y` (the same coordinate convention `project_
/// reader.d`/FLTK both use: a widget's `x`/`y` is always relative
/// to its own top-level window, not its immediate parent group) -- so
/// `n` itself is also constructed at *its own* stored `x`/`y` first
/// (keeping every descendant's coordinates internally consistent
/// against it), and the caller is expected to reposition the whole
/// returned widget as one rigid block afterward (`Widget.position()`,
/// which `fl.group.FlGroup`'s own `resize()` already shifts every child
/// by the same delta) -- exactly FLTK's own trick in `live_mode_cb()`
/// (`live_widget->position(10, 10);`, run *after* `enter_live_mode()`
/// returns). A `WindowNode` is the one exception: its own `x`/`y` is
/// its *editor-session screen position*, not meaningful geometry for a
/// freshly built copy (matching `instantiate()`'s own root-window
/// handling just above), so the fresh `Window` is left at its
/// construction default instead.
///
/// Three of FLTK's own per-kind overrides do something genuinely
/// special beyond generic construction, none of it reproduced here:
/// `Tabs_Node` re-selects the clone's active tab to match the original
/// (`widget_panel.fl`'s own `liveModeCb()` handles this instead, using
/// `liveTree_` to read the *original* live `Tabs`' current page --  a
/// property-panel-level concern, not this function's own construction
/// job); `Scroll_Node` calls `show()` on the fresh `Fl_Scroll` before
/// building its children (an FLTK-internal scrollbar-layout-timing
/// nuance with no confirmed fldtk equivalent need -- not replicated,
/// a possible source of a slightly-off initial scrollbar until the
/// first resize, not a structural gap); `Table_Node` builds a private
/// `Fl_Table_Proxy` directly instead of walking children through the
/// shared `propagate_live_mode()` at all (its own real children, if
/// any, go through the generic path here instead -- Table support in
/// this port has no proxy-widget layer to begin with, matching
/// `canvas.d`'s own "concrete, not polymorphic" stance).
Widget instantiateStandalone(Node n, ref LiveTree live, string projectDir = ".")
{
    if (auto wn = cast(WindowNode) n)
    {
        FlGroup.current(null);
        auto win = new Window(wn.hasXywh ? wn.w : 400, wn.hasXywh ? wn.h : 300,
            wn.hasLabel ? wn.label : null);
        applyProperties(wn, win, projectDir, false); // false: see instantiate()'s
                                                      // own identical root-window call
        if (wn.xclass.length) win.xclass(wn.xclass);
        live.widgetOf[n] = win;
        live.nodeOf[win] = n;
        win.begin();
        foreach (child; wn.children)
            instantiateChild(child, live, projectDir);
        win.end();
        return win;
    }

    auto leaf = cast(WidgetNode) n;
    if (leaf is null)
        return null; // Function/code/class/comment/decl/declblock/MenuItem: nothing to build

    auto ctor = leaf.typeName in registry;
    if (ctor is null)
        return null;

    int x = leaf.hasXywh ? leaf.x : 0;
    int y = leaf.hasXywh ? leaf.y : 0;
    int w = leaf.hasXywh ? leaf.w : 20;
    int h = leaf.hasXywh ? leaf.h : 20;

    FlGroup.current(null);
    auto widget = (*ctor)(x, y, w, h, leaf.hasLabel ? leaf.label : null);
    applyProperties(leaf, widget, projectDir);
    applyMenuItems(leaf, widget);
    live.widgetOf[n] = widget;
    live.nodeOf[widget] = n;

    if (leaf.canHaveChildren())
    {
        auto group = cast(FlGroup) widget;
        if (group !is null)
        {
            if (auto gn = cast(GridNode) leaf) applyGridOwnProperties(gn, cast(Grid) group);
            else if (auto fn = cast(FlexNode) leaf) applyFlexOwnProperties(fn, cast(Flex) group);

            group.begin();
            foreach (child; leaf.children)
                instantiateChild(child, live, projectDir);
            group.end();

            if (auto gn = cast(GridNode) leaf) applyGridChildPlacement(gn, cast(Grid) group, live);
            else if (auto fn = cast(FlexNode) leaf) applyFlexFixedSizes(fn, cast(Flex) group);
        }
    }

    return widget;
}

/// `package(fluid)`, not `private` -- `gui_main.d`'s Paste/Duplicate
/// need to instantiate an arbitrary already-parsed subtree under an
/// already-live parent `FlGroup` (the exact same recursive walk
/// `instantiate()`'s own top-level loop already does for a freshly-
/// opened project, just entered mid-tree instead of at the root), so
/// this can't stay module-private the way it was when `instantiate()`
/// was its only caller.
package(fluid) void instantiateChild(Node n, ref LiveTree live, string projectDir)
{
    if (cast(WindowNode) n)
        return; // nested windows: out of scope for Phase 1, skip

    // A `codeblock {}` has no live widget of its own (it's purely a
    // `code_writer.d`-level codegen wrapper -- see `code_block_node.d`'s
    // own doc comment), but its *children* can be real widgets (FLTK
    // Fluid renders them on the canvas same as any other child; a
    // codeblock is invisible at the FLTK-widget level, not a boundary
    // that hides what's inside it). Recurse into its children directly,
    // under whichever `FlGroup` is currently open -- same as walking a
    // plain widget-tree node's own children would, just without an
    // extra live widget/level of its own to instantiate first.
    if (auto cb = cast(CodeBlockNode) n)
    {
        foreach (child; cb.children)
            instantiateChild(child, live, projectDir);
        return;
    }

    auto wn = cast(WidgetNode) n;
    if (wn is null)
        return; // Function/code/class/comment/decl/declblock/MenuItem: no live widget

    auto ctor = wn.typeName in registry;
    if (ctor is null)
        return; // not yet in this registry -- silently skip, matching
                // factory.d's own "grows one type at a time" convention
                // (unlike factory.d, this is not a hard error: a
                // partially-renderable project is still useful to edit)

    int x = wn.hasXywh ? wn.x : 0;
    int y = wn.hasXywh ? wn.y : 0;
    int w = wn.hasXywh ? wn.w : 20;
    int h = wn.hasXywh ? wn.h : 20;
    // Relies on the enclosing group.begin()/group.end() (or, at the
    // top level, instantiate()'s own FlGroup.current(null) + into.begin())
    // to auto-parent this widget via the ambient FlGroup.current() --
    // unlike instantiateOne() below, deliberately does NOT touch
    // FlGroup.current() itself, since doing so here would defeat that
    // auto-parenting for every sibling still to come in this same walk.
    auto widget = (*ctor)(x, y, w, h, wn.hasLabel ? wn.label : null);

    applyProperties(wn, widget, projectDir);
    applyMenuItems(wn, widget);

    live.widgetOf[n] = widget;
    live.nodeOf[widget] = n;

    if (wn.canHaveChildren())
    {
        auto group = cast(FlGroup) widget;
        if (group !is null)
        {
            // Grid/Flex own properties (dimensions/margin/gap/...) have
            // to be applied *before* children are built, matching
            // FLTK's own ordering (a Grid needs its row/col count
            // before any child can be placed into a cell) -- unlike
            // the generic `applyProperties()` subset, neither is part
            // of it, since neither is a plain WidgetNode field.
            if (auto gn = cast(GridNode) wn) applyGridOwnProperties(gn, cast(Grid) group);
            else if (auto fn = cast(FlexNode) wn) applyFlexOwnProperties(fn, cast(Flex) group);

            group.begin();
            foreach (child; wn.children)
                instantiateChild(child, live, projectDir);
            group.end();

            // Placement/fixed-size need the children's own live widgets
            // to already exist, so these run after the loop above, not
            // interleaved with it.
            if (auto gn = cast(GridNode) wn) applyGridChildPlacement(gn, cast(Grid) group, live);
            else if (auto fn = cast(FlexNode) wn) applyFlexFixedSizes(fn, cast(Flex) group);
        }
    }
}

/// Grid's own dimensions/margin/gap/per-row-or-column arrays -- see
/// `grid_node.d`'s own doc comment for the property list this mirrors.
private void applyGridOwnProperties(GridNode gn, Grid g)
{
    if (gn.hasDimensions) g.layout(gn.rows, gn.cols);
    if (gn.hasMargin) g.margin(gn.marginLeft, gn.marginTop, gn.marginRight, gn.marginBottom);
    if (gn.hasGap) g.gap(gn.gapRow, gn.gapCol);
    foreach (i, v; gn.rowHeights) g.rowHeight(cast(int) i, v);
    foreach (i, v; gn.rowWeights) g.rowWeight(cast(int) i, v);
    foreach (i, v; gn.rowGaps) g.rowGap(cast(int) i, v);
    foreach (i, v; gn.colWidths) g.colWidth(cast(int) i, v);
    foreach (i, v; gn.colWeights) g.colWeight(cast(int) i, v);
    foreach (i, v; gn.colGaps) g.colGap(cast(int) i, v);
}

/// Places every already-instantiated child into its recorded grid cell
/// (`GridNode.cellOf`, populated by `readParentProperty()` while
/// parsing -- see `grid_node.d`'s own doc comment on the
/// `parent_properties` mechanism this comes from).
private void applyGridChildPlacement(GridNode gn, Grid g, ref LiveTree live)
{
    foreach (childNode, info; gn.cellOf)
    {
        auto w = childNode in live.widgetOf;
        if (w is null)
            continue; // child wasn't instantiated (unregistered type, etc.)
        auto cell = g.widget(*w, info.row, info.col, info.rowspan, info.colspan,
            cast(GridAlign) info.alignRaw);
        if (cell !is null && (info.minW != 20 || info.minH != 20))
            cell.minimumSize(info.minW, info.minH);
    }
}

private void applyFlexOwnProperties(FlexNode fn, Flex f)
{
    if (fn.hasMargin) f.margin(fn.marginLeft, fn.marginTop, fn.marginRight, fn.marginBottom);
    if (fn.hasGap) f.gap(fn.gap);
}

/// Applies `FlexNode.fixedSizeTuples` (`[idx0, size0, idx1, size1, ...]`)
/// against the now-fully-built child list -- see `flex_node.d`'s own
/// doc comment on why this needs no "postprocess" hook in the parser
/// itself (children are always fully known by the time this runs).
private void applyFlexFixedSizes(FlexNode fn, Flex f)
{
    for (size_t i = 0; i + 1 < fn.fixedSizeTuples.length; i += 2)
    {
        int idx = fn.fixedSizeTuples[i];
        int size = fn.fixedSizeTuples[i + 1];
        if (idx >= 0 && idx < f.children())
            f.fixed(f.child(idx), size);
    }
}

/// Constructs one live widget for `wn` alone (no children, no
/// `LiveTree` bookkeeping, no auto-parenting) -- what the widget
/// palette (`fluid.gui_main`'s "New" menu) needs to create a single
/// new widget outside of any tree walk, so it can `FlGroup.add()` the
/// result onto whatever target group the user actually has selected.
/// Returns `null` if `wn.typeName` isn't in `registry` (shouldn't
/// happen for anything the palette itself offers, since it only
/// offers types already registered here).
///
/// Unlike `instantiateChild()` above (which deliberately leaves
/// `FlGroup.current()` alone to let the ambient `begin()`/`end()`
/// bracket auto-parent each widget during a tree walk), this function
/// explicitly resets `FlGroup.current(null)` first: called standalone,
/// with no such bracket in scope, the ambient current group could be
/// anything left over from unrelated shelf/property-panel
/// construction -- resetting it avoids silently stealing this widget
/// into the wrong group instead of leaving it for the caller to
/// `FlGroup.add()` explicitly.
Widget instantiateOne(WidgetNode wn, string projectDir = ".")
{
    auto ctor = wn.typeName in registry;
    if (ctor is null)
        return null;

    int x = wn.hasXywh ? wn.x : 0;
    int y = wn.hasXywh ? wn.y : 0;
    int w = wn.hasXywh ? wn.w : 20;
    int h = wn.hasXywh ? wn.h : 20;

    FlGroup.current(null);
    auto widget = (*ctor)(x, y, w, h, wn.hasLabel ? wn.label : null);
    applyProperties(wn, widget, projectDir);
    applyMenuItems(wn, widget);
    return widget;
}

/// Applies the Phase 1 property subset from `n` onto the already-
/// constructed `w`. Called both for the root window (against `into`
/// directly, with `applyXywh = false` -- see `instantiate()`'s own
/// comment) and for every other widget (against its freshly `new`'d
/// instance, with `applyXywh = true`, though for those `w` was already
/// constructed at `n.x/y/w/h` in `instantiateChild()` too -- reapplying
/// here is harmless and keeps this function the single place every
/// property, xywh included, gets applied). `projectDir` resolves
/// `imageFilename`/`deimageFilename` (the `Widget_Image` port) the same way `code_writer.d`'s own `projectDir_`
/// does; defaults to "." since most callers (a freshly palette-created
/// widget, every existing unittest) never have an image set anyway.
///
/// Public (not `private`) so `widget_panel.d`'s `syncCurrentToLive()`
/// can call it too, as a live model->widget re-sync after every panel
/// edit -- the same single place every property gets applied,
/// reused for "re-apply after an edit" instead of only "apply once at
/// construction time".
void applyProperties(WidgetNode n, Widget w, string projectDir = ".", bool applyXywh = true)
{
    if (applyXywh && n.hasXywh) w.resize(n.x, n.y, n.w, n.h);

    // Unconditional, unlike most other fields below -- `n.label` is
    // already "" whenever `!n.hasLabel` (every writer of these two
    // fields sets them together, e.g. `widget_panel.fl`'s own
    // `wpGuiLabel` callback: `wn.hasLabel = v.length > 0`), so this
    // correctly clears the live widget's label too when the user
    // deletes it entirely. Gating this behind `if (n.hasLabel)` (the
    // same pattern most fields below use, where "unset" has a
    // meaningful non-blank default to fall back to) would be a real
    // bug: clearing the label would update the Node model
    // (and the project tree, which reads straight off it) but the
    // live canvas widget would keep showing its stale prior label forever,
    // since this line would simply never run again once `hasLabel` flipped
    // to `false`.
    w.label(n.label);

    if (n.hasBoxtype)
    {
        if (auto p = n.boxtype in boxtypeMap)
            w.box(*p);
    }

    // See `typeWordValueMap`'s own doc comment above -- not a
    // `WindowNode` case (a window's `typeWord` means "Double"/single,
    // handled separately, entirely at construction time via
    // `instantiateOne()`'s own class-selection switch, not via
    // `Widget.type()` here).
    if (n.typeWord.length && cast(WindowNode) n is null)
    {
        if (auto st = subtypeFor(n.typeName, n.typeWord))
            w.type(st.value);
        else if (auto p = n.typeWord in typeWordValueMap)
            w.type(*p);
    }

    if (n.color >= 0) w.color(cast(Color) n.color);
    if (n.selectionColor >= 0) w.selectionColor(cast(Color) n.selectionColor);

    // labelfont/labelsize: added alongside panels/widget_panel.fl's own
    // matching edit fields so a
    // project loaded with either already set (e.g. radio.fl's own
    // `labelfont 1` rows) renders correctly on the canvas from the
    // start, not just after the user re-touches the field in the
    // property panel.
    if (n.labelfont >= 0) w.labelfont(cast(Font) n.labelfont);
    if (n.labelsize >= 0) w.labelsize(n.labelsize);

    // down_box/labeltype/align/when: added alongside panels/widget_panel.fl's
    // own "Widget Style" section, same reasoning as labelfont/labelsize just above -- a
    // project loaded with any of these already set renders correctly
    // from the start.
    if (n.hasDownBoxtype)
        if (auto p = n.downBoxtype in boxtypeMap)
        {
            if (auto btn = cast(Button) w) btn.downBox(*p);
            else if (auto m = cast(Menu_) w) m.downBox(*p);
            else if (auto fi = cast(FileInput) w) fi.downBox(*p);
            else if (auto ic = cast(InputChoice) w) ic.downBox(*p);
        }
    if (n.labeltype.length)
        if (auto p = n.labeltype in labeltypeMap)
            w.labeltype(*p);
    if (n.alignRaw >= 0) w.alignment(cast(Align) n.alignRaw);
    // `whenRaw` was already parsed by `project_reader.d` and round-tripped by
    // `project_writer.d`, but `code_writer.d`'s D-codegen path silently
    // dropped it until the same pass that added this line -- see that
    // file's own `writeCommonProps()` comment for the full story.
    if (n.whenRaw >= 0) w.when(cast(When) n.whenRaw);

    // labelcolor/text font-size-color/label margins/compact: the
    // Style tab's own callbacks (e.g. `applyLabelColor()`) correctly write
    // the model field in every case, and this function reads all of
    // them back. `labelcolor()`/
    // `horizontalLabelMargin()`/`verticalLabelMargin()`/
    // `labelImageSpacing()` are plain base-`Widget` methods (FLTK has no
    // such method on the base `Fl_Widget`); `compact()` is `Button`-only.
    //
    // `textfont()`/`textsize()`/`textcolor()` don't exist on the base
    // `Fl_Widget` either -- `Input_`/`ValueOutput`/`ValueInput`/
    // `ValueSlider`/`Menu_` each have their own independent, unrelated
    // version (confirmed real in each of those 5 classes' own D source),
    // all 5 covered here: e.g. `samples/test/inactive.fl`'s
    // `ValueOutput` sets `textfont 5 textsize 24 textcolor 4` in real,
    // byte-identical-to-FLTK `.fl` text, and it applies on
    // the live canvas. A widget can only be one of these 5 unrelated
    // hierarchies at once, so a plain `if`/`else if` chain is exhaustive
    // and unambiguous.
    if (n.labelcolorRaw >= 0) w.labelcolor(cast(Color) n.labelcolorRaw);
    if (auto in_ = cast(Input_) w)
    {
        if (n.textfont >= 0) in_.textfont(cast(Font) n.textfont);
        if (n.textsize >= 0) in_.textsize(n.textsize);
        if (n.textcolorRaw >= 0) in_.textcolor(cast(Color) n.textcolorRaw);
    }
    else if (auto vout = cast(ValueOutput) w)
    {
        if (n.textfont >= 0) vout.textfont(cast(Font) n.textfont);
        if (n.textsize >= 0) vout.textsize(n.textsize);
        if (n.textcolorRaw >= 0) vout.textcolor(cast(Color) n.textcolorRaw);
    }
    else if (auto vin = cast(ValueInput) w)
    {
        if (n.textfont >= 0) vin.textfont(cast(Font) n.textfont);
        if (n.textsize >= 0) vin.textsize(n.textsize);
        if (n.textcolorRaw >= 0) vin.textcolor(cast(Color) n.textcolorRaw);
    }
    else if (auto vslider = cast(ValueSlider) w)
    {
        if (n.textfont >= 0) vslider.textfont(cast(Font) n.textfont);
        if (n.textsize >= 0) vslider.textsize(n.textsize);
        if (n.textcolorRaw >= 0) vslider.textcolor(cast(Color) n.textcolorRaw);
    }
    else if (auto menu = cast(Menu_) w)
    {
        if (n.textfont >= 0) menu.textfont(cast(Font) n.textfont);
        if (n.textsize >= 0) menu.textsize(n.textsize);
        if (n.textcolorRaw >= 0) menu.textcolor(cast(Color) n.textcolorRaw);
    }
    if (n.hLabelMargin >= 0) w.horizontalLabelMargin(n.hLabelMargin);
    if (n.vLabelMargin >= 0) w.verticalLabelMargin(n.vLabelMargin);
    if (n.imageSpacing >= 0) w.labelImageSpacing(n.imageSpacing);
    if (n.compactRaw.length)
        if (auto btn = cast(Button) w) btn.compact(n.compactRaw == "1");

    // value/minimum/maximum/step: for numerical
    // boxes, same as Label -- the live canvas must reflect the Value
    // defined in the Values group. `n.valueRaw`/`minimumRaw`/
    // `maximumRaw`/`stepRaw` are stored as raw D-expression text (a
    // hand-authored `.fl` file can genuinely put an arbitrary D
    // expression there, e.g. a named constant -- matching `shortcutRaw`'s
    // own documented "not a value this generator can evaluate" limit,
    // see this module's own top comment), so this can't unconditionally
    // apply them the way a real int/enum field can. But `widget_panel.
    // fl`'s own "Values:" group (`valuesMinimum`/`valuesMaximum`/
    // `valuesStep`/`valuesValue`) is a plain numeric `ValueInput`
    // quartet that only ever writes `to!string(aDouble)` into these
    // fields in the first place -- so a best-effort `to!double` parse,
    // silently skipped when it doesn't parse (a hand-authored `.fl`
    // file's own non-numeric expression, the one case this genuinely
    // can't preview live), covers the common, UI-driven case for real.
    // `code_writer.d`'s own D-codegen still emits the raw text verbatim
    // either way, so nothing here can ever lose information -- only
    // fail to *preview* it live, exactly like `shortcutRaw` already
    // does. `minimum`/`maximum`/`step` apply to `Valuator` (slider/
    // counter/dial/roller/...) and `Spinner` (a `Group` subclass
    // in FLTK, not a `Valuator` -- duck-type-identical `minimum()`/
    // `maximum()`/`step()`/`value()` API, but no common base type to
    // dispatch through in this port either, matching FLTK's own
    // separate class hierarchy). `value` additionally applies to
    // `Button` -- its own checked/down state, sharing this
    // exact same `.fl` property and `widget_panel.fl` field with
    // Valuator/Spinner (see the `else if (auto btn = cast(Button) w)`
    // branch just below for the full writeup), matching FLTK's own
    // `Widget_Node::read_property()`/`widget_panel.cxx` "Value:" field,
    // both of which handle all three kinds identically.
    {
        static bool tryParseDouble(string raw, out double v)
        {
            try { v = to!double(raw); return true; }
            catch (Exception) { return false; }
        }
        auto valuator = cast(Valuator) w;
        auto spinner = cast(Spinner) w;
        if (valuator !is null || spinner !is null)
        {
            double v;
            if (n.hasMinimum && tryParseDouble(n.minimumRaw, v))
            {
                if (valuator !is null) valuator.minimum(v);
                else spinner.minimum(v);
            }
            if (n.hasMaximum && tryParseDouble(n.maximumRaw, v))
            {
                if (valuator !is null) valuator.maximum(v);
                else spinner.maximum(v);
            }
            if (n.hasStep && tryParseDouble(n.stepRaw, v))
            {
                if (valuator !is null) valuator.step(v);
                else spinner.step(v);
            }
            if (n.hasValue && tryParseDouble(n.valueRaw, v))
            {
                if (valuator !is null) valuator.value(v);
                else spinner.value(v);
            }
        }
        else if (auto btn = cast(Button) w)
        {
            // A `Button`'s own `value` (its checked/down state) shares
            // the exact same `.fl` "value N" property and the exact
            // same `widget_panel.fl` "Values:" `valuesValue` field as
            // Valuator/Spinner above -- matches FLTK's own
            // `Widget_Node::read_property()` (`atoi(value)` for
            // `is_button()`, `strtod()` for a `Valuator`/`Spinner`) and
            // `widget_panel.cxx`'s own single shared "Value:" callback
            // (`is_button()` -> `((Fl_Button*)(q->o))->value(n != 0);`,
            // same `n` the Valuator/Spinner branches use). Same
            // best-effort `to!double` parse as above, since this port's
            // own `valuesValue` field writes the identical `to!string(
            // aDouble)` text regardless of which of the three kinds is
            // selected.
            double v;
            if (n.hasValue && tryParseDouble(n.valueRaw, v))
                btn.value(v != 0);
        }
    }

    // shortcutRaw needs no D-expression interpreter to live-apply.
    // FLTK's own `Widget_Node::read_property()`/`write_properties()`
    // (`Widget_Node.cxx`) store `shortcut` as a **plain integer**
    // (`strtol(f.read_word(), nullptr, 0)` / `f.write_string("shortcut
    // 0x%x", ...)`), never an arbitrary expression -- this port's own
    // `shortcutRaw` matches exactly (`widget_node.d`'s own doc comment:
    // "a raw int/hex literal"), and `widget_panel.fl`'s own `wpGuiShortcut`
    // field (a real keystroke-capturing `ShortcutButton`, matching
    // FLTK's own `wp_gui_shortcut`) only ever writes `format("0x%x",
    // sc)` into it. So the same best-effort literal parse `value`/
    // `minimum`/`maximum`/`step` already get above applies here too --
    // just with an explicit hex radix, since `to!uint` doesn't auto-
    // detect a `"0x"` prefix the way a D/C integer literal would.
    // Dispatches on the same 4 widget kinds FLTK's own `is_button()`/
    // `Input_Node`/`Value_Input_Node`/`Text_Display_Node` branch does.
    if (n.hasShortcut)
    {
        bool tryParseShortcut(string raw, out uint v)
        {
            import std.string : startsWith;
            try
            {
                v = (raw.startsWith("0x") || raw.startsWith("0X"))
                    ? to!uint(raw[2 .. $], 16) : to!uint(raw);
                return true;
            }
            catch (Exception) { return false; }
        }
        uint sc;
        if (tryParseShortcut(n.shortcutRaw, sc))
        {
            if (auto btn = cast(Button) w) btn.shortcut(sc);
            else if (auto in_ = cast(Input_) w) in_.shortcut(sc);
            else if (auto vi = cast(ValueInput) w) vi.shortcut(sc);
            else if (auto td = cast(TextDisplay) w) td.shortcut(sc);
        }
    }

    // hidden/deactivated are applied bidirectionally for ordinary
    // child widgets (an explicit `else` branch too), not just the
    // "turn it on" half a one-shot fresh-construction call would need
    // -- this function also now doubles as the live model->widget
    // re-sync path the property panel calls after every edit (see
    // `widget_panel.d`'s `syncCurrentToLive()`), where a field can
    // toggle back off just as easily as it toggled on (e.g.
    // unchecking "Visible" after it was already hidden once).
    // Gated on `applyXywh` -- the same flag that already means "this
    // is the root canvas window, not an ordinary child" -- because
    // `w.show()`/`w.activate()` dispatch virtually, and for the root
    // canvas `w` is actually a `Window`: an unconditional `w.show()`
    // there would call `Window.show()`, mapping a real X11 window as
    // a side effect of a completely unrelated property sync, instead
    // of the base `Widget.show()`'s plain visibility-flag toggle an
    // ordinary child gets. The root window's own visibility isn't a
    // panel-editable property anyway (nothing calls this with
    // `applyXywh == false` from a "Visible" checkbox).
    if (n.hidden) w.hide();
    else if (applyXywh) w.show();
    if (n.deactivated) w.deactivate();
    else if (applyXywh) w.activate();
    w.tooltip(n.tooltip);

    // image/deimage (the `Widget_Image` port): unlike `code_writer.d`'s own `writeWidgetImage()` (which embeds
    // the file's bytes into generated D), the live canvas just loads
    // the file directly off disk via the already-real codec's own
    // `this(string filename)` constructor -- simpler here since there's
    // no "generate self-contained source" constraint for a live preview.
    // A missing/invalid file doesn't throw (every codec here mirrors
    // FLTK's own `Fl_Image::ld(ERR_FILE_ACCESS)` pattern -- see
    // e.g. `fl.png_image.PngImage`'s own constructor), so no try/catch
    // is needed at this call site either.
    // `scaleImageW`/`.scaleImageH` (`WidgetNode`'s own doc comment) are
    // real both for the generated-D codegen path (`code_writer.d`'s own
    // trailing `.scale(...)` call, ported from `Widget_Image::write_
    // code()`) and applied here: a `.fl` file with a real
    // `scale_image {w h}` (e.g. `settings_panel.fl`'s own tab icons,
    // `../icons/*_64.png` scaled down to `{36 24}`) generates correctly-
    // sized code and shows the image at that size on the
    // live canvas too. Same "0 falls back to the image's own
    // natural size" rule as `code_writer.d`'s version.
    if (n.hasImage && n.imageFilename.length)
        if (auto img = loadImageFile(buildPath(projectDir, n.imageFilename)))
        {
            if (n.scaleImageW || n.scaleImageH)
                img.scale(n.scaleImageW > 0 ? n.scaleImageW : img.dataW(),
                    n.scaleImageH > 0 ? n.scaleImageH : img.dataH(), false, true);
            w.image(img);
        }
    if (n.hasDeimage && n.deimageFilename.length)
        if (auto img = loadImageFile(buildPath(projectDir, n.deimageFilename)))
        {
            if (n.scaleDeimageW || n.scaleDeimageH)
                img.scale(n.scaleDeimageW > 0 ? n.scaleDeimageW : img.dataW(),
                    n.scaleDeimageH > 0 ? n.scaleDeimageH : img.dataH(), false, true);
            w.deimage(img);
        }

    // resizableFlag: added alongside panels/widget_panel.fl's own
    // "Attributes:" section. `w.parent()` is already the ambient live group by this
    // point -- every widget ctor auto-adds itself to `FlGroup.current()`
    // before `applyProperties()` ever runs (see `fl.widget.Widget`'s
    // own constructor) -- except for the root window itself (`w is
    // into` in `instantiate()`, no live parent group to designate),
    // matching `code_writer.d`'s own D-codegen for that case (`Window.
    // resizable(itself)`, a self-reference `FlGroup.resizable()` has no
    // equivalent of here since the canvas *is* the window, not a child
    // of one).
    if (n.resizableFlag)
        if (auto parentGroup = cast(FlGroup) w.parent())
            parentGroup.resizable(w);
}

/// Builds a real `MenuItem[]` array from `n`'s own `MenuItemNode`
/// children and applies it via `.menu(items)` -- the live-canvas
/// counterpart of `code_writer.d`'s `writeMenuOwnerNode()`/
/// `writeMenuItemLiteral()` (same field set, same `MenuFlags`
/// combination via `menuItemFlags()` just below). Previously entirely
/// missing here: a `Choice`/`Menu_Button`/`Menu_Bar`/`Input_Choice`
/// populated the real, declarative Fluid way (literal `MenuItem {}`
/// children in the `.fl` tree, as opposed to a `setup{}` code snippet
/// -- the two cases are genuinely different problems) rendered as an
/// empty menu on the canvas even though the very same project already
/// generates a correctly populated D `MenuItem[]` array. No-op for
/// anything that isn't a `Menu_` (every ordinary leaf/group widget) or
/// has no `MenuItemNode` children at all, so safe to call unconditionally
/// right after `applyProperties()`.
///
/// A `MenuItemNode`'s own `callback` text can't be applied here (raw D
/// source, the same standing "no D-expression interpreter" limitation
/// `shortcutRaw`/setup code already have -- see this module's own top
/// comment) -- every live menu item's callback is `null`, appearance/
/// selection only, matching every other live-canvas simplification in
/// this module.
void applyMenuItems(WidgetNode n, Widget w)
{
    // `InputChoice` is a `Group` FLTK too (embeds a real `Input` +
    // `MenuButton` rather than being a `Menu_` itself), so its own menu
    // lives on `menubutton()`, not `w` directly -- without this,
    // an `InputChoice`'s live-canvas
    // dropdown would always be empty regardless of its `MenuItemNode`
    // children, unlike `Choice`/`MenuButton`/`MenuBar`.
    Menu_ m;
    if (auto ic = cast(InputChoice) w)
        m = ic.menubutton();
    else
        m = cast(Menu_) w;
    if (m is null) return;

    // `uses_font_menu` (`fluid.font_menu`'s own doc comment): a shared
    // font list instead of literal `MenuItem {}` children, so there are
    // none to walk here -- populate the live canvas from the same
    // shared array `code_writer.d`'s own codegen path uses, matching
    // FLTK's real menu text/order exactly, instead of showing an
    // empty dropdown while editing.
    if (n.usesFontMenu)
    {
        m.menu(fontMenuItems());
        return;
    }
    // `uses_color_menu` (`fluid.color_menu`'s own doc comment): same
    // mechanism, for the 14-entry quick-pick color list instead.
    if (n.usesColorMenu)
    {
        m.menu(colorMenuItems());
        return;
    }

    MenuItem[] items;
    Node[] itemNodes;
    appendMenuItems(n, items, itemNodes);
    if (items.length == 0) return;

    // `fl.menu_item`'s own item-array walk relies on a trailing
    // null-text sentinel to know where the array ends, same as
    // `code_writer.d`'s own generated `MenuItem(null),` -- see that
    // function's own comment for why this isn't optional.
    items ~= MenuItem(null);
    m.menu(items);
}

/// Same walk `applyMenuItems()` uses to populate a live `Menu_`'s items,
/// returning just the `MenuItemNode`/`SubmenuNode` side (a `null` entry
/// marks a submenu-closing sentinel, matching `appendMenuItems()`'s own
/// `MenuItem(null)`) -- lets a caller that already has a picked item's
/// index (via `Menu_.findIndex()` on the live `const(MenuItem)*` `Menu_.
/// mvalue()` returns) map it back to the source node. Used by `canvas.d`'s
/// menu click-test (ported from `Menu_Base_Node::click_test()`/
/// `Input_Choice_Node::click_test()`, `nodes/Menu_Node.cxx`) -- recomputing
/// this fresh on every click rather than caching it alongside the applied
/// `MenuItem[]` is safe and simpler: the walk is a pure function of `n`'s
/// own children, unchanged between the paint that last called
/// `applyMenuItems()` and the click that reads it back.
package(fluid) Node[] menuItemNodeMap(WidgetNode n)
{
    MenuItem[] items;
    Node[] itemNodes;
    appendMenuItems(n, items, itemNodes);
    return itemNodes;
}

/// Appends `n`'s own `MenuItemNode` children into `items`, recursing
/// into a `SubmenuNode` child's own children and closing that nesting
/// level with a `MenuItem(null)` sentinel before continuing -- the
/// live-canvas counterpart of `code_writer.d`'s own recursive
/// `writeMenuOwnerNode()`/`writeMenuItemLiteral()` walk. Matches
/// `fl.menu_item`'s own flat, sentinel-delimited embedded-submenu
/// format (see `validateMenuArray()`'s doc comment in `fl.menu_item`):
/// a `menuSubmenu`-flagged item's nested items follow it inline in the
/// same array, closed by a matching null-text entry, even when that
/// submenu has zero children -- an *unconditional* close, not "only if
/// there's something to close", since a missing sentinel here is
/// exactly the "consumes the rest of the array" hazard that function's
/// own doc comment describes.
private void appendMenuItems(WidgetNode n, ref MenuItem[] items, ref Node[] itemNodes)
{
    foreach (c; n.children)
    {
        auto mi = cast(MenuItemNode) c;
        if (mi is null) continue;
        Labeltype labeltype = Labeltype.normalLabel;
        if (mi.labeltype.length)
            if (auto p = mi.labeltype in labeltypeMap)
                labeltype = *p;
        items ~= MenuItem(mi.hasLabel ? mi.label : null, 0, null, menuItemFlags(mi),
            labeltype,
            mi.labelfont >= 0 ? cast(Font) mi.labelfont : 0,
            mi.labelsize >= 0 ? mi.labelsize : 0,
            mi.labelcolorRaw >= 0 ? cast(Color) mi.labelcolorRaw : 0);
        itemNodes ~= mi;
        if (mi.canHaveChildren())
        {
            appendMenuItems(mi, items, itemNodes);
            items ~= MenuItem(null);
            itemNodes ~= null;
        }
    }
}

/// FLTK: `Menu_Item_Node::flags()` (`Menu_Node.cxx`) -- combines
/// `hotspotFlag` (reused as "divider" for a menu item, `FL_MENU_DIVIDER`),
/// `headline_` (`FL_MENU_HEADLINE`), `canHaveChildren()` (`FL_SUBMENU` --
/// FLTK computes this dynamically from `can_have_children()` too,
/// rather than storing it, since it's really a property of which
/// concrete node class this is, `Submenu_Node` vs. plain
/// `Menu_Item_Node`), and `typeName` (`FL_MENU_TOGGLE`/`FL_MENU_RADIO`
/// -- FLTK bakes these into the generated widget's own `type()` at
/// creation time via `Checkbox_Menu_Item_Node`/`Radio_Menu_Item_Node`'s
/// `make()` overrides; this port's `typeName` field already carries the
/// same "which `.fl` keyword created this" signal, see `menu_item_node.d`'s
/// own doc comment for why no dedicated D subclass was needed for these
/// two) into the live `MenuFlags` word. The live-canvas counterpart of
/// `code_writer.d`'s own identically-named `menuItemFlags()`.
private MenuFlags menuItemFlags(MenuItemNode mi)
{
    MenuFlags flags;
    if (mi.hotspotFlag) flags |= menuDivider;
    if (mi.headline_) flags |= menuHeadline;
    if (mi.canHaveChildren()) flags |= menuSubmenu;
    if (mi.typeName == "CheckMenuItem") flags |= menuToggle;
    if (mi.typeName == "RadioMenuItem") flags |= menuRadio;
    return flags;
}

private immutable Labeltype[string] labeltypeMap;

shared static this()
{
    labeltypeMap = [
        "NORMAL_LABEL": Labeltype.normalLabel,
        "NO_LABEL": Labeltype.noLabel,
        "SHADOW_LABEL": Labeltype.shadowLabel,
        "ENGRAVED_LABEL": Labeltype.engravedLabel,
        "EMBOSSED_LABEL": Labeltype.embossedLabel,
    ];
}

/// Which of this port's own already-real image codecs to construct for
/// a live-canvas preview, chosen by file extension -- the live-load
/// counterpart of `code_writer.d`'s own `imageClassFor()` (same extension
/// table, kept as a separate copy rather than shared since one picks a
/// D *class name string* for codegen and this one directly constructs
/// an `Image`; sharing would need its own small abstraction for little
/// benefit at this size, matching `fontNames`/`labeltypeMap`'s own
/// "not worth a shared table" precedent elsewhere in this port). `null`
/// for an unrecognized extension -- the caller just skips setting the
/// image rather than erroring the whole canvas render. `package(fluid)`,
/// not `private`: `panels/widget_panel.fl`'s own "Image:"/"Inactive:" fields
/// reuse this directly to live-apply an edit, matching `boxtypeMap`'s
/// own visibility widening for the same "one copy, two consumers"
/// reason.
package(fluid) Image loadImageFile(string path)
{
    import std.path : extension;
    import std.string : toLower;

    switch (path.extension.toLower)
    {
    case ".png": return new PngImage(path);
    case ".jpg": case ".jpeg": return new JpegImage(path);
    case ".gif": return new GifImage(path);
    case ".bmp": return new BMPImage(path);
    case ".xpm": return new XPMImage(path);
    case ".xbm": return new XBMImage(path);
    case ".ico": return new ICOImage(path);
    case ".svg": case ".svgz": return new SvgImage(path);
    case ".pnm": case ".pbm": case ".pgm": case ".ppm": return new PNMImage(path);
    default: return null;
    }
}

unittest
{
    // A `codeblock {}` sitting among a window's own widget-tree children
    // has no live widget of its own, but its own children still need to
    // be instantiated -- otherwise the interactive canvas would silently
    // fail to render (or hit-test) anything nested inside one, even
    // though `code_writer.d`'s own codegen already walks into it for
    // real.
    import fluid.window_node : WindowNode;
    import fluid.widget_node : WidgetNode;

    FlGroup.current(null);

    auto rootNode = new WindowNode();
    rootNode.typeName = "Fl_Window";
    rootNode.x = 0; rootNode.y = 0; rootNode.w = 100; rootNode.h = 100;
    rootNode.hasXywh = true;

    auto cb = new CodeBlockNode();
    cb.typeName = "codeblock";
    cb.instanceName = "if (test())";
    rootNode.addChild(cb);

    auto boxNode = new WidgetNode();
    boxNode.typeName = "Fl_Box";
    boxNode.instanceName = "b";
    boxNode.x = 0; boxNode.y = 0; boxNode.w = 20; boxNode.h = 20;
    boxNode.hasXywh = true;
    cb.addChild(boxNode);

    auto into = new Window(100, 100);
    auto live = instantiate(rootNode, into);

    assert(cb !in live.widgetOf); // the codeblock itself has no live widget
    auto boxWidget = boxNode in live.widgetOf;
    assert(boxWidget !is null); // but its child widget was still instantiated
    assert((*boxWidget).parent() is into); // ...directly under the window, matching FLTK

    FlGroup.current(null);
}

/// Per-type default geometry for a freshly-created widget -- this
/// port's counterpart to FLTK's `Widget_Node::ideal_size()` and its
/// ~12 per-type overrides (`nodes/Widget_Node.cxx`, `nodes/Button_Node.
/// cxx`, `nodes/Group_Node.cxx`, `nodes/factory.cxx`'s own per-
/// prototype-class overrides), called from `add_new_widget_from_user()`
/// for *every* newly created widget, drag-dropped or palette-clicked
/// alike.
///
/// Backed by the real `fluid.
/// layout_suite.LayoutList`: every formula below reads `layout.
/// labelsize`/`layout.textsizeNotNull()` from the *actual current*
/// Layout Suite preset, matching FLTK's own `Fluid.proj.
/// layout->labelsize`/`textsize_not_null()` exactly (see `layout_suite.d`'s
/// own top comment for what's ported of that subsystem and what's
/// still deliberately narrower). `Snap_Action::better_size()`'s own
/// grid-snapping pass (FLTK runs it after computing the raw ideal
/// size) is real too -- see `fluid.snap_action.betterSize()`,
/// applied at the very end of this function.
///
/// Container types (`Group`/`Tabs`/`Wizard`/`Pack`/`Scroll`/`Tile`) also
/// skip FLTK's `Group_Node::ideal_size()` parent-relative halving
/// (`w = parent->w()/2` when dropped into another true widget) --
/// always returns its own flat `140x140` "no applicable parent" branch
/// instead, since threading the *target* parent's own live size into
/// this lookup would need a real signature change for a cosmetic
/// refinement.
///
/// Everything not explicitly listed here falls back to `120x100`,
/// matching FLTK's own `Widget_Node::ideal_size()` base-class
/// default exactly (confirmed: no `ideal_size` override exists
/// anywhere in `nodes/Menu_Node.cxx`/`Grid_Node.cxx` either, so
/// `Slider`/`Scrollbar`/`ValueSlider`/`ValueInput`/`Spinner`/`Terminal`/
/// `Output`/`Input`/`FloatInput`/`IntInput`/`TextDisplay`/`TextEditor`/
/// `MenuButton`/`MenuBar`/`Choice`/`InputChoice`/`ShortcutButton`/
/// `Grid`/`Flex` all genuinely use the plain default FLTK too, not
/// a fldtk gap).
package(fluid) void idealSizeFor(string typeName, out int w, out int h)
{
    import fluid.layout_suite : layoutList;
    import fluid.snap_action : betterSize;
    import fluid.code_writer : stripFlPrefix;

    auto layout = layoutList.current();

    // The `switch` below has bare, no-prefix,
    // no-underscore case labels ("ReturnButton", "FileBrowser", ...),
    // matching what `gui_main.d`'s `addWidget()`/`insertWidget()` sets
    // `Node.typeName` to when a widget is created via the "&New" menu
    // or widget palette. But `project_reader.d`'s real `.fl`-file
    // parser (`parseNode()`) sets `typeName` to the literal token read
    // from the file -- FLTK's actual `.fl` syntax, always
    // "Fl_"-prefixed *and* underscored ("Fl_Return_Button",
    // "Fl_Button", even "Fl_Box"), which wouldn't match any
    // `case` here directly (not even the single-word ones, since "Fl_Button" !=
    // "Button"), so without normalizing, *every* widget loaded from a saved `.fl` file would fall
    // through to the generic `120x100` default regardless of its real
    // type -- silently wrong ideal sizes, which would starve
    // `fluid.snap_action.SnapWidgetIdealWidth`/`Height`'s resize-hint
    // guides of a real target to snap to for any widget in a loaded
    // project. Normalizing through `code_writer.d`'s own established
    // `stripFlPrefix()` (already used there for the exact same
    // `Fl_Round_Button` -> `RoundButton` translation, generating D
    // class names) fixes both code paths at once, and also covers a
    // narrower case that would otherwise exist even for freshly-added widgets:
    // `ReturnButton`/`LightButton`/`CheckButton`/`RoundButton`/
    // `CheckBrowser`/`FileBrowser`/`FileInput`/`ValueOutput` already
    // matched correctly when added via the GUI, but would have quietly
    // gone back to wrong (120x100) sizing the moment that same project
    // was saved and reloaded.
    typeName = stripFlPrefix(typeName);

    switch (typeName)
    {
    case "Group": case "Tabs": case "Wizard":
    case "Pack": case "Scroll": case "Tile":
        w = 140; h = 140;
        break;

    case "Button":
        h = layout.labelsize + 8;
        w = layout.labelsize * 4 + 8;
        break;
    case "ReturnButton":
        h = layout.labelsize + 8;
        w = layout.labelsize * 4 + 8 + h; // room for the return-arrow symbol
        break;
    case "LightButton": case "CheckButton": case "RoundButton":
        h = layout.labelsize + 8;
        w = layout.labelsize * 4 + 8 + layout.labelsize; // room for the light/check/dot
        break;

    case "Browser": case "CheckBrowser": case "FileBrowser": case "Tree":
        w = 120; h = 160;
        break;
    case "HelpView": case "Table":
        w = 160; h = 120;
        break;

    case "Counter":
        h = layout.textsizeNotNull() + 8;
        w = layout.textsizeNotNull() * 4 + 4 * h; // room for the increment/decrement arrows
        break;
    case "Adjuster":
        h = layout.labelsize + 8;
        w = 3 * h;
        break;
    case "Dial":
        w = 60; h = 60;
        break;
    case "Roller":
        w = layout.labelsize + 8;
        h = 4 * w;
        break;
    case "ValueOutput":
        h = layout.textsizeNotNull() + 8;
        w = layout.textsizeNotNull() * 4 + 8;
        break;
    case "FileInput":
        h = layout.textsizeNotNull() + 8 + 10; // the directory bar adds 10px
        w = layout.textsizeNotNull() * 10 + 8;
        break;

    case "Box":
        w = 100; h = 100;
        break;
    case "Clock":
    case "ClockOutput":
        w = 80; h = 80;
        break;
    case "Progress":
        h = layout.labelsize + 8;
        w = layout.labelsize * 12;
        break;

    default:
        w = 120; h = 100; // Widget_Node's own generic default
        break;
    }

    betterSize(w, h);
}

/// The default label a newly-created widget of `typeName` should start
/// with -- ported from each FLTK `..._Node::widget()` factory
/// override's own literal label argument (`Fl_Button(x,y,w,h,"Button")`
/// and similar), found by grepping every `return new Fl_...(x, y, w,
/// h, "...")` call across the real `fluid/nodes/*.cxx` tree rather than
/// assumed. `gui_main.d`'s `insertWidget()` uses this to give a new
/// node a real default label per type, matching every entry in FLTK's
/// own table: `Button` family/
/// `Counter`/`ValueSlider`/`Box`/`Slider`/`ValueInput`/`ValueOutput`/`Input`/
/// `Output`/`Spinner`/`FileInput`/`Progress` all pass a literal
/// label. `File_Input`'s own
/// registry constructor (`instantiate.d`'s own `static this()`) already
/// had an inline "file:" fallback for the *live-widget* rendering, but
/// this function -- the *Node-level*, persisted-to-`.fl` default a
/// fresh `addWidget()` call seeds -- never had a matching entry, so a
/// freshly-dropped File_Input's label field itself stayed empty even
/// though the canvas happened to show "file:" anyway via that separate
/// fallback.
package(fluid) string defaultLabelFor(string typeName)
{
    import fluid.code_writer : stripFlPrefix;

    typeName = stripFlPrefix(typeName);
    switch (typeName)
    {
    case "Button": case "ReturnButton": case "RepeatButton":
    case "LightButton": case "CheckButton": case "RoundButton":
        return "Button";
    case "Slider": case "ValueSlider":
        return "slider:";
    case "ValueInput": case "ValueOutput":
        return "value:";
    case "Counter":
        return "counter:";
    case "Spinner":
        return "spinner:";
    case "Input":
        return "input:";
    case "Output":
        return "output:";
    case "FileInput":
        return "file:";
    case "Box": case "Progress":
        return "label";
    default:
        return "";
    }
}

unittest
{
    int w, h;
    idealSizeFor("Box", w, h);
    assert(w == 100 && h == 100);

    idealSizeFor("Dial", w, h);
    assert(w == 60 && h == 60);

    // Unknown/generic-default types (every type FLTK itself never
    // overrides ideal_size() for either).
    idealSizeFor("Slider", w, h);
    assert(w == 120 && h == 100);
    idealSizeFor("SomeTypeThatDoesNotExist", w, h);
    assert(w == 120 && h == 100);
}

unittest
{
    assert(defaultLabelFor("Button") == "Button");
    assert(defaultLabelFor("Fl_Return_Button") == "Button"); // .fl-file dialect, "Fl_"-prefixed+underscored
    assert(defaultLabelFor("RoundButton") == "Button");
    assert(defaultLabelFor("Counter") == "counter:");
    assert(defaultLabelFor("ValueSlider") == "slider:");
    assert(defaultLabelFor("Box") == "label");
    assert(defaultLabelFor("Group") == "");
    assert(defaultLabelFor("Input") == "input:");
    assert(defaultLabelFor("Output") == "output:");
    assert(defaultLabelFor("FileInput") == "file:");
    assert(defaultLabelFor("Slider") == "slider:");
    assert(defaultLabelFor("ValueInput") == "value:");
    assert(defaultLabelFor("ValueOutput") == "value:");
    assert(defaultLabelFor("Spinner") == "spinner:");
    assert(defaultLabelFor("Progress") == "label");
}

unittest
{
    // Regression coverage: `applyProperties()` must apply labelcolor/text font-size-color/
    // label margins/compact to the live widget, matching the Style
    // tab's own callbacks (e.g. `applyLabelColor()`), which write the
    // model field.
    FlGroup.current(null);

    auto wn = new WidgetNode();
    wn.typeName = "Fl_Input";
    wn.labelcolorRaw = cast(int) red;
    wn.textfont = cast(int) courier;
    wn.textsize = 18;
    wn.textcolorRaw = cast(int) blue;
    wn.hLabelMargin = 5;
    wn.vLabelMargin = 7;
    wn.imageSpacing = 3;

    auto w = instantiateOne(wn);
    assert(w.labelcolor() == red);
    auto in_ = cast(Input_) w;
    assert(in_ !is null);
    assert(in_.textfont() == courier);
    assert(in_.textsize() == 18);
    assert(in_.textcolor() == blue);
    assert(w.horizontalLabelMargin() == 5);
    assert(w.verticalLabelMargin() == 7);
    assert(w.labelImageSpacing() == 3);

    auto bn = new WidgetNode();
    bn.typeName = "Fl_Button";
    bn.compactRaw = "1";
    auto b = instantiateOne(bn);
    assert((cast(Button) b).compact());

    FlGroup.current(null);
}

unittest
{
    // Regression coverage for the `ValueOutput`/`ValueInput`/
    // `ValueSlider`/`Menu_` textfont/textsize/textcolor dispatch
    // (e.g. `samples/test/inactive.fl`'s `ValueOutput` sets `textfont 5
    // textsize 24 textcolor 4` in real, byte-identical-to-FLTK `.fl`
    // text, all of which must apply on the live canvas).
    FlGroup.current(null);

    auto von = new WidgetNode();
    von.typeName = "Fl_Value_Output";
    von.textfont = cast(int) courier;
    von.textsize = 24;
    von.textcolorRaw = cast(int) blue;
    auto vo = cast(ValueOutput) instantiateOne(von);
    assert(vo !is null);
    assert(vo.textfont() == courier);
    assert(vo.textsize() == 24);
    assert(vo.textcolor() == blue);

    auto vin_n = new WidgetNode();
    vin_n.typeName = "Fl_Value_Input";
    vin_n.textfont = cast(int) courier;
    vin_n.textsize = 18;
    vin_n.textcolorRaw = cast(int) red;
    auto vi = cast(ValueInput) instantiateOne(vin_n);
    assert(vi !is null);
    assert(vi.textfont() == courier);
    assert(vi.textsize() == 18);
    assert(vi.textcolor() == red);

    auto vsn = new WidgetNode();
    vsn.typeName = "Fl_Value_Slider";
    vsn.textfont = cast(int) courier;
    vsn.textsize = 12;
    vsn.textcolorRaw = cast(int) blue;
    auto vs = cast(ValueSlider) instantiateOne(vsn);
    assert(vs !is null);
    assert(vs.textfont() == courier);
    assert(vs.textsize() == 12);
    assert(vs.textcolor() == blue);

    auto mn = new WidgetNode();
    mn.typeName = "Fl_Choice";
    mn.textfont = cast(int) courier;
    mn.textsize = 16;
    mn.textcolorRaw = cast(int) red;
    auto m = cast(Menu_) instantiateOne(mn);
    assert(m !is null);
    assert(m.textfont() == courier);
    assert(m.textsize() == 16);
    assert(m.textcolor() == red);

    FlGroup.current(null);
}

unittest
{
    // Regression coverage: menu items must apply to
    // the live canvas.
    // A Choice populated the real, declarative way (literal MenuItem
    // {} children) must render its real menu on the canvas,
    // matching the same project's own generated D, which correctly builds
    // and applies the array via code_writer.d's writeMenuOwnerNode().
    FlGroup.current(null);

    auto cn = new WidgetNode();
    cn.typeName = "Choice";

    auto item1 = new MenuItemNode();
    item1.label = "First";
    item1.hasLabel = true;
    cn.addChild(item1);

    auto item2 = new MenuItemNode();
    item2.label = "Second";
    item2.hasLabel = true;
    item2.hotspotFlag = true; // reused as "divider" for a menu item
    cn.addChild(item2);

    auto item3 = new MenuItemNode();
    item3.label = "Third";
    item3.hasLabel = true;
    item3.headline_ = true;
    cn.addChild(item3);

    auto w = instantiateOne(cn);
    applyMenuItems(cn, w);
    auto choice = cast(Choice) w;
    assert(choice !is null);
    assert(choice.size() == 4); // 3 items + trailing sentinel
    assert(choice.text(0) == "First");
    assert(choice.text(1) == "Second");
    assert((choice.menu()[1].flags & menuDivider) != 0);
    assert(choice.text(2) == "Third");
    assert((choice.menu()[2].flags & menuHeadline) != 0);

    // A non-menu-owning widget (or one with no MenuItemNode children)
    // is a safe no-op, not a crash -- confirms applyMenuItems() doesn't
    // assume its caller already checked either precondition.
    auto bn2 = new WidgetNode();
    bn2.typeName = "Fl_Button";
    auto b2 = instantiateOne(bn2);
    applyMenuItems(bn2, b2); // no-op: not a Menu_

    auto emptyChoiceNode = new WidgetNode();
    emptyChoiceNode.typeName = "Choice";
    auto emptyChoice = instantiateOne(emptyChoiceNode);
    applyMenuItems(emptyChoiceNode, emptyChoice); // no-op: no MenuItemNode children
    assert((cast(Choice) emptyChoice).size() == 0);

    FlGroup.current(null);
}

unittest
{
    // Regression coverage: a nested Submenu -- including a genuinely empty one
    // -- and the two toggle-kind items all need to produce a real,
    // `validateMenuArray()`-clean `MenuItem[]`, not just parse without
    // throwing.
    FlGroup.current(null);

    auto cn = new WidgetNode();
    cn.typeName = "Choice";

    auto plain = new MenuItemNode();
    plain.label = "Plain";
    plain.hasLabel = true;
    cn.addChild(plain);

    auto sub = new SubmenuNode();
    sub.label = "Sub";
    sub.hasLabel = true;
    cn.addChild(sub);

    auto nested = new MenuItemNode();
    nested.label = "Nested";
    nested.hasLabel = true;
    sub.addChild(nested);

    // A second, genuinely empty Submenu -- must still close with its
    // own sentinel, not silently swallow the rest of the array.
    auto emptySub = new SubmenuNode();
    emptySub.label = "Empty";
    emptySub.hasLabel = true;
    cn.addChild(emptySub);

    auto check = new MenuItemNode();
    check.label = "Check";
    check.hasLabel = true;
    check.typeName = "CheckMenuItem";
    cn.addChild(check);

    auto radio = new MenuItemNode();
    radio.label = "Radio";
    radio.hasLabel = true;
    radio.typeName = "RadioMenuItem";
    cn.addChild(radio);

    auto w = instantiateOne(cn);
    applyMenuItems(cn, w);
    auto choice = cast(Choice) w;
    assert(choice !is null);

    // fl.menu_item's own array-length validation already ran inside
    // Menu_.menu() -- reaching this line at all confirms every submenu
    // level (including the empty one) got its closing sentinel.
    auto items = choice.menu(); // const(MenuItem)*, indexable but no .length
    assert(items[0].text == "Plain");
    assert(items[1].text == "Sub");
    assert((items[1].flags & menuSubmenu) != 0);
    assert(items[2].text == "Nested");
    assert(items[3].text is null); // closes "Sub"
    assert(items[4].text == "Empty");
    assert((items[4].flags & menuSubmenu) != 0);
    assert(items[5].text is null); // closes "Empty", even though it has no children
    assert(items[6].text == "Check");
    assert((items[6].flags & menuToggle) != 0);
    assert(items[7].text == "Radio");
    assert((items[7].flags & menuRadio) != 0);
    assert(items[8].text is null); // top-level sentinel

    FlGroup.current(null);
}

unittest
{
    // Regression coverage for the missing-sentinel case in
    // `fontMenuItems()`/`colorMenuItems()` -- exercises the
    // exact live-canvas call `widget_panel.d`'s own construction makes
    // (`instantiateOne()` -> `applyMenuItems()` -> `m.menu(fontMenuItems())`),
    // attaching the result to a live `Menu_` rather than only checking
    // generated *text*, which `code_writer.d`'s own tests for
    // `usesFontMenu`/`usesColorMenu` do.
    FlGroup.current(null);

    auto fn = new WidgetNode();
    fn.typeName = "Choice";
    fn.usesFontMenu = true;
    auto fw = cast(Choice) instantiateOne(fn);
    assert(fw !is null);
    assert(fw.size() == 17); // 16 fonts + sentinel

    auto cn2 = new WidgetNode();
    cn2.typeName = "Menu_Button";
    cn2.usesColorMenu = true;
    auto cw = cast(MenuButton) instantiateOne(cn2);
    assert(cw !is null);
    assert(cw.size() == 15); // 14 colors + sentinel

    FlGroup.current(null);
}
