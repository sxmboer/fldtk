// D transliteration of FLTK's test/native-filechooser.cxx (~/Repositories/fltk).
// Part of the samples/ contract -- see samples/README.md.
// Check: ./samples/build.sh native-filechooser
import fl;

enum TERMINAL_HEIGHT = 120;

// GLOBALS
Input G_filename;
MultilineInput G_filter;
Terminal G_tty;

void pickFileCb(Widget)
{
    // Create native chooser
    auto native_ = new NativeFileChooser();
    native_.title("Pick a file");
    native_.type(BrowseType.browseFile);
    native_.filter(G_filter.value());
    native_.presetFile(G_filename.value());
    // Show native chooser
    switch (native_.show())
    {
    case -1:
        G_tty.printf("ERROR: %s\n", native_.errmsg());
        break; // ERROR
    case 1:
        G_tty.printf("*** CANCEL\n");
        fl_beep();
        break; // CANCEL
    default: // PICKED FILE
        if (native_.filename())
        {
            G_filename.value(native_.filename());
            G_tty.printf("filename='%s'\n", native_.filename());
        }
        else
        {
            G_filename.value("NULL");
            G_tty.printf("filename='(null)'\n");
        }
        break;
    }
}

void pickFilesCb(Widget)
{
    // Create native chooser
    auto native_ = new NativeFileChooser();
    native_.title("Pick multiple files");
    native_.type(BrowseType.browseMultiFile);
    native_.filter(G_filter.value());
    native_.presetFile(G_filename.value());
    // Show native chooser
    switch (native_.show())
    {
    case -1:
        G_tty.printf("ERROR: %s\n", native_.errmsg());
        break; // ERROR
    case 1:
        G_tty.printf("*** CANCEL\n");
        fl_beep();
        break; // CANCEL
    default: // PICKED FILE
        if (native_.count() > 0)
        {
            G_filename.value(native_.filename(0));
            G_tty.printf("count=%d\n", native_.count());
            for (int i = 0; i < native_.count(); i++)
            {
                G_tty.printf("filename[%d]='%s'\n", i, native_.filename(i));
            }
        }
        else
        {
            G_tty.printf("count=0\n");
        }
        break;
    }
}

void pickDirCb(Widget)
{
    // Create native chooser
    auto native_ = new NativeFileChooser();
    native_.title("Pick a Directory");
    native_.directory(G_filename.value());
    native_.type(BrowseType.browseDirectory);
    // Show native chooser
    switch (native_.show())
    {
    case -1:
        G_tty.printf("ERROR: %s\n", native_.errmsg());
        break; // ERROR
    case 1:
        G_tty.printf("*** CANCEL\n");
        fl_beep();
        break; // CANCEL
    default: // PICKED DIR
        if (native_.filename())
        {
            G_filename.value(native_.filename());
            G_tty.printf("filename='%s'\n", native_.filename());
        }
        else
        {
            G_filename.value("NULL");
            G_tty.printf("filename='(null)'\n");
        }
        break;
    }
}

void pickDirsCb(Widget)
{
    // Create native chooser
    auto native_ = new NativeFileChooser();
    native_.title("Pick multiple directories");
    native_.type(BrowseType.browseMultiDirectory);
    native_.filter(G_filter.value());
    native_.presetFile(G_filename.value());
    // Show native chooser
    switch (native_.show())
    {
    case -1:
        G_tty.printf("ERROR: %s\n", native_.errmsg());
        break; // ERROR
    case 1:
        G_tty.printf("*** CANCEL\n");
        fl_beep();
        break; // CANCEL
    default: // PICKED DIR
        if (native_.count() > 0)
        {
            G_filename.value(native_.filename(0));
            G_tty.printf("count=%d\n", native_.count());
            for (int i = 0; i < native_.count(); i++)
            {
                G_tty.printf("filename[%d]='%s'\n", i, native_.filename(i));
            }
        }
        else
        {
            G_tty.printf("count=0\n");
        }
        break;
    }
}

void saveFileCb(Widget)
{
    // Create native chooser
    auto native_ = new NativeFileChooser();
    native_.title("Save a file");
    native_.type(BrowseType.browseSaveFile);
    native_.filter(G_filter.value());
    native_.presetFile(G_filename.value());
    // Show native chooser
    switch (native_.show())
    {
    case -1:
        G_tty.printf("ERROR: %s\n", native_.errmsg());
        break; // ERROR
    case 1:
        G_tty.printf("*** CANCEL\n");
        fl_beep();
        break; // CANCEL
    default: // PICKED FILE
        if (native_.filename())
        {
            G_filename.value(native_.filename());
            G_tty.printf("filename='%s'\n", native_.filename());
        }
        else
        {
            G_filename.value("NULL");
            G_tty.printf("filename='(null)'\n");
        }
        break;
    }
}

void saveDirCb(Widget)
{
    // Create native chooser
    auto native_ = new NativeFileChooser();
    native_.title("Save a Directory");
    native_.directory(G_filename.value());
    native_.type(BrowseType.browseSaveDirectory);
    // Show native chooser
    switch (native_.show())
    {
    case -1:
        G_tty.printf("ERROR: %s\n", native_.errmsg());
        break; // ERROR
    case 1:
        G_tty.printf("*** CANCEL\n");
        fl_beep();
        break; // CANCEL
    default: // PICKED DIR
        if (native_.filename())
        {
            G_filename.value(native_.filename());
            G_tty.printf("filename='%s'\n", native_.filename());
        }
        else
        {
            G_filename.value("NULL");
            G_tty.printf("filename='(null)'\n");
        }
        break;
    }
}

void main(string[] args)
{
    /* For a nicer looking browser under linux/unix, call fl_register_images()
      (If you do this, you'll need to link with fltk_images).
      That's required for the preview option of the GTK filechooser.
      In the unlikely situation where no native filechooser is found on
      the active Linux system, FLTK reverts to using its own file chooser
      (Fl_File_Chooser) which looks best if you also call
      Fl_File_Icon::load_system_icons().

      None of that is useful for the native file chooser under macOS or Windows.
     */
    version (linux)
    {
        loadSystemIcons();
    }

    int argn = 1;

    // Parse preset filename (if any)
    string filename = null;
    if (args.length > argn && args[argn][0] != '-')
    {
        filename = args[argn++];
    }

    auto win = new Window(640, 400 + TERMINAL_HEIGHT, "Native File Chooser Test");
    win.sizeRange(win.w(), win.h(), 0, 0);
    win.begin();
    {
        G_tty = new Terminal(0, 400, win.w(), TERMINAL_HEIGHT);

        int x = 80, y = 10;
        G_filename = new Input(x, y, win.w() - 80 - 10, 25, "Filename");
        G_filename.value(filename ? filename : ".");
        G_filename.tooltip("Default filename");

        y += G_filename.h() + 10;
        G_filter = new MultilineInput(x, y, G_filename.w(), 100, "Filter");
        G_filter.value("Text\t*.txt\n"
                       ~ "D Files\t*.d\n"
                       ~ "Tars\t*.{tar,tar.gz}\n"
                       ~ "Apps\t*.app");
        G_filter.tooltip("Filter to be used for browser.\n"
                          ~ "An empty string may be used.\n");

        y += G_filter.h() + 10;
        auto view = new HelpView(x, y, G_filename.w(), 200);
        view.box(Boxtype.flatBox);
        view.color(win.color());
        enum TAB = "&lt;Tab&gt;";
        view.textfont(helvetica);
        view.textsize(10);
        view.value("The Filter can be one or more filter patterns, one per line.\n"
                   ~ "Patterns can be:<ul>\n"
                   ~ "  <li>A single wildcard (e.g. <tt>\"*.txt\"</tt>)</li>\n"
                   ~ "  <li>Multiple wildcards (e.g. <tt>\"*.{d,di}\"</tt>)</li>\n"
                   ~ "  <li>A descriptive name followed by a " ~ TAB ~ " and a wildcard (e.g. <tt>\"Text Files" ~ TAB ~ "*.txt\"</tt>)</li>\n"
                   ~ "</ul>\n"
                   ~ "In the above \"Filter\" field, you can use <b><font color=#55f face=Courier>Ctrl-I</font></b> to enter " ~ TAB ~ " characters as needed.<br>\n"
                   ~ "Example:<pre>\n"
                   ~ "\n"
                   ~ "    Text<font color=#55f>&lt;Ctrl-I&gt;</font>*.txt\n"
                   ~ "    D Files<font color=#55f>&lt;Ctrl-I&gt;</font>*.d\n"
                   ~ "    Tars<font color=#55f>&lt;Ctrl-I&gt;</font>*.{tar,tar.gz}\n"
                   ~ "    Apps<font color=#55f>&lt;Ctrl-I&gt;</font>*.app\n"
                   ~ "</pre>\n");

        // pick file, pick files, pick dir, pick dirs, save file, save files
        // browseFile,           ///< browse files (lets user choose one file)
        // browseDirectory,      ///< browse directories (lets user choose one directory)
        // browseMultiFile,      ///< browse files (lets user choose multiple files)
        // browseMultiDirectory, ///< browse directories (lets user choose multiple directories)
        // browseSaveFile,       ///< browse to save a file
        // browseSaveDirectory   ///< browse to save a directory

        auto pickFileW = new Button(win.w() - 600 - 10, win.h() - TERMINAL_HEIGHT - 25 - 10, 80, 25, "Pick File");
        pickFileW.callback((wgt) { pickFileCb(wgt); });

        auto pickFilesW = new Button(win.w() - 500 - 10, win.h() - TERMINAL_HEIGHT - 25 - 10, 80, 25, "Pick Files");
        pickFilesW.callback((wgt) { pickFilesCb(wgt); });

        auto pickDirW = new Button(win.w() - 400 - 10, win.h() - TERMINAL_HEIGHT - 25 - 10, 80, 25, "Pick Dir");
        pickDirW.callback((wgt) { pickDirCb(wgt); });

        auto pickDirsW = new Button(win.w() - 300 - 10, win.h() - TERMINAL_HEIGHT - 25 - 10, 80, 25, "Pick Dirs");
        pickDirsW.callback((wgt) { pickDirsCb(wgt); });

        auto saveFileW = new Button(win.w() - 200 - 10, win.h() - TERMINAL_HEIGHT - 25 - 10, 80, 25, "Save File");
        saveFileW.callback((wgt) { saveFileCb(wgt); });

        auto saveDirW = new Button(win.w() - 100 - 10, win.h() - TERMINAL_HEIGHT - 25 - 10, 80, 25, "Save Dir");
        saveDirW.callback((wgt) { saveDirCb(wgt); });

        win.resizable(G_filter);
    }
    win.end();
    // Pass show() remaining args we haven't already parsed..
    win.show();
    fl.run();
}
