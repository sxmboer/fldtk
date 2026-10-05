/*
 * Ported from FL/Fl_File_Browser.H + src/Fl_File_Browser.cxx
 * (FLTK 1.5.0).
 *
 * A fl.browser.Browser subclass specialized for displaying filenames:
 * multi-line item height (each embedded `'\n'` adds a text line),
 * directory names shown in bold with a trailing `'/'`, and a per-file
 * icon drawn from a registered `fl.file_icon.FileIcon`.
 *
 * Deliberate deviations:
 *
 *  - `fl.file_icon.loadSystemIcons()` registers at least the three
 *    built-in vector icons on any system (see that module's own row):
 *    `loadDirectory()` looks each entry up via `FileIcon.find()` and
 *    attaches the match as the line's `Object data`
 *    (`Browser.insert()`/`add()`'s existing optional user-data
 *    parameter -- no new storage needed), and
 *    `itemHeight()`/`itemWidth()`/`itemDraw()` branch on
 *    `FileIcon.first() !is null` exactly like FLTK, drawing the
 *    per-line icon via its own `draw()` (yellow when selected, light2
 *    otherwise, matching FLTK's `FL_YELLOW`/`FL_LIGHT2`).
 *
 *  - `load(const char*, Fl_File_Sort_F*)` is ported as
 *    `loadDirectory()`, not an overload of `load()` -- `Browser`
 *    already has its own `load(filename)` (one file line per browser
 *    line, no directory listing at all); giving the directory-lister
 *    a default-valued second parameter (`sortFn = null`) means a
 *    single-string call would be genuinely ambiguous between the two
 *    if both were named `load()` and brought into one overload set
 *    (D resolves this differently from FLTK's C++, which has no
 *    trouble keeping the two `load()` overloads distinct by arity
 *    alone) -- a distinct name sidesteps the ambiguity outright.
 *    It doesn't go through `Fl::system_driver()->
 *    file_browser_load_directory()`/`fl_filename_list()` (the
 *    FLTK driver-abstraction path for enumerating a directory) --
 *    this port lists directories directly via `std.file.dirEntries()`
 *    and matches the existing `fl.filename.filenameMatch()` port for
 *    the filter pattern, consistent with this project's general
 *    "concrete implementation over a driver-abstraction layer built
 *    for one platform" convention (see fl.platform_x11's own module
 *    comment). `Fl_File_Sort_F` (a `dirent**`-comparing C function
 *    pointer type) has no D equivalent shape to port either, since
 *    nothing here touches a raw `dirent`; the sort parameter is a
 *    plain `string`-comparing delegate instead (delegate-over-
 *    function-pointer, the usual substitution -- see CONVENTIONS.md),
 *    defaulting to a small natural/numeric-aware comparator in place
 *    of FLTK's unported `fl_numericsort()`.
 *
 *  - Listing "all mount points" (FLTK's behavior when `directory`
 *    is `""`, via a further driver-specific
 *    `file_browser_load_filesystem()` call) isn't ported -- a
 *    genuinely platform-specific feature (parsing `/proc/mounts` or
 *    similar) out of scope for this pass. `load("")` returns `false`
 *    with an explanatory `errmsg()` instead of silently doing nothing.
 *
 *  - Found a likely FLTK bug while reading the source, NOT
 *    replicated here: `Fl_File_Browser::full_height()` calls
 *    `item_height(find_line(i))` with `i` starting at *0* and running
 *    to `size()-1`, but `find_line()` is documented and implemented
 *    throughout the rest of `Fl_Browser` as strictly 1-based (line
 *    numbers `1..size()`) -- `find_line(0)` always resolves to `NULL`
 *    by tracing `Fl_Browser::find_line()`'s own cache/bisection logic
 *    by hand. In FLTK this doesn't crash only by coincidence:
 *    `Fl_File_Browser::item_height(NULL)` calls `bline_txt(NULL)`
 *    first (computing a dangling `NULL+offset` pointer, which is
 *    "safe" in C++ *only* because forming a flexible-array-member
 *    address doesn't itself dereference anything) before its own
 *    `if (line != NULL)` guard skips ever reading through that
 *    pointer -- so the net effect is just a silently-wrong total
 *    (missing the true last item's height, substituting a bogus
 *    default height for a nonexistent "line 0" instead). This does
 *    NOT carry over safely to D: `Object` is a real reference type,
 *    and dereferencing a field on a `null` reference is a genuine,
 *    immediate runtime error here, not harmless pointer arithmetic --
 *    faithfully replicating the 0-based loop would crash this port on
 *    the very first `draw()` of any non-empty `FileBrowser`. Since
 *    `fl.browser.Browser`'s own cached `fullHeight()` (incrementally
 *    maintained by `insertNode()`, which already calls `itemHeight()`
 *    *virtually* -- correctly reaching `FileBrowser`'s own override
 *    even during `Browser`'s insert bookkeeping) already produces the
 *    right total without this bug's help, `full_height()` simply
 *    isn't overridden here at all; `incr_height()`'s `item_height(0)`
 *    call is ported with an explicit `item is null` guard in
 *    `itemHeight()` instead of relying on the same accidental C
 *    pointer-arithmetic safety. Filed as an FLTK_ISSUES.md
 *    candidate (off-by-one line-number bug, not a crash FLTK, but
 *    a wrong height sum) rather than silently worked around.
 */
module fl.file_browser;

import fl.browser;
import fl.enumerations;
import fl.core;
import fldraw = fl.draw;
import fl.filename : filenameMatch;
import fl.file_icon : FileIcon;
import std.file : dirEntries, SpanMode;
import std.path : baseName, buildPath;
import std.algorithm.sorting : sort;
import std.algorithm.mutation : SwapStrategy;

/// filetype() values (FLTK's anonymous enum FILES/DIRECTORIES).
enum int fileBrowserFiles = 0;
enum int fileBrowserDirectories = 1;

alias FileSortFunc = int delegate(string a, string b);

/// A small natural/numeric-aware comparator, standing in for
/// FLTK's unported `fl_numericsort()` (see the module comment):
/// runs of digits compare numerically (so "file2" sorts before
/// "file10"), everything else compares byte-for-byte.
int defaultFileSort(string a, string b)
{
    size_t i = 0, j = 0;
    while (i < a.length && j < b.length)
    {
        if (isDigit(a[i]) && isDigit(b[j]))
        {
            size_t si = i, sj = j;
            while (i < a.length && isDigit(a[i])) i++;
            while (j < b.length && isDigit(b[j])) j++;
            auto na = stripLeadingZeros(a[si .. i]);
            auto nb = stripLeadingZeros(b[sj .. j]);
            if (na.length != nb.length) return na.length < nb.length ? -1 : 1;
            if (na != nb) return na < nb ? -1 : 1;
        }
        else
        {
            if (a[i] != b[j]) return a[i] < b[j] ? -1 : 1;
            i++;
            j++;
        }
    }
    if (i < a.length) return 1;
    if (j < b.length) return -1;
    return 0;
}

private bool isDigit(char c) { return c >= '0' && c <= '9'; }

private string stripLeadingZeros(string s)
{
    size_t i = 0;
    while (i + 1 < s.length && s[i] == '0') i++;
    return s[i .. $];
}

class FileBrowser : Browser
{
    private
    {
        int filetype_;
        string directory_;
        ubyte iconsize_;
        string pattern_;
        string errmsg_;
    }

    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        pattern_ = "*";
        directory_ = "";
        iconsize_ = cast(ubyte)(3 * textsize() / 2);
        filetype_ = fileBrowserFiles;
        errmsg_ = null;
    }

    /// Icon size, in pixels (default 20).
    ubyte iconsize() const { return iconsize_; }
    void iconsize(ubyte s) { iconsize_ = s; redraw(); } /// ditto

    /// Filename filter pattern, matched via fl.filename.filenameMatch().
    void filter(string pattern) { pattern_ = pattern.length ? pattern : "*"; }
    string filter() const { return pattern_; } /// ditto

    /// fileBrowserFiles (show files and directories) or
    /// fileBrowserDirectories (directories only).
    int filetype() const { return filetype_; }
    void filetype(int t) { filetype_ = t; } /// ditto

    void errmsg(string emsg) { errmsg_ = emsg; }
    string errmsg() const { return errmsg_; }

    override Fontsize textsize() const { return super.textsize(); }
    override void textsize(Fontsize s)
    {
        super.textsize(s);
        iconsize_ = cast(ubyte)(3 * s / 2);
    }

    protected override int incrHeight() const { return itemHeight(null) + linespacing(); }

    protected override int itemHeight(Object item) const
    {
        fldraw.fl_font(textfont(), textsize());
        int textheight = fldraw.height();
        int height = textheight;

        if (item !is null)
        {
            foreach (c; blineTxt(item))
                if (c == '\n') height += textheight;
        }

        if (FileIcon.first() !is null && height < iconsize_)
            height = iconsize_;

        height += 2;
        return height;
    }

    protected override int itemWidth(Object item) const
    {
        if (item is null) return 2;
        const(char)[] text = blineTxt(item);
        const(int)[] columns = columnWidths();

        if (text.length > 0 && text[$ - 1] == '/')
            fldraw.fl_font(textfont() | bold, textsize());
        else
            fldraw.fl_font(textfont(), textsize());

        bool hasNewline = false, hasColumn = false;
        foreach (c; text)
        {
            if (c == '\n') hasNewline = true;
            if (c == columnChar()) hasColumn = true;
        }

        int width;
        if (!hasNewline && !hasColumn)
        {
            width = cast(int)(fldraw.width(text) + 0.5);
        }
        else
        {
            int tempwidth = 0;
            int column = 0;
            size_t fragStart = 0;

            void measure(size_t end)
            {
                int w = cast(int)(fldraw.width(text[fragStart .. end]) + 0.5);
                tempwidth += w;
                if (tempwidth > width) width = tempwidth;
            }

            for (size_t i = 0; i < text.length; i++)
            {
                if (text[i] == '\n')
                {
                    measure(i);
                    fragStart = i + 1;
                    tempwidth = 0;
                    column = 0;
                }
                else if (text[i] == columnChar())
                {
                    column++;
                    // FLTK's `for(i=0;i<column&&columns[i];i++)
                    // tempwidth+=columns[i];` -- sums configured
                    // column widths up to the first zero-terminator.
                    tempwidth = sumColumnWidths(columns, column);
                    if (tempwidth > width) width = tempwidth;
                    fragStart = i + 1;
                }
            }
            if (fragStart < text.length || text.length == 0) measure(text.length);
        }

        if (FileIcon.first() !is null)
            width += iconsize_ + 8;

        width += 2;
        return width;
    }

    protected override void itemDraw(Object item, int X, int Y, int W, int H) const
    {
        if (item is null) return;
        const(char)[] text = blineTxt(item);
        char flags = blineFlags(item);

        if (text.length > 0 && text[$ - 1] == '/')
            fldraw.fl_font(textfont() | bold, textsize());
        else
            fldraw.fl_font(textfont(), textsize());

        Color c = (flags & 1) ? fldraw.contrast(textcolor(), selectionColor()) : textcolor();

        if (FileIcon.first() is null)
        {
            // No icons registered at all -- just draw the text.
            X += 1;
            W -= 2;
        }
        else
        {
            auto icon = cast(FileIcon) blineData(item);
            if (icon !is null)
                icon.draw(X, Y + (H - iconsize_) / 2, iconsize_, iconsize_,
                    (flags & 1) ? yellow : light2, activeR());

            X += iconsize_ + 9;
            W -= iconsize_ - 10;
        }

        int height = fldraw.height();
        foreach (ch; text) if (ch == '\n') height += fldraw.height();
        Y += (H - height) / 2;

        const(int)[] columns = columnWidths();
        int width = 0;
        int column = 0;

        fldraw.fl_color(activeR() ? c : fldraw.inactive(c));

        size_t fragStart = 0;
        for (size_t i = 0; i < text.length; i++)
        {
            if (text[i] == '\n')
            {
                fldraw.fl_draw(cast(string) text[fragStart .. i], X + width, Y, W - width, fldraw.height(),
                    cast(Align)(alignLeft | alignClip));
                fragStart = i + 1;
                width = 0;
                Y += fldraw.height();
                column = 0;
            }
            else if (text[i] == columnChar())
            {
                int cW = W - width;
                // FLTK: cW = columns[column] only if columns[0..column]
                // are all configured (nonzero) too -- see module comment.
                if (columnEntryValid(columns, column)) cW = columns[column];

                fldraw.fl_draw(cast(string) text[fragStart .. i], X + width, Y, cW, fldraw.height(),
                    cast(Align)(alignLeft | alignClip));

                column++;
                width = sumColumnWidths(columns, column);
                fragStart = i + 1;
            }
        }
        if (fragStart < text.length || text.length == 0)
            fldraw.fl_draw(cast(string) text[fragStart .. $], X + width, Y, W - width, fldraw.height(),
                cast(Align)(alignLeft | alignClip));
    }

    /// Clears the browser and loads directory's entries (directories
    /// first, in bold with a trailing '/', then files matching
    /// filter()). See the module comment for what's deliberately not
    /// ported (mount-point listing for directory == "") and why this
    /// isn't named load().
    bool loadDirectory(string directory, FileSortFunc sortFn = null)
    {
        errmsg(null);
        clear();
        directory_ = directory;

        if (directory.length == 0)
        {
            errmsg("Listing filesystem mount points is not supported by this port");
            return false;
        }

        struct Entry
        {
            string name; // display name (bare, no path)
            string path; // full path, for FileIcon.find()
            bool isDir;
        }

        Entry[] entries;
        try
        {
            foreach (e; dirEntries(directory, SpanMode.shallow))
                entries ~= Entry(baseName(e.name), e.name, e.isDir);
        }
        catch (Exception e)
        {
            errmsg(e.msg);
            return false;
        }

        // std.file.dirEntries() never yields "."/".." pseudo-entries the
        // way POSIX scandir()/readdir() do -- FLTK's own
        // Fl_File_Browser::load() relies on ".." being present in its
        // raw directory listing to show a real, clickable "go up" row
        // (its own load() loop explicitly skips only "./", never
        // "../"). Without it, an otherwise-empty (but perfectly
        // navigable) directory would look genuinely empty to
        // rescan()'s `fileList.size() == 0` check, showing a spurious
        // "No files found..." error box instead of FLTK's own "../"
        // row. Added back explicitly so it sorts and displays exactly
        // like any other directory entry.
        entries ~= Entry("..", buildPath(directory, ".."), true);

        FileSortFunc cmp = sortFn !is null ? sortFn : (a, b) => defaultFileSort(a, b);
        entries.sort!((a, b) => cmp(a.name, b.name) < 0, SwapStrategy.stable);

        int numDirs = 0;
        foreach (e; entries)
        {
            auto icon = FileIcon.find(e.path); // by full path, matching FLTK
            if (e.isDir)
            {
                numDirs++;
                insert(numDirs, e.name ~ "/", icon); // trailing '/' marks directories, see item*() above
            }
            else if (filetype_ == fileBrowserFiles && filenameMatch(e.name, pattern_))
            {
                add(e.name, icon);
            }
        }
        return true;
    }
}

// Sums columns[0 .. n), stopping at the first missing/zero entry --
// matches FLTK's `for(i=0;i<n&&columns[i];i++) sum+=columns[i];`.
private int sumColumnWidths(const(int)[] columns, int n)
{
    int sum = 0;
    for (int i = 0; i < n; i++)
    {
        if (i >= columns.length || columns[i] == 0) break;
        sum += columns[i];
    }
    return sum;
}

// True if columns[0..idx] all exist and are nonzero -- matches
// FLTK's after-the-fact `if (columns[i])` check once its own
// `for(i=0;i<=idx&&columns[i];i++);` loop stops.
private bool columnEntryValid(const(int)[] columns, int idx)
{
    for (int i = 0; i <= idx; i++)
        if (i >= columns.length || columns[i] == 0) return false;
    return true;
}

unittest
{
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto b = new FileBrowser(0, 0, 200, 100);
    b.end();

    assert(b.filetype() == fileBrowserFiles);
    assert(b.filter() == "*");
    assert(b.iconsize() == cast(ubyte)(3 * b.textsize() / 2));
    assert(b.errmsg() is null);

    b.filter("*.d");
    assert(b.filter() == "*.d");
    b.filter(null);
    assert(b.filter() == "*"); // null resets to "*", matching FLTK

    FlGroup.current(null);
}

unittest
{
    // defaultFileSort(): numeric runs compare by value, not lexically.
    assert(defaultFileSort("file2", "file10") < 0);
    assert(defaultFileSort("file10", "file2") > 0);
    assert(defaultFileSort("abc", "abd") < 0);
    assert(defaultFileSort("same", "same") == 0);
    assert(defaultFileSort("a", "ab") < 0);
}

unittest
{
    // loadDirectory() against a real temp directory: directories sort first
    // (bold/trailing '/' convention), files matching filter() second.
    import fl.group : FlGroup;
    import std.file : mkdir, mkdirRecurse, write, rmdirRecurse, exists, tempDir;
    import std.path : buildPath;
    import std.uuid : randomUUID;
    FlGroup.current(null);

    string dir = buildPath(tempDir(), "fldtk-file-browser-test-" ~ randomUUID().toString());
    mkdirRecurse(buildPath(dir, "subdir"));
    write(buildPath(dir, "a.txt"), "hi");
    write(buildPath(dir, "b.log"), "hi");
    scope(exit) if (exists(dir)) rmdirRecurse(dir);

    auto win = new FlGroup(0, 0, 300, 300);
    auto b = new FileBrowser(0, 0, 200, 100);
    win.end();

    assert(b.loadDirectory(dir));
    assert(b.size() == 4); // ../, subdir/, a.txt, b.log

    assert(b.text(1) == "../"); // ".." sorts before "subdir" ('.' < 's')
    assert(b.text(2) == "subdir/"); // directories listed first, trailing '/'

    b.filter("*.txt");
    assert(b.loadDirectory(dir));
    assert(b.size() == 3); // ../, subdir/, a.txt (b.log filtered out)

    assert(!b.loadDirectory(""));
    assert(b.errmsg() !is null);

    FlGroup.current(null);
}

unittest
{
    // itemHeight()/itemWidth()/itemDraw() headless smoke test,
    // including a null item (incrHeight()'s own call pattern).
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto win = new FlGroup(0, 0, 300, 300);
    auto b = new FileBrowser(0, 0, 200, 100);
    b.add("subdir/");
    b.add("multi\nline\nentry");
    win.end();

    assert(b.itemHeight(null) > 0); // matches incrHeight()'s own call
    // itemHeight()/itemWidth()/itemDraw() (all overridden here) are
    // exercised indirectly via draw(), which walks every item through
    // Browser_'s own itemFirst()/itemNext() traversal internally.
    b.draw();

    FlGroup.current(null);
}
