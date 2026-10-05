// Ported from `fluid/widgets/Bin_Button.h`/`.cxx` -- the `Fl_Button`
// subclass used by the widget palette (`fluid/panels/function_panel.fl`'s
// `widgetBinPanel`, via a `class {BinButton}` override on every
// button) to let the user either click a button (adds the widget at a
// default position, via the shared `binButtonCb` hook that .fl file
// declares) or drag it onto the canvas (drops it at the exact point the
// mouse released), matching FLTK's own dual-purpose Bin_Button.
//
// The drag path works by faking a "dragged outside the button" FL_DRAG/
// FL_RELEASE pair (via `fl.core.eventX(int)`) to un-arm the button
// without firing its own click callback, then starting a real
// cross-window drag-and-drop (`fl.copy()` + `fl.dnd()`) carrying the
// widget's type name as the payload -- the same XDND infrastructure
// `source/examples/howto_drag_and_drop.d` exercises. See
// `fluid.canvas.ProjectCanvas.handle()`'s `Event.paste` case for the
// receiving side.
//
// `typeName()`/`typeName(string)` (getter/setter, not a constructor
// parameter) exist because every generated widget-node constructor call
// is a fixed `ClassName(x, y, w, h[, label])` shape (`code_writer.d`'s
// `writeWidgetNode()`) -- `function_panel.fl` sets each button's type
// name via its own `setup {o.typeName("...");}` property instead,
// matching how any other post-construction-only field in this dialect
// is wired (see that .fl file's own top comment).
//
// Deliberately not ported: `Bin_Window_Button`, FLTK's separate
// button class for dragging a new top-level window's floating preview
// onto the desktop at the release point. This port's "Window" bin
// button uses a different mechanism entirely: `binButtonCb`
// (`gui_main.d`) special-cases `typeName() == "Window"` to call
// `createWindowNode()` on click, matching FLTK's own
// `Window_Node::make()` (walk up for a `Function`/code-block ancestor,
// `fl_message("Please select a function")` if none exists) -- see that
// function's own doc comment. `handle()`'s own `Event.drag` case
// suppresses drag-and-drop specifically for the Window button: its
// `typeName()` was never a real `fluid.instantiate`-registered widget
// type, so dropping it the normal way reaches `gui_main.d`'s generic
// `dropWidget()`/`insertWidget()`, which has no "Window" special case
// and would silently create a structurally-nested `WindowNode` with no
// live widget at all. Dragging the Window button behaves like an
// ordinary click instead, matching FLTK's own lack of a
// drag-and-drop counterpart for it.

module fluid.bin_button;

import fl;

final class BinButton : Button
{
    private string typeName_;

    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
    }

    /// The `fluid.instantiate`/`fluid.factory` registered type name this
    /// button creates (e.g. "Button", "CheckButton") -- also the raw
    /// payload string a drag-and-drop of this button carries.
    string typeName() const { return typeName_; }
    /// ditto
    void typeName(string v) { typeName_ = v; }

    override int handle(Event event)
    {
        int ret = 0;
        switch (event)
        {
        case Event.push:
            super.handle(event);
            return 1; // make sure we keep getting drag events

        case Event.drag:
            ret = super.handle(event);
            // "Window" has no DND drop target to receive it -- see this
            // module's own top comment for the confusing broken state
            // (a structurally-nested `WindowNode` with no live widget)
            // that dragging it used to reach.
            if (!fl.eventIsClick() && typeName_ != "Window")
            {
                // fake a drag outside of the widget
                fl.eventX(x() - 1);
                super.handle(Event.drag);
                // fake a button release
                super.handle(Event.release);
                // make it into a dnd event
                fl.copy(typeName_, 0);
                fl.dnd();
                return 1;
            }
            return ret;

        default:
            break;
        }
        return super.handle(event);
    }
}
