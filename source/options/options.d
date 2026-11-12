/*
 * fldtk-options: shows and changes the settings every fldtk program
 * reads when it starts, for this user or for every user of the computer:
 * the on/off options (`fl.core.Option`) and the scheme, zoom, display
 * backend and graphics (`fl.core.startupSetting()`).
 *
 * Build: dub build fldtk:options   (puts ./fldtk-options in the repo root)
 *
 * Each setting has a "System" and a "User" value, either one of its
 * choices or "default". A program takes the user value if there is one,
 * otherwise the system value, otherwise the default. For the scheme,
 * zoom, backend and graphics an environment variable (`FLDTK_SCHEME`,
 * `FLDTK_SCALING_FACTOR`, `FLDTK_BACKEND`, `FLDTK_GRAPHICS`) comes before
 * both, for a single run or a script. Ctrl +/-/0 in any fldtk program
 * store the user's zoom.
 *
 * The values are stored in the "options" group of the `fldtk`/`options`
 * preferences: `~/.config/fldtk/options.prefs` and
 * `/etc/fldtk/fldtk/options.prefs` on Linux, `%APPDATA%` and the common
 * application data folder on Windows. A value that can't be written (the
 * system file, usually) is shown but can't be changed. A change applies
 * to programs started afterwards.
 *
 * Started with switches it changes or prints values without opening a
 * window; `fldtk-options -h` lists them.
 */
module options;

import fl;
import std.stdio : writefln, writeln, stderr;
import std.string : toLower, indexOf;
import std.uni : icmp;
import std.functional : toDelegate;
import std.conv : to;

/// One setting as fldtk-options shows it.
struct Entry
{
    string heading;  /// non-empty for the first setting under a heading
    string name;     /// command-line name
    string key;      /// preferences key
    string title;    /// bold name in the window
    string brief;    /// one line, also printed by `-h`
    string help;     /// the longer explanation
    string[] labels; /// the choices, as shown
    string[] values; /// the choices, as stored (same order as labels)
    string defaultLabel; /// what "default" means
    string envVar;   /// environment variable that overrides it, or null
    bool anyNumber;  /// any positive number is a valid value (the zoom)
}

/// The zoom steps of Ctrl +/- (`fl.core`'s scale handler).
immutable float[] zoomSteps = [0.5f, 2f / 3, 0.8f, 0.9f, 1.0f, 1.1f, 1.2f,
    4f / 3, 1.5f, 1.7f, 2.0f, 2.4f, 3.0f];

string percent(float f)
{
    import std.math : round;
    return (cast(int) round(f * 100)).to!string ~ "%";
}

/// `name` is the option's `Option` member name, written out:
/// `to!string` on an `Option` would visit every member, the deprecated
/// one too.
Entry boolEntry(string heading, Option opt, string name, string title, string brief, string help)
{
    return Entry(heading, name, optionKey(opt), title, brief, help,
        ["off", "on"], ["0", "1"], optionDefault(opt) ? "on" : "off");
}

Entry[] makeEntries()
{
    Entry[] e;
    e ~= boolEntry("Keyboard focus", Option.visibleFocus, "visibleFocus", "Visible keyboard focus",
        "Mark the widget that has the keyboard focus.",
        "When on, a dotted rectangle is drawn inside the widget that receives "
        ~ "the next key press, and Tab moves the focus from widget to widget. "
        ~ "When off, no rectangle is drawn and clicking a button, slider or "
        ~ "list doesn't give it the keyboard focus.");
    e ~= boolEntry("", Option.arrowFocus, "arrowFocus", "Arrow keys move the focus",
        "Left and Right leave a text field at its start or end.",
        "When on, moving the text cursor past the start or end of a text field "
        ~ "with the arrow keys moves the focus to the previous or next widget. "
        ~ "When off, the cursor stops at the end of the text, and Tab moves "
        ~ "the focus.");
    e ~= boolEntry("Tooltips", Option.showTooltips, "showTooltips", "Show tooltips",
        "Show a widget's tooltip when the mouse rests on it.",
        "When on, resting the mouse on a widget that has a tooltip opens a "
        ~ "small window with that text until the mouse leaves the widget. When "
        ~ "off, no tooltips are shown.");
    e ~= boolEntry("Drag and drop", Option.dndText, "dndText", "Drag selected text",
        "Selected text can be dragged to another place or program.",
        "When on, text selected in a text field or editor can be dragged with "
        ~ "the mouse, within the program or into another one. When off, text "
        ~ "can't be dragged out, but text dragged in from other programs is "
        ~ "still accepted.");

    e ~= Entry("Appearance", "scheme", "Scheme", "Scheme",
        "The look of programs that don't choose a scheme themselves.",
        "The scheme gives buttons, boxes and sliders their look. A program "
        ~ "that sets its own scheme keeps it.",
        ["base", "plastic", "gtk+", "gleam", "oxy"],
        ["base", "plastic", "gtk+", "gleam", "oxy"], "base", "FLDTK_SCHEME");
    string[] zl, zv;
    foreach (f; zoomSteps)
    {
        zl ~= percent(f);
        zv ~= f.to!string;
    }
    e ~= Entry("", "zoom", "Zoom", "Zoom",
        "The zoom programs start with, on top of the desktop's scale.",
        "Ctrl and '+', '-' or '0' change the zoom of a running program and "
        ~ "store it as your value here, so the next program starts with it.",
        zl, zv, "100%", "FLDTK_SCALING_FACTOR", true);
    e ~= boolEntry("", Option.showScaling, "showScaling", "Show the zoom factor",
        "Briefly show the new zoom factor when it changes.",
        "When on, zooming a window with Ctrl and '+', '-' or '0' shows the new "
        ~ "zoom factor in a small window for a moment. When off, nothing is "
        ~ "shown.");

    version (linux)
    {
        // "automatic" is a choice of its own, not only the default, so a
        // user can undo a system value of X11 or Wayland.
        e ~= Entry("Display", "backend", "Backend", "Display backend",
            "Whether programs run on X11 or on Wayland.",
            "By default a program uses Wayland when the desktop offers it and "
            ~ "X11 otherwise. If Wayland is asked for here but isn't available, "
            ~ "X11 is used.",
            ["automatic", "X11", "Wayland"], ["auto", "x11", "wayland"],
            "automatic", "FLDTK_BACKEND");
        e ~= Entry("", "graphics", "Graphics", "Graphics on X11",
            "How programs draw on X11: Xlib, or Cairo with Pango text.",
            "Xlib draws without antialiasing and shows text with Xft. Cairo "
            ~ "draws antialiased and shows text with Pango, which also finds "
            ~ "emoji and other characters in fallback fonts. On Wayland "
            ~ "programs always draw with Cairo.",
            ["Xlib", "Cairo"], ["xlib", "cairo"], "Xlib", "FLDTK_GRAPHICS");
    }
    return e;
}

Entry[] entries;

// ---- reading and writing the values -----------------------------------

enum Context { system, user }

private Root rootOf(Context ctx)
{
    return ctx == Context.system ? rootCoreSystemL : rootCoreUserL;
}

/// The stored value of `e`, or null when there is none.
string getValue(Context ctx, ref const Entry e)
{
    auto prefs = new Preferences(rootOf(ctx), "fldtk", "options");
    auto group = new Preferences(prefs, "options");
    string value;
    group.get(e.key, value, "");
    return value.length ? value : null;
}

/// Stores `value` for `e`, or removes the value for null. Returns false
/// if the file couldn't be written.
bool setValue(Context ctx, ref const Entry e, string value)
{
    auto prefs = new Preferences(rootOf(ctx), "fldtk", "options");
    auto group = new Preferences(prefs, "options");
    if (value is null)
        group.deleteEntry(e.key);
    else
        group.set(e.key, value);
    return prefs.flush() == 0;
}

/// The index in `e.values` of `value`, or -1. Numbers are compared as
/// numbers, so "1.5" and "1.50" are the same zoom.
int indexOfValue(ref const Entry e, string value)
{
    import std.math : abs;
    foreach (i, v; e.values)
    {
        if (icmp(v, value) == 0) return cast(int) i;
        if (e.anyNumber)
        {
            float a, b;
            if (parseNumber(v, a) && parseNumber(value, b) && abs(a - b) < 1e-3)
                return cast(int) i;
        }
    }
    return -1;
}

bool parseNumber(string s, out float f)
{
    try
    {
        f = s.to!float;
        return f > 0;
    }
    catch (Exception)
        return false;
}

/// Whether the settings file for `ctx` can be written: the file itself
/// if it exists, otherwise the nearest folder above it that exists (the
/// missing folders are created when the file is first written).
bool canWrite(Context ctx)
{
    import std.file : exists, isDir, remove;
    import std.path : dirName, buildPath;
    import std.stdio : File;

    string path;
    preferencesFilename(path, rootOf(ctx), "fldtk", "options");
    if (path.length == 0) return false;
    try
    {
        if (exists(path))
        {
            File(path, "r+").close();
            return true;
        }
        string dir = dirName(path);
        while (!exists(dir))
        {
            string up = dirName(dir);
            if (up == dir) return false;
            dir = up;
        }
        if (!isDir(dir)) return false;
        string probe = buildPath(dir, ".fldtk-options-write-test");
        File(probe, "w").close();
        remove(probe);
        return true;
    }
    catch (Exception)
        return false;
}

/// The value the environment variable of `e` is set to, or null.
string envValue(ref const Entry e)
{
    import std.process : environment;
    if (e.envVar is null) return null;
    string v = environment.get(e.envVar);
    return v.length ? v : null;
}

// ---- command line ------------------------------------------------------

bool batchMode;   // a switch did the work: don't open the window
bool verbose;
bool forceWrite;  // -f: don't report missing write permission
int exitStatus;

/// The entry named `name` (any case), or null.
const(Entry)* findEntry(string name)
{
    foreach (ref e; entries)
        if (icmp(e.name, name) == 0) return &e;
    return null;
}

/// The values `-S`/`-U` accept for `e`, for messages.
string choicesText(ref const Entry e)
{
    import std.array : join;
    if (e.anyNumber) return "a number such as 1.5, or default";
    if (e.values == ["0", "1"]) return "on, off or default";
    return e.values.join(", ") ~ " or default";
}

void printUsage(string app)
{
    writeln("Usage:");
    writefln("%s [-Sname[=value]] [-Uname[=value]] [-L] [-LS] [-LU] [-f] [-v] [-h[name]]", app);
    writeln("  -Sname[=value]  change or print a value for every user");
    writeln("  -Uname[=value]  change or print a value for this user");
    writeln("      default (or -1) removes the value. Without =value the current value");
    writeln("      is printed, or -1 when there is none.");
    writeln("  -L, -LS, -LU  list all values, the system values, or the user values");
    writeln("  -f  don't report missing permission to write a settings file");
    writeln("  -v, --verbose  say what was done");
    writeln("  -h[name], --help [name]  this text, or more about one setting");
    writeln();
    writeln("Settings (names are not case sensitive):");
    foreach (ref e; entries)
        writefln("  %-20s %s", e.name, e.brief);
    writeln();
    writefln("Without switches %s opens its window.", app);
}

void printInfo(string name)
{
    auto e = findEntry(name);
    if (e is null)
    {
        stderr.writefln("Unknown setting \"%s\"; -h lists them.", name);
        exitStatus = 1;
        return;
    }
    writefln("%s: %s\n\n%s\n\nValues: %s. Default is %s.", e.name, e.brief, e.help,
        choicesText(*e), e.defaultLabel);
    if (e.envVar !is null)
        writefln("The environment variable %s comes before both values.", e.envVar);
}

void listValues(char which)
{
    import std.format : format;
    foreach (ref e; entries)
    {
        string line = format("%-20s", e.name);
        string show(Context c) { auto v = getValue(c, e); return v is null ? "-1" : v; }
        if (which == 'S' || which == 0) line ~= format(" system: %-8s", show(Context.system));
        if (which == 'U' || which == 0) line ~= format(" user: %s", show(Context.user));
        writeln(line);
    }
}

/// Handles `-Sname[=value]`/`-Uname[=value]`.
void handleSetting(Context ctx, string arg)
{
    string where = ctx == Context.system ? "system" : "user";
    string name = arg, val;
    bool print = true;
    auto eq = arg.indexOf('=');
    if (eq >= 0)
    {
        name = arg[0 .. eq];
        val = arg[eq + 1 .. $];
        print = false;
    }
    auto e = findEntry(name);
    if (e is null)
    {
        stderr.writefln("Unknown %s setting \"%s\"; -h lists them.", where, name);
        exitStatus = 1;
        return;
    }
    if (print)
    {
        string v = getValue(ctx, *e);
        if (verbose) writefln("The %s value of %s is %s.", where, e.name, v is null ? "not set" : v);
        else writeln(v is null ? "-1" : v);
        return;
    }

    string value;
    string lower = val.toLower;
    float f;
    if (lower == "default" || lower == "-1")
        value = null;
    else if (e.values == ["0", "1"] && (lower == "on" || lower == "1"))
        value = "1";
    else if (e.values == ["0", "1"] && (lower == "off" || lower == "0"))
        value = "0";
    else if (e.values != ["0", "1"] && indexOfValue(*e, val) >= 0)
        value = e.values[indexOfValue(*e, val)];
    else if (e.anyNumber && parseNumber(val, f))
        value = f.to!string;
    else
    {
        stderr.writefln("Unknown value \"%s\" for %s; use %s.", val, e.name, choicesText(*e));
        exitStatus = 1;
        return;
    }
    if (!forceWrite && !canWrite(ctx))
    {
        stderr.writefln("No permission to write the %s settings.", where);
        exitStatus = 1;
        return;
    }
    if (!setValue(ctx, *e, value) && !forceWrite)
    {
        stderr.writefln("Could not write the %s settings.", where);
        exitStatus = 1;
        return;
    }
    if (verbose)
    {
        if (value is null) writefln("Removed the %s value of %s.", where, e.name);
        else writefln("Set the %s value of %s to %s.", where, e.name, value);
    }
}

/// `fl.core.args()` handler for fldtk-options' own switches; the
/// standard ones (`-scheme`, `-geometry`, ...) are left to `args()`.
int handleArg(string[] argv, ref int i)
{
    import std.path : baseName;

    string a = argv[i];
    string app = baseName(argv[0]);
    if (a == "--help" || a == "-h")
    {
        i++;
        if (a == "--help" && i < argv.length && argv[i].length && argv[i][0] != '-')
            printInfo(argv[i++]);
        else
            printUsage(app);
        batchMode = true;
        return 1;
    }
    if (a.length > 2 && a[0 .. 2] == "-h")
    {
        i++;
        printInfo(a[2 .. $]);
        batchMode = true;
        return 1;
    }
    if (a == "-v" || a == "--verbose") { i++; verbose = true; return 1; }
    if (a == "-f") { i++; forceWrite = true; return 1; }
    if (a == "-L" || a == "-LS" || a == "-LU")
    {
        i++;
        listValues(a.length > 2 ? a[2] : 0);
        batchMode = true;
        return 1;
    }
    if (a.length > 2 && (a[0 .. 2] == "-S" || a[0 .. 2] == "-U"))
    {
        i++;
        handleSetting(a[1] == 'S' ? Context.system : Context.user, a[2 .. $]);
        batchMode = true;
        return 1;
    }
    return 0;
}

// ---- the window --------------------------------------------------------

enum gap = 10, choiceW = 90, choiceH = 22, optionsW = 540, scrollbarW = 16;
enum textW = optionsW - 3 * gap - 2 * choiceW;

/// A System or User choice for `e`: its values, a divider, then
/// "default". A stored value that isn't one of the choices (a zoom set
/// with a 1% step, say) is added as an extra item before the divider.
class SettingChoice : Choice
{
    const(Entry)* entry;
    Context ctx;
    string[] values; // stored value per item; null for "default"

    this(int x, int y, const(Entry)* e, Context ctx, string label)
    {
        super(x, y, choiceW, choiceH, label);
        entry = e;
        this.ctx = ctx;
        labelsize(11);
        alignment(alignTop);

        string current = getValue(ctx, *e);
        int currentIndex = current is null ? -1 : indexOfValue(*e, current);
        foreach (i, l; e.labels)
        {
            values ~= e.values[i];
            add(l, 0, null);
        }
        if (current !is null && currentIndex < 0)
        {
            float f;
            values ~= current;
            add(e.anyNumber && parseNumber(current, f) ? percent(f) : current, 0, null);
            currentIndex = cast(int) values.length - 1;
        }
        mode(cast(int) values.length - 1, menuDivider);
        values ~= null;
        add("default", 0, null);
        value(currentIndex < 0 ? cast(int) values.length - 1 : currentIndex);

        callback = (Widget w) {
            auto c = cast(SettingChoice) w;
            if (!setValue(c.ctx, *c.entry, c.values[c.value()]))
                fl.ask.alert(c.ctx == Context.system
                    ? "Could not write the system settings."
                    : "Could not write your settings.");
        };
    }
}

/// Height of `text` wrapped to `w` pixels in the help font.
int wrappedHeight(string text, int w)
{
    fl_font(helvetica, 11);
    int ww = w, hh;
    fl_measure(text, ww, hh);
    return hh;
}

/// Adds one setting's widgets at `y` and returns the y below them.
int addEntry(const(Entry)* e, int x, int y, bool systemOk, bool userOk)
{
    auto title = new Box(x, y, textW, 20, e.title);
    title.labelfont(helveticaBold);
    title.alignment(alignLeft | alignInside);

    auto sys = new SettingChoice(x + textW + gap, y + 16, e, Context.system, "System:");
    auto usr = new SettingChoice(x + textW + 2 * gap + choiceW, y + 16, e, Context.user, "User:");
    if (!systemOk)
    {
        sys.deactivate();
        sys.tooltip("You don't have permission to change the system settings.");
    }
    if (!userOk) usr.deactivate();

    string text = e.help ~ " Default is " ~ e.defaultLabel ~ ".";
    if (e.envVar !is null)
        text ~= " The environment variable " ~ e.envVar ~ " comes before both values.";
    int yy = y + 20;
    int h = wrappedHeight(text, textW - 4);
    auto help = new Box(x, yy, textW, h + 4, text);
    help.labelsize(11);
    help.labelcolor(lighter(foregroundColor));
    help.alignment(alignLeft | alignTop | alignInside | alignWrap);
    yy += h + 4;

    if (string env = envValue(*e))
    {
        // Say so when this run already has the variable set: the choices
        // then don't describe what programs started from here will do.
        string note = e.envVar ~ " is set to \"" ~ env ~ "\" here, so programs "
            ~ "started from this session use that.";
        int nh = wrappedHeight(note, textW - 4);
        auto n = new Box(x, yy, textW, nh + 4, note);
        n.labelsize(11);
        n.labelcolor(darkRed);
        n.alignment(alignLeft | alignTop | alignInside | alignWrap);
        yy += nh + 4;
    }
    if (yy < y + 16 + choiceH) yy = y + 16 + choiceH;
    return yy + gap;
}

Window buildWindow()
{
    bool systemOk = canWrite(Context.system);
    bool userOk = canWrite(Context.user);

    enum winW = optionsW + scrollbarW + 2 * gap;
    enum winH = 520;
    enum buttonH = 25;
    auto win = new DoubleWindow(winW, winH, "fldtk options");

    auto scroll = new Scroll(gap, gap, optionsW + scrollbarW, winH - 3 * gap - buttonH);
    scroll.box(Boxtype.downBox);
    scroll.type(scrollVertical);
    int x = scroll.x() + gap, y = scroll.y() + gap / 2;
    foreach (ref e; entries)
    {
        if (e.heading.length)
        {
            if (y > scroll.y() + gap) y += gap;
            auto head = new Box(scroll.x() + 4, y, optionsW - 8, 24, e.heading);
            head.labelfont(helveticaBold);
            head.labelsize(15);
            head.alignment(alignLeft | alignInside);
            y += 28;
        }
        y = addEntry(&e, x, y, systemOk, userOk);
    }
    scroll.end();
    win.resizable(scroll);

    auto note = new Box(gap, winH - gap - buttonH, winW - 3 * gap - 80, buttonH,
        "Changes apply to fldtk programs started from now on.");
    note.labelsize(11);
    note.alignment(alignLeft | alignInside);

    auto close = new Button(winW - gap - 80, winH - gap - buttonH, 80, buttonH, "Close");
    close.callback = (Widget) { hideAllWindows(); };
    win.end();
    win.sizeRange(winW, 200);
    return win;
}

int main(string[] args)
{
    entries = makeEntries();
    int i;
    if (fl.core.args(args, i, toDelegate(&handleArg)) < args.length)
    {
        stderr.writefln("Unknown switch \"%s\"; -h lists the switches.", args[i]);
        return 1;
    }
    if (batchMode) return exitStatus;

    fl.tooltip.size(11);
    auto win = buildWindow();
    win.show(args);
    run();
    return 0;
}
