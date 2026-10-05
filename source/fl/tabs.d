/*
 * Ported from FL/Fl_Tabs.H + src/Fl_Tabs.cxx (FLTK 1.5.0).
 *
 * A FlGroup that shows one child at a time, selected via a row of
 * clickable "file card" tabs drawn along the top or bottom edge
 * (whichever side has more free space, per tabHeight()). Faithful,
 * complete port of the tab layout math (tabPositions(), including the
 * OVERFLOW_COMPRESS shrink-around-the-selected-tab algorithm),
 * hit-testing, drag/keyboard/shortcut handling, and drawing -- with a
 * few deliberate, documented gaps where FLTK reaches for a
 * subsystem this port doesn't have yet:
 *
 *  - **The overflow popup menu is real now** (`handleOverflowMenu()`,
 *    built on `fl.menu_item.MenuItem` + `fl.menu_popup.popup()`, the
 *    same popup engine `fl.menu_button`/`fl.choice` use). One deviation:
 *    the picked item's tab is recovered via pointer arithmetic against
 *    the local `MenuItem[]` array instead of FLTK's `user_data()`
 *    -- this port's `MenuItem` has no such slot (see `fl.menu_item`'s
 *    doc comment), so there's nowhere to stash the corresponding tab
 *    widget directly the way FLTK does.
 *  - **Tooltip integration is real**. `maybeDoCallback()` calls `fl.tooltip.current(o)` after a
 *    tab is selected, and `handle()`'s `Event.move` case calls
 *    `fl.tooltip.mouseEnter(n)` whenever the hovered tab changes,
 *    matching FLTK's `Fl_Tooltip::current()`/`enter()` calls
 *    exactly (renamed from the bare `enter()` FLTK uses -- see
 *    `fl.tooltip.mouseEnter()`'s own doc comment for why).
 *  - **The close-button glyph is FLTK's real "@3+" glyph**:
 *    `drawCloseCross()` calls
 *    `drawSymbol("@3+", ...)` directly, matching FLTK exactly.
 *  - **`Fl_Widget_Tracker`'s deleted-during-callback guard is ported**
 *    (`fl.widget_tracker.WidgetTracker`, matching every other
 *    module in this port that has it, e.g. `fl.button`).
 *    `maybeDoCallback()` watches the newly-selected tab widget across
 *    this Tabs' own callback and bails out if it was destroyed as a
 *    side effect, matching FLTK's own comment on why the tracker
 *    watches the tab, not `this`.
 *  - **`Window.drawBackdrop()` is real** -- the "draw the tab bar's background
 *    against the parent window" branch of `draw()` calls it for real,
 *    matching FLTK's `win->draw_backdrop()` exactly.
 *  - **No destructor**: FLTK's `~Fl_Tabs()` only frees
 *    `tab_pos`/`tab_width`/`tab_flags`, which here are plain D dynamic
 *    arrays (see below) -- the GC reclaims them on its own.
 *
 * Storage simplification, not touching any layout/hit-test logic:
 * `tab_pos`/`tab_width`/`tab_flags` (manually `malloc()`-sized C
 * arrays, reallocated only when the child count actually changes,
 * purely as a perf optimization against needless churn) collapse to
 * plain D dynamic arrays, resized unconditionally on every
 * `tabPositions()` call (D's `.length =` is already cheap when the
 * length doesn't change, so the "did it actually change?" guard has
 * nothing left to optimize). `tab_count` itself isn't a separate
 * field -- `tabWidth_.length` already tracks the same thing (it's set
 * to `children()` every time `tabPositions()` runs).
 */
module fl.tabs;

import fl.group : FlGroup;
import fl.widget : Widget;
import fl.widget_tracker : WidgetTracker;
import fl.window : Window;
import fl.rect : Rect;
import fl.enumerations;
import fl.core;
import fl.menu_item : MenuItem, menuDivider;
import fl.menu_popup;
import fldraw = fl.draw;
import fl.symbols : drawSymbol;
import fltooltip = fl.tooltip;
import std.algorithm : min;
import std.math : abs;

/// Values for handleOverflow()/overflow-mode tracking; mirrors
/// Fl_Tabs.H's anonymous enum.
enum ubyte overflowCompress = 0;
enum ubyte overflowClip = 1;
enum ubyte overflowPulldown = 2;
enum ubyte overflowDrag = 3;

/// draw_tab()'s "which side of the selected tab" tag. Named tabLeft/
/// tabRight/tabSelected (not the bare left/right FLTK uses)
/// because fl.enumerations already defines Keysym constants named
/// left/right (used by this same module's FL_Left/FL_Right keyboard
/// handling) -- reusing those names here would collide.
private enum int tabLeft = 0;
private enum int tabRight = 1;
private enum int tabSelected = 2;

private enum int border = 2;
private enum int ovBorder = 2;
private enum int extraSpace = 10;
private enum int selectionBorder = 5;
private enum int extraGap = 2;
private enum int margin = 20;

class Tabs : FlGroup
{
    private Widget push_;
    private ubyte overflowType_ = overflowCompress;
    private int tabOffset_;
    private int[] tabPos_;   // nc+1 entries: left edges, plus one past the last tab
    private int[] tabWidth_; // nc entries
    private int[] tabFlags_; // nc entries; bit 0 = compressed/overlapped
    private Align tabAlign_ = alignCenter;
    private bool hasOverflowMenu_;

    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        box(Boxtype.thinUpBox);
    }

    void tabAlign(Align a) { tabAlign_ = a; }
    Align tabAlign() const { return tabAlign_; }

    protected override int onInsert(Widget candidate, int index)
    {
        redrawTabs();
        return super.onInsert(candidate, index);
    }

    protected override int onMove(int a, int b)
    {
        redrawTabs();
        return super.onMove(a, b);
    }

    protected override void onRemove(int index)
    {
        redrawTabs();
        if (child(index).visible())
        {
            if (index + 1 < children())
                value(child(index + 1));
            else if (index > 0)
                value(child(index - 1));
        }
        if (children() == 1)
            damage(damageAll);
        super.onRemove(index);
    }

    override void resize(int X, int Y, int W, int H)
    {
        redrawTabs();
        super.resize(X, Y, W, H);
    }

    /// Sets the tab bar's damage flag so it (and only it) redraws.
    protected void redrawTabs()
    {
        int H = tabHeight();
        if (H >= 0)
            damage(damageExpose, x(), y(), w(), H + selectionBorder);
        else
        {
            H = -H;
            damage(damageExpose, x(), y() + h() - H - selectionBorder, w(), H + selectionBorder);
        }
    }

    /// Vertical space usable for tabs: positive to put them at the
    /// top, negative for the bottom, magnitude is the tab bar height.
    protected int tabHeight()
    {
        if (children() == 0) return h();
        int H = h();
        int H2 = y();
        foreach (o; array())
        {
            if (o.y() < y() + H) H = o.y() - y();
            if (o.y() + o.h() > H2) H2 = o.y() + o.h();
        }
        H2 = y() + h() - H2;
        if (H2 > H) return (H2 <= 0) ? 0 : -H2;
        else return (H <= 0) ? 0 : H;
    }

    /**
     * Recomputes tabPos_/tabWidth_/tabFlags_ from each child's
     * measured label width, then (in OVERFLOW_COMPRESS mode) shrinks
     * tabs around the selected one until the whole bar fits.
     * Returns the selected child's index, or -1 if there are no children.
     */
    protected int tabPositions()
    {
        const int nc = children();
        tabPos_.length = nc + 1;
        tabWidth_.length = nc;
        tabFlags_.length = nc;
        if (nc == 0) return -1;

        int selected = 0;
        auto a = array();

        // Tab labels always show their '&' shortcut marker regardless of
        // each child's own shortcutLabel flag (a plain FlGroup, unlike
        // Fl_Button, never sets it) -- matches FLTK's own
        // Fl_Tabs::tab_positions()/draw_tab(), both of which force this
        // globally for the duration of their own label measuring/drawing.
        int prevDrawShortcut = fldraw.fl_draw_shortcut;
        fldraw.fl_draw_shortcut = 1;

        int l = tabPos_[0] = fl.core.boxDx(box());
        for (int i = 0; i < nc; i++)
        {
            Widget o = a[i];
            if (o.visible()) selected = i;

            int wt = 0, ht = 0;
            Labeltype ot = o.labeltype();
            Align oa = o.alignment();
            if (ot == Labeltype.noLabel)
                o.labeltype(Labeltype.normalLabel);
            o.alignment(tabAlign_);
            o.measureLabel(wt, ht);
            o.labeltype(ot);
            o.alignment(oa);

            if (o.when() & whenClosed)
                wt += labelsize() / 2 + extraGap;

            tabWidth_[i] = wt + extraSpace;
            tabPos_[i + 1] = tabPos_[i] + tabWidth_[i] + border;
            tabFlags_[i] = 0;
        }
        fldraw.fl_draw_shortcut = prevDrawShortcut;

        if (overflowType_ == overflowCompress)
        {
            int r = w() - fl.core.boxDw(box());
            if (nc > 1 && tabPos_[nc] > r)
            {
                int wdt = r - l;
                int available = wdt - tabWidth_[selected];
                if (available <= 8 * nc)
                {
                    for (int i = 0; i < nc; i++)
                    {
                        if (i < selected)
                        {
                            tabPos_[i] = l + 8 * i;
                            tabFlags_[i] |= 1;
                        }
                        else if (i > selected)
                        {
                            tabPos_[i] = r - (nc - i) * 8;
                            tabFlags_[i] |= 1;
                        }
                        else
                        {
                            tabPos_[i] = l + 8 * i;
                            tabFlags_[i] &= ~1;
                        }
                        tabPos_[nc] = r;
                    }
                }
                else
                {
                    int overflow = tabPos_[nc] - r;
                    int leftTotal = tabPos_[selected] - l;
                    int rightTotal = tabPos_[nc] - tabPos_[selected + 1];
                    int leftOverflow = (leftTotal + rightTotal) != 0
                        ? overflow * leftTotal / (leftTotal + rightTotal) : overflow;
                    int rightOverflow = overflow - leftOverflow;

                    int xdelta = 0;
                    for (int i = 0; i < selected; i++)
                    {
                        int tw = tabWidth_[i];
                        if (leftOverflow > 0)
                        {
                            tw -= leftOverflow;
                            if (tw < 8) tw = 8;
                            int wdelta = tabWidth_[i] - tw;
                            leftOverflow -= wdelta;
                            xdelta += wdelta;
                            if (wdelta > 16) tabFlags_[i] |= 1;
                        }
                        tabPos_[i + 1] -= xdelta;
                    }

                    xdelta = 0;
                    for (int i = nc - 1; i > selected; i--)
                    {
                        int tw = tabWidth_[i];
                        if (rightOverflow > 0)
                        {
                            tw -= rightOverflow;
                            if (tw < 8) tw = 8;
                            int wdelta = tabWidth_[i] - tw;
                            rightOverflow -= wdelta;
                            xdelta += wdelta;
                            if (wdelta > 4) tabFlags_[i] |= 1;
                        }
                        tabPos_[i] -= overflow - xdelta;
                    }
                    tabPos_[nc] = r;
                }
            }
        }
        return selected;
    }

    Widget which(int eventX, int eventY)
    {
        if (children() == 0) return null;
        int H = tabHeight();
        if (H < 0)
        {
            if (eventY > y() + h() || eventY < y() + h() + H) return null;
        }
        else
        {
            if (eventY > y() + H || eventY < y()) return null;
        }
        if (eventX < x()) return null;
        Widget ret = null;
        const int nc = children();
        tabPositions();
        for (int i = 0; i < nc; i++)
        {
            if (eventX < x() + tabPos_[i + 1] + tabOffset_)
            {
                ret = child(i);
                break;
            }
        }
        return ret;
    }

    protected int hitClose(Widget o, int eventX, int eventY)
    {
        for (int i = 0; i < children(); i++)
        {
            if (child(i) is o)
            {
                if (tabFlags_[i] & 1) return 0;
                int tabX = tabPos_[i] + tabOffset_ + x();
                return (eventX >= tabX && eventX < tabX + (labelsize() + extraSpace + extraGap) / 2) ? 1 : 0;
            }
        }
        return 0;
    }

    protected int hitOverflowMenu(int eventX, int eventY)
    {
        if (!hasOverflowMenu_) return 0;
        int H = tabHeight();
        if (eventX < x() + w() - abs(H) + ovBorder) return 0;
        if (H >= 0)
        {
            if (eventY > y() + H) return 0;
        }
        else
        {
            if (eventY < y() + h() + H) return 0;
        }
        return 1;
    }

    protected int hitTabsArea(int eventX, int eventY)
    {
        int H = tabHeight();
        if (H >= 0)
        {
            if (eventY > y() + H) return 0;
        }
        else
        {
            if (eventY < y() + h() + H) return 0;
        }
        if (hasOverflowMenu_ && eventX > x() + w() - abs(H) + ovBorder) return 0;
        return 1;
    }

    protected void checkOverflowMenu()
    {
        const int nc = children();
        if (nc == 0) { hasOverflowMenu_ = false; return; }
        int H = tabHeight();
        if (H < 0) H = -H;
        hasOverflowMenu_ = tabPos_[nc] > w() - H + ovBorder;
    }

    protected void takeFocus(Widget o)
    {
        if (o !is null && fl.core.visibleFocus() && fl.core.focus() !is this)
        {
            fl.core.focus(this);
            redrawTabs();
        }
    }

    protected int maybeDoCallback(Widget o)
    {
        if (o is null) return 0;

        int tabChanged = value(o);
        if (tabChanged) setChanged();

        if (tabChanged || (when() & whenNotChanged))
        {
            // Watches o (the newly-selected tab), not this -- this
            // Tabs' own callback (fired because the selection changed)
            // may itself delete the tab widget o that was just
            // selected, matching FLTK's own comment.
            auto wp = WidgetTracker(o);
            doCallback(CallbackReason.selected);
            if (wp.deleted()) return 0;
        }

        fltooltip.current(o);
        return 1;
    }

    /**
     * Builds a menu item per tab (visible ones in bold, a divider
     * separating the scrolled-off-left/scrolled-off-right groups from
     * the visible middle), pops it up below/above the overflow button,
     * and selects whichever tab the user picks. Ported from
     * Fl_Tabs::handle_overflow_menu(); the picked item's index is
     * recovered via pointer arithmetic against the local `items` array
     * rather than FLTK's `user_data()` (this port's `MenuItem` has
     * no such slot -- see `fl.menu_item`'s doc comment -- so there's
     * nothing to store the corresponding tab widget in directly).
     * `popup()` takes screen-absolute coordinates (`Widget.
     * topWindowOffset()` does the conversion), matching every other
     * caller of `fl.menu_popup` in this port.
     */
    protected void handleOverflowMenu()
    {
        const int nc = children();
        if (nc == 0) return;
        int H = tabHeight();
        if (H < 0) H = -H;
        int fv = -1, lv = nc;

        for (int i = 0; i < nc; i++)
        {
            if (tabPos_[i] + tabOffset_ < 0) fv = i;
            if (tabPos_[i] + tabWidth_[i] + tabOffset_ <= w() - H + ovBorder) lv = i;
        }

        auto items = new MenuItem[nc + 1]; // last one stays the null-text sentinel
        foreach (i; 0 .. nc)
        {
            items[i] = MenuItem(child(i).label());
            items[i].labelfont_ = labelfont();
            items[i].labelsize_ = labelsize();
            if (i == fv || i == lv) items[i].flags |= menuDivider;
            if (child(i).visible()) items[i].labelfont_ |= bold;
        }

        int xoff, yoff;
        auto topWin = topWindowOffset(xoff, yoff);
        int screenX = (topWin !is null ? topWin.x() : 0) + xoff + (w() - H + ovBorder);
        int screenY = (topWin !is null ? topWin.y() : 0) + yoff
            + (tabHeight() > 0 ? H : h() - ovBorder);

        auto picked = fl.menu_popup.popup(&items[0], screenX, screenY);
        if (picked !is null)
        {
            auto idx = picked - &items[0];
            if (idx >= 0 && idx < nc)
            {
                auto o = child(cast(int) idx);
                push(null);
                takeFocus(o);
                maybeDoCallback(o);
            }
        }
    }

    protected void drawOverflowMenuButton()
    {
        int H = tabHeight();
        int X, Y;
        if (H > 0)
        {
            X = x() + w() - H + ovBorder;
            if (ovBorder > 0)
                fldraw.fl_rectf(X, y(), H - ovBorder, ovBorder, color());
            Y = y() + ovBorder;
        }
        else
        {
            H = -H;
            X = x() + w() - H + ovBorder;
            Y = y() + h() - H;
            if (ovBorder > 0)
                fldraw.fl_rectf(X, Y + H - ovBorder, H - ovBorder, ovBorder, color());
        }
        H -= ovBorder;
        drawBox(box(), X, Y, H, H, color());
        auto r = Rect(X, Y, H, H);
        Color arrowColor = fldraw.contrast(fl_gray_ramp(0), color());
        if (!activeR())
            arrowColor = fldraw.inactive(arrowColor);
        fldraw.drawArrow(r, ArrowType.arrowChoice, Orientation.orientNone, arrowColor);
    }

    /// Draws the close-button glyph, via `fl.symbols`'s general
    /// `@`-symbol mini-language: matches FLTK's own
    /// `fl_draw_symbol("@3+", ...)`
    /// exactly (rotation digit '3' = 315 degrees applied to the "+"
    /// symbol, giving a diagonal X).
    private void drawCloseCross(int cx, int cy, int cw, int ch, Color col)
    {
        drawSymbol("@3+", cx, cy, cw, ch, col);
    }

    override void draw()
    {
        if (children() == 0)
        {
            fldraw.fl_rectf(x(), y(), w(), h(), color());
            if (alignment() & alignInside)
                drawLabel();
            clearDamage();
            return;
        }

        Widget selectedChild = value();
        tabPositions();
        int selected = find(selectedChild);
        if (selected == children()) selected = -1;
        int H = tabHeight();
        Color selectedTabColor = selectedChild !is null ? selectedChild.color() : color();
        bool tabsAtTop = (H > 0);
        bool coloredSelectionBorder = (selectionColor() != selectedTabColor);

        int tabsY, tabsH;
        int childAreaY, childAreaH;
        int clippedChildAreaY, clippedChildAreaH;
        int selectionBorderY, selectionBorderH;

        selectionBorderH = coloredSelectionBorder ? selectionBorder : fl.core.boxDx(box());

        if (tabsAtTop)
        {
            tabsH = H;
            tabsY = y();
            selectionBorderY = y() + tabsH;
            childAreaY = y() + tabsH;
            childAreaH = h() - tabsH;
            clippedChildAreaY = y() + tabsH + selectionBorderH;
            clippedChildAreaH = h() - tabsH - selectionBorderH;
        }
        else
        {
            tabsH = -H;
            tabsY = y() + h() - tabsH;
            selectionBorderY = tabsY - selectionBorderH;
            childAreaY = y();
            childAreaH = h() - tabsH;
            clippedChildAreaY = y();
            clippedChildAreaH = h() - tabsH - selectionBorderH;
        }

        if (damage() & (damageAll | damageScroll))
        {
            Widget selectedTab = value();
            if (selectedTab !is null) value(selectedTab);
        }

        if (damage() & (damageAll | damageExpose | damageScroll))
        {
            if (parent !is null)
            {
                // Cast always safe: a Tabs's own parent is always a
                // real FlGroup or null (see Widget.parent()'s own doc
                // comment / FlGroup.end()'s identical cast).
                FlGroup p = cast(FlGroup) parent;
                fldraw.pushClip(x(), tabsY, w(), tabsH);
                Window win = p.asWindow();
                if (win !is null)
                {
                    p.drawBox(p.box(), 0, 0, p.w(), p.h(), p.color());
                    win.drawBackdrop();
                }
                else
                {
                    p.drawBox(p.box(), p.x(), p.y(), p.w(), p.h(), p.color());
                }
                fldraw.popClip();
            }
            else
            {
                fldraw.fl_rectf(x(), tabsY, w(), tabsH, color());
            }

            fldraw.pushClip(x(), selectionBorderY, w(), selectionBorderH);
            if (coloredSelectionBorder)
            {
                drawBox(box(), x(), y(), w(), h(), selectedTabColor);
                drawBox(box(), x(), selectionBorderY, w(), selectionBorderH, selectionColor());
            }
            else
            {
                drawBox(box(), x(), childAreaY, w(), childAreaH, selectedTabColor);
            }
            if (selected != -1)
            {
                int stemX = x() + tabPos_[selected] + tabOffset_;
                int stemW = min(tabPos_[selected + 1] - tabPos_[selected], tabWidth_[selected]);
                if (coloredSelectionBorder)
                {
                    if (tabsAtTop)
                        fldraw.fl_rectf(stemX, selectionBorderY, stemW, selectionBorderH / 2, selectionColor());
                    else
                        fldraw.fl_rectf(stemX, selectionBorderY + selectionBorderH - selectionBorderH / 2,
                            stemW, selectionBorderH / 2, selectionColor());
                }
                else
                {
                    fldraw.fl_rectf(stemX, childAreaY - tabsH, stemW, childAreaH + 2 * tabsH, selectionColor());
                }
            }
            fldraw.popClip();

            fldraw.pushClip(x(), tabsY, w(), tabsH);
            int clipLeft, clipRight;
            int safeSelected = selected == -1 ? children() : selected;
            clipLeft = x();
            for (int i = 0; i < safeSelected; i++)
            {
                clipRight = (i < cast(int) tabWidth_.length - 1)
                    ? x() + (tabOffset_ + tabPos_[i + 1] + tabWidth_[i + 1] / 2)
                    : x() + w();
                fldraw.pushClip(clipLeft, tabsY, clipRight - clipLeft, tabsH);
                drawTab(x() + tabPos_[i], x() + tabPos_[i + 1], tabWidth_[i], H, child(i), tabFlags_[i], tabLeft);
                fldraw.popClip();
            }
            clipRight = x() + w();
            for (int i = children() - 1; i > safeSelected; i--)
            {
                clipLeft = (i > 0) ? (tabOffset_ + tabPos_[i] - tabWidth_[i - 1] / 2) : x();
                fldraw.pushClip(clipLeft, tabsY, clipRight - clipLeft, tabsH);
                drawTab(x() + tabPos_[i], x() + tabPos_[i + 1], tabWidth_[i], H, child(i), tabFlags_[i], tabRight);
                fldraw.popClip();
            }
            if (selected > -1)
                drawTab(x() + tabPos_[selected], x() + tabPos_[selected + 1], tabWidth_[selected], H,
                    selectedChild, tabFlags_[selected], tabSelected);
            fldraw.popClip();

            if (overflowType_ == overflowPulldown) checkOverflowMenu();
            if (hasOverflowMenu_) drawOverflowMenuButton();
        }

        if (damage() & (damageAll | damageChild))
        {
            fldraw.pushClip(x(), clippedChildAreaY, w(), clippedChildAreaH);
            if (damage() & damageAll)
            {
                if (coloredSelectionBorder)
                    drawBox(box(), x(), y(), w(), h(), selectedTabColor);
                else
                    drawBox(box(), x(), childAreaY, w(), childAreaH, selectedTabColor);
                if (selectedChild !is null) drawChild(selectedChild);
            }
            else if (damage() & damageChild)
            {
                if (selectedChild !is null) updateChild(selectedChild);
            }
            fldraw.popClip();
        }

        clearDamage();
    }

    protected void drawTab(int x1In, int x2In, int W, int H, Widget o, int flags, int what)
    {
        int x1 = x1In + tabOffset_;
        int x2 = x2In + tabOffset_;
        bool sel = (what == tabSelected);
        int dh = fl.core.boxDh(box());
        int wc = 0;

        // See tabPositions()'s own comment -- tab labels always show
        // their '&' shortcut marker, regardless of the child's own
        // shortcutLabel flag.
        int prevDrawShortcut = fldraw.fl_draw_shortcut;
        fldraw.fl_draw_shortcut = 1;

        Boxtype bt = (o is push_ && !sel) ? fl_down(box()) : box();
        Color bc = sel ? selectionColor() : o.selectionColor();

        Color oc = o.labelcolor();
        Labeltype ot = o.labeltype();

        if (ot == Labeltype.noLabel)
            o.labeltype(Labeltype.normalLabel);

        int yofs = sel ? 0 : border;

        if (x2 < x1 + W && what == tabRight) x1 = x2 - W;

        if (H >= 0)
        {
            H += dh;
            drawBox(bt, x1, y() + yofs, W, H + 10 - yofs, bc);

            o.labelcolor(sel ? labelcolor() : o.labelcolor());

            if ((o.when() & whenClosed) && !(flags & 1))
            {
                int sz = labelsize() / 2;
                int sy = (H - sz) / 2;
                Color closeColor = fldraw.contrast(fl_gray_ramp(0), bc);
                if (!activeR()) closeColor = fldraw.inactive(closeColor);
                drawCloseCross(x1 + extraSpace / 2, y() + yofs / 2 + sy, sz, sz, closeColor);
                wc = sz + extraGap;
            }

            o.drawLabel(x1 + wc, y() + yofs, W - wc, H - yofs, tabAlign_);

            if (fl.core.focus() is this && o.visible())
                drawFocus(bt, x1, y(), W, H, bc);
        }
        else
        {
            H = -H;
            H += dh;
            drawBox(bt, x1, y() + h() - H - 10, W, H + 10 - yofs, bc);

            o.labelcolor(sel ? labelcolor() : o.labelcolor());

            if ((o.when() & whenClosed) && (x1 + W < x2))
            {
                int sz = labelsize() / 2;
                int sy = (H - sz) / 2;
                Color closeColor = fldraw.contrast(fl_gray_ramp(0), bc);
                if (!activeR()) closeColor = fldraw.inactive(closeColor);
                drawCloseCross(x1 + extraSpace / 2, y() + h() - H - yofs / 2 + sy, sz, sz, closeColor);
                wc = sz + extraGap;
            }

            o.drawLabel(x1 + wc, y() + h() - H, W - wc, H - yofs, tabAlign_);

            if (fl.core.focus() is this && o.visible())
                drawFocus(bt, x1, y() + h() - H + 1, W, H, bc);
        }

        fldraw.fl_draw_shortcut = prevDrawShortcut;
        o.labelcolor(oc);
        o.labeltype(ot);
    }

    override int handle(Event event)
    {
        static int initialX;
        static int initialTabOffset;
        static bool forwardMotionToGroup;
        static Widget oPushDrag;

        int mx = fl.core.eventX();
        int my = fl.core.eventY();

        switch (event)
        {
        case Event.mouseWheel:
            if ((overflowType_ == overflowDrag || overflowType_ == overflowPulldown)
                    && children() > 0 && hitTabsArea(mx, my))
            {
                int originalTabOffset = tabOffset_;
                tabOffset_ -= 2 * fl.core.eventDx();
                if (tabOffset_ > 0) tabOffset_ = 0;
                int m = 0;
                if (overflowType_ == overflowPulldown) m = abs(tabHeight());
                int dw = tabPos_[children()] + tabOffset_ - w();
                if (dw < -m) tabOffset_ -= dw + m;
                if (tabOffset_ != originalTabOffset) redrawTabs();
                return 1;
            }
            return super.handle(event);

        case Event.push:
            initialX = mx;
            initialTabOffset = tabOffset_;
            forwardMotionToGroup = false;
            if (hitOverflowMenu(mx, my))
            {
                handleOverflowMenu();
                return 1;
            }
            if (!hitTabsArea(mx, my))
                forwardMotionToGroup = true;
            goto case;

        case Event.drag:
            oPushDrag = which(mx, my);
            goto case;

        case Event.release:
        {
            if (forwardMotionToGroup)
                return super.handle(event);

            Widget o = which(mx, my);
            if (event == Event.release && o !is oPushDrag)
                return 1;

            if ((overflowType_ == overflowDrag || overflowType_ == overflowPulldown) && children() > 0)
            {
                if (tabPos_[children()] < w() && tabOffset_ == 0)
                {
                    // fall through to plain tab-selection handling below
                }
                else if (!fl.core.eventIsClick())
                {
                    tabOffset_ = initialTabOffset + mx - initialX;
                    int m = 0;
                    if (overflowType_ == overflowPulldown) m = abs(tabHeight()) - ovBorder;
                    if (tabOffset_ > 0)
                    {
                        initialTabOffset -= tabOffset_;
                        tabOffset_ = 0;
                    }
                    else
                    {
                        int dw = tabPos_[children()] + tabOffset_ - w();
                        if (dw < -m)
                        {
                            initialTabOffset -= dw + m;
                            tabOffset_ -= dw + m;
                        }
                    }
                    redrawTabs();
                    return 1;
                }
            }
            if (event == Event.release)
            {
                push(null);
                takeFocus(o);
                if (o !is null && (o.when() & whenClosed) && hitClose(o, mx, my))
                {
                    o.doCallback(CallbackReason.closed);
                    return 1; // o may be deleted at this point
                }
                maybeDoCallback(o);
            }
            else
            {
                push(o);
            }
            return 1;
        }

        case Event.move:
        {
            int ret = super.handle(event);
            int H = tabHeight();
            if (H >= 0 && my > y() + H) return ret;
            if (H < 0 && my < y() + h() + H) return ret;
            Widget tooltipWidget = fltooltip.current();
            Widget n = which(mx, my);
            if (n is null) n = this;
            if (n !is tooltipWidget) fltooltip.mouseEnter(n);
            return ret;
        }

        case Event.focus:
        case Event.unfocus:
            if (!fl.core.visibleFocus()) return super.handle(event);
            {
                Event e = fl.core.event();
                if (e == Event.release || e == Event.shortcut || e == Event.keyDown
                        || e == Event.focus || e == Event.unfocus)
                {
                    redrawTabs();
                    if (e == Event.focus) return super.handle(event);
                    if (e == Event.unfocus) return 0;
                    return 1;
                }
            }
            return super.handle(event);

        case Event.keyDown:
        {
            int i;
            switch (fl.core.eventKey())
            {
            case left:
                if (!children()) return 0;
                if (child(0).visible()) return 0;
                for (i = 1; i < children(); i++)
                    if (child(i).visible()) break;
                value(child(i - 1));
                setChanged();
                doCallback(CallbackReason.selected);
                return 1;
            case right:
                if (!children()) return 0;
                if (child(children() - 1).visible()) return 0;
                for (i = 0; i < children() - 1; i++)
                    if (child(i).visible()) break;
                value(child(i + 1));
                setChanged();
                doCallback(CallbackReason.selected);
                return 1;
            case down:
                redraw();
                return super.handle(Event.focus);
            default:
                break;
            }
            return super.handle(event);
        }

        case Event.shortcut:
            for (int i = 0; i < children(); i++)
            {
                Widget c = child(i);
                if (Widget.testShortcut(c.label()))
                {
                    bool sc = !c.visible();
                    value(c);
                    if (sc)
                    {
                        setChanged();
                        doCallback(CallbackReason.selected);
                    }
                    else
                    {
                        doCallback(CallbackReason.reselected);
                    }
                    return 1;
                }
            }
            return super.handle(event);

        case Event.show:
            value(); // update visibilities, then fall through to FlGroup's own handling
            return super.handle(event);

        default:
            return super.handle(event);
        }
    }

    /// Sets/gets the tab widget the user last pushed on (null once
    /// released or dragged off). Mainly used by drawTab() to draw a
    /// "down" box for the pushed tab.
    int push(Widget o)
    {
        if (push_ is o) return 0;
        if ((push_ !is null && !push_.visible()) || (o !is null && !o.visible()))
            redrawTabs();
        push_ = o;
        return 1;
    }

    Widget push() { return push_; }

    /**
     * Returns the currently visible child, showing the first visible
     * one found and hiding the rest -- or, if none are visible, forces
     * the last child visible. Ensures exactly one child is shown.
     */
    Widget value()
    {
        Widget v = null;
        auto a = array();
        foreach (idx, o; a)
        {
            if (v !is null) o.hide();
            else if (o.visible()) v = o;
            else if (idx == a.length - 1) { o.show(); v = o; }
        }
        return v;
    }

    /// Makes newvalue the visible child (hiding all others). Returns 1
    /// if this changed which child was visible, 0 otherwise.
    int value(Widget newvalue)
    {
        auto a = array();
        int ret = 0;
        int selected = -1;
        foreach (idx, o; a)
        {
            if (o is newvalue)
            {
                if (!o.visible()) ret = 1;
                o.show();
                selected = cast(int) idx;
            }
            else
            {
                o.hide();
            }
        }

        if (selected >= 0 && (overflowType_ == overflowDrag || overflowType_ == overflowPulldown))
        {
            int m = margin;
            if (selected == 0 || selected == children() - 1) m = border;
            int mr = m;
            tabPositions();
            if (overflowType_ == overflowPulldown) mr += abs(tabHeight() - ovBorder);
            if (tabPos_[selected] + tabWidth_[selected] + tabOffset_ + mr > w())
                tabOffset_ = w() - tabPos_[selected] - tabWidth_[selected] - mr;
            else if (tabPos_[selected] + tabOffset_ - m < 0)
                tabOffset_ = -tabPos_[selected] + m;
        }

        redrawTabs();
        return ret;
    }

    /// Same as value(child(ix)); returns 0 (no change) if ix is out of range.
    int value(int ix)
    {
        if (ix < 0 || ix >= children()) return 0;
        return value(child(ix));
    }

    /// Position/size available for children, in rx/ry/rw/rh. If there
    /// are no children yet, estimates from tabh (0: top, computed
    /// height; -1: bottom, computed height; >0/<-1: explicit height,
    /// top/bottom respectively) and the current labelfont()/labelsize().
    void clientArea(out int rx, out int ry, out int rw, out int rh, int tabh = 0)
    {
        if (children())
        {
            rx = child(0).x();
            ry = child(0).y();
            rw = child(0).w();
            rh = child(0).h();
        }
        else
        {
            int yOffset;
            int labelHeight = fldraw.height(labelfont(), labelsize()) + border * 2;

            if (tabh == 0) yOffset = labelHeight;
            else if (tabh == -1) yOffset = -labelHeight;
            else yOffset = tabh;

            rx = x();
            rw = w();

            if (yOffset >= 0) { ry = y() + yOffset; rh = h() - yOffset; }
            else { ry = y(); rh = h() + yOffset; }
        }
    }

    /// Sets how an overflowing tab bar (more tabs than fit) is
    /// handled: overflowCompress (default), overflowClip,
    /// overflowPulldown, or overflowDrag.
    void handleOverflow(ubyte ov)
    {
        overflowType_ = ov;
        tabOffset_ = 0;
        hasOverflowMenu_ = false;
        damage(damageScroll);
        redraw();
    }
}

unittest
{
    FlGroup.current(null);

    auto t = new Tabs(0, 0, 300, 200);
    assert(t.box() == Boxtype.thinUpBox);
    assert(t.children() == 0);
    t.end();

    FlGroup.current(null);
}

unittest
{
    // The first child added becomes the visible tab; adding a second
    // hides it once value() reconciles visibility (matches FLTK:
    // exactly one child is visible at a time).
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto t = new Tabs(0, 0, 300, 200);
    auto g1 = new FlGroup(20, 20, 260, 160, "One");
    g1.end();
    auto g2 = new FlGroup(20, 20, 260, 160, "Two");
    g2.end();
    t.end();

    assert(t.value() is g1);
    assert(g2.visible() == false);

    FlGroup.current(null);
}

unittest
{
    // value(Widget)/value(int) select a tab and hide the rest; value()
    // reports the currently selected one.
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto t = new Tabs(0, 0, 300, 200);
    auto g1 = new FlGroup(20, 20, 260, 160, "One");
    g1.end();
    auto g2 = new FlGroup(20, 20, 260, 160, "Two");
    g2.end();
    auto g3 = new FlGroup(20, 20, 260, 160, "Three");
    g3.end();
    t.end();

    t.value(); // reconcile: exactly one (the first, g1) starts visible
    assert(t.value(g2) == 1); // changed
    assert(t.value() is g2);
    assert(!g1.visible() && g2.visible() && !g3.visible());

    assert(t.value(g2) == 0); // already selected: no change
    assert(t.value(1) == 0);  // g2 is index 1: still no change
    assert(t.value(2) == 1);
    assert(t.value() is g3);

    FlGroup.current(null);
}

unittest
{
    // onRemove(): removing the visible tab selects a neighbor (prefers
    // the next one, falls back to the previous).
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto t = new Tabs(0, 0, 300, 200);
    auto g1 = new FlGroup(20, 20, 260, 160, "One");
    g1.end();
    auto g2 = new FlGroup(20, 20, 260, 160, "Two");
    g2.end();
    auto g3 = new FlGroup(20, 20, 260, 160, "Three");
    g3.end();
    t.end();

    t.value(g2);
    t.deleteChild(t.find(g2));
    assert(t.value() is g3); // the next one (index after g2) is preferred

    t.value(g3);
    t.deleteChild(t.find(g3));
    assert(t.value() is g1); // only one left, falls back to previous

    FlGroup.current(null);
}

unittest
{
    // tabPositions(): tab widths are the measured label width plus
    // EXTRASPACE, laid out left to right with BORDER between them.
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto t = new Tabs(0, 0, 400, 200);
    auto g1 = new FlGroup(20, 20, 360, 160, "AA");
    g1.end();
    auto g2 = new FlGroup(20, 20, 360, 160, "BBBBBB");
    g2.end();
    t.end();

    t.tabPositions();
    assert(t.tabWidth_[0] > 0 && t.tabWidth_[1] > t.tabWidth_[0]); // longer label -> wider tab
    assert(t.tabPos_[0] == fl.core.boxDx(t.box()));
    assert(t.tabPos_[1] == t.tabPos_[0] + t.tabWidth_[0] + border);
    assert(t.tabPos_[2] == t.tabPos_[1] + t.tabWidth_[1] + border);

    FlGroup.current(null);
}

unittest
{
    // which(): hit-testing maps a point in the tab bar back to the
    // right child, based on the positions tabPositions() computed.
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto t = new Tabs(0, 0, 400, 200);
    auto g1 = new FlGroup(20, 20, 360, 160, "AA");
    g1.end();
    auto g2 = new FlGroup(20, 20, 360, 160, "BB");
    g2.end();
    t.end();

    t.tabPositions();
    int H = t.tabHeight();
    assert(H > 0); // tabs at top (children leave room above them)

    assert(t.which(t.x() + t.tabPos_[0] + 1, t.y() + H / 2) is g1);
    assert(t.which(t.x() + t.tabPos_[1] + 1, t.y() + H / 2) is g2);
    assert(t.which(t.x() - 5, t.y() + H / 2) is null); // left of the tabs entirely

    FlGroup.current(null);
}

unittest
{
    // which(), tabs at the bottom (H < 0): the H<0 branches in
    // tabHeight()/which() are a hand-transcribed sign-flipped mirror
    // of the H>=0 ones (y() -> y()+h()+H), same mirror-transcription
    // hazard as fl.tile's L/R-vs-T/B helpers and fl.grid's row-vs-
    // column code -- needs its own execution, not just "top tabs work".
    import fl.group : FlGroup;
    FlGroup.current(null);

    // More gap below the children (45px) than above (5px) -> tabs
    // relocate to the bottom.
    auto t = new Tabs(0, 0, 400, 200);
    auto g1 = new FlGroup(20, 5, 360, 150, "AA");
    g1.end();
    auto g2 = new FlGroup(20, 5, 360, 150, "BB");
    g2.end();
    t.end();

    t.value(); // reconcile: exactly one (the first, g1) starts visible
    t.tabPositions();
    int H = t.tabHeight();
    assert(H < 0); // tabs at the bottom

    int stripY = t.y() + t.h() + H / 2; // middle of the bottom tab strip
    assert(t.which(t.x() + t.tabPos_[0] + 1, stripY) is g1);
    assert(t.which(t.x() + t.tabPos_[1] + 1, stripY) is g2);
    assert(t.which(t.x() + t.tabPos_[1] + 1, t.y() + 5) is null); // top: outside the strip now

    FlGroup.current(null);
}

unittest
{
    // handle(): clicking a tab selects it and fires the callback with
    // CallbackReason.selected.
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto t = new Tabs(0, 0, 400, 200);
    auto g1 = new FlGroup(20, 20, 360, 160, "AA");
    g1.end();
    auto g2 = new FlGroup(20, 20, 360, 160, "BB");
    g2.end();
    t.end();

    t.value(); // reconcile: exactly one (the first, g1) starts visible
    t.tabPositions();
    int H = t.tabHeight();
    int tabX = t.x() + t.tabPos_[1] + 1;
    int tabY = t.y() + H / 2;

    CallbackReason lastReason;
    Widget lastValue;
    t.callback((w) {
        lastReason = fl.core.callbackReason();
        lastValue = (cast(Tabs) w).value();
    });

    g2.tooltip("G2 tip"); // maybeDoCallback() only tracks a widget that
                          // has one somewhere in its own ancestor chain
                          // (matches Fl_Tooltip::current()'s own walk).

    fl.core.eX_ = tabX;
    fl.core.eY_ = tabY;
    assert(t.handle(Event.push) == 1);
    assert(t.handle(Event.release) == 1);

    assert(lastReason == CallbackReason.selected);
    assert(lastValue is g2);
    assert(t.value() is g2);
    assert(fltooltip.current() is g2);

    fl.core.resetForTest();
    FlGroup.current(null);
}

unittest
{
    // handle(): Event.move over a tab with a tooltip string updates
    // fl.tooltip.current() -- ported from Fl_Tabs::handle()'s own
    // FL_MOVE case, ` Fl_Tooltip::current()`/`enter()`.
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto t = new Tabs(0, 0, 400, 200);
    auto g1 = new FlGroup(20, 20, 360, 160, "AA");
    g1.end();
    auto g2 = new FlGroup(20, 20, 360, 160, "BB");
    g2.end();
    t.end();

    g2.tooltip("G2 tip");

    t.value();
    t.tabPositions();
    int H = t.tabHeight();

    fl.core.eX_ = t.x() + t.tabPos_[1] + 1;
    fl.core.eY_ = t.y() + H / 2;
    t.handle(Event.move);

    assert(fltooltip.current() is g2);

    fl.core.resetForTest();
    FlGroup.current(null);
}

unittest
{
    // handleOverflow()/OVERFLOW_COMPRESS: many narrow tabs that don't
    // fit get compressed (flagged bit 0) except the selected one.
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto t = new Tabs(0, 0, 100, 100); // deliberately narrow
    FlGroup[] tabs;
    foreach (i; 0 .. 8)
    {
        auto g = new FlGroup(20, 20, 60, 60, "Tab label " ~ cast(char)('A' + i));
        g.end();
        tabs ~= g;
    }
    t.end();

    t.value(tabs[4]);
    int selected = t.tabPositions();
    assert(selected == 4);
    assert((t.tabFlags_[4] & 1) == 0); // selected tab never compressed
    // With 8 wide-labeled tabs crammed into 100px, at least some
    // neighbor must be compressed.
    bool anyCompressed = false;
    foreach (i, f; t.tabFlags_)
        if (i != 4 && (f & 1)) anyCompressed = true;
    assert(anyCompressed);

    FlGroup.current(null);
}

unittest
{
    // draw() calls into fl.draw's real-on-Linux-only primitives, which
    // no-op safely without an open display (same pattern as other
    // widgets' draw() unittests) -- just confirm no exception, for
    // both the empty-tabs and populated-tabs paths.
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto empty = new Tabs(0, 0, 200, 100);
    empty.end();
    empty.draw();

    auto t = new Tabs(0, 0, 200, 100);
    auto g1 = new FlGroup(10, 30, 180, 60, "One");
    g1.end();
    auto g2 = new FlGroup(10, 30, 180, 60, "Two");
    g2.end();
    t.end();
    t.draw();

    FlGroup.current(null);
}
