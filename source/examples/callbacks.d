// D transliteration of FLTK's examples/callbacks.cxx.
// Build: rdmd buildsamples.d examples callbacks
//
// FLTK demonstrates the FL_FUNCTION_CALLBACK_N / FL_METHOD_CALLBACK_N /
// FL_INLINE_CALLBACK_N macros, which exist purely to let a plain C
// function pointer + void* carry extra typed parameters. D delegates
// already close over whatever state they need, so none of that macro
// machinery is needed here -- every "callback with custom parameters"
// below is just a delegate literal capturing its parameters directly
// (see CONVENTIONS.md's callback-delegate convention).
import fl;
import std.format : format;

Window window;

void hello0Args()
{
    message("Hello with 0 arguments");
}

void hello2Args(string text, int number)
{
    message(format("Hello with 2 arguments,\n\"%s\" and '%d'", text, number));
}

void hello4Args(int a1, int a2, int a3, int a4)
{
    message(format("Hello with 4 arguments:\n%d %d %d %d", a1, a2, a3, a4));
}

// We create our own little class here that uses method callbacks.
class MyButton : Button
{
    // id_ is set in the constructor
    private int id_;

    this(int x, int y, int w, int h, string label, int id)
    {
        super(x, y, w, h, label);
        id_ = id;
    }

    // public non-static callback method -- a plain method, no macro needed
    // since the delegate created from it already carries `this`.
    void hello(int a, int b, int c)
    {
        message(format("MyButton has the id %d\nand was called with the custom parameters\n%d, %d, and %d.",
            id_, a, b, c));
    }
}

// Each call creates its own MyButton with its own captured parameters --
// a D delegate created per-widget already gives every widget its own
// separate set of "user data" at runtime, same guarantee the macro gave.
void makeButton(Window win, int set)
{
    int[2] yLut = [60, 90];
    string[2] labelLut = ["id 2 (5, 6, 7)", "id 3 (6, 7, 8)"];
    auto btn = new MyButton(200, yLut[set], 180, 25, labelLut[set], set + 2);
    btn.callback((w) { btn.hello(set + 5, set + 6, set + 7); });
}

void main(string[] args)
{
    window = new Window(580, 120);

    // -- testing function callbacks with multiple arguments

    new Box(10, 5, 180, 25, "Function Callbacks:");

    auto funcCbBtn0 = new Button(10, 30, 180, 25, "0 args");
    funcCbBtn0.callback((w) { hello0Args(); });

    auto funcCbBtn2 = new Button(10, 60, 180, 25, "2 args");
    funcCbBtn2.callback((w) { hello2Args("FLTK", 2); });

    auto funcCbBtn4 = new Button(10, 90, 180, 25, "4 args");
    funcCbBtn4.callback((w) { hello4Args(1, 2, 3, 4); });

    // -- testing non-static method callbacks with multiple arguments

    new Box(200, 5, 180, 25, "Method Callbacks:");

    auto methCbBtn0 = new MyButton(200, 30, 180, 25, "id 1 (1, 2, 3)", 1);
    methCbBtn0.callback((w) { methCbBtn0.hello(1, 2, 3); });

    // call makeButton() multiple times to ensure we get individual
    // parameter sets -- each captures its own `set` and `btn`.
    makeButton(window, 0);
    makeButton(window, 1);

    // -- testing inline callback functions

    new Box(390, 5, 180, 25, "Inline Callbacks:");

    auto inlineCbBtn0 = new Button(390, 30, 180, 25, "0 args");
    inlineCbBtn0.callback((w) {
        message("Inline callback with 0 args.");
    });

    auto inlineCbBtn2 = new Button(390, 60, 180, 25, "2 args");
    {
        string text = "FLTK";
        int number = 2;
        inlineCbBtn2.callback((w) {
            message(format("We received the message %s with %d!", text, number));
        });
    }

    auto inlineCbBtn4 = new Button(390, 90, 180, 25, "4 args");
    {
        int x = window.x();
        int y = window.y();
        int w = window.w();
        int h = window.h();
        inlineCbBtn4.callback((btn) {
            message(format("The main window was at\nx:%d, y:%d, w:%d, h:%d\n"
                ~ "when the callback was created\n"
                ~ "and is now at x:%d, y:%d", x, y, w, h,
                window.x(), window.y()));
        });
    }

    window.end();
    window.show(args);
    fl.run();
}
