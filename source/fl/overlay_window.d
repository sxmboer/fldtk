/*
 * Ported from FL/Fl_Overlay_Window.H + src/Fl_Overlay_Window.cxx (FLTK
 * 1.5.0), plus the driver-agnostic core of
 * src/Fl_Window_Driver.cxx's own can_do_overlay()/redraw_overlay() and
 * src/drivers/X11/Fl_X11_Window_Driver.cxx's flush_overlay(). FLTK
 * splits the real logic across Fl_Window_Driver rather than keeping it
 * in Fl_Overlay_Window itself; this port folds it back into a single
 * place, fl.platform_x11.flushDamage()'s overlay branch, matching how
 * fl.double_window's own real double-buffering already lives in that
 * same function rather than a separate virtual flush() hook (neither
 * Window nor DoubleWindow has one either).
 *
 * FLTK's own class doc comment: "Fl_Overlay_Window uses the
 * overlay planes provided by your graphics hardware if they are
 * available. If no hardware support is found the overlay is simulated
 * by drawing directly into the on-screen copy of the double-buffered
 * window, and 'erased' by copying the backbuffer over it again. This
 * means the overlay will blink if you change the image in the
 * window." This port never implements the hardware-overlay-plane
 * path -- neither does FLTK's own X11 driver: `canDoOverlay()`
 * always returns `false`, matching `Fl_Window_Driver::can_do_overlay()`'s
 * own unconditional `return 0;` with no X11-specific override anywhere
 * in `Fl_X11_Window_Driver.cxx` (only the WinAPI/Cocoa Gl_Window
 * drivers have a real one, for OpenGL's own separate overlay-plane
 * extension -- unrelated to this class, and blocked on GL like the
 * rest of `fl.gl_window` per CONVENTIONS.md). So the software-simulated
 * path is the *only* path here, same as real FLTK on X11.
 *
 * `type()` is deliberately NOT overridden to a distinct tag, matching
 * FLTK exactly: `Fl_Overlay_Window`'s own constructor never calls
 * `type()`, so it keeps `Fl_Double_Window`'s `FL_DOUBLE_WINDOW` value
 * -- FLTK distinguishes the two via C++ virtual dispatch
 * (`Fl_Overlay_Window::flush()` overrides `Fl_Double_Window`'s), this
 * port distinguishes them via a runtime `cast(OverlayWindow)` check in
 * `fl.platform_x11.flushDamage()` instead, achieving the same effect
 * without a second type tag.
 *
 * Not ported: `show()`/`hide()`/`resize()`'s own overrides (FLTK:
 * `if (overlay_ && overlay_ != this) overlay_->show();` and similar) --
 * these exist purely to cascade to a *separate* hardware-overlay
 * window object, which never exists in this port (`overlay_` here is
 * always either `null` or `this`, never a distinct window -- see
 * `canDoOverlay()` above), so the condition they guard is permanently
 * false by construction, not just unreached-for-now. Same reasoning as
 * `fl.double_window`'s own skipped Cairo-specific bookkeeping: dead
 * code for a code path this port's architecture never takes. The
 * destructor (`~Fl_Overlay_Window() { hide(); }`) is skipped too,
 * matching every other `Window` subclass in this port (none define an
 * explicit destructor -- see CONVENTIONS.md's GC-finalizer-hazard note).
 */
module fl.overlay_window;

import fl.double_window : DoubleWindow;
import fl.enumerations : damageOverlay;

abstract class OverlayWindow : DoubleWindow
{
    /// Matches FLTK's private `Fl_Window *overlay_` field --
    /// `null` until the first `redrawOverlay()` call, `this` from then
    /// on (never anything else, since `canDoOverlay()` is always
    /// `false` here -- see the module doc comment). Read by
    /// `fl.platform_x11.flushDamage()` via `overlayActive()` below.
    package(fl) OverlayWindow overlay_;

    this(int w, int h, string label = null)
    {
        super(w, h, label);
    }

    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
    }

    /**
     * You must override this method. It is just like `draw()`, except
     * it draws the overlay. The overlay will already have been
     * "cleared" when this is called (see `fl.platform_x11.
     * flushDamage()`'s overlay branch for exactly when/how -- the
     * on-screen buffer is freshly recopied from the clean backbuffer
     * immediately before this runs). You can use any of the drawing
     * routines in `fl.draw`.
     */
    abstract void drawOverlay();

    /// Returns non-zero if there's hardware overlay support. Always
    /// `false` in this port -- see the module doc comment.
    bool canDoOverlay() { return false; }

    /// Backs `fl.platform_x11.flushDamage()`'s overlay branch --
    /// `overlay_ !is null` once `redrawOverlay()` has been called at
    /// least once (never subsequently cleared, matching FLTK: the
    /// overlay stays "on" for the window's whole lifetime once used).
    package(fl) bool overlayActive() const { return overlay_ !is null; }

    /**
     * Call this to indicate that the overlay data has changed and
     * needs to be redrawn. The overlay will be clear until the first
     * time this is called, so if you want an initial display you must
     * call this after calling `show()`. Ported from `Fl_Window_Driver::
     * redraw_overlay()` (the base, no-hardware-overlay implementation
     * -- the only one this port ever exercises, see the module doc
     * comment).
     *
     * Calls the real, invalidating `damage()` setter directly, not
     * `clearDamage()`: FLTK's `pWindow->clear_damage(...)` relies on
     * a second, separate statement right after,
     * `Fl::damage(FL_DAMAGE_CHILD);` -- a global "something, somewhere
     * needs a flush soon" flag every platform's own `wait()` checks each
     * iteration -- to actually guarantee a repaint gets scheduled. This
     * port has no equivalent global flag, so without a real invalidate
     * here, the overlay would only ever get drawn as an incidental side
     * effect of some *other* widget in the same window separately
     * triggering a real, invalidating redraw of its own. Calling the
     * real, invalidating `damage()` setter directly is a more targeted
     * fit for this port's architecture than reintroducing a global flag,
     * and behaviorally exactly what's needed: force a real repaint of
     * *this* window specifically. Matches
     * `fl.gl_window.GlWindow.redrawOverlay()`'s identical approach to
     * the same underlying gap (that class's own FLTK driver methods
     * use a real invalidating `damage()` call directly, with no
     * dropped-global-flag complication at all -- see that method's own
     * doc comment).
     */
    void redrawOverlay()
    {
        overlay_ = this;
        damage(damageOverlay);
    }
}

unittest
{
    import fl.group : FlGroup;

    FlGroup.current(null);

    static class TestOverlay : OverlayWindow
    {
        int overlayDraws;
        this(int w, int h) { super(w, h); }
        override void drawOverlay() { overlayDraws++; }
    }

    auto w = new TestOverlay(200, 150);
    assert(!w.canDoOverlay());
    assert(!w.overlayActive());

    w.clearDamage();
    w.redrawOverlay();
    assert(w.overlayActive());
    assert((w.damage() & damageOverlay) != 0);

    FlGroup.current(null);
}
