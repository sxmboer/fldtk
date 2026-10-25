// Helper for the test programs that read a data file (rgb.txt,
// help_dialog.html, demo.menu, ...). Not a program itself.
//
// The data files live in source/test, next to the programs' source;
// the programs are built into build/. dataFile() finds a file there
// relative to the program's own location, so a program finds its data
// whichever folder it is started from.
module data_file;

import std.file : exists, thisExePath;
import std.path : buildNormalizedPath, dirName;

/// The path of the data file `name` in source/test, found from the
/// folder the running program is in (build/). Returns `name` unchanged
/// if it is not there, so an error message still names the file.
string dataFile(string name)
{
    string path = buildNormalizedPath(dirName(thisExePath()), "..", "source", "test", name);
    return exists(path) ? path : name;
}
