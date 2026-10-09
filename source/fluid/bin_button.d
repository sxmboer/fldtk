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
// The "Window" button is FLTK's `Bin_Window_Button`: a click calls
// `binButtonCb` (`gui_main.d`), which special-cases `typeName() ==
// "Window"` to call `createWindowNode()`, matching FLTK's own
// `Window_Node::make()` (walk up for a `Function`/code-block ancestor,
// `fl_message("Please select a function")` if none exists). Dragging it
// shows a borderless preview window following the pointer, and releasing
// calls `onWindowDropped` with the pointer's screen position, where
// `gui_main.d` creates the window. There is no drag-and-drop payload for
// it, since a window is not a widget a canvas can receive.

module fluid.bin_button;

import fl;

/// Called when the Window button is dropped on the desktop, with the
/// pointer's screen position. Set by `gui_main.d`.
void delegate(int x, int y) onWindowDropped;

final class BinButton : Button
{
    private string typeName_;

    /// The preview window dragged with the Window button; null otherwise.
    private Window dragWin_;

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
            if (typeName_ == "Window")
            {
                if (!fl.eventIsClick())
                {
                    if (dragWin_ is null)
                    {
                        FlGroup.current(null);
                        dragWin_ = new Window(0, 0, 480, 320);
                        dragWin_.border(false);
                        dragWin_.setNonModal();
                    }
                    dragWin_.position(fl.eventXRoot() + 1, fl.eventYRoot() + 1);
                    dragWin_.show();
                }
                return ret;
            }
            if (!fl.eventIsClick())
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

        case Event.release:
            if (dragWin_ !is null)
            {
                dragWin_.hide();
                fl.core.deleteWidget(dragWin_);
                dragWin_ = null;
                int xr = fl.eventXRoot(), yr = fl.eventYRoot();
                // Released over the button or not, this is a drop, not a click.
                fl.eventX(x() - 1);
                super.handle(event);
                if (onWindowDropped !is null) onWindowDropped(xr, yr);
                return 1;
            }
            break;

        default:
            break;
        }
        return super.handle(event);
    }
}
