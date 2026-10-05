/**
 * Small, standalone path-display/normalization helpers -- ported from
 * FLTK's `fluid/tools/filename.h`/`.cxx`. Despite the
 * `fl_filename_shortened()` name matching the core `FL/filename.H`
 * naming convention, none of this is actually part of that header --
 * it's Fluid-project-local (FLTK's own file comment: "File names
 * and URI utility functions for FLUID only"), so it's ported here as
 * its own module rather than folded into `fl.filename` (which maps
 * the real `FL/filename.H`). Named `path_util` rather than a bare
 * `filename.d` to avoid exactly that confusion.
 *
 * `filenameShortened()` truncates a path for limited-width display
 * (title bars, recent-files menus) -- not reversible, purely for
 * display. Reimplemented over `dstring` (indexable by Unicode
 * codepoint) rather than transliterating FLTK's own manual
 * `fl_utf8strlen()`-based byte-offset arithmetic (CONVENTIONS.md's "check
 * for a cleaner D stdlib alternative before transliterating a raw C
 * library call" -- this is exactly that case: the byte-offset-of-the-
 * Nth-codepoint dance FLTK needs has no equivalent problem once
 * the string is a random-access codepoint array), with defensive
 * clamping FLTK's own pointer arithmetic doesn't have (harmless
 * for any realistic `maxChars`, but a `dstring` slice with an
 * out-of-range bound throws in D rather than reading adjacent memory
 * the way an unchecked `fl_utf8strlen()` byte offset could -- see
 * `FLTK_ISSUES.md`'s entry on this function's own unclamped
 * `left_chars`/`remove_chars` math for a tiny `max_chars`).
 *
 * `endWithSlash()`/`fixSeparators()` are trivial, ported as-is except
 * `endWithSlash("")` -- see `FLTK_ISSUES.md` for why FLTK's
 * own `str[str.size()-1]` is undefined behavior on an empty string,
 * faithfully NOT reproduced here (this port just returns `""`
 * unchanged for that one input instead).
 */
module fluid.path_util;

import std.conv : to;
import std.string : replace;
import std.algorithm.searching : startsWith;

import fl.filename : filenameExpand;

private string home_;
private bool homeInit_;

/// Truncates `filename` to at most `maxChars` *characters* (not
/// bytes) for display, replacing the home directory prefix with `~/`
/// first and, if still too long, collapsing the middle into `...`.
/// The result is for display only -- not usable to reopen the file.
string filenameShortened(string filename, int maxChars)
{
    if (!homeInit_)
    {
        home_ = filenameExpand("~/");
        homeInit_ = true;
    }

    string homed = (home_.length && filename.startsWith(home_))
        ? "~/" ~ filename[home_.length .. $]
        : filename;

    enum ellChars = 3;
    dstring wide = homed.to!dstring;
    int numChars = cast(int) wide.length;

    if (numChars + ellChars - 1 <= maxChars)
        return homed;

    int removeChars = numChars - maxChars + ellChars;
    int leftChars = (maxChars - ellChars) / 2;
    if (leftChars < 0) leftChars = 0;
    if (leftChars > numChars) leftChars = numChars;
    int rightStart = leftChars + removeChars;
    if (rightStart < leftChars) rightStart = leftChars;
    if (rightStart > numChars) rightStart = numChars;

    return wide[0 .. leftChars].to!string ~ "..." ~ wide[rightStart .. $].to!string;
}

/// Appends `/` unless `str` already ends with `/` or `\`. `""` is
/// returned unchanged (see this module's own doc comment on why --
/// FLTK's own equivalent is undefined behavior for this input).
string endWithSlash(string str)
{
    if (str.length == 0) return str;
    char last = str[$ - 1];
    return (last != '/' && last != '\\') ? str ~ "/" : str;
}

/// Replaces every `\` with `/`.
string fixSeparators(string fn)
{
    return fn.replace('\\', '/');
}

/// Appends `.fl` unless `path` already ends with it (case-insensitively,
/// so `Example.FL` is left alone -- on a case-insensitive filesystem that
/// *is* the same file). The check is on the whole `.fl` suffix, not on
/// "has any extension at all", so a name that merely contains a dot
/// (`design.v2`) still gets its `.fl`, while re-saving `example.fl` can
/// never grow into `example.fl.fl`. `""` is returned unchanged.
///
/// Deliberately not ported from FLTK's Fluid, whose Save As uses the
/// chooser's result verbatim (a name typed without an extension is
/// written without one).
string ensureFlExtension(string path)
{
    import std.string : toLower;

    if (path.length == 0) return path;
    if (path.length >= 3 && path[$ - 3 .. $].toLower() == ".fl") return path;
    return path ~ ".fl";
}

unittest
{
    assert(ensureFlExtension("") == "");
    assert(ensureFlExtension("example") == "example.fl");
    assert(ensureFlExtension("example.fl") == "example.fl");
    assert(ensureFlExtension("Example.FL") == "Example.FL");
    assert(ensureFlExtension("/a/b/example") == "/a/b/example.fl");
    assert(ensureFlExtension("/a/b/example.fl") == "/a/b/example.fl");
    // Never stacks, however often it is applied.
    assert(ensureFlExtension(ensureFlExtension(ensureFlExtension("example"))) == "example.fl");
    // A dot in the name is not an extension of ours.
    assert(ensureFlExtension("design.v2") == "design.v2.fl");
    assert(ensureFlExtension("notes.txt") == "notes.txt.fl");
    assert(ensureFlExtension(".fl") == ".fl");
}

unittest
{
    assert(endWithSlash("") == "");
    assert(endWithSlash("/a/b") == "/a/b/");
    assert(endWithSlash("/a/b/") == "/a/b/");
    assert(endWithSlash(`C:\a\b`) == `C:\a\b/`);

    assert(fixSeparators(`a\b\c`) == "a/b/c");
    assert(fixSeparators("a/b/c") == "a/b/c");

    // Short enough already -- returned unchanged.
    assert(filenameShortened("short.fl", 40) == "short.fl");

    // Long enough to need collapsing -- first/last characters kept,
    // middle replaced with "...".
    string longPath = "/some/very/deeply/nested/directory/structure/project.fl";
    string shortened = filenameShortened(longPath, 20);
    assert(shortened.length < longPath.length);
    import std.algorithm.searching : canFind;
    assert(shortened.canFind("..."));
    assert(shortened.startsWith(longPath[0 .. 8]));
}
