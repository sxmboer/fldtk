/*
 * Ported from FL/Fl_Scheme.H + src/Fl_Scheme.cxx (FLTK 1.5.0): a
 * registry of known scheme names, used by fl.scheme_choice's
 * SchemeChoice to populate its dropdown. FLTK's own doc comment
 * calls this class "intentionally not fully documented... subject to
 * change... do not rely on details of this class" -- ported minimally,
 * matching that scope, as free functions rather than a class with only
 * static members (same "D modules already behave like namespaces"
 * reasoning CLAUDE.md documents for fl.core/Fl namespace mapping).
 *
 * The registry is a plain, growable D `string[]` rather than FLTK's
 * manually malloc/realloc'd `const char**` -- the D container already
 * handles growth, no reason to hand-roll it.
 *
 * NOT ported here: `Fl_Scheme::plastic_color_average(int)`. Despite
 * being declared on `Fl_Scheme`, FLTK itself actually *defines* it
 * in src/fl_plastic.cxx, not Fl_Scheme.cxx -- it's really
 * plastic-scheme-specific static state (a color-averaging tuning
 * parameter for that scheme's gradients) smuggled onto this class's
 * namespace for lack of a real per-scheme-class home. Port it
 * alongside plastic's own boxtype family (core-roadmap item 11
 * Phase B), not here.
 */
module fl.scheme;

import std.string : indexOf;

private string[] names_;

private void ensureInit()
{
    if (names_ !is null) return;
    addSchemeName("base");
    addSchemeName("plastic");
    addSchemeName("gtk+");
    addSchemeName("gleam");
    addSchemeName("oxy");
}

/**
 * Returns the list of all known scheme names, in registration order
 * (built-ins first: "base"/"plastic"/"gtk+"/"gleam"/"oxy", then any
 * `addSchemeName()`-registered names after). Ported from
 * `Fl_Scheme::names()` -- FLTK returns a nul-terminated `const
 * char**`; this returns a plain D `string[]` instead, so there's no
 * terminator element to skip.
 */
string[] names()
{
    ensureInit();
    return names_;
}

/// Returns the number of currently registered schemes. Ported from
/// `Fl_Scheme::num_schemes()`.
int numSchemes()
{
    ensureInit();
    return cast(int) names_.length;
}

/**
 * Registers a new scheme name. Ported from `Fl_Scheme::add_scheme_name()`:
 * validates name (lowercase `a`-`z`, digits `0`-`9`, or any of `$+_.`
 * only; at most 12 bytes), rejects an already-registered name, and
 * appends otherwise.
 *
 * Returns the new `numSchemes()` (== the new name's index + 1) on
 * success, `0` if name is already registered, `-1` for an invalid
 * character, `-2` if name is too long.
 */
int addSchemeName(string name)
{
    if (name.length > 12) return -2;
    foreach (c; name)
    {
        bool ok = (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')
            || "$+_.".indexOf(c) >= 0;
        if (!ok) return -1;
    }

    foreach (existing; names_)
        if (existing == name) return 0;

    names_ ~= name;
    return cast(int) names_.length;
}

package(fl) void resetForTest()
{
    names_ = null;
}

unittest
{
    resetForTest();

    auto n = names();
    assert(n == ["base", "plastic", "gtk+", "gleam", "oxy"]);
    assert(numSchemes() == 5);

    // Duplicate of a built-in -> rejected (0), registry unchanged.
    assert(addSchemeName("gtk+") == 0);
    assert(numSchemes() == 5);

    // Valid new name -> appended, returns the new count.
    assert(addSchemeName("my.scheme_1") == 6);
    assert(names()[5] == "my.scheme_1");

    // Invalid character (uppercase) -> rejected (-1), registry unchanged.
    assert(addSchemeName("Bad") == -1);
    assert(numSchemes() == 6);

    // Too long (> 12 bytes) -> rejected (-2).
    assert(addSchemeName("way-too-long-a-name") == -2);
    assert(numSchemes() == 6);

    resetForTest();
    assert(numSchemes() == 5);
}
