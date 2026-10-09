/*
 * Ported from FL/Fl_Scheme_Choice.H + src/Fl_Scheme_Choice.cxx (FLTK
 * 1.5.0): a Choice pre-populated with every known scheme name (see
 * fl.scheme.names()) that switches fl.core.scheme() when the user
 * picks a different one.
 *
 * Deviation from FLTK, documented rather than silently dropped:
 * FLTK's scheme_cb_() callback does nothing but call
 * `Fl::scheme(new_scheme)` and relies entirely on `Fl::reload_scheme()`'s
 * own `first_window()`/`next_window()` walk (src/Fl_get_system_colors.cxx,
 * the last few lines of that function) to redraw *every* open window.
 * This port's `fl.core.reloadScheme()` doesn't do that walk -- there is
 * no ported window-list/`first_window()`/`next_window()` mechanism at
 * all (the same gap `fl.core.getSystemScheme()`'s skipped X-resource-
 * database fallback already documents). Rather than build a whole
 * window registry to support one call site, `schemeCb_()` here redraws
 * only *this* widget's own `window()` -- narrower than FLTK (a
 * second, separate open window showing scheme-dependent boxtypes won't
 * repaint until its own next `Expose`), but correct for the common
 * single-window case, which is every consumer of this widget in this
 * repo so far (calling `fl.core.scheme()` directly needs a manual
 * `win.redraw()`; a `SchemeChoice` does not).
 */
module fl.scheme_choice;

import fl.choice : Choice;
import fl.widget : Widget;
import fl.enumerations : Event;
static import fl.core;
import fl.scheme;

class SchemeChoice : Choice
{
    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);

        foreach (name; fl.scheme.names())
            add(name, 0, null);

        callback((w) { schemeCb_(w); });
        initValue();
    }

    /**
     * Handles FL_SHOW/FL_PUSH/FL_ENTER by re-syncing value() to the
     * active scheme first (in case it changed since this widget was
     * last shown/interacted with), then defers to Choice::handle() for
     * everything else. Ported from Fl_Scheme_Choice::handle() --
     * FLTK's own comment explains why FL_PUSH/FL_ENTER are handled
     * in addition to FL_SHOW: if the scheme changes after show() this
     * widget has no other way to notice.
     */
    override int handle(Event event)
    {
        int ret = 0;
        switch (event)
        {
        case Event.show:
        case Event.push:
        case Event.enter:
            initValue();
            ret = 1;
            break;
        default:
            break;
        }
        ret |= super.handle(event);
        return ret;
    }

    /**
     * Sets value() to match the currently active scheme (fl.core.scheme()).
     * Normally you don't need to call this directly -- handle() already
     * calls it on FL_SHOW/FL_PUSH/FL_ENTER -- but it's public so a
     * caller that changes the scheme directly (fl.core.scheme(...))
     * can force an immediate re-sync. Ported from
     * Fl_Scheme_Choice::init_value().
     */
    void initValue()
    {
        string current = fl.core.scheme();
        value(0);
        if (current is null) return;

        auto names = fl.scheme.names();
        foreach (i, name; names)
        {
            if (name == current)
            {
                value(cast(int) i);
                break;
            }
        }
    }

    private void schemeCb_(Widget w)
    {
        string newScheme = text(value());
        if (!fl.core.isScheme(newScheme))
            fl.core.scheme(newScheme);

        auto win = window();
        if (win !is null) win.redraw();
    }
}
