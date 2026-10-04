// D transliteration of FLTK's examples/texteditor-with-dynamic-colors.cxx
// (~/Repositories/fltk).
// Part of the samples/ contract -- see samples/README.md.
// Check: ./samples/build.sh texteditor-with-dynamic-colors
import fl;
import std.ascii : isDigit;

// Custom class to demonstrate a specialized text editor
class MyEditor : TextEditor
{
    TextBuffer tbuff; // text buffer
    TextBuffer sbuff; // style buffer

    // Modify callback handler
    void modifyCallback(int pos, // position of update
            int nInserted, // number of inserted chars
            int nDeleted, // number of deleted chars
            int nRestyled, // number of restyled chars (unused here)
            const(char)[] deletedText) // text deleted (unused here)
    {
        // Nothing inserted or deleted?
        if (nInserted == 0 && nDeleted == 0)
            return;

        // Characters inserted into tbuff?
        //     Insert same number of chars into style buffer..
        if (nInserted > 0)
        {
            char[] style;
            style.length = nInserted;
            style[] = 'A'; // init style to "A"s
            sbuff.insert(pos, cast(string) style); // insert "A"s into style buffer
        }

        // Characters deleted from tbuff?
        //    Delete same number of chars from style buffer..
        if (nDeleted > 0)
        {
            sbuff.remove(pos, pos + nDeleted);
            return; // nothing more to do; deleting won't affect our single char coloring
        }

        // Focus on characters inserted
        int start = pos;
        int end = pos + nInserted;

        // SIMPLE EXAMPLE:
        //     Color the digits 0-4 in green, 5-9 in red.
        foreach (i; start .. end)
        {
            uint c = tbuff.charAt(i);
            if (c >= '0' && c <= '4')
                sbuff.replace(i, i + 1, "B"); // style 'B' (green)
            else if (c >= '5' && c <= '9')
                sbuff.replace(i, i + 1, "C"); // style 'C' (red)
            else
                sbuff.replace(i, i + 1, "A"); // style 'A' (black)
        }
    }

public:
    this(int X, int Y, int W, int H)
    {
        super(X, Y, W, H);
        // Style table for the respective styles
        StyleTableEntry[] stable = [
            // FONT COLOR    FONT FACE   FONT SIZE
            StyleTableEntry(black, courier, 14), // A - Black
            StyleTableEntry(darkGreen, courier, 14), // B - Green
            StyleTableEntry(red, courier, 14), // C - Red
        ];
        tbuff = new TextBuffer(); // text buffer
        sbuff = new TextBuffer(); // style buffer
        buffer(tbuff);
        highlightData(sbuff, stable, 'A', null);
        tbuff.addModifyCallback((pos, nInserted, nDeleted, nRestyled, deletedText) {
            modifyCallback(pos, nInserted, nDeleted, nRestyled, deletedText);
        });
    }

    void text(string val)
    {
        tbuff.text(val);
    }
}

void main()
{
    auto win = new Window(720, 480, "Text Editor With Dynamic Coloring");
    auto med = new MyEditor(10, 10, win.w() - 20, win.h() - 20);
    // Initial text in editor.
    med.text("In this editor, digits 0-4 are shown in green, 5-9 shown in red.\n"
            ~ "So here's some numbers 0123456789.\n"
            ~ "Coloring is handled automatically by the add_modify_callback().\n"
            ~ "\n"
            ~ "You can type here to test. ");
    win.resizable(med);
    win.show();
    fl.run();
}
