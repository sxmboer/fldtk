// D transliteration of FLTK's test/buttons.cxx (~/Repositories/fltk).
// Part of the samples/ contract -- see samples/README.md.
// Check: ./samples/build.sh buttons
import fl;

void main(string[] args)
{
    auto window = new Window(420, 170);
    auto b1 = new Button(10, 10, 130, 30, "Button");
    b1.tooltip("Button");
    Button b2 = new ReturnButton(150, 10, 160, 30, "ReturnButton");
    b2.tooltip("ReturnButton");
    Button b3 = new RepeatButton(10, 50, 130, 30, "RepeatButton");
    b3.tooltip("RepeatButton");
    Button b4 = new RoundButton(150, 50, 160, 30, "RoundButton");
    b4.tooltip("RoundButton");
    Button b5 = new LightButton(10, 90, 130, 30, "LightButton");
    b5.tooltip("LightButton");
    Button b6 = new CheckButton(150, 90, 160, 30, "CheckButton");
    b6.tooltip("CheckButton");

    auto keypad = new FlGroup(320, 10, 90, 120);
    Button[11] kp;
    kp[7] = new Button(320, 10, 30, 30, "7");
    kp[8] = new Button(350, 10, 30, 30, "8");
    kp[9] = new Button(380, 10, 30, 30, "9");
    kp[4] = new Button(320, 40, 30, 30, "4");
    kp[5] = new Button(350, 40, 30, 30, "5");
    kp[6] = new Button(380, 40, 30, 30, "6");
    kp[1] = new Button(320, 70, 30, 30, "1");
    kp[2] = new Button(350, 70, 30, 30, "2");
    kp[3] = new Button(380, 70, 30, 30, "3");
    kp[0] = new Button(320, 100, 60, 30, "0");
    kp[10] = new Button(380, 100, 30, 30, ".");
    for (int i = 0; i < 11; i++)
    {
        kp[i].compact(true);
        kp[i].selectionColor(selectionColor);
    }
    keypad.end();

    // Add a scheme choice widget for easier testing. Position the widget at
    // the right window border so the menu popup doesn't cover the check boxes etc.
    auto schemeChoice = new SchemeChoice(180, 130, 130, 30, "Active FLTK Scheme:");
    schemeChoice.tooltip("SchemeChoice");

    window.end();
    window.resizable(window);
    window.sizeRange(320, 130);
    window.show(args);
    fl.run();
}
