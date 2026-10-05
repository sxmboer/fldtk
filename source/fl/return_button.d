/*
 * Ported from FL/Fl_Return_Button.H + src/Fl_Return_Button.cxx (FLTK
 * 1.5.0).
 *
 * Faithful, complete port: draw()/handle()/the constructor all match
 * FLTK, including fl_return_arrow() -- FLTK defines that as a
 * free (non-static) function in Fl_Return_Button.cxx rather than in
 * fl_draw.H, so it's kept here rather than in fl.draw, same file
 * placement as FLTK. It needed two fl.draw primitives that were
 * still stubs until now: the 4-arg fl_xyline() and 5-arg fl_yxline()
 * overloads (both added there as plain compositions of the already-real
 * 3-arg forms -- see that module's doc comment).
 */
module fl.return_button;

import fl.enumerations;
import fl.core;
import fl.button : Button, hiddenButton;
import fldraw = fl.draw;

/// Draws the little carriage-return arrow glyph next to the button's
/// label. Ported verbatim from Fl_Return_Button.cxx's free function of
/// the same name. FLTK shares this one function across two
/// translation units via a bare `extern int fl_return_arrow(...)`
/// forward declaration (not exported, not in any header) -- the D
/// equivalent of "shared within the library, not part of the public
/// API" is `package(fl)` visibility, used here so fl.symbols's
/// "returnarrow" `@`-symbol (src/fl_symbols.cxx's own `draw_returnarrow()`)
/// can call the exact same logic instead of duplicating it.
package(fl) int returnArrow(int x, int y, int w, int h)
{
    int size = w;
    if (h < size) size = h;
    int d = (size + 2) / 4;
    if (d < 3) d = 3;
    int t = (size + 9) / 12;
    if (t < 1) t = 1;
    int x0 = x + (w - 2 * d - 2 * t - 1) / 2;
    int x1 = x0 + d;
    int y0 = y + h / 2;

    fldraw.fl_color(light3);
    fldraw.fl_line(x0, y0, x1, y0 + d);
    fldraw.fl_yxline(x1, y0 + d, y0 + t, x1 + d + 2 * t, y0 - d);
    fldraw.fl_yxline(x1, y0 - t, y0 - d);
    fldraw.fl_color(fl_gray_ramp(0));
    fldraw.fl_line(x0, y0, x1, y0 - d);
    fldraw.fl_color(dark3);
    fldraw.fl_xyline(x1 + 1, y0 - t, x1 + d, y0 - d, x1 + d + 2 * t);
    return 1;
}

/// A subclass of Button that generates a callback when pressed or when
/// the user presses Enter/KP_Enter. Draws a carriage-return arrow glyph
/// next to its label.
class ReturnButton : Button
{
    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
    }

    override void draw()
    {
        if (type() == hiddenButton) return;

        Boxtype bt = value() ? (downBox() != Boxtype.noBox ? downBox() : fl_down(box())) : box();
        int dx = fl.core.boxDx(bt);
        drawBox(bt, value() ? selectionColor() : color());
        int W = h();
        if (w() / 3 < W) W = w() / 3;
        returnArrow(x() + w() - (W + dx), y(), W, h());
        drawLabel(x() + dx, y(), w() - (dx + W + dx), h());
        if (fl.core.focus() is this) drawFocus();
    }

    override int handle(Event event)
    {
        if (event == Event.shortcut
                && (fl.core.eventKey() == enter || fl.core.eventKey() == kpEnter))
        {
            simulateKeyAction();
            doCallback(CallbackReason.selected);
            return 1;
        }
        return super.handle(event);
    }
}

unittest
{
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto b = new ReturnButton(0, 0, 80, 20, "OK");
    assert(b.box() == Boxtype.upBox); // inherited from Button's ctor
    assert(!b.value());

    fl.core.resetForTest();
}

unittest
{
    // FL_SHORTCUT with Enter/KP_Enter triggers the callback even though
    // the button has no explicit shortcut() or '&'-label shortcut.
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto b = new ReturnButton(0, 0, 80, 20, "OK");
    bool called;
    b.callback((w) { called = true; });
    b.when(whenChanged | whenRelease); // whenChanged is the default; explicit for clarity

    fl.core.eKeysym_ = enter;
    assert(b.handle(Event.shortcut) == 1);
    assert(called);
    assert(b.value()); // simulateKeyAction() sets value(true)

    called = false;
    b.value(false);
    fl.core.eKeysym_ = kpEnter;
    assert(b.handle(Event.shortcut) == 1);
    assert(called);

    fl.core.resetForTest();
}

unittest
{
    // Any other key falls through to Button::handle()'s FL_SHORTCUT
    // case, which tests the label's '&' shortcut (none here) and
    // returns 0.
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto b = new ReturnButton(0, 0, 80, 20, "OK");
    bool called;
    b.callback((w) { called = true; });

    fl.core.eKeysym_ = 'z';
    assert(b.handle(Event.shortcut) == 0);
    assert(!called);

    fl.core.resetForTest();
}
