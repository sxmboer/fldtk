/*
 * Ported from real Fluid's "Predefined" comment-template menu
 * (`fluid/panels/widget_panel.fl`'s `comment_predefined_2` callback,
 * ~90 lines of C++): a small, persistent, `Fl_Preferences`-backed
 * library of reusable comment texts, shared across projects. Two
 * separate preference databases, matching FLTK's own split
 * exactly: "fluid_comments_menu" holds the ordered index of saved
 * names (so the menu can be rebuilt on demand), "fluid_comments"
 * holds the actual text keyed by name. Vendor is "fldtk", not
 * FLTK's "fltk.org" -- same deliberate divergence
 * `fluid.app_prefs` documents, so this never collides with a real
 * installed FLTK Fluid's own comment library on the same machine.
 *
 * Not ported: FLTK's one-time `load_comments_preset()` migration
 * that seeds a few built-in defaults when upgrading a pre-1.4.0 prefs
 * file -- there is no legacy fldtk prefs format to migrate from, so a
 * fresh install just starts with an empty list.
 *
 * Also not ported: the leading-underscore ("_Edit/...") divider-line
 * convention FLTK's own menu-path parser recognizes -- not a
 * mechanism this port's `fl.menu_` has at all (a separate, general
 * gap, not specific to this feature). The fixed "Edit" submenu is
 * built the same way either way; only the cosmetic divider line after
 * it is skipped.
 */
module fluid.comment_presets;

import fl;
import std.conv : to;
import std.format : format;

private Preferences menuPrefs() { return new Preferences(rootUserL, "fldtk", "fluid_comments_menu"); }
private Preferences textPrefs() { return new Preferences(rootUserL, "fldtk", "fluid_comments"); }

private string lastSelectedPath_;
private int lastSelectedIndex_;

/// Rebuilds `btn`'s dropdown from the saved-comment database: a fixed
/// "Edit/Add current comment.../Edit/Remove last selection..." pair
/// (always items 1/2 in the flat array -- item 0 is the "Edit"
/// submenu title, item 3 its terminator) followed by every saved
/// template name, in stored order. Call this once whenever a Comment
/// node is loaded into the property panel, matching FLTK's own
/// LOAD-time rebuild.
void reloadPredefinedMenu(MenuButton btn)
{
    btn.clear();
    btn.add("Edit/Add current comment...", 0, null);
    btn.add("Edit/Remove last selection...", 0, null);

    auto menu = menuPrefs();
    int n;
    menu.get("n", n, 0);

    string text;
    menu.get(to!string(0), text, "");
    foreach (i; 0 .. n)
    {
        string next;
        menu.get(to!string(i + 1), next, "");
        auto sz = text.length;
        bool isSubmenuPrefix = sz > 0 && next.length > sz && next[0 .. sz] == text && next[sz] == '/';
        if (!isSubmenuPrefix)
            btn.add(text, 0, null);
        text = next;
    }

    lastSelectedPath_ = null;
    lastSelectedIndex_ = 0;
}

private void addCurrentComment(MenuButton btn, string currentText)
{
    string xname = fl_input(
        "Please enter a name to reference the current\n"
        ~ "comment in your database.\n\n"
        ~ "Use forward slashes '/' to create submenus.",
        "My Comment");
    if (xname is null) return;

    auto nameChars = xname.dup;
    foreach (ref c; nameChars) if (c == ':') c = ';';
    string name = cast(string) nameChars;

    textPrefs().set(name, currentText);

    auto menu = menuPrefs();
    int n;
    menu.get("n", n, 0);
    menu.set(to!string(n), name);
    menu.set("n", n + 1);

    btn.add(name, 0, null);
}

private void removeLastSelection(MenuButton btn)
{
    if (lastSelectedPath_.length == 0 || lastSelectedIndex_ == 0)
    {
        message("Please select an entry from this menu first.");
        return;
    }
    if (choice(format("Are you sure that you want to delete the entry\n\"%s\"\nfrom the database?",
                       lastSelectedPath_), "Cancel", "Delete", null) != 1)
        return;

    textPrefs().deleteEntry(lastSelectedPath_);

    int idx = lastSelectedIndex_;
    btn.remove(idx);

    auto items = btn.menu();
    if (idx > 0 && items[idx - 1].submenu() && items[idx].label() is null)
        btn.remove(idx - 1);

    auto menu = menuPrefs();
    int n = 0;
    items = btn.menu();
    for (int i = 4; i < btn.size(); i++)
    {
        auto mi = &items[i];
        if (mi.submenu()) continue;
        string path = btn.itemPathname(mi);
        if (path.length) menu.set(to!string(n++), path);
    }
    for (int i = n; i < btn.size() + 4; i++)
        menu.deleteEntry(to!string(i));
    menu.set("n", n);

    lastSelectedPath_ = null;
    lastSelectedIndex_ = 0;
}

private string selectPredefinedText(MenuButton btn)
{
    string path = btn.itemPathname();
    if (path is null) return null;

    lastSelectedPath_ = path;
    lastSelectedIndex_ = btn.value();

    string text;
    textPrefs().get(path, text, "(no text found in data base)");
    return text;
}

/// Top-level dispatcher for the "Predefined" `MenuButton`'s own
/// callback, matching FLTK's `o->value()==1`/`==2`/else
/// branching exactly (relying on the same fixed 4-slot "Edit"
/// structure `reloadPredefinedMenu()` builds). `currentText` is the
/// Comment tab's text editor's current contents (for "Add"); `setText`
/// replaces them with a loaded template's text (for a normal pick).
void handlePredefinedSelection(MenuButton btn, string currentText, void delegate(string) setText)
{
    if (btn.value() == 1)
        addCurrentComment(btn, currentText);
    else if (btn.value() == 2)
        removeLastSelection(btn);
    else
    {
        string text = selectPredefinedText(btn);
        if (text !is null) setText(text);
    }
}
