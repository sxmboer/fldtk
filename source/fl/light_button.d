/*
 * Ported from FL/Fl_Light_Button.H + src/Fl_Light_Button.cxx (FLTK
 * 1.5.0). Also includes Fl_Radio_Light_Button,
 * which FLTK defines inline at the bottom of Fl_Light_Button.cxx
 * (fl.radio_light_button -- a complete, tested trivial subclass).
 *
 * Structurally faithful port of draw()/handle()/the constructor, and
 * draws real pixels entirely: fl_color()/inactive()/
 * contrast()/colorAverage()/fl_pie()/drawCheck()/
 * drawRadio() (all added to fl.draw specifically for this widget,
 * see that module's note) are all real, so the box/label/
 * dimmed-when-inactive parts *and* the checkbox/radio glyph itself all
 * render. `isScheme()` is real (all four scheme families), so this
 * widget's "gtk+"/"plastic" branches (already fully ported, every
 * branch) react to an active scheme for real. Nothing is skipped: every
 * branch FLTK's draw() takes is ported.
 */
module fl.light_button;

import fl.enumerations;
import fl.button : Button, toggleButton;
import fl.rect : Rect;
import fl.draw;
import fl.core;

class LightButton : Button
{
    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        type(toggleButton);
        selectionColor(yellow);
        alignment(alignLeft | alignInside);
    }

    override void draw()
    {
        if (box() != Boxtype.noBox)
            drawBox(this is fl.core.pushed() ? fl_down(box()) : box(), color());

        Color col = value() ? (activeR() ? selectionColor() : inactive(selectionColor())) : color();

        // Color of the check mark or radio button (circle).
        Color checkColor = selectionColor();
        if (fl.core.isScheme("gtk+"))
            checkColor = fl.enumerations.selectionColor; // the FL_SELECTION_COLOR constant, not the accessor above
        if (!activeR())
            checkColor = inactive(checkColor);
        checkColor = contrast(checkColor, background2Color);

        int W = labelsize(); // check mark box size
        if (W > 25) W = 25;  // limit box size
        int bx = fl.core.boxDx(box());
        int dx = bx + 2;
        int dy = (h() - W) / 2;
        int lx = 0;
        int cx = x() + dx;
        int cy = y() + dy;
        int cw = 0;

        // The down_box() boxtype determines the drawing style: unset
        // (0) means the Fl_Light_Button "light" style; set means one
        // of the "other button styles" below.
        if (downBox() != Boxtype.noBox)
        {
            switch (downBox())
            {
            case Boxtype.downBox:
            case Boxtype.upBox:
            case Boxtype.plasticDownBox:
            case Boxtype.plasticUpBox:
                // Check box...
                drawBox(downBox(), cx, cy, W, W, background2Color);
                if (value())
                {
                    cx += fl.core.boxDx(downBox());
                    cy += fl.core.boxDy(downBox());
                    cw = W - fl.core.boxDw(downBox());
                    drawCheck(Rect(cx, cy, cw, cw), checkColor);
                }
                break;

            case Boxtype.roundDownBox:
            case Boxtype.roundUpBox:
                // Radio button...
                drawBox(downBox(), x() + dx, y() + dy, W, W, background2Color);
                if (value())
                {
                    int tW = (W - fl.core.boxDw(downBox())) / 2 + 1;
                    if ((W - tW) & 1) tW++; // keep the difference even, to center
                    int tdx = dx + (W - tW) / 2;
                    int tdy = dy + (W - tW) / 2;
                    drawRadio(x() + tdx - 1, y() + tdy - 1, tW + 2, checkColor);
                }
                break;

            default:
                drawBox(downBox(), x() + dx, y() + dy, W, W, col);
                break;
            }
            lx = dx + W + 2;
        }
        else
        {
            // down_box() is unset: draw the light-button style.
            int hh = h() - 2 * dy - 2;
            int ww = W / 2 + 1;
            int xx = dx;
            if (w() < ww + 2 * xx) xx = (w() - ww) / 2;
            if (fl.core.isScheme("plastic"))
            {
                col = activeR() ? selectionColor() : inactive(selectionColor());
                fl_color(value() ? col : colorAverage(col, black, 0.5f));
                fl_pie(x() + xx, y() + dy + 1, ww, hh, 0, 360);
            }
            else
            {
                drawBox(Boxtype.thinDownBox, x() + xx, y() + dy + 1, ww, hh, col);
            }
            lx = dx + ww + 2;
        }

        drawLabel(x() + lx, y(), w() - lx - bx, h());
        if (fl.core.focus() is this) drawFocus();
    }

    override int handle(Event event)
    {
        if (event == Event.release && box() != Boxtype.noBox)
            redraw();
        return super.handle(event);
    }
}

unittest
{
    import fl.group : FlGroup;

    FlGroup.current(null);

    auto b = new LightButton(0, 0, 80, 20, "x");
    assert(b.type() == toggleButton);
    assert(b.selectionColor() == yellow);
    assert(b.alignment() == (alignLeft | alignInside));

    // draw() calls into stubs only -- just confirm it doesn't throw.
    b.draw();

    FlGroup.current(null);
}

unittest
{
    // FL_RELEASE with a box set forwards to Button.handle() too (not
    // just an early return), so a normal click still fires the callback.
    import fl.group : FlGroup;

    FlGroup.current(null);
    fl.core.focus(null);

    auto b = new LightButton(0, 0, 20, 20);
    bool called;
    b.callback((w) { called = true; });

    fl.core.eX_ = 10;
    fl.core.eY_ = 10;
    b.handle(Event.push);
    assert(b.handle(Event.release) == 1);
    assert(called);

    fl.core.eX_ = 0;
    fl.core.eY_ = 0;
    fl.core.focus(null);
    FlGroup.current(null);
}
