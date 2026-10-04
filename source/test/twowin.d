// D transliteration of FLTK's test/twowin.cxx (~/Repositories/fltk).
// Part of the samples/ contract -- see samples/README.md.
// Check: ./samples/build.sh twowin
import fl;

private Input b1, b2;

void main(string[] args)
{
    auto win1 = new DoubleWindow(200, 200);
    auto bb1 = new Button(10, 10, 100, 100, "b1");
    bb1.callback((w) { b2.takeFocus(); });
    b1 = new Input(10, 150, 100, 25);
    win1.label("win1");
    win1.end();

    auto win2 = new DoubleWindow(200, 200);
    auto bb2 = new Button(10, 10, 100, 100, "b2");
    bb2.callback((w) { b1.takeFocus(); });
    b2 = new Input(10, 150, 100, 25);
    win2.label("win2");
    win2.end();

    win1.position(200, 200);
    win2.position(400, 200);

    win1.show(args);
    win2.show();
    fl.run();
}
