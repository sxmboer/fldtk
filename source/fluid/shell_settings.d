// The interactive editor's Settings-dialog "Shell" tab -- field-wiring
// logic, kept as a hand-written companion module rather than inline
// `.fl` callback snippets (matching `fluid.bin_button`'s own precedent:
// a hand-written module a *generated* panel's callbacks call into, not
// itself Fluid-generated). `settings_panel.fl`'s own Shell-tab widgets
// each have a short one-line callback calling one function here --
// this file owns the actual list-management/field-load/field-apply
// logic, following this project's own established `panels/widget_panel.fl`
// idiom (direct `load()`/`onXChanged()` pairs, not FLTK's `v==LOAD`
// sentinel dispatch).
//
// Ported from FLTK's `fluid/panels/settings_panel.fl` lines
// ~935-1600 (the "Shell" tab: browser list, toolbar, details panel).
// `selectedIndex_` mirrors FLTK's own `w_settings_shell_list_
// selected` module-level int.
//
// Deliberate simplification from FLTK: FLTK's 4 "Example
// Scripts" menu items are dropped entirely -- they're `hide`-flagged/
// unimplemented placeholders in the real FLTK file too, not a
// scope cut made here.
//
// "Export selected" operates on the single currently-highlighted row.
// This matches FLTK exactly, not a simplification: FLTK's own
// `w_settings_shell_list` has no `type(FL_MULTI_BROWSER)` either, so
// `Fd_Shell_Command_List::export_selected()`'s loop over every row's
// `selected(i+1)` can only ever find the one row a normal (single-
// select) `Fl_Browser` allows to be selected at a time.

module fluid.shell_settings;

import fl;

import fluid.shell_command;
import fluid.shell_process : ShellFlags, shellSaveProject, shellSaveSourceCode,
    shellSaveStrings, shellDontShowTerminal, shellClearTerminal, shellClearHistory;
import settings_panel;
import shell_run_window : showShellRunWindow;

private int selectedIndex_ = -1; // -1 == nothing selected, matches FLTK's own "0" (1-based, 0 == none) shifted to 0-based

/// FLTK's own visible Condition menu order (`settings_panel.fl`'s
/// real `Fl_Choice` item list) does *not* match `ShellCondition`'s own
/// declaration order -- the Choice's item *index* and the enum's own
/// numeric *value* are two different things, so a translation table is
/// needed (same shape `panels/widget_panel.fl`'s own `boxtypeMap`-style
/// index<->value tables already use for a Choice whose menu order
/// differs from its backing enum).
private immutable ShellCondition[9] conditionMenuOrder = [
    ShellCondition.always, ShellCondition.winOnly, ShellCondition.uxOnly,
    ShellCondition.macOnly, ShellCondition.macAndUxOnly, ShellCondition.never,
    ShellCondition.userOnly, ShellCondition.hostOnly, ShellCondition.envOnly,
];

private int conditionToMenuIndex(ShellCondition c)
{
    foreach (i, v; conditionMenuOrder)
        if (v == c) return cast(int) i;
    return 0;
}

private immutable ToolStore[2] storeMenuOrder = [ToolStore.user, ToolStore.project];

private int storeToMenuIndex(ToolStore s)
{
    foreach (i, v; storeMenuOrder)
        if (v == s) return cast(int) i;
    return 0;
}

/// Rebuilds every row of `shellList` from `shellCommandList.list`,
/// preserving `selectedIndex_`'s own current selection if it's still
/// in range. Called after any add/duplicate/remove/import, and once at
/// Settings-dialog construction time.
///
/// Each row's storage-location icon is a real per-row `Browser.icon(int,
/// Image)` call, matching FLTK's own row-icon API.
/// `shellFdProjectBox`/`shellFdUserBox` (`settings_panel.fl`) are
/// hidden icon-holder widgets whose own `.image()` gets reused per
/// row, matching FLTK's own `w_settings_shell_fd_project`/
/// `w_settings_shell_fd_user` exactly.
void shellRefreshList()
{
    shellList.clear();
    foreach (i, cmd; shellCommandList.list)
    {
        shellList.add(cmd.name);
        int line = cast(int) i + 1; // Browser rows are 1-based
        if (cmd.storage == ToolStore.user)
            shellList.icon(line, shellFdUserBox.image());
        else if (cmd.storage == ToolStore.project)
            shellList.icon(line, shellFdProjectBox.image());
    }
    if (selectedIndex_ >= 0 && selectedIndex_ < cast(int) shellCommandList.list.length)
        shellList.value(selectedIndex_ + 1); // Browser rows are 1-based
    shellLoadDetails();
}

/// `shellList`'s own callback -- updates `selectedIndex_` from the
/// browser's own 1-based `.value()` and refreshes the details panel.
void shellOnListSelect()
{
    int line = shellList.value();
    selectedIndex_ = line > 0 ? line - 1 : -1;
    shellLoadDetails();
}

private ShellCommand selected()
{
    if (selectedIndex_ < 0 || selectedIndex_ >= cast(int) shellCommandList.list.length)
        return null;
    return shellCommandList.list[selectedIndex_];
}

/// Pushes the selected command's own fields into every detail widget
/// (or clears/deactivates them all if nothing is selected) -- the
/// "load" half of this panel's own direct load/apply field pairs.
void shellLoadDetails()
{
    auto cmd = selected();
    bool has = cmd !is null;

    shellCmdGroup.opt(has);

    shellPlayButton.opt(has);

    if (!has)
    {
        shellNameField.value("");
        shellLabelField.value("");
        shellShortcutField.shortcutValue(0);
        shellStoreField.value(0);
        shellConditionField.value(0);
        shellConditionDataField.value("");
        shellConditionDataField.hide();
        shellCommandField.buffer().text("");
        shellSaveProjectField.value(0);
        shellSaveSourceField.value(0);
        shellSaveStringsField.value(0);
        shellShowTerminalField.value(0);
        shellClearTerminalField.value(0);
        shellClearHistoryField.value(0);
        return;
    }

    shellNameField.value(cmd.name);
    shellLabelField.value(cmd.label);
    shellShortcutField.shortcutValue(cmd.shortcut);
    shellStoreField.value(storeToMenuIndex(cmd.storage));
    shellConditionField.value(conditionToMenuIndex(cmd.condition));
    shellConditionDataField.value(cmd.conditionData);
    if (cmd.condition == ShellCondition.userOnly || cmd.condition == ShellCondition.hostOnly
        || cmd.condition == ShellCondition.envOnly)
        shellConditionDataField.show();
    else
        shellConditionDataField.hide();
    shellCommandField.buffer().text(cmd.command);
    shellSaveProjectField.value((cmd.flags & shellSaveProject) != 0);
    shellSaveSourceField.value((cmd.flags & shellSaveSourceCode) != 0);
    shellSaveStringsField.value((cmd.flags & shellSaveStrings) != 0);
    shellShowTerminalField.value((cmd.flags & shellDontShowTerminal) == 0);
    shellClearTerminalField.value((cmd.flags & shellClearTerminal) != 0);
    shellClearHistoryField.value((cmd.flags & shellClearHistory) != 0);
}

/// Marks the project dirty if the just-edited command is project-
/// stored -- `gui_main.d` owns the real `dirty_`/undo state and has no
/// hook into this panel's own field edits, so this reaches out via the
/// same small `onProjectShellCommandChanged` delegate `gui_main.d`
/// wires once at startup (mirrors `fluid.shell_process`'s own outward-
/// delegate shape).
private void markDirtyIfProject(ShellCommand cmd)
{
    if (cmd.storage == ToolStore.project && onProjectShellCommandChanged !is null)
        onProjectShellCommandChanged();
}

/// Fired whenever an edit touches a `ToolStore.project` command --
/// `gui_main.d`'s own hook into "the project itself changed", since
/// this panel has no other way to reach `gui_main.d`'s private
/// `dirty_`/undo state.
void delegate() onProjectShellCommandChanged;

/// Fired after *any* change to the live command list -- add/duplicate/
/// remove/import, or any single field edit -- so `gui_main.d` can both
/// rebuild the `&Shell` menu and re-persist `ToolStore.user` entries to
/// `appPrefs` (there's no separate, narrower "only the fields that
/// actually affect the menu" signal; re-doing both on every edit is
/// cheap and simpler than tracking which fields need which side
/// effect).
void delegate() onShellListChanged;

private void notifyListChanged()
{
    if (onShellListChanged !is null) onShellListChanged();
}

// -- toolbar --

void shellAddCmd()
{
    auto cmd = new ShellCommand("New Command");
    size_t insertAt = selectedIndex_ >= 0 ? selectedIndex_ + 1 : shellCommandList.list.length;
    shellCommandList.insert(insertAt, cmd);
    selectedIndex_ = cast(int) insertAt;
    shellRefreshList();
    notifyListChanged();
}

void shellDupCmd()
{
    auto src = selected();
    if (src is null) return;
    auto cmd = new ShellCommand(src);
    size_t insertAt = selectedIndex_ + 1;
    shellCommandList.insert(insertAt, cmd);
    selectedIndex_ = cast(int) insertAt;
    shellRefreshList();
    notifyListChanged();
}

void shellRemoveCmd()
{
    if (selectedIndex_ < 0) return;
    auto cmd = shellCommandList.list[selectedIndex_];
    shellCommandList.remove(selectedIndex_);
    if (selectedIndex_ >= cast(int) shellCommandList.list.length)
        selectedIndex_ = cast(int) shellCommandList.list.length - 1;
    shellRefreshList();
    markDirtyIfProject(cmd);
    notifyListChanged();
}

void shellRunSelected()
{
    auto cmd = selected();
    if (cmd !is null) cmd.run();
}

// -- field apply (called from each widget's own callback) --

void shellApplyName()
{
    auto cmd = selected();
    if (cmd is null) return;
    cmd.name = shellNameField.value();
    shellList.text(selectedIndex_ + 1, cmd.name);
    markDirtyIfProject(cmd);
    notifyListChanged();
}

void shellApplyLabel()
{
    auto cmd = selected();
    if (cmd is null) return;
    cmd.label = shellLabelField.value();
    markDirtyIfProject(cmd);
    notifyListChanged();
}

void shellApplyShortcut()
{
    auto cmd = selected();
    if (cmd is null) return;
    cmd.shortcut = shellShortcutField.shortcutValue();
    markDirtyIfProject(cmd);
    notifyListChanged();
}

void shellApplyStore()
{
    auto cmd = selected();
    if (cmd is null) return;
    cmd.storage = storeMenuOrder[shellStoreField.value()];
    shellList.icon(selectedIndex_ + 1, cmd.storage == ToolStore.user ? shellFdUserBox.image() : shellFdProjectBox.image());
    markDirtyIfProject(cmd);
    notifyListChanged();
}

void shellApplyCondition()
{
    auto cmd = selected();
    if (cmd is null) return;
    cmd.condition = conditionMenuOrder[shellConditionField.value()];
    if (cmd.condition == ShellCondition.userOnly || cmd.condition == ShellCondition.hostOnly
        || cmd.condition == ShellCondition.envOnly)
        shellConditionDataField.show();
    else
        shellConditionDataField.hide();
    markDirtyIfProject(cmd);
    notifyListChanged();
}

void shellApplyConditionData()
{
    auto cmd = selected();
    if (cmd is null) return;
    cmd.conditionData = shellConditionDataField.value();
    markDirtyIfProject(cmd);
    notifyListChanged();
}

void shellApplyCommand()
{
    auto cmd = selected();
    if (cmd is null) return;
    cmd.command = shellCommandField.buffer().text();
    markDirtyIfProject(cmd);
    notifyListChanged();
}

/// Shared by all 6 save-flag `CheckButton`s -- each just toggles its
/// own bit and calls this, matching `panels/widget_panel.fl`'s own "plain
/// repetition over a generic table" call for a field count this small.
void shellApplyFlags()
{
    auto cmd = selected();
    if (cmd is null) return;
    ShellFlags f;
    if (shellSaveProjectField.value()) f |= shellSaveProject;
    if (shellSaveSourceField.value()) f |= shellSaveSourceCode;
    if (shellSaveStringsField.value()) f |= shellSaveStrings;
    if (!shellShowTerminalField.value()) f |= shellDontShowTerminal;
    if (shellClearTerminalField.value()) f |= shellClearTerminal;
    if (shellClearHistoryField.value()) f |= shellClearHistory;
    cmd.flags = f;
    markDirtyIfProject(cmd);
    notifyListChanged();
}

// -- macro-insert menu + zoom button --

/// Called by each of the 6 macro `MenuItem`s (`@BASENAME@`, etc, see
/// `settings_panel.fl`'s own Shell-tab macro `MenuButton`) with its own
/// literal macro text -- inserts at the command editor's own insert
/// position (FLTK's own `Fl_Text_Editor::insert_position()`
/// equivalent), or replaces the current selection if there is one.
void shellInsertMacro(string macro_)
{
    auto buf = shellCommandField.buffer();
    int start, end;
    if (buf.selectionPosition(start, end))
        buf.replace(start, end, macro_);
    else
        buf.insert(shellCommandField.insertPosition(), macro_);
    shellApplyCommand();
}

/// The "zoom" button -- opens `scriptPanel` (a bigger `TextEditor` for
/// the same command text) as a real modal edit loop, matching
/// `gui_main.d`'s own established `while (panel.shown()) fl.wait();`
/// pattern (see e.g. `newFromTemplate()`) rather than FLTK's own
/// `Fl::readqueue()` loop -- an equivalent, already-established-in-
/// this-project shape for "block until this dialog is dismissed."
void shellOpenScriptEditor()
{
    if (selected() is null) return;
    if (scriptPanel is null) makeScriptPanel();
    scriptInput.buffer().text(shellCommandField.buffer().text());
    scriptPanel.show();
    while (scriptPanel.shown())
        fl.wait();
}

void shellScriptOk()
{
    shellCommandField.buffer().text(scriptInput.buffer().text());
    shellApplyCommand();
    scriptPanel.hide();
}

void shellScriptCancel()
{
    scriptPanel.hide();
}

// -- import/export --

void shellExportSelected()
{
    auto cmd = selected();
    if (cmd is null) return;

    string path = fileChooser("Export Shell Commands", "*.flcmd", "");
    if (path.length == 0) return;

    auto file = new Preferences(path, "flcmd.fluid.fltk.org", null, rootCLocale | rootClear);
    auto group = new Preferences(file, "shell_commands");
    auto entry = new Preferences(group, "0");
    cmd.writeTo(entry, true);
}

void shellImportFromFile()
{
    string path = fileChooser("Import Shell Commands", "*.flcmd", "");
    if (path.length == 0) return;

    auto file = new Preferences(path, "flcmd.fluid.fltk.org", null, rootCLocale);
    auto group = new Preferences(file, "shell_commands");
    int n = group.groups();
    foreach (i; 0 .. n)
    {
        auto entry = new Preferences(group, i);
        auto cmd = new ShellCommand();
        cmd.storage = ToolStore.user;
        cmd.readFrom(entry);
        shellCommandList.add(cmd);
    }
    shellRefreshList();
    notifyListChanged();
}

/// `FlGroup.opt(bool)` -- FLTK's own `activate()`/`deactivate()` pair
/// spelled as a single call, matching how many of this panel's own
/// widgets need both an active/inactive AND (for the whole details
/// group) an implicit "there's nothing meaningful to show" state.
private void opt(FlGroup g, bool active)
{
    if (active) g.activate(); else g.deactivate();
}

private void opt(Widget w, bool active)
{
    if (active) w.activate(); else w.deactivate();
}
