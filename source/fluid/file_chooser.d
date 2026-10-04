/**
 * A single, shared file-picker helper used everywhere Fluid needs one
 * -- ported from FLTK's `fluid/io/file_chooser.h`/`.cxx`
 * (`fluid::io::filechooser()`). FLTK genuinely funnels *every*
 * chooser dialog in the whole app through this one function: project
 * Open/Save As (`Fluid.cxx`), the Image/Data "Browse..." buttons
 * (`Image_Asset.cxx`'s `ui_find_image()`, `widget_panel.cxx`), and
 * settings/shell-command file pickers -- not just image assets, the
 * scope this module might otherwise be mistaken for given it was
 * ported alongside the `fluid/proj/Image_Asset` work.
 *
 * Needed zero new core-library work: `fl.native_file_chooser.
 * NativeFileChooser` (a native-OS-dialog-shaped picker, falling back
 * to FLTK's own themed dialog where no native backend is wired up --
 * see that module's own doc comment) and `fl.filename`'s `filename
 * Absolute()`/`filenamePath()`/`filenameName()`/`filenameRelative()`
 * were both already real, complete ports; this is purely new glue
 * code combining them the way FLTK's own `filechooser()` does.
 *
 * `errorMessage` is faithful, not a gap:
 * `Fl_Native_File_Chooser::show()` FLTK documents three distinct
 * outcomes (`-1` error, `0` picked, `1` cancelled), and FLTK's own
 * `filechooser()` reports the `-1` case via `fl_alert(error_message,
 * fnfc.errmsg())` -- but FLTK's own FLTK-driver backend (the one
 * this port actually implements, see `fl.native_file_chooser`'s own
 * module comment) *never produces* the `-1` case at all:
 * `Fl_Native_File_Chooser_FLTK_Driver::show()` only ever returns `0`/
 * `1`, and its own private `errmsg(const char*)` setter is never
 * called anywhere in that whole source file. This port's
 * `NativeFileChooser.show()`/`.errmsg()` match that exactly, letter
 * for letter -- `errorMessage` is accepted here for API parity with
 * every FLTK call site (same reason every call site still passes
 * one), genuinely unreachable today, and stays that way until this
 * port's own GTK/Kdialog/Zenity backend (already tracked as
 * "Deferred" in `fl.native_file_chooser`'s own module comment) exists
 * to have a real OS-level failure to report -- not a separate gap of
 * its own to fix ahead of that.
 *
 * `fallbackPath`'s own FLTK fallback-of-the-fallback is `Fluid.
 * launch_path()` (the directory Fluid itself was launched from, a
 * `Project`-independent app-global this port has no equivalent
 * singleton for) -- this port uses `"."` (the process's own current
 * directory) instead, matching the same default already used
 * elsewhere in this editor (e.g. `gui_main.d`'s `projectDir_()`).
 */
module fluid.file_chooser;

import fl.native_file_chooser : NativeFileChooser, BrowseType, saveasConfirm, newFolder, preview, useFilterExt;
import fl.filename : filenameAbsolute, filenamePath, filenameName, filenameRelative;

/// Mirrors FLTK's `fluid::io::FileChooserType` exactly.
enum FileChooserType
{
    loadFile,
    saveFile,
}

/// Mirrors FLTK's `fluid::io::FileChooserPath` exactly.
enum FileChooserPath
{
    absolutePath,
    relativePath,
}

/// Shows a load/save file dialog and returns the chosen path (absolute
/// or relative to the current directory, per `pathType`), or `""` if
/// the user cancelled. `filter` is FLTK's own `"Description\t*.ext"`
/// filter-string syntax (`fl.file_chooser`'s own convention, unchanged
/// here). See this module's own doc comment on `errorMessage` --
/// confirmed unreachable today, matching FLTK's own FLTK-driver
/// backend exactly, not a bug.
string filechooser(
    FileChooserType type,
    FileChooserPath pathType,
    string title,
    string errorMessage,
    string presetPath,
    string fallbackPath,
    string filter,
)
{
    auto btype = type == FileChooserType.loadFile ? BrowseType.browseFile : BrowseType.browseSaveFile;
    auto fnfc = new NativeFileChooser(btype);
    fnfc.options(type == FileChooserType.loadFile ? preview : (newFolder | saveasConfirm | useFilterExt));
    fnfc.title(title);
    fnfc.filter(filter);

    string presetDirectory, presetFilename;
    if (presetPath.length)
    {
        string preset = filenameAbsolute(presetPath);
        presetDirectory = filenamePath(preset);
        presetFilename = filenameName(preset);
    }
    else
    {
        presetDirectory = filenameAbsolute(fallbackPath.length ? fallbackPath : ".");
        presetFilename = "";
    }
    fnfc.directory(presetDirectory);
    fnfc.presetFile(presetFilename);

    if (fnfc.show() != 0)
    {
        // Cancelled -- see this module's own doc comment on why the
        // FLTK `-1` (error) case, and `errorMessage`/`fnfc.errmsg()`
        // with it, is unreachable in this port today.
        return "";
    }

    return pathType == FileChooserPath.absolutePath
        ? filenameAbsolute(fnfc.filename())
        : filenameRelative(fnfc.filename());
}
