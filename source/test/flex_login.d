// D transliteration of FLTK's test/flex_login.cxx.
// Build: rdmd buildsamples.d test flex_login
import fl;

Button createButton(string caption)
{
    auto rtn = new Button(0, 0, 100, 25, caption);
    rtn.color(rgbColor(225, 225, 225));
    return rtn;
}

// create widgets inside a column, i.e. parent is type(COLUMN)

void buttonsPanel(Flex parent)
{
    new Box(0, 0, 0, 0, "");
    auto title = new Box(0, 0, 0, 0, "Welcome to Flex");
    title.alignment(alignCenter);
    title.labelfont(bold + italic);
    title.labelsize(16);

    auto urow = new Flex(flexRow);
    {
        auto b = new Box(0, 0, 0, 0, "Username:");
        b.alignment(alignInside | alignRight);
        auto username = new Input(0, 0, 0, 0, "");

        urow.fixed(username, 180);
        urow.end();
    }

    auto prow = new Flex(flexRow);
    {
        auto b = new Box(0, 0, 0, 0, "Password:");
        b.alignment(alignInside | alignRight);
        // A deliberate deviation from FLTK (which uses a plain
        // Input here too, same as the other samples this comment
        // appears in) -- fldtk's own transliterations use a real
        // masked SecretInput for a password field regardless of what
        // the FLTK demo does, per explicit user direction.
        auto password = new SecretInput(0, 0, 0, 0, "");

        prow.fixed(password, 180);
        prow.end();
    }

    auto pad = new Box(0, 0, 0, 0, "");

    auto brow = new Flex(flexRow);
    {
        new Box(0, 0, 0, 0, "");
        auto reg = createButton("Register");
        auto login = createButton("Login");

        brow.fixed(reg, 80);
        brow.fixed(login, 80);
        brow.gap(20);

        brow.end();
    }

    auto b = new Box(0, 0, 0, 0, "");

    parent.fixed(title, 60);
    parent.fixed(urow, 30);
    parent.fixed(prow, 30);
    parent.fixed(pad, 1);
    parent.fixed(brow, 30);
    parent.fixed(b, 30);
}

// create widgets inside a row, i.e. parent is type(ROW)

void middlePanel(Flex parent)
{
    new Box(0, 0, 0, 0, "");

    auto box = new Box(0, 0, 0, 0, "Image");
    box.box(Boxtype.borderBox);
    box.color(rgbColor(0, 200, 0));
    auto spacer = new Box(0, 0, 0, 0, "");

    auto bp = new Flex(flexColumn);
    buttonsPanel(bp);
    bp.end();

    new Box(0, 0, 0, 0, "");

    parent.fixed(box, 150);
    parent.fixed(spacer, 10);
    parent.fixed(bp, 300);
}

// The main panel consists of three "rows" inside a column, i.e. parent is
// type(COLUMN). The middle panel has a fixed size (200) such that the two
// boxes take the remaining space and middlePanel has all widgets.

void mainPanel(Flex parent)
{
    new Box(0, 0, 0, 0, ""); // flexible separator

    auto mp = new Flex(flexRow);
    middlePanel(mp);
    mp.end();

    new Box(0, 0, 0, 0, ""); // flexible separator

    parent.fixed(mp, 200);
}

void main()
{
    Window win = new DoubleWindow(100, 100, "Flex \"Login\" Layout");

    auto col = new Flex(5, 5, 90, 90, flexColumn);
    mainPanel(col);
    col.end();

    win.resizable(col);
    win.color(rgbColor(250, 250, 250));
    win.end();

    win.resize(0, 0, 600, 300); // same size as grid_login
    win.sizeRange(550, 250);
    win.show();

    fl.run();
    destroy(win); // not necessary but useful to test for memory leaks
}
