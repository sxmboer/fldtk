// D transliteration of FLTK's examples/grid-simple.cxx.
// Build: rdmd buildsamples.d examples grid_simple
import fl;

void main(string[] args)
{
    auto win = new DoubleWindow(320, 180, "3x3 Grid with Buttons");
    // create the Grid container with five buttons
    auto grid = new Grid(0, 0, win.w(), win.h());
    grid.layout(3, 3, 10, 10);
    grid.color(white);
    auto b0 = new Button(0, 0, 0, 0, "New");
    auto b1 = new Button(0, 0, 0, 0, "Options");
    auto b3 = new Button(0, 0, 0, 0, "About");
    auto b4 = new Button(0, 0, 0, 0, "Help");
    auto b6 = new Button(0, 0, 0, 0, "Quit");
    // assign buttons to grid positions
    grid.widget(b0, 0, 0);
    grid.widget(b1, 0, 2);
    grid.widget(b3, 1, 1);
    grid.widget(b4, 2, 0);
    grid.widget(b6, 2, 2);
    // grid.showGrid(true);     // enable to display grid helper lines
    grid.end();
    win.end();
    win.resizable(grid);
    win.sizeRange(300, 100);
    win.show(args);
    fl.run();
}
