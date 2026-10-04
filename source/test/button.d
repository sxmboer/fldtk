// D transliteration of FLTK's test/button.cxx (~/Repositories/fltk).
// Part of the samples/ contract -- see samples/README.md.
// Check: ./samples/build.sh button
import fl;
import std.stdio : stdout;
import core.stdc.stdlib : exit; /* how it was done in C++, but not really a clean way to do this in D
                                isn't there a clean way to call fl.exit(); or something like that? */

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
//    b3.callback((w) { exit(0); });
    b3.callback((w) { window.hide(); } );
    window.end();
    window.show(args);
    fl.run();
}
