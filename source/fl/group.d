/*
 * Ported from FL/Fl_Group.H + src/Fl_Group.cxx (FLTK 1.5.0,
 * ~/Repositories/fltk).
 *
 * `Fl_Group` is ported as `FlGroup`, not `Group` -- one of two deliberate
 * exceptions to this port's usual "drop the `Fl_`/`Fl` prefix" naming
 * convention (see `CLAUDE.md`'s "Porting conventions" section), because
 * a bare `Group` collides with `std.algorithm.iteration.Group` the
 * moment generated code (which does a wildcard `import fl; import
 * std;`) names one. `fl.clock.Clock` got the same treatment for the
 * same reason
 * (`std.datetime.systime.Clock`) -- see that module's own doc comment.
 *
 * Faithfully ported: the container/child-management surface (add,
 * insert, remove, clear, deleteChild, find, array, children/child,
 * the onInsert/onMove/onRemove hooks), resizable()/addResizable(),
 * clipChildren(), initSizes()/bounds(), the real resize() layout
 * algorithm, current()/begin()/end(), and the constructor/destructor
 * (including FLTK's "destroying a group destroys its children"
 * behavior).
 *
 * draw()/drawChildren()/drawChild()/updateChild()/drawOutsideLabel() are
 * structurally ported (same branching, same iteration) and draw real
 * pixels/text via fl.widget's drawBox()/drawLabel() (both real), with
 * clipChildren()'s pushClip()/popClip() calls real too -- a FlGroup
 * with clipChildren() set actually confines its children to its own
 * bounds. drawFocus() is real too -- see fl.widget's drawFocus().
 *
 * handle(int)/navigation(int) are now ported too, backed by the
 * event-state subsystem in fl.core (event_key()/event_state()/
 * belowmouse()/pushed()/event_inside(), plus focus()'s new oldFocus()
 * tracking). The private send()/navkey() helpers Fl_Group.cxx declares
 * as file-local statics (not part of FL/Fl_Group.H's public surface)
 * are ported the same way, as private module-level functions here.
 * FL_PUSH's Fl_Widget_Tracker safety net (checks a child widget wasn't
 * destroyed by its own FL_PUSH handler/callback before touching it
 * again) is ported now too, via fl.widget_tracker.WidgetTracker -- see
 * that module's comment for why it needed a real D-appropriate
 * redesign rather than a straight translation.
 *
 * Deliberately not ported:
 *  - sizes()/sizes_: the pre-1.4 (int quad) compatibility array.
 *    FLTK's own doc says it "will be removed in a future FLTK
 *    version (1.5.0 or higher)" -- we're 1.5.0, so it's simply not
 *    ported; bounds() (the Fl_Rect-based replacement) is.
 *  - _ddfdesign_kludge()/forms_end(): Forms-compatibility back-compat,
 *    out of scope (see FL/forms.H in PORTING.md).
 *  - Fl_End: a C++-only trick for closing a group from inside a
 *    constructor's member-initializer list, needed because C++
 *    constructors can't contain arbitrary statements before the member
 *    list finishes. D constructors are ordinary function bodies, so
 *    `group.end();` as a plain statement already does the job.
 */
module fl.group;

import core.memory : GC;

import fl.enumerations;
import fl.rect : Rect;
import fl.widget;
import fl.widget_tracker : WidgetTracker;
import fl.window : Window;
import fl.draw;
import fl.core;

/**
 * File-local helper in src/Fl_Group.cxx (not declared in FL/Fl_Group.H),
 * used throughout handle(): forwards event to o, translating e_x/e_y
 * into o's coordinate space first if o is a window (for back-compatible
 * subwindow support), and updating belowmouse() on a successful
 * FL_ENTER/FL_DND_ENTER.
 */
private int send(Widget o, Event event)
{
    if (o.asWindow() is null) return o.handle(event);

    if (event == Event.dndEnter || event == Event.dndDrag)
        event = o.contains(fl.core.belowmouse()) ? Event.dndDrag : Event.dndEnter;

    int savedX = fl.core.eX_; fl.core.eX_ -= o.x;
    int savedY = fl.core.eY_; fl.core.eY_ -= o.y;
    int ret = o.handle(event);
    fl.core.eY_ = savedY;
    fl.core.eX_ = savedX;

    if (event == Event.enter || event == Event.dndEnter)
        if (!o.contains(fl.core.belowmouse())) fl.core.belowmouse(o);

    return ret;
}

/// File-local helper in src/Fl_Group.cxx: translates the current
/// keystroke into a navigation direction (left/right/up/down), or 0 if
/// the current event isn't a navigation keystroke. Tab (or shift-Tab)
/// is treated as right (or left); ctrl/alt/meta are left alone so the
/// app can still use ctrl/alt-modified keys as its own hotkeys.
private Keysym navkey()
{
    if (fl.core.eventState(stateCtrl | stateAlt | stateMeta) != 0) return 0;

    switch (fl.core.eventKey())
    {
    case tab:
        return fl.core.eventState(stateShift) != 0 ? left : right;
    case right:
        return right;
    case left:
        return left;
    case up:
        return up;
    case down:
        return down;
    default:
        return 0;
    }
}

class FlGroup : Widget
{
    private static FlGroup current_;

    private
    {
        Widget[] child_;
        Widget savedfocus_;
        Widget resizable_;
        Rect[] bounds_;
    }

    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        alignment(alignTop);
        savedfocus_ = null;
        resizable_ = this;
        bounds_ = null;

        // Subclasses may want to construct child widgets as part of
        // their own constructor; begin() makes sure they get add()'d to
        // this group. Callers must end() the group themselves.
        begin();
    }

    ~this()
    {
        // See fl.widget's ~this() for why cross-object work is guarded
        // like this: touching other GC-managed objects (our children)
        // is only safe when this destructor runs deterministically.
        if (!GC.inFinalizer())
        {
            if (current_ is this)
                end();
            clear();
        }
    }

    /// The group new widgets are auto-added to; see fl.widget's ctor.
    static FlGroup current() { return current_; }
    static void current(FlGroup g) { current_ = g; }

    /// Makes this the current() group: subsequently constructed widgets
    /// are auto-added to it until end() is called.
    void begin() { current_ = this; }

    /// Same as current(this.parent), so widget construction resumes
    /// adding to the enclosing group. The cast is always safe: a real
    /// FlGroup's own parent is always itself a FlGroup or null, by
    /// construction (only an exotic composed-child relationship --
    /// see Widget.parent()'s own doc comment -- ever has a non-FlGroup
    /// parent, and that's never a FlGroup itself).
    void end() { current_ = cast(FlGroup) parent; }

    override int handle(Event event)
    {
        switch (event)
        {
        case Event.focus:
        {
            // Mirrors FLTK's `switch (navkey()) { default: ...
            // /*FALLTHROUGH*/ case FL_Right: case FL_Down: ... }` --
            // when the event isn't a navigation keystroke (navkey()==0,
            // e.g. focus assigned programmatically, or reached here at
            // a moment when the last real key event was something else
            // entirely, such as Enter committing a table cell edit),
            // FLTK tries savedfocus_ first but, if that fails,
            // deliberately falls through into the same forward-order
            // child scan FL_Right/FL_Down uses -- it does NOT give up.
            // Returning 0 directly instead of falling through breaks
            // re-deriving focus after fl.core.throwFocus() calls
            // takeFocus() on a top-level window outside of an actual
            // arrow-key/Tab keystroke (see fl.core.throwFocus()'s own
            // doc comment).
            Keysym nk = navkey();
            if (nk == left || nk == up)
            {
                foreach_reverse (o; rawArray())
                    if (o.takeFocus()) return 1;
                return 0;
            }
            if (nk != right && nk != down)
            {
                if (savedfocus_ !is null && savedfocus_.takeFocus()) return 1;
                // fall through to the forward scan below
            }
            foreach (o; rawArray())
                if (o.takeFocus()) return 1;
            return 0;
        }

        case Event.unfocus:
            savedfocus_ = fl.core.oldFocus();
            return 0;

        case Event.keyDown: // aka FL_KEYBOARD; see fl.enumerations.keyboard
            return navigation(navkey());

        case Event.shortcut:
            foreach_reverse (o; rawArray())
                if (o.takesEvents() && fl.core.eventInside(o) && send(o, Event.shortcut))
                    return 1;
            foreach_reverse (o; rawArray())
                if (o.takesEvents() && !fl.core.eventInside(o) && send(o, Event.shortcut))
                    return 1;
            if (fl.core.eventKey() == enter || fl.core.eventKey() == kpEnter)
                return navigation(down);
            return 0;

        case Event.enter:
        case Event.move:
            foreach_reverse (o; rawArray())
            {
                if (o.visible() && fl.core.eventInside(o))
                {
                    if (o.contains(fl.core.belowmouse()))
                        return send(o, Event.move);
                    fl.core.belowmouse(o);
                    if (send(o, Event.enter)) return 1;
                }
            }
            fl.core.belowmouse(this);
            return 1;

        case Event.dndEnter:
        case Event.dndDrag:
            foreach_reverse (o; rawArray())
            {
                if (o.takesEvents() && fl.core.eventInside(o))
                {
                    if (o.contains(fl.core.belowmouse()))
                        return send(o, Event.dndDrag);
                    else if (send(o, Event.dndEnter))
                    {
                        if (!o.contains(fl.core.belowmouse())) fl.core.belowmouse(o);
                        return 1;
                    }
                }
            }
            fl.core.belowmouse(this);
            return 0;

        case Event.push:
            foreach_reverse (o; rawArray())
            {
                if (o.takesEvents() && fl.core.eventInside(o))
                {
                    auto wp = WidgetTracker(o);
                    if (send(o, Event.push))
                    {
                        if (fl.core.pushed() !is null && wp.exists() && !o.contains(fl.core.pushed()))
                            fl.core.pushed(o);
                        return 1;
                    }
                }
            }
            return 0;

        case Event.release:
        case Event.drag:
        {
            Widget o = fl.core.pushed();
            if (o is this) return 0;
            if (o !is null) return send(o, event) != 0;
            foreach_reverse (c; rawArray())
                if (c.takesEvents() && fl.core.eventInside(c) && send(c, event))
                    return 1;
            return 0;
        }

        case Event.mouseWheel:
            foreach_reverse (o; rawArray())
                if (o.takesEvents() && fl.core.eventInside(o) && send(o, Event.mouseWheel))
                    return 1;
            foreach_reverse (o; rawArray())
                if (o.takesEvents() && !fl.core.eventInside(o) && send(o, Event.mouseWheel))
                    return 1;
            return 0;

        case Event.deactivate:
        case Event.activate:
            foreach (o; rawArray())
                if (o.active()) o.handle(event);
            return 1;

        case Event.show:
        case Event.hide:
            foreach (o; rawArray())
            {
                if (event == Event.hide && o is fl.core.focus())
                {
                    auto savedEvent = fl.core.eNumber_;
                    fl.core.eNumber_ = Event.unfocus;
                    o.handle(Event.unfocus);
                    fl.core.eNumber_ = savedEvent;
                    fl.core.focus(null);
                }
                if (o.visible()) o.handle(event);
            }
            return 1;

        default:
            // For all other events, try each child in turn, starting at
            // whichever one currently has focus.
            auto a = rawArray();
            int i = 0;
            for (; i < rawChildren; i++)
                if (fl.core.focus() is a[i]) break;
            if (i >= rawChildren) i = 0;

            if (rawChildren > 0)
            {
                int j = i;
                for (;;)
                {
                    if (a[j].takesEvents() && send(a[j], event)) return 1;
                    j++;
                    if (j >= rawChildren) j = 0;
                    if (j == i) break;
                }
            }
            return 0;
        }
    }

    /// Tries to move the keyboard focus in response to a navigation
    /// keystroke (key is one of fl.enumerations' left/right/up/down, or
    /// 0 for "not a navigation key", as returned by navkey()).
    private int navigation(Keysym key)
    {
        if (rawChildren <= 1) return 0;

        auto a = rawArray();
        int i;
        for (i = 0; ; i++)
        {
            if (i >= rawChildren) return 0;
            if (a[i].contains(fl.core.focus())) break;
        }
        Widget previous = a[i];

        for (;;)
        {
            switch (key)
            {
            case right:
            case down:
                i++;
                if (i >= rawChildren)
                {
                    if (parent !is null) return 0;
                    i = 0;
                }
                break;
            case left:
            case up:
                if (i) i--;
                else
                {
                    if (parent !is null) return 0;
                    i = rawChildren - 1;
                }
                break;
            default:
                return 0;
            }

            Widget o = a[i];
            if (o is previous) return 0;

            if (key == down || key == up)
            {
                // For up/down, the widgets have to overlap horizontally.
                if (o.x >= previous.x + previous.w || o.x + o.w <= previous.x)
                    continue;
            }
            if (o.takeFocus()) return 1;
        }
    }

    int children() const { return cast(int) child_.length; }

    /**
     * The group's own real, structural child list/count -- deliberately
     * `final` (never overridable), unlike the public `array()`/
     * `children()` just above. Matches FLTK's actual semantics:
     * `Fl_Group::array()`/`children()` are declared *without* `virtual`
     * in `FL/Fl_Group.H`, so a subclass like `Fl_Table` "hides" them
     * (C++ name hiding) only for *external* callers holding an
     * `Fl_Table*`-typed reference -- `Fl_Group`'s own internal code
     * (`draw_children()`, `handle()`, `navigation()`, `resize()`,
     * `bounds()`) is compiled once, calling the non-virtual base
     * version regardless of the object's real dynamic type, so it
     * always sees the true structural list. D methods are virtual by
     * default, so a naive port of a subclass's override (see
     * `fl.table.Table.array()`/`children()`, which redirects to
     * `table_`'s own children for external callers' convenience) would
     * *also* silently redirect every one of `FlGroup`'s own internal
     * call sites below: `drawChildren()`/`handle()`/`resize()` would
     * never reach `fl.table`'s real `vscrollbar_`/`hscrollbar_`/
     * `table_` at all, only `table_`'s own leftover, never-repositioned
     * internal `Fl_Scroll` scrollbar widgets, since those are what
     * `Table.array()` substitutes in. Every internal call site in this
     * module calls these non-virtual accessors instead, restoring
     * FLTK's real behavior.
     */
    private final inout(Widget)[] rawArray() inout { return child_; }
    private final int rawChildren() const { return cast(int) child_.length; } // ditto

    /// Returns null if n is out of range.
    inout(Widget) child(int n) inout
    {
        if (n < 0 || n > rawChildren - 1) return null;
        return child_[n];
    }

    /// Returns children() if o is null or not found.
    int find(const(Widget) o) const
    {
        int i;
        for (i = 0; i < rawChildren; i++)
            if (child_[i] is o) break;
        return i;
    }

    /// Valid only until the next add()/insert()/remove() on this group.
    inout(Widget)[] array() inout { return child_; }

    /**
     * The widget is removed from its current group (if any) and then
     * inserted into this group at index (or appended, if index >=
     * children()). Can also be used to rearrange widgets within a group.
     */
    void insert(Widget o, int index)
    {
        // A non-null but non-FlGroup parent (a composed-but-not-tree-
        // managed child relationship -- see Widget.parent()'s own doc
        // comment) has no FlGroup child-list to detach from; just fall
        // through to inserting into `this` below, which overwrites
        // o.parent(this) regardless. In normal use `o` always either
        // has no parent yet or a real FlGroup one, from a previous
        // ordinary insert()/add() -- this cast only ever fails for the
        // exotic composed-child case, which never goes through
        // insert()/add() at all in practice.
        if (auto g = cast(FlGroup) o.parent)
        {
            int n = g.find(o);
            if (g is this)
            {
                // Moving a widget within this group: avoid the more
                // expensive remove()+add().
                index = onMove(n, index);
                if (index < 0) return;
                if (index > children) index = children;
                if (index > n) index--; // compensate for removal+reinsertion
                if (index == n) return; // same position

                if (index > n)
                {
                    for (int j = n; j < index; j++)
                        child_[j] = child_[j + 1];
                }
                else
                {
                    for (int j = n; j > index; j--)
                        child_[j] = child_[j - 1];
                }
                child_[index] = o;
                initSizes();
                return;
            }
            g.remove(n);
        }

        index = onInsert(o, index);
        if (index == -1) return;
        if (index >= children)
            child_ ~= o;
        else
            child_ = child_[0 .. index] ~ o ~ child_[index .. $];
        o.parent(this);
        initSizes();
    }

    /// insert(o, find(before)); appends if before is not in the group.
    void insert(Widget o, Widget before) { insert(o, find(before)); }

    /// The widget is removed from its current group (if any) and added
    /// to the end of this group.
    void add(Widget o) { insert(o, children); }

    /// Removes the widget at index from the group without deleting it.
    /// Does nothing if index is out of bounds.
    void remove(int index)
    {
        if (index < 0 || index >= children) return;
        onRemove(index); // notify subclass
        if (index >= children) return; // subclass may have removed it already

        Widget o = child(index);
        if (o is savedfocus_) savedfocus_ = null;
        if (o is resizable_) resizable_ = this;
        if (o.parent is this)
            o.parent(null);

        if (index == children - 1)
            child_ = child_[0 .. $ - 1];
        else
            child_ = child_[0 .. index] ~ child_[index + 1 .. $];

        initSizes();
    }

    /// Removes o from the group without deleting it. Does nothing if o
    /// is not a child of this group.
    void remove(Widget o)
    {
        if (children == 0) return;
        int i = find(o);
        if (i < children)
            remove(i);
    }

    /**
     * Removes all children from the group and destroys them (deltes all
     * child widgets from memory, recursively). Resets resizable() to
     * this group. Differs from remove() in that it affects every child
     * and actually destroys them, matching FLTK's clear().
     */
    void clear()
    {
        savedfocus_ = null;
        resizable_ = this;
        initSizes();

        // Redirect fl.core.pushed() away from this group's children
        // before destroying them, so nothing about to be deleted is
        // still the target of event routing partway through the loop
        // below. If pushed() is (or is inside) this group, it becomes
        // this group itself for the duration; otherwise it's left
        // completely alone and restored unchanged at the end.
        Widget pushed = fl.core.pushed();
        if (contains(pushed)) pushed = this;
        fl.core.pushed(this);

        for (int i = children - 1; i >= 0; i--)
        {
            if (i >= children) continue; // a subclass may have removed some
            deleteChild(i);
        }

        if (pushed !is this) fl.core.pushed(pushed);
    }

    /**
     * Removes the widget at index from the group and destroys it.
     * Returns 0 on success, 1 if index is out of range. Does not call
     * initSizes() or redraw() -- that's left to the caller if needed.
     */
    int deleteChild(int index)
    {
        if (index < 0 || index >= children) return 1;
        Widget w = child(index);
        remove(index);
        // Deterministic, not GC-driven: safe for w's destructor to
        // reach into other objects (detach from parent, etc.), unlike
        // during automatic GC finalization. See fl.widget's ~this().
        destroy(w);
        return 0;
    }

    /**
     * The resizable widget defines both the resizing box and the
     * resizing behavior of the group and its children; see resizable(Widget).
     */
    // Not `const`: unlike C++, D's const is transitive, so a const method
    // could only return a const-qualified (uncallable-as-is) Widget
    // here. Same rationale as fl.widget's userData()/callback() getters.
    Widget resizable() { return resizable_; }

    /// See the getter's documentation for the resizing rules. Pass null
    /// to fix the group's size (all children stay a fixed size/distance
    /// from the top-left corner). Pass the group itself (the default) to
    /// resize all direct children proportionally.
    void resizable(Widget o) { resizable_ = o; }

    /// Adds o to the group and makes it the resizable widget.
    void addResizable(Widget o)
    {
        resizable_ = o;
        add(o);
    }

    /// Discards the cached initial child sizes/positions used by
    /// resize(); they'll be recomputed from the current layout next time
    /// resize() or bounds() runs. Called automatically whenever children
    /// are added, removed, or rearranged.
    void initSizes() { bounds_ = null; }

    void clipChildren(bool c)
    {
        if (c) setFlag(Flag.clipChildren);
        else clearFlag(Flag.clipChildren);
    }

    bool clipChildren() const { return (flags() & Flag.clipChildren) != 0; }

    override FlGroup asGroup() { return this; }
    override const(FlGroup) asGroup() const { return this; }

    override void resize(int x, int y, int w, int h)
    {
        int dx = x - this.x;
        int dy = y - this.y;
        int dw = w - this.w;
        int dh = h - this.h;

        Rect[] p = bounds(); // save initial sizes/positions

        super.resize(x, y, w, h); // update raw geometry, no virtual redispatch

        if (resizable_ is null || (dw == 0 && dh == 0))
        {
            // No resizable(), or the size didn't change: just move the
            // children (also covers plain window rescaling, dw==dh==0).

            if (asWindow() !is null)
                dx = dy = 0; // top/subwindows don't reposition their children

            if (Window.isARescale() || dx != 0 || dy != 0)
            {
                foreach (o; rawArray())
                    o.resize(o.x + dx, o.y + dy, o.w, o.h);
            }
        }
        else if (rawChildren > 0)
        {
            // We have a resizable() widget: scale children relative to it.
            dx = x - p[0].x;
            dw = w - p[0].w;
            dy = y - p[0].y;
            dh = h - p[0].h;
            if (asWindow() !is null)
                dx = dy = 0;

            int resizableLeft   = p[1].x;
            int resizableRight  = resizableLeft + p[1].w;
            int resizableTop    = p[1].y;
            int resizableBottom = resizableTop + p[1].h;

            auto a = rawArray();
            for (int i = 0; i < rawChildren; i++)
            {
                Widget o = a[i];
                const rect = p[2 + i];
                int left   = rect.x;
                int right  = left + rect.w;
                int top    = rect.y;
                int bottom = top + rect.h;

                if (left >= resizableRight) left += dw;
                else if (left > resizableLeft) left += dw * (left - resizableLeft) / (resizableRight - resizableLeft);
                if (right >= resizableRight) right += dw;
                else if (right > resizableLeft) right += dw * (right - resizableLeft) / (resizableRight - resizableLeft);
                if (top >= resizableBottom) top += dh;
                else if (top > resizableTop) top += dh * (top - resizableTop) / (resizableBottom - resizableTop);
                if (bottom >= resizableBottom) bottom += dh;
                else if (bottom > resizableTop) bottom += dh * (bottom - resizableTop) / (resizableBottom - resizableTop);

                o.resize(left + dx, top + dy, right - left, bottom - top);
            }
        }
    }

    override void draw()
    {
        if (damage() & ~damageChild)
        {
            drawBox();
            drawLabel();
        }
        drawChildren();
    }

    /// Draws every child, useful when a FlGroup subclass wants to draw its
    /// own border/background then call this from its own draw().
    void drawChildren()
    {
        if (clipChildren())
            pushClip(x + fl.core.boxDx(box), y + fl.core.boxDy(box), w - fl.core.boxDw(box), h - fl.core.boxDh(box));

        if (damage() & ~damageChild)
        {
            // Redraw the entire thing.
            foreach (o; rawArray())
            {
                drawChild(o);
                drawOutsideLabel(o);
            }
        }
        else
        {
            // Only redraw the children that need it.
            foreach (o; rawArray())
                updateChild(o);
        }

        if (clipChildren())
            popClip();
    }

    /// Draws widget only if it needs it (has damage and isn't clipped).
    protected void updateChild(Widget widget) const
    {
        if (widget.damage() && widget.visible() && widget.type() < windowTypeTag
            && notClipped(widget.x, widget.y, widget.w, widget.h))
        {
            widget.draw();
            widget.clearDamage();
        }
    }

    /// Forces widget to redraw, unless it's clipped away entirely.
    protected void drawChild(Widget widget) const
    {
        if (widget.visible() && widget.type() < windowTypeTag
            && notClipped(widget.x, widget.y, widget.w, widget.h))
        {
            widget.clearDamage(damageAll);
            widget.draw();
            widget.clearDamage();
        }
    }

    /// Draws widget's label if it's positioned outside of widget itself.
    protected void drawOutsideLabel(const(Widget) widget) const
    {
        if (!widget.visible()) return;
        // Skip labels that are drawn inside the widget.
        if (!(widget.alignment & alignPositionMask) || (widget.alignment & alignInside)) return;

        Align a = widget.alignment;
        int labelX = widget.x;
        int labelY = widget.y;
        int labelW = widget.w;
        int labelH = widget.h;
        int wx, wy;
        if (asWindow() !is null)
        {
            wx = 0;
            wy = 0;
        }
        else
        {
            wx = x;
            wy = y;
        }

        if ((a & alignPositionMask) == alignLeftTop)
        {
            a = (a & ~alignPositionMask) | alignTopRight;
            labelX = wx;
            labelW = widget.x - labelX - 3;
        }
        else if ((a & alignPositionMask) == alignLeftBottom)
        {
            a = (a & ~alignPositionMask) | alignBottomRight;
            labelX = wx;
            labelW = widget.x - labelX - 3;
        }
        else if ((a & alignPositionMask) == alignRightTop)
        {
            a = (a & ~alignPositionMask) | alignTopLeft;
            labelX = labelX + labelW + 3;
            labelW = wx + w - labelX;
        }
        else if ((a & alignPositionMask) == alignRightBottom)
        {
            a = (a & ~alignPositionMask) | alignBottomLeft;
            labelX = labelX + labelW + 3;
            labelW = wx + w - labelX;
        }
        else if (a & alignTop)
        {
            a = (a ^ alignTop) | alignBottom;
            labelY = wy;
            labelH = widget.y - labelY;
        }
        else if (a & alignBottom)
        {
            a = (a ^ alignBottom) | alignTop;
            labelY = labelY + labelH;
            labelH = wy + h - labelY;
        }
        else if (a & alignLeft)
        {
            a = (a ^ alignLeft) | alignRight;
            labelX = wx;
            labelW = widget.x - labelX - 3;
        }
        else if (a & alignRight)
        {
            a = (a ^ alignRight) | alignLeft;
            labelX = labelX + labelW + 3;
            labelW = wx + w - labelX;
        }

        widget.drawLabel(labelX, labelY, labelW, labelH, a);
    }

    /**
     * Lazily computes and caches each child's (and the group's, and the
     * resizable's) initial size/position, for use by resize(). Cleared
     * by initSizes() whenever children are added, removed, or rearranged.
     */
    protected Rect[] bounds()
    {
        if (bounds_ is null)
        {
            auto b = new Rect[rawChildren + 2];

            // First entry: the group's own size (position zeroed if the
            // group is a window).
            b[0] = (asWindow() !is null) ? Rect(w, h) : Rect(this);

            // Second entry: the resizable's size, clipped to the group.
            int left = b[0].x, top = b[0].y, right = b[0].r, bottom = b[0].b;
            Widget r = resizable_;
            if (r !is null && r !is this)
            {
                int t;
                t = r.x; if (t > left) left = t;
                t += r.w; if (t < right) right = t;
                t = r.y; if (t > top) top = t;
                t += r.h; if (t < bottom) bottom = t;
            }
            b[1] = Rect(left, top, right - left, bottom - top);

            // The rest: every child's size.
            auto a = rawArray();
            for (int i = 0; i < rawChildren; i++)
                b[2 + i] = Rect(a[i]);

            bounds_ = b;
        }
        return bounds_;
    }

    /// Allows derived groups to act when a widget is about to be added.
    /// Return -1 to refuse the insertion, or a different index to
    /// reposition it.
    protected int onInsert(Widget candidate, int index) { return index; }

    /// Allows derived groups to act when a child is about to be moved
    /// within the group. Return -1 to refuse the move.
    protected int onMove(int oldIndex, int newIndex) { return newIndex; }

    /// Allows derived groups to act just before the child at index is removed.
    protected void onRemove(int index) {}
}

// FlGroup's constructor calls begin(), which points the process-wide
// current() at the new group -- and leaves it there if a test doesn't
// end() it. Every unittest below starts by resetting current() to null
// so it can't inherit stray state left behind by another test.

unittest
{
    FlGroup.current(null);

    static class Leaf : Widget
    {
        this() { super(0, 0, 1, 1); }
        override void draw() {}
    }

    auto g = new FlGroup(0, 0, 100, 100);
    auto leaf = new Leaf();

    g.add(leaf);
    assert(g.children == 1);
    assert(leaf.parent is g);
    assert(g.find(leaf) == 0);
    assert(g.child(0) is leaf);

    g.remove(leaf);
    assert(g.children == 0);
    assert(leaf.parent is null);

    FlGroup.current(null);
}

unittest
{
    // Fl_Widget's constructor auto-adds to Fl_Group::current().
    FlGroup.current(null);

    auto g = new FlGroup(0, 0, 100, 100);
    g.begin();

    static class Leaf : Widget
    {
        this() { super(0, 0, 1, 1); }
        override void draw() {}
    }

    auto leaf = new Leaf();
    assert(leaf.parent is g);
    assert(g.children == 1);

    g.end();
    assert(FlGroup.current() is null);
}

unittest
{
    // resizable() defaults to the group itself; with no size change,
    // children just move by the group's delta.
    FlGroup.current(null);

    auto g = new FlGroup(0, 0, 100, 100);

    static class Leaf : Widget
    {
        this(int x, int y, int w, int h) { super(x, y, w, h); }
        override void draw() {}
    }

    auto leaf = new Leaf(10, 10, 20, 20);
    g.add(leaf);

    g.resize(50, 50, 100, 100);
    assert(leaf.x == 60 && leaf.y == 60);
    assert(leaf.w == 20 && leaf.h == 20);

    FlGroup.current(null);
}

unittest
{
    // With the default resizable() (the group itself), children scale
    // proportionally when the group's size changes.
    FlGroup.current(null);

    auto g = new FlGroup(0, 0, 100, 100);

    static class Leaf : Widget
    {
        this(int x, int y, int w, int h) { super(x, y, w, h); }
        override void draw() {}
    }

    auto leaf = new Leaf(0, 0, 50, 50);
    g.add(leaf);

    g.resize(0, 0, 200, 200);
    assert(leaf.w == 100 && leaf.h == 100);

    FlGroup.current(null);
}

unittest
{
    // clear() destroys all children and detaches them.
    FlGroup.current(null);

    auto g = new FlGroup(0, 0, 100, 100);

    static class Leaf : Widget
    {
        this() { super(0, 0, 1, 1); }
        override void draw() {}
    }

    g.add(new Leaf());
    g.add(new Leaf());
    assert(g.children == 2);

    g.clear();
    assert(g.children == 0);
    assert(g.resizable() is g);

    FlGroup.current(null);
}

unittest
{
    // clear() redirects fl.core.pushed() away from a child about to be
    // deleted (to the group itself, since the child won't exist to
    // route events to afterward), but leaves it completely alone if it
    // wasn't one of this group's children/descendants to begin with.
    FlGroup.current(null);
    resetCoreEventState();

    static class Leaf : Widget
    {
        this() { super(0, 0, 1, 1); }
        override void draw() {}
    }

    auto g = new FlGroup(0, 0, 100, 100);
    auto child = new Leaf();
    g.add(child);
    FlGroup.current(null);

    fl.core.pushed(child);
    g.clear();
    assert(fl.core.pushed() is g); // child is gone; redirected to the group

    resetCoreEventState();
    FlGroup.current(null);

    auto g2 = new FlGroup(0, 0, 100, 100);
    g2.add(new Leaf());
    FlGroup.current(null);
    auto outsider = new Leaf();
    FlGroup.current(null);

    fl.core.pushed(outsider);
    g2.clear();
    assert(fl.core.pushed() is outsider); // untouched -- never was a child

    resetCoreEventState();
    FlGroup.current(null);
}

unittest
{
    // Moving a widget already in this group rearranges instead of
    // removing/re-adding it.
    FlGroup.current(null);

    auto g = new FlGroup(0, 0, 100, 100);

    static class Leaf : Widget
    {
        this() { super(0, 0, 1, 1); }
        override void draw() {}
    }

    auto a = new Leaf();
    auto b = new Leaf();
    auto c = new Leaf();
    g.add(a);
    g.add(b);
    g.add(c);
    assert(g.find(a) == 0 && g.find(b) == 1 && g.find(c) == 2);

    g.insert(c, 0);
    assert(g.find(c) == 0 && g.find(a) == 1 && g.find(b) == 2);
    assert(g.children == 3);

    FlGroup.current(null);
}

// Tests below exercise handle()/navigation(), which read and mutate the
// shared event-state globals in fl.core (event key/state, focus,
// belowmouse, pushed). Those are process-wide, like FlGroup.current(), so
// every test resets them on both ends too -- see the module-level note
// above on hermetic tests.

private void resetCoreEventState()
{
    fl.core.resetForTest();
}

private static class FocusableLeaf : Widget
{
    this(int x, int y, int w, int h) { super(x, y, w, h); }
    override void draw() {}
    override int handle(Event event) { return event == Event.focus ? 1 : 0; }
}

/// Accepts every event; used to test handle() paths (ENTER/MOVE, PUSH)
/// that only take their "handled" branch when the child's own handle()
/// returns non-zero.
private static class AcceptingLeaf : Widget
{
    this(int x, int y, int w, int h) { super(x, y, w, h); }
    override void draw() {}
    override int handle(Event event) { return 1; }
}

unittest
{
    // Tab moves focus to the next child; shift-Tab moves to the previous.
    FlGroup.current(null);
    resetCoreEventState();

    auto g = new FlGroup(0, 0, 100, 100);
    auto a = new FocusableLeaf(0, 0, 10, 10);
    auto b = new FocusableLeaf(20, 0, 10, 10);
    g.add(a);
    g.add(b);
    FlGroup.current(null);

    a.takeFocus();
    assert(fl.core.focus() is a);

    fl.core.eKeysym_ = tab;
    assert(g.handle(Event.keyDown) == 1);
    assert(fl.core.focus() is b);

    fl.core.eKeysym_ = tab;
    fl.core.eState_ = stateShift;
    assert(g.handle(Event.keyDown) == 1);
    assert(fl.core.focus() is a);

    resetCoreEventState();
    FlGroup.current(null);
}

unittest
{
    // FL_FOCUS with no navigation key restores the last-focused child
    // (saved via FL_UNFOCUS's savedfocus_ = fl.core.oldFocus()).
    FlGroup.current(null);
    resetCoreEventState();

    auto g = new FlGroup(0, 0, 100, 100);
    auto a = new FocusableLeaf(0, 0, 10, 10);
    auto b = new FocusableLeaf(20, 0, 10, 10);
    g.add(a);
    g.add(b);
    FlGroup.current(null);

    b.takeFocus();
    assert(fl.core.focus() is b);

    // Focusing something outside the group sends FL_UNFOCUS up b's
    // ancestor chain, including g -- which records savedfocus_ = b.
    auto outsider = new FocusableLeaf(0, 0, 10, 10);
    fl.core.focus(outsider);
    assert(fl.core.focus() is outsider);

    fl.core.eKeysym_ = 0; // not a navigation key
    assert(g.handle(Event.focus) == 1);
    assert(fl.core.focus() is b);

    resetCoreEventState();
    FlGroup.current(null);
}

unittest
{
    // FL_ENTER/FL_MOVE routes to the topmost child under the mouse and
    // updates belowmouse().
    FlGroup.current(null);
    resetCoreEventState();

    auto g = new FlGroup(0, 0, 100, 100);
    auto a = new AcceptingLeaf(0, 0, 10, 10);
    auto b = new AcceptingLeaf(20, 0, 10, 10);
    g.add(a);
    g.add(b);
    FlGroup.current(null);

    fl.core.eX_ = 25; // inside b, outside a
    fl.core.eY_ = 5;
    assert(g.handle(Event.move) == 1);
    assert(fl.core.belowmouse() is b);

    fl.core.eX_ = 0;
    fl.core.eY_ = 0;
    resetCoreEventState();
    FlGroup.current(null);
}

unittest
{
    // FL_PUSH routes to the child under the mouse and FlGroup.handle()
    // reports it as handled.
    FlGroup.current(null);
    resetCoreEventState();

    auto g = new FlGroup(0, 0, 100, 100);
    auto a = new AcceptingLeaf(0, 0, 10, 10);
    g.add(a);
    FlGroup.current(null);

    fl.core.eX_ = 5;
    fl.core.eY_ = 5;
    assert(g.handle(Event.push) == 1);

    fl.core.eX_ = 0;
    fl.core.eY_ = 0;
    resetCoreEventState();
    FlGroup.current(null);
}

private static class SelfDestructingLeaf : Widget
{
    this(int x, int y, int w, int h) { super(x, y, w, h); }
    override void draw() {}
    override int handle(Event event)
    {
        if (event == Event.push) destroy(this);
        return 1;
    }
}

unittest
{
    // WidgetTracker guard: a child that destroys itself while handling
    // FL_PUSH must not crash FlGroup.handle() when it tries to touch that
    // child again afterward (the pushed()/contains() follow-up check).
    FlGroup.current(null);
    resetCoreEventState();

    auto g = new FlGroup(0, 0, 100, 100);
    auto a = new SelfDestructingLeaf(0, 0, 10, 10);
    g.add(a);
    FlGroup.current(null);

    fl.core.eX_ = 5;
    fl.core.eY_ = 5;
    // Should not crash even though `a` destroys itself mid-push.
    assert(g.handle(Event.push) == 1);

    fl.core.eX_ = 0;
    fl.core.eY_ = 0;
    resetCoreEventState();
    FlGroup.current(null);
}
