// D transliteration of FLTK's test/tile.cxx.
// Build: rdmd buildsamples.d test tile
//
// FLTK picks between two whole demos with #if 0/#else (the "Sample
// code from Fl_Tile documentation" branch is dead, #if 0'd out) and gates
// a couple of details with #ifndef CLASSIC_MODE / #ifdef TEST_INACTIVE
// (neither CLASSIC_MODE nor TEST_INACTIVE is defined by default). This
// transliteration follows the one compiled-in path: the "new Fl_Tile test
// code" branch, non-classic mode, without the inactive test.
import fl;

void main(string[] args)
{
    // FLTK: Fl_Double_Window window(300, 300) -- DoubleWindow doesn't
    // exist yet at all (fl.double_window is planned but not started).
    auto window = new DoubleWindow(300, 300);
    window.box(Boxtype.noBox);
    window.resizable(window);

    auto tile = new Tile(0, 0, 300, 300);
    tile.initSizeRange(30, 30); // all children's size shall be at least 30x30

    // create the symmetrical resize box with dx and dy pixels distance, resp.
    // from the borders of the Fl_Tile widget before all other children

    auto box0 = new Box(0, 0, 150, 150, "0");
    box0.box(Boxtype.downBox);
    box0.color(9);
    box0.labelsize(36);
    box0.alignment(alignClip);
    tile.resizable(box0);

    // FLTK: Fl_Double_Window w1(150,0,150,150,"1") -- note this is NOT
    // fldtk's Window (which does have a matching 5-arg x/y/w/h/label ctor);
    // using DoubleWindow here matters, since Window would silently compile.
    auto w1 = new DoubleWindow(150, 0, 150, 150, "1");
    w1.box(Boxtype.noBox);
    auto box1 = new Box(0, 0, 150, 150, "1\nThis is a child window");
    box1.box(Boxtype.downBox);
    box1.color(19);
    box1.labelsize(18);
    box1.alignment(alignClip | alignInside | alignWrap);
    w1.resizable(box1);
    w1.end();

    auto box2a = new Box(0, 150, 70, 150, "2a");
    box2a.box(Boxtype.downBox);
    box2a.color(12);
    box2a.labelsize(36);
    box2a.alignment(alignClip);

    auto box2b = new Box(70, 150, 80, 150, "2b");
    box2b.box(Boxtype.downBox);
    box2b.color(13);
    box2b.labelsize(36);
    box2b.alignment(alignClip);

    auto box3a = new Box(150, 150, 150, 70, "3a");
    box3a.box(Boxtype.downBox);
    box3a.color(12);
    box3a.labelsize(36);
    box3a.alignment(alignClip);

    auto box3b = new Box(150, 150 + 70, 150, 80, "3b");
    box3b.box(Boxtype.downBox);
    box3b.color(13);
    box3b.labelsize(36);
    box3b.alignment(alignClip);

    tile.end();
    window.end();

    w1.show();
    window.sizeRange(90, 90);
    window.show(args);

    fl.run();
}
