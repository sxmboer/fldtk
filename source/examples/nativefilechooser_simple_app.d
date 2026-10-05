// D transliteration of FLTK's examples/nativefilechooser-simple-app.cxx.
// Build: rdmd buildsamples.d examples nativefilechooser_simple_app
import fl;
import std.stdio : File, writefln;
import std.string : empty;
import std.format : format;

class Application : Window
{
    private NativeFileChooser fc;

    // Does file exist?
    private bool exist(string filename)
    {
        try
        {
            auto f = File(filename, "r");
            f.close();
            return true;
        }
        catch (Exception)
        {
            return false;
        }
    }

    // 'Open' the file
    private void open(string filename)
    {
        writefln("Open '%s'", filename);
    }

    // 'Save' the file
    //    Create the file if it doesn't exist
    //    and save something in it.
    private void save(string filename)
    {
        writefln("Saving '%s'", filename);
        if (!exist(filename))
        {
            try
            {
                auto f = File(filename, "w"); // create file if it doesn't exist
                // A real app would do something useful here.
                f.writefln("Hello world.");
                f.close();
            }
            catch (Exception e)
            {
                message(format("Error: %s: %s", filename, e.msg));
            }
        }
        else
        {
            // A real app would do something useful here.
        }
    }

    // Handle an 'Open' request from the menu
    private void openCb(Widget w)
    {
        fc.title("Open");
        fc.type(BrowseType.browseFile); // only picks files that exist
        switch (fc.show())
        {
        case -1:
            break; // Error
        case 1:
            break; // Cancel
        default: // Choice
            fc.presetFile(fc.filename());
            open(fc.filename());
            break;
        }
    }

    // Handle a 'Save as' request from the menu
    private void saveasCb(Widget w)
    {
        fc.title("Save As");
        fc.type(BrowseType.browseSaveFile); // need this if file doesn't exist yet
        switch (fc.show())
        {
        case -1:
            break; // Error
        case 1:
            break; // Cancel
        default: // Choice
            fc.presetFile(fc.filename());
            save(fc.filename());
            break;
        }
    }

    // Handle a 'Save' request from the menu
    private void saveCb(Widget w)
    {
        if (fc.filename().empty)
            saveasCb(w);
        else
            save(fc.filename());
    }

    private static void quitCb(Widget w)
    {
        fl.hideAllWindows();
    }

    // Return an 'untitled' default pathname
    private string untitledDefault()
    {
        import std.process : environment;
        import std.path : buildPath;

        // "HOME" on Linux/macOS; Windows has no environment variable of
        // that name, but always sets "USERPROFILE" to the user's home
        // directory (unlike the previous "HOME_PATH" fallback here,
        // which isn't a real Windows variable either and was always a
        // no-op).
        string home = environment.get("HOME", environment.get("USERPROFILE", "."));
        return buildPath(home, "untitled.txt");
    }

public:
    // CTOR
    this()
    {
        super(400, 200, "Native File Chooser Example");
        auto menu = new MenuBar(0, 0, 400, 25);
        menu.add("&File/&Open", fl.stateCommand + 'o', (w) { openCb(w); });
        menu.add("&File/&Save", fl.stateCommand + 's', (w) { saveCb(w); });
        menu.add("&File/&Save As", 0, (w) { saveasCb(w); });
        menu.add("&File/&Quit", fl.stateCommand + 'q', (w) { quitCb(w); });
        // Describe the demo..
        auto box = new Box(20, 25 + 20, w() - 40, h() - 40 - 25);
        box.color(cast(Color) 45);
        box.box(Boxtype.flatBox);
        box.alignment(alignCenter | alignInside | alignWrap);
        box.label("This demo shows an example of implementing "
                ~ "common 'File' menu operations like:\n"
                ~ "    File/Open, File/Save, File/Save As\n"
                ~ "..using the NativeFileChooser widget.\n\n"
                ~ "Note 'Save' and 'Save As' really *does* create files! "
                ~ "This is to show how behavior differs when "
                ~ "files exist vs. do not.");
        box.labelsize(12);
        // Initialize the file chooser
        fc = new NativeFileChooser();
        fc.filter("Text\t*.txt\n");
        fc.presetFile(untitledDefault());
        end();
    }
}

void main()
{
    scheme("gtk+");
    auto app = new Application();
    app.show();
    fl.run();
}
