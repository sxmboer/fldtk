// Ported from `fluid/widgets/Code_Viewer.h`/`.cxx` -- the read-only view
// behind the Code View window's Source and Project tabs
// (`fluid/panels/codeview_panel.fl`, via a `class {CodeViewer}` override).
//
// FLTK's `Code_Viewer::draw()` tricks `Fl_Text_Display` into using a
// bearable highlight color: `TextDisplay` derives the color of the
// node-selection highlight from the global selection color (which is
// often a saturated blue or purple that makes syntax-colored text hard to
// read), so `draw()` temporarily replaces `FL_SELECTION_COLOR` with a
// light gray -- 90% background, 10% foreground -- around the base draw, then
// restores it. Done at draw time, not once at construction, so the highlight
// follows a later scheme/background change.
//
// Not ported: `Code_Viewer`'s constructor's key-binding removal
// (`default_key_function(kf_ignore)`, `remove_all_key_bindings()`,
// `cursor_style(CARET_CURSOR)`): those belong to `Fl_Text_Editor`, and
// this port's Code View uses plain `TextDisplay`s, which have no key bindings.
module fluid.code_viewer;

import fl;

/// A `TextDisplay` whose selection/highlight color is a soft gray blended
/// from the current background and foreground colors.
class CodeViewer : TextDisplay
{
    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
    }

    override void draw()
    {
        // The member `selectionColor()` shadows the global palette slot.
        enum slot = fl.enumerations.selectionColor;
        const saved = getColor(slot);
        setColor(slot, colorAverage(backgroundColor, foregroundColor, 0.9f));
        scope (exit) setColor(slot, saved);
        super.draw();
    }
}
