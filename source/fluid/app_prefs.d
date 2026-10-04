/*
 * The interactive editor's single, shared `fl.preferences.Preferences`
 * instance -- vendor "fldtk", application "fluid" (deliberately
 * distinct from real Fluid's own "fltk.org"/"fluid" pair, so this
 * port's own preferences file never collides with a real installed
 * FLTK Fluid's on the same machine). Matches FLTK's own single
 * `Fluid.preferences` global used by every panel that persists UI
 * state (`fluid/panels/template_panel.fl`'s own `Fluid.preferences`
 * calls, `settings_panel.fl`'s, ...) -- factored out here rather than
 * each panel constructing (and so opening/reading) its own separate
 * `Preferences` instance for the same underlying file: two live
 * `Preferences` objects open against the same (root, vendor,
 * application) tuple would each hold their own in-memory copy, and
 * whichever flushes last would silently clobber the other's unsaved
 * changes.
 */
module fluid.app_prefs;

import fl;

Preferences appPrefs;

static this()
{
    appPrefs = new Preferences(rootUserL, "fldtk", "fluid");
}
