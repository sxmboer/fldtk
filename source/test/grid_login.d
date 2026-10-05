// D transliteration of FLTK's test/grid_login.cxx.
// Build: rdmd buildsamples.d test grid_login
import fl;

void main()
{
    Window win = new DoubleWindow(480, 200, "Grid \"Login\" Layout");

    // Fl_Grid of 6 x 6 cells, margin 2 and gap 2

    auto grid = new Grid(5, 5, 470, 190);
    grid.layout(6, 6, 2, 2); // 6 rows, 6 columns, margin 2, gap 2

    // image (150x200) in left column

    auto ibox = new Box(0, 0, 150, 200, "Image");
    ibox.box(Boxtype.borderBox);
    ibox.color(rgbColor(0, 200, 0));
    grid.widget(ibox, 1, 1, 4, 1, gridCenter);

    // the title spans 2 columns (3 - 4)

    auto title = new Box(0, 0, 200, 60);
    title.label("Welcome to Grid");
    title.alignment(alignCenter);
    title.labelfont(bold + italic);
    title.labelsize(16);
    grid.widget(title, 1, 3, 1, 2, gridHorizontal | gridCenter);

    grid.colWidth(2, 90); // placeholder for labels

    // input widgets with fixed height and horizontal stretching

    auto i1 = new Input(0, 0, 150, 30, "Username:");
    grid.widget(i1, 2, 3, 1, 2, gridHorizontal);
    grid.rowGap(2, 10); // gap below username

    // A deliberate deviation from FLTK (which uses a plain Input
    // here too) -- fldtk's own transliterations use a real masked
    // SecretInput for a password field, per explicit user direction.
    auto i2 = new SecretInput(0, 0, 150, 30, "Password:");
    grid.widget(i2, 3, 3, 1, 2, gridHorizontal);
    grid.rowGap(3, 10); // gap below password

    // register and login buttons

    auto btr = new Button(0, 0, 80, 30, "Register");
    grid.widget(btr, 4, 3, 1, 1, gridHorizontal);
    grid.colGap(3, 20); // gap right of the register button

    auto btl = new Button(0, 0, 80, 30, "Login");
    grid.widget(btl, 4, 4, 1, 1, gridHorizontal);

    // set column and row weights for resizing behavior (optional)

    int[6] cw = [20, 0, 0, 10, 10, 20]; // column weights
    int[6] rw = [10, 0, 0, 0, 0, 10]; // row weights
    grid.colWeight(cw[]);
    grid.rowWeight(rw[]);

    grid.end();
    grid.layout();
    // grid.debugLevel(1);
    // grid.showGrid(1);     // enable to display grid helper lines
    win.end();
    grid.color(rgbColor(250, 250, 250));
    win.color(rgbColor(250, 250, 250));

    win.resizable(grid);
    win.resize(0, 0, 600, 300); // same size as flex_login
    win.sizeRange(550, 250);
    win.show();

    fl.run();
    destroy(win); // not necessary but useful to test for memory leaks
}
