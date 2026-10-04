// The Widget Bin's own top-level window -- saves its position to
// `appPrefs` the moment it's actually moved, rather than only at app
// quit the way FLTK's `widgetbin_panel` does (beyond-FLTK).
//
// A hand-written companion to a Fluid-generated panel, not itself
// Fluid-generated -- `function_panel.fl`'s own `widgetBinPanel` window
// node uses `class {WidgetBinWindow}` to opt into this.

module fluid.widget_bin_window;

import fl;
import fluid.app_prefs : appPrefs;

final class WidgetBinWindow : Window
{
    // `Window` node codegen (`code_writer.d`'s `writeWindowNode()`)
    // always emits the plain `(w, h, label)` constructor for a window
    // -- position is an app-level runtime concern (`gui_main.d`'s own
    // `positionWindow()` call, right after construction), never baked
    // into generated code -- so only that overload is needed here.
    // Defining an explicit constructor at all (rather than just
    // inheriting `Window`'s) is what's needed here, since D does not
    // inherit a base class's constructors automatically.
    this(int w, int h, string label = null)
    {
        super(w, h, label);
    }

    /// `Fl_Window::resize()` is FLTK's single entry point for both a
    /// position change and a size change alike (a `ConfigureNotify`
    /// from the window manager, or an app-initiated move/resize,
    /// funnels through here either way) -- checking the *old* position
    /// against the incoming one before calling `super.resize()` is what
    /// distinguishes "the user actually dragged this window" from
    /// every other reason this might fire.
    override void resize(int X, int Y, int W, int H)
    {
        bool moved = (X != x() || Y != y());
        super.resize(X, Y, W, H);

        // `shown()` -- not `visible()` -- is the real guard: false for
        // every `resize()` call this window's own construction and
        // `gui_main.d`'s own startup `positionWindow()` call (`Widget.
        // position()` is implemented as `resize(x, y, w_, h_)`) trigger
        // before the window is ever actually mapped on screen, so
        // neither would otherwise spuriously overwrite a just-restored
        // saved position with itself. Only becomes true once `.show()`
        // has actually run.
        if (moved && shown())
        {
            auto pos = new Preferences(appPrefs, "widgetbin_pos");
            pos.set("x", X);
            pos.set("y", Y);
            pos.flush();
        }
    }
}
