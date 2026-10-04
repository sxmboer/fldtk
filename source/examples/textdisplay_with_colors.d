// D transliteration of FLTK's examples/textdisplay-with-colors.cxx (~/Repositories/fltk).
// Part of the samples/ contract -- see samples/README.md.
// Check: ./samples/build.sh textdisplay-with-colors
import fl;

void main()
{
    // Style table
    StyleTableEntry[] stable = [
        // FONT COLOR   FONT FACE   FONT SIZE
        StyleTableEntry(red, courier, 18), // A - Red
        StyleTableEntry(darkYellow, courier, 18), // B - Yellow
        StyleTableEntry(darkGreen, courier, 18), // C - Green
        StyleTableEntry(blue, courier, 18), // D - Blue
    ];
    auto win = new Window(640, 480, "Simple Text Display With Colors");
    auto disp = new TextDisplay(20, 20, 640 - 40, 480 - 40);
    auto tbuff = new TextBuffer(); // text buffer
    auto sbuff = new TextBuffer(); // style buffer
    disp.buffer(tbuff);
    disp.highlightData(sbuff, stable, 'A', null);
    // Text
    tbuff.text("Red Line 1\nYel Line 2\nGrn Line 3\nBlu Line 4\n"
            ~ "Red Line 5\nYel Line 6\nGrn Line 7\nBlu Line 8\n");
    // Style for text
    sbuff.text("AAAAAAAAAA\nBBBBBBBBBB\nCCCCCCCCCC\nDDDDDDDDDD\n"
            ~ "AAAAAAAAAA\nBBBBBBBBBB\nCCCCCCCCCC\nDDDDDDDDDD\n");
    win.resizable(disp);
    win.show();
    fl.run();
}
