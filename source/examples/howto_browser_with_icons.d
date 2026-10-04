// D transliteration of FLTK's examples/howto-browser-with-icons.cxx
// (~/Repositories/fltk).
// Part of the samples/ contract -- see samples/README.md.
// Check: ./samples/build.sh howto-browser-with-icons
import fl;

immutable string[] big = [ // XPM
    "50 34 4 1",
    "  c #000000",
    "o c #ff9900",
    "@ c #ffffff",
    "# c None",
    "##################################################",
    "###      ##############################       ####",
    "### ooooo  ###########################  ooooo ####",
    "### oo  oo  #########################  oo  oo ####",
    "### oo   oo  #######################  oo   oo ####",
    "### oo    oo  #####################  oo    oo ####",
    "### oo     oo  ###################  oo     oo ####",
    "### oo      oo                     oo      oo ####",
    "### oo       oo  ooooooooooooooo  oo       oo ####",
    "### oo        ooooooooooooooooooooo        oo ####",
    "### oo     ooooooooooooooooooooooooooo    ooo ####",
    "#### oo   ooooooo ooooooooooooo ooooooo   oo #####",
    "####  oo oooooooo ooooooooooooo oooooooo oo  #####",
    "##### oo oooooooo ooooooooooooo oooooooo oo ######",
    "#####  o ooooooooooooooooooooooooooooooo o  ######",
    "###### ooooooooooooooooooooooooooooooooooo #######",
    "##### ooooooooo     ooooooooo     ooooooooo ######",
    "##### oooooooo  @@@  ooooooo  @@@  oooooooo ######",
    "##### oooooooo @@@@@ ooooooo @@@@@ oooooooo ######",
    "##### oooooooo @@@@@ ooooooo @@@@@ oooooooo ######",
    "##### oooooooo  @@@  ooooooo  @@@  oooooooo ######",
    "##### ooooooooo     ooooooooo     ooooooooo ######",
    "###### oooooooooooooo       oooooooooooooo #######",
    "###### oooooooo@@@@@@@     @@@@@@@oooooooo #######",
    "###### ooooooo@@@@@@@@@   @@@@@@@@@ooooooo #######",
    "####### ooooo@@@@@@@@@@@ @@@@@@@@@@@ooooo ########",
    "######### oo@@@@@@@@@@@@ @@@@@@@@@@@@oo ##########",
    "########## o@@@@@@ @@@@@ @@@@@ @@@@@@o ###########",
    "########### @@@@@@@     @     @@@@@@@ ############",
    "############  @@@@@@@@@@@@@@@@@@@@@  #############",
    "##############  @@@@@@@@@@@@@@@@@  ###############",
    "################    @@@@@@@@@    #################",
    "####################         #####################",
    "##################################################",
];

immutable string[] med = [ // XPM
    "14 14 2 1",
    "# c #000000",
    "  c #ffffff",
    "##############",
    "##############",
    "##          ##",
    "##  ##  ##  ##",
    "##  ##  ##  ##",
    "##   ####   ##",
    "##    ##    ##",
    "##    ##    ##",
    "##   ####   ##",
    "##  ##  ##  ##",
    "##  ##  ##  ##",
    "##          ##",
    "##############",
    "##############",
];

immutable string[] sml = [ // XPM
    "9 11 5 1",
    ".  c None",
    "@  c #000000",
    "+  c #808080",
    "r  c #802020",
    "#  c #ff8080",
    ".........",
    ".........",
    "@+.......",
    "@@@+.....",
    "@@r@@+...",
    "@@##r@@+.",
    "@@####r@@",
    "@@##r@@+.",
    "@@r@@+...",
    "@@@+.....",
    "@+.......",
];

// Create a custom browser
//
// You don't *have* to derive a class just to control icons in a browser,
// but in final apps it's something you'd do to keep the implementation
// clean. All it really comes down to is calling browser.icon() to define
// icons for the items you want.
class MyBrowser : Browser
{
    Image bigIcon;
    Image medIcon;
    Image smlIcon;

    this(int X, int Y, int W, int H, string L = null)
    {
        super(X, Y, W, H, L);

        // Create icons (these could also be pngs, jpegs..)
        bigIcon = new Pixmap(big);
        medIcon = new Pixmap(med);
        smlIcon = new Pixmap(sml);

        // Normal browser initialization stuff
        textfont(courier);
        textsize(14);
        type(multiBrowser);
        add("One");
        add("Two");
        add("Three");
        add("Four");
        add("Five");
        add("Six");
        add("Seven");
    }

    // See which icon the user picked, and change the icon of three
    // browser items to it. This is all you have to do to change a
    // browser item's icon -- the browser will automatically resize the
    // items if need be.
    void choiceCb(Choice ch)
    {
        Image i = null;
        if (ch.text() == "None") i = null;
        else if (ch.text() == "Small") i = smlIcon;
        else if (ch.text() == "Medium") i = medIcon;
        else if (ch.text() == "Large") i = bigIcon;

        icon(3, i);
        icon(4, i);
        icon(5, i);
    }
}

void main()
{
    auto w = new DoubleWindow(400, 300);

    // Create a browser
    auto b = new MyBrowser(10, 40, w.w() - 20, w.h() - 50);

    // Create a chooser to let the user change the icons
    auto choice = new Choice(60, 10, 140, 25, "Icon:");
    choice.add("None", 0, null);
    choice.add("Small", 0, null);
    choice.add("Medium", 0, null);
    choice.add("Large", 0, null);
    choice.callback((ch) { b.choiceCb(cast(Choice) ch); });
    choice.takeFocus();
    choice.value(1);
    choice.doCallback();

    w.end();
    w.show();
    fl.run();
}
