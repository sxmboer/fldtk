// D transliteration of FLTK's test/grid_alignment.cxx (~/Repositories/fltk).
// Part of the samples/ contract -- see samples/README.md.
// Check: ./samples/build.sh grid_alignment
import fl;

// This program tests several different alignment features of Fl_Grid.
//
// FLTK gates a relayout-timer test (TEST_RELAYOUT) and a
// remove-notify test (TEST_REMOVE_NOTIFY) behind `#if 0` -- both fully
// disabled, including their callback function definitions -- so, like
// the preprocessor would, they're omitted here entirely rather than
// transliterated as dead code.

void main()
{
    Cell c;
    Box b;
    Window win = new DoubleWindow(440, 350, "Grid Alignment Test");
    auto grid = new Grid(10, 10, 420, 330);
    grid.layout(7, 7, 8, 4); // cols, rows, margin, gap
    grid.box(Boxtype.flatBox);
    grid.color(white);

    // add boxes (top and bottom rows)

    for (int col = 0; col < 7; col++)
    {
        grid.colWidth(col, 50);
        b = new Box(0, 0, 20, 20); // variable size
        if (col == 5)
        {
            b.size(4, 20); // reduce width
            grid.colWidth(col, 4); // new min. width
            grid.colWeight(col, 0); // no hor. resizing
        }
        b.box(Boxtype.flatBox);
        b.color(blue);
        grid.widget(b, 0, col);

        if (col == 5)
            b = new Box(0, 0, 4, 20); // variable size
        else
            b = new Box(0, 0, 20, 20); // variable size
        b.box(Boxtype.flatBox);
        b.color(red);
        grid.widget(b, 6, col);
    }

    // add boxes (left and right columns)

    grid.rowHeight(0, 40);
    grid.rowHeight(6, 40);

    for (int row = 1; row < 6; row++)
    {
        grid.rowHeight(row, 40);
        b = new Box(0, 0, 20, 20); // fixed size, see alignment below
        b.box(Boxtype.flatBox);
        b.color(red);
        switch (row)
        {
            case 1: grid.widget(b, row, 0, gridFill); break;
            case 2: grid.widget(b, row, 0, alignCenter); break;
            case 3: grid.widget(b, row, 0, alignBottomRight); break;
            case 4: grid.widget(b, row, 0, alignBottomRight); break;
            case 5: grid.widget(b, row, 0, alignTopRight); break;
            default: break;
        }

        b = new Box(0, 0, 20, 20);
        b.box(Boxtype.flatBox);
        b.color(green);
        c = grid.widget(b, row, 6, alignCenter);
    }

    // two more boxes to demonstrate widget alignment inside the cell

    for (int row = 4; row < 6; row++)
    {
        b = new Box(0, 0, 20, 20); // fixed size, see alignment below
        b.box(Boxtype.flatBox);
        b.color(magenta);
        c = grid.widget(b, row, 1); // default alignment: FL_GRID_FILL
        if (row == 4)
            c.alignment(alignBottomLeft); // alignment uses widget size
        if (row == 5)
            c.alignment(alignTopLeft); // alignment uses widget size
    }

    // one vertical box (line), spanning 5 rows

    b = new Box(0, 0, 2, 2); // extends vertically
    b.box(Boxtype.flatBox);
    b.color(black);
    grid.widget(b, 1, 5, 5, 1, gridVertical | alignRight);

    // add a textbox with label or title, spanning 5 cells, centered

    b = new Box(0, 0, 1, 1); // variable size
    b.label("Hello, Grid !");
    b.labelfont(bold + italic);
    b.labelsize(30);
    b.labeltype(Labeltype.shadowLabel);
    grid.widget(b, 1, 1, 1, 5); // rowspan = 1, colspan = 5

    // add a footer textbox, spanning 3 cells, right aligned

    b = new Box(0, 0, 1, 10); // variable size
    // ".d", not FLTK's ".cxx" -- this is just a literal display
    // caption in both ports (not a real file lookup, unlike
    // test/browser.d's fname), but it should still name this port's own
    // file, not FLTK's.
    b.label("fldtk/test/grid_alignment.d");
    b.labelfont(courier);
    b.labelsize(11);
    b.alignment(alignInside | alignRight);
    grid.widget(b, 5, 2, 1, 3, gridHorizontal | alignBottom);

    // input widgets with fixed size and alignment inside the cell

    auto i1 = new Input(0, 0, 100, 30, "Username:");
    c = grid.widget(i1, 2, 3, 1, 2); // widget, col, row, colspan, rowspan
    c.alignment(gridHorizontal); // widget alignment in cell

    // A deliberate deviation from FLTK (which uses a plain Input
    // here too) -- fldtk's own transliterations use a real masked
    // SecretInput for a password field, per explicit user direction.
    auto i2 = new SecretInput(0, 0, 100, 30, "Password:");
    c = grid.widget(i2, 3, 3, 1, 2); // widget, col, row, colspan, rowspan
    c.alignment(gridHorizontal); // widget alignment in cell

    // the login button spans 2 columns

    auto bt = new Button(0, 0, 10, 30, "Login");
    grid.widget(bt, 4, 3, 1, 2, gridHorizontal); // widget, col, row, colspan, rowspan, alignment

    grid.rowWeight(1, 90);
    grid.rowWeight(2, 0);
    grid.rowWeight(3, 0);
    grid.rowWeight(4, 0);

    grid.colWeight(0, 30);
    grid.colWeight(4, 90);

    grid.rowGap(5, 12);

    grid.end();
    grid.layout();
    grid.showGrid(false);
    // grid.showGrid(true);     // enable to display grid helper lines
    win.end();
    win.resizable(grid);
    win.sizeRange(440, 350);
    win.show();

    // return fl.run();
    fl.run();
    grid.clearLayout();
    destroy(win);
}
