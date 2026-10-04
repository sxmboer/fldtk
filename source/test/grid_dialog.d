// D transliteration of FLTK's test/grid_dialog.cxx (~/Repositories/fltk).
// Part of the samples/ contract -- see samples/README.md.
// Check: ./samples/build.sh grid_dialog

// This demo program builds a flexible layout of a dialog similar
// to fl_ask(), fl_choice(), and others.
//
// For <N> buttons we use an Fl_Grid with 2 rows and <N+2> columns:
// - Cell (0, 0) (III) holds an icon (top left cell)
// - Cell (0, 1) holds the message text; spans <N+1> columns
// - Cell (1, n) holds buttons (2 <= n <= <N+1>)
// - Column 1    (XX) is the resizable column; not used for buttons
// - Column 2+   is used for buttons
//      _________________________________________________
//     |                                                 |
//     |  III  Some message text ... ... ... ... ... ... |
//     |  III  more message text ... ... ... ... ... ... |
//     |  III  more message text ... ... ... ... ... ... |
//     |       more message text ... ... ... ... ... ... |
//     |       more message text ... ... ... ... ... ... |
//     |       XX                      +--------+ +----+ |
//     |       XX  [more buttons ...]  | Cancel | | OK | |
//     |       XX                      +--------+ +----+ |
//     |_________________________________________________|

import fl;
import std.stdio : writefln, stdout;

enum int rows = 2;
enum int buttons = 4; // default = 4, use 1 to 5 to test
enum int cols = buttons + 2;
enum int buttonH = 25;
enum int iconW = 60;
enum int iconH = 70;
enum int marginSize = 10;
enum int gapSize = 8;

// Button labels (left to right)
immutable string[5] labels = ["Quit", "Copy", "Cancel", "OK", "More ..."];

immutable string[5] tooltips = [
    "Quit this program",
    "Copy the message text to the clipboard",
    "Cancel - does nothing",
    "OK - does nothing",
    "More buttons could be added here"
];

// button widths (left to right) to avoid font calculations
immutable int[5] buttonW = [50, 50, 70, 40, 100];

int[7] colWeights = [0, 100, 0, 0, 0, 0, 0];
int[7] rowWeights = [100, 0, 0, 0, 0, 0, 0];

immutable string messageText =
    "This is a long message in a Grid based dialog "
    ~ "that may wrap over more than one line. "
    ~ "Resize the window to see how it (un)wraps.";

Box messageBox; // global only to simplify the code

// Common button callback

void buttonCb(Widget w, int val)
{
    writefln("Button %d: '%s'", val, w.label());
    switch (val)
    {
        case 0: // Quit
            w.window().hide();
            break;
        case 1: // Copy
        {
            string text = messageBox.label();
            fl.copy(text, 1);
        }
            writefln("Message copied to clipboard.");
            break;
        default:
            break;
    }
    stdout.flush();
}

void main()
{
    int minW = iconW + 2 * marginSize + (buttons + 1) * gapSize;
    int minH = iconH + 10 + 2 * marginSize + gapSize + buttonH;

    for (int i = 0; i < buttons; i++)
    {
        minW += buttonW[i];
    }

    Window win = new DoubleWindow(minW, minH, "Grid Based Dialog");

    auto grid = new Grid(0, 0, win.w(), win.h());
    grid.layout(rows, cols, marginSize, gapSize);
    grid.color(white);
    grid.tooltip("Resize the window to see this dialog \"in action\"");

    // Child 0: Fl_Box for the "icon" or image (fixed size)

    auto icon = new Box(0, 0, iconW, iconH, "ICON");
    grid.widget(icon, 0, 0, 1, 1, gridTop);
    icon.box(Boxtype.thinUpBox);
    icon.color(0xddffff00);
    icon.alignment(alignCenter | alignInside | alignClip);
    icon.tooltip("This could also be a full Image or subclass thereof");

    // Child 1: the message box

    messageBox = new Box(0, 0, 0, 0);
    grid.widget(messageBox, 0, 1, 1, buttons + 1, gridFill);
    messageBox.label(messageText);
    messageBox.alignment(alignTop | alignInside | alignWrap);
    messageBox.tooltip("The text in this box can be copied to the clipboard");

    // Children 2++: the buttons (left to right for tab navigation order)

    // static foreach (compile-time unrolled, since `buttons` is a
    // compile-time constant), not a plain runtime foreach: a runtime
    // foreach's loop variable is shared/mutated across iterations, so
    // every button's delegate would end up capturing the *same* final
    // `i` (all reporting `buttons` on click, not their own index).
    // FLTK sidesteps this entirely by passing `i` through the C
    // callback's `void*` argument (`fl_voidptr(i)`) instead of a
    // captured closure.
    static foreach (i; 0 .. buttons)
    {
        {
            auto b = new Button(0, 0, buttonW[i], buttonH, labels[i]);
            grid.widget(b, 1, i + 2);
            b.callback((w) { buttonCb(w, i); });
            b.tooltip(tooltips[i]);
        }
    }

    grid.end();

    // set row and column weights for resizing

    grid.rowWeight(rowWeights[0 .. rows]);
    grid.colWeight(colWeights[0 .. cols]);

    // Set environment variable "FLTK_GRID_DEBUG=1" or uncomment this line:
    // grid.showGrid(1);     // enable to display grid helper lines

    win.end();
    win.resizable(grid);
    win.sizeRange(minW, minH, 3 * minW, minH + 50);
    win.show();

    fl.run();
    destroy(win); // not necessary but useful to test for memory leaks
}
