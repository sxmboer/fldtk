// D transliteration of FLTK's examples/howto-remap-numpad-keyboard-keys.cxx
// (~/Repositories/fltk).
// Part of the samples/ contract -- see samples/README.md.
// Check: ./samples/build.sh howto-remap-numpad-keyboard-keys
import fl;

CheckButton gCheckbut;

// Global event handler: FLTK calls this after event translation. It's up
// to us to call fl.handle(e,w) to actually deliver the event to the
// widgets. If we don't and just return, the event will be dropped.

int myHandler(Event e, Widget w)
{
    // Remapping disabled? Early exit..
    if (gCheckbut.value() == false)
        return fl.handle(e, w);
    // Keyboard key pressed? See if we should remap..
    if (e == Event.keyDown || e == Event.keyUp)
    {
        // Get FLTK keycode /before/ NumLock state is applied (see above DESCRIPTION)
        int keycode = fl.eventOriginalKey(); // get keycode before FLTK applies NumLock
        if (keycode >= kp && keycode <= kpLast) // keypad key pressed?
        {
            static char[2] buf; // static: we don't want buffer to go out of scope
            buf[0] = cast(char)(keycode - kp); // convert keypad keycode -> ascii
            buf[1] = 0; // terminate string (for safety)
            fl.eventText(buf[0 .. 1].idup); // point to our static buffer (eventLength() derives from this)
            fl.eventKeysym(keycode); // note: some input widgets require this too
        }
    }
    return fl.handle(e, w); // let FLTK deliver event to widgets
}

void main(string[] args)
{
    auto win = new DoubleWindow(400, 150, "Keyboard Translation Test");
    win.begin();
    {
        new Input(100, 10, 200, 25, "Input:");
        gCheckbut = new CheckButton(100, 40, 280, 25, "Force numeric keypad to type numbers");
        gCheckbut.labelsize(12);
        gCheckbut.set();
    }
    win.end();
    win.resizable(win);
    win.show(args);
    win.tooltip("Turn NumLock OFF, then type into Input:\nusing numeric keypad to test translation");
    // Set up our event handler to manage events
    fl.eventDispatch((e, w) { return myHandler(e, w); });
    fl.run();
}
