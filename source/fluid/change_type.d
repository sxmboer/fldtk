/*
 * Changing a widget into another kind of widget in place: an Output into
 * a Value Output, a Button into a Check Button, a Group into a Tabs. The
 * widget keeps its place in the tree, its geometry, label, name,
 * callback, tooltip, colors and every other property the new kind also
 * has; properties the new kind does not have are cleared, so the
 * generated code never calls a method the new class lacks.
 *
 * A widget can change into another kind of the same family (`families`):
 * text fields and number widgets (one family, so a text field can become a
 * number display and back), buttons, menus, and containers. Flex and Grid
 * are not in the container family: their children carry layout data of
 * their own that a plain group has no place for.
 *
 * `gui_main.d` offers the change in three places: the project tree's
 * right-click menu, the canvas's right-click menu on a selected widget,
 * and the "Change to:" choice on the Style tab of the Widget Properties
 * panel. All three call `changeType()` here.
 */
module fluid.change_type;

import fluid.node : Node;
import fluid.widget_node : WidgetNode;
import fluid.subtypes : subtypeFor;

/// The kinds of widget a widget can change between, by family. Each
/// family lists its kinds in the order the menus show them.
private immutable string[][] families = [
    // Text fields first, then number widgets.
    ["Input", "FloatInput", "IntInput", "FileInput", "Output",
     "ValueOutput", "ValueInput", "Spinner", "Counter", "Slider",
     "ValueSlider", "Dial", "Roller", "Adjuster", "Scrollbar"],
    ["Button", "ReturnButton", "RepeatButton", "LightButton",
     "CheckButton", "RoundButton"],
    ["MenuBar", "MenuButton", "Choice"],
    ["Group", "Pack", "Scroll", "Tabs", "Tile", "Wizard"],
];

private immutable string[] textKinds = ["Input", "FloatInput", "IntInput", "FileInput", "Output"];
private immutable string[] numberKinds = ["ValueOutput", "ValueInput", "Spinner", "Counter",
    "Slider", "ValueSlider", "Dial", "Roller", "Adjuster", "Scrollbar"];
private immutable string[] buttonKinds = ["Button", "ReturnButton", "RepeatButton",
    "LightButton", "CheckButton", "RoundButton"];
private immutable string[] menuKinds = ["MenuBar", "MenuButton", "Choice"];

/// `typeName` as written in a `.fl` file (`Fl_Value_Output`,
/// `ValueOutput`) reduced to the D class name (`ValueOutput`).
string kindName(string typeName)
{
    string s = typeName.length > 3 && typeName[0 .. 3] == "Fl_" ? typeName[3 .. $] : typeName;
    string r;
    foreach (c; s)
        if (c != '_')
            r ~= c;
    return r;
}

/// The kind as the menus show it: `ValueOutput` -> "Value Output".
string displayName(string kind)
{
    string r;
    foreach (i, c; kind)
    {
        if (i > 0 && c >= 'A' && c <= 'Z')
            r ~= ' ';
        r ~= c;
    }
    return r;
}

private bool among(string kind, const string[] list)
{
    foreach (k; list)
        if (k == kind) return true;
    return false;
}

/// The kinds `n` can change into, its own kind included (so a menu can
/// mark the current one), or an empty list when `n` can't change kind.
string[] changeTargets(Node n)
{
    import fluid.flex_node : FlexNode;
    import fluid.grid_node : GridNode;

    auto wn = cast(WidgetNode) n;
    if (wn is null || cast(FlexNode) n || cast(GridNode) n)
        return [];
    string kind = kindName(n.typeName);
    foreach (family; families)
        if (kind.among(family))
            return family.dup;
    return [];
}

/// Whether every node in `nodes` can change into `kind` (and at least one
/// of them isn't that kind already).
bool canChangeAll(Node[] nodes, string kind)
{
    bool any;
    foreach (n; nodes)
    {
        if (!kind.among(changeTargets(n))) return false;
        if (kindName(n.typeName) != kind) any = true;
    }
    return any;
}

/// Changes `n` into a widget of `kind` (a D class name such as
/// "ValueOutput"), keeping every property the new kind also has and
/// clearing the rest. The caller rebuilds the live widget and records the
/// undo step. Returns false, changing nothing, when `n` can't become `kind`.
bool changeType(WidgetNode n, string kind)
{
    import fluid.instantiate : defaultLabelFor;

    if (!kind.among(changeTargets(n)))
        return false;
    string old = kindName(n.typeName);
    if (old == kind)
        return false;

    // A label still at the old kind's starting text ("output:") gets the
    // new kind's ("value:").
    if (n.hasLabel && n.label == defaultLabelFor(old))
    {
        n.label = defaultLabelFor(kind);
        n.hasLabel = n.label.length > 0;
    }

    // The value only means the same thing within text fields, number
    // widgets or buttons: "12.5" is no button state.
    bool sameValueKind = (old.among(textKinds) && kind.among(textKinds))
        || (old.among(numberKinds) && kind.among(numberKinds))
        || (old.among(buttonKinds) && kind.among(buttonKinds));
    if (!sameValueKind)
    {
        n.valueRaw = null;
        n.hasValue = false;
    }

    if (!kind.among(numberKinds))
    {
        n.minimumRaw = n.maximumRaw = n.stepRaw = null;
        n.hasMinimum = n.hasMaximum = n.hasStep = false;
    }
    if (!kind.among(["Slider", "ValueSlider", "Scrollbar"]))
    {
        n.sliderSizeRaw = null;
        n.hasSliderSize = false;
    }
    // Text font, size and color: text fields, the number widgets that
    // show their value as text, and menus.
    if (!kind.among(textKinds) && !kind.among(menuKinds)
        && !kind.among(["ValueOutput", "ValueInput", "ValueSlider", "Spinner", "Counter"]))
    {
        n.textfont = n.textsize = n.textcolorRaw = -1;
    }
    if (!kind.among(buttonKinds) && !kind.among(menuKinds))
    {
        n.downBoxtype = null;
        n.hasDownBoxtype = false;
    }
    if (!kind.among(buttonKinds) && !kind.among(textKinds) && kind != "ValueInput")
    {
        n.shortcutRaw = null;
        n.hasShortcut = false;
    }
    if (!kind.among(buttonKinds))
    {
        n.compactRaw = null;
        n.hasCompact = false;
    }
    if (!kind.among(menuKinds))
        n.usesFontMenu = n.usesColorMenu = false;
    // A subtype keyword survives only if the new kind has the same one
    // (a horizontal Slider stays horizontal as a Value Slider).
    if (n.typeWord.length && subtypeFor(kind, n.typeWord) is null)
        n.typeWord = null;
    // A class override names a class derived from the old kind.
    n.classOverride = null;
    n.hasClassOverride = false;

    n.typeName = kind;
    return true;
}

unittest
{
    auto o = new WidgetNode();
    o.typeName = "Output";
    o.instanceName = "total";
    o.label = "Total";
    o.hasLabel = true;
    o.textsize = 14;
    o.tooltip = "The sum";
    o.callback = "calculate();";

    assert(changeTargets(o).length > 0);
    assert(changeType(o, "ValueOutput"));
    assert(o.typeName == "ValueOutput");
    assert(o.instanceName == "total" && o.label == "Total");
    assert(o.textsize == 14 && o.tooltip == "The sum" && o.callback == "calculate();");

    // A number widget's range does not carry over to a text field, nor
    // its value; a default label follows the kind.
    auto s = new WidgetNode();
    s.typeName = "Fl_Spinner";
    s.label = "spinner:";
    s.hasLabel = true;
    s.minimumRaw = "1"; s.hasMinimum = true;
    s.valueRaw = "2"; s.hasValue = true;
    s.typeWord = "Float";
    assert(changeType(s, "ValueSlider"));
    assert(s.hasMinimum && s.hasValue);
    assert(s.label == "slider:");
    assert(s.typeWord.length == 0); // a Value Slider has no Float subtype
    assert(changeType(s, "Input"));
    assert(!s.hasMinimum && !s.hasValue);
    assert(s.label == "input:");

    // A slider's orientation survives within the sliders.
    auto sl = new WidgetNode();
    sl.typeName = "Slider";
    sl.typeWord = "Horizontal";
    sl.sliderSizeRaw = "0.2"; sl.hasSliderSize = true;
    assert(changeType(sl, "ValueSlider"));
    assert(sl.typeWord == "Horizontal" && sl.hasSliderSize);
    assert(changeType(sl, "Dial"));
    assert(!sl.hasSliderSize);

    // Buttons keep their state and shortcut among themselves.
    auto b = new WidgetNode();
    b.typeName = "Button";
    b.valueRaw = "1"; b.hasValue = true;
    b.shortcutRaw = "0x31"; b.hasShortcut = true;
    b.typeWord = "Toggle";
    assert(changeType(b, "CheckButton"));
    assert(b.hasValue && b.hasShortcut && b.typeWord == "Toggle");

    // No kind outside the family, and no change to the same kind.
    assert(!changeType(b, "Group"));
    assert(!changeType(b, "CheckButton"));
    auto box = new WidgetNode();
    box.typeName = "Box";
    assert(changeTargets(box).length == 0);

    assert(displayName("ValueOutput") == "Value Output");
    assert(kindName("Fl_Value_Output") == "ValueOutput");
}
