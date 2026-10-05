// D transliteration of FLTK's test/demo.cxx.
// Build: rdmd buildsamples.d test demo
//
// Notes on this transliteration:
//  - Only the Unix/Linux path-handling and process-launch branches are
//    transliterated (this project's primary target -- see CONVENTIONS.md);
//    FLTK's _WIN32 CreateProcess() branch and the macOS
//    "open '/path/app.app'" bundle branch are dropped entirely, the same
//    way source/test/sudoku.d keeps only the ALSA branch of its sound
//    backend. The CMAKE_INTDIR (Visual Studio/Xcode multi-config build
//    type subdirectory) handling is dropped too -- this project builds
//    with dub, which has no equivalent concept.
//  - Fl_Terminal, Fl_Menu_Button, Fl_Scheme_Choice have no fldtk
//    equivalent yet (no menu subsystem, no terminal widget -- see
//    PORTING.md); Terminal/MenuButton/SchemeChoice below reuse the
//    names already established by source/examples/simple_terminal.d,
//    source/examples/howto_menu_with_images.d, and
//    source/test/boxtype.d respectively. Terminal.historyLines()/
//    displayRows()/displayColumns()/textsize() are new invented methods
//    (camelCase of FLTK's history_lines()/display_rows()/
//    display_columns()/textsize()) following the same convention.
//  - fl_chdir()/fl_getcwd()/fl_putenv() are plain cross-platform libc
//    wrappers, not FLTK widget/drawing API, so they're written directly
//    against Phobos (std.file.chdir/getcwd, std.process.environment,
//    fl.stdc.stdlib.exit) rather than invented as fldtk calls -- the
//    same reasoning source/examples/table_sort.d (std.process) and
//    source/examples/nativefilechooser_simple_app.d (std.process/
//    std.path) already apply, and fl.filename's own source imports
//    std.file's getcwd() for the same reason. fl_filename_absolute()/
//    fl_filename_name()/fl_filename_setext() DO have a real fldtk
//    equivalent (fl.filename, D-`string`-returning, not the C
//    buffer+length API) and are used as such below.
//  - FLTK's dobut()/popup_menu_cb() callbacks take a `long`/`void*`
//    argument for the button/menu index; per CONVENTIONS.md's callback
//    convention these become delegates that capture the index directly,
//    with no void*/long round-trip.
//  - FLTK's system()-based process launch (a shell command string,
//    backgrounded with a trailing " &") becomes std.process.spawnProcess()
//    with a real argv array -- launches the child directly, no
//    intermediate shell, already non-blocking on every platform with
//    no "&"/shell-backgrounding syntax needed at all (that syntax is
//    Unix-shell-specific and would need a different mechanism on
//    Windows).
import fl;
import std.process : spawnProcess, environment;
import std.file : chdir, getcwd;
import std.stdio : File;
import std.string : indexOf, startsWith, strip, split;
import std.format : format;
import std.path : dirName, buildPath, dirSeparator;

enum int FORM_W = 350;
enum int FORM_H = 440;
enum int TTY_W = 780;
enum int TTY_H = 200;

DoubleWindow form;
FlGroup demogrp;
Terminal tty;
SchemeChoice schemeChoice;
Button[9] but;
Button exitButton;

// Global path variables (Unix/Linux only -- see the file header note).
string appPath;     // directory of all demo binaries
string fluidPath;   // binary directory of fluid
string optionsPath; // binary directory of fltk-options
string dataPath;    // working directory of all demos

enum string suffix = ""; // Linux: no executable suffix (see file header note)

// debug output function
void debugVar(string varname, string value)
{
    tty.printf("%-10s = %s\n", varname, value);
}

// Show or hide the tty window. Generally this could be much simpler
// but the extra space (10 px) at the bottom needs "special care"
void showTty(bool val)
{
    if (val)
    {
        tty.show();                                 // show debug terminal
        form.sizeRange(FORM_W, FORM_H + TTY_H / 2, 0, 0); // allow resizing
        form.size(TTY_W + 20, FORM_H + TTY_H + 10);  // demo + height for tty + space (10)
        tty.size(TTY_W, TTY_H);                      // force tty size
    }
    else
    {
        tty.hide();                                  // hide debug terminal
        form.sizeRange(FORM_W, FORM_H, FORM_W, FORM_H); // no resizing
        form.size(FORM_W, FORM_H);                   // normal demo size
        tty.resize(10, FORM_H - 1, FORM_W - 20, 1);  // restore original position and size
    }
    form.initSizes();
    exitButton.takeFocus();
}

// Right click popup menu handler
void popupMenuCb(bool show)
{
    showTty(show);
}

void createTheForms()
{
    form = new DoubleWindow(FORM_W, FORM_H, "FLTK Demonstration");

    // Parent group for demo
    demogrp = new FlGroup(0, 0, FORM_W, FORM_H - 1);

    // Top demo button
    Widget obj = new Box(Boxtype.engravedBox, 10, 15, 330, 40, "FLTK Demonstration");
    obj.color(gray - 4);
    obj.labelsize(24);
    obj.labelfont(bold);
    obj.labeltype(Labeltype.engravedLabel);

    obj = new Box(Boxtype.engravedBox, 10, 65, 330, 330, null);
    obj.color(gray - 8);

    schemeChoice = new SchemeChoice(90, 405, 100, 25, "Scheme:");
    schemeChoice.labelfont(helveticaBold);

    exitButton = new Button(280, 405, 60, 25, "Exit");
    exitButton.callback((w) { doexit(w); });
    exitButton.takeFocus();

    obj = new Button(10, 15, 330, 380);
    obj.type(hiddenButton);
    obj.callback((w) { doback(w); });
    obj.tooltip("Use right mouse button to show/hide debug terminal");

    but[0] = new Button( 30, 85, 90, 90);
    but[1] = new Button(130, 85, 90, 90);
    but[2] = new Button(230, 85, 90, 90);
    but[3] = new Button( 30,185, 90, 90);
    but[4] = new Button(130,185, 90, 90);
    but[5] = new Button(230,185, 90, 90);
    but[6] = new Button( 30,285, 90, 90);
    but[7] = new Button(130,285, 90, 90);
    but[8] = new Button(230,285, 90, 90);

    foreach (i, b; but)
    {
        b.alignment(alignWrap);
        // dobutCallback(idx) (not a delegate literal written directly
        // here) deliberately -- see that function's own comment: DMD
        // shares one closure frame across every delegate literal
        // created inside a loop body, so all 9 buttons would otherwise
        // capture the same (last) `i`.
        b.callback(dobutCallback(cast(int) i));
    }

    // Right click popup menu (inside demogrp)
    auto popup = new MenuButton(0, 0, FORM_W, FORM_H);
    popup.box(Boxtype.noBox);
    popup.type(MenuButton.PopupButtons.popup3); // pop menu on right-click
    popup.add("Show debug terminal", 0, (w) { popupMenuCb(true); });
    popup.add("Hide debug terminal", 0, (w) { popupMenuCb(false); });

    // The resizable box of 'demogrp' ensures that the demo form is not resized
    // if the user resizes the window while the debug terminal (tty) is shown
    obj = new Box(FORM_W - 1, 0, 1, FORM_H);
    obj.box(Boxtype.noBox);
    demogrp.resizable(obj);

    demogrp.end();

    // Small debug terminal window parented to window, not demogrp
    //    To show/hide debug terminal, use demo's right-click menu
    //
    tty = new Terminal(10, FORM_H - 1, FORM_W - 20, 1);
    tty.historyLines(50);
    tty.displayRows(2);      // make display at least 2 rows high, even if not seen
    tty.displayColumns(100); // make display at least 100 cols wide, even if not seen
    tty.ansi(true);
    tty.hide();
    tty.textsize(12);

    // End window
    form.end();
    form.resizable(tty);

    // Note: do not set sizeRange() before show() or window can't be made
    // resizable later (macOS and Windows only, works on Linux though)
    // form.sizeRange(FORM_W, FORM_H, FORM_W, FORM_H);
}

/* Maintaining and building up the menus. */

struct Menu
{
    string name;
    int numb;
    string[9] iname;
    string[9] icommand;
}

enum int MAXMENU = 32;

Menu[MAXMENU] menus;
int mennumb = 0;

// Return the number of a given menu name.
int findMenu(string nnn)
{
    foreach (i; 0 .. mennumb)
        if (menus[i].name == nnn) return i;
    return -1;
}

// Create a new menu with name nnn
void createMenu(string nnn)
{
    if (mennumb == MAXMENU - 1) return;
    menus[mennumb].name = nnn;
    menus[mennumb].numb = 0;
    mennumb++;
}

// Add an item to a menu
void addtoMenu(string men, string item, string comm)
{
    int n = findMenu(men);
    if (n < 0) { createMenu(men); n = findMenu(men); }
    if (menus[n].numb == 9) return;
    menus[n].iname[menus[n].numb] = item;
    menus[n].icommand[menus[n].numb] = comm;
    menus[n].numb++;
}

/* Button to Item conversion and back. */

immutable int[9][9] b2n = [
    [ -1, -1, -1, -1,  0, -1, -1, -1, -1],
    [ -1, -1, -1,  0, -1,  1, -1, -1, -1],
    [  0, -1, -1, -1,  1, -1, -1, -1,  2],
    [  0, -1,  1, -1, -1, -1,  2, -1,  3],
    [  0, -1,  1, -1,  2, -1,  3, -1,  4],
    [  0, -1,  1,  2, -1,  3,  4, -1,  5],
    [  0, -1,  1,  2,  3,  4,  5, -1,  6],
    [  0,  1,  2,  3, -1,  4,  5,  6,  7],
    [  0,  1,  2,  3,  4,  5,  6,  7,  8],
];
immutable int[9][9] n2b = [
    [  4, -1, -1, -1, -1, -1, -1, -1, -1],
    [  3,  5, -1, -1, -1, -1, -1, -1, -1],
    [  0,  4,  8, -1, -1, -1, -1, -1, -1],
    [  0,  2,  6,  8, -1, -1, -1, -1, -1],
    [  0,  2,  4,  6,  8, -1, -1, -1, -1],
    [  0,  2,  3,  5,  6,  8, -1, -1, -1],
    [  0,  2,  3,  4,  5,  6,  8, -1, -1],
    [  0,  1,  2,  3,  5,  6,  7,  8, -1],
    [  0,  1,  2,  3,  4,  5,  6,  7,  8],
];

// Transform a button number to an item number when there are
// maxnumb items in total. -1 if the button should not exist.
int but2numb(int bnumb, int maxnumb) { return b2n[maxnumb][bnumb]; }

// Transform an item number to a button number when there are
// maxnumb items in total. -1 if the item should not exist.
int numb2but(int inumb, int maxnumb) { return n2b[maxnumb][inumb]; }

/* Pushing and Popping menus */

string[64] stack;
int stsize = 0;

// Push a menu to be visible
void pushMenu(string nnn)
{
    int men = findMenu(nnn);
    if (men < 0) return;
    int n = menus[men].numb;
    foreach (b; but) b.hide();
    for (int i = 0; i < n; i++)
    {
        int bn = numb2but(i, n - 1);
        but[bn].show();
        but[bn].label(menus[men].iname[i]);
        if (menus[men].icommand[i].length && menus[men].icommand[i][0] != '@')
            but[bn].tooltip(menus[men].icommand[i]);
        else
            but[bn].tooltip(null);
    }
    stack[stsize] = nnn;
    stsize++;
}

// Pop a menu
void popMenu()
{
    if (stsize <= 1) return;
    stsize -= 2;
    pushMenu(stack[stsize]);
}

/* The callback Routines */

// Builds button `idx`'s callback as a real per-call function
// invocation rather than a delegate literal written directly inside
// the button-construction loop above -- DMD allocates a single closure
// frame for delegate literals created inside a loop body and reuses it
// every iteration, so all 9 buttons would otherwise capture the same
// (final-iteration) index. Same fix pattern as
// fl.ask.MessageDialog.buttonCallback().
Callback dobutCallback(int idx)
{
    return (w) { dobut(idx); };
}

// Handle a button push
void dobut(int arg)
{
    int men = findMenu(stack[stsize - 1]);
    int n = menus[men].numb;
    int bn = but2numb(arg, n - 1);

    // menu ?
    if (menus[men].icommand[bn].length && menus[men].icommand[bn][0] == '@')
    {
        pushMenu(menus[men].icommand[bn]);
        return;
    }

    // not a menu: run test/demo/fluid executable
    // find and separate "command" and "params"

    // skip leading spaces in command
    string startCommand = menus[men].icommand[bn].strip();

    string cmdbuf, params;

    // find the space between the command and parameters if one exists
    auto spacePos = startCommand.indexOf(' ');
    if (spacePos >= 0)
    {
        cmdbuf = startCommand[0 .. spacePos];   // command w/o params
        params = startCommand[spacePos + 1 .. $]; // parameters
    }
    else
    {
        cmdbuf = startCommand;
        params = "";
    }

    // select application path: either app_path, fluid_path, or options_path
    string path = appPath;
    if (cmdbuf.startsWith("fluid"))
        path = fluidPath;
    else if (cmdbuf.startsWith("fltk-options"))
        path = optionsPath;

    // format commandline with optional parameters (other platforms:
    // Unix/Linux, X11, and XQuartz on macOS -- see file header note)
    string exePath = path ~ "/" ~ cmdbuf ~ suffix;
    string[] argv = params.length ? [exePath] ~ params.split() : [exePath];
    string command = params.length ? exePath ~ " " ~ params : exePath;

    // finally, execute program in the background
    debugVar("Command", command);

    // spawnProcess() launches the child directly (no intermediate
    // shell), so it's already non-blocking on every platform with no
    // shell-backgrounding syntax needed at all -- unlike FLTK's own
    // system()-based launch (a shell command string plus a trailing
    // " &"), which is Unix-shell-specific.
    try
        spawnProcess(argv);
    catch (Exception e)
        alert("Could not start program: " ~ e.msg ~ "\n'" ~ command ~ "'");
}

void doback(Widget widget) { popMenu(); }

void doexit(Widget widget) { fl.hideAllWindows(); }

/*
  Load the menu file. Returns whether successful.
*/
bool loadTheMenu(string menu)
{
    File fin;
    try
        fin = File(menu, "r");
    catch (Exception e)
        return false;

    scope(exit) fin.close();

    foreach (rawLine; fin.byLine())
    {
        // remove all carriage returns that Cygwin may have inserted
        char[] line;
        foreach (c; rawLine) if (c != '\r') line ~= c;

        // interpret the line
        size_t i = 0;
        while (i < line.length && (line[i] == ' ' || line[i] == '\t')) i++;
        if (i >= line.length) continue;
        if (line[i] == '#') continue;

        string mname;
        while (i < line.length && line[i] != ':') mname ~= line[i++];
        if (i < line.length && line[i] == ':') i++;

        string iname;
        while (i < line.length && line[i] != ':')
        {
            if (line[i] == '\\')
            {
                i++;
                if (i < line.length && line[i] == 'n') iname ~= '\n';
                else if (i < line.length) iname ~= line[i];
                i++;
            }
            else
                iname ~= line[i++];
        }
        if (i < line.length && line[i] == ':') i++;

        string cname;
        while (i < line.length && line[i] != ':') cname ~= line[i++];

        addtoMenu(mname, iname, cname);
    }
    return true;
}

// Strip the filename off path (if requested), leaving the containing
// directory. Not an FLTK function -- demo.cxx's own fix_path()
// helper, kept as local app logic rather than an fldtk API.
//
// Uses `std.path.dirName()` rather than a manual `'/'`-only scan --
// FLTK's own `fix_path()` (`test/demo.cxx:518-534`) has an `#ifdef
// _WIN32` block that rewrites every `\` to `/` before scanning for the
// last separator to strip; `dirName()` already understands both `/` and
// `\` as separators on every platform Phobos targets, so there's no
// separate Windows branch to maintain here at all.
string fixPath(string path, bool stripFilename = true)
{
    if (path.length == 0) return path;
    if (stripFilename) return dirName(path);
    return path;
}

void main(string[] args)
{
    environment["FLTK_DOCDIR"] = "../documentation/html"; // used by fluid

    // construct app_path for all executable files
    appPath = fixPath(filenameAbsolute(args[0]));

    // fluid's/fltk-options' paths are relative to app_path -- just the
    // parent directory (no CMAKE_INTDIR build-type subdirectory to strip,
    // see the file header note)
    fluidPath = fixPath(appPath);   // remove folder name ("test")
    optionsPath = fixPath(appPath);

    // construct data_path for the menu file and all resources (data files)
    // CMake: replace "/bin/test" with "/data" -- inert for this project's
    // own dub-based build (binaries sit flat in build/, never under a
    // "bin/test" subdirectory on any platform), kept only for parity with
    // FLTK's own CMake-install-layout logic. Separator-aware via
    // `std.path.dirSeparator` rather than a hardcoded "/", matching
    // `fixPath()`'s own fix just above -- see that function's doc comment
    // for why a hardcoded '/'-only search silently never matches on
    // Windows.
    dataPath = appPath;
    auto binTestPos = dataPath.indexOf(dirSeparator ~ "bin" ~ dirSeparator ~ "test");
    if (binTestPos >= 0)
        dataPath = dataPath[0 .. binTestPos] ~ dirSeparator ~ "data";

    // Construct the menu file name, optionally overridden by command args.
    string fn = filenameName(args[0]);
    string menu = filenameSetExt(buildPath(dataPath, fn), ".menu");

    // parse commandline
    int i = 0;
    fl.argsToUtf8(args); // for MSYS2/MinGW
    if (!fl.args(args, i) || i < args.length - 1)
        fl.fatal(format("Usage: %s <switches> <menufile>\n%s", args[0], fl.argsHelp));
    if (i < args.length)
    {
        // override menu file *and* data path!
        menu = filenameAbsolute(args[i]);
        dataPath = fixPath(menu);
    }

    // set current work directory to 'data_path'
    try chdir(dataPath); catch (Exception e) { /* ignore */ }

    // Create forms first
    //    tty needs to exist before we can print debug msgs
    //
    createTheForms();

    {
        string cwd = getcwd();

        debugVar("app_path",     appPath);
        debugVar("fluid_path",   fluidPath);
        debugVar("options_path", optionsPath);
        debugVar("data_path",    dataPath);
        debugVar("menu file",    menu);
        debugVar("cwd",          cwd);
        tty.printf("\n");
    }

    if (!loadTheMenu(menu))
        fl.fatal(format("Can't open menu file '%s'", menu));

    pushMenu("@main");
    form.show(args);

    // set sizeRange() after show() so the window can be resizable (Win + macOS)
    form.sizeRange(FORM_W, FORM_H, FORM_W, FORM_H);

    fl.run();
}
