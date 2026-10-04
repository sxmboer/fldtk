// D transliteration of FLTK's test/input_choice.cxx (~/Repositories/fltk).
// Part of the samples/ contract -- see samples/README.md.
// Check: ./samples/build.sh input_choice
import fl;

enum int terminalHeight = 150;

// Globals
Terminal gTty;

void main(string[] args)
{
    auto win = new Window(300, 200 + terminalHeight);

    gTty = new Terminal(0, 200, win.w(), terminalHeight);

    // this group can be activated and deactivated:
    auto activeGroup = new FlGroup(0, 0, 300, 120);

    // all *_Choice widgets must be aligned for easier visual comparison:

    auto in_ = new InputChoice(180, 40, 100, 25, "InputChoice:");
    in_.callback((w) {
        gTty.printf("InputChoice value='%s'\n", in_.value());
    });
    in_.add("one");
    in_.add("two");
    in_.add("three");
    in_.value(0);

    auto choice = new Choice(180, 70, 100, 25, "Choice:");
    choice.callback((w) {
        gTty.printf("Choice      value='%d'\n", choice.value());
    });
    choice.add("aaa", 0, null);
    choice.add("bbb", 0, null);
    choice.add("ccc", 0, null);
    choice.value(1);

    activeGroup.end();

    // Interactive control of scheme
    auto sch = new SchemeChoice(180, 120, 100, 25, "Choose scheme:");
    sch.visibleFocus(false);

    auto active = new CheckButton(50, 160, 160, 30, "Activate/deactivate");
    active.callback((w) {
        auto b = cast(CheckButton) w;
        if (b.value())
        {
            activeGroup.activate();
            gTty.printf("activate group\n");
        }
        else
        {
            activeGroup.deactivate();
            gTty.printf("deactivate group\n");
        }
        activeGroup.redraw();
        if (b.changed())
        {
            gTty.printf("Callback: changed() is set\n");
            b.clearChanged();
        }
    });
    active.value(1);

    win.end();
    win.resizable(win);
    win.sizeRange(200, 160);
    win.show(args);
    fl.run();
    destroy(win);
}
