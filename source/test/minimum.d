// D transliteration of FLTK's test/minimum.cxx.
// Build: rdmd buildsamples.d test minimum
import fl;

void main(string[] args)
{
    auto window = new DoubleWindow(400, 320, args[0]);
    window.resizable(new Box(Boxtype.engravedFrame, 10, 10, 300, 300,
        "MINIMUM UPDATE TEST\n"
        ~ "\n"
        ~ "The slider on the right purposely\n"
        ~ "draws outside its boundaries.\n"
        ~ "Moving it should leave old copies\n"
        ~ "of the label.  These copies should\n"
        ~ "*not* be erased by any actions\n"
        ~ "other than hiding and showing\n"
        ~ "of that portion of the window\n"
        ~ "or changing the button that\n"
        ~ "intersects them."));

    auto s = new Slider(320, 10, 20, 300, "Too_Big_Label");
    s.alignment(0);

    new Button(20, 270, 100, 30, "Button");
    new ReturnButton(200, 270, 100, 30, "Button");

    window.show(args);
    fl.run();
}
