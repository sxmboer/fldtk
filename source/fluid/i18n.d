/**
 * Project-wide internationalization settings -- ported from FLTK
 * FLTK's `fluid/proj/i18n.h`/`.cxx` (`fluid::proj::I18n`). Unlike
 * every other `fluid/proj/` piece ported so far, this isn't a
 * `Node`-tree concept at all: it's a handful of project-wide settings
 * (which translation mechanism to use, if any, plus the handful of
 * strings/macro-names each one needs), parsed/written once per
 * project from a flat `key value` list at the very top of a `.fl`
 * file (alongside `version`/`header_name`/`code_name`), not nested
 * inside any node -- see `project_reader.d`'s `Reader.i18n` field and
 * `project_writer.d`'s `ProjectWriter.generate()`'s own `i18n`
 * parameter for where it's actually threaded through, and
 * `gui_main.d`'s `projectI18n_` for how the interactive editor keeps
 * it alive across load/checkpoint/undo/redo/save.
 *
 * Consumed by `code_writer.d`: `i18nWrap()` wraps every literal
 * string in the configured translation call once `type` is non-`none`,
 * and `writeI18nPrologue()` emits the support declarations -- the
 * `gnuInclude`/`posixInclude` field as a D `import` (the field holds a
 * D module name, not a C header), inside `version (<conditional>)`
 * when `gnuConditional`/`posixConditional` is set, with an `else`
 * branch of pass-through fallbacks. D has no text-substitution macros,
 * so FLTK's `#ifndef gettext #define gettext(text) text #endif`
 * becomes an ordinary identity function defined in that `else` branch.
 * A C-style value (`<libintl.h>`, `"gettext.h"`, as found in `.fl`
 * files written by real Fluid) is reported in a comment instead of
 * being emitted. The POSIX catalog variable and its `catopen()` call
 * are not generated; the program declares them next to the module the
 * include field names.
 *
 * Menu item label translation is real --
 * `code_writer.d`'s `writeMenuItemLiteral()` wraps `MenuItem` labels
 * via the same `i18nWrap()` every other label/tooltip in that file
 * already goes through, a single-phase `gettext(...)`/`catgets(...)`
 * call at the point the label is emitted. This is deliberately
 * *simpler* than FLTK's own `Menu_Node.cxx` mechanism (a static
 * `Fl_Menu_Item[]` array entry wrapped in `gnu_static_function`/
 * `gettext_noop()` at declaration time, then re-wrapped and reassigned
 * to `label()` via a *separate* runtime statement once the menu
 * actually exists) -- but that two-phase dance is purely a workaround
 * for FLTK's array being a real C static aggregate initializer,
 * evaluated before `main()` runs, which can't call a function at all.
 * This port's own generated `MenuItem[]` array is never a static
 * initializer -- it's always a plain local `auto arr = [...]` built
 * inside whatever function is already executing, genuine runtime code
 * from the moment it exists, exactly like an ordinary widget's
 * `w.label(...)` call already is (and, confirmed against FLTK's
 * own `Widget_Node.cxx`, exactly how FLTK itself already writes
 * *widget* labels too -- `gnu_function`/`gettext()` directly, no
 * `gettext_noop()` step, for the identical reason). See `code_writer.d`'s
 * own `writeMenuItemLiteral()` doc comment for the full writeup.
 */
module fluid.i18n;

/// Mirrors FLTK's `fluid::I18n_Type` (`FL/proj/i18n.h`) exactly --
/// same three values, same underlying numbers (round-tripped as a
/// plain int in `.fl` text via `i18n_type %d`).
enum I18nType
{
    none = 0,
    gnu = 1,
    posix = 2,
}

/// Mirrors FLTK's `fluid::proj::I18n` field-for-field, minus the
/// `Project&` back-reference (this port has no `Project` singleton --
/// see `gui_main.d`'s own module-level state instead) and the
/// `read()`/`write()` methods themselves (ported as free functions in
/// `project_reader.d`/`project_writer.d`, matching how every other
/// `.fl`-level property is parsed/written in this port).
struct I18nSettings
{
    I18nType type = I18nType.none;

    string gnuInclude = "fl.gettext";
    string gnuConditional = "";
    string gnuFunction = "gettext";
    string gnuStaticFunction = "gettext_noop";

    string posixInclude = "";
    string posixConditional = "";
    string posixFile = "";
    string posixSet = "1";
}
