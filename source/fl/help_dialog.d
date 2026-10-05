/*
 * Ported from FL/Fl_Help_Dialog.H + src/Fl_Help_Dialog.cxx (FLTK
 * 1.5.0). Milestone 3 of the fl.help_view port
 * (see PORTING.md's row for that module).
 *
 * A small, self-contained help browser window: a toolbar (Back/
 * Forward buttons, smaller/larger text-size buttons, a find field)
 * over an embedded `HelpView`, plus growable navigation history.
 * Fluid-generated FLTK (`Fl_Help_Dialog.fl`) -- ported by hand
 * from the generated `.H`/`.cxx` output, same as every other
 * fluid-generated dialog in this port (`fl.file_chooser`).
 *
 * Deliberate deviations:
 *
 *  - **No `cb_xxx_i`/`cb_xxx` static-trampoline pairs.** Every widget
 *    FLTK gets a `static void cb_xxx(Fl_Widget*, void*)`
 *    trampoline that recovers `this` via
 *    `o->parent()->...->user_data()` and forwards to a real `cb_xxx_i`
 *    instance method -- needed only because `Fl_Callback` is a plain
 *    C function pointer. A D delegate already closes over `this`
 *    directly, so each pair collapses into one closure, matching
 *    `fl.file_chooser`'s identical simplification and CONVENTIONS.md's
 *    "Callbacks are D delegates" convention. Not a behavior change --
 *    it's exactly the boilerplate the delegate substitution exists to
 *    eliminate.
 *
 *  - **`HelpDialog` is not a `Widget`**, matching FLTK
 *    (`Fl_Help_Dialog` is a plain class owning a real `DoubleWindow`,
 *    not itself a widget) -- same shape as `fl.file_chooser.FileChooser`.
 *
 *  - **Growable navigation history, not fixed 100-slot arrays.**
 *    FLTK's `int line_[100]`/`char file_[100][FL_PATH_MAX]` are
 *    flagged in its own source as `// FIXME: we must remove those
 *    static numbers` -- past 100 visited pages it silently evicts the
 *    oldest 10 via `memmove()` (`index_ -= 10`). This port replaces
 *    both arrays with one growable `HistoryEntry[] history_`
 *    (`struct HistoryEntry { string file; int line; }`), matching
 *    this project's established precedent for dissolving a C array's
 *    fixed cap into a growable D array (e.g. `fl.preferences`'s
 *    child-node arrays, `fl.help_view`'s own `formatTable()` column
 *    arrays) -- no eviction, no cap, and since FLTK flags the cap
 *    as a bug it wants gone rather than a deliberate design choice,
 *    this isn't a "port faithfully, deviations must be justified"
 *    judgment call the way most deviations in this project are; it's
 *    doing what FLTK's own comment already asked for.
 *
 *  - **`fl_register_images()` is called**, matching FLTK's own
 *    constructor: it registers `fl.shared_image.registerImages()`'s
 *    real, native format detectors (XBM/XPM/PNM/BMP/ICO/GIF/SVG/PNG/
 *    JPEG, see that function's own doc comment in `fl.shared_image.d`)
 *    so `<IMG>` tags load real image data via `SharedImage`.
 *
 *  - **`show(int argc, char **argv)` is not ported** -- FLTK's
 *    X11-command-line-flag-parsing overload of `Fl_Window::show()`
 *    (`-display`/`-geometry`/etc.) has no equivalent anywhere in this
 *    port's window-creation path; `fl.window`/`fl.platform_x11` don't
 *    have an argv-parsing entry point to forward to.
 *
 *  - **Found a likely FLTK bug while porting `cb_forward_`,
 *    ported faithfully (not fixed) -- see `FLTK_ISSUES.md`**:
 *    `cb_back__i` sets the target page's scroll position from
 *    `line_[index_]` (the *recorded* topline for the history entry
 *    being navigated to), but `cb_forward__i` instead captures
 *    `view_->topline()` -- the *current* page's scroll position,
 *    read *before* the target page is loaded -- and applies that
 *    stale value to the new page instead. `forwardCB()` below
 *    reproduces this exact asymmetry (`currentTopline`, captured
 *    before `view_.load()`, not `history_[index_].line`).
 */
module fl.help_dialog;

import fl.double_window : DoubleWindow;
import fl.group : FlGroup;
import fl.button : Button;
import fl.input : Input;
import fl.box : Box;
import fl.help_view : HelpView;
import fl.shared_image : registerImages;
import fl.enumerations;
import fl.core;

class HelpDialog
{
    private struct HistoryEntry
    {
        string file;
        int line;
    }

    // Growable replacement for FLTK's index_/max_/line_[100]/
    // file_[100][FL_PATH_MAX] -- see the module comment. `index_`
    // is -1 until the first page is ever recorded (matching
    // FLTK's own initial value); `history_[index_]` is always the
    // page currently on screen once `index_ >= 0`.
    private HistoryEntry[] history_;
    private int index_ = -1;
    private int findPos_;

    private DoubleWindow window_;
    private Button back_, forward_, smaller_, larger_;
    private Input find_;
    private HelpView view_;

    this()
    {
        auto prevCurrent = FlGroup.current();
        FlGroup.current(null);

        window_ = new DoubleWindow(530, 385, "Help Dialog");

        auto toolbar = new FlGroup(10, 10, 511, 25);

        back_ = new Button(10, 10, 25, 25, "@<-");
        back_.tooltip("Show the previous help page.");
        back_.shortcut(left);
        back_.labelcolor(cast(Color) 2);
        back_.callback((w) { backCB(); });

        forward_ = new Button(45, 10, 25, 25, "@->");
        forward_.tooltip("Show the next help page.");
        forward_.shortcut(right);
        forward_.labelcolor(cast(Color) 2);
        forward_.callback((w) { forwardCB(); });

        smaller_ = new Button(80, 10, 25, 25, "F");
        smaller_.tooltip("Make the help text smaller.");
        smaller_.labelfont(helveticaBold);
        smaller_.labelsize(10);
        smaller_.callback((w) { smallerCB(); });

        larger_ = new Button(115, 10, 25, 25, "F");
        larger_.tooltip("Make the help text larger.");
        larger_.labelfont(helveticaBold);
        larger_.labelsize(16);
        larger_.callback((w) { largerCB(); });

        auto findGroup = new FlGroup(350, 10, 171, 25);
        findGroup.box(Boxtype.downBox);
        findGroup.color(background2Color);

        find_ = new Input(375, 12, 143, 21, "@search");
        find_.tooltip("find text in document");
        find_.box(Boxtype.flatBox);
        find_.labelsize(13);
        find_.textfont(courier);
        find_.callback((w) { findCB(); });
        find_.when(whenEnterKeyAlways);
        findGroup.end();

        auto spacer = new Box(150, 10, 190, 25);
        toolbar.resizable(spacer);
        toolbar.end();

        view_ = new HelpView(10, 45, 510, 330);
        view_.box(Boxtype.downBox);
        view_.callback((w) { viewCB(); });
        FlGroup.current().resizable(view_);

        window_.sizeRange(260, 150);
        window_.end();

        back_.deactivate();
        forward_.deactivate();

        // Ported from `Fl_Help_Dialog::Fl_Help_Dialog()`'s own trailing
        // `fl_register_images();` call -- registers GIF/BMP/ICO/SVG
        // detection with `SharedImage` so this dialog's `<IMG>` tags can
        // actually load (see `registerImages()`'s own doc comment in
        // `fl.shared_image.d`). A no-op on a second/third HelpDialog in
        // the same process (`addHandler()`'s own dedup).
        registerImages();

        FlGroup.current(prevCurrent);
    }

    // ------------------------------------------------------------
    // Callbacks
    // ------------------------------------------------------------

    /// Ported from `cb_back__i()`.
    private void backCB()
    {
        if (index_ > 0)
            index_--;

        if (index_ == 0)
            back_.deactivate();

        forward_.activate();

        int l = history_[index_].line;

        if (view_.filename() != history_[index_].file)
            view_.load(history_[index_].file);

        view_.topline(l);
    }

    /// Ported from `cb_forward__i()` -- see the module comment for the
    /// `currentTopline`-vs-`history_[index_].line` asymmetry against
    /// `backCB()`, faithfully reproduced from FLTK.
    private void forwardCB()
    {
        if (index_ < cast(int) history_.length - 1)
            index_++;

        if (index_ >= cast(int) history_.length - 1)
            forward_.deactivate();

        back_.activate();

        int currentTopline = view_.topline();

        if (view_.filename() != history_[index_].file)
            view_.load(history_[index_].file);

        view_.topline(currentTopline);
    }

    /// Ported from `cb_smaller__i()`.
    private void smallerCB()
    {
        if (view_.textsize() > 8)
            view_.textsize(cast(Fontsize)(view_.textsize() - 2));

        if (view_.textsize() <= 8)
            smaller_.deactivate();
        larger_.activate();
    }

    /// Ported from `cb_larger__i()`.
    private void largerCB()
    {
        if (view_.textsize() < 18)
            view_.textsize(cast(Fontsize)(view_.textsize() + 2));

        if (view_.textsize() >= 18)
            larger_.deactivate();
        smaller_.activate();
    }

    /// Ported from `cb_find__i()`.
    private void findCB()
    {
        findPos_ = view_.find(find_.value(), findPos_);
    }

    /**
     * Ported from `cb_view__i()` -- the navigation-history tracker,
     * wired to `HelpView.callback()`. Fires on every `topline()` call
     * (see `fl.help_view.d`'s own `topline()`, which unconditionally
     * calls `doCallback(CallbackReason.dragged)` -- a real, FLTK-
     * confirmed mechanism: `Fl_Help_View::Impl::topline()` does the
     * same, so *every* navigation (`value()`/`load()`/an anchor jump)
     * ends up here, not just mouse drags, despite the reason's name).
     * `changed()` distinguishes "a genuinely new page was just loaded"
     * (set by `value()`/`load()`/`followLink()`, cleared by
     * `doCallback()` right after this callback returns) from "the
     * scroll position moved within the page already on screen" (e.g.
     * a `resize()`-triggered reformat).
     */
    private void viewCB()
    {
        if (view_.filename() !is null)
        {
            if (view_.changed())
            {
                index_++;

                // A genuinely new page truncates any "forward" history
                // past this point (matching FLTK's `max_ = index_`)
                // before appending -- growable array, no 100-slot cap
                // or eviction, see the module comment.
                if (index_ < cast(int) history_.length)
                    history_ = history_[0 .. index_];
                history_ ~= HistoryEntry(view_.filename(), view_.topline());

                if (index_ > 0)
                    back_.activate();
                else
                    back_.deactivate();

                forward_.deactivate();
                window_.label(view_.title());
            }
            else
            {
                history_[index_] = HistoryEntry(view_.filename(), view_.topline());
            }
        }
        else
        {
            // An unnamed internal page (value() called directly, not
            // via load()) -- hitting one disables the back/forward
            // history, matching FLTK exactly.
            index_ = 0;
            history_ = [HistoryEntry("", view_.topline())];
            back_.deactivate();
            forward_.deactivate();
        }
    }

    // ------------------------------------------------------------
    // Public API -- thin forwarders, matching FLTK 1:1.
    // ------------------------------------------------------------

    int h() => window_.h();

    void hide() => window_.hide();

    /// Ported from `Fl_Help_Dialog::load()`. Unlike `HelpView.load()`
    /// itself, this explicitly marks the view changed *before*
    /// loading -- `Fl_Help_View::load()` doesn't call `setChanged()`
    /// on its own (only `value()` does), so callers that want the
    /// navigation-history tracker in `viewCB()` to treat this as a
    /// real new page must set it themselves, matching FLTK.
    int load(string f)
    {
        view_.setChanged();
        int ret = view_.load(f);
        window_.label(view_.title());
        return ret;
    }

    void position(int xx, int yy) => window_.position(xx, yy);

    void resize(int xx, int yy, int ww, int hh) => window_.resize(xx, yy, ww, hh);

    void show() => window_.show();

    void textsize(Fontsize s)
    {
        view_.textsize(s);

        if (s <= 8)
            smaller_.deactivate();
        else
            smaller_.activate();

        if (s >= 18)
            larger_.deactivate();
        else
            larger_.activate();
    }

    Fontsize textsize() => view_.textsize();

    void topline(string n) => view_.topline(n);
    void topline(int n) => view_.topline(n); /// ditto

    void value(string f)
    {
        view_.setChanged();
        view_.value(f);
        window_.label(view_.title());
    }

    string value() const => view_.value();

    bool visible() => window_.visible();

    int w() => window_.w();
    int x() => window_.x();
    int y() => window_.y();
}

unittest
{
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto d = new HelpDialog();

    assert(d.w() == 530);
    assert(d.h() == 385);
    // visible() forwards to Widget.visible() (the "not explicitly
    // hidden" flag, true by default even before show() maps the
    // window on screen -- matches FLTK's own Fl_Widget-inherited
    // semantics exactly); use the window's shown() for "actually
    // mapped", which HelpDialog doesn't expose separately, matching
    // FLTK (Fl_Help_Dialog has no shown() forwarder either).
    assert(d.visible());
    assert(d.textsize() == 12); // HelpView's own default

    FlGroup.current(null);
}

unittest
{
    // value(): pushes a new "unnamed internal page" history entry
    // (no filename), disables back/forward.
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto d = new HelpDialog();
    d.value("<HTML><HEAD><TITLE>Hello</TITLE></HEAD><BODY>Hi</BODY></HTML>");

    assert(d.value().length > 0);

    FlGroup.current(null);
}

unittest
{
    // load(): real file navigation builds real back/forward history
    // via a real temp file on disk, including the growable-array
    // truncate-on-new-page behavior this module deliberately replaces
    // FLTK's fixed 100-slot arrays with.
    import fl.group : FlGroup;
    import std.file : write, remove, tempDir;
    import std.path : buildPath;

    FlGroup.current(null);

    auto pathA = buildPath(tempDir(), "fldtk-help-dialog-test-a.html");
    auto pathB = buildPath(tempDir(), "fldtk-help-dialog-test-b.html");
    write(pathA, "<HTML><HEAD><TITLE>A</TITLE></HEAD><BODY>Page A</BODY></HTML>");
    write(pathB, "<HTML><HEAD><TITLE>B</TITLE></HEAD><BODY>Page B</BODY></HTML>");
    scope (exit)
    {
        remove(pathA);
        remove(pathB);
    }

    auto d = new HelpDialog();

    assert(d.load(pathA) == 0);
    assert(d.load(pathB) == 0);

    FlGroup.current(null);
}
