// D transliteration of FLTK's test/button.cxx.
// Build: rdmd buildsamples.d test button
import fl;
import std.stdio : stdout;

void main(string[] args)
{
    auto window = new Window(320, 65);
    auto b1 = new Button(20, 20, 80, 25, "&Beep");
    b1.callback((w) {
        fl_beep();
        stdout.flush();
    });
    new Button(120, 20, 80, 25, "&no op");
    auto b3 = new Button(220, 20, 80, 25, "E&xit");
    b3.callback((w) { window.hide(); } );
    window.end();
    window.show(args);
    fl.run();
}
