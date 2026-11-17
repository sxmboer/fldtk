/*
 * MarkdownDialog: a window for reading Markdown documents, such as a
 * program's README or its help pages.
 *
 * A toolbar (Back and Forward, smaller and larger text, a find field)
 * over a `fl.markdown_view.MarkdownView`. Clicking a link to another
 * `.md` file opens it in the same window; Back and Forward go through
 * the pages visited, each at the scroll position it was left at. The
 * window's title is the page's title (`MarkdownView.title()`).
 *
 * Besides the toolbar's buttons: Alt+Left and Alt+Right, or the mouse's
 * back and forward side buttons, go back and forward; Ctrl with the
 * mouse wheel makes the text larger or smaller (`fl.browser_window`).
 *
 * ---
 * auto d = new MarkdownDialog();
 * d.load("README.md");
 * d.show();
 * ---
 */
module fl.markdown_dialog;

import fl.browser_window : BrowserWindow;
import fl.group : FlGroup;
import fl.button : Button;
import fl.input : Input;
import fl.box : Box;
import fl.markdown_view : MarkdownView;
import fl.enumerations;
import fl.core;

class MarkdownDialog
{
    private struct Page
    {
        string file;
        int line;
    }

    private Page[] history_;     // history_[index_] is the page on show
    private int index_ = -1;
    private int findPos_;

    private BrowserWindow window_;
    private Button back_, forward_, smaller_, larger_;
    private Input find_;
    private MarkdownView view_;

    /// The smallest and largest text size the toolbar's buttons set.
    enum Fontsize minTextSize = 8, maxTextSize = 32;

    this()
    {
        auto prevCurrent = FlGroup.current();
        FlGroup.current(null);

        window_ = new BrowserWindow(760, 600, "Markdown");
        window_.onHistory = (step) { go(step); };
        window_.onZoom = (step) { textsize(cast(Fontsize)(view_.textsize() + 2 * step)); };

        auto toolbar = new FlGroup(10, 10, 740, 25);

        back_ = new Button(10, 10, 25, 25, "@<-");
        back_.tooltip("Show the previous page (Alt+Left, or the mouse's back button).");
        back_.shortcut(stateAlt | left);
        back_.labelcolor(cast(Color) 2);
        back_.callback((w) { go(-1); });

        forward_ = new Button(45, 10, 25, 25, "@->");
        forward_.tooltip("Show the next page (Alt+Right, or the mouse's forward button).");
        forward_.shortcut(stateAlt | right);
        forward_.labelcolor(cast(Color) 2);
        forward_.callback((w) { go(1); });

        smaller_ = new Button(80, 10, 25, 25, "F");
        smaller_.tooltip("Make the text smaller (Ctrl+wheel down).");
        smaller_.labelfont(helveticaBold);
        smaller_.labelsize(10);
        smaller_.callback((w) { textsize(cast(Fontsize)(view_.textsize() - 2)); });

        larger_ = new Button(115, 10, 25, 25, "F");
        larger_.tooltip("Make the text larger (Ctrl+wheel up).");
        larger_.labelfont(helveticaBold);
        larger_.labelsize(16);
        larger_.callback((w) { textsize(cast(Fontsize)(view_.textsize() + 2)); });

        auto findGroup = new FlGroup(579, 10, 171, 25);
        findGroup.box(Boxtype.downBox);
        findGroup.color(background2Color);
        find_ = new Input(604, 12, 143, 21, "@search");
        find_.tooltip("Find text in the page. Enter finds the next match.");
        find_.box(Boxtype.flatBox);
        find_.labelsize(13);
        find_.callback((w) { findNext(); });
        find_.when(whenEnterKeyAlways);
        findGroup.end();

        auto spacer = new Box(150, 10, 420, 25);
        toolbar.resizable(spacer);
        toolbar.end();

        view_ = new MarkdownView(10, 45, 740, 545);
        view_.callback((w) { viewChanged(); });
        window_.resizable(view_);

        window_.sizeRange(260, 150);
        window_.end();

        back_.deactivate();
        forward_.deactivate();

        FlGroup.current(prevCurrent);
    }

    /// Shows the Markdown file `f` (see `MarkdownView.load()`), as a new
    /// page in the history. Returns 0, or -1 if it can't be read.
    int load(string f)
    {
        view_.setChanged();
        int ret = view_.load(f);
        window_.label(view_.title());
        return ret;
    }

    /// Shows the Markdown text `md`. Text not from a file has no place
    /// in the history: Back and Forward are switched off.
    void value(string md)
    {
        view_.setChanged();
        view_.value(md);
        window_.label(view_.title());
    }

    /// The Markdown text on show.
    string value() const => view_.value();

    /// The text size (see `MarkdownView.textsize()`), kept between
    /// `minTextSize` and `maxTextSize`.
    Fontsize textsize() => view_.textsize();

    /// ditto
    void textsize(Fontsize s)
    {
        if (s < minTextSize) s = minTextSize;
        if (s > maxTextSize) s = maxTextSize;
        view_.textsize(s);
        if (s <= minTextSize) smaller_.deactivate(); else smaller_.activate();
        if (s >= maxTextSize) larger_.deactivate(); else larger_.activate();
    }

    /// The view, for settings this dialog doesn't forward.
    MarkdownView view() => view_;

    void show() => window_.show();       /// The window's own.
    void hide() => window_.hide();       /// ditto
    bool shown() => window_.shown();     /// ditto
    bool visible() => window_.visible(); /// ditto
    void resize(int x, int y, int w, int h) => window_.resize(x, y, w, h); /// ditto
    void position(int x, int y) => window_.position(x, y); /// ditto
    int x() => window_.x(); /// ditto
    int y() => window_.y(); /// ditto
    int w() => window_.w(); /// ditto
    int h() => window_.h(); /// ditto

    // Back (-1) or Forward (1) through the history.
    private void go(int step)
    {
        int i = index_ + step;
        if (i < 0 || i >= cast(int) history_.length) return;
        index_ = i;
        auto p = history_[index_];
        if (view_.filename() != p.file) view_.load(p.file);
        view_.topline(p.line);
        window_.label(view_.title());
        updateButtons();
    }

    private void updateButtons()
    {
        if (index_ > 0) back_.activate(); else back_.deactivate();
        if (index_ >= 0 && index_ < cast(int) history_.length - 1) forward_.activate();
        else forward_.deactivate();
    }

    private void findNext()
    {
        int at = view_.find(find_.value(), findPos_);
        findPos_ = at >= 0 ? at + 1 : 0;
    }

    // The view calls back whenever its scroll position is set, with
    // changed() set when a new page was loaded: a new page starts a new
    // history entry (dropping the pages ahead of it); a scroll updates
    // the entry's position.
    private void viewChanged()
    {
        if (view_.filename() is null)
        {
            history_ = null;
            index_ = -1;
            updateButtons();
            return;
        }
        if (view_.changed() || index_ < 0)
        {
            findPos_ = 0;
            index_++;
            if (index_ < cast(int) history_.length) history_ = history_[0 .. index_];
            history_ ~= Page(view_.filename(), view_.topline());
            window_.label(view_.title());
            updateButtons();
        }
        else
            history_[index_] = Page(view_.filename(), view_.topline());
    }
}

unittest
{
    import std.file : write, remove, tempDir;
    import std.path : buildPath;

    FlGroup.current(null);
    scope (exit) FlGroup.current(null);

    auto a = buildPath(tempDir(), "fldtk-markdown-dialog-a.md");
    auto b = buildPath(tempDir(), "fldtk-markdown-dialog-b.md");
    write(a, "# Page A\n\nGo to [B](fldtk-markdown-dialog-b.md).\n");
    write(b, "# Page B\n");
    scope (exit) { remove(a); remove(b); }

    auto d = new MarkdownDialog();
    assert(d.load(a) == 0);
    assert(d.view().title() == "Page A");
    assert(!d.back_.active());
    assert(d.load(b) == 0);
    assert(d.back_.active() && !d.forward_.active());
    d.go(-1);
    assert(d.view().title() == "Page A");
    assert(!d.back_.active() && d.forward_.active());
    d.go(1);
    assert(d.view().title() == "Page B");

    d.textsize(100);
    assert(d.textsize() == MarkdownDialog.maxTextSize && !d.larger_.active());
}
