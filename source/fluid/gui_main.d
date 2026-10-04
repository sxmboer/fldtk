/*
 * The interactive editor's app shell: one small "shelf" window (menu
 * bar + node browser, matching FLTK's real proportions/shape) plus,
 * once a project is open, one design-canvas window per top-level
 * `WindowNode` (`canvases_`, a `ProjectCanvas[WindowNode]`) and one
 * shared property-panel window. Undo/redo, settings, and about are all
 * real (`checkpoint()`/`undo()`/`redo()`, `settingsToggleVisibility()`,
 * `showAboutPanel()`). A `WindowNode` nested *inside* another window's
 * own widget tree (as opposed to a top-level project window) is a
 * separate, still-unported case -- see `instantiate.d`'s own top
 * comment.
 *
 * `&Edit` menu: Cut/Copy/Paste/Duplicate/Select All/
 * Select None are real -- `cutSelected()`/`copySelected()`/
 * `pasteFromClipboard()`/`duplicateSelected()` (an in-memory
 * `clipboardText_` holding real `.fl` text, not FLTK's own
 * `cutfname()` temp file -- see `clipboardText_`'s own doc comment)
 * and `selectAll()`/`selectNone()`. Ported from `Fluid.cxx`'s
 * `Application::cut_selected()`/`copy_selected()`/`paste_from_
 * clipboard()`/`duplicate_selected()` -- see each function's own doc
 * comment for the specific, deliberate simplifications from FLTK.
 *
 * Sort/Earlier/Later/Group/Ungroup are real --
 * `sortSelectedCmd()`/`earlierSelectedCmd()`/`laterSelectedCmd()`
 * (`fluid.node_order`, ported from `Widget_Node.cxx`'s free `sort()`
 * function and `Node.cxx`'s `earlier_cb()`/`later_cb()`) and
 * `groupSelectedCmd()`/`ungroupSelectedCmd()` (`fluid.group_ungroup`,
 * ported from `Group_Node.cxx`'s `group_cb()`/`ungroup_cb()`) -- both
 * modules build on three `fluid.node.Node` primitives,
 * `prevSibling()`/`nextSibling()`/`moveBefore()`, trivial here since
 * this port's `Node` is a real tree rather than FLTK's flat
 * doubly-linked list. See each module's own doc comment for the one
 * deliberate scope cut both share: the menu-item-grouping branch
 * `group_cb()`/`ungroup_cb()` themselves dispatch to first
 * (`Menu_Node.cxx`) isn't ported.
 * `fluid.flex_node.FlexNode.
 * fixedSizeTuples` stores *positional* child indices, which a reorder
 * would otherwise silently point at the wrong child -- `fluid.
 * node_order`/`fluid.group_ungroup` both call `fluid.flex_node.
 * reindexFlexIfNeeded()` right after every child-order/-membership
 * change. `fluid.group_ungroup.ungroupSelected()`'s own empty-parent
 * deletion is gated on the dissolved node genuinely being a
 * plain `GroupNode` (not a nested `WindowNode`, which needs
 * `removeNodes()`'s own fuller teardown -- `cv.hide()`/`canvases_.
 * remove()`/clearing `activeWindow_` -- to delete safely).
 *
 * `show_help()` is real -- `showHelp()` below,
 * wired to `&Help/&Rapid development with FLUID.../&FLTK Programmers
 * Manual...`. Ported from `Application::show_help()` (`Fluid.cxx`); see
 * its own doc comment for the fallback chain (`$FLTK_DOCDIR`, a canned
 * page, or `fl.openUri()` to fltk.org).
 *
 * `topLevelSelection()` reaches a
 * selected top-level `Function`/`decl`/`comment`/... project root for
 * Cut/Copy/Duplicate/Delete: selecting one in the browser has no
 * enclosing `WindowNode` to resolve `activeWindow_` from, so
 * `allSelectedNodes()` merges the canvas's own selection with the
 * node browser's authoritative one -- see that function's own doc
 * comment for the full mechanism. `pasteFromClipboard()` has the same
 * mechanism on the *target* side (pasting after a selected top-level
 * Code-group node lands beside the
 * target, not inside the active window) -- see that function's own doc comment.
 *
 * `print_snapshots()` is real too, backing `&File/&Print...` -- see
 * that function's own doc comment.
 *
 * The widget palette: a text `&New` menu lets the editor
 * create widgets, not just edit ones already in the file -- see
 * `addWidget()`'s own doc comment below. A real
 * "Tools" window also exists
 * (`function_panel : makeWidgetBin`,
 * generated from `fluid/panels/function_panel.fl` -- a literal,
 * geometry-faithful port of FLTK's own `widgetbin_panel`;
 * see that .fl file's own top comment for exactly which buttons
 * were kept/omitted and why). Both paths stay -- the menu remains a
 * complete, always-available way to create a widget, and the Tools
 * window (`&Edit/&Tools`)
 * additionally supports real drag-and-drop placement onto the canvas
 * (`fluid/panels/BinButton.d`'s `BinButton`) that the menu alone can't
 * offer.
 */
module fluid.gui_main;

import std.file : readText, write;
import std.stdio : stderr, writefln;

import fl;

import fluid.node : Node;
import fluid.widget_node : WidgetNode;
import fluid.window_node : WindowNode;
import fluid.group_node : GroupNode;
import fluid.project_reader : Reader;
import fluid.project_writer : ProjectWriter;
import fluid.raw_cpp_guard : looksLikeRawCpp;
import fluid.canvas : ProjectCanvas;
import fluid.node_browser : NodeBrowser, nodeBrowserLoadPrefs = loadPrefs;
import widget_panel : make_widget_panel, wireEditHooks, widgetPanelLoad = load,
    widgetPanelCurrent = current, refreshCodeFromNode, widgetPanelOnBeforeEdit = onBeforeEdit,
    widgetPanelOnEdited = onEdited, widgetPanelOnOpenExternalEditor = onOpenExternalEditor,
    widgetPanelOnBeforeTextEdit = onBeforeTextEdit,
    overlayCb, okCb, liveModeCb, wLiveMode, thePanel, widgetTabs, tabsWizard, overlayButton;
import fluid.factory : createNode;
import fluid.instantiate : instantiateOne, instantiateChild, instantiateStandalone, idealSizeFor, defaultLabelFor, LiveTree, loadImageFile, applyMenuItems, applyProperties;
import fluid.menu_owner_node : MenuOwnerNode;
import fluid.menu_item_node : MenuItemNode;
import fluid.layout_suite : layoutList, LayoutSuite, LayoutList;
import fluid.align_widget : AlignHow, alignWidgets;
import fluid.node_order : moveSelectedEarlier, moveSelectedLater, sortSelected;
import fluid.group_ungroup : groupSelected, ungroupSelected, fixGroupSize;
import fluid.i18n : I18nSettings, I18nType;
import fluid.project_settings : ProjectSettings;
import fluid.edit_session : EditSession;
import fluid.mergeback : Mergeback, Task, rememberCodePath, rememberedCodePath;
import fluid.project_history : History;
import fluid.app_prefs : appPrefs;
import fluid_icon : makeFluidIcon;
import about_panel : makeAboutPanel, aboutPanel;
import template_panel : makeTemplatePanel, templatePanel, templateBrowser,
    templateInstance, templateDelete, templateSubmit,
    templateName, templateClear, templateLoad, templateSelectedPath;
import codeview_panel : codeviewToggleVisibility, codeviewRefresh, codeviewPanel,
    codeviewUpdatePosition, codeviewAutoRefresh, cvOnReveal;
import settings_panel : settingsToggleVisibility, settingsShowShellTab, settingsShowLayoutTab,
    layoutRefreshTabIfOpen, layoutSaveUser;
import function_panel : makeWidgetBin, widgetBinPanel, binButtonCb, codeButtonCb, widgetBinToggleVisibility;
import fluid.bin_button : BinButton;
import fluid.shell_process;
import shell_run_window : makeShellRunWindow, showShellRunWindow, shellRunWindow,
    shellRunTerminal, shellRunButton;
import fluid.shell_command;
import fluid.shell_settings : onProjectShellCommandChanged, onShellListChanged;
import fluid.code_node : CodeNode;
import fluid.decl_node : DeclNode;
import fluid.data_node : DataNode;
import fluid.function_node : FunctionNode;
import fluid.external_code_editor : ExternalCodeEditor;
import fluid.pixmaps : loadPixmaps, pixmapFor;

private enum SHELF_W = 280;
private enum SHELF_H = 400;
private enum MENU_H = 25;

private Node[] projectRoots_;
private string projectPath_;

/// The current project's project-wide i18n settings (`fluid/proj/i18n`
/// port) -- set from `Reader.i18n` whenever a project is
/// loaded/restored (`loadProject()`/`restoreFromText()`), threaded
/// through every `ProjectWriter.generate()`/`Writer.generate()` call
/// this module makes so a project's own i18n configuration survives
/// checkpoint/undo/redo/save and shows up correctly in Code View,
/// rather than silently reverting to `I18nSettings.init` (no i18n) on
/// the very next round-trip. Defaults to `I18nSettings.init` for a
/// brand-new project (`newProject()`), matching FLTK's own
/// `I18n::reset()`.
private I18nSettings projectI18n_;

/// Direct read/write access to the live `projectI18n_` for the
/// Settings dialog's "Locale" tab (`fluid/panels/settings_panel.fl`) --
/// that panel lives outside the `fluid` package (a plain `settings_
/// panel` module under `fluid/panels/`, matching every other hand-
/// written panel companion here) and has no other way to reach this
/// module's own private state. Returns a pointer so the dialog's own
/// field callbacks can mutate the struct's members in place, matching
/// `panels/widget_panel.fl`'s own "read/write shared state directly" idiom
/// rather than a getter/setter pair per field.
I18nSettings* projectI18n() { return &projectI18n_; }

/// The project-wide "dub single-file-package header" setting
/// (`Settings -> Project`'s `dubHeaderButton`, `fluid/panels/
/// settings_panel.fl`) -- `false` (unchecked) for a brand-new project,
/// matching `newProject()`'s reset. See `code_writer.d`'s `Writer.
/// generate()` `dubHeader` parameter for what it actually controls, and
/// `project_writer.d`/`project_reader.d`'s own `dubHeader`/`dub_header`
/// for how it round-trips through the `.fl` project file. Same pointer-
/// access shape as `projectI18n()` just above, for the same reason.
private bool projectDubHeader_;
bool* projectDubHeader() { return &projectDubHeader_; }

/// The project's code-generation flags (`fluid.project_settings`:
/// `Settings -> Project`'s "Menu shortcuts use stateCommand"
/// checkbox), reset to defaults by `newProject()` and restored from
/// the `.fl` file's own Options block on load/undo/redo. Same
/// pointer-access shape as `projectI18n()` just above.
private ProjectSettings projectSettings_;
ProjectSettings* projectSettings() { return &projectSettings_; }

/// FLTK: `Project::code_file_name` (`.fl` Options-list `code_name`,
/// parsed by `Reader.codeFileName`/emitted by `ProjectWriter.generate()`'s
/// own `codeFileName` parameter) -- overrides the generated `.d` file's
/// own name (and, if it contains a path separator, its output
/// directory) independently of the `.fl` project file's own basename.
/// Empty means "use the project's own basename", matching `write
/// CodeFile()`'s own pre-existing default. Simplified from FLTK's
/// own three-case `codefile_name()` resolution (empty field / a bare
/// `.ext`-only value / a real name) down to two: this dialect always
/// generates `.d` regardless, so FLTK's own "type just the
/// extension" shorthand (there specifically to keep a `.cxx`/`.h` pair
/// in sync under one shared basename) has no real use case here with
/// only one output file to name -- see `settings_panel.fl`'s Project
/// tab for the user-facing field this backs, and its own top comment
/// for the fuller reasoning.
private string codeFileName_;

/// Read/write access for the Settings dialog's "Code File:" field,
/// matching `projectI18n()`'s own reasoning just above.
string* codeFileName() { return &codeFileName_; }

/// The `.fl` file's own directory, for resolving `WidgetNode.
/// imageFilename`/`.deimageFilename` (the `Widget_Image` port) the same way `code_writer.d`'s own headless codegen
/// path does -- "." for a not-yet-saved project (`projectPath_` unset),
/// matching `fluid.canvas.ProjectCanvas`'s own default.
private string projectDir_()
{
    import std.path : dirName;

    return projectPath_.length ? dirName(projectPath_) : ".";
}

/// Undo -- text snapshots of the
/// whole project (`ProjectWriter.generate(projectRoots_)`), not a
/// command-pattern edit log. Deliberately simpler than FLTK's own
/// `Fluid.proj.undo` (a real command/checkpoint stack over live `Node`
/// mutations): this port's own `Reader`/`ProjectWriter` already give a
/// fast, correct, already-tested serialize/deserialize round trip for
/// free (`project_writer.d`'s own load->save->load unittest proves the
/// round trip is lossless for everything this editor can actually
/// edit), so reusing it as the undo mechanism itself avoids building a
/// second, parallel "how do I reverse this specific kind of edit"
/// abstraction. A real deviation from FLTK's own approach, not a
/// port of it -- justified by scale (this editor's own projects are
/// nowhere near the size where re-serializing the whole tree per edit
/// would be a real cost) and by reuse (zero new parse/emit logic
/// needed). `checkpoint()` is called *before* a mutation (see
/// `panels/widget_panel.fl`'s `onBeforeEdit`'s own doc comment
/// on why that timing matters), from every one of this module's own
/// project-mutating entry points: `addWidget()`, `deleteSelected()`,
/// and the property panel's own field edits.
private string[] undoStack_;
private string[] redoStack_;

/// Dirty tracking -- true exactly when the current
/// project has edits `checkpoint()` has seen (i.e. every real edit)
/// that haven't been saved since. Small once undo already existed, as
/// that phase's own "Phasing" note predicted: `checkpoint()` already
/// fires at exactly the moments this needs to know about, so
/// `dirty_ = true` is one line added there rather than a second,
/// separately-tracked signal. Drives the shelf window's own title bar
/// (`updateShelfTitle()`) and the quit/close-with-unsaved-changes
/// prompt (`confirmDiscardChanges()`).
private bool dirty_;

/// One `ProjectCanvas` per currently-open top-level window, keyed by
/// its own `WindowNode` -- real FLTK has no "root window" concept at
/// all (confirmed by reading `Window_Node::open_()`/`Project_Reader::
/// read_project()`: every top-level window shows live, unconditionally,
/// as soon as it's read), so a project can have any number of these
/// open simultaneously (`panels/widget_panel.fl` has two, and both must
/// show correctly, with double-clicking either in the browser opening
/// the right one).
private ProjectCanvas[WindowNode] canvases_;

/// The window currently driving keyboard-shortcut-scoped edits (Cut/
/// Copy/Paste/Duplicate/Align/Select All/Select None/Delete) and the
/// property panel -- this port's counterpart to FLTK's single
/// project-wide `Fluid.proj.tree.current` pointer, which is *shared*
/// across every open window there too (FLTK has no per-window
/// selection scope either; neither does this port). Updated by every
/// per-canvas callback (`showWindowCanvas()`'s own wiring) and by
/// `openNode()`/`selectFromBrowser()` resolving whichever window a
/// given `Node` belongs to.
private WindowNode activeWindow_;

/// The canvas `activeWindow_` currently points at -- `null` before any
/// window has ever become active this session (a brand-new/emptied
/// project) or after that window's own canvas was torn down (e.g.
/// `closeProject()`) with nothing yet chosen to replace it.
private ProjectCanvas activeCanvas() { return canvases_.get(activeWindow_, null); }

/// The "Fluid Live Resize" wrapper window (`liveModeCb`'s own state) --
/// `null` whenever Live Resize isn't currently active. See `liveModeCb`'s
/// own assignment below for the full mechanism.
private DoubleWindow liveResizeWindow_;

/// `n`'s own enclosing top-level `WindowNode`, found by walking
/// `n.parent` (`n` itself if it's already one) -- `null` for a node
/// with no `WindowNode` ancestor at all (a bare `Function`/`decl`/...
/// project root, or anything hanging off one that isn't inside any
/// window yet).
private WindowNode enclosingWindowNode(Node n)
{
    for (Node p = n; p !is null; p = p.parent)
        if (auto wn = cast(WindowNode) p) return wn;
    return null;
}

/// The `ProjectCanvas` that shows/edits `n` -- resolved via
/// `enclosingWindowNode()`, then looked up in `canvases_`. `null` if
/// `n` has no `WindowNode` ancestor, or that window has no canvas yet
/// (a freshly-added `WindowNode` nobody has opened/shown yet).
private ProjectCanvas canvasFor(Node n)
{
    auto wn = enclosingWindowNode(n);
    return wn is null ? null : canvases_.get(wn, null);
}

/// After a `MenuItemNode`/`SubmenuNode` is added to, removed from, or
/// moved anywhere under a live `MenuOwnerNode`'s own subtree, that
/// widget's `.menu()` array needs rebuilding from scratch --
/// `instantiate.d`'s `applyMenuItems()` was, until now, only ever run
/// at construction time (`instantiateOne()`/`instantiateChild()`/
/// `instantiateStandalone()`), never again afterward, so a `Choice`/
/// `MenuButton`/`MenuBar`/`InputChoice` that's already live on the
/// canvas silently kept showing its stale dropdown after any edit to
/// its own menu items -- including the newly-real `Submenu`/
/// `CheckMenuItem`/`RadioMenuItem`/`MenuItem` creation this enables
/// (see `addNode()`), and, discovered the same way, plain deletion too
/// (see `removeNodes()`). `n` can be the item itself (post-add, its
/// `.parent` chain is already correct) or its former parent (post-
/// remove, since `Node.removeChild()` clears the removed node's own
/// `.parent` -- see that function's own doc comment) -- either way this
/// walks upward past any nesting `SubmenuNode`s to the one real
/// `MenuOwnerNode` that owns a live widget. A no-op when `n` has no
/// such ancestor (an ordinary widget/group edit) or that ancestor has
/// no live widget yet (nothing open on the canvas for it).
private void refreshLiveMenu(Node n)
{
    for (Node p = n; p !is null; p = p.parent)
    {
        auto owner = cast(MenuOwnerNode) p;
        if (owner is null) continue;
        auto cv = canvasFor(owner);
        if (cv is null) return;
        auto w = cv.liveTree().widgetOf.get(owner, null);
        if (w !is null) applyMenuItems(owner, w);
        return;
    }
}

/// Read-only accessor for the Settings dialog's General tab (`fluid/
/// panels/settings_panel.fl`'s "Show Positioning Guides" checkbox) --
/// that panel lives outside the `fluid` package and has no other way to
/// reach this module's own private canvas state. Matches the same
/// toggle the "&Edit/Hide Guides" menu item above already flips; now
/// resolves to whichever window is currently active among possibly
/// several open ones.
ProjectCanvas canvas() { return activeCanvas(); }

private NodeBrowser browser_;

/// Read-only accessor for the Settings dialog's "Show Comments in
/// Browser" checkbox (`fluid/panels/settings_panel.fl`), matching
/// `canvas()`'s own reasoning just above -- that panel lives outside
/// the `fluid` package and has no other way to reach this module's own
/// private `browser_`.
NodeBrowser browser() { return browser_; }
private Window shelf_;
private MenuBar menu_;

/// Mirrors `WidgetPanelDialog`'s own private `overlaysHidden_` (its
/// button-label state) -- tracked separately here rather than exposing
/// that field, since this module only ever needs to know the current
/// state to apply it to every open canvas, never to read the panel's
/// own copy back. Also the value newly-opened windows pick up (see
/// `showWindowCanvas()`), matching FLTK's own `Fluid.show_guides`/
/// `show_restricted`/overlay toggles: project-wide display settings,
/// not per-window state, even though each `ProjectCanvas` happens to
/// carry its own instance of the underlying field.
private bool overlaysHidden_;
private bool showGuides_ = true;
private bool showRestricted_ = true;
private bool showGhostedOutline_ = true;
private bool allowLayout_ = false;

/// Shared body for `&Edit/Hide O&verlays` (FLTK's own `toggle_
/// overlays()`, `Fluid.cxx`) and `widget_panel.fl`'s own `overlayCb`
/// (the panel's own "Hide Overlays" button) -- extracted so the two
/// real triggers for this one toggle can't drift out of sync with each
/// other (see `runEditor()`'s own `onToggleOverlays` wiring).
/// Applies to every currently-open window's canvas -- a display
/// preference, not a single
/// document's own state.
private void toggleOverlays()
{
    overlaysHidden_ = !overlaysHidden_;
    foreach (cv; canvases_.byValue())
    {
        cv.overlaysHidden = overlaysHidden_;
        cv.redrawOverlay();
    }
}

/// Read/write accessors for `showGuides_`/`showRestricted_`/
/// `showGhostedOutline_` -- exposed publicly for multi-window
/// support: `settings_panel.
/// fl`'s own three "Overlays:" checkboxes must not read/write
/// `canvas().showGuides` etc. directly, which would only touch
/// whichever single canvas happens to be active and never update
/// this module's own shadow state, so a newly-opened *second* window
/// would silently ignore whatever the Settings dialog had just set, and
/// the checkbox itself would show the wrong value after switching which
/// window was active. Every setter here applies to every currently
/// open canvas at once and updates the shared shadow field
/// `showWindowCanvas()` seeds a freshly-opened canvas from -- the exact
/// same "one project-wide preference, several canvases carrying their
/// own copy of the underlying field" shape `toggleOverlays()` already
/// established, just generalized to the two menu-only toggles and the
/// one Settings-dialog-only toggle alike.
bool showGuides() { return showGuides_; }
void showGuides(bool v)
{
    showGuides_ = v;
    foreach (cv; canvases_.byValue()) cv.showGuides = v;
}

bool showRestricted() { return showRestricted_; }
void showRestricted(bool v)
{
    showRestricted_ = v;
    foreach (cv; canvases_.byValue()) { cv.showRestricted = v; cv.redrawOverlay(); }
}

bool showGhostedOutline() { return showGhostedOutline_; }
void showGhostedOutline(bool v)
{
    showGhostedOutline_ = v;
    foreach (cv; canvases_.byValue()) { cv.showGhostedOutline = v; cv.redraw(); }
}

/// See `ProjectCanvas.allowLayout`'s own doc comment for the actual
/// mechanism -- this is purely the same "one shared preference, every
/// open canvas carries its own mirrored copy" plumbing `showGuides()`/
/// etc. above already established, applied to a fourth toggle. No
/// redraw needed here (unlike the three above): this only changes how
/// a *future* interactive resize behaves, not anything already on
/// screen.
bool allowLayout() { return allowLayout_; }
void allowLayout(bool v)
{
    allowLayout_ = v;
    foreach (cv; canvases_.byValue()) cv.allowLayout = v;
}

/// Recent-projects list (`fluid/app/history` port) --
/// loaded once in `runEditor()`, updated (and the shelf menu rebuilt)
/// every time a project gets a real, saved-to-disk path
/// (`loadProject()`/`writeProjectTo()`).
private History history_;

/// Full `"&File/..."` menu paths of the recent-file items currently
/// shown, in display order -- needed by `rebuildRecentFilesMenu()` to
/// remove exactly last time's items (and no more) before re-adding a
/// fresh set, since `fl.menu_.Menu_` (unlike FLTK's own pre-
/// allocated, in-place-relabeled `Fl_Menu_Item[10]`) has no by-index
/// relabel-and-rehide primitive to update existing items in place --
/// see that function's own doc comment for the full reasoning.
private string[] recentMenuPaths_;

/// Entry point for `fluid [file.fl]` (GUI mode, now the default -- see
/// `app.d`'s own top comment) -- see that module's `main()` for the
/// branch that calls this.
void runEditor(string[] args)
{
    // Ported from FLTK's own `loadPixmaps();` call in `make_main_
    // window()` (`Fluid.cxx`) -- populates `fluid.pixmaps`' per-node-
    // type icon table once at startup, before anything that might
    // display one (the widget palette, the node browser) gets built.
    loadPixmaps();

    shelf_ = new Window(SHELF_W, SHELF_H, "Fluid");
    makeFluidIcon(shelf_);
    // Matches FLTK's own `main_window->callback(exit_cb)` -- the
    // window-manager close box quits through the same path (confirm-
    // discard-changes, save window positions) as `&File/&Quit`, rather
    // than the default `Widget.defaultCallback()`'s bare hide-and-queue.
    shelf_.callback((w) { doQuit(); });

    auto menu = new MenuBar(0, 0, SHELF_W, MENU_H);
    menu_ = menu;
    // Ported from FLTK's own `main_menubar->global();`
    // (`Fluid.cxx`) -- makes every shortcut on this menu (Ctrl-C/V/X/
    // Z/..., Alt-mnemonics) reachable regardless of which top-level
    // window currently has focus, via `fl.menu_.Menu_.global()`'s
    // already-real `fl.core.addHandler()` registration. Without this,
    // a shortcut typed while `canvas_`/`panel_` (separate top-level
    // windows from this one, `shelf_`) has focus never reaches this
    // menu at all -- `fl.core.handle()`'s own `Event.shortcut`
    // dispatch only walks the *current* event's own window chain, and
    // FLTK's real Fluid relies on exactly this `.global()` call,
    // not some other cross-window mechanism, to work around that (a
    // real, live FLTK app behavior, not a gap specific to this port --
    // confirmed by reading `Fluid.cxx` itself, not assumed). Without
    // it, Ctrl-C/Ctrl-V would only work with
    // focus in the node browser (same window as this menu bar), not
    // in the canvas.
    menu.global();
    // Order/shortcuts/dividers match `fluid/app/Menu.cxx`'s real
    // `main_menu[]` &File group exactly. `&Insert...`/`Sa&ve A Copy...`/
    // `&Revert...` are real, planned features with no implementation yet
    // (each independently portable, just not done) -- present below as
    // deactivated placeholders (`menuInactive`), same pattern as
    // `&Edit`'s/`&Layout`'s own placeholder items just below, so this
    // menu's layout and divider
    // grouping don't need revisiting again once each lands. `&Print...`
    // is real (`printSnapshots()` below).
    menu.add("&File/&New", stateCtrl + 'n', (w) { if (confirmDiscardChanges()) newProject(); });
    menu.add("&File/&Open...", stateCtrl + 'o', (w) { if (confirmDiscardChanges()) openProject(); });
    menu.add("&File/&Insert...", stateCtrl + 'i', null, menuInactive | menuDivider);
    menu.add("&File/&Save", stateCtrl + 's', (w) { saveProject(); });
    menu.add("&File/Save &As...", stateCtrl + stateShift + 's', (w) { saveProjectAs(); });
    menu.add("&File/Sa&ve A Copy...", 0, null, menuInactive);
    menu.add("&File/&Revert...", 0, null, menuInactive | menuDivider);
    menu.add("&File/New &From Template...", stateCtrl + stateShift + 'n', (w) { if (confirmDiscardChanges()) newFromTemplate(); });
    menu.add("&File/Save As &Template...", 0, (w) { saveAsTemplate(); }, menuDivider);
    menu.add("&File/&Print...", stateCtrl + 'p', (w) { printSnapshots(); });
    // `writeCodeFile()` already existed (a shell-command save action,
    // `ShellFlags.shellSaveSourceCode`) but had no menu entry of its
    // own -- FLTK's real "Write &Code" (`FL_COMMAND+FL_SHIFT+'c'`)
    // wires straight to it.
    menu.add("&File/Write &Code", stateCtrl + stateShift + 'c', (w) { writeCodeFile(); });
    // Hidden unless the project has MergeBack enabled, see `updateMergebackMenu()`.
    menu.add("&File/MergeBack Code", stateCtrl + stateShift + 'm', (w) { mergebackCodeFiles(true); }, menuInvisible);
    menu.add("&File/&Write Strings", stateCtrl + stateShift + 'w', (w) { writeStringsFile(); }, menuDivider);

    history_ = new History();
    history_.load(appPrefs);
    rebuildRecentFilesMenu(); // adds the recent-file items and &File/&Quit together, in that order

    // Ported from `Fluid.cxx`'s own startup sequence: `history.load();
    // ...; widget_browser->load_prefs();` -- loads the User tab's 12
    // persisted role color/font values (`fluid.node_browser.
    // loadPrefs()`) before the project tree is ever drawn, so a
    // previous session's customization (or the very first run's real
    // defaults) is in effect from the first paint, not just from the
    // next time the Settings dialog happens to touch one of these
    // fields.
    nodeBrowserLoadPrefs();
    startAutoMergeback();

    // FLTK's own top-level order is File, Edit, New, Layout, Shell,
    // Help (`fluid/app/Menu.cxx`'s `Application::main_menu[]`) --
    // `Menu_.add()`'s path API orders top-level entries by first-seen
    // call order, so &Edit's own block must be built here, second, to
    // land in the right position.
    //
    // Names/shortcuts/divider placement below match
    // FLTK's real &Edit group exactly for every item this port
    // implements, including `&Delete` (FLTK's own text has no
    // "Selected"), `Show Widget &Bin...` (the window
    // this opens really is titled "Widget Bin" -- `function_panel.fl`'s
    // own `widgetbin_panel`), and `Show Code View`: FLTK's own text
    // genuinely has no `&`-mnemonic on this one item (every other item
    // in this whole menu does; confirmed by reading `Menu.cxx` itself,
    // not assumed to be a transcription slip). `Hide O&verlays` is a
    // real menu item -- see `toggleOverlays()` just
    // above, shared with the Widget Properties panel's own button so the two triggers can't drift.
    // `&Sort`/`&Earlier`/`&Later`/`&Group`/`Ung&roup` are real --
    // `sortSelectedCmd()`/`earlierSelectedCmd()`/
    // `laterSelectedCmd()` (`fluid.node_order`) and `groupSelectedCmd()`/
    // `ungroupSelectedCmd()` (`fluid.group_ungroup`); see each module's
    // own doc comment. Still not (yet) ported, so not wired to
    // anything: `Pr&operties...`. `Hide Restricted` is real too, see its own
    // `.add()` call below. Present as deactivated placeholders
    // anyway: these are
    // real, planned features (not permanent exclusions like the
    // Forms-compat items CLAUDE.md documents), so the
    // position/shortcut/divider is locked in
    // via `menuInactive` (grays the item out and makes it
    // unselectable/non-shortcut-reachable, matching FLTK's own
    // `FL_MENU_INACTIVE` semantics exactly), with a real callback
    // dropped in the moment the underlying mechanism exists. `f + n` is
    // this port's `FL_F(n)` -- `fl.enumerations.f == 0xffbd`, "f + n
    // for function key n", matching FLTK's own encoding.
    menu.add("&Edit/&Undo", stateCtrl + 'z', (w) { undo(); });
    menu.add("&Edit/&Redo", stateCtrl + stateShift + 'z', (w) { redo(); }, menuDivider);
    menu.add("&Edit/C&ut", stateCtrl + 'x', (w) { cutSelected(); });
    menu.add("&Edit/&Copy", stateCtrl + 'c', (w) { copySelected(); });
    menu.add("&Edit/&Paste", stateCtrl + 'v', (w) { pasteFromClipboard(); });
    menu.add("&Edit/Dup&licate", stateCtrl + 'u', (w) { duplicateSelected(); });
    menu.add("&Edit/&Delete", deleteKey, (w) { deleteSelected(); }, menuDivider);
    menu.add("&Edit/Select &All", stateCtrl + 'a', (w) { selectAll(); });
    menu.add("&Edit/Select &None", stateCtrl + stateShift + 'a', (w) { selectNone(); }, menuDivider);
    menu.add("&Edit/Pr&operties...", fl.enumerations.f + 1, null, menuInactive);
    menu.add("&Edit/&Sort", 0, (w) { sortSelectedCmd(); });
    menu.add("&Edit/&Earlier", fl.enumerations.f + 2, (w) { earlierSelectedCmd(); });
    menu.add("&Edit/&Later", fl.enumerations.f + 3, (w) { laterSelectedCmd(); });
    menu.add("&Edit/&Group", fl.enumerations.f + 7, (w) { groupSelectedCmd(); });
    menu.add("&Edit/Ung&roup", fl.enumerations.f + 8, (w) { ungroupSelectedCmd(); });
    // Not a port -- real Fluid has no equivalent menu item (F+9 is
    // unused across its own whole menu, confirmed against `Menu.cxx`).
    // See `fitGroupToContentsCmd()`'s own doc comment for why this
    // exists at all.
    menu.add("&Edit/Fit &Group to Contents", fl.enumerations.f + 9, (w) { fitGroupToContentsCmd(); }, menuDivider);
    menu.add("&Edit/Hide O&verlays", stateCtrl + stateShift + 'o', (w) { toggleOverlays(); });
    // Matches FLTK's own `Fluid.show_guides` toggle (a main-menu
    // item there too, `toggle_guides()`) -- see `ProjectCanvas.
    // showGuides`'s own doc comment for what it actually gates.
    // Deliberately simpler than FLTK here: a plain toggle, no
    // dynamic checkmark/relabel (FLTK's own `guides_button->value(
    // ...)` has no menu-item equivalent wired up yet) and no persisted
    // preference -- both real, smaller follow-ups.
    menu.add("&Edit/Hide Guides", stateCtrl + stateShift + 'g', (w) { showGuides(!showGuides_); });
    // Matches FLTK's own `Fluid.show_restricted` toggle -- see
    // `ProjectCanvas.showRestricted`'s own doc comment
    // for what it actually gates (the out-of-bounds/overlap hatching
    // feature this menu item flips).
    menu.add("&Edit/Hide Restricted", stateCtrl + stateShift + 'r', (w) { showRestricted(!showRestricted_); });
    menu.add("&Edit/Show Widget &Bin...", stateAlt + 'b', (w) { widgetBinToggleVisibility(); });
    menu.add("&Edit/Show Code View", stateAlt + 'c', (w) { codeviewToggleVisibility(projectRoots_, projectI18n_, projectDubHeader_, projectSettings_); }, menuDivider);
    menu.add("&Edit/&Settings...", stateAlt + 'p', (w) { settingsToggleVisibility(); });
    // FLTK's own top-level order is File, Edit, New, Layout, Shell,
    // Help and its own `New_Menu[]` group order/names are Code, Group,
    // Buttons, Valuators, Text, Menus, Browsers, Other
    // (`fluid/nodes/factory.cxx`) -- so this whole &New block must
    // build, in this group order, before &Layout's own first `.add()`
    // call just below it (`Menu_.add()`'s path API orders top-level
    // entries, and items within one submenu, by first-seen call order),
    // with its container-widgets
    // group named "Group" (matching FLTK, not "Containers"),
    // groups ordered Code/Group/Buttons/Valuators/Text/Menus/Browsers/Other,
    // and a dedicated Menus group for Menu
    // Bar/Menu Button/Choice/Input Choice.
    //
    // See addWidget()'s/addNode()'s own doc comments for the target-
    // parent/default-geometry rules every one of these shares. The flat
    // set of type names is exactly `fluid.instantiate`'s registry
    // (identical to `fluid.factory`'s, see that module's own comment on
    // why the two stay in lockstep), minus "Window"/"DoubleWindow"
    // (a `WindowNode` nested inside another window's own widget tree
    // isn't rendered by the canvas at all -- see `instantiate.d`'s
    // `instantiateChild()` -- so offering them here
    // would silently create a dead-end node the canvas can't show) and
    // minus FLTK's own Submenu/Menu_Item/Checkbox_Menu_Item/
    // Radio_Menu_Item entries (menu-item-editing nodes with no
    // `addNode()`/`addWidget()` target-selection support in this port
    // yet -- a real, separate follow-up, not silently dropped).
    //
    // **Deliberate text deviation**: FLTK's own
    // `fill_in_New_Menu()` auto-derives a plain widget type's leaf label
    // by stripping `Fl_` off `type_name()` and using what's left as-is
    // (literal underscores -- "Return_Button", "Value_Slider", ...), and
    // FLTK's `New_Menu[]` has no `&`-mnemonics anywhere in it at all
    // (a flat ~50-item list where single-letter mnemonics would collide
    // constantly). This block's own space-separated labels ("Return
    // Button") and per-item mnemonics are real deviations from that
    // literal text -- but a deliberate, kept one: they match the mnemonic
    // convention every *other* menu in this file already uses
    // (File/Edit/Layout/...). Category *names* (just below)
    // match FLTK's own `New_Menu[]` strings exactly.
    //
    // Every leaf item also gets the same 16x16 icon the widget palette's
    // own buttons use (`fluid.pixmaps.pixmapFor()`, matching FLTK's
    // own `fill_in_New_Menu()`/`make_iconlabel()`).
    // Uses `Menu_.multiLabel()`, not `Menu_.image(idx, icon)` (a plain
    // `MenuItem.image()` field), which would produce an "icon and name show on two
    // lines instead of one" result -- `fl.widget.Label.measure()`/`draw()`
    // default an image with no `alignImageNextToText` bit to stacking
    // *above* the text (matching FLTK's own `fl_normal_measure()`/
    // `fl_normal_label()` exactly, confirmed by reading `fl_labeltype.
    // cxx` -- not a fldtk-only quirk), and `MenuItem::draw()` draws its
    // label with plain `FL_ALIGN_LEFT`, no next-to-text bit, matching
    // FLTK's own `Fl_Menu_Item::draw()` call site exactly too. This
    // is *why* FLTK's own `make_iconlabel()` reaches for an
    // `Fl_Multi_Label` instead of `Fl_Menu_Item::image()` here --
    // `Fl_Multi_Label::draw()`/`measure()` (`fl.multi_label`) always lay
    // their two parts out left-to-right regardless of that bit. Ported
    // for real via `addIcon()` below (`Menu_.multiLabel()`, mirroring
    // `Menu_.image()`), including FLTK's own
    // leading-space-plus-"..." suffix on the text part (FLTK's
    // `make_iconlabel()`: `" " + txt + "..."`) -- not cosmetic filler:
    // every one of these items' own callback (`addWidget()`/`addNode()`
    // -> `openNode()`) already opens the Widget Properties panel right
    // after creating the node, so "..." correctly signals "this opens a
    // dialog" the same way it does on any other menu item in this app.
    // `pixmapFor()` returning `null` for a handful of types with no
    // dedicated icon FLTK either (Fl_Float_Input/Fl_Int_Input, ...)
    // is handled the same way FLTK's own `else` branch does: leave
    // the item's plain text alone, no `MultiLabel`, no "..." suffix.
    void addIcon(int idx, string typeName)
    {
        auto icon = pixmapFor(typeName);
        if (icon is null) return;
        auto ml = new MultiLabel();
        ml.imageA = icon;
        ml.textB = " " ~ menu.text(idx) ~ "...";
        menu.multiLabel(idx, ml);
    }
    void newWidgetItem(string path, string typeName)
    {
        int idx = menu.add(path, 0, (w) { addWidget(typeName); });
        addIcon(idx, typeName);
    }
    void newNodeItem(string path, string typeName)
    {
        int idx = menu.add(path, 0, (w) { addNode(typeName); });
        addIcon(idx, typeName);
    }
    // Deactivated placeholder for a real FLTK `New_Menu` leaf whose
    // node type isn't registered in `fluid.factory`'s registry yet --
    // `createNode()` throws on an unknown type name, so this can't be
    // wired to `addNode()`/`addWidget()` the way `newNodeItem()`/
    // `newWidgetItem()` are; still gets the same icon+"..." treatment
    // for visual consistency with every other &New leaf (FLTK's
    // own `fill_in_New_Menu()` icon-labels every leaf regardless of
    // whether this port has gotten around to implementing it).
    void newDeadItem(string path, string typeName)
    {
        int idx = menu.add(path, 0, null, menuInactive);
        addIcon(idx, typeName);
    }

    // The palette's "Code" group -- project-structure nodes, not canvas
    // widgets, so these route through `addNode()`, not `addWidget()`
    // (see that function's own doc comment for the target-selection
    // rule, which differs from `addWidget()`'s widget-only version).
    newNodeItem("&New/&Code/&Function", "Function");
    newNodeItem("&New/&Code/C&lass", "class");
    newNodeItem("&New/&Code/Co&mment", "comment");
    newNodeItem("&New/&Code/&Code", "code");
    newNodeItem("&New/&Code/Code Bloc&k", "codeblock");
    newNodeItem("&New/&Code/&Widget Class", "widget_class");
    newNodeItem("&New/&Code/&Declaration", "decl");
    newNodeItem("&New/&Code/Declaration &Block", "declblock");
    newNodeItem("&New/&Code/&Inline Data", "data");
    // Order matches FLTK's own `New_Menu[]` "Group" category
    // exactly: Window, Group, Pack, Flex, Tabs, Scroll, Tile, Wizard,
    // Grid.
    //
    // `&Window` mimics what FLTK does when clicking on window, via
    // `createWindowNode()` -- not `newWidgetItem()`/`addWidget()` like
    // every sibling here, since a window nested inside another window's
    // canvas has no live-rendering path (`instantiate.d`'s
    // `instantiateChild()` already skips `WindowNode`s) and needs FLTK's own real placement
    // rule (a function ancestor, or a "Please select a function"
    // message) rather than `addWidget()`'s generic "current selection
    // or project root" fallback. See `createWindowNode()`'s own doc
    // comment for the full port of `Window_Node::make()`'s logic.
    {
        int idx = menu.add("&New/&Group/&Window", 0, (w) { createWindowNode(); });
        addIcon(idx, "Window");
    }
    newWidgetItem("&New/&Group/&Group", "Group");
    newWidgetItem("&New/&Group/&Pack", "Pack");
    newWidgetItem("&New/&Group/F&lex", "Flex");
    newWidgetItem("&New/&Group/&Tabs", "Tabs");
    newWidgetItem("&New/&Group/S&croll", "Scroll");
    newWidgetItem("&New/&Group/Til&e", "Tile");
    newWidgetItem("&New/&Group/&Wizard", "Wizard");
    newWidgetItem("&New/&Group/G&rid", "Grid");
    newWidgetItem("&New/&Buttons/&Button", "Button");
    newWidgetItem("&New/&Buttons/&Return Button", "ReturnButton");
    newWidgetItem("&New/&Buttons/&Light Button", "LightButton");
    newWidgetItem("&New/&Buttons/&Check Button", "CheckButton");
    newWidgetItem("&New/&Buttons/&Round Button", "RoundButton");
    newWidgetItem("&New/&Buttons/Re&peat Button", "RepeatButton");
    newWidgetItem("&New/&Valuators/&Slider", "Slider");
    newWidgetItem("&New/&Valuators/Value S&lider", "ValueSlider");
    newWidgetItem("&New/&Valuators/Value &Input", "ValueInput");
    newWidgetItem("&New/&Valuators/Scroll&bar", "Scrollbar");
    newWidgetItem("&New/&Valuators/R&oller", "Roller");
    newWidgetItem("&New/&Valuators/&Dial", "Dial");
    newWidgetItem("&New/&Valuators/Cloc&k", "Clock");
    // Not FLTK -- see `fluid.factory`'s own matching registry
    // comment for why this exists at all (added at the user's explicit
    // request, after asking about `Fl_Clock`/`Fl_Clock_Output`'s real
    // difference). Placed right next to Clock since FLTK has no
    // menu precedent of its own to match for this one.
    newWidgetItem("&New/&Valuators/Clock &Output", "ClockOutput");
    newWidgetItem("&New/&Valuators/Ad&juster", "Adjuster");
    newWidgetItem("&New/&Valuators/&Counter", "Counter");
    newWidgetItem("&New/&Valuators/&Spinner", "Spinner");
    newWidgetItem("&New/&Text/&Input", "Input");
    newWidgetItem("&New/&Text/&Output", "Output");
    newWidgetItem("&New/&Text/&Float Input", "FloatInput");
    newWidgetItem("&New/&Text/&Int Input", "IntInput");
    newWidgetItem("&New/&Text/Value O&utput", "ValueOutput");
    newWidgetItem("&New/&Text/Text &Display", "TextDisplay");
    newWidgetItem("&New/&Text/Text Ed&itor", "TextEditor");
    newWidgetItem("&New/&Text/Fil&e Input", "FileInput");
    // Matches FLTK's own dedicated "Menus" group (`New_Menu[]`), all 8
    // entries. The last 4 (`Submenu`/`MenuItem`/
    // `CheckMenuItem`/`RadioMenuItem`) are menu-item-editing node
    // types, not canvas widgets: `fluid.factory`'s registry has `"Submenu"` (a real
    // `SubmenuNode`, `canHaveChildren() == true` so nested items parse
    // and can themselves be added under it) and `"CheckMenuItem"`/
    // `"RadioMenuItem"` (plain `MenuItemNode`s -- see that class's own
    // doc comment for why no dedicated D subclass was needed for
    // these two), and `addNode()`'s target-selection logic nests any
    // of the four under a currently-selected `MenuOwnerNode`/
    // `SubmenuNode` for real, including the `AFTER_CURRENT`-style
    // sibling-insert fix that made "select a MenuItem, add another"
    // land next to it instead of at the project root (see `addNode()`'s
    // own doc comment).
    newWidgetItem("&New/&Menus/&Menu Bar", "MenuBar");
    newWidgetItem("&New/&Menus/Menu &Button", "MenuButton");
    newWidgetItem("&New/&Menus/C&hoice", "Choice");
    newWidgetItem("&New/&Menus/&Input Choice", "InputChoice");
    newNodeItem("&New/&Menus/Sub&menu", "Submenu");
    newNodeItem("&New/&Menus/Menu &Item", "MenuItem");
    newNodeItem("&New/&Menus/&Checkbox Menu Item", "CheckMenuItem");
    newNodeItem("&New/&Menus/&Radio Menu Item", "RadioMenuItem");
    // A dedicated category, matching `function_panel.fl`'s own "Browsers"
    // group box.
    newWidgetItem("&New/&Browsers/&Browser", "Browser");
    newWidgetItem("&New/&Browsers/Tre&e", "Tree");
    newWidgetItem("&New/&Browsers/Chec&k Browser", "CheckBrowser");
    newWidgetItem("&New/&Browsers/&Help View", "HelpView");
    newWidgetItem("&New/&Browsers/File Bro&wser", "FileBrowser");
    newWidgetItem("&New/&Browsers/Ta&ble", "Table");
    newWidgetItem("&New/&Other/Bo&x", "Box");
    newWidgetItem("&New/&Other/&Terminal", "Terminal");
    newWidgetItem("&New/&Other/Pro&gress", "Progress");

    menu.add("&Layout/&Align/&Left", 0, (w) { alignSelected(AlignHow.left); });
    menu.add("&Layout/&Align/&Center", 0, (w) { alignSelected(AlignHow.hCenter); });
    menu.add("&Layout/&Align/&Right", 0, (w) { alignSelected(AlignHow.right); });
    menu.add("&Layout/&Align/&Top", 0, (w) { alignSelected(AlignHow.top); });
    menu.add("&Layout/&Align/&Middle", 0, (w) { alignSelected(AlignHow.vCenter); });
    menu.add("&Layout/&Align/&Bottom", 0, (w) { alignSelected(AlignHow.bottom); });
    menu.add("&Layout/&Space Evenly/&Across", 0, (w) { alignSelected(AlignHow.spaceAcross); });
    menu.add("&Layout/&Space Evenly/&Down", 0, (w) { alignSelected(AlignHow.spaceDown); });
    menu.add("&Layout/&Make Same Size/&Width", 0, (w) { alignSelected(AlignHow.sameWidth); });
    menu.add("&Layout/&Make Same Size/&Height", 0, (w) { alignSelected(AlignHow.sameHeight); });
    menu.add("&Layout/&Make Same Size/&Both", 0, (w) { alignSelected(AlignHow.sameSize); });
    menu.add("&Layout/&Center In Group/&Horizontal", 0, (w) { alignSelected(AlignHow.centerHorizontal); });
    menu.add("&Layout/&Center In Group/&Vertical", 0, (w) { alignSelected(AlignHow.centerVertical); });

    // "Synchronized Resize" toggles `allowLayout()` below.
    // "&Grid and Size Settings..." opens the Settings
    // dialog straight to the Layout tab, matching FLTK's own
    // `show_grid_cb()` (`Window_Node.cxx`: `settings_window->show();
    // w_settings_tabs->value(w_settings_layout_tab);`).
    menu.add("&Layout/Synchronized Resize", 0, (w) { allowLayout(!allowLayout_); }, menuToggle | menuDivider);
    menu.add("&Layout/&Grid and Size Settings...", stateCtrl + 'g', (w) { settingsShowLayoutTab(); }, menuDivider);

    // Matches FLTK's own `main_layout_submenu_`/`Presets` submenu
    // pointer plus the 3 flat radio siblings that follow it directly in
    // `main_menu[]` (`app/Snap_Action.cxx`/`app/Menu.cxx`): "Presets" is
    // its own tiny nested radio submenu selecting which *suite* is
    // active, dynamically rebuilt from `layoutList` itself now
    // (`rebuildLayoutMenu()`, same "&Presets" convention -- see also the
    // FLTK-repo-confirmed structure note in `rebuildLayoutMenu()`'s own
    // doc comment) so a custom suite added from the Settings dialog's
    // "+" button shows up here too, matching FLTK's own `capacity()`-
    // grown `main_menu_`; "Application"/"Dialog"/"Toolbox" are a
    // SEPARATE flat radio group of 3 fixed siblings directly under
    // &Layout (not nested inside "Presets"), selecting which *preset
    // within the current suite* is active -- fixed since there are
    // always exactly 3, only their checked state needs refreshing.
    menu.add("&Layout/&Application", 0, (w) { layoutList.currentPreset(0); layoutMenuChanged(); }, menuRadio | menuValue);
    menu.add("&Layout/&Dialog", 0, (w) { layoutList.currentPreset(1); layoutMenuChanged(); }, menuRadio);
    menu.add("&Layout/&Toolbox", 0, (w) { layoutList.currentPreset(2); layoutMenuChanged(); }, menuRadio);
    rebuildLayoutMenu(); // adds the &Layout/&Presets/* radio group from layoutList itself

    browser_ = new NodeBrowser(0, MENU_H, SHELF_W, SHELF_H - MENU_H);
    // NodeBrowser extends Tree extends Group -- its own constructor's
    // inherited FlGroup.begin() left FlGroup.current() pointing at
    // browser_ itself, not restored back to shelf_ (Tree doesn't add
    // any real Widget children of its own during construction, so
    // there's no matching end() call inside it to do that for us).
    // Nothing here currently constructs another shelf_ child after
    // this point, so this specific leak has no visible effect today --
    // reset anyway, on the same "don't leave FlGroup.current() wrong"
    // principle CLAUDE.md calls out repeatedly, so it doesn't bite a
    // future addition to this function.
    FlGroup.current(shelf_);
    browser_.onSelect = (n) { selectFromBrowser(n); };
    browser_.onOpen = (n) { openNode(n); };
    shelf_.resizable(browser_);

    // `overlayCb`/`okCb`/`liveModeCb` are `widget_panel.fl`'s own
    // module-level `void delegate(Widget)` hooks (see that file's
    // "gui_main.d integration surface" comment, and its own comment
    // directly above the three stub Functions for exactly why a real
    // implementation has to live here rather than in the .fl file
    // itself -- a callback-shaped Function's own body is unreachable
    // dead code in any file with no `main()`-shaped root Function,
    // which every panel file is) -- assigned *before* `make_widget_
    // panel()` runs, since `overlayButton.callback(overlayCb)`/
    // `wLiveMode.callback(liveModeCb)` inside it capture each
    // delegate's value at that statement, not a live reference to this
    // variable.
    //
    // `overlayCb` mirrors `WidgetPanelDialog.onOverlayButtonPressed()`'s
    // own old body: flip the button's own label in lockstep, then apply
    // the toggle project-wide via `toggleOverlays()`.
    overlayCb = (w) {
        toggleOverlays();
        overlayButton.label(overlaysHidden_ ? "Show &Overlays" : "Hide &Overlays");
        overlayButton.redraw();
    };
    // Every field in this dialog already applies its own edit live, as
    // you type -- FLTK's own "apply everything on OK" sweep
    // (`widget_panel_callbacks.cxx`'s `set_cb()`) has nothing left to
    // do here, so Close really is just Close.
    okCb = (w) { thePanel.hide(); };

    // Live Resize -- ported from FLTK's own `live_mode_cb()`
    // (`widget_panel_callbacks.cxx`): clones the single selected
    // widget-tree node into a standalone, genuinely resizable duplicate
    // window, letting the user verify `resizable()`/layout settings
    // behave the way the real generated app would (the design canvas
    // itself deliberately never reflows children on resize during
    // editing -- see the "&Layout/Synchronized Resize" placeholder's
    // own comment above). Matches FLTK's exact wrapper-window
    // construction (a small non-resizing "Exit Live Resize" bar pinned
    // to the bottom-left via a hidden resizable dummy `Box`, green
    // `flatBox` background, `setModal()`) and its `o is null` == "force
    // leave" convention, reused here for the wrapper window's own close
    // callback and its "Exit Live Resize" button, matching FLTK's
    // identical `live_mode_cb(nullptr, nullptr)` via `leave_live_mode_
    // cb()`. See `fluid.instantiate.instantiateStandalone()`'s own doc
    // comment for the one real structural adaptation from FLTK
    // (a single shared function instead of a virtual method overridden
    // per node kind) and its one genuinely-replicated per-kind special
    // case (re-selecting a cloned `Tabs`' active page below, using the
    // active canvas's own live tree to read the *original* widget's
    // current runtime state).
    liveModeCb = (o) {
        auto cv = activeCanvas();
        Node[] selected = cv !is null ? cv.selected() : null;
        auto wn = selected.length == 1 ? cast(WidgetNode) selected[0] : null;
        if (wn is null)
        {
            wLiveMode.value(0);
            return;
        }

        if (o is null)
        {
            o = wLiveMode;
            wLiveMode.value(0);
        }

        auto toggle = cast(Button) o;
        if (toggle !is null && toggle.value())
        {
            // Re-entrancy guard: `liveResizeWindow_` is module state, and
            // nothing else here stops a second "enter" from running while
            // one is already active and overwriting the only reference to
            // it (a leaked X11 window, silently). The wrapper window is
            // modal, which should already make `wLiveMode` itself
            // unclickable while active -- this is a belt-and-suspenders
            // backstop in case that enforcement ever has a gap, not a
            // path expected to be reachable normally.
            if (liveResizeWindow_ !is null)
                return;

            // A failure anywhere in `enterLiveResize()` (an unexpected
            // exception from a widget constructor, `applyProperties()`'s
            // image loading, or similar) would otherwise leave `wLiveMode`
            // stuck showing "pressed" with nothing actually open and no
            // trace of why -- caught here so a failure is recoverable
            // (button resets, nothing leaked) and logged instead of
            // vanishing silently.
            try
            {
                enterLiveResize(cv, wn);
                if (liveResizeWindow_ is null)
                    wLiveMode.value(0);
            }
            catch (Exception e)
            {
                stderr.writefln("Live Resize: failed to enter (%s)", e.msg);
                if (liveResizeWindow_ !is null)
                {
                    liveResizeWindow_.hide();
                    fl.core.deleteWidget(liveResizeWindow_);
                    liveResizeWindow_ = null;
                }
                wLiveMode.value(0);
            }
        }
        else
        {
            if (liveResizeWindow_ !is null)
            {
                liveResizeWindow_.hide();
                fl.core.deleteWidget(liveResizeWindow_);
                liveResizeWindow_ = null;
            }
        }
    };

    // Every other live edit in this app takes
    // effect in its target immediately as you type -- a node's
    // `comment` (bold class name/plain instance name row-format work,
    // above) has its own visible target too, the project tree's own
    // row (green comment sub-line, taller row, `NodeBrowserItem` --
    // see that class's own top comment), which needs telling that
    // `browser_`'s cached row geometry might be stale, since only
    // structural changes (add/delete/load) call `browser_.build()`
    // anywhere in this file. `browser_.recalcTree()` (public --
    // see `fl.tree.Tree`'s own doc comment) + `redraw()`
    // is the same repaint-without-rebuilding shape `Tree`'s own property
    // setters use internally, applied here to data
    // the tree doesn't own itself.
    widgetPanelOnEdited = () {
        if (auto cv = activeCanvas()) cv.redraw();
        browser_.recalcTree();
        browser_.redraw();
    };
    widgetPanelOnBeforeEdit = () { checkpoint(); };
    widgetPanelOnBeforeTextEdit = (Object key) { checkpointTextEdit(key); };
    widgetPanelOnOpenExternalEditor = (n) { openExternalEditor(n); };

    thePanel = make_widget_panel();
    // Threads `widgetPanelOnBeforeEdit`/`widgetPanelOnEdited` through
    // every property-editing widget under `tabsWizard` -- every tab
    // page (`widgetTabs`, both Grid sub-panels included, plus
    // `commentTabs`/`funcTabs`/`classTabs`/`codeTabs`/`codeblockTabs`/
    // `declTabs`/`declblockTabs`/`dataTabs`), not just `widgetTabs`
    // alone: `wireEditHooks()`'s own generic model->live-widget re-sync
    // only ever touches `selectedWidgetNodes()`, so it's already a
    // harmless no-op for a Function/Comment/Code/... field's own
    // callback -- the checkpoint/dirty-flag/tree-refresh half of
    // `onBeforeEdit`/`onEdited` is what those node kinds were actually
    // missing (see `widget_panel.fl`'s `codeText`/`codeblockEnd`
    // callback comments -- "Fluid.proj.set_modflag(1);
    // redraw_browser();" -- real via this). Not
    // `thePanel` itself, since the bottom bar's own
    // `wLiveMode`/`overlayButton`/the Close `ReturnButton` are
    // `tabsWizard`'s own siblings under `thePanel`, not its children --
    // see `widget_panel.fl`'s own `wireEditHooks()` doc comment for the
    // mechanism and its one accepted imprecision (a cancelled Browse
    // dialog still pushes an undo checkpoint).
    wireEditHooks(tabsWizard);
    ExternalCodeEditor.setUpdateTimerCallback(() { externalEditorTimer(); });

    // Must be assigned *before* `makeWidgetBin()` runs: `Callback`/`void delegate(Widget)` is
    // a plain value type in D, so `o.callback(binButtonCb)` (executed
    // inside `makeWidgetBin()`, which every button's own `setup {}`
    // property runs during construction) copies whatever `binButtonCb`
    // *currently holds* into that button's own `callback_` field --
    // permanently. If this assignment ran *after*
    // `makeWidgetBin()` instead, every
    // button's `callback_` would capture `binButtonCb`'s un-initialized
    // `.init` value, `null`, and a later `binButtonCb = (w) { ... };`
    // line would only ever update the free-standing module-level variable,
    // never any already-copied `callback_` field (confirmed with a
    // minimal standalone repro: a class storing a delegate value copied
    // from a module-level var, reassigned after the copy, has the class's
    // own copy stay null). A click on any widget-bin button would then
    // silently fall through to `Widget.defaultCallback()` (push onto
    // the read queue) instead of ever reaching `addWidget()`/
    // `addNode()` -- invisible for the *widget* palette specifically
    // because dragging a button onto the canvas is a separate code path
    // that never touches `callback_` at all (`BinButton.handle()`'s own
    // `Event.drag` case calls `fl.copy()`/`fl.dnd()` directly), but fatal for the Code group, which has no
    // canvas/drag path at all.
    binButtonCb = (w) {
        auto btn = cast(BinButton) w;
        if (btn is null) return;
        // "Window" needs its own dedicated placement rule (a function
        // ancestor, FLTK's own "Please select a function" message
        // otherwise) rather than `addWidget()`'s generic one -- see
        // `createWindowNode()`'s own doc comment. Every other bin
        // button still goes through the shared `addWidget()` path.
        if (btn.typeName() == "Window") createWindowNode();
        else addWidget(btn.typeName());
    };
    // The palette's "Code" group (Function/Class/comment/Code/
    // CodeBlock/widget_class/decl/declblock/data) reuses `BinButton`
    // purely for its `typeName()` storage/tooltip -- these buttons are
    // never dragged onto the canvas (there's no live widget to drop),
    // matching FLTK's own real split: the widget-tree buttons use
    // `Bin_Button`'s click-or-drag handling, but the Code group's own
    // buttons use a plain click-only callback (`type_make_cb`) instead.
    // A stray drag of one of these is harmless -- `dropWidget()` ->
    // `insertWidget()` silently no-ops on a non-`WidgetNode` type.
    codeButtonCb = (w) {
        auto btn = cast(BinButton) w;
        if (btn !is null) addNode(btn.typeName());
    };
    makeWidgetBin();

    // The Code View panel's own "Reveal" button (text position -> Node)
    // reports back here -- matches FLTK's `cb_Reveal()` (`select_
    // only(node); reveal_in_browser(node); if (double click) node->
    // open();`). `selectFromBrowser()` already covers select_only()'s
    // "deselect everything else, select just this one" plus reveal_in_
    // browser()'s "make sure it's visible" (`NodeBrowser.syncSelection()`
    // reveals and highlights, per its own doc comment) in one call, the
    // same pair of effects a plain tree-browser click already produces
    // for any other node.
    cvOnReveal = (n, doubleClick) {
        selectFromBrowser([n]);
        if (doubleClick)
            openNode(n);
    };

    makeShellRunWindow();
    wireShellProcess();

    shellCommandList = new ShellCommandList();
    shellCommandList.readFromPrefs(appPrefs);
    fluid.shell_command.macroProvider = () => currentShellMacros();
    fluid.shell_command.showShellRunWindowHook = () { showShellRunWindow(); };
    onProjectShellCommandChanged = () { dirty_ = true; updateShelfTitle(); };
    // Fires on every shell-command add/duplicate/remove/import and
    // every field edit (`shell_settings.d`'s own apply functions) --
    // `ToolStore.user` entries need re-persisting to `appPrefs` on any
    // of those (there's no separate "only if it's actually a user-
    // stored field" signal the way `onProjectShellCommandChanged`
    // has), and the `&Shell` menu needs rebuilding on all of them too
    // (a label/shortcut/condition edit changes what the menu shows).
    onShellListChanged = () {
        shellCommandList.writeToPrefs(appPrefs);
        rebuildShellMenu();
    };
    rebuildShellMenu(); // adds &Shell/&Customize... plus any active user-stored commands

    // Added last, after &Shell above: FLTK's own top-level order is
    // File, Edit, New, Layout, Shell, Help, and this call is the first
    // `.add()` under the "&Help" path -- moved from right after &Layout
    // (where it landed 5th, before &Shell) to land 6th/last instead,
    // matching FLTK.
    //
    // `&Rapid development with FLUID...`/`&FLTK Programmers Manual...`
    // both call `showHelp()`, ported
    // from `Application::show_help()` (`Fluid.cxx`); see that function's
    // own doc comment for what it actually shows. Order/names/divider
    // match `Menu.cxx`'s real `main_menu[]` `&Help` group exactly.
    menu.add("&Help/&Rapid development with FLUID...", 0, (w) { showHelp("fluid.html"); });
    menu.add("&Help/&FLTK Programmers Manual...", 0, (w) { showHelp("index.html"); }, menuDivider);
    menu.add("&Help/&About", 0, (w) { showAboutPanel(); });

    shelf_.end();

    // Every window needs a real starting position, not the plain,
    // unpositioned default (`shelf_`/`panel_` would otherwise both
    // land at literal screen `(0,0)` -- `fl.window.Window`'s own
    // 2-arg ctor forwards to `this(0, 0, w, h, label)`, not "let the
    // window manager decide" -- and `widgetBinPanel` would sit wherever
    // `function_panel.fl`'s own leftover, arbitrary `xywh` happens to
    // be), or the user would have to manually drag every window apart on every
    // single launch. FLTK never has this problem: `Application::
    // position_window()`/`save_position()` (`Fluid.cxx`) explicitly
    // positions `main_window`/`widgetbin_panel` from saved preferences
    // (falling back to hardcoded, deliberately non-overlapping defaults
    // -- `(10,30)` and `(320,30)` -- on a first run), and persists
    // whatever the user last dragged them to across sessions. Ported
    // here as `positionWindow()`/`saveWindowPosition()` (below),
    // against `fluid.app_prefs.appPrefs` the same way every other
    // persisted UI setting in this app already works. Defaults chosen
    // to tile the same way FLTK's own do, just resized for this
    // port's own `shelf_`/`widgetBinPanel` dimensions (280x400/600x102
    // here vs FLTK's 300x525/600x102) rather than copying FLTK's
    // literal pixel values verbatim.
    bool shelfVisible = positionWindow(shelf_, "main_window_pos", true, 10, 30);
    // `persistVisibility: false` -- always opens, position only is
    // remembered. See `positionWindow()`'s own doc comment.
    bool binVisible = positionWindow(widgetBinPanel, "widgetbin_pos", true, SHELF_W + 20, 30, false);
    // `thePanel` (Widget Properties) is the one FLTK window that is
    // genuinely never shown at startup at all -- it's lazily created
    // and shown for the first time by `open_panel()`, called only once
    // a node is actually created or double-clicked (this port's own
    // `openNode()`, which already exists and is already the only other
    // caller of `thePanel.show()`). Matches FLTK exactly: give it a
    // sensible one-time default position here (chosen to avoid both
    // `shelf_`'s and `widgetBinPanel`'s own *default* rectangles by
    // construction, below the widget bin), but do NOT `.show()` it, and
    // do NOT persist its position across sessions -- FLTK's own
    // `Application::quit()` never calls `save_position()` for `the_panel`
    // either, only for `main_window`/`widgetbin_panel`/`codeview_panel`.
    thePanel.position(SHELF_W + 20, 150);
    forceRealPosition(thePanel);

    if (shelfVisible) shelf_.show();
    if (binVisible) widgetBinPanel.show();

    // "Open Previous File on Startup" (`settings_panel.fl`'s General
    // tab, `appPrefs` key `open_previous_file`) -- matches FLTK's
    // own startup check exactly: `Fluid.cxx`'s `if (!c && openlast_
    // button->value() && history.abspath[0][0] && ...)`. Read directly
    // from `appPrefs` rather than a live Settings-dialog widget, same
    // reasoning as `positionWindow()`'s own `prev_window_pos` read
    // just above -- the Settings panel doesn't exist yet this early.
    int openPrevious;
    appPrefs.get("open_previous_file", openPrevious, 0);

    if (args.length >= 1 && args[0].length)
        loadProject(args[0]);
    else if (openPrevious && history_.abspath[0].length)
        loadProject(history_.abspath[0]);
    else
        // Matches FLTK's own startup state exactly (`Fluid.cxx`'s
        // `main()`, no file argument): `proj` starts out already
        // default-constructed to an empty project (`Project()`'s own
        // constructor does nothing) and `proj.set_modflag(0)` runs
        // unconditionally near the end of `main()`, which is what
        // actually paints the "Untitled.fl" title -- there's no
        // separate "uninitialized, no project yet" state to fall into
        // at all in FLTK. `newProject()` reaches that same empty-
        // project/"Untitled" state here; calling it directly (rather
        // than leaving every project-related field at its plain `.init`
        // default) is what makes a brand-new window/function creatable
        // immediately on first launch, without first requiring an
        // explicit `&File/&New` click to "initialize" anything.
        newProject();

    fl.run();
}

/// The "enter Live Resize" half of `liveModeCb`'s own assignment above
/// (`runEditor()`) -- split out so it can be wrapped in a single
/// `try`/`catch` there without the exception-safety concern spreading
/// into the rest of `runEditor()`'s own init sequence. Builds the
/// standalone duplicate and its wrapper window; assigns `liveResizeWindow_`
/// only once everything else succeeded (an exception partway through
/// propagates to the caller instead of leaving it half-built).
private void enterLiveResize(ProjectCanvas cv, WidgetNode wn)
{
    LiveTree standalone;
    auto liveWidget = instantiateStandalone(wn, standalone, projectDir_());
    if (liveWidget is null)
        return; // caller resets wLiveMode when liveResizeWindow_ is still null

    // Re-select a cloned `Tabs`' active page to match whatever page is
    // actually showing on the design canvas right now -- FLTK's own
    // `Tabs_Node::enter_live_mode()` special case; see `instantiateStandalone()`'s
    // own doc comment for why this lives here instead of there.
    if (auto origTabs = cast(Tabs) cv.liveTree().widgetOf.get(wn, null))
    {
        if (auto cloneTabs = cast(Tabs) liveWidget)
        {
            int idx = origTabs.find(origTabs.value());
            if (idx >= 0 && idx < cloneTabs.children())
                cloneTabs.value(cloneTabs.child(idx));
        }
    }

    int w = liveWidget.w();
    int h = liveWidget.h();
    auto wrapper = new DoubleWindow(w + 20, h + 55, "Fluid Live Resize");
    wrapper.box(Boxtype.flatBox);
    wrapper.color(green);
    auto rsz = new FlGroup(0, h + 20, 130, 35);
    rsz.box(Boxtype.noBox);
    auto rszDummy = new Box(110, h + 20, 1, 25);
    rszDummy.box(Boxtype.noBox);
    rsz.resizable(rszDummy);
    auto exitBtn = new Button(10, h + 20, 100, 25, "Exit Live Resize");
    exitBtn.labelsize(12);
    exitBtn.callback((raw_) { liveModeCb(null); });
    rsz.end();
    wrapper.add(liveWidget);
    liveWidget.position(10, 10);
    wrapper.resizable(liveWidget);
    wrapper.setModal(); // block all other UI, matching FLTK
    wrapper.callback((raw_) { liveModeCb(null); });

    if (auto winNode = cast(WindowNode) wn)
    {
        int mw = winNode.hasSizeRange ? winNode.sizeRangeMinW : 0; if (mw > 0) mw += 20;
        int mh = winNode.hasSizeRange ? winNode.sizeRangeMinH : 0; if (mh > 0) mh += 55;
        int MW = winNode.hasSizeRange ? winNode.sizeRangeMaxW : 0; if (MW > 0) MW += 20;
        int MH = winNode.hasSizeRange ? winNode.sizeRangeMaxH : 0; if (MH > 2) MH += 55;
        if (mw || mh || MW || MH)
            wrapper.sizeRange(mw, mh, MW, MH);
    }

    wrapper.end();

    // Assigned only now, once construction fully succeeded -- an
    // exception anywhere above propagates to `liveModeCb`'s own
    // `catch` with `liveResizeWindow_` still `null`, so its cleanup
    // branch has nothing dangling to tear down.
    liveResizeWindow_ = wrapper;
    liveResizeWindow_.show();
    liveWidget.show();
}

/// Positions `w` from a saved preference sub-group under `appPrefs`
/// (falling back to `(defaultX, defaultY)` if nothing was saved yet)
/// and returns whether it should be shown -- this port's counterpart to
/// FLTK's `Application::position_window()` (`Fluid.cxx`).
///
/// "Remember Window Positions" (`settings_panel.
/// fl`'s General tab, `appPrefs` key `prev_window_pos`, default on)
/// gates the `x`/`y` restore below, matching FLTK's own `if
/// (prevpos_button->value())` guard around the same two `pos.get()`
/// calls -- when off, `w` keeps whatever `(defaultX, defaultY)` the
/// caller already passed instead of ever reading the saved position.
/// Reads `appPrefs` directly rather than a live Settings-dialog widget
/// the way FLTK's own `prevpos_button->value()` does: this port's
/// Settings panel is constructed lazily on first open (unlike
/// FLTK, which builds it, hidden, during startup specifically so
/// this preference is available this early), so there may be no widget
/// to read at all the first time `positionWindow()` runs. `appPrefs`
/// is the single shared source of truth every other General-tab toggle
/// already persists through and reads back from elsewhere (`show
/// Positioning Guides` is the one exception, reading live canvas state
/// instead, precisely because a canvas already exists to read from by
/// the time that one matters).
///
/// `persistVisibility`: whether a saved "visible" flag should ever
/// suppress showing `w` at startup at all. The widget bin passes
/// `false`: unlike `shelf_`, which persists visibility the same way
/// FLTK's own `position_window()` does, the widget bin should always
/// open by default -- position remembered, but not whether it was
/// left open or closed. The saved "visible" key (if any -- `saveWindowPosition()`
/// still writes one, now simply unread) is ignored entirely and this
/// always returns `true`.
private bool positionWindow(Window w, string prefsGroup, bool defaultVisible, int defaultX, int defaultY, bool persistVisibility = true)
{
    auto pos = new Preferences(appPrefs, prefsGroup);
    int rememberPositions;
    appPrefs.get("prev_window_pos", rememberPositions, 1);
    if (rememberPositions)
    {
        int x = defaultX, y = defaultY;
        pos.get("x", x, defaultX);
        pos.get("y", y, defaultY);
        sanitizePosition(x, y, w.w(), w.h(), defaultX, defaultY);
        w.position(x, y);
        forceRealPosition(w);
    }
    if (!persistVisibility) return true;
    int visible = defaultVisible ? 1 : 0;
    pos.get("visible", visible, visible);
    return visible != 0;
}

/// Defensive check on a position read back from a saved preference:
/// a stale save from a since-changed
/// monitor configuration, a hand-edited prefs file, or any future bug
/// anywhere would otherwise place a window
/// somewhere the user can never see or reach again, with no way back
/// short of manually editing or deleting the prefs file by hand.
///
/// If the window rectangle `(x, y, w, h)` wouldn't overlap the real
/// virtual screen bounds (`fl.core.screenXYWH()`'s no-arg overload --
/// the whole display, every monitor, not just the primary one) by at
/// least `minVisibleMargin` pixels in both dimensions, resets `x`/`y`
/// to `(defaultX, defaultY)` instead of trusting the saved value
/// blindly. `int` has no NaN of its own, but the same underlying worry --
/// "what if this value is garbage" -- applies just as well to a huge,
/// negative, or otherwise out-of-range integer.
private enum minVisibleMargin = 20;

private void sanitizePosition(ref int x, ref int y, int w, int h, int defaultX, int defaultY)
{
    int scrX, scrY, scrW, scrH;
    fl.screenXYWH(scrX, scrY, scrW, scrH);

    bool xOnScreen = x + w > scrX + minVisibleMargin && x < scrX + scrW - minVisibleMargin;
    bool yOnScreen = y + h > scrY + minVisibleMargin && y < scrY + scrH - minVisibleMargin;

    if (!xOnScreen || !yOnScreen)
    {
        x = defaultX;
        y = defaultY;
    }
}

/// Why "the window doesn't reopen where it
/// was left" needs more than a preferences-flush fix alone: a window
/// manager is free to ignore an app's requested `x`/`y` entirely unless
/// the app explicitly asks it not to, via the ICCCM `USPosition` hint
/// in `WM_NORMAL_HINTS` -- `fl.platform_x11.sendSizeHints()` only sends
/// that hint when `win.forcePosition()` is true (see that function's
/// own doc comment: a window manager like fvwm is
/// otherwise
/// always free to auto-place the window whichever open spot it likes
/// instead). `Window.resize()` sets that flag automatically, but only
/// `if (resizeFromProgram && shown())` -- i.e. only for a move that
/// happens *while the window is already visible* (a real user drag).
/// Every window this module positions before its first `.show()` call
/// (deliberately, to avoid a visible jump into place) therefore never
/// took this path at all, so `forcePosition()` stayed `false` and fvwm
/// (or any other WM with its own placement policy) was free to ignore
/// the restored position on every single launch, silently. Setting the
/// flag directly, matching what a real drag would have set it to
/// anyway, is the actual fix -- not a workaround.
private void forceRealPosition(Window w)
{
    w.forcePosition(true);
}

/// This port's counterpart to FLTK's `Application::save_position()`
/// -- called from `doQuit()` for every window `positionWindow()` above
/// restores, matching FLTK's own `Application::quit()` (`main_
/// window`/`widgetbin_panel` only -- `the_panel` is deliberately not
/// included here either, see `positionWindow()`'s own call site
/// comment). `saveVisibility: false` matches `positionWindow()`'s own
/// `persistVisibility: false` for the widget bin -- no point writing a
/// "visible" key nothing ever reads back; a stale-looking `visible:0`
/// sitting in the prefs file for a window that in fact always opens
/// would just be confusing to find later.
private void saveWindowPosition(Window w, string prefsGroup, bool saveVisibility = true)
{
    auto pos = new Preferences(appPrefs, prefsGroup);
    pos.set("x", w.x());
    pos.set("y", w.y());
    if (saveVisibility)
        pos.set("visible", (w.shown() && w.visible()) ? 1 : 0);
    // `set()` only marks the in-memory tree dirty -- without an
    // explicit `flush()`, nothing
    // here ever actually reaches disk (see `fl.preferences.Preferences`'s
    // own top comment: "callers that actually need the data saved must
    // call `.flush()` explicitly" -- there is no implicit save-on-exit
    // to fall back on, regardless of how the process ends). This
    // function's entire *purpose* is "the data must actually be saved,"
    // so this omission made it a complete no-op end to end despite
    // compiling and running cleanly.
    pos.flush();
}

/// Ported from `Application::new_project()` (`Fluid.cxx`), which just
/// calls `proj.reset()` -- `Project::reset()` (`Project.cxx`) deletes
/// every node and nothing else; it never inserts so much as a `Function`,
/// let alone a `Window`. A genuinely empty, never-touched FLTK Fluid
/// project has *zero* top-level nodes, full stop, and the title bar
/// reads "Untitled.fl" purely because `Project::set_modflag()`'s own
/// title-string builder falls back to that literal whenever
/// `proj_filename` is null (`if (!proj_filename) basename =
/// "Untitled.fl";`) -- nothing more than an empty-filename display rule.
///
/// Must NOT auto-insert a `Function {}
/// {}` wrapping a single `Window`, even though `code_writer.d`
/// needs *something* to generate against -- that's never FLTK's
/// behavior (confirmed above), and doing so would break the state machine: a fresh/New project would start with a Window
/// node that couldn't be deleted cleanly (deleting it would leave `canvas_`/
/// `projectRoot_` unable to reconcile with `openLoadedProject()`'s own
/// "always a real root `WindowNode`" assumption), and deleting the
/// wrapping Function would cascade away the Window with it. `code_writer.d` generating no `main()` for a
/// truly empty project is *correct*, not a gap -- it matches what real
/// Fluid would also produce from an empty `.fl` file. The empty-tree
/// state itself is fully supported:
/// `loadProject()` already has a real, exercised "no top-level window
/// at all" path (`findRootWindow()` returning `null`, see that
/// function's own comment) that leaves `canvas_`/`projectRoot_` both
/// `null` and shows the node browser/properties panel with nothing
/// loaded -- this function reaches that exact same state directly,
/// instead of manufacturing fake content to avoid it.
private void newProject()
{
    closeProject();
    projectRoots_ = [];
    projectI18n_ = I18nSettings.init;
    projectDubHeader_ = false;
    projectSettings_ = ProjectSettings.init;
    updateMergebackMenu();
    codeFileName_ = "";
    projectPath_ = null;

    browser_.build(projectRoots_);
    widgetPanelLoad([], LiveTree.init, projectDir_());

    undoStack_ = [];
    redoStack_ = [];
    dirty_ = false;
    updateShelfTitle();

    codeviewAutoRefresh();

    // A brand-new project has no `ToolStore.project` shell commands of
    // its own -- drop whatever the *previous* project's own entries
    // were (matches `projectI18n_`'s own reset just above; `ToolStore.
    // user` entries are untouched, they're not this project's data).
    shellCommandList.clear(ToolStore.project);
    rebuildShellMenu();
}

/// `&File/New from &Template...` -- shows `template_panel.fl`'s own
/// dialog (`fluid/panels/template_panel.d`), modally (blocks on the
/// window's own `modal` flag + `fl.wait()`, matching FLTK's shape
/// for a dialog whose result the caller needs before continuing), then
/// loads whichever template the user picked as a fresh, not-yet-saved
/// project (`loadProject(path, asTemplate: true)` -- see that
/// parameter's own doc comment for why `projectPath_` deliberately
/// stays unset rather than pointing at the template file itself).
///
/// `templateClear()` before `templateLoad()` matters on every call, not
/// just the first: `templateLoad()` only ever *adds* rows, so without
/// clearing first, opening this dialog a second time in the same
/// session would duplicate every entry already listed.
///
/// Scope note: the dialog's own "Template Name:"/"Instance Name:"
/// fields are read here only to detect a genuine cancel (FLTK's
/// own `template_panel.fl` doesn't consume them itself either -- that
/// belongs to a real "instantiate this template under a chosen name"
/// step, which needs project-copying logic this port doesn't have yet;
/// tracked as a real follow-up, not silently dropped). For now, the
/// user picks the on-disk destination for their new project themselves
/// via the ordinary `&File/&Save As...` afterward.
private void newFromTemplate()
{
    // `makeTemplatePanel()` must run first, not last -- `templateClear()`/
    // `templateLoad()` below both touch `templateBrowser`, which is
    // `null` until a panel has actually been constructed at least once
    // (this dialog is shared with `saveAsTemplate()` below, which would
    // otherwise crash on its first-ever call in a session the same way
    // this one would).
    makeTemplatePanel();
    // Explicit, not left at `template_panel.fl`'s own default "Save"
    // label -- this dialog is shared with `saveAsTemplate()` below, so
    // relying on the `.fl` source's own default would show "Save"
    // instead of "New" here.
    templateSubmit.label("New");
    templateClear();
    templateLoad();
    templatePanel.show();
    while (templatePanel.shown())
        fl.wait();

    if (templateName.value().length == 0)
        return; // cancelled

    string path = templateSelectedPath();
    if (path.length == 0)
        return; // nothing actually selected

    loadProject(path, true);
}

/// `&File/Save As &Template...` -- ported from FLTK's
/// `fluid::app::save_template()` (`fluid/app/templates.cxx`). Reuses
/// `newFromTemplate()`'s own dialog in "save" mode: an extra "New
/// Template" row prepended to the list (no `data()`, matching
/// FLTK's own `template_browser->add("New Template")` and this
/// port's now-real per-row `Browser.data()` use in `template_panel.fl`
/// -- see that file's own "Correction" note for why this needed fixing
/// first), and `templateName` (shown by default already) is where the
/// save name comes from -- `templateInstance`/`templateDelete`/
/// `templateSubmit`'s label all already default to what save mode
/// wants from `makeTemplatePanel()`'s own construction (`templateName`
/// shown+empty, `templateInstance` hidden, `templateSubmit` labeled
/// "Save"), so unlike FLTK's own explicit `show()`/`hide()`/
/// `label()` calls, nothing extra needs setting here.
///
/// Sanitizes the name (whitespace -> underscore, matching FLTK's
/// own `fl_ascii_isspace()` sweep via `std.ascii.isWhite`), resolves
/// the same templates directory `templateLoad()` reads from
/// (`appPrefs.getUserdataPath()` + "templates"), confirms before
/// overwriting an existing file, and writes the current project's
/// `.fl` text via the same `ProjectWriter` every other save path uses
/// -- deliberately a raw write, not `writeProjectTo()` (that one also
/// mutates `projectPath_`/`dirty_`/recent-files history, none of which
/// a *template* save should touch; this is a snapshot, not a "save
/// as").
///
/// Also captures a PNG preview alongside it, matching FLTK's own
/// `#if HAVE_LIBPNG && HAVE_LIBZ` screenshot block -- both
/// `fl.core.captureWindow()` and `fl.png_image.writePng()` are
/// already real, so this needed no new infrastructure. Matches
/// FLTK's own search for "the first window" (`Node::next`'s own
/// depth-first walk) via `findAllWindowRoots(projectRoots_)[0]`,
/// picking the same one
/// FLTK's own search would even when a project has several windows
/// open at once. A failed screenshot (that window not
/// open/shown, capture error) is silently skipped, matching FLTK's
/// own `if (!t) return;`/`if (pixels == nullptr) return;` early-outs --
/// the `.fl` file is already safely on disk by that point either way.
private void saveAsTemplate()
{
    import std.ascii : isWhite;
    import std.path : buildPath, setExtension;
    import std.file : exists;
    import std.format : format;
    import fluid.path_util : ensureFlExtension;

    if (projectRoots_.length == 0) return;
    // See `writeProjectTo()`'s matching guard / `raw_cpp_guard.d`'s own
    // module doc comment -- the same lossy-writer risk applies to a
    // template save, just to a templates-directory copy instead of the
    // original file.
    if (looksLikeRawCpp(projectRoots_))
    {
        fl.ask.alert("This project contains raw FLTK C++, not this project's "
            ~ "own D-embedded `.fl` dialect. Saving it as a template would "
            ~ "silently lose content -- not saved.");
        return;
    }

    makeTemplatePanel();
    // Explicit, not left at `template_panel.fl`'s own default -- see
    // `newFromTemplate()`'s matching comment above (its own default
    // "Save" label was wrong for *that* mode; this one is already
    // correct by coincidence, but setting it explicitly here too means
    // that stops being something either mode is silently relying on).
    templateSubmit.label("Save");
    templateClear();
    templateBrowser.add("New Template");
    templateLoad();
    templatePanel.show();
    while (templatePanel.shown())
        fl.wait();

    string rawName = templateName.value();
    if (rawName.length == 0)
        return; // cancelled

    char[] saveNameBuf = rawName.dup;
    foreach (ref c; saveNameBuf)
        if (isWhite(c)) c = '_';
    string saveName = saveNameBuf.idup;

    string templatesDir;
    appPrefs.getUserdataPath(templatesDir);
    templatesDir = buildPath(templatesDir, "templates");

    // Not `setExtension("fl")`: that *replaces* an existing extension, so a
    // template named `v1.2` would be written as `v1.fl`.
    string flPath = ensureFlExtension(buildPath(templatesDir, saveName));

    if (exists(flPath))
    {
        if (fl.ask.choice(format("The template \"%s\" already exists.\nDo you want to replace it?", rawName),
                "Cancel", "Replace", null) == 0)
            return;
    }

    auto text = new ProjectWriter().generate(projectRoots_, projectI18n_, shellCommandList.list, "", layoutList,
        false, projectDubHeader_, projectSettings_);
    try
        write(flPath, text);
    catch (Exception e)
    {
        stderr.writefln("fluid: could not write %s: %s", flPath, e.msg);
        fl.message(format("Could not write %s:\n%s", flPath, e.msg));
        return;
    }

    auto firstWindows = findAllWindowRoots(projectRoots_);
    if (firstWindows.length == 0) return;
    auto cv = canvases_.get(firstWindows[0], null);
    if (cv is null || !cv.shown()) return;
    auto screenshot = fl.core.captureWindow(cv, 0, 0, cv.w(), cv.h());
    if (screenshot is null) return;
    fl.png_image.writePng(flPath.setExtension("png"), screenshot);
}

private void openProject()
{
    string path = fileChooser("Open .fl file", "*.fl", projectPath_);
    if (path.length) loadProject(path);
}

/// `asTemplate = true` (used by `newFromTemplate()` below) loads
/// `path`'s widget tree the same way but leaves `projectPath_` unset --
/// the point of "New from Template" is a fresh, not-yet-saved project
/// seeded from the template's content, not an in-place edit of the
/// template file itself; a plain `loadProject()` call would silently
/// let "Save" overwrite the user's own template library.
private void loadProject(string path, bool asTemplate = false)
{
    import std.format : format;

    string source;
    try
        source = readText(path);
    catch (Exception e)
    {
        stderr.writefln("fluid: could not read %s: %s", path, e.msg);
        fl.message(format("Could not read %s:\n%s", path, e.msg));
        return;
    }

    Node[] roots;
    I18nSettings i18n;
    ShellCommand[] shellCommands;
    string codeFileName;
    bool dubHeader;
    ProjectSettings settings;
    LayoutSuite[] layoutSuites;
    string layoutCurrentSuite;
    int layoutCurrentPreset;
    bool hasSnap;
    try
    {
        auto reader = new Reader(source);
        roots = reader.readProject();
        i18n = reader.i18n;
        shellCommands = reader.shellCommands;
        codeFileName = reader.codeFileName;
        dubHeader = reader.dubHeader;
        settings = reader.settings;
        layoutSuites = reader.layoutSuites;
        layoutCurrentSuite = reader.layoutCurrentSuite;
        layoutCurrentPreset = reader.layoutCurrentPreset;
        hasSnap = reader.hasSnap;
    }
    catch (Exception e)
    {
        stderr.writefln("fluid: could not parse %s: %s", path, e.msg);
        fl.message(format("Could not parse %s:\n%s", path, e.msg));
        return;
    }

    auto windowRoots = findAllWindowRoots(roots);
    if (windowRoots.length == 0)
    {
        // A real, expected case, not an error: this project's own
        // samples/examples/fluid-callback.fl has no WindowNode at all
        // (its window is built entirely from `code {}` text at runtime,
        // e.g. `super(x,y,l);` inside a hand-written constructor) --
        // structurally outside what this editor can render at all (it
        // only instantiates a declarative widget tree, never executes
        // arbitrary D snippets). Real FLTK's own Fluid still shows the
        // *project tree* in this
        // exact case (every Function/class/decl/comment, just no canvas
        // editor window since there's nothing to render there), so this
        // falls through to the
        // normal load path below with an empty `windowRoots` (already
        // safe -- `openLoadedProject()`'s own `foreach (wn; roots)` is a
        // no-op for zero windows, and its `browser_.build(projectRoots_)`
        // call already uses the *full* tree, not `windowRoots`), matching
        // FLTK's own silence here with just a
        // quiet stderr line.
        stderr.writefln("fluid: %s has no top-level window -- no canvas editor window to show, loading the project tree only", path);
    }

    closeProject();
    projectRoots_ = roots;
    projectPath_ = asTemplate ? null : path;
    projectI18n_ = i18n;
    projectDubHeader_ = dubHeader;
    projectSettings_ = settings;
    updateMergebackMenu();
    codeFileName_ = codeFileName;
    openLoadedProject(windowRoots);
    undoStack_ = [];
    redoStack_ = [];
    dirty_ = false;
    updateShelfTitle();

    // Swap in this project's own `ToolStore.project` shell commands --
    // matches FLTK's own `Fd_Shell_Command_List::read(Project_
    // Reader*)`'s `clear(Tool_Store::PROJECT)`-then-reload shape.
    // `ToolStore.user` entries are untouched (not this project's data).
    shellCommandList.clear(ToolStore.project);
    foreach (cmd; shellCommands)
        shellCommandList.add(cmd);
    rebuildShellMenu();

    // Swap in this project's own `ToolStore.project` layout suites --
    // matches FLTK's own `Layout_List::read(Project_Reader*)`'s
    // shape exactly (`readSnap()`'s own doc comment in `project_reader
    // .d`), mirroring the shell-command swap-in just above. A project
    // with no `snap {...}` block at all (`hasSnap == false`, the common
    // case) leaves the current suite/preset selection untouched.
    layoutList.removeAll(ToolStore.project);
    foreach (suite; layoutSuites)
        layoutList.add(suite);
    if (hasSnap)
    {
        if (layoutCurrentSuite.length) layoutList.currentSuite(layoutCurrentSuite);
        layoutList.currentPreset(layoutCurrentPreset);
    }
    layoutRefreshTabIfOpen();
    rebuildLayoutMenu();

    if (projectPath_.length && history_ !is null)
    {
        history_.update(appPrefs, projectPath_);
        rebuildRecentFilesMenu();
    }

    if (!asTemplate)
        mergebackCodeFiles(false);
}

/// Every top-level `WindowNode` reachable anywhere in `roots`' forest,
/// in tree order -- `Reader.readProject()`'s roots are almost always
/// `[FunctionNode]`, with each real window one level down as that
/// Function's own child (see `fluid.function_node`'s own doc comment),
/// but a project can declare any number of these, one per independently
/// edited top-level window (`panels/widget_panel.fl` has two: `make_
/// image_panel()`'s and `make_widget_panel()`'s). Matches real FLTK's
/// own behavior, confirmed by reading `Window_Node::open_()`/
/// `Project_Reader::read_project()`: every top-level `Window_Node`
/// shows its own live window as soon as it's read, unconditionally --
/// there's no "root window" concept FLTK at all, just however many
/// top-level windows a project happens to declare. Stops descending
/// once a `WindowNode` is found (its own children are that window's
/// nested content, not additional top-level roots -- an actual
/// subwindow nested inside another window's tree renders as part of
/// that parent window's own live tree, not a separate top-level
/// canvas, matching `instantiate.d`'s documented nested-window scope).
private WindowNode[] findAllWindowRoots(Node[] roots)
{
    WindowNode[] result;
    void walk(Node[] ns)
    {
        foreach (n; ns)
        {
            if (auto w = cast(WindowNode) n) result ~= w;
            else walk(n.children);
        }
    }
    walk(roots);
    return result;
}

/// Pushes the project's current state onto the undo stack and clears
/// the redo stack (a real, new edit invalidates whatever redo history
/// existed -- matches every other editor's own undo convention). A
/// no-op with no project open. Called *before* the mutation it's
/// guarding, from every project-mutating entry point.
private void checkpoint()
{
    if (projectRoots_.length == 0) return;
    undoStack_ ~= new ProjectWriter().generate(projectRoots_, projectI18n_, [], codeFileName_, null, true, projectDubHeader_, projectSettings_);
    redoStack_ = [];
    dirty_ = true;
    updateShelfTitle();
}

/// Reflects `dirty_`/`projectPath_` in the shelf window's own title
/// bar (`"Fluid - name.fl *"`, matching this port's own equivalent of
/// FLTK's title-bar unsaved-changes indicator). Called from every
/// place `dirty_` or `projectPath_` changes.
private void updateShelfTitle()
{
    import std.path : baseName;

    if (shelf_ is null) return;
    string name = projectPath_.length ? baseName(projectPath_) : "Untitled";
    shelf_.label("Fluid - " ~ name ~ (dirty_ ? " *" : ""));
}

/// Shows a Cancel/Discard confirmation if there are unsaved changes,
/// returning `true` if it's safe to proceed (either nothing to lose,
/// or the user confirmed discarding it) -- guards every action that
/// would otherwise silently lose edits: `&File/&Quit`, `&File/&New`,
/// `&File/&Open...`, and `&File/New from &Template...`.
private bool confirmDiscardChanges()
{
    if (!dirty_) return true;
    return fl.ask.choice("This project has unsaved changes.\nDiscard them?",
        "Cancel", "Discard", null) == 1;
}

/// Session tracker for `checkpointTextEdit()`.
private EditSession textEditSession_;

/// `checkpoint()` for one change of a text field: typing in a field calls
/// back on every keystroke, so only the first change of a session (see
/// `fluid.edit_session`) records an undo step.
private void checkpointTextEdit(Object key)
{
    if (!textEditSession_.needsCheckpoint(key, undoStack_.length))
        return;
    checkpoint();
    textEditSession_.started(key, undoStack_.length);
}

private void undo()
{
    textEditSession_.end();
    if (undoStack_.length == 0) return;
    redoStack_ ~= new ProjectWriter().generate(projectRoots_, projectI18n_, [], codeFileName_, null, true, projectDubHeader_, projectSettings_);
    string text = undoStack_[$ - 1];
    undoStack_ = undoStack_[0 .. $ - 1];
    restoreFromText(text);
}

private void redo()
{
    textEditSession_.end();
    if (redoStack_.length == 0) return;
    undoStack_ ~= new ProjectWriter().generate(projectRoots_, projectI18n_, [], codeFileName_, null, true, projectDubHeader_, projectSettings_);
    string text = redoStack_[$ - 1];
    redoStack_ = redoStack_[0 .. $ - 1];
    restoreFromText(text);
}

/// Parses `text` (always this module's own previous `ProjectWriter`
/// output, never user-supplied) and swaps it in as the current
/// project, same tail as `loadProject()` but without touching
/// `projectPath_`/the undo stacks themselves -- undo/redo must never
/// change *where* the project would save to, and must never be
/// mistaken for a new edit worth checkpointing.
///
/// **Keeps every still-corresponding window's own live X11 window
/// alive across the restore, instead of destroying and recreating it.**
/// An undo/redo step re-parses the *whole project* as `.fl` text (a
/// deliberate deviation from FLTK's own command-pattern undo: this port snapshots/
/// restores whole-project text instead of reversing individual edits in
/// place), which always produces brand-new `Node`/`WindowNode`
/// instances with no identity in common with the ones just discarded.
/// Handing every one of those fresh `WindowNode`s to
/// `showWindowCanvas()` unconditionally would create a brand-new
/// `ProjectCanvas` (a brand-new X11 window) for any `WindowNode` it
/// hasn't seen before -- i.e. every one of them, every single time.
/// Reapplying each window's own previous on-screen position
/// before its replacement's first `.show()` only ever
/// addresses part of the problem: several window managers (tiling ones
/// especially) don't respect a program's requested position for what
/// they see as a genuinely new top-level window at all, placing it
/// according to their own layout instead -- the real cause of windows
/// visibly jumping around on every undo/redo step if the window itself
/// isn't retained and is retired from
/// the X windows list.
///
/// The real fix: never destroy the X11 window in the first place.
/// Matches each *previous* top-level `WindowNode` with the *restored*
/// one by real identity (`fluid.node.Node.uid`, matching FLTK's own
/// `uid`/`set_uid()`; see that field's own
/// doc comment for the mechanism and its two disclosed simplifications),
/// not ordinal position: matching purely by position would be exactly
/// right whenever a step doesn't itself
/// add or remove a top-level window (the overwhelming majority of
/// edits), but wrong the moment one does anywhere but the very end of
/// the list -- e.g. undoing a step that deleted the *first* of three
/// windows would match the restored [A, B, C] against the current
/// [B, C] purely by position (A<->B, B<->C), silently reassigning B's
/// and C's own live X11 windows to the wrong `WindowNode`s instead of
/// recognizing A as the one actually coming back and B/C as unchanged.
/// Real `uid` matching has no such failure mode, whatever changed.
///
/// For every matched pair with an already-open canvas, calls
/// `ProjectCanvas.rebuildFrom()` on the *same* canvas object instead of
/// creating a new one -- see that method's own doc comment for the
/// mechanism. Only a window with no previous counterpart (added since
/// the state being restored to) gets a genuinely fresh
/// `showWindowCanvas()` call, and only a previously-open window with no
/// counterpart in the restored state (removed by this step) gets closed
/// -- both exactly matching what those cases would need even outside of
/// undo/redo. `activeWindow_` is restored to whichever window was
/// active before, tracked by the same `uid` match. Previously bailed
/// out entirely on a restored state with zero windows (a real, if rare,
/// latent bug -- undoing all the way back to an empty project silently
/// did nothing); the rewritten flow below handles it for free, since
/// closing every previous window with no counterpart needs no special
/// case for "there happen to be none left".
private void restoreFromText(string text)
{
    Node[] roots;
    I18nSettings i18n;
    string codeFileName;
    bool dubHeader;
    ProjectSettings settings;
    try
    {
        auto reader = new Reader(text);
        roots = reader.readProject();
        i18n = reader.i18n;
        codeFileName = reader.codeFileName;
        dubHeader = reader.dubHeader;
        settings = reader.settings;
    }
    catch (Exception e)
        return; // shouldn't happen -- this module generated the text itself

    auto windowRoots = findAllWindowRoots(roots);
    auto previousWindows = findAllWindowRoots(projectRoots_);

    // `uid`-keyed lookup of the restored windows -- see this function's
    // own top comment for why this replaced ordinal-position matching.
    WindowNode[ushort] newByUid;
    foreach (wn; windowRoots) newByUid[wn.uid] = wn;

    bool haveActiveUid;
    ushort activeUid;
    if (activeWindow_ !is null) { activeUid = activeWindow_.uid; haveActiveUid = true; }

    bool[WindowNode] matchedNew; // restored windows already claimed below

    // Reuse every still-corresponding window's own live canvas in
    // place. Deliberately does *not* route through `ensureCanvasVisible()`
    // when the canvas is already shown -- unlike `showWindowCanvas()`'s
    // own unconditional `cv.show()` (a "raise" when already shown), an
    // undo/redo step restoring content into a window the user is
    // already looking at has no reason to also jump it to the front of
    // the window stack. A canvas that happens to be closed still gets
    // shown, matching every other window-open path's own "every project
    // window ends up visible" guarantee.
    foreach (oldWn; previousWindows)
    {
        auto cv = canvases_.get(oldWn, null);
        auto newWnP = oldWn.uid in newByUid;
        if (newWnP is null)
        {
            // No counterpart in the restored state (removed by this
            // step) -- close its canvas, same as deleting a window
            // normally does.
            if (cv !is null)
            {
                cv.hide();
                canvases_.remove(oldWn);
            }
            continue;
        }
        auto newWn = *newWnP;
        matchedNew[newWn] = true;
        if (cv is null) continue; // not currently open -- nothing live to reuse
        canvases_.remove(oldWn);
        cv.rebuildFrom(newWn, projectDir_());
        canvases_[newWn] = cv;
        wireCanvasCallbacks(newWn, cv);
        if (!cv.shown()) ensureCanvasVisible(cv);
    }

    closeExternalEditors(); // every Node this restore discards goes with it

    projectRoots_ = roots;
    projectI18n_ = i18n;
    projectDubHeader_ = dubHeader;
    projectSettings_ = settings;
    updateMergebackMenu();
    codeFileName_ = codeFileName;

    // A window with no previous counterpart is genuinely new (added
    // since the state being restored to) -- no live canvas to reuse, so
    // it gets a real fresh one, same as opening any newly-added window.
    foreach (wn; windowRoots)
        if (wn !in matchedNew)
            showWindowCanvas(wn);

    auto activeP = haveActiveUid ? (activeUid in newByUid) : null;
    activeWindow_ = activeP !is null ? *activeP : (windowRoots.length ? windowRoots[0] : null);

    browser_.build(projectRoots_);
    widgetPanelLoad([], LiveTree.init, projectDir_());

    codeviewAutoRefresh();
}

/// Creates (if `wn` has no canvas yet) and shows/raises `wn`'s own live
/// `ProjectCanvas` -- the one shared primitive behind "open every
/// window a freshly loaded project declares" (`openLoadedProject()`,
/// matching real FLTK's own unconditional-show-on-load behavior, see
/// `findAllWindowRoots()`'s own doc comment) and "double-click a
/// `WindowNode` to (re)open its design window, or create the very
/// first/a brand new one" (`openNode()`/`createWindowNode()`).
/// `restoreFromText()` only calls this for a genuinely new window (one
/// with no live counterpart before the restore) -- every other window
/// keeps its own already-open canvas via `ProjectCanvas.rebuildFrom()`
/// instead, never going through here at all.
///
/// Wires every per-canvas callback to mark `wn` the active window
/// before delegating to the shared handler (`activeWindow_ = wn;`) --
/// this is what makes keyboard-shortcut-driven edits (Cut/Copy/Paste/
/// Align/Select All/Delete/...), which have no canvas of their own to
/// consult, always act on whichever window the user most recently
/// interacted with, matching FLTK's own single project-wide
/// `Fluid.proj.tree.current` scope.
private ProjectCanvas showWindowCanvas(WindowNode wn)
{
    auto cv = canvases_.get(wn, null);
    bool freshlyCreated = cv is null;
    if (freshlyCreated)
    {
        cv = new ProjectCanvas(wn, projectDir_());
        canvases_[wn] = cv;
        wireCanvasCallbacks(wn, cv);
        // Carries the current "Hide Overlays"/"Hide Guides"/"Hide
        // Restricted"/"Show Ghosted Group Outlines" toggle state to a
        // freshly-opened window -- a brand-new `ProjectCanvas` otherwise
        // defaults back to its own class defaults, silently forgetting
        // whatever every other open window (or a previous session's
        // toggle) already agreed on.
        cv.overlaysHidden = overlaysHidden_;
        cv.showGuides = showGuides_;
        cv.showRestricted = showRestricted_;
        cv.showGhostedOutline = showGhostedOutline_;
        cv.allowLayout = allowLayout_;
    }
    activeWindow_ = wn;
    ensureCanvasVisible(cv);
    return cv;
}

/// Wires every per-canvas callback so it always marks `wn` as the
/// active window before delegating. Split out of `showWindowCanvas()`
/// (a freshly-created canvas) since `restoreFromText()`'s reused-canvas
/// path needs it too: `ProjectCanvas.rebuildFrom()` swaps in a
/// brand-new `WindowNode` for an already-open canvas, but every closure
/// below closes over its own `wn` parameter *by that call's own
/// binding*, fixed at the moment it's created -- reassigning `cv`'s
/// internal `root_` field afterward doesn't touch it. Without calling
/// this again after a rebuild, every one of these callbacks would keep
/// setting `activeWindow_` to the stale, already-discarded `WindowNode`
/// instead of the one `restoreFromText()` just swapped in.
private void wireCanvasCallbacks(WindowNode wn, ProjectCanvas cv)
{
    cv.onSelectionChanged = (n) { activeWindow_ = wn; selectFromCanvas(n); };
    cv.onDeleteRequested = () { activeWindow_ = wn; deleteSelected(); };
    cv.onWidgetDropped = (typeName, parent, x, y) { activeWindow_ = wn; dropWidget(typeName, parent, x, y); };
    cv.onBeforeGeometryEdit = () { activeWindow_ = wn; checkpoint(); };
    cv.onGeometryEdited = () { activeWindow_ = wn; geometryEdited(); };
    cv.onOpenRequested = (n) { openNode(n); };
    cv.onContextMenu = (x, y) { activeWindow_ = wn; showCanvasContextMenu(cv, x, y); };
    cv.onImageDropped = (path, target, inactive) { activeWindow_ = wn; dropImage(path, target, inactive); };
}

/// Ensures `cv` is shown/raised, including the WM size-hint fixup a
/// not-yet-mapped (or previously closed) window still needs. Split out
/// of `showWindowCanvas()` so `restoreFromText()`'s reused-canvas path
/// can reach the exact same "every project window ends up visible"
/// guarantee undo/redo has always given (matching real FLTK's own
/// unconditional-show-on-load behavior) without also recreating the
/// canvas `showWindowCanvas()` itself would.
///
/// `fl.window.Window`'s own constructor defaults to `resizable(null);`,
/// and `defaultSizeRange()`'s documented behavior is: "If resizable() is
/// null (the default), the window becomes fixed-size (min == max == its
/// current size)" -- computed once, the very first time a window is
/// shown, and never recomputed after. Without a fixup, that would leave
/// every canvas window unresizable from the window manager's controls.
/// Ports FLTK's own one-shot trick for exactly this situation
/// (`Window_Node::open_()`, `nodes/Window_Node.cxx`): temporarily set
/// `resizable(this)` (spanning the *whole* window, via
/// `defaultSizeRange()`'s own `r is this` special case) only for the
/// single `.show()` call that computes and sends the real (non-fixed)
/// size hints to the WM, then immediately restore whatever
/// `resizable()` was before (`null` here, always, since nothing else
/// ever sets it) -- so ordinary D-side `FlGroup.resize()` child auto-
/// relayout, which FLTK's own trick is equally careful never to
/// leave permanently enabled, never actually engages during normal
/// editing; only the WM-facing size hints computed during this one call
/// persist. Needed again every time a *closed* window is reopened too,
/// not just its first show -- a destroyed-and-recreated X window has no
/// WM size hints of its own yet, matching FLTK's own `if (w->
/// shown()) { w->show(); ... } else { <the resizable() trick>; w->
/// show(); ... }`.
private void ensureCanvasVisible(ProjectCanvas cv)
{
    if (!cv.shown())
    {
        auto priorResizable = cv.resizable();
        if (priorResizable is null) cv.resizable(cv);
        cv.show();
        cv.resizable(priorResizable);
    }
    else
        cv.show(); // already shown -> raises (fl.window.Window.show() semantics)
    cv.redrawOverlay();
}

private void openLoadedProject(WindowNode[] roots)
{
    foreach (wn; roots)
        showWindowCanvas(wn);
    // `showWindowCanvas()` itself sets `activeWindow_` on every call, so
    // after the loop it's whichever root was shown *last* -- reset to
    // the first, matching the "primary window" convention
    // `saveAsTemplate()`'s own screenshot already uses.
    if (roots.length) activeWindow_ = roots[0];

    browser_.build(projectRoots_);
    widgetPanelLoad([], LiveTree.init, projectDir_());

    // Keep an already-open Code View in sync with whichever project is
    // now current -- codeviewRefresh()'s own `cvRoots_` would otherwise
    // go stale the moment the user switches projects while it's open
    // (its "Refresh" button re-renders whatever it was last told to,
    // not necessarily the project on screen right now).
    codeviewAutoRefresh();
}

private void closeProject()
{
    foreach (cv; canvases_.byValue())
        cv.hide();
    canvases_.clear();
    activeWindow_ = null;
    projectRoots_ = null;

    closeExternalEditors();
}

/// Deterministic cleanup (not left to the GC finalizer -- see
/// `Widget.~this()`'s own established GC-finalizer-hazard note,
/// CLAUDE.md): `closeEditor()` prompts the user if a process is still
/// running, the same experience switching projects with a live shell
/// command running would already give via a different path. Shared by
/// `closeProject()` and `restoreFromText()` -- an undo/redo step
/// replaces every `Node` in the project (not just window roots), so any
/// external-editor session keyed by a node this restore is discarding
/// needs the same forced close a full project switch already gives it,
/// even though `restoreFromText()` no longer tears down the live
/// windows themselves (see `ProjectCanvas.rebuildFrom()`'s own doc
/// comment).
private void closeExternalEditors()
{
    foreach (editor; externalEditors_.byValue())
        editor.closeEditor();
    externalEditors_.clear();
}

/// Creates a new `typeName` node/widget (`typeName` is one of
/// `fluid.instantiate`'s registered bare names, e.g. "Box"/"Button") --
/// the widget palette's whole "New" menu (above, `runEditor()`) funnels
/// through this one function.
///
/// Target parent: the currently-selected node if it's a container
/// (`WidgetNode.canHaveChildren()` -- a `WindowNode`/`GroupNode`/
/// `Tabs`/`Wizard`), otherwise the project's own root window --
/// matches the intuitive "select a group, add into it; select nothing
/// or a leaf widget, add to the top level" rule. Default geometry is
/// `10,10` plus `fluid.instantiate.idealSizeFor(typeName)`'s own
/// per-type size (matching FLTK's real `add_new_widget_from_user()`
/// -- see that function's own doc comment for the full story).
///
/// Node-side (`createNode()`) and live-widget-side (`instantiateOne()`)
/// construction are two separate calls, matching this module's existing
/// split between the parsed `Node` tree (`projectRoots_`, what gets
/// saved) and each open window's own live `fl.widget.Widget` tree
/// (`canvasFor(n).liveTree()`, what gets shown) -- same two trees
/// `openLoadedProject()` builds from a loaded file, just grown by one
/// node/widget pair instead of parsed wholesale.
private void addWidget(string typeName)
{
    // Matches `Widget_Node::make()` exactly (`nodes/Widget_Node.cxx`):
    // FLTK shows `fl_message("Please select a group widget or
    // window")` and creates nothing when there's no valid container to
    // place the new widget in. An empty project (no `WindowNode` yet)
    // is a real, reachable state -- clicking a plain widget-bin button
    // (Button, Box, ...) before any window exists deserves the same
    // message `createWindowNode()` shows for the equivalent "no
    // Function yet" case, not silence.
    Node anchorNode = currentSelection();
    Node parentNode = anchorNode;
    if (parentNode is null || !parentNode.canHaveChildren())
        parentNode = activeWindow_;
    if (parentNode is null)
    {
        fl.message("Please select a group widget or window");
        return;
    }

    checkpoint();

    int w, h;
    idealSizeFor(typeName, w, h);
    // Uses the canvas's own right-click point when this call came from
    // `showCanvasContextMenu()`'s popup (`popupX_`/`popupY_`, ported
    // from FLTK's own `popupx`/`popupy` -- `Window_Node::handle()`'s
    // `FL_PUSH` right-click case sets them around the same `New_Menu->
    // popup()` call this port's own `showCanvasContextMenu()` mirrors);
    // every other caller (the shelf's own `&New` menu, the widget bin)
    // gets `Widget_Node::make()`'s own real adjacent-placement algorithm
    // instead of a flat `10, 10`, so clicking the same bin button
    // repeatedly places each new widget next to the last one made
    // rather than stacking them all at the same spot. See
    // `defaultPositionFor()`'s own doc comment for the full algorithm.
    int px, py;
    if (popupX_ >= 0)
    {
        px = popupX_; py = popupY_;
    }
    else
    {
        bool newIsGroup = createNode(typeName).canHaveChildren();
        defaultPositionFor(parentNode, anchorNode, newIsGroup, px, py);
    }
    insertWidget(typeName, parentNode, px, py, w, h);
}

/// Ported from `Widget_Node::make()`'s own position-selection algorithm
/// (`nodes/Widget_Node.cxx`) -- computes where a newly-created widget
/// should land when there's no explicit drop/right-click point: fill
/// the parent if the new widget is itself a container (`newIsGroup`,
/// FLTK's `dynamic_cast<Group_Node*>(this)`), otherwise place it
/// directly adjacent to the currently selected sibling widget
/// (`anchorNode`, FLTK's `q`) -- copying its position and wrapping
/// to the next row if it would overflow the parent's right edge -- or a
/// small top-left-corner square if nothing else is selected (`anchorNode
/// is null` or *is* `parentNode` itself, FLTK's `q == p`).
/// `parentNode` mirrors FLTK's `p`; `ulx`/`uly` mirror its `ULX`/
/// `ULY` ("parent's origin in window" -- `(0,0)` for a `WindowNode`
/// parent, the parent's own live position for a nested `Group`); `b`
/// mirrors its `B` (a border margin, `min(p.w/2, p.h/2, 25)`).
/// Deliberately doesn't also compute width/height the way FLTK's
/// own `make()` does for the adjacent-placement branch (copying the
/// anchor's size) -- FLTK's own *caller* (`add_new_widget_from_
/// user()`) immediately overwrites that guess with the real `ideal_
/// size()` right afterward for every non-`Window_Node` case anyway
/// (`o->size(w, h)`, position only, matching `addWidget()`'s own
/// pre-existing `idealSizeFor()` call), so only X/Y need computing
/// here to get the same net observable effect.
private void defaultPositionFor(Node parentNode, Node anchorNode, bool newIsGroup, out int x, out int y)
{
    auto p = cast(WidgetNode) parentNode;
    if (p is null) { x = 10; y = 10; return; }

    int ulx, uly;
    if (cast(WindowNode) parentNode is null) { ulx = p.x; uly = p.y; }

    int b = p.w / 2;
    if (p.h / 2 < b) b = p.h / 2;
    if (b > 25) b = 25;

    if (newIsGroup)
    {
        x = ulx + b; y = uly + b;
        return;
    }

    auto q = cast(WidgetNode) anchorNode;
    if (q !is null && anchorNode !is parentNode)
    {
        x = q.x + q.w; y = q.y;
        if (x + q.w > ulx + p.w)
        {
            x = q.x; y = q.y + q.h;
            if (y + q.h > uly + p.h) y = uly + b;
        }
        return;
    }

    x = ulx + b; y = uly + b;
}

/// `-1` (this port's own sentinel, FLTK's is `0x7FFFFFFF`) outside
/// of a `showCanvasContextMenu()` popup -- see `addWidget()`'s own doc
/// comment on the one consumer.
private int popupX_ = -1, popupY_ = -1;

/// `ProjectCanvas.onContextMenu`'s target -- pops up the exact same
/// "&New" widget-creation submenu the shelf's own menu bar already has,
/// reusing its real `MenuItem[]` array (`menu_.menu()` plus `findIndex(
/// "&New")`'s own position, a pointer straight into the middle of that
/// same array -- FLTK's native flat, embedded-submenu format, matching
/// FLTK's own `Fl_Menu_Item::popup()`/`pulldown()` shape exactly)
/// rather than building a second, separately-maintained copy of the
/// same item list. Ported from `Window_Node::handle()`'s own `FL_PUSH`
/// right-click case (`New_Menu->popup(mx,my,"New",myprev); if (m &&
/// m->callback()) {myprev = m; m->do_callback(this->o);}`) -- `fl.
/// menu_popup.popup()` only *shows* the menu and returns whichever item
/// was picked, the same as FLTK's own `popup()`/`pulldown()`; the
/// caller is responsible for invoking that item's own callback
/// afterward, matching FLTK's explicit `do_callback()` call rather
/// than assuming the engine does it internally. `x`/`y` are canvas-
/// local (matching `onWidgetDropped`'s own convention) -- translated to
/// real screen coordinates here via `cv.x()`/`.y()` (`cv` is a real
/// top-level window, whose own `x()`/`y()` already report screen
/// position) for `fl.menu_popup.popup()`'s own screen-coordinate
/// contract. `cv` identifies *which* canvas fired this -- `showWindowCanvas()`'s
/// own wiring passes its own canvas explicitly, since a bare `x`/`y`
/// pair alone can't say which window it's relative to once more than
/// one can be open.
///
/// Not ported: FLTK's `in_this_only` (constrains which menu items
/// even apply while the popup is open) -- it exists to scope certain
/// FLTK-specific menu behaviors this port doesn't have an
/// equivalent mechanism for at all; out of scope for this pass.
private void showCanvasContextMenu(ProjectCanvas cv, int x, int y)
{
    if (menu_ is null || cv is null) return;
    auto idx = menu_.findIndex("&New");
    if (idx < 0) return;
    auto items = menu_.menu() + idx + 1;

    popupX_ = x;
    popupY_ = y;
    auto m = fl.popup(items, cv.x() + x, cv.y() + y, null, fl.MenuStyle.defaults(), "New");
    if (m !is null) m.doCallback(cv);
    popupX_ = -1;
    popupY_ = -1;
}

/// `ProjectCanvas.onWidgetDropped`'s target (wired in
/// `openLoadedProject()`) -- the drag-and-drop counterpart to
/// `addWidget()` above, fed by the widget palette's `WidgetBin`/
/// `BinButton` (`fluid.widget_bin`/`fluid.bin_button`). `parent`/`x`/`y`
/// are already resolved by the canvas itself (live hit-testing during
/// the drag -- see `ProjectCanvas.handle()`'s `Event.dndEnter`/
/// `dndDrag` cases), so this only needs to turn them into a real node.
/// Default size matches `addWidget()`'s own per-type `idealSizeFor()`;
/// the drop point becomes the new widget's top-left corner, the
/// simplest, most predictable placement rule for a first cut
/// (FLTK's own drop-centers-under-cursor feel needs per-drag
/// geometry this port doesn't track yet).
private void dropWidget(string typeName, Node parent, int x, int y)
{
    if (parent is null) return;
    checkpoint();
    int w, h;
    idealSizeFor(typeName, w, h);
    insertWidget(typeName, parent, x, y, w, h);
}

/// `ProjectCanvas.onImageDropped`'s target -- an external image file (a
/// file manager, a browser, ...) dropped onto a widget on the canvas. Ported
/// from `Window_Node::handle()`'s own `FL_PASTE` image-drop branch:
/// resolve `absPath` to the project's own directory (matching FLTK's
/// `Fluid.proj.enter_project_dir(); fl_filename_relative(...); Fluid.
/// proj.leave_project_dir();`, and `widget_panel.d`'s own manually-typed
/// image-filename fields, which store the identical project-relative
/// form), store it on the target's own `imageFilename`/`deimageFilename`
/// (`inactive` picks which), update the live widget's `.image()`/
/// `.deimage()` the same way `WidgetPanelDialog.onImageChanged()`/
/// `onDeimageChanged()` already do for a manually-typed path, then
/// select and open the target -- matching FLTK's own trailing
/// `select_only(tgt); tgt->open();`.
private void dropImage(string absPath, Node target, bool inactive)
{
    import std.path : relativePath;

    auto wn = cast(WidgetNode) target;
    if (wn is null) return;
    auto cv = canvasFor(wn);

    checkpoint();
    string rel = relativePath(absPath, projectDir_());
    auto lw = cv !is null ? cv.liveTree().widgetOf.get(wn, null) : null;
    if (inactive)
    {
        wn.deimageFilename = rel;
        wn.hasDeimage = true;
        if (lw !is null) lw.deimage(loadImageFile(absPath));
    }
    else
    {
        wn.imageFilename = rel;
        wn.hasImage = true;
        if (lw !is null) lw.image(loadImageFile(absPath));
    }
    if (lw !is null) lw.redraw();

    if (cv !is null) cv.syncSelectionFrom([wn]);
    browser_.syncSelection([wn]);
    openNode(wn);

    codeviewAutoRefresh();
}

/// Shared tail of `addWidget()`/`dropWidget()` -- constructs the
/// `Node`, inserts it under `parentNode`, builds its live widget if the
/// parent is already realized, and refreshes every dependent UI
/// (browser, selection, property panel, code view). `typeName` must
/// already be `WidgetNode`-shaped (every entry both the "&New" menu and
/// the widget palette offer is -- see their own comments on excluding
/// "Window"/"DoubleWindow").
private void insertWidget(string typeName, Node parentNode, int x, int y, int w, int h)
{
    auto newNode = createNode(typeName);
    newNode.typeName = typeName;
    newNode.instanceName = ""; // anonymous, same as newProject()'s own
                                // Window -- code_writer.d already handles
                                // anonymous nodes (including several of
                                // the same type) via its own anonNames
                                // naming, nothing extra needed here

    auto wn = cast(WidgetNode) newNode;
    if (wn is null)
        return; // defensive only, should never actually be null
    wn.hasXywh = true;
    wn.x = x; wn.y = y; wn.w = w; wn.h = h;

    // `defaultLabelFor()` matches the small, real set of FLTK node
    // kinds whose own `widget()` factory override passes a default
    // label ("Button"/"label"/etc) at all; every other type gets none,
    // same as FLTK.
    string defaultLabel = defaultLabelFor(typeName);
    if (defaultLabel.length)
    {
        wn.label = defaultLabel;
        wn.hasLabel = true;
    }

    // A Menu_Bar dropped as the very first child of a window: matches
    // FLTK's own `add_new_widget_from_user()` special case
    // (`nodes/factory.cxx`) -- span the window's full width and pin to
    // (0, 0) instead of using the normal drop position/ideal size,
    // since a menu bar spanning only part of the window's top edge
    // would look broken the moment it's created, not just eventually
    // resized by hand. Checked before `addChild()` runs (`children.
    // length == 0` means "no children yet", not "about to have its
    // first" -- `newNode` itself hasn't been added yet at this point).
    auto cv = canvasFor(parentNode);

    if ((typeName == "MenuBar" || typeName == "Menu_Bar")
        && cast(WindowNode) parentNode !is null
        && parentNode.children.length == 0)
    {
        wn.x = 0; wn.y = 0;
        auto parentWindow = cv is null ? null : cast(Window) cv.liveTree().widgetOf.get(parentNode, null);
        if (parentWindow !is null) wn.w = parentWindow.w();
    }

    parentNode.addChild(newNode);

    if (cv !is null)
    {
        auto parentGroup = cast(FlGroup) cv.liveTree().widgetOf.get(parentNode, null);
        if (parentGroup !is null)
        {
            auto widget = instantiateOne(wn, projectDir_());
            if (widget !is null)
            {
                insertIntoGroup(parentGroup, widget, x, y);
                cv.liveTree().widgetOf[newNode] = widget;
                cv.liveTree().nodeOf[widget] = newNode;
            }
        }
    }

    browser_.build(projectRoots_);
    if (cv !is null) cv.selectOnly(newNode);
    browser_.syncSelection([newNode]);
    openNode(newNode);
    if (cv !is null) { cv.redraw(); cv.redrawOverlay(); }

    codeviewAutoRefresh();
}

/// Adds `widget` to `parentGroup` -- a plain append (`FlGroup.add()`) for
/// every ordinary container, but `Flex`/`Grid` parents get real
/// position-aware placement instead, matching FLTK's own
/// `add_new_widget_from_user()` (`nodes/factory.cxx`) special cases:
///
/// - **`Flex`**: `Flex_Node::insert_child_at()` finds the existing
///   child whose own position (along the Flex's primary axis) is
///   closest to the drop point and inserts right there, rather than
///   always at the end -- ported verbatim (same closest-neighbor scan,
///   same "or past the last child" tail case), using `FlGroup.insert()`
///   (this port's own `Fl_Group::insert(Fl_Widget&, int)` equivalent,
///   already real) instead of FLTK's own `Fl_Flex::insert()`
///   override, which does the identical thing.
/// - **`Grid`**: FLTK's own `Grid_Node::insert_child_at()` (click-
///   position-to-nearest-cell, using the grid's own margin/gap/computed
///   row-height/col-width accumulation) is *not* ported -- a
///   deliberately narrower simplification, not an oversight: this port
///   only implements the *other* FLTK entry point, `Grid_Node::
///   insert_child_at_next_free_cell()` (used when there's no specific
///   drop position to go on), applied unconditionally here rather than
///   only for the click-to-add case. Real click-position-aware Grid
///   placement is a real, separate, bigger follow-up if ever needed --
///   scanning for the first unoccupied `(row, col)` already fixes the
///   actual reported gap (a dropped widget landing in *some* real,
///   unoccupied cell instead of never being placed into the grid's own
///   cell system at all, which is what a plain `FlGroup.add()` did
///   before this).
/// - **Everything else**: plain `FlGroup.add()` (append), unchanged.
private void insertIntoGroup(FlGroup parentGroup, Widget widget, int x, int y)
{
    if (auto flex = cast(Flex) parentGroup)
    {
        int closestIdx = -1;
        int closestDist = flex.w() + flex.h();
        foreach (i; 0 .. flex.children())
        {
            auto c = flex.child(i);
            int d = (flex.horizontal() ? x - c.x() : y - c.y());
            if (d < 0) d = -d;
            if (d < closestDist) { closestDist = d; closestIdx = i; }
        }
        int tailD = (flex.horizontal()
            ? x - (flex.x() + flex.w())
            : y - (flex.y() + flex.h()));
        if (tailD < 0) tailD = -tailD;
        if (tailD < closestDist) { closestDist = tailD; closestIdx = flex.children(); }

        if (closestIdx >= 0)
            flex.insert(widget, closestIdx);
        else
            flex.add(widget); // defensive only -- closestIdx is always
                               // set by the tail case above even with
                               // zero existing children
        return;
    }

    if (auto grid = cast(Grid) parentGroup)
    {
        foreach (r; 0 .. grid.rows())
        {
            foreach (c; 0 .. grid.cols())
            {
                if (grid.cell(r, c) is null)
                {
                    grid.widget(widget, r, c);
                    return;
                }
            }
        }
        // Every existing cell is occupied -- FLTK grows the grid by
        // one row and uses its first column; matched here exactly.
        grid.layout(grid.rows() + 1, grid.cols());
        grid.widget(widget, grid.rows() - 1, 0);
        return;
    }

    parentGroup.add(widget);
}

/// Creates a new non-widget project-structure node -- the widget
/// palette's "Code" group (`Function`/`Class`/`comment`/`Code`/
/// `CodeBlock`/`widget_class`/`decl`/`declblock`/`data`) -- and inserts
/// it into the project tree. The non-widget counterpart to
/// `insertWidget()`: these types are never `WidgetNode`s (no live
/// `fl.widget.Widget`, no xywh, no canvas placement), so there's no
/// `instantiateOne()`/live-parenting step at all, matching FLTK's
/// own `type_make_cb`/`add_new_widget_from_user()` for this same "Code"
/// group (a plain click-through-a-shared-callback path, not the
/// widget-palette's drag-and-drop `Bin_Button` mechanism, even though
/// this port reuses the `BinButton` class for its `typeName()` storage
/// -- see `function_panel.fl`'s own top comment).
///
/// Target, matching FLTK's own `AS_LAST_CHILD`/`AFTER_CURRENT`
/// strategy split (`Node::add_new_widget_from_user()`): if the current
/// selection can itself hold children (a `Function`/`Class`/
/// `widget_class`/`declblock`/`codeblock`), the new node becomes its
/// last child. Otherwise the new node becomes a top-level project root
/// -- spliced in right after the selection's own top-level ancestor if
/// something is selected, or appended at the end if nothing is.
/// This port's counterpart to FLTK's `Fluid.proj.tree.current` --
/// a single project-wide "what's selected right now" pointer FLTK
/// tracks off the one shared project tree (shared across every open
/// window there too, matching `activeWindow_`'s own doc comment). This
/// port instead splits selection tracking across two separate UI
/// elements (the *active* window's own `ProjectCanvas`, which only
/// exists once at least one `WindowNode` does, and `browser_`, the node
/// tree list that exists unconditionally from startup) -- so "current
/// selection" needs to consult whichever one is actually meaningful
/// right now rather than assuming a canvas always exists the way
/// FLTK's single tracked pointer does. Prefers the active canvas's
/// own selection (kept in sync with the browser's by `selectFromCanvas(
/// )`/`selectFromBrowser()` whenever both exist); falls back to the
/// browser's own selection when there's no canvas at all yet (a project
/// with no `WindowNode`, e.g. right after `&File/&New` or right after
/// adding a first `Function` -- see `addNode()`'s and
/// `createWindowNode()`'s own callers).
private Node currentSelection()
{
    if (auto cv = activeCanvas())
    {
        auto n = cv.primarySelection();
        if (n !is null) return n;
    }
    auto sel = browser_.selectedNodes();
    return sel.length ? sel[$ - 1] : null;
}

private void addNode(string typeName)
{
    checkpoint();

    auto newNode = createNode(typeName);
    newNode.typeName = typeName;
    // A freshly-created `Function` defaults to a real, non-empty
    // signature rather than the generic empty-name placeholder every
    // other Code-group node gets -- matches FLTK's own
    // `Function_Node::make()` exactly (`o->name("make_window()")`,
    // adapted from C++'s snake_case to this project's own D camelCase
    // convention, e.g. `CubeViewUI.fl`'s own `makeWindow()`), including
    // *why*: leaving `return_type` unset (D's counterpart:
    // `FunctionNode.returnType` starts empty by construction, untouched
    // here) is what makes `code_writer.d`'s `writePlainFunction()` (see
    // its own doc comment) auto-infer the return type from this
    // function's first widget child once one exists -- the classic
    // "click Function, click Window, get a real `Window makeWindow()
    // { ...; return w; }`" shape this whole feature is about. Every
    // other Code-group type keeps the empty-name placeholder (a plain
    // `Comment`/`Declaration`/etc. has no equivalent "generic starting
    // point" FLTK gives it either).
    newNode.instanceName = typeName == "Function" ? "makeWindow()" : "";

    Node current = currentSelection();
    if (current !is null && current.canHaveChildren())
    {
        current.addChild(newNode);
    }
    else if (current !is null && current.parent !is null)
    {
        // Matches FLTK's `Strategy::AFTER_CURRENT` half of
        // `Node::add_new_widget_from_user()`: a selection that can't
        // itself hold children (a `MenuItemNode`, a `Comment`, ...) still
        // has the new node land as its own next sibling, not all the way
        // up at the project root. Without this branch, selecting a plain
        // `Menu Item` and adding another spliced the new item in as a
        // sibling of the enclosing `Function` instead of the enclosing
        // menu -- the single most common menu-building workflow
        // (item, item, item) landed every item after the first in the
        // wrong place entirely.
        current.parent.insertChildAfter(current, newNode);
    }
    else
    {
        import std.algorithm : countUntil;

        // Walk up to whichever `projectRoots_` entry `current` sits
        // under (a plain child's `.parent` chain always reaches one --
        // `current` itself if nothing was selected under a root, i.e.
        // `current is null`).
        Node topLevel = current;
        while (topLevel !is null && topLevel.parent !is null)
            topLevel = topLevel.parent;

        auto idx = topLevel is null ? -1 : projectRoots_.countUntil(topLevel);
        if (idx >= 0)
            projectRoots_ = projectRoots_[0 .. idx + 1] ~ newNode ~ projectRoots_[idx + 1 .. $];
        else
            projectRoots_ ~= newNode;
    }

    if (cast(MenuItemNode) newNode !is null) refreshLiveMenu(newNode);

    browser_.build(projectRoots_);
    if (auto cv = canvasFor(newNode)) cv.syncSelectionFrom([newNode]);
    browser_.syncSelection([newNode]);
    openNode(newNode);

    codeviewAutoRefresh();
}

/// Ported from `Window_Node::make()` (`nodes/Window_Node.cxx`) --
/// `&New/&Group/&Window`'s and the widget bin's own dedicated
/// callback, deliberately *not* routed through `addWidget()`/
/// `addNode()`'s generic target-selection rules the way every sibling
/// item is. FLTK's own placement rule is stricter than either of
/// those: walk up from the current selection until a "code block"
/// ancestor is found (this port's equivalent, for now: a `FunctionNode`
/// -- the only real container this port has that plays that role;
/// FLTK's own check also matches `Class_Node`/`declblock`/etc. and
/// explicitly excludes `Widget_Class_Node`, neither of which is
/// relevant yet since this port has no window-inside-a-class-method
/// creation path at all -- broaden this the same way once one exists).
/// If none exists, FLTK shows `fl_message("Please select a
/// function")` and creates nothing at all -- ported verbatim, since a
/// window with no enclosing function has nowhere sensible to be
/// written as D code either (`code_writer.d` only ever emits a
/// `WindowNode`'s construction from inside a `FunctionNode`'s own
/// body).
///
/// Default geometry (100x100) matches FLTK's own `new
/// Fl_Window(100,100)` here exactly -- deliberately *not*
/// `newProject()`'s own 400x300/`FLAT_BOX` defaults, which are that
/// function's own, separate, more-convenient-for-a-blank-project
/// choice, not `Window_Node::make()`'s.
private void createWindowNode()
{
    // `currentSelection()` (see its own doc comment just above
    // `addNode()`) covers both the "canvas already open" case and the
    // "brand-new/emptied project, only the browser has a selection"
    // case -- the common real-world path to get here at all: a freshly
    // added `Function` node (`addNode("Function")`, itself now reachable
    // from a genuinely empty project too, see `newProject()`'s own doc
    // comment) has no live canvas of its own to select it *on*, only a
    // browser row.
    Node current = currentSelection();
    Node anchor = current;
    while (anchor !is null && cast(FunctionNode) anchor is null)
        anchor = anchor.parent;

    if (anchor is null)
    {
        fl.message("Please select a function");
        return;
    }

    checkpoint();

    auto win = new WindowNode();
    win.typeName = "Window";
    win.instanceName = "";
    win.x = 0;
    win.y = 0;
    win.w = 100;
    win.h = 100;
    win.hasXywh = true;

    anchor.addChild(win);

    // `showWindowCanvas()` handles both "this is the project's very
    // first `WindowNode`" and "one already exists" identically -- it
    // creates a fresh canvas whenever `win` doesn't have one yet.
    browser_.build(projectRoots_);
    showWindowCanvas(win);
    canvases_[win].syncSelectionFrom([win]);
    browser_.syncSelection([win]);
    openNode(win);

    codeviewAutoRefresh();
}

/// This port's counterpart to FLTK's `Node::open()` ("what happens
/// when you double-click", `nodes/Node.h`'s own doc comment) -- shows
/// (or raises, if already visible/behind another window --
/// `fl.window.Window.show()` on an already-shown window forwards to
/// `platformX11.raiseWindow()`, matching real `XMapRaised` semantics)
/// the Widget Properties panel with `n` loaded, the same pairing
/// FLTK's own shared `open_panel()` does (`widget_panel_callbacks.
/// cxx`: lazily construct-or-reuse `the_panel`, `load_panel()`, then
/// `the_panel->show()`). FLTK dispatches this per-node-kind through
/// a virtual `Node::open()` purely because C++ needs *some* override
/// point to reach the one shared `open_panel()` call from `Widget_
/// Node::open()`/`Function_Node::open()`/every other Code-group node's
/// own override alike -- fldtk's own `widget_panel.fl`'s `load()`
/// already branches on the node's runtime type internally
/// (`cast(WidgetNode)`/`cast(FunctionNode)`/etc.), so one plain
/// function already covers every kind without needing a matching
/// virtual method on `fluid.node.Node` itself.
///
/// A `ProjectCanvas` has no `callback()` override, so closing it via
/// the WM's own close button falls back to `fl.window.Window`'s plain
/// default (`hide()` + push onto the read queue, same as any other
/// window), and `hide()` really does destroy the underlying X resource
/// (`platformX11.destroyWindow()`), not just unmap it -- so once
/// closed, `shown()` is genuinely `false` with nothing left to reopen
/// it on its own. Double-clicking the node in the project panel reuses
/// the same one-shot `resizable()` trick for re-showing a closed window
/// that a first show needs too, matching FLTK's own `Window_Node::
/// open_()` (`if (w->shown()) { w->show(); ... } else { <the
/// resizable() trick>; w->show(); ... }`) -- generalized into
/// `showWindowCanvas()`, the one shared primitive behind every place a
/// `WindowNode`'s canvas needs creating and/or (re)showing, called
/// below for *any* `n` inside a window, not just a single designated
/// root.
///
/// Called from every place a node newly comes into being or is
/// explicitly re-opened (`insertWidget()`, `addNode()`,
/// `NodeBrowser.onOpen` via a double-click) -- not from ordinary
/// selection-change (`selectFromCanvas()`/`selectFromBrowser()`), which
/// only calls `widgetPanelLoad()` directly, matching FLTK's own
/// `selection_changed()` (updates `the_panel` if it's already visible,
/// never forces it to the front on a plain click).
private void openNode(Node n)
{
    if (auto wn = enclosingWindowNode(n))
        showWindowCanvas(wn);

    // `canvasFor(n)` is legitimately `null` here whenever `n` has no
    // `WindowNode` ancestor at all (a brand-new project's bare
    // `Function`/`decl`/... project root) -- its own non-widget
    // properties page must still load without crashing on a live-widget
    // lookup that has nothing to look up yet. `LiveTree.init` (empty
    // AAs) is exactly what `openLoadedProject()`'s own "no top-level
    // window at all" path already leaves `widgetPanelLoad()` with for the
    // same reason -- see `loadProject()`'s `findAllWindowRoots() ==
    // []` branch.
    auto cv = canvasFor(n);
    widgetPanelLoad([n], cv !is null ? cv.liveTree() : LiveTree.init, projectDir_());
    if (!panelPositionAdjusted_)
    {
        panelPositionAdjusted_ = true;
        // One-time nudge away from the widget bin, matching FLTK's
        // own `open_panel()` (`widget_panel_callbacks.cxx`) -- only
        // applied the very first time the panel is ever shown in a
        // session, so a user who's since dragged it elsewhere never has
        // that choice silently overridden on a later `openNode()` call.
        if (widgetBinPanel.visible()
            && thePanel.x() + thePanel.w() > widgetBinPanel.x()
            && thePanel.x() < widgetBinPanel.x() + widgetBinPanel.w()
            && thePanel.y() + thePanel.h() > widgetBinPanel.y()
            && thePanel.y() < widgetBinPanel.y() + widgetBinPanel.h())
        {
            int scrX, scrY, scrW, scrH;
            fl.screenXYWH(scrX, scrY, scrW, scrH);
            if (widgetBinPanel.y() + widgetBinPanel.h() + thePanel.h() > scrY + scrH)
                thePanel.position(thePanel.x(), widgetBinPanel.y() - thePanel.h() - 30);
            else
                thePanel.position(thePanel.x(), widgetBinPanel.y() + widgetBinPanel.h() + 30);
        }
    }
    thePanel.show();
}

/// Guards the one-time widget-bin-overlap nudge in `openNode()` above.
private bool panelPositionAdjusted_;

/// `&Edit/&Delete Selected` and `ProjectCanvas.onDeleteRequested`
/// (Delete/Backspace with canvas focus) both funnel here -- the more
/// basic, more urgently-missing counterpart to `addWidget()` (this
/// project could add a widget via the palette but had no way to remove one again at all
/// before this, short of hand-editing the `.fl` file -- a real gap
/// noticed while scoping "phase 3, undo" and worth fixing first, since
/// undo over an editor that can't yet delete anything has less to
/// undo).
///
/// Deletes every currently-selected node (multi-select-aware, now that
/// phase 2 makes that meaningful) -- removes each from its parent's
/// `Node.children` (`Node.removeChild()`, the new inverse of
/// `addChild()`) and destroys its live widget via the already-
/// established `fl.core.deleteWidget()` (not a direct `destroy()` --
/// see CLAUDE.md's own note on why calling `destroy()` isn't safe from
/// every call context; this one's a menu/keyboard callback, not a
/// widget's own callback, but there's no reason to reach for the
/// riskier path when the safe one already exists and works). A
/// A top-level `WindowNode` deletes cleanly too: its own canvas just
/// gets torn down along with it (see `removeNodes()`'s own doc
/// comment) -- FLTK has no special protection against this either,
/// since it has no singular "the" project window to protect in the
/// first place.
private void deleteSelected()
{
    auto toDelete = allSelectedNodes();
    if (toDelete.length == 0) return;
    checkpoint();

    removeNodes(toDelete);

    auto cv = activeCanvas();
    if (cv !is null) cv.selectOnly(null);
    browser_.build(projectRoots_);
    browser_.syncSelection(null);
    widgetPanelLoad([], cv !is null ? cv.liveTree() : LiveTree.init, projectDir_());
    if (cv !is null) { cv.redraw(); cv.redrawOverlay(); }

    codeviewAutoRefresh();
}

/// Shared tail of `deleteSelected()`/`cutSelected()`: removes each of
/// `roots` from its own parent's `Node.children` (or, for a top-level
/// project root with no parent -- a `Function`/`decl`/`comment`/... the
/// widget palette's "Code" group added directly to `projectRoots_`,
/// see `addNode()` -- splices it out of `projectRoots_` itself instead)
/// and destroys its live widget (if any). Callers own checkpointing and
/// UI refresh -- this only mutates the tree/live-widget state.
///
/// A `WindowNode` being deleted needs no special protection: `canvases_`/
/// `activeWindow_` handle zero open windows exactly as gracefully as
/// one or several (the same state a brand-new project already starts
/// in), so it just needs its own canvas torn down along with it, same
/// as any other node's live widget.
private void removeNodes(Node[] roots)
{
    import std.algorithm : countUntil, remove;

    foreach (n; roots)
    {
        auto cv = canvasFor(n);

        if (auto wn = cast(WindowNode) n)
        {
            if (cv !is null)
            {
                cv.hide();
                canvases_.remove(wn);
                if (activeWindow_ is wn) activeWindow_ = null;
            }
        }

        bool isMenuItem = cast(MenuItemNode) n !is null;
        Node menuParent = n.parent;

        if (n.parent is null)
        {
            auto idx = projectRoots_.countUntil(n);
            if (idx < 0) continue; // not actually a project root -- shouldn't happen
            projectRoots_ = projectRoots_.remove(idx);
        }
        else
            n.parent.removeChild(n);

        if (isMenuItem && menuParent !is null) refreshLiveMenu(menuParent);

        if (cv is null) continue;
        auto w = cv.liveTree().widgetOf.get(n, null);
        if (w !is null)
        {
            fl.core.deleteWidget(w);
        }
        // Deleting a group destroys its live children with it, so every
        // descendant's entry must go too -- a stale entry points at a
        // destroyed widget and crashes the next walk over `widgetOf`.
        void forget(Node d)
        {
            if (auto dw = cv.liveTree().widgetOf.get(d, null))
            {
                cv.liveTree().nodeOf.remove(dw);
                cv.liveTree().widgetOf.remove(d);
            }
            foreach (c; d.children) forget(c);
        }
        forget(n);
    }
}

/// Every currently-selected node, merging the active canvas's own
/// click-ordered selection (`ProjectCanvas.selected()`) with the node
/// browser's -- the latter is the authoritative superset
/// (`NodeBrowser.selectedNodes()`'s own doc comment: "the source of
/// truth for what is selected"), appending any browser-selected node
/// the canvas doesn't already have. The two diverge specifically when a
/// selected top-level Code-group node (a bare `Function`/`decl`/
/// `comment`/... project root the widget palette's "Code" group adds
/// directly to `projectRoots_`, see `addNode()`) is the browser's own
/// primary selection: `selectFromBrowser()` resolves `activeWindow_`
/// from the primary selection's own enclosing `WindowNode`, which is
/// `null` for a Code-group node (it *contains* windows, it's never
/// *inside* one) -- so the canvas is never told about that selection at
/// all, and `ProjectCanvas.selected()` alone would silently drop it
/// (so Cut/Copy/Duplicate/Delete reach top-level Function/decl/comment/
/// code nodes too, not just widgets inside a window). Preserves the
/// canvas's own click order for whatever it does have (matching
/// `fluid.align_widget`'s own documented click-order convention) --
/// only the appended stragglers fall back to the browser's own
/// unspecified iteration order.
private Node[] allSelectedNodes()
{
    Node[] sel = activeCanvas() !is null ? activeCanvas().selected().dup : [];
    bool[Node] have;
    foreach (n; sel) have[n] = true;
    foreach (n; browser_.selectedNodes())
        if (n !is null && n !in have) { sel ~= n; have[n] = true; }
    return sel;
}

/// `allSelectedNodes()`, filtered down to only the "outermost" members
/// -- excludes any node whose own ancestor is *also* currently selected
/// (so cutting a selected Group along with one of its own
/// already-selected children doesn't serialize that child twice -- once
/// nested inside the Group's own subtree, once again as its own
/// separate top-level entry). A top-level project root (`parent is
/// null`, whether a `WindowNode` or a Code-group node) has no ancestors
/// to test, so it's always included -- see `allSelectedNodes()`'s own
/// doc comment for why a Code-group node can now reach this function at
/// all. Shared by `cutSelected()`/`copySelected()`/`duplicateSelected()`
/// -- every one of them needs "the independent roots of whatever's
/// selected," not the raw flat selection list.
private Node[] topLevelSelection()
{
    auto sel = allSelectedNodes();
    if (sel.length == 0) return [];
    bool[Node] isSel;
    foreach (n; sel) isSel[n] = true;

    Node[] result;
    outer: foreach (n; sel)
    {
        for (Node p = n.parent; p !is null; p = p.parent)
            if (p in isSel) continue outer;
        result ~= n;
    }
    return result;
}

/// In-memory clipboard for Cut/Copy/Paste -- holds the last cut/copied
/// selection as real `.fl` text (`ProjectWriter.generate()`/`Reader.
/// readProject()`, the same round-trip Save/Open already use).
/// Deliberately not FLTK's own `cutfname()` temp file -- the exact
/// same "in-memory instead of numbered temp files" call this port's
/// own `undo.h` port already made, for the identical reason (this
/// editor's own project scale has no need for on-disk persistence
/// here, and a plain string is simpler than file I/O plus cleanup).
private string clipboardText_;

/// `&Edit/C&ut` -- writes the selection to `clipboardText_` (same as
/// `copySelected()`) then removes it from the tree, matching FLTK's
/// `cut_selected()`. A no-op (with a beep, matching FLTK's own
/// `fl_beep()`) if nothing selected.
private void cutSelected()
{
    auto roots = topLevelSelection();
    if (roots.length == 0) { fl.beep(); return; }

    clipboardText_ = new ProjectWriter().generate(roots, projectI18n_);
    checkpoint();
    removeNodes(roots);

    // `removeNodes()` may have just torn down the active canvas itself
    // (one of `roots` was a `WindowNode`), and there may never have
    // been one in the first place (a windowless, Code-group-only
    // selection -- see `allSelectedNodes()`'s own doc comment) --
    // re-resolve rather than trust any pre-removal reference.
    auto cv = activeCanvas();
    if (cv is null)
    {
        browser_.build(projectRoots_);
        browser_.syncSelection(null);
        widgetPanelLoad([], LiveTree.init, projectDir_());
        return;
    }

    cv.selectOnly(null);
    browser_.build(projectRoots_);
    browser_.syncSelection(null);
    widgetPanelLoad([], cv.liveTree(), projectDir_());
    cv.redraw();
    cv.redrawOverlay();

    codeviewAutoRefresh();
}

/// `&Edit/&Copy` -- writes the selection to `clipboardText_` without
/// touching the tree, matching FLTK's `copy_selected()`.
private void copySelected()
{
    auto roots = topLevelSelection();
    if (roots.length == 0) { fl.beep(); return; }

    clipboardText_ = new ProjectWriter().generate(roots, projectI18n_);
}

/// `&Edit/&Paste` -- ported from FLTK's `paste_from_clipboard()`,
/// re-expressed over `clipboardText_` instead of re-reading a temp
/// file. Insertion target matches FLTK's own rule exactly: if the
/// current selection can contain children, paste *into* it (as its
/// last child); otherwise paste *after* it as a sibling (or, with
/// nothing selected at all, into the project's own root window) --
/// FLTK's own additional "unless it's folded in the browser" case
/// isn't replicated (this port's node browser has no per-node
/// collapsed-in-the-tree state to consult the way FLTK's own
/// `folded_` flag does), a real, narrow, deliberate simplification.
///
/// A top-level Code-group target (`target.parent is null`, e.g. a
/// selected `decl`/`comment`) is its own "paste after" case, spliced
/// into `projectRoots_` directly rather than falling back to pasting
/// *inside* the active window -- matches `duplicateSelected()`'s
/// identical handling of the same shape (`topLevelSelection()`'s own
/// doc comment). Also uses `currentSelection()` (browser-aware) instead
/// of `activeCanvas().primarySelection()` alone, and doesn't require an
/// active canvas up front -- both for the same reason `allSelectedNodes()`
/// exists: selecting a Code-group node in the browser resolves
/// `activeWindow_`/the active canvas to `null` (see that function's own
/// doc comment).
private void pasteFromClipboard()
{
    import std.format : format;

    if (clipboardText_.length == 0) { fl.beep(); return; }

    Node[] parsedRoots;
    try
    {
        auto reader = new Reader(clipboardText_);
        parsedRoots = reader.readProject();
    }
    catch (Exception e)
    {
        fl.message(format("Could not paste:\n%s", e.msg));
        return;
    }
    if (parsedRoots.length == 0) return;

    checkpoint();

    Node target = currentSelection();
    Node parentNode;
    bool asSibling, asTopLevelSibling;
    if (target !is null && target.canHaveChildren())
    {
        parentNode = target;
    }
    else if (target !is null && target.parent !is null)
    {
        parentNode = target.parent;
        asSibling = true;
    }
    else if (target !is null)
    {
        asTopLevelSibling = true;
    }
    else
        parentNode = activeWindow_;

    if (asTopLevelSibling)
    {
        import std.algorithm : countUntil;

        auto idx = projectRoots_.countUntil(target);
        auto insertAt = idx < 0 ? projectRoots_.length : idx + 1;
        foreach (root; parsedRoots)
        {
            projectRoots_ = projectRoots_[0 .. insertAt] ~ root ~ projectRoots_[insertAt .. $];
            insertAt++;
        }
    }
    else if (parentNode !is null)
    {
        Node afterNode = target;
        foreach (root; parsedRoots)
        {
            if (asSibling)
            {
                parentNode.insertChildAfter(afterNode, root);
                afterNode = root; // keep a multi-node paste in relative order
            }
            else
                parentNode.addChild(root);
            instantiateUnderLiveParent(parentNode, root);
        }
    }
    else
    {
        // No window, nothing selected at all -- no sane anchor to paste
        // relative to; append directly to the project root list,
        // matching `addNode()`'s own identical "no anchor" fallback.
        projectRoots_ ~= parsedRoots;
    }

    browser_.build(projectRoots_);
    auto cv = activeCanvas();
    if (cv !is null)
    {
        cv.syncSelectionFrom(parsedRoots);
        cv.redraw();
        cv.redrawOverlay();
    }
    browser_.syncSelection(parsedRoots);
    widgetPanelLoad(cv !is null ? cv.selected() : parsedRoots, cv !is null ? cv.liveTree() : LiveTree.init, projectDir_());

    codeviewAutoRefresh();
}

/// `&Edit/Dup&licate` -- ported from FLTK's `duplicate_selected()`,
/// but simpler: FLTK re-derives the lowest-level selected node to
/// insert after (its own tree has no direct "insert after each
/// original, in place" primitive since child order lives in a flat
/// `next`/`prev` list shared across the whole project); this port's
/// real `Node.insertChildAfter()` just does that directly, once per
/// selected root, each one right after its own original (never nested
/// *inside* the thing being duplicated, matching FLTK). Unlike
/// Cut/Copy/Paste, this never touches `clipboardText_` -- serializing
/// then immediately re-parsing is still how a duplicate becomes an
/// independent copy (deep-copying a `Node` subtree directly would need
/// its own clone logic no other feature here needs), it just never
/// leaves the clipboard itself.
///
/// A top-level Code-group root (`orig.parent is null`) is spliced into
/// `projectRoots_` right after `orig`, matching `addNode()`'s own
/// splice exactly.
private void duplicateSelected()
{
    import std.algorithm : countUntil;
    import std.format : format;

    auto roots = topLevelSelection();
    if (roots.length == 0) { fl.beep(); return; }

    string text = new ProjectWriter().generate(roots, projectI18n_);

    Node[] parsedRoots;
    try
    {
        auto reader = new Reader(text);
        parsedRoots = reader.readProject();
    }
    catch (Exception e)
    {
        fl.message(format("Could not duplicate:\n%s", e.msg));
        return;
    }
    if (parsedRoots.length != roots.length) return; // defensive only

    checkpoint();

    foreach (i, orig; roots)
    {
        if (orig.parent is null)
        {
            auto idx = projectRoots_.countUntil(orig);
            if (idx < 0) continue; // defensive only -- shouldn't happen
            projectRoots_ = projectRoots_[0 .. idx + 1] ~ parsedRoots[i] ~ projectRoots_[idx + 1 .. $];
            continue;
        }
        orig.parent.insertChildAfter(orig, parsedRoots[i]);
        instantiateUnderLiveParent(orig.parent, parsedRoots[i]);
    }

    browser_.build(projectRoots_);
    auto cv = activeCanvas();
    if (cv !is null)
    {
        cv.syncSelectionFrom(parsedRoots);
        cv.redraw();
        cv.redrawOverlay();
    }
    browser_.syncSelection(parsedRoots);
    widgetPanelLoad(cv !is null ? cv.selected() : parsedRoots, cv !is null ? cv.liveTree() : LiveTree.init, projectDir_());

    codeviewAutoRefresh();
}

/// Shared tail of `pasteFromClipboard()`/`duplicateSelected()`:
/// instantiates `n` (and its own descendants) as a live widget under
/// `parentNode`'s own live `Group`, merging into `parentNode`'s own
/// window's `LiveTree` -- the recursive counterpart to `insertWidget()`'s
/// single-node `instantiateOne()` call, needed here since a pasted/
/// duplicated subtree can be an arbitrarily deep Group. A no-op if
/// `parentNode`'s window has no canvas, `parentNode` itself has no live
/// widget (e.g. a nested window -- this port's canvas doesn't render
/// those at all, see `instantiate.d`'s own top comment), or `n` isn't
/// itself `WidgetNode`-shaped (a bare `Function`/`decl`/`class`
/// selection has nothing to instantiate) -- the node still lands in
/// the tree either way, just without a live counterpart, matching how
/// an unregistered widget type is already handled elsewhere in this
/// file.
private void instantiateUnderLiveParent(Node parentNode, Node n)
{
    auto cv = canvasFor(parentNode);
    if (cv is null) return;
    auto parentGroup = cast(FlGroup) cv.liveTree().widgetOf.get(parentNode, null);
    if (parentGroup is null) return;
    parentGroup.begin();
    // `instantiateChild()` takes `ref LiveTree` -- bind to a local first
    // (`cv.liveTree()` itself is an rvalue); its AA fields are
    // reference types, so mutations through this local still land in
    // `cv`'s own underlying tables, the same as `insertWidget()`'s own
    // `cv.liveTree().widgetOf[newNode] = widget;` already relies on
    // elsewhere in this file.
    auto live = cv.liveTree();
    instantiateChild(n, live, projectDir_());
    parentGroup.end();
}

/// `&Edit/Select &All` -- simplified relative to FLTK's own
/// `select_all_cb()`, which operates within the *current selection's
/// own parent* first (falling back outward to an ancestor, then the
/// whole project, only if that scope has nothing left to select) --
/// a shape built around FLTK's flat `Node::descendants()` walk
/// that doesn't map cleanly onto this port's own tree. This selects
/// every node in `activeWindow_` outright (matching what "Select All"
/// means the moment nothing more specific is already selected,
/// FLTK's own eventual fallback case) -- a real, deliberate
/// simplification, not an oversight. Scoped to the active window, not
/// the whole project: matches every other keyboard-shortcut-driven edit
/// in this file, and matches FLTK too -- its own `Node::descendants()`
/// walk is scoped by starting point, never spans multiple independent
/// top-level windows either.
private void selectAll()
{
    auto cv = activeCanvas();
    if (cv is null || activeWindow_ is null) return;
    Node[] all;
    void collect(Node n)
    {
        all ~= n;
        foreach (c; n.children) collect(c);
    }
    foreach (c; activeWindow_.children) collect(c);
    if (all.length == 0) return;

    cv.syncSelectionFrom(all);
    browser_.syncSelection(all);
    widgetPanelLoad(all, cv.liveTree(), projectDir_());
    cv.redrawOverlay();
}

/// `&Edit/Select &None`.
private void selectNone()
{
    auto cv = activeCanvas();
    if (cv is null) return;
    cv.selectOnly(null);
    browser_.syncSelection(null);
    widgetPanelLoad([], cv.liveTree(), projectDir_());
    cv.redrawOverlay();
}

/// `&Layout` menu -- ported from `fluid/proj/align_widget.h`/`.cxx`'s
/// `align_widget_cb()` (see `fluid.align_widget`'s own doc comment for
/// the full mechanism and its one deliberate, documented ordering
/// divergence from FLTK). A no-op with no project open or nothing
/// selected. The undo snapshot is taken up front (before mutating, same
/// as every other entry point) but only actually pushed if
/// `alignWidgets()` reports a real change, matching FLTK's own
/// single `Fluid.proj.undo.checkpoint()` call gated by its `changed`
/// flag -- not `checkpoint()` itself, since that helper always commits
/// unconditionally and this is the one call site that doesn't know
/// whether there's anything to commit until after the mutation runs.
private void alignSelected(AlignHow how)
{
    auto cv = activeCanvas();
    if (cv is null || cv.selected().length == 0) return;

    string snapshot = new ProjectWriter().generate(projectRoots_, projectI18n_, [], codeFileName_, null, true, projectDubHeader_, projectSettings_);
    bool changed = alignWidgets(how, cv.selected(), cv.liveTree());
    if (!changed) return;

    undoStack_ ~= snapshot;
    redoStack_ = [];
    dirty_ = true;
    updateShelfTitle();

    cv.redraw();
    cv.redrawOverlay();
    widgetPanelLoad(cv.selected(), cv.liveTree(), projectDir_());

    codeviewAutoRefresh();
}

/// Shared tail of `sortSelectedCmd()`/`earlierSelectedCmd()`/
/// `laterSelectedCmd()`/`groupSelectedCmd()`/`ungroupSelectedCmd()`: all
/// five only know whether anything changed *after* calling into
/// `fluid.node_order`/`fluid.group_ungroup` (mirroring `alignSelected()`'s
/// own "checkpoint only if something actually changed" shape, since
/// plain `checkpoint()` always commits unconditionally), so each one
/// takes its own snapshot up front and calls this to either commit it or
/// discard it and refresh the rest of the UI either way (the browser
/// tree/generated code view need refreshing regardless of whether the
/// undo stack grew, matching `alignSelected()`'s "changed" path exactly,
/// since a no-op run never gets here at all -- every caller returns
/// early on `!changed`, so `refreshAfterReorder()` is only ever reached
/// once something did move).
private void refreshAfterReorder(string snapshot)
{
    undoStack_ ~= snapshot;
    redoStack_ = [];
    dirty_ = true;
    updateShelfTitle();

    browser_.build(projectRoots_);
    auto cv = activeCanvas();
    if (cv !is null)
    {
        browser_.syncSelection(cv.selected());
        cv.redraw();
        cv.redrawOverlay();
        widgetPanelLoad(cv.selected(), cv.liveTree(), projectDir_());
    }

    codeviewAutoRefresh();
}

/// `&Edit/&Sort` -- ported from `Application::sort_selected()`
/// (`Fluid.cxx`). See `fluid.node_order.sortSelected()`'s own doc
/// comment for the actual reorder logic; scoped to `activeWindow_`
/// like every other Edit-menu command in this file (`selectAll()`'s own
/// doc comment).
private void sortSelectedCmd()
{
    auto cv = activeCanvas();
    if (cv is null || activeWindow_ is null) return;

    string snapshot = new ProjectWriter().generate(projectRoots_, projectI18n_, [], codeFileName_, null, true, projectDubHeader_, projectSettings_);
    if (!sortSelected(activeWindow_, cv.liveTree())) return;
    refreshAfterReorder(snapshot);
}

/// `&Edit/&Earlier` -- ported from `earlier_cb()` (`nodes/Node.cxx`).
private void earlierSelectedCmd()
{
    auto cv = activeCanvas();
    if (cv is null || activeWindow_ is null) return;

    string snapshot = new ProjectWriter().generate(projectRoots_, projectI18n_, [], codeFileName_, null, true, projectDubHeader_, projectSettings_);
    if (!moveSelectedEarlier(activeWindow_, cv.liveTree())) return;
    refreshAfterReorder(snapshot);
}

/// `&Edit/&Later` -- ported from `later_cb()` (`nodes/Node.cxx`).
private void laterSelectedCmd()
{
    auto cv = activeCanvas();
    if (cv is null || activeWindow_ is null) return;

    string snapshot = new ProjectWriter().generate(projectRoots_, projectI18n_, [], codeFileName_, null, true, projectDubHeader_, projectSettings_);
    if (!moveSelectedLater(activeWindow_, cv.liveTree())) return;
    refreshAfterReorder(snapshot);
}

/// `&Edit/&Group` -- ported from `group_cb()` (`nodes/Group_Node.cxx`).
/// See `fluid.group_ungroup.groupSelected()`'s own doc comment for the
/// full mechanism (menu-item grouping, `Menu_Node.cxx`'s own separate
/// `group_selected_menuitems()`, isn't ported). Reports FLTK's own two `fl_message()` guards (no
/// selection at all / selection isn't a widget) the same way FLTK
/// does -- these aren't errors, just narrower preconditions than the
/// menu item's own `menuInactive` gate already enforces structurally,
/// so they stay reachable via the `F+7` shortcut with nothing selected.
private void groupSelectedCmd()
{
    auto cv = activeCanvas();
    if (cv is null) return;
    auto q = cv.primarySelection();
    if (q is null) { fl.message("No widgets selected."); return; }
    if (cast(WidgetNode) q is null) { fl.message("Only widgets and menu items can be grouped."); return; }

    string snapshot = new ProjectWriter().generate(projectRoots_, projectI18n_, [], codeFileName_, null, true, projectDubHeader_, projectSettings_);
    auto newGroup = groupSelected(cast(WidgetNode) q, cv.liveTree(), projectDir_());
    if (newGroup is null) { fl.message("Can't create a new group here."); return; }

    // Set the real final selection *before* `refreshAfterReorder()`
    // runs its own `browser_.syncSelection(cv.selected())` -- this used
    // to run that call first (against whatever was selected *before*
    // grouping), then immediately overwrite it with this one, a
    // redundant extra scroll-to-reveal pass for no visible benefit.
    cv.selectOnly(newGroup);
    refreshAfterReorder(snapshot);
    openNode(newGroup);
}

/// `&Edit/Ung&roup` -- ported from `ungroup_cb()` (`nodes/Group_Node.cxx`).
/// See `groupSelectedCmd()`'s own doc comment on the not-ported
/// menu-item-ungroup branch.
private void ungroupSelectedCmd()
{
    auto cv = activeCanvas();
    if (cv is null) return;
    auto q = cv.primarySelection();
    if (q is null) { fl.message("No widgets selected."); return; }
    if (cast(WidgetNode) q is null) { fl.message("Only widgets and menu items can be ungrouped."); return; }

    string snapshot = new ProjectWriter().generate(projectRoots_, projectI18n_, [], codeFileName_, null, true, projectDubHeader_, projectSettings_);
    if (!ungroupSelected(cast(WidgetNode) q, cv.liveTree()))
    {
        fl.message("Only menu widgets inside a group can be ungrouped.");
        return;
    }

    // See `groupSelectedCmd()`'s own comment on why this runs *before*
    // `refreshAfterReorder()` now, not after.
    cv.selectOnly(q);
    refreshAfterReorder(snapshot);
}

/// `&Edit/Fit &Group to Contents` -- not a port of anything FLTK
/// (real FLTK's own Fluid has no equivalent command). Fitting sets the
/// group's bounds to the exact combined bounding box of its contents,
/// shrinking as well as growing (`fixGroupSize(target, true)`). Dragging
/// a widget outside its parent group's own boundary shows this port's
/// overlay warning rather than FLTK's own live auto-grow
/// (`fix_group_size()`, which FLTK only runs automatically right after
/// *creating* a new group -- `groupSelectedCmd()`, just above -- never
/// during an ordinary drag, and which never shrinks back down). This
/// command grows or shrinks a boundary on demand instead of as a side
/// effect of every drag. Operates on the primary selection directly
/// if it's itself a `GroupNode`, else on its immediate parent (this
/// port's tree has no non-container node type that can sit between an
/// ordinary widget and its structural parent -- see
/// `fluid.group_ungroup.isContainerNode()`'s own doc comment -- so an
/// ordinary widget's `.parent` is always already the nearest group
/// worth fitting). Deliberately doesn't extend to a `WindowNode`
/// selection/parent -- growing the top-level canvas window itself would
/// need `applyProperties()`'s `applyXywh` gate lifted for that one case,
/// which currently exists specifically to avoid other, unrelated live
/// side effects on the canvas window (see that call site's own comment)
/// -- out of scope for what was actually asked for here.
///
/// `fixGroupSize()` only touches the `Node` model (`gui_main.d`'s
/// already-established "Node fields are the authoritative source" rule,
/// see `geometryEdited()`'s own doc comment just below). Applying the
/// *new* bounds to the live group widget via `fl.group.Group`'s own
/// `resize()` would cascade and shift every direct child by the group's
/// own position delta (real `Fl_Group::resize()` behavior, ported
/// faithfully in `fl.group.d`) -- exactly the "move contents" semantic
/// this command must *not* have, since the whole point is growing the
/// box around contents that stay exactly where they are. So after
/// resizing the live group, every `WidgetNode` anywhere in its own
/// subtree gets its own model geometry re-applied too
/// (`applyProperties(..., applyXywh: true)`), overwriting whatever the
/// cascade did with each node's own true, unchanged absolute position.
private void fitGroupToContentsCmd()
{
    auto cv = activeCanvas();
    if (cv is null) return;
    auto q = cv.primarySelection();
    if (q is null) { fl.message("No widgets selected."); return; }
    auto wn = cast(WidgetNode) q;
    if (wn is null) { fl.message("Only widgets can be fit to their contents."); return; }

    auto target = cast(GroupNode) wn !is null ? cast(GroupNode) wn : cast(GroupNode) wn.parent;
    if (target is null)
    {
        fl.message("Select a group, or a widget inside one, to fit its boundary to its contents.");
        return;
    }

    string snapshot = new ProjectWriter().generate(projectRoots_, projectI18n_, [], codeFileName_, null, true, projectDubHeader_, projectSettings_);

    int oldX = target.x, oldY = target.y, oldW = target.w, oldH = target.h;
    fixGroupSize(target, true);
    if (target.x == oldX && target.y == oldY && target.w == oldW && target.h == oldH)
        return; // already fits its contents -- no-op, nothing to undo

    auto live = cv.liveTree();
    if (auto liveW = live.widgetOf.get(target, null))
    {
        applyProperties(target, liveW, projectDir_(), true);

        void resync(Node n)
        {
            foreach (child; n.children)
            {
                if (auto wc = cast(WidgetNode) child)
                    if (auto lw = live.widgetOf.get(wc, null))
                        applyProperties(wc, lw, projectDir_(), cast(WindowNode) wc is null);
                resync(child);
            }
        }
        resync(target);
        liveW.redraw();
    }

    refreshAfterReorder(snapshot);
}

/// `ProjectCanvas.onGeometryEdited`'s target (wired in
/// `openLoadedProject()`) -- fired once after a real mouse-driven
/// move/resize drag ends with actual movement (`ProjectCanvas.
/// onBeforeGeometryEdit`, wired alongside it, already called
/// `checkpoint()` before the drag itself began, matching every other
/// mutating entry point's "checkpoint before the edit" convention).
/// Refreshes the property panel's X/Y/W/H display -- it may still be
/// showing the just-dragged widget's now-stale pre-drag values -- and
/// marks the project dirty, the same tail `alignSelected()` already
/// uses after its own geometry-mutating operation.
private void geometryEdited()
{
    dirty_ = true;
    updateShelfTitle();

    auto cv = activeCanvas();
    if (cv !is null)
        widgetPanelLoad(cv.selected(), cv.liveTree(), projectDir_());

    codeviewAutoRefresh();
}

/// Walks up `s`'s ancestor chain and, at the first `Tabs`/`Wizard`
/// ancestor found, switches its visible child to whichever branch
/// leads to `s` -- so selecting a widget that's inside a currently-
/// hidden tab/wizard page (from the browser tree, or a multi-select
/// spanning into one) actually reveals it. Ported from
/// `check_redraw_corresponding_parent()` (`nodes/Window_Node.cxx`);
/// FLTK calls this unconditionally from its own single central
/// `selection_changed()` on every selection change -- a no-op when the
/// target is already visible (`Tabs.value()`/`Wizard.value()` both
/// detect "no change" and do nothing further), so it's harmless to call
/// from both of this port's selection entry points below too, even
/// though a canvas-originated click (see `ProjectCanvas.hitTest()`)
/// can only ever land on an already-visible widget in the first place.
private void revealAncestorTabs(Node s, LiveTree live)
{
    if (s is null) return;
    Node prevParent;
    for (Node i = s; i !is null; i = i.parent)
    {
        auto iw = i in live.widgetOf;
        if (iw !is null && cast(FlGroup)(*iw) !is null && prevParent !is null)
        {
            auto pw = prevParent in live.widgetOf;
            if (pw !is null)
            {
                if (auto tabs = cast(Tabs)(*iw)) { tabs.value(*pw); return; }
                if (auto wiz = cast(Wizard)(*iw)) { wiz.value(*pw); return; }
            }
        }
        if (iw !is null && cast(FlGroup)(*iw) !is null)
            prevParent = i;
    }
}

/// `selected` may contain more than one node (Ctrl/Shift-click, see
/// `ProjectCanvas`'s own top comment), passed straight through to
/// `widgetPanelLoad()` for `browser_`/`activeWindow_` bookkeeping's
/// sake. Multi-select apply is real now: most of `widget_panel.fl`'s
/// field callbacks loop the whole selection, matching FLTK's own
/// real multi-select shape -- a small, FLTK-confirmed set (widget
/// name, Resizable, Hotspot, Border/Modal/Nonmodal) stays single-target
/// because FLTK's own real callback does too, not because this
/// port hasn't caught up.
private void selectFromCanvas(Node[] selected)
{
    browser_.syncSelection(selected);
    // `activeWindow_` is already set correctly by the caller
    // (`showWindowCanvas()`'s own `onSelectionChanged` wiring marks it
    // before invoking this) -- `activeCanvas()` always resolves to the
    // canvas that actually fired this callback.
    auto cv = activeCanvas();
    if (cv !is null)
        revealAncestorTabs(selected.length ? selected[$ - 1] : null, cv.liveTree());
    widgetPanelLoad(selected, cv !is null ? cv.liveTree() : LiveTree.init, projectDir_());
    // Matches FLTK's own `selection_changed()`: called unconditionally
    // on every selection change, not just while the Code View panel is
    // open -- `codeviewUpdatePosition()` tracks `cvCurrent_` regardless
    // (so reopening the panel later immediately shows the right node's
    // code) and does its own internal "is the panel even visible" guard
    // before touching any widget.
    codeviewUpdatePosition(selected.length ? selected[$ - 1] : null);
}

/// Triggered by the node browser's own tree, which spans every open
/// window (and every windowless project root) at once -- unlike
/// `selectFromCanvas()`, there's no already-known originating canvas
/// here, so this resolves `activeWindow_` itself from whichever window
/// `selected`'s own primary member belongs to.
private void selectFromBrowser(Node[] selected)
{
    auto primary = selected.length ? selected[$ - 1] : null;
    activeWindow_ = primary is null ? null : enclosingWindowNode(primary);

    auto cv = activeCanvas();
    if (cv !is null)
    {
        revealAncestorTabs(primary, cv.liveTree());
        cv.syncSelectionFrom(selected);
    }
    // Loads the panel regardless of whether a canvas exists yet -- a
    // selected `FunctionNode` (or any other Code-group node) in a
    // project with no `WindowNode` at all has no live widget to show on
    // a canvas, but its own non-widget properties page still needs to
    // reflect the click.
    widgetPanelLoad(selected, cv !is null ? cv.liveTree() : LiveTree.init, projectDir_());
    codeviewUpdatePosition(primary);
}

private void saveProject()
{
    if (projectPath_.length == 0) { saveProjectAs(); return; }
    writeProjectTo(projectPath_);
}

private void saveProjectAs()
{
    import std.file : exists;
    import std.format : format;
    import std.path : baseName;
    import fluid.path_util : ensureFlExtension;

    string typed = fileChooser("Save .fl file as", "*.fl", projectPath_);
    if (typed.length == 0) return;
    // Typing `example` saves `example.fl` (FLTK's Fluid writes it as-is).
    string path = ensureFlExtension(typed);
    // The chooser's own "already exists, replace?" prompt ran against the
    // name as typed; if adding the extension turned it into a different,
    // already-existing file, that file has not been confirmed yet.
    if (path != typed && exists(path)
        && fl.ask.choice(format("The file \"%s\" already exists.\nDo you want to replace it?", baseName(path)),
            "Cancel", "Replace", null) == 0)
        return;
    projectPath_ = path;
    writeProjectTo(path);
}

private void writeProjectTo(string path)
{
    if (projectRoots_.length == 0) return;
    // See `raw_cpp_guard.d`'s own module doc comment for the incident
    // this guards against: `project_writer.d`'s round-trip is
    // deliberately lossy, and saving a raw, unconverted FLTK-C++ `.fl`
    // file (opened only as read-only reference material) through it
    // once silently corrupted `panels/widget_panel.fl` for real.
    if (looksLikeRawCpp(projectRoots_))
    {
        fl.ask.alert("This project contains raw FLTK C++ (a C preprocessor "
            ~ "directive or a C++ namespace-qualified class override), not "
            ~ "this project's own D-embedded `.fl` dialect. Saving it through "
            ~ "this editor would silently lose content -- not saved.");
        return;
    }
    auto text = new ProjectWriter().generate(projectRoots_, projectI18n_, shellCommandList.list, codeFileName_,
        layoutList, false, projectDubHeader_, projectSettings_);
    try
    {
        write(path, text);
        dirty_ = false;
        updateShelfTitle();
        if (history_ !is null)
        {
            history_.update(appPrefs, path);
            rebuildRecentFilesMenu();
        }
    }
    catch (Exception e)
        stderr.writefln("fluid: could not write %s: %s", path, e.msg);
}

/// `&File/&Write Strings` -- ported from FLTK's `Project::write_
/// strings()`. Requires a saved project (prompts Save As first if
/// none exists yet, matching FLTK's own `if (!proj_filename) {
/// save_project_file(nullptr); if (!proj_filename) return; }`); the
/// output filename is the project's own basename with its extension
/// swapped for `.txt`/`.po`/`.msg` per `projectI18n_.type`, written
/// alongside the project file -- matching FLTK's own `stringsfile_
/// path()`'s interactive-mode branch (this port has no batch-mode
/// equivalent of that function's other branch, which writes to the
/// launch directory instead).
private void writeStringsFile()
{
    import std.path : dirName, baseName, buildPath;
    import std.format : format;
    import fluid.string_writer : writeStrings;

    if (projectRoots_.length == 0) return;

    if (projectPath_.length == 0)
    {
        saveProjectAs();
        if (projectPath_.length == 0) return;
    }

    string ext;
    final switch (projectI18n_.type)
    {
    case I18nType.none: ext = ".txt"; break;
    case I18nType.gnu: ext = ".po"; break;
    case I18nType.posix: ext = ".msg"; break;
    }

    string outPath = buildPath(dirName(projectPath_), filenameSetExt(baseName(projectPath_), ext));

    if (writeStrings(projectRoots_, projectI18n_, outPath) != 0)
    {
        stderr.writefln("fluid: could not write %s", outPath);
        fl.message(format("Could not write %s", outPath));
    }
    else
        showCompletionDialog(format("Wrote %s", outPath));
}

/// `fluid.shell_process.ShellFlags.shellSaveSourceCode`'s own save
/// action -- ported from FLTK's `Fluid.write_code_files()`. Unlike
/// `writeStringsFile()`/`saveProject()`, the interactive editor never
/// had a "generate the real D code and write it to disk" action at all
/// before this: `codeview_panel.d`'s own `Writer().generate()` call is
/// display-only (renders into the Code View panel's own text buffer,
/// never touches disk). Default output path/shape matches the headless
/// `fluid -c` CLI (`fluid.app`'s own `Writer().generate()` call): the
/// project's own basename with a `.d` extension, alongside the `.fl`
/// file -- overridable via `codeFileName()` (`settings_panel.fl`'s
/// Project-tab "Code File:" field), the interactive equivalent of that
/// same CLI's own `-o` flag.
private void writeCodeFile()
{
    import std.path : stripExtension, isAbsolute, buildPath, extension;
    import std.format : format;
    import fluid.code_writer : Writer;

    if (projectRoots_.length == 0) return;

    if (projectPath_.length == 0)
    {
        saveProjectAs();
        if (projectPath_.length == 0) return;
    }

    string outPath = codeFilePath_();
    auto writer = new Writer();
    string code;
    try
        code = writer.generate(projectRoots_, projectDir_(), projectI18n_, projectDubHeader_, projectSettings_);
    catch (Exception e)
    {
        // Matches `fluid.compile`'s own headless `-c` path: a hard,
        // loud failure here (an unknown boxtype/type/labeltype
        // keyword -- see code_writer.d's translateBoxtype()/
        // translateTypeWord()/translateLabeltype()) is deliberate, not
        // silently-degraded-and-move-on. Reported via `fl.message()`
        // rather than `exit(1)` since this is the interactive editor,
        // not the CLI -- the project itself is left untouched, nothing
        // gets written.
        stderr.writefln("fluid: could not generate %s: %s", outPath, e.msg);
        fl.message(format("Could not generate %s:\n%s", outPath, e.msg));
        return;
    }

    try
    {
        write(outPath, code);
        if (projectSettings_.writeMergebackData)
            rememberCodePath(projectPath_, outPath);
        showCompletionDialog(format("Wrote %s", outPath));
    }
    catch (Exception e)
    {
        stderr.writefln("fluid: could not write %s: %s", outPath, e.msg);
        fl.message(format("Could not write %s:\n%s", outPath, e.msg));
    }
}

/**
 * Prints a preview snapshot of each currently-shown design window --
 * `&File/&Print...`'s real implementation. Ported
 * from `Application::print_snapshots()` (`fluid/Fluid.cxx`), adapted to
 * this port's tree-shaped `Node` model: FLTK's own linear scan
 * (`proj.tree.all_widgets()`, filtering for `Window_Node` and its
 * `shown()` state) becomes `findAllWindowRoots(projectRoots_)` (already
 * real, used by `saveAsTemplate()`/`newFromTemplate()` above) plus a
 * `canvases_.get(wn, null)` lookup for each root's live `ProjectCanvas`
 * -- exactly the same "Node -> live Window" mapping every other
 * project-tree-to-canvas operation in this file already uses.
 *
 * Reuses real, already-ported infrastructure with no new plumbing
 * needed: `fl.printer.Printer` (the real interactive print dialog,
 * `smoke-tests/printer.d`) and `fl.paged_device.PagedDevice.
 * printWindow()` (a real port of `Fl_Paged_Device::print_window()`,
 * itself a synonym for `drawDecoratedWindow()` -- captures the real
 * on-screen title bar, not just the widget content). Per-page layout
 * (date/time centered, "page/total" right-aligned, project basename
 * left-aligned, all at `fl_height()`, then the window itself scaled
 * down -- never up -- to fit the printable area and centered via
 * `origin(w/2, h/2)` + a `-decoratedW/2, -decoratedH/2` draw offset)
 * matches FLTK line for line.
 *
 * One deliberate difference: FLTK's own scan builds its window
 * list and applies `Fl::first_window()`-style unconditional inclusion
 * of every `Window_Node` regardless of `shown()`, silently overwriting
 * unshown entries in place (a real but easy-to-misread FLTK
 * pattern -- see this function's own history in `PORTING.md` for the
 * full trace) so only shown windows survive into the final list; this
 * port's own filter (`if (cv !is null && cv.shown())`) does the same
 * filtering more directly. A project with no currently-shown design
 * window prints nothing and shows no dialog at all, matching FLTK's
 * own `if (printjob.start_job(num_windows, ...))` early-return when
 * `num_windows == 0` (the dialog itself handles a zero-page job as an
 * immediate cancel).
 */
private void printSnapshots()
{
    import std.datetime : Clock;
    import std.format : format;
    import std.path : baseName;

    WindowNode[] shownWindows;
    foreach (wn; findAllWindowRoots(projectRoots_))
    {
        auto cv = canvases_.get(wn, null);
        if (cv !is null && cv.shown())
            shownWindows ~= wn;
    }
    if (shownWindows.length == 0) return;

    auto printer = new Printer();
    int from, to;
    string err;
    int result = printer.beginJob(cast(int) shownWindows.length, from, to, err);
    if (result == 1) return; // cancelled
    if (result != 0)
    {
        fl.message(format("Print job failed to start:\n%s", err.length ? err : "(no message)"));
        return;
    }

    string projectName = projectPath_.length ? baseName(projectPath_) : "Untitled";
    int pageCount = 0;
    int totalPages = to - from + 1;

    foreach (winpage, wn; shownWindows)
    {
        if (cast(int)(winpage + 1) < from || cast(int)(winpage + 1) > to) continue;

        printer.beginPage();
        int w, h;
        printer.printableRect(w, h);

        fl.fl_font(fl.helvetica, 12);
        fl.fl_color(fl.black);
        string date = Clock.currTime().toSimpleString();
        fl.fl_draw(date, (w - cast(int) fl.width(date)) / 2, fl.height());
        pageCount++;
        string pageLabel = format("%d/%d", pageCount, totalPages);
        fl.fl_draw(pageLabel, w - cast(int) fl.width(pageLabel), fl.height());
        fl.fl_draw(projectName, 0, fl.height());

        auto win = canvases_[wn];
        int ww = win.decoratedW();
        int hh = win.decoratedH();
        float scale = 1, scaleX = 1, scaleY = 1;
        if (ww > w) scaleX = cast(float) w / ww;
        if (hh > h) scaleY = cast(float) h / hh;
        if (scaleX < scale) scale = scaleX;
        if (scaleY < scale) scale = scaleY;
        if (scale < 1)
        {
            printer.scale(scale);
            printer.printableRect(w, h);
        }
        printer.origin(w / 2, h / 2);
        printer.printWindow(win, -ww / 2, -hh / 2);
        printer.endPage();
    }
    printer.endJob();
}

/// Where `writeCodeFile()` writes the generated `.d` file: the project's
/// own basename with a `.d` extension, or the "Code File:" setting
/// (`codeFileName_`), relative to the project's directory unless
/// absolute. Requires a saved project.
private string codeFilePath_()
{
    import std.path : stripExtension, isAbsolute, buildPath, extension;

    if (codeFileName_.length == 0)
        return projectPath_.stripExtension() ~ ".d";
    string name = codeFileName_;
    if (name.extension().length == 0) name ~= ".d";
    return name.isAbsolute() ? name : buildPath(projectDir_(), name);
}

/// Shows or hides `&File/MergeBack Code` to match the project's
/// MergeBack setting. FLTK does this from `App_Menu_Bar::handle()`
/// on `FL_BEFORE_MENU`; here the item is updated whenever the setting
/// can change (project load/new/undo, and the Settings dialog's
/// checkbox, which calls this).
void updateMergebackMenu()
{
    if (menu_ is null) return;
    int idx = menu_.findIndex("&File/MergeBack Code");
    if (idx < 0) return;
    // `menu()` hands out a const view; flipping one item's flag is the
    // same cast FLTK's `App_Menu_Bar::handle()` makes.
    auto item = cast(MenuItem*) (menu_.menu() + idx);
    if (projectSettings_.writeMergebackData)
        item.show();
    else
        item.hide();
}

private bool mergebackBusy_;

/// Merges edits made to the generated code file back into the open
/// project. Ported from `mergeback_code_files()`
/// (`fluid/proj/mergeback.cxx`). The code file is the one most recently
/// written for this project (see `rememberCodePath()`), else the
/// default location `writeCodeFile()` would use. `chatty` also reports
/// "not enabled", "no modifications" and "no code file" in dialogs.
/// Returns 2 if already running (a dialog can re-enter through an
/// app-activate event), 1 if the project has no file yet, 0 if MergeBack
/// is off, otherwise `Mergeback.mergeBack()`'s result.
private int mergebackCodeFiles(bool chatty)
{
    import std.file : exists;
    import std.format : format;

    if (mergebackBusy_) return 2;
    mergebackBusy_ = true;
    scope (exit) mergebackBusy_ = false;

    if (projectPath_.length == 0) return 1;
    if (!projectSettings_.writeMergebackData)
    {
        if (chatty)
            fl.message("MergeBack is not enabled for this project.\n"
                ~ "Please enable MergeBack in the project settings\n"
                ~ "dialog and re-save the project file and the code.");
        return 0;
    }

    string codeFilename = rememberedCodePath(projectPath_);
    if (codeFilename.length == 0 || !exists(codeFilename))
        codeFilename = codeFilePath_();

    auto mergeback = new Mergeback(projectRoots_);
    mergeback.beforeApply = () { checkpoint(); };
    int c = mergeback.mergeBack(codeFilename, projectPath_, Task.interactive);
    if (c > 0)
    {
        // The nodes' text changed: repaint the tree and reload the
        // property panel so neither shows the old text.
        browser_.recalcTree();
        browser_.redraw();
        if (widgetPanelCurrent() !is null)
        {
            if (auto cv = activeCanvas())
                widgetPanelLoad(cv.selected(), cv.liveTree(), projectDir_());
            refreshCodeFromNode();
        }
        codeviewAutoRefresh();
    }
    if (chatty)
    {
        if (c == 0)
            fl.message(format("Comparing\n  \"%s\"\nto\n  \"%s\"\n\n"
                ~ "MergeBack found no external modifications\nin the source code.",
                codeFilename, projectPath_));
        if (c == -2)
            fl.message("No corresponding source code file found.");
    }
    return c;
}

/// When the application becomes active again, check the code file for
/// edits made in an external editor in the meantime. Ported from
/// `start_auto_mergeback()`. Only a platform driver that delivers
/// `Event.appActivate` triggers it.
private void startAutoMergeback()
{
    fl.core.addHandler((Event event) {
        if (event == Event.appActivate && !autoMergebackPending_)
        {
            autoMergebackPending_ = true;
            fl.core.addTimeout(0.5, () {
                autoMergebackPending_ = false;
                mergebackCodeFiles(false);
            });
        }
        return 0;
    });
}

private bool autoMergebackPending_;

/// "Show Completion Dialogs" (`settings_panel.fl`'s General tab,
/// `appPrefs` key `show_completion_dialogs`, default on) -- ported
/// from FLTK's own `completion_button->value()` check, present at
/// the tail of both `Fluid.write_code_files()` and `Project::write_
/// strings()` (`Fluid.cxx`/`Project.cxx`): a small `fl_message()`
/// confirming a *successful* write, purely a courtesy notification --
/// never shown for a failed write, which is a separate, unconditional
/// alert at each call site above. FLTK also takes a one-shot
/// `dont_show_completion_dialog` parameter on `write_code_files()` for
/// callers that want to suppress just one call regardless of the
/// persisted setting (no current caller here needs that -- both this
/// port's call sites are direct, interactive "&File/Write ..." actions,
/// not the kind of internal/automated write FLTK uses that
/// parameter for).
private void showCompletionDialog(string text)
{
    int show;
    appPrefs.get("show_completion_dialogs", show, 1);
    if (show) fl.message(text);
}

/// Ported from FLTK's `expand_macros()`'s own five call sites
/// (`Fluid.proj.basename()`/`projectfile_path()`/etc.) -- computes this
/// session's own `fluid.shell_process.ShellMacros`, the project-
/// specific values `runShellCommand()`'s `@BASENAME@`/etc. expand to.
/// An unsaved project (`projectPath_` unset) leaves every field but
/// `tmpDir` empty, matching this function's only real caller
/// (`fluid.shell_command`'s `ShellCommand.run()`, via `macroProvider`)
/// always checking for a saved project first the same way
/// `writeStringsFile()`/`writeCodeFile()` already do.
private ShellMacros currentShellMacros()
{
    import std.path : dirName, baseName, stripExtension, buildPath;
    import std.file : tempDir;

    ShellMacros m;
    m.tmpDir = tempDir();
    if (projectPath_.length == 0) return m;

    m.baseName = baseName(projectPath_).stripExtension();
    m.projectFilePath = dirName(projectPath_) ~ "/";
    m.projectFileName = baseName(projectPath_);

    string codePath = projectPath_.stripExtension() ~ ".d";
    m.codeFilePath = dirName(codePath) ~ "/";
    m.codeFileName = baseName(codePath);

    string ext;
    final switch (projectI18n_.type)
    {
    case I18nType.none: ext = ".txt"; break;
    case I18nType.gnu: ext = ".po"; break;
    case I18nType.posix: ext = ".msg"; break;
    }
    string textPath = buildPath(dirName(projectPath_), filenameSetExt(baseName(projectPath_), ext));
    m.textFilePath = dirName(textPath) ~ "/";
    m.textFileName = baseName(textPath);

    return m;
}

/// Wires `fluid.shell_process`'s three outward delegates -- called once
/// from `runEditor()`, matching how every other startup-scoped
/// cross-module hook gets wired exactly once (per-canvas hooks like
/// `ProjectCanvas.onSelectionChanged` are the exception -- those get
/// (re)wired once per window, in `showWindowCanvas()`, not here).
/// `onPrepareSave`/`onOutputLine`/`onDone` are the runner's
/// own full contract; showing `shellRunWindow` before a run starts is
/// deliberately *not* this module's job either (see `fluid.shell_
/// process`'s own top comment on the layering) -- that's `fluid.shell_
/// command`'s `ShellCommand.run()` call to make, since only it knows
/// the `shellDontShowTerminal` flag for a given saved command.
private void wireShellProcess()
{
    fluid.shell_process.onPrepareSave = (flags) {
        if (flags & shellSaveProject) saveProject();
        if (flags & shellSaveSourceCode) writeCodeFile();
        if (flags & shellSaveStrings) writeStringsFile();
    };
    fluid.shell_process.onOutputLine = (line) { shellRunTerminal.append(line); };
    fluid.shell_process.onDone = (success) {
        shellRunTerminal.append("... END SHELL COMMAND ...\n");
        shellRunButton.activate();
        shellRunWindow.label("FLUID Shell");
        fl.beep();
    };
}

/// Reads `appPrefs`'s own `"external_editor_command"` key directly --
/// mirrors FLTK's `Fluid.external_editor_command`, but there's no
/// single owning object to read a field off of here the way there is
/// in FLTK's `Application` class, so this (and `useExternalEditor()`
/// below) just reads the same key `settings_panel.fl`'s own
/// `editorCommandField`/`useExternalEditorButton` write, the same "read
/// straight from `appPrefs`, no widget round-trip" shape `fluid.shell_
/// command.ShellCommand.run()` already established for
/// `shellDontShowTerminal`.
private string externalEditorCommand()
{
    string s;
    appPrefs.get("external_editor_command", s, "");
    return s;
}

/// ditto -- `"use_external_editor"`.
private bool useExternalEditor()
{
    int b;
    appPrefs.get("use_external_editor", b, 0);
    return b != 0;
}

/// One `ExternalCodeEditor` per code-bearing `Node` that's ever had one
/// opened, kept here (not on the `Node` itself) since `fluid.node`/
/// `fluid.*_node` deliberately stay free of any `import fl` at all
/// (the same architectural line `fluid.instantiate.LiveTree` already
/// draws, see that struct's own doc comment) -- `ExternalCodeEditor`
/// itself pulls in `fl.ask`/`fl.core`. Entries persist across
/// selection changes (an editor stays open, and keeps being polled,
/// even after the user selects a different node in the tree) but not
/// across projects -- `closeProject()` clears the table, matching
/// FLTK's own per-`Code_Node` `editor_` member's lifetime (dies
/// with the node).
private ExternalCodeEditor[Node] externalEditors_;

/// `widgetPanelOnOpenExternalEditor`'s target -- ported from FLTK's
/// `Code_Node::open()`, but as an explicit button rather than
/// FLTK's overload-the-same-"open"-gesture design: this port's
/// property panel always shows the inline `codeField_` editor (there's
/// no separate FLTK-style fallback panel to switch away from), so
/// "use an external editor instead" needs its own affordance rather
/// than a global on/off flag silently changing what a click on the
/// node does.
private void openExternalEditor(Node n)
{
    if (!useExternalEditor())
    {
        fl.message("External editor use is turned off.\nEnable \"Use for Code Nodes\" in Settings -> General first.");
        return;
    }
    string cmd = externalEditorCommand();
    if (cmd.length == 0)
    {
        fl.message("No external editor command is configured.\nSet one in Settings -> General -> External Editor.");
        return;
    }

    auto existing = n in externalEditors_;
    ExternalCodeEditor editor;
    if (existing is null)
    {
        editor = new ExternalCodeEditor();
        externalEditors_[n] = editor;
    }
    else
        editor = *existing;

    // openEditor() itself pops an "Editor Already Open" alert and
    // returns 0 (not an error) if this same instance is already
    // editing -- nothing extra needed here for that case.
    editor.openEditor(cmd, n.instanceName);
}

/// `ExternalCodeEditor.setUpdateTimerCallback()`'s target, registered
/// once in `runEditor()` -- ported from FLTK's `Fluid.cxx`'s own
/// `external_editor_timer()`. Walks the whole project tree (not just
/// the currently-selected node -- an editor can stay open on a node
/// the user has since navigated away from) looking for external-editor
/// changes to pull in, then re-arms itself while any editor across the
/// whole project is still open, matching FLTK's own "recheck after
/// reaping, in case reaping just closed the last one" comment.
private void externalEditorTimer()
{
    if (ExternalCodeEditor.editorsOpen() > 0)
    {
        bool modified;
        foreach (root; projectRoots_)
            modified |= pollExternalEditors(root);
        if (modified)
        {
            dirty_ = true;
            updateShelfTitle();
            foreach (cv; canvases_.byValue()) cv.redraw();
        }
    }
    if (ExternalCodeEditor.editorsOpen() > 0)
        fl.core.repeatTimeout(2.0, () { externalEditorTimer(); });
}

/// Recursive half of `externalEditorTimer()` -- for every code-bearing
/// node (`CodeNode`, or a `DeclNode` that isn't a `DataNode`, matching
/// `panels/widget_panel.fl`'s own `isCodeBody` check) with an open editor:
/// pulls in a changed file's text (`ExternalCodeEditor.handleChanges()`,
/// writing straight to `n.instanceName` -- Save reads the in-memory
/// tree directly, so this alone is enough for the change to survive a
/// save regardless of whether the panel is displaying this node right
/// now), refreshes the property panel's own code buffer if `n` happens
/// to be the currently-loaded node, and reaps the editor if it's
/// exited in the meantime (FLTK's own belt-and-suspenders
/// `is_editing()`-then-`reap_editor()` pair, in case the process died
/// between polls without going through `reapEditor()`'s own exit path
/// first). Returns whether anything changed, so the caller only marks
/// the project dirty/redraws once, not per node.
private bool pollExternalEditors(Node n)
{
    bool modified;

    auto codeNode = cast(CodeNode) n;
    auto declNode = cast(DeclNode) n;
    auto dataNode = cast(DataNode) n;
    bool isCodeBody = codeNode !is null || (declNode !is null && dataNode is null);
    if (isCodeBody)
    {
        auto existing = n in externalEditors_;
        if (existing !is null)
        {
            auto editor = *existing;
            string code;
            if (editor.handleChanges(code) == 1)
            {
                n.instanceName = code;
                modified = true;
                if (widgetPanelCurrent() is n)
                    refreshCodeFromNode();
            }
            if (editor.isEditing())
                editor.reapEditor();
        }
    }

    foreach (c; n.children)
        modified |= pollExternalEditors(c);

    return modified;
}

/// Opens `history_.abspath[i]` (a no-op if that slot is empty),
/// guarded the same way every other project-discarding menu action is.
private void openRecentFile(int i)
{
    if (i < 0 || i >= history_.abspath.length) return;
    string path = history_.abspath[i];
    if (path.length == 0) return;
    if (!confirmDiscardChanges()) return;
    loadProject(path);
}

/// Returns a callback closing over `i` via a real function *parameter*
/// (not a loop variable) -- the unambiguously-correct capture shape
/// regardless of D's own foreach-closure-capture subtleties, used by
/// `rebuildRecentFilesMenu()`'s own loop below.
private void delegate(Widget) recentFileMenuCallback(int i)
{
    return (w) { openRecentFile(i); };
}

private void delegate(Widget) quitMenuCallback()
{
    return (w) { doQuit(); };
}

/// The one real quit path -- shared by `&File/&Quit` and `shelf_`'s own
/// window-close-box callback, matching FLTK's own single
/// `Application::quit()`, used identically by both the `&Quit` menu
/// item and `main_window`'s `callback(exit_cb)` (`exit_cb` just calls
/// `Fluid.quit()` -- confirmed by reading `app/Menu.cxx`/`Fluid.cxx`
/// directly rather than assumed). Saves `shelf_`/`widgetBinPanel`'s own
/// current positions before exiting -- see `positionWindow()`'s own
/// doc comment for why `thePanel` is deliberately excluded, matching
/// FLTK's own narrower persistence scope exactly.
private void doQuit()
{
    if (!confirmDiscardChanges()) return;
    saveWindowPosition(shelf_, "main_window_pos");
    saveWindowPosition(widgetBinPanel, "widgetbin_pos", false);
    fl.hideAllWindows();
}

/// `fluid/app/history` port's own menu integration -- ported in
/// spirit from FLTK's `app/Menu.cxx`, which wires 10 pre-
/// allocated `Fl_Menu_Item` slots (`Fluid.history_item[10]`) directly
/// into the static main-menu array and relabels/hides them in place
/// as `History::load()`/`update()` run. This port's own `fl.menu_.
/// Menu_` has no by-index relabel-and-rehide primitive to update
/// existing items that way (only `replace(i, label)` for the label
/// text alone, no way to reassign a callback or hide/show a specific
/// index from outside the class) -- extending that core API is a
/// separate, bigger task than this one `fluid/app/` file warrants, so
/// this rebuilds the whole flat set instead: removes every menu path
/// this function itself added last time (`recentMenuPaths_`, tracked
/// exactly for this purpose) plus `&File/&Quit`, then re-adds fresh
/// items for every non-empty `history_` slot (`Ctrl+1`..`Ctrl+9`,
/// matching FLTK's own shortcuts) followed by `&File/&Quit` again
/// -- re-adding Quit last is what keeps it pinned to the bottom of
/// `&File` across rebuilds, since a plain `add()` appends to the end
/// of whichever submenu the path resolves into. Observably equivalent
/// to FLTK's hide-empty-slots behavior (no visible entry for an
/// empty slot either way), just built differently.
/// The Settings dialog's "# Recent Files:" spinner (`settings_panel.
/// fl`'s General tab) calls this after changing `appPrefs`'s own
/// `recent_files` key -- matches FLTK's own `recent_spinner`
/// callback exactly (`Fluid.preferences.set("recent_files", ...);
/// Fluid.history.load();`), just also rebuilding the live `&File`
/// menu afterward, since this port shows the recent-files list as
/// real menu items rather than FLTK's own pre-allocated/hidden-
/// in-place `Fl_Menu_Item` slots (see `rebuildRecentFilesMenu()`'s own
/// doc comment) and a smaller max would otherwise leave stale entries
/// visible until the next full menu rebuild.
void reloadRecentFiles()
{
    if (history_ is null) return;
    history_.load(appPrefs);
    rebuildRecentFilesMenu();
}

private void rebuildRecentFilesMenu()
{
    foreach_reverse (path; recentMenuPaths_)
    {
        int idx = menu_.findIndex(path);
        if (idx >= 0) menu_.remove(idx);
    }
    recentMenuPaths_ = [];

    int quitIdx = menu_.findIndex("&File/&Quit");
    if (quitIdx >= 0) menu_.remove(quitIdx);

    int shortcutDigit = '1';
    // Captured directly from `add()`'s own return value rather than a
    // later `findIndex(path)` re-lookup: `fl_filename_shortened()`-style
    // display paths can legitimately collide between two different
    // history entries -- e.g. two different projects both named
    // "test.fl" in different directories -- and `findIndex()` returns
    // the *first* matching item's index, not necessarily the actually-
    // last-added one, which would place the divider on the wrong item.
    // A plain captured index has no such ambiguity.
    int lastAddedIdx = -1;
    foreach (i; 0 .. history_.abspath.length)
    {
        if (history_.abspath[i].length == 0) continue;
        // `relpath[i]` is a path -- almost certainly contains '/',
        // which `Menu_.add()`'s own path syntax treats as a submenu
        // separator unless escaped (backslash, matching FLTK's
        // own `\/` convention -- see `menu_.d`'s own doc comment).
        // Escaping '\\' first, then '/', keeps the label a single
        // flat `&File` entry instead of silently fragmenting into a
        // nested submenu tree for every path segment.
        import std.array : replace;

        string escaped = history_.relpath[i].replace("\\", "\\\\").replace("/", "\\/");
        string path = "&File/" ~ escaped;
        int shortcut = shortcutDigit <= '9' ? stateCtrl + shortcutDigit : 0;
        lastAddedIdx = menu_.add(path, shortcut, recentFileMenuCallback(cast(int) i));
        recentMenuPaths_ ~= path;
        shortcutDigit++;
    }

    // Divider between the recent-files group and `&Quit`: FLTK's own
    // fixed 10-slot array always has `FL_MENU_DIVIDER` on its own last
    // slot regardless of how many are actually populated; this port's
    // dynamic list needs it placed on whichever item ends up last
    // instead.
    if (lastAddedIdx >= 0)
        menu_.mode(lastAddedIdx, menu_.mode(lastAddedIdx) | menuDivider);

    menu_.add("&File/&Quit", stateCtrl + 'q', quitMenuCallback());
}

/// Full `"&Shell/..."` menu paths this function itself added last time
/// -- same tracked-then-removed-then-readded shape `recentMenuPaths_`
/// already established, same reason (`fl.menu_.Menu_` has no by-index
/// relabel-in-place primitive).
private string[] shellMenuPaths_;

/// Ported from FLTK's `Fd_Shell_Command_List::rebuild_shell_menu()`
/// -- but built the same way `rebuildRecentFilesMenu()` already is
/// (remove-then-readd through `fl.menu_.Menu_`'s own path-based API),
/// not FLTK's own raw `Fl_Menu_Item` array reallocation. Wired as
/// `shell_settings.onShellListChanged` (fired on every add/duplicate/
/// remove/import/label/shortcut/condition edit) and called once at
/// startup. Only `ShellCommand.isActive()` entries get a real menu
/// item, matching FLTK's own `is_active()`-gated menu-building
/// exactly; the trailing `&Shell/&Customize...` entry (FLTK's own
/// `Fd_Shell_Command_List::default_menu`) opens the Settings dialog
/// straight to the Shell tab.
private void rebuildShellMenu()
{
    foreach_reverse (path; shellMenuPaths_)
    {
        int idx = menu_.findIndex(path);
        if (idx >= 0) menu_.remove(idx);
    }
    shellMenuPaths_ = [];

    int customizeIdx = menu_.findIndex("&Shell/&Customize...");
    if (customizeIdx >= 0) menu_.remove(customizeIdx);

    // Captured directly from `add()`'s own return value, not a later
    // `findIndex(path)` re-lookup -- see `rebuildRecentFilesMenu()`'s
    // own doc comment for why: two shell commands with the same label
    // would make `findIndex()` return the *first* match, not
    // necessarily the actually-last-added one.
    int lastAddedIdx = -1;
    foreach (cmd; shellCommandList.list)
    {
        if (!cmd.isActive()) continue;
        import std.array : replace;

        string escaped = cmd.label.replace("\\", "\\\\").replace("/", "\\/");
        string path = "&Shell/" ~ escaped;
        lastAddedIdx = menu_.add(path, cmd.shortcut, shellMenuCallback(cmd));
        shellMenuPaths_ ~= path;
    }

    // Divider between the shell-command group and `&Customize...` --
    // same "no active commands means no divider needed" edge case
    // `rebuildRecentFilesMenu()`'s own divider handling covers.
    if (lastAddedIdx >= 0)
        menu_.mode(lastAddedIdx, menu_.mode(lastAddedIdx) | menuDivider);

    menu_.add("&Shell/&Customize...", stateAlt + 'x', (w) { settingsShowShellTab(); });
}

/// Returns a callback closing over `cmd` via a real function
/// *parameter* (not a loop variable) -- same unambiguously-correct
/// capture shape `recentFileMenuCallback()` already established, used
/// by `rebuildShellMenu()`'s own loop above.
private void delegate(Widget) shellMenuCallback(ShellCommand cmd)
{
    return (w) { cmd.run(); };
}

private string[] layoutSuiteMenuPaths_;

/// Rebuilds the `&Layout/&Presets/*` radio group from `layoutList`
/// itself -- same "remove the old tracked paths, re-`add()` from the
/// live list" shape as `rebuildShellMenu()` just above, needed once
/// `layoutList.add()`/`rename()`/`remove()` (Settings dialog Layout
/// tab, `settings_panel.fl`) can actually change what suites exist,
/// unlike this menu's own old hardcoded "&FLTK"/"&Grid" pair. Called
/// once at startup and after every structural `layoutList` change
/// (add/rename/remove/storage-switch/suite-select/load), from either
/// this menu's own callbacks or the Settings dialog's.
///
/// The "&Presets" pair (FLTK, Grid) look "oddly identical" because
/// FLTK's own `@fd_beaker` icon symbol is reused identically for both;
/// that icon symbol itself isn't ported here (`fl_add_symbol()` glyphs
/// are omitted throughout, see `PORTING.md`'s `fluid/panels/` row).
void rebuildLayoutMenu()
{
    foreach_reverse (path; layoutSuiteMenuPaths_)
    {
        int idx = menu_.findIndex(path);
        if (idx >= 0) menu_.remove(idx);
    }
    layoutSuiteMenuPaths_ = [];

    foreach (i; 0 .. layoutList.size())
    {
        import std.array : replace;

        string escaped = layoutList[i].name.replace("\\", "\\\\").replace("/", "\\/");
        string path = "&Layout/&Presets/" ~ escaped;
        int idx = menu_.add(path, 0, layoutSuiteMenuCallback(i), menuRadio);
        if (layoutList.currentSuiteIndex() == i)
            menu_.mode(idx, menu_.mode(idx) | menuValue);
        layoutSuiteMenuPaths_ ~= path;
    }

    // The 3 preset radios are fixed siblings (always exactly
    // Application/Dialog/Toolbox) -- only their checked state needs
    // refreshing here, never their existence.
    static immutable string[3] presetPaths = [
        "&Layout/&Application", "&Layout/&Dialog", "&Layout/&Toolbox",
    ];
    foreach (i, path; presetPaths)
    {
        int idx = menu_.findIndex(path);
        if (idx < 0) continue;
        int f = menu_.mode(idx) & ~menuValue;
        if (layoutList.currentPresetIndex() == i) f |= menuValue;
        menu_.mode(idx, f);
    }
}

/// Returns a callback closing over `i` via a real function parameter,
/// same reasoning as `shellMenuCallback()` above.
private void delegate(Widget) layoutSuiteMenuCallback(int i)
{
    return (w) { layoutList.currentSuite(i); layoutMenuChanged(); };
}

/// Shared tail for every one of *this menu's own* Layout callbacks
/// (suite/preset radios): persists the new selection, refreshes the
/// Settings dialog's Layout tab if it's open, and re-syncs this menu's
/// own checkmarks. The Settings dialog's own Layout-tab callbacks
/// (`settings_panel.fl`) call `rebuildLayoutMenu()` directly instead
/// (they already know the dialog is open, no `layoutRefreshTabIfOpen()`
/// guard needed there).
private void layoutMenuChanged()
{
    layoutSaveUser();
    layoutRefreshTabIfOpen();
    rebuildLayoutMenu();
}

/// `&Help/&About` -- `fluid/panels/about_panel.fl`'s own generated
/// `makeAboutPanel()` doesn't call `.show()` itself (matching FLTK's
/// identical convention: a named Function only builds the window,
/// leaving showing it to the caller -- see `code_writer.d`'s own
/// `inMainFunction_` gate), and doesn't guard against being called
/// twice either (it would just construct a second window and reassign
/// the module-level `aboutPanel` variable out from under the first) --
/// same `if (window is null) { make...(); }` guard-then-show shape
/// `samples/test/checkers.d`'s own `copyright_cb()`/`intel_cb()` already
/// establish for this exact pattern.
private void showAboutPanel()
{
    if (aboutPanel is null)
        makeAboutPanel();
    aboutPanel.show();
}

/// Lazily-created, reused across calls -- matches FLTK's own
/// `Application::help_dialog` (a single persistent `Fl_Help_Dialog*`,
/// never recreated).
private HelpDialog helpDialog_;

/// `&Help/&Rapid development with FLUID...` (`name == "fluid.html"`) and
/// `&Help/&FLTK Programmers Manual...` (`name == "index.html"`) --
/// ported from `Application::show_help()` (`Fluid.cxx`). Tries
/// `$FLTK_DOCDIR/name` first, exactly like FLTK (this project ships
/// none of FLTK's own HTML doc tree, so that lookup only succeeds if the
/// user points `FLTK_DOCDIR` at a real one); falls back to FLTK's
/// own per-name special cases otherwise: a small canned page for
/// "fluid.html" (adapted to describe this port's own single-`.d`-file
/// output instead of FLTK's `.cxx`/`.h` pair -- see the Build
/// commands section of CLAUDE.md; FLTK's own embedded flow-chart
/// image is skipped, since no PNG asset for it has been ported into
/// this project -- a real, narrow, separate gap, not silently dropped),
/// and `fl.openUri()` to the real fltk.org docs page for everything
/// else, including "index.html" -- matching FLTK's own `fl_open_uri()`
/// call for that case exactly (this port's `openUri()`, `fl.filename`'s
/// real Linux port).
private void showHelp(string name)
{
    import std.process : environment;
    import std.file : exists;

    if (helpDialog_ is null) helpDialog_ = new HelpDialog();

    auto docdir = environment.get("FLTK_DOCDIR");
    string helpname = docdir ? docdir ~ "/" ~ name : "";

    if (helpname.length && exists(helpname))
    {
        helpDialog_.load(helpname);
    }
    else if (name == "fluid.html")
    {
        helpDialog_.value(
            "<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.01 Transitional//EN\">\n"
            ~ "<html><head><title>FLTK: Programming with FLUID</title></head><body>\n"
            ~ "<h2>What is FLUID?</h2>\n"
            ~ "The Fast Light User Interface Designer, or FLUID, is a graphical editor "
            ~ "that is used to produce FLTK source code. FLUID edits and saves its state "
            ~ "in <code>.fl</code> files. These files are text, and you can (with care) "
            ~ "edit them in a text editor, perhaps to get some special effects.<p>\n"
            ~ "FLUID can \"compile\" the <code>.fl</code> file into a single generated "
            ~ "<code>.d</code> source file that defines all the objects from the "
            ~ "<code>.fl</code> file. FLUID also supports localization (Internationalization) "
            ~ "of label strings using message files.<p>\n"
            ~ "<p>More information about FLTK itself is available online at <a href="
            ~ "\"https://www.fltk.org/doc-1.5/fluid.html\">https://www.fltk.org/</a>"
            ~ "</body></html>"
        );
    }
    else
    {
        string msg;
        // Matches `fl.help_view`'s own caller convention (`if
        // (!openUri(f, urimsg)) ...`) -- surface a real failure (no
        // browser configured, etc.) instead of silently discarding it.
        if (!openUri("https://www.fltk.org/doc-1.5/" ~ name, msg))
            fl.message(msg);
        return;
    }
    helpDialog_.show();
}
