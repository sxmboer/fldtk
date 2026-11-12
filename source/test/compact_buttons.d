// fldtk test program: buttons joined into bars with compact().
// Build: rdmd buildsamples.d test compact_buttons
//
// Each row is one group whose buttons all have compact(true), so they
// draw as a single bar with short dividers between them. One row per
// button kind that has a frame to join, and a last row that mixes kinds.
// Each light and return arrow stays inside its own part of the bar.
// Change the scheme to see the bars in every box style.
import fl;

FlGroup bar(int y, string title)
{
    new Box(10, y, 120, 30, title).alignment(alignLeft | alignInside);
    return new FlGroup(140, y, 360, 30);
}

void join(FlGroup g)
{
    foreach (i; 0 .. g.children())
        if (auto b = cast(Button) g.child(i))
            b.compact(true);
    g.end();
}

void main(string[] args)
{
    auto win = new DoubleWindow(520, 250, "fldtk compact buttons");

    auto g = bar(10, "Button");
    foreach (i, l; ["One", "Two", "Three", "Four"])
        new Button(140 + cast(int) i * 90, 10, 90, 30, l);
    join(g);

    g = bar(50, "Toggle (radio)");
    foreach (i, l; ["Left", "Center", "Right"])
    {
        auto b = new Button(140 + cast(int) i * 120, 50, 120, 30, l);
        b.type(radioButton);
        if (i == 0) b.value(true);
    }
    join(g);

    g = bar(90, "LightButton");
    foreach (i, l; ["Bold", "Italic", "Underline"])
        new LightButton(140 + cast(int) i * 120, 90, 120, 30, l);
    join(g);

    g = bar(130, "ReturnButton");
    new Button(140, 130, 120, 30, "Cancel");
    new Button(260, 130, 120, 30, "Apply");
    new ReturnButton(380, 130, 120, 30, "OK");
    join(g);

    g = bar(170, "Mixed");
    new Button(140, 170, 120, 30, "Button");
    new LightButton(260, 170, 120, 30, "Light");
    new ReturnButton(380, 170, 120, 30, "OK");
    join(g);

    new SchemeChoice(140, 210, 120, 30, "Scheme:");
    win.end();
    win.show(args);
    run();
}
