// D transliteration of FLTK's test/hello.cxx.
// Build: rdmd buildsamples.d test hello
import fl;

void main(string[] args)
{
    auto window = new Window(340, 180);
    auto box = new Box(20, 40, 300, 100, "Hello, World!");
    box.box(Boxtype.upBox);
    box.labelfont(bold + italic);
    box.labelsize(36);
    box.labeltype(Labeltype.shadowLabel);
    window.end();
    window.show(args);
    fl.run();
}
