// D transliteration of FLTK's test/grid_buttons.cxx.
// Build: rdmd buildsamples.d test grid_buttons

// Q: How to achieve a spaced out layout?
// https://groups.google.com/g/fltkgeneral/c/haet7hOQR0g

// A: We use an Fl_Grid with 1 x 7 cells (5 buttons) as requested:
// [New] [Options] <gap> [About] [Help] <gap> [Quit]

import fl;

void main()
{
    Window win = new DoubleWindow(460, 200, "Grid Row with 5 Buttons");

    auto grid = new Grid(0, 0, win.w(), 50);
    grid.layout(1, 7, 10, 10);

    // create the buttons

    auto b0 = new Button(0, 0, 80, 30, "New");
    auto b1 = new Button(0, 0, 80, 30, "Options");
    auto b3 = new Button(0, 0, 80, 30, "About");
    auto b4 = new Button(0, 0, 80, 30, "Help");
    auto b6 = new Button(0, 0, 80, 30, "Quit");

    grid.end();

    // assign buttons to grid positions

    grid.widget(b0, 0, 0);
    grid.widget(b1, 0, 1); grid.colGap(1, 0);
    grid.widget(b3, 0, 3);
    grid.widget(b4, 0, 4); grid.colGap(4, 0);
    grid.widget(b6, 0, 6);

    // set column weights for resizing (only empty columns resize)

    int[7] weight = [0, 0, 50, 0, 0, 50, 0];
    grid.colWeight(weight[]);

    grid.end();
    // grid.showGrid(1);     // enable to display grid helper lines

    // add content ...

    auto g1 = new FlGroup(0, 50, win.w(), win.h() - 50);
    // add more widgets ...

    win.end();
    win.resizable(g1);
    win.sizeRange(win.w(), 100);
    win.show();

    fl.run();
    destroy(win); // not necessary but useful to test for memory leaks
}
