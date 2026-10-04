/*
 * Ported from FLTK's `fluid::app::Snap_Action` (`fluid/app/
 * Snap_Action.h`/`.cxx`) -- the drag-time alignment/size-hint guide
 * system: while dragging or resizing a selected widget on the design
 * canvas, FLTK finds and draws snap points against the window's
 * own margins/grid, the parent group's margins/grid, and sibling
 * widgets' edges/centers, and actually snaps the drag to the closest
 * one. `fluid.canvas.ProjectCanvas`'s own drag code has real move/resize
 * and real snapping and guide-line drawing.
 *
 * See `fluid.layout_suite`'s own top comment for what's ported of the
 * companion "Layout Suite" settings system this module reads its
 * margin/grid/gap distances from, and what's deliberately narrower
 * than FLTK there.
 */
module fluid.snap_action;

import fluid.layout_suite : layoutList;
import fl;

/// Ported from `Snap_Action::get_resize_stepsize()`.
void getResizeStepsize(out int xStep, out int yStep)
{
    auto layout = layoutList.current();
    if (layout.widgetIncW > 1 && layout.widgetIncH > 1)
    {
        xStep = layout.widgetIncW;
        yStep = layout.widgetIncH;
    }
    else if (layout.groupGridX > 1 && layout.groupGridY > 1)
    {
        xStep = layout.groupGridX;
        yStep = layout.groupGridY;
    }
    else
    {
        xStep = layout.windowGridX;
        yStep = layout.windowGridY;
    }
}

/// Ported from `Snap_Action::get_move_stepsize()`.
void getMoveStepsize(out int xStep, out int yStep)
{
    auto layout = layoutList.current();
    if (layout.groupGridX > 1 && layout.groupGridY > 1)
    {
        xStep = layout.groupGridX;
        yStep = layout.groupGridY;
    }
    else if (layout.windowGridX > 1 && layout.windowGridY > 1)
    {
        xStep = layout.windowGridX;
        yStep = layout.windowGridY;
    }
    else
    {
        xStep = layout.widgetGapX;
        yStep = layout.widgetGapY;
    }
}

/// Ported from `Snap_Action::better_size()` -- fixes a raw ideal size
/// (`fluid.instantiate.idealSizeFor()`'s own call site) to the same or
/// next-bigger snap position, using the current Layout Suite preset's
/// own resize step size and minimum size.
void betterSize(ref int w, ref int h)
{
    auto layout = layoutList.current();

    int xInc, yInc;
    getResizeStepsize(xInc, yInc);
    if (xInc < 1) xInc = 1;
    if (yInc < 1) yInc = 1;

    int xMin, yMin;
    if (layout.widgetMinW > 1 && layout.widgetMinH > 1)
    {
        xMin = layout.widgetMinW;
        yMin = layout.widgetMinH;
    }
    else if (layout.groupGridX > 1 && layout.groupGridY > 1)
    {
        xMin = layout.groupGridX;
        yMin = layout.groupGridY;
    }
    else
    {
        xMin = xInc;
        yMin = yInc;
    }

    int ww = w - xMin; if (ww < 0) ww = 0;
    w = (w - ww + xInc - 1) / xInc;
    w = w * xInc;
    w = w + ww;

    int hh = h - yMin; if (hh < 0) hh = 0;
    h = (h - hh + yInc - 1) / yInc;
    h = h * yInc;
    h = h + hh;
}

unittest
{
    // Under the default (FLTK/application) preset -- widget_inc_w=10,
    // widget_inc_h=4, widget_min_w=widget_min_h=20, no grid -- every
    // one of `idealSizeFor()`'s own hardcoded "nice round number"
    // defaults should round-trip unchanged, confirmed by hand-tracing
    // FLTK's own formula.
    int w = 100, h = 100;
    betterSize(w, h);
    assert(w == 100 && h == 100);

    w = 60; h = 60;
    betterSize(w, h);
    assert(w == 60 && h == 60);

    w = 120; h = 100;
    betterSize(w, h);
    assert(w == 120 && h == 100);

    // The formula is algebraically a no-op for *any* `w >= x_min`
    // whenever `x_min` (`widget_min_w`, from `getResizeStepsize()`'s
    // own min branch) is itself an exact multiple of `x_inc`
    // (`widget_inc_w`) -- `ww = w - x_min` always makes `w - ww ==
    // x_min` exactly, so the round-up-then-multiply step reconstructs
    // the same constant every time, regardless of the original `w`.
    // Every one of FLTK's own built-in presets happens to have
    // `widget_min_w`/`widget_min_h` as an exact multiple of `widget_
    // inc_w`/`widget_inc_h` (confirmed against all 6 -- FLTK and Grid,
    // application/dialog/toolbox each), so `better_size()` is
    // genuinely a no-op for every built-in preset on any size at or
    // above the minimum -- it only does real work for a custom preset
    // whose minimum isn't cleanly divisible by its own increment.
    w = 103; h = 97;
    betterSize(w, h);
    assert(w == 103 && h == 97);
}

// ===========================================================================
// Drag-time snapping/guide-drawing -- ported from Snap_Action.cxx's own
// `Snap_Data`/`Snap_Action` base class and its `Fd_Snap_*` concrete
// subclasses (`nodes/Window_Node.cxx`'s own `newdx()` is the call site
// this feeds into -- see `fluid.canvas.ProjectCanvas.handle()`'s
// `Event.drag` case, where `checkAll()` now runs, and `drawOverlay()`,
// where `drawAll()` now runs).
//
// **Scope, narrower than FLTK's full 33-class roster**:
// window edge/margin (8), group edge/margin (8), sibling alignment (8),
// widget-ideal-size resize feedback (2), and grid snapping
// (`SnapGrid`/`SnapWindowGrid`/`SnapGroupGrid`, ported from
// `Fd_Snap_Grid`/`_Window_Grid`/`_Group_Grid`, plus the `drawGrid()`
// crosshair-cluster helper -- `Snap_Action.cxx`'s own file-static
// `draw_grid()`) are ported. `SnapWidgetIdealWidth`/`Height` are the
// *only* place
// FLTK's own `draw_width()`/`draw_height()` size-hint labels are
// ever actually invoked from (confirmed by grepping every call site
// across the real `fluid/` tree), so these two -- despite
// being the smallest, least fanned-out class in FLTK's own file --
// are what "size hints" concretely means, not a separate feature.
// **Still deliberately deferred**: tabs-margin snapping
// (`Fd_Snap_*_Tabs_Margin`, 2 classes -- needs `Fl_Tabs` detection).
// ===========================================================================

/// Ported from `fluid::app::Snap_Data`. Live `fl.widget.Widget`
/// references (`wgt`/`win`) rather than FLTK's `Widget_Node*`/
/// `Window_Node*` -- every snap check/draw here only ever needs live
/// geometry (`x()`/`y()`/`w()`/`h()`/`parent()`), never anything
/// Node-specific, so there's no reason to thread the parsed-tree layer
/// through this module at all.
struct SnapData
{
    int dx, dy;
    int bx, by, br, bt;
    int drag;
    int xDist = 4, yDist = 4;
    int dxOut, dyOut;
    Widget wgt;
    Widget win;
    int exOut, eyOut;

    /// `wgt`'s own "ideal size" -- FLTK's `Widget_Node::ideal_size()`
    /// virtual call, resolved by `fluid.canvas.ProjectCanvas` (the only
    /// place that knows `wgt`'s corresponding `WidgetNode.typeName`)
    /// via `fluid.instantiate.idealSizeFor()` before `checkAll()`/
    /// `drawAll()` run, and stashed here so `SnapWidgetIdealWidth`/
    /// `SnapWidgetIdealHeight` (below) don't need their own path back
    /// into the parsed-tree layer. Defaults match FLTK's own
    /// `int iw = 15, ih = 15;` fallback.
    int wgtIdealW = 15, wgtIdealH = 15;
}

/// Matches FLTK's own `Snap_Action::eex`/`eey` -- `static` class
/// members there (so, in effect, module-wide/shared across every
/// concrete action instance, not per-instance) holding the *winning*
/// snap coordinate from the most recent `checkAll()` pass, consulted
/// by every action's own `matches()` to decide whether *it* was the
/// one that won (and so should draw its own guide).
private int eex = 0x7fff;
private int eey = 0x7fff;

/// Ported from `fluid::app::Snap_Action`.
abstract class SnapAction
{
    int ex = 0x7fff, ey = 0x7fff, dx = 128, dy = 128;
    int type;
    int mask;

    protected void clr() { ex = dx = 0x7fff; }

    protected int checkX(ref SnapData d, int xRef, int xSnap)
    {
        int dd = xRef + d.dx - xSnap;
        int d2 = dd < 0 ? -dd : dd;
        if (d2 > d.xDist) return 1;
        dx = d.dxOut = d.dx - dd;
        ex = d.exOut = xSnap;
        if (d2 == d.xDist) return 0;
        d.xDist = d2;
        return -1;
    }

    protected int checkY(ref SnapData d, int yRef, int ySnap)
    {
        int dd = yRef + d.dy - ySnap;
        int d2 = dd < 0 ? -dd : dd;
        if (d2 > d.yDist) return 1;
        dy = d.dyOut = d.dy - dd;
        ey = d.eyOut = ySnap;
        if (d2 == d.yDist) return 0;
        d.yDist = d2;
        return -1;
    }

    protected void checkXY(ref SnapData d, int xRef, int xSnap, int yRef, int ySnap)
    {
        int ddx = xRef + d.dx - xSnap;
        int d2x = ddx < 0 ? -ddx : ddx;
        int ddy = yRef + d.dy - ySnap;
        int d2y = ddy < 0 ? -ddy : ddy;
        if (d2x <= d.xDist && d2y <= d.yDist)
        {
            dx = d.dxOut = d.dx - ddx;
            ex = d.exOut = xSnap;
            d.xDist = d2x;
            dy = d.dyOut = d.dy - ddy;
            ey = d.eyOut = ySnap;
            d.yDist = d2y;
        }
    }

    abstract void check(ref SnapData d);
    void draw(ref SnapData d) {}

    bool matches(ref SnapData d)
    {
        switch (type)
        {
        case 1: return (d.drag & mask) != 0 && eex == ex && d.dx == dx;
        case 2: return (d.drag & mask) != 0 && eey == ey && d.dy == dy;
        case 3: return (d.drag & mask) != 0
            && eex == ex && d.dx == dx && eey == ey && d.dy == dy;
        default: return false;
        }
    }
}

// ---- drag-mask bits -- matches fluid.canvas's own DragFlag values
// exactly (FD_DRAG/FD_LEFT/FD_RIGHT/FD_TOP/FD_BOTTOM in FLTK); kept
// as a second, independent set of constants rather than importing
// canvas.d's own `private` ones, matching how FLTK's own `Snap_
// Action.h`/`Window_Node.h` independently both `#define` the same
// `FD_*` bits rather than one including the other for them.
private enum fdMove = 1;
private enum fdLeft = 2;
private enum fdRight = 4;
private enum fdTop = 8;
private enum fdBottom = 16;

private bool inWindow(SnapData d) { return d.wgt !is null && d.wgt.parent() is d.win; }
private bool inGroup(SnapData d) { return d.wgt !is null && d.wgt.parent() !is null && d.wgt.parent() !is d.win; }
private FlGroup parentOf(SnapData d) { return cast(FlGroup) d.wgt.parent(); }

// ---- drawing helpers -- ported from Snap_Action.cxx's own file-static
// draw_h_arrow()/draw_v_arrow()/draw_left_brace()/draw_right_brace()/
// draw_top_brace()/draw_bottom_brace()/draw_width()/draw_height().
// ----------------------------------------------------------------------

private void drawVArrow(int x, int y1, int y2)
{
    int d = (y1 > y2) ? -1 : 1;
    fl_yxline(x, y1, y2);
    fl_xyline(x - 4, y2, x + 4);
    fl_line(x - 2, y2 - d * 5, x, y2 - d);
    fl_line(x + 2, y2 - d * 5, x, y2 - d);
}

private void drawHArrow(int x1, int y, int x2)
{
    int d = (x1 > x2) ? -1 : 1;
    fl_xyline(x1, y, x2);
    fl_yxline(x2, y - 4, y + 4);
    fl_line(x2 - d * 5, y - 2, x2 - d, y);
    fl_line(x2 - d * 5, y + 2, x2 - d, y);
}

private void drawTopBrace(Widget w)
{
    int x = w.asWindow() !is null ? 0 : w.x();
    int y = w.asWindow() !is null ? 0 : w.y();
    fl_yxline(x, y - 2, y + 6);
    fl_yxline(x + w.w() - 1, y - 2, y + 6);
    fl_xyline(x - 2, y, x + w.w() + 1);
}

private void drawLeftBrace(Widget w)
{
    int x = w.asWindow() !is null ? 0 : w.x();
    int y = w.asWindow() !is null ? 0 : w.y();
    fl_xyline(x - 2, y, x + 6);
    fl_xyline(x - 2, y + w.h() - 1, x + 6);
    fl_yxline(x, y - 2, y + w.h() + 1);
}

private void drawRightBrace(Widget w)
{
    int x = w.asWindow() !is null ? w.w() - 1 : w.x() + w.w() - 1;
    int y = w.asWindow() !is null ? 0 : w.y();
    fl_xyline(x - 6, y, x + 2);
    fl_xyline(x - 6, y + w.h() - 1, x + 2);
    fl_yxline(x, y - 2, y + w.h() + 1);
}

private void drawBottomBrace(Widget w)
{
    int x = w.asWindow() !is null ? 0 : w.x();
    int y = w.asWindow() !is null ? w.h() - 1 : w.y() + w.h() - 1;
    fl_yxline(x, y - 6, y + 2);
    fl_yxline(x + w.w() - 1, y - 6, y + 2);
    fl_xyline(x - 2, y, x + w.w() + 1);
}

/// Ported from `draw_height()` -- the vertical size-hint label (the
/// actual, in-pixels current height, drawn alongside a top/bottom
/// resize arrow) a user comparison against real Fluid specifically
/// asked for ("show size hints"). `a` mirrors FLTK's own `Fl_Align`
/// parameter -- only `alignLeft` is ever tested against (matches
/// FLTK: any other value takes the same "put it on the right"
/// branch both places it's used).
package(fluid) void drawHeightHint(int x, int y, int b, Align a)
{
    import std.format : format;

    int h = b - y;
    string buf = format("%d", h);
    fl_font(helvetica, 9);
    int lw, lh;
    fl_measure(buf, lw, lh);
    int lx;

    b--;
    if (h < 30)
    {
        lx = (a == alignLeft) ? x - lw - 2 : x + 2;
        fl_yxline(x, y, b);
    }
    else
    {
        lx = (a == alignLeft) ? x - lw + 2 : x - lw / 2;
        fl_yxline(x, y, y + (h - 11) / 2);
        fl_yxline(x, y + (h + 11) / 2, b);
    }

    fl_draw(buf, lx, y + (h + 7) / 2);

    fl_line(x - 2, y + 5, x, y + 1, x + 2, y + 5);
    fl_line(x - 2, b - 5, x, b - 1, x + 2, b - 5);

    fl_xyline(x - 4, y, x + 4);
    fl_xyline(x - 4, b, x + 4);
}

/// Ported from `draw_width()` -- the horizontal counterpart to
/// `drawHeightHint()` above.
package(fluid) void drawWidthHint(int x, int y, int r, Align a)
{
    import std.format : format;

    int w = r - x;
    string buf = format("%d", w);
    fl_font(helvetica, 9);
    int lw, lh;
    fl_measure(buf, lw, lh);
    int ly = y + 4;

    r--;

    if (lw > w - 20)
    {
        ly += (a == alignTop) ? -10 : 10;
        fl_xyline(x, y, r);
    }
    else
    {
        fl_xyline(x, y, x + (w - lw - 2) / 2);
        fl_xyline(x + (w + lw + 2) / 2, y, r);
    }

    fl_draw(buf, x + (w - lw) / 2, ly - 2);

    fl_line(x + 5, y - 2, x + 1, y, x + 5, y + 2);
    fl_line(r - 5, y - 2, r - 1, y, r - 5, y + 2);

    fl_yxline(x, y - 4, y + 4);
    fl_yxline(r, y - 4, y + 4);
}

// ---- window edge/margin snapping -------------------------------------

private class SnapLeft : SnapAction { this() { type = 1; mask = fdLeft | fdMove; } }
private class SnapRight : SnapAction { this() { type = 1; mask = fdRight | fdMove; } }
private class SnapTop : SnapAction { this() { type = 2; mask = fdTop | fdMove; } }
private class SnapBottom : SnapAction { this() { type = 2; mask = fdBottom | fdMove; } }

private final class SnapLeftWindowEdge : SnapLeft
{
    override void check(ref SnapData d) { clr(); checkX(d, d.bx, 0); }
    override void draw(ref SnapData d) { drawLeftBrace(d.win); }
}

private final class SnapRightWindowEdge : SnapRight
{
    override void check(ref SnapData d) { clr(); checkX(d, d.br, d.win.w()); }
    override void draw(ref SnapData d) { drawRightBrace(d.win); }
}

private final class SnapTopWindowEdge : SnapTop
{
    override void check(ref SnapData d) { clr(); checkY(d, d.by, 0); }
    override void draw(ref SnapData d) { drawTopBrace(d.win); }
}

private final class SnapBottomWindowEdge : SnapBottom
{
    override void check(ref SnapData d) { clr(); checkY(d, d.bt, d.win.h()); }
    override void draw(ref SnapData d) { drawBottomBrace(d.win); }
}

private final class SnapLeftWindowMargin : SnapLeft
{
    override void check(ref SnapData d)
    {
        clr();
        if (inWindow(d)) checkX(d, d.bx, layoutList.current().leftWindowMargin);
    }
    override void draw(ref SnapData d) { drawHArrow(d.bx, (d.by + d.bt) / 2, 0); }
}

private final class SnapRightWindowMargin : SnapRight
{
    override void check(ref SnapData d)
    {
        clr();
        if (inWindow(d)) checkX(d, d.br, d.win.w() - layoutList.current().rightWindowMargin);
    }
    override void draw(ref SnapData d) { drawHArrow(d.br, (d.by + d.bt) / 2, d.win.w() - 1); }
}

private final class SnapTopWindowMargin : SnapTop
{
    override void check(ref SnapData d)
    {
        clr();
        if (inWindow(d)) checkY(d, d.by, layoutList.current().topWindowMargin);
    }
    override void draw(ref SnapData d) { drawVArrow((d.bx + d.br) / 2, d.by, 0); }
}

private final class SnapBottomWindowMargin : SnapBottom
{
    override void check(ref SnapData d)
    {
        clr();
        if (inWindow(d)) checkY(d, d.bt, d.win.h() - layoutList.current().bottomWindowMargin);
    }
    override void draw(ref SnapData d) { drawVArrow((d.bx + d.br) / 2, d.bt, d.win.h() - 1); }
}

// ---- group edge/margin snapping ---------------------------------------

private final class SnapLeftGroupEdge : SnapLeft
{
    override void check(ref SnapData d) { clr(); if (inGroup(d)) checkX(d, d.bx, parentOf(d).x()); }
    override void draw(ref SnapData d) { drawLeftBrace(parentOf(d)); }
}

private final class SnapRightGroupEdge : SnapRight
{
    override void check(ref SnapData d) { clr(); if (inGroup(d)) checkX(d, d.br, parentOf(d).x() + parentOf(d).w()); }
    override void draw(ref SnapData d) { drawRightBrace(parentOf(d)); }
}

private final class SnapTopGroupEdge : SnapTop
{
    override void check(ref SnapData d) { clr(); if (inGroup(d)) checkY(d, d.by, parentOf(d).y()); }
    override void draw(ref SnapData d) { drawTopBrace(parentOf(d)); }
}

private final class SnapBottomGroupEdge : SnapBottom
{
    override void check(ref SnapData d) { clr(); if (inGroup(d)) checkY(d, d.bt, parentOf(d).y() + parentOf(d).h()); }
    override void draw(ref SnapData d) { drawBottomBrace(parentOf(d)); }
}

private final class SnapLeftGroupMargin : SnapLeft
{
    override void check(ref SnapData d)
    {
        clr();
        if (inGroup(d)) checkX(d, d.bx, parentOf(d).x() + layoutList.current().leftGroupMargin);
    }
    override void draw(ref SnapData d)
    {
        drawLeftBrace(parentOf(d));
        drawHArrow(d.bx, (d.by + d.bt) / 2, parentOf(d).x());
    }
}

private final class SnapRightGroupMargin : SnapRight
{
    override void check(ref SnapData d)
    {
        clr();
        if (inGroup(d)) checkX(d, d.br, parentOf(d).x() + parentOf(d).w() - layoutList.current().rightGroupMargin);
    }
    override void draw(ref SnapData d)
    {
        drawRightBrace(parentOf(d));
        drawHArrow(d.br, (d.by + d.bt) / 2, parentOf(d).x() + parentOf(d).w() - 1);
    }
}

private final class SnapTopGroupMargin : SnapTop
{
    override void check(ref SnapData d)
    {
        clr();
        if (inGroup(d)) checkY(d, d.by, parentOf(d).y() + layoutList.current().topGroupMargin);
    }
    override void draw(ref SnapData d)
    {
        drawTopBrace(parentOf(d));
        drawVArrow((d.bx + d.br) / 2, d.by, parentOf(d).y());
    }
}

private final class SnapBottomGroupMargin : SnapBottom
{
    override void check(ref SnapData d)
    {
        clr();
        if (inGroup(d)) checkY(d, d.bt, parentOf(d).y() + parentOf(d).h() - layoutList.current().bottomGroupMargin);
    }
    override void draw(ref SnapData d)
    {
        drawBottomBrace(parentOf(d));
        drawVArrow((d.bx + d.br) / 2, d.bt, parentOf(d).y() + parentOf(d).h() - 1);
    }
}

// ---- grid snapping --------------------------------------------------------

/// Ported from `Fd_Snap_Grid` -- base class for window/group grid
/// snapping (`SnapWindowGrid`/`SnapGroupGrid` below).
/// `type = 3` (both X and Y checked via `checkXY()`, matching `Fd_Snap_
/// Grid`'s own `type = 3`), but `matches()` overrides the generic
/// type-3 rule (both axes must match the winning snap) with a relaxed,
/// single-axis check when only *one* axis is actually being dragged
/// (`d.drag == fdLeft`/`fdTop` alone -- resizing just one edge, not
/// moving the whole widget) -- ported letter for letter from `Fd_Snap_
/// Grid::matches()`, not the inherited default.
private abstract class SnapGrid : SnapAction
{
    protected int nearestX, nearestY;

    this() { type = 3; mask = fdLeft | fdTop | fdMove; }

    protected void checkGrid(ref SnapData d, int left, int gridX, int right, int top, int gridY, int bottom)
    {
        if (gridX <= 1 || gridY <= 1) return;
        int suggestedX = d.bx + d.dx;
        nearestX = nearestGrid(suggestedX, left, gridX, right);
        int suggestedY = d.by + d.dy;
        nearestY = nearestGrid(suggestedY, top, gridY, bottom);
        if (d.drag == fdLeft)
            checkX(d, d.bx, nearestX);
        else if (d.drag == fdTop)
            checkY(d, d.by, nearestY);
        else
            checkXY(d, d.bx, nearestX, d.by, nearestY);
    }

    override bool matches(ref SnapData d)
    {
        if (d.drag == fdLeft) return eex == ex;
        if (d.drag == fdTop) return eey == ey && d.dx == dx;
        return (d.drag & mask) != 0 && eex == ex && d.dx == dx && eey == ey && d.dy == dy;
    }
}

/// Ported from `Fd_Snap_Window_Grid`.
private final class SnapWindowGrid : SnapGrid
{
    override void check(ref SnapData d)
    {
        auto layout = layoutList.current();
        clr();
        if (inWindow(d))
            checkGrid(d, layout.leftWindowMargin, layout.windowGridX, d.win.w() - layout.rightWindowMargin,
                layout.topWindowMargin, layout.windowGridY, d.win.h() - layout.bottomWindowMargin);
    }
    override void draw(ref SnapData d)
    {
        auto layout = layoutList.current();
        drawGrid(nearestX, nearestY, layout.windowGridX, layout.windowGridY);
    }
}

/// Ported from `Fd_Snap_Group_Grid`.
private final class SnapGroupGrid : SnapGrid
{
    override void check(ref SnapData d)
    {
        if (inGroup(d))
        {
            auto layout = layoutList.current();
            clr();
            auto g = parentOf(d);
            checkGrid(d, g.x() + layout.leftGroupMargin, layout.groupGridX, g.x() + g.w() - layout.rightGroupMargin,
                g.y() + layout.topGroupMargin, layout.groupGridY, g.y() + g.h() - layout.bottomGroupMargin);
        }
    }
    override void draw(ref SnapData d)
    {
        auto layout = layoutList.current();
        drawGrid(nearestX, nearestY, layout.groupGridX, layout.groupGridY);
    }
}

// ---- sibling snapping ---------------------------------------------------

/// Ported from `Fd_Snap_Sibling` -- scans every *other* child of the
/// dragged widget's own live parent group, keeping whichever one
/// `siblingCheck()` reports as the closest real match (`sret < 1` --
/// matches FLTK's own `check_x_`/`check_y_` return convention:
/// `1` means "out of range", `0`/`-1` both mean "a real candidate").
private abstract class SnapSibling : SnapAction
{
    protected Widget bestMatch;

    override void check(ref SnapData d)
    {
        clr();
        bestMatch = null;
        if (d.wgt is null) return;
        auto g = cast(FlGroup) d.wgt.parent();
        if (g is null) return;
        int dsibMin = 1024;
        foreach (i; 0 .. g.children())
        {
            auto c = g.child(i);
            if (c is d.wgt) continue;
            int sret = siblingCheck(d, c);
            if (sret < 1)
            {
                int dsib = (type == 1)
                    ? absInt((d.by + d.bt) / 2 + d.dy - (c.y() + c.h() / 2))
                    : absInt((d.bx + d.br) / 2 + d.dx - (c.x() + c.w() / 2));
                if (sret == -1 || dsib < dsibMin)
                {
                    dsibMin = dsib;
                    bestMatch = c;
                }
            }
        }
    }

    protected abstract int siblingCheck(ref SnapData d, Widget s);
}

private int absInt(int v) { return v < 0 ? -v : v; }

private final class SnapSiblingsLeftSame : SnapSibling
{
    this() { type = 1; mask = fdLeft | fdMove; }
    override protected int siblingCheck(ref SnapData d, Widget s) { return checkX(d, d.bx, s.x()); }
    override void draw(ref SnapData d) { if (bestMatch !is null) drawLeftBrace(bestMatch); }
}

private final class SnapSiblingsLeft : SnapSibling
{
    this() { type = 1; mask = fdLeft | fdMove; }
    override protected int siblingCheck(ref SnapData d, Widget s)
    {
        auto a = checkX(d, d.bx, s.x() + s.w());
        auto b = checkX(d, d.bx, s.x() + s.w() + layoutList.current().widgetGapX);
        return a < b ? a : b;
    }
    override void draw(ref SnapData d) { if (bestMatch !is null) drawRightBrace(bestMatch); }
}

private final class SnapSiblingsRightSame : SnapSibling
{
    this() { type = 1; mask = fdRight | fdMove; }
    override protected int siblingCheck(ref SnapData d, Widget s) { return checkX(d, d.br, s.x() + s.w()); }
    override void draw(ref SnapData d) { if (bestMatch !is null) drawRightBrace(bestMatch); }
}

private final class SnapSiblingsRight : SnapSibling
{
    this() { type = 1; mask = fdRight | fdMove; }
    override protected int siblingCheck(ref SnapData d, Widget s)
    {
        auto a = checkX(d, d.br, s.x());
        auto b = checkX(d, d.br, s.x() - layoutList.current().widgetGapX);
        return a < b ? a : b;
    }
    override void draw(ref SnapData d) { if (bestMatch !is null) drawLeftBrace(bestMatch); }
}

private final class SnapSiblingsTopSame : SnapSibling
{
    this() { type = 2; mask = fdTop | fdMove; }
    override protected int siblingCheck(ref SnapData d, Widget s) { return checkY(d, d.by, s.y()); }
    override void draw(ref SnapData d) { if (bestMatch !is null) drawTopBrace(bestMatch); }
}

private final class SnapSiblingsTop : SnapSibling
{
    this() { type = 2; mask = fdTop | fdMove; }
    override protected int siblingCheck(ref SnapData d, Widget s)
    {
        auto a = checkY(d, d.by, s.y() + s.h());
        auto b = checkY(d, d.by, s.y() + s.h() + layoutList.current().widgetGapY);
        return a < b ? a : b;
    }
    override void draw(ref SnapData d) { if (bestMatch !is null) drawBottomBrace(bestMatch); }
}

private final class SnapSiblingsBottomSame : SnapSibling
{
    this() { type = 2; mask = fdBottom | fdMove; }
    override protected int siblingCheck(ref SnapData d, Widget s) { return checkY(d, d.bt, s.y() + s.h()); }
    override void draw(ref SnapData d) { if (bestMatch !is null) drawBottomBrace(bestMatch); }
}

private final class SnapSiblingsBottom : SnapSibling
{
    this() { type = 2; mask = fdBottom | fdMove; }
    override protected int siblingCheck(ref SnapData d, Widget s)
    {
        auto a = checkY(d, d.bt, s.y());
        auto b = checkY(d, d.bt, s.y() - layoutList.current().widgetGapY);
        return a < b ? a : b;
    }
    override void draw(ref SnapData d) { if (bestMatch !is null) drawTopBrace(bestMatch); }
}

// ---- widget-ideal-size snapping -----------------------------------------

/// Ported from `Snap_Action.cxx`'s own file-static `nearest()` -- rounds
/// `x` to the nearest multiple of `grid` relative to `left`, clamped
/// into `[left, right]`.
private int nearestGrid(int x, int left, int grid, int right = 0x7fff)
{
    int gridX = ((x - left + grid / 2) / grid) * grid + left;
    if (gridX < left + grid / 2) return left;
    if (gridX > right - grid / 2) return right;
    return gridX;
}

/// Ported from `Snap_Action.cxx`'s own file-static `draw_grid()` --
/// draws a small diamond-shaped cluster of tiny crosshair marks around
/// the nearest grid intersection `(x, y)`, spaced `dx`/`dy` apart
/// (`SnapWindowGrid`/`SnapGroupGrid`'s own `draw()`, above the sibling
/// section). `n = 2` and the `abs(i)+abs(j) < 4` diamond cutoff are
/// FLTK's own literal constants, not derived from anything.
private void drawGrid(int x, int y, int dx, int dy)
{
    enum dx2 = 1, dy2 = 1;
    enum n = 2;
    for (int i = -n; i <= n; i++)
    {
        for (int j = -n; j <= n; j++)
        {
            if (absInt(i) + absInt(j) < 4)
            {
                int xx = x + i * dx, yy = y + j * dy;
                fl_xyline(xx - dx2, yy, xx + dx2);
                fl_yxline(xx, yy - dy2, yy + dy2);
            }
        }
    }
}

/// Ported from `Fd_Snap_Widget_Ideal_Width` -- resize-to-ideal-width
/// feedback (the "show size hints" a user comparison against real
/// Fluid specifically asked for), snapping a horizontal resize to
/// either the dragged widget's own `idealSizeFor()` width or the
/// nearest `widget_min_w`/`widget_inc_w` grid step, whichever the
/// drag is closer to.
///
/// **Deliberate deviation from FLTK**: FLTK's own
/// `check()` branches on an *exact* equality, `if (d.drag ==
/// FD_RIGHT)` -- verified against `Fd_Snap_Widget_Ideal_Width::check()`
/// in `Snap_Action.cxx`, letter for letter. Tested this way, a corner-drag (which FLTK's own
/// `Window_Node::handle()` sets as `FD_RIGHT|FD_BOTTOM` together, same
/// shape as this port's own
/// `dragRight|dragBottom`) never equals `FD_RIGHT` alone, so it always
/// falls into the `else` branch written for a *left*-edge drag --
/// computing a target that moves the *wrong direction* as the drag
/// continues, matching only within the first few pixels of the
/// drag. Real Fluid shows the hint
/// continuously and reliably on a corner-drag too, including standing
/// still mid-drag, so this port tests the *bit*, not exact equality --
/// `fdLeft`/`fdRight` can never both be set at once (a resize grab is
/// only ever from one horizontal edge), so `(d.drag & fdRight) != 0`
/// is unambiguous and correctly recognizes "the right edge is among
/// the edges being dragged" whether alone or as part of a corner,
/// with no change in behavior for a plain single-edge drag.
private final class SnapWidgetIdealWidth : SnapAction
{
    this() { type = 1; mask = fdLeft | fdRight; }

    override void check(ref SnapData d)
    {
        clr();
        if (d.wgt is null) return;
        auto layout = layoutList.current();
        int iw = d.wgtIdealW;
        if ((d.drag & fdRight) != 0)
        {
            checkX(d, d.br, d.bx + iw);
            iw = layout.widgetMinW;
            if (iw > 0) iw = nearestGrid(d.br - d.bx + d.dx, layout.widgetMinW, layout.widgetIncW);
            checkX(d, d.br, d.bx + iw);
        }
        else
        {
            checkX(d, d.bx, d.br - iw);
            iw = layout.widgetMinW;
            if (iw > 0) iw = nearestGrid(d.br - d.bx - d.dx, layout.widgetMinW, layout.widgetIncW);
            checkX(d, d.bx, d.br - iw);
        }
    }

    override void draw(ref SnapData d) { drawWidthHint(d.bx, d.bt + 7, d.br, cast(Align) 0); }
}

/// Ported from `Fd_Snap_Widget_Ideal_Height` -- the vertical
/// counterpart to `SnapWidgetIdealWidth` above, including the same
/// bitwise-test deviation from FLTK's exact-equality check --
/// see that class's own doc comment for the full reasoning.
private final class SnapWidgetIdealHeight : SnapAction
{
    this() { type = 2; mask = fdTop | fdBottom; }

    override void check(ref SnapData d)
    {
        clr();
        if (d.wgt is null) return;
        auto layout = layoutList.current();
        int ih = d.wgtIdealH;
        if ((d.drag & fdBottom) != 0)
        {
            checkY(d, d.bt, d.by + ih);
            ih = layout.widgetMinH;
            if (ih > 0) ih = nearestGrid(d.bt - d.by + d.dy, layout.widgetMinH, layout.widgetIncH);
            checkY(d, d.bt, d.by + ih);
        }
        else
        {
            checkY(d, d.by, d.bt - ih);
            ih = layout.widgetMinH;
            if (ih > 0) ih = nearestGrid(d.bt - d.by - d.dy, layout.widgetMinH, layout.widgetIncH);
            checkY(d, d.by, d.bt - ih);
        }
    }

    override void draw(ref SnapData d) { drawHeightHint(d.br + 7, d.by, d.bt, cast(Align) 0); }
}

private SnapAction[] snapActions;

static this()
{
    snapActions = [
        cast(SnapAction) new SnapLeftWindowEdge(),
        new SnapRightWindowEdge(),
        new SnapTopWindowEdge(),
        new SnapBottomWindowEdge(),
        new SnapLeftWindowMargin(),
        new SnapRightWindowMargin(),
        new SnapTopWindowMargin(),
        new SnapBottomWindowMargin(),
        new SnapLeftGroupEdge(),
        new SnapRightGroupEdge(),
        new SnapTopGroupEdge(),
        new SnapBottomGroupEdge(),
        new SnapLeftGroupMargin(),
        new SnapRightGroupMargin(),
        new SnapTopGroupMargin(),
        new SnapBottomGroupMargin(),
        new SnapWindowGrid(),
        new SnapGroupGrid(),
        new SnapSiblingsLeftSame(),
        new SnapSiblingsLeft(),
        new SnapSiblingsRightSame(),
        new SnapSiblingsRight(),
        new SnapSiblingsTopSame(),
        new SnapSiblingsTop(),
        new SnapSiblingsBottomSame(),
        new SnapSiblingsBottom(),
        new SnapWidgetIdealWidth(),
        new SnapWidgetIdealHeight(),
    ];
}

/// Ported from `Snap_Action::check_all()` -- runs every registered
/// snap action whose own `mask` overlaps the current drag, then
/// records the overall winning coordinate (`eex`/`eey`) for `drawAll()`
/// (via each action's own `matches()`) to consult afterward.
package(fluid) void checkAll(ref SnapData data)
{
    foreach (a; snapActions)
        if ((a.mask & data.drag) != 0)
            a.check(data);
    eex = data.exOut;
    eey = data.eyOut;
}

/// Ported from `Snap_Action::draw_all()`.
package(fluid) void drawAll(ref SnapData data)
{
    foreach (a; snapActions)
        if (a.matches(data))
            a.draw(data);
}
