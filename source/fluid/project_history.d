/**
 * Recent-projects list, persisted via `fl.preferences` -- ported from
 * FLTK's `fluid/app/history.h`/`.cxx` (`fluid::app::History`).
 *
 * Reuses three pieces of infrastructure ported earlier the same day:
 * `fluid.path_util.filenameShortened()`/`.fixSeparators()` (the
 * `fluid/tools/filename` port) for the menu-display path, and
 * `fl.filename.filenameAbsolute()`/`.filenamePath()` (already real)
 * for path normalization.
 *
 * **Simplified from FLTK's own storage shape**: FLTK's
 * `abspath[10][FL_PATH_MAX]`/`relpath[10][FL_PATH_MAX]` are fixed
 * `char` buffers (C++ has no growable, GC-owned string array handy at
 * this layer without extra machinery) -- this port just uses
 * `string[maxEntries]` (a real D array of GC strings), no fixed byte
 * cap needed.
 *
 * **Takes its `Preferences` instance as a parameter rather than
 * reaching for a module-global** (unlike this port's other panels,
 * which all use `fluid.app_prefs.appPrefs` directly) -- a deliberate,
 * small deviation from that established pattern, specifically so this
 * class stays headless-unit-testable against a throwaway `Preferences`
 * instance instead of the real app's own on-disk prefs file. Every
 * real call site still just passes `appPrefs`, matching every other
 * panel's own usage.
 *
 * **No pre-allocated `Fl_Menu_Item[10]` array** (FLTK's own
 * `Fluid.history_item[10]`, hidden/relabeled in place to avoid
 * restructuring the live menu): this port's own `fl.menu_.Menu_`
 * supports real `remove()`/`add()` at a path, so `gui_main.d`'s own
 * menu-rebuilding approach (`rebuildRecentFilesMenu()`) just removes
 * and re-adds the whole "Recent Files" submenu each time the list
 * changes -- simpler, though it means a freshly rebuilt submenu is
 * re-appended positionally rather than updated in place; see that
 * function's own doc comment.
 */
module fluid.project_history;

import std.format : format;

import fl.preferences : Preferences;
import fl.filename : filenameAbsolute, filenamePath;
import fluid.path_util : filenameShortened, fixSeparators;

enum maxEntries = 10;
private enum defaultMaxFiles = 5;

class History
{
    /// Absolute paths of the most recently used project files, most
    /// recent first. Empty string for unused trailing slots.
    string[maxEntries] abspath;

    /// Shortened (`filenameShortened(..., 48)`) versions of `abspath`,
    /// suitable for menu display.
    string[maxEntries] relpath;

    private string latestProjectPath_;

    /// The directory containing the most recently used project file
    /// (independent of `maxFiles` -- updated on every `update()` call,
    /// not just ones that actually change the top-of-list entry).
    string latestProjectPath() const { return latestProjectPath_; }

    /// Loads the history from `prefs` (`"recent_files"` for how many
    /// entries to track, capped at `maxEntries`, then `"file0"`..
    /// `"fileN"`).
    void load(Preferences prefs)
    {
        int maxFiles;
        prefs.get("recent_files", maxFiles, defaultMaxFiles);
        if (maxFiles > maxEntries) maxFiles = maxEntries;

        int i;
        for (i = 0; i < maxFiles; i++)
        {
            string val;
            prefs.get(format("file%d", i), val, "");
            if (val.length == 0) break;
            abspath[i] = val;
            relpath[i] = filenameShortened(val, 48);
        }
        for (; i < maxEntries; i++)
        {
            abspath[i] = "";
            relpath[i] = "";
        }

        prefs.get("latest_project_path", latestProjectPath_, "");
    }

    /// Moves `projectFile` (converted to an absolute path) to the
    /// front of the list, shifting the others down, and persists the
    /// result to `prefs`. A no-op re-persist if it's already at the
    /// front. Always updates/persists `latestProjectPath()`, even when
    /// the top-of-list entry doesn't change.
    void update(Preferences prefs, string projectFile)
    {
        int maxFiles;
        prefs.get("recent_files", maxFiles, defaultMaxFiles);
        if (maxFiles > maxEntries) maxFiles = maxEntries;

        string absolute = fixSeparators(filenameAbsolute(projectFile));

        int i;
        for (i = 0; i < maxFiles; i++)
            if (absolute == abspath[i]) break;

        string path = filenamePath(absolute);
        if (path != latestProjectPath_)
        {
            latestProjectPath_ = path;
            prefs.set("latest_project_path", latestProjectPath_);
        }

        if (i == 0) return; // already at the front

        if (i >= maxFiles) i = maxFiles - 1;

        for (int j = i; j > 0; j--)
        {
            abspath[j] = abspath[j - 1];
            relpath[j] = relpath[j - 1];
        }

        abspath[0] = absolute;
        relpath[0] = filenameShortened(absolute, 48);

        int k;
        for (k = 0; k < maxFiles; k++)
        {
            prefs.set(format("file%d", k), abspath[k]);
            if (abspath[k].length == 0) break;
        }
        for (; k < maxEntries; k++)
            prefs.set(format("file%d", k), "");

        prefs.flush();
    }
}

unittest
{
    import std.file : tempDir, rmdirRecurse, exists, mkdirRecurse;
    import std.path : buildPath;
    import std.uuid : randomUUID;
    import fl.preferences : rootCLocale;

    auto dir = buildPath(tempDir(), "fldtk-history-test-" ~ randomUUID().toString());
    mkdirRecurse(dir);
    scope (exit) if (exists(dir)) rmdirRecurse(dir);

    auto prefs = new Preferences(dir, "fldtk.test", "history", rootCLocale);

    auto h = new History();
    h.load(prefs); // nothing saved yet -- every slot stays empty
    assert(h.abspath[0] == "");

    h.update(prefs, "project_a.fl");
    assert(h.abspath[0] == filenameAbsolute("project_a.fl"));
    assert(h.relpath[0].length > 0);

    h.update(prefs, "project_b.fl");
    assert(h.abspath[0] == filenameAbsolute("project_b.fl"));
    assert(h.abspath[1] == filenameAbsolute("project_a.fl"));

    // Re-opening an already-listed file moves it back to the front
    // without duplicating it.
    h.update(prefs, "project_a.fl");
    assert(h.abspath[0] == filenameAbsolute("project_a.fl"));
    assert(h.abspath[1] == filenameAbsolute("project_b.fl"));
    assert(h.abspath[2] == "");

    assert(h.latestProjectPath() == filenamePath(filenameAbsolute("project_a.fl")));

    // A fresh History loaded from the same prefs sees the persisted list.
    auto h2 = new History();
    h2.load(prefs);
    assert(h2.abspath[0] == h.abspath[0]);
    assert(h2.abspath[1] == h.abspath[1]);
    assert(h2.latestProjectPath() == h.latestProjectPath());
}
