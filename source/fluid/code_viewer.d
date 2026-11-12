// Ported from `fluid/widgets/Code_Viewer.h`/`.cxx` -- the read-only view
// behind the Code View window's Source and Project tabs
// (`fluid/panels/codeview_panel.fl`, via a `class {CodeViewer}` override).
//
// The node highlight has to stand out against the syntax-colored text:
// the text area is drawn in a light gray and the highlighted code in the
// display's own color (white by default), so the highlighted part is the
// brightest. The gray is 60% the display's color and 40% a mix of 90%
// background and 10% foreground color. Worked out at draw time,
// not once at construction, so it follows a later scheme/background
// change.
//
// Not ported: `Code_Viewer`'s constructor's key-binding removal
// (`default_key_function(kf_ignore)`, `remove_all_key_bindings()`,
// `cursor_style(CARET_CURSOR)`): those belong to `Fl_Text_Editor`, and
// this port's Code View uses plain `TextDisplay`s, which have no key bindings.
module fluid.code_viewer;

import fl;

/// A `TextDisplay` drawn on a soft gray, with highlighted text in the
/// display's own color.
class CodeViewer : TextDisplay
{
    private Color highlight_ = background2Color;

    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
    }

    override void draw()
    {
        const own = color();
        highlight_ = own;
        color(colorAverage(own, colorAverage(backgroundColor, foregroundColor, 0.9f), 0.6f));
        scope (exit) color(own);
        super.draw();
    }

    protected override Color highlightBackground(Color base, bool focused)
    {
        return highlight_;
    }
}
