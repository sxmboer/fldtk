/*
 * Ported from FL/fl_show_colormap.H + src/fl_show_colormap.cxx (FLTK
 * 1.5.0). A small modal popup ("pretty much
 * unchanged from Forms", per FLTK's own comment) showing all 256
 * legacy colormap entries as an 8x32 grid of swatches; click, drag, or
 * arrow-key/Enter/Escape to pick one and return it as a `Color`.
 *
 * Faithful, complete port -- every branch of `ColorMenu::draw()`/
 * `handle()`/`run()` carries over directly onto this port's own
 * `Widget`/`Window`/`fl.core` primitives (`grab()` for exclusivity,
 * matching FLTK's own genuine single-widget-grab-owner use here --
 * same category as `fl.menu_popup`'s popup engine, not the `modal()`
 * mechanism `fl.ask`'s dialogs use instead; see `fl.core.grab()`'s own
 * doc comment for why the two are kept separate).
 */
module fl.show_colormap;

import fl.enumerations;
import fl.widget : Widget;
import fl.group : FlGroup;
import fl.window : Window;
import fl.draw : drawBoxAt;
import fl.core;

private enum boxsize = 14;
private enum border = 4;

private final class ColorMenu : Window
{
    Color initial_;
    Color which_;
    Color previous_;
    bool done_;

    this(Color oldcol)
    {
        super(boxsize * 8 + 1 + 2 * border, boxsize * 32 + 1 + 2 * border);
        clearBorder();
        setModal();
        initial_ = which_ = oldcol;
    }

    private void drawbox(Color c)
    {
        if (c > 255) return;
        int X = (c % 8) * boxsize + border;
        int Y = (c / 8) * boxsize + border;
        // FLTK gates this on `#if BORDER_WIDTH < 3` -- FLTK's
        // `BORDER_WIDTH` config constant defaults to 2 (config.h.in)
        // and this port has no equivalent knob, so only the `< 3`
        // branch is reachable and is the only one ported.
        if (c == which_)
            drawBoxAt(Boxtype.downBox, X + 1, Y + 1, boxsize - 1, boxsize - 1, c);
        else
            drawBoxAt(Boxtype.borderBox, X, Y, boxsize + 1, boxsize + 1, c);
    }

    override void draw()
    {
        if (damage() != damageChild)
        {
            drawBoxAt(Boxtype.upBox, 0, 0, w(), h(), color());
            for (int c = 0; c < 256; c++) drawbox(cast(Color) c);
        }
        else
        {
            drawbox(previous_);
            drawbox(which_);
        }
        previous_ = which_;
    }

    override int handle(Event event)
    {
        int c = which_;
        switch (event)
        {
        case Event.push:
        case Event.drag:
            {
                int X = fl.core.eventXRoot() - x() - border;
                if (X >= 0) X = X / boxsize;
                int Y = fl.core.eventYRoot() - y() - border;
                if (Y >= 0) Y = Y / boxsize;
                if (X >= 0 && X < 8 && Y >= 0 && Y < 32)
                    c = 8 * Y + X;
                else
                    c = initial_;
            }
            break;
        case Event.release:
            done_ = true;
            return 1;
        case Event.keyDown: // aka FL_KEYBOARD; see fl.enumerations.keyboard
            switch (fl.core.eventKey())
            {
            case up: if (c > 7) c -= 8; break;
            case down: if (c < 256 - 8) c += 8; break;
            case left: if (c > 0) c--; break;
            case right: if (c < 255) c++; break;
            case escape: which_ = initial_; done_ = true; return 1;
            case kpEnter:
            case enter: done_ = true; return 1;
            default: return 0;
            }
            break;
        default:
            return 0;
        }
        if (c != which_)
        {
            which_ = cast(Color) c;
            damage(damageChild);
            int bx = (c % 8) * boxsize + border;
            int by = (c / 8) * boxsize + border;
            int px = x();
            int py = y();
            int scrX, scrY, scrW, scrH;
            fl.core.screenXYWH(scrX, scrY, scrW, scrH);
            if (px < scrX) px = scrX;
            if (px + bx + boxsize + border >= scrX + scrW) px = scrX + scrW - bx - boxsize - border;
            if (py < scrY) py = scrY;
            if (py + by + boxsize + border >= scrY + scrH) py = scrY + scrH - by - boxsize - border;
            if (px + bx < border) px = border - bx;
            if (py + by < border) py = border - by;
            position(px, py);
        }
        return 1;
    }

    // Ported verbatim, including a likely FLTK quirk: when
    // `which_ > 255` (a true-color, non-palette-index Color), the
    // vertical half of the initial position uses the *window's own*
    // still-default `y()` (0, pre-`show()`) rather than `h()/2` the
    // way the horizontal half uses `w()/2` -- see
    // `FLTK_ISSUES.md`'s `fl_show_colormap.cxx` entry. Not
    // exercised by any sample so far (every caller passes a plain
    // palette index), so left exactly as FLTK has it rather than
    // silently "fixed".
    Color run()
    {
        if (which_ > 255)
            position(fl.core.eventXRoot() - w() / 2, fl.core.eventYRoot() - y() / 2);
        else
            position(fl.core.eventXRoot() - (initial_ % 8) * boxsize - boxsize / 2 - border,
                fl.core.eventYRoot() - (initial_ / 8) * boxsize - boxsize / 2 - border);
        show();
        fl.core.grab(this);
        done_ = false;
        while (!done_) fl.core.wait();
        fl.core.grab(null);
        return which_;
    }
}

/**
 * Pops up a window to let the user pick a colormap entry. `oldcol` is
 * highlighted when the grid is shown; returns the chosen entry.
 */
Color showColormap(Color oldcol)
{
    FlGroup.current(null);
    auto m = new ColorMenu(oldcol);
    scope (exit) FlGroup.current(null);
    auto result = m.run();
    m.hide();
    destroy(m);
    return result;
}
