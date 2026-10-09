/*
 * Ported from FL/Fl_Window.H (FLTK 1.5.0). show()/hide()/shown() are
 * real on Linux, backed by fl.platform_x11 -- see that module's
 * top-of-file note for exactly what "real" means here (a minimal,
 * deliberately non-faithful-yet window-creation/event-loop path).
 * sizeRange()'s WM_NORMAL_HINTS negotiation is real (see
 * fl.platform_x11.sendSizeHints()) -- a cooperating window manager
 * actually enforces min/max/aspect/increment constraints.
 * default_size_range() is ported too (see its own doc comment) and
 * called automatically from show(), so a window that never calls
 * sizeRange() explicitly still gets a sensible computed range (fixed-
 * size if it has no resizable() widget, otherwise derived from that
 * widget's own clipped/capped size) instead of no hints at all.
 * cursor() changes real cursor shapes
 * (fl.platform_x11.setCursor(), an XDefineCursor() call) -- see that
 * function's doc comment for the handful of shapes still unsupported
 * (need a custom pixmap cursor). fullscreen()/fullscreenOff() are real
 * (fl.platform_x11.fullscreenOn()/fullscreenOff(), the EWMH
 * `_NET_WM_STATE_FULLSCREEN` protocol). maximize()/unMaximize() are real too,
 * built the same way (fl.platform_x11.maximizeOn()/maximizeOff(), EWMH
 * `_NET_WM_STATE_MAXIMIZED_VERT`/`_HORZ`). Externally-triggered
 * maximize/fullscreen changes (e.g. double-clicking the title bar) are
 * tracked too, via fl.platform_x11's PropertyNotify handling --
 * see setMaximizedFlag()'s and PropertyNotify's own doc comments.
 * Icons (`icon()`/`icons()` below) are real, backed by
 * fl.platform_x11's `setIcons()` real `_NET_WM_ICON` property.
 *
 * `modal()`/`setModal()`/`setNonModal()`/`freePosition()` are pure
 * per-window flag bookkeeping here, same as FLTK's own
 * `Fl_Window::set_modal()` et al. -- the *real* enforcement (a
 * `Fl::modal_`-equivalent global, event filtering, WM_TRANSIENT_FOR/
 * `_NET_WM_STATE_MODAL` hints) lives entirely in `fl.core`/
 * `fl.platform_x11`, not here, matching FLTK's own architecture
 * precisely (`Fl_Window::show()`/`hide()` contain no modal-specific
 * code at all FLTK either -- see `fl.core.modal()`'s doc comment
 * for the full mechanism). The constructor's own default `callback()`
 * (hide() + push onto the read queue, ported from
 * `Fl_Window::default_callback`/`Fl::default_atclose`) is what keeps
 * an ordinary window's OS close button working, since
 * `fl.platform_x11`'s `WM_DELETE_WINDOW` handling routes through real,
 * `modal()`-aware `Event.close` dispatch instead of an unconditional
 * direct destroy.
 *
 * `resize()`'s FLTK `resize_bug_fix` echo-prevention guard for
 * app-initiated moves/resizes is real (see `resizeBugFix_` below --
 * fl.platform_x11 calls resize() both ways). Windows is a second
 * backend (`version (Windows)` throughout, backed by
 * `fl.platform_win32`); Wayland and macOS have none.
 */
module fl.window;

import fl.group;
import fl.widget : Widget, Label;
import fl.image : Image, RGBImage;
import fl.bitmap : Bitmap;
import fl.tiled_image : TiledImage;
import fl.enumerations : Event, Cursor, Boxtype, Labeltype, damageChild, alignInside,
    alignCenter, alignClip;
import fl.filename : filenameName;
import fl.core;
import fldraw = fl.draw;
import core.memory : GC;
import std.algorithm.iteration : map;
import std.array : array;

version (linux)
{
    import fl.xlib : XlibWindow = Window;
    import platformX11 = fl.platform_x11;
}

version (Windows)
{
    import core.sys.windows.windef : Win32Window = HWND;
    import platformWin32 = fl.platform_win32;
}

/**
 * Mirrors FLTK's static `Fl_Window* resize_bug_fix` (`Fl_x.cxx`) --
 * see `Window.resize()`'s own doc comment for the full echo-prevention
 * mechanism this exists for. `fl.platform_x11`'s `ConfigureNotify`
 * handler sets this to the window in question immediately before
 * calling its `resize()`, so that override can tell "the window
 * manager already applied this geometry and is just reporting it" apart
 * from "the application asked for a new geometry directly."
 */
package(fl) Window resizeBugFix_;

class Window : FlGroup
{
    version (linux) private XlibWindow xid_;
    version (Windows) private Win32Window xid_;
    private bool shown_;

    private string xclass_;

    private
    {
        int minw_, minh_, maxw_, maxh_;
        int dw_, dh_;
        bool aspect_;
        bool sizeRangeSet_;
    }

    /// The default xclass used for any window that hasn't set its own
    /// (via `xclass(string)`) before `show()`. "fldtk" until changed --
    /// **deliberately not FLTK's own literal default ("FLTK")**:
    /// an fldtk-built app's `WM_CLASS`
    /// reading literally "FLTK" would misidentify it as FLTK
    /// itself to anything keying off that property (window-manager
    /// rules, `xprop`, etc.) -- ported from `Fl_Window::
    /// default_xclass()` (`src/Fl_Window.cxx`), same mechanism, only
    /// the sentinel string itself differs.
    private static string defaultXclass_;

    static string defaultXclass()
    {
        return defaultXclass_.length ? defaultXclass_ : "fldtk";
    }

    /// Sets the default xclass for all windows subsequently created
    /// (and shown) that don't set their own. Pass `null` to reset it
    /// back to "fldtk". Ported from `Fl_Window::default_xclass(const
    /// char*)`.
    static void defaultXclass(string xc)
    {
        defaultXclass_ = xc;
    }

    /// This window's own X11 WM_CLASS, or `defaultXclass()` if this
    /// window never set one. Ported from `Fl_Window::xclass() const`.
    string xclass() const
    {
        return xclass_.length ? xclass_ : defaultXclass();
    }

    /// Sets this window's own xclass. Also sets `defaultXclass()`, but
    /// only if nothing has set it yet -- matches FLTK's own
    /// documented side effect exactly ("If you call
    /// `Fl_Window::xclass(const char*)` for any window, then this also
    /// sets the default xclass, unless it has been set before").
    void xclass(string xc)
    {
        xclass_ = xc;
        if (xc.length && defaultXclass_ is null) defaultXclass_ = xc;
    }

    private RGBImage[] icons_;

    /// Process-wide fallback icon list, used by any window that hasn't
    /// set its own via `icons()`/`icon()` before `show()`. Ported from
    /// `Fl_Window::default_icons()`.
    private static RGBImage[] defaultIcons_;

    /// Backs `fl.platform_x11.setIcons()`'s fallback -- not exposed
    /// publicly (matching `iconsForWM()`'s own package-only scope just
    /// below).
    package(fl) static const(RGBImage)[] defaultIconsForWM()
    {
        return defaultIcons_;
    }

    /// Sets the process-wide default icon(s) for windows created (and
    /// shown) after this call -- doesn't affect already-created
    /// windows or ones that already set their own. Ported from
    /// `Fl_Window::default_icons(const Fl_RGB_Image*[], int)`; the D
    /// slice replaces the pointer+count pair, same substitution as
    /// everywhere else in this port a C array-plus-length crosses into
    /// D.
    ///
    /// **Deep-copies each image with `Image.copy()` here**, rather than
    /// storing the caller's own `RGBImage` references directly: the GC
    /// keeping a referenced object alive does nothing to protect
    /// against the caller explicitly calling `destroy()` on that same
    /// object right after, which is exactly the idiom FLTK's own doc
    /// comment licenses and every faithfully-ported sample naturally
    /// does
    /// (`test/device.d`: `Window.defaultIcon(rgbaIcon); destroy
    /// (rgbaIcon);`, transliterated straight from FLTK's own
    /// `delete rgba_icon;` right after `Fl_Window::default_icon()`).
    /// FLTK's version of that idiom is safe only because its own
    /// `Fl_X11_Screen_Driver::default_icons()` (`Fl_x.cxx`) immediately
    /// converts the images into the `_NET_WM_ICON` property's raw byte
    /// buffer and keeps *that*, never the `Fl_RGB_Image*` pointers
    /// themselves -- this port's own lazy, convert-at-window-creation
    /// design (`fl.platform_x11.setIcons()`/`iconsToProperty()`) needs
    /// its own equivalent eager copy for the same reason, so a
    /// `destroy()`d source image doesn't
    /// leave a later `setIcons()` call reading a live reference to
    /// a finalized object. This genuinely restores the "free the
    /// source immediately after" contract this doc comment promises.
    static void defaultIcons(RGBImage[] icons)
    {
        defaultIcons_ = icons.map!(i => cast(RGBImage) i.copy()).array;
    }

    /// Convenience one-icon form of `defaultIcons()`. Ported from
    /// `Fl_Window::default_icon(const Fl_RGB_Image*)`; `null` clears it
    /// (matching FLTK's own `count = 0` case).
    static void defaultIcon(RGBImage icon)
    {
        defaultIcons(icon is null ? [] : [icon]);
    }

    /// Backs `fl.platform_x11.setIcons()` -- this window's own icons
    /// (before falling back to `defaultIconsForWM()`), not exposed
    /// publicly since callers use `icons()`/`icon()` instead.
    package(fl) const(RGBImage)[] iconsForWM() const
    {
        return icons_;
    }

    /**
     * Sets this window's icon(s) -- shown by the window manager in the
     * taskbar/titlebar/alt-tab switcher, etc. Ported from
     * `Fl_Window::icons(const Fl_RGB_Image*[], int)`. Applied
     * immediately (via `fl.platform_x11.setIcons()`) if this window is
     * already `shown()`, matching FLTK's own "re-push if the X
     * resource already exists" behavior; otherwise takes effect at the
     * next `show()` (see `createWindow()`'s own call site). Passing an
     * empty array clears this window's own icons and falls back to
     * `defaultIconsForWM()` -- matching FLTK's identical
     * `icon_->count` fallback exactly (this is *not* the same as
     * `freeIcons()` below, which faithfully replicates a real FLTK
     * quirk instead -- see that method's own doc comment).
     */
    void icons(RGBImage[] imgs)
    {
        // Deep-copied for the same reason defaultIcons() copies its
        // own argument now -- see that method's doc comment for the
        // full story (a live crash from a caller destroy()ing its
        // source image right after handing it off, matching FLTK's
        // own "free immediately after" contract).
        icons_ = imgs.map!(i => cast(RGBImage) i.copy()).array;
        if (shown())
        {
            version (linux) platformX11.setIcons(this);
            version (Windows) platformWin32.setIcons(this);
        }
    }

    /// Convenience one-icon form of `icons()`. Ported from
    /// `Fl_Window::icon(const Fl_RGB_Image*)`; `null` clears this
    /// window's own icon(s) (matching FLTK's own `count = 0` case).
    void icon(RGBImage ic)
    {
        icons(ic is null ? [] : [ic]);
    }

    /**
     * Clears this window's own icon(s) (falling back to
     * `defaultIconsForWM()` on the *next* icon-property update).
     * Ported from `Fl_Window::free_icons()`. **Faithfully replicates a
     * real FLTK quirk, not silently corrected**: unlike `icons([])`
     * above, this does *not* immediately re-push `_NET_WM_ICON` even on
     * an already-`shown()` window -- FLTK's own `Fl_X11_Window_
     * Driver::free_icons()` just clears `icon_`'s fields, with no
     * `set_icons()` call anywhere in it, unlike `icons()`'s driver-level
     * counterpart which explicitly calls `set_icons()` right after its
     * own `free_icons()`. So on a shown window, calling `icons([])`
     * updates the on-screen icon right away; calling `freeIcons()`
     * alone leaves the previous icon showing until something else
     * (e.g. a later `icons()`/`icon()` call) triggers a repaint of the
     * property. Logged as an `FLTK_ISSUES.md` candidate rather than
     * fixed here, per this project's standing policy on suspected
     * FLTK inconsistencies.
     */
    void freeIcons()
    {
        icons_ = [];
    }

    /**
     * Ported from `Fl_Window::label(const char*)`, which resolves to
     * `Fl_Window::label(name, iconlabel())` and always calls
     * `pWindowDriver->label(name, mininame)` -- i.e. FLTK pushes
     * *every* `label()` call to the platform, not just the one made
     * before the window is first shown. This port's `Widget.label()`
     * would otherwise only ever touch the in-process `label_` field, with nothing
     * window-specific reacting to it; `createWindow()` reads the
     * current label once, at creation time, but a title set *after*
     * `show()` (e.g. a playback-
     * status update from a timer callback -- several of the newer
     * GIF-animation/pixmap samples do exactly this) needs its own
     * live push to reach the window manager.
     * Overriding `label()` here to also push the change live
     * via `fl.platform_x11.updateWindowLabel()` whenever this window is
     * already `shown()` (a no-op otherwise, matching FLTK's own
     * `if (shown() && !parent())` guard -- see that function's doc
     * comment). `Widget.copyLabel()` isn't overridden separately: it
     * already calls `label()` internally, and virtual dispatch means it
     * reaches this override for free on any `Window` instance.
     */
    override void label(string text)
    {
        super.label(text);
        if (shown()) version (linux) platformX11.updateWindowLabel(this);
    }

    /// D hides a base class's entire overload set once a derived class
    /// overrides even one overload of the same name -- without this,
    /// `Widget.label() const` (the getter) would become uncallable on
    /// any `Window`, since only the setter above is overridden here.
    alias label = Widget.label;

    private string iconlabel_;

    /// The window's icon-title override, or empty if none was ever set
    /// (in which case the icon name shown to the window manager is
    /// derived from `label()` instead -- see `fl.platform_x11.
    /// applyWindowLabel()`'s own fallback). Ported from `Fl_Window::
    /// iconlabel() const` (`FL/Fl_Window.H`).
    string iconlabel() const { return iconlabel_; }

    /**
     * Sets an explicit icon-title, distinct from the window's main
     * titlebar text. Ported from `Fl_Window::iconlabel(const char*)`
     * (`src/Fl_Window.cxx`), which resolves to `label(label(), iname)`
     * -- pushed live via `fl.platform_x11.updateWindowLabel()` when
     * already `shown()`, matching `label(string)`'s own re-application
     * behavior just above. Backs `fl.glut`'s `glutSetIconTitle()`
     * -- FLTK's `Fl_Glut_Window::iconlabel` is exactly this method.
     */
    void iconlabel(string iname)
    {
        iconlabel_ = iname;
        if (shown()) version (linux) platformX11.updateWindowLabel(this);
    }

    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        type(Widget.windowTypeTag);

        // Ported from Fl_Window::_Fl_Window() (src/Fl_Window.cxx): every
        // FLTK window gets an opaque flatBox background and no
        // in-window label by default -- box() otherwise defaults to
        // Widget's own noBox (paints nothing at all), and labeltype()
        // defaults to normalLabel (would draw the window's title string,
        // meant for the WM titlebar, as an actual centered label inside
        // the window body). Without this, a window with no covering
        // child widget shows whatever pixels were already in that
        // screen region before it was mapped -- not real alpha
        // transparency, just never-painted content -- which is exactly
        // what FLTK's box(FL_FLAT_BOX) call prevents.
        //
        // `noLabel` here is just the constructor's own initial default,
        // matching FLTK's `_Fl_Window()` -- `show()` (see that method)
        // is what actually applies
        // `fl.core.schemeBg()`'s `normalLabel`/alignment when the
        // "plastic" scheme is active, matching FLTK's own split
        // between constructor-time default and show()-time real
        // application exactly.
        box(Boxtype.flatBox);
        labeltype(Labeltype.noLabel);

        // Also from _Fl_Window(): a plain window doesn't proportionally
        // scale its children by default (unlike a bare FlGroup, whose
        // resizable() defaults to itself) -- the caller opts in
        // explicitly via resizable(someChild).
        resizable(null);

        // Ported from Fl_Window's own constructor
        // (`callback((Fl_Callback*)default_callback);`, src/Fl_Window.cxx)
        // plus what that default_callback actually does
        // (`Fl::atclose`/`Fl::default_atclose`, same file): hide()
        // this window, then still push it onto the read queue like any
        // other widget's default callback would. This is why a plain
        // FLTK window with no custom callback() set still closes
        // normally when its OS close button is clicked -- distinct
        // from (and overriding) the generic Widget.defaultCallback()
        // every *other* widget type falls back to, which only pushes
        // onto the queue and never hides anything. A caller who sets
        // their own callback() later (fl.ask's MessageDialog does)
        // simply replaces this, exactly matching FLTK's own
        // inheritance-based override.
        //
        // Needed because fl.core.handle()'s Event.close
        // case does real, modal()-aware
        // dispatch through doCallback(), so every window needs *some*
        // callback that actually closes it, matching FLTK exactly.
        callback((w) {
            auto win = cast(Window) w;
            if (win !is null) win.hide();
            Widget.defaultCallback(w);
        });

        // Matches FLTK's own `Fl_Window(int X,int Y,int W,int H,
        // const char *l)` constructor, which sets this flag
        // unconditionally too -- an explicit (X, Y) means the caller
        // wants this exact position honored, not left to the platform's
        // own default-placement heuristic. This matters even though
        // `resize()`'s own move-tracking also sets `Flag.forcePosition`
        // on any later `position()`/`resize()` call: that tracking only
        // fires once `shown()` is already true, so it can't cover a
        // window's very first placement -- exactly the case every
        // popup/tooltip/dialog window hits, since each is a fresh
        // `Window` (this 4-arg ctor) explicitly positioned via its own
        // constructor call or a `position()`/`hotspot()` call, then
        // shown for the first time. Without this, that first `show()`
        // fell through to `createWindow()`'s no-explicit-position
        // branch on Windows (`CW_USEDEFAULT`, added for the unrelated
        // "every unpositioned window opens in the same corner" bug) --
        // a real, reported bug: pulldown menus and tooltips appearing
        // in the wrong place (upper-left of the main window) instead of
        // at their computed position.
        forcePosition(true);
    }

    /// Same as this(x, y, w, h, label) but without an explicit
    /// position. Mirrors FLTK's "fix common user error of a
    /// missing end() with current(0)" trick: resets the currently-open
    /// group (if any) before construction, so a window built without
    /// an explicit position never accidentally becomes the child of a
    /// forgotten-open FlGroup. Explicitly undoes the 4-arg constructor's
    /// own `forcePosition(true)` -- unlike that constructor, this one
    /// really doesn't have a caller-requested position to honor (both
    /// constructors share one D delegating-constructor body, so the
    /// flag has to be set there and cleared back out here rather than
    /// the other way around).
    this(int w, int h, string label = null)
    {
        FlGroup.current(null);
        this(0, 0, w, h, label);
        forcePosition(false);
    }

    override Window asWindow() { return this; }
    override const(Window) asWindow() const { return this; }

    /**
     * Ported from Fl_Window::draw() (src/Fl_Window.cxx) -- NOT the same
     * as Fl_Group::draw() despite looking similar, and the difference
     * matters: it draws its own box at local (0,0), not at x()/y().
     * Every *child* widget's x()/y() is already relative to this
     * window's own top-left, so drawing them via FlGroup.drawChildren()
     * (inherited below, unchanged) is correct as-is -- but the WINDOW's
     * own x()/y() are its position *on screen* (needed for WM
     * interaction, event-coordinate math, etc.), which has nothing to
     * do with where to paint within its own drawable. A drawable's
     * local origin is always (0,0) at its own top-left, by definition,
     * regardless of where the window sits on screen.
     *
     * Without this override, a freshly-created
     * Window would inherit FlGroup.draw()'s `drawBox()` (fl.widget, the
     * no-arg overload), which fills at (x_, y_, w_, h_) -- for the
     * window itself, that's (screen-x, screen-y, w, h). Once a
     * ConfigureNotify updates x_/y_ to the window's real on-screen
     * position (see fl.platform_x11's ConfigureNotify handling), any
     * window not sitting near the screen's own (0,0) origin would end up
     * asking to fill pixels almost entirely *outside* its own 400x300-
     * ish drawable -- e.g. a window at screen (834,648) would fill
     * starting at local (834,648) within its own 400x300 drawable,
     * which is entirely out of bounds, so literally zero pixels of the
     * background would get painted. The window's children still draw
     * fine either way (their coordinates are already window-relative),
     * which is
     * why a covering child widget hides
     * this class of bug entirely -- only an uncovered background near a
     * far-from-origin screen position would show it.
     *
     * `drawBackdrop()` is overridden below (ported from
     * `Fl_Window::draw_backdrop()`) rather than falling back to the
     * base `Widget.drawBackdrop()`'s `alignImageBackdrop` handling --
     * a top-level window's background image uses a different
     * condition (`alignInside`, not `alignImageBackdrop`) and draws
     * through a full `Label` honoring the window's real `align()`
     * placement, not just centered. Also not ported:
     * pWindowDriver->draw_begin()/draw_end() (Wayland-only buffer-swap
     * hooks FLTK; X11's own driver overrides are empty, so this
     * port has nothing to call), and the label draw FLTK
     * deliberately skips too (a top-level window's label goes in the
     * WM titlebar via XStoreName(), not as an in-window label -- this
     * port's constructor already sets labeltype(noLabel) so skipping
     * drawLabel() here isn't even a behavior change, just matches
     * FLTK's own reasoning for not calling it).
     */
    override void draw()
    {
        applyShapeMaskIfNeeded();
        if (damage() & ~damageChild)
        {
            drawBox(box(), 0, 0, w(), h(), color());
            drawBackdrop();
        }
        drawChildren();
    }

    /**
     * Draws image() (or deimage() when inactive) as the window's
     * background, honoring the window's own align()/labeltype(), but
     * only when alignInside is set -- unlike the base
     * Widget.drawBackdrop() this overrides (which checks
     * alignImageBackdrop and always centers), matching FLTK's
     * distinct Fl_Window::draw_backdrop() exactly (src/Fl_Window.cxx).
     *
     * `public`, not `protected` like the base `Widget.drawBackdrop()`
     * it overrides -- matches FLTK's own access-widening override
     * exactly (`Fl_Window.H` re-declares it under a `public:` section,
     * unlike `Fl_Widget.H`'s `protected:` one), since fl.tabs's own
     * `draw()` needs to call a *sibling* window's `drawBackdrop()`
     * directly (`win.drawBackdrop()` where `win` is the Tabs' parent,
     * not `this` or an ancestor of it) -- exactly the case `protected`
     * doesn't allow.
     *
     * **`TiledImage` special-case, deliberately exceeding FLTK**: a
     * `TiledImage` background (e.g. the "plastic" scheme's
     * window tile, `fl.core.plasticSchemeTile()`) deliberately reports
     * `w()`/`h() == 0` (a multi-monitor safety measure, matching
     * FLTK's own `Fl_Tiled_Image` exactly), so routing it through
     * the generic `Label`-based path below -- which ultimately calls
     * the image's plain 2-arg natural-size `draw(x,y)`, i.e.
     * `draw(x,y,w(),h())` -- draws nothing at all for a 0-sized tile.
     * This is a real, documented FLTK limitation (`Fl_Tiled_Image.H`'s
     * own class doc comment, `STR #3106`); FLTK's own recommended
     * workaround is to put the tile on a plain child `FlGroup`/`Box`
     * filling the window instead of setting it as the window's own
     * background. Bypassing the generic path here for a `TiledImage`
     * specifically -- calling its tiling-aware 4-arg `draw(0,0,w(),h())`
     * directly -- goes beyond what FLTK itself does, but is small and
     * contained; see `fl.core.plasticSchemeTile()`'s own
     * doc comment for the original citation this was sketched from.
     */
    public override void drawBackdrop() const
    {
        if (image() is null || !(alignment() & alignInside)) return;
        auto tiled = cast(TiledImage) image();
        if (tiled !is null)
        {
            (cast(Image) tiled).draw(0, 0, w(), h());
            return;
        }
        Label l1;
        l1.image = cast(Image) image();
        if (!activeR() && l1.image !is null && deimage() !is null)
            l1.image = cast(Image) deimage();
        l1.type = labeltype();
        l1.hMargin = 0;
        l1.vMargin = 0;
        l1.spacing = 0;
        l1.draw(0, 0, w(), h(), alignment());
    }

    /// True once the platform layer has created (and not since
    /// destroyed) this window's real on-screen representation.
    bool shown() const { return shown_; }

    /**
     * Creates (if this is the first call) or re-shows the window's
     * real on-screen representation. Ported from `Fl_Window::show()`
     * (`src/Fl_Window.cxx`), including real subwindow support:
     * if this window is a
     * subwindow (`parent() !is null`) whose immediate window ancestor
     * (`window()`) isn't itself shown yet, `fl.platform_x11.createWindow()`
     * defers real creation and just marks this logically visible --
     * `handle()`'s own `Event.show` case below is what actually creates
     * it later, once that ancestor's own `show()` cascades `Event.show`
     * down through the widget tree and reaches this window. This method
     * itself doesn't need to know or care whether it's being called on a
     * top-level window or a subwindow -- `createWindow()` does that
     * branching, matching FLTK's own single, parent()-oblivious
     * `Fl_Window::show()` calling straight into the driver either way.
     */
    override void show()
    {
        // Apply `-scaling_factor` once, when the first top-level window shows.
        static bool firstShow = true;
        if (firstShow && parent() is null)
        {
            firstShow = false;
            if (fl.core.argScalingFactor_ != 1.0f)
                fl.core.normalizedScreenScale(-1, fl.core.argScalingFactor_);
        }

        if (!shown_) defaultSizeRange();

        // Ported from Fl_Window::show()'s own unconditional
        // `image(Fl::scheme_bg_);` -- applies (or clears) the current
        // scheme's tiled background on every show() call, not just
        // once at construction, so a window created after
        // fl.core.scheme("plastic") was already set still picks it up.
        auto bg = fl.core.schemeBg();
        image(bg);
        if (bg !is null)
        {
            labeltype(Labeltype.normalLabel);
            alignment(alignCenter | alignInside | alignClip);
        }
        else
            labeltype(Labeltype.noLabel);

        version (linux)
        {
            if (!shown_)
                platformX11.createWindow(this);
            else
                platformX11.raiseWindow(this);
        }
        version (Windows)
        {
            if (!shown_)
                platformWin32.createWindow(this);
            else
                platformWin32.raiseWindow(this);
        }
    }

    /// Set once command-line `-geometry`/scheme have been applied to
    /// the first window shown via `show(string[])` -- FLTK's own
    /// `beenhere` is a function-local static inside `Fl_Window::show(int,
    /// char**)`, i.e. shared process-wide, not per-window, so a plain
    /// module-level flag matches its real scope faithfully (only the
    /// *first* window shown this way picks up `-geometry`, matching
    /// real FLTK exactly -- a second, unrelated window shown later via
    /// the same overload does not).
    private static bool argsBeenHere_;

    /**
     * Convenience overload matching FLTK's `Fl_Window::show(int
     * argc, char **argv)` call shape -- a `main(string[] args)`'s
     * `args` can be handed straight through. Ported from
     * `src/Fl_arg.cxx`'s real `Fl_Window::show(int,char**)`.
     *
     * If `fl.core.args()`/`arg()` hasn't already been called explicitly,
     * calls `fl.core.args(args)` first (matching FLTK's own `if
     * (argc && !arg_called) Fl::args(argc,argv);` guard -- a caller that
     * already parsed its own switches via `fl.core.args(args, i, cb)`
     * doesn't get re-parsed here), then `fl.core.getSystemColors()`, in
     * the same position FLTK calls it. Applies `-geometry` (once per
     * process, see `argsBeenHere_` above) via `resize()`/`size()`,
     * translating a negative x/y (an offset from the right/
     * bottom screen edge rather than the left/top) against
     * `fl.core.w()`/`h()`. Prefers an explicit `-name`/`-title` over the
     * `argv[0]`-derived fallback (matching real FLTK:
     * `examples/callbacks` titles its window "callbacks", its own
     * basename, not a window manager's "Untitled" fallback for a
     * genuinely empty title).
     *
     * Not ported: the `Fl_Window_Driver::show_with_args_begin()`/
     * `show_with_args_end()` hooks (this port has no driver-class
     * hierarchy for them to belong to -- see `fl.platform_x11`'s own
     * "concrete module, not driver abstraction" doc note).
     */
    void show(string[] args)
    {
        if (args.length > 0 && !fl.core.argCalled())
            fl.core.args(args);

        fl.core.getSystemColors();

        if (!argsBeenHere_)
        {
            if (fl.core.argGeometry_.length > 0)
            {
                int gx = x(), gy = y();
                uint gw = cast(uint) w(), gh = cast(uint) h();
                int flags = fl.core.parseGeometry(fl.core.argGeometry_, gx, gy, gw, gh);
                if (flags & fl.core.geomXNegative) gx = fl.core.w() - w() + gx;
                if (flags & fl.core.geomYNegative) gy = fl.core.h() - h() + gy;

                Widget r = resizable();
                if (r is null) resizable(this);
                if (flags & (fl.core.geomXValue | fl.core.geomYValue))
                    resize(gx, gy, cast(int) gw, cast(int) gh);
                else
                    size(cast(int) gw, cast(int) gh);
                resizable(r);
            }
        }

        if (fl.core.argName_.length > 0) { xclass(fl.core.argName_); fl.core.argName_ = null; }
        else if (xclass().length == 0 || xclass() == "fldtk") xclass(filenameName(args.length ? args[0] : null));

        if (fl.core.argTitle_.length > 0) { label(fl.core.argTitle_); fl.core.argTitle_ = null; }
        else if (label().length == 0) label(xclass());

        if (!argsBeenHere_)
            argsBeenHere_ = true;

        // -iconic: matches FLTK exactly -- Fl::arg()'s own -iconic case calls
        // fl.core.showNextWindowIconic_ = true directly at parse time,
        // consumed by createWindow()'s WM_HINTS.initial_state below,
        // before this show() ever maps the window, so no separate
        // post-show() call is needed here (see
        // fl.window.Window.iconize()'s own doc comment).
        show();
    }

    /**
     * Ported from `Fl_Window::~Fl_Window()`, whose own body is just
     * `hide();` before implicitly chaining to `~Fl_Group()`/
     * `~Fl_Widget()`. This is load-bearing, not defensive: `destroy()`ing
     * a still-*shown* `Window` directly,
     * without an explicit prior `hide()`, would leave its `fl.platform_x11`
     * window-registry entry (`WindowRecord`) dangling -- the next
     * `flushDamage()` would walk that stale entry and crash dereferencing
     * a widget already torn down by the rest of the destructor chain.
     *
     * Guarded by `GC.inFinalizer()` the same way `Widget.~this()`/
     * `FlGroup.~this()` already are: `hide()` reaches into other
     * GC-managed state (the window registry, subwindow teardown), only
     * safe when this destructor runs deterministically (`destroy(win)`)
     * rather than during GC-driven finalization, where finalization
     * order across objects is undefined.
     */
    ~this()
    {
        if (!GC.inFinalizer())
            hide();
    }

    /// Destroys the window's real on-screen representation. Safe to
    /// call again later via show(). Ported from `Fl_Window::hide()`
    /// (`src/Fl_Window.cxx`) -- `fl.platform_x11.destroyWindow()`
    /// also recursively destroys any subwindows nested inside this one,
    /// matching FLTK's
    /// `Fl_Window_Driver::hide_common()`.
    override void hide()
    {
        version (linux)
        {
            if (shown_)
                platformX11.destroyWindow(this);
        }
        version (Windows)
        {
            if (shown_)
                platformWin32.destroyWindow(this);
        }
    }

    /**
     * Ported from `Fl_Window::handle()` (`src/Fl_Window.cxx`) --
     * subwindow-specific reaction to `Event.show`/`Event.hide` cascading
     * down from an ancestor window's own `show()`/`hide()` (see
     * `FlGroup.handle()`'s `Event.show`/`Event.hide` case, which forwards
     * these to every visible child, and `fl.platform_x11.createWindow()`'s
     * trailing `win.handle(Event.show)` call, which is what starts this
     * cascade for the window actually being shown). Only relevant for a
     * subwindow (`parent() !is null`) -- FLTK's own comment explains
     * why top-level windows need no reaction here at all: "it is assumed
     * the window has already been mapped or unmapped" by the time this
     * fires, since a top-level's own `show()`/`hide()` call already did
     * the real work directly, not via this cascade.
     *
     * **Real unmap-in-place**: for the common
     * "ancestor `FlGroup`, not a `Window`, hidden directly" case, a full
     * destroy-then-recreate `hide()`/`show()` cycle would be
     * behaviorally different from FLTK, not just more expensive:
     * `hide()` (`platformX11.destroyWindow()`) unconditionally cascades
     * `Event.hide` through this subwindow's own widget tree, and since
     * the outer `handle()` call already does the same via its own
     * trailing `super.handle(event)`, that would dispatch it *twice* --
     * and
     * recreating the X resource from scratch on every reveal is real,
     * avoidable work FLTK never does for this path. Faithfully
     * ported from `Fl_Window::handle()` (`src/Fl_Window.cxx`),
     * including its `FL_HIDE` guard: walk up while each ancestor is
     * still `visible()`; if the first *invisible* one found is itself a
     * `Window`, that ancestor's own hide/destroy already handles
     * everything below it, so skip the unmap here to avoid an
     * unnecessary extra hide/show blink when the ancestor window
     * reappears. Otherwise (the common case -- a plain `FlGroup`
     * ancestor was hidden), `platformX11.unmapWindow()`/`raiseWindow()`
     * toggle the real X window's mapped state in place, leaving this
     * subwindow's own `WindowRecord`/`shown_` untouched -- matching
     * `Fl_X11_Window_Driver::unmap()`/`::map()` exactly, no destroy or
     * `Event.hide` cascade involved.
     */
    override int handle(Event event)
    {
        if (parent !is null)
        {
            if (event == Event.show)
            {
                if (!shown_)
                    show();
                else
                {
                    version (linux) platformX11.raiseWindow(this);
                    version (Windows) platformWin32.raiseWindow(this);
                }
            }
            else if (event == Event.hide)
            {
                if (shown_)
                {
                    bool doUnmap = true;
                    if (visible())
                    {
                        Widget p = parent;
                        while (p !is null && p.visible())
                            p = p.parent;
                        if (p !is null && p.asWindow() !is null)
                            doUnmap = false;
                    }
                    if (doUnmap)
                    {
                        version (linux) platformX11.unmapWindow(this);
                        version (Windows) platformWin32.unmapWindow(this);
                    }
                }
            }
        }
        return super.handle(event);
    }

    /// Internal use only; called by `Widget.damage(Damage,x,y,w,h)`
    /// to accumulate a
    /// window-relative sub-rectangle into this window's real damage
    /// tracking, so `fl.platform_x11.flushDamage()` can clip its next
    /// repaint to (the bounding box of) everything actually damaged
    /// since the last flush, instead of redrawing the whole window
    /// unconditionally. A no-op on non-Linux platforms (no driver
    /// exists for them yet, matching this module's own established
    /// pattern for `show()`/`hide()`).
    package(fl) void accumulateDamageRect(int x, int y, int w, int h)
    {
        version (linux) platformX11.accumulateDamage(this, x, y, w, h);
        // `fl.platform_win32.accumulateDamageRect()` mirrors
        // `platformX11.accumulateDamage()`'s own bounding-box-merge
        // algorithm, see that function's own doc comment.
        version (Windows) platformWin32.accumulateDamageRect(this, x, y, w, h);
    }

    /// Internal use only; called by `Widget.damage(Damage)` (whole-
    /// widget damage reaching this window) to discard any previously-
    /// accumulated partial-damage rectangle -- matching FLTK's own
    /// `Fl_Widget::damage(uchar)` comment ("damage entire window by
    /// deleting the region"): once the whole window is damaged, a
    /// stale partial rectangle from `accumulateDamageRect()` would
    /// wrongly clip the next repaint to less than the whole window.
    package(fl) void clearDamageRegion()
    {
        version (linux) platformX11.clearDamageRegion(this);
        version (Windows) platformWin32.clearDamageRegion(this);
    }

    version (linux)
    {
        /// Internal use only; the platform layer's own handle for
        /// this window, needed to re-show() an already-created window.
        package(fl) XlibWindow xid() const { return xid_; }

        /// Ported from `Fl_Window::make_current()`: points every
        /// subsequent `fl.draw` call at this window's own real X
        /// resource, the same handoff `fl.platform_x11.flushDamage()`
        /// already does before each window's own `draw()` cycle (see
        /// `fl.draw.setDrawable()`'s doc comment) -- exposed here as a
        /// public method for callers that need to draw (or, per
        /// FLTK's own doc comment, need a valid window context to
        /// base an offscreen buffer on) outside the normal repaint
        /// cycle, e.g. `test/offscreen.cxx`'s first-time
        /// `fl_create_offscreen()` call. A no-op if the window hasn't
        /// been `show()`n yet (`xid_` still `0`).
        void makeCurrent()
        {
            if (xid_ != 0)
            {
                fldraw.setDrawable(xid_);
                current_ = this;
                fl.core.currentScale(fl.core.screenScale(screenNum()));
            }
        }

        /// Internal use only; called by fl.platform_x11 once the
        /// window's real on-screen representation exists.
        package(fl) void markShown(XlibWindow xid)
        {
            xid_ = xid;
            shown_ = true;
            setVisible();
        }

        /// Internal use only; called by fl.platform_x11 once the
        /// window's real on-screen representation has been destroyed.
        package(fl) void markHidden()
        {
            xid_ = 0;
            shown_ = false;
            clearVisible();
        }
    }

    version (Windows)
    {
        import core.sys.windows.windef : HDC;
        import core.sys.windows.winuser : GetDC;
        import fl.gdi_graphics_driver : GdiGraphicsDriver;
        import fl.graphics_driver : currentDriver;

        /// Internal use only; the platform layer's own handle for
        /// this window, needed to re-show() an already-created window.
        package(fl) Win32Window xid() const { return cast(Win32Window) xid_; }

        /// `makeCurrent()` matters for `mandelbrot` (`source/test/
        /// DrawingArea.d`), which draws incrementally from an idle callback
        /// (`win.makeCurrent()` then `drawImageMono()`/`drawImage()`/
        /// `overlayRect()` per scanline/drag-frame, entirely outside any
        /// `WM_PAINT`): without a real `GetDC()` call here,
        /// `GdiGraphicsDriver.hdc_` would still be `null`
        /// (reset by `WM_PAINT`'s own trailing
        /// `gdiDriver_.setHdc(null)`, see `fl.platform_win32.wndProc()`'s
        /// own `WM_PAINT` case), and `GraphicsDriver.drawImage()`/etc.
        /// all no-op on a null `hdc_` -- the window would show nothing but
        /// its own plain box fill, no image content
        /// would ever appear.
        ///
        /// `GetDC(hwnd)` is cheap and safe to call every time here,
        /// unlike an ordinary window class: `registerWindowClass()` sets
        /// `CS_OWNDC`, so every call returns the *same* permanently-
        /// owned `HDC` for this window (any GDI state selected into it
        /// persists between calls) -- the same DC `BeginPaint()` itself
        /// returns during a real paint. No matching `ReleaseDC()` is
        /// needed for a `CS_OWNDC` window (MSDN: it "has no effect"
        /// there) -- the DC lives for the window's whole lifetime
        /// either way, which is exactly the semantics this needs (a
        /// draw made now must still be visible on the next real
        /// repaint, since this window is never double-buffered -- see
        /// `mandelbrot_ui.fl`'s own `type Single`).
        void makeCurrent()
        {
            auto hwnd = xid();
            if (hwnd is null) return;
            auto driver = cast(GdiGraphicsDriver) currentDriver;
            if (driver is null) return;
            HDC dc = GetDC(hwnd);
            if (dc is null) return;
            driver.setHdc(dc);
            current_ = this;
            fl.core.currentScale(fl.core.screenScale(screenNum()));
        }

        /// Internal use only; called by fl.platform_win32 once the
        /// window's real on-screen representation exists.
        package(fl) void markShown(Win32Window xid)
        {
            xid_ = xid;
            shown_ = true;
            setVisible();
        }

        /// Internal use only; called by fl.platform_win32 once the
        /// window's real on-screen representation has been destroyed.
        package(fl) void markHidden()
        {
            xid_ = null;
            shown_ = false;
            clearVisible();
        }
    }

    /**
     * Sets the allowable range to which the user can resize this
     * window. Records the bookkeeping fields FLTK tracks
     * (minw_/minh_/maxw_/maxh_/dw_/dh_/aspect_/size_range_set_), and --
     * on Linux, if the window is already shown() -- re-sends the
     * WM_NORMAL_HINTS X property immediately (`Fl_Window_Driver::
     * size_range()`'s `if (shown()) sendxjunk();`, see
     * fl.platform_x11.sizeRangeChanged()). If the window isn't shown()
     * yet, createWindow() sends the hints itself as part of window
     * creation (matching FLTK's make_xid()), so a window built with
     * sizeRange() before show() is still constrained correctly once it
     * appears -- only a call to sizeRange() *after* show() needed this
     * extra push.
     */
    void sizeRange(int minWidth, int minHeight, int maxWidth = 0, int maxHeight = 0,
        int deltaX = 0, int deltaY = 0, bool aspectRatio = false)
    {
        minw_ = minWidth;
        minh_ = minHeight;
        maxw_ = maxWidth;
        maxh_ = maxHeight;
        dw_ = deltaX;
        dh_ = deltaY;
        aspect_ = aspectRatio;
        sizeRangeSet_ = true;

        version (linux) platformX11.sizeRangeChanged(this);
    }

    /// Gets the allowable resize range set by sizeRange(). Returns
    /// `sizeRangeSet_` (true once *any* range is on record, whether
    /// from an explicit sizeRange() call or a computed
    /// defaultSizeRange() default) -- matches FLTK's own
    /// `size_range_set_`, which the same two call sites both set.
    bool getSizeRange(int* minWidth = null, int* minHeight = null, int* maxWidth = null,
        int* maxHeight = null, int* deltaX = null, int* deltaY = null, bool* aspectRatio = null)
    {
        if (minWidth) *minWidth = minw_;
        if (minHeight) *minHeight = minh_;
        if (maxWidth) *maxWidth = maxw_;
        if (maxHeight) *maxHeight = maxh_;
        if (deltaX) *deltaX = dw_;
        if (deltaY) *deltaY = dh_;
        if (aspectRatio) *aspectRatio = aspect_;
        return sizeRangeSet_;
    }

    /**
     * Calculates and records a default size range when sizeRange() was
     * never called explicitly -- ported from
     * `Fl_Window::default_size_range()` (`src/Fl_Window.cxx`). Called
     * automatically from show(), matching FLTK's own
     * `if (!shown()) default_size_range();` inside `Fl_Window::show()`,
     * so a window's resizable() widget (if any) determines its size
     * constraints even when the caller never calls sizeRange() itself.
     *
     * If resizable() is null (the default), the window becomes fixed-
     * size (min == max == its current size). Otherwise the
     * resizable() widget is clipped to the window's own bounds, and
     * the window's minimum size becomes the non-resizable portion of
     * the window (whatever's left over once the clipped resizable
     * widget's own area is subtracted) plus up to 100x100 of that
     * clipped resizable widget -- letting it shrink to 100x100 or its
     * own size (whichever is smaller) while growing unboundedly (no
     * max is set), unless a dimension of resizable() is exactly zero,
     * which disables resizing in that direction entirely (min==max in
     * that dimension).
     */
    void defaultSizeRange()
    {
        if (sizeRangeSet_) return;

        if (resizable() is null)
        {
            sizeRange(w(), h(), w(), h());
            return;
        }

        Widget r = resizable();

        int maxw = 0;
        int maxh = 0;

        // Clip the resizable() widget to the window.
        int L = (r is this) ? 0 : r.x();
        int R = L + r.w();
        if (R < 0 || L > w()) R = L; // outside the window
        else
        {
            if (L < 0) L = 0;
            if (R > w()) R = w();
        }
        int rw = R - L;

        int T = (r is this) ? 0 : r.y();
        int B = T + r.h();
        if (B < 0 || T > h()) B = T; // outside the window
        else
        {
            if (T < 0) T = 0;
            if (B > h()) B = h();
        }
        int rh = B - T;

        // Non-resizable part of the window (FLTK cites STR 3352),
        // computed before shrinking the resizable widget's own clipped
        // size below.
        int minw = w() - rw;
        int minh = h() - rh;

        // Limit the resizable dimensions to 100x100 -- lets it shrink,
        // not just grow (matches FLTK's own issue #392 fix).
        if (rw > 100) rw = 100;
        if (rh > 100) rh = 100;

        minw += rw;
        minh += rh;

        // A zero-sized resizable() dimension disables resizing in that
        // direction entirely.
        if (r.w() == 0) { minw = w(); maxw = w(); }
        if (r.h() == 0) { minh = h(); maxh = h(); }

        sizeRange(minw, minh, maxw, maxh);
    }

    private static Window current_;

    /**
     * Ported from `Fl_Window::current()`: the last window made current
     * for drawing. Set by `makeCurrent()` above for callers that draw
     * outside the normal repaint cycle (e.g. `test/offscreen.cxx`), and
     * by `fl.platform_x11.flushDamage()` (via `setCurrentForDraw()`
     * below) right before each window's own `draw()` cycle -- matching
     * FLTK's own two `current_ = this;` call sites in
     * `Fl_Window::make_current()`/`Fl_Window::draw()`.
     *
     * The one real consumer today: `fl.tiled_image.TiledImage.draw()`'s
     * `W == 0 && H == 0` case ("tile the whole current window" --
     * FLTK's own documented, if fragile, background-image
     * convenience) reads this to know what to fill.
     * `examples/shapedwindow.cxx`'s `Dragbox` binds exactly such a
     * zero-sized `Fl_Tiled_Image` as its background; without a current
     * window `TiledImage.draw()` would draw nothing at all (a plain gray
     * `Box` background showing through instead of the checkered tile
     * FLTK shows).
     */
    static Window current() { return current_; }

    /// Internal use only; called by `fl.platform_x11.flushDamage()`
    /// right before a window's own `draw()` cycle. A separate setter
    /// from `makeCurrent()` (rather than reusing it directly) since
    /// `flushDamage()` may point `fl.draw`'s actual drawable at a
    /// `DoubleWindow`'s off-screen buffer, not this window's own real X
    /// resource -- `current_` tracks "which window is being drawn," a
    /// different question from "which drawable is currently active."
    ///
    /// **Also refreshes `fl.core.currentScale()` from `w.screenNum()`'s
    /// own per-screen table entry** -- this is this port's actual
    /// `make_current()`-equivalent hook (the *real* per-`Expose` repaint
    /// path calls this, not `makeCurrent()`, which only ever runs for
    /// draws made outside the normal cycle), matching FLTK's own
    /// `Fl_X11_Window_Driver::make_current()`: `fl_graphics_driver->
    /// scale(Fl::screen_driver()->scale(screen_num()))`. This
    /// is what makes every `fl.draw`
    /// primitive draw each window at *that window's own* screen's
    /// scale instead of one value shared by every window regardless of
    /// which monitor it's actually on.
    package(fl) static void setCurrentForDraw(Window w)
    {
        current_ = w;
        if (w !is null) fl.core.currentScale(fl.core.screenScale(w.screenNum()));
    }

    /// Reports whether the current resize is due to a DPI/scale change
    /// rather than an ordinary size change -- used by `FlGroup.resize()`
    /// to force a child resize even when the relative position didn't
    /// change (a rescale can change device-pixel geometry while every
    /// FLTK-unit coordinate involved stays numerically identical, e.g.
    /// a window sitting at `x() == 0` with an unchanged FLTK-unit
    /// width). Reads the real `isARescale_` flag that
    /// `resizeAfterScaleChange()` sets/clears
    /// right around its own `resize()`
    /// call. Without that, any child whose own `dx`/`dy` happens to land on exactly
    /// 0 during a live rescale (e.g. an `x() == 0` window, or any
    /// child whose parent's `x()`/`y()` didn't shift) would never get its own
    /// `resize()` called at all -- silently skipping the device-pixel
    /// `XMoveResizeWindow()` a nested subwindow (a `GlWindow` embedded
    /// in a `FlGroup`, e.g. `source/test/CubeViewUI.fl`'s own `cube`)
    /// needs to actually move/resize its real X11 resource.
    static bool isARescale() { return isARescale_; }

    /**
     * Changes this window's cursor shape. Real on Linux (backed by
     * fl.platform_x11.setCursor(), an XDefineCursor() call) -- see that
     * function's own doc comment for exactly which Cursor values are
     * supported (most are; `nwse`/`nesw`/`none` need a custom pixmap
     * cursor that isn't ported). A no-op if the window isn't shown()
     * yet, matching FLTK's own `if (!flx_) return;` guard.
     *
     * **Real subwindow redirect**: ported from
     * `Fl_Window::cursor(Fl_Cursor)`'s own top-of-function walk
     * (`src/fl_cursor.cxx`) -- the cursor must be set on the *top-level*
     * window's real X resource regardless of which (sub)window `cursor()`
     * was actually called on, since a subwindow's own child X window has
     * no cursor of its own in any useful sense (X11 cursors are a
     * per-real-window property, and FLTK's own driver-level
     * `XDefineCursor()` call always targets whatever `fl_xid()` maps to,
     * which FLTK ensures is always the top-level).
     */
    void cursor(Cursor c)
    {
        Window w = window(), toplevel = this;
        while (w !is null) { toplevel = w; w = w.window(); }
        if (toplevel !is this) { toplevel.cursor(c); return; }

        version (linux) platformX11.setCursor(this, c);
        version (Windows) platformWin32.setCursor(this, c);
    }

    /**
     * Sets this window's cursor to a custom image, with `(hotx, hoty)`
     * as the active hotspot relative to `image`'s own top-left corner.
     * Real on Linux, backed by
     * `fl.platform_x11.setCursorImage()`, an `Xcursor`-based
     * `XDefineCursor()` call -- see that function's own doc comment).
     * Falls back to the plain default arrow cursor if `image`/`hotx`/
     * `hoty` are invalid, matching FLTK's own fallback exactly.
     * Ported from `Fl_Window::cursor(const Fl_RGB_Image*, int, int)`
     * (`src/fl_cursor.cxx`) -- same top-level-window redirect and
     * `!shown()` no-op guard as the `Cursor` overload just above.
     */
    void cursor(const(RGBImage) image, int hotx, int hoty)
    {
        Window w = window(), toplevel = this;
        while (w !is null) { toplevel = w; w = w.window(); }
        if (toplevel !is this) { toplevel.cursor(image, hotx, hoty); return; }
        if (!shown()) return;

        bool ok = false;
        version (linux) ok = platformX11.setCursorImage(this, image, hotx, hoty);
        version (Windows) ok = platformWin32.setCursorImage(this, image, hotx, hoty);
        if (!ok) cursor(Cursor.default_);
    }

    private Image shapeImage_;
    private Bitmap shapeBitmap_;
    private int shapeAppliedW_ = -1, shapeAppliedH_ = -1;

    /**
     * Assigns a non-rectangular shape to this window via the X SHAPE
     * extension (`fl.platform_x11.applyWindowShapeMask()`). Ported from
     * `Fl_Window::shape(const Fl_Image*)`
     * (`src/drivers/X11/Fl_X11_Window_Driver.cxx`'s `shape()`/
     * `shape_alpha_()`/`shape_bitmap_()`): with a `Bitmap` (depth 0), the
     * window covers the part where bits are set; with an `RGBImage`, the
     * window covers the non-fully-transparent part (depth 2/4, alpha
     * channel) or the non-black part (depth 1/3, matching FLTK's own
     * "no alpha channel" fallback). Also calls `border(false)`, matching
     * FLTK exactly (a shaped window's own outline replaces the WM
     * decorations).
     *
     * The mask isn't sent to the X server here -- it's computed once and
     * then (re)applied lazily from `draw()`, right before the window's
     * next repaint, the same way FLTK's `draw_begin()` does (see that
     * function's own doc comment for why: this window may not be
     * `shown()` yet, and it may be resized one or more times before its
     * next repaint, in which case only the size at that repaint matters).
     *
     * Deliberately unsupported, unlike FLTK: a `Pixmap`-family image
     * with more than one underlying data array (FLTK's `count() >= 2`
     * branch, `shape_pixmap_()`) -- this port's `Image` base class has no
     * `count()`/generic `data()` at all (a documented simplification, see
     * `fl.image`'s own module comment), and no sample or test in this
     * port's tree ever passes one to `shape()` (`shapedwindow.d` only
     * ever passes an `ImageSurface.image()` result, a plain `RGBImage`).
     * A no-op for any image type that isn't a `Bitmap` or `RGBImage`.
     */
    void shape(const(Image) img)
    {
        border(false);
        shapeImage_ = cast(Image) img;
        shapeBitmap_ = cast(Bitmap) computeShapeBitmap(img);
        shapeAppliedW_ = -1;
        shapeAppliedH_ = -1;
    }

    /// Ported from `Fl_Window::shape() const`.
    const(Image) shape() const { return shapeImage_; }

    /**
     * Ported from `Fl_X11_Window_Driver::shape_alpha_()`/`shape_bitmap_()`
     * -- builds the 1-bit-per-pixel mask `applyShapeMask()` scales and
     * sends to the X server. Deliberately doesn't consult `RGBImage.ld()`
     * (assumes a tightly-packed buffer), matching FLTK's own
     * `shape_alpha_()` exactly, which reads `img->data()` as one flat
     * array without ever referencing a line-delta either.
     */
    private static const(Bitmap) computeShapeBitmap(const(Image) img)
    {
        auto bm = cast(const(Bitmap)) img;
        if (bm !is null) return bm;

        auto rgb = cast(const(RGBImage)) img;
        if (rgb is null) return null;

        int w = rgb.dataW(), h = rgb.dataH(), d = rgb.d();
        if (w <= 0 || h <= 0) return null;

        int offset;
        if (d == 2 || d == 4) offset = d - 1;
        else if (d == 1 || d == 3) offset = 0;
        else return null;

        const(ubyte)[] array = rgb.array;
        if (array.length < w * h * d) return null;

        int rowBytes = (w + 7) / 8;
        auto bits = new ubyte[h * rowBytes];
        foreach (y; 0 .. h)
        {
            foreach (x; 0 .. w)
            {
                const(ubyte)* p = array.ptr + (y * w + x) * d + offset;
                uint u = (d == 3) ? (p[0] + p[1] + p[2]) : p[0];
                if (u > 0) bits[y * rowBytes + x / 8] |= cast(ubyte)(1 << (x % 8));
            }
        }
        return new Bitmap(bits, w, h);
    }

    /**
     * Recomputes and (re)applies this window's SHAPE mask if its size has
     * changed since the mask was last sent to the X server -- called from
     * `draw()`, matching FLTK's own `draw_begin()` call site and
     * lazy-recompute condition exactly (`Fl_X11_Window_Driver::
     * draw_begin()`/`combine_mask()`). A no-op if `shape()` was never
     * called, or if `computeShapeBitmap()` couldn't build a mask for the
     * image passed to it.
     *
     * The mask is resized to `w()`/`h()` **scaled** to real device pixels,
     * not the plain FLTK-unit `w()`/`h()` -- matching
     * FLTK's own `combine_mask()` exactly (`shape_data_->lw_ =
     * w()*s;`/`temp->copy(shape_data_->lw_, shape_data_->lh_)`) and its
     * `draw_begin()`'s own change-detection (`lw_ != int(s*w())`, not
     * just `!= w()`, so a *scale* change alone -- with no FLTK-unit
     * resize at all -- still correctly triggers a rebuild). An X11
     * `XShapeCombineMask` mask is inherently device-pixel-sized (like
     * `fl.pixmap.Pixmap`'s own clip-mask, which had the identical bug);
     * passing the *unscaled* window size left the mask permanently
     * capped at the pre-scale pixel footprint regardless of the
     * window's real (scaled) size -- visually pinning the *visible*
     * area to that fixed size while the window itself and its label
     * content kept growing/shrinking with scale, exactly matching the
     * reported "shape doesn't grow above 100%, right/bottom corners go
     * missing below 100%" symptom (the too-small or too-large mask,
     * relative to the real window, left the window's own rectangular
     * edge doing the actual clipping instead of the intended rounded
     * shape).
     */
    private void applyShapeMaskIfNeeded()
    {
        if (shapeBitmap_ is null) return;

        float scale = fl.core.screenScale(screenNum());
        int scaledW = cast(int)(scale * w());
        int scaledH = cast(int)(scale * h());
        if (shapeAppliedW_ == scaledW && shapeAppliedH_ == scaledH) return;

        auto resized = shapeBitmap_.copy(scaledW, scaledH);
        shapeAppliedW_ = scaledW;
        shapeAppliedH_ = scaledH;
        if (resized is null) return;

        version (linux) platformX11.applyWindowShapeMask(this, scaledW, scaledH, resized.array);
        version (Windows) platformWin32.applyWindowShapeMask(this, scaledW, scaledH, resized.array);
    }

    /**
     * Whether the window manager draws a border/titlebar/decorations
     * around this window. Ported from `Fl_Window::border()`/
     * `clear_border()`/`border(int)` (`FL/Fl_Window.H`) -- backed by
     * the pre-existing `Flag.noBorder` bit (matches FLTK's own
     * `NOBORDER` flag exactly, including its bit position).
     *
     * On Windows, changing it on a shown window takes effect at once:
     * like FLTK's `Fl_Window::border(int)` -> `Fl_Window_Driver::
     * use_border()` (the generic version, which the WinAPI driver
     * doesn't override), the window is hidden and shown again at its
     * current position, re-created with the new style. On Linux it must
     * still be called before `show()` -- see
     * `fl.platform_x11.createWindow()`'s `_MOTIF_WM_HINTS` handling;
     * FLTK's X11 `use_border()` re-sends the hints instead
     * (`sendxjunk()`), and this port's hints can only turn decorations
     * off, not back on.
     */
    bool border() const { return (flags() & Flag.noBorder) == 0; }
    /// ditto
    void border(bool b)
    {
        if (b == border()) return;
        if (b) clearFlag(Flag.noBorder); else setFlag(Flag.noBorder);
        version (Windows)
        {
            if (shown())
            {
                hide();
                forcePosition(true);
                show();
            }
        }
    }
    /// ditto -- FLTK's fast inline spelling for `border(false)`.
    void clearBorder() { setFlag(Flag.noBorder); }

    /**
     * The width/height of this window's outer, window-manager-decorated
     * bounding box (title bar + borders included), as opposed to `w()`/
     * `h()` which only ever cover this window's own content area. Ported
     * from `Fl_Window::decorated_w()`/`decorated_h()` (`FL/Fl_Window.H`
     * + `src/Fl_Window.cxx`), backed on Linux by
     * `fl.platform_x11.decoratedWinSize()` (a real
     * `XQueryTree()`/`XGetWindowAttributes()` query of the reparenting
     * window manager's own frame window -- see that function's doc
     * comment for the full mechanism and its one deliberate
     * simplification, no per-monitor DPI scaling). Falls back to plain
     * `w()`/`h()` whenever no WM frame can be found (not yet shown(),
     * undecorated, a subwindow, or a non-reparenting window manager),
     * same as FLTK's own documented fallback behavior.
     *
     * Note FLTK's own asymmetry, preserved here: `decoratedH()`
     * always reports the queried frame height even when only
     * "estimated" (`trueSides` false), while `decoratedW()` only trusts
     * the query when `trueSides` is true and falls back to `w()`
     * otherwise -- see `decoratedWinSize()`'s own doc comment for why.
     */
    int decoratedW() const
    {
        version (linux)
        {
            int dw, dh;
            bool trueSides = platformX11.decoratedWinSize(cast(Window) this, dw, dh);
            return trueSides ? dw : w();
        }
        else return w();
    }

    /// ditto
    int decoratedH() const
    {
        version (linux)
        {
            int dw, dh;
            platformX11.decoratedWinSize(cast(Window) this, dw, dh);
            return dh;
        }
        else return h();
    }

    /// Whether this window is flagged modal. Ported from
    /// `Fl_Window::modal()`/`set_modal()`/`set_non_modal()`
    /// (`FL/Fl_Window.H`) -- pure flag bookkeeping, same as `border()`
    /// above: setting it here has zero effect by itself. The real,
    /// cross-window enforcement (`Fl::modal_`'s equivalent tracker,
    /// input filtering, focus pinning, WM stacking hints) happens
    /// automatically as a side effect of `show()`ing/`hide()`ing a
    /// window with this flag set -- see `fl.core.modal()`'s own doc
    /// comment for the full mechanism, matching FLTK's own
    /// `Fl_X::set_xid()`/`Fl_Window_Driver::hide_common()` exactly.
    bool modal() const { return (flags() & Flag.modal) != 0; }
    void setModal() { setFlag(Flag.modal); }
    void setNonModal() { setFlag(Flag.nonModal); } /// ditto

    /// Whether this window is flagged *either* modal or non-modal-
    /// transient -- ported from `Fl_Window::non_modal()` (`FL/Fl_Window.H`,
    /// `return flags() & (NON_MODAL|MODAL);`), a real, if confusingly-
    /// named, combined check: "this window is a dialog-like window
    /// logically owned by another top-level window" (as opposed to a
    /// plain, default, untouched top-level window), true for either
    /// flag, not just `NON_MODAL`. Backs
    /// `fl.platform_x11`'s own `WM_TRANSIENT_FOR` hint -- see that
    /// module's own
    /// `createWindow()` doc comment. Fluid's own Tools
    /// panel is a real `non_modal()` window that needs this broader
    /// check, not just `modal()` alone.
    bool nonModal() const { return (flags() & (Flag.nonModal | Flag.modal)) != 0; }

    /// Clears `Flag.forcePosition` -- the next `show()` (or, on this
    /// port's Linux path, the initial `createWindow()`) is free to let
    /// the window manager place the window rather than requesting an
    /// exact position. Ported from `Fl_Window::free_position()`.
    void freePosition() { clearFlag(Flag.forcePosition); }

    /// Ported from `Fl_Window::force_position(int)`/`force_position()
    /// const`. `Flag.forcePosition` is set by
    /// `resize()`'s own move-tracking and `fl.core.
    /// transientScaleDisplay()`'s scale indicator popup, which needs
    /// its exact requested position honored rather than left to
    /// whatever empty spot the window manager happens to auto-place
    /// it in.
    /// `fl.platform_x11.sendSizeHints()` consults this to decide
    /// whether to add `USPosition` to `WM_NORMAL_HINTS`.
    bool forcePosition() const { return (flags() & Flag.forcePosition) != 0; }

    /// ditto -- the setter. Ported from `Fl_Window::force_position(int)`.
    void forcePosition(bool force)
    {
        if (force) setFlag(Flag.forcePosition);
        else clearFlag(Flag.forcePosition);
    }

    /**
     * Ported from `Fl_Window::resize()` -> `Fl_X11_Window_Driver::resize()`
     * (`Fl_x.cxx`). Unlike the base `FlGroup.resize()` this overrides
     * (pure widget-geometry bookkeeping, no X server interaction at
     * all), resizing/moving a *shown* top-level window also issues
     * the real `XMoveResizeWindow()`/`XResizeWindow()`/`XMoveWindow()`
     * call needed to actually move/resize the on-screen X window.
     *
     * The tricky part, faithfully ported: `fl.platform_x11`'s own
     * `ConfigureNotify` handler *also* calls this same `resize()`, to
     * record the window manager's own authoritative geometry after a
     * server-side move/resize (e.g. the user dragging the title bar).
     * Without a guard, an application-initiated resize would round-trip
     * forever: app calls `resize()` -> `XMoveResizeWindow()` -> the
     * server moves the real window -> sends back `ConfigureNotify` ->
     * which calls `resize()` again -> which would issue *another*
     * `XMoveResizeWindow()` -> another `ConfigureNotify` -> .... Matches
     * FLTK's own `resize_bug_fix` static exactly: `fl.platform_x11`'s
     * `ConfigureNotify` handler sets `resizeBugFix_` (this module) to
     * the window *before* calling `resize()`, so this override can tell
     * "the window manager already moved the real window, this call is
     * just relaying its new geometry" (skip the X call -- it would just
     * echo back what the server already did) apart from "the
     * application called `resize()`/`position()`/`size()` directly"
     * (issue the real X call). `resizeBugFix_` is a single-shot flag,
     * unconditionally cleared on the very next `ConfigureNotify`
     * regardless of whether its geometry matches anything, matching
     * FLTK's own `Fl_X11_Window_Driver::resize()` exactly.
     *
     * A pure move (position changed, size didn't) skips `FlGroup.resize()`
     * entirely via `resizeBoundsOnly()` -- matching FLTK's own plain
     * `x(X); y(Y);` field update for this case: a top-level window's
     * children are already window-relative, so moving the window on
     * screen never needs to reposition them. Also matches FLTK's
     * `if (shown()) pWindow->redraw();` being gated on `isResize`, not
     * on whether this call was an echo or not, which avoids drag-to-move
     * flicker.
     *
     * A separate, rapid-resize `DoubleWindow` off-screen-buffer
     * corruption remains open and unfixed -- see `PORTING.md`'s
     * `FL/Fl_Window.H` row.
     */
    override void resize(int X, int Y, int W, int H)
    {
        // A rescale of a fullscreen or maximized window is followed by
        // switching that state off and on again, so the window fills
        // the screen at the new scale -- ported from
        // `Fl_WinAPI_Window_Driver::resize()`'s `delayed_fullscreen`/
        // `delayed_maximize` checks.
        version (Windows)
        {
            if (isARescale_ && fullscreenActive())
                addCheck(&delayedFullscreen);
            else if (isARescale_ && maximizeActive())
                addCheck(&delayedMaximize);
        }

        bool resizeFromProgram = this !is resizeBugFix_;
        if (!resizeFromProgram)
            resizeBugFix_ = null;

        // `|| isARescale_` matches FLTK's own `is_a_move = (X !=
        // x() || Y != y() || is_a_rescale)` (`Fl_X11_Window_Driver::
        // resize()`) -- needed because `resizeAfterScaleChange()`
        // below deliberately computes the *same* FLTK-unit W/H in its
        // common (non-fullscreen) case (a window's FLTK-unit size never
        // changes just because the scale did), and X/Y can easily land
        // back on the same integer too (e.g. any window at x()==0).
        // Without this, `resize()` would see "nothing changed" and
        // return before ever reaching `platformX11.resizeWindow()` --
        // silently skipping the one call that actually updates the
        // window's real on-screen pixel size.
        bool isMove = X != x() || Y != y() || isARescale_;
        bool isResize = W != w() || H != h() || isARescale_;
        if (resizeFromProgram && !isResize && !isMove) return;

        // Windows: a resize from the program is ignored while the
        // system shows the window maximized, as in FLTK's
        // `Fl_WinAPI_Window_Driver::resize()`. Like FLTK, a move's
        // force-position flag is still set first.
        version (Windows)
        {
            if (isResize && resizeFromProgram && shown()
                && platformWin32.isPlacementMaximized(this))
            {
                if (isMove) setFlag(Flag.forcePosition);
                return;
            }
        }

        if (isResize)
        {
            super.resize(X, Y, W, H);
            if (shown()) redraw();
        }
        else
        {
            resizeBoundsOnly(X, Y, w(), h());
        }

        // `setFlag(Flag.forcePosition)` deliberately sits outside the
        // `shown()`-gated block below: it's pure bookkeeping (setting a
        // flag), unlike the platform resize calls just below, which
        // genuinely need a real window to act on. This matters for a
        // widget that doesn't know
        // its own position until *after* construction (`fl.show_colormap.
        // ColorMenu`'s own `super(w, h)` 2-arg ctor, position computed
        // later in `run()` from the mouse's location, then `position()`
        // called *before* the first `show()`) -- if this were gated on
        // `shown()`, the flag would never get set at that point (`shown()`
        // is false), so `Window`'s very first `show()` -> `createWindow()`
        // (Windows: `fl.platform_win32.createWindow()`) would take the
        // no-explicit-position branch (`CW_USEDEFAULT`) regardless of
        // where `run()` had actually positioned it, opening the popup
        // anywhere Windows' own placement heuristic chose.
        if (resizeFromProgram && isMove) setFlag(Flag.forcePosition);

        if (resizeFromProgram && shown())
        {
            if (isResize && isResizable() == 0) sizeRange(w(), h(), w(), h());
            // Only the window resizeAfterScaleChange() actually computed
            // devX/devY for gets the exact-device-position override --
            // see exactDeviceTarget_'s own doc comment. Every other
            // window this same rescale's FlGroup.resize() cascade also
            // resizes (e.g. a nested GlWindow subwindow) falls back to
            // int.min, letting platformX11.resizeWindow() compute its
            // own device position from X/Y as usual.
            version (linux) platformX11.resizeWindow(this, X, Y, W, H, isMove, isResize,
                this is exactDeviceTarget_ ? exactDeviceX_ : int.min,
                this is exactDeviceTarget_ ? exactDeviceY_ : int.min);
            // Windows'
            // resizeWindow() also receives this exact
            // device-pixel target -- see that function's own doc comment
            // for the rounding-drift bug it avoids.
            version (Windows) platformWin32.resizeWindow(this, X, Y, W, H, isMove, isResize,
                this is exactDeviceTarget_ ? exactDeviceX_ : int.min,
                this is exactDeviceTarget_ ? exactDeviceY_ : int.min);
        }
    }

    /// Set only around the `resize()` call inside `resizeAfterScaleChange()`
    /// below -- matches FLTK's own shared (not per-window)
    /// `Fl_Window_Driver::is_a_rescale_` static exactly (there's no
    /// reentrancy risk to guard against: it's set immediately before,
    /// and cleared immediately after, one synchronous `resize()` call
    /// on the very same window).
    private static bool isARescale_ = false;

    version (Windows)
    {
        /// Check callbacks queued by `resize()` after a rescale --
        /// ported from `Fl_win32.cxx`'s file-scope `delayed_fullscreen()`
        /// and `delayed_maximize()`.
        private void delayedFullscreen()
        {
            removeCheck(&delayedFullscreen);
            fullscreenOff();
            fullscreen();
        }

        /// ditto
        private void delayedMaximize()
        {
            removeCheck(&delayedMaximize);
            unMaximize();
            maximize();
        }
    }

    /// Set only around the `resize()` call inside
    /// `resizeAfterScaleChange()`'s own non-clamped case (no FLTK
    /// equivalent -- a deliberate improvement, see that function's own
    /// doc comment and `FLTK_ISSUES.md`). `int.min` (the sentinel
    /// `platformX11.resizeWindow()`'s own default parameters use) means
    /// "no override, compute the device-pixel position from FLTK units
    /// as usual." Set to the window's own *already-known-correct*
    /// device-pixel position for the duration of that one `resize()`
    /// call.
    ///
    /// This matters because "the window's position
    /// isn't supposed to change at all" cannot simply *omit* the position
    /// from the X11 request (an `XResizeWindow()` with no
    /// accompanying move, relying on X11's own window-gravity default to
    /// leave the top-left corner alone) -- a real window manager
    /// doesn't have to honor that the naive way: it can resize
    /// the window *about its centre* instead, silently overriding the
    /// unspecified position with its own placement heuristic -- every
    /// corner moving, not just the far corners a top-left-anchored
    /// resize would move. Explicitly telling the WM the exact position
    /// (still `XMoveResizeWindow()`, i.e. still asking for a move, just
    /// asking for the *same* device-pixel spot the window is already
    /// at) leaves it no unspecified position to apply its own heuristic
    /// to.
    ///
    /// `exactDeviceX_`/`exactDeviceY_`
    /// are `private static`, so they stay set for the *entire*
    /// duration of the top-level window's own `resize()` call --
    /// including the recursive `FlGroup.resize()` cascade into every
    /// child that call triggers. `isARescale_`'s own doc comment
    /// explicitly documents that this cascade deliberately reaches a
    /// nested subwindow like `CubeViewUI.fl`'s own `cube` (a `GlWindow`,
    /// itself a `Window` subclass with its own real X11 resource) --
    /// exactly the case this override has no business applying to: a
    /// subwindow's `resize()` call reading the *top-level* window's own
    /// absolute screen-device coordinates (computed for and correct
    /// only for the top-level) as if they were its own, via the exact
    /// same two static fields, would ask the X server to move *itself*
    /// there -- an absolute screen position used for a window whose
    /// real X11 parent is the top-level window, not the root, so the
    /// requested coordinates would be interpreted relative to entirely the
    /// wrong origin. `exactDeviceTarget_` records *which* window
    /// instance this override was actually computed for, so `resize()`
    /// below only honors it for that exact instance and passes the
    /// normal `int.min` ("compute it yourself") sentinel to every other
    /// window a rescale's cascade happens to resize along the way.
    private static Window exactDeviceTarget_ = null;
    private static int exactDeviceX_ = int.min;
    private static int exactDeviceY_ = int.min; /// ditto

    /**
     * Repositions/resizes this window to account for a screen-wide
     * scale change from `oldF` to `newF` (already in effect globally
     * by the time this runs -- see `fl.core.rescaleAllWindowsFromScreen()`,
     * the only caller) -- ported from `Fl_Window_Driver::resize_after_
     * scale_change()`. This window's own FLTK-unit `w()`/`h()` stay
     * exactly what they were *unless* `fullscreenActive()` (a
     * fullscreen window's FLTK-unit size must shrink/grow inversely
     * with scale, since it's still meant to exactly cover one
     * unchanging physical screen); `x()`/`y()` always rescale by
     * `oldF/newF` to keep the window's on-screen *center* roughly
     * anchored, then (non-fullscreen case only) get clamped so that
     * center stays within the new screen's bounds, matching FLTK's
     * own "make sure new window centre is located in new screen" `d =
     * 5`-pixel-margin logic exactly. Re-sends `WM_NORMAL_HINTS` (a
     * scale change alone can change the min/max *device-pixel* values
     * even when the FLTK-unit hints didn't change) before the actual
     * `resize()` call, matching FLTK's own `size_range()` call at
     * this same point ("adjust the OS-level boundary size values for
     * the window").
     */
    package(fl) void resizeAfterScaleChange(int ns, float oldF, float newF)
    {
        import std.math : lround;

        // **`rawScreenNum(ns)`, not the public, guarded `screenNum(ns)`**:
        // using the guarded setter here would be a no-op on an
        // already-`shown()` window, leaving it stuck
        // reporting its *old* screen after a cross-screen rescale --
        // load-bearing now that
        // `setCurrentForDraw()`/`makeCurrent()` read each window's own
        // `screenNum()` to pick its live drawing scale. FLTK keeps two distinct
        // setters here: the public `Fl_Window::screen_num(int)`
        // (`if (!shown()) pWindowDriver->screen_num(n);` -- "call this
        // before show()", matching this port's own guarded `screenNum()`
        // above) and the internal, unguarded `Fl_Window_Driver::
        // screen_num(int) { screen_num_ = n; }`, which is what `resize_
        // after_scale_change()` actually calls, bypassing the public
        // guard entirely since it's driver-internal code. This port has
        // no separate driver class to naturally keep the two apart, so
        // this calls the unguarded `rawScreenNum()` directly instead.
        rawScreenNum(ns);

        // Matches FLTK's own `Fl_Graphics_Driver::default_driver().
        // scale(new_f)` at this exact point in `resize_after_scale_
        // change()` -- keeps the live drawing scale (`fl.core.
        // currentScale()`, read by every `fl.draw` primitive) in step
        // with this window's own new per-screen factor even before its
        // next `draw()`/`makeCurrent()` call refreshes it from the
        // per-screen table directly.
        fl.core.currentScale(newF);

        // The window's actual, current on-screen device-pixel position.
        // Prefer the *confirmed* value `devicePosX_`/`devicePosY_` tracks
        // (kept live-updated by `fl.platform_x11`'s own `ConfigureNotify`
        // handler on every real geometry confirmation) over reconstructing
        // one from `x()`/`y()` (FLTK units) times `oldF`: once a *previous*
        // rescale has already rounded `x()`/`y()` to the nearest FLTK
        // unit, re-multiplying by the scale is not guaranteed to land back
        // on the exact device-pixel value that produced it -- e.g.
        // `x()==185` at `oldF==1.7f` reconstructs
        // `lround(185*1.7) == 315`, not the `314` that was actually on
        // screen and produced `x()==185` in the first place -- `185*1.7`
        // lands exactly on a rounding boundary `lround()` rounds up). Only
        // fall back to the reconstruction for a window that's never had
        // its position confirmed yet (shouldn't normally happen -- a
        // window being rescaled is by definition already shown()). No
        // FLTK equivalent -- a deliberate improvement, see
        // `FLTK_ISSUES.md`.
        int devX = devicePosX_ != int.min ? devicePosX_ : cast(int) lround(x() * cast(double) oldF);
        int devY = devicePosY_ != int.min ? devicePosY_ : cast(int) lround(y() * cast(double) oldF);

        // Candidate FLTK-unit position/size for the *screen-boundary*
        // check just below only -- FLTK's own conversion truncates
        // here (`int(x() * old_f / new_f)`), which rounds toward zero
        // rather than to nearest and so only ever discards a fractional
        // pixel, never adds one back; `lround()` at least removes that
        // directional bias for the (rare) case where clamping actually
        // fires and this candidate value is what ends up used for real.
        int X = cast(int) lround(x() * oldF / newF);
        int Y = cast(int) lround(y() * oldF / newF);
        int W, H;
        bool clamped = false;
        if (fullscreenActive())
        {
            // A fullscreen window's FLTK-unit size genuinely must
            // change (it still has to exactly cover one unchanging
            // physical screen), so there's no unchanged physical spot
            // to preserve here the way the ordinary case below has --
            // leave this path exactly as FLTK's own conversion.
            W = cast(int) lround(w() * oldF / newF);
            H = cast(int) lround(h() * oldF / newF);
            clamped = true;
        }
        else
        {
            W = w();
            H = h();
            int sX, sY, sW, sH;
            fl.core.screenXYWH(sX, sY, sW, sH, ns);
            enum d = 5; // make sure the new window center lands in the new screen
            if (X + W / 2 < sX) { X = sX - W / 2 + d; clamped = true; }
            else if (X + W / 2 > sX + sW - 1) { X = sX + sW - 1 - W / 2 - d; clamped = true; }
            if (Y + H / 2 < sY) { Y = sY - H / 2 + d; clamped = true; }
            else if (Y + H / 2 > sY + sH - 1) { Y = sY + sH - 1 - H / 2 - d; clamped = true; }
        }

        version (linux) platformX11.sizeRangeChanged(this);

        isARescale_ = true;
        if (!clamped)
        {
            // Common case: the window's centre already lands inside its
            // screen without adjustment, so it was never actually
            // supposed to move at all. Recompute the FLTK-unit X/Y
            // directly from the untouched device-pixel position instead
            // of the candidate above -- a single division, done once,
            // purely for internal bookkeeping -- and tell resize() below
            // to send that exact device-pixel spot to the window manager
            // explicitly (`exactDeviceX_`/`exactDeviceY_`) rather than
            // reissuing `devX`/`devY` through a second lossy FLTK-unit
            // round-trip (compute X, then have resizeWindow() convert X
            // back to device pixels via newF) that has no guarantee of
            // landing back on the same integer. The window's real
            // on-screen position is then guaranteed byte-identical to
            // before, not merely closely approximated.
            X = cast(int) lround(devX / cast(double) newF);
            Y = cast(int) lround(devY / cast(double) newF);
            exactDeviceX_ = devX;
            exactDeviceY_ = devY;
            exactDeviceTarget_ = this;
        }
        resize(X, Y, W, H);
        exactDeviceX_ = int.min;
        exactDeviceY_ = int.min;
        exactDeviceTarget_ = null;
        isARescale_ = false;
    }

    /**
     * Positions this window so that point `(X, Y)` *within* it lands
     * under the current mouse position -- e.g. `hotspot(w()/2, h()/2)`
     * centers the window on the mouse. Ported from
     * `Fl_Window::hotspot(int, int, int)` (`src/Fl_Window_hotspot.cxx`).
     * Used by `fl.ask`'s message dialogs to appear where the user is
     * looking, matching FLTK's own default behavior there.
     *
     * **Real multi-monitor targeting**: clamps against the actual bounding box of whichever
     * monitor contains the mouse (`fl.core.getMouse()`'s now-real
     * returned screen index, fed into `fl.core.screenXYWH()`), matching
     * FLTK's own `this->screen_num(ms)` + `Fl::screen_work_area()`
     * pairing in spirit. Two remaining simplifications versus FLTK:
     * `screen_work_area()` (monitor bounds minus taskbar/dock -- see
     * `fl.platform_x11`'s own note on why this wasn't ported alongside
     * `screen_xywh()`) collapses to the plain monitor bounding box, and
     * no window-manager decoration-size query
     * (`pWindowDriver->decoration_sizes()` isn't ported -- no concept of
     * border/titlebar pixel dimensions exists anywhere in this port --
     * so the on-screen clamp below treats the border as zero-sized
     * rather than reserving real space for it).
     */
    void hotspot(int X, int Y, bool offscreen = false)
    {
        int mx, my;
        int screenIdx = fl.core.getMouse(mx, my);
        X = mx - X;
        Y = my - Y;

        if (!offscreen)
        {
            int scrX, scrY, scrW, scrH;
            fl.core.screenXYWH(scrX, scrY, scrW, scrH, screenIdx);

            if (X + w() > scrW + scrX) X = scrW + scrX - w();
            if (X < scrX) X = scrX;
            if (Y + h() > scrH + scrY) Y = scrH + scrY - h();
            if (Y < scrY) Y = scrY;
            // Force this position even if it happens to already match
            // x() -- matches FLTK's `if (X==x()) x(X-1);` trick
            // (FLTK's Fl_Widget::x(int) is a bare field setter, no
            // resize/redraw side effect; this port's Widget has no such
            // single-axis setter, so position(X-1, y()) substitutes --
            // same net effect, one extra y() round-trip). Ensures the
            // position() call just below is never silently dropped as
            // a no-op by some future caller that compares against the
            // previous position before applying a move.
            if (X == x()) position(X - 1, y());
        }

        position(X, Y);
    }

    /// ditto -- centers widget `o` under the mouse instead of an
    /// explicit point, by walking up to the containing window (or this
    /// window itself) to accumulate `o`'s offset first. Ported from
    /// `Fl_Window::hotspot(const Fl_Widget*, int)`.
    void hotspot(Widget o, bool offscreen = false)
    {
        int X = o.w() / 2;
        int Y = o.h() / 2;
        Widget ow = o;
        while (ow !is this && ow !is null)
        {
            X += ow.x();
            Y += ow.y();
            ow = ow.window();
        }
        hotspot(X, Y, offscreen);
    }

    /// The window's position on the screen, in root (screen) coordinates.
    /// Ported from `Fl_Window::x_root()`/`y_root()` (`src/Fl_Window.cxx`):
    /// for a top-level window, `x()`/`y()` already *is* the on-screen
    /// position (kept current by `ConfigureNotify` handling, see
    /// `fl.platform_x11`), so this only needs real work for a subwindow,
    /// recursively adding its own `x()`/`y()` (relative to its immediate
    /// parent) to the parent window's own `xRoot()`/`yRoot()`. No new X11
    /// query needed -- purely derived from state already tracked.
    int xRoot() const
    {
        auto p = window();
        return p !is null ? p.xRoot() + x() : x();
    }

    /// ditto
    int yRoot() const
    {
        auto p = window();
        return p !is null ? p.yRoot() + y() : y();
    }

    /// Non-zero (bit 1 for horizontal, bit 2 for vertical) if the
    /// window is resizable in that direction -- computes
    /// defaultSizeRange() first if sizeRange() was never called
    /// explicitly. Ported from `Fl_Window::is_resizable()`
    /// (`src/Fl_Window.cxx`); used by fullscreen() below to match
    /// FLTK's own "fullscreen requires a resizable window" gate.
    int isResizable()
    {
        defaultSizeRange();
        int ret = 0;
        if (minw_ != maxw_) ret |= 1;
        if (minh_ != maxh_) ret |= 2;
        return ret;
    }

    /// True once fullscreen() has taken effect and fullscreenOff()
    /// hasn't undone it. Ported from `Fl_Window::fullscreen_active()`.
    bool fullscreenActive() const { return (flags() & Flag.fullscreen) != 0; }

    /// Internal use only; called by fl.platform_x11's fullscreenOn()/
    /// fullscreenOff() once the EWMH request has actually been sent.
    /// Ported from `Fl_Widget::_set_fullscreen()`/`_clear_fullscreen()`
    /// (`FL/Fl_Widget.H`) -- FLTK's `Fl_X11_Window_Driver::
    /// fullscreen_on()`/`fullscreen_off()` call these on the *window*
    /// (`pWindow->_set_fullscreen();`) themselves; missing this call
    /// was a real bug in this port's first pass (fullscreenActive()
    /// never actually flipped true when going through the shown()
    /// path, so a second fullscreen()/fullscreenOff() toggle call kept
    /// re-requesting fullscreen instead of turning it off -- caught by
    /// the user interactively testing smoke-tests/fullscreen.d).
    package(fl) void setFullscreenFlag() { setFlag(Flag.fullscreen); }
    package(fl) void clearFullscreenFlag() { clearFlag(Flag.fullscreen); } /// ditto

    /// True once maximize() has taken effect and unMaximize() hasn't
    /// undone it. Ported from `Fl_Window::maximize_active()`.
    bool maximizeActive() const { return (flags() & Flag.maximized) != 0; }

    /// Internal use only; called by fl.platform_x11's PropertyNotify
    /// handling to reflect an externally-triggered maximize/unmaximize
    /// (e.g. double-clicking the title bar) back into maximizeActive().
    /// Ported from `Fl_Window::is_maximized_(bool)` -- unlike
    /// maximize()/unMaximize() themselves, this has no shown()/
    /// isResizable()/fullscreenActive() gate, matching FLTK: it's
    /// reacting to a state change that already happened, not
    /// requesting one.
    package(fl) void setMaximizedFlag() { setFlag(Flag.maximized); }
    package(fl) void clearMaximizedFlag() { clearFlag(Flag.maximized); } /// ditto

    private int noFullscreenX_, noFullscreenY_, noFullscreenW_, noFullscreenH_;

    /**
     * The platform-independent maximize: remember the current geometry,
     * then resize to the screen's work area, less the window's own
     * decorations. Ported from `Fl_Window_Driver::maximize()`
     * (`src/Fl_Window_Driver.cxx`), which a platform driver falls back to
     * when it can't ask the system to maximize -- on Windows, for a
     * borderless window (`fl.platform_win32.maximizeOn()`).
     * `needsHideShow` is FLTK's `maximize_needs_hide()` (true on
     * Windows): the window is hidden around the resize and shown again.
     */
    package(fl) void maximizeByResize(bool needsHideShow)
    {
        rememberUnmaximizedGeometry();
        int X, Y, W, H;
        fl.core.screenWorkArea(X, Y, W, H, screenNum());
        int dw = decoratedW() - w();
        int dh = decoratedH() - h() - dw;
        if (needsHideShow) hide(); // FLTK: "pb may occur in subwindow without this"
        resize(X + dw / 2, Y + dh + dw / 2, W - dw, H - dh - dw);
        if (needsHideShow) show();
    }

    /// Records the current geometry for unMaximizeByResize(). Called by
    /// maximizeByResize(), and by `fl.platform_win32.maximizeOn()`
    /// before a system maximize too: `border()` can change while the
    /// window is maximized, so the restore may end up going through
    /// unMaximizeByResize() even when the maximize did not.
    package(fl) void rememberUnmaximizedGeometry()
    {
        noFullscreenX_ = x();
        noFullscreenY_ = y();
        noFullscreenW_ = w();
        noFullscreenH_ = h();
    }

    /// The reverse of maximizeByResize(), ported from
    /// `Fl_Window_Driver::un_maximize()`: back to the remembered geometry.
    /// **Deviation**: does not resize when nothing was remembered (FLTK
    /// would resize to 0x0 at 0,0, leaving the window invisible).
    package(fl) void unMaximizeByResize()
    {
        if (noFullscreenW_ > 0 && noFullscreenH_ > 0)
            resize(noFullscreenX_, noFullscreenY_, noFullscreenW_, noFullscreenH_);
        noFullscreenX_ = noFullscreenY_ = noFullscreenW_ = noFullscreenH_ = 0;
    }

    /**
     * Makes the window fill its screen with no window-manager
     * decorations, via the EWMH `_NET_WM_STATE_FULLSCREEN` protocol on
     * Linux (see `fl.platform_x11.fullscreenOn()` for the exact scope
     * -- EWMH-supporting window managers only). Ported from
     * `Fl_Window::fullscreen()` (`src/Fl_Window_fullscreen.cxx`); call
     * fullscreenOff() to undo. A no-op if isResizable() reports the
     * window isn't resizable in *either* direction, matching FLTK
     * exactly -- a plain `Window` with no explicit `resizable()` widget
     * is fixed-size by default (see defaultSizeRange()), so call
     * `resizable(someChild)` (or `resizable(this)`) first if
     * fullscreen() should actually take effect.
     *
     * Matches FLTK's `!maximize_active()` gate on recording the
     * pre-fullscreen geometry: if the window is already maximized when
     * fullscreen() is called, the geometry `unMaximize()` would restore
     * is left alone rather than being overwritten with the maximized
     * geometry.
     */
    void fullscreen()
    {
        if (!isResizable()) return;

        if (!maximizeActive())
        {
            noFullscreenX_ = x();
            noFullscreenY_ = y();
            noFullscreenW_ = w();
            noFullscreenH_ = h();
        }

        if (shown() && !fullscreenActive())
        {
            version (linux) platformX11.fullscreenOn(this);
            version (Windows) platformWin32.fullscreenOn(this);
        }
        else
            setFlag(Flag.fullscreen);
    }

    /**
     * Turns off any side effects of fullscreen() and moves/resizes the
     * window to (X,Y,W,H) -- except on Linux's EWMH path, where the
     * window manager restores the pre-fullscreen geometry on its own
     * once `_NET_WM_STATE_FULLSCREEN` is cleared, so (X,Y,W,H) go
     * unused there. On Windows there's no such window-manager-side
     * restore at all -- `fl.platform_win32.fullscreenOff()` is the
     * "future non-EWMH/other-platform path" this doc comment used to
     * describe hypothetically; it actually needs and uses (X,Y,W,H),
     * matching FLTK's own `Fl_WinAPI_Window_Driver::fullscreen_off(
     * int,int,int,int)` exactly.
     */
    void fullscreenOff(int X, int Y, int W, int H)
    {
        if (shown() && fullscreenActive())
        {
            version (linux) platformX11.fullscreenOff(this);
            version (Windows) platformWin32.fullscreenOff(this, X, Y, W, H);
        }
        else
            clearFlag(Flag.fullscreen);

        if (!maximizeActive())
            noFullscreenX_ = noFullscreenY_ = noFullscreenW_ = noFullscreenH_ = 0;
    }

    /// ditto -- restores the geometry recorded by the fullscreen()
    /// call being undone (or, if fullscreen() was somehow never
    /// called, the window's current position with its existing size).
    void fullscreenOff()
    {
        if (noFullscreenX_ == 0 && noFullscreenY_ == 0)
        {
            noFullscreenX_ = x();
            noFullscreenY_ = y();
        }
        fullscreenOff(noFullscreenX_, noFullscreenY_, noFullscreenW_, noFullscreenH_);
    }

    private int fullscreenScreenTop_ = -1;
    private int fullscreenScreenBottom_ = -1;
    private int fullscreenScreenLeft_ = -1;
    private int fullscreenScreenRight_ = -1;

    /**
     * Sets which screens should be used when this window is in
     * fullscreen mode: the window spans from the top edge of monitor
     * `top` to the bottom edge of monitor `bottom`, the left edge of
     * `left` to the right edge of `right` (so a single value repeated
     * four times spans exactly that one monitor; different values let
     * the window span multiple physical monitors). If never called, or
     * if any argument is negative, the window fills whichever single
     * screen it's currently on -- ported from
     * `Fl_Window::fullscreen_screens()` (`src/Fl_Window_fullscreen.cxx`).
     * Backed by `fl.core.screenNum()`/`screenXYWH()`'s real Xinerama
     * geometry (see
     * `fl.platform_x11.fullscreenOn()`'s own doc comment).
     */
    void fullscreenScreens(int top, int bottom, int left, int right)
    {
        if (top < 0 || bottom < 0 || left < 0 || right < 0)
        {
            fullscreenScreenTop_ = -1;
            fullscreenScreenBottom_ = -1;
            fullscreenScreenLeft_ = -1;
            fullscreenScreenRight_ = -1;
        }
        else
        {
            fullscreenScreenTop_ = top;
            fullscreenScreenBottom_ = bottom;
            fullscreenScreenLeft_ = left;
            fullscreenScreenRight_ = right;
        }

        if (shown() && fullscreenActive())
        {
            version (linux) platformX11.fullscreenOn(this);
            version (Windows) platformWin32.fullscreenOn(this);
        }
    }

    /// package(fl): read by fl.platform_x11.fullscreenOn() to build the
    /// `_NET_WM_FULLSCREEN_MONITORS` request. -1 means "unset".
    package(fl) int fullscreenScreenTop() const { return fullscreenScreenTop_; }
    package(fl) int fullscreenScreenBottom() const { return fullscreenScreenBottom_; } /// ditto
    package(fl) int fullscreenScreenLeft() const { return fullscreenScreenLeft_; } /// ditto
    package(fl) int fullscreenScreenRight() const { return fullscreenScreenRight_; } /// ditto

    private int screenNum_ = -1;

    /**
     * The index (0 .. `fl.core.screenCount()` - 1) of the monitor this
     * window is mapped on, if shown() -- undefined/meaningless otherwise
     * (matching FLTK's own doc note). Ported from
     * `Fl_Window::screen_num() const` (`src/Fl_Window.cxx`), which
     * forwards to `Fl_Window_Driver::screen_num()`
     * (`src/Fl_Window_Driver.cxx`): a subwindow always delegates to its
     * `topWindow()`'s value; a top-level window returns a value cached
     * at creation time by `fl.platform_x11.createWindow()` (see that
     * function for how the cache is populated -- either an explicit
     * pre-show() `screenNum(int)` call below, or `fl.core.firstWindow()`'s
     * screen as a fallback hint, matching FLTK's own
     * `Fl_X11_Window_Driver`/`Fl_x.cxx` creation-time logic). **Real,
     * live-updated as a shown window is dragged across monitors**: on
     * Linux, `fl.platform_x11`'s `ConfigureNotify` handler relocates the cache
     * (`rawScreenNum()`) whenever a window's centre crosses screens; on
     * Windows, `fl.platform_win32`'s `WM_DPICHANGED`/`WM_MOVE` handlers
     * do the equivalent, matching FLTK's own `Fl_Window_Driver::
     * screen_num(int)` (an unguarded internal setter, distinct from the
     * public, `!shown()`-guarded `Fl_Window::screen_num(int)` below) --
     * see `rawScreenNum()`'s own doc comment for why this port needs a
     * separate escape hatch for that distinction. Menu-window
     * repositioning still doesn't relocate this cache, matching
     * FLTK's own scope for that mechanism.
     */
    int screenNum() const
    {
        if (parent() !is null) return topWindow().screenNum();
        return screenNum_ >= 0 ? screenNum_ : 0;
    }

    /**
     * Requests that this window map onto monitor `n` when it's next
     * shown() -- call this (and set the desired `x()`/`y()`) *before*
     * show(), matching FLTK's own documented usage; a no-op once the
     * window is already shown() or if `n` is out of
     * `fl.core.screenCount()`'s range. Ported from
     * `Fl_Window::screen_num(int)`.
     */
    void screenNum(int n)
    {
        if (!shown() && n >= 0 && n < fl.core.screenCount()) screenNum_ = n;
    }

    /// package(fl): the raw cache `screenNum()`'s getter reads and
    /// `screenNum(int)`'s setter writes -- `-1` means "never explicitly
    /// set or computed yet". Used by `fl.platform_x11.createWindow()` to
    /// tell an explicit pre-show() `screenNum(int)` call apart from an
    /// unset window it needs to fill in a creation-time default for.
    package(fl) int rawScreenNum() const { return screenNum_; }
    package(fl) void rawScreenNum(int n) { screenNum_ = n; } /// ditto

    /// `int.min` = "never confirmed yet". The window's true, exact
    /// on-screen device-pixel position, as last confirmed by a real
    /// `ConfigureNotify` (`fl.platform_x11`'s handler calls
    /// `devicePos(rx, ry)` there on *every* geometry confirmation, not
    /// just rescale-driven ones -- a drag, a WM-driven move, anything).
    /// No FLTK equivalent -- exists purely to back
    /// `resizeAfterScaleChange()`'s non-clamped case (see that
    /// function's own doc comment): deriving "the window's current
    /// device-pixel position" by reading `x()`/`y()` (FLTK units) and
    /// multiplying by the old scale is *not* exact once a previous
    /// rescale has already rounded `x()`/`y()` to the nearest FLTK unit
    /// -- e.g. `x()==185`,
    /// `oldF==1.7f` reconstructs `lround(185*1.7) == 315`, not the `314`
    /// that produced `x()==185` in the first place, purely because
    /// `185*1.7 == 314.5` lands exactly on a rounding boundary that
    /// `lround()` rounds up. That reconstructed-but-wrong value would
    /// then get sent to the window manager as the "unchanged" position
    /// on the *next* rescale, silently turning a bookkeeping rounding
    /// artifact into a real, visible 1px move. Tracking the confirmed
    /// exact value directly, instead of reconstructing an approximation
    /// of it from a lossier representation, sidesteps the whole problem.
    package(fl) int devicePosX_ = int.min;
    package(fl) int devicePosY_ = int.min; /// ditto

    /**
     * Maximizes a top-level window to its current screen, via the EWMH
     * `_NET_WM_STATE_MAXIMIZED_VERT`/`_HORZ` protocol on Linux (see
     * `fl.platform_x11.maximizeOn()` for the exact scope -- EWMH-
     * supporting window managers only). Ported from
     * `Fl_Window::maximize()` (`src/Fl_Window.cxx`); call unMaximize()
     * to undo. Effective only for a shown(), top-level (no parent()),
     * resizable window that isn't already maximized or fullscreen --
     * matches FLTK's gate exactly, including that (unlike
     * fullscreen()) this is a true no-op rather than a
     * deferred-until-shown one: FLTK's `Fl_Window::maximize()` bails
     * out entirely on `!shown()` rather than recording state to apply
     * later, so calling this before show() does nothing at all (call it
     * again after show() if that's what's wanted).
     *
     * Externally-triggered maximize/unmaximize (e.g. the user double-
     * clicking the title bar) is tracked too,
     * via `fl.platform_x11`'s `PropertyNotify` handling reading
     * `_NET_WM_STATE` back and calling `setMaximizedFlag()`/
     * `clearMaximizedFlag()` -- see that module's own doc comment for
     * the exact scope (fullscreen state is synced the same way, firing
     * `Event.fullscreen`; maximize has no equivalent event FLTK
     * either, matching `Fl_Window::is_maximized_(bool)`'s plain flag
     * update with no `Fl::handle()` call).
     */
    void maximize()
    {
        if (!shown() || parent() !is null || !isResizable() || maximizeActive() || fullscreenActive())
            return;
        setFlag(Flag.maximized);
        version (linux) platformX11.maximizeOn(this);
        version (Windows) platformWin32.maximizeOn(this);
    }

    /**
     * Returns a previously maximize()'d top-level window to its
     * previous size. Ported from `Fl_Window::un_maximize()`. Same gate
     * as maximize() in reverse (shown(), top-level, currently
     * maximized, not fullscreen); a no-op otherwise.
     */
    void unMaximize()
    {
        if (!shown() || parent() !is null || !isResizable() || !maximizeActive() || fullscreenActive())
            return;
        clearFlag(Flag.maximized);
        version (linux) platformX11.maximizeOff(this);
        version (Windows) platformWin32.maximizeOff(this);
    }

    /**
     * Whether the *next* top-level window shown will be created already
     * iconified (born iconified, no visible-then-minimized flash) --
     * ported from `Fl_Window::show_next_window_iconic(char)`/`()`. A
     * process-wide flag (matching FLTK's own `static char` on
     * `Fl_Window`), backed by `fl.core.showNextWindowIconic_`, consumed
     * and reset by `fl.platform_x11.createWindow()`'s `WM_HINTS` setup
     * the moment a window is actually created. See `iconize()`'s own
     * doc comment for the consumer half.
     */
    static void showNextWindowIconic(bool v) { fl.core.showNextWindowIconic_ = v; }
    static bool showNextWindowIconic() { return fl.core.showNextWindowIconic_; } /// ditto

    /**
     * Iconifies (minimizes) this top-level window. Ported from
     * `Fl_Window::iconize()` (`src/Fl_Window_iconize.cxx`),
     * including FLTK's own `!shown()` branch
     * (`show_next_window_iconic(1); show();`): a bare `iconize()` call
     * on a not-yet-shown window sets `showNextWindowIconic(true)` then
     * calls `show()`, which `fl.platform_x11.createWindow()` consumes
     * via `WM_HINTS.initial_state = IconicState` before the window is
     * ever mapped, so it's genuinely born iconified rather than
     * flashing visible first. The real, `shown()` case
     * (`Fl_X11_Window_Driver::iconize()`: `XIconifyWindow()`, a single
     * standard, ICCCM-compliant Xlib call) is unchanged.
     */
    void iconize()
    {
        if (!shown())
        {
            showNextWindowIconic(true);
            show();
        }
        else
        {
            version (linux) platformX11.iconizeWindow(this);
            version (Windows) platformWin32.iconizeWindow(this);
        }
    }

    /**
     * Blocks until this window has received its first real repaint
     * since being shown -- useful right after `show()` when the very
     * next thing a program does (e.g. `takeFocus()`) needs the window
     * to genuinely be on screen first, not just requested. Ported from
     * `Fl_Window::wait_for_expose()` (`src/Fl_Window.cxx`); see
     * `fl.platform_x11.waitForExpose()`'s own doc comment for the exact
     * mechanism. A no-op if this window isn't `shown()`.
     */
    void waitForExpose()
    {
        version (linux) platformX11.waitForExpose(this);
    }

    /// Whether this window is a popup/tooltip-style menu window (an
    /// override-redirect, undecorated top-level created by
    /// `fl.menu_popup`/`fl.tooltip`, not an ordinary application
    /// window). Ported from `Fl_Window::menu_window()` (`FL/
    /// Fl_Window.H`) -- the flag itself (`Widget.Flag.menuWindow`) was
    /// already set by both real callers; this query accessor was the
    /// missing piece, found via `source/test/pixmap_browser.d`, which
    /// uses it to skip forcing a redraw on popups while walking every
    /// shown window.
    bool menuWindow() const
    {
        return (flags() & Flag.menuWindow) != 0;
    }
}

unittest
{
    FlGroup.current(null);

    auto w = new Window(10, 20, 300, 200, "positioned");
    assert(w.x() == 10 && w.y() == 20 && w.w() == 300 && w.h() == 200);
    assert(w.type() == Widget.windowTypeTag);

    auto w2 = new Window(300, 200, "unpositioned");
    assert(w2.x() == 0 && w2.y() == 0 && w2.w() == 300 && w2.h() == 200);
    assert(w2.type() == Widget.windowTypeTag);

    FlGroup.current(null);
}

unittest
{
    FlGroup.current(null);

    auto w = new Window(300, 200, "x");
    int minW, minH, maxW, maxH;
    assert(w.getSizeRange(&minW, &minH, &maxW, &maxH) == false); // never set

    w.sizeRange(100, 80, 400, 300);
    assert(w.getSizeRange(&minW, &minH, &maxW, &maxH) == true);
    assert(minW == 100 && minH == 80 && maxW == 400 && maxH == 300);

    FlGroup.current(null);
}

// defaultSizeRange() -- pure geometry, no X server needed, so this can
// be covered directly unlike most of fl.window/fl.platform_x11.
unittest
{
    import fl.box : Box;

    int minW, minH, maxW, maxH;

    // No resizable(): fixed size (min == max == current size).
    FlGroup.current(null);
    auto fixed = new Window(300, 200, "fixed");
    fixed.end();
    fixed.defaultSizeRange();
    assert(fixed.getSizeRange(&minW, &minH, &maxW, &maxH) == true);
    assert(minW == 300 && minH == 200 && maxW == 300 && maxH == 200);
    FlGroup.current(null);

    // resizable() == the window itself, larger than the 100x100 cap --
    // FLTK's own doc-comment example (Fl_Window win(400,400);
    // win.resizable(win); // win.size_range(100, 100, 0, 0);).
    auto self = new Window(400, 400, "self");
    self.resizable(self);
    self.end();
    self.defaultSizeRange();
    assert(self.getSizeRange(&minW, &minH, &maxW, &maxH) == true);
    assert(minW == 100 && minH == 100 && maxW == 0 && maxH == 0);
    FlGroup.current(null);

    // resizable() a child widget, clipped+capped -- also FLTK's own
    // doc-comment example (Fl_Window win(400,400); Fl_Box box(20,20,
    // 360,360); win.resizable(box); // win.size_range(140,140,0,0);).
    auto withChild = new Window(400, 400, "child");
    auto box = new Box(20, 20, 360, 360);
    withChild.resizable(box);
    withChild.end();
    withChild.defaultSizeRange();
    assert(withChild.getSizeRange(&minW, &minH, &maxW, &maxH) == true);
    assert(minW == 140 && minH == 140 && maxW == 0 && maxH == 0);
    FlGroup.current(null);

    // A zero-width resizable() disables horizontal resizing entirely
    // (min == max == current width), independent of the vertical
    // calculation.
    auto zeroWidth = new Window(300, 200, "zero-width");
    auto vBox = new Box(50, 0, 0, 200);
    zeroWidth.resizable(vBox);
    zeroWidth.end();
    zeroWidth.defaultSizeRange();
    assert(zeroWidth.getSizeRange(&minW, &minH, &maxW, &maxH) == true);
    assert(minW == 300 && maxW == 300);
    FlGroup.current(null);

    // An explicit sizeRange() call beats defaultSizeRange() -- it's a
    // no-op once sizeRangeSet_ is already true, matching FLTK's
    // own `if (size_range_set_) return;` guard.
    auto explicit_ = new Window(300, 200, "explicit");
    explicit_.sizeRange(10, 10, 20, 20);
    explicit_.end();
    explicit_.defaultSizeRange();
    assert(explicit_.getSizeRange(&minW, &minH, &maxW, &maxH) == true);
    assert(minW == 10 && minH == 10 && maxW == 20 && maxH == 20);
    FlGroup.current(null);
}

// isResizable() -- also pure geometry (computes defaultSizeRange()
// internally), no X server needed.
unittest
{
    import fl.box : Box;

    // No resizable(): fixed size, not resizable in either direction.
    FlGroup.current(null);
    auto fixed = new Window(300, 200, "fixed");
    fixed.end();
    assert(fixed.isResizable() == 0);
    FlGroup.current(null);

    // resizable() == self: resizable in both directions.
    auto both = new Window(400, 400, "both");
    both.resizable(both);
    both.end();
    assert(both.isResizable() == 3); // bit 1 | bit 2

    FlGroup.current(null);

    // A zero-width resizable() child disables horizontal resizing only
    // -- still resizable vertically.
    auto vOnly = new Window(300, 200, "v-only");
    auto vBox = new Box(50, 0, 0, 200);
    vOnly.resizable(vBox);
    vOnly.end();
    assert(vOnly.isResizable() == 2); // vertical bit only
    FlGroup.current(null);

    // An explicit fixed sizeRange() (min == max in both dimensions)
    // reports not resizable, same as never calling sizeRange() at all.
    auto explicitFixed = new Window(300, 200, "explicit-fixed");
    explicitFixed.sizeRange(300, 200, 300, 200);
    explicitFixed.end();
    assert(explicitFixed.isResizable() == 0);
    FlGroup.current(null);
}

// fullscreenActive()/fullscreen()'s isResizable() gate -- the parts
// that don't need a live X server (fullscreen()/fullscreenOff()'s
// actual EWMH ClientMessage only fires once shown(), which needs a
// real display -- see smoke-tests/fullscreen.d for that half).
unittest
{
    FlGroup.current(null);

    // fullscreen() is a no-op on a never-shown, non-resizable window
    // (isResizable() == 0): the flag never gets set.
    auto notResizable = new Window(300, 200, "not resizable");
    notResizable.end();
    notResizable.fullscreen();
    assert(!notResizable.fullscreenActive());
    FlGroup.current(null);

    // On a resizable-but-never-shown window, fullscreen() takes the
    // `else setFlag(Flag.fullscreen);` branch directly (matching
    // FLTK's own `if (shown() && ...) {...} else set_flag(...);`),
    // since platformX11.fullscreenOn() is only reachable once shown().
    auto resizable_ = new Window(300, 200, "resizable, unshown");
    resizable_.resizable(resizable_);
    resizable_.end();
    resizable_.fullscreen();
    assert(resizable_.fullscreenActive());
    resizable_.fullscreenOff(0, 0, 300, 200);
    assert(!resizable_.fullscreenActive());
    FlGroup.current(null);
}

// fullscreenScreens()'s own bookkeeping -- the part that doesn't need a
// live X server (the actual _NET_WM_FULLSCREEN_MONITORS ClientMessage
// only fires once shown() *and* fullscreenActive(), matching FLTK's
// `if (shown() && fullscreen_active()) pWindowDriver->fullscreen_on();`
// tail call).
unittest
{
    FlGroup.current(null);

    auto win = new Window(300, 200, "fullscreen screens");
    win.end();

    // Defaults to "unset" (-1 on every field).
    assert(win.fullscreenScreenTop() == -1);
    assert(win.fullscreenScreenBottom() == -1);
    assert(win.fullscreenScreenLeft() == -1);
    assert(win.fullscreenScreenRight() == -1);

    win.fullscreenScreens(1, 2, 0, 3);
    assert(win.fullscreenScreenTop() == 1);
    assert(win.fullscreenScreenBottom() == 2);
    assert(win.fullscreenScreenLeft() == 0);
    assert(win.fullscreenScreenRight() == 3);

    // Any negative argument resets every field to "unset" (matching
    // FLTK's `(top < 0) || (bottom < 0) || (left < 0) || (right < 0)`
    // reset condition -- not just the negative one).
    win.fullscreenScreens(1, -1, 0, 3);
    assert(win.fullscreenScreenTop() == -1);
    assert(win.fullscreenScreenBottom() == -1);
    assert(win.fullscreenScreenLeft() == -1);
    assert(win.fullscreenScreenRight() == -1);

    // Never shown() -> the shown()&&fullscreenActive() tail call never
    // fires, so this stays a pure bookkeeping call, same reasoning as
    // fullscreen()'s own "never-shown" test case just above.
    win.fullscreenScreens(0, 0, 0, 0);
    assert(!win.fullscreenActive());

    FlGroup.current(null);
}

unittest
{
    // border(): true by default, settable both ways, backed by
    // Flag.noBorder (pure bookkeeping here -- the actual
    // _MOTIF_WM_HINTS effect only happens once shown(), see
    // fl.platform_x11.createWindow()).
    FlGroup.current(null);

    auto w = new Window(300, 200, "bordered by default");
    assert(w.border());

    w.border(false);
    assert(!w.border());

    w.border(true);
    assert(w.border());

    w.clearBorder();
    assert(!w.border());

    FlGroup.current(null);
}

// maximizeActive()/maximize()/unMaximize()'s shown() gate -- unlike
// fullscreen() (which still sets its flag on an unshown, resizable
// window), FLTK's Fl_Window::maximize()/un_maximize() bail out
// entirely on !shown(), so there's no "unshown but flagged" state to
// exercise here headlessly -- only that both calls are true no-ops
// without a live display (the actual EWMH ClientMessage only fires
// once shown(), which needs a real window manager -- not covered by
// `dub test`).
unittest
{
    FlGroup.current(null);

    auto resizable_ = new Window(300, 200, "resizable, unshown");
    resizable_.resizable(resizable_);
    resizable_.end();

    resizable_.maximize();
    assert(!resizable_.maximizeActive()); // no-op: shown() is false

    resizable_.unMaximize();
    assert(!resizable_.maximizeActive()); // no-op: not maximized either

    FlGroup.current(null);

    // Also a no-op when not resizable, same as fullscreen()'s gate.
    auto notResizable = new Window(300, 200, "not resizable");
    notResizable.end();
    notResizable.maximize();
    assert(!notResizable.maximizeActive());
    FlGroup.current(null);
}

unittest
{
    // modal()/setModal()/setNonModal()/freePosition(): pure flag
    // bookkeeping, same category as border()'s own unittest above.
    // hotspot() isn't covered here -- it calls fl.core.getMouse(),
    // which needs a live X display (see fl.platform_x11's module note
    // on why that file has no unittest blocks at all); verify it
    // interactively instead, e.g. via fl.ask's message dialogs.
    FlGroup.current(null);

    auto w = new Window(300, 200, "not modal by default");
    assert(!w.modal());

    w.setModal();
    assert(w.modal());

    // setNonModal() is NOT modal()'s inverse -- FLTK documents three
    // independent window states (modal/non-modal/normal, see
    // Fl_Window::set_non_modal()'s own doc comment), so it sets a
    // distinct Flag.nonModal bit rather than clearing Flag.modal.
    auto w2 = new Window(300, 200, "non-modal");
    w2.setNonModal();
    assert(!w2.modal());

    FlGroup.current(null);
}

unittest
{
    // The constructor's own default callback (ported from
    // Fl_Window::default_callback/Fl::default_atclose): hide() the
    // window, then still push it onto the read queue like any other
    // widget's default. hide() is a safe no-op here (shown() is false,
    // never actually show()n against a live display), but the queue
    // push is real and headless-testable.
    import fl.core : readqueue, resetForTest;

    FlGroup.current(null);
    resetForTest();

    auto w = new Window(300, 200, "closable by default");
    assert(!w.shown());

    w.doCallback(); // matches Event.close's wi.doCallback(CallbackReason.closed)
    assert(!w.shown()); // hide() no-op'd cleanly, no live display needed
    assert(readqueue() is w);
    assert(readqueue() is null); // queue drained

    resetForTest();
    FlGroup.current(null);
}

unittest
{
    // xclass()/defaultXclass(): the process-wide default state is
    // reset around this test (see CONVENTIONS.md's "shared static state
    // needs hermetic tests" convention) since Window.defaultXclass_ is
    // exactly that kind of state, same category as FlGroup.current_.
    Window.defaultXclass_ = null;
    scope (exit) Window.defaultXclass_ = null;

    FlGroup.current(null);
    auto w1 = new Window(100, 100, "w1");
    assert(w1.xclass() == "fldtk"); // untouched: falls back to the hardcoded default

    w1.xclass("myapp");
    assert(w1.xclass() == "myapp");
    assert(Window.defaultXclass() == "myapp"); // first-ever set also becomes the default

    // A second window that never sets its own xclass() picks up the
    // now-customized default, not "fldtk" -- matches FLTK's own
    // "affects windows created after this call" semantics.
    auto w2 = new Window(100, 100, "w2");
    assert(w2.xclass() == "myapp");

    // Explicitly setting a second window's own xclass() does NOT
    // reassign the already-set default (FLTK: "unless it has been
    // set before").
    w2.xclass("other");
    assert(w2.xclass() == "other");
    assert(Window.defaultXclass() == "myapp");

    Window.defaultXclass("reset");
    assert(Window.defaultXclass() == "reset");
    Window.defaultXclass(null);
    assert(Window.defaultXclass() == "fldtk"); // null resets to the hardcoded default

    FlGroup.current(null);
}

unittest
{
    // show(string[] args)'s argv[0]-derived title/xclass fallback: the
    // pure derivation logic, without actually calling the real show()
    // (needs a live display, see this module's own established
    // convention) -- confirms the exact same condition show(args)
    // itself uses, since that method isn't itself callable headless.
    import fl.filename : filenameName;

    Window.defaultXclass_ = null;
    scope (exit) Window.defaultXclass_ = null;
    FlGroup.current(null);

    // No explicit label, no explicit xclass: both derive from argv[0]'s
    // basename, matching a real FLTK program's default window title.
    auto w1 = new Window(100, 100);
    assert(w1.label().length == 0);
    string derived = filenameName("/usr/local/bin/callbacks");
    assert(derived == "callbacks");
    if (w1.xclass().length == 0 || w1.xclass() == "fldtk")
        w1.xclass(derived);
    if (w1.label().length == 0)
        w1.label(w1.xclass());
    assert(w1.xclass() == "callbacks");
    assert(w1.label() == "callbacks");

    // An explicit label is never overwritten. Reset the process-wide
    // default first -- w1 already claimed it as "callbacks" above
    // (the first-ever xclass() set becomes sticky for every later
    // window that doesn't set its own, confirmed in the previous
    // unittest), which would otherwise leak into this scenario.
    Window.defaultXclass_ = null;
    auto w2 = new Window(100, 100, "Custom Title");
    if (w2.xclass().length == 0 || w2.xclass() == "fldtk")
        w2.xclass(filenameName("/usr/local/bin/othertool"));
    if (w2.label().length == 0)
        w2.label(w2.xclass());
    assert(w2.label() == "Custom Title"); // untouched
    assert(w2.xclass() == "othertool"); // xclass still derives independently

    FlGroup.current(null);
}
