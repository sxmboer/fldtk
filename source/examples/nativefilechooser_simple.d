// D transliteration of FLTK's examples/nativefilechooser-simple.cxx.
// Build: rdmd buildsamples.d examples nativefilechooser_simple
import fl;
import std.stdio : writefln;
import std.format : format;

Window gWin;
MenuButton gMenu;
NativeFileChooser gChooser;

void main()
{
    scheme("gtk+");
    gWin = new Window(640, 480, "Test Native File Chooser");
    gWin.tooltip("Use right-click for popup menu..");
    {
        // Setup right-click menu for window..
        gMenu = new MenuButton(0, 20, 640, 480, "Popup Menu");
        gMenu.type(MenuButton.PopupButtons.popup3);
        gMenu.add("Open File Chooser..", 0, (w) {
            if (gChooser is null)
            {
                // Create an instance of file chooser we can reuse..
                gChooser = new NativeFileChooser();
                gChooser.directory(".");                                 // directory to start browsing with
                gChooser.presetFile("nativefilechooser_simple.d");        // file to start with
                gChooser.filter("D\t*.d\n");
                gChooser.type(BrowseType.browseFile);              // only picks files that exist
                gChooser.title("Pick a file please..");                  // custom title for chooser window
            }
            // Show the chooser
            //    This blocks while chooser is open.
            switch (gChooser.show())
            {
            case -1:
                break; // Error
            case 1:
                break; // Cancel
            default: // Choice
                gChooser.presetFile(gChooser.filename());
                message(format("You chose: %s", gChooser.filename()));
                break;
            }
        });
        gMenu.add("Quit", 0, (w) { fl.hideAllWindows(); });
    }
    gWin.end();
    gWin.show();
    fl.run();
}
