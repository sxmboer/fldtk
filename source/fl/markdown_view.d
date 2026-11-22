/*
 * MarkdownView: a widget that shows a Markdown document, formatted.
 *
 * The text is parsed once into a document tree (`fl.markdown`), which
 * is laid out for the widget's width into positioned pieces: text runs
 * in their font and colour, filled rectangles (code backgrounds, table
 * cells, rules, the bar of a quote), and images. `draw()` paints the
 * pieces in view; the layout is redone when the width or the text size
 * changes.
 *
 * What it shows: headings (an anchor for each, see
 * `fl.markdown.headingSlug()`), paragraphs with bold, italic,
 * strikethrough and code, code blocks (not wrapped, scrolled
 * sideways; a block marked as D, ```` ```D ````, coloured as in Fluid's
 * code editors, see `fl.d_syntax`), block quotes, bullet and numbered lists, tables with
 * column alignment and wrapped cells, rules, links and images.
 *
 * Links: a click on a link to `#anchor` scrolls to that heading; a
 * link to another `.md` file loads it (with its `#anchor`, if any); a
 * link with a scheme (`https:`, `mailto:`, ...) or to another kind of
 * file goes to `fl.filename.openUri()`, which hands it to the program
 * the system uses for it. `link()` sets a function that sees each link
 * first. Hovering over a link shows its address in a tooltip.
 *
 * Images are read from files, relative to the document's folder.
 * MarkdownView does not download: for an image given by URL it looks
 * for the same file under the document's folder (the URL's path, or
 * its tail end, such as `docs/button.png` for
 * `https://host/user/project/branch/docs/button.png`), and shows the
 * image's description when there is none. An image wider than the
 * view is scaled down to fit.
 *
 * Text can be selected with the mouse (a double click selects a word)
 * and copied with Ctrl+C or the right-click menu; `find()` searches it.
 * The keyboard scrolls with the arrow keys, Page Up/Down, Home and End.
 *
 * Callbacks: like `fl.html_view.HtmlView`, the widget calls its
 * callback (`CallbackReason.dragged`) whenever its scroll position is
 * set, with `changed()` true when a new document was loaded, so a
 * dialog can keep a history (`fl.markdown_dialog.MarkdownDialog`).
 */
module fl.markdown_view;

import fl.group : FlGroup;
import fl.widget : Widget;
import fl.scrollbar : Scrollbar;
import fl.slider : horSlider;
static import fl.enumerations;
import fl.enumerations : Color, Font, Fontsize, Event, CallbackReason, Boxtype, Cursor,
    foregroundColor, background2Color, selectionColor, normalSize,
    helvetica, courier, courierBold, rightMouse, stateMeta, stateAlt, stateShift, stateCtrl,
    stateCommand;
import fl.draw;
import fl.core;
import fl.image : Image;
import fl.shared_image : SharedImage;
import fl.filename : openUri;
import fl.menu_item : MenuItem;
import fl.menu_popup;
import fl.markdown;
import fl.d_syntax : styleParse, styleTable, stylePlain;
import fl.text_display : StyleTableEntry;

/// A function that sees every link the user clicks in a `MarkdownView`
/// before the view follows it. Returns true when it handled the link
/// itself, false to let the view follow it.
alias MarkdownLinkFunc = bool delegate(MarkdownView view, string url);

class MarkdownView : FlGroup
{
    /// No widgets: the parts a MarkdownView is made of
    /// (its scrollbars) are not listed (see `FlGroup.widgets`).
    override Widget[] widgets() { return null; }

    // FlGroup.find(Widget) is hidden by find(string, int) below.
    alias find = FlGroup.find;

    /// The text of the right-click menu's one entry.
    static string copyMenuText = "Copy";

    private
    {
        // A piece of text on one line, in one font and colour. `pos` is
        // where its text starts in `plain_`.
        struct Run
        {
            int x, y;          // y is the baseline
            int w, asc, desc;
            Font font;
            Fontsize size;
            Color color;
            string text;
            size_t pos;
            int link = -1;
            bool strike;
        }

        struct Fill
        {
            int x, y, w, h;
            Color color;
            bool frame;        // an outline instead of a filled rectangle
        }

        struct Pic
        {
            int x, y, w, h;
            Image img;
            int link = -1;
        }

        // A word, a space, a line break or an image, waiting to be put
        // on a line by layoutLines().
        struct Piece
        {
            enum Kind { word, space, lineBreak, image }
            Kind kind;
            string text;
            Style st;
            Image img;
            int w, h;
        }

        struct Style
        {
            bool bold, italic, code, strike;
            int link = -1;
            Fontsize size;
            Color color;
        }

        string value_;
        MdBlock doc_;
        string filename_, directory_, title_;

        Fontsize textsize_;            // normalSize, set by the constructor
        Font textfont_ = helvetica;
        Color textcolor_ = foregroundColor;
        Color linkcolor_ = 0;          // 0 until first used: see linkcolor()

        Scrollbar scrollbar_, hscrollbar_;
        int scrollbarSize_;
        int topline_, leftline_;
        int size_, hsize_;             // the laid-out document's height and width
        int layoutWidth_ = -1;

        Run[] runs_;
        Fill[] fills_;
        Pic[] pics_;
        string[] linkUrls_;
        int[string] anchors_;
        LineMark[] lineMarks_;         // where blocks start and end, by source line
        char[] plain_;                 // the document's text, as copy() gives it

        size_t selFirst_, selLast_, selAnchor_;
        bool selecting_;
        int pressLink_ = -1;
        MarkdownLinkFunc linkFunc_;

        SharedImage[string] images_;   // held for the document's lifetime
        Image[string] scaled_;         // scaled copies, per layout

        // Layout state.
        Color curColor_;
        int availRight_;
    }

    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        textsize_ = normalSize;
        box(Boxtype.downBox);
        color(background2Color, selectionColor);

        auto ss = fl.core.scrollbarSize();
        scrollbar_ = new Scrollbar(x + w - ss, y, ss, h - ss);
        scrollbar_.value(0, h, 0, 1);
        scrollbar_.step(8.0);
        scrollbar_.callback((wd) { topline(cast(int) scrollbar_.value()); });

        hscrollbar_ = new Scrollbar(x, y + h - ss, w - ss, ss);
        hscrollbar_.type(horSlider);
        hscrollbar_.value(0, w, 0, 1);
        hscrollbar_.step(8.0);
        hscrollbar_.callback((wd) { leftline(cast(int) hscrollbar_.value()); });

        end();
        resize(x, y, w, h);
    }

    /// The vertical and horizontal scrollbars.
    Scrollbar scrollbar() => scrollbar_;
    Scrollbar hscrollbar() => hscrollbar_; /// ditto

    // ---- The document ----

    /**
     * Shows the Markdown text `md`. Relative links and images are found
     * from the folder `directory`, or from the current directory when it
     * is null: an editor showing the text it edits passes the file's
     * folder. `load()` finds them from the file's own folder. `null`
     * clears the view.
     */
    void value(string md, string directory = null)
    {
        import std.path : absolutePath, buildNormalizedPath;
        filename_ = null;
        directory_ = directory.length ? buildNormalizedPath(absolutePath(directory)) : null;
        setDocument(md);
        topline(0);
    }

    /// The Markdown text on show.
    string value() const => value_;

    /**
     * Loads and shows the Markdown file `f`, scrolled to the heading
     * `#anchor` at the end of `f` if there is one (`README.md#status`).
     * A `file:` prefix is allowed. Returns 0, or -1 if the file can't
     * be read, in which case the view shows why.
     */
    int load(string f)
    {
        import std.file : readText;
        import std.path : absolutePath, buildNormalizedPath, dirName;
        import std.string : indexOf, startsWith;

        string name = f, anchor;
        auto hash = name.indexOf('#');
        if (hash >= 0)
        {
            anchor = name[hash + 1 .. $];
            name = name[0 .. hash];
        }
        if (name.startsWith("file://")) name = name[7 .. $];
        else if (name.startsWith("file:")) name = name[5 .. $];

        int ret = 0;
        string text;
        if (name.length)
        {
            name = buildNormalizedPath(absolutePath(name));
            try text = readText(name);
            catch (Exception e)
            {
                text = "# Can't show this page\n\n`" ~ name ~ "`: " ~ e.msg ~ "\n";
                ret = -1;
            }
            filename_ = name;
            directory_ = dirName(name);
            setDocument(text);
        }
        if (anchor.length) topline(anchor);
        else topline(0);
        return ret;
    }

    /// The file on show, as an absolute path, or null.
    string filename() const => filename_;

    /// The folder relative links and images are found from, or null for
    /// the current directory.
    string directory() const => directory_;

    /// The document's title: the text of its first heading, or else its
    /// file name.
    string title() const => title_;

    /// Sets a function that sees each link the user clicks first (see
    /// `MarkdownLinkFunc`).
    void link(MarkdownLinkFunc fn) { linkFunc_ = fn; }

    // ---- Text attributes ----

    /// The size of body text; headings and code are sized from it.
    Fontsize textsize() const => textsize_;

    /// ditto
    void textsize(Fontsize s)
    {
        if (s < 4) s = 4;
        if (s == textsize_) return;
        textsize_ = s;
        relayout(true);
    }

    /// The font of body text, with its bold and italic forms used for
    /// emphasis. Code is shown in `courier`.
    Font textfont() const => textfont_;

    /// ditto
    void textfont(Font f)
    {
        textfont_ = f;
        relayout(true);
    }

    /// The colour of body text.
    Color textcolor() const => textcolor_;

    /// ditto
    void textcolor(Color c)
    {
        textcolor_ = c;
        relayout(true);
    }

    /// The scrollbars' width, or 0 for `fl.core.scrollbarSize()`.
    int scrollbarSize() const => scrollbarSize_;

    /// ditto
    void scrollbarSize(int s)
    {
        scrollbarSize_ = s;
        resize(x(), y(), w(), h());
    }

    // ---- Scrolling ----

    /// Scrolls to the heading whose anchor is `anchor` (`fl.markdown.
    /// headingSlug()`), or to the top if there is none.
    void topline(string anchor)
    {
        import std.uni : toLower;
        auto y = toLower(anchor) in anchors_;
        topline(y !is null ? *y : 0);
    }

    /**
     * Scrolls so that what source line `line` of the Markdown text (counting
     * from 0) shows is at the top of the view. An editor showing the text
     * it edits uses it to keep the page at the line at its own top. Within
     * a block that takes several lines (a paragraph, a table), the line's
     * place is estimated from its share of the block's lines.
     */
    void scrollToSourceLine(int line)
    {
        topline(sourceLineY(line));
    }

    /**
     * The source line of the Markdown text (counting from 0) whose part of
     * the page is at the top of the view: the other way round from
     * `scrollToSourceLine()`, for an editor that follows the page.
     */
    int topSourceLine()
    {
        // The last mark at or above the view's top (the later line when
        // two are at the same row) and the first one below it.
        auto lo = LineMark(0, 0, false);
        auto hi = LineMark(doc_ !is null ? doc_.lineCount : 0, size_, false);
        foreach (m; lineMarks_)
        {
            if (m.y <= topline_)
            {
                if (m.y > lo.y || (m.y == lo.y && m.line > lo.line)) lo = m;
            }
            else if (m.y < hi.y || (m.y == hi.y && m.line < hi.line))
                hi = m;
        }
        if (lo.y == topline_ || hi.y <= lo.y || hi.line <= lo.line) return lo.line;
        return lo.line + cast(int)(cast(long)(hi.line - lo.line) * (topline_ - lo.y) / (hi.y - lo.y));
    }

    /// The pixel row of the page where source line `line` shows; see
    /// `scrollToSourceLine()`.
    private int sourceLineY(int line)
    {
        // The last mark at or before the line (a block starting on it wins
        // over one ending there) and the first one after it.
        auto lo = LineMark(0, 0, false);
        auto hi = LineMark(doc_ !is null ? doc_.lineCount : 0, size_, false);
        foreach (m; lineMarks_)
        {
            if (m.line <= line)
            {
                if (m.line > lo.line || (m.line == lo.line && m.start && !lo.start)) lo = m;
            }
            else if (m.line < hi.line)
                hi = m;
        }
        if (lo.line == line || hi.line <= lo.line) return lo.y;
        return lo.y + cast(int)(cast(long)(hi.y - lo.y) * (line - lo.line) / (hi.line - lo.line));
    }

    /// Scrolls so that `top`, in pixels from the start of the document,
    /// is at the top of the view.
    void topline(int top)
    {
        int maxTop = size_ - innerH();
        if (top > maxTop) top = maxTop;
        if (top < 0) top = 0;
        topline_ = top;
        scrollbar_.value(topline_, innerH(), 0, size_);
        doCallback(CallbackReason.dragged);
        redraw();
    }

    /// The scroll position: the document's pixel row at the top of the view.
    int topline() const => topline_;

    /// Scrolls sideways so that column `left` is at the left of the view.
    void leftline(int left)
    {
        int maxLeft = hsize_ - innerW();
        if (left > maxLeft) left = maxLeft;
        if (left < 0) left = 0;
        leftline_ = left;
        hscrollbar_.value(leftline_, innerW(), 0, hsize_);
        redraw();
    }

    /// The sideways scroll position.
    int leftline() const => leftline_;

    /// The laid-out document's height in pixels.
    int size() const => size_;

    // ---- Selection and search ----

    /// Whether text is selected.
    bool textSelected() const => selLast_ > selFirst_;

    /// Unselects the text.
    void clearSelection()
    {
        selFirst_ = selLast_ = 0;
        redraw();
    }

    /// Selects all text.
    void selectAll()
    {
        selFirst_ = 0;
        selLast_ = plain_.length;
        redraw();
    }

    /// The selected text, as `copy()` gives it.
    string selection() const => plain_[selFirst_ .. selLast_].idup;

    /**
     * Puts the selected text on the clipboard (`clipboard` 1) or the
     * selection buffer (0). Returns 1, or 0 if nothing is selected.
     */
    int copy(int clipboard = 1)
    {
        if (!textSelected()) return 0;
        fl.core.copy(selection(), clipboard);
        return 1;
    }

    /**
     * Finds `s` in the document's text, ignoring the case of ASCII
     * letters, starting at text position `p`. Selects the match, scrolls
     * it into view and returns its position, or -1.
     */
    int find(string s, int p = 0)
    {
        if (s.length == 0 || plain_.length == 0) return -1;
        if (p < 0 || p >= cast(int) plain_.length) p = 0;
        foreach (i; cast(size_t) p .. plain_.length)
        {
            if (i + s.length > plain_.length) break;
            bool match = true;
            foreach (k, c; s)
                if (asciiLower(plain_[i + k]) != asciiLower(c)) { match = false; break; }
            if (!match) continue;
            selFirst_ = i;
            selLast_ = i + s.length;
            foreach (ref r; runs_)
                if (r.pos + r.text.length > i)
                {
                    int top = r.y - r.asc;
                    if (top < topline_ || r.y + r.desc > topline_ + innerH())
                        topline(top - innerH() / 3);
                    if (r.x < leftline_ || r.x > leftline_ + innerW())
                        leftline(r.x - textsize_);
                    break;
                }
            redraw();
            return cast(int) i;
        }
        return -1;
    }

    // ---- Widget ----

    override void resize(int x, int y, int w, int h)
    {
        super.resize(x, y, w, h);
        relayout(false);
    }

    override void draw()
    {
        Boxtype b = box() ? box() : Boxtype.downBox;
        drawBox(b, x(), y(), w(), h(), color());

        int ss = sbSize();
        if (scrollbar_.visible()) drawChild(scrollbar_);
        if (hscrollbar_.visible()) drawChild(hscrollbar_);
        if (scrollbar_.visible() && hscrollbar_.visible())
            fl_rectf(scrollbar_.x(), hscrollbar_.y(), ss, ss, fl.enumerations.backgroundColor);

        int ix = x() + boxDx(b), iy = y() + boxDy(b);
        int iw = innerW(), ih = innerH();
        pushClip(ix, iy, iw, ih);
        scope (exit) popClip();

        int ox = ix - leftline_, oy = iy - topline_;
        bool visible(int fy, int fh) { return fy + fh >= topline_ && fy <= topline_ + ih; }

        foreach (ref f; fills_)
            if (!f.frame && visible(f.y, f.h))
                fl_rectf(ox + f.x, oy + f.y, f.w, f.h, f.color);
        foreach (ref f; fills_)
            if (f.frame && visible(f.y, f.h))
            {
                fl_color(f.color);
                fl_rect(ox + f.x, oy + f.y, f.w, f.h);
            }
        foreach (ref p; pics_)
            if (visible(p.y, p.h))
                p.img.draw(ox + p.x, oy + p.y);

        Color selBg = fl.core.focus() is this ? selectionColor() : colorAverage(selectionColor(), color(), 0.5f);
        Color selFg = contrast(textcolor_, selBg);
        foreach (ref r; runs_)
        {
            if (!visible(r.y - r.asc, r.asc + r.desc)) continue;
            fl_font(r.font, r.size);
            int rx = ox + r.x, ry = oy + r.y;
            fl_color(r.color);
            fl_draw(r.text, rx, ry);
            if (r.strike)
                fl_xyline(rx, ry - r.asc / 3, rx + r.w);

            // The selected part, drawn again over a selection background.
            size_t a = selFirst_ > r.pos ? selFirst_ - r.pos : 0;
            size_t e = selLast_ > r.pos ? selLast_ - r.pos : 0;
            if (e > r.text.length) e = r.text.length;
            if (a < e)
            {
                int sx = rx + cast(int) width(r.text[0 .. a]);
                int sw = cast(int) width(r.text[a .. e]);
                fl_rectf(sx, ry - r.asc, sw, r.asc + r.desc, selBg);
                pushClip(sx, ry - r.asc, sw, r.asc + r.desc);
                fl_color(selFg);
                fl_draw(r.text, rx, ry);
                popClip();
            }
        }
    }

    override int handle(Event event)
    {
        import fl.enumerations : kHome = home, kEnd = end, kUp = up, kDown = down,
            kLeft = left, kRight = right, kPageUp = pageUp, kPageDown = pageDown;

        Boxtype b = box() ? box() : Boxtype.downBox;
        int dx = fl.core.eventX() - x() - boxDx(b) + leftline_;
        int dy = fl.core.eventY() - y() - boxDy(b) + topline_;
        bool inText = fl.core.eventX() < x() + boxDx(b) + innerW()
            && fl.core.eventY() < y() + boxDy(b) + innerH();

        switch (event)
        {
        case Event.focus, Event.unfocus:
            if (textSelected()) redraw();
            return 1;
        case Event.enter:
            super.handle(event);
            return 1;
        case Event.leave:
            if (window() !is null) window().cursor(Cursor.default_);
            break;
        case Event.move:
        {
            int l = inText ? linkAt(dx, dy) : -1;
            if (window() !is null)
                window().cursor(l >= 0 ? Cursor.hand : Cursor.default_);
            linkTip(l >= 0 ? linkUrls_[l] : null);
            return 1;
        }
        case Event.mouseWheel:
            if (fl.core.eventDy()) topline(topline_ + fl.core.eventDy() * 3 * lineStep());
            if (fl.core.eventDx()) leftline(leftline_ + fl.core.eventDx() * 3 * lineStep());
            return 1;
        case Event.push:
            if (!inText) break;
            takeFocus();
            if (fl.core.eventButton() == rightMouse)
            {
                MenuItem[2] items;
                items[0] = MenuItem(copyMenuText);
                if (!textSelected()) items[0].deactivate();
                int sx, sy;
                fl.core.getMouse(sx, sy);
                if (fl.menu_popup.popup(&items[0], sx, sy) !is null) copy();
                return 1;
            }
            pressLink_ = linkAt(dx, dy);
            if (pressLink_ >= 0) return 1;
            size_t p = posAt(dx, dy);
            if (fl.core.eventClicks() > 0)
            {
                selectWordAt(p);
                selecting_ = false;
            }
            else
            {
                selAnchor_ = selFirst_ = selLast_ = p;
                selecting_ = true;
                if (window() !is null) window().cursor(Cursor.insert);
            }
            redraw();
            return 1;
        case Event.drag:
            if (pressLink_ >= 0)
            {
                if (fl.core.eventIsClick()) return 1;
                // Dragging off a link starts a selection.
                selAnchor_ = posAt(dx, dy);
                pressLink_ = -1;
                selecting_ = true;
            }
            if (selecting_)
            {
                // Scroll when dragging past the top or bottom.
                if (fl.core.eventY() < y()) topline(topline_ - lineStep());
                else if (fl.core.eventY() > y() + h()) topline(topline_ + lineStep());
                size_t p = posAt(dx, dy);
                selFirst_ = p < selAnchor_ ? p : selAnchor_;
                selLast_ = p < selAnchor_ ? selAnchor_ : p;
                redraw();
            }
            return 1;
        case Event.release:
            if (pressLink_ >= 0)
            {
                int l = pressLink_;
                pressLink_ = -1;
                if (fl.core.eventIsClick() && linkAt(dx, dy) == l)
                    followLink(linkUrls_[l]);
                return 1;
            }
            if (selecting_)
            {
                selecting_ = false;
                if (window() !is null) window().cursor(Cursor.default_);
                if (textSelected()) copy(0);
                return 1;
            }
            break;
        case Event.keyDown:
            // With Alt or Meta held, the arrow keys are left to shortcuts
            // (a browser's Alt+Left and Alt+Right for back and forward).
            if (fl.core.eventState() & (stateAlt | stateMeta))
                goto case Event.shortcut;
            switch (fl.core.eventKey())
            {
            case kUp: topline(topline_ - lineStep()); return 1;
            case kDown: topline(topline_ + lineStep()); return 1;
            case kLeft: leftline(leftline_ - lineStep()); return 1;
            case kRight: leftline(leftline_ + lineStep()); return 1;
            case kPageUp: topline(topline_ - innerH() + lineStep()); return 1;
            case kPageDown: topline(topline_ + innerH() - lineStep()); return 1;
            case kHome: topline(0); return 1;
            case kEnd: topline(size_); return 1;
            default: break;
            }
            goto case Event.shortcut;
        case Event.shortcut:
        {
            auto mods = fl.core.eventState() & (stateMeta | stateAlt | stateShift | stateCtrl);
            if (mods == stateCommand)
            {
                switch (fl.core.eventKey())
                {
                case 'a':
                    selectAll();
                    return 1;
                case 'c':
                    copy(1);
                    return 1;
                default:
                    break;
                }
            }
            break;
        }
        default:
            break;
        }
        return super.handle(event);
    }

    // ---- Following links ----

    private void followLink(string url)
    {
        import std.path : buildNormalizedPath, absolutePath, extension;
        import std.string : indexOf, startsWith, toLower;
        import std.uri : decodeComponent;

        if (linkFunc_ !is null && linkFunc_(this, url)) return;

        if (url.startsWith("#"))
        {
            topline(url[1 .. $]);
            return;
        }

        if (hasScheme(url) && !url.startsWith("file:"))
        {
            string msg;
            openUri(url, msg);
            return;
        }

        string path = url, anchor;
        auto hash = path.indexOf('#');
        if (hash >= 0)
        {
            anchor = path[hash + 1 .. $];
            path = path[0 .. hash];
        }
        if (path.startsWith("file://")) path = path[7 .. $];
        else if (path.startsWith("file:")) path = path[5 .. $];
        try path = decodeComponent(path);
        catch (Exception) {}
        path = resolve(path);

        auto ext = extension(path).toLower();
        if (ext == ".md" || ext == ".markdown")
        {
            clearSelection();
            setChanged();
            load(anchor.length ? path ~ "#" ~ anchor : path);
        }
        else
        {
            string msg;
            openUri("file://" ~ path, msg);
        }
    }

    // ---- Layout ----

    private int sbSize() const => scrollbarSize_ ? scrollbarSize_ : fl.core.scrollbarSize();

    private int innerW()
    {
        Boxtype b = box() ? box() : Boxtype.downBox;
        return w() - boxDw(b) - (scrollbar_ !is null && scrollbar_.visible() ? sbSize() : 0);
    }

    private int innerH()
    {
        Boxtype b = box() ? box() : Boxtype.downBox;
        return h() - boxDh(b) - (hscrollbar_ !is null && hscrollbar_.visible() ? sbSize() : 0);
    }

    private int lineStep() const => textsize_ + textsize_ / 2;

    // A block's first source line (`start`) or the line after its last,
    // and its pixel row on the page: the top or the bottom of the block.
    private struct LineMark
    {
        int line, y;
        bool start;
    }

    /// Whether a code block's info string (```` ```D ````) says it holds D:
    /// its first word is `d` or `dlang`, in any case.
    private static bool isDCode(string info)
    {
        import std.string : indexOf, strip, toLower;
        string lang = info.strip();
        auto sp = lang.indexOf(' ');
        if (sp >= 0) lang = lang[0 .. sp];
        lang = lang.toLower();
        return lang == "d" || lang == "dlang";
    }

    private void setDocument(string md)
    {
        freeImages();
        value_ = md;
        doc_ = md is null ? null : parseMarkdown(md);
        title_ = null;
        if (doc_ !is null)
            foreach (b; doc_.children)
                if (b.kind == MdBlockKind.heading)
                {
                    title_ = plainText(b.inlines);
                    break;
                }
        if (title_ is null && filename_.length)
        {
            import std.path : baseName;
            title_ = baseName(filename_);
        }
        selFirst_ = selLast_ = 0;
        relayout(true);
        leftline(0);
    }

    private void freeImages()
    {
        freeScaled();
        foreach (img; images_) img.release();
        images_ = null;
    }

    // The scaled copies are shared images too, each holding on to its
    // original in the pool: released here, so that an image file changed
    // on disk is read again the next time the document is loaded.
    private void freeScaled()
    {
        foreach (img; scaled_) img.release();
        scaled_ = null;
    }

    /// Lays the document out again if the width changed (or `force`),
    /// and sets up the scrollbars.
    private void relayout(bool force)
    {
        if (scrollbar_ is null) return; // during construction
        Boxtype b = box() ? box() : Boxtype.downBox;
        int ss = sbSize();
        // The width is that of the view without the vertical scrollbar,
        // whether it shows or not, so showing it doesn't reflow the text.
        int width_ = w() - boxDw(b) - ss;
        if (force || width_ != layoutWidth_)
        {
            layoutWidth_ = width_;
            layout(width_);
        }

        // Scrollbars.
        int fullW = w() - boxDw(b), fullH = h() - boxDh(b);
        bool needV = size_ > fullH;
        bool needH = hsize_ > fullW - (needV ? ss : 0);
        if (needH && !needV) needV = size_ > fullH - ss;
        int vx = x() + w() - boxDw(b) + boxDx(b) - ss;
        int hy = y() + h() - boxDh(b) + boxDy(b) - ss;
        if (needV)
        {
            scrollbar_.resize(vx, y() + boxDy(b), ss, fullH - (needH ? ss : 0));
            scrollbar_.show();
        }
        else
            scrollbar_.hide();
        if (needH)
        {
            hscrollbar_.resize(x() + boxDx(b), hy, fullW - (needV ? ss : 0), ss);
            hscrollbar_.show();
        }
        else
            hscrollbar_.hide();
        initSizes();

        topline(topline_);
        leftline(leftline_);
    }

    private Color linkcolor()
    {
        // GitHub's link blue, or a lighter blue on a dark background.
        ubyte r, g, bl;
        fl.core.getColor(color(), r, g, bl);
        bool dark = r * 3 + g * 6 + bl < 128 * 10;
        return dark ? rgbColor(0x58, 0xa6, 0xff) : rgbColor(0x09, 0x69, 0xda);
    }

    private Color mix(Color fg, float weight) { return colorAverage(fg, color(), weight); }

    private void layout(int width)
    {
        runs_ = null;
        fills_ = null;
        pics_ = null;
        linkUrls_ = null;
        anchors_ = null;
        lineMarks_ = null;
        plain_ = null;
        freeScaled();
        linkcolor_ = linkcolor();
        curColor_ = textcolor_;

        int margin = textsize_;
        hsize_ = width;
        int bottom = margin;
        if (doc_ !is null)
        {
            availRight_ = width - margin;
            bottom = layoutBlocks(doc_.children, margin, width - margin, margin, false, 0);
        }
        size_ = bottom + margin;
        import std.algorithm : sort;
        lineMarks_.sort!((a, b) => a.line != b.line ? a.line < b.line : a.y < b.y);
    }

    private int gapBefore(MdBlock b, bool tight)
    {
        final switch (b.kind)
        {
        case MdBlockKind.heading:
            return b.level <= 2 ? textsize_ * 3 / 2 : textsize_;
        case MdBlockKind.paragraph:
            return tight ? textsize_ / 4 : textsize_ * 3 / 4;
        case MdBlockKind.list:
            return tight ? textsize_ / 4 : textsize_ * 3 / 4;
        case MdBlockKind.codeBlock, MdBlockKind.quote, MdBlockKind.table, MdBlockKind.listItem:
            return textsize_ * 3 / 4;
        case MdBlockKind.rule:
            return textsize_;
        case MdBlockKind.document:
            return 0;
        }
    }

    private int gapAfter(MdBlock b, bool tight)
    {
        if (b.kind == MdBlockKind.heading) return textsize_ / 2;
        return gapBefore(b, tight);
    }

    /// Lays out `blocks` one under the other, from `y`, between `x0` and
    /// `x1`. Returns the bottom.
    private int layoutBlocks(MdBlock[] blocks, int x0, int x1, int y, bool tight, int listDepth)
    {
        int prevGap = -1;
        foreach (b; blocks)
        {
            int above = y; // the bottom of the block before
            if (prevGap >= 0)
            {
                int g = gapBefore(b, tight);
                y += g > prevGap ? g : prevGap;
                if (plain_.length && !tight) newline(2);
            }
            // A block's top, with some of the space above it, as a
            // heading's anchor has: scrolled there, it isn't flush with
            // the view's edge.
            int room = y - above < textsize_ / 2 ? y - above : textsize_ / 2;
            if (b.line >= 0) lineMarks_ ~= LineMark(b.line, y - room, true);
            y = layoutBlock(b, x0, x1, y, tight, listDepth);
            if (b.line >= 0) lineMarks_ ~= LineMark(b.line + b.lineCount, y, false);
            prevGap = gapAfter(b, tight);
        }
        return y;
    }

    /// Ends the copied text's line: makes sure it ends in `n` newlines.
    private void newline(int n)
    {
        int have;
        while (have < plain_.length && plain_[$ - 1 - have] == '\n') have++;
        foreach (i; have .. n) plain_ ~= '\n';
    }

    private int layoutBlock(MdBlock b, int x0, int x1, int y, bool tight, int listDepth)
    {
        import std.conv : to;

        Style st;
        st.size = textsize_;
        st.color = curColor_;

        final switch (b.kind)
        {
        case MdBlockKind.document:
            return layoutBlocks(b.children, x0, x1, y, false, listDepth);

        case MdBlockKind.paragraph:
            Piece[] pieces;
            flatten(b.inlines, st, pieces, x1 - x0);
            y = layoutLines(pieces, x0, x1, y, MdAlign.none);
            newline(1);
            return y;

        case MdBlockKind.heading:
            static immutable float[6] scale = [2.0f, 1.5f, 1.25f, 1.0f, 0.875f, 0.85f];
            st.size = cast(Fontsize)(textsize_ * scale[b.level - 1] + 0.5f);
            st.bold = true;
            if (b.level == 6) st.color = mix(curColor_, 0.65f);
            if (b.id.length && b.id !in anchors_) anchors_[b.id] = y - textsize_ / 2;
            Piece[] pieces;
            flatten(b.inlines, st, pieces, x1 - x0);
            y = layoutLines(pieces, x0, x1, y, MdAlign.none);
            newline(1);
            if (b.level <= 2)
            {
                y += textsize_ / 4;
                fills_ ~= Fill(x0, y, x1 - x0, 1, mix(curColor_, 0.2f));
                y += 1;
            }
            return y;

        case MdBlockKind.codeBlock:
            int pad = textsize_ * 2 / 3;
            Font f = courier;
            Fontsize fs = cast(Fontsize)(textsize_ * 0.9f + 0.5f);
            fl_font(f, fs);
            int lh = fl.draw.height(), d = fl.draw.descent();

            // D code is coloured as in Fluid's code editors (fl.d_syntax):
            // each line becomes one run per stretch of one style.
            string text = b.text.length && b.text[$ - 1] == '\n' ? b.text[0 .. $ - 1] : b.text;
            char[] style;
            StyleTableEntry[] styles;
            if (isDCode(b.info))
            {
                style = new char[text.length];
                styleParse(text, style);
                styles = styleTable(fs);
            }

            int widest;
            int top = y;
            int ly = y + pad;
            size_t ls = 0;
            while (true)
            {
                size_t le = ls;
                while (le < text.length && text[le] != '\n') le++;
                int lx = x0 + pad;
                size_t s = ls;
                while (s < le)
                {
                    // One stretch of text in one style (the whole line when
                    // it isn't D).
                    size_t e = style.length ? s + 1 : le;
                    while (e < le && style[e] == style[s]) e++;
                    Font rf = f;
                    Color rc = curColor_;
                    if (style.length && style[s] != stylePlain)
                    {
                        rf = styles[style[s] - 'A'].font;
                        rc = styles[style[s] - 'A'].color;
                    }
                    fl_font(rf, fs);
                    int rw = cast(int) width(text[s .. e]);
                    runs_ ~= Run(lx, ly + lh - d, rw, lh - d, d, rf, fs, rc, text[s .. e], plain_.length);
                    plain_ ~= text[s .. e];
                    lx += rw;
                    s = e;
                }
                if (lx - (x0 + pad) > widest) widest = lx - (x0 + pad);
                plain_ ~= '\n';
                ly += lh;
                if (le >= text.length) break;
                ls = le + 1;
            }
            int boxW = widest + 2 * pad;
            if (boxW < x1 - x0) boxW = x1 - x0;
            fills_ ~= Fill(x0, top, boxW, ly + pad - top, mix(curColor_, 0.06f));
            noteRight(x0 + boxW);
            return ly + pad;

        case MdBlockKind.quote:
            int bar = textsize_ / 4 > 3 ? textsize_ / 4 : 3;
            Color saved = curColor_;
            curColor_ = mix(curColor_, 0.65f);
            int top = y;
            y = layoutBlocks(b.children, x0 + bar + textsize_, x1, y, false, listDepth);
            curColor_ = saved;
            fills_ ~= Fill(x0, top, bar, y - top, mix(saved, 0.25f));
            return y;

        case MdBlockKind.list:
            int indent = textsize_ * 2;
            foreach (n, item; b.children)
            {
                if (n > 0)
                {
                    y += b.tight ? textsize_ / 4 : textsize_ * 3 / 4;
                    newline(b.tight ? 1 : 2);
                }
                // The marker, right-aligned in the indent, on the item's
                // first baseline.
                string marker;
                if (b.ordered) marker = to!string(b.start + n) ~ ".";
                else
                {
                    static immutable string[3] bullets = ["\u2022", "\u25E6", "\u25AA"];
                    marker = bullets[listDepth % 3];
                }
                Font mf = textfont_;
                fl_font(mf, textsize_);
                int asc = fl.draw.height() - fl.draw.descent();
                int mw = cast(int) width(marker);
                runs_ ~= Run(x0 + indent - textsize_ / 2 - mw, y + firstAscent(item), mw, asc,
                    fl.draw.descent(), mf, textsize_, curColor_, marker, plain_.length);
                plain_ ~= marker ~ " ";
                y = layoutBlocks(item.children, x0 + indent, x1, y, b.tight, listDepth + 1);
            }
            newline(1);
            return y;

        case MdBlockKind.listItem:
            return layoutBlocks(b.children, x0, x1, y, tight, listDepth);

        case MdBlockKind.table:
            return layoutTable(b, x0, x1, y);

        case MdBlockKind.rule:
            int t = textsize_ / 6 > 2 ? textsize_ / 6 : 2;
            fills_ ~= Fill(x0, y, x1 - x0, t, mix(curColor_, 0.2f));
            return y + t;
        }
    }

    /// The ascent of the first line of a list item, where its marker goes.
    private int firstAscent(MdBlock item)
    {
        fl_font(textfont_, textsize_);
        int asc = fl.draw.height() - fl.draw.descent();
        if (item.children.length && item.children[0].kind == MdBlockKind.heading)
        {
            static immutable float[6] scale = [2.0f, 1.5f, 1.25f, 1.0f, 0.875f, 0.85f];
            fl_font(textfont_ + fl.enumerations.bold,
                cast(Fontsize)(textsize_ * scale[item.children[0].level - 1] + 0.5f));
            asc = fl.draw.height() - fl.draw.descent();
        }
        return asc;
    }

    private void noteRight(int right)
    {
        int r = right + textsize_;
        if (r > hsize_) hsize_ = r;
    }

    private Font fontOf(ref const Style st)
    {
        if (st.code) return st.bold ? courierBold : courier;
        return textfont_ + (st.bold ? fl.enumerations.bold : 0) + (st.italic ? fl.enumerations.italic : 0);
    }

    private Fontsize sizeOf(ref const Style st)
    {
        return st.code ? cast(Fontsize)(st.size * 0.9f + 0.5f) : st.size;
    }

    /// Turns inlines into words, spaces, breaks and images.
    private void flatten(const(MdInline)[] inlines, Style st, ref Piece[] pieces, int avail)
    {
        foreach (ref i; inlines)
        {
            final switch (i.kind)
            {
            case MdInlineKind.text:
                addWords(i.text, st, pieces);
                break;
            case MdInlineKind.code:
                Style c = st;
                c.code = true;
                addWords(i.text, c, pieces);
                break;
            case MdInlineKind.emphasis:
                Style c = st;
                c.italic = true;
                flatten(i.children, c, pieces, avail);
                break;
            case MdInlineKind.strong:
                Style c = st;
                c.bold = true;
                flatten(i.children, c, pieces, avail);
                break;
            case MdInlineKind.strike:
                Style c = st;
                c.strike = true;
                flatten(i.children, c, pieces, avail);
                break;
            case MdInlineKind.link:
                Style c = st;
                c.link = cast(int) linkUrls_.length;
                c.color = linkcolor_;
                linkUrls_ ~= i.url;
                flatten(i.children, c, pieces, avail);
                break;
            case MdInlineKind.image:
                Image img = imageFor(i.url, avail);
                if (img is null)
                {
                    // No image: its description, in brackets.
                    Style c = st;
                    c.italic = true;
                    c.color = st.link >= 0 ? st.color : mix(curColor_, 0.6f);
                    addWords("[" ~ (i.text.length ? i.text : "image") ~ "]", c, pieces);
                }
                else
                {
                    Piece p;
                    p.kind = Piece.Kind.image;
                    p.img = img;
                    p.w = img.w();
                    p.h = img.h();
                    p.st = st;
                    p.text = i.text;
                    pieces ~= p;
                }
                break;
            case MdInlineKind.softBreak:
                Piece p;
                p.kind = Piece.Kind.space;
                p.st = st;
                pieces ~= p;
                break;
            case MdInlineKind.hardBreak:
                Piece p;
                p.kind = Piece.Kind.lineBreak;
                p.st = st;
                pieces ~= p;
                break;
            }
        }
    }

    private void addWords(string text, Style st, ref Piece[] pieces)
    {
        size_t i;
        while (i < text.length)
        {
            if (text[i] == ' ' || text[i] == '\n')
            {
                Piece p;
                p.kind = Piece.Kind.space;
                p.st = st;
                pieces ~= p;
                while (i < text.length && (text[i] == ' ' || text[i] == '\n')) i++;
            }
            else
            {
                size_t s = i;
                while (i < text.length && text[i] != ' ' && text[i] != '\n') i++;
                Piece p;
                p.kind = Piece.Kind.word;
                p.text = text[s .. i];
                p.st = st;
                pieces ~= p;
            }
        }
    }

    /**
     * Puts `pieces` on lines from `y`, wrapping at `x1`. Each line is
     * aligned between `x0` and `x1` as `al` says. Adds the runs and
     * images, and the text to `plain_` (a space where a line wraps).
     * Returns the bottom of the last line.
     */
    private int layoutLines(Piece[] pieces, int x0, int x1, int y, MdAlign al)
    {
        // Measure.
        foreach (ref p; pieces)
        {
            if (p.kind == Piece.Kind.word)
            {
                fl_font(fontOf(p.st), sizeOf(p.st));
                p.w = cast(int) width(p.text);
            }
            else if (p.kind == Piece.Kind.space)
            {
                fl_font(fontOf(p.st), sizeOf(p.st));
                p.w = cast(int) width(" ");
            }
        }

        size_t[] line;         // indices of the pieces on the current line
        int lx;                // width of the current line
        ptrdiff_t pendingSpace = -1;

        void emit(bool wrapped)
        {
            // Drop trailing spaces.
            while (line.length && pieces[line[$ - 1]].kind == Piece.Kind.space) line = line[0 .. $ - 1];
            int asc, desc, lw;
            fl_font(textfont_, textsize_);
            asc = fl.draw.height() - fl.draw.descent();
            desc = fl.draw.descent();
            foreach (k; line)
            {
                auto p = &pieces[k];
                lw += p.w;
                if (p.kind == Piece.Kind.image)
                {
                    if (p.h > asc) asc = p.h;
                }
                else
                {
                    fl_font(fontOf(p.st), sizeOf(p.st));
                    int a = fl.draw.height() - fl.draw.descent(), d = fl.draw.descent();
                    if (a > asc) asc = a;
                    if (d > desc) desc = d;
                }
            }
            int baseline = y + asc;
            int px = x0;
            if (al == MdAlign.right) px = x1 - lw;
            else if (al == MdAlign.center) px = x0 + (x1 - x0 - lw) / 2;

            size_t k = 0;
            while (k < line.length)
            {
                auto p = &pieces[line[k]];
                if (p.kind == Piece.Kind.image)
                {
                    pics_ ~= Pic(px, baseline - p.h, p.w, p.h, p.img, p.st.link);
                    px += p.w;
                    k++;
                    continue;
                }
                // Join pieces of the same style into one run.
                size_t e = k;
                string text;
                int rw;
                while (e < line.length)
                {
                    auto q = &pieces[line[e]];
                    if (q.kind == Piece.Kind.image || !sameStyle(q.st, p.st)) break;
                    text ~= q.kind == Piece.Kind.space ? " " : q.text;
                    rw += q.w;
                    e++;
                }
                fl_font(fontOf(p.st), sizeOf(p.st));
                int a = fl.draw.height() - fl.draw.descent(), d = fl.draw.descent();
                if (p.st.code)
                {
                    // A code span's background, around its text (not
                    // around a space next to it).
                    size_t cs = 0, ce = text.length;
                    int lead, trail;
                    while (cs < ce && text[cs] == ' ') { cs++; lead += cast(int) width(" "); }
                    while (ce > cs && text[ce - 1] == ' ') { ce--; trail += cast(int) width(" "); }
                    if (ce > cs)
                        fills_ ~= Fill(px + lead - 2, baseline - a, rw - lead - trail + 4, a + d,
                            mix(textcolor_, 0.08f));
                }
                runs_ ~= Run(px, baseline, rw, a, d, fontOf(p.st), sizeOf(p.st), p.st.color,
                    text, plain_.length, p.st.link, p.st.strike);
                plain_ ~= text;
                px += rw;
                k = e;
            }
            noteRight(px);
            plain_ ~= wrapped ? ' ' : '\n';
            y = baseline + desc;
            line = null;
            lx = 0;
            pendingSpace = -1;
        }

        foreach (i, ref p; pieces)
        {
            final switch (p.kind)
            {
            case Piece.Kind.lineBreak:
                emit(false);
                break;
            case Piece.Kind.space:
                if (line.length && pendingSpace < 0) pendingSpace = i;
                break;
            case Piece.Kind.word, Piece.Kind.image:
                int sw = pendingSpace >= 0 ? pieces[pendingSpace].w : 0;
                if (line.length && lx + sw + p.w > x1 - x0)
                    emit(true);
                else if (pendingSpace >= 0)
                {
                    line ~= pendingSpace;
                    lx += sw;
                }
                pendingSpace = -1;
                line ~= i;
                lx += p.w;
                break;
            }
        }
        if (line.length) emit(false);
        // emit() ends the text with a newline; the caller decides what
        // separates this text from the next.
        if (plain_.length && plain_[$ - 1] == '\n') plain_.length--;
        return y;
    }

    private static bool sameStyle(ref const Style a, ref const Style b)
    {
        return a.bold == b.bold && a.italic == b.italic && a.code == b.code && a.strike == b.strike
            && a.link == b.link && a.size == b.size && a.color == b.color;
    }

    private int layoutTable(MdBlock b, int x0, int x1, int y)
    {
        size_t cols = b.aligns.length;
        int pad = textsize_ / 2, vpad = textsize_ / 3;
        if (cols == 0) return y;

        // Each cell's pieces, and each column's narrowest and natural width.
        Piece[][][] cells;
        int[] minW = new int[cols], maxW = new int[cols];
        foreach (r, row; b.rows)
        {
            Piece[][] rc;
            foreach (c, cell; row)
            {
                Style st;
                st.size = textsize_;
                st.color = curColor_;
                st.bold = r == 0;
                Piece[] pieces;
                flatten(cell, st, pieces, x1 - x0);
                int lineW, widest;
                bool space;
                foreach (ref p; pieces)
                {
                    fl_font(fontOf(p.st), sizeOf(p.st));
                    if (p.kind == Piece.Kind.word) p.w = cast(int) width(p.text);
                    else if (p.kind == Piece.Kind.space) p.w = cast(int) width(" ");
                    if (p.kind == Piece.Kind.lineBreak) { lineW = 0; continue; }
                    lineW += p.w;
                    if (p.w > widest && p.kind != Piece.Kind.space) widest = p.w;
                    if (lineW > maxW[c]) maxW[c] = lineW;
                }
                if (widest > minW[c]) minW[c] = widest;
                rc ~= pieces;
            }
            cells ~= rc;
        }

        int avail = x1 - x0;
        int[] colW = new int[cols];
        int sumMin, sumMax;
        foreach (c; 0 .. cols)
        {
            sumMin += minW[c] + 2 * pad;
            sumMax += maxW[c] + 2 * pad;
        }
        foreach (c; 0 .. cols)
        {
            if (sumMax <= avail) colW[c] = maxW[c] + 2 * pad;
            else if (sumMin >= avail) colW[c] = minW[c] + 2 * pad;
            else
            {
                int extra = avail - sumMin;
                int spread = sumMax - sumMin;
                colW[c] = minW[c] + 2 * pad + cast(int)(cast(long) extra * (maxW[c] - minW[c]) / spread);
            }
        }

        Color border = mix(curColor_, 0.25f);
        foreach (r, rc; cells)
        {
            int top = y, bottom = y;
            int cx = x0;
            size_t firstRun = runs_.length;
            // Each row is a source line of its own; the header's is followed
            // by the delimiter row (|---|).
            if (r > 0 && b.line >= 0) lineMarks_ ~= LineMark(b.line + cast(int) r + 1, top, true);
            foreach (c, pieces; rc)
            {
                if (c > 0) plain_ ~= '\t';
                int cb = layoutLines(pieces, cx + pad, cx + colW[c] - pad, top + vpad, b.aligns[c]);
                if (cb > bottom) bottom = cb;
                cx += colW[c];
            }
            plain_ ~= '\n';
            int rowH = bottom + vpad - top;
            if (rowH < textsize_ + 2 * vpad) rowH = textsize_ + 2 * vpad;
            cx = x0;
            if (r == 0) fills_ ~= Fill(x0, top, sumOf(colW), rowH, mix(curColor_, 0.06f));
            else if (r % 2 == 0) fills_ ~= Fill(x0, top, sumOf(colW), rowH, mix(curColor_, 0.03f));
            foreach (c; 0 .. cols)
            {
                fills_ ~= Fill(cx, top, colW[c] + 1, rowH + 1, border, true);
                cx += colW[c];
            }
            y = top + rowH;
        }
        noteRight(x0 + sumOf(colW));
        newline(1);
        return y + 1;
    }

    private static int sumOf(int[] a)
    {
        int s;
        foreach (v; a) s += v;
        return s;
    }

    // ---- Images ----

    /// The image at `url`, scaled down to `avail` pixels wide if wider,
    /// or null if there is no such file (see the module comment).
    private Image imageFor(string url, int avail)
    {
        import std.conv : to;

        string path = imagePath(url);
        if (path is null) return null;
        SharedImage img;
        if (auto held = path in images_) img = *held;
        else
        {
            img = SharedImage.get(path);
            if (img is null || img.w() <= 0 || img.h() <= 0)
            {
                if (img !is null) img.release();
                return null;
            }
            images_[path] = img;
        }
        if (img.w() <= avail || avail <= 0) return img;
        string key = path ~ "@" ~ to!string(avail);
        if (auto s = key in scaled_) return *s;
        auto small = img.copy(avail, cast(int)(cast(long) img.h() * avail / img.w()));
        scaled_[key] = small;
        return small;
    }

    private string imagePath(string url)
    {
        import std.file : exists, isFile;
        import std.string : indexOf, startsWith;
        import std.array : split, join;
        import std.uri : decodeComponent;

        if (url.length == 0) return null;
        try url = decodeComponent(url);
        catch (Exception) {}
        if (url.startsWith("file://")) url = url[7 .. $];
        else if (url.startsWith("file:")) url = url[5 .. $];

        bool isFileAt(string p)
        {
            try return exists(p) && isFile(p);
            catch (Exception) return false;
        }

        if (hasScheme(url))
        {
            // A local copy: the URL's path, or its tail end, under the
            // document's folder.
            auto rest = url[url.indexOf("://") >= 0 ? url.indexOf("://") + 3 : url.indexOf(':') + 1 .. $];
            auto q = rest.indexOf('?');
            if (q >= 0) rest = rest[0 .. q];
            auto parts = rest.split("/");
            if (parts.length < 2) return null;
            parts = parts[1 .. $]; // drop the host
            foreach (k; 0 .. parts.length)
            {
                auto p = resolve(parts[k .. $].join("/"));
                if (isFileAt(p)) return p;
            }
            return null;
        }
        auto p = resolve(url);
        return isFileAt(p) ? p : null;
    }

    /// `path` made absolute against the document's folder.
    private string resolve(string path)
    {
        import std.path : absolutePath, buildNormalizedPath, isAbsolute;
        if (isAbsolute(path)) return buildNormalizedPath(path);
        return buildNormalizedPath(directory_.length ? absolutePath(path, directory_) : absolutePath(path));
    }

    private static bool hasScheme(string url)
    {
        import std.ascii : isAlpha, isAlphaNum;
        size_t i;
        while (i < url.length && (isAlphaNum(url[i]) || url[i] == '+' || url[i] == '-' || url[i] == '.')) i++;
        // A single letter before ':' is a Windows drive, not a scheme.
        return i >= 2 && i < url.length && url[i] == ':' && isAlpha(url[0]);
    }

    // ---- Hit testing ----

    /// Shows the address of the link under the mouse in a tooltip; away
    /// from links, the widget's own tooltip, if it has one.
    private void linkTip(string url)
    {
        static import fl.tooltip;
        if (url.length)
            fl.tooltip.enterArea(this, 0, fl.core.eventY() - y() - lineStep() / 2, w(), lineStep(), url);
        else
            fl.tooltip.enterArea(this, 0, 0, w(), h(), tooltip());
    }

    /// The link at document position (dx, dy), or -1.
    private int linkAt(int dx, int dy)
    {
        foreach (ref r; runs_)
            if (r.link >= 0 && dx >= r.x && dx < r.x + r.w && dy >= r.y - r.asc && dy < r.y + r.desc)
                return r.link;
        foreach (ref p; pics_)
            if (p.link >= 0 && dx >= p.x && dx < p.x + p.w && dy >= p.y && dy < p.y + p.h)
                return p.link;
        return -1;
    }

    /// The text position nearest document position (dx, dy).
    private size_t posAt(int dx, int dy)
    {
        if (runs_.length == 0) return 0;
        size_t best;
        long bestScore = long.max;
        foreach (k, ref r; runs_)
        {
            int top = r.y - r.asc, bottom = r.y + r.desc;
            long vd = dy < top ? top - dy : dy >= bottom ? dy - bottom + 1 : 0;
            long hd = dx < r.x ? r.x - dx : dx >= r.x + r.w ? dx - (r.x + r.w) + 1 : 0;
            long score = vd * 100_000 + hd;
            if (score < bestScore)
            {
                bestScore = score;
                best = k;
            }
        }
        auto r = &runs_[best];
        if (dx <= r.x) return r.pos;
        if (dx >= r.x + r.w) return r.pos + r.text.length;
        fl_font(r.font, r.size);
        import std.utf : stride;
        size_t i;
        while (i < r.text.length)
        {
            size_t n = i + stride(r.text, i);
            int left = cast(int) width(r.text[0 .. i]);
            int right = cast(int) width(r.text[0 .. n]);
            if (dx < r.x + (left + right) / 2) return r.pos + i;
            i = n;
        }
        return r.pos + r.text.length;
    }

    private void selectWordAt(size_t p)
    {
        bool wordChar(char c) { return c != ' ' && c != '\n' && c != '\t'; }
        size_t a = p, e = p;
        while (a > 0 && wordChar(plain_[a - 1])) a--;
        while (e < plain_.length && wordChar(plain_[e])) e++;
        selFirst_ = a;
        selLast_ = e;
        selAnchor_ = a;
    }

    private static char asciiLower(char c) { return c >= 'A' && c <= 'Z' ? cast(char)(c + 32) : c; }
}

unittest
{
    import std.algorithm : canFind;
    import std.file : write, remove, tempDir, mkdirRecurse, rmdirRecurse, exists;
    import std.path : buildPath;

    FlGroup.current(null);
    scope (exit) FlGroup.current(null);

    auto v = new MarkdownView(0, 0, 400, 300);
    v.value("# Title\n\nSome **bold** text and a [link](#second).\n\n## Second\n\n- one\n- two\n");
    assert(v.title() == "Title");
    assert(v.size() > 0);
    assert(v.directory() is null && v.filename() is null);

    // Text with a folder of its own: relative paths resolve from there. A
    // relative folder is taken from the current directory.
    import std.path : buildNormalizedPath;
    import std.file : getcwd;
    v.value("# Doc\n", tempDir());
    assert(v.directory() == buildNormalizedPath(tempDir()) && v.filename() is null);
    assert(v.resolve("pic.png") == buildPath(buildNormalizedPath(tempDir()), "pic.png"));
    v.value("![pic](pic.png)\n", ".");
    assert(v.directory() == getcwd());
    assert(v.resolve("pic.png") == buildPath(getcwd(), "pic.png"));
    v.value("# Title\n\nSome **bold** text and a [link](#second).\n\n## Second\n\n- one\n- two\n");
    assert(v.directory() is null);

    // The copied text: blocks separated by blank lines, list markers kept.
    v.selectAll();
    auto t = v.selection();
    assert(t.canFind("Title\n\nSome bold text and a link."), t);
    assert(t.canFind("\u2022 one\n\u2022 two"), t);

    // find() selects the match.
    auto at = v.find("BOLD");
    assert(at >= 0 && v.selection() == "bold");
    assert(v.find("nowhere") == -1);

    // load(): relative .md links and images resolve from the file's folder.
    auto dir = buildPath(tempDir(), "fldtk_markdown_view_test");
    if (exists(dir)) rmdirRecurse(dir);
    mkdirRecurse(buildPath(dir, "docs"));
    scope (exit) rmdirRecurse(dir);
    write(buildPath(dir, "README.md"), "# Read me\n\nSee [docs](docs/a.md#part).\n");
    write(buildPath(dir, "docs", "a.md"), "# A\n\n## Part\n");
    assert(v.load(buildPath(dir, "README.md")) == 0);
    assert(v.title() == "Read me");
    assert(v.directory() == dir);
    assert(v.resolve("docs/a.md") == buildPath(dir, "docs", "a.md"));
    assert(v.load(buildPath(dir, "missing.md")) == -1);
    assert(v.title() == "Can't show this page");

    // A URL's image is found under the document's folder by its tail.
    write(buildPath(dir, "docs", "pic.png"), "not really a png");
    v.load(buildPath(dir, "README.md"));
    assert(v.imagePath("https://raw.githubusercontent.com/u/p/main/docs/pic.png")
        == buildPath(dir, "docs", "pic.png"));
    assert(v.imagePath("https://example.com/none.png") is null);
    assert(v.imagePath("docs/pic.png") == buildPath(dir, "docs", "pic.png"));

    assert(MarkdownView.hasScheme("https://x"));
    assert(MarkdownView.hasScheme("mailto:a@b"));
    assert(!MarkdownView.hasScheme("C:/dir/file.md"));
    assert(!MarkdownView.hasScheme("docs/a.md"));
}

unittest
{
    // A code block marked as D is coloured by fl.d_syntax: one run per
    // stretch of one style. Another block is one run per line. Either way
    // the copied text is the code as written.
    import std.algorithm : canFind;
    FlGroup.current(null);
    scope (exit) FlGroup.current(null);

    auto v = new MarkdownView(0, 0, 400, 300);
    v.value("```D\nint x = 1; // one\n```\n");
    assert(v.runs_.length > 3, "D code should split into styled runs");
    assert(v.runs_.canFind!(r => r.text == "int" && r.font == courierBold));
    assert(v.runs_.canFind!(r => r.text == "// one"));
    v.selectAll();
    assert(v.selection() == "int x = 1; // one\n", v.selection());

    v.value("```\nint x = 1; // one\n```\n");
    assert(v.runs_.length == 1 && v.runs_[0].text == "int x = 1; // one");
    with (MarkdownView)
        assert(isDCode("dlang") && isDCode(" D title") && !isDCode("dart") && !isDCode(""));
}

unittest
{
    // scrollToSourceLine() puts what a source line shows at the top: a
    // heading's line scrolls to the heading, as its anchor does, and a
    // later line never scrolls to an earlier place.
    import std.array : appender;
    import std.conv : to;
    FlGroup.current(null);
    scope (exit) FlGroup.current(null);

    auto md = appender!string();
    foreach (k; 0 .. 40)
        md ~= "## Part " ~ k.to!string ~ "\n\nSome text for part " ~ k.to!string ~ ".\n\n";
    auto v = new MarkdownView(0, 0, 300, 200);
    v.value(md[]);

    // "## Part 20" is source line 80.
    v.topline("part-20");
    int byAnchor = v.topline();
    v.scrollToSourceLine(80);
    assert(v.topline() == byAnchor, v.topline().to!string ~ " vs " ~ byAnchor.to!string);

    int prev = -1;
    foreach (line; 0 .. 160)
    {
        v.scrollToSourceLine(line);
        assert(v.topline() >= prev);
        prev = v.topline();
    }
}

unittest
{
    // Each table row is a mark of its own: a row's line scrolls to that row,
    // however much the rows above it wrap.
    import std.array : appender;
    import std.conv : to;
    FlGroup.current(null);
    scope (exit) FlGroup.current(null);

    auto md = appender!string();
    md ~= "| A | B |\n|---|---|\n";
    foreach (k; 0 .. 60)
        md ~= "| row " ~ k.to!string ~ " | " ~ (k % 3 == 0 ? "a long cell that wraps over several lines in a narrow view" : "short") ~ " |\n";
    auto v = new MarkdownView(0, 0, 300, 200);
    v.value(md[]);
    // Row 40 is source line 42; its text's run sits just below the mark.
    v.scrollToSourceLine(42);
    int top = v.topline();
    bool found;
    foreach (ref r; v.runs_)
        if (r.text == "40")
        {
            found = true;
            assert(r.y - r.asc >= top && r.y - r.asc < top + 3 * v.textsize(),
                (r.y - r.asc).to!string ~ " vs " ~ top.to!string);
        }
    assert(found);
}

unittest
{
    // topSourceLine() undoes scrollToSourceLine() at the start of every
    // block (here every heading and paragraph) and every table row.
    import std.array : appender;
    import std.conv : to;
    FlGroup.current(null);
    scope (exit) FlGroup.current(null);

    auto md = appender!string();
    foreach (k; 0 .. 30)
        md ~= "## Part " ~ k.to!string ~ "\n\nSome text for part " ~ k.to!string ~ ".\n\n";
    md ~= "| A | B |\n|---|---|\n";
    foreach (k; 0 .. 30)
        md ~= "| " ~ k.to!string ~ " | " ~ (k % 3 == 0 ? "a long cell that wraps over several lines" : "short") ~ " |\n";
    auto v = new MarkdownView(0, 0, 300, 200);
    v.value(md[]);
    int[] starts;
    foreach (k; 0 .. 30) starts ~= [4 * k, 4 * k + 2];
    foreach (k; 0 .. 30) starts ~= 122 + k;
    foreach (line; starts)
    {
        v.scrollToSourceLine(line);
        if (v.topline() >= v.size() - v.h() + 4) break; // the end: can't scroll further
        assert(v.topSourceLine() == line, line.to!string ~ " -> " ~ v.topSourceLine().to!string);
    }
}

unittest
{
    // An image changed on disk shows when the document is loaded again,
    // also when the view shows it scaled down.
    import fl.shared_image : SharedImage;
    import std.file : write, remove, tempDir;
    import std.path : buildPath;
    FlGroup.current(null);
    scope (exit) FlGroup.current(null);

    auto pic = buildPath(tempDir(), "fldtk-markdown-view-reload.ppm");
    auto page = buildPath(tempDir(), "fldtk-markdown-view-reload.md");
    void writePic(int w) { write(pic, "P3\n" ~ (w == 600 ? "600" : "500") ~ " 1\n255\n" ~ repeatPixel(w)); }
    writePic(600);
    write(page, "# Page\n\n![a picture](fldtk-markdown-view-reload.ppm)\n");
    scope (exit) { remove(pic); remove(page); }

    int originalWidth()
    {
        foreach (im; SharedImage.images())
            if (im.name() == pic && im.original()) return im.dataW();
        return 0;
    }

    auto v = new MarkdownView(0, 0, 300, 200);  // narrower: drawn scaled down
    v.load(page);
    assert(originalWidth() == 600);
    writePic(500);
    v.load(page);
    assert(originalWidth() == 500);
    v.value("# No pictures\n");
    assert(originalWidth() == 0);               // nothing left in the pool
}

version (unittest) private string repeatPixel(int w)
{
    import std.array : replicate;
    return replicate("0 0 0 ", w) ~ "\n";
}
