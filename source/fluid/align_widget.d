/**
 * Alignment/distribute/same-size/center-in-group operations over a
 * multi-widget selection.
 *
 * Ported from FLTK's `fluid/proj/align_widget.h`/`.cxx`
 * (`align_widget_cb()`, a single `Fl_Callback`-shaped function keyed by
 * an integer "how" code, invoked from `app/Menu.cxx`'s `&Layout` menu).
 * This port re-expresses the numeric codes as a real D enum
 * (`AlignHow`) rather than a bare `int` cast through `void*
 * user_data` -- see CLAUDE.md's "Closed, non-combinable tag sets ...
 * become real D enums" convention -- and returns whether anything
 * changed instead of reaching into a project-wide `Fluid.proj.undo`/
 * `Fluid.proj.tree` singleton this port doesn't have; the caller
 * (`gui_main.d`) already owns checkpointing/redraw and decides what to
 * do with that result, matching FLTK's own `changed`-gated
 * `Fluid.proj.undo.checkpoint()`/`Fluid.proj.set_modflag(1)` calls one
 * level up instead of duplicating that bookkeeping in here.
 *
 * **`BREAK_ON_FIRST` note**: FLTK's own file has
 * `#define BREAK_ON_FIRST break` active (with a commented-out empty
 * alternative right next to it), which switches every "align" (10-15)
 * and "make same size" (30-32) case between two behaviors: reference =
 * the *first* selected widget (the currently-active behavior, per its
 * own doc comment) or reference = the most extreme bound across the
 * whole selection (the commented-out alternative). Ported faithfully
 * as the currently-active, first-selected-widget-as-reference
 * behavior -- "space evenly" (20-21) and "center in group" (40-41)
 * were never gated by this `#define` FLTK either, and still scan
 * the full selection here, unchanged.
 *
 * **Selection order note**: FLTK's `Fluid.proj.tree.
 * all_selected_widgets()` iterates the project tree in document order,
 * not click order. This port's own selection (`fluid.canvas.
 * ProjectCanvas.selected()`) is in click/Ctrl-Shift-click order
 * instead (see that module's own top comment) -- a harmless,
 * already-established divergence (this port's `primarySelection()` is
 * likewise "last clicked", not "last in the tree"), and the only
 * operations it can actually change the *result* of are the
 * first-selected-as-reference cases just above (now "first clicked"
 * rather than "first in the tree") and "space evenly"'s left-to-right/
 * top-to-bottom accumulation order, which already assumed a spatially
 * coherent selection either way.
 */
module fluid.align_widget;

import fluid.node : Node;
import fluid.widget_node : WidgetNode;
import fluid.window_node : WindowNode;
import fluid.instantiate : LiveTree;

/// Mirrors FLTK's numeric "how" codes exactly (`app/Menu.cxx`'s
/// `&Layout` submenu: `&Align` = 10-15, `&Space Evenly` = 20-21,
/// `&Make Same Size` = 30-32, `&Center In Group` = 40-41).
enum AlignHow
{
    left = 10,
    hCenter = 11,
    right = 12,
    top = 13,
    vCenter = 14,
    bottom = 15,

    spaceAcross = 20,
    spaceDown = 21,

    sameWidth = 30,
    sameHeight = 31,
    sameSize = 32,

    centerHorizontal = 40,
    centerVertical = 41,
}

private void applyResize(WidgetNode wn, int x, int y, int w, int h, LiveTree live)
{
    wn.x = x;
    wn.y = y;
    wn.w = w;
    wn.h = h;
    wn.hasXywh = true;

    if (auto widget = live.widgetOf.get(wn, null))
        widget.resize(x, y, w, h);
}

/// Applies alignment `how` to every `WidgetNode` in `selected`
/// (non-`WidgetNode` entries are silently skipped -- nothing in this
/// port's palette currently produces one, but `ProjectCanvas.
/// selected()` isn't itself restricted to widgets). Returns `true` if
/// at least one widget was actually moved/resized, mirroring FLTK's
/// own `changed` flag.
bool alignWidgets(AlignHow how, Node[] selected, LiveTree live)
{
    enum max = 32_768;
    enum min = -32_768;
    bool changed;

    WidgetNode[] widgets;
    foreach (n; selected)
        if (auto wn = cast(WidgetNode) n)
            widgets ~= wn;

    final switch (how)
    {
    case AlignHow.left:
        if (widgets.length)
        {
            int left = widgets[0].x;
            foreach (wn; widgets)
            {
                changed = true;
                applyResize(wn, left, wn.y, wn.w, wn.h, live);
            }
        }
        break;

    case AlignHow.hCenter:
        if (widgets.length)
        {
            int left = widgets[0].x;
            int right = widgets[0].x + widgets[0].w;
            int center2 = left + right;
            foreach (wn; widgets)
            {
                changed = true;
                applyResize(wn, (center2 - wn.w) / 2, wn.y, wn.w, wn.h, live);
            }
        }
        break;

    case AlignHow.right:
        if (widgets.length)
        {
            int right = widgets[0].x + widgets[0].w;
            foreach (wn; widgets)
            {
                changed = true;
                applyResize(wn, right - wn.w, wn.y, wn.w, wn.h, live);
            }
        }
        break;

    case AlignHow.top:
        if (widgets.length)
        {
            int top = widgets[0].y;
            foreach (wn; widgets)
            {
                changed = true;
                applyResize(wn, wn.x, top, wn.w, wn.h, live);
            }
        }
        break;

    case AlignHow.vCenter:
        if (widgets.length)
        {
            int top = widgets[0].y;
            int bot = widgets[0].y + widgets[0].h;
            int center2 = top + bot;
            foreach (wn; widgets)
            {
                changed = true;
                applyResize(wn, wn.x, (center2 - wn.h) / 2, wn.w, wn.h, live);
            }
        }
        break;

    case AlignHow.bottom:
        if (widgets.length)
        {
            int bot = widgets[0].y + widgets[0].h;
            foreach (wn; widgets)
            {
                changed = true;
                applyResize(wn, wn.x, bot - wn.h, wn.w, wn.h, live);
            }
        }
        break;

    case AlignHow.spaceAcross:
    {
        int left = max, right = min, wdt = 0;
        foreach (wn; widgets)
        {
            if (wn.x < left) left = wn.x;
            if (wn.x + wn.w > right) right = wn.x + wn.w;
            wdt += wn.w;
        }
        wdt = (right - left) - wdt;
        int n = cast(int) widgets.length - 1;
        if (n > 0)
        {
            wdt = wdt / n * n; // keep every gap identical, possibly moving the rightmost widget
            int cnt = 0, wsum = 0;
            foreach (wn; widgets)
            {
                changed = true;
                applyResize(wn, left + wsum + wdt * cnt / n, wn.y, wn.w, wn.h, live);
                cnt++;
                wsum += wn.w;
            }
        }
        break;
    }

    case AlignHow.spaceDown:
    {
        int top = max, bot = min, hgt = 0;
        foreach (wn; widgets)
        {
            if (wn.y < top) top = wn.y;
            if (wn.y + wn.h > bot) bot = wn.y + wn.h;
            hgt += wn.h;
        }
        hgt = (bot - top) - hgt;
        int n = cast(int) widgets.length - 1;
        if (n > 0)
        {
            hgt = hgt / n * n;
            int cnt = 0, hsum = 0;
            foreach (wn; widgets)
            {
                changed = true;
                applyResize(wn, wn.x, top + hsum + hgt * cnt / n, wn.w, wn.h, live);
                cnt++;
                hsum += wn.h;
            }
        }
        break;
    }

    case AlignHow.sameWidth:
        if (widgets.length)
        {
            int wdt = widgets[0].w;
            foreach (wn; widgets)
            {
                changed = true;
                applyResize(wn, wn.x, wn.y, wdt, wn.h, live);
            }
        }
        break;

    case AlignHow.sameHeight:
        if (widgets.length)
        {
            int hgt = widgets[0].h;
            foreach (wn; widgets)
            {
                changed = true;
                applyResize(wn, wn.x, wn.y, wn.w, hgt, live);
            }
        }
        break;

    case AlignHow.sameSize:
        if (widgets.length)
        {
            int wdt = widgets[0].w;
            int hgt = widgets[0].h;
            foreach (wn; widgets)
            {
                changed = true;
                applyResize(wn, wn.x, wn.y, wdt, hgt, live);
            }
        }
        break;

    case AlignHow.centerHorizontal:
        foreach (wn; widgets)
        {
            auto p = cast(WidgetNode) wn.parent;
            if (p is null) continue;
            changed = true;
            int center2 = (cast(WindowNode) wn.parent !is null) ? p.w : 2 * p.x + p.w;
            applyResize(wn, (center2 - wn.w) / 2, wn.y, wn.w, wn.h, live);
        }
        break;

    case AlignHow.centerVertical:
        foreach (wn; widgets)
        {
            auto p = cast(WidgetNode) wn.parent;
            if (p is null) continue;
            changed = true;
            int center2 = (cast(WindowNode) wn.parent !is null) ? p.h : 2 * p.y + p.h;
            applyResize(wn, wn.x, (center2 - wn.h) / 2, wn.w, wn.h, live);
        }
        break;
    }

    return changed;
}

unittest
{
    import fluid.window_node : WindowNode;
    import fluid.group_node : GroupNode;

    // "align left": three widgets, reference = first selected.
    auto w1 = new WidgetNode();
    w1.x = 50; w1.y = 10; w1.w = 20; w1.h = 20;
    auto w2 = new WidgetNode();
    w2.x = 10; w2.y = 40; w2.w = 20; w2.h = 20;
    auto w3 = new WidgetNode();
    w3.x = 90; w3.y = 70; w3.w = 20; w3.h = 20;

    LiveTree live;
    bool changed = alignWidgets(AlignHow.left, [w1, w2, w3], live);
    assert(changed);
    assert(w1.x == 50 && w2.x == 50 && w3.x == 50);

    // "same size": reference = first selected widget's own w/h.
    auto s1 = new WidgetNode();
    s1.x = 0; s1.y = 0; s1.w = 30; s1.h = 15;
    auto s2 = new WidgetNode();
    s2.x = 0; s2.y = 0; s2.w = 10; s2.h = 60;
    changed = alignWidgets(AlignHow.sameSize, [s1, s2], live);
    assert(changed);
    assert(s2.w == 30 && s2.h == 15);

    // "space evenly across": three widgets, gaps become identical.
    auto e1 = new WidgetNode();
    e1.x = 0; e1.y = 0; e1.w = 10; e1.h = 10;
    auto e2 = new WidgetNode();
    e2.x = 15; e2.y = 0; e2.w = 10; e2.h = 10;
    auto e3 = new WidgetNode();
    e3.x = 90; e3.y = 0; e3.w = 10; e3.h = 10;
    changed = alignWidgets(AlignHow.spaceAcross, [e1, e2, e3], live);
    assert(changed);
    assert(e1.x == 0 && e3.x == 90); // span 0..100, three widgets of width 10 => gap 35 each
    assert(e2.x == 45);

    // "center in group": parent is a plain GroupNode at (100, 50, 200, 100).
    auto group = new GroupNode();
    group.x = 100; group.y = 50; group.w = 200; group.h = 100;
    auto c1 = new WidgetNode();
    c1.x = 110; c1.y = 60; c1.w = 20; c1.h = 10;
    c1.parent = group;
    changed = alignWidgets(AlignHow.centerHorizontal, [c1], live);
    assert(changed);
    assert(c1.x == 190); // center2 = 2*100+200 = 400; (400-20)/2 = 190

    // A node with no parent (e.g. the root window) is silently skipped.
    auto orphan = new WidgetNode();
    orphan.x = 5; orphan.y = 5; orphan.w = 5; orphan.h = 5;
    changed = alignWidgets(AlignHow.centerHorizontal, [orphan], live);
    assert(!changed);
}
