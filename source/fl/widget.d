/*
 * Ported from FL/Fl_Widget.H + src/Fl_Widget.cxx (FLTK 1.5.0). Fl_Widget is the base class of every widget in
 * FLTK; this is the first class ported in this project.
 *
 * Porting conventions used here (and going forward):
 *
 *  - Private storage fields keep FLTK's trailing-underscore names
 *    (x_, y_, label_, flags_, ...) so they never collide with their
 *    public accessor methods, exactly as FLTK uses the convention
 *    (and for the same reason: `align` is also a D keyword, matching
 *    Fl_Label::align_ needing to dodge the same problem in C++).
 *
 *  - Where FLTK stores a value in a raw `uchar`/`int` specifically to
 *    stay open to values outside the documented enum (box types, label
 *    types, widget `type()`), this port still uses the real D enum type
 *    (e.g. `Boxtype box_` instead of `ubyte box_`) since D enums permit
 *    forward-cast extension via `cast(Boxtype) n` when needed, so nothing
 *    is lost.
 *
 *  - `label()`/`tooltip()` use D `string` (GC-owned, immutable) rather
 *    than `const char*`. FLTK's COPIED_LABEL/COPIED_TOOLTIP flags
 *    exist because plain C strings need explicit malloc/free bookkeeping
 *    to know whether the widget owns its copy; under D's GC that
 *    bookkeeping is unnecessary; copyLabel()/copyTooltip() still exist
 *    and still set the flag (so isLabelCopied() etc. keep working), they
 *    just skip the manual free().
 *
 *  - Callbacks are D delegates (`Callback = void delegate(Widget)`), not
 *    a C-style function pointer plus `void*` user data. A delegate
 *    already carries its own captured context, which is exactly what
 *    Fl_Widget's callback-argument use of `user_data()`/`argument()`/
 *    `Fl_Callback_User_Data`/`AUTO_DELETE_USER_DATA` exist to simulate
 *    by hand -- C++'s workaround for plain function pointers not being
 *    able to close over state. A caller who wants per-callback data just
 *    captures it in the closure passed to callback(), e.g.
 *    `btn.callback((w) { doSomething(id); });` instead of
 *    `btn.callback(fn, cast(void*) id)`.
 *
 *  - `user_data()` as a plain per-widget tag (attach something to a
 *    widget, read it back later, independent of any callback) is ported
 *    as `userData()`/`userData(Object)`: an `Object` reference instead of
 *    a `void*`, GC-managed, like `TreeItem.userData`. There is no
 *    `argument()` (the same slot read as a `long`) and no
 *    `Fl_Callback_User_Data`/`AUTO_DELETE_USER_DATA`: the GC owns the
 *    object.
 *
 *  - labelShortcut()/testShortcut() (Fl_Widget::label_shortcut()/
 *    test_shortcut(), src/fl_shortcut.cxx): the '&x'-in-label shortcut
 *    parsing/matching, ported since something finally calls it
 *    (fl.button, and Fl_Group's FL_SHORTCUT handling in fl.group). Not
 *    ported alongside it: fl_old_shortcut() (Forms-compat ASCII
 *    shortcut syntax, out of scope, see forms.H in PORTING.md).
 *    fl_shortcut_label() (human-readable "Ctrl+Alt+F1"-style rendering)
 *    is ported too, as fl.core.flShortcutLabel() (see that
 *    module's row in PORTING.md for the per-platform key-name lookup
 *    it needed); fl.shortcut_button is its first caller.
 *
 * **`drawBackdrop()`/`Label.image`/`Label.deimage` are real**:
 * `drawBackdrop()` draws
 * `image()`/`deimage()` centered when `alignImageBackdrop` is set,
 * `Label.draw()`'s normalLabel branch composes `image` alongside text
 * via `fl.draw`'s image-aware `fl_draw()` overload, and
 * `Label.measure()` sizes for it too -- all ported from
 * `Fl_Widget::draw_backdrop()`/`fl_normal_label()`/`fl_normal_measure()`.
 *
 * do_callback()'s Fl_Widget_Tracker "was `this` deleted?" guard IS
 * ported (fl.widget_tracker.WidgetTracker) -- see that module's own
 * comment for why it needed a real D-appropriate redesign rather than a
 * straight translation (a naive `bool` flag set inside `~this()` does
 * not work in D: `destroy()` wipes an object's fields back to `.init`
 * immediately after the destructor runs, silently erasing such a flag
 * before any caller could observe it).
 */
module fl.widget;

import std.typecons : Rebindable;
import std.utf : decode;
import core.memory : GC;

import fl.enumerations;
import fl.image : Image;
import fl.group : FlGroup;
import fl.window : Window;
import fl.core;
import fl.widget_tracker : WidgetTracker;
import fl.multi_label : MultiLabel;
import fl.file_icon : FileIcon;
import fldraw = fl.draw;

/**
 * Fl_Callback's D equivalent: a closure invoked with the widget that
 * triggered it. Unlike FLTK, there is no companion `void*` user-data
 * parameter -- capture whatever state the callback needs directly.
 */
alias Callback = void delegate(Widget);

/// Fl_Label: everything needed to draw a widget's text/image label.
struct Label
{
    string text;
    Image image;
    Image deimage;
    Font font = helvetica;
    Fontsize size;
    Color color = foregroundColor;
    Align alignment = alignCenter;
    Labeltype type = Labeltype.normalLabel;
    byte hMargin;
    byte vMargin;
    ubyte spacing;

    /// Backing storage for `Labeltype.multiLabel` (fl.multi_label's
    /// MultiLabel) -- see draw()/measure()'s dispatch below. FLTK's
    /// equivalent mechanism is `Fl::set_labeltype()`'s per-type
    /// function-pointer table plus `Fl_Multi_Label::label(Fl_Widget*)`
    /// smuggling a `Fl_Multi_Label*` through the label's `const char*`
    /// value slot; D's `text` is a real `string`, not a raw pointer
    /// that can be reinterpreted, so multiLabel gets its own typed slot
    /// instead.
    MultiLabel multi;

    /// Backing storage for `Labeltype.iconLabel` -- see `fl.file_icon`'s
    /// module comment and `Widget.label(FileIcon)` below. Same "typed
    /// slot instead of a reinterpreted pointer" substitution as `multi`
    /// above; FLTK smuggles the `Fl_File_Icon*` through this same
    /// `const char*` value slot (`w->label(FL_ICON_LABEL, (const
    /// char*)this)`).
    FileIcon icon;

    /**
     * Draws this label within (x,y,w,h) per alignment. Ported from
     * Fl_Label::draw() (src/fl_labeltype.cxx): applies the h/vMargin
     * inset on whichever edges alignment doesn't push the label
     * against, then dispatches on type().
     *
     * FLTK dispatches through a per-labeltype function-pointer
     * table (`Fl::set_labeltype()`).
     * `FL_SHADOW_LABEL`/`FL_ENGRAVED_LABEL`/`FL_EMBOSSED_LABEL` are
     * each a macro (`#define FL_SHADOW_LABEL fl_define_FL_SHADOW_LABEL()`,
     * `FL/Enumerations.H`) that performs the `Fl::set_labeltype()`
     * registration as a side effect of merely being *referenced* -- so
     * any program that names the constant at all (as every real caller
     * must, to set `labeltype()` to it) gets the real effect with no
     * separate opt-in step, FLTK's own `test/label.cxx` included.
     * Those three
     * cases call `fl.draw`'s callback-`fl_draw()` overload with
     * `shadowLabelDraw()`/`engravedLabelDraw()`/
     * `fl_embossed_label_draw()` (ported from `src/
     * fl_engraved_label.cxx`) as the per-line drawing hook, each drawing
     * the same text several times at small pixel offsets in different
     * shades before the final normal-color pass -- exactly FLTK's
     * own `innards()` trick. `normalLabel` keeps calling the plain
     * (non-callback) overload, drawing plain text plus `image` (via
     * `fl.draw`'s image-aware `fl_draw()` overload), matching
     * FLTK's own `fl_normal_label()`. `multiLabel` dispatches into
     * the `multi` field (see
     * fl.multi_label) when set. `iconLabel` dispatches into `icon`
     * (see fl.file_icon) when set. **`imageLabel`/`_FL_IMAGE_LABEL` is
     * deliberately not ported**: FLTK's own doc comment on
     * `Fl_Image::label(Fl_Widget*)` calls that whole mechanism
     * "obsolete... please use Fl_Widget::image() or
     * Fl_Widget::deimage() instead" -- it exists only to smuggle an
     * `Fl_Image*` through the label's `value`/text pointer for
     * pre-`image()`-field-era code, the same category of C-pointer-
     * punning trick this port already declines to replicate for
     * `MultiLabel`/`FileIcon` (real typed fields instead) elsewhere in
     * this struct. Since `image`/`deimage` already draw for real via
     * the `normalLabel` branch below, `imageLabel` would produce
     * exactly the same pixels through a redundant second mechanism --
     * not worth porting. `noLabel`/`freeLabeltype` still draw nothing
     * (`fl_no_label`'s equivalent).
     */
    void draw(int x, int y, int w, int h, Align alignment) const
    {
        if (text.length == 0 && image is null && multi is null && icon is null) return;

        int X = x, Y = y, W = w, H = h;
        switch (alignment & (alignTop | alignBottom))
        {
        case 0: Y += vMargin; H -= 2 * vMargin; break;
        case alignTop: Y += vMargin; H -= vMargin; break;
        case alignBottom: H -= vMargin; break;
        default: break;
        }
        switch (alignment & (alignLeft | alignRight))
        {
        case 0: X += hMargin; W -= 2 * hMargin; break;
        case alignLeft: X += hMargin; W -= hMargin; break;
        case alignRight: W -= hMargin; break;
        default: break;
        }

        switch (type)
        {
        case Labeltype.normalLabel:
            fldraw.fl_font(font, size);
            fldraw.fl_color(color);
            fldraw.fl_draw(text, X, Y, W, H, alignment, cast(Image) image, spacing);
            break;
        case Labeltype.shadowLabel:
            fldraw.fl_font(font, size);
            fldraw.fl_color(color);
            fldraw.fl_draw(text, X, Y, W, H, alignment,
                (s, n, x1, y1) { fldraw.shadowLabelDraw(s, n, x1, y1); }, cast(Image) image, spacing);
            break;
        case Labeltype.engravedLabel:
            fldraw.fl_font(font, size);
            fldraw.fl_color(color);
            fldraw.fl_draw(text, X, Y, W, H, alignment,
                (s, n, x1, y1) { fldraw.engravedLabelDraw(s, n, x1, y1); }, cast(Image) image, spacing);
            break;
        case Labeltype.embossedLabel:
            fldraw.fl_font(font, size);
            fldraw.fl_color(color);
            fldraw.fl_draw(text, X, Y, W, H, alignment,
                (s, n, x1, y1) { fldraw.embossedLabelDraw(s, n, x1, y1); }, cast(Image) image, spacing);
            break;
        case Labeltype.multiLabel:
            if (multi !is null) multi.draw(X, Y, W, H, alignment, &this);
            break;
        case Labeltype.iconLabel:
            // Matches FLTK's Fl_File_Icon::labeltype(o,...) exactly:
            // always active=true (default parameter) regardless of the
            // widget's real active state -- the caller (Widget.drawLabel())
            // already pre-dims `color` via inactive() when inactive,
            // same as FLTK's Fl_Widget::draw_label() does to `l1.color`
            // before reaching here.
            if (icon !is null) icon.draw(X, Y, W, H, color);
            break;
        default:
            break;
        }
    }

    /// Measures the size this label needs to draw at, in font/size,
    /// including `image` (real, matching FLTK's
    /// `fl_normal_measure()`, src/fl_labeltype.cxx exactly): an
    /// `alignImageNextToText` image adds its width plus `spacing` and
    /// grows the height to fit if taller; otherwise (image above/below
    /// text, the default) it adds its height plus `spacing` and grows
    /// the width to fit if wider. An `alignImageBackdrop` image is
    /// ignored here, same as FLTK -- it doesn't affect layout, see
    /// `Widget.drawBackdrop()`. `multiLabel` dispatches into `multi`
    /// (see fl.multi_label).
    void measure(out int w, out int h) const
    {
        if (type == Labeltype.multiLabel)
        {
            if (multi !is null) multi.measure(w, h, &this);
            else { w = 0; h = 0; }
            return;
        }
        if (text.length != 0)
        {
            fldraw.fl_font(font, size);
            fldraw.fl_measure(text, w, h);
        }
        else
        {
            w = 0;
            h = 0;
        }
        if (image !is null)
        {
            int iw = image.w(), ih = image.h();
            if (alignment & alignImageBackdrop)
            {
                // Ignore backdrop image for layout calculation.
            }
            else if (alignment & alignImageNextToText)
            {
                w += iw + spacing;
                if (ih > h) h = ih;
            }
            else
            {
                if (iw > w) w = iw;
                h += ih + spacing;
            }
        }
    }
}

/**
 * Fl_Widget: the base class for all widgets in FLTK.
 *
 * The constructor is protected, matching FLTK: you can't create a
 * bare Widget, only subclass it.
 */
abstract class Widget
{
    // package(fl) rather than private: subclasses in other fl.* modules
    // (starting with fl.group, for CLIP_CHILDREN) need to read/set these.
    package(fl) enum Flag : uint
    {
        inactive           = 1 << 0,
        invisible          = 1 << 1,
        output             = 1 << 2,
        noBorder           = 1 << 3,
        forcePosition      = 1 << 4,
        nonModal           = 1 << 5,
        shortcutLabel      = 1 << 6,
        changed            = 1 << 7,
        windowOverride     = 1 << 8,
        visibleFocus       = 1 << 9,
        copiedLabel        = 1 << 10,
        clipChildren       = 1 << 11,
        menuWindow         = 1 << 12,
        tooltipWindow      = 1 << 13,
        modal              = 1 << 14,
        noOverlay          = 1 << 15,
        groupRelative      = 1 << 16,
        copiedTooltip      = 1 << 17,
        fullscreen         = 1 << 18,
        macUseAccentsMenu  = 1 << 19,
        needsKeyboard       = 1 << 20,
        imageBound         = 1 << 21,
        deimageBound       = 1 << 22,
        // 1 << 23 was AUTO_DELETE_USER_DATA FLTK; not needed here,
        // see the module-level note on Callback. Left unused rather than
        // renumbered so the remaining bits still match FLTK 1:1.
        maximized          = 1 << 24,
        popup              = 1 << 25,
        userflag3          = 1 << 29,
        userflag2          = 1 << 30,
        userflag1          = 1 << 31,
    }

    /// Widgets whose type() is at least this are Fl_Window or a subclass;
    /// see fl.window's Window constructor. Mirrors FL_WINDOW (0xF0) from
    /// FL/Fl_Window.H.
    package(fl) enum ubyte windowTypeTag = 0xF0;

    private
    {
        // Widget, not FlGroup -- see the doc comment on parent()/parent(Widget)
        // below for why this is wider than FLTK's Fl_Widget::parent()
        // (which returns Fl_Group*).
        Widget parent_;
        Callback callback_;
        int x_, y_, w_, h_;
        Label label_;
        uint flags_;
        Color color_;
        Color selectionColor_;
        ubyte type_;
        ubyte damage_;
        Boxtype box_;
        ubyte when_;
        string tooltip_;
        Object userData_;
    }

    protected this(int x, int y, int w, int h, string label = null)
    {
        x_ = x; y_ = y; w_ = w; h_ = h;

        label_.text      = label;
        label_.image     = null;
        label_.deimage   = null;
        label_.type      = Labeltype.normalLabel;
        label_.font      = helvetica;
        label_.size      = normalSize;
        label_.color     = foregroundColor;
        label_.alignment = alignCenter;
        label_.hMargin   = 0;
        label_.vMargin   = 0;
        label_.spacing   = 0;

        tooltip_        = null;
        callback_       = null; // null means "use the default (queue) behavior"; see doCallback()
        type_           = 0;
        flags_          = Flag.visibleFocus;
        damage_         = 0;
        box_            = Boxtype.noBox;
        color_          = gray;
        selectionColor_ = gray;
        when_           = whenRelease;

        parent_ = null;
        if (FlGroup.current() !is null)
            FlGroup.current().add(this);
    }

    package(fl) uint flags() const { return flags_; }
    package(fl) void setFlag(uint f) { flags_ |= f; }
    package(fl) void clearFlag(uint f) { flags_ &= ~f; }

    ~this()
    {
        fl.core.clearWidgetPointer(this);

        if (!GC.inFinalizer())
        {
            // The operations below reach into other GC-managed objects
            // (parent_, the label's image/deimage). That's only safe
            // when this destructor runs deterministically, e.g. via
            // `destroy(widget)`. During GC-driven finalization (program
            // exit, a collection sweep) those objects' finalization
            // order relative to this one is undefined, so touching them
            // here risks a use-after-free. If the collector reclaimed
            // this instance, nothing reachable was still pointing at it
            // -- including parent_.children -- so skipping the
            // bookkeeping below is safe in that case.
            image(null);
            deimage(null);
            // A composed-but-not-tree-managed child (see parent()'s own
            // doc comment) has a non-FlGroup parent_ -- cast fails (null),
            // and there's no FlGroup child-list to remove it from anyway.
            if (auto g = cast(FlGroup) parent_)
                g.remove(this);
            parent_ = null;
            fl.core.throwFocus(this);
        }

        if (callback_ is null)
            cleanupReadqueue(this);
    }

    /// Never call directly; FLTK schedules redraws. Override to draw.
    abstract void draw();

    /// Returns 0 if the event was not used, non-zero if it was.
    int handle(Event event)
    {
        return 0;
    }

    /// Sends event to this widget; a wrapper for handle(), used by groups
    /// to deliver events to children. For a subwindow it first translates
    /// the mouse coordinates and settles belowmouse()/DND state, so it,
    /// rather than handle(), is the dispatch to use for any event.
    final int send(Event event)
    {
        if (asWindow() is null) return handle(event);

        if (event == Event.dndEnter || event == Event.dndDrag)
            event = contains(fl.core.belowmouse()) ? Event.dndDrag : Event.dndEnter;

        int savedX = fl.core.eX_; fl.core.eX_ -= x();
        int savedY = fl.core.eY_; fl.core.eY_ -= y();
        int ret = handle(event);
        fl.core.eY_ = savedY;
        fl.core.eX_ = savedX;

        if (event == Event.enter || event == Event.dndEnter)
            if (!contains(fl.core.belowmouse())) fl.core.belowmouse(this);

        return ret;
    }

    bool isLabelCopied() const { return (flags_ & Flag.copiedLabel) != 0; }

    void needsKeyboard(bool needs)
    {
        if (needs) setFlag(Flag.needsKeyboard);
        else clearFlag(Flag.needsKeyboard);
    }

    bool needsKeyboard() const { return (flags_ & Flag.needsKeyboard) != 0; }

    /**
     * The widget's parent -- normally a real FlGroup (matching FLTK's
     * `Fl_Widget::parent()`, which returns `Fl_Group*`), but widened to
     * plain `Widget` here so a non-FlGroup widget can still legitimately
     * set itself as the parent of a composed-but-not-tree-managed child
     * (e.g. `fl.value_input.ValueInput`'s embedded `Input`). Every
     * consumer of `.parent`/`.parent_` in this port (`contains()`,
     * `damage()`, `window()`, `fl.core`'s focus/belowmouse ancestor
     * walks) only ever needs `Widget`-level information (identity,
     * `type()`, and the chain itself) -- none of them call anything
     * FlGroup-specific on a parent they've walked to, so this widening
     * costs nothing there. The few call sites that *do* need FlGroup-
     * specific behavior (`fl.group.FlGroup.insert()`/`end()`,
     * `fl.pack.Pack.resize()`) cast back to `FlGroup` explicitly; see
     * each one's own comment for why that cast is always safe there
     * (a real FlGroup's own parent -- as opposed to some exotic composed
     * child's -- is always itself a FlGroup or null, by construction).
     *
     * This replaces an earlier design (three separate, narrow
     * overrides/workarounds scattered across `fl.value_input.d` and
     * its two `handleRmb()` callers) that patched each broken
     * `parent_`-dependent mechanism one at a time as it was discovered
     * interactively -- `contains()`, `damage()`, then `window()`. Once
     * a third mechanism broke the same way, it was clear the actual
     * bug was `parent_`'s type being narrower than it needed to be,
     * not any one consumer -- fixing it here fixes all of them (and
     * any future one) at once, for any future widget with the same
     * composed-child shape, not just this one.
     */
    @property inout(Widget) parent() inout { return parent_; }
    /// Internal use only; use FlGroup.add()/FlGroup.remove() for a normal
    /// tree-managed child. A widget composing a private, non-tree-
    /// managed child widget (see parent()'s own doc comment) may also
    /// call this directly to give that child a working ancestor chain.
    @property package(fl) void parent(Widget p) { parent_ = p; }

    ubyte type() const { return type_; }
    void type(ubyte t) { type_ = t; }

    int x() const { return x_; }
    int y() const { return y_; }
    int w() const { return w_; }
    int h() const { return h_; }

    void resize(int x, int y, int w, int h)
    {
        x_ = x; y_ = y; w_ = w; h_ = h;
    }

    /**
     * Sets x()/y()/w()/h() directly, without going through any
     * subclass's resize() override -- the D structural equivalent of
     * a C++-only pattern FLTK leans on in a few places: calling
     * `Fl_Widget::resize(...)` by explicit qualification to reach the
     * base implementation from several levels down, skipping every
     * override in between (e.g. `Fl_Pack::draw()` resizing the pack
     * itself to fit its children, without re-running
     * `Fl_Group::resize()`'s child-layout algorithm or a subclass's
     * own `resize()` override's side effects). D's `super.foo()` only
     * reaches the *immediate* parent's implementation, not an
     * arbitrary ancestor, so there's no direct equivalent; a same-
     * bodied `final` method (not part of the vtable, so it always runs
     * exactly this code no matter how far down the hierarchy it's
     * called from) is the closest match. First needed by fl.pack.
     *
     * Public, not `protected`: `fluid.canvas`'s
     * `ProjectCanvas.applyDrag()` needs the identical bypass from
     * *outside* the class hierarchy entirely, for the "Synchronized
     * Resize" off state (the interactive editor's design-time default,
     * matching FLTK's own `Fl_Group_Proxy::resize()` calling
     * `Fl_Widget::resize()` when its own `allow_layout` toggle is off)
     * -- a real, external, legitimate second use for the same bypass
     * `fl.pack` already established the need for, not a workaround.
     */
    final void resizeBoundsOnly(int x, int y, int w, int h)
    {
        x_ = x; y_ = y; w_ = w; h_ = h;
    }

    /// Internal use only.
    int damageResize(int x, int y, int w, int h)
    {
        if (x_ == x && y_ == y && w_ == w && h_ == h)
            return 0;
        resize(x, y, w, h);
        redraw();
        return 1;
    }

    void position(int x, int y) { resize(x, y, w_, h_); }
    void size(int w, int h) { resize(x_, y_, w, h); }

    Align alignment() const { return label_.alignment; }
    void alignment(Align a) { label_.alignment = a; }

    Boxtype box() const { return box_; }
    void box(Boxtype b) { box_ = b; }

    Color color() const { return color_; }
    void color(Color bg) { color_ = bg; }

    Color selectionColor() const { return selectionColor_; }
    void selectionColor(Color c) { selectionColor_ = c; }

    void color(Color bg, Color sel) { color_ = bg; selectionColor_ = sel; }

    string label() const { return label_.text; }

    void label(string text)
    {
        clearFlag(Flag.copiedLabel);
        label_.text = text;
        redrawLabel();
    }

    /// Unlike label(), stores an owned copy of the text.
    void copyLabel(const(char)[] newLabel)
    {
        label(newLabel.idup);
        setFlag(Flag.copiedLabel);
    }

    void label(Labeltype type, string text)
    {
        label_.type = type;
        label_.text = text;
    }

    /// Associates m with this widget's label: draws/measures via m's
    /// labela/labelb from now on. D counterpart of
    /// `Fl_Multi_Label::label(Fl_Widget*)` calling
    /// `o->label(FL_MULTI_LABEL, (const char*)this)` -- see
    /// fl.multi_label's MultiLabel.label() (the actual FLTK-shaped
    /// entry point) and Label.multi's doc comment for why this needs
    /// its own setter rather than reusing label(Labeltype, string).
    void label(MultiLabel m)
    {
        label_.type = Labeltype.multiLabel;
        label_.multi = m;
    }

    inout(MultiLabel) labelMulti() inout { return label_.multi; }

    /// Associates ic with this widget's label: draws via ic's
    /// FileIcon.draw() from now on. D counterpart of
    /// `Fl_File_Icon::label(Fl_Widget*)` calling `w->label(FL_ICON_LABEL,
    /// (const char*)this)` -- same reasoning as label(MultiLabel) above.
    void label(FileIcon ic)
    {
        label_.type = Labeltype.iconLabel;
        label_.icon = ic;
    }

    inout(FileIcon) labelIcon() inout { return label_.icon; }

    Labeltype labeltype() const { return label_.type; }
    void labeltype(Labeltype t) { label_.type = t; }

    Color labelcolor() const { return label_.color; }
    void labelcolor(Color c) { label_.color = c; }

    Font labelfont() const { return label_.font; }
    void labelfont(Font f) { label_.font = f; }

    Fontsize labelsize() const { return label_.size; }
    void labelsize(Fontsize s) { label_.size = s; }

    inout(Image) image() inout { return label_.image; }

    void image(Image img)
    {
        if (imageBound())
        {
            if (label_.image !is null && label_.image !is img)
                label_.image.release();
            bindImage(false);
        }
        label_.image = img;
    }

    /// Binds img to the widget: the widget will release() it when no
    /// longer needed.
    void bindImage(Image img)
    {
        image(img);
        bindImage(img !is null);
    }

    void bindImage(bool bound)
    {
        if (bound) setFlag(Flag.imageBound);
        else clearFlag(Flag.imageBound);
    }

    bool imageBound() const { return (flags_ & Flag.imageBound) != 0; }

    inout(Image) deimage() inout { return label_.deimage; }

    void deimage(Image img)
    {
        if (deimageBound())
        {
            if (label_.deimage !is null && label_.deimage !is img)
                label_.deimage.release();
            bindDeimage(false);
        }
        label_.deimage = img;
    }

    void bindDeimage(Image img)
    {
        deimage(img);
        bindDeimage(img !is null);
    }

    void bindDeimage(bool bound)
    {
        if (bound) setFlag(Flag.deimageBound);
        else clearFlag(Flag.deimageBound);
    }

    bool deimageBound() const { return (flags_ & Flag.deimageBound) != 0; }

    void labelImageSpacing(int gap) { label_.spacing = cast(ubyte) gap; }
    int labelImageSpacing() const { return label_.spacing; }

    void horizontalLabelMargin(int px) { label_.hMargin = cast(byte) px; }
    int horizontalLabelMargin() const { return label_.hMargin; }

    void verticalLabelMargin(int px) { label_.vMargin = cast(byte) px; }
    int verticalLabelMargin() const { return label_.vMargin; }

    /// The object attached to this widget, or null. Nothing in the toolkit
    /// reads it: it is for the application, typically to tell widgets
    /// apart in a callback several of them share (`o.userData`).
    Object userData() { return userData_; }

    /// ditto
    void userData(Object data) { userData_ = data; }

    string tooltip() const { return tooltip_; }

    void tooltip(string text)
    {
        // Deliberately doesn't call Fl_Tooltip::set_enter_exit_once_():
        // that
        // FLTK call lazily wires up Fl_Tooltip::enter/exit function
        // pointers purely so an app that never sets a tooltip doesn't
        // link in Fl_Tooltip.cxx -- a C++ static-linking concern with
        // no D equivalent. fl.core calls straight into fl.tooltip
        // unconditionally instead; see that module's own top comment.
        clearFlag(Flag.copiedTooltip);
        tooltip_ = text;
    }

    /// Unlike tooltip(), stores an owned copy of the text.
    void copyTooltip(const(char)[] text)
    {
        setFlag(Flag.copiedTooltip);
        tooltip_ = text.idup;
    }

    // Not `const`: unlike C++, D's const is transitive, so a const method
    // could only ever return a const-qualified (uncallable-as-is)
    // delegate here. The FLTK accessor is logically const anyway
    // (only the stored callback *value* is read, not mutated).
    Callback callback() { return callback_; }

    /// Sets the callback invoked by doCallback(). Pass null to restore
    /// the default behavior (push the widget onto fl.fl.core.readqueue()).
    void callback(Callback cb) { callback_ = cb; }

    When when() const { return when_; }
    void when(When i) { when_ = cast(ubyte) i; }

    bool visible() const { return (flags_ & Flag.invisible) == 0; }

    bool visibleR() const
    {
        Rebindable!(const Widget) o = this;
        while (o !is null)
        {
            if (!o.visible())
                return false;
            o = o.parent_;
        }
        return true;
    }

    void show()
    {
        if (!visible())
        {
            clearFlag(Flag.invisible);
            if (visibleR())
            {
                redraw();
                redrawLabel();
                handle(Event.show);
                if (inside(fl.core.focus()))
                    fl.core.focus().takeFocus();
            }
        }
    }

    void hide()
    {
        if (visibleR())
        {
            setFlag(Flag.invisible);
            for (Widget p = parent_; p !is null; p = p.parent_)
            {
                if (p.box() != Boxtype.noBox || p.parent is null)
                {
                    p.redraw();
                    break;
                }
            }
            handle(Event.hide);
            fl.core.throwFocus(this);
        }
        else
        {
            setFlag(Flag.invisible);
        }
    }

    void setVisible() { clearFlag(Flag.invisible); }
    void clearVisible() { setFlag(Flag.invisible); }

    bool active() const { return (flags_ & Flag.inactive) == 0; }

    bool activeR() const
    {
        Rebindable!(const Widget) o = this;
        while (o !is null)
        {
            if (!o.active())
                return false;
            o = o.parent_;
        }
        return true;
    }

    void activate()
    {
        if (!active())
        {
            clearFlag(Flag.inactive);
            if (activeR())
            {
                redraw();
                redrawLabel();
                handle(Event.activate);
                if (inside(fl.core.focus()))
                    fl.core.focus().takeFocus();
            }
        }
    }

    void deactivate()
    {
        if (activeR())
        {
            setFlag(Flag.inactive);
            redraw();
            redrawLabel();
            handle(Event.deactivate);
            fl.core.throwFocus(this);
        }
        else
        {
            setFlag(Flag.inactive);
        }
    }

    bool output() const { return (flags_ & Flag.output) != 0; }
    void setOutput() { setFlag(Flag.output); }
    void clearOutput() { clearFlag(Flag.output); }

    bool takesEvents() const
    {
        return (flags_ & (Flag.inactive | Flag.invisible | Flag.output)) == 0;
    }

    bool changed() const { return (flags_ & Flag.changed) != 0; }
    void setChanged() { setFlag(Flag.changed); }
    void clearChanged() { clearFlag(Flag.changed); }

    void clearActive() { setFlag(Flag.inactive); }
    void setActive() { clearFlag(Flag.inactive); }

    bool takeFocus()
    {
        if (!takesEvents()) return false;
        if (!visibleFocus()) return false;
        if (handle(Event.focus) == 0) return false;
        if (contains(fl.core.focus())) return true;
        fl.core.focus(this);
        return true;
    }

    void setVisibleFocus() { setFlag(Flag.visibleFocus); }
    void clearVisibleFocus() { clearFlag(Flag.visibleFocus); }
    void visibleFocus(bool v) { if (v) setVisibleFocus(); else clearVisibleFocus(); }
    bool visibleFocus() const { return (flags_ & Flag.visibleFocus) != 0; }

    /// Puts a pointer to the widget on the queue returned by
    /// fl.fl.core.readqueue(). This is the default behavior for every
    /// widget until callback() is set to something else.
    static void defaultCallback(Widget widget)
    {
        pushQueue(widget);
    }

    void doCallback(CallbackReason reason = CallbackReason.unknown)
    {
        doCallback(this, reason);
    }

    void doCallback(Widget widget, CallbackReason reason = CallbackReason.unknown)
    {
        fl.core.callbackReason(reason);
        if (callback_ !is null)
        {
            auto wp = WidgetTracker(this);
            callback_(widget);
            if (wp.deleted()) return;
            clearChanged();
        }
        else
        {
            defaultCallback(widget);
        }
    }

    bool contains(const(Widget) w) const
    {
        Rebindable!(const Widget) o = w;
        while (o !is null)
        {
            if (o is this) return true;
            o = o.parent_;
        }
        return false;
    }

    bool inside(const(Widget) w) const
    {
        return w is null ? false : w.contains(this);
    }

    void redraw() { damage(damageAll); }

    /**
     * Ported from `Fl_Widget::redraw_label()` (`src/Fl.cxx`), backed by
     * `fl.platform_x11.flushDamage()`'s real per-rectangle damage
     * handling (see `damage(Damage,x,y,w,h)`
     * below). A widget with no solid background needs its *parent* to
     * repaint the thin strip around it (the parent owns those pixels);
     * a widget whose label sits *outside* its own bounds (`alignment()`
     * set and not `alignInside`) damages just that computed bounding
     * box instead of the whole window; otherwise (label drawn inside
     * the widget) a plain whole-widget `damage(damageAll)` covers it.
     */
    void redrawLabel()
    {
        auto win = window();
        if (win is null) return;

        // Widgets without a solid background need a parent to redraw,
        // since it is responsible for redrawing the background...
        if (!fl.core.boxBg(box_))
        {
            int X = x_ > 0 ? x_ - 1 : 0;
            int Y = y_ > 0 ? y_ - 1 : 0;
            win.damage(damageAll, X, Y, w_ + 2, h_ + 2);
        }

        if (alignment() && !(alignment() & alignInside) && win.shown())
        {
            // If the label is not inside the widget, compute the
            // location of the label and redraw the window within that
            // bounding box...
            int W, H;
            measureLabel(W, H);
            W += 5; // Add a little to the size of the label to cover overflow
            H += 5;

            // FIXME (FLTK's own comment, kept): this assumes
            // measureLabel() returns the correct outline, which it
            // does not in all possible cases of alignment combined
            // with image and symbols.
            switch (alignment() & alignPositionMask)
            {
            case alignTopLeft:     win.damage(damageExpose, x_, y_ - H, W, H); break;
            case alignTop:         win.damage(damageExpose, x_ + (w_ - W) / 2, y_ - H, W, H); break;
            case alignTopRight:    win.damage(damageExpose, x_ + w_ - W, y_ - H, W, H); break;
            case alignLeftTop:     win.damage(damageExpose, x_ - W, y_, W, H); break;
            case alignRightTop:    win.damage(damageExpose, x_ + w_, y_, W, H); break;
            case alignLeft:        win.damage(damageExpose, x_ - W, y_ + (h_ - H) / 2, W, H); break;
            case alignRight:       win.damage(damageExpose, x_ + w_, y_ + (h_ - H) / 2, W, H); break;
            case alignLeftBottom:  win.damage(damageExpose, x_ - W, y_ + h_ - H, W, H); break;
            case alignRightBottom: win.damage(damageExpose, x_ + w_, y_ + h_ - H, W, H); break;
            case alignBottomLeft:  win.damage(damageExpose, x_, y_ + h_, W, H); break;
            case alignBottom:      win.damage(damageExpose, x_ + (w_ - W) / 2, y_ + h_, W, H); break;
            case alignBottomRight: win.damage(damageExpose, x_ + w_ - W, y_ + h_, W, H); break;
            default:
                win.damage(damageAll);
                break;
            }
        }
        else
        {
            // The label is inside the widget, so just redraw the widget itself...
            damage(damageAll);
        }
    }

    Damage damage() const { return damage_; }
    void clearDamage(Damage c = 0) { damage_ = cast(ubyte) c; }

    /**
     * Sets the whole-widget damage bits. Ported from
     * `Fl_Widget::damage(uchar)` (`src/Fl.cxx`). For a window, this
     * also invalidates any accumulated partial-damage rectangle,
     * matching FLTK's own "damage
     * entire window by deleting the region" comment exactly: once the
     * *whole* window is damaged, any previously-accumulated sub-
     * rectangle from `damage(Damage,x,y,w,h)` below is moot, so
     * `fl.platform_x11.flushDamage()` should draw completely unclipped
     * on its next pass rather than clipping to a now-meaningless
     * partial rectangle.
     */
    void damage(Damage c)
    {
        if (type_ < windowTypeTag)
        {
            damage(c, x_, y_, w_, h_);
        }
        else
        {
            auto win = asWindow();
            if (win !is null) win.clearDamageRegion();
            damage_ |= cast(ubyte) c;
        }
    }

    /**
     * Sets damage bits for a sub-rectangle of this widget. Ported from
     * `Fl_Widget::damage(uchar,int,int,int,int)` (`src/Fl.cxx`): walks
     * up marking every ancestor between here and the top-level window
     * with `damageChild` (the original `c` only applies at this
     * widget's own level), then clips `(x,y,w,h)` to the window's
     * bounds and accumulates it into that window's real damage
     * rectangle.
     * `(x,y,w,h)` are already window-relative by the time they reach
     * here regardless of nesting depth, matching FLTK's own widget
     * coordinate model (every `Widget.x()`/`y()` is relative to its
     * enclosing *window*, not its immediate parent) -- no coordinate
     * transformation is needed while walking up.
     */
    void damage(Damage c, int x, int y, int w, int h)
    {
        Widget wi = this;
        Damage bits = c;
        while (wi.type_ < windowTypeTag)
        {
            wi.damage_ |= cast(ubyte) bits;
            wi = wi.parent_;
            if (wi is null) return;
            bits = damageChild;
        }

        // Clip the damage to the window and quit if none.
        if (x < 0) { w += x; x = 0; }
        if (y < 0) { h += y; y = 0; }
        if (w > wi.w_ - x) w = wi.w_ - x;
        if (h > wi.h_ - y) h = wi.h_ - y;
        if (w <= 0 || h <= 0) return;

        if (x == 0 && y == 0 && w == wi.w_ && h == wi.h_)
        {
            // Damage covers the entire window -- matches FLTK's
            // own shortcut, which also deletes any accumulated region.
            wi.damage(bits);
            return;
        }

        wi.damage_ |= cast(ubyte) bits;
        auto win = wi.asWindow();
        if (win !is null) win.accumulateDamageRect(x, y, w, h);
    }

    void measureLabel(out int w, out int h) const { label_.measure(w, h); }

    /// Returns the window widget containing this widget -- a sub-window
    /// if this widget is inside one, otherwise the top-level window.
    /// For a Window widget itself, returns its *parent* window, not
    /// itself (FLTK's own doc note). Ported from
    /// `Fl_Widget::window()` (`src/Fl_Window.cxx`). The walk
    /// stops at the nearest enclosing window, which is a subwindow when
    /// there is one.
    Window window() const
    {
        Rebindable!(const Widget) o = parent_;
        while (o !is null)
        {
            if (o.type() >= windowTypeTag) return cast(Window) o.asWindow();
            o = o.parent_;
        }
        return null;
    }

    /// Returns the top-level window containing this widget (never a
    /// sub-window, even if there is one). Ported from
    /// `Fl_Widget::top_window()` (`src/Fl_Window.cxx`).
    Window topWindow() const
    {
        Rebindable!(const Widget) w = this;
        while (w.parent_ !is null) w = w.parent_;
        return cast(Window) w.asWindow();
    }

    /// Finds this widget's x/y offset relative to its top-level window,
    /// walking up through any sub-windows along the way. Returns that
    /// top-level window, or null if this widget isn't in one at all.
    /// Ported from `Fl_Widget::top_window_offset()`
    /// (`src/Fl_Window.cxx`).
    Window topWindowOffset(out int xoff, out int yoff) const
    {
        xoff = 0;
        yoff = 0;
        Rebindable!(const Widget) w = this;
        while (w !is null && w.window() !is null)
        {
            xoff += w.x();
            yoff += w.y();
            w = w.window();
        }
        return w !is null ? cast(Window) w.asWindow() : null;
    }

    FlGroup asGroup() { return null; }
    const(FlGroup) asGroup() const { return null; }

    Window asWindow() { return null; }
    const(Window) asWindow() const { return null; }

    bool useAccentsMenu() const { return (flags_ & Flag.macUseAccentsMenu) != 0; }

    void shortcutLabel(bool value)
    {
        if (value) setFlag(Flag.shortcutLabel);
        else clearFlag(Flag.shortcutLabel);
    }

    bool shortcutLabel() const { return (flags_ & Flag.shortcutLabel) != 0; }

    /**
     * Internal use only. Returns the Unicode code point of the '&x'
     * shortcut in t, or 0 if there isn't one. A literal '&' is written
     * as '&&' (and does not itself count as a shortcut).
     */
    static uint labelShortcut(string t)
    {
        if (t is null) return 0;

        size_t i = 0;
        while (true)
        {
            if (i >= t.length) return 0;
            if (t[i] == '&')
            {
                size_t j = i + 1;
                if (j >= t.length) return 0;
                dchar s = decode(t, j);
                if (s == '&')
                    i++; // "&&": skip the first '&'; the loop's i++ below skips the second
                else
                    return cast(uint) s;
            }
            i++;
        }
    }

    /**
     * Internal use only. Returns true if t contains a '&x' shortcut
     * (see labelShortcut()) matching the key entered in the current
     * event. Must only be called from handle()/a callback in response
     * to a keypress event (FL_KEYDOWN/FL_SHORTCUT). If requireAlt is
     * true, the Alt modifier must also be held.
     */
    static bool testShortcut(string t, bool requireAlt = false)
    {
        if (t is null) return false;
        if (requireAlt && !fl.core.eventAlt()) return false;

        string text = fl.core.eventText();
        dchar c = 0;
        if (text.length > 0)
        {
            size_t idx = 0;
            c = decode(text, idx);
        }
        // TODO: FLTK also has a macOS-only extra check here
        // (Fl_System_Driver::need_test_shortcut_extra(), overridden only
        // by the Darwin driver) that re-derives c from event_key() when
        // Alt is down, so underline shortcuts behave like Windows/Linux.
        // macOS is out of scope for this port (see CONVENTIONS.md), and the
        // default -- what X11/Wayland/Windows use too -- is a no-op, so
        // it's skipped rather than faked.
        if (c == 0) return false;

        return cast(uint) c == labelShortcut(t);
    }

    /// Same as testShortcut(label()), but only if shortcutLabel() is
    /// set (label() is allowed to be used as a shortcut source).
    bool testShortcut()
    {
        if (!shortcutLabel()) return false;
        return testShortcut(label());
    }

    protected
    {
        /// Draws box() at this widget's own bounds, in color(). Every
        /// boxtype fl.core.boxTable has metrics for is a real, drawable
        /// case in fl.draw.drawBoxAt().
        /// Ported from Fl_Widget::draw_box(): this 0-arg overload is the
        /// one FLTK's own version calls
        /// `draw_backdrop()` from right after drawing the box fill -- the
        /// *other* `drawBox()` overloads below deliberately don't (matching
        /// FLTK: only the 0-arg one does), which is what makes
        /// `alignImageBackdrop` (FLTK's `FL_ALIGN_IMAGE_BACKDROP`, "back"
        /// in test/label.d) actually draw its image.
        ///
        /// These three overloads are `drawBoxAt()`'s single most common
        /// caller (virtually every ordinary widget's own `draw()`
        /// eventually reaches one of them), and this is exactly the
        /// "caller's responsibility" spot `fl.draw.drawBoxAt()`'s own
        /// module doc comment documents as replacing FLTK's
        /// process-wide `draw_it_active` auto-dim flag: dimming this
        /// call's fill color when `!activeR()` is what keeps a
        /// deactivated `FlGroup`'s contents evenly greyed, matching
        /// FLTK's real behavior, rather than only its
        /// *label* (`drawLabel()`, below) ever dimming while the box
        /// itself stays full color.
        ///
        /// Dimming the *fill* color
        /// passed to `drawBoxAt()` (above) isn't the whole story -- the
        /// beveled *border/frame* half of every classic up/down boxtype
        /// (`flUpFrame()`/`flDownFrame()`/etc., `fl.draw`) is drawn via a
        /// completely separate mechanism (`grayRampChar()`'s gray-ramp
        /// table) that never derives from the fill color at all, so
        /// button bevels/outlines and slider "decorations" (the
        /// thin-down-box bevel drawn around a slider's thumb/ticks)
        /// need their own dimming too. `fldraw.drawBoxActive()` (the direct
        /// equivalent of FLTK's own `Fl_Widget::draw_box()` setting
        /// its process-wide `draw_it_active` flag around the identical
        /// call) tells `grayRampChar()` to swap to its dimmed ramp table
        /// for the duration of this call.
        void drawBox() const
        {
            fldraw.drawBoxActive(activeR());
            fldraw.drawBoxAt(box_, x_, y_, w_, h_, activeR() ? color_ : fldraw.inactive(color_));
            fldraw.drawBoxActive(true);
            drawBackdrop();
        }
        /// Draws boxtype t at this widget's own bounds, in color c.
        void drawBox(Boxtype t, Color c) const
        {
            fldraw.drawBoxActive(activeR());
            fldraw.drawBoxAt(t, x_, y_, w_, h_, activeR() ? c : fldraw.inactive(c));
            fldraw.drawBoxActive(true);
        }
        /// Draws boxtype t at (x,y,w,h), in color c.
        void drawBox(Boxtype t, int x, int y, int w, int h, Color c) const
        {
            fldraw.drawBoxActive(activeR());
            fldraw.drawBoxAt(t, x, y, w, h, activeR() ? c : fldraw.inactive(c));
            fldraw.drawBoxActive(true);
        }

        /// If alignImageBackdrop is set, draws image() (or deimage()
        /// when inactive and a deimage exists) centered over the
        /// widget's own bounds. Ported from Fl_Widget::draw_backdrop()
        /// (src/fl_boxtype.cxx). Unlike fl.draw's own image-aware
        /// fl_draw() overload (which deliberately ignores
        /// alignImageBackdrop, deferring to this method instead -- see
        /// that function's own doc comment), this *is* the real
        /// alignImageBackdrop handler: drawBox() calls this
        /// unconditionally right after drawing the box itself, matching
        /// FLTK's own Fl_Widget::draw_box() exactly.
        void drawBackdrop() const
        {
            if (!(alignment() & alignImageBackdrop)) return;
            Image img = cast(Image) image();
            if (img !is null && deimage() !is null && !activeR())
                img = cast(Image) deimage();
            if (img !is null)
                img.draw(x_ + (w_ - img.w()) / 2, y_ + (h_ - img.h()) / 2);
        }

        void drawFocus() const { drawFocus(box_, x_, y_, w_, h_, color_); }

        void drawFocus(Boxtype t, int x, int y, int w, int h) const
        {
            drawFocus(t, x, y, w, h, color_);
        }

        /// Ported from Fl_Widget::draw_focus() (src/Fl_Widget.cxx):
        /// `drawBoxFocus(bt, x, y, w, h, FL_BLACK, bg)` -- see that
        /// function's own doc comment (fl.draw) for the dashed-rect
        /// mechanism and what's simplified relative to FLTK.
        void drawFocus(Boxtype t, int x, int y, int w, int h, Color bg) const
        {
            if (!fl.core.visibleFocus()) return;
            if (!visibleFocus()) return;
            fldraw.drawBoxFocus(t, x, y, w, h, black, bg);
        }

        /// Draws the label at its default position, inset from box()
        /// by its dx/dy/dw/dh insets. Ported from
        /// Fl_Widget::draw_label() (src/fl_labeltype.cxx): also nudges
        /// 3px in from a left/right-aligned edge, but only when the
        /// widget is wide enough (>11px) for that to still leave room.
        void drawLabel() const
        {
            int X = x_ + fl.core.boxDx(box_);
            int W = w_ - fl.core.boxDw(box_);
            if (W > 11 && (alignment() & (alignLeft | alignRight)))
            {
                X += 3;
                W -= 6;
            }
            drawLabel(X, y_ + fl.core.boxDy(box_), W, h_ - fl.core.boxDh(box_));
        }

        /// Draws the label within an arbitrary (x,y,w,h), at this
        /// widget's own alignment() -- unless alignment() places the
        /// label *outside* the widget (any of the low 4 align bits set
        /// without alignInside), in which case this is a no-op: an
        /// outside label is drawn by the parent FlGroup instead (see
        /// fl.group's drawOutsideLabel()), not by the widget itself.
        void drawLabel(int x, int y, int w, int h) const
        {
            if ((alignment() & 15) && !(alignment() & alignInside)) return;
            drawLabel(x, y, w, h, alignment());
        }

        /// Draws the label within an arbitrary (x,y,w,h) at an
        /// arbitrary alignment, unconditionally (skips the outside-label
        /// gating the 4-arg overload does) -- for a caller that wants
        /// to force the label to draw somewhere specific.
        void drawLabel(int x, int y, int w, int h, Align a) const
        {
            // Sets fl.draw's fl_draw_shortcut flag for the duration of
            // this draw so '&'-shortcut markers in the label get
            // stripped and underlined instead of drawn literally --
            // matches FLTK's own set/clear wrapping in
            // Fl_Widget::draw_label(X,Y,W,H,a) (src/fl_labeltype.cxx).
            if (flags_ & Flag.shortcutLabel) fldraw.fl_draw_shortcut = 1;
            scope(exit) fldraw.fl_draw_shortcut = 0;

            // A plain field-wise copy, like FLTK's `Fl_Label l1 =
            // label_;` -- cast away const rather than leaving it
            // implicit, since Label carries Image references (D
            // refuses an implicit const-struct copy when any field is
            // a reference type). Safe here: only l1.color/l1.image are
            // ever mutated below; the underlying Image/deimage objects
            // themselves, and text, are never written through l1.
            Label l1 = cast(Label) label_;
            if (!activeR())
            {
                l1.color = fldraw.inactive(l1.color);
                if (l1.deimage !is null) l1.image = l1.deimage;
            }
            l1.draw(x, y, w, h, a);
        }
    }
}

// -----------------------------------------------------------------------
// Default callback queue.
//
// Ported from the file-static obj_queue/obj_head/obj_tail state in
// src/Fl_Widget.cxx. Every widget without an explicit callback() uses
// Widget.defaultCallback, which pushes itself onto this queue; it is
// read out via fl.fl.core.readqueue() (Fl::readqueue() FLTK).
// -----------------------------------------------------------------------

private enum queueSize = 20;
private Widget[queueSize] objQueue;
private int objHead, objTail;

private void pushQueue(Widget widget)
{
    objQueue[objHead++] = widget;
    if (objHead >= queueSize) objHead = 0;
    if (objHead == objTail)
    {
        objTail++;
        if (objTail >= queueSize) objTail = 0;
    }
}

package(fl) Widget widgetQueuePop()
{
    if (objTail == objHead) return null;
    Widget widget = objQueue[objTail++];
    if (objTail >= queueSize) objTail = 0;
    return widget;
}

/// Removes all pending entries for w from the default callback queue.
/// Only called from Widget's destructor when it uses defaultCallback.
private void cleanupReadqueue(Widget w)
{
    if (objTail == objHead) return;

    int oldHead = objHead;
    int entry = objTail;
    objHead = objTail;
    for (;;)
    {
        Widget o = objQueue[entry++];
        if (entry >= queueSize) entry = 0;
        if (o !is w)
        {
            objQueue[objHead++] = o;
            if (objHead >= queueSize) objHead = 0;
        }
        if (entry == oldHead) break;
    }
}

unittest
{
    // userData(): a per-widget object slot, empty by default.
    static class TestWidget : Widget
    {
        this() { super(0, 0, 10, 10); }
        override void draw() {}
    }
    static class Payload { int n; this(int n) { this.n = n; } }

    auto w = new TestWidget();
    assert(w.userData() is null);
    auto p = new Payload(7);
    w.userData(p);
    assert(w.userData() is p);
    assert((cast(Payload) w.userData()).n == 7);
    w.userData(null);
    assert(w.userData() is null);
}

unittest
{
    static class TestWidget : Widget
    {
        this() { super(0, 0, 10, 10); }
        override void draw() {}
    }

    auto w = new TestWidget();
    assert(w.x == 0 && w.w == 10);
    assert(w.box == Boxtype.noBox);
    assert(w.when == whenRelease);

    w.label = "hi";
    assert(w.label == "hi");
    assert(!w.isLabelCopied);

    w.copyLabel("owned");
    assert(w.label == "owned");
    assert(w.isLabelCopied);

    // Callbacks are closures: no void* user-data slot needed to pass
    // state into them, just capture it directly.
    int calls;
    Widget seenSender;
    auto expectedId = 42;
    w.callback((Widget sender) {
        calls++;
        seenSender = sender;
        assert(expectedId == 42);
    });
    w.doCallback();
    assert(calls == 1);
    assert(seenSender is w);

    assert(w.active);
    w.deactivate();
    assert(!w.active);
    w.activate();
    assert(w.active);

    assert(w.visible);
    w.hide();
    assert(!w.visible);
    w.show();
    assert(w.visible);
}

unittest
{
    // Widgets created with no callback push themselves onto the default
    // queue, readable via fl.fl.core.readqueue().
    static class TestWidget : Widget
    {
        this() { super(0, 0, 1, 1); }
        override void draw() {}
    }

    auto w = new TestWidget();
    w.doCallback();
    assert(fl.core.readqueue() is w);
}

unittest
{
    static class TestWidget : Widget
    {
        this() { super(0, 0, 1, 1); }
        override void draw() {}
    }

    auto parent = new TestWidget();
    auto child = new TestWidget();
    // contains()/inside() only resolve through a real parent_ chain,
    // which requires FlGroup; exercised in fl.group's unittests instead.
    assert(parent.contains(parent));
    assert(!parent.contains(child));
    assert(!parent.inside(child));
}

unittest
{
    // labelShortcut() finds the '&x' shortcut character, treats '&&' as
    // a literal '&', and returns 0 when there isn't one.
    assert(Widget.labelShortcut("&Open") == 'O');
    assert(Widget.labelShortcut("Save &As") == 'A');
    assert(Widget.labelShortcut("A && B") == 0); // "&&" is literal, no shortcut after it
    assert(Widget.labelShortcut("No shortcut here") == 0);
    assert(Widget.labelShortcut("trailing &") == 0);
    assert(Widget.labelShortcut(null) == 0);
    assert(Widget.labelShortcut("") == 0);
}

unittest
{
    // testShortcut(text) matches the label's '&x' shortcut against
    // fl.core.eventText()'s first character.
    fl.core.eText_ = "a";
    assert(Widget.testShortcut("&Apple") == false); // case-sensitive: 'A' != 'a'
    assert(Widget.testShortcut("&apple") == true);
    assert(Widget.testShortcut("no shortcut") == false);

    fl.core.eText_ = "";
    assert(Widget.testShortcut("&apple") == false); // no event text to match

    fl.core.eState_ = 0;
    fl.core.eText_ = "a";
    assert(Widget.testShortcut("&apple", true) == false); // requireAlt, but Alt isn't down

    fl.core.eState_ = stateAlt;
    assert(Widget.testShortcut("&apple", true) == true);

    fl.core.eText_ = "";
    fl.core.eState_ = 0;
}

unittest
{
    // The no-arg testShortcut() only fires when shortcutLabel() is set
    // (matching FLTK gating it on the SHORTCUT_LABEL flag).
    static class TestWidget : Widget
    {
        this(string label) { super(0, 0, 1, 1, label); }
        override void draw() {}
    }

    auto w = new TestWidget("&go");
    fl.core.eText_ = "g";

    assert(!w.shortcutLabel());
    assert(w.testShortcut() == false);

    w.shortcutLabel(true);
    assert(w.testShortcut() == true);

    fl.core.eText_ = "";
}

unittest
{
    // Label.measure()/draw() with no text: the "no image support
    // either, so nothing to draw/size" early-out (see Label.draw()'s
    // doc comment) -- headless-safe since it never reaches fl.draw.
    Label l;
    int w, h;
    l.measure(w, h);
    assert(w == 0 && h == 0);

    l.draw(0, 0, 100, 20, alignCenter); // just confirm it doesn't throw
}

unittest
{
    // noLabel/multiLabel/iconLabel/imageLabel draw nothing (the
    // fl_no_label-equivalent branch) even with real text -- also
    // headless-safe, since that branch never reaches fl.draw either.
    Label l;
    l.text = "hidden";
    l.type = Labeltype.noLabel;
    l.draw(0, 0, 100, 20, alignCenter); // no-op; just confirm it doesn't throw
}

unittest
{
    // drawLabel()'s outside-label gating: an alignment with a low
    // bit set (e.g. alignBottom, "outside the box, below it") and no
    // alignInside means the 4-arg drawLabel(x,y,w,h) is a no-op --
    // outside labels are drawn by the parent FlGroup instead (see
    // fl.group's drawOutsideLabel()). Headless-safe: a true no-op
    // never reaches fl.draw.
    static class TestWidget : Widget
    {
        this() { super(0, 0, 50, 20, "x"); }
        override void draw() {}
    }

    auto w = new TestWidget();
    w.alignment(alignBottom); // outside, below -- not alignInside
    w.drawLabel(0, 0, 50, 20); // just confirm it doesn't throw
}

unittest
{
    // drawFocus(): both guards (Fl::visible_focus() and the widget's
    // own visibleFocus()) still gate it correctly now that it does
    // real drawing, and the drawing path itself doesn't throw headless
    // (no display -> fl.draw's primitives early-return safely, same as
    // every other draw()-adjacent unittest in this file).
    static class TestWidget : Widget
    {
        this() { super(0, 0, 50, 20, "x"); }
        override void draw() {}
    }

    auto w = new TestWidget();

    fl.core.visibleFocus(false);
    w.setVisibleFocus();
    w.drawFocus(); // no-op: fl.core.visibleFocus() is off

    fl.core.visibleFocus(true);
    w.clearVisibleFocus();
    w.drawFocus(); // no-op: this widget's own visibleFocus() is off

    w.setVisibleFocus();
    w.drawFocus(); // both guards clear -- reaches fl.draw for real
    w.drawFocus(Boxtype.downBox, 0, 0, 50, 20);
    w.drawFocus(Boxtype.downBox, 0, 0, 50, 20, white);

    fl.core.visibleFocus(true); // restore the module default for later tests
}

// window()/topWindow()/topWindowOffset() -- pure widget-tree walking, no
// X server needed (never calls show()/hide()). Real subwindows exist in
// this port, and window()/
// topWindow()/topWindowOffset() need no special-casing for it: all
// three are written in terms of the generic `.window()`/
// `.parent()` walk rather than any single-top-level-window assumption
// (see this test's own second unittest block below for a genuine
// window-inside-window case exercising that).
unittest
{
    import fl.group : FlGroup;
    import fl.window : Window;
    import fl.box : Box;

    FlGroup.current(null);

    auto win = new Window(10, 20, 400, 300, "outer");
    auto grp = new FlGroup(50, 60, 200, 150);
    auto box = new Box(5, 5, 20, 20); // relative to grp: (55,65) in win
    grp.end();
    win.end();
    FlGroup.current(null);

    // A widget with no window ancestor at all.
    auto orphan = new Box(0, 0, 10, 10);
    assert(orphan.window() is null);
    assert(orphan.topWindow() is null);

    // A direct child of the window.
    assert(grp.window() is win);
    assert(grp.topWindow() is win);

    // A grandchild, nested inside the plain FlGroup.
    assert(box.window() is win);
    assert(box.topWindow() is win);

    // The window widget itself has no *parent* window (FLTK's own
    // documented distinction: window() on a Window returns its parent
    // window, not itself) -- but topWindow() called on a Window that
    // has no parent window returns *itself* (its own parent-walk loop
    // never executes, so `w` stays `this`, and `this->as_window()` is
    // non-null since it really is a window).
    assert(win.window() is null);
    assert(win.topWindow() is win);

    int xoff, yoff;
    auto topWin = box.topWindowOffset(xoff, yoff);
    assert(topWin is win);
    // box is at (5,5) within grp, grp is at (50,60) within win -- no
    // subwindows to walk through, so this is a single hop with box's
    // own parent-relative x/y (matching FLTK: topWindowOffset()
    // accumulates each widget's own x()/y() once per window hop, not
    // the full absolute screen position).
    assert(xoff == 5 && yoff == 5);

    int xoff2, yoff2;
    assert(orphan.topWindowOffset(xoff2, yoff2) is null);
    assert(xoff2 == 0 && yoff2 == 0);
}

// Genuine window-inside-window nesting (never calls show()/hide(), so
// no real X subwindow is created -- pure widget-tree-walking coverage).
unittest
{
    import fl.group : FlGroup;
    import fl.window : Window;
    import fl.box : Box;

    FlGroup.current(null);

    auto outer = new Window(10, 20, 400, 300, "outer");
    // A subwindow's x()/y() are relative to its immediate window
    // ancestor, exactly like any other embedded widget's -- (30,40)
    // here means "30,40 within outer", not screen-absolute.
    auto sub = new Window(30, 40, 200, 150, "sub");
    auto box = new Box(5, 5, 20, 20); // relative to sub
    sub.end();
    outer.end();
    FlGroup.current(null);

    // window() stops at the *nearest* window ancestor, not the
    // top-level one -- box's is sub, not outer.
    assert(box.window() is sub);
    assert(box.topWindow() is outer);

    // For the subwindow itself: window() returns its *parent* window
    // (FLTK's own documented distinction, same as the plain-window
    // case above), and topWindow() walks all the way to the real root.
    assert(sub.window() is outer);
    assert(sub.topWindow() is outer);

    // topWindowOffset() now genuinely exercises two window-type hops
    // (box -> sub -> outer) instead of the single hop every other test
    // in this file exercises -- accumulates box's own x/y, then sub's,
    // matching FLTK's real multi-level-nesting algorithm exactly.
    int xoff, yoff;
    auto topWin = box.topWindowOffset(xoff, yoff);
    assert(topWin is outer);
    assert(xoff == 5 + 30 && yoff == 5 + 40);

    destroy(box);
    destroy(sub);
    destroy(outer);
}

unittest
{
    // damage(Damage,x,y,w,h): the
    // ancestor walk marks every parent up to (not including) the
    // window with damageChild -- only the *starting* widget keeps the
    // original bits -- then clips the rectangle to the window's own
    // bounds (matching FLTK's Fl_Widget::damage(fl,X,Y,W,H)
    // exactly), collapsing to a plain whole-widget damage() call if
    // the clipped rectangle covers the entire window, or silently
    // dropping it if clipping leaves nothing. Doesn't (and can't,
    // headlessly) verify the accumulated rectangle itself -- that
    // lives in fl.platform_x11's private per-window record, invisible
    // without a live X display and a real createWindow() call -- but
    // accumulateDamageRect()/clearDamageRegion() are confirmed safe
    // no-ops when the window was never actually shown() (not in
    // fl.platform_x11's tracked list at all), and every widget-tree-
    // visible half (the damage_ bitmasks) is fully exercised.
    import fl.group : FlGroup;
    import fl.box : Box;

    FlGroup.current(null);
    auto win = new Window(200, 150, "damage test");
    auto grp = new FlGroup(10, 10, 100, 100);
    auto box = new Box(5, 5, 20, 20); // absolute (15,15) within win
    grp.end();
    win.end();
    FlGroup.current(null);

    // A rectangle fully within the window.
    win.clearDamage();
    grp.clearDamage();
    box.clearDamage();
    box.damage(damageExpose, 15, 15, 20, 20);
    assert(box.damage() == damageExpose); // the starting widget keeps the original bits
    assert(grp.damage() == damageChild);  // every ancestor above it gets damageChild instead
    assert(win.damage() == damageChild);

    // Negative x/y clamp (and shrink w/h to match); a rectangle that
    // ends up covering the *entire* window after clipping collapses to
    // the whole-widget damage() shortcut rather than staying "partial".
    win.clearDamage();
    grp.clearDamage();
    box.clearDamage();
    box.damage(damageExpose, -5, -5, 210, 160); // clips to exactly (0,0,200,150) == the whole window
    assert(win.damage() == damageChild);

    // A rectangle entirely outside the window (negative width/height
    // after clipping) is silently dropped -- no window damage at all.
    win.clearDamage();
    grp.clearDamage();
    box.clearDamage();
    box.damage(damageExpose, 500, 500, 20, 20);
    assert(box.damage() == damageExpose); // ancestor walk itself still ran...
    assert(grp.damage() == damageChild);
    assert(win.damage() == 0); // ...but the final window-level marking was skipped

    destroy(win); // also exercises Window's dtor with damage state present, safely
    FlGroup.current(null);
}

unittest
{
    // redrawLabel(): the two
    // FLTK `if` blocks are independent (not if/else-if): a non-
    // solid-background widget (noBox) *always* damages its parent
    // window in a +2px-expanded rectangle regardless of alignment, and
    // *separately* either damages the window again (a computed outside-
    // label rectangle, only reached once window().shown() is true --
    // untestable headlessly, no live X display to actually show()
    // against) or falls to damaging itself (the else branch, taken
    // here since alignment() is 0/falsy by default -- no explicit
    // alignment() call -- and again once shown() is checked and found
    // false for an outside alignment on an unshown window).
    //
    // Important invariant this test also exercises (not
    // redrawLabel()-specific, but easy to trip over when reading these
    // assertions): *any* damage reaching a nested widget always
    // propagates at least damageChild up to its window too -- calling
    // plain damage(damageAll) on a widget several levels deep is never
    // "invisible" to the window the way "window().damage() == 0" might
    // suggest; only a call that returns *before* reaching the window
    // at all (e.g. clipped away to nothing, see the damage() test
    // above) leaves the window's own damage() truly untouched.
    import fl.group : FlGroup;
    import fl.box : Box;

    FlGroup.current(null);
    auto win = new Window(200, 150, "redrawLabel test");

    // noBox (no solid background), default (falsy) alignment: the
    // box_bg block damages the *window* directly (damageAll, since
    // it's called straight on win, never downgraded to damageChild by
    // an ancestor walk that never runs), AND (independently) the else
    // branch damages the widget itself, which propagates damageChild
    // up to the window too -- so the window ends up with *both* bits.
    auto noBg = new Box(Boxtype.noBox, 10, 10, 50, 20, "x");
    win.clearDamage();
    noBg.clearDamage();
    noBg.redrawLabel();
    assert(noBg.damage() == damageAll);
    assert(win.damage() == (damageAll | damageChild));

    // flatBox (solid background), default (falsy) alignment: the
    // box_bg block is skipped entirely (solid background -- the
    // widget repaints its own edges), so only the else branch fires,
    // damaging the widget itself -- which still propagates damageChild
    // up to the window (see the invariant note above), just without
    // the extra damageAll bit noBg's case had.
    auto solidBg = new Box(Boxtype.flatBox, 70, 10, 50, 20, "y");
    win.clearDamage();
    solidBg.clearDamage();
    solidBg.redrawLabel();
    assert(solidBg.damage() == damageAll);
    assert(win.damage() == damageChild);

    // Outside alignment (alignTop) on a solid-background widget whose
    // *window* was never shown() (no live display in this test):
    // window().shown() gates the real outside-label-rectangle branch,
    // so this still falls to the else branch, exactly like the falsy-
    // alignment case above -- confirms the shown() guard itself, not
    // the branch it gates.
    auto outsideUnshown = new Box(Boxtype.flatBox, 70, 60, 50, 20, "label");
    outsideUnshown.alignment(alignTop);
    assert(!win.shown());
    win.clearDamage();
    outsideUnshown.clearDamage();
    outsideUnshown.redrawLabel();
    assert(outsideUnshown.damage() == damageAll);
    assert(win.damage() == damageChild);

    win.end();
    destroy(win);
    FlGroup.current(null);
}
