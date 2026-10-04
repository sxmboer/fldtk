// D transliteration of FLTK's test/clock.cxx (~/Repositories/fltk).
// Part of the samples/ contract -- see samples/README.md.
// Check: ./samples/build.sh clock
import fl;

enum bool devTest = false; // true = enable non-standard colors and no-shadow tests

// close all windows when the user closes one of the windows
void closeCb(Widget w)
{
    Window win = fl.firstWindow();
    while (win !is null)
    {
        win.hide();
        win = fl.firstWindow();
    }
}

void main()
{
    auto window = new DoubleWindow(220, 220, "FlClock");
    window.callback((w) { closeCb(w); });
    auto c1 = new FlClock(0, 0, 220, 220); // c1.color(2,1);
    window.resizable(c1);
    window.end();

    auto window2 = new DoubleWindow(220, 220, "RoundClock");
    window2.callback((w) { closeCb(w); });
    auto c2 = new RoundClock(0, 0, 220, 220);
    if (devTest)
    {
        c2.color(yellow, red); // set background and hands colors, resp.
        c2.shadow(false); // disable shadows of the hands
    }
    window2.resizable(c2);
    window2.end();

    // my machine had a clock* Xresource set for another program, so
    // I don't want the class to be "clock":
    window.xclass("FlClock");
    window2.xclass("FlClock");
    window.show();
    window2.show();
    fl.run();
}
