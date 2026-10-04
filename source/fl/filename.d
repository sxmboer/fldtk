/*
 * Ported from FL/filename.H (FLTK 1.5.0) + src/filename_ext.cxx,
 * src/filename_setext.cxx, src/filename_isdir.cxx, src/filename_match.cxx,
 * src/filename_expand.cxx, src/filename_absolute.cxx (which also holds
 * filename_relative()), and the driver-level defaults in
 * src/Fl_System_Driver.cxx / src/drivers/Unix/Fl_Unix_System_Driver.cxx.
 *
 * DELIBERATE API DEVIATION: FLTK exposes two parallel surfaces --
 * a C-style `char* + tolen` buffer API (the original, `FL_PATH_MAX`-sized)
 * and a set of `_str` wrappers added later that return `std::string` for
 * C++ callers. This port only has the latter shape, using D `string`
 * (immutable, GC-owned) throughout -- the same substitution CLAUDE.md
 * already documents for `Widget.label()`/`tooltip()`: the buffer-length
 * bookkeeping the C API needs has no D equivalent worth keeping.
 * Functions are also "does this filename look absolute" boolean-free --
 * e.g. `filenameAbsolute()`/`filenameRelative()` just return the
 * resulting string (FLTK's C API additionally returns an int "did
 * anything change" flag via the return value, alongside writing through
 * the output buffer; no caller in this port needs that signal, and
 * string equality already answers the same question if one ever does).
 *
 * Not ported: `fl_filename_list()`/`fl_filename_free_list()` (a portable
 * `scandir()` wrapper) and `fl_decode_uri()` -- both exist to back a file
 * chooser's own directory listing (`fl.file_chooser`/`fl.native_file_chooser`,
 * both done now, but neither ended up needing this specific pair -- see
 * their own module comments for what they use instead) or percent-decoding
 * a URI's path component, and still have no caller in this port.
 * `Fl_File_Sort_F`, `fl_alphasort()`/`fl_casealphasort()`/
 * `fl_casenumericsort()`/`fl_numericsort()` (the sort-order callbacks for
 * that scandir wrapper) skipped for the same reason.
 *
 * `openUri()` (`fl.help_view`'s first real caller, for non-`file:`
 * link schemes -- http/https/ftp/mailto/news) is real on both
 * platforms it's ported for. On Linux, only a minimal port: FLTK's
 * own `Fl_Unix_System_Driver::open_uri()` tries a whole fallback chain
 * of browsers/mail-readers/file-managers (xdg-open, htmlview, firefox,
 * mozilla, netscape, konqueror, ...); this port only tries `xdg-open`
 * (the Portland/freedesktop.org "let the desktop environment pick"
 * launcher -- listed first in every one of FLTK's own fallback
 * arrays), via `std.process.spawnProcess()`, fire-and-forget like
 * FLTK itself (no wait for the launched program to exit, no
 * argv-shape special-casing for specific browsers since xdg-open takes
 * a plain `xdg-open URI` command line either way). On Windows, ported
 * from `Fl_WinAPI_System_Driver::open_uri()`: a single
 * `ShellExecuteW(null, "open", uri, null, null, SW_SHOWNORMAL)` call --
 * Windows' own "hand this to whatever's registered for it" entry
 * point, the direct equivalent of `xdg-open` for this platform. Success
 * is `ShellExecuteW` returning a value `> 32` (its own documented
 * convention -- anything `<= 32` is an `SE_ERR_*` failure code, not a
 * real `HINSTANCE`).
 *
 * `filenameExpand()`'s `~user` (another user's home directory, not the
 * current user's `~`) is POSIX-only (`getpwnam()`), guarded by
 * `version (Posix)`; matches this project's Linux-primary/Windows-
 * secondary scope (`~` alone still works everywhere via the `HOME`
 * environment variable). `filenameRelative()`'s case-insensitive mode
 * (FLTK's Windows/macOS path-comparison variant) isn't ported --
 * only the case-sensitive behavior Linux/Wayland need.
 */
module fl.filename;

import std.file : exists, isDir, getcwd;
import std.process : environment;
import std.string : toStringz, indexOf;

/// Ported from `Fl_System_Driver::isdirsep()` (`filename_absolute.cxx`,
/// `{return c == '/';}`) on Linux, but `Fl_WinAPI_System_Driver::
/// isdirsep()` (`{return c == '/' || c == '\\';}`) on Windows -- a real,
/// separate override FLTK itself has, not a Linux-only detail this
/// port skipped: confirmed by reading `~/Repositories/fltk`'s own
/// `Fl_WinAPI_System_Driver.cxx`, both `filename_absolute()` and the
/// `filename_relative()` helpers there scan for `\` as a separator too.
/// This port has no per-platform driver-class split (matching every
/// other module's own "concrete implementation, `version()` choice, no
/// abstraction until a real second backend needs one" precedent -- see
/// e.g. `fl.file_chooser`'s own module comment on the identical
/// `backslash_as_slash()`/`colon_is_drive()` pair), so the two real
/// FLTK bodies collapse into one function with a `version (Windows)`
/// branch instead of two driver subclasses.
private bool isDirSep(char c)
{
    version (Windows) return c == '/' || c == '\\';
    else return c == '/';
}

/**
 * Returns the name part of filename -- everything after the last
 * separator, or the whole string if there's none. Ported from
 * `Fl_Unix_System_Driver::filename_name()` on Linux (`'/'` only);
 * matches its documented quirks: `"/usr/"` -> `""` (unlike POSIX
 * `basename(3)`, which would return `"usr"`), `"/"` -> `""`, `"."` ->
 * `"."`, `".."` -> `".."`. **`Fl_WinAPI_System_Driver::filename_name()`
 * on Windows** is a genuinely different body, not just this same one
 * widened to accept `\` too -- confirmed by reading the real source
 * (`Fl_win32.cxx`) rather than assumed: it also skips a leading drive
 * letter first (`if (q[0] && q[1] == ':') q += 2;`), so `filenameName
 * ("C:file.txt")` (a drive-relative path with no separator at all,
 * legal on Windows) correctly returns `"file.txt"`, not the whole
 * string including the drive letter. Getting this right matters for
 * real, not just theoretically: `samples/test/demo.d`'s own
 * `filenameName(args[0])` call silently returned the *entire* argv[0]
 * path unchanged on Windows before this fix (no `/` anywhere in a
 * normal `C:\...\demo.exe` argv[0]), which then fed into a
 * `dataPath ~ "/" ~ fn`-style concatenation elsewhere and produced a
 * visibly duplicated path.
 */
string filenameName(string path)
{
    string q = path;
    version (Windows)
        if (q.length >= 2 && q[1] == ':') q = q[2 .. $];
    ptrdiff_t lastSlash = -1;
    foreach (i, c; q)
        if (isDirSep(c)) lastSlash = i;
    return q[lastSlash + 1 .. $];
}

/// Returns the path part of filename -- everything up to and including
/// the last '/', or "" if there's none. Not an FLTK function by
/// itself; FLTK's `fl_filename_path_str()` (filename_absolute.cxx)
/// does the equivalent via `fl_filename_name()`.
string filenamePath(string path)
{
    auto name = filenameName(path);
    return path[0 .. $ - name.length];
}

/**
 * Returns the extension of filename, including the leading '.', or ""
 * if there's none. Ported from `Fl_System_Driver::filename_ext()`
 * (src/filename_ext.cxx) -- the last '.' after the last separator --
 * but using `isDirSep()` (not a literal `'/'`) so this also matches
 * `Fl_WinAPI_System_Driver::filename_ext()`'s identical body on Windows
 * (`Fl_WinAPI_System_Driver.cxx`: same algorithm, its own widened
 * `isdirsep()`).
 */
string filenameExt(string path)
{
    ptrdiff_t lastDot = -1;
    foreach (i, c; path)
    {
        if (isDirSep(c)) lastDot = -1;
        else if (c == '.') lastDot = i;
    }
    return lastDot >= 0 ? path[lastDot .. $] : "";
}

/// Returns a copy of path with its extension replaced by ext (which
/// should include the leading '.'; "" removes the extension entirely).
/// Ported from fl_filename_setext() (src/filename_setext.cxx).
string filenameSetExt(string path, string ext)
{
    auto curExt = filenameExt(path);
    return path[0 .. $ - curExt.length] ~ ext;
}

version (Posix)
private string posixHomeDir(string username)
{
    import core.sys.posix.pwd : getpwnam;
    import std.string : fromStringz;

    auto pw = getpwnam(username.toStringz());
    return (pw is null || pw.pw_dir is null) ? null : pw.pw_dir.fromStringz.idup;
}
else
private string posixHomeDir(string username) { return null; }

/**
 * Expands a filename containing shell variables and a leading tilde:
 * `"~"`/`"~/rest"` (current user's `$HOME`), `"~user/rest"` (that
 * user's home directory, POSIX only -- see the module note), and
 * `"$VARNAME"` (an environment variable; does NOT handle `${VARNAME}`).
 * Ported from Fl_System_Driver::filename_expand()
 * (src/Fl_System_Driver.cxx); unlike FLTK's in-place buffer
 * rewrite, this only expands the first '/'-delimited component (a
 * substituted home/env value starting with more path segments is not
 * re-scanned for a second `~`/`$` prefix) -- behaviorally identical for
 * every realistic input, since expanded values are themselves plain
 * paths, never `~`/`$`-prefixed.
 */
string filenameExpand(string from)
{
    import std.string : indexOf;

    string result;
    size_t i = 0;
    while (i < from.length)
    {
        auto slash = from[i .. $].indexOf('/');
        size_t end = slash < 0 ? from.length : i + slash;
        string component = from[i .. end];
        string value;

        if (component.length && component[0] == '~')
            value = component.length == 1
                ? environment.get("HOME", "")
                : posixHomeDir(component[1 .. $]);
        else if (component.length && component[0] == '$')
            value = environment.get(component[1 .. $], "");

        if (value.length)
        {
            if (isDirSep(value[$ - 1])) value = value[0 .. $ - 1];
            result = isDirSep(value[0]) ? value : result ~ value;
        }
        else
            result ~= component;

        i = end;
        if (i < from.length) { result ~= from[i]; i++; }
    }
    return result;
}

/**
 * Makes from absolute, resolving `.`/`..` segments against base (which
 * defaults to the current working directory). Already-absolute paths
 * (starting with '/', or with a drive letter like `C:` on Windows --
 * `Fl_WinAPI_System_Driver::filename_absolute()`'s own `from[1]==':'`
 * check, confirmed by reading the real source rather than assumed) and
 * FLTK's `'|'`-prefixed special paths are returned unchanged, matching
 * FLTK. Ported from Fl_System_Driver::filename_absolute()
 * (src/filename_absolute.cxx) on Linux, `Fl_WinAPI_System_Driver::
 * filename_absolute()` on Windows -- **the drive-letter check matters
 * for real, not just theoretically**: without it, an already-absolute
 * `C:\...` path reaching this function (e.g. `fl.file_chooser.
 * FileChooser.directory()`, or a `-menufile`-style command-line
 * argument) would fail the "already absolute" test (`C` isn't a
 * directory separator), fall through to the relative-path branch below,
 * and come back as `base ~ "/" ~ from` -- a duplicated, doubled path
 * exactly matching a real symptom seen on this port's Windows build
 * (`samples/test/demo.d`'s own menu-file lookup).
 */
string filenameAbsolute(string from, string base = null)
{
    if (base is null) base = getcwd();
    if (from.length == 0 || isDirSep(from[0]) || from[0] == '|' || base.length == 0)
        return from;
    version (Windows)
        if (from.length >= 2 && from[1] == ':') return from;

    // Fl_WinAPI_System_Driver::filename_absolute()'s own "ha ha"-commented
    // line: base (usually getcwd(), which returns backslashes on Windows)
    // gets its separators normalized to '/' before building the result --
    // from's own separators are left alone, matching upstream exactly.
    version (Windows)
    {
        import std.array : replace;
        if (base.indexOf('\\') >= 0) base = base.replace('\\', '/');
    }

    string result = isDirSep(base[$ - 1]) ? base[0 .. $ - 1] : base;
    string start = from;

    while (start.length && start[0] == '.')
    {
        if (start.length >= 2 && start[1] == '.'
            && (start.length == 2 || isDirSep(start[2])))
        {
            ptrdiff_t idx = -1;
            foreach_reverse (i, c; result)
                if (isDirSep(c)) { idx = i; break; }
            if (idx < 0) break;
            result = result[0 .. idx];
            start = start.length == 2 ? start[2 .. $] : start[3 .. $];
        }
        else if (start.length >= 2 && isDirSep(start[1]))
            start = start[2 .. $];
        else if (start.length == 1)
        {
            start = start[1 .. $];
            break;
        }
        else
            break;
    }
    return result ~ "/" ~ start;
}

/**
 * Makes dest relative to base (which defaults to the current working
 * directory), similar to C++17 `std::filesystem::path::lexically_relative`.
 * Purely lexical: both paths must already be absolute and contain no
 * `.`/`..` segments or double separators, or dest is returned unchanged
 * (matching FLTK's "no change" fallback). Ported from
 * Fl_System_Driver::filename_relative_() (src/filename_absolute.cxx),
 * case-sensitive branch only -- see the module note.
 */
string filenameRelative(string dest, string base = null)
{
    if (base is null) base = getcwd();
    if (dest.length == 0 || base.length == 0 || !isDirSep(base[0]) || !isDirSep(dest[0]))
        return dest;

    size_t bi = 0, di = 0;
    size_t baseSep = 0, destSep = 0;
    for (;;)
    {
        bi++;
        di++;
        char b = bi < base.length ? base[bi] : '\0';
        char d = di < dest.length ? dest[di] : '\0';
        bool bEnd = b == '\0' || isDirSep(b);
        bool dEnd = d == '\0' || isDirSep(d);
        if (bEnd && dEnd) { baseSep = bi; destSep = di; }
        if (b == '\0' || d == '\0') break;
        if (b != d) break;
    }

    bool baseExhausted = bi >= base.length || (isDirSep(base[bi]) && bi + 1 >= base.length);
    bool destExhausted = di >= dest.length || (isDirSep(dest[di]) && di + 1 >= dest.length);
    if (baseExhausted && destExhausted) return ".";

    int nUp = 0;
    for (size_t p = baseSep; p < base.length; p++)
        if (isDirSep(base[p]) && p + 1 < base.length) nUp++;

    string result;
    if (nUp > 0) result = "..";
    foreach (_; 1 .. nUp) result ~= "/..";

    if (destSep < dest.length)
    {
        if (nUp) result ~= "/";
        result ~= dest[destSep + 1 .. $];
    }
    return result;
}

/**
 * Checks whether s matches the glob-like pattern p: `?` any single
 * char, `*` any run of chars, `[set]`/`[^set]`/`[!set]` a character
 * class (ranges via `a-z`), `{X|Y|Z}` alternation, `\x` to quote a
 * special character. Matching is case-insensitive for literal
 * characters, case-sensitive within `[set]` ranges -- exactly FLTK's
 * documented behavior. Ported from fl_filename_match()
 * (src/filename_match.cxx), operating on null-terminated copies so the
 * recursive pointer-walking algorithm (including its `goto`-based
 * `{...}` handling) transliterates directly rather than being
 * reinvented on D slices.
 */
bool filenameMatch(string s, string pattern)
{
    return filenameMatchImpl(s.toStringz(), pattern.toStringz()) != 0;
}

private int filenameMatchImpl(const(char)* s, const(char)* p)
{
    import std.ascii : toLower;

    int matched;
    for (;;)
    {
        switch (*p++)
        {
        case '?':
            if (!*s++) return 0;
            break;

        case '*':
            if (!*p) return 1;
            while (!filenameMatchImpl(s, p)) if (!*s++) return 0;
            return 1;

        case '[':
        {
            if (!*s) return 0;
            int reverse = (*p == '^' || *p == '!');
            if (reverse) p++;
            matched = 0;
            char last = 0;
            while (*p)
            {
                if (*p == '-' && last)
                {
                    if (*s <= *++p && *s >= last) matched = 1;
                    last = 0;
                }
                else if (*s == *p)
                    matched = 1;
                last = *p++;
                if (*p == ']') break;
            }
            if (matched == reverse) return 0;
            s++; p++;
            break;
        }

        case '{':
        NEXTCASE:
            if (filenameMatchImpl(s, p)) return 1;
            for (matched = 0;;)
            {
                switch (*p++)
                {
                case '\\': if (*p) p++; break;
                case '{': matched++; break;
                case '}': if (!matched--) return 0; break;
                case '|': case ',': if (matched == 0) goto NEXTCASE; break;
                case '\0': return 0;
                default: break;
                }
            }
            assert(0); // unreachable: the loop above only exits via return/goto

        case '|':
        case ',':
            for (matched = 0; *p && matched >= 0; )
            {
                switch (*p++)
                {
                case '\\': if (*p) p++; break;
                case '{': matched++; break;
                case '}': matched--; break;
                default: break;
                }
            }
            break;

        case '}':
            break;

        case '\0':
            return !*s;

        case '\\':
            if (*p) p++;
            goto default;

        default:
            if (toLower(*s) != toLower(*(p - 1))) return 0;
            s++;
            break;
        }
    }
    assert(0); // unreachable: the loop above only exits via return
}

/**
 * Returns whether path exists and is a directory. Ported from
 * Fl_System_Driver::filename_isdir() (src/filename_isdir.cxx); a
 * trailing '/' is stripped first, matching FLTK's own comment on
 * sloppy `stat()` implementations. Simplified to `std.file`'s
 * exists()/isDir() rather than a raw `stat()` call -- same observable
 * behavior (false for a nonexistent path, matching FLTK's `!stat()`
 * check) without hand-rolling the syscall.
 */
bool filenameIsdir(string path)
{
    if (path.length > 1 && isDirSep(path[$ - 1])) path = path[0 .. $ - 1];
    return exists(path) && isDir(path);
}

unittest
{
    assert(filenameName("/usr/lib") == "lib");
    assert(filenameName("/usr/") == "");
    assert(filenameName("/usr") == "usr");
    assert(filenameName("/") == "");
    assert(filenameName(".") == ".");
    assert(filenameName("..") == "..");
    assert(filenameName("plain") == "plain");

    assert(filenamePath("/usr/lib") == "/usr/");
    assert(filenamePath("plain") == "");

    version (Windows)
    {
        // Regression cases for filenameName()'s Windows path handling:
        // a real-world argv[0]-style path with no forward slash at all
        // -- see that function's own doc comment.
        assert(filenameName(`C:\fldtk\build\demo.exe`) == "demo.exe");
        assert(filenameName(`C:\fldtk\build\`) == "");
        assert(filenameName(`C:file.txt`) == "file.txt"); // drive-relative, no separator at all
        assert(filenameName(`C:\a/b`) == "b"); // mixed separators
    }
}

unittest
{
    assert(filenameExt("/some/path/foo.txt") == ".txt");
    assert(filenameExt("/some/path/foo") == "");
    assert(filenameExt("/some.dir/foo") == "");
    assert(filenameExt(".hidden") == ".hidden");

    assert(filenameSetExt("/path/myfile.cxx", ".txt") == "/path/myfile.txt");
    assert(filenameSetExt("/path/myfile", ".txt") == "/path/myfile.txt");
    assert(filenameSetExt("/path/myfile.cxx", "") == "/path/myfile");

    version (Windows)
        assert(filenameExt(`C:\path\myfile.cxx`) == ".cxx");
}

unittest
{
    import std.process : environment;

    environment["FLDTK_TEST_VAR"] = "/var/tmp";
    scope (exit) environment.remove("FLDTK_TEST_VAR");

    assert(filenameExpand("$FLDTK_TEST_VAR/foo.txt") == "/var/tmp/foo.txt");
    assert(filenameExpand("plain/path") == "plain/path");

    auto home = environment.get("HOME", "");
    if (home.length)
        assert(filenameExpand("~/x") == home ~ "/x");
}

unittest
{
    assert(filenameAbsolute("foo.txt", "/var/tmp") == "/var/tmp/foo.txt");
    assert(filenameAbsolute("./foo.txt", "/var/tmp") == "/var/tmp/foo.txt");
    assert(filenameAbsolute("../log/messages", "/var/tmp") == "/var/log/messages");
    assert(filenameAbsolute("/already/abs", "/var/tmp") == "/already/abs");

    version (Windows)
    {
        // Regression case for filenameAbsolute()'s Windows handling:
        // an already-absolute drive-letter path has no leading '/', so
        // it needs its own "already absolute" check -- see this
        // function's own doc comment.
        assert(filenameAbsolute(`C:\already\abs`, `C:\var\tmp`) == `C:\already\abs`);
        assert(filenameAbsolute("C:/already/abs", "C:/var/tmp") == "C:/already/abs");

        // Regression case for a real reported bug: base (as getcwd()
        // returns it on Windows) is backslash-delimited; the result must
        // come back fully '/'-normalized, not mixed, matching
        // Fl_WinAPI_System_Driver::filename_absolute()'s own backslash-
        // to-slash pass over base before joining it with from.
        assert(filenameAbsolute(".", `C:\fldtk\build`) == "C:/fldtk/build/");
        assert(filenameAbsolute("foo.txt", `C:\fldtk\build`) == "C:/fldtk/build/foo.txt");
    }
}

unittest
{
    assert(filenameRelative("/var/tmp/somedir/foo.txt", "/var/tmp/somedir") == "foo.txt");
    assert(filenameRelative("/var/tmp/foo.txt", "/var/tmp/somedir") == "../foo.txt");
    assert(filenameRelative("/var/tmp/somedir", "/var/tmp/somedir") == ".");
    assert(filenameRelative("foo.txt", "/var/tmp") == "foo.txt"); // not absolute -> unchanged
}

unittest
{
    assert(filenameMatch("foo.txt", "*.txt"));
    assert(!filenameMatch("foo.txt", "*.cxx"));
    assert(filenameMatch("foo.txt", "foo.???"));
    assert(filenameMatch("FOO.TXT", "foo.txt")); // case-insensitive literals
    assert(filenameMatch("abc", "[a-c][a-c][a-c]"));
    assert(!filenameMatch("abd", "[a-c][a-c][a-c]"));
    assert(filenameMatch("foo.txt", "{*.cxx|*.txt}"));
    assert(!filenameMatch("foo.log", "{*.cxx|*.txt}"));
}

unittest
{
    assert(filenameIsdir("/"));
    assert(!filenameIsdir("/nonexistent-fldtk-test-path-xyz"));
    assert(!filenameIsdir(__FILE__)); // a regular file, not a directory
}

/**
 * Opens uri via the system's `xdg-open` launcher (see the module
 * comment for why this is a deliberately minimal subset of FLTK's
 * own multi-program fallback chain). Returns `true` on success --
 * `xdg-open` was found and launched, matching FLTK's own
 * fire-and-forget contract (doesn't guarantee the URI actually opened,
 * just that a handler process was started) -- with `msg` set to the
 * command line that was run, same as FLTK's own success case.
 * Returns `false` with `msg` set to an explanatory message if the URI
 * scheme isn't one of FLTK's own supported set, or if `xdg-open`
 * itself couldn't be found/launched.
 */
bool openUri(string uri, out string msg)
{
    import std.algorithm.searching : startsWith;
    import std.string : indexOf;

    // Matches FLTK openUri()'s own scheme allowlist
    // (src/fl_open_uri.cxx) -- validated here rather than left to
    // xdg-open/ShellExecuteW, same as FLTK validates before ever
    // reaching its Fl_System_Driver::open_uri().
    static immutable string[] schemes = [
        "file://", "ftp://", "http://", "https://", "mailto:", "news://"
    ];
    bool schemeOk = false;
    foreach (s; schemes)
        if (uri.startsWith(s)) { schemeOk = true; break; }
    if (!schemeOk)
    {
        auto colon = uri.indexOf(':');
        msg = colon >= 0
            ? "URI scheme \"" ~ uri[0 .. colon] ~ "\" not supported."
            : "Bad URI \"" ~ uri ~ "\"";
        return false;
    }

    version (Windows)
    {
        import core.sys.windows.windows : ShellExecuteW, SW_SHOWNORMAL, HINSTANCE;
        import std.utf : toUTF16z;

        auto result = ShellExecuteW(null, "open"w.ptr, uri.toUTF16z, null, null, SW_SHOWNORMAL);
        if (cast(size_t) result > 32)
        {
            msg = "ShellExecute " ~ uri;
            return true;
        }
        msg = "No helper application found for \"" ~ uri ~ "\"";
        return false;
    }
    else
    {
        import std.process : spawnProcess, wait, ProcessException;
        import core.thread : Thread;

        try
        {
            auto pid = spawnProcess(["xdg-open", uri]);
            // Reap in the background so a quickly-exiting xdg-open doesn't
            // linger as a zombie for the lifetime of this (typically
            // long-running GUI) process. FLTK's own
            // Fl_Posix_System_Driver::run_program() double-forks + setsid()
            // for the same reason; a detached reaper thread is the cleaner
            // D stdlib substitute for that POSIX daemonizing trick.
            auto reaper = new Thread({ wait(pid); });
            reaper.isDaemon = true;
            reaper.start();
            msg = "xdg-open " ~ uri;
            return true;
        }
        catch (ProcessException)
        {
            msg = "No helper application found for \"" ~ uri ~ "\"";
            return false;
        }
    }
}
