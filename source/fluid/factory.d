/*
 * `.fl` Type-keyword -> D node constructor dispatch, mirroring
 * FLTK's prototype-registry factory (`fluid/nodes/factory.cxx`,
 * ~164 registered widget types there). Every plain widget type is
 * registered under *both* spellings -- FLTK's own `Fl_Foo` (kept
 * for tolerance of old-dialect/legacy `.fl` files) and the fldtk-native
 * dialect's bare `Foo` (matching this project's real D class names
 * directly, no "Fl_" prefix -- see `FLUID_DIALECT.md`'s "dialect pivot"
 * section) -- both resolve to the exact same node class, so nothing
 * downstream needs to care which spelling a given `.fl` file uses.
 */
module fluid.factory;

import fluid.node;
import fluid.widget_node;
import fluid.window_node;
import fluid.widget_class_node;
import fluid.group_node;
import fluid.function_node;
import fluid.code_node;
import fluid.class_node;
import fluid.menu_item_node;
import fluid.menu_owner_node;
import fluid.decl_node;
import fluid.decl_block_node;
import fluid.data_node;
import fluid.code_block_node;
import fluid.comment_node;
import fluid.grid_node;
import fluid.flex_node;

private Node delegate()[string] registry;

/// Registers both `"Fl_" ~ bareName` and `bareName` itself against the
/// same constructor -- the common case for every plain widget type.
private void reg(string bareName, Node delegate() ctor)
{
    registry["Fl_" ~ bareName] = ctor;
    registry[bareName] = ctor;
}

static this()
{
    registry["Function"] = () => cast(Node) new FunctionNode();
    registry["code"] = () => cast(Node) new CodeNode();
    registry["codeblock"] = () => cast(Node) new CodeBlockNode();
    registry["class"] = () => cast(Node) new ClassNode();
    registry["comment"] = () => cast(Node) new CommentNode();
    registry["decl"] = () => cast(Node) new DeclNode();
    registry["declblock"] = () => cast(Node) new DeclBlockNode();
    registry["data"] = () => cast(Node) new DataNode();
    registry["MenuItem"] = () => cast(Node) new MenuItemNode();
    // `CheckMenuItem`/`RadioMenuItem` are plain `MenuItemNode`s -- see
    // that class's own doc comment for why no dedicated D subclass is
    // needed (typeName alone tells them apart). `Submenu` genuinely does
    // need its own class (`canHaveChildren() == true`).
    registry["CheckMenuItem"] = () => cast(Node) new MenuItemNode();
    registry["RadioMenuItem"] = () => cast(Node) new MenuItemNode();
    registry["Submenu"] = () => cast(Node) new SubmenuNode();
    registry["widget_class"] = () => cast(Node) new WidgetClassNode();

    reg("Window", () => cast(Node) new WindowNode());
    reg("Double_Window", () => cast(Node) new WindowNode());
    registry["DoubleWindow"] = () => cast(Node) new WindowNode();
    reg("Group", () => cast(Node) new GroupNode());
    // Both effectively GroupNode-shaped -- a plain container plus
    // children, no properties/codegen of their own beyond what every
    // container already gets (confirmed while actually porting tabs.fl).
    reg("Tabs", () => cast(Node) new GroupNode());
    reg("Wizard", () => cast(Node) new GroupNode());
    reg("Grid", () => cast(Node) new GridNode());
    reg("Flex", () => cast(Node) new FlexNode());
    reg("Pack", () => cast(Node) new GroupNode());
    reg("Scroll", () => cast(Node) new GroupNode());
    reg("Tile", () => cast(Node) new GroupNode());

    reg("Slider", () => cast(Node) new WidgetNode());
    reg("Box", () => cast(Node) new WidgetNode());
    reg("Button", () => cast(Node) new WidgetNode());
    reg("Return_Button", () => cast(Node) new WidgetNode());
    registry["ReturnButton"] = () => cast(Node) new WidgetNode();
    reg("Light_Button", () => cast(Node) new WidgetNode());
    registry["LightButton"] = () => cast(Node) new WidgetNode();
    reg("Check_Button", () => cast(Node) new WidgetNode());
    registry["CheckButton"] = () => cast(Node) new WidgetNode();
    reg("Round_Button", () => cast(Node) new WidgetNode());
    registry["RoundButton"] = () => cast(Node) new WidgetNode();
    // `Fl_Shortcut_Button` -- FLTK's own key-combination-capturing
    // button (already ported, `fl.shortcut_button.ShortcutButton`),
    // needed by the Settings dialog's own Shell-tab shortcut field
    // (`fluid/panels/settings_panel.fl`).
    reg("Shortcut_Button", () => cast(Node) new WidgetNode());
    registry["ShortcutButton"] = () => cast(Node) new WidgetNode();
    reg("Repeat_Button", () => cast(Node) new WidgetNode());
    registry["RepeatButton"] = () => cast(Node) new WidgetNode();
    reg("Output", () => cast(Node) new WidgetNode());
    reg("Input", () => cast(Node) new WidgetNode());
    // Fl_Float_Input/Fl_Int_Input are real, distinct FLTK widget
    // classes (confirmed: source/fl/float_input.d's `class FloatInput :
    // Input`) -- FLTK's own .fl grammar spells these as plain
    // "Fl_Input { ... type Float }"/"type Int" (a "type" keyword that
    // selects a different concrete class entirely, the same shape as a
    // Window's "type Double" selecting DoubleWindow), but the fldtk
    // dialect just names the class directly instead, matching every
    // other type name here and avoiding a second special case in
    // className() to match Window's -- write "FloatInput x_input { ... }"
    // in .fl text, not "Input x_input { ... type Float }".
    reg("Float_Input", () => cast(Node) new WidgetNode());
    registry["FloatInput"] = () => cast(Node) new WidgetNode();
    reg("Int_Input", () => cast(Node) new WidgetNode());
    registry["IntInput"] = () => cast(Node) new WidgetNode();
    reg("Value_Output", () => cast(Node) new WidgetNode());
    registry["ValueOutput"] = () => cast(Node) new WidgetNode();
    reg("Value_Slider", () => cast(Node) new WidgetNode());
    registry["ValueSlider"] = () => cast(Node) new WidgetNode();
    reg("Value_Input", () => cast(Node) new WidgetNode());
    registry["ValueInput"] = () => cast(Node) new WidgetNode();
    reg("Scrollbar", () => cast(Node) new WidgetNode());
    reg("Roller", () => cast(Node) new WidgetNode());
    reg("Dial", () => cast(Node) new WidgetNode());
    reg("Clock", () => cast(Node) new WidgetNode());
    // Not FLTK -- neither FLTK's own Fluid palette nor this port's
    // had a way to place a static (non-ticking) `Fl_Clock_Output`
    // directly; both only ever offered `Fl_Clock`. Added at the user's
    // own explicit request after asking about the two classes' real
    // difference (`fl.clock.ClockOutput`/`FlClock`'s own doc comment).
    reg("Clock_Output", () => cast(Node) new WidgetNode());
    registry["ClockOutput"] = () => cast(Node) new WidgetNode();
    reg("Adjuster", () => cast(Node) new WidgetNode());
    reg("Counter", () => cast(Node) new WidgetNode());
    reg("Spinner", () => cast(Node) new WidgetNode());
    reg("Terminal", () => cast(Node) new WidgetNode());
    reg("Browser", () => cast(Node) new WidgetNode());
    reg("TextDisplay", () => cast(Node) new WidgetNode());
    // `Fl_Text_Editor` -- needed by the Settings dialog's own Shell-tab
    // command editor and its "zoom" Script Editor dialog
    // (`fluid/panels/settings_panel.fl`); `fl.text_editor.TextEditor`
    // itself was already real, just never registered for `.fl` parsing.
    reg("Text_Editor", () => cast(Node) new WidgetNode());
    registry["TextEditor"] = () => cast(Node) new WidgetNode();
    reg("File_Input", () => cast(Node) new WidgetNode());
    registry["FileInput"] = () => cast(Node) new WidgetNode();
    // Fl_Tree/Fl_Help_View/Fl_Table are Fl_Group subclasses in C++, but
    // FLUID itself treats them as leaf Widget_Type nodes -- their own
    // FLTK source comments say so explicitly ("FLUID does not
    // support extended Fl_Tree"/"Fl_Help_View is derived from Fl_Group,
    // but supporting children is not useful"), and this port's own
    // fl.tree.Tree/fl.help_view.HelpView/fl.table.Table constructors all
    // already call end() internally (matching Fl_Text_Display's own
    // FLTK pattern), so registering them as a plain WidgetNode here
    // -- not GroupNode -- needs no extra Group.current() bookkeeping.
    // Table's FLTK Table_Node does support real widget children via
    // its own specialized add_child()/move_child() overrides; that's a
    // separate, bigger mechanism this port doesn't have yet, so Table's
    // own widget-in-cell support stays deferred, same as Tree/Help_View.
    reg("Tree", () => cast(Node) new WidgetNode());
    reg("Help_View", () => cast(Node) new WidgetNode());
    registry["HelpView"] = () => cast(Node) new WidgetNode();
    reg("Check_Browser", () => cast(Node) new WidgetNode());
    registry["CheckBrowser"] = () => cast(Node) new WidgetNode();
    reg("File_Browser", () => cast(Node) new WidgetNode());
    registry["FileBrowser"] = () => cast(Node) new WidgetNode();
    reg("Table", () => cast(Node) new WidgetNode());
    reg("Progress", () => cast(Node) new WidgetNode());

    reg("Menu_Button", () => cast(Node) new MenuOwnerNode());
    registry["MenuButton"] = () => cast(Node) new MenuOwnerNode();
    reg("Choice", () => cast(Node) new MenuOwnerNode());
    // `Menu_Bar_Node`/`Input_Choice_Node` (FLTK's `nodes/Menu_Node.h`)
    // -- both, like `Menu_Button_Node`/`Choice_Node` just above, are
    // concrete subclasses of FLTK's abstract `Menu_Manager_Node`
    // (a "widget that owns a menu, can have MenuItem children" role
    // this port's own `MenuOwnerNode` already covers generically, not
    // ported as its own separate node class -- there's nothing
    // `Menu_Manager_Node` itself does beyond that role that a fourth
    // concrete registry entry needed anything new for).
    reg("Menu_Bar", () => cast(Node) new MenuOwnerNode());
    registry["MenuBar"] = () => cast(Node) new MenuOwnerNode();
    reg("Input_Choice", () => cast(Node) new MenuOwnerNode());
    registry["InputChoice"] = () => cast(Node) new MenuOwnerNode();
}

Node createNode(string typeName)
{
    auto ctor = typeName in registry;
    if (ctor is null)
        throw new Exception("fluid: unknown .fl type \"" ~ typeName ~ "\" -- not yet in factory.d's registry");
    return (*ctor)();
}
