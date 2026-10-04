/**
 * Project-wide code-generation flags that live in the leading Options
 * block of a `.fl` file, next to `i18n_*`/`code_name`/`dub_header`.
 *
 * Ported from the corresponding fields of FLTK's `fluid::Project`
 * (`fluid/proj/Project.h`). Only flags that still mean something for
 * generated D live here: the C/C++ header-file flags
 * (`do_not_include_H_from_C`, `include_guard`, `utf8_in_src`,
 * `avoid_early_includes`) have no D equivalent and are parsed and
 * dropped by `fluid.project_reader.Reader`.
 *
 * Threaded through `fluid.project_reader.Reader.settings` (parse),
 * `fluid.project_writer.ProjectWriter.generate()` (write) and
 * `fluid.code_writer.Writer.generate()` (the main consumer), with
 * `gui_main.d`'s `projectSettings_` holding the live copy for the
 * interactive editor.
 */
module fluid.project_settings;

/// See the module comment.
struct ProjectSettings
{
    /// `use_FL_COMMAND` (bare flag in the `.fl` file). When set, the
    /// modifier bits of every generated widget and menu-item shortcut
    /// are written as the platform-neutral `stateCommand`/`stateControl`
    /// names instead of the literal `stateCtrl`/`stateMeta` bits, so the
    /// shortcut follows the platform's command key (Ctrl on X11/
    /// Wayland/Windows, Cmd on macOS).
    bool useFlCommand;

    /// `mergeback 1` in the `.fl` file (FLTK's
    /// `write_mergeback_data`). When set, every node's `uid` is written
    /// to the `.fl` file and the generated code gets tag lines around
    /// its editable blocks, so `fluid.mergeback.Mergeback` can merge
    /// edits made in the generated file back into the project.
    bool writeMergebackData;
}
