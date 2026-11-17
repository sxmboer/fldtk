// fldtk's Markdown viewer: MarkdownDialog showing a Markdown file.
// Build: rdmd buildsamples.d test markdown_viewer
// Run:   build/markdown_viewer [file.md]
//
// Shows the file given, or else fldtk's README.md (from the current
// folder, or the fldtk folder above build/). Links to other .md files
// open in the same window; Back and Forward go through the pages
// visited.
import fl;
import std.file : exists, thisExePath;
import std.path : buildPath, dirName;
import std.stdio : stderr;

int main(string[] args)
{
    string file = args.length > 1 ? args[1] : "README.md";
    if (args.length < 2 && !exists(file))
        file = buildPath(dirName(dirName(thisExePath())), "README.md");
    if (!exists(file))
    {
        stderr.writeln("markdown_viewer: there is no ", file);
        return 1;
    }

    auto dialog = new MarkdownDialog();
    dialog.load(file);
    dialog.show();
    fl.run();
    return 0;
}
