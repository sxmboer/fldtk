/*
 * The window of the document browsers, `fl.markdown_dialog.MarkdownDialog`
 * and `fl.html_dialog.HtmlDialog`: the mouse controls a web browser has.
 *
 *  - The mouse's back and forward side buttons go back and forward
 *    through the pages visited.
 *  - Ctrl with the wheel makes the text larger (wheel up) or smaller
 *    (wheel down).
 *
 * The window sees these events before the widget under the mouse does,
 * so they work wherever the mouse is in the window. Every other event
 * goes on to the widgets as usual.
 */
module fl.browser_window;

import fl.double_window : DoubleWindow;
import fl.enumerations : Event, backMouse, forwardMouse, stateCtrl;
static import fl.core;

package(fl) final class BrowserWindow : DoubleWindow
{
    /// Called with -1 for back and 1 for forward.
    void delegate(int step) onHistory;

    /// Called with 1 for larger text and -1 for smaller.
    void delegate(int step) onZoom;

    this(int w, int h, string label)
    {
        super(w, h, label);
    }

    override int handle(Event e)
    {
        switch (e)
        {
        case Event.push, Event.release:
        {
            int b = fl.core.eventButton();
            if (b != backMouse && b != forwardMouse) break;
            if (e == Event.push && onHistory !is null)
                onHistory(b == backMouse ? -1 : 1);
            return 1;
        }
        case Event.mouseWheel:
            if (!(fl.core.eventState() & stateCtrl) || fl.core.eventDy() == 0) break;
            if (onZoom !is null) onZoom(fl.core.eventDy() < 0 ? 1 : -1);
            return 1;
        default:
            break;
        }
        return super.handle(e);
    }
}

unittest
{
    import fl.group : FlGroup;
    import fl.enumerations : button;

    FlGroup.current(null);
    scope (exit) FlGroup.current(null);

    auto w = new BrowserWindow(100, 100, "test");
    w.end();
    int history, zoom;
    w.onHistory = (step) { history = step; };
    w.onZoom = (step) { zoom = step; };

    // The side buttons.
    fl.core.eventKeysym(cast(typeof(button))(button + backMouse));
    assert(w.handle(Event.push) == 1 && history == -1);
    assert(w.handle(Event.release) == 1);
    fl.core.eventKeysym(cast(typeof(button))(button + forwardMouse));
    assert(w.handle(Event.push) == 1 && history == 1);

    // Ctrl with the wheel; without Ctrl the wheel is left alone.
    scope (exit) { fl.core.eState_ = 0; fl.core.setWheelDelta(0, 0); }
    fl.core.setWheelDelta(0, -1);
    assert(w.handle(Event.mouseWheel) == 0 && zoom == 0);
    fl.core.eState_ = stateCtrl;
    assert(w.handle(Event.mouseWheel) == 1 && zoom == 1);
    fl.core.setWheelDelta(0, 2);
    assert(w.handle(Event.mouseWheel) == 1 && zoom == -1);
    fl.core.eventKeysym(cast(typeof(button)) 0);
}
