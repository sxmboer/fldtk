/*
 * Ported from FL/Fl_File_Chooser.H + src/Fl_File_Chooser.cxx +
 * src/Fl_File_Chooser2.cxx + src/fl_file_dir.cxx (FLTK 1.5.0).
 *
 * A full file-selection dialog: a directory-listing FileBrowser, a
 * filename input field, a "Show:" filter dropdown, a favorites menu +
 * management dialog (backed by fl.preferences), a real text/image
 * preview pane, and hidden-file toggling.
 * Also ports the two free-function convenience wrappers
 * (fileChooser()/dirChooser()) from fl_file_dir.cxx, since
 * they're declared in the same header and have no other module to
 * live in.
 *
 * Deliberate deviations:
 *
 *  - **No `cb_xxx_i`/`cb_xxx` static-trampoline pairs.** FLTK's
 *    fluid-generated `Fl_File_Chooser.cxx` exists almost entirely to
 *    work around `Fl_Callback` being a plain C function pointer: every
 *    widget gets a `static void cb_xxx(Fl_Widget*, void*)` trampoline
 *    that casts `o->parent()->...->user_data()` back to
 *    `Fl_File_Chooser*` and forwards to a real `cb_xxx_i` instance
 *    method. A D delegate already closes over `this` directly, so
 *    every one of those ~20 trampoline pairs collapses into a single
 *    closure passed straight to `callback()` -- matching CONVENTIONS.md's
 *    established "Callbacks are D delegates, not function-pointer +
 *    `void*`" convention. This is *not* a hand-simplification of the
 *    logic itself, every callback body is still a faithful port --
 *    it's exactly the boilerplate the delegate substitution is meant
 *    to eliminate.
 *
 *  - **`FileChooser` is not a `Widget`,** matching FLTK (`Fl_File_
 *    Chooser` is a plain class wrapping two real `Window`s, not itself
 *    a widget) -- `callback()` takes a `void delegate(FileChooser)`
 *    directly rather than the `Fl_Callback` shape, and (matching the
 *    same "no `void*` user_data alongside a delegate" precedent as
 *    `Fl_Widget::user_data()`/`argument()`) `void* user_data()`/
 *    `user_data(void*)` are **not ported at all** -- a caller needing
 *    extra context in the callback just captures it directly, the
 *    same substitution `fl.widget`'s own module comment documents.
 *
 *  - **FL_PATH_MAX-sized `char[]` buffers become plain D `string`s**
 *    throughout (`directory_`, `pattern_`, every local scratch buffer
 *    FLTK's C string functions needed) -- no buffer-size
 *    bookkeeping, no `strlcpy`/`snprintf`/manual null-termination
 *    anywhere in this port. FLTK's pointer-splice tricks in
 *    `value(const char*)` (temporarily truncating a shared buffer with
 *    `*slash='\0'`, calling `directory()` on the truncated view, then
 *    restoring the buffer with `slash[-1]='/'` before using it again)
 *    are re-derived as separate, clearly-named string slices instead
 *    of replicated as pointer surgery -- same observable behavior
 *    (verified by hand-tracing both the "value is a file" and "value
 *    is a directory" cases), much easier to follow.
 *
 *  - **Preview pane: real text preview and real image preview.**
 *    `updatePreview()`'s image-loading branch (`SharedImage.get(filename)`,
 *    the scale-to-fit and "image has errors" cases) recognizes whatever
 *    `fl.shared_image.SharedImage`'s own format-detection handles
 *    (XBM/XPM/PNM built in, plus anything registered via its
 *    `addHandler()`) -- any other file still falls through to the
 *    text-preview path, exactly the code path FLTK's own `if
 *    (image) ...` already takes when `Fl_Shared_Image::get()` returns
 *    null for any reason. The "image has errors" check substitutes
 *    `fail()` for FLTK's `count() <= 0` term (this port never
 *    ported a public `count()` accessor at all -- see
 *    `fl.shared_image`'s own module comment); same intent, not a
 *    byte-for-byte reproduction of FLTK's exact condition shape.
 *    Also dropped: FLTK's *second*, plain-8-bit `isprint()`/
 *    `isspace()` fallback scan that only runs when the first (UTF-8-
 *    aware) scan fails -- it's redundant, since any input that reaches
 *    the fallback already failed the exact same per-byte `isprint()`/
 *    `isspace()` test in the first scan's own ASCII branch, so the
 *    fallback can never accept something the first scan rejected.
 *
 *  - **`Fl::system_driver()`-gated branches collapse to their POSIX
 *    answer**, matching this port's "concrete implementation, no
 *    driver abstraction until a second platform needs one" convention
 *    (see `fl.platform_x11`'s own module comment): `colon_is_drive()`/
 *    `backslash_as_slash()`/`case_insensitive_filenames()` are always
 *    `false` on POSIX (their branches are simply not ported, not
 *    ported-then-dead-code'd), `dot_file_hidden()` is always `true`
 *    (so `rescan()`'s hidden-file sweep always runs unconditionally),
 *    `home_directory_name()` is `environment.get("HOME")`, and
 *    `filesystems_label()` is the POSIX default `"File Systems"`.
 *    `filename_isdir_quick()` (a private `Fl_System_Driver` helper --
 *    trailing-slash check, falling back to a real `stat()`-based
 *    `filename_isdir()` only when needed) is ported as a small local
 *    `filenameIsdirQuick()` in this module, since `FL/filename.H`
 *    doesn't expose it publicly FLTK either.
 *
 *  - **Directory listing "" (all mount points / drive letters)
 *    is not supported**, matching `fl.file_browser.loadDirectory()`'s
 *    own already-documented scope decision (out of scope, no
 *    `/proc/mounts`-parsing added here either). Where FLTK's
 *    `directory("")` triggers `Fl::system_driver()->
 *    file_browser_load_filesystem()`, this port's `directory()`
 *    simply treats an empty argument the same as `null`/no argument
 *    (current directory) -- so `favoritesButtonCB()`'s "Filesystems"
 *    popup entry and the free-function wrappers' equivalent paths are
 *    ported (the menu item/API surface exists), but they resolve to
 *    "go to `.`" rather than a real filesystem-root listing.
 *
 *  - **The `newButton` "new directory" bitmap icon is real**:
 *    `newDirBits`/`newDirImage()` are a verbatim transcription of
 *    FLTK's own `idata_new[]` (`src/Fl_File_Chooser.cxx`).
 *
 *  - **`fl_input()`/`alert()` calls replace the printf-style
 *    `fl_input("%s", deflt, label)` FLTK uses everywhere in this
 *    file** -- this port's `fl_input()` already collapsed away the
 *    printf-varargs shape (see `fl.ask`'s own doc comment), so every
 *    call site here just passes the label text directly, matching what
 *    `"%s"`-formatting a single string argument already reduces to.
 *
 *  - **`newdir()`'s directory-creation error path uses a caught
 *    `Exception`'s `.msg` instead of `errno`/`strerror()`** -- no
 *    `fl_mkdir()`/`errno` equivalent is ported anywhere in this
 *    project; `std.file.mkdir()`'s own exception message serves the
 *    same "tell the user why it failed" purpose. The "ignore EEXIST"
 *    behavior is preserved via an explicit `exists()` pre-check instead
 *    of an error-code comparison after the fact.
 *
 *  - **`Fl::first_window()`-based `fl_cursor()` isn't available**
 *    (that global convenience wrapper needs `Fl::first_window()`,
 *    itself not ported -- see `fl.core`'s row in `PORTING.md`), so
 *    `show()`'s wait-cursor bracket calls `window.cursor(...)`
 *    directly on this dialog's own window instead -- identical
 *    observable effect for this single-window use case.
 *
 *  - **The favorites-dialog callback dispatch is split into one named
 *    method per widget** (`favListSelectCB()`/`favUpCB()`/
 *    `favDeleteCB()`/`favDownCB()`/`favSaveCB()`) **instead of
 *    FLTK's single `favoritesCB(Fl_Widget *w)` if/else-on-identity
 *    dispatcher.** FLTK's dispatcher exists because every one of
 *    those buttons had to share the *same* `Fl_Callback` function
 *    pointer (`cb_favUpButton`, etc. each just call `favoritesCB
 *    (favUpButton)` -- still one function per button, immediately
 *    re-dispatching) purely so the bodies could live together in one
 *    function; since each button already gets its own D closure here
 *    (see the first bullet above), routing them all back through one
 *    switch-on-identity function first would be pure indirection with
 *    no reader benefit. Every branch's *body* is still a faithful,
 *    line-for-line port; only the dispatch shape changed.
 */
module fl.file_chooser;

import std.algorithm.searching : canFind;
import std.file : exists, mkdir, DirEntry, isFile;
import std.format : format;
import std.process : environment;
import std.string : indexOf, lastIndexOf;

import fl.widget : Widget, Callback;
import fl.group : FlGroup;
import fl.window : Window;
import fl.double_window : DoubleWindow;
import fl.box : Box;
import fl.choice : Choice;
import fl.menu_button : MenuButton;
import fl.menu_item : menuInactive, menuDivider;
import fl.button : Button;
import fl.check_button : CheckButton;
import fl.return_button : ReturnButton;
import fl.tile : Tile;
import fl.file_input : FileInput;
import fl.file_browser : FileBrowser, fileBrowserFiles, fileBrowserDirectories,
    defaultFileSort, FileSortFunc;
import fl.browser_ : holdBrowser, multiBrowser;
import fl.file_icon : FileIcon, FileType;
import fl.preferences : Preferences, rootUser, rootCore;
import fl.filename : filenameAbsolute, filenameIsdir, filenameExpand, filenameName,
    filenameRelative;
import fl.ask : fl_input, alert, ok, fl_cancel;
import fl.shared_image : SharedImage;
import fl.bitmap : Bitmap;
import fl.enumerations;
import fl.core : eventClicks, eventKey, check, addTimeout, removeTimeout, grab, wait;

/// Ported from the `Fl::system_driver()->backslash_as_slash()` block
/// repeated at the top of both `Fl_File_Chooser::directory()` and
/// `Fl_File_Chooser::value()` (`Fl_File_Chooser2.cxx`) -- true on
/// Windows only (`Fl_WinAPI_System_Driver::backslash_as_slash()`
/// returns `1`; the base `Fl_System_Driver` returns `0`). Every other
/// path-splitting check throughout this module (`lastIndexOf('/')`,
/// `dir[0] == '/'`, `directory_ == "/"`, ...) stays a literal `'/'`
/// test unchanged, exactly matching FLTK's own POSIX-shaped body --
/// FLTK's real fix for Windows isn't to widen each of those, it's
/// to make the input uniform once, at these two entry points, before
/// any of them run. A single shared helper here (rather than repeating
/// FLTK's own copy-pasted conversion loop at both call sites) --
/// same operation, no behavioral difference.
version (Windows)
private string normalizeSlashes(string s)
{
    import std.array : replace;
    return s.indexOf('\\') >= 0 ? s.replace('\\', '/') : s;
}

/// Fl_File_Chooser::Type -- an open, combinable bitmask (CREATE can be
/// combined with DIRECTORY), so a D `alias` + manifest constants,
/// matching CONVENTIONS.md's convention for this shape (same treatment as
/// `Align`/`When`/`Damage`). `directoryType`, not `directory` --
/// `FileChooser` already has a `directory()`/`directory(string)`
/// method pair, and D resolves an unqualified name inside the class
/// body to the member first, shadowing this module-level constant.
alias Type = int;

enum : Type
{
    single = 0,
    multi = 1,
    create = 2,
    directoryType = 4,
}

/// FileChooser's own callback -- `void delegate(FileChooser)`. See the
/// module comment's first bullet for why there's no companion
/// `void*`/user_data slot alongside it.
alias FileChooserCallback = void delegate(FileChooser);

// Verbatim transcription of FLTK's own `idata_new[]` (src/
// Fl_File_Chooser.cxx) -- a 16x16 XBM-style bitmap for newButton's "new
// folder" icon. FLTK's `new Fl_Bitmap(idata_new, 32, 16, 16)`
// passes the array's byte length (32) as an explicit `bits_length`
// argument to the length-checked constructor overload;
// `fl.bitmap.Bitmap`'s own constructor infers that from the D slice
// directly, so it's dropped here.
private immutable ubyte[32] newDirBits = [
    0, 0, 120, 0, 132, 0, 2, 1, 1, 254, 1, 128, 49, 128, 49, 128, 253, 128,
    253, 128, 49, 128, 49, 128, 1, 128, 1, 128, 255, 255, 0, 0];
private Bitmap newDirImage_;
private Bitmap newDirImage()
{
    if (newDirImage_ is null) newDirImage_ = new Bitmap(newDirBits, 16, 16);
    return newDirImage_;
}

class FileChooser
{
    private static Preferences prefs_;

    static string addFavoritesLabel = "Add to Favorites";
    static string allFilesLabel = "All Files (*)";
    static string customFilterLabel = "Custom Filter";
    static string existingFileLabel = "Please choose an existing file!";
    static string favoritesLabel = "Favorites";
    static string filenameLabel = "Filename:";
    static string filesystemsLabel = "File Systems";
    static string manageFavoritesLabel = "Manage Favorites";
    static string newDirectoryLabel = "New Directory?";
    static string newDirectoryTooltip = "Create a new directory.";
    static string previewLabel = "Preview";
    static string saveLabel = "Save";
    static string showLabel = "Show:";
    static string hiddenLabel = "Show hidden files";

    /// The sort function used when loading a directory's contents --
    /// defaults to fl.file_browser's own natural/numeric-aware
    /// comparator, standing in for unported `fl_numericsort()` (see
    /// that module's own row for why).
    static FileSortFunc sort;

    static this()
    {
        sort = (a, b) => defaultFileSort(a, b);
    }

    private FileChooserCallback callback_;
    private string directory_;
    private string pattern_;
    private int type_;

    private DoubleWindow window;
    private Choice showChoice;
    private MenuButton favoritesButton;
    public Button newButton;
    public FileBrowser fileList;
    private Box errorBox;
    private Box previewBox;
    public CheckButton previewButton;
    public CheckButton showHiddenButton;
    private FileInput fileName;
    private ReturnButton okButton;
    private Button cancelButton;

    private DoubleWindow favWindow;
    private FileBrowser favList;
    private Button favUpButton, favDeleteButton, favDownButton;
    private Button favCancelButton;
    private ReturnButton favOkButton;

    private Widget extGroup;

    this(string pathname, string pattern, int typeVal, string title)
    {
        if (prefs_ is null)
            prefs_ = new Preferences(rootUser | rootCore, "fltk.org", "filechooser");

        auto prevCurrent = FlGroup.current();
        FlGroup.current(null);

        window = new DoubleWindow(490, 380, "Choose File");
        window.callback((w) {
            fileName.value("");
            fileList.deselect();
            hide();
        });

        auto topRow = new FlGroup(10, 10, 470, 25);
        showChoice = new Choice(65, 10, 215, 25, "Show:");
        showChoice.downBox(Boxtype.borderBox);
        showChoice.labelfont(helveticaBold);
        showChoice.callback((w) { showChoiceCB(); });
        topRow.resizable(showChoice);
        showChoice.label(showLabel);

        favoritesButton = new MenuButton(290, 10, 155, 25, "Favorites");
        favoritesButton.downBox(Boxtype.borderBox);
        favoritesButton.callback((w) { favoritesButtonCB(); });
        favoritesButton.alignment(cast(Align)(alignLeft | alignInside));
        favoritesButton.label(favoritesLabel);

        newButton = new Button(455, 10, 25, 25);
        newButton.image(newDirImage());
        newButton.labelsize(8);
        newButton.callback((w) { newdir(); });
        newButton.tooltip(newDirectoryTooltip);
        topRow.end();

        auto tileGroup = new Tile(10, 45, 470, 225);
        tileGroup.callback((w) { updatePreview(); });

        fileList = new FileBrowser(10, 45, 295, 225);
        fileList.type(holdBrowser);
        fileList.box(Boxtype.downBox);
        fileList.callback((w) { fileListCB(); });

        errorBox = new Box(Boxtype.downBox, 10, 45, 295, 225, "dynamic error display");
        errorBox.color(background2Color);
        errorBox.labelsize(18);
        errorBox.labelcolor(cast(Color) 1);
        errorBox.alignment(cast(Align)(alignWrap | alignLeft | alignTop | alignInside));
        errorBox.hide();

        previewBox = new Box(305, 45, 175, 225, "?");
        previewBox.box(Boxtype.downBox);
        previewBox.labelsize(100);
        previewBox.alignment(cast(Align)(alignClip | alignInside));

        tileGroup.end();
        FlGroup.current().resizable(tileGroup);

        auto bottomGroup = new FlGroup(10, 275, 470, 95);
        auto checksRow = new FlGroup(10, 275, 470, 20);

        previewButton = new CheckButton(10, 275, 105, 20, "Preview");
        previewButton.shortcut(stateAlt + 'p');
        previewButton.downBox(Boxtype.downBox);
        previewButton.value(true);
        previewButton.callback((w) { preview(previewButton.value()); });
        previewButton.label(previewLabel);

        showHiddenButton = new CheckButton(115, 275, 140, 20, "Show hidden files");
        showHiddenButton.downBox(Boxtype.downBox);
        showHiddenButton.callback((w) { showHidden(showHiddenButton.value()); });
        showHiddenButton.label(hiddenLabel);

        auto checksStretch = new Box(255, 275, 225, 20);
        checksRow.resizable(checksStretch);
        checksRow.end();

        fileName = new FileInput(115, 300, 365, 35);
        fileName.labelfont(helveticaBold);
        fileName.callback((w) { fileNameCB(); });
        fileName.when(whenEnterKey);
        bottomGroup.resizable(fileName);
        fileName.when(cast(When)(whenChanged | whenEnterKeyAlways));

        auto filenameLabelBox = new Box(10, 310, 105, 25, "Filename:");
        filenameLabelBox.labelfont(helveticaBold);
        filenameLabelBox.alignment(cast(Align)(alignRight | alignInside));
        filenameLabelBox.label(filenameLabel);

        auto buttonRow = new FlGroup(10, 345, 470, 25);
        okButton = new ReturnButton(313, 345, 85, 25, "OK");
        okButton.callback((w) { okButtonCB(); });
        okButton.label(ok);

        cancelButton = new Button(408, 345, 72, 25, "Cancel");
        cancelButton.callback((w) {
            fileName.value("");
            fileList.deselect();
            hide();
        });
        cancelButton.label(fl_cancel);

        auto buttonStretch = new Box(10, 345, 30, 25);
        buttonRow.resizable(buttonStretch);
        buttonRow.end();

        bottomGroup.end();

        window.setModal();
        if (title.length) window.label(title);
        window.end();

        favWindow = new DoubleWindow(355, 150, "Manage Favorites");

        favList = new FileBrowser(10, 10, 300, 95);
        favList.type(holdBrowser);
        favList.callback((w) { favListSelectCB(); });
        FlGroup.current().resizable(favList);

        auto favButtonCol = new FlGroup(320, 10, 25, 95);
        favUpButton = new Button(320, 10, 25, 25, "@8>");
        favUpButton.callback((w) { favUpCB(); });

        favDeleteButton = new Button(320, 45, 25, 25, "X");
        favDeleteButton.labelfont(helveticaBold);
        favDeleteButton.callback((w) { favDeleteCB(); });
        favButtonCol.resizable(favDeleteButton);

        favDownButton = new Button(320, 80, 25, 25, "@2>");
        favDownButton.callback((w) { favDownCB(); });
        favButtonCol.end();

        auto favBottomRow = new FlGroup(10, 113, 335, 29);
        favCancelButton = new Button(273, 115, 72, 25, "Cancel");
        favCancelButton.callback((w) { favWindow.hide(); });
        favCancelButton.label(fl_cancel);

        favOkButton = new ReturnButton(181, 115, 79, 25, "Save");
        favOkButton.callback((w) { favSaveCB(); });
        favOkButton.label(saveLabel);

        auto favStretch = new Box(10, 115, 161, 25);
        favBottomRow.resizable(favStretch);
        favBottomRow.end();

        favWindow.setModal();
        favWindow.sizeRange(181, 150);
        favWindow.label(manageFavoritesLabel);
        favWindow.end();

        directory_ = "";
        window.sizeRange(window.w(), window.h());
        type(typeVal);
        filter(pattern);
        updateFavorites();
        value(pathname);
        type(typeVal);

        int previewFlag;
        prefs_.get("preview", previewFlag, 1);
        preview(previewFlag != 0);

        FlGroup.current(prevCurrent);
        extGroup = null;
    }

    // ------------------------------------------------------------
    // Public accessors -- thin forwarders, matching FLTK 1:1.
    // ------------------------------------------------------------

    void callback(FileChooserCallback cb) { callback_ = cb; }

    void color(Color c) { fileList.color(c); }
    Color color() const { return fileList.color(); }

    /// Number of selected files -- ported from `count()`.
    int count() const
    {
        string filename = fileName.value();

        if (!(type_ & multi))
            return filename.length == 0 ? 0 : 1;

        int fcount = 0;
        for (int i = 1; i <= fileList.size(); i++)
            if (fileList.selected(i)) fcount++;

        if (fcount) return fcount;
        return filename.length == 0 ? 0 : 1;
    }

    string directory() const { return directory_; }

    /// Sets the current directory. See the module comment for why an
    /// empty `d` isn't the "list all mount points" sentinel here.
    /// **Normalizes backslashes to `/` first on Windows** (matching
    /// FLTK's real `Fl_File_Chooser::directory()`'s own
    /// `backslash_as_slash()` block, `Fl_File_Chooser2.cxx`) -- every
    /// other check in this function and `rescan()`/`value()` below
    /// still only ever tests for a literal `'/'`, exactly like
    /// FLTK's own POSIX-shaped body does; FLTK's real fix isn't
    /// to widen each of those checks, it's to make the separator
    /// uniform once, right here, before any of them run.
    void directory(string d)
    {
        string dir = (d.length == 0) ? "." : d;
        version (Windows) dir = normalizeSlashes(dir);
        string abs = (dir.length && dir[0] == '/') ? dir : filenameAbsolute(dir);

        if (abs.length > 1 && abs[$ - 1] == '/')
            abs = abs[0 .. $ - 1];

        if (abs.length >= 3 && abs[$ - 3 .. $] == "/..")
        {
            abs = abs[0 .. $ - 3];
            auto idx = abs.lastIndexOf('/');
            abs = idx >= 0 ? abs[0 .. idx] : "";
        }
        else if (abs.length >= 2 && abs[$ - 2 .. $] == "/.")
        {
            abs = abs[0 .. $ - 2];
        }

        directory_ = abs;

        if (shown()) rescan();
    }

    void filter(string p)
    {
        string pat = (p.length == 0) ? "*" : p;

        showChoice.clear();

        auto parts = pat.split_('\t');
        if (parts.length > 0 && parts[$ - 1].length == 0) parts = parts[0 .. $ - 1];

        bool allfiles = false;
        foreach (part; parts)
        {
            if (part == "*")
            {
                showChoice.add(allFilesLabel, 0, null);
                allfiles = true;
            }
            else
            {
                showChoice.add(quotePathname(part), 0, null);
                if (part.canFind("(*)")) allfiles = true;
            }
        }

        if (!allfiles) showChoice.add(allFilesLabel, 0, null);
        showChoice.add(customFilterLabel, 0, null);

        showChoice.value(0);
        showChoiceCB();
    }

    string filter() const { return fileList.filter(); }

    int filterValue() const { return showChoice.value(); }
    void filterValue(int f) { showChoice.value(f); showChoiceCB(); }

    ubyte iconsize() const { return fileList.iconsize(); }
    void iconsize(ubyte s) { fileList.iconsize(s); }

    string label() const { return window.label(); }
    void label(string l) { window.label(l); }

    void okLabel(string l)
    {
        if (l !is null) okButton.label(l);
        int w, h;
        okButton.measureLabel(w, h);
        okButton.resize(cancelButton.x() - 50 - w, cancelButton.y(), w + 40, 25);
        (cast(FlGroup) okButton.parent()).initSizes();
    }
    string okLabel() const { return okButton.label(); }

    /// Enable/disable the preview tile. FLTK: `void preview(int)`
    /// -- `bool` here, matching the underlying `CheckButton.value()`'s
    /// own type (see the module comment).
    void preview(bool e)
    {
        previewButton.value(e);
        prefs_.set("preview", e ? 1 : 0);
        prefs_.flush();

        auto p = cast(FlGroup) previewBox.parent();
        if (e)
        {
            int w = p.w() * 2 / 3;
            fileList.resize(fileList.x(), fileList.y(), w, fileList.h());
            errorBox.resize(errorBox.x(), errorBox.y(), w, errorBox.h());
            previewBox.resize(fileList.x() + w, previewBox.y(), p.w() - w, previewBox.h());
            previewBox.show();
            updatePreview();
        }
        else
        {
            fileList.resize(fileList.x(), fileList.y(), p.w(), fileList.h());
            errorBox.resize(errorBox.x(), errorBox.y(), p.w(), errorBox.h());
            previewBox.resize(p.x() + p.w(), previewBox.y(), 0, previewBox.h());
            previewBox.hide();
        }
        p.initSizes();
        fileList.parent().redraw();
    }
    bool preview() const { return previewButton.value(); }

    /// Reloads the current directory into the file list.
    void rescan()
    {
        string pathname = directory_;
        if (pathname.length && pathname[$ - 1] != '/') pathname ~= "/";
        fileName.value(pathname);

        if (type_ & directoryType) okButton.activate();
        else okButton.deactivate();

        bool ok = fileList.loadDirectory(directory_, sort);
        if (!ok || fileList.size() == 0)
            showErrorMessage();
        else
            showErrorBox(false);

        // Fl::system_driver()->dot_file_hidden() is always true on this
        // port's only platform, see the module comment.
        if (!showHiddenButton.value())
            removeHiddenFiles();

        updatePreview();
    }

    /// Rescans without clearing the filename field, then re-selects it
    /// if still present in the (possibly-changed) listing.
    void rescanKeepFilename()
    {
        string fn = fileName.value();
        if (fn.length == 0 || fn[$ - 1] == '/')
        {
            rescan();
            return;
        }

        bool ok = fileList.loadDirectory(directory_, sort);
        if (!ok || fileList.size() == 0)
            showErrorMessage();
        else
            showErrorBox(false);

        if (!showHiddenButton.value())
            removeHiddenFiles();

        updatePreview();

        bool found = false;
        auto slashIdx = fn.lastIndexOf('/');
        string slash = slashIdx >= 0 ? fn[slashIdx + 1 .. $] : fn;

        for (int i = 1; i <= fileList.size(); i++)
        {
            if (fileList.text(i) == slash)
            {
                fileList.topline(i);
                fileList.select(i);
                found = true;
                break;
            }
        }

        if (found || (type_ & create)) okButton.activate();
        else okButton.deactivate();
    }

    void show()
    {
        window.hotspot(fileList);
        window.show();
        check();
        window.cursor(Cursor.wait);
        rescanKeepFilename();
        window.cursor(Cursor.default_);
        fileName.takeFocus();
        // Ported from `Fl_File_Chooser::show()`'s own trailing
        // `if (!Fl::system_driver()->dot_file_hidden()) showHiddenButton->hide();`
        // -- FLTK only hides this button on platforms where dotfiles
        // aren't the hidden-file convention (so toggling them wouldn't
        // mean anything there). On this port's only platform,
        // `dot_file_hidden()` is always `true` (see the module's own top
        // comment), so that condition never holds and the button just
        // stays visible -- the `if` collapses away entirely rather than
        // being kept as a real (always-false) check, matching this
        // port's usual `Fl::system_driver()`-branch-collapsing
        // convention.
    }

    void hide()
    {
        previewBox.image(null);
        window.hide();
    }

    bool shown() const { return window.shown(); }

    void textcolor(Color c) { fileList.textcolor(c); }
    Color textcolor() const { return fileList.textcolor(); }
    void textfont(Font f) { fileList.textfont(f); }
    Font textfont() const { return fileList.textfont(); }
    void textsize(Fontsize s) { fileList.textsize(s); }
    Fontsize textsize() const { return fileList.textsize(); }

    void type(int t)
    {
        type_ = t;
        fileList.type((t & multi) ? multiBrowser : holdBrowser);
        if (t & create) newButton.activate();
        else newButton.deactivate();
        fileList.filetype((t & directoryType) ? fileBrowserDirectories : fileBrowserFiles);
    }
    int type() const { return type_; }

    bool visible() const { return window.visible(); }
    void position(int x, int y) { window.position(x, y); }
    int x() const { return window.x(); }
    int y() const { return window.y(); }
    int w() const { return window.w(); }
    int h() const { return window.h(); }
    void size(int w, int h) { window.size(w, h); }
    void resize(int x, int y, int w, int h) { window.resize(x, y, w, h); }

    /// Gets the current value of the selected file(s). `f` is a
    /// 1-based index; see `count()`.
    string value(int f = 1)
    {
        string name = fileName.value();

        if (!(type_ & multi))
            return name.length == 0 ? null : name;

        int fcount = 0;
        for (int i = 1; i <= fileList.size(); i++)
        {
            if (fileList.selected(i))
            {
                fcount++;
                if (fcount == f)
                {
                    string n = fileList.text(i).idup;
                    return directory_.length ? directory_ ~ "/" ~ n : n;
                }
            }
        }

        return name.length == 0 ? null : name;
    }

    /// Sets the current value. See the module comment for why this is
    /// re-derived with plain string slices instead of FLTK's
    /// pointer-splice trick.
    void value(string filename)
    {
        if (filename is null || filename.length == 0)
        {
            directory(".");
            fileName.value("");
            okButton.deactivate();
            return;
        }

        string fname = filename;
        version (Windows) fname = normalizeSlashes(fname);
        string pathname = filenameAbsolute(fname);

        string dirPart, slash;
        auto idx = pathname.lastIndexOf('/');
        if (idx >= 0)
        {
            if (!filenameIsdir(pathname))
            {
                dirPart = pathname[0 .. idx];
                slash = pathname[idx + 1 .. $];
            }
            else
            {
                dirPart = pathname;
                slash = pathname; // matches FLTK: nothing in the list will match the whole path
            }
            directory(dirPart);
        }
        else
        {
            directory(".");
            slash = pathname;
        }

        fileName.value(pathname);
        fileName.insertPosition(0, cast(int) pathname.length);
        okButton.activate();

        fileList.deselect(0);
        fileList.redraw();

        for (int i = 1; i <= fileList.size(); i++)
        {
            if (fileList.text(i) == slash)
            {
                fileList.topline(i);
                fileList.select(i);
                break;
            }
        }
    }

    Widget addExtra(Widget gr)
    {
        Widget ret = extGroup;
        if (gr is extGroup) return ret;

        if (extGroup !is null)
        {
            int sh = extGroup.h() + 4;
            Widget svres = window.resizable();
            window.resizable(null);
            window.size(window.w(), window.h() - sh);
            window.remove(extGroup);
            extGroup = null;
            window.resizable(svres);
        }

        if (gr !is null)
        {
            int nh = window.h() + gr.h() + 4;
            Widget svres = window.resizable();
            window.resizable(null);
            window.size(window.w(), nh);
            gr.position(2, okButton.y() + okButton.h() + 2);
            window.add(gr);
            extGroup = gr;
            window.resizable(svres);
        }

        return ret;
    }

    // ------------------------------------------------------------
    // Private callback bodies.
    // ------------------------------------------------------------

    private void showErrorMessage()
    {
        string msg = fileList.errmsg();
        errorBox.label(msg.length ? msg : "No files found...");
        showErrorBox(true);
    }

    private void showErrorBox(bool val)
    {
        if (val)
        {
            errorBox.color(fileList.color());
            errorBox.show();
            fileList.hide();
        }
        else
        {
            errorBox.hide();
            fileList.show();
        }
    }

    private void removeHiddenFiles()
    {
        for (int i = fileList.size(); i >= 1; i--)
        {
            string p = fileList.text(i).idup;
            if (p.length && p[0] == '.' && p != "../")
                fileList.remove(i);
        }
        fileList.topline(1);
    }

    private void okButtonCB()
    {
        hide();
        if (callback_) callback_(this);
    }

    private void newdir()
    {
        string dir = fl_input(newDirectoryLabel, null);
        if (dir is null) return;

        string pathname = (dir.length && dir[0] == '/') ? dir : directory_ ~ "/" ~ dir;

        if (!exists(pathname))
        {
            try mkdir(pathname);
            catch (Exception e) { alert(e.msg); return; }
        }

        directory(pathname);
    }

    private void showHidden(bool value)
    {
        if (value)
            fileList.loadDirectory(directory_);
        else
        {
            removeHiddenFiles();
            fileList.redraw();
        }
    }

    private void fileListCB()
    {
        int idx = fileList.value();
        if (idx < 1) return;
        string filename = fileList.text(idx).idup;
        if (filename is null) return;

        string pathname;
        if (directory_.length == 0) pathname = filename;
        else if (directory_ == "/") pathname = "/" ~ filename;
        else pathname = directory_ ~ "/" ~ filename;

        if (eventClicks())
        {
            if (filenameIsdirQuick(pathname))
            {
                directory(pathname);
                eventClicks(-1);
            }
            else
            {
                window.hide();
                if (callback_) callback_(this);
            }
        }
        else
        {
            if ((type_ & multi) && !(type_ & directoryType))
            {
                if (pathname.length && pathname[$ - 1] == '/')
                {
                    int i = fileList.value();
                    fileList.deselect();
                    fileList.select(i);
                }
                else
                {
                    bool dirSelected = false;
                    for (int i = 1; i <= fileList.size(); i++)
                    {
                        if (i != fileList.value() && fileList.selected(i))
                        {
                            string t = fileList.text(i).idup;
                            if (t.length && t[$ - 1] == '/') { dirSelected = true; break; }
                        }
                    }
                    if (dirSelected)
                    {
                        int i = fileList.value();
                        fileList.deselect();
                        fileList.select(i);
                    }
                }
            }

            if (pathname.length && pathname[$ - 1] == '/')
                pathname = pathname[0 .. $ - 1];

            fileName.value(pathname);

            // FLTK waits one second before updating the preview; this
            // updates it at once.
            updatePreview();

            if (callback_) callback_(this);

            if (!filenameIsdirQuick(pathname) || (type_ & directoryType))
                okButton.activate();
            else
                okButton.deactivate();
        }
    }

    private void fileNameCB()
    {
        string filename = fileName.value();

        if (filename is null || filename.length == 0)
        {
            okButton.deactivate();
            return;
        }

        if (filename.canFind('~') || filename.canFind('$'))
        {
            filename = filenameExpand(filename);
            value(filename);
        }

        bool dirIsRelative = directory_.length != 0 && filename[0] != '/';
        if (dirIsRelative)
        {
            filename = filenameAbsolute(filename);
            value(filename);
            fileName.insertPosition(cast(int) filename.length, cast(int) filename.length);
        }

        string pathname = filename;

        if (eventKey() == enter || eventKey() == kpEnter)
        {
            bool condition = filenameIsdirQuick(pathname) && compareDirnames(pathname, directory_) != 0;
            if (condition)
            {
                directory(pathname);
            }
            else if ((type_ & create) || exists(pathname))
            {
                if (!filenameIsdirQuick(pathname) || (type_ & directoryType))
                {
                    updatePreview();
                    if (callback_) callback_(this);
                    window.hide();
                }
            }
            else
            {
                alert(existingFileLabel);
            }
        }
        else if (eventKey() != deleteKey && eventKey() != backSpace)
        {
            auto slashIdx = pathname.lastIndexOf('/');
            if (slashIdx < 0) return;

            string dirPart = pathname[0 .. slashIdx];
            string filePart = pathname[slashIdx + 1 .. $];

            if (compareDirnames(dirPart, directory_) != 0 && (dirPart.length != 0 || directory_ != "/"))
            {
                int p = fileName.insertPosition();
                int m = fileName.mark();

                directory(dirPart);

                if (filePart.length)
                {
                    string tempname = directory_ ~ "/" ~ filePart;
                    fileName.value(tempname);
                    pathname = tempname;
                }

                fileName.insertPosition(p, m);
            }

            int numFiles = fileList.size();
            int minMatch = cast(int) filePart.length;
            int maxMatch = minMatch + 1;
            int firstLine = 0;
            string matchname;

            for (int i = 1; i <= numFiles && maxMatch > minMatch; i++)
            {
                string file = fileList.text(i).idup;
                if (strEqN(filePart, file, minMatch))
                {
                    if (firstLine == 0)
                    {
                        matchname = file;
                        maxMatch = cast(int) matchname.length;

                        if (maxMatch > 0 && matchname[$ - 1] == '/' && matchname.length != 1)
                        {
                            maxMatch--;
                            matchname = matchname[0 .. maxMatch];
                        }

                        fileList.topline(i);
                        firstLine = i;
                    }
                    else
                    {
                        while (maxMatch > minMatch && !strEqN(file, matchname, maxMatch))
                            maxMatch--;
                        matchname = matchname[0 .. maxMatch];
                    }
                }
            }

            if (firstLine > 0 && minMatch == maxMatch && maxMatch == cast(int) fileList.text(firstLine).length)
            {
                fileList.deselect(0);
                fileList.select(firstLine);
                fileList.redraw();
            }
            else if (maxMatch > minMatch && firstLine)
            {
                int base = cast(int) slashIdx + 1;
                fileName.replace(base, base + minMatch, matchname);
                fileName.insertPosition(base + maxMatch, base + minMatch);
            }
            else if (maxMatch == 0)
            {
                fileList.deselect(0);
                fileList.redraw();
            }

            updateOkButton();
        }
        else
        {
            fileList.deselect(0);
            fileList.redraw();
            updateOkButton();
        }
    }

    private void updateOkButton()
    {
        if (((type_ & create) || exists(fileName.value()))
            && (!filenameIsdir(fileName.value()) || (type_ & directoryType)))
            okButton.activate();
        else
            okButton.deactivate();
    }

    private void showChoiceCB()
    {
        string item = showChoice.text(showChoice.value());

        if (item == customFilterLabel)
        {
            string entered = fl_input(customFilterLabel, pattern_);
            if (entered !is null)
            {
                pattern_ = entered;
                showChoice.add(quotePathname(entered), 0, null);
                showChoice.value(showChoice.size() - 2);
            }
        }
        else
        {
            auto lp = item.indexOf('(');
            if (lp < 0)
            {
                pattern_ = item;
            }
            else
            {
                string rest = item[lp + 1 .. $];
                auto rp = rest.lastIndexOf(')');
                pattern_ = rp >= 0 ? rest[0 .. rp] : rest;
            }
        }

        fileList.filter(pattern_);

        if (shown())
            rescanKeepFilename();
    }

    private void favoritesButtonCB()
    {
        int v = favoritesButton.value();

        if (v == 0)
        {
            int idx = environment.get("HOME", "").length
                ? favoritesButton.size() - 5 : favoritesButton.size() - 4;
            prefs_.set(format("favorite%02d", idx), directory_);
            prefs_.flush();

            updateFavorites();

            if (favoritesButton.size() > 104)
                favoritesButton.mode(0, favoritesButton.mode(0) | menuInactive);
        }
        else if (v == 1)
        {
            manageFavorites();
        }
        else if (v == 2)
        {
            directory(""); // "Filesystems" -- see the module comment
        }
        else
        {
            directory(unquotePathname(favoritesButton.text(v)));
        }
    }

    private void manageFavorites()
    {
        favList.clear();
        favList.deselect();

        for (int i = 0; i < 100; i++)
        {
            string pathname;
            if (!prefs_.get(format("favorite%02d", i), pathname, "") || pathname.length == 0) break;
            favList.add(pathname, FileIcon.find(pathname, FileType.directory));
        }

        favUpButton.deactivate();
        favDeleteButton.deactivate();
        favDownButton.deactivate();
        favOkButton.deactivate();

        favWindow.hotspot(favList);
        favWindow.show();
    }

    private void favListSelectCB()
    {
        int i = favList.value();
        if (i)
        {
            if (i > 1) favUpButton.activate(); else favUpButton.deactivate();
            favDeleteButton.activate();
            if (i < favList.size()) favDownButton.activate(); else favDownButton.deactivate();
        }
        else
        {
            favUpButton.deactivate();
            favDeleteButton.deactivate();
            favDownButton.deactivate();
        }
    }

    private void favUpCB()
    {
        int i = favList.value();
        if (i < 1) return;
        favList.insert(i - 1, favList.text(i).idup, favList.data(i));
        favList.remove(i + 1);
        favList.select(i - 1);
        if (i == 2) favUpButton.deactivate();
        favDownButton.activate();
        favOkButton.activate();
    }

    private void favDeleteCB()
    {
        int i = favList.value();
        if (i < 1) return;
        favList.remove(i);
        if (i > favList.size()) i--;
        favList.select(i);
        if (i < favList.size()) favDownButton.activate(); else favDownButton.deactivate();
        if (i > 1) favUpButton.activate(); else favUpButton.deactivate();
        if (!i) favDeleteButton.deactivate();
        favOkButton.activate();
    }

    private void favDownCB()
    {
        int i = favList.value();
        if (i < 1) return;
        favList.insert(i + 2, favList.text(i).idup, favList.data(i));
        favList.remove(i);
        favList.select(i + 1);
        if ((i + 1) == favList.size()) favDownButton.deactivate();
        favUpButton.activate();
        favOkButton.activate();
    }

    private void favSaveCB()
    {
        int i;
        for (i = 0; i < favList.size(); i++)
            prefs_.set(format("favorite%02d", i), favList.text(i + 1).idup);

        for (; i < 100; i++)
        {
            string pathname;
            if (!prefs_.get(format("favorite%02d", i), pathname, "") || pathname.length == 0) break;
            prefs_.set(format("favorite%02d", i), "");
        }

        updateFavorites();
        prefs_.flush();
        favWindow.hide();
    }

    private void updateFavorites()
    {
        favoritesButton.clear();
        favoritesButton.add(addFavoritesLabel, stateAlt + 'a', null);
        favoritesButton.add(manageFavoritesLabel, stateAlt + 'm', null, menuDivider);
        favoritesButton.add(filesystemsLabel, stateAlt + 'f', null);

        string home = environment.get("HOME", "");
        if (home.length)
            favoritesButton.add(quotePathname(home), stateAlt + 'h', null);

        int i;
        for (i = 0; i < 100; i++)
        {
            string pathname;
            if (!prefs_.get(format("favorite%02d", i), pathname, "") || pathname.length == 0) break;

            string menuname = quotePathname(pathname);
            if (i < 10) favoritesButton.add(menuname, stateAlt + '0' + i, null);
            else favoritesButton.add(menuname, 0, null);
        }

        if (i == 100)
            favoritesButton.mode(0, favoritesButton.mode(0) | menuInactive);
    }

    private void updatePreview()
    {
        if (!previewButton.value()) return;

        string filename = value();
        string newlabel;
        bool set = false;
        SharedImage image;

        if (filename is null || filename.length == 0)
        {
            set = true;
        }
        else if (filenameIsdir(filename))
        {
            newlabel = "@fileopen";
            set = true;
        }
        else
        {
            try
            {
                auto de = DirEntry(filename);
                if (!de.isFile)
                {
                    newlabel = "@-3refresh";
                    set = true;
                }
                else if (de.size == 0)
                {
                    newlabel = "<empty file>";
                    set = true;
                }
                else
                {
                    // Try loading as an image. XBM/XPM/PNM are always
                    // recognized; PNG/JPEG/GIF/BMP/ICO/SVG only once the
                    // program has called `registerImages()` (see
                    // SharedImage's own module comment); anything else falls through to the
                    // text-preview path below, matching exactly what
                    // FLTK itself does when Fl_Shared_Image::get()
                    // returns null for any reason (an unregistered
                    // format included).
                    if (window !is null) window.cursor(Cursor.wait);
                    check();
                    image = SharedImage.get(filename);
                    if (image !is null)
                    {
                        if (window !is null) window.cursor(Cursor.default_);
                        check();
                        set = true;
                    }
                }
            }
            catch (Exception) { /* stat() failed -- falls to text-preview path, matching FLTK */ }
        }
        // A file that was not an image is still being previewed as text;
        // the wait cursor set for the image attempt ends here.
        if (!set && window !is null)
        {
            window.cursor(Cursor.default_);
            check();
        }

        auto oldImage = cast(SharedImage) previewBox.image();
        if (oldImage !is null) oldImage.release();
        previewBox.image(null);

        if (!set)
        {
            string text;
            try
            {
                import std.stdio : File;
                auto f = File(filename, "rb");
                ubyte[2048] buf;
                auto n = f.rawRead(buf[]).length;
                text = cast(string)(buf[0 .. n].idup);
            }
            catch (Exception) { }

            if (!isPrintableUtf8(text))
            {
                previewBox.label(filename.length ? "?" : null);
                previewBox.alignment(alignClip);
                previewBox.labelsize(75);
                previewBox.labelfont(helvetica);
            }
            else
            {
                int size = previewBox.h() / 20;
                if (size < 6) size = 6;
                else if (size > normalSize) size = normalSize;

                previewBox.label(text);
                previewBox.alignment(cast(Align)(alignClip | alignInside | alignLeft | alignTop));
                previewBox.labelsize(size);
                previewBox.labelfont(courier);
            }
        }
        else if (image !is null
            && (image.w() <= 0 || image.h() <= 0 || image.d() < 0 || image.fail() != 0))
        {
            // Image has errors -- show a big X. FLTK's own check
            // also consults image->count() <= 0; this port never
            // ported a public count() accessor at all (see
            // fl.shared_image's own module comment), so fail() stands
            // in for that piece -- same intent (detect a load that
            // produced no real pixel data), not a byte-for-byte
            // reproduction of FLTK's exact condition shape.
            image.release();
            previewBox.label("X");
            previewBox.alignment(alignClip);
            previewBox.labelsize(70);
            previewBox.labelfont(helvetica);
        }
        else if (image !is null)
        {
            int pbw = previewBox.w() - 20;
            int pbh = previewBox.h() - 20;
            if (image.w() > pbw || image.h() > pbh)
            {
                int w = pbw;
                int h = w * image.h() / image.w();
                if (h > pbh)
                {
                    h = pbh;
                    w = h * image.w() / image.h();
                }
                auto scaled = cast(SharedImage) image.copy(w, h);
                previewBox.image(scaled);
                image.release();
            }
            else
            {
                previewBox.image(image);
            }
            previewBox.alignment(alignClip);
            previewBox.label(cast(string) null);
        }
        else if (newlabel.length)
        {
            previewBox.label(newlabel);
            previewBox.alignment(alignClip);
            previewBox.labelsize(newlabel[0] == '@' ? 75 : 12);
            previewBox.labelfont(helvetica);
        }
        else
        {
            previewBox.label(cast(string) null);
        }

        previewBox.redraw();
    }
}

// ---------------------------------------------------------------------
// Local helpers -- string logic only, no widget dependency.
// ---------------------------------------------------------------------

/// Splits on a single-char separator without std.array.split's
/// template-instantiation overhead mattering here -- named `split_` to
/// avoid shadowing `std.array.split` at call sites that also want it.
private string[] split_(string s, char sep)
{
    string[] parts;
    size_t start = 0;
    foreach (i, c; s)
        if (c == sep) { parts ~= s[start .. i]; start = i + 1; }
    parts ~= s[start .. $];
    return parts;
}

/// `strncmp(a, b, n) == 0` equivalent for D strings shorter than `n`
/// (no null terminator to stop at, so "both strings end at the same
/// point within the window" has to be checked explicitly). Ported
/// from the bare `strncmp()` calls in `fileNameCB()`'s completion loop.
private bool strEqN(string a, string b, int n)
{
    int alen = cast(int) a.length;
    int blen = cast(int) b.length;
    if (alen < n || blen < n)
        return alen == blen && a == b;
    return a[0 .. n] == b[0 .. n];
}

/// Compares two directory names ignoring a trailing slash on either
/// side. Ported from `compare_dirnames()`.
private int compareDirnames(string a, string b)
{
    int alen = cast(int) a.length - 1;
    int blen = cast(int) b.length - 1;
    if (alen < 0 || blen < 0) return alen - blen;
    if (a[alen] != '/') alen++;
    if (b[blen] != '/') blen++;
    if (alen != blen) return alen - blen;
    import std.algorithm.comparison : cmp;
    return cmp(a[0 .. alen], b[0 .. alen]);
}

/// Escapes `/` (and `\`, though real paths on this port's only
/// platform never contain one) as `\/` for display in a `Fl_Menu_`
/// label, where a bare `/` means "submenu boundary". Ported from
/// `quote_pathname()`.
private string quotePathname(string src)
{
    import std.array : appender;
    auto dst = appender!string;
    foreach (c; src)
    {
        if (c == '\\' || c == '/') { dst.put('\\'); dst.put('/'); }
        else dst.put(c);
    }
    return dst.data;
}

/// Reverses quotePathname(). Ported from `unquote_pathname()`.
private string unquotePathname(string src)
{
    import std.array : appender;
    auto dst = appender!string;
    size_t i = 0;
    while (i < src.length)
    {
        if (src[i] == '\\') i++;
        if (i < src.length) { dst.put(src[i]); i++; }
    }
    return dst.data;
}

/// `Fl_System_Driver::filename_isdir_quick()`: a trailing-slash check
/// before falling back to a real `stat()`-based `filename_isdir()`.
/// Not exposed by `FL/filename.H` FLTK either -- see the module
/// comment.
private bool filenameIsdirQuick(string n)
{
    return (n.length && n[$ - 1] == '/') ? true : filenameIsdir(n);
}

/// Scans `text` for printable UTF-8 content (ASCII-range bytes must be
/// printable-or-whitespace; multi-byte sequences are only checked for
/// well-formed continuation bytes, not full decoding). Ported from
/// `update_preview()`'s first scan loop -- see the module comment for
/// why the second, plain-8-bit fallback scan isn't ported (redundant).
private bool isPrintableUtf8(string text)
{
    import std.ascii : isPrintable = isPrintable, isWhite;

    size_t i = 0;
    while (i < text.length)
    {
        ubyte c = cast(ubyte) text[i];
        if ((c & 0x80) == 0)
        {
            if (!isPrintable(c) && !isWhite(c)) return false;
            i++;
        }
        else if ((c & 0xe0) == 0xc0)
        {
            i++;
            if (!checkContinuation(text, i)) return false;
            i++;
        }
        else if ((c & 0xf0) == 0xe0)
        {
            i++;
            foreach (_; 0 .. 2) { if (!checkContinuation(text, i)) return false; i++; }
        }
        else if ((c & 0xf8) == 0xf0)
        {
            i++;
            foreach (_; 0 .. 3) { if (!checkContinuation(text, i)) return false; i++; }
        }
        else
        {
            i++;
        }
    }
    return true;
}

private bool checkContinuation(string text, size_t i)
{
    if (i >= text.length) return true; // matches FLTK's lenient end-of-buffer handling
    return (cast(ubyte) text[i] & 0xc0) == 0x80;
}

unittest
{
    // split_(): including FLTK's "middle empty segments survive,
    // a trailing empty one doesn't" quirk (see filter()'s doc comment).
    assert(split_("a\tb\tc", '\t') == ["a", "b", "c"]);
    assert(split_("a\t\tb", '\t') == ["a", "", "b"]);
    assert(split_("solo", '\t') == ["solo"]);
}

unittest
{
    // strEqN(): strncmp(a,b,n)==0 semantics, including the
    // shorter-than-n "must end at the same point" case.
    assert(strEqN("hello", "help", 3));
    assert(!strEqN("hello", "help", 4));
    assert(strEqN("ab", "ab", 5)); // both end at the same point within n
    assert(!strEqN("ab", "abc", 5));
    assert(strEqN("", "", 0));
}

unittest
{
    // compareDirnames(): trailing-slash-insensitive comparison.
    assert(compareDirnames("/home/user", "/home/user/") == 0);
    assert(compareDirnames("/home/user", "/home/user2") != 0);
    assert(compareDirnames("/", "/") == 0);
}

unittest
{
    // quotePathname()/unquotePathname(): round trip, and the
    // Fl_Menu_-hierarchy-escaping behavior itself.
    assert(quotePathname("/home/user") == "\\/home\\/user");
    assert(unquotePathname(quotePathname("/home/user")) == "/home/user");
    assert(unquotePathname("\\/home\\/user") == "/home/user");
}

unittest
{
    // isPrintableUtf8(): plain ASCII, whitespace, real UTF-8, and
    // binary/non-printable content.
    assert(isPrintableUtf8("hello, world\n"));
    assert(isPrintableUtf8("café")); // 2-byte UTF-8 sequence
    assert(isPrintableUtf8(""));
    assert(!isPrintableUtf8("bin\x01ary"));
    assert(!isPrintableUtf8("\xc0A")); // 2-byte lead followed by a non-continuation byte
}

// ---------------------------------------------------------------------
// Free-function convenience wrappers, ported from src/fl_file_dir.cxx.
// ---------------------------------------------------------------------

private FileChooser fc_;
private void delegate(string) currentCallback_;
private string currentLabel_ = "OK"; // ok's default value, see fl.ask

/// Ported from `fl_file_chooser_callback()`.
void fileChooserCallback(void delegate(string) cb)
{
    currentCallback_ = cb;
}

/// Ported from `fl_file_chooser_ok_label()`.
void fileChooserOkLabel(string l)
{
    currentLabel_ = l.length ? l : ok;
}

private void popupChooser(FileChooser chooser)
{
    chooser.show();

    auto g = grab();
    if (g !is null) grab(null);

    while (chooser.shown())
        wait();

    if (g !is null) grab(g);
}

/// Shows a file chooser dialog and gets a filename. Ported from
/// `fileChooser()`.
string fileChooser(string message, string pat, string fname, bool relative = false)
{
    if (fc_ is null)
    {
        string initial = fname.length == 0 ? "." : fname;
        fc_ = new FileChooser(initial, pat, create, message);
        fc_.callback((c) { if (currentCallback_ !is null && c.value() !is null) currentCallback_(c.value()); });
    }
    else
    {
        fc_.type(create);

        bool samePattern = (fc_.filter() == pat)
            || (fc_.filter().length == 0 && pat.length == 0);
        fc_.filter(pat);
        fc_.label(message);

        if (fname is null)
        {
            if (!samePattern && fc_.value() !is null)
            {
                string retname = fc_.value();
                auto p = retname.lastIndexOf('/');
                if (p >= 0) retname = (p == 0) ? "/" : retname[0 .. p];
                fc_.value(retname);
            }
        }
        else if (fname.length == 0)
        {
            string retname = fc_.value() !is null ? fc_.value() : "";
            string n = filenameName(retname);
            if (n.length && n.length <= retname.length) retname = retname[0 .. $ - n.length];

            if (retname.length)
            {
                fc_.value("");
                fc_.directory(retname);
            }
            else
            {
                string dirsave = fc_.directory();
                fc_.value("");
                fc_.directory(dirsave);
            }
        }
        else
        {
            fc_.value(fname);
        }
    }

    fc_.okLabel(currentLabel_);
    popupChooser(fc_);

    string val = fc_.value();
    if (val !is null && relative) return filenameRelative(val);
    return val;
}

/// Shows a file chooser dialog and gets a directory. Ported from
/// `dirChooser()`.
string dirChooser(string message, string fname, bool relative = false)
{
    if (fc_ is null)
    {
        string initial = fname.length == 0 ? "." : fname;
        fc_ = new FileChooser(initial, "*", create | directoryType, message);
        fc_.callback((c) { if (currentCallback_ !is null && c.value() !is null) currentCallback_(c.value()); });
    }
    else
    {
        fc_.type(create | directoryType);
        fc_.filter("*");
        if (fname.length) fc_.value(fname);
        fc_.label(message);
    }

    popupChooser(fc_);

    string val = fc_.value();
    if (val !is null && relative) return filenameRelative(val);
    return val;
}
