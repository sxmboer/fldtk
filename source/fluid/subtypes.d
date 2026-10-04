/**
 * Per-widget-kind subtype tables: the values a widget's `type` property can
 * take, by kind. Ported from FLTK's `Widget_Node::subtypes()` and the
 * `*_type_menu[]` arrays it returns (`nodes/factory.cxx`, `Group_Node.cxx`,
 * `Button_Node.cxx`, `Menu_Node.cxx`).
 *
 * A subtype's `label` is both the text of the panel's Subtype choice and the
 * keyword a `.fl` file uses (`type {Vert Fill}`). `dName` is the D
 * expression generated code passes to `type()`, `value` the number the live
 * canvas widget gets. The value that a freshly constructed widget of the
 * kind already has (`SubtypeTable.defaultValue`) is never written to the
 * `.fl` file.
 *
 * The same keyword means different numbers for different kinds
 * (`VERTICAL` is 0 for a Pack or Flex, 2 for a Scroll; `Multiline` is 4 for
 * an Input, 12 for an Output), so every lookup goes through the widget's
 * kind. `code_writer.d` and `instantiate.d` keep flat keyword maps only as
 * a fallback for kinds without a table.
 *
 * Three kinds do not store the choice as a `type()` value. A window's
 * Single/Double picks the class (`Window` versus `DoubleWindow`), a menu
 * item's Normal/Toggle/Radio is its node kind (`MenuItem`/`CheckMenuItem`/
 * `RadioMenuItem` here), and a menu bar's `Fl_Sys_Menu_Bar` picks the class
 * `SysMenuBar`. Their tables carry a different `SubtypeStorage`, and
 * `subtypeIndex()`/`setSubtype()` hide the difference from the panel.
 */
module fluid.subtypes;

import fl;
import fluid.widget_node : WidgetNode;

/// One choice of a widget's `type`.
struct Subtype
{
    string label;
    string dName;
    ubyte value;
}

/// Where a kind keeps its subtype.
enum SubtypeStorage
{
    /// `WidgetNode.typeWord`, applied with `type()`.
    typeWord,
    /// `WidgetNode.typeWord` is `Double` for a `DoubleWindow`.
    windowClass,
    /// `WidgetNode.typeName` is one of `MenuItem`/`CheckMenuItem`/`RadioMenuItem`.
    menuItemKind,
    /// `WidgetNode.typeWord` is `Fl_Sys_Menu_Bar` for a `SysMenuBar`.
    menuBarClass,
}

/// The subtypes of one widget kind, in menu order.
struct SubtypeTable
{
    immutable(Subtype)[] items;
    /// `type()` of a newly constructed widget of this kind.
    ubyte defaultValue;
    SubtypeStorage storage = SubtypeStorage.typeWord;

    /// The item whose `label` is `word`, or null.
    const(Subtype)* find(string word) const
    {
        foreach (ref it; items)
            if (it.label == word)
                return &it;
        return null;
    }

    /// Index of the item with `value`, or the default's index.
    size_t indexOf(ubyte v) const
    {
        foreach (i, ref it; items)
            if (it.value == v)
                return i;
        foreach (i, ref it; items)
            if (it.value == defaultValue)
                return i;
        return 0;
    }
}

/// `typeName` as written in a `.fl` file (`Fl_Return_Button`, `ReturnButton`)
/// reduced to the D class name (`ReturnButton`).
private string kindOf(string typeName)
{
    string s = typeName.length > 3 && typeName[0 .. 3] == "Fl_" ? typeName[3 .. $] : typeName;
    string r;
    foreach (c; s)
        if (c != '_')
            r ~= c;
    return r;
}

private immutable SubtypeTable buttonTable = SubtypeTable([
    Subtype("Normal", "normalButton", normalButton),
    Subtype("Toggle", "toggleButton", toggleButton),
    Subtype("Radio", "radioButton", radioButton),
], normalButton);

private immutable SubtypeTable packTable = SubtypeTable([
    Subtype("HORIZONTAL", "packHorizontal", packHorizontal),
    Subtype("VERTICAL", "packVertical", packVertical),
], packVertical);

private immutable SubtypeTable flexTable = SubtypeTable([
    Subtype("HORIZONTAL", "flexHorizontal", flexHorizontal),
    Subtype("VERTICAL", "flexVertical", flexVertical),
], flexVertical);

private immutable SubtypeTable scrollTable = SubtypeTable([
    Subtype("BOTH", "scrollBoth", scrollBoth),
    Subtype("HORIZONTAL", "scrollHorizontal", scrollHorizontal),
    Subtype("VERTICAL", "scrollVertical", scrollVertical),
    Subtype("HORIZONTAL_ALWAYS", "scrollHorizontalAlways", scrollHorizontalAlways),
    Subtype("VERTICAL_ALWAYS", "scrollVerticalAlways", scrollVerticalAlways),
    Subtype("BOTH_ALWAYS", "scrollBothAlways", scrollBothAlways),
], scrollBoth);

private immutable SubtypeTable sliderTable = SubtypeTable([
    Subtype("Vertical", "vertSlider", vertSlider),
    Subtype("Horizontal", "horizontalType", horSlider),
    Subtype("Vert Fill", "vertFillSlider", vertFillSlider),
    Subtype("Horz Fill", "horFillSlider", horFillSlider),
    Subtype("Vert Knob", "vertNiceSlider", vertNiceSlider),
    Subtype("Horz Knob", "horNiceSlider", horNiceSlider),
], vertSlider);

private immutable SubtypeTable orientationTable = SubtypeTable([
    Subtype("Vertical", "vertSlider", vertSlider),
    Subtype("Horizontal", "horizontalType", horSlider),
], vertSlider);

private immutable SubtypeTable inputTable = SubtypeTable([
    Subtype("Normal", "inputNormal", inputNormal),
    Subtype("Multiline", "inputMultiline", inputMultiline),
    Subtype("Secret", "inputSecret", inputSecret),
    Subtype("Int", "inputInt", inputInt),
    Subtype("Float", "inputFloat", inputFloat),
], inputNormal);

private immutable SubtypeTable outputTable = SubtypeTable([
    Subtype("Normal", "outputNormal", outputNormal),
    Subtype("Multiline", "outputMultiline", outputMultiline),
], outputNormal);

private immutable SubtypeTable spinnerTable = SubtypeTable([
    Subtype("Integer", "inputInt", inputInt),
    Subtype("Float", "inputFloat", inputFloat),
], inputInt);

private immutable SubtypeTable counterTable = SubtypeTable([
    Subtype("Normal", "normalCounter", normalCounter),
    Subtype("Simple", "simpleCounter", simpleCounter),
], normalCounter);

private immutable SubtypeTable dialTable = SubtypeTable([
    Subtype("Dot", "normalDial", normalDial),
    Subtype("Line", "lineDial", lineDial),
    Subtype("Fill", "fillDial", fillDial),
], normalDial);

private immutable SubtypeTable browserTable = SubtypeTable([
    Subtype("No Select", "normalBrowser", normalBrowser),
    Subtype("Select", "selectBrowser", selectBrowser),
    Subtype("Hold", "holdBrowser", holdBrowser),
    Subtype("Multi", "multiBrowser", multiBrowser),
], normalBrowser);

private immutable SubtypeTable menuButtonTable = SubtypeTable([
    Subtype("normal", "0", 0),
    Subtype("popup1", "MenuButton.PopupButtons.popup1", MenuButton.PopupButtons.popup1),
    Subtype("popup2", "MenuButton.PopupButtons.popup2", MenuButton.PopupButtons.popup2),
    Subtype("popup3", "MenuButton.PopupButtons.popup3", MenuButton.PopupButtons.popup3),
    Subtype("popup12", "MenuButton.PopupButtons.popup12", MenuButton.PopupButtons.popup12),
    Subtype("popup23", "MenuButton.PopupButtons.popup23", MenuButton.PopupButtons.popup23),
    Subtype("popup13", "MenuButton.PopupButtons.popup13", MenuButton.PopupButtons.popup13),
    Subtype("popup123", "MenuButton.PopupButtons.popup123", MenuButton.PopupButtons.popup123),
], 0);

private immutable SubtypeTable windowTable = SubtypeTable([
    Subtype("Single", "Window", 0),
    Subtype("Double", "DoubleWindow", 1),
], 0, SubtypeStorage.windowClass);

private immutable SubtypeTable menuItemTable = SubtypeTable([
    Subtype("Normal", "MenuItem", 0),
    Subtype("Toggle", "CheckMenuItem", 1),
    Subtype("Radio", "RadioMenuItem", 2),
], 0, SubtypeStorage.menuItemKind);

private immutable SubtypeTable menuBarTable = SubtypeTable([
    Subtype("Fl_Menu_Bar", "MenuBar", 0),
    Subtype("Fl_Sys_Menu_Bar", "SysMenuBar", 1),
], 0, SubtypeStorage.menuBarClass);

/// The subtype table for a widget kind, or null if the kind has none.
/// Kinds that share a table return the same pointer, which is how the
/// panel tells which selected widgets a subtype choice applies to (FLTK
/// compares `subtypes()` pointers the same way).
const(SubtypeTable)* subtypesFor(string typeName)
{
    switch (kindOf(typeName))
    {
    case "Button": case "ReturnButton": case "RepeatButton":
    case "LightButton": case "CheckButton": case "RoundButton":
        return &buttonTable;
    case "Pack": return &packTable;
    case "Flex": return &flexTable;
    case "Scroll": return &scrollTable;
    case "Slider": case "ValueSlider": return &sliderTable;
    case "Scrollbar": case "Roller": return &orientationTable;
    case "Input": return &inputTable;
    case "Output": return &outputTable;
    case "Spinner": return &spinnerTable;
    case "Counter": return &counterTable;
    case "Dial": return &dialTable;
    case "Browser": return &browserTable;
    case "MenuButton": return &menuButtonTable;
    case "Window": case "DoubleWindow": return &windowTable;
    case "MenuItem": case "CheckMenuItem": case "RadioMenuItem": return &menuItemTable;
    case "MenuBar": return &menuBarTable;
    default: return null;
    }
}

/// The subtype a node's `type` keyword names, or null if the kind has no
/// table, the table does not keep its subtype as a `type()` value, or the
/// keyword is not in it.
const(Subtype)* subtypeFor(string typeName, string word)
{
    auto table = subtypesFor(typeName);
    if (table is null || table.storage != SubtypeStorage.typeWord)
        return null;
    return table.find(word);
}

/// Whether `typeName`'s `type` keyword picks the class rather than being a
/// `type()` value; such a keyword must not be emitted as a `type()` call.
bool subtypePicksClass(string typeName)
{
    auto table = subtypesFor(typeName);
    return table !is null && table.storage != SubtypeStorage.typeWord
        && table.storage != SubtypeStorage.menuItemKind;
}

/// Whether a `WindowNode`-kind node generates a `DoubleWindow`.
bool isDoubleWindow(string typeName, string typeWord)
{
    return typeWord == "Double" || kindOf(typeName) == "DoubleWindow";
}

/// Index into `table.items` of `n`'s current subtype.
size_t subtypeIndex(WidgetNode n, const(SubtypeTable)* table)
{
    final switch (table.storage)
    {
    case SubtypeStorage.typeWord:
        auto named = table.find(n.typeWord);
        return table.indexOf(named !is null ? named.value : table.defaultValue);
    case SubtypeStorage.windowClass:
        return isDoubleWindow(n.typeName, n.typeWord) ? 1 : 0;
    case SubtypeStorage.menuItemKind:
        foreach (i, ref it; table.items)
            if (it.dName == kindOf(n.typeName))
                return i;
        return 0;
    case SubtypeStorage.menuBarClass:
        return n.typeWord == "Fl_Sys_Menu_Bar" ? 1 : 0;
    }
}

/// Makes item `index` of `table` the subtype of `n`, in the model only. A
/// value equal to the kind's default is stored as no `type` keyword at all.
void setSubtype(WidgetNode n, const(SubtypeTable)* table, size_t index)
{
    auto item = table.items[index];
    final switch (table.storage)
    {
    case SubtypeStorage.typeWord:
        n.typeWord = item.value == table.defaultValue ? "" : item.label;
        break;
    case SubtypeStorage.windowClass:
        n.typeWord = index == 1 ? "Double" : "";
        // `Fl_Double_Window` names the double class itself.
        if (index == 0 && kindOf(n.typeName) == "DoubleWindow")
            n.typeName = n.typeName.length > 3 && n.typeName[0 .. 3] == "Fl_" ? "Fl_Window" : "Window";
        break;
    case SubtypeStorage.menuItemKind:
        n.typeName = item.dName;
        break;
    case SubtypeStorage.menuBarClass:
        n.typeWord = index == 1 ? "Fl_Sys_Menu_Bar" : "";
        break;
    }
}

unittest
{
    // Kinds sharing a menu share the table; the same keyword resolves per kind.
    assert(subtypesFor("Fl_Button") is subtypesFor("Fl_Return_Button"));
    assert(subtypesFor("Fl_Slider") is subtypesFor("ValueSlider"));
    assert(subtypesFor("Fl_Box") is null);
    assert(subtypeFor("Fl_Scroll", "VERTICAL").value == scrollVertical);
    assert(subtypeFor("Fl_Pack", "VERTICAL").value == packVertical);
    assert(subtypeFor("Fl_Input", "Multiline").value == inputMultiline);
    assert(subtypeFor("Fl_Output", "Multiline").value == outputMultiline);
    assert(subtypeFor("Fl_Input", "Vert Fill") is null);
    assert(subtypeFor("Fl_Slider", "Vert Fill").dName == "vertFillSlider");

    // Kinds that keep the subtype somewhere other than `type()`.
    assert(subtypeFor("Fl_Window", "Double") is null);
    auto win = new WidgetNode();
    win.typeName = "Fl_Double_Window";
    auto wt = subtypesFor(win.typeName);
    assert(wt is subtypesFor("Fl_Window") && subtypesFor("widget_class") is null);
    assert(subtypeIndex(win, wt) == 1 && isDoubleWindow("Fl_Window", "Double"));
    setSubtype(win, wt, 0);
    assert(win.typeName == "Fl_Window" && win.typeWord == "" && subtypeIndex(win, wt) == 0);
    setSubtype(win, wt, 1);
    assert(win.typeWord == "Double" && subtypeIndex(win, wt) == 1);

    auto item = new WidgetNode();
    item.typeName = "MenuItem";
    auto mt = subtypesFor("MenuItem");
    assert(mt is subtypesFor("CheckMenuItem") && mt is subtypesFor("RadioMenuItem"));
    setSubtype(item, mt, 2);
    assert(item.typeName == "RadioMenuItem" && subtypeIndex(item, mt) == 2);
    setSubtype(item, mt, 0);
    assert(item.typeName == "MenuItem" && subtypeIndex(item, mt) == 0);

    auto bar = new WidgetNode();
    bar.typeName = "Fl_Menu_Bar";
    auto bt = subtypesFor("Fl_Menu_Bar");
    setSubtype(bar, bt, 1);
    assert(bar.typeWord == "Fl_Sys_Menu_Bar" && subtypeIndex(bar, bt) == 1);
    setSubtype(bar, bt, 0);
    assert(bar.typeWord == "" && subtypePicksClass("Fl_Menu_Bar") && !subtypePicksClass("Fl_Button"));

    // Every table's default value is one of its items, and lookups by
    // value find the item.
    foreach (name; ["Button", "Pack", "Flex", "Scroll", "Slider", "Scrollbar", "Input", "Output",
        "Spinner", "Counter", "Dial", "Browser", "MenuButton"])
    {
        auto t = subtypesFor(name);
        assert(t !is null, name);
        bool hasDefault;
        foreach (i, it; t.items)
        {
            assert(t.indexOf(it.value) == i, name);
            if (it.value == t.defaultValue) hasDefault = true;
        }
        assert(hasDefault, name);
    }
}
