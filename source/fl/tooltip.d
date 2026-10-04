/*
 * Ported from FL/Fl_Tooltip.H + src/Fl_Tooltip.cxx (FLTK 1.5.0,
 * ~/Repositories/fltk). FLTK is "only static methods" on a class
 * that's never instantiated -- the same "namespace as free functions"
 * shape fl.core/fl.enumerations already use for exactly this reason,
 * so this port is free functions + module state, not a class with
 * static methods.
 *
 * Faithful port of the real behavior: hover-delay/show-delay/hide-delay
 * timers (fl.core.addTimeout()), the popup window itself (TooltipBox,
 * a borderless fl.menu_window.MenuWindow subclass reusing
 * Widget.Flag.menuWindow for override-redirect X11 treatment -- see
 * that flag's existing use in fl.menu_popup for why that alone is
 * enough; FLTK's *separate* TOOLTIP_WINDOW flag mostly just adds a
 * `_NET_WM_WINDOW_TYPE_MENU` EWMH hint to suppress compositor
 * animations, cosmetic polish this port skips, see fl_x.cxx's own
 * comment on it), current()/current(Widget) target tracking (via
 * fl.core.watchWidgetPointer() so a destroyed target widget can't
 * leave a dangling reference -- see currentWidget_'s own doc comment),
 * the "recently shown, pop up again fast" hover-chain logic, and
 * FL_BEFORE_TOOLTIP + overrideText() for apps that want to compute a
 * tooltip's text dynamically.
 *
 * Integration with fl.core.handle() (matching FLTK's Fl::handle_()
 * call sites in Fl.cxx) doesn't replicate FLTK's lazy
 * `Fl_Tooltip::enter`/`exit` function-pointer wiring
 * (`set_enter_exit_once_()`, called from `Fl_Widget::tooltip()`): that
 * exists purely so an app that never sets a tooltip doesn't link in
 * Fl_Tooltip.cxx at all, a C++ static-linking concern with no D
 * equivalent (this library is already one compiled unit) -- calling
 * mouseEnter()/exit() unconditionally is already cheap when nothing has a
 * tooltip (widget_/currentWidget_ stays null, every call early-returns
 * immediately), so fl.core just calls straight into this module's
 * mouseEnter()/exit()/current() (see this module's own call sites, cross-
 * referenced from fl.core's handle()/belowmouse()/clearWidgetPointer()
 * doc comments).
 *
 * **`@`-symbol image glyphs in tooltip text are real**: a tooltip
 * string starting or ending with
 * `@symbolname` draws the real glyph, matching every other `fl_draw()`
 * caller in this port -- `draw()`'s call into
 * `fl.draw.fl_draw()` picks up `fl.symbols`'s feature automatically,
 * with no code needed here.
 *
 * **Real hover-intent behavior, a deliberate improvement
 * beyond FLTK, not a faithful port**: the mouse moving from the
 * target widget onto the open tooltip popup keeps it showing and
 * leaves it exactly where it is (no repositioning -- see
 * `mouseEnter()`'s own doc comment for why re-`layout()`ing it here,
 * which is what FLTK's own analogous branch in `Fl_Tooltip::
 * enter_()` does, actively makes it chase the cursor instead). Any
 * other transition away from the target that isn't yet on the popup --
 * including the small screen-space gap `TooltipBox.layout()` leaves
 * between the two, and a `belowmouse(null)` transition, which
 * `fl.platform_x11`'s `LeaveNotify` handling fires unconditionally the
 * moment the pointer leaves the target's own top-level window, before
 * it could possibly have reached the separate top-level popup window
 * yet -- gets a brief grace period (`hoverdelay()`) before actually
 * hiding, cancelled if the mouse lands on the target or the popup
 * before it fires. This has no literal FLTK equivalent to port:
 * FLTK hides synchronously on every such transition, no grace
 * period at all, and its own "reposition, but don't move if nothing
 * changed" branch doesn't reliably prevent that in practice either,
 * since its position recompute reads the live mouse coordinate and so
 * essentially always reports "moved" once the cursor is genuinely over
 * the popup. No real FLTK Windows build was available to confirm
 * whether unmodified FLTK has the same underlying issue. The one real
 * immediate-dismiss case (`fl.core.handle()`'s `Event.keyDown`) calls
 * the separate `dismissNow()`, not `mouseEnter(null)` -- a null target
 * there doesn't mean "dismiss now," since it also arises naturally
 * from the `LeaveNotify` transition above. The mouse being over the
 * popup also suspends the stale-tooltip auto-hide
 * (`hidedelay()`, 12s default) for as long as it stays there -- that
 * timer still runs its full course while the mouse merely sits still
 * over the *source* widget (real, intended, unrelated behavior), but
 * once the mouse has moved onto the popup itself, staying open is the
 * whole point.
 */
module fl.tooltip;

import fl.enumerations;
import fl.widget : Widget;
import fl.window : Window;
import fl.group : FlGroup;
import fl.menu_window : MenuWindow;
import fldraw = fl.draw;
import core.memory : GC;
static import fl.core;

// ---------------------------------------------------------------------
// Configuration (Fl_Tooltip's public static get/set surface)
// ---------------------------------------------------------------------

private float delay_ = 1.0f;
private float hidedelay_ = 12.0f;
private float hoverdelay_ = 0.2f;

/// Delay before a tooltip is shown. Default 1.0 seconds.
float delay() { return delay_; }
/// ditto
void delay(float f) { delay_ = f; }

/// Delay until a shown tooltip hides itself again. Default 12.0 seconds.
float hidedelay() { return hidedelay_; }
/// ditto
void hidedelay(float f) { hidedelay_ = f; }

/// Delay between tooltips -- how long "recently shown" lasts, letting
/// a quick hover from one tooltipped widget to another pop up
/// immediately instead of waiting delay() again. Default 0.2 seconds.
float hoverdelay() { return hoverdelay_; }
/// ditto
void hoverdelay(float f) { hoverdelay_ = f; }

/// True if tooltips are enabled globally. Ported from FLTK's
/// `Fl::option(Fl::OPTION_SHOW_TOOLTIPS)`, routed through the real
/// general `fl.core.option()` mechanism (see that function's own doc
/// comment).
bool enabled() { return fl.core.option(fl.core.Option.showTooltips); }
/// Enables (or, if b is false, disables) tooltips globally.
void enable(bool b = true) { fl.core.option(fl.core.Option.showTooltips, b); }
/// Same as enable(false).
void disable() { fl.core.option(fl.core.Option.showTooltips, false); }

private Color color_ = cast(Color) 215;
private Color textcolor_ = black;
private Font font_ = helvetica;
private Fontsize size_ = -1;
private int marginWidth_ = 3;
private int marginHeight_ = 3;
private int wrapWidth_ = 400;

/// Background color for tooltips. Default a pale yellow -- FLTK
/// computes this as `fl_color_cube(FL_NUM_RED-1, FL_NUM_GREEN-1,
/// FL_NUM_BLUE-2)` = index 215 into the 256-entry default color cube;
/// this port has no general fl_color_cube() (nothing else needs one
/// yet), so the literal resulting index is used directly -- resolves
/// to the identical RGB value through fl.enumerations.colorTable, the
/// same table fl_color() already uses for every other indexed color.
Color color() { return color_; }
/// ditto
void color(Color c) { color_ = c; }

/// Text color for tooltips. Default black.
Color textcolor() { return textcolor_; }
/// ditto
void textcolor(Color c) { textcolor_ = c; }

/// Typeface for tooltip text. Default Helvetica.
Font font() { return font_; }
/// ditto
void font(Font f) { font_ = f; }

/// Size of tooltip text. -1 (the default) means normalSize.
Fontsize size() { return size_ == -1 ? normalSize : size_; }
/// ditto
void size(Fontsize s) { size_ = s; }

/// Extra space left/right of the tooltip's text. Default 3.
int marginWidth() { return marginWidth_; }
/// ditto
void marginWidth(int v) { marginWidth_ = v; }

/// Extra space above/below the tooltip's text. Default 3.
int marginHeight() { return marginHeight_; }
/// ditto
void marginHeight(int v) { marginHeight_ = v; }

/// Maximum width before tooltip text would word-wrap. Default 400.
/// See this module's own top comment for the real-word-wrap gap this
/// currently only partially enforces (clamps the reported width, does
/// not reflow text into more lines).
int wrapWidth() { return wrapWidth_; }
/// ditto
void wrapWidth(int v) { wrapWidth_ = v; }

// ---------------------------------------------------------------------
// Current target widget
// ---------------------------------------------------------------------

/**
 * The widget a tooltip is currently tracking (armed, showing, or about
 * to show for), or null. Watched via fl.core.watchWidgetPointer() (the
 * same external watch-list `fl.widget_tracker.WidgetTracker` uses,
 * called directly here since this is a single, persistent, module-
 * level slot rather than a scope-local value -- see that module's own
 * doc comment on why it's a stack-only `struct` and doesn't fit this
 * use case) rather than FLTK's reliance on `fl_throw_focus()`
 * unconditionally calling `Tooltip::exit(o)` for every widget
 * destruction: registering once means a destroyed target widget can
 * never leave a dangling reference here, matching this port's general
 * "external watch-list, not a self-reported flag" approach to this
 * class of problem (see CLAUDE.md's WidgetTracker note). exit()
 * (called from fl.core.clearWidgetPointer(), see that function's own
 * doc comment) is still needed on top of the automatic nulling,
 * though: the watch-list only clears the *reference*, it doesn't hide
 * an already-showing window or cancel its timers.
 */
private Widget currentWidget_;
private bool watchRegistered_;

private void ensureWatched()
{
    if (!watchRegistered_)
    {
        fl.core.watchWidgetPointer(currentWidget_);
        watchRegistered_ = true;
    }
}

/// The widget a tooltip is currently tracking, or null.
Widget current() { return currentWidget_; }

/**
 * Sets the current target widget as though mouseEnter(w) happened, but
 * without popping up a tooltip -- used when the user clicks (see
 * fl.core.handle()'s Event.push case), so a tooltip doesn't reappear
 * immediately after a click just because the mouse is still over the
 * same widget. Ported from Fl_Tooltip::current(Fl_Widget*).
 */
void current(Widget w)
{
    exit(null);
    Widget tw = w;
    for (;;)
    {
        if (tw is null) return;
        if (tw.tooltip().length) break;
        tw = tw.parent;
    }
    ensureWatched();
    currentWidget_ = w;
}

// ---------------------------------------------------------------------
// The popup window
// ---------------------------------------------------------------------

private string tip_;
private int currentTooltipY_, currentTooltipH_;
private bool recentTooltip_;
private bool recursion_;
private TooltipBox window_;

/// The window used to display tooltips, or null if none has been
/// created yet. Ported from Fl_Tooltip::current_window().
Window currentWindow() { return window_; }

private final class TooltipBox : MenuWindow
{
    this()
    {
        super(0, 0);
        clearBorder();
        setFlag(Widget.Flag.menuWindow);
        end();
    }

    override void show()
    {
        if (tip_.length == 0) return;
        super.show();
    }

    override int handle(Event e)
    {
        if (e == Event.push || e == Event.keyDown)
        {
            hide();
            fl.core.removeTimeout(hideTimeoutCb_);
            return 1;
        }
        return super.handle(e);
    }

    override void draw()
    {
        // Explicit local (0,0) origin, not the 2-arg drawBox(t, c)
        // overload -- that one draws at the widget's own x_/y_, which
        // for a top-level window like this holds *screen* position, not
        // window-local (0,0). Same bug class as fl.window.Window.draw()
        // already had to guard against; see CLAUDE.md/memory on that
        // fix for the full story.
        drawBox(Boxtype.borderBox, 0, 0, w(), h(), color_);
        fldraw.fl_color(textcolor_);
        // Qualified: unqualified size() inside a Widget subclass method
        // resolves to the inherited Widget.size(int,int) geometry
        // setter, not this module's own free function of the same name.
        fldraw.fl_font(font_, fl.tooltip.size());
        int X = marginWidth_;
        int Y = marginHeight_;
        int W = w() - marginWidth_ * 2;
        int H = h() - marginHeight_ * 2;
        fldraw.fl_draw(tip_, X, Y, W, H, alignLeft | alignWrap);
    }

    /// Ported from Fl_TooltipBox::layout(): computes the box size from
    /// tip_'s measured extent (now real word-wrap, not just a width
    /// clamp -- fl.draw's fl_measure() got its own real in/out
    /// wrap-width parameter to match, see that module's row), and
    /// positions it near either the mouse (for a "large" hover target,
    /// matching FLTK's H>30 branch -- e.g. a whole pane rather than
    /// a small button) or just below the hovered widget, clamped to
    /// stay on-screen.
    void layout()
    {
        // Qualified: unqualified size() inside a Widget subclass method
        // resolves to the inherited Widget.size(int,int) geometry
        // setter, not this module's own free function of the same name.
        fldraw.fl_font(font_, fl.tooltip.size());
        int ww = wrapWidth_, hh;
        fldraw.fl_measure(tip_, ww, hh);
        ww += marginWidth_ * 2;
        hh += marginHeight_ * 2;

        int ox = fl.core.eventXRoot();
        int oy;
        if (currentTooltipH_ > 30)
        {
            oy = fl.core.eventYRoot() + 13;
        }
        else
        {
            int xoff, yoff;
            auto topWin = currentWidget_ !is null
                ? currentWidget_.topWindowOffset(xoff, yoff) : null;
            oy = currentTooltipY_ + currentTooltipH_ + 2
                + (topWin !is null ? topWin.y() + yoff : 0);
        }

        int scrX, scrY, scrW, scrH;
        fl.core.screenXYWH(scrX, scrY, scrW, scrH, ox, oy);
        if (ox + ww > scrX + scrW) ox = scrX + scrW - ww;
        if (ox < scrX) ox = scrX;
        if (currentTooltipH_ > 30)
        {
            if (oy + hh > scrY + scrH) oy -= 23 + hh;
        }
        else
        {
            if (oy + hh > scrY + scrH) oy -= (4 + hh + currentTooltipH_);
        }
        if (oy < scrY) oy = scrY;

        resize(ox, oy, ww, hh);
    }
}

// ---------------------------------------------------------------------
// Timeouts
// ---------------------------------------------------------------------

// fl.core's addTimeout()/removeTimeout() take a delegate (TimeoutHandler
// = void delegate()), not a plain function pointer, per the project's
// usual function-pointer -> delegate convention -- and removeTimeout()
// removes by delegate *equality*, so the exact same delegate value has
// to be passed to both addTimeout() and every later removeTimeout()
// call for the same logical timer. `&someFreeFunction` produces a
// `void function()` at each call site (not implicitly a delegate in an
// argument-passing context), so these three are captured once, here,
// as real TimeoutHandler-typed values, and every add/removeTimeout()
// call below reuses these instead of re-taking `&hideTimeout_` etc.
// each time.
private void hideTimeout_()
{
    if (window_ !is null) window_.hide();
    recentTooltip_ = false;
}

private void recentTimeout_()
{
    recentTooltip_ = false;
}

private fl.core.TimeoutHandler hideTimeoutCb_;
private fl.core.TimeoutHandler recentTimeoutCb_;
private fl.core.TimeoutHandler tooltipTimeoutCb_;

/// The widget argument for the pending grace-delayed `exit()` call
/// `pendingExitCb_` fires -- see `mouseEnter()`'s own doc comment for
/// the hover-intent mechanism this backs. Always `null` in practice
/// (matching the one call site that schedules it), kept as a named
/// field rather than a hardcoded `null` in the callback purely for
/// symmetry/clarity with `hideTimeoutCb_`/etc.'s own shape.
private Widget pendingExitTarget_;
private fl.core.TimeoutHandler pendingExitCb_;

static this()
{
    hideTimeoutCb_ = () { hideTimeout_(); };
    recentTimeoutCb_ = () { recentTimeout_(); };
    tooltipTimeoutCb_ = () { tooltipTimeout_(); };
    pendingExitCb_ = () { exit(pendingExitTarget_); };
}

private bool topWinIconified()
{
    if (currentWidget_ is null) return false;
    auto topwin = currentWidget_.topWindow();
    if (topwin is null) return false;
    return !topwin.visible();
}

private void tooltipTimeout_()
{
    if (recursion_) return;
    recursion_ = true;
    scope(exit) recursion_ = false;

    if (!topWinIconified())
    {
        if (currentWidget_ !is null && currentWidget_.handle(Event.beforeTooltip))
            tip_ = overrideText_;

        if (tip_.length == 0)
        {
            if (window_ !is null) window_.hide();
            fl.core.removeTimeout(hideTimeoutCb_);
        }
        else if (fl.core.grab() is null)
        {
            FlGroup previousGroup = FlGroup.current();
            FlGroup.current(null);
            if (window_ is null) window_ = new TooltipBox;
            FlGroup.current(previousGroup);

            window_.label(tip_);
            window_.layout();
            window_.redraw();
            window_.show();
            fl.core.addTimeout(hidedelay(), hideTimeoutCb_);
        }
    }

    fl.core.removeTimeout(recentTimeoutCb_);
    recentTooltip_ = true;
}

// ---------------------------------------------------------------------
// Enter / exit / enterArea (the actual hover-tracking state machine)
// ---------------------------------------------------------------------

/**
 * Called when the mouse enters w (or, from fl.core.handle()'s
 * Event.keyDown case, with w == null to dismiss any showing tooltip
 * when the user starts typing). Ported from Fl_Tooltip::enter_().
 *
 * Named `mouseEnter()`, not the bare `enter()` FLTK's own
 * `Fl_Tooltip::enter()` uses:
 * a bare `enter()` collides with `fl.enumerations.enter` (the
 * `Keysym.enter`-equivalent constant), both reachable unqualified
 * under a single `import fl;` -- a real ambiguity error
 * (`samples/test/handle_keys.d`, which legitimately wants
 * the keysym). No other module in this port names anything bare
 * `enter`, so renaming this one, less commonly referenced, symbol
 * resolves the collision without displacing the keysym constant.
 */
void mouseEnter(Widget w)
{
    // The mouse is over the tooltip popup itself -- stays open, left
    // exactly where it is. No re-`layout()` call: `layout()`'s own math
    // reads the *live* mouse position, so calling it here would
    // reposition the popup to chase wherever the cursor is *within* it,
    // which promptly moves the popup out from under the now-stationary
    // cursor and repeats -- visibly "running away" from the mouse. An
    // already-shown, already-correctly-placed popup never needs
    // re-laying-out just because the mouse moved onto it. See this
    // module's own top comment for why this (and the grace period
    // below) go beyond FLTK's own `Fl_Tooltip::enter_()` rather than
    // porting it literally.
    if (w !is null && w is window_)
    {
        fl.core.removeTimeout(pendingExitCb_);
        // Also suspends the stale-tooltip auto-hide (`hidedelay()`) --
        // without this, the popup would vanish on
        // its own after the usual 12s even while the mouse sat on it.
        // That timer starts the moment the tooltip first appears and,
        // deliberately, keeps ticking even while the mouse just sits
        // still over the *source* widget (see smoke-tests/tooltip.d's
        // own documented test for that case -- real, intended behavior,
        // unrelated to this fix) -- but once the mouse has moved onto
        // the popup itself, that's active engagement, not staleness,
        // and should not expire out from under it.
        fl.core.removeTimeout(hideTimeoutCb_);
        return;
    }

    // `w is null` is NOT an immediate-dismiss signal here: a null
    // `belowmouse()` target also arises naturally from `fl.platform_x11`'s
    // own `LeaveNotify` handling, fired the instant the pointer leaves
    // the target widget's own top-level window -- exactly what happens
    // first when heading toward the (separate top-level) tooltip popup,
    // well before the cursor could reach it. Falling through to the
    // walk below (immediately taking its `tw is null` exit) gives it
    // the same grace treatment as any other no-tooltip destination,
    // which is correct: "just left our window" and "landed on some
    // other widget with no tooltip" mean the same thing here -- not yet
    // on the popup, not yet dismissed. The one real immediate-dismiss
    // case (a keypress) calls `dismissNow()` instead of this function.
    Widget tw = w;
    for (;;)
    {
        if (tw is null) break; // walked the whole ancestor chain, no tooltip anywhere
        if (tw is currentWidget_)
        {
            fl.core.removeTimeout(pendingExitCb_);
            return;
        }
        if (tw.tooltip().length)
        {
            fl.core.removeTimeout(pendingExitCb_);
            enterArea(w, 0, 0, w.w(), w.h(), tw.tooltip());
            return;
        }
        tw = tw.parent;
    }

    // Hover-intent grace period: the widget/window the mouse just
    // entered has no tooltip anywhere in its ancestor chain and isn't
    // the popup itself -- rather than hiding instantly, give the mouse
    // a brief window (`hoverdelay()`) to land back on the original
    // target or the tooltip popup, e.g. while crossing the small
    // screen-space gap `TooltipBox.layout()` leaves between them.
    // No-op if nothing is actually showing (`currentWidget_ is null`).
    if (currentWidget_ is null) return;
    pendingExitTarget_ = null;
    fl.core.removeTimeout(pendingExitCb_);
    fl.core.addTimeout(hoverdelay(), pendingExitCb_);
}

/**
 * Immediately dismisses any showing/pending tooltip, bypassing
 * `mouseEnter()`'s own hover-intent grace period entirely -- the one
 * remaining instant-hide path, for a caller that genuinely wants "hide
 * this right now regardless of where the mouse is," not a mouse
 * transition. `fl.core.handle()`'s `Event.keyDown` case is the one real
 * caller: ported from FLTK's own unconditional `Fl_Tooltip::enter(
 * (Fl_Widget*)0)` at the top of `Fl::handle_()`'s `FL_KEYBOARD` case
 * ("any keypress dismisses a showing/pending tooltip, regardless of
 * where the mouse is"). Split out from `mouseEnter(null)` itself,
 * since a null target also arises
 * naturally from an ordinary `belowmouse()` transition (see
 * `mouseEnter()`'s own doc comment for the full story), so `null`
 * can't double as "the caller wants an instant dismiss."
 */
void dismissNow()
{
    fl.core.removeTimeout(pendingExitCb_);
    exit(null);
}

private string overrideText_;

/**
 * Temporarily overrides the tooltip text about to be shown -- call
 * from a widget's handle() in response to Event.beforeTooltip, then
 * return 1. Ported from Fl_Tooltip::override_text().
 */
int overrideText(string newText)
{
    overrideText_ = newText;
    return 1;
}

/// Hides any visible tooltip and clears the current target. Ported
/// from Fl_Tooltip::exit_(). Called for Event.leave-equivalent
/// transitions (via fl.core.belowmouse()'s setter, see that function's
/// own doc comment) and from fl.core.clearWidgetPointer() (this port's
/// fl_throw_focus() stand-in) for every widget destruction -- including
/// from `Widget.~this()` during GC-driven finalization, where the guard
/// below matters (see it for why).
///
/// **`GC.inFinalizer()`-guarded**: `clearWidgetPointer()`
/// calls this *unconditionally* for every widget's destruction, `Widget.~this()`
/// included, so this runs during GC-driven finalization too, not just
/// deterministic `destroy()`. The check below only ever short-circuits
/// on `currentWidget_ is null`/`w is window_` -- notably *not*
/// `currentWidget_ is w` -- so without this guard, any widget's
/// finalization at all (not
/// just one that was ever the tooltip's own target) would reach into the
/// *shared* tooltip `window_` object (`.visible()`/`.hide()`) and the
/// global timer queue (`fl.core.add/removeTimeout()`) whenever a tooltip
/// happened to be active at that moment -- exactly the "touching other
/// GC-managed objects during undefined finalization order" hazard
/// CLAUDE.md's own GC-finalizer note describes.
/// `window_.hide()` in particular can synchronously destroy a
/// native window, and Windows' own message-delivery for that can
/// reenter `WndProc` -- any GC allocation made from *there*, while the
/// outer collection that triggered this finalizer is still in progress,
/// throws `InvalidMemoryOperationError`. Matches `Widget.~this()`/`Window.~this()`'s own
/// established `if (!GC.inFinalizer())` pattern: if the collector
/// reclaimed `w`, nothing reachable (including `currentWidget_`, a real
/// GC root) was pointing at it, so there is nothing here that still
/// *needs* undoing on `w`'s account specifically -- skipping is safe.
void exit(Widget w)
{
    if (currentWidget_ is null || (w !is null && w is window_)) return;
    if (GC.inFinalizer()) return;
    currentWidget_ = null;
    fl.core.removeTimeout(tooltipTimeoutCb_);
    fl.core.removeTimeout(recentTimeoutCb_);
    // Also cancels a pending hover-intent grace timer (mouseEnter()'s
    // own doc comment) -- exit() can run via a different path (an
    // immediate click/keypress dismiss, or widget destruction via
    // fl.core.clearWidgetPointer()) while one happens to be scheduled;
    // harmless either way (this function's own top guard makes a stale
    // fire a safe no-op once currentWidget_ is already null), but
    // there's no reason to leave a dead timer ticking.
    fl.core.removeTimeout(pendingExitCb_);
    if (window_ !is null && window_.visible())
    {
        window_.hide();
        fl.core.removeTimeout(hideTimeoutCb_);
    }
    if (recentTooltip_)
    {
        if (fl.core.eventState(stateButtons) != 0) recentTooltip_ = false;
        else fl.core.addTimeout(hoverdelay(), recentTimeoutCb_);
    }
}

/**
 * Arms a tooltip for wid: the rectangle (x,y,w,h) is relative to wid's
 * own bounds (for a caller providing a tooltip for one internal piece
 * of a composite widget -- x/w are accepted for API fidelity with
 * FLTK but, matching FLTK exactly, unused: only y/h feed the
 * positioning math in TooltipBox.layout()). t is the tooltip text; a
 * null or empty t dismisses any current tooltip instead of arming one.
 * Ported from Fl_Tooltip::enter_area().
 */
void enterArea(Widget wid, int x, int y, int w, int h, string t)
{
    if (recursion_) return;
    if (t.length == 0 || !enabled())
    {
        exit(null);
        return;
    }
    if (wid is currentWidget_ && t == tip_) return;

    fl.core.removeTimeout(tooltipTimeoutCb_);
    fl.core.removeTimeout(recentTimeoutCb_);

    ensureWatched();
    currentWidget_ = wid;
    currentTooltipY_ = y;
    currentTooltipH_ = h;
    tip_ = t;

    if (recentTooltip_)
    {
        if (window_ !is null)
        {
            window_.hide();
            fl.core.removeTimeout(hideTimeoutCb_);
        }
        fl.core.addTimeout(hoverdelay(), tooltipTimeoutCb_);
    }
    else if (delay() < .1)
    {
        tooltipTimeout_();
    }
    else
    {
        if (window_ !is null && window_.visible())
        {
            window_.hide();
            fl.core.removeTimeout(hideTimeoutCb_);
        }
        fl.core.addTimeout(delay(), tooltipTimeoutCb_);
    }
}

/// Resets every module-level global back to its default -- see
/// fl.core.resetForTest()'s own doc comment for why any test touching
/// this module's state needs this, same reasoning. Package-visible,
/// for this module's own unittests and any future widget test that
/// exercises tooltip hover behavior.
package(fl) void resetForTest()
{
    fl.core.removeTimeout(tooltipTimeoutCb_);
    fl.core.removeTimeout(hideTimeoutCb_);
    fl.core.removeTimeout(recentTimeoutCb_);
    if (window_ !is null && window_.visible()) window_.hide();
    currentWidget_ = null;
    tip_ = null;
    overrideText_ = null;
    currentTooltipY_ = 0;
    currentTooltipH_ = 0;
    recentTooltip_ = false;
    recursion_ = false;
}

// ===========================================================================
// Unit tests
// ===========================================================================

unittest
{
    // Plain get/set surface -- no display needed.
    resetForTest();
    scope(exit) resetForTest();

    delay(0.5f);
    assert(delay() == 0.5f);
    hidedelay(6.0f);
    assert(hidedelay() == 6.0f);
    hoverdelay(0.1f);
    assert(hoverdelay() == 0.1f);
    delay(1.0f);
    hidedelay(12.0f);
    hoverdelay(0.2f);

    assert(enabled());
    disable();
    assert(!enabled());
    enable();
    assert(enabled());

    // Wiring check: enabled()
    // reads the actual shared fl.core.Option.showTooltips entry, not an
    // independent copy of its own.
    fl.core.option(fl.core.Option.showTooltips, false);
    assert(!enabled());
    fl.core.resetForTest();

    color(red);
    assert(color() == red);
    color(cast(Color) 215);

    marginWidth(5);
    assert(marginWidth() == 5);
    marginWidth(3);

    wrapWidth(200);
    assert(wrapWidth() == 200);
    wrapWidth(400);

    assert(size() == normalSize); // size_ == -1 sentinel
    size(20);
    assert(size() == 20);
    size(-1);
}

unittest
{
    // enterArea()/exit(): arms a delayed timeout, exit() cancels it and
    // clears current() without ever needing a live display (no show()
    // is reached since delay() stays at its 1.0s default and this test
    // never lets the timeout actually fire).
    import fl.group : FlGroup;
    import fl.box : Box;

    FlGroup.current(null);
    fl.core.resetForTest();
    resetForTest();

    auto b = new Box(0, 0, 50, 20);
    b.tooltip("hello");

    enterArea(b, 0, 0, 50, 20, "hello");
    assert(current() is b);
    assert(fl.core.hasTimeout(tooltipTimeoutCb_));

    exit(null);
    assert(current() is null);
    assert(!fl.core.hasTimeout(tooltipTimeoutCb_));

    destroy(b);
    fl.core.resetForTest();
    resetForTest();
    FlGroup.current(null);
}

unittest
{
    // current(Widget): acts like mouseEnter() without ever arming a popup
    // timeout -- matches FLTK's documented "prevent a tooltip from
    // reappearing" use, exercised here the same way fl.core.handle()'s
    // Event.push case uses it.
    import fl.group : FlGroup;
    import fl.box : Box;

    FlGroup.current(null);
    fl.core.resetForTest();
    resetForTest();

    auto b = new Box(0, 0, 50, 20);
    b.tooltip("hi");

    enterArea(b, 0, 0, 50, 20, "hi");
    assert(fl.core.hasTimeout(tooltipTimeoutCb_));

    current(b);
    assert(current() is b);
    // current() doesn't arm a new popup timeout -- exit(null) inside
    // it cancels the one enterArea() started, and nothing re-arms one.
    assert(!fl.core.hasTimeout(tooltipTimeoutCb_));

    destroy(b);
    fl.core.resetForTest();
    resetForTest();
    FlGroup.current(null);
}

unittest
{
    // A widget destroyed while it's the current tooltip target is
    // never left as a dangling reference -- the watch-list nulls it
    // out automatically (see currentWidget_'s own doc comment), and
    // fl.core.clearWidgetPointer() (called from ~Widget()) also runs
    // this module's exit() so any showing window/timers get cleaned
    // up, not just the reference.
    import fl.group : FlGroup;
    import fl.box : Box;

    FlGroup.current(null);
    fl.core.resetForTest();
    resetForTest();

    auto b = new Box(0, 0, 50, 20);
    b.tooltip("bye");
    enterArea(b, 0, 0, 50, 20, "bye");
    assert(current() is b);

    destroy(b);
    assert(current() is null);
    assert(!fl.core.hasTimeout(tooltipTimeoutCb_));

    fl.core.resetForTest();
    resetForTest();
    FlGroup.current(null);
}

unittest
{
    // mouseEnter(): walks up the parent chain to find an ancestor's
    // tooltip() when the widget under the mouse has none of its own
    // (a FlGroup's tooltip is inherited by children that don't set their
    // own -- matches FLTK's documented Fl_Widget::tooltip()
    // inheritance behavior).
    import fl.group : FlGroup;
    import fl.box : Box;

    FlGroup.current(null);
    fl.core.resetForTest();
    resetForTest();

    auto g = new FlGroup(0, 0, 100, 100);
    g.tooltip("group tip");
    auto child = new Box(10, 10, 20, 20);
    g.end();
    FlGroup.current(null);

    mouseEnter(child);
    assert(current() is child);
    assert(fl.core.hasTimeout(tooltipTimeoutCb_));

    exit(null);
    destroy(g); // destroys child too
    fl.core.resetForTest();
    resetForTest();
    FlGroup.current(null);
}
