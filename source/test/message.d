// D transliteration of FLTK's test/message.cxx (~/Repositories/fltk).
// Part of the samples/ contract -- see samples/README.md.
// Check: ./samples/build.sh message
import fl;
import std.stdio : writefln;
import std.format : format;

void main(string[] args)
{
    scheme(null);
    fl.args(args);
    fl.getSystemColors();

    fl.ask.message(format("Spelling check sucessful, %d errors found with %g%% confidence",
               1002, 100 * (15 / 77.0)));

    alert(format("Quantum fluctuations in the space-time continuum detected,\n"
             ~ "you have %g seconds to comply.\n\n"
             ~ "\"In physics, spacetime is any mathematical model that combines\n"
             ~ "space and time into a single construct called the space-time\n"
             ~ "continuum. Spacetime is usually interpreted with space being\n"
             ~ "three-dimensional and time playing the role of the\n"
             ~ "fourth dimension.\" - Wikipedia",
             10.0));

    writefln("choice returned %d",
        choice(format("Do you really want to %s?", "continue"), "No", "Yes", null));

    writefln("choice returned %d",
        choice("Choose one of the following:", "choice0", "choice1", "choice2"));

    string r;

    r = fl_input(format("Please enter a string for '%s':", "testing"), "this is the default value");
    writefln("fl_input returned \"%s\"", r ? r : "NULL");

    r = password(format("Enter %s's password:", "somebody"), null);
    writefln("password returned \"%s\"", r ? r : "NULL");
}
