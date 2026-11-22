// Going through a group's widgets: FlGroup.widgets lists the widgets a
// group holds itself, FlGroup.allWidgets every widget inside it, depth
// first. Both are plain arrays, so foreach and Phobos (filter, map,
// each) work on them. A widget's own parts, such as the Spinner's input
// and buttons or the Scroll's scrollbars, are not listed.
//
// Type in the inputs, tick some boxes, then press "Changed" to see which
// widgets were changed since the last time.
//
// Build: rdmd buildsamples.d examples howto_go_through_widgets
import fl;
import std.algorithm : each, filter, map;
import std.array : array, join;
import std.format : format;
import std.range : repeat;
import std.string : lastIndexOf;

FlGroup form;
Browser result;

// One line of the result: the widget's class and label, indented by how
// deep it is inside the form.
string describe(Widget w)
{
    string type = typeid(w).name;
    type = type[type.lastIndexOf('.') + 1 .. $];
    int depth = 0;
    for (auto p = w.parent(); p !is null && p !is form; p = p.parent())
        depth++;
    return format("%s%s \"%s\"", "    ".repeat(depth).join, type, w.label());
}

// What a widget holds, as text, or null for a widget without a value
// (a group). Each kind of widget has its own value(), so each is asked
// in its own type.
string valueText(Widget w)
{
    if (auto input = cast(Input) w) return format("\"%s\"", input.value());
    if (auto spinner = cast(Spinner) w) return format("%g", spinner.value());
    if (auto button = cast(Button) w) return button.value() ? "on" : "off";
    return null;
}

void show(string title, Widget[] list)
{
    result.clear();
    result.add(format("%s: %d", title, list.length));
    foreach (w; list)
        result.add(describe(w));
}

void main()
{
    auto window = new DoubleWindow(560, 400, "Going through widgets");

    form = new FlGroup(10, 10, 300, 330);
        new Input(90, 20, 200, 25, "Name:");
        new Input(90, 50, 200, 25, "Email:");
        new Spinner(90, 80, 70, 25, "Age:");
        new CheckButton(175, 80, 115, 25, "Newsletter");

        auto address = new FlGroup(20, 130, 280, 75, "Address");
        address.box(Boxtype.engravedFrame);
        address.alignment(alignTopLeft);
            new Input(90, 140, 200, 25, "Street:");
            new Input(90, 170, 200, 25, "City:");
        address.end();

        auto options = new Scroll(20, 230, 280, 100, "Options");
        options.box(Boxtype.downBox);
        options.alignment(alignTopLeft);
            foreach (i; 0 .. 6)
                new CheckButton(30, 235 + i * 25, 200, 25, format("Option %d", i + 1));
        options.end();
    form.end();

    result = new Browser(320, 30, 230, 310, "Result");
    result.alignment(alignTopLeft);

    auto listAll = new Button(10, 360, 85, 25, "List all");
    listAll.tooltip("form.allWidgets: every widget, depth first");
    listAll.callback((w) { show("form.allWidgets", form.allWidgets); });

    auto listOwn = new Button(101, 360, 85, 25, "List form");
    listOwn.tooltip("form.widgets: only the form's own widgets");
    listOwn.callback((w) { show("form.widgets", form.widgets); });

    auto values = new Button(192, 360, 85, 25, "Values");
    values.tooltip("What every widget with a value holds");
    values.callback((w) {
        result.clear();
        foreach (x; form.allWidgets)
            if (auto text = valueText(x))
                result.add(format("%s %s", x.label(), text));
    });

    auto changed = new Button(283, 360, 85, 25, "Changed");
    changed.tooltip("The widgets changed since the last press, then clears the mark");
    changed.callback((w) {
        show("Changed", form.allWidgets.filter!(x => x.changed).array);
        form.allWidgets.each!(x => x.clearChanged());
    });

    auto clearInputs = new Button(374, 360, 85, 25, "Clear inputs");
    clearInputs.tooltip("Empties every Input in the form");
    clearInputs.callback((w) {
        form.allWidgets
            .map!(x => cast(Input) x)
            .filter!(input => input !is null)
            .each!(input => input.value(""));
    });

    auto tickAll = new Button(465, 360, 85, 25, "Tick all");
    tickAll.tooltip("Ticks every CheckButton in the form");
    tickAll.callback((w) {
        foreach (x; form.allWidgets)
            if (auto box = cast(CheckButton) x)
                box.value(true);
    });

    window.end();
    window.show();
    run();
}
