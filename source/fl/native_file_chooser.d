/*
 * Ported from FL/Fl_Native_File_Chooser.H + src/Fl_Native_File_Chooser.cxx
 * + src/Fl_Native_File_Chooser_FLTK.cxx (FLTK 1.5.0, ~/Repositories/fltk).
 *
 * Deliberate deviations:
 *
 *  - **Only the FLTK-backend implementation is ported.** FLTK's
 *    header documents a `Fl_Native_File_Chooser_Driver` abstract base
 *    with the FLTK-backend driver (`Fl_Native_File_Chooser_FLTK_Driver`,
 *    itself just a thin wrapper around `Fl_File_Chooser` -- this port's
 *    `fl.file_chooser.FileChooser`) as ONE of several implementations
 *    selectable at runtime: GTK (`Fl_Native_File_Chooser_GTK.cxx`,
 *    ~1060 lines, `dlopen()`s `libgtk` and drives `GtkFileChooserDialog`
 *    directly), Kdialog/Zenity (spawn `kdialog`/`zenity` as a
 *    subprocess and parse its stdout). None of the infrastructure those
 *    three need (`dlopen`/`dlsym` bindings against GTK's C API, or a
 *    subprocess-spawning-and-parsing layer) exists anywhere in this
 *    port, and building it is a real, separate effort -- **deferred**,
 *    not "not applicable": a real native-desktop-look chooser is a
 *    legitimate future improvement, just out of scope for this pass
 *    (see `PORTING.md`'s row for this file). This class *is* named
 *    `NativeFileChooser`, matching FLTK's public-facing type, since
 *    from a caller's perspective this already faithfully implements
 *    the *documented fallback behavior*: "Otherwise, FLTK's own dialog
 *    ... opens" (`Fl_Native_File_Chooser.H`'s own class doc comment) --
 *    which is exactly what happens today on every Linux desktop this
 *    port targets that lacks Zenity/KDE+kdialog/GTK, and will keep
 *    happening (as the fallback) once those backends are added later.
 *    No separate `Fl_Native_File_Chooser_Driver` abstract base is
 *    ported either, matching this project's established "concrete
 *    implementation, add the abstraction when a second backend
 *    actually needs it" convention (see `fl.platform_x11`'s own module
 *    comment) -- adding the GTK/Kdialog/Zenity backends later is the
 *    point at which introducing that split would earn its keep.
 *
 *  - **`strnew()`/`strfree()`/`strapp()`/`chrcat()` are not ported.**
 *    FLTK's `Fl_Native_File_Chooser_Driver` static helpers exist
 *    purely to manage `char*` buffers by hand (`new char[]`/`delete[]`,
 *    manual `strcpy`/`strcat`); every field they backed
 *    (`_filter`/`_parsedfilt`/`_preset_file`/`_prevvalue`/`_directory`/
 *    `_errmsg`) is a plain GC `string` here instead, reassigned
 *    directly with no manual free anywhere.
 *
 *  - **`SAVEAS_CONFIRM`'s overwrite-confirmation dialog is real**,
 *    backed by `fl.ask.choice()` (see that module's row):
 *    `existDialog()` calls it with a "Cancel"/"Overwrite" pair,
 *    ported from `Fl_Native_File_Chooser_FLTK_Driver::exist_dialog()`
 *    exactly, and `show()`'s own SAVEAS_CONFIRM branch re-prompts when
 *    the chosen path already exists as a regular file (`std.file.
 *    exists()`/`isFile()`, matching FLTK's `fl_stat()`+`S_IFREG`
 *    check) and the user picked "Cancel" (returns `1`, matching
 *    FLTK's own early-return-on-decline exactly).
 */
module fl.native_file_chooser;

import std.algorithm.searching : canFind;
import std.array : join;

import fl.file_chooser : FileChooser, single, multi, createType = create, directoryType;
import fl.core : wait;
import fl.ask : choice, fl_cancel, ok;

/// `Fl_Native_File_Chooser::Type` -- a closed, non-combinable tag set,
/// so a real D `enum`, matching CLAUDE.md's convention.
enum BrowseType
{
    browseFile = 0,
    browseDirectory,
    browseMultiFile,
    browseMultiDirectory,
    browseSaveFile,
    browseSaveDirectory,
}

/// `Fl_Native_File_Chooser::Option` -- an open, combinable bitmask, so
/// a D `alias` + manifest constants.
alias NativeOption = int;

enum : NativeOption
{
    noOptions = 0x0000,
    saveasConfirm = 0x0001,
    newFolder = 0x0002,
    preview = 0x0004,
    useFilterExt = 0x0008,
}

class NativeFileChooser
{
    static string fileExistsMessage = "File exists. Are you sure you want to overwrite?";

    private int btype_;
    private int options_;
    private int nfilters_;
    private string filter_;
    private string parsedFilter_;
    private int filtValue_;
    private string presetFile_;
    private string prevValue_;
    private string directory_;
    private string errmsg_;
    private FileChooser fileChooser_;

    this(BrowseType val = BrowseType.browseFile)
    {
        fileChooser_ = new FileChooser(null, null, 0, null);
        type(val);
    }

    void type(int t)
    {
        btype_ = t;
        fileChooser_.type(typeFlFile(t));
    }
    int type() const { return btype_; }

    void options(int o) { options_ = o; }
    int options() const { return options_; }

    int count() const { return fileChooser_.count(); }

    string filename()
    {
        return fileChooser_.count() > 0 ? fileChooser_.value() : "";
    }

    string filename(int i)
    {
        return i < fileChooser_.count() ? fileChooser_.value(i + 1) : "";
    }

    void directory(string val) { directory_ = val; }
    string directory() const { return directory_; }

    void title(string t) { fileChooser_.label(t); }
    string title() const { return fileChooser_.label(); }

    string filter() const { return filter_; }
    void filter(string f)
    {
        filter_ = f;
        parseFilterField();
    }

    int filters() const { return nfilters_; }

    void filterValue(int i) { filtValue_ = i; }
    int filterValue() const { return filtValue_; }

    void presetFile(string f) { presetFile_ = f; }
    string presetFile() const { return presetFile_; }

    /// **Faithful, not a gap**: `errmsg_`
    /// is never assigned anywhere in this file, so this always returns
    /// `"No error"` -- matching FLTK's own `Fl_Native_File_Chooser_
    /// FLTK_Driver` exactly, where the equivalent private `errmsg(const
    /// char*)` setter exists but is likewise never called anywhere in
    /// `Fl_Native_File_Chooser_FLTK.cxx` either. `show()`'s own `-1`
    /// error outcome (and a caller-visible `errmsg()`) only becomes
    /// real once this class gains a real GTK/Kdialog/Zenity backend
    /// with an actual OS-level failure to report -- the same "Deferred"
    /// item this module's own top comment already tracks, not a
    /// separate gap of its own.
    string errmsg() const { return errmsg_.length ? errmsg_ : "No error"; }

    /// Posts the chooser's dialog, blocking until completed or
    /// cancelled. Returns 0 (picked), 1 (cancelled).
    int show()
    {
        if (parsedFilter_ !is null)
            fileChooser_.filter(parsedFilter_);

        fileChooser_.filterValue(filtValue_);

        if (directory_.length)
            fileChooser_.directory(directory_);
        else
            fileChooser_.directory(prevValue_);

        if (presetFile_ !is null)
            fileChooser_.value(presetFile_);

        fileChooser_.preview((options_ & preview) != 0);

        if (options_ & newFolder)
            fileChooser_.type(fileChooser_.type() | createType);

        fileChooser_.show();

        while (fileChooser_.shown())
            wait();

        auto val = fileChooser_.value();
        if (val !is null && val.length)
        {
            prevValue_ = val;
            filtValue_ = fileChooser_.filterValue();

            // HANDLE SHOWING 'SaveAs' CONFIRM -- ported from
            // Fl_Native_File_Chooser_FLTK_Driver::show(), backed by
            // fl.ask.choice() (see the module comment).
            if ((options_ & saveasConfirm) && btype_ == BrowseType.browseSaveFile)
            {
                import std.file : exists, isFile;

                if (exists(val) && isFile(val))
                {
                    if (existDialog() == 0)
                        return 1;
                }
            }
        }

        return fileChooser_.count() ? 0 : 1;
    }

    /// Ported from `Fl_Native_File_Chooser_FLTK_Driver::exist_dialog()`
    /// -- a "Cancel"/"Overwrite" choice, returning 0 for Cancel (per
    /// `choice()`'s own b0/b1/b2 -> 0/1/2 convention).
    private int existDialog()
    {
        return choice(fileExistsMessage, fl_cancel, ok, null);
    }

    private static int typeFlFile(int val)
    {
        switch (val)
        {
        case BrowseType.browseFile: return single;
        case BrowseType.browseDirectory: return single | directoryType;
        case BrowseType.browseMultiFile: return multi;
        case BrowseType.browseMultiDirectory: return directoryType | multi;
        case BrowseType.browseSaveFile: return single | createType;
        case BrowseType.browseSaveDirectory: return directoryType | multi | createType;
        default: return single;
        }
    }

    /// Converts the caller-supplied native-style filter string
    /// (`"C Files\t*.{cxx,h}\nText Files\t*.txt"`) into
    /// `fl.file_chooser.FileChooser`'s own tab-separated
    /// `"name(wild)\tname(wild)"` format. Ported from
    /// `Fl_Native_File_Chooser_FLTK_Driver::parse_filter()`'s character-
    /// at-a-time state machine (`chrcat()`-into-fixed-buffers becomes
    /// plain string appends; the `goto regchar`/`continue`-driven
    /// control flow becomes a a plain `while` loop over an index).
    private void parseFilterField()
    {
        parsedFilter_ = null;
        nfilters_ = 0;

        string inp = filter_;
        if (inp is null || inp.length == 0) return;

        char mode = inp.canFind('\t') ? 'n' : 'w';
        string wildcard, name;
        string[] parts;

        size_t i = 0;
        while (i <= inp.length)
        {
            char c = (i < inp.length) ? inp[i] : '\0';

            if (c == '\t' && mode == 'n')
            {
                mode = 'w';
            }
            else if (c == '\\' && i + 1 < inp.length)
            {
                i++;
                char rc = inp[i];
                if (mode == 'n') name ~= rc; else wildcard ~= rc;
            }
            else if (c == '\r' || c == '\n' || c == '\0')
            {
                if (wildcard.length)
                {
                    parts ~= name ~ "(" ~ wildcard ~ ")";
                    nfilters_++;
                }
                wildcard = null;
                name = null;

                if (c == '\0')
                {
                    parsedFilter_ = parts.length ? parts.join("\t") : null;
                    return;
                }

                mode = (i + 1 < inp.length && inp[i + 1 .. $].canFind('\t')) ? 'n' : 'w';
            }
            else
            {
                if (mode == 'n') name ~= c; else wildcard ~= c;
            }

            i++;
        }
    }
}

unittest
{
    // typeFlFile(): the Native-Type -> FileChooser-Type mapping.
    assert(NativeFileChooser.typeFlFile(BrowseType.browseFile) == single);
    assert(NativeFileChooser.typeFlFile(BrowseType.browseDirectory) == (single | directoryType));
    assert(NativeFileChooser.typeFlFile(BrowseType.browseMultiFile) == multi);
    assert(NativeFileChooser.typeFlFile(BrowseType.browseMultiDirectory) == (directoryType | multi));
    assert(NativeFileChooser.typeFlFile(BrowseType.browseSaveFile) == (single | createType));
    assert(NativeFileChooser.typeFlFile(BrowseType.browseSaveDirectory) == (directoryType | multi | createType));
}

unittest
{
    // parseFilterField(): the documented FROM -> TO examples from
    // Fl_Native_File_Chooser_FLTK_Driver::parse_filter()'s own comment.
    import fl.group : FlGroup;
    FlGroup.current(null);
    auto n = new NativeFileChooser();
    FlGroup.current(null);

    n.filter("*.cxx");
    assert(n.parsedFilter_ == "(*.cxx)");
    assert(n.filters() == 1);

    n.filter("C Files\t*.{cxx,h}");
    assert(n.parsedFilter_ == "C Files(*.{cxx,h})");
    assert(n.filters() == 1);

    n.filter("C Files\t*.{cxx,h}\nText Files\t*.txt");
    assert(n.parsedFilter_ == "C Files(*.{cxx,h})\tText Files(*.txt)");
    assert(n.filters() == 2);

    n.filter(null);
    assert(n.parsedFilter_ is null);
    assert(n.filters() == 0);
}
