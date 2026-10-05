// D transliteration of FLTK's examples/howto-flex-simple.cxx.
// Build: rdmd buildsamples.d examples howto_flex_simple
import fl;
import std.format : format;

// the 'Exit' button callback closes the window and terminates the program
void exitCb(Widget w)
{
    message(format("The '%s' button closes the window\nand terminates the program.", w.label()));
    w.window().hide();
}

// common callback for all other buttons
void buttonCb(Widget w)
{
    message(format("The '%s' button does nothing.", w.label()));
}

void main(string[] args)
{
    auto window = new DoubleWindow(410, 40, "Simple Flex Demo");
    auto flex = new Flex(5, 5, window.w() - 10, window.h() - 10, flexHorizontal);
    auto b1 = new Button(0, 0, 0, 0, "File");
    auto b2 = new Button(0, 0, 0, 0, "New");
    auto b3 = new Button(0, 0, 0, 0, "Save");
    auto bx = new Box(0, 0, 0, 0); // empty space
    auto eb = new Button(0, 0, 0, 0, "Exit");

    // assign callbacks to buttons
    b1.callback((w) { buttonCb(w); });
    b2.callback((w) { buttonCb(w); });
    b3.callback((w) { buttonCb(w); });
    eb.callback((w) { exitCb(w); });

    // set gap between adjacent buttons and extra spacing (invisible box size)
    flex.gap(10);
    flex.fixed(bx, 30); // total 50: 2 * gap + 30

    // end() groups
    flex.end();
    window.end();

    // set resizable, minimal window size, show() window, and execute event loop
    window.resizable(flex);
    window.sizeRange(300, 30);
    window.show(args);
    fl.run();
}
