/*
 * The interactive editor's live design surface -- one `ProjectCanvas`
 * per open project window. Ported in spirit from FLTK's real
 * Fluid: an open project window is literally the actual `Fl_Window`
 * being designed, shown live, with `handle()` overridden to intercept
 * mouse events for edit-mode interaction instead of normal widget
 * dispatch, and an overlay plane painting selection boxes on top --
 * see `fl.overlay_window.OverlayWindow`, this port's own real port of
 * exactly that mechanism (`Fl_Overlay_Window`), used here for the
 * first time by anything other than its own unittest.
 *
 * Real mouse-driven move/
 * resize is ported in spirit from `Window_Node::handle()`'s own
 * `FL_PUSH`/`FL_DRAG`/`FL_RELEASE` state machine and `newposition()`'s
 * per-widget edge-clamping math -- see `beginDrag()`/`applyDrag()`
 * below for the mechanism. The `Snap_Action` rule engine itself is
 * real -- `fluid.snap_action`'s `checkAll()`/
 * `drawAll()`, ported from `Window_Node::newdx()`'s own call sites
 * (window/group edge+margin snapping, sibling alignment, resize-to-ideal-
 * size feedback, and window/group grid snapping too;
 * Tabs-margin snapping is the one piece still deferred, see that
 * module's own top comment for the exact scope line) -- wired into
 * `Event.drag` (snaps `ddx`/`ddy` before
 * `applyDrag()` runs) and `drawOverlay()` (draws the winning guide).
 *
 * This module covers every FLTK file that
 * decides click/double-click/right-click/drag semantics (the only 6 in
 * all of Fluid's own source: `Window_Node.cxx` here, plus 5 small
 * header-only widget classes elsewhere in this port). Real:
 * right-click context menu (`Event.push`'s `eventButton() >= 3` case,
 * pops up `gui_main.d`'s own real `&New` menu via `onContextMenu`),
 * rubber-band box-select (`FD_BOX`, `dragBox`/`finishBoxSelect()`),
 * double-click-to-open (`Event.release`'s `eventClicks()` check,
 * `onOpenRequested`), keyboard arrow-key nudge and Tab/Shift+Tab
 * widget-cycling (`Event.keyDown`), Escape-hides-the-window, and
 * external image-file drag-and-drop onto a widget (`onImageDropped`,
 * distinguished from a widget-bin type-name drop via
 * `imageDropPath()`). See each feature's own doc comment (`handle()`'s
 * `Event.push`/`drag`/`release`/`keyDown`/`paste` cases,
 * `finishBoxSelect()`, `flattenWidgets()`, `imageDropPath()`) for the
 * individual porting notes, including the one deliberate behavioral
 * fork from FLTK (Ctrl-click stays this port's own toggle-selection
 * modifier, not also "open" the way FLTK's Ctrl-click-release is --
 * see `Event.release`'s own comment) and the one narrower-than-FLTK
 * gap (image-file drops aren't URI-decoded, see `imageDropPath()`).
 *
 * Also simplified from FLTK: a *direct hit* on an ordinary widget
 * still selects immediately on push (a pre-existing, tested behavior,
 * see the "Multi-selection" note below), not FLTK's own two-phase
 * model (select on *release*, driven by a per-node-type `click_test()`
 * virtual). So a plain click on an unselected widget here both selects
 * *and* arms a move drag in the same press-drag gesture, rather than
 * requiring two separate clicks the way FLTK's timing does. An
 * *empty-space* press is one exception to "immediate on push": it
 * defers to FLTK's own two-phase timing after all, since that's
 * exactly what box-select needs (see `finishBoxSelect()`'s own doc
 * comment). `click_test()` itself *is* ported now, for the two node
 * kinds FLTK overrides it on: a `Tabs` hit on its own tab-label
 * strip forwards to the live `Fl_Tabs`' own click-to-switch-page
 * handling (`Tabs_Node::click_test()`), and an unselected menu widget
 * (`Choice`/`Menu_Button`/`Menu_Bar`/`Input_Choice`) pops its own real
 * dropdown so a specific item can be picked for editing
 * (`Menu_Base_Node::click_test()`/`Input_Choice_Node::click_test()`,
 * see `Event.push`'s own two matching cases below) -- both are real
 * exceptions to the "immediate select-on-push" simplification above,
 * not covered by it.
 *
 * **Multi-selection**:
 * Ctrl-click toggles a node's membership in the selection instead of
 * replacing it; Shift-click range-selects from the last plain-clicked
 * widget through the new target (`selectRange()`, using the pre-order
 * `flattenWidgets()` walk, shared with Tab-cycling, as its
 * traversal order). Deliberately scoped to
 * *selection* only:
 * the widget panel (`panels/widget_panel.fl`) still shows/edits only the
 * `primarySelection()` (the most recently added member) -- "apply an
 * edit to every selected node at once" is FLTK's own generic
 * `propagate_load()` dispatch's job (phase 1, already done for single-
 * selection) and is deliberately left for whenever that dispatch grows
 * multi-target support, not bolted on here as a special case.
 */
module fluid.canvas;

import fl;

import fluid.node : Node;
import fluid.window_node : WindowNode;
import fluid.widget_node : WidgetNode;
import fluid.instantiate : instantiate, LiveTree, idealSizeFor, menuItemNodeMap;
import fluid.snap_action : SnapData, checkAll, drawAll, getMoveStepsize, getResizeStepsize;

/// Which edge(s) (or plain move) a drag is currently manipulating --
/// mirrors FLTK's `FD_DRAG`/`FD_LEFT`/`FD_RIGHT`/`FD_TOP`/
/// `FD_BOTTOM` bitmask exactly (`FD_BOX` isn't ported, see this
/// module's own top comment). An open, combinable bitmask, not a
/// closed tag set -- an `alias`+manifest-constants pair, matching
/// CONVENTIONS.md's own porting convention for exactly this shape (a real D
/// `enum` would need an explicit `cast()` back on every `|=`).
private alias DragFlag = int;
private enum DragFlag dragNone = 0;
private enum DragFlag dragMove = 1;
private enum DragFlag dragLeft = 2;
private enum DragFlag dragRight = 4;
private enum DragFlag dragTop = 8;
private enum DragFlag dragBottom = 16;
/// Rubber-band box-select, FLTK's `FD_BOX` -- see `finishBoxSelect()`.
/// A
/// distinct value from every move/resize bit above, never OR'd with
/// them -- `dragMode_ == dragBox` is checked with plain `==`, not `&`,
/// everywhere this is read.
private enum DragFlag dragBox = 32;

/// One selected widget's geometry as of the start of the current drag
/// -- `applyDrag()` computes every new position relative to this fixed
/// origin (not incrementally frame-to-frame), matching FLTK's own
/// `newposition()` reading straight off the live `Fl_Widget`'s
/// still-original geometry each call.
private struct DragOrigin
{
    WidgetNode node;
    int x, y, w, h;
}

final class ProjectCanvas : OverlayWindow
{
    private Node root_;
    private LiveTree live_;
    private Node[] selected_;

    /// This is the mechanism backing `WidgetPanelDialog`'s "Hide
    /// Overlays" button (`onToggleOverlays`, wired in `gui_main.d`),
    /// matching FLTK's own
    /// `overlays_invisible` (`nodes/Window_Node.cxx`) -- a process-wide
    /// static there (one "Hide Overlays" button/menu toggle for every
    /// open project window), here just per-canvas since Phase 1 only
    /// ever has one project open at a time anyway. **FLTK still
    /// draws overlays while a drag is actually in progress even when
    /// `overlays_invisible` is set** (`if (overlays_invisible && !drag)
    /// return;`) -- hiding the persistent selection outline, not live
    /// drag feedback -- replicated in `drawOverlay()`'s own check
    /// below via `dragMode_`.
    bool overlaysHidden;

    /// Matches FLTK's own `Fluid.show_guides` (`Window_Node::
    /// newdx()`'s own gate around the whole `Snap_Action::check_all()`
    /// call) -- a *separate* toggle from `overlaysHidden` above:
    /// `overlays_invisible` hides the persistent selection outline,
    /// `show_guides` controls whether dragging snaps/draws alignment
    /// guides at all. Defaults to `true`, matching FLTK's own
    /// default (a fresh install has never written a `Fluid.show_guides`
    /// preference, and FLTK's own `Fl_Preferences::get()` default
    /// for it is `1`).
    bool showGuides = true;

    /// Matches FLTK's own `Fluid.show_ghosted_outline` (`Fluid.h`'s
    /// own `int show_ghosted_outline { 1 };`) -- see `draw()`'s own doc
    /// comment for the mechanism this drives.
    bool showGhostedOutline = true;

    /// Matches FLTK's own `Fluid.show_restricted` (`Fluid.h`'s own
    /// `int show_restricted { 1 };`) -- see `drawOverlay()`'s own doc
    /// comment for the mechanism this drives.
    bool showRestricted = true;

    /// Matches FLTK's own `Fluid.proj.tree.allow_layout` (`&Layout/
    /// Synchronized Resize`, `Tree.h`'s own `int allow_layout = 0;`) --
    /// gates whether interactively resizing a `Group`/`Window`-family
    /// widget on this canvas (via `applyDrag()`'s resize handles, or
    /// dragging this canvas's own OS window border) also resizes/
    /// repositions its *unselected* children to match real runtime
    /// behavior (`true`), or leaves them exactly where they are and
    /// only changes the container's own box (`false`, the default,
    /// matching FLTK's own `0` default) -- ordinary WYSIWYG
    /// editing, where each child's position is set independently of
    /// however its parent's own box happens to be sized at the moment.
    /// See `applyDrag()`'s and `resize()`'s own doc comments for where
    /// this is actually consulted, and their notes on the two real,
    /// disclosed simplifications versus FLTK's own considerably
    /// more involved `moveallchildren()` (`Window_Node.cxx`): a plain
    /// MOVE (no size change) always drags children along regardless of
    /// this flag here too, matching FLTK's own unconditional
    /// per-descendant translation loop, just achieved via this port's
    /// existing `FlGroup.resize()` cascade instead of a separate manual
    /// walk; and `Flex`/`Grid` children always self-layout on resize
    /// regardless of this flag, matching FLTK's own forced
    /// `allow_layout++`/`--` bracket around exactly those two node
    /// kinds, achieved here for free since `fl.flex.Flex`/`fl.grid.Grid`
    /// already override `resize()` themselves rather than relying on
    /// the generic `FlGroup.resize()` cascade this flag gates.
    bool allowLayout = false;

    /// The most recent `SnapData` a `checkAll()` call produced during
    /// `Event.drag` -- `drawOverlay()` re-runs `drawAll()` against this
    /// same snapshot (matching FLTK's own class-static `Snap_
    /// Action::eex`/`eey`-plus-per-instance-`ex`/`ey` state, read back
    /// by a *separate* `draw_overlay()` call rather than passed
    /// directly, since drag-handling and drawing are two different
    /// entry points here too). Reset to `SnapData.init` at the top of
    /// every `Event.drag` (see that case's own comment) so a stale
    /// snap from a *previous* drag gesture never lingers into
    /// `drawOverlay()` once the current one no longer has any
    /// selection/mode to match against.
    private SnapData lastSnapData_;

    private DragFlag dragMode_;
    private int pushX_, pushY_;
    private int dragBx_, dragBy_, dragBr_, dragBt_; // selection bbox at drag start
    private bool dragMoved_;
    private DragOrigin[] dragOrigins_;
    /// The box's currently-moving opposite corner while `dragMode_ ==
    /// dragBox` -- `pushX_`/`pushY_` (already tracked for every other
    /// drag mode) serve as the box's fixed origin corner, so no
    /// separate origin fields were needed for this mode.
    private int boxX1_, boxY1_;

    /// The "anchor" end of a Shift-click range-select -- the last
    /// widget hit by a *plain* (unmodified) click, updated only there
    /// (Ctrl-click/Shift-click themselves never move it, matching the
    /// conventional "Explorer/Finder"-style Shift-click shape: repeated
    /// Shift-clicks with different targets each recompute the range
    /// from this same fixed anchor, not cumulatively from the previous
    /// Shift-click's own target). See `selectRange()`.
    private WidgetNode rangeAnchor_;

    /// Fired once, lazily, the first time an armed drag actually
    /// produces movement (not on every mouse-down) -- lets `gui_main.d`
    /// `checkpoint()` before the live geometry mutation begins, matching
    /// every other mutating entry point's "checkpoint before the edit"
    /// convention. A plain click that never moves the mouse never fires
    /// this, so selecting something never pushes an empty undo entry.
    void delegate() onBeforeGeometryEdit;

    /// Fired once after a real move/resize drag ends (`Event.release`)
    /// with actual movement -- lets `gui_main.d` refresh the property
    /// panel and mark the project dirty, the same way `alignSelected()`
    /// already does after `alignWidgets()` mutates geometry.
    void delegate() onGeometryEdited;

    /// Fired after a click changes the selection (possibly to an empty
    /// array, if the click hit nothing live and wasn't a modifier-click)
    /// -- the shelf window wires this to the node browser
    /// (`fluid.node_browser`) and property panel (`panels/widget_panel.fl`)
    /// so all three stay in sync, matching FLTK's own shared-
    /// `Node.selected`-flag sync model. Does *not* itself notify the
    /// caller that invoked it -- callers that already know (e.g. the
    /// node browser, reacting to its own click) should update their
    /// own UI directly rather than bouncing back through the delegate.
    void delegate(Node[]) onSelectionChanged;

    /// Fired when Delete/Backspace is pressed while the canvas has
    /// keyboard focus -- `gui_main.d` wires this to its own
    /// `deleteSelected()`. The canvas itself has no opinion on *what*
    /// deleting means (removing from the `Node` tree, destroying the
    /// live widget, refreshing the browser, ...) -- that's all
    /// `gui_main.d`'s own state to own, matching how `onSelectionChanged`
    /// already delegates "what does a selection change mean" outward
    /// rather than the canvas reaching into browser/property-panel
    /// state itself.
    void delegate() onDeleteRequested;

    /// Fired on a double-click (or, per this module's own top comment on
    /// the Ctrl-collision, a *plain* click alone -- see the doc comment
    /// where this is fired) on an already-armed selection with no actual
    /// drag movement -- `gui_main.d` wires this to `openNode()`, matching
    /// FLTK's own `Window_Node::handle()` `FL_RELEASE` case
    /// (`Widget_Node::open()`).
    void delegate(Node) onOpenRequested;

    /// Fired on a right-click (`event_button() >= 3`) anywhere on the
    /// canvas, `(x, y)` in this window's own local coordinates -- ported
    /// from FLTK's own `Window_Node::handle()` `FL_PUSH`
    /// case (`New_Menu->popup(mx,my,"New",myprev)`). The canvas has no
    /// menu-item list of its own to show -- `gui_main.d` already owns
    /// the real `&New` widget-creation menu, so it's the one that builds
    /// and pops up the actual context menu; this delegate just tells it
    /// where and that a right-click happened, the same "canvas reports
    /// the interaction, the owner decides what it means" split every
    /// other delegate on this class already uses.
    void delegate(int x, int y) onContextMenu;

    /// Fired on a real drag-and-drop widget-palette drop (`Event.paste`,
    /// see `fluid/panels/BinButton.d`'s `BinButton`/`fluid/panels/
    /// function_panel.fl`'s `widgetBinPanel` for the sending side) --
    /// `typeName` is the dropped payload
    /// (`fluid.instantiate`'s registered type name), `parent` is the
    /// container the drop landed in/over (resolved live during
    /// `Event.dndEnter`/`dndDrag`, see `handle()` below), and `x`/`y`
    /// are the drop point in this window's own coordinate space --
    /// already directly usable as the new node's `WidgetNode.x/y`
    /// without any parent-relative translation, since this port stores
    /// (and `fluid.instantiate` applies) every node's geometry as
    /// window-relative, matching real FLTK's own widget-coordinate
    /// convention (see `hitTest()`'s own doc comment below). `gui_main.d`
    /// owns the actual `Node`/live-widget construction (checkpoint,
    /// browser rebuild, ...), the same split `onDeleteRequested` already
    /// established.
    void delegate(string typeName, Node parent, int x, int y) onWidgetDropped;

    /// Fired on a real drag-and-drop *image file* drop (`Event.paste`,
    /// dropped from outside Fluid entirely -- a file manager, a
    /// browser, ...) landing on a widget, as opposed to a widget-bin
    /// type-name drop (`onWidgetDropped` above) -- ported from
    /// `Window_Node::handle()`'s own `FL_PASTE` case's "it's not a
    /// FLUID type, so it could be the filename of an image" fallback.
    /// `path` is the dropped file's own real path (see
    /// `imageDropPath()`'s own doc comment for what "real" means here
    /// and its one documented gap), `target` is the widget the drop
    /// landed on, `inactive` is whether Alt was held (FLTK: sets
    /// the widget's *inactive* image instead of its normal one).
    /// `gui_main.d` owns the actual project-relative-path resolution
    /// and live-widget `.image()`/`.deimage()` update, the same split
    /// `onWidgetDropped` already established.
    void delegate(string path, Node target, bool inactive) onImageDropped;

    /// The container a drag-and-drop is currently hovering over --
    /// tracked across `Event.dndEnter`/`dndDrag` so `Event.paste` (which
    /// carries no position information of its own beyond `eventX()`/
    /// `eventY()`, already consumed by then) knows which parent to drop
    /// into. Deliberately not restored on `Event.dndLeave`/a cancelled
    /// drag -- matches FLTK's own `Window_Node::handle()`, which
    /// mutates `Fluid.proj.tree.current`/the selection as live visual
    /// feedback during the drag and never reverts it either.
    private Node dndTarget_;

    /// `projectDir` resolves any `WidgetNode.imageFilename`/
    /// `.deimageFilename` (the `Widget_Image` port) the same way `code_writer.d`'s own D-codegen
    /// path does -- see `instantiate()`'s own doc comment. Defaults to
    /// "." (an unsaved, not-yet-on-disk project has no meaningful
    /// project directory yet anyway, matching `gui_main.d`'s own
    /// `projectDir_()` helper).
    this(WindowNode rootNode, string projectDir = ".")
    {
        root_ = rootNode;
        int w = rootNode.hasXywh ? rootNode.w : 400;
        int h = rootNode.hasXywh ? rootNode.h : 300;
        // A window with no `label` property gets no title at all,
        // matching FLTK: `Window_Node::setlabel()` just forwards
        // straight to `Fl_Window::label()`, and real FLTK's own
        // "Untitled" fallback (`Project.cxx`'s `Untitled.fl`) is the
        // *project file's* own display name, never a per-window label
        // default -- confirmed by grepping the whole `fluid/` tree for
        // "Untitled": it appears nowhere near `Window_Node`.
        super(w, h, rootNode.hasLabel ? rootNode.label : null);
        live_ = instantiate(rootNode, this, projectDir);
    }

    /// Rebuilds this canvas's live widget content in place from
    /// `newRoot`, keeping the same underlying `fl.window.Window`/X11
    /// resource alive throughout -- the undo/redo counterpart to the
    /// constructor above, called by `gui_main.d`'s `restoreFromText()`
    /// instead of destroying this canvas and creating a fresh one for
    /// every window on every single undo/redo step.
    ///
    /// Rebuilding every open window from
    /// scratch on every undo/redo step (`gui_main.d`'s own `showWindowCanvas()`
    /// creating a brand-new `ProjectCanvas` -- a brand-new X11 window --
    /// since `restoreFromText()` always produces fresh `WindowNode`
    /// instances by re-parsing the whole project's `.fl` text) would be
    /// visibly disruptive: several
    /// window managers (tiling ones especially) don't respect a
    /// program's requested position for what they see as a brand-new
    /// top-level window at all, placing it according to their own
    /// layout instead, even if the previous on-screen position is
    /// reused before the new window's first `show()`. The real fix is never destroying the X11 window
    /// in the first place: `clear()` destroys just this window's own
    /// *children* (the same real, deterministic teardown `Group.
    /// clear()`/`deleteChild()` already give every other mutating entry
    /// point in this editor), then `instantiate()` -- the exact same
    /// function the constructor above calls, already designed to double
    /// as a live model->widget re-sync path (see its own doc comment on
    /// `applyProperties()`'s `hidden`/`deactivated` handling) -- rebuilds
    /// them from `newRoot`. The window itself never unmaps, never loses
    /// focus/stacking order, and never gets a new X11 id.
    void rebuildFrom(WindowNode newRoot, string projectDir = ".")
    {
        clear();
        selected_ = [];
        rangeAnchor_ = null;
        root_ = newRoot;
        live_ = instantiate(newRoot, this, projectDir);
        redraw();
    }

    /// Resizing the design window
    /// itself -- via the window manager (`gui_main.d`'s own
    /// `resizable(this)`) or the Properties
    /// panel's own W/H fields -- must update the project's own
    /// `WindowNode.w`/`.h`, or the panel would keep showing stale values
    /// after a WM-driven resize, and generated code (Code View, `-c`)
    /// would use the *original* size regardless of what the window had
    /// actually been resized to since. `WindowNode` is the single
    /// source of truth `code_writer.d`/the panel both read from --
    /// nothing kept it in sync with the live window's own real,
    /// current size the way an ordinary widget's node is kept in sync
    /// by every edit path that touches it.
    ///
    /// Deliberately only syncs `w`/`h`, not `x`/`y`: this window's own
    /// on-screen *position* is an editor-session, window-manager-
    /// decided detail with no meaningful equivalent in the generated
    /// program (the same reason `instantiate()`'s own `applyProperties(
    /// root, into, projectDir, false)` call never reapplies the root's
    /// recorded position onto the live canvas in the first place --
    /// see that call's own comment) -- syncing it back would mean a
    /// generated program's own startup window position silently
    /// depended on wherever the *editor's* preview window happened to
    /// be sitting on the developer's own screen, which nothing about
    /// this feature request asked for and would be actively wrong.
    override void resize(int X, int Y, int W, int H)
    {
        bool sizeChanged = (W != w() || H != h());

        // See `allowLayout`'s own doc comment. Matches FLTK's own
        // `Overlay_Window::resize()` technique exactly (`Window_Node.cxx`):
        // temporarily clear `resizable()` around the real `super.resize()`
        // call rather than bypassing it -- this window's own `resize()`
        // chain (WM size hints, the actual X11 resize) still needs to run
        // unconditionally, only the `FlGroup.resize()` cascade partway
        // through it should skip repositioning/resizing children. Safe to
        // do unconditionally on a pure move too (`!sizeChanged`): a plain
        // `FlGroup.resize()` already zeroes `dx`/`dy` for any window
        // regardless of `resizable()` (see that method's own doc
        // comment), so clearing it here has no effect on that case either
        // way -- no need to gate this on `sizeChanged` specifically.
        Widget savedResizable = resizable();
        if (!allowLayout) resizable(null);
        super.resize(X, Y, W, H);
        if (!allowLayout) resizable(savedResizable);

        if (sizeChanged && shown())
        {
            if (auto wn = cast(WindowNode) root_)
            {
                wn.w = W;
                wn.h = H;
                wn.hasXywh = true;
            }
            if (onGeometryEdited !is null) onGeometryEdited();
        }
    }

    /// The live widget tree this canvas rendered `root_` into --
    /// the widget panel (`panels/widget_panel.fl`) needs this to find the
    /// live `Widget` for whatever `Node` gets selected.
    LiveTree liveTree() { return live_; }

    /// Every currently-selected node, in the order each was added to
    /// the selection (`selectOnly()` resets this to a single element).
    Node[] selected() { return selected_; }

    /// The node the property panel should show/edit -- the most
    /// recently added member of the selection, or `null` if nothing is
    /// selected. See this module's own top comment on why multi-target
    /// apply isn't built here.
    Node primarySelection() { return selected_.length ? selected_[$ - 1] : null; }

    bool isSelected(Node n) const
    {
        import std.algorithm : canFind;
        return selected_.canFind(n);
    }

    /// Replaces the whole selection with just `n` (or clears it, if
    /// `null`) -- the plain-click case.
    void selectOnly(Node n)
    {
        clearSelectedFlags(root_);
        selected_ = n is null ? [] : [n];
        if (n !is null) n.selected_ = true;
        redrawOverlay();
    }

    /// Replaces the whole selection with exactly `nodes`, without
    /// firing `onSelectionChanged` -- for the node browser's own click
    /// handling to push its (already-known) selection onto the canvas,
    /// the mirror of `selectOnly()`/`toggleSelection()` pushing the
    /// canvas's own clicks onto the browser via `syncSelection()`.
    void syncSelectionFrom(Node[] nodes)
    {
        clearSelectedFlags(root_);
        selected_ = nodes.dup;
        foreach (n; selected_) n.selected_ = true;
        redrawOverlay();
    }

    /// Toggles `n`'s membership in the current selection -- the
    /// Ctrl-click case (adds it if not already selected, removes it if
    /// it is; matches the universal desktop convention for this
    /// modifier). Distinct from Shift-click, which is a real
    /// range-select (`selectRange()`, using `flattenWidgets()`'s
    /// traversal order, shared with Tab-cycling) -- the two modifiers
    /// must not collapse into the same behavior.
    void toggleSelection(Node n)
    {
        import std.algorithm : countUntil, remove;

        if (n is null) return;
        auto idx = selected_.countUntil(n);
        if (idx >= 0)
        {
            selected_ = selected_.remove(idx);
            n.selected_ = false;
        }
        else
        {
            selected_ ~= n;
            n.selected_ = true;
        }
        redrawOverlay();
    }

    /// Shift-click range-select: replaces the whole selection with
    /// every widget between `rangeAnchor_` (the last *plain*-clicked
    /// widget) and `n`, inclusive, in `flattenWidgets()`'s own pre-order
    /// -- the "Explorer/Finder"-style shape: repeated Shift-clicks
    /// recompute the range from the same fixed anchor each time, they
    /// don't accumulate. Falls back to a plain single-widget select
    /// (and adopts `n` as the new anchor) when there's no anchor yet, or
    /// when either end isn't in the flattened list at all (shouldn't
    /// normally happen -- both come from a live hit-test against the
    /// same tree `flattenWidgets()` walks -- but a range-select with a
    /// nonsensical range is worse than degrading to a plain select).
    private void selectRange(Node n)
    {
        auto wn = cast(WidgetNode) n;
        if (wn is null) return;

        if (rangeAnchor_ is null)
        {
            selectOnly(n);
            rangeAnchor_ = wn;
            return;
        }

        import std.algorithm : countUntil, min, max;

        auto flat = flattenWidgets(root_);
        auto ai = flat.countUntil(rangeAnchor_);
        auto bi = flat.countUntil(wn);
        if (ai < 0 || bi < 0)
        {
            selectOnly(n);
            rangeAnchor_ = wn;
            return;
        }

        auto lo = min(ai, bi), hi = max(ai, bi);
        clearSelectedFlags(root_);
        selected_ = [];
        foreach (i; lo .. hi + 1)
        {
            selected_ ~= cast(Node) flat[i];
            flat[i].selected_ = true;
        }
        redrawOverlay();
    }

    private static void clearSelectedFlags(Node n)
    {
        n.selected_ = false;
        foreach (c; n.children) clearSelectedFlags(c);
    }

    /// Checkerboard-fills the whole canvas before the real content
    /// paints whenever the window's own `box()` wouldn't itself cover
    /// every pixel (`noBox`, any frame-only type, or anything in the
    /// `roundedBox`-and-beyond "may leave gaps" range) -- ported from
    /// `Overlay_Window::draw()`'s own numeric boxtype test verbatim
    /// (`fl.enumerations.Boxtype`'s declared order matches FLTK's
    /// `Fl_Boxtype` numbering exactly, confirmed field-by-field, so the
    /// same bit-pattern check applies unchanged). Lets the user see
    /// which areas of a transparent/frame-boxed window are actually
    /// clear, the same purpose it serves in FLTK.
    ///
    /// "Show Ghosted Group Outlines" (`Fluid.
    /// show_ghosted_outline`): FLTK's own mechanism is two-part --
    /// `Overlay_Window::draw()` temporarily swaps `FL_FLAT_BOX`'s
    /// registered drawing function for `fd_flat_box_ghosted()` around
    /// the real content redraw (ported as `fl.draw.ghostFlatBox`, a
    /// plain flag `drawBoxAt()`'s own `flatBox` case consults -- see
    /// that flag's own doc comment for why a flag substitutes for
    /// FLTK's function-pointer swap), plus a *separate* explicit
    /// outline for any `noBox` group specifically (FLTK:
    /// `Group_Node.cxx`/`Grid_Node.cxx`'s own live-preview `draw()`
    /// overrides -- `if (Fluid.show_ghosted_outline && box()==FL_NO_
    /// BOX) fl_rect(...)`), since a `noBox` widget paints nothing at
    /// all for the flat-box swap to ever apply to. This port has no
    /// per-node-kind proxy `draw()` overrides the way FLTK's
    /// `Fl_Group_Proxy`/`Fl_Grid_Proxy` provide (`fluid.instantiate`
    /// creates plain `fl.group.Group`/`fl.grid.Grid` instances
    /// directly, matching this project's established "concrete, not
    /// polymorphic" stance) -- `outlineNoBoxGroups()` below covers the
    /// same ground with one tree-walk from here instead, right after
    /// the real content has been drawn. Covers every FLTK node
    /// kind that gets this treatment: `Group`/`Tabs`/`Wizard`/`Pack`/
    /// `Scroll`/`Tile` all instantiate as plain `fl.group.Group`
    /// (`fluid.factory`'s own registry), and `fl.grid.Grid` is a
    /// `Group` subclass too, so a single `cast(FlGroup)` walk reaches
    /// all of them with no extra type-kind checks needed.
    override void draw()
    {
        enum checkSize = 8;
        if ((damage() & damageAll)
            && (box() == Boxtype.noBox
                || (box() >= 4 && (box() & 2) == 0)
                || box() >= Boxtype.roundedBox))
        {
            for (int Y = 0; Y < h(); Y += checkSize)
                for (int X = 0; X < w(); X += checkSize)
                {
                    fl_color(((Y / (2 * checkSize)) & 1) != ((X / (2 * checkSize)) & 1)
                        ? fl.enumerations.white : fl.enumerations.black);
                    fl_rectf(X, Y, checkSize, checkSize);
                }
        }
        ghostFlatBox = showGhostedOutline;
        super.draw();
        ghostFlatBox = false;
        if (showGhostedOutline) outlineNoBoxGroups(this);
    }

    /// See `draw()`'s own doc comment. Recurses into every child,
    /// drawing a contrast outline (FLTK's own `fl_color_average
    /// (FL_FOREGROUND_COLOR, color(), .1f)` formula, `colorAverage()`
    /// here) around any `Group` (or subclass, e.g. `fl.grid.Grid`)
    /// whose own `box()` is `noBox` -- an otherwise fully invisible
    /// container, which the `ghostFlatBox` flat-box swap above can
    /// never reach since it never calls the flat-box drawer at all.
    ///
    /// Must skip an invisible child (and, since it's a
    /// container, everything nested inside it) entirely: recursing into
    /// every
    /// child unconditionally would give a `Tabs`' *inactive* pages their own
    /// no-box outline too, right alongside the active page's --
    /// FLTK never shows this, since `Fl_Group_Proxy::draw()`'s
    /// equivalent outline is drawn from *within* each group's own `draw()`
    /// override, and `FlGroup.drawChildren()` never calls `draw()` on a
    /// hidden child at all (see `collectWithDepth()`'s own matching note).
    private static void outlineNoBoxGroups(FlGroup g)
    {
        foreach (i; 0 .. g.children())
        {
            auto c = g.child(i);
            if (!c.visible()) continue;
            if (auto cg = cast(FlGroup) c)
            {
                if (cg.box() == Boxtype.noBox)
                {
                    fl_color(colorAverage(foregroundColor, cg.color(), 0.1f));
                    fl_rect(cg.x(), cg.y(), cg.w(), cg.h());
                }
                outlineNoBoxGroups(cg);
            }
        }
    }

    /// FLTK: `fd_hatch()` (`nodes/Window_Node.cxx`) -- a diagonal
    /// hatch-line pattern (not a solid fill) covering a rectangle
    /// expanded by `pad` on every side, used to flag both out-of-bounds
    /// and overlapping widget regions below. Pure geometry, no FLTK-
    /// specific behavior beyond `fl_line()`, so ported verbatim rather
    /// than reinterpreted -- three line-drawing phases depending on
    /// whether the (padded) rectangle is wider than it is tall.
    private static void hatch(int x, int y, int w, int h, int size = 6, int offset = 0, int pad = 3)
    {
        x -= pad;
        y -= pad;
        w += 2 * pad;
        h += 2 * pad;
        int yp = (x + offset + y * size - 1 - y) % size;
        if (w > h)
        {
            for (; yp < h; yp += size) fl_line(x, y + yp, x + yp, y);
            for (; yp < w; yp += size) fl_line(x + yp - h, y + h, x + yp, y);
            for (; yp < w + h; yp += size) fl_line(x + yp - h, y + h, x + w, y + yp - w);
        }
        else
        {
            for (; yp < w; yp += size) fl_line(x, y + yp, x + yp, y);
            for (; yp < h; yp += size) fl_line(x, y + yp, x + w, y + yp - w);
            for (; yp < h + w; yp += size) fl_line(x + yp - h, y + h, x + w, y + yp - w);
        }
    }

    /// FLTK: `Window_Node::draw_out_of_bounds(Widget_Node*, int,
    /// int, int, int)` -- hatches the portion of any direct child of
    /// `g` that sticks outside `(boundsX, boundsY, boundsW, boundsH)`,
    /// then recurses into every nested `Group` (using *that* group's
    /// own `x()`/`y()`/`w()`/`h()` as the next bounds, matching FLTK's
    /// "coordinates are relative to the nearest enclosing window, not
    /// the immediate parent" convention exactly -- no coordinate
    /// translation needed at any level). Skips `Scroll`, matching
    /// FLTK's own explicit exclusion (`draw_out_of_bounds()`'s own
    /// comment: "don't do this for Fl_Scroll (which we currently can't
    /// handle in FLUID anyway)") -- a scrollable child area is expected
    /// to extend beyond its own visible viewport, so flagging that as
    /// "out of bounds" would be actively wrong, not just unhelpful.
    ///
    /// **Also skips `TextDisplay`** (covers `TextEditor` too, a
    /// subclass): without this, a
    /// widget_panel.fl `Comment:`/`Declaration:`/etc. field would hatch
    /// across the whole panel's own upper-left corner from `(0,0)`
    /// outward. Root cause: FLTK's own `draw_out_of_bounds()`
    /// walks *Fluid's own project-node tree*, a data structure that
    /// only ever contains one entry per `Widget_Node` -- it has no way
    /// to see a widget's own private implementation-detail children at
    /// all, since those were never Nodes to begin with. This port's
    /// version, by contrast, walks the *live FLTK widget tree* directly
    /// (`FlGroup.children()`), matching this port's own "concrete, not
    /// polymorphic" instantiation model -- but that means it reaches
    /// `TextDisplay`'s own real internal `hScrollBar_`/`vScrollBar_`
    /// (constructed at `new Scrollbar(0, 0, 1, 1)`, matching FLTK
    /// exactly -- see `fl.text_display.TextDisplay`'s own constructor;
    /// only ever repositioned once a real `resize()`/layout pass runs).
    /// A `TextDisplay` inside a page that's constructed but never
    /// actually drawn (an inactive `Tabs` page nobody has switched to
    /// yet, for instance) never gets that layout pass, so its
    /// scrollbars sit at that literal `(0,0,1,1)` placeholder forever
    /// -- massively "out of bounds" against any real bounds, and this
    /// function (unlike `overlapHatch()` below) never skipped hidden
    /// widgets in the first place. Not `widget_panel.fl`-specific: any
    /// project with a `TextEditor`/`TextDisplay` on an inactive Tabs
    /// page hits this once "Show Restricted Areas" is on. Treating
    /// `TextDisplay` as an opaque leaf (matching how FLTK's own
    /// node-tree walk implicitly treats it, having no way to do
    /// otherwise) is the fix, not fixing the scrollbars' own placeholder
    /// geometry, which is correct/faithful on its own.
    private static void outOfBoundsHatch(FlGroup g, int boundsX, int boundsY, int boundsW, int boundsH)
    {
        foreach (i; 0 .. g.children())
        {
            auto o = g.child(i);
            if (o.x() < boundsX) hatch(o.x(), o.y(), boundsX - o.x(), o.h());
            if (o.y() < boundsY) hatch(o.x(), o.y(), o.w(), boundsY - o.y());
            if (o.x() + o.w() > boundsX + boundsW)
                hatch(boundsX + boundsW, o.y(), (o.x() + o.w()) - (boundsX + boundsW), o.h());
            if (o.y() + o.h() > boundsY + boundsH)
                hatch(o.x(), boundsY + boundsH, o.w(), (o.y() + o.h()) - (boundsY + boundsH));
        }
        foreach (i; 0 .. g.children())
        {
            if (auto cg = cast(FlGroup) g.child(i))
                if (cast(Scroll) cg is null && cast(TextDisplay) cg is null)
                    outOfBoundsHatch(cg, cg.x(), cg.y(), cg.w(), cg.h());
        }
    }

    /// FLTK: `Window_Node::draw_overlaps()` -- hatches the
    /// intersection of any two *visible* widgets at the same nesting
    /// depth ("level"), matching that function's own doc comment
    /// ("compare all children in the same level") deliberately, not
    /// narrowed to same-parent siblings only: two widgets from
    /// different branches of the tree can still visually collide on
    /// screen (FLTK positions are always window-relative), and
    /// FLTK's own flat node-list traversal genuinely compares any
    /// same-depth pair reachable before it walks back out of the
    /// window's own subtree, not just direct siblings.
    ///
    /// **Deliberately simplified, not FLTK's exact bounded scan**:
    /// FLTK's own inner loop additionally stops early once the flat
    /// list ascends back out of `q`'s local region (`p->level>=q->
    /// level`) -- a byte-exact replication of that traversal-order-
    /// dependent bound isn't worth the complexity here. This compares
    /// every same-depth pair in the *entire* window's tree instead
    /// (still a real rectangle-intersection test either way, so it can
    /// only ever additionally flag rare, genuinely-overlapping pairs in
    /// deeply-nested layouts FLTK's own narrower scan happens not
    /// to reach -- never a false positive, and every real-world case
    /// FLTK would flag is still flagged here).
    /// Must not recurse into an invisible group's children at all:
    /// `overlapHatch()`'s own `if (!w1.visible()) continue;` check only
    /// excludes a widget from being a hatch *candidate* itself -- it does
    /// nothing for a widget nested *inside* a hidden ancestor, since
    /// `Widget.visible()` (matching FLTK's own non-recursive
    /// `Fl_Widget::visible()`) only ever reports that one widget's own flag,
    /// never an ancestor's. A `Tabs`' inactive pages are hidden by setting
    /// only the *page Group's own* flag (`fl.tabs.Tabs.value()`); the
    /// individual widgets inside that hidden page keep `visible() == true`
    /// on their own account, so without this guard they would still get
    /// collected and
    /// compared against the active page's widgets -- which, for a typical
    /// `.fl` layout where every tab page occupies the same client-area
    /// rectangle, means nearly every widget pair would "overlap." FLTK never
    /// hits this: `Window_Node::draw_overlaps()`'s own traversal walks a
    /// flat, depth-ordered node list and, the moment it finds an invisible
    /// node, fast-forwards past every node whose level is deeper (skipping
    /// the whole subtree without ever visiting it), rather than checking
    /// each descendant's own flag individually.
    ///
    /// **Also doesn't recurse into `TextDisplay`** (covers `TextEditor`
    /// too) -- same reasoning as `outOfBoundsHatch()`'s own identical
    /// exclusion just above (see that doc comment for the full story):
    /// its internal scrollbar children are a live-widget-tree
    /// implementation detail FLTK's own Node-tree walk never had a
    /// way to see, and a scrollbar left at its unlaid-out `(0,0,1,1)`
    /// construction default (a `TextDisplay` inside a page that's never
    /// actually been drawn) is a latent false-overlap source here too,
    /// even though a concrete repro wasn't needed to justify fixing it
    /// the same way.
    private static void collectWithDepth(FlGroup g, int depth, ref Widget[] widgets, ref int[] depths)
    {
        foreach (i; 0 .. g.children())
        {
            auto c = g.child(i);
            if (!c.visible()) continue;
            widgets ~= c;
            depths ~= depth;
            if (auto cg = cast(FlGroup) c)
                if (cast(TextDisplay) cg is null)
                    collectWithDepth(cg, depth + 1, widgets, depths);
        }
    }

    private static void overlapHatch(FlGroup root)
    {
        import std.algorithm : min, max;

        Widget[] widgets;
        int[] depths;
        collectWithDepth(root, 1, widgets, depths);

        foreach (i, w1; widgets)
        {
            if (!w1.visible()) continue;
            int x1 = w1.x(), y1 = w1.y(), r1 = x1 + w1.w(), b1 = y1 + w1.h();
            foreach (j; i + 1 .. widgets.length)
            {
                if (depths[j] != depths[i]) continue;
                auto w2 = widgets[j];
                if (!w2.visible()) continue;
                int px = max(x1, w2.x());
                int py = max(y1, w2.y());
                int pr = min(r1, w2.x() + w2.w());
                int pb = min(b1, w2.y() + w2.h());
                if (pr > px && pb > py) hatch(px, py, pr - px, pb - py);
            }
        }
    }

    override void drawOverlay()
    {
        if (overlaysHidden && dragMode_ == dragNone) return;

        fl_color(fl.enumerations.red);

        // "Show Restricted Areas" (`Fluid.show_restricted`).
        // Matches FLTK's own placement in `Window_Node
        // ::draw_overlay()` exactly: after the `overlaysHidden` guard
        // above, but *before* the rubber-band box-select check below,
        // so restricted-area hatching still shows mid-drag during a
        // box-select the same way FLTK's own (no early-return
        // there) does.
        if (showRestricted)
        {
            fl_color(fl.enumerations.darkRed);
            outOfBoundsHatch(this, 0, 0, w(), h());
            fl_color(fl.enumerations.darkYellow);
            overlapHatch(this);
            fl_color(fl.enumerations.red);
        }

        // Rubber-band box-select in progress -- draws just the box
        // outline and returns, skipping the persistent per-widget
        // selection rects below entirely (matches FLTK's own
        // `Fl_Overlay_Window` model: while a drag interaction is live,
        // its own transient feedback is what's shown, not the prior
        // static selection).
        if (dragMode_ == dragBox)
        {
            int x0 = pushX_ < boxX1_ ? pushX_ : boxX1_;
            int x1 = pushX_ < boxX1_ ? boxX1_ : pushX_;
            int y0 = pushY_ < boxY1_ ? pushY_ : boxY1_;
            int y1 = pushY_ < boxY1_ ? boxY1_ : pushY_;
            fl_rect(x0, y0, x1 - x0, y1 - y0);
            return;
        }

        // `root_` (the window itself) can be part of the selection too
        // -- selecting its own row in the node browser
        // (`fluid.node_browser`) syncs it in via `syncSelectionFrom()`.
        // It needs its own special case, matching FLTK's `if
        // (selected) fl_rect(0,0,o->w(),o->h());`: `root_`'s live
        // widget *is* this canvas itself (see the constructor), whose
        // `x()`/`y()` report its actual screen position, not `0,0` --
        // running it through the generic per-widget branch below (which
        // assumes every entry's `x()`/`y()` are already in this
        // window's own local draw-coordinate space) would offset the
        // highlight by the window's own screen position instead of
        // outlining it. `selectionBounds()`/`beginDrag()` below both
        // exclude `root_` from their own bbox/drag math for the same
        // reason -- matching FLTK, where only *descendants* ever
        // enter the resize-drag machinery to begin with.
        bool windowSelected = false;
        foreach (n; selected_)
        {
            if (n is root_) { windowSelected = true; continue; }
            auto w = n in live_.widgetOf;
            if (w is null) continue;
            // No inflation -- matches FLTK's own per-widget
            // `fl_rect(x,y,r-x,t-y)` exactly (drawn straight off the
            // live widget's own edges), so a single selected widget's
            // box below (drawn at the same, uninflated edges) coincides
            // with this one instead of showing as two concentric rects
            // 1px apart (a real bug this pass introduced and caught
            // before landing -- an earlier version of this line read
            // `(*w).x() - 1, (*w).y() - 1, (*w).w() + 2, (*w).h() + 2`).
            fl_rect((*w).x(), (*w).y(), (*w).w(), (*w).h());
        }
        if (windowSelected)
        {
            fl_rect(0, 0, w(), h());
            return; // matches FLTK's own early-out (`if (selected) return;`)
        }

        // Dashed outer rect additionally expanded for any selected
        // widget's own outside-the-box label -- ported from FLTK's
        // `fl_focus_rect(mybx,myby,mybr-mybx,mybt-myby)` (`mybx`/etc.
        // computed alongside `mysx`/etc. in the same loop, widened by
        // each widget's own external `measure_label()` rect whenever
        // `!(align() & alignInside)`). Drawn *underneath* the solid
        // selection box below, matching FLTK's own draw order
        // (`fl_focus_rect` first, then `fl_rect`) -- this is what makes
        // selecting a `Tabs` page (e.g. `wpGuiTab`, whose "GUI" label is
        // drawn by the parent `Tabs` in its own tab bar, not inside the
        // page itself, so it defaults to `alignTop`, not `alignInside`)
        // show a dotted box reaching up to include that tab label, not
        // just the page's own content area.
        {
            int lbx, lby, lbr, lbt;
            if (selectionBoundsWithLabels(lbx, lby, lbr, lbt))
                focusRect(lbx, lby, lbr - lbx, lbt - lby);
        }

        // Resize-handle affordance -- an outer frame around the whole
        // selection (matching FLTK's own `fl_rect(mysx,mysy,mysr-
        // mysx,myst-mysy)`; needed since, with more than
        // one widget selected, the per-widget boxes above leave the
        // selection with no single connecting outline) plus small
        // filled squares at its corners (`fl_rectf(mysx,mysy,5,5)` et
        // al.), so the user has a visual target for the edge-grab drag
        // `handle()`'s `Event.push` case below tests for.
        int bx, by, br, bt;
        if (selectionBounds(bx, by, br, bt))
        {
            fl_rect(bx, by, br - bx, bt - by);
            fl_rectf(bx - 2, by - 2, 5, 5);
            fl_rectf(br - 3, by - 2, 5, 5);
            fl_rectf(br - 3, bt - 3, 5, 5);
            fl_rectf(bx - 2, bt - 3, 5, 5);
        }

        // Ported from `Window_Node::draw_overlay()`'s own trailing
        // `if (Fluid.show_guides && (drag & (FD_DRAG|FD_TOP|FD_LEFT|
        // FD_BOTTOM|FD_RIGHT))) { ... Snap_Action::draw_all(data); }` --
        // draws whichever guide(s) `checkAll()` found to be the winning
        // match during the current drag (`lastSnapData_`, populated by
        // `Event.drag` right before this same `redrawOverlay()` fires).
        if (showGuides && dragMode_ != dragNone)
            drawAll(lastSnapData_);
    }

    /// Bounding box (this window's own local coordinates) of every
    /// currently-selected live widget -- ported from `Window_Node::
    /// draw_overlay()`'s own `bx/by/br/bt` recalculation. Returns
    /// `false` (all fields left at their `out`-default `0`) if nothing
    /// in the current selection has a live widget.
    private bool selectionBounds(out int bx, out int by, out int br, out int bt)
    {
        bool any;
        bx = w(); by = h(); br = 0; bt = 0;
        foreach (n; selected_)
        {
            if (n is root_) continue;
            auto wp = n in live_.widgetOf;
            if (wp is null) continue;
            auto wgt = *wp;
            any = true;
            if (wgt.x() < bx) bx = wgt.x();
            if (wgt.y() < by) by = wgt.y();
            if (wgt.x() + wgt.w() > br) br = wgt.x() + wgt.w();
            if (wgt.y() + wgt.h() > bt) bt = wgt.y() + wgt.h();
        }
        return any;
    }

    /// Same bounding box as `selectionBounds()`, but widened per-widget
    /// for any selected widget's own *external* label -- ported from
    /// `Window_Node::draw_overlay()`'s own `mybx`/`myby`/`mybr`/`mybt`
    /// (as opposed to that same loop's `mysx`/`mysy`/`mysr`/`myst`,
    /// which `selectionBounds()` above already matches and which stays
    /// unwidened -- FLTK keeps both boxes: the wider one only for
    /// `fl_focus_rect()`'s own dashed outline, the narrower one for the
    /// solid resize-handle box and the drag-snapping math). Only used
    /// for that one dashed-outline draw call -- deliberately *not*
    /// substituted for `selectionBounds()` at any of its other call
    /// sites (drag math, empty-space detection, ...), matching FLTK
    /// exactly (`sx=mysx` etc., never `mybx`, feeds `newposition()`).
    /// No wrap-width hint passed to `measureLabel()` (unlike FLTK's
    /// in/out `measure_label(ww, hh)`, which uses `ww` as the wrap
    /// width for an `alignWrap` label) -- `Widget.measureLabel()` takes
    /// no such hint at all yet, a separate, pre-existing, narrower gap
    /// that doesn't affect a short, unwrapped tab label like `wpGuiTab`'s
    /// own "GUI".
    private bool selectionBoundsWithLabels(out int bx, out int by, out int br, out int bt)
    {
        bool any;
        bx = w(); by = h(); br = 0; bt = 0;
        foreach (n; selected_)
        {
            if (n is root_) continue;
            auto wp = n in live_.widgetOf;
            if (wp is null) continue;
            auto wgt = *wp;
            any = true;
            int x = wgt.x(), y = wgt.y(), r = wgt.x() + wgt.w(), t = wgt.y() + wgt.h();
            if (!(wgt.alignment() & fl.enumerations.alignInside))
            {
                int ww, hh;
                wgt.measureLabel(ww, hh);
                if (wgt.alignment() & fl.enumerations.alignTop) y -= hh;
                else if (wgt.alignment() & fl.enumerations.alignBottom) t += hh;
                else if (wgt.alignment() & fl.enumerations.alignLeft) x -= ww + 4;
                else if (wgt.alignment() & fl.enumerations.alignRight) r += ww + 4;
            }
            if (x < bx) bx = x;
            if (y < by) by = y;
            if (r > br) br = r;
            if (t > bt) bt = t;
        }
        return any;
    }

    /// Arms a move/resize drag as of `mx`/`my` (the just-received
    /// `Event.push`'s coordinates) -- snapshots every selected
    /// `WidgetNode`'s current live geometry as the fixed origin
    /// `applyDrag()` will compute every subsequent frame relative to.
    private void beginDrag(DragFlag flag, int bx, int by, int br, int bt, int mx, int my)
    {
        dragMode_ = flag;
        pushX_ = mx; pushY_ = my;
        dragBx_ = bx; dragBy_ = by; dragBr_ = br; dragBt_ = bt;
        dragMoved_ = false;
        dragOrigins_ = [];
        foreach (n; selected_)
        {
            if (n is root_) continue; // see drawOverlay()'s own note on why
            auto wn = cast(WidgetNode) n;
            if (wn is null) continue;
            auto wgt = live_.widgetOf.get(n, null);
            if (wgt is null) continue;
            dragOrigins_ ~= DragOrigin(wn, wgt.x(), wgt.y(), wgt.w(), wgt.h());
        }
    }

    /// The minimum width/height a drag is ever allowed to shrink a
    /// widget to -- FLTK has no equivalent explicit clamp in this
    /// exact function (`Fl_Widget::resize()` itself doesn't reject a
    /// tiny/zero size either), but letting a live widget collapse to
    /// zero or negative size is both visually useless and a real crash
    /// risk in some drawing code paths, so this port clamps defensively.
    private enum minWidgetSize = 4;

    /// Applies the current drag's accumulated delta (`ddx`/`ddy`,
    /// relative to `pushX_`/`pushY_`) to every widget captured in
    /// `dragOrigins_` -- ported from `Window_Node::newposition()`
    /// exactly (per-widget edge clamping against the drag's own fixed
    /// starting bounding box `dragBx_`-`dragBt_`), including one
    /// faithfully-preserved FLTK quirk: the `FD_BOTTOM` branch's
    /// "don't invert past the new bound" check compares against
    /// `dragBt_ + ddx` (not `+ ddy`) -- almost certainly an FLTK
    /// typo (see `FLTK_ISSUES.md`), ported as-is rather than
    /// silently corrected, matching this port's own "log it, don't
    /// quietly fix it" policy for unconfirmed FLTK bugs.
    private void applyDrag(int ddx, int ddy)
    {
        foreach (o; dragOrigins_)
        {
            int X = o.x, Y = o.y, R = o.x + o.w, T = o.y + o.h;
            if (dragMode_ & dragMove)
            {
                X += ddx; Y += ddy; R += ddx; T += ddy;
            }
            else
            {
                if (dragMode_ & dragLeft)
                {
                    if (X == dragBx_) X += ddx;
                    else if (X < dragBx_ + ddx) X = dragBx_ + ddx;
                }
                if (dragMode_ & dragTop)
                {
                    if (Y == dragBy_) Y += ddy;
                    else if (Y < dragBy_ + ddy) Y = dragBy_ + ddy;
                }
                if (dragMode_ & dragRight)
                {
                    if (R == dragBr_) R += ddx;
                    else if (R > dragBr_ + ddx) R = dragBr_ + ddx;
                }
                if (dragMode_ & dragBottom)
                {
                    if (T == dragBt_) T += ddy;
                    else if (T > dragBt_ + ddx) T = dragBt_ + ddx; // see this function's own doc comment
                }
            }
            if (R < X) { int t = X; X = R; R = t; }
            if (T < Y) { int t = Y; Y = T; T = t; }

            int neww = R - X, newh = T - Y;
            if (neww < minWidgetSize) neww = minWidgetSize;
            if (newh < minWidgetSize) newh = minWidgetSize;

            auto wgt = live_.widgetOf.get(o.node, null);
            if (wgt is null) continue;

            // See `allowLayout`'s own doc comment for the full mechanism
            // and its two disclosed simplifications versus FLTK.
            // A plain move (`dragMove`) always uses the real, polymorphic
            // `resize()` -- for a `Group`-family widget this dispatches to
            // `FlGroup.resize()`, whose own "no size change" branch already
            // repositions every child by the same `dx`/`dy` unconditionally
            // (matching FLTK's own unconditional per-descendant
            // translation during a move, just via this port's existing
            // cascade instead of a separate manual walk). `Flex`/`Grid`
            // also always get the real `resize()` even when *resizing* --
            // their own `resize()` overrides always self-layout regardless
            // of this flag, matching FLTK's own forced bracket around
            // exactly those two node kinds. Everything else (an ordinary
            // `Group`/`Window`/etc. actually changing size) is gated: real
            // `resize()` (the `FlGroup.resize()` cascade) when `allowLayout`
            // is on, `resizeBoundsOnly()` (skip the cascade, matching
            // FLTK's own `Fl_Group_Proxy::resize()` "off" branch
            // calling `Fl_Widget::resize()` instead) when it's off.
            bool forceRealResize = (dragMode_ & dragMove) != 0
                || cast(Flex) wgt !is null || cast(Grid) wgt !is null;
            if (allowLayout || forceRealResize)
                wgt.resize(X, Y, neww, newh);
            else
                wgt.resizeBoundsOnly(X, Y, neww, newh);
        }
    }

    /// Writes every dragged/nudged widget's real, live post-move/-resize
    /// geometry back onto its own `Node` and fires `onGeometryEdited` --
    /// factored out of `Event.release`'s own move/resize-commit branch
    /// (formerly inline there) so keyboard arrow-nudge can reuse the
    /// identical logic instead of duplicating it. Sharing this matters,
    /// not just tidiness: without it, an arrow-key nudge would move the
    /// *live* widget (via `applyDrag()`) but never persist the new
    /// position to the node tree and never notify anything to
    /// checkpoint/mark dirty -- a silent-data-loss bug in the same
    /// family as this session's own shortcut-modifier one.
    private void commitDragGeometry()
    {
        foreach (o; dragOrigins_)
        {
            auto wgt = live_.widgetOf.get(o.node, null);
            if (wgt is null) continue;
            o.node.x = wgt.x();
            o.node.y = wgt.y();
            o.node.w = wgt.w();
            o.node.h = wgt.h();
            o.node.hasXywh = true;
        }
        if (onGeometryEdited !is null) onGeometryEdited();
    }

    /// Selects (or, `toggle`, flips the selection state of) every
    /// widget fully contained in the box from `(pushX_, pushY_)` to
    /// `(boxX1_, boxY1_)` -- the `Event.release` counterpart to
    /// `Event.push`'s `dragBox` arming. Ported from `Window_Node::
    /// handle()`'s own `FL_RELEASE` box-select branch, including its
    /// exact containment test (`>=`/`>` on the near edges, `<` on the
    /// far ones -- FLTK's own asymmetry, kept rather than "fixed").
    /// `toggle` (Shift held) flips each covered widget's own prior
    /// selection state and leaves everything outside the box untouched,
    /// matching FLTK's `select(myo, toggle ? !myo->selected : 1)`;
    /// otherwise the whole selection is cleared first (`selectOnly(
    /// null)`, FLTK's `deselect()`) so only the box's own contents
    /// end up selected.
    ///
    /// **User-reported gap, found comparing this port's own editor
    /// against real FLTK's own Fluid side by side: clicking the
    /// window's own empty margin selected nothing here, but selects the
    /// window itself FLTK.** Root cause traced to FLTK's own
    /// `Window_Node::handle()`: `FL_PUSH` seeds a local `selection =
    /// this` (the window) before scanning descendants, only overwriting
    /// it with a specific child whose bounds contain the click point --
    /// so a click on empty background leaves `selection == this`
    /// unchanged. `FL_RELEASE`'s own box-select loop re-derives
    /// `selection` the same way at the release point, counts how many
    /// widgets actually landed inside the box (`n`), and *only when
    /// `n == 0`* falls back to `select(selection, ...)` -- which is
    /// what actually selects the window for a plain empty-space click
    /// (a box that never grew past a single point, matching zero
    /// widgets inside it either way). This function used to stop after
    /// the containment loop, silently dropping that whole fallback --
    /// reproducing only the "clear the selection" half of FLTK's
    /// behavior, never the "select the window" half. Restored below,
    /// using this port's own `hitTest()` (already the same "what's at
    /// this point" primitive `Event.push` itself uses) at the release
    /// point in place of FLTK's own flat-list re-scan, falling back
    /// to `root_` (the window) when even that finds nothing.
    private void finishBoxSelect(bool toggle)
    {
        int x0 = pushX_ < boxX1_ ? pushX_ : boxX1_;
        int x1 = pushX_ < boxX1_ ? boxX1_ : pushX_;
        int y0 = pushY_ < boxY1_ ? pushY_ : boxY1_;
        int y1 = pushY_ < boxY1_ ? boxY1_ : pushY_;

        if (!toggle) selectOnly(null);

        int n = 0;
        foreach (nd, w; live_.widgetOf)
        {
            if (nd is root_) continue;
            if (w.x() >= x0 && w.y() > y0 && w.x() + w.w() < x1 && w.y() + w.h() < y1)
            {
                n++;
                if (toggle)
                    toggleSelection(nd);
                else if (!isSelected(nd))
                {
                    selected_ ~= nd;
                    nd.selected_ = true;
                }
            }
        }

        if (n == 0)
        {
            auto hitW = hitTest(this, boxX1_, boxY1_);
            Node fallback = hitW is null ? root_ : live_.nodeOf.get(hitW, root_);
            if (fallback !is null)
            {
                if (toggle)
                    toggleSelection(fallback);
                else if (!isSelected(fallback))
                {
                    selected_ ~= fallback;
                    fallback.selected_ = true;
                }
                rangeAnchor_ = cast(WidgetNode) fallback;
            }
        }

        redrawOverlay();
        if (onSelectionChanged !is null) onSelectionChanged(selected_);
    }

    /// Every `WidgetNode` under `n`, in pre-order -- backs Tab/Shift+Tab
    /// widget-cycling (`handle()`'s own `Event.keyDown`/`tab` case). Not
    /// itself FLTK's traversal (FLTK walks a flat doubly-linked
    /// `Node` list this port's real tree doesn't have) -- see that
    /// case's own doc comment for why the same *effect* is what matters
    /// here, not a byte-for-byte port of the walk itself.
    private static WidgetNode[] flattenWidgets(Node n)
    {
        WidgetNode[] result;
        void walk(Node x)
        {
            foreach (c; x.children)
            {
                if (auto wn = cast(WidgetNode) c) result ~= wn;
                walk(c);
            }
        }
        walk(n);
        return result;
    }

    override int handle(Event e)
    {
        if (e == Event.push)
        {
            dragMode_ = dragNone;
            int mx = eventX(), my = eventY();

            // Right-click test *first*, before anything else in this
            // case -- matches FLTK's own ordering exactly
            // (`Window_Node::handle()`'s `FL_PUSH`: `if (Fl::event_
            // button() >= 3) { ... New_Menu->popup(...); return 1; }`,
            // checked before any hit-test/edge-grab logic runs at all).
            if (fl.core.eventButton() >= 3)
            {
                if (onContextMenu !is null) onContextMenu(mx, my);
                return 1;
            }

            // Edge/corner-grab check *first*, using the selection as it
            // stood *before* this click -- matches FLTK's own
            // ordering exactly (`Window_Node::handle()`'s `FL_PUSH`
            // case checks `mx<=br+2 && ...` before doing any hit-test/
            // reselection), so grabbing a resize handle never disturbs
            // an existing multi-selection. This only *arms* `flag`,
            // though -- it does not act on it yet (see the `Tabs`
            // click-test just below for why).
            int bx, by, br, bt;
            bool haveSel = selectionBounds(bx, by, br, bt);
            DragFlag flag = dragNone;
            if (haveSel && !fl.core.eventShift()
                && mx <= br + 2 && mx >= bx - 2 && my <= bt + 2 && my >= by - 2)
            {
                if (mx >= br - 5) flag |= dragRight;
                else if (mx <= bx + 5) flag |= dragLeft;
                if (my >= bt - 5) flag |= dragBottom;
                else if (my <= by + 5) flag |= dragTop;
                if (flag == dragNone) flag = dragMove;
            }

            auto hit = hitTest(this, mx, my);
            Node n = hit is null ? null : live_.nodeOf.get(hit, null);

            // Clicking a `Tabs`' own tab-label strip switches pages
            // instead of selecting/dragging the `Tabs` widget itself.
            // Ported from `Tabs_Node::click_test()` (`nodes/
            // Group_Node.cxx`): a click that lands within the `Tabs`'
            // own bounds but not inside any deeper child (`hitTest()`
            // only descends into a *page*'s bounds, which start below
            // the tab strip, so a label click resolves `hit` to the
            // `Tabs` widget itself, same as FLTK's own flat-list
            // hit-scan) forwards the push to the live `Tabs`' own
            // `handle()`/`which()` machinery -- a real FLTK pointer-grab
            // drag loop, exactly as if this were a live, running window
            // -- so it performs its own tab switch, then re-targets the
            // editor's selection at whichever page is now visible.
            //
            // Checked *unconditionally*, even when the edge/corner-grab
            // check above already armed `flag` -- matching FLTK's
            // own sequencing exactly: `Window_Node::handle()` computes
            // `drag` tentatively, then *always* calls `click_test()`
            // next and resets `drag = 0` if it fires, rather than
            // acting on `drag` immediately. **Bug found via a live
            // report**: an earlier version of this function returned
            // right after arming `flag`, before ever reaching this
            // check -- once the `Tabs` itself was the current
            // selection (so `haveSel`'s own bounding box *was* the
            // whole `Tabs`, tab strip included), every subsequent click
            // anywhere inside that box, including directly on a tab
            // label, fell into the `dragMove` fallback and got
            // swallowed as "start moving the selection" before the
            // tab-switch logic ever ran -- the individual tabs became
            // permanently unclickable the moment the `Tabs` widget
            // itself was selected.
            if (auto tabs = cast(Tabs) hit)
            {
                auto clickedTab = tabs.which(mx, my);
                if (clickedTab !is null)
                {
                    tabs.handle(Event.push);
                    fl.core.pushed(tabs);
                    while (fl.core.pushed() is tabs) fl.core.wait();
                    auto selectedTab = tabs.value();
                    auto tabNode = selectedTab is null ? null : live_.nodeOf.get(selectedTab, null);
                    if (tabNode !is null)
                    {
                        if (fl.core.eventCtrl())
                            toggleSelection(tabNode);
                        else if (fl.core.eventShift())
                            selectRange(tabNode);
                        else
                        {
                            selectOnly(tabNode);
                            rangeAnchor_ = cast(WidgetNode) tabNode;
                        }
                        if (onSelectionChanged !is null) onSelectionChanged(selected_);
                    }
                    redrawOverlay();
                    return 1;
                }
            }

            // Clicking an unselected `Choice`/`Menu_Button`/`Menu_Bar`/
            // `Input_Choice` pops up its own real dropdown so the user
            // can pick a menu item to edit -- ported from
            // `Menu_Base_Node::click_test()`/`Input_Choice_Node::
            // click_test()` (`nodes/Menu_Node.cxx`). Checked
            // unconditionally, same as the `Tabs` case just above and
            // matching FLTK's own sequencing (`click_test()` is
            // called before `drag`'s armed edge/corner-grab flag is
            // acted on, and resets it to 0 when it fires). Only fires
            // the *first* click, before the widget is `selected` --
            // matches FLTK's own `if (selected) return nullptr; //
            // let user move the widget` exactly, so a second click on an
            // already-selected menu widget drags/resizes it normally
            // instead of popping the menu up again.
            if (n !is null && !n.selected_)
            {
                Menu_ menu;
                if (auto ic = cast(InputChoice) hit)
                    menu = ic.menubutton();
                else
                    menu = cast(Menu_) hit;

                if (menu !is null)
                {
                    auto wn = cast(WidgetNode) n;
                    auto itemNodes = wn is null ? null : menuItemNodeMap(wn);
                    if (itemNodes.length > 0)
                    {
                        auto save = menu.mvalue();
                        menu.value(null);
                        fl.core.pushed(cast(Widget) menu);
                        (cast(Widget) menu).handle(Event.push);
                        fl.core.focus(null);

                        Node target = n;
                        auto picked = menu.mvalue();
                        if (picked !is null)
                        {
                            auto idx = menu.findIndex(picked);
                            if (idx >= 0 && idx < itemNodes.length && itemNodes[idx] !is null)
                                target = itemNodes[idx];
                        }
                        else
                        {
                            menu.value(save);
                        }

                        if (fl.core.eventShift())
                            selectRange(target);
                        else
                        {
                            selectOnly(target);
                            rangeAnchor_ = cast(WidgetNode) target;
                        }
                        if (onSelectionChanged !is null) onSelectionChanged(selected_);
                        redrawOverlay();
                        return 1;
                    }
                }
            }

            if (flag != dragNone)
            {
                beginDrag(flag, bx, by, br, bt, mx, my);
                return 1;
            }

            if (n is null)
            {
                // Empty-space press -- arms a rubber-band box-select
                // (FLTK's `FD_BOX`) instead of changing the
                // selection immediately. Matches FLTK's own timing
                // for this one case specifically: a *direct* widget hit
                // (below) still selects at push, unchanged, but an
                // empty-space press defers its effect on the selection
                // to release (`finishBoxSelect()`) -- including the
                // "clicked on nothing at all, box never grew" case,
                // which reproduces a plain empty-space click's "clear
                // the selection" behavior through that same release-time
                // path rather than a separate one.
                dragMode_ = dragBox;
                pushX_ = mx; pushY_ = my;
                boxX1_ = mx; boxY1_ = my;
                dragOrigins_ = [];
                return 1;
            }
            if (fl.core.eventCtrl())
                toggleSelection(n);
            else if (fl.core.eventShift())
                selectRange(n);
            else
            {
                selectOnly(n);
                rangeAnchor_ = cast(WidgetNode) n;
                // A plain click landing on a (now-selected) widget
                // also arms a move drag for this same press-drag
                // gesture -- see this module's own top comment on
                // why that's a deliberate simplification of
                // FLTK's own two-phase click/release timing.
                int bx2, by2, br2, bt2;
                selectionBounds(bx2, by2, br2, bt2);
                beginDrag(dragMove, bx2, by2, br2, bt2, mx, my);
            }
            if (onSelectionChanged !is null) onSelectionChanged(selected_);
            return 1;
        }
        else if (e == Event.drag && dragMode_ == dragBox)
        {
            // Kept entirely separate from the move/resize drag branch
            // below rather than folded in -- `dragOrigins_` is empty for
            // this mode (nothing is *moving*), and box-select has no use
            // for `applyDrag()`/snap-guide machinery at all, only its
            // own rectangle.
            boxX1_ = eventX();
            boxY1_ = eventY();
            redrawOverlay();
            return 1;
        }
        else if (e == Event.drag && dragMode_ != dragNone)
        {
            int mx = eventX(), my = eventY();
            int ddx = mx - pushX_;
            int ddy = my - pushY_;
            if (!(dragMode_ & (dragMove | dragLeft | dragRight)))
                ddx = 0;
            if (!(dragMode_ & (dragMove | dragTop | dragBottom)))
                ddy = 0;

            // Ported from `Window_Node::newdx()`'s own `if (Fluid.
            // show_guides && (drag & ...)) { ... Snap_Action::check_all
            // (data); if (data.x_dist < 4) mydx = data.dx_out; ... }` --
            // snaps the raw mouse delta to the closest matching guide
            // (window/group edge or margin, sibling alignment, or
            // ideal-size) *before* `applyDrag()` ever sees it, so a
            // drag that lands within 4px of a guide locks onto it
            // exactly rather than requiring pixel-perfect placement.
            lastSnapData_ = SnapData.init;
            SnapData data;
            bool haveGuideData = showGuides && dragMode_ != dragNone && dragOrigins_.length > 0;
            if (haveGuideData)
            {
                data.dx = ddx; data.dy = ddy;
                data.bx = dragBx_; data.by = dragBy_; data.br = dragBr_; data.bt = dragBt_;
                data.drag = dragMode_;
                data.wgt = live_.widgetOf.get(dragOrigins_[0].node, null);
                data.win = this;
                idealSizeFor(dragOrigins_[0].node.typeName, data.wgtIdealW, data.wgtIdealH);
                checkAll(data);
                if (data.xDist < 4) ddx = data.dxOut;
                if (data.yDist < 4) ddy = data.dyOut;
            }

            if (ddx != 0 || ddy != 0)
            {
                if (!dragMoved_)
                {
                    dragMoved_ = true;
                    if (onBeforeGeometryEdit !is null) onBeforeGeometryEdit();
                }
                applyDrag(ddx, ddy);
                // `applyDrag()` calls `Widget.resize()` directly, a bare
                // setter that never touches `damage()` (matching real
                // FLTK: geometry-only resize doesn't imply a redraw on
                // its own) -- so the dragged/resized widget's own pixels
                // need an explicit `redraw()` here, not just
                // `redrawOverlay()` (which -- correctly, by design --
                // only repaints the thin selection-rectangle layer, not
                // page content). Without this the widget would visibly stay
                // frozen at its pre-drag position/size while only the
                // selection outline tracks the cursor.
                redraw();
            }

            // `lastSnapData_` (fed to `drawAll()`
            // below, which is what `drawWidthHint()`/`drawHeightHint()`
            // read their `x`/`r`/`y`/`b` from) must NOT be built with
            // `bx`/`by`/`br`/`bt` copied from `dragBx_`/`dragBy_`/
            // `dragBr_`/`dragBt_` -- the *fixed*, drag-*start* bounding
            // box, correct for `checkAll()`'s own snap-distance math
            // above (matches FLTK's `newdx()`, which *also* feeds
            // `check_all()` the fixed `Window_Node::bx`/`by`/`br`/`bt`)
            // but wrong for drawing: `drawWidthHint(d.bx, d.bt+7,
            // d.br, ...)` computes the displayed number as `d.br -
            // d.bx`, so a fixed, never-updated `bx`/`br` would mean the
            // *drawn* width could only ever show the widget's size at
            // the moment the drag *began*, no matter how far it was
            // since dragged. FLTK avoids this because
            // `Window_Node::draw_overlay()` builds its *own*, separate
            // `Snap_Data` for `Snap_Action::draw_all()` -- reusing the
            // field names `bx`/`by`/`br`/`bt`, but populated from
            // `sx`/`sy`/`sr`/`st`, local variables *freshly recomputed
            // every single `draw_overlay()` call* from each selected
            // widget's own *current*, live `newposition()` -- not the
            // fixed values `check_all()` saw. Matched here by
            // recomputing the live selection bounding box (the same
            // `selectionBounds()` this file's own `Event.push`/
            // `beginDrag()` already use, just called again now that
            // `applyDrag()` above has actually moved/resized the live
            // widget) right before building `lastSnapData_`, instead of
            // reusing the stale drag-start box.
            if (haveGuideData)
            {
                int lbx, lby, lbr, lbt;
                if (selectionBounds(lbx, lby, lbr, lbt))
                {
                    data.bx = lbx; data.by = lby; data.br = lbr; data.bt = lbt;
                }
                // Carried over from the previous fix on this same
                // struct: `matches()` compares against the *final*,
                // post-snap delta, not the pre-snap value `checkAll()`
                // itself consumed.
                data.dx = ddx;
                data.dy = ddy;
                lastSnapData_ = data;
            }

            // `redrawOverlay()` must run unconditionally here, not
            // gated on the *post-snap* delta being nonzero (`ddx != 0
            // || ddy != 0`): the whole point of a
            // successful snap is often that the delta becomes exactly
            // zero (dragged right onto the guide) -- exactly the
            // moment the guide should be most visible, so gating on a
            // nonzero delta would skip the repaint that shows it.
            // FLTK's own `Window_Node::newdx()` avoids this by
            // comparing the new `dx`/`dy` against the *previous*
            // frame's stored value (`if (dx != mydx || dy != mydy)`),
            // not against zero -- functionally equivalent to just
            // calling `redraw_overlay()` on every drag event
            // unconditionally, which is what this does: the
            // overlay itself is a cheap, small-clip repaint (unlike
            // `redraw()`/`applyDrag()` above, correctly still gated --
            // no reason to redraw a widget's own *content* when it
            // hasn't actually moved), so there's no real cost to
            // keeping it unconditional rather than reconstructing
            // FLTK's exact previous-frame comparison.
            redrawOverlay();
            return 1;
        }
        else if (e == Event.release && dragMode_ == dragBox)
        {
            finishBoxSelect(fl.core.eventShift());
            dragMode_ = dragNone;
            redrawOverlay();
            return 1;
        }
        else if (e == Event.release && dragMode_ != dragNone)
        {
            if (dragMoved_)
            {
                commitDragGeometry();
            }
            else if (fl.core.eventClicks() && onOpenRequested !is null)
            {
                // Ported from `Window_Node::handle()`'s own `FL_RELEASE`
                // case: `(Fl::event_clicks() || Fl::event_state(FL_
                // CTRL))` -> `Widget_Node::open()`. Deliberately
                // double-click *only* here, not also Ctrl -- Ctrl-click
                // is already this port's own toggle-selection modifier
                // (`Event.push`'s own `eventCtrl() || eventShift()`
                // check just above, and this module's own top comment on
                // why both do the same thing here), so reusing it for
                // "open" too would collide with an existing, deliberate,
                // already-shipped behavior instead of adding a new one.
                auto n = primarySelection();
                if (n !is null) onOpenRequested(n);
            }
            else
            {
                // Ported from `Window_Node::handle()`'s own `FL_RELEASE`
                // case: when the press never actually moved the mouse
                // (`dx==0 && dy==0 && Fl::event_is_click()`), FLTK
                // falls all the way through to a *fresh* innermost-widget
                // rescan at the click point and reselects whatever it
                // finds there, rather than leaving the pre-press
                // selection in place. `Event.push` above only *arms* a
                // tentative move/resize drag when the click lands inside
                // the current selection's bounding box (`flag != dragNone`
                // at line ~1245) -- it never re-resolves what's actually
                // under the cursor in that case, so without this branch a
                // second click anywhere inside an already-selected
                // Group's interior would just re-confirm the Group forever and
                // never drill down into a nested child.
                auto hit = hitTest(this, pushX_, pushY_);
                Node n = hit is null ? null : live_.nodeOf.get(hit, null);
                if (n !is null)
                {
                    if (fl.core.eventCtrl())
                        toggleSelection(n);
                    else if (fl.core.eventShift())
                        selectRange(n);
                    else
                    {
                        selectOnly(n);
                        rangeAnchor_ = cast(WidgetNode) n;
                    }
                    if (onSelectionChanged !is null) onSelectionChanged(selected_);
                }
            }
            dragMode_ = dragNone;
            dragOrigins_ = [];
            // `lastSnapData_` must be reset here, at the end of this
            // drag, not only at the *start* of the
            // next `Event.drag`: otherwise the winning snap guide's widget reference (`bestMatch`,
            // cached on the module-level `SnapAction` instances in
            // `fluid.snap_action`, keyed off this same `SnapData`'s own
            // `matches()` check) would survive indefinitely past this drag's
            // own completion. `drawOverlay()` unconditionally re-runs
            // `drawAll(lastSnapData_)` on *every* overlay repaint, drag
            // or not -- so if that referenced widget were later destroyed
            // by anything else entirely (Delete, Cut, Group/Ungroup, ...)
            // before another drag ever started, the very next
            // repaint (any click, any menu command) would dereference a
            // dangling `Widget` and crash: drag a widget once, then
            // Ungroup something else entirely, then click, with no new drag
            // in between to naturally clear it. Matches the guide's own
            // real-world lifetime too: it should only ever be visible
            // *during* an active drag, not linger forever after release.
            lastSnapData_ = SnapData.init;
            redraw();
            redrawOverlay();
            return 1;
        }
        else if (e == Event.keyDown)
        {
            auto key = fl.core.eventKey();

            if ((key == deleteKey || key == backSpace) && selected_.length && onDeleteRequested !is null)
            {
                onDeleteRequested();
                return 1;
            }

            // Arrow-key nudge, ported from `Window_Node::handle()`'s own
            // `FL_KEYBOARD`/`ARROW:` case -- Shift resizes (grows/shrinks
            // the bottom-right corner) instead of moving, matching
            // FLTK's own `drag = event_state(FL_SHIFT) ? (FD_RIGHT|
            // FD_BOTTOM) : FD_DRAG` exactly. Ctrl/Cmd steps by the
            // project's own move/resize snap-grid size (`fluid.snap_
            // action.getMoveStepsize()`/`getResizeStepsize()`, the same
            // ones a mouse-drag already snaps to) instead of 1px, ported
            // from FLTK's own `Fl::event_state(FL_COMMAND)` check.
            // Reuses `beginDrag()`/`applyDrag()` (the same machinery a
            // real mouse-drag uses) rather than duplicating the edge-
            // clamping math -- matches FLTK's own reuse of `newdx()`
            // via `moveallchildren(Fl::event_key())` for this same case.
            int ndx, ndy;
            bool isArrow = true;
            switch (key)
            {
                case left:  ndx = -1; break;
                case right: ndx = +1; break;
                case up:    ndy = -1; break;
                case down:  ndy = +1; break;
                default: isArrow = false; break;
            }
            if (isArrow && selected_.length)
            {
                int sbx, sby, sbr, sbt;
                if (selectionBounds(sbx, sby, sbr, sbt))
                {
                    int step = 1;
                    if (fl.core.eventState() & stateCommand)
                    {
                        int xStep, yStep;
                        if (fl.core.eventShift())
                            getResizeStepsize(xStep, yStep);
                        else
                            getMoveStepsize(xStep, yStep);
                        step = ndx != 0 ? xStep : yStep;
                    }

                    DragFlag flag = fl.core.eventShift() ? (dragRight | dragBottom) : dragMove;
                    beginDrag(flag, sbx, sby, sbr, sbt, eventX(), eventY());
                    if (dragOrigins_.length)
                    {
                        if (onBeforeGeometryEdit !is null) onBeforeGeometryEdit();
                        applyDrag(ndx * step, ndy * step);
                        redraw();
                        commitDragGeometry();
                        redrawOverlay();
                    }
                    dragMode_ = dragNone;
                    dragOrigins_ = [];
                }
                return 1;
            }

            // Tab/Shift+Tab cycles the *editor's* selection to the
            // next/previous widget in the design -- ported in spirit
            // from `Window_Node::handle()`'s own `FL_Tab` case, which
            // walks FLTK's flat doubly-linked `Node` list; this
            // port's real tree has no such flat chain, so this walks a
            // fresh pre-order flatten of the whole design instead
            // (`flattenWidgets()`) -- same effect (visit every widget in
            // the design, cycling, wrapping at the ends), not a
            // byte-for-byte port of the traversal itself. **Must
            // `return 1` unconditionally once this case is reached** --
            // falling through to `super.handle(e)` would hand Tab to
            // `FlGroup.navigation()` instead, which cycles *keyboard
            // input* focus among the design's own live widgets (a
            // completely different, pre-existing behavior this would
            // otherwise silently break).
            if (key == tab)
            {
                auto flat = flattenWidgets(root_);
                if (flat.length)
                {
                    import std.algorithm : countUntil;

                    auto idx = flat.countUntil(cast(WidgetNode) primarySelection());
                    int nextIdx;
                    if (idx < 0)
                        nextIdx = 0;
                    else if (fl.core.eventShift())
                        nextIdx = cast(int)((idx - 1 + flat.length) % flat.length);
                    else
                        nextIdx = cast(int)((idx + 1) % flat.length);
                    selectOnly(flat[nextIdx]);
                    if (onSelectionChanged !is null) onSelectionChanged(selected_);
                }
                return 1;
            }

            // Escape hides the design window -- ported from `Window_
            // Node::handle()`'s own `FL_Escape` case (`((Fl_Window*)o)->
            // hide()`). Safe to hide unconditionally: `openNode()` has a
            // real reopen path
            // (double-clicking the window's
            // own row in the project browser re-shows it, see
            // `gui_main.d`'s "Reopening a closed project window" note).
            if (key == escape)
            {
                hide();
                return 1;
            }
        }
        else if (e == Event.dndEnter || e == Event.dndDrag)
        {
            auto hit = hitTest(this, eventX(), eventY());
            Node n = hit is null ? null : live_.nodeOf.get(hit, null);
            while (n !is null && !n.canHaveChildren())
                n = n.parent;
            if (n is null) n = root_;
            if (n !is dndTarget_)
            {
                dndTarget_ = n;
                selectOnly(n);
                if (onSelectionChanged !is null) onSelectionChanged(selected_);
            }
            fl.core.belowmouse(this);
            return 1;
        }
        else if (e == Event.dndRelease)
        {
            fl.core.belowmouse(this);
            return 1;
        }
        else if (e == Event.paste)
        {
            if (dndTarget_ !is null)
            {
                string text = fl.core.eventText();
                string imgPath = imageDropPath(text);
                if (imgPath.length && onImageDropped !is null)
                {
                    // Deliberately *not* `dndTarget_` here -- that field
                    // is walked up to the nearest *container* (see
                    // `Event.dndEnter`/`dndDrag` just above), correct
                    // for a widget-bin drop (which needs to know what to
                    // insert *into*) but wrong for an image drop, which
                    // FLTK targets at the deepest specific widget
                    // under the cursor (`Window_Node::handle()`'s own
                    // `FL_PASTE` loop: `if (Fl::event_inside(myo->o) &&
                    // ...) tgt = myo;`, no container-walk at all) -- a
                    // fresh `hitTest()` matches that directly.
                    auto hitW = hitTest(this, eventX(), eventY());
                    Node hitN = hitW is null ? null : live_.nodeOf.get(hitW, null);
                    if (hitN !is null)
                    {
                        // Ported from `Window_Node::handle()`'s own
                        // `FL_PASTE` case: `Fl::get_key(FL_Alt_L) ||
                        // Fl::get_key(FL_Alt_R)` -- a direct keyboard-
                        // state query, kept verbatim rather than
                        // `eventState() & stateAlt`, matching FLTK's
                        // own comment on *why*: "X11/Wayland does not
                        // set the e_state on DND events".
                        bool inactive = fl.core.getKey(altL) || fl.core.getKey(altR);
                        onImageDropped(imgPath, hitN, inactive);
                    }
                }
                else if (onWidgetDropped !is null)
                    onWidgetDropped(text, dndTarget_, eventX(), eventY());
            }
            dndTarget_ = null;
            return 1;
        }
        return super.handle(e);
    }

    /// Distinguishes an external image-file drop from a widget-bin
    /// type-name drop by checking whether the dropped text names a
    /// real, existing file. FLTK disambiguates the other direction
    /// (`typename_to_prototype()`: is this a recognized FLUID type
    /// name?) -- this port's own type registry
    /// (`fluid.instantiate`'s `registry` AA) has no public query
    /// exposed to check that here, so this checks the direction that's
    /// actually reachable instead: a widget-bin type name like
    /// "Button"/"Fl_Window" is never coincidentally also a path to a
    /// file that exists on disk, so "does this name a real file" is an
    /// equally reliable signal in practice. Strips a `scheme://` prefix
    /// and trailing CR/LF the same way FLTK's own `FL_PASTE` case
    /// does. **Does not** decode `%XX` URI escapes (`fl_decode_uri()`,
    /// FLTK's next step on X11/Wayland) -- `fl.filename` doesn't
    /// have that function ported yet (a real, documented,
    /// narrower-than-FLTK gap, not silently dropped: see that
    /// module's own row in `PORTING.md`), so a dropped file whose path
    /// needs URI-decoding (uncommon: only paths containing characters a
    /// URI must escape, e.g. spaces as `%20`) won't be recognized here.
    /// Returns `""` if `text` isn't a droppable file.
    private static string imageDropPath(string text)
    {
        import std.file : exists;
        import std.string : indexOf;

        if (text.length == 0) return "";
        string fn = text;
        auto sep = fn.indexOf("://");
        if (sep >= 0) fn = fn[sep + 3 .. $];
        while (fn.length && (fn[$ - 1] == '\n' || fn[$ - 1] == '\r'))
            fn = fn[0 .. $ - 1];
        return fn.length && exists(fn) ? fn : "";
    }

    /// Deepest live widget under `(px, py)` (window-local coordinates
    /// -- every non-subwindow descendant's `x()`/`y()` is already in
    /// this same coordinate space, matching real FLTK's own "relative
    /// to the enclosing window, not the immediate parent group"
    /// widget-coordinate convention; Phase 1 never instantiates a
    /// nested window, so that convention's one exception never
    /// applies here). Children are checked back-to-front (highest
    /// index -- normally the most recently added, so visually on top
    /// -- first) so an overlapping pair resolves to whichever one a
    /// user would actually see under the cursor.
    private static Widget hitTest(FlGroup g, int px, int py)
    {
        for (int i = g.children() - 1; i >= 0; i--)
        {
            auto c = g.child(i);
            // Matches FLTK's own ancestor-chain visibility walk
            // (`for (Fl_Widget *o1 = myo->o; o1; o1 = o1->parent()) if
            // (!o1->visible()) goto CONTINUE2;`) -- a single per-level
            // check here has the same effect, since a hidden child is
            // never recursed into, so its own hidden-or-not descendants
            // never get considered either. Without this, a `Tabs`/
            // `Wizard` page not currently showing (or any node with its
            // own `hide` property set) could still be hit-tested and
            // selected/dropped-onto from underneath its visible sibling,
            // since children are walked back-to-front by pure geometry
            // with no visibility filter at all.
            if (!c.visible()) continue;
            if (!(px >= c.x() && px < c.x() + c.w() && py >= c.y() && py < c.y() + c.h()))
                continue;
            if (auto cg = cast(FlGroup) c)
            {
                auto deeper = hitTest(cg, px, py);
                if (deeper !is null) return deeper;
            }
            return c;
        }
        return null;
    }
}

unittest
{
    // Regression coverage for rubber-band box-select and
    // double-click-to-open, both ported
    // from `Window_Node::handle()` -- driven via `fl.core`'s own
    // public `eventX(int)`/`eventY(int)`/`eventClicks(int)` setters,
    // the only event-state mutators reachable from outside package `fl`
    // at all: `eKeysym_`/`eState_` are `package(fl)`-scoped, so the
    // *keyboard*-driven features added in the same pass (arrow-key
    // nudge, Tab/Shift+Tab, Escape) have no headless test here and rely
    // on the user's own interactive confirmation instead -- the same
    // position this file's pre-existing Delete/Backspace handling has
    // always been in (this module had zero unittest blocks before this
    // one).
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto win = new WindowNode();
    win.typeName = "Window";
    win.x = 0; win.y = 0; win.w = 200; win.h = 200;
    win.hasXywh = true;

    auto btn1 = new WidgetNode();
    btn1.typeName = "Button";
    btn1.x = 10; btn1.y = 10; btn1.w = 50; btn1.h = 20;
    btn1.hasXywh = true;
    win.addChild(btn1);

    auto btn2 = new WidgetNode();
    btn2.typeName = "Button";
    btn2.x = 10; btn2.y = 40; btn2.w = 50; btn2.h = 20;
    btn2.hasXywh = true;
    win.addChild(btn2);

    auto canvas = new ProjectCanvas(win);

    // Box-select: press on empty space, drag to enclose both buttons,
    // release -- both end up selected.
    fl.core.eventX(0); fl.core.eventY(0);
    assert(canvas.handle(Event.push) == 1);
    fl.core.eventX(100); fl.core.eventY(100);
    assert(canvas.handle(Event.drag) == 1);
    assert(canvas.handle(Event.release) == 1);
    assert(canvas.isSelected(btn1));
    assert(canvas.isSelected(btn2));

    // A plain click on empty space (a box that never grew past a single
    // point, no `Event.drag` in between) clears the selection -- the
    // same release-time path as a real box-select, not a separate one.
    fl.core.eventX(150); fl.core.eventY(150);
    assert(canvas.handle(Event.push) == 1);
    assert(canvas.handle(Event.release) == 1);
    assert(!canvas.isSelected(btn1));
    assert(!canvas.isSelected(btn2));

    // Double-click-to-open: click btn1 (selects it and arms a move drag,
    // this port's own established simplification), release immediately
    // -- no `Event.drag` in between, so `dragMoved_` stays false -- with
    // `eventClicks()` reporting a double-click. Should fire
    // `onOpenRequested`, not commit any geometry change.
    Node opened;
    canvas.onOpenRequested = (n) { opened = n; };
    fl.core.eventX(20); fl.core.eventY(15);
    assert(canvas.handle(Event.push) == 1);
    assert(canvas.isSelected(btn1));
    fl.core.eventClicks(1);
    assert(canvas.handle(Event.release) == 1);
    assert(opened is btn1);

    fl.core.eventX(0); fl.core.eventY(0); fl.core.eventClicks(0);
}

unittest
{
    // Regression coverage for the Shift-click range-select / Ctrl-click
    // toggle split (see `toggleSelection()`'s own
    // doc comment). Exercises `toggleSelection()`/`selectRange()`
    // directly rather than through `handle(Event.push)` -- `eState_` (the
    // field `eventCtrl()`/`eventShift()` read) is `package(fl)`-scoped,
    // so simulating a specific modifier held during a click isn't
    // reachable from this package's own tests at all, the same
    // constraint the box-select/double-click tests above already ran
    // into for keyboard state.
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto win = new WindowNode();
    win.typeName = "Window";
    win.x = 0; win.y = 0; win.w = 200; win.h = 200;
    win.hasXywh = true;

    auto btn1 = new WidgetNode();
    btn1.typeName = "Button";
    btn1.x = 10; btn1.y = 10; btn1.w = 50; btn1.h = 20;
    btn1.hasXywh = true;
    win.addChild(btn1);

    auto btn2 = new WidgetNode();
    btn2.typeName = "Button";
    btn2.x = 10; btn2.y = 40; btn2.w = 50; btn2.h = 20;
    btn2.hasXywh = true;
    win.addChild(btn2);

    auto btn3 = new WidgetNode();
    btn3.typeName = "Button";
    btn3.x = 10; btn3.y = 70; btn3.w = 50; btn3.h = 20;
    btn3.hasXywh = true;
    win.addChild(btn3);

    auto canvas = new ProjectCanvas(win);

    // Ctrl-click (toggleSelection): adds, then removes, one widget at a
    // time -- unaffected by any other widget's own selection state.
    canvas.toggleSelection(btn1);
    assert(canvas.isSelected(btn1));
    canvas.toggleSelection(btn1);
    assert(!canvas.isSelected(btn1));

    // Shift-click with no prior anchor: degrades to a plain single
    // select and adopts the target as the new anchor.
    canvas.selectRange(btn2);
    assert(canvas.isSelected(btn2));
    assert(!canvas.isSelected(btn1) && !canvas.isSelected(btn3));

    // A plain click (`selectOnly()` + explicit anchor assignment, the
    // same pairing `handle()`'s own push case does) sets a fresh
    // anchor; a following Shift-click range-selects from *that* anchor
    // through the target, inclusive, replacing whatever was selected
    // before -- not toggling, not accumulating.
    canvas.selectOnly(btn1);
    canvas.rangeAnchor_ = btn1;
    canvas.selectRange(btn3);
    assert(canvas.isSelected(btn1) && canvas.isSelected(btn2) && canvas.isSelected(btn3));

    // A second Shift-click with a different target recomputes the range
    // from the *same* anchor (btn1), it doesn't extend from btn3 --
    // the "Explorer/Finder" shape, not a cumulative one.
    canvas.selectRange(btn2);
    assert(canvas.isSelected(btn1) && canvas.isSelected(btn2) && !canvas.isSelected(btn3));
}
