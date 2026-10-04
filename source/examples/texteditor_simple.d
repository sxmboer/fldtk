// D transliteration of FLTK's examples/texteditor-simple.cxx (~/Repositories/fltk).
// Part of the samples/ contract -- see samples/README.md.
// Check: ./samples/build.sh texteditor-simple
import fl;

void main()
{
    auto win = new DoubleWindow(640, 480, "Simple TextEditor");
//    auto win = new Window(640, 480, "Simple TextEditor");

    auto buff = new TextBuffer();
    auto edit = new TextEditor(20, 20, 640 - 40, 480 - 40);
    edit.buffer(buff); // attach the text buffer to our editor widget
    win.resizable(edit);
    win.show();
    buff.text("line 0\nline 1\nline 2\n"
            ~ "line 3\nline 4\nline 5\n"
            ~ "line 6\nline 7\nline 8\n"
            ~ "line 9\nline 10\nline 11\n"
            ~ "line 12\nline 13\nline 14\n"
            ~ "line 15\nline 16\nline 17\n"
            ~ "line 18\nline 19\nline 20\n"
            ~ "line 21\nline 22\nline 23\n");
    fl.run();
}
