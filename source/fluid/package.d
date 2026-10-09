/*
 * Aggregator module, matching `fl/package.d`'s own pattern: lets any
 * consumer write a single `import fluid;` instead of piecemeal
 * `import fluid.xxx : Yyy;` lines. The one real name clash this would
 * otherwise hit (`fl.preferences.
 * Node` vs. `fluid.node.Node` -- see that module's own top comment and
 * `PORTING.md`'s `FL/Fl_Preferences.H` row) is resolved by renaming
 * the `fl`-side type instead.
 *
 * Deliberately excludes `fluid.app`/`fluid.bootstrap`: both are real
 * `void main(string[] args)` entry points for two separate `dub.sdl`
 * build configurations (`"fluid"` and `"bootstrap"`, see `fluid/
 * dub.sdl` and CONVENTIONS.md's own build-commands section) that are never
 * linked together into one binary -- `public import`ing both here
 * would force any consumer of this aggregator to compile both `main()`s
 * into the same translation unit, an unconditional error neither
 * config's own real, narrower source-file list ever hits today.
 * Neither module has any other reason to be imported by anything else
 * anyway (they're drivers, not libraries), so excluding them costs
 * nothing.
 *
 * Every other `fluid.*` module is included. A type-name sweep (every
 * `class`/`struct`/`enum` declared across all of them) found zero
 * internal clashes, and a function-name sweep found only same-module
 * overloads (false positives) and `private` helpers (invisible to
 * `public import` regardless) -- see the git history around this
 * file's own introduction for the exact commands, if that sweep ever
 * needs re-running after a new module is added.
 */
module fluid;

public import fluid.align_widget;
public import fluid.app_prefs;
public import fluid.bin_button;
public import fluid.canvas;
public import fluid.class_node;
public import fluid.code_block_node;
public import fluid.code_highlight;
public import fluid.code_node;
public import fluid.code_viewer;
public import fluid.code_writer;
public import fluid.color_menu;
public import fluid.comment_node;
public import fluid.comment_presets;
public import fluid.compile;
public import fluid.data_node;
public import fluid.decl_block_node;
public import fluid.decl_node;
public import fluid.edit_session;
public import fluid.external_code_editor;
public import fluid.factory;
public import fluid.file_chooser;
public import fluid.flex_node;
public import fluid.font_menu;
public import fluid.formula_input;
public import fluid.function_node;
public import fluid.grid_node;
public import fluid.group_node;
public import fluid.group_ungroup;
public import fluid.gui_main;
public import fluid.i18n;
public import fluid.instantiate;
public import fluid.layout_edit;
public import fluid.layout_suite;
public import fluid.menu_item_node;
public import fluid.menu_owner_node;
public import fluid.mergeback;
public import fluid.node;
public import fluid.node_browser;
public import fluid.node_order;
public import fluid.path_util;
public import fluid.pixmaps;
public import fluid.pixmaps_xpm;
public import fluid.project_history;
public import fluid.project_reader;
public import fluid.project_settings;
public import fluid.project_writer;
public import fluid.raw_cpp_guard;
public import fluid.shell_command;
public import fluid.shell_process;
public import fluid.shell_settings;
public import fluid.snap_action;
public import fluid.string_writer;
public import fluid.subtypes;
public import fluid.widget_bin_window;
public import fluid.widget_class_node;
public import fluid.widget_node;
public import fluid.window_node;
