/*
 * Ported from FLTK's `fluid::app::Layout_Preset`/`Layout_Suite`/
 * `Layout_List` (`fluid/app/Snap_Action.h`/`.cxx`) -- the "Layout
 * Suite" settings this module reads for real, which
 * `fluid.instantiate.idealSizeFor()` reads instead of a plain
 * `fl.enumerations.normalSize` constant, and what `fluid.snap_action`'s own drag-time alignment
 * guides read their margin/grid/gap distances from.
 *
 * A `Layout_Preset` is a named bundle of window/group margins, grid
 * spacing, tab margins, default widget min-size/increment/gap, and
 * label/text font/size -- three presets ("application"/"dialog"/
 * "toolbox") make up one `Layout_Suite`; FLTK ships two built-in
 * suites ("FLTK" -- plain margins, no grid -- and "Grid" -- the same
 * shape but with real grid spacing set), both ported here verbatim,
 * numeric value for numeric value, from `Snap_Action.cxx`'s own
 * `fltk_app`/`fltk_dlg`/`fltk_tool`/`grid_app`/`grid_dlg`/`grid_tool`
 * static tables.
 *
 * The Settings-dialog Layout tab is fully wired. Matches FLTK's real
 * `Layout_List`/`Layout_Suite` behavior in full: `add()` inherits the
 * source suite's own storage (remapping only `internal`->`user`, not
 * always forcing `user`), `LayoutSuite`/`LayoutPreset` round-trip
 * through the `.fl` project file (`writeTo()`/`readFrom()`, consumed
 * by `fluid.project_writer`/`fluid.project_reader`'s own `snap { ... }`
 * Option block -- the `.fl`-file half of `ToolStore.project` storage),
 * `writeToPrefs()`/`readFromPrefs()` persist *every* storage-filtered
 * suite (not just the current selection) into a given `Preferences`
 * root, and `load()`/`save()` back a standalone `.fll` file the same
 * way (a `Preferences` opened directly against a file path, matching
 * FLTK's own `Fl_Preferences(filename, "layout.fluid.fltk.org",
 * nullptr, C_LOCALE)` call). One deliberate simplification, shared
 * with the Settings dialog's User tab: no `@fd_beaker`/`@fd_user`/`@fd_project`/
 * `@fd_file` `fl_add_symbol()` glyphs -- `LayoutSuite` has no separate
 * `menu_label` field at all (FLTK's own symbol-prefixed display
 * string); every caller just uses `.name` directly where FLTK
 * would read `menu_label`.
 */
module fluid.layout_suite;

import std.array : Appender;
import std.conv : to, ConvException;
import std.format : format;

import fl.preferences : Preferences;
import fluid.app_prefs : appPrefs;
import fluid.project_reader : Reader;
import fluid.shell_command : ToolStore;

/// Ported from `fluid::app::Layout_Preset` (`Snap_Action.h`). Plain
/// data plus `read()`/`write()` against `fl.preferences.Preferences`
/// -- FLTK's own field-by-field `Fl_Preferences` sub-group layout
/// (`"Window"`/`"Group"`/`"Tabs"`/`"Widget"`/`"Layout"`) is matched
/// exactly, so a preferences file written by this port and FLTK's
/// own Fluid would parse identically (not that anything reads the
/// other's file today -- this port's own vendor/application pair is
/// deliberately distinct, see `fluid.app_prefs`'s own doc comment --
/// but there's no reason to invent a different layout gratuitously).
final class LayoutPreset
{
    int leftWindowMargin, rightWindowMargin, topWindowMargin, bottomWindowMargin;
    int windowGridX, windowGridY;

    int leftGroupMargin, rightGroupMargin, topGroupMargin, bottomGroupMargin;
    int groupGridX, groupGridY;

    int topTabsMargin, bottomTabsMargin;

    int widgetMinW, widgetIncW, widgetGapX;
    int widgetMinH, widgetIncH, widgetGapY;

    int labelfont, labelsize, textfont, textsize;

    this() {}

    this(int lwm, int rwm, int twm, int bwm, int wgx, int wgy,
         int lgm, int rgm, int tgm, int bgm, int ggx, int ggy,
         int ttm, int btm,
         int wminw, int wincw, int wgapx,
         int wminh, int winch, int wgapy,
         int lf, int ls, int tf, int ts)
    {
        leftWindowMargin = lwm; rightWindowMargin = rwm;
        topWindowMargin = twm; bottomWindowMargin = bwm;
        windowGridX = wgx; windowGridY = wgy;
        leftGroupMargin = lgm; rightGroupMargin = rgm;
        topGroupMargin = tgm; bottomGroupMargin = bgm;
        groupGridX = ggx; groupGridY = ggy;
        topTabsMargin = ttm; bottomTabsMargin = btm;
        widgetMinW = wminw; widgetIncW = wincw; widgetGapX = wgapx;
        widgetMinH = wminh; widgetIncH = winch; widgetGapY = wgapy;
        labelfont = lf; labelsize = ls; textfont = tf; textsize = ts;
    }

    /// Ported from `Layout_Preset::textsize_not_null()` -- the preferred
    /// text size, falling back to `labelsize`, then a hardcoded `14`,
    /// whenever `textsize` itself is `<= 0` (this port's dialect for
    /// FLTK's own "user never set one" sentinel).
    int textsizeNotNull() const
    {
        if (textsize > 0) return textsize;
        if (labelsize > 0) return labelsize;
        return 14;
    }

    void write(Preferences prefs)
    {
        auto pWin = new Preferences(prefs, "Window");
        pWin.set("left_margin", leftWindowMargin);
        pWin.set("right_margin", rightWindowMargin);
        pWin.set("top_margin", topWindowMargin);
        pWin.set("bottom_margin", bottomWindowMargin);
        pWin.set("grid_x", windowGridX);
        pWin.set("grid_y", windowGridY);

        auto pGrp = new Preferences(prefs, "Group");
        pGrp.set("left_margin", leftGroupMargin);
        pGrp.set("right_margin", rightGroupMargin);
        pGrp.set("top_margin", topGroupMargin);
        pGrp.set("bottom_margin", bottomGroupMargin);
        pGrp.set("grid_x", groupGridX);
        pGrp.set("grid_y", groupGridY);

        auto pTbs = new Preferences(prefs, "Tabs");
        pTbs.set("top_margin", topTabsMargin);
        pTbs.set("bottom_margin", bottomTabsMargin);

        auto pWgt = new Preferences(prefs, "Widget");
        pWgt.set("min_w", widgetMinW);
        pWgt.set("inc_w", widgetIncW);
        pWgt.set("gap_x", widgetGapX);
        pWgt.set("min_h", widgetMinH);
        pWgt.set("inc_h", widgetIncH);
        pWgt.set("gap_y", widgetGapY);

        auto pLyt = new Preferences(prefs, "Layout");
        pLyt.set("labelfont", labelfont);
        pLyt.set("labelsize", labelsize);
        pLyt.set("textfont", textfont);
        pLyt.set("textsize", textsize);
    }

    void read(Preferences prefs)
    {
        auto pWin = new Preferences(prefs, "Window");
        pWin.get("left_margin", leftWindowMargin, 15);
        pWin.get("right_margin", rightWindowMargin, 15);
        pWin.get("top_margin", topWindowMargin, 15);
        pWin.get("bottom_margin", bottomWindowMargin, 15);
        pWin.get("grid_x", windowGridX, 0);
        pWin.get("grid_y", windowGridY, 0);

        auto pGrp = new Preferences(prefs, "Group");
        pGrp.get("left_margin", leftGroupMargin, 10);
        pGrp.get("right_margin", rightGroupMargin, 10);
        pGrp.get("top_margin", topGroupMargin, 10);
        pGrp.get("bottom_margin", bottomGroupMargin, 10);
        pGrp.get("grid_x", groupGridX, 0);
        pGrp.get("grid_y", groupGridY, 0);

        auto pTbs = new Preferences(prefs, "Tabs");
        pTbs.get("top_margin", topTabsMargin, 25);
        pTbs.get("bottom_margin", bottomTabsMargin, 25);

        auto pWgt = new Preferences(prefs, "Widget");
        pWgt.get("min_w", widgetMinW, 20);
        pWgt.get("inc_w", widgetIncW, 10);
        pWgt.get("gap_x", widgetGapX, 4);
        pWgt.get("min_h", widgetMinH, 20);
        pWgt.get("inc_h", widgetIncH, 4);
        pWgt.get("gap_y", widgetGapY, 8);

        auto pLyt = new Preferences(prefs, "Layout");
        pLyt.get("labelfont", labelfont, 0);
        pLyt.get("labelsize", labelsize, 14);
        pLyt.get("textfont", textfont, 0);
        pLyt.get("textsize", textsize, 14);
    }

    /// Ported from `Layout_Preset::write(Project_Writer*)`. Emits the
    /// same 23 ints, in the same order, as FLTK's own flat
    /// `"preset { 1\n  ...\n}"` block -- only the layout differs
    /// (`depth`-based GNU style, matching `project_writer.d`'s own
    /// established deviation from FLTK's raw K&R-ish spacing, e.g.
    /// `ShellCommand.writeTo()`), not the token sequence the reader below
    /// actually parses: the version tag `1` becomes the first content
    /// line of the group. `depth` is the indent level of the `preset`
    /// keyword line; the `{` sits one level deeper, the contents one
    /// level deeper still.
    void writeTo(ref Appender!string buf, int depth)
    {
        string ind1 = indentOf(depth + 1);
        string ind2 = indentOf(depth + 2);
        buf ~= indentOf(depth) ~ "preset\n";
        buf ~= ind1 ~ "{\n";
        buf ~= ind2 ~ "1\n";
        buf ~= ind2 ~ format!"%d %d %d %d %d %d\n"(leftWindowMargin, rightWindowMargin,
            topWindowMargin, bottomWindowMargin, windowGridX, windowGridY);
        buf ~= ind2 ~ format!"%d %d %d %d %d %d\n"(leftGroupMargin, rightGroupMargin,
            topGroupMargin, bottomGroupMargin, groupGridX, groupGridY);
        buf ~= ind2 ~ format!"%d %d\n"(topTabsMargin, bottomTabsMargin);
        buf ~= ind2 ~ format!"%d %d %d %d %d %d\n"(widgetMinW, widgetIncW, widgetGapX,
            widgetMinH, widgetIncH, widgetGapY);
        buf ~= ind2 ~ format!"%d %d %d %d\n"(labelfont, labelsize, textfont, textsize);
        buf ~= ind1 ~ "}\n";
    }

    /// Ported from `Layout_Preset::read(Project_Reader*)` -- called
    /// with `r` positioned right after the "preset" keyword token that
    /// introduced this block, matching `ShellCommand.readFrom(Reader)`'s
    /// own "keyword already consumed by the caller" convention. The
    /// leading integer inside the braces is a format-version tag
    /// (FLTK's own `ver`, always `1` today); an unrecognized future
    /// version's own chunk is skipped defensively, matching FLTK's
    /// `else { skip unknown chunks }` branch exactly.
    void readFrom(Reader r)
    {
        string open = r.readToken();
        if (open != "{") return;
        while (true)
        {
            string key = r.readToken();
            if (key is null) return;
            if (key == "}") break;
            int ver;
            try ver = to!int(key);
            catch (ConvException) ver = -1; // unrecognized -- fall through to the "skip" branch below
            if (ver == 0)
            {
                continue;
            }
            else if (ver == 1)
            {
                try leftWindowMargin = to!int(r.readValue()); catch (ConvException) leftWindowMargin = 0;
                try rightWindowMargin = to!int(r.readValue()); catch (ConvException) rightWindowMargin = 0;
                try topWindowMargin = to!int(r.readValue()); catch (ConvException) topWindowMargin = 0;
                try bottomWindowMargin = to!int(r.readValue()); catch (ConvException) bottomWindowMargin = 0;
                try windowGridX = to!int(r.readValue()); catch (ConvException) windowGridX = 0;
                try windowGridY = to!int(r.readValue()); catch (ConvException) windowGridY = 0;

                try leftGroupMargin = to!int(r.readValue()); catch (ConvException) leftGroupMargin = 0;
                try rightGroupMargin = to!int(r.readValue()); catch (ConvException) rightGroupMargin = 0;
                try topGroupMargin = to!int(r.readValue()); catch (ConvException) topGroupMargin = 0;
                try bottomGroupMargin = to!int(r.readValue()); catch (ConvException) bottomGroupMargin = 0;
                try groupGridX = to!int(r.readValue()); catch (ConvException) groupGridX = 0;
                try groupGridY = to!int(r.readValue()); catch (ConvException) groupGridY = 0;

                try topTabsMargin = to!int(r.readValue()); catch (ConvException) topTabsMargin = 0;
                try bottomTabsMargin = to!int(r.readValue()); catch (ConvException) bottomTabsMargin = 0;

                try widgetMinW = to!int(r.readValue()); catch (ConvException) widgetMinW = 0;
                try widgetIncW = to!int(r.readValue()); catch (ConvException) widgetIncW = 0;
                try widgetGapX = to!int(r.readValue()); catch (ConvException) widgetGapX = 0;
                try widgetMinH = to!int(r.readValue()); catch (ConvException) widgetMinH = 0;
                try widgetIncH = to!int(r.readValue()); catch (ConvException) widgetIncH = 0;
                try widgetGapY = to!int(r.readValue()); catch (ConvException) widgetGapY = 0;

                try labelfont = to!int(r.readValue()); catch (ConvException) labelfont = 0;
                try labelsize = to!int(r.readValue()); catch (ConvException) labelsize = 0;
                try textfont = to!int(r.readValue()); catch (ConvException) textfont = 0;
                try textsize = to!int(r.readValue()); catch (ConvException) textsize = 0;
            }
            else
            {
                while (true)
                {
                    string k2 = r.readToken();
                    if (k2 is null || k2 == "}") return;
                }
            }
        }
    }
}

/// GNU-style, 2-space-per-level indentation -- shared by
/// `LayoutPreset.writeTo()`/`LayoutSuite.writeTo()` below, matching
/// `ShellCommand.writeTo()`'s own local `ind()` helper in
/// `shell_command.d` (kept as a free function here since both classes
/// need it, not just one).
private string indentOf(int depth)
{
    string s;
    foreach (i; 0 .. depth) s ~= "  ";
    return s;
}

/// Ported from `fluid::app::Layout_Suite`. Three presets --
/// `presets[0]` = application, `presets[1]` = dialog, `presets[2]` =
/// toolbox, matching FLTK's own fixed `layout[3]` array order and
/// every caller's own `current_preset()` indexing convention exactly.
final class LayoutSuite
{
    string name;
    LayoutPreset[3] presets;
    ToolStore storage = ToolStore.internal;

    this(string name, LayoutPreset application, LayoutPreset dialog, LayoutPreset toolbox,
        ToolStore storage = ToolStore.internal)
    {
        this.name = name;
        presets[0] = application;
        presets[1] = dialog;
        presets[2] = toolbox;
        this.storage = storage;
    }

    void write(Preferences prefs)
    {
        prefs.set("name", name);
        foreach (i; 0 .. 3)
        {
            auto p = new Preferences(prefs, i.to2Digits());
            presets[i].write(p);
        }
    }

    void read(Preferences prefs)
    {
        foreach (i; 0 .. 3)
        {
            auto p = new Preferences(prefs, i.to2Digits());
            presets[i].read(p);
        }
    }

    /// Ported from `Layout_Suite::write(Project_Writer*)`.
    /// `depth` is the indent level of the `suite` keyword line, same
    /// convention as `LayoutPreset.writeTo()`.
    void writeTo(ref Appender!string buf, int depth)
    {
        buf ~= indentOf(depth) ~ "suite\n";
        buf ~= indentOf(depth + 1) ~ "{\n";
        buf ~= indentOf(depth + 2) ~ "name {" ~ name ~ "}\n";
        foreach (p; presets) p.writeTo(buf, depth + 2);
        buf ~= indentOf(depth + 1) ~ "}\n";
    }

    /// Ported from `Layout_Suite::read(Project_Reader*)` -- `r`
    /// positioned right after the "suite" keyword token, same
    /// "keyword already consumed by the caller" convention as
    /// `LayoutPreset.readFrom()` above.
    void readFrom(Reader r)
    {
        string open = r.readToken();
        if (open != "{") return;
        int ix = 0;
        while (true)
        {
            string key = r.readToken();
            if (key is null) return;
            if (key == "name")
                name = r.readValue();
            else if (key == "preset")
            {
                if (ix >= 3) return; // file format error, matching FLTK
                presets[ix++].readFrom(r);
            }
            else if (key == "}")
                break;
            else
                r.readValue(); // unknown key -- skip its value defensively
        }
    }
}

/// Matches FLTK's own `Fl_Preferences::Name(int)` -- a zero-padded
/// decimal group-name string (`Fl_Preferences` itself has no numeric
/// group-name convenience in this port, so every caller that needs one
/// spells it out the same way `Layout_Suite`'s own FLTK source
/// does: a plain `"%d"`-formatted sub-group name).
private string to2Digits(int i)
{
    import std.format : format;
    return format("%d", i);
}

/// Ported from `fluid::app::Layout_List` -- see this module's own top
/// comment for real
/// `add()`/`rename()`/`remove()`/storage-switching/`.fl`-project/
/// `.fll`-file round-tripping.
final class LayoutList
{
    private LayoutSuite[] list_;
    private int currentSuite_;
    private int currentPreset_;

    /// Matches FLTK's own `std::string filename_` -- the last
    /// path used by the Settings dialog's Layout-tab "Load.../Save..."
    /// menu items (`w_layout_menu_load`/`w_layout_menu_save`), reused
    /// as next time's suggested filename.
    string filename;

    this()
    {
        list_ = [fltkSuite(), gridSuite()];
    }

    /// The presently-active preset -- what `idealSizeFor()`/`fluid.
    /// snap_action` both read from. Matches FLTK's own `Fluid.proj.
    /// layout` global (assigned in `Layout_List::update_dialogs()`)
    /// as a live accessor instead, since this port has no separate
    /// "current project" struct field to mirror it into.
    LayoutPreset current()
    {
        return list_[currentSuite_].presets[currentPreset_];
    }

    int currentSuiteIndex() const { return currentSuite_; }
    int currentPresetIndex() const { return currentPreset_; }
    int size() const { return cast(int) list_.length; }
    LayoutSuite opIndex(int i) { return list_[i]; }

    void currentSuite(int ix)
    {
        if (ix < 0 || ix >= list_.length) return;
        currentSuite_ = ix;
    }

    /// Matches FLTK's own `current_suite(std::string)` overload --
    /// selects by name (used when restoring a saved preference, which
    /// stores the suite's *name*, not its index, so a future suite-list
    /// reordering doesn't silently select the wrong one).
    void currentSuite(string name)
    {
        foreach (i, s; list_)
            if (s.name == name) { currentSuite_ = cast(int) i; return; }
    }

    void currentPreset(int ix)
    {
        if (ix < 0 || ix >= 3) return;
        currentPreset_ = ix;
    }

    /// Ported from `Layout_List::add()` -- appends a new suite cloned
    /// from the *current* suite's own preset values (matching
    /// FLTK's own "start from what you have" convention for a
    /// user-created suite). Storage is inherited from the source
    /// suite, remapping only `internal`->`user` (FLTK's own
    /// `new_storage = old_suite.storage_; if (internal) new_storage =
    /// USER;`) -- cloning an already-`user`/`project`/`file` suite
    /// keeps that same storage, it does *not* always reset to `user`.
    /// Also reused, exactly like FLTK reuses it, as the "make a
    /// blank slot, then overwrite every field via `read()`/`readFrom()`"
    /// mechanism for `readFromPrefs()`/project-file loading below --
    /// the cloned starting values are irrelevant there since the very
    /// next call replaces them all.
    int add(string name)
    {
        auto cur = list_[currentSuite_];
        auto newStorage = cur.storage == ToolStore.internal ? ToolStore.user : cur.storage;
        auto suite = new LayoutSuite(name,
            clonePreset(cur.presets[0]),
            clonePreset(cur.presets[1]),
            clonePreset(cur.presets[2]),
            newStorage);
        list_ ~= suite;
        currentSuite_ = cast(int) list_.length - 1;
        return currentSuite_;
    }

    /// Appends an already-fully-built `LayoutSuite` -- used by
    /// `gui_main.d`'s project-load path, which parses complete suites
    /// via `fluid.project_reader.Reader.readSnap()` (each one already
    /// carrying real data, tagged `ToolStore.project`) before deciding
    /// whether to apply them at all. Unlike the `add(string)` overload
    /// above, this doesn't clone from the current suite (the caller
    /// already has real data) and doesn't change the current selection
    /// (matching FLTK's own `Layout_List::read(Project_Reader*)`,
    /// which only applies `current_suite`/`current_preset` once, after
    /// every `suite { ... }` block in the file has been added).
    int add(LayoutSuite suite)
    {
        list_ ~= suite;
        return cast(int) list_.length - 1;
    }

    void rename(string name)
    {
        list_[currentSuite_].name = name;
    }

    /// Ported from `Layout_List::remove()` -- the two built-in suites
    /// (index 0/1, both `ToolStore.internal`) can never be removed,
    /// matching FLTK's own guard.
    void remove(int ix)
    {
        import std.algorithm : remove;
        if (ix < 0 || ix >= list_.length) return;
        if (list_[ix].storage == ToolStore.internal) return;
        list_ = list_.remove(ix);
        if (currentSuite_ >= list_.length) currentSuite_ = cast(int) list_.length - 1;
    }

    /// Ported from `Layout_List::remove_all(Tool_Store)` -- drops every
    /// suite tagged with the given storage, keeping the rest. Used
    /// before reloading a fresh batch of same-storage suites (matching
    /// `ShellCommandList.clear(ToolStore)`'s own identical pre-reload
    /// role): `load()` calls this for `ToolStore.file` before reading a
    /// `.fll` file, and project loading calls it for `ToolStore.project`
    /// before reading a `.fl` file's own `snap { ... }` block.
    void removeAll(ToolStore storage)
    {
        foreach_reverse (i; 0 .. list_.length)
            if (list_[i].storage == storage) remove(cast(int) i);
    }

    /// Ported from `Layout_List::write(Fl_Preferences&, Tool_Store)` --
    /// writes the current selection (by name, so a later reordering of
    /// `list_` doesn't silently select the wrong suite back) plus every
    /// suite tagged with `storage`, into the `"Layouts"` sub-group of
    /// `prefs`. Used both for `ToolStore.user` against `fluid.app_prefs
    /// .appPrefs` and for `ToolStore.file` against a standalone `.fll`
    /// file's own root (see `save()` below) -- exactly FLTK's own
    /// dual use of one storage-parameterized method. Ends with an
    /// explicit `.flush()` -- `set()` alone only marks the in-memory
    /// tree dirty (unlike FLTK's deterministic C++ destructor-driven
    /// write), the exact bug `fluid.node_browser.savePrefs()`'s/
    /// `gui_main.saveWindowPosition()`'s own doc comments already
    /// documented hitting for the same reason; `Preferences.flush()`
    /// always walks up to the true root regardless of which sub-group
    /// instance it's called on, so calling it here (rather than
    /// separately in every caller) covers both use sites in one place.
    void writeToPrefs(Preferences prefs, ToolStore storage)
    {
        auto p = new Preferences(prefs, "Layouts");
        p.clear();
        p.set("current_suite", list_[currentSuite_].name);
        p.set("current_preset", currentPreset_);
        int n;
        foreach (s; list_)
        {
            if (s.storage != storage) continue;
            auto sp = new Preferences(p, n.to2Digits());
            s.write(sp);
            n++;
        }
        p.flush();
    }

    /// Ported from `Layout_List::read(Fl_Preferences&, Tool_Store)`.
    /// Every stored suite becomes a real, `add()`-appended `LayoutSuite`
    /// tagged with `storage` (matching FLTK's own `add()`-then-
    /// `read()`-then-`storage()` sequence); the selection is restored
    /// last, by name, so it's resolved against the now-complete list.
    void readFromPrefs(Preferences prefs, ToolStore storage)
    {
        auto p = new Preferences(prefs, "Layouts");
        string cs;
        p.get("current_suite", cs, "");
        int cp;
        p.get("current_preset", cp, 0);
        foreach (i; 0 .. p.groups())
        {
            auto sp = new Preferences(p, i.to2Digits());
            string name;
            sp.get("name", name, "");
            if (!name.length) continue;
            int n = add(name);
            list_[n].read(sp);
            list_[n].storage = storage;
        }
        if (cs.length) currentSuite(cs);
        currentPreset(cp);
    }

    /// Ported from `Layout_List::load()` -- opens `filename` directly
    /// as its own standalone `Preferences` root (matching FLTK's
    /// own `Fl_Preferences(filename.c_str(), "layout.fluid.fltk.org",
    /// nullptr, C_LOCALE)` -- an empty `application` name means "treat
    /// `path` as the literal file", see `fl.preferences.Preferences`'s
    /// own doc comment on that constructor), replacing every existing
    /// `ToolStore.file` suite with whatever that file contains.
    void load(string filename_)
    {
        import fl.preferences : rootCLocale;

        filename = filename_;
        removeAll(ToolStore.file);
        auto prefs = new Preferences(filename, "layout.fluid.fltk.org", "", rootCLocale);
        readFromPrefs(prefs, ToolStore.file);
    }

    /// Ported from `Layout_List::save()`.
    void save(string filename_)
    {
        import fl.preferences : Root, rootCLocale, rootClear;

        filename = filename_;
        auto prefs = new Preferences(filename, "layout.fluid.fltk.org", "",
            cast(Root)(rootCLocale | rootClear));
        writeToPrefs(prefs, ToolStore.file); // flushes internally, see its own doc comment
    }

    /// Ported from `Layout_List::write(Project_Writer*)`. FLTK
    /// skips emitting the whole `snap { ... }` block for the common
    /// case (default suite/preset selected, no `ToolStore.project`
    /// suites at all) so an otherwise-untouched `.fl` file doesn't grow
    /// a block it doesn't need -- matched exactly here.
    void writeToProject(ref Appender!string buf)
    {
        if (currentSuite_ == 0 && currentPreset_ == 0)
        {
            bool any;
            foreach (s; list_)
                if (s.storage == ToolStore.project) { any = true; break; }
            if (!any) return;
        }
        buf ~= "\nsnap\n  {\n    ver 1\n";
        buf ~= "    current_suite {" ~ list_[currentSuite_].name ~ "}\n";
        buf ~= format!"    current_preset %d\n"(currentPreset_);
        foreach (s; list_)
            if (s.storage == ToolStore.project) s.writeTo(buf, 2);
        buf ~= "  }\n";
    }
}

private LayoutPreset clonePreset(LayoutPreset p)
{
    return new LayoutPreset(
        p.leftWindowMargin, p.rightWindowMargin, p.topWindowMargin, p.bottomWindowMargin,
        p.windowGridX, p.windowGridY,
        p.leftGroupMargin, p.rightGroupMargin, p.topGroupMargin, p.bottomGroupMargin,
        p.groupGridX, p.groupGridY,
        p.topTabsMargin, p.bottomTabsMargin,
        p.widgetMinW, p.widgetIncW, p.widgetGapX,
        p.widgetMinH, p.widgetIncH, p.widgetGapY,
        p.labelfont, p.labelsize, p.textfont, p.textsize);
}

// ---- The two built-in suites, ported verbatim from Snap_Action.cxx's
// own fltk_app/fltk_dlg/fltk_tool/grid_app/grid_dlg/grid_tool static
// tables (numeric value for numeric value). ----

private LayoutSuite fltkSuite()
{
    auto app = new LayoutPreset(
        15, 15, 15, 15, 0, 0,
        10, 10, 10, 10, 0, 0,
        25, 25,
        20, 10, 4,
        20, 4, 8,
        0, 14, -1, 14);
    auto dlg = new LayoutPreset(
        10, 10, 10, 10, 0, 0,
        10, 10, 10, 10, 0, 0,
        20, 20,
        20, 10, 5,
        20, 5, 5,
        0, 11, -1, 11);
    auto tool = new LayoutPreset(
        10, 10, 10, 10, 0, 0,
        10, 10, 10, 10, 0, 0,
        18, 18,
        16, 8, 2,
        16, 4, 2,
        0, 10, -1, 10);
    return new LayoutSuite("FLTK", app, dlg, tool, ToolStore.internal);
}

private LayoutSuite gridSuite()
{
    auto app = new LayoutPreset(
        12, 12, 12, 12, 12, 12,
        12, 12, 12, 12, 12, 12,
        24, 24,
        12, 6, 6,
        12, 6, 6,
        0, 14, -1, 14);
    auto dlg = new LayoutPreset(
        10, 10, 10, 10, 10, 10,
        10, 10, 10, 10, 10, 10,
        20, 20,
        10, 5, 5,
        10, 5, 5,
        0, 12, -1, 12);
    auto tool = new LayoutPreset(
        8, 8, 8, 8, 8, 8,
        8, 8, 8, 8, 8, 8,
        16, 16,
        8, 4, 4,
        8, 4, 4,
        0, 10, -1, 10);
    return new LayoutSuite("Grid", app, dlg, tool, ToolStore.internal);
}

/// The process-wide instance -- matches FLTK's own single `Fluid.
/// layout_list` (an `Application`-owned member, functionally a
/// singleton in a single-project-at-a-time editor exactly like this
/// port's own `fluid.app_prefs.appPrefs`).
///
/// Lazily constructed on first access rather than via `static this()`
/// -- mirrors `fl.symbols`' own `ensureDefaultSymbols()` fix for the
/// identical failure mode (see that module's doc comment for the full
/// writeup). `LayoutPreset`/`LayoutSuite`'s
/// project-file parsing (`readFrom(Reader)`) makes `fluid.layout_suite` import `fluid.
/// project_reader`, which itself already imports `fluid.factory`/
/// `fluid.class_node` in a pre-existing cycle back to `project_reader`
/// -- adding `layout_suite` into that same cycle while it still had a
/// real `static this()` made druntime's `sortCtors()` refuse to start
/// the program at all (`Cyclic dependency between module constructors/
/// destructors of fluid.layout_suite and fluid.factory`). Kept as a
/// property-style function rather than renaming this module's many
/// existing `layoutList.xxx` call sites across `fluid.snap_action`/
/// `fluid.instantiate`/`gui_main.d`/`settings_panel.fl`: D resolves a
/// parenthesis-less call to a niladic function transparently, so
/// `layoutList.currentSuite(...)` keeps compiling unchanged everywhere
/// it already appears.
private LayoutList layoutList_;

@property LayoutList layoutList()
{
    if (layoutList_ is null) layoutList_ = new LayoutList();
    return layoutList_;
}

unittest
{
    auto list = new LayoutList();
    assert(list.size() == 2);
    assert(list.current().leftWindowMargin == 15); // FLTK/application default

    list.currentSuite(1); // Grid
    list.currentPreset(1); // dialog
    assert(list.current().leftWindowMargin == 10);
    assert(list.current().windowGridX == 10); // Grid suite actually sets a grid

    list.currentSuite("FLTK");
    assert(list.currentSuiteIndex() == 0);

    // add()/rename()/remove(): backing the Settings dialog's Layout
    // tab "+"/rename/delete controls.
    auto ix = list.add("My Suite");
    assert(list.size() == 3);
    assert(list[ix].storage == ToolStore.user); // cloned from FLTK (internal) -> user
    list.currentSuite(ix);
    list.rename("Renamed Suite");
    assert(list[ix].name == "Renamed Suite");
    list.remove(ix);
    assert(list.size() == 2);

    // The built-in suites can never be removed.
    list.remove(0);
    assert(list.size() == 2);
}

unittest
{
    // add()'s storage-inheritance fix: cloning a non-internal suite
    // keeps that same storage, it does not always reset to `user`.
    auto list = new LayoutList();
    auto ix = list.add("Project Suite");
    list[ix].storage = ToolStore.project;
    list.currentSuite(ix);
    auto ix2 = list.add("Clone of Project Suite");
    assert(list[ix2].storage == ToolStore.project);
}

unittest
{
    // writeToPrefs()/readFromPrefs(): a real round trip through an
    // in-memory Preferences tree, storage-filtered. `new Preferences(
    // null, group)` is this project's own established in-RAM-only test
    // idiom (falls back to the shared `runtimePrefs()` root), matching
    // `fl.preferences`'s own unittest precedent -- not a standalone
    // on-disk database the way `load()`/`save()` use below.
    auto list = new LayoutList();
    list.currentSuite(1); // Grid
    list.currentPreset(2); // toolbox
    auto ix = list.add("Custom");
    list[ix].storage = ToolStore.user;
    list[ix].presets[0].leftWindowMargin = 99;

    auto prefs = new Preferences(null, "layout_suite_test");
    list.writeToPrefs(prefs, ToolStore.user);

    auto reloaded = new LayoutList();
    reloaded.readFromPrefs(prefs, ToolStore.user);
    assert(reloaded.size() == 3); // FLTK, Grid, + the one restored `user` suite
    assert(reloaded.currentSuiteIndex() == reloaded.size() - 1); // "Custom", restored by name
    assert(reloaded.currentPresetIndex() == 2);
    assert(reloaded[reloaded.size() - 1].name == "Custom");
    assert(reloaded[reloaded.size() - 1].presets[0].leftWindowMargin == 99);
}

unittest
{
    import std.array : appender;

    // writeToProject()/the project-file "snap { ... }" format: no
    // block at all for the default selection with no project suites.
    auto buf = appender!string();
    auto list = new LayoutList();
    list.writeToProject(buf);
    assert(buf.data.length == 0);
}

unittest
{
    import std.algorithm.searching : canFind;
    import std.array : appender;
    import fluid.project_reader : Reader;

    auto list = new LayoutList();
    auto ix = list.add("Proj Suite");
    list[ix].storage = ToolStore.project;
    list[ix].presets[1].labelfont = 3;
    list.currentSuite(ix);
    list.currentPreset(1);

    auto buf = appender!string();
    list.writeToProject(buf);
    assert(buf.data.canFind("snap\n  {\n"));
    assert(buf.data.canFind("Proj Suite"));

    // Re-parse it the same way `project_reader.d`'s own Options loop
    // would (skipWsAndComments() eats the leading blank line; the
    // "snap" keyword itself is consumed here since that's the caller's
    // job in the real loop, not `readFrom()`'s).
    auto r = new Reader(buf.data);
    string tok = r.readToken();
    assert(tok == "snap");
    string open = r.readToken();
    assert(open == "{");
    string verKey = r.readToken();
    assert(verKey == "ver");
    r.readValue();
    string csKey = r.readToken();
    assert(csKey == "current_suite");
    string cs = r.readValue();
    assert(cs == "Proj Suite");
    string cpKey = r.readToken();
    assert(cpKey == "current_preset");
    int cp = to!int(r.readValue());
    assert(cp == 1);
    string suiteKey = r.readToken();
    assert(suiteKey == "suite");
    auto restored = new LayoutSuite("", new LayoutPreset(), new LayoutPreset(), new LayoutPreset());
    restored.readFrom(r);
    assert(restored.name == "Proj Suite");
    assert(restored.presets[1].labelfont == 3);
}

unittest
{
    // load()/save(): a real `.fll` file round trip, matching FLTK's
    // own `Fl_Preferences(filename, "layout.fluid.fltk.org", nullptr,
    // C_LOCALE)` (an empty `application` name = "treat `path` as the
    // literal file").
    import std.file : tempDir, remove, exists;
    import std.path : buildPath;
    import std.uuid : randomUUID;

    string path = buildPath(tempDir(), "fldtk-layout-suite-test-" ~ randomUUID().toString() ~ ".fll");
    scope(exit) if (exists(path)) remove(path);

    auto list = new LayoutList();
    auto ix = list.add("Exported");
    list[ix].storage = ToolStore.file;
    list[ix].presets[2].widgetGapY = 42;
    list.currentSuite(ix);
    list.currentPreset(2);
    list.save(path);
    assert(list.filename == path);

    auto reloaded = new LayoutList();
    reloaded.load(path);
    assert(reloaded.filename == path);
    assert(reloaded.size() == 3);
    auto restored = reloaded[reloaded.size() - 1];
    assert(restored.name == "Exported");
    assert(restored.storage == ToolStore.file);
    assert(restored.presets[2].widgetGapY == 42);
    assert(reloaded.currentSuiteIndex() == reloaded.size() - 1);
    assert(reloaded.currentPresetIndex() == 2);
}

unittest
{
    // GNU-style layout of the `snap` block, byte-exact (the same
    // contract `project_writer.d`'s own layout test pins for nodes):
    // keyword line, `{` one level deeper, contents one level deeper
    // still, `}` aligned with its `{`; a preset's version tag `1` is the
    // first content line. Also re-reads it to confirm the reader still
    // accepts exactly what the writer emits.
    import std.array : appender;
    import fluid.project_reader : Reader;

    auto list = new LayoutList();
    auto ix = list.add("Proj");
    list[ix].storage = ToolStore.project;
    list.currentSuite(ix);
    list.currentPreset(1);

    auto buf = appender!string();
    list.writeToProject(buf);
    string text = buf.data;

    string preset(int d, int n)
    {
        auto p = list[ix].presets[n];
        string in1 = indentOf(d + 1), in2 = indentOf(d + 2);
        return indentOf(d) ~ "preset\n" ~ in1 ~ "{\n" ~ in2 ~ "1\n"
            ~ in2 ~ format!"%d %d %d %d %d %d\n"(p.leftWindowMargin, p.rightWindowMargin,
                p.topWindowMargin, p.bottomWindowMargin, p.windowGridX, p.windowGridY)
            ~ in2 ~ format!"%d %d %d %d %d %d\n"(p.leftGroupMargin, p.rightGroupMargin,
                p.topGroupMargin, p.bottomGroupMargin, p.groupGridX, p.groupGridY)
            ~ in2 ~ format!"%d %d\n"(p.topTabsMargin, p.bottomTabsMargin)
            ~ in2 ~ format!"%d %d %d %d %d %d\n"(p.widgetMinW, p.widgetIncW, p.widgetGapX,
                p.widgetMinH, p.widgetIncH, p.widgetGapY)
            ~ in2 ~ format!"%d %d %d %d\n"(p.labelfont, p.labelsize, p.textfont, p.textsize)
            ~ in1 ~ "}\n";
    }
    string expected = "\nsnap\n  {\n    ver 1\n    current_suite {Proj}\n    current_preset 1\n"
        ~ "    suite\n      {\n        name {Proj}\n"
        ~ preset(4, 0) ~ preset(4, 1) ~ preset(4, 2)
        ~ "      }\n  }\n";
    assert(text == expected, text);

    auto r = new Reader(text);
    assert(r.readToken() == "snap");
    assert(r.readToken() == "{");
    assert(r.readToken() == "ver");
    r.readValue();
    assert(r.readToken() == "current_suite");
    assert(r.readValue() == "Proj");
}
